extends SceneTree
## Mic-leak probe for the audio plan (docs/design/audio-plan.md, "Mic safety"): plays each prototype cue into the real
## recognizer as if it leaked from speakers into the mic, and checks that
##   A. a cue on its own produces no words and no casts (gate on and off), and
##   B. the "cast heard" chime, overlapping the spell word, does not break a real "cast <spell>".
##   C. a "cast <spell>" said over a teammate's loud cue starting with the voice still casts.
##   Godot --path . --headless --script res://tools/sfx_proto/mic_leak_probe.gd [-- <recipe> ...]
## With no recipes it probes every one the game renders (render_game_sfx.gd GAME_CUES). A runs them, B runs the
## cast_armed* ones among them and C the others.
## Needs the model and the TTS clips (tests/voice_clips). Not part of the test suite.
const Synth = preload("res://tools/sfx_proto/sfx_round3.gd")   # it extends sfx_synth.gd
const Render = preload("res://tools/sfx_proto/render_game_sfx.gd")
const RATE := 16000
const STEP := 320

var caster: VoiceCaster
var _heard: Array[String] = []
var _casts: Array[String] = []
var _done := false
var _rng := RandomNumberGenerator.new()


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _run() -> void:
	caster = VoiceCaster.new()
	caster.use_mic = false
	caster.use_saved_settings = false
	caster.persist_settings = false
	caster.voice_log.enabled = false
	root.add_child(caster)
	if not caster.start(PackedStringArray(SpellBook.ids())):
		print("probe: model failed to load (%s)" % caster.status)
		return
	caster.heard.connect(func(text: String, final: bool) -> void:
		if final and text.strip_edges() != "":
			_heard.append(text))
	caster.spell_spoken.connect(func(id: String, _p: float, _h: String) -> void: _casts.append(id))
	_rng.seed = 11
	var synth := Synth.new()

	var args := OS.get_cmdline_user_args()
	var cues: Array = Render.GAME_CUES.values() if args.is_empty() else Array(args)
	var armed: Array = cues.filter(func(c: String) -> bool: return c.begins_with("cast_armed"))
	var others: Array = cues.filter(func(c: String) -> bool: return not c.begins_with("cast_armed"))
	var offsets := [0.25, 0.4] if args.is_empty() else [0.15, 0.3]

	print("A. each cue alone (peak 0.5 = a loud speaker leak), 3 plays in a row")
	for cue: String in cues:
		var s := _resample(synth.make(cue), 0.5)
		var stream := _hiss(0.8)
		for k in 3:
			stream.append_array(s)
			stream.append_array(_hiss(0.35))
		stream.append_array(_hiss(1.0))
		var res := []
		for gate_on in [false, true]:
			caster.gate.enabled = gate_on
			caster.reset()
			_heard.clear()
			_casts.clear()
			_feed(stream)
			res.append("gate %s: heard %s casts %s" % ["on " if gate_on else "off", str(_heard), str(_casts)])
		print("  %-18s %s | %s" % [cue, res[0], res[1]])

	print("B. 'cast <spell>' with the armed chime overlapping the spell word (gate on)")
	caster.gate.enabled = true
	var wav_lib: GDScript = load("res://tests/test_voice_audio.gd")
	var clips := ProjectSettings.globalize_path("res://tests/voice_clips")
	for spell: String in ["heal", "fireball", "armor", "corn", "coffee"]:
		for voice in ["a0", "b0"]:
			var speech: PackedFloat32Array = wav_lib.call("_load_wav16", clips.path_join("clean_cast_%s_%s.wav" % [spell, voice]))
			if speech.is_empty():
				continue
			var onset := _onset(speech)
			var line := "  %-9s %s:" % [spell, voice]
			for cue: String in [""] + armed:
				for level in ([0.0] if cue == "" else [0.15, 0.4]):
					for at in ([0.0] if cue == "" else offsets):
						var mix := _hiss(0.6)
						var body := speech.duplicate()
						body.append_array(_hiss(0.2))
						if cue != "":
							var chime := _resample(synth.make(cue), level)
							var i0 := onset + int(at * RATE)
							for i in chime.size():
								if i0 + i < body.size():
									body[i0 + i] += chime[i]
						mix.append_array(body)
						mix.append_array(_hiss(1.0))
						caster.reset()
						_heard.clear()
						_casts.clear()
						_feed(mix)
						var tag := "clean" if cue == "" else "%s@%.2f+%.2fs" % [cue.trim_prefix("cast_armed_"), level, at]
						line += "  %s=%s" % [tag, ",".join(_casts) if not _casts.is_empty() else "MISS(" + " / ".join(_heard) + ")"]
			print(line)

	print("C. 'cast <spell>' said over a teammate's loudest speech-like cues (peak 0.4, starting with the voice)")
	for spell: String in ["heal", "fireball", "corn"]:
		var speech: PackedFloat32Array = wav_lib.call("_load_wav16", clips.path_join("clean_cast_%s_a0.wav" % spell))
		if speech.is_empty():
			continue
		var onset := _onset(speech)
		var line := "  %-9s:" % spell
		for cue: String in others:
			var body := speech.duplicate()
			body.append_array(_hiss(0.3))
			var sfx := _resample(synth.make(cue), 0.4)
			for i in sfx.size():
				if onset + i < body.size():
					body[onset + i] += sfx[i]
			var mix := _hiss(0.6)
			mix.append_array(body)
			mix.append_array(_hiss(1.0))
			caster.reset()
			_heard.clear()
			_casts.clear()
			_feed(mix)
			line += "  %s=%s(%s)" % [cue, ",".join(_casts) if not _casts.is_empty() else "MISS", " / ".join(_heard)]
		print(line)
	caster.stop()


## Synth output (44.1 kHz) to 16 kHz with a 3-tap smoothing, scaled to `peak`.
func _resample(src: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var n := int(src.size() * float(RATE) / Synth.RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var m := 0.0
	for i in n:
		var x := float(i) * Synth.RATE / RATE
		var j := int(x)
		var a := src[maxi(j - 1, 0)] * 0.25 + src[j] * 0.5 + src[mini(j + 1, src.size() - 1)] * 0.25
		out[i] = a
		m = maxf(m, absf(a))
	for i in n:
		out[i] *= peak / maxf(m, 1e-6)
	return out


func _onset(s: PackedFloat32Array) -> int:
	for i in s.size():
		if absf(s[i]) > 0.03:
			return i
	return 0


func _hiss(sec: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(sec * RATE))
	for i in a.size():
		a[i] = _rng.randf_range(-0.004, 0.004)
	return a


func _feed(stream: PackedFloat32Array) -> void:
	var start := Time.get_ticks_usec()
	var pos := 0
	while pos < stream.size():
		caster.push_samples(stream.slice(pos, pos + STEP), RATE)
		pos += STEP
		caster.poll()
		var wait := start + int(float(pos) * 1000000.0 / RATE / 4.0) - Time.get_ticks_usec()   # 4x real time, as test_voice_noise
		if wait > 0:
			OS.delay_usec(wait)
	caster.flush()
	for i in 25:
		OS.delay_msec(20)
		caster.poll()
