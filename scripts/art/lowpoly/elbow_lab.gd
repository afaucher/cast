extends LabBase
## The elbow IK lab (docs/design/animation-research.md, "Elbow IK study (2026-10-24)"): LOOK-DEV ONLY. Each hero with
## today's one-piece arms next to the same hero with the IK arms (TwoBoneIK; LowPolyModel.elbow_pick per model), frozen in
## the same poses. Left to right: Wick today, Wick IK, Gasket today, Gasket IK, Rebar today, Rebar IK.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/elbow_lab.tscn --shot <abs.png>
##       writes, for each pose, <base>_<pose>_game.png (all six at the game camera: yaw 45, pitch -56, size 24, a x3 crop
##       of the middle) and <base>_<pose>_<hero>.png (that hero's pair at the same angle, zoomed), and a contact sheet of
##       the pairs at <png>
##   godot --path . --headless -- --scene res://scenes/elbow_lab.tscn --bench 200
##       times apply_idle for 200 of each hero, today's arms and then the IK arms, and prints the numbers
## No --shot / --bench: the six stand in a row and cycle through the poses every 1.5 s.

## Poses, each hero's own version: "draw" is Wick's bow draw, Gasket's smash at the top and Rebar's slam at the top;
## "windup" Wick's bash wind-up, Gasket's wrench wind-up, Rebar's punch cocked; "strike" the bash, the smash's bottom, the
## punch; "slam" Wick's follow-through, Gasket's spin, Rebar's slam at the bottom.
const POSES: Array[String] = ["rest", "walk", "draw", "windup", "strike", "slam", "cast"]
const HEROES: Array[String] = ["wick", "gasket", "rebar"]
const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const CLOSE := {"wick": [4.2, 1.1], "gasket": [4.0, 0.8], "rebar": [5.6, 1.5]}   ## hero -> [ortho size, aim height]
const SLOTS := [-5.2, -3.6, -1.7, -0.2, 2.0, 4.2]                               ## along the camera's right axis
const TURN := 0.6             ## the models turn this far from facing the camera so their right arms show

var models: Array[LowPolyModel] = []
var _cycle := 0.0
var _pose_i := 0


func _ready() -> void:
	var bench := int(arg(args, "--bench", "0"))
	if bench > 0:
		await get_tree().process_frame
		_bench(bench)
		finish()
		return
	build_arena(14, 10, 12, 1)
	make_camera()
	for i in 6:
		var m := _make(HEROES[i / 2])
		m.elbow_pick = i % 2
		m.idle_enabled = false
		add_child(m)
		models.append(m)
	_place()
	_pose(POSES[0])
	if shot_path != "":
		_run_shots()


static func _make(hero: String) -> LowPolyModel:
	match hero:
		"wick":
			return WickModel.new()
		"gasket":
			return GasketModel.new()
	return RebarModel.new()


func _right() -> Vector3:
	var yaw := deg_to_rad(GAME_YAW)
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func _place() -> void:
	for i in models.size():
		models[i].global_position = _right() * float(SLOTS[i])
		models[i].rotation.y = deg_to_rad(GAME_YAW) + PI + TURN
	aim(GAME_YAW, GAME_PITCH, GAME_SIZE, Vector3(0.0, 0.9, 0.0))


## Freeze every model in `pose` (each hero in its own version of it).
func _pose(pose: String) -> void:
	for m in models:
		if m is WickModel:
			_pose_wick(m as WickModel, pose)
		elif m is GasketModel:
			_pose_gasket(m as GasketModel, pose)
		else:
			_pose_rebar(m as RebarModel, pose)


func _pose_wick(m: WickModel, pose: String) -> void:
	match pose:
		"walk":
			m.pose_preview("rest")
			m.apply_idle(3.0 * PI / 18.0, 4.0)
		"draw":
			m.pose_preview("shoot")
		"windup":
			m.pose_preview("rest")
			m._arm_kick["bash"] = 1.0
			m.apply_idle(0.6)
		"strike":
			m.pose_preview("bash")
		"slam":
			m.pose_preview("rest")
			m._arm_kick["follow"] = 1.0
			m.apply_idle(0.6)
			m._arm_kick["follow"] = 0.0
		"cast":
			m.pose_preview("cast")
		_:
			m.pose_preview("rest")


