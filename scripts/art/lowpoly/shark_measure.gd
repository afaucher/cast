extends RefCounted
## The shark lab's measurements (docs/design/sharks.md, "Pool shapes against a shark" and "Moat reconsidered"). Lab-only:
## nothing in the game calls it, and it changes nothing (it reads PoolGeo's shapes and replays SiteBuilder's placement up to
## the carve on the test_pools floors, trying other pool shapes in the moat rooms).
##
##   godot --path . --headless -- --scene res://scenes/shark_lab.tscn --measure
##
## 1. SHAPES: every pool shape PoolGeo deals (indoor pool, specimen pool, shark pool, moat ring) and the proposed ones (a
##    two-row moat ring, three-row "lagoon" shark pools): size, outline, water area, the biggest circle inside the water
##    (inradius), the turning circle a 2.4-long shark gets, the longest straight run and the patrol lap.
## 2. PLACEMENT: the 44 moat rooms of the test_pools floors (5 clients x 7 seeds x 3 floors), each moat option placed the
##    way PoolGeo.carve places a pool (its _choose: the same clearances, the 30 % budget, near the room's centre).
##
## The shark: 2.4 long (snout to tail stock), 0.72 across the body (PoolProps "shark"). Clearances used:
##   BODY_CLEAR  its centre line keeps this far from a rim (half its width plus a hair of liner)
##   R_MIN       the tightest turn a bending body makes (three segments 0.8 apart, at most 35 degrees between two)
##   R_CRUISE    the turn it makes without looking cramped

const PoolProps := preload("res://scripts/art/lowpoly/props/pool_props.gd")

const SHARK_LEN := 2.4
const HALF_WIDTH := 0.36
const BODY_CLEAR := 0.42
const R_MIN := 1.2
const R_CRUISE := 2.0
const RUN_SEEDS: Array[int] = [1, 2, 3, 4, 5, 7, 42]   ## test_pools' seeds


## Print both tables.
static func run() -> void:
	print("\n=== SHAPES (shark %.1f long; centre clearance %.2f; tightest bend R %.1f, cruising R %.1f) ===" % [SHARK_LEN, BODY_CLEAR, R_MIN, R_CRUISE])
	print("%-22s %5s %5s %13s %6s %6s %8s %8s %7s %7s  %s" % ["shape", "basin", "cells", "outline LxW", "water", "r_in", "R_circle", "R_rigid", "run", "lap", "verdict"])
	for look: String in [PoolGeo.LOOK_POOL, PoolGeo.LOOK_SPECIMEN, PoolGeo.MOAT_POOL]:
		for v: Dictionary in _distinct(PoolGeo.variants(look)):
			_print_shape(look, v)
	for v: Dictionary in _distinct(lagoon_variants()):
		_print_shape("lagoon (proposed)", v)
	for v: Dictionary in _distinct(PoolGeo.variants(PoolGeo.LOOK_MOAT)):
		_print_ring("moat 1-row", v)
	for v: Dictionary in _distinct(ring_variants(2)):
		_print_ring("moat 2-row (prop.)", v)
	_placement()


# --- shapes --------------------------------------------------------------------------------------------------------

## One variant per distinct shape (orientations dropped): same size and the same outline extents.
static func _distinct(list: Array) -> Array:
	var out: Array = []
	var seen := {}
	for v: Dictionary in list:
		var ext := _extents(v["outline"])
		var key := "%d %.1f %.1f %.1f" % [int(v["size"]), maxf(ext.x, ext.y), minf(ext.x, ext.y), absf(PoolGeo.area(v["outline"]))]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(v)
	return out


## The outline's length and width along its own long axis (the longest of the three hex directions it spans).
static func _extents(outline: PackedVector2Array) -> Vector2:
	var best := Vector2.ZERO
	for d in 3:
		var ax := Vector2(Hex.dir_vector(d).x, Hex.dir_vector(d).z)
		var perp := Vector2(-ax.y, ax.x)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in outline:
			lo.x = minf(lo.x, p.dot(ax))
			hi.x = maxf(hi.x, p.dot(ax))
			lo.y = minf(lo.y, p.dot(perp))
			hi.y = maxf(hi.y, p.dot(perp))
		var e := hi - lo
		if e.x > best.x:
			best = e
	return best


