extends TestCase
## The faceted monster models (grunt skeleton, archer, brute, swarmer imp, and the design-only goblin scout
## from MonsterModels.DESIGN_KINDS): each builds headless
## with its named parts on the shared LowPolyModel base, uses FLAT per-face normals, stays cheap, glows
## only where it should (heroes never do), and its windup / swing / downed / tint / fade hooks run.

const MAX_NODES := 20
## kind -> triangle budget
var BUDGET := _budgets()   # each kind's MonsterDefs "tris"


static func _budgets() -> Dictionary:
	var out := {}
	for k in MonsterDefs.model_kinds():
		out[k] = int(MonsterDefs.row(k)["tris"])
	return out


func _part_names(kind: String) -> Array[String]:
	match kind:
		"grunt":
			return GruntModel.PART_NAMES
		"archer":
			return ArcherModel.PART_NAMES
		"brute":
			return BruteModel.PART_NAMES
		"goblin":
			return GoblinModel.PART_NAMES
		_:
			return SwarmerModel.PART_NAMES


func setup() -> void:
	check(MonsterModels.make("nope") == null, "unknown kind gives null")
	var heights := {}
	var all_kinds: Array[String] = []
	all_kinds.append_array(MonsterModels.KINDS)
	all_kinds.append_array(MonsterModels.DESIGN_KINDS)
	for kind in all_kinds:
		var m := MonsterModels.make(kind)
		check(m != null, "%s model made" % kind)
		if m == null:
			continue
		add_child(m)
		check(m is MonsterModel and m is LowPolyModel, "%s extends LowPolyModel" % kind)
		eq(m.monster_kind, kind, "%s monster_kind" % kind)
		heights[kind] = m.ui_height
		_check_parts(kind, m)
		_check_budget(kind, m)
		_check_flat_normals(kind, m)
		_check_glow(kind, m)
		await _check_poses(kind, m)

	# silhouettes keep their gameplay sizes: imp < skeleton ~ archer < brute
	check(heights["swarmer"] < heights["grunt"], "swarmer is smaller than the grunt")
	check(heights["grunt"] < heights["brute"] and heights["archer"] < heights["brute"], "brute is the tallest")
	check(heights["swarmer"] > 0.5, "swarmer is not tiny")
	# the goblin scout: bigger than an imp, under the brute (his bar sits above the rocket rack)
	check(heights["goblin"] > heights["swarmer"] and heights["goblin"] < heights["brute"], "goblin sits between the imp and the brute")
	await _check_goblin_poses()

	# heroes stay matte: nothing in Rebar glows
	var peb := RebarModel.new()
	add_child(peb)
	var glowing := 0
	for part_name in RebarModel.PART_NAMES:
		for c: Color in peb.get_part(part_name).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
			if c.a < 0.75:
				glowing += 1
	eq(glowing, 0, "hero faces never use the glow alpha")

	# the monster material is the hero shader plus the enemy patches
	var mat := MonsterMaterial.make()
	check(mat.shader.code.contains("glow_gain") and mat.shader.code.contains("tint_k"), "monster shader has glow + tint")
	check(mat.shader.code.contains("amber_rim"), "monster shader keeps the hero rim")
	check(mat.next_pass != null, "monster material has the ink outline pass")
	finish()


func _check_parts(kind: String, m: MonsterModel) -> void:
	for part_name in _part_names(kind):
		check(m.has_part(part_name), "%s part %s exists" % [kind, part_name])
		var mi := m.get_part(part_name)
		if mi != null:
			check(mi.mesh != null and mi.mesh.get_surface_count() == 1, "%s/%s has a mesh" % [kind, part_name])
			check(mi.material_override != null, "%s/%s has the monster material" % [kind, part_name])
	var nodes := _count_nodes(m)
	check(nodes <= MAX_NODES, "%s node count %d <= %d" % [kind, nodes, MAX_NODES])


