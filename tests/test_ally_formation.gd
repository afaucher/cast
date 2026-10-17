extends TestCase
## AllyBrain formation and personal space: idle allies settle 2.5-3.5 hexes from the leader at distinct
## angles and keep their distance from each other; an ally standing in a walking leader's path in a
## corridor steps aside (three-wide) or falls behind (one-wide) instead of blocking.

var root: Node3D


func _strip(rows: Array[int], length: int) -> HexMap:
	var m := HexMap.new()
	for r in rows:
		for q in range(-length / 2 - r, length - length / 2 - r):
			m.set_cell(Vector2i(q, r), 0)
	return m


func _hero(cell: Vector2i, name_: String) -> Hero:
	return HeroFactory.spawn_hero(cell, name_, Color.WHITE)


func _flat_dist(a: Hero, b: Hero) -> float:
	return GameWorld.flat_distance(a.global_position, b.global_position)


## Angle of `h` around `leader` in degrees.
func _angle(h: Hero, leader: Hero) -> float:
	var d := h.global_position - leader.global_position
	return rad_to_deg(atan2(d.z, d.x))


func _angle_gap(a: float, b: float) -> float:
	return absf(fposmod(a - b + 180.0, 360.0) - 180.0)


func setup() -> void:
	root = Node3D.new()
	add_child(root)
	await _check_formation()
	var wide: Array[int] = [-1, 0, 1]
	var narrow: Array[int] = [0]
	await _check_corridor(wide, true)
	await _check_corridor(narrow, false)
	finish()


func _check_formation() -> void:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 14):
		m.set_cell(c, 0)
	GameWorld.begin(m, root, 1)
	var leader := _hero(Vector2i(0, 0), "Leader")
	var a := _hero(Vector2i(1, 0), "Rebar")
	var b := _hero(Vector2i(0, 1), "Gasket")   # both start right on top of the leader
	HeroFactory.make_ally(a, leader, false, 2.4, 2.6)
	HeroFactory.make_ally(b, leader, false, 3.9, 3.3)
	await frames(60 * 6)
	var hex := AllyBrain.HEX_STEP
	var da := _flat_dist(a, leader) / hex
	var db := _flat_dist(b, leader) / hex
	check(da >= 2.5 - 0.6 and da <= 3.5 + 0.6, "Rebar settles %.2f hexes from the leader (2.5-3.5)" % da)
	check(db >= 2.5 - 0.6 and db <= 3.5 + 0.6, "Gasket settles %.2f hexes from the leader (2.5-3.5)" % db)
	check(_angle_gap(_angle(a, leader), _angle(b, leader)) >= 40.0, "distinct angles around the leader (%.0f vs %.0f)" % [_angle(a, leader), _angle(b, leader)])
	check(_flat_dist(a, b) >= AllyBrain.PERSONAL_SPACE, "the two allies keep their distance (%.2f)" % _flat_dist(a, b))
	check(_flat_dist(a, leader) >= AllyBrain.PERSONAL_SPACE and _flat_dist(b, leader) >= AllyBrain.PERSONAL_SPACE, "and give the leader room")
	# Crowded on purpose: an idle ally on top of the other backs off.
	b.global_position = a.global_position + Vector3(0.5, 0, 0)
	await frames(60 * 4)
	check(_flat_dist(a, b) >= AllyBrain.PERSONAL_SPACE - 0.2, "personal space restored after a crowding (%.2f)" % _flat_dist(a, b))
	# The ally formation constants match the brief.
	check(AllyBrain.FORMATION_HEX_MIN == 2.5 and AllyBrain.FORMATION_HEX_MAX == 3.5, "formation is 2.5-3.5 hexes")
	for h in [leader, a, b]:
		h.queue_free()
	await frames(3)


## The leader walks +x down a corridor with an ally standing in its path.
func _check_corridor(rows: Array[int], can_step_aside: bool) -> void:
	var label := "3-wide corridor" if can_step_aside else "1-wide hall"
	GameWorld.begin(_strip(rows, 40), root, 2)
	var leader := _hero(Vector2i(-12, 0), "Leader")
	var ally := _hero(Vector2i(-10, 0), "Ally")
	var brain := HeroFactory.make_ally(ally, leader, false, 2.4, 2.5)
	await frames(30)
	var dir := Vector3.RIGHT
	var start_x := leader.global_position.x
	var blocked_frames := 0
	for i in 60 * 5:
		leader.move(dir, 1.0 / 60.0)
		await get_tree().physics_frame
		if i > 90:   # give it a moment to react
			var rel := ally.global_position - leader.global_position
			if rel.x > -0.2 and rel.x < AllyBrain.BLOCK_AHEAD and absf(rel.z) < AllyBrain.BLOCK_LANE:
				blocked_frames += 1
	check(leader.global_position.x - start_x > 8.0, "%s: the leader walked on (%.1f)" % [label, leader.global_position.x - start_x])
	check(blocked_frames < 60, "%s: the ally does not keep blocking the leader (%d frames in its path)" % [label, blocked_frames])
	var rel_end := ally.global_position - leader.global_position
	check(not (rel_end.x > -0.2 and rel_end.x < AllyBrain.BLOCK_AHEAD and absf(rel_end.z) < AllyBrain.BLOCK_LANE), "%s: the ally ends up out of the lane (%s)" % [label, str(rel_end)])
	if can_step_aside:
		check(ally.global_position.x > leader.global_position.x - AllyBrain.FORMATION_HEX_MAX * AllyBrain.HEX_STEP - 3.0, "%s: it kept up with the leader" % label)
	brain.queue_free()
	leader.queue_free()
	ally.queue_free()
	await frames(3)
