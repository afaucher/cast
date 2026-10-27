extends LabBase
## "Cast armed" look-dev lab (docs/design/cast-armed-fx.md). LOOK-DEV ONLY: nothing here is wired into the game.
## Five copies of one real hero (a real Hero with its faceted model, moved by Hero.move, casting a real fireball through
## Hero.try_cast) stand side by side, each with one style of the armed tell (CastArmedFx), and play the same script of
## voice events: the trigger word heard, the spell word recognised, the cast landing (or the window running out).
##
##   lane A "rune"       a rune circle on the floor under the hero, drawn in from the aim notch, trailing the feet
##   lane B "hand"       a glow at the casting hand (+ a small light pooling on the floor)
##   lane C "rune+hand"  A + B (dimmer rune, no light)
##   lane D "glyph"      A, with a neutral hub that rewrites into the spell's glyph on recognition
##   lane E "sigil"      a small rune disc above the head
##
##   godot --path . --fixed-fps 60 --resolution 1920x1080 -- --scene res://scenes/cast_fx_lab.tscn --clip stand
##         --zoom game --out <abs dir> [--hero wick|gasket|rebar] [--frames]
##   godot --path . --fixed-fps 60 --resolution 1920x1080 -- --scene res://scenes/cast_fx_lab.tscn --clip lineup
##         --zoom game --out <abs dir>
##
## --clip stand|walk|cancel|expire|lineup   (default stand)
##     stand   trigger at 0.40 s, the spell word recognised at 1.10, the cast lands at 1.30 (online: NetCasts.LEAD later)
##     walk    the same while walking a dog-leg (right, diagonal toward the camera, right, stop)
##     cancel  trigger at 0.30, nothing else; the window (1.8 s) runs out at 2.10: a fizzle (SpellBook.fizzle's puff too)
##     expire  the same, but a quiet expiry (a "cast" buried in chatter that never found a spell word)
##     lineup  ten heroes with lane D's rune, one per spell, recognised (the spell colours and glyphs side by side)
## --zoom game|close    the game's own zoom (ortho 24, pitch -56) or a close-up (ortho 9.5, same pitch)
## --out <dir>          saves cells: <clip>_<zoom>_<lane>_<col>.png at the clip's strip times (8 columns), and with
##                      --frames every 2nd frame (30 fps) per lane as frames/<clip>_<zoom>_<lane>_<NNN>.png (GIFs)
## --hero               the hero (default wick)
## No --out: plays the clip in a loop.

const DT := 1.0 / 60.0
const YAW := 45.0
const PITCH := -56.0
const STYLES: Array[String] = ["rune", "hand", "rune_hand", "glyph", "sigil"]
const NAMES: Array[String] = ["A rune", "B hand", "C rune+hand", "D glyph", "E sigil"]
const LINEUP: Array[String] = ["fireball", "heal", "corn", "armor", "tentacles", "teeth", "vines", "damp", "coffee", "chicken", "revive"]
const SPELL := "fireball"
const AIM_DIST := 3.5

## clip -> {dur, times (the strip's 8 columns), arm, recog, land, cancel, fizzle}
const CLIPS := {
	"stand": {"dur": 2.0, "times": [0.36, 0.47, 0.62, 1.0, 1.22, 1.32, 1.38, 1.55], "arm": 0.40, "recog": 1.10, "land": 1.30},
	"walk": {"dur": 2.4, "times": [0.45, 0.62, 0.9, 1.1, 1.36, 1.47, 1.53, 1.85], "arm": 0.35, "recog": 1.25, "land": 1.45},
	"cancel": {"dur": 2.75, "times": [0.42, 0.75, 1.1, 1.5, 1.9, 2.15, 2.3, 2.5], "arm": 0.30, "cancel": 2.10, "fizzle": true},
	"expire": {"dur": 2.6, "times": [0.42, 0.75, 1.1, 1.5, 1.9, 2.15, 2.25, 2.4], "arm": 0.30, "cancel": 2.10, "fizzle": false},
	"lineup": {"dur": 0.75, "times": [0.7], "arm": 0.05, "recog": 0.45},
}

