extends TestCase
## The gym door (user, 2026-10-22: "a way to trigger the gym from the main menu. Maybe clicking on the H in HEXES in the
## garage?"; docs/design/test-gym.md "From the main menu"):
##   1. the backdrop: the menu camera's ray finds the dead H of "WE FIX HEXES" at several window sizes and aspects and in
##      every mood, and only the H (its neighbours, the bare wall and the heroes are not it); the hover makes it sputter
##   2. the main menu: the pointer on the H wakes it (and leaves the pointer an arrow), a click opens the game with the gym's
##      flag (game.gd menu_args), which GymDev.parse reads as `--gym`; a sub-screen covers it
##   3. never in a crew: a hosting attempt, and a real (in-process ENet) crew, ignore the H
##   4. the game with only the menu's flag (no command line) is the gym: GymDev attaches on GymMap's floor with the pick as
##      the player's hero, and the pause menu's "Main menu" goes back to the menu and forgets the flag

const GAME := preload("res://scripts/app/game.gd")
const TMP := "user://test_gym_door_settings.cfg"
const PORT := 28785
## Window sizes (and so aspects) the door must work at: 16:9 small and large, ultrawide, 4:3, 16:10.
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1024, 768), Vector2i(1680, 1050)]


func setup() -> void:
	timeout_sec = 150.0
	_rm(TMP)
	await _check_backdrop()
	await _check_menu()
	await _check_crew()
	await _check_game()
	_rm(TMP)
	GAME.reset_flow()
	Session.character_id = ""
	finish()


func _rm(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)


