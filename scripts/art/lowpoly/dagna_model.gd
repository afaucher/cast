class_name DagnaModel
extends LowPolyModel
## Dagna, Dwarf Pipe Warlock: a short, very wide FACETED low-poly dwarf woman with a huge ginger
## braided beard, green welding goggles pushed up on her forehead, a dark blue padded overcoat with
## cream fur trim, a leather belt and buckle, a bandaged left forearm, brown boots, and a big
## faceted pipe-wrench hammer carried upright at her right side. Built entirely in code from LowPoly
## soups (flat shaded, per-face painted colours) with the LowPolyMaterial toon + rim + outline.
##
## Faces local -Z, +X is her right. Origin is at the feet. About 1.6 units tall (the prototype hero
## is ~1.95, Pebble ~3.2) and ~1.4 wide across the shoulders and arms: stout. The head pokes up
## clear of the fur collar, the beard is a bright orange wedge down her front, the arms hang at her
## sides and the boots show under the coat, so she still reads as standing from the steep camera.
##
## Rigid named parts (all MeshInstance3D): body, head, beard, goggles, coat, belt, arm_l, arm_r,
## leg_l, leg_r, weapon. head / beard / coat / belt / arms / weapon hang under body (the weapon is
## her right fist plus the wrench, and the right sleeve re-aims at the fist every frame); goggles
## hang under head; legs under the root.
##
## Hero hooks: attack_swing() (overhead wrench smash + torso twist), cast_pose(), set_downed(),
## ui_height, has_own_weapon. Demo: spin() whirls her 360 degrees with the wrench held out.

const MODEL_SCALE := 1.0

const PART_NAMES: Array[String] = ["body", "head", "beard", "goggles", "coat", "belt", "arm_l", "arm_r", "leg_l", "leg_r", "weapon"]

# Palette (sRGB, painted).
const COAT := Color(0.20, 0.30, 0.56)          ## dark blue padded overcoat
const COAT_LIGHT := Color(0.30, 0.42, 0.72)
const COAT_DARK := Color(0.13, 0.19, 0.38)
const FUR := Color(0.94, 0.87, 0.70)           ## cream fur trim
const FUR_DARK := Color(0.80, 0.72, 0.55)
const SKIN := Color(0.93, 0.68, 0.52)
const SKIN_DARK := Color(0.82, 0.54, 0.40)
const GINGER := Color(0.95, 0.43, 0.10)
const GINGER_LIGHT := Color(1.00, 0.60, 0.20)
const GINGER_DARK := Color(0.76, 0.30, 0.07)
const LEATHER := Color(0.36, 0.22, 0.12)
const LEATHER_LIGHT := Color(0.52, 0.33, 0.17)
const BOOT := Color(0.42, 0.26, 0.14)
const BRASS := Color(0.86, 0.72, 0.30)
const LENS := Color(0.30, 0.90, 0.48)
const BANDAGE := Color(0.92, 0.88, 0.76)
const BANDAGE_DARK := Color(0.78, 0.72, 0.58)
const METAL := Color(0.62, 0.64, 0.69)         ## grey wrench head
const METAL_LIGHT := Color(0.80, 0.82, 0.86)
const METAL_DARK := Color(0.38, 0.40, 0.46)
const HANDLE := Color(0.30, 0.20, 0.14)
const DARK := Color(0.12, 0.08, 0.06)

const BODY_Y := 0.58
const HEAD_Y := 0.78
const HIP_Y := 0.48
const SHOULDER := Vector3(0.54, 0.50, 0.0)         ## body-local shoulder pivot (mirrored for the left)
const ARM_LEN := 0.62                               ## shoulder to fist
const WEAPON_REST_POS := Vector3(0.70, -0.06, -0.24)   ## body-local fist (the weapon pivot)
const WEAPON_REST_ROT := Vector3(0.0, 0.0, deg_to_rad(-7.0))   ## handle leans a little out to her right
const SPIN_OUT_POS := Vector3(0.78, 0.30, -0.30)

