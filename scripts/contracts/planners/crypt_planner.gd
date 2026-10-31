class_name CryptPlanner
extends RefCounted
## HAUNTED H2 (docs/design/haunted-build-plan.md, "H2 as built"): a haunted floor's CRYPT in the site plan. DungeonGen cut it
## (its "crypt" option, CryptCluster: 2-4 rooms of a wing at one base level, their links flat, a narrow stair of flights down
## into them) and left its record in HexMap.crypt; this planner themes and dresses it with the look test's kit (CryptProps,
## CryptLook's vault and chapel sets: docs/design/crypt-section.md). On a floor without a crypt every step returns at once, so
## nothing on the floor moves.
##
## SiteBuilder.plan calls, in this order:
##   theme()       after RoomThemes.assign (no dice): the crypt's set from the site (CryptCluster.SETS: the vault under a
##                 mansion, the chapel under a church) and each room's look by its steps from the stair's foot: the foot's
##                 room LIT (the burial chamber), the next DARK (the ossuary gallery), and so on (RoomThemeDefs.CRYPT). The
##                 origin room is never a crypt room (GatePlanner keeps it out; if it ever were, it would keep the theme its
##                 story names). Written to the record: set, lit, dark.
##   plan_tombs()  after the priced props and the landings' set pieces, on the crypt's own dice (lent to the ThemeCtx for its
##                 poses): in each lit room a ROW of PRICED sarcophagi (PricedProp "<set>_sarcophagus") head to a wall, side
##                 by side, facing into the room: SitePlan.props, so the decor (the vigil's candles) steers round them.
##   dress()       after the decor (no dice): candles on the stair's landing between its flights.
##   materials()   after FloorMaterials.assign: the crypt's halls and the stair in its set's hall stone, the walls round it
##                 in its blocks (its rooms wear their theme rows').
## DoorPlanner asks doorways() which doorways are the crypt's (none gets an office door) and puts gate() in each: a stone
## arch at the head of the stair (in the room above), an open iron gate at its foot, a half-open gate into a lit room and an
## arch into a dark one (decor: nothing shuts).
## Its actors are ordinary: the sarcophagi are priced props (host-arbitrated, spawned with the floor's props), the rest is
## decor. SiteBuilder.spawn calls spawn() last (cosmetic): the pieces on the crypt's floor go out of the key light with its
## stone (HexMapView.UNDER_LAYER), so candles light the crypt as they lit the look test's. Floor data only: every machine plans the same crypt from the seed (map.crypt is in NetFloor's checksum).

const TOMB_SPACING := 1.7          ## a sarcophagus's centre from the next one's in a row
const TOMB_POSES := 12             ## wall poses tried for a row's first sarcophagus
const LANDING_SIDE := 0.85         ## the landing's candles off the stair's centre line, toward a wall
const FOOT_OPEN := 0.85            ## the gate at the stair's foot: open
const LIT_OPEN := 0.45             ## the gate into a lit room: half open

## Microseconds the last floor's crypt planning took (not in SiteBuilder.last_plan_usec).
static var last_usec := 0


## The floor's crypt record (HexMap.crypt), {} when it has none.
static func record(map: HexMap) -> Dictionary:
	return map.crypt if map != null else {}


## The tombs' kind in a set.
static func tomb_kind(set_name: String) -> String:
	return "%s_sarcophagus" % set_name


## The crypt's rooms take the crypt themes (see the header). After RoomThemes.assign.
static func theme(map: HexMap, run: ContractRun, p: SitePlan) -> void:
	last_usec = 0
	var rec := record(map)
	if rec.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var set_name := CryptCluster.set_for(run.site_type)
	var themes: Array = RoomThemeDefs.CRYPT[set_name]
	# the rooms by steps from the stair's foot over the crypt's own halls (ties: room order)
	var adj := {}
	for h: Dictionary in rec["halls"]:
		adj[str(h["a"])] = (adj.get(str(h["a"]), []) as Array) + [str(h["b"])]
		adj[str(h["b"])] = (adj.get(str(h["b"]), []) as Array) + [str(h["a"])]
	var foot := str((rec["stair"] as Dictionary).get("room", (rec["rooms"] as Array)[0]))
	var steps := {foot: 0}
	var queue: Array[String] = [foot]
	var qi := 0
	while qi < queue.size():
		var r: String = queue[qi]
		qi += 1
		var nbs: Array = adj.get(r, [])
		nbs.sort()
		for nb: String in nbs:
			if not steps.has(nb):
				steps[nb] = int(steps[r]) + 1
				queue.append(nb)
	var lit: Array[String] = []
	var dark: Array[String] = []
	for t: String in rec["rooms"]:
		if t == p.origin_room:
			continue   # (the story's room keeps its theme: its note and the dispatch name it)
		var is_lit := int(steps.get(t, 0)) % 2 == 0
		p.room_themes[t] = themes[0] if is_lit else themes[1]
		(lit if is_lit else dark).append(t)
	rec["set"] = set_name
	rec["lit"] = lit
	rec["dark"] = dark
	last_usec += Time.get_ticks_usec() - t0


