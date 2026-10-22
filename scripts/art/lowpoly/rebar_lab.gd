extends LabBase
## Rebar look-dev lab: the real terrain look (HexMapView + DungeonLook) with the faceted Rebar on a
## slate patch, the old prototype hero standing next to him, and an orbiting orthographic camera.
##
##   godot --path . -- --scene res://scenes/rebar_lab.tscn --shot <abs.png>
##
## --shot <png>  renders front / three-quarter / back / overhead / game-zoom views, saves each as
##               <png minus .png>_<view>.png plus a contact sheet at <png>, then quits.
## --view <name> only that view (any name in VIEWS) as <png>; --views a,b,c those views as <base>_<view>.png.
## --pose punch  freeze Rebar mid-punch (mostly for checking the swing silhouette)
## Extra views: head (a close-up of the face), crew (the game camera at the game's 1080p pixel scale, Rebar between Wick
##               and Gasket; also <base>_crew_crop.png, x3 nearest), slam_up / slam (the slam's top and bottom,
##               three-quarter), bowl (the bowl's follow-through), headshot (the party HUD's portrait, x3).
##               The jaw and vest look-dev: docs/design/rebar-jaw.md.
##   godot --path . --resolution 1600x1600 -- --scene res://scenes/rebar_lab.tscn --views crew,head,headshot --shot <abs.png>
## No --shot: just opens the lab and orbits slowly with idle animation.

const GAME_YAW := 45.0
const GAME_PITCH := -62.0
const GAME_SIZE := 24.0
## The crew view: CameraRig's pitch, and its default size 24 scaled from 1080 lines to the lab's 1600 (the game's pixels).
const CREW_PITCH := -56.0
const CREW_SIZE := 24.0 * 1600.0 / 1080.0
const CREW_GAP := 2.4          ## Wick and Gasket stand this far either side of Rebar (on the camera's right axis)

## name -> [camera yaw deg (180 = in front of Rebar (he faces -Z)), pitch deg, ortho size, hero offset on screen-right]
const VIEWS := {
	"front": [180.0, -14.0, 4.4],
	"three_quarter": [142.0, -26.0, 4.4],
	"back": [0.0, -20.0, 4.4],
	"overhead": [180.0, -72.0, 4.6],
	"game": [GAME_YAW, GAME_PITCH, GAME_SIZE],
	"head": [150.0, -12.0, 1.7],
	"crew": [GAME_YAW, CREW_PITCH, CREW_SIZE],
	"slam_up": [125.0, -20.0, 5.2],
	"slam": [125.0, -20.0, 5.2],
	"bowl": [150.0, -20.0, 3.4],
}
const SHEET_ORDER: Array[String] = ["front", "three_quarter", "back", "overhead", "game"]

var pose := ""
var rebar: RebarModel
var old_hero: Hero
var wick: WickModel
var gasket: GasketModel
var _target := Vector3(0, 1.5, 0)   ## (high enough that the close-ups take in his whole head)
var _spin := 0.0


func _ready() -> void:
	_parse_args()
	build_arena(26, 14, 20, 1)
	rebar = RebarModel.new()
	rebar.position = Vector3.ZERO
	add_child(rebar)
	wick = WickModel.new()
	gasket = GasketModel.new()
	for m: LowPolyModel in [wick, gasket]:
		add_child(m)
		m.position = Vector3(0, 0, 40)   # out of shot but in the crew view
	old_hero = HeroFactory.spawn_hero(Vector2i.ZERO, "", Color(0.3, 0.55, 0.95))
	old_hero.facing = Vector3(0, 0, -1)
	old_hero.set_physics_process(false)
	make_camera()
	if shot_path != "":
		for m: LowPolyModel in [rebar, wick, gasket]:
			m.idle_enabled = false
			m.apply_idle(0.6)
		if pose == "punch":
			rebar.parts["arm_r"].rotation.x = 1.4
		_run_shots()
	else:
		_place_view("three_quarter")


func _parse_args() -> void:
	pose = arg(args, "--pose")


