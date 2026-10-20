extends MonsterTestBase
## The goblin scout (docs/design/goblin-scout.md, monster-awareness.md step 2): his clock ("!" 0.6 s, light 1.4 s, fuse
## 1.6 s), the stops (killed while lighting: silent; killed with the fuse lit: the rockets still go up; soaked: no light
## or a dud; shoved or rooted: the light starts over; fire: an instant volley), the alarm (radius 18, the 12 nearest,
## ALERT toward where he saw the crew, a dormant hellgate within 18 wakes, a second scout runs over), the restock, his
## corridor routes on real floors (1-2 a floor, deterministic, inside the plan's time) and the combat log rows.

const GOBLIN := "goblin"


func _init() -> void:
	timeout_sec = 300.0


func setup() -> void:
	MonsterSenses.restless_override = 0.0
	await _check_clock()
	await _check_silent_kill()
	await _check_late_kill()
	await _check_damp()
	await _check_interrupts()
	await _check_fire()
	await _check_alarm()
	await _check_gate_wake()
	await _check_second_scout()
	await _check_restock()
	_check_floors()
	await _check_log()
	MonsterSenses.restless_override = -1.0
	finish()


## A goblin at the origin looking east (+X) and a hero `dist_hex` hexes east of him: in his cone.
func _scene(dist_hex: int = 5, radius: int = 14) -> Array:
	new_world(flat_map(radius))
	var hero := add_hero(Vector2i(dist_hex, 0))
	var g = MonsterFactory.spawn(GOBLIN, Vector2i(0, 0))
	g.set_spawn_facing(Vector3.RIGHT)
	return [g, hero]


func _phase_times(g: Variant, frames_n: int) -> Dictionary:
	var out := {}
	for _f in frames_n:
		await get_tree().physics_frame
		if not is_instance_valid(g):
			break
		var p: int = g.scout_phase
		if not out.has(p):
			out[p] = GameWorld.time
		if g.dead:
			break
	return out


func _fireworks() -> int:
	var n := 0
	for c in world.get_children():
		if c is FireworksFx:
			n += 1
	return n


# --- The clock -----------------------------------------------------------------------------------------------------------

func _check_clock() -> void:
	var s := _scene(5)                                   # 8.7 away, in his cone
	var g = s[0]
	var t0 := GameWorld.time
	var times: Dictionary = await _phase_times(g, 60 * 6)
	var P: Dictionary = g.Phase
	check(times.has(P["TELL"]) and times.has(P["LIGHT"]) and times.has(P["FUSE"]) and times.has(P["HIDE"]), "patrol -> tell -> light -> fuse -> hide (%s)" % str(times))
	if not (times.has(P["TELL"]) and times.has(P["LIGHT"]) and times.has(P["FUSE"]) and times.has(P["HIDE"])):
		return
	near(float(times[P["TELL"]]) - t0, 0.35, 0.06, "he is sure after 0.35 s of sight")
	near(float(times[P["LIGHT"]]) - float(times[P["TELL"]]), 0.6, 0.04, "the \"!\" lasts 0.6 s")
	near(float(times[P["FUSE"]]) - float(times[P["LIGHT"]]), 1.4, 0.04, "striking a light takes 1.4 s")
	near(float(times[P["HIDE"]]) - float(times[P["FUSE"]]), 1.6, 0.04, "the fuse burns 1.6 s")
	eq(g.volleys, 1, "one volley")
	check(not g.loaded, "the rack is empty")
	check(_fireworks() == 1, "the fireworks are in the world")
	eq(g.state, Monster.State.SEARCH, "hiding rides SEARCH on the wire")
	# Behind him the same hero is not seen (all-round sight is only 3).
	new_world(flat_map(14))
	add_hero(Vector2i(5, 0))
	g = MonsterFactory.spawn(GOBLIN, Vector2i(0, 0))
	g.set_spawn_facing(Vector3.LEFT)
	g._glance_t = 99.0
	await frames(90)
	eq(g.scout_phase, P["PATROL"], "a hero behind him at 8.7 goes unseen")
	# A hit counts as being spotted.
	g.apply_damage(1.0, world.get_child(0))
	eq(g.scout_phase, P["TELL"], "a hit: the \"!\"")


# --- Stops ---------------------------------------------------------------------------------------------------------------

func _check_silent_kill() -> void:
	var s := _scene(5)
	var g = s[0]
	var hero: Actor = s[1]
	var witness := MonsterFactory.spawn("grunt", Vector2i(-7, 0))   # 12.1 behind him: the alarm would reach it (the hit's shout, 10, not)
	witness.set_spawn_facing(Vector3.LEFT)
	var lit := await wait_until(func() -> bool: return g.scout_phase == g.Phase.LIGHT, 120)
	check(lit, "he is lighting")
	await frames(30)
	g.apply_damage(100.0, hero)
	eq(g.volleys, 0, "killed while lighting: no volley")
	await frames(240)
	eq(_fireworks(), 0, "... no fireworks")
	check(witness.state != Monster.State.ALERT, "... and no alarm (the witness is %s)" % witness.state_name())


