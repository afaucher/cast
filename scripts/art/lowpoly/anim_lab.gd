extends LabBase
## Animation-feel look-dev lab (docs/design/animation-research.md). LOOK-DEV ONLY: nothing here is wired into the game.
## Three copies of one real hero (a real Hero node with its faceted model, moved by Hero.move, hit by apply_damage, shoved
## by Actor.shove, swinging by Hero.melee) stand side by side and play the same scripted clip:
##
##   lane 1 "Today"        the game as it is (the model's own idle / walk clock, the hero's cast and swing poses)
##   lane 2 "B grounded"   + the proposed locomotion layer (anim_lab_feel.gd level 1: stride matched to speed, legs turned
##                         toward the walk, a springy lean that leads the velocity, squash on start / stop)
##   lane 3 "C actions"    + the action layer (level 2: a voice-cast channel and release, a hit flinch with hit-stop, a
##                         strike-first melee with a lunge and an attacker hit-stop)
##
##   godot --path . --fixed-fps 60 --resolution 1920x1080 -- --scene res://scenes/anim_lab.tscn --hero wick
##         --clip startstop --shot <abs.png> [--zoom close|game] [--frames-dir <abs dir>]
##   godot --path . --fixed-fps 60 -- --scene res://scenes/anim_lab.tscn --hero gasket --measure
##
## --hero wick|gasket|rebar   the hero (default wick)
## --clip <name>              startstop, strafe, turn, cast, hit, attack (default startstop)
## --shot <png>               saves the clip's strip (3 rows: the lanes; 8 columns: the clip's strip times) and quits
## --zoom close|game          close (ortho 8, the default) or the game's own zoom (ortho 24, crops upscaled x2)
## --frames-dir <dir>         also saves every 2nd frame (30 fps) of the three lanes side by side as frame_NNN.png (GIFs)
## --measure                  prints the stride match (the planted foot's sweep speed / the ground speed) per lane and speed
## No --shot: plays the clip in a loop.

const FeelScript := preload("res://scripts/art/lowpoly/anim_lab_feel.gd")

const DT := 1.0 / 60.0
const YAW := 45.0
const PITCH := -56.0
const CLOSE_PITCH := -32.0        ## the close-ups look a little lower than the game so the lean and the legs read
const LANE_NAMES: Array[String] = ["Today", "B grounded", "C actions"]
const LANE_COLORS: Array[Color] = [Color(0.75, 0.75, 0.78), Color(0.45, 0.8, 0.55), Color(0.4, 0.8, 1.0)]

## clip -> [duration s, the strip's 8 sample times]
const CLIPS := {
	"startstop": [2.1, [0.25, 0.35, 0.45, 0.75, 1.3, 1.38, 1.5, 1.75]],
	"strafe": [2.2, [0.15, 0.3, 0.5, 0.8, 1.15, 1.35, 1.6, 1.9]],
	"turn": [2.0, [0.5, 0.9, 0.95, 1.0, 1.08, 1.2, 1.6, 1.75]],
	"cast": [2.0, [0.15, 0.4, 0.7, 1.0, 1.12, 1.18, 1.35, 1.7]],
	"hit": [2.0, [0.28, 0.32, 0.36, 0.45, 0.65, 1.05, 1.2, 1.5]],
	"attack": [1.6, [0.28, 0.32, 0.35, 0.38, 0.45, 0.6, 0.92, 0.98]],
}
## Hand-picked so the sole points sit at the bottom of each model's boot (model-local, under the leg part).
const SOLE := {"wick": Vector3(0, -0.90, -0.03), "gasket": Vector3(0, -0.46, -0.06), "rebar": Vector3(0, -1.12, -0.08)}

var hero_kind := "wick"
var clip := "startstop"
var zoom := "close"
var frames_dir := ""
var heroes: Array[Hero] = []
var feels: Array = []              ## [null, feel B, feel C]
var _origin := Vector3.ZERO
var _right := Vector3.ZERO
var _up := Vector3.ZERO           ## on the ground, away from the camera (screen up)
var _gap := 3.2


