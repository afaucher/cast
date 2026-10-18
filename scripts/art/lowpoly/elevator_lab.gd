extends Node3D
## Elevator options lab (docs/design/elevator-options.md): the two elevator LOOKS in the three PLACEMENTS on the real
## terrain (HexMapView with midpoint walls from HexMap.cut_walls(), FloorMaterials, DungeonLook's lights), with the
## crew for scale. Look-dev: the game builds the chosen styles itself (ElevatorGeo, ElevatorArrival); the lobby placement
## and its props stay lab-only. Scene: scenes/elevator_lab.tscn.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/elevator_lab.tscn --look service --place adjacent
##         [--shot <png>] [--view <name>] [--door 0..1] [--no-crew]
##
## --look   service | fancy
## --place  adjacent  the car is a 3-cell notch cut into the back wall of an ordinary room
##          lobby     a small dedicated lobby room with the doors on its back wall, a corridor leading in
##          midfloor  free-standing in the middle of a room (fancy: glass shaft; service: freight platform lift)
## --shot <png>   renders every view and writes <base>.png (game) and <base>_<view>.png for the others (base = the
##                png without extension), then quits
## --view <name>  only that view, written to <png> exactly
## Views (the game camera: ortho yaw 45, pitch -56; size 24 is the game's default zoom, the close views are size 9):
##   game          size 24, doors open, the crew stepping out (one still in the car, one on the sill, one out)
##   closed        size 24, doors shut, the crew waiting outside (one at the call box)
##   close         size 9, doors open, the whole crew standing in the car (the arrival moment)
##   close_out     size 9, doors open, the crew stepping out
##   close_closed  size 9, doors shut, the crew waiting
## No --shot: the doors open and close every 4 seconds.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0          ## CameraRig.SIZE_DEFAULT
const CLOSE_SIZE := 9.0
const VIEWS: Array[String] = ["game", "closed", "close", "close_out", "close_closed"]

const NOTCH_MID := Vector2i(-2, -2)                  ## middle cell of the 3-cell notch (row q + r = -4)
const NOTCH: Array[Vector2i] = [Vector2i(-3, -1), Vector2i(-2, -2), Vector2i(-1, -3)]
const BACK_ROW := -3                                 ## q + r of the back wall line (the notch's mouth)
const NORMAL := Vector3(0.8660254, 0, 0.5)           ## the back wall's normal, into the room (15 degrees off the camera)
const ELEV_YAW := 60.0                               ## local +Z = NORMAL
const LOBBY_MID := Vector2i(-1, -1)

var shot_path := ""
var only_view := ""
var look := "service"
var place := "adjacent"
var door_arg := NAN
var with_crew := true
var map: HexMap
var camera: Camera3D
var elevator: ElevatorModel
var elev_pos := Vector3.ZERO
var crew: Array[LowPolyModel] = []
var _t := 0.0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	shot_path = _arg(a, "--shot")
	only_view = _arg(a, "--view")
	look = _arg(a, "--look", "service")
	place = _arg(a, "--place", "adjacent")
	if _arg(a, "--door") != "":
		door_arg = float(_arg(a, "--door"))
	with_crew = not a.has("--no-crew")
	_build_world()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 220.0
	add_child(camera)
	_place_elevator()
	_dress()
	if with_crew:
		for m: LowPolyModel in [WickModel.new(), GasketModel.new(), RebarModel.new()]:
			add_child(m)
			m.idle_enabled = false
			m.apply_idle(0.6)
			crew.append(m)
	if shot_path != "":
		_run_shots()
	else:
		_prepare("game" if is_nan(door_arg) or door_arg > 0.5 else "closed")


static func _arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := a.find(key)
	if i >= 0 and i + 1 < a.size():
		return a[i + 1]
	return fallback


# --------------------------------------------------------------------------- terrain

func _mats() -> Dictionary:
	var fancy := look == "fancy"
	match place:
		"lobby":
			return {"floor": FloorMaterials.F_MARBLE if fancy else FloorMaterials.F_DIAMOND,
					"wall": FloorMaterials.W_MARBLE if fancy else FloorMaterials.W_CONCRETE}
		"midfloor":
			return {"floor": FloorMaterials.F_MARBLE if fancy else FloorMaterials.F_CONCRETE,
					"wall": FloorMaterials.W_MARBLE if fancy else FloorMaterials.W_CONCRETE}
		_:
			return {"floor": FloorMaterials.F_CARPET if fancy else FloorMaterials.F_CONCRETE,
					"wall": FloorMaterials.W_PANELLING if fancy else FloorMaterials.W_CONCRETE}


