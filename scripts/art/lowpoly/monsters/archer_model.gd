class_name ArcherModel
extends MonsterModel
## Archer: a hooded skeleton marksman in a deep emerald hood and robe, a void face with two lime eyes,
## a quiver of fletched arrows over the shoulder and a big dark horn-tipped bow. The bow is what says
## "ranged threat" from above: it is long, it is held out in front, and during the telegraph it comes up
## to aim, the string draws back and a toxic-green arrow nocks.
##
## INTEGRATION: kind "archer" -> MonsterModels.make("archer"); see the full patch at the top of
## monster_model.gd. windup(_telegraph) every frame (the draw: the bow rises, the string pulls back, the
## arrow nocks), attack_swing() at the shot (the string snaps, the bow kicks), set_downed / set_tint /
## set_fade as for every model. archer.gd needs no change (its _pose is null-guarded).
##
## Faces local -Z, +X is its right (the bow is in the left hand, -X). About 1.8 tall to the hood tip,
## ~0.8 wide, the bow ~1.4 long. Rigid named parts (MeshInstance3D): body, head, hood, quiver, arm_l,
## arm_r, leg_l, leg_r, weapon (the bow), string, arrow. Everything but the legs hangs under body; hood
## under head; string and arrow under the bow. Both arms are re-aimed every frame at their hand.

const MODEL_SCALE := 1.0
const PART_NAMES: Array[String] = ["body", "head", "hood", "quiver", "arm_l", "arm_r", "leg_l", "leg_r", "weapon", "string", "arrow"]

const HOOD := Color(0.12, 0.52, 0.26)
const HOOD_LIGHT := Color(0.26, 0.68, 0.30)
const HOOD_DARK := Color(0.07, 0.33, 0.16)
const ROBE := Color(0.09, 0.38, 0.18)
const ROBE_DARK := Color(0.05, 0.25, 0.12)
const VOID := Color(0.05, 0.04, 0.06)
const EYE := Color(0.82, 1.0, 0.22)
const BONE := Color(0.90, 0.86, 0.74)
const BONE_DARK := Color(0.62, 0.58, 0.48)
const LEATHER := Color(0.40, 0.25, 0.14)
const LEATHER_DARK := Color(0.26, 0.16, 0.10)
const WOOD := Color(0.36, 0.22, 0.16)
const WOOD_LIGHT := Color(0.52, 0.34, 0.22)
const STRING_COL := Color(0.94, 0.92, 0.80)
const SHAFT := Color(0.70, 0.56, 0.36)
const TOXIC := Color(0.55, 1.0, 0.25)
const BRASS := Color(0.82, 0.66, 0.32)

const BODY_Y := 0.86
const SHOULDER := Vector3(0.31, 0.30, 0.0)       ## body-local, mirrored for the left arm
const ARM_LEN := 0.64                            ## shoulder to fist
const LEG_X := 0.13
const BOW_HALF := 0.70
const BOW_BULGE := 0.32                          ## the tips curl this far toward the archer
const BOW_PULL := 0.34                           ## string travel when fully drawn
const GRIP_REST := Vector3(-0.44, 0.10, -0.42)   ## body-local bow grip while carried
const GRIP_AIM := Vector3(-0.12, 0.44, -0.68)    ## ... and while aiming
const HAND_REST := Vector3(0.30, -0.10, -0.22)   ## draw hand at rest

var _thin_mat: ShaderMaterial
var _string_pull := 99.0


func _init() -> void:
	_setup_model("ArcherModel", MODEL_SCALE)
	monster_kind = "archer"
	ui_height = 1.85 * MODEL_SCALE
	has_own_weapon = true
	_thin_mat = MonsterMaterial.make(1.1)
	_build()
	apply_idle(0.0)


# ------------------------------------------------------------------ build

