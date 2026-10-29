class_name ArmourModel
extends LowPolyModel
## LOOK-DEV ONLY (docs/design/ghost-look.md): a suit of armour on its stand, the haunted mansion's antique that a ghost
## possesses (new-themes.md "Ghost house"). A blockout for the ghost look test: it stands still, it is not a monster and
## nothing in the game spawns it (only GhostBody and HauntPiece, for the gym and the look labs). It holds one of STANCES
## (pose(): dormant, and the two possessed stances of the haunt look test, docs/design/haunt-look.md).
##
## The house look: a few big faceted masses (frustum plates, jittered blobs), tarnished steel in three values, one faded
## crimson accent (the plume and the tabard). A knight's silhouette (the user, 2026-10-29: "Knight silhouette", "Sword, not
## halberd"): big domed pauldrons, a broad chest narrowing to the waist, a tall flat-topped great helm with a clear eye
## slit, and a big sword held point-down in front, both gauntlets on its pommel. Faces local -Z, +X is its right, origin at
## the foot of the stand. About 2.1 tall to the plume (before MODEL_SCALE). Named rigid parts like the monsters' (body,
## head, arm_l, arm_r, leg_l, leg_r, weapon, stand), so a possessed suit could be posed later.

const STEEL := Color(0.46, 0.49, 0.54)
const STEEL_LIGHT := Color(0.64, 0.68, 0.72)
const STEEL_DARK := Color(0.25, 0.27, 0.32)
const TARNISH := Color(0.38, 0.38, 0.33)
const BRASS := Color(0.76, 0.60, 0.30)
const LEATHER := Color(0.30, 0.19, 0.11)
const CRIMSON := Color(0.50, 0.13, 0.13)
const CRIMSON_DARK := Color(0.32, 0.08, 0.09)
const VOID := Color(0.05, 0.04, 0.05)
const WOOD := Color(0.30, 0.18, 0.10)
const WOOD_DARK := Color(0.18, 0.10, 0.06)

const MODEL_SCALE := 1.12       ## a little over a skeleton's height: an imposing antique
const STAND_H := 0.12           ## the plinth's top
const WAIST_Y := 1.08
const HIP := Vector3(0.13, 1.06, 0.0)
const SHOULDER := Vector3(0.40, 0.42, 0.0)  ## body space
const ARM_LEN := 0.66
const SWORD := Vector3(0.0, STAND_H, -0.34)     ## where the sword's point rests on the plinth
const SWORD_GRIP := 1.08                        ## the grip's height above the stand's foot, where both hands meet
const GRIP_FROM_POINT := 0.995                  ## the sword's point to the middle of its grip

## The stances (docs/design/haunt-look.md, look-dev only): "dormant" the antique as it stands, the sword point-down on the
## plinth and both gauntlets on the pommel; two possessed ones, "guard" (still on the plinth, the sword raised point-up
## across the body in both hands, a wider stance, leaning in, the helm lowered) and "lurch" (stepped down off the plinth
## onto the floor in front of it, hunched forward, one gauntlet reaching out, the sword low in the other, point leading).
const STANCES: Array[String] = ["dormant", "guard", "lurch"]

var stance := "dormant"


func _init() -> void:
	_setup_model("ArmourModel", MODEL_SCALE)
	ui_height = 2.0 * MODEL_SCALE
	has_own_weapon = true
	idle_enabled = false
	_build()


func _build() -> void:
	_add_part("stand", _stand_soup(), self, Vector3.ZERO)
	var body := _add_part("body", _body_soup(), self, Vector3(0, WAIST_Y, 0))
	_add_part("head", _head_soup(), body, Vector3(0, 0.58, 0.0))
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(HIP.x * s, HIP.y, HIP.z))
		_add_part("arm_" + side, _arm_soup(s), body, Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z))
	_add_part("weapon", _sword_soup(), self, SWORD)
	pose(stance)


