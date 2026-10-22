class_name WickModel
extends LowPolyModel
## Wick, the Nervous Archer: a lanky, thin, worried FACETED low-poly human with a huge crooked,
## droopy olive wizard hat, messy dark hair, a muted blue-grey patched work jacket, a brown leather
## strap and satchel, brown boots, a makeshift bow of gnarled branches carried in his left hand, a
## stubby copper wand tucked in his belt and a quiver of mismatched arrows on his back. Built
## entirely in code from LowPoly soups (flat shaded, per-face painted colours) with the shared
## LowPolyMaterial toon + amber rim + ink outline.
##
## Faces local -Z, +X is his right (so the bow is in the -X hand). Origin is at the feet. About
## 2.2 units to the hat tip (the prototype hero is ~1.95, Gasket 1.74, Rebar ~3.2), only ~0.8 wide
## across the shoulders and arms, so he is the tallest, thinnest silhouette, and the hat is the
## signature shape from above.
##
## Rigid named parts (all MeshInstance3D): body, head, hat, jacket, belt, quiver, arm_l, arm_r,
## leg_l, leg_r, weapon (the bow), wand. Extras that belong to the bow: string (rebuilt when drawn)
## and arrow (only shown while a shot is drawn). head / jacket / belt / quiver / arms / bow / wand hang
## under body; hat hangs under head; string and arrow under the bow; legs under the root. Both
## sleeves are re-aimed every frame at their hand (the bow grip, the string, the wand).
##
## Hero hooks: shoot_pose() (raise the bow, draw, release), attack_swing() (bow bash), cast_pose()
## (raise the copper wand), set_downed(), ui_height, has_own_weapon. For the future hold-to-draw
## charged shot: draw_hold(amount) holds the bow raised and drawn, draw_hold(0.0) lets it go.

const MODEL_SCALE := 1.0

const PART_NAMES: Array[String] = ["body", "head", "hat", "jacket", "belt", "quiver", "arm_l", "arm_r", "leg_l", "leg_r", "weapon", "wand"]
const BOW_PART_NAMES: Array[String] = ["string", "arrow"]

# Palette (sRGB, painted).
const HAT := Color(0.50, 0.54, 0.22)             ## olive / khaki green
const HAT_LIGHT := Color(0.63, 0.67, 0.30)
const HAT_DARK := Color(0.36, 0.40, 0.15)
const BAND := Color(0.30, 0.20, 0.12)
const JACKET := Color(0.46, 0.55, 0.68)          ## muted blue-grey work jacket
const JACKET_LIGHT := Color(0.55, 0.63, 0.75)
const JACKET_DARK := Color(0.30, 0.37, 0.48)
const PANTS := Color(0.27, 0.32, 0.42)
const PANTS_DARK := Color(0.21, 0.25, 0.34)
const SHIRT := Color(0.88, 0.84, 0.74)
const SKIN := Color(0.95, 0.78, 0.66)
const SKIN_DARK := Color(0.84, 0.61, 0.49)
const EYE := Color(0.96, 0.95, 0.90)
const MOUTH := Color(0.55, 0.28, 0.25)
const HAIR := Color(0.16, 0.11, 0.09)
const HAIR_LIGHT := Color(0.29, 0.20, 0.14)
const LEATHER := Color(0.36, 0.22, 0.12)
const LEATHER_LIGHT := Color(0.55, 0.35, 0.18)
const BOOT := Color(0.46, 0.28, 0.15)
const BOOT_DARK := Color(0.30, 0.18, 0.10)
const PATCH_OCHRE := Color(0.76, 0.60, 0.30)
const PATCH_RED := Color(0.66, 0.30, 0.25)
const COPPER := Color(0.86, 0.48, 0.25)
const COPPER_LIGHT := Color(0.96, 0.67, 0.42)
const COPPER_DARK := Color(0.62, 0.32, 0.16)
const GLOW := Color(0.78, 1.00, 0.86)
const LAMP := Color(1.00, 0.93, 0.62)
const METAL := Color(0.62, 0.64, 0.69)
const METAL_DARK := Color(0.38, 0.40, 0.46)
const BRANCH := Color(0.82, 0.62, 0.36)           ## gnarled bow wood
const BRANCH_DARK := Color(0.58, 0.40, 0.22)
const CORD := Color(0.88, 0.80, 0.60)
const STRING_COL := Color(0.96, 0.93, 0.82)
const SHAFT := Color(0.84, 0.72, 0.48)
const FLETCH_RED := Color(0.88, 0.26, 0.20)
const FLETCH_TEAL := Color(0.25, 0.70, 0.68)
const FLETCH_YELLOW := Color(0.96, 0.82, 0.30)
const FLETCH_BLACK := Color(0.16, 0.14, 0.16)

const BODY_Y := 0.92                               ## pelvis / hip height
const HEAD_Y := 0.78                               ## body-local head centre
const SHOULDER := Vector3(0.28, 0.54, 0.0)         ## body-local shoulder pivot (mirrored for the left)
const ARM_LEN := 0.64                              ## shoulder to fist
const LEG_X := 0.14

