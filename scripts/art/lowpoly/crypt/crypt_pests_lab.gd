extends "res://scripts/art/lowpoly/crypt/crypt_section_lab.gd"
## Crypt pests lab (docs/design/crypt-pests-look.md): the two proposed haunted-contract pests, the crypt rats (RatModel) and
## the ecto blobs (EctoBlobModel, its slick EctoplasmLook.trail), staged in the crypt section lab's vault set (its candle-lit
## burial chamber and its unlit ossuary gallery, CryptLook's light), so they are judged in context and in the crypt's dim
## light. LOOK-DEV ONLY: posed models, nothing here is used by the game.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/crypt_pests_lab.tscn --shot <abs dir>/rats.png [--set rats|packs|blobs|close|lineup]
##
## PNGs, next to --shot (docs/design/crypt_pests_look/), every game view at the game camera (yaw 45, pitch -56, size 24, 1:1):
##   rats.png, rats_2x.png    a row per rat: running, reared up (the tell), biting (Wick beside it in the chamber), running in
##                            the dark gallery; _2x the middle of each cell doubled (nearest)
##   rat_packs.png            a pack of six per rat, round Wick and Rebar, in the chamber and in the gallery
##   blobs.png, blobs_2x.png  a row per blob: resting, crawling on its slick, gathered up (the tell), lunging, crawling in the dark
##   rats_close.png, blobs_close.png   closer (the game's angles, size 5 / 5.5) in the lit display room: the models' detail
##   lineup.png, lineup_2x.png  Wick, Rebar, the grunt, the swarmer imp, the mourner zombie, the three rats and the three blobs
##                            (in the display room)
## --set   one group only.

const CELL := Vector2i(340, 280)
const BLOB_CELL := Vector2i(330, 280)
const PACK_CELL := Vector2i(560, 420)
const CLOSE_CELL := Vector2i(400, 300)
const CLOSE_RAT := 5.0
const CLOSE_BLOB := 5.6
const FREEZE := 2.0                  ## every shader clock in the stills

var stage: Node3D                    ## this lab's own pieces, cleared per cell
var chamber := Vector3.ZERO          ## the candle-lit stage in the burial chamber
var gallery := Vector3.ZERO          ## the dark stage in the ossuary gallery
var shelf := Vector3.ZERO            ## the display room's front, for the close-ups and the lineup


func _ready() -> void:
	GhostLook.reset()
	NecroLook.reset()
	GhostLook.clock = FREEZE
	NecroLook.clock = FREEZE
	EctoplasmLook.clock = FREEZE
	EctoBlobModel.clock = FREEZE
	make_camera(260.0)
	build("vault")
	_setup_stage()
	if shot_path != "":
		_run_pests(arg(args, "--set", ""))


## The lab's stages (the chamber in front of the sarcophagi with a few candles of its own, the gallery, the display room's
## front) and the crew put away: Wick stands in each cell for scale, the rest only where a view asks.
func _setup_stage() -> void:
	var back := -Hex.dir_vector(5)
	chamber = (spots["bright"] as Vector3) - back * 2.2
	gallery = (spots["dark"] as Vector3) + TOWARD * 0.4
	shelf = Hex.to_world(DISPLAY) + TOWARD * 3.0
	for k: String in ["rebar", "grunt", "grunt2"]:
		(crew[k] as Node3D).visible = false
	_crypt("candles", chamber - RIGHT * 0.6 - TOWARD * 1.3, 0.0, {"count": 4, "radius": 0.25, "seed": 21, "light": 0.8})
	_crypt("candles", chamber + RIGHT * 2.4 - TOWARD * 0.9, 0.0, {"count": 3, "radius": 0.2, "seed": 22, "light": 0.6})
	_clear()


func _clear() -> void:
	if stage != null:
		holder.remove_child(stage)
		stage.free()
	stage = Node3D.new()
	stage.name = "PestStage"
	holder.add_child(stage)


