class_name ThemeVignettes
extends RefCounted
## The recipes behind the room themes. Each op places a vignette as ONE unit with relative transforms (a
## cinema screen on a wall with rows of recliners facing it; a table with chairs facing it; a desk, its
## monitor and its chair; bunk rows; a bench in front of its rack; candles ringing a chalk circle; a
## barrel cluster) or a single piece by its rule (wall-backed, corner, centrepiece, floor). Everything goes
## through ThemeCtx.place(), so nothing lands on a door, a corridor, the start or the exit, off flat floor, or
## in front of something that faces it; a vignette that does not fit is rolled back whole.

const SEAT_JITTER := 8.0          ## degrees; the rule allows 10, the test 15


## Run one recipe op in a room. True when it placed something.
static func run(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, op: Dictionary) -> bool:
	if room.cells.size() < int(op.get("min_cells", 0)):
		return false
	match String(op["op"]):
		"cinema": return cinema(ctx, room)
		"popcorn": return not corner_one(ctx, room, "popcorn_machine").is_empty()
		"tasting": return tasting(ctx, room)
		"barrels": return barrels(ctx, room)
		"circle": return circle(ctx, room)
		"mats": return mats(ctx, room)
		"bench_rack": return bench_rack(ctx, room)
		"dumbbells": return not wall_one(ctx, room, "dumbbell_rack").is_empty()
		"racks": return wall_row(ctx, room, "rack_cab", 3, 1.05, 2)
		"desk": return desk(ctx, room)
		"crates": return not corner_one(ctx, room, "crate_stack").is_empty()
		"pool": return pool(ctx, room)
		"cage": return not corner_one(ctx, room, "chains_cage").is_empty()
		"carpet": return carpet(ctx, room)
		"shelf": return not wall_one(ctx, room, "specimen_shelf").is_empty()
		"bunks": return wall_row(ctx, room, "bunk_bed", 3, 2.15, 2)
		"moat": return moat(ctx, room)
		"sign": return neon(ctx, room, op)
		"hazard": return hazard(ctx, room)
		"wet_floor": return wet_floor(ctx, room)
	return false


# --- helpers ------------------------------------------------------------------------------------------------------

static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


static func jit(ctx: ThemeCtx, amount: float = SEAT_JITTER) -> float:
	return ctx.rng.randf_range(-amount, amount)


static func _size_of(kind: String, size: Vector2) -> Vector2:
	if size != Vector2.ZERO:
		return size
	var m: Dictionary = RoomThemeDefs.decor(kind)
	return Vector2(float(m["w"]), float(m["d"]))


## Every wall-backed (or, with `corner`, corner) pose for `kind` on the room's free wall cells, shuffled. A
## pose is {pos, yaw, cell, normal}; each one already fits (footprint, bodies), lanes aside.
static func wall_poses(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, kind: String, jitter: float = 6.0, corner: bool = false, size: Vector2 = Vector2.ZERO) -> Array[Dictionary]:
	var sz := _size_of(kind, size)
	var out: Array[Dictionary] = []
	# a wide piece also tries sliding half a cell along the wall (a hex wall is a sawtooth: more places fit)
	var shifts: Array[float] = [0.0]
	if not corner and sz.x >= 1.5:
		shifts = [0.0, -0.55, 0.55]
	for c in room.cells:
		if not ctx.cell_free(room, c) or ctx.wall_dirs(c).is_empty():
			continue
		for shift in shifts:
			var j := jit(ctx, jitter) if jitter > 0.0 else 0.0
			var pose: Dictionary = {}
			if corner:
				pose = ctx.corner_pose(room, c, sz.x, sz.y, j)
			elif shift == 0.0:
				pose = ctx.wall_pose(room, c, sz.x, sz.y, j)
			else:
				var n := ctx.wall_normal(c)
				if n != Vector2.ZERO:
					pose = ctx.wall_pose_at(room, ThemeGeo.world(c) + Vector2(-n.y, n.x) * shift, n, sz.x, sz.y, j)
			if pose.is_empty():
				continue
			if not ctx.fits(room, pose["pos"], pose["yaw"], sz.x, sz.y):
				continue
			pose["walls"] = ctx.wall_dirs(c).size()
			pose["cam"] = ThemeGeo.facing(float(pose["yaw"])).dot(ThemeGeo.CAMERA_DIR)
			pose["score"] = 2.0 * float(pose["cam"]) + ctx.rng.randf() * 1.3     # the far walls first, but not only them
			out.append(pose)
			break                                                               # one pose per anchor cell: the first shift that fits
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	if corner:
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["walls"]) > int(b["walls"]))
	return out


