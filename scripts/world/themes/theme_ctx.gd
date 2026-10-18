class_name ThemeCtx
extends RefCounted
## The per-floor state of the room-theme planner: for each room the cells a prop may stand on, the door
## the crew comes in by, every body already placed (gates, employees, notes, priced props, decor) and the
## cells that blocking props made solid. It answers "does this prop fit here?" and builds wall-backed /
## corner poses, so a prop can never end up facing a wall, on a door, or boxing a corridor in.
##
## Walls are HexMap's midpoint walls: the anchor cells next to a wall are cut cells (half floor, half wall), every
## footprint point must be off the wall side (HexMap.wall_at) and a wall-backed piece marches to the flat face, so it
## stands flush against it. Walkability (the room's reach, connected_ok) uses full cells only.
##
## Pure data and queries (no nodes): the plan is deterministic and testable without a running game.

const GATE_CLEAR := 3            ## no decor within this many cells of a hellgate (4 for the origin gate)
const ORIGIN_GATE_CLEAR := 4
const TOL := 0.1                 ## how far two props may interpenetrate
const GROUP_TOL := 0.35          ## ... members of one vignette (a chair tucked under its table)
const LANE_AHEAD := 0.95         ## the clear lane in front of a facing prop starts this far past its front
const CENTER_CLEAR := 3.0        ## blocking decor stays this far from a room's centre (the fighting area)
const CELLS_PER_DECOR := 11.0    ## decor budget: one weight point per this many room cells ...
const MIN_BUDGET := 5.0
const MAX_BUDGET := 14.0
const CELLS_PER_BLOCKER := 22    ## ... and one blocking piece per this many
const MAX_BLOCKERS := 8
const MIN_ALIGN := 0.3           ## a wall-backed piece must face within ~72 degrees of the nearest wall face's normal
const BACK_OFF := 0.75           ## a wall pose marches toward the wall from this far inside the anchor (a cut cell's center lies ON the wall line)
const MARCH := 2.2               ## ... and looks this far for the face


class Body:
	extends RefCounted
	var pos := Vector2.ZERO
	var yaw := 0.0
	var w := 0.0
	var d := 0.0
	var group := -1
	var kind := ""
	var lane := false


class RoomInfo:
	extends RefCounted
	var tag := ""
	var index := 0
	var theme := ""
	var cells: Array[Vector2i] = []
	var open: Dictionary = {}          ## Vector2i -> true: flat floor at the room's base level
	var base := 0
	var center := Vector2i.ZERO
	var center_w := Vector2.ZERO
	var entrance := Vector2i.ZERO      ## the room cell by the main door (nearest the start; for the start room, nearest the exit)
	var entrance_w := Vector2.ZERO
	var walk: Dictionary = {}          ## room cells reachable on foot from the entrance
	var budget := 0.0
	var used := 0.0
	var block_budget := 0
	var blockers := 0.0
	var bodies: Array[Body] = []
	var items: Array[Dictionary] = []
	var solid_log: Array[Vector2i] = []
	var gate: Dictionary = {}          ## the plan's gate in this room, if any


var map: HexMap
var plan: SitePlan
var avoid: Dictionary = {}             ## cells near the start / exit
var near_corr: Dictionary = {}         ## cells near a corridor (the doors)
var gate_zone: Dictionary = {}
var solid: Dictionary = {}             ## cells a blocking prop made impassable
var rooms: Dictionary = {}             ## tag -> RoomInfo
var rng := RandomNumberGenerator.new()
var allow_gate := false                ## true while a vignette is built around a hellgate
var _group := 0
var _walls: Dictionary = {}
var _reach_cache: Dictionary = {}
var _faces: Dictionary = {}            ## Vector2i -> the wall faces near that cell (HexMap.segments_near)


