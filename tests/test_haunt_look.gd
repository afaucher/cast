extends TestCase
## The haunt look test (docs/design/haunt-look.md, LOOK-DEV ONLY): the suit of armour's three stances (ArmourModel.pose), the
## haunt pieces (HauntPiece: the armour and the crypt skeleton, dormant and possessed), the hero's ghost form (GhostForm)
## on and off, the gym's Haunts spawns and its "Ghost form" picker, and the haunt look lab's staging, all headless.

const LAB := "res://scripts/art/lowpoly/ghost/haunt_look_lab.gd"

var root: Node3D


func setup() -> void:
	GhostLook.reset()
	GhostForm.treatment = "off"
	_check_stances()
	_check_pieces()
	_check_ghost_form()
	_check_entries()
	await _check_gym_spawns()
	await _check_lab()
	GhostLook.reset()
	GhostForm.treatment = "off"
	finish()


## The armour's stances move the sword and the figure: dormant has the point on the plinth, guard raises it point-up, lurch
## steps off the plinth onto the floor and holds it low, point leading.
func _check_stances() -> void:
	var a := ArmourModel.new()
	eq(a.stance, "dormant", "the armour starts dormant")
	var point := func() -> Vector3: return (a.get_part("weapon") as Node3D).position
	var pommel := func() -> Vector3: return (a.get_part("weapon") as Node3D).transform * Vector3(0, 1.1, 0)
	near(point.call().y, ArmourModel.STAND_H, 0.001, "dormant: the point rests on the plinth")
	check(pommel.call().y > point.call().y + 1.0, "dormant: point-down")
	a.pose("guard")
	check(point.call().y > pommel.call().y + 0.6, "guard: the sword raised point-up (%.2f over %.2f)" % [point.call().y, pommel.call().y])
	check(point.call().y > 1.5, "guard: the point up past the shoulders")
	var body_z_guard := (a.get_part("body") as Node3D).position.z
	a.pose("lurch")
	var body := a.get_part("body") as Node3D
	check(body.position.z < body_z_guard - 0.5, "lurch: stepped forward off the plinth")
	check(body.position.y < ArmourModel.WAIST_Y - ArmourModel.STAND_H, "lurch: down on the floor")
	check(body.rotation.x < -0.3, "lurch: hunched forward")
	check(point.call().z < pommel.call().z - 0.5 and point.call().y < pommel.call().y - 0.2, "lurch: the sword low, its point leading")
	check(point.call().y > 0.05, "lurch: the point clear of the floor (%.2f)" % point.call().y)
	near((a.get_part("stand") as Node3D).position.length(), 0.0, 0.0001, "the plinth stays where it was")
	a.pose("nope")
	eq(a.stance, "dormant", "an unknown stance is dormant")
	near(point.call().y, ArmourModel.STAND_H, 0.001, "... and the sword goes back on the plinth")
	# each hand reaches its spot (the gauntlet at the end of the arm)
	for st: String in ArmourModel.STANCES:
		a.pose(st)
		var arm := a.get_part("arm_r") as Node3D
		var hand := (a.get_part("body") as Node3D).transform * arm.transform * Vector3(0, -(ArmourModel.ARM_LEN - 0.03), 0)
		var grip := (a.get_part("weapon") as Node3D).transform * Vector3(0, ArmourModel.GRIP_FROM_POINT, 0)
		check(hand.distance_to(grip) < 0.15, "%s: the right gauntlet on the grip (%.2f off)" % [st, hand.distance_to(grip)])
	a.free()


