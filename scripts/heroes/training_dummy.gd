class_name TrainingDummy
extends Actor
## A monster-team target for testing heroes and spells without the real
## monsters. STATIC: a straw post that respawns after being destroyed.
## WALKER: a slow grunt-like brute that shuffles toward the nearest hero and
## punches, so armor and heal have something to chew on.

enum Mode { STATIC, WALKER }

const RESPAWN_TIME := 3.0
const WALK_SPEED := 1.6
const PUNCH_DAMAGE := 8.0
const PUNCH_REACH := 1.25
const PUNCH_COOLDOWN := 1.2
const PUNCH_SHOVE := 0.35
const AGGRO_RANGE := 14.0

@export var mode: Mode = Mode.STATIC

var home := Vector3.ZERO     ## respawn point, captured on the first physics frame
var _home_set := false
var _respawn_at := -1.0
var _punch_ready_at := 0.0
var _visual: Node3D
var _bar: HpBar
var _body_mat: StandardMaterial3D
var _base_color := Color(0.85, 0.72, 0.4)
var _rest_yaw := 0.0       ## static dummies face the iso camera (+X,+Z)


func _init() -> void:
	team = GameWorld.TEAM_MONSTERS
	max_hp = 120.0
	radius = 0.45
	move_speed = WALK_SPEED
	display_name = "Dummy"


func _ready() -> void:
	super._ready()
	_build_visual()
	Fx.attach_hit_feedback(self)
	damaged.connect(func(_a: float, _s: Node) -> void: _bar.set_fraction(hp / max_hp))


## Who may write each var (see Net); Actor's come from super(). The host owns the dummy.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"mode": Net.SPAWN,
		# The host's AI and respawn bookkeeping; others see the result through hp / dead / position.
		"home": Net.PRIVATE, "_home_set": Net.PRIVATE, "_respawn_at": Net.PRIVATE,
		"_punch_ready_at": Net.PRIVATE,
		"_visual": Net.LOCAL, "_bar": Net.LOCAL, "_body_mat": Net.LOCAL,
		"_base_color": Net.LOCAL, "_rest_yaw": Net.LOCAL,
	})
	return f


func _physics_process(delta: float) -> void:
	if not _home_set:
		home = global_position
		_home_set = true
	if dead:
		if _respawn_at >= 0.0 and GameWorld.time >= _respawn_at:
			_respawn()
		return
	if mode != Mode.WALKER or is_helpless():
		return
	var target := GameWorld.nearest_actor(global_position, GameWorld.TEAM_HEROES, AGGRO_RANGE)
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0.0
	facing = to.normalized() if to.length() > 0.01 else facing
	if to.length() > PUNCH_REACH * 0.8:
		move(to.normalized(), delta)
	elif GameWorld.time >= _punch_ready_at:
		_punch_ready_at = GameWorld.time + PUNCH_COOLDOWN
		Combat.melee_arc(self, facing, PUNCH_REACH, 120.0, PUNCH_DAMAGE, PUNCH_SHOVE)
		_punch_anim()


func _process(delta: float) -> void:
	if _visual and mode == Mode.WALKER and not dead:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-facing.x, -facing.z), clampf(10.0 * delta, 0.0, 1.0))


func _on_death() -> void:
	_respawn_at = GameWorld.time + RESPAWN_TIME
	_bar.visible = false
	var tw := create_tween()
	tw.tween_property(_visual, "rotation:x", deg_to_rad(-90), 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.6)
	tw.tween_callback(func() -> void: visible = false)
	var straw: Array[Color] = [Color(0.9, 0.8, 0.5), Color(0.6, 0.5, 0.3)]
	Fx.burst(global_position + Vector3.UP * 0.8, straw, 14, 3.0, 0.08, 0.7, 9.0)


func _respawn() -> void:
	dead = false
	hp = max_hp
	_respawn_at = -1.0
	global_position = home
	snap_to_ground()
	visible = true
	scale = Vector3.ONE
	rotation = Vector3.ZERO
	_visual.rotation = Vector3(0, _rest_yaw, 0)
	_bar.visible = true
	_bar.set_fraction(1.0)
	_modifiers.clear()
	Fx.ring(home, 1.0, Color(0.9, 0.9, 0.6, 0.7), 0.5)


func _punch_anim() -> void:
	var tw := create_tween()
	_visual.position = Vector3.ZERO
	tw.tween_property(_visual, "position", facing * 0.5, 0.08)
	tw.tween_property(_visual, "position", Vector3.ZERO, 0.2)


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	if mode == Mode.WALKER:
		_base_color = Color(0.75, 0.3, 0.25)
		_body_mat = Fx.solid_material(_base_color, 0.7)
		var body := CapsuleMesh.new()
		body.radius = 0.42
		body.height = 1.5
		_mesh(body, _body_mat, Vector3(0, 0.75, 0))
		var head := SphereMesh.new()
		head.radius = 0.3
		head.height = 0.6
		_mesh(head, Fx.solid_material(Color(0.6, 0.25, 0.2)), Vector3(0, 1.65, 0))
		var fist := SphereMesh.new()
		fist.radius = 0.2
		fist.height = 0.4
		for sx in [-1.0, 1.0]:
			_mesh(fist, Fx.solid_material(Color(0.55, 0.2, 0.18)), Vector3(0.5 * sx, 0.9, -0.35))
		var eye := BoxMesh.new()
		eye.size = Vector3(0.45, 0.07, 0.07)
		_mesh(eye, Fx.solid_material(Color(1.0, 0.9, 0.2)), Vector3(0, 1.72, -0.28))
		display_name = "Grunt"
	else:
		_rest_yaw = deg_to_rad(-135.0)
		_visual.rotation.y = _rest_yaw
		_body_mat = Fx.solid_material(_base_color, 0.9)
		var post := CylinderMesh.new()
		post.top_radius = 0.1
		post.bottom_radius = 0.14
		post.height = 1.3
		_mesh(post, Fx.solid_material(Color(0.45, 0.3, 0.18)), Vector3(0, 0.65, 0))
		var torso := CylinderMesh.new()
		torso.top_radius = 0.34
		torso.bottom_radius = 0.34
		torso.height = 0.9
		torso.radial_segments = 8
		_mesh(torso, _body_mat, Vector3(0, 1.0, 0))
		# Bullseye on the front (toward -Z).
		for i in 3:
			var d := CylinderMesh.new()
			d.top_radius = 0.28 - i * 0.09
			d.bottom_radius = d.top_radius
			d.height = 0.02
			var m := _mesh(d, Fx.solid_material(Color(0.85, 0.15, 0.15) if i % 2 == 0 else Color(0.95, 0.95, 0.95)), Vector3(0, 1.05, -0.345 - i * 0.004))
			m.rotation.x = deg_to_rad(90)
		var cap := SphereMesh.new()
		cap.radius = 0.22
		cap.height = 0.44
		_mesh(cap, _body_mat, Vector3(0, 1.7, 0))
	_bar = HpBar.new()
	_bar.position = Vector3(0, 2.3, 0)
	add_child(_bar)


func _mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_visual.add_child(mi)
	return mi
