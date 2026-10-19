class_name FuseFx
extends Node3D
## The warning on a lit explosive prop (ExplosiveProp, docs/design/hazards.md): a hiss, a jet of sparks from its valve, a
## red glow that pulses faster as the fuse burns down, the model shaking harder and harder, and the blast's TRUE radius on
## the floor: a red rim with a fill that grows to it by the moment it blows (like the brute's slam ring), so the crew can
## see where to get out to. Cosmetic: every machine draws it from the fuse's start and end on its own clock
## (`progress`), nothing here decides anything, and its jitter is a function of time (no randomness at all).
##
##   var fx := FuseFx.attach(prop, model, fuse_point, radius, start, end)
##   fx.stop(doused)     # the blast took over (false), or the fuse was put out (true: a puff of steam)

const RIM := Color(1.0, 0.18, 0.06, 0.9)
const FILL := Color(1.0, 0.3, 0.08, 0.3)
const GLOW := Color(1.0, 0.35, 0.1)
const SHAKE_MAX := 0.06         ## world units of jitter at the end of the fuse
const TILT_MAX := 4.0           ## degrees of wobble at the end of the fuse

var _prop: Node3D = null
var _model: Node3D = null
var _start := 0.0
var _end := 1.0
var _radius := 3.0
var _ring: Node3D = null
var _fill: MeshInstance3D = null
var _sparks: CPUParticles3D = null
var _light: OmniLight3D = null
var _bulb: MeshInstance3D = null
var _bulb_mat: StandardMaterial3D = null
var _model_rest := Vector3.ZERO


static func attach(prop: Node3D, model: Node3D, fuse_point: Vector3, radius: float, start: float, end: float) -> FuseFx:
	var fx := FuseFx.new()
	fx.name = "FuseFx"
	fx._prop = prop
	fx._model = model
	fx._start = start
	fx._end = maxf(end, start + 0.05)
	fx._radius = radius
	prop.add_child(fx)
	fx.position = fuse_point
	fx._build()
	return fx


## 0 at the light, 1 at the blast.
func progress() -> float:
	return clampf((GameWorld.time - _start) / (_end - _start), 0.0, 1.0)


func _build() -> void:
	if _model != null:
		_model_rest = _model.position
	# the jet of sparks from the valve
	_sparks = CPUParticles3D.new()
	_sparks.amount = 28
	_sparks.lifetime = 0.35
	_sparks.local_coords = false
	_sparks.direction = Vector3.UP
	_sparks.spread = 55.0
	_sparks.initial_velocity_min = 1.6
	_sparks.initial_velocity_max = 3.4
	_sparks.gravity = Vector3(0, -7.0, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 4
	sm.rings = 2
	sm.material = Fx.glow_material(Color(1.0, 0.85, 0.35, 0.95))
	_sparks.mesh = sm
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0))
	_sparks.scale_amount_curve = c
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sparks)
	_sparks.emitting = true
	# a hot bulb of light at the valve, and a red light on the room
	var bs := SphereMesh.new()
	bs.radius = 0.16
	bs.height = 0.32
	bs.radial_segments = 8
	bs.rings = 4
	_bulb_mat = Fx.glow_material(Color(GLOW.r, GLOW.g, GLOW.b, 0.7))
	_bulb = MeshInstance3D.new()
	_bulb.mesh = bs
	_bulb.material_override = _bulb_mat
	_bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bulb.set_meta("no_flash", true)
	add_child(_bulb)
	_light = OmniLight3D.new()
	_light.light_color = GLOW
	_light.omni_range = 4.5
	_light.shadow_enabled = false
	add_child(_light)
	# the blast radius on the floor
	_ring = Node3D.new()
	_ring.name = "BlastRing"
	_ring.top_level = true
	add_child(_ring)
	_ring.global_position = Vector3(_prop.global_position.x, _prop.global_position.y + 0.07, _prop.global_position.z)
	var rim_mat := StandardMaterial3D.new()
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rim_mat.albedo_color = RIM
	var rim := TorusMesh.new()
	rim.inner_radius = _radius - 0.09
	rim.outer_radius = _radius + 0.03
	rim.rings = 40
	rim.ring_segments = 4
	var rim_mi := MeshInstance3D.new()
	rim_mi.mesh = rim
	rim_mi.material_override = rim_mat
	rim_mi.scale = Vector3(1.0, 0.15, 1.0)
	rim_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(rim_mi)
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill_mat.albedo_color = FILL
	var disc := CylinderMesh.new()
	disc.top_radius = _radius
	disc.bottom_radius = _radius
	disc.height = 0.01
	disc.radial_segments = 40
	disc.rings = 1
	_fill = MeshInstance3D.new()
	_fill.mesh = disc
	_fill.material_override = fill_mat
	_fill.scale = Vector3(0.05, 1.0, 0.05)
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(_fill)
	Sfx.play_at("fuse", global_position)
	_process(0.0)


func _process(_delta: float) -> void:
	var k := progress()
	var t := GameWorld.time
	# the pulse quickens from 3 Hz to 12 Hz, and the glow swells
	var rate := lerpf(3.0, 12.0, k * k)
	var pulse := 0.5 + 0.5 * sin((t - _start) * TAU * rate)
	if _light != null:
		_light.light_energy = lerpf(1.2, 4.0, k) * (0.55 + 0.45 * pulse)
	if _bulb != null:
		var s := lerpf(0.6, 1.4, k) * (0.8 + 0.3 * pulse)
		_bulb.scale = Vector3.ONE * s
		_bulb_mat.albedo_color.a = lerpf(0.45, 0.85, k) * (0.7 + 0.3 * pulse)
	if _fill != null:
		var f := maxf(k, 0.05)
		_fill.scale = Vector3(f, 1.0, f)
	if _sparks != null:
		_sparks.speed_scale = lerpf(0.8, 1.5, k)
	# the shake: a function of time only, so every screen shakes the same way
	if _model != null and is_instance_valid(_model):
		var amp := SHAKE_MAX * (0.25 + 0.75 * k * k)
		_model.position = _model_rest + Vector3(sin(t * 61.0) * amp, 0.0, cos(t * 53.0) * amp)
		_model.rotation_degrees.z = sin(t * 37.0) * TILT_MAX * k
		_model.rotation_degrees.x = cos(t * 41.0) * TILT_MAX * 0.6 * k


## The fuse is over: the blast takes over (doused false) or it was put out (true: steam and "FIZZLE"). Frees itself.
func stop(doused: bool) -> void:
	if _model != null and is_instance_valid(_model):
		_model.position = _model_rest
		_model.rotation = Vector3.ZERO
	if doused:
		var steam: Array[Color] = [Color(0.85, 0.92, 0.98), Color(0.6, 0.7, 0.78)]
		Fx.burst(global_position, steam, 14, 1.6, 0.18, 0.9, -1.2, Vector3.UP, 40.0, false)
		Fx.number(global_position + Vector3.UP * 0.7, "FIZZLE", Color(0.6, 0.88, 1.0), 0.85)
	set_process(false)
	queue_free()
