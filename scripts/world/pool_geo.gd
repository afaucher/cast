class_name PoolGeo
extends RefCounted
## In-ground pools (docs/design/pool-options.md, "Built": option B, the midpoint inset, wading depth only).
##
## A pool is a convex cluster of BASIN cells sunk DROP level below its room's floor. Like a wall cut downward, the ring of
## cells round it is cut along the midpoint lines (hex centre to hex centre): kites d - 1 and d of a ring cell whose
## neighbour d is a basin cell are pool floor (`Cell.pool_mask`, at `Cell.pool_level`), the rest of the ring cell is deck.
## So the rim is a straight line at 0 / 60 / 120 degrees that turns only on hex centres, and every turn is 120 degrees.
## The rim is a one-level STEP, not a wall: heroes, allies, employees and monsters walk in and out anywhere along it,
## and every pool cell is an ordinary full cell for pathing (HexMap.find_path needs no change).
##
## Shapes: whole rows of basin cells (1-4 long) and two nested rows (trapezoids and parallelograms), in all six
## orientations. Every oriented shape is checked once to be convex (its pool kites are exactly the triangles inside the
## convex hull of its ring centres), so nothing pokes out of the outline and the coping, liner and water are one convex
## polygon each.
##
## MOATS (the shark moat theme, LOOK_MOAT) are a RING: the water between a convex outline and a convex ISLAND (`hole`)
## one ROW inside it. The outline is a lattice hexagon (MOAT_SIDES: side lengths along DIRS[0..5], every corner 120
## degrees on a hex centre) and the island is the same hexagon offset one row in, whose corners land on hex centres too
## (a 120-degree corner moves one lattice step along its bisector), so both rims run on midpoint lines. A kite is pool
## exactly when its triangle lies inside the outline and outside the island: one body of water, one liner, one coping
## round the outside and one round the island, no seams. Every corner of the water is 120 degrees (outside) or 240
## (round the island), never 60, so no wall-like sliver is ever needed. A one-row moat has no basin cells: all its cells
## are ring cells (deck and pool kites).
##
## Placement (carve(), from SiteBuilder.plan right after the room themes are dealt, before the theme planner sees the
## room): each room whose theme has a pool (THEME_LOOK) gets a shape of a size rolled among the look's biggest few (the
## next smaller one when none fits, bigger ones last), placed nearest the room's centre:
##   - the basin and ring cells: the room's own flat floor at its base level, full cells (no wall kites, no set piece),
##     not near the start / exit / elevator (the planner's `avoid`: START_CLEAR, EXIT_CLEAR, ElevatorGeo.keep_cells), not
##     within CORRIDOR_CLEAR of a corridor (doors), not in a hellgate's clear zone, EMPLOYEE_CLEAR from every employee;
##   - the WALK ring (every cell next to the ring) is the room's floor at its base level too (a wall-cut cell will do: its
##     floor side is deck), so there is dry deck all round and no pillar, platform or pit touches the water;
##   - the water (basin + ring cells) takes at most MAX_SHARE of the room.
## The van (floor 1, the start room) and the crew's arrival spots are inside the avoided start / exit zones. Monster packs,
## props, notes, mail and decor are planned afterwards and keep to dry floor (HexMap.is_pool_cell).
## Deterministic per floor seed, no shared random stream (its own generator): spawn data, in the floor checksum.
##
## The record (HexMap.pools): {room, look, deck_level, floor_level, surface_y, basin, ring, outline (convex, Vector2 X/Z,
## counter-clockwise seen from above), hole (a moat's island: convex, the same winding, its corner i one row in from
## outline corner i; [] for a pool), center, axis (the long axis), half_len, half_wid, ladder {pos, yaw} | {},
## gantry {pos, yaw, span, legs} | {}}. A specimen pool's gantry stands on two deck cells across its middle: its legs are
## HexMap.solids and those cells are no_stand (not path nodes), like the elevator's posts.

