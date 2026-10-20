class_name PropPlanner
extends RefCounted
## The priced props of a floor (PricedProp): plan() places at most MAX_PROPS, the kinds picked by the rooms' themes, back
## to the wall (SitePlan.props), drawing from SiteBuilder.plan's shared rng; spawn() puts them into the world.
## SiteBuilder.plan / spawn call them; moved out of SiteBuilder verbatim (refactor plan H8).


const PROP_SPACING := 4
const MAX_PROPS := 6


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
