class_name BruteModel
extends MonsterModel
## Brute: the bunker owner's pet demon bouncer. A huge, hunched, dark-red horned bruiser with lava cracks
## glowing through its hide, ivory horns and tusks, a heavy gold chain, gold cuffs on its wrists and the
## shredded remains of charcoal pinstripe suit trousers. Pebble's bulk, but a villain: darker, warmer, glowing.
##
## INTEGRATION: kind "brute" -> MonsterModels.make("brute"); see the full patch at the top of
## monster_model.gd. windup(_telegraph) every frame (both fists go up overhead, the cracks flare),
## attack_swing() at the slam (fists crash down, it hunches), set_downed / set_tint / set_fade as for every
## model. brute.gd needs no change (its _pose is null-guarded; the slam ring is independent of the model).
##
## Faces local -Z, +X is its right. About 2.8 tall to the horn tips, ~2.3 across the fists (Pebble: 3.2 x
## 1.7). Rigid named parts (MeshInstance3D): body, head, horn_l, horn_r, chain, arm_l, arm_r, fist_l,
## fist_r, leg_l, leg_r. head / chain / arms hang under body; horns under head; fists under their arm;
## legs under the root.

const MODEL_SCALE := 0.90
const PART_NAMES: Array[String] = ["body", "head", "horn_l", "horn_r", "chain", "arm_l", "arm_r", "fist_l", "fist_r", "leg_l", "leg_r"]

const SKIN := Color(0.44, 0.10, 0.07)
const SKIN_LIGHT := Color(0.54, 0.15, 0.09)
const SKIN_DARK := Color(0.36, 0.08, 0.07)
const PLATE := Color(0.24, 0.07, 0.07)           ## darker horn-plate shoulders, brow, spines
const BELLY := Color(0.46, 0.15, 0.10)
const LAVA := Color(1.0, 0.30, 0.04)
const LAVA_HOT := Color(1.0, 0.55, 0.12)
const IVORY := Color(0.92, 0.86, 0.68)
const IVORY_DARK := Color(0.66, 0.58, 0.42)
const GOLD := Color(0.95, 0.74, 0.22)
const GOLD_DARK := Color(0.72, 0.52, 0.14)
const SUIT := Color(0.20, 0.18, 0.19)
const SUIT_LIGHT := Color(0.38, 0.34, 0.34)
const HOOF := Color(0.16, 0.09, 0.08)

const HIP_Y := 0.95
const BODY_Y := 1.55
const SHOULDER := Vector3(1.00, 0.38, 0.0)
const FIST_AT := Vector3(0.0, -1.10, -0.10)       ## arm-local fist centre
const LEG_X := 0.36
const CHEST := Vector3(0.80, 0.62, 0.50)          ## chest ellipsoid radii



func _init() -> void:
	_setup_model("BruteModel", MODEL_SCALE)
	monster_kind = "brute"
	glow_flare = 0.9                 # the cracks flare during the telegraph
	ui_height = 3.0 * MODEL_SCALE
	_build()
	apply_idle(0.0)


# ------------------------------------------------------------------ build

func _build() -> void:
	var body := _add_part("body", _body_soup(), self, Vector3(0, BODY_Y, 0))
	var head := _add_part("head", _head_soup(), body, Vector3(0, 0.62, -0.40))
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		_add_part("horn_" + side, _horn_soup(s), head, Vector3(0.25 * s, 0.17, 0.03))
		var arm := _add_part("arm_" + side, _arm_soup(s), body, Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z))
		arm.rotation = Vector3(0.0, 0.0, 0.2 * s)
		_add_part("fist_" + side, _fist_soup(s), arm, FIST_AT)
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(LEG_X * s, HIP_Y, 0.0))
	_add_part("chain", _chain_soup(), body, Vector3.ZERO)


## A point on the chest ellipsoid in front of (x, y) (body-local), pushed `push` outward.
static func _chest_front(x: float, y: float, push: float) -> Vector3:
	var k := 1.0 - (x / CHEST.x) * (x / CHEST.x) - (y / CHEST.y) * (y / CHEST.y)
	var z := -CHEST.z * sqrt(maxf(k, 0.04))
	return Vector3(x, y, z - push)


## A glowing crack along a polyline of points.
static func _crack(s: LowPoly.Soup, pts: Array[Vector3], r: float, seed_value: int) -> void:
	for i in pts.size() - 1:
		limb(s, pts[i], pts[i + 1], r * 1.5, r * 1.2, 4, glow(LAVA if i % 2 == 0 else LAVA_HOT), seed_value + i, 0.0, 0.0)