const BOW_HALF := 0.80                             ## half length of the bow
const BOW_BULGE := 0.34                            ## how far the tips curl toward the archer
const BOW_PULL := 0.46                             ## string travel when fully drawn
const BOW_REST_POS := Vector3(-0.70, 0.12, -0.28)   ## body-local grip while carried
const BOW_REST_YAW := deg_to_rad(90.0)              ## carried with its curve facing the viewer from the front
const BOW_REST_ROLL := deg_to_rad(36.0)             ## and canted so both limbs show
const BOW_AIM_YAW := deg_to_rad(22.0)              ## the aimed bow is turned a little so its curve still shows
const BOW_AIM_ROLL := deg_to_rad(20.0)
const BOW_AIM_POS := Vector3(-0.18, 0.64, -0.70)    ## body-local grip while aiming
const BOW_WIND_POS := Vector3(-0.88, 0.36, 0.10)    ## bash wind-up
const BOW_STRIKE_POS := Vector3(-0.02, 0.30, -0.76)
## The strike-first bash's follow-through (the grounded_anim profile, HeroFeel's `follow` channel 0..1): the bow carries on
## from the strike across to his right front, so the sweep covers the wedge it hits.
const BOW_FOLLOW_POS := Vector3(0.46, 0.26, -0.56)
const BOW_FOLLOW_ROLL := -0.7

const HAND_R_REST := Vector3(0.38, -0.08, -0.03)    ## body-local right fist hanging
const HAND_R_CAST := Vector3(0.30, 0.80, -0.56)     ## wand raised
const WAND_REST_POS := Vector3(0.26, 0.06, -0.16)   ## tucked in the belt at the right hip
## The held spell component (hold_item) rides in his right fist wherever it is (hanging, on the string, raised with the
## wand): just under the knuckles, so the wand stands clear above it, and about 0.35 across (it used to float 0.3 above
## the hand at torso size and hid the wand hand: animation-research.md gap 8).
const HOLD_GRIP := Vector3(0.0, -0.09, -0.05)
const HOLD_SCALE := 0.7
const WAND_REST_ROT := Vector3(deg_to_rad(-18.0), 0.0, deg_to_rad(-16.0))

var _body_base_y := BODY_Y
var _thin_mat: ShaderMaterial          ## thinner ink outline for the string and arrow
var _arrow_on := false
var _string_pull := -9.0               ## the pull the string mesh was last built for
var _shoot_tween: Tween


func _init() -> void:
	_setup_model("WickModel", MODEL_SCALE)
	ui_height = 2.27 * MODEL_SCALE
	has_own_weapon = true
	_arm_kick = {"bash": 0.0, "cast": 0.0, "raise": 0.0, "draw": 0.0, "follow": 0.0}
	hold_scale = HOLD_SCALE
	_thin_mat = LowPolyMaterial.make(1.1)
	_build()


# ------------------------------------------------------------------ build

func _build() -> void:
	var body := _add_part("body", _body_soup(), self, Vector3(0, _body_base_y, 0))
	var head := _add_part("head", _head_soup(), body, Vector3(0, HEAD_Y, -0.03))
	_add_part("hat", _hat_soup(), head, Vector3(0, 0.14, 0.0))
	_add_part("jacket", _jacket_soup(), body, Vector3.ZERO)
	_add_part("belt", _belt_soup(), body, Vector3(0, 0.13, 0))
	_add_part("quiver", _quiver_soup(), body, Vector3.ZERO)
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		_add_part("arm_" + side, _arm_soup(s), body, Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z))
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(LEG_X * s, BODY_Y, 0.0))
	var bow := _add_part("weapon", _bow_soup(), body, BOW_REST_POS)
	var string_mi := _add_part("string", _string_soup(0.0), bow, Vector3.ZERO)
	string_mi.material_override = _thin_mat
	var arrow := _add_part("arrow", _arrow_soup(), bow, Vector3(0.0, 0.03, BOW_BULGE))
	arrow.material_override = _thin_mat
	arrow.visible = false
	_add_part("wand", _wand_soup(), body, WAND_REST_POS)
	apply_idle(0.0)


## The pelvis, an undershirt and the neck. The jacket and belt go over this.
func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.box(Vector3(0.34, 0.22, 0.26), PANTS, 221, 0.02, 1, 0.07)
	s.merge(LowPoly.frustum(Vector2(0.34, 0.24), Vector2(0.40, 0.26), 0.52, SHIRT, 222, 0.02, 1, Vector2.ZERO, 0.06), LowPoly.at(Vector3(0, 0.30, 0)))
	s.merge(LowPoly.cylinder(0.07, 0.06, 0.20, 6, SKIN_DARK, 223, 0.008), LowPoly.at(Vector3(0, 0.66, 0.0)))   # long neck
	return s


