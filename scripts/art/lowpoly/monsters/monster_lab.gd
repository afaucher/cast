extends LabBase
## Monster look-dev lab: the real terrain look (HexMapView + DungeonLook) with the four faceted monsters
## (grunt, archer, brute, swarmer) and the three heroes (Wick, Gasket, Rebar) for scale. Scene:
## scenes/monster_lab.tscn. A separate lab from character_lab.gd so the hero labs stay untouched.
##
##   godot --path . -- --scene res://scenes/monster_lab.tscn --shot <abs.png>
##
## --shot <png>   renders every view, then quits:
##                  <base>_<kind>_<view>.png   close-ups of each monster (front, three_quarter, back, overhead,
##                                              windup, swing), kind in grunt / archer / brute / swarmer
##                  <base>_lineup.png          low angle, heroes and monsters side by side
##                  <base>_game.png (+ _game_crop.png)          the real game camera (yaw 45, pitch -56, size 24),
##                                              everyone standing in a row facing the camera
##                  <base>_game_windup.png (+ _crop)            same, monsters frozen in their attack telegraph
##                  <base>_fight.png (+ _fight_crop.png)        heroes facing the monsters, as in play
##                  <base>_row.png / <base>_row_windup.png      the four monsters alone, front view
##                and a contact sheet of the close-ups at <png>.
## --view <name>  only that view, written to <png> exactly (add --kind <kind> for a close-up view).
## No --shot: opens the lab, orbits slowly with idle animation, and the monsters cycle windup / strike.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0

const KINDS: Array[String] = ["grunt", "archer", "brute", "swarmer"]
const CLOSE_VIEWS: Array[String] = ["front", "three_quarter", "back", "overhead", "windup", "swing"]
const GROUP_VIEWS: Array[String] = ["lineup", "game", "game_windup", "fight", "row", "row_windup"]

## close-up views: name -> [camera yaw deg (180 = in front, models face -Z), pitch deg, pose: rest|windup|swing]
const CLOSE := {
	"front": [180.0, -14.0, "rest"],
	"three_quarter": [142.0, -26.0, "rest"],
	"back": [0.0, -20.0, "rest"],
	"overhead": [180.0, -72.0, "rest"],
	"windup": [142.0, -26.0, "windup"],
	"swing": [142.0, -26.0, "swing"],
}
## kind -> [ortho size for a close-up, height aimed at]
const FRAME := {
	"grunt": [3.4, 0.95],
	"archer": [3.6, 0.95],
	"brute": [4.8, 1.3],
	"swarmer": [2.0, 0.45],
}
## group views: name -> [camera yaw deg, pitch deg, ortho size, aim height, pose, layout]
const GROUP := {
	"lineup": [160.0, -22.0, 12.5, 1.1, "rest", "row"],
	"game": [GAME_YAW, GAME_PITCH, GAME_SIZE, 0.6, "rest", "row"],
	"game_windup": [GAME_YAW, GAME_PITCH, GAME_SIZE, 0.6, "windup", "row"],
	"fight": [GAME_YAW, GAME_PITCH, GAME_SIZE, 0.6, "rest", "fight"],
	"row": [180.0, -14.0, 7.5, 1.2, "rest", "monsters"],
	"row_windup": [150.0, -22.0, 7.5, 1.2, "windup", "monsters"],
}

var only_kind := ""
var wick: WickModel
var gasket: GasketModel
var rebar: RebarModel
var monsters := {}                       ## kind -> MonsterModel
var extra_swarmers: Array[MonsterModel] = []
var _orbit := 0.0
var _cycle := 0.0


func _ready() -> void:
	_parse_args()
	build_arena(26, 14, 20, 1)
	wick = WickModel.new()
	gasket = GasketModel.new()
	rebar = RebarModel.new()
	for h: Node3D in [wick, gasket, rebar]:
		add_child(h)
	for k in KINDS:
		var m := MonsterModels.make(k)
		monsters[k] = m
		add_child(m)
	for i in 2:
		var m2 := MonsterModels.make("swarmer")
		extra_swarmers.append(m2)
		add_child(m2)
	make_camera()
	if shot_path != "":
		for m: LowPolyModel in _all_models():
			m.idle_enabled = false
			m.apply_idle(0.6)
		_run_shots()
	else:
		_place_group("lineup")


func _parse_args() -> void:
	only_kind = arg(args, "--kind")


func _heroes() -> Array[LowPolyModel]:
	var out: Array[LowPolyModel] = [wick, gasket, rebar]
	return out


func _all_models() -> Array[LowPolyModel]:
	var out: Array[LowPolyModel] = _heroes()
	for k in KINDS:
		out.append(monsters[k])
	for m in extra_swarmers:
		out.append(m)
	return out


func _monster_list() -> Array[MonsterModel]:
	var out: Array[MonsterModel] = []
	for k in KINDS:
		out.append(monsters[k])
	for m in extra_swarmers:
		out.append(m)
	return out


func _pose_monsters(pose: String) -> void:
	for m in _monster_list():
		m.pose_preview(pose, 1.0)


func _park_all() -> void:
	var i := 0
	for m in _all_models():
		m.global_position = Vector3(80.0 + 4.0 * float(i), 0.0, 80.0)
		i += 1


