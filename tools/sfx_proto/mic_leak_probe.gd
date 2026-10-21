extends Node
## Mic-leak probe for the audio plan (docs/design/audio-plan.md, "Mic safety"): plays each prototype cue into the real
## recognizer as if it leaked from speakers into the mic, and checks that
##   A. a cue on its own produces no words and no casts (gate on and off), and
##   B. the "cast heard" chime, overlapping the spell word, does not break a real "cast <spell>".
##   C. a "cast <spell>" said over a teammate's loud cue starting with the voice still casts (voice a0; with recipes
##      named on the command line, voice b0 too).
##   D. (2026-10-21) a "cast <spell>" said with a REPEATING or SUSTAINED cue running under the whole utterance (wading steps
##      every 0.45 s, the lava bed replayed every 1.7 s, the live wire's 6 s buzz) still casts: at peaks 0.4, 0.2 and 0.1,
##      and for the beds the game ducks also at 0.1 ducked as the game does it (DUCK_DB from 100 ms after the voice onset,
##      the gate's look-ahead, to 300 ms after its end). A control row with no cue runs first.
##   Godot --path . --headless res://tools/sfx_proto/mic_leak_probe.tscn [-- <recipe> ...]
## (A scene, not --script, since 2026-10-21: the recognizer's spell list now needs the autoloads, GameWorld among them.)
## With no recipes it probes every one the game renders (render_game_sfx.gd GAME_CUES). A runs them, B runs the
## cast_armed* ones among them, C the others, and D the ones in REPEATS.
## Needs the model and the TTS clips (tests/voice_clips). Not part of the test suite.
const Synth = preload("res://tools/sfx_proto/sfx_round3.gd")   # it extends sfx_synth.gd
const Render = preload("res://tools/sfx_proto/render_game_sfx.gd")
const RATE := 16000
const STEP := 320
## D: recipe -> seconds between its starts under the utterance (how the game repeats it).
const REPEATS := {"wade_step_v1": 0.45, "lava_bubble_v1": 1.7, "wire_buzz_v4": 6.0}
## D: the beds the game ducks while the local player speaks (Sfx duck_db), and by how much.
const DUCKED := {"lava_bubble_v1": true, "wire_buzz_v4": true}
const DUCK_DB := -10.0

var caster: VoiceCaster
var _heard: Array[String] = []
var _casts: Array[String] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	_run()
	get_tree().quit()


func _run() -> void:
	caster = VoiceCaster.new()
	caster.use_mic = false
	caster.use_saved_settings = false
	caster.persist_settings = false
	caster.voice_log.enabled = false
	add_child(caster)
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
	for sv: String in ["heal_a0", "fireball_a0", "corn_a0", "heal_b0", "fireball_b0", "corn_b0"]:
		var spell := sv.get_slice("_", 0)
		if sv.ends_with("b0") and args.is_empty():
			continue   # (the full default run keeps its round 1-3 shape: voice a0)
		var speech: PackedFloat32Array = wav_lib.call("_load_wav16", clips.path_join("clean_cast_%s.wav" % sv))
		if speech.is_empty():
			continue
		var onset := _onset(speech)
		var line := "  %-12s:" % sv
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

	var repeating: Array = cues.filter(func(c: String) -> bool: return REPEATS.has(c))
	if not repeating.is_empty():
		print("D. 'cast <spell>' with a repeating or sustained cue under the whole utterance (gate on; peak 0.4 loud, 0.2, 0.1 realistic,")
		print("   and for the beds the game ducks, 0.1 ducked: DUCK_DB from 100 ms after the voice onset to 300 ms after its end)")
	if not repeating.is_empty():
		repeating.push_front("(none)")   # the control: the same runs with no cue at all
	for cue: String in repeating:
		var one := synth.make(cue) if cue != "(none)" else PackedFloat32Array([0.0])
		var conds: Array = [[0.4, false], [0.2, false], [0.1, false]]
		if DUCKED.has(cue):
			conds.append([0.1, true])
		var tally := {}
		var line := "  %-16s" % cue
		for spell: String in ["heal", "fireball", "armor", "corn", "coffee"]:
			for voice in ["a0", "b0"]:
				var speech: PackedFloat32Array = wav_lib.call("_load_wav16", clips.path_join("clean_cast_%s_%s.wav" % [spell, voice]))
				if speech.is_empty():
					continue
				for cond: Array in conds:
					var level: float = cond[0]
					var ducked: bool = cond[1]
					var lead := int(0.8 * RATE)   # (the speech starts 0.8 s in, under the cue already running)
					var body := _hiss(0.8)
					body.append_array(speech)
					body.append_array(_hiss(1.2))
					var bed := PackedFloat32Array()
					bed.resize(body.size())
					var s := _resample(one, level)
					var period := int(float(REPEATS.get(cue, 10.0)) * RATE)
					var at := 0
					while at < bed.size():
						for i in s.size():
							if at + i < bed.size():
								bed[at + i] += s[i]
						at += period
					if ducked:
						var d0 := lead + _onset(speech) + int(0.1 * RATE)
						var d1 := lead + _offset(speech) + int(0.3 * RATE)
						var g := db_to_linear(DUCK_DB)
						for i in bed.size():
							var k := 0.0
							if i >= d0 and i < d1:
								k = minf(float(i - d0) / (0.03 * RATE), 1.0)
							elif i >= d1:
								k = maxf(1.0 - float(i - d1) / (0.25 * RATE), 0.0)
							bed[i] *= lerpf(1.0, g, k)
					for i in body.size():
						body[i] += bed[i]
					caster.reset()
					_heard.clear()
					_casts.clear()
					_feed(body)
					var tag := "%.2f%s" % [level, " ducked" if ducked else ""]
					var t: Array = tally.get(tag, [0, 0])
					t[1] += 1
					if _casts.has(spell):
						t[0] += 1
						if _casts.size() > 1:
							line += "  EXTRA %s/%s@%s(%s)" % [spell, voice, tag, ",".join(_casts)]
					else:
						line += "  MISS %s/%s@%s(%s)" % [spell, voice, tag, " / ".join(_heard)]
					tally[tag] = t
		var sums := []
		for tag: String in tally:
			sums.append("%s %d/%d" % [tag, tally[tag][0], tally[tag][1]])
		print("%s  | cast: %s" % [line, ", ".join(sums)])
	caster.stop()


func _offset(s: PackedFloat32Array) -> int:
	for i in range(s.size() - 1, -1, -1):
		if absf(s[i]) > 0.03:
			return i
	return s.size()


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
