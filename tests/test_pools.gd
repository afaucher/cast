extends MonsterTestBase
## In-ground pools (docs/design/pool-options.md, "Built"; PoolGeo, HexMap pool cells, HexMapView's inset drawing, PoolView,
## Wading):
##  - generated floors: the indoor pool, science and shark moat rooms get a pool (most of them), deterministic per seed and in the
##    floor checksum; every pool is convex on the midpoint grid (its pool kites are exactly the triangles inside its outline,
##    every corner 120 degrees on a hex centre); the water keeps clear of the doors and corridors, the start, the exit and
##    the elevator, the van, the gates and the employees, with dry deck all round; props, decor, notes, mail and monsters
##    keep to dry floor; a specimen pool's gantry legs are solids on no_stand cells;
##  - walkable: the rim is a one-level step: A* and a walking body get in and out of the water from every side;
##  - wading: 0.75x speed for any actor in the water, dry speed on the deck;
##  - wet: in the water an actor is soaked the whole time and stays soaked DampSpell.DAMP_SOAK seconds after it steps out;
##    wading in puts a fire out and a fireball fizzles on a wader;
##  - networking: only the actor's owner soaks it (a copy is left to the owner's NetStatus announcement);
##  - AI: an ally follows its leader through the pool, a monster chases across it, an employee follows through it;
##  - view: HexMapView builds the pool floor, the liner and PoolView's water and coping.
##  - MOAT (the shark moat: a ring of water round an island; a convex "shark pool" in the moat's look where no ring
##    fits): its water cells form one closed ring round a dry island,
##    one body of water with no rim, liner or step across it (every rim line lies on the outline or the island's rim),
##    both rims convex with 120-degree corners on hex centres, the channel one row wide; walkable in and out over every
##    outer and island edge (A* and a walking body reach the island and leave it); the wading and wet rules apply in the
##    channel; its two fins patrol the channel, in the water all the way round.

const RUN_SEEDS: Array[int] = [1, 2, 3, 4, 5, 7, 42]
const DT := 1.0 / 60.0

var _pools := 0
var _pool_rooms := 0
var _moats := 0
var _shark_pools := 0


func setup() -> void:
	timeout_sec = 240.0
	_check_generated()
	_check_determinism()
	_check_rules()
	await _check_walk_in_out()
	await _check_speed()
	await _check_wet()
	await _check_fire()
	await _check_owner_only()
	await _check_ai()
	await _check_site_spawn()
	_check_view()
	await _check_moat()
	print("pools: %d pools (%d moat rings, %d shark pools) in %d pool rooms over the generated floors" % [_pools, _moats, _shark_pools, _pool_rooms])
	check(_moats >= 5, "the generated floors have moats to check (%d)" % _moats)
	finish()


# --- a synthetic pool room ---------------------------------------------------------------------------------------

## One round room (tag room:0) with walls round it, midpoint-cut, and its pool carved by PoolGeo (look of `theme`).
## Returns [map, plan].
func _pool_world(theme: String = "pool", radius: int = 9) -> Array:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 0).tag = "room:0"
	for c in Hex.ring(Vector2i.ZERO, radius + 1):
		m.set_cell(c, 3, HexMap.Tile.WALL)
	m.cut_walls()
	var p := SitePlan.new()
	SiteBuilder._index_rooms(m, p)
	p.room_themes = {"room:0": theme}
	PoolGeo.carve(m, p, {}, {}, 11)
	return [m, p]


func _pool(m: HexMap) -> Dictionary:
	return m.pools[0] if not m.pools.is_empty() else {}


## A deck point just outside the middle of outline edge i (`out` world units from the rim), and the edge's outward normal.
func _edge_out(rec: Dictionary, i: int, out: float) -> Array:
	var ol: Array = rec["outline"]
	var a: Vector2 = ol[i]
	var b: Vector2 = ol[(i + 1) % ol.size()]
	var n: Vector2 = PoolGeo.edge_normals(ol)[i]
	var p := (a + b) * 0.5 + n * out
	return [Vector3(p.x, 0.0, p.y), Vector3(n.x, 0.0, n.y)]


# --- generated floors ----------------------------------------------------------------------------------------------

