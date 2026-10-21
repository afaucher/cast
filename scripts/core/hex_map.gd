class_name HexMap
extends RefCounted
## Terrain data + the queries every system uses: ground height, movement
## rules (step / climb / blocked), wall collision, line of sight and A* pathing.
##
## Terrain is a heightfield of hex columns. A cell that is absent is void
## (a pit / out of bounds): nothing stands there. Walls are very tall WALL cells.
##
## MIDPOINT WALLS (cut_walls(), which DungeonGen runs): wall faces do not follow the hex edges, they run
## along the lines that join adjacent hex CENTERS, so every wall is straight (0, 60 or 120 degrees), crosses
## a hex edge at its midpoint and turns only on a hex center. A floor cell next to a WALL cell is cut: its
## `wall_mask` marks which of its six kites (Hex.kite_of) are on the wall side, `wall_top` is the height of
## that part. Such a HALF cell is floor on one side of the line and wall on the other; a corner cell has
## two lines through its center (a 120-degree floor wedge, or a 240-degree one at an inside corner). A
## cell with wall_mask 0 is FULL. Walls block whole triangles of hex centers, so the mask of every cell
## around a triangle agrees. Maps that never call cut_walls() (labs, the arena, hand-built tests) keep
## plain hex walls: WALL cells are solid and no floor cell is cut.
##
## Collision lives here and nowhere else: blocks_point(p, radius), clip_move(from, to, radius),
## sweep(from, to, radius), solid_contact(from, to), nearest_wall(p, max_dist). movement_check() and
## ground_level() already see the wall side of half cells (the wall top), so line of sight, projectiles
## and the height rules treat the wall LINE as the boundary.
##
## Movement rule, measured in height LEVELS between two nearby ground points:
##   rise <= STEP_LEVELS   walk (step up)
##   rise <= CLIMB_LEVELS  climb (slow)
##   rise >  CLIMB_LEVELS  blocked
##   drop >  DROP_LEVELS   blocked (no jumping off cliffs)
## STAIRS cells ramp smoothly from `level` (back edge) to `level + rise`
## (the edge facing `stair_dir`), which is how big height gaps are bridged.
##
## Pathing stays on cells: find_path only uses FULL cells as nodes (a half cell's center lies on its wall
## line). A half cell may be the start (the path steps out of it) or the goal (the path ends beside it).
##
## SET PIECES (the elevator, docs/design/elevator-options.md): `solids` are convex polygons (world X/Z) that block
## bodies like a wall face does (blocks_point, clip_move, sweep, nearest_wall, segments_near) without being cells: the
## elevator's jambs, the glass shaft's sides, the platform's railings. They are not drawn here and line of sight,
## projectiles and the height rules ignore them (glass and railings). `no_stand` cells are floor a set piece stands on
## (the shaft's posts sit on their centers): not full cells for pathing or placement. `elevator` is the elevator's
## record (ElevatorGeo). All three are built from the floor seed on every machine.
##
## POOLS (docs/design/pool-options.md, "Built"): an in-ground pool is a convex cluster of hex-center triangles sunk one
## level below the room floor (PoolGeo carves it). Its BASIN cells lie wholly inside (`level` is the pool floor, `pool_mask`
## ALL_KITES); the RING cells round them are cut along midpoint lines like a wall cut downward: their `pool_mask` kites are
## pool floor at `pool_level`, the rest is deck at `level`. The rim is NOT a wall: it is a one-level step, so bodies walk in
## and out anywhere along it, and ring and basin cells are ordinary full cells for pathing. Everything on the pool side is
## under water (water_at); the record of each pool (outline, surface, look) is in `pools`. Spawn data from the floor seed.

enum Tile { FLOOR, WALL, STAIRS, BRIDGE }
enum Move { OK, CLIMB, BLOCKED }

const STEP_LEVELS := 1.05
const CLIMB_LEVELS := 2.05
const DROP_LEVELS := 3.05
const ALL_KITES := 63
const NO_CELL := Vector2i(1 << 20, 1 << 20)
const NO_TOP := -1048576   ## wall_top not known yet (during cut_walls)
const WATER_DEPTH := 0.36   ## world units of water over a pool floor (wading: about knee deep; the deck is one level up)


class Cell:
	var level: int = 0
	var type: int = Tile.FLOOR
	var stair_dir: int = 0   ## direction index (Hex.DIRS) the stairs climb toward
	var stair_rise: int = 0  ## levels gained across the stairs
	var tag: String = ""     ## free-form (e.g. "room:3", "exit", "spawn")
	var wall_mask: int = 0   ## midpoint walls: bit k set = kite k (between DIRS[k] and DIRS[k+1]) is wall. 0 = full cell
	var wall_top: int = 0    ## level of the top of this cell's wall part (cells with a wall_mask)
	var mat_id: int = 0      ## look: floor material in bits 0-7, wall material in bits 8-15 (FloorMaterials; 0 = classic slate). Spawn data written by SiteBuilder.plan()
	var pool_mask: int = 0   ## pools: bit k set = kite k is pool floor (at pool_level, under water). ALL_KITES = a basin cell. 0 = dry
	var pool_level: int = 0  ## level of the pool floor under this cell's pool kites (cells with a pool_mask)