## Narrow, worried head: a long nose, wide eyes with brows pinched up in the middle, a small
## wobbly mouth, messy dark hair sticking out under the hat.
func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.box(Vector3(0.32, 0.38, 0.30), SKIN, 211, 0.05, 2, 0.05)
	s.merge(LowPoly.boulder(Vector3(0.045, 0.085, 0.075), 0, 0.2, SKIN_DARK, 212, 0.06), LowPoly.at(Vector3(0, -0.04, -0.175)))   # long nose
	for x: int in [-1, 1]:
		s.merge(LowPoly.box(Vector3(0.075, 0.08, 0.03), EYE, 213 + x, 0.0, 1, 0.0), LowPoly.at(Vector3(0.075 * x, 0.045, -0.158)))
		s.merge(LowPoly.box(Vector3(0.035, 0.05, 0.03), HAIR, 215 + x, 0.0, 1, 0.0), LowPoly.at(Vector3(0.068 * x, 0.04, -0.17)))   # pupils
		s.merge(LowPoly.box(Vector3(0.11, 0.032, 0.03), HAIR, 217 + x, 0.0, 1, 0.05), LowPoly.at(Vector3(0.08 * x, 0.115, -0.162), Vector3(0, 0, -16.0 * x)))   # worried brows
		s.merge(LowPoly.boulder(Vector3(0.03, 0.06, 0.04), 0, 0.2, SKIN_DARK, 219 + x, 0.05), LowPoly.at(Vector3(0.17 * x, 0.0, 0.0)))   # ears
		s.merge(LowPoly.boulder(Vector3(0.07, 0.16, 0.14), 0, 0.15, HAIR, 224 + x, 0.07), LowPoly.at(Vector3(0.175 * x, 0.03, 0.03)))   # side hair
		s.merge(LowPoly.boulder(Vector3(0.08, 0.10, 0.07), 0, 0.15, HAIR_LIGHT, 226 + x, 0.07), LowPoly.at(Vector3(0.10 * x, -0.17, 0.14)))   # nape tufts
		s.merge(LowPoly.box(Vector3(0.04, 0.17, 0.04), HAIR, 228 + x, 0.01, 1, 0.07), LowPoly.at(Vector3(0.21 * x, -0.12, 0.05), Vector3(0, 0, 24.0 * x)))   # stray locks
	s.merge(LowPoly.box(Vector3(0.08, 0.022, 0.025), MOUTH, 230, 0.0, 1, 0.0), LowPoly.at(Vector3(0.012, -0.125, -0.158), Vector3(0, 0, 6)))
	s.merge(LowPoly.boulder(Vector3(0.19, 0.20, 0.10), 0, 0.15, HAIR, 231, 0.07), LowPoly.at(Vector3(0, 0.0, 0.15)))   # back mass
	s.merge(LowPoly.boulder(Vector3(0.06, 0.07, 0.04), 0, 0.15, HAIR_LIGHT, 232, 0.07), LowPoly.at(Vector3(0.05, 0.17, -0.155), Vector3(0, 0, 20)))   # fringe
	s.merge(LowPoly.boulder(Vector3(0.06, 0.07, 0.04), 0, 0.15, HAIR, 233, 0.07), LowPoly.at(Vector3(-0.07, 0.165, -0.15), Vector3(0, 0, -25)))
	s.merge(LowPoly.box(Vector3(0.04, 0.15, 0.04), HAIR, 234, 0.01, 1, 0.07), LowPoly.at(Vector3(0.0, -0.20, 0.17), Vector3(-20, 0, 0)))
	return s


## The signature shape: a huge crooked, droopy polygonal wizard hat. Local origin is the centre of the
## brim, just above the forehead. A wavy, drooping brim (low at the front, lifted at the back), a
## dark band with a little headlamp, and a crown that leans, bends over and droops at the tip.
func _hat_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(201, 0.08)
	var edge_y: Array[float] = [-0.04, 0.03, 0.05, -0.04, -0.15, -0.14, -0.05, -0.03]
	var edge_r: Array[float] = [0.40, 0.38, 0.43, 0.49, 0.53, 0.46, 0.40, 0.40]
	var n := edge_y.size()
	var inner := 0.26
	var thick := Vector3(0, -0.035, 0)
	for i in n:
		var j := (i + 1) % n
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(j) / float(n)
		var in0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var in1 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		var out0 := Vector3(cos(a0) * edge_r[i], edge_y[i], sin(a0) * edge_r[i])
		var out1 := Vector3(cos(a1) * edge_r[j], edge_y[j], sin(a1) * edge_r[j])
		_quad(s, in0, in1, out1, out0, HAT_LIGHT if i % 2 == 0 else HAT, Vector3.UP)
		_quad(s, in0 + thick, in1 + thick, out1 + thick, out0 + thick, HAT_DARK, Vector3.DOWN)
		_quad(s, out0, out1, out1 + thick, out0 + thick, HAT_DARK, (out0 + out1) * Vector3(0.5, 0.0, 0.5))
	var band_pts: Array[Vector3] = [Vector3(0, 0.0, 0), Vector3(0, 0.10, 0)]
	var band_r: Array[float] = [0.268, 0.256]
	_tube(s, band_pts, band_r, 8, BAND, BAND, false, false)
	var crown_pts: Array[Vector3] = [Vector3(0, 0.10, 0), Vector3(0, 0.19, 0.01), Vector3(0.02, 0.28, 0.05),
			Vector3(0.08, 0.35, 0.13), Vector3(0.18, 0.38, 0.24), Vector3(0.29, 0.35, 0.34), Vector3(0.35, 0.28, 0.37)]
	var crown_r: Array[float] = [0.256, 0.226, 0.185, 0.14, 0.10, 0.06, 0.0]
	_tube(s, crown_pts, crown_r, 8, HAT_LIGHT, HAT_DARK, false, true)
	# headlamp on the band
	s.merge(LowPoly.box(Vector3(0.14, 0.10, 0.08), METAL_DARK, 202, 0.005, 1, 0.05), LowPoly.at(Vector3(0, 0.05, -0.285)))
	s.merge(LowPoly.box(Vector3(0.09, 0.06, 0.03), LAMP, 203, 0.0, 1, 0.0), LowPoly.at(Vector3(0, 0.05, -0.33)))
	s.merge(LowPoly.box(Vector3(0.06, 0.12, 0.03), PATCH_OCHRE, 204, 0.0, 1, 0.05), LowPoly.at(Vector3(0.2, 0.22, -0.13), Vector3(0, -35, 8)))   # patch on the crown
	return s