func _check_generated() -> void:
	var worst_center := 0.0
	for id in ClientArchetype.IDS:
		for s in RUN_SEEDS:
			var run := ContractRun.make(id, s, float(s % 10) / 10.0 + 0.05)
			var catalog := PricedProp.catalog(run.site_type)
			for f in range(1, ContractRun.FLOOR_COUNT + 1):
				var map := DungeonGen.for_run(run, f)
				var plan := SiteBuilder.plan(map, run, f, catalog)
				var tag := "%s/%d floor %d" % [id, s, f]
				for rt: String in plan.room_themes:
					if PoolGeo.THEME_LOOK.has(plan.theme_of(rt)):
						_pool_rooms += 1
				for rec in map.pools:
					_pools += 1
					eq(str(rec["look"]), String(PoolGeo.THEME_LOOK[plan.theme_of(str(rec["room"]))]), "%s: the pool's look is its room's" % tag)
					_check_pool(map, plan, rec, tag)
					worst_center = maxf(worst_center, (rec["center"] as Vector2).distance_to(ThemeGeo.world(plan.centers[str(rec["room"])])))
				# props, decor, notes and mail keep to dry floor
				for pr in plan.props:
					check(not _wet_footprint(map, pr["pos"], pr["yaw"], (pr["foot"] as Vector2).x, (pr["foot"] as Vector2).y), "%s: priced %s stands on dry floor" % [tag, pr["kind"]])
				for dc in plan.decor:
					check(not _wet_footprint(map, dc["pos"], dc["yaw"], float(dc["w"]), float(dc["d"])), "%s: decor %s stands on dry floor" % [tag, dc["kind"]])
					check(String(dc["kind"]) != "pool_basin", "%s: the flat pool decal is gone" % tag)
				for nt in plan.notes:
					check(not map.is_pool_cell(nt["cell"]), "%s: a note lies on dry floor" % tag)
				for pk in plan.packages:
					check(not map.is_pool_cell(pk["cell"]), "%s: a mail stack stands on dry floor" % tag)
	check(_pool_rooms > 20, "the floors have pool rooms to check (%d)" % _pool_rooms)
	check(float(_pools) >= 0.85 * float(_pool_rooms), "most pool rooms get their pool (%d of %d)" % [_pools, _pool_rooms])
	check(worst_center <= PoolGeo.MAX_CENTER_DIST + 0.01, "pools stand near their room's middle (worst %.1f)" % worst_center)


func _wet_footprint(map: HexMap, pos: Vector2, yaw: float, w: float, d: float) -> bool:
	for p in ThemeGeo.foot_points(pos, yaw, w, d):
		if map.water_at(Vector3(p.x, 0.0, p.y)) or map.is_pool_cell(Hex.from_world(Vector3(p.x, 0.0, p.y))):
			return true
	return false


