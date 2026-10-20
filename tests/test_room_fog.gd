extends TestCase
## Room fog (RoomFog, Doorways; docs/design/exploration.md "Decisions: map information, fog and doors", 2026-10-19): the space states and how they change.
## A hand-built floor in a row, west to east: room A, a SHORT hall (5 cells), room B, a LONG hall (19 cells), room C, a long
## hall, room D. Walls are midpoint walls (cut_walls), as on a generated floor.

const A := Vector2i(0, 0)
const B := Vector2i(16, 0)
const C := Vector2i(46, 0)
const D := Vector2i(76, 0)
const R := 5


## `lanes` 4: tree-link halls (4 cells across, 4.5 between the walls); 3: narrow halls (3 across, 3.0, one full lane).
static func row_map(lanes: int = 4) -> HexMap:
	var m := HexMap.new()
	var cells := {}
	var rooms := [A, B, C, D]
	for i in rooms.size():
		for c in Hex.range_cells(rooms[i], R):
			cells[c] = "room:%d" % i
	for i in range(rooms.size() - 1):
		var q0: int = (rooms[i] as Vector2i).x
		var q1: int = (rooms[i + 1] as Vector2i).x
		for q in range(q0, q1 + 1):
			for r in (range(-2, 2) if lanes >= 4 else range(-1, 2)):
				var c := Vector2i(q, r)
				if not cells.has(c):
					cells[c] = "corridor"
	for c: Vector2i in cells:
		m.set_cell(c, 0).tag = cells[c]
	var walls := {}
	for c: Vector2i in cells:
		for d in Hex.DIRS:
			if not cells.has(c + d):
				walls[c + d] = true
	for w: Vector2i in walls:
		m.set_cell(w, 3, HexMap.Tile.WALL)
	m.cut_walls()
	return m


static func at(c: Vector2i) -> Vector3:
	return Hex.to_world(c)


