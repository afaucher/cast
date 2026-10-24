extends TestCase
## The test gym (`--gym`, docs/design/test-gym.md; GymMap, GymDev, GymSpawns):
##   1. the map and plan hold every environment: the arena, the lobby's elevator, the course (steps, a 3-level drop, a +2
##      ledge, every floor material), the office rooms and their doors, the hellgate, the pool and the moat with their
##      sharks, the sewer cluster (water, sumps, the outfall, a sluice, the panel, the gator) and the lava cave (lava, the
##      bridge, the isle a crust reaches, the rim), priced props of both sites, explosives, decor of several themes, fog
##      spaces; and every place is reachable on foot from the start (the isle only over a crust); the build is the same twice
##   2. the spawn list covers every registry entry (a new monster kind, prop, style, spell or decor gets its button)
##   3. in the real game (GameDev with --gym, under the grounded_anim profile): the panel is up, one of each entry spawns and the world runs on (god mode on),
##      the tools work (AI off / on, clear, heal, the pack), the hit log counts a swing at a dummy, the experiments' pickers
##      switch the movement profile, the smoothing, the monsters' walk (old / new), their war cries (off / A / B / C) and
##      the elbow study's arms (old / ik),
##      the hallway packs come down the arena-lobby hall at the player, the War cry button makes the nearest monster of each
##      kind yell once, the slot picker and
##      infinite components keep a spell castable, and the player switches through every hero with the allies filling the rest

const GAME := preload("res://scripts/app/game.gd")


func setup() -> void:
	timeout_sec = 240.0
	_check_map()
	_check_registry()
	await _check_game()
	finish()


# --- 1. the map ----------------------------------------------------------------------------------------------------------