## Pose one of STANCES (an unknown one is "dormant"). Rigid parts only: the body and legs move and turn, each arm (one
## piece, no elbow) is aimed at its hand's spot and stretched a little to reach it, the sword is laid along its line.
func pose(st: String) -> void:
	stance = st if STANCES.has(st) else "dormant"
	var body := parts["body"] as Node3D
	var head := parts["head"] as Node3D
	var leg_l := parts["leg_l"] as Node3D
	var leg_r := parts["leg_r"] as Node3D
	match stance:
		"guard":
			body.position = Vector3(0.0, WAIST_Y - 0.05, 0.03)
			body.rotation = Vector3(deg_to_rad(-9.0), deg_to_rad(14.0), 0.0)
			head.rotation = Vector3(deg_to_rad(-14.0), deg_to_rad(-10.0), 0.0)
			leg_l.position = Vector3(-HIP.x - 0.03, HIP.y - 0.05, -0.06)
			leg_l.rotation = Vector3(deg_to_rad(12.0), 0.0, deg_to_rad(-9.0))
			leg_r.position = Vector3(HIP.x + 0.03, HIP.y - 0.05, 0.10)
			leg_r.rotation = Vector3(deg_to_rad(-10.0), 0.0, deg_to_rad(9.0))
			# the sword point-up across the body, leaning to its left; the grip at the belly, both hands on it
			var grip := Vector3(0.02, 1.16, -0.56)
			var up := Vector3(-0.42, 0.86, -0.30).normalized()   # from the grip toward the point
			_lay_sword(grip, up)
			_reach("r", grip - up * 0.07)
			_reach("l", grip + up * 0.05)
		"lurch":
			var off := Vector3(0.04, -STAND_H - 0.07, -0.70)   # down off the plinth, onto the floor in front of it
			body.position = Vector3(0.0, WAIST_Y, 0.0) + off + Vector3(0.0, 0.0, 0.06)
			body.rotation = Vector3(deg_to_rad(-18.0), deg_to_rad(16.0), deg_to_rad(8.0))
			head.rotation = Vector3(deg_to_rad(12.0), deg_to_rad(-18.0), deg_to_rad(-14.0))
			leg_l.position = HIP * Vector3(-1, 1, 1) + off
			leg_l.rotation = Vector3(deg_to_rad(24.0), 0.0, deg_to_rad(-4.0))
			leg_r.position = HIP + off
			leg_r.rotation = Vector3(deg_to_rad(-20.0), 0.0, deg_to_rad(5.0))
			# the left gauntlet reaching out ahead at chest height; the right holds the sword low at its side, its point
			# leading, angled down toward the floor ahead
			var sl := _shoulder(-1)
			_reach("l", sl + Vector3(0.12, 0.22, -1.0).normalized() * ARM_LEN * 1.1)
			var hand := _shoulder(1) + Vector3(0.10, -0.52, -0.22)
			_lay_sword(hand, Vector3(0.18, -0.42, -1.0))
			_reach("r", hand)
		_:
			body.position = Vector3(0, WAIST_Y, 0)
			body.rotation = Vector3.ZERO
			head.rotation = Vector3.ZERO
			leg_l.position = HIP * Vector3(-1, 1, 1)
			leg_l.rotation = Vector3.ZERO
			leg_r.position = HIP
			leg_r.rotation = Vector3.ZERO
			# both hands on the sword's pommel: each arm aimed at its side of the grip
			var weapon := parts["weapon"] as Node3D
			weapon.position = SWORD
			weapon.basis = Basis.IDENTITY
			for s: int in [-1, 1]:
				_reach("l" if s < 0 else "r", Vector3(SWORD.x + 0.06 * s, SWORD_GRIP, SWORD.z))


## A shoulder's pivot in model space (side -1 left, 1 right), where the body is now.
func _shoulder(side: int) -> Vector3:
	return (parts["body"] as Node3D).transform * Vector3(SHOULDER.x * side, SHOULDER.y, SHOULDER.z)


## Aim arm `side` ("l" / "r") so its gauntlet reaches `hand` (model space), stretched or shortened a little to meet it.
func _reach(side: String, hand: Vector3) -> void:
	var arm := parts["arm_" + side] as Node3D
	var body := parts["body"] as Node3D
	var d := body.basis.inverse() * (hand - body.transform * arm.position)
	var l := d.length()
	if l < 0.001:
		return
	arm.basis = Basis(Quaternion(Vector3.DOWN, d / l)) * Basis.from_scale(Vector3(1.0, clampf(l / (ARM_LEN - 0.03), 0.7, 1.3), 1.0))


## Lay the sword with the middle of its grip at `grip` (model space) and its blade running from there along `to_point`.
func _lay_sword(grip: Vector3, to_point: Vector3) -> void:
	var weapon := parts["weapon"] as Node3D
	var d := to_point.normalized()
	weapon.basis = Basis(Quaternion(Vector3.UP, -d))
	weapon.position = grip + d * GRIP_FROM_POINT