static func make(map_: HexMap, plan_: SitePlan, avoid_: Dictionary, near_corr_: Dictionary, seed_value: int) -> ThemeCtx:
	var ctx := ThemeCtx.new()
	ctx.map = map_
	ctx.plan = plan_
	ctx.avoid = avoid_
	ctx.near_corr = near_corr_
	ctx.rng.seed = seed_value
	for g in plan_.gates:
		var r := ORIGIN_GATE_CLEAR if bool(g["origin"]) else GATE_CLEAR
		for c in Hex.range_cells(g["cell"], r):
			ctx.gate_zone[c] = true
	var tags: Array = plan_.rooms.keys()
	tags.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("room:")) < int(b.trim_prefix("room:")))
	for tag: String in tags:
		ctx.rooms[tag] = ctx._room_info(tag)
	for g in plan_.gates:
		var gr := ctx.room_of(g["cell"])
		if gr != null:
			gr.gate = g
			var rad := 2.9 if bool(g["origin"]) else 1.5
			ctx.add_body(gr, ThemeGeo.world(g["cell"]), 0.0, rad * 2.0, rad * 2.0, -1, "gate")
	for e in plan_.employees:
		var er := ctx.room_of(e["cell"])
		if er != null:
			# (1.45 across: even a candle keeps 0.7 from where the employee stands)
			ctx.add_body(er, ThemeGeo.world(e["cell"]), 0.0, 1.45, 1.45, -1, "employee")
	return ctx


func _room_info(tag: String) -> RoomInfo:
	var r := RoomInfo.new()
	r.tag = tag
	r.index = int(tag.trim_prefix("room:"))
	r.cells = plan.rooms[tag]
	r.base = int(plan.base_levels[tag])
	r.center = plan.centers[tag]
	r.center_w = ThemeGeo.world(r.center)
	for c in r.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type != HexMap.Tile.FLOOR or cell.level != r.base:
			continue
		var flat := true
		for d in Hex.DIRS:
			var nb: HexMap.Cell = map.get_cell(c + d)
			if nb == null:
				flat = false       # a pit edge: leave it alone
				break
			if nb.type == HexMap.Tile.STAIRS or (nb.type != HexMap.Tile.WALL and absi(nb.level - r.base) > 1):
				flat = false
				break
		if flat:
			r.open[c] = true
	# The main door: a room cell touching a corridor, nearest the start (the start room: nearest the exit).
	var target: Vector2i = plan.exit if tag == plan.start_room else plan.start
	var best := r.center
	var best_d := 1 << 20
	for c in r.cells:
		var touches := false
		for d in Hex.DIRS:
			var nb: HexMap.Cell = map.get_cell(c + d)
			if nb != null and nb.tag == "corridor":
				touches = true
				break
		if not touches or not map.is_walkable_cell(c):
			continue
		var dist := Hex.distance(c, target)
		if dist < best_d or (dist == best_d and (c.x < best.x or (c.x == best.x and c.y < best.y))):
			best_d = dist
			best = c
	r.entrance = best
	r.entrance_w = ThemeGeo.world(best)
	# Baseline reachability inside the room (floor to floor within one level).
	var seen := {best: true}
	var queue: Array[Vector2i] = [best]
	var qi := 0
	var room_set := {}
	for c in r.cells:
		room_set[c] = true
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		for d in Hex.DIRS:
			var nb: Vector2i = c + d
			if seen.has(nb) or not room_set.has(nb) or not _steppable(c, nb):
				continue
			seen[nb] = true
			queue.append(nb)
	r.walk = seen
	var n_cells := float(r.cells.size())
	r.budget = clampf(floorf(n_cells / CELLS_PER_DECOR), MIN_BUDGET, MAX_BUDGET)
	r.block_budget = clampi(int(n_cells) / CELLS_PER_BLOCKER, 2, MAX_BLOCKERS)
	return r


