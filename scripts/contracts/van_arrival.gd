class_name VanArrival
extends Node3D
## The crew's arrival at the start of every floor: the work van teleports in over a summoning circle, lands on its
## suspension, the side door slides open and Wick, Gasket and Rebar step out beside it. Afterwards the van stays
## parked as solid set dressing (invisible DecorBlocker circles keep heroes and monsters out of it, like any blocking
## decor; it is not priced and does not take damage) and the circle settles into a faint chalk mark on the floor.
##
## It is driven by a plain timeline (time = seconds since the start, advanced in _process, so pause and the elevator
## freeze stop it), and every moment is a pure function of `time`: _pose(t). Total 2.5 s until the crew is out
## (`finished`), then the circle keeps settling to chalk for another second (non-blocking: control is already back).
##
##   0.00  the circle ignites: a ring of amber light draws itself around, sparks rise, a column of light grows
##   0.80  POP: flash, smoke, the van appears stretched tall above the circle and drops
##   1.06  it lands on its suspension (squash, dust ring, a little camera shake), the shock ring races out; `landed`
##   1.22  the horn honks twice and the headlights flash (`honked` is the audio hook: no sound assets exist yet)
##   1.32  the side door slides open (violet glow from inside)       1.55-2.4  the crew steps out, one after another
##   2.50  `finished`: control goes back to the player. The lights dim; the circle settles into chalk by ~3.5 s
##
## Skippable: skip() jumps to the final state (the game calls it on any key or click). The plan is SitePlan.van
## (VanPlan): pos, yaw, crew spots, block points.
##
##   var a := VanArrival.spawn(plan.van, [wick, gasket, rebar], true)   # true = play the sequence, false = parked
##   a.finished.connect(func() -> void: controller.enabled = true)

signal landed
signal honked                        ## audio hook: play the horn here
signal door_opened
signal finished                      ## the crew is out and standing at their spots

const DURATION := 2.5                ## until the crew is out
const SETTLE_END := 3.5              ## the circle is chalk from here on
const T_IGNITE := 0.7
const T_POP := 0.8
const T_LAND := 1.06
const T_HONK := 1.22
const T_DOOR0 := 1.32
const T_DOOR1 := 1.78
const T_CREW0 := 1.55
const CREW_STAGGER := 0.15
const CREW_WALK := 0.55
const T_SETTLE0 := 2.1
const DROP_HEIGHT := 2.7
const LIGHTS_PARKED := 0.45          ## how bright the headlights stay once parked
const START_OFF: Array[float] = [0.0, 0.32, -0.32]   ## where each hero starts, along the door opening

const FLASH_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float k = 0.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	vec2 q = UV - vec2(0.5);
	float d = length(q) * 2.0;
	float core = pow(clamp(1.0 - d, 0.0, 1.0), 2.0);
	float ray = pow(abs(cos(atan(q.y, q.x) * 4.0)), 24.0) * clamp(1.0 - d, 0.0, 1.0);
	float fade = pow(clamp(1.0 - k, 0.0, 1.0), 1.5);
	ALBEDO = vec3(1.0, 0.9, 0.7) * (core * 3.5 + ray * 2.0) * fade;
	ALPHA = 1.0;
}
"""

const PUFF_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float body = smoothstep(1.0, 0.8, d);
	float rim = smoothstep(0.5, 0.95, d);
	ALBEDO = COLOR.rgb * mix(1.0, 0.74, rim);
	ALPHA = body * COLOR.a;
}
"""

static var _flash_shader: Shader
static var _puff_shader: Shader

var plan: Dictionary = {}
var van: VanModel
var circle: VanCircle
var blockers: Array[DecorBlocker] = []
var crew: Array[Hero] = []
var time := 0.0
var playing := false                 ## the timeline is running
var done := false                    ## the crew is out (finished emitted)
var settled := false                 ## the circle is chalk
var ground := 0.0
var _flash: MeshInstance3D
var _flash_mat: ShaderMaterial
var _flash_light: OmniLight3D
var _pop_smoke: CPUParticles3D
var _dust: CPUParticles3D
var _fired := {}                     ## one-shot events already fired
var _hidden_brains: Array[Node] = []


