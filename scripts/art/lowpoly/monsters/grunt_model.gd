class_name GruntModel
extends MonsterModel
## Grunt: a skeleton warrior of the bunker's old security detail. Bone-white faceted skeleton with ember
## eyes, a scrap of charcoal security tabard (gold badge, one epaulette) and a battered, rusted blade.
## Chunky bones (nothing thinner than a hand) so it still reads from the steep game camera.
##
## INTEGRATION: kind "grunt" -> MonsterModels.make("grunt"); see the full patch at the top of
## monster_model.gd. Hooks the monster calls: windup(_telegraph) every frame, attack_swing() at the
## strike, set_downed(true) / set_tint() / set_fade() on hit and death. grunt.gd needs no change.
##
## Faces local -Z, +X is its right (the sword is in the right hand). About 1.65 tall to the skull,
## ~0.75 wide with the sword arm. Rigid named parts (MeshInstance3D): body, head, jaw, tabard, arm_l,
## arm_r, leg_l, leg_r, weapon. head / tabard / arms / weapon hang under body (weapon under arm_r, in the
## fist); jaw under head; legs under the root.

const MODEL_SCALE := 1.10
const PART_NAMES: Array[String] = ["body", "head", "jaw", "tabard", "arm_l", "arm_r", "leg_l", "leg_r", "weapon"]

const BONE := Color(0.90, 0.85, 0.72)
const BONE_LIGHT := Color(0.98, 0.95, 0.84)
const BONE_DARK := Color(0.64, 0.58, 0.46)
const CAVITY := Color(0.34, 0.28, 0.24)
const VOID := Color(0.09, 0.05, 0.05)
const EMBER := Color(1.0, 0.20, 0.06)
const UNIFORM := Color(0.20, 0.17, 0.18)
const UNIFORM_DARK := Color(0.12, 0.10, 0.12)
const BADGE := Color(0.95, 0.74, 0.22)
const STEEL := Color(0.72, 0.77, 0.83)
const STEEL_LIGHT := Color(0.88, 0.92, 0.96)
const STEEL_DARK := Color(0.44, 0.48, 0.55)
const RUST := Color(0.60, 0.36, 0.22)
const GRIP := Color(0.36, 0.21, 0.12)
const BRASS := Color(0.80, 0.66, 0.34)

const BODY_Y := 0.80            ## pelvis centre
const HIP_Y := 0.74
const SHOULDER := Vector3(0.36, 0.60, 0.0)
const HAND := Vector3(0.0, -0.65, -0.08)    ## arm-local fist centre (where the sword's grip sits)
const LEG_X := 0.14


func _init() -> void:
	_setup_model("GruntModel", MODEL_SCALE)
	monster_kind = "grunt"
	ui_height = 1.85 * MODEL_SCALE
	has_own_weapon = true
	_build()
	apply_idle(0.0)


# ------------------------------------------------------------------ build

func _build() -> void:
	var body := _add_part("body", _body_soup(), self, Vector3(0, BODY_Y, 0))
	var head := _add_part("head", _head_soup(), body, Vector3(0, 0.86, -0.02))
	_add_part("jaw", _jaw_soup(), head, Vector3(0, -0.10, 0.05))
	_add_part("tabard", _tabard_soup(), body, Vector3.ZERO)
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var arm := _add_part("arm_" + side, _arm_soup(s), body, Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z))
		arm.rotation = Vector3(0.0, 0.0, 0.2 * s)
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(LEG_X * s, HIP_Y, 0.0))
	_add_part("weapon", _sword_soup(), parts["arm_r"] as Node3D, HAND)