## Orbit the camera around Rebar and put the old hero on the camera's right.
func _place_view(view: String) -> void:
	var v: Array = VIEWS[view]
	var yaw := deg_to_rad(float(v[0]))
	var size := float(v[2])
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var crew := view == "crew"
	var is_game := view == "game" or crew
	var dist := 60.0
	var tgt := _target
	if view == "game":
		tgt = right * 1.1 + Vector3(0, 0.8, 0)
	elif crew:
		tgt = Vector3(0, 0.9, 0)
	elif view == "head":
		tgt = Vector3(0, 3.0, 0)
	elif view.begins_with("slam"):
		tgt = Vector3(0, 1.9, 0)
	elif view == "bowl":
		tgt = Vector3(0, 2.4, 0)
	_slam(view)
	aim(float(v[0]), float(v[1]), size, tgt, dist)
	# Old hero beside Rebar: on the camera's right (so they are side by side on screen)
	var gap := 2.3 if not is_game else 2.6
	old_hero.global_position = Vector3(0, 0, 0) + right * gap
	if crew or view == "head":
		old_hero.global_position = Vector3(0, 0, -40)
	# both face the camera (front) so the comparison is fair; Rebar keeps his local -Z forward
	rebar.rotation.y = 0.0
	if is_game:
		# in the game view face roughly toward the camera, like the in-game default
		rebar.rotation.y = yaw + PI
	old_hero.facing = Vector3(0, 0, -1).rotated(Vector3.UP, rebar.rotation.y)
	old_hero._visual_yaw = atan2(-old_hero.facing.x, -old_hero.facing.z)
	old_hero._visual.rotation.y = old_hero._visual_yaw
	wick.position = -right * CREW_GAP if crew else Vector3(0, 0, 40)
	gasket.position = right * CREW_GAP if crew else Vector3(0, 0, 40)
	wick.rotation.y = rebar.rotation.y
	gasket.rotation.y = rebar.rotation.y


## Freeze the slam's top (slam_up) or bottom (slam: both fists down in front, the torso bent), or the bowl's
## follow-through (bowl), for the clip check.
func _slam(view: String) -> void:
	if shot_path == "":
		return
	rebar._arm_kick["slam_w"] = 1.0 if view.begins_with("slam") else 0.0
	rebar._arm_kick["slam_a"] = RebarModel.SLAM_UP if view == "slam_up" else RebarModel.SLAM_DOWN
	rebar._arm_kick["bowl_w"] = 1.0 if view == "bowl" else 0.0
	rebar._arm_kick["bowl_a"] = RebarModel.BOWL_FOLLOW
	rebar.apply_idle(0.6)


func _process(delta: float) -> void:
	if shot_path == "":
		_spin += delta * 0.4
		var yaw := _spin
		camera.global_position = _target + Vector3(sin(yaw) * 0.6, 0.55, cos(yaw) * 0.6).normalized() * 60.0
		camera.look_at(_target, Vector3.UP)
		camera.size = 5.0
		old_hero.global_position = Vector3(cos(yaw), 0, -sin(yaw)) * 2.3


func _run_shots() -> void:
	await wait_frames(20)
	var base := shot_path.get_basename()
	var views: Array[String] = SHEET_ORDER.duplicate()
	if only_view != "":
		views = [only_view]
	elif arg(args, "--views") != "":   # a comma list: each as <base>_<view>.png, no sheet
		views.assign(arg(args, "--views").split(","))
	var images: Array[Image] = []
	for view in views:
		if view == "headshot":   # the party HUD's portrait (Headshots), x3 nearest
			var shots := Headshots.new()
			add_child(shots)
			if shots.texture("hero:rebar") == null:
				await shots.rendered
			var pic := Headshots.cached("hero:rebar").get_image()
			pic.resize(pic.get_width() * 3, pic.get_height() * 3, Image.INTERPOLATE_NEAREST)
			save_shot(pic, shot_path if only_view != "" else "%s_%s.png" % [base, view])
			shots.queue_free()
			continue
		_place_view(view)
		var img := await grab()
		var out_path := shot_path if only_view != "" else "%s_%s.png" % [base, view]
		if view == "game":
			# true game zoom: centre crop, nearest upscale x3 so the pixels are inspectable
			var cw := 400
			var ch := 280
			var crop := img.get_region(Rect2i((img.get_width() - cw) / 2, (img.get_height() - ch) / 2, cw, ch))
			crop.resize(cw * 3, ch * 3, Image.INTERPOLATE_NEAREST)
			crop.save_png("%s_game_crop.png" % base)
		elif view == "crew":
			# the game's pixels: a crop round the three of them, nearest upscale x3 so the pixels are inspectable
			var w := 300
			var hh := 170
			var c := img.get_region(Rect2i((img.get_width() - w) / 2, (img.get_height() - hh) / 2 - 20, w, hh))
			c.resize(w * 3, hh * 3, Image.INTERPOLATE_NEAREST)
			c.save_png("%s_crew_crop.png" % base)
		save_shot(img, out_path)
		images.append(img)
	if only_view == "" and arg(args, "--views") == "":
		save_sheet(images, 3, 2)
	finish()
