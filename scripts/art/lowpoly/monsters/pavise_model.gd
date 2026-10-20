class_name PaviseModel
extends MonsterModel
## Pavise Crossbowman look test (docs/design/combat-proposals.md §2, findings: docs/design/pavise-read-test.md).
## LAB ONLY: no Monster kind, not in MonsterModels, no net. scripts/art/lowpoly/monsters/pavise_lab.gd renders it.
##
## Four variants, each a different answer to "does a shielded sniper read from the fixed iso camera?":
##   "a" DOC      the doc's version: the grunt skeleton behind a door-sized pavise of dark planks, iron rim, red
##                chevrons, a sight notch and a foot spike; a heavy crossbow with a winding crank.
##   "b" HEAVY    the threat is the body: a big plate-armoured skeleton (helm with an ember slit, pauldrons) with a
##                steel arbalest, behind a lighter, chest-high mantlet of pale wood.
##   "c" PAINTED  colour and shape: the front is painted (crimson, a bone border and skull) and the back is raw pale
##                wood, so the colour says which side you see; a pointed-arch top; an oversize glowing bolt head.
##   "d" LAMP     a security skeleton behind a steel riot slab with a searchlight on it: the lamp lights the floor in
##                front (the shielded side is the lit side) and, while aiming, narrows to a red spot on its target.
##
## Shield states (set_shield): "carried" (walks behind it), "planted" (stamped in, aims through the notch), "left"
## (shoved off it: the pavise stands alone ahead of it), "dropped" (lying flat in front of it), "broken" (a stub of
## planks on the arm, splinters on the floor). windup(t) is the AIM (the bow comes up into the notch, the bolt head
## glows and flares); set_locked(true) is the last 0.4 s (hotter flare). set_stuck(n): n hero arrows in the front.
##
## Faces local -Z, +X is its right; origin at the feet. Rigid named parts (MeshInstance3D): body, head, jaw, gear,
## arm_l, arm_r, leg_l, leg_r (the grunt's skeleton), helm (b) or cap (d) under head, weapon (the crossbow, under the
## root), string and bolt (under weapon), shield (under the root), prop and arrows (under shield), lamp_warm / lamp_red
## (d, under shield), shield_broken and debris (under the root). Not parts: the bolt-head flare (an additive
## billboard) and, for d, a SpotLight3D and the floor light fan.

const VARIANTS: Array[String] = ["a", "b", "c", "d"]
const TITLES := {"a": "A doc pavise", "b": "B heavy", "c": "C painted", "d": "D lamp"}
const STATES: Array[String] = ["carried", "planted", "left", "dropped", "broken"]

# the skeleton (the grunt's paint)
const BONE := Color(0.90, 0.85, 0.72)
const BONE_LIGHT := Color(0.98, 0.95, 0.84)
const BONE_DARK := Color(0.64, 0.58, 0.46)
const CAVITY := Color(0.34, 0.28, 0.24)
const VOID := Color(0.09, 0.05, 0.05)
const EMBER := Color(1.0, 0.20, 0.06)
const UNIFORM := Color(0.20, 0.17, 0.18)
const UNIFORM_DARK := Color(0.12, 0.10, 0.12)
const BADGE := Color(0.95, 0.74, 0.22)
# wood, iron, paint
const PLANK_DARK := Color(0.25, 0.16, 0.11)
const PLANK_DARK2 := Color(0.20, 0.13, 0.09)
const PLANK_PALE := Color(0.70, 0.54, 0.34)
const PLANK_PALE2 := Color(0.60, 0.45, 0.28)
const IRON := Color(0.30, 0.31, 0.34)
const IRON_LIGHT := Color(0.50, 0.52, 0.56)
const RUST := Color(0.55, 0.30, 0.18)
const CHEVRON := Color(0.80, 0.13, 0.08)
const CRIMSON := Color(0.82, 0.10, 0.10)
const CRIMSON_DARK := Color(0.52, 0.06, 0.07)
const PAINT_BONE := Color(0.97, 0.93, 0.80)
const STEEL := Color(0.44, 0.47, 0.52)
const STEEL_DARK := Color(0.27, 0.29, 0.33)
const STEEL_LIGHT := Color(0.68, 0.72, 0.78)
const STOCK := Color(0.32, 0.20, 0.12)
const STOCK_LIGHT := Color(0.46, 0.30, 0.18)
const STRING_COL := Color(0.92, 0.88, 0.74)
const SHAFT := Color(0.84, 0.72, 0.48)                ## a hero arrow (Wick's paint)
const FLETCHES: Array[Color] = [Color(0.88, 0.26, 0.20), Color(0.25, 0.70, 0.68), Color(0.96, 0.82, 0.30)]
const BOLT_SHAFT := Color(0.22, 0.15, 0.11)
const BOLT_VANE := Color(0.72, 0.12, 0.08)
const TIP := Color(1.0, 0.30, 0.08)                   ## the bolt head: enemy glow
const TIP_HOT := Color(1.0, 0.72, 0.22)               ## c's bigger, hotter head
const LAMP_WARM := Color(1.0, 0.86, 0.56)
const LAMP_RED := Color(1.0, 0.16, 0.08)
const HAZARD_W := Color(0.93, 0.91, 0.85)

const BODY_Y := 0.80
const HIP_Y := 0.74
const SHOULDER := Vector3(0.36, 0.60, 0.0)
const ARM_LEN := 0.65
const LEG_X := 0.14
## Crossbow-local points (origin at the trigger grip, the bolt flies down -Z).
const REAR_GRIP := Vector3(0.0, -0.07, 0.03)
const FORE_GRIP := Vector3(0.0, -0.07, -0.26)
const NUT_Z := -0.16
const PROD_Z := -0.56
const LEFT_GAP := 1.5                                  ## "left": how far the pavise stands ahead of it

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

var variant := "a"
## d: how far (world units) its target stands, so the lamp's red spot lands on it while aiming.
var aim_distance := 10.0
var _state := "planted"
var _locked := false
var _stuck := 0
var _cue := ""                                          ## "", "glint" or "arc" (front cues to test)

# the variant's measurements (model space)
var _w := 0.90
var _h := 1.56
var _th := 0.08
var _planks := 5
var _top := "flat"
var _notch := 0.10
var _shield_z := 0.50
var _shield_x := 0.06
var _crouch := 0.08
var _bow_k := 1.0
var _tip_k := 1.0
var _armour := false

var _thin_mat: ShaderMaterial
var _flare: MeshInstance3D
var _flare_mat: ShaderMaterial
var _spot: SpotLight3D
var _fan: MeshInstance3D


func _init(variant_name: String = "a") -> void:
	variant = variant_name if VARIANTS.has(variant_name) else "a"
	_read_spec()
	var sc := 1.42 if variant == "b" else 1.20
	_setup_model("PaviseModel_" + variant, sc)
	monster_kind = "pavise"
	ui_height = (2.15 if variant == "b" else 1.9) * sc
	has_own_weapon = true
	glow_flare = 0.9
	_thin_mat = MonsterMaterial.make(1.1)
	_build()
	apply_idle(0.0)


