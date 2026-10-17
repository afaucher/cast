extends Node3D
## Look-dev lab for the "teeth" spell effect (TeethFx): the three heroes and a few monsters stand on
## a slate hex patch (HexMapView + DungeonLook) and are all afflicted at once, with staggered grow times.
##
##   godot --path . -- --scene res://scenes/teeth_lab.tscn --view close --at 0.6 --shot <abs png>
##
## --shot <png>   deterministic: time is stepped by hand to --at seconds, one frame is saved, then quit.
## --at <sec>     the moment to capture (default 0.6)
## --view game|close   game = the exact game camera (yaw 45, pitch -56, ortho 24); close = ortho ~7
##                on Dagna and the grunt (override with --yaw / --pitch / --size)
## --grow <sec>   give every victim the same grow time instead of the staggered 1.0 .. 2.0 s
## --seed <n>     tooth layout seed (default 7)
## --cancel <sec> heal everyone at that time (cancel()) instead of letting them pop
## No --shot: realtime loop, everyone is afflicted again every few seconds, orbiting slowly.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0

## name -> [x along the camera's right axis, depth, grow time]
const SLOTS := {
	"pebble": [-7.2, 0.8, 1.0],
	"larkin": [-4.4, -0.6, 1.5],
	"dagna": [-1.5, 0.3, 1.3],
	"grunt": [1.6, -0.2, 1.7],
	"brute": [4.9, 0.9, 2.0],
	"swarmer": [7.4, -0.4, 1.2],
}

var shot_path := ""
var at_time := 0.6
var view := "game"
var grow_override := 0.0
var seed_arg := 7
var cancel_at := -1.0
var cam_yaw := GAME_YAW
var cam_pitch := GAME_PITCH
var cam_size := 0.0

var map: HexMap
var camera: Camera3D
var victims := {}                       ## name -> Node3D
var fxs: Array[TeethFx] = []
var _loop := 0.0
var _orbit := 0.0


func _ready() -> void:
	_parse_args()
	_build_world()
	victims["pebble"] = PebbleModel.new()
	victims["larkin"] = LarkinModel.new()
	victims["dagna"] = DagnaModel.new()
	victims["grunt"] = MonsterModels.make("grunt")
	victims["brute"] = MonsterModels.make("brute")
	victims["swarmer"] = MonsterModels.make("swarmer")
	for k: String in victims:
		add_child(victims[k])
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 200.0
	add_child(camera)
	_layout()
	if shot_path != "":
		for k: String in victims:
			var m := victims[k] as LowPolyModel
			m.idle_enabled = false
			m.apply_idle(0.6)
		TeethFx.seed_base = seed_arg
		_afflict_all(true)
		_run_shot()
	else:
		_afflict_all(false)


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	shot_path = _arg(a, "--shot")
	at_time = float(_arg(a, "--at", "0.6"))
	view = _arg(a, "--view", "game")
	grow_override = float(_arg(a, "--grow", "0"))
	seed_arg = int(_arg(a, "--seed", "7"))
	cancel_at = float(_arg(a, "--cancel", "-1"))
	if view == "close":
		cam_yaw = 20.0
		cam_pitch = -34.0
		cam_size = 5.2
	else:
		cam_size = GAME_SIZE
	cam_yaw = float(_arg(a, "--yaw", str(cam_yaw)))
	cam_pitch = float(_arg(a, "--pitch", str(cam_pitch)))
	cam_size = float(_arg(a, "--size", str(cam_size)))


static func _arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := a.find(key)
	if i >= 0 and i + 1 < a.size():
		return a[i + 1]
	return fallback


func _build_world() -> void:
	map = HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 22):
		var d := Hex.distance(c, Vector2i.ZERO)
		if d <= 13:
			map.set_cell(c, 0).tag = "room:0"
		elif d <= 18:
			map.set_cell(c, 6, HexMap.Tile.WALL)
	GameWorld.begin(map, self, 1)
	var terrain := HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)


func _right() -> Vector3:
	var yaw := deg_to_rad(GAME_YAW if view != "close" else cam_yaw)
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func _fwd() -> Vector3:
	var yaw := deg_to_rad(GAME_YAW if view != "close" else cam_yaw)
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Everyone in a loose row across the screen, facing the camera.
func _layout() -> void:
	var yaw := deg_to_rad(cam_yaw)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	for k: String in victims:
		var s: Array = SLOTS[k]
		var n := victims[k] as Node3D
		n.global_position = right * float(s[0]) + fwd * float(s[1])
		n.rotation.y = yaw + PI
	var tgt := right * 0.05 + Vector3(0.0, 1.2, 0.0)
	if view == "close":
		tgt = right * 0.05 + Vector3(0.0, 1.35, 0.0)
	camera.size = cam_size
	var pitch := deg_to_rad(cam_pitch)
	camera.global_position = tgt + Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * 60.0
	camera.look_at(tgt, Vector3.UP)


func _afflict_all(manual: bool) -> void:
	fxs.clear()
	for k: String in victims:
		var s: Array = SLOTS[k]
		var g := grow_override if grow_override > 0.0 else float(s[2])
		var fx := TeethFx.afflict(victims[k] as Node3D, g, func() -> void: print("pop ", k))
		fx.manual = manual
		fxs.append(fx)


func _process(delta: float) -> void:
	if shot_path != "":
		return
	_orbit += delta
	_loop += delta
	if _loop > 4.2:
		_loop = 0.0
		_afflict_all(false)
		if cancel_at > 0.0:
			get_tree().create_timer(cancel_at).timeout.connect(func() -> void:
				for f in fxs:
					if is_instance_valid(f):
						f.cancel())


func _run_shot() -> void:
	for i in 12:
		await get_tree().process_frame
	var dt := 1.0 / 60.0
	var steps := roundi(at_time * 60.0)
	var cancel_step := roundi(cancel_at * 60.0) if cancel_at > 0.0 else -1
	for i in steps:
		if i == cancel_step:
			for f in fxs:
				if is_instance_valid(f):
					f.cancel()
		for f in fxs:
			if is_instance_valid(f):
				f.advance(dt)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("shot ", shot_path, " ", img.save_png(shot_path))
	get_tree().quit()
