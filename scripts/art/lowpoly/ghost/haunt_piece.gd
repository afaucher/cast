class_name HauntPiece
extends Node3D
## LOOK-DEV ONLY (docs/design/haunt-look.md): the hosts a ghost possesses (new-themes.md "Ghost house"), dormant and
## possessed, as plain cosmetic nodes: not an Actor, no HP, no AI, no collision, nothing networked. The gym spawns them
## ("haunt: ...", GymSpawns "haunt") and the haunt look lab poses them. Nothing in the game makes one.
##   armour_dormant    the suit of armour (ArmourModel "dormant") as a priced prop: the props' material and ink outline
##   armour_guard      possessed, still on its plinth, the sword raised point-up in both hands (ArmourModel "guard")
##   armour_lurch      possessed, stepped off the plinth onto the floor, hunched forward, reaching (ArmourModel "lurch")
##   skeleton_niche    today's grunt model (GruntModel) laid on its back in a wall niche, hands crossed on its sword
##   skeleton_slumped  the same, sat on the floor slumped against a stone block, head lolled, its sword by its hand
##   skeleton_risen    the same skeleton standing in front of its empty niche, possessed, idling
## A possessed piece wears the ghost look the user picked (2026-10-29, "The rim look is really good"): the host's toon body
## with the ghost rim (GhostLook), whatever the gym's Ghost look picker says; it follows the Ghost strength and colour
## pickers (it is in GhostLook.GROUP). The plinth is never possessed: it keeps the props' look. A dormant piece is drawn like
## any prop on the floor (PropModels.material(): the ink outline), its eyes dark.
## The niche and the stone block are blockouts only, to show the poses in place (the crypt section is built elsewhere).
## Looks only: the pulse phase comes from GameWorld.fx_rng.

const KINDS: Array[String] = ["armour_dormant", "armour_guard", "armour_lurch", "skeleton_niche", "skeleton_slumped",
	"skeleton_risen"]
const POSSESSED: Array[String] = ["armour_guard", "armour_lurch", "skeleton_risen"]
const FACING := -135.0            ## the yaw that turns a piece's front (-Z) straight at the game camera (a niche, a block)

const STONE := Color(0.47, 0.44, 0.40)
const STONE_LIGHT := Color(0.58, 0.55, 0.50)
const STONE_DARK := Color(0.33, 0.31, 0.29)
const HOLLOW := Color(0.17, 0.15, 0.14)
const DUST := Color(0.40, 0.36, 0.31)
const CAP := Color(0.21, 0.19, 0.18)       ## the top, dark like the game's wall tops
const MORTAR := Color(0.25, 0.23, 0.21)

## The niche blockout (its opening faces -Z): the whole block's width, depth and height, the shelf's top and the opening's
## top. The recess is shallow enough that the game camera sees its whole floor.
const NICHE_W := 2.9
const NICHE_D := 0.72
const NICHE_H := 1.75
const SHELF_Y := 0.5
const OPENING_TOP := 1.42
const RECESS := 0.6

var kind := "armour_dormant"
var model: LowPolyModel           ## the ArmourModel or the GruntModel
var base: ShaderMaterial          ## a possessed piece's ghost body (shared by its possessed parts)
var phase := 0.0
var blockout: MeshInstance3D      ## the niche or the stone block (null for the armour)


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
			"skeleton_niche":
				blockout = _add_blockout(_niche_soup(), Vector3.ZERO)
				var pivot := Node3D.new()
				pivot.name = "Lying"
				add_child(pivot)
				# on its back along the shelf, the head to +X, its face up, its right side toward the opening
				pivot.transform = Transform3D(Basis(Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0)),
						Vector3(-1.10, SHELF_Y + 0.19, -0.02))
				pivot.add_child(g)
				_pose_lying(g)
			"skeleton_slumped":
				blockout = _add_blockout(_block_soup(), Vector3(0.0, 0.0, 0.56))
				add_child(g)
				_pose_slumped(g)
			_:
				blockout = _add_blockout(_niche_soup(), Vector3(0.0, 0.0, 0.85))
				add_child(g)
				g.position = Vector3(0.25, 0.0, -0.2)
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


## Redress a possessed piece for GhostLook's strength and colour as they are now, always in the rim look.
func refresh() -> void:
	if base == null:
		return
	var was := GhostLook.look
	GhostLook.look = "rim"
	GhostLook.dress(base, false, phase)
	GhostLook.look = was