func _read_spec() -> void:
	match variant:
		"b":
			_w = 0.74
			_h = 1.02
			_th = 0.07
			_planks = 4
			_notch = 0.0
			_shield_z = 0.56
			_shield_x = 0.0
			_crouch = 0.0
			_bow_k = 1.25
			_armour = true
		"c":
			_top = "arch"
			_h = 1.62
			_tip_k = 1.9
		"d":
			_top = "slab"
			_w = 0.94
			_h = 1.50


# ------------------------------------------------------------------ build

func _build() -> void:
	var body := _add_part("body", _body_soup(), self, Vector3(0, BODY_Y, 0))
	var head := _add_part("head", _head_soup(), body, Vector3(0, 0.86, -0.02))
	_add_part("jaw", _jaw_soup(), head, Vector3(0, -0.10, 0.05))
	_add_part("gear", _armour_soup() if _armour else _tabard_soup(), body, Vector3.ZERO)
	if _armour:
		_add_part("helm", _helm_soup(), head, Vector3.ZERO)
	elif variant == "d":
		_add_part("cap", _cap_soup(), head, Vector3.ZERO)
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		_add_part("arm_" + side, _arm_soup(s), body, Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z))
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(LEG_X * s, HIP_Y, 0.0))
	var bow := _add_part("weapon", _bow_soup(), self, Vector3(0.4, 1.0, 0.0))
	_add_part("string", _string_soup(), bow, Vector3.ZERO).material_override = _thin_mat
	var bolt := _add_part("bolt", _bolt_soup(), bow, Vector3(0.0, 0.075, NUT_Z))
	var shield := _add_part("shield", _shield_soup(), self, Vector3(0, 0, -_shield_z))
	_add_part("prop", _prop_soup(), shield, Vector3(0.0, _h * 0.66, _th * 0.5 + 0.05))
	var arrows := _add_part("arrows", LowPoly.Soup.new(1, 0.0), shield, Vector3.ZERO)
	arrows.material_override = _thin_mat
	arrows.visible = false
	if variant == "d":
		var lamp_at := Vector3(_w * 0.5 - 0.13, _h + 0.13, -0.02)
		_add_part("lamp_warm", _lens_soup(LAMP_WARM), shield, lamp_at)
		var red := _add_part("lamp_red", _lens_soup(LAMP_RED), shield, lamp_at)
		red.visible = false
		_spot = SpotLight3D.new()
		_spot.name = "Searchlight"
		_spot.light_color = LAMP_WARM
		_spot.light_energy = 6.0
		_spot.spot_range = 9.0
		_spot.spot_angle = 48.0
		_spot.spot_attenuation = 0.6
		_spot.shadow_enabled = false
		_spot.position = lamp_at + Vector3(0, 0, -0.16)
		_spot.rotation = Vector3(-0.42, 0.0, 0.0)
		shield.add_child(_spot)
	_fan = MeshInstance3D.new()
	_fan.name = "FrontFan"
	_fan.mesh = _fan_mesh(3.4, 70.0, Color(1.0, 0.80, 0.50, 0.30)) if variant == "d" else _arc_mesh(1.45, 1.70, 70.0, Color(1.0, 0.20, 0.08, 0.55))
	_fan.material_override = _additive_vertex_material()
	_fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fan.visible = false
	add_child(_fan)
	_add_part("glint", _glint_soup(), shield, Vector3.ZERO).visible = false
	_add_part("shield_broken", _broken_soup(), self, Vector3.ZERO).visible = false
	_add_part("debris", _debris_soup(), self, Vector3.ZERO).visible = false
	_flare_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FLARE_SHADER
	_flare_mat.shader = sh
	_flare_mat.set_shader_parameter("color", TIP_HOT if variant == "c" else TIP)
	_flare = MeshInstance3D.new()
	_flare.name = "TipFlare"
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_flare.mesh = q
	_flare.material_override = _flare_mat
	_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flare.position = Vector3(0.0, 0.0, -0.66 - 0.06 * _tip_k)
	_flare.visible = false
	bolt.add_child(_flare)


# ------------------------------------------------------------------ the skeleton (the grunt's, with variant dress)

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


## The grunt's security tabard; c wears its shield's crimson.
func _tabard_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(651, 0.07)
	var cloth := CRIMSON_DARK if variant == "c" else UNIFORM
	var cloth_dk := Color(0.36, 0.05, 0.06) if variant == "c" else UNIFORM_DARK
	slab(s, Vector3(0, 0.15, 0.0), Vector3(0.54, 0.09, 0.36), cloth_dk, 652, Vector3.ZERO, 0.01)          # belt
	slab(s, Vector3(0, 0.26, -0.185), Vector3(0.34, 0.20, 0.05), cloth, 653, Vector3(4, 0, 0), 0.012)     # front flap
	slab(s, Vector3(0, 0.25, 0.18), Vector3(0.38, 0.22, 0.05), cloth_dk, 654, Vector3(-3, 0, 0), 0.012)   # back flap
	slab(s, Vector3(0.0, 0.46, -0.20), Vector3(0.10, 0.50, 0.04), cloth, 655, Vector3(0, 0, -38), 0.01)   # sash
	slab(s, Vector3(-0.07, 0.50, -0.225), Vector3(0.10, 0.12, 0.03), BADGE, 656, Vector3(0, 0, -38), 0.0, 0.03)
	slab(s, Vector3(0.38, 0.69, 0.0), Vector3(0.24, 0.06, 0.22), cloth, 657, Vector3(0, 0, -10), 0.01)   # epaulette
	slab(s, Vector3(0, 0.15, -0.185), Vector3(0.10, 0.08, 0.03), BADGE, 658, Vector3.ZERO, 0.0, 0.03)     # buckle
	# a bolt quiver on the right hip
	limb(s, Vector3(0.30, -0.05, 0.10), Vector3(0.34, 0.30, 0.16), 0.07, 0.08, 5, STOCK, 659, 0.01)
	for i in 3:
		limb(s, Vector3(0.30 + 0.035 * i, 0.28, 0.15), Vector3(0.31 + 0.04 * i, 0.42, 0.17), 0.016, 0.016, 4, BOLT_SHAFT, 660 + i)
		limb(s, Vector3(0.31 + 0.04 * i, 0.38, 0.17), Vector3(0.315 + 0.04 * i, 0.46, 0.175), 0.04, 0.012, 3, BOLT_VANE, 664 + i)
	return s


