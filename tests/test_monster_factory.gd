extends MonsterTestBase
## MonsterFactory: spawn, spawn_pack budget / placement, and a 40-monster frame-time smoke test.


func setup() -> void:
	var map := flat_map(7)
	# Mix in stairs and walls that must never be used.
	map.set_stairs(Vector2i(1, 1), 0, 0, 2)
	map.set_cell(Vector2i(-1, 1), 5, HexMap.Tile.WALL)
	map.set_cell(Vector2i(2, -1), 0, HexMap.Tile.BRIDGE)
	new_world(map)

	for k in MonsterFactory.KINDS:
		var m := MonsterFactory.spawn(k, Vector2i(0, 0))
		check(m != null, k + " spawns")
		eq(m.kind, k, "kind name")
		eq(m.team, GameWorld.TEAM_MONSTERS, "team")
		check(m.is_inside_tree(), "in the tree")
		m.free()
	eq(MonsterFactory.spawn("dragon", Vector2i(0, 0)), null, "unknown kind -> null")

	var room: Array[Vector2i] = []
	room.assign(Hex.range_cells(Vector2i.ZERO, 6))
	room.append(Vector2i(-1, 1))     # wall
	room.append(Vector2i(1, 1))      # stairs
	room.append(Vector2i(40, 40))    # void
	var rng := RandomNumberGenerator.new()
	var seen_kinds := {}
	for budget in [0, 1, 2, 3, 5, 6, 8, 10, 14, 20, 30]:
		for trial in 6:
			rng.seed = budget * 100 + trial
			var pack := MonsterFactory.spawn_pack(room, budget, rng)
			var cost := MonsterFactory.cost_of(pack)
			check(cost <= budget, "budget %d respected (spent %d)" % [budget, cost])
			if budget >= 10:
				check(cost >= budget - 1, "budget %d mostly spent (spent %d)" % [budget, cost])
			var used := {}
			var swarmers := 0
			for m in pack:
				seen_kinds[m.kind] = true
				var c := m.current_cell()
				var cell := map.get_cell(c)
				check(cell != null and map.is_walkable_cell(c), "placed on walkable cell %s" % str(c))
				check(cell != null and cell.type != HexMap.Tile.STAIRS, "never on stairs")
				check(not used.has(c), "one monster per cell")
				used[c] = true
				if m.kind == "swarmer":
					swarmers += 1
			if swarmers > 0:
				check(swarmers >= 4 and swarmers <= 6, "swarmer pack of 4-6 (got %d)" % swarmers)
			for m in pack:
				m.free()
	eq(seen_kinds.size(), 4, "all four kinds appear across budgets")

	# Same seed, same pack.
	rng.seed = 99
	var a := MonsterFactory.spawn_pack(room, 12, rng)
	var ka := a.map(func(m: Monster) -> String: return m.kind + str(m.current_cell()))
	for m in a:
		m.free()
	rng.seed = 99
	var b := MonsterFactory.spawn_pack(room, 12, rng)
	var kb := b.map(func(m: Monster) -> String: return m.kind + str(m.current_cell()))
	for m in b:
		m.free()
	eq(ka, kb, "deterministic for a seed")

	# Performance smoke test: 40 aggroed monsters on a big flat floor.
	new_world(flat_map(14))
	var hero := add_hero(Vector2i(0, 0))
	hero.max_hp = 1.0e9
	hero.hp = hero.max_hp
	var cells := Hex.ring(Vector2i.ZERO, 3)     # all inside every aggro range
	cells.append_array(Hex.ring(Vector2i.ZERO, 4))
	var crowd: Array[Monster] = []
	for i in 40:
		crowd.append(MonsterFactory.spawn(MonsterFactory.KINDS[i % 4], cells[i]))
	await frames(60)
	var chasing := 0
	for m in crowd:
		if m.state != Monster.State.IDLE:
			chasing += 1
	check(chasing >= 38, "the crowd is awake and active (%d)" % chasing)
	var t0 := Time.get_ticks_usec()
	await frames(240)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 240.0
	print("40 monsters: %.2f ms per physics frame (headless)" % ms)
	check(ms < 16.0, "40 monsters fit a 60fps frame budget (%.2f ms)" % ms)
	finish()