## Muted blue-grey patched work jacket: shoulder yoke, collar, hem, pockets, buttons, patches and the
## leather strap across the chest.
func _jacket_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(231, 0.07)
	s.merge(LowPoly.frustum(Vector2(0.44, 0.33), Vector2(0.52, 0.30), 0.52, JACKET, 232, 0.025, 2, Vector2.ZERO, 0.07), LowPoly.at(Vector3(0, 0.30, 0)))
	s.merge(LowPoly.frustum(Vector2(0.46, 0.36), Vector2(0.45, 0.34), 0.16, JACKET_DARK, 233, 0.02, 1, Vector2.ZERO, 0.07), LowPoly.at(Vector3(0, 0.03, 0)))   # hem
	s.merge(LowPoly.boulder(Vector3(0.29, 0.08, 0.17), 0, 0.14, JACKET_LIGHT, 234, 0.07), LowPoly.at(Vector3(0, 0.57, 0.0)))   # shoulder yoke
	for x: int in [-1, 1]:
		s.merge(LowPoly.box(Vector3(0.15, 0.10, 0.05), JACKET_DARK, 235 + x, 0.01, 1, 0.07), LowPoly.at(Vector3(0.08 * x, 0.62, -0.07), Vector3(0, 0, -22.0 * x)))   # collar
		s.merge(LowPoly.box(Vector3(0.14, 0.12, 0.04), JACKET_DARK, 237 + x, 0.01, 1, 0.07), LowPoly.at(Vector3(0.12 * x, 0.14, -0.172)))   # pockets
	s.merge(LowPoly.box(Vector3(0.28, 0.10, 0.05), JACKET_DARK, 239, 0.01, 1, 0.07), LowPoly.at(Vector3(0, 0.62, 0.08)))   # back collar
	s.merge(LowPoly.box(Vector3(0.04, 0.44, 0.02), JACKET_DARK, 240, 0.0, 1, 0.05), LowPoly.at(Vector3(0, 0.30, -0.162)))   # placket
	for y: float in [0.20, 0.34, 0.48]:
		s.merge(LowPoly.box(Vector3(0.04, 0.04, 0.03), COPPER, 241, 0.0, 1, 0.0), LowPoly.at(Vector3(0, y, -0.17)))
	s.merge(LowPoly.box(Vector3(0.11, 0.11, 0.03), PATCH_RED, 242, 0.005, 1, 0.06), LowPoly.at(Vector3(-0.13, 0.43, -0.156)))   # chest patch
	s.merge(LowPoly.box(Vector3(0.09, 0.08, 0.03), PATCH_OCHRE, 243, 0.005, 1, 0.06), LowPoly.at(Vector3(-0.12, 0.14, -0.2), Vector3(0, 0, 8)))   # pocket patch
	s.merge(LowPoly.box(Vector3(0.12, 0.12, 0.03), PATCH_OCHRE, 244, 0.005, 1, 0.06), LowPoly.at(Vector3(-0.10, 0.40, 0.16), Vector3(0, 0, 10)))   # back patch
	# the leather strap over the right shoulder and across the chest to the left hip
	var a := Vector2(0.18, 0.58)
	var b := Vector2(-0.20, 0.08)
	var d := b - a
	var mid := (a + b) * 0.5
	s.merge(LowPoly.box(Vector3(0.07, d.length(), 0.03), LEATHER, 245, 0.005, 1, 0.06),
			LowPoly.at(Vector3(mid.x, mid.y, -0.172), Vector3(0, 0, rad_to_deg(atan2(-d.x, d.y)))))
	s.merge(LowPoly.box(Vector3(0.07, 0.035, 0.37), LEATHER, 246, 0.005, 1, 0.06), LowPoly.at(Vector3(0.18, 0.62, 0.0)))
	s.merge(LowPoly.box(Vector3(0.05, 0.05, 0.03), COPPER, 247, 0.0, 1, 0.0), LowPoly.at(Vector3(-0.02, 0.34, -0.19)))   # buckle
	return s


func _belt_soup() -> LowPoly.Soup:
	var s := LowPoly.box(Vector3(0.48, 0.07, 0.35), LEATHER, 251, 0.01, 2)
	s.merge(LowPoly.box(Vector3(0.09, 0.08, 0.03), COPPER, 252, 0.0, 1, 0.04), LowPoly.at(Vector3(0, 0, -0.18)))   # buckle
	s.merge(LowPoly.box(Vector3(0.11, 0.13, 0.08), LEATHER_LIGHT, 253, 0.01, 1, 0.07), LowPoly.at(Vector3(-0.19, -0.05, -0.15)))   # pouch
	s.merge(LowPoly.box(Vector3(0.12, 0.05, 0.09), LEATHER, 254, 0.0, 1, 0.07), LowPoly.at(Vector3(-0.19, 0.0, -0.15)))
	s.merge(LowPoly.box(Vector3(0.06, 0.10, 0.04), LEATHER, 255, 0.0, 1, 0.07), LowPoly.at(Vector3(0.20, -0.04, -0.17)))   # wand loop
	return s


