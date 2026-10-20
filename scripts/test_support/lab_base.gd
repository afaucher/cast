class_name LabBase
extends Node3D
## The base of the look-dev / screenshot labs (`scripts/**/*_lab.gd`, scenes `scenes/*_lab.tscn`): the command line
## after `--`, the settle-then-grab-then-save screenshot step, the quit, and the orthographic game camera. A lab
## `extends LabBase`, keeps its own views and its own flags, and only writes what is special to it.
##
##   godot --path . --resolution 1280x720 -- --scene res://scenes/x_lab.tscn --shot <abs.png> [--view <name>]
##
## Every lab reads `--shot <png>` (`shot_path`; empty = the interactive lab) and most also `--view <name>`
## (`only_view`; empty = every view). `args` is the whole `OS.get_cmdline_user_args()`, parsed in `_init` so a lab's
## `_ready` can use it at once; `arg(args, "--flag", "default")` reads one value and `args.has("--flag")` a switch.
##
## A lab with several views writes its own sequence and calls `snap(path)` once per view (it settles, grabs, saves
## and prints "shot <path> <result>"), then `finish()` to quit. A lab with a single shot calls
## `shot_after(path, seconds)`. `make_camera()` + `aim()` are the game's isometric camera (a yaw and pitch, an
## orthographic size, a target), `build_arena()` the slate disc with a wall ring the 3D labs stand on.
##
## Labs that cannot inherit Node3D (a Control lab) call the static `LabBase.arg` and `LabBase.grab_of`.

## The command line after `--`.
var args := PackedStringArray()
## `--shot <png>` ("" = interactive).
var shot_path := ""
## `--view <name>` ("" = every view).
var only_view := ""
## The lab's orthographic camera (`make_camera`).
var camera: Camera3D
## The lab's floor map (`build_arena`).
var map: HexMap


func _init() -> void:
	args = OS.get_cmdline_user_args()
	shot_path = arg(args, "--shot")
	only_view = arg(args, "--view")


## The value after `key`, or `fallback`.
static func arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var v := Boot.arg_value(a, key)
	return v if v != "" else fallback


## Wait `n` rendered frames.
func wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Wait `settle` frames, then the frame after the draw, and return what the root viewport shows.
func grab(settle: int = 6) -> Image:
	return await grab_of(self, settle)


## `grab` for any node in the tree (a Control lab).
static func grab_of(node: Node, settle: int = 6) -> Image:
	for i in settle:
		await node.get_tree().process_frame
	await RenderingServer.frame_post_draw
	return node.get_viewport().get_texture().get_image()


## Save `img` as a PNG and print "shot <path> <result>" (`tail` is appended: extra facts about the shot).
func save_shot(img: Image, path: String, tail: String = "") -> void:
	print("shot ", path, " ", img.save_png(path), tail)


## Settle, grab, save and print one screenshot; returns the image (for crops and contact sheets).
func snap(path: String, settle: int = 6, tail: String = "") -> Image:
	var img := await grab(settle)
	save_shot(img, path, tail)
	return img


## Wait `seconds` of game time, then `snap` (the lab's one screenshot) and quit.
func shot_after(path: String, seconds: float, settle: int = 6) -> void:
	await get_tree().create_timer(seconds).timeout
	await snap(path, settle)
	finish()


## Quit (the last line of every screenshot run).
func finish() -> void:
	get_tree().quit()


## An orthographic camera (near 0.1) added to the lab and kept in `camera`.
func make_camera(far: float = 200.0) -> Camera3D:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = far
	add_child(camera)
	return camera


## Put the camera `dist` away from `tgt`, looking at it from `yaw_deg` / `pitch_deg` (the game's is 45 / -56) with the
## orthographic `size` (the game's default zoom is 24).
func aim(yaw_deg: float, pitch_deg: float, size: float, tgt: Vector3, dist: float = 60.0) -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	camera.size = size
	camera.global_position = tgt + Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * dist
	camera.look_at(tgt, Vector3.UP)


## A slate room of hex radius `floor_r` (room:0) inside a wall ring out to `wall_r`, cells to `reach`, with the real
## terrain look (HexMapView + DungeonLook), the world begun with `world_seed`. Fills `map`.
func build_arena(reach: int, floor_r: int, wall_r: int, world_seed: int) -> void:
	map = HexMap.new()
	var origin := Vector2i.ZERO
	for c in Hex.range_cells(origin, reach):
		var d := Hex.distance(c, origin)
		if d <= floor_r:
			map.set_cell(c, 0).tag = "room:0"
		elif d <= wall_r:
			map.set_cell(c, 6, HexMap.Tile.WALL)
	GameWorld.begin(map, self, world_seed)
	var terrain := HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)
