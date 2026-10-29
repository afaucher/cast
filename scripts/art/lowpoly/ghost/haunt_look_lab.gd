extends "res://scripts/art/lowpoly/ghost/ghost_look_lab.gd"
## Haunt look lab (docs/design/haunt-look.md): the possessed hosts dormant and possessed (HauntPiece: the suit of armour,
## the crypt skeleton) and the hero in ghost form (GhostForm), at the game camera (yaw 45, pitch -56, size 24, 1:1 pixels)
## in the ghost look lab's room (its bright downlight pool and its dark corner), with Wick and Rebar standing by. The
## ghosts wear the rim look the user picked, soft, pale blue. LOOK-DEV ONLY: nothing here is used by the game.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/haunt_look_lab.tscn --shot <abs dir>/armour.png
##
## PNGs, next to --shot (docs/design/haunt_look/):
##   armour.png          the armour dormant / guard / lurch: bright room and dark corner at 1:1, then the same at 2x
##   skeleton.png        the skeleton slumped / risen: the same columns
##   ghost_hero.png      Wick and Rebar off / glass / spirit, a possessed skeleton on their left and a wisp on their right,
##                       bright room then dark corner, 1:1
##   ghost_hero_2x.png   the same at 2x
##   lineup.png          everything in a row at 1:1 for scale: Wick, Rebar, a grunt, the armour's three stances, the
##                       skeleton's three, Wick in glass and in spirit
##   close_armour.png, close_skeleton.png, close_hero.png   close-ups at the game's angle (size 7)

const CLOSE_SIZE := 7.0
const CLOSE_CROP := Vector2i(1680, 640)   ## the middle of a close-up's frame
const ARMOUR_ROWS: Array[String] = ["armour_dormant", "armour_guard", "armour_lurch"]
const SKELETON_ROWS: Array[String] = ["skeleton_slumped", "skeleton_risen"]
const NICHE_YAW := HauntPiece.FACING
const HEROES: Array[String] = ["wick", "rebar"]


func _run() -> void:
	await wait_frames(10)
	var dir := shot_path.get_base_dir()
	GhostLook.reset()
	GhostLook.look = "rim"
	GhostLook.clock = CLOCK
	GhostForm.clock = CLOCK
	if only_view == "turn":
		await _turn(shot_path)
		finish()
		return
	var both := [["1:1 game pixels", [LIGHT_NAMES["bright"], LIGHT_NAMES["dark"]]], ["2x", [LIGHT_NAMES["bright"], LIGHT_NAMES["dark"]]]]
	# the armour and the skeleton: a row per pose; bright, dark at 1:1 then the same doubled
	for test: Array in [["armour", ARMOUR_ROWS, "Suit of armour: dormant (a priced prop) and two possessed stances (rim, soft, pale blue)"],
			["skeleton", SKELETON_ROWS, "Crypt skeleton: dormant slumped, risen (rim, soft, pale blue)"]]:
		var rows: Array = []
		for kind: String in test[1]:
			var row: Array[Image] = []
			for light in LIGHTS:
				row.append(await _piece_cell(kind, light))
			row.append(_doubled(row[0]))
			row.append(_doubled(row[1]))
			rows.append(row)
		await _sheet("%s/%s.png" % [dir, test[0]], "%s  -  docs/design/haunt-look.md" % test[2], _names(test[1]), both, rows, CROP.x)
	# the hero in ghost form: a row per hero, the treatments in the bright room then the dark corner
	var hero_rows: Array = []
	var hero_rows_2x: Array = []
	for which: String in HEROES:
		var row: Array[Image] = []
		var row2: Array[Image] = []
		for light in LIGHTS:
			for t: String in GhostForm.TREATMENTS:
				var img := await _hero_cell(which, t, light)
				row.append(img)
				row2.append(_doubled(img))
		hero_rows.append(row)
		hero_rows_2x.append(row2)
	var blocks := [[LIGHT_NAMES["bright"], GhostForm.TREATMENTS], [LIGHT_NAMES["dark"], GhostForm.TREATMENTS]]
	await _sheet("%s/ghost_hero.png" % dir, "Ghost form: off / glass / spirit, a possessed skeleton (left) and a wisp (right) for contrast, 1:1",
			["Wick", "Rebar"], blocks, hero_rows, 294)
	await _sheet("%s/ghost_hero_2x.png" % dir, "Ghost form at 2x (the middle of each cell)", ["Wick", "Rebar"], blocks, hero_rows_2x, 294)
	await _lineup("%s/lineup.png" % dir)
	await _close("%s/close_armour.png" % dir, ARMOUR_ROWS, [], 2.7)
	await _close("%s/close_skeleton.png" % dir, SKELETON_ROWS, [], 3.4)
	# the possessed hosts against the free ghost they should match (the user, 2026-10-29: "show me against the wisp again")
	var was := HauntPiece.wisps
	for w in HauntPiece.WISPS.size():
		HauntPiece.wisps = HauntPiece.WISPS[w]
		await _close("%s/close_wisps_%d.png" % [dir, w], ["wisp", "armour_guard", "skeleton_risen", "wisp"], [], 2.6, 120)   # (2 s: the puffs fill in)
	HauntPiece.wisps = was
	await _close("%s/close_vs_wisp.png" % dir, ["wisp", "armour_guard", "skeleton_risen", "wisp"], [], 2.6)
	for light: String in ["bright", "dark"]:
		_clear()
		var at: Vector3 = spots[light]
		var items: Array[String] = ["wisp", "armour_guard", "skeleton_risen"]
		for i in items.size():
			_put(items[i], at + RIGHT * 1.9 * (float(i) - 1.0))
		save_shot(await _crop_at(at + Vector3(0, 0.9, 0)), "%s/vs_wisp_%s.png" % [dir, light])
	await _close("%s/close_hero.png" % dir, [], ["wick:off", "wick:glass", "wick:spirit", "rebar:off", "rebar:glass", "rebar:spirit"], 1.8)
	GhostLook.reset()
	GhostForm.clock = -1.0
	finish()


