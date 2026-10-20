class_name PaviseModel
extends MonsterModel
## Pavise Crossbowman look (docs/design/combat-proposals.md §2; read test and decisions: docs/design/pavise-read-test.md).
## The game's model for the "pavise" kind (MonsterDefs, scripts/monsters/pavise.gd; combat-proposals.md §2 "As built"), and
## the lab's (scripts/art/lowpoly/monsters/pavise_lab.gd renders it). MonsterModels.make("pavise") builds the "above" carry
## (recommended in the read test and built as the default, 2026-10-20).
##
## The final look (the user, 2026-10-20, after the first read test): the grunt skeleton in a crimson tabard behind a
## door-sized pavise with an iron rim, a sight notch, a foot spike and a prop leg. Its front is painted crimson with a
## bone border and a bone skull; its back is raw pale wood, so the colour says which side you see. The heavy crossbow
## has an oversize, always-glowing bolt head. The pavise blocks while carried as well as planted.
##
## Where the crossbow rests when it is not aiming (`carry`, the two placements under test; the bow never passes through
## the shield: bow_shield_overlap() and tests/test_pavise_model.gd):
##   "side"   slung nose-down at the right hip, outside the shield's edge; it reloads there too (nose down, foot in
##            the stirrup, cranking).
##   "above"  shouldered, nose forward and up, over the shield's top; it reloads laid over the top rim in the notch.
##
## Shield states (set_shield): "carried" (walks behind it), "planted" (stamped in: aim 0 = reloading, aim 1 = aiming
## through the notch), "left" (shoved off it: the pavise stands alone ahead of it, or where set_left_anchor says in the
## world), "dropped" (lying flat in front of it), "broken" (a stub of planks on the arm, splinters on the floor). set_aim(k)
## is the AIM (the bow raised into the notch, planted); set_locked(true) is the last 0.4 s (a hotter flare). windup(t) is
## the SHIELD BASH's wind-up (the pavise drawn back) and attack_swing() the bash (shoved forward), in any state that holds
## it. set_stuck(n): n hero arrows stuck in the front.
##
## Faces local -Z, +X is its right; origin at the feet. Rigid named parts (MeshInstance3D): body, head, jaw, gear,
## arm_l, arm_r, leg_l, leg_r (the grunt's skeleton), weapon (the crossbow, under the root), string and bolt (under
## weapon), shield (under the root), prop and arrows (under shield), shield_broken and debris (under the root). Not a
## part: the bolt head's flare (an additive billboard).

const CARRY_STYLES: Array[String] = ["side", "above"]
## The carry the game builds (pavise-read-test.md: (b) "above", recommended, built as the default).
const GAME_CARRY := "above"
## The rigid parts the game animates (test_monster_models).
const PART_NAMES: Array[String] = ["body", "head", "jaw", "gear", "arm_l", "arm_r", "leg_l", "leg_r", "weapon", "string", "bolt", "shield", "prop"]
const STATES: Array[String] = ["carried", "planted", "left", "dropped", "broken"]
const MODEL_SCALE := 1.20

# the skeleton (the grunt's paint)
const BONE := Color(0.90, 0.85, 0.72)
const BONE_LIGHT := Color(0.98, 0.95, 0.84)
const BONE_DARK := Color(0.64, 0.58, 0.46)
const CAVITY := Color(0.34, 0.28, 0.24)
const VOID := Color(0.09, 0.05, 0.05)
const EMBER := Color(1.0, 0.20, 0.06)
const BADGE := Color(0.95, 0.74, 0.22)
# wood, iron, paint
const PLANK := Color(0.70, 0.54, 0.34)
const PLANK2 := Color(0.60, 0.45, 0.28)
const IRON := Color(0.30, 0.31, 0.34)
const IRON_LIGHT := Color(0.50, 0.52, 0.56)
const CRIMSON := Color(0.82, 0.10, 0.10)
const CRIMSON2 := Color(0.74, 0.08, 0.09)
const CRIMSON_DARK := Color(0.52, 0.06, 0.07)
const CLOTH_DARK := Color(0.36, 0.05, 0.06)
const PAINT_BONE := Color(0.97, 0.93, 0.80)
const PAINT_VOID := Color(0.10, 0.04, 0.04)
const STEEL_DARK := Color(0.27, 0.29, 0.33)
const STOCK := Color(0.32, 0.20, 0.12)
const STOCK_LIGHT := Color(0.46, 0.30, 0.18)
const STRING_COL := Color(0.92, 0.88, 0.74)
const SHAFT := Color(0.84, 0.72, 0.48)                ## a hero arrow (Wick's paint)
const FLETCHES: Array[Color] = [Color(0.88, 0.26, 0.20), Color(0.25, 0.70, 0.68), Color(0.96, 0.82, 0.30)]
const BOLT_SHAFT := Color(0.22, 0.15, 0.11)
const BOLT_VANE := Color(0.72, 0.12, 0.08)
const TIP := Color(1.0, 0.72, 0.22)                   ## the bolt head: a hot enemy glow

const BODY_Y := 0.80
const HIP_Y := 0.74
const SHOULDER := Vector3(0.36, 0.60, 0.0)
const ARM_LEN := 0.65
const LEG_X := 0.14
# the pavise (model units; x1.2 in the world: 1.24 wide, 1.87 tall)
const W := 1.035
const H := 1.56
const TH := 0.08
const PLANKS := 5
const NOTCH := 0.10
const SADDLE := 0.08                                   ## the notch's iron saddle stands this far above the notch
const SHIELD_Z := 0.50
const SHIELD_X := 0.04
const CROUCH := 0.08
const LEFT_GAP := 1.5                                  ## "left": how far the pavise stands ahead of it
const TIP_K := 1.9                                     ## the bolt head's size
## Crossbow-local points (origin at the trigger grip, the bolt flies down -Z).
const REAR_GRIP := Vector3(0.0, -0.07, 0.03)
const FORE_GRIP := Vector3(0.0, -0.07, -0.08)
const NUT_Z := -0.16
const PROD_Z := -0.56
const PROD_HALF := 0.44

