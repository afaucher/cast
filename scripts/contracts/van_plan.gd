class_name VanPlan
extends RefCounted
## Where the crew's work van parks on a floor: pure data (SitePlan.van), deterministic per map, no nodes.
## SiteBuilder.plan() calls plan() right after the room themes are dealt, registers the result as a body in the
## start room (so no decor, package or note lands on it) and blocks its cells.
##
## The van is 2.0 wide x 4.2 long (VanModel). Its model faces +Z (the nose), the sliding side door is on the
## model's -X side, and the pose is (pos, yaw) in the same convention as the decor: yaw in degrees about +Y, the
## nose faces (sin yaw, cos yaw), the door faces away from lateral(yaw) = (cos yaw, -sin yaw).
##
## Placement rules:
##  - the van parks in the start room at most MAX_FROM_START cells from the start cell, its sliding door facing a
##    clear strip of floor where the crew steps out (Wick opposite the door, Gasket toward the cab, Rebar toward the
##    tail);
##  - the whole footprint (body + a PAD of clearance) is flat FULL floor (never a cell cut by a midpoint wall) of the start room's base level (strictly flat
##    cells first, lenient ones if the room has nothing better), at least CORRIDOR_MIN cells from any corridor cell
##    (a doorway is never boxed in), and the crew spots are flat and clear of the body too;
##  - parking the van may not cut any walkable cell off from the start (a BFS with the van's cells removed must still
##    reach everything it reached before);
##  - among the poses that pass, the door faces the iso camera (the player sees the open door and the crew), the nose
##    points toward the elevator, and the van keeps away from the corridors.
##
## The dictionary: {pos: Vector2, yaw: float, w, d, cells: Array[Vector2i] (blocked by the blocker circles),
##   block_points: Array[Vector2], block_radius: float, door: Vector2 (the floor in front of the door), door_normal:
##   Vector2 (unit, pointing out of the door), crew: Array[Vector2] (Wick, Gasket, Rebar standing spots), crew_cells,
##   circle_radius: float, room: String, level: int (the floor level the van stands on)}.

const W := 2.0
const L := 4.2
const H := 2.2
const PAD := Vector2(0.4, 0.55)         ## clearance kept flat around the body (sideways, lengthways)
const CIRCLE_RADIUS := 2.9              ## the summoning circle drawn under the van
const DOOR_Z := 0.4                     ## the centre of the sliding door along the van (model +Z is the nose)
const STEP_OUTS: Array[float] = [2.55, 2.85]   ## how far from the van's axis Wick stands
const CREW_Z: Array[float] = [0.1, 1.5, -1.3]   ## the crew's spots along the van's side relative to the door
const CREW_OUT: Array[float] = [0.0, 0.1, 0.3]   ## ... and how much farther from the van each stands
const YAW_STEP := 20.0
const CORRIDOR_MIN := 2                 ## hex cells between the body and the nearest corridor cell
## [margin scale, corridor distance] tried in order: full clearance first, then a small room squeezes the van in
const TIGHTNESS := [[1.0, 2], [0.4, 2], [0.0, 1]]
const BLOCK_Z: Array[float] = [-1.2, -0.4, 0.4, 1.2]   ## blocker circle centres along the van's axis
const BLOCK_R := 0.98
const REACH_LIMIT := 12                 ## the connectivity check looks this many cells around the start
const WANTED := 3                       ## fitting poses collected before the best is picked
const SAMPLE := 0.5                     ## footprint sampling step
const MAX_FROM_START := 5               ## the van's centre is at most this many cells from the start cell


## Plan the van for the floor described by `p` (rooms indexed, start known). `door_d` is the hex distance to the
## nearest corridor cell (SiteBuilder._corridor_distance). Returns {} when the start room has nowhere to park it.
static func plan(map: HexMap, p: SitePlan, door_d: Dictionary) -> Dictionary:
	if p.start_room == "" or not p.base_levels.has(p.start_room):
		return {}
	var base: int = int(p.base_levels[p.start_room])
	var start_w := ThemeGeo.world(p.start)
	var exit_dir := (ThemeGeo.world(p.exit) - start_w)
	exit_dir = exit_dir.normalized() if exit_dir.length() > 0.5 else Vector2.ZERO
	var baseline := _reach(map, p.start, {})
	var steps := int(round(360.0 / YAW_STEP))
	# strictly flat ground and full clearance first; then lenient ground; then less clearance
	for tight in TIGHTNESS:
		var pad := PAD * float(tight[0])
		var corr_min: int = int(tight[1])
		for strict in [true, false]:
			var flat := _flat_cells(map, p, base, strict)
			# the poses whose door faces the camera first (they win anyway); every yaw only if none of those fits
			for tier in 2:
				var cands := _candidates(map, p, base, baseline, flat, door_d, pad, corr_min, start_w, exit_dir, steps, tier == 0)
				if not cands.is_empty():
					return cands[0]
	return {}


