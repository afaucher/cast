extends Node3D
## Character look-dev lab: the real terrain look (HexMapView + DungeonLook) with the procedural toy
## heroes on it, next to the old capsule prototype hero and two enemies, under the game camera.
##
##   godot --path . -- --scene res://scenes/character_lineup.tscn --view game --shot <abs.png>
##
## User args (after `--`):
##   --view game|close|turntable|compare   (default game)
##          game      the exact game camera (CameraRig: ortho 24, yaw 45, pitch -62)
##          close     zoomed ortho (size 7) for detail; use --focus to pick who is in frame
##          turntable 4 views (front / right / back / left) of each hero, lower pitch
##          compare   the 4 core heroes in all 3 styles, one row per style (mid zoom), plus
##                    <shot>_game.png / _game_crop.png (true game zoom) and _low.png (low camera, shows proportions)
##   --style toy|heroic|flat   look for the heroes (ignored by compare)
##   --focus pebble,dagna      close view: centre on these (ids, or "proto", "imp", "skeleton")
##   --size N                  override the ortho size
##   --pitch N                 override the camera pitch (degrees, negative looks down)
##   --pose melee|secondary    freeze everyone in a demo pose (default: idle frozen at t=1)
##   --frames N                frames to wait before the screenshot (default 20)
##   --crop W,H                centre-crop the saved screenshot to W x H pixels
##   --upscale N               nearest-neighbour upscale of the saved image (to inspect game-zoom pixels)
##   --shot <abs png>          save a screenshot and quit (otherwise it just runs, idling)

const YAW := 45.0
const PITCH := -62.0
const HERO_ROW: Array[String] = ["pebble", "dagna", "larkin", "sir_rattles", "gulp"]
const COMPARE_HEROES: Array[String] = ["pebble", "dagna", "larkin", "sir_rattles"]
const SPACING := 2.5
const FACE_YAW := -135.0 + 22.0     ## toward the camera, turned a little so a side shows

var view_name := "game"
var style: StringName = &"toy"
var shot_path := ""
var focus_ids: Array[String] = []
var size_override := 0.0
var pitch_override := 0.0
var pose_name := ""
var wait_frames := 20
var crop := Vector2i.ZERO
var upscale := 1

var map: HexMap
var rig: CameraRig
var figures: Dictionary = {}      ## key -> Node3D (hero ids, "proto", "imp", "skeleton")
var _right := Vector3(1, 0, -1).normalized()    ## screen-right on the ground
var _up := Vector3(-1, 0, -1).normalized()      ## screen-up (away from the camera) on the ground
var _center := Vector3.ZERO
var _frames := 0
var _compare_labels: Array[Label3D] = []
var _compare_rows: Array = []     ## Array of Array[ToyFigure], one per style row
var _view_size := 24.0


func _ready() -> void:
	_parse_args()
	_build_world()
	match view_name:
		"turntable": _layout_turntable()
		"compare": _layout_compare()
		_: _layout_lineup()
	_setup_camera()


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	var v := _arg(a, "--view")
	if v != "":
		view_name = v
	var st := _arg(a, "--style")
	if st != "":
		style = StringName(st)
	shot_path = _arg(a, "--shot")
	for id in _arg(a, "--focus").split(",", false):
		focus_ids.append(id)
	size_override = float(_arg(a, "--size", "0"))
	pitch_override = float(_arg(a, "--pitch", "0"))
	pose_name = _arg(a, "--pose")
	wait_frames = int(_arg(a, "--frames", "20"))
	upscale = maxi(1, int(_arg(a, "--upscale", "1")))
	var c := _arg(a, "--crop")
	if c.contains(","):
		var p := c.split(",")
		crop = Vector2i(int(p[0]), int(p[1]))


static func _arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := a.find(key)
	if i >= 0 and i + 1 < a.size():
		return a[i + 1]
	return fallback


# ------------------------------------------------------------------ world