## Pelvis, spine, ribcage (dark cavity with pale rib bands), collar bones and neck.
func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(101, 0.07)
	blob(s, Vector3(0, -0.04, 0), Vector3(0.25, 0.11, 0.15), BONE, 102, 0.14)                       # pelvis
	limb(s, Vector3(0, 0.0, 0.02), Vector3(0, 0.30, 0.03), 0.06, 0.06, 5, BONE_DARK, 103)           # spine
	slab(s, Vector3(0, 0.40, 0.0), Vector3(0.50, 0.40, 0.28), CAVITY, 104, Vector3.ZERO, 0.03)        # rib cavity
	for i in 4:
		var y := 0.25 + 0.115 * i
		slab(s, Vector3(0, y, -0.005), Vector3(0.56, 0.06, 0.33), BONE, 105 + i, Vector3.ZERO, 0.0)  # rib band
	slab(s, Vector3(0, 0.62, 0.02), Vector3(0.80, 0.08, 0.12), BONE_LIGHT, 110, Vector3.ZERO, 0.02)  # collar bone
	for x: float in [-0.38, 0.38]:
		blob(s, Vector3(x, 0.62, 0.0), Vector3(0.11, 0.10, 0.11), BONE, 111 + int(x * 10.0), 0.15)   # shoulder joints
	limb(s, Vector3(0, 0.62, -0.01), Vector3(0, 0.78, -0.02), 0.07, 0.06, 5, BONE_DARK, 114)         # neck
	return s


func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(121, 0.06)
	blob(s, Vector3.ZERO, Vector3(0.23, 0.20, 0.22), BONE, 122, 0.1, 1)                             # skull
	slab(s, Vector3(0, 0.05, -0.17), Vector3(0.38, 0.07, 0.12), BONE_DARK, 123, Vector3(-10, 0, 0), 0.02)   # brow
	for x: int in [-1, 1]:
		slab(s, Vector3(0.095 * x, 0.0, -0.19), Vector3(0.12, 0.11, 0.07), VOID, 124 + x, Vector3(0, 0, 16 * x), 0.0, 0.0)   # sockets
		slab(s, Vector3(0.095 * x, -0.005, -0.215), Vector3(0.075, 0.06, 0.03), glow(EMBER), 126 + x, Vector3(0, 0, 16 * x), 0.0, 0.0)   # ember eyes
		blob(s, Vector3(0.15 * x, -0.07, -0.15), Vector3(0.06, 0.05, 0.06), BONE_LIGHT, 128 + x, 0.2)   # cheekbones
	wedge(s, Vector3(0, -0.07, -0.20), Vector2(0.07, 0.04), Vector2(0.03, 0.03), 0.09, VOID, 130, Vector3.ZERO, 0.0, 0.0)   # nose hole
	slab(s, Vector3(0, -0.15, -0.14), Vector3(0.22, 0.05, 0.10), BONE_LIGHT, 131, Vector3.ZERO, 0.01)   # upper teeth
	return s


## Lower jaw, pivot at the hinge (so rotation.x opens it); teeth along the front edge.
func _jaw_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(141, 0.06)
	wedge(s, Vector3(0, -0.03, -0.11), Vector2(0.14, 0.14), Vector2(0.24, 0.20), 0.07, BONE, 142, Vector3.ZERO, 0.01)
	slab(s, Vector3(0, 0.02, -0.19), Vector3(0.20, 0.04, 0.05), BONE_LIGHT, 143, Vector3.ZERO, 0.01)
	return s