## b: plate over the ribs, big pauldrons, a gorget, a fauld skirt and a red tabard strip.
func _armour_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(671, 0.06)
	s.merge(LowPoly.frustum(Vector2(0.60, 0.40), Vector2(0.74, 0.44), 0.50, STEEL_DARK, 672, 0.02, 1), LowPoly.at(Vector3(0, 0.40, -0.01)))  # cuirass
	slab(s, Vector3(0, 0.46, -0.235), Vector3(0.12, 0.40, 0.03), STEEL_LIGHT, 673, Vector3(-6, 0, 0), 0.0, 0.03)   # ridge
	s.merge(LowPoly.frustum(Vector2(0.66, 0.44), Vector2(0.58, 0.40), 0.24, STEEL, 674, 0.02, 1), LowPoly.at(Vector3(0, 0.04, 0)))      # fauld
	for x: int in [-1, 1]:
		blob(s, Vector3(0.40 * x, 0.68, 0.0), Vector3(0.24, 0.15, 0.24), STEEL, 675 + x, 0.12, 0)       # pauldron
		blob(s, Vector3(0.44 * x, 0.58, 0.0), Vector3(0.21, 0.10, 0.21), STEEL_DARK, 678 + x, 0.12, 0)  # lame under it
		limb(s, Vector3(0.40 * x, 0.80, 0.02), Vector3(0.42 * x, 0.95, 0.06), 0.06, 0.0, 4, STEEL_LIGHT, 681 + x)   # spike
	s.merge(LowPoly.cylinder(0.15, 0.12, 0.12, 7, STEEL_LIGHT, 684, 0.01), LowPoly.at(Vector3(0, 0.70, -0.01)))   # gorget
	slab(s, Vector3(0, 0.02, -0.245), Vector3(0.22, 0.44, 0.03), CRIMSON_DARK, 685, Vector3(-4, 0, 0), 0.01)       # tabard strip
	slab(s, Vector3(0, 0.20, -0.225), Vector3(0.62, 0.07, 0.42), STOCK, 686, Vector3.ZERO, 0.01)                   # belt
	slab(s, Vector3(0, 0.20, -0.45 * 0.5 - 0.02), Vector3(0.10, 0.09, 0.03), BADGE, 687, Vector3.ZERO, 0.0, 0.03)  # buckle
	return s


## b's great helm: a bucket over the skull, one glowing ember slit, a nose bar, a crest.
func _helm_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(691, 0.05)
	s.merge(LowPoly.cylinder(0.25, 0.27, 0.42, 8, STEEL_DARK, 692, 0.012), LowPoly.at(Vector3(0, 0.02, 0.0)))
	s.merge(LowPoly.cylinder(0.27, 0.20, 0.08, 8, STEEL, 693, 0.01), LowPoly.at(Vector3(0, 0.27, 0.0)))   # crown
	slab(s, Vector3(0, 0.04, -0.255), Vector3(0.34, 0.06, 0.05), VOID, 694)                               # slit
	slab(s, Vector3(0, 0.04, -0.272), Vector3(0.28, 0.035, 0.03), glow(EMBER), 695, Vector3.ZERO, 0.0, 0.0)
	slab(s, Vector3(0, -0.07, -0.27), Vector3(0.06, 0.20, 0.04), STEEL_LIGHT, 696)                        # nose bar
	s.merge(LowPoly.frustum(Vector2(0.05, 0.34), Vector2(0.03, 0.18), 0.12, CRIMSON, 697, 0.006, 1, Vector2(0, 0.06)), LowPoly.at(Vector3(0, 0.36, 0.03)))  # crest
	return s


## d: a peaked security cap.
func _cap_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(701, 0.05)
	s.merge(LowPoly.cylinder(0.25, 0.27, 0.12, 8, UNIFORM, 702, 0.01), LowPoly.at(Vector3(0, 0.15, 0.0)))
	s.merge(LowPoly.cylinder(0.24, 0.25, 0.05, 8, UNIFORM_DARK, 703, 0.0), LowPoly.at(Vector3(0, 0.115, 0.0)))
	slab(s, Vector3(0, 0.10, -0.25), Vector3(0.36, 0.03, 0.16), UNIFORM_DARK, 704, Vector3(-12, 0, 0))   # peak
	slab(s, Vector3(0, 0.17, -0.27), Vector3(0.09, 0.08, 0.02), BADGE, 705, Vector3.ZERO, 0.0, 0.03)     # badge
	return s


func _arm_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(711 + side, 0.07)
	limb(s, Vector3(0, -0.02, 0), Vector3(0, -0.30, -0.02), 0.062, 0.054, 5, BONE, 712 + side)
	blob(s, Vector3(0, -0.31, -0.02), Vector3(0.07, 0.07, 0.07), BONE_LIGHT, 714 + side, 0.15)
	limb(s, Vector3(0, -0.32, -0.02), Vector3(0, -0.60, -0.04), 0.054, 0.046, 5, BONE, 716 + side)
	blob(s, Vector3(0, -0.64, -0.04), Vector3(0.08, 0.085, 0.08), BONE_LIGHT, 718 + side, 0.15)
	if _armour:
		limb(s, Vector3(0, -0.36, -0.02), Vector3(0, -0.56, -0.04), 0.09, 0.10, 6, STEEL, 720 + side, 0.01)   # vambrace
		blob(s, Vector3(0, -0.66, -0.04), Vector3(0.11, 0.10, 0.11), STEEL_DARK, 722 + side, 0.12)              # gauntlet
	return s


func _leg_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(731 + side, 0.07)
	limb(s, Vector3(0, -0.02, 0), Vector3(0, -0.38, -0.03), 0.085, 0.07, 5, BONE, 732 + side)
	blob(s, Vector3(0, -0.39, -0.04), Vector3(0.085, 0.085, 0.085), BONE_LIGHT, 734 + side, 0.15)
	limb(s, Vector3(0, -0.40, -0.04), Vector3(0, -0.68, 0.0), 0.07, 0.058, 5, BONE, 736 + side)
	if not _armour:
		blob(s, Vector3(0, -0.70, -0.08), Vector3(0.10, 0.055, 0.17), BONE_DARK, 738 + side, 0.12)
	else:
		limb(s, Vector3(0, -0.44, -0.04), Vector3(0, -0.66, -0.01), 0.10, 0.09, 6, STEEL_DARK, 740 + side, 0.01)   # greave
		blob(s, Vector3(0, -0.40, -0.06), Vector3(0.11, 0.10, 0.10), STEEL, 742 + side, 0.12)                       # knee cop
		blob(s, Vector3(0, -0.71, -0.08), Vector3(0.12, 0.06, 0.19), STEEL_DARK, 744 + side, 0.1)                   # sabaton
	return s


# ------------------------------------------------------------------ the crossbow

