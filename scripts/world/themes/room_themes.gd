class_name RoomThemes
extends RefCounted
## Room themes for a generated floor (docs/design/environment.md): every room gets a theme from the site's
## pool (bunker: wine cellar, home cinema, spa, gym, server room, panic room, indoor pool; lair: torture
## chamber, throne room, lab, barracks, shark moat, science); the start room is the SERVICE ENTRANCE; on the origin
## floor the ORIGIN room gets the theme the story names (RoomThemeDefs.ORIGIN_THEMES). The theme picks the
## room's priced props (placed wall-backed / in corners, facing into the room) and its decor (vignettes
## placed as one unit, see ThemeVignettes), and one accent light.
##
## Pure data, deterministic per (floor seed, story): SiteBuilder.plan() calls assign() once rooms are
## indexed, place_priced() from its prop loop, and plan_decor() once everything else is placed.
## The result lives on the SitePlan: room_themes (room tag -> theme id), decor, lights, entrances.

const JITTER := ThemeGeo.JITTER
## How much a priced kind wants to face the camera (default 1.0): the projector wants the near wall, facing the screen.
const CAMERA_PREF := {"projector": -2.0}


## Deal a theme to every room: plan.room_themes[tag] = theme id.
static func assign(plan: SitePlan, site_type: String, story: Dictionary, floor_n: int, seed_value: int) -> void:
	plan.room_themes = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 977 + floor_n * 31 + 11
	var rest: Array[String] = []
	var tags: Array = plan.rooms.keys()
	tags.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("room:")) < int(b.trim_prefix("room:")))
	for tag: String in tags:
		if tag == plan.start_room:
			plan.room_themes[tag] = RoomThemeDefs.SERVICE
		else:
			rest.append(tag)
	var origin_theme := ""
	if floor_n == int(story.get("origin_floor", ContractRun.FLOOR_COUNT)) and plan.origin_room != "" and rest.has(plan.origin_room):
		origin_theme = RoomThemeDefs.origin_theme(site_type, str(story.get("origin", "")))
		plan.room_themes[plan.origin_room] = origin_theme
		rest.erase(plan.origin_room)
	var pool := RoomThemeDefs.pool(site_type)
	# the exit room (the elevator sits in its middle) and the rooms with a hellgate cannot host a centrepiece theme
	var crowded := {plan.exit_room: true}
	for g in plan.gates:
		crowded[str(g["room"])] = true
	var bag: Array[String] = []
	var cycle := 0
	while not rest.is_empty():
		if bag.is_empty():
			bag = pool.duplicate()
			if cycle == 0 and origin_theme != "":
				bag.erase(origin_theme)
			ThemeVignettes.shuffle(bag, rng)
			cycle += 1
		var theme: String = bag.pop_back()
		var need := int((RoomThemeDefs.THEMES[theme] as Dictionary)["min_cells"])
		# the smallest room that is big enough keeps the big rooms for the themes that need them
		var by_size := rest.duplicate()
		by_size.sort_custom(func(a: String, b: String) -> bool:
			var na: int = (plan.rooms[a] as Array).size()
			var nb: int = (plan.rooms[b] as Array).size()
			return na < nb or (na == nb and int(a.trim_prefix("room:")) < int(b.trim_prefix("room:"))))
		var needs_center := bool((RoomThemeDefs.THEMES[theme] as Dictionary).get("needs_center", false))
		var avoid_exit := bool((RoomThemeDefs.THEMES[theme] as Dictionary).get("avoid_exit", false))
		var pick: String = by_size[by_size.size() - 1]
		var found := false
		for tag in by_size:
			if (plan.rooms[tag] as Array).size() >= need and not (needs_center and crowded.has(tag)) and not (avoid_exit and tag == plan.exit_room):
				pick = tag
				found = true
				break
		if not found:
			for tag in by_size:
				if (plan.rooms[tag] as Array).size() >= need:
					pick = tag
					break
		plan.room_themes[pick] = theme
		rest.erase(pick)


