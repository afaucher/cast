extends TestCase
## The necro look test (docs/design/necro-look.md, LOOK-DEV ONLY): the zombie, acolyte and grimoire builders run headless
## (every variant, pose and state), the grimoire never carries text, the gym's necro spawns (GymSpawns "necro") put plain
## cosmetic NecroBody nodes down that loop their poses, the panel's two rows (NecroLook.pick) and the Ghost colour redress
## them, the real grunt is untouched, and the look lab's builders run headless.

const LAB := "res://scripts/art/lowpoly/necro/necro_look_lab.gd"

var root: Node3D


func setup() -> void:
	NecroLook.reset()
	GhostLook.reset()
	_check_entries()
	_check_experiments()
	_check_zombies()
	_check_acolytes()
	_check_grimoires()
	await _check_gym_spawns()
	await _check_lab()
	NecroLook.reset()
	GhostLook.reset()
	finish()


func _check_entries() -> void:
	check(GymSpawns.GROUPS.has("necro"), "the necro group is listed")
	var n := 0
	for r: Array in NecroBody.entries():
		var e := GymSpawns.find("necro:" + NecroBody.key_of(r[0], r[1], r[2]))
		if check(not e.is_empty(), "necro:%s:%s:%s is a gym entry" % r):
			eq(str(e["skip"]), "", "it has a button")
			n += 1
	eq(n, 2 * 4 + 2 * 3 + 2, "two zombies in four poses, two acolytes in three, the grimoire on two stands")
	eq(NecroBody.label_of("zombie", "digger", "rising"), "zombie (digger): rising", "a figure's button label")
	eq(NecroBody.label_of("grimoire", "altar", "state"), "grimoire: altar", "a grimoire's button label")


func _check_experiments() -> void:
	var rows := {}
	for row: Array in GymDev.experiments():
		rows[str(row[0])] = row
	check(rows.has("necro_rim") and rows.has("grimoire"), "the panel has the Necro rim and Grimoire pickers")
	eq(str(rows["necro_rim"][1]), "Necro rim", "its label")
	eq(str(rows["grimoire"][2]), str(["open", "damaged", "shut", "burnt"]), "the grimoire's states")
	check(not NecroLook.pick("grimoire", "nope"), "an unknown state is refused")
	check(not NecroLook.pick("necro_nope", "on"), "an unknown switch is refused")
	eq(NecroLook.grimoire, "open", "a refused pick changes nothing")


