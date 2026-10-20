extends MonsterTestBase
## The lava cave prototype (docs/design/lava-playtest.md; LavaCave, LavaField; the dev flag --lava-cave):
##   - every layout: a climb-free way from the start to the exit on the two-wide bridges, archers on rock no path reaches,
##     every two-wide row with its lane, the same map every build;
##   - lava is void with a burn: a monster shoved off a bridge dies in it, a hero is pulled back onto the rock with 15
##     damage and burning;
##   - damp crusts the lava: walkable for LavaField.CRUST_LIFE, then it melts, and whoever stands on it gets the lava
##     rule (the hero back on the nearest rock, burned; the monster sinks).


func setup() -> void:
	timeout_sec = 120.0
	_check_layouts()
	await _check_shoves()
	await _check_crust()
	finish()


func _check_layouts() -> void:
	for id in range(1, LavaCave.COUNT + 1):
		var r := LavaCave.check(id)
		check(bool(r["ok"]), "layout %d (%s): %s" % [id, LavaCave.layout(id)["name"], ", ".join(r["problems"]) if not r["ok"] else "ok"])
		var a := LavaCave.build_map(id)
		var b := LavaCave.build_map(id)
		var same := a.cells.size() == b.cells.size()
		for c: Vector2i in a.cells:
			same = same and b.has_cell(c) and a.cells[c].level == b.cells[c].level and a.cells[c].tag == b.cells[c].tag
		check(same, "layout %d builds the same map every time" % id)
		check(not LavaCave.lava_cells(a).is_empty(), "layout %d has lava" % id)
		var p := LavaCave.plan(a, 1)
		check(p.rooms.size() >= 2 and p.start != p.exit, "layout %d: a plan with rooms (%d), a start and an exit" % [id, p.rooms.size()])


## The cave (layout 1) with its LavaField active: returns the field.
func _cave() -> LavaField:
	var m := LavaCave.build_map(1)
	new_world(m)
	var f := LavaField.new()
	world.add_child(f)
	f.setup(m)
	f.activate()
	return f


## A bridge cell of layout 1's causeway and the direction off its near side (into the lava).
func _bridge_edge() -> Array:
	var b: Dictionary = LavaCave.layout(1)["bridges"][0]
	var rows := LavaCave.bridge_rows(b)
	var c: Vector2i = rows[3][0]
	return [c, Hex.dir_vector(5)]


func _check_shoves() -> void:
	var f := _cave()
	check(f.active and not GameWorld.map.has_cell(LavaCave.lava_cells(LavaCave.build_map(1))[0]), "active: the lava cells are void")
	var e := _bridge_edge()
	var cell: Vector2i = e[0]
	var off: Vector3 = e[1]
	var grunt := MonsterFactory.spawn("grunt", cell)
	grunt.aggro_range = 0.0
	await frames(2)
	grunt.shove(off, 3.0, null)
	var gone := await wait_until(func() -> bool: return grunt.dead or not is_instance_valid(grunt), 240)
	check(gone, "a grunt shoved off the bridge falls into the lava and dies")
	var hero := add_hero(cell, float(GameWorld.map.get_cell(cell).level))
	await frames(2)
	var hp0 := hero.hp
	hero.shove(off, 3.0, null)
	var back := await wait_until(func() -> bool: return not hero.is_shoved(), 240)
	check(back, "the hero's shove ends")
	var under := Hex.from_world(hero.global_position)
	check(GameWorld.map.is_walkable_cell(under), "the hero is pulled back onto rock (%s)" % under)
	near(hp0 - hero.hp, 15.0, 1.6, "15 damage (the pull's 5 and the lava's 10; plus a burn tick at most): %.1f" % (hp0 - hero.hp))
	check(Burning.is_burning(hero), "and it burns")
	world.free()
	world = null


func _check_crust() -> void:
	var f := _cave()
	var e := _bridge_edge()
	var cell: Vector2i = e[0]
	var off: Vector3 = e[1]
	var at := Hex.to_world(cell, float(GameWorld.map.get_cell(cell).level))
	var d := Damp.new()
	d.power = 1.0
	GameWorld.spawn(d, at)
	await frames(30)
	check(f.crusts.size() == 1, "a damp at the bridge's edge crusts the lava (%d crusts)" % f.crusts.size())
	var crust_cell := Hex.from_world(at + off * Hex.SQRT3 * 2.0)
	check(GameWorld.map.is_walkable_cell(crust_cell), "the lava two cells off the bridge is crust: walkable")
	check(GameWorld.map.find_path(cell, crust_cell, false).size() > 0, "a path leads onto it")
	var hero := add_hero(crust_cell, float(LavaCave.CRUST_LEVEL))
	var mon := MonsterFactory.spawn("grunt", crust_cell + Hex.DIRS[1])
	mon.aggro_range = 0.0
	var hp0 := hero.hp
	var melted := await wait_until(func() -> bool: return f.crusts.is_empty(), int((LavaField.CRUST_LIFE + 1.0) * 60.0))
	check(melted, "the crust melts after about %.0f s" % LavaField.CRUST_LIFE)
	check(not GameWorld.map.has_cell(crust_cell), "its cells are lava again")
	await wait_until(func() -> bool: return not hero.is_shoved(), 240)
	check(GameWorld.map.is_walkable_cell(Hex.from_world(hero.global_position)), "the hero on the crust is put back on rock")
	check(hp0 - hero.hp >= 14.0, "with the lava's damage (%.1f)" % (hp0 - hero.hp))
	var sunk := await wait_until(func() -> bool: return mon.dead or not is_instance_valid(mon), 240)
	check(sunk, "the grunt on the crust sinks")
	world.free()
	world = null