## The best poses that fit and keep the floor connected, best first. Poses are tried in order of a cheap pre-score (door toward the camera, nose
## toward the elevator, near the start) and the search stops after WANTED fits, so a floor costs a few dozen footprint
## checks, not hundreds. `facing_only`: only yaws whose door faces within 60 degrees of the camera.
static func _candidates(map: HexMap, p: SitePlan, base: int, baseline: Dictionary, flat: Dictionary, door_d: Dictionary, pad: Vector2, corr_min: int, start_w: Vector2, exit_dir: Vector2, steps: int, facing_only: bool) -> Array[Dictionary]:
	var order: Array[Dictionary] = []
	for c: Vector2i in flat:
		if Hex.distance(c, p.start) > MAX_FROM_START:
			continue
		var pos := ThemeGeo.world(c)
		for step in steps:
			var yaw := YAW_STEP * float(step)
			var cam := (-ThemeGeo.lateral(yaw)).dot(ThemeGeo.CAMERA_DIR)
			if facing_only and cam < 0.5:
				continue
			order.append({"pos": pos, "yaw": yaw, "score": 3.0 * cam + ThemeGeo.facing(yaw).dot(exit_dir) - 0.35 * pos.distance_to(start_w)})
	order.sort_custom(_better)
	var cands: Array[Dictionary] = []
	for cd in order:
		var pos: Vector2 = cd["pos"]
		var yaw: float = cd["yaw"]
		var fit := _footprint_ok(pos, yaw, flat, door_d, pad, corr_min)
		if fit < 0.0:
			continue
		for out in STEP_OUTS:
			var spots := _crew_spots(pos, yaw, out)
			if not _spots_ok(spots, pos, yaw, flat, door_d, corr_min):
				continue
			var dict := _make(pos, yaw, spots, p, base)
			if (dict["cells"] as Array).has(p.start) or not _keeps_connected(map, p.start, baseline, dict["cells"]):
				break
			dict["score"] = float(cd["score"]) + 0.4 * minf(fit, 4.0) - 0.5 * (out - STEP_OUTS[0])
			cands.append(dict)
			break
		if cands.size() >= WANTED:
			break
	cands.sort_custom(_better)
	return cands


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if absf(float(a["score"]) - float(b["score"])) > 0.0001:
		return float(a["score"]) > float(b["score"])
	var pa: Vector2 = a["pos"]
	var pb: Vector2 = b["pos"]
	if pa != pb:
		return pa.x < pb.x or (pa.x == pb.x and pa.y < pb.y)
	return float(a["yaw"]) < float(b["yaw"])


## The standing spots (world X/Z) of Wick, Gasket and Rebar beside the door: `out` is Wick's distance from the axis.
static func _crew_spots(pos: Vector2, yaw: float, out: float) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	for i in CREW_Z.size():
		spots.append(ThemeGeo.local_to_world(pos, yaw, -(out + CREW_OUT[i]), DOOR_Z + CREW_Z[i]))
	return spots


static func _make(pos: Vector2, yaw: float, spots: Array[Vector2], p: SitePlan, base: int) -> Dictionary:
	var points: Array[Vector2] = []
	for z in BLOCK_Z:
		points.append(ThemeGeo.local_to_world(pos, yaw, 0.0, z))
	var cells: Array[Vector2i] = []
	for bp in points:
		for c in Hex.range_cells(ThemeGeo.cell_of(bp), 2):
			if ThemeGeo.hex_dist(bp, c) < BLOCK_R + 0.1 and not cells.has(c):
				cells.append(c)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	var crew_cells: Array[Vector2i] = []
	for s in spots:
		crew_cells.append(ThemeGeo.cell_of(s))
	var n := -ThemeGeo.lateral(yaw)
	return {
		"pos": pos, "yaw": yaw, "w": W, "d": L, "cells": cells, "block_points": points, "block_radius": BLOCK_R,
		"door": ThemeGeo.local_to_world(pos, yaw, -(W * 0.5), DOOR_Z), "door_normal": n,
		"crew": spots, "crew_cells": crew_cells, "circle_radius": CIRCLE_RADIUS, "room": p.start_room, "level": base,
	}