func _check_zombies() -> void:
	for v: String in ZombieModel.VARIANTS:
		for charred: bool in [false, true]:
			var z := ZombieModel.new(v, charred)
			for p: String in ZombieModel.PART_NAMES:
				check(z.has_part(p), "%s%s has its %s" % [v, " (burnt)" if charred else "", p])
			check(z.triangle_count() < 3000, "%s is a cheap model (%d tris)" % [v, z.triangle_count()])
			var m := (z.get_part("body") as MeshInstance3D).material_override as ShaderMaterial
			check(m.shader.code.contains("ghost_rim"), "%s wears the ghost rim's toon body" % v)
			near(float(m.get_shader_parameter("ghost_rim")), 0.0 if charred else NecroLook.RIM, 0.0001, "%s: the rim (none burnt)" % v)
			check(m.next_pass is ShaderMaterial and (m.next_pass as ShaderMaterial).shader.code == LowPolyMaterial.OUTLINE_SHADER,
					"%s keeps the ink outline (a body, not a ghost)" % v)
			check(_glows(z, NecroLook.glow_colour()) != charred, "%s: its eyes glow in the ghost colour%s" % [v, " (out when burnt)" if charred else ""])
			# standing, then down: lying low, the rise mark (or smoke) under it, then back up
			var head_up := (z.get_part("head") as Node3D).position
			z.apply_idle(0.6, 0.0)
			var stood := _world_y(z, "head")
			z.pose_rise(0.0)
			check(z.is_lying() and _world_y(z, "head") < stood * 0.4, "%s lies down (head %.2f, standing %.2f)" % [v, _world_y(z, "head"), stood])
			var flat := _world_y(z, "head")
			z.pose_rise(1.0)
			check(_world_y(z, "head") > flat + 0.1, "%s pushes up on its arms to rise" % v)
			check(z.rise_fx != null and z.rise_fx.visible, "%s: motes (smoke when burnt) while down" % v)
			check(z.find_children("*", "MeshInstance3D", false, false).filter(func(n: Node) -> bool: return not z.parts.values().has(n)).is_empty(), "%s: no glow ring on the floor" % v)
			z.stand_up()
			check(not z.is_lying() and z.rise_fx != null and not z.rise_fx.visible, "%s stands back up" % v)
			check((z.get_part("head") as Node3D).position.is_equal_approx(head_up), "the head stays on its neck")
			z.free()
	# the rim switch
	NecroLook.rim = false
	var off := ZombieModel.new("mourner")
	near(float(((off.get_part("body") as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("ghost_rim")), 0.0, 0.0001,
			"Necro rim off: no rim")
	off.free()
	NecroLook.rim = true


func _check_acolytes() -> void:
	for v: String in AcolyteModel.VARIANTS:
		var a := AcolyteModel.new(v)
		for p: String in AcolyteModel.PART_NAMES:
			check(a.has_part(p), "%s has its %s" % [v, p])
		check(a.triangle_count() < 3000, "%s is a cheap model (%d tris)" % [v, a.triangle_count()])
		check(_glows(a, NecroLook.glow_colour()), "%s carries the ghost colour (its eyes and its light)" % v)
		a.apply_idle(0.6, 0.0)
		check(not (a.get_part("aura_r") as Node3D).visible, "%s idle: hands unlit" % v)
		var hand_low := _hand_y(a)
		a.set_raise(1.0)
		a.apply_idle(0.6, 0.0)
		check(_hand_y(a) > hand_low + 0.5, "%s raising: hands up (%.2f from %.2f)" % [v, _hand_y(a), hand_low])
		check((a.get_part("aura_r") as Node3D).visible, "%s raising: hands lit" % v)
		a.set_raise(0.0)
		a.apply_idle(0.25, AcolyteModel.RUN_SPEED)
		check(absf((a.get_part("head") as Node3D).rotation.y) > 0.7, "%s fleeing: looks back over its shoulder" % v)
		check((a.get_part("body") as Node3D).rotation.x < -0.3, "%s fleeing: leans into the run" % v)
		a.free()


func _check_grimoires() -> void:
	for st: String in GrimoireModel.STANDS:
		for state: String in GrimoireModel.STATES:
			var g := GrimoireModel.make(st, state)
			var lit := state == "open" or state == "damaged"
			eq(g.is_lit(), lit, "%s %s: lit or not" % [st, state])
			check(g.find_child("Sigil", true, false) != null and (g.find_child("Sigil", true, false) as Node3D).visible == lit,
					"%s %s: the circle %s" % [st, state, "lit" if lit else "out"])
			check((g.find_child("Column", true, false) != null) == lit, "%s %s: the column of light %s" % [st, state, "up" if lit else "gone"])
			check((g.find_child("BookLight", true, false) != null) == lit, "%s %s: the pale light %s" % [st, state, "on" if lit else "off"])
			check((g.find_child("Smoke", true, false) != null) == (state == "burnt"), "%s %s: smoke only when burnt" % [st, state])
			check(g.triangle_count() < 6000, "%s %s: cheap (%d tris)" % [st, state, g.triangle_count()])
			check(g.scale.x > 1.2 and g.ui_height > 3.5, "%s %s: an outsized set piece (ui height %.1f)" % [st, state, g.ui_height])
			check(_no_text(g), "%s %s: no text anywhere" % [st, state])
			g.free()
	check(not NecroLook.FLOOR_SHADER.contains("texture"), "the circle is drawn from rings and spokes, no glyph texture")


func _check_gym_spawns() -> void:
	root = Node3D.new()
	add_child(root)
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 9):
		map.set_cell(c, 0).tag = "room:0"
	GameWorld.begin(map, root, 3)
	var made := {}
	for r: Array in NecroBody.entries():
		var key := NecroBody.key_of(r[0], r[1], r[2])
		var out := GymSpawns.spawn(GymSpawns.find("necro:" + key), Vector3.ZERO, 1, null, null)
		if check(out.size() == 1 and out[0] is NecroBody, "%s spawns one NecroBody" % key):
			var b := out[0] as NecroBody
			made[key] = b
			check(not (out[0] is Actor) and b.is_in_group(GhostLook.GROUP), "a cosmetic node in the ghost group")
			check(b.get_parent() == GameWorld.root, "under the world")
	await frames(2)
	if made.size() != NecroBody.entries().size():
		return
	# the loops run: a shamble walks its line, a rising zombie pushes up, an acolyte raises its zombie
	var walker: NecroBody = made["zombie:mourner:shamble"]
	var riser: NecroBody = made["zombie:digger:rising"]
	var raiser: NecroBody = made["acolyte:cowl:raise"]
	walker.pose_at(0.5)
	var p0 := walker.model.position
	walker.pose_at(1.5)
	check(walker.model.position.distance_to(p0) > 0.5, "the shambler walks its line")
	walker.pose_at(NecroBody.SHAMBLE_LEN / ZombieModel.WALK_SPEED + 0.5)
	check(absf(walker.model.rotation.y - PI) < 0.01, "and turns back at its end")
	riser.t = 3.5
	raiser.t = 3.0
	await frames(2)
	check((riser.model as ZombieModel).rise_k() > 0.3, "the riser pushes up (k %.2f)" % (riser.model as ZombieModel).rise_k())
	check((raiser.model as AcolyteModel).raise_k() > 0.99 and raiser.raised != null and raiser.raised.is_lying(), "the acolyte raises its zombie")
	# the panel's rows and the ghost colour redress them
	var lec: NecroBody = made["grimoire:lectern:state"]
	eq((lec.model as GrimoireModel).state, "open", "a grimoire starts open")
	check(NecroLook.pick("grimoire", "shut"), "pick shut")
	eq((lec.model as GrimoireModel).state, "shut", "the grimoire slams shut live")
	check(lec.model.find_child("Column", true, false) == null, "its column gone")
	check(NecroLook.pick("necro_rim", "off"), "pick rim off")
	var zm := (made["zombie:mourner:stand"] as NecroBody).model as ZombieModel
	near(float(((zm.get_part("body") as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("ghost_rim")), 0.0, 0.0001,
			"the zombies lose their rim live")
	NecroLook.pick("grimoire", "open")
	check(GhostLook.pick("ghost_colour", "ecto green"), "pick ecto green")
	var green: Color = GhostLook.COLOUR["ecto green"]
	var light := lec.model.find_child("BookLight", true, false) as OmniLight3D
	check(light != null and light.light_color == green, "the grimoire's light turns ecto green")
	check(_glows((made["acolyte:mask:idle"] as NecroBody).model, green), "so do the acolytes' eyes")
	GhostLook.reset()
	NecroLook.reset()
	GhostLook.refresh_all()
	# the real grunt is untouched
	var grunt := GruntModel.new()
	check(((grunt.get_part("body") as MeshInstance3D).material_override as ShaderMaterial).shader.code == MonsterMaterial._code(),
			"a real grunt still wears MonsterMaterial")
	grunt.free()
	root.queue_free()
	await frames(2)


## The lab's builders, headless: its room, its spots, a still of every pose.
func _check_lab() -> void:
	var lab: Node3D = load(LAB).new()
	add_child(lab)
	await frames(2)
	var spots: Dictionary = lab.get("spots")
	check(spots.has("bright") and spots.has("dark") and spots.has("middle"), "the lab has its spots")
	var m: HexMap = lab.get("map")
	if check(m != null, "the lab built its room"):
		var c := Hex.from_world(spots["dark"] as Vector3)
		check(m.cells.has(c) and m.cells[c].type != HexMap.Tile.WALL, "the dark corner is floor")
	for r: Array in NecroBody.entries():
		var pose: String = "open" if r[0] == "grimoire" else r[2]
		var b: NecroBody = lab.call("stage", r[0], r[1], pose, spots["bright"])
		check(b != null and not b.live and b.model != null, "the lab stages %s %s %s" % [r[0], r[1], pose])
	lab.queue_free()
	await frames(2)


## True when some face of `n`'s meshes is painted the glow (vertex alpha 0.5) in colour `col`'s hue.
func _glows(n: Node, col: Color) -> bool:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh as ArrayMesh
		if mesh == null:
			continue
		var cols = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		if cols == null:
			continue
		for c: Color in cols:
			if absf(c.a - MonsterMaterial.GLOW_ALPHA) < 0.01 and absf(c.h - col.h) < 0.06 and c.s > 0.1:
				return true
	return false


func _world_y(z: ZombieModel, part: String) -> float:
	return (z.transform.affine_inverse() * (z.get_part(part) as Node3D).global_transform.origin).y if z.is_inside_tree() \
			else _local_origin(z, z.get_part(part)).y


## A part's origin in the model's own space (works outside the tree).
func _local_origin(model: Node3D, n: Node3D) -> Vector3:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != model:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf.origin


func _hand_y(a: AcolyteModel) -> float:
	var arm := a.get_part("arm_r") as Node3D
	var xf := Transform3D.IDENTITY
	var cur: Node = arm
	while cur != null and cur != a:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return (xf * Vector3(0, -AcolyteModel.ARM_LEN, 0)).y


func _no_text(n: Node) -> bool:
	return n.find_children("*", "Label3D", true, false).is_empty() and n.find_children("*", "Label", true, false).is_empty() \
			and n.find_children("*", "Sprite3D", true, false).is_empty()
