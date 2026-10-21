extends TestCase
## The sound system (scripts/fx/sfx.gd, the `Sfx` autoload; docs/design/audio-plan.md "As built"):
## - the bus layout (default_bus_layout.tres) and every cue on an existing bus, every cue with a render recipe;
## - Sfx is silent and builds nothing headless, and a missing file keeps its cue silent without an error;
## - the voice hooks: VoiceCaster.trigger_heard fires once per armed trigger (Incantation.trigger_armed), the fizzle
##   plays on spell_fizzled, is cut the moment the listener hears new speech (speech_started), and is not started over
##   speech (mic safety, audio-plan.md Â§4);
## - paper: a form opening plays it, so does a VOID going back and the spec sheet turning to another spell; a burst
##   of opens inside min_gap plays once;
## - pools: the cue's voice limit steals its oldest voice; jitter rolls GameWorld.fx_rng, never GameWorld.rng;
## - ducking: the long beds (a duck_db: the lava's bubbling) go down while the local player speaks,
##   held a moment after, then come back; other cues keep their level (the sewer and lava hooks: test_sfx_sewer_lava);
## - GameSettings round-trips the Effects / Paperwork / Spell feedback volumes and apply() sets each bus by name.
## No audio files or speech model needed: tests put their own streams in (Sfx.override_stream).

const TMP := "user://test_sfx_settings.cfg"
const RATE := 16000
const RENDER := "res://tools/sfx_proto/render_game_sfx.gd"
const SYNTH := "res://tools/sfx_proto/sfx_round3.gd"


func setup() -> void:
	timeout_sec = 120.0
	_check_buses()
	_check_recipes()
	_check_headless()
	Sfx.enable_for_tests()
	_check_missing_files()
	await _check_pools()
	_check_trigger_signal()
	await _check_voice_cues()
	await _check_ducking()
	await _check_paper()
	Sfx.disable_for_tests()
	_check_settings()
	_rm(TMP)
	finish()


func _rm(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)


## A short tone that plays long enough to be caught playing.
func _tone(seconds: float = 1.0) -> AudioStreamWAV:
	var n := int(seconds * 22050.0)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(2000.0 * sin(TAU * 440.0 * float(i) / 22050.0)))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	w.data = bytes
	return w


## Let `ms` of real time pass (Sfx's min_gap is wall-clock; tests run at --fixed-fps, so frames are not real time).
func _real_ms(ms: int) -> void:
	OS.delay_msec(ms)
	await frames(1)


## Let a stop_cue fade (game time, a tween) finish.
func _after_fade() -> void:
	await frames(ceili(Sfx.STOP_FADE * Engine.physics_ticks_per_second) + 4)


# --- buses and the cue table -----------------------------------------------------------------------

func _check_buses() -> void:
	var sends := {"SFX": "Master", "World": "SFX", "Stings": "SFX", "UI": "Master", "VoiceFeedback": "Master", "Music": "Master"}
	for bus: String in sends:
		var i := AudioServer.get_bus_index(bus)
		if check(i > 0, "bus %s exists" % bus):
			eq(str(AudioServer.get_bus_send(i)), sends[bus], "%s sends to %s" % [bus, sends[bus]])
	check(AudioServer.get_bus_effect_count(0) >= 1 and AudioServer.get_bus_effect(0, 0) is AudioEffectHardLimiter, "a limiter on Master")
	var sfx := AudioServer.get_bus_index("SFX")
	check(sfx > 0 and AudioServer.get_bus_effect_count(sfx) >= 1 and AudioServer.get_bus_effect(sfx, 0) is AudioEffectCompressor, "a compressor on SFX")
	for cue: String in Sfx.CUES:
		var c: Dictionary = Sfx.CUES[cue]
		check(AudioServer.get_bus_index(str(c["bus"])) >= 0, "cue %s's bus %s exists" % [cue, c["bus"]])
		for key in ["file", "volume_db", "pitch_jitter", "max_voices", "min_gap", "positional"]:
			check(c.has(key), "cue %s has %s" % [cue, key])
		if bool(c["positional"]):
			check(c.has("unit_size") and c.has("max_distance"), "3D cue %s has a distance" % cue)
	for cue in ["cast_heard", "fizzle"]:
		eq(Sfx.CUES[cue]["bus"], "VoiceFeedback", "%s is spell feedback (own volume, never ducked)" % cue)
		check(not bool(Sfx.CUES[cue]["positional"]), "%s is not positional (your machine only)" % cue)
	eq(Sfx.CUES["stamp"]["bus"], "UI", "the stamp is paperwork")
	eq(Sfx.CUES["paper"]["bus"], "UI", "the paper is paperwork")
	check(not bool(Sfx.CUES["paper"]["positional"]) and float(Sfx.CUES["paper"]["min_gap"]) >= 0.1, "paper: flat, with a gap against fast navigation")
	for cue in ["fireball", "elevator_ding"]:
		eq(Sfx.CUES[cue]["bus"], "World", "%s is a world sound" % cue)
		check(bool(Sfx.CUES[cue]["positional"]), "%s is 3D" % cue)


