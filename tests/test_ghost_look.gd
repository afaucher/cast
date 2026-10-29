extends TestCase
## The ghost look test (docs/design/ghost-look.md, LOOK-DEV ONLY): the gym's three ghost spawns (GymSpawns "ghost": a
## skeleton, a suit of armour, a wisp) put plain cosmetic GhostBody nodes down; the panel's three switches (GhostLook.pick,
## GymDev.set_experiment's "ghost_*" rows) change the material parameters on every ghost live; the wisp drifts round its
## spot; the real grunt's material is untouched; and the look lab's builders (its room, its dark corner, a staged cell)
## run headless.

const LAB := "res://scripts/art/lowpoly/ghost/ghost_look_lab.gd"

var root: Node3D


func setup() -> void:
	GhostLook.reset()
	_check_entries()
	_check_experiments()
	_check_shaders()
	await _check_gym_spawns()
	await _check_lab()
	GhostLook.reset()
	finish()


func _check_entries() -> void:
	for kind: String in GhostBody.KINDS:
		var e := GymSpawns.find("ghost:" + kind)
		if check(not e.is_empty(), "ghost:%s is a gym entry" % kind):
			eq(str(e["label"]), "ghost: " + kind, "its button label")
			eq(str(e["skip"]), "", "it has a button")
	check(GymSpawns.GROUPS.has("ghost"), "the ghost group is listed")


func _check_experiments() -> void:
	var rows := {}
	for row: Array in GymDev.experiments():
		rows[str(row[0])] = row
	for nm: String in ["ghost_look", "ghost_strength", "ghost_colour"]:
		check(rows.has(nm), "the panel has a %s picker" % nm)
	eq(str(rows["ghost_look"][1]), "Ghost look", "its label")
	eq(str(rows["ghost_look"][2]), str(["outline", "rim", "shimmer"]), "the looks")
	eq(str(rows["ghost_strength"][2]), str(["faint", "soft", "strong"]), "the strengths")
	eq(str(rows["ghost_colour"][2]), str(["pale blue", "ecto green"]), "the colours")
	check(not GhostLook.pick("ghost_look", "nope"), "an unknown look is refused")
	check(not GhostLook.pick("ghost_nope", "rim"), "an unknown switch is refused")
	eq(GhostLook.look, "outline", "a refused pick changes nothing")


func _check_shaders() -> void:
	var code := GhostLook.body_code()
	check(code.contains("uniform float ghost_rim"), "the ghost body declares its rim")
	check(code.contains("EMISSION += ghost_color.rgb * ghost_rim"), "the rim is added to the emission")
	check(code.contains("glow_gain"), "the ghost body is the monsters' toon shader")
	check(not MonsterMaterial._code().contains("ghost"), "the monsters' own shader has no ghost in it")
	var grunt := GruntModel.new()
	var gm := (grunt.get_part("body") as MeshInstance3D).material_override as ShaderMaterial
	check(gm.shader.code == MonsterMaterial._code(), "a real grunt still wears MonsterMaterial")
	check(gm.next_pass is ShaderMaterial and (gm.next_pass as ShaderMaterial).shader.code == LowPolyMaterial.OUTLINE_SHADER,
			"... with its ink outline")
	grunt.free()


