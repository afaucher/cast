extends MonsterTestBase
## Hellgates: spawn on a difficulty / depth curve, wake only when a hero is near or the gate is hit, hold
## a cap of living spawns, respect the pest kind, close exactly once, the origin gate's three phases with
## the shove burst, site-wide spawn stop, and immovability.

var _closed_count := 0
var _origin_events := 0
var _gate_events := 0


func _gate(cell: Vector2i, opts: Dictionary) -> Hellgate:
	var g := Hellgate.spawn(cell, opts)
	g.set_physics_process(false)     # tests drive the spawner with step() for speed and determinism
	g.fx_enabled = false
	return g


## Step `seconds` of game time in 1/30 s slices; frees every spawn each slice when `kill` is set
## (so the cap never limits the count). Returns gate.spawned_total.
func _run(g: Hellgate, seconds: float, kill: bool) -> int:
	var steps := int(seconds * 30.0)
	for i in steps:
		g.step(1.0 / 30.0)
		if kill:
			for m in g.living_spawns():
				m.free()
	return g.spawned_total


func setup() -> void:
	Monster.use_proto_visuals = true
	await _t_basics()
	await _t_closing()
	await _t_activation()
	await _t_scaling()
	await _t_cap_and_pest()
	await _t_origin_phases()
	await _t_origin_stops_site()
	await _t_immovable()
	Monster.use_proto_visuals = false
	finish()


func _t_basics() -> void:
	new_world(flat_map(14))
	var g := _gate(Vector2i(0, 0), {"difficulty": 0.4, "depth": 1})
	eq(g.team, GameWorld.TEAM_MONSTERS, "monster team")
	eq(g.display_name, "Hellgate", "name")
	near(g.shove_mult, 0.0, 0.0001, "immovable")
	check(g.max_hp >= Hellgate.HP_EASY and g.max_hp <= Hellgate.HP_HARD, "hp in range %f" % g.max_hp)
	check(g.is_in_group("hellgates"), "grouped")
	check(not g.is_origin(), "not origin")
	var o := _gate(Vector2i(7, 0), {"origin": true, "difficulty": 0.4, "depth": 3})
	eq(o.display_name, "Origin Gate", "origin name")
	check(o.is_origin(), "is origin")
	near(o.max_hp, Hellgate.profile(0.4, 3, true)["hp"], 0.01, "origin hp from profile")
	check(o.max_hp > g.max_hp * 2.5, "origin is much tougher")
	check(o.radius > g.radius, "origin is bigger")
	var o2 := _gate(Vector2i(-7, 0), {"max_hp": 77.0})
	near(o2.max_hp, 77.0, 0.001, "max_hp override")
	check(g.model != null and o.model != null, "models built")
	check(o.model.triangle_count() > g.model.triangle_count(), "origin has more shards")
	check(o.model.shard_count > g.model.shard_count, "origin has more spikes")
	# Heroes damage it with everything (it is on the monster team).
	var hero := add_hero(Vector2i(3, 0))
	var hp0 := g.hp
	Combat.explode(g.global_position, 3.0, 20.0, GameWorld.TEAM_MONSTERS, hero)
	check(g.hp < hp0, "area spell hurts it")


