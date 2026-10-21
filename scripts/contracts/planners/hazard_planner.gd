class_name HazardPlanner
extends RefCounted
## The explosive props of a floor (ExplosiveProp, docs/design/hazards.md): plan() places them in the rooms whose theme
## has some (SitePlan.hazards) on dice of their own, spawn() puts them into the world. SiteBuilder.plan / spawn call them;
## moved out of SiteBuilder verbatim (refactor plan H8).


const MAX_HAZARDS := 3                 ## explosive props a floor (a pair counts two)
const HAZARD_PAIR_ODDS := 0.5           ## a hazard room gets a second one close by, so they chain
const HAZARD_PAIR_MIN := 2.0            ## world units between the two of a pair (centre to centre) ...
const HAZARD_PAIR_MAX := 3.2            ## ... and at most this: inside each other's blast
const HAZARD_GATE_CLEAR := 4            ## hex cells from a hellgate
const HAZARD_EMPLOYEE_CLEAR := 3        ## ... from an employee's spot
const HAZARD_PROP_CLEAR := 2            ## ... from a priced prop (still inside the blast: the money call)
const HAZARD_SPACING := 4               ## ... from another room's explosive
const HAZARD_ANCHORS := 14              ## wall cells of a room tried for its explosive (a random sample)


## Explosive props (ExplosiveProp, docs/design/hazards.md): in the rooms whose theme has some (RoomThemeDefs "hazards": the
## server room's battery pack, the lab's gas cylinders, the torture chamber's oil drum, ...), never in the start room, at most
## MAX_HAZARDS a floor, one a room, and in HAZARD_PAIR_ODDS of them a second one HAZARD_PAIR_MIN..MAX units away (inside its
## blast: they chain). Wall-backed like a priced prop (the same poses, bodies and lanes), on the same wall cells (out of the
## start / exit / elevator zones and the doors), HAZARD_GATE_CLEAR from a hellgate, HAZARD_EMPLOYEE_CLEAR from an employee,
## HAZARD_PROP_CLEAR from a priced prop and HAZARD_SPACING from the other rooms' ones. Its own dice: it moves nothing else on
## the floor (decor only steps around what it placed).
static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan, avoid: Dictionary, near_corr: Dictionary, ctx: ThemeCtx) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = run.floor_seed(floor_n) * 197 + floor_n * 23 + 9
	var tags: Array[String] = []
	for tag: String in p.rooms.keys():
		if tag != p.start_room and not RoomThemes.hazard_kinds(p.theme_of(tag)).is_empty():
			tags.append(tag)
	if tags.is_empty():
		return
	tags.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("room:")) < int(b.trim_prefix("room:")))
	ThemeVignettes.shuffle(tags, rng)
	var saved_rng := ctx.rng
	ctx.rng = rng   # (the poses draw from the hazards' own dice, so the decor after them rolls exactly as before)
	var gate_cells := p.gate_cells()
	for tag in tags:
		if p.hazards.size() >= MAX_HAZARDS:
			break
		var kinds := RoomThemes.hazard_kinds(p.theme_of(tag))
		var edge := SiteBuilder._edge_cells(map, p, tag, avoid, near_corr)
		if edge.is_empty():
			continue
		var kind := kinds[rng.randi_range(0, kinds.size() - 1)]
		# (a sample of the room's wall cells is plenty for one prop, and keeps the floor's planning time down)
		ThemeVignettes.shuffle(edge, rng)
		var first := _hazard_pose(ctx, p, tag, kind, edge.slice(0, HAZARD_ANCHORS), gate_cells, Vector2.INF)
		if first.is_empty():
			continue
		_commit_hazard(ctx, p, tag, kind, first)
		if p.hazards.size() < MAX_HAZARDS and rng.randf() < HAZARD_PAIR_ODDS:
			var kind2 := kinds[rng.randi_range(0, kinds.size() - 1)]
			var near: Array[Vector2i] = []
			for c in edge:
				var hd := Hex.distance(c, first["cell"])
				if hd >= 1 and hd <= 2:
					near.append(c)
			var second := _hazard_pose(ctx, p, tag, kind2, near, gate_cells, first["pos"])
			if not second.is_empty():
				_commit_hazard(ctx, p, tag, kind2, second)
	ctx.rng = saved_rng


