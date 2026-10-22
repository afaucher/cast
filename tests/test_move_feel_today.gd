extends TestCase
## The `today` movement profile is the game as it was before MoveFeel existed, to the last digit
## (docs/design/movement-research.md, "As built"). A scripted walk over a course with every kind of ground (a +1 step and a
## +2 climb, a reversal, a wall push, a lava edge slide, wading, coffee, a bow draw, a 3-level drop) and an AI ally following
## is replayed through the real PlayerController and AllyBrain, and every physics frame's positions must match the trace
## recorded from the code BEFORE the movement profiles were added (tests/golden/move_today.txt).
##
## Re-record only when `today` is MEANT to change (it should not: it is the A/B baseline):
##   $env:CAST_MOVE_RECORD = "1"; .\test_runner.ps1 -TestName test_move_feel_today; Remove-Item Env:CAST_MOVE_RECORD

const PATH := "res://tests/golden/move_today.txt"
const LEVEL := 2

var root: Node3D


## The course: a disc at LEVEL with a +1 and a +2 platform, a short hex wall, a pool basin one level down, a strip of lava
## along the west rim and a pit three levels down in the north-east.
static func course_map() -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 9):
		m.set_cell(c, LEVEL)
	for c in Hex.range_cells(Vector2i(3, 0), 1):
		m.set_cell(c, LEVEL + 1)
	for c in Hex.range_cells(Vector2i(-3, 0), 1):
		m.set_cell(c, LEVEL + 2)
	for c in [Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3)]:
		m.set_cell(c, 10, HexMap.Tile.WALL)
	for c in Hex.range_cells(Vector2i(-3, 6), 1):
		var cell := m.get_cell(c)
		cell.pool_mask = HexMap.ALL_KITES
		cell.pool_level = LEVEL - 1
	m.pools.append({"look": "pool", "basin": Hex.range_cells(Vector2i(-3, 6), 1)})
	for c in Hex.range_cells(Vector2i(6, -5), 1):
		m.set_cell(c, LEVEL - 3)
	for c: Vector2i in m.cells.keys():
		if Hex.to_world(c).x < -10.5:
			m.remove_cell(c)
			m.lava[c] = true
	return m


## The script: [frames, kind, value]. kind "dir" walks a fixed world direction, "to" walks toward a cell's centre, "idle"
## stands, "coffee" / "draw" / "undraw" are one-frame events.
static func script_steps() -> Array:
	return [
		[20, "idle", null],
		[70, "to", Vector2i(3, 0)],          # onto the +1 platform
		[10, "idle", null],
		[15, "dir", Vector3.LEFT],           # reversals
		[15, "dir", Vector3.RIGHT],
		[12, "dir", Vector3.LEFT],
		[8, "idle", null],
		[150, "to", Vector2i(-3, 0)],        # down the step and up the +2 climb
		[60, "to", Vector2i(-6, 2)],
		[90, "dir", Vector3(-0.35, 0, 1).normalized()],   # along the lava edge
		[40, "dir", Vector3(0.7, 0, -0.7)],
		[1, "coffee", null],
		[80, "to", Vector2i(1, 2)],          # coffee: into the wall
		[30, "dir", Vector3(0.3, 0, 1).normalized()],      # pushing on the hex wall
		[1, "draw", null],
		[60, "to", Vector2i(-3, 6)],         # bow drawn, into the pool
		[1, "undraw", null],
		[40, "dir", Vector3(1, 0, 0.2).normalized()],
		[25, "idle", null],
		[70, "to", Vector2i(-2, 3)],
		[210, "to", Vector2i(6, -5)],        # off the edge into the pit
		[30, "idle", null],
	]


func setup() -> void:
	timeout_sec = 120.0
	root = Node3D.new()
	add_child(root)
	var lines := await run_trace(get_tree(), root)
	if OS.get_environment("CAST_MOVE_RECORD") == "1":
		var f := FileAccess.open(PATH, FileAccess.WRITE)
		check(f != null, "can write %s" % PATH)
		if f != null:
			f.store_string("\n".join(lines) + "\n")
			f.close()
		print("[move] recorded %d frames to %s" % [lines.size(), PATH])
		finish()
		return
	if not check(FileAccess.file_exists(PATH), "the recorded trace exists (%s)" % PATH):
		finish()
		return
	var want := FileAccess.get_file_as_string(PATH).strip_edges().split("\n")
	eq(lines.size(), want.size(), "as many frames as recorded")
	var first_bad := -1
	for i in mini(lines.size(), want.size()):
		if lines[i] != want[i]:
			first_bad = i
			break
	check(first_bad < 0, "today's motion is the recorded motion (first difference at frame %d: got %s, want %s)" % [
		first_bad, lines[first_bad] if first_bad >= 0 else "", want[first_bad] if first_bad >= 0 else ""])
	finish()


## Walk the script and return one line per physics frame: the player's and the ally's positions.
static func run_trace(tree: SceneTree, parent: Node3D) -> PackedStringArray:
	var world := Node3D.new()
	parent.add_child(world)
	GameWorld.begin(course_map(), world, 4242)
	var player := HeroFactory.spawn_hero(Vector2i(0, 0), "Walker", Color.BLUE, "sword", null, "wick")
	var pc := HeroFactory.make_player(player, [] as Array[String])
	pc.aim_override = Hex.to_world(Vector2i(0, -4))
	var ally := HeroFactory.spawn_hero(Vector2i(-1, 1), "Follower", Color.RED, "sword", null, "gasket")
	HeroFactory.make_ally(ally, player, false, 2.4)
	var out := PackedStringArray()
	var frame := 0
	for step: Array in script_steps():
		var n: int = step[0]
		var kind: String = step[1]
		match kind:
			"coffee":
				player.set_modifier("test_coffee", 1.6, 2.0, Actor.STAT_MOVE_SPEED)
			"draw":
				player.start_draw()
			"undraw":
				player.cancel_draw()
		for i in n:
			match kind:
				"dir":
					pc.move_override = step[2]
				"to":
					var to: Vector3 = Hex.to_world(step[2]) - player.global_position
					to.y = 0.0
					pc.move_override = to.normalized() if to.length() > 0.3 else Vector3.ZERO
				_:
					pc.move_override = Vector3.ZERO
			await tree.physics_frame
			frame += 1
			var p := player.global_position
			var a := ally.global_position
			out.append("%d %.5f %.5f %.5f %.5f %.5f %.5f" % [frame, p.x, p.y, p.z, a.x, a.y, a.z])
	world.queue_free()
	GameWorld.end()
	return out
