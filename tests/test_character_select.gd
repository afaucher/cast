extends TestCase
## The character select (user, 2026-10-19): clicking a hero in the main menu's garage picks it (hover outlines it), FORM 31
## the personnel file shows that hero's HeroKit numbers, the pick is saved and comes back, the keyboard reaches it through
## the card's NAME line; solo, seat 1 is the pick and the AI seats are the other two (CrewSeats); online, the roster carries
## the pick and the AI seats fill with the heroes nobody human picked.

const GAME := preload("res://scripts/app/game.gd")
const TMP := "user://test_character_select_settings.cfg"
const PORT := 28781


func setup() -> void:
	timeout_sec = 150.0
	_rm(TMP)
	_check_crew_seats()
	_check_card_numbers()
	_check_settings()
	await _check_garage_picking()
	await _check_persistence()
	await _check_keyboard()
	await _check_solo_seats()
	await _check_online()
	_rm(TMP)
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


# --- Seats as data -------------------------------------------------------------------------------------

func _check_crew_seats() -> void:
	eq(CrewSeats.fill({1: "wick"}), {1: "wick", 2: "rebar", 3: "gasket"}, "solo Wick: AI Rebar and Gasket (the crew as before)")
	eq(CrewSeats.fill({1: "rebar"}), {1: "rebar", 2: "wick", 3: "gasket"}, "solo Rebar: AI Wick and Gasket")
	eq(CrewSeats.fill({1: "gasket"}), {1: "gasket", 2: "rebar", 3: "wick"}, "solo Gasket: AI Rebar and Wick")
	eq(CrewSeats.fill({1: "wick", 2: "wick"}), {1: "wick", 2: "wick", 3: "gasket"}, "two Wicks (allowed): the AI is Gasket")
	eq(CrewSeats.fill({1: "rebar", 2: "gasket"}), {1: "rebar", 2: "gasket", 3: "wick"}, "Rebar and Gasket taken: the AI is the one left, Wick")
	eq(CrewSeats.fill({1: "gasket", 3: "rebar"}), {1: "gasket", 2: "wick", 3: "rebar"}, "a human in seat 3: seat 2's AI takes the free hero")
	eq(CrewSeats.fill({1: "wick", 2: "rebar", 3: "gasket"}), {1: "wick", 2: "rebar", 3: "gasket"}, "a full crew of people: no AI")
	for pick in HeroKit.ids():
		var seats := CrewSeats.fill({1: pick})
		var heroes: Array = seats.values()
		heroes.sort()
		eq(heroes, ["gasket", "rebar", "wick"], "solo %s: the crew is the three heroes, each once" % pick)
	# A seat its player leaves: the AI plays a hero nobody else plays, the same one the next floor gives that seat.
	eq(CrewSeats.ai_for(2, ["rebar", "gasket"]), "wick", "Rebar host, Gasket AI: seat 2 goes back to Wick")
	eq(CrewSeats.ai_for(3, ["wick", "wick"]), "gasket", "two Wicks: seat 3 goes back to Gasket")
	eq(CrewSeats.ai_for(2, ["wick", "gasket"]), "rebar", "seat 2's own hero when it is free")
	eq(CrewSeats.ai_for(2, ["rebar", "gasket", "wick"]), "rebar", "every hero taken: the seat's own (a duplicate)")
	eq(CrewSeats.fill({1: "rebar"})[2], CrewSeats.ai_for(2, ["rebar", "gasket"]), "a drop and the next floor agree")


# --- FORM 31: the numbers are HeroKit's ------------------------------------------------------------------

