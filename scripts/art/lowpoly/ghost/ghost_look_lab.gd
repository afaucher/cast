extends LabBase
## Ghost look lab (docs/design/ghost-look.md): GhostLook's three looks on the three ghosts (GhostBody: the skeleton, the
## suit of armour, the wisp) in a bright room and a dark corner, at the game camera (yaw 45, pitch -56, size 24, 1:1
## pixels), with Wick and Rebar standing by for scale and contrast. The room is the game's drawing (HexMapView, DungeonLook):
## a wood-floored, panelled room (FloorMaterials), one warm downlight pool (DungeonLook's) over the bright spot, and the
## dark corner at the foot of the far walls, out of the pool and in the key light's wall shadow. LOOK-DEV ONLY: nothing
## here is used by the game.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/ghost_look_lab.tscn --shot <abs dir>/sheet.png [--each <abs dir>]
##
## PNGs, next to --shot (docs/design/ghost_look/):
##   sheet.png            soft, pale blue: a row per ghost, a column per look, in the bright room and the dark corner
##   sheet_2x.png         the same, the middle of each cell at twice the size
##   strip_strength.png   the armour: a row per look, faint / soft / strong, bright and dark
##   strip_colour.png     the armour: a row per look, pale blue / ecto green, bright and dark
## --each   also writes every cell's crop there (<look>_<body>_<light>_<strength>_<colour>.png; not committed)
## The pulse and the shimmer's drift are frozen at CLOCK (GhostLook.clock), so the stills are the look at a steady moment.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const CLOCK := 0.0                  ## the frozen shader clock (the pulse at its middle)
const WISP_T := 1.9                 ## where on its loop the wisp is posed (drifting toward the camera and a little right)
const ROOM_R := 9
const WALL_R := 11
const CROP := Vector2i(420, 300)    ## each cell's crop round the subject, 1:1 game pixels
const LIGHTS: Array[String] = ["bright", "dark"]
const LIGHT_NAMES := {"bright": "bright room", "dark": "dark corner"}
const RIGHT := Vector3(0.7071, 0.0, -0.7071)       ## the game camera's screen right on the floor
const TOWARD := Vector3(0.7071, 0.0, 0.7071)       ## toward the game camera on the floor

var holder: Node3D
var terrain: HexMapView
var spots := {}                     ## "bright" / "dark" -> the subject's floor point
var crops := {}                     ## key -> Image (CROP)
var each_dir := ""


func _ready() -> void:
	each_dir = arg(args, "--each", "")
	make_camera(220.0)
	_build_room()
	holder = Node3D.new()
	holder.name = "Subjects"
	add_child(holder)
	if shot_path != "":
		_run()


# --- the room ---------------------------------------------------------------------------------------------------------

## A radius-9 room of wood boards in panelled walls (a mansion room), the walls 3 high. The bright spot sits a few cells
## toward the camera from the middle under one warm downlight; the dark corner is the far (north-west) corner, out of the
## pool, where the west wall shades the floor from the key light.
func _build_room() -> void:
	map = HexMap.new()
	var mat := FloorMaterials.pack(FloorMaterials.F_WOOD, FloorMaterials.W_PANELLING)
	for c in Hex.range_cells(Vector2i.ZERO, WALL_R):
		var d := Hex.distance(c, Vector2i.ZERO)
		var cell: HexMap.Cell
		if d <= ROOM_R:
			cell = map.set_cell(c, 0)
			cell.tag = "room:0"
		else:
			cell = map.set_cell(c, 6, HexMap.Tile.WALL)
		cell.mat_id = mat
	GameWorld.begin(map, self, 7)
	terrain = HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self)
	spots["bright"] = _floor_near(Vector3(2.6, 0, 2.6))
	spots["dark"] = _dark_corner()
	var l := OmniLight3D.new()
	l.name = "Downlight"
	l.position = (spots["bright"] as Vector3) + Vector3(-0.8, DungeonLook.POOL_HEIGHT, -0.8)
	l.light_color = DungeonLook.WARM
	l.light_energy = 11.0
	l.omni_range = 9.5
	l.omni_attenuation = 1.8
	l.light_specular = 0.2
	add_child(l)


func _floor_near(p: Vector3) -> Vector3:
	return Hex.to_world(Hex.from_world(p))


