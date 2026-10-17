class_name PlayerController
extends Node
## Keyboard + mouse control for the player's hero (add as a child of the Hero).
## WASD moves relative to the iso camera, the mouse aims via a camera ray onto
## the terrain, LMB = melee, RMB = ranged bolt, keys 1/2 = slot spells at full
## power (the keyboard fallback for voice). aim_point() is also what voice
## casts aim at; cast_spell() is the single entry for voice and keys.

const DEFAULT_YAW_DEG := 45.0   ## iso yaw used when there is no camera (tests)
const GROUND_REFINE_STEPS := 3
const FALLBACK_AIM_DIST := 5.0

var hero: Hero
var camera: Camera3D = null     ## defaults to the viewport's current Camera3D
var hud: Hud = null             ## optional: receives cast / cooldown toasts
var enabled := true
var aim_override := Vector3.INF ## scripted aim (autocast, tests); INF = use the mouse


func _ready() -> void:
	hero = get_parent() as Hero
	if hero:
		hero.is_player = true
	if not InputMap.has_action("attack_melee"):
		InputSetup.ensure_actions()


func _physics_process(delta: float) -> void:
	if hero == null or hero.dead or not enabled or _typing():
		return
	if hero.is_helpless():
		hero.climbing = false   # shoved or staggered: no steering, no attacks (voice casts still work)
		return
	var cam := _camera()
	var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dir := move_direction(iv, cam)
	if dir.length() > 0.01:
		hero.move(dir, delta)
	else:
		hero.climbing = false
	if cam != null or aim_override != Vector3.INF:
		hero.face_point(aim_point())
	if _over_ui():
		return
	var aim := aim_point()
	var to := aim - hero.global_position
	to.y = 0.0
	if Input.is_action_pressed("attack_melee"):
		hero.melee(to)
	elif Input.is_action_pressed("attack_ranged"):
		hero.shoot(to)
	for i in 2:
		if i < hero.spell_slots.size() and Input.is_action_just_pressed("cast_slot_%d" % (i + 1)):
			cast_spell(hero.spell_slots[i], 1.0)


## Cast from voice or keys. Handles the toasts: unknown spell, cooldown, success.
func cast_spell(id: String, power: float) -> bool:
	if hero == null or hero.dead:
		return false
	if not hero.spell_slots.has(id):
		if hud:
			hud.show_unknown_spell(id)
		return false
	var left := hero.cooldown_left(id)
	if left > 0.0:
		if hud:
			hud.show_cooldown(id, left)
		return false
	if hero.try_cast(id, power, aim_point()):
		if hud:
			hud.show_cast(id, power)
		return true
	return false


## World point under the mouse (on the terrain), or the scripted aim, or a spot ahead of the hero.
func aim_point() -> Vector3:
	if aim_override != Vector3.INF:
		return aim_override
	var cam := _camera()
	if cam == null or hero == null:
		return (hero.global_position if hero else Vector3.ZERO) + (hero.facing if hero else Vector3.FORWARD) * FALLBACK_AIM_DIST
	var vp := cam.get_viewport()
	var mouse := vp.get_mouse_position()
	var p := ray_to_ground(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse), hero.global_position.y, GameWorld.map)
	if p == Vector3.INF:
		return hero.global_position + hero.facing * FALLBACK_AIM_DIST
	return p


## WASD vector (x = right, y = down on screen) to a world X/Z move direction relative to the camera.
static func move_direction(input: Vector2, cam: Camera3D = null) -> Vector3:
	if input.length() < 0.01:
		return Vector3.ZERO
	var fwd: Vector3
	var right: Vector3
	if cam != null and cam.is_inside_tree():
		fwd = -cam.global_transform.basis.z
		right = cam.global_transform.basis.x
	else:
		var yaw := deg_to_rad(DEFAULT_YAW_DEG)
		fwd = Vector3(-sin(yaw), 0, -cos(yaw))
		right = Vector3(cos(yaw), 0, -sin(yaw))
	fwd.y = 0.0
	right.y = 0.0
	fwd = fwd.normalized()
	right = right.normalized()
	return (right * input.x + fwd * -input.y).limit_length(1.0)


## Intersect a ray with the horizontal plane at height y. Vector3.INF if parallel or behind.
static func ray_to_plane(origin: Vector3, dir: Vector3, y: float) -> Vector3:
	if absf(dir.y) < 0.00001:
		return Vector3.INF
	var t := (y - origin.y) / dir.y
	if t < 0.0:
		return Vector3.INF
	return origin + dir * t


## Ray vs terrain: start at the plane of height `start_y` (the hero's feet), then
## re-intersect at the ground height under the hit a few times (converges quickly).
static func ray_to_ground(origin: Vector3, dir: Vector3, start_y: float, map: HexMap) -> Vector3:
	var p := ray_to_plane(origin, dir, start_y)
	if p == Vector3.INF or map == null:
		return p
	for _i in GROUND_REFINE_STEPS:
		var g := map.ground_height(p)
		if is_nan(g):
			break
		var q := ray_to_plane(origin, dir, g)
		if q == Vector3.INF:
			break
		p = q
	return p


func _camera() -> Camera3D:
	if camera != null and is_instance_valid(camera):
		return camera
	return get_viewport().get_camera_3d() if is_inside_tree() else null


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return f is LineEdit or f is TextEdit


func _over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null