func _check_budget(kind: String, m: MonsterModel) -> void:
	var tris := m.triangle_count()
	check(tris > 200, "%s has real geometry (%d tris)" % [kind, tris])
	check(tris <= int(BUDGET[kind]), "%s triangle budget %d <= %d" % [kind, tris, int(BUDGET[kind])])
	print("  %s: %d tris, %d nodes, ui_height %.2f" % [kind, tris, _count_nodes(m), m.ui_height])


## Every vertex of a triangle carries that triangle's geometric normal, and corners are shared.
func _check_flat_normals(kind: String, m: MonsterModel) -> void:
	var shared := 0
	var distinct := 0
	var bad := 0
	for part_name in _part_names(kind):
		var arrays := m.get_part(part_name).mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var normals_at := {}
		for t in range(0, v.size(), 3):
			var geo := (v[t + 2] - v[t]).cross(v[t + 1] - v[t]).normalized()
			for k in 3:
				if n[t + k].dot(geo) < 0.999:
					bad += 1
				var key := LowPoly.key(v[t + k])
				if not normals_at.has(key):
					normals_at[key] = []
				normals_at[key].append(n[t + k])
		for key in normals_at:
			var list: Array = normals_at[key]
			if list.size() > 1:
				shared += 1
				for other: Vector3 in list:
					if other.dot(list[0]) < 0.999:
						distinct += 1
						break
	eq(bad, 0, "%s: every vertex carries its face normal" % kind)
	check(shared > 40, "%s meshes share corner positions (%d)" % [kind, shared])
	check(distinct > shared / 2, "%s: most shared corners keep distinct per-face normals (%d of %d)" % [kind, distinct, shared])


## Enemies glow (ember eyes): some faces carry the glow alpha, but only a small part of the surface.
func _check_glow(kind: String, m: MonsterModel) -> void:
	var glow_faces := 0
	var faces := 0
	for part_name in _part_names(kind):
		var cols: PackedColorArray = m.get_part(part_name).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		for i in range(0, cols.size(), 3):
			faces += 1
			if cols[i].a < 0.75:
				glow_faces += 1
	check(glow_faces >= 4, "%s has emissive faces (eyes) (%d)" % [kind, glow_faces])
	check(glow_faces < faces / 4, "%s glows only in small places (%d of %d faces)" % [kind, glow_faces, faces])


## All part transforms flattened into one list, to see a pose change.
func _snapshot(m: MonsterModel) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var names: Array = m.parts.keys()
	names.sort()
	for n: String in names:
		out.append((m.parts[n] as MeshInstance3D).transform)
	return out


func _pose_distance(a: Array[Transform3D], b: Array[Transform3D]) -> float:
	var d := 0.0
	for i in a.size():
		d = maxf(d, (a[i].origin - b[i].origin).length())
		d = maxf(d, (a[i].basis.x - b[i].basis.x).length())
		d = maxf(d, (a[i].basis.y - b[i].basis.y).length())
		d = maxf(d, (a[i].basis.z - b[i].basis.z).length())
	return d