func setup() -> void:
	# Sections 1-7: the doorway rules on WHOLE halls (the row's long halls stay one space each). The game cuts long halls
	# into segments (RoomFog.split_long_halls): sections 8-11.
	var was := RoomFog.split_long_halls
	RoomFog.split_long_halls = false
	var map := row_map()
	var fog := RoomFog.build(map)
	var a := fog.space_of_cell(A)
	var b := fog.space_of_cell(B)
	var c := fog.space_of_cell(C)
	var d := fog.space_of_cell(D)
	var h0 := fog.space_of_cell(Vector2i(8, 0))
	var h1 := fog.space_of_cell(Vector2i(31, 0))
	var h2 := fog.space_of_cell(Vector2i(61, 0))
	eq(fog.space_count(), 7, "four rooms and three halls")
	check(fog.is_hall[h0] and fog.is_hall[h1] and fog.is_hall[h2] and not fog.is_hall[a], "corridors are halls of their own")
	eq(fog.doorways.size(), 6, "one doorway at each end of each hall")
	for dw in fog.doorways:
		check(bool(dw["ok"]), "doorway %d: the corridor was measured" % int(dw["id"]))
		near(float(dw.get("width", 0.0)), 4.5, 0.15, "a 4-cell corridor is 4.5 between its walls")
		check(not bool(dw["narrow"]) and not bool(dw["door_ok"]), "a wide hallway's doorway has no door place: always open")
	check(fog.state.size() == 7 and fog.census()["unknown"] == 7, "nothing known before anyone looks")

	# 1. Enter a room (its doorway shut, so only the room itself): in view; the hall and the room past it are NEXT (layout);
	#    the rest is dark.
	var a_h0 := fog.doorways_between(a, h0)[0]
	fog.set_shut(a_h0, true)
	check(fog.update([at(A)]), "the first look changes the states")
	eq(fog.state_of(a), RoomFog.IN_VIEW, "the room a hero stands in is in view")
	eq(fog.state_of(h0), RoomFog.NEXT, "its hall shows its layout")
	eq(fog.state_of(b), RoomFog.NEXT, "... and so does the room at the hall's far end (the next room)")
	eq(fog.state_of(h1), RoomFog.UNKNOWN, "beyond the next room is dark")
	eq(fog.state_of(c), RoomFog.UNKNOWN, "beyond the next room is dark (C)")
	check(not fog.update([at(A)]), "the same look again changes nothing")

	# 2. A shut door blocks the look through its doorway; open it and the hall comes into view, and (the hall being short
	#    and straight) room B behind it from the door cell.
	fog.set_shut(a_h0, false)
	fog.update([at(A)])
	eq(fog.state_of(h0), RoomFog.IN_VIEW, "an open doorway within reach and sight: the hall beyond is in view")
	eq(fog.state_of(b), RoomFog.NEXT, "from the room's middle, room B is too far to see into")
	fog.update([at(Vector2i(5, 0))])
	eq(fog.state_of(b), RoomFog.IN_VIEW, "from the doorway, two doorways deep down a short straight hall: B is in view")
	eq(fog.state_of(a), RoomFog.IN_VIEW, "... and A, where the hero stands")
	eq(fog.state_of(h1), RoomFog.NEXT, "B's other hall is next now")
	eq(fog.state_of(c), RoomFog.NEXT, "... and C beyond it")
	eq(fog.state_of(d), RoomFog.UNKNOWN, "D stays dark")
	fog.set_shut(a_h0, true)
	fog.update([at(Vector2i(5, 0))])
	eq(fog.state_of(h0), RoomFog.SEEN, "shut the door: the hall is out of view, but it was seen")
	eq(fog.state_of(b), RoomFog.SEEN, "... and so was B")
	eq(fog.state_of(a), RoomFog.IN_VIEW, "the room you stand in never goes dark")

	# 3. A hero in the long hall far from both ends: only the hall (its doorways are beyond DOOR_SIGHT).
	var fog2 := RoomFog.build(map)
	fog2.update([at(Vector2i(31, 0))])
	eq(fog2.state_of(h1), RoomFog.IN_VIEW, "the hall a hero stands in")
	var mid_b: Vector3 = fog2.doorways[fog2.doorways_between(b, h1)[0]]["mid"]
	check(GameWorld.flat_distance(at(Vector2i(31, 0)), mid_b) > RoomFog.DOOR_SIGHT, "(B's doorway is out of sight range)")
	eq(fog2.state_of(b), RoomFog.NEXT, "B is next: layout only")
	eq(fog2.state_of(c), RoomFog.NEXT, "C is next: layout only")
	eq(fog2.state_of(h0), RoomFog.UNKNOWN, "a hall one room away is dark")

	# 4. Shared reveal: two heroes, two rooms: both in view for the whole crew.
	var fog3 := RoomFog.build(map)
	for dw in fog3.doorways:
		fog3.set_shut(int(dw["id"]), true)
	fog3.update([at(A), at(C)])
	eq(fog3.state_of(a), RoomFog.IN_VIEW, "shared reveal: A (hero 1)")
	eq(fog3.state_of(c), RoomFog.IN_VIEW, "shared reveal: C (hero 2)")
	eq(fog3.state_of(b), RoomFog.NEXT, "B is between them: next")
	eq(fog3.state_of(d), RoomFog.NEXT, "D is one hall from C: next")
	fog3.update([at(A)])
	eq(fog3.state_of(c), RoomFog.SEEN, "hero 2 leaves C: seen, dimmed")

	# 5. Contents: a monster shows only in a space in view; furniture in view or seen.
	var monster_in_c := at(C) + Vector3(1.0, 0.0, 0.5)
	check(not fog3.shows_contents(monster_in_c), "a monster in a seen room is hidden (no last-known ghosts)")
	check(fog3.shows_static(monster_in_c), "furniture in a seen room still shows (dimmed)")
	check(not fog3.shows_contents(at(D)) and not fog3.shows_static(at(D)), "nothing in a next room shows: layout only")
	check(fog3.shows_contents(at(A) + Vector3(2.0, 0.0, 0.0)), "a monster in the room in view shows")
	check(not fog3.shows_contents(Hex.to_world(Vector2i(0, -6))), "a point in the wall is in no space")

	# 6. Vantage: two levels up in a room sees into the spaces next to it through an open doorway, however far; never past a
	#    shut door (user, 2026-10-19).
	var map2 := row_map()
	for t in [Vector2i(-4, 0), Vector2i(-4, 1), Vector2i(-3, 0)]:
		map2.get_cell(t).level = 2
	var fog4 := RoomFog.build(map2)
	var tier := at(Vector2i(-4, 0))
	var hv0 := fog4.space_of_cell(Vector2i(8, 0))
	var a_hv0 := fog4.doorways_between(fog4.space_of_cell(A), hv0)[0]
	check(GameWorld.flat_distance(tier, fog4.doorways[a_hv0]["mid"]) > RoomFog.DOOR_SIGHT, "(the tier is out of plain doorway sight)")
	fog4.update([at(Vector2i(-4, 2))])
	eq(fog4.state_of(hv0), RoomFog.NEXT, "on the floor at the same distance: the hall is only next")
	fog4.update([tier])
	eq(fog4.state_of(hv0), RoomFog.IN_VIEW, "a vantage two levels up sees into the next space through the open doorway")
	var fog5 := RoomFog.build(map2)
	fog5.set_shut(a_hv0, true)
	fog5.update([tier])
	eq(fog5.state_of(hv0), RoomFog.NEXT, "... but not past a shut door")

	# 7. Determinism: the same map builds the same spaces and doorways.
	var again := RoomFog.build(row_map())
	eq(again.tags, fog.tags, "same spaces")
	eq(again.doorways.size(), fog.doorways.size(), "same doorways")
	for i in fog.doorways.size():
		eq(again.doorways[i]["mid"], fog.doorways[i]["mid"], "same doorway %d" % i)
	var narrow := RoomFog.build(row_map(3))
	for dw in narrow.doorways:
		check(bool(dw["narrow"]) and bool(dw["door_ok"]), "a narrow hall's doorway %d has a door place" % int(dw["id"]))
		near(float(dw["width"]), 3.0, 0.15, "a 3-cell corridor is 3.0 between its walls")
		eq((dw["band"] as Array).size(), 3, "the band: the doorway cell and the two cut cells beside it")
		check(narrow.map.is_walkable_cell(dw["cell"]), "the doorway cell is a full cell")
		check(not (dw["edges"] as Array).is_empty(), "the band's room-side hex edges")

	# 8. A generated floor (long halls cut, as in the game): every room and hall is a space, every hall has doorways, most
	#    of them take a door.
	RoomFog.split_long_halls = true
	var gen := DungeonGen.generate(7)
	var gf := RoomFog.build(gen)
	var spans := 0
	var narrows := 0
	for dw in gf.doorways:
		if gf.is_cut(int(dw["id"])):
			continue   # (a cut between two segments of a long hall: no door place, section 9)
		if bool(dw["ok"]):
			spans += 1
		if bool(dw["narrow"]):
			narrows += 1
			check(bool(dw["door_ok"]), "a narrow doorway of a generated floor has a door place (%d)" % int(dw["id"]))
	var halls := 0
	for i in gf.space_count():
		if gf.is_hall[i]:
			halls += 1
			check(not (gf.links[i] as Array).is_empty(), "%s leads somewhere" % gf.tags[i])
	print("generated floor 7: %d spaces (%d halls), %d doorways, %d measured, %d narrow" % [gf.space_count(), halls, gf.doorways.size(), spans, narrows])
	var real := 0
	for dw in gf.doorways:
		if not gf.is_cut(int(dw["id"])):
			real += 1
	check(spans * 10 >= real * 7, "at least 70% of a generated floor's doorways are measured")
	var t0 := Time.get_ticks_usec()
	var heroes: Array = []
	for i in 3:
		heroes.append(Hex.to_world(gen.cells_with_tag("start")[0]) + Vector3(0.5 * i, 0.0, 0.0))
	for i in 100:
		gf.update(heroes)
	var per := float(Time.get_ticks_usec() - t0) / 100.0
	print("RoomFog.update, 3 heroes on a generated floor: %.1f us" % per)
	check(per < 2000.0, "an update costs well under 2 ms")

	_long_halls()
	RoomFog.split_long_halls = was
	finish()