func _check_map() -> void:
	var m := GymMap.build_map()
	var run := ContractBoard.run_for_seed(GymMap.SEED)
	var p := GymMap.plan(m, run, 1)
	var m2 := GymMap.build_map()
	var p2 := GymMap.plan(m2, run, 1)
	check(NetFloor.map_text_of(m) == NetFloor.map_text_of(m2), "the gym builds the same twice")
	eq(p.decor.size(), p2.decor.size(), "the same plan twice")
	eq(m.cells_with_tag("start").size(), 1, "a start")
	eq(m.cells_with_tag("exit").size(), 1, "an exit (the elevator's landing)")
	check(not m.elevator.is_empty() and not p.elevator.is_empty(), "the freight elevator")
	check(m.midpoint_walls, "midpoint walls")
	for row: Array in GymMap.ROOMS:
		var tag := GymMap.tag_of(str(row[0]))
		check(p.rooms.has(tag) and (p.rooms[tag] as Array).size() > 6, "room %s (%s) is on the map" % [row[0], tag])
		eq(p.theme_of(tag), str(row[1]), "%s's theme" % row[0])
	check((p.rooms[GymMap.tag_of("arena")] as Array).size() >= 200, "the arena is big (%d cells)" % (p.rooms[GymMap.tag_of("arena")] as Array).size())
	# the course: steps, the top, a 3-level drop, a +2 ledge, every floor material
	var course := GymMap.tag_of("course")
	var levels := {}
	var drop3 := false
	var climb2 := false
	for c: Vector2i in (p.rooms[course] as Array):
		var cell: HexMap.Cell = m.get_cell(c)
		if cell.type == HexMap.Tile.WALL:
			continue
		levels[cell.level] = true
		for nb in Hex.neighbors(c):
			var o: HexMap.Cell = m.get_cell(nb)
			if o != null and o.type != HexMap.Tile.WALL and o.tag == course and m.is_walkable_cell(c) and m.is_walkable_cell(nb):
				drop3 = drop3 or cell.level - o.level == 3
				climb2 = climb2 or o.level - cell.level == 2
	for k in range(1, 4):
		check(levels.has(GymMap.LEVEL + k), "the course's step run reaches +%d" % k)
	check(drop3, "the course has a 3-level drop")
	check(climb2, "the course has a +2 ledge (a climb)")
	var mats := {}
	for c: Vector2i in m.cells:
		var cell: HexMap.Cell = m.cells[c]
		if cell.type != HexMap.Tile.WALL:
			mats[FloorMaterials.floor_of(cell.mat_id)] = true
	for i in FloorMaterials.FLOORS.size():
		check(mats.has(i), "floor material %d (%s) is on the floor" % [i, FloorMaterials.floor_name(i)])
	# doors and the gate
	check(p.doors.size() >= 8, "office doors (%d)" % p.doors.size())
	var service := 0
	for d: Dictionary in p.doors:
		service += 1 if str(d["style"]) == OfficeDoorModel.SERVICE else 0
	eq(service, 1, "the service stair's head has its service door")
	eq(p.gates.size(), 1, "a hellgate")
	eq(str(p.gates[0]["room"]), GymMap.tag_of(GymMap.GATE_ROOM), "the hellgate stands in the throne room")
	eq(p.employees.size(), 2, "the staff and a henchman")
	# props, explosives, decor
	var sites := {}
	for e: Dictionary in p.props:
		sites[PricedProp.TABLE[str(e["kind"])]["site"]] = true
	check(sites.has("bunker") and sites.has("lair"), "priced props of both sites (%s)" % str(sites.keys()))
	check(not p.hazards.is_empty(), "explosive props (%d)" % p.hazards.size())
	var decor_themes := {}
	for e: Dictionary in p.decor:
		decor_themes[p.theme_of(str(e["room"]))] = true
	check(decor_themes.size() >= 6, "decor in several themes (%s)" % str(decor_themes.keys()))
	for id in GymMap.BARE_ROOMS:
		var tag := GymMap.tag_of(id)
		for key in ["props", "hazards", "decor", "packages"]:
			for e: Dictionary in (p.get(key) as Array):
				check(str(e.get("room", "")) != tag, "nothing planned in the bare %s (%s)" % [id, key])
	# the pool and the moat, each with a shark
	var looks := {}
	for i in m.pools.size():
		var rec: Dictionary = m.pools[i]
		if not bool(rec.get("body", false)):
			looks[str(rec["look"])] = true
			check(str(rec.get("shark", "")) != "", "the %s has a shark" % rec["look"])
	check(looks.has(PoolGeo.LOOK_POOL) and looks.has(PoolGeo.LOOK_MOAT), "an indoor pool and a moat (%s)" % str(looks.keys()))
	eq(p.sharks.size(), 2, "two sharks")
	# the sewer
	var sw := SewerPlanner.record(m)
	check(not sw.is_empty(), "the sewer cluster is flooded")
	check((sw.get("sumps", []) as Array).size() == 3, "a sump in each sewer room")
	var outfall := false
	for e: Dictionary in (sw.get("ends", []) as Array):
		outfall = outfall or str(e["kind"]) == "outfall"
	check(outfall, "the source's outfall")
	eq((sw.get("gators", []) as Array).size(), 1, "a gator in its territory")
	var panel := false
	for e: Dictionary in p.props + p.hazards:
		panel = panel or str(e["kind"]) == "electrical_panel"
	check(panel, "the electrical panel (its live wire)")
	var sluice := false
	for e: Dictionary in p.decor:
		sluice = sluice or str(e["kind"]) == "sluice"
	check(sluice, "a sluice gate on the flooded narrow hall")
	var body: Dictionary = m.pools[int(sw["body"])]
	check((body["basin"] as Array).size() > 30, "wading water (%d cells)" % (body["basin"] as Array).size())
	# the lava cave
	check(m.lava.size() > 80, "a lava field (%d cells)" % m.lava.size())
	var isles: Array = m.cave["isles"]
	eq(isles.size(), 1, "an isle")
	var bridge := 0
	for c: Vector2i in (m.cave["rock"] as Array):
		bridge += 1 if m.get_cell(c).tag == "corridor" else 0
	check(bridge >= 12, "a two-wide bridge (%d cells)" % bridge)
	var rim := 0
	for c: Vector2i in m.lava:
		for nb in Hex.neighbors(c):
			var w: HexMap.Cell = m.get_cell(nb)
			if w != null and w.type == HexMap.Tile.WALL and w.level >= GymMap.LEVEL + GymMap.RIM_FRONT:
				rim += 1
	check(rim > 20, "the rim round the lava (%d wall faces)" % rim)
	# fog spaces: every room is one
	var fog := RoomFog.build(m)
	for row: Array in GymMap.ROOMS:
		check(fog.tags.has(GymMap.tag_of(str(row[0]))), "room %s is a fog space" % row[0])
	# reachable on foot from the start (the lava gone, as LavaField leaves it)
	for c: Vector2i in m.lava:
		m.remove_cell(c)
	var start: Vector2i = m.cells_with_tag("start")[0]
	var spots := GymMap.spots(m)
	for k: String in spots:
		var path := m.find_path(start, spots[k], true, 40000)
		check(not path.is_empty() and path[path.size() - 1] == spots[k], "%s %s is reachable from the start" % [k, spots[k]])
	var isle: Dictionary = isles[0]
	var to_isle := m.find_path(start, isle["center"], true, 40000)
	check(to_isle.is_empty() or to_isle[to_isle.size() - 1] != isle["center"], "the isle is not reachable on foot")
	var rock := {}
	for c: Vector2i in (m.cave["rock"] as Array):
		rock[c] = GymMap.LEVEL
	var isle_set := {}
	for c: Vector2i in (isle["cells"] as Array):
		isle_set[c] = m.get_cell(c).level
		rock.erase(c)
	var lava := {}
	for c: Vector2i in (m.cave["lava"] as Array):
		lava[c] = true
	var present := func(x: Vector2i) -> bool: return rock.has(x) or lava.has(x) or isle_set.has(x)
	var crust := CaveGen.crust_cells(Hex.to_world(isle["shore"]), CaveGen.crust_reach(), lava, present)
	check(CaveGen.crust_path(rock, isle_set, crust, isle["shore"], GymMap.LEVEL - 1), "a damp's crust from the shore reaches the isle")


