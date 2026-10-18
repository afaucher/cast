class_name ElevatorGeo
extends RefCounted
## The elevator as floor geometry (docs/design/elevator-options.md, "Built"): where it can stand, the cells and the
## collision it takes, and where the crew stands in it and outside it. Pure and deterministic (no random numbers):
## DungeonGen picks the spot and writes the record to HexMap.elevator, SiteBuilder keeps everything else off it, and
## ElevatorArrival builds the model and the arrival beat from the same record.
##
## Two PLACEMENTS (the job picks one, ContractRun.elevator_place):
##   "wall"  the car is a 3-cell NOTCH cut into a camera-facing wall of a room (option A). Three wall cells behind a
##           straight stretch of the room's wall line become floor before the walls are built, so the midpoint walls open
##           exactly a trapezoid: a 5.2 mouth on the room's wall line and the car's back wall on the next hex wall line,
##           1.5 behind it. The two slanted slivers beside the car are filled by the jambs (two solids). Nothing walkable
##           lies within two cells behind or beside the notch.
##   "free"  free-standing in the middle of a room (option C): a hexagonal car whose corners stand on the six neighbour
##           centres of one cell, so its sides lie on midpoint-wall lines. Five sides are solid (the glass shaft, or the
##           freight platform's railings), the sixth is the door. The seven cells under it are HexMap.no_stand.
## The door faces the iso camera: 15 degrees off it (yaw 60, preferred) or 45 (yaw 0).
##
## The record (HexMap.elevator; SitePlan.elevator adds the job's look):
##   place "wall" | "free"; fallback (true: a wall job whose floor had no wall slot); pos (Vector2, the model's origin: the
##   middle of the mouth on the wall line / the middle of the car); yaw (degrees, model +Z = out of the car); level (int);
##   room (int, DungeonGen's room index); cells (Array[Vector2i], the car's cells); landing (Vector2i, the exit cell: the
##   full cell straight in front of the doors, 1.5 out); door (Vector2, the middle of the doorway); out (Vector2, unit, out
##   of the car); inside (Array[Vector2], the crew's spots in the car's front row: middle, left, right); steps
##   (Array[Vector2], where each stands once out, the first on the landing); via (Array[Vector2], the doorway point each
##   walks through).

const PLACE_WALL := "wall"
const PLACE_FREE := "free"
const WALL_KS: Array[int] = [2, 1]     ## notch back directions tried: DIRS[k], DIRS[k + 1] point from the room into the notch
const FREE_JS: Array[int] = [5, 4]     ## free car doors tried: the door side lies between neighbours DIRS[j] and DIRS[j + 1]

const CAR_HALF := 1.732                ## the notch car's inner half width (sqrt 3)
const CAR_DEPTH := 1.5
const JAMB_IN := 1.70                  ## the jamb solids span |x| = JAMB_IN .. JAMB_OUT, z = JAMB_BACK .. JAMB_FRONT (local)
const JAMB_OUT := 2.78
const JAMB_BACK := -1.58
const JAMB_FRONT := 0.14
const SHAFT_R := 1.732                 ## the free car's corner radius (its corners on the neighbour centres)
const SHAFT_APOTHEM := 1.5
const FACE_HALF_T := 0.07              ## half the thickness of a free car's solid side
const FACE_OVERRUN := 0.1              ## ... and how far it runs past each corner (the corner post)

## Local (model frame: x right, z out of the car) crew spots, in the order middle, left, right.
const WALL_INSIDE: Array[Vector2] = [Vector2(0.0, -0.62), Vector2(-1.05, -0.62), Vector2(1.05, -0.62)]
const WALL_STEPS: Array[Vector2] = [Vector2(0.0, 1.5), Vector2(-1.35, 1.85), Vector2(1.35, 1.95)]
const WALL_VIA: Array[Vector2] = [Vector2(0.0, 0.1), Vector2(-0.8, 0.1), Vector2(0.8, 0.1)]
const FREE_INSIDE: Array[Vector2] = [Vector2(0.0, 0.55), Vector2(-0.72, 0.4), Vector2(0.72, 0.4)]
const FREE_STEPS: Array[Vector2] = [Vector2(0.0, 3.0), Vector2(-1.4, 2.75), Vector2(1.4, 2.85)]
const FREE_VIA: Array[Vector2] = [Vector2(0.0, 1.5), Vector2(-0.25, 1.5), Vector2(0.25, 1.5)]


static func _d(i: int) -> Vector2i:
	return Hex.DIRS[posmod(i, 6)]


static func _dv(i: int) -> Vector2:
	var v := Hex.dir_vector(posmod(i, 6))
	return Vector2(v.x, v.z)


# --- the wall notch -----------------------------------------------------------------------------------------------