func _build_world() -> void:
	map = HexMap.new()
	var origin := Vector2i.ZERO
	for c in Hex.range_cells(origin, 30):
		var d := Hex.distance(c, origin)
		if d <= 15:
			map.set_cell(c, 0).tag = "room:0"
		elif d <= 22:
			map.set_cell(c, 6, HexMap.Tile.WALL)
	# a crate platform behind the cast, and a couple of single crates, so heroes meet props
	var plat := Hex.from_world(_up * 7.0 + _right * -13.0)
	for c in Hex.range_cells(plat, 1):
		map.set_cell(c, 2).tag = "room:0"
	for off in [_right * 11.0 + _up * 4.0, _right * -12.0 + _up * -2.0, _right * 5.0 + _up * 8.0]:
		map.set_cell(Hex.from_world(off), 1).tag = "room:0"
	GameWorld.begin(map, self, 1)
	var terrain := HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)


func _setup_camera() -> void:
	rig = CameraRig.new()
	add_child(rig)
	rig.set_process(false)
	var pitch := pitch_override if pitch_override != 0.0 else PITCH
	match view_name:
		"close": _view_size = 7.0
		"turntable":
			_view_size = 17.0 if focus_ids.size() != 1 else 5.2
			if pitch_override == 0.0:
				pitch = -30.0 if focus_ids.size() != 1 else -24.0
		"compare": _view_size = 11.0
		_: _view_size = 24.0
	if size_override > 0.0:
		_view_size = size_override
	rig.global_position = _center + Vector3.UP * CameraRig.FOCUS_HEIGHT
	rig.camera.size = _view_size
	var d := CameraRig.DISTANCE
	var pr := deg_to_rad(-pitch)
	rig.camera.position = Vector3(0, d * sin(pr), d * cos(pr))
	rig.camera.rotation_degrees.x = pitch


# ------------------------------------------------------------------ layouts

func _ground(a: float, b: float) -> Vector3:
	return _right * a + _up * b


func _hero(id: String, st: StringName) -> ToyFigure:
	var fig := CharacterKit.build(id, st) as ToyFigure
	add_child(fig)
	return fig


func _finish_figure(fig: ToyFigure) -> void:
	if pose_name != "":
		fig.pose(StringName(pose_name))
	elif shot_path != "":
		fig.idle_enabled = false
		fig.apply_idle(1.0)


func _layout_lineup() -> void:
	var order: Array[String] = ["proto"]
	order.append_array(HERO_ROW)
	var x0 := -SPACING * (order.size() - 1) * 0.5
	for i in order.size():
		var key := order[i]
		var pos := _ground(x0 + i * SPACING, 0.0)
		if key == "proto":
			figures[key] = _spawn_proto(pos)
		else:
			var fig := _hero(key, style)
			fig.position = pos
			fig.rotation_degrees.y = FACE_YAW
			_finish_figure(fig)
			figures[key] = fig
	# enemies in a front row, nearer the camera: two imps and a skeleton
	var enemies: Array = [["swarmer", "imp", -2.2], ["swarmer", "imp2", -0.6], ["grunt", "skeleton", 1.6]]
	for e in enemies:
		var m := _spawn_monster(str(e[0]), _ground(float(e[2]) + SPACING * 1.0, -3.4))
		figures[str(e[1])] = m
	_center = _ground(0.0, -1.2)
	if view_name == "close" and not focus_ids.is_empty():
		var sum := Vector3.ZERO
		for id in focus_ids:
			if figures.has(id):
				sum += (figures[id] as Node3D).position
		_center = sum / focus_ids.size()
		_center.y = 0.0
	elif view_name == "close":
		_center = _ground(0.0, 0.0)


func _layout_turntable() -> void:
	var ids: Array[String] = HERO_ROW.duplicate()
	if not focus_ids.is_empty():
		ids = focus_ids.duplicate()
	var row_gap := 4.4 if ids.size() > 1 else 0.0
	var col_gap := 2.4 if ids.size() > 1 else 2.6
	var y0 := row_gap * (ids.size() - 1) * 0.5
	for r in ids.size():
		var b := y0 - r * row_gap
		for c in 4:
			var fig := _hero(ids[r], style)
			fig.position = _ground((c - 1.5) * col_gap, b)
			fig.rotation_degrees.y = -135.0 + 90.0 * c
			_finish_figure(fig)
		_label(ids[r].replace("_", " "), _ground(-1.5 * col_gap - 2.3, b))
	_center = Vector3.ZERO