func _check_pool(map: HexMap, plan: SitePlan, rec: Dictionary, tag: String) -> void:
	var room := str(rec["room"])
	var base: int = int(plan.base_levels[room])
	var label := "%s %s pool" % [tag, room]
	eq(int(rec["deck_level"]), base, "%s: its deck is the room's floor" % label)
	eq(int(rec["floor_level"]), base - PoolGeo.DROP, "%s: its floor is one step down" % label)
	near(float(rec["surface_y"]) - float(rec["floor_level"]) * Hex.LEVEL_HEIGHT, HexMap.WATER_DEPTH, 0.001, "%s: wading depth" % label)
	var outline: Array = rec["outline"]
	var poly := PackedVector2Array(outline)
	var hole_a: Array = rec.get("hole", [])
	var hole := PackedVector2Array(hole_a)
	if not hole.is_empty():
		eq(str(rec["look"]), PoolGeo.LOOK_MOAT, "%s: only a moat has an island" % label)
	# convex, every corner a 120-degree turn on a hex centre, every edge along a midpoint line (0 / 60 / 120 degrees);
	# a moat's island the same
	var rims: Array = [outline, hole_a] if not hole.is_empty() else [outline]
	for ri in rims.size():
		var rim: Array = rims[ri]
		var rl := label + (" island" if ri == 1 else "")
		check(PoolGeo.area(PackedVector2Array(rim)) > 0.0, "%s: the outline winds counter-clockwise" % rl)
		for i in rim.size():
			var a: Vector2 = rim[(i - 1 + rim.size()) % rim.size()]
			var b: Vector2 = rim[i]
			var c: Vector2 = rim[(i + 1) % rim.size()]
			var turn := rad_to_deg((b - a).angle_to(c - b))
			near(turn, 60.0, 0.5, "%s: corner %d turns 60 degrees (a 120-degree corner)" % [rl, i])
			var hc := Hex.to_world(Hex.from_world(Vector3(b.x, 0.0, b.y)))
			check(Vector2(hc.x, hc.z).distance_to(b) < 0.001, "%s: corner %d is on a hex centre" % [rl, i])
			var ang := fposmod(rad_to_deg((c - b).angle()), 60.0)
			check(ang < 0.5 or ang > 59.5, "%s: edge %d runs along a midpoint line" % [rl, i])
	if not hole.is_empty():
		var normals := PoolGeo.edge_normals(outline)
		for i in hole.size():
			check(Geometry2D.is_point_in_polygon(hole[i], poly), "%s: island corner %d lies inside the outline" % [label, i])
			for e: int in [(i - 1 + outline.size()) % outline.size(), i]:
				near(((outline[e] as Vector2) - hole[i]).dot(normals[e]), PoolGeo.ROW, 0.001, "%s: the channel is one row wide at island corner %d" % [label, i])
	# the pool kites are exactly the triangles inside the outline; basin cells wholly inside, at the pool floor
	for bc: Vector2i in (rec["basin"] as Array):
		var cell: HexMap.Cell = map.cells[bc]
		check(cell.pool_mask == HexMap.ALL_KITES and cell.level == base - PoolGeo.DROP, "%s: basin cell %s is pool floor" % [label, bc])
	for rc: Vector2i in (rec["ring"] as Array):
		var cell: HexMap.Cell = map.cells[rc]
		check(cell.pool_mask != 0 and cell.pool_mask != HexMap.ALL_KITES and cell.level == base and cell.wall_mask == 0,
				"%s: ring cell %s is cut between deck and pool" % [label, rc])
		for k in 6:
			var tri := (_xz(Hex.to_world(rc)) + _xz(Hex.to_world(rc + Hex.DIRS[k])) + _xz(Hex.to_world(rc + Hex.DIRS[(k + 1) % 6]))) / 3.0
			var inside := Geometry2D.is_point_in_polygon(tri, poly) and (hole.is_empty() or not Geometry2D.is_point_in_polygon(tri, hole))
			eq(inside, (cell.pool_mask >> k) & 1 == 1, "%s: kite %d of %s is pool exactly inside the outline (and outside an island)" % [label, k, rc])
			# the same triangle has the same state in all its cells
			var nb: Vector2i = rc + Hex.DIRS[k]
			var nbc: HexMap.Cell = map.cells.get(nb)
			if nbc != null:
				eq(nbc.pool_mask >> ((k + 2) % 6) & 1, (cell.pool_mask >> k) & 1, "%s: kite masks agree round the triangle" % label)
	# clear of the doors, corridors, start, exit, elevator, van, gates and employees; dry deck all round
	var wet: Array[Vector2i] = []
	wet.append_array(rec["basin"])
	wet.append_array(rec["ring"])
	var keep := {}
	for c in ElevatorGeo.keep_cells(plan.elevator):
		keep[c] = true
	var van_cells := {}
	for c: Vector2i in (plan.van.get("cells", []) as Array):
		van_cells[c] = true
	for c in wet:
		var cl := "%s: water cell %s" % [label, c]
		eq(map.cells[c].tag, room, "%s is in its room" % cl)
		check(Hex.distance(c, plan.start) > SiteBuilder.START_CLEAR, "%s keeps off the start" % cl)
		check(Hex.distance(c, plan.exit) > SiteBuilder.EXIT_CLEAR, "%s keeps off the exit (the elevator's landing)" % cl)
		check(not keep.has(c), "%s keeps off the elevator" % cl)
		check(not van_cells.has(c), "%s keeps off the van" % cl)
		for d in Hex.range_cells(c, SiteBuilder.CORRIDOR_CLEAR):
			check(map.get_cell(d) == null or map.get_cell(d).tag != "corridor", "%s keeps off the doors and corridors" % cl)
		for g in plan.gates:
			check(Hex.distance(c, g["cell"]) > (PoolGeo.ORIGIN_GATE_CLEAR if bool(g["origin"]) else PoolGeo.GATE_CLEAR), "%s keeps clear of the hellgate" % cl)
		for e in plan.employees:
			check(Hex.distance(c, e["cell"]) >= PoolGeo.EMPLOYEE_CLEAR, "%s keeps clear of an employee" % cl)
		for d in Hex.DIRS:
			var nb: HexMap.Cell = map.cells.get(c + d)
			check(nb != null and nb.type == HexMap.Tile.FLOOR and (nb.level == base or nb.pool_mask != 0) and nb.tag == room,
					"%s has the room's floor round it" % cl)
	# the walk ring: dry deck all round, not under a set piece except the gantry's legs
	var gantry: Dictionary = rec["gantry"]
	if str(rec["look"]) == PoolGeo.LOOK_SPECIMEN:
		check(not gantry.is_empty(), "%s: a specimen pool has its gantry" % label)
		for lc: Vector2i in (gantry.get("legs", []) as Array):
			check(map.no_stand.has(lc), "%s: a gantry leg's cell is no_stand" % label)
			check(map.blocks_point(Hex.to_world(lc)), "%s: a gantry leg blocks bodies" % label)
			check(not map.is_pool_cell(lc), "%s: a gantry leg stands on the deck" % label)
	elif str(rec["look"]) == PoolGeo.LOOK_POOL:
		check(gantry.is_empty() and not (rec["ladder"] as Dictionary).is_empty(), "%s: an indoor pool has a ladder, no gantry" % label)
	else:
		check(gantry.is_empty() and (rec["ladder"] as Dictionary).is_empty(), "%s: a moat has no ladder and no gantry" % label)
		if not hole.is_empty():
			_moats += 1
			_check_ring(map, rec, label)
		else:
			# no ring fitted: a shark pool, its fins circling inside the rim
			_shark_pools += 1
			var loop := PoolGeo.channel(rec)
			var dry_pts := 0
			for k in loop.size():
				var p: Vector2 = loop[k].lerp(loop[(k + 1) % loop.size()], 0.5)
				if not map.water_at(Vector3(loop[k].x, 0.0, loop[k].y)) or not map.water_at(Vector3(p.x, 0.0, p.y)):
					dry_pts += 1
			check(loop.size() >= 3 and dry_pts == 0, "%s: a shark pool's fins circle in the water" % label)