func _check_card_numbers() -> void:
	for id in HeroKit.ids():
		var kit := HeroKit.get_kit(id)
		var f := PersonnelFile.facts(kit)
		eq(f["hp"], "%d" % roundi(kit.max_hp), "%s: HP from the kit" % id)
		check(str(f["primary"]).begins_with(kit.primary_name) and str(f["primary"]).contains("%d dmg" % roundi(kit.melee_damage)),
			"%s: the primary's name and damage from the kit (%s)" % [id, f["primary"]])
		check(str(f["speed"]).contains(PersonnelFile._num(kit.melee_cooldown)), "%s: the primary's speed (%s)" % [id, f["speed"]])
		check(str(f["secondary"]).to_lower().begins_with(kit.secondary_kind), "%s: the secondary (%s)" % [id, f["secondary"]])
		check(str(f["role"]) != "", "%s has a role line" % id)
		var b := PersonnelFile.bars(id)
		for k: String in b:
			check(int(b[k]) >= 0 and int(b[k]) <= PersonnelFile.BOXES, "%s: %s bar in range (%d)" % [id, k, int(b[k])])
	eq(PersonnelFile.facts(HeroKit.get_kit("rebar"))["primary"], "Slam fist, 15 dmg", "Rebar's punch is the kit's 15 (2026-10-19)")
	eq(PersonnelFile.facts(HeroKit.get_kit("rebar"))["weight"], "Immovable", "Rebar is immovable (shove_mult 0)")
	eq(PersonnelFile.facts(HeroKit.get_kit("wick"))["climb"], "+2 at 60% pace", "Wick climbs at the kit's 0.6")
	eq(PersonnelFile.bars("rebar")["hp"], PersonnelFile.BOXES, "the most HP fills the scale (Rebar)")
	eq(PersonnelFile.bars("gasket")["primary"], PersonnelFile.BOXES, "the hardest hit fills it (Gasket)")
	eq(PersonnelFile.bars("wick")["speed"], PersonnelFile.BOXES, "the fastest swing fills it (Wick)")
	eq(PersonnelFile.bars("rebar")["climb"], 0, "Rebar can't climb: no boxes")
	eq(PersonnelFile.bars("rebar")["weight"], PersonnelFile.BOXES, "immovable: all ten")
	check(PersonnelFile.bars("wick")["weight"] < PersonnelFile.bars("gasket")["weight"], "Wick is lighter than Gasket")
	check(PersonnelFile.bars("wick")["hp"] < PersonnelFile.bars("gasket")["hp"], "Wick has less HP than Gasket")
	# Typed on the card, in one typewriter, and nothing about keys.
	var card := PersonnelFile.new()
	add_child(card)
	check(card.show_hero("gasket"), "the card types up Gasket")
	eq(card.name_row.value, "GASKET", "the name is typed")
	var text := " ".join(card.typed_text())
	check(text.contains("Hammer, 28 dmg") and text.contains("120"), "the card carries the kit's numbers (%s)" % text)
	for bad in ["[", "press", "click", "Enter", "Left", "Right"]:
		check(not text.contains(bad), "nothing on the card names a key or explains the game (%s)" % bad)
	check(not card.show_hero("sir_rattles"), "a hero without a kit is refused")
	eq(card.hero_id, "gasket", "and the card keeps what it had")
	eq(card.header.form_no_label.text, PersonnelFile.FORM_NO, "FORM 31")
	card.queue_free()


func _check_settings() -> void:
	eq(GameSettings.load_settings(TMP)["character"], NetSession.DEFAULT_CHARACTER, "no pick saved yet: Wick")
	GameSettings.save_settings({"character": "rebar"}, TMP)
	eq(GameSettings.load_settings(TMP)["character"], "rebar", "a saved pick reloads")
	GameSettings.save_settings({"character": "sir_rattles"}, TMP)
	eq(GameSettings.load_settings(TMP)["character"], NetSession.DEFAULT_CHARACTER, "an unknown hero falls back to Wick")
	eq(Boot.hero_pick(PackedStringArray([]), "gasket"), "gasket", "Boot: the saved pick")
	eq(Boot.hero_pick(PackedStringArray(["--hero", "rebar"]), "gasket"), "rebar", "Boot: --hero wins for the run")
	eq(Boot.hero_pick(PackedStringArray(["--backdrop-hero", "wick"]), "gasket"), "wick", "Boot: --backdrop-hero too")
	eq(Boot.hero_pick(PackedStringArray(["--hero", "bogus"]), "nope"), NetSession.DEFAULT_CHARACTER, "Boot: nonsense is Wick")
	_rm(TMP)


# --- The garage ----------------------------------------------------------------------------------------

func _make_menu() -> MainMenu:
	var menu: MainMenu = (load(Boot.MENU_SCENE) as PackedScene).instantiate()
	menu.use_mic = false
	menu.settings_path = TMP
	menu.apply_settings_live = false
	menu.change_scene = func(_p: String) -> void: pass
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


func _settle(menu: MainMenu) -> void:
	for i in 240:
		if not menu.backdrop.is_stepping():
			break
		await frames(1)