var _body_base_y := BODY_Y


func _init() -> void:
	_setup_model("DagnaModel", MODEL_SCALE)
	ui_height = 1.74 * MODEL_SCALE
	has_own_weapon = true
	_arm_kick = {"weapon": 0.0, "spin": 0.0}
	_build()


# ------------------------------------------------------------------ build

func _build() -> void:
	var body := _add_part("body", _body_soup(), self, Vector3(0, _body_base_y, 0))
	var head := _add_part("head", _head_soup(), body, Vector3(0, HEAD_Y, -0.04))
	_add_part("goggles", _goggles_soup(), head, Vector3(0, 0.19, 0.0))
	_add_part("beard", _beard_soup(), body, Vector3.ZERO)
	_add_part("coat", _coat_soup(), body, Vector3.ZERO)
	_add_part("belt", _belt_soup(), body, Vector3(0, 0.05, 0))
	for s in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var arm := _add_part("arm_" + side, _arm_soup(s), body, Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z))
		arm.rotation = Vector3(0.10, 0.0, deg_to_rad(10.0 * s))   # hangs at her sides, splayed clear of the belly
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(0.22 * s, HIP_Y, 0.0))
	var weapon := _add_part("weapon", _wrench_soup(), body, WEAPON_REST_POS)
	weapon.rotation = WEAPON_REST_ROT
	apply_idle(0.0)


## The coveralls torso: a wide dark-blue barrel, with a broad shoulder yoke on top.
func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.frustum(Vector2(1.00, 0.74), Vector2(1.06, 0.74), 0.44, COAT, 11, 0.03, 2, Vector2.ZERO, 0.08)
	s.merge(LowPoly.boulder(Vector3(0.56, 0.16, 0.40), 0, 0.14, COAT_LIGHT, 12, 0.08), LowPoly.at(Vector3(0, 0.44, 0.01)))   # shoulder yoke
	s.merge(LowPoly.cylinder(0.22, 0.24, 0.20, 8, SKIN_DARK, 13, 0.01), LowPoly.at(Vector3(0, 0.55, -0.02)))   # neck
	return s


## Stout head: ruddy face, a heavy brow, ginger hair, brows and moustache. Goggles are their own part.
func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.box(Vector3(0.50, 0.42, 0.44), SKIN, 21, 0.05, 2)
	s.merge(LowPoly.boulder(Vector3(0.08, 0.075, 0.085), 0, 0.2, SKIN_DARK, 22, 0.06), LowPoly.at(Vector3(0, -0.05, -0.235)))   # nose
	for x in [-1, 1]:
		s.merge(LowPoly.box(Vector3(0.075, 0.055, 0.04), DARK, 23 + x, 0.0, 1, 0.0), LowPoly.at(Vector3(0.12 * x, 0.02, -0.225)))   # eyes
		s.merge(LowPoly.box(Vector3(0.14, 0.05, 0.06), GINGER_DARK, 25 + x, 0.01, 1, 0.06), LowPoly.at(Vector3(0.12 * x, 0.085, -0.235), Vector3(0, 0, 10 * x)))   # brows
		s.merge(LowPoly.boulder(Vector3(0.075, 0.19, 0.20), 0, 0.15, GINGER_DARK, 27 + x, 0.07), LowPoly.at(Vector3(0.255 * x, -0.02, 0.0)))   # sideburns
	# hair: a thick cap, a heavy mass at the back and a small bun
	s.merge(LowPoly.boulder(Vector3(0.28, 0.12, 0.27), 0, 0.14, GINGER, 29, 0.07), LowPoly.at(Vector3(0, 0.19, 0.02)))
	s.merge(LowPoly.boulder(Vector3(0.27, 0.28, 0.13), 0, 0.14, GINGER_DARK, 30, 0.07), LowPoly.at(Vector3(0, -0.01, 0.22)))
	s.merge(LowPoly.boulder(Vector3(0.10, 0.09, 0.10), 0, 0.14, GINGER, 31, 0.07), LowPoly.at(Vector3(0, 0.27, 0.14)))
	return s