## The cells of a notch whose first mouth cell is m0, back direction k: n (the three car cells, becoming floor), m (the
## four mouth cells on the room's wall line), e (the two cells beside the car, staying wall), landing, R (along the wall).
static func notch_cells(m0: Vector2i, k: int) -> Dictionary:
	var r := _d(k + 2)
	var n0 := m0 + _d(k + 1)
	var ns: Array[Vector2i] = [n0, n0 + r, n0 + r * 2]
	var ms: Array[Vector2i] = [m0, m0 + r, m0 + r * 2, m0 + r * 3]
	var es: Array[Vector2i] = [n0 - r, n0 + r * 3]
	return {"n": ns, "m": ms, "e": es, "landing": n0 + r + _d(k + 3) + _d(k + 4), "R": r}


## Can a notch go behind mouth cell m0 of `room` (cell -> true) with back direction k? Checked on the floor plan BEFORE
## the walls exist (`map` holds the rooms and corridors only, all room cells still at the room's level). {} when it
## cannot, else {"strict": the room's wall line runs straight one more cell past each end of the mouth}.
static func wall_slot(map: HexMap, room: Dictionary, m0: Vector2i, k: int) -> Dictionary:
	var g := notch_cells(m0, k)
	for m: Vector2i in g["m"]:
		if not room.has(m):
			return {}
	var notch := {}
	for n: Vector2i in g["n"]:
		notch[n] = true
		if map.has_cell(n):
			return {}
	for e: Vector2i in g["e"]:
		if map.has_cell(e):
			return {}
	# nothing walkable behind or beside the car: every floor cell within two cells of it is this room's
	for n: Vector2i in g["n"]:
		for x in Hex.range_cells(n, 2):
			if map.has_cell(x) and not room.has(x):
				return {}
	for e: Vector2i in g["e"]:
		for x in Hex.range_cells(e, 1):
			if map.has_cell(x) and not room.has(x):
				return {}
	# the landing and the floor around it: this room's, and full once the walls are cut
	var landing: Vector2i = g["landing"]
	var ends: Array = g["e"]
	for x in Hex.range_cells(landing, 2):
		if not room.has(x) and not notch.has(x) and not ends.has(x):
			return {}
	for x in Hex.range_cells(landing, 1):
		for d in Hex.DIRS:
			if not room.has(x + d) and not notch.has(x + d):
				return {}
	var r: Vector2i = g["R"]
	var e0: Vector2i = ends[0]
	var e1: Vector2i = ends[1]
	var m3: Vector2i = (g["m"] as Array)[3]
	var strict := room.has(m0 - r) and room.has(m3 + r) and not map.has_cell(e0 - r) and not map.has_cell(e1 + r)
	return {"strict": strict}


## The record of a notch elevator (see the header).
static func make_wall(m0: Vector2i, k: int, level: int, room_index: int) -> Dictionary:
	var g := notch_cells(m0, k)
	var ms: Array = g["m"]
	var pos := (ThemeGeo.world(ms[1]) + ThemeGeo.world(ms[2])) * 0.5
	var out := -(_dv(k) + _dv(k + 1)).normalized()
	var rec := {
		"place": PLACE_WALL, "fallback": false, "k": k, "pos": pos, "yaw": ThemeGeo.yaw_of(out), "level": level,
		"room": room_index, "cells": (g["n"] as Array).duplicate(), "mouth": ms.duplicate(), "landing": g["landing"],
		"door": pos, "out": out,
	}
	_add_spots(rec, WALL_INSIDE, WALL_STEPS, WALL_VIA)
	return rec


# --- the free-standing car ----------------------------------------------------------------------------------------

## Can the free car stand on cell c of `room` with its door between DIRS[j] and DIRS[j + 1]? The car, a walk round it and
## the landing in front must all be this room's flat floor (checked before the features and walls exist).
static func free_ok(room: Dictionary, c: Vector2i, j: int) -> bool:
	for x in Hex.range_cells(c, 3):
		if not room.has(x):
			return false
	var landing := c + _d(j) + _d(j + 1)
	for x in Hex.range_cells(landing, 2):
		if not room.has(x):
			return false
	return true


static func make_free(c: Vector2i, j: int, level: int, room_index: int) -> Dictionary:
	var out := (_dv(j) + _dv(j + 1)).normalized()
	var pos := ThemeGeo.world(c)
	var cells: Array[Vector2i] = [c]
	for d in Hex.DIRS:
		cells.append(c + d)
	var rec := {
		"place": PLACE_FREE, "fallback": false, "j": j, "pos": pos, "yaw": ThemeGeo.yaw_of(out), "level": level,
		"room": room_index, "cells": cells, "landing": c + _d(j) + _d(j + 1), "door": pos + out * SHAFT_APOTHEM, "out": out,
	}
	_add_spots(rec, FREE_INSIDE, FREE_STEPS, FREE_VIA)
	return rec