## Every game cue is rendered from a recipe that exists (tools/sfx_proto/render_game_sfx.gd).
func _check_recipes() -> void:
	var render: Script = load(RENDER)
	var map: Dictionary = render.get_script_constant_map()["GAME_CUES"]
	eq(map.keys().size(), Sfx.CUES.keys().size(), "one recipe per cue")
	var synth: Object = (load(SYNTH) as Script).new()
	for cue: String in Sfx.CUES:
		check(map.has(cue), "cue %s has a render recipe" % cue)
		eq(str(Sfx.CUES[cue]["file"]), cue + ".wav", "cue %s's file is <cue>.wav (what the render writes)" % cue)
		if map.has(cue):
			check(synth.has_method("_" + str(map[cue])), "recipe %s exists" % map[cue])


# --- headless and missing files ----------------------------------------------------------------------

func _check_headless() -> void:
	check(not Sfx.enabled, "Sfx is off headless")
	var rng_state := GameWorld.fx_rng.state
	for cue: String in Sfx.CUES:
		check(Sfx.play(cue) == null, "headless: %s plays nothing" % cue)
		check(Sfx.play_at(cue, Vector3(1, 0, 2)) == null, "headless: %s at a point plays nothing" % cue)
	Sfx.stop_cue("fizzle")
	eq(Sfx.get_child_count(), 0, "headless: no players, no listener built")
	check(Sfx.played.is_empty(), "headless: nothing counted")
	eq(GameWorld.fx_rng.state, rng_state, "headless: no rolls")


func _check_missing_files() -> void:
	Sfx.dir = "res://tests/no_such_sfx_dir/"
	for cue: String in Sfx.CUES:
		check(Sfx.play(cue) == null, "missing file: %s stays silent" % cue)
		check(Sfx.stream_of(cue) == null, "missing file: no stream for %s" % cue)
	check(Sfx.played.is_empty(), "missing files play nothing")
	Sfx.dir = Sfx.DIR


# --- players ---------------------------------------------------------------------------------------

func _check_pools() -> void:
	var tone := _tone()
	for cue: String in Sfx.CUES:
		Sfx.override_stream(cue, tone)
	var rng_state := GameWorld.rng.state
	var fx_state := GameWorld.fx_rng.state
	var p := Sfx.play_at("fireball", Vector3(3, 0, 4))
	check(p is AudioStreamPlayer3D, "a 3D cue plays on a 3D player")
	if p is AudioStreamPlayer3D:
		check((p as AudioStreamPlayer3D).global_position.is_equal_approx(Vector3(3, 0, 4)), "at the point")
		eq(str((p as AudioStreamPlayer3D).bus), "World", "on its bus")
		check((p as AudioStreamPlayer3D).playing, "playing (dummy driver)")
	eq(GameWorld.rng.state, rng_state, "jitter never touches GameWorld.rng")
	check(GameWorld.fx_rng.state != fx_state, "jitter rolls GameWorld.fx_rng")
	var flat := Sfx.play("fireball")
	check(flat == null, "min_gap drops a replay this soon")
	await _real_ms(60)
	flat = Sfx.play("fireball")
	check(flat is AudioStreamPlayer, "play() of a 3D cue plays flat")
	var stamp := Sfx.play_at("stamp", Vector3(9, 0, 9))
	check(stamp is AudioStreamPlayer, "a non-positional cue ignores the point")
	# The stamp's voice limit (2): a third steals the oldest.
	var stamps: Array[Node] = [stamp]
	for i in 2:
		await _real_ms(70)
		stamps.append(Sfx.play("stamp"))
	var playing := 0
	for s in Sfx.get_children():
		if s is AudioStreamPlayer and s.get("playing") and Sfx._voice.get(s, [""])[0] == "stamp":
			playing += 1
	check(stamps[2] == stamps[0], "the third stamp took the oldest stamp's player")
	eq(playing, 2, "no more than max_voices stamps at once")
	Sfx.stop_cue("stamp", 0.0)
	check(not Sfx.is_playing("stamp"), "stop_cue(.., 0) stops at once")
	Sfx.stop_cue("fireball", 0.0)