## Welding goggles pushed up on the forehead: a leather strap, two brass-rimmed green lenses.
## Local origin is the forehead (parent is the head).
func _goggles_soup() -> LowPoly.Soup:
	var s := LowPoly.box(Vector3(0.54, 0.06, 0.48), LEATHER, 41, 0.01, 2)
	for x in [-1, 1]:
		s.merge(LowPoly.cylinder(0.105, 0.105, 0.06, 8, BRASS, 42 + x, 0.008), LowPoly.at(Vector3(0.12 * x, 0.04, -0.245), Vector3(90, 0, 0)))
		s.merge(LowPoly.cylinder(0.078, 0.078, 0.07, 8, LENS, 44 + x, 0.01, 1, 0.12), LowPoly.at(Vector3(0.12 * x, 0.04, -0.255), Vector3(90, 0, 0)))
	s.merge(LowPoly.box(Vector3(0.07, 0.05, 0.05), BRASS, 46, 0.0), LowPoly.at(Vector3(0, 0.04, -0.245)))   # bridge
	return s


## The signature shape: a huge ginger wedge down her chest with two braids, brass-banded at the tips.
func _beard_soup() -> LowPoly.Soup:
	var s := LowPoly.frustum(Vector2(0.26, 0.18), Vector2(0.62, 0.32), 0.54, GINGER, 51, 0.05, 2, Vector2(0, 0.0), 0.09)
	s = s.merge(LowPoly.boulder(Vector3(0.34, 0.19, 0.17), 0, 0.14, GINGER_DARK, 52, 0.08), LowPoly.at(Vector3(0, 0.29, 0.0)))   # moustache bulk / upper beard
	for x in [-1, 1]:
		# braids: a zig-zag of chunky tilted boulders alternating light and dark so the plait reads
		for i in 5:
			var y := 0.26 - i * 0.125
			var col := GINGER_LIGHT if i % 2 == 0 else GINGER_DARK
			var w := 0.115 - i * 0.008
			var zig := 0.025 * (1 if i % 2 == 0 else -1)
			s.merge(LowPoly.boulder(Vector3(w, 0.085, w * 0.9), 0, 0.15, col, 53 + i + 5 * x, 0.08),
					LowPoly.at(Vector3(0.105 * x + zig, y, -0.15), Vector3(0, 0, (28 if i % 2 == 0 else -28))))
		s.merge(LowPoly.box(Vector3(0.10, 0.04, 0.10), BRASS, 70, 0.0), LowPoly.at(Vector3(0.105 * x, 0.26 - 5 * 0.125 + 0.03, -0.15)))
		s.merge(LowPoly.boulder(Vector3(0.06, 0.07, 0.06), 0, 0.15, GINGER, 71 + x, 0.08), LowPoly.at(Vector3(0.105 * x, 0.26 - 5 * 0.125 - 0.03, -0.15)))
	return _moved(s, Vector3(0, 0.38, -0.45))