func _pose_gasket(m: GasketModel, pose: String) -> void:
	for k: String in ["weapon", "spin", "smash_w", "smash_a"]:
		m._arm_kick[k] = 0.0
	var speed := 0.0
	var t := 0.6
	match pose:
		"walk":
			speed = 4.0
			t = 3.0 * PI / 16.0
		"draw":
			m._arm_kick["smash_w"] = 1.0
			m._arm_kick["smash_a"] = GasketModel.SMASH_UP
		"windup":
			m._arm_kick["weapon"] = 1.0
		"strike":
			m._arm_kick["smash_w"] = 1.0
			m._arm_kick["smash_a"] = GasketModel.SMASH_DOWN
		"slam":
			m._arm_kick["spin"] = 1.0
		"cast":
			m._arm_kick["weapon"] = 0.9
	m.apply_idle(t, speed)


func _pose_rebar(m: RebarModel, pose: String) -> void:
	for k: String in ["arm_l", "arm_r", "slam_w", "slam_a", "bowl_w", "bowl_a"]:
		m._arm_kick[k] = 0.0
	var speed := 0.0
	var t := 0.6
	match pose:
		"walk":
			speed = 4.5
			t = 3.0 * PI / 14.0
		"draw":
			m._arm_kick["slam_w"] = 1.0
			m._arm_kick["slam_a"] = RebarModel.SLAM_UP
		"windup":
			m._arm_kick["arm_r"] = -0.6
		"strike":
			m._arm_kick["arm_r"] = 1.55
		"slam":
			m._arm_kick["slam_w"] = 1.0
			m._arm_kick["slam_a"] = RebarModel.SLAM_DOWN
		"cast":
			m._arm_kick["arm_l"] = 0.9
			m._arm_kick["arm_r"] = 0.9
	m.apply_idle(t, speed)


func _process(delta: float) -> void:
	if shot_path != "" or models.is_empty():
		return
	_cycle += delta
	if _cycle > 1.5:
		_cycle = 0.0
		_pose_i = (_pose_i + 1) % POSES.size()
		_pose(POSES[_pose_i])


func _run_shots() -> void:
	await wait_frames(20)
	var base := shot_path.get_basename()
	var sheet: Array[Image] = []
	for pose in POSES:
		_pose(pose)
		aim(GAME_YAW, GAME_PITCH, GAME_SIZE, Vector3(0.0, 0.9, 0.0))
		var img := await grab()
		var cw := 600
		var ch := 220
		var crop := img.get_region(Rect2i((img.get_width() - cw) / 2, (img.get_height() - ch) / 2 - 20, cw, ch))
		crop.resize(cw * 3, ch * 3, Image.INTERPOLATE_NEAREST)
		save_shot(crop, "%s_%s_game.png" % [base, pose])
		for h in HEROES.size():
			var hero := HEROES[h]
			var mid := (float(SLOTS[h * 2]) + float(SLOTS[h * 2 + 1])) * 0.5
			var c: Array = CLOSE[hero]
			aim(GAME_YAW, GAME_PITCH, float(c[0]), _right() * mid + Vector3(0.0, float(c[1]), 0.0))
			var shot := await snap("%s_%s_%s.png" % [base, pose, hero])
			if hero != "gasket":
				sheet.append(shot)
	save_sheet(sheet, 2, 2)
	finish()


## Time apply_idle for n of each hero with today's arms, then with the IK arms (in the tree, posed by hand: the pose maths
## and the transform updates, which is all the IK adds per frame; drawing is not counted).
func _bench(n: int) -> void:
	const FRAMES := 120
	for hero: String in HEROES:
		var res := {}
		for pick: int in [0, 1]:
			var ms: Array[LowPolyModel] = []
			for i in n:
				var m := _make(hero)
				m.elbow_pick = pick
				m.idle_enabled = false
				add_child(m)
				m.apply_idle(0.0, 0.0)
				ms.append(m)
			var t0 := Time.get_ticks_usec()
			for f in FRAMES:
				var t := f / 60.0
				for m in ms:
					m.apply_idle(t, 4.0 if (f / 30) % 2 == 0 else 0.0)
			var us := float(Time.get_ticks_usec() - t0) / float(FRAMES * n)
			res[pick] = us
			print("bench %s %s: %.1f us per model per frame (%d models, %d frames), %d parts" % [hero, "ik" if pick == 1 else "old",
					us, n, FRAMES, ms[0].parts.size()])
			for m in ms:
				m.free()
		print("bench %s: the IK arms add %.1f us per model per frame (x%.2f)" % [hero, float(res[1]) - float(res[0]),
				float(res[1]) / float(res[0])])