# --- 2. the spawn list -------------------------------------------------------------------------------------------------

func _check_registry() -> void:
	var entries := GymSpawns.entries()
	var by := {}
	for e in entries:
		by["%s/%s" % [e["group"], e["key"]]] = e
	var ids := {}
	for e in entries:
		check(not ids.has(e["id"]), "entry ids are unique (%s)" % e["id"])
		ids[e["id"]] = true
	for kind: String in MonsterDefs.DEFS:
		check(by.has("monster/" + kind), "monster kind %s is in the spawn list" % kind)
	for kind: String in MonsterFactory.SCRIPTS:
		check(by.has("monster/" + kind) and str(by["monster/" + kind]["skip"]) == "", "factory kind %s has a button" % kind)
	for kind: String in PricedProp.TABLE:
		check(by.has("prop/" + kind) or by.has("hazard/" + kind), "priced prop %s is in the spawn list" % kind)
	for kind in PricedProp.hazard_kinds():
		check(by.has("hazard/" + kind), "explosive %s is a hazard" % kind)
	for style in EmployeeModel.STYLES:
		check(by.has("staff/" + style), "staff style %s" % style)
	for id: String in SpellBook.SPELLS:
		check(by.has("pickup/" + id), "spell %s's component is in the list" % id)
		if SpellBook.is_available(id):
			eq(str(by["pickup/" + id]["skip"]), "", "%s's component has a button" % id)
	for kind: String in RoomThemeDefs.DECOR:
		check(by.has("decor/" + kind), "decor %s" % kind)
	check(by.has("dummy/static") and by.has("dummy/walker"), "the training dummies")
	check(by.has("gate/hellgate") and by.has("gate/origin"), "the gates")


# --- 3. the gym in the game -------------------------------------------------------------------------------------------