## A torn charcoal security tabard over the ribs: gold badge, a ragged hem and one epaulette.
func _tabard_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(151, 0.07)
	slab(s, Vector3(0, 0.15, 0.0), Vector3(0.54, 0.09, 0.36), UNIFORM_DARK, 161, Vector3.ZERO, 0.01)          # belt
	slab(s, Vector3(0, 0.26, -0.185), Vector3(0.34, 0.20, 0.05), UNIFORM, 152, Vector3(4, 0, 0), 0.012)       # ragged front flap
	slab(s, Vector3(0, 0.25, 0.18), Vector3(0.38, 0.22, 0.05), UNIFORM_DARK, 153, Vector3(-3, 0, 0), 0.012)   # back flap
	for i in 3:
		var x := -0.12 + 0.12 * i
		wedge(s, Vector3(x, 0.07 - 0.03 * (i % 2), -0.19), Vector2(0.10, 0.04), Vector2(0.12, 0.04), 0.16 + 0.06 * (i % 2), UNIFORM, 154 + i, Vector3(0, 0, (i - 1) * 8), 0.01)   # torn tails
	# a diagonal sash over the ribs, left shoulder to right hip, with the badge
	slab(s, Vector3(0.0, 0.46, -0.20), Vector3(0.10, 0.50, 0.04), UNIFORM, 163, Vector3(0, 0, -38), 0.01)
	slab(s, Vector3(-0.07, 0.50, -0.225), Vector3(0.10, 0.12, 0.03), BADGE, 158, Vector3(0, 0, -38), 0.0, 0.03)   # badge
	slab(s, Vector3(0.38, 0.69, 0.0), Vector3(0.24, 0.06, 0.22), UNIFORM, 159, Vector3(0, 0, -10), 0.01)   # epaulette
	slab(s, Vector3(0.38, 0.725, 0.0), Vector3(0.24, 0.025, 0.06), BADGE, 160, Vector3(0, 0, -10), 0.0, 0.03)
	slab(s, Vector3(0, 0.15, -0.185), Vector3(0.10, 0.08, 0.03), BADGE, 162, Vector3.ZERO, 0.0, 0.03)        # buckle
	return s


## Shoulder joint, upper arm, elbow, forearm and a hand, hanging down from the shoulder pivot.
func _arm_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(171 + side, 0.07)
	limb(s, Vector3(0, -0.02, 0), Vector3(0, -0.30, -0.02), 0.062, 0.054, 5, BONE, 172 + side)
	blob(s, Vector3(0, -0.31, -0.02), Vector3(0.07, 0.07, 0.07), BONE_LIGHT, 174 + side, 0.15)
	limb(s, Vector3(0, -0.32, -0.02), Vector3(0, -0.60, -0.07), 0.054, 0.046, 5, BONE, 176 + side)
	blob(s, HAND, Vector3(0.08, 0.085, 0.08), BONE_LIGHT, 178 + side, 0.15)
	return s


## Thigh, knee, shin, a chunky foot; pivot at the hip.
func _leg_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(181 + side, 0.07)
	limb(s, Vector3(0, -0.02, 0), Vector3(0, -0.38, -0.03), 0.085, 0.07, 5, BONE, 182 + side)
	blob(s, Vector3(0, -0.39, -0.04), Vector3(0.085, 0.085, 0.085), BONE_LIGHT, 184 + side, 0.15)
	limb(s, Vector3(0, -0.40, -0.04), Vector3(0, -0.68, 0.0), 0.07, 0.058, 5, BONE, 186 + side)
	blob(s, Vector3(0, -0.70, -0.08), Vector3(0.10, 0.055, 0.17), BONE_DARK, 188 + side, 0.12)
	return s


## A battered arming sword. Origin at the grip; the blade runs up +Y (so it can be re-aimed freely).
func _sword_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(191, 0.06)
	limb(s, Vector3(0, -0.12, 0), Vector3(0, 0.08, 0), 0.042, 0.042, 5, GRIP, 192)
	blob(s, Vector3(0, -0.15, 0), Vector3(0.06, 0.05, 0.06), BRASS, 193, 0.1)                       # pommel
	slab(s, Vector3(0, 0.10, 0), Vector3(0.46, 0.08, 0.12), STEEL_DARK, 194, Vector3(0, 0, 4), 0.02)   # crossguard
	slab(s, Vector3(0, 0.40, 0), Vector3(0.22, 0.60, 0.05), STEEL, 195, Vector3.ZERO, 0.02)          # blade
	s.merge(LowPoly.frustum(Vector2(0.22, 0.05), Vector2(0.03, 0.025), 0.26, STEEL, 196, 0.01, 1, Vector2(0.045, 0.0), 0.05), LowPoly.at(Vector3(0, 0.82, 0)))   # chipped, bent tip
	slab(s, Vector3(0, 0.40, 0), Vector3(0.06, 0.56, 0.062), STEEL_LIGHT, 197, Vector3.ZERO, 0.0)    # fuller
	slab(s, Vector3(0.06, 0.30, 0), Vector3(0.11, 0.20, 0.055), RUST, 198, Vector3(0, 0, 3), 0.01, 0.1)   # rust patches
	slab(s, Vector3(-0.05, 0.58, 0), Vector3(0.09, 0.15, 0.055), RUST, 199, Vector3(0, 0, -3), 0.01, 0.1)
	return s


