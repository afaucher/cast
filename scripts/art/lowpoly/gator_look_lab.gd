extends LabBase
## Gator look lab (docs/design/gator-look.md): the old gator (SewerProps "gator"), the rebuilds not chosen (GatorLooks v1,
## v2) and the game's gator as built (v3: GatorModel, the rig the game poses), on the sewer slice's real drawing (a
## SewerLayouts.Builder room with a 3.0 channel across it, HexMapView, DungeonLook, SewerView's water and light). LOOK-DEV
## ONLY: nothing here is used by the game. The repo keeps only sheet, lineup, game_v3 and the strips; the rest re-render.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/gator_look_lab.tscn --shot <abs dir>/sheet.png [--set <name>] [--look concrete|brick|toxic] [--frames <abs dir>]
##
## Every PNG goes next to --shot (docs/design/gator_look/):
##   close_<v>     three-quarters close on the deck, at rest (a lazy S, the head turned a little, a breath in)
##   game_<v>      the game camera (yaw 45, pitch -56, size 24): the gator in the channel, Wick on the deck, Rebar wading
##   water_<v>     swimming in the channel, only the top breaking the surface
##   walk_<v>      walking on the deck (the high walk; the old gator has no gait: it glided)
##   open_<v>      the nip's gape, from the front
##   sil_<v>       silhouettes, black on white: top-down over side
##   lineup, lineup_game   Wick, a grunt, the pool shark, then the four gators, three-quarters and at the game camera
##   strip_swim, strip_walk, strip_idle, strip_nip   the motion strips: a row per gator, frames left to right
##   sheet         the comparison sheet (the --shot path): a row per gator, a column per view
## --set     all (default) | close (close_* and sil_* only: the quick iteration loop) | strips | lineup
## --frames  also write the swim and walk cycles as frame sequences (<dir>/<v>_<cycle>_NN.png) for the GIFs (the doc says
##           how to assemble them)

const GatorLooks := preload("res://scripts/art/lowpoly/props/gator_looks.gd")
const SharkModels := preload("res://scripts/art/lowpoly/props/shark_models.gd")
const PoolProps := preload("res://scripts/art/lowpoly/props/pool_props.gd")

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const SCALE := 1.3                                  ## Gator.GATOR_SCALE
const LAND := Vector3(0.6, 0.0, -4.5)               ## a dry deck spot (row -3)
const WATER := Vector3(0.0, -0.48, 0.75)            ## the channel's centre line (rows 0 and 1), the channel floor + WATER_LIFT
const VARS: Array[String] = ["current", "v1", "v2", "v3"]
## The rest pose every still starts from: a lazy S down the tail, the head a little round, a breath in.
const REST := {"bend": 22.0, "wave": 24.0, "phase": 0.3, "head_yaw": 16.0, "breath": 0.6}

var look := "concrete"
var set_name := "all"
var frames_dir := ""
var holder: Node3D
var terrain: HexMapView
var sewer: SewerView
var shots := {}                                     ## name -> Image (for the sheet)
var _white_env: Environment
var _sil_mat: StandardMaterial3D


func _ready() -> void:
	look = arg(args, "--look", "concrete")
	set_name = arg(args, "--set", "all")
	frames_dir = arg(args, "--frames", "")
	make_camera(220.0)
	_build_room()
	holder = Node3D.new()
	holder.name = "Subjects"
	add_child(holder)
	_white_env = Environment.new()
	_white_env.background_mode = Environment.BG_COLOR
	_white_env.background_color = Color(1, 1, 1)
	_white_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_sil_mat = StandardMaterial3D.new()
	_sil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sil_mat.albedo_color = Color(0, 0, 0)
	for v in VARS:
		var m := GatorLooks.build(v, REST)
		print("tris %s %d" % [v, _tris(m)])
		m.free()
	if shot_path != "":
		_run()


# --- the room ---------------------------------------------------------------------------------------------------------