# --- voice hooks -----------------------------------------------------------------------------------

## Incantation.trigger_armed: once per trigger, not again while a partial is revised, again for the next one.
func _check_trigger_signal() -> void:
	var inc := Incantation.new(PackedStringArray(["heal", "fireball", "corn"]))
	var armed: Array[String] = []
	inc.trigger_armed.connect(func(tok: String) -> void: armed.append(tok))
	inc.feed("CAST", false, 1.0)
	eq(armed.size(), 1, "a partial CAST arms the trigger")
	inc.feed("CAST HE", false, 1.3)
	inc.feed("CAST HEAL", true, 1.6)
	eq(armed.size(), 1, "the same trigger, revised partials: still once")
	inc.feed("CAST CORN", true, 3.0)
	eq(armed.size(), 2, "the next utterance's trigger arms again")
	inc.feed("CAST HEAL CAST CORN", true, 5.0)
	eq(armed.size(), 4, "two triggers in one breath: twice")
	inc.feed("HEAL", true, 7.0)
	eq(armed.size(), 4, "a spell word alone arms nothing")
	var strict := Incantation.new(PackedStringArray(["heal"]), {"strictness": "strict"})
	var n := [0]
	strict.trigger_armed.connect(func(_t: String) -> void: n[0] += 1)
	strict.feed("I CAST", true, 1.0)
	eq(n[0], 0, "strict: a trigger mid-sentence is not armed, so no cue")


func _caster() -> VoiceCaster:
	var vc := VoiceCaster.new()
	vc.use_mic = false
	vc.use_saved_settings = false
	vc.persist_settings = false
	vc.voice_log.enabled = false
	add_child(vc)
	return vc