## A round wooden plinth.
func _stand_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(401, 0.05)
	s.merge(LowPoly.cylinder(0.46, 0.43, STAND_H * 0.6, 8, WOOD_DARK, 402, 0.0), LowPoly.at(Vector3(0, STAND_H * 0.3, 0)))
	s.merge(LowPoly.cylinder(0.40, 0.38, STAND_H * 0.4, 8, WOOD, 403, 0.0), LowPoly.at(Vector3(0, STAND_H * 0.8, 0)))
	return s


## The torso: faulds (a flared skirt of three lames), a belt at a narrow waist, a broad breastplate with its ridge, a
## gorget, big domed pauldrons with two lames each and the faded tabard down the front.
func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(411, 0.06)
	for i in 3:
		var y := -0.05 - 0.085 * i
		MonsterModel.wedge(s, Vector3(0, y, 0.0), Vector2(0.44 + 0.06 * i, 0.30 + 0.03 * i), Vector2(0.38 + 0.06 * i, 0.27 + 0.03 * i),
				0.09, STEEL if i % 2 == 0 else TARNISH, 412 + i)
	MonsterModel.slab(s, Vector3(0, 0.02, 0.0), Vector3(0.38, 0.06, 0.27), LEATHER, 416)                 # belt
	MonsterModel.slab(s, Vector3(0, 0.02, -0.14), Vector3(0.08, 0.07, 0.03), BRASS, 417)                 # buckle
	MonsterModel.wedge(s, Vector3(0, 0.27, 0.0), Vector2(0.36, 0.25), Vector2(0.70, 0.38), 0.44, STEEL, 418, Vector3.ZERO, 0.01)  # cuirass
	MonsterModel.wedge(s, Vector3(0, 0.30, -0.16), Vector2(0.05, 0.06), Vector2(0.03, 0.08), 0.40, STEEL_LIGHT, 419)              # the ridge
	MonsterModel.slab(s, Vector3(0, 0.47, -0.02), Vector3(0.50, 0.03, 0.36), BRASS, 420)                  # the cuirass's brass rim
	s.merge(LowPoly.cylinder(0.15, 0.13, 0.14, 8, STEEL_DARK, 421), LowPoly.at(Vector3(0, 0.55, 0.0)))   # gorget
	for x: float in [-1.0, 1.0]:
		MonsterModel.blob(s, Vector3(0.37 * x, 0.46, 0.0), Vector3(0.18, 0.11, 0.19), STEEL, 422 + int(x), 0.08)        # pauldron
		MonsterModel.blob(s, Vector3(0.41 * x, 0.37, 0.0), Vector3(0.16, 0.06, 0.17), TARNISH, 425 + int(x), 0.08)      # its lames
		MonsterModel.blob(s, Vector3(0.43 * x, 0.30, 0.0), Vector3(0.14, 0.05, 0.15), STEEL_DARK, 430 + int(x), 0.08)
	# the tabard: a faded crimson panel from the belt to the knees, a brass-edged hem
	MonsterModel.slab(s, Vector3(0, -0.24, -0.175), Vector3(0.26, 0.42, 0.03), CRIMSON, 428, Vector3(-4.0, 0, 0))
	MonsterModel.slab(s, Vector3(0, -0.45, -0.19), Vector3(0.27, 0.04, 0.035), BRASS, 429, Vector3(-4.0, 0, 0))
	return s


## A great helm: a tall flat-topped barrel, a dark eye slit across the front split by a brass ridge, a brass brow band,
## breaths, and a crimson plume arcing back off the flat top.
func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(431, 0.06)
	s.merge(LowPoly.cylinder(0.18, 0.17, 0.40, 8, STEEL, 432, 0.006), LowPoly.at(Vector3(0, 0.20, 0)))
	s.merge(LowPoly.cylinder(0.17, 0.14, 0.04, 8, STEEL_LIGHT, 433), LowPoly.at(Vector3(0, 0.42, 0)))   # the flat top
	MonsterModel.slab(s, Vector3(0, 0.27, -0.17), Vector3(0.32, 0.05, 0.04), VOID, 434)                  # the eye slit
	MonsterModel.slab(s, Vector3(0, 0.31, -0.175), Vector3(0.34, 0.03, 0.04), BRASS, 435)                # the brow band
	MonsterModel.slab(s, Vector3(0, 0.17, -0.18), Vector3(0.04, 0.24, 0.03), BRASS, 436)                 # the ridge
	for i in 3:
		for x: float in [-1.0, 1.0]:
			MonsterModel.slab(s, Vector3(0.07 * x, 0.18 - 0.04 * i, -0.17), Vector3(0.05, 0.016, 0.03), VOID, 437 + i)   # breaths
	MonsterModel.slab(s, Vector3(0, 0.005, 0), Vector3(0.36, 0.03, 0.36), BRASS, 439)                      # the helm's brass band
	for i in 4:
		var t := float(i) / 3.0
		var p := Vector3(0, 0.48 + 0.06 * sin(t * PI) - 0.05 * t, 0.02 + 0.22 * t)
		MonsterModel.blob(s, p, Vector3(0.06, 0.08 - 0.012 * i, 0.09), CRIMSON if i % 2 == 0 else CRIMSON_DARK, 440 + i, 0.18)
	return s