static func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## The same seed carves the same pools (the map checksum agrees); another seed carves others.
func _check_determinism() -> void:
	var seen := 0
	for s in [4, 5, 7]:
		var run := ContractBoard.run_for_seed(s)
		for f in range(1, 4):
			var a := DungeonGen.for_run(run, f)
			var b := DungeonGen.for_run(run, f)
			SiteBuilder.plan(a, run, f, PricedProp.catalog(run.site_type))
			SiteBuilder.plan(b, run, f, PricedProp.catalog(run.site_type))
			eq(NetFloor.map_text_of(a), NetFloor.map_text_of(b), "seed %d floor %d: the same pools every time" % [s, f])
			seen += a.pools.size()
			# planning twice on one map keeps its pool (no second carve)
			var n := a.pools.size()
			SiteBuilder.plan(a, run, f, PricedProp.catalog(run.site_type))
			eq(a.pools.size(), n, "seed %d floor %d: a second plan keeps the pools" % [s, f])
	check(seen > 0, "the determinism seeds have pools (%d)" % seen)
	# the checksum sees a pool: drop one cell's pool kites and the map text changes
	var run2 := ContractBoard.run_for_seed(4)
	var m := DungeonGen.for_run(run2, 1)
	SiteBuilder.plan(m, run2, 1, PricedProp.catalog(run2.site_type))
	if check(not m.pools.is_empty(), "seed 4 floor 1 has a pool"):
		var before := NetFloor.map_text_of(m)
		var rc: Vector2i = (m.pools[0]["ring"] as Array)[0]
		var keep: int = m.cells[rc].pool_mask
		m.cells[rc].pool_mask = 0
		check(NetFloor.map_text_of(m) != before, "the floor checksum covers the pool kites")
		m.cells[rc].pool_mask = keep
	check(HexMap.new().net_fields().get("pools", -1) == Net.SPAWN, "HexMap.pools is spawn data")


# --- the rules ------------------------------------------------------------------------------------------------------

func _check_rules() -> void:
	var w := _pool_world()
	var m: HexMap = w[0]
	var rec := _pool(m)
	if not check(not rec.is_empty(), "the synthetic room gets a pool"):
		return
	# every step across the rim is a walk, both ways; the rim is not a wall
	var n := (rec["outline"] as Array).size()
	for i in n:
		var e := _edge_out(rec, i, 0.2)
		var dry: Vector3 = e[0]
		var wet: Vector3 = dry - (e[1] as Vector3) * 0.4
		check(not m.water_at(dry) and m.water_at(wet), "edge %d: water inside the rim, dry deck outside" % i)
		eq(m.movement_check(dry, wet), HexMap.Move.OK, "edge %d: stepping down into the water is a walk" % i)
		eq(m.movement_check(wet, dry), HexMap.Move.OK, "edge %d: stepping up out of it is a walk" % i)
		check(not m.blocks_point(dry, 0.4) and not m.blocks_point(wet, 0.4), "edge %d: the rim is no wall" % i)
		near(m.ground_height(wet), float(rec["floor_level"]) * Hex.LEVEL_HEIGHT, 0.001, "edge %d: the pool floor is one level down" % i)
		near(m.water_surface(wet), float(rec["surface_y"]), 0.001, "edge %d: the water surface" % i)
		check(is_nan(m.water_surface(dry)), "edge %d: no water on the deck" % i)
	# every pool cell is a full cell and a path node; paths cross the pool and leave it on every side
	for c: Vector2i in (rec["basin"] as Array) + (rec["ring"] as Array):
		check(m.is_walkable_cell(c), "pool cell %s is a full cell (a path node)" % c)
	var mid: Vector2i = (rec["basin"] as Array)[0]
	for i in n:
		var out := Hex.from_world(_edge_out(rec, i, 2.4)[0])
		check(not m.find_path(out, mid, false).is_empty(), "A* (no climbing) gets into the pool from edge %d" % i)
		check(not m.find_path(mid, out, false).is_empty(), "A* gets out of the pool over edge %d" % i)


## A body walking straight at the water from just outside each edge gets in, then walks back out the same way.
func _check_walk_in_out() -> void:
	var w := _pool_world()
	new_world(w[0])
	var m: HexMap = w[0]
	var rec := _pool(m)
	var a := Actor.new()
	a.team = GameWorld.TEAM_MONSTERS
	a.move_speed = 4.0
	GameWorld.spawn(a, Vector3.ZERO)
	await frames(2)
	var n := (rec["outline"] as Array).size()
	for i in n:
		var e := _edge_out(rec, i, 1.2)
		var start: Vector3 = e[0]
		var nrm: Vector3 = e[1]
		a.global_position = start
		a.snap_to_ground()
		var got_in := false
		for _f in 90:
			a.move(-nrm, DT)
			if m.water_at(a.global_position):
				got_in = true
				break
		check(got_in, "edge %d: a body walks into the water" % i)
		for _f in 30:
			a.move(-nrm, DT)
		check(a.global_position.y < -0.3, "edge %d: and down onto the pool floor (y %.2f)" % [i, a.global_position.y])
		var got_out := false
		for _f in 240:
			a.move(nrm, DT)
			if not m.water_at(a.global_position) and GameWorld.flat_distance(a.global_position, start) < 1.0:
				got_out = true
				break
		check(got_out, "edge %d: and walks back out onto the deck" % i)
		for _f in 20:
			a.move(nrm * 0.01, DT)
		near(a.global_position.y, 0.0, 0.05, "edge %d: back up on the deck" % i)
	a.queue_free()
	await frames(2)