## Flat floor cells around the start that the van may stand on: floor of the start room (or the start cell) at the
## room's base level. `strict` also wants every neighbour at the same level (or a wall), so no step touches the body.
static func _flat_cells(map: HexMap, p: SitePlan, base: int, strict: bool) -> Dictionary:
	var out := {}
	for c in Hex.range_cells(p.start, 10):
		var cell: HexMap.Cell = map.get_cell(c)
		if cell == null or cell.type != HexMap.Tile.FLOOR or cell.level != base or not map.is_walkable_cell(c):
			continue   # (full cells only: a wall-cut cell is half wall, so the van and the crew stay off it)
		if not (cell.tag == "start" or cell.tag == p.start_room):
			continue
		var ok := true
		for d in Hex.DIRS:
			var nb: HexMap.Cell = map.get_cell(c + d)
			if nb == null:
				ok = false     # a pit edge
				break
			if nb.type == HexMap.Tile.WALL:
				continue
			if nb.type == HexMap.Tile.STAIRS or absi(nb.level - base) > (0 if strict else 1):
				ok = false
				break
		if ok:
			out[c] = true
	return out


## Is the padded footprint on flat floor, clear of the corridors? Returns the smallest corridor distance (a clearance
## measure, capped by the caller) or -1 when it does not fit.
static func _footprint_ok(pos: Vector2, yaw: float, flat: Dictionary, door_d: Dictionary, pad: Vector2 = PAD, corr_min: int = CORRIDOR_MIN) -> float:
	var w := W + pad.x * 2.0
	var d := L + pad.y * 2.0
	var nx := int(ceilf(w / SAMPLE))
	var nz := int(ceilf(d / SAMPLE))
	var clear := 99.0
	for i in nx + 1:
		var lx := lerpf(-w * 0.5, w * 0.5, float(i) / float(nx))
		for j in nz + 1:
			var lz := lerpf(-d * 0.5, d * 0.5, float(j) / float(nz))
			var c := ThemeGeo.cell_of(ThemeGeo.local_to_world(pos, yaw, lx, lz))
			if not flat.has(c):
				return -1.0
			var dd := float(door_d.get(c, 99))
			if dd < corr_min:
				return -1.0
			clear = minf(clear, dd)
	return clear


## The crew spots stand on flat floor (with a hero's width of margin), outside the body and the corridor zone.
static func _spots_ok(spots: Array[Vector2], pos: Vector2, yaw: float, flat: Dictionary, door_d: Dictionary, corr_min: int = CORRIDOR_MIN) -> bool:
	for s in spots:
		for off in [Vector2.ZERO, Vector2(0.45, 0), Vector2(-0.45, 0), Vector2(0, 0.45), Vector2(0, -0.45)]:
			var c := ThemeGeo.cell_of(s + off)
			if not flat.has(c) or int(door_d.get(c, 99)) < corr_min:
				return false
		# outside the body: more than half the width plus a hero's radius from the axis
		var lx := absf((s - pos).dot(ThemeGeo.lateral(yaw)))
		if lx < W * 0.5 + 0.55:
			return false
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			if spots[i].distance_to(spots[j]) < 1.1:
				return false
	return true


## Walkable cells within `limit` of `start` reachable on foot (floor to floor, climbs excluded), skipping `blocked`.
static func _reach(map: HexMap, start: Vector2i, blocked: Dictionary, limit: int = REACH_LIMIT) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		for d in Hex.DIRS:
			var nb: Vector2i = c + d
			if seen.has(nb) or blocked.has(nb) or Hex.distance(nb, start) > limit or not map.is_walkable_cell(nb):
				continue
			if map.cell_transition(c, nb) != HexMap.Move.OK:
				continue
			seen[nb] = true
			queue.append(nb)
	return seen


## True when removing the van's cells strands nothing: every cell reachable before (and not itself a van cell) is
## still reachable from the start.
static func _keeps_connected(map: HexMap, start: Vector2i, baseline: Dictionary, cells: Array) -> bool:
	var blocked := {}
	for c: Vector2i in cells:
		blocked[c] = true
	var after := _reach(map, start, blocked)
	for c: Vector2i in baseline:
		if not blocked.has(c) and not after.has(c):
			return false
	return true


## Does an oriented rectangle (a note, a box) at `pos` come within `margin` of the van body?
static func near(van: Dictionary, pos: Vector2, w: float, d: float, margin: float) -> bool:
	if van.is_empty():
		return false
	return ThemeGeo.overlap(pos, 0.0, w, d, van["pos"], float(van["yaw"]), float(van["w"]), float(van["d"]), -margin)
