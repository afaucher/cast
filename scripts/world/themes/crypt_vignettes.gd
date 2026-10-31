class_name CryptVignettes
extends RefCounted
## The crypt's rooms' vignettes (haunted-build-plan.md H2): the burial vault and bone vault under a mansion, the crypt chapel
## and ossuary under a church (RoomThemeDefs.THEMES, "crypt_set" vault | chapel), dressed with the look test's kit (DECOR rows
## with "crypt": CryptProps builds them in the room's set; docs/design/crypt-section.md). The same rules as ThemeVignettes,
## whose OPS name these: everything goes through ThemeCtx.place(), so nothing lands on a door, a corridor, the start or the
## exit, and a piece that does not fit is skipped. The layouts follow the look test's section: the sarcophagi against the
## burial chamber's wall with a candelabra at each end of the row and candles at their feet (the "vigil"), bone walls on
## straight runs of wall, a fallen skeleton, an opened tomb in the dark rooms, and in the chapel a pale shaft from above.

const VIGIL_SIDE := 0.95          ## a candelabra's centre off the end sarcophagus's centre, sideways
const VIGIL_BACK := 0.45          ## ... and back toward the heads (the wall)
const FOOT_CANDLES := 1.4         ## a candle cluster's centre ahead of a sarcophagus's centre, at its foot
const OSSUARY_W := 3.0            ## the widest bone wall (a run shorter than it gets a narrower one)
const OSSUARY_MIN_W := 1.5        ## no bone wall narrower than this
const RUN_REACH := 1.2            ## a wall run is looked for this far from the pose
const BONES_CLEAR := 2.5          ## a skeleton lies this far or more from the room's centre


static func _set_of(room: ThemeCtx.RoomInfo) -> String:
	return str(RoomThemeDefs.theme(room.theme).get("crypt_set", "vault"))


## The room's sarcophagi (CryptPlanner.plan_tombs placed them, priced), in plan order.
static func tombs_in(ctx: ThemeCtx, room: ThemeCtx.RoomInfo) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pr in ctx.plan.props:
		if str(pr["room"]) == room.tag and str(pr["kind"]).ends_with("_sarcophagus"):
			out.append(pr)
	return out


## The vigil round the room's row of sarcophagi: a lit candelabra at each end of the row, by the heads, and a cluster of floor
## candles at the foot of each (the look test's burial chamber).
static func vigil(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, _op: Dictionary = {}) -> bool:
	var tombs := tombs_in(ctx, room)
	if tombs.is_empty():
		return false
	var set_name := _set_of(room)
	var placed := false
	var ends: Array[Dictionary] = [tombs[0]]
	if tombs.size() > 1:
		ends.append(tombs[tombs.size() - 1])
	for i in ends.size():
		var t: Dictionary = ends[i]
		var pos: Vector2 = t["pos"]
		var yaw := float(t["yaw"])
		# the outer side of the row's end: away from the other end (a lone tomb tries both sides)
		var sides: Array[float] = [1.0, -1.0]
		if tombs.size() > 1:
			var other: Vector2 = (ends[1 - i] as Dictionary)["pos"]
			var lat := ThemeGeo.lateral(yaw)
			sides = [-1.0 if (other - pos).dot(lat) > 0.0 else 1.0]
		for side in sides:
			var cp := ThemeGeo.local_to_world(pos, yaw, side * VIGIL_SIDE, -VIGIL_BACK)
			if not ctx.place(room, "crypt_candelabra", cp, yaw, {"lane": false, "force": true, "role": "vigil",
					"params": {"set": set_name}}).is_empty():
				placed = true
				break
	for t in tombs:
		var fp := ThemeGeo.local_to_world(t["pos"], float(t["yaw"]), 0.0, FOOT_CANDLES)
		if not ctx.place(room, "crypt_candles", fp, ctx.rng.randf() * 360.0, {"lane": false, "force": true, "ignore": ["lane"],
				"role": "vigil", "params": {"set": set_name, "count": 5, "radius": 0.32, "light": 0.8}}).is_empty():
			placed = true
	return placed


## A bone wall (the ossuary: niches of skulls) on the straight run of wall behind a wall pose, centred on it and no wider than
## it (CryptProps.wall_run, the look test's placement: on the nearest point alone it sat across a corner).
static func ossuary(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, _op: Dictionary = {}) -> bool:
	var set_name := _set_of(room)
	var d := float(RoomThemeDefs.decor("ossuary")["d"])
	var tries := 0
	for pose in ThemeVignettes.wall_poses(ctx, room, "ossuary", 0.0, false, Vector2(OSSUARY_MIN_W, d)):
		tries += 1
		if tries > 16:
			break
		var pp: Vector2 = pose["pos"]
		var run := CryptProps.wall_run(ctx.map, pp, RUN_REACH)
		if run.is_empty():
			continue
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var n: Vector2 = run[2]
		var length := a.distance_to(b)
		var width := minf(OSSUARY_W, length - 0.2)
		if width < OSSUARY_MIN_W:
			continue
		var along := (b - a) / length
		var t := clampf((pp - a).dot(along), width * 0.5 + 0.1, length - width * 0.5 - 0.1)
		var at := a + along * t + n * (d * 0.5 + ThemeGeo.GAP)
		if not ctx.place(room, "ossuary", at, ThemeGeo.yaw_of(n), {"w": width, "params": {"set": set_name, "width": width}}).is_empty():
			return true
	return false


## A cluster of lit floor candles in a corner (or against a wall).
static func candles(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, _op: Dictionary = {}) -> bool:
	return not ThemeVignettes.corner_one(ctx, room, "crypt_candles", {"params": {"set": _set_of(room), "count": 7}}).is_empty()


## A fallen skeleton on the floor, off the room's middle (the fighting area), turned any way.
static func bones(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, _op: Dictionary = {}) -> bool:
	var cells := room.cells.duplicate()
	ThemeVignettes.shuffle(cells, ctx.rng)
	var tries := 0
	for c: Vector2i in cells:
		if not ctx.cell_free(room, c) or ThemeGeo.world(c).distance_to(room.center_w) < BONES_CLEAR:
			continue
		tries += 1
		if tries > 20:
			break
		if not ctx.place(room, "bones", ThemeGeo.world(c), ctx.rng.randf() * 360.0, {"lane": false, "params": {"set": _set_of(room)}}).is_empty():
			return true
	return false


## An opened sarcophagus, its lid pushed aside (something got out), head to a wall: decor (it is already broken open).
static func open_tomb(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, _op: Dictionary = {}) -> bool:
	return not ThemeVignettes.wall_one(ctx, room, "open_tomb", {"params": {"set": _set_of(room)}}).is_empty()


## The chapel's pale shaft of light from a grating in the church floor above: before the row of sarcophagi when the room has
## them, else near its middle.
static func shaft(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, _op: Dictionary = {}) -> bool:
	var spots: Array[Vector2] = []
	var tombs := tombs_in(ctx, room)
	if not tombs.is_empty():
		var mid := Vector2.ZERO
		for t in tombs:
			mid += t["pos"] as Vector2
		mid /= float(tombs.size())
		spots.append(mid + ThemeGeo.facing(float((tombs[0] as Dictionary)["yaw"])) * 0.6)
	for c in ThemeVignettes.cells_near(ctx, room, room.center_w, 5.0, 8):
		spots.append(ThemeGeo.world(c))
	for p in spots:
		if not ctx.place(room, "light_shaft", p, 0.0, {"lane": false, "ignore": ["lane", "vault_sarcophagus", "chapel_sarcophagus", "crypt_candles"]}).is_empty():
			return true
	return false
