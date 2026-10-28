extends TestCase
## HUD (with the party frame), spell picker, camera rig and the arena smoke test (all run headless).


func setup() -> void:
	var root := Node3D.new()
	add_child(root)
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 5):
		m.set_cell(c, 0)
	GameWorld.begin(m, root)

	# --- Picker: exactly 2 spells, third pick replaces the oldest.
	var picker := SpellPicker.new()
	picker.sign_hold = 0.0   # (submit as soon as it is signed)
	add_child(picker)
	var got: Array = []
	picker.picked.connect(func(s: Array[String]) -> void: got.append(s))
	check(not picker.confirm(), "cannot confirm with nothing chosen")
	picker.toggle("heal")
	check(not picker.confirm(), "cannot confirm with one spell")
	picker.toggle("corn")
	picker.toggle("armor")
	eq(picker.selected(), ["corn", "armor"] as Array[String], "third pick drops the oldest")
	picker.toggle("armor")
	picker.toggle("fireball")
	eq(picker.selected(), ["corn", "fireball"] as Array[String], "toggle off then on")
	check(picker.confirm(), "confirm with two")
	eq(got.size(), 1, "picked emitted once")
	eq(got[0], ["corn", "fireball"] as Array[String], "picked payload")
	picker.queue_free()

	# --- HUD binding + toasts (no crash, bars follow hp).
	var hero := HeroFactory.spawn_hero(Vector2i(0, 0), "Aria", Color.BLUE)
	hero.spell_slots = ["heal", "fireball"]
	var ally := HeroFactory.spawn_hero(Vector2i(1, 0), "Brom", Color.ORANGE)
	var hud := Hud.new()
	add_child(hud)
	var allies: Array[Hero] = [ally]
	hud.bind(hero, allies)
	hud.enable_console()
	hud.show_cast("heal", 0.92)
	hud.show_fizzle("hail", "too garbled")
	hud.show_unknown_spell("fireball")
	hud.show_cooldown("heal", 3.2)
	hud.set_trigger_word("pickle")
	eq(hud.trigger_word, "pickle", "trigger word stored")
	check(not hud.console.visible, "the type box is hidden until Enter")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	hud._unhandled_input(enter)
	check(hud.console.visible and hud.console.has_focus(), "Enter shows and focuses the type box")
	var typed: Array = []
	hud.console_submitted.connect(func(t: String) -> void: typed.append(t))
	hud.console.text_submitted.emit("cast heal")
	eq(typed, ["cast heal"], "console emits what was typed")
	await frames(1)
	check(not hud.console.visible, "and hides again once submitted")
	hero.apply_damage(30.0)
	await frames(3)
	eq(hud.party.views.size(), 2, "a party row per hero")
	check(bool(hud.party.views[0]["you"]), "yours first")
	near(float(hud.party.views[0]["hp"]) / float(hud.party.views[0]["max_hp"]), 0.7, 0.001, "your row follows hp")
	eq(str(hud.party.views[0]["name"]), SteamIdentity.player_name("Aria"), "your row: the Steam name, else the hero's")
	eq(str(hud.party.views[1]["name"]), "Brom", "an AI seat: the hero's name")
	eq(hud.party.show_followers, Hud.SHOW_FOLLOWERS, "the employee list follows the constant")
	check(hero.try_cast("heal", 1.0, hero.global_position), "cast for the card flash")
	await frames(3)
	check(hud._cards.size() == SpellComponents.SLOT_COUNT and hud._cards[0].flash > 0.0, "card flashes on cast")
	hud.queue_free()
	await frames(1)

	# --- Party frame: names, the order chip, down / dazed, the employee list.
	await _party_frame(hero, ally)

	# --- Camera rig: ortho, iso angles, follows, zooms.
	var rig := CameraRig.new()
	root.add_child(rig)
	rig.target = hero
	await frames(2)
	eq(rig.camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "orthographic")
	near(rig.rotation_degrees.y, 45.0, 0.01, "yaw 45")
	near(rig.camera.rotation_degrees.x, CameraRig.PITCH_DEG, 0.01, "pitch")
	rig.snap()
	near(rig.global_position.x, hero.global_position.x, 0.01, "snap to target")
	hero.global_position = Vector3(5, 0, 0)
	await frames(30)
	check(rig.global_position.x > 3.0, "follows target smoothly")
	var s0 := rig._zoom_target
	rig.zoom_by(2)
	check(rig._zoom_target < s0, "wheel up zooms in")
	rig.zoom_by(-100)
	near(rig._zoom_target, CameraRig.SIZE_MAX, 0.001, "zoom clamps")

	# --- Arena map: platform rules from the real layout.
	var am := Arena.build_map()
	eq(am.cell_transition(Vector2i(2, -1), Vector2i(3, -1)), HexMap.Move.OK, "+1 platform walks")
	eq(am.cell_transition(Vector2i(-3, 1), Vector2i(-4, 1)), HexMap.Move.CLIMB, "+2 platform climbs")
	eq(am.cell_transition(Vector2i(1, -5), Vector2i(0, -5)), HexMap.Move.BLOCKED, "+3 platform is blocked from the ground")
	check(am.find_path(Vector2i(0, 0), Vector2i(0, -6)).size() > 0, "+3 platform reachable by the stairs")
	check(Arena.build_terrain_mesh(am).get_surface_count() == 1, "terrain mesh builds")

	# --- Arena scene boots headless.
	var arena: Node = load("res://scenes/arena.tscn").instantiate()
	add_child(arena)
	await frames(10)
	check(arena.player != null and arena.hud != null and arena.picker != null, "arena built with the picker waiting")
	arena.picker.toggle("heal")
	arena.picker.toggle("armor")
	check(arena.picker.confirm(), "the arena's requisition signs")
	await frames(ceili(SpellPicker.SIGN_HOLD * Engine.physics_ticks_per_second) + 5)
	eq(arena.player.spell_slots, ["heal", "armor"] as Array[String], "picked spells land in the slots")
	check(GameWorld.team_actors(GameWorld.TEAM_MONSTERS).size() >= 4, "monsters spawned after picking")
	await frames(60)
	finish()


