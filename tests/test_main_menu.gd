extends TestCase
## The main menu: boot routing, the buttons, the 3D background, Start a job, Join a crew (no Steam in tests:
## greyed out), the crew view of a joined client (over ENet in this process), Esc out of sub-screens, the
## Voice setup screen (no mic) and its effect on VoiceSettings, the Settings screen and GameSettings
## persistence, and the in-game pause overlay (Esc during a contract).

const GAME := preload("res://scripts/app/game.gd")
const TMP := "user://test_main_menu_settings.cfg"
const PORT := 28779


func setup() -> void:
	timeout_sec = 120.0
	_rm(TMP)
	_check_routing()
	_check_game_settings()
	await _check_menu()
	await _check_crew_view()
	await _check_voice_setup()
	await _check_settings_screen()
	await _check_pause()
	await _check_panel_setting()
	_rm(TMP)
	finish()


func _rm(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)


func _args(list: Array) -> PackedStringArray:
	return PackedStringArray(list)


func _action(name_: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name_
	e.pressed = true
	return e


# --- Boot routing ----------------------------------------------------------------------------------

func _check_routing() -> void:
	eq(Boot.route(_args([])), Boot.MENU_SCENE, "a plain boot shows the menu")
	eq(Boot.route(_args(["--no-mic"])), Boot.MENU_SCENE, "--no-mic alone still shows the menu")
	eq(Boot.route(_args(["--menu-shot", "x.png", "--menu-screen", "voice"])), Boot.MENU_SCENE, "menu flags show the menu")
	eq(Boot.route(_args(["--settings-file", "s.cfg"])), Boot.MENU_SCENE, "--settings-file shows the menu")
	eq(Boot.route(_args(["--menu", "--seed", "5", "--spells", "heal"])), Boot.MENU_SCENE, "--menu forces the menu")
	for flags: Array in [["--seed", "5"], ["--spells", "heal,corn"], ["--contract", "1"], ["--floor", "2"], ["--shot", "a.png"],
			["--zoom", "6"], ["--proto-heroes"], ["--invoice-demo"], ["--seed", "3", "--no-mic"]]:
		eq(Boot.route(PackedStringArray(flags)), Boot.GAME_SCENE, "dev flags %s jump straight into the game" % str(flags))
	eq(Boot.route(_args(["--net-join", "127.0.0.1:24600", "--net-name", "B", "--net-link", "coast"])), Boot.MENU_SCENE, "--net-join waits on the menu")
	eq(Boot.route(_args(["--net-host", "--net-port", "24601"])), Boot.GAME_SCENE, "--net-host opens the job board")
	eq(Boot.route(_args(["--scene", "res://scenes/rebar_lab.tscn"])), "res://scenes/rebar_lab.tscn", "--scene opens that scene")
	eq(Boot.route(_args(["--menu", "--scene", "res://scenes/rebar_lab.tscn"])), "res://scenes/rebar_lab.tscn", "--scene wins")
	eq(Boot.arg_value(_args(["--a", "1", "--b"]), "--b"), "", "a flag without a value reads as empty")
	# Every flag game.gd understands (except --no-mic) must skip the menu, so no dev flow breaks.
	var src := FileAccess.get_file_as_string("res://scripts/app/game.gd")
	var rx := RegEx.create_from_string("\"(--[a-z-]+)\":\\s*opts\\[")
	var flags_found := 0
	for m in rx.search_all(src):
		var flag := m.get_string(1)
		flags_found += 1
		if flag != "--no-mic":
			eq(Boot.route(PackedStringArray([flag, "1"])), Boot.GAME_SCENE, "game flag %s skips the menu" % flag)
	check(flags_found >= 20, "found the game's dev flags (%d)" % flags_found)
	check(ResourceLoader.exists(Boot.MENU_SCENE), "the menu scene exists")
	check(ResourceLoader.exists(Boot.GAME_SCENE), "the game scene exists")


# --- GameSettings ----------------------------------------------------------------------------------

func _check_game_settings() -> void:
	var d := GameSettings.load_settings(TMP)
	eq(d["master_volume"], 1.0, "default volume 100%")
	eq(d["fullscreen"], false, "default windowed")
	eq(d["resolution"], "1600x900", "default resolution")
	eq(d["voice_panel_visible"], true, "the voice debug panel is visible at start by default")

	check(GameSettings.save_settings({"master_volume": 0.4, "fullscreen": true, "resolution": "1920x1080", "voice_panel_visible": false}, TMP), "saved")
	var s := GameSettings.load_settings(TMP)
	near(float(s["master_volume"]), 0.4, 0.0001, "volume reloads")
	eq(s["fullscreen"], true, "fullscreen reloads")
	eq(s["resolution"], "1920x1080", "resolution reloads")
	eq(s["voice_panel_visible"], false, "panel flag reloads")
	var cfg := ConfigFile.new()
	cfg.load(TMP)
	check(cfg.has_section_key("game", "master_volume") and cfg.has_section_key("game", "voice_panel_visible"), "stored in the [game] section")

	# Voice settings share the file without clobbering each other.
	VoiceSettings.save_settings({"trigger_word": "pickle"}, TMP)
	GameSettings.save_settings({"master_volume": 0.9}, TMP)
	eq(VoiceSettings.load_settings(TMP)["trigger_word"], "pickle", "saving game settings keeps the voice section")
	eq(GameSettings.load_settings(TMP)["resolution"], "1920x1080", "saving one key keeps the others")

	# Garbage is repaired.
	cfg = ConfigFile.new()
	cfg.set_value("game", "master_volume", 7.0)
	cfg.set_value("game", "resolution", "123x45")
	cfg.save(TMP)
	var bad := GameSettings.load_settings(TMP)
	eq(bad["master_volume"], 1.0, "volume is clamped")
	eq(bad["resolution"], "1600x900", "an unknown resolution falls back")
	eq(GameSettings.parse_resolution("1280x720"), Vector2i(1280, 720), "parse 1280x720")

	var before := AudioServer.get_bus_volume_db(0)
	GameSettings.apply_volume(0.5)
	near(AudioServer.get_bus_volume_db(0), linear_to_db(0.5), 0.01, "apply sets the master bus")
	GameSettings.apply_volume(0.0)
	check(AudioServer.is_bus_mute(0), "volume 0 mutes the master bus")
	GameSettings.apply_volume(1.0)
	AudioServer.set_bus_volume_db(0, before)
	AudioServer.set_bus_mute(0, false)
	_rm(TMP)


# --- The menu ------------------------------------------------------------------------------------------

func _make_menu(extra_backdrop := true) -> MainMenu:
	var menu: MainMenu = (load(Boot.MENU_SCENE) as PackedScene).instantiate()
	menu.use_mic = false
	menu.settings_path = TMP
	menu.apply_settings_live = false
	menu.backdrop_enabled = extra_backdrop
	return menu


func _check_menu() -> void:
	var menu := _make_menu()
	var changed: Array[String] = []
	var quit_count := [0]
	menu.change_scene = func(p: String) -> void: changed.append(p)
	menu.quit_game = func() -> void: quit_count[0] += 1
	add_child(menu)
	await frames(3)

	for b: Button in [menu.start_button, menu.join_button, menu.voice_button, menu.settings_button, menu.quit_button]:
		check(b != null and b.is_inside_tree(), "a menu button exists")
	eq(menu.start_button.text, "Start a job", "Start a job")
	eq(menu.start_button.number, "01", "row 01")
	eq(menu.join_button.text, "Join a crew", "Join a crew")
	eq(menu.join_button.number, "02", "row 02")
	eq(menu.voice_button.text, "Voice setup", "Voice setup")
	eq(menu.settings_button.text, "Settings", "Settings")
	eq(menu.quit_button.text, "Quit", "Quit")
	eq((menu.quit_button as FormRow).number, "05", "five rows")
	# No Steam in a test run: Join is greyed out and says why; Start plays solo.
	check(menu.join_button.disabled, "Join a crew is greyed out without Steam")
	eq(menu.join_button.hint, NetSession.STEAM_OFF, "and says Steam isn't running")
	eq(menu.start_button.hint, "solo", "Start a job says it will be solo")
	check(menu.start_button.has_focus(), "keyboard focus starts on Start a job")
	eq(menu.start_button.find_valid_focus_neighbor(SIDE_BOTTOM), menu.voice_button, "Down skips the greyed Join: Start -> Voice setup")
	eq(menu.settings_button.find_valid_focus_neighbor(SIDE_BOTTOM), menu.quit_button, "Down moves Settings -> Quit")
	eq(menu.status_label.text, "", "no status line on a fresh menu")
	eq(menu.screen, "main", "opens on the main screen")

	# The background (the garage, scripts/ui/menu_backdrop.gd; test_menu_backdrops covers it in depth): the three heroes, a hellgate, a moving camera.
	check(menu.backdrop != null, "the 3D backdrop is built")
	if menu.backdrop != null:
		check(menu.backdrop.wick is WickModel and menu.backdrop.rebar is RebarModel and menu.backdrop.gasket is GasketModel, "the three heroes idle in the scene")
		check(menu.backdrop.gate is HellgateModel, "a hellgate glows in the distance")
		check(menu.backdrop.camera != null and menu.backdrop.camera.current, "a camera is current")
		check(menu.backdrop.map.cells.size() > 100, "a generated floor")
		check(menu.backdrop.van is VanModel and MenuBackdrop.MOODS.has(menu.backdrop.mood), "the garage: the van is parked, in a valid mood (%s)" % menu.backdrop.mood)
		var p0: Vector3 = menu.backdrop.camera.global_position
		await frames(60)
		check(menu.backdrop.camera.global_position.distance_to(p0) > 0.001, "the camera orbits")
		check(MenuBackdrop.yaw_at(0.0) != MenuBackdrop.yaw_at(5.0), "the sway changes the yaw over time")
		var tris: int = menu.backdrop.wick.triangle_count() + menu.backdrop.rebar.triangle_count() + menu.backdrop.gasket.triangle_count()
		check(tris < 20000, "the crew stays cheap (%d triangles)" % tris)

	# Start loads the game scene (the job board lives there), solo without Steam.
	menu.start_button.pressed.emit()
	eq(changed, [Boot.GAME_SCENE] as Array[String], "Start opens the game scene")
	eq(Session.offline_note, "Steam not running: solo only", "the board will say why it's solo")
	check(not Session.online(), "no session without Steam")
	var board := JobBoard.new([] as Array[ContractRun])
	add_child(board)
	check(board.crew_strip != null and board.crew_strip.visible and board.crew_strip.text == Session.offline_note, "the job board shows the solo note")
	board.queue_free()
	Session.offline_note = ""
	var game_scene := load(Boot.GAME_SCENE) as PackedScene
	check(game_scene != null, "the game scene loads")
	if game_scene != null:
		var g := game_scene.instantiate()
		check(g is Node3D and g.get_script() == GAME, "it is the game")
		g.free()

	# Sub-screens and Esc.
	menu.settings_button.pressed.emit()
	eq(menu.screen, "settings", "Settings opens the settings screen")
	check(menu.settings_screen != null and not menu.main_panel.visible, "the main buttons give way to it")
	menu._unhandled_input(_action("pause"))
	eq(menu.screen, "main", "Esc backs out of Settings")
	check(menu.main_panel.visible and menu.settings_screen == null, "the main screen is back")
	menu.voice_button.pressed.emit()
	await frames(3)
	eq(menu.screen, "voice", "Voice setup opens the voice screen")
	check(menu.voice_screen != null, "the voice screen exists")
	if menu.voice_screen != null:
		eq(menu.voice_screen.settings_path, TMP, "the voice screen uses the menu's settings file")
		eq(menu.voice_screen.caster.settings_path, TMP, "and so does its caster")
		check(not menu.voice_screen.caster.use_mic, "use_mic=false reaches the caster")
	var vs := menu.voice_screen
	menu._unhandled_input(_action("pause"))
	await frames(3)
	eq(menu.screen, "main", "Esc backs out of Voice setup")
	check(not is_instance_valid(vs), "the voice screen (and its mic) is freed")
	menu.quit_button.pressed.emit()
	eq(quit_count[0], 1, "Quit quits")
	menu.queue_free()
	await frames(2)


# --- A joined client waits on the menu (M0: no shared run yet) -------------------------------------------

## Wall-clock wait: this batch runs --fixed-fps, so frames say nothing about elapsed time on a socket.
func _until(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(cond.call()):
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true


func _check_crew_view() -> void:
	# A host in this process, under its own multiplayer root: its RPC path ("Session/Wire" from the root)
	# matches the autoload's, so the autoload Session can join it over ENet.
	var root := Node.new()
	root.name = "HostRoot"
	add_child(root)
	get_tree().set_multiplayer(SceneMultiplayer.new(), root.get_path())
	var host := NetSession.new()
	host.name = "Session"
	host.telemetry_enabled = false
	host.player_name = "Hana"
	root.add_child(host)
	check(host.host_enet(PORT), "an in-process host")
	Session.telemetry_enabled = false
	Session.player_name = "Tess"
	Session.join_enet("127.0.0.1", PORT)
	if not check(await _until(func() -> bool: return Session.online(), 5.0), "the menu's Session joins it"):
		return
	var menu := _make_menu(false)
	add_child(menu)
	await frames(2)
	eq(menu.join_button.text, "Leave the crew", "joined: Join becomes Leave the crew")
	check(not menu.join_button.disabled, "and is enabled")
	check(menu.start_button.disabled, "Start a job is greyed out while in a crew")
	check(menu.status_label.text.begins_with("Connected to Hana's crew."), "the status says whose crew (%s)" % menu.status_label.text)
	check(menu.status_label.text.contains(MainMenu.WAITING_NOTE), "and that shared jobs come later")
	var lines := menu.crew_label.text.split("\n")
	eq(lines.size(), 2, "the crew list has both players")
	check(lines[0].contains("Hana") and lines[0].begins_with("1") and lines[0].contains("Wick"), "seat 1: the host and its character (%s)" % lines[0])
	check(lines[1].contains("Tess") and lines[1].contains("(you)"), "seat 2: you (%s)" % lines[1])
	check(menu.join_button.has_focus(), "focus moves to Leave the crew")
	# The host leaves: the menu says so and the rows come back.
	host.leave()
	check(await _until(func() -> bool: return not Session.online(), 3.0), "the host's goodbye arrives")
	await frames(2)
	eq(menu.status_label.text, NetSession.HOST_LEFT, "the status says the host clocked out")
	eq(menu.join_button.text, "Join a crew", "the Join row is back")
	eq(menu.crew_label.text, "", "the crew list is cleared")
	check(not menu.start_button.disabled, "Start a job is available again")
	# Leaving on purpose, through the row.
	host.host_enet(PORT)
	Session.join_enet("127.0.0.1", PORT)
	check(await _until(func() -> bool: return Session.online(), 5.0), "joined again")
	await frames(2)
	menu.join_button.pressed.emit()
	check(not Session.online(), "Leave the crew leaves")
	eq(menu.status_label.text, NetSession.YOU_LEFT, "and says so")
	host.leave()
	menu.queue_free()
	root.queue_free()
	Session.player_name = ""
	Session.telemetry_enabled = true
	Session.last_reason = ""
	await frames(3)


# --- Voice setup ---------------------------------------------------------------------------------------

func _check_voice_setup() -> void:
	_rm(TMP)
	var screen := VoiceSetupScreen.new()
	screen.use_mic = false
	screen.settings_path = TMP
	screen.log_utterances = false
	var backed: Array[int] = [0]
	screen.back.connect(func() -> void: backed[0] += 1)
	add_child(screen)
	await frames(4)
	check(screen.caster != null and not screen.caster.use_mic, "the caster runs without a mic")
	check(screen.caster.status != "not started", "the caster started (%s)" % screen.caster.status)
	eq(screen.trigger_menu.item_count, VoiceCaster.TRIGGER_OPTIONS.size() + 1, "every cast word plus custom...")
	eq(screen.strict_menu.item_count, 3, "strict / loose / chaos")
	eq(screen.trigger_menu.get_item_text(screen.trigger_menu.selected), "cast", "default cast word")
	eq(screen.strict_menu.get_item_text(screen.strict_menu.selected), "loose", "default strictness")
	check(screen.strict_help.text.length() > 20, "each strictness has an explanation")
	var helps := {}
	for m: String in VoiceCaster.STRICTNESS_OPTIONS:
		check(VoiceSetupScreen.STRICTNESS_HELP.has(m), "help for " + m)
		helps[VoiceSetupScreen.STRICTNESS_HELP[m]] = true
	eq(helps.size(), 3, "three different explanations")

	# The cast word.
	var v := screen.set_trigger("pickle")
	check(bool(v["ok"]), "pickle is accepted")
	eq(VoiceSettings.load_settings(TMP)["trigger_word"], "pickle", "VoiceSettings holds the cast word")
	eq(screen.trigger_menu.get_item_text(screen.trigger_menu.selected), "pickle", "the dropdown follows")
	check(screen.say_label.text.contains("PICKLE HEAL"), "the Try it prompt names the cast word")
	check(not screen.set_trigger("two words")["ok"], "two words are refused")
	check(screen.trigger_note.visible, "a refused word shows why")
	eq(VoiceSettings.load_settings(TMP)["trigger_word"], "pickle", "a refused word changes nothing")
	check(not screen.set_trigger("heal")["ok"], "a spell word is refused")
	var custom := screen.set_trigger("zorbax")
	check(bool(custom["ok"]), "a custom word is accepted")
	eq(VoiceSettings.load_settings(TMP)["trigger_word"], "zorbax", "the custom word is saved")
	check(screen.trigger_menu.get_item_text(screen.trigger_menu.selected).contains("zorbax"), "the dropdown shows the custom word")
	var warned := screen.set_trigger("go")   # short and common: the screen warns
	check(bool(warned["ok"]) and screen.trigger_note.visible and screen.trigger_note.text != "", "a risky custom word shows warnings")
	# Through the controls themselves.
	screen.trigger_menu.select(0)
	screen.trigger_menu.item_selected.emit(0)
	eq(VoiceSettings.load_settings(TMP)["trigger_word"], VoiceCaster.TRIGGER_OPTIONS[0], "picking a dropdown entry saves it")
	screen.trigger_menu.select(VoiceCaster.TRIGGER_OPTIONS.size())
	screen.trigger_menu.item_selected.emit(VoiceCaster.TRIGGER_OPTIONS.size())
	check(screen.custom_row.visible, "custom... opens the word box")
	screen.custom_edit.text_submitted.emit("Conjure")
	eq(VoiceSettings.load_settings(TMP)["trigger_word"], "conjure", "the word box saves (lower-cased)")
	screen.set_trigger("cast")

	# Strictness.
	check(screen.set_strictness("strict"), "strict")
	eq(VoiceSettings.load_settings(TMP)["strictness"], "strict", "strictness is saved")
	check(screen.strict_help.text.contains("start"), "the strict explanation shows")
	screen.strict_menu.select(2)
	screen.strict_menu.item_selected.emit(2)
	eq(VoiceSettings.load_settings(TMP)["strictness"], "chaos", "the strictness dropdown saves")
	check(screen.say_label.text.contains("any spell word"), "chaos changes the prompt")
	check(not screen.set_strictness("bogus"), "an unknown mode is refused")
	screen.set_strictness("loose")

	# The min-voice slider and the meter.
	screen.set_min_voice(-35.0)
	near(float(VoiceSettings.load_settings(TMP)["min_voice_db"]), -35.0, 0.001, "min voice is saved")
	near(screen.gate_slider.value, -35.0, 0.001, "the slider follows")
	near(screen.caster.gate.min_voice_db, -35.0, 0.001, "and the gate")
	screen.gate_slider.value = -28.0
	near(float(VoiceSettings.load_settings(TMP)["min_voice_db"]), -28.0, 0.001, "moving the slider saves")
	screen.set_min_voice(-120.0)
	near(float(VoiceSettings.load_settings(TMP)["min_voice_db"]), -70.0, 0.001, "min voice is clamped")
	screen.set_min_voice(-42.0)
	check(screen.meter.gate == screen.caster.gate, "the meter reads the caster's gate")
	check(screen.meter.size.x > 200.0, "the meter has room (%d px)" % int(screen.meter.size.x))
	near(screen.meter.db_at(screen.meter.x_of(-42.0)), -42.0, 0.6, "meter x <-> dB round trip")
	var rng := RandomNumberGenerator.new()
	var chunk := PackedFloat32Array()
	chunk.resize(480)
	for i in chunk.size():
		chunk[i] = rng.randf_range(-1.0, 1.0) * 0.1
	screen.caster.gate.process(chunk, 48000)
	await frames(3)
	check(screen.caster.gate.level_db > -30.0, "loud audio reaches the gate level (%.1f dB)" % screen.caster.gate.level_db)
	check(screen.meter.shown_db > -30.0, "the meter shows it")
	screen.meter.threshold_dragged.emit(-50.0)
	near(float(VoiceSettings.load_settings(TMP)["min_voice_db"]), -50.0, 0.001, "dragging the meter's threshold line saves")

	# Try it: "<cast word> heal" -> HEARD, the matched spell and its power.
	screen.set_trigger("cast")
	screen.say("cast heal")
	await frames(2)
	check(screen.heard_label.text.contains("cast heal"), "HEARD shows the text (%s)" % screen.heard_label.text)
	check(screen.result_label.text.begins_with("CAST HEAL"), "the matched spell shows (%s)" % screen.result_label.text)
	check(screen.result_label.text.contains("%"), "with its power")
	var heal_chip: Dictionary = screen._chips["heal"]
	check(float(heal_chip["glow"]) > 0.0 and (heal_chip["power"] as Label).text.contains("%"), "the heal chip lights with its power")
	screen.say("hello there")
	await frames(2)
	check(screen.result_label.text.begins_with("no spell"), "chatter matches nothing (%s)" % screen.result_label.text)
	var typed_ok := [false]
	screen.type_edit.text_submitted.connect(func(_t: String) -> void: typed_ok[0] = true)
	screen.type_edit.text_submitted.emit("cast fireball")
	await frames(2)
	check(typed_ok[0] and screen.result_label.text.begins_with("CAST FIREBALL"), "the type-it box casts (%s)" % screen.result_label.text)

	screen.back_button.pressed.emit()
	eq(backed[0], 1, "Back emits back")
	screen.queue_free()
	await frames(2)

	# The game's own caster picks the saved settings up.
	var game_caster := VoiceCaster.new()
	game_caster.use_mic = false
	game_caster.settings_path = TMP
	game_caster.voice_log.enabled = false
	add_child(game_caster)
	game_caster.start(PackedStringArray(SpellBook.ids()))
	eq(game_caster.get_trigger_word(), "cast", "the game's caster starts with the saved cast word")
	eq(game_caster.get_strictness(), "loose", "and strictness")
	near(game_caster.gate.min_voice_db, -50.0, 0.001, "and min voice")
	game_caster.queue_free()
	_rm(TMP)


# --- Settings screen -----------------------------------------------------------------------------------

func _check_settings_screen() -> void:
	_rm(TMP)
	var s := SettingsScreen.new()
	s.settings_path = TMP
	s.apply_live = false
	add_child(s)
	await frames(3)
	near(s.volume_slider.value, 100.0, 0.01, "volume starts at 100%")
	check(not s.fullscreen_check.button_pressed, "starts windowed")
	check(s.panel_check.button_pressed, "the voice panel is on by default")
	eq(s.resolution_menu.item_count, 3, "three resolutions")
	eq(s.resolution_menu.get_item_text(0), "1280 x 720", "1280 x 720")
	eq(s.resolution_menu.get_item_text(2), "1920 x 1080", "1920 x 1080")

	s.volume_slider.value = 35.0   # the slider itself
	near(float(GameSettings.load_settings(TMP)["master_volume"]), 0.35, 0.001, "the volume slider saves")
	s.fullscreen_check.button_pressed = true
	eq(GameSettings.load_settings(TMP)["fullscreen"], true, "the fullscreen toggle saves")
	check(s.resolution_menu.disabled, "the window size is disabled in fullscreen")
	s.fullscreen_check.button_pressed = false
	check(not s.resolution_menu.disabled, "and enabled in a window")
	s.resolution_menu.select(2)
	s.resolution_menu.item_selected.emit(2)
	eq(GameSettings.load_settings(TMP)["resolution"], "1920x1080", "the resolution dropdown saves")
	s.panel_check.button_pressed = false
	eq(GameSettings.load_settings(TMP)["voice_panel_visible"], false, "the voice panel toggle saves")
	var backed := [0]
	s.back.connect(func() -> void: backed[0] += 1)
	s.back_button.pressed.emit()
	eq(backed[0], 1, "Back emits back")
	s.queue_free()
	await frames(2)

	# A fresh screen reloads everything.
	var s2 := SettingsScreen.new()
	s2.settings_path = TMP
	s2.apply_live = false
	add_child(s2)
	await frames(3)
	near(s2.volume_slider.value, 35.0, 0.01, "volume reloads")
	check(not s2.fullscreen_check.button_pressed, "windowed reloads")
	eq(s2.resolution_menu.selected, 2, "resolution reloads")
	check(not s2.panel_check.button_pressed, "the voice panel flag reloads")
	s2.queue_free()
	await frames(2)
	_rm(TMP)


# --- In-game pause ---------------------------------------------------------------------------------------

func _make_game(extra: Dictionary) -> Node3D:
	var g: Node3D = load("res://scripts/app/game.gd").new()
	var o := {"no_mic": true, "spells": "heal,corn", "contract": 1, "seed": 5}
	o.merge(extra, true)
	g.set("opts", o)
	GAME.reset_flow()
	return g


func _check_pause() -> void:
	_rm(TMP)
	GameSettings.path = TMP
	var g := _make_game({})
	var changed: Array[String] = []
	g.set("scene_changer", func(p: String) -> void: changed.append(p))
	add_child(g)
	await frames(10)
	check(g.get("_session") != null, "a contract is running")
	check(g.call("_can_pause"), "Esc can pause a running contract")

	g.call("_unhandled_input", _action("pause"))
	var pause: PauseMenu = g.get("_pause")
	check(pause != null, "Esc opens the pause overlay")
	check(get_tree().paused, "the tree is paused")
	check(pause.resume_button != null and pause.abandon_button != null and pause.menu_button != null, "Resume / Abandon / Main menu")
	eq(pause.resume_button.text, "Resume", "Resume")
	eq(pause.abandon_button.text, "Abandon contract", "Abandon contract")
	eq(pause.menu_button.text, "Main menu", "Main menu")
	var t0 := GameWorld.time
	var pos0: Vector3 = (g.get("player") as Hero).global_position
	await frames(20)
	eq(GameWorld.time, t0, "the game clock stands still while paused")
	check((g.get("player") as Hero).global_position.is_equal_approx(pos0), "the world stands still")
	check(not g.call("_can_pause"), "a second Esc does not stack another overlay")

	pause.resume_button.pressed.emit()
	check(g.get("_pause") == null and not get_tree().paused, "Resume unpauses")
	await frames(10)
	check(GameWorld.time > t0, "the clock runs again")

	# Not while another modal is open.
	g.set("_menu", ElevatorMenu.new({}))
	check(not g.call("_can_pause"), "no pause over the elevator menu")
	(g.get("_menu") as Node).free()
	g.set("_menu", null)
	g.set("_ended", true)
	check(not g.call("_can_pause"), "no pause once the contract is over")
	g.set("_ended", false)
	check(g.call("_can_pause"), "pausable again")

	# Abandon: back to the job board, the contract dropped.
	g.call("_unhandled_input", _action("pause"))
	pause = g.get("_pause")
	pause.abandon_button.pressed.emit()
	eq(changed, [""] as Array[String], "Abandon reloads the game scene (the job board)")
	check(g.get("_session") == null and not get_tree().paused, "the contract is dropped and the tree runs")
	g.queue_free()
	await frames(3)

	# Main menu.
	changed.clear()
	g = _make_game({})
	g.set("scene_changer", func(p: String) -> void: changed.append(p))
	add_child(g)
	await frames(10)
	g.call("_unhandled_input", _action("pause"))
	pause = g.get("_pause")
	pause.menu_button.pressed.emit()
	eq(changed, [Boot.MENU_SCENE] as Array[String], "Main menu opens the menu scene")
	check(not get_tree().paused, "the tree runs again")
	g.queue_free()
	await frames(3)

	# The spell picker is a modal too; Esc on the job board goes to the menu.
	changed.clear()
	g = _make_game({})
	g.get("opts").erase("spells")
	g.set("scene_changer", func(p: String) -> void: changed.append(p))
	add_child(g)
	await frames(10)
	check(g.get("_picker") != null, "the spell picker is open")
	check(not g.call("_can_pause"), "no pause over the spell picker")
	g.queue_free()
	await frames(3)
	GAME.reset_flow()
	g = _make_game({})
	g.get("opts").erase("spells")
	g.get("opts").erase("contract")
	g.set("scene_changer", func(p: String) -> void: changed.append(p))
	add_child(g)
	await frames(4)
	check(g.get("_board") != null, "the job board is up")
	g.call("_unhandled_input", _action("pause"))
	eq(changed, [Boot.MENU_SCENE] as Array[String], "Esc on the job board goes to the main menu")
	g.queue_free()
	await frames(3)
	GAME.reset_flow()
	GameSettings.path = GameSettings.DEFAULT_PATH
	_rm(TMP)


## Settings > "Voice debug panel visible at start" is what game.gd reads.
func _check_panel_setting() -> void:
	_rm(TMP)
	GameSettings.path = TMP
	for on: bool in [false, true]:
		GameSettings.save_settings({"voice_panel_visible": on}, TMP)
		var g := _make_game({})
		add_child(g)
		await frames(6)
		var panel: Control = g.get("debug_panel")
		check(panel != null and panel.visible == on, "voice panel visible at start = %s" % str(on))
		eq((g.get("voice") as VoiceCaster).settings_path, TMP, "the game's voice caster reads the same settings file")
		g.queue_free()
		await frames(3)
		GAME.reset_flow()
	GameSettings.path = GameSettings.DEFAULT_PATH
	_rm(TMP)
