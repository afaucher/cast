class_name BowlBoulder
extends Node3D
## Rebar's "bowl": a faceted sandstone boulder that rolls along the terrain (following the
## ground height, dropping down ledges), passes THROUGH actors and shoves each one it touches
## sideways/forward out of its path. Monsters take damage; heroes (teammates, the player) are
## only shoved. Stops at a +2 rise, a wall, the end of its range or a pit.
## Kinematic and deterministic: it uses physics frames, no random numbers.

const RADIUS := 0.5             ## visual radius of the boulder
const HIT_RADIUS := 0.55        ## reach around its center (an actor's own radius is added)
const PROP_DAMAGE_MULT := 6.0   ## a rolling boulder is rough on priced props (6 x damage each)
const MAX_DY := 1.1             ## only touches actors at about its own height
const GRAVITY := 24.0
const SLAM_RISE_LEVELS := 1.95
const STONE := Color(0.76, 0.66, 0.49)

var source: Actor = null
var direction := Vector3.FORWARD
var speed := 7.0
var max_range := 9.0
var damage := 6.0
var shove_distance := 3.5

var _travelled := 0.0
var _hit := {}                  ## actor instance id -> true (each actor is shoved once)
var _vy := 0.0
var _airborne := false
var _done := false
var _flip := 1.0                ## alternates the side for dead-center hits
var _roll: Node3D = null
var _angle := 0.0
var _dust: CPUParticles3D = null


## Roll a boulder from `src` toward `dir` (X/Z).
static func launch(src: Actor, dir: Vector3, spd: float = 7.0, rng: float = 9.0, dmg: float = 6.0, shove: float = 3.5) -> BowlBoulder:
	var b := BowlBoulder.new()
	b.source = src
	dir.y = 0.0
	b.direction = dir.normalized() if dir.length() > 0.001 else src.facing
	b.speed = spd
	b.max_range = rng
	b.damage = dmg
	b.shove_distance = shove
	var start := src.global_position + b.direction * (src.radius + RADIUS + 0.1)
	if GameWorld.map != null:
		var g := GameWorld.map.ground_height(start)
		start.y = src.global_position.y if is_nan(g) else g
	GameWorld.spawn(b, start)
	Sfx.play_at("boulder_roll", start)
	return b


func _ready() -> void:
	_build_visual()


## Who may write each var (see Net). A scheduled effect: one launch event, then every machine
## rolls the boulder itself from these parameters.
func net_fields() -> Dictionary:
	return {
		"source": Net.SPAWN,      # will travel as an entity id in the launch event
		"direction": Net.SPAWN, "speed": Net.SPAWN, "max_range": Net.SPAWN, "damage": Net.SPAWN,
		"shove_distance": Net.SPAWN,
		"_travelled": Net.LOCAL, "_hit": Net.LOCAL, "_vy": Net.LOCAL, "_airborne": Net.LOCAL,
		"_done": Net.LOCAL, "_flip": Net.LOCAL, "_angle": Net.LOCAL,
		"_roll": Net.LOCAL, "_dust": Net.LOCAL,
	}


func _physics_process(delta: float) -> void:
	if _done:
		return
	var map: HexMap = GameWorld.map
	var left := speed * delta
	while left > 0.0001 and not _done:
		var s := minf(left, 0.2)
		left -= s
		var np := global_position + direction * s
		np.y = global_position.y
		if map != null:
			var cell: HexMap.Cell = map.get_cell(Hex.from_world(np))
			if cell == null:
				_fall_into_void(np)
				return
			if map.blocks_point(np, RADIUS):   # a wall face (HexMap): stop with the boulder against it
				global_position = global_position.lerp(np, map.sweep(global_position, np, RADIUS))
				_stop()
				return
			var probe := np + direction * RADIUS * 0.6
			var pg := map.ground_height(probe)
			var ref_y := global_position.y
			if not _airborne:
				var g0 := map.ground_height(global_position)
				if not is_nan(g0):
					ref_y = g0
			if not is_nan(pg) and (pg - ref_y) / Hex.LEVEL_HEIGHT >= SLAM_RISE_LEVELS:
				_stop()
				return
		global_position = np
		_travelled += s
		_angle += s / RADIUS
		_check_hits()
	_follow_ground(delta, map)
	if _roll != null:
		var axis := Vector3.UP.cross(direction)
		_roll.basis = Basis(axis.normalized(), _angle)
	if _travelled >= max_range:
		_stop()