## The dark corner: the floor cell, out of the downlight's pool, where the most of the subject and the two heroes beside it
## stand in the walls' shadow from the key light (DungeonLook's KeyLight); the farther from the pool the better.
func _dark_corner() -> Vector3:
	var to_light := Basis.from_euler(Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)).z.normalized()
	var pitch := deg_to_rad(-GAME_PITCH)
	var to_cam := (TOWARD * cos(pitch) + Vector3.UP * sin(pitch)).normalized()   # (and no wall between it and the camera)
	var pool: Vector3 = spots["bright"]
	var best := Vector3.ZERO
	var best_k := -INF
	for c: Vector2i in map.cells:
		if map.cells[c].type == HexMap.Tile.WALL or Hex.distance(c, Vector2i.ZERO) < ROOM_R - 3:
			continue
		var w := Hex.to_world(c)
		var shade := 0
		var room := true
		for p: Vector3 in [w, w - RIGHT * 1.55 + TOWARD * 0.35, w + RIGHT * 1.6 + TOWARD * 0.2, w + Vector3(0, 1.2, 0)]:
			shade += 1 if _in_shadow(p, to_light) else 0
			var pc := Hex.from_world(p)
			room = room and map.cells.has(pc) and map.cells[pc].type != HexMap.Tile.WALL and not _in_shadow(p, to_cam)
		if not room:
			continue
		var k := shade * 100.0 + w.distance_to(pool)
		if k > best_k:
			best_k = k
			best = w
	return best


## True when a wall stands between `p` and the key light (a wall cell under the ray below its top, 3 up); with the camera's
## direction, whether a wall hides `p` from the camera.
func _in_shadow(p: Vector3, to_light: Vector3) -> bool:
	var t := 0.2
	while t < 8.0:
		var q := p + to_light * t
		if q.y > 6 * Hex.LEVEL_HEIGHT:
			return false
		var c := Hex.from_world(q)
		if map.cells.has(c) and map.cells[c].type == HexMap.Tile.WALL:
			return true
		t += 0.15
	return false


# --- subjects -------------------------------------------------------------------------------------------------------

func _clear() -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.free()


## One cell's scene: the ghost `kind` at `at` (a wisp's head over it), Wick to its left and Rebar to its right.
func _stage(kind: String, at: Vector3) -> void:
	_clear()
	var g := GhostBody.make(kind)
	g.drift = false
	holder.add_child(g)
	g.position = at
	if kind == "wisp":
		var dp := g.drift_point(WISP_T)
		g.position = at - Vector3(dp.x, 0.0, dp.z)
		g.pose_wisp(WISP_T)
	else:
		g.rotation_degrees.y = GymSpawns.GHOST_YAW
		g.model.idle_enabled = false
		g.model.apply_idle(0.6)
	_hero("wick", at - RIGHT * 1.55 + TOWARD * 0.35, TOWARD + RIGHT * 0.6)
	_hero("rebar", at + RIGHT * 1.6 + TOWARD * 0.2, TOWARD - RIGHT * 0.6)


func _hero(which: String, pos: Vector3, face: Vector3) -> void:
	var m: LowPolyModel = RebarModel.new() if which == "rebar" else WickModel.new()
	holder.add_child(m)
	m.idle_enabled = false
	m.apply_idle(0.6)
	m.position = pos
	m.rotation_degrees = Vector3(0, rad_to_deg(atan2(-face.x, -face.z)), 0)


static func key_of(look: String, kind: String, light: String, strength: String, colour: String) -> String:
	return "%s_%s_%s_%s_%s" % [look, kind, light, strength, colour.replace(" ", "_")]


## Render (or reuse) one cell: the switches set, the ghost staged, the game camera on it, the middle CROP of the frame.
func _cell(look: String, kind: String, light: String, strength: String, colour: String) -> Image:
	var k := key_of(look, kind, light, strength, colour)
	if crops.has(k):
		return crops[k]
	GhostLook.look = look
	GhostLook.strength = strength
	GhostLook.colour = colour
	GhostLook.clock = CLOCK
	var at: Vector3 = spots[light]
	_stage(kind, at)
	aim(GAME_YAW, GAME_PITCH, GAME_SIZE, at + Vector3(0, 0.9, 0))
	var img := await grab()
	img.convert(Image.FORMAT_RGBA8)
	var crop := img.get_region(Rect2i(img.get_width() / 2 - CROP.x / 2, img.get_height() / 2 - CROP.y / 2, CROP.x, CROP.y))
	crops[k] = crop
	if each_dir != "":
		save_shot(crop, "%s/%s.png" % [each_dir, k])
	return crop


# --- the run --------------------------------------------------------------------------------------------------------------