## Distance from p to the rim of a water body (outline, optional island): positive in the water.
static func rim_distance(p: Vector2, outline: PackedVector2Array, hole: PackedVector2Array) -> float:
	var d := INF
	var inside := Geometry2D.is_point_in_polygon(p, outline)
	for i in outline.size():
		var q := Geometry2D.get_closest_point_to_segment(p, outline[i], outline[(i + 1) % outline.size()])
		d = minf(d, p.distance_to(q))
	if not inside:
		d = -d
	if not hole.is_empty():
		var dh := INF
		for i in hole.size():
			var q := Geometry2D.get_closest_point_to_segment(p, hole[i], hole[(i + 1) % hole.size()])
			dh = minf(dh, p.distance_to(q))
		if Geometry2D.is_point_in_polygon(p, hole):
			dh = -dh
		d = minf(d, dh)
	return d


## The biggest circle in the water: [radius, centre] (a grid search, 0.05 fine).
static func inradius(outline: PackedVector2Array, hole: PackedVector2Array) -> Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in outline:
		lo = lo.min(p)
		hi = hi.max(p)
	var best := -INF
	var at := Vector2.ZERO
	var step := 0.1
	var y := lo.y
	while y <= hi.y:
		var x := lo.x
		while x <= hi.x:
			var d := rim_distance(Vector2(x, y), outline, hole)
			if d > best:
				best = d
				at = Vector2(x, y)
			x += step
		y += step
	# refine
	for _i in 3:
		step *= 0.3
		var c := at
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var q := c + Vector2(dx, dy) * step
				var d := rim_distance(q, outline, hole)
				if d > best:
					best = d
					at = q
	return [best, at]


## The longest straight run the shark's centre has (the longest chord of the outline pulled in by BODY_CLEAR).
static func longest_run(outline: PackedVector2Array) -> float:
	var inner := PoolGeo.offset(Array(outline), -BODY_CLEAR)
	var best := 0.0
	for i in inner.size():
		for j in range(i + 1, inner.size()):
			best = maxf(best, inner[i].distance_to(inner[j]))
	return best


static func perimeter(poly: PackedVector2Array) -> float:
	var t := 0.0
	for i in poly.size():
		t += poly[i].distance_to(poly[(i + 1) % poly.size()])
	return t


static func _print_shape(look: String, v: Dictionary) -> void:
	var ol: PackedVector2Array = v["outline"]
	var ext := _extents(ol)
	var ir: Array = inradius(ol, PackedVector2Array())
	var r_in: float = ir[0]
	var r_circle := r_in - BODY_CLEAR
	var r_rigid := _rigid_circle(r_in)
	var run_len := longest_run(ol)
	# the patrol lap: the outline pulled in to the middle of the space the shark's centre may use
	var lane := minf(BODY_CLEAR + 0.6, r_in * 0.6)
	var lap := perimeter(PoolGeo.offset(Array(ol), -lane))
	var verdict := "turns round (circles at R %.1f)" % r_circle if r_circle >= R_CRUISE else ("tight turns only" if r_circle >= R_MIN else "no turn: back and forth")
	print("%-22s %5d %5d %6.1f x %4.1f %6.1f %6.2f %8.2f %8s %7.1f %7.1f  %s" % [look, int(v["size"]), int(v["cells"]),
		ext.x, ext.y, absf(PoolGeo.area(ol)), r_in, r_circle, ("%.2f" % r_rigid) if r_rigid > 0.0 else "none", run_len, lap, verdict])


## A rigid 2.4 body circling at R: its nose and tail (1.2 ahead and behind on the tangent) swing out to sqrt(R^2 + 1.2^2).
static func _rigid_circle(r_in: float) -> float:
	var room := r_in - HALF_WIDTH
	var h := SHARK_LEN * 0.5
	return sqrt(room * room - h * h) if room > h else -1.0


static func _print_ring(label: String, v: Dictionary) -> void:
	var ol: PackedVector2Array = v["outline"]
	var hole: PackedVector2Array = v["hole"]
	var ext := _extents(ol)
	var width := rim_distance((ol[0] + ol[1] + hole[0] + hole[1]) * 0.25, ol, hole) * 2.0
	var mid := PackedVector2Array()
	for i in hole.size():
		mid.append((ol[i] + hole[i]) * 0.5)
	var lap := perimeter(mid)
	var fillet := corner_fillet(ol, hole, mid)
	var lane := width - 2.0 * BODY_CLEAR
	var verdict := "one way round; can't turn or face a rim" if lane < 2.0 * R_MIN else ("turns round (U-turn R %.1f)" % (lane * 0.5))
	print("%-22s %5d %5d %6.1f x %4.1f %6.1f  channel %.2f wide, lane %.2f, corner fillet R %.2f, side %.1f, lap %.1f  %s" % [label,
		int(v["size"]), int(v["cells"]), ext.x, ext.y, absf(PoolGeo.area(ol)) - absf(PoolGeo.area(hole)), width, lane, fillet,
		mid[0].distance_to(mid[1]), lap, verdict])


