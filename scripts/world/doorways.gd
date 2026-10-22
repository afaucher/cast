class_name Doorways
extends RefCounted
## The floor's SPACES and DOORWAYS, read from the map alone (pure data, deterministic, no rng): what room fog
## (RoomFog) and office doors (OfficeDoor) are built on. docs/design/exploration.md, "Decisions: map information, fog and doors", 2026-10-19.
##
## SPACES. Every room ("room:N" cells, SitePlan.rooms) is a space, and so is every HALL: one connected run of "corridor"
## cells ("hall:0", "hall:1", ... in the order of each run's first cell). A corridor is its own space, not part of the room
## it leads to: a door stands between the two, so the two must be able to differ. The cells that carry neither tag
## (the start and exit cells, the bits of a room only a climb reaches) take the space of the nearest tagged cell (a
## breadth-first fill over floor cells). Wall cells are in no space.
##
## DOORWAYS. Where a hall's cells touch a room's: the room's DOOR cells (room cells next to the hall: DungeonGen's door
## cell and its flared neighbours) and the hall's MOUTH cells (hall cells next to the room), one doorway per connected
## patch of them. Each has `mid` (the middle of the opening on the floor), `axis` (the unit direction from the room into
## the hall, snapped to a hex direction, which is what corridor walls run along) and `dead_end` (its hall leads nowhere
## else). Where the flare has ended, about one cell into the hall, the corridor's WIDTH between its wall faces is measured:
## 4.5 for a tree link (two full lanes), 3.0 for a loop, the climb shortcut or the chokepoint (one full lane: NARROW).
##
## THE DOOR PLACE (on the hex grid, never at an angle; only a NARROW doorway has one, the user's rule: a wide hallway
## always meets its room open): the DOORWAY CELL `cell` (the corridor's full cell just past the door, on its centre lane),
## the BAND (that cell and the two cut cells beside it on the room side, cell + DIRS[axis +/- 2]: a chevron that closes the
## corridor wall to wall), `edges` (the hex edges between the band and the room, clipped to the floor), and the DOOR LINE:
## `a` / `b`, its two JAMBS (wall points, hex centres), `center` their middle on the floor. `door_ok` says it has all of that.
## The door line is SQUARE across the corridor through the band's two cut cells (_square_place; user, 2026-10-21: "normal
## doors would be placed perpendicular to the hall, or at least prioritize the shortest span"): the corridor's width, 3.0,
## its shortest cut, at the lane cell nearest the room whose line seals the opening, so one jamb is where the corridor's
## second wall ends and the other on the opposite corridor wall (both on the room's wall line where it meets the corridor
## square on). Only where no lane cell has one (none on the 90 floors test_door_span builds) is it the older chord
## between the two points where the corridor's wall faces end at the room, which could run diagonally across a flared or
## oblique mouth. `flush`: the room wall runs straight past both jambs. settle() then moves the cells on the wrong side
## of a door line to the space on their side (fog goes by cell).
##
##   var sp := Doorways.spaces(map)          # {cell_space, cells, kind, order}
##   var dws := Doorways.find(map, sp)       # [{id, room, hall, door_cells, mouth_cells, mid, axis, width, narrow, dead_end,
##                                           #   ok, door_ok, cell, center, band, edges, a, b}]
##   Doorways.settle(map, sp["cell_space"], dws)   # (the fog's spaces: each door's cells on its own side)

