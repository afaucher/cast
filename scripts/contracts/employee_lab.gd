extends LabBase
## Employee look-dev lab: the real terrain look with both employee styles (bunker staff and lair
## henchmen) cowering, panicking away from a skeleton and following Wick, plus close-ups of every mood.
##
##   godot --path . -- --scene res://scenes/employee_lab.tscn --shot <abs.png> [--view game|close]
##
## --shot <png>   renders every view then quits:
##                  <base>_game.png (+ _game_crop.png)   the real game camera, everyone in a row
##                  <base>_close_<style>_<mood>.png      close-ups, mood in cower / panic / follow / cheer
##                  and a contact sheet of the close-ups at <png>
## --view game    only the game view, written to <png> exactly (and <base>_crop.png)
## --view close   only the close-ups, <base>_close_<style>_<mood>.png (no sheet)
## No --shot: opens the lab with the live AI (the employees react to the skeleton and to Wick).

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const CLOSE_YAW := 156.0
const CLOSE_PITCH := -22.0
const CLOSE_SIZE := 4.2
const MOODS: Array[String] = ["cower", "panic", "follow", "cheer"]
const SPACING := 2.3

var wick: Hero
var grunt: Monster
var row: Array[Node3D] = []              ## everything standing in the game-view row
var dummies := {}                        ## style -> Employee used for the close-ups
var _spin := 0.0


func _ready() -> void:
	build_arena(26, 14, 20, 1)
	make_camera()
	_build_row()
	if shot_path != "":
		_run_shots()
	else:
		aim(GAME_YAW, GAME_PITCH, 16.0, Vector3(0, 0.8, 0))


## The game-view row, left to right along the camera's right axis:
## cowering staff + henchman | panicking staff + henchman, a skeleton behind them | Wick, with a staffer
## and a henchman trotting after him.
func _build_row() -> void:
	var right := _right(GAME_YAW)
	var toward_cam := Vector3(sin(deg_to_rad(GAME_YAW)), 0, cos(deg_to_rad(GAME_YAW)))   # unit vector pointing at the camera
	var shot := shot_path != ""
	var slots := 9
	var x0 := -SPACING * (slots - 1) * 0.5
	var i := 0
	var cow_s := _employee("staff", "Beatrice", right * (x0 + SPACING * 0.0))
	var cow_h := _employee("henchman", "Gary", right * (x0 + SPACING * 1.0))
	var pan_s := _employee("staff", "Mabel", right * (x0 + SPACING * 2.6))
	var pan_h := _employee("henchman", "Steve", right * (x0 + SPACING * 3.6) + toward_cam * 0.6)
	grunt = MonsterFactory.spawn("grunt", Hex.from_world(right * (x0 + SPACING * 5.0) - toward_cam * 1.8))
	grunt.global_position = right * (x0 + SPACING * 5.0) - toward_cam * 1.8
	grunt.set_physics_process(shot_path == "")
	var wick_model := WickModel.new()
	wick = HeroFactory.spawn_hero(Hex.from_world(right * (x0 + SPACING * 6.6)), "Wick", Color(0.3, 0.55, 0.95), "sword", wick_model, "wick")
	wick.global_position = right * (x0 + SPACING * 6.6)
	wick.set_physics_process(false)
	var fol_s := _employee("staff", "Stan", right * (x0 + SPACING * 7.6) + toward_cam * 0.9)
	var fol_h := _employee("henchman", "Kevin", right * (x0 + SPACING * 8.4) + toward_cam * 0.1)
	for n: Node3D in [cow_s, cow_h, pan_s, pan_h, grunt, wick, fol_s, fol_h]:
		row.append(n)
	if shot:
		for e: Employee in [cow_s, cow_h]:
			_pin(e, "cower", 0.0, "", toward_cam, 0.6 + 0.37 * i)
			i += 1
		for e: Employee in [pan_s, pan_h]:
			_pin(e, "panic", 3.6, "", toward_cam, 0.7 + 0.31 * i)
			i += 1
		cow_s.say("help!", 9999.0)
		cow_h.say("boss?!", 9999.0)
		pan_s.say("AAAH!", 9999.0)
		pan_h.say("NOPE!", 9999.0)
		for e: Employee in [fol_s, fol_h]:
			_pin(e, "follow", 3.2, "", toward_cam, 0.6 + 0.43 * i)
			i += 1
		# the followers face the way Wick faces; the panickers run from the skeleton, so they face the camera
		for e: Employee in [fol_s, fol_h]:
			_face(e, toward_cam)
		for e: Employee in [cow_s, cow_h, pan_s, pan_h]:
			_refresh(e)
		wick_model.idle_enabled = false
		wick_model.apply_idle(0.6, 3.2)
		wick.facing = toward_cam
		wick._visual_yaw = atan2(-toward_cam.x, -toward_cam.z)
		wick._visual.rotation.y = wick._visual_yaw
		_face_monster(grunt, toward_cam)
		fol_s.say("oh, thank you!", 9999.0)
		_refresh(fol_s)
		_refresh(fol_h)
	# the close-up dummies sit off to the side, hidden until needed
	for st in EmployeeModel.STYLES:
		var d := _employee(st, "Beatrice" if st == "staff" else "Gary", Vector3(0, 0, 40))
		dummies[st] = d
		d.visible = false
		d.set_physics_process(false)