func _ready() -> void:
	hero_kind = arg(args, "--hero", "wick")
	clip = arg(args, "--clip", "startstop")
	zoom = arg(args, "--zoom", "close")
	frames_dir = arg(args, "--frames-dir")
	build_arena(30, 24, 27, 1)
	var yaw := deg_to_rad(YAW)
	_right = Vector3(cos(yaw), 0, -sin(yaw))
	_up = -Vector3(sin(yaw), 0, cos(yaw))
	_gap = {"wick": 3.0, "gasket": 3.0, "rebar": 3.8}[hero_kind]
	if zoom == "game":
		_gap *= 0.85
	_origin = -_right * 6.0 + _up * 1.0 if clip == "startstop" or clip == "turn" else Vector3.ZERO
	for i in 3:
		var model := _make_model()
		var h := HeroFactory.spawn_hero(Vector2i.ZERO, LANE_NAMES[i], LANE_COLORS[i], "sword", model, hero_kind)
		if clip == "cast":
			h.spell_slots = ["heal"]   # the held component shows in the hand, as in the game (only where it matters)
		h.global_position = _lane_pos(i)
		h.snap_to_ground()
		heroes.append(h)
		if i == 0:
			feels.append(null)
		else:
			var feel: Node3D = FeelScript.new()
			var vis: Node3D = h.get("_visual")
			vis.add_child(feel)
			model.reparent(feel, false)
			feel.call("setup", h, model, hero_kind, i)
			feels.append(feel)
	make_camera()
	_aim_camera()
	if args.has("--measure"):
		_measure()
	elif shot_path != "":
		_record()
	else:
		_loop()


func _make_model() -> LowPolyModel:
	match hero_kind:
		"gasket":
			return GasketModel.new()
		"rebar":
			return RebarModel.new()
	return WickModel.new()


func _lane_pos(i: int) -> Vector3:
	return _origin + _right * (i - 1) * _gap


func _aim_camera() -> void:
	var mid := heroes[1].global_position if heroes.size() > 1 else _origin
	var h := 1.2 if hero_kind != "rebar" else 1.6
	aim(YAW, PITCH if zoom == "game" else CLOSE_PITCH, 24.0 if zoom == "game" else (9.5 if hero_kind == "rebar" else 8.0), mid + Vector3(0, h, 0))


# --- The clips -----------------------------------------------------------------------------------------------------

## [move dir (world, X/Z, length <= 1), aim dir] at time t.
func _input_at(t: float) -> Array:
	var down := -_up
	match clip:
		"startstop":
			return [_right if t >= 0.3 and t < 1.3 else Vector3.ZERO, _right]
		"strafe":
			var mv := Vector3.ZERO
			if t >= 0.2 and t < 1.0:
				mv = _right
			elif t >= 1.0 and t < 1.8:
				mv = _up
			return [mv, down]
		"turn":
			if t < 0.2:
				return [Vector3.ZERO, _right]
			if t < 0.9:
				return [_right, _right]
			if t < 1.6:
				return [-_right, -_right]
			return [Vector3.ZERO, -_right]
		"attack":
			return [Vector3.ZERO, _right]
	return [Vector3.ZERO, (down - _right * 0.6).normalized()]


## The clip's events on frame f (every lane gets the same one; lane 3 also gets the feel layer's version).
func _events(f: int) -> void:
	var t := f * DT
	var at := func(s: float) -> bool: return f == int(roundf(s * 60.0))
	match clip:
		"cast":
			if at.call(0.2):
				_feel_call("on_speech")
			if at.call(0.55):
				_feel_call("on_armed")
			if at.call(1.1):
				for i in 3:
					if i < 2:
						heroes[i].call("_cast_pose")
					else:
						feels[i].call("on_cast")
		"hit":
			if at.call(0.3):
				for i in 3:
					heroes[i].apply_damage(12.0, null)
					if feels[i] != null:
						feels[i].call("on_hit", -_right, 12.0)
			if at.call(1.0):
				for h in heroes:
					h.shove(-_right, 2.2, null)
		"attack":
			if at.call(0.3) or at.call(0.9):
				for i in 3:
					if i < 2:
						heroes[i].melee(_right)
					else:
						var h := heroes[i]
						Fx.slash_arc(h.global_position, _right, h.melee_reach, h.melee_arc, h.hero_color.lightened(0.5))
						feels[i].call("on_attack", true)
	t = t