## One piece against a wall, back to the wall, facing into the room.
static func wall_one(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, kind: String, extra: Dictionary = {}, size: Vector2 = Vector2.ZERO) -> Dictionary:
	var tries := 0
	for pose in wall_poses(ctx, room, kind, 6.0, false, size):
		tries += 1
		if tries > 14:
			break
		var ex := extra.duplicate()
		if size != Vector2.ZERO:
			ex["w"] = size.x
			ex["d"] = size.y
		var it := ctx.place(room, kind, pose["pos"], pose["yaw"], ex)
		if not it.is_empty():
			return it
	return {}


## One piece in a concave corner facing the room's centre; with no such corner, against a wall.
static func corner_one(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, kind: String, extra: Dictionary = {}) -> Dictionary:
	var tries := 0
	for pose in wall_poses(ctx, room, kind, 6.0, true):
		tries += 1
		if tries > 14:
			break
		var it := ctx.place(room, kind, pose["pos"], pose["yaw"], extra)
		if not it.is_empty():
			return it
	var fallback := extra.duplicate()
	fallback["place"] = "wall"            # no corner fits: it stands against a wall instead, facing into the room
	fallback["orient"] = "away_from_wall"
	return wall_one(ctx, room, kind, fallback)


## Room cells nearest a world point, free to stand on, nearest first (at most `limit`, within `max_d` units).
static func cells_near(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, p: Vector2, max_d: float, limit: int = 18) -> Array[Vector2i]:
	var scored: Array[Dictionary] = []
	for c in room.cells:
		if not ctx.cell_free(room, c):
			continue
		var d := ThemeGeo.world(c).distance_to(p)
		if d <= max_d:
			scored.append({"c": c, "d": d})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	var out: Array[Vector2i] = []
	for s in scored:
		out.append(s["c"])
		if out.size() >= limit:
			break
	return out


static func find_priced(ctx: ThemeCtx, tag: String, kind: String) -> Dictionary:
	for pr in ctx.plan.props:
		if str(pr["room"]) == tag and str(pr["kind"]) == kind and pr.has("pos"):
			return pr
	return {}


# --- cinema -------------------------------------------------------------------------------------------------------

## A screen on a wall, 2-3 rows of recliners facing it. If the room holds the projector, the screen goes on
## the wall the projector faces and the projector faces it. Of the candidate walls the one with the most seats
## (and the most camera-facing screen) wins.
static func cinema(ctx: ThemeCtx, room: ThemeCtx.RoomInfo) -> bool:
	var proj := find_priced(ctx, room.tag, "projector")
	var scored: Array[Dictionary] = []
	for pose in wall_poses(ctx, room, "cinema_screen", 3.0):
		var f := ThemeGeo.facing(pose["yaw"])
		var s := minf(ctx.free_run(room, pose["pos"], f, 12.0), 10.0)
		if not proj.is_empty():
			var to_proj: Vector2 = (proj["pos"] as Vector2) - (pose["pos"] as Vector2)
			var pf := ThemeGeo.facing(float(proj["yaw"]))
			s += 10.0 * f.dot(to_proj.normalized()) + 10.0 * pf.dot(-to_proj.normalized())
		s += ctx.rng.randf() * 1.5 + 5.0 * float(pose["cam"])
		pose["score"] = s
		scored.append(pose)
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	var min_seats := 4 if room.cells.size() >= 130 else 3       # a cramped room gets a small cinema
	var ranked: Array[Dictionary] = []
	var tries := 0
	for pose in scored:
		tries += 1
		if tries > 16:
			break
		var mk := ctx.mark(room)
		var seats := _cinema_try(ctx, room, pose)
		ctx.rollback(room, mk)
		if seats >= min_seats:
			pose["value"] = float(seats) + float(pose["score"]) * 0.25
			ranked.append(pose)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["value"]) > float(b["value"]))
	for pose in ranked:
		var mk2 := ctx.mark(room)
		if _cinema_try(ctx, room, pose) >= min_seats:
			return true
		ctx.rollback(room, mk2)
	return false