var cells: Dictionary = {}       ## Vector2i -> Cell
var midpoint_walls := false      ## cut_walls() ran: walls follow the lines between hex centers
var solids: Array[PackedVector2Array] = []   ## convex polygons (world X/Z) that block bodies: set-piece walls (see above)
var no_stand: Dictionary = {}    ## Vector2i -> true: floor under a set piece (not a full cell: no path node, no standing spot)
var elevator: Dictionary = {}    ## the elevator's record (ElevatorGeo.make_*), {} when the floor has none
var pools: Array[Dictionary] = []   ## the in-ground pools (PoolGeo records: room, look, basin, ring, outline, surface ...)
## The floor's SEWER CLUSTER (DungeonGen's "sewer" option, then SewerPlanner and GatorPlanner; docs/design/sewer-concept.md
## "Phase 3 as built"): {seed, level, rooms, stair, halls, all_doors, and once flooded body (index into pools), look, sumps,
## ends, source, flows, gators}. {} on a floor without one. Spawn data, solo only for now: phase 2 puts it in NetFloor's
## checksum (its water already is, as cells and the body record in pools).
var sewer: Dictionary = {}
## The floor's LAVA CAVE (DungeonGen's "cave" option, CaveGen and LavaPlanner; the `--lava-cave` prototype's LavaCave too;
## docs/design/lava-playtest.md "As built"): {seed, pattern, level, rooms, bridges, spans, isles, rock, crust_level, ...}. {}
## on a floor without one. Spawn data, in NetFloor's checksum.
var cave: Dictionary = {}
## The cave's LAVA cells (Vector2i -> true; spawn data). They are in `cells` (at the lava bed, tagged "lava") while the floor
## is built, planned, drawn and its fog read, then LavaField.activate() takes them out (remove_cell) on every machine: lava is
## void, with the lava rule (Actor._enter_void). A damp crust puts some back for a while (CRUST_TAG cells, LavaField: terrain
## that changes on a schedule every machine computes from the shared cast).
var lava: Dictionary = {}
const CRUST_TAG := "lava_crust"
## DYNAMIC BLOCKERS (shut doors, docs/design/exploration.md "Decisions: map information, fog and doors"): key -> [a: Vector2,
## b: Vector2, top: float]. A segment in world X/Z that is SOLID while it is set (user, 2026-10-19: a shut door is solid):
## line_of_sight treats it as a wall face up to world height `top`; bodies stop against it like a wall face (_gather adds it
## to the faces near a point, so blocks_point / clip_move / sweep / nearest_wall see it: walking, shoves, the boulder); and a
## projectile meets it (blocker_contact). Pathing ignores it (find_path is on cells): a body walking into a shut door opens it
## (OfficeDoor). Every machine recomputes it from the blocker's own state (an OfficeDoor's `shut`), so it is LOCAL. Empty on
## every floor without doors (then it costs one is_empty a query).
var blockers: Dictionary = {}
var _segs: Dictionary = {}       ## Vector2i -> PackedVector2Array [a, b, n, ...]: wall faces bordering that cell's floor (lazy cache)
var _solid_segs: Dictionary = {} ## Vector2i -> PackedVector2Array [a, b, n, ...]: pieces of the solids' edges, filed under the cell of their middle
var _solid_box := Rect2()        ## the bounding box of every solid


## Who may write each var (see Net). The map is built from the floor seed on every machine.
func net_fields() -> Dictionary:
	return {"cells": Net.SPAWN, "midpoint_walls": Net.SPAWN, "solids": Net.SPAWN, "no_stand": Net.SPAWN,
		"elevator": Net.SPAWN, "pools": Net.SPAWN, "sewer": Net.SPAWN, "_segs": Net.LOCAL, "_solid_segs": Net.LOCAL, "_solid_box": Net.LOCAL,
		"blockers": Net.LOCAL, "cave": Net.SPAWN, "lava": Net.SPAWN}


func set_cell(c: Vector2i, level: int, type: int = Tile.FLOOR) -> Cell:
	var cell := Cell.new()
	cell.level = level
	cell.type = type
	if type == Tile.WALL:
		cell.wall_mask = ALL_KITES
	cells[c] = cell
	_touch(c)
	return cell


func set_stairs(c: Vector2i, level: int, dir: int, rise: int) -> Cell:
	var cell := set_cell(c, level, Tile.STAIRS)
	cell.stair_dir = posmod(dir, 6)
	cell.stair_rise = rise
	return cell


func get_cell(c: Vector2i) -> Cell:
	return cells.get(c)


## Take cell c out of the map (it becomes void), keeping the wall-face cache right: runtime terrain (a lava cave's lava
## going void, a damp crust melting) goes through here, never cells.erase.
func remove_cell(c: Vector2i) -> void:
	if cells.erase(c):
		_touch(c)


## Is c one of the lava cave's lava cells (void, or a crust while one lasts)?
func is_lava(c: Vector2i) -> bool:
	return lava.has(c)


## Is c a damp crust over the lava right now (walkable for a while: never a safe spot to be pulled back to)?
func is_crust(c: Vector2i) -> bool:
	var cell: Cell = cells.get(c)
	return cell != null and cell.tag == CRUST_TAG