## A radius-9 sewer room, a two-row (3.0) channel running wall to wall along X (rows 0 and 1: z -0.75 .. 2.25), decks on
## both banks, in the sewer slice's drawing.
func _build_room() -> void:
	var b := SewerLayouts.Builder.new()
	b.room(Vector2i.ZERO, 9, "room:0")
	b.make_map()
	var wet := []
	for c: Vector2i in b.cells:
		if c.y == 0 or c.y == 1:
			wet.append(c)
	b.flood(wet)
	b.apply_water()
	b.body_record(look)
	map = b.map
	GameWorld.begin(map, self, 1)
	terrain = HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)
	sewer = SewerView.dress(self, map, terrain, look, [PackedVector2Array([Vector2(-14.0, 0.75), Vector2(14.0, 0.75)])])


# --- subjects -------------------------------------------------------------------------------------------------------

func _clear() -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.free()


## A gator of `v` at `pos` heading `yaw` degrees (0 = +Z), in `pose` (merged over nothing: pass REST explicitly).
func _gator(v: String, pos: Vector3, yaw: float, pose: Dictionary) -> Node3D:
	var m := GatorLooks.build(v, pose)
	m.scale = Vector3.ONE * SCALE
	holder.add_child(m)
	m.position = pos
	m.rotation_degrees.y = yaw
	return m


## The game's ripple ring round the head of a gator swimming along +X from `pos` (Gator._pose: at HEAD 0.9 ahead).
func _ripple(pos: Vector3) -> void:
	var r := PoolProps.build("ripple", {"radius": 0.55})
	holder.add_child(r)
	r.position = Vector3(pos.x + 0.9, SewerLayouts.SURFACE_Y + 0.012, pos.z)


func _hero(which: String, pos: Vector3, face: Vector3) -> Node3D:
	var m: LowPolyModel = RebarModel.new() if which == "rebar" else WickModel.new()
	holder.add_child(m)
	m.idle_enabled = false
	m.apply_idle(0.6)
	m.position = pos
	m.rotation_degrees = Vector3(0, rad_to_deg(atan2(-face.x, -face.z)), 0)
	return m


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = b[k]
	return out