const HALL_PREFIX := "hall:"
const SPAN_STEP := 0.3          ## how far apart the cross-sections tried for a door are (world units along the axis)
const SPAN_FROM := 0.6          ## the first cross-section tried, measured from the mouth's middle into the hall
const SPAN_TO := 3.9            ## the last one
const SPAN_MAX := 4.9           ## a corridor is at most this wide (a tree-link corridor is 4.5 between its walls)
const SPAN_MIN := 2.0
const NARROW_MAX := 3.6         ## a corridor this wide or less is NARROW (one full lane, 3.0): only those take a door
const JAMB_SEARCH := 4.5        ## how far back toward the room a corridor wall is followed to its end (the jamb)
const JAMB_SPAN_MAX := 5.2      ## a door chord longer than this (a very oblique mouth) is no door place
const MARCH := 0.04             ## the step of the march out to each wall face
const MARCH_MAX := 3.4
const SQUARE_BACK := 2          ## the square door place is looked for from this many lane cells toward the room ...
const SQUARE_ON := 3            ## ... to this many into the hall, from the doorway cell the cross-section found
const SEAL_REACH := 0.12        ## a door's line runs on this far into wall past each jamb (it seals the opening)
const SEAL_SAMPLES := 24        ## points tried along a door's line for open, level floor
const SETTLE_REACH := 4.5       ## settle(): cells this close to a door's middle take the space on their side of it ...
const SETTLE_ON := 0.05         ## ... unless their floor is this close to the door line (a jamb's cut cell)
const SIGHT_STEP := 0.1         ## settle()'s plain-sight test samples the line this finely
const MARCH_COARSE := 5         ## the march's stride, in MARCH steps (0.2): finer steps only inside the stride that hits


## Spaces of `map`: {cell_space: {Vector2i: tag}, cells: {tag: Array[Vector2i] (sorted)}, kind: {tag: "room"|"hall"},
## order: Array[String] (rooms by number, then halls)}.
static func spaces(map: HexMap) -> Dictionary:
	var cell_space := {}
	var keys: Array[Vector2i] = []
	for c: Vector2i in map.cells:
		keys.append(c)
	keys.sort_custom(_cell_less)
	# Rooms by tag.
	for c in keys:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type != HexMap.Tile.WALL and cell.tag.begins_with("room:"):
			cell_space[c] = cell.tag
	# Halls: connected runs of corridor cells, numbered in the order of their first (smallest) cell.
	var hall_n := 0
	for c in keys:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type == HexMap.Tile.WALL or cell.tag != "corridor" or cell_space.has(c):
			continue
		var tag := HALL_PREFIX + str(hall_n)
		hall_n += 1
		var queue: Array[Vector2i] = [c]
		cell_space[c] = tag
		var qi := 0
		while qi < queue.size():
			var cur := queue[qi]
			qi += 1
			for d in Hex.DIRS:
				var nb: Vector2i = cur + d
				var nc: HexMap.Cell = map.cells.get(nb)
				if nc != null and nc.type != HexMap.Tile.WALL and nc.tag == "corridor" and not cell_space.has(nb):
					cell_space[nb] = tag
					queue.append(nb)
	# Everything else that is floor: the nearest tagged cell's space (breadth first from every tagged cell, in cell order).
	var frontier: Array[Vector2i] = []
	for c in keys:
		if cell_space.has(c):
			frontier.append(c)
	var fi := 0
	while fi < frontier.size():
		var cur := frontier[fi]
		fi += 1
		for d in Hex.DIRS:
			var nb: Vector2i = cur + d
			var nc: HexMap.Cell = map.cells.get(nb)
			if nc != null and nc.type != HexMap.Tile.WALL and not cell_space.has(nb):
				cell_space[nb] = cell_space[cur]
				frontier.append(nb)
	var cells := {}
	var kind := {}
	for c in keys:
		if not cell_space.has(c):
			continue
		var tag: String = cell_space[c]
		if not cells.has(tag):
			cells[tag] = [] as Array[Vector2i]
			kind[tag] = "hall" if tag.begins_with(HALL_PREFIX) else "room"
		(cells[tag] as Array[Vector2i]).append(c)
	var order: Array[String] = []
	for tag: String in cells:
		order.append(tag)
	order.sort_custom(_tag_less)
	return {"cell_space": cell_space, "cells": cells, "kind": kind, "order": order}


