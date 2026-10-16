class_name SpeechGate
extends RefCounted
## Cleans mic audio before the recognizer. Two failure modes were measured with
## the streaming model (tests/test_voice_noise.gd):
##  1. Exact digital silence (mics with noise suppression send zeros in a quiet
##     room) makes it invent "HE" / "AND" every ~0.6 s.
##  2. Any speech-like sound is transcribed: a TV, voice chat on speakers,
##     someone across the room.
## Mechanical noise (typing, fans, hum) produced no words in any test.
##
## So the gate keeps the stream CONTINUOUS (the model needs lead-in and trailing
## quiet around words: dropping audio clipped "heal" to "EL") and:
##  - adds a faint comfort-noise floor to everything (fixes 1);
##  - replaces audio with that comfort noise unless voice-level sound is near:
##    a frame counts as voice when it is above min_voice_db AND well above the
##    learned noise floor, in a run of at least MIN_RUN frames (so key clicks
##    don't count). Audio is passed from LOOKAHEAD before a voice run (the
##    output is delayed by LOOKAHEAD so quiet onsets like the "h" of heal
##    survive) until HANGOVER after it (fixes 2 when min_voice_db sits between
##    the player's voice and the background).
##
## min_voice_db is the knob: the debug panel shows the floor, the threshold and
## the peak of the last voice so the player can set it.

const FRAME_SEC := 0.01
const LOUD_RATIO := 6.0           ## voice frames must be this far above the floor (~7.8 dB)
const DEFAULT_MIN_VOICE_DB := -42.0
const MIN_RUN := 5                ## frames (50 ms) of sustained sound to count as voice; clicks are shorter
const LOOKAHEAD_SEC := 0.08       ## output delay; audio this long before a voice run is kept
const HANGOVER_SEC := 0.5         ## audio kept after the last voice frame
const COMFORT_RMS := 0.0003       ## ~-70 dBFS white noise floor added to everything
const FLOOR_MIN := 1e-8
const FLOOR_BLOCK := 10           ## frames per floor block (100 ms)
const FLOOR_SPAN := 30            ## blocks remembered (3 s): floor = quietest block

var enabled := true
var comfort_rms := COMFORT_RMS    ## comfort-noise level (tests/probes may vary it)
## Frames quieter than this (dBFS RMS) never count as voice. Raise it to ignore
## distant speech (TV, speakers); lower it for a quiet mic.
var min_voice_db := DEFAULT_MIN_VOICE_DB
var is_open := false              ## voice is (or was within HANGOVER) present
var noise_floor := 1e-6           ## mean-square energy
var level := 0.0                  ## 0..1 meter value, like WordListener.get_level()
var level_db := -100.0            ## latest 10 ms frame, dBFS
var last_peak_db := -100.0        ## loudest frame of the most recent voice span
var opens := 0                    ## voice spans seen (stats)
var rejected_bursts := 0          ## short loud blips that did not count as voice (clicks)

var _rate := 0
var _frame_len := 0
var _acc := PackedFloat32Array()  ## partial frame carried between calls
var _delay: Array[PackedFloat32Array] = []   ## frames waiting LOOKAHEAD before output
var _run := 0                     ## current run of loud frames
var _hold := 0                    ## frames of audio still to pass (hangover countdown)
var _peak := 0.0
var _rng := RandomNumberGenerator.new()
var _blocks := PackedFloat32Array()
var _block_sum := 0.0
var _block_n := 0


## Feed mono samples; returns the cleaned audio (same length, delayed by LOOKAHEAD).
func process(samples: PackedFloat32Array, rate: int) -> PackedFloat32Array:
	if not enabled:
		_update_level(samples)
		return samples
	if rate != _rate:
		_rate = rate
		_frame_len = maxi(1, int(rate * FRAME_SEC))
		reset()
	var out := PackedFloat32Array()
	_acc.append_array(samples)
	var pos := 0
	while _acc.size() - pos >= _frame_len:
		out.append_array(_frame(_acc.slice(pos, pos + _frame_len)))
		pos += _frame_len
	_acc = _acc.slice(pos)
	return out


