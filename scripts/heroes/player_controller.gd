class_name PlayerController
extends Node
## Keyboard + mouse control for the player's hero (add as a child of the Hero).
## WASD moves relative to the iso camera, the mouse aims via a camera ray onto
## the terrain, LMB = melee (the hero's primary), RMB = the secondary (bolt / bowl / spin; Wick's arrow:
## tap to shoot, hold to draw a piercing shot and release), keys 1-4 = ready (hold) a spell slot,
## E = use the elevator when standing at it, else tell your employee to wait / bring a waiting one (Employee.interact),
## else cast the readied spell at the aim point (power SpellComponents.READIED_POWER), F = swap
## the pickup underfoot into the held slot. aim_point() is also what voice casts aim at;
## cast_spell() is the single entry for voice and E (charges, cooldown, toasts).

const DEFAULT_YAW_DEG := 45.0   ## iso yaw used when there is no camera (tests)
const GROUND_REFINE_STEPS := 3
const FALLBACK_AIM_DIST := 5.0

var hero: Hero
var camera: Camera3D = null     ## defaults to the viewport's current Camera3D
var hud: Hud = null             ## optional: receives cast / cooldown toasts
var enabled := true
var aim_override := Vector3.INF ## scripted aim (autocast, tests); INF = use the mouse
## Context action on E: called with no arguments when E is pressed, it returns true when it used the
## press (the game opens the elevator when the hero stands at it). A used press does NOT cast.
var interact: Callable = Callable()


func _ready() -> void:
	hero = get_parent() as Hero
	if hero:
		hero.is_player = true
	if not InputMap.has_action("attack_melee"):
		InputSetup.ensure_actions()


## Who may write each var (see Net). Exists only on the machine of the player it controls, so
## nothing here travels: input and aim are that machine's working state.
func net_fields() -> Dictionary:
	return {
		"hero": Net.LOCAL, "camera": Net.LOCAL, "hud": Net.LOCAL, "interact": Net.LOCAL,
		"enabled": Net.PRIVATE, "aim_override": Net.PRIVATE,
	}


func _physics_process(delta: float) -> void:
	if hero == null or hero.dead or not enabled or _typing():
		return
	if hero.is_helpless():
		hero.climbing = false   # shoved or staggered: no steering, no attacks (voice casts still work)
		hero.cancel_draw()
		_slot_keys()
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
	_slot_keys()
	var aim := aim_point()
	var to := aim - hero.global_position
	to.y = 0.0
	var ranged := Input.is_action_pressed("attack_ranged")
	if hero.is_drawing() and not ranged:
		hero.release_draw(to)   # RMB let go: tap or drawn shot (even if the cursor drifted onto the HUD)
	if _over_ui():
		return
	if Input.is_action_pressed("attack_melee"):
		hero.melee(to)          # also lowers a drawn bow
	elif ranged:
		if hero.secondary_kind == "arrow":
			hero.start_draw()   # hold to draw; released above (early = tap shot)
		else:
			hero.shoot(to)


## Keys 1-4 (ready a slot), E (cast the readied spell) and F (swap a pickup in).
func _slot_keys() -> void:
	for i in SpellComponents.SLOT_COUNT:
		if Input.is_action_just_pressed("cast_slot_%d" % (i + 1)):
			select_slot(i)
	if Input.is_action_just_pressed("cast_readied"):
		press_readied()
	if Input.is_action_just_pressed("swap_pickup"):
		swap_pickup()


## Ready slot `i` (0-based). An empty slot just says so.
func select_slot(i: int) -> bool:
	if hero == null or hero.dead:
		return false
	if hero.select_slot(i):
		return true
	if hud:
		hud.show_message("Slot %d is empty" % (i + 1), Hud.COLOR_NEUTRAL)
	return false


## The E key, in priority order: the context action (the elevator, when the hero stands at it), then an
## employee next to the hero (dismiss the one following them, or recruit a waiting one), else cast_readied().
## One press does one thing, never more.
func press_readied() -> bool:
	if interact.is_valid() and bool(interact.call()):
		return true
	if hero != null and not hero.dead and Employee.interact(hero):
		return true
	return cast_readied()


## E: cast the held spell at the aim point with the fixed readied power.
func cast_readied() -> bool:
	if hero == null or hero.dead:
		return false
	var id := hero.held_spell()
	if id == "":
		if hud:
			hud.show_message("Nothing readied", Hud.COLOR_NEUTRAL)
		return false
	return cast_spell(id, SpellComponents.READIED_POWER)


## F: swap the pickup the hero stands next to into the held slot.
func swap_pickup() -> bool:
	if hero == null or hero.dead:
		return false
	return hero.swap_in_pickup()


## Cast from voice or E. Handles the toasts: unknown spell, out of components (no cooldown spent),
## cooldown, success.
func cast_spell(id: String, power: float) -> bool:
	if hero == null or hero.dead:
		return false
	if not hero.spell_slots.has(id):
		if hud:
			hud.show_unknown_spell(id)
		return false
	if hero.charges_of(id) <= 0:
		SpellBook.fizzle(hero)
		if hud:
			hud.show_out_of_component(id)
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