static func _names(kinds: Array) -> Array:
	return kinds.map(func(k: String) -> String: return k.replace("_", "\n"))


## The middle half of a CROP image, doubled (nearest: the game's pixels, larger), back at CROP size.
static func _doubled(img: Image) -> Image:
	var out := img.get_region(Rect2i(CROP.x / 4, CROP.y / 4, CROP.x / 2, CROP.y / 2))
	out.resize(CROP.x, CROP.y, Image.INTERPOLATE_NEAREST)
	return out


## A piece's yaw: a niche straight at the camera, anything else the gym's three-quarter turn.
static func yaw_of(kind: String) -> float:
	return NICHE_YAW if kind.begins_with("skeleton") else GymSpawns.GHOST_YAW


## Stage HauntPiece `kind` at `at` with Wick on its left and Rebar on its right (further out round a niche).
func stage_piece(kind: String, at: Vector3) -> HauntPiece:
	_clear()
	var p := HauntPiece.make(kind)
	holder.add_child(p)
	p.position = at
	p.rotation_degrees.y = yaw_of(kind)
	_still(p.model)
	var out := 1.0 if kind.begins_with("skeleton") else 0.0
	_hero("wick", at - RIGHT * (1.55 + out) + TOWARD * 0.35, TOWARD + RIGHT * 0.6)
	_hero("rebar", at + RIGHT * (1.6 + out) + TOWARD * 0.2, TOWARD - RIGHT * 0.6)
	return p


## Freeze a model's idle at the lab's moment.
static func _still(m: LowPolyModel) -> void:
	if m != null and m.idle_enabled:
		m.idle_enabled = false
		m.apply_idle(0.6)


## Stage hero `which` in ghost form `t` at `at`, a possessed skeleton (GhostBody, rim) on its left and a wisp on its right.
func stage_hero(which: String, t: String, at: Vector3) -> LowPolyModel:
	_clear()
	var m: LowPolyModel = RebarModel.new() if which == "rebar" else WickModel.new()
	holder.add_child(m)
	m.idle_enabled = false
	m.apply_idle(0.6)
	m.position = at
	var face := TOWARD + RIGHT * 0.3
	m.rotation_degrees = Vector3(0, rad_to_deg(atan2(-face.x, -face.z)), 0)
	GhostForm.apply(m, t)
	var sk := GhostBody.make("skeleton")
	sk.drift = false
	holder.add_child(sk)
	sk.position = at - RIGHT * 1.7 + TOWARD * 0.2
	sk.rotation_degrees.y = GymSpawns.GHOST_YAW
	_still(sk.model)
	var wi := GhostBody.make("wisp")
	wi.drift = false
	holder.add_child(wi)
	var dp := wi.drift_point(WISP_T)
	wi.position = at + RIGHT * 1.7 - Vector3(dp.x, 0.0, dp.z)
	wi.pose_wisp(WISP_T)
	return m


func _piece_cell(kind: String, light: String) -> Image:
	var at: Vector3 = spots[light]
	stage_piece(kind, at)
	return await _crop_at(at + Vector3(0, 0.9, 0))


func _hero_cell(which: String, t: String, light: String) -> Image:
	var at: Vector3 = spots[light]
	stage_hero(which, t, at)
	return await _crop_at(at + Vector3(0, 0.9, 0))


## The game camera on `tgt`, the middle CROP of the frame.
func _crop_at(tgt: Vector3) -> Image:
	aim(GAME_YAW, GAME_PITCH, GAME_SIZE, tgt)
	var img := await grab()
	img.convert(Image.FORMAT_RGBA8)
	return img.get_region(Rect2i(img.get_width() / 2 - CROP.x / 2, img.get_height() / 2 - CROP.y / 2, CROP.x, CROP.y))


