extends MonsterTestBase
## Monster awareness, step 1 (docs/design/monster-awareness.md): spawn facing, look-arounds, the hit shout, noise,
## SUSPICIOUS -> CHASE, ALERT -> SEARCH -> home, hits while walking home, restlessness and idle life near the crew,
## determinism, and the passive combat log.

const SEEDS := [1, 2, 3, 7]
const ARCHETYPES := ["prepper", "supervillain", "guru", "founder"]


func _init() -> void:
	timeout_sec = 300.0


func setup() -> void:
	MonsterSenses.restless_override = 0.0
	_check_ramp()
	await _check_spawn_facing()
	await _check_look_around()
	await _check_shout()
	await _check_noise()
	await _check_suspicion()
	await _check_alert_search_home()
	await _check_hit_on_the_way_home()
	await _check_idle_life()
	await _check_imp_play()
	await _check_determinism()
	await _check_combat_log()
	MonsterSenses.restless_override = -1.0
	finish()


# --- Restlessness ramp ----------------------------------------------------------------------------------------------

func _check_ramp() -> void:
	near(MonsterSenses.ramp(0.0), 0.0, 0.0001, "R = 0 at the start of a floor")
	near(MonsterSenses.ramp(120.0), 0.0, 0.0001, "R = 0 until 2 minutes")
	near(MonsterSenses.ramp(240.0), 0.5, 0.0001, "R = 0.5 at 4 minutes")
	near(MonsterSenses.ramp(360.0), 1.0, 0.0001, "R = 1 at 6 minutes")
	near(MonsterSenses.ramp(900.0), 1.0, 0.0001, "R stays 1")


# --- Spawn facing on real floors -------------------------------------------------------------------------------------

func _floor_facings(arch: String, s: int, f: int) -> Dictionary:
	var run := ContractRun.make(arch, s, 0.5)
	var map := DungeonGen.for_run(run, f)
	new_world(map)
	GameWorld.begin(map, world, run.floor_seed(f))
	var site := SiteBuilder.build(map, run, f)
	var facings: Array[String] = []
	var walled := 0
	var walled_default := 0
	for m in site.monsters:
		facings.append("%s:%.3f,%.3f" % [str(m.current_cell()), m.facing.x, m.facing.z])
		if MonsterSenses.wall_ahead(m, m.facing):
			walled += 1
		if MonsterSenses.wall_ahead(m, Vector3.FORWARD):
			walled_default += 1
	return {"facings": facings, "walled": walled, "walled_default": walled_default, "n": site.monsters.size()}


func _check_spawn_facing() -> void:
	var total := 0
	var walled := 0
	var walled_default := 0
	var i := 0
	for s: int in SEEDS:
		for f in range(1, 4):
			var r := _floor_facings(ARCHETYPES[i % ARCHETYPES.size()], s, f)
			i += 1
			total += int(r["n"])
			walled += int(r["walled"])
			walled_default += int(r["walled_default"])
	var share := float(walled) / maxf(1.0, float(total))
	var old := float(walled_default) / maxf(1.0, float(total))
	print("spawn facing: %d monsters, wall within 2 hexes ahead: %.1f%% (all facing -Z it was %.1f%%)" % [total, share * 100.0, old * 100.0])
	check(total > 100, "enough monsters measured (%d)" % total)
	check(share < 0.05, "under 5%% of spawned monsters face a wall close ahead (%.1f%%)" % (share * 100.0))
	# Same seed, same facings.
	var a := _floor_facings("guru", 42, 2)
	var b := _floor_facings("guru", 42, 2)
	eq(a["facings"], b["facings"], "spawn facings are the same for a seed")
	await frames(1)


# --- Look-arounds -----------------------------------------------------------------------------------------------------

