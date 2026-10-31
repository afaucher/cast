class_name HauntVignettes
extends RefCounted
## The haunted rooms' vignettes (haunted-build-plan.md H1): the mansion's library, portrait gallery, ballroom, dining hall
## and conservatory and the church's nave (RoomThemeDefs.THEMES), dressed with the look test's props (DECOR rows with
## "haunt": HauntProps builds them). The same rules as ThemeVignettes, whose OPS name these (and its small makers place
## the single pieces: a row of bookshelves, a candelabrum in a corner): everything goes through ThemeCtx.place(), so
## nothing lands on a door, a corridor, the start or the exit, and a vignette that does not fit is rolled back whole.
## The layouts follow the look test's rooms (mansion-rooms.md, church-rooms.md), cut down to what a dealt room fits.

const READ_CHAIR_GAP := 1.05      ## a reading chair's centre from its table's
const DINING_SIDE := 1.0          ## a dining chair's centre from the table's long axis
const PEW_GAP := 1.3              ## a row of pews behind the next
const PEW_AISLE := 1.9            ## a block of pews' centre off the aisle (pews 2.8 wide: a 1.0 aisle)


## A reading table off the middle of the room with a wingback chair pulled up to it and a stack of books beside it.
static func reading(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, _op: Dictionary = {}) -> bool:
	for c in ThemeVignettes.cells_near(ctx, room, room.center_w, 9.0, 24):
		var pos := ThemeGeo.world(c)
		var mk := ctx.mark(room)
		var group := ctx.new_group()
		var to_door := room.entrance_w - pos
		var yaw := ThemeGeo.yaw_of(to_door.normalized() if to_door.length() > 0.5 else Vector2(0, 1)) + ThemeVignettes.jit(ctx)
		var table := ctx.place(room, "reading_table", pos, yaw, {"group": group, "role": "table", "lane": false})
		if table.is_empty():
			continue
		var f := ThemeGeo.facing(yaw)
		var cp := pos + f * READ_CHAIR_GAP
		var chair := ctx.place(room, "reading_chair", cp, ThemeGeo.yaw_of(-f) + ThemeVignettes.jit(ctx), {"group": group, "role": "seat", "target": pos, "lane": false})
		if chair.is_empty():
			ctx.rollback(room, mk)
			continue
		var lat := ThemeGeo.lateral(yaw)
		for side: float in [1.0, -1.0]:
			if not ctx.place(room, "book_stack", pos + lat * (side * 1.05), ctx.rng.randf() * 360.0, {"group": group, "role": "books", "lane": false}).is_empty():
				break
		return true
	return false


## A long runner down the room from its middle toward the door (the gallery's).
static func runner(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, _op: Dictionary = {}) -> bool:
	var dir := room.entrance_w - room.center_w
	var dist := dir.length()
	dir = dir.normalized() if dist > 0.5 else Vector2(0, 1)
	for frac: float in [0.2, 0.35, 0.5, 0.0, 0.65]:
		for length: float in [6.0, 5.0, 4.0]:
			# the runner's length lies along its local x (HauntProps.runner), so it turns a quarter from the walk direction
			var it := ctx.place(room, "runner", room.center_w + dir * (dist * frac), ThemeGeo.yaw_of(dir) + 90.0, {"w": length, "d": 1.4,
					"lane": false, "role": "runner", "force": true, "ignore": ["lane"], "params": {"length": length}})
			if not it.is_empty():
				return true
	return false


## The ballroom's dance floor: the parquet medallion (an eight-pointed star) at the room's middle, the chandelier hung over it.
static func dance_floor(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, _op: Dictionary = {}) -> bool:
	for c in ThemeVignettes.cells_near(ctx, room, room.center_w, 4.0, 10):
		var pos := ThemeGeo.world(c)
		var mk := ctx.mark(room)
		var group := ctx.new_group()
		var med := ctx.place(room, "medallion", pos, 0.0, {"group": group, "role": "floor", "lane": false, "center_ok": true, "ignore": ["lane"]})
		if med.is_empty():
			continue
		var ch := ctx.place(room, "chandelier", pos, ctx.rng.randf() * 60.0, {"group": group, "role": "chandelier", "lane": false,
				"center_ok": true, "force": true, "ignore": ["medallion", "lane"]})
		if not ch.is_empty():
			return true
		ctx.rollback(room, mk)
	return false


