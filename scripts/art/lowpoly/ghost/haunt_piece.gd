class_name HauntPiece
extends Node3D
## LOOK-DEV ONLY (docs/design/haunt-look.md): the hosts a ghost possesses (new-themes.md "Ghost house"), dormant and
## possessed, as plain cosmetic nodes: not an Actor, no HP, no AI, no collision, nothing networked. The gym spawns them
## ("haunt: ...", GymSpawns "haunt") and the haunt look lab poses them. Nothing in the game makes one.
##   armour_dormant    the suit of armour (ArmourModel "dormant") as a priced prop: the props' material and ink outline
##   armour_guard      possessed, still on its plinth, the sword raised point-up in both hands (ArmourModel "guard")
##   armour_lurch      possessed, stepped off the plinth onto the floor, hunched forward, reaching (ArmourModel "lurch")
##   skeleton_slumped  today's grunt model (GruntModel), sat on the floor slumped against a stone block, head lolled, its sword by its hand
##   skeleton_risen    the same skeleton standing, possessed, idling
## A possessed piece wears the ghost look the user picked (2026-10-29, "The rim look is really good"): the host's toon body
## with the ghost rim (GhostLook), whatever the gym's Ghost look picker says; it follows the Ghost strength and colour
## pickers (it is in GhostLook.GROUP). The plinth is never possessed: it keeps the props' look. A dormant piece is drawn like
## any prop on the floor (PropModels.material(): the ink outline), its eyes dark.
## The stone block is a blockout only, to show the poses in place (the crypt section is built elsewhere).
## Looks only: the pulse phase comes from GameWorld.fx_rng.

## (No "skeleton_niche": the user dropped the niche pose, 2026-10-29: "Drop the niche for now"; burial slots belong to the
## crypt section's real walls.)
const KINDS: Array[String] = ["armour_dormant", "armour_guard", "armour_lurch", "skeleton_slumped", "skeleton_risen"]
const POSSESSED: Array[String] = ["armour_guard", "armour_lurch", "skeleton_risen"]
const FACING := -135.0            ## the yaw that turns a piece's front (-Z) straight at the game camera (a niche, a block)

const STONE := Color(0.47, 0.44, 0.40)
const STONE_LIGHT := Color(0.58, 0.55, 0.50)
const STONE_DARK := Color(0.33, 0.31, 0.29)
const HOLLOW := Color(0.17, 0.15, 0.14)
const DUST := Color(0.40, 0.36, 0.31)
const CAP := Color(0.21, 0.19, 0.18)       ## the top, dark like the game's wall tops
const MORTAR := Color(0.25, 0.23, 0.21)


## The ghost wearing a possessed host (the user, 2026-10-29: "The ghost shows around it. A faint, larger wisp-like body
## overlaps the armour, as if the ghost is wearing it"; the risen skeleton too: "Yes"): every part again, GHOST_GROW times larger round its own
## middle, in the wisp's vapour (GhostLook's wisp shader, one even tint: no dark eye parts, no vertex colours).
const GHOST_GROW := 1.2

var kind := "armour_dormant"
var model: LowPolyModel           ## the ArmourModel or the GruntModel
var base: ShaderMaterial          ## a possessed piece's ghost body (shared by its possessed parts)
var phase := 0.0
var blockout: MeshInstance3D      ## the slumped skeleton's stone block (null otherwise)
var vapour: ShaderMaterial        ## a possessed piece's ghost body round the host (null when dormant)
var puff: ShaderMaterial          ## its wisps' puffs
var pace := false                 ## the gym: a possessed piece glides slowly to and fro, so its wisps trail in motion
var _shells: Array[MeshInstance3D] = []
var _seep: Array[CPUParticles3D] = []
var _cloak: Array[CPUParticles3D] = []
var _home := Vector3.ZERO
var _t := 0.0

static var _vapour_shader: Shader
static var _puff_shader: Shader
static var _puff_mesh: Mesh