## Dormant pieces are props (the props' material, the ink, dark eyes, not in the ghost group); possessed ones wear the ghost
## body in the rim look whatever the Ghost look picker says (the plinth excepted).
func _check_pieces() -> void:
	var prop_code := PropModels.material().shader.code
	for kind: String in HauntPiece.KINDS:
		var p := HauntPiece.make(kind)
		add_child(p)
		check(not ((p as Node) is Actor) and p.find_children("*", "CollisionObject3D").is_empty(), "%s: a cosmetic node" % kind)
		check(p.model != null and p.model.triangle_count() > 0, "%s: built" % kind)
		check((p.model is ArmourModel) if kind.begins_with("armour") else (p.model is GruntModel), "%s: the right model" % kind)
		if kind.begins_with("skeleton"):
			check(p.blockout != null, "%s: its blockout" % kind)
		if p.is_possessed():
			check(p.is_in_group(GhostLook.GROUP), "%s: redressed by the ghost pickers" % kind)
			for part: MeshInstance3D in p.model.parts.values():
				if part.name == "stand":
					check(part.material_override != p.base, "%s: the plinth is not possessed" % kind)
				else:
					check(part.material_override == p.base, "%s: %s wears the ghost body" % [kind, part.name])
			near(float(p.base.get_shader_parameter("ghost_rim")), float(GhostLook.STRENGTH["soft"]["rim"]), 0.0001, "%s: in the rim look" % kind)
			check(not _has_ink(GhostLook.passes_of(p.base)), "%s: no ink outline" % kind)
			if kind.begins_with("armour"):
				var vap := p.find_children("Vapour", "MeshInstance3D", true, false)
				eq(vap.size(), p.model.parts.size() - 1, "%s: the ghost's body round every part but the plinth" % kind)
				near(float(p.vapour.get_shader_parameter("alpha")), float(GhostLook.STRENGTH["soft"]["wisp"]), 0.0001, "%s: the ghost's body at the wisp's alpha" % kind)
		else:
			check(p.find_children("Vapour", "MeshInstance3D", true, false).is_empty(), "%s: no ghost body" % kind)
			check(not p.is_in_group(GhostLook.GROUP), "%s: not a ghost" % kind)
			var m := (p.model.get_part("body") as MeshInstance3D).material_override as ShaderMaterial
			check(m.shader.code == prop_code, "%s: drawn like a prop" % kind)
			check(_has_ink(GhostLook.passes_of(m)), "%s: with its ink outline" % kind)
			if kind.begins_with("skeleton"):
				near(float(m.get_shader_parameter("glow_gain")), 0.0, 0.0001, "%s: its eyes are out" % kind)
		p.free()
	# the possessed pieces stay rim when the picker says outline, and follow its colour
	var g := HauntPiece.make("armour_guard")
	add_child(g)
	check(GhostLook.pick("ghost_look", "outline") and GhostLook.pick("ghost_colour", "ecto green"), "pick outline, ecto green")
	check(float(g.base.get_shader_parameter("ghost_rim")) > 0.0, "still rim under the outline pick")
	eq(g.base.get_shader_parameter("ghost_color"), GhostLook.COLOUR["ecto green"], "follows the colour pick")
	eq(GhostLook.look, "outline", "redressing leaves the pick alone")
	g.free()
	GhostLook.reset()


func _has_ink(passes: Array[Material]) -> bool:
	for m in passes:
		if m is ShaderMaterial and (m as ShaderMaterial).shader.code == LowPolyMaterial.OUTLINE_SHADER:
			return true
	return false