func _check_late_kill() -> void:
	var s := _scene(5)
	var g = s[0]
	var hero: Actor = s[1]
	var witness := MonsterFactory.spawn("grunt", Vector2i(-7, 0))
	witness.set_spawn_facing(Vector3.LEFT)
	var fuse := await wait_until(func() -> bool: return g.scout_phase == g.Phase.FUSE, 240)
	check(fuse, "the fuse is lit")
	g.apply_damage(100.0, hero)
	check(g.dead, "killed with the fuse lit")
	eq(g.volleys, 1, "the rockets still go up (user, 2026-10-18)")
	eq(_fireworks(), 1, "... fireworks in the world")
	eq(witness.state, Monster.State.ALERT, "... and the alarm sounds")


func _check_damp() -> void:
	# Soaked while lighting: no light, he runs and yells (a room shout), no volley.
	var s := _scene(5)
	var g = s[0]
	var lit := await wait_until(func() -> bool: return g.scout_phase == g.Phase.LIGHT, 120)
	check(lit, "lighting")
	Burning.soak(g, 15.0)
	await frames(2)
	eq(g.scout_phase, g.Phase.RUN, "soaked before the fuse: he runs instead")
	await frames(60 * 10)
	eq(g.volleys, 0, "no fireworks from a soaked scout")
	check(g.loaded, "the rack stays loaded (only damp)")
	# Soaked with the fuse lit: a dud.
	s = _scene(5)
	g = s[0]
	var fuse := await wait_until(func() -> bool: return g.scout_phase == g.Phase.FUSE, 240)
	check(fuse, "the fuse is lit")
	Burning.soak(g, 15.0)
	await frames(3)
	eq(g.volleys, 0, "a soaked fuse: a dud, no volley")
	check(not g.loaded, "the wet rockets are spent")
	eq(_fireworks(), 0, "no fireworks")
	# Soaked, then killed with the fuse lit: nothing goes up.
	s = _scene(5)
	g = s[0]
	fuse = await wait_until(func() -> bool: return g.scout_phase == g.Phase.FUSE, 240)
	check(fuse, "the fuse is lit")
	Burning.soak(g, 15.0)                                # (a soak and a kill on the same frame)
	g.apply_damage(100.0, s[1])
	eq(_fireworks(), 0, "a soaked rack on a dead scout stays quiet")


func _check_interrupts() -> void:
	# A shove while lighting: he starts over.
	var s := _scene(5)
	var g = s[0]
	await wait_until(func() -> bool: return g.scout_phase == g.Phase.LIGHT, 120)
	await frames(60)                                     # 1 s into the 1.4 s light
	g.shove(Vector3.LEFT, 1.0, s[1])
	check(g._light_t < 0.05, "a shove drops the match")
	var t_free := -1.0
	await wait_until(func() -> bool: return not g.is_helpless(), 60)
	t_free = GameWorld.time
	var fuse := await wait_until(func() -> bool: return g.scout_phase == g.Phase.FUSE, 200)
	check(fuse and GameWorld.time - t_free >= 1.35, "... and lights from the start once free (%.2f s)" % (GameWorld.time - t_free))
	# Rooted (vines): no light while rooted.
	s = _scene(5)
	g = s[0]
	await wait_until(func() -> bool: return g.scout_phase == g.Phase.LIGHT, 120)
	g.set_modifier("vines", 0.0, 2.0, Actor.STAT_ROOT)
	await frames(100)
	eq(g.scout_phase, g.Phase.LIGHT, "rooted: still trying to light after 1.7 s")
	check(g._light_t < 0.05, "... with no progress (the vines bind his match arm)")
	fuse = await wait_until(func() -> bool: return g.scout_phase == g.Phase.FUSE, 200)
	check(fuse, "he lights once the vines let go")


func _check_fire() -> void:
	var s := _scene(9)                                   # 15.6 away: unseen, on patrol
	var g = s[0]
	await frames(10)
	eq(g.scout_phase, g.Phase.PATROL, "patrolling")
	MonsterSenses.fire_at(g.global_position, 1.5)        # a fireball's blast
	eq(g.volleys, 1, "fire lights the rack: an instant volley")
	# A soaked scout fizzles a fireball (no volley).
	s = _scene(9)
	g = s[0]
	await frames(5)
	Burning.soak(g, 15.0)
	MonsterSenses.fire_at(g.global_position, 1.5)
	eq(g.volleys, 0, "damp, then fire: no volley")


