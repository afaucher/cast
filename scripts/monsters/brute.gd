extends Monster
## Brute: slow, tanky, cannot climb (a +2 ledge is a safe spot). Its ground
## slam shows a red ring of the true radius that fills up during the 0.9 s
## windup; when it lands, `slammed(pos)` fires (for screen shake) and every hero
## inside the ring at a similar height takes damage (linear falloff to 50%).

signal slammed(pos: Vector3)

const HP := 140.0
const SPEED := 2.2
const SLAM_DAMAGE := 25.0
const SLAM_RADIUS := 2.0
const SLAM_EDGE_MULT := 0.5
const SLAM_SHOVE := 1.0         ## outward push on everything the slam hits
const WINDUP := 0.9
const COOLDOWN := 2.4
const AGGRO := 9.0
const START_RANGE := 1.9        ## a hero this close (and level with us) triggers a slam
const MAX_SLAM_DY := 0.8        ## world units; a hero on a +2 ledge (1.0) is out of reach

var _arm_l: Node3D = null
var _arm_r: Node3D = null
var _ring: Node3D = null
var _ring_fill: MeshInstance3D = null
var _ring_mat: StandardMaterial3D = null


func _init() -> void:
	super._init()
	kind = "brute"
	display_name = "Brute"
	max_hp = HP
	move_speed = SPEED
	radius = 0.6
	can_climb = false
	shove_mult = 0.4
	aggro_range = AGGRO
	attack_damage = SLAM_DAMAGE
	attack_windup = WINDUP
	attack_cooldown = COOLDOWN
	attack_start_range = START_RANGE
	stop_distance = 1.5
	bar_height = 2.55
	bar_width = 1.3
	walk_bob = 0.07
	walk_freq = 6.0
	windup_scale = 0.08


## Who may write each var (see Net); Monster's come from super(). All presentation.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"_arm_l": Net.LOCAL, "_arm_r": Net.LOCAL,
		"_ring": Net.LOCAL, "_ring_fill": Net.LOCAL, "_ring_mat": Net.LOCAL,
	})
	return f


func _build_visual(root: Node3D) -> void:
	var fur := _mat(Color(0.55, 0.16, 0.1))
	var dark := _mat(Color(0.32, 0.12, 0.08))
	var skin := _mat(Color(0.45, 0.2, 0.12))
	var horn := _mat(Color(0.9, 0.85, 0.7))
	var eye := _mat(Color(1.0, 0.85, 0.1), 3.0)
	# Legs
	_box(root, Vector3(0.32, 0.55, 0.36), Vector3(-0.3, 0.28, 0.0), dark)
	_box(root, Vector3(0.32, 0.55, 0.36), Vector3(0.3, 0.28, 0.0), dark)
	# Torso (big block) and belly
	_box(root, Vector3(1.05, 0.95, 0.72), Vector3(0.0, 1.0, 0.0), fur)
	_box(root, Vector3(0.7, 0.4, 0.2), Vector3(0.0, 0.8, -0.3), dark)
	# Shoulders
	_sphere(root, 0.3, Vector3(-0.66, 1.4, 0.0), skin)
	_sphere(root, 0.3, Vector3(0.66, 1.4, 0.0), skin)
	# Head + horns + eyes
	_box(root, Vector3(0.45, 0.38, 0.42), Vector3(0.0, 1.72, -0.06), skin)
	_cone(root, 0.08, 0.45, Vector3(-0.3, 2.0, -0.04), horn, Vector3(0, 0, 38))
	_cone(root, 0.08, 0.45, Vector3(0.3, 2.0, -0.04), horn, Vector3(0, 0, -38))
	_sphere(root, 0.05, Vector3(-0.11, 1.76, -0.27), eye)
	_sphere(root, 0.05, Vector3(0.11, 1.76, -0.27), eye)
	# Arms with fists (pivot at the shoulder for the slam animation)
	_arm_l = _pivot(root, Vector3(-0.68, 1.4, 0.0))
	_arm_r = _pivot(root, Vector3(0.68, 1.4, 0.0))
	for arm in [_arm_l, _arm_r]:
		var a: Node3D = arm
		_box(a, Vector3(0.3, 0.7, 0.3), Vector3(0.0, -0.36, 0.0), fur)
		_box(a, Vector3(0.38, 0.38, 0.38), Vector3(0.0, -0.8, 0.0), dark)