# --- shared ----------------------------------------------------------------------------------------------------

static func _add_spots(rec: Dictionary, inside: Array[Vector2], steps: Array[Vector2], via: Array[Vector2]) -> void:
	var pos: Vector2 = rec["pos"]
	var yaw: float = rec["yaw"]
	for key: String in ["inside", "steps", "via"]:
		var src: Array[Vector2] = inside if key == "inside" else (steps if key == "steps" else via)
		var pts: Array[Vector2] = []
		for p in src:
			pts.append(ThemeGeo.local_to_world(pos, yaw, p.x, p.y))
		rec[key] = pts


## A point in the model's frame (x right, z out of the car) -> world X/Z.
static func to_world(rec: Dictionary, local: Vector2) -> Vector2:
	return ThemeGeo.local_to_world(rec["pos"], float(rec["yaw"]), local.x, local.y)


## World X/Z -> the model's frame.
static func to_local(rec: Dictionary, p: Vector2) -> Vector2:
	var d := p - (rec["pos"] as Vector2)
	var yaw := float(rec["yaw"])
	return Vector2(d.dot(ThemeGeo.lateral(yaw)), d.dot(ThemeGeo.facing(yaw)))


## The polygons (world X/Z) that block bodies: the notch's two jambs, or the free car's five closed sides.
static func solids(rec: Dictionary) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if rec.is_empty():
		return out
	if str(rec["place"]) == PLACE_WALL:
		for sgn: float in [-1.0, 1.0]:
			var poly := PackedVector2Array()
			for q: Vector2 in [Vector2(JAMB_IN, JAMB_BACK), Vector2(JAMB_OUT, JAMB_BACK), Vector2(JAMB_OUT, JAMB_FRONT), Vector2(JAMB_IN, JAMB_FRONT)]:
				poly.append(to_world(rec, Vector2(q.x * sgn, q.y)))
			out.append(poly)
		return out
	for k in 5:
		var a := _corner(k)
		var b := _corner(k + 1)
		var t := (b - a).normalized()
		var n := Vector2(-t.y, t.x) * FACE_HALF_T
		var a2 := a - t * FACE_OVERRUN
		var b2 := b + t * FACE_OVERRUN
		var poly := PackedVector2Array()
		for q: Vector2 in [a2 + n, b2 + n, b2 - n, a2 - n]:
			poly.append(to_world(rec, q))
		out.append(poly)
	return out


## Corner k of the free car in its local frame: corners stand at 30 + 60k degrees from +Z (the door side lies between
## corners 5 and 0), on the neighbour centres (ElevatorModel._corner).
static func _corner(k: int) -> Vector2:
	var a := deg_to_rad(30.0 + 60.0 * k)
	return Vector2(sin(a), cos(a)) * SHAFT_R


## Is world X/Z point p inside the car (its floor, between the doors and the back)?
static func inside(rec: Dictionary, p: Vector2) -> bool:
	if rec.is_empty():
		return false
	var l := to_local(rec, p)
	if str(rec["place"]) == PLACE_WALL:
		return l.y >= -CAR_DEPTH - 0.05 and l.y <= 0.05 and absf(l.x) <= CAR_HALF + 0.02
	for i in 6:
		var a := deg_to_rad(60.0 * i)
		if l.dot(Vector2(sin(a), cos(a))) > SHAFT_APOTHEM:
			return false
	return true


## The distance from world X/Z point p to the elevator's door or its landing, whichever is nearer (0 inside the car).
static func door_distance(rec: Dictionary, p: Vector2) -> float:
	if rec.is_empty():
		return INF
	if inside(rec, p):
		return 0.0
	return minf(p.distance_to(rec["door"]), p.distance_to(ThemeGeo.world(rec["landing"])))


## The cells the elevator keeps for itself (nothing is planned or spawned on them): the car, the doorway and landing, and
## for the free car the walk round it.
static func keep_cells(rec: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if rec.is_empty():
		return out
	var seen := {}
	var src: Array[Vector2i] = []
	for c: Vector2i in (rec["cells"] as Array):
		src.append(c)
	if str(rec["place"]) == PLACE_WALL:
		for c: Vector2i in (rec["mouth"] as Array):
			src.append(c)
	for c in src:
		for x in Hex.range_cells(c, 1 if str(rec["place"]) == PLACE_WALL else 2):
			if not seen.has(x):
				seen[x] = true
				out.append(x)
	for x in Hex.range_cells(rec["landing"], 1):
		if not seen.has(x):
			seen[x] = true
			out.append(x)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out
