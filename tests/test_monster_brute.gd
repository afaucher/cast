extends MonsterTestBase
## Brute: cannot climb a +2 ledge (the hero up there is safe), but walks up steps and stairs.


func setup() -> void:
	# --- A: hero on a +2 ledge, far from the edge: unreachable, no slam -------------------
	var map_a := flat_map(10)
	for c in map_a.cells.keys():
		if Hex.to_world(c).x > 3.0:
			map_a.cells[c].level = 2
	new_world(map_a)
	var hero := add_hero(Vector2i(5, 0), 2.0)                   # x = 8.7, deep on the ledge
	var brute := MonsterFactory.spawn("brute", Vector2i(0, 0))
	check(not brute.can_climb, "brute cannot climb")
	eq(map_a.find_path(Vector2i(0, 0), Vector2i(5, 0), false).size(), 0, "no non-climb route")
	check(map_a.find_path(Vector2i(0, 0), Vector2i(5, 0), true).size() > 0, "climbers can reach it")
	brute.aggro(hero)                                           # force it (LOS is covered by the grunt test)
	await frames(420)
	near(hero.hp, 100.0, 0.001, "ledge hero takes no slam")
	check(brute.global_position.x < 3.5, "brute stays below the ledge (x=%.2f)" % brute.global_position.x)
	check(brute.global_position.y < 0.2, "brute never got up (y=%.2f)" % brute.global_position.y)

	# Even standing right at the lip, a hero one ledge up is out of slam reach.
	hero.global_position = Hex.to_world(Vector2i(2, 0), 2.0)    # x = 3.46, first ledge cell
	await frames(240)
	near(hero.hp, 100.0, 0.001, "hero at the lip is still safe")

	# And a ground-level hero is not (the ledge hero leaves; the brute retargets).
	hero.die()
	var low := add_hero(Vector2i(-1, 0), 0.0)
	await wait_until(func() -> bool: return low.hp < 100.0, 600)
	check(low.hp < 100.0, "ground hero near the brute takes a slam")

	# --- B: terraced steps (+1 each) up to the hero: brute walks up and slams -------------
	var map_b := flat_map(10)
	for c in map_b.cells.keys():
		var x := Hex.to_world(c).x
		map_b.cells[c].level = clampi(int(floor((x - 1.0) / 2.5)) + 1, 0, 3) if x > 1.0 else 0
	new_world(map_b)
	var top_cell := Vector2i(5, 0)
	hero = add_hero(top_cell, map_b.get_cell(top_cell).level)
	brute = MonsterFactory.spawn("brute", Vector2i(-1, 0))
	brute.aggro(hero)
	var slams := [0]
	brute.slammed.connect(func(_p: Vector3): slams[0] += 1)
	await wait_until(func() -> bool: return hero.hp < 100.0, 900)
	check(hero.hp < 100.0, "brute climbed the steps and slammed the hero (hp %.1f)" % hero.hp)
	check(brute.global_position.y > 0.5, "brute is up the steps (y=%.2f)" % brute.global_position.y)
	check(slams[0] >= 1, "slammed(pos) signal emitted")

	# --- C: stairs bridging a 4-level gap ----------------------------------------------------
	var map_c := HexMap.new()
	for q in range(-3, 1):
		map_c.set_cell(Vector2i(q, 0), 0)
	map_c.set_stairs(Vector2i(1, 0), 0, 0, 4)
	for q in range(2, 7):
		map_c.set_cell(Vector2i(q, 0), 4)
	new_world(map_c)
	hero = add_hero(Vector2i(4, 0), 4.0)
	brute = MonsterFactory.spawn("brute", Vector2i(-2, 0))
	brute.aggro(hero)
	await wait_until(func() -> bool: return hero.hp < 100.0, 1200)
	check(hero.hp < 100.0, "brute took the stairs and slammed the hero (hp %.1f)" % hero.hp)
	check(brute.global_position.y > 1.5, "brute is on the upper level (y=%.2f)" % brute.global_position.y)
	finish()