## The doorways of `map` (see the header). `sp` is spaces(map) (computed when empty).
static func find(map: HexMap, sp: Dictionary = {}) -> Array[Dictionary]:
	if sp.is_empty():
		sp = spaces(map)
	var cell_space: Dictionary = sp["cell_space"]
	var kind: Dictionary = sp["kind"]
	# Contact cells per (room, hall) pair.
	var pairs := {}
	for tag: String in sp["order"]:
		if kind[tag] != "hall":
			continue
		for c: Vector2i in (sp["cells"][tag] as Array[Vector2i]):
			# Only the hall's own corridor cells and the room's own room cells touch: a cell that merely took the nearest
			# space (spaces' fill: the start and exit cells, a climb-only bit, a lava cave's lava) is no part of a doorway.
			# (It was: two such filled cells touching made a doorway patch out in the open, its middle at THEIR height, so
			# a lava cave's doorways sat on the lava bed, below the bridge, and line of sight to them failed from some
			# spots and not others: the "I see the shortcut from here but not from there" fog.)
			if map.cells[c].tag != "corridor":
				continue
			for d in Hex.DIRS:
				var nb: Vector2i = c + d
				var other: String = cell_space.get(nb, "")
				if other == "" or kind.get(other, "") != "room" or map.cells[nb].tag != other:
					continue
				var key := other + "|" + tag
				if not pairs.has(key):
					pairs[key] = {"room": other, "hall": tag, "door": {}, "mouth": {}}
				(pairs[key]["door"] as Dictionary)[nb] = true
				(pairs[key]["mouth"] as Dictionary)[c] = true
	var pair_keys: Array = pairs.keys()
	pair_keys.sort_custom(func(x: String, y: String) -> bool:
		var rx := x.split("|")
		var ry := y.split("|")
		return _tag_less(rx[0], ry[0]) if rx[0] != ry[0] else _tag_less(rx[1], ry[1]))
	var out: Array[Dictionary] = []
	for key: String in pair_keys:
		var p: Dictionary = pairs[key]
		for patch in _patches(p["door"], p["mouth"]):
			var dw := {"id": out.size(), "room": p["room"], "hall": p["hall"], "door_cells": patch[0], "mouth_cells": patch[1]}
			_shape(map, dw, sp)
			out.append(dw)
	# A dead end: the hall touches one room only.
	var rooms_of := {}
	for dw in out:
		if not rooms_of.has(dw["hall"]):
			rooms_of[dw["hall"]] = {}
		(rooms_of[dw["hall"]] as Dictionary)[dw["room"]] = true
	for dw in out:
		dw["dead_end"] = (rooms_of[dw["hall"]] as Dictionary).size() < 2
	return out


## SETTLE the spaces at the door places (after find()): a door stands square across its corridor where the corridor's
## second wall ends (_square_place), which need not be where the tags change from corridor to room, so some of the hall's
## cells can lie on the room side of the door line (or the room's on the hall side). Fog goes by cell (a hero's space is
## the cell under them), so each such cell moves to the space on its side: every cell of the doorway's room or hall whose
## floor is within SETTLE_REACH of the door's middle, in plain sight of it (no wall between) and off the line by more than
## SETTLE_ON. In plain sight is what keeps it to the opening: a straight line from the door's middle reaches the other side
## of a sealing door only through a wall. The jambs' own cut cells (their centres on the line) keep their spaces.
## `cell_space` maps cell -> space (spaces()' tags, or RoomFog's indices); each doorway names its room's and hall's space
## under `room_key` / `hall_key`. Changes cell_space in place (only it: spaces()' `cells` lists stay as they were) and
## returns the cells it moved. Deterministic, from the map alone. RoomFog.build settles its spaces this way, after cutting
## its long halls (so the cuts fall where they did).
static func settle(map: HexMap, cell_space: Dictionary, dws: Array[Dictionary], room_key: String = "room", hall_key: String = "hall") -> Array[Vector2i]:
	var moved := {}
	var order: Array[Vector2i] = []
	for dw in dws:
		if not bool(dw.get("door_ok", false)) or not dw.has("a") or not dw.has(room_key) or not dw.has(hall_key):
			continue
		var a: Vector2 = dw["a"]
		var b: Vector2 = dw["b"]
		var m := (a + b) * 0.5
		var t := (b - a).normalized()
		var n := Vector2(-t.y, t.x)
		var ax: Vector3 = dw["axis"]
		if n.dot(Vector2(ax.x, ax.z)) < 0.0:
			n = -n   # (toward the hall)
		var room: Variant = dw[room_key]
		var hall: Variant = dw[hall_key]
		var around := Hex.range_cells(Hex.from_world(Vector3(m.x, 0.0, m.y)), ceili(SETTLE_REACH / (Hex.SIZE * Hex.SQRT3)) + 1)
		around.sort_custom(_cell_less)
		for c in around:
			if not cell_space.has(c):
				continue
			var space: Variant = cell_space[c]
			if space != room and space != hall:
				continue
			var cell: HexMap.Cell = map.cells[c]
			if cell.type == HexMap.Tile.WALL or cell.wall_mask == HexMap.ALL_KITES:
				continue
			var fp := _floor_point(cell, c)
			var side := (fp - m).dot(n)
			if fp.distance_to(m) > SETTLE_REACH or absf(side) <= SETTLE_ON or not _in_sight(map, m, fp):
				continue
			var want: Variant = hall if side > 0.0 else room
			if want != space:
				if not moved.has(c):
					order.append(c)
				moved[c] = want
	var out: Array[Vector2i] = []
	for c in order:
		if cell_space[c] != moved[c]:
			cell_space[c] = moved[c]
			out.append(c)
	return out


