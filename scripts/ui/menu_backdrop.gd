class_name MenuBackdrop
extends Node3D
## The main menu's living background: a slate/amber dungeon hall (the real HexMapView + DungeonLook, no
## simulation), the three heroes idling in the foreground and a big hellgate glowing in the distance,
## seen by a slowly swaying perspective camera. It needs none of the game systems (no GameWorld, no
## actors, no physics), so it is cheap: one terrain mesh, three models, one gate and a few lights.
##
## The camera sits on the game's side of the world (towards +X +Z), so DungeonLook's light and the
## hellgate's "tall shards at the back" are right without changes. The frame is composed for a menu on the
## left: the crew lands in the right half of the screen.

const HALL_CENTER_AT := Vector3(-3.5, 0.0, -3.5)   ## world point the floor disc is centred on (between camera and gate)
const HALL_RADIUS := 13                  ## floor cells (a cell is ~1.7 units across)
const WALL_RADIUS := 17                  ## ring of walls out to here
const GATE_AT := Vector3(-15.0, 0.0, -16.0)
const CREW_AT := Vector3.ZERO
const CAMERA_DISTANCE := 13.5
const CAMERA_HEIGHT := 4.4
const CAMERA_FOV := 40.0
const BASE_YAW_DEG := 45.0               ## the game camera's yaw
const SWAY_DEG := 20.0                   ## +- around the base yaw
const SWAY_SPEED := 0.16                 ## rad/s: a full sway takes ~40 s
const LOOK_SHIFT := 3.4                  ## world units the aim point is moved to the camera's left (crew -> right of screen)

var map: HexMap
var terrain: HexMapView
var camera: Camera3D
var gate: HellgateModel
var wick: WickModel
var rebar: RebarModel
var gasket: GasketModel
var key_light: DirectionalLight3D

var _t := 0.0
var _gate_cell := Vector2i.ZERO
var _hall_center := Vector2i.ZERO


func _ready() -> void:
	_build_map()
	terrain = HexMapView.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)
	_tune_look()
	_build_gate()
	_build_crew()
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = CAMERA_FOV
	camera.near = 0.3
	camera.far = 120.0
	add_child(camera)
	camera.current = true
	_place_camera(0.0)


func _process(delta: float) -> void:
	_t += delta
	_place_camera(_t)


## The camera's yaw at time t (degrees): a slow sway around the game view.
static func yaw_at(t: float) -> float:
	return BASE_YAW_DEG + SWAY_DEG * sin(t * SWAY_SPEED)


func _place_camera(t: float) -> void:
	var yaw := deg_to_rad(yaw_at(t))
	var focus := CREW_AT + Vector3(0.0, 1.1, 0.0)
	var dist := CAMERA_DISTANCE + 0.6 * sin(t * 0.11)
	camera.global_position = focus + Vector3(sin(yaw) * dist, CAMERA_HEIGHT - 1.1 + 0.25 * sin(t * 0.13), cos(yaw) * dist)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	camera.look_at(focus - right * LOOK_SHIFT + Vector3(0.0, 0.5, 0.0), Vector3.UP)


# --- World -------------------------------------------------------------------------------------------

func _build_map() -> void:
	map = HexMap.new()
	_gate_cell = Hex.from_world(GATE_AT)
	_hall_center = Hex.from_world(HALL_CENTER_AT)
	for c in Hex.range_cells(_hall_center, WALL_RADIUS):
		var d := Hex.distance(c, _hall_center)
		var from_gate := Hex.distance(c, _gate_cell)
		var from_crew := Hex.distance(c, Hex.from_world(CREW_AT))
		if d <= HALL_RADIUS:
			var level := 0
			if from_gate <= 3:
				level = 1   # the gate sits on a low dais
			elif from_crew > 5 and _hash(c) < 0.2 and from_gate > 5:
				level = 1   # rubble: the odd raised hex far from the crew
			var cell := map.set_cell(c, level)
			cell.tag = "room:0"
		else:
			var h := 5 + int(_hash(c) * 3.0)
			map.set_cell(c, h, HexMap.Tile.WALL)
	# A few pillars (single tall hexes) for depth, away from the crew and the gate.
	for c in Hex.range_cells(_hall_center, HALL_RADIUS - 2):
		if Hex.distance(c, Hex.from_world(CREW_AT)) > 6 and Hex.distance(c, _gate_cell) > 6 and _hash(c + Vector2i(7, 3)) < 0.035:
			map.set_cell(c, 4, HexMap.Tile.WALL)


## 0..1, stable per cell.
static func _hash(c: Vector2i) -> float:
	var h := (c.x * 73856093) ^ (c.y * 19349663)
	return float((h & 0x7fffffff) % 1000) / 1000.0


## The game's dungeon light, moodier: dark red fog so the far wall and the gate sit in haze.
func _tune_look() -> void:
	var we := get_node_or_null("LookEnvironment") as WorldEnvironment
	if we != null:
		var env := we.environment
		env.fog_enabled = true
		env.fog_light_color = Color(0.20, 0.09, 0.07)
		env.fog_density = 0.016
		env.fog_sky_affect = 1.0
	key_light = get_node_or_null("KeyLight") as DirectionalLight3D


func _build_gate() -> void:
	gate = HellgateModel.make(true)
	gate.name = "Hellgate"
	add_child(gate)
	gate.set_active(true)
	var level := map.get_cell(_gate_cell).level if map.has_cell(_gate_cell) else 0
	gate.position = Hex.to_world(_gate_cell, level)


func _build_crew() -> void:
	# Camera-aligned frame at the base yaw: `right` along the screen, `toward` out of the screen.
	var yaw := deg_to_rad(BASE_YAW_DEG)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var toward := Vector3(sin(yaw), 0.0, cos(yaw))
	var spots := {
		"wick": [CREW_AT + toward * 1.0 + right * 0.2, 12.0],
		"rebar": [CREW_AT - right * 2.7 - toward * 0.1, 28.0],
		"gasket": [CREW_AT + right * 2.5 - toward * 0.3, -26.0],
	}
	wick = WickModel.new()
	rebar = RebarModel.new()
	gasket = GasketModel.new()
	var models := {"wick": wick, "rebar": rebar, "gasket": gasket}
	for key: String in models:
		var m: LowPolyModel = models[key]
		var spot: Array = spots[key]
		add_child(m)
		var p: Vector3 = spot[0]
		m.position = Vector3(p.x, _ground_at(p), p.z)
		# Models face -Z; turn them to the camera, then a little inward / outward for the group's shape.
		m.rotation.y = atan2(-toward.x, -toward.z) + deg_to_rad(float(spot[1]))


func _ground_at(p: Vector3) -> float:
	var g := map.ground_height(p)
	return 0.0 if is_nan(g) else g
