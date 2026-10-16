extends TestCase
## Hex math + HexMap movement rules (step / climb / block / stairs) + A*.


func setup() -> void:
	# Round trips
	for c in [Vector2i(0, 0), Vector2i(3, -2), Vector2i(-5, 7)]:
		eq(Hex.from_world(Hex.to_world(c)), c, "round trip")
	eq(Hex.distance(Vector2i(0, 0), Vector2i(3, -1)), 3, "distance")
	eq(Hex.range_cells(Vector2i.ZERO, 2).size(), 19, "range 2")
	eq(Hex.ring(Vector2i.ZERO, 2).size(), 12, "ring 2")
	eq(Hex.line(Vector2i(0, 0), Vector2i(4, 0)).size(), 5, "line")

	# A row of cells going east with assorted heights.
	var m := HexMap.new()
	m.set_cell(Vector2i(0, 0), 0)
	m.set_cell(Vector2i(1, 0), 1)   # step up
	m.set_cell(Vector2i(2, 0), 3)   # climb (+2)
	m.set_cell(Vector2i(3, 0), 6)   # blocked (+3)
	eq(m.cell_transition(Vector2i(0, 0), Vector2i(1, 0)), HexMap.Move.OK, "step")
	eq(m.cell_transition(Vector2i(1, 0), Vector2i(2, 0)), HexMap.Move.CLIMB, "climb")
	eq(m.cell_transition(Vector2i(2, 0), Vector2i(3, 0)), HexMap.Move.BLOCKED, "too high")
	eq(m.cell_transition(Vector2i(2, 0), Vector2i(1, 0)), HexMap.Move.OK, "drop 2")
	eq(m.cell_transition(Vector2i(0, 0), Vector2i(0, 1)), HexMap.Move.BLOCKED, "void")

	# Stairs bridge a 4-level gap eastward.
	var s := HexMap.new()
	s.set_cell(Vector2i(0, 0), 0)
	s.set_stairs(Vector2i(1, 0), 0, 0, 4)
	s.set_cell(Vector2i(2, 0), 4)
	eq(s.cell_transition(Vector2i(0, 0), Vector2i(1, 0)), HexMap.Move.OK, "onto stairs")
	eq(s.cell_transition(Vector2i(1, 0), Vector2i(2, 0)), HexMap.Move.OK, "off stairs top")
	near(s.ground_level(Hex.to_world(Vector2i(1, 0))), 2.0, 0.01, "stairs mid height")
	eq(s.find_path(Vector2i(0, 0), Vector2i(2, 0)).size(), 3, "path over stairs")

	# Line of sight blocked by a wall
	var w := HexMap.new()
	for q in 5:
		w.set_cell(Vector2i(q, 0), 0)
	w.set_cell(Vector2i(2, 0), 10, HexMap.Tile.WALL)
	check(not w.line_of_sight(Hex.to_world(Vector2i(0, 0)) + Vector3.UP, Hex.to_world(Vector2i(4, 0)) + Vector3.UP), "wall blocks LOS")
	check(m.line_of_sight(Hex.to_world(Vector2i(0, 0)) + Vector3.UP * 5, Hex.to_world(Vector2i(1, 0)) + Vector3.UP * 5), "clear LOS")
	eq(w.find_path(Vector2i(0, 0), Vector2i(4, 0)).size(), 0, "wall blocks path")
	finish()