func _build_world() -> void:
	map = HexMap.new()
	var m := _mats()
	var room_mat := FloorMaterials.pack(int(m["floor"]), int(m["wall"]))
	var corr_mat := FloorMaterials.pack(FloorMaterials.F_CORR_CONCRETE if look == "service" else FloorMaterials.F_CORR_STONE,
			FloorMaterials.W_CONCRETE if look == "service" else FloorMaterials.W_STONE)
	var floor_cells := {}   # cell -> [tag, mat]
	match place:
		"lobby":
			for c in Hex.range_cells(LOBBY_MID, 4):
				if c.x + c.y >= BACK_ROW:
					floor_cells[c] = ["room:0", room_mat]
			# the corridor that leads in, toward the camera
			var lw := Hex.to_world(LOBBY_MID)
			var along := Vector3(0.5, 0, -0.8660254)
			for c in Hex.range_cells(LOBBY_MID, 14):
				var d := Hex.to_world(c) - lw
				var fwd := d.dot(NORMAL)
				if absf(d.dot(along)) <= 1.3 and fwd >= 3.0 and not floor_cells.has(c):
					floor_cells[c] = ["corridor", corr_mat]
			# a second room glimpsed at the end of the corridor
			for c in Hex.range_cells(LOBBY_MID + Vector2i(7, 6), 4):
				if not floor_cells.has(c):
					floor_cells[c] = ["room:1", FloorMaterials.pack(FloorMaterials.F_CONCRETE, FloorMaterials.W_CONCRETE)]
		_:
			for c in Hex.range_cells(Vector2i.ZERO, 7):
				if c.x + c.y >= BACK_ROW:
					floor_cells[c] = ["room:0", room_mat]
			# a corridor off the right-hand side, so the room is not an island
			for c in Hex.range_cells(Vector2i.ZERO, 13):
				var p := Hex.to_world(c)
				if not floor_cells.has(c) and absf(p.z - 4.5) <= 1.4 and p.x > 6.0:
					floor_cells[c] = ["corridor", corr_mat]
	if place != "midfloor":
		for c in NOTCH:
			floor_cells[c] = ["room:0", room_mat]
	for c: Vector2i in floor_cells:
		var cell := map.set_cell(c, 0)
		cell.tag = str(floor_cells[c][0])
		cell.mat_id = int(floor_cells[c][1])
	# one ring of wall cells around everything walkable (DungeonGen does the same), 3 levels tall
	for c: Vector2i in floor_cells:
		for nb in Hex.neighbors(c):
			if not floor_cells.has(nb) and not map.has_cell(nb):
				var w := map.set_cell(nb, 3, HexMap.Tile.WALL)
				w.mat_id = int(floor_cells[c][1])
	map.cut_walls()
	GameWorld.begin(map, self, 1)
	var terrain := HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)


# --------------------------------------------------------------------------- the elevator and its dressing

func _place_elevator() -> void:
	if place == "midfloor":
		elevator = ElevatorModel.new(look, "column")
		elev_pos = Hex.to_world(Vector2i.ZERO)
	else:
		elevator = ElevatorModel.new(look, "wall")
		elev_pos = Hex.to_world(NOTCH_MID) + NORMAL * 1.5
	add_child(elevator)
	elevator.position = elev_pos
	elevator.rotation_degrees.y = ELEV_YAW
	elevator.set_indicator({"adjacent": 0.12, "lobby": 0.5, "midfloor": 0.88}.get(place, 0.3))


## Local (elevator frame) -> world.
func _w(local: Vector3) -> Vector3:
	return elev_pos + Basis.from_euler(Vector3(0, deg_to_rad(ELEV_YAW), 0)) * local


func _put(node: Node3D, local: Vector3, local_yaw: float = 0.0) -> Node3D:
	add_child(node)
	node.position = _w(local)
	node.rotation_degrees.y = ELEV_YAW + local_yaw
	return node


func _dress() -> void:
	var fancy := look == "fancy"
	match place:
		"lobby":
			if fancy:
				_put(ElevatorLobbyProps.build("directory", look), Vector3(3.8, 0, 0.02))
				_put(ElevatorLobbyProps.build("palm", look), Vector3(-3.6, 0, 0.7))
				_put(ElevatorLobbyProps.build("runner", look, {"length": 7.5}), Vector3(0, 0, 4.9))
				_put(ElevatorLobbyProps.build("bench", look), Vector3(-4.3, 0, 3.6), 75.0)
				_put(ElevatorLobbyProps.build("palm", look), Vector3(5.0, 0, 0.9))
			else:
				_put(ElevatorLobbyProps.build("service_sign", look), Vector3(-3.9, 0, 0.02))
				_put(ElevatorLobbyProps.build("extinguisher", look), Vector3(3.4, 0, 0.02))
				_put(ElevatorLobbyProps.build("keep_clear", look, {"width": 4.4, "depth": 1.7}), Vector3(0, 0, 2.2))
				_put(ElevatorLobbyProps.build("pallet", look), Vector3(4.0, 0, 1.4), -20.0)
				_put(ElevatorLobbyProps.build("bench", look), Vector3(-4.3, 0, 3.6), 75.0)
				_put(ElevatorLobbyProps.build("palm", look), Vector3(-5.2, 0, 0.9))
		"adjacent":
			if fancy:
				_put(PropModels.build("marble_statue"), Vector3(-4.6, 0, 0.9))
				_put(PropModels.build("crystal_lamp"), Vector3(4.4, 0, 0.9))
				_put(DecorModels.build("recliner"), Vector3(-1.2, 0, 6.0), 180.0)
				_put(DecorModels.build("recliner"), Vector3(1.2, 0, 6.0), 180.0)
			else:
				_put(DecorModels.build("crate_stack"), Vector3(-4.7, 0, 1.0))
				_put(DecorModels.build("wet_floor_sign"), Vector3(3.6, 0, 2.2), -25.0)
				_put(ElevatorLobbyProps.build("pallet", look), Vector3(4.8, 0, 1.2), 10.0)
		"midfloor":
			if fancy:
				_put(PropModels.build("marble_statue"), Vector3(-4.2, 0, -2.0), 40.0)
				_put(PropModels.build("crystal_lamp"), Vector3(4.0, 0, -2.2), -40.0)
				_put(ElevatorLobbyProps.build("bench", look), Vector3(-3.6, 0, 2.4), 70.0)
			else:
				_put(DecorModels.build("crate_stack"), Vector3(-4.2, 0, -2.0), 30.0)
				_put(ElevatorLobbyProps.build("pallet", look), Vector3(3.8, 0, -2.4), -15.0)
				_put(DecorModels.build("wet_floor_sign"), Vector3(-3.4, 0, 2.6), 20.0)


