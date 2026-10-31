class_name ProcessionPlanner
extends RefCounted
## A haunted floor's processions (docs/design/haunted-build-plan.md, "H4 as built"): plan() picks each one's route, a loop of
## ROUTE_ROOMS rooms (SitePlan.processions), and spawn() puts the procession on the floor: an acolyte at the head, Procession.FILE
## zombies GAP apart behind it along the way it came, a second acolyte at the rear (the look test's formation), and the
## Procession that walks them (the host's). How many a floor gets is the contract's (ContractRun.floor_processions: floor 1 one,
## floor 2 one or two, none on the last floor or on a hellgate contract). SiteBuilder.plan / spawn call them.
##
## THE ROUTE (no dice but its own): the rooms it may use are every room but the start, arrival and exit rooms and a crypt's
## (its stair is the crypt's one way in), with a walkable spot near the centre. The first procession starts in the room
## farthest from where the crew arrives, a second in the room farthest from both; each walks on to the nearest room it can
## reach not yet on its route, and back round. Its spawn: on its way, the leader the file's length along its first leg (the
## first room's spot to the second's) and the file in line behind it back to the first spot, so it walks on from the start (no
## turn back through its own file).

const ROUTE_ROOMS := 3              ## rooms in a route (fewer when the floor has fewer it may use; at least 2)
const PATH_NODES := 6000            ## the path finder's budget between two rooms' spots


static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan) -> void:
	var want := run.floor_processions[floor_n - 1] if floor_n >= 1 and floor_n <= run.floor_processions.size() else 0
	if want <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = run.floor_seed(floor_n) * 6151 + floor_n * 37 + 19
	var skip := {p.start_room: true, p.exit_room: true, SiteBuilder.arrival_room(p): true}
	var crypt := CryptPlanner.record(map)
	for tag: Variant in (crypt.get("rooms", []) as Array):
		skip[str(tag)] = true
	var spots := {}
	for tag: String in SiteBuilder._room_tags(p):
		if skip.has(tag):
			continue
		var c := _spot(map, p, tag)
		if c != SiteBuilder.NO_SPOT:
			spots[tag] = c
	var tags: Array[String] = []
	for tag: String in spots:
		tags.append(tag)
	for i in range(tags.size() - 1, 0, -1):   # (ties in a seeded order)
		var j := rng.randi_range(0, i)
		var t := tags[i]
		tags[i] = tags[j]
		tags[j] = t
	if tags.size() < 2:
		return
	var arrival: Vector2i = p.centers.get(SiteBuilder.arrival_room(p), p.start)
	var starts: Array[Vector2i] = [arrival]
	var used_starts := {}
	for _n in want:
		# the start: the room whose spot is farthest from the crew's arrival and the other processions' starts
		var best := ""
		var best_d := -1
		for tag in tags:
			if used_starts.has(tag):
				continue
			var d := 1 << 20
			for s in starts:
				d = mini(d, Hex.distance(spots[tag], s))
			if d > best_d:
				best_d = d
				best = tag
		if best == "":
			break
		used_starts[best] = true
		var route: Array[String] = [best]
		while route.size() < ROUTE_ROOMS:
			var here: Vector2i = spots[route[route.size() - 1]]
			var nxt := ""
			var nd := 1 << 20
			for tag in tags:
				if route.has(tag) or Hex.distance(here, spots[tag]) >= nd:
					continue
				if map.find_path(here, spots[tag], true, PATH_NODES).is_empty():
					continue
				nd = Hex.distance(here, spots[tag])
				nxt = tag
			if nxt == "":
				break
			route.append(nxt)
		# the loop closes: the last room back to the first
		while route.size() > 1 and map.find_path(spots[route[route.size() - 1]], spots[route[0]], true, PATH_NODES).is_empty():
			route.pop_back()
		if route.size() < 2:
			continue
		var cells: Array[Vector2i] = []
		for tag in route:
			cells.append(spots[tag])
		p.processions.append({"rooms": route, "route": cells})
		starts.append(spots[best])


## A room's spot: its centre, or the nearest cell to it that is full floor at the room's level and that nothing is planned on
## (SitePlan.blocked). NO_SPOT when the room has none.
static func _spot(map: HexMap, p: SitePlan, tag: String) -> Vector2i:
	var centre: Vector2i = p.centers[tag]
	var level := int(p.base_levels.get(tag, 0))
	var best := SiteBuilder.NO_SPOT
	var best_d := 1 << 20
	for c: Vector2i in (p.rooms[tag] as Array):
		var cell := map.get_cell(c)
		if cell == null or cell.type != HexMap.Tile.FLOOR or cell.level != level or not map.is_walkable_cell(c):
			continue
		if p.blocked.has(c) or map.is_pool_cell(c):
			continue
		var d := Hex.distance(c, centre)
		if d < best_d:
			best_d = d
			best = c
	return best