func _add_blockout(soup: LowPoly.Soup, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Blockout"
	mi.mesh = soup.to_mesh()
	mi.material_override = PropModels.material()
	mi.position = at
	add_child(mi)
	return mi


# --- the blockouts --------------------------------------------------------------------------------------------------

## A wall niche (a loculus): a stone block with a long, shallow recess at waist height, its opening to -Z, a lip on the
## shelf and a dark back. NICHE_W x NICHE_H x NICHE_D, standing on the floor.
static func _niche_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(801, 0.05)
	var half_d := NICHE_D * 0.5
	var back_z := -half_d + RECESS
	var open_h := OPENING_TOP - SHELF_Y
	MonsterModel.slab(s, Vector3(0, SHELF_Y * 0.5, 0), Vector3(NICHE_W, SHELF_Y, NICHE_D), STONE, 802, Vector3.ZERO, 0.02)   # base
	MonsterModel.slab(s, Vector3(0, SHELF_Y + open_h * 0.5, (back_z + half_d) * 0.5), Vector3(NICHE_W - 0.3, open_h, half_d - back_z),
			STONE, 803)                                                                                                 # the back
	MonsterModel.slab(s, Vector3(0, SHELF_Y + open_h * 0.5, back_z + 0.01), Vector3(NICHE_W - 0.3, open_h, 0.03), HOLLOW, 812)   # its dark face
	for x: float in [-1.0, 1.0]:
		MonsterModel.slab(s, Vector3(x * (NICHE_W * 0.5 - 0.1), SHELF_Y + open_h * 0.5, 0), Vector3(0.2, open_h, NICHE_D), STONE, 804 + int(x), Vector3.ZERO, 0.02)
	var top_h := NICHE_H - OPENING_TOP
	MonsterModel.slab(s, Vector3(0, OPENING_TOP + top_h * 0.5, 0), Vector3(NICHE_W, top_h, NICHE_D), STONE, 807, Vector3.ZERO, 0.02)   # lintel
	MonsterModel.slab(s, Vector3(0, SHELF_Y + 0.01, (back_z - half_d) * 0.5), Vector3(NICHE_W - 0.4, 0.03, RECESS - 0.02), DUST, 808)  # the shelf's dust
	MonsterModel.slab(s, Vector3(0, SHELF_Y - 0.03, -half_d - 0.02), Vector3(NICHE_W + 0.04, 0.06, 0.08), STONE_LIGHT, 809)    # the lip
	MonsterModel.slab(s, Vector3(0, OPENING_TOP + 0.03, -half_d - 0.02), Vector3(NICHE_W + 0.04, 0.08, 0.08), STONE_LIGHT, 810)
	MonsterModel.slab(s, Vector3(0, NICHE_H - 0.04, 0), Vector3(NICHE_W + 0.06, 0.1, NICHE_D + 0.06), CAP, 811)        # the cap (dark: the
	# top is the biggest face the steep game camera sees, and a pale one outshone the bones)
	# the masonry's joints on the front: a course line through the base and the lintel, and staggered upright joints
	var front := -half_d - 0.005
	for y: float in [SHELF_Y * 0.5, OPENING_TOP + top_h * 0.45]:
		MonsterModel.slab(s, Vector3(0, y, front), Vector3(NICHE_W - 0.04, 0.025, 0.02), MORTAR, 813)
	for x: float in [-0.95, 0.15, 1.05]:
		MonsterModel.slab(s, Vector3(x, SHELF_Y * 0.25, front), Vector3(0.025, SHELF_Y * 0.5 - 0.02, 0.02), MORTAR, 814)
	for x: float in [-0.45, 0.6]:
		MonsterModel.slab(s, Vector3(x, SHELF_Y * 0.75, front), Vector3(0.025, SHELF_Y * 0.5 - 0.02, 0.02), MORTAR, 815)
		MonsterModel.slab(s, Vector3(x + 0.3, OPENING_TOP + top_h * 0.72, front), Vector3(0.025, top_h * 0.5, 0.02), MORTAR, 816)
	return s


## A rough stone block to slump against (a stand-in for a wall): 1.7 wide, 1.4 high, 0.4 deep, centred on its foot.
static func _block_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(821, 0.05)
	MonsterModel.slab(s, Vector3(0, 0.6, 0), Vector3(1.7, 1.2, 0.42), STONE, 822, Vector3.ZERO, 0.03)
	MonsterModel.slab(s, Vector3(0.05, 1.28, 0.02), Vector3(1.6, 0.18, 0.40), STONE_LIGHT, 823, Vector3(0, 0, 2.0), 0.03)
	MonsterModel.slab(s, Vector3(-0.55, 0.05, -0.26), Vector3(0.24, 0.1, 0.16), STONE_DARK, 824, Vector3(0, 20.0, 0), 0.04)   # rubble
	MonsterModel.slab(s, Vector3(0.70, 0.04, -0.30), Vector3(0.14, 0.08, 0.12), STONE_DARK, 825, Vector3(0, -35.0, 0), 0.04)
	return s


# --- the skeleton's dormant poses (the grunt's rigid parts, its standing frame) ---------------------------------------------

## Laid out: straight, the skull turned toward the opening with its jaw dropped, both hands crossed on its chest over the
## sword, whose blade runs down its body to its feet.
static func _pose_lying(g: GruntModel) -> void:
	var body := g.parts["body"] as Node3D
	body.position = Vector3(0, GruntModel.BODY_Y, 0)
	body.rotation = Vector3.ZERO
	(g.parts["head"] as Node3D).rotation = Vector3(deg_to_rad(-6.0), deg_to_rad(-55.0), 0.0)
	(g.parts["jaw"] as Node3D).rotation = Vector3(-0.42, 0.0, 0.0)
	(g.parts["leg_l"] as Node3D).rotation = Vector3(0.0, 0.0, deg_to_rad(-3.0))
	(g.parts["leg_r"] as Node3D).rotation = Vector3(0.0, 0.0, deg_to_rad(3.0))
	_aim(g.parts["arm_l"], Vector3(0.12, 0.34, -0.24), 0.62)
	_aim(g.parts["arm_r"], Vector3(-0.10, 0.28, -0.26), 0.62)
	set_in_model(g, g.parts["weapon"], Transform3D(Basis.from_euler(Vector3(0.0, 0.0, PI)), Vector3(0.0, 1.10, -0.30)))


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
