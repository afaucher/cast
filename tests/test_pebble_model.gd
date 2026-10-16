extends TestCase
## Pebble's faceted low-poly model: builds headless with every named part, uses FLAT per-face
## normals (adjacent faces never share a smoothed normal), stays cheap, and works as a Hero's
## visual override (swing, hit flash, downed) without changing the hero's gameplay numbers.

const MAX_NODES := 20
const MAX_TRIS := 2500


func setup() -> void:
	var peb := PebbleModel.new()
	add_child(peb)
	for part_name in PebbleModel.PART_NAMES:
		check(peb.has_part(part_name), "part %s exists" % part_name)
		var mi := peb.get_part(part_name)
		if mi != null:
			check(mi.mesh != null and mi.mesh.get_surface_count() == 1, "%s has a mesh" % part_name)
			check(mi.material_override != null, "%s has the low-poly material" % part_name)
	check(peb.get_part("glove_l").get_parent() == peb.get_part("arm_l"), "glove hangs under its arm")

	# node count is modest
	var nodes := _count_nodes(peb)
	check(nodes <= MAX_NODES, "node count %d <= %d" % [nodes, MAX_NODES])
	check(peb.triangle_count() <= MAX_TRIS, "triangle budget %d" % peb.triangle_count())

	# flat normals: every vertex of a triangle carries that triangle's geometric normal
	var shared_positions := 0
	var distinct_at_shared := 0
	for part_name in PebbleModel.PART_NAMES:
		var arrays := peb.get_part(part_name).mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var normals_at := {}   # position -> Array of normals
		for t in range(0, v.size(), 3):
			# Godot front faces are clockwise: the outward geometric normal is (c-a) x (b-a)
			var geo := (v[t + 2] - v[t]).cross(v[t + 1] - v[t]).normalized()
			for k in 3:
				if not near(n[t + k].dot(geo), 1.0, 0.001, "%s tri %d flat normal" % [part_name, t / 3]):
					break
				var key := LowPoly.key(v[t + k])
				if not normals_at.has(key):
					normals_at[key] = []
				normals_at[key].append(n[t + k])
		for key in normals_at:
			var list: Array = normals_at[key]
			if list.size() > 1:
				shared_positions += 1
				for other: Vector3 in list:
					if other.dot(list[0]) < 0.999:
						distinct_at_shared += 1
						break
	check(shared_positions > 100, "meshes have many shared corner positions (%d)" % shared_positions)
	check(distinct_at_shared > shared_positions / 2, "most shared corners keep distinct per-face normals (%d of %d)" % [distinct_at_shared, shared_positions])

	# a boulder is a closed, outward-wound, faceted shape
	var boulder := LowPoly.boulder(Vector3(0.5, 0.4, 0.5), 1, 0.15, Color(0.8, 0.7, 0.5), 3).to_mesh()
	var ba := boulder.surface_get_arrays(0)
	var bv: PackedVector3Array = ba[Mesh.ARRAY_VERTEX]
	var bn: PackedVector3Array = ba[Mesh.ARRAY_NORMAL]
	check(bv.size() == 80 * 3, "detail-1 boulder has 80 faces, got %d" % (bv.size() / 3))
	var outward := 0
	for t in range(0, bv.size(), 3):
		if bn[t].dot((bv[t] + bv[t + 1] + bv[t + 2]) / 3.0) > 0.0:
			outward += 1
	check(outward == 80, "boulder normals point outward (%d/80)" % outward)
	var cust: PackedByteArray = ba[Mesh.ARRAY_CUSTOM0]
	check(cust.size() == bv.size() * 4, "outline normal in CUSTOM0")

	# ---- as a Hero's visual override ----
	var root := Node3D.new()
	add_child(root)
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 6):
		map.set_cell(c, 0)
	GameWorld.begin(map, root)
	var model := PebbleModel.new()
	var hero := HeroFactory.spawn_hero(Vector2i.ZERO, "Brom", Color(0.85, 0.5, 0.25), "sword", model)
	var plain := HeroFactory.spawn_hero(Vector2i(2, 0), "Plain", Color(0.3, 0.55, 0.95))
	await frames(2)
	check(model.get_parent() == hero.get_node("Visual"), "model sits under the hero's Visual")
	check(hero._visual.get_child_count() == 2, "no prototype body next to the override")
	check(plain._visual.get_child_count() > 2, "default hero keeps its prototype body")
	eq(hero.max_hp, plain.max_hp, "same hp")
	eq(hero.move_speed, plain.move_speed, "same speed")
	eq(hero.radius, plain.radius, "same radius")
	check(hero._bar.position.y > plain._bar.position.y, "health bar floats above the taller model")
	check(hero.melee(Vector3(0, 0, -1)), "melee works")
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