const LOOK_POOL := "pool"          ## the indoor pool: blue water, white tile, stone coping, a chrome ladder
const LOOK_SPECIMEN := "specimen"  ## science: green water, dark tile with glowing grout, steel coping, the gantry
const LOOK_MOAT := "moat"          ## the shark moat: a ring of murky water round an island, stone blocks and coping, fins
const THEME_LOOK := {"pool": LOOK_POOL, "science": LOOK_SPECIMEN, "moat": LOOK_MOAT}
const DROP := 1                    ## pool floor levels below the deck: one step, so you wade in and out anywhere
const MAX_SHARE := 0.3
const EMPLOYEE_CLEAR := 2
const GATE_CLEAR := 3              ## ThemeCtx.GATE_CLEAR / ORIGIN_GATE_CLEAR
const ORIGIN_GATE_CLEAR := 4
const MAX_CENTER_DIST := 7.0       ## world units from the room's centre to the pool's
const GANTRY_SPAN := 6.0           ## leg to leg (the cells two rows over on each side of the middle basin cell)
const GANTRY_HEIGHT := 3.3
const LEG_FOOT := Vector2(0.42, 1.75)   ## a gantry leg's footprint: across the beam x along the pool's axis
## A moat room where no ring fits (a ring needs a clear area 7-11 cells across: crates, platforms, doors or a hellgate get
## in the way in about two rooms in five) gets a SHARK POOL instead: a convex pool (the indoor pool's shapes) in the
## moat's look, its fins circling half a row inside the rim.
const MOAT_POOL := "moat_pool"
## The first size tried is one of the look's this-many biggest.
const VARIETY := {"pool": 3, "specimen": 2, "moat": 2, "moat_pool": 3}
const ROW := 1.5 * Hex.SIZE        ## between two neighbouring parallel midpoint lines: a moat is one row wide
## Moat outlines: lattice hexagons by their side lengths (walked along DIRS[i + rot]), biggest first. The island is the
## same hexagon one ROW in (every side one shorter).
const MOAT_SIDES: Array = [
	[6, 6, 6, 6, 6, 6], [6, 5, 5, 6, 5, 5], [5, 5, 5, 5, 5, 5], [5, 4, 4, 5, 4, 4], [4, 4, 4, 4, 4, 4],
	[4, 3, 3, 4, 3, 3], [3, 3, 3, 3, 3, 3], [3, 2, 3, 2, 3, 2], [3, 2, 2, 3, 2, 2], [2, 2, 2, 2, 2, 2],
]

## Basin shapes (axial offsets, rows along DIRS[0]), biggest first.
const SHAPE_ROW4: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
const SHAPE_ROW3: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
const SHAPE_ROW2: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
const SHAPE_ONE: Array[Vector2i] = [Vector2i(0, 0)]
const SHAPE_TRAP43: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]
const SHAPE_PARA33: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]
const SHAPE_PARA33B: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
const SHAPE_TRAP32: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)]
const SHAPE_PARA22: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]

static var _variants: Dictionary = {}   ## look -> Array of oriented shapes (LOCAL cache: pure geometry)


## The shapes a look tries, biggest first (single rows only under a gantry).
static func shapes(look: String) -> Array:
	if look == LOOK_SPECIMEN:
		return [SHAPE_ROW3, SHAPE_ROW2, SHAPE_ONE]
	return [SHAPE_TRAP43, SHAPE_PARA33, SHAPE_PARA33B, SHAPE_TRAP32, SHAPE_ROW4, SHAPE_PARA22, SHAPE_ROW3, SHAPE_ROW2]


## Rotate an axial offset by 60 degrees `times` times (DIRS[0] -> DIRS[times]).
static func rotate(c: Vector2i, times: int) -> Vector2i:
	var out := c
	for _i in posmod(times, 6):
		out = Vector2i(out.x + out.y, -out.x)
	return out


static func _v2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _cell_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