## The best pose for an explosive of `kind` in room `tag` that keeps the clearances; with `near` (a pair's first one, X/Z)
## only a pose HAZARD_PAIR_MIN..MAX from it. {} when there is none.
static func _hazard_pose(ctx: ThemeCtx, p: SitePlan, tag: String, kind: String, edge: Array[Vector2i], gate_cells: Array[Vector2i], near: Vector2) -> Dictionary:
	for pose in RoomThemes.priced_poses(ctx, tag, kind, edge):
		var c: Vector2i = pose["cell"]
		var pos: Vector2 = pose["pos"]
		if near != Vector2.INF:
			var d := pos.distance_to(near)
			if d < HAZARD_PAIR_MIN or d > HAZARD_PAIR_MAX:
				continue
		var ok := true
		for g in gate_cells:
			if Hex.distance(g, c) < HAZARD_GATE_CLEAR:
				ok = false
		for e in p.employees:
			if Hex.distance(e["cell"], c) < HAZARD_EMPLOYEE_CLEAR:
				ok = false
		for pr in p.props:
			if Hex.distance(pr["cell"], c) < HAZARD_PROP_CLEAR:
				ok = false
		for hz in p.hazards:
			if str(hz["room"]) != tag and Hex.distance(hz["cell"], c) < HAZARD_SPACING:
				ok = false
		if ok:
			return pose
	return {}


static func _commit_hazard(ctx: ThemeCtx, p: SitePlan, tag: String, kind: String, pose: Dictionary) -> void:
	RoomThemes.commit_priced(ctx, tag, kind, pose)
	p.hazards.append({"cell": pose["cell"], "kind": kind, "room": tag, "pos": pose["pos"], "yaw": pose["yaw"],
			"place": pose["place"], "orient": pose["orient"], "foot": pose["foot"]})


## The planned explosives, in plan order.
static func spawn(run: ContractRun, p: SitePlan, site: SiteBuilder.Site) -> void:
	for hz in p.hazards:
		var hazard := PricedProp.spawn(hz["cell"], str(hz["kind"]), {"site": run.site_type, "pos": hz["pos"], "yaw": hz["yaw"]})
		if hazard != null:
			site.hazards.append(hazard)


# --- the sewer cluster's money calls (docs/design/sewer-concept.md, "Phase 3 as built") ------------------------------

const PANEL_REACH := 3.5               ## world units from a panel to where its cable lands in the water (LiveWire looks 3.5 ahead)
const PANEL_ANCHOR := 4                ## wall cells this close to the water may hold the panel or a pump
const SEWER_PUMPS := 2                 ## sump pumps in the pump room (the cluster's room farthest from its stair)
const SEWER_DRUM_ODDS := 0.6           ## an oil drum on a dry deck of the cluster


