class_name PropPlanner
extends RefCounted
## The priced props of a floor (PricedProp): plan() places at most MAX_PROPS, the kinds picked by the rooms' themes, back
## to the wall (SitePlan.props), drawing from SiteBuilder.plan's shared rng; spawn() puts them into the world.
## SiteBuilder.plan / spawn call them; moved out of SiteBuilder verbatim (refactor plan H8).
##
## The hallway SET PIECES (docs/design/hallways.md; the user, 2026-10-26: "For 3 lets think which will give the most impact
## with the fewest props. Lets not just spam to have something." and "Build landings and set pieces only, no hall
## explosives."): plan_set_pieces() gives each LANDING of the floor (HexMap.landings, DungeonGen) exactly one priced prop, a
## tall landmark of the site's catalog (LANDING_KINDS, cycled from a seeded start so a floor shows several), standing flush
## against the landing's back wall facing the hall (ThemeCtx's wall pose), its whole footprint on the cells the landing
## added: the hall's own width stays clear for the crew and a monster pack. Own dice (from the floor seed), so nothing else
## on the floor moves; SitePlan.set_pieces. spawn_set_pieces() spawns them after every other actor (no earlier net id
## moves), as ordinary PricedProps (host-arbitrated world objects, in Site.props).


const PROP_SPACING := 4
const MAX_PROPS := 6
## A landing's set piece, by site (the catalog's tall pieces, readable from the hall's ends), in the order they are dealt.
const LANDING_KINDS := {
	"bunker": ["marble_statue", "crystal_lamp", "zen_fountain"],
	"lair": ["evil_portrait", "brazier", "henchman_locker"],
}
const SET_PIECE_REACH := 3.5   ## the wall pose's march starts this far from the landing's centre toward its back side


static func plan(map: HexMap, run: ContractRun, p: SitePlan, rng: RandomNumberGenerator, avoid: Dictionary, near_corr: Dictionary, catalog: Array[String], ctx: ThemeCtx) -> void:
	if catalog.is_empty():
		return
	var gate_cells := p.gate_cells()
	var taken: Array[Vector2i] = []
	for e in p.employees:
		taken.append(e["cell"])
	var tags: Array = p.rooms.keys()
	tags.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("room:")) < int(b.trim_prefix("room:")))
	# Edge cells per room: next to a wall, flat, out of the corridors' way.
	var edges: Dictionary = {}
	var order: Array[String] = []
	for tag: String in tags:
		if tag == p.start_room:
			continue
		edges[tag] = SiteBuilder._edge_cells(map, p, tag, avoid, near_corr)
		order.append(tag)
	# A shuffled room order, so the first rooms do not hog the few props a floor gets.
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := order[i]
		order[i] = order[j]
		order[j] = t
	var placed: Dictionary = {}
	var round_n := 0
	while p.props.size() < MAX_PROPS and round_n < 3:
		round_n += 1
		for tag in order:
			if p.props.size() >= MAX_PROPS:
				break
			var want := clampi((p.rooms[tag] as Array).size() / 40, 1, 3)
			var edge: Array[Vector2i] = edges[tag]
			if int(placed.get(tag, 0)) >= want or edge.is_empty():
				continue
			# The theme picks the kind (a wine rack in the cellar, the projector in the cinema ...); a room
			# whose theme has none in this catalog takes any kind of the site.
			var themed := RoomThemes.priced_kinds(str(p.room_themes.get(tag, "")), catalog)
			var kinds: Array[String] = []
			var n_placed := int(placed.get(tag, 0))
			if themed.is_empty():
				kinds = catalog.duplicate()
				for i in range(kinds.size() - 1, 0, -1):
					var j := rng.randi_range(0, i)
					var t := kinds[i]
					kinds[i] = kinds[j]
					kinds[j] = t
			else:
				# the theme's first choice half the time, any of its props otherwise
				var first := 0 if rng.randf() < 0.5 else rng.randi_range(0, themed.size() - 1)
				for i in themed.size():
					kinds.append(themed[(n_placed + first + i) % themed.size()])
			var done := false
			for kind in kinds:
				for pose in RoomThemes.priced_poses(ctx, tag, kind, edge):
					var c: Vector2i = pose["cell"]
					var ok := true
					for g in gate_cells:
						if Hex.distance(g, c) < 4:
							ok = false
							break
					if ok:
						for t in taken:
							if Hex.distance(t, c) < PROP_SPACING:
								ok = false
								break
					if not ok:
						continue
					taken.append(c)
					placed[tag] = n_placed + 1
					RoomThemes.commit_priced(ctx, tag, kind, pose)
					p.props.append({"cell": c, "kind": kind, "room": tag, "pos": pose["pos"], "yaw": pose["yaw"],
							"place": pose["place"], "orient": pose["orient"], "foot": pose["foot"]})
					done = true
					break
				if done:
					break


