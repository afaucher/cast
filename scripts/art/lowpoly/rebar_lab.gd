extends Node3D
## Rebar look-dev lab: the real terrain look (HexMapView + DungeonLook) with the faceted Rebar on a
## slate patch, the old prototype hero standing next to him, and an orbiting orthographic camera.
##
##   godot --path . -- --scene res://scenes/rebar_lab.tscn --shot <abs.png>
##
## --shot <png>  renders front / three-quarter / back / overhead / game-zoom views, saves each as
##               <png minus .png>_<view>.png plus a contact sheet at <png>, then quits.
## --view <name> only that view (front, three_quarter, back, overhead, game) as <png>.
## --pose punch  freeze Rebar mid-punch (mostly for checking the swing silhouette)
## No --shot: just opens the lab and orbits slowly with idle animation.

const GAME_YAW := 45.0
const GAME_PITCH := -62.0
const GAME_SIZE := 24.0

## name -> [camera yaw deg (180 = in front of Rebar (he faces -Z)), pitch deg, ortho size, hero offset on screen-right]
const VIEWS := {
	"front": [180.0, -14.0, 4.4],
	"three_quarter": [142.0, -26.0, 4.4],
	"back": [0.0, -20.0, 4.4],
	"overhead": [180.0, -72.0, 4.6],
	"game": [GAME_YAW, GAME_PITCH, GAME_SIZE],
}
const SHEET_ORDER: Array[String] = ["front", "three_quarter", "back", "overhead", "game"]

var shot_path := ""
var only_view := ""
var pose := ""
var map: HexMap
var rebar: RebarModel
var old_hero: Hero
var camera: Camera3D
var _target := Vector3(0, 1.0, 0)
var _spin := 0.0


func _ready() -> void:
	_parse_args()
	_build_world()
	rebar = RebarModel.new()
	rebar.position = Vector3.ZERO
	add_child(rebar)
	old_hero = HeroFactory.spawn_hero(Vector2i.ZERO, "", Color(0.3, 0.55, 0.95))
	old_hero.facing = Vector3(0, 0, -1)
	old_hero.set_physics_process(false)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 200.0
	add_child(camera)
	if shot_path != "":
		rebar.idle_enabled = false
		rebar.apply_idle(0.6)
		if pose == "punch":
			rebar.parts["arm_r"].rotation.x = 1.4
		_run_shots()
	else:
		_place_view("three_quarter")


func _parse_args() -> void:
	var a := OS.get_cmdline_user_args()
	shot_path = _arg(a, "--shot")
	only_view = _arg(a, "--view")
	pose = _arg(a, "--pose")


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


## Orbit the camera around Rebar and put the old hero on the camera's right.
func _place_view(view: String) -> void:
	var v: Array = VIEWS[view]
	var yaw := deg_to_rad(float(v[0]))
	var pitch := deg_to_rad(float(v[1]))
	var size := float(v[2])
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var is_game := view == "game"
	var dist := 60.0
	var tgt := _target
	if is_game:
		tgt = right * 1.1 + Vector3(0, 0.8, 0)
	camera.size = size
	camera.global_position = tgt + Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * dist
	camera.look_at(tgt, Vector3.UP)
	# Old hero beside Rebar: on the camera's right (so they are side by side on screen)
	var gap := 2.3 if not is_game else 2.6
	old_hero.global_position = Vector3(0, 0, 0) + right * gap
	# both face the camera (front) so the comparison is fair; Rebar keeps his local -Z forward
	rebar.rotation.y = 0.0
	if is_game:
		# in the game view face roughly toward the camera, like the in-game default
		rebar.rotation.y = yaw + PI
	old_hero.facing = Vector3(0, 0, -1).rotated(Vector3.UP, rebar.rotation.y)
	old_hero._visual_yaw = atan2(-old_hero.facing.x, -old_hero.facing.z)
	old_hero._visual.rotation.y = old_hero._visual_yaw


func _process(delta: float) -> void:
	if shot_path == "":
		_spin += delta * 0.4
		var yaw := _spin
		camera.global_position = _target + Vector3(sin(yaw) * 0.6, 0.55, cos(yaw) * 0.6).normalized() * 60.0
		camera.look_at(_target, Vector3.UP)
		camera.size = 5.0
		old_hero.global_position = Vector3(cos(yaw), 0, -sin(yaw)) * 2.3


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
			# true game zoom: centre crop, nearest upscale x3 so the pixels are inspectable
			var cw := 400
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