static func face_yaw(f: Vector3) -> float:
	return atan2(-f.x, -f.z)


## A pest model at `pos` facing `f` (its front -Z), frozen in `pose` ("rest", "run", "windup", "swing", "crawl").
func _pest(kind: String, variant: String, pose: String, pos: Vector3, f: Vector3, t: float = 0.42) -> MonsterModel:
	var m: MonsterModel = RatModel.new(variant) if kind == "rat" else EctoBlobModel.new(variant)
	m.idle_enabled = false
	stage.add_child(m)
	m.position = pos
	m.rotation.y = face_yaw(f)
	match pose:
		"run":
			m.pose_preview("rest")
			m.apply_idle(t, RatModel.RUN_SPEED)
		"crawl":
			m.pose_preview("rest")
			m.apply_idle(t, EctoBlobModel.CRAWL_SPEED)
		"windup", "swing":
			m.pose_preview(pose, 1.0)
		_:
			m.pose_preview("rest")
			m.apply_idle(t, 0.0)
	return m


## The blob's slick: `length` behind `pos` (against facing `f`), its new end under the blob.
func _slick(pos: Vector3, f: Vector3, length: float, seed_value: int) -> Node3D:
	var pts: Array[Vector3] = []
	for i in 25:
		var u := float(i) / 24.0
		pts.append(Vector3(0.14 * sin(u * 6.0 + 0.7) * u, 0.0, (1.0 - u) * length))
	var tr := EctoplasmLook.trail("film", pts, 1.0, seed_value)
	stage.add_child(tr)
	tr.position = pos
	tr.rotation.y = face_yaw(f)
	return tr


func _wick(pos: Vector3, f: Vector3) -> void:
	var wick: Node3D = crew["wick"]
	wick.visible = true
	wick.position = pos
	wick.rotation.y = face_yaw(f)


## One game-camera cell: aim at `at`, grab, crop.
func _cell(at: Vector3, size: Vector2i, ortho: float = GAME_SIZE) -> Image:
	aim(GAME_YAW, GAME_PITCH, ortho, at + Vector3(0, 0.3, 0))
	return _crop(await grab(), size)


# --- the run --------------------------------------------------------------------------------------------------------

func _run_pests(only: String) -> void:
	await wait_frames(10)
	var dir := shot_path.get_base_dir()
	if only == "" or only == "rats":
		await _rats(dir)
	if only == "" or only == "packs":
		await _packs(dir)
	if only == "" or only == "blobs":
		await _blobs(dir)
	if only == "" or only == "close":
		await _close(dir)
	if only == "" or only == "lineup":
		await _lineup(dir)
	finish()


## A row per rat: running at Wick, reared up at him, biting, and running in the dark gallery.
func _rats(dir: String) -> void:
	var rows: Array = []
	var names: Array = []
	var toward_wick := -RIGHT + TOWARD * 0.35
	for v: String in RatModel.VARIANTS:
		var row: Array[Image] = []
		for col in 4:
			_clear()
			var at: Vector3 = gallery if col == 3 else chamber
			var pose := ["run", "windup", "swing", "run"][col] as String
			_wick(at - RIGHT * 1.6 + TOWARD * 0.1, RIGHT - TOWARD * 0.2)
			_pest("rat", v, pose, at + RIGHT * 0.4, toward_wick)
			row.append(await _cell(at - RIGHT * 0.5, CELL))
		rows.append(row)
		names.append("%s: %s" % [v, RatModel.NAMES[v]])
	var blocks := [["burial chamber (candle-lit)", ["running", "reared up (the tell)", "biting"]], ["ossuary gallery (dark)", ["running"]]]
	await _sheet("%s/rats.png" % dir, "Crypt rats at the game camera (size 24, 1:1), Wick for scale  -  docs/design/crypt-pests-look.md",
			names, blocks, rows, CELL, 0)
	await _sheet("%s/rats_2x.png" % dir, "The same, the middle of each cell at 2x (nearest)", names, blocks, rows, CELL, 0, 2)