## The landings' set pieces (see the header): one per landing, against its back wall. `catalog` is the site's kinds.
static func plan_set_pieces(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan, catalog: Array[String], ctx: ThemeCtx) -> void:
	if map.landings.is_empty():
		return
	var kinds: Array[String] = []
	for k: String in (LANDING_KINDS.get(run.site_type, []) as Array):
		if catalog.has(k):
			kinds.append(k)
	if kinds.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = run.floor_seed(floor_n) * 389 + floor_n * 29 + 7
	var first := rng.randi_range(0, kinds.size() - 1)
	for li in map.landings.size():
		var lr: Dictionary = map.landings[li]
		var room := landing_room(map, lr, li)
		for j in kinds.size():
			var kind := kinds[(first + li + j) % kinds.size()]
			var pose := landing_pose(map, lr, room, kind, ctx)
			if pose.is_empty():
				continue
			var pl := PricedProp.placement(kind)
			p.set_pieces.append({"cell": pose["cell"], "kind": kind, "room": "", "landing": li, "pos": pose["pos"],
					"yaw": pose["yaw"], "place": "wall", "orient": "away_from_wall", "foot": pl["foot"], "back": pose["back"]})
			break


## A landing as a ThemeCtx room for the wall pose: its hexagon's floor at its level.
static func landing_room(map: HexMap, lr: Dictionary, li: int) -> ThemeCtx.RoomInfo:
	var r := ThemeCtx.RoomInfo.new()
	r.tag = "landing:%d" % li
	r.index = li
	r.base = int(lr["level"])
	r.center = lr["hub"]
	r.center_w = ThemeGeo.world(r.center)
	for c in Hex.range_cells(r.center, DungeonGen.LANDING_R + 1):
		var cell := map.get_cell(c)
		if cell != null and cell.type == HexMap.Tile.FLOOR and cell.level == r.base:
			r.cells.append(c)
			r.open[c] = true
	return r


## Where a `kind` stands on landing `lr`: flush against the first of its backs where it fits, facing the hall, every
## footprint point on a cell the landing added (off the hall's own width) and off the wall side. {pos, yaw, cell, back} or {}.
static func landing_pose(map: HexMap, lr: Dictionary, room: ThemeCtx.RoomInfo, kind: String, ctx: ThemeCtx) -> Dictionary:
	var foot: Vector2 = PricedProp.placement(kind)["foot"]
	var added := {}
	for c: Vector2i in (lr["cells"] as Array):
		added[c] = true
	var center: Vector2i = lr["hub"]
	var cw := ThemeGeo.world(center)
	for k: int in (lr["backs"] as Array):
		var bc: Vector2i = center + Hex.DIRS[k] + Hex.DIRS[(k + 1) % 6]
		var n := (ThemeGeo.world(bc) - cw).normalized()
		var pose := ctx.wall_pose_at(room, cw + n * SET_PIECE_REACH, n, foot.x, foot.y, 0.0)
		if pose.is_empty():
			continue
		var pos: Vector2 = pose["pos"]
		var yaw := float(pose["yaw"])
		if not ctx.rect_clear(pos, yaw, foot.x, foot.y):
			continue
		var ok := true
		for fp in ThemeGeo.foot_points(pos, yaw, foot.x, foot.y):
			if map.wall_at(Vector3(fp.x, 0.0, fp.y)) or not added.has(ThemeGeo.cell_of(fp)):
				ok = false
				break
		if ok:
			return {"pos": pos, "yaw": yaw, "cell": ThemeGeo.cell_of(pos), "back": k}
	return {}


## The planned priced props, in plan order.
static func spawn(run: ContractRun, p: SitePlan, site: SiteBuilder.Site) -> void:
	for pr in p.props:
		var opts := {"site": run.site_type}
		if pr.has("pos"):
			opts["pos"] = pr["pos"]     # back to the wall, facing into the room
			opts["yaw"] = pr["yaw"]
		var prop := PricedProp.spawn(pr["cell"], str(pr["kind"]), opts)
		if prop != null:
			site.props.append(prop)


## The landings' set pieces, in plan order: ordinary priced props (into Site.props), spawned after every other actor
## (SiteBuilder.spawn), so no earlier net id moves.
static func spawn_set_pieces(run: ContractRun, p: SitePlan, site: SiteBuilder.Site) -> void:
	for sp in p.set_pieces:
		var prop := PricedProp.spawn(sp["cell"], str(sp["kind"]), {"site": run.site_type, "pos": sp["pos"], "yaw": sp["yaw"]})
		if prop != null:
			site.props.append(prop)
