class_name SwarmerModel
extends MonsterModel
## Swarmer: a small, fast, grinning imp. Bright orchid-purple pot-bellied body, pale spikes down its back,
## big bat ears, little horns, huge glowing yellow eyes and a glowing jagged grin, a spade-tipped tail.
## Kept bright and spiky so a pack of them pops against the dark floor and reads as "many small threats".
##
## INTEGRATION: kind "swarmer" -> MonsterModels.make("swarmer"); see the full patch at the top of
## monster_model.gd. windup(_telegraph) every frame (it coils into a crouch), attack_swing() at the bite
## (it lunges), set_downed / set_tint / set_fade as for every model. swarmer.gd needs no change. With a
## model, windup_scale 0.3 (a 30% swell) is too much on top of the crouch: use about 0.12.
##
## Faces local -Z, +X is its right. About 0.95 tall to the horn tips, ~0.8 wide with the ears.
## Rigid named parts (MeshInstance3D): body, head, ear_l, ear_r, arm_l, arm_r, leg_l, leg_r, tail.
## head / arms / tail hang under body, ears under head, legs under the root.

const MODEL_SCALE := 0.88
const PART_NAMES: Array[String] = ["body", "head", "ear_l", "ear_r", "arm_l", "arm_r", "leg_l", "leg_r", "tail"]

const VIOLET := Color(0.52, 0.22, 0.78)
const VIOLET_LIGHT := Color(0.64, 0.32, 0.90)
const VIOLET_DARK := Color(0.34, 0.13, 0.56)
const BELLY := Color(0.82, 0.52, 0.94)
const SPIKE := Color(0.96, 0.88, 1.0)
const CLAW := Color(0.98, 0.94, 0.82)
const VOID := Color(0.10, 0.04, 0.14)
const EYE := Color(1.0, 0.90, 0.18)
const MOUTH := Color(1.0, 0.45, 0.12)

const BODY_Y := 0.32
const LEG_X := 0.12
const HEAD_AT := Vector3(0.0, 0.46, -0.05)


func _init() -> void:
	_setup_model("SwarmerModel", MODEL_SCALE)
	monster_kind = "swarmer"
	ui_height = 1.05 * MODEL_SCALE
	_build()
	apply_idle(0.0)


# ------------------------------------------------------------------ build

func _build() -> void:
	var body := _add_part("body", _body_soup(), self, Vector3(0, BODY_Y, 0))
	var head := _add_part("head", _head_soup(), body, HEAD_AT)
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		_add_part("ear_" + side, _ear_soup(s), head, Vector3(0.22 * s, 0.05, 0.03))
		_add_part("arm_" + side, _arm_soup(s), body, Vector3(0.23 * s, 0.26, -0.05))
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(LEG_X * s, BODY_Y, 0.0))
	_add_part("tail", _tail_soup(), body, Vector3(0, 0.04, 0.18))


## Pot belly with a pale plate, a lumpy back and a row of pale spikes down the spine.
func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(701, 0.08)
	blob(s, Vector3(0, 0.15, 0.0), Vector3(0.25, 0.25, 0.23), VIOLET, 702, 0.15, 0)
	blob(s, Vector3(0, 0.12, -0.15), Vector3(0.17, 0.19, 0.10), BELLY, 703, 0.15, 0)                  # belly plate
	blob(s, Vector3(0, 0.32, 0.06), Vector3(0.19, 0.11, 0.16), VIOLET_LIGHT, 704, 0.15, 0)            # shoulders
	limb(s, Vector3(0, 0.34, 0.14), Vector3(0, 0.54, 0.30), 0.07, 0.0, 5, SPIKE, 705)                 # back spikes
	limb(s, Vector3(0, 0.22, 0.20), Vector3(0, 0.34, 0.42), 0.065, 0.0, 5, SPIKE, 706)
	limb(s, Vector3(0, 0.42, 0.04), Vector3(0, 0.60, 0.10), 0.06, 0.0, 5, SPIKE, 707)
	for x: int in [-1, 1]:
		limb(s, Vector3(0.17 * x, 0.30, 0.10), Vector3(0.30 * x, 0.46, 0.22), 0.05, 0.0, 5, SPIKE, 708 + x)   # shoulder spikes
	return s


