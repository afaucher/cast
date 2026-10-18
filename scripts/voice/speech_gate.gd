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
## REPEAT GUARD (repeat_guard, on for the live mic): real mic audio never repeats bit for bit, but
## a stalled input device replaying an old buffer does (playtest 2026-10-17). Loud frames already
## seen in the last REPEAT_MEMORY are never voice and never reach the recognizer; a run of them sets
## is_stale, which VoiceCaster answers by restarting the device.
##
## FLUSH ON VOICE END (flush_on_end, docs/design/stt-latency-staggered-streams.md). The streaming
## model decodes in 320 ms chunks and only commits a word after hearing ~0.35-0.6 s of audio past
## it, so waiting for real audio put ~0.6 s between the end of the voice and the cast. Instead, once
## the raw (undelayed) input has been quiet for flush_quiet_sec after a voice run, the gate hands out
## its delay line at once plus flush_pad_sec of comfort noise (the recognizer finishes the word and
## the endpoint immediately), then owes that much audio: later output is dropped while the input
## stays quiet. The first loud frame cancels the debt; its onset is safe in the delay line, the
## recognizer just hears a longer pause. The END uses a softer rule than voice (flush_soft_db below
## the voice level, at least FLUSH_FLOOR_RATIO x the floor) so quiet endings ("th", "s") are kept.
## Replayed (repeat-guard) frames never count as voice, and the drained delay line follows the
## same pass/cut rule as normal output, so a stale-mic replay is never flushed through.
## voice_end_sample marks where the last voice ended (raw samples), for the true latency metric.
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
const REPEAT_MEMORY := 1000       ## frames (10 s) of loud-frame fingerprints remembered
const STALE_SCORE := 20.0         ## repeat score that means the input is replaying old audio
const STALE_DECAY := 0.05         ## score lost per frame: 0.2 s of replayed words sets stale, word gaps don't clear it
const STALE_MAX := 40.0           ## score cap: stale clears ~8 s after the repeats stop
const FLUSH_QUIET_SEC := 0.1      ## quiet after a voice run that counts as the end of voice
const FLUSH_SOFT_DB := 6.0        ## end rule: a frame this far below the voice rule still counts as voice
const FLUSH_FLOOR_RATIO := 3.0    ## ... and must be at least this far above the floor (~4.8 dB)
const FLUSH_PAD_SEC := 1.4        ## comfort noise pushed at the end (covers the model's delay + endpoint)

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
var repeat_guard := false         ## drop loud frames heard before (see REPEAT GUARD)
var is_stale := false             ## the input is replaying old audio
var repeated_frames := 0          ## loud frames dropped as repeats (stats)
var flush_on_end := true          ## see FLUSH ON VOICE END
var flush_quiet_sec := FLUSH_QUIET_SEC
var flush_soft_db := FLUSH_SOFT_DB
var flush_pad_sec := FLUSH_PAD_SEC
var flushes := 0                  ## voice ends flushed (stats)
var samples_in := 0               ## raw samples received while enabled (since the start)
var voice_end_sample := -1        ## raw sample position where the most recent voice ended (-1 = none yet)
var voice_start_sample := -1      ## raw sample position where the most recent voice span began (-1 = none yet; the voice onset)

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
var _seen := {}                   ## fingerprint -> times in _seen_order
var _seen_order := PackedInt64Array()
var _seen_pos := 0
var _repeat_score := 0.0
var _frame_end := 0               ## raw sample position just after the last framed sample
var _span := false                ## inside a voice span (raw input, for the end of voice)
var _span_quiet := 0              ## frames since the span last had voice (soft rule)
var _debt := 0                    ## output samples still owed after a flush (dropped while quiet)
var _pad := PackedFloat32Array()  ## cached comfort noise for flushes (rebuilt on rate/length change)


## Feed mono samples; returns the cleaned audio, delayed by LOOKAHEAD. Same length on average, but
## with flush_on_end a voice end returns extra padding at once and later calls return less.
func process(samples: PackedFloat32Array, rate: int) -> PackedFloat32Array:
	if not enabled:
		_update_level(samples)
		return samples
	if rate != _rate:
		_rate = rate
		_frame_len = maxi(1, int(rate * FRAME_SEC))
		reset()
	samples_in += samples.size()
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
	_frame_end = samples_in           # the dropped partial frame was counted in samples_in
	_span = false
	_span_quiet = 0
	_debt = 0
	voice_end_sample = -1
	voice_start_sample = -1
	_acc = PackedFloat32Array()
	_delay.clear()
	_run = 0
	_hold = 0
	is_stale = false
	_repeat_score = 0.0
	_seen.clear()
	_seen_order = PackedInt64Array()
	_seen_pos = 0


## Human-readable state for the debug panel.
func describe() -> String:
	if not enabled:
		return "gate off"
	var s := "gate %s · floor %d dB · min voice %d dB · last voice peak %s · blips ignored %d" % [
		"STALE (replayed audio)" if is_stale else ("OPEN" if is_open else "closed"), roundi(db(noise_floor)),
		roundi(min_voice_db), "-" if last_peak_db <= -99.0 else "%d dB" % roundi(last_peak_db), rejected_bursts]
	if repeated_frames > 0:
		s += " · repeats dropped %d" % repeated_frames
	if flush_on_end:
		s += " · end flushes %d (quiet %d ms, pad %.1f s)" % [flushes, roundi(flush_quiet_sec * 1000.0), flush_pad_sec]
	return s


