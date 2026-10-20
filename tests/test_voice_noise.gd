extends TestCase
## Real model + SpeechGate: an idle room with hiss and keyboard typing must not
## produce recognized text ("AND", "HE"...), while "cast heal" spoken over the
## same noise still casts. With the gate off the same noise is fed straight to
## the model, and the hallucination count is printed for comparison.
## Skips (passes) when the model/extension or the TTS clips are unavailable.

const RATE := 16000
const STEP := 320
const SPEED := 4.0
const CLIP := "clean_cast_heal_a0.wav"

var caster: VoiceCaster
var _heard: Array[String] = []
var _casts: Array[String] = []


func _init() -> void:
	timeout_sec = 200.0


func setup() -> void:
	if not ClassDB.class_exists("WordListener"):
		print("SKIP test_voice_noise: WordListener extension not loaded")
		finish()
		return
	var clip_path := ProjectSettings.globalize_path("res://tests/voice_clips").path_join(CLIP)
	var wav_lib: GDScript = load("res://tests/test_voice_audio.gd")
	var speech: PackedFloat32Array = wav_lib.call("_load_wav16", clip_path) if FileAccess.file_exists(clip_path) else PackedFloat32Array()
	if speech.is_empty():
		print("SKIP test_voice_noise: %s missing (run tools/make_voice_clips.ps1)" % CLIP)
		finish()
		return
	caster = VoiceCaster.new()
	caster.use_mic = false
	caster.use_saved_settings = false
	caster.persist_settings = false
	caster.voice_log.enabled = false
	add_child(caster)
	if not caster.start(VoiceCaster.default_spells()):
		print("SKIP test_voice_noise: model failed to load (%s)" % caster.status)
		finish()
		return
	caster.heard.connect(func(text: String, final: bool) -> void:
		if final and text.strip_edges() != "":
			_heard.append(text))
	caster.spell_spoken.connect(func(id: String, _p: float, _h: String) -> void: _casts.append(id))

	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var idle := _hiss(1.5, 0.004, rng)
	idle.append_array(_typing(6.0, 9.0, rng))
	idle.append_array(_hiss(1.5, 0.004, rng))

	# Gate off: what the model makes of the noise (informational).
	caster.gate.enabled = false
	_feed(idle)
	var ungated := _heard.size()
	print("gate OFF: %d phantom utterances from idle noise: %s" % [ungated, str(_heard)])

	# Gate on: nothing at all.
	caster.gate.enabled = true
	caster.reset()
	_heard.clear()
	_casts.clear()
	_feed(idle)
	print("gate ON: %d utterances (%s); %s" % [_heard.size(), str(_heard), caster.gate.describe()])
	eq(_heard.size(), 0, "idle typing + hiss produce no recognized text through the gate")
	eq(_casts.size(), 0, "and no casts")

	# A noise-suppressed mic in a quiet room sends exact zeros. Fed straight to the
	# model that produces phantom "HE"/"AND"; through the gate (comfort noise) nothing.
	var zeros := PackedFloat32Array()
	zeros.resize(8 * RATE)
	zeros.fill(0.0)
	caster.gate.enabled = false
	caster.reset()
	_heard.clear()
	_feed(zeros)
	print("digital silence, gate OFF: %d phantoms %s" % [_heard.size(), str(_heard)])
	caster.gate.enabled = true
	caster.reset()
	_heard.clear()
	_feed(zeros)
	print("digital silence, gate ON: %d %s" % [_heard.size(), str(_heard)])
	eq(_heard.size(), 0, "digital silence produces no phantom words through the gate")

	# Speech over the same noise still gets through and casts.
	caster.reset()
	_heard.clear()
	var mixed := _hiss(1.0, 0.004, rng)
	var noisy := _typing(speech.size() / float(RATE) + 1.0, 6.0, rng)
	for i in speech.size():
		noisy[i + int(0.5 * RATE)] += speech[i]
	mixed.append_array(noisy)
	mixed.append_array(_hiss(1.0, 0.004, rng))
	_feed(mixed)
	print("speech over noise heard: %s, casts: %s" % [str(_heard), str(_casts)])
	check(_casts.has("heal"), "cast heal over typing noise still casts")
	finish()


func _feed(stream: PackedFloat32Array) -> void:
	var start := Time.get_ticks_usec()
	var pos := 0
	while pos < stream.size():
		caster.push_samples(stream.slice(pos, pos + STEP), RATE)
		pos += STEP
		caster.poll()
		var wait := start + int(float(pos) * 1000000.0 / RATE / SPEED) - Time.get_ticks_usec()
		if wait > 0:
			OS.delay_usec(wait)
	caster.flush()
	for i in 25:
		OS.delay_msec(20)
		caster.poll()


func _hiss(sec: float, amp: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(sec * RATE))
	for i in a.size():
		a[i] = rng.randf_range(-amp, amp)
	return a


func _typing(sec: float, keys_per_sec: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var a := _hiss(sec, 0.004, rng)
	var t := 0.05
	while t < sec - 0.05:
		var start := int(t * RATE)
		for i in int(0.03 * RATE):
			a[start + i] += rng.randf_range(-0.3, 0.3) * exp(-float(i) / (0.006 * RATE))
		t += rng.randf_range(0.6, 1.4) / keys_per_sec
	return a