func _feel_call(m: String) -> void:
	for fe in feels:
		if fe != null:
			fe.call(m)


func _step(f: int) -> void:
	var inp := _input_at(f * DT)
	var mv: Vector3 = inp[0]
	var aim_dir: Vector3 = inp[1]
	for h in heroes:
		if h.is_helpless():
			h.climbing = false
		elif mv.length() > 0.01:
			h.move(mv, DT)
		h.face_point(h.global_position + aim_dir * 5.0)
	_events(f)
	for fe in feels:
		if fe != null:
			fe.call("step", DT)
	_aim_camera()


func _loop() -> void:
	var dur: float = CLIPS[clip][0]
	while true:
		for i in 3:
			heroes[i].global_position = _lane_pos(i)
			heroes[i].heal(heroes[i].max_hp)
		for f in int(dur * 60.0) + 30:
			_step(f)
			await get_tree().process_frame


# --- Recording ------------------------------------------------------------------------------------------------------

func _crop_size(img_h: int) -> Vector2i:
	var unit := img_h / camera.size
	var w := {"wick": 2.6, "gasket": 2.6, "rebar": 3.4}[hero_kind] as float
	var hh := {"wick": 3.6, "gasket": 3.6, "rebar": 4.6}[hero_kind] as float
	return Vector2i(int(w * unit), int(hh * unit))


func _crop(img: Image, i: int) -> Image:
	var size := _crop_size(img.get_height())
	var top := heroes[i].global_position + Vector3(0, {"wick": 1.3, "gasket": 1.25, "rebar": 1.8}[hero_kind] as float, 0)
	var vp := get_viewport().get_visible_rect().size
	var c := camera.unproject_position(top) * Vector2(img.get_width() / vp.x, img.get_height() / vp.y)
	var r := Rect2i(int(c.x) - size.x / 2, int(c.y) - size.y / 2, size.x, size.y)
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var out := img.get_region(r)
	if out.get_size() != size:
		var pad := Image.create(size.x, size.y, false, out.get_format())
		pad.blit_rect(out, Rect2i(Vector2i.ZERO, out.get_size()), Vector2i.ZERO)
		out = pad
	if zoom == "game":
		out.resize(size.x * 2, size.y * 2, Image.INTERPOLATE_NEAREST)
	return out


func _record() -> void:
	await wait_frames(10)
	var dur: float = CLIPS[clip][0]
	var times: Array = CLIPS[clip][1]
	var want := {}
	for s: float in times:
		want[int(roundf(s * 60.0))] = true
	var cells: Array = []   # [frame][lane] -> Image
	var gif_n := 0
	for f in int(dur * 60.0):
		_step(f)
		await RenderingServer.frame_post_draw
		var need_gif := frames_dir != "" and f % 2 == 0
		if not want.has(f) and not need_gif:
			continue
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var lanes: Array[Image] = []
		for i in 3:
			lanes.append(_crop(img, i))
		if want.has(f):
			cells.append(lanes)
		if need_gif:
			_save_gif_frame(lanes, gif_n)
			gif_n += 1
	_save_strip(cells)
	finish()