## A pack of six per rat round Wick and Rebar: in the chamber, and in the gallery.
func _packs(dir: String) -> void:
	var rows: Array = []
	var row_names: Array = []
	for light: int in 2:
		var row: Array[Image] = []
		var at: Vector3 = chamber if light == 0 else gallery
		for v: String in RatModel.VARIANTS:
			_clear()
			_wick(at - RIGHT * 1.0 - TOWARD * 0.4, RIGHT + TOWARD * 0.3)
			var rebar: Node3D = crew["rebar"]
			rebar.visible = true
			rebar.position = at - RIGHT * 2.4 + TOWARD * 0.6
			rebar.rotation.y = face_yaw(RIGHT)
			# the pack streams in from the right at the two of them, spread out, one rearing at Wick
			var spots6 := [Vector3(1.0, 0, -0.2), Vector3(1.9, 0, 0.5), Vector3(2.4, 0, -0.9), Vector3(3.2, 0, 0.1),
					Vector3(3.6, 0, -1.4), Vector3(4.3, 0, 0.8)]
			for i in spots6.size():
				var o: Vector3 = spots6[i]
				var p := at + RIGHT * o.x + TOWARD * o.z
				var f := (at - RIGHT * 1.0 - p).normalized()
				_pest("rat", v, "windup" if i == 0 else "run", p, f, 0.30 + 0.17 * float(i))
			row.append(await _cell(at + RIGHT * 1.2, PACK_CELL))
		rebar_hide()
		rows.append(row)
		row_names.append("burial chamber\n(candle-lit)" if light == 0 else "ossuary gallery\n(dark)")
	var names: Array = []
	for v: String in RatModel.VARIANTS:
		names.append("%s: %s" % [v, RatModel.NAMES[v]])
	await _sheet("%s/rat_packs.png" % dir, "A pack of six at the game camera (size 24, 1:1), Wick and Rebar  -  docs/design/crypt-pests-look.md",
			row_names, [["", names]], rows, PACK_CELL, 0)


func rebar_hide() -> void:
	(crew["rebar"] as Node3D).visible = false


## A row per blob: resting, crawling on its slick, gathered up, lunging (at Wick), and crawling in the dark gallery.
func _blobs(dir: String) -> void:
	var rows: Array = []
	var names: Array = []
	var toward_wick := -RIGHT + TOWARD * 0.6
	for v: String in EctoBlobModel.VARIANTS:
		var row: Array[Image] = []
		for col in 5:
			_clear()
			var at: Vector3 = gallery if col == 4 else chamber
			var pose := ["rest", "crawl", "windup", "swing", "crawl"][col] as String
			_wick(at - RIGHT * 1.9 + TOWARD * 0.1, RIGHT - TOWARD * 0.2)
			var p := at + RIGHT * 0.2
			_pest("blob", v, pose, p, toward_wick, 0.4)
			if pose == "crawl":
				_slick(p, toward_wick, 3.0, 31 + col)
			row.append(await _cell(at + RIGHT * 0.25, BLOB_CELL))
		rows.append(row)
		names.append("%s: %s" % [v, EctoBlobModel.NAMES[v]])
	var blocks := [["burial chamber (candle-lit)", ["resting", "crawling, its slick", "gathered up (the tell)", "lunging"]],
			["ossuary gallery (dark)", ["crawling"]]]
	await _sheet("%s/blobs.png" % dir, "Ecto blobs at the game camera (size 24, 1:1), Wick for scale  -  docs/design/crypt-pests-look.md",
			names, blocks, rows, BLOB_CELL, 0)
	await _sheet("%s/blobs_2x.png" % dir, "The same, the middle of each cell at 2x (nearest)", names, blocks, rows, BLOB_CELL, 0, 2)