func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(501, 0.08)
	blob(s, Vector3.ZERO, CHEST, SKIN, 502, 0.16, 0)                                                  # chest
	blob(s, Vector3(0, -0.50, -0.04), Vector3(0.60, 0.40, 0.46), BELLY, 503, 0.16, 0)                 # belly
	blob(s, Vector3(0, -0.80, 0.0), Vector3(0.56, 0.20, 0.44), SUIT, 504, 0.1, 0)                    # waistband of the suit trousers
	blob(s, Vector3(0, 0.34, 0.30), Vector3(0.58, 0.42, 0.32), SKIN_DARK, 505, 0.16, 0)               # back hump
	for x: int in [-1, 1]:
		blob(s, Vector3(0.74 * x, 0.42, 0.0), Vector3(0.40, 0.32, 0.40), PLATE, 506 + x, 0.2, 0)      # shoulder plates
		blob(s, Vector3(0.28 * x, 0.18, -0.30), Vector3(0.30, 0.24, 0.20), SKIN_LIGHT, 508 + x, 0.2, 0)   # pecs
	for i in 4:
		var y := 0.62 - 0.13 * float(i)
		limb(s, Vector3(0, y, 0.40 + 0.05 * float(i)), Vector3(0, y + 0.26 - 0.03 * float(i), 0.62 + 0.10 * float(i)), 0.09, 0.0, 5, PLATE, 510 + i)   # spine spikes
	# lava cracks through the hide
	var c1: Array[Vector3] = [_chest_front(-0.10, 0.50, 0.03), _chest_front(0.05, 0.32, 0.03), _chest_front(-0.12, 0.14, 0.03), _chest_front(0.04, -0.06, 0.03), _chest_front(-0.04, -0.26, 0.03)]
	_crack(s, c1, 0.032, 520)
	var c2: Array[Vector3] = [_chest_front(0.05, 0.32, 0.03), _chest_front(0.30, 0.24, 0.03), _chest_front(0.46, 0.34, 0.03)]
	_crack(s, c2, 0.026, 530)
	var c3: Array[Vector3] = [_chest_front(-0.12, 0.14, 0.03), _chest_front(-0.36, 0.06, 0.03), _chest_front(-0.52, -0.08, 0.03)]
	_crack(s, c3, 0.026, 540)
	var c4: Array[Vector3] = [Vector3(-0.10, -0.2, -0.48), Vector3(0.12, -0.45, -0.52), Vector3(-0.05, -0.68, -0.40)]
	_crack(s, c4, 0.03, 550)
	var c5: Array[Vector3] = [Vector3(-0.30, 0.78, 0.42), Vector3(-0.08, 0.50, 0.62), Vector3(-0.25, 0.22, 0.60), Vector3(0.05, 0.0, 0.52)]
	_crack(s, c5, 0.034, 560)    # the back, for when it faces away
	var c6: Array[Vector3] = [Vector3(0.40, 0.70, 0.40), Vector3(0.34, 0.40, 0.58), Vector3(0.52, 0.18, 0.50)]
	_crack(s, c6, 0.03, 570)
	return s


func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(581, 0.08)
	blob(s, Vector3.ZERO, Vector3(0.36, 0.29, 0.31), SKIN_LIGHT, 582, 0.12, 1)                        # skull
	slab(s, Vector3(0, 0.12, -0.23), Vector3(0.68, 0.13, 0.22), PLATE, 583, Vector3(-16, 0, 0), 0.03)  # heavy brow
	for x: int in [-1, 1]:
		slab(s, Vector3(0.15 * x, 0.03, -0.31), Vector3(0.15, 0.065, 0.04), glow(Color(1.0, 0.92, 0.45)), 584 + x, Vector3(0, 0, 22 * x), 0.0, 0.0)   # eyes
		blob(s, Vector3(0.30 * x, -0.02, -0.12), Vector3(0.11, 0.14, 0.13), SKIN, 586 + x, 0.2)         # cheeks
	wedge(s, Vector3(0, -0.24, -0.10), Vector2(0.46, 0.34), Vector2(0.60, 0.40), 0.18, SKIN_DARK, 588, Vector3.ZERO, 0.03)   # jaw
	slab(s, Vector3(0, -0.13, -0.31), Vector3(0.34, 0.05, 0.04), glow(LAVA), 589, Vector3.ZERO, 0.0, 0.0)   # glowing mouth line
	for x: int in [-1, 1]:
		limb(s, Vector3(0.21 * x, -0.20, -0.27), Vector3(0.26 * x, 0.08, -0.40), 0.065, 0.0, 5, IVORY, 590 + x)   # tusks
	blob(s, Vector3(0, -0.02, -0.31), Vector3(0.07, 0.06, 0.05), SKIN, 592, 0.2)                      # nose
	return s