func has_cell(c: Vector2i) -> bool:
	return cells.has(c)


## A FULL floor cell: present, not a wall, not cut by a midpoint wall, no set piece on it. Path nodes, spawn and
## placement spots.
func is_walkable_cell(c: Vector2i) -> bool:
	var cell: Cell = cells.get(c)
	return cell != null and cell.type != Tile.WALL and cell.wall_mask == 0 and not no_stand.has(c)


## A floor cell cut by a midpoint wall (part floor, part wall).
func is_half(c: Vector2i) -> bool:
	var cell: Cell = cells.get(c)
	return cell != null and cell.type != Tile.WALL and cell.wall_mask != 0 and cell.wall_mask != ALL_KITES


## The wall kites of a cell: ALL_KITES for a WALL, 0 for a full cell or void.
func wall_mask_of(c: Vector2i) -> int:
	var cell: Cell = cells.get(c)
	return 0 if cell == null else _mask(cell)


static func _mask(cell: Cell) -> int:
	return ALL_KITES if cell.type == Tile.WALL else cell.wall_mask


## Is kite k of cell c on the wall side? (Void is not.)
func kite_blocked(c: Vector2i, k: int) -> bool:
	var cell: Cell = cells.get(c)
	return cell != null and (_mask(cell) >> posmod(k, 6)) & 1 == 1


## Is the world X/Z point itself on the wall side (inside a WALL cell or the wall part of a half cell)?
func wall_at(p: Vector3) -> bool:
	var c := Hex.from_world(p)
	var cell: Cell = cells.get(c)
	if cell == null:
		return false
	var m := _mask(cell)
	if m == 0:
		return false
	if m == ALL_KITES:
		return true
	return (m >> Hex.kite_of(p - Hex.to_world(c))) & 1 == 1


## Is the world X/Z point in pool water (a basin cell, or the pool side of a ring cell's rim line)?
func water_at(p: Vector3) -> bool:
	var c := Hex.from_world(p)
	var cell: Cell = cells.get(c)
	if cell == null or cell.pool_mask == 0:
		return false
	return cell.pool_mask == ALL_KITES or (cell.pool_mask >> Hex.kite_of(p - Hex.to_world(c))) & 1 == 1


## The water surface (world Y) over the point, or NAN when it is dry.
func water_surface(p: Vector3) -> float:
	if not water_at(p):
		return NAN
	return float(cells[Hex.from_world(p)].pool_level) * Hex.LEVEL_HEIGHT + WATER_DEPTH


## A cell with any pool kites (a basin or a ring cell): no prop, note, package or spawn stands on it.
func is_pool_cell(c: Vector2i) -> bool:
	var cell: Cell = cells.get(c)
	return cell != null and cell.pool_mask != 0


## Ground height in LEVELS at a world X/Z point, or NAN over void. On the wall side it is the wall's top.
func ground_level(p: Vector3) -> float:
	var c := Hex.from_world(p)
	var cell: Cell = cells.get(c)
	if cell == null:
		return NAN
	if cell.pool_mask != 0 and (cell.pool_mask == ALL_KITES or (cell.pool_mask >> Hex.kite_of(p - Hex.to_world(c))) & 1 == 1):
		return float(cell.pool_level)
	if cell.type != Tile.WALL and cell.wall_mask != 0:
		if cell.wall_mask == ALL_KITES or (cell.wall_mask >> Hex.kite_of(p - Hex.to_world(c))) & 1 == 1:
			return float(cell.wall_top)
	if cell.type != Tile.STAIRS:
		return float(cell.level)
	var off := p - Hex.to_world(c)
	off.y = 0.0
	var t := clampf(off.dot(Hex.dir_vector(cell.stair_dir)) / (2.0 * Hex.INNER) + 0.5, 0.0, 1.0)
	return cell.level + t * cell.stair_rise


## Ground height in WORLD units at a world X/Z point, or NAN over void.
func ground_height(p: Vector3) -> float:
	return ground_level(p) * Hex.LEVEL_HEIGHT


## Can something standing at `from` move to the nearby point `to`?
## Meant for short hops (one frame of movement, or across one cell edge). A point on the wall side of a
## midpoint wall is BLOCKED; bodies with a radius use clip_move() / blocks_point() for the wall itself.
func movement_check(from: Vector3, to: Vector3) -> int:
	var a := ground_level(from)
	var b := ground_level(to)
	if is_nan(a) or is_nan(b):
		return Move.BLOCKED
	if wall_at(to):
		return Move.BLOCKED
	var d := b - a
	if d > CLIMB_LEVELS or -d > DROP_LEVELS:
		return Move.BLOCKED
	if d > STEP_LEVELS:
		return Move.CLIMB
	return Move.OK


## Movement between two adjacent cells, judged across their shared edge (both must be full cells).
func cell_transition(a: Vector2i, b: Vector2i) -> int:
	if not is_walkable_cell(a) or not is_walkable_cell(b):
		return Move.BLOCKED
	return _edge_move(a, b)


