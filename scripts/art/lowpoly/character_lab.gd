extends LabBase
## Character look-dev lab: the real terrain look (HexMapView + DungeonLook) with the faceted
## GasketModel, RebarModel and the old prototype hero side by side on a slate patch, an orbiting /
## fixed orthographic camera, and the game's own camera angle for the "game zoom" check.
## `focus_hero` picks the hero the close-up views frame: "gasket" (scenes/gasket_lab.tscn) or "wick"
## (scenes/wick_lab.tscn, which also stands Wick in the lineup, in front of Gasket and Rebar).
##
##   godot --path . -- --scene res://scenes/gasket_lab.tscn --shot <abs.png>
##
## --shot <png>  renders every view as <png minus .png>_<view>.png plus a contact sheet at <png>,
##               then quits. The game view also writes <base>_game_crop.png (centre crop, x3).
## --view <name> only that view as <png>.
## No --shot: opens the lab, orbits slowly with idle animation, and Gasket spins every few seconds.
##
## Views: front, three_quarter, back, overhead (close-ups of the focus hero), lineup (everyone), game
## (the real camera angle, size 24). Gasket lab: wind / hit (the wrench smash frozen at wind-up and
## impact), spin (mid-whirl). Wick lab: shoot (bow raised and drawn), cast (wand raised), bash.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0

## name -> [camera yaw deg (180 = in front of the heroes, who face -Z), pitch deg, ortho size, focus: hero|lineup]
const VIEWS := {
	"front": [180.0, -14.0, 3.2, "hero"],
	"three_quarter": [142.0, -26.0, 3.2, "hero"],
	"back": [0.0, -20.0, 3.2, "hero"],
	"overhead": [180.0, -72.0, 3.4, "hero"],
	"lineup": [160.0, -22.0, 6.4, "lineup"],
	"game": [GAME_YAW, GAME_PITCH, GAME_SIZE, "lineup"],
	"wind": [142.0, -26.0, 3.2, "hero"],
	"hit": [142.0, -26.0, 3.2, "hero"],
	"spin": [GAME_YAW, GAME_PITCH, 4.0, "hero"],
	"shoot": [142.0, -26.0, 3.2, "hero"],
	"cast": [142.0, -26.0, 3.2, "hero"],
	"bash": [142.0, -26.0, 3.2, "hero"],
	"shoot_game": [GAME_YAW, GAME_PITCH, 6.0, "hero"],
}
const SHEET_ORDER: Array[String] = ["front", "three_quarter", "back", "overhead", "lineup", "game", "wind", "hit", "spin"]
const SHEET_ORDER_WICK: Array[String] = ["front", "three_quarter", "back", "overhead", "lineup", "game", "shoot", "cast", "bash"]

const GAP_REBAR := 2.7     ## how far right (on screen) of Gasket each figure stands
const GAP_HERO := 4.9
## Wick lab lineup: x (on screen, from Wick) of Gasket, Rebar and the old hero.
const GAP_L_GASKET := 2.7
const GAP_L_REBAR := 5.3
const GAP_L_HERO := 7.7
## Close-up framing of a hero taller than Gasket: ortho size multiplier and the height aimed at.
const WICK_ZOOM := 1.35
const WICK_FOCUS_Y := 1.1

@export var focus_hero := "gasket"   ## "gasket" or "wick"

var gasket: GasketModel
var rebar: RebarModel
var wick: WickModel                ## only in the Wick lab
var old_hero: Hero
var _spin_t := 0.0
var _orbit := 0.0


func _ready() -> void:
	build_arena(26, 14, 20, 1)
	gasket = GasketModel.new()
	add_child(gasket)
	rebar = RebarModel.new()
	add_child(rebar)
	if focus_hero == "wick":
		wick = WickModel.new()
		add_child(wick)
	old_hero = HeroFactory.spawn_hero(Vector2i.ZERO, "", Color(0.3, 0.55, 0.95))
	old_hero.facing = Vector3(0, 0, -1)
	old_hero.set_physics_process(false)
	make_camera()
	if shot_path != "":
		for m: LowPolyModel in [gasket, rebar]:
			m.idle_enabled = false
			m.apply_idle(0.6)
		_run_shots()
	else:
		_place_view("lineup")


## The models in the scene (the focus hero first).
func _models() -> Array[LowPolyModel]:
	var out: Array[LowPolyModel] = []
	if wick != null:
		out.append(wick)
	out.append(gasket)
	out.append(rebar)
	return out