# --------------------------------------------------------------------------- views

## The car floor's height above the room floor (the crew stands on it inside).
func _car_floor() -> float:
	return 0.06


## mode: "inside" (the arrival: everyone in the car), "stepping" (one in the car, one on the sill, one out on the
## landing) or "waiting" (doors shut, the crew outside, one at the call box). Models face -Z, so 180 = out of the car.
func _pose_crew(mode: String) -> void:
	if crew.is_empty():
		return
	var h := _car_floor()
	var spots: Array[Vector3] = []
	var yaws: Array[float] = []
	match mode:
		"inside":
			for p in elevator.car_spots():
				spots.append(p + Vector3(0, h, 0))
			yaws = [172.0, 180.0, 188.0]
		"stepping":
			if place != "midfloor":
				spots = [Vector3(-0.9, h, -0.75), Vector3(0.15, 0.07, 0.25), Vector3(2.0, 0, 1.75)]
			elif look == "fancy":
				spots = [Vector3(-0.5, h, -0.4), Vector3(0.0, 0.12, 1.5), Vector3(1.6, 0, 3.0)]
			else:
				spots = [Vector3(-0.6, h, -0.5), Vector3(0.1, h, 1.25), Vector3(1.0, 0, 3.5)]
			yaws = [175.0, 185.0, 160.0]
		_:
			if place == "midfloor":
				spots = [Vector3(-1.4, 0, 3.1), Vector3(0.1, 0, 3.6), Vector3(2.0, 0, 2.6)]
			else:
				spots = [Vector3(-1.3, 0, 1.9), Vector3(0.2, 0, 2.4), Vector3(1.85, 0, 1.0)]
			yaws = [-10.0, 0.0, -35.0 if place != "midfloor" else -20.0]   # facing the doors; the last one at the call box
	for i in crew.size():
		crew[i].position = _w(spots[i])
		crew[i].rotation_degrees.y = ELEV_YAW + yaws[i]


func _prepare(view: String) -> void:
	var closed := view.contains("closed")
	var d := 0.0 if closed else 1.0
	if not is_nan(door_arg) and only_view == "":
		d = door_arg
	elevator.set_door_open(d)
	_pose_crew("waiting" if closed else ("inside" if view == "close" else "stepping"))
	var close := view == "close" or view.begins_with("close_")
	var tgt: Vector3
	if close:
		tgt = _w(Vector3(0, 1.3, 0.6 if place != "midfloor" else 0.2))
	else:
		tgt = _w(Vector3(0, 0.8, 0.9 if place != "midfloor" else 0.6))   # the camera follows the crew: centred on the car
	_aim(GAME_YAW, GAME_PITCH, CLOSE_SIZE if close else GAME_SIZE, tgt)


func _aim(yaw_deg: float, pitch_deg: float, size: float, tgt: Vector3) -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	camera.size = size
	camera.global_position = tgt + Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * 60.0
	camera.look_at(tgt, Vector3.UP)


func _run_shots() -> void:
	for i in 10:
		await get_tree().process_frame
	var base := shot_path.get_basename()
	var list: Array[String] = []
	if only_view == "":
		list.append_array(VIEWS)
	else:
		list.append(only_view)
	for v in list:
		_prepare(v)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var out := shot_path if only_view != "" else ("%s.png" % base if v == "game" else "%s_%s.png" % [base, v])
		var img := get_viewport().get_texture().get_image()
		print("shot ", out, " ", img.save_png(out), " ", img.get_size(), " tris ", elevator.triangle_count())
	get_tree().quit()


func _process(delta: float) -> void:
	if shot_path != "":
		return
	_t += delta
	var k := clampf(absf(fmod(_t, 8.0) - 4.0) - 1.0, 0.0, 1.0)
	elevator.set_door_open(k)
