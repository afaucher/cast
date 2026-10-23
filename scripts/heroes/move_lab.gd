class_name MoveLab
extends RefCounted
## The movement lab (`--move-lab`; docs/design/movement-research.md §5.2 and "As built"): a hand-built floor laid out for
## feel, played as floor 1 of a contract like the `--lava-cave` prototype (so --move-feel, the crew, the AI allies, the HUD and
## the voice all work as on a real floor). West to east, one lap from START to FINISH:
##   1. the start pad (concrete)
##   2. a slalom of three pillars (carpet): starts, stops, turns
##   3. a +1 stair run, three steps up (wood): hops
##   4. the top (marble), then a 3-level drop (tile): gravity and a big landing
##   5. a +2 ledge (flagstone): the mantle; and a 2-level drop off its far side
##   6. a one-wide bridge at 60 degrees over lava (corridor stone): the edge slide, the stop at the lip
##   7. a wading pool (pool tile deck): the 0.75x stride, wading steps, the rim's step down and up
##   8. a cut-wall corridor at 60 degrees (diamond plate): the wall slide
##   9. the finish pad (concrete), with a grunt and a swarmer in a pen beside it (the gap in its wall is the gate):
##      wind-ups and being chased
## MoveLog times each lap (START to FINISH) per profile into user://move_lab.csv. Built from nothing but this script, so
## every window of a crew builds the same floor (the barrier's checksum agrees); `.\run.ps1 -Crew 2 --net-wait 2 --move-lab` shows a
## teammate's walk on a puppet.

const LEVEL := 2                   ## the course's ground level (the lava, the pool and the drops go below it)
const WALL_LEVEL := 9
const LAVA_BED := -3               ## lava cells sit here until LavaField makes them void
const LAVA_Y := 0.2                ## the lava surface (world units; the rock is at LEVEL x 0.5)
const CRUST_LEVEL := 1
const BOUNDS := Rect2(-8.0, -15.0, 96.0, 30.0)   ## world X/Z of the whole lab (walls round the course)
const START := Vector3(-2.0, 0.0, 0.0)
const FINISH := Vector3(82.0, 0.0, -1.0)
const EXIT := Vector3(85.5, 0.0, 2.0)
const GATE_RADIUS := 2.2
const PILLARS: Array[Vector2] = [Vector2(7.0, -3.0), Vector2(10.5, 2.5), Vector2(14.0, -3.0)]
const BRIDGE_FROM := Vector2(46.6, 7.5)   ## the bridge's first cell; it runs along Hex.DIRS[1] (60 degrees) to BRIDGE_TO_X
const BRIDGE_TO_X := 55.5
const POOL_AT := Vector2(63.0, 0.0)
const CORRIDOR_FROM := Vector2(70.0, 6.0)  ## the corridor's centre line runs at 60 degrees from here ...
const CORRIDOR_DIR := Vector2(0.5, -0.8660254)
const CORRIDOR_HALF := 3.0                 ## ... this far either side
const GRUNT_AT := Vector2(80.5, 9.5)
const SWARMER_AT := Vector2(83.0, 10.5)


## Where the laps start and end (MoveLog).
static func gates() -> Dictionary:
	return {"start": START, "finish": FINISH, "radius": GATE_RADIUS}


## What the course is at world X/Z (x, z): [kind, level, floor material]; kind is "floor", "wall" or "lava".
static func feature(x: float, z: float) -> Array:
	var F := FloorMaterials
	var main := absf(z) <= 7.6
	if x < -6.5 or x > 86.5 or absf(z) > 13.5:
		return ["wall", WALL_LEVEL, F.F_CONCRETE]
	if x < 4.0:
		return ["floor", LEVEL, F.F_CONCRETE] if main else ["wall", WALL_LEVEL, F.F_CONCRETE]
	if x < 18.0:
		return ["floor", LEVEL, F.F_CARPET] if main else ["wall", WALL_LEVEL, F.F_CONCRETE]
	if x < 24.0:
		return ["floor", LEVEL + 1 + int((x - 18.0) / 2.0), F.F_WOOD] if main else ["wall", WALL_LEVEL, F.F_CONCRETE]
	if x < 28.0:
		return ["floor", LEVEL + 3, F.F_MARBLE] if main else ["wall", WALL_LEVEL, F.F_CONCRETE]
	if x < 36.0:
		return ["floor", LEVEL, F.F_TILE] if main else ["wall", WALL_LEVEL, F.F_CONCRETE]
	if x < 42.0:
		return ["floor", LEVEL + 2, F.F_FLAGSTONE] if main else ["wall", WALL_LEVEL, F.F_CONCRETE]
	if x < 46.0:
		return ["floor", LEVEL, F.F_FLAGSTONE] if absf(z) <= 10.5 else ["wall", WALL_LEVEL, F.F_CONCRETE]
	if x < 56.0:
		return ["lava", LAVA_BED, F.F_CORR_STONE] if absf(z) <= 10.5 else ["wall", WALL_LEVEL, F.F_CONCRETE]
	if x < 70.0:
		return ["floor", LEVEL, F.F_POOL_TILE] if absf(z) <= (10.5 if x < 59.0 else 6.5) else ["wall", WALL_LEVEL, F.F_CONCRETE]
	if x < 78.0:
		var rel := Vector2(x, z) - CORRIDOR_FROM
		var off := absf(rel.x * -CORRIDOR_DIR.y + rel.y * CORRIDOR_DIR.x)
		return ["floor", LEVEL, F.F_DIAMOND] if off <= CORRIDOR_HALF else ["wall", WALL_LEVEL, F.F_CONCRETE]
	if z >= 5.0 and z <= 6.4 and x < 84.5:
		return ["wall", WALL_LEVEL, F.F_CONCRETE]   # the pen's wall; the gap at its east end is the gate
	return ["floor", LEVEL, F.F_CONCRETE]