var hero_kind := "wick"
var clip := "stand"
var zoom := "game"
var out_dir := ""
var save_frames := false
var heroes: Array[Hero] = []
var fxs: Array[CastArmedFx] = []
var _hand := []                    ## B / C: the lab-only wand raise while armed (Wick's "cast" arm kick), per lane
var _origin := Vector3.ZERO
var _right := Vector3.ZERO
var _up := Vector3.ZERO           ## on the ground, away from the camera (screen up)
var _gap := 3.0
var _spec: Dictionary
var _frame := 0


func _ready() -> void:
	hero_kind = arg(args, "--hero", "wick")
	clip = arg(args, "--clip", "stand")
	zoom = arg(args, "--zoom", "game")
	out_dir = arg(args, "--out")
	save_frames = args.has("--frames")
	_spec = CLIPS[clip]
	build_arena(30, 24, 27, 1)
	var yaw := deg_to_rad(YAW)
	_right = Vector3(cos(yaw), 0, -sin(yaw))
	_up = -Vector3(sin(yaw), 0, cos(yaw))
	_gap = {"wick": 3.0, "gasket": 3.3, "rebar": 3.6}[hero_kind]
	_origin = -_right * 4.0 if clip == "walk" else Vector3.ZERO
	make_camera()
	var n := LINEUP.size() if clip == "lineup" else STYLES.size()
	for i in n:
		var model := _make_model()
		var label := LINEUP[i].capitalize() if clip == "lineup" else NAMES[i]
		var h := HeroFactory.spawn_hero(Vector2i.ZERO, label, Color(0.75, 0.78, 0.85), "sword", model, hero_kind)
		h.spell_slots = [SPELL]
		h.set_charges(SPELL, 3)
		h.global_position = _lane_pos(i)
		h.snap_to_ground()
		heroes.append(h)
		var fx := CastArmedFx.new("glyph" if clip == "lineup" else STYLES[i])
		add_child(fx)
		fx.setup(h, model, hero_kind, camera)
		fxs.append(fx)
		_hand.append(0.0)
	_aim_camera()
	if out_dir != "":
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
	if clip == "lineup":
		var col := i % 5
		var row := i / 5
		return _origin + _right * (col - 2) * _gap * 0.95 + _up * (0.5 - row) * 3.4
	return _origin + _right * (i - 2) * _gap


func _aim_camera() -> void:
	var mid := heroes[2].global_position if clip != "lineup" else _origin
	var close := {"wick": 9.5, "gasket": 10.5, "rebar": 11.5}[hero_kind] as float
	var size := 24.0 if zoom == "game" else (12.5 if clip == "lineup" else close)
	aim(YAW, PITCH, size, mid + Vector3(0, 0.6, 0) - _up * 0.6)


# --- The script ----------------------------------------------------------------------------------------------------

func _move_at(t: float) -> Vector3:
	if clip != "walk":
		return Vector3.ZERO
	if t >= 0.2 and t < 1.0:
		return _right
	if t >= 1.0 and t < 1.5:
		return (_right - _up).normalized()
	if t >= 1.5 and t < 2.05:
		return _right
	return Vector3.ZERO


func _aim_of(i: int) -> Vector3:
	return heroes[i].global_position - _up * AIM_DIST


func _step(f: int) -> void:
	var t := f * DT
	var at := func(key: String) -> bool: return _spec.has(key) and f == int(roundf(float(_spec[key]) * 60.0))
	var mv := _move_at(t)
	for i in heroes.size():
		var h := heroes[i]
		if mv.length() > 0.01:
			h.move(mv, DT)
		h.face_point(_aim_of(i))
	for i in heroes.size():
		var fx := fxs[i]
		var h := heroes[i]
		if at.call("arm"):
			fx.arm()
		if at.call("recog"):
			fx.recognise(LINEUP[i] if clip == "lineup" else SPELL)
		if at.call("land"):
			var target := SpellBook.resolve_target(h, _aim_of(i))
			fx.release(target)
			h.try_cast(SPELL, 1.0, _aim_of(i))
		if at.call("cancel"):
			fx.cancel(bool(_spec.get("fizzle", true)))
			if bool(_spec.get("fizzle", true)):
				SpellBook.fizzle(h)
		_pose_hand(i, fx)
		fx.step(DT, _aim_of(i))
	_aim_camera()