func _steppable(a: Vector2i, b: Vector2i) -> bool:
	var ca: HexMap.Cell = map.cells.get(a)
	var cb: HexMap.Cell = map.cells.get(b)
	if ca == null or cb == null or ca.type != HexMap.Tile.FLOOR or cb.type != HexMap.Tile.FLOOR:
		return false
	if not map.is_walkable_cell(a) or not map.is_walkable_cell(b):
		return false   # a wall-cut cell is not a step on a route (its center is on the wall line)
	return absi(ca.level - cb.level) <= 1


func room_of(c: Vector2i) -> RoomInfo:
	var cell: HexMap.Cell = map.get_cell(c)
	if cell == null:
		return null
	return rooms.get(cell.tag)


func new_group() -> int:
	_group += 1
	return _group


# --- Cells ----------------------------------------------------------------------------------------------------

## May something stand in cell c of this room? (Solid cells are NOT excluded: pieces of one vignette share
## cells; physical overlap is the bodies' job, walkability is connected_ok()'s.)
func cell_free(room: RoomInfo, c: Vector2i) -> bool:
	return room.open.has(c) and not avoid.has(c) and not near_corr.has(c) and (allow_gate or not gate_zone.has(c))


func wall_dirs(c: Vector2i) -> Array[int]:
	if _walls.has(c):
		return _walls[c]
	var out: Array[int] = []
	for d in 6:
		var nb: HexMap.Cell = map.get_cell(c + Hex.DIRS[d])
		if nb != null and nb.type == HexMap.Tile.WALL:
			out.append(d)
	_walls[c] = out
	return out


## Unit vector from cell c toward its wall(s), or ZERO (no wall, or walls on opposite sides).
func wall_normal(c: Vector2i) -> Vector2:
	var dirs := wall_dirs(c)
	if dirs.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	var nrm := ThemeGeo.normals()
	for d in dirs:
		sum += nrm[d]
	if sum.length() < 0.4:
		return Vector2.ZERO
	return sum.normalized()


## Unit vector from cell c toward the flat wall FACE a wall-backed piece at c stands against (midpoint walls: the
## face through c's center; at a corner cell the first of its two faces), or wall_normal(c) on a plain hex map.
func face_normal(c: Vector2i) -> Vector2:
	var avg := wall_normal(c)
	if not map.midpoint_walls or avg == Vector2.ZERO:
		return avg
	var segs := map.wall_segments(c)
	var best := avg
	var best_dot := -INF
	var i := 0
	while i < segs.size():
		var toward := -segs[i + 2]
		var dt := toward.dot(avg)
		if dt > best_dot + 0.0001:
			best_dot = dt
			best = toward
		i += 3
	return best.normalized()


## Distance along unit vector n from p0 (inside the room's open floor) to the wall face; -1 when the open
## floor ends against something that is not a wall, -2 when p0 itself is not open floor. Exact: the first wall
## face the ray crosses (HexMap's faces), then the room's open floor is checked up to it.
func wall_hit(room: RoomInfo, p0: Vector2, n: Vector2) -> float:
	var c0 := ThemeGeo.cell_of(p0)
	if not room.open.has(c0) or _wall(p0):
		return -2.0
	var segs := _faces_near(c0)
	var t_wall := INF
	var i := 0
	while i < segs.size():
		var a := segs[i]
		var e := segs[i + 1] - a
		var den := n.x * e.y - n.y * e.x
		if absf(den) > 0.000001:
			var ao := a - p0
			var t := (ao.x * e.y - ao.y * e.x) / den
			var u := (ao.x * n.y - ao.y * n.x) / den
			if t >= 0.0 and t < t_wall and u >= -0.000001 and u <= 1.000001:
				t_wall = t
		i += 3
	if t_wall > MARCH:
		return -1.0
	var tt := 0.15
	while tt < t_wall - 0.005:
		if not room.open.has(ThemeGeo.cell_of(p0 + n * tt)):
			return -1.0
		tt += 0.15
	return t_wall