## Two rooms joined by one long straight hall, 3 cells across (LONG_Q apart): the hall gets cut into segments.
const LONG_Q := 96


static func long_map() -> HexMap:
	var m := HexMap.new()
	var cells := {}
	for i in 2:
		for c in Hex.range_cells(Vector2i(i * LONG_Q, 0), R):
			cells[c] = "room:%d" % i
	for q in range(0, LONG_Q + 1):
		for r in range(-1, 2):
			if not cells.has(Vector2i(q, r)):
				cells[Vector2i(q, r)] = "corridor"
	for c: Vector2i in cells:
		m.set_cell(c, 0).tag = cells[c]
	for c: Vector2i in cells:
		for d in Hex.DIRS:
			if not cells.has(c + d):
				m.set_cell(c + d, 3, HexMap.Tile.WALL)
	m.cut_walls()
	return m


# 9-11. LONG HALLS (RoomFog.split_long_halls, on in the game; user, 2026-10-20: "Turn it on"): a long hall is cut into
# segments; walking down it shows it about a segment ahead; a hero standing on a cut sees the same from either side (no
# flicker); the crew's sight is shared; every machine (a puppet's position, a late joiner) gets the same view.
func _long_halls() -> void:
	var m := long_map()
	var fog := RoomFog.build(m)
	var ra := fog.space_of_cell(Vector2i(0, 0))
	var rb := fog.space_of_cell(Vector2i(LONG_Q, 0))
	var hall := fog.space_of_cell(Vector2i(LONG_Q / 2, 0))
	var segs := fog.hall_segments(hall)
	check(segs.size() >= 6, "the long hall is cut into segments (%d)" % segs.size())
	# the segments in order along the hall, west to east
	var path: Array[Vector2i] = []
	for q in range(R + 1, LONG_Q - R):
		path.append(Vector2i(q, 0))
	var rank := _ranks(fog, path)
	eq(rank.size(), segs.size(), "the walk crosses every segment")
	var cuts := 0
	for dw in fog.doorways:
		if fog.is_cut(int(dw["id"])):
			cuts += 1
			check(fog.segmented[int(dw["ri"])] == 1 and fog.segmented[int(dw["hi"])] == 1, "cut %d joins two segments" % int(dw["id"]))
			check(absi(int(rank[int(dw["ri"])]) - int(rank[int(dw["hi"])])) == 1, "cut %d joins consecutive segments" % int(dw["id"]))
		else:
			check(not fog.is_hall[int(dw["ri"])], "doorway %d is a room's" % int(dw["id"]))
	eq(cuts, segs.size() - 1, "a cut between each two segments")
	eq(fog.doorways.size(), 2 + cuts, "the room doorways keep their ids, the cuts come after")

	# 9. From room A: the first segment is in view or next, the one after it next at most; the rest and room B dark.
	fog.update([at(Vector2i(0, 0))])
	var first: int = rank.find_key(0)
	check(fog.state_of(first) >= RoomFog.NEXT, "from room A the hall's first segment shows")
	for s: int in rank:
		if int(rank[s]) >= 3:
			eq(fog.state_of(s), RoomFog.UNKNOWN, "from room A segment %s (rank %d) is dark" % [fog.tags[s], rank[s]])
	eq(fog.state_of(rb), RoomFog.UNKNOWN, "a room at the far end of a cut hall is not next (it was, down a whole hall)")

	# 10. Walk down the hall: the hero's segment in view, the next one at least next, nothing three or more segments ahead
	#     ever seen; at the end room B shows.
	var max_lead := 0
	for c in path:
		fog.update([at(c)])
		var k := int(rank[fog.space_of_cell(c)])
		eq(fog.state_of(fog.space_of_cell(c)), RoomFog.IN_VIEW, "walking: the segment under the hero is in view (%s)" % c)
		for s: int in rank:
			var ahead := int(rank[s]) - k
			if ahead == 1:
				check(fog.state_of(s) >= RoomFog.NEXT, "walking at %s: the next segment shows (%s)" % [c, RoomFog.NAMES[fog.state_of(s)]])
			if ahead >= 1 and fog.state_of(s) >= RoomFog.SEEN:
				max_lead = maxi(max_lead, ahead)
			if ahead >= 3:
				check(fog.state_of(s) < RoomFog.SEEN, "walking at %s: segment %s, %d ahead, not seen yet" % [c, fog.tags[s], ahead])
	print("long hall: %d segments, revealed up to %d segment(s) ahead of the hero" % [segs.size(), max_lead])
	check(max_lead >= 1, "the hall shows ahead of the hero")
	fog.update([at(Vector2i(LONG_Q - R, 0))])
	eq(fog.state_of(rb), RoomFog.IN_VIEW, "at the far end, room B")

	# 11a. No flicker: a hero standing on a cut, nudged a hair either way, has the same spaces in view, and stepping back
	#      and forth over it changes nothing.
	_no_flicker(m, "long hall")
	# 11b. Shared sight: two heroes in different segments: both segments and what each sees.
	var a_pos := at(Vector2i(20, 0))
	var b_pos := at(Vector2i(70, 0))
	var f1 := RoomFog.build(m)
	f1.update([a_pos])
	var f2 := RoomFog.build(m)
	f2.update([b_pos])
	var crew := RoomFog.build(m)
	crew.update([a_pos, b_pos])
	for s in crew.space_count():
		eq(crew.view[s], maxi(f1.view[s], f2.view[s]), "shared sight: %s in view for the crew iff for one hero" % crew.tags[s])
	# 11c. Every machine: a host and a client fed the same heroes (theirs, and puppets) agree; a late joiner, built fresh
	#      mid-walk, has the same in view at once (and knows nothing it hasn't seen).
	var host := RoomFog.build(m)
	var client := RoomFog.build(m)
	eq(host.tags, client.tags, "every machine cuts the same segments")
	for i in host.doorways.size():
		eq(host.doorways[i]["mid"], client.doorways[i]["mid"], "every machine puts cut %d in the same place" % i)
	var pts: Array = []
	for q in range(R + 1, 60, 3):
		pts = [at(Vector2i(q, 0)), at(Vector2i(q - 2, 1))]
		host.update(pts)
		client.update(pts)
	eq(host.state, client.state, "host and client: the same states after the same walk")
	var late := RoomFog.build(m)
	late.update(pts)
	eq(late.view, host.view, "a late joiner has the same in view at once")
	for s in late.space_count():
		check(late.state[s] <= host.state[s], "a late joiner knows no more than the crew (%s)" % late.tags[s])

	# 11d. A generated floor's longest hall (contract seed 3, floor 1: 83 steps of corridor): the same walk, and no flicker
	#      at any cut of the floor.
	var gm := DungeonGen.for_run(ContractBoard.run_for_seed(3), 1)
	var gf := RoomFog.build(gm)
	var longest := -1
	for s in gf.space_count():
		if gf.segmented[s] == 1 and (longest < 0 or gf.hall_segments(s).size() > gf.hall_segments(longest).size()):
			longest = s
	check(longest >= 0, "seed 3 floor 1 has a cut hall")
	var gsegs := gf.hall_segments(longest)
	var corr: Array[Vector2i] = []
	for c: Vector2i in gf.cell_space:
		if gsegs.has(gf.space_of_cell(c)) and gm.cells[c].tag == "corridor" and gm.is_walkable_cell(c):
			corr.append(c)
	corr.sort()
	var e0 := RoomFog._walk_far(corr, corr[0])[0] as Vector2i
	var e1 := RoomFog._walk_far(corr, e0)[0] as Vector2i
	var gpath := _path(corr, e0, e1)
	var grank := _ranks(gf, gpath)
	eq(grank.size(), gsegs.size(), "seed 3 floor 1: the walk down %s crosses all its %d segments" % [gf.tags[longest], gsegs.size()])
	var glead := 0
	for c in gpath:
		gf.update([Hex.to_world(c, float(gm.cells[c].level))])
		var k := int(grank[gf.space_of_cell(c)])
		for s: int in grank:
			var ahead := int(grank[s]) - k
			if ahead == 1:
				check(gf.state_of(s) >= RoomFog.NEXT, "seed 3 floor 1 at %s: the next segment shows" % c)
			if ahead >= 1 and gf.state_of(s) >= RoomFog.SEEN:
				glead = maxi(glead, ahead)
			if ahead >= 3:
				check(gf.state_of(s) < RoomFog.SEEN, "seed 3 floor 1 at %s: segment %s, %d ahead, not seen yet" % [c, gf.tags[s], ahead])
	print("seed 3 floor 1 %s: %d segments over %d steps, revealed up to %d ahead" % [gf.tags[longest], gsegs.size(), gpath.size() - 1, glead])
	_no_flicker(gm, "seed 3 floor 1")