## B and C mock the hand in the lab only: Wick draws the copper wand and holds it half raised while armed (the model's own
## "cast" arm kick, as the animation lab's feel layer does). The release is the hero's real cast pose (Hero.try_cast).
func _pose_hand(i: int, fx: CastArmedFx) -> void:
	if not fx.uses_hand() or hero_kind != "wick":
		return
	var model := heroes[i].visual_override as LowPolyModel
	var want := 0.0
	if fx.phase == CastArmedFx.Phase.ARMING or fx.phase == CastArmedFx.Phase.ARMED:
		want = 0.62
	elif fx.phase == CastArmedFx.Phase.RELEASE:
		return   # the cast pose's own tween drives the arm now
	var v: float = _hand[i]
	v = move_toward(v, want, DT * (6.0 if want > v else 3.0))
	_hand[i] = v
	model._arm_kick["cast"] = v + sin(_frame * DT * 47.0) * 0.03 * v   # a small tremble while it waits


func _loop() -> void:
	var dur: float = _spec["dur"]
	while true:
		for i in heroes.size():
			heroes[i].global_position = _lane_pos(i)
			heroes[i].set_charges(SPELL, 3)
		for f in int(dur * 60.0) + 40:
			_frame = f
			_step(f)
			await get_tree().process_frame
		await wait_frames(30)


# --- Recording ------------------------------------------------------------------------------------------------------

## A lane's crop in world units on screen: the lane's width, from above the head (the sigil, the name) to below the rune.
func _crop_rect(img: Image, i: int) -> Rect2i:
	var unit := img.get_height() / camera.size
	var w := _gap * (0.95 if clip == "lineup" else 1.0)
	var above := {"wick": 2.75, "gasket": 2.5, "rebar": 3.45}[hero_kind] as float
	var below := 1.35 if clip == "lineup" else 1.75
	var vp := get_viewport().get_visible_rect().size
	var c := camera.unproject_position(heroes[i].global_position) * Vector2(img.get_width() / vp.x, img.get_height() / vp.y)
	return Rect2i(int(c.x - w * unit * 0.5), int(c.y - above * unit), int(w * unit), int((above + below) * unit))


func _crop(img: Image, i: int) -> Image:
	var r := _crop_rect(img, i)
	var cut := r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var out := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGB8)
	out.fill(DungeonLook.BACKGROUND)
	out.blit_rect(img.get_region(cut), Rect2i(Vector2i.ZERO, cut.size), cut.position - r.position)
	return out


func _record() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	if save_frames:
		DirAccess.make_dir_recursive_absolute(out_dir + "/frames")
	await wait_frames(10)
	var dur: float = _spec["dur"]
	var times: Array = _spec["times"]
	var want := {}
	for k in times.size():
		want[int(roundf(float(times[k]) * 60.0))] = k
	var gif_n := 0
	var tag := "%s_%s%s" % [clip, zoom, "" if hero_kind == "wick" else "_" + hero_kind]
	for f in int(dur * 60.0) + 1:
		_frame = f
		_step(f)
		await RenderingServer.frame_post_draw
		var need_gif := save_frames and f % 2 == 0
		if not want.has(f) and not need_gif:
			continue
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		if clip == "lineup" and want.has(f):
			img.save_png("%s/%s_full.png" % [out_dir, tag])
		for i in heroes.size():
			var cell := _crop(img, i)
			if want.has(f):
				cell.save_png("%s/%s_%d_%d.png" % [out_dir, tag, i, int(want[f])])
			if need_gif:
				cell.save_png("%s/frames/%s_%d_%03d.png" % [out_dir, tag, i, gif_n])
		if need_gif:
			gif_n += 1
	print("cells ", tag, " done (", gif_n, " gif frames)")
	finish()
