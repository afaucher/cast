extends LabBase
## Look-dev lab for the "teeth" spell effect (TeethFx): the three heroes and a few monsters stand on
## a slate hex patch (HexMapView + DungeonLook) and are all afflicted at once, with staggered grow times.
##
##   godot --path . -- --scene res://scenes/teeth_lab.tscn --view close --at 0.6 --shot <abs png>
##
## --shot <png>   deterministic: time is stepped by hand to --at seconds, one frame is saved, then quit.
## --at <sec>     the moment to capture (default 0.6)
## --view game|close   game = the exact game camera (yaw 45, pitch -56, ortho 24); close = ortho ~7
##                on Gasket and the grunt (override with --yaw / --pitch / --size)
## --grow <sec>   give every victim the same grow time instead of the staggered 1.0 .. 2.0 s
## --seed <n>     tooth layout seed (default 7)
## --cancel <sec> heal everyone at that time (cancel()) instead of letting them pop
## No --shot: realtime loop, everyone is afflicted again every few seconds, orbiting slowly.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0

## name -> [x along the camera's right axis, depth, grow time]
const SLOTS := {
	"rebar": [-7.2, 0.8, 1.0],
	"wick": [-4.4, -0.6, 1.5],
	"gasket": [-1.5, 0.3, 1.3],
	"grunt": [1.6, -0.2, 1.7],
	"brute": [4.9, 0.9, 2.0],
	"swarmer": [7.4, -0.4, 1.2],
}

var at_time := 0.6
var view := "game"
var grow_override := 0.0
var seed_arg := 7
var cancel_at := -1.0
var cam_yaw := GAME_YAW
var cam_pitch := GAME_PITCH
var cam_size := 0.0

var victims := {}                       ## name -> Node3D
var fxs: Array[TeethFx] = []
var _loop := 0.0
var _orbit := 0.0


func _ready() -> void:
	_parse_args()
	build_arena(22, 13, 18, 1)
	victims["rebar"] = RebarModel.new()
	victims["wick"] = WickModel.new()
	victims["gasket"] = GasketModel.new()
	victims["grunt"] = MonsterModels.make("grunt")
	victims["brute"] = MonsterModels.make("brute")
	victims["swarmer"] = MonsterModels.make("swarmer")
	for k: String in victims:
		add_child(victims[k])
	make_camera()
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
	at_time = float(arg(args, "--at", "0.6"))
	view = arg(args, "--view", "game")
	grow_override = float(arg(args, "--grow", "0"))
	seed_arg = int(arg(args, "--seed", "7"))
	cancel_at = float(arg(args, "--cancel", "-1"))
	if view == "close":
		cam_yaw = 20.0
		cam_pitch = -34.0
		cam_size = 5.2
	else:
		cam_size = GAME_SIZE
	cam_yaw = float(arg(args, "--yaw", str(cam_yaw)))
	cam_pitch = float(arg(args, "--pitch", str(cam_pitch)))
	cam_size = float(arg(args, "--size", str(cam_size)))


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
	aim(cam_yaw, cam_pitch, cam_size, tgt)


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
	await snap(shot_path, 4)
	finish()
