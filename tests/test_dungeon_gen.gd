extends TestCase
## DungeonGen invariants (big airy rooms, corridors with a full centre lane, sparse features kept out of room
## centers, generation time, the elevator on its landing for both placements) + HexMapView smoke test + prototype
## textures. The midpoint-wall geometry itself (half cells, collision, doorways, placement) is tests/test_midpoint_walls.gd;
## the elevator in depth is tests/test_elevator.gd.

const SEEDS: Array[int] = [1, 2, 3, 7, 42, 99, 1234, 31337]


func setup() -> void:
	var total_ms := 0.0
	var worst_ms := 0.0
	for s in SEEDS:
		var t0 := Time.get_ticks_usec()
		var m := DungeonGen.generate(s)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total_ms += ms
		worst_ms = maxf(worst_ms, ms)
		_check_map(m, s, s <= 2)
		_check_corridor_width(m, s)
		_check_room_sizes(m, s)
	print("dungeon gen: avg %.0f ms, worst %.0f ms over %d seeds" % [total_ms / SEEDS.size(), worst_ms, SEEDS.size()])
	check(worst_ms < 300.0, "generation under 300 ms (worst %.0f ms)" % worst_ms)
	_check_features(s_list())
	# the free-standing elevator (the default is the wall notch): the same invariants hold
	for s in [1, 2, 3, 42]:
		var mf := DungeonGen.generate(s, {"elevator": ElevatorGeo.PLACE_FREE})
		_check_map(mf, s, false)
		eq(str(mf.elevator.get("place", "")), ElevatorGeo.PLACE_FREE, "seed %d: the free elevator was asked for" % s)

	# determinism
	var a := DungeonGen.generate(5)
	var b := DungeonGen.generate(5)
	var c := DungeonGen.generate(6)
	check(_same(a, b), "same seed -> same map")
	check(not _same(a, c), "different seed -> different map")

	# params
	var small := DungeonGen.generate(11, {"rooms": 6, "size": 34})
	_check_map(small, 11, false)
	var rooms := _room_ids(small)
	check(rooms.size() <= 6 and rooms.size() >= 5, "rooms param (%d)" % rooms.size())

	_view_smoke(DungeonGen.generate(3))
	for n in ProtoTextures.NAMES:
		var img := ProtoTextures.make(n)
		check(img != null and not img.is_empty(), "texture " + n)
	finish()


func _same(a: HexMap, b: HexMap) -> bool:
	if a.cells.size() != b.cells.size():
		return false
	for c in a.cells:
		var x: HexMap.Cell = a.cells[c]
		var y: HexMap.Cell = b.cells.get(c)
		if y == null or x.level != y.level or x.type != y.type or x.tag != y.tag or x.stair_dir != y.stair_dir or x.stair_rise != y.stair_rise:
			return false
	return true


func _room_ids(m: HexMap) -> Dictionary:
	var ids := {}
	for c in m.cells:
		var t: String = m.cells[c].tag
		if t.begins_with("room:"):
			ids[t] = true
	return ids


