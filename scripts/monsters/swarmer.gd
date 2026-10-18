extends Monster
## Swarmer: a fast, fragile spiky imp that comes in packs. Instead of stacking
## on the hero it closes in, darts in for a bite when off cooldown, and circles
## (each imp picks its own direction) while the bite recharges.

const HP := 12.0
const SPEED := 5.5
const DAMAGE := 4.0
const WINDUP := 0.15
const COOLDOWN := 0.6
const AGGRO := 9.0
const REACH := 0.7
const START_RANGE := 1.0
const FLANK_RANGE := 2.8       ## inside this (with line of sight) it darts/circles instead of pathing
const ORBIT_DIST := 1.5        ## preferred circling distance while the bite recharges

var _side := 1.0
var _los_t := 0.0
var _los_ok := false


func _init() -> void:
	super._init()
	kind = "swarmer"
	display_name = "Swarmer"
	max_hp = HP
	move_speed = SPEED
	radius = 0.26
	shove_mult = 1.5
	aggro_range = AGGRO
	attack_damage = DAMAGE
	attack_windup = WINDUP
	attack_cooldown = COOLDOWN
	attack_reach = REACH
	attack_start_range = START_RANGE
	attack_arc_deg = 160.0
	stop_distance = 0.6
	bar_height = 0.95
	bar_width = 0.5
	walk_bob = 0.14
	walk_freq = 16.0
	windup_scale = 0.3
	model_windup_scale = 0.12


func _ready() -> void:
	super._ready()
	_side = 1.0 if GameWorld.rng.randf() < 0.5 else -1.0


## Who may write each var (see Net); Monster's come from super(). The circling side and the
## LOS check are host-side AI choices that nobody else needs.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({"_side": Net.PRIVATE, "_los_t": Net.PRIVATE, "_los_ok": Net.PRIVATE})
	return f


func _build_visual(root: Node3D) -> void:
	var body := _mat(Color(0.5, 0.2, 0.7))
	var spike := _mat(Color(0.3, 0.08, 0.42))
	var eye := _mat(Color(1.0, 0.9, 0.2), 3.0)
	_sphere(root, 0.28, Vector3(0.0, 0.32, 0.0), body)
	# Spikes spread over the upper hemisphere (fibonacci spiral).
	var n := 11
	for i in n:
		var y := lerpf(1.0, -0.15, (float(i) + 0.5) / float(n))
		var ring_r := sqrt(maxf(0.0, 1.0 - y * y))
		var a := float(i) * 2.399963
		var dir := Vector3(cos(a) * ring_r, y, sin(a) * ring_r)
		var mi := _cone(root, 0.06, 0.24, Vector3(0.0, 0.32, 0.0) + dir * 0.35, spike)
		mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), Vector3(0.0, 0.32, 0.0) + dir * 0.36)
	_sphere(root, 0.055, Vector3(-0.1, 0.38, -0.24), eye)
	_sphere(root, 0.055, Vector3(0.1, 0.38, -0.24), eye)


func _chase_move(delta: float, dist: float) -> void:
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = 0.3
		_los_ok = dist < FLANK_RANGE and _can_strike_target()
	var tp := target_point()
	if dist > FLANK_RANGE or not _los_ok:
		_nav_to(tp, delta)
		return
	var to := tp - global_position
	to.y = 0.0
	var fwd := to.normalized()
	var side := Vector3(-fwd.z, 0.0, fwd.x) * _side
	var dir: Vector3
	if GameWorld.time >= _next_attack_time:
		dir = (fwd + side * 0.4).normalized()       # dart in on a curve
	else:
		# Recharging: circle the hero at roughly ORBIT_DIST.
		var radial := clampf((dist - ORBIT_DIST) * 0.8, -0.7, 0.7)
		dir = (side + fwd * radial).normalized()
	if not move(dir, delta):
		_nav_to(tp, delta)
	else:
		_prog_t = 0.0
		face_point(tp)   # keep biting end toward the hero while circling