## A cell's floor, flat (world X/Z): its centre, or for a cut cell the middle of its floor kites.
static func _floor_point(cell: HexMap.Cell, c: Vector2i) -> Vector2:
	var w := Hex.to_world(c)
	if cell.wall_mask == 0:
		return Vector2(w.x, w.z)
	var d := Vector2.ZERO
	for k in 6:
		if (cell.wall_mask >> k) & 1 == 0:
			var ang := (k + 0.5) * PI / 3.0
			d += Vector2(cos(ang), -sin(ang))
	if d.length() < 0.001:
		return Vector2(w.x, w.z)
	return Vector2(w.x, w.z) + d.normalized() * Hex.SIZE * 0.5


## No wall on the flat line from p to q (sampled every SIGHT_STEP).
static func _in_sight(map: HexMap, p: Vector2, q: Vector2) -> bool:
	var n := maxi(1, ceili(p.distance_to(q) / SIGHT_STEP))
	for i in range(1, n + 1):
		var x := p.lerp(q, float(i) / n)
		if map.wall_at(Vector3(x.x, 0.0, x.y)):
			return false
	return true


## Split a pair's contact cells into connected patches: [[door cells], [mouth cells]] per patch, in cell order.
static func _patches(door: Dictionary, mouth: Dictionary) -> Array:
	var all: Array[Vector2i] = []
	for c: Vector2i in door:
		all.append(c)
	for c: Vector2i in mouth:
		if not door.has(c):
			all.append(c)
	all.sort_custom(_cell_less)
	var seen := {}
	var out := []
	for c in all:
		if seen.has(c):
			continue
		var d_cells: Array[Vector2i] = []
		var m_cells: Array[Vector2i] = []
		var queue: Array[Vector2i] = [c]
		seen[c] = true
		var qi := 0
		while qi < queue.size():
			var cur := queue[qi]
			qi += 1
			if door.has(cur):
				d_cells.append(cur)
			else:
				m_cells.append(cur)
			for dd in Hex.DIRS:
				var nb: Vector2i = cur + dd
				if not seen.has(nb) and (door.has(nb) or mouth.has(nb)):
					seen[nb] = true
					queue.append(nb)
		d_cells.sort_custom(_cell_less)
		m_cells.sort_custom(_cell_less)
		out.append([d_cells, m_cells])
	return out


