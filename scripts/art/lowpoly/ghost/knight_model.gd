class_name KnightModel
extends MonsterModel
## The possessed suit of armour, animated (docs/design/haunted-build-plan.md, "H5 as built"; the user, haunt-look.md: "Fine for
## now. I'll want to see it animated."). ArmourModel's knight (the same soups: big domed pauldrons, the great helm, the big
## sword in both hands, the plinth) as a monster model: kind "armour" (ArmourHost).
##   DORMANT  (awake false) the antique exactly as the priced suit stands: on its plinth, the sword point-down, both gauntlets on
##            the pommel (ArmourModel's "dormant"). Nothing moves.
##   AWAKE    a ghost wears it. Rest: the guard (a wide stance, leaning in, the sword raised point-up across the body in both
##            hands, a slow breath). The walk: a heavy march, the legs swinging from the hip (no knees: plate), the body rolling
##            over each step and leaning into it, the sword carried low at the right hip, point leading. The wind-up: the sword
##            hauled up over the right shoulder in both hands, the body leaning back and twisting. The strike: a chop down and
##            forward, a lunge onto the left foot. The war cry: the sword thrust straight up. Downed: it folds forward and drops
##            the sword. `lift` raises it onto its plinth (ArmourHost: still standing on it, or stepping off it).
##   THE WAKE (wake()): from the dormant pose to the awake one over WAKE_T (every part's transform eased between the two).
## The look is the props' while dormant (MonsterMaterial, its ink: the priced suit's); set_ghost(true) dresses it in the
## possessed look the user picked (HauntDress: the rim, the vapour body, the seep). Faces local -Z, +X its right, origin at the
## foot of the plinth. Parts: stand (the plinth), body, head, arm_l, arm_r, leg_l, leg_r, weapon.

const MODEL_SCALE := ArmourModel.MODEL_SCALE
const PART_NAMES: Array[String] = ["stand", "body", "head", "arm_l", "arm_r", "leg_l", "leg_r", "weapon"]
const WAKE_T := 1.2                 ## seconds from the dormant pose to standing awake
const STRIDE_RATE := 5.2            ## the march's stride (radians of its cycle per second)

const WAIST_Y := ArmourModel.WAIST_Y
const HIP := ArmourModel.HIP
const SHOULDER := ArmourModel.SHOULDER
const ARM_LEN := ArmourModel.ARM_LEN

var awake := true                   ## false: the dormant antique's pose
var lift := 0.0                     ## the stance's height above the floor (ArmourModel.STAND_H: on its plinth)
var phase := 0.0                    ## the ghost's pulse phase
var _wake := 1.0                    ## 0 -> 1 over WAKE_T from wake()
var _dormant := {}                  ## part name -> its dormant transform (the wake blends from it)
var _ghost := {}                    ## HauntDress pieces while possessed
var _plain: ShaderMaterial          ## its own material (the props' look)


func _init() -> void:
	_setup_model("KnightModel", MODEL_SCALE)
	monster_kind = "armour"
	ui_height = 2.0 * MODEL_SCALE
	has_own_weapon = true
	glow_flare = 0.0
	_build()
	_plain = _mat
	_pose_dormant()
	for n: String in PART_NAMES:
		_dormant[n] = (parts[n] as Node3D).transform
	apply_idle(0.0)


func _build() -> void:
	_add_part("stand", ArmourModel._stand_soup(), self, Vector3.ZERO)
	var body := _add_part("body", ArmourModel._body_soup(), self, Vector3(0, WAIST_Y, 0))
	_add_part("head", ArmourModel._head_soup(), body, Vector3(0, 0.58, 0.0))
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		_add_part("leg_" + side, ArmourModel._leg_soup(s), self, Vector3(HIP.x * s, HIP.y, HIP.z))
		_add_part("arm_" + side, ArmourModel._arm_soup(s), body, Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z))
	_add_part("weapon", ArmourModel._sword_soup(), self, ArmourModel.SWORD)


# --- states -------------------------------------------------------------------------------------------------------------

## Back to the dormant antique (no blend).
func set_dormant() -> void:
	awake = false
	_wake = 1.0
	_pose_dormant()


## A ghost takes it: from the dormant pose to awake over WAKE_T (`instant`: at once, a host possessed at spawn).
func wake(instant: bool = false) -> void:
	awake = true
	_wake = 1.0 if instant else 0.0
	apply_idle(_t, _speed)


## The wake's progress, 0..1 (1: standing awake, or dormant).
func wake_k() -> float:
	return _wake


## The possessed look on (HauntDress) or off (its own material).
func set_ghost(on: bool) -> void:
	if on and _ghost.is_empty():
		_ghost = HauntDress.dress(self, phase)
		add_to_group(GhostLook.GROUP)
		(parts["stand"] as MeshInstance3D).material_override = _plain
	elif not on and not _ghost.is_empty():
		HauntDress.undress(self, _ghost, _plain)
		_ghost = {}
		remove_from_group(GhostLook.GROUP)


func is_ghost() -> bool:
	return not _ghost.is_empty()


## GhostLook.refresh_all (the gym's strength and colour pickers).
func refresh() -> void:
	HauntDress.refresh(_ghost, phase)


func _process(delta: float) -> void:
	if _wake < 1.0 and not _downed:
		_wake = minf(1.0, _wake + delta / WAKE_T)
		if not idle_enabled:
			apply_idle(_t, _speed)
	super._process(delta)


# --- the poses ----------------------------------------------------------------------------------------------------------