## Wading is 0.75x for any actor, dry speed on the deck; moving speeds match.
func _check_speed() -> void:
	var w := _pool_world()
	new_world(w[0])
	var m: HexMap = w[0]
	var rec := _pool(m)
	var c: Vector2 = rec["center"]
	var a := Actor.new()
	a.move_speed = 4.0
	GameWorld.spawn(a, Vector3(c.x, 0.0, c.y))
	await frames(1)
	a.snap_to_ground()
	near(Wading.SPEED_MULT, 0.75, 0.0001, "wading is three quarters speed")
	near(a.effective_speed(), 4.0 * Wading.SPEED_MULT, 0.001, "in the water an actor walks at 0.75x")
	var ax: Vector2 = rec["axis"]
	var from := a.global_position
	for _f in 20:
		a.move(Vector3(ax.x, 0.0, ax.y), DT)
	near(GameWorld.flat_distance(from, a.global_position), 4.0 * Wading.SPEED_MULT * 20.0 * DT, 0.02, "and covers 0.75x the ground")
	var dry := _edge_out(rec, 0, 2.0)[0] as Vector3
	a.global_position = dry
	a.snap_to_ground()
	near(a.effective_speed(), 4.0, 0.001, "on the deck it walks at full speed")
	# coffee and the water stack (the modifiers multiply)
	a.global_position = Vector3(c.x, 0.0, c.y)
	a.set_modifier("coffee_test", 1.6, 5.0, Actor.STAT_MOVE_SPEED)
	near(a.effective_speed(), 4.0 * 1.6 * Wading.SPEED_MULT, 0.001, "a hasted wader is hasted and slowed")
	a.queue_free()
	await frames(1)


## Wet the whole time in the water and DAMP_SOAK seconds after leaving it. GameWorld.time is stepped by hand (Wading.tick
## between steps), so the 15 s run in a moment.
func _check_wet() -> void:
	var w := _pool_world()
	new_world(w[0])
	var m: HexMap = w[0]
	var rec := _pool(m)
	var c: Vector2 = rec["center"]
	var a := Actor.new()
	a.team = GameWorld.TEAM_HEROES
	GameWorld.spawn(a, _edge_out(rec, 0, 2.0)[0])
	await frames(2)
	check(not Wet.is_wet(a), "dry on the deck")
	a.global_position = Vector3(c.x, 0.0, c.y)
	a.snap_to_ground()
	Wading.tick()
	check(Wet.is_wet(a), "wet as soon as it is in the water")
	near(Wet.remaining(a), DampSpell.DAMP_SOAK, 0.05, "soaked for the full damp time")
	check(a.get_node_or_null("Wet") != null, "dripping (the Damp spell's status node)")
	check(a.get_node_or_null(Wading.RIPPLE_NAME) != null, "a ripple ring round the wader")
	var t0 := GameWorld.time
	var stayed := true
	for _i in 100:   # 25 s in the water
		GameWorld.time += 0.25
		Wading.tick()
		stayed = stayed and Wet.is_wet(a)
	check(stayed, "wet the whole time it stays in the water (%.0f s)" % (GameWorld.time - t0))
	a.global_position = _edge_out(rec, 0, 2.0)[0]
	a.snap_to_ground()
	Wading.tick()
	near(Wet.remaining(a), DampSpell.DAMP_SOAK, 0.05, "stepping out it is wet for the full damp time from then")
	await frames(1)
	check(a.get_node_or_null(Wading.RIPPLE_NAME) == null or a.get_node(Wading.RIPPLE_NAME).is_queued_for_deletion(), "no ripple on the deck")
	var out_t := GameWorld.time
	GameWorld.time = out_t + DampSpell.DAMP_SOAK - 0.2
	Wading.tick()
	check(Wet.is_wet(a), "still wet just before the damp time runs out")
	GameWorld.time = out_t + DampSpell.DAMP_SOAK + 0.2
	Wading.tick()
	check(not Wet.is_wet(a), "dry once the damp time is over")
	a.queue_free()
	await frames(1)


## Wading in puts a fire out; a fireball fizzles on a wader.
func _check_fire() -> void:
	var w := _pool_world()
	new_world(w[0])
	var m: HexMap = w[0]
	var rec := _pool(m)
	var c: Vector2 = rec["center"]
	var a := Actor.new()
	a.team = GameWorld.TEAM_HEROES
	a.max_hp = 200.0
	GameWorld.spawn(a, _edge_out(rec, 0, 2.0)[0])
	await frames(2)
	check(Burning.ignite(a, null, 8.0) != null, "it catches fire on the deck")
	await frames(2)
	check(Burning.is_burning(a), "burning")
	a.global_position = Vector3(c.x, 0.0, c.y)
	a.snap_to_ground()
	await frames(2)   # (GameWorld ticks the water itself)
	check(not Burning.is_burning(a), "wading in puts the fire out")
	check(Wet.is_wet(a) and not Burning.can_burn(a), "and it cannot catch fire while wet")
	check(Burning.on_blast(a.global_position, 3.0, 1.0, null).is_empty(), "a fireball fizzles on a wader")
	a.queue_free()
	await frames(1)


## Only the owner soaks: a copy of someone else's actor is not doused here (its owner's NetStatus "soak" shows it).
func _check_owner_only() -> void:
	var w := _pool_world()
	new_world(w[0])
	var rec := _pool(w[0])
	var c: Vector2 = rec["center"]
	var mine := Actor.new()
	var theirs := Actor.new()
	GameWorld.spawn(mine, Vector3(c.x, 0.0, c.y))
	GameWorld.spawn(theirs, Vector3(c.x + 0.6, 0.0, c.y))
	Net.make_copy(theirs)
	await frames(1)
	Wading.tick()
	check(Net.resolves(mine) and Wet.is_wet(mine), "this machine soaks the wader it owns")
	check(not Net.resolves(theirs) and not Wet.is_wet(theirs), "... and leaves a copy to its owner")
	check(theirs.get_node_or_null(Wading.RIPPLE_NAME) != null, "the ripple is cosmetic: every machine draws it")
	check(Wading.speed_mult(theirs.global_position) == Wading.SPEED_MULT, "the slowdown is a function of the position and the map (LOCAL)")
	mine.queue_free()
	theirs.queue_free()
	await frames(1)


