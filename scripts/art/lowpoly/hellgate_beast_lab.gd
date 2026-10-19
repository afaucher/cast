extends Node3D
## Hellgate beast options lab (look-dev, nothing here is in the game): a REAL generated floor (DungeonGen.for_run,
## SiteBuilder plan + spawn, HexMapView, DungeonLook, the grime layer) with the crew standing in a hellgate's room and
## the monster under the level (HellgateBeast) built around that room in one of its styles. Monsters are removed so
## the room reads. Scene: scenes/hellgate_beast_lab.tscn.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/hellgate_beast_lab.tscn [--style abyss]
##         [--seed 7] [--arch guru] [--floor 1] [--gate 0] [--shot <dir/prefix>] [--styles a,b] [--views game,wide]
##         [--motion abyss,roots] [--t 1.7] [--zfight]
##
## --style    abyss | cracks | peek | roots | none (interactive start style)
## --floor 3  the origin floor: the room of the ORIGIN gate (the bigger version of each style)
## --shot     renders and writes <prefix>_<style>_<view>.png for every style in --styles (default all four) and every
##            view in --views (default game, wide), then <prefix>_<style>_motion_a/b.png for each style in --motion, and quits.
##              game    the game camera (ortho yaw 45, pitch -56, size 24 = the default zoom) on the crew
##              wide    size 36 (the farthest the player can zoom out) on the room's centre
##              close   size 14 on the gate
##              spot    size 10 on the style's focus (the eye, where the first tentacle comes out from under the slab)
##              low     a low three-quarter view (yaw 25, pitch -24, size 30) on the room: the cliffs and the tentacles
##                      climbing them from under the level
## --t        the animation time the shots are frozen at (gate and beast together; default 1.7)
## --zfight   run ZFightCheck on every style (its own pieces, and against the real terrain) and print the findings
## Interactive (no --shot): 1-4 pick a style, 0 none, C closes / reopens the gate (the beast sinks), Q / E zoom, WASD pan.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const WIDE_SIZE := 36.0

var seed_value := 7
var archetype := "guru"
var floor_n := 1
var gate_index := 0
var style := "abyss"
var shot_prefix := ""
var t_shot := 1.7

var run: ContractRun
var map: HexMap
var plan: SitePlan
var site: SiteBuilder.Site
var view: HexMapView
var gate: Hellgate
var room_tag := ""
var room_cells: Array[Vector2i] = []
var avoid: Array[Vector2] = []
var beast: HellgateBeast = null
var camera: Camera3D
var crew_center := Vector3.ZERO
var room_center := Vector3.ZERO
var _cam_target := Vector3.ZERO
var _cam_size := GAME_SIZE
var _closing := false
var _close_k := 0.0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	seed_value = int(_arg(a, "--seed", "7"))
	archetype = _arg(a, "--arch", "guru")
	floor_n = clampi(int(_arg(a, "--floor", "1")), 1, ContractRun.FLOOR_COUNT)
	gate_index = int(_arg(a, "--gate", "0"))
	style = _arg(a, "--style", "abyss")
	shot_prefix = _arg(a, "--shot")
	t_shot = float(_arg(a, "--t", "1.7"))
	_build_floor()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 220.0
	add_child(camera)
	camera.make_current()
	_place_crew()
	_set_style(style)
	_cam_target = crew_center
	_aim(GAME_SIZE, crew_center)
	if a.has("--zfight"):
		_run_zfight()
	elif shot_prefix != "":
		_run_shots(a)


static func _arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := a.find(key)
	if i >= 0 and i + 1 < a.size():
		return a[i + 1]
	return fallback