## The priced kinds this theme prefers that the site's catalog offers, in preference order.
static func priced_kinds(theme: String, catalog: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for k: String in (RoomThemeDefs.theme(theme).get("priced", []) as Array):
		if catalog.has(k):
			out.append(k)
	return out


## The explosive props (ExplosiveProp) this theme may hold, in preference order (empty: none fit the room).
static func hazard_kinds(theme: String) -> Array[String]:
	var out: Array[String] = []
	for k: String in (RoomThemeDefs.theme(theme).get("hazards", []) as Array):
		if PricedProp.is_hazard(k):
			out.append(k)
	return out


## Valid poses for a priced prop on the given anchor cells (wall-adjacent flat floor), best first. Corner kinds
## try a concave corner first; everything else is wall-backed. Each pose is
## {cell, pos, yaw, place, orient, normal, foot, radius}.
static func priced_poses(ctx: ThemeCtx, tag: String, kind: String, anchors: Array[Vector2i]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var room: ThemeCtx.RoomInfo = ctx.rooms[tag]
	var meta := PricedProp.placement(kind)
	var foot: Vector2 = meta["foot"]
	var want_corner := String(meta["place"]) == "corner"
	var order: Array[Vector2i] = anchors.duplicate()
	ThemeVignettes.shuffle(order, ctx.rng)
	for c in order:
		if not ctx.cell_free(room, c):
			continue
		var j := ctx.rng.randf_range(-JITTER, JITTER)
		var place := "corner"
		var pose: Dictionary = {}
		if want_corner:
			pose = ctx.corner_pose(room, c, foot.x, foot.y, j)
		if pose.is_empty():
			place = "wall"
			pose = ctx.wall_pose(room, c, foot.x, foot.y, j)
		if pose.is_empty():
			continue
		var pos: Vector2 = pose["pos"]
		var yaw: float = pose["yaw"]
		if place == "wall" and ctx.wall_alignment(pos, yaw) < ThemeCtx.MIN_ALIGN:
			continue
		if not ctx.fits(room, pos, yaw, foot.x, foot.y) or not ctx.lane_ok(room, pos, yaw, foot.y):
			continue
		pose["cell"] = c
		pose["place"] = place
		pose["orient"] = String(meta["orient"]) if place == String(meta["place"]) else "away_from_wall"
		pose["foot"] = foot
		pose["radius"] = float(meta["radius"])
		pose["score"] = _priced_score(ctx, room, String(meta["orient"]), pos, yaw) + float(CAMERA_PREF.get(kind, 1.0)) * ThemeGeo.facing(yaw).dot(ThemeGeo.CAMERA_DIR) + ctx.rng.randf() * 0.7
		out.append(pose)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	return out


static func _priced_score(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, orient: String, pos: Vector2, yaw: float) -> float:
	var f := ThemeGeo.facing(yaw)
	match orient:
		"face_entrance":
			var to_door := room.entrance_w - pos
			return f.dot(to_door.normalized()) * 2.0 + minf(pos.distance_to(room.entrance_w), 12.0) * 0.15
	return 0.0


## Record a priced prop's pose in the context (so decor leaves it its lane).
static func commit_priced(ctx: ThemeCtx, tag: String, kind: String, pose: Dictionary) -> void:
	ctx.commit_priced(ctx.rooms[tag], kind, pose, pose["foot"], float(pose["radius"]))


## Dress every room: run each theme's recipe (while the room's decor budget lasts) and plan its accent light.
## Fills plan.decor, plan.lights, plan.entrances.
static func plan_decor(ctx: ThemeCtx) -> void:
	var plan := ctx.plan
	plan.decor.clear()
	plan.lights.clear()
	plan.entrances.clear()
	for nt in plan.notes:
		var nr := ctx.room_of(nt["cell"])
		if nr != null:
			ctx.add_body(nr, ThemeGeo.world(nt["cell"]), 0.0, 0.9, 1.1, -1, "note")
	for tag: String in ctx.rooms:
		var room: ThemeCtx.RoomInfo = ctx.rooms[tag]
		room.theme = String(plan.room_themes.get(tag, ""))
		plan.entrances[tag] = room.entrance_w
		var def := RoomThemeDefs.theme(room.theme)
		if def.is_empty():
			continue
		for op: Dictionary in (def["recipe"] as Array):
			if room.used >= room.budget:
				break
			var skipped := room.cells.size() < int(op.get("min_cells", 0))
			var ok := false if skipped else ThemeVignettes.run(ctx, room, op)
			plan.decor_report.append({"room": tag, "theme": room.theme, "op": String(op["op"]), "ok": ok, "skipped": skipped})
		var light := _light_for(room, def)
		if not light.is_empty():
			plan.lights.append(light)
	for it in ctx.all_items():
		plan.decor.append(it)


static func _light_for(room: ThemeCtx.RoomInfo, def: Dictionary) -> Dictionary:
	var l: Dictionary = def.get("light", {})
	if l.is_empty():
		return {}
	var p := room.center_w
	return {
		"room": room.tag, "theme": room.theme, "pos": Vector3(p.x, float(room.base) * Hex.LEVEL_HEIGHT + 2.7, p.y),
		"color": l["color"], "energy": float(l["energy"]), "range": float(l["range"]),
		"flicker": float(l.get("flicker", 0.0)), "pulse": float(l.get("pulse", 0.0)),
	}


## Unit facing vector of a placement (works for decor and priced entries alike).
static func facing_of(entry: Dictionary) -> Vector2:
	return ThemeGeo.facing(float(entry["yaw"]))
