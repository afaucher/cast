extends Node3D
## Visual lab for the four monster kinds on a flat hex patch under the iso camera.
##   godot --path . -- --scene res://scenes/monster_preview.tscn [--shot <abs png>] [--windup] [--hurt]
## --shot saves a screenshot after ~10 frames and quits; --windup freezes every
## monster in its attack telegraph; --hurt shows the HP bars.

var _shot_path := ""
var _frames := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var si := args.find("--shot")
	if si >= 0 and si + 1 < args.size():
		_shot_path = args[si + 1]
	var windup := args.has("--windup")
	var hurt := args.has("--hurt")

	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 7):
		map.set_cell(c, 0)
	GameWorld.begin(map, self, 1)
	_build_floor(map)
	_build_stage()

	var lineup := [
		["grunt", Vector2i(-3, 1)],
		["archer", Vector2i(-1, 0)],
		["brute", Vector2i(1, 0)],
		["swarmer", Vector2i(3, -1)],
		["swarmer", Vector2i(3, 0)],
		["swarmer", Vector2i(2, 1)],
	]
	var monsters: Array[Monster] = []
	for e in lineup:
		var m := MonsterFactory.spawn(e[0], e[1])
		m.facing = Vector3(0.45, 0.0, 1.0).normalized()     # face the camera-ish
		monsters.append(m)
	await get_tree().physics_frame
	for m in monsters:
		m.set_physics_process(false)     # hold them still
		m._visual.rotation.y = atan2(-m.facing.x, -m.facing.z)
		if hurt:
			m.apply_damage(m.max_hp * 0.4, null)
		if windup:
			m._telegraph = 0.85
			m._begin_windup(1.0)
			m._telegraph = 0.85
			m._update_visual(0.016)
			m._telegraph = 0.85
			m._update_visual(0.016)


func _build_floor(map: HexMap) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.44, 0.4)
	var mat2 := StandardMaterial3D.new()
	mat2.albedo_color = Color(0.36, 0.38, 0.35)
	var mesh := CylinderMesh.new()
	mesh.top_radius = Hex.SIZE * 0.97
	mesh.bottom_radius = Hex.SIZE * 0.97
	mesh.height = 0.2
	mesh.radial_segments = 6
	mesh.rings = 1
	for c in map.cells:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat if (c.x + c.y) % 2 == 0 else mat2
		mi.position = Hex.to_world(c) + Vector3.DOWN * 0.1
		mi.rotation_degrees.y = 30.0
		add_child(mi)


func _build_stage() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.09, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.7)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 10.0
	cam.rotation_degrees = Vector3(-55.0, 45.0, 0.0)
	cam.position = cam.basis * Vector3(0, 0, 20) + Vector3(0, 0.8, 0.5)
	add_child(cam)
	cam.make_current()


func _process(_delta: float) -> void:
	_frames += 1
	if _shot_path != "" and _frames == 10:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("saved ", _shot_path)
		get_tree().quit()
