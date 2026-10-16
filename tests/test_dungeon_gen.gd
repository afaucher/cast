extends TestCase
## DungeonGen invariants + HexMapView smoke test + prototype textures.

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
	print("dungeon gen: avg %.0f ms, worst %.0f ms over %d seeds" % [total_ms / SEEDS.size(), worst_ms, SEEDS.size()])
	check(worst_ms < 1000.0, "generation under 1s (worst %.0f ms)" % worst_ms)

	# determinism
	var a := DungeonGen.generate(5)
	var b := DungeonGen.generate(5)
	var c := DungeonGen.generate(6)
	check(_same(a, b), "same seed -> same map")
	check(not _same(a, c), "different seed -> different map")

	# params
	var small := DungeonGen.generate(11, {"rooms": 6, "size": 22})
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
			check(reached.has(c), tag + "room cell reachable " + str(c))
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