func _party_frame(hero: Hero, ally: Hero) -> void:
	# Names: a short one stays as it is; a long one shrinks (to NAME_MIN_SCALE at most), then is cut with an ellipsis.
	var font := PartyFrame.name_font()
	var w := PartyFrame.name_width(true)
	var short := PartyFrame.fit_name("Fox", font, 25, w)
	check(short["text"] == "Fox" and int(short["size"]) == 25 and not bool(short["cut"]), "a short name is left alone")
	for long_name in ["xX_TheLongestSteamNameEver_Xx", "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW", "ミッドナイト・キャスター・ジャパン",
			"Повелитель_Заклинаний_и_Огня", "김철수마법사길드장인"]:
		var fit := PartyFrame.fit_name(long_name, font, 25, w)
		check(font.get_string_size(fit["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, int(fit["size"])).x <= w + 0.5,
			"'%s' fits its row (%s)" % [long_name, fit["text"]])
		check(int(fit["size"]) >= int(floorf(25 * PartyFrame.NAME_MIN_SCALE)), "it never shrinks below the floor")
		check(not bool(fit["cut"]) or str(fit["text"]).ends_with("…"), "a cut name ends in an ellipsis")
	check(bool(PartyFrame.fit_name("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW", font, 25, w)["cut"]), "32 wide letters are cut")
	# The plates' round right ends start where the bar ends (the bar never runs into the curve), and their rows do not overlap.
	for sp: Dictionary in [PartyFrame.YOU, PartyFrame.ALLY]:
		var plate := PartyFrame.plate_rect(sp, 0.0)
		near(plate.end.x - plate.size.y * 0.5, float(sp["tx"]) + float(sp["bar_w"]), 0.01, "the plate's curve starts at the bar's right end")
		check(plate.size.y * 0.5 >= PartyFrame.PAD, "... at least PAD past it")
		check(plate.end.y - (float(sp["bar_y"]) + float(sp["bar_h"])) >= 8.0, "... and its bottom")
		check(float(sp["name_y"]) - float(sp["name"]) * 0.75 - plate.position.y >= 8.0, "... and the name's top")
	var frame := PartyFrame.new()
	add_child(frame)
	var none: Array[Hero] = [ally]
	var brain := HeroFactory.make_ally(ally, hero, false, 2.4)
	frame.bind(hero, none)
	await frames(2)
	eq(str(frame.views[1]["order"]), "follow", "an AI ally with no order: FOLLOW")
	eq(ally.order_state, "follow", "... its brain writes the hero's order state (what the host sends clients)")
	brain.give_order("attack", hero)
	await frames(2)
	eq(str(frame.views[1]["order"]), "attack", "... told attack: ATTACK")
	brain.give_order("go", hero, ally.global_position + Vector3(0.1, 0, 0))
	await frames(3)
	check(["go", "hold"].has(str(frame.views[1]["order"])), "... told go: GO, then HOLD once there")
	eq(str(frame.views[0]["order"]), "", "your own row has no chip without an order marker")
	OrderFx.marker(hero.global_position + Vector3(8, 0, 0), "Fox: go here", hero, Color.ORANGE, "go")
	await frames(2)
	eq(str(frame.views[0]["order"]), "go", "a crewmate's order to you shows GO while its marker stands")
	check(float(frame.views[0]["order_left"]) > 0.9 and float(frame.views[0]["order_left"]) <= 1.0, "... and drains from full")
	ally.set_player_name("Rosa")
	await frames(1)
	check(bool(frame.views[1]["human"]) and str(frame.views[1]["name"]) == "Rosa", "a seat a person plays: their name")
	eq(str(frame.views[1]["order"]), "", "... and no order chip (nobody orders a person)")
	ally.remove_meta(Net.NAME_META)
	# Employees: listed while they follow you, a short name, capped with "+N more", the list switches off.
	var gary: Employee = null
	var cells := Hex.range_cells(hero.current_cell(), 2)
	for i in 6:
		var e := Employee.spawn(cells[i + 1], {"style": "henchman" if i == 0 else "staff", "name": ["Gary (Henchman 1)",
			"Beatrice (sommelier)", "Mr. Bloom (accounts)", "Penny (concierge)", "Molly (IT support)", "Iris (intern)"][i]})
		e.order("follow", hero)
		if i == 0:
			gary = e
	await frames(2)
	eq(frame.follower_list.size(), 6, "every employee following you is listed")
	eq(frame.followers_shown(), PartyFrame.MAX_FOLLOWERS, "the list shows MAX_FOLLOWERS rows, the rest as +N more")
	eq(PartyInfo.short_name(gary.display_name), "Gary", "a short name")
	eq(PartyInfo.short_name("Mr. Bloom (accounts)"), "Mr. Bloom", "... titles kept")
	gary.order("attack", hero)
	await frames(1)
	eq(PartyInfo.employee_state(gary), "fight", "a henchman sent to fight: FIGHT")
	check(frame.follower_list.has(gary), "... and stays on your list while it fights")
	check(frame.frame_height() > frame.row_top(2), "the list adds height")
	frame.show_followers = false
	await frames(1)
	eq(frame.follower_list.size(), 0, "the list switches off")
	# Down and dazed read on the row.
	ally.apply_damage(ally.max_hp * 5.0)
	await frames(1)
	check(bool(frame.views[1]["down"]), "a downed ally: DOWN")
	hero.daze(2.0)
	await frames(1)
	check(bool(frame.views[0]["dazed"]), "you dazed: DAZED")
	frame.queue_free()