## The doorway's middle, its axis and its door span.
static func _shape(map: HexMap, dw: Dictionary, sp: Dictionary) -> void:
	var door_c: Array[Vector2i] = dw["door_cells"]
	var mouth_c: Array[Vector2i] = dw["mouth_cells"]
	var rc := _centroid(door_c)
	var mc := _centroid(mouth_c)
	var mid := (rc + mc) * 0.5
	var g := map.ground_height(mid)
	mid.y = 0.0 if is_nan(g) else g
	dw["mid"] = mid
	# The axis: from the mouth toward the hall cells 3-4 steps in (a corridor runs straight there), else room -> mouth.
	var hall: String = dw["hall"]
	var cell_space: Dictionary = sp["cell_space"]
	var dist := {}
	var queue: Array[Vector2i] = []
	for c in mouth_c:
		dist[c] = 0
		queue.append(c)
	var far: Array[Vector2i] = []
	var qi := 0
	while qi < queue.size():
		var cur := queue[qi]
		qi += 1
		var dc: int = dist[cur]
		if dc >= 3 and map.is_walkable_cell(cur):
			far.append(cur)
		if dc >= 4:
			continue
		for d in Hex.DIRS:
			var nb: Vector2i = cur + d
			if not dist.has(nb) and cell_space.get(nb, "") == hall:
				dist[nb] = dc + 1
				queue.append(nb)
	var raw := (_centroid(far) - mc) if not far.is_empty() else (mc - rc)
	raw.y = 0.0
	var axis := Vector3.FORWARD
	var best := -2.0
	var axis_i := 0
	for i in 6:
		var v := Hex.dir_vector(i)
		var dot := v.dot(raw.normalized()) if raw.length() > 0.0001 else -1.0
		if dot > best:
			best = dot
			axis = v
			axis_i = i
	dw["axis"] = axis
	dw["ok"] = false
	dw["door_ok"] = false
	dw["narrow"] = false
	dw["width"] = 0.0
	# The corridor's width where the flare has ended: the first level cross-section narrow enough, a narrow one first.
	var perp := Vector3(-axis.z, 0.0, axis.x)
	var first_wide := Vector3.INF
	var t := SPAN_FROM
	while t <= SPAN_TO + 0.001:
		var p := Vector3(mc.x, 0.0, mc.z) + axis * t
		t += SPAN_STEP
		if map.wall_at(p) or is_nan(map.ground_level(p)):
			continue
		var d1 := _march(map, p, perp)
		var d2 := _march(map, p, -perp)
		if d1 < 0.0 or d2 < 0.0 or d1 + d2 > SPAN_MAX or d1 + d2 < SPAN_MIN:
			continue
		if not _level_between(map, p + perp * d1, p - perp * d2):
			continue
		dw["ok"] = true
		if d1 + d2 <= NARROW_MAX:
			if not bool(dw["narrow"]):
				dw["width"] = d1 + d2
			dw["narrow"] = true
			_door_place(map, dw, sp, p, axis_i)   # (a cross-section in the taper may have no clean cell row: try on)
			if bool(dw["door_ok"]):
				dw["width"] = d1 + d2
				return
			continue
		if first_wide == Vector3.INF:
			first_wide = p
			dw["width"] = d1 + d2