## Place the screen at `pose` and the recliner rows in front of it; returns the seat count (0 = the screen did
## not fit). The caller rolls back or keeps the result.
static func _cinema_try(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, pose: Dictionary) -> int:
	var group := ctx.new_group()
	var screen := ctx.place(room, "cinema_screen", pose["pos"], pose["yaw"], {"group": group, "role": "screen"})
	if screen.is_empty():
		return 0
	var rows := 3 if room.cells.size() >= 130 else 2
	var seats := 0
	var spos: Vector2 = pose["pos"]
	for r in rows:
		var dist := 3.3 + 1.9 * float(r)
		for k: int in [-1, 0, 1]:
			var sp := ThemeGeo.local_to_world(spos, pose["yaw"], 1.7 * float(k), dist)
			var syaw := ThemeGeo.yaw_of((spos - sp).normalized()) + jit(ctx)
			var seat := ctx.place(room, "recliner", sp, syaw, {"group": group, "role": "seat", "target": spos, "lane": false})
			if not seat.is_empty():
				seats += 1
	return seats


# --- tables, desks, benches ---------------------------------------------------------------------------------------

## A tasting table at the room's focal point with chairs facing it. Big rooms only (the recipe's min_cells).
static func tasting(ctx: ThemeCtx, room: ThemeCtx.RoomInfo) -> bool:
	for c in cells_near(ctx, room, room.center_w, 8.0, 24):
		var pos := ThemeGeo.world(c)
		var mk := ctx.mark(room)
		var group := ctx.new_group()
		var to_door := room.entrance_w - pos
		var yaw := ThemeGeo.yaw_of(to_door.normalized() if to_door.length() > 0.5 else Vector2(0, 1)) + jit(ctx)
		var table := ctx.place(room, "tasting_table", pos, yaw, {"group": group, "role": "table", "center_ok": true, "lane": false})
		if table.is_empty():
			continue
		var chairs := 0
		var a0 := ctx.rng.randf() * 90.0
		for k in 4:
			var ang := deg_to_rad(a0 + 90.0 * float(k) + ctx.rng.randf_range(-10.0, 10.0))
			var cp := pos + Vector2(cos(ang), sin(ang)) * 1.3
			var cyaw := ThemeGeo.yaw_of((pos - cp).normalized()) + jit(ctx)
			if not ctx.place(room, "chair", cp, cyaw, {"group": group, "role": "seat", "target": pos, "lane": false}).is_empty():
				chairs += 1
		if chairs >= 3:
			return true
		ctx.rollback(room, mk)
	return false


## A desk against the wall, its monitor on it, its chair pulled up facing it.
static func desk(ctx: ThemeCtx, room: ThemeCtx.RoomInfo) -> bool:
	var tries := 0
	for pose in wall_poses(ctx, room, "desk", 6.0):
		tries += 1
		if tries > 10:
			break
		var mk := ctx.mark(room)
		var group := ctx.new_group()
		var pos: Vector2 = pose["pos"]
		var yaw: float = pose["yaw"]
		var dsk := ctx.place(room, "desk", pos, yaw, {"group": group, "role": "desk", "lane": false})
		if dsk.is_empty():
			continue
		var f := ThemeGeo.facing(yaw)
		ctx.place(room, "monitor", pos - f * 0.12, yaw, {"group": group, "role": "monitor", "lift": 0.85, "lane": false, "force": true, "ignore": ["desk"]})
		var cpos := pos + f * (0.425 + 0.6)
		var cyaw := ThemeGeo.yaw_of(-f) + jit(ctx)
		var chair := ctx.place(room, "office_chair", cpos, cyaw, {"group": group, "role": "seat", "target": pos, "lane": false})
		if not chair.is_empty():
			return true
		ctx.rollback(room, mk)
	return false