## A leaning leather quiver on his back (bottom at the right hip, mouth over the left shoulder) with
## four mismatched arrows poking out, plus a satchel on the left hip.
func _quiver_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(261, 0.07)
	var bot := Vector3(0.15, 0.02, 0.24)
	var top := Vector3(-0.30, 0.80, 0.23)
	var axis := (top - bot).normalized()
	var pts: Array[Vector3] = [bot, bot.lerp(top, 0.35), bot.lerp(top, 0.7), top]
	var radii: Array[float] = [0.085, 0.10, 0.115, 0.125]
	_tube(s, pts, radii, 6, LEATHER_LIGHT, LEATHER, true, false)
	var rim_pts: Array[Vector3] = [top, top + axis * 0.05]
	var rim_r: Array[float] = [0.132, 0.132]
	_tube(s, rim_pts, rim_r, 6, BOOT_DARK, BOOT_DARK, false, false)
	var fletch: Array[Color] = [FLETCH_RED, FLETCH_TEAL, FLETCH_YELLOW, FLETCH_BLACK]
	var offs: Array[Vector3] = [Vector3(0.05, 0.0, 0.03), Vector3(-0.04, 0.0, 0.04), Vector3(0.0, 0.0, -0.05), Vector3(-0.07, 0.0, -0.02)]
	var splay: Array[Vector3] = [Vector3(0.20, 0.0, 0.10), Vector3(-0.15, 0.0, 0.18), Vector3(0.05, 0.0, -0.22), Vector3(-0.28, 0.0, -0.05)]
	var lens: Array[float] = [0.46, 0.38, 0.52, 0.42]
	for i in 4:
		var p0: Vector3 = top + offs[i] - axis * 0.12
		var dir := (axis + splay[i]).normalized()
		var p1 := p0 + dir * lens[i]
		var shaft_pts: Array[Vector3] = [p0, p1]
		var shaft_r: Array[float] = [0.02, 0.02]
		_tube(s, shaft_pts, shaft_r, 4, SHAFT, SHAFT, false, true)
		var fl_pts: Array[Vector3] = [p1 - dir * 0.15, p1]
		var fl_r: Array[float] = [0.045, 0.05]
		_tube(s, fl_pts, fl_r, 4, fletch[i], fletch[(i + 1) % 4], false, true)
	# satchel on the left hip
	s.merge(LowPoly.box(Vector3(0.12, 0.20, 0.18), LEATHER_LIGHT, 262, 0.01, 1, 0.07), LowPoly.at(Vector3(-0.28, 0.02, 0.10)))
	s.merge(LowPoly.box(Vector3(0.13, 0.07, 0.19), LEATHER, 263, 0.01, 1, 0.07), LowPoly.at(Vector3(-0.28, 0.11, 0.10)))
	s.merge(LowPoly.box(Vector3(0.14, 0.04, 0.04), COPPER, 264, 0.0, 1, 0.0), LowPoly.at(Vector3(-0.28, 0.07, 0.0)))
	return s


## Thin sleeve + shoulder pad, pivot at the shoulder, bare forearm and a hand at the end.
func _arm_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.boulder(Vector3(0.11, 0.09, 0.11), 0, 0.15, JACKET_LIGHT, 301 + side, 0.07)
	s.merge(LowPoly.frustum(Vector2(0.15, 0.15), Vector2(0.12, 0.12), 0.40, JACKET, 303 + side, 0.025, 1, Vector2.ZERO, 0.07), LowPoly.at(Vector3(0, -0.22, 0)))
	s.merge(LowPoly.box(Vector3(0.11, 0.10, 0.03), PATCH_OCHRE if side < 0 else PATCH_RED, 305 + side, 0.005, 1, 0.06), LowPoly.at(Vector3(0, -0.24, -0.078)))   # elbow patch
	s.merge(LowPoly.cylinder(0.075, 0.075, 0.07, 6, JACKET_DARK, 307 + side, 0.01), LowPoly.at(Vector3(0, -0.43, 0)))   # cuff
	s.merge(LowPoly.cylinder(0.052, 0.046, 0.14, 6, SKIN_DARK, 309 + side, 0.008), LowPoly.at(Vector3(0, -0.52, 0)))
	s.merge(LowPoly.boulder(Vector3(0.07, 0.075, 0.07), 0, 0.15, SKIN, 311 + side, 0.06), LowPoly.at(Vector3(0, -0.62, 0)))   # hand
	return s


## Long thin trouser leg with a knee patch and a brown boot. Pivot at the hip.
func _leg_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(321, 0.07)
	s.merge(LowPoly.frustum(Vector2(0.15, 0.15), Vector2(0.17, 0.17), 0.40, PANTS, 322 + side, 0.02), LowPoly.at(Vector3(0, -0.21, 0)))
	s.merge(LowPoly.frustum(Vector2(0.12, 0.12), Vector2(0.15, 0.15), 0.36, PANTS_DARK, 324 + side, 0.02), LowPoly.at(Vector3(0, -0.58, 0)))
	s.merge(LowPoly.box(Vector3(0.11, 0.10, 0.03), PATCH_OCHRE, 326 + side, 0.005, 1, 0.06), LowPoly.at(Vector3(0, -0.40, -0.08)))   # knee patch
	s.merge(LowPoly.frustum(Vector2(0.20, 0.28), Vector2(0.17, 0.20), 0.30, BOOT, 328 + side, 0.025, 2, Vector2.ZERO, 0.08), LowPoly.at(Vector3(0, -0.77, -0.03)))
	s.merge(LowPoly.cylinder(0.115, 0.115, 0.05, 6, LEATHER_LIGHT, 330 + side, 0.01), LowPoly.at(Vector3(0, -0.62, -0.01)))   # boot cuff
	s.merge(LowPoly.boulder(Vector3(0.09, 0.06, 0.10), 0, 0.14, BOOT_DARK, 332 + side, 0.08), LowPoly.at(Vector3(0, -0.86, -0.15)))   # toe cap
	s.merge(LowPoly.box(Vector3(0.21, 0.04, 0.30), BOOT_DARK, 334 + side, 0.0, 1, 0.05), LowPoly.at(Vector3(0, -0.90, -0.03)))   # sole
	return s


