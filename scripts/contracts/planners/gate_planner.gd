class_name GatePlanner
extends RefCounted
## The hellgates of a floor: plan() places them (SitePlan.gates and, on the last floor, the origin room), drawing from
## SiteBuilder.plan's shared rng; spawn() puts the gates, and the monster under each gate's room, into the world.
## SiteBuilder.plan / spawn call them; moved out of SiteBuilder verbatim (refactor plan H8).


const GATE_START_CLEAR := 5


static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan, rng: RandomNumberGenerator, avoid: Dictionary, near_corr: Dictionary) -> void:
	var cand: Array[String] = []
	for tag: String in p.rooms:
		if tag != p.start_room and tag != p.exit_room:
			cand.append(tag)
	if cand.is_empty():
		for tag: String in p.rooms:
			if tag != p.start_room:
				cand.append(tag)
	if floor_n >= ContractRun.FLOOR_COUNT:
		# The origin gate: the biggest eligible room (ties: farthest from the start); a room with no room
		# for it is skipped for the next biggest.
		var by_size: Array[String] = cand.duplicate()
		by_size.sort_custom(func(a: String, b: String) -> bool:
			var na: int = (p.rooms[a] as Array).size()
			var nb: int = (p.rooms[b] as Array).size()
			if na != nb:
				return na > nb
			var da := Hex.distance(p.centers[a], p.start)
			var db := Hex.distance(p.centers[b], p.start)
			return da > db or (da == db and int(a.trim_prefix("room:")) < int(b.trim_prefix("room:"))))
		var spot := SiteBuilder.NO_SPOT
		var pick := ""
		for radius in [2, 1, 0]:
			for tag in by_size:
				spot = _gate_spot(map, p, tag, radius, avoid, near_corr, [])
				if spot != SiteBuilder.NO_SPOT:
					pick = tag
					break
			if spot != SiteBuilder.NO_SPOT and (radius < 2 or pick == by_size[0]):
				break
		p.origin_room = pick
		if spot != SiteBuilder.NO_SPOT:
			p.gates.append({"cell": spot, "origin": true, "room": pick})
		return
	var count: int = run.floor_gates[floor_n - 1]
	var chosen: Array[String] = []
	var taken: Array[Vector2i] = []
	var first_pick := rng.randi_range(0, maxi(0, cand.size() - 1))
	for i in count:
		# Rooms in order of preference: the first gate goes to a random room, each next one to the room
		# farthest from the gates already placed (a room repeats only once all are used).
		var ordered: Array[String] = cand.duplicate()
		if chosen.is_empty():
			ordered = ordered.slice(first_pick) + ordered.slice(0, first_pick)
		else:
			var score: Dictionary = {}
			for tag in cand:
				var nearest := 1 << 20
				for ch in chosen:
					nearest = mini(nearest, Hex.distance(p.centers[tag], p.centers[ch]))
				score[tag] = nearest - (1000 if chosen.has(tag) else 0)
			ordered.sort_custom(func(a: String, b: String) -> bool:
				return int(score[a]) > int(score[b]) or (int(score[a]) == int(score[b]) and int(a.trim_prefix("room:")) < int(b.trim_prefix("room:"))))
		var spot := SiteBuilder.NO_SPOT
		var pick := ""
		for radius in [1, 0]:
			for tag in ordered:
				spot = _gate_spot(map, p, tag, radius, avoid, near_corr, taken)
				if spot != SiteBuilder.NO_SPOT:
					pick = tag
					break
			if spot != SiteBuilder.NO_SPOT:
				break
		if spot == SiteBuilder.NO_SPOT:
			continue
		chosen.append(pick)
		taken.append(spot)
		p.gates.append({"cell": spot, "origin": false, "room": pick})


## The flat spot nearest the room centre that keeps clear of the start/exit, corridors and `taken` gates.
static func _gate_spot(map: HexMap, p: SitePlan, tag: String, radius: int, avoid: Dictionary, near_corr: Dictionary, taken: Array) -> Vector2i:
	var center: Vector2i = p.centers[tag]
	var cells: Array[Vector2i] = (p.rooms[tag] as Array[Vector2i]).duplicate()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := Hex.distance(a, center)
		var db := Hex.distance(b, center)
		return da < db or (da == db and SiteBuilder._cell_less(a, b)))
	for strict in [true, false]:
		for c in cells:
			if not SiteBuilder._flat_spot(map, p, tag, c, radius):
				continue
			if avoid.has(c) or Hex.distance(c, p.start) < GATE_START_CLEAR:
				continue
			if strict and near_corr.has(c):
				continue
			var ok := true
			for t: Vector2i in taken:
				if Hex.distance(t, c) < 5:
					ok = false
					break
			if ok:
				return c
	return SiteBuilder.NO_SPOT


## The planned gates, in plan order, each with the monster under its room.
static func spawn(map: HexMap, run: ContractRun, p: SitePlan, site: SiteBuilder.Site) -> void:
	var gate_pest := "" if run.pest == "everything" else run.pest
	for g in p.gates:
		var gate := Hellgate.spawn(g["cell"], {"difficulty": run.difficulty, "depth": p.floor_number, "origin": bool(g["origin"]), "pest": gate_pest})
		if gate == null:
			continue
		site.gates.append(gate)
		if bool(g["origin"]):
			site.origin_gate = gate
		# the monster under the level round the gate's room (cosmetic: every machine builds it from the seed; it sinks away
		# when its gate closes)
		var beast := HellgateBeast.for_gate(gate, map, p, run.floor_seed(p.floor_number))
		if beast != null:
			site.beasts.append(beast)