## A heavy crossbow (b: a steel arbalest, bigger). Origin at the trigger grip; the bolt flies down -Z.
func _bow_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(751, 0.06)
	var k := _bow_k
	var prod_col := STEEL if variant == "b" else STEEL_DARK
	slab(s, Vector3(0, 0.0, -0.18 * k), Vector3(0.09, 0.10, 0.80 * k), STOCK, 752, Vector3.ZERO, 0.01)            # stock
	slab(s, Vector3(0, -0.03, 0.24 * k), Vector3(0.12, 0.17, 0.06), STOCK_LIGHT, 753, Vector3(8, 0, 0), 0.01)       # butt plate
	slab(s, Vector3(0, 0.058, NUT_Z), Vector3(0.11, 0.04, 0.08), IRON, 754, Vector3.ZERO, 0.0)                       # the nut
	limb(s, Vector3(0, -0.05, -0.02), Vector3(0, -0.13, 0.07), 0.018, 0.012, 4, IRON, 755)                          # trigger
	# the prod: a thick, swept steel bow across the front
	var half := 0.44 * k
	for sgn: float in [-1.0, 1.0]:
		var mid := Vector3(sgn * half * 0.5, 0.04, PROD_Z * k + 0.05 * k)
		limb(s, Vector3(0, 0.04, PROD_Z * k), mid, 0.045 * k, 0.036 * k, 5, prod_col, 756 + int(sgn), 0.005)
		limb(s, mid, Vector3(sgn * half, 0.04, PROD_Z * k + 0.16 * k), 0.036 * k, 0.024 * k, 5, prod_col, 758 + int(sgn), 0.005)
		blob(s, Vector3(sgn * half, 0.04, PROD_Z * k + 0.16 * k), Vector3(0.035, 0.035, 0.035) * k, IRON_LIGHT, 760 + int(sgn), 0.1)
	slab(s, Vector3(0, 0.04, PROD_Z * k), Vector3(0.14, 0.12, 0.10), IRON, 762, Vector3.ZERO, 0.01)                  # bow block
	# the stirrup at the nose
	limb(s, Vector3(-0.07, 0.0, -0.62 * k), Vector3(-0.08, -0.04, -0.74 * k), 0.018, 0.018, 4, IRON, 763)
	limb(s, Vector3(0.07, 0.0, -0.62 * k), Vector3(0.08, -0.04, -0.74 * k), 0.018, 0.018, 4, IRON, 764)
	limb(s, Vector3(-0.08, -0.04, -0.74 * k), Vector3(0.08, -0.04, -0.74 * k), 0.018, 0.018, 4, IRON, 765)
	# the winding crank at the butt (a windlass drum and a handle)
	s.merge(LowPoly.cylinder(0.05, 0.05, 0.22, 6, IRON, 766, 0.0), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0.02, 0.15 * k)))
	limb(s, Vector3(0.11, 0.02, 0.15 * k), Vector3(0.13, 0.15, 0.15 * k), 0.02, 0.02, 4, IRON_LIGHT, 767)
	limb(s, Vector3(0.13, 0.15, 0.15 * k), Vector3(0.20, 0.15, 0.15 * k), 0.025, 0.025, 4, STOCK_LIGHT, 768)
	return s


## The drawn string, from the prod tips back to the nut.
func _string_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(771, 0.0)
	var k := _bow_k
	var nut := Vector3(0, 0.07, NUT_Z + 0.03)
	for sgn: float in [-1.0, 1.0]:
		limb(s, Vector3(sgn * 0.44 * k, 0.04, PROD_Z * k + 0.16 * k), nut, 0.013, 0.013, 4, STRING_COL, 772 + int(sgn), 0.0, 0.0)
	return s


## The loaded bolt, origin at the nut, flying down -Z, with a glowing head (c: oversize and hotter).
func _bolt_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(781, 0.04)
	var k := _tip_k
	var nose := -0.52 * _bow_k - 0.06
	limb(s, Vector3(0, 0, 0.02), Vector3(0, 0, nose), 0.022, 0.022, 4, BOLT_SHAFT, 782, 0.0, 0.0)
	for i in 2:
		var rz := 90.0 * i
		slab(s, Vector3(0, 0, -0.05), Vector3(0.10, 0.012, 0.12), BOLT_VANE, 783 + i, Vector3(0, 0, rz + 45.0), 0.0, 0.03)
	var col := glow(TIP_HOT if variant == "c" else TIP)
	limb(s, Vector3(0, 0, nose), Vector3(0, 0, nose - 0.17 * k), 0.06 * k, 0.0, 4, col, 786, 0.0, 0.0)                    # head
	limb(s, Vector3(0, 0, nose + 0.035), Vector3(0, 0, nose), 0.035 * k, 0.06 * k, 4, col, 787, 0.0, 0.0)                 # socket
	return s


# ------------------------------------------------------------------ the shield

## Plank top height at plank i (the notch at the centre; c's pointed arch).
func _plank_h(i: int) -> float:
	var n := _planks
	var x := -_w * 0.5 + _w / n * (i + 0.5)
	var h := _h
	if _top == "arch":
		var u := x / (_w * 0.5)
		h = 1.30 + (_h - 1.30) * (1.0 - u * u)
	if _notch > 0.0 and n % 2 == 1 and i == n / 2:
		h = _h - _notch
	return h


## Origin at the bottom centre of the boards (the foot spike below it), the front faces -Z.
func _shield_soup() -> LowPoly.Soup:
	if _top == "slab":
		return _slab_soup()
	var s := LowPoly.Soup.new(801, 0.06)
	var n := _planks
	var pw := _w / n
	var t := _th
	var wood := PLANK_DARK
	var wood2 := PLANK_DARK2
	if variant == "b" or variant == "c":
		wood = PLANK_PALE
		wood2 = PLANK_PALE2
	for i in n:
		var x := -_w * 0.5 + pw * (i + 0.5)
		var ph := _plank_h(i)
		var tz := t + (0.008 if i % 2 == 0 else -0.008)    # alternate depths: no two neighbours flush
		slab(s, Vector3(x, ph * 0.5, 0.0), Vector3(pw, ph, tz), wood if i % 2 == 0 else wood2, 802 + i, Vector3.ZERO, 0.004)
	var f := t * 0.5 + 0.004                              # the front of the thicker planks
	limb(s, Vector3(0, 0.03, 0), Vector3(0, -0.22, 0), 0.06, 0.0, 5, IRON, 810)            # the foot spike
	match variant:
		"c":
			_painted_front(s, f)
		_:
			_iron_rim(s, f)
	# the back: two crossed braces and a grip
	var bz := t * 0.5 + 0.004
	slab(s, Vector3(0, _h * 0.45, bz + 0.025), Vector3(0.06, _h * 1.02, 0.04), wood2, 830, Vector3(0, 0, 24), 0.004)
	slab(s, Vector3(0, _h * 0.45, bz + 0.032), Vector3(0.06, _h * 1.02, 0.04), wood2, 831, Vector3(0, 0, -24), 0.004)
	slab(s, Vector3(0, _h * 0.55, bz + 0.07), Vector3(0.22, 0.05, 0.05), STOCK_LIGHT, 832)
	for x: float in [-0.10, 0.10]:
		slab(s, Vector3(x, _h * 0.55, bz + 0.035), Vector3(0.04, 0.07, 0.07), STOCK, 833 + int(x * 10.0))
	return s