# --- The alarm -----------------------------------------------------------------------------------------------------------

func _check_alarm() -> void:
	new_world(flat_map(16))
	var hero := add_hero(Vector2i(14, 0))
	var g = MonsterFactory.spawn(GOBLIN, Vector2i(0, 0))
	g.aggro_range = 0.001
	var near_one := MonsterFactory.spawn("grunt", Vector2i(-9, 0))      # 15.6 from F
	var far_one := MonsterFactory.spawn("grunt", Vector2i(-11, 0))      # 19.1 from F
	var chasing := MonsterFactory.spawn("grunt", Vector2i(-8, 2))
	for m in [near_one, far_one, chasing]:
		m.aggro_range = 0.001                                           # (they see nothing; not frozen)
	await frames(2)
	chasing.state = Monster.State.CHASE
	chasing.target = hero
	g._sight_point = hero.global_position
	g._launch()
	eq(near_one.state, Monster.State.ALERT, "a resting monster 15.6 from the volley is alerted")
	check(near_one._point.distance_to(hero.global_position) < 0.01, "... toward where the crew was seen")
	check(near_one.is_on_edge(), "... and on edge")
	eq(far_one.state, Monster.State.IDLE, "one 19.1 away is not")
	eq(chasing.state, Monster.State.CHASE, "a fighting monster keeps fighting")
	# The 12 nearest only.
	new_world(flat_map(14))
	add_hero(Vector2i(13, 0))
	g = MonsterFactory.spawn(GOBLIN, Vector2i(0, 0))
	var crowd: Array = []
	for c in Hex.range_cells(Vector2i(-4, 0), 2):
		var m := MonsterFactory.spawn("grunt", c)
		m.aggro_range = 0.001
		crowd.append(m)
	await frames(2)
	g._launch()
	var woken := crowd.filter(func(m: Monster) -> bool: return m.state == Monster.State.ALERT).size()
	eq(woken, MonsterSenses.ALARM_CAP, "one alarm wakes the 12 nearest of %d" % crowd.size())
	# A room's door within 24: its monsters hear it beyond 18 (rooms west, the corridor to the east).
	var map := flat_map(16)
	for c in map.cells.keys():
		var p := Hex.to_world(c)
		map.get_cell(c).tag = "room:1" if p.x < -6.0 else "corridor"
	new_world(map)
	add_hero(Vector2i(15, 0))
	g = MonsterFactory.spawn(GOBLIN, Vector2i(5, 0))                   # x 8.7
	var roomie := MonsterFactory.spawn("grunt", Vector2i(-11, 0))       # x -19: 27.7 from F, its room's door 15.6 from F
	roomie.aggro_range = 0.001
	await frames(2)
	g._launch()
	eq(roomie.state, Monster.State.ALERT, "a room whose door is within 24 of F hears it")


func _check_gate_wake() -> void:
	new_world(flat_map(16))
	add_hero(Vector2i(15, 0))
	var g = MonsterFactory.spawn(GOBLIN, Vector2i(0, 0))
	var near_gate := Hellgate.spawn(Vector2i(-6, 0), {"difficulty": 0.5})
	var far_gate := Hellgate.spawn(Vector2i(-12, 2), {"difficulty": 0.5})
	await frames(2)
	check(not near_gate.is_active() and not far_gate.is_active(), "both gates dormant")
	g._launch()
	check(near_gate.is_active(), "the fireworks wake a dormant gate 10.4 away (user, 2026-10-18)")
	check(not far_gate.is_active(), "... not one 20+ away")


func _check_second_scout() -> void:
	new_world(flat_map(16))
	var hero := add_hero(Vector2i(14, 0))
	var g = MonsterFactory.spawn(GOBLIN, Vector2i(0, 0))
	var g2 = MonsterFactory.spawn(GOBLIN, Vector2i(-8, 0))
	g2.set_spawn_facing(Vector3.LEFT)
	await frames(2)
	g._sight_point = hero.global_position
	g._launch()
	eq(g2.scout_phase, g2.Phase.ASSIST, "a second scout runs to the sighting point")
	check(g2.loaded, "... and keeps his own rockets")
	await frames(60 * 4)
	eq(g2.volleys, 0, "no chain reaction")


func _check_restock() -> void:
	new_world(flat_map(14))
	add_hero(Vector2i(13, 0))
	var g = MonsterFactory.spawn(GOBLIN, Vector2i(0, 0))
	g.set_spawn_facing(Vector3.LEFT)
	await frames(2)
	g._launch()
	check(not g.loaded, "empty after the volley")
	var t0 := GameWorld.time
	var back := await wait_until(func() -> bool: return g.loaded, 60 * 70)
	check(back, "he restocks")
	near(GameWorld.time - t0, g.RESTOCK_TIME, 1.0, "about 60 s after the volley")
	var patrol := await wait_until(func() -> bool: return g.scout_phase == g.Phase.PATROL or g.scout_phase == g.Phase.LOOK, 60 * 30)
	check(patrol, "and he is back on patrol")


