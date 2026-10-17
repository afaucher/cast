extends TestCase
## Wick's faceted low-poly model (the Nervous Archer): builds headless with every named part on the
## shared LowPolyModel base, uses FLAT per-face normals, stays cheap, is tall and thin next to Gasket and
## Rebar, runs its shoot / bash / cast poses and works as a Hero's visual override without changing
## gameplay numbers.

const MAX_NODES := 20
const MAX_TRIS := 3500


func setup() -> void:
	var lar := WickModel.new()
	add_child(lar)
	check(lar is LowPolyModel, "WickModel extends LowPolyModel")
	var all_names: Array[String] = []
	all_names.append_array(WickModel.PART_NAMES)
	all_names.append_array(WickModel.BOW_PART_NAMES)
	for part_name in all_names:
		check(lar.has_part(part_name), "part %s exists" % part_name)
		var mi := lar.get_part(part_name)
		if mi != null:
			check(mi.mesh != null and mi.mesh.get_surface_count() == 1, "%s has a mesh" % part_name)
			check(mi.material_override != null, "%s has the low-poly material" % part_name)
	check(lar.get_part("hat").get_parent() == lar.get_part("head"), "the hat sits on the head")
	check(lar.get_part("weapon").get_parent() == lar.get_part("body"), "the bow hangs under the body")
	check(lar.get_part("string").get_parent() == lar.get_part("weapon"), "the string hangs on the bow")
	check(lar.has_own_weapon, "model carries its own weapon")

	var nodes := _count_nodes(lar)
	check(nodes <= MAX_NODES, "node count %d <= %d" % [nodes, MAX_NODES])
	check(lar.triangle_count() <= MAX_TRIS, "triangle budget %d" % lar.triangle_count())
	check(lar.triangle_count() > 400, "a real faceted mesh, not a stub (%d tris)" % lar.triangle_count())

	# flat normals: every vertex of a triangle carries that triangle's geometric normal
	var checked := 0
	for part_name in all_names:
		var arrays := lar.get_part(part_name).mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var cust: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0]
		check(cust.size() == v.size() * 4, "%s carries the outline normal in CUSTOM0" % part_name)
		for t in range(0, v.size(), 3):
			var geo := (v[t + 2] - v[t]).cross(v[t + 1] - v[t]).normalized()
			for k in 3:
				if not near(n[t + k].dot(geo), 1.0, 0.001, "%s tri %d flat normal" % [part_name, t / 3]):
					break
			checked += 1
	check(checked > 400, "checked %d triangles" % checked)

	# size: taller and thinner than the old hero and Gasket, shorter than Rebar, hat over his head
	check(lar.ui_height > 2.0 and lar.ui_height < 2.4, "about 2.1-2.3 units to the hat tip (ui_height %.2f)" % lar.ui_height)
	var dag := GasketModel.new()
	var peb := RebarModel.new()
	check(lar.ui_height > dag.ui_height + 0.3, "taller than Gasket")
	check(lar.ui_height < peb.ui_height, "shorter than Rebar")
	dag.free()
	peb.free()
	var hat_box := lar.get_part("hat").mesh.get_aabb()
	check(hat_box.size.x > 0.9, "a huge hat brim (%.2f wide)" % hat_box.size.x)
	check(hat_box.size.y > 0.4, "a tall crown (%.2f)" % hat_box.size.y)
	var tip_y := lar.get_part("body").position.y + lar.get_part("head").position.y + lar.get_part("hat").position.y + hat_box.end.y
	check(tip_y > 2.0 and tip_y < 2.4, "the hat tip is the top of him (%.2f)" % tip_y)
	var bow_box := lar.get_part("weapon").mesh.get_aabb()
	check(bow_box.size.y > 1.2, "a full-size bow (%.2f long)" % bow_box.size.y)
	check(bow_box.size.z > 0.25, "the bow is visibly curved (%.2f)" % bow_box.size.z)
	var shoulders := (WickModel.SHOULDER.x + 0.12) * 2.0
	check(shoulders < 0.9, "thin: %.2f across the shoulders" % shoulders)

	# poses: the shoot pose raises the bow and draws the string, the bash and the cast move things
	lar.idle_enabled = false
	lar.pose_preview("rest")
	var rest_bow := lar.get_part("weapon").position
	var rest_wand := lar.get_part("wand").position
	check(not lar.get_part("arrow").visible, "no arrow nocked at rest")
	var rest_string := lar.get_part("string").mesh.get_aabb().size.z
	lar.pose_preview("shoot")
	check(lar.get_part("weapon").position.distance_to(rest_bow) > 0.4, "shooting raises the bow")
	check(lar.get_part("arrow").visible, "an arrow is nocked while drawn")
	check(lar.get_part("string").mesh.get_aabb().size.z > rest_string + 0.2, "the string is pulled back")
	var arm_l := lar.get_part("arm_l")
	var arm_r := lar.get_part("arm_r")
	check(arm_l.scale.y > 0.5 and arm_l.scale.y < 1.4, "the left sleeve reaches the bow (stretch %.2f)" % arm_l.scale.y)
	check(arm_r.scale.y > 0.5 and arm_r.scale.y < 1.4, "the right sleeve reaches the string (stretch %.2f)" % arm_r.scale.y)
	lar.pose_preview("bash")
	check(lar.get_part("weapon").position.distance_to(rest_bow) > 0.3, "the bash sweeps the bow")
	lar.pose_preview("cast")
	check(lar.get_part("wand").position.distance_to(rest_wand) > 0.3, "casting raises the wand")
	lar.pose_preview("rest")
	check(lar.get_part("weapon").position.distance_to(rest_bow) < 0.01, "back to rest")
	# the real tweened poses run
	lar.shoot_pose()
	await frames(10)
	check(absf(lar.arm_kick("raise")) > 0.01, "shoot_pose raises the bow")
	await frames(60)
	lar.attack_swing()
	await frames(10)
	check(absf(lar.arm_kick("bash")) > 0.01, "attack_swing drives the bow")
	await frames(60)
	lar.cast_pose()
	await frames(10)
	check(absf(lar.arm_kick("cast")) > 0.01, "cast_pose raises the wand")
	await frames(60)
	lar.idle_enabled = true
	lar.set_downed(true)
	check(not lar.idle_enabled, "downed stops the idle")
	lar.set_downed(false)

	# ---- as a Hero's visual override ----
	var root := Node3D.new()
	add_child(root)
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 6):
		map.set_cell(c, 0)
	GameWorld.begin(map, root)
	var model := WickModel.new()
	var hero := HeroFactory.spawn_hero(Vector2i.ZERO, "You", Color(0.3, 0.55, 0.95), "sword", model)
	var plain := HeroFactory.spawn_hero(Vector2i(2, 0), "Plain", Color(0.3, 0.55, 0.95))
	await frames(2)
	check(model.get_parent() == hero.get_node("Visual"), "model sits under the hero's Visual")
	check(hero._visual.get_child_count() == 1, "no prototype body or stand-in weapon next to the model")
	check(hero._weapon == null, "no inert weapon stand-in for a model with its own weapon")
	check(plain._weapon != null, "default hero keeps its weapon")
	eq(hero.max_hp, plain.max_hp, "same hp")
	eq(hero.move_speed, plain.move_speed, "same speed")
	eq(hero.radius, plain.radius, "same radius")
	check(hero._bar.position.y > plain._bar.position.y, "health bar floats above the tall hat")
	check(hero.melee(Vector3(0, 0, -1)), "melee works")
	await frames(3)
	check(absf(model.arm_kick("bash")) > 0.0, "melee bashes with the bow")
	await frames(40)
	check(hero.shoot(Vector3(0, 0, -1)), "shoot works")
	await frames(4)
	check(absf(model.arm_kick("raise")) > 0.0, "shoot raises the bow")
	Fx.flash(hero)
	await frames(2)
	check(model.get_part("body").material_overlay != null, "hit flash overlays the model")
	hero.apply_damage(hero.max_hp + 5.0, null)
	await frames(2)
	check(hero.dead, "override hero can be downed")
	await frames(30)
	finish()


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c