## Every oriented, convex variant of the look's shapes (relative to an anchor at the origin cell), biggest first:
## {size, cells (water cells), basin, ring: {cell: mask}, walk, outline (world offsets), hole (a moat's island, else
## empty), axis (dir index), center (world offset), gantry legs}.
static func variants(look: String) -> Array:
	if _variants.has(look):
		return _variants[look]
	if look == LOOK_MOAT:
		_variants[look] = _moat_variants()
		return _variants[look]
	var out: Array = []
	var seen := {}
	for shape: Array[Vector2i] in shapes(look):
		for rot in 6:
			var basin: Array[Vector2i] = []
			for o in shape:
				basin.append(rotate(o, rot))
			basin.sort_custom(_cell_less)
			var key := str(_normalized(basin))
			if seen.has(key):
				continue
			seen[key] = true
			var v := _build_variant(basin, rot % 3, look)
			if not v.is_empty():
				out.append(v)
	_variants[look] = out
	return out


static func _normalized(cells: Array[Vector2i]) -> Array[Vector2i]:
	var lo := cells[0]
	var out: Array[Vector2i] = []
	for c in cells:
		out.append(c - lo)
	return out


## The geometry of one oriented shape, or {} when it is not convex.
static func _build_variant(basin: Array[Vector2i], axis: int, look: String) -> Dictionary:
	var in_basin := {}
	for b in basin:
		in_basin[b] = true
	var ring := {}
	for b in basin:
		for d in 6:
			var r: Vector2i = b + Hex.DIRS[d]
			if in_basin.has(r):
				continue
			var back := (d + 3) % 6          # the basin cell is neighbour `back` of r: kites back - 1 and back are pool
			ring[r] = int(ring.get(r, 0)) | (1 << back) | (1 << posmod(back - 1, 6))
	var walk: Array[Vector2i] = []
	var walk_set := {}
	for r: Vector2i in ring:
		for d in Hex.DIRS:
			var w: Vector2i = r + d
			if in_basin.has(w) or ring.has(w) or walk_set.has(w):
				continue
			walk_set[w] = true
			walk.append(w)
	walk.sort_custom(_cell_less)
	# the outline: the convex hull of the ring centres, without collinear points, counter-clockwise (X/Z)
	var pts := PackedVector2Array()
	for r: Vector2i in ring:
		pts.append(_v2(Hex.to_world(r)))
	var hull := _clean_hull(Geometry2D.convex_hull(pts))
	if hull.size() < 3:
		return {}
	# convex: every kite of every ring cell is pool exactly when its triangle lies inside the hull
	for r: Vector2i in ring:
		var m: int = ring[r]
		for k in 6:
			var tri := (_v2(Hex.to_world(r)) + _v2(Hex.to_world(r + Hex.DIRS[k])) + _v2(Hex.to_world(r + Hex.DIRS[(k + 1) % 6]))) / 3.0
			var inside := Geometry2D.is_point_in_polygon(tri, hull)
			if inside != ((m >> k) & 1 == 1):
				return {}
	var center := Vector2.ZERO
	for b in basin:
		center += _v2(Hex.to_world(b))
	center /= float(basin.size())
	var ax := _v2(Hex.dir_vector(axis))
	var perp := Vector2(-ax.y, ax.x)
	var half_len := 0.0
	var half_wid := 0.0
	for p in hull:
		half_len = maxf(half_len, absf((p - center).dot(ax)))
		half_wid = maxf(half_wid, absf((p - center).dot(perp)))
	var v := {"size": basin.size(), "cells": basin.size() + ring.size(), "basin": basin, "ring": ring, "walk": walk,
		"outline": hull, "hole": PackedVector2Array(), "axis": axis,
		"center": center, "half_len": half_len, "half_wid": half_wid, "legs": [] as Array[Vector2i], "mid": basin[0]}
	if look == LOOK_SPECIMEN:
		# the gantry stands across the middle basin cell, its legs on the deck cells two rows over
		var mid: Vector2i = basin[(basin.size() - 1) / 2]
		var l1: Vector2i = mid + Hex.DIRS[(axis + 1) % 6] + Hex.DIRS[(axis + 2) % 6]
		var l2: Vector2i = mid + Hex.DIRS[(axis + 4) % 6] + Hex.DIRS[(axis + 5) % 6]
		if not walk_set.has(l1) or not walk_set.has(l2):
			return {}
		v["legs"] = [l1, l2] as Array[Vector2i]
		v["mid"] = mid
	return v