func _run() -> void:
	await wait_frames(10)
	var dir := shot_path.get_base_dir()
	if each_dir != "":
		DirAccess.make_dir_recursive_absolute(each_dir)
	# the main sheet: soft, pale blue; a row per ghost, the looks in the bright room then the dark corner
	var rows: Array = []
	for kind: String in GhostBody.KINDS:
		var row: Array[Image] = []
		for light in LIGHTS:
			for look: String in GhostLook.LOOKS:
				row.append(await _cell(look, kind, light, "soft", "pale blue"))
		rows.append(row)
	await _sheet(shot_path, "Ghost look test: soft, pale blue, at the game camera (size 24, 1:1)  -  docs/design/ghost-look.md",
			GhostBody.KINDS, [[LIGHT_NAMES["bright"], GhostLook.LOOKS], [LIGHT_NAMES["dark"], GhostLook.LOOKS]], rows, 294)
	# the same, twice the size (the middle of each cell, nearest-neighbour: the pixels as the game draws them, larger)
	await _sheet("%s/sheet_2x.png" % dir, "The same at 2x (the middle of each cell): soft, pale blue",
			GhostBody.KINDS, [[LIGHT_NAMES["bright"], GhostLook.LOOKS], [LIGHT_NAMES["dark"], GhostLook.LOOKS]], rows, 294, 2)
	# the strength strip: the armour, a row per look
	rows = []
	for look: String in GhostLook.LOOKS:
		var row: Array[Image] = []
		for light in LIGHTS:
			for st: String in GhostLook.STRENGTHS:
				row.append(await _cell(look, "armour", light, st, "pale blue"))
		rows.append(row)
	await _sheet("%s/strip_strength.png" % dir, "Ghost strength on the armour: faint / soft / strong, pale blue",
			GhostLook.LOOKS, [[LIGHT_NAMES["bright"], GhostLook.STRENGTHS], [LIGHT_NAMES["dark"], GhostLook.STRENGTHS]], rows, 294)
	# the colour strip: the armour, a row per look
	rows = []
	for look: String in GhostLook.LOOKS:
		var row: Array[Image] = []
		for light in LIGHTS:
			for col: String in GhostLook.COLOURS:
				row.append(await _cell(look, "armour", light, "soft", col))
		rows.append(row)
	await _sheet("%s/strip_colour.png" % dir, "Ghost colour on the armour: pale blue / ecto green, soft",
			GhostLook.LOOKS, [[LIGHT_NAMES["bright"], GhostLook.COLOURS], [LIGHT_NAMES["dark"], GhostLook.COLOURS]], rows, 420)
	GhostLook.reset()
	finish()


## A labelled contact sheet: `row_names` down the left, column blocks [[block title, [column names]], ...] across the top,
## `rows` the images (row-major, each CROP, cut to `cw` wide round its middle; `zoom` 2: the middle half, doubled), laid
## out in window pixels and grabbed.
func _sheet(path: String, title: String, row_names: Array, blocks: Array, rows: Array, cw: int, zoom: int = 1) -> void:
	_clear()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	# laid out in window pixels: the project's canvas_items stretch scales the UI, so undo it
	var layer := Control.new()
	var k := get_viewport().get_visible_rect().size.x / float(get_window().size.x)
	layer.scale = Vector2(k, k)
	canvas.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.11, 0.1)
	bg.size = Vector2(1920, 1080)
	layer.add_child(bg)
	var ch := CROP.y
	var gap := 4
	var block_gap := 20
	var x0 := 112
	var y0 := 80
	var head := _label(layer, title, Vector2(x0, 8), 22)
	head.modulate = Color(1.0, 0.9, 0.7)
	var xs: Array[int] = []
	var x := x0
	for b: Array in blocks:
		var names: Array = b[1]
		var bl := _label(layer, str(b[0]), Vector2(x, 38), 17)
		bl.modulate = Color(1.0, 0.85, 0.4)
		for n in names:
			xs.append(x)
			_label(layer, str(n), Vector2(x + 4, 56), 15)
			x += cw + gap
		x += block_gap
	var right := x - block_gap - gap
	for r in rows.size():
		var y := y0 + r * (ch + 6)
		_label(layer, str(row_names[r]), Vector2(10, y + ch / 2 - 12), 18)
		var row: Array = rows[r]
		for c in row.size():
			var img: Image = (row[c] as Image).get_region(Rect2i((CROP.x - cw / zoom) / 2, (CROP.y - ch / zoom) / 2, cw / zoom, ch / zoom))
			if zoom != 1:
				img.resize(cw, ch, Image.INTERPOLATE_NEAREST)
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.position = Vector2(xs[c], y)
			layer.add_child(tr)
	var bottom := y0 + rows.size() * (ch + 6)
	var shot := await grab(8)
	shot.convert(Image.FORMAT_RGBA8)
	var w := mini(right + 10, shot.get_width())
	var h := mini(bottom + 4, shot.get_height())
	save_shot(shot.get_region(Rect2i(0, 0, w, h)), path)
	canvas.queue_free()
	await wait_frames(2)


func _label(parent: Control, text: String, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l