func _check_map(m: HexMap, s: int, deep: bool) -> void:
	var tag := "seed %d: " % s
	var starts := m.cells_with_tag("start")
	var exits := m.cells_with_tag("exit")
	eq(starts.size(), 1, tag + "one start")
	eq(exits.size(), 1, tag + "one exit")
	if starts.size() != 1 or exits.size() != 1:
		return
	var start := starts[0]
	var exit := exits[0]
	check(not m.find_path(start, exit, false).is_empty(), tag + "start->exit without climbing")
	# the elevator stands at the exit: the exit cell is its landing, full floor in front of its doors
	if check(not m.elevator.is_empty(), tag + "the floor has an elevator"):
		eq(m.elevator["landing"], exit, tag + "the exit is the elevator's landing")
		check(m.is_walkable_cell(exit), tag + "the landing is full floor")

	# BFS reach (no climbing) from start
	var reached := {start: true}
	var queue: Array[Vector2i] = [start]
	var qi := 0
	while qi < queue.size():
		var cur := queue[qi]
		qi += 1
		for d in Hex.DIRS:
			var nb: Vector2i = cur + d
			if not reached.has(nb) and m.is_walkable_cell(nb) and m.cell_transition(cur, nb) == HexMap.Move.OK:
				reached[nb] = true
				queue.append(nb)

	var rooms: Dictionary = {}   # tag -> Array of cells
	var stairs := 0
	var corridor := 0
	var walls := 0
	var lo := 99
	var hi := -99
	var pits := 0
	for c in m.cells:
		var cell: HexMap.Cell = m.cells[c]
		if cell.type == HexMap.Tile.STAIRS:
			stairs += 1
			check(cell.stair_rise >= 1 and cell.stair_rise <= 4, tag + "stairs rise 1..4")
		if cell.type == HexMap.Tile.WALL:
			walls += 1
			continue
		lo = mini(lo, cell.level)
		hi = maxi(hi, cell.level)
		if cell.tag == "corridor":
			corridor += 1
		if cell.tag.begins_with("room:"):
			if not rooms.has(cell.tag):
				rooms[cell.tag] = []
			rooms[cell.tag].append(c)
			if m.is_walkable_cell(c):
				check(reached.has(c), tag + "room cell reachable " + str(c))
			elif m.no_stand.has(c):
				check(m.elevator.get("cells", []).has(c), tag + "a cell under the elevator %s is the free car's" % str(c))
			else:
				check(m.is_half(c) and _touches_full(m, c), tag + "cut room cell %s borders the room's floor" % str(c))
	check(rooms.size() >= 5 and rooms.size() <= 9, tag + "room count %d" % rooms.size())
	for r in rooms:
		check(rooms[r].size() >= 5, tag + r + " has floor")
	check(reached.has(exit), tag + "exit reached")
	check(stairs >= 1, tag + "has stairs")
	check(corridor > 20, tag + "has corridors")
	check(walls > 50, tag + "has walls")
	check(hi - lo >= 5, tag + "height variety %d..%d" % [lo, hi])

	# at least one climb (+2) transition somewhere
	var climbs := 0
	for c in m.cells:
		if not m.is_walkable_cell(c):
			continue
		for d in Hex.DIRS:
			var nb: Vector2i = c + d
			if m.is_walkable_cell(nb) and m.cell_transition(c, nb) == HexMap.Move.CLIMB:
				climbs += 1
	check(climbs >= 1, tag + "has a climb transition")

	# rim: void next to walkable space must be an enclosed pit, never the open outside
	var void_seen := {}
	for c in m.cells:
		if not m.is_walkable_cell(c):
			continue
		for d in Hex.DIRS:
			var v: Vector2i = c + d
			if m.has_cell(v) or void_seen.has(v):
				continue
			var size := _void_size(m, v, 20)
			void_seen[v] = true
			check(size < 20, tag + "walkable cell borders open void at " + str(v))
			if size < 20:
				pits += 1
	check(pits >= 1, tag + "has a pit")

	# walls tower over what they enclose
	for c in m.cells:
		var cell: HexMap.Cell = m.cells[c]
		if cell.type != HexMap.Tile.WALL:
			continue
		for d in Hex.DIRS:
			var nc: HexMap.Cell = m.get_cell(c + d)
			if nc != null and nc.type != HexMap.Tile.WALL:
				if cell.level < nc.level + nc.stair_rise + 3:
					check(false, tag + "wall too low at " + str(c))
					return

	# clear area around start
	for c in Hex.range_cells(start, 2):
		var cell: HexMap.Cell = m.get_cell(c)
		check(cell != null and cell.type == HexMap.Tile.FLOOR and cell.level == m.get_cell(start).level, tag + "clear start area")

	if deep:
		# every room reachable by A* too
		for r in rooms:
			var cell0: Vector2i = rooms[r][0]
			check(not m.find_path(start, cell0, false).is_empty(), tag + "A* to " + r)


func _touches_full(m: HexMap, c: Vector2i) -> bool:
	for d in Hex.DIRS:
		if m.is_walkable_cell(c + d):
			return true
	return false


## Corridors have a full centre lane with the walls through their outer cells' centers: the outer cells are cut
## (each touching the full lane), the tree links carry a second full lane (4 cells across, 4.5 wide), so a good
## share of corridor cells is full and many full ones have a full neighbour beside them, not just ahead / behind.
func _check_corridor_width(m: HexMap, s: int) -> void:
	var total := 0
	var full := 0
	var double := 0
	for c: Vector2i in m.cells:
		if m.cells[c].tag != "corridor":
			continue
		total += 1
		if not m.is_walkable_cell(c):
			check(m.is_half(c) and _touches_full(m, c), "seed %d: cut corridor cell %s borders the full lane" % [s, str(c)])
			continue
		full += 1
		var k := 0
		for d in Hex.DIRS:
			if m.is_walkable_cell(c + d):
				k += 1
		if k >= 4:
			double += 1
	check(total > 0 and float(full) / total >= 0.35, "seed %d: corridors have full lanes (%d of %d cells)" % [s, full, total])
	check(full > 0 and float(double) / full >= 0.3, "seed %d: the main corridors are two full lanes wide (%d of %d full cells)" % [s, double, full])