func _t_closing() -> void:
	new_world(flat_map(12))
	_closed_count = 0
	_gate_events = 0
	var died_count := [0]
	var hub := HellgateEvents.hub()
	var conn := func(_gate: Actor) -> void: _gate_events += 1
	hub.gate_closed.connect(conn)
	var g := _gate(Vector2i(0, 0), {"difficulty": 0.2, "depth": 1, "max_hp": 60.0})
	g.closed.connect(func(_gate: Actor) -> void: _closed_count += 1)
	GameWorld.actor_died.connect(func(a: Actor) -> void:
		if a is Hellgate:
			died_count[0] += 1)
	var hero := add_hero(Vector2i(2, 0))
	hero.facing = Vector3.LEFT
	# A real hero melee swing next to the gate.
	hero.global_position = g.global_position + Vector3(1.6, 0, 0)
	var swings := 0
	while not g.dead and swings < 20:
		Combat.melee_arc(hero, Vector3.LEFT, 2.5, 120.0, 20.0)
		swings += 1
	check(g.dead, "hero damage closes it (swings %d)" % swings)
	check(swings >= 3, "takes more than a poke: 60 hp / 20 dmg")
	eq(_closed_count, 1, "closed fired once")
	eq(_gate_events, 1, "hub gate_closed fired once")
	eq(died_count[0], 1, "actor_died once")
	check(g.apply_damage(50.0, hero) == 0.0, "no damage once closed")
	g.die()
	eq(_closed_count, 1, "still once after a second die()")
	check(not Hellgate.open_gates().has(g), "no longer an open gate")
	check(not GameWorld.actors().has(g), "off the target lists immediately")
	check(g.model.is_closing(), "collapse animation playing")
	await frames(int((Hellgate.CLOSE_TIME + 0.5) * 60.0))
	check(not is_instance_valid(g), "node freed after the collapse")
	hub.gate_closed.disconnect(conn)


func _t_activation() -> void:
	new_world(flat_map(24))
	var g := _gate(Vector2i(0, 0), {"difficulty": 1.0, "depth": 3})
	var far := add_hero(Vector2i(16, 0))
	check(GameWorld.flat_distance(far.global_position, g.global_position) > Hellgate.ACTIVATE_RANGE, "hero is out of range")
	g.step(120.0)
	check(not g.is_active(), "still dormant with the hero far away")
	eq(g.spawned_total, 0, "no spawns before activation")
	eq(g.living_spawn_count(), 0, "no living spawns before activation")
	# Hit it: wakes without a hero near.
	g.apply_damage(5.0, far)
	check(g.is_active(), "being hit wakes it")
	check(g.time_to_burst() > Hellgate.TELEGRAPH_TIME, "the first burst is not instant")
	# A second gate woken by proximity.
	var h2 := _gate(Vector2i(-14, 0), {"difficulty": 0.5, "depth": 2})
	var near_hero := add_hero(Vector2i(-11, 0))
	check(not h2.is_active(), "dormant before the first scan")
	for i in 15:
		h2.step(0.1)
	check(h2.is_active(), "a hero within %d wakes it" % int(Hellgate.ACTIVATE_RANGE))
	near_hero.global_position = Vector3(500, 0, 500)
	# Telegraph precedes the burst.
	var tele := [0.0, 0.0]
	h2.burst_telegraphed.connect(func(d: float) -> void: tele[0] = d)
	h2.burst_spawned.connect(func(_m: Array) -> void: tele[1] = 1.0)
	var guard := 0
	while tele[1] == 0.0 and guard < 3000:
		h2.step(1.0 / 30.0)
		guard += 1
		if tele[1] == 0.0 and tele[0] > 0.0:
			check(h2.is_telegraphing(), "telegraphing before the burst")
	check(tele[0] > 0.0 and tele[1] > 0.0, "flare then burst")
	check(h2.spawned_total > 0, "it spawned something")