## Everything in a row across the screen in the bright room, at the game camera and 1:1.
func _lineup(path: String) -> void:
	_clear()
	var at: Vector3 = spots["bright"]
	var items: Array[String] = ["wick", "rebar", "grunt", "armour_dormant", "armour_guard", "armour_lurch",
		"skeleton_slumped", "skeleton_risen", "wick:glass", "wick:spirit"]
	var step := 1.75
	var xs: Array[float] = []
	var x := 0.0
	for it in items:
		var wide := it.begins_with("skeleton") or it == "armour_lurch"
		x += step * (0.5 if wide else 0.0)
		xs.append(x)
		x += step * (1.5 if wide else 1.0)
	var mid := (xs[0] + xs[xs.size() - 1]) * 0.5
	for i in items.size():
		var it := items[i]
		_put(it, at + RIGHT * (xs[i] - mid) + TOWARD * (0.0 if it.begins_with("skeleton") or it.begins_with("armour") else 0.6))
	aim(GAME_YAW, GAME_PITCH, GAME_SIZE, at + Vector3(0, 0.9, 0))
	var img := await grab()
	img.convert(Image.FORMAT_RGBA8)
	var h := 330
	save_shot(img.get_region(Rect2i(0, img.get_height() / 2 - h / 2 - 20, img.get_width(), h)), path)


## Put one lineup or close-up item down: a hero ("wick", "rebar", "wick:glass"), "grunt" or a HauntPiece kind.
func _put(it: String, p: Vector3) -> void:
	if it == "grunt":
		var g := GruntModel.new()
		holder.add_child(g)
		g.position = p
		g.rotation_degrees.y = GymSpawns.GHOST_YAW
		_still(g)
	elif it.begins_with("wick") or it.begins_with("rebar"):
		var which := it.get_slice(":", 0)
		var m: LowPolyModel = RebarModel.new() if which == "rebar" else WickModel.new()
		holder.add_child(m)
		m.idle_enabled = false
		m.apply_idle(0.6)
		m.position = p
		var face := TOWARD + RIGHT * 0.3
		m.rotation_degrees = Vector3(0, rad_to_deg(atan2(-face.x, -face.z)), 0)
		if it.contains(":"):
			GhostForm.apply(m, it.get_slice(":", 1))
	elif it == "wisp":
		var wi := GhostBody.make("wisp")
		wi.drift = false
		holder.add_child(wi)
		var dp := wi.drift_point(WISP_T)
		wi.position = p - Vector3(dp.x, 0.0, dp.z)
		wi.pose_wisp(WISP_T)
	else:
		var hp := HauntPiece.make(it)
		holder.add_child(hp)
		hp.position = p
		hp.rotation_degrees.y = yaw_of(it)
		_still(hp.model)


## `--view turn` (a check while modelling, not committed as a sheet): every piece and ghost-form hero from the front, the
## side and the back, at eye level, in a row each.
func _turn(path: String) -> void:
	var at := Vector3(70.0, 0.0, 70.0)   # (out past the room: nothing in the way)
	var rows: Array = [["armour_dormant", "armour_guard", "armour_lurch"], ["skeleton_slumped", "skeleton_risen"]]
	for r in rows.size():
		_clear()
		for i in (rows[r] as Array).size():
			for k in 3:
				var hp := HauntPiece.make(str(rows[r][i]))
				holder.add_child(hp)
				hp.position = at + RIGHT * (float(i * 3 + k) - 4.0) * (3.0 if r == 1 else 2.2)
				hp.rotation_degrees.y = HauntPiece.FACING + 90.0 * k
				_still(hp.model)
		aim(GAME_YAW, -12.0, 15.0 if r == 0 else 18.0, at + Vector3(0, 1.0, 0))
		var img := await grab()
		save_shot(img, path.get_basename() + "_%d.png" % r)


## A close-up at the game's angle (size CLOSE_SIZE): `pieces` or `heroes` in a row `step` apart, in the bright room.
func _close(path: String, pieces: Array, heroes: Array, step: float, settle: int = 6) -> void:
	_clear()
	var at: Vector3 = spots["bright"]
	var items: Array = pieces + heroes
	for i in items.size():
		_put(str(items[i]), at + RIGHT * step * (float(i) - (items.size() - 1) * 0.5))
	aim(GAME_YAW, GAME_PITCH, CLOSE_SIZE, at + Vector3(0, 0.9, 0))
	var img := await grab(settle)
	img.convert(Image.FORMAT_RGBA8)
	save_shot(img.get_region(Rect2i(img.get_width() / 2 - CLOSE_CROP.x / 2, img.get_height() / 2 - CLOSE_CROP.y / 2 + 30, CLOSE_CROP.x, CLOSE_CROP.y)), path)