## A dumbbell rack against the wall with a weight bench in front of it (the bench's head end toward the rack).
static func bench_rack(ctx: ThemeCtx, room: ThemeCtx.RoomInfo) -> bool:
	var tries := 0
	for pose in wall_poses(ctx, room, "dumbbell_rack", 6.0):
		tries += 1
		if tries > 10:
			break
		var mk := ctx.mark(room)
		var group := ctx.new_group()
		var pos: Vector2 = pose["pos"]
		var yaw: float = pose["yaw"]
		var rack := ctx.place(room, "dumbbell_rack", pos, yaw, {"group": group, "role": "rack", "lane": false})
		if rack.is_empty():
			continue
		var f := ThemeGeo.facing(yaw)
		var bpos := pos + f * (0.325 + 0.55 + 0.8)
		var byaw := ThemeGeo.yaw_of(-f) + jit(ctx)
		var bench := ctx.place(room, "weight_bench", bpos, byaw, {"group": group, "role": "bench", "target": pos, "lane": false})
		if not bench.is_empty():
			return true
		ctx.rollback(room, mk)
	return false


## A row of identical pieces along one wall (bunks, server cabinets), each hugging the wall, all facing the
## room the same way.
static func wall_row(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, kind: String, count: int, spacing: float, min_count: int) -> bool:
	var sz := _size_of(kind, Vector2.ZERO)
	var tries := 0
	for pose in wall_poses(ctx, room, kind, 0.0):
		tries += 1
		if tries > 10:
			break
		var mk := ctx.mark(room)
		var group := ctx.new_group()
		var yaw: float = pose["yaw"]
		var n: Vector2 = pose["normal"]
		var first := ctx.place(room, kind, pose["pos"], yaw, {"group": group, "role": "row"})
		if first.is_empty():
			continue
		var placed := 1
		var lat := ThemeGeo.lateral(yaw)
		for k: int in [1, -1, 2, -2]:
			if placed >= count:
				break
			var p0: Vector2 = (pose["pos"] as Vector2) + lat * (spacing * float(k)) - n * 0.6
			var np := ctx.wall_pose_at(room, p0, n, sz.x, sz.y, 0.0)
			if np.is_empty():
				continue
			if not ctx.place(room, kind, np["pos"], yaw, {"group": group, "role": "row"}).is_empty():
				placed += 1
		if placed >= min_count:
			return true
		ctx.rollback(room, mk)
	return false


# --- barrels ------------------------------------------------------------------------------------------------------

## A cluster of 2-3 barrels in a corner.
static func barrels(ctx: ThemeCtx, room: ThemeCtx.RoomInfo) -> bool:
	var tries := 0
	for pose in wall_poses(ctx, room, "barrel", 0.0, true):
		tries += 1
		if tries > 10:
			break
		var mk := ctx.mark(room)
		var group := ctx.new_group()
		var pos: Vector2 = pose["pos"]
		var first := ctx.place(room, "barrel", pos, ctx.rng.randf() * 360.0, {"group": group, "role": "cluster", "lane": false, "bw": 0.5})
		if first.is_empty():
			continue
		var n := 1
		var toward := (room.center_w - pos).normalized()
		for ang: float in [-58.0, 58.0, 0.0]:
			if n >= 3:
				break
			var p2 := pos + toward.rotated(deg_to_rad(ang)) * 0.95
			if not ctx.place(room, "barrel", p2, ctx.rng.randf() * 360.0, {"group": group, "role": "cluster", "lane": false, "bw": 0.5}).is_empty():
				n += 1
		if n >= 2:
			return true
		ctx.rollback(room, mk)
	return false


# --- spa: the chalk circle, candles, mats ------------------------------------------------------------------------------