## The overcoat: skirt flaring over the hips, cream fur hem, fat fur collar, lapel panels and pockets.
func _coat_soup() -> LowPoly.Soup:
	var s := LowPoly.frustum(Vector2(1.06, 0.78), Vector2(1.00, 0.76), 0.20, COAT_DARK, 61, 0.03, 2, Vector2.ZERO, 0.08)
	s = _moved(s, Vector3(0, -0.08, 0))   # the skirt, under the belt
	var hem := LowPoly.frustum(Vector2(1.10, 0.82), Vector2(1.08, 0.80), 0.10, FUR, 62, 0.03, 2, Vector2.ZERO, 0.07)
	s.merge(hem, LowPoly.at(Vector3(0, -0.17, 0)))
	# fat fur collar: a ring of fluffy boulders around the neck
	s.merge(LowPoly.cylinder(0.36, 0.33, 0.12, 8, FUR, 63, 0.02), LowPoly.at(Vector3(0, 0.56, -0.01)))
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		s.merge(LowPoly.boulder(Vector3(0.13, 0.09, 0.13), 0, 0.15, FUR if i % 2 == 0 else FUR_DARK, 64 + i, 0.06),
				LowPoly.at(Vector3(cos(a) * 0.36, 0.58, sin(a) * 0.30 - 0.01)))
	# lapel panels and buttons down the front, side pockets
	for x in [-1, 1]:
		s.merge(LowPoly.box(Vector3(0.11, 0.44, 0.04), COAT_LIGHT, 80 + x, 0.01, 1, 0.07), LowPoly.at(Vector3(0.27 * x, 0.30, -0.375)))
		s.merge(LowPoly.box(Vector3(0.24, 0.16, 0.06), COAT_DARK, 82 + x, 0.01, 1, 0.07), LowPoly.at(Vector3(0.40 * x, 0.12, -0.35)))
		s.merge(LowPoly.box(Vector3(0.06, 0.06, 0.05), BRASS, 84 + x, 0.0, 1, 0.0), LowPoly.at(Vector3(0.27 * x, 0.34, -0.40)))
	return s


func _belt_soup() -> LowPoly.Soup:
	var s := LowPoly.box(Vector3(1.04, 0.12, 0.78), LEATHER, 91, 0.012, 2)
	s.merge(LowPoly.box(Vector3(0.22, 0.15, 0.05), BRASS, 92, 0.006, 1, 0.04), LowPoly.at(Vector3(0, 0, -0.41)))   # buckle
	s.merge(LowPoly.box(Vector3(0.10, 0.08, 0.06), LEATHER, 93, 0.0), LowPoly.at(Vector3(0, 0, -0.42)))
	for x in [-1, 1]:   # pouches on the hips
		s.merge(LowPoly.box(Vector3(0.18, 0.2, 0.12), LEATHER_LIGHT, 94 + x, 0.012), LowPoly.at(Vector3(0.50 * x, -0.04, -0.20)))
	return s


## Short thick sleeve + shoulder pad, pivot at the shoulder. The left forearm is bandaged, the right
## ends in a fur cuff (the fist is part of the weapon).
func _arm_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.boulder(Vector3(0.19, 0.16, 0.19), 0, 0.18, COAT_LIGHT, 101 + side, 0.08)   # shoulder pad
	s.merge(LowPoly.frustum(Vector2(0.34, 0.34), Vector2(0.28, 0.28), 0.40, COAT, 103 + side, 0.03, 2, Vector2.ZERO, 0.08), LowPoly.at(Vector3(0, -0.24, 0)))
	if side < 0:
		# rolled-up sleeve, bandaged forearm, bare fist
		for i in 3:
			s.merge(LowPoly.cylinder(0.145, 0.145, 0.12, 8, BANDAGE if i % 2 == 0 else BANDAGE_DARK, 105 + i, 0.012), LowPoly.at(Vector3(0, -0.52 - i * 0.075, 0.0)))
		s.merge(LowPoly.boulder(Vector3(0.14, 0.13, 0.14), 0, 0.15, SKIN, 109, 0.06), LowPoly.at(Vector3(0, -0.76, 0)))
	else:
		s.merge(LowPoly.cylinder(0.19, 0.20, 0.16, 8, FUR, 110, 0.02), LowPoly.at(Vector3(0, -0.52, 0)))   # fur cuff
	return s


## Stubby leg: dark trouser, brown boot with a fur tuft at the top and a pushed-forward toe.
## Pivot at the hip.
func _leg_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(121, 0.07)
	s.merge(LowPoly.frustum(Vector2(0.30, 0.30), Vector2(0.28, 0.28), 0.22, COAT_DARK, 122 + side, 0.02), LowPoly.at(Vector3(0, -0.12, 0)))
	s.merge(LowPoly.cylinder(0.19, 0.20, 0.08, 8, FUR, 124, 0.02), LowPoly.at(Vector3(0, -0.25, 0)))   # fur tuft
	s.merge(LowPoly.frustum(Vector2(0.34, 0.36), Vector2(0.32, 0.32), 0.24, BOOT, 125 + side, 0.025, 2, Vector2.ZERO, 0.08), LowPoly.at(Vector3(0, -0.36, 0)))
	s.merge(LowPoly.boulder(Vector3(0.18, 0.10, 0.20), 0, 0.14, LEATHER, 127 + side, 0.08), LowPoly.at(Vector3(0, -0.38, -0.14)))   # toe cap
	return s