func _t_scaling() -> void:
	# Pure curve: monotonic in difficulty and in depth.
	var last_rate := -1.0
	for d in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var r: float = Hellgate.profile(d, 2)["rate"]
		check(r >= last_rate, "profile rate rises with difficulty %.2f" % d)
		last_rate = r
	last_rate = -1.0
	for dp in [1, 2, 3]:
		var r2: float = Hellgate.profile(0.5, dp)["rate"]
		check(r2 >= last_rate, "profile rate rises with depth %d" % dp)
		last_rate = r2
	var easy: Dictionary = Hellgate.profile(0.0, 1)
	var hard: Dictionary = Hellgate.profile(1.0, 3)
	check(int(easy["burst"]) <= 1 and float(easy["interval"]) >= 12.0, "easy and shallow is slow and sparse")
	check(int(hard["burst"]) >= 4 and float(hard["interval"]) <= 5.0, "hard and deep pumps out waves")
	check(int(hard["cap"]) > int(easy["cap"]), "cap rises")

	# Simulated: count real spawns over 60 s (the hero stays near; spawns are freed so the cap is out of it).
	new_world(flat_map(14))
	add_hero(Vector2i(5, 0))
	var settings := [[0.0, 1], [0.5, 1], [1.0, 1], [0.5, 2], [0.5, 3]]
	var counts: Array[int] = []
	for s in settings:
		var g := _gate(Vector2i(0, 0), {"difficulty": float(s[0]), "depth": int(s[1])})
		counts.append(_run(g, 60.0, true))
		g.free()
	print("hellgate spawns in 60 s  (difficulty, depth) -> ", counts, "  ", settings)
	check(counts[0] > 0, "even the easiest gate spawns")
	check(counts[0] < counts[1] and counts[1] < counts[2], "monotonic in difficulty: %s" % str(counts))
	check(counts[1] < counts[3] and counts[3] < counts[4], "monotonic in depth: %s" % str(counts))
	check(counts[2] >= counts[0] * 3, "hard is at least 3x easy")


func _t_cap_and_pest() -> void:
	new_world(flat_map(14))
	var hero := add_hero(Vector2i(6, 0))
	# The cap holds when nothing is killed.
	var g := _gate(Vector2i(0, 0), {"difficulty": 1.0, "depth": 3})
	g.apply_damage(1.0, hero)
	var worst := 0
	for i in 1800:
		g.step(1.0 / 30.0)
		worst = maxi(worst, g.living_spawn_count())
	eq(worst, g.spawn_cap, "living spawns reach the cap and never pass it (%d / %d)" % [worst, g.spawn_cap])
	eq(g.spawned_total, g.spawn_cap, "no more than the cap were ever made")
	for m in g.living_spawns():
		check(m.get_meta("from_gate") == g, "spawn carries from_gate")
		check(m.is_aggro(), "spawn is aggroed, not idling")
		check(GameWorld.flat_distance(m.global_position, g.global_position) > g.radius, "spawned clear of the gate body")
	# Kill some: it tops up again.
	var living := g.living_spawns()
	for i in 4:
		living[i].free()
	var before := g.spawned_total
	for i in 900:
		g.step(1.0 / 30.0)
	check(g.spawned_total > before, "it refills when spawns die")
	check(g.living_spawn_count() <= g.spawn_cap, "still within the cap")
	var easy := _gate(Vector2i(-8, 0), {"difficulty": 0.0, "depth": 1})
	easy.apply_damage(1.0, hero)
	for i in 3000:
		easy.step(1.0 / 30.0)
	eq(easy.living_spawn_count(), easy.spawn_cap, "easy gate caps at its own, smaller cap")
	check(easy.spawn_cap < g.spawn_cap, "easy cap is lower")

	# Pest: only that kind.
	for pest in ["swarmer", "brute", "archer"]:
		new_world(flat_map(14))
		add_hero(Vector2i(5, 0))
		var pg := _gate(Vector2i(0, 0), {"difficulty": 1.0, "depth": 2, "pest": pest})
		_run(pg, 30.0, false)
		var seen := {}
		for m in pg.living_spawns():
			seen[m.kind] = true
		check(pg.spawned_total > 0, "pest gate spawned")
		eq(seen.keys(), [pest], "pest %s respected" % pest)
	# Mixed: several kinds, swarmers the most common, brutes the rarest.
	new_world(flat_map(14))
	add_hero(Vector2i(5, 0))
	var mg := _gate(Vector2i(0, 0), {"difficulty": 0.5, "depth": 2})
	var counts := {}
	for i in 9000:
		mg.step(1.0 / 30.0)
		for m in mg.living_spawns():
			counts[m.kind] = int(counts.get(m.kind, 0)) + 1
			m.free()
	check(counts.size() >= 3, "mixed gate makes several kinds: %s" % str(counts))
	check(int(counts.get("swarmer", 0)) > int(counts.get("brute", 0)), "more swarmers than brutes: %s" % str(counts))
	# Walls and pits are not spawn cells.
	new_world(flat_map(14))
	wall_where(GameWorld.map, func(p: Vector3) -> bool: return p.x > 0.5)
	add_hero(Vector2i(-4, 0))
	var wg := _gate(Vector2i(0, 0), {"difficulty": 1.0, "depth": 3})
	wg.apply_damage(1.0, null)
	_run(wg, 20.0, false)
	check(wg.spawned_total > 0, "walled gate still spawns")
	for m in wg.living_spawns():
		var c := Hex.from_world(m.global_position)
		check(GameWorld.map.is_walkable_cell(c), "spawn stands on a walkable cell")