func _check_poses(kind: String, m: MonsterModel) -> void:
	m.idle_enabled = false      # freeze the idle loop so poses are exactly comparable
	m._t = 0.6
	m.apply_idle(0.6)
	var rest := _snapshot(m)
	m.apply_idle(0.6, 5.0)
	check(_pose_distance(rest, _snapshot(m)) > 0.05, "%s walk cycle moves the limbs" % kind)
	m.apply_idle(0.6)

	m.windup(1.0)
	var wound := _snapshot(m)
	check(_pose_distance(rest, wound) > 0.3, "%s windup(1) strikes a clearly different pose (%.2f)" % [kind, _pose_distance(rest, wound)])
	m.windup(0.5)
	var half := _snapshot(m)
	check(_pose_distance(rest, half) > 0.05 and _pose_distance(half, wound) > 0.05, "%s windup(0.5) is in between" % kind)
	m.windup(0.0)
	check(_pose_distance(rest, _snapshot(m)) < 0.001, "%s windup(0) returns to rest" % kind)

	m.attack_swing()
	check(_pose_distance(rest, _snapshot(m)) > 0.2, "%s attack_swing snaps into a swing pose" % kind)
	m.idle_enabled = true
	await get_tree().create_timer(MonsterModel.SWING_TIME + 0.25).timeout
	m.idle_enabled = false
	m.apply_idle(0.6)
	check(_pose_distance(rest, _snapshot(m)) < 0.001, "%s swing settles back to rest" % kind)

	# tint + fade
	m.set_tint(Color.WHITE, 0.9)
	near(float((m._mat as ShaderMaterial).get_shader_parameter("tint_k")), 0.9, 0.001, "%s tint_k" % kind)
	m.set_tint(Color.WHITE, 0.0)
	var s0 := m.scale
	m.set_fade(0.5)
	check(m.scale.x < s0.x * 0.6, "%s set_fade shrinks the model" % kind)
	m.set_fade(1.0)
	near(m.scale.x, s0.x, 0.0001, "%s set_fade(1) restores the scale" % kind)

	# downed: greyed, glow out, idle stops, windup / swing are ignored; revive works
	m.set_downed(true)
	check(m.is_downed() and not m.idle_enabled, "%s downed" % kind)
	near(float((m._mat as ShaderMaterial).get_shader_parameter("glow_gain")), 0.0, 0.0001, "%s glow out when downed" % kind)
	near(float((m._mat as ShaderMaterial).get_shader_parameter("desat")), 0.85, 0.0001, "%s greyed when downed" % kind)
	var slack := _snapshot(m)
	check(_pose_distance(rest, slack) > 0.1, "%s goes slack when downed" % kind)
	m.attack_swing()
	m.windup(1.0)
	check(_pose_distance(slack, _snapshot(m)) < 0.001, "%s ignores windup / swing while downed" % kind)
	m.set_downed(false)
	check(not m.is_downed(), "%s can be revived" % kind)
	near(float((m._mat as ShaderMaterial).get_shader_parameter("glow_gain")), MonsterModel.GLOW_GAIN * (1.0 + m.glow_flare * m.wind_e()), 0.01, "%s glow back" % kind)
	m.idle_enabled = true
	m.windup(0.0)


## The goblin's own pose hooks (alert, look-around, fuse sparks, rockets fired, cower) each change the pose,
## and switching them off returns exactly to rest.
func _check_goblin_poses() -> void:
	var g := GoblinModel.new()
	add_child(g)
	g.idle_enabled = false
	g._t = 0.6                  # the hooks re-pose at the model's own clock
	g.apply_idle(0.6)
	var rest := _snapshot(g)
	check(not g.get_part("mark").visible and not g.get_part("spark").visible and g.get_part("rockets").visible, "goblin rest: no mark, no sparks, rack loaded")
	g.set_alert(1.0)
	check(_pose_distance(rest, _snapshot(g)) > 0.3 and g.get_part("mark").visible, "goblin alert pose + the ! mark")
	g.set_alert(0.0)
	g.set_look(1.0, 0.25)
	check(_pose_distance(rest, _snapshot(g)) > 0.2, "goblin look-around pose")
	g.set_look(0.0)
	g.set_fuse_lit(true)
	check(g.get_part("spark").visible, "goblin fuse sparks show")
	g.set_fuse_lit(false)
	g.set_loaded(false)
	check(not g.get_part("rockets").visible, "goblin rockets gone after the volley")
	g.set_loaded(true)
	g.set_cower(1.0)
	check(_pose_distance(rest, _snapshot(g)) > 0.3, "goblin cower pose")
	g.set_cower(0.0)
	check(_pose_distance(rest, _snapshot(g)) < 0.001, "goblin hooks off: back to rest")
	g.pose_scout("fuse_run")
	check(_pose_distance(rest, _snapshot(g)) > 0.3, "goblin fuse_run pose")
	g.pose_scout("rest")
	check(_pose_distance(rest, _snapshot(g)) < 0.001, "goblin pose_scout(rest) is the rest pose")
	g.queue_free()
	await get_tree().process_frame


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c