## The wall faces within reach of a march from cell c (cached: the map does not change while planning).
func _faces_near(c: Vector2i) -> PackedVector2Array:
	if _faces.has(c):
		return _faces[c]
	var segs := map.segments_near(Hex.to_world(c), MARCH)
	_faces[c] = segs
	return segs


## Does no wall face cross the w x d footprint at (pos, yaw)? (The sample points of foot_points() can straddle
## the tip of a wall that pokes between them.)
func rect_clear(pos: Vector2, yaw: float, w: float, d: float) -> bool:
	var lat := ThemeGeo.lateral(yaw)
	var fac := ThemeGeo.facing(yaw)
	var hw := w * 0.5 - 0.02
	var hd := d * 0.5 - 0.02
	var segs := _faces_near(ThemeGeo.cell_of(pos))
	var reach := Vector2(w, d).length() * 0.5 + 0.05
	var i := 0
	while i < segs.size():
		var a := segs[i] - pos
		var b := segs[i + 1] - pos
		if minf(a.length(), b.length()) < reach + Hex.INNER:
			if _seg_hits_box(Vector2(a.dot(lat), a.dot(fac)), Vector2(b.dot(lat), b.dot(fac)), hw, hd):
				return false
		i += 3
	return true


## Liang-Barsky: does segment a -> b touch the box |x| <= hx, |y| <= hy?
static func _seg_hits_box(a: Vector2, b: Vector2, hx: float, hy: float) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var dv := b - a
	for k in 4:
		var pk: float = [-dv.x, dv.x, -dv.y, dv.y][k]
		var qk: float = [a.x + hx, hx - a.x, a.y + hy, hy - a.y][k]
		if absf(pk) < 0.0000001:
			if qk < 0.0:
				return false
			continue
		var r := qk / pk
		if pk < 0.0:
			t0 = maxf(t0, r)
		else:
			t1 = minf(t1, r)
		if t0 > t1:
			return false
	return true


## Is world X/Z point p on the wall side (a WALL cell or the wall part of a cut cell)?
func _wall(p: Vector2) -> bool:
	return map.wall_at(Vector3(p.x, 0.0, p.y))


## The nearest wall face along n over a line of width `span` through p0 (perpendicular to n): a wide prop
## has to stand off the sawtooth of a hex wall by its worst tooth. -1 when no sample reaches a wall.
func wall_reach(room: RoomInfo, p0: Vector2, n: Vector2, span: float) -> float:
	var key := Vector4i(roundi(p0.x * 100.0), roundi(p0.y * 100.0), roundi(span * 100.0), roundi(n.angle() * 100.0))
	if _reach_cache.has(key):
		return _reach_cache[key]
	var r := _wall_reach(room, p0, n, span)
	_reach_cache[key] = r
	return r


func _wall_reach(room: RoomInfo, p0: Vector2, n: Vector2, span: float) -> float:
	var lat := Vector2(-n.y, n.x)
	var half := span * 0.5
	var steps := maxi(2, int(ceilf(span / 0.4)))
	var best := INF
	for i in steps + 1:
		var t := wall_hit(room, p0 + lat * lerpf(-half, half, float(i) / float(steps)), n)
		if t >= 0.0:
			best = minf(best, t)
	return best if best < INF else -1.0


## Free distance (to the first non-open cell) ahead of p along unit vector f, up to `limit`.
func free_run(room: RoomInfo, p: Vector2, f: Vector2, limit: float) -> float:
	var t := 0.25
	while t <= limit:
		if not room.open.has(ThemeGeo.cell_of(p + f * t)):
			return t - 0.25
		t += 0.25
	return limit