func _check_look_around() -> void:
	# A wall 2 hexes east of the grunt; it starts facing straight at it.
	var map := flat_map(8)
	wall_where(map, func(p: Vector3) -> bool: return p.x > 2.5)
	new_world(map)
	var g := MonsterFactory.spawn("grunt", Vector2i(0, 0))
	g.set_spawn_facing(Vector3.RIGHT)
	check(MonsterSenses.wall_ahead(g, g.facing), "set up facing the wall")
	await frames(2)
	for _i in 300:
		g.look_around()
		if MonsterSenses.wall_ahead(g, g.facing):
			check(false, "a look-around picked a heading with a wall close ahead (%s)" % str(g.facing))
			break
	# Naturally: turns every 4-9 s while idle.
	g.facing = Vector3.LEFT
	var last := g.facing
	var last_t := GameWorld.time
	var gaps: Array[float] = []
	for _f in 60 * 40:
		await get_tree().physics_frame
		if g.facing.distance_to(last) > 0.001:
			gaps.append(GameWorld.time - last_t)
			last = g.facing
			last_t = GameWorld.time
			check(not MonsterSenses.wall_ahead(g, g.facing), "an idle look-around never faces the wall")
	check(gaps.size() >= 4, "it looked around several times in 40 s (%d)" % gaps.size())
	for k in range(1, gaps.size()):   # (the first gap starts from the manual turn above)
		check(gaps[k] >= Monster.LOOK_MIN - 0.05 and gaps[k] <= Monster.LOOK_MAX + 0.05, "look-arounds 4-9 s apart (%.2f)" % gaps[k])
	check(g.global_position.distance_to(Hex.to_world(Vector2i.ZERO)) < 0.01, "looking around never walks (no room, no idle life)")


# --- The shout: a hit wakes monsters within 10 -----------------------------------------------------------------------

func _check_shout() -> void:
	new_world(flat_map(14))
	var hero := add_hero(Vector2i(-8, 0))                     # 13.9 west of the victim, 22+ from the others
	var victim := MonsterFactory.spawn("grunt", Vector2i(0, 0))
	var near_one := MonsterFactory.spawn("grunt", Vector2i(5, 0))   # 8.7 away
	var far_one := MonsterFactory.spawn("grunt", Vector2i(7, 0))    # 12.1 away
	var frozen := MonsterFactory.spawn("grunt", Vector2i(4, 2))     # within 10, frozen
	frozen.aggro_range = 0.0
	for m in [victim, near_one, far_one, frozen]:
		(m as Monster).set_spawn_facing(Vector3.RIGHT)          # all looking away from the hero
	await frames(3)
	eq(victim.state, Monster.State.IDLE, "the hero is unseen (behind, 13.9)")
	victim.apply_damage(1.0, hero)
	eq(victim.state, Monster.State.CHASE, "the victim fights")
	eq(near_one.state, Monster.State.ALERT, "a monster 8.7 away heard the fight (ALERT)")
	eq(far_one.state, Monster.State.IDLE, "a monster 12.1 away did not")
	eq(frozen.state, Monster.State.IDLE, "a frozen monster stays put")
	check(near_one._point.distance_to(hero.global_position) < 0.01, "it walks to where the attacker stood")
	# A frozen victim stays silent.
	new_world(flat_map(14))
	hero = add_hero(Vector2i(-8, 0))
	victim = MonsterFactory.spawn("grunt", Vector2i(0, 0))
	victim.aggro_range = 0.0
	near_one = MonsterFactory.spawn("grunt", Vector2i(4, 0))
	near_one.set_spawn_facing(Vector3.RIGHT)
	await frames(3)
	victim.apply_damage(1.0, hero)
	eq(near_one.state, Monster.State.IDLE, "a frozen monster never shouts")


# --- Noise ------------------------------------------------------------------------------------------------------------

func _hears(radius: float, dist_hex: int, walled: bool) -> bool:
	var map := flat_map(14)
	if walled:
		wall_where(map, func(p: Vector3) -> bool: return absf(p.x - Hex.to_world(Vector2i(dist_hex, 0)).x * 0.5) < 0.9 and absf(p.z) < 6.0)
	new_world(map)
	var m := MonsterFactory.spawn("grunt", Vector2i(dist_hex, 0))
	m.set_spawn_facing(Vector3.RIGHT)
	await frames(2)
	MonsterSenses.noise(Hex.to_world(Vector2i.ZERO), radius, "test")
	return m.state == Monster.State.SUSPICIOUS