func _check_game() -> void:
	MoveFeel.reset()   # (grounded_anim, the default: the switch re-kits a hero under the lean / squash pivot and its own hit area)
	eq(MoveFeel.active(), MoveFeel.GROUNDED_ANIM, "grounded_anim is the default profile")
	var g: Node3D = load("res://scripts/app/dev/game_dev.gd").new()
	g.set("opts", {"no_mic": true, "gym": true, "spells": GymDev.DEFAULT_SPELLS, "seed": GymMap.SEED})
	GAME.reset_flow()
	add_child(g)
	var gym: GymDev = null
	for _i in 120:
		await frames(1)
		gym = g.get("gym")
		if gym != null:
			break
	if not check(gym != null, "--gym attaches the gym's driver"):
		return
	await frames(5)
	check(gym.panel != null and gym.panel.visible, "the panel is up")
	eq(gym.staged.size(), GymDev.STAGE_DUMMIES, "the arena's training dummies")
	for d in gym.staged:
		check(d is TrainingDummy and (d as TrainingDummy).max_hp >= GymSpawns.DUMMY_HP, "a dummy with lots of HP")
	var player: Hero = g.get("player")
	# the hit log: the player swings at a dummy
	var dummy: TrainingDummy = gym.staged[0]
	player.global_position = dummy.global_position + Vector3(1.0, 0.0, 0.0)
	player.snap_to_ground()
	for _i in 30:
		player.melee(dummy.global_position - player.global_position)
		await frames(2)
		if int(gym.stats.totals("you")["hits"]) > 0:
			break
	check(int(gym.stats.totals("you")["hits"]) > 0, "the hit log counts the player's swing (%s)" % str(gym.stats.totals("you")))
	check(gym.stats.text().contains("You dealt"), "the readout")
	# the cast tell (CastTell): on the player, in colour (the default; no key changes it any more)
	var tell := g.get_node_or_null("CastTell") as CastTell
	check(tell != null and tell.hero == player, "the cast tell is on the player")
	eq(CastTell.mode, CastTell.COLOUR, "the cast tell is in colour")
	# the experiments (the panel's pickers, not keys): the movement profile and the judder smoothing, live
	var feel_pick := gym.panel.experiment("feel")
	var smooth_pick := gym.panel.experiment("smoothing")
	check(feel_pick != null and smooth_pick != null, "the panel has the movement and smoothing pickers")
	if feel_pick != null and smooth_pick != null:
		eq(feel_pick.get_item_text(feel_pick.selected), MoveFeel.GROUNDED_ANIM, "the movement picker shows grounded_anim")
		eq(smooth_pick.get_item_text(smooth_pick.selected), "off", "the smoothing picker shows off")
		var tag := g.get_node_or_null("MoveFeelTag") as MoveFeelTag
		feel_pick.item_selected.emit(MoveFeel.ORDER.find(MoveFeel.TODAY))
		eq(MoveFeel.active(), MoveFeel.TODAY, "picking today plays today")
		check(tag != null and tag.label.text == "movement: today", "the dev tag says so")
		smooth_pick.item_selected.emit(1)
		check(MoveFeel.interp, "picking on turns the smoothing on")
		eq(smooth_pick.get_item_text(smooth_pick.selected), "on", "the picker shows it")
		gym.set_experiment("smoothing", "off")
		check(not MoveFeel.interp, "and off again")
		gym.set_experiment("feel", MoveFeel.GROUNDED_ANIM)
		eq(MoveFeel.active(), MoveFeel.GROUNDED_ANIM, "back to grounded_anim")
		eq(feel_pick.get_item_text(feel_pick.selected), MoveFeel.GROUNDED_ANIM, "the picker follows")
	# the crowd variety's switches are gone (settled 2026-10-24: always on)
	for ex: String in ["path_jitter", "speed_spread", "size_jitter", "walk_unsync"]:
		check(gym.panel.experiment(ex) == null, "no %s picker any more" % ex)
	# spells: the slot picker and infinite components
	gym.set_slot(0, "corn")
	eq(player.slot_spell(0), "corn", "the slot picker puts corn in slot 1")
	g.call("_cast", "corn", 1.0, "test")
	await frames(3)
	eq(player.charges_of("corn"), SpellComponents.MAX_CHARGES, "infinite components: corn is full again")
	gym.set_toggle("no_cooldowns", true)
	await frames(2)
	eq(player.cooldown_left("corn"), 0.0, "cooldowns off")
	gym.set_toggle("no_cooldowns", false)
	# the character switch: every hero, the allies fill the rest
	var kits := HeroKit.ids()
	var slots := player.spell_slots.duplicate()
	for kit in kits + [kits[0]]:
		gym.switch_to(kit)
		await frames(3)
		eq(player.kit_id, kit, "the player is %s" % kit)
		check(g.get("player") == player, "the same hero node")
		eq(player.spell_slots, slots, "the spell slots are kept")
		var crew := {}
		for h: Hero in gym.heroes():
			crew[h.kit_id] = true
		eq(crew.size(), mini(kits.size(), gym.heroes().size()), "the allies fill the other heroes (%s)" % str(crew.keys()))
	gym.cycle(1)
	await frames(2)
	eq(player.kit_id, kits[1 % kits.size()], "F2 cycles to the next hero")
	# one of everything, god mode on (the crew must live through it)
	gym.set_toggle("god", true)
	var arena := GymMap.center_of("arena")
	var cells: Array[Vector2i] = []
	for c in Hex.range_cells(arena, 8):
		if GymSpawns.valid_cell(GameWorld.map, c):
			cells.append(c)
	cells.sort_custom(HexMap._cell_less)
	var made := 0
	var tried := 0
	var i := 0
	for e in GymSpawns.entries():
		if str(e["skip"]) != "":
			continue
		tried += 1
		var at := Hex.to_world(cells[(i * 7) % cells.size()])
		i += 1
		var out := gym.spawn(str(e["id"]), at)
		if check(not out.is_empty(), "%s spawns" % e["id"]):
			made += 1
		await frames(1)
	print("[gym] spawned %d of %d kinds" % [made, tried])
	await frames(90)
	check(not player.dead, "god mode: the player stands")
	gym.set_toggle("ai", false)
	await frames(20)
	var still := 0
	for a in GameWorld.actors():
		if a is Monster and not a.dead and not a.is_physics_processing():
			still += 1
	check(still > 5, "monster AI off: they stand (%d)" % still)
	gym.set_toggle("ai", true)
	# the hallway packs: twelve skeletons at the far end of the arena-lobby hall, the crew at its arena end, sent at the player
	gym.clear_monsters()
	await frames(2)
	var lk := GymDev.hall_link()
	var hall := gym.hall_pack(false)
	eq(hall.size(), GymDev.HALL_COUNT, "Hallway x12: twelve skeletons")
	check(Hex.distance(player.current_cell(), lk["door_a"] as Vector2i) <= 1, "the crew at the hall's arena end")
	var d0 := {}
	for m: Monster in hall:
		check(m.kind == "grunt" and Hex.distance(m.current_cell(), lk["door_b"] as Vector2i) <= 4, "a skeleton at the far end (%s)" % m.current_cell())
		check(m.state == Monster.State.CHASE and m.target == player, "... sent at the player")
		d0[m] = GameWorld.flat_distance(m.global_position, player.global_position)
	await frames(120)
	var closer := 0
	for m: Monster in hall:
		if is_instance_valid(m) and GameWorld.flat_distance(m.global_position, player.global_position) < float(d0[m]) - 3.0:
			closer += 1
	check(closer >= GymDev.HALL_COUNT - 2, "they come down the hall (%d of %d)" % [closer, hall.size()])
	gym.clear_monsters()
	await frames(2)
	var mix := gym.hall_pack(true)
	var kinds := {}
	for m: Monster in mix:
		kinds[m.kind] = int(kinds.get(m.kind, 0)) + 1
	eq(mix.size(), GymDev.HALL_COUNT, "Hallway mix: twelve")
	check(kinds.has("brute") and kinds.has("swarmer") and kinds.has("grunt"), "skeletons, a brute and imps (%s)" % str(kinds))
	# the monsters' walk and war cries (playtest feedback item 4, batch 2): two pickers, live, and the War cry button
	var walk_pick := gym.panel.experiment("walk")
	var cry_pick := gym.panel.experiment("war_cries")
	if check(walk_pick != null and cry_pick != null, "the panel has the monster walk and war cry pickers"):
		eq(walk_pick.get_item_text(walk_pick.selected), "new", "the monster walk picker shows new (the default)")
		eq(cry_pick.get_item_text(cry_pick.selected), "A", "the war cry picker shows A (the default)")
		walk_pick.item_selected.emit(0)
		check(not MonsterModel.active_walk, "picking old plays the old walk")
		gym.set_experiment("walk", "new")
		check(MonsterModel.active_walk, "and new again")
		eq(walk_pick.get_item_text(walk_pick.selected), "new", "the picker follows")
		cry_pick.item_selected.emit(Monster.CRY_PICKS.find("C"))
		eq(Monster.war_cry, "C", "picking C plays candidate C")
		eq(Monster.war_cry_cue("brute"), "cry_brute_c", "... the brute's C")
		cry_pick.item_selected.emit(Monster.CRY_PICKS.find("off"))
		eq(Monster.war_cry, "off", "and off")
		gym.set_experiment("war_cries", "A")
		eq(Monster.war_cry, "A", "back to A")
		eq(cry_pick.get_item_text(cry_pick.selected), "A", "the picker follows")
	# the elbow study (docs/design/animation-research.md, "Elbow IK study"): old / ik, live; the skeletons and Gasket rebuild
	# their arms on their next pose
	var elbow_pick := gym.panel.experiment("elbows")
	if check(elbow_pick != null, "the panel has the Elbows picker"):
		eq(elbow_pick.get_item_text(elbow_pick.selected), "old", "the Elbows picker shows old (the default)")
		check(not LowPolyModel.elbow_ik, "today's arms by default")
		var grunt: GruntModel = null
		for m: Monster in mix:
			if m.model is GruntModel:
				grunt = m.model as GruntModel
		var gasket: GasketModel = null
		for h: Hero in gym.heroes():
			if h.visual_override is GasketModel:
				gasket = h.visual_override as GasketModel
		elbow_pick.item_selected.emit(1)
		check(LowPolyModel.elbow_ik, "picking ik gives the IK arms")
		await frames(3)
		if check(grunt != null, "a skeleton in the mix"):
			check(grunt.has_part("fore_r") and grunt.get_part("weapon").get_parent() == grunt.get_part("fore_r"),
					"a skeleton's arms split at the elbow, the sword in the forearm's fist")
		if gasket != null:
			check(gasket.has_part("fore_l") and gasket.has_part("fore_r"), "Gasket's arms split at the elbow")
		gym.set_experiment("elbows", "old")
		check(not LowPolyModel.elbow_ik, "and old again")
		eq(elbow_pick.get_item_text(elbow_pick.selected), "old", "the picker follows")
		await frames(3)
		if grunt != null:
			check(not grunt.has_part("fore_r") and grunt.get_part("weapon").get_parent() == grunt.get_part("arm_r"),
					"the skeleton's one-piece arms are back")
	var before := {}
	for m: Monster in mix:
		before[m] = m.cries
	gym.act("cry")
	var yelled := {}
	for m: Monster in mix:
		if m.cries > int(before[m]):
			yelled[m.kind] = int(yelled.get(m.kind, 0)) + m.cries - int(before[m])
	eq(yelled, {"brute": 1, "grunt": 1, "swarmer": 1}, "the War cry button: one monster of each kind yells once")
	check(gym.panel.status_label.text.begins_with("war cry (A)"), "the status line says so (%s)" % gym.panel.status_label.text)
	gym.act("pack")
	await frames(10)
	var n := gym.clear_monsters()
	check(n > 5, "clear monsters (%d)" % n)
	await frames(2)
	var site: SiteBuilder.Site = g.get("_site")
	var fauna := {}
	for f in site.sharks:
		fauna[f] = true
	for f in site.gators:
		fauna[f] = true
	for f in site.jockeys:
		fauna[f] = true
	for a in GameWorld.actors():
		if a is Monster and not a.is_queued_for_deletion():
			check(fauna.has(a), "only the gym's own fauna is left (%s)" % a.name)
	gym.act("clear_spawned")
	gym.set_toggle("god", false)
	player.apply_damage(30.0, null)
	gym.heal_crew()
	eq(player.hp, player.max_hp, "heal crew")
	gym.set_toggle("areas", true)
	await frames(3)
	check(gym.overlay.visible, "the hit areas show")
	g.queue_free()
	await frames(2)
	GAME.reset_flow()
	MoveFeel.reset()
	MonsterModel.active_walk = true
	Monster.war_cry = "A"
	LowPolyModel.elbow_ik = false