static func spawn(map: HexMap, run: ContractRun, p: SitePlan, site: SiteBuilder.Site) -> void:
	for i in p.processions.size():
		var rec: Dictionary = p.processions[i]
		var cells: Array[Vector2i] = []
		cells.assign(rec["route"] as Array)
		var room_tags: Array[String] = []
		for t: Variant in (rec["rooms"] as Array):
			room_tags.append(str(t))
		var pr := build(map, cells, room_tags, "Procession%d" % i)
		site.processions.append(pr)
		site.acolytes.append_array(pr.acolytes)
		for z in pr.zombies:
			site.monsters.append(z)
			if run.pest == z.kind:
				site.pest_spawned += 1


## A procession round the spots on `cells` (at least 2), in the world: its Procession under GameWorld.root, then its members in
## spawn (= net id) order: the leader at the head, Procession.FILE zombies GAP apart behind it, the rear acolyte last, standing on
## the way it came (the last two legs of its loop, into the first spot). The game's floors (spawn) and the gym.
static func build(map: HexMap, cells: Array[Vector2i], room_tags: Array[String] = [], node_name: String = "Procession") -> Procession:
	var spots: Array[Vector3] = []
	for c in cells:
		spots.append(_at(map, c))
	# the way it is on: its first leg (the first spot to the second), the leader the file's length along it, the file behind it
	# back to the first spot. (A leg shorter than the file starts on the leg before it, so the file still stands in line.)
	var n := cells.size()
	var file_len := Procession.GAP * float(Procession.FILE + Procession.ACOLYTES - 1)
	var legs: Array = [_leg(map, cells[0], cells[1 % n])]
	if _path_len(map, legs[0]) < file_len + 0.5:
		legs.push_front(_leg(map, cells[n - 1], cells[0]))
	var all: Array[Vector3] = []
	for leg: Array[Vector2i] in legs:
		for c in leg:
			var w := _at(map, c)
			if all.is_empty() or all[all.size() - 1].distance_to(w) > 0.01:
				all.append(w)
	var whole := ProcessionPath.through(all)
	var head_arc := minf(whole.head_arc(), maxf(whole.head_arc() - _path_len(map, legs[legs.size() - 1]), 0.0) + file_len + 0.5)
	var trail: Array[Vector3] = []
	for i in all.size():
		if whole.cum[i] < head_arc:
			trail.append(all[i])
	var head: Vector3 = whole.point(head_arc)["pos"]
	if trail.is_empty() or trail[trail.size() - 1].distance_to(head) > 0.01:
		trail.append(head)
	var pr := Procession.make(spots, trail, room_tags, 1 % n)
	pr.name = node_name
	GameWorld.root.add_child(pr)
	var kinds: Array[String] = ["acolyte"]
	for _z in Procession.FILE:
		kinds.append("zombie")
	kinds.append("acolyte")
	for k in kinds.size():
		var at := pr.trail.point(pr.trail.head_arc() - Procession.GAP * float(k))
		var m := _member(map, kinds[k], at["pos"], at["dir"])
		if m != null:
			pr.add_member(m, kinds[k] == "acolyte")
	return pr


## The cells from `a` to `b` (the path finder's; a straight step when it finds none).
static func _leg(map: HexMap, a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var path := map.find_path(a, b, true, PATH_NODES)
	return path if not path.is_empty() else ([a, b] as Array[Vector2i])


static func _path_len(map: HexMap, cells: Array[Vector2i]) -> float:
	var d := 0.0
	for i in range(1, cells.size()):
		d += _at(map, cells[i]).distance_to(_at(map, cells[i - 1]))
	return d


## A floor point over cell `c` (its ground).
static func _at(map: HexMap, c: Vector2i) -> Vector3:
	var lv := map.ground_level(Hex.to_world(c))
	return Hex.to_world(c, 0.0 if is_nan(lv) else lv)


static func _member(map: HexMap, kind: String, pos: Vector3, dir: Vector3) -> Monster:
	var m := MonsterFactory.spawn(kind, Hex.from_world(pos))
	if m == null:
		return null
	var lv := map.ground_level(pos)
	m.global_position = Vector3(pos.x, m.global_position.y if is_nan(lv) else lv, pos.z)
	m.set_spawn_facing(dir)
	return m