## cell_transition without the full-cell test: the step across the shared edge midpoint.
func _edge_move(a: Vector2i, b: Vector2i) -> int:
	var pa := Hex.to_world(a)
	var pb := Hex.to_world(b)
	var mid := (pa + pb) * 0.5
	var eps := 0.05
	return movement_check(mid.lerp(pa, eps / Hex.INNER), mid.lerp(pb, eps / Hex.INNER))


## True when nothing taller than the sight line sits between the two points.
## Points are world positions (Y included, e.g. eye height). Void never blocks. `step` is the sampling distance:
## a finer one also sees the tip of a wall corner the line only grazes (an archer deciding a shot uses one).
## Shut doors (`blockers`) block it too, unless `use_blockers` is false (a sound muffled by a door asks about the walls alone).
func line_of_sight(from: Vector3, to: Vector3, step: float = 0.25, use_blockers: bool = true) -> bool:
	if use_blockers and not blockers.is_empty() and _blocked(from, to):
		return false
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	var steps := maxi(1, int(flat / step))
	for i in range(1, steps):
		var p := from.lerp(to, float(i) / steps)
		var g := ground_height(p)
		if not is_nan(g) and g > p.y:
			return false
	return true


## Add (or move) a dynamic sight blocker: the segment a -> b (world X/Z) blocks sight below world height `top`.
func set_blocker(key: Variant, a: Vector2, b: Vector2, top: float) -> void:
	blockers[key] = [a, b, top]


func clear_blocker(key: Variant) -> void:
	blockers.erase(key)


## Does the flat line from -> to cross a sight blocker (at any height)? A sound through a shut door asks this.
func crosses_blocker(from: Vector3, to: Vector3) -> bool:
	if blockers.is_empty():
		return false
	var p := Vector2(from.x, from.z)
	var q := Vector2(to.x, to.z)
	for k: Variant in blockers:
		var bl: Array = blockers[k]
		if Geometry2D.segment_intersects_segment(p, q, bl[0], bl[1]) != null:
			return true
	return false


## Where the segment from -> to first meets a blocker below its top (a projectile hitting a shut door), or Vector3.INF.
func blocker_contact(from: Vector3, to: Vector3) -> Vector3:
	if blockers.is_empty():
		return Vector3.INF
	var p := Vector2(from.x, from.z)
	var q := Vector2(to.x, to.z)
	var len2 := p.distance_squared_to(q)
	var best := INF
	for k: Variant in blockers:
		var bl: Array = blockers[k]
		var hit: Variant = Geometry2D.segment_intersects_segment(p, q, bl[0], bl[1])
		if hit == null:
			continue
		var t := 0.0 if len2 < 0.000001 else sqrt(p.distance_squared_to(hit as Vector2) / len2)
		if lerpf(from.y, to.y, t) < float(bl[2]) and t < best:
			best = t
	if best == INF:
		return Vector3.INF
	return from.lerp(to, maxf(0.0, best - 0.02))


## Does the sight line from -> to pass a blocker below its top?
func _blocked(from: Vector3, to: Vector3) -> bool:
	var p := Vector2(from.x, from.z)
	var q := Vector2(to.x, to.z)
	var len2 := p.distance_squared_to(q)
	for k: Variant in blockers:
		var bl: Array = blockers[k]
		var hit: Variant = Geometry2D.segment_intersects_segment(p, q, bl[0], bl[1])
		if hit == null:
			continue
		var t := 0.0 if len2 < 0.000001 else sqrt(p.distance_squared_to(hit as Vector2) / len2)
		if lerpf(from.y, to.y, t) < float(bl[2]):
			return true
	return false


# --- Wall collision ---------------------------------------------------------------------------------

## Does a circle of `radius` at world X/Z point p touch a wall? radius 0 is the point test (wall_at).
func blocks_point(p: Vector3, radius: float = 0.0) -> bool:
	if wall_at(p) or solid_at(p):
		return true
	if radius <= 0.0:
		return false
	var q := Vector2(p.x, p.z)
	var r2 := radius * radius - 0.000001
	var segs := _gather(p, radius)
	var i := 0
	while i < segs.size():
		if q.distance_squared_to(_closest(q, segs[i], segs[i + 1])) < r2:
			return true
		i += 3
	return false


## Where a body of `radius` moving from `from` toward `to` ends up: `to` pushed out of every wall face it
## overlaps (so it stops touching the face, slides along it and settles in corners without jitter). Returns
## `from` if no wall-free spot is found (Y is taken from `to`). `from` is assumed clear.
func clip_move(from: Vector3, to: Vector3, radius: float) -> Vector3:
	if wall_at(to) or solid_at(to):
		return from
	if radius <= 0.0:
		return to
	var p := Vector2(to.x, to.z)
	var segs := _gather(to, radius + 0.15)
	if segs.is_empty():
		return to
	for _i in 8:
		var best := radius
		var push := Vector2.ZERO
		var hit := false
		var i := 0
		while i < segs.size():
			var cp := _closest(p, segs[i], segs[i + 1])
			var v := p - cp
			var d := v.length()
			if d < best:
				best = d
				hit = true
				push = (v / d if d > 0.00001 else segs[i + 2]) * (radius - d + 0.0005)
			i += 3
		if not hit:
			break
		p += push
	p = _settle_corner(p, Vector2(to.x, to.z), segs, radius)
	var out := Vector3(p.x, to.y, p.y)
	if blocks_point(out, radius - 0.003):
		return from
	return out