# --- Real floors -----------------------------------------------------------------------------------------------------------

func _check_floors() -> void:
	var total := 0
	var worst_ms := 0.0
	var worst_scout_ms := 0.0
	var plans := []
	for s: int in [1, 2, 3, 7, 42]:
		for f in range(1, 4):
			var run := ContractRun.make(["prepper", "supervillain", "guru", "founder"][s % 4], s, 0.5)
			var map := DungeonGen.for_run(run, f)
			var p := SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
			worst_ms = maxf(worst_ms, float(SiteBuilder.last_plan_usec) / 1000.0)
			var n := p.scouts.size()
			total += n
			check(n >= 1 and n <= 2, "seed %d floor %d: 1-2 scouts (%d)" % [s, f, n])
			check(n <= SiteBuilder.scout_count(run, f), "... never more than the floor's count")
			for sc: Dictionary in p.scouts:
				var route: Array[Vector2i] = sc["route"]
				check(route.size() >= 3, "a route of waypoints")
				for c in route:
					check(map.get_cell(c).tag == "corridor", "route cells are corridor (%s)" % str(c))
				for r: String in (sc["rooms"] as Array):
					check(r != p.start_room and r != SiteBuilder.arrival_room(p), "never by the start or arrival room")
			plans.append(str(p.scouts))
			var before := str(p.scouts)
			p.scouts.clear()
			var t0 := Time.get_ticks_usec()
			ScoutPlanner.plan(map, run, f, p)
			worst_scout_ms = maxf(worst_scout_ms, float(Time.get_ticks_usec() - t0) / 1000.0)
			eq(str(p.scouts), before, "planning the scouts again gives the same routes")
	print("goblin scouts: %d on 15 floors; worst plan %.1f ms (the scouts' part at most %.2f ms)" % [total, worst_ms, worst_scout_ms])
	check(worst_scout_ms < 20.0, "planning the scouts is cheap (%.2f ms)" % worst_scout_ms)
	check(worst_ms < 300.0, "the plan stays inside its time (%.1f ms)" % worst_ms)
	# Deterministic.
	var run2 := ContractRun.make("guru", 42, 0.5)
	var a := SiteBuilder.plan(DungeonGen.for_run(run2, 2), run2, 2, PricedProp.catalog(run2.site_type))
	var b := SiteBuilder.plan(DungeonGen.for_run(run2, 2), run2, 2, PricedProp.catalog(run2.site_type))
	eq(str(a.scouts), str(b.scouts), "same seed, same scouts")
	# Spawned: in the world, on his route, not a pack monster.
	var run := ContractRun.make("prepper", 3, 0.5)
	var map := DungeonGen.for_run(run, 3)
	new_world(map)
	GameWorld.begin(map, world, run.floor_seed(3))
	var site := SiteBuilder.build(map, run, 3)
	check(site.scouts.size() >= 1, "the floor's scouts spawned (%d)" % site.scouts.size())
	for g in site.scouts:
		eq(g.kind, GOBLIN, "a goblin")
		check(not site.monsters.has(g), "not in the packs")
		check((g.route as Array).size() >= 3, "with his route")
		# He counts toward an "exterminate everything" contract (user, 2026-10-18: "Yes, count him"): the game's pest
		# count (game.gd _pest_alive) is every living Monster in the "monsters" group when the pest is "everything".
		check(g is Monster and get_tree().get_nodes_in_group("monsters").has(g), "a scout counts toward \"exterminate everything\"")


func _check_log() -> void:
	var path := "user://test_combat_log_goblin.csv"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	CombatLog.path = path
	CombatLog.enabled = true
	CombatLog.reset()
	var s := _scene(5)
	var g = s[0]
	var witness := MonsterFactory.spawn("grunt", Vector2i(-6, 0))
	witness.aggro_range = 0.001
	await wait_until(func() -> bool: return g.volleys > 0, 60 * 6)
	CombatLog.flush()
	CombatLog.enabled = false
	CombatLog.path = CombatLog.PATH
	var text := FileAccess.get_file_as_string(path)
	check(text.contains(",scout,goblin,sighted,"), "a sighting row")
	check(text.contains(",scout,goblin,launch,"), "a launch row")
	var cols := CombatLog.HEADER.split(",")
	for line in text.split("\n"):
		if line.contains(",launch,"):
			eq(line.split(",")[cols.find("count")], "1", "the launch row counts the monsters woken")
