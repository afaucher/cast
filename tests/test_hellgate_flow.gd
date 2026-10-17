extends MonsterTestBase
## Hellgate on real physics frames (no manual stepping): wakes when a hero walks up, flares, spawns
## aggroed monsters that carry from_gate, stops when closed, leaves its spawns alone.


func setup() -> void:
	Monster.use_proto_visuals = true
	new_world(flat_map(16))
	var hero := add_hero(Vector2i(0, 0))
	hero.max_hp = 100000.0
	hero.hp = 100000.0
	var g := Hellgate.spawn(Vector2i(12, 0), {"difficulty": 1.0, "depth": 3})
	g.fx_enabled = false
	var bursts := [0]
	var flares := [0]
	g.burst_spawned.connect(func(m: Array) -> void: bursts[0] += m.size())
	g.burst_telegraphed.connect(func(_d: float) -> void: flares[0] += 1)
	await frames(180)
	check(GameWorld.flat_distance(hero.global_position, g.global_position) > Hellgate.ACTIVATE_RANGE, "hero starts out of range")
	check(not g.is_active() and g.spawned_total == 0, "dormant while the hero is far")
	hero.global_position = Hex.to_world(Vector2i(6, 0))
	check(await wait_until(func() -> bool: return g.is_active(), 60), "wakes when the hero walks up")
	check(await wait_until(func() -> bool: return g.is_telegraphing(), 600), "a flare precedes the burst")
	check(g.model != null, "model present")
	check(await wait_until(func() -> bool: return g.spawned_total >= 3, 900), "spawns monsters on its own")
	check(flares[0] >= 1, "burst_telegraphed fired")
	for m in g.living_spawns():
		check(m.get_meta("from_gate") == g, "from_gate meta")
	await frames(120)
	var hurt := false
	for m in g.living_spawns():
		if m.is_aggro() or m.state == Monster.State.ATTACK:
			hurt = true
	check(hurt, "spawned monsters go for the hero")
	var closed := [0]
	g.closed.connect(func(_x: Actor) -> void: closed[0] += 1)
	var before: int = bursts[0]
	g.apply_damage(100000.0, hero)
	eq(closed[0], 1, "closed once")
	await frames(300)
	eq(bursts[0], before, "no spawns after it closed")
	check(not is_instance_valid(g), "gate node freed after collapsing")
	Monster.use_proto_visuals = false
	finish()