## A wall-backed pose: the prop's back `GAP` from the wall face along normal n (toward the wall), facing
## away from it, plus `jit` degrees of yaw. The march toward the wall starts BACK_OFF behind p0 (an anchor
## cell's center lies on the wall line itself), so the prop ends flush against the flat face.
func wall_pose_at(room: RoomInfo, p0: Vector2, n: Vector2, w: float, d: float, jit: float) -> Dictionary:
	p0 -= n * BACK_OFF
	if not room.open.has(ThemeGeo.cell_of(p0)):
		return {}
	var t := wall_reach(room, p0, n, w)
	if t < 0.0:
		return {}
	if map.midpoint_walls:
		# flush or nothing: the face straight behind must be square to n and nothing nearer across the width
		var tc := wall_hit(room, p0, n)
		if tc < 0.0 or t < tc - 0.05:
			return {}
		var q := p0 + n * tc
		var hit := map.nearest_wall(Vector3(q.x, 0.0, q.y), 0.1)
		if hit.is_empty() or (hit["normal"] as Vector2).dot(-n) < 0.98:
			return {}
	var gap := ThemeGeo.GAP + absf(sin(deg_to_rad(jit))) * w * 0.5
	var pos := p0 + n * (t - d * 0.5 - gap)
	return {"pos": pos, "yaw": ThemeGeo.yaw_of(-n) + jit, "cell": ThemeGeo.cell_of(pos), "normal": n}


func wall_pose(room: RoomInfo, c: Vector2i, w: float, d: float, jit: float) -> Dictionary:
	var n := face_normal(c)
	if n == Vector2.ZERO:
		return {}
	return wall_pose_at(room, ThemeGeo.world(c), n, w, d, jit)


## A corner pose: tucked into a concave corner (two walls), facing the room's centre.
func corner_pose(room: RoomInfo, c: Vector2i, w: float, d: float, jit: float) -> Dictionary:
	if wall_dirs(c).size() < 2:
		return {}
	var n := wall_normal(c)
	if n == Vector2.ZERO or not room.open.has(c):
		return {}
	var p0 := ThemeGeo.world(c) - n * BACK_OFF            # off the corner point (a cut cell's center is the wall corner)
	var reach := Vector2(w, d).length() * 0.5 + 0.03     # the half-diagonal: a corner piece may face any way
	var t := wall_reach(room, p0, n, reach * 2.0)
	if t < 0.0:
		return {}
	var pos := p0 + n * (t - reach - 0.04)
	var to_center := room.center_w - pos
	var f := to_center.normalized() if to_center.length() > 0.5 else -n
	return {"pos": pos, "yaw": ThemeGeo.yaw_of(f) + jit, "cell": ThemeGeo.cell_of(pos), "normal": n}


## cos of the angle between a facing yaw and the normal of the wall face nearest to `pos` (1 = square to the
## wall, < 0 = facing the wall). Midpoint walls are flat, so a piece squared to its wall is square to the face.
func wall_alignment(pos: Vector2, yaw: float) -> float:
	var f := ThemeGeo.facing(yaw)
	var segs := _faces_near(ThemeGeo.cell_of(pos))
	var best := 2.0
	var nrm := Vector2.ZERO
	var i := 0
	while i < segs.size():
		var cp := HexMap._closest(pos, segs[i], segs[i + 1])
		var dd := pos.distance_to(cp)
		if dd < best:
			best = dd
			var on_seg := cp.distance_squared_to(segs[i]) > 0.0001 and cp.distance_squared_to(segs[i + 1]) > 0.0001
			nrm = segs[i + 2] if on_seg or dd < 0.0001 else (pos - cp) / dd
		i += 3
	return f.dot(nrm) if nrm != Vector2.ZERO else -1.0


# --- Fitting and committing ----------------------------------------------------------------------------------

