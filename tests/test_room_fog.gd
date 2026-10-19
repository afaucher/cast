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

	# 8. A generated floor: every room and hall is a space, every hall has doorways, most of them take a door.
	var gen := DungeonGen.generate(7)
	var gf := RoomFog.build(gen)
	var spans := 0
	var narrows := 0
	for dw in gf.doorways:
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
	check(spans * 10 >= gf.doorways.size() * 7, "at least 70% of a generated floor's doorways are measured")
	var t0 := Time.get_ticks_usec()
	var heroes: Array = []
	for i in 3:
		heroes.append(Hex.to_world(gen.cells_with_tag("start")[0]) + Vector3(0.5 * i, 0.0, 0.0))
	for i in 100:
		gf.update(heroes)
	var per := float(Time.get_ticks_usec() - t0) / 100.0
	print("RoomFog.update, 3 heroes on a generated floor: %.1f us" % per)
	check(per < 2000.0, "an update costs well under 2 ms")
	finish()