func _employee(style: String, nm: String, pos: Vector3) -> Employee:
	var e := Employee.spawn(Hex.from_world(pos), {"style": style, "name": nm})
	e.global_position = Vector3(pos.x, 0.0, pos.z)
	return e


static func _right(yaw_deg: float) -> Vector3:
	var yaw := deg_to_rad(yaw_deg)
	return Vector3(cos(yaw), 0, -sin(yaw))


## Freeze an employee in a pose for a screenshot: no AI, no idle, the bubble and name tag forced on.
func _pin(e: Employee, mood: String, walk_speed: float, text: String, face_dir: Vector3, t: float) -> void:
	e.set_physics_process(false)
	e.model.idle_enabled = false
	e.model.pose_preview(mood, t, walk_speed)
	e._hero_near = true
	match mood:
		"cower":
			e.state = Employee.State.COWER
		"panic":
			e.state = Employee.State.PANIC
		"follow":
			e.state = Employee.State.FOLLOW
		"cheer":
			e.state = Employee.State.EXTRACT
	if text != "":
		e.say(text, 9999.0)
	_face(e, face_dir)


func _face(e: Employee, dir: Vector3) -> void:
	e.facing = dir
	e._visual.rotation.y = atan2(-dir.x, -dir.z)


func _face_monster(m: Monster, dir: Vector3) -> void:
	m.facing = dir
	m._visual.rotation.y = atan2(-dir.x, -dir.z)


func _refresh(e: Employee) -> void:
	e._update_visual(0.0)


func _process(delta: float) -> void:
	if shot_path == "":
		_spin += delta * 0.25
		var yaw := GAME_YAW + sin(_spin) * 25.0
		aim(yaw, GAME_PITCH + 6.0, 16.0, Vector3(0, 0.8, 0))


# ---------------------------------------------------------------------------------------------
# Shots

func _run_shots() -> void:
	await wait_frames(20)
	var base := shot_path.get_basename()
	if only_view == "" or only_view == "game":
		aim(GAME_YAW, GAME_PITCH, GAME_SIZE, Vector3(0, 0.6, 0))
		var img := await grab()
		var out_path := shot_path if only_view == "game" else "%s_game.png" % base
		save_shot(img, out_path)
		var cw := 560
		var ch := 340
		var crop := img.get_region(Rect2i((img.get_width() - cw) / 2, (img.get_height() - ch) / 2, cw, ch))
		crop.resize(cw * 2, ch * 2, Image.INTERPOLATE_NEAREST)
		var crop_path := ("%s_crop.png" % base) if only_view == "game" else ("%s_game_crop.png" % base)
		crop.save_png(crop_path)
		# a closer look at the escort trio
		aim(GAME_YAW, GAME_PITCH, 9.0, _right(GAME_YAW) * (SPACING * 3.4) + Vector3(0, 0.8, 0))
		var img2 := await grab()
		var out2 := ("%s_trio.png" % base) if only_view == "game" else ("%s_game_trio.png" % base)
		save_shot(img2, out2)
	if only_view == "" or only_view == "close":
		await _close_ups(base)
	finish()


func _close_ups(base: String) -> void:
	for n in row:
		n.visible = false
	var images: Array[Image] = []
	var toward := Vector3(sin(deg_to_rad(CLOSE_YAW)), 0, cos(deg_to_rad(CLOSE_YAW)))
	for st in EmployeeModel.STYLES:
		var e: Employee = dummies[st]
		e.visible = true
		e.global_position = Vector3(0, 0, 0)
		for mood in MOODS:
			var speed := 3.6 if mood == "panic" else (3.2 if mood == "follow" else 0.0)
			var text := ""
			match mood:
				"cower":
					text = "help!" if st == "staff" else "boss?!"
				"panic":
					text = "AAAH!" if st == "staff" else "NOPE!"
				"cheer":
					text = "thank you!"
				"follow":
					text = "oh, thank you!" if st == "staff" else "I'm with you!"
			_pin(e, mood, speed, text, toward, 0.6)
			e._hero_near = true
			e._update_visual(0.0)
			aim(CLOSE_YAW, CLOSE_PITCH, CLOSE_SIZE, Vector3(0, 1.45, 0))
			var img := await grab()
			var out_path := "%s_close_%s_%s.png" % [base, st, mood]
			save_shot(img, out_path)
			images.append(img)
		e.visible = false
	if only_view == "":
		save_sheet(images, 4, 3)