## The makeshift bow: gnarled branches lashed together, chunkier than a real bow so it survives the
## game zoom. Local origin is the grip; the limbs run along local Y and the tips curl toward +Z, the
## side the string and the archer are on.
func _bow_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(401, 0.08)
	var ys: Array[float] = [-0.80, -0.60, -0.40, -0.20, 0.0, 0.20, 0.40, 0.60, 0.80]
	var wob: Array[float] = [0.0, 0.03, -0.02, 0.02, 0.0, -0.02, 0.03, -0.03, 0.0]
	var rad: Array[float] = [0.050, 0.060, 0.072, 0.080, 0.086, 0.080, 0.072, 0.060, 0.050]
	var pts: Array[Vector3] = []
	for i in ys.size():
		var f := absf(ys[i]) / BOW_HALF
		pts.append(Vector3(wob[i], ys[i], BOW_BULGE * pow(f, 1.8)))
	_tube(s, pts, rad, 5, BRANCH, BRANCH_DARK, true, true)
	s.merge(LowPoly.cylinder(0.104, 0.104, 0.22, 6, LEATHER, 402, 0.01), LowPoly.at(Vector3(0, 0.0, 0)))   # leather grip wrap
	for y: float in [-0.42, 0.40]:
		var z := BOW_BULGE * pow(absf(y) / BOW_HALF, 1.8)
		s.merge(LowPoly.cylinder(0.088, 0.088, 0.06, 6, CORD, 403, 0.008), LowPoly.at(Vector3(0.0, y, z), Vector3(0, 0, 0)))   # lashings
	s.merge(LowPoly.boulder(Vector3(0.07, 0.06, 0.07), 0, 0.2, BRANCH_DARK, 404, 0.07), LowPoly.at(Vector3(0.06, 0.26, 0.05)))   # knots
	s.merge(LowPoly.boulder(Vector3(0.055, 0.05, 0.055), 0, 0.2, BRANCH_DARK, 405, 0.07), LowPoly.at(Vector3(-0.06, -0.52, 0.17)))
	s.merge(LowPoly.boulder(Vector3(0.07, 0.07, 0.07), 0, 0.2, BRANCH_DARK, 406, 0.07), LowPoly.at(Vector3(0.0, BOW_HALF + 0.01, BOW_BULGE)))   # tip nocks
	s.merge(LowPoly.boulder(Vector3(0.07, 0.07, 0.07), 0, 0.2, BRANCH_DARK, 407, 0.07), LowPoly.at(Vector3(0.0, -BOW_HALF - 0.01, BOW_BULGE)))
	var twig_pts: Array[Vector3] = [Vector3(0.02, -0.32, 0.06), Vector3(0.13, -0.46, -0.03), Vector3(0.22, -0.58, -0.13)]
	var twig_r: Array[float] = [0.042, 0.034, 0.018]
	_tube(s, twig_pts, twig_r, 4, BRANCH, BRANCH_DARK, false, true)   # a stub of branch left on
	return s


## The bowstring: a V from tip to nock to tip. `pull` 0 = at rest, 1 = fully drawn (negative = the
## recoil past rest after release). Rebuilt only when the pull changes.
func _string_soup(pull: float) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(411, 0.0)
	var nock := Vector3(0.0, 0.0, BOW_BULGE + BOW_PULL * pull)
	var top_pts: Array[Vector3] = [Vector3(0.0, BOW_HALF + 0.01, BOW_BULGE), nock]
	var bot_pts: Array[Vector3] = [nock, Vector3(0.0, -BOW_HALF - 0.01, BOW_BULGE)]
	var r: Array[float] = [0.020, 0.020]
	_tube(s, top_pts, r, 4, STRING_COL, STRING_COL, false, false)
	_tube(s, bot_pts, r, 4, STRING_COL, STRING_COL, false, false)
	return s


## A nocked arrow, origin at the nock end, flying down local -Z.
func _arrow_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(421, 0.05)
	var shaft: Array[Vector3] = [Vector3(0, 0, 0), Vector3(0, 0, -0.95)]
	var shaft_r: Array[float] = [0.021, 0.021]
	_tube(s, shaft, shaft_r, 4, SHAFT, SHAFT, false, false)
	var fl: Array[Vector3] = [Vector3(0, 0, 0.0), Vector3(0, 0, -0.15)]
	var fl_r: Array[float] = [0.048, 0.04]
	_tube(s, fl, fl_r, 4, FLETCH_RED, FLETCH_YELLOW, true, false)
	var head: Array[Vector3] = [Vector3(0, 0, -0.95), Vector3(0, 0, -1.10)]
	var head_r: Array[float] = [0.045, 0.0]
	_tube(s, head, head_r, 4, METAL, METAL_DARK, false, false)
	return s


## The stubby copper wand. Local origin is the grip; it runs up local +Y.
func _wand_soup() -> LowPoly.Soup:
	var s := LowPoly.cylinder(0.050, 0.044, 0.50, 6, COPPER, 431, 0.008, 2)
	s = _moved(s, Vector3(0, 0.13, 0))                                                                       # spans y -0.12 .. 0.38
	s.merge(LowPoly.cylinder(0.064, 0.064, 0.14, 6, CORD, 432, 0.01), LowPoly.at(Vector3(0, 0.0, 0)))          # taped grip
	s.merge(LowPoly.cylinder(0.062, 0.062, 0.04, 6, COPPER_DARK, 433, 0.008), LowPoly.at(Vector3(0, 0.17, 0)))   # collars
	s.merge(LowPoly.cylinder(0.062, 0.062, 0.04, 6, COPPER_DARK, 434, 0.008), LowPoly.at(Vector3(0, 0.30, 0)))
	s.merge(LowPoly.boulder(Vector3(0.075, 0.075, 0.075), 0, 0.15, COPPER_LIGHT, 435, 0.06), LowPoly.at(Vector3(0, 0.41, 0)))   # tip
	s.merge(LowPoly.boulder(Vector3(0.042, 0.042, 0.042), 0, 0.1, GLOW, 436, 0.03), LowPoly.at(Vector3(0, 0.47, 0)))
	return s


# ------------------------------------------------------------------ soup helpers

