extends LabBase
## The elbow study's lab (docs/design/animation-research.md, "Elbow IK study (2026-10-24)"): LOOK-DEV ONLY. Gasket and the
## grunt with today's arms next to the same models with the IK arms (TwoBoneIK; LowPolyModel.elbow_pick per model), frozen
## in the same poses, at the game camera. Left to right: Gasket today, Gasket IK, the grunt today, the grunt IK.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/elbow_lab.tscn --shot <abs.png>
##       writes <base>_<pose>_game.png (the game camera: yaw 45, pitch -56, size 24, a x3 crop of the middle),
##       <base>_<pose>_close.png (the same angle at size 6) for each pose, and a contact sheet of the close-ups at <png>
##   godot --path . --headless -- --scene res://scenes/elbow_lab.tscn --bench 200
##       times apply_idle for 200 Gaskets and 200 grunts, today's arms and then the IK arms, and prints the numbers
## No --shot / --bench: the four stand in a row and cycle through the poses every 1.5 s.

const POSES: Array[String] = ["rest", "walk", "windup", "strike", "overhead", "cast"]
const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const CLOSE_SIZE := 4.6
const GAP := 1.55
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
	build_arena(12, 8, 10, 1)
	make_camera()
	for i in 4:
		var m: LowPolyModel = GasketModel.new() if i < 2 else GruntModel.new()
		m.elbow_pick = i % 2
		m.idle_enabled = false
		add_child(m)
		models.append(m)
	_place()
	_pose(POSES[0])
	if shot_path != "":
		_run_shots()


func _place() -> void:
	var yaw := deg_to_rad(GAME_YAW)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	for i in models.size():
		var m := models[i]
		m.global_position = right * (float(i) - 1.5) * GAP + right * (0.35 if i >= 2 else 0.0)
		m.rotation.y = yaw + PI + TURN
	aim(GAME_YAW, GAME_PITCH, GAME_SIZE, Vector3(0.0, 0.7, 0.0))


## Freeze every model in `pose` (Gasket and the grunt each in their own version of it).
func _pose(pose: String) -> void:
	for m in models:
		if m is GasketModel:
			_pose_gasket(m as GasketModel, pose)
		else:
			_pose_grunt(m as GruntModel, pose)


func _pose_gasket(m: GasketModel, pose: String) -> void:
	for k: String in ["weapon", "spin", "smash_w", "smash_a"]:
		m._arm_kick[k] = 0.0
	var speed := 0.0
	var t := 0.6
	match pose:
		"walk":
			speed = 4.0
			t = 3.0 * PI / 16.0
		"windup":
			m._arm_kick["weapon"] = 1.0
		"strike":
			m._arm_kick["smash_w"] = 1.0
			m._arm_kick["smash_a"] = GasketModel.SMASH_DOWN
		"overhead":
			m._arm_kick["smash_w"] = 1.0
			m._arm_kick["smash_a"] = GasketModel.SMASH_UP
		"cast":
			m._arm_kick["weapon"] = 0.9
	m.apply_idle(t, speed)


func _pose_grunt(m: GruntModel, pose: String) -> void:
	m._wind = 0.0
	m._swing = 0.0
	m._cry = 0.0
	var speed := 0.0
	var t := 0.6
	match pose:
		"walk":
			speed = 4.0
			t = 3.0 * PI / 17.0
		"windup":
			m._wind = 1.0
		"strike":
			m._swing = 1.0
		"overhead", "cast":
			m._cry = 1.0
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
		aim(GAME_YAW, GAME_PITCH, GAME_SIZE, Vector3(0.0, 0.7, 0.0))
		var img := await grab()
		var cw := 520
		var ch := 200
		var crop := img.get_region(Rect2i((img.get_width() - cw) / 2, (img.get_height() - ch) / 2 - 20, cw, ch))
		crop.resize(cw * 3, ch * 3, Image.INTERPOLATE_NEAREST)
		save_shot(crop, "%s_%s_game.png" % [base, pose])
		aim(GAME_YAW, GAME_PITCH, CLOSE_SIZE, Vector3(0.0, 0.9, 0.0) - Vector3(cos(deg_to_rad(GAME_YAW)), 0.0, -sin(deg_to_rad(GAME_YAW))) * 0.3)
		sheet.append(await snap("%s_%s_close.png" % [base, pose]))
	save_sheet(sheet, 2, 2)
	finish()


## Time apply_idle for n Gaskets and n grunts with today's arms, then with the IK arms (in the tree, posed by hand: the
## pose maths and the transform updates, which is all the IK adds per frame; drawing is not counted).
func _bench(n: int) -> void:
	const FRAMES := 120
	for kind: String in ["gasket", "grunt"]:
		var res := {}
		for pick: int in [0, 1]:
			var ms: Array[LowPolyModel] = []
			for i in n:
				var m: LowPolyModel = GasketModel.new() if kind == "gasket" else GruntModel.new()
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
			print("bench %s %s: %.1f us per model per frame (%d models, %d frames), %d parts" % [kind, "ik" if pick == 1 else "old",
					us, n, FRAMES, ms[0].parts.size()])
			for m in ms:
				m.free()
		print("bench %s: the IK arms add %.1f us per model per frame (x%.2f); %d of them add %.2f ms a frame" % [kind,
				float(res[1]) - float(res[0]), float(res[1]) / float(res[0]), n, (float(res[1]) - float(res[0])) * n / 1000.0])