## Closer, in the lit display room: each variant in its four poses.
func _close(dir: String) -> void:
	(crew["wick"] as Node3D).visible = false
	var f := RIGHT * -1.0 + TOWARD * 0.5
	for kind: String in ["rat", "blob"]:
		var rows: Array = []
		var names: Array = []
		var vs: Array[String] = RatModel.VARIANTS if kind == "rat" else EctoBlobModel.VARIANTS
		var poses: Array = ["rest", "run", "windup", "swing"] if kind == "rat" else ["rest", "crawl", "windup", "swing"]
		for v: String in vs:
			var row: Array[Image] = []
			for pose: String in poses:
				_clear()
				_pest(kind, v, pose, shelf, f, 0.42 if kind == "rat" else 0.4)
				if pose == "crawl":
					_slick(shelf, f, 3.0, 41)
				var aim_at := shelf + Vector3(0, 0.1, 0) + (RIGHT * 0.25 if pose == "crawl" else Vector3.ZERO)
				row.append(await _cell(aim_at, CLOSE_CELL, CLOSE_RAT if kind == "rat" else CLOSE_BLOB))
			rows.append(row)
			names.append("%s:\n%s" % [v, (RatModel.NAMES if kind == "rat" else EctoBlobModel.NAMES)[v]])
		var cols := ["resting", "running", "reared up (the tell)", "biting"] if kind == "rat" else ["resting", "crawling", "gathered up (the tell)", "lunging"]
		await _sheet("%s/%s_close.png" % [dir, "rats" if kind == "rat" else "blobs"],
				"%s, closer (size %.1f) at the game angles, in a lit display room" % ["Crypt rats" if kind == "rat" else "Ecto blobs",
				CLOSE_RAT if kind == "rat" else CLOSE_BLOB], names, [["", cols]], rows, CLOSE_CELL, 0)


## The roster for scale at the game camera, in the display room (the chamber is too small for the row): Wick, Rebar, the grunt, the swarmer imp, the mourner, the
## three rats and the three blobs.
func _lineup(dir: String) -> void:
	_clear()
	var f := TOWARD * 1.0 - RIGHT * 0.6
	var base := shelf - RIGHT * 7.0 - TOWARD * 1.0
	var x := 0.0
	_wick(base, f)
	var rebar: Node3D = crew["rebar"]
	rebar.visible = true
	rebar.position = base + RIGHT * 1.7
	rebar.rotation.y = face_yaw(f)
	x = 3.5
	for kind: String in ["grunt", "swarmer"]:
		var m := MonsterModels.make(kind)
		stage.add_child(m)
		m.position = base + RIGHT * x
		m.rotation.y = face_yaw(f)
		m.pose_preview("rest", 1.0)
		x += 1.4
	var z := ZombieModel.new("mourner")
	z.idle_enabled = false
	stage.add_child(z)
	z.position = base + RIGHT * x
	z.rotation.y = face_yaw(f)
	z.apply_idle(0.6, 0.0)
	x += 1.4
	for v: String in RatModel.VARIANTS:
		_pest("rat", v, "rest", base + RIGHT * x, -RIGHT + TOWARD * 0.6)
		x += 1.25
	x += 0.2
	for v: String in EctoBlobModel.VARIANTS:
		_pest("blob", v, "rest", base + RIGHT * x, -RIGHT + TOWARD * 0.6)
		x += 1.9 if v == "puddle" else 1.5
	var mid := base + RIGHT * (x * 0.5 - 0.6)
	aim(GAME_YAW, GAME_PITCH, GAME_SIZE, mid - TOWARD * 1.4 + Vector3(0, 0.3, 0))
	var img := _crop(await grab(), Vector2i(1000, 300))
	save_shot(img, "%s/lineup.png" % dir)
	var big := img.get_region(Rect2i(0, 0, 1000, 300))
	big.resize(2000, 600, Image.INTERPOLATE_NEAREST)
	save_shot(big, "%s/lineup_2x.png" % dir)
	rebar_hide()