## Pose the frozen action views: Gasket's wrench wind-up / impact / mid-spin, Wick's shot, cast and bash.
func _pose_for(view: String) -> void:
	gasket._arm_kick["weapon"] = 0.0
	gasket._arm_kick["spin"] = 0.0
	gasket.parts["body"].rotation = Vector3.ZERO
	match view:
		"wind":
			gasket._arm_kick["weapon"] = 1.0
			gasket.parts["body"].rotation.x = -0.10
		"hit":
			gasket._arm_kick["weapon"] = -1.25
			gasket.parts["body"].rotation.x = 0.16
		"spin":
			gasket._arm_kick["spin"] = 1.0
	gasket.apply_idle(0.6)
	if wick != null:
		wick.pose_preview("shoot" if view.begins_with("shoot") else view)


## x offsets (along the camera's right axis) of everyone standing in the lineup.
func _lineup() -> Array:
	if wick != null:
		return [[wick, 0.0], [gasket, GAP_L_GASKET], [rebar, GAP_L_REBAR], [old_hero, GAP_L_HERO]]
	return [[gasket, 0.0], [rebar, GAP_REBAR], [old_hero, GAP_HERO]]


## Place the figures on the camera's right axis and aim the camera.
func _place_view(view: String) -> void:
	var v: Array = VIEWS[view]
	var yaw := deg_to_rad(float(v[0]))
	var focus: String = v[3]
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var zoom := WICK_ZOOM if wick != null else 1.0
	var tgt := Vector3(0, WICK_FOCUS_Y if wick != null else 0.85, 0)
	if focus == "lineup":
		var mid := GAP_L_HERO * 0.5 if wick != null else 2.45
		tgt = right * mid + Vector3(0, 1.1 if view == "lineup" else 0.6, 0)
		zoom = 1.0
	aim(float(v[0]), float(v[1]), float(v[2]) * zoom, tgt)
	# Everyone faces the camera in the angled views (as in game), else straight ahead (-Z).
	var face := 0.0
	if view == "game" or view == "spin" or view == "shoot_game":
		face = yaw + PI
	for entry: Array in _lineup():
		var n: Node3D = entry[0]
		var x: float = entry[1]
		if wick != null and focus == "hero" and n != wick:
			x += 14.0   # close-ups of Wick: the others stand well out of frame
		if n is Hero:
			var h := n as Hero
			h.global_position = right * x
			h.facing = Vector3(0, 0, -1).rotated(Vector3.UP, face)
			h._visual_yaw = atan2(-h.facing.x, -h.facing.z)
			h._visual.rotation.y = h._visual_yaw
		else:
			n.global_position = right * x
			n.rotation.y = face
	_pose_for(view)


func _process(delta: float) -> void:
	if shot_path != "":
		return
	_orbit += delta * 0.4
	var yaw := _orbit
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var mid := GAP_L_HERO * 0.5 if wick != null else 2.4
	var tgt := right * mid + Vector3(0, 1.0, 0)
	camera.global_position = tgt + Vector3(sin(yaw) * 0.6, 0.55, cos(yaw) * 0.6).normalized() * 60.0
	camera.look_at(tgt, Vector3.UP)
	camera.size = 6.4
	for entry: Array in _lineup():
		var n: Node3D = entry[0]
		n.global_position = right * float(entry[1])
	_spin_t += delta
	if _spin_t > 4.0:
		_spin_t = 0.0
		if wick != null:
			wick.shoot_pose()
		else:
			gasket.spin()


func _run_shots() -> void:
	await wait_frames(20)
	var base := shot_path.get_basename()
	var views: Array[String] = (SHEET_ORDER_WICK if wick != null else SHEET_ORDER).duplicate()
	if only_view != "":
		views = [only_view]
	var images: Array[Image] = []
	for view in views:
		_place_view(view)
		var img := await grab()
		var out_path := shot_path if only_view != "" else "%s_%s.png" % [base, view]
		if view == "game":
			# true game zoom: crop around the three figures, nearest upscale x3 so the pixels are inspectable
			var cw := 520
			var ch := 280
			var crop := img.get_region(Rect2i((img.get_width() - cw) / 2, (img.get_height() - ch) / 2, cw, ch))
			crop.resize(cw * 3, ch * 3, Image.INTERPOLATE_NEAREST)
			crop.save_png("%s_game_crop.png" % base)
		save_shot(img, out_path)
		images.append(img)
	if only_view == "":
		save_sheet(images, 3, 2)
	finish()