## Candles ringing a chalk summoning circle at the room's focal point. If a hellgate stands there the circle is
## drawn around the gate (it IS the summoning circle); otherwise it sits at the centre.
static func circle(ctx: ThemeCtx, room: ThemeCtx.RoomInfo) -> bool:
	var origin := not room.gate.is_empty() and bool(room.gate["origin"])
	var cands: Array[Dictionary] = []      # {pos, radius, gate}
	if not room.gate.is_empty():
		cands.append({"pos": ThemeGeo.world(room.gate["cell"]), "radius": 3.5 if origin else 2.25, "gate": true})
		cands.append({"pos": ThemeGeo.world(room.gate["cell"]), "radius": 2.9 if origin else 1.9, "gate": true})
	for c in cells_near(ctx, room, room.center_w, 6.0, 8):
		cands.append({"pos": ThemeGeo.world(c), "radius": 2.1, "gate": false})
	var ok := false
	for cd in cands:
		var pos: Vector2 = cd["pos"]
		var radius: float = cd["radius"]
		var around_gate: bool = cd["gate"]
		ctx.allow_gate = around_gate
		var mk := ctx.mark(room)
		var group := ctx.new_group()
		var side := radius * 1.42
		var circ := ctx.place(room, "summoning_circle", pos, ctx.rng.randf() * 360.0, {"group": group, "role": "circle", "w": side, "d": side, "lane": false,
				"center_ok": true, "ignore": ["gate", "lane"], "params": {"radius": radius}})
		if circ.is_empty():
			continue
		var ring_r := radius + 0.5
		var count := 12 if (around_gate and origin) else 10
		var placed := 0
		var a0 := ctx.rng.randf() * TAU
		for i in count:
			var ang := a0 + TAU * float(i) / float(count) + ctx.rng.randf_range(-0.08, 0.08)
			var cp := pos + Vector2(cos(ang), sin(ang)) * ring_r
			if not ctx.place(room, "candle", cp, ctx.rng.randf() * 360.0, {"group": group, "role": "candle", "lane": false, "ignore": ["gate", "lane"], "force": true}).is_empty():
				placed += 1
		if placed >= 5:
			ok = true
			break
		ctx.rollback(room, mk)
	ctx.allow_gate = false
	return ok


## Three yoga mats side by side, all facing the same way (away from the door), around the middle of the room.
static func mats(ctx: ThemeCtx, room: ThemeCtx.RoomInfo) -> bool:
	var away := room.center_w - room.entrance_w
	var yaw0 := ThemeGeo.yaw_of(away.normalized() if away.length() > 1.0 else Vector2(0, 1))
	var lat := ThemeGeo.lateral(yaw0)
	var cands: Array[Dictionary] = []
	for c in room.cells:
		if ctx.cell_free(room, c):
			cands.append({"c": c, "s": absf(ThemeGeo.world(c).distance_to(room.center_w) - 4.2) + ctx.rng.randf() * 0.8})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) < float(b["s"]))
	var tries := 0
	for cd in cands:
		tries += 1
		if tries > 16:
			break
		var mk := ctx.mark(room)
		var group := ctx.new_group()
		var base := ThemeGeo.world(cd["c"])
		var n := 0
		for k: int in [0, 1, -1]:
			var y := yaw0 + jit(ctx, 6.0)
			if not ctx.place(room, "yoga_mat", base + lat * float(k), y, {"group": group, "role": "mat", "lane": false}).is_empty():
				n += 1
		if n >= 2:
			return true
		ctx.rollback(room, mk)
	return false


# --- pool, moat, carpet -------------------------------------------------------------------------------------------

## A pool basin at the focal point with loungers along its sides, each facing the water.
static func pool(ctx: ThemeCtx, room: ThemeCtx.RoomInfo) -> bool:
	for c in cells_near(ctx, room, room.center_w, 9.0, 28):
		var pos := ThemeGeo.world(c)
		var mk := ctx.mark(room)
		var group := ctx.new_group()
		var to_door := room.entrance_w - pos
		var yaw := ThemeGeo.yaw_of(to_door.normalized() if to_door.length() > 0.5 else Vector2(0, 1)) + jit(ctx)
		var basin := ctx.place(room, "pool_basin", pos, yaw, {"group": group, "role": "pool", "center_ok": true, "lane": false})
		if basin.is_empty():
			continue
		if _loungers(ctx, room, pos, yaw, group, [1.0, -1.0]) >= 2:
			return true
		ctx.rollback(room, mk)
	# the middle is taken (a hellgate, the elevator, raised floor): a pool along a wall, loungers on the room side
	var tries := 0
	for pose in wall_poses(ctx, room, "pool_basin", 4.0):
		tries += 1
		if tries > 8:
			break
		var mk2 := ctx.mark(room)
		var group2 := ctx.new_group()
		var basin2 := ctx.place(room, "pool_basin", pose["pos"], pose["yaw"], {"group": group2, "role": "pool", "place": "wall", "orient": "away_from_wall", "lane": false})
		if basin2.is_empty():
			continue
		if _loungers(ctx, room, pose["pos"], pose["yaw"], group2, [1.0]) >= 2:
			return true
		ctx.rollback(room, mk2)
	return false