func apply_idle(t: float, speed: float = 0.0) -> void:
	if _downed:
		return
	if not awake:
		_pose_dormant()
		return
	var walk := clampf(speed / 2.0, 0.0, 1.0)
	var w := wind_e()
	var sw := _swing
	var cr := cry_k()
	var mv := walk * (1.0 - clampf(w + sw, 0.0, 1.0))   # the march, giving way to a wind-up or a strike
	var g := gait_k(walk)                                  # the active walk's extras (the roll, the bounce)
	var stride := sin(t * STRIDE_RATE)
	var step := absf(cos(t * STRIDE_RATE))                 # 1 as a foot comes down
	var breath := sin(t * 1.4)
	var oy := lift - ArmourModel.STAND_H
	var body := parts["body"] as Node3D
	body.position = Vector3(stride * 0.045 * mv, WAIST_Y + oy + breath * 0.012 * (1.0 - walk) - 0.05 * mv + 0.04 * step * g - 0.07 * sw,
			0.03 * w + 0.06 * sw)
	body.rotation = Vector3(-0.10 - 0.10 * mv + 0.24 * w - 0.40 * sw + 0.14 * cr, stride * 0.13 * mv + 0.32 * w - 0.28 * sw,
			stride * 0.07 * (mv + g))
	var head := parts["head"] as Node3D
	head.rotation = Vector3(-0.14 + sin(t * 0.9) * 0.03 + 0.06 * mv - 0.10 * w + 0.12 * sw + 0.40 * cr,
			-0.22 * w + 0.18 * sw + sin(t * 0.6) * 0.05 * (1.0 - walk), -stride * 0.05 * mv)
	var leg_l := parts["leg_l"] as Node3D
	var leg_r := parts["leg_r"] as Node3D
	leg_l.position = Vector3(-HIP.x - 0.03, HIP.y + oy, -0.02)
	leg_r.position = Vector3(HIP.x + 0.03, HIP.y + oy, 0.04)
	leg_l.rotation = Vector3(0.12 * (1.0 - mv) + stride * 0.55 * mv + 0.12 * w + 0.32 * sw, 0.0, -0.07)
	leg_r.rotation = Vector3(-0.10 * (1.0 - mv) - stride * 0.55 * mv - 0.06 * w - 0.28 * sw, 0.0, 0.07)
	# The sword's grip (model space) and the way to its point: the guard, carried low on the march, hauled up over the shoulder
	# in the wind-up, chopped down and forward in the strike, thrust up in the cry.
	var grip := Vector3(0.04, 1.10 + oy + breath * 0.015, -0.50)
	var to_point := Vector3(-0.30, 0.88, -0.36)
	grip = grip.lerp(Vector3(0.30, 0.98 + oy, -0.30 - 0.10 * stride), mv)
	to_point = to_point.lerp(Vector3(0.12, -0.30, -1.0), mv)
	grip = grip.lerp(Vector3(0.14, 1.80 + oy, 0.08), w)
	to_point = to_point.lerp(Vector3(-0.12, 0.45, 0.88), w)
	grip = grip.lerp(Vector3(0.02, 0.92 + oy, -0.86), sw)
	to_point = to_point.lerp(Vector3(0.05, -0.55, -0.85), sw)
	grip = grip.lerp(Vector3(0.05, 1.98 + oy, -0.22), cr)
	to_point = to_point.lerp(Vector3(0.0, 1.0, -0.15), cr)
	var d := to_point.normalized()
	_lay_sword(grip, d)
	_reach("r", grip + d * 0.05)
	_reach("l", grip - d * 0.07)
	if _wake < 1.0:
		var k := _wake * _wake * (3.0 - 2.0 * _wake)
		for n: String in PART_NAMES:
			if n == "stand":
				continue
			var p := parts[n] as Node3D
			p.transform = (_dormant[n] as Transform3D).interpolate_with(p.transform, k)


## ArmourModel's "dormant": on the plinth, the sword point-down on it, both gauntlets on the pommel.
func _pose_dormant() -> void:
	var body := parts["body"] as Node3D
	body.position = Vector3(0, WAIST_Y, 0)
	body.rotation = Vector3.ZERO
	(parts["head"] as Node3D).rotation = Vector3.ZERO
	var leg_l := parts["leg_l"] as Node3D
	var leg_r := parts["leg_r"] as Node3D
	leg_l.position = HIP * Vector3(-1, 1, 1)
	leg_l.rotation = Vector3.ZERO
	leg_r.position = HIP
	leg_r.rotation = Vector3.ZERO
	var weapon := parts["weapon"] as Node3D
	weapon.position = ArmourModel.SWORD
	weapon.basis = Basis.IDENTITY
	for s: int in [-1, 1]:
		_reach("l" if s < 0 else "r", Vector3(ArmourModel.SWORD.x + 0.06 * s, ArmourModel.SWORD_GRIP, ArmourModel.SWORD.z))


## Downed (broken): it folds forward over its legs and the sword falls flat by it.
func _slump() -> void:
	var oy := lift - ArmourModel.STAND_H
	var body := parts["body"] as Node3D
	body.position = Vector3(0.0, WAIST_Y + oy - 0.22, -0.10)
	body.rotation = Vector3(-0.55, 0.15, 0.18)
	(parts["head"] as Node3D).rotation = Vector3(-0.45, 0.2, 0.3)
	(parts["leg_l"] as Node3D).rotation = Vector3(0.35, 0.0, -0.1)
	(parts["leg_r"] as Node3D).rotation = Vector3(-0.15, 0.0, 0.12)
	_lay_sword(Vector3(0.45, 0.06 + oy + ArmourModel.STAND_H, -0.30), Vector3(0.55, -0.02, -1.0))
	(parts["arm_l"] as Node3D).basis = Basis.IDENTITY
	(parts["arm_r"] as Node3D).basis = Basis.IDENTITY


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
	weapon.position = grip + d * ArmourModel.GRIP_FROM_POINT