func _until(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(cond.call()):
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true


# --- 1. The backdrop: the ray finds the H ---------------------------------------------------------------------------

## A letter of the sign on screen (its mesh's middle).
func _letter_point(g: MenuBackdrop, i: int) -> Vector2:
	var m := g.get_node("HexesSign/Letter%d" % i) as MeshInstance3D
	return g.camera.unproject_position(m.global_transform * m.get_aabb().get_center())


func _check_backdrop() -> void:
	eq(MenuBackdrop.HEXES_SIGN.substr(MenuBackdrop.GYM_LETTER, 1), "H", "the door is the H ...")
	eq(MenuBackdrop.HEXES_SIGN.substr(MenuBackdrop.GYM_LETTER, 5), "HEXES", "... of HEXES")
	var vp := SubViewport.new()
	vp.size = SIZES[0]
	vp.own_world_3d = true
	add_child(vp)
	var g := MenuBackdrop.new()
	g.mood = "dawn"
	vp.add_child(g)
	await frames(3)
	var h := g.get_node_or_null("HexesSign/Letter%d" % MenuBackdrop.GYM_LETTER) as MeshInstance3D
	if not check(h != null, "the sign's H is its own mesh"):
		vp.queue_free()
		return
	near(float((h.material_override as ShaderMaterial).get_shader_parameter("glow_gain")), MenuBackdrop.DEAD_GAIN, 0.001, "the H is burnt out")
	for mood in MenuBackdrop.MOODS:
		g.set_mood(mood)
		for size in SIZES:
			vp.size = size
			await frames(2)   # (the camera sways a little between frames: the ray follows it)
			var at := g.door_screen_point()
			var tag := "%s %dx%d" % [mood, size.x, size.y]
			check(Rect2(Vector2.ZERO, Vector2(size)).has_point(at), "%s: the H is on screen (%s)" % [tag, str(at)])
			check(g.door_at(at), "%s: the ray finds the H under itself" % tag)
			eq(g.hero_at(at), "", "%s: no hero stands in front of it" % tag)
			# only the H: its neighbours on the sign, the wall above and below, the far corners
			for i in [MenuBackdrop.GYM_LETTER - 2, MenuBackdrop.GYM_LETTER + 1, MenuBackdrop.GYM_LETTER + 2]:
				var near_at := _letter_point(g, i)
				check(not g.door_at(near_at), "%s: letter %d (%s) is not the door" % [tag, i, MenuBackdrop.HEXES_SIGN.substr(i, 1)])
			var tall := float(size.y) * 0.05
			check(not g.door_at(at + Vector2(0, -tall)) and not g.door_at(at + Vector2(0, tall)), "%s: the wall above and below is not" % tag)
			check(not g.door_at(Vector2(4, 4)) and not g.door_at(Vector2(size) - Vector2(4, 4)), "%s: the corners are not" % tag)
			for id in MenuBackdrop.HEROES:
				check(not g.door_at(g.hero_screen_point(id)), "%s: %s is not the door" % [tag, id])
	# the hover: a dead tube catching, then a buzz brighter than the live letters; off again, dark again
	eq(MenuBackdrop.door_gain(0.0), MenuBackdrop.DEAD_GAIN, "the first beat is dark")
	check(MenuBackdrop.door_gain(0.5) > 2.2, "then it burns hotter than the live letters (%.2f)" % MenuBackdrop.door_gain(0.5))
	g.set_door_hover(true)
	check(g.door_hovered, "hovered")
	await frames(40)
	check(g.door_glow() > 1.0, "the H sputters to life under the pointer (%.2f)" % g.door_glow())
	g.set_door_hover(false)
	near(g.door_glow(), MenuBackdrop.DEAD_GAIN, 0.001, "and goes dark when it leaves")
	vp.queue_free()
	await frames(2)


# --- 2. The main menu: hover and click ------------------------------------------------------------------------------

func _make_menu(scenes: Array) -> MainMenu:
	var menu: MainMenu = (load(Boot.MENU_SCENE) as PackedScene).instantiate()
	menu.use_mic = false
	menu.settings_path = TMP
	menu.apply_settings_live = false
	menu.change_scene = func(p: String) -> void: scenes.append(p)
	menu.quit_game = func() -> void: pass
	return menu


func _click(menu: MainMenu, at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	menu._unhandled_input(e)


func _move(menu: MainMenu, at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	menu._input(e)


func _check_menu() -> void:
	GAME.reset_flow()
	var scenes: Array = []
	var menu := _make_menu(scenes)
	add_child(menu)
	await frames(3)
	var g := menu.backdrop
	var at := g.door_screen_point()
	check(not menu.clipboard.get_global_rect().has_point(at), "the H is clear of the clipboard (%s)" % str(at))
	check(menu.garage_door_at(at), "the menu finds the door under the pointer")
	check(not menu.garage_door_at(menu.clipboard.get_global_rect().get_center()), "a click on the paper is the paper's")
	_move(menu, at)
	check(g.door_hovered, "the pointer on the H wakes it")
	eq(g.hovered, "", "no hero outlined")
	check(not bool(menu.get("_pointer_hand")), "the pointer stays an arrow (nothing gives it away)")
	_move(menu, Vector2(4, 4))
	check(not g.door_hovered, "off the H: dark again")
	# a sub-screen covers the garage
	menu.settings_button.pressed.emit()
	check(not menu.garage_door_at(at), "no door under the settings form")
	_click(menu, at)
	eq(scenes.size(), 0, "a click there does nothing")
	menu.show_screen("main")
	# the click: the game, with the gym's flag
	GAME.menu_args = PackedStringArray()
	_click(menu, at)
	eq(scenes, [Boot.GAME_SCENE], "a click on the H opens the game")
	check(GAME.menu_args.has(GymDev.FLAG), "... with the gym's flag (%s)" % str(GAME.menu_args))
	check(GAME.launch_args().has(GymDev.FLAG), "launch_args carries it as if typed on the command line")
	var opts := {}
	GymDev.parse(GAME.launch_args(), opts)
	check(bool(opts.get("gym", false)), "GymDev.parse reads it as --gym")
	eq(str(opts.get("spells", "")), GymDev.DEFAULT_SPELLS, "the gym's spells (the license is skipped)")
	eq(int(opts.get("seed", -1)), GymMap.SEED, "the gym's seed")
	check(not opts.has("gym_tour"), "no tour")
	eq(Session.offline_note, "", "solo, with no 'Steam not running' note")
	menu.queue_free()
	await frames(2)
	# a menu shown again forgets it (a job started from it is a job)
	var menu2 := _make_menu(scenes)
	add_child(menu2)
	await frames(2)
	eq(GAME.menu_args.size(), 0, "back on the menu: the flag is spent")
	menu2.queue_free()
	await frames(2)


# --- 3. Never in a crew --------------------------------------------------------------------------------------------

func _check_crew() -> void:
	var scenes: Array = []
	var menu := _make_menu(scenes)
	add_child(menu)
	await frames(3)
	var at := menu.backdrop.door_screen_point()
	# a crew opening (Start a job waiting for the Steam lobby)
	menu.set("_hosting_attempt", true)
	check(not menu.garage_door_at(at), "no door while a crew is opening")
	_move(menu, at)
	check(not menu.backdrop.door_hovered, "... and no sputter")
	_click(menu, at)
	check(not menu.open_gym(), "open_gym refuses")
	eq(scenes.size(), 0, "a click does nothing")
	menu.set("_hosting_attempt", false)
	# a real crew: an in-process host, and this menu joined to it
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
	menu.change_scene = func(p: String) -> void: scenes.append(p)
	Session.join_enet("127.0.0.1", PORT)
	if check(await _until(func() -> bool: return Session.online() and Session.crew().size() == 2, 5.0), "joined a crew"):
		# (a joined client goes on to the shared run's board by itself: that scene change is not the gym's)
		var before := scenes.size()
		menu.set("_entering", false)   # (so it is the crew itself, Session.online(), that locks the door)
		GAME.menu_args = PackedStringArray()
		check(not menu.garage_door_at(at), "in a crew: no door")
		_move(menu, at)
		check(not menu.backdrop.door_hovered, "in a crew: no sputter")
		_click(menu, at)
		check(not menu.open_gym(), "in a crew: open_gym refuses")
		eq(GAME.menu_args.size(), 0, "in a crew: no gym flag")
		eq(scenes.size(), before, "in a crew: the click opens nothing")
	Session.leave()
	host.leave()
	await frames(2)
	root.queue_free()
	menu.queue_free()
	Session.player_name = ""
	Session.telemetry_enabled = true
	Session.last_reason = ""
	await frames(3)


# --- 4. The game from the menu's flag alone --------------------------------------------------------------------------

func _check_game() -> void:
	MoveFeel.reset()
	GAME.reset_flow()
	Session.character_id = "rebar"
	GAME.menu_args = PackedStringArray([GymDev.FLAG])   # (what open_gym leaves; this process has no --gym on its command line)
	check(not OS.get_cmdline_user_args().has(GymDev.FLAG), "no --gym on the command line")
	var g: Node3D = load("res://scripts/app/dev/game_dev.gd").new()
	g.set("opts", {"no_mic": true})
	var scenes: Array = []
	g.set("scene_changer", func(p: String) -> void: scenes.append(p))
	add_child(g)
	var gym: GymDev = null
	for _i in 120:
		await frames(1)
		gym = g.get("gym")
		if gym != null:
			break
	if check(gym != null, "the menu's flag opens the gym (GymDev attached)"):
		await frames(3)
		check(gym.panel != null and gym.panel.visible, "its panel is up")
		var map: HexMap = g.get("map")
		check(map != null and GymMap.spots(map).has("arena"), "on GymMap's floor")
		var player: Hero = g.get("player")
		eq(player.kit_id if player != null else "", "rebar", "the player plays the menu's pick")
		eq(Array(player.spell_slots) if player != null else [], Array(GymDev.DEFAULT_SPELLS.split(",")), "with the gym's spells")
		check(not bool(g.get("_shared")), "solo")
		# Esc, then the pause menu's "Main menu": back to the menu, the flag forgotten
		g.call("_open_pause")
		var pause: PauseMenu = g.get("_pause")
		if check(pause != null, "the pause menu opens"):
			pause.main_menu.emit()
			eq(scenes, [Boot.MENU_SCENE], "its Main menu goes back to the main menu")
			eq(GAME.menu_args.size(), 0, "and the gym's flag is forgotten")
	get_tree().paused = false
	g.queue_free()
	await frames(3)
	GAME.reset_flow()
	MoveFeel.reset()