func _check_noise() -> void:
	# The table: corn 14, fireball 10, teeth/tentacles 8, death 6, melee 4, arrow 3.
	for row in [["corn", MonsterSenses.NOISE_CORN], ["fireball", MonsterSenses.NOISE_FIREBALL],
			["teeth", MonsterSenses.NOISE_TEETH], ["tentacles", MonsterSenses.NOISE_TENTACLES],
			["death", MonsterSenses.NOISE_DEATH], ["melee", MonsterSenses.NOISE_MELEE], ["arrow", MonsterSenses.NOISE_ARROW]]:
		var r: float = row[1]
		var inside := floori(r / Hex.SQRT3)           # the farthest hex step still inside the radius
		check(await _hears(r, inside, false), "%s (%.0f) is heard %.1f away" % [row[0], r, inside * Hex.SQRT3])
		check(not await _hears(r, inside + 1, false), "%s (%.0f) is not heard %.1f away" % [row[0], r, (inside + 1) * Hex.SQRT3])
	eq([MonsterSenses.NOISE_CORN, MonsterSenses.NOISE_FIREBALL, MonsterSenses.NOISE_TEETH, MonsterSenses.NOISE_TENTACLES,
			MonsterSenses.NOISE_DEATH, MonsterSenses.NOISE_MELEE, MonsterSenses.NOISE_ARROW], [14.0, 10.0, 8.0, 8.0, 6.0, 4.0, 3.0],
			"the noise table")
	# Through a wall it carries 60%: corn at 12.1 behind a wall is not heard, at 6.9 it is.
	check(not await _hears(MonsterSenses.NOISE_CORN, 7, true), "corn through a wall: not heard at 12.1")
	check(await _hears(MonsterSenses.NOISE_CORN, 4, true), "corn through a wall: heard at 6.9 (inside 8.4)")
	# A frozen monster is deaf.
	new_world(flat_map(10))
	var deaf := MonsterFactory.spawn("grunt", Vector2i(2, 0))
	deaf.aggro_range = 0.0
	await frames(2)
	MonsterSenses.noise(Hex.to_world(Vector2i.ZERO), MonsterSenses.NOISE_CORN, "corn")
	eq(deaf.state, Monster.State.IDLE, "frozen monsters are deaf")
	# The hooks: Wick's arrow thunks into the floor 1.5 from an idle grunt (passing it by); a death is heard.
	new_world(flat_map(14))
	var hero := add_hero(Vector2i(-3, 0))
	var g := MonsterFactory.spawn("grunt", Vector2i(6, -1))   # (9.5, -1.5)
	g.set_spawn_facing(Vector3.BACK)                            # looking away from the hero
	await frames(2)
	ArrowShot.shoot(hero, Vector3.RIGHT, 5.0, 40.0, 14.0, 1, false, Color.WHITE)
	var heard := await wait_until(func() -> bool: return g.state == Monster.State.SUSPICIOUS, 60)
	check(heard, "an arrow landing 1.5 away makes an idle grunt suspicious")
	near(g.hp, g.max_hp, 0.001, "the arrow passed it by")
	new_world(flat_map(10))
	hero = add_hero(Vector2i(-9, 0))
	var dying := MonsterFactory.spawn("swarmer", Vector2i(0, 0))
	var witness := MonsterFactory.spawn("grunt", Vector2i(3, 0))   # 5.2 away (inside the death's 6)
	witness.set_spawn_facing(Vector3.RIGHT)
	await frames(2)
	dying.apply_damage(100.0, null)                                 # (no attacker: no shout, only the death is heard)
	eq(witness.state, Monster.State.SUSPICIOUS, "a monster dying 5.2 away is heard")


# --- SUSPICIOUS -> CHASE ----------------------------------------------------------------------------------------------

func _check_suspicion() -> void:
	# A hero 12.1 away straight ahead: beyond aggro 8, inside the cone's 14.
	new_world(flat_map(14))
	var hero := add_hero(Vector2i(7, 0))
	var g := MonsterFactory.spawn("grunt", Vector2i(0, 0))
	g.set_spawn_facing(Vector3.RIGHT)
	var t_sus := -1.0
	var t_chase := -1.0
	for _f in 300:
		await get_tree().physics_frame
		if t_sus < 0.0 and g.state == Monster.State.SUSPICIOUS:
			t_sus = GameWorld.time
		if g.state == Monster.State.CHASE:
			t_chase = GameWorld.time
			break
	check(t_sus >= 0.0, "a hero in the front cone makes it suspicious")
	check(t_chase > t_sus, "then it fights")
	var beat := t_chase - t_sus
	check(beat >= 1.4 and beat <= 1.8, "the \"?\" lasts about 1.5 s (%.2f)" % beat)
	# Behind it, the same hero is not seen (no look-around within 2 s).
	new_world(flat_map(14))
	hero = add_hero(Vector2i(7, 0))
	g = MonsterFactory.spawn("grunt", Vector2i(0, 0))
	g.set_spawn_facing(Vector3.LEFT)
	await frames(120)
	eq(g.state, Monster.State.IDLE, "a hero behind it at 12.1 goes unseen")
	# A hit confirms at once.
	new_world(flat_map(14))
	hero = add_hero(Vector2i(7, 0))
	g = MonsterFactory.spawn("grunt", Vector2i(0, 0))
	g.set_spawn_facing(Vector3.RIGHT)
	var sus := await wait_until(func() -> bool: return g.state == Monster.State.SUSPICIOUS, 30)
	check(sus, "suspicious")
	g.apply_damage(1.0, hero)
	eq(g.state, Monster.State.CHASE, "a hit while suspicious: straight to the fight")
	# Nothing more seen: it calms down after 6 s.
	new_world(flat_map(14))
	g = MonsterFactory.spawn("grunt", Vector2i(0, 0))
	await frames(2)
	g.hear(Hex.to_world(Vector2i(0, 2)))
	eq(g.state, Monster.State.SUSPICIOUS, "a sound: suspicious")
	var calm := await wait_until(func() -> bool: return g.state == Monster.State.IDLE, 60 * 12)
	check(calm, "nothing seen: calm again")


