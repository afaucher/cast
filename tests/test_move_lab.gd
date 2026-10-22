extends TestCase
## The movement lab's course (MoveLab, `--move-lab`; docs/design/movement-research.md "As built"): the map has what the doc
## lists (a slalom, a +1 stair run, a 3-level drop, a +2 ledge, a one-wide bridge over lava, a wading pool, a cut-wall
## corridor, a pen with a gate), and a hero walks a whole lap from START to FINISH on foot under each profile (today: the
## slow +2 climb; grounded: hops, the mantle, falls), never over the lava. Prints each profile's lap time for the doc.

const DT := 1.0 / 60.0

var root: Node3D


func setup() -> void:
	timeout_sec = 120.0
	MoveFeel.reset()
	root = Node3D.new()
	add_child(root)
	var m := MoveLab.build_map()
	eq(m.cells_with_tag("start").size(), 1, "one start")
	eq(m.cells_with_tag("exit").size(), 1, "one exit")
	check(m.lava.size() > 30, "a lava field (%d cells)" % m.lava.size())
	eq(m.pools.size(), 1, "a pool")
	check(m.midpoint_walls, "the walls are cut (midpoint walls)")
	var bridge := 0
	for c: Vector2i in m.cells:
		var w := Hex.to_world(c)
		if w.x > MoveLab.BRIDGE_FROM.x - 0.1 and w.x < MoveLab.BRIDGE_TO_X and m.cells[c].level == MoveLab.LEVEL:
			bridge += 1
			var side := 0
			for n in Hex.neighbors(c):
				side += 1 if m.lava.has(n) else 0
			check(side >= 2, "the bridge is one wide (cell %s has lava on %d sides)" % [str(c), side])
	check(bridge >= 8, "a bridge over the lava (%d cells)" % bridge)
	var plan := MoveLab.plan(m, 1)
	check(plan.rooms.has("room:0"), "one room")
	check(not plan.van.is_empty(), "the work van parks on the start pad (its arrival holds the crew until the shared start)")
	var laps := {}
	for feel: String in [MoveFeel.TODAY, MoveFeel.GROUNDED]:
		MoveFeel.set_mode(feel)
		laps[feel] = await _lap()
	print("[lab] lap START -> FINISH on foot: today %.2f s, grounded %.2f s" % [laps["today"], laps["grounded"]])
	MoveFeel.reset()
	finish()


## Walk Wick from START to FINISH along the map's own path (the lava as LavaField leaves it: gone). Returns the lap time.
func _lap() -> float:
	for c in root.get_children():
		c.free()
	var m := MoveLab.build_map()
	for c: Vector2i in m.lava:
		m.remove_cell(c)
	var world := Node3D.new()
	root.add_child(world)
	GameWorld.begin(m, world, 5)
	var start := Hex.from_world(MoveLab.START)
	var h := HeroFactory.spawn_hero(start, "Lapper", Color.BLUE, "sword", null, "wick")
	var pc := HeroFactory.make_player(h, [] as Array[String])
	var pool := Hex.from_world(Vector3(MoveLab.POOL_AT.x, 0, MoveLab.POOL_AT.y))
	var path := m.find_path(start, pool, true, 20000)   # (through the pool, not round it)
	path.append_array(m.find_path(pool, Hex.from_world(MoveLab.FINISH), true, 20000).slice(1))
	if not check(path.size() > 20, "a path from start to finish (%d cells)" % path.size()):
		return -1.0
	var t0 := GameWorld.time
	var i := 1
	var over := false
	var waded := false
	var top := 0.0
	while i < path.size() and GameWorld.time - t0 < 60.0:
		var to := Hex.to_world(path[i]) - h.global_position
		to.y = 0.0
		if to.length() < 0.45:
			i += 1
			continue
		pc.move_override = to.normalized()
		pc.aim_override = h.global_position + to.normalized() * 5.0
		await get_tree().physics_frame
		over = over or is_nan(m.ground_height(h.global_position))
		waded = waded or m.water_at(h.global_position)
		top = maxf(top, h.global_position.y)
	var lap := GameWorld.time - t0
	check(i >= path.size(), "%s: the lap is walked to the finish (%d of %d cells, %.1f s)" % [MoveFeel.active(), i, path.size(), lap])
	check(not over, "%s: never over the lava or a pit" % MoveFeel.active())
	check(waded, "%s: waded through the pool" % MoveFeel.active())
	near(top, (MoveLab.LEVEL + 3) * Hex.LEVEL_HEIGHT, 0.2, "%s: up the stair run to the top" % MoveFeel.active())
	if MoveFeel.active() == MoveFeel.GROUNDED:
		check(h._motion.hops >= 3, "grounded: the stair run is hopped (%d hops)" % h._motion.hops)
		check(h._motion.mantles >= 1, "grounded: the ledge is mantled (%d)" % h._motion.mantles)
		check(h._motion.landings >= 2, "grounded: the drops are fallen (%d landings)" % h._motion.landings)
	world.queue_free()
	return lap