## The moat rings: every rotation of every MOAT_SIDES hexagon, anchored on its first corner (a water cell), biggest first.
static func _moat_variants() -> Array:
	var out: Array = []
	var seen := {}
	for sides: Array in MOAT_SIDES:
		var longest := 0
		for i in 6:
			if int(sides[i]) > int(sides[longest]):
				longest = i
		for rot in 6:
			var corners: Array[Vector2i] = []
			var at := Vector2i.ZERO
			for i in 6:
				corners.append(at)
				at += Hex.DIRS[(i + rot) % 6] * int(sides[i])
			if at != Vector2i.ZERO:
				continue   # (not a closed hexagon)
			var v := _build_ring(corners, (longest + rot) % 3)
			if v.is_empty():
				continue
			var cells: Array[Vector2i] = []
			cells.append_array(v["basin"])
			for r: Vector2i in (v["ring"] as Dictionary):
				cells.append(r)
			cells.sort_custom(_cell_less)
			var key := str(_normalized(cells))
			if seen.has(key):
				continue
			seen[key] = true
			out.append(v)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["size"]) > int(b["size"]))
	return out


## One moat ring from its outer corners (cells), or {} when the island's corners miss the hex centres.
static func _build_ring(corners: Array[Vector2i], axis: int) -> Dictionary:
	var pts := PackedVector2Array()
	for c in corners:
		pts.append(_v2(Hex.to_world(c)))
	var outline := _clean_hull(Geometry2D.convex_hull(pts))
	if outline.size() != 6:
		return {}
	var hole := offset(Array(outline), -ROW)
	for i in hole.size():
		var hc := _v2(Hex.to_world(Hex.from_world(Vector3(hole[i].x, 0.0, hole[i].y))))
		if hc.distance_to(hole[i]) > 0.01:
			return {}
		hole[i] = hc
	if area(hole) <= 0.0:
		return {}
	var center := Vector2.ZERO
	for p in outline:
		center += p
	center /= float(outline.size())
	var reach := 0.0
	for p in outline:
		reach = maxf(reach, p.distance_to(center))
	var c0 := Hex.from_world(Vector3(center.x, 0.0, center.y))
	var basin: Array[Vector2i] = []
	var ring := {}
	for c in Hex.range_cells(c0, int(ceilf(reach / Hex.SQRT3)) + 2):
		var m := kite_mask(c, outline, hole)
		if m == HexMap.ALL_KITES:
			basin.append(c)
		elif m != 0:
			ring[c] = m
	basin.sort_custom(_cell_less)
	var wet := {}
	for b in basin:
		wet[b] = true
	for r: Vector2i in ring:
		wet[r] = true
	# the walk: the dry cells touching the water, outside and round the island's rim (the island's middle may hold
	# anything: a crate or a pillar there leaves the island reachable from all round)
	var walk: Array[Vector2i] = []
	var walk_set := {}
	for r: Vector2i in wet:
		for d in Hex.DIRS:
			var w: Vector2i = r + d
			if wet.has(w) or walk_set.has(w):
				continue
			walk_set[w] = true
			walk.append(w)
	walk.sort_custom(_cell_less)
	var ax := _v2(Hex.dir_vector(axis))
	var perp := Vector2(-ax.y, ax.x)
	var half_len := 0.0
	var half_wid := 0.0
	for p in outline:
		half_len = maxf(half_len, absf((p - center).dot(ax)))
		half_wid = maxf(half_wid, absf((p - center).dot(perp)))
	return {"size": wet.size(), "cells": wet.size(), "basin": basin, "ring": ring, "walk": walk, "outline": outline,
		"hole": hole, "axis": axis, "center": center, "half_len": half_len, "half_wid": half_wid,
		"legs": [] as Array[Vector2i], "mid": c0}


