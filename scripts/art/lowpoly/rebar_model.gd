class_name RebarModel
extends LowPolyModel
## Rebar, Golem Utility: a hulking FACETED low-poly sandstone golem in a hi-vis vest, tool belt and
## faded jeans, with giant leather work gloves. Built entirely in code from LowPoly soups (flat
## shaded, per-face painted colours) with the LowPolyMaterial toon + amber rim + ink outline.
##
## Faces local -Z, +X is its right. Origin is at the feet. About 2.9 units tall, ~1.7 wide with
## the gloves (the prototype hero is ~1.9 tall and 0.8 wide). Kept taller than wide, with the head
## poking up above the shoulders, so he reads as standing from the steep game camera.
##
## Rigid named parts (all MeshInstance3D): body, head, vest, belt, arm_l, arm_r, glove_l, glove_r,
## leg_l, leg_r. head / vest / belt / arms hang under body; gloves under their arm; legs under root.
##
## Hero hooks (all optional on the hero side): attack_swing(), cast_pose(), set_downed(), ui_height.

## Rest pitch of the arms (radians, positive swings the hanging arm forward): puts the fists in front
## of the hips so they show from above and from the game camera.
const ARM_FWD := 0.0          ## arms hang straight down so he reads upright from the steep game camera

## The model is built at ~2.4 units; this scales it up so Rebar is ~1.35x the prototype hero.
const MODEL_SCALE := 1.1
## The CENTRED DOUBLE-FIST SLAM (the grounded_anim profile's strike, driven by HeroFeel through two kick channels):
## `slam_w` (0..1) blends both arms from their hanging pose into the slam, `slam_a` is their forward swing (rad about the
## shoulder): SLAM_UP both fists high over his head, SLAM_DOWN both fists down in front of him; the fists close together
## on his centre line as they come down (SLAM_CLASP, the arms' inward yaw at the bottom).
const SLAM_UP := 2.85
const SLAM_DOWN := 0.62
const SLAM_CLASP := 0.46
const SLAM_BEND := 0.45        ## his torso bends forward this far (rad) at the bottom of the slam ...
const SLAM_CROUCH := 0.22      ## ... and sinks this much (model units), so the fists come down to a grunt's head
## The strike-first BOWL (grounded_anim, HeroFeel's `bowl_w` / `bowl_a`): his right arm swings forward and in (BOWL_IN)
## with the slam's bend and a deeper crouch, so the glove is down at the boulder on the click's frame (BOWL_RELEASE), then
## follows through up (BOWL_FOLLOW).
const BOWL_RELEASE := 0.45
const BOWL_FOLLOW := 1.7
const BOWL_IN := 0.45
const BOWL_CROUCH := 0.34

const PART_NAMES: Array[String] = ["body", "head", "vest", "belt", "arm_l", "arm_r", "glove_l", "glove_r", "leg_l", "leg_r"]

# Palette (sRGB, painted): warm sandstone, hi-vis orange with silver tape, leather, faded denim.
const STONE := Color(0.76, 0.66, 0.49)
const STONE_LIGHT := Color(0.85, 0.76, 0.58)
const STONE_DARK := Color(0.58, 0.48, 0.36)
const VEST := Color(1.00, 0.45, 0.07)
const VEST_DARK := Color(0.90, 0.36, 0.05)
const TAPE := Color(0.84, 0.86, 0.88, 1.0)      ## alpha 1 = retro-reflective
const LEATHER := Color(0.36, 0.22, 0.12)
const LEATHER_LIGHT := Color(0.50, 0.31, 0.16)
const BRASS := Color(0.78, 0.70, 0.48)
const DENIM := Color(0.30, 0.43, 0.64)
const DENIM_LIGHT := Color(0.42, 0.55, 0.74)
const GLOVE := Color(0.62, 0.46, 0.28)
const GLOVE_DARK := Color(0.42, 0.29, 0.17)
const DARK := Color(0.12, 0.08, 0.06)


var _swing_next_right := true
var _slam_bent := false          ## the slam bent the torso last frame (it is put back upright once)
var _body_base_y := 1.55
var _head_base_y := 1.24


