extends Node3D
## Work-van lab: the real terrain look (HexMapView + DungeonLook) with the crew's van arriving over its summoning
## circle, Wick, Gasket and Rebar stepping out beside it. Scene: scenes/van_lab.tscn.
##
##   godot --path . -- --scene res://scenes/van_lab.tscn --shot <abs.png> [--t 1.4] [--view game]
##
## --shot <png>   render and quit. Without --t the van is parked (the final state); with --t <seconds> the arrival
##                is played in real time and the shot is taken when it reaches that moment (0..3.5)
## --t <s>        moment of the arrival to capture (see VanArrival: 0.4 circle igniting, 0.85 pop, 1.1 landing,
##                1.5 door opening, 2.0 crew stepping out, 3.5 settled)
## --view <name>  game (default: the real game camera, yaw 45 pitch -56, ortho size 14), close (size 8), far (size 24, the
##                zoom the game starts at), side (the door side) / other / rear / front / top (the van alone, size 6, from that side)
## --yaw/--pitch/--size   override the camera;  --van-yaw <deg>  turn the van (default 135: the door faces the camera)
## --no-crew      leave the heroes out
## --door <0..1>  force the sliding door (0 closed, 1 open) on a parked (no --t) van, to inspect either state
## No --shot: the arrival replays every 8 seconds.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0

var shot_path := ""
var view := "game"
var at_t := NAN
var cam_yaw := NAN
var cam_pitch := NAN
var cam_size := NAN
var van_yaw := 135.0
var with_crew := true
var door_override := NAN
var map: HexMap
var camera: Camera3D
var arrival: VanArrival
var crew: Array[Hero] = []
var _plan: Dictionary = {}
var _cycle := 0.0
var _shot_done := false


func _ready() -> void:
	_parse_args()
	_build_world()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 200.0
	add_child(camera)
	_spawn_crew()
	_start()
	_set_view()


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	shot_path = _arg(a, "--shot")
	view = _arg(a, "--view", "game")
	if _arg(a, "--t") != "":
		at_t = float(_arg(a, "--t"))
	if _arg(a, "--yaw") != "":
		cam_yaw = float(_arg(a, "--yaw"))
	if _arg(a, "--pitch") != "":
		cam_pitch = float(_arg(a, "--pitch"))
	if _arg(a, "--size") != "":
		cam_size = float(_arg(a, "--size"))
	if _arg(a, "--van-yaw") != "":
		van_yaw = float(_arg(a, "--van-yaw"))
	with_crew = not a.has("--no-crew")
	if _arg(a, "--door") != "":
		door_override = float(_arg(a, "--door"))


static func _arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := a.find(key)
	if i >= 0 and i + 1 < a.size():
		return a[i + 1]
	return fallback


func _build_world() -> void:
	map = HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 20):
		var d := Hex.distance(c, Vector2i.ZERO)
		if d <= 11:
			map.set_cell(c, 0).tag = "room:0"
		elif d <= 16:
			map.set_cell(c, 6, HexMap.Tile.WALL)
	GameWorld.begin(map, self, 3)
	var terrain := HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)


func _make_plan() -> Dictionary:
	var p := SitePlan.new()
	p.start_room = "room:0"
	var pos := Vector2.ZERO
	return VanPlan._make(pos, van_yaw, VanPlan._crew_spots(pos, van_yaw, VanPlan.STEP_OUTS[0]), p, 0)


func _spawn_crew() -> void:
	_plan = _make_plan()
	if not with_crew:
		return
	var spots: Array = _plan["crew"]
	var kinds: Array = [["Wick", Color(0.3, 0.55, 0.95), WickModel, HeroKit.WICK], ["Gasket", Color(0.7, 0.4, 0.85), GasketModel, HeroKit.GASKET], ["Rebar", Color(0.85, 0.5, 0.25), RebarModel, HeroKit.REBAR]]
	for i in 3:
		var k: Array = kinds[i]
		var sp: Vector2 = spots[i]
		var h := HeroFactory.spawn_hero(Hex.from_world(Vector3(sp.x, 0, sp.y)), str(k[0]), k[1], "sword", (k[2] as GDScript).new(), str(k[3]))
		crew.append(h)


func _start() -> void:
	# a shot without --t shows the parked van; --t (or no --shot at all) plays the arrival
	var play := shot_path == "" or not is_nan(at_t)
	arrival = VanArrival.spawn(_plan, crew, play)
	if not play and not is_nan(door_override):
		arrival.van.set_door_open(door_override)
	if shot_path != "":
		_run_shot()


func _aim(yaw_deg: float, pitch_deg: float, size: float, tgt: Vector3) -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	camera.size = size
	camera.global_position = tgt + Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * 60.0
	camera.look_at(tgt, Vector3.UP)


func _set_view() -> void:
	var tgt := Vector3(0, 0.6, 0)
	var yaw := GAME_YAW
	var pitch := GAME_PITCH
	var size := 14.0
	match view:
		"close":
			size = 8.0
		"far":
			size = 24.0
		"side":     # the door side
			yaw = ThemeGeo.yaw_of(-ThemeGeo.lateral(van_yaw))
			pitch = -12.0
			size = 6.5
		"other":    # the banner side
			yaw = ThemeGeo.yaw_of(ThemeGeo.lateral(van_yaw))
			pitch = -12.0
			size = 6.5
		"rear":
			yaw = ThemeGeo.yaw_of(-ThemeGeo.facing(van_yaw)) + 25.0
			pitch = -14.0
			size = 6.5
		"front":
			yaw = ThemeGeo.yaw_of(ThemeGeo.facing(van_yaw)) - 25.0
			pitch = -14.0
			size = 6.5
		"top":
			pitch = -88.0
			size = 7.0
	if not is_nan(cam_yaw):
		yaw = cam_yaw
	if not is_nan(cam_pitch):
		pitch = cam_pitch
	if not is_nan(cam_size):
		size = cam_size
	_aim(yaw, pitch, size, tgt)


func _run_shot() -> void:
	if is_nan(at_t):
		for i in 30:
			await get_tree().process_frame
	else:
		while arrival.time < at_t:
			await get_tree().process_frame
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("shot ", shot_path, " ", img.save_png(shot_path), " at arrival time ", arrival.time)
	get_tree().quit()


func _process(delta: float) -> void:
	if shot_path != "":
		return
	_cycle += delta
	if _cycle > 8.0:
		_cycle = 0.0
		for h in crew:
			h.visible = false
		arrival.queue_free()
		arrival = VanArrival.spawn(_plan, crew, true)
