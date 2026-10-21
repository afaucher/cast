class_name EmployeePlanner
extends RefCounted
## The client's employees on a floor: plan() ranks the rooms farthest from the gates (SitePlan.ranked_rooms) and places the
## employees there with their names (SitePlan.employees), drawing from SiteBuilder.plan's shared rng; spawn() puts them into
## the world. The names are SiteBuilder.STAFF_NAMES / HENCHMAN_NAMES. SiteBuilder.plan / spawn call them; moved out of
## SiteBuilder verbatim (refactor plan H8).


static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan, rng: RandomNumberGenerator, avoid: Dictionary) -> void:
	var gate_cells := p.gate_cells()
	var scored: Array[Dictionary] = []
	for tag: String in p.rooms:
		if tag == p.start_room or tag == SiteBuilder.arrival_room(p):
			continue
		var d := 1 << 20
		for g in gate_cells:
			d = mini(d, Hex.distance(p.centers[tag], g))
		if gate_cells.is_empty():
			d = Hex.distance(p.centers[tag], p.start)
		scored.append({"tag": tag, "d": d})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["d"]) != int(b["d"]):
			return int(a["d"]) > int(b["d"])
		return int(str(a["tag"]).trim_prefix("room:")) < int(str(b["tag"]).trim_prefix("room:")))
	for s in scored:
		p.ranked_rooms.append(str(s["tag"]))
	if p.ranked_rooms.is_empty():
		return
	var count: int = run.floor_employees[floor_n - 1]
	var style := "staff" if run.site_type == "bunker" else "henchman"
	var pool: Array[String] = SiteBuilder.STAFF_NAMES.duplicate() if style == "staff" else SiteBuilder.HENCHMAN_NAMES.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := pool[i]
		pool[i] = pool[j]
		pool[j] = t
	var rooms_used := clampi((count + 1) / 2, 1, p.ranked_rooms.size())
	var taken: Array[Vector2i] = []
	for i in count:
		# The preferred room first, then the next-farthest rooms in order.
		var spot := SiteBuilder.NO_SPOT
		var tag := ""
		for k in p.ranked_rooms.size():
			tag = p.ranked_rooms[(i % rooms_used + k) % p.ranked_rooms.size()]
			spot = _employee_spot(map, p, tag, avoid, gate_cells, taken, rng)
			if spot != SiteBuilder.NO_SPOT:
				break
		if spot == SiteBuilder.NO_SPOT:
			continue
		taken.append(spot)
		p.employees.append({"cell": spot, "name": pool[i % pool.size()], "style": style, "room": tag})


static func _employee_spot(map: HexMap, p: SitePlan, tag: String, avoid: Dictionary, gate_cells: Array[Vector2i], taken: Array[Vector2i], rng: RandomNumberGenerator) -> Vector2i:
	var level: int = int(p.base_levels[tag])
	var cands: Array[Vector2i] = []
	for c in (p.rooms[tag] as Array[Vector2i]):
		var cell: HexMap.Cell = map.cells[c]
		if cell.type != HexMap.Tile.FLOOR or cell.level != level or avoid.has(c) or not map.is_walkable_cell(c) or cell.pool_mask != 0:
			continue
		var ok := true
		for g in gate_cells:
			if Hex.distance(g, c) < 4:
				ok = false
				break
		for t in taken:
			if Hex.distance(t, c) < 2:
				ok = false
				break
		if ok:
			cands.append(c)
	if cands.is_empty():
		return SiteBuilder.NO_SPOT
	return cands[rng.randi_range(0, cands.size() - 1)]


## The planned employees, in plan order.
static func spawn(p: SitePlan, site: SiteBuilder.Site) -> void:
	for e in p.employees:
		var emp := Employee.spawn(e["cell"], {"style": str(e["style"]), "name": str(e["name"])})
		if emp != null:
			site.employees.append(emp)
