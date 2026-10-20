class_name Headshots
extends Node
## Head-and-shoulders pictures of the crew's and the employees' models for the party HUD's round portraits, rendered
## ONCE per look and kept for the rest of the process (`_cache`, static: floors and contracts reuse them).
##
##   var tex := headshots.texture("hero:wick")          # null until it is rendered; `rendered(key)` fires then
##   var tex := headshots.texture("emp:henchman:3")      # an employee's model, by style and variant
##
## Each picture is one SubViewport with its own 3D world: the model in its rest pose (idle off), a key light, a soft fill
## and a camera framed on the model's `head` part (its mesh bounds, so every hero and employee is framed the same way: a
## three-quarter view from the front, slightly above). One render at a time, a frame or two each; the viewport is freed
## as soon as the image is read. Nothing renders headless (tests, the dedicated runs): `texture()` stays null and the
## HUD draws the lettered bubble instead.
##
## Pure presentation, LOCAL to each machine.

signal rendered(key: String)

const SIZE := 160                  ## pixels (square); the HUD draws it at 22..76 canvas units
const FOV := 26.0
const PAD := 1.75                  ## the head's bounds times this fill the frame (room for hair, hats, shoulders)
const VIEW_DIR := Vector3(0.42, 0.22, -1.0)   ## from the head toward the camera (models face -Z): three-quarter, a bit above

static var _cache: Dictionary = {}     ## key -> Texture2D

var _queue: Array[String] = []
var _busy := false


func _init() -> void:
	name = "Headshots"


## The picture for `key` ("hero:<kit>" or "emp:<style>:<variant>"), or null while it is rendered (or can't be: headless).
func texture(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	if not can_render() or not known(key):
		return null
	if not _queue.has(key):
		_queue.append(key)
	_pump.call_deferred()
	return null


static func cached(key: String) -> Texture2D:
	return _cache.get(key)


## Stand a picture in for `key` (tests; the dev stage's stand-in pictures).
static func put(key: String, tex: Texture2D) -> void:
	_cache[key] = tex


static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


## Does `key` name a model this class can picture?
static func known(key: String) -> bool:
	var bits := key.split(":")
	if bits.size() >= 2 and bits[0] == "hero":
		return ["wick", "rebar", "gasket"].has(bits[1])
	return bits.size() >= 3 and bits[0] == "emp"


func _pump() -> void:
	if _busy or _queue.is_empty() or not is_inside_tree():
		return
	_busy = true
	var key: String = _queue.pop_front()
	if not _cache.has(key):
		await _render(key)
	_busy = false
	if not _queue.is_empty():
		_pump.call_deferred()


func _render(key: String) -> void:
	var model := _make_model(key)
	if model == null:
		return
	var vp := SubViewport.new()
	vp.name = "Shot"
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(SIZE, SIZE)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.9)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	vp.add_child(env)
	if "idle_enabled" in model:
		model.set("idle_enabled", false)   # (the rest pose: every shot the same)
	vp.add_child(model)
	var key_light := DirectionalLight3D.new()
	key_light.light_energy = 1.15
	vp.add_child(key_light)
	key_light.look_at_from_position(Vector3(1.5, 3.0, -2.5), Vector3.ZERO)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	vp.add_child(fill)
	fill.look_at_from_position(Vector3(-2.0, 1.0, -1.0), Vector3.ZERO)
	var cam := Camera3D.new()
	cam.fov = FOV
	cam.near = 0.05
	vp.add_child(cam)
	await get_tree().process_frame   # (the parts are placed once the model is in the tree)
	var box := _head_box(model)
	var center := box.get_center()
	var reach := maxf(box.size.x, box.size.y) * PAD * 0.5
	var dist := reach / tan(deg_to_rad(FOV * 0.5))
	cam.look_at_from_position(center + VIEW_DIR.normalized() * dist, center)
	cam.current = true
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image() if vp.get_texture() != null else null
	if img != null and not img.is_empty():
		_cache[key] = ImageTexture.create_from_image(img)
	vp.queue_free()
	if _cache.has(key):
		rendered.emit(key)


## The head part's bounds in world space (its own mesh: the hair, hats and helmets hanging under it are left out so a tall
## hat doesn't shrink the face).
static func _head_box(model: Node3D) -> AABB:
	var head: MeshInstance3D = null
	if model.has_method("get_part"):
		head = model.call("get_part", "head") as MeshInstance3D
	if head == null or head.mesh == null:
		return AABB(Vector3(-0.3, 1.2, -0.3), Vector3(0.6, 0.6, 0.6))
	return head.global_transform * head.mesh.get_aabb()


## A fresh model for `key`, or null for a key nobody knows.
static func _make_model(key: String) -> Node3D:
	var bits := key.split(":")
	if bits.size() >= 2 and bits[0] == "hero":
		match bits[1]:
			"wick":
				return WickModel.new()
			"rebar":
				return RebarModel.new()
			"gasket":
				return GasketModel.new()
		return null
	if bits.size() >= 3 and bits[0] == "emp":
		return EmployeeModel.new(bits[1], int(bits[2]))
	return null