func _pose(_delta: float, _moving: bool) -> void:
	if _arm_l == null:
		return
	var a := -2.7 * _telegraph + 1.1 * _strike_t
	_arm_l.rotation.x = a
	_arm_r.rotation.x = a


# --- Slam -------------------------------------------------------------------------------------

func _can_strike_target() -> bool:
	# Out of reach if the hero stands on a ledge we can't climb (or in a pit).
	return absf(target.global_position.y - global_position.y) <= MAX_SLAM_DY


func _strike() -> void:
	var pos := global_position
	# Judged by each hero's center, so the ring is honest; online each hero's own machine decides it (Combat.slam).
	Combat.slam(pos, SLAM_RADIUS, SLAM_DAMAGE, SLAM_EDGE_MULT, SLAM_SHOVE, MAX_SLAM_DY, GameWorld.other_team(team), self)
	slammed.emit(pos)
	_spawn_shockwave(pos)


## A puppet's slam (M3): the shockwave only; the host deals the damage.
func _on_strike_visual() -> void:
	_spawn_shockwave(global_position)


func _on_windup_begin() -> void:
	_free_ring()
	_ring = Node3D.new()
	_ring.top_level = true
	add_child(_ring)
	_ring.global_position = global_position + Vector3.UP * 0.07
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat.albedo_color = Color(1.0, 0.1, 0.05, 0.85)
	var rim := TorusMesh.new()
	rim.inner_radius = SLAM_RADIUS - 0.07
	rim.outer_radius = SLAM_RADIUS
	rim.rings = 32
	rim.ring_segments = 4
	var rim_mi := MeshInstance3D.new()
	rim_mi.mesh = rim
	rim_mi.material_override = _ring_mat
	rim_mi.scale = Vector3(1.0, 0.3, 1.0)
	rim_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(rim_mi)
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.albedo_color = Color(1.0, 0.12, 0.05, 0.3)
	var disc := CylinderMesh.new()
	disc.top_radius = SLAM_RADIUS - 0.05
	disc.bottom_radius = SLAM_RADIUS - 0.05
	disc.height = 0.02
	disc.radial_segments = 32
	disc.rings = 1
	_ring_fill = MeshInstance3D.new()
	_ring_fill.mesh = disc
	_ring_fill.material_override = fill_mat
	_ring_fill.scale = Vector3(0.05, 1.0, 0.05)
	_ring_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(_ring_fill)


func _on_windup_end() -> void:
	_free_ring()


func _free_ring() -> void:
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null
	_ring_fill = null


func _update_visual(delta: float) -> void:
	super._update_visual(delta)
	if _ring_fill != null:
		var k := maxf(_telegraph, 0.05)
		_ring_fill.scale = Vector3(k, 1.0, k)
		# The ring stays put on the ground even while the body swells.
		_ring.global_position = Vector3(_ring.global_position.x, global_position.y + 0.07, _ring.global_position.z)


func _spawn_shockwave(pos: Vector3) -> void:
	if GameWorld.root == null:
		return
	var holder := Node3D.new()
	GameWorld.root.add_child(holder)
	holder.global_position = pos + Vector3.UP * 0.1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.55, 0.25, 0.8)
	var torus := TorusMesh.new()
	torus.inner_radius = SLAM_RADIUS - 0.12
	torus.outer_radius = SLAM_RADIUS
	torus.rings = 32
	torus.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	holder.scale = Vector3(0.3, 1.0, 0.3)
	var tw := holder.create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.set_parallel(true)
	tw.tween_property(holder, "scale", Vector3(1.15, 1.0, 1.15), 0.3)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(holder.queue_free)