## a and b: an iron rim (proud of the boards), two bands with studs, and the painted mark.
func _iron_rim(s: LowPoly.Soup, f: float) -> void:
	var t := _th
	var pw := _w / _planks
	for sx: float in [-1.0, 1.0]:
		slab(s, Vector3(sx * _w * 0.5, _h * 0.5, 0.0), Vector3(0.06, _h + 0.04, t + 0.03), IRON, 811 + int(sx))    # sides
	slab(s, Vector3(0, 0.02, 0.0), Vector3(_w + 0.10, 0.07, t + 0.04), IRON, 814)                                 # bottom
	if _notch > 0.0:
		var seg := (_w - pw) * 0.5
		for sx: float in [-1.0, 1.0]:
			slab(s, Vector3(sx * (pw * 0.5 + (seg + 0.05) * 0.5), _h, 0.0), Vector3(seg + 0.05, 0.06, t + 0.04), IRON, 815 + int(sx))
		slab(s, Vector3(0, _h - _notch, 0.0), Vector3(pw + 0.02, 0.05, t + 0.046), IRON_LIGHT, 818)                # the notch's saddle
	else:
		slab(s, Vector3(0, _h, 0.0), Vector3(_w + 0.10, 0.06, t + 0.04), IRON, 815)
	var band_y: Array[float] = [_h * 0.16, _h * 0.86]
	if variant != "a":
		band_y = [_h * 0.20, _h * 0.52, _h * 0.84]
	for i in band_y.size():
		slab(s, Vector3(0, band_y[i], 0.0), Vector3(_w, 0.05, t + 0.022), IRON, 819 + i)
		for j in _planks:
			var x := -_w * 0.5 + pw * (j + 0.5)
			blob(s, Vector3(x, band_y[i], -(f + 0.012)), Vector3(0.022, 0.022, 0.012), IRON_LIGHT, 823 + i * 7 + j, 0.0)
	if variant == "a":
		# three red chevrons pointing up (each arm a few mm off the other: they overlap at the apex)
		for c in 3:
			var yc := _h * (0.30 + 0.19 * c)
			for sx: float in [-1.0, 1.0]:
				var z := -(f + 0.022 + (0.0 if sx < 0.0 else 0.004))
				slab(s, Vector3(sx * 0.15, yc, z), Vector3(0.40, 0.10, 0.012), CHEVRON, 840 + c * 2 + int(sx > 0.0), Vector3(0, 0, -sx * 34.0), 0.0, 0.05)
	else:
		# b: one broad red chevron
		for sx: float in [-1.0, 1.0]:
			var z := -(f + 0.022 + (0.0 if sx < 0.0 else 0.004))
			slab(s, Vector3(sx * 0.15, _h * 0.66, z), Vector3(0.38, 0.12, 0.012), CHEVRON, 850 + int(sx > 0.0), Vector3(0, 0, -sx * 36.0), 0.0, 0.05)


## c: crimson paint over the planks' fronts, a bone border, a painted skull and a central ridge.
func _painted_front(s: LowPoly.Soup, f: float) -> void:
	var n := _planks
	var pw := _w / n
	for i in n:
		var x := -_w * 0.5 + pw * (i + 0.5)
		var ph := _plank_h(i)
		slab(s, Vector3(x, ph * 0.5, -(f + 0.008)), Vector3(pw, ph - 0.01, 0.01), CRIMSON if i % 2 == 0 else Color(0.74, 0.08, 0.09), 860 + i, Vector3.ZERO, 0.0, 0.03)
		slab(s, Vector3(x, ph - 0.045, -(f + 0.019 + 0.003 * (i % 2))), Vector3(pw, 0.07, 0.012), PAINT_BONE, 866 + i, Vector3.ZERO, 0.0, 0.03)   # top border
	for sx: float in [-1.0, 1.0]:
		var ph := _plank_h(0)
		slab(s, Vector3(sx * (_w * 0.5 - 0.035), (ph - 0.08) * 0.5, -(f + 0.026)), Vector3(0.07, ph - 0.08, 0.012), PAINT_BONE, 872 + int(sx > 0.0), Vector3.ZERO, 0.0, 0.03)
	slab(s, Vector3(0, 0.05, -(f + 0.030)), Vector3(_w - 0.02, 0.08, 0.012), PAINT_BONE, 875, Vector3.ZERO, 0.0, 0.03)   # bottom border
	# the skull: a pale dome, black sockets, a jaw
	var sy := _h * 0.62
	s.merge(LowPoly.boulder(Vector3(0.20, 0.17, 0.03), 0, 0.0, PAINT_BONE, 876, 0.03), LowPoly.at(Vector3(0, sy, -(f + 0.040))))
	slab(s, Vector3(0, sy - 0.17, -(f + 0.034)), Vector3(0.20, 0.08, 0.012), PAINT_BONE, 877, Vector3.ZERO, 0.0, 0.03)
	for sx: float in [-1.0, 1.0]:
		slab(s, Vector3(sx * 0.075, sy - 0.01, -(f + 0.068)), Vector3(0.09, 0.08, 0.012), Color(0.10, 0.04, 0.04), 878 + int(sx > 0.0), Vector3(0, 0, sx * 14.0), 0.0, 0.0)
	wedge(s, Vector3(0, sy - 0.09, -(f + 0.066)), Vector2(0.05, 0.012), Vector2(0.015, 0.012), 0.06, Color(0.10, 0.04, 0.04), 880, Vector3.ZERO, 0.0, 0.0)
	# the ridge below the skull
	slab(s, Vector3(0, _h * 0.26, -(f + 0.030)), Vector3(0.08, _h * 0.36, 0.05), CRIMSON_DARK, 881, Vector3.ZERO, 0.004)


## d: a steel riot slab with a notch, a frame, a dark viewing slot, rivets and a red-and-white base band.
func _slab_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(901, 0.05)
	var t := _th
	var nw := 0.18
	var body_h := _h - _notch
	slab(s, Vector3(0, body_h * 0.5, 0.0), Vector3(_w, body_h, t), STEEL_DARK, 902)
	var ear := (_w - nw) * 0.5
	for sx: float in [-1.0, 1.0]:
		slab(s, Vector3(sx * (nw * 0.5 + ear * 0.5), body_h + _notch * 0.5, 0.0), Vector3(ear, _notch, t), STEEL_DARK, 903 + int(sx > 0.0))
	limb(s, Vector3(0, 0.03, 0), Vector3(0, -0.22, 0), 0.06, 0.0, 5, IRON, 905)
	var f := t * 0.5
	# a raised frame round the front
	for sx: float in [-1.0, 1.0]:
		slab(s, Vector3(sx * (_w * 0.5 - 0.03), _h * 0.5, -(f + 0.010)), Vector3(0.06, _h + 0.02, 0.02), STEEL, 906 + int(sx > 0.0))
	slab(s, Vector3(0, 0.03, -(f + 0.014)), Vector3(_w - 0.04, 0.06, 0.02), STEEL, 908)
	for sx: float in [-1.0, 1.0]:
		slab(s, Vector3(sx * (nw * 0.5 + (ear - 0.03) * 0.5), _h - 0.03, -(f + 0.014)), Vector3(ear - 0.03, 0.06, 0.02), STEEL, 909 + int(sx > 0.0))
	slab(s, Vector3(0, _h * 0.80, -(f + 0.012)), Vector3(_w * 0.62, 0.08, 0.02), Color(0.06, 0.05, 0.06), 911)   # viewing slot
	for i in 6:
		var bx := -_w * 0.5 + 0.06 + (_w - 0.12) / 6.0 * (i + 0.5)
		slab(s, Vector3(bx, 0.20, -(f + 0.012)), Vector3((_w - 0.12) / 6.0, 0.20, 0.016), CRIMSON if i % 2 == 0 else HAZARD_W, 912 + i, Vector3.ZERO, 0.0, 0.03)
	for i in 4:
		for sx: float in [-1.0, 1.0]:
			blob(s, Vector3(sx * (_w * 0.5 - 0.03), 0.30 + i * 0.34, -(f + 0.026)), Vector3(0.022, 0.022, 0.01), STEEL_LIGHT, 920 + i * 2 + int(sx > 0.0), 0.0)
	# the lamp's housing and bracket (the lens is its own part: it turns red)
	var lamp := Vector3(_w * 0.5 - 0.13, _h + 0.13, -0.02)
	s.merge(LowPoly.cylinder(0.11, 0.12, 0.22, 8, STEEL, 930, 0.0), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), lamp + Vector3(0, 0, 0.06)))
	slab(s, Vector3(lamp.x, _h + 0.01, -0.02), Vector3(0.06, 0.06, 0.06), IRON, 931)
	# the back: two upright struts and a grip
	slab(s, Vector3(-0.22, _h * 0.48, f + 0.025), Vector3(0.06, _h * 0.9, 0.05), IRON, 932)
	slab(s, Vector3(0.22, _h * 0.48, f + 0.031), Vector3(0.06, _h * 0.9, 0.05), IRON, 933)
	slab(s, Vector3(0, _h * 0.55, f + 0.075), Vector3(0.58, 0.05, 0.05), STOCK_LIGHT, 934)
	return s