## Pushed into an inside corner (two faces), one projection after the other lands on one face or the other in turn,
## so a body pressed into the corner would flicker between the two. When `want` lies beyond both faces of a corner
## (in their outward cone) the closest wall-free spot is the corner point itself: return that.
func _settle_corner(p: Vector2, want: Vector2, segs: PackedVector2Array, radius: float) -> Vector2:
	var act: Array[int] = []
	var i := 0
	while i < segs.size():
		var cp := _closest(want, segs[i], segs[i + 1])
		var on_seg := cp.distance_squared_to(segs[i]) > 0.000001 and cp.distance_squared_to(segs[i + 1]) > 0.000001
		if on_seg and want.distance_to(cp) < radius:
			act.append(i)   # a face the wanted spot presses into
		i += 3
	for x in act.size():
		for y in range(x + 1, act.size()):
			var na: Vector2 = segs[act[x] + 2]
			var nb: Vector2 = segs[act[y] + 2]
			var det := na.x * nb.y - na.y * nb.x
			if absf(det) < 0.1:
				continue   # parallel (two halves of one straight face)
			var ca := na.dot(segs[act[x]]) + radius
			var cb := nb.dot(segs[act[y]]) + radius
			var e := Vector2((ca * nb.y - cb * na.y) / det, (na.x * cb - nb.x * ca) / det)
			# want - e = -(alpha * na + beta * nb) with alpha, beta >= 0: the corner is the closest spot
			var off := e - want
			var alpha := (off.x * nb.y - off.y * nb.x) / det
			var beta := (na.x * off.y - na.y * off.x) / det
			if alpha < -0.000001 or beta < -0.000001:
				continue
			var q := e + (na + nb).normalized() * 0.0005
			if not blocks_point(Vector3(q.x, 0.0, q.y), radius - 0.003):
				return q
	return p


## Fraction (0..1) of the straight move from `from` to `to` a body of `radius` can make before it touches a
## wall (1 = no contact). `from` is assumed clear.
func sweep(from: Vector3, to: Vector3, radius: float) -> float:
	if not blocks_point(to, radius):
		return 1.0
	var lo := 0.0
	var hi := 1.0
	for _i in 12:
		var mid := (lo + hi) * 0.5
		if blocks_point(from.lerp(to, mid), radius):
			hi = mid
		else:
			lo = mid
	return lo


## The point where the segment from -> to first meets terrain taller than itself (a wall face, a cliff), found by
## bisection; `to` if it never does. For projectiles: an arrow stops AT the face, not a step short of it.
func solid_contact(from: Vector3, to: Vector3) -> Vector3:
	if not _solid(to):
		return to
	var lo := 0.0
	var hi := 1.0
	for _i in 10:
		var mid := (lo + hi) * 0.5
		if _solid(from.lerp(to, mid)):
			hi = mid
		else:
			lo = mid
	return from.lerp(to, lo)


func _solid(p: Vector3) -> bool:
	var g := ground_height(p)
	return not is_nan(g) and g > p.y


## The wall face nearest to world point p within max_dist: {dist, point: Vector2, normal: Vector2 (unit, out of
## the wall toward p's side)}; {} when there is none.
func nearest_wall(p: Vector3, max_dist: float) -> Dictionary:
	var q := Vector2(p.x, p.z)
	var segs := _gather(p, max_dist)
	var best := max_dist
	var out: Dictionary = {}
	var i := 0
	while i < segs.size():
		var cp := _closest(q, segs[i], segs[i + 1])
		var d := q.distance_to(cp)
		if d < best:
			best = d
			var n: Vector2 = segs[i + 2]
			var on_seg := cp.distance_squared_to(segs[i]) > 0.0001 and cp.distance_squared_to(segs[i + 1]) > 0.0001
			if not on_seg and d > 0.0001:
				n = (q - cp) / d
			out = {"dist": d, "point": cp, "normal": n}
		i += 3
	return out


## The wall faces bordering cell c's floor: [a, b, n, a, b, n, ...] in world X/Z, n the unit normal pointing to
## the floor side. Midpoint walls give the spokes from c's center; plain hex walls give the hex edges.
func wall_segments(c: Vector2i) -> PackedVector2Array:
	if _segs.has(c):
		return _segs[c]
	var out := PackedVector2Array()
	var cell: Cell = cells.get(c)
	if cell != null and cell.type != Tile.WALL and cell.wall_mask != ALL_KITES:
		var m := cell.wall_mask
		var w := Hex.to_world(c)
		var ctr := Vector2(w.x, w.z)
		for d in 6:
			var b_here := (m >> d) & 1
			var b_prev := (m >> posmod(d - 1, 6)) & 1
			if b_here == b_prev:
				continue
			# the spoke toward DIRS[d] separates kites d - 1 and d
			var mid := ctr + _v2(Hex.edge_mid(d))
			var t := (mid - ctr).normalized()
			var n := Vector2(-t.y, t.x)
			var open_k := d if b_here == 0 else posmod(d - 1, 6)
			if n.dot(_v2(Hex.kite_corner(open_k))) < 0.0:
				n = -n
			out.append(ctr)
			out.append(mid)
			out.append(n)
		for k in 6:
			if (m >> k) & 1 == 1:
				continue
			var corner := ctr + _v2(Hex.kite_corner(k))
			# the half edges of kite k border kite k + 2 of the DIRS[k] neighbour and kite k + 4 of the DIRS[k+1] one
			if kite_blocked(c + Hex.DIRS[k], k + 2):
				out.append(ctr + _v2(Hex.edge_mid(k)))
				out.append(corner)
				out.append(-_v2(Hex.dir_vector(k)))
			if kite_blocked(c + Hex.DIRS[(k + 1) % 6], k + 4):
				out.append(corner)
				out.append(ctr + _v2(Hex.edge_mid(k + 1)))
				out.append(-_v2(Hex.dir_vector(k + 1)))
	_segs[c] = out
	return out