## Loungers beside a basin at (pos, yaw), on the given sides (+1 = the basin's front), each facing the water.
static func _loungers(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, pos: Vector2, yaw: float, group: int, sides: Array[float]) -> int:
	var f := ThemeGeo.facing(yaw)
	var lat := ThemeGeo.lateral(yaw)
	var n := 0
	for side: float in sides:
		for k: float in [-1.0, 1.0]:
			var lp := pos + f * (side * 2.55) + lat * (k * 1.15)
			var lyaw := ThemeGeo.yaw_of((pos - lp).normalized()) + jit(ctx)
			if not ctx.place(room, "pool_lounger", lp, lyaw, {"group": group, "role": "seat", "target": pos, "lane": false}).is_empty():
				n += 1
	return n


## A moat ring around the focal point (the hellgate when there is one) with a plank bridge at the door side
## and two fins patrolling it.
static func moat(ctx: ThemeCtx, room: ThemeCtx.RoomInfo) -> bool:
	var origin := not room.gate.is_empty() and bool(room.gate["origin"])
	var cands: Array[Dictionary] = []      # {pos, radius, gate}
	if not room.gate.is_empty():
		cands.append({"pos": ThemeGeo.world(room.gate["cell"]), "radius": 4.3 if origin else 3.0, "gate": true})
	for c in cells_near(ctx, room, room.center_w, 7.0, 16):
		cands.append({"pos": ThemeGeo.world(c), "radius": 2.8, "gate": false})
	for c in cells_near(ctx, room, room.center_w, 7.0, 16):
		cands.append({"pos": ThemeGeo.world(c), "radius": 2.2, "gate": false})
	var ok := false
	for cd in cands:
		var pos: Vector2 = cd["pos"]
		var radius: float = cd["radius"]
		var around_gate: bool = cd["gate"]
		ctx.allow_gate = around_gate
		# the whole ring (and its rims) must lie on free floor
		var clear := true
		for i in 28:
			var a := TAU * float(i) / 28.0
			for rr: float in [radius - 0.55, radius, radius + 0.55]:
				if not ctx.cell_free(room, ThemeGeo.cell_of(pos + Vector2(cos(a), sin(a)) * rr)):
					clear = false
					break
			if not clear:
				break
		if not clear:
			continue
		var to_door := room.entrance_w - pos
		var gap_yaw := ThemeGeo.yaw_of(to_door.normalized() if to_door.length() > 0.5 else Vector2(0, 1))
		var mk := ctx.mark(room)
		var group := ctx.new_group()
		var water := ctx.place(room, "moat_water", pos, gap_yaw, {"group": group, "role": "moat", "w": 0.8, "d": 0.8, "lane": false, "center_ok": true,
				"ignore": ["gate", "lane"], "force": true, "params": {"radius": radius, "width": 0.95, "gap": 48.0}})
		if water.is_empty():
			continue
		# the ring as bodies, so nothing else is dropped into the water
		for i in 10:
			var a2 := TAU * float(i) / 10.0
			var mid := pos + Vector2(cos(a2), sin(a2)) * radius
			ctx.add_body(room, mid, rad_to_deg(PI * 0.5 - a2), 1.4, radius * TAU / 10.0, group, "moat")
		for i in 2:
			var fa := 0.7 + PI * float(i)
			ctx.place(room, "shark_fin", pos + Vector2(cos(fa), sin(fa)) * radius, 0.0, {"group": group, "role": "fin", "lane": false, "force": true, "ignore": ["moat", "gate", "lane"],
					"params": {"center": pos, "radius": radius, "gap_yaw": gap_yaw, "phase": float(i) * 2.2, "speed": 0.6 + 0.15 * float(i)}})
		ok = true
		break
	ctx.allow_gate = false
	return ok


## A red carpet runner leading from the throne toward the door (from the middle of the room toward the door
## when there is no throne).
static func carpet(ctx: ThemeCtx, room: ThemeCtx.RoomInfo) -> bool:
	var throne := find_priced(ctx, room.tag, "villain_throne")
	if not throne.is_empty():
		var tf := ThemeGeo.facing(float(throne["yaw"]))
		var foot: Vector2 = throne.get("foot", Vector2(1.1, 1.1))
		for off: float in [0.1, 0.6, 1.1]:       # the runner starts at the throne's front, or a little out (the wall's teeth)
			var start := (throne["pos"] as Vector2) + tf * (foot.y * 0.5 + off)
			for length: float in [7.0, 6.0, 5.0, 4.0, 3.0]:
				if _carpet_at(ctx, room, start + tf * (length * 0.5), tf, length):
					return true
		return false
	# no throne here: a runner from the middle of the room toward the door
	var dir := room.entrance_w - room.center_w
	var dist := dir.length()
	dir = dir.normalized() if dist > 0.5 else Vector2(0, 1)
	for frac: float in [0.25, 0.4, 0.55, 0.7, 0.1, 0.85, -0.1, -0.25]:
		for length: float in [6.0, 5.0, 4.0, 3.0]:
			if _carpet_at(ctx, room, room.center_w + dir * (dist * frac), dir, length):
				return true
	return false