func _build() -> void:
	var body := _add_part("body", _body_soup(), self, Vector3(0, BODY_Y, 0))
	var head := _add_part("head", _head_soup(), body, Vector3(0, 0.56, -0.02))
	_add_part("hood", _hood_soup(), head, Vector3.ZERO)
	_add_part("quiver", _quiver_soup(), body, Vector3.ZERO)
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		_add_part("arm_" + side, _arm_soup(s), body, Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z))
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(LEG_X * s, BODY_Y, 0.0))
	var bow := _add_part("weapon", _bow_soup(), body, GRIP_REST)
	var string_mi := _add_part("string", _string_soup(0.0), bow, Vector3.ZERO)
	string_mi.material_override = _thin_mat
	var arrow := _add_part("arrow", _arrow_soup(), bow, Vector3(0.0, 0.03, BOW_BULGE))
	arrow.material_override = _thin_mat
	arrow.visible = false


## Tapering robe with a ragged hem, a broad mantle over the shoulders, a belt and a bone buckle.
func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(301, 0.07)
	s.merge(LowPoly.frustum(Vector2(0.74, 0.60), Vector2(0.44, 0.34), 0.88, ROBE, 302, 0.03, 2, Vector2.ZERO, 0.08), LowPoly.at(Vector3(0, -0.10, 0)))
	s.merge(LowPoly.frustum(Vector2(0.76, 0.62), Vector2(0.74, 0.60), 0.07, HOOD_DARK, 303, 0.02, 1), LowPoly.at(Vector3(0, -0.50, 0)))   # hem trim
	for i in 9:
		var a := TAU * float(i) / 9.0 + 0.2
		var p := Vector3(cos(a) * 0.35, -0.53, sin(a) * 0.29)
		limb(s, p, p + Vector3(cos(a) * 0.03, -0.12 - 0.04 * float(i % 3), sin(a) * 0.03), 0.08, 0.0, 4, ROBE_DARK, 304 + i)   # ragged hem points
	blob(s, Vector3(0, 0.30, 0.0), Vector3(0.38, 0.17, 0.28), HOOD, 320, 0.14)                      # mantle
	slab(s, Vector3(0, 0.0, 0.0), Vector3(0.50, 0.07, 0.40), LEATHER, 321, Vector3.ZERO, 0.01)         # belt
	slab(s, Vector3(0, 0.0, -0.205), Vector3(0.08, 0.08, 0.03), BRASS, 322, Vector3.ZERO, 0.0, 0.03)  # buckle
	slab(s, Vector3(-0.26, -0.06, -0.14), Vector3(0.12, 0.14, 0.10), LEATHER_DARK, 323, Vector3(0, 12, 0), 0.01)   # pouch
	slab(s, Vector3(0, -0.10, 0.25), Vector3(0.40, 0.70, 0.04), ROBE_DARK, 324, Vector3(-4, 0, 0), 0.015)   # back cloak panel
	return s


## The face in the hood: a black void, two lime eyes and a bone jaw.
func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(331, 0.06)
	slab(s, Vector3(0, -0.02, -0.20), Vector3(0.32, 0.32, 0.20), VOID, 332, Vector3.ZERO, 0.02, 0.0)
	for x: int in [-1, 1]:
		slab(s, Vector3(0.082 * x, 0.02, -0.305), Vector3(0.10, 0.05, 0.03), glow(EYE), 333 + x, Vector3(0, 0, 18 * x), 0.0, 0.0)
	slab(s, Vector3(0, -0.13, -0.285), Vector3(0.16, 0.06, 0.05), BONE, 336, Vector3.ZERO, 0.01)        # jaw
	for i in 4:
		slab(s, Vector3(-0.054 + 0.036 * i, -0.095, -0.30), Vector3(0.02, 0.04, 0.02), BONE, 337 + i, Vector3.ZERO, 0.0, 0.0)   # teeth
	return s