func _init() -> void:
	_setup_model("RebarModel", MODEL_SCALE)
	ui_height = 2.95 * MODEL_SCALE
	_arm_kick = {"arm_l": 0.0, "arm_r": 0.0, "slam_w": 0.0, "slam_a": 0.0, "bowl_w": 0.0, "bowl_a": 0.0}
	# the held spell component: gripped in the palm of his left glove (glove-local; the knuckles are at z -0.38), half
	# in the leather so it reads as held, about 0.55 across beside a 0.8 glove (it used to hang off the glove's outside)
	hold_offset = Vector3(0.0, -0.20, -0.30)
	hold_scale = 1.0
	_build()


# ------------------------------------------------------------------ build



func _build() -> void:
	var body := _add_part("body", _body_soup(), self, Vector3(0, _body_base_y, 0))
	_add_part("head", _head_soup(), body, Vector3(0, _head_base_y, -0.07))
	_add_part("vest", _vest_soup(), body, Vector3.ZERO)
	_add_part("belt", _belt_soup(), body, Vector3(0, -0.27, 0))
	for s in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var arm := _add_part("arm_" + side, _arm_soup(s), body, Vector3(0.60 * s, 0.64, 0.0))
		arm.rotation = Vector3(ARM_FWD, 0.0, deg_to_rad(10.0 * s))   # hangs down at his sides, splayed clear of the belly
		_add_part("glove_" + side, _glove_soup(s), arm, Vector3(0.10 * s, -1.22, -0.02))
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(0.23 * s, 1.2, 0.0))


## Stone torso (hidden mostly by the vest, but the belly, the traps behind the head and the chest
## edges show) plus the jeans pelvis.
func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.boulder(Vector3(0.50, 0.50, 0.31), 0, 0.16, STONE, 11, 0.11)
	s.merge(LowPoly.boulder(Vector3(0.44, 0.34, 0.31), 0, 0.14, STONE_DARK, 12, 0.11), LowPoly.at(Vector3(0, -0.28, 0)))
	# low trapezius yoke behind the neck (kept low so the head clears it)
	s.merge(LowPoly.boulder(Vector3(0.36, 0.18, 0.26), 0, 0.12, STONE_LIGHT, 13), LowPoly.at(Vector3(0, 0.46, 0.10)))
	# a short stone neck so the head pokes up above the shoulders
	s.merge(LowPoly.boulder(Vector3(0.19, 0.20, 0.19), 0, 0.12, STONE_DARK, 15), LowPoly.at(Vector3(0, 0.98, -0.04)))
	# jeans pelvis under the belt
	s.merge(LowPoly.frustum(Vector2(0.80, 0.62), Vector2(0.76, 0.60), 0.34, DENIM, 14, 0.015), LowPoly.at(Vector3(0, -0.50, 0)))
	return s


func _head_soup() -> LowPoly.Soup:
	# a small blocky head with a heavy brow, sunk between the shoulders (no neck)
	var s := LowPoly.box(Vector3(0.50, 0.44, 0.46), STONE, 21, 0.045, 2)
	s.merge(LowPoly.frustum(Vector2(0.44, 0.40), Vector2(0.50, 0.40), 0.16, STONE_DARK, 22, 0.03, 1), LowPoly.at(Vector3(0, -0.24, -0.02)))   # jaw
	# heavy brow ridge, a dark shelf over the eyes
	s.merge(LowPoly.box(Vector3(0.54, 0.11, 0.17), STONE_DARK, 23, 0.025), LowPoly.at(Vector3(0, 0.08, -0.24), Vector3(12, 0, 0)))
	s.merge(LowPoly.box(Vector3(0.14, 0.17, 0.12), STONE_LIGHT, 24, 0.02), LowPoly.at(Vector3(0, -0.04, -0.26)))   # nose
	for x in [-1, 1]:
		s.merge(LowPoly.box(Vector3(0.10, 0.065, 0.05), DARK, 25 + x, 0.0, 1, 0.0), LowPoly.at(Vector3(0.11 * x, 0.0, -0.225)))
	s.merge(LowPoly.box(Vector3(0.22, 0.035, 0.04), DARK, 27, 0.0, 1, 0.0), LowPoly.at(Vector3(0, -0.19, -0.235)))
	# a couple of chipped facets on top
	s.merge(LowPoly.boulder(Vector3(0.13, 0.07, 0.12), 0, 0.2, STONE_LIGHT, 28), LowPoly.at(Vector3(0.08, 0.22, 0.02)))
	return s