## The ghost's wisps on a possessed host, options to compare (the user, 2026-10-29: "I think we might want particles to
## give that wispy effect", "Show me some options", "I want to see it in motion to make a final decision"):
##   shell          the vapour body alone (no particles)
##   shell + seep   the vapour body, and puffs seeping off the head and shoulders, drifting up and fading
##   seep           the puffs alone (no vapour body)
##   cloak          no vapour body: puffs rising off every part, a moving cloud the shape of the host
const WISPS: Array[String] = ["shell", "shell + seep", "seep", "cloak"]
static var wisps := "shell + seep"

const PUFF_SHADER := """
shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never, blend_mix, cull_back;

uniform vec4 ghost_color : source_color = vec4(0.70, 0.86, 1.0, 1.0);
uniform float alpha = 0.3;
uniform float glow = 1.0;

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = pow(1.0 - ndv, 1.4);
	ALBEDO = ghost_color.rgb * glow * (0.85 + 0.5 * edge);
	ALPHA = clamp(alpha * COLOR.a * (0.45 + 0.9 * edge), 0.0, 1.0);
}
"""


static func make(k: String) -> HauntPiece:
	var p := HauntPiece.new()
	p.kind = k if KINDS.has(k) else "armour_dormant"
	p._build()
	return p


func _init() -> void:
	name = "HauntPiece"


func is_possessed() -> bool:
	return POSSESSED.has(kind)


func _ready() -> void:
	if GameWorld.fx_rng != null:
		phase = GameWorld.fx_rng.randf_range(0.0, TAU)
	refresh()


func _process(delta: float) -> void:
	if not pace or not is_possessed():
		return
	if _t == 0.0:
		_home = position
	_t += delta
	position = _home + transform.basis.x.normalized() * sin(_t * 0.6) * 1.4


func _build() -> void:
	name = "Haunt_" + kind
	if kind.begins_with("armour"):
		var a := ArmourModel.new()
		model = a
		add_child(a)
		a.pose(kind.trim_prefix("armour_"))
		var prop := PropModels.material()
		for p: MeshInstance3D in a.parts.values():
			p.material_override = prop
		a._mat = prop
	else:
		var g := GruntModel.new()
		model = g
		g.idle_enabled = false
		match kind:
			"skeleton_slumped":
				blockout = _add_blockout(_block_soup(), Vector3(0.0, 0.0, 0.56))
				add_child(g)
				_pose_slumped(g)
			_:
				add_child(g)
				g.idle_enabled = true
		if not is_possessed():
			g._mat.set_shader_parameter("glow_gain", 0.0)   # dead bones: the ember eyes out
	if is_possessed():
		add_to_group(GhostLook.GROUP)
		base = GhostLook.body_material()
		for p: MeshInstance3D in model.parts.values():
			if p.name != "stand":
				p.material_override = base
		if model is GruntModel:
			model._mat = base
		_add_vapour()
		_add_wisps()


## Redress a possessed piece for GhostLook's strength and colour as they are now, always in the rim look.
func refresh() -> void:
	if base == null:
		return
	var was := GhostLook.look
	GhostLook.look = "rim"
	GhostLook.dress(base, false, phase)
	GhostLook.look = was
	if vapour != null:
		var st := GhostLook.strength_now()
		vapour.set_shader_parameter("ghost_color", GhostLook.color_now())
		vapour.set_shader_parameter("alpha", float(st["wisp"]))
		vapour.set_shader_parameter("edge_k", 1.7)
		vapour.set_shader_parameter("glow", float(st["glow"]))
		vapour.set_shader_parameter("pulse", GhostLook.PULSE)
		vapour.set_shader_parameter("phase", phase)
		vapour.set_shader_parameter("clock", GhostLook.clock)
	if puff != null:
		var st2 := GhostLook.strength_now()
		puff.set_shader_parameter("ghost_color", GhostLook.color_now())
		puff.set_shader_parameter("alpha", float(st2["wisp"]) * 1.6)
		puff.set_shader_parameter("glow", float(st2["glow"]))
		for v in _shells:
			v.visible = wisps.begins_with("shell")
		for e in _seep:
			e.visible = wisps.ends_with("seep")
			e.emitting = e.visible
		for e in _cloak:
			e.visible = wisps == "cloak"
			e.emitting = e.visible