## A leg hanging from the hip: cuisse, knee cop with its fan, greave, sabaton.
func _leg_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(451 + side, 0.06)
	MonsterModel.limb(s, Vector3(0, -0.02, 0), Vector3(0, -0.42, -0.01), 0.10, 0.08, 6, STEEL, 452 + side)
	MonsterModel.blob(s, Vector3(0, -0.47, -0.03), Vector3(0.095, 0.085, 0.10), STEEL_LIGHT, 454 + side, 0.1)
	MonsterModel.wedge(s, Vector3(0.05 * side, -0.47, -0.02), Vector2(0.03, 0.12), Vector2(0.01, 0.10), 0.10, TARNISH, 456 + side, Vector3(0, 0, -60.0 * side))
	MonsterModel.limb(s, Vector3(0, -0.52, -0.02), Vector3(0, -0.86, 0.0), 0.085, 0.07, 6, STEEL, 458 + side)
	MonsterModel.slab(s, Vector3(0, -0.905, -0.06), Vector3(0.14, 0.08, 0.30), STEEL_DARK, 460 + side, Vector3(-6.0, 0, 0))
	MonsterModel.wedge(s, Vector3(0, -0.92, -0.24), Vector2(0.12, 0.06), Vector2(0.06, 0.03), 0.06, STEEL, 462 + side, Vector3(-90.0, 0, 0))
	return s


## An arm hanging from the shoulder (local -Y): rerebrace, couter, vambrace, gauntlet.
func _arm_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(471 + side, 0.06)
	MonsterModel.limb(s, Vector3(0, 0.0, 0), Vector3(0, -0.30, 0), 0.08, 0.07, 6, STEEL, 472 + side)
	MonsterModel.blob(s, Vector3(0, -0.33, 0.02), Vector3(0.085, 0.08, 0.09), STEEL_LIGHT, 474 + side, 0.12)
	MonsterModel.limb(s, Vector3(0, -0.36, 0), Vector3(0, -0.58, 0), 0.075, 0.065, 6, TARNISH, 476 + side)
	MonsterModel.blob(s, Vector3(0, -ARM_LEN + 0.03, 0), Vector3(0.085, 0.10, 0.09), STEEL_DARK, 478 + side, 0.14)
	return s


## The sword, point-down from the plinth: a broad pale blade with a dark fuller, a wide brass crossguard, a leather grip
## for both hands and a brass pommel.
func _sword_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(491, 0.05)
	var guard := SWORD_GRIP - STAND_H - 0.12
	MonsterModel.wedge(s, Vector3(0, 0.0, 0), Vector2(0.02, 0.02), Vector2(0.12, 0.03), 0.12, STEEL_LIGHT, 492)              # the point
	MonsterModel.slab(s, Vector3(0, (0.12 + guard) * 0.5, 0), Vector3(0.12, guard - 0.12, 0.03), STEEL_LIGHT, 493)       # the blade
	MonsterModel.slab(s, Vector3(0, (0.16 + guard) * 0.5, -0.017), Vector3(0.03, guard - 0.2, 0.01), STEEL_DARK, 494)     # the fuller
	MonsterModel.slab(s, Vector3(0, guard + 0.025, 0), Vector3(0.44, 0.05, 0.06), BRASS, 495)                           # the crossguard
	MonsterModel.limb(s, Vector3(0, guard + 0.05, 0), Vector3(0, guard + 0.26, 0), 0.03, 0.03, 5, LEATHER, 496)         # the grip
	MonsterModel.blob(s, Vector3(0, guard + 0.30, 0), Vector3(0.05, 0.05, 0.05), BRASS, 497, 0.1)                       # the pommel
	return s