## The hi-vis vest: blocky orange shell with silver reflective tape (two vertical stripes front and
## back, a horizontal band around, tape over the shoulder straps) and a pocket.
func _vest_soup() -> LowPoly.Soup:
	var y0 := -0.12     # local to body origin (body at world y 1.25): vest from y 1.13 to 1.98
	var h := 0.85
	var wb := 0.92
	var wt := 1.08
	var d := 0.74
	var cy := y0 + h * 0.5
	var s := LowPoly.frustum(Vector2(wb, d), Vector2(wt, d), h, VEST, 31, 0.03, 2, Vector2.ZERO, 0.10)
	s.merge(LowPoly.box(Vector3(0.86, 0.07, d + 0.02), VEST_DARK, 32, 0.008), LowPoly.at(Vector3(0, y0 + 0.02, 0)))   # hem
	# two vertical tape stripes front and back, standing off the surface a little
	var half := d * 0.5 + 0.012
	for sx in [-0.22, 0.22]:
		for sz in [-1.0, 1.0]:
			s.merge(LowPoly.box(Vector3(0.12, h - 0.10, 0.03), TAPE, 33, 0.0, 1, 0.03), LowPoly.at(Vector3(sx, cy - 0.02, half * sz)))
	# horizontal band wrapping the vest, at about a third up
	var by := y0 + 0.34
	var tb := (by - y0) / h
	var bw := lerpf(wb, wt, tb) + 0.045
	s.merge(LowPoly.box(Vector3(bw, 0.09, d + 0.05), TAPE, 34, 0.0, 1, 0.03), LowPoly.at(Vector3(0, by, 0)))
	# top plate: from above the vest is one big orange field with the tape stripes running over it
	s.merge(LowPoly.box(Vector3(wt - 0.10, 0.06, d - 0.02), VEST, 39, 0.012, 2, 0.10), LowPoly.at(Vector3(0, y0 + h - 0.01, 0)))
	# shoulder straps over the tops: orange with a tape stripe running over
	for sx in [-0.22, 0.22]:
		s.merge(LowPoly.box(Vector3(0.22, 0.06, d + 0.04), VEST, 35 + int(sx * 10), 0.01), LowPoly.at(Vector3(sx, y0 + h + 0.0, 0)))
		s.merge(LowPoly.box(Vector3(0.13, 0.03, d + 0.05), TAPE, 36, 0.0, 1, 0.03), LowPoly.at(Vector3(sx, y0 + h + 0.035, 0)))
	# collar plate between the straps (what shows around the head from above)
	s.merge(LowPoly.cylinder(0.30, 0.34, 0.07, 8, VEST_DARK, 37, 0.01), LowPoly.at(Vector3(0, y0 + h + 0.0, -0.02)))
	# chest pocket
	s.merge(LowPoly.box(Vector3(0.22, 0.2, 0.05), VEST_DARK, 38, 0.01), LowPoly.at(Vector3(-0.36, y0 + 0.5, -half - 0.01)))
	return s