## A narrow doorway's door place (see the header) near the cross-section point p.
static func _door_place(map: HexMap, dw: Dictionary, sp: Dictionary, p: Vector3, axis_i: int) -> void:
	var hall: String = dw["hall"]
	var cell_space: Dictionary = sp["cell_space"]
	var axis := Hex.dir_vector(axis_i)
	var perp := Vector3(-axis.z, 0.0, axis.x)
	# the doorway cell: the full hall cell nearest p (ties: cell order)
	var best := HexMap.NO_CELL
	var best_d := INF
	var around := Hex.range_cells(Hex.from_world(p), 2)
	around.sort_custom(_cell_less)
	for c in around:
		if cell_space.get(c, "") != hall or not map.is_walkable_cell(c):
			continue
		var d := GameWorld.flat_distance(Hex.to_world(c), p)
		if d < best_d - 0.001:
			best_d = d
			best = c
	if best == HexMap.NO_CELL:
		return
	var cell: HexMap.Cell = map.get_cell(best)
	if cell.type == HexMap.Tile.STAIRS:
		return
	if _square_place(map, dw, sp, best, axis_i):
		return
	var center := Hex.to_world(best, float(cell.level))
	var band: Array[Vector2i] = [best]
	for k in [axis_i + 2, axis_i + 4]:
		var side: Vector2i = best + Hex.DIRS[posmod(k, 6)]
		var sc: HexMap.Cell = map.get_cell(side)
		if sc == null or sc.type == HexMap.Tile.WALL or sc.type == HexMap.Tile.STAIRS or sc.level != cell.level:
			return
		band.append(side)
	var d1 := _march(map, center, perp)
	var d2 := _march(map, center, -perp)
	if d1 < 0.0 or d2 < 0.0 or not _level_between(map, center + perp * d1, center - perp * d2):
		return
	var edges := _band_edges(map, band, axis)
	dw["cell"] = best
	dw["band"] = band
	dw["edges"] = edges
	# The jambs: where the corridor's two wall faces end at the room (each a wall corner, so a hex centre). The door spans
	# the chord between them, in the room's wall line: flush with it where the room wall runs straight past the opening,
	# a straight chord across the corner where the opening sits at a bend (`flush` false).
	var jl := _jamb(map, center, perp, d1, axis)
	var jr := _jamb(map, center, -perp, d2, axis)
	if jl == Vector3.INF and jr == Vector3.INF:
		return
	# One corridor wall runs straight on as the room's wall: that jamb is the foot on it, square across from the other.
	if jl == Vector3.INF:
		jl = center - axis * (jr - center).dot(-axis) + perp * d1
	elif jr == Vector3.INF:
		jr = center - axis * (jl - center).dot(-axis) - perp * d2
	var chord := jr - jl
	if chord.length() > JAMB_SPAN_MAX or not _level_between(map, jl.lerp(jr, 0.04), jl.lerp(jr, 0.96)):
		return
	var dc := (jl + jr) * 0.5
	dc.y = map.ground_height(dc)
	dw["center"] = dc
	dw["a"] = Vector2(jl.x, jl.z)
	dw["b"] = Vector2(jr.x, jr.z)
	dw["flush"] = _flush(map, jl, jr, axis)
	dw["door_ok"] = not edges.is_empty()


## The SQUARE door place (user, 2026-10-21: "normal doors would be placed perpendicular to the hall, or at least prioritize
## the shortest span"): the door stands square across the corridor, on the line through the two cut cells of a lane
## cell's band (lane + DIRS[axis +/- 2]: their centres are on the corridor's two wall lines, 3.0 apart for a narrow hall,
## the corridor's width and so the shortest cut there is). The lane cells from SQUARE_BACK toward the room to SQUARE_ON
## into the hall from `near` are tried (full cells of the hall, or of the room where its tags reach into the corridor),
## the room's end first: the first whose line SEALS the opening (_seals: both ends
## run on into wall, level floor between) is the door place, so the door stands at the jamb that reaches furthest into
## the hall, square, and the other jamb is on that corridor wall (where the room wall meets the corridor square on, both
## are on the room's wall line). False (nothing written) when no lane cell has one: _door_place then falls back to the
## jambs' chord.
static func _square_place(map: HexMap, dw: Dictionary, sp: Dictionary, near: Vector2i, axis_i: int) -> bool:
	var hall: String = dw["hall"]
	var cell_space: Dictionary = sp["cell_space"]
	var axis := Hex.dir_vector(axis_i)
	for k in range(-SQUARE_BACK, SQUARE_ON + 1):
		var lane: Vector2i = near + Hex.DIRS[axis_i] * k
		var lane_space := str(cell_space.get(lane, ""))
		if (lane_space != hall and lane_space != str(dw["room"])) or not map.is_walkable_cell(lane):
			continue
		var cell: HexMap.Cell = map.get_cell(lane)
		if cell.type == HexMap.Tile.STAIRS:
			continue
		var band: Array[Vector2i] = [lane]
		for j in [axis_i + 2, axis_i + 4]:
			var side: Vector2i = lane + Hex.DIRS[posmod(j, 6)]
			var sc: HexMap.Cell = map.get_cell(side)
			if sc == null or sc.type == HexMap.Tile.WALL or sc.type == HexMap.Tile.STAIRS or sc.level != cell.level:
				break
			band.append(side)
		if band.size() < 3:
			continue
		var ja := Hex.to_world(band[1], float(cell.level))
		var jb := Hex.to_world(band[2], float(cell.level))
		if not _seals(map, ja, jb, cell.level):
			continue
		var edges := _band_edges(map, band, axis)
		if edges.is_empty():
			continue
		var dc := (ja + jb) * 0.5
		dc.y = map.ground_height(dc)
		dw["cell"] = lane
		dw["band"] = band
		dw["edges"] = edges
		dw["center"] = dc
		dw["a"] = Vector2(ja.x, ja.z)
		dw["b"] = Vector2(jb.x, jb.z)
		dw["flush"] = _flush(map, ja, jb, axis)
		dw["door_ok"] = true
		return true
	return false