func _build_floor() -> void:
	run = ContractRun.make(archetype, seed_value, 0.6)
	map = DungeonGen.for_run(run, floor_n)
	plan = SiteBuilder.plan(map, run, floor_n, ContractParts.prop_catalog(run.site_type))
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	GameWorld.begin(map, world, run.floor_seed(floor_n))
	view = HexMapView.new()
	view.name = "Terrain"
	add_child(view)
	view.build(map)
	DungeonLook.apply(self, map)
	site = SiteBuilder.spawn(map, run, plan)
	GrimeLayer.attach(self, map, plan, run.floor_seed(floor_n))
	# no monsters: the room should read; nothing walks
	for m in site.monsters:
		if is_instance_valid(m):
			m.free()
	for m in site.scouts:
		if is_instance_valid(m):
			m.free()
	for e in site.employees:
		e.set_physics_process(false)
	for g in site.gates:
		g.set_physics_process(false)
	var gi := clampi(gate_index, 0, maxi(site.gates.size() - 1, 0))
	if floor_n >= ContractRun.FLOOR_COUNT and site.origin_gate != null:
		gate = site.origin_gate as Hellgate
		room_tag = plan.origin_room
	else:
		gate = site.gates[gi] as Hellgate
		room_tag = str(plan.gates[gi]["room"])
	gate.model.set_active(true)
	room_cells.assign(plan.rooms[room_tag])
	room_center = Hex.to_world(plan.centers[room_tag], float(plan.base_levels[room_tag]))
	for pr in plan.props:
		if pr.has("pos"):
			avoid.append(pr["pos"])
	for d in plan.decor:
		avoid.append(d["pos"])
	print("lab: seed %d %s floor %d  gate %s in %s (%s, %d cells)  %d gates" % [seed_value, archetype, floor_n,
			str(Hex.from_world(gate.global_position)), room_tag, plan.theme_of(room_tag), room_cells.size(), site.gates.size()])


## The crew a few cells from the gate, on the camera's side of it, looking at it.
func _place_crew() -> void:
	var gc := Hex.from_world(gate.global_position)
	var cands: Array[Vector2i] = []
	var near := 4 if gate.origin else 3
	for c in room_cells:
		var d := Hex.distance(c, gc)
		if d >= near and d <= near + 1 and map.is_walkable_cell(c):
			cands.append(c)
	var cam := Vector3(0.7071, 0, 0.7071)
	cands.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		return (Hex.to_world(p) - gate.global_position).normalized().dot(cam) > (Hex.to_world(q) - gate.global_position).normalized().dot(cam))
	var models: Array[LowPolyModel] = [WickModel.new(), GasketModel.new(), RebarModel.new()]
	var sum := Vector3.ZERO
	var placed := 0
	var used: Array[Vector2i] = []
	for m in models:
		var cell := gc
		for c in cands:
			var ok := true
			for u in used:
				if Hex.distance(u, c) < 2:
					ok = false
			if ok:
				cell = c
				break
		used.append(cell)
		add_child(m)
		m.idle_enabled = false
		m.apply_idle(0.6)
		var cl := map.get_cell(cell)
		m.global_position = Hex.to_world(cell, float(cl.level))
		var to_gate := gate.global_position - m.global_position
		m.rotation.y = atan2(to_gate.x, to_gate.z)
		sum += m.global_position
		placed += 1
	crew_center = sum / maxf(placed, 1) + Vector3(0, CameraRig.FOCUS_HEIGHT, 0)


func _set_style(s: String) -> void:
	if beast != null:
		beast.free()
		beast = null
	style = s
	if s == "none" or not HellgateBeast.STYLES.has(s):
		return
	var t0 := Time.get_ticks_usec()
	var seed_v := hash(Vector3i(Hex.from_world(gate.global_position).x, Hex.from_world(gate.global_position).y, run.floor_seed(floor_n)))
	beast = HellgateBeast.make(s, map, room_cells, gate.global_position, gate.origin, seed_v, avoid)
	add_child(beast)
	beast.set_gate(gate.model)
	print("beast %s%s: %s  built in %.1f ms" % [s, " (origin)" if gate.origin else "", str(beast.stats), (Time.get_ticks_usec() - t0) / 1000.0])