## Stereo mic frames -> mono, then process().
func process_frames(frames: PackedVector2Array, rate: int) -> PackedFloat32Array:
	var mono := PackedFloat32Array()
	mono.resize(frames.size())
	for i in frames.size():
		var f := frames[i]
		mono[i] = (f.x + f.y) * 0.5
	return process(mono, rate)


func reset() -> void:
	is_open = false
	_acc = PackedFloat32Array()
	_delay.clear()
	_run = 0
	_hold = 0


## Human-readable state for the debug panel.
func describe() -> String:
	if not enabled:
		return "gate off"
	return "gate %s · floor %d dB · min voice %d dB · last voice peak %s · blips ignored %d" % [
		"OPEN" if is_open else "closed", roundi(db(noise_floor)), roundi(min_voice_db),
		"-" if last_peak_db <= -99.0 else "%d dB" % roundi(last_peak_db), rejected_bursts]


## Mean-square energy -> dBFS.
static func db(ms: float) -> float:
	return 10.0 * log(maxf(ms, FLOOR_MIN)) / log(10.0)


func _frame(frame: PackedFloat32Array) -> PackedFloat32Array:
	var e := 0.0
	for s in frame:
		e += s * s
	var ms := e / frame.size()
	level = minf(1.0, sqrt(ms) * 8.0)
	level_db = db(ms)
	var loud := ms > maxf(noise_floor * LOUD_RATIO, pow(10.0, min_voice_db / 10.0))
	_track_floor(ms)

	var lookahead := maxi(1, int(round(LOOKAHEAD_SEC / FRAME_SEC)))
	var hangover := int(round(HANGOVER_SEC / FRAME_SEC))
	if loud:
		_run += 1
		_peak = maxf(_peak, ms)
		if _run == MIN_RUN and not is_open:
			opens += 1
			is_open = true
		if _run >= MIN_RUN:
			# Keep the delayed audio from LOOKAHEAD before this run until HANGOVER after it.
			_hold = hangover + lookahead + MIN_RUN
	else:
		if _run > 0 and _run < MIN_RUN:
			rejected_bursts += 1
		_run = 0

	# Delay line: the frame leaving now was recorded LOOKAHEAD ago.
	_delay.append(frame)
	if _delay.size() <= lookahead:
		return _comfort(frame.size())
	var outgoing: PackedFloat32Array = _delay.pop_front()
	if _hold > 0:
		_hold -= 1
		if _hold == 0:
			is_open = false
			last_peak_db = db(_peak)
			_peak = 0.0
		return _dither(outgoing)
	return _comfort(outgoing.size())


## Minimum statistics: the floor is the quietest 100 ms block in the last 3 s.
## Speech always has quieter gaps, so it never becomes the floor; steady noise
## (fans, hum, hiss) does within a few seconds.
func _track_floor(ms: float) -> void:
	_block_sum += ms
	_block_n += 1
	if _block_n < FLOOR_BLOCK:
		return
	_blocks.append(_block_sum / _block_n)
	_block_sum = 0.0
	_block_n = 0
	if _blocks.size() > FLOOR_SPAN:
		_blocks = _blocks.slice(_blocks.size() - FLOOR_SPAN)
	var lo := INF
	for b in _blocks:
		lo = minf(lo, b)
	noise_floor = maxf(lo, FLOOR_MIN)


func _dither(a: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate()
	var amp := comfort_rms * 1.732   # uniform noise with RMS = comfort_rms
	for i in out.size():
		out[i] += _rng.randf_range(-amp, amp)
	return out


func _comfort(n: int) -> PackedFloat32Array:
	var z := PackedFloat32Array()
	z.resize(n)
	var amp := comfort_rms * 1.732
	for i in n:
		z[i] = _rng.randf_range(-amp, amp)
	return z


func _update_level(samples: PackedFloat32Array) -> void:
	if samples.is_empty():
		return
	var e := 0.0
	for s in samples:
		e += s * s
	level = minf(1.0, sqrt(e / samples.size()) * 8.0)
	level_db = db(e / samples.size())