## One triangle appended wound so its normal points along `hint` (rather than away from the soup's
## origin), for thin sheets and bent tubes where "outward from the origin" is ambiguous.
static func _tri(s: LowPoly.Soup, a: Vector3, b: Vector3, c: Vector3, col: Color, hint: Vector3) -> void:
	var bb := b
	var cc := c
	if (b - a).cross(c - a).dot(hint) < 0.0:
		bb = c
		cc = b
	s.verts.append(a)
	s.verts.append(bb)
	s.verts.append(cc)
	s.cols.append(s.paint(col))


static func _quad(s: LowPoly.Soup, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, hint: Vector3) -> void:
	_tri(s, a, b, c, col, hint)
	_tri(s, a, c, d, col, hint)


## A faceted tube along a path: a ring of `sides` points around each path point (radius per point,
## 0 closes it to a point), quads between rings alternating col_a / col_b, optional flat end caps.
static func _tube(s: LowPoly.Soup, pts: Array[Vector3], radii: Array[float], sides: int, col_a: Color, col_b: Color, cap_start: bool = true, cap_end: bool = true) -> void:
	var n := pts.size()
	var rings: Array[PackedVector3Array] = []
	var u := Vector3.ZERO
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		if i == 0:
			var ref := Vector3.UP if absf(t.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
			u = (ref - t * t.dot(ref)).normalized()
		else:
			u = (u - t * u.dot(t)).normalized()
		var v := t.cross(u)
		var ring := PackedVector3Array()
		for j in sides:
			var ang := TAU * float(j) / float(sides)
			ring.append(pts[i] + (u * cos(ang) + v * sin(ang)) * radii[i])
		rings.append(ring)
	for i in n - 1:
		var mid := (pts[i] + pts[i + 1]) * 0.5
		for j in sides:
			var k := (j + 1) % sides
			var a := rings[i][j]
			var b := rings[i][k]
			var c := rings[i + 1][k]
			var d := rings[i + 1][j]
			_quad(s, a, b, c, d, col_a if j % 2 == 0 else col_b, (a + b + c + d) * 0.25 - mid)
	if cap_start:
		for j in sides:
			_tri(s, pts[0], rings[0][j], rings[0][(j + 1) % sides], col_a, pts[0] - pts[1])
	if cap_end:
		for j in sides:
			_tri(s, pts[n - 1], rings[n - 1][j], rings[n - 1][(j + 1) % sides], col_b, pts[n - 1] - pts[n - 2])


## `s` shifted by `off` (a fresh soup carrying the same painted faces).
static func _moved(s: LowPoly.Soup, off: Vector3) -> LowPoly.Soup:
	var out := LowPoly.Soup.new(1, 0.0)
	return out.merge(s, LowPoly.at(off))


# ------------------------------------------------------------------ animation

## Idle: a nervous fidget (hunch, head darting about, trembling knees, the hat tip bobbing). Walk:
## long strides, swinging free arm, hat tip lagging. Poses: raise / draw (shoot), bash, cast.
func apply_idle(t: float, speed: float = 0.0) -> void:
	var walk := clampf(speed / 4.0, 0.0, 1.0)
	var calm := 1.0 - walk
	var breath := sin(t * 2.1)
	var stride := sin(t * 9.0)
	var raise := clampf(arm_kick("raise"), 0.0, 1.0)
	var draw := arm_kick("draw")
	var bash := arm_kick("bash")
	var cast := clampf(arm_kick("cast"), 0.0, 1.0)

	var body := parts["body"] as MeshInstance3D
	body.position = Vector3(sin(t * 0.7) * 0.015 * calm, _body_base_y + breath * 0.010 - absf(stride) * 0.035 * walk, 0.0)
	body.rotation = Vector3(-0.10 - 0.05 * walk + breath * 0.01 + 0.12 * bash, sin(t * 0.8) * 0.04 * calm - 0.25 * raise, 0.0)
	var head := parts["head"] as MeshInstance3D
	head.rotation = Vector3(0.05 + sin(t * 1.7) * 0.02 - 0.04 * walk, (sin(t * 1.1) * 0.20 + sin(t * 3.1) * 0.07) * calm * (1.0 - raise) + 0.25 * raise, 0.0)
	var hat := parts["hat"] as MeshInstance3D
	hat.rotation = Vector3(0.16 + sin(t * 2.3) * 0.10 - absf(stride) * 0.12 * walk, 0.0, 0.10 + sin(t * 1.7 + 1.0) * 0.12 + stride * 0.06 * walk)
	var tremble := sin(t * 7.0) * 0.03 * calm
	(parts["leg_l"] as MeshInstance3D).rotation = Vector3(stride * 0.60 * walk + tremble, 0.0, 0.04)
	(parts["leg_r"] as MeshInstance3D).rotation = Vector3(-stride * 0.60 * walk - tremble, 0.0, -0.04)

	# the bow: carried at his left side, kicked by the bash, raised to aim by `raise`
	var bow_pos := BOW_REST_POS + Vector3(0.0, breath * 0.012 + stride * 0.02 * walk, -absf(stride) * 0.02 * walk)
	var roll := BOW_REST_ROLL + sin(t * 1.3) * 0.03
	var yaw := BOW_REST_YAW
	if bash > 0.0:
		bow_pos = bow_pos.lerp(BOW_WIND_POS, minf(bash, 1.0))
		roll += bash
	elif bash < 0.0:
		bow_pos = bow_pos.lerp(BOW_STRIKE_POS, minf(-bash / 1.2, 1.0))
		roll += bash * 1.1
	var follow := clampf(arm_kick("follow"), 0.0, 1.0)
	if follow > 0.0:
		bow_pos = bow_pos.lerp(BOW_FOLLOW_POS, follow)
		roll += BOW_FOLLOW_ROLL * follow
	bow_pos = bow_pos.lerp(BOW_AIM_POS, raise)
	roll = lerpf(roll, BOW_AIM_ROLL, raise)
	yaw = lerpf(yaw, BOW_AIM_YAW, raise)
	var bow := parts["weapon"] as MeshInstance3D
	bow.position = bow_pos
	bow.basis = Basis(Vector3.BACK, roll) * Basis(Vector3.UP, yaw)
	_set_string_pull(draw)
	var arrow := parts["arrow"] as MeshInstance3D
	arrow.visible = _arrow_on
	arrow.position.z = BOW_BULGE + BOW_PULL * clampf(draw, 0.0, 1.0)
	_aim_arm(parts["arm_l"] as MeshInstance3D, bow_pos)

	# the right hand: hangs and swings, draws the string, or raises the wand
	var hand := HAND_R_REST + Vector3(0.0, sin(t * 3.3) * 0.01 * calm, -stride * 0.20 * walk)
	hand = hand.lerp(HAND_R_CAST, cast)
	var nock := bow_pos + bow.basis * Vector3(0.0, 0.0, BOW_BULGE + BOW_PULL * clampf(draw, 0.0, 1.0))
	hand = hand.lerp(nock, raise)
	_aim_arm(parts["arm_r"] as MeshInstance3D, hand)

	# the wand: tucked in the belt, drawn to the hand for a cast
	var wand := parts["wand"] as MeshInstance3D
	var c := smoothstep(0.0, 0.5, cast)
	wand.position = (WAND_REST_POS + Vector3(0.0, breath * 0.006, 0.0)).lerp(hand + Vector3(0.0, 0.02, -0.04), c)
	wand.rotation = Vector3(lerpf(WAND_REST_ROT.x, deg_to_rad(-70.0), c), 0.0, lerpf(WAND_REST_ROT.z, 0.0, c))
	wand.visible = true

	# a held component sits in the free right hand, wherever it is (hanging, drawing, raised)
	if hold_anchor != null:
		hold_anchor.position = hand + HOLD_GRIP


## Re-aim a sleeve from the shoulder at `hand`, stretching it a little so it always reaches.
func _aim_arm(arm: MeshInstance3D, hand: Vector3) -> void:
	var d := hand - arm.position
	var dist := d.length()
	if dist < 0.01:
		return
	arm.quaternion = Quaternion(Vector3.DOWN, d / dist)
	arm.scale = Vector3(1.0, clampf(dist / ARM_LEN, 0.55, 1.3), 1.0)


func _set_string_pull(pull: float) -> void:
	var p := clampf(pull, -0.4, 1.0)
	if absf(p - _string_pull) < 0.02:
		return
	_string_pull = p
	(parts["string"] as MeshInstance3D).mesh = _string_soup(p).to_mesh()


## Raise the bow, draw, release: the hero's shoot pose. The bolt is already away when this is called,
## so it is quick: the string recoils and the bow comes back down.
func shoot_pose() -> void:
	if not is_inside_tree():
		return
	if _shoot_tween != null and _shoot_tween.is_valid():
		_shoot_tween.kill()
	_arrow_on = true
	_arm_kick["raise"] = 0.0
	_arm_kick["draw"] = 0.0
	var tw := create_tween()
	_shoot_tween = tw
	tw.tween_method(func(v: float) -> void: _arm_kick["raise"] = v, 0.0, 1.0, 0.07).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(v: float) -> void: _arm_kick["draw"] = v, 0.0, 1.0, 0.09).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: _arrow_on = false)
	tw.tween_method(func(v: float) -> void: _arm_kick["draw"] = v, 1.0, 0.0, 0.20).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.12)
	tw.tween_method(func(v: float) -> void: _arm_kick["raise"] = v, 1.0, 0.0, 0.30).set_trans(Tween.TRANS_SINE)