func _layout_compare() -> void:
	var row_gap := 2.9
	var styles: Array[StringName] = [&"toy", &"heroic", &"flat"]
	var y0 := row_gap
	for r in styles.size():
		var b := y0 - r * row_gap
		var row: Array = []
		for c in COMPARE_HEROES.size():
			var fig := _hero(COMPARE_HEROES[c], styles[r])
			fig.position = _ground((c - 1.5) * SPACING, b)
			fig.rotation_degrees.y = FACE_YAW
			_finish_figure(fig)
			row.append(fig)
		_compare_rows.append(row)
		_compare_labels.append(_label(String(styles[r]).to_upper(), _ground(-1.5 * SPACING - 1.9, b)))
	_center = Vector3.ZERO


func _label(text: String, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.012
	l.outline_size = 12
	l.modulate = Color(1.0, 0.92, 0.75)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos + Vector3(0, 1.0, 0)
	add_child(l)
	return l


func _spawn_proto(pos: Vector3) -> Hero:
	var h := HeroFactory.spawn_hero(Hex.from_world(pos), "", Color(0.3, 0.55, 0.95))
	h.facing = Vector3(sin(deg_to_rad(-FACE_YAW)), 0, cos(deg_to_rad(-FACE_YAW))) * -1.0
	h.global_position = pos
	h.set_physics_process(false)
	return h


func _spawn_monster(kind: String, pos: Vector3) -> Monster:
	var m := MonsterFactory.spawn(kind, Hex.from_world(pos))
	m.global_position = pos
	m.facing = (_ground(0.0, 0.0) * 0.0 + Vector3(0.7, 0, 0.7)).normalized()
	m.set_physics_process(false)
	m._visual.rotation.y = atan2(-m.facing.x, -m.facing.z)
	return m


# ------------------------------------------------------------------ screenshot

func _process(_delta: float) -> void:
	if shot_path == "":
		return
	_frames += 1
	if _frames == wait_frames:
		_take_shots()


func _take_shots() -> void:
	await RenderingServer.frame_post_draw
	_save(shot_path, crop)
	if view_name == "compare":
		rig.camera.size = 24.0
		for i in 4:
			await RenderingServer.frame_post_draw
		var base := shot_path.get_basename()
		_save(base + "_game.png", Vector2i.ZERO)
		_save(base + "_game_crop.png", Vector2i(600, 440))
		# the same grid from a low angle, where the proportion differences actually show
		for r in _compare_rows.size():
			for c in _compare_rows[r].size():
				var fig: Node3D = _compare_rows[r][c]
				fig.position = _ground((c - 1.5) * 2.7, (1 - r) * 5.2)
			_compare_labels[r].position = _ground(-1.5 * 2.7 - 2.3, (1 - r) * 5.2) + Vector3(0, 1.0, 0)
		rig.camera.size = 12.0
		rig.camera.position = Vector3(0, CameraRig.DISTANCE * sin(deg_to_rad(30.0)), CameraRig.DISTANCE * cos(deg_to_rad(30.0)))
		rig.camera.rotation_degrees.x = -30.0
		for i in 4:
			await RenderingServer.frame_post_draw
		_save(base + "_low.png", Vector2i.ZERO)
	get_tree().quit()


func _save(path: String, crop_size: Vector2i) -> void:
	var img := get_viewport().get_texture().get_image()
	if crop_size != Vector2i.ZERO:
		var w := mini(crop_size.x, img.get_width())
		var h := mini(crop_size.y, img.get_height())
		img = img.get_region(Rect2i((img.get_width() - w) / 2, (img.get_height() - h) / 2, w, h))
	if upscale > 1:
		img.resize(img.get_width() * upscale, img.get_height() * upscale, Image.INTERPOLATE_NEAREST)
	var err := img.save_png(path)
	print("shot saved ", path, " ", img.get_size(), " err=", err)