func _follow_ground(delta: float, map: HexMap) -> void:
	if map == null:
		return
	var g := map.ground_height(global_position)
	if is_nan(g):
		return
	if not _airborne:
		if global_position.y > g + 0.03:
			_airborne = true
			_vy = 0.0
		else:
			global_position.y = lerpf(global_position.y, g, clampf(20.0 * delta, 0.0, 1.0))
			if absf(global_position.y - g) < 0.01:
				global_position.y = g
			return
	_vy -= GRAVITY * delta
	global_position.y += _vy * delta
	if global_position.y <= g:
		global_position.y = g
		_vy = 0.0
		_airborne = false
		_puff(6)


func _check_hits() -> void:
	for a in GameWorld.actors_in_radius(global_position, HIT_RADIUS):
		if a == source or _hit.has(a.get_instance_id()):
			continue
		if absf(a.global_position.y - global_position.y) > MAX_DY:
			continue
		_hit[a.get_instance_id()] = true
		var rel := a.global_position - global_position
		rel.y = 0.0
		var side := rel - direction * rel.dot(direction)
		if side.length() < 0.2:
			side = Vector3(-direction.z, 0.0, direction.x) * _flip
			_flip = -_flip
		Fx.burst(a.global_position + Vector3.UP * 0.4, _dust_colors(), 8, 2.5, 0.09, 0.45, 3.0, Vector3.UP, 70.0, false)
		if Combat.shielded(a, global_position - direction * 2.0, Combat.HIT_SHOT, source):
			_stop()   # (a bonk on a pavise's planks: the boulder crumbles, nothing moves)
			return
		Sfx.play_at("hit_heavy", a.global_position)
		if not Combat.resolves(a, source):
			continue   # (online: the boulder rolls on every screen; the victim decides a hero, the bowler the rest)
		var push := (side.normalized() * 0.85 + direction * 0.5).normalized()
		if a.team == GameWorld.TEAM_MONSTERS:
			Fx.attach_hit_feedback(a)
			a.apply_damage(damage, source)
		elif a is PricedProp or a.is_in_group("sharks"):
			a.apply_damage(damage * PROP_DAMAGE_MULT, source)   # rolls through the client's property
		elif a.is_in_group("breakables"):
			a.apply_damage(damage, source)                      # and through the client's mail
		a.shove(push, shove_distance, source)


func _stop() -> void:
	if _done:
		return
	_done = true
	_puff(10)
	if _dust != null:
		_dust.emitting = false
	var tw := create_tween()
	if _roll != null:
		tw.tween_property(_roll, "scale", Vector3.ONE * 0.05, 0.18)
	tw.tween_interval(0.4)
	tw.tween_callback(queue_free)


func _fall_into_void(np: Vector3) -> void:
	_done = true
	global_position = np
	if _dust != null:
		_dust.emitting = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "global_position:y", global_position.y - 4.0, 0.7).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "scale", Vector3.ONE * 0.3, 0.7)
	tw.chain().tween_callback(queue_free)


func _dust_colors() -> Array[Color]:
	var cols: Array[Color] = [Color(0.86, 0.78, 0.6), Color(0.7, 0.6, 0.45)]
	return cols


func _puff(amount: int) -> void:
	Fx.burst(global_position + Vector3.UP * 0.1, _dust_colors(), amount, 2.0, 0.1, 0.5, 2.0, Vector3.UP, 80.0, false)


func _build_visual() -> void:
	_roll = Node3D.new()
	_roll.position = Vector3(0, RADIUS * 0.95, 0)
	add_child(_roll)
	var mi := MeshInstance3D.new()
	mi.mesh = LowPoly.boulder(Vector3(RADIUS, RADIUS * 0.92, RADIUS * 0.96), 1, 0.16, STONE, 7, 0.1).to_mesh()
	mi.material_override = LowPolyMaterial.make(2.2)
	_roll.add_child(mi)
	_dust = CPUParticles3D.new()
	_dust.amount = 14
	_dust.lifetime = 0.55
	_dust.local_coords = false
	_dust.direction = Vector3.UP
	_dust.spread = 50.0
	_dust.initial_velocity_min = 0.3
	_dust.initial_velocity_max = 1.0
	_dust.gravity = Vector3(0, 0.5, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.82, 0.74, 0.58)
	sm.material = mat
	_dust.mesh = sm
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0))
	_dust.scale_amount_curve = c
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dust.position = Vector3(0, 0.1, 0)
	add_child(_dust)
	_dust.emitting = true