## The pipe-wrench hammer. Local origin is her right fist; the handle runs up local +Y, the chunky
## open-jawed head sits at the top, a knob caps the butt end. About 2.3 units long overall.
func _wrench_soup() -> LowPoly.Soup:
	var s := LowPoly.cylinder(0.060, 0.060, 1.55, 8, HANDLE, 131, 0.01, 3)
	s = _moved(s, Vector3(0, 0.375, 0))                                          # handle spans y -0.40 .. 1.15
	s.merge(LowPoly.cylinder(0.082, 0.082, 0.22, 8, LEATHER_LIGHT, 132, 0.012), LowPoly.at(Vector3(0, 0.02, 0)))          # grip wrap
	s.merge(LowPoly.cylinder(0.082, 0.082, 0.14, 8, LEATHER, 133, 0.012), LowPoly.at(Vector3(0, 0.42, 0)))
	s.merge(LowPoly.boulder(Vector3(0.12, 0.09, 0.12), 0, 0.15, METAL_DARK, 134, 0.06), LowPoly.at(Vector3(0, -0.42, 0)))   # butt knob
	# her fist wrapped round the grip
	s.merge(LowPoly.boulder(Vector3(0.15, 0.14, 0.16), 0, 0.15, SKIN, 135, 0.06), LowPoly.at(Vector3(0, 0.02, 0)))
	s.merge(LowPoly.boulder(Vector3(0.15, 0.05, 0.16), 0, 0.15, FUR, 136, 0.06), LowPoly.at(Vector3(0, -0.08, 0)))
	# the head: a heavy neck, a broad body, the fixed jaw and the hooked jaw with a gap between, an adjuster ring
	s.merge(LowPoly.frustum(Vector2(0.18, 0.22), Vector2(0.34, 0.30), 0.24, METAL_DARK, 137, 0.015, 1), LowPoly.at(Vector3(0, 1.17, 0)))
	s.merge(LowPoly.box(Vector3(0.62, 0.34, 0.34), METAL, 138, 0.02, 2, 0.07), LowPoly.at(Vector3(0, 1.43, 0)))
	s.merge(LowPoly.box(Vector3(0.24, 0.34, 0.34), METAL_LIGHT, 139, 0.02, 2, 0.07), LowPoly.at(Vector3(-0.19, 1.71, 0)))   # fixed jaw
	s.merge(LowPoly.box(Vector3(0.24, 0.24, 0.34), METAL, 140, 0.02, 2, 0.07), LowPoly.at(Vector3(0.19, 1.66, 0)))         # hook jaw
	s.merge(LowPoly.box(Vector3(0.12, 0.14, 0.34), METAL_DARK, 141, 0.01, 1, 0.07), LowPoly.at(Vector3(0.0, 1.56, 0)))     # throat of the jaw
	s.merge(LowPoly.cylinder(0.15, 0.15, 0.38, 8, METAL_DARK, 142, 0.01), LowPoly.at(Vector3(0.0, 1.27, 0), Vector3(90, 0, 0)))   # adjuster ring
	s.merge(LowPoly.cylinder(0.06, 0.06, 0.40, 6, BRASS, 143, 0.0), LowPoly.at(Vector3(0.0, 1.27, 0), Vector3(90, 0, 0)))
	return s


# ------------------------------------------------------------------ animation

