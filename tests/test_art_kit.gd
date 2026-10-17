extends TestCase
## The procedural character kit: every hero id builds (headless) in every style with its named
## parts, stays cheap (node count), is posable, and uses toon materials with the right outline.

const BASE_PARTS: Array[String] = ["rig", "body", "head", "arm_l", "arm_r", "leg_l", "leg_r", "weapon"]
const MAX_NODES := 40

var _made: Array[Node] = []


func setup() -> void:
	for id in CharacterKit.HEROES:
		for style in CharacterKit.STYLE_IDS:
			var fig := _b(id, style) as ToyFigure
			if not check(fig != null, "%s/%s built" % [id, style]):
				continue
			add_child(fig)
			_check_figure(fig, id, style)

	# unknown ids do not crash and give an empty figure
	var empty := _b("nobody") as ToyFigure
	check(empty != null and empty.parts.size() == 1, "unknown hero id gives an empty rig")

	# per-hero identity pieces from characters.md
	var rebar := _b("rebar") as ToyFigure
	check(rebar.has_part("moss") and rebar.has_part("hat"), "Rebar: moss cap + tiny hard hat")
	var gasket := _b("gasket") as ToyFigure
	check(gasket.has_part("beard") and gasket.has_part("weapon_head"), "Gasket: beard + hammer head")
	var wick := _b("wick") as ToyFigure
	check(wick.has_part("hat") and wick.has_part("bowstring") and wick.has_part("wand_tape") and wick.has_part("lamp"), "Wick: hat, bow, taped wand, headlamp")
	var rattles := _b("sir_rattles") as ToyFigure
	check(rattles.has_part("visor") and rattles.has_part("neck") and rattles.has_part("plume"), "Sir Rattles: void visor, empty neck, plume")
	var visor := rattles.get_part("visor") as MeshInstance3D
	var vm := visor.material_override as ShaderMaterial
	var vcol: Color = vm.get_shader_parameter("albedo")
	check(vcol.get_luminance() < 0.1, "Sir Rattles' face is a dark gap")
	check(float(vm.get_shader_parameter("self_light")) == 0.0, "nothing glows on Sir Rattles")

	# every hero has a white crew strip somewhere
	for id in CharacterKit.HEROES:
		var f := _b(id) as ToyFigure
		var has_strip := false
		for k in f.parts:
			var n: Node3D = f.parts[k]
			if n is MeshInstance3D:
				var m := (n as MeshInstance3D).material_override as ShaderMaterial
				var c: Color = m.get_shader_parameter("albedo")
				if c.is_equal_approx(CharacterKit.STRIP):
					has_strip = true
		check(has_strip, "%s wears a crew strip" % id)

	# style differences: toy outlines, flat does not, heroic is taller
	var toy := _b("gasket", &"toy") as ToyFigure
	var flat := _b("gasket", &"flat") as ToyFigure
	var heroic := _b("gasket", &"heroic") as ToyFigure
	check((toy.get_part("body") as MeshInstance3D).material_override.next_pass != null, "toy style has an outline pass")
	check((flat.get_part("body") as MeshInstance3D).material_override.next_pass == null, "flat style has no outline pass")
	check(top_of(heroic) > top_of(toy), "heroic Gasket is taller than toy Gasket")
	var lark_t := _b("wick", &"toy") as ToyFigure
	check(top_of(lark_t) > top_of(toy), "Wick is taller than Gasket")
	for n in _made:
		n.free()
	finish()


func _b(id: String, style: StringName = &"toy") -> Node3D:
	var n := CharacterKit.build(id, style)
	_made.append(n)
	return n


func _check_figure(fig: ToyFigure, id: String, style: StringName) -> void:
	for p in BASE_PARTS:
		check(fig.has_part(p), "%s/%s has part '%s'" % [id, style, p])
	var n := fig.node_count()
	check(n < MAX_NODES, "%s/%s node count %d < %d" % [id, style, n, MAX_NODES])
	for k in fig.parts:
		var node: Node3D = fig.parts[k]
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			check(mi.mesh != null and mi.mesh.get_surface_count() == 1, "%s/%s part %s has a mesh" % [id, style, k])
			check(mi.material_override is ShaderMaterial, "%s/%s part %s is toon shaded" % [id, style, k])
	# idle + poses run and actually move something
	fig.apply_idle(1.3)
	var rest_r: Transform3D = fig.rest["arm_r"]
	fig.pose(&"melee")
	check(not (fig.get_part("arm_r").transform.is_equal_approx(rest_r) and fig.get_part("body").transform.is_equal_approx(fig.rest["body"])), "%s/%s melee pose moves parts" % [id, style])
	fig.pose(&"secondary")
	fig.pose(&"idle")
	check(fig.idle_enabled, "%s/%s resumes idle" % [id, style])
	fig.reset_pose()
	check(fig.get_part("arm_r").transform.is_equal_approx(rest_r), "%s/%s reset_pose restores rest" % [id, style])


## Highest point of any mesh part in the figure's local space.
func top_of(fig: ToyFigure) -> float:
	var top := 0.0
	for k in fig.parts:
		var node: Node3D = fig.parts[k]
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			var aabb := mi.mesh.get_aabb()
			var xf := _local_to_fig(mi, fig)
			for i in 8:
				top = maxf(top, (xf * aabb.get_endpoint(i)).y)
	return top


func _local_to_fig(n: Node3D, fig: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != fig:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