## The hood: a rounded cowl, lighter rim framing the face, and a tall peak that droops backward.
func _hood_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(341, 0.07)
	blob(s, Vector3(0, 0.03, 0.04), Vector3(0.30, 0.29, 0.31), HOOD, 342, 0.1, 1)
	slab(s, Vector3(0, 0.17, -0.27), Vector3(0.42, 0.08, 0.10), HOOD_LIGHT, 343, Vector3(-8, 0, 0), 0.02)    # brow rim
	for x: int in [-1, 1]:
		slab(s, Vector3(0.205 * x, -0.03, -0.25), Vector3(0.08, 0.34, 0.10), HOOD_LIGHT, 344 + x, Vector3(0, 10 * x, 0), 0.02)   # cheek rims
	limb(s, Vector3(0, 0.16, 0.06), Vector3(0, 0.36, 0.26), 0.23, 0.08, 6, HOOD, 346, 0.02)           # low cowl peak
	limb(s, Vector3(0, 0.34, 0.24), Vector3(0, 0.22, 0.54), 0.09, 0.0, 5, HOOD_DARK, 347)             # drooping tip
	return s


## Leather quiver slung on the back with fletched arrows standing up behind the right shoulder.
func _quiver_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(351, 0.07)
	limb(s, Vector3(0.10, 0.04, 0.26), Vector3(0.24, 0.50, 0.30), 0.09, 0.115, 6, LEATHER, 352, 0.01)
	limb(s, Vector3(0.24, 0.48, 0.30), Vector3(0.245, 0.52, 0.30), 0.12, 0.12, 6, LEATHER_DARK, 353)
	var cols: Array[Color] = [BONE, Color(0.12, 0.10, 0.12), TOXIC]
	for i in 3:
		var x := 0.18 + 0.065 * float(i)
		limb(s, Vector3(x, 0.46, 0.30), Vector3(x + 0.03, 0.82 + 0.06 * float(i % 2), 0.31), 0.022, 0.022, 4, SHAFT, 354 + i)
		slab(s, Vector3(x + 0.03, 0.80 + 0.06 * float(i % 2), 0.31), Vector3(0.09, 0.15, 0.025), cols[i], 358 + i, Vector3(0, 0, -4), 0.0, 0.05)
	return s


## Wide sleeve, flared cuff, then a bare bone forearm and hand. Hangs from the shoulder; ARM_LEN long.
func _arm_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(361 + side, 0.07)
	blob(s, Vector3(0, 0.0, 0.0), Vector3(0.13, 0.12, 0.13), HOOD_DARK, 362 + side, 0.15)
	limb(s, Vector3(0, 0.0, 0.0), Vector3(0, -0.36, -0.01), 0.12, 0.10, 5, ROBE, 364 + side, 0.01)
	limb(s, Vector3(0, -0.34, -0.01), Vector3(0, -0.46, -0.01), 0.105, 0.125, 5, HOOD_LIGHT, 366 + side)
	limb(s, Vector3(0, -0.46, -0.01), Vector3(0, -0.60, -0.02), 0.045, 0.04, 4, BONE, 368 + side)
	blob(s, Vector3(0, -0.64, -0.03), Vector3(0.07, 0.075, 0.07), BONE, 370 + side, 0.15)
	return s


func _leg_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(381 + side, 0.07)
	limb(s, Vector3(0, -0.3, 0), Vector3(0, -0.76, 0.0), 0.06, 0.05, 5, BONE_DARK, 382 + side)
	blob(s, Vector3(0, -0.80, -0.06), Vector3(0.11, 0.07, 0.18), LEATHER_DARK, 384 + side, 0.12)
	return s