# --- ALERT -> SEARCH -> home --------------------------------------------------------------------------------------------

func _check_alert_search_home() -> void:
	new_world(flat_map(14))
	var g := MonsterFactory.spawn("grunt", Vector2i(0, 0))
	g.set_spawn_facing(Vector3.FORWARD)
	await frames(2)
	var home := g.global_position
	var goal := Hex.to_world(Vector2i(5, 0))
	check(g.alert(goal), "alerted")
	eq(g.state, Monster.State.ALERT, "ALERT")
	await frames(30)
	var p0 := g.global_position
	await frames(60)
	var speed := GameWorld.flat_distance(p0, g.global_position)
	check(speed > 0.8 * 3.2 * 0.85 and speed < 0.8 * 3.2 * 1.1, "walks at 80%% speed (%.2f u/s)" % speed)
	var searching := await wait_until(func() -> bool: return g.state == Monster.State.SEARCH, 300)
	check(searching, "arrives and searches")
	check(GameWorld.flat_distance(g.global_position, goal) <= Monster.ARRIVE_DIST + 0.2, "at the last known position")
	var t0 := GameWorld.time
	var returning := await wait_until(func() -> bool: return g.state == Monster.State.RETURN, 400)
	check(returning, "then goes home")
	near(GameWorld.time - t0, Monster.SEARCH_TIME, 0.1, "after a 5 s search")
	var home_again := await wait_until(func() -> bool: return g.state == Monster.State.IDLE, 400)
	check(home_again, "back at rest")
	check(GameWorld.flat_distance(g.global_position, home) <= Monster.HOME_ARRIVE_DIST, "at home")
	check(g.facing.distance_to(Vector3.FORWARD) < 0.01, "facing its post again")
	# Seeing a hero while alert: a fight.
	new_world(flat_map(14))
	add_hero(Vector2i(-6, 0))                                   # 10.4 behind it: outside aggro 8, inside alert's 12
	g = MonsterFactory.spawn("grunt", Vector2i(0, 0))
	g.set_spawn_facing(Vector3.RIGHT)
	await frames(2)
	g.alert(Hex.to_world(Vector2i(4, 0)))
	var fought := await wait_until(func() -> bool: return g.state == Monster.State.CHASE, 30)
	check(fought, "alert sight is wider (all round aggro + 4)")


# --- The walking-home bug ----------------------------------------------------------------------------------------------

func _check_hit_on_the_way_home() -> void:
	new_world(flat_map(14))
	var hero := add_hero(Vector2i(-5, 0))                      # 8.7 from its post, behind it: unseen
	var g := MonsterFactory.spawn("grunt", Vector2i(0, 0))
	g.set_spawn_facing(Vector3.RIGHT)
	await frames(2)
	eq(g.state, Monster.State.IDLE, "resting")
	g.global_position = Hex.to_world(Vector2i(6, 0))
	g.apply_damage(20.0, null)                                  # (hurt earlier, no attacker)
	g._begin_return()
	await frames(10)
	eq(g.state, Monster.State.RETURN, "walking home")
	g.apply_damage(5.0, hero)
	eq(g.state, Monster.State.CHASE, "a hit turns it around")
	await frames(90)
	check(g.state == Monster.State.CHASE or g.state == Monster.State.ATTACK, "and it keeps fighting")
	check(g.hp <= 15.0 + 0.001, "it did not heal to full")