## The biggest arc radius that rounds a channel midline's corner while the centre stays BODY_CLEAR off both rims.
static func corner_fillet(ol: PackedVector2Array, hole: PackedVector2Array, mid: PackedVector2Array) -> float:
	var n := mid.size()
	var a := mid[n - 1]
	var c := mid[0]
	var b := mid[1]
	var u1 := (a - c).normalized()
	var u2 := (b - c).normalized()
	var half := acos(clampf(u1.dot(u2), -1.0, 1.0)) * 0.5
	var bis := (u1 + u2).normalized()
	var best := 0.0
	var r := 0.05
	while r < 6.0:
		var t := r / tan(half)                 # tangent points' distance from the corner
		if t > c.distance_to(a) * 0.5 or t > c.distance_to(b) * 0.5:
			break
		var centre := c + bis * (r / sin(half))
		var ok := true
		for k in 9:
			var p1 := c + u1 * t
			var p2 := c + u2 * t
			var s1 := (p1 - centre).angle()
			var s2 := (p2 - centre).angle()
			var ds := wrapf(s2 - s1, -PI, PI)
			var p := centre + Vector2.from_angle(s1 + ds * float(k) / 8.0) * r
			if rim_distance(p, ol, hole) < BODY_CLEAR - 0.001:
				ok = false
				break
		if not ok:
			break
		best = r
		r += 0.05
	return best


# --- proposed shapes ----------------------------------------------------------------------------------------------

## Three-row "lagoon" shark pools: every cell within one step of a row of k cells (k = 1: the 7-cell hexagon, 2: 3+4+3,
## 3: 4+5+4, 4: 5+6+5), in every orientation, built and checked by PoolGeo itself (in the moat's look). Biggest first.
static func lagoon_variants() -> Array:
	var out: Array = []
	var seen := {}
	for k in [4, 3, 2, 1]:
		var base := {}
		for i in k:
			for c in Hex.range_cells(Vector2i(i, 0), 1):
				base[c] = true
		for rot in 6:
			var basin: Array[Vector2i] = []
			for c: Vector2i in base:
				basin.append(PoolGeo.rotate(c, rot))
			basin.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
			var lo := basin[0]
			var norm: Array[Vector2i] = []
			for c in basin:
				norm.append(c - lo)
			var key := str(norm)
			if seen.has(key):
				continue
			seen[key] = true
			var v := PoolGeo._build_variant(basin, rot % 3, PoolGeo.MOAT_POOL)
			if not v.is_empty():
				out.append(v)
	return out


## Moat rings `rows` rows wide (PoolGeo's ring with the island `rows` ROWs in: every island side `rows` shorter), biggest
## first. rows = 1 is exactly PoolGeo's.
static func ring_variants(rows: int) -> Array:
	var out: Array = []
	var seen := {}
	var sides_list: Array = [
		[7, 7, 7, 7, 7, 7], [7, 6, 6, 7, 6, 6], [6, 6, 6, 6, 6, 6], [6, 5, 5, 6, 5, 5], [5, 5, 5, 5, 5, 5],
		[5, 4, 4, 5, 4, 4], [4, 4, 4, 4, 4, 4], [4, 3, 3, 4, 3, 3], [3, 3, 3, 3, 3, 3],
	] if rows >= 2 else PoolGeo.MOAT_SIDES
	for sides: Array in sides_list:
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
				continue
			var v := _build_ring(corners, (longest + rot) % 3, rows)
			if v.is_empty():
				continue
			var cells: Array[Vector2i] = []
			cells.append_array(v["basin"])
			for r: Vector2i in (v["ring"] as Dictionary):
				cells.append(r)
			cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
			var lo := cells[0]
			var norm: Array[Vector2i] = []
			for c in cells:
				norm.append(c - lo)
			var key := str(norm)
			if seen.has(key):
				continue
			seen[key] = true
			out.append(v)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["size"]) > int(b["size"]))
	return out