## Does a door on p -> q close the opening: both ends run on into wall (SEAL_REACH past each), and the floor between is
## open (no wall) and one flat level `level` (no stairs)? Then nobody walks round it: a wall face meets each jamb.
static func _seals(map: HexMap, p: Vector3, q: Vector3, level: int) -> bool:
	var u := q - p
	u.y = 0.0
	u = u.normalized()
	if not map.wall_at(p - u * SEAL_REACH) or not map.wall_at(q + u * SEAL_REACH):
		return false
	for i in range(1, SEAL_SAMPLES):
		var m := p.lerp(q, float(i) / SEAL_SAMPLES)
		if map.wall_at(m):
			return false
		var c: HexMap.Cell = map.get_cell(Hex.from_world(m))
		if c == null or c.type == HexMap.Tile.STAIRS or absf(map.ground_level(m) - level) > 0.01:
			return false
	return true


## The hex edges between a door band and the room side (facing against `axis`), clipped to the floor.
static func _band_edges(map: HexMap, band: Array[Vector2i], axis: Vector3) -> Array:
	var inband := {}
	for c in band:
		inband[c] = true
	var edges: Array = []
	for c in band:
		var cc := Hex.to_world(c)
		for k in 6:
			if inband.has(c + Hex.DIRS[k]) or Hex.dir_vector(k).dot(axis) > -0.01:
				continue
			var dv := Hex.dir_vector(k)
			var m := cc + Hex.edge_mid(k)
			var along := Vector3(-dv.z, 0.0, dv.x) * (Hex.SIZE * 0.5)
			var seg := _clip_to_floor(map, m - along, m + along, cc)
			if not seg.is_empty():
				edges.append(seg)
	return edges


## Walk back from the doorway cell toward the room along one corridor wall (at `dist` along `side`) to where the wall
## face ends: the jamb, snapped to the wall corner (a hex centre). Vector3.INF when the wall runs on past JAMB_SEARCH.
static func _jamb(map: HexMap, center: Vector3, side: Vector3, dist: float, axis: Vector3) -> Vector3:
	var s := 0.0
	while s <= JAMB_SEARCH:
		var outside := center - axis * s + side * (dist + 0.1)
		if not map.wall_at(outside):
			var p := center - axis * maxf(0.0, s - MARCH * 0.5) + side * dist
			var hc := Hex.to_world(Hex.from_world(p))
			if Vector2(hc.x - p.x, hc.z - p.z).length() < 0.35:
				p = Vector3(hc.x, p.y, hc.z)
			return p
		s += MARCH
	return Vector3.INF


## Do the room's wall faces either side of the opening run along the chord (one straight wall), or turn (a bend)?
static func _flush(map: HexMap, jl: Vector3, jr: Vector3, axis: Vector3) -> bool:
	var t := Vector2(jr.x - jl.x, jr.z - jl.z).normalized()
	var found := 0
	for j: Vector3 in [jl, jr]:
		var segs := map.segments_near(j, 0.9)
		var i := 0
		while i < segs.size():
			var sa: Vector2 = segs[i]
			var sb: Vector2 = segs[i + 1]
			var n: Vector2 = segs[i + 2]
			i += 3
			var dir := (sb - sa).normalized()
			if n.dot(Vector2(-axis.x, -axis.z)) < 0.2:
				continue   # (a corridor face, or the back of something)
			if minf(sa.distance_to(Vector2(j.x, j.z)), sb.distance_to(Vector2(j.x, j.z))) > 0.05:
				continue
			if absf(dir.dot(t)) > 0.995:
				found += 1
	return found >= 2