## Build the van, the circle and the blockers for `van_plan` (SitePlan.van) under `parent` (default GameWorld.root).
## play = true: start the arrival (the crew is hidden until it steps out); false: the parked final state at once.
static func spawn(van_plan: Dictionary, heroes: Array[Hero], play: bool, parent: Node = null) -> VanArrival:
	var root: Node = parent if parent != null else GameWorld.root
	if root == null or van_plan.is_empty():
		return null
	var a := VanArrival.new()
	a.plan = van_plan
	a.crew = heroes
	root.add_child(a)
	a.setup()
	if play:
		a.begin()
	else:
		a.park()
	return a


func _init() -> void:
	name = "VanArrival"


## Co-op authority (docs/design/networking.md): the van is a host-arbitrated world object planned from the floor seed
## (SitePlan.van is SPAWN: every machine derives the same pose and the same blockers) plus a purely cosmetic arrival.
## The timeline is each machine's own presentation (LOCAL); each player's machine walks its OWN hero out of the van.
func net_fields() -> Dictionary:
	return {
		"plan": Net.SPAWN, "blockers": Net.SPAWN, "ground": Net.LOCAL,
		"van": Net.LOCAL, "circle": Net.LOCAL, "crew": Net.LOCAL, "time": Net.LOCAL, "playing": Net.LOCAL,
		"done": Net.LOCAL, "settled": Net.LOCAL, "_flash": Net.LOCAL, "_flash_mat": Net.LOCAL, "_flash_light": Net.LOCAL,
		"_pop_smoke": Net.LOCAL, "_dust": Net.LOCAL, "_fired": Net.LOCAL, "_hidden_brains": Net.LOCAL,
	}


func setup() -> void:
	var pos: Vector2 = plan["pos"]
	var map := GameWorld.map
	ground = 0.0
	if map != null:
		var h := map.ground_height(Vector3(pos.x, 0.0, pos.y))
		if not is_nan(h):
			ground = h
	global_position = Vector3(pos.x, ground, pos.y)
	rotation_degrees.y = float(plan["yaw"])
	circle = VanCircle.new(float(plan["circle_radius"]))
	add_child(circle)
	van = VanModel.new()
	van.visible = false
	add_child(van)
	_make_fx()
	_make_blockers()


## The invisible circles that keep actors out of the van (the DecorBlocker the blocking decor uses).
func _make_blockers() -> void:
	var pts: Array = plan["block_points"]
	for bp: Vector2 in pts:
		var b := DecorBlocker.new()
		b.radius = float(plan["block_radius"])
		add_child(b)
		b.global_position = Vector3(bp.x, ground, bp.y)
		b.snap_to_ground()
		blockers.append(b)


func _make_fx() -> void:
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = FLASH_SHADER
	if _puff_shader == null:
		_puff_shader = Shader.new()
		_puff_shader.code = PUFF_SHADER
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = _flash_shader
	_flash = MeshInstance3D.new()
	_flash.name = "Flash"
	_flash.mesh = q
	_flash.material_override = _flash_mat
	_flash.position = Vector3(0, 1.2, 0)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)
	_flash_light = OmniLight3D.new()
	_flash_light.name = "FlashLight"
	_flash_light.position = Vector3(0, 1.6, 0)
	_flash_light.light_color = Color(1.0, 0.85, 0.6)
	_flash_light.omni_range = 9.0
	_flash_light.omni_attenuation = 1.2
	_flash_light.light_specular = 0.0
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	add_child(_flash_light)
	_pop_smoke = _puffs("PopSmoke", 16, 0.9, 1.4, 0.2, true)
	_pop_smoke.position = Vector3(0, 0.8, 0)
	_pop_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_pop_smoke.emission_sphere_radius = 1.0
	_pop_smoke.gravity = Vector3(0, 0.5, 0)
	add_child(_pop_smoke)
	_dust = _puffs("Dust", 18, 0.8, 1.1, 0.14, false)
	_dust.position = Vector3(0, 0.25, 0)
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_dust.emission_ring_axis = Vector3.UP
	_dust.emission_ring_height = 0.1
	_dust.emission_ring_radius = 1.9
	_dust.emission_ring_inner_radius = 1.4
	_dust.direction = Vector3(0, 0.05, 0)
	_dust.radial_accel_min = 2.2
	_dust.radial_accel_max = 3.4
	_dust.gravity = Vector3(0, 0.25, 0)
	add_child(_dust)


