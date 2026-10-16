extends Node3D
## Terrain preview: generates a dungeon, builds the view, lights it, frames it.
## User args (after `--`): --seed N, --shot <abs.png>, --size N (ortho size), --focus q,r
## Also --nowalls hides the wall rim. Keys: R new seed, mouse wheel zoom, WASD / arrows pan.

const YAW := 45.0
const PITCH := -55.0

var seed_value := 1
var shot_path := ""
var size_override := 0.0
var focus_override := Vector2i(1 << 20, 0)
var no_walls := false
var focus_arg := ""   # "q,r", "stairs" (Nth: stairs2), "start" or "exit"
var map: HexMap
var view: HexMapView
var cam: Camera3D
var label: Label
var _frames := 0
var _center := Vector3.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--seed")
	if i >= 0 and i + 1 < args.size():
		seed_value = int(args[i + 1])
	i = args.find("--shot")
	if i >= 0 and i + 1 < args.size():
		shot_path = args[i + 1]
	i = args.find("--size")
	if i >= 0 and i + 1 < args.size():
		size_override = float(args[i + 1])
	no_walls = args.has("--nowalls")
	i = args.find("--focus")
	if i >= 0 and i + 1 < args.size():
		focus_arg = args[i + 1]
	_setup_world()
	_regenerate()


func _setup_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.045, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.82)
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 220.0
	add_child(sun)
	# light travels toward -x, -y, -z-ish so the faces turned to the camera get two different brightnesses
	sun.look_at_from_position(Vector3(40, 80, 55), Vector3.ZERO)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 1.0
	cam.far = 400.0
	cam.rotation_degrees = Vector3(PITCH, YAW, 0.0)
	add_child(cam)

	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	label.position = Vector2(12, 8)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	layer.add_child(label)


func _regenerate() -> void:
	if view != null:
		view.queue_free()
	var t0 := Time.get_ticks_usec()
	map = DungeonGen.generate(seed_value)
	var t1 := Time.get_ticks_usec()
	var shown := map
	if no_walls:   # debugging aid: strip the rim so interior detail is visible from the iso camera
		shown = HexMap.new()
		for c in map.cells:
			if map.cells[c].type != HexMap.Tile.WALL:
				shown.cells[c] = map.cells[c]
	view = HexMapView.new()
	add_child(view)
	view.build(shown)
	var t2 := Time.get_ticks_usec()
	label.text = "seed %d | gen %.0f ms | view %.0f ms | %d cells, %d tris   [R] new seed  [wheel] zoom  [WASD] pan" % [
		seed_value, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, map.cells.size(), view.stats.get("triangles", 0)]
	print("seed ", seed_value, " ", label.text)
	_frame_camera()


func _frame_camera() -> void:
	var basis := cam.global_transform.basis
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var sum := Vector3.ZERO
	var count := 0
	for c in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type == HexMap.Tile.WALL:
			continue
		var p := Hex.to_world(c, cell.level)
		sum += p
		count += 1
	var mean := sum / maxf(1.0, count)
	for c in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		var p := Hex.to_world(c, cell.level) - mean
		var sx := p.dot(basis.x)
		var sy := p.dot(basis.y)
		lo = Vector2(minf(lo.x, sx), minf(lo.y, sy))
		hi = Vector2(maxf(hi.x, sx), maxf(hi.y, sy))
	_center = mean + basis.x * (lo.x + hi.x) * 0.5 + basis.y * (lo.y + hi.y) * 0.5
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var size := maxf((hi.y - lo.y) + 4.0, (hi.x - lo.x) / aspect + 4.0)
	cam.size = clampf(size, 14.0, 120.0)
	if focus_arg != "":
		_resolve_focus()
	if focus_override.x != 1 << 20:
		var fc := map.get_cell(focus_override)
		_center = Hex.to_world(focus_override, fc.level if fc != null else 0)
	if size_override > 0.0:
		cam.size = size_override
	_place_camera()


func _resolve_focus() -> void:
	if focus_arg.contains(","):
		var parts := focus_arg.split(",")
		focus_override = Vector2i(int(parts[0]), int(parts[1]))
	elif focus_arg.begins_with("stairs"):
		var want := maxi(1, int(focus_arg.substr(6)))
		var n := 0
		for c in map.cells:
			if map.cells[c].type == HexMap.Tile.STAIRS:
				n += 1
				focus_override = c
				if n == want:
					break
	elif map.cells_with_tag(focus_arg).size() > 0:
		focus_override = map.cells_with_tag(focus_arg)[0]


func _place_camera() -> void:
	cam.global_position = _center + cam.global_transform.basis.z * 150.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		seed_value += 1
		_regenerate()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.size = maxf(6.0, cam.size * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.size = minf(160.0, cam.size * 1.1)


func _process(delta: float) -> void:
	var pan := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan -= cam.global_transform.basis.z
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan += cam.global_transform.basis.z
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan -= cam.global_transform.basis.x
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan += cam.global_transform.basis.x
	pan.y = 0.0
	if pan != Vector3.ZERO:
		_center += pan.normalized() * cam.size * 0.6 * delta
		_place_camera()
	if shot_path != "":
		_frames += 1
		if _frames == 10:
			_save_shot()


func _save_shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(shot_path)
	print("shot saved ", shot_path, " err=", err)
	get_tree().quit()