## The AI: an ally follows its leader through the water, a monster chases a hero across the pool, an employee follows.
func _check_ai() -> void:
	var w := _pool_world("pool", 10)
	var m: HexMap = w[0]
	new_world(m)
	var rec := _pool(m)
	var ax: Vector2 = rec["axis"]
	var c: Vector2 = rec["center"]
	var nrm := Vector2(-ax.y, ax.x)
	var side_a := c + nrm * (float(rec["half_wid"]) + 2.2)
	var side_b := c - nrm * (float(rec["half_wid"]) + 2.2)
	# an ally follows a leader who walks straight across the pool
	var leader := HeroFactory.spawn_hero(Hex.from_world(Vector3(side_a.x, 0, side_a.y)), "Leader", Color.WHITE)
	var ally := HeroFactory.spawn_hero(Hex.from_world(Vector3(side_a.x, 0, side_a.y) + Vector3(nrm.x, 0, nrm.y) * 1.8), "Rebar", Color.WHITE)
	HeroFactory.make_ally(ally, leader, false, 0.0, 2.6)
	await frames(30)
	var waded := false
	for _f in 240:
		var to := Vector3(side_b.x, 0, side_b.y) - leader.global_position
		to.y = 0.0
		if to.length() > 0.2:
			leader.move(to.normalized(), DT)
		waded = waded or m.water_at(ally.global_position)
		await get_tree().physics_frame
	for _f in 240:
		waded = waded or m.water_at(ally.global_position)
		await get_tree().physics_frame
	check(m.water_at(Vector3(c.x, 0, c.y)), "the pool lies between the two sides")
	check(GameWorld.flat_distance(leader.global_position, Vector3(side_b.x, 0, side_b.y)) < 0.5, "the leader waded across")
	check(GameWorld.flat_distance(ally.global_position, leader.global_position) < 4.5, "the ally followed the leader across (%.1f)" % GameWorld.flat_distance(ally.global_position, leader.global_position))
	check(not m.water_at(ally.global_position), "... and out of the water again")
	print("pools: the ally %s on its way across" % ("waded" if waded else "walked round the pool"))
	leader.queue_free()
	ally.queue_free()
	await frames(2)
	# a monster chases a hero standing across the pool
	var hero := add_hero(Hex.from_world(Vector3(side_b.x, 0, side_b.y)))
	var grunt := MonsterFactory.spawn("grunt", Hex.from_world(Vector3(side_a.x, 0, side_a.y)))
	var reached := await wait_until(func() -> bool: return fdist(grunt, hero) < 2.2, 60 * 12)
	check(reached, "a grunt chases a hero across the pool (dist %.1f)" % fdist(grunt, hero))
	grunt.queue_free()
	hero.queue_free()
	await frames(2)
	# an employee follows a hero who steps across the pool
	var emp := Employee.spawn(Hex.from_world(Vector3(side_a.x, 0, side_a.y)), {"style": "staff"})
	var h2 := add_hero(Hex.from_world(Vector3(side_a.x, 0, side_a.y) + Vector3(nrm.x, 0, nrm.y) * 1.5))
	await frames(2)
	check(emp.request_follow(h2), "the employee latches on")
	h2.global_position = Vector3(side_b.x, 0.0, side_b.y)
	h2.snap_to_ground()
	var followed := await wait_until(func() -> bool: return fdist(emp, h2) < Employee.FOLLOW_MAX + 0.4, 60 * 12)
	check(followed, "an employee follows its hero across the pool (dist %.1f)" % fdist(emp, h2))
	emp.queue_free()
	h2.queue_free()
	await frames(2)


## A whole site with a pool: its monsters spawn on dry floor.
func _check_site_spawn() -> void:
	var run := ContractBoard.run_for_seed(4)
	var map := DungeonGen.for_run(run, 1)
	new_world(map)
	Ledger.begin_contract(1000000)
	var site := SiteBuilder.build(map, run, 1)
	check(not map.pools.is_empty(), "the site has a pool")
	for mo in site.monsters:
		if is_instance_valid(mo):
			check(not map.is_pool_cell(Hex.from_world(mo.global_position)), "monster %s spawned on dry floor" % mo.display_name)
	await frames(2)
	world.free()
	world = null
	GameWorld.end()