static func _tris(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mesh := (n as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			t += (mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	for c in n.get_children():
		t += _tris(c)
	return t


func _silhouette(on: bool) -> void:
	terrain.visible = not on
	sewer.visible = not on
	camera.environment = _white_env if on else null
	if on:
		for n in holder.find_children("*", "MeshInstance3D", true, false):
			(n as MeshInstance3D).material_override = _sil_mat


# --- shots ------------------------------------------------------------------------------------------------------------

func _run() -> void:
	await wait_frames(10)
	var dir := shot_path.get_base_dir()
	var heading := 90.0                               # every gator swims / walks along +X
	if set_name in ["all", "close"]:
		for v in VARS:
			_clear()
			_gator(v, LAND, heading, REST)
			aim(40.0, -30.0, 3.6, LAND + Vector3(0.1, 0.35, 0))
			shots["close_" + v] = await snap("%s/close_%s.png" % [dir, v])
			await _sil_shots(v, dir, heading)
	if set_name == "all":
		for v in VARS:
			# the game camera: the gator in the channel, Wick on the near deck, Rebar wading toward it
			_clear()
			_gator(v, WATER + Vector3(-0.5, 0, 0), heading, _merge(REST, {"swim": true, "wave": 22.0, "head_yaw": -14.0}))
			_ripple(WATER + Vector3(-0.5, 0, 0))
			_hero("wick", Vector3(4.5, 0, 4.2), Vector3(-1, 0, -1))
			_hero("rebar", Vector3(-4.2, -0.5, 1.0), Vector3(1, 0, 0))
			aim(GAME_YAW, GAME_PITCH, GAME_SIZE, WATER)
			shots["game_" + v] = await snap("%s/game_%s.png" % [dir, v])
			# swimming, close
			_clear()
			_gator(v, WATER, heading, _merge(REST, {"swim": true, "wave": 26.0, "phase": 0.15, "head_yaw": 0.0}))
			_ripple(WATER)
			aim(GAME_YAW, -42.0, 6.0, WATER + Vector3(0.2, 0.3, 0))
			shots["water_" + v] = await snap("%s/water_%s.png" % [dir, v])
			# walking on the deck
			_clear()
			_gator(v, LAND, heading, _merge(REST, {"gait": 0.15, "wave": 0.0, "bend": 0.0}))
			aim(30.0, -26.0, 3.8, LAND + Vector3(0.0, 0.4, 0))
			shots["walk_" + v] = await snap("%s/walk_%s.png" % [dir, v])
			# the nip's gape, from the front
			_clear()
			_gator(v, LAND, heading, _merge(REST, {"jaw": 1.0, "head_pitch": 14.0, "head_yaw": 0.0}))
			aim(68.0, -16.0, 3.4, LAND + Vector3(0.9, 0.45, 0))
			shots["open_" + v] = await snap("%s/open_%s.png" % [dir, v])
	if set_name in ["all", "lineup"]:
		await _lineup(dir)
	if set_name in ["all", "strips"]:
		await _strips(dir)
	if frames_dir != "":
		await _frames()
	if set_name == "all":
		await _sheet()
	finish()


## Black-on-white silhouettes: top-down and from the side, side by side in one image.
func _sil_shots(v: String, dir: String, heading: float) -> void:
	_clear()
	_gator(v, LAND, heading, REST)
	_silhouette(true)
	aim(0.0, -89.9, 4.0, LAND + Vector3(-0.15, 0, 0))
	var top := await grab()
	aim(0.0, -2.0, 4.0, LAND + Vector3(-0.15, 0.45, 0))
	var side := await grab()
	_silhouette(false)
	var w := top.get_width() / 2
	var h := top.get_height() / 2
	var out := Image.create(w, h * 2, false, Image.FORMAT_RGBA8)
	for k in 2:
		var im := (top if k == 0 else side).get_region(Rect2i(w / 2, h / 2, w, h))
		im.convert(Image.FORMAT_RGBA8)
		out.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(0, k * h))
	save_shot(out, "%s/sil_%s.png" % [dir, v])
	shots["sil_" + v] = out


## Wick, a grunt, the pool shark and the four gators in a row on the far deck, three-quarters and at the game camera.
func _lineup(dir: String) -> void:
	_clear()
	var z := -6.0
	var x := -11.2
	_hero("wick", Vector3(x, 0, z), Vector3(0, 0, 1))
	var grunt := GruntModel.new()
	holder.add_child(grunt)
	grunt.idle_enabled = false
	grunt.apply_idle(0.6)
	grunt.position = Vector3(x + 1.6, 0, z)
	grunt.rotation_degrees.y = 180.0
	var shark := SharkModels.build("regular")
	holder.add_child(shark)
	shark.position = Vector3(x + 4.4, 0, z)
	shark.rotation_degrees.y = 90.0
	for i in VARS.size():
		_gator(VARS[i], Vector3(x + 8.4 + 3.6 * float(i), 0, z), 90.0, REST)
	aim(16.0, -24.0, 13.0, Vector3(-1.5, 0.7, z))
	shots["lineup"] = await snap("%s/lineup.png" % dir)
	aim(GAME_YAW, GAME_PITCH, GAME_SIZE, Vector3(0.0, 0, z))
	shots["lineup_game"] = await snap("%s/lineup_game.png" % dir)


## The motion strips: a row per gator, frames left to right, each frame the middle of a close shot.
func _strips(dir: String) -> void:
	var cur_bends := [-44.0, -22.0, 0.0, 22.0, 44.0, 22.0]
	# the swim: one S-wave cycle from above (the current gator: the five bends it has, all it can do)
	# (the water hidden, so the whole body shows)
	var rows: Array = []
	sewer.visible = false
	for v in VARS:
		var row: Array[Image] = []
		for f in 6:
			_clear()
			var pose := {"swim": true, "wave": 36.0, "phase": float(f) / 6.0} if v != "current" else {"bend": cur_bends[f]}
			_gator(v, WATER, 90.0, pose)
			aim(0.0, -89.9, 4.4, WATER + Vector3(-0.3, 0, 0))
			row.append(_mid(await grab(), 0.62, 0.62))
		rows.append(row)
	sewer.visible = true
	_save_strip(rows, "%s/strip_swim.png" % dir, "strip_swim")
	# the walk: half a cycle in six frames, three-quarters
	rows = []
	for v in VARS:
		var row: Array[Image] = []
		for f in 6:
			_clear()
			_gator(v, LAND, 90.0, {"gait": float(f) / 6.0})
			aim(30.0, -26.0, 3.8, LAND + Vector3(0.0, 0.4, 0))
			row.append(_mid(await grab(), 0.6, 0.62))
		rows.append(row)
	_save_strip(rows, "%s/strip_walk.png" % dir, "strip_walk")
	# idle: breathe out, breathe in, a jaw twitch looking right, tracking left with the head up
	var idle := [{"breath": 0.0}, {"breath": 1.0}, {"jaw": 0.18, "head_yaw": -22.0, "breath": 0.5},
		{"head_yaw": 30.0, "head_pitch": 7.0, "breath": 0.3}]
	rows = []
	for v in VARS:
		var row: Array[Image] = []
		for e: Dictionary in idle:
			_clear()
			_gator(v, LAND, 90.0, _merge(REST, e))
			aim(40.0, -30.0, 3.6, LAND + Vector3(0.1, 0.35, 0))
			row.append(_mid(await grab(), 0.6, 0.62))
		rows.append(row)
	_save_strip(rows, "%s/strip_idle.png" % dir, "strip_idle")
	# the nip: watching, the wind-up (head up, jaws parting), the gape, the snap (lunged forward)
	var nip := [{"head_pitch": 4.0}, {"head_pitch": 12.0, "jaw": 0.45}, {"head_pitch": 18.0, "jaw": 1.0},
		{"head_pitch": -4.0, "jaw": 0.0, "bend": 0.0, "wave": 6.0}]
	rows = []
	for v in VARS:
		var row: Array[Image] = []
		for i in nip.size():
			_clear()
			var at := LAND + Vector3(0.45 * SCALE if i == 3 else 0.0, 0, 0)
			_gator(v, at, 90.0, _merge(REST, _merge({"head_yaw": 0.0}, nip[i])))
			aim(55.0, -22.0, 3.6, LAND + Vector3(0.5, 0.4, 0))
			row.append(_mid(await grab(), 0.62, 0.62))
		rows.append(row)
	_save_strip(rows, "%s/strip_nip.png" % dir, "strip_nip")


## The middle `fw` x `fh` of an image, shrunk by half.
static func _mid(img: Image, fw: float, fh: float) -> Image:
	var w := int(img.get_width() * fw)
	var h := int(img.get_height() * fh)
	var out := img.get_region(Rect2i((img.get_width() - w) / 2, (img.get_height() - h) / 2, w, h))
	out.convert(Image.FORMAT_RGBA8)
	out.resize(w / 2, h / 2, Image.INTERPOLATE_BILINEAR)
	return out


func _save_strip(rows: Array, path: String, key: String) -> void:
	var first: Image = (rows[0] as Array)[0]
	var tw := first.get_width()
	var th := first.get_height()
	var cols := (rows[0] as Array).size()
	var out := Image.create(tw * cols + 4 * (cols - 1), th * rows.size() + 4 * (rows.size() - 1), false, Image.FORMAT_RGBA8)
	out.fill(Color(0.1, 0.09, 0.08))
	for r in rows.size():
		for c in cols:
			out.blit_rect((rows[r] as Array)[c], Rect2i(0, 0, tw, th), Vector2i(c * (tw + 4), r * (th + 4)))
	save_shot(out, path)
	shots[key] = out


## The swim and walk cycles as frame sequences (for GIFs), three-quarters, 12 frames each.
func _frames() -> void:
	DirAccess.make_dir_recursive_absolute(frames_dir)
	for v in VARS:
		if v == "current":
			continue
		for f in 12:
			_clear()
			_gator(v, WATER, 90.0, {"swim": true, "wave": 32.0, "phase": float(f) / 12.0, "breath": 0.5})
			_ripple(WATER)
			aim(GAME_YAW, -50.0, 5.0, WATER + Vector3(0.0, 0.2, 0))
			_mid(await grab(), 0.7, 0.62).save_png("%s/%s_swim_%02d.png" % [frames_dir, v, f])
			_clear()
			_gator(v, LAND, 90.0, {"gait": float(f) / 12.0, "breath": 0.5})
			aim(30.0, -26.0, 3.8, LAND + Vector3(0.0, 0.4, 0))
			_mid(await grab(), 0.7, 0.62).save_png("%s/%s_walk_%02d.png" % [frames_dir, v, f])
	print("frames ", frames_dir)


## The comparison sheet: a row per gator, a column per view, labelled.
func _sheet() -> void:
	_clear()
	var cols: Array[String] = ["close", "game", "water", "walk", "open", "sil"]
	var titles := {"close": "three-quarters, at rest", "game": "game camera (size 24, 1:1)", "water": "swimming",
		"walk": "walking", "open": "the nip's gape", "sil": "silhouette: top, side"}
	var canvas := CanvasLayer.new()
	add_child(canvas)
	# laid out in window pixels (1920 x 1080): the project's canvas_items stretch scales the UI, so undo it
	var layer := Control.new()
	var k := get_viewport().get_visible_rect().size.x / float(get_window().size.x)
	layer.scale = Vector2(k, k)
	canvas.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.11, 0.1)
	bg.size = Vector2(1920, 1080)
	layer.add_child(bg)
	var cw := 292
	var ch := 219
	var x0 := 116
	var y0 := 64
	var head := Label.new()
	head.text = "Sewer gator: the old model, the rebuilds, and V3 Mugger as built in the game (docs/design/gator-look.md)"
	head.position = Vector2(x0, 12)
	head.add_theme_font_size_override("font_size", 26)
	layer.add_child(head)
	for c in cols.size():
		var l := Label.new()
		l.text = titles[cols[c]]
		l.position = Vector2(x0 + c * (cw + 6), y0 - 22)
		l.add_theme_font_size_override("font_size", 16)
		layer.add_child(l)
	for r in VARS.size():
		var v := VARS[r]
		var rl := Label.new()
		rl.text = str(GatorLooks.NAMES[v]).replace(" ", "\n")
		rl.position = Vector2(10, y0 + r * (ch + 26) + ch * 0.4)
		rl.add_theme_font_size_override("font_size", 20)
		layer.add_child(rl)
		for c in cols.size():
			var key := "%s_%s" % [cols[c], v]
			if not shots.has(key):
				continue
			var img: Image = (shots[key] as Image).duplicate()
			img.convert(Image.FORMAT_RGBA8)
			if cols[c] == "sil":
				# letterboxed into a white cell (the image is top over side)
				var fit_h := ch
				var fit_w := int(float(img.get_width()) * float(ch) / float(img.get_height()))
				img.resize(fit_w, fit_h, Image.INTERPOLATE_BILINEAR)
				var cell := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
				cell.fill(Color(1, 1, 1))
				cell.blit_rect(img, Rect2i(0, 0, fit_w, fit_h), Vector2i((cw - fit_w) / 2, 0))
				img = cell
			elif cols[c] == "game":
				img = img.get_region(Rect2i(img.get_width() / 2 - cw / 2 - 20, img.get_height() / 2 - ch / 2, cw, ch))
			else:
				var ratio := float(cw) / float(ch)
				var w := img.get_width()
				var h := img.get_height()
				var cwid := int(w * 0.62)
				var chei := int(cwid / ratio)
				if chei > h:
					chei = h
					cwid = int(chei * ratio)
				img = img.get_region(Rect2i((w - cwid) / 2, (h - chei) / 2, cwid, chei))
				img.resize(cw, ch, Image.INTERPOLATE_BILINEAR)
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.position = Vector2(x0 + c * (cw + 6), y0 + r * (ch + 26))
			layer.add_child(tr)
	shots["sheet"] = await snap(shot_path, 8)
	canvas.queue_free()