func _aim(size: float, tgt: Vector3, yaw_deg: float = GAME_YAW, pitch_deg: float = GAME_PITCH) -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	camera.size = size
	camera.global_position = tgt + Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * 60.0
	camera.look_at(tgt, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if shot_prefix != "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1:
				_set_style("abyss")
			KEY_2:
				_set_style("cracks")
			KEY_3:
				_set_style("peek")
			KEY_4:
				_set_style("roots")
			KEY_0:
				_set_style("none")
			KEY_C:
				_closing = not _closing
			KEY_Q:
				_cam_size = clampf(_cam_size * 1.1, 8.0, 48.0)
			KEY_E:
				_cam_size = clampf(_cam_size / 1.1, 8.0, 48.0)


func _process(delta: float) -> void:
	if shot_prefix != "":
		return
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		mv += Vector3(-1, 0, -1)
	if Input.is_key_pressed(KEY_S):
		mv += Vector3(1, 0, 1)
	if Input.is_key_pressed(KEY_A):
		mv += Vector3(-1, 0, 1)
	if Input.is_key_pressed(KEY_D):
		mv += Vector3(1, 0, -1)
	_cam_target += mv.normalized() * delta * 10.0 if mv != Vector3.ZERO else Vector3.ZERO
	_aim(_cam_size, _cam_target)
	_close_k = move_toward(_close_k, 1.0 if _closing else 0.0, delta * 0.6)
	if beast != null:
		beast.set_close(_close_k)


# ------------------------------------------------------------------ shots

func _snap(path: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("shot ", path, " ", img.save_png(path))


func _freeze(t: float) -> void:
	gate.model.freeze_at(t)
	if beast != null:
		beast.freeze_at(t)


func _run_shots(a: PackedStringArray) -> void:
	for i in 10:
		await get_tree().process_frame
	var styles: Array = Array(_arg(a, "--styles", ",".join(HellgateBeast.STYLES)).split(",", false))
	var views: Array = Array(_arg(a, "--views", "game,wide").split(",", false))
	var motion: Array = Array(_arg(a, "--motion", "").split(",", false))
	for s: String in styles:
		_set_style(s)
		_freeze(t_shot)
		for v: String in views:
			match v:
				"game":
					_aim(GAME_SIZE, crew_center)
				"wide":
					_aim(WIDE_SIZE, room_center + Vector3(0, 0.8, 0))
				"close":
					_aim(14.0, gate.global_position + Vector3(0, 1.0, 0))
				"low":
					_aim(30.0, room_center + Vector3(0, -0.5, 0), 25.0, -24.0)
				"spot":
					var focus := gate.global_position
					if beast != null and beast.focus != Vector3.ZERO:
						focus = beast.focus
					_aim(10.0, focus)
			await _snap("%s_%s_%s.png" % [shot_prefix, s, v])
	for s: String in motion:
		_set_style(s)
		_aim(GAME_SIZE, crew_center)
		_freeze(t_shot)
		await _snap("%s_%s_motion_a.png" % [shot_prefix, s])
		_freeze(t_shot + 1.6)
		await _snap("%s_%s_motion_b.png" % [shot_prefix, s])
	get_tree().quit()


# ------------------------------------------------------------------ z-fighting

func _run_zfight() -> void:
	await get_tree().process_frame
	for s in HellgateBeast.STYLES:
		_set_style(s)
		await get_tree().process_frame
		var own := ZFightCheck.TriSet.new()
		for ch in beast.get_children():
			if ch is Node3D:
				own.add_node(ch, own.add_item("%s/%s" % [s, ch.name]), (ch as Node3D).global_transform)
		var f_own := own.find(false)
		var ts := ZFightCheck.TriSet.new()
		ts.add_node(beast, ts.add_item("beast/" + s), beast.global_transform)
		ts.add_node(view, ts.add_item("terrain", true), view.global_transform)
		ts.trim_terrain()
		var f_ter := ts.find(true)
		print("zfight %s: %d own findings, %d against the terrain" % [s, f_own.size(), f_ter.size()])
		for f in f_own.slice(0, 6):
			print("   own  ", ZFightCheck.describe(f))
		for f in f_ter.slice(0, 6):
			print("   ter  ", ZFightCheck.describe(f))
	get_tree().quit()