## A floor with a sewer cluster (SewerPlanner): the ELECTRICAL PANEL ($250) on a wall within PANEL_REACH of the water (its live
## wire, LiveWire: the cable drops into the water and shocks everyone in it within 5 cells; SewerPlanner.spawn attaches it), up
## to SEWER_PUMPS SUMP PUMPS ($3,500) on the pump room's walls by the water, and now and then an OIL DRUM on a dry deck (never
## on a wet or rim cell: ThemeCtx keeps to dry floor). Priced props go in SitePlan.props, the drum in SitePlan.hazards, after
## the floor's own. Own dice (the cluster's seed): nothing else on the floor moves. Nothing on a floor without a cluster.
static func plan_sewer(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan, avoid: Dictionary, near_corr: Dictionary, ctx: ThemeCtx) -> void:
	var rec := SewerPlanner.record(map)
	if rec.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rec["seed"]) * 197 + floor_n * 29 + 13
	var saved_rng := ctx.rng
	ctx.rng = rng
	var wet := {}
	for c: Vector2i in (map.pools[int(rec["body"])]["basin"] as Array):
		wet[c] = true
	var tags: Array[String] = []
	for t: String in rec["rooms"]:
		if ctx.rooms.has(t):
			tags.append(t)
	var stair_door: Vector2i = rec["stair"]["door"]
	var by_far := tags.duplicate()
	by_far.sort_custom(func(a: String, b: String) -> bool:
		var da := Hex.distance(p.centers[a], stair_door)
		var db := Hex.distance(p.centers[b], stair_door)
		return da > db or (da == db and int(a.trim_prefix("room:")) < int(b.trim_prefix("room:"))))
	var order := tags.duplicate()
	ThemeVignettes.shuffle(order, rng)
	# the panel: the first room (in a shuffled order) with a wall by the water to hang it on
	for tag: String in order:
		if _sewer_prop(map, p, ctx, tag, "electrical_panel", _by_water(map, p, tag, avoid, near_corr, wet), true):
			break
	# the pumps, in the pump room
	if not by_far.is_empty():
		for _i in SEWER_PUMPS:
			_sewer_prop(map, p, ctx, by_far[0], "sump_pump", _by_water(map, p, by_far[0], avoid, near_corr, wet), false)
	# the drum
	if rng.randf() < SEWER_DRUM_ODDS:
		for tag: String in order:
			var edge := SiteBuilder._edge_cells(map, p, tag, avoid, near_corr)
			ThemeVignettes.shuffle(edge, rng)
			var pose := _hazard_pose(ctx, p, tag, "oil_drum", edge.slice(0, HAZARD_ANCHORS), p.gate_cells(), Vector2.INF)
			if not pose.is_empty():
				_commit_hazard(ctx, p, tag, "oil_drum", pose)
				break
	ctx.rng = saved_rng


## A room's wall cells within PANEL_ANCHOR of the water.
static func _by_water(map: HexMap, p: SitePlan, tag: String, avoid: Dictionary, near_corr: Dictionary, wet: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in SiteBuilder._edge_cells(map, p, tag, avoid, near_corr):
		if _near_wet(c, wet, PANEL_ANCHOR):
			out.append(c)
	return out


static func _near_wet(c: Vector2i, wet: Dictionary, r: int) -> bool:
	for n in Hex.range_cells(c, r):
		if wet.has(n):
			return true
	return false


## Place one sewer priced prop of `kind` in room `tag` on one of `anchors` (the panel: only where its cable reaches the water),
## clear of the staff, the gates and the other props. True when placed.
static func _sewer_prop(map: HexMap, p: SitePlan, ctx: ThemeCtx, tag: String, kind: String, anchors: Array[Vector2i], panel: bool) -> bool:
	if anchors.is_empty():
		return false
	for pose in RoomThemes.priced_poses(ctx, tag, kind, anchors):
		var c: Vector2i = pose["cell"]
		var pos: Vector2 = pose["pos"]
		if map.water_at(Vector3(pos.x, 0.0, pos.y)):
			continue
		var ok := true
		for g in p.gate_cells():
			ok = ok and Hex.distance(g, c) >= HAZARD_GATE_CLEAR
		for e in p.employees:
			ok = ok and Hex.distance(e["cell"], c) >= HAZARD_EMPLOYEE_CLEAR
		for pr in p.props + p.hazards:
			ok = ok and Hex.distance(pr["cell"], c) >= HAZARD_PROP_CLEAR
		if not ok:
			continue
		if panel:
			var drop := LiveWire.drop_point_for(map, pos, ThemeGeo.facing(float(pose["yaw"])))
			if drop == Vector3.INF or pos.distance_to(Vector2(drop.x, drop.z)) > PANEL_REACH:
				continue
		RoomThemes.commit_priced(ctx, tag, kind, pose)
		p.props.append({"cell": c, "kind": kind, "room": tag, "pos": pos, "yaw": pose["yaw"], "place": pose["place"],
				"orient": pose["orient"], "foot": pose["foot"]})
		return true
	return false