func _check_garage_picking() -> void:
	var menu := _make_menu()
	add_child(menu)
	await frames(3)
	var g := menu.backdrop
	eq(Session.local_character(), "wick", "a fresh menu: Wick")
	eq(g.featured_hero, "wick", "Wick in front")
	check(menu.card == null, "no personnel file under the clipboard (user, 2026-10-19: removed for now)")
	var canvas := menu.main_panel.get_global_rect()
	check(menu.clipboard.get_global_rect().end.y <= canvas.end.y + 0.5 and menu.clipboard.get_global_rect().position.y >= canvas.position.y - 0.5,
		"the clipboard fits the canvas (clipboard %s, canvas %s)" % [str(menu.clipboard.get_global_rect()), str(canvas)])
	var sheet: Control = menu.clipboard.content
	check(sheet.get_combined_minimum_size().y <= menu.clipboard.size.y - 59.0, "the work order fits its shorter board (%.0f of %.0f)"
		% [sheet.get_combined_minimum_size().y, menu.clipboard.size.y - 60.0])
	# Nothing in the empty wall.
	eq(menu.garage_hero_at(Vector2(1560, 40)), "", "no hero up on the back wall")
	eq(menu.garage_hero_at(menu.clipboard.get_global_rect().get_center()), "", "a click on the paper is the paper's")
	for id in ["rebar", "gasket", "wick", "rebar"]:
		var at := g.hero_screen_point(id)
		check(at.x > 0.0 and at.y > 0.0, "%s is on screen (%s)" % [id, str(at)])
		eq(menu.garage_hero_at(at), id, "the ray finds %s under its own figure" % id)
		_move(menu, at)
		eq(g.hovered, id, "hovering %s outlines it" % id)
		check(g.is_outlined(id), "%s's outline is on" % id)
		_click(menu, at)
		eq(Session.character_id, id, "a click picks %s" % id)
		eq(g.featured_hero, id, "%s steps to the front" % id)
		eq(GameSettings.load_settings(TMP)["character"], id, "the pick is saved")
		await _settle(menu)
		check(not g.is_stepping(), "the crew has walked to its new spots")
		var cam: Vector3 = g.camera.global_position
		for other in MenuBackdrop.HEROES:
			if other != id:
				check(g.hero_model(id).global_position.distance_to(cam) < g.hero_model(other).global_position.distance_to(cam) - 1.0,
					"%s now stands nearer the camera than %s" % [id, other])
		_move(menu, Vector2(1560, 40))
		eq(g.hovered, "", "off the heroes: no outline")
		check(not g.is_outlined(id), "the outline comes off %s" % id)
	# The pick is locked while a crew is opening or open (the roster already has it).
	menu.set("_hosting_attempt", true)
	check(not menu.pick_hero("wick"), "no pick while a crew is opening")
	eq(Session.character_id, "rebar", "the pick stays")
	menu.set("_hosting_attempt", false)
	# Sub-screens cover the garage.
	menu.settings_button.pressed.emit()
	eq(menu.garage_hero_at(g.hero_screen_point("gasket")), "", "no picking under the settings form")
	menu._unhandled_input(_esc())
	await after_void()
	eq(menu.screen, "main", "back on the menu")
	menu.queue_free()
	await frames(2)


func _esc() -> InputEventAction:
	var e := InputEventAction.new()
	e.action = "pause"
	e.pressed = true
	return e


func _check_persistence() -> void:
	Session.character_id = ""   # (a fresh process: Boot would load it; the menu reads its own settings file)
	var menu := _make_menu()
	add_child(menu)
	await frames(3)
	eq(Session.character_id, "rebar", "the saved pick comes back with the menu")
	eq(menu.backdrop.featured_hero, "rebar", "Rebar is in front again")
	menu.queue_free()
	await frames(2)