## PoolGeo._build_ring with the island `rows` rows in.
static func _build_ring(corners: Array[Vector2i], axis: int, rows: int) -> Dictionary:
	var pts := PackedVector2Array()
	for c in corners:
		pts.append(Vector2(Hex.to_world(c).x, Hex.to_world(c).z))
	var outline := PoolGeo._clean_hull(Geometry2D.convex_hull(pts))
	if outline.size() != 6:
		return {}
	var hole := PoolGeo.offset(Array(outline), -PoolGeo.ROW * float(rows))
	for i in hole.size():
		var w := Hex.to_world(Hex.from_world(Vector3(hole[i].x, 0.0, hole[i].y)))
		var hc := Vector2(w.x, w.z)
		if hc.distance_to(hole[i]) > 0.01:
			return {}
		hole[i] = hc
	if PoolGeo.area(hole) <= 0.0:
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
		var m := PoolGeo.kite_mask(c, outline, hole)
		if m == HexMap.ALL_KITES:
			basin.append(c)
		elif m != 0:
			ring[c] = m
	var wet := {}
	for b in basin:
		wet[b] = true
	for r: Vector2i in ring:
		wet[r] = true
	var walk: Array[Vector2i] = []
	var walk_set := {}
	for r: Vector2i in wet:
		for d in Hex.DIRS:
			var w: Vector2i = r + d
			if wet.has(w) or walk_set.has(w):
				continue
			walk_set[w] = true
			walk.append(w)
	var ax := Vector2(Hex.dir_vector(axis).x, Hex.dir_vector(axis).z)
	var perp := Vector2(-ax.y, ax.x)
	var half_len := 0.0
	var half_wid := 0.0
	for p in outline:
		half_len = maxf(half_len, absf((p - center).dot(ax)))
		half_wid = maxf(half_wid, absf((p - center).dot(perp)))
	return {"size": wet.size(), "cells": wet.size(), "basin": basin, "ring": ring, "walk": walk, "outline": outline,
		"hole": hole, "axis": axis, "center": center, "half_len": half_len, "half_wid": half_wid,
		"legs": [] as Array[Vector2i], "mid": c0}


# --- placement ------------------------------------------------------------------------------------------------------

## The moat rooms of the test_pools floors, each option placed the way PoolGeo.carve places a pool (lab copy of
## SiteBuilder.plan up to the carve; the real carve's own result is the "now" column's check).
static func _placement() -> void:
	PoolGeo._variants["moat2"] = ring_variants(2)
	PoolGeo._variants["lagoon"] = lagoon_variants()
	# the shark pool's shapes without the single rows (a shark cannot turn round in a row: r_in 1.5)
	var wide: Array = []
	for v: Dictionary in PoolGeo.variants(PoolGeo.MOAT_POOL):
		if float(inradius(v["outline"], PackedVector2Array())[0]) > 2.0:
			wide.append(v)
	PoolGeo._variants["moat_pool2"] = wide
	var options := {
		"A now: 1-row ring, else shark pool": ["moat", "moat_pool"],
		"A2: 1-row ring, else 2-row shark pool": ["moat", "moat_pool2"],
		"B: 2-row ring, else 1-row ring, else pool": ["moat2", "moat", "moat_pool"],
		"B2: 2-row ring, else shark pool": ["moat2", "moat_pool"],
		"C: shark pool only (all its shapes)": ["moat_pool"],
		"C2: shark pool only (2-row shapes)": ["moat_pool2"],
		"D: lagoon (3-row), else shark pool": ["lagoon", "moat_pool"],
		"D3: lagoon, else 2-row shark pool": ["lagoon", "moat_pool2"],
		"D2: lagoon only": ["lagoon"],
	}
	var stats := {}
	for name: String in options:
		stats[name] = {"rooms": 0, "got": {}, "none": 0, "cells": 0, "room_cells": 0, "fit_rooms": 0}
	var rooms := 0
	var room_sizes: Array[int] = []
	var real := {"ring": 0, "pool": 0, "none": 0}
	var sizes := {}
	var pool_rooms := {}
	for id in ClientArchetype.IDS:
		for s in RUN_SEEDS:
			var run := ContractRun.make(id, s, float(s % 10) / 10.0 + 0.05)
			for f in range(1, ContractRun.FLOOR_COUNT + 1):
				var map := DungeonGen.for_run(run, f)
				var ctx := _plan_to_carve(map, run, f)
				var p: SitePlan = ctx[0]
				for tag: String in p.room_themes:
					if String(p.room_themes[tag]) != "moat":
						continue
					rooms += 1
					room_sizes.append((p.rooms[tag] as Array).size())
					for name: String in options:
						var st: Dictionary = stats[name]
						var rng := RandomNumberGenerator.new()
						rng.seed = (run.floor_seed(f) * 613 + f * 7 + 1) * 31 + int(tag.trim_prefix("room:")) * 7919 + 17   # (PoolGeo.carve's)
						var got := ""
						var pick := {}
						for look: String in options[name]:
							pick = PoolGeo._choose(map, p, tag, look, ctx[1], ctx[2], ctx[3], rng)
							if not pick.is_empty():
								got = look
								break
						if got == "":
							st["none"] = int(st["none"]) + 1
						else:
							(st["got"] as Dictionary)[got] = int((st["got"] as Dictionary).get(got, 0)) + 1
							st["cells"] = int(st["cells"]) + int((pick["variant"] as Dictionary)["cells"])
							st["room_cells"] = int(st["room_cells"]) + (p.rooms[tag] as Array).size()
				# the real carve on the same plan, to check the copy matches the game
				PoolGeo.carve(map, p, ctx[1], ctx[2], run.floor_seed(f) * 613 + f * 7 + 1)
				for rec in map.pools:
					var key := "%s %d%s" % [rec["look"], (rec["basin"] as Array).size() if (rec["hole"] as Array).is_empty() else -1, "" if not (rec["hole"] as Array).is_empty() else (" 2-row" if float(rec["half_wid"]) > 2.0 else " 1-row")]
					sizes[key] = int(sizes.get(key, 0)) + 1
				for tag: String in p.room_themes:
					if PoolGeo.THEME_LOOK.has(String(p.room_themes[tag])):
						var lk: String = PoolGeo.THEME_LOOK[String(p.room_themes[tag])]
						pool_rooms[lk] = int(pool_rooms.get(lk, 0)) + 1
					if String(p.room_themes[tag]) != "moat":
						continue
					var rec := PoolGeo.pool_of_room(map, tag)
					if rec.is_empty():
						real["none"] = int(real["none"]) + 1
					elif (rec["hole"] as Array).is_empty():
						real["pool"] = int(real["pool"]) + 1
					else:
						real["ring"] = int(real["ring"]) + 1
	room_sizes.sort()
	print("\n=== MOAT PLACEMENT: %d moat rooms on the test_pools floors (room cells: min %d, median %d, max %d) ===" % [rooms,
		room_sizes[0], room_sizes[room_sizes.size() / 2], room_sizes[room_sizes.size() - 1]])
	print("the game's own carve on these floors: %d rings, %d shark pools, %d none" % [real["ring"], real["pool"], real["none"]])
	print("every pool the carve made, by look and basin cells (-1 = a ring): %s; rooms by look: %s" % [str(sizes), str(pool_rooms)])
	for name: String in options:
		var st: Dictionary = stats[name]
		var placed := rooms - int(st["none"])
		print("%-44s placed %2d / %d (%3.0f%%)  %s  none %2d  mean water %.1f cells (%.0f%% of its room)" % [name, placed, rooms,
			100.0 * float(placed) / float(maxi(rooms, 1)), str(st["got"]), int(st["none"]),
			float(st["cells"]) / float(maxi(placed, 1)), 100.0 * float(st["cells"]) / float(maxi(int(st["room_cells"]), 1))])