## The ghost's body round a possessed host: a copy of each part (not the plinth), grown round its own middle, as a child of
## the part so it follows the pose.
func _add_vapour() -> void:
	if _vapour_shader == null:
		_vapour_shader = Shader.new()
		_vapour_shader.code = GhostLook.WISP_SHADER.replace("float eye = 1.0 - step(0.25, lum);", "float eye = 0.0;") 				.replace("ghost_color.rgb * COLOR.rgb", "ghost_color.rgb")
	vapour = ShaderMaterial.new()
	vapour.shader = _vapour_shader
	for p: MeshInstance3D in model.parts.values():
		if p.name == "stand":
			continue
		var c := p.mesh.get_aabb().get_center()
		var v := MeshInstance3D.new()
		v.name = "Vapour"
		v.mesh = p.mesh
		v.material_override = vapour
		v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		v.transform = Transform3D(Basis.from_scale(Vector3.ONE * GHOST_GROW), c - c * GHOST_GROW)
		p.add_child(v)
		_shells.append(v)


## The wisps' emitters (refresh shows the ones WISPS picks): seep off the head and the top of the body; cloak off every
## part but the plinth. Puffs are left behind in the world as the host moves (not local), so they trail.
func _add_wisps() -> void:
	if _puff_shader == null:
		_puff_shader = Shader.new()
		_puff_shader.code = PUFF_SHADER
		_puff_mesh = LowPoly.boulder(Vector3(0.1, 0.09, 0.1), 0, 0.12, Color.WHITE, 611, 0.0).to_mesh(0.0)
	puff = ShaderMaterial.new()
	puff.shader = _puff_shader
	var head := model.parts.get("head") as MeshInstance3D
	var body := model.parts.get("body") as MeshInstance3D
	if head != null:
		var hb := head.mesh.get_aabb()
		_seep.append(_emitter(head, hb.get_center() + Vector3(0, hb.size.y * 0.25, 0), hb.size * 0.35, 8, 1.8, 0.35, 1.0))
	if body != null:
		var bb := body.mesh.get_aabb()
		var top := Vector3(bb.get_center().x, bb.end.y - 0.05, bb.get_center().z)
		_seep.append(_emitter(body, top, Vector3(bb.size.x * 0.45, 0.04, bb.size.z * 0.35), 10, 1.8, 0.3, 1.0))
	for p: MeshInstance3D in model.parts.values():
		if p.name == "stand":
			continue
		var ab := p.mesh.get_aabb()
		var n := clampi(int(ab.size.length() * 5.0), 2, 7)
		_cloak.append(_emitter(p, ab.get_center(), ab.size * 0.5, n, 1.2, 0.15, 0.8))


func _emitter(parent: Node3D, at: Vector3, box: Vector3, amount: int, life: float, speed: float, size: float) -> CPUParticles3D:
	var e := CPUParticles3D.new()
	e.name = "Wisps"
	var m := _puff_mesh.duplicate() as ArrayMesh
	m.surface_set_material(0, puff)
	e.mesh = m
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.amount = amount
	e.lifetime = life
	e.preprocess = life
	e.local_coords = false
	e.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	e.emission_box_extents = box
	e.direction = Vector3.UP
	e.spread = 30.0
	e.gravity = Vector3(0, 0.25, 0)
	e.initial_velocity_min = speed * 0.5
	e.initial_velocity_max = speed
	e.scale_amount_min = size * 0.6
	e.scale_amount_max = size
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


