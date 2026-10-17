extends Monster
## Skeleton warrior: the bread-and-butter melee monster. Chases, raises its
## sword (visible windup + orange pulse), then cleaves a cone in front of it.

const HP := 40.0
const SPEED := 3.2
const DAMAGE := 10.0
const WINDUP := 0.35
const COOLDOWN := 1.1
const AGGRO := 8.0
const REACH := 1.4            ## strike reach (the target's radius is added on top)
const START_RANGE := 1.5      ## windup starts at this center distance
const ARC_DEG := 120.0

var _sword_arm: Node3D = null


func _init() -> void:
	super._init()
	kind = "grunt"
	display_name = "Skeleton"
	max_hp = HP
	move_speed = SPEED
	radius = 0.38
	aggro_range = AGGRO
	attack_damage = DAMAGE
	attack_windup = WINDUP
	attack_cooldown = COOLDOWN
	attack_reach = REACH
	attack_start_range = START_RANGE
	attack_arc_deg = ARC_DEG
	stop_distance = 1.0
	bar_height = 1.85
	bar_width = 0.8


## Who may write each var (see Net); Monster's come from super().
func net_fields() -> Dictionary:
	var f := super()
	f.merge({"_sword_arm": Net.LOCAL})
	return f


func _build_visual(root: Node3D) -> void:
	var bone := _mat(Color(0.88, 0.85, 0.74))
	var dark := _mat(Color(0.2, 0.17, 0.15))
	var eye := _mat(Color(1.0, 0.08, 0.04), 3.0)
	var steel := _mat(Color(0.62, 0.68, 0.74))
	var grip := _mat(Color(0.35, 0.2, 0.1))
	# Legs + pelvis
	_box(root, Vector3(0.1, 0.55, 0.1), Vector3(-0.11, 0.28, 0.0), bone)
	_box(root, Vector3(0.1, 0.55, 0.1), Vector3(0.11, 0.28, 0.0), bone)
	_box(root, Vector3(0.34, 0.14, 0.2), Vector3(0.0, 0.62, 0.0), bone)
	# Ribcage
	_box(root, Vector3(0.38, 0.46, 0.22), Vector3(0.0, 0.95, 0.0), bone)
	for y in [0.84, 0.94, 1.04]:
		_box(root, Vector3(0.4, 0.035, 0.24), Vector3(0.0, y, 0.0), dark)
	# Skull
	_sphere(root, 0.18, Vector3(0.0, 1.33, 0.0), bone, Vector3(1.0, 1.0, 1.1))
	_box(root, Vector3(0.15, 0.06, 0.14), Vector3(0.0, 1.17, -0.04), bone)
	_sphere(root, 0.04, Vector3(-0.07, 1.36, -0.17), eye)
	_sphere(root, 0.04, Vector3(0.07, 1.36, -0.17), eye)
	# Left arm (hangs)
	_box(root, Vector3(0.08, 0.46, 0.08), Vector3(-0.27, 0.93, 0.0), bone, Vector3(0, 0, 8))
	# Sword arm: pivot at the shoulder so the windup can swing it overhead.
	_sword_arm = _pivot(root, Vector3(0.27, 1.12, 0.0))
	_box(_sword_arm, Vector3(0.08, 0.46, 0.08), Vector3(0.0, -0.23, 0.0), bone)
	_box(_sword_arm, Vector3(0.1, 0.1, 0.1), Vector3(0.0, -0.48, 0.0), grip)
	_box(_sword_arm, Vector3(0.2, 0.04, 0.05), Vector3(0.0, -0.53, 0.0), grip)
	_box(_sword_arm, Vector3(0.07, 0.6, 0.025), Vector3(0.0, -0.84, 0.0), steel)


func _pose(_delta: float, _moving: bool) -> void:
	if _sword_arm != null:
		_sword_arm.rotation.x = -2.9 * _telegraph + 1.4 * _strike_t