## Hold the bow raised and drawn by `amount` (0..1), for the hold-to-draw charged shot. 0 lowers it.
func draw_hold(amount: float) -> void:
	if _shoot_tween != null and _shoot_tween.is_valid():
		_shoot_tween.kill()
	var a := clampf(amount, 0.0, 1.0)
	_arrow_on = a > 0.0
	_arm_kick["raise"] = 1.0 if a > 0.0 else 0.0
	_arm_kick["draw"] = a


## Bow bash: wind the bow back and out, then sweep it across in front of him.
func attack_swing() -> void:
	if not is_inside_tree():
		return
	_kick_arm("bash", 1.0, -1.25, 0.10, 0.07, 0.30)


## Raise the copper wand for a cast (the hero's cast pose).
func cast_pose() -> void:
	if not is_inside_tree():
		return
	_kick_arm("cast", 0.5, 1.0, 0.08, 0.10, 0.55)


## Freeze a pose for the lab and tests: "rest", "shoot" (bow raised and drawn), "bash" (mid-sweep) or "cast".
func pose_preview(kind: String, time: float = 0.6) -> void:
	_arrow_on = false
	_arm_kick["raise"] = 0.0
	_arm_kick["draw"] = 0.0
	_arm_kick["bash"] = 0.0
	_arm_kick["cast"] = 0.0
	match kind:
		"shoot":
			_arm_kick["raise"] = 1.0
			_arm_kick["draw"] = 0.9
			_arrow_on = true
		"bash":
			_arm_kick["bash"] = -1.0
		"cast":
			_arm_kick["cast"] = 1.0
	apply_idle(time)


func set_downed(downed: bool) -> void:
	super.set_downed(downed)
	_thin_mat.set_shader_parameter("desat", 0.85 if downed else 0.0)
