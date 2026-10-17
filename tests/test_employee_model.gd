extends TestCase
## EmployeeModel: both styles (staff, henchman) build headless on the shared LowPolyModel base with every
## named part, FLAT per-face normals, a cheap budget, a height between Gasket and Wick, and distinct
## cower / panic / follow / cheer poses.

const MAX_NODES := 20
const MAX_TRIS := 3500


func setup() -> void:
	for style in EmployeeModel.STYLES:
		var m := EmployeeModel.new(style, 1)
		add_child(m)
		check(m is LowPolyModel, "%s extends LowPolyModel" % style)
		eq(m.style, style, "style kept")
		for part_name in EmployeeModel.PART_NAMES:
			check(m.has_part(part_name), "%s has part %s" % [style, part_name])
			var mi := m.get_part(part_name)
			if mi != null:
				check(mi.mesh != null and mi.mesh.get_surface_count() == 1, "%s/%s has a mesh" % [style, part_name])
				check(mi.material_override != null, "%s/%s has the low-poly material" % [style, part_name])
		check(m.has_part("cloche") == (style == "staff"), "only the staff carries a cloche")
		check(m.get_part("hat").get_parent() == m.get_part("head"), "the hat sits on the head")
		check(m.get_part("prop").get_parent() == m.get_part("body"), "the tray / clipboard hangs under the body")
		check(_count_nodes(m) <= MAX_NODES, "%s node count %d" % [style, _count_nodes(m)])
		check(m.triangle_count() <= MAX_TRIS and m.triangle_count() > 300, "%s triangle budget %d" % [style, m.triangle_count()])
		# flat normals
		var checked := 0
		for p: MeshInstance3D in m.parts.values():
			var arrays := p.mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var cust: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0]
			check(cust.size() == v.size() * 4, "%s/%s carries the outline normal" % [style, p.name])
			for t in range(0, v.size(), 3):
				var geo := (v[t + 2] - v[t]).cross(v[t + 1] - v[t]).normalized()
				if not near(n[t].dot(geo), 1.0, 0.001, "%s/%s tri %d flat normal" % [style, p.name, t / 3]):
					break
				checked += 1
		check(checked > 300, "%s checked %d triangles" % [style, checked])

		# size: between Gasket and Wick, shorter than a hero in the helmet-less staff case
		var wick := WickModel.new()
		check(m.ui_height < wick.ui_height - 0.15, "%s is shorter than Wick (%.2f vs %.2f)" % [style, m.ui_height, wick.ui_height])
		check(m.ui_height > 1.6, "%s is a full-size adult (%.2f)" % [style, m.ui_height])
		wick.free()

		# moods
		m.idle_enabled = false
		m.pose_preview("stand")
		var stand_body := m.get_part("body").position.y
		var stand_arm := m.get_part("arm_l").quaternion
		m.pose_preview("cower")
		check(m.get_part("body").position.y < stand_body - 0.25, "%s crouches when cowering" % style)
		check(m.get_part("arm_l").quaternion.angle_to(stand_arm) > 0.8, "%s covers its head" % style)
		m.pose_preview("panic", 0.6, 3.6)
		check(m.get_part("mouth").scale.y > 2.5, "%s screams" % style)
		check(m.get_part("arm_r").quaternion.angle_to(stand_arm) > 0.8, "%s flails its arms" % style)
		var run_a := m.get_part("leg_l").rotation.x
		m.pose_preview("panic", 0.65, 3.6)
		check(absf(m.get_part("leg_l").rotation.x - run_a) > 0.1, "%s legs are running" % style)
		m.pose_preview("follow", 0.6, 3.0)
		check(absf(m.get_part("leg_l").rotation.x) > 0.05 or absf(m.get_part("leg_r").rotation.x) > 0.05, "%s walks" % style)
		m.pose_preview("cheer")
		check(m.get_part("arm_l").position.y + 0.0 > 0.0, "%s cheer pose builds" % style)
		check(m.get_part("arm_l").quaternion.angle_to(stand_arm) > 2.0, "%s raises its arms to cheer" % style)
		m.set_scared(true)
		m.pose_preview("stand")
		check(m.get_part("arm_l").quaternion.angle_to(stand_arm) > 0.2, "%s wrings its hands when scared" % style)
		m.set_scared(false)
		m.set_downed(true)
		check(not m.idle_enabled, "downed stops the idle")
		m.set_fade(0.0)
		check(m.scale.x < 0.01, "fade shrinks the model away")
		m.free()
	finish()


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c
