class_name DecorAnim
extends Node
## Tiny animation drivers for the few animated set-dressing pieces (kept off the models so the soup stays
## static): "neon" flickers a sign's letters one by one (a dead letter only sparks now and then), "screen"
## flips the cinema screen between snow frames and, now and then, the demon silhouette, "fin" sends a shark fin
## patrolling the moat. Added by DecorModels.build(); costs nothing when nothing is animated.

var mode := ""
# neon
var mats: Array[ShaderMaterial] = []
var dead: Array = []
# screen
var screen: MeshInstance3D = null
# fin
var fin_center := Vector2.ZERO
var fin_radius := 3.0
var fin_gap_yaw := 0.0
var fin_phase := 0.0
var fin_speed := 0.6

const LIT := 1.9
const OFF := 0.12

var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _off_until: Array[float] = []
var _next_flick: Array[float] = []
var _last_gain: Array[float] = []
var _frame_t := 0.0
var _demon_until := 0.0
var _next_demon := 0.0
var _y0 := 0.0


func _ready() -> void:
	_rng.randomize()
	_t = _rng.randf() * 20.0
	for i in mats.size():
		_off_until.append(0.0)
		_next_flick.append(_t + _rng.randf_range(0.5, 5.0))
		_last_gain.append(-1.0)
	_next_demon = _t + _rng.randf_range(2.0, 6.0)
	if mode == "fin":
		var model := get_parent() as Node3D
		_y0 = model.global_position.y
		model.top_level = true
	set_process(mode != "")


func _process(delta: float) -> void:
	_t += delta
	match mode:
		"neon": _neon()
		"screen": _screen(delta)
		"fin": _fin()


func _neon() -> void:
	for i in mats.size():
		var gain := LIT
		if dead.has(i):
			gain = OFF
			if fmod(_t * 0.7 + float(i) * 1.3, 4.6) < 0.09:
				gain = 1.3        # an occasional spark in the dead tube
		else:
			if _t >= _next_flick[i]:
				_off_until[i] = _t + _rng.randf_range(0.05, 0.22)
				_next_flick[i] = _t + _rng.randf_range(1.8, 6.5)
				if _rng.randf() < 0.3:
					_next_flick[i] = _t + _off_until[i] - _t + _rng.randf_range(0.08, 0.2)   # a double stutter
			if _t < _off_until[i]:
				gain = OFF
			else:
				gain = LIT * (0.92 + 0.08 * sin(_t * 31.0 + float(i)))
		if absf(gain - _last_gain[i]) > 0.02:
			_last_gain[i] = gain
			mats[i].set_shader_parameter("glow_gain", gain)


func _screen(delta: float) -> void:
	if screen == null:
		return
	_frame_t -= delta
	if _frame_t > 0.0:
		return
	_frame_t = 0.075
	var frames := DecorScreen.frames()
	var idx := _rng.randi_range(0, DecorScreen.SNOW_FRAMES - 1)
	if _t >= _next_demon:
		_demon_until = _t + _rng.randf_range(0.25, 0.5)
		_next_demon = _t + _rng.randf_range(3.0, 8.0)
	if _t < _demon_until and _rng.randf() < 0.8:
		idx = DecorScreen.SNOW_FRAMES
	var m := screen.material_override as StandardMaterial3D
	m.albedo_texture = frames[idx]
	var v := _rng.randf_range(0.85, 1.25)
	m.albedo_color = Color(1.1 * v, 1.18 * v, 1.3 * v)


func _fin() -> void:
	var model := get_parent() as Node3D
	var dir_g := Vector2(sin(deg_to_rad(fin_gap_yaw)), cos(deg_to_rad(fin_gap_yaw)))
	var lat_g := Vector2(cos(deg_to_rad(fin_gap_yaw)), -sin(deg_to_rad(fin_gap_yaw)))
	var amp := PI - 0.5
	var arg := fin_speed * _t + fin_phase
	var phi := PI + amp * sin(arg)
	var p := fin_center + (lat_g * sin(phi) + dir_g * cos(phi)) * fin_radius
	var v := (lat_g * cos(phi) - dir_g * sin(phi)) * signf(cos(arg))
	model.global_position = Vector3(p.x, _y0, p.y)
	model.rotation = Vector3(0.0, atan2(v.x, v.y), 0.0)