## A big recurve bow of dark wood with bone-capped tips. Grip at the origin, limbs along +-Y, tips
## curled toward +Z (the archer). Arrows fly down -Z.
func _bow_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(391, 0.07)
	var n := 8
	for i in n:
		var y0 := -BOW_HALF + 2.0 * BOW_HALF * float(i) / float(n)
		var y1 := -BOW_HALF + 2.0 * BOW_HALF * float(i + 1) / float(n)
		var z0 := BOW_BULGE * pow(absf(y0) / BOW_HALF, 1.8)
		var z1 := BOW_BULGE * pow(absf(y1) / BOW_HALF, 1.8)
		var r0 := lerpf(0.075, 0.034, absf(y0) / BOW_HALF)
		var r1 := lerpf(0.075, 0.034, absf(y1) / BOW_HALF)
		limb(s, Vector3(0, y0, z0), Vector3(0, y1, z1), r0, r1, 5, WOOD if i % 2 == 0 else WOOD_LIGHT, 392 + i, 0.01)
	limb(s, Vector3(0, -0.12, 0), Vector3(0, 0.12, 0), 0.09, 0.09, 6, LEATHER, 400, 0.01)             # grip wrap
	slab(s, Vector3(0, 0.0, -0.075), Vector3(0.06, 0.07, 0.05), glow(EYE), 401, Vector3.ZERO, 0.0, 0.0)  # a toxic rune on the riser
	for sgn: float in [-1.0, 1.0]:
		limb(s, Vector3(0, sgn * (BOW_HALF - 0.02), BOW_BULGE), Vector3(0, sgn * (BOW_HALF + 0.14), BOW_BULGE + 0.06), 0.05, 0.0, 5, BONE, 402 + int(sgn))   # bone tips
	return s


## The string: a V from tip to nock to tip. pull 0 = at rest, 1 = drawn, negative = the snap past rest.
func _string_soup(pull: float) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(411, 0.0)
	var nock := Vector3(0.0, 0.0, BOW_BULGE + BOW_PULL * pull)
	limb(s, Vector3(0, BOW_HALF + 0.02, BOW_BULGE), nock, 0.016, 0.016, 4, STRING_COL, 412, 0.0, 0.0)
	limb(s, nock, Vector3(0, -BOW_HALF - 0.02, BOW_BULGE), 0.016, 0.016, 4, STRING_COL, 413, 0.0, 0.0)
	return s


## A nocked arrow, origin at the nock end, flying down local -Z, with a glowing toxic head.
func _arrow_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(421, 0.05)
	limb(s, Vector3(0, 0, 0), Vector3(0, 0, -1.0), 0.026, 0.026, 4, SHAFT, 422, 0.0, 0.0)
	limb(s, Vector3(0, 0, -1.0), Vector3(0, 0, -1.16), 0.06, 0.0, 4, glow(TOXIC), 423, 0.0, 0.0)
	slab(s, Vector3(0, 0, -0.08), Vector3(0.11, 0.012, 0.16), BONE, 424, Vector3.ZERO, 0.0, 0.0)
	slab(s, Vector3(0, 0, -0.08), Vector3(0.012, 0.11, 0.16), Color(0.12, 0.10, 0.12), 425, Vector3.ZERO, 0.0, 0.0)
	return s


func _set_string_pull(pull: float) -> void:
	if absf(pull - _string_pull) < 0.015:
		return
	_string_pull = pull
	var mi := parts["string"] as MeshInstance3D
	mi.mesh = _string_soup(pull).to_mesh()
	(parts["arrow"] as MeshInstance3D).position.z = BOW_BULGE + BOW_PULL * pull


# ------------------------------------------------------------------ animation