## Each segment's rank along `path` (the order the walk first enters it): {space: rank}.
static func _ranks(fog: RoomFog, path: Array[Vector2i]) -> Dictionary:
	var rank := {}
	for c in path:
		var s := fog.space_of_cell(c)
		if s >= 0 and fog.segmented[s] == 1 and not rank.has(s):
			rank[s] = rank.size()
	return rank


## The shortest walk from `a` to `b` over `cells`.
static func _path(cells: Array[Vector2i], a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var inside := {}
	for c in cells:
		inside[c] = true
	var parent := {a: a}
	var queue: Array[Vector2i] = [a]
	var i := 0
	while i < queue.size():
		var cur := queue[i]
		i += 1
		if cur == b:
			break
		for d in Hex.DIRS:
			var n: Vector2i = cur + d
			if inside.has(n) and not parent.has(n):
				parent[n] = cur
				queue.append(n)
	var out: Array[Vector2i] = [b]
	while out[0] != a:
		out.push_front(parent[out[0]])
	return out


## At every cut of the map: a hero on the line between two touching cells of its two segments, nudged 0.01 either way,
## has the same spaces in view; stepping back and forth over it, after the first two looks, changes nothing.
func _no_flicker(m: HexMap, label: String) -> void:
	var fog := RoomFog.build(m)
	var cuts := 0
	var bad := 0
	for dw in fog.doorways:
		if not fog.is_cut(int(dw["id"])):
			continue
		for a: Vector2i in dw["door_cells"]:
			for d in Hex.DIRS:
				var b: Vector2i = a + d
				if not (dw["mouth_cells"] as Array).has(b) or not m.is_walkable_cell(a) or not m.is_walkable_cell(b):
					continue
				var pa := Hex.to_world(a, float(m.cells[a].level))
				var pb := Hex.to_world(b, float(m.cells[b].level))
				var mid := (pa + pb) * 0.5
				var step := (pb - pa).normalized() * 0.01
				var one := RoomFog.build(m)
				one.update([mid - step])
				var other := RoomFog.build(m)
				other.update([mid + step])
				cuts += 1
				if one.view != other.view:
					bad += 1
					check(false, "%s: cut %d between %s and %s: the same in view either side" % [label, int(dw["id"]), a, b])
				var walk := RoomFog.build(m)
				walk.update([mid - step])
				walk.update([mid + step])
				var changes := 0
				for i in 6:
					if walk.update([mid - step if i % 2 == 0 else mid + step]):
						changes += 1
				if changes > 0:
					check(false, "%s: cut %d between %s and %s: stepping back and forth changes the fog %d times" % [label, int(dw["id"]), a, b, changes])
	print("%s: no flicker checked at %d spots on cuts (%d differ)" % [label, cuts, bad])
	check(cuts > 0, "%s: there are cuts to check" % label)
