extends Node3D
## Character look-dev lab: the real terrain look (HexMapView + DungeonLook) with the faceted
## DagnaModel, PebbleModel and the old prototype hero side by side on a slate patch, an orbiting /
## fixed orthographic camera, and the game's own camera angle for the "game zoom" check.
##
##   godot --path . -- --scene res://scenes/dagna_lab.tscn --shot <abs.png>
##
## --shot <png>  renders every view as <png minus .png>_<view>.png plus a contact sheet at <png>,
##               then quits. The game view also writes <base>_game_crop.png (centre crop, x3).
## --view <name> only that view as <png>.
## No --shot: opens the lab, orbits slowly with idle animation, and Dagna spins every few seconds.
##
## Views: front, three_quarter, back, overhead (Dagna close-ups), lineup (all three), game (the real
## camera angle, size 24), wind / hit (the wrench smash frozen at wind-up and impact), spin (mid-whirl).

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0

## name -> [camera yaw deg (180 = in front of the heroes, who face -Z), pitch deg, ortho size, focus: dagna|lineup]
const VIEWS := {
	"front": [180.0, -14.0, 3.2, "dagna"],
	"three_quarter": [142.0, -26.0, 3.2, "dagna"],
	"back": [0.0, -20.0, 3.2, "dagna"],
	"overhead": [180.0, -72.0, 3.4, "dagna"],
	"lineup": [160.0, -22.0, 6.4, "lineup"],
	"game": [GAME_YAW, GAME_PITCH, GAME_SIZE, "lineup"],
	"wind": [142.0, -26.0, 3.2, "dagna"],
	"hit": [142.0, -26.0, 3.2, "dagna"],
	"spin": [GAME_YAW, GAME_PITCH, 4.0, "dagna"],
}
const SHEET_ORDER: Array[String] = ["front", "three_quarter", "back", "overhead", "lineup", "game", "wind", "hit", "spin"]

const GAP_PEBBLE := 2.7     ## how far right (on screen) of Dagna each figure stands
const GAP_HERO := 4.9

var shot_path := ""
var only_view := ""
var map: HexMap
var dagna: DagnaModel
var pebble: PebbleModel
var old_hero: Hero
var camera: Camera3D
var _spin_t := 0.0
var _orbit := 0.0


func _ready() -> void:
	_parse_args()
	_build_world()
	dagna = DagnaModel.new()
	add_child(dagna)
	pebble = PebbleModel.new()
	add_child(pebble)
	old_hero = HeroFactory.spawn_hero(Vector2i.ZERO, "", Color(0.3, 0.55, 0.95))
	old_hero.facing = Vector3(0, 0, -1)
	old_hero.set_physics_process(false)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 200.0
	add_child(camera)
	if shot_path != "":
		for m: LowPolyModel in [dagna, pebble]:
			m.idle_enabled = false
			m.apply_idle(0.6)
		_run_shots()
	else:
		_place_view("lineup")


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	shot_path = _arg(a, "--shot")
	only_view = _arg(a, "--view")


static func _arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := a.find(key)
	if i >= 0 and i + 1 < a.size():
		return a[i + 1]
	return fallback


func _build_world() -> void:
	map = HexMap.new()
	var origin := Vector2i.ZERO
	for c in Hex.range_cells(origin, 26):
		var d := Hex.distance(c, origin)
		if d <= 14:
			map.set_cell(c, 0).tag = "room:0"
		elif d <= 20:
			map.set_cell(c, 6, HexMap.Tile.WALL)
	GameWorld.begin(map, self, 1)
	var terrain := HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)


## Pose the frozen action views: the wrench wind-up, the impact, the mid-spin.
func _pose_for(view: String) -> void:
	dagna._arm_kick["weapon"] = 0.0
	dagna._arm_kick["spin"] = 0.0
	dagna.parts["body"].rotation = Vector3.ZERO
	match view:
		"wind":
			dagna._arm_kick["weapon"] = 1.0
			dagna.parts["body"].rotation.x = -0.10
		"hit":
			dagna._arm_kick["weapon"] = -1.25
			dagna.parts["body"].rotation.x = 0.16
		"spin":
			dagna._arm_kick["spin"] = 1.0
	dagna.apply_idle(0.6)


## Place the three figures on the camera's right axis and aim the camera.
func _place_view(view: String) -> void:
	var v: Array = VIEWS[view]
	var yaw := deg_to_rad(float(v[0]))
	var pitch := deg_to_rad(float(v[1]))
	var focus: String = v[3]
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var tgt := Vector3(0, 0.85, 0)
	if focus == "lineup":
		tgt = right * 2.45 + Vector3(0, 1.1 if view == "lineup" else 0.6, 0)
	camera.size = float(v[2])
	camera.global_position = tgt + Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * 60.0
	camera.look_at(tgt, Vector3.UP)
	# Everyone faces the camera in the angled views (as in game), else straight ahead (-Z).
	var face := 0.0
	if view == "game" or view == "spin":
		face = yaw + PI
	dagna.position = Vector3.ZERO
	dagna.rotation.y = face
	pebble.global_position = right * GAP_PEBBLE
	pebble.rotation.y = face
	old_hero.global_position = right * GAP_HERO
	old_hero.facing = Vector3(0, 0, -1).rotated(Vector3.UP, face)
	old_hero._visual_yaw = atan2(-old_hero.facing.x, -old_hero.facing.z)
	old_hero._visual.rotation.y = old_hero._visual_yaw
	_pose_for(view)


func _process(delta: float) -> void:
	if shot_path != "":
		return
	_orbit += delta * 0.4
	var yaw := _orbit
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var tgt := right * 2.4 + Vector3(0, 1.0, 0)
	camera.global_position = tgt + Vector3(sin(yaw) * 0.6, 0.55, cos(yaw) * 0.6).normalized() * 60.0
	camera.look_at(tgt, Vector3.UP)
	camera.size = 6.4
	pebble.global_position = right * GAP_PEBBLE
	old_hero.global_position = right * GAP_HERO
	_spin_t += delta
	if _spin_t > 4.0:
		_spin_t = 0.0
		dagna.spin()


func _run_shots() -> void:
	for i in 20:
		await get_tree().process_frame
	var base := shot_path.get_basename()
	var views: Array[String] = SHEET_ORDER.duplicate()
	if only_view != "":
		views = [only_view]
	var images: Array[Image] = []
	for view in views:
		_place_view(view)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var out_path := shot_path if only_view != "" else "%s_%s.png" % [base, view]
		if view == "game":
			# true game zoom: crop around the three figures, nearest upscale x3 so the pixels are inspectable
			var cw := 520
			var ch := 280
			var crop := img.get_region(Rect2i((img.get_width() - cw) / 2, (img.get_height() - ch) / 2, cw, ch))
			crop.resize(cw * 3, ch * 3, Image.INTERPOLATE_NEAREST)
			crop.save_png("%s_game_crop.png" % base)
		print("shot ", out_path, " ", img.save_png(out_path))
		images.append(img)
	if only_view == "":
		_save_sheet(images)
	get_tree().quit()


func _save_sheet(images: Array[Image]) -> void:
	var cols := 3
	var rows := ceili(images.size() / float(cols))
	var tw := images[0].get_width() / 2
	var th := images[0].get_height() / 2
	var sheet := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGBA8)
	for i in images.size():
		var im := images[i].duplicate() as Image
		im.convert(Image.FORMAT_RGBA8)
		im.resize(tw, th, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(im, Rect2i(0, 0, tw, th), Vector2i((i % cols) * tw, (i / cols) * th))
	print("sheet ", shot_path, " ", sheet.save_png(shot_path))