## A one-shot burst of grey-white cartoon puffs.
func _puffs(node_name: String, amount: int, life: float, size: float, speed: float, spherical: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = node_name
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0 if spherical else 20.0
	p.initial_velocity_min = speed * 6.0
	p.initial_velocity_max = speed * 12.0
	p.damping_min = 3.0
	p.damping_max = 5.0
	p.scale_amount_min = size * 0.55
	p.scale_amount_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.45))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1.0, 1.25))
	p.scale_amount_curve = curve
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var sm := ShaderMaterial.new()
	sm.shader = _puff_shader
	quad.material = sm
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.95, 0.9, 0.84, 0.9))
	ramp.set_color(1, Color(0.55, 0.52, 0.52, 0.0))
	p.color_ramp = ramp
	return p


# --------------------------------------------------------------------------- control

## Start the arrival: hide the crew and run the timeline from zero.
func begin() -> void:
	time = 0.0
	playing = true
	done = false
	settled = false
	_fired.clear()
	for h in crew:
		if is_instance_valid(h):
			h.visible = false
	_pause_brains(true)
	van.visible = false
	_pose(0.0)


## The final parked state at once, no animation (the crew is where it would end up).
func park() -> void:
	playing = false
	time = SETTLE_END
	_pose(SETTLE_END)
	_finish_crew()
	done = true
	settled = true


## Skip to the end: the van is parked, the circle chalk, the crew out. Safe to call at any time (also when done).
func skip() -> void:
	if settled and done:
		return
	var was_done := done
	playing = false
	time = SETTLE_END
	_pose(SETTLE_END)
	_flash.visible = false
	_flash_light.light_energy = 0.0
	_finish_crew()
	done = true
	settled = true
	if not was_done:
		finished.emit()


## True while the crew is still on its way out (the player has no control yet).
func is_running() -> bool:
	return playing and not done


## The crew is out and control may be handed back (finished has been emitted / the van is parked).
func is_done() -> bool:
	return done


func _process(delta: float) -> void:
	if not playing:
		return
	var prev := time
	time += delta
	_events(prev, time)
	_pose(time)
	if time >= DURATION and not done:
		_finish_crew()
		done = true
		finished.emit()
	if time >= SETTLE_END:
		playing = false
		settled = true


func _pause_brains(on: bool) -> void:
	if on:
		_hidden_brains.clear()
		for h in crew:
			if is_instance_valid(h):
				var brain := h.get_node_or_null("AllyBrain")
				if brain != null:
					brain.set_physics_process(false)
					_hidden_brains.append(brain)
	else:
		for brain in _hidden_brains:
			if is_instance_valid(brain):
				brain.set_physics_process(true)
		_hidden_brains.clear()


func _finish_crew() -> void:
	var n3 := _out_dir()
	for i in crew.size():
		var h := crew[i]
		if not is_instance_valid(h):
			continue
		h.visible = true
		if i < (plan["crew"] as Array).size():
			_place_hero(h, (plan["crew"] as Array)[i])
		h.facing = n3
	_pause_brains(false)


## World direction pointing out of the door (X/Z unit vector as Vector3).
func _out_dir() -> Vector3:
	var n: Vector2 = plan["door_normal"]
	return Vector3(n.x, 0.0, n.y)


func _place_hero(h: Hero, spot: Vector2) -> void:
	var y := ground
	if GameWorld.map != null:
		var g := GameWorld.map.ground_height(Vector3(spot.x, 0.0, spot.y))
		if not is_nan(g):
			y = g
	h.global_position = Vector3(spot.x, y, spot.y)


# --------------------------------------------------------------------------- one-shot events

func _events(prev: float, now: float) -> void:
	if _crossed(prev, now, T_POP, "pop"):
		_flash.visible = true
		_pop_smoke.restart()
		_pop_smoke.emitting = true
		Fx.shake(0.18)
	if _crossed(prev, now, T_LAND, "land"):
		_dust.restart()
		_dust.emitting = true
		Fx.shake(0.4)
		landed.emit()
	if _crossed(prev, now, T_HONK, "honk"):
		honked.emit()
	if _crossed(prev, now, T_DOOR0, "door"):
		door_opened.emit()


func _crossed(prev: float, now: float, at: float, key: String) -> bool:
	if _fired.has(key) or now < at or prev > at + 0.5:
		return false
	_fired[key] = true
	return true


# --------------------------------------------------------------------------- the timeline

static func _ease_out(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - u) * (1.0 - u) * (1.0 - u)