# ------------------------------------------------------------------ animation

func apply_idle(t: float, speed: float = 0.0) -> void:
	if _downed:
		return
	var walk := clampf(speed / 4.0, 0.0, 1.0)
	var breath := sin(t * 2.0)
	var stride := sin(t * 8.5)
	var w := wind_e()
	var sw := _swing
	var body := parts["body"] as MeshInstance3D
	body.position.y = BODY_Y + breath * 0.012 - absf(stride) * 0.04 * walk - 0.05 * sw
	body.rotation = Vector3(0.14 * w - 0.24 * sw - 0.06 * walk, stride * 0.10 * walk - 0.25 * sw, 0.0)
	var head := parts["head"] as MeshInstance3D
	head.rotation = Vector3(sin(t * 1.3) * 0.03 + 0.12 * w - 0.12 * sw + sin(t * 17.0) * 0.012 * walk, 0.0, 0.0)
	var jaw := parts["jaw"] as MeshInstance3D
	jaw.rotation.x = -0.05 - 0.04 * (0.5 + 0.5 * sin(t * 1.7)) - 0.50 * w - 0.55 * sw - 0.1 * walk * absf(stride)
	(parts["leg_l"] as MeshInstance3D).rotation.x = stride * 0.7 * walk - 0.35 * sw
	(parts["leg_r"] as MeshInstance3D).rotation.x = -stride * 0.7 * walk + 0.25 * sw
	var sway := breath * 0.02
	var arm_l := parts["arm_l"] as MeshInstance3D
	arm_l.rotation = Vector3(-stride * 0.5 * walk + sway - 0.7 * w + 0.6 * sw, 0.0, -0.15 - 0.2 * w)
	# sword arm + blade: a is the arm's pitch, b the blade's own pitch in world terms (0 = straight up)
	var a_rest := -0.55 + stride * 0.35 * walk + sway
	var b_rest := -0.30
	var a := lerpf(a_rest, -2.55, w)
	var b := lerpf(b_rest, 0.95, w)
	a = lerpf(a, -0.95, sw)
	b = lerpf(b, -1.75, sw)
	var arm_r := parts["arm_r"] as MeshInstance3D
	arm_r.rotation = Vector3(a, 0.0, 0.32 - 0.2 * w)
	(parts["weapon"] as MeshInstance3D).rotation = Vector3(b - a, 0.0, -0.45 * (1.0 - w))


func _slump() -> void:
	(parts["body"] as MeshInstance3D).rotation = Vector3(-0.30, 0.0, 0.0)
	(parts["head"] as MeshInstance3D).rotation = Vector3(-0.45, 0.0, 0.0)
	(parts["jaw"] as MeshInstance3D).rotation.x = -0.55
	(parts["arm_l"] as MeshInstance3D).rotation = Vector3(0.1, 0.0, -0.45)
	(parts["arm_r"] as MeshInstance3D).rotation = Vector3(0.0, 0.0, 0.45)
	(parts["weapon"] as MeshInstance3D).rotation = Vector3(1.9, 0.0, 0.0)
	(parts["leg_l"] as MeshInstance3D).rotation.x = 0.0
	(parts["leg_r"] as MeshInstance3D).rotation.x = 0.0