func _add_blockout(soup: LowPoly.Soup, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Blockout"
	mi.mesh = soup.to_mesh()
	mi.material_override = PropModels.material()
	mi.position = at
	add_child(mi)
	return mi


# --- the blockouts --------------------------------------------------------------------------------------------------

## A rough stone block to slump against (a stand-in for a wall): 1.7 wide, 1.4 high, 0.4 deep, centred on its foot.
static func _block_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(821, 0.05)
	MonsterModel.slab(s, Vector3(0, 0.6, 0), Vector3(1.7, 1.2, 0.42), STONE, 822, Vector3.ZERO, 0.03)
	MonsterModel.slab(s, Vector3(0.05, 1.28, 0.02), Vector3(1.6, 0.18, 0.40), STONE_LIGHT, 823, Vector3(0, 0, 2.0), 0.03)
	MonsterModel.slab(s, Vector3(-0.55, 0.05, -0.26), Vector3(0.24, 0.1, 0.16), STONE_DARK, 824, Vector3(0, 20.0, 0), 0.04)   # rubble
	MonsterModel.slab(s, Vector3(0.70, 0.04, -0.30), Vector3(0.14, 0.08, 0.12), STONE_DARK, 825, Vector3(0, -35.0, 0), 0.04)
	return s


# --- the skeleton's dormant poses (the grunt's rigid parts, its standing frame) ---------------------------------------------

## Sat on the floor against the block: the pelvis down, leaning back and to its left, the skull dropped and lolled, the
## legs out in front (one splayed), the left hand on the floor, the right in its lap, the sword flat on the floor by it.
static func _pose_slumped(g: GruntModel) -> void:
	var body := g.parts["body"] as Node3D
	body.position = Vector3(0.0, 0.17, 0.10)
	body.rotation = Vector3(deg_to_rad(16.0), deg_to_rad(8.0), deg_to_rad(12.0))
	(g.parts["head"] as Node3D).rotation = Vector3(deg_to_rad(-34.0), deg_to_rad(18.0), deg_to_rad(22.0))
	(g.parts["jaw"] as Node3D).rotation = Vector3(-0.50, 0.0, 0.0)
	var leg_l := g.parts["leg_l"] as Node3D
	leg_l.position = Vector3(-0.15, 0.14, -0.02)
	leg_l.rotation = Vector3(deg_to_rad(84.0), deg_to_rad(16.0), 0.0)
	var leg_r := g.parts["leg_r"] as Node3D
	leg_r.position = Vector3(0.15, 0.14, -0.02)
	leg_r.rotation = Vector3(deg_to_rad(76.0), deg_to_rad(-30.0), 0.0)
	var to_body := body.transform.affine_inverse()
	_aim(g.parts["arm_l"], to_body * Vector3(-0.62, 0.05, -0.20), 0.62)
	_aim(g.parts["arm_r"], to_body * Vector3(0.10, 0.30, -0.36), 0.62)
	var along := Vector3(0.45, 0.0, -1.0).normalized()
	set_in_model(g, g.parts["weapon"], Transform3D(Basis(along.cross(Vector3.UP), along, Vector3.UP), Vector3(0.62, 0.05, -0.30)))


## Aim a limb that hangs down its local -Y from its pivot so its end reaches `target` (its parent's space), stretched or
## shortened along its own length to meet it.
static func _aim(part: Node3D, target: Vector3, rest_len: float) -> void:
	var d := target - part.position
	var l := d.length()
	if l < 0.001:
		return
	part.basis = Basis(Quaternion(Vector3.DOWN, d / l)) * Basis.from_scale(Vector3(1.0, clampf(l / rest_len, 0.6, 1.3), 1.0))


## Put `part` (somewhere under model `m`) at transform `xf` in the model's own space, whatever its parents' poses.
static func set_in_model(m: Node3D, part: Node3D, xf: Transform3D) -> void:
	var up := Transform3D.IDENTITY
	var p := part.get_parent() as Node3D
	while p != null and p != m:
		up = p.transform * up
		p = p.get_parent() as Node3D
	part.transform = up.affine_inverse() * xf
