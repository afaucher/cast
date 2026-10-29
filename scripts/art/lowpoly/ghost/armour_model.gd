class_name ArmourModel
extends LowPolyModel
## LOOK-DEV ONLY (docs/design/ghost-look.md): a suit of armour on its stand, the haunted mansion's antique that a ghost
## possesses (new-themes.md "Ghost house"). A blockout for the ghost look test: it stands still, it is not a monster and
## nothing in the game spawns it (only GhostBody, for the gym and the look lab).
##
## The house look: a few big faceted masses (frustum plates, jittered blobs), tarnished steel in three values, one faded
## crimson accent (the plume and the tabard) and one silhouette tell (the halberd planted on the stand, taller than the
## suit). Faces local -Z, +X is its right, origin at the foot of the stand. About 2.0 tall to the plume, 2.35 to the
## halberd's spike (before MODEL_SCALE). Named rigid parts like the monsters' (body, head, arm_l, arm_r, leg_l, leg_r,
## weapon, stand), so a possessed suit could be posed later.

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
const SHOULDER := Vector3(0.33, 0.42, 0.0)  ## body space
const ARM_LEN := 0.66
const HALBERD := Vector3(0.42, STAND_H, -0.30)   ## where the halberd's butt stands on the plinth


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
		var arm := _add_part("arm_" + side, _arm_soup(s), body, Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z))
		if s < 0:
			arm.rotation = Vector3(0.08, 0.0, -0.12)
	# the right hand on the halberd's haft: the arm aimed at the grip (one piece, no elbow)
	var arm_r := parts["arm_r"] as MeshInstance3D
	var shoulder_w := Vector3(SHOULDER.x, WAIST_Y + SHOULDER.y, 0.0)
	var grip := Vector3(HALBERD.x, 0.92, HALBERD.z)
	var d := (grip - shoulder_w).normalized()
	arm_r.basis = Basis(Quaternion(Vector3.DOWN, d))
	_add_part("weapon", _halberd_soup(), self, HALBERD)


## A round wooden plinth.
func _stand_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(401, 0.05)
	s.merge(LowPoly.cylinder(0.46, 0.43, STAND_H * 0.6, 8, WOOD_DARK, 402, 0.0), LowPoly.at(Vector3(0, STAND_H * 0.3, 0)))
	s.merge(LowPoly.cylinder(0.40, 0.38, STAND_H * 0.4, 8, WOOD, 403, 0.0), LowPoly.at(Vector3(0, STAND_H * 0.8, 0)))
	return s


## The torso: faulds (a flared skirt of three lames), a belt, the breastplate with its ridge, a gorget, pauldrons and the
## faded tabard down the front.
func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(411, 0.06)
	for i in 3:
		var y := -0.05 - 0.085 * i
		MonsterModel.wedge(s, Vector3(0, y, 0.0), Vector2(0.48 + 0.05 * i, 0.32 + 0.03 * i), Vector2(0.44 + 0.05 * i, 0.29 + 0.03 * i),
				0.09, STEEL if i % 2 == 0 else TARNISH, 412 + i)
	MonsterModel.slab(s, Vector3(0, 0.02, 0.0), Vector3(0.46, 0.06, 0.30), LEATHER, 416)                 # belt
	MonsterModel.slab(s, Vector3(0, 0.02, -0.155), Vector3(0.08, 0.07, 0.03), BRASS, 417)                # buckle
	MonsterModel.wedge(s, Vector3(0, 0.27, 0.0), Vector2(0.42, 0.27), Vector2(0.58, 0.36), 0.44, STEEL, 418, Vector3.ZERO, 0.01)  # cuirass
	MonsterModel.wedge(s, Vector3(0, 0.30, -0.16), Vector2(0.05, 0.06), Vector2(0.03, 0.08), 0.40, STEEL_LIGHT, 419)              # the ridge
	MonsterModel.slab(s, Vector3(0, 0.47, -0.02), Vector3(0.60, 0.05, 0.38), BRASS, 420)                  # the cuirass's brass rim
	s.merge(LowPoly.cylinder(0.15, 0.13, 0.12, 8, STEEL_DARK, 421), LowPoly.at(Vector3(0, 0.54, 0.0)))   # gorget
	for x: float in [-1.0, 1.0]:
		MonsterModel.blob(s, Vector3(0.33 * x, 0.44, 0.0), Vector3(0.18, 0.12, 0.19), STEEL, 422 + int(x), 0.1)        # pauldron
		MonsterModel.blob(s, Vector3(0.36 * x, 0.34, 0.0), Vector3(0.15, 0.08, 0.16), TARNISH, 425 + int(x), 0.1)      # its lame
	# the tabard: a faded crimson panel from the belt to the knees, a brass-edged hem
	MonsterModel.slab(s, Vector3(0, -0.24, -0.185), Vector3(0.26, 0.42, 0.03), CRIMSON, 428, Vector3(-4.0, 0, 0))
	MonsterModel.slab(s, Vector3(0, -0.45, -0.20), Vector3(0.27, 0.04, 0.035), BRASS, 429, Vector3(-4.0, 0, 0))
	return s


## A great helm: a faceted barrel, a domed top, a dark visor slit and breaths, and a crimson plume arcing back.
func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(431, 0.06)
	s.merge(LowPoly.cylinder(0.165, 0.155, 0.30, 8, STEEL, 432, 0.006), LowPoly.at(Vector3(0, 0.15, 0)))
	s.merge(LowPoly.cylinder(0.155, 0.08, 0.08, 8, STEEL_LIGHT, 433), LowPoly.at(Vector3(0, 0.34, 0)))
	MonsterModel.slab(s, Vector3(0, 0.19, -0.155), Vector3(0.24, 0.035, 0.04), VOID, 434)                 # visor slit
	MonsterModel.slab(s, Vector3(0, 0.14, -0.16), Vector3(0.03, 0.12, 0.03), STEEL_LIGHT, 435)            # the nose ridge
	for i in 3:
		MonsterModel.slab(s, Vector3(0.07, 0.08 - 0.03 * i, -0.155), Vector3(0.05, 0.015, 0.03), VOID, 436 + i)   # breaths
	MonsterModel.slab(s, Vector3(0, 0.005, 0), Vector3(0.34, 0.03, 0.34), BRASS, 439)                      # the helm's brass band
	for i in 4:
		var t := float(i) / 3.0
		var p := Vector3(0, 0.40 + 0.06 * sin(t * PI) - 0.05 * t, 0.02 + 0.22 * t)
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


## The halberd: a dark haft from the plinth up past the helm, an axe blade to the right, a back hook and a top spike.
func _halberd_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(491, 0.05)
	MonsterModel.limb(s, Vector3(0, 0.0, 0), Vector3(0, 2.0, 0), 0.035, 0.03, 5, WOOD_DARK, 492)
	MonsterModel.slab(s, Vector3(0, 1.62, 0), Vector3(0.09, 0.05, 0.09), BRASS, 493)                  # the socket's collar
	MonsterModel.wedge(s, Vector3(0.15, 1.80, 0), Vector2(0.20, 0.03), Vector2(0.12, 0.03), 0.30, STEEL_LIGHT, 494, Vector3(0, 0, -90.0))  # the axe blade
	MonsterModel.wedge(s, Vector3(-0.09, 1.82, 0), Vector2(0.07, 0.03), Vector2(0.01, 0.02), 0.14, STEEL, 495, Vector3(0, 0, 90.0))      # the back hook
	MonsterModel.limb(s, Vector3(0, 1.96, 0), Vector3(0, 2.26, 0), 0.04, 0.0, 4, STEEL_LIGHT, 496)   # the spike
	return s