func _key(action: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	return e


func _check_keyboard() -> void:
	var menu := _make_menu()
	add_child(menu)
	await frames(3)
	eq(menu.quit_button.find_valid_focus_neighbor(SIDE_BOTTOM), menu.start_button, "Down from Quit wraps back to Start a job")
	menu.start_button.grab_focus()
	await frames(1)
	var hints := " ".join(_hint_text(menu.keys))
	check(hints.contains("LEFT") and hints.contains("RIGHT"), "the key strip (off the paper) says Left / Right picks a hero (%s)" % hints)
	var ids := HeroKit.ids()
	var start := ids.find(Session.local_character())
	menu._unhandled_input(_key("ui_right"))
	eq(Session.character_id, ids[(start + 1) % ids.size()], "Right steps to the next hero")
	menu._unhandled_input(_key("ui_left"))
	eq(Session.character_id, ids[start], "Left steps back")
	eq(menu.backdrop.featured_hero, Session.character_id, "the garage follows")
	eq(menu.screen, "main", "and the menu stays put")
	menu.pick_hero("rebar")
	menu.queue_free()
	await frames(2)


func _hint_text(keys: KeyHints) -> PackedStringArray:
	var out := PackedStringArray()
	for l in keys.find_children("*", "Label", true, false):
		out.append((l as Label).text.to_upper())
	return out


# --- Solo seats in the game ------------------------------------------------------------------------------

func _check_solo_seats() -> void:
	for pick in ["rebar", "gasket", "wick"]:
		Session.character_id = pick
		var g: Node3D = load("res://scripts/app/game.gd").new()
		g.set("opts", {"no_mic": true, "spells": "heal,corn", "contract": 1, "seed": 5})
		GAME.reset_flow()
		add_child(g)
		await frames(8)
		var seats: Dictionary = g.get("heroes_by_seat")
		var player: Hero = g.get("player")
		var expect := CrewSeats.fill({1: pick})
		eq(seats.size(), 3, "%s: three seats" % pick)
		check(seats.get(1) == player, "%s: seat 1 is the player" % pick)
		for seat: int in [1, 2, 3]:
			var h: Hero = seats.get(seat)
			eq(h.kit_id if h != null else "", str(expect[seat]), "%s: seat %d plays %s" % [pick, seat, str(expect[seat])])
		eq(player.kit_id, pick, "%s: you play the pick" % pick)
		var kits: Array = []
		for seat: int in seats:
			kits.append((seats[seat] as Hero).kit_id)
		kits.sort()
		eq(kits, ["gasket", "rebar", "wick"], "%s: the AI crew is the other two" % pick)
		for seat: int in [2, 3]:
			var h: Hero = seats[seat]
			var brain := h.get_node_or_null("AllyBrain") as AllyBrain
			check(brain != null and brain.leader == player, "%s: seat %d is an AI ally following you" % [pick, seat])
			if brain != null:
				eq(brain.prefers_ranged, h.secondary_kind == "arrow", "%s: AI %s keeps its distance only with a bow" % [pick, h.kit_id])
		var hud: Hud = g.get("hud")
		check(hud != null, "%s: the HUD is up" % pick)
		g.queue_free()
		await frames(3)
	GAME.reset_flow()
	Session.character_id = ""


# --- Online: the roster carries the pick; AI seats fill with the heroes nobody picked ---------------------

func _check_online() -> void:
	var root := Node.new()
	root.name = "HostRoot"
	add_child(root)
	get_tree().set_multiplayer(SceneMultiplayer.new(), root.get_path())
	var host := NetSession.new()
	host.name = "Session"
	host.telemetry_enabled = false
	host.player_name = "Hana"
	host.character_id = "rebar"
	root.add_child(host)
	check(host.host_enet(PORT), "an in-process host playing Rebar")
	Session.telemetry_enabled = false
	Session.player_name = "Tess"
	Session.character_id = "gasket"
	Session.join_enet("127.0.0.1", PORT)
	if check(await _until(func() -> bool: return Session.online() and Session.crew().size() == 2, 5.0), "the client joins as Gasket"):
		var on_host := {}
		for e: Dictionary in host.crew():
			on_host[int(e["seat"])] = str(e["character"])
		eq(on_host, {1: "rebar", 2: "gasket"}, "the host's roster carries both picks")
		var on_client := {}
		for e: Dictionary in Session.crew():
			on_client[int(e["seat"])] = str(e["character"])
		eq(on_client, on_host, "and so does the roster the client was sent")
		# The seat table a shared floor is built with (game.gd _crew_seats, the client's view of the same roster).
		var g: Node3D = load("res://scripts/app/game.gd").new()
		g.set("_shared", true)
		var table: Array[Dictionary] = g.call("_crew_seats")
		var by_seat := {}
		for s: Dictionary in table:
			by_seat[int(s["seat"])] = s
		eq(str(by_seat[1]["character"]), "rebar", "seat 1: the host's Rebar")
		eq(str(by_seat[2]["character"]), "gasket", "seat 2: the client's Gasket")
		check(bool(by_seat[2]["local"]), "seat 2 is this machine's")
		eq(str(by_seat[3]["character"]), "wick", "seat 3: the AI plays the hero nobody picked, Wick")
		eq(int(by_seat[3]["peer"]), 0, "seat 3 is the AI's")
		# If the client leaves, its seat goes back to the AI as the hero nobody else plays (Gasket again).
		eq(GAME._ai_character(2, table), "gasket", "a drop from seat 2 gives the AI Gasket (Rebar and Wick are in the other seats)")
		g.free()
	Session.leave()
	host.leave()
	await frames(2)
	root.queue_free()
	Session.player_name = ""
	Session.telemetry_enabled = true
	Session.last_reason = ""
	Session.character_id = ""
	await frames(3)
