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

## Patrol (idle life near the crew, docs/design/monster-awareness.md): walks between 2-3 points in its room, pausing at
## each to look around. Restlessness R (MonsterSenses.restlessness) speeds it up (60% -> 80% of its speed) and shortens
## the pauses (6 s -> 2.5 s); once R reaches 0.5, one skeleton in 3 adds a point in the next room through the corridor.
const PATROL_SPEED_CALM := 0.6
const PATROL_SPEED_RESTLESS := 0.8
const PAUSE_CALM := 6.0
const PAUSE_RESTLESS := 2.5
const VISITOR_AT := 0.5
const VISITOR_CHANCE := 1.0 / 3.0
const POINT_REACHED := 0.5

var _sword_arm: Node3D = null
var _route: Array[Vector3] = []
var _route_built := false
var _route_i := 0
var _pause_t := 0.0
var _visitor_rolled := false
var visitor := false              ## its patrol reaches into the next room (tests, the combat log)


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
	f.merge({
		"_sword_arm": Net.LOCAL,
		# The patrol is host AI working state.
		"_route": Net.PRIVATE, "_route_built": Net.PRIVATE, "_route_i": Net.PRIVATE, "_pause_t": Net.PRIVATE,
		"_visitor_rolled": Net.PRIVATE, "visitor": Net.PRIVATE,
	})
	return f


# --- Patrol ---------------------------------------------------------------------------------

func _idle_life(delta: float) -> bool:
	if not _route_built:
		_route_built = true
		_route = MonsterSenses.patrol_route(self, _room)
		_route_i = 1 if _route.size() > 1 else 0
		_pause_t = GameWorld.rng.randf_range(0.0, PAUSE_CALM)   # (a room's skeletons don't all set off at once)
	if _route.size() < 2:
		return false
	var r := MonsterSenses.restlessness()
	if not _visitor_rolled and r >= VISITOR_AT:
		_visitor_rolled = true
		if GameWorld.rng.randf() < VISITOR_CHANCE:
			var v := MonsterSenses.visitor_point(self, _room)
			if v != Vector3.INF:
				visitor = true
				_route.append(v)
				CombatLog.visitor(self)
	if _pause_t > 0.0:
		_pause_t -= delta
		return false   # standing at a point: the usual look-arounds
	var goal := _route[_route_i]
	if GameWorld.flat_distance(global_position, goal) <= POINT_REACHED or _stuck_n >= 3:
		_stuck_n = 0
		_route_i = (_route_i + 1) % _route.size()
		_pause_t = lerpf(PAUSE_CALM, PAUSE_RESTLESS, r)
		if _route_i == 1 and spawn_facing != Vector3.ZERO and GameWorld.flat_distance(global_position, home) <= POINT_REACHED:
			facing = spawn_facing   # back at its post: face the door again
		else:
			look_around()
		_look_t = GameWorld.rng.randf_range(LOOK_MIN, LOOK_MAX)
		return false
	_speed_k = lerpf(PATROL_SPEED_CALM, PATROL_SPEED_RESTLESS, r)
	_nav_to(goal, delta)
	_speed_k = 1.0
	return true


## Home again after a fight or a scare: the patrol starts over from its post.
func _on_home() -> void:
	_route_i = 1 if _route.size() > 1 else 0
	_pause_t = PAUSE_CALM * 0.5


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