## Camera aimed at `tgt` from yaw / pitch (degrees).
## A close-up of one monster at the origin.
func _place_close(kind: String, view: String) -> void:
	_park_all()
	var v: Array = CLOSE[view]
	var f: Array = FRAME[kind]
	var m: MonsterModel = monsters[kind]
	m.global_position = Vector3.ZERO
	m.rotation.y = 0.0
	aim(float(v[0]), float(v[1]), float(f[0]), Vector3(0.0, float(f[1]), 0.0))
	_pose_monsters("rest")
	m.pose_preview(String(v[2]), 1.0)


## x offsets along the camera's right axis for the row layout: heroes, then monsters, then the swarm.
func _row_slots() -> Array:
	return [[wick, -8.4, 0.0], [gasket, -6.1, 0.0], [rebar, -3.5, 0.0],
			[monsters["grunt"], -0.6, 0.0], [monsters["archer"], 1.6, 0.0], [monsters["brute"], 4.3, 0.0],
			[monsters["swarmer"], 6.9, 0.0], [extra_swarmers[0], 7.7, 0.9], [extra_swarmers[1], 7.9, -0.9]]


## Hero group on the left, monsters on the right, all facing each other, as in play.
func _fight_slots() -> Array:
	return [[wick, -6.0, 2.0], [gasket, -5.2, -0.6], [rebar, -3.6, 1.2],
			[monsters["grunt"], 0.4, -0.8], [monsters["archer"], 3.6, 2.4], [monsters["brute"], 2.6, 0.5],
			[monsters["swarmer"], 1.2, 1.6], [extra_swarmers[0], 1.8, 2.4], [extra_swarmers[1], 0.8, -2.0]]


func _place_group(view: String) -> void:
	_park_all()
	var v: Array = GROUP[view]
	var yaw := deg_to_rad(float(v[0]))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))   # away from the camera
	var layout: String = v[5]
	var slots: Array
	var mid := Vector3.ZERO
	match layout:
		"monsters":
			slots = [[monsters["grunt"], -4.6, 0.0], [monsters["archer"], -1.6, 0.0], [monsters["brute"], 1.9, 0.0], [monsters["swarmer"], 4.7, 0.0]]
		"fight":
			slots = _fight_slots()
			mid = right * -1.0
		_:
			slots = _row_slots()
			mid = right * -0.4
	aim(float(v[0]), float(v[1]), float(v[2]), mid + Vector3(0.0, float(v[3]), 0.0))
	var toward_cam := float(v[0]) * PI / 180.0 + PI    # facing the camera
	for e: Array in slots:
		var n: LowPolyModel = e[0]
		n.global_position = right * float(e[1]) + fwd * float(e[2])
		if layout == "fight":
			var is_hero := n == wick or n == gasket or n == rebar
			var face_dir := right if is_hero else -right
			n.rotation.y = atan2(-face_dir.x, -face_dir.z)
		else:
			n.rotation.y = toward_cam
	_pose_monsters(String(v[4]))
	for h in _heroes():
		h.apply_idle(0.6)


func _process(delta: float) -> void:
	if shot_path != "":
		return
	_orbit += delta * 0.35
	var yaw := 120.0 + 40.0 * sin(_orbit)
	var right := Vector3(cos(deg_to_rad(yaw)), 0.0, -sin(deg_to_rad(yaw)))
	for e: Array in _row_slots():
		var n: Node3D = e[0]
		n.global_position = right * float(e[1]) + Vector3(0.0, 0.0, float(e[2]))
	var tgt := right * -0.4 + Vector3(0.0, 1.1, 0.0)
	aim(yaw + 40.0, -24.0, 12.5, tgt)
	_cycle += delta
	if _cycle > 4.0:
		_cycle = 0.0
		var tw := create_tween()
		for m in _monster_list():
			tw.parallel().tween_method(m.windup, 0.0, 1.0, 1.0)
		tw.tween_callback(_strike_all)
	for m in _monster_list():
		m.rotation.y = deg_to_rad(yaw + 180.0)
	for h in _heroes():
		h.rotation.y = deg_to_rad(yaw + 180.0)


func _strike_all() -> void:
	for m in _monster_list():
		m.windup(0.0)
		m.attack_swing()


# ------------------------------------------------------------------ screenshots

## Save a centre crop of the three-heroes-plus-monsters area at x2 (nearest) so game-zoom pixels are inspectable.
func _save_crop(img: Image, path: String) -> void:
	var cw := 840
	var ch := 300
	var crop := img.get_region(Rect2i((img.get_width() - cw) / 2, (img.get_height() - ch) / 2 - 10, cw, ch))
	crop.resize(cw * 2, ch * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png(path)


func _run_shots() -> void:
	await wait_frames(20)
	var base := shot_path.get_basename()
	var sheet_imgs: Array[Image] = []
	if only_view != "":
		if CLOSE.has(only_view):
			var kind := only_kind if only_kind != "" else "grunt"
			_place_close(kind, only_view)
		else:
			_place_group(only_view)
		var img := await snap(shot_path)
		if only_view.begins_with("game") or only_view == "fight":
			_save_crop(img, "%s_crop.png" % base)
		finish()
		return
	for kind in KINDS:
		for view in CLOSE_VIEWS:
			_place_close(kind, view)
			var img := await snap("%s_%s_%s.png" % [base, kind, view])
			if view in ["front", "three_quarter", "overhead", "windup"]:
				sheet_imgs.append(img)
	for view in GROUP_VIEWS:
		_place_group(view)
		var img := await snap("%s_%s.png" % [base, view])
		if view.begins_with("game") or view == "fight":
			_save_crop(img, "%s_%s_crop.png" % [base, view])
	save_sheet(sheet_imgs, 4, 3)
	finish()
