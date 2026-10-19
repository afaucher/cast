class_name ChickenModel
extends LowPolyModel
## The Chicken spell's bird (scripts/spells/chicken.gd): a plump WHITE hen with a big red comb and wattle, an orange beak and
## orange legs, a cocked tail fan. Same faceted toon + ink look as the hero and monster models, but the hero material (it
## never glows: it is not an enemy). White and round with a red top so a flock reads as chickens at the game's zoom and is
## never mistaken for the purple, spiky imps.
##
## Faces local -Z, +X is its right, origin at the feet, about 1.0 tall to the comb (as big as an imp: a real hen would be
## half that, and unreadable at the game's zoom). Rigid named parts (MeshInstance3D):
## body, head, wing_l, wing_r, leg_l, leg_r, tail. head / wings / tail hang under body, legs under the root.
##
## Hooks (Chicken drives them every frame; idle / run animate by themselves from how fast the model moves):
##   set_peck(t)    0..1 the peck's wind-up: the head pulls back and up. Back to 0 = the peck itself: the head plunges
##                  forward and down and recovers (a short snap played by the model).
##   set_flap(on)   wings beating hard (the flap away after a peck, the scatter, a hit)
##   set_swell(k)   0..1 puffed up before it poofs
##   set_downed()   as every model (greyed, still)

const MODEL_SCALE := 1.2
const PART_NAMES: Array[String] = ["body", "head", "wing_l", "wing_r", "leg_l", "leg_r", "tail"]

const WHITE := Color(0.97, 0.96, 0.92)
const CREAM := Color(0.93, 0.89, 0.80)
const SHADE := Color(0.80, 0.78, 0.74)
const COMB := Color(0.90, 0.13, 0.12)
const COMB_DARK := Color(0.70, 0.08, 0.08)
const BEAK := Color(1.0, 0.66, 0.12)
const LEG := Color(1.0, 0.58, 0.10)
const EYE := Color(0.06, 0.04, 0.04)

const BODY_Y := 0.27
const HIP_Y := 0.27
const LEG_X := 0.075
const NECK := Vector3(0.0, 0.22, -0.13)    ## the head's pivot, on the body
const PECK_SNAP := 0.2                     ## seconds the peck's plunge takes to recover

var _peck := 0.0          ## set_peck
var _strike := 0.0        ## 1 right at the peck, easing to 0
var _flap := false
var _flap_k := 0.0
var _swell := 0.0
var _strike_tween: Tween = null


func _init() -> void:
	_setup_model("ChickenModel", MODEL_SCALE)
	ui_height = 0.85 * MODEL_SCALE
	_build()
	apply_idle(0.0)


# ------------------------------------------------------------------ build

func _build() -> void:
	var body := _add_part("body", _body_soup(), self, Vector3(0, BODY_Y, 0))
	_add_part("head", _head_soup(), body, NECK)
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		_add_part("wing_" + side, _wing_soup(s), body, Vector3(0.17 * s, 0.12, 0.02))
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(LEG_X * s, HIP_Y, 0.02))
	_add_part("tail", _tail_soup(), body, Vector3(0, 0.14, 0.19))


## A plump teardrop: round breast in front, a fuller cream belly, the back rising to the tail.
func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(901, 0.05)
	MonsterModel.blob(s, Vector3(0, 0.12, 0.02), Vector3(0.20, 0.17, 0.25), WHITE, 902, 0.1, 1)
	MonsterModel.blob(s, Vector3(0, 0.08, -0.12), Vector3(0.16, 0.15, 0.14), CREAM, 903, 0.1, 0)      # breast
	MonsterModel.blob(s, Vector3(0, 0.02, 0.06), Vector3(0.15, 0.08, 0.17), SHADE, 904, 0.1, 0)       # belly underside
	MonsterModel.blob(s, Vector3(0, 0.20, -0.10), Vector3(0.10, 0.12, 0.09), WHITE, 905, 0.1, 0)      # neck
	return s


## A small round head: the big red comb on top (three lobes), a red wattle under the beak, an orange beak, black eyes.
func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(911, 0.05)
	MonsterModel.blob(s, Vector3(0, 0.10, -0.04), Vector3(0.095, 0.10, 0.10), WHITE, 912, 0.08, 1)
	for i in 3:
		var z := -0.10 + 0.055 * float(i)
		var h := 0.075 - 0.012 * float(i)
		MonsterModel.blob(s, Vector3(0, 0.20 + h * 0.5, z), Vector3(0.032, h, 0.036), COMB if i != 1 else COMB_DARK, 913 + i, 0.12)
	MonsterModel.blob(s, Vector3(0, 0.205, -0.045), Vector3(0.03, 0.03, 0.09), COMB, 916, 0.1)       # the comb's base
	MonsterModel.limb(s, Vector3(0, 0.085, -0.12), Vector3(0, 0.06, -0.23), 0.04, 0.0, 4, BEAK, 917)   # beak
	MonsterModel.blob(s, Vector3(0, 0.01, -0.12), Vector3(0.028, 0.05, 0.03), COMB, 918, 0.12)       # wattle
	for x: int in [-1, 1]:
		MonsterModel.blob(s, Vector3(0.078 * x, 0.12, -0.09), Vector3(0.022, 0.026, 0.02), EYE, 919 + x, 0.0)
	return s


## A folded wing on the flank: a flat, slightly cupped oval, the flight feathers darker at the back.
func _wing_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(931 + side, 0.05)
	var sd := float(side)
	MonsterModel.blob(s, Vector3(0.02 * sd, -0.04, 0.02), Vector3(0.045, 0.11, 0.17), CREAM, 932 + side, 0.08, 0, Vector3(0, 0, -12 * sd))
	MonsterModel.blob(s, Vector3(0.03 * sd, -0.07, 0.13), Vector3(0.035, 0.07, 0.09), SHADE, 934 + side, 0.1, 0, Vector3(20, 0, -12 * sd))
	return s