const FLARE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.3, 0.08, 1.0);
uniform float energy = 2.0;
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = clamp(1.0 - d, 0.0, 1.0);
	a = a * a;
	float core = smoothstep(0.45, 0.0, d);
	ALBEDO = (color.rgb + vec3(core * 0.7)) * energy * a;
	ALPHA = a;
}
"""

var carry := "side"
var aim_k := 0.0                  ## planted: 0 = reloading (cranking), 1 = aiming through the notch (set_aim)
var _state := "carried"
var _locked := false
var _anchored := false            ## "left": the pavise stands at _anchor_pos / _anchor_yaw in the world (set_left_anchor)
var _anchor_pos := Vector3.ZERO
var _anchor_yaw := 0.0
var _stuck := 0
var _thin_mat: ShaderMaterial
var _flare: MeshInstance3D
var _flare_mat: ShaderMaterial


func _init(carry_style: String = GAME_CARRY) -> void:
	carry = carry_style if CARRY_STYLES.has(carry_style) else "side"
	_setup_model("PaviseModel_" + carry, MODEL_SCALE)
	monster_kind = "pavise"
	ui_height = 1.9 * MODEL_SCALE
	has_own_weapon = true
	glow_flare = 0.9
	_thin_mat = MonsterMaterial.make(1.1)
	_build()
	apply_idle(0.0)


# ------------------------------------------------------------------ build

func _build() -> void:
	var body := _add_part("body", _body_soup(), self, Vector3(0, BODY_Y, 0))
	var head := _add_part("head", _head_soup(), body, Vector3(0, 0.86, -0.02))
	_add_part("jaw", _jaw_soup(), head, Vector3(0, -0.10, 0.05))
	_add_part("gear", _tabard_soup(), body, Vector3.ZERO)
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		_add_part("arm_" + side, _arm_soup(s), body, Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z))
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(LEG_X * s, HIP_Y, 0.0))
	var bow := _add_part("weapon", _bow_soup(), self, Vector3(0.4, 1.0, 0.0))
	_add_part("string", _string_soup(), bow, Vector3.ZERO).material_override = _thin_mat
	var bolt := _add_part("bolt", _bolt_soup(), bow, Vector3(0.0, 0.075, NUT_Z))
	var shield := _add_part("shield", _shield_soup(), self, Vector3(0, 0, -SHIELD_Z))
	_add_part("prop", _prop_soup(), shield, Vector3(0.0, H * 0.66, TH * 0.5 + 0.05))
	var arrows := _add_part("arrows", _arrows_soup(9), shield, Vector3.ZERO)
	arrows.material_override = _thin_mat
	arrows.visible = false
	_add_part("shield_broken", _broken_soup(), self, Vector3.ZERO).visible = false
	_add_part("debris", _debris_soup(), self, Vector3.ZERO).visible = false
	_flare_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FLARE_SHADER
	_flare_mat.shader = sh
	_flare_mat.set_shader_parameter("color", TIP)
	_flare = MeshInstance3D.new()
	_flare.name = "TipFlare"
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_flare.mesh = q
	_flare.material_override = _flare_mat
	_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flare.position = Vector3(0.0, 0.0, -0.66 - 0.06 * TIP_K)
	bolt.add_child(_flare)


# ------------------------------------------------------------------ the skeleton (the grunt's, in crimson)

func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(601, 0.07)
	blob(s, Vector3(0, -0.04, 0), Vector3(0.25, 0.11, 0.15), BONE, 602, 0.14)                       # pelvis
	limb(s, Vector3(0, 0.0, 0.02), Vector3(0, 0.30, 0.03), 0.06, 0.06, 5, BONE_DARK, 603)           # spine
	slab(s, Vector3(0, 0.40, 0.0), Vector3(0.50, 0.40, 0.28), CAVITY, 604, Vector3.ZERO, 0.03)        # rib cavity
	for i in 4:
		slab(s, Vector3(0, 0.25 + 0.115 * i, -0.005), Vector3(0.56, 0.06, 0.33), BONE, 605 + i)        # rib bands
	slab(s, Vector3(0, 0.62, 0.02), Vector3(0.80, 0.08, 0.12), BONE_LIGHT, 610, Vector3.ZERO, 0.02)  # collar bone
	for x: float in [-0.38, 0.38]:
		blob(s, Vector3(x, 0.62, 0.0), Vector3(0.11, 0.10, 0.11), BONE, 611 + int(x * 10.0), 0.15)   # shoulder joints
	limb(s, Vector3(0, 0.62, -0.01), Vector3(0, 0.78, -0.02), 0.07, 0.06, 5, BONE_DARK, 614)         # neck
	return s


func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(621, 0.06)
	blob(s, Vector3.ZERO, Vector3(0.23, 0.20, 0.22), BONE, 622, 0.1, 1)                             # skull
	slab(s, Vector3(0, 0.05, -0.17), Vector3(0.38, 0.07, 0.12), BONE_DARK, 623, Vector3(-10, 0, 0), 0.02)   # brow
	for x: int in [-1, 1]:
		slab(s, Vector3(0.095 * x, 0.0, -0.19), Vector3(0.12, 0.11, 0.07), VOID, 624 + x, Vector3(0, 0, 16 * x), 0.0, 0.0)
		slab(s, Vector3(0.095 * x, -0.005, -0.215), Vector3(0.075, 0.06, 0.03), glow(EMBER), 626 + x, Vector3(0, 0, 16 * x), 0.0, 0.0)
		blob(s, Vector3(0.15 * x, -0.07, -0.15), Vector3(0.06, 0.05, 0.06), BONE_LIGHT, 628 + x, 0.2)
	wedge(s, Vector3(0, -0.07, -0.20), Vector2(0.07, 0.04), Vector2(0.03, 0.03), 0.09, VOID, 630, Vector3.ZERO, 0.0, 0.0)
	slab(s, Vector3(0, -0.15, -0.14), Vector3(0.22, 0.05, 0.10), BONE_LIGHT, 631, Vector3.ZERO, 0.01)
	return s


func _jaw_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(641, 0.06)
	wedge(s, Vector3(0, -0.03, -0.11), Vector2(0.14, 0.14), Vector2(0.24, 0.20), 0.07, BONE, 642, Vector3.ZERO, 0.01)
	slab(s, Vector3(0, 0.02, -0.19), Vector3(0.20, 0.04, 0.05), BONE_LIGHT, 643, Vector3.ZERO, 0.01)
	return s


## The grunt's tabard in its shield's crimson, and a bolt quiver on the right hip.
func _tabard_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(651, 0.07)
	slab(s, Vector3(0, 0.15, 0.0), Vector3(0.54, 0.09, 0.36), CLOTH_DARK, 652, Vector3.ZERO, 0.01)          # belt
	slab(s, Vector3(0, 0.26, -0.185), Vector3(0.34, 0.20, 0.05), CRIMSON_DARK, 653, Vector3(4, 0, 0), 0.012)  # front flap
	slab(s, Vector3(0, 0.25, 0.18), Vector3(0.38, 0.22, 0.05), CLOTH_DARK, 654, Vector3(-3, 0, 0), 0.012)    # back flap
	slab(s, Vector3(0.0, 0.46, -0.20), Vector3(0.10, 0.50, 0.04), CRIMSON_DARK, 655, Vector3(0, 0, -38), 0.01)   # sash
	slab(s, Vector3(-0.07, 0.50, -0.225), Vector3(0.10, 0.12, 0.03), BADGE, 656, Vector3(0, 0, -38), 0.0, 0.03)
	slab(s, Vector3(0.38, 0.69, 0.0), Vector3(0.24, 0.06, 0.22), CRIMSON_DARK, 657, Vector3(0, 0, -10), 0.01)  # epaulette
	slab(s, Vector3(0, 0.15, -0.185), Vector3(0.10, 0.08, 0.03), BADGE, 658, Vector3.ZERO, 0.0, 0.03)         # buckle
	limb(s, Vector3(0.30, -0.05, 0.10), Vector3(0.34, 0.30, 0.16), 0.07, 0.08, 5, STOCK, 659, 0.01)          # quiver
	for i in 3:
		limb(s, Vector3(0.30 + 0.035 * i, 0.28, 0.15), Vector3(0.31 + 0.04 * i, 0.42, 0.17), 0.016, 0.016, 4, BOLT_SHAFT, 660 + i)
		limb(s, Vector3(0.31 + 0.04 * i, 0.38, 0.17), Vector3(0.315 + 0.04 * i, 0.46, 0.175), 0.04, 0.012, 3, BOLT_VANE, 664 + i)
	return s


func _arm_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(711 + side, 0.07)
	limb(s, Vector3(0, -0.02, 0), Vector3(0, -0.30, -0.02), 0.062, 0.054, 5, BONE, 712 + side)
	blob(s, Vector3(0, -0.31, -0.02), Vector3(0.07, 0.07, 0.07), BONE_LIGHT, 714 + side, 0.15)
	limb(s, Vector3(0, -0.32, -0.02), Vector3(0, -0.60, -0.04), 0.054, 0.046, 5, BONE, 716 + side)
	blob(s, Vector3(0, -0.64, -0.04), Vector3(0.08, 0.085, 0.08), BONE_LIGHT, 718 + side, 0.15)
	return s


func _leg_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(731 + side, 0.07)
	limb(s, Vector3(0, -0.02, 0), Vector3(0, -0.38, -0.03), 0.085, 0.07, 5, BONE, 732 + side)
	blob(s, Vector3(0, -0.39, -0.04), Vector3(0.085, 0.085, 0.085), BONE_LIGHT, 734 + side, 0.15)
	limb(s, Vector3(0, -0.40, -0.04), Vector3(0, -0.68, 0.0), 0.07, 0.058, 5, BONE, 736 + side)
	blob(s, Vector3(0, -0.70, -0.08), Vector3(0.10, 0.055, 0.17), BONE_DARK, 738 + side, 0.12)
	return s


# ------------------------------------------------------------------ the crossbow

## A heavy crossbow. Origin at the trigger grip; the bolt flies down -Z.
func _bow_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(751, 0.06)
	slab(s, Vector3(0, 0.0, -0.18), Vector3(0.09, 0.10, 0.80), STOCK, 752, Vector3.ZERO, 0.01)            # stock
	slab(s, Vector3(0, -0.03, 0.24), Vector3(0.12, 0.17, 0.06), STOCK_LIGHT, 753, Vector3(8, 0, 0), 0.01)   # butt plate
	slab(s, Vector3(0, 0.058, NUT_Z), Vector3(0.11, 0.04, 0.08), IRON, 754, Vector3.ZERO, 0.0)               # the nut
	limb(s, Vector3(0, -0.05, -0.02), Vector3(0, -0.13, 0.07), 0.018, 0.012, 4, IRON, 755)                  # trigger
	for sgn: float in [-1.0, 1.0]:   # the prod: a thick, swept steel bow across the front
		var mid := Vector3(sgn * PROD_HALF * 0.5, 0.04, PROD_Z + 0.05)
		limb(s, Vector3(0, 0.04, PROD_Z), mid, 0.045, 0.036, 5, STEEL_DARK, 756 + int(sgn), 0.005)
		limb(s, mid, Vector3(sgn * PROD_HALF, 0.04, PROD_Z + 0.16), 0.036, 0.024, 5, STEEL_DARK, 758 + int(sgn), 0.005)
		blob(s, Vector3(sgn * PROD_HALF, 0.04, PROD_Z + 0.16), Vector3(0.035, 0.035, 0.035), IRON_LIGHT, 760 + int(sgn), 0.1)
	slab(s, Vector3(0, 0.04, PROD_Z), Vector3(0.14, 0.12, 0.10), IRON, 762, Vector3.ZERO, 0.01)              # bow block
	limb(s, Vector3(-0.07, 0.0, -0.62), Vector3(-0.08, -0.04, -0.74), 0.018, 0.018, 4, IRON, 763)          # the stirrup
	limb(s, Vector3(0.07, 0.0, -0.62), Vector3(0.08, -0.04, -0.74), 0.018, 0.018, 4, IRON, 764)
	limb(s, Vector3(-0.08, -0.04, -0.74), Vector3(0.08, -0.04, -0.74), 0.018, 0.018, 4, IRON, 765)
	# the winding crank at the butt (a windlass drum and a handle)
	s.merge(LowPoly.cylinder(0.05, 0.05, 0.22, 6, IRON, 766, 0.0), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0.02, 0.15)))
	limb(s, Vector3(0.11, 0.02, 0.15), Vector3(0.13, 0.15, 0.15), 0.02, 0.02, 4, IRON_LIGHT, 767)
	limb(s, Vector3(0.13, 0.15, 0.15), Vector3(0.20, 0.15, 0.15), 0.025, 0.025, 4, STOCK_LIGHT, 768)
	return s


## The drawn string, from the prod tips back to the nut.
func _string_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(771, 0.0)
	var nut := Vector3(0, 0.07, NUT_Z + 0.03)
	for sgn: float in [-1.0, 1.0]:
		limb(s, Vector3(sgn * PROD_HALF, 0.04, PROD_Z + 0.16), nut, 0.013, 0.013, 4, STRING_COL, 772 + int(sgn), 0.0, 0.0)
	return s


## The loaded bolt, origin at the nut, flying down -Z, with an oversize glowing head.
func _bolt_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(781, 0.04)
	var nose := -0.58
	limb(s, Vector3(0, 0, 0.02), Vector3(0, 0, nose), 0.022, 0.022, 4, BOLT_SHAFT, 782, 0.0, 0.0)
	for i in 2:
		slab(s, Vector3(0, 0, -0.05), Vector3(0.10, 0.012, 0.12), BOLT_VANE, 783 + i, Vector3(0, 0, 90.0 * i + 45.0), 0.0, 0.03)
	limb(s, Vector3(0, 0, nose), Vector3(0, 0, nose - 0.17 * TIP_K), 0.06 * TIP_K, 0.0, 4, glow(TIP), 786, 0.0, 0.0)      # head
	limb(s, Vector3(0, 0, nose + 0.035), Vector3(0, 0, nose), 0.035 * TIP_K, 0.06 * TIP_K, 4, glow(TIP), 787, 0.0, 0.0)  # socket
	return s


# ------------------------------------------------------------------ the pavise

static func _plank_x(i: int) -> float:
	return -W * 0.5 + W / PLANKS * (i + 0.5)


static func _plank_h(i: int) -> float:
	return H - NOTCH if i == PLANKS / 2 else H


## Origin at the bottom centre of the boards (the foot spike below it), the front faces -Z. Raw pale planks; the
## front painted crimson with a bone border and skull inside a proud iron rim; braces and a grip on the back.
func _shield_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(801, 0.06)
	var pw := W / PLANKS
	for i in PLANKS:
		var tz := TH + (0.008 if i % 2 == 0 else -0.008)    # alternate depths: no two neighbours flush
		slab(s, Vector3(_plank_x(i), _plank_h(i) * 0.5, 0.0), Vector3(pw, _plank_h(i), tz), PLANK if i % 2 == 0 else PLANK2, 802 + i, Vector3.ZERO, 0.004)
	var f := TH * 0.5 + 0.004                              # the front of the thicker planks
	limb(s, Vector3(0, 0.03, 0), Vector3(0, -0.22, 0), 0.06, 0.0, 5, IRON, 810)            # the foot spike
	# the paint: crimson over each plank's front, a bone border, a skull, a ridge below it
	for i in PLANKS:
		var ph := _plank_h(i)
		slab(s, Vector3(_plank_x(i), ph * 0.5, -(f + 0.008)), Vector3(pw, ph - 0.01, 0.01), CRIMSON if i % 2 == 0 else CRIMSON2, 820 + i, Vector3.ZERO, 0.0, 0.03)
		slab(s, Vector3(_plank_x(i), ph - 0.075, -(f + 0.019 + 0.003 * (i % 2))), Vector3(pw, 0.06, 0.012), PAINT_BONE, 826 + i, Vector3.ZERO, 0.0, 0.03)
	for sx: float in [-1.0, 1.0]:
		slab(s, Vector3(sx * (W * 0.5 - 0.07), (H - 0.10) * 0.5, -(f + 0.026)), Vector3(0.06, H - 0.20, 0.012), PAINT_BONE, 832 + int(sx > 0.0), Vector3.ZERO, 0.0, 0.03)
	slab(s, Vector3(0, 0.10, -(f + 0.030)), Vector3(W - 0.12, 0.06, 0.012), PAINT_BONE, 835, Vector3.ZERO, 0.0, 0.03)
	var sy := H * 0.62
	s.merge(LowPoly.boulder(Vector3(0.21, 0.18, 0.03), 0, 0.0, PAINT_BONE, 836, 0.03), LowPoly.at(Vector3(0, sy, -(f + 0.040))))
	slab(s, Vector3(0, sy - 0.18, -(f + 0.034)), Vector3(0.21, 0.08, 0.012), PAINT_BONE, 837, Vector3.ZERO, 0.0, 0.03)
	for sx: float in [-1.0, 1.0]:
		slab(s, Vector3(sx * 0.08, sy - 0.01, -(f + 0.068)), Vector3(0.095, 0.085, 0.012), PAINT_VOID, 838 + int(sx > 0.0), Vector3(0, 0, sx * 14.0), 0.0, 0.0)
	wedge(s, Vector3(0, sy - 0.095, -(f + 0.066)), Vector2(0.05, 0.012), Vector2(0.015, 0.012), 0.06, PAINT_VOID, 840, Vector3.ZERO, 0.0, 0.0)
	slab(s, Vector3(0, H * 0.26, -(f + 0.030)), Vector3(0.08, H * 0.30, 0.05), CRIMSON_DARK, 841, Vector3.ZERO, 0.004)
	# the iron rim, proud of the paint; the top in two runs either side of the notch, a saddle in it
	for sx: float in [-1.0, 1.0]:
		slab(s, Vector3(sx * W * 0.5, H * 0.5, 0.0), Vector3(0.06, H + 0.04, TH + 0.07), IRON, 811 + int(sx))
	slab(s, Vector3(0, 0.02, 0.0), Vector3(W + 0.10, 0.07, TH + 0.08), IRON, 814)
	var seg := (W - pw) * 0.5
	for sx: float in [-1.0, 1.0]:
		# from just short of the notch (its ends off the planks' sides) to past the side bars
		slab(s, Vector3(sx * (pw * 0.5 + 0.012 + (seg + 0.038) * 0.5), H, 0.0), Vector3(seg + 0.038, 0.06, TH + 0.08), IRON, 815 + int(sx))
	slab(s, Vector3(0, H - NOTCH + SADDLE * 0.5 - 0.03, 0.0), Vector3(pw + 0.02, SADDLE + 0.06, TH + 0.09), IRON_LIGHT, 818)
	for i in 4:
		for sx: float in [-1.0, 1.0]:
			blob(s, Vector3(sx * W * 0.5, 0.25 + i * 0.36, -(TH * 0.5 + 0.045)), Vector3(0.024, 0.024, 0.012), IRON_LIGHT, 842 + i * 2 + int(sx > 0.0), 0.0)
	# the back: two crossed braces and a grip
	var bz := TH * 0.5 + 0.004
	slab(s, Vector3(0, H * 0.45, bz + 0.025), Vector3(0.06, H * 1.02, 0.04), PLANK2, 850, Vector3(0, 0, 24), 0.004)
	slab(s, Vector3(0, H * 0.45, bz + 0.032), Vector3(0.06, H * 1.02, 0.04), PLANK2, 851, Vector3(0, 0, -24), 0.004)
	slab(s, Vector3(0, H * 0.55, bz + 0.07), Vector3(0.22, 0.05, 0.05), STOCK_LIGHT, 852)
	for x: float in [-0.10, 0.10]:
		slab(s, Vector3(x, H * 0.55, bz + 0.035), Vector3(0.04, 0.07, 0.07), STOCK, 853 + int(x * 10.0))
	return s


## The prop leg on the back: hangs from its hinge; planted it swings out to the floor behind.
func _prop_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(951, 0.06)
	var pl := H * 0.74
	limb(s, Vector3(0, 0.02, 0), Vector3(0, -pl, 0), 0.035, 0.03, 5, STOCK, 952)
	limb(s, Vector3(0, -pl, 0), Vector3(0, -pl - 0.07, 0), 0.03, 0.0, 4, IRON, 953)
	s.merge(LowPoly.cylinder(0.045, 0.045, 0.10, 6, IRON, 954, 0.0), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO))
	return s


## A stub of the shield (the outer planks, splintered) for "broken"; same origin as the shield.
func _broken_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(961, 0.06)
	var pw := W / PLANKS
	var hs: Array[float] = [H * 0.78, H * 0.52]
	for i in 2:
		var x := _plank_x(i)
		var tz := TH + (0.008 if i % 2 == 0 else -0.008)
		slab(s, Vector3(x, hs[i] * 0.5, 0.0), Vector3(pw, hs[i], tz), PLANK, 962 + i, Vector3.ZERO, 0.004)
		slab(s, Vector3(x, hs[i] * 0.5, -(TH * 0.5 + 0.012)), Vector3(pw, hs[i] - 0.02, 0.01), CRIMSON, 964 + i, Vector3.ZERO, 0.0, 0.03)
		for k in 2:   # jagged splinters off the broken top
			var sx := x - pw * 0.25 + pw * 0.5 * k
			limb(s, Vector3(sx, hs[i] - 0.02, 0.0), Vector3(sx + 0.03 * (k * 2 - 1), hs[i] + 0.12 + 0.06 * k, 0.0), 0.04, 0.0, 3, PLANK, 966 + i * 2 + k)
	slab(s, Vector3(-W * 0.5, H * 0.40, 0.0), Vector3(0.06, H * 0.80, TH + 0.03), IRON, 970)
	slab(s, Vector3(-W * 0.5 + pw, 0.02, 0.0), Vector3(pw * 2.0 + 0.08, 0.07, TH + 0.04), IRON, 971)
	slab(s, Vector3(-W * 0.5 + pw, H * 0.40, TH * 0.5 + 0.03), Vector3(pw * 2.0, 0.06, 0.04), PLANK2, 972)
	return s


## Splinters and boards on the floor (root space, in front of it) for "broken".
func _debris_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(981, 0.06)
	var pw := W / PLANKS
	var bits: Array[Vector4] = [Vector4(0.25, -1.05, 0.9, 20.0), Vector4(-0.35, -1.30, 0.6, -35.0), Vector4(0.55, -0.70, 0.45, 70.0), Vector4(-0.05, -1.60, 0.35, 5.0)]
	for i in bits.size():
		var b := bits[i]
		slab(s, Vector3(b.x, TH * 0.5 + 0.003 * i, b.y), Vector3(pw, TH, b.z), PLANK, 982 + i, Vector3(0, b.w, 0), 0.01)
	slab(s, Vector3(0.25, TH + 0.009, -1.05), Vector3(pw - 0.02, 0.01, 0.86), CRIMSON, 988, Vector3(0, 20.0, 0), 0.0, 0.03)
	for i in 5:
		var a := 0.9 * i
		limb(s, Vector3(0.3 * cos(a), 0.02, -0.9 + 0.4 * sin(a)), Vector3(0.3 * cos(a) + 0.18, 0.02, -0.9 + 0.4 * sin(a) + 0.08), 0.025, 0.0, 3, PLANK, 990 + i)
	return s


## Hero arrows stuck in the front, n of them (seeded: the same arrows every time).
func _arrows_soup(n: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1001, 0.04)
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var f := TH * 0.5 + 0.004
	for i in n:
		var p := Vector3(r.randf_range(-0.36, 0.36) * W, r.randf_range(0.22, 0.80) * H, -f + 0.04)
		var d := Vector3(r.randf_range(-0.30, 0.30), r.randf_range(-0.05, 0.35), -1.0).normalized()
		var tail := p + d * 0.62
		limb(s, p, tail - d * 0.05, 0.018, 0.018, 4, SHAFT, 1002 + i * 3, 0.0, 0.0)
		limb(s, tail - d * 0.16, tail, 0.055, 0.02, 3, FLETCHES[i % FLETCHES.size()], 1003 + i * 3, 0.0, 0.03)
		limb(s, p - d * 0.02, p + d * 0.05, 0.038, 0.028, 5, BOLT_SHAFT, 1004 + i * 3, 0.0, 0.0)   # a splintered ring round the hole
	return s


# ------------------------------------------------------------------ hooks

## "carried", "planted", "left", "dropped" or "broken".
func set_shield(state: String) -> void:
	_state = state if STATES.has(state) else "planted"
	var broken := _state == "broken"
	(parts["shield"] as MeshInstance3D).visible = not broken
	(parts["shield_broken"] as MeshInstance3D).visible = broken
	(parts["debris"] as MeshInstance3D).visible = broken
	_refresh()


func shield_state() -> String:
	return _state


## The aim (planted): 0 = reloading, 1 = the stock on the saddle, aiming.
func set_aim(k: float) -> void:
	aim_k = clampf(k, 0.0, 1.0)
	_update_fx(aim_k)
	_refresh()


## "left": the pavise stands on its own at this world point (its foot) with this yaw (the visual's: atan2(-f.x, -f.z)),
## wherever the crossbowman goes.
func set_left_anchor(pos: Vector3, yaw: float) -> void:
	_anchored = true
	_anchor_pos = pos
	_anchor_yaw = yaw


## The last 0.4 s of the aim: the flare runs hot.
func set_locked(on: bool) -> void:
	_locked = on
	_refresh()


## n hero arrows stuck in the front of the pavise (0 = none).
func set_stuck(n: int) -> void:
	_stuck = maxi(n, 0)
	var mi := parts["arrows"] as MeshInstance3D
	mi.visible = _stuck > 0
	if _stuck > 0:
		mi.mesh = _arrows_soup(_stuck).to_mesh()


## The bolt head (world space) for sight lines and the shot.
func tip_position() -> Vector3:
	return _flare.global_position


## The point on the front of the shield where a blocked hit lands (world), at height share `v` (0..1).
func shield_point(v: float = 0.6) -> Vector3:
	var sh := parts["shield"] as MeshInstance3D
	return sh.global_transform * Vector3(0.05, H * v, -TH * 0.5 - 0.06)


## Frozen lab pose: state, aim 0..1 (planted: 0 = reloading), walk speed (0 = standing) and a time for the cycles.
func pose_state(state: String, aim: float = 0.0, walk_speed: float = 0.0, t: float = 0.6, locked: bool = false) -> void:
	idle_enabled = false
	_locked = locked
	aim_k = clampf(aim, 0.0, 1.0)
	_wind = 0.0
	_swing = 0.0
	_state = state
	set_shield(state)
	_update_glow()
	apply_idle(t, walk_speed)


## How many sample points of the crossbow (stock, prod, string, bolt: every vertex, edge midpoint and face centre) lie
## inside the pavise's solid (the boards, rim and back fittings, less the notch), in the current pose. 0 = clear.
func bow_shield_overlap() -> int:
	return bow_shield_hits().size()


## The offending points of bow_shield_overlap(), in the shield's own space (for reports).
func bow_shield_hits() -> PackedVector3Array:
	var out := PackedVector3Array()
	var sh := parts["shield"] as MeshInstance3D
	if _state == "broken" or not sh.visible:
		return out
	var to_shield := sh.transform.affine_inverse()
	var bow := parts["weapon"] as MeshInstance3D
	for mi: MeshInstance3D in [bow, parts["string"], parts["bolt"]]:
		var xf := bow.transform if mi == bow else bow.transform * mi.transform
		var v := mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for i in range(0, v.size(), 3):
			var a := xf * v[i]
			var b := xf * v[i + 1]
			var c := xf * v[i + 2]
			for p: Vector3 in [a, b, c, (a + b) * 0.5, (b + c) * 0.5, (c + a) * 0.5, (a + b + c) / 3.0]:
				var q := to_shield * p
				if _in_shield(q):
					out.append(q)
	return out


## Shield-local point inside the pavise's solid: the boards with their paint and rim (less the sight notch above its
## saddle), the two crossed braces and the grip on the back.
static func _in_shield(p: Vector3) -> bool:
	if absf(p.x) > W * 0.5 + 0.035 or p.y < -0.01 or p.y > H + 0.035:
		return false
	var pw := W / PLANKS
	var in_notch := absf(p.x) < pw * 0.5 and p.y > H - NOTCH + SADDLE
	if not in_notch and p.z > -(TH * 0.5 + 0.08) and p.z < TH * 0.5 + 0.045:
		return true   # boards, paint, skull, rim
	if p.z < TH * 0.5 or p.z > TH * 0.5 + 0.11:
		return false
	if absf(p.x) < 0.14 and absf(p.y - H * 0.55) < 0.06:
		return true   # the grip
	for sgn: float in [-1.0, 1.0]:   # the braces: 24 degrees off upright through (0, 0.45 H)
		var d := Vector2(p.x, p.y - H * 0.45)
		var axis := Vector2(-sgn * sin(deg_to_rad(24.0)), cos(deg_to_rad(24.0)))
		if absf(d.dot(axis)) < H * 0.51 and absf(d.cross(axis)) < 0.045 and p.z < TH * 0.5 + 0.06:
			return true
	return false


# ------------------------------------------------------------------ animation

func apply_idle(t: float, speed: float = 0.0) -> void:
	if _downed:
		return
	var walk := clampf(speed / 2.5, 0.0, 1.0)
	var breath := sin(t * 2.0)
	var stride := sin(t * 7.0)
	var w := aim_k * aim_k * (3.0 - 2.0 * aim_k)
	var bash := wind_e()                       # the shield bash: drawn back (windup), shoved forward (_swing)
	var body := parts["body"] as MeshInstance3D
	var head := parts["head"] as MeshInstance3D
	var leg_l := parts["leg_l"] as MeshInstance3D
	var leg_r := parts["leg_r"] as MeshInstance3D
	var prop := parts["prop"] as MeshInstance3D
	var planted_xf := Transform3D(Basis(Vector3.RIGHT, 0.06), Vector3(SHIELD_X, -0.03, -SHIELD_Z))
	var shield_xf := planted_xf
	var bow_xf: Transform3D
	var hand_l: Vector3
	var hand_r_local := REAR_GRIP
	leg_l.position = Vector3(-LEG_X, HIP_Y, 0.0)
	leg_r.position = Vector3(LEG_X, HIP_Y, 0.0)
	(parts["jaw"] as MeshInstance3D).rotation.x = -0.06 - 0.05 * (0.5 + 0.5 * sin(t * 1.7)) - 0.25 * w
	match _state:
		"planted":
			body.position = Vector3(0, BODY_Y - CROUCH + breath * 0.008, 0)
			body.rotation = Vector3(-0.08 - 0.06 * w, 0.0, 0.0)
			head.rotation = Vector3(sin(t * 1.3) * 0.02 - 0.10 * w, 0.0, 0.05 * w)
			leg_l.rotation = Vector3(0.34, 0.0, -0.08)
			leg_r.rotation = Vector3(-0.30, 0.0, 0.08)
			leg_l.position.y -= CROUCH * 0.4
			leg_r.position.y -= CROUCH * 0.4
			prop.rotation = Vector3(-0.50, 0.0, 0.0)
			bow_xf = _bow_planted_xf(planted_xf, w, t)
			hand_l = bow_xf * (FORE_GRIP if w > 0.5 else _reload_left_grip())
			if w <= 0.5:
				hand_r_local = Vector3(0.20, 0.15, 0.15)   # on the crank handle
		"carried", "broken":
			var bob := absf(stride) * 0.03 * walk
			body.position = Vector3(0, BODY_Y + breath * 0.01 - bob, 0)
			body.rotation = Vector3(-0.05 - 0.05 * walk, stride * 0.06 * walk, 0.0)
			head.rotation = Vector3(sin(t * 1.3) * 0.03 + sin(t * 14.0) * 0.012 * walk, 0.0, 0.0)
			leg_l.rotation = Vector3(stride * 0.6 * walk, 0.0, 0.0)
			leg_r.rotation = Vector3(-stride * 0.6 * walk, 0.0, 0.0)
			prop.rotation = Vector3(-0.04, 0.0, 0.0)
			shield_xf = Transform3D(Basis(Vector3.UP, -0.10) * Basis(Vector3.RIGHT, 0.05), Vector3(-0.04, 0.12 - bob * 1.5, -SHIELD_Z + 0.06))
			bow_xf = _bow_carry_xf(stride * walk)
			hand_l = shield_xf * Vector3(0.0, H * 0.55, TH * 0.5 + 0.08)
		_:
			# "left" / "dropped": exposed, staggered back off its pavise, the bow held low in both hands
			body.position = Vector3(0, BODY_Y + breath * 0.01, 0)
			body.rotation = Vector3(0.10, 0.12, 0.04)
			head.rotation = Vector3(0.08 + sin(t * 1.3) * 0.03, 0.15, 0.0)
			leg_l.rotation = Vector3(0.22, 0.0, -0.10)
			leg_r.rotation = Vector3(-0.12, 0.0, 0.10)
			prop.rotation = Vector3(-0.50, 0.0, 0.0)
			if _state == "left" and _anchored and is_inside_tree():
				var world := Transform3D(Basis(Vector3.UP, _anchor_yaw) * Basis(Vector3.RIGHT, 0.06) * MODEL_SCALE, _anchor_pos)
				shield_xf = global_transform.affine_inverse() * world
			elif _state == "left":
				shield_xf = Transform3D(planted_xf.basis, planted_xf.origin + Vector3(0, 0, -LEFT_GAP))
			else:
				prop.rotation = Vector3(-0.04, 0.0, 0.0)
				shield_xf = Transform3D(Basis(Vector3.UP, PI + 0.35) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.30, TH * 0.5 + 0.075, -0.75))
			bow_xf = Transform3D(Basis(Vector3.UP, 0.45) * Basis(Vector3.RIGHT, -0.25), Vector3(0.10, 0.96, -0.30))
			hand_l = bow_xf * Vector3(0.0, -0.07, -0.26)
	if (bash > 0.0 or _swing > 0.0) and (_state == "carried" or _state == "planted"):
		# The bash: the pavise drawn back and tipped (the wind-up), then shoved out at the hero (the swing). The hand on its
		# grip and the body go with it.
		var tip := Basis(Vector3.RIGHT, -0.38 * bash + 0.22 * _swing)
		shield_xf = Transform3D(shield_xf.basis * tip, shield_xf.origin + Vector3(0.0, 0.05 * bash, 0.30 * bash - 0.42 * _swing))
		body.rotation.x += 0.16 * bash - 0.20 * _swing
		if _state == "carried":
			hand_l = shield_xf * Vector3(0.0, H * 0.55, TH * 0.5 + 0.08)
	(parts["shield"] as MeshInstance3D).transform = shield_xf
	(parts["shield_broken"] as MeshInstance3D).transform = shield_xf
	(parts["weapon"] as MeshInstance3D).transform = bow_xf
	var to_body := body.transform.affine_inverse()
	aim_limb(parts["arm_r"] as MeshInstance3D, to_body * (bow_xf * hand_r_local), ARM_LEN)
	aim_limb(parts["arm_l"] as MeshInstance3D, to_body * hand_l, ARM_LEN)
	_update_fx(w)


## Planted, aim w (0 = reloading, 1 = aiming). The side style lifts the bow nose-up outside the shield's edge, swings
## it level over the top and lowers it into the notch, so it never cuts through the boards.
func _bow_planted_xf(planted_xf: Transform3D, w: float, t: float) -> Transform3D:
	var reload := _bow_reload_xf(planted_xf, t)
	var aim := _bow_aim_xf(planted_xf)
	if carry != "side":
		return reload.interpolate_with(aim, w)
	var up := Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5 - 0.25), Vector3(0.70, 1.20, 0.10))
	var over := Transform3D(Basis.IDENTITY, aim.origin + Vector3(0.0, 0.35, 0.25))
	if w < 0.35:
		return reload.interpolate_with(up, w / 0.35)
	if w < 0.7:
		return up.interpolate_with(over, (w - 0.35) / 0.35)
	return over.interpolate_with(aim, (w - 0.7) / 0.3)


## Aiming: the stock in the sight notch, level, far enough forward that the prod clears the shield's face; the butt
## comes back to the cheek.
func _bow_aim_xf(planted_xf: Transform3D) -> Transform3D:
	var top := planted_xf * Vector3(0.0, H - NOTCH, 0.0)
	return Transform3D(Basis.IDENTITY, Vector3(SHIELD_X + 0.02, top.y + SADDLE + 0.055, top.z + 0.22))


## Reloading (planted, not aiming). side: nose down at the right hip outside the shield's edge, the foot in the
## stirrup, cranking. above: laid over the top rim in the notch, nose up, the butt drawn back to the chest.
func _bow_reload_xf(planted_xf: Transform3D, t: float) -> Transform3D:
	if carry == "side":
		var b := Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5 + 0.12)
		return Transform3D(b, Vector3(0.68, 0.78 + 0.01 * sin(t * 6.0), 0.10))
	var top := planted_xf * Vector3(0.0, H - NOTCH, 0.0)
	var tilt := 0.42
	var bb := Basis(Vector3.RIGHT, tilt)
	# the stock's underside at stock-local z_n rests on the back edge of the saddle; nose up, it clears the front
	var z_n := -0.10
	var rest := Vector3(SHIELD_X + 0.02, top.y + SADDLE + 0.01, top.z + TH * 0.5 + 0.05)   # the saddle's back edge
	return Transform3D(bb, rest - bb * Vector3(0.0, -0.05, z_n))


func _reload_left_grip() -> Vector3:
	return Vector3(0.0, 0.04, 0.10) if carry == "side" else Vector3(0.0, -0.07, -0.02)


## Carried. side: slung nose-down at the right hip, the prod along the body, outside the shield's edge, swinging a
## little. above: shouldered, the stock on the right shoulder, nose forward and up over the shield's top.
func _bow_carry_xf(swing: float) -> Transform3D:
	if carry == "side":
		var b := Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5 + 0.10 + 0.05 * swing)
		return Transform3D(b, Vector3(0.62, 0.80, 0.16))
	var ba := Basis(Vector3.UP, -0.10) * Basis(Vector3.RIGHT, 0.78 + 0.03 * swing)
	return Transform3D(ba, Vector3(0.30, 1.54, 0.04))


func _update_fx(w: float) -> void:
	if _flare == null:
		return
	var aiming := _state == "planted" and w > 0.04
	_flare.visible = _state != "broken"
	var k := w if aiming else 0.0
	var size := maxf((0.30 + 0.75 * k) * (1.35 if _locked and aiming else 1.0), 0.42)
	_flare.scale = Vector3.ONE * size * (0.75 + 0.25 * TIP_K)
	_flare_mat.set_shader_parameter("energy", (3.2 if _locked and aiming else 1.7) * (0.6 + 0.4 * maxf(k, 0.4)))


func _slump() -> void:
	(parts["body"] as MeshInstance3D).rotation = Vector3(-0.30, 0.0, 0.0)
	(parts["head"] as MeshInstance3D).rotation = Vector3(-0.45, 0.0, 0.0)
	(parts["jaw"] as MeshInstance3D).rotation.x = -0.55
	(parts["arm_l"] as MeshInstance3D).rotation = Vector3(0.1, 0.0, -0.45)
	(parts["arm_r"] as MeshInstance3D).rotation = Vector3(0.0, 0.0, 0.45)
	(parts["arm_l"] as MeshInstance3D).scale = Vector3.ONE
	(parts["arm_r"] as MeshInstance3D).scale = Vector3.ONE
	_flare.visible = false