## SiteBuilder.plan's steps up to PoolGeo.carve (the same order and seeds): [plan, avoid, near_corr, gate_zone].
static func _plan_to_carve(map: HexMap, run: ContractRun, floor_n: int) -> Array:
	var p := SitePlan.new()
	p.floor_number = floor_n
	var rng := RandomNumberGenerator.new()
	rng.seed = run.floor_seed(floor_n) * 131 + floor_n * 17 + 5
	var starts := map.cells_with_tag("start")
	var exits := map.cells_with_tag("exit")
	p.start = starts[0] if not starts.is_empty() else Vector2i.ZERO
	p.exit = exits[0] if not exits.is_empty() else p.start
	SiteBuilder._index_rooms(map, p)
	var near_corr := SiteBuilder._corridor_zone(map)
	var avoid := {}
	for c in SiteBuilder._area(p.start, SiteBuilder.START_CLEAR):
		avoid[c] = true
	for c in SiteBuilder._area(p.exit, SiteBuilder.EXIT_CLEAR):
		avoid[c] = true
	p.elevator = map.elevator.duplicate(true)
	if not p.elevator.is_empty():
		p.elevator["look"] = run.elevator_look
	for c in ElevatorGeo.keep_cells(p.elevator):
		avoid[c] = true
	GatePlanner.plan(map, run, floor_n, p, rng, avoid, near_corr)
	SiteBuilder._plan_employees(map, run, floor_n, p, rng, avoid)
	RoomThemes.assign(p, run.site_type, run.story, floor_n, run.floor_seed(floor_n))
	var gate_zone := {}
	for g in p.gates:
		for c in Hex.range_cells(g["cell"], PoolGeo.ORIGIN_GATE_CLEAR if bool(g["origin"]) else PoolGeo.GATE_CLEAR):
			gate_zone[c] = true
	return [p, avoid, near_corr, gate_zone]