## The sarcophagi (see the header): a row against a wall of each lit room, priced, on the crypt's own dice.
static func plan_tombs(map: HexMap, p: SitePlan, avoid: Dictionary, near_corr: Dictionary, ctx: ThemeCtx) -> void:
	var rec := record(map)
	if rec.is_empty() or not rec.has("lit"):
		return
	var t0 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = (int(rec["seed"]) * 211 + 17) & 0x7fffffff
	var keep := ctx.rng
	ctx.rng = rng   # (the crypt's dice for the poses: the floor's own ctx.rng draws as without it)
	var kind := tomb_kind(str(rec["set"]))
	var foot: Vector2 = PricedProp.placement(kind)["foot"]
	var radius := float(PricedProp.placement(kind)["radius"])
	var tombs: Array = []
	for tag: String in rec["lit"]:
		if not ctx.rooms.has(tag):
			continue
		var room: ThemeCtx.RoomInfo = ctx.rooms[tag]
		var want := 3 if room.cells.size() >= 110 else (2 if room.cells.size() >= 60 else 1)
		var anchors := SiteBuilder._edge_cells(map, p, tag, avoid, near_corr)
		var tries := 0
		for pose in RoomThemes.priced_poses(ctx, tag, kind, anchors):
			tries += 1
			if tries > TOMB_POSES or str(pose["place"]) != "wall":
				break
			var row := _row(ctx, room, pose, foot, want)
			for rp: Dictionary in row:
				ctx.commit_priced(room, kind, rp, foot, radius)
				p.props.append({"cell": rp["cell"], "kind": kind, "room": tag, "pos": rp["pos"], "yaw": rp["yaw"],
						"place": "wall", "orient": "away_from_wall", "foot": foot})
			if not row.is_empty():
				tombs.append(tag)
				break
	ctx.rng = keep
	rec["tombs"] = tombs
	last_usec += Time.get_ticks_usec() - t0