## Big round head: huge glowing eyes, a wide glowing grin full of teeth, two little horns.
func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(711, 0.08)
	blob(s, Vector3.ZERO, Vector3(0.27, 0.22, 0.23), VIOLET_LIGHT, 712, 0.1, 1)
	for x: int in [-1, 1]:
		slab(s, Vector3(0.10 * x, 0.05, -0.215), Vector3(0.14, 0.07, 0.04), glow(EYE), 713 + x, Vector3(0, 0, 32 * x), 0.0, 0.0)     # eyes
		limb(s, Vector3(0.13 * x, 0.15, 0.0), Vector3(0.21 * x, 0.38, -0.03), 0.065, 0.0, 5, SPIKE, 715 + x)                          # horns
	slab(s, Vector3(0, -0.095, -0.215), Vector3(0.34, 0.09, 0.04), glow(MOUTH), 717, Vector3.ZERO, 0.0, 0.0)                        # grin
	for i in 5:
		var x := -0.12 + 0.06 * float(i)
		limb(s, Vector3(x, -0.05, -0.235), Vector3(x, -0.12, -0.235), 0.03, 0.0, 4, CLAW, 718 + i, 0.0, 0.03)                           # teeth
	blob(s, Vector3(0, -0.02, -0.22), Vector3(0.05, 0.04, 0.04), VIOLET_DARK, 724, 0.2)                                                # nose
	return s


## A flared bat ear: a flat leaf pointing out and up.
func _ear_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(731 + side, 0.07)
	var sd := float(side)
	limb(s, Vector3(0, 0, 0), Vector3(0.36 * sd, 0.20, 0.06), 0.12, 0.0, 4, VIOLET_DARK, 732 + side, 0.0)
	limb(s, Vector3(0.02 * sd, 0.0, -0.02), Vector3(0.26 * sd, 0.14, 0.03), 0.06, 0.0, 4, BELLY, 734 + side, 0.0)
	return s


## Stubby arm with a clawed hand, hanging from the shoulder (rest pose raises it).
func _arm_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(741 + side, 0.07)
	limb(s, Vector3(0, 0, 0), Vector3(0, -0.26, -0.02), 0.075, 0.065, 5, VIOLET, 742 + side)
	blob(s, Vector3(0, -0.30, -0.03), Vector3(0.085, 0.085, 0.085), VIOLET_LIGHT, 744 + side, 0.15)
	for i in 3:
		var x := (float(i) - 1.0) * 0.045
		limb(s, Vector3(x, -0.34, -0.04), Vector3(x * 1.4, -0.46, -0.07), 0.03, 0.0, 4, CLAW, 746 + i + 3 * side, 0.0, 0.03)
	return s


func _leg_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(761 + side, 0.07)
	limb(s, Vector3(0, 0, 0), Vector3(0, -0.20, -0.02), 0.095, 0.075, 5, VIOLET_DARK, 762 + side)
	blob(s, Vector3(0, -0.25, -0.07), Vector3(0.10, 0.055, 0.14), VIOLET, 764 + side, 0.14)
	for i in 2:
		var x := (float(i) - 0.5) * 0.08
		limb(s, Vector3(x, -0.25, -0.17), Vector3(x, -0.27, -0.26), 0.03, 0.0, 4, CLAW, 766 + i + 2 * side, 0.0, 0.03)
	return s


## A curling tail with a spade tip; pivots where it leaves the body.
func _tail_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(771, 0.07)
	limb(s, Vector3(0, 0.0, 0.0), Vector3(0, -0.03, 0.18), 0.06, 0.05, 5, VIOLET, 772)
	limb(s, Vector3(0, -0.03, 0.18), Vector3(0, 0.07, 0.34), 0.05, 0.04, 5, VIOLET, 773)
	limb(s, Vector3(0, 0.07, 0.34), Vector3(0, 0.22, 0.40), 0.04, 0.03, 5, VIOLET_DARK, 774)
	blob(s, Vector3(0, 0.27, 0.40), Vector3(0.09, 0.10, 0.035), SPIKE, 775, 0.15, 0, Vector3(0, 0, 45))   # spade
	return s


# ------------------------------------------------------------------ animation