## The pool kites of cell `c` for the water inside `outline` and outside `hole` (convex polygons in X/Z; `hole` may be
## empty): bit k is set when the triangle of kite k (the cell's centre and its neighbours k and k + 1) lies in the water.
static func kite_mask(c: Vector2i, outline: PackedVector2Array, hole: PackedVector2Array) -> int:
	var m := 0
	for k in 6:
		var tri := (_v2(Hex.to_world(c)) + _v2(Hex.to_world(c + Hex.DIRS[k])) + _v2(Hex.to_world(c + Hex.DIRS[(k + 1) % 6]))) / 3.0
		if Geometry2D.is_point_in_polygon(tri, outline) and (hole.is_empty() or not Geometry2D.is_point_in_polygon(tri, hole)):
			m |= 1 << k
	return m


## A point surely in the water of a pool record: its centre, or for a moat the middle of the channel along edge 0.
static func wet_point(rec: Dictionary) -> Vector2:
	var hole: Array = rec.get("hole", [])
	if hole.is_empty():
		return rec["center"]
	var ol: Array = rec["outline"]
	return ((ol[0] as Vector2) + (ol[1] as Vector2) + (hole[0] as Vector2) + (hole[1] as Vector2)) * 0.25


## The fins' loop: the middle line of a moat's channel (corner i halfway between outline corner i and island corner i),
## or half a row inside a shark pool's rim; empty for any other pool.
static func channel(rec: Dictionary) -> PackedVector2Array:
	var hole: Array = rec.get("hole", [])
	var ol: Array = rec["outline"]
	if hole.is_empty():
		return offset(ol, -ROW * 0.5) if str(rec.get("look", "")) == LOOK_MOAT else PackedVector2Array()
	var out := PackedVector2Array()
	for i in hole.size():
		out.append(((ol[i] as Vector2) + (hole[i] as Vector2)) * 0.5)
	return out


## Convex hull as Geometry2D gives it, minus the repeated last point and collinear points, counter-clockwise in X/Z
## (positive signed area with x right, z down... as computed by _area below).
static func _clean_hull(h: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array(h)
	if pts.size() > 1 and pts[0].distance_to(pts[pts.size() - 1]) < 0.0001:
		pts.remove_at(pts.size() - 1)
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[(i - 1 + n) % n]
		var b := pts[i]
		var c := pts[(i + 1) % n]
		if absf((b - a).cross(c - b)) > 0.0001:
			out.append(b)
	if area(out) < 0.0:
		out.reverse()
	return out


## Signed area of a polygon in X/Z (positive = the winding `outline` uses).
static func area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


# --- placement ------------------------------------------------------------------------------------------------------

## Carve a pool into every room whose theme has one (plan.room_themes; THEME_LOOK). Rooms that already have one (a plan
## made twice from one map) keep it. `avoid`: cells near the start, the exit and the elevator; `near_corr`: cells near a
## corridor. Writes the cells, HexMap.pools and (a specimen pool's gantry legs) HexMap.solids / no_stand.
static func carve(map: HexMap, plan: SitePlan, avoid: Dictionary, near_corr: Dictionary, seed_value: int) -> void:
	var tags: Array = plan.room_themes.keys()
	tags.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("room:")) < int(b.trim_prefix("room:")))
	var gate_zone := {}
	for g in plan.gates:
		for c in Hex.range_cells(g["cell"], ORIGIN_GATE_CLEAR if bool(g["origin"]) else GATE_CLEAR):
			gate_zone[c] = true
	for tag: String in tags:
		var look: String = THEME_LOOK.get(String(plan.room_themes[tag]), "")
		if look == "" or not plan.rooms.has(tag) or not pool_of_room(map, tag).is_empty():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value * 31 + int(tag.trim_prefix("room:")) * 7919 + 17
		var pick := _choose(map, plan, tag, look, avoid, near_corr, gate_zone, rng)
		if pick.is_empty() and look == LOOK_MOAT:
			pick = _choose(map, plan, tag, MOAT_POOL, avoid, near_corr, gate_zone, rng)   # no ring fits: a shark pool
		if not pick.is_empty():
			_apply(map, tag, look, int(plan.base_levels[tag]), pick["variant"], pick["anchor"])


## The pool of a room ({} when it has none).
static func pool_of_room(map: HexMap, tag: String) -> Dictionary:
	for rec in map.pools:
		if str(rec["room"]) == tag:
			return rec
	return {}