## The lab as a HexMap: the course, its walls cut along the midpoint lines, the pool carved, the lava recorded (HexMap.lava
## and the cave record LavaField and the look read), the start and exit tags.
static func build_map() -> HexMap:
	var m := HexMap.new()
	var wall_mat := FloorMaterials.W_CONCRETE
	var lo := Hex.from_world(Vector3(BOUNDS.position.x, 0, BOUNDS.position.y))
	var hi := Hex.from_world(Vector3(BOUNDS.end.x, 0, BOUNDS.end.y))
	var lava: Array[Vector2i] = []
	for r in range(lo.y - 2, hi.y + 3):
		for q in range(lo.x - 12, hi.x + 12):
			var c := Vector2i(q, r)
			var w := Hex.to_world(c)
			if not BOUNDS.has_point(Vector2(w.x, w.z)):
				continue
			var f := feature(w.x, w.z)
			var cell: HexMap.Cell
			match str(f[0]):
				"wall":
					cell = m.set_cell(c, int(f[1]), HexMap.Tile.WALL)
				"lava":
					cell = m.set_cell(c, int(f[1]))
					cell.tag = "lava"
					lava.append(c)
				_:
					cell = m.set_cell(c, int(f[1]))
					cell.tag = "room:0"
			cell.mat_id = FloorMaterials.pack(int(f[2]), wall_mat)
	# the pillars: a triangle of wall cells each (a midpoint wall triangle once cut)
	for p in PILLARS:
		var c := Hex.from_world(Vector3(p.x, 0, p.y))
		for cc: Vector2i in [c, c + Hex.DIRS[0], c + Hex.DIRS[5]]:
			m.set_cell(cc, WALL_LEVEL, HexMap.Tile.WALL).mat_id = FloorMaterials.pack(FloorMaterials.F_CONCRETE, wall_mat)
	# the bridge: one-wide, along DIRS[1] (60 degrees)
	var b := Hex.from_world(Vector3(BRIDGE_FROM.x, 0, BRIDGE_FROM.y))
	while Hex.to_world(b).x < BRIDGE_TO_X:
		var cell := m.get_cell(b)
		if cell != null and lava.has(b):
			cell.level = LEVEL
			cell.tag = "room:0"
			lava.erase(b)
		b += Hex.DIRS[1]
	_carve_pool(m)
	m.cut_walls()
	m.get_cell(Hex.from_world(START)).tag = "start"
	m.get_cell(Hex.from_world(EXIT)).tag = "exit"
	lava.sort_custom(HexMap._cell_less)
	for c in lava:
		m.lava[c] = true
	m.cave = {"pattern": "move lab", "level": LEVEL, "crust_level": CRUST_LEVEL, "bed": LAVA_BED, "lava_y": LAVA_Y,
		"rooms": ["room:0"], "rock": [], "lava": lava}
	return m


## The pool: the first indoor-pool shape (PoolGeo) that fits round POOL_AT on the deck.
static func _carve_pool(m: HexMap) -> void:
	var ok := {}
	for c: Vector2i in m.cells:
		var w := Hex.to_world(c)
		var cell := m.get_cell(c)
		if cell.type == HexMap.Tile.FLOOR and cell.level == LEVEL and w.x > 58.5 and w.x < 68.5 and absf(w.z) < 5.0:
			ok[c] = 2
	var anchor := Hex.from_world(Vector3(POOL_AT.x, 0, POOL_AT.y))
	for v: Dictionary in PoolGeo.variants(PoolGeo.LOOK_POOL):
		if PoolGeo._fits(ok, anchor, v):
			PoolGeo._apply(m, "room:0", PoolGeo.LOOK_POOL, LEVEL, v, anchor)
			return


## A minimal site plan: the room, start and exit (no gates, employees, props, notes, mail, packs or doors).
static func plan(m: HexMap, floor_n: int) -> SitePlan:
	var p := SitePlan.new()
	p.floor_number = floor_n
	p.start = m.cells_with_tag("start")[0]
	p.exit = m.cells_with_tag("exit")[0]
	SiteBuilder._index_rooms(m, p)
	if floor_n <= SiteBuilder.VAN_FLOOR:
		# the work van on the start pad, as on any first floor: its arrival holds the crew (and pauses the AI) until the
		# shared start, so in a crew nobody walks before the barrier's checksum
		p.van = VanPlan.plan(m, p, SiteBuilder._corridor_distance(m, 4))
	p.dispatch = "Movement lab."
	return p


## The pen's grunt and swarmer.
static func spawn_monsters(site: SiteBuilder.Site) -> void:
	for e: Array in [["grunt", GRUNT_AT], ["swarmer", SWARMER_AT]]:
		var at: Vector2 = e[1]
		var mon := MonsterFactory.spawn(str(e[0]), Hex.from_world(Vector3(at.x, 0, at.y)))
		if mon != null:
			site.monsters.append(mon)