## HexMapView draws the pool: tiled pool floor and liner surfaces, PoolView's water and coping per pool, a gantry over a
## specimen pool, a ladder by an indoor pool.
func _check_view() -> void:
	for theme in ["pool", "science", "moat"]:
		var w := _pool_world(theme)
		var m: HexMap = w[0]
		var view := HexMapView.new()
		view.build(m)
		check(view.pool_view != null, "%s: the view has a pool layer" % theme)
		if view.pool_view != null:
			eq(view.pool_view.waters.size(), m.pools.size(), "%s: a water surface per pool" % theme)
			eq(view.pool_view.copings.size(), m.pools.size(), "%s: a coping per pool" % theme)
			var dressing := {"pool": "Ladder", "science": "Gantry", "moat": "Fin0"}
			check(view.pool_view.get_node_or_null(String(dressing[theme])) != null, "%s: its dressing" % theme)
			eq(view.pool_view.fins.size(), 2 if theme == "moat" else 0, "%s: shark fins in a moat only" % theme)
			var wm := view.pool_view.waters[0].material_override as ShaderMaterial
			var alpha := float(wm.get_shader_parameter("alpha"))
			check(alpha >= 0.55 and alpha <= 0.7, "%s: the water is translucent (alpha %.2f)" % [theme, alpha])
		var pool_surf := false
		for s in view.mesh_instance.mesh.get_surface_count():
			var sm := view.mesh_instance.mesh.surface_get_material(s) as ShaderMaterial
			if sm != null and sm.shader != null and sm.shader.code == HexMapView.POOL_SHADER:
				pool_surf = true
		check(pool_surf, "%s: the terrain mesh has the tiled pool floor and liner" % theme)
		view.free()


# --- the moat ---------------------------------------------------------------------------------------------------------

## The ring of a moat record: its water cells are one connected ring, closed round a dry island (the island's dry cells
## reach the room's floor only across water), one body of water: the channel's middle line is water all the way round
## at one surface, and every rim line (a spoke where a cell's kites change between deck and pool) lies on the outline or
## on the island's rim, so there is no rim, liner or step anywhere across the water.
func _check_ring(map: HexMap, rec: Dictionary, label: String) -> void:
	var wet := {}
	for c: Vector2i in (rec["basin"] as Array) + (rec["ring"] as Array):
		wet[c] = true
	# connected
	var start: Vector2i = wet.keys()[0]
	var seen := {start: true}
	var todo: Array[Vector2i] = [start]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d in Hex.DIRS:
			if wet.has(c + d) and not seen.has(c + d):
				seen[c + d] = true
				todo.append(c + d)
	eq(seen.size(), wet.size(), "%s: the water cells are one connected ring" % label)
	# closed: the dry cells inside never reach the dry cells outside
	var hole := PackedVector2Array(rec["hole"] as Array)
	var outline := PackedVector2Array(rec["outline"] as Array)
	var island: Array[Vector2i] = []
	for c: Vector2i in map.cells:
		if not wet.has(c) and Geometry2D.is_point_in_polygon(_xz(Hex.to_world(c)), hole):
			island.append(c)
	if check(not island.is_empty(), "%s: a dry island in the middle" % label):
		var reach := {island[0]: true}
		var q: Array[Vector2i] = [island[0]]
		var escaped := false
		while not q.is_empty() and not escaped:
			var c: Vector2i = q.pop_back()
			for d in Hex.DIRS:
				var nb: Vector2i = c + d
				if wet.has(nb) or reach.has(nb) or not map.cells.has(nb):
					continue
				if not Geometry2D.is_point_in_polygon(_xz(Hex.to_world(nb)), outline):
					escaped = true
				reach[nb] = true
				q.append(nb)
		check(not escaped, "%s: the ring is closed (the island meets the room's floor only across water)" % label)
	# one body of water: the channel's middle is wet all the way round, at one surface
	var path := PoolGeo.channel(rec)
	var total := 0.0
	for i in path.size():
		total += path[i].distance_to(path[(i + 1) % path.size()])
	var dry_pts := 0
	for k in 200:
		var p: Vector2 = DecorAnim.path_pose(path, total, total * float(k) / 200.0)[0]
		var p3 := Vector3(p.x, 0.0, p.y)
		if not map.water_at(p3) or absf(map.water_surface(p3) - float(rec["surface_y"])) > 0.001:
			dry_pts += 1
	eq(dry_pts, 0, "%s: the channel is water all the way round, at one surface" % label)
	# no rim across the water: every deck / pool change lies on the outline or on the island's rim
	var off := 0
	for c: Vector2i in wet:
		var m: int = map.cells[c].pool_mask
		for d in 6:
			if ((m >> d) & 1) == ((m >> posmod(d - 1, 6)) & 1):
				continue
			var mid := _xz(Hex.to_world(c) + Hex.edge_mid(d) * 0.5)
			if _dist_to_rim(mid, rec["outline"]) > 0.001 and _dist_to_rim(mid, rec["hole"]) > 0.001:
				off += 1
	eq(off, 0, "%s: no rim, liner or step inside the water (every rim line is on the outline or the island's rim)" % label)