## The strip: one row per lane, one column per sample time, each cell shrunk to fit.
func _save_strip(cells: Array) -> void:
	var k := 0.62 if zoom == "close" else 0.5
	var cw := int(cells[0][0].get_width() * k)
	var ch := int(cells[0][0].get_height() * k)
	var sheet := Image.create(cw * cells.size(), ch * 3, false, Image.FORMAT_RGB8)
	for col in cells.size():
		for row in 3:
			var im: Image = (cells[col][row] as Image).duplicate()
			im.resize(cw, ch, Image.INTERPOLATE_LANCZOS if zoom == "close" else Image.INTERPOLATE_NEAREST)
			sheet.blit_rect(im, Rect2i(0, 0, cw, ch), Vector2i(col * cw, row * ch))
	# thin dark separators
	for col in range(1, cells.size()):
		sheet.fill_rect(Rect2i(col * cw - 1, 0, 2, ch * 3), Color(0.05, 0.05, 0.07))
	for row in range(1, 3):
		sheet.fill_rect(Rect2i(0, row * ch - 1, cw * cells.size(), 2), Color(0.05, 0.05, 0.07))
	print("strip ", shot_path, " ", sheet.save_png(shot_path), " ", sheet.get_size())


func _save_gif_frame(lanes: Array[Image], n: int) -> void:
	var s := 0.5 if zoom == "close" else 0.5
	var cw := int(lanes[0].get_width() * s)
	var ch := int(lanes[0].get_height() * s)
	var im := Image.create(cw * 3, ch, false, Image.FORMAT_RGB8)
	for i in 3:
		var c := lanes[i].duplicate() as Image
		c.resize(cw, ch, Image.INTERPOLATE_BILINEAR)
		im.blit_rect(c, Rect2i(0, 0, cw, ch), Vector2i(i * cw, 0))
	im.save_png("%s/frame_%03d.png" % [frames_dir, n])


# --- Measuring the stride match --------------------------------------------------------------------------------------

## For each speed, walk the lanes straight ahead (aim = walk) for 1.5 s and track each lane's feet: the planted foot's
## backward sweep relative to the body at its fastest, divided by the ground speed. 1.0 = the feet stay put at mid-stance;
## below 1 the feet skate forward (ice skating), above 1 they paddle backward. Also the side-step case (aim 90 deg off).
func _measure() -> void:
	await wait_frames(5)
	var model_of := func(h: Hero) -> LowPolyModel:
		return h.visual_override as LowPolyModel
	for case: Array in [["draw (bow drawn) 2.25", 2.25, 0.0], ["wading 3.4", 3.375, 0.0], ["walk 4.5", 4.5, 0.0],
			["coffee 7.2", 7.2, 0.0], ["strafe 4.5 (aim 90 deg off)", 4.5, 90.0], ["backpedal 4.5", 4.5, 180.0]]:
		var spd: float = case[1]
		var off := deg_to_rad(float(case[2]))
		for i in 3:
			heroes[i].global_position = _lane_pos(i)
			heroes[i].move_speed = spd
		var prev := {}
		var best := [0.0, 0.0, 0.0]
		var along := [0.0, 0.0, 0.0]
		for f in 90:
			for h in heroes:
				h.move(_right, DT)
				h.face_point(h.global_position + _right.rotated(Vector3.UP, off) * 5.0)
			for fe in feels:
				if fe != null:
					fe.call("step", DT)
			await get_tree().process_frame
			for i in 3:
				var m: LowPolyModel = model_of.call(heroes[i])
				for side in ["leg_l", "leg_r"]:
					var leg := m.parts[side] as Node3D
					var p := leg.global_transform * (SOLE[hero_kind] as Vector3)
					var key := "%d%s" % [i, side]
					if prev.has(key) and f > 30:
						var rel: Vector3 = (p - prev[key]) / DT - _right * spd
						rel.y = 0.0
						# the sweep that would plant the foot points backward along the walk
						var back := -rel.dot(_right)
						if back > best[i]:
							best[i] = back
							along[i] = rel.length()
					prev[key] = p
		print("measure %-28s today %.2f   B %.2f   C %.2f   (|sweep| %.2f / %.2f / %.2f)" % [case[0],
				best[0] / spd, best[1] / spd, best[2] / spd, along[0] / spd, along[1] / spd, along[2] / spd])
	finish()