static func _ease_in_out(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## Everything as a function of the time since the start.
func _pose(t: float) -> void:
	_pose_circle(t)
	_pose_van(t)
	_pose_fx(t)
	_pose_crew(t)


func _pose_circle(t: float) -> void:
	var ign := _ease_in_out(t / T_IGNITE)
	var since_pop := t - T_POP
	var pulse := 0.0
	if since_pop >= 0.0:
		pulse = exp(-since_pop * 3.2)
	var settle_k := _ease_in_out((t - T_SETTLE0) / (SETTLE_END - T_SETTLE0))
	var glow := (0.2 + 1.0 * ign + 0.9 * pulse) * (1.0 - settle_k)
	var flare := (0.35 * ign + 0.9 * pulse) * (1.0 - settle_k)
	circle.set_figure(ign, glow, settle_k, flare)
	var col := _ease_in_out((t - 0.25) / 0.55) * (1.0 - _ease_in_out((t - 1.35) / 0.6))
	circle.set_column(col * (0.7 + 0.5 * pulse))
	circle.set_light((0.35 * ign + 1.0 * pulse + 0.5 * col) * (1.0 - settle_k))
	circle.sparks(t > 0.08 and t < 1.9)
	var shock_t := (t - T_LAND) / 0.55
	circle.set_shock(shock_t if shock_t > 0.0 and shock_t < 1.0 else 0.0)


func _pose_van(t: float) -> void:
	if t < T_POP:
		van.visible = false
		return
	van.visible = true
	var u := clampf((t - T_POP) / (T_LAND - T_POP), 0.0, 1.0)
	var tau := maxf(t - T_LAND, 0.0)
	var y := DROP_HEIGHT * (1.0 - u * u)
	var sc := Vector3.ONE
	if t < T_LAND:
		# materialises as a tall, thin streak and fattens as it falls
		var k := u * u
		sc = Vector3(lerpf(0.55, 1.0, k), lerpf(1.75, 1.0, k), lerpf(0.55, 1.0, k))
	else:
		# a quick squash on touchdown, then the suspension rocks the chassis
		var squash := exp(-tau * 13.0)
		sc = Vector3(1.0 + 0.1 * squash, 1.0 - 0.2 * squash, 1.0 + 0.1 * squash)
	van.position = Vector3(0, y, 0)
	van.scale = sc
	var spring := exp(-tau * 5.0) * cos(tau * 15.0) if t >= T_LAND else 0.0
	van.set_bounce(-0.13 * spring, 0.035 * exp(-tau * 4.5) * sin(tau * 11.0) if t >= T_LAND else 0.0)
	# headlights: off, two flashes with the honks, then on and dimming to the parked glow
	var lights := 0.0
	if t >= T_HONK:
		var h := t - T_HONK
		var blink := 1.0 if (h < 0.12 or (h > 0.2 and h < 0.34)) else 0.1
		var settle := _ease_in_out((t - 2.3) / 0.9)
		lights = lerpf(1.0, LIGHTS_PARKED, settle) if h > 0.34 else blink
	van.set_lights(lights)
	van.set_door_open(_ease_out((t - T_DOOR0) / (T_DOOR1 - T_DOOR0)))


func _pose_fx(t: float) -> void:
	var f := (t - T_POP) / 0.4
	if f >= 0.0 and f < 1.0:
		_flash.visible = true
		_flash.scale = Vector3.ONE * lerpf(2.5, 11.0, sqrt(f))
		_flash_mat.set_shader_parameter("k", f)
		_flash_light.light_energy = 16.0 * pow(1.0 - f, 2.0)
	else:
		_flash.visible = false
		_flash_light.light_energy = 0.0


func _pose_crew(t: float) -> void:
	var spots: Array = plan["crew"]
	var yaw: float = plan["yaw"]
	var pos: Vector2 = plan["pos"]
	for i in crew.size():
		var h := crew[i]
		if not is_instance_valid(h) or i >= spots.size():
			continue
		var t0 := T_CREW0 + CREW_STAGGER * float(i)
		var from := ThemeGeo.local_to_world(pos, yaw, -0.4, VanPlan.DOOR_Z + START_OFF[i % START_OFF.size()])
		if t < t0:
			h.visible = false
			_place_hero(h, from)      # waiting inside the van
			continue
		h.visible = true
		var u := clampf((t - t0) / CREW_WALK, 0.0, 1.0)
		var to: Vector2 = spots[i]
		_place_hero(h, from.lerp(to, _ease_out(u)))
		var d := to - from
		if u < 1.0 and d.length() > 0.01:
			h.facing = Vector3(d.x, 0.0, d.y).normalized()
		else:
			h.facing = _out_dir()