## One horn: three tapering segments sweeping out, up and forward. Origin at the root; side mirrors it.
func _horn_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(601 + side, 0.07)
	var sd := float(side)
	var p0 := Vector3(0.0, 0.0, 0.0)
	var p1 := Vector3(0.22 * sd, 0.14, -0.02)
	var p2 := Vector3(0.40 * sd, 0.40, -0.08)
	var p3 := Vector3(0.36 * sd, 0.72, -0.22)
	limb(s, p0, p1, 0.14, 0.115, 6, IVORY_DARK, 602 + side, 0.02)
	limb(s, p1, p2, 0.115, 0.085, 6, IVORY, 604 + side, 0.02)
	limb(s, p2, p3, 0.085, 0.0, 6, IVORY, 606 + side, 0.02)
	blob(s, p0, Vector3(0.17, 0.12, 0.17), PLATE, 608 + side, 0.15)                                   # base ring
	return s


## Thick gold chain hung round the neck with a heavy gold pendant.
func _chain_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(611, 0.07)
	var n := 11
	for i in n:
		var x := lerpf(-0.56, 0.56, float(i) / float(n - 1))
		var y := 0.40 - 0.48 * (1.0 - pow(absf(x) / 0.56, 2.0))
		var p := _chest_front(x, y, 0.07)
		slab(s, p, Vector3(0.13, 0.10, 0.09), GOLD if i % 2 == 0 else GOLD_DARK, 612 + i, Vector3(0, 0, 25.0 * float((i % 3) - 1)), 0.01)
	var pend := _chest_front(0.0, -0.10, 0.10)
	slab(s, pend, Vector3(0.22, 0.26, 0.08), GOLD, 630, Vector3(0, 0, 45), 0.01, 0.04)
	return s


## Shoulder to forearm: a hunk of upper arm, an elbow, a swollen forearm and a gold cuff at the wrist.
func _arm_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(641 + side, 0.08)
	limb(s, Vector3(0, -0.05, 0), Vector3(0, -0.52, -0.04), 0.31, 0.27, 6, SKIN, 642 + side, 0.02)
	blob(s, Vector3(0, -0.54, -0.05), Vector3(0.28, 0.24, 0.28), SKIN_DARK, 644 + side, 0.15)
	limb(s, Vector3(0, -0.56, -0.06), Vector3(0, -0.96, -0.10), 0.26, 0.31, 6, SKIN, 646 + side, 0.02)
	limb(s, Vector3(0, -0.95, -0.10), Vector3(0, -1.03, -0.10), 0.34, 0.34, 6, GOLD, 648 + side, 0.0)   # cuff
	var arm_crack: Array[Vector3] = [Vector3(0.20 * side, -0.62, -0.30), Vector3(0.28 * side, -0.76, -0.18), Vector3(0.22 * side, -0.88, -0.32)]
	_crack(s, arm_crack, 0.028, 650 + 3 * side)
	return s


## A huge fist: dark knuckle mass, three knuckle humps and a glowing crack across the back of the hand.
func _fist_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(661 + side, 0.08)
	blob(s, Vector3.ZERO, Vector3(0.42, 0.38, 0.42), SKIN_DARK, 662 + side, 0.15)
	for i in 3:
		blob(s, Vector3((float(i) - 1.0) * 0.22, -0.02, -0.38), Vector3(0.13, 0.12, 0.12), PLATE, 664 + i + 3 * side, 0.15)
	blob(s, Vector3(-0.30 * side, 0.08, -0.22), Vector3(0.14, 0.2, 0.14), SKIN, 670 + side, 0.15, 0, Vector3(0, 0, 25 * side))   # thumb
	var crk: Array[Vector3] = [Vector3(-0.28, 0.20, -0.22), Vector3(-0.08, 0.08, -0.38), Vector3(0.10, 0.20, -0.30), Vector3(0.30, 0.04, -0.34)]
	_crack(s, crk, 0.03, 672 + 4 * side)
	return s