## Ghost form on Wick and Rebar: every part redrawn in the chain (depth, body, ink or halo), the colours kept (vertex
## colours, nothing tinted cold), off puts everything back; a held item and a rebuilt arm get dressed too.
func _check_ghost_form() -> void:
	for which: String in ["wick", "rebar"]:
		var m: LowPolyModel = RebarModel.new() if which == "rebar" else WickModel.new()
		add_child(m)
		var own := {}
		for part: MeshInstance3D in m.parts.values():
			own[part] = part.material_override
		for t: String in ["glass", "spirit"]:
			var f := GhostForm.apply(m, t)
			if not check(f != null and GhostForm.of(m) == f, "%s: %s applied" % [which, t]):
				continue
			for part: MeshInstance3D in m.parts.values():
				check(part.material_override == f.head, "%s %s: %s redrawn" % [which, t, part.name])
			check(f.head.render_priority < f.body.render_priority, "%s: the depth pass draws first" % t)
			check(f.head.next_pass == f.body, "%s: the body after the depth pass" % t)
			var warm: Color = f.body.get_shader_parameter("rim_color")
			check(warm.r > warm.b, "%s: a warm edge (never the enemy ghosts' cold one)" % t)
			check(float(f.body.get_shader_parameter("alpha")) < 0.6, "%s: see-through" % t)
			var tail := f.body.next_pass as ShaderMaterial
			if t == "glass":
				check(tail != null and tail.shader.code == GhostForm.INK_SHADER, "glass: keeps a translucent ink outline")
			else:
				check(tail != null and tail.shader.code == GhostLook.SHELL_SHADER, "spirit: a soft halo instead of the ink")
				check(float(f.body.get_shader_parameter("fade_h")) > 0.0, "spirit: the legs fade toward the floor")
				check((m.get_part("body") as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "spirit: no shadow")
		# a held item: not the hero's material, so only made see-through
		var item := MeshInstance3D.new()
		item.mesh = BoxMesh.new()
		m.hold_item(item)
		var f2 := GhostForm.of(m)
		f2.scan()
		check(item.transparency > 0.3, "%s: a held item is made see-through" % which)
		check(f2.counts().x >= m.parts.size() and f2.counts().y >= 1, "%s: the parts redrawn, the item only see-through (%s)" % [which, f2.counts()])
		GhostForm.apply(m, "off")
		check(GhostForm.of(m) == null, "%s: off removes it" % which)
		for part: MeshInstance3D in own:
			check(part.material_override == own[part], "%s: %s back to its own material" % [which, part.name])
		near(item.transparency, 0.0, 0.0001, "%s: the held item solid again" % which)
		m.free()
	check(not GhostForm.pick(null, "nope"), "an unknown treatment is refused")
	check(GhostForm.pick(null, "glass") and GhostForm.treatment == "glass", "a pick with no model still sets the treatment")
	GhostForm.treatment = "off"


func _check_entries() -> void:
	for kind: String in HauntPiece.KINDS:
		var e := GymSpawns.find("haunt:" + kind)
		if check(not e.is_empty(), "haunt:%s is a gym entry" % kind):
			eq(str(e["skip"]), "", "it has a button")
	check(GymSpawns.GROUPS.has("haunt"), "the haunt group is listed")
	var rows := {}
	for row: Array in GymDev.experiments():
		rows[str(row[0])] = row
	if check(rows.has("hero_ghost"), "the panel has the Ghost form picker"):
		eq(str(rows["hero_ghost"][1]), "Ghost form", "its label")
		eq(str(rows["hero_ghost"][2]), str(["off", "glass", "spirit"]), "off and the two treatments")
		eq(str(rows["hero_ghost"][3]), "off", "off by default")


func _check_gym_spawns() -> void:
	root = Node3D.new()
	add_child(root)
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 7):
		map.set_cell(c, 0).tag = "room:0"
	GameWorld.begin(map, root, 3)
	for kind: String in HauntPiece.KINDS:
		var made := GymSpawns.spawn(GymSpawns.find("haunt:" + kind), Vector3.ZERO, 1, null, null)
		if check(made.size() == 1 and made[0] is HauntPiece, "haunt: %s spawns one HauntPiece" % kind):
			eq((made[0] as HauntPiece).kind, kind, "of its kind")
			check(made[0].get_parent() == GameWorld.root, "under the world")
	await frames(2)
	root.queue_free()
	await frames(2)


## The lab's builders, headless: a piece staged with Wick and Rebar, a hero staged in ghost form with a possessed skeleton
## and a wisp.
func _check_lab() -> void:
	var lab: Node3D = load(LAB).new()
	add_child(lab)
	await frames(2)
	var spots: Dictionary = lab.get("spots")
	var holder: Node3D = lab.get("holder")
	for kind: String in HauntPiece.KINDS:
		var p: HauntPiece = lab.call("stage_piece", kind, spots["bright"])
		check(p != null and p.kind == kind, "the lab stages %s" % kind)
		eq(holder.get_child_count(), 3, "%s: with Wick and Rebar" % kind)
	for t: String in GhostForm.TREATMENTS:
		var m: LowPolyModel = lab.call("stage_hero", "rebar", t, spots["dark"])
		check(m is RebarModel, "the lab stages Rebar (%s)" % t)
		eq(GhostForm.of(m) != null, t != "off", "%s: in ghost form or not" % t)
		eq(holder.get_child_count(), 3, "%s: with a possessed skeleton and a wisp" % t)
	lab.queue_free()
	await frames(2)