## The walk (active walk, MonsterModel.gait_k): a scurry. Low and pitched forward, bouncing off every footfall, its pot
## belly wobbling side to side at half the step, the head bobbing and darting, the arms pumping and the tail whipping.
## The war cry (cry_k): a little hop with both arms flung up, the ears up and the head back.
func apply_idle(t: float, speed: float = 0.0) -> void:
	if _downed:
		return
	var walk := clampf(speed / 5.0, 0.0, 1.0)
	var g := gait_k(walk)
	var cr := cry_k()
	var breath := sin(t * 3.2)
	var stride := sin(t * 19.0)
	var wob := sin(t * 9.5)                       # the belly's waddle, one per two steps
	var w := wind_e()
	var sw := _swing
	var body := parts["body"] as MeshInstance3D
	body.position = Vector3(wob * 0.035 * g, BODY_Y + breath * 0.012 + absf(stride) * 0.07 * walk - 0.11 * w + 0.03 * sw
			- 0.07 * g + absf(stride) * 0.06 * g + 0.10 * cr, -0.14 * sw)
	body.rotation = Vector3(0.40 * w - 0.65 * sw - 0.15 * walk - 0.22 * g + 0.25 * cr, stride * 0.12 * walk + wob * 0.10 * g,
			sin(t * 2.3) * 0.03 + wob * 0.16 * g)
	(parts["head"] as MeshInstance3D).rotation = Vector3(-0.30 * w + 0.15 * sw + sin(t * 2.0) * 0.04 + 0.22 * g + absf(stride) * 0.10 * g + 0.45 * cr,
			sin(t * 1.6) * 0.12 * (1.0 - w) + sin(t * 7.0) * 0.12 * g, -wob * 0.12 * g)
	(parts["leg_l"] as MeshInstance3D).rotation.x = stride * (0.95 * walk + 0.15 * g) - 0.55 * w + 0.5 * sw - 0.25 * g
	(parts["leg_r"] as MeshInstance3D).rotation.x = -stride * (0.95 * walk + 0.15 * g) - 0.55 * w + 0.5 * sw - 0.25 * g
	var flap := sin(t * 5.0) * 0.12 + stride * (0.15 * walk + 0.15 * g)
	(parts["ear_l"] as MeshInstance3D).rotation = Vector3(0.0, 0.0, flap - 0.25 * w + 0.20 * g - 0.45 * cr)
	(parts["ear_r"] as MeshInstance3D).rotation = Vector3(0.0, 0.0, -flap + 0.25 * w - 0.20 * g + 0.45 * cr)
	# arms: clawing forward and out; spread wide when coiled; thrust forward on the bite
	var claw := sin(t * 4.0) * 0.12
	var a := -0.85 + claw + stride * 0.5 * walk
	a = lerpf(a, 0.35, w)
	a = lerpf(a, -1.85, sw)
	var pump := stride * (1.0 * walk + 0.35 * g)
	var al := a if walk < 0.01 else a - pump
	var ar := a if walk < 0.01 else a + pump
	(parts["arm_l"] as MeshInstance3D).rotation = Vector3(lerpf(al, -2.7, cr), 0.0, -0.45 - 0.55 * w - 0.45 * cr)
	(parts["arm_r"] as MeshInstance3D).rotation = Vector3(lerpf(ar, -2.7, cr), 0.0, 0.45 + 0.55 * w + 0.45 * cr)
	(parts["tail"] as MeshInstance3D).rotation = Vector3(0.25 * w + 0.25 * cr, sin(t * 4.5) * 0.35 + stride * (0.3 * walk + 0.25 * g) + wob * 0.3 * g, 0.0)


func _slump() -> void:
	(parts["body"] as MeshInstance3D).rotation = Vector3(-0.3, 0.0, 0.0)
	(parts["head"] as MeshInstance3D).rotation = Vector3(-0.4, 0.0, 0.0)
	(parts["arm_l"] as MeshInstance3D).rotation = Vector3(0.1, 0.0, -0.6)
	(parts["arm_r"] as MeshInstance3D).rotation = Vector3(0.1, 0.0, 0.6)
	(parts["ear_l"] as MeshInstance3D).rotation = Vector3(0.0, 0.0, -0.5)
	(parts["ear_r"] as MeshInstance3D).rotation = Vector3(0.0, 0.0, 0.5)
	(parts["leg_l"] as MeshInstance3D).rotation.x = 0.0
	(parts["leg_r"] as MeshInstance3D).rotation.x = 0.0