## Mean-square energy -> dBFS.
static func db(ms: float) -> float:
	return 10.0 * log(maxf(ms, FLOOR_MIN)) / log(10.0)


## The level meters' scale (debug panel graph, voice setup meter): -70 dBFS at 0, -10 dBFS at 1.
const METER_MIN_DB := -70.0
const METER_MAX_DB := -10.0


static func db_to_unit(v: float) -> float:
	return clampf((v - METER_MIN_DB) / (METER_MAX_DB - METER_MIN_DB), 0.0, 1.0)


func _frame(frame: PackedFloat32Array) -> PackedFloat32Array:
	var e := 0.0
	for s in frame:
		e += s * s
	var ms := e / frame.size()
	level = minf(1.0, sqrt(ms) * 8.0)
	level_db = db(ms)
	var loud := ms > maxf(noise_floor * LOUD_RATIO, pow(10.0, min_voice_db / 10.0))
	var repeated := false
	if repeat_guard:
		_repeat_score = maxf(0.0, _repeat_score - STALE_DECAY)
		if loud and _remember(hash(frame)):
			loud = false
			repeated = true
			repeated_frames += 1
			_repeat_score = minf(STALE_MAX, _repeat_score + 1.0)
			_cut()                # a replay is cut off mid-word
		is_stale = _repeat_score >= STALE_SCORE or (is_stale and _repeat_score > 0.0)
		if is_stale:
			_cut()
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

	_frame_end += frame.size()
	var flush := _track_end(ms, loud, repeated)

	# Delay line: the frame leaving now was recorded LOOKAHEAD ago.
	_delay.append(frame)
	var out: PackedFloat32Array
	if _delay.size() <= lookahead:
		out = _comfort(frame.size())
	else:
		out = _emit(_delay.pop_front())
	if _debt > 0:
		if loud:
			_debt = 0             # voice is back: keep the inserted pause, stop dropping
		else:
			var drop := mini(_debt, out.size())
			_debt -= drop
			out = out.slice(drop)
	if flush:
		out.append_array(_flush_block())
	return out


## One delayed frame out: passed (with comfort noise) during the hangover, comfort noise otherwise.
func _emit(outgoing: PackedFloat32Array) -> PackedFloat32Array:
	if _hold > 0:
		_hold -= 1
		if _hold == 0:
			is_open = false
			last_peak_db = db(_peak)
			_peak = 0.0
		return _dither(outgoing)
	return _comfort(outgoing.size())


## End-of-voice tracking on the raw input; true when this frame ends a voice span (flush now).
func _track_end(ms: float, loud: bool, repeated: bool) -> bool:
	if _run >= MIN_RUN and not _span:
		voice_start_sample = _frame_end - _run * _frame_len   # (the first frame of the run that opened this span)
	if _run >= MIN_RUN:
		_span = true
	if not _span:
		return false
	if is_stale:
		_span = false             # a replay is cut, never flushed through
		return false
	var soft_level := maxf(noise_floor * FLUSH_FLOOR_RATIO, pow(10.0, (min_voice_db - flush_soft_db) / 10.0))
	if loud or (ms > soft_level and not repeated):
		_span_quiet = 0
		voice_end_sample = _frame_end
		return false
	_span_quiet += 1
	if float(_span_quiet) * FRAME_SEC < flush_quiet_sec - 0.0001:
		return false
	_span = false
	return flush_on_end


## The delay line at once (same pass/cut rule as normal output), then flush_pad_sec of comfort
## noise; both are owed back by dropping later output while the input stays quiet.
func _flush_block() -> PackedFloat32Array:
	var block := PackedFloat32Array()
	for f in _delay:
		block.append_array(_emit(f))
	_delay.clear()
	var n := int(flush_pad_sec * _rate)
	if _pad.size() != n:
		_pad = _comfort(n)
	block.append_array(_pad)
	_debt += block.size()
	flushes += 1
	return block


func _cut() -> void:
	_run = 0
	if _hold > 0:
		_hold = 0
		is_open = false
		last_peak_db = db(_peak)
		_peak = 0.0


## Records a loud frame's fingerprint; true if it was already seen in the last REPEAT_MEMORY.
func _remember(h: int) -> bool:
	var again := _seen.has(h)
	if _seen_order.size() < REPEAT_MEMORY:
		_seen_order.append(h)
	else:
		var old := _seen_order[_seen_pos]
		var c: int = int(_seen.get(old, 1)) - 1
		if c <= 0:
			_seen.erase(old)
		else:
			_seen[old] = c
		_seen_order[_seen_pos] = h
		_seen_pos = (_seen_pos + 1) % REPEAT_MEMORY
	_seen[h] = int(_seen.get(h, 0)) + 1
	return again


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