## Does a w x d footprint at (pos, yaw) fit: on free floor, clear of every other body and of the
## lanes kept open in front of facing props?
func fits(room: RoomInfo, pos: Vector2, yaw: float, w: float, d: float, group: int = -1, ignore: Array = []) -> bool:
	for p in ThemeGeo.foot_points(pos, yaw, w, d):
		if not cell_free(room, ThemeGeo.cell_of(p)) or _wall(p):
			return false
	if not rect_clear(pos, yaw, w, d):
		return false
	for b in room.bodies:
		if ignore.has(b.kind) or (b.lane and ignore.has("lane")):
			continue
		var same := group >= 0 and b.group == group
		if b.lane and same:
			continue
		var tol := GROUP_TOL if same else TOL
		if b.lane:
			tol = 0.0
		if ThemeGeo.overlap(pos, yaw, w, d, b.pos, b.yaw, b.w, b.d, tol):
			return false
	return true


## The clear lane in front of a prop (centre, size) must be walkable floor and not hold anything.
func lane_ok(room: RoomInfo, pos: Vector2, yaw: float, d: float, group: int = -1) -> bool:
	var lc := pos + ThemeGeo.facing(yaw) * (d * 0.5 + LANE_AHEAD)
	var cc := ThemeGeo.cell_of(lc)
	if not room.open.has(cc) or solid.has(cc) or _wall(lc):
		return false
	for b in room.bodies:
		if b.lane or (group >= 0 and b.group == group):
			continue
		if ThemeGeo.overlap(lc, yaw, 0.9, 0.9, b.pos, b.yaw, b.w, b.d, 0.05):
			return false
	return true


func add_body(room: RoomInfo, pos: Vector2, yaw: float, w: float, d: float, group: int, kind: String, lane: bool = false) -> void:
	var b := Body.new()
	b.pos = pos
	b.yaw = yaw
	b.w = w
	b.d = d
	b.group = group
	b.kind = kind
	b.lane = lane
	room.bodies.append(b)