func _belt_soup() -> LowPoly.Soup:
	var d := 0.70
	var s := LowPoly.box(Vector3(0.88, 0.14, d), LEATHER, 41, 0.01, 2)
	s.merge(LowPoly.box(Vector3(0.20, 0.13, 0.05), BRASS, 42, 0.005, 1, 0.03), LowPoly.at(Vector3(0, 0, -d * 0.5 - 0.015)))   # buckle
	s.merge(LowPoly.box(Vector3(0.10, 0.07, 0.06), LEATHER, 43, 0.0), LowPoly.at(Vector3(0, 0, -d * 0.5 - 0.02)))
	# pouches
	for p in [[-0.33, -0.31, 0.18, 0.24], [0.35, -0.30, 0.20, 0.20], [-0.18, 0.20, 0.24, 0.22]]:
		var px: float = p[0]
		var pz: float = p[1]
		var pw: float = p[2]
		var ph: float = p[3]
		var back := pz > 0.0
		var zz := d * 0.5 + 0.06 if back else -d * 0.5 - 0.06
		if absf(px) > 0.3:
			zz = zz * 0.9
		s.merge(LowPoly.box(Vector3(pw, ph, 0.12), LEATHER_LIGHT, 44 + int(px * 20), 0.012), LowPoly.at(Vector3(px, -0.14, zz)))
		s.merge(LowPoly.box(Vector3(pw + 0.02, 0.06, 0.14), LEATHER, 45, 0.008), LowPoly.at(Vector3(px, -0.14 + ph * 0.5, zz)))   # flap
	# a wrench handle sticking out of the right pouch, a hammer loop on the left hip
	s.merge(LowPoly.box(Vector3(0.05, 0.30, 0.05), Color(0.55, 0.57, 0.6), 46, 0.0), LowPoly.at(Vector3(0.37, -0.02, -0.30), Vector3(0, 0, -14)))
	s.merge(LowPoly.box(Vector3(0.07, 0.26, 0.07), LEATHER_LIGHT, 47, 0.0), LowPoly.at(Vector3(-0.47, -0.10, 0.0)))
	return s


## Shoulder boulder + upper arm + forearm, all stone. Pivot at the shoulder.
func _arm_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.boulder(Vector3(0.33, 0.31, 0.33), 0, 0.22, STONE_LIGHT, 51 + side, 0.12)   # the shoulder
	s.merge(LowPoly.boulder(Vector3(0.27, 0.40, 0.27), 0, 0.2, STONE, 53 + side, 0.12), LowPoly.at(Vector3(0.04 * side, -0.44, 0.0)))
	s.merge(LowPoly.boulder(Vector3(0.29, 0.38, 0.29), 0, 0.2, STONE_DARK, 55 + side, 0.12), LowPoly.at(Vector3(0.07 * side, -0.86, 0.0)))
	return s


## Giant work glove: a huge tan leather mitt with a heavy cuff, a thumb and knuckle bumps.
## Local origin is the middle of the fist.
func _glove_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.boulder(Vector3(0.40, 0.44, 0.41), 0, 0.15, GLOVE, 61 + side, 0.11)
	s.merge(LowPoly.cylinder(0.26, 0.29, 0.20, 8, GLOVE_DARK, 62, 0.025), LowPoly.at(Vector3(0, 0.39, 0.0)))   # cuff
	s.merge(LowPoly.cylinder(0.29, 0.29, 0.05, 8, LEATHER, 68, 0.0), LowPoly.at(Vector3(0, 0.35, 0.0)))   # cuff strap
	s.merge(LowPoly.boulder(Vector3(0.15, 0.23, 0.15), 0, 0.15, GLOVE, 63), LowPoly.at(Vector3(-0.33 * side, 0.07, -0.17), Vector3(0, 0, 22 * side)))   # thumb
	for i in 3:
		s.merge(LowPoly.boulder(Vector3(0.12, 0.11, 0.11), 0, 0.15, GLOVE_DARK, 64 + i), LowPoly.at(Vector3((i - 1) * 0.20, -0.04, -0.38)))   # knuckles
	return s


## Stubby leg: faded jeans, a lighter turn-up cuff, chunky stone foot. Pivot at the hip.
func _leg_soup(side: int) -> LowPoly.Soup:
	var out := LowPoly.Soup.new(73, 0.07)
	out.merge(LowPoly.frustum(Vector2(0.38, 0.40), Vector2(0.33, 0.36), 0.92, DENIM, 71 + side, 0.02, 2, Vector2.ZERO, 0.08), LowPoly.at(Vector3(0, -0.48, 0)))
	out.merge(LowPoly.frustum(Vector2(0.36, 0.38), Vector2(0.34, 0.36), 0.12, DENIM_LIGHT, 72, 0.015), LowPoly.at(Vector3(0, -0.92, 0)))
	# stone foot, pushed forward so it reads from the front and overhead
	out.merge(LowPoly.boulder(Vector3(0.24, 0.15, 0.33), 0, 0.14, STONE_DARK, 74 + side, 0.1), LowPoly.at(Vector3(0.0, -1.06, -0.08)))
	return out


## A held component rides in his left glove.
func _hold_host() -> Node3D:
	return parts["glove_l"] as Node3D