## The best spot in the room: the biggest shape that fits anywhere, nearest the room's centre. {variant, anchor} or {}.
static func _choose(map: HexMap, plan: SitePlan, tag: String, look: String, avoid: Dictionary, near_corr: Dictionary,
		gate_zone: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var cells: Array = plan.rooms[tag]
	var base: int = int(plan.base_levels[tag])
	var center_w := _v2(Hex.to_world(plan.centers[tag]))
	# 2 = may hold water, 1 = may be the dry walk round it
	var ok := {}
	for c: Vector2i in cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type != HexMap.Tile.FLOOR or cell.level != base or cell.pool_mask != 0 or map.no_stand.has(c):
			continue   # (the walk may be a wall-cut cell: its floor side is deck; a ring cell is always full, see _fits)
		var wet := cell.wall_mask == 0 and not avoid.has(c) and not near_corr.has(c) and not gate_zone.has(c)
		if wet:
			for e in plan.employees:
				if Hex.distance(c, e["cell"]) < EMPLOYEE_CLEAR:
					wet = false
					break
		ok[c] = 2 if wet else 1
	for e in plan.employees:
		ok.erase(e["cell"])   # (nobody's standing spot is part of the walk either)
	var budget := float(cells.size()) * MAX_SHARE
	# the size to try first: one of the look's biggest few (variety), then smaller ones, then bigger ones
	var sizes: Array[int] = []
	for v: Dictionary in variants(look):
		if not sizes.has(int(v["size"])):
			sizes.append(int(v["size"]))
	var target: int = sizes[rng.randi_range(0, mini(int(VARIETY.get(look, 1)), sizes.size()) - 1)]
	sizes.sort_custom(func(a: int, b: int) -> bool:
		if (a > target) != (b > target):
			return b > target
		return absi(a - target) < absi(b - target))
	for size in sizes:
		var best := {}
		var best_score := INF
		for v: Dictionary in variants(look):
			if int(v["size"]) != size or float(v["cells"]) > budget:
				continue
			var vc: Vector2 = v["center"]
			for anchor: Vector2i in cells:
				if int(ok.get(anchor, 0)) != 2:
					continue   # (the anchor is a basin cell)
				var aw := _v2(Hex.to_world(anchor))
				var dist := (aw + vc).distance_to(center_w)
				if dist > MAX_CENTER_DIST or not _fits(ok, anchor, v):
					continue
				var score := dist + rng.randf() * 0.8
				if score < best_score:
					best_score = score
					best = {"variant": v, "anchor": anchor}
		if not best.is_empty():
			return best
	return {}


static func _fits(ok: Dictionary, anchor: Vector2i, v: Dictionary) -> bool:
	for b: Vector2i in (v["basin"] as Array):
		if int(ok.get(anchor + b, 0)) != 2:
			return false
	for r: Vector2i in (v["ring"] as Dictionary):
		if int(ok.get(anchor + r, 0)) != 2:
			return false
	for w: Vector2i in (v["walk"] as Array):
		if int(ok.get(anchor + w, 0)) == 0:
			return false
	for l: Vector2i in (v["legs"] as Array):
		if int(ok.get(anchor + l, 0)) != 2:
			return false   # (a gantry leg is a set piece: not on the start / exit / a door either)
	return true


## Write the pool into the map and record it.
static func _apply(map: HexMap, tag: String, look: String, deck: int, v: Dictionary, anchor: Vector2i) -> void:
	var low := deck - DROP
	var aw := _v2(Hex.to_world(anchor))
	var basin: Array[Vector2i] = []
	for b: Vector2i in (v["basin"] as Array):
		var c: Vector2i = anchor + b
		var cell: HexMap.Cell = map.cells[c]
		cell.level = low
		cell.pool_mask = HexMap.ALL_KITES
		cell.pool_level = low
		basin.append(c)
	var ring: Array[Vector2i] = []
	var rmap: Dictionary = v["ring"]
	for r: Vector2i in rmap:
		var c: Vector2i = anchor + r
		var cell: HexMap.Cell = map.cells[c]
		cell.pool_mask = int(rmap[r])
		cell.pool_level = low
		ring.append(c)
	ring.sort_custom(_cell_less)
	var outline: Array = []
	for p in (v["outline"] as PackedVector2Array):
		outline.append(aw + p)
	var hole: Array = []
	for p in (v["hole"] as PackedVector2Array):
		hole.append(aw + p)
	var axis_v := _v2(Hex.dir_vector(int(v["axis"])))
	var center: Vector2 = aw + (v["center"] as Vector2)
	var rec := {
		"room": tag, "look": look, "deck_level": deck, "floor_level": low,
		"surface_y": float(low) * Hex.LEVEL_HEIGHT + HexMap.WATER_DEPTH,
		"basin": basin, "ring": ring, "outline": outline, "hole": hole, "center": center, "axis": axis_v,
		"half_len": float(v["half_len"]), "half_wid": float(v["half_wid"]), "ladder": {}, "gantry": {},
	}
	if look == LOOK_POOL:
		rec["ladder"] = _ladder_spot(outline)
	var legs: Array = v["legs"]
	if not legs.is_empty():
		var l1: Vector2i = anchor + (legs[0] as Vector2i)
		var l2: Vector2i = anchor + (legs[1] as Vector2i)
		var p1 := _v2(Hex.to_world(l1))
		var p2 := _v2(Hex.to_world(l2))
		var beam := (p1 - p2).normalized()
		var mid := _v2(Hex.to_world(anchor + (v["mid"] as Vector2i)))
		rec["gantry"] = {"pos": mid, "yaw": rad_to_deg(atan2(-beam.y, beam.x)), "span": p1.distance_to(p2),
			"height": GANTRY_HEIGHT, "legs": [l1, l2]}
		for lc: Vector2i in [l1, l2]:
			map.add_solid(leg_poly(_v2(Hex.to_world(lc)), beam))
			map.no_stand[lc] = true
	map.pools.append(rec)


## A gantry leg's footprint (a convex quad, X/Z) at `at`, `beam` the unit direction of the beam.
static func leg_poly(at: Vector2, beam: Vector2) -> PackedVector2Array:
	var along := Vector2(-beam.y, beam.x)
	var hx := beam * (LEG_FOOT.x * 0.5)
	var hz := along * (LEG_FOOT.y * 0.5)
	return PackedVector2Array([at - hx - hz, at + hx - hz, at + hx + hz, at - hx + hz])


## The ladder (decoration: wading needs none) on the middle of the longest rim edge facing away from the camera, where the
## near rim cannot hide it: {pos, yaw} with the model's +Z pointing into the pool.
static func _ladder_spot(outline: Array) -> Dictionary:
	var best := {}
	var best_score := -INF
	var n := outline.size()
	for i in n:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % n]
		var e := b - a
		var out := Vector2(e.y, -e.x).normalized()   # (counter-clockwise outline: the outward normal)
		var score := -out.dot(ThemeGeo.CAMERA_DIR) * 2.0 + e.length() * 0.3
		if score > best_score:
			best_score = score
			best = {"pos": (a + b) * 0.5, "yaw": rad_to_deg(atan2(-out.x, -out.y)), "normal": out}
	return best


## The outward unit normal of each outline edge (i -> i + 1).
static func edge_normals(outline: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := outline.size()
	for i in n:
		var e: Vector2 = (outline[(i + 1) % n] as Vector2) - (outline[i] as Vector2)
		out.append(Vector2(e.y, -e.x).normalized())
	return out


## A polygon offset from the convex outline by `d` along every edge's outward normal (negative = inward), with
## mitred corners: each new corner lies on the bisector, exactly `d` from both edges that meet there.
static func offset(outline: Array, d: float) -> PackedVector2Array:
	var normals := edge_normals(outline)
	var n := outline.size()
	var out := PackedVector2Array()
	for i in n:
		var na := normals[(i - 1 + n) % n]
		var nb := normals[i]
		var bis := (na + nb).normalized()
		var k := d / maxf(0.2, bis.dot(nb))
		out.append((outline[i] as Vector2) + bis * k)
	return out