## Push `seconds` of a voiced tone (amp) or of faint hiss through the caster's gate, as the mic would.
func _push(vc: VoiceCaster, seconds: float, amp: float, live: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	for i in s.size():
		var t := float(i) / RATE
		s[i] = (amp * sin(TAU * 180.0 * t) * (0.6 + 0.4 * sin(TAU * 4.0 * t)) if amp > 0.0 else 0.0) + rng.randf_range(-0.003, 0.003)
	if live:
		vc.push_samples(s, RATE)
	else:
		# (no speech model: the same gate and the same onset bookkeeping push_samples runs)
		vc.gate.process(s, RATE)
		vc._note_voice_end(RATE)


func _check_voice_cues() -> void:
	var vc := _caster()
	var live := vc.start(PackedStringArray(["heal", "fireball", "corn"]))
	if not live:
		print("test_sfx: no speech model; driving the caster's gate directly")
	Sfx.listen_to_voice(vc)
	var heard: Array[String] = []
	var starts := [0]
	vc.trigger_heard.connect(func(w: String) -> void: heard.append(w))
	vc.speech_started.connect(func() -> void: starts[0] += 1)

	# The trigger arms: the hook fires once and "cast heard" plays.
	Sfx.played.clear()
	vc.inject_text("cast heal")
	eq(heard.size(), 1, "trigger_heard fires when the trigger arms")
	if heard.size() == 1:
		eq(heard[0].to_lower(), "cast", "with the token heard")
	eq(int(Sfx.played.get("cast_heard", 0)), 1, "cast_heard plays")
	check(Sfx.is_playing("cast_heard"), "cast_heard is playing")

	# A fizzle plays (on the VoiceFeedback bus) ...
	_push(vc, 1.0, 0.0, live)   # (quiet: the gate learns the floor)
	eq(starts[0], 0, "hiss is not speech")
	check(not vc.is_speaking(), "not speaking yet")
	vc.inject_text("cast hello")
	eq(int(Sfx.played.get("fizzle", 0)), 1, "the fizzle plays on spell_fizzled")
	check(Sfx.is_playing("fizzle"), "the fizzle is playing")
	# ... and stops the moment the listener hears new speech.
	_push(vc, 0.3, 0.2, live)
	eq(starts[0], 1, "speech_started fires at the voice onset")
	check(vc.is_speaking(), "speaking now")
	await _after_fade()
	check(not Sfx.is_playing("fizzle"), "the fizzle stopped when speech started")

	# While the player is speaking a new fizzle does not start at all.
	await _real_ms(150)   # (past the cue's min_gap)
	vc.inject_text("cast hello")
	eq(int(Sfx.played.get("fizzle", 0)), 1, "no fizzle over the player's speech")
	check(not Sfx.is_playing("fizzle"), "still silent")
	# Speech ends; the next fizzle plays again.
	_push(vc, 1.0, 0.0, live)
	check(not vc.is_speaking(), "the span ended")
	vc.inject_text("cast hello")
	eq(int(Sfx.played.get("fizzle", 0)), 2, "a fizzle after the speech plays")
	_push(vc, 0.3, 0.2, live)
	eq(starts[0], 2, "the next onset is a new speech start")
	await _after_fade()
	check(not Sfx.is_playing("fizzle"), "and it is cut again")
	vc.stop()
	vc.queue_free()


## The long beds (a "duck_db" in CUES: the lava's bubbling) go down while the local player speaks and
## come back after (audio-plan.md §4 rule 4); every other cue keeps its level.
func _check_ducking() -> void:
	var beds: Array[String] = []
	for cue: String in Sfx.CUES:
		if Sfx.CUES[cue].has("duck_db"):
			beds.append(cue)
			check(float(Sfx.CUES[cue]["duck_db"]) <= -6.0, "%s ducks by 6 dB or more" % cue)
			check(bool(Sfx.CUES[cue]["positional"]), "%s is a 3D bed" % cue)
	check(beds.has("lava_bubble"), "the lava bed ducks")
	var vc := _caster()
	var live := vc.start(PackedStringArray(["heal", "fireball", "corn"]))
	Sfx.listen_to_voice(vc)
	Sfx.override_stream("lava_bubble", _tone(3.0))
	Sfx.override_stream("fireball", _tone(3.0))
	await _real_ms(int(Sfx.DUCK_HOLD * 1000.0) + 80)   # (the last check's speech is over: no duck left)
	Sfx._tick_duck(1.0)
	var bed := Sfx.play_at("lava_bubble", Vector3(1, 0, 1)) as AudioStreamPlayer3D
	var shot := Sfx.play_at("fireball", Vector3(2, 0, 2)) as AudioStreamPlayer3D
	if not check(bed != null and shot != null, "a bed and a fireball playing"):
		vc.stop()
		vc.queue_free()
		return
	var base := float(Sfx.CUES["lava_bubble"]["volume_db"])
	near(bed.volume_db, base, 0.01, "the bed at its level while nobody speaks")
	# Ducking is off in the game for now (Sfx.ducking): the player's voice leaves the bed alone.
	check(not Sfx.ducking, "ducking is off by default (user, 2026-10-21)")
	_push(vc, 1.0, 0.0, live)
	_push(vc, 0.3, 0.2, live)
	Sfx._tick_duck(0.1)
	near(bed.volume_db, base, 0.01, "with ducking off, the bed keeps its level while the player speaks")
	_push(vc, 1.0, 0.0, live)
	await _real_ms(int(Sfx.DUCK_HOLD * 1000.0) + 80)
	Sfx._tick_duck(1.0)
	# The mechanism, switched on as it will be later.
	Sfx.ducking = true
	_push(vc, 1.0, 0.0, live)
	_push(vc, 0.3, 0.2, live)
	check(vc.is_speaking(), "the player speaks")
	Sfx._tick_duck(0.1)
	near(Sfx.duck_level(), 1.0, 0.001, "ducked within the attack (%.0f ms)" % (Sfx.DUCK_ATTACK * 1000.0))
	near(bed.volume_db, base + float(Sfx.CUES["lava_bubble"]["duck_db"]), 0.01, "the bed goes down by its duck_db")
	near(shot.volume_db, float(Sfx.CUES["fireball"]["volume_db"]), 0.01, "a fireball keeps its level")
	Sfx._last.erase("lava_bubble")   # (past its min_gap)
	var later := Sfx.play_at("lava_bubble", Vector3(4, 0, 4)) as AudioStreamPlayer3D
	if check(later != null, "a second bed play"):
		near(later.volume_db, base + float(Sfx.CUES["lava_bubble"]["duck_db"]), 0.01, "a bed that starts while the player speaks starts ducked")
	var t0 := Time.get_ticks_msec()
	_push(vc, 1.0, 0.0, live)
	check(not vc.is_speaking(), "the player stopped")
	Sfx._tick_duck(0.1)
	if Time.get_ticks_msec() - t0 < int(Sfx.DUCK_HOLD * 1000.0) - 50:   # (the push itself can take that long with the model)
		near(Sfx.duck_level(), 1.0, 0.001, "held just after the voice stops (%.0f ms)" % (Sfx.DUCK_HOLD * 1000.0))
	await _real_ms(int(Sfx.DUCK_HOLD * 1000.0) + 30)
	Sfx._tick_duck(Sfx.DUCK_RELEASE * 0.5)
	check(Sfx.duck_level() > 0.3 and Sfx.duck_level() < 0.7, "coming back up over the release (%.2f)" % Sfx.duck_level())
	Sfx._tick_duck(Sfx.DUCK_RELEASE)
	near(Sfx.duck_level(), 0.0, 0.001, "back up")
	near(bed.volume_db, base, 0.01, "the bed at its level again")
	Sfx.ducking = false
	Sfx.stop_cue("lava_bubble", 0.0)
	Sfx.stop_cue("fireball", 0.0)
	Sfx.override_stream("lava_bubble", _tone())
	Sfx.override_stream("fireball", _tone())
	vc.stop()
	vc.queue_free()


# --- paper ---------------------------------------------------------------------------------------

func _check_paper() -> void:
	Sfx.played.clear()
	await _real_ms(250)
	var screen := SettingsScreen.new()
	screen.settings_path = TMP
	screen.apply_live = false
	add_child(screen)
	eq(int(Sfx.played.get("paper", 0)), 1, "opening a form (Settings) plays the paper")
	var picker := SpellPicker.new()
	add_child(picker)
	eq(int(Sfx.played.get("paper", 0)), 1, "a second form inside min_gap: no machine-gun")
	await _real_ms(250)
	var ids := picker.offered()
	if check(ids.size() >= 2, "the requisition offers spells"):
		picker.focus_line(1)
		await frames(2)
		eq(int(Sfx.played.get("paper", 0)), 2, "the spec sheet turning to another spell plays the paper")
		await _real_ms(250)
		picker.focus_line(1)
		await frames(2)
		eq(int(Sfx.played.get("paper", 0)), 2, "the same page again: nothing")
	picker.queue_free()
	await _real_ms(250)
	var stamps := int(Sfx.played.get("stamp", 0))
	check(screen.void_back(), "void the settings form")
	await after_void()
	eq(int(Sfx.played.get("stamp", 0)), stamps + 1, "the VOID stamp lands")
	eq(int(Sfx.played.get("paper", 0)), 3, "and the voided form goes with the paper")
	if is_instance_valid(screen):
		screen.queue_free()
	_rm(TMP)


# --- settings --------------------------------------------------------------------------------------

func _check_settings() -> void:
	_rm(TMP)
	# No per-sound controls for players (user, 2026-10-18): the master volume is the only one; the rest is tuned in the game.
	eq(GameSettings.BUS_VOLUMES.keys(), ["master_volume"], "the master is the only volume setting")
	for key in ["sfx_volume", "ui_volume", "voice_feedback_volume"]:
		check(not GameSettings.defaults().has(key), "no %s setting" % key)
	var before := {}
	for bus: String in ["Master", "SFX", "UI", "VoiceFeedback"]:
		var i := AudioServer.get_bus_index(bus)
		before[bus] = [AudioServer.get_bus_volume_db(i), AudioServer.is_bus_mute(i)]
	GameSettings.apply({"master_volume": 0.8}, false)
	near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), linear_to_db(0.8), 0.01, "apply sets Master")
	GameSettings.apply_bus_volume("NoSuchBus", 0.5)   # (skipped, no error)
	var screen := SettingsScreen.new()
	screen.settings_path = TMP
	screen.apply_live = false
	add_child(screen)
	check(screen.volume_slider != null, "the settings form has the master volume")
	screen.queue_free()

	for bus: String in before:
		var i := AudioServer.get_bus_index(bus)
		AudioServer.set_bus_volume_db(i, float(before[bus][0]))
		AudioServer.set_bus_mute(i, bool(before[bus][1]))