## Torn pinstripe suit trouser leg over a dark red calf and a cloven hoof. Pivot at the hip.
func _leg_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(681 + side, 0.07)
	s.merge(LowPoly.frustum(Vector2(0.58, 0.54), Vector2(0.64, 0.58), 0.56, SUIT, 682 + side, 0.02, 2, Vector2.ZERO, 0.07), LowPoly.at(Vector3(0, -0.26, 0)))
	for i in 3:
		slab(s, Vector3((float(i) - 1.0) * 0.17, -0.27, -0.29), Vector3(0.025, 0.50, 0.02), SUIT_LIGHT, 684 + i, Vector3.ZERO, 0.0, 0.03)   # pinstripes
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.3
		var p := Vector3(cos(a) * 0.26, -0.52, sin(a) * 0.25)
		limb(s, p, p + Vector3(cos(a) * 0.04, -0.14 - 0.05 * float(i % 2), sin(a) * 0.04), 0.1, 0.0, 4, SUIT, 690 + i)   # shredded cuff
	s.merge(LowPoly.frustum(Vector2(0.34, 0.34), Vector2(0.42, 0.40), 0.34, SKIN_DARK, 698 + side, 0.03, 1, Vector2.ZERO, 0.08), LowPoly.at(Vector3(0, -0.66, 0)))   # calf
	blob(s, Vector3(0, -0.86, -0.06), Vector3(0.30, 0.11, 0.34), HOOF, 700 + side, 0.14)               # hoof
	blob(s, Vector3(-0.11, -0.84, -0.30), Vector3(0.11, 0.08, 0.11), HOOF, 702 + side, 0.14)           # cloven toes
	blob(s, Vector3(0.11, -0.84, -0.30), Vector3(0.11, 0.08, 0.11), HOOF, 704 + side, 0.14)
	return s


# ------------------------------------------------------------------ animation

func apply_idle(t: float, speed: float = 0.0) -> void:
	if _downed:
		return
	var walk := clampf(speed / 2.6, 0.0, 1.0)
	var breath := sin(t * 1.5)
	var stride := sin(t * 6.0)
	var w := wind_e()
	var sw := _swing
	var body := parts["body"] as MeshInstance3D
	body.position.y = BODY_Y + breath * 0.02 - absf(stride) * 0.07 * walk + 0.10 * w - 0.20 * sw
	body.scale = Vector3(1.0 + breath * 0.008, 1.0 + breath * 0.014, 1.0)
	body.rotation = Vector3(-0.10 + 0.34 * w - 0.34 * sw - 0.06 * walk, stride * 0.08 * walk, stride * 0.05 * walk)
	(parts["head"] as MeshInstance3D).rotation = Vector3(sin(t * 1.1) * 0.03 + 0.20 * w - 0.20 * sw - 0.05 * walk, 0.0, 0.0)
	(parts["leg_l"] as MeshInstance3D).rotation.x = stride * 0.45 * walk - 0.15 * sw
	(parts["leg_r"] as MeshInstance3D).rotation.x = -stride * 0.45 * walk - 0.15 * sw
	var sway := breath * 0.012
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var a := -stride * 0.28 * walk * float(s) + sway - 0.05
		a = lerpf(a, -2.75, w)          # fists up and slightly back, overhead
		a = lerpf(a, -0.70, sw)         # ... and crashing down
		(parts["arm_" + side] as MeshInstance3D).rotation = Vector3(a, 0.0, (0.20 - 0.10 * w - 0.05 * sw) * float(s))
		(parts["fist_" + side] as MeshInstance3D).rotation.x = 0.35 * w - 0.4 * sw


func _slump() -> void:
	(parts["body"] as MeshInstance3D).rotation = Vector3(-0.35, 0.0, 0.0)
	(parts["head"] as MeshInstance3D).rotation = Vector3(-0.45, 0.0, 0.0)
	(parts["arm_l"] as MeshInstance3D).rotation = Vector3(0.1, 0.0, -0.5)
	(parts["arm_r"] as MeshInstance3D).rotation = Vector3(0.1, 0.0, 0.5)
	(parts["leg_l"] as MeshInstance3D).rotation.x = 0.0
	(parts["leg_r"] as MeshInstance3D).rotation.x = 0.0