## d: the lamp lens (lit warm, or red while aiming), facing -Z.
func _lens_soup(col: Color) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(941, 0.0)
	s.merge(LowPoly.cylinder(0.095, 0.095, 0.03, 8, glow(col), 942, 0.0, 1, 0.0), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.055)))
	return s


## The prop leg on the back: hangs from its hinge; planted it swings out to the floor behind.
func _prop_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(951, 0.06)
	var pl := _h * 0.74
	limb(s, Vector3(0, 0.02, 0), Vector3(0, -pl, 0), 0.035, 0.03, 5, STOCK, 952)
	limb(s, Vector3(0, -pl, 0), Vector3(0, -pl - 0.07, 0), 0.03, 0.0, 4, IRON, 953)
	s.merge(LowPoly.cylinder(0.045, 0.045, 0.10, 6, IRON, 954, 0.0), Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO))
	return s


## A stub of the shield (the outer planks, splintered) for "broken"; same origin as the shield.
func _broken_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(961, 0.06)
	var pw := _w / _planks
	var wood := PLANK_DARK if variant == "a" else PLANK_PALE
	var face := CRIMSON if variant == "c" else wood
	if variant == "d":
		wood = STEEL_DARK
		face = STEEL_DARK
	var hs: Array[float] = [_h * 0.78, _h * 0.52]
	for i in 2:
		var x := -_w * 0.5 + pw * (i + 0.5)
		var tz := _th + (0.008 if i % 2 == 0 else -0.008)
		slab(s, Vector3(x, hs[i] * 0.5, 0.0), Vector3(pw, hs[i], tz), wood, 962 + i, Vector3.ZERO, 0.004)
		if face != wood:
			slab(s, Vector3(x, hs[i] * 0.5, -(_th * 0.5 + 0.012)), Vector3(pw, hs[i] - 0.02, 0.01), face, 964 + i, Vector3.ZERO, 0.0, 0.03)
		for k in 2:   # jagged splinters off the broken top
			var sx := x - pw * 0.25 + pw * 0.5 * k
			limb(s, Vector3(sx, hs[i] - 0.02, 0.0), Vector3(sx + 0.03 * (k * 2 - 1), hs[i] + 0.12 + 0.06 * k, 0.0), 0.04, 0.0, 3, wood, 966 + i * 2 + k)
	slab(s, Vector3(-_w * 0.5, _h * 0.40, 0.0), Vector3(0.06, _h * 0.80, _th + 0.03), IRON, 970)
	slab(s, Vector3(-_w * 0.5 + pw, 0.02, 0.0), Vector3(pw * 2.0 + 0.08, 0.07, _th + 0.04), IRON, 971)
	slab(s, Vector3(-_w * 0.5 + pw, _h * 0.40, _th * 0.5 + 0.03), Vector3(pw * 2.0, 0.06, 0.04), PLANK_DARK2, 972)
	return s


## Splinters and boards on the floor (root space, in front of it) for "broken".
func _debris_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(981, 0.06)
	var pw := _w / _planks
	var wood := PLANK_DARK if variant == "a" else PLANK_PALE
	if variant == "d":
		wood = STEEL_DARK
	var bits: Array[Vector4] = [Vector4(0.25, -1.05, 0.9, 20.0), Vector4(-0.35, -1.30, 0.6, -35.0), Vector4(0.55, -0.70, 0.45, 70.0), Vector4(-0.05, -1.60, 0.35, 5.0)]
	for i in bits.size():
		var b := bits[i]
		slab(s, Vector3(b.x, _th * 0.5 + 0.003 * i, b.y), Vector3(pw, _th, b.z), wood, 982 + i, Vector3(0, b.w, 0), 0.01)
	if variant == "c":
		slab(s, Vector3(0.25, _th + 0.009, -1.05), Vector3(pw - 0.02, 0.01, 0.86), CRIMSON, 988, Vector3(0, 20.0, 0), 0.0, 0.03)
	for i in 5:
		var a := 0.9 * i
		limb(s, Vector3(0.6 * cos(a) * 0.5, 0.02, -0.9 + 0.4 * sin(a)), Vector3(0.6 * cos(a) * 0.5 + 0.18, 0.02, -0.9 + 0.4 * sin(a) + 0.08), 0.025, 0.0, 3, wood, 990 + i)
	return s


## Hero arrows stuck in the front, n of them (seeded: the same arrows every time).
func _arrows_soup(n: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1001, 0.04)
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var f := _th * 0.5 + (0.02 if _top == "slab" else 0.004)
	for i in n:
		var p := Vector3(r.randf_range(-0.36, 0.36) * _w, r.randf_range(0.22, 0.80) * _h, -f + 0.04)
		var d := Vector3(r.randf_range(-0.30, 0.30), r.randf_range(-0.05, 0.35), -1.0).normalized()
		var tail := p + d * 0.62
		limb(s, p, tail - d * 0.05, 0.018, 0.018, 4, SHAFT, 1002 + i * 3, 0.0, 0.0)
		limb(s, tail - d * 0.16, tail, 0.055, 0.02, 3, FLETCHES[i % FLETCHES.size()], 1003 + i * 3, 0.0, 0.03)
		limb(s, p - d * 0.02, p + d * 0.05, 0.038, 0.028, 5, BOLT_SHAFT, 1004 + i * 3, 0.0, 0.0)   # a splintered ring round the hole
	return s


