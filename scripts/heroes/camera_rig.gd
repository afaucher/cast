class_name CameraRig
extends Node3D
## Orthographic isometric camera: yaw 45 deg, pitch -55 deg, smooth follow of
## `target`, mouse-wheel zoom, and a little screen shake (Fx.shake).

const YAW_DEG := 45.0
const PITCH_DEG := -56.0   ## lower than straight-down so characters read upright; walls still hide little
const DISTANCE := 60.0
const SIZE_DEFAULT := 24.0
const SIZE_MIN := 10.0
const SIZE_MAX := 36.0
const ZOOM_FACTOR := 1.1
const FOLLOW_RATE := 7.0
const FOCUS_HEIGHT := 0.8
const SHAKE_DECAY := 2.2
const SHAKE_MAX_OFFSET := 0.5

var target: Node3D = null
## The aim point (a Callable returning a world Vector3), for a movement feel's camera lead toward the aim; unset = none.
var aim_source: Callable = Callable()
var right_inset_px := 0.0   ## screen pixels covered on the right (debug panel); keeps the target centered in the rest
var camera: Camera3D
var _trauma := 0.0
var _zoom_target := SIZE_DEFAULT
var _lead_vel := Vector3.ZERO     ## the target's velocity, smoothed over MoveFeel "cam_lead_time" (the lead)
var _lead_last := Vector3.INF
var lead := Vector3.ZERO          ## the offset the camera leads by right now (tests)


func _ready() -> void:
	add_to_group("camera_rig")
	rotation_degrees.y = YAW_DEG
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = SIZE_DEFAULT
	camera.near = 0.1
	camera.far = 220.0
	var pitch := deg_to_rad(-PITCH_DEG)
	camera.position = Vector3(0, DISTANCE * sin(pitch), DISTANCE * cos(pitch))
	camera.rotation_degrees.x = PITCH_DEG
	add_child(camera)
	camera.make_current()


func _process(delta: float) -> void:
	if target != null and is_instance_valid(target):
		var want := target.global_position + Vector3.UP * FOCUS_HEIGHT
		if MoveFeel.num("cam_lead") > 0.0:
			want += _lead(delta)
		elif _lead_last != Vector3.INF:
			_lead_last = Vector3.INF
			_lead_vel = Vector3.ZERO
			lead = Vector3.ZERO
		global_position = global_position.lerp(want, clampf(FOLLOW_RATE * delta, 0.0, 1.0))
	camera.size = lerpf(camera.size, _zoom_target, clampf(10.0 * delta, 0.0, 1.0))
	if _trauma > 0.0:
		_trauma = maxf(0.0, _trauma - SHAKE_DECAY * delta)
		var k := _trauma * _trauma * SHAKE_MAX_OFFSET
		camera.h_offset = _inset_offset() + GameWorld.fx_rng.randf_range(-k, k)
		camera.v_offset = GameWorld.fx_rng.randf_range(-k, k)
	else:
		camera.h_offset = _inset_offset()
		camera.v_offset = 0.0


## A movement feel's lead (docs/design/movement-research.md, package A): cam_lead units along the target's velocity
## (smoothed over cam_lead_time, so a reversal eases the view across rather than snapping it), plus cam_aim_share of the
## way toward the aim, at most cam_lead_max in all.
func _lead(delta: float) -> Vector3:
	var p := target.global_position
	if _lead_last == Vector3.INF or delta <= 0.0:
		_lead_last = p
	var v := (p - _lead_last) / maxf(delta, 0.0001)
	v.y = 0.0
	_lead_last = p
	if v.length() > 30.0:
		v = Vector3.ZERO   # (a teleport)
	_lead_vel = _lead_vel.lerp(v, clampf(delta / maxf(MoveFeel.num("cam_lead_time"), 0.01), 0.0, 1.0))
	var full := 4.5
	if target is Actor:
		full = maxf((target as Actor).move_speed, 0.1)
	var out := _lead_vel / full * MoveFeel.num("cam_lead")
	if aim_source.is_valid():
		var to: Vector3 = (aim_source.call() as Vector3) - p
		to.y = 0.0
		out += to * MoveFeel.num("cam_aim_share")
	lead = out.limit_length(MoveFeel.num("cam_lead_max"))
	return lead


## World units to slide the view so the target sits in the middle of the uncovered area.
func _inset_offset() -> float:
	var vh := float(get_viewport().get_visible_rect().size.y)
	return 0.0 if vh <= 0.0 else right_inset_px * 0.5 * camera.size / vh


## Jump straight to the target (no easing), e.g. on level start.
func snap() -> void:
	if target != null and is_instance_valid(target):
		global_position = target.global_position + Vector3.UP * FOCUS_HEIGHT


## Add screen shake (0..1).
func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func zoom_by(steps: int) -> void:
	_zoom_target = clampf(_zoom_target * pow(ZOOM_FACTOR, -steps), SIZE_MIN, SIZE_MAX)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(-1)