static func _dist_to_rim(p: Vector2, rim: Array) -> float:
	var best := INF
	for i in rim.size():
		var a: Vector2 = rim[i]
		var b: Vector2 = rim[(i + 1) % rim.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## A synthetic moat room: the ring, a step in and out over every outer and island edge, A* to the island and back, a
## body wading across the channel onto the island and back off it (slowed and soaked on the way), the fins.
func _check_moat() -> void:
	for radius in [7, 9]:
		var w := _pool_world("moat", radius)
		var m: HexMap = w[0]
		var rec := _pool(m)
		if not check(not rec.is_empty() and str(rec["look"]) == PoolGeo.LOOK_MOAT, "moat room %d: the moat is carved" % radius):
			continue
		_check_ring(m, rec, "moat room %d" % radius)
		eq((rec["hole"] as Array).size(), 6, "moat room %d: a hexagonal island" % radius)
	var w2 := _pool_world("moat", 9)
	var map: HexMap = w2[0]
	var mo := _pool(map)
	if mo.is_empty():
		return
	var outline: Array = mo["outline"]
	var hole: Array = mo["hole"]
	var ctr: Vector2 = mo["center"]
	var island := Hex.from_world(Vector3(ctr.x, 0.0, ctr.y))
	check(not map.water_at(Vector3(ctr.x, 0.0, ctr.y)) and map.is_walkable_cell(island), "the island's middle is dry floor")
	# every edge, outside and round the island: a step down into the water and up out of it
	var steps_ok := 0
	var steps := 0
	for ri in 2:
		var rim: Array = outline if ri == 0 else hole
		var normals := PoolGeo.edge_normals(rim)
		var water_side := -1.0 if ri == 0 else 1.0   # (round the island the water is outside its rim)
		for i in rim.size():
			var mid: Vector2 = ((rim[i] as Vector2) + (rim[(i + 1) % rim.size()] as Vector2)) * 0.5
			var nrm: Vector2 = normals[i] * water_side
			var dry := Vector3(mid.x - nrm.x * 0.3, 0.0, mid.y - nrm.y * 0.3)
			var wet_p := Vector3(mid.x + nrm.x * 0.4, 0.0, mid.y + nrm.y * 0.4)
			steps += 1
			if not map.water_at(dry) and map.water_at(wet_p) and map.movement_check(dry, wet_p) == HexMap.Move.OK \
					and map.movement_check(wet_p, dry) == HexMap.Move.OK and not map.blocks_point(dry, 0.4) and not map.blocks_point(wet_p, 0.4):
				steps_ok += 1
	eq(steps_ok, steps, "every moat edge (outside and round the island) is a step into the water and out (%d of %d)" % [steps_ok, steps])
	# A* (no climbing) from every side of the room to the island and back
	var onormals := PoolGeo.edge_normals(outline)
	for i in outline.size():
		var nrm: Vector2 = onormals[i]
		var mid: Vector2 = ((outline[i] as Vector2) + (outline[(i + 1) % outline.size()] as Vector2)) * 0.5 + nrm * 2.2
		var out := Hex.from_world(Vector3(mid.x, 0.0, mid.y))
		check(not map.find_path(out, island, false).is_empty(), "A* reaches the island from edge %d" % i)
		check(not map.find_path(island, out, false).is_empty(), "A* leaves the island over edge %d" % i)
	# a body walks from the room's floor across the channel onto the island, and back off it
	new_world(map)
	var a := Actor.new()
	a.team = GameWorld.TEAM_HEROES
	a.move_speed = 4.0
	var m0: Vector2 = ((outline[0] as Vector2) + (outline[1] as Vector2)) * 0.5
	var outside := Vector3(m0.x + onormals[0].x * 1.4, 0.0, m0.y + onormals[0].y * 1.4)
	GameWorld.spawn(a, outside)
	await frames(2)
	a.snap_to_ground()
	var to_island := (Vector3(ctr.x, 0.0, ctr.y) - outside).normalized()
	var waded := false
	var slowed := false
	var soaked := false
	var reached := false
	for _f in 400:
		a.move(to_island, DT)
		Wading.tick()
		if map.water_at(a.global_position):
			waded = true
			slowed = slowed or is_equal_approx(a.effective_speed(), 4.0 * Wading.SPEED_MULT)
			soaked = soaked or Wet.is_wet(a)
		if GameWorld.flat_distance(a.global_position, Vector3(ctr.x, 0.0, ctr.y)) < 0.4:
			reached = true
			break
	check(waded and reached, "a body wades across the moat onto the island (waded %s, reached %s)" % [waded, reached])
	check(slowed, "wading in the moat is 0.75x")
	check(soaked, "wading in the moat soaks")
	near(a.global_position.y, float(mo["deck_level"]) * Hex.LEVEL_HEIGHT, 0.05, "up on the island's deck")
	var back := false
	for _f in 400:
		a.move(-to_island, DT)
		Wading.tick()
		if GameWorld.flat_distance(a.global_position, outside) < 0.4:
			back = true
			break
	check(back, "and wades back off the island to the room's floor")
	check(Wet.is_wet(a) and Wet.remaining(a) > DampSpell.DAMP_SOAK - 3.0, "still wet after stepping out of the moat")
	near(a.effective_speed(), 4.0, 0.001, "full speed on the room's floor")
	a.queue_free()
	await frames(1)
	# the fins patrol the channel, in the water all the way
	var view := HexMapView.new()
	view.build(map)
	if check(view.pool_view != null and view.pool_view.fins.size() == 2, "the moat has two fins"):
		var fa: DecorAnim = null
		for ch in view.pool_view.fins[0].get_children():
			if ch is DecorAnim:
				fa = ch
		if check(fa != null and fa.fin_path.size() == 6, "a fin follows the channel's middle line"):
			var total := 0.0
			for i in fa.fin_path.size():
				total += fa.fin_path[i].distance_to(fa.fin_path[(i + 1) % fa.fin_path.size()])
			var out_pts := 0
			for k in 120:
				var p: Vector2 = DecorAnim.path_pose(fa.fin_path, total, total * float(k) / 120.0)[0]
				if not map.water_at(Vector3(p.x, 0.0, p.y)):
					out_pts += 1
			eq(out_pts, 0, "the fin's patrol stays in the water")
			near(fa.fin_y, float(mo["surface_y"]), 0.001, "the fin rides the water surface")
	view.free()