## A front-edge glint (a fix to test): ember-lit strips along the front's top and sides, so the shielded face shows a
## glowing outline from any angle that sees it, and the back never does.
func _glint_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1101, 0.0)
	var f := _th * 0.5 + 0.004 + (0.05 if variant == "c" else 0.032)
	if _top == "slab":
		f = _th * 0.5 + 0.03
	var g := glow(Color(0.95, 0.30, 0.08))
	var n := _planks
	var pw := _w / n
	for i in n:
		var x := -_w * 0.5 + pw * (i + 0.5)
		var ph := _plank_h(i) if _top != "slab" else (_h if i != n / 2 else _h - _notch)
		slab(s, Vector3(x, ph - 0.012, -f - 0.003 * (i % 2)), Vector3(pw, 0.03, 0.01), g, 1102 + i, Vector3.ZERO, 0.0, 0.0)
	var side_h := _plank_h(0) if _top != "slab" else _h
	for sx: float in [-1.0, 1.0]:
		slab(s, Vector3(sx * (_w * 0.5 - 0.012), side_h * 0.5, -f - 0.008), Vector3(0.03, side_h - 0.04, 0.01), g, 1110 + int(sx > 0.0), Vector3.ZERO, 0.0, 0.0)
	return s


# ------------------------------------------------------------------ the floor fan (d's light; a front-arc cue to test)

## A flat fan on the floor in front (-Z), `deg` wide, fading out to `radius`: the lit, shielded side.
static func _fan_mesh(radius: float, deg: float, inner: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := deg_to_rad(deg)
	var segs := 24
	var outer := Color(inner.r, inner.g * 0.9, inner.b * 0.8, 0.0)
	for i in segs:
		var a0 := -half + 2.0 * half * float(i) / segs
		var a1 := -half + 2.0 * half * float(i + 1) / segs
		st.set_color(inner)
		st.add_vertex(Vector3(0, 0, -0.1))
		st.set_color(outer)
		st.add_vertex(Vector3(sin(a1) * radius, 0, -cos(a1) * radius))
		st.set_color(outer)
		st.add_vertex(Vector3(sin(a0) * radius, 0, -cos(a0) * radius))
	return st.commit()


## The front-arc cue: a thin band on the floor round the front, `deg` either side of -Z (the shield's +-70 degrees),
## brightest at its outer edge, with a faint fill inside.
static func _arc_mesh(r0: float, r1: float, deg: float, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := deg_to_rad(deg)
	var segs := 28
	var fill := Color(col.r, col.g, col.b, col.a * 0.18)
	var clear := Color(col.r, col.g, col.b, 0.0)
	for i in segs:
		var a0 := -half + 2.0 * half * float(i) / segs
		var a1 := -half + 2.0 * half * float(i + 1) / segs
		var d0 := Vector3(sin(a0), 0, -cos(a0))
		var d1 := Vector3(sin(a1), 0, -cos(a1))
		# the band
		for tri: Array in [[d0 * r0, d1 * r0, d1 * r1, col * Color(1, 1, 1, 0.5), col * Color(1, 1, 1, 0.5), col],
				[d0 * r0, d1 * r1, d0 * r1, col * Color(1, 1, 1, 0.5), col, col]]:
			for k in 3:
				st.set_color(tri[3 + k])
				st.add_vertex(tri[k])
		# the faint fill, fading toward the body
		for tri: Array in [[d0 * 0.45, d1 * 0.45, d1 * r0, clear, clear, fill], [d0 * 0.45, d1 * r0, d0 * r0, clear, fill, fill]]:
			for k in 3:
				st.set_color(tri[3 + k])
				st.add_vertex(tri[k])
	return st.commit()


static func _additive_vertex_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color.WHITE
	return m


# ------------------------------------------------------------------ hooks

## "carried", "planted", "left", "dropped" or "broken".
func set_shield(state: String) -> void:
	_state = state if STATES.has(state) else "planted"
	var broken := _state == "broken"
	(parts["shield"] as MeshInstance3D).visible = not broken
	(parts["shield_broken"] as MeshInstance3D).visible = broken
	(parts["debris"] as MeshInstance3D).visible = broken
	(parts["glint"] as MeshInstance3D).visible = _cue == "glint" and not broken
	_refresh()


func shield_state() -> String:
	return _state


## The last 0.4 s of the aim: the flare runs hot.
func set_locked(on: bool) -> void:
	_locked = on
	_refresh()


## A front cue to test: "" (none), "glint" (ember strips on the front's edges) or "arc" (a faint red fan on the floor
## over the blocked arc). d always has its lamp's fan.
func set_front_cue(cue: String) -> void:
	_cue = cue
	(parts["glint"] as MeshInstance3D).visible = cue == "glint" and _state != "broken"
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
	return sh.global_transform * Vector3(0.05, _h * v, -_th * 0.5 - 0.05)


## Frozen lab pose: state, aim 0..1, walk speed (0 = standing) and a time for the cycles.
func pose_state(state: String, aim: float = 0.0, walk_speed: float = 0.0, t: float = 0.6, locked: bool = false) -> void:
	idle_enabled = false
	_locked = locked
	_wind = clampf(aim, 0.0, 1.0)
	_swing = 0.0
	_state = state
	set_shield(state)
	_update_glow()
	apply_idle(t, walk_speed)


# ------------------------------------------------------------------ animation

func apply_idle(t: float, speed: float = 0.0) -> void:
	if _downed:
		return
	var walk := clampf(speed / 2.5, 0.0, 1.0)
	var breath := sin(t * 2.0)
	var stride := sin(t * 7.0)
	var w := wind_e()
	var body := parts["body"] as MeshInstance3D
	var head := parts["head"] as MeshInstance3D
	var leg_l := parts["leg_l"] as MeshInstance3D
	var leg_r := parts["leg_r"] as MeshInstance3D
	var shield := parts["shield"] as MeshInstance3D
	var prop := parts["prop"] as MeshInstance3D
	var bow := parts["weapon"] as MeshInstance3D
	var planted_xf := Transform3D(Basis(Vector3.RIGHT, 0.06), Vector3(_shield_x, -0.03, -_shield_z))
	var shield_xf := planted_xf
	var bow_xf: Transform3D
	var hand_l: Vector3
	leg_l.position = Vector3(-LEG_X, HIP_Y, 0.0)
	leg_r.position = Vector3(LEG_X, HIP_Y, 0.0)
	(parts["jaw"] as MeshInstance3D).rotation.x = -0.06 - 0.05 * (0.5 + 0.5 * sin(t * 1.7)) - 0.25 * w
	match _state:
		"planted":
			body.position = Vector3(0, BODY_Y - _crouch + breath * 0.008, 0)
			body.rotation = Vector3(-0.08 - 0.06 * w, 0.0, 0.0)
			head.rotation = Vector3(sin(t * 1.3) * 0.02 - 0.10 * w, 0.0, 0.05 * w)
			leg_l.rotation = Vector3(0.34, 0.0, -0.08)
			leg_r.rotation = Vector3(-0.30, 0.0, 0.08)
			leg_l.position.y -= _crouch * 0.4
			leg_r.position.y -= _crouch * 0.4
			prop.rotation = Vector3(-0.50, 0.0, 0.0)
			bow_xf = _bow_rest_xf().interpolate_with(_bow_aim_xf(planted_xf), w)
			hand_l = bow_xf * FORE_GRIP
		"carried", "broken":
			var bob := absf(stride) * 0.03 * walk
			body.position = Vector3(0, BODY_Y + breath * 0.01 - bob, 0)
			body.rotation = Vector3(-0.05 - 0.05 * walk, stride * 0.06 * walk, 0.0)
			head.rotation = Vector3(sin(t * 1.3) * 0.03 + sin(t * 14.0) * 0.012 * walk, 0.0, 0.0)
			leg_l.rotation = Vector3(stride * 0.6 * walk, 0.0, 0.0)
			leg_r.rotation = Vector3(-stride * 0.6 * walk, 0.0, 0.0)
			prop.rotation = Vector3(-0.04, 0.0, 0.0)
			if _armour:
				shield_xf = Transform3D(Basis(Vector3.UP, -0.30) * Basis(Vector3.RIGHT, 0.04), Vector3(-0.26, 0.36 - bob, -_shield_z + 0.08))
			else:
				shield_xf = Transform3D(Basis(Vector3.UP, -0.12) * Basis(Vector3.RIGHT, 0.05), Vector3(-0.02, 0.12 - bob * 1.5, -_shield_z + 0.06))
			bow_xf = _bow_carry_xf(stride * walk)
			hand_l = shield_xf * Vector3(0.0, _h * 0.55, _th * 0.5 + 0.08)
		_:
			# "left" / "dropped": exposed, staggered back off its pavise, the bow held low in both hands
			body.position = Vector3(0, BODY_Y + breath * 0.01, 0)
			body.rotation = Vector3(0.10, 0.12, 0.04)
			head.rotation = Vector3(0.08 + sin(t * 1.3) * 0.03, 0.15, 0.0)
			leg_l.rotation = Vector3(0.22, 0.0, -0.10)
			leg_r.rotation = Vector3(-0.12, 0.0, 0.10)
			prop.rotation = Vector3(-0.50, 0.0, 0.0)
			if _state == "left":
				shield_xf = Transform3D(planted_xf.basis, planted_xf.origin + Vector3(0, 0, -LEFT_GAP))
			else:
				prop.rotation = Vector3(-0.04, 0.0, 0.0)
				shield_xf = Transform3D(Basis(Vector3.UP, PI + 0.35) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.30, _th * 0.5 + 0.075, -0.75))
			bow_xf = Transform3D(Basis(Vector3.UP, 0.45) * Basis(Vector3.RIGHT, -0.25), Vector3(0.10, 0.96, -0.30))
			hand_l = bow_xf * FORE_GRIP
	shield.transform = shield_xf
	(parts["shield_broken"] as MeshInstance3D).transform = shield_xf
	bow.transform = bow_xf
	var to_body := body.transform.affine_inverse()
	aim_limb(parts["arm_r"] as MeshInstance3D, to_body * (bow_xf * REAR_GRIP), ARM_LEN)
	aim_limb(parts["arm_l"] as MeshInstance3D, to_body * hand_l, ARM_LEN)
	_update_fx(w, shield_xf)


## Planted, not aiming (reloading, waiting): the bow held nose-down behind the shield.
func _bow_rest_xf() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, 0.15) * Basis(Vector3.RIGHT, -0.70), Vector3(0.16, BODY_Y - _crouch + 0.42, -0.08))


