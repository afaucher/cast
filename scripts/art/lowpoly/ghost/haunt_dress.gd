class_name HauntDress
extends RefCounted
## The possessed look on a game model (docs/design/haunted-build-plan.md, "H5 as built"): what the user picked in the look tests
## (ghost-look.md: "The rim look is really good. Especially as a wisp."; haunt-look.md: "The ghost shows around it", the vapour
## body and the toned-down seep, "shell + seep"), put on a live host (KnightModel, BonesModel) when a ghost possesses it. The
## look test's HauntPiece builds the same pieces for its cosmetic nodes; this is the game's, on any LowPolyModel:
##   - every part (not the plinth, "stand") wears a ghost toon body in the RIM look (GhostLook.body_material, dressed at the
##     look test's strength and colour, always rim whatever GhostLook.look says), which is also the model's `_mat` (so the
##     monsters' hit flash, wind-up tint and glow hooks work on it);
##   - the ghost's vapour body round it: each part again, HauntPiece.GHOST_GROW larger round its own middle, in the wisp's
##     vapour (HauntPiece.vapour_shader), a child of the part so it follows the pose;
##   - the seep: a few puffs off the head and the top of the body, left in the world as it moves (HauntPiece.PUFF_SHADER).
## Cosmetic only, every machine dresses its own copy (LOCAL); the pulse phase comes from GameWorld.fx_rng.

const SEEP_HEAD := 5                ## puffs off the head (the look test's toned-down seep)
const SEEP_BODY := 6                ## and off the shoulders
const NO_GHOST: Array[String] = ["stand"]   ## parts the ghost never wears (the plinth: it stays behind)

static var _puff_shader: Shader
static var _puff_mesh: Mesh


## The pieces put on one model: {base, vapour, puff, shells: Array[MeshInstance3D], seep: Array[CPUParticles3D]}.
static func dress(model: LowPolyModel, phase: float) -> Dictionary:
	var base := GhostLook.body_material()
	base.set_shader_parameter("glow_gain", MonsterModel.GLOW_GAIN)
	dress_body(base, phase)
	for p: MeshInstance3D in model.parts.values():
		if not NO_GHOST.has(str(p.name)):
			p.material_override = base
	model._mat = base
	var vapour := ShaderMaterial.new()
	vapour.shader = HauntPiece.vapour_shader()
	var shells: Array[MeshInstance3D] = []
	for p: MeshInstance3D in model.parts.values():
		if NO_GHOST.has(str(p.name)):
			continue
		var c := p.mesh.get_aabb().get_center()
		var v := MeshInstance3D.new()
		v.name = "Vapour"
		v.mesh = p.mesh
		v.material_override = vapour
		v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		v.transform = Transform3D(Basis.from_scale(Vector3.ONE * HauntPiece.GHOST_GROW), c - c * HauntPiece.GHOST_GROW)
		p.add_child(v)
		shells.append(v)
	var puff := _puff_material()
	var seep: Array[CPUParticles3D] = []
	var head := model.parts.get("head") as MeshInstance3D
	var body := model.parts.get("body") as MeshInstance3D
	if head != null:
		var hb := head.mesh.get_aabb()
		seep.append(_emitter(head, puff, hb.get_center() + Vector3(0, hb.size.y * 0.25, 0), hb.size * 0.35, SEEP_HEAD))
	if body != null:
		var bb := body.mesh.get_aabb()
		var top := Vector3(bb.get_center().x, bb.end.y - 0.05, bb.get_center().z)
		seep.append(_emitter(body, puff, top, Vector3(bb.size.x * 0.45, 0.04, bb.size.z * 0.35), SEEP_BODY))
	var out := {"base": base, "vapour": vapour, "puff": puff, "shells": shells, "seep": seep}
	refresh(out, phase)
	return out


## The ghost toon body in the rim look at GhostLook's strength and colour now (whatever its look switch says: the user's pick).
static func dress_body(base: ShaderMaterial, phase: float) -> void:
	var was := GhostLook.look
	GhostLook.look = "rim"
	GhostLook.dress(base, false, phase)
	GhostLook.look = was


## Redress the pieces for GhostLook's strength and colour now (a host is in GhostLook.GROUP while possessed: the gym's pickers).
static func refresh(d: Dictionary, phase: float) -> void:
	if d.is_empty():
		return
	dress_body(d["base"] as ShaderMaterial, phase)
	var st := GhostLook.strength_now()
	var vapour := d["vapour"] as ShaderMaterial
	vapour.set_shader_parameter("ghost_color", GhostLook.color_now())
	vapour.set_shader_parameter("alpha", float(st["wisp"]))
	vapour.set_shader_parameter("edge_k", 1.7)
	vapour.set_shader_parameter("glow", float(st["glow"]))
	vapour.set_shader_parameter("pulse", GhostLook.PULSE)
	vapour.set_shader_parameter("phase", phase)
	vapour.set_shader_parameter("clock", GhostLook.clock)
	var puff := d["puff"] as ShaderMaterial
	puff.set_shader_parameter("ghost_color", GhostLook.color_now())
	puff.set_shader_parameter("alpha", float(st["wisp"]) * HauntPiece.PUFF_ALPHA)
	puff.set_shader_parameter("glow", float(st["glow"]))


## Take the ghost off a model again (its parts back on `plain`, the model's own material): the vapour and the seep go.
static func undress(model: LowPolyModel, d: Dictionary, plain: ShaderMaterial) -> void:
	for v: Variant in (d.get("shells", []) as Array):
		if is_instance_valid(v):
			(v as Node).queue_free()
	for e: Variant in (d.get("seep", []) as Array):
		if is_instance_valid(e):
			(e as Node).queue_free()
	for p: MeshInstance3D in model.parts.values():
		p.material_override = plain
	model._mat = plain


static func _puff_material() -> ShaderMaterial:
	if _puff_shader == null:
		_puff_shader = Shader.new()
		_puff_shader.code = HauntPiece.PUFF_SHADER
		_puff_mesh = LowPoly.boulder(Vector3(0.1, 0.09, 0.1), 0, 0.12, Color.WHITE, 611, 0.0).to_mesh(0.0)
	var m := ShaderMaterial.new()
	m.shader = _puff_shader
	return m


## One seep emitter under `parent` (puffs drifting up and fading, left in the world: they trail as the host moves).
static func _emitter(parent: Node3D, puff: ShaderMaterial, at: Vector3, box: Vector3, amount: int) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.name = "Wisps"
	var m := _puff_mesh.duplicate() as ArrayMesh
	m.surface_set_material(0, puff)
	e.mesh = m
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.amount = amount
	e.lifetime = 1.8
	e.preprocess = 1.8
	e.local_coords = false
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	e.emission_box_extents = box
	e.direction = Vector3.UP
	e.spread = 30.0
	e.gravity = Vector3(0, 0.25, 0)
	e.initial_velocity_min = 0.15
	e.initial_velocity_max = 0.3
	e.scale_amount_min = 0.48
	e.scale_amount_max = 0.8
	var grow := Curve.new()
	grow.max_value = 2.0
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 1.4))
	e.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	e.color_ramp = fade
	e.position = at
	e.emitting = true
	parent.add_child(e)
	return e