func _t_origin_phases() -> void:
	new_world(flat_map(16))
	var hero := add_hero(Vector2i(2, 2))
	var o := _gate(Vector2i(0, 0), {"origin": true, "difficulty": 0.6, "depth": 3, "max_hp": 300.0})
	var phases: Array[int] = []
	var shoves := [0]
	var telegraphs := [0]
	o.phase_changed.connect(func(p: int) -> void: phases.append(p))
	o.shove_burst.connect(func(_r: float) -> void: shoves[0] += 1)
	o.shove_telegraphed.connect(func(_r: float, _d: float) -> void: telegraphs[0] += 1)
	var interval0 := o.spawn_interval
	var burst0 := o.burst_size
	var cap0 := o.spawn_cap
	eq(o.phase, 0, "starts in phase 0")
	# A monster inside the radius is not shoved; a hero is.
	var imp := MonsterFactory.spawn("grunt", Vector2i(2, -1))
	imp.set_physics_process(false)      # so it cannot walk off by itself: only a shove could move it
	var imp_pos := imp.global_position
	hero.global_position = o.global_position + Vector3(3.6, 0, 0.5)
	var hero_pos := hero.global_position
	o.apply_damage(60.0, hero)           # 240/300 = 80%: still phase 0
	eq(o.phase, 0, "above 66% is phase 0")
	eq(phases.size(), 0, "no phase event yet")
	o.apply_damage(60.0, hero)           # 180/300 = 60%
	eq(o.phase, 1, "below 66% is phase 1")
	eq(phases, [1] as Array[int], "phase_changed(1)")
	eq(telegraphs[0], 1, "shove telegraphed on the phase change")
	eq(shoves[0], 0, "...but not fired yet")
	check(o.spawn_interval < interval0 and o.burst_size > burst0 and o.spawn_cap > cap0, "phase 1 spawns faster and bigger")
	var interval1 := o.spawn_interval
	for i in 20:
		o.step(0.05)        # 1.0 s
	eq(shoves[0], 1, "shove burst fired after the wind-up")
	await frames(40)
	check(GameWorld.flat_distance(hero.global_position, o.global_position) > GameWorld.flat_distance(hero_pos, o.global_position) + 0.8, "hero was shoved outward")
	check(GameWorld.flat_distance(imp.global_position, imp_pos) < 0.5, "monsters inside the radius are not shoved")
	o.apply_damage(100.0, hero)          # 80/300 = 27%
	eq(o.phase, 2, "below 33% is phase 2")
	eq(phases, [1, 2] as Array[int], "phase_changed(2)")
	check(o.spawn_interval < interval1, "phase 2 faster again")
	for i in 20:
		o.step(0.05)
	eq(shoves[0], 2, "second shove burst")
	# A killing blow skips straight to closed: no phase event, no shove, closed once.
	var closed := [0]
	o.closed.connect(func(_g: Actor) -> void: closed[0] += 1)
	o.apply_damage(1000.0, hero)
	eq(closed[0], 1, "origin closed once")
	eq(phases.size(), 2, "no extra phase event on the kill")
	for i in 40:
		o.step(0.05)
	eq(shoves[0], 2, "no shove after it is closed")
	# Phases cannot be skipped silently: one big non-lethal hit past both thresholds gives both events.
	new_world(flat_map(16))
	add_hero(Vector2i(2, 2))
	var o2 := _gate(Vector2i(0, 0), {"origin": true, "max_hp": 300.0})
	var ph2: Array[int] = []
	o2.phase_changed.connect(func(p: int) -> void: ph2.append(p))
	o2.apply_damage(230.0, null)         # 70/300 = 23%
	eq(ph2, [1, 2] as Array[int], "a big hit reports every phase it crossed")