## Pose the idle / walk cycle at time t: breathing, a slow head nod, stomping legs, swinging left arm,
## and the weapon: rest pose plus the swing / spin kicks, with the right sleeve aimed at the fist.
func apply_idle(t: float, speed: float = 0.0) -> void:
	var walk := clampf(speed / 4.0, 0.0, 1.0)
	var breath := sin(t * 1.9)
	var stride := sin(t * 8.0)
	var body := parts["body"] as MeshInstance3D
	body.position.y = _body_base_y + breath * 0.012 - absf(stride) * 0.04 * walk
	body.scale = Vector3(1.0 + breath * 0.006, 1.0 + breath * 0.012, 1.0)
	(parts["head"] as MeshInstance3D).rotation.x = sin(t * 1.3) * 0.02 - 0.04 * walk
	(parts["leg_l"] as MeshInstance3D).rotation.x = stride * 0.55 * walk
	(parts["leg_r"] as MeshInstance3D).rotation.x = -stride * 0.55 * walk
	(parts["arm_l"] as MeshInstance3D).rotation.x = 0.10 - stride * 0.30 * walk + breath * 0.015

	# weapon: k > 0 winds the wrench up behind her, k < 0 slams it forward; spin holds it out sideways
	var k := arm_kick("weapon")
	var out := arm_kick("spin")
	var pos := WEAPON_REST_POS + Vector3(0, 0.012 * sin(t * 1.9 + 1.0), 0)
	pos.y += 0.80 * maxf(k, 0.0) + 0.20 * maxf(-k, 0.0)
	pos.z += 0.30 * maxf(k, 0.0) + 0.55 * minf(k, 0.0)
	pos = pos.lerp(SPIN_OUT_POS, out)
	var rot := WEAPON_REST_ROT
	rot.x = k * 1.15
	rot.z = lerpf(rot.z, deg_to_rad(-92.0), out)
	var weapon := parts["weapon"] as MeshInstance3D
	weapon.position = pos
	weapon.rotation = rot
	_aim_right_arm(pos)


## Re-aim the right sleeve from the shoulder at the fist, stretching it a little so it always reaches.
func _aim_right_arm(fist: Vector3) -> void:
	var arm := parts["arm_r"] as MeshInstance3D
	var d := fist - arm.position
	var dist := d.length()
	if dist < 0.01:
		return
	arm.quaternion = Quaternion(Vector3.DOWN, d / dist)
	arm.scale = Vector3(1.0, dist / ARM_LEN, 1.0)


## Overhead wrench smash: wind the wrench up behind her head, slam it down in front, with a torso
## twist and a lean into the blow.
func attack_swing() -> void:
	if not is_inside_tree():
		return
	_kick_arm("weapon", 1.0, -1.25, 0.12, 0.08, 0.32)
	var body := parts["body"] as MeshInstance3D
	var lean := create_tween()
	lean.tween_property(body, "rotation:x", -0.10, 0.12).set_trans(Tween.TRANS_SINE)
	lean.tween_property(body, "rotation:x", 0.16, 0.08).set_trans(Tween.TRANS_SINE)
	lean.tween_property(body, "rotation:x", 0.0, 0.32).set_trans(Tween.TRANS_BACK)


## Raise the wrench for a cast (the hero's cast pose).
func cast_pose() -> void:
	if not is_inside_tree():
		return
	_kick_arm("weapon", 0.6, 0.9, 0.12, 0.10, 0.5)


## Her signature move: a full 360 degree whirl with the wrench held out. A demo for the lab.
func spin(duration: float = 0.7) -> void:
	if not is_inside_tree():
		return
	_kick_arm("spin", 1.0, 1.0, 0.10, maxf(duration - 0.25, 0.1), 0.15)
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", rotation.y + TAU, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## `s` shifted by `off` (a fresh soup carrying the same painted faces).
static func _moved(s: LowPoly.Soup, off: Vector3) -> LowPoly.Soup:
	var out := LowPoly.Soup.new(1, 0.0)
	return out.merge(s, LowPoly.at(off))


## A short wrench jab for a ranged-style action (the hero shoot pose).
func shoot_pose() -> void:
	if not is_inside_tree():
		return
	_kick_arm("weapon", 0.3, -0.7, 0.08, 0.08, 0.3)