## Aiming: the stock in the sight notch (b: over the mantlet's top), the butt at the cheek.
func _bow_aim_xf(planted_xf: Transform3D) -> Transform3D:
	var top := planted_xf * Vector3(0.0, _h - _notch, 0.0)
	var y := top.y + 0.085
	if _armour:
		y = BODY_Y + 0.62
	return Transform3D(Basis.IDENTITY, Vector3(_shield_x + 0.06, y, top.z + 0.42 * _bow_k))


## Carried: shouldered, nose up and back, leaning out from the head.
func _bow_carry_xf(swing: float) -> Transform3D:
	var b := Basis(Vector3.BACK, -0.30) * Basis(Vector3.RIGHT, 1.80 + 0.05 * swing)
	return Transform3D(b, Vector3(0.44, 0.98, 0.10))


func _update_fx(w: float, shield_xf: Transform3D) -> void:
	var aiming := _state == "planted" and w > 0.04
	var idle_glow := variant == "c" and _state != "broken"
	_flare.visible = aiming or idle_glow
	var k := w if aiming else 0.0
	var size := (0.30 + 0.75 * k) * (1.35 if _locked and aiming else 1.0)
	if idle_glow:
		size = maxf(size, 0.42)
	_flare.scale = Vector3.ONE * size * (0.75 + 0.25 * _tip_k)
	_flare_mat.set_shader_parameter("energy", (3.2 if _locked and aiming else 1.7) * (0.6 + 0.4 * maxf(k, 0.4)))
	var fan_on := variant == "d" or _cue == "arc"
	_fan.visible = fan_on and (_state == "planted" or _state == "carried" or _state == "left") and (variant != "d" or k < 0.5)
	if _fan.visible:
		var o := shield_xf.origin
		_fan.transform = Transform3D(Basis(Vector3.UP, shield_xf.basis.get_euler().y), Vector3(o.x, 0.025, o.z))
	if variant == "d":
		var red := aiming and w > 0.3
		(parts["lamp_warm"] as MeshInstance3D).visible = not red and _state != "broken"
		(parts["lamp_red"] as MeshInstance3D).visible = red
		_spot.visible = _state != "broken" and _state != "dropped"
		_spot.light_color = LAMP_WARM.lerp(LAMP_RED, k)
		var d_model := maxf(aim_distance / maxf(scale.x, 0.01), 1.0)
		var down := atan2(_h + 0.13, d_model) + 0.06
		var dot_deg := rad_to_deg(atan2(0.9, d_model))                     # a spot ~1 unit across on the target
		_spot.spot_angle = lerpf(48.0, dot_deg, k)
		_spot.spot_range = lerpf(9.0, d_model * 2.5, k)
		_spot.spot_attenuation = lerpf(0.6, 0.0, k)
		_spot.light_energy = lerpf(6.0, 40.0 if _locked else 24.0, k)
		_spot.rotation = Vector3(lerpf(-0.42, -down, k), 0.0, 0.0)


func _slump() -> void:
	(parts["body"] as MeshInstance3D).rotation = Vector3(-0.30, 0.0, 0.0)
	(parts["head"] as MeshInstance3D).rotation = Vector3(-0.45, 0.0, 0.0)
	(parts["jaw"] as MeshInstance3D).rotation.x = -0.55
	(parts["arm_l"] as MeshInstance3D).rotation = Vector3(0.1, 0.0, -0.45)
	(parts["arm_r"] as MeshInstance3D).rotation = Vector3(0.0, 0.0, 0.45)
	(parts["arm_l"] as MeshInstance3D).scale = Vector3.ONE
	(parts["arm_r"] as MeshInstance3D).scale = Vector3.ONE
	_flare.visible = false