## Cells a blocking piece makes solid: those its blocker circles reach.
func _solid_cells(points: Array[Vector2], radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p in points:
		for c in Hex.range_cells(ThemeGeo.cell_of(p), 1):
			if ThemeGeo.hex_dist(p, c) < radius + 0.1 and not out.has(c):
				out.append(c)
	return out


## The centres and radius of the blocker circles that stand in for a w x d piece.
static func blocker_circles(pos: Vector2, yaw: float, w: float, d: float) -> Dictionary:
	var r := clampf(minf(w, d) * 0.5 * 0.92, 0.34, 0.62)
	var pts: Array[Vector2] = []
	var n := maxi(1, roundi(w / 1.05))
	if n == 1:
		pts.append(pos)
	else:
		var half := maxf(0.0, w * 0.5 - r)
		for i in n:
			pts.append(ThemeGeo.local_to_world(pos, yaw, lerpf(-half, half, float(i) / float(n - 1)), 0.0))
	return {"points": pts, "radius": r}


func mark(room: RoomInfo) -> Array:
	return [room.items.size(), room.bodies.size(), room.used, room.blockers, room.solid_log.size()]


func rollback(room: RoomInfo, m: Array) -> void:
	room.items.resize(int(m[0]))
	room.bodies.resize(int(m[1]))
	room.used = float(m[2])
	room.blockers = float(m[3])
	while room.solid_log.size() > int(m[4]):
		solid.erase(room.solid_log.pop_back())


func connected_ok(room: RoomInfo) -> bool:
	if solid.has(room.entrance) or not room.walk.has(room.entrance):
		return true
	var seen := {room.entrance: true}
	var queue: Array[Vector2i] = [room.entrance]
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		for d in Hex.DIRS:
			var nb: Vector2i = c + d
			if seen.has(nb) or not room.walk.has(nb) or solid.has(nb) or not _steppable(c, nb):
				continue
			seen[nb] = true
			queue.append(nb)
	var expected := 0
	for c: Vector2i in room.walk:
		if not solid.has(c):
			expected += 1
	return seen.size() == expected


## Try to put one decor piece down. On success it is recorded (body, lane, solid cells, budget) and its
## placement Dictionary returned; {} when it does not fit.
##   extra: group, role, target (Vector2 it faces), params, lift, lane (false = no clear lane), w/d overrides,
##          center_ok (a blocking centrepiece), ignore (body kinds it may overlap), force (ignore the budget)
func place(room: RoomInfo, kind: String, pos: Vector2, yaw: float, extra: Dictionary = {}) -> Dictionary:
	var m: Dictionary = RoomThemeDefs.decor(kind)
	if m.is_empty():
		return {}
	var w: float = float(extra.get("w", m["w"]))
	var d: float = float(extra.get("d", m["d"]))
	var blocks: bool = bool(m["blocks"])
	var weight: float = float(extra.get("weight", m["weight"]))
	var group: int = int(extra.get("group", -1))
	if not bool(extra.get("force", false)) and room.used + weight > room.budget + 0.001:
		return {}
	var bw: float = float(extra.get("bw", 1.0))
	if blocks and room.blockers + bw > float(room.block_budget) + 0.001:
		return {}
	if blocks and not bool(extra.get("center_ok", false)) and pos.distance_to(room.center_w) < CENTER_CLEAR:
		return {}
	var ignore: Array = extra.get("ignore", [])
	if String(extra.get("place", m["place"])) == "wall" and wall_alignment(pos, yaw) < MIN_ALIGN:
		return {}
	if not fits(room, pos, yaw, w, d, group, ignore):
		return {}
	var want_lane: bool = bool(extra.get("lane", String(m["place"]) in ["wall", "corner", "center"]))
	if want_lane and not lane_ok(room, pos, yaw, d, group):
		return {}
	var circles: Dictionary = {}
	var added: Array[Vector2i] = []
	if blocks:
		circles = blocker_circles(pos, yaw, w, d)
		added = _solid_cells(circles["points"], float(circles["radius"]))
		var mark_n := room.solid_log.size()
		for c in added:
			if not solid.has(c):
				solid[c] = true
				room.solid_log.append(c)
		if not connected_ok(room):
			while room.solid_log.size() > mark_n:
				solid.erase(room.solid_log.pop_back())
			return {}
	var item := {
		"kind": kind, "pos": pos, "yaw": yaw, "cell": ThemeGeo.cell_of(pos), "room": room.tag,
		"place": String(extra.get("place", m["place"])), "orient": String(extra.get("orient", m["orient"])),
		"group": group, "role": String(extra.get("role", "")), "blocks": blocks, "w": w, "d": d,
		"lift": float(extra.get("lift", 0.0)), "priced": false, "lane": want_lane,
	}
	if extra.has("target"):
		item["target"] = extra["target"]
	if extra.has("params"):
		item["params"] = extra["params"]
	if blocks:
		item["block_points"] = circles["points"]
		item["block_radius"] = circles["radius"]
		room.blockers += bw
	room.used += weight
	room.items.append(item)
	add_body(room, pos, yaw, w, d, group, kind)
	if want_lane:
		add_body(room, pos + ThemeGeo.facing(yaw) * (d * 0.5 + LANE_AHEAD), yaw, 0.9, 0.9, group, kind, true)
	return item


## Record a priced prop's body, lane and solid cells (it stands where the pose says).
func commit_priced(room: RoomInfo, kind: String, pose: Dictionary, foot: Vector2, radius: float) -> void:
	var pos: Vector2 = pose["pos"]
	var yaw: float = pose["yaw"]
	add_body(room, pos, yaw, foot.x, foot.y, -1, kind)
	add_body(room, pos + ThemeGeo.facing(yaw) * (foot.y * 0.5 + LANE_AHEAD), yaw, 0.9, 0.9, -1, kind, true)
	for c in Hex.range_cells(ThemeGeo.cell_of(pos), 1):
		if ThemeGeo.hex_dist(pos, c) < radius + 0.1 and not solid.has(c):
			solid[c] = true
			room.solid_log.append(c)


## Everything planned so far, in room order.
func all_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tag: String in rooms:
		for it in (rooms[tag] as RoomInfo).items:
			out.append(it)
	return out