## Rooms are big: no tiny rooms (radius 5-8 blobs), a decent average, and a real span across.
func _check_room_sizes(m: HexMap, s: int) -> void:
	var rooms: Dictionary = {}
	for c: Vector2i in m.cells:
		var t: String = m.cells[c].tag
		if t.begins_with("room:"):
			if not rooms.has(t):
				rooms[t] = []
			rooms[t].append(c)
	var sum := 0
	for t in rooms:
		var cells: Array = rooms[t]
		sum += cells.size()
		check(cells.size() >= 55, "seed %d: %s is roomy (%d cells)" % [s, t, cells.size()])
		var span := 0
		for a: Vector2i in cells:
			for b: Vector2i in [cells[0], cells[cells.size() / 2], cells[cells.size() - 1]]:
				span = maxi(span, Hex.distance(a, b))
		check(span >= 8, "seed %d: %s spans %d cells across" % [s, t, span])
	check(not rooms.is_empty() and float(sum) / rooms.size() >= 90.0, "seed %d: average room has %.0f cells" % [s, float(sum) / maxi(1, rooms.size())])


func s_list() -> Array[int]:
	return SEEDS


## Raised features, pits and ledges stay out of the middle of every room (radius 2) and away from its doors.
func _check_features(seeds: Array[int]) -> void:
	var off_level := 0
	var room_count := 0
	for s in seeds:
		var b := DungeonGen.Builder.new(s, {})
		var m := b.build()
		if m == null:
			continue   # this seed needed a retry; the public generate() path is covered above
		for r in b.rooms:
			room_count += 1
			for c in Hex.range_cells(r.center, DungeonGen.FEATURE_CENTER_CLEAR):
				var cell: HexMap.Cell = m.get_cell(c)
				check(cell != null and cell.level == r.level and cell.type == HexMap.Tile.FLOOR, "seed %d room %d: the middle is clear at %s" % [s, r.index, str(c)])
			for c: Vector2i in r.cells:
				var cell: HexMap.Cell = m.get_cell(c)
				if cell == null or cell.level == r.level:
					continue
				off_level += 1
				for d: Vector2i in b.corr_cells:
					if Hex.distance(c, d) <= DungeonGen.FEATURE_DOOR_CLEAR:
						check(false, "seed %d room %d: feature cell %s is within %d of a door" % [s, r.index, str(c), DungeonGen.FEATURE_DOOR_CLEAR])
						break
	check(room_count > 10, "features checked on %d rooms" % room_count)
	check(float(off_level) / maxi(1, room_count) <= 9.0, "sparse features: %.1f raised cells a room" % (float(off_level) / maxi(1, room_count)))


## Size of the void component containing v, counting at most `limit`.
func _void_size(m: HexMap, v: Vector2i, limit: int) -> int:
	var seen := {v: true}
	var queue: Array[Vector2i] = [v]
	var qi := 0
	while qi < queue.size() and seen.size() < limit:
		var cur := queue[qi]
		qi += 1
		for d in Hex.DIRS:
			var nb: Vector2i = cur + d
			if not seen.has(nb) and not m.has_cell(nb):
				seen[nb] = true
				queue.append(nb)
	return seen.size()


func _view_smoke(m: HexMap) -> void:
	var view := HexMapView.new()
	add_child(view)
	view.build(m)
	check(view.get_child_count() >= 1 and view.get_child(0) is MeshInstance3D, "view has a mesh instance")
	var mi: MeshInstance3D = view.mesh_instance
	check(mi != null and mi.mesh != null, "mesh built")
	check(mi.mesh.get_surface_count() >= 5, "several surfaces (%d)" % mi.mesh.get_surface_count())
	check(int(view.stats["triangles"]) > 2000, "triangles %d" % int(view.stats["triangles"]))
	check(int(view.stats["stair_steps"]) > 0, "stair steps built")
	view.build(m)  # rebuild must not leak children
	check(view.get_child_count() == 1 or view.get_children().filter(func(n): return not n.is_queued_for_deletion()).size() == 1, "rebuild replaces mesh")
	view.queue_free()