## A thin orange leg with a three-toed foot (hangs down -Y from the hip).
func _leg_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(941 + side, 0.05)
	MonsterModel.limb(s, Vector3(0, 0.0, 0.0), Vector3(0, -0.26, 0.01), 0.026, 0.022, 4, LEG, 942 + side)
	for k in 3:
		var a := deg_to_rad(-28.0 + 28.0 * float(k))
		var toe := Vector3(sin(a) * 0.09, -0.27, -cos(a) * 0.09)
		MonsterModel.limb(s, Vector3(0, -0.26, 0.0), toe, 0.018, 0.008, 3, LEG, 944 + k + 3 * side)
	MonsterModel.limb(s, Vector3(0, -0.26, 0.0), Vector3(0, -0.27, 0.05), 0.016, 0.008, 3, LEG, 950 + side)   # hind toe
	return s


## The tail: a cocked fan of feathers rising up and back.
func _tail_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(961, 0.05)
	for k in 4:
		var x := (float(k) - 1.5) * 0.05
		var up := 0.20 + 0.03 * (1.5 - absf(float(k) - 1.5))
		MonsterModel.limb(s, Vector3(x * 0.6, 0.0, 0.0), Vector3(x, up, 0.12), 0.05, 0.02, 4, WHITE if k % 2 == 0 else CREAM, 962 + k)
	MonsterModel.blob(s, Vector3(0, 0.04, 0.03), Vector3(0.09, 0.08, 0.07), WHITE, 967, 0.1)
	return s


# ------------------------------------------------------------------ hooks

## The peck's wind-up, 0..1 (0 = no peck coming). Dropping back to 0 from a wind-up IS the peck: the head plunges.
func set_peck(t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	if _peck > 0.5 and t <= 0.001:
		peck_strike()
	_peck = t


## The peck itself: the head snaps forward and down, then recovers.
func peck_strike() -> void:
	if _strike_tween != null and _strike_tween.is_valid():
		_strike_tween.kill()
	_strike = 1.0
	if not is_inside_tree():
		return
	_strike_tween = create_tween()
	_strike_tween.tween_method(func(v: float) -> void: _strike = v, 1.0, 0.0, PECK_SNAP).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func set_flap(on: bool) -> void:
	_flap = on


## Puffed up before the poof, 0..1.
func set_swell(k: float) -> void:
	_swell = clampf(k, 0.0, 1.0)
	scale = Vector3.ONE * MODEL_SCALE * (1.0 + 0.45 * _swell)


## Frozen pose for the lab / screenshots: "rest", "run", "windup" (the head back), "peck" (the plunge) or "flap".
func pose_preview(kind: String, k: float = 1.0) -> void:
	idle_enabled = false
	_peck = k if kind == "windup" else 0.0
	_strike = k if kind == "peck" else 0.0
	_flap = kind == "flap"
	_flap_k = 1.0 if _flap else 0.0
	apply_idle(0.35, 4.0 if kind == "run" or kind == "flap" else 0.0)


# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	_flap_k = move_toward(_flap_k, 1.0 if _flap else 0.0, delta * 8.0)
	super._process(delta)


func apply_idle(t: float, speed: float = 0.0) -> void:
	var run := clampf(speed / 4.0, 0.0, 1.0)
	var stride := sin(t * 24.0)
	var w := _peck * _peck * (3.0 - 2.0 * _peck)
	var sw := _strike
	var body := parts["body"] as MeshInstance3D
	# Run: a bouncy, forward-leaning trot. Peck: the body tips in after the head.
	body.position = Vector3(0.0, BODY_Y + absf(stride) * 0.05 * run + sin(t * 3.0) * 0.006, 0.0)
	body.rotation = Vector3(-0.22 * run - 0.35 * sw + 0.12 * w, stride * 0.08 * run, sin(t * 24.0) * 0.06 * run)
	# Head: a chicken's head jerks from pose to pose (stepped look-arounds at rest, a bob at a run); the peck pulls it
	# back and up, then plunges it forward and down.
	var head := parts["head"] as MeshInstance3D
	var look := sin(floorf(t * 2.2) * 2.7) * 0.6 * (1.0 - run)
	var bob := sin(t * 12.0) * 0.03 * run
	head.position = NECK + Vector3(0.0, 0.035 * w - 0.03 * sw, bob + 0.06 * w - 0.08 * sw)
	head.rotation = Vector3(0.45 * w - 0.85 * sw + sin(t * 1.7) * 0.05, look * (1.0 - w), 0.0)
	# Legs.
	(parts["leg_l"] as MeshInstance3D).rotation.x = stride * 0.9 * run
	(parts["leg_r"] as MeshInstance3D).rotation.x = -stride * 0.9 * run
	# Wings: tucked, a nervous twitch at a run, beating hard while flapping.
	var beat := absf(sin(t * 34.0))
	var open := lerpf(0.12 * run * absf(sin(t * 12.0)), 0.55 + 1.25 * beat, _flap_k)
	(parts["wing_l"] as MeshInstance3D).rotation = Vector3(0.0, 0.0, -open)
	(parts["wing_r"] as MeshInstance3D).rotation = Vector3(0.0, 0.0, open)
	(parts["tail"] as MeshInstance3D).rotation = Vector3(-0.15 * run + 0.25 * sw, sin(t * 5.0) * 0.12, 0.0)


func set_downed(downed: bool) -> void:
	super.set_downed(downed)
	if downed:
		_flap = false
		_flap_k = 0.0
		_strike = 0.0
		_peck = 0.0