## The part of the segment p -> q on the floor side (judged a touch toward `inside`): [Vector2, Vector2], or [] if none.
static func _clip_to_floor(map: HexMap, p: Vector3, q: Vector3, inside: Vector3) -> Array:
	var n := 24
	var lo := -1
	var hi := -1
	for i in n:
		var m := p.lerp(q, (i + 0.5) / n)
		m += (inside - m).normalized() * 0.03
		if not map.wall_at(m):
			if lo < 0:
				lo = i
			hi = i
	if lo < 0:
		return []
	var s := p.lerp(q, float(lo) / n)
	var e := p.lerp(q, float(hi + 1) / n)
	if s.distance_to(e) < 0.05:
		return []
	return [Vector2(s.x, s.z), Vector2(e.x, e.z)]

## Distance from p along dir to the first wall face (-1 when none within MARCH_MAX or the floor ends first).
## Strides of MARCH_COARSE steps first, then the fine MARCH steps in the stride that met a wall (or the whole way again
## when a stride met the floor's end). The same answer as stepping finely all the way unless a wall sliver thinner than a
## stride sits between floor on both sides (the doorway tests and 14k probes of generated floors found none); about a
## third of the probes.
static func _march(map: HexMap, p: Vector3, dir: Vector3) -> float:
	var k := 1
	var last := 0          # the steps a float march of MARCH up to MARCH_MAX takes (84: 85 * 0.04 rounds past 3.4)
	var acc := MARCH
	while acc <= MARCH_MAX:
		last += 1
		acc += MARCH
	while k <= last:
		var kc := mini(k + MARCH_COARSE - 1, last)
		var q := p + dir * (MARCH * kc)
		var hit := map.wall_at(q)
		if kc == last or hit or is_nan(map.ground_level(q)):
			# the floor ends here: a wall corner grazed on the way (thinner than a stride) would have been the answer, so
			# the whole march is redone fine; a wall: only this stride
			for kf in range(k if hit else 1, kc + 1):
				var qf := p + dir * (MARCH * kf)
				if map.wall_at(qf):
					# back off to the face (half a step: the face is within one step behind)
					return MARCH * kf - MARCH * 0.5
				if is_nan(map.ground_level(qf)):
					return -1.0
		k = kc + 1
	return -1.0


## The floor under a door span is one flat level (no stairs, no step).
static func _level_between(map: HexMap, a: Vector3, b: Vector3) -> bool:
	var lv := map.ground_level(a.lerp(b, 0.5))
	if is_nan(lv) or map.get_cell(Hex.from_world(a.lerp(b, 0.5))).type == HexMap.Tile.STAIRS:
		return false
	for i in range(1, 8):
		var q := a.lerp(b, float(i) / 8.0)
		var l := map.ground_level(q)
		if is_nan(l) or absf(l - lv) > 0.01:
			return false
		var cell := map.get_cell(Hex.from_world(q))
		if cell != null and cell.type == HexMap.Tile.STAIRS:
			return false
	return true


static func _centroid(cells: Array[Vector2i]) -> Vector3:
	var s := Vector3.ZERO
	for c in cells:
		s += Hex.to_world(c)
	return s / maxf(1.0, float(cells.size()))


static func _cell_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


## Rooms by number, then halls by number.
static func _tag_less(a: String, b: String) -> bool:
	var ha := a.begins_with(HALL_PREFIX)
	var hb := b.begins_with(HALL_PREFIX)
	if ha != hb:
		return hb
	return int(a.get_slice(":", 1)) < int(b.get_slice(":", 1))
