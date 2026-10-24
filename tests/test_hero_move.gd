extends TestCase
## Hero movement obeys the terrain: blocked by a +3 ledge, slower on a +2 climb;
## camera-relative input mapping and mouse ray math in PlayerController.

var root: Node3D


func _row_map(levels: Array) -> HexMap:
	var m := HexMap.new()
	for i in levels.size():
		m.set_cell(Vector2i(i, 0), levels[i])
	return m


func _walk(hero: Hero, dir: Vector3, seconds: float) -> void:
	var n := int(seconds * 60.0)
	for i in n:
		hero.move(dir, 1.0 / 60.0)
		await get_tree().physics_frame


func setup() -> void:
	root = Node3D.new()
	add_child(root)

	# Flat run: roughly move_speed * time.
	GameWorld.begin(_row_map([0, 0, 0, 0, 0, 0, 0, 0]), root)
	var h := HeroFactory.spawn_hero(Vector2i(0, 0), "Walker", Color.BLUE)
	var x0 := h.global_position.x
	await _walk(h, Vector3.RIGHT, 1.0)
	near(h.global_position.x - x0, h.move_speed, 0.4, "flat walking speed")
	h.queue_free()

	# +1 step is walked, a +3 ledge is a wall.
	GameWorld.begin(_row_map([0, 0, 1, 0, 6]), root)
	var h2 := HeroFactory.spawn_hero(Vector2i(0, 0), "Ledge", Color.RED)
	await _walk(h2, Vector3.RIGHT, 4.0)
	eq(h2.current_cell(), Vector2i(3, 0), "stopped at the +3 ledge (cell 3), stepped over +1")
	check(h2.global_position.x < Hex.to_world(Vector2i(4, 0)).x, "never entered the blocked cell")
	h2.queue_free()

	# +2 is a climb: slower while climbing, but passable.
	GameWorld.begin(_row_map([0, 0, 2, 2, 2, 2]), root)
	var h3 := HeroFactory.spawn_hero(Vector2i(0, 0), "Climber", Color.GREEN)
	var saw_climb := false
	var min_speed := 999.0
	var prev_x := h3.global_position.x
	for i in 360:
		h3.move(Vector3.RIGHT, 1.0 / 60.0)
		if h3.climbing:
			saw_climb = true
			min_speed = minf(min_speed, (h3.global_position.x - prev_x) * 60.0)
		prev_x = h3.global_position.x
		await get_tree().physics_frame
	check(saw_climb, "climbing flag set on +2 ledge")
	check(min_speed < h3.move_speed * 0.5, "climb is slow (%f)" % min_speed)
	check(h3.global_position.x > Hex.to_world(Vector2i(3, 0)).x, "eventually got over the ledge")
	near(h3.global_position.y, 2 * Hex.LEVEL_HEIGHT, 0.05, "stands on the +2 platform")
	h3.queue_free()

	# Camera-relative input (default iso yaw): W goes "up the screen" = -X,-Z.
	var up := PlayerController.move_direction(Vector2(0, -1))
	near(up.x, -0.7071, 0.01, "W x")
	near(up.z, -0.7071, 0.01, "W z")
	var right := PlayerController.move_direction(Vector2(1, 0))
	near(right.x, 0.7071, 0.01, "D x")
	near(right.z, -0.7071, 0.01, "D z")
	check(PlayerController.move_direction(Vector2.ZERO) == Vector3.ZERO, "no input, no move")

	# Mouse ray onto the terrain: a ray coming from the iso direction hits the +2 platform at its top.
	var hill := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 5):
		hill.set_cell(c, 0)
	for c in Hex.range_cells(Vector2i(2, 0), 1):
		hill.set_cell(c, 4)
	GameWorld.begin(hill, root)
	var target := Hex.to_world(Vector2i(2, 0), 4)
	var dir := Vector3(-1, -1.4, -1).normalized()
	var origin := target - dir * 30.0
	var hit := PlayerController.ray_to_ground(origin, dir, 0.0, GameWorld.map)
	near(hit.x, target.x, 0.05, "ray refined onto the raised cell (x)")
	near(hit.y, target.y, 0.05, "ray refined onto the raised cell (y)")

	# Off a pillar (playtest feedback 2026-10-24 item 1): a player's hero on top of a +5 cell walks off it, any height; an AI
	# hero (an ally) keeps the 3-level drop limit its paths are built for.
	GameWorld.begin(_row_map([5, 0, 0, 0]), root)
	var top := HeroFactory.spawn_hero(Vector2i(0, 0), "Stuck", Color.WHITE)
	top.is_player = true
	await _walk(top, Vector3.RIGHT, 2.0)
	check(top.current_cell() != Vector2i(0, 0), "a player's hero jumps down off a +5 pillar (now in %s)" % top.current_cell())
	top.queue_free()
	GameWorld.begin(_row_map([5, 0, 0, 0]), root)
	var ally := HeroFactory.spawn_hero(Vector2i(0, 0), "Ally", Color.GRAY)
	ally.is_player = false
	await _walk(ally, Vector3.RIGHT, 2.0)
	eq(ally.current_cell(), Vector2i(0, 0), "an AI hero keeps the drop limit")
	ally.queue_free()
	finish()