func _check_gym_spawns() -> void:
	root = Node3D.new()
	add_child(root)
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 6):
		map.set_cell(c, 0).tag = "room:0"
	GameWorld.begin(map, root, 3)
	var ghosts := {}
	for kind: String in GhostBody.KINDS:
		var made := GymSpawns.spawn(GymSpawns.find("ghost:" + kind), Hex.to_world(Vector2i(0, 0)), 1, null, null)
		if check(made.size() == 1 and made[0] is GhostBody, "ghost: %s spawns one GhostBody" % kind):
			var g := made[0] as GhostBody
			ghosts[kind] = g
			eq(g.kind, kind, "of its kind")
			check(not (made[0] is Actor) and g.is_in_group(GhostLook.GROUP), "a cosmetic node in the ghost group")
			check(g.get_parent() == GameWorld.root, "under the world")
	var n := GymSpawns.spawn(GymSpawns.find("ghost:armour"), Vector3.ZERO, 3, null, null).size()
	eq(n, 3, "x3 puts three down")
	await frames(2)
	if ghosts.size() != 3:
		return
	var sk: GhostBody = ghosts["skeleton"]
	var ar: GhostBody = ghosts["armour"]
	var wi: GhostBody = ghosts["wisp"]
	check(sk.model is GruntModel and ar.model is ArmourModel, "the skeleton is the grunt model, the armour its own")
	for g: GhostBody in [sk, ar]:
		for p: MeshInstance3D in g.model.parts.values():
			check(p.material_override == g.base, "%s: every part wears the ghost body (%s)" % [g.kind, p.name])
	check(ar.model.triangle_count() < 2400, "the armour is a cheap blockout (%d tris)" % ar.model.triangle_count())
	# the default: outline, soft, pale blue
	var soft: Dictionary = GhostLook.STRENGTH["soft"]
	var passes := GhostLook.passes_of(sk.base)
	eq(passes.size(), 1 + GhostLook.SHELLS.size(), "outline: the body and three soft shells")
	near(float(sk.base.get_shader_parameter("ghost_rim")), 0.0, 0.0001, "outline: no rim")
	near(float((passes[1] as ShaderMaterial).get_shader_parameter("alpha")), float(soft["alpha"]) * float(GhostLook.SHELLS[0][1]), 0.0001,
			"the inner shell's alpha")
	check(not _has_ink(passes), "the ink outline is gone")
	# rim
	check(GhostLook.pick("ghost_look", "rim"), "pick rim")
	near(float(sk.base.get_shader_parameter("ghost_rim")), float(soft["rim"]), 0.0001, "rim: the body's edges glow")
	near(float(ar.base.get_shader_parameter("ghost_rim")), float(soft["rim"]), 0.0001, "rim: on the armour too")
	eq(GhostLook.passes_of(sk.base).size(), 3, "rim: the body and a faint two-shell outline")
	near(float(wi.base.get_shader_parameter("edge_k")), 1.7, 0.0001, "rim: the wisp's edges brighter")
	# shimmer
	check(GhostLook.pick("ghost_look", "shimmer"), "pick shimmer")
	passes = GhostLook.passes_of(ar.base)
	eq(passes.size(), 2 + GhostLook.SHELLS.size(), "shimmer: the body, the shells and the afterimage")
	check((passes[passes.size() - 1] as ShaderMaterial).shader.code == GhostLook.AFTER_SHADER, "the afterimage last")
	near(float(ar.base.get_shader_parameter("ghost_rim")), 0.0, 0.0001, "shimmer: no rim")
	passes = GhostLook.passes_of(wi.base)
	eq(passes.size(), 2 + GhostLook.SHELLS.size(), "the wisp follows the look")
	# strength
	check(GhostLook.pick("ghost_strength", "faint"), "pick faint")
	var faint_a := float((GhostLook.passes_of(sk.base)[1] as ShaderMaterial).get_shader_parameter("alpha"))
	near(float(wi.base.get_shader_parameter("alpha")), float(GhostLook.STRENGTH["faint"]["wisp"]), 0.0001, "faint: the wisp's alpha")
	check(not wi.light.visible, "faint: the wisp's light is off")
	check(GhostLook.pick("ghost_strength", "strong"), "pick strong")
	var strong_a := float((GhostLook.passes_of(sk.base)[1] as ShaderMaterial).get_shader_parameter("alpha"))
	check(strong_a > faint_a * 3.0, "strong outlines far harder than faint (%.3f vs %.3f)" % [strong_a, faint_a])
	check(wi.light.visible and wi.light.light_energy > 1.0, "strong: the wisp lights the floor")
	# colour
	check(GhostLook.pick("ghost_colour", "ecto green"), "pick ecto green")
	var green: Color = GhostLook.COLOUR["ecto green"]
	eq(sk.base.get_shader_parameter("ghost_color"), green, "the body's rim colour")
	eq((GhostLook.passes_of(ar.base)[1] as ShaderMaterial).get_shader_parameter("ghost_color"), green, "the shells' colour")
	eq(wi.base.get_shader_parameter("ghost_color"), green, "the wisp's colour")
	eq(wi.light.light_color, green, "the wisp's light")
	# the wisp drifts round its spot, near the floor's height above it
	var a := wi.head.global_position
	await frames(40)
	var b := wi.head.global_position
	check(a.distance_to(b) > 0.05, "the wisp drifts (%s -> %s)" % [a, b])
	var off := b - wi.global_position
	check(Vector2(off.x, off.z).length() <= GhostBody.DRIFT_R + 0.01 and off.y > 0.9 and off.y < 1.4,
			"in a slow loop round where it was put (%s)" % off)
	for p in wi.puffs:
		check(p.position.y < wi.head.position.y, "its tail hangs below the head")
	GhostLook.reset()
	GhostLook.refresh_all()
	root.queue_free()
	await frames(2)


func _has_ink(passes: Array[Material]) -> bool:
	for m in passes:
		if m is ShaderMaterial and (m as ShaderMaterial).shader.code == LowPolyMaterial.OUTLINE_SHADER:
			return true
	return false


## The lab's builders, headless: its room (a wood and panelling room), its two spots, a staged cell per ghost.
func _check_lab() -> void:
	var lab: Node3D = load(LAB).new()
	add_child(lab)
	await frames(2)
	var spots: Dictionary = lab.get("spots")
	check(spots.has("bright") and spots.has("dark"), "the lab has its bright spot and its dark corner")
	var m: HexMap = lab.get("map")
	if check(m != null, "the lab built its room"):
		var dark: Vector3 = spots["dark"]
		var c := Hex.from_world(dark)
		check(m.cells.has(c) and m.cells[c].type != HexMap.Tile.WALL, "the dark corner is floor")
		check(dark.distance_to(spots["bright"]) > 6.0, "far from the bright spot's pool (%.1f)" % dark.distance_to(spots["bright"]))
		eq(FloorMaterials.floor_of(m.cells[c].mat_id), FloorMaterials.F_WOOD, "wood boards")
	for kind: String in GhostBody.KINDS:
		lab.call("_stage", kind, spots["bright"])
		var holder: Node3D = lab.get("holder")
		var ghosts := holder.get_children().filter(func(n: Node) -> bool: return n is GhostBody)
		eq(ghosts.size(), 1, "%s: one ghost staged" % kind)
		eq(holder.get_child_count(), 3, "%s: with Wick and Rebar" % kind)
	eq(lab.call("key_of", "rim", "wisp", "dark", "soft", "ecto green"), "rim_wisp_dark_soft_ecto_green", "the cell keys")
	lab.queue_free()
	await frames(2)