func apply_idle(t: float, speed: float = 0.0) -> void:
	if _downed:
		return
	var walk := clampf(speed / 3.5, 0.0, 1.0)
	# The walk (active walk, MonsterModel.gait_k): a stalk. Crouched lower and leaning in, long careful steps that roll
	# the hips from side to side while the hooded head stays level and fixed ahead, the bow carried up and ready across
	# the body with the draw hand near the string. The war cry (cry_k): the bow raised high overhead and shaken, the
	# other fist up, the hood thrown back.
	var g := gait_k(walk)
	var cr := cry_k()
	var breath := sin(t * 1.8)
	var stride := sin(t * 7.5)
	var w := wind_e()
	var sw := _swing
	var draw := smoothstep(0.25, 1.0, _wind)
	var body := parts["body"] as MeshInstance3D
	body.position = Vector3(stride * 0.03 * g, BODY_Y + breath * 0.012 - absf(stride) * 0.035 * walk - 0.07 * g, 0.0)
	var lean := -0.16 * g
	body.rotation = Vector3(0.06 * w - 0.05 * walk + 0.10 * sw + lean + 0.18 * cr, stride * 0.05 * walk + stride * 0.06 * g,
			sin(t * 1.1) * 0.012 + stride * 0.03 * walk + stride * 0.06 * g)
	(parts["head"] as MeshInstance3D).rotation = Vector3(sin(t * 1.3) * 0.03 - 0.10 * w + 0.05 * sw - lean * 0.8 + 0.40 * cr,
			-stride * 0.06 * g, -stride * 0.06 * g)
	(parts["hood"] as MeshInstance3D).rotation.x = sin(t * 2.1 + 1.0) * 0.025 - 0.04 * walk - 0.05 * g + 0.20 * cr
	(parts["leg_l"] as MeshInstance3D).rotation.x = stride * (0.55 * walk + 0.15 * g) + 0.10 * g
	(parts["leg_r"] as MeshInstance3D).rotation.x = -stride * (0.55 * walk + 0.15 * g) + 0.10 * g

	# the bow hand (left): carried low and slanted (up and ready on the stalk), lifts to aim; the shot kicks it back
	var grip := GRIP_REST.lerp(GRIP_AIM, 0.35 * g)
	grip = grip.lerp(Vector3(-0.30, 1.05, -0.45), cr)            # the cry: the bow raised up in front
	grip = grip.lerp(GRIP_AIM, w)
	grip.y += breath * 0.01 + absf(stride) * 0.03 * walk + sin(t * 26.0) * 0.03 * cr
	grip.z += 0.07 * sw
	var bow := parts["weapon"] as MeshInstance3D
	bow.position = grip
	bow.rotation = Vector3(0.0 + 0.30 * sw, 0.0, lerpf(lerpf(lerpf(0.55, 0.30, g), 0.15, cr), 0.0, w))
	aim_limb(parts["arm_l"] as MeshInstance3D, Vector3(grip.x, grip.y + 0.04, grip.z + 0.02), ARM_LEN)

	# the string and the nocked arrow, and the draw hand following the nock
	var pull := draw - 1.25 * sw
	_set_string_pull(pull)
	var nock := Vector3(grip.x, grip.y + 0.03, grip.z + BOW_BULGE + BOW_PULL * draw)
	var hand := HAND_REST + Vector3(0.0, breath * 0.01, 0.0)
	hand.z += 0.10 * stride * walk
	hand = hand.lerp(Vector3(0.06, 0.16, -0.30), 0.5 * g)           # near the string on the stalk
	hand = hand.lerp(Vector3(0.40, 0.92, -0.40), cr)                # the cry: the fist up in front
	hand = hand.lerp(nock + Vector3(0.0, -0.02, 0.0), smoothstep(0.0, 0.5, _wind))
	hand = hand.lerp(Vector3(0.52, 0.50, 0.16), clampf(sw * 1.5, 0.0, 1.0))
	aim_limb(parts["arm_r"] as MeshInstance3D, hand, ARM_LEN)
	(parts["arrow"] as MeshInstance3D).visible = _wind > 0.12 and sw < 0.2


func _slump() -> void:
	(parts["body"] as MeshInstance3D).rotation = Vector3(-0.25, 0.0, 0.0)
	(parts["head"] as MeshInstance3D).rotation = Vector3(-0.35, 0.0, 0.0)
	(parts["arm_l"] as MeshInstance3D).rotation = Vector3(0.1, 0.0, -0.4)
	(parts["arm_r"] as MeshInstance3D).rotation = Vector3(0.0, 0.0, 0.4)
	(parts["arm_l"] as MeshInstance3D).scale = Vector3.ONE
	(parts["arm_r"] as MeshInstance3D).scale = Vector3.ONE
	var bow := parts["weapon"] as MeshInstance3D
	bow.position = Vector3(-0.5, -0.1, -0.3)
	bow.rotation = Vector3(0.0, 0.0, 1.2)
	_set_string_pull(0.0)
	(parts["arrow"] as MeshInstance3D).visible = false