## A row from `pose`: it and up to want - 1 more along the same wall, TOMB_SPACING apart, each flush with the wall, on free
## floor and with its lane clear. [] when the first does not fit.
static func _row(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, pose: Dictionary, foot: Vector2, want: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n: Vector2 = pose["normal"]
	var anchor := ThemeGeo.world(pose["cell"])
	var lat := Vector2(-n.y, n.x)
	for k: int in [0, 1, -1, 2, -2]:
		if out.size() >= want:
			break
		var rp := pose if k == 0 else ctx.wall_pose_at(room, anchor + lat * (TOMB_SPACING * float(k)), n, foot.x, foot.y, 0.0)
		if rp.is_empty():
			if k == 0:
				return out
			continue
		var pos: Vector2 = rp["pos"]
		var yaw := float(rp["yaw"])
		var ok := ctx.fits(room, pos, yaw, foot.x, foot.y) and ctx.lane_ok(room, pos, yaw, foot.y) and ctx.wall_alignment(pos, yaw) >= ThemeCtx.MIN_ALIGN
		for o in out:
			ok = ok and not ThemeGeo.overlap(pos, yaw, foot.x, foot.y, o["pos"], float(o["yaw"]), foot.x, foot.y, ThemeCtx.TOL)
		if not ok:
			if k == 0:
				return out
			continue
		out.append({"pos": pos, "yaw": yaw, "cell": ThemeGeo.cell_of(pos)})
	return out


## Candles on the stair's landing, the flat step between its flights (see the header). After the decor.
static func dress(map: HexMap, p: SitePlan) -> void:
	var rec := record(map)
	if rec.is_empty() or not rec.has("set"):
		return
	var t0 := Time.get_ticks_usec()
	var st: Dictionary = rec["stair"]
	var route: Array = st.get("route", [])
	if route.size() >= 3:
		var top := map.get_cell(route[0]).level
		var bottom := map.get_cell(route[route.size() - 1]).level
		var best := -1
		for i in range(1, route.size() - 1):
			var cell := map.get_cell(route[i])
			if cell == null or cell.type != HexMap.Tile.FLOOR or cell.level >= maxi(top, bottom) or cell.level <= mini(top, bottom):
				continue
			if best < 0 or absi(i - route.size() / 2) < absi(best - route.size() / 2):
				best = i
		if best > 0:
			var c: Vector2i = route[best]
			var along := (ThemeGeo.world(route[best + 1]) - ThemeGeo.world(route[best - 1])).normalized()
			var lat := Vector2(-along.y, along.x)
			for side: float in [1.0, -1.0]:
				var at := ThemeGeo.world(c) + lat * (side * LANDING_SIDE)
				if map.wall_at(Vector3(at.x, 0.0, at.y)):
					continue
				SewerPlanner._decor(map, p, "crypt_candles", at, 0.0, {"set": str(rec["set"]), "count": 5, "radius": 0.3, "seed": 8,
						"light": 0.8}, float(map.get_cell(c).level) * Hex.LEVEL_HEIGHT)
				break
	last_usec += Time.get_ticks_usec() - t0


## The doorways of the crypt (Doorways.find): its rooms' and the stair's head in the room above, in doorway order.
static func doorways(map: HexMap, dws: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	var rec := record(map)
	if rec.is_empty():
		return out
	var rooms: Array = rec["rooms"]
	var st: Dictionary = rec["stair"]
	for dw in dws:
		if rooms.has(str(dw["room"])) or (str(dw["room"]) == str(st.get("from", "")) and (dw["door_cells"] as Array).has(st.get("door_up"))):
			out.append(int(dw["id"]))
	return out


## The arch or the gate across one of the crypt's doorways (see the header): decor on the doorway's line, its leaves swinging
## into the room.
static func gate(map: HexMap, p: SitePlan, dw: Dictionary) -> void:
	var rec := record(map)
	if rec.is_empty():
		return
	var room := str(dw["room"])
	var in_crypt := (rec["rooms"] as Array).has(room)
	var foot := in_crypt and str((rec["stair"] as Dictionary).get("room", "")) == room and _on_stair(map, rec, dw)
	var kind := "crypt_arch"
	var open := 0.0
	if foot:
		kind = "crypt_gate"
		open = FOOT_OPEN
	elif in_crypt and (rec.get("lit", []) as Array).has(room):
		kind = "crypt_gate"
		open = LIT_OPEN
	var mid: Vector3 = dw["mid"]
	var axis: Vector3 = dw["axis"]
	var width := float(dw.get("width", 3.0))
	width = clampf(width if width > 0.0 else 3.0, 3.0, 4.6)
	SewerPlanner._decor(map, p, kind, Vector2(mid.x, mid.z), SewerLayouts.yaw_to(Vector2(-axis.x, -axis.z)),
			{"set": str(rec.get("set", "vault")), "width": width, "open": open}, float(int(p.base_levels.get(room, 0))) * Hex.LEVEL_HEIGHT)


## After SiteBuilder.spawn (cosmetic, no actor added): every decor piece and priced prop standing on the crypt's underground
## floor (FloorMaterials.is_under) goes on HexMapView.UNDER_LAYER with the crypt's stone, so the key light leaves it too and
## the candles light it, as in the look test. The crew, the monsters and the staff keep the game's light.
static func spawn(map: HexMap, site: SiteBuilder.Site) -> void:
	if record(map).is_empty():
		return
	var nodes: Array[Node3D] = []
	for d in site.decor:
		if d is DecorProp:
			nodes.append(d)
	for pr in site.props:
		nodes.append(pr)
	for n in nodes:
		if not is_instance_valid(n):
			continue
		var cell := map.get_cell(Hex.from_world(n.global_position))
		if cell != null and FloorMaterials.is_under(cell.mat_id):
			for g in n.find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).layers = HexMapView.UNDER_LAYER


## Is this crypt doorway the stair's foot (its door cells hold the stair's door)?
static func _on_stair(_map: HexMap, rec: Dictionary, dw: Dictionary) -> bool:
	return (dw["door_cells"] as Array).has((rec["stair"] as Dictionary).get("door"))


## The crypt's halls and stair in the set's hall stone, and the walls only the crypt touches in its blocks (after
## FloorMaterials.assign; its rooms have their theme rows').
static func materials(map: HexMap, p: SitePlan) -> void:
	var rec := record(map)
	if rec.is_empty() or not rec.has("set"):
		return
	var t0 := Time.get_ticks_usec()
	var chapel := str(rec["set"]) == "chapel"
	var wall := FloorMaterials.W_CHAPEL if chapel else FloorMaterials.W_VAULT
	var room_mat := FloorMaterials.pack(FloorMaterials.F_CHAPEL if chapel else FloorMaterials.F_VAULT, wall)
	var hall_mat := FloorMaterials.pack(FloorMaterials.F_CHAPEL_HALL if chapel else FloorMaterials.F_VAULT_HALL, wall)
	var rooms := {}
	for t: String in rec["rooms"]:
		rooms[t] = true
	var mine := {}
	for c: Vector2i in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type != HexMap.Tile.WALL and rooms.has(cell.tag):
			mine[c] = true
	var halls: Array = (rec["halls"] as Array).duplicate()
	halls.append(rec["stair"])
	for h: Dictionary in halls:
		for c: Vector2i in (h.get("cells", []) as Array):
			var cell: HexMap.Cell = map.get_cell(c)
			if cell != null and cell.type != HexMap.Tile.WALL:
				cell.mat_id = hall_mat
				mine[c] = true
	for c: Vector2i in mine:
		for d in Hex.DIRS:
			var nb: Vector2i = c + d
			var cell: HexMap.Cell = map.get_cell(nb)
			if cell == null or cell.type != HexMap.Tile.WALL:
				continue
			var only_ours := true
			for d2 in Hex.DIRS:
				var o: HexMap.Cell = map.get_cell(nb + d2)
				if o != null and o.type != HexMap.Tile.WALL and not mine.has(nb + d2):
					only_ours = false
					break
			if only_ours:
				cell.mat_id = room_mat
	last_usec += Time.get_ticks_usec() - t0