## The dining hall's long table at the room's focal point, set lengthwise, with high-backed chairs down both long sides.
static func banquet(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, _op: Dictionary = {}) -> bool:
	var to_door := room.entrance_w - room.center_w
	var along := ThemeGeo.yaw_of(to_door.normalized() if to_door.length() > 0.5 else Vector2(0, 1))
	for c in ThemeVignettes.cells_near(ctx, room, room.center_w, 5.0, 14):
		var pos := ThemeGeo.world(c)
		for length: float in [5.0, 3.6]:
			# the table's length lies along its local x: try it across the door line, then along it
			for yaw: float in [along, along + 90.0]:
				var mk := ctx.mark(room)
				var group := ctx.new_group()
				var table := ctx.place(room, "dining_table", pos, yaw, {"group": group, "role": "table", "w": length, "lane": false,
						"center_ok": true, "params": {"length": length}})
				if table.is_empty():
					ctx.rollback(room, mk)
					continue
				var chairs := 0
				var per_side := 4 if length >= 5.0 else 3
				for side: float in [1.0, -1.0]:
					for i in per_side:
						var lx := (float(i) - float(per_side - 1) * 0.5) * (length - 0.8) / float(per_side)
						var cp := ThemeGeo.local_to_world(pos, yaw, lx, side * DINING_SIDE)
						var target := ThemeGeo.local_to_world(pos, yaw, lx, 0.0)
						var cyaw := ThemeGeo.yaw_of((target - cp).normalized()) + ThemeVignettes.jit(ctx)
						if not ctx.place(room, "dining_chair", cp, cyaw, {"group": group, "role": "seat", "target": target, "lane": false}).is_empty():
							chairs += 1
				if chairs >= 4:
					return true
				ctx.rollback(room, mk)
	return false


## The conservatory's raised planter bed, off the middle of the room.
static func planters(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, _op: Dictionary = {}) -> bool:
	for c in ThemeVignettes.cells_near(ctx, room, room.center_w, 9.0, 24):
		var pos := ThemeGeo.world(c)
		var to_c := room.center_w - pos
		var yaw := ThemeGeo.yaw_of(to_c.normalized() if to_c.length() > 0.5 else Vector2(0, 1)) + 90.0
		if not ctx.place(room, "planter_bed", pos, yaw, {"role": "planter", "lane": false}).is_empty():
			return true
	return false


## The nave: the altar on its stone step against a wall, and rows of pews facing it in two blocks either side of an aisle.
## Of the walls, the one with the most pews (and the most camera-facing altar) wins, like the cinema's screen.
static func pews(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, _op: Dictionary = {}) -> bool:
	var ranked: Array[Dictionary] = []
	var tries := 0
	for pose in ThemeVignettes.wall_poses(ctx, room, "altar", 3.0):
		tries += 1
		if tries > 14:
			break
		var mk := ctx.mark(room)
		var n := _nave_try(ctx, room, pose)
		ctx.rollback(room, mk)
		if n >= 4:
			pose["value"] = float(n) + 3.0 * float(pose["cam"]) + ctx.rng.randf()
			ranked.append(pose)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["value"]) > float(b["value"]))
	for pose in ranked:
		var mk2 := ctx.mark(room)
		if _nave_try(ctx, room, pose) >= 4:
			return true
		ctx.rollback(room, mk2)
	return false


## The altar at `pose`, its step under it and the pews before it; returns the pew count (0: the altar did not fit). The
## caller keeps or rolls back the result.
static func _nave_try(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, pose: Dictionary) -> int:
	var group := ctx.new_group()
	var apos: Vector2 = pose["pos"]
	var ayaw: float = pose["yaw"]
	var altar := ctx.place(room, "altar", apos, ayaw, {"group": group, "role": "altar", "lift": 0.25})
	if altar.is_empty():
		return 0
	var f := ThemeGeo.facing(ayaw)
	var dais_d := float(RoomThemeDefs.decor("altar_dais")["d"])
	ctx.place(room, "altar_dais", apos + f * (dais_d * 0.5 - 0.35), ayaw, {"group": group, "role": "dais", "target": apos + f * 9.0, "lane": false,
			"force": true, "ignore": ["altar", "lane"]})
	var rows := 4 if room.cells.size() >= 130 else 3
	var placed := 0
	for r in rows:
		var dist := dais_d - 0.35 + 0.9 + PEW_GAP * float(r)
		for side: float in [-1.0, 1.0]:
			var pp := ThemeGeo.local_to_world(apos, ayaw, side * PEW_AISLE, dist)
			var target := ThemeGeo.local_to_world(apos, ayaw, side * PEW_AISLE, 0.0)
			if not ctx.place(room, "pew", pp, ThemeGeo.yaw_of(-f), {"group": group, "role": "seat", "target": target, "lane": false}).is_empty():
				placed += 1
	return placed
