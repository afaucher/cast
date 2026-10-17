extends TestCase
## Gasket's faceted low-poly model: builds headless with every named part on the shared LowPolyModel
## base, uses FLAT per-face normals, stays cheap, is short and wide next to Rebar, animates her own
## wrench (swing / spin) and works as a Hero's visual override without changing gameplay numbers.

const MAX_NODES := 20
const MAX_TRIS := 3500


func setup() -> void:
	var dag := GasketModel.new()
	add_child(dag)
	check(dag is LowPolyModel, "GasketModel extends LowPolyModel")
	for part_name in GasketModel.PART_NAMES:
		check(dag.has_part(part_name), "part %s exists" % part_name)
		var mi := dag.get_part(part_name)
		if mi != null:
			check(mi.mesh != null and mi.mesh.get_surface_count() == 1, "%s has a mesh" % part_name)
			check(mi.material_override != null, "%s has the low-poly material" % part_name)
	check(dag.get_part("goggles").get_parent() == dag.get_part("head"), "goggles sit on the head")
	check(dag.get_part("weapon").get_parent() == dag.get_part("body"), "the wrench hangs under the body")
	check(dag.has_own_weapon, "model carries its own weapon")

	var nodes := _count_nodes(dag)
	check(nodes <= MAX_NODES, "node count %d <= %d" % [nodes, MAX_NODES])
	check(dag.triangle_count() <= MAX_TRIS, "triangle budget %d" % dag.triangle_count())
	check(dag.triangle_count() > 400, "a real faceted mesh, not a stub (%d tris)" % dag.triangle_count())

	# flat normals: every vertex of a triangle carries that triangle's geometric normal
	var checked := 0
	for part_name in GasketModel.PART_NAMES:
		var arrays := dag.get_part(part_name).mesh.surface_get_arrays(0)
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

	# size: short next to Rebar and the old hero, with a beard wider than her head and a wrench taller than her
	check(dag.ui_height > 1.4 and dag.ui_height < 1.9, "about 1.5-1.8 units tall (ui_height %.2f)" % dag.ui_height)
	var peb := RebarModel.new()
	check(dag.ui_height < peb.ui_height * 0.65, "much shorter than Rebar")
	peb.free()
	var beard := dag.get_part("beard")
	check(beard.mesh.get_aabb().size.x > 0.55, "a broad beard (%.2f wide)" % beard.mesh.get_aabb().size.x)
	check(beard.mesh.get_aabb().size.y > 0.5, "a long beard (%.2f tall)" % beard.mesh.get_aabb().size.y)
	var wrench_h := dag.get_part("weapon").mesh.get_aabb().size.y
	check(wrench_h > dag.ui_height, "the wrench (%.2f) is longer than she is tall" % wrench_h)

	# her own wrench animates: the swing kicks it, the spin turns her all the way round
	dag.idle_enabled = false
	dag.apply_idle(0.0)
	var rest_pos := dag.get_part("weapon").position
	dag._arm_kick["weapon"] = 1.0
	dag.apply_idle(0.0)
	check(dag.get_part("weapon").position.distance_to(rest_pos) > 0.3, "wind-up lifts the wrench")
	var arm_r := dag.get_part("arm_r")
	check(arm_r.scale.y > 0.4 and arm_r.scale.y < 1.6, "the right sleeve stays reaching her fist (stretch %.2f)" % arm_r.scale.y)
	dag._arm_kick["weapon"] = 0.0
	dag.apply_idle(0.0)
	dag.attack_swing()
	await frames(10)
	check(absf(dag.arm_kick("weapon")) > 0.01, "attack_swing drives the wrench")
	await frames(40)
	dag.idle_enabled = true
	dag.rotation.y = 0.0
	dag.spin(0.3)
	await frames(8)
	check(absf(dag.rotation.y) > 0.2, "spin turns her")
	await frames(40)
	var end_yaw := fposmod(dag.rotation.y, TAU)
	check(end_yaw < 0.05 or end_yaw > TAU - 0.05, "spin ends a full 360 turn later (yaw %.2f)" % dag.rotation.y)

	# ---- as a Hero's visual override ----
	var root := Node3D.new()
	add_child(root)
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 6):
		map.set_cell(c, 0)
	GameWorld.begin(map, root)
	var model := GasketModel.new()
	var hero := HeroFactory.spawn_hero(Vector2i.ZERO, "Wren", Color(0.7, 0.4, 0.85), "staff", model)
	var plain := HeroFactory.spawn_hero(Vector2i(2, 0), "Plain", Color(0.3, 0.55, 0.95))
	await frames(2)
	check(model.get_parent() == hero.get_node("Visual"), "model sits under the hero's Visual")
	check(hero._visual.get_child_count() == 1, "no prototype body or stand-in weapon next to the model")
	check(hero._weapon == null, "no inert weapon stand-in for a model with its own weapon")
	check(plain._weapon != null, "default hero keeps its weapon")
	eq(hero.max_hp, plain.max_hp, "same hp")
	eq(hero.move_speed, plain.move_speed, "same speed")
	eq(hero.radius, plain.radius, "same radius")
	check(hero._bar.position.y < plain._bar.position.y + 0.1, "health bar floats just above the short model")
	check(hero.melee(Vector3(0, 0, -1)), "melee works")
	await frames(3)
	check(absf(model.arm_kick("weapon")) > 0.0, "melee swings her wrench")
	check(hero.shoot(Vector3(0, 0, -1)), "shoot works")
	await frames(3)
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