# --- Idle life: patrols, restlessness, the 28-unit limit --------------------------------------------------------------

## Two rooms joined by a corridor: room:1 west (x < -4), room:2 east (x > 4), walls between except |z| < 1.5. Plus an
## isolated cell 69 units away to park a hero out of the relevance range.
func _two_rooms() -> HexMap:
	var map := flat_map(12)
	for c in map.cells.keys():
		var p := Hex.to_world(c)
		if absf(p.x) < 4.0 and absf(p.z) > 1.5:
			map.set_cell(c, 12, HexMap.Tile.WALL)
			continue
		map.get_cell(c).tag = "room:1" if p.x <= -4.0 else ("room:2" if p.x >= 4.0 else "corridor")
	map.set_cell(Vector2i(40, 0), 0)
	return map


func _moved_in(m: Monster, frames_n: int) -> float:
	var start := m.global_position
	var most := 0.0
	for _f in frames_n:
		await get_tree().physics_frame
		most = maxf(most, GameWorld.flat_distance(start, m.global_position))
	return most


func _check_idle_life() -> void:
	MonsterSenses.restless_override = 0.0
	# A skeleton with the crew within 28 patrols its room.
	new_world(_two_rooms())
	add_hero(Vector2i(9, -1))                                   # in room:2, ~22 from the skeleton, out of its sight
	var g = MonsterFactory.spawn("grunt", Vector2i(-6, 0))     # (untyped: the patrol's vars are the grunt's)
	g.set_spawn_facing(Vector3.LEFT)
	var moved: float = await _moved_in(g, 60 * 16)
	check(moved > 2.5, "patrols its room when the crew is within 28 (moved %.1f)" % moved)
	eq(MonsterSenses.room_of(g.current_cell()), "room:1", "and stays in its room")
	eq(g.state, Monster.State.IDLE, "patrolling is idle")
	check(g._route.size() >= 2, "a route of 2-3 points")
	for p in g._route:
		eq(MonsterSenses.room_of(Hex.from_world(p)), "room:1", "patrol points are in its room")
	# Nobody within 28: it stands still.
	new_world(_two_rooms())
	add_hero(Vector2i(40, 0))
	g = MonsterFactory.spawn("grunt", Vector2i(-6, 0))
	moved = await _moved_in(g, 60 * 16)
	check(moved < 0.01, "no idle life with the crew beyond 28 (moved %.2f)" % moved)
	# Frozen: never moves.
	new_world(_two_rooms())
	add_hero(Vector2i(9, -1))
	g = MonsterFactory.spawn("grunt", Vector2i(-6, 0))
	g.aggro_range = 0.0
	moved = await _moved_in(g, 60 * 12)
	check(moved < 0.01, "a frozen skeleton stays put")
	var facing0: Vector3 = g.facing
	check(facing0.distance_to(Vector3.FORWARD) < 0.01, "and never looks around")
	# Restlessness gates the visitors and sets the pace: R 0 -> no visitors, long pauses; R 1 -> ~1 in 3 visit.
	for r in [0.0, 1.0]:
		MonsterSenses.restless_override = r
		new_world(_two_rooms())
		add_hero(Vector2i(3, -1))                               # the whole of room:1 within 28 (they see nothing anyway)
		var crew: Array = []
		var cells := Hex.range_cells(Vector2i(-5, 0), 2)
		for c in cells:
			if MonsterSenses.room_of(c) == "room:1":
				crew.append(MonsterFactory.spawn("grunt", c))
		for m in crew:
			m.aggro_range = 0.001   # (sees nothing: only the idle life runs; not frozen)
		await frames(30)
		var visitors := 0
		for m in crew:
			if m.visitor:
				visitors += 1
				var last: Vector3 = m._route.back()
				eq(MonsterSenses.room_of(Hex.from_world(last)), "room:2", "a visitor's extra point is in the next room")
		if r == 0.0:
			eq(visitors, 0, "no visitors before R 0.5 (%d grunts)" % crew.size())
		else:
			check(visitors >= 1 and visitors <= crew.size() - 1, "about 1 in 3 visit at R 1 (%d of %d)" % [visitors, crew.size()])
		# The pause at a patrol point: 6 s calm, 2.5 s at full restlessness.
		var walker = crew[0]
		var paused := await wait_until(func() -> bool: return walker._pause_t > 0.0 and walker._route_i != 1, 60 * 20)
		if paused:
			near(walker._pause_t, lerpf(6.0, 2.5, r), 0.1, "pause at R %.0f" % r)
		else:
			check(false, "a patrol reached its next point (R %.0f)" % r)
	MonsterSenses.restless_override = 0.0