# ------------------------------------------------------------------ animation

## Pose the idle / walk cycle at time t (breathing, a slow head nod, stomping legs when moving).
func apply_idle(t: float, speed: float = 0.0) -> void:
	var walk := clampf(speed / 4.5, 0.0, 1.0)
	var breath := sin(t * 1.9)
	var stride := sin(t * 7.0)
	var body := parts["body"] as MeshInstance3D
	body.position.y = _body_base_y + breath * 0.018 - absf(stride) * 0.05 * walk
	body.scale = Vector3(1.0 + breath * 0.006, 1.0 + breath * 0.012, 1.0)
	(parts["head"] as MeshInstance3D).rotation.x = sin(t * 1.3) * 0.02 - 0.04 * walk
	(parts["leg_l"] as MeshInstance3D).rotation.x = stride * 0.5 * walk
	(parts["leg_r"] as MeshInstance3D).rotation.x = -stride * 0.5 * walk
	var sway := breath * 0.015
	var w := clampf(arm_kick("slam_w"), 0.0, 1.0)
	var a := arm_kick("slam_a")
	var down := w * clampf(inverse_lerp(SLAM_UP, SLAM_DOWN, a), 0.0, 1.0)
	var clasp := SLAM_CLASP * down
	var bw := clampf(arm_kick("bowl_w"), 0.0, 1.0)   # (the strike-first bowl: his right glove down at the boulder)
	var stoop := maxf(down, bw * clampf(inverse_lerp(BOWL_FOLLOW, BOWL_RELEASE, arm_kick("bowl_a")), 0.0, 1.0))
	if w > 0.0 or bw > 0.0 or _slam_bent:
		body.rotation.x = -SLAM_BEND * stoop * stoop   # (forward: the model faces -Z)
		body.position.y -= (SLAM_CROUCH if bw <= 0.0 else BOWL_CROUCH) * stoop
		_slam_bent = w > 0.0 or bw > 0.0
	for s: int in [-1, 1]:
		var side := "arm_l" if s < 0 else "arm_r"
		var swing := ARM_FWD + s * (stride * 0.28 * walk - sway) + arm_kick(side)
		var r := Vector3(lerpf(swing, a, w), clasp * s, deg_to_rad(10.0 * s) * (1.0 - 0.6 * w))
		if s > 0 and bw > 0.0:
			r = r.lerp(Vector3(arm_kick("bowl_a"), BOWL_IN, deg_to_rad(4.0)), bw)
		(parts[side] as MeshInstance3D).rotation = r


## A quick heavy punch with alternating arms: wind back, slam forward, recover.
func attack_swing() -> void:
	if not is_inside_tree():
		return
	var key := "arm_r" if _swing_next_right else "arm_l"
	_swing_next_right = not _swing_next_right
	_kick_arm(key, -0.6, 1.55, 0.06, 0.07, 0.30)
	var body := parts["body"] as MeshInstance3D
	var lean := create_tween()
	lean.tween_property(body, "rotation:x", 0.14, 0.07).set_trans(Tween.TRANS_SINE)
	lean.tween_property(body, "rotation:x", 0.0, 0.30).set_trans(Tween.TRANS_BACK)


## Both fists up for a cast (the hero's cast pose).
func cast_pose() -> void:
	if not is_inside_tree():
		return
	_kick_arm("arm_l", 0.0, 0.9, 0.1, 0.1, 0.5)
	_kick_arm("arm_r", 0.0, 0.9, 0.1, 0.1, 0.5)




## An underhand bowling throw (the hero's bowl pose): the right arm swings back, then sweeps
## forward and low while the body leans into it.
func bowl_pose() -> void:
	if not is_inside_tree():
		return
	_kick_arm("arm_r", -1.1, 1.3, 0.14, 0.09, 0.4)
	var body := parts["body"] as MeshInstance3D
	var lean := create_tween()
	lean.tween_property(body, "rotation:x", -0.08, 0.14).set_trans(Tween.TRANS_SINE)
	lean.tween_property(body, "rotation:x", 0.22, 0.09).set_trans(Tween.TRANS_SINE)
	lean.tween_property(body, "rotation:x", 0.0, 0.4).set_trans(Tween.TRANS_BACK)
