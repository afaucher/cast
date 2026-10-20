class_name ScoutPlanner
extends RefCounted
## The goblin scouts of a floor (monster awareness step 2, docs/design/goblin-scout.md §5): plan() routes them along the
## corridors (SitePlan.scouts) and spawn() puts them into the world. How many a floor gets is SiteBuilder.scout_count.
## SiteBuilder.plan / spawn call them; moved out of SiteBuilder verbatim (refactor plan H8).


const SCOUT_MIN_CELLS := 9              ## a scout's corridor route is longer than 8 cells
const SCOUT_WAYPOINT_EVERY := 3         ## a waypoint every this many cells along the route


## Routes from the corridors: each connected run of "corridor" cells is one link; its doors are its cells beside a
## room. A route goes doorway to doorway inside the link (the lane the generator carved), longer than 8 cells, never
## touching the start or arrival room; links whose two rooms both hold a pack come first. Several scouts take different
## links. Rolled on a generator of its own, seeded from the floor, so nothing else in the plan moves.
static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = run.floor_seed(floor_n) * 7919 + floor_n * 101 + 11
	var arrival := SiteBuilder.arrival_room(p)
	var seen := {}
	var cands: Array = []
	var cells: Array = map.cells.keys()
	cells.sort_custom(SiteBuilder._cell_less)
	for c0: Vector2i in cells:
		if seen.has(c0) or map.get_cell(c0).tag != "corridor" or map.get_cell(c0).type == HexMap.Tile.WALL:
			continue
		# One link: the corridor cells joined to c0.
		var comp: Array[Vector2i] = []
		var q: Array[Vector2i] = [c0]
		seen[c0] = true
		var qi := 0
		while qi < q.size():
			var c := q[qi]
			qi += 1
			comp.append(c)
			for nb in Hex.neighbors(c):
				var nc := map.get_cell(nb)
				if nc != null and not seen.has(nb) and nc.tag == "corridor" and nc.type != HexMap.Tile.WALL:
					seen[nb] = true
					q.append(nb)
		# Its doors: per room, the walkable link cell beside the room nearest that room's centre.
		var doors := {}
		for c in comp:
			if not map.is_walkable_cell(c):
				continue
			for nb in Hex.neighbors(c):
				var nc := map.get_cell(nb)
				if nc == null or not nc.tag.begins_with("room:") or not p.centers.has(nc.tag):
					continue
				var d := Hex.distance(c, p.centers[nc.tag])
				if not doors.has(nc.tag) or d < int((doors[nc.tag] as Array)[1]):
					doors[nc.tag] = [c, d]
		var tags: Array = doors.keys()
		if tags.size() < 2:
			continue
		tags.sort()
		var a: String = tags[0]
		var b: String = tags[1]
		if a == p.start_room or b == p.start_room or a == arrival or b == arrival:
			continue
		var path := _link_path(map, comp, (doors[a] as Array)[0], (doors[b] as Array)[0])
		if path.size() < SCOUT_MIN_CELLS:
			continue
		var score := (1 if p.pack_budgets.has(a) else 0) + (1 if p.pack_budgets.has(b) else 0)
		cands.append({"path": path, "rooms": [a, b], "score": score})
	# Best links first, ties in a seeded order.
	for i in range(cands.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = cands[i]
		cands[i] = cands[j]
		cands[j] = t
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["score"]) > int(y["score"]))
	var want := SiteBuilder.scout_count(run, floor_n)
	for cand: Dictionary in cands:
		if p.scouts.size() >= want:
			break
		var path: Array[Vector2i] = cand["path"]
		var route: Array[Vector2i] = []
		for i in path.size():
			if i % SCOUT_WAYPOINT_EVERY == 0 or i == path.size() - 1:
				route.append(path[i])
		var rooms: Array = cand["rooms"]
		var looks: Array[Vector2] = []
		for k in 2:
			var door := Hex.to_world(path[0] if k == 0 else path[path.size() - 1])
			var centre := Hex.to_world(p.centers[rooms[k]])
			var dir := Vector2(centre.x - door.x, centre.z - door.z)
			looks.append(dir.normalized() if dir.length() > 0.01 else Vector2(0, -1))
		p.scouts.append({"route": route, "looks": looks, "rooms": rooms, "start": rng.randi_range(0, route.size() - 1)})


## The shortest walkable path from `a` to `b` inside one corridor link (breadth first; goblins climb).
static func _link_path(map: HexMap, comp: Array[Vector2i], a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var inside := {}
	for c in comp:
		if map.is_walkable_cell(c):
			inside[c] = true
	var prev := {a: a}
	var q: Array[Vector2i] = [a]
	var qi := 0
	while qi < q.size():
		var c := q[qi]
		qi += 1
		if c == b:
			break
		for nb in Hex.neighbors(c):
			if not inside.has(nb) or prev.has(nb):
				continue
			var mv := map.cell_transition(c, nb)
			if mv != HexMap.Move.OK and mv != HexMap.Move.CLIMB:
				continue
			prev[nb] = c
			q.append(nb)
	var out: Array[Vector2i] = []
	if not prev.has(b):
		return out
	var c := b
	while c != a:
		out.push_front(c)
		c = prev[c]
	out.push_front(a)
	return out


static func spawn(map: HexMap, p: SitePlan, site: SiteBuilder.Site) -> void:
	for sc: Dictionary in p.scouts:
		var route: Array[Vector2i] = sc["route"]
		if route.is_empty():
			continue
		var pts: Array[Vector3] = []
		for c in route:
			pts.append(Hex.to_world(c, float(map.get_cell(c).level)))
		var looks: Array[Vector3] = []
		for v: Vector2 in (sc["looks"] as Array):
			looks.append(Vector3(v.x, 0.0, v.y))
		var start: int = sc["start"]
		var g := MonsterFactory.spawn("goblin", route[start])
		if g == null:
			continue
		g.call("set_route", pts, looks, start)
		var next := pts[mini(start + 1, pts.size() - 1)] if start < pts.size() - 1 else pts[maxi(start - 1, 0)]
		var to := next - g.global_position
		to.y = 0.0
		if to.length() > 0.1:
			g.set_spawn_facing(to.normalized())
		site.scouts.append(g)