func _t_origin_stops_site() -> void:
	new_world(flat_map(24))
	HellgateEvents.reset()
	check(not Hellgate.spawns_stopped(), "spawning is on")
	var hero := add_hero(Vector2i(4, 0))
	var o := _gate(Vector2i(0, 0), {"origin": true, "difficulty": 0.8, "depth": 3, "max_hp": 100.0})
	var other := _gate(Vector2i(-8, 0), {"difficulty": 1.0, "depth": 3})
	other.apply_damage(1.0, hero)
	_origin_events = 0
	var conn := func(_g: Actor) -> void: _origin_events += 1
	HellgateEvents.on_origin_closed(conn)
	_run(other, 20.0, true)
	var made := other.spawned_total
	check(made > 0, "the other gate spawns while the origin is open")
	o.apply_damage(500.0, hero)
	check(o.dead, "origin closed")
	eq(_origin_events, 1, "origin_closed fired once")
	check(Hellgate.spawns_stopped(), "site-wide spawns stopped")
	_run(other, 60.0, true)
	eq(other.spawned_total, made, "the other gate spawns nothing more")
	var none := other.spawn_burst_now()
	eq(none.size(), 0, "not even a forced burst")
	# A gate made afterwards is also silent; a new world clears the flag by itself.
	var late := _gate(Vector2i(8, 0), {"difficulty": 1.0, "depth": 3})
	late.apply_damage(1.0, hero)
	_run(late, 30.0, true)
	eq(late.spawned_total, 0, "a gate made after the origin closed is silent")
	new_world(flat_map(12))
	check(not Hellgate.spawns_stopped(), "a new world clears the flag")
	HellgateEvents.hub().origin_closed.disconnect(conn)
	# Closing an ordinary gate does not stop anything.
	add_hero(Vector2i(3, 0))
	var a := _gate(Vector2i(0, 0), {"difficulty": 0.5, "max_hp": 10.0})
	var b := _gate(Vector2i(-6, 0), {"difficulty": 1.0, "depth": 3})
	b.apply_damage(1.0, null)
	a.apply_damage(100.0, null)
	check(not Hellgate.spawns_stopped(), "a normal gate closing leaves the others spawning")
	_run(b, 20.0, true)
	check(b.spawned_total > 0, "others keep spawning")
	HellgateEvents.stop_spawns()
	check(Hellgate.spawns_stopped(), "close_all_spawns style flag works by hand")
	HellgateEvents.reset()
	check(not Hellgate.spawns_stopped(), "reset clears it")
	Hellgate.close_all_spawns()
	check(Hellgate.spawns_stopped(), "Hellgate.close_all_spawns()")
	Hellgate.reset_spawn_state()


func _t_immovable() -> void:
	new_world(flat_map(12))
	var hero := add_hero(Vector2i(3, 0))
	var g := _gate(Vector2i(0, 0), {"difficulty": 0.5})
	g.set_physics_process(true)
	var p0 := g.global_position
	g.shove(Vector3.RIGHT, 4.0, hero)
	check(not g.is_shoved(), "shove is ignored")
	Combat.shove_radius(g.global_position + Vector3(1, 0, 0), 4.0, 5.0, hero)
	await frames(30)
	check(g.global_position.distance_to(p0) < 0.001, "the gate did not move")
	var o := _gate(Vector2i(6, 0), {"origin": true})
	var q0 := o.global_position
	Combat.shove_radius(o.global_position + Vector3(0, 0, 1), 4.0, 5.0, hero)
	await frames(30)
	check(o.global_position.distance_to(q0) < 0.001, "the origin gate did not move either")
	check(hero.global_position.distance_to(Hex.to_world(Vector2i(3, 0))) > 0.5, "while the hero in the same shove did")