static func _carpet_at(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, mid: Vector2, dir: Vector2, length: float) -> bool:
	var it := ctx.place(room, "red_carpet", mid, ThemeGeo.yaw_of(dir), {"w": 1.5, "d": length, "lane": false, "role": "carpet", "force": true,
			"ignore": ["lane"], "params": {"length": length}})
	return not it.is_empty()


# --- signs ---------------------------------------------------------------------------------------------------------

## A standing neon sign against a wall, facing into the room (preferring a wall the door looks at).
static func neon(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, op: Dictionary) -> bool:
	var text := String(op["text"])
	var sz := Vector2(DecorModels.sign_width(text) + 0.2, 0.4)
	var scored: Array[Dictionary] = []
	var all_poses := wall_poses(ctx, room, "neon_sign", 6.0, false, sz)
	var readable: Array[Dictionary] = []      # a sign has to be readable from the game camera: facing it, not edge-on
	for pose in all_poses:
		if float(pose["cam"]) >= 0.3:
			readable.append(pose)
	for pose in (readable if not readable.is_empty() else all_poses):
		var to_door: Vector2 = room.entrance_w - (pose["pos"] as Vector2)
		pose["score"] = 0.6 * ThemeGeo.facing(pose["yaw"]).dot(to_door.normalized()) + 2.5 * float(pose["cam"]) + ctx.rng.randf() * 0.8
		scored.append(pose)
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	var tries := 0
	for pose in scored:
		tries += 1
		if tries > 10:
			break
		var params := {"text": text, "color": op["color"], "dead": op.get("dead", [])}
		var it := ctx.place(room, "neon_sign", pose["pos"], pose["yaw"], {"w": sz.x, "d": sz.y, "role": "sign", "params": params})
		if not it.is_empty():
			return true
	return false


# --- the service entrance ------------------------------------------------------------------------------------------

## Hazard tape strung along a wall, near where the crew starts.
static func hazard(ctx: ThemeCtx, room: ThemeCtx.RoomInfo) -> bool:
	var scored: Array[Dictionary] = []
	for pose in wall_poses(ctx, room, "hazard_tape", 6.0):
		var d := float(Hex.distance(pose["cell"], ctx.plan.start))
		pose["score"] = -absf(d - 6.0) + ctx.rng.randf() * 1.5
		scored.append(pose)
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	var tries := 0
	for pose in scored:
		tries += 1
		if tries > 10:
			break
		if not ctx.place(room, "hazard_tape", pose["pos"], pose["yaw"], {"role": "tape"}).is_empty():
			return true
	return false


## A WET FLOOR sign a few cells from the start, facing it.
static func wet_floor(ctx: ThemeCtx, room: ThemeCtx.RoomInfo) -> bool:
	var start_w := ThemeGeo.world(ctx.plan.start)
	var cands: Array[Dictionary] = []
	for c in room.cells:
		if not ctx.cell_free(room, c):
			continue
		var d := Hex.distance(c, ctx.plan.start)
		if d < 4 or d > 6:
			continue
		cands.append({"c": c, "s": absf(float(d) - 4.0) * 1.5 + ThemeGeo.world(c).distance_to(room.entrance_w) * 0.2 + ctx.rng.randf()})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) < float(b["s"]))
	var tries := 0
	for cd in cands:
		tries += 1
		if tries > 12:
			break
		var pos := ThemeGeo.world(cd["c"])
		var yaw := ThemeGeo.yaw_of((start_w - pos).normalized()) + jit(ctx)
		if not ctx.place(room, "wet_floor_sign", pos, yaw, {"role": "sign", "target": start_w, "lane": false}).is_empty():
			return true
	return false