## Every wall face within about `radius` of p (the cells around it): [a, b, n, ...] as wall_segments().
func segments_near(p: Vector3, radius: float) -> PackedVector2Array:
	return _gather(p, radius)


func _gather(p: Vector3, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var c0 := Hex.from_world(p)
	var reach := maxi(1, int(floorf((2.0 + radius) / 1.5)))
	for c in Hex.range_cells(c0, reach):
		if cells.has(c):
			out.append_array(wall_segments(c))
	if not _solid_segs.is_empty() and _solid_box.grow(radius + 0.5).has_point(Vector2(p.x, p.z)):
		# a solid's pieces are filed under the cell of their middle, which can be one cell farther out than a wall face
		for c in Hex.range_cells(c0, reach + 1):
			if _solid_segs.has(c):
				out.append_array(_solid_segs[c])
	if not blockers.is_empty():
		var q := Vector2(p.x, p.z)
		for k: Variant in blockers:
			var bl: Array = blockers[k]
			var a: Vector2 = bl[0]
			var b: Vector2 = bl[1]
			if q.distance_to(_closest(q, a, b)) > radius + 2.0:
				continue
			var t := (b - a).normalized()
			var n := Vector2(-t.y, t.x)
			if n.dot(q - a) < 0.0:
				n = -n   # (out of the door toward p's side)
			out.append(a)
			out.append(b)
			out.append(n)
	return out


# --- Set-piece solids -------------------------------------------------------------------------------------------

const SOLID_PIECE := 0.5        ## a solid's edges are filed in pieces this long (so _gather's cell reach finds them)


## Add a convex polygon (world X/Z, either winding) that blocks bodies. Deterministic: the same polygons in the same
## order give the same collision on every machine.
func add_solid(poly: PackedVector2Array) -> void:
	if poly.size() < 3:
		return
	solids.append(poly)
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	var box := Rect2(poly[0], Vector2.ZERO)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		box = box.expand(a)
		var e := b - a
		var n := Vector2(e.y, -e.x).normalized() if area > 0.0 else Vector2(-e.y, e.x).normalized()   # outward
		var pieces := maxi(1, int(ceilf(e.length() / SOLID_PIECE)))
		for k in pieces:
			var pa := a + e * (float(k) / pieces)
			var pb := a + e * (float(k + 1) / pieces)
			var mid := (pa + pb) * 0.5
			var c := Hex.from_world(Vector3(mid.x, 0.0, mid.y))
			var arr: PackedVector2Array = _solid_segs.get(c, PackedVector2Array())
			arr.append(pa)
			arr.append(pb)
			arr.append(n)
			_solid_segs[c] = arr
	_solid_box = box if solids.size() == 1 else _solid_box.merge(box)


## Is the world X/Z point inside one of the set-piece solids?
func solid_at(p: Vector3) -> bool:
	if solids.is_empty():
		return false
	var q := Vector2(p.x, p.z)
	if not _solid_box.grow(0.001).has_point(q):
		return false
	for poly in solids:
		if _in_convex(q, poly):
			return true
	return false


## Does the straight walk a -> b (world X/Z) come within `margin` of a set-piece solid? Steering asks this before it walks
## straight at a goal (movement_check samples points, and the elevator's sides are thinner than a step).
func crosses_solid(a: Vector3, b: Vector3, margin: float = 0.0) -> bool:
	if solids.is_empty():
		return false
	var p := Vector2(a.x, a.z)
	var q := Vector2(b.x, b.z)
	if not Rect2(p, Vector2.ZERO).expand(q).grow(margin + 0.01).intersects(_solid_box):
		return false
	for poly in solids:
		if _in_convex(p, poly) or _in_convex(q, poly):
			return true
		for i in poly.size():
			var c := poly[i]
			var d := poly[(i + 1) % poly.size()]
			var pts := Geometry2D.get_closest_points_between_segments(p, q, c, d)
			if pts[0].distance_to(pts[1]) < margin + 0.0001:
				return true
	return false


static func _in_convex(q: Vector2, poly: PackedVector2Array) -> bool:
	var sgn := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var cr := (b - a).cross(q - a)
		if absf(cr) < 0.0000001:
			continue
		if sgn == 0.0:
			sgn = signf(cr)
		elif signf(cr) != sgn:
			return false
	return true


static func _closest(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0000001:
		return a
	return a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)


static func _v2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _touch(c: Vector2i) -> void:
	if _segs.is_empty():
		return
	_segs.erase(c)
	for d in Hex.DIRS:
		_segs.erase(c + d)


# --- Cutting the walls ------------------------------------------------------------------------------

## Turn the hex walls into midpoint walls: every floor cell next to a WALL cell gets its wall kites and wall
## height, then thin leftovers are walled in (a floor triangle wedged between two wall faces, a pocket of
## floor touching no full cell), so no sliver of floor too thin to stand in survives. Deterministic.
func cut_walls() -> void:
	midpoint_walls = true
	_segs.clear()
	var keys: Array[Vector2i] = []
	for c: Vector2i in cells:
		keys.append(c)
	keys.sort_custom(_cell_less)
	for c in keys:
		var cell: Cell = cells[c]
		if cell.type == Tile.WALL:
			cell.wall_mask = ALL_KITES
			continue
		var m := 0
		var top := NO_TOP
		for d in 6:
			var nb: Cell = cells.get(c + Hex.DIRS[d])
			if nb != null and nb.type == Tile.WALL:
				m |= (1 << d) | (1 << posmod(d - 1, 6))   # neighbour d is a corner of kites d - 1 and d
				top = maxi(top, nb.level)
		cell.wall_mask = m
		cell.wall_top = top if m != 0 else 0
	_trim_slivers(keys)


func _trim_slivers(keys: Array[Vector2i]) -> void:
	var half: Array[Vector2i] = []
	for c in keys:
		var cell: Cell = cells[c]
		if cell.type != Tile.WALL and cell.wall_mask != 0:
			half.append(c)
	# 1. Spikes: an open triangle with walls on two of its three sides is a 60-degree sliver. Close it, repeat.
	var changed := true
	while changed:
		changed = false
		for c in half:
			for k in 2:
				if not _tri_all_floor(c, k) or _tri_blocked(c, k):
					continue
				var walls := 0
				if _tri_blocked(c, k - 1):
					walls += 1
				if _tri_blocked(c, k + 1):
					walls += 1
				if _tri_blocked(c + Hex.DIRS[k], k + 1):
					walls += 1
				if walls >= 2:
					_block_tri(c, k)
					changed = true
	# 2. Pockets: open triangles whose corners are all cut cells, connected to nothing with a full corner.
	var seen := {}
	for c in half:
		for k in 2:
			var key := Vector3i(c.x, c.y, k)
			if seen.has(key) or not _tri_all_half(c, k) or _tri_blocked(c, k):
				continue
			var comp: Array[Vector3i] = [key]
			seen[key] = true
			var anchored := false
			var qi := 0
			while qi < comp.size():
				var t := comp[qi]
				qi += 1
				var tc := Vector2i(t.x, t.y)
				for nb: Vector3i in [_canon(tc, t.z - 1), _canon(tc, t.z + 1), _canon(tc + Hex.DIRS[t.z], t.z + 1)]:
					var nc := Vector2i(nb.x, nb.y)
					if _tri_blocked(nc, nb.z):
						continue
					if not _tri_all_half(nc, nb.z):
						anchored = true   # open and touching a full cell (or a pit): part of the real floor
						continue
					if not seen.has(nb):
						seen[nb] = true
						comp.append(nb)
			if not anchored:
				for t in comp:
					_block_tri(Vector2i(t.x, t.y), t.z)
	# Cells that only got wall kites from the trimming take the wall height of their neighbours.
	for c in keys:
		var cell: Cell = cells[c]
		if cell.type == Tile.WALL or cell.wall_mask == 0 or cell.wall_top > NO_TOP:
			continue
		var top := cell.level + 3
		for d in Hex.DIRS:
			var nb: Cell = cells.get(c + d)
			if nb != null and nb.type != Tile.WALL and nb.wall_mask != 0 and nb.wall_top > NO_TOP:
				top = maxi(top, nb.wall_top)
		cell.wall_top = top


## The canonical name of triangle (c, k): the corner cell whose kite index is 0 (even triangles) or 1 (odd).
func _canon(c: Vector2i, k: int) -> Vector3i:
	var kk := posmod(k, 6)
	if kk < 2:
		return Vector3i(c.x, c.y, kk)
	# (c, kk) = (c + DIRS[kk], kk + 2) = (c + DIRS[kk + 1], kk + 4); one of the three has index 0 or 1.
	var b := c + Hex.DIRS[kk]
	var kb := (kk + 2) % 6
	if kb < 2:
		return Vector3i(b.x, b.y, kb)
	var e := c + Hex.DIRS[(kk + 1) % 6]
	return Vector3i(e.x, e.y, (kk + 4) % 6)


## The three corner cells of triangle (c, k).
func _tri_cells(c: Vector2i, k: int) -> Array[Vector2i]:
	var kk := posmod(k, 6)
	return [c, c + Hex.DIRS[kk], c + Hex.DIRS[(kk + 1) % 6]]


func _tri_blocked(c: Vector2i, k: int) -> bool:
	var kk := posmod(k, 6)
	var cell: Cell = cells.get(c)
	if cell != null:
		return (_mask(cell) >> kk) & 1 == 1
	var b: Cell = cells.get(c + Hex.DIRS[kk])
	if b != null:
		return (_mask(b) >> ((kk + 2) % 6)) & 1 == 1
	var e: Cell = cells.get(c + Hex.DIRS[(kk + 1) % 6])
	if e != null:
		return (_mask(e) >> ((kk + 4) % 6)) & 1 == 1
	return false


func _tri_all_floor(c: Vector2i, k: int) -> bool:
	for t in _tri_cells(c, k):
		var cell: Cell = cells.get(t)
		if cell == null or cell.type == Tile.WALL:
			return false
	return true


## Every corner present, not a wall, and cut (no full cell among them).
func _tri_all_half(c: Vector2i, k: int) -> bool:
	for t in _tri_cells(c, k):
		var cell: Cell = cells.get(t)
		if cell == null or cell.type == Tile.WALL or cell.wall_mask == 0:
			return false
	return true


func _block_tri(c: Vector2i, k: int) -> void:
	var kk := posmod(k, 6)
	var reps: Array = [[c, kk], [c + Hex.DIRS[kk], (kk + 2) % 6], [c + Hex.DIRS[(kk + 1) % 6], (kk + 4) % 6]]
	for r: Array in reps:
		var rc: Vector2i = r[0]
		var cell: Cell = cells.get(rc)
		if cell == null or cell.type == Tile.WALL:
			continue
		if cell.wall_mask == 0:
			cell.wall_top = NO_TOP   # filled in from the neighbours at the end of _trim_slivers
		cell.wall_mask |= 1 << int(r[1])
	_touch(c)


static func _cell_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


# --- Pathing ------------------------------------------------------------------------------------------

## A* over FULL cells. Returns the cell path from start to goal (inclusive of
## both) or [] if unreachable. Climbs cost extra; allow_climb=false treats
## them as walls (e.g. for heavy monsters). A half cell (cut by a midpoint wall) is never a step on
## a path (its center lies on the wall line), but it may be the start or the goal: a path from one
## begins with it and steps straight into its best full neighbour; a path to one ends at the full
## neighbour next to it (the caller then steers to its actual goal point).
func find_path(start: Vector2i, goal: Vector2i, allow_climb: bool = true, max_nodes: int = 4000) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var s := start
	var gl := goal
	if start == goal:
		if is_walkable_cell(start) or is_half(start):
			empty.append(start)
		return empty
	if not is_walkable_cell(start):
		s = _entry_cell(start, goal, allow_climb, true)
		if s == NO_CELL:
			return empty
	if not is_walkable_cell(goal):
		gl = _entry_cell(goal, start, allow_climb, false)
		if gl == NO_CELL:
			return empty
	var path := _astar(s, gl, allow_climb, max_nodes)
	if path.is_empty():
		return path
	if s != start:
		path.push_front(start)
	return path


## The full neighbour of half cell h to enter (or leave) the path by: reachable across their shared edge, nearest
## to `toward`. NO_CELL when h is not a half cell or has none.
func _entry_cell(h: Vector2i, toward: Vector2i, allow_climb: bool, leaving: bool) -> Vector2i:
	if not is_half(h):
		return NO_CELL
	var best := NO_CELL
	var best_d := 1 << 30
	for d in Hex.DIRS:
		var n: Vector2i = h + d
		if not is_walkable_cell(n):
			continue
		var mv := _edge_move(h, n) if leaving else _edge_move(n, h)
		if mv == Move.BLOCKED or (mv == Move.CLIMB and not allow_climb):
			continue
		var dist := Hex.distance(n, toward)
		if dist < best_d:
			best_d = dist
			best = n
	return best


func _astar(start: Vector2i, goal: Vector2i, allow_climb: bool, max_nodes: int) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not is_walkable_cell(start) or not is_walkable_cell(goal):
		return empty
	var open := {start: true}
	var came := {}
	var g := {start: 0.0}
	var f := {start: float(Hex.distance(start, goal))}
	var expanded := 0
	while not open.is_empty():
		var cur: Vector2i = open.keys()[0]
		for k in open:
			if f[k] < f[cur]:
				cur = k
		if cur == goal:
			var path: Array[Vector2i] = [cur]
			while came.has(cur):
				cur = came[cur]
				path.push_front(cur)
			return path
		open.erase(cur)
		expanded += 1
		if expanded > max_nodes:
			return empty
		for d in Hex.DIRS:
			var nb: Vector2i = cur + d
			var mv := cell_transition(cur, nb)
			if mv == Move.BLOCKED or (mv == Move.CLIMB and not allow_climb):
				continue
			var cost: float = g[cur] + (3.0 if mv == Move.CLIMB else 1.0)
			if cost < g.get(nb, INF):
				came[nb] = cur
				g[nb] = cost
				f[nb] = cost + Hex.distance(nb, goal)
				open[nb] = true
	return empty


## Every FULL floor cell.
func walkable_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		if is_walkable_cell(c):
			out.append(c)
	return out


func cells_with_tag(tag: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		if cells[c].tag == tag:
			out.append(c)
	return out