func _check_imp_play() -> void:
	MonsterSenses.restless_override = 0.0
	new_world(_two_rooms())
	add_hero(Vector2i(9, -1))
	var imps: Array = []
	for c in [Vector2i(-7, 0), Vector2i(-6, 0), Vector2i(-7, 1), Vector2i(-8, 1), Vector2i(-6, -1)]:
		var m := MonsterFactory.spawn("swarmer", c)
		m.aggro_range = 0.001   # (sees nothing: only the idle life runs)
		imps.append(m)
	var homes: Array[Vector3] = []
	for m in imps:
		homes.append(m.global_position)
	var moved := 0
	var far := 0.0
	for _f in 60 * 12:
		await get_tree().physics_frame
		for m in imps:
			far = maxf(far, GameWorld.flat_distance(m.global_position, homes[0]))
			if _f % 60 == 0:
				check(MonsterSenses.room_of(m.current_cell()) == "room:1", "imps play inside their room")
	for i in imps.size():
		if GameWorld.flat_distance(imps[i].global_position, homes[i]) > 0.5 or imps[i]._play != 0:
			moved += 1
	check(moved >= 3, "the clump is playing (%d of 5 moved)" % moved)
	check(far < 5.0 * Hex.SQRT3 + 3.0, "they stay near the clump (farthest %.1f)" % far)
	var leaders := 0
	for m in imps:
		if m._leads():
			leaders += 1
	eq(leaders, 1, "one clump, one leader")
	for m in imps:
		check(not m.dead and m.state == Monster.State.IDLE, "playing hurts nobody and stays idle")



# --- Determinism ----------------------------------------------------------------------------------------------------------

func _route_for_seed() -> Array:
	new_world(_two_rooms())
	add_hero(Vector2i(9, -1))
	var g = MonsterFactory.spawn("grunt", Vector2i(-6, 0))
	g.aggro_range = 0.001
	await wait_until(func() -> bool: return g._route_built, 30)
	var out: Array = []
	for p in g._route:
		out.append(Hex.from_world(p))
	var looks: Array = []
	for _i in 5:
		g.look_around()
		looks.append("%.4f,%.4f" % [g.facing.x, g.facing.z])
	return [out, looks]


func _check_determinism() -> void:
	var a: Array = await _route_for_seed()
	var b: Array = await _route_for_seed()
	eq(a[0], b[0], "same seed, same patrol route")
	eq(a[1], b[1], "same seed, same look-arounds")


# --- The combat log -------------------------------------------------------------------------------------------------------

func _check_combat_log() -> void:
	var path := "user://test_combat_log.csv"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	CombatLog.path = path
	CombatLog.enabled = true
	CombatLog.reset()
	new_world(flat_map(14))
	var hero := add_hero(Vector2i(-7, 0))
	var g := MonsterFactory.spawn("grunt", Vector2i(0, 0))
	g.set_spawn_facing(Vector3.RIGHT)
	await frames(5)
	g.apply_damage(1.0, hero)
	await frames(30)
	g.apply_damage(100.0, hero)
	await frames(60 * 4)
	CombatLog.flush()
	CombatLog.enabled = false
	CombatLog.path = CombatLog.PATH
	var lines := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	eq(lines[0].strip_edges(), CombatLog.HEADER, "a header")
	var cols := CombatLog.HEADER.split(",")
	var events := {}
	for i in range(1, lines.size()):
		var row := lines[i].split(",")
		events[row[cols.find("event")]] = row
	check(events.has("facing"), "a facing row for the floor")
	check(events.has("first_hit"), "a first-hit row")
	if events.has("first_hit"):
		var fh: PackedStringArray = events["first_hit"]
		eq(fh[cols.find("state")], "idle", "hit while idle")
		near(float(fh[cols.find("dist")]), 12.12, 0.05, "from 12.1 away")
		eq(fh[cols.find("kind")], "grunt", "a grunt")
	check(events.has("kill"), "a kill row")
	check(events.has("fight"), "an engagement row")
	if events.has("fight"):
		eq(events["fight"][cols.find("count")], "1", "one monster fought")
