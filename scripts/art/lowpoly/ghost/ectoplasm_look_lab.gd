extends LabBase
## Ectoplasm look lab (docs/design/ectoplasm-look.md): EctoplasmLook's three variants (film, slime, mist) as a floor puddle
## with a drip down the wall behind it, next to today's goo patch (GooSoups.patch) for comparison, on the mansion's wood
## floor (wood boards, wood panelling) and on a crypt's stone floor (corridor stone flags, rough stone blocks), each in a
## bright spot (under one of the game's warm downlights) and a dark spot (the same wall, far out of the pool, toward the
## corner the key light's wall shadow falls in), at the game camera (yaw 45, pitch -56, size 24, 1:1 pixels), with Wick, a
## grunt and Rebar standing by for scale. The rooms are the game's drawing (HexMap with midpoint walls, HexMapView,
## DungeonLook). LOOK-DEV ONLY: nothing here is used by the game.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/ectoplasm_look_lab.tscn --shot <abs dir>/sheet.png [--each <abs dir>]
##
## PNGs, next to --shot (docs/design/ectoplasm_look/):
##   sheet.png          pale blue: a row per variant and today's goo, wood bright / dark, stone bright / dark
##   sheet_2x.png       the same, the middle of each cell at twice the size
##   strip_wash.png     each variant fresh, then Damp washing it away (0.4, 0.7, 0.9), wood bright and stone dark
##   strip_colour.png   each variant in pale blue and ecto green (the ghosts' colour), wood bright and stone dark
##   close.png          a closer camera (size 9) on each variant and the goo, wood bright and stone dark
## --each   also writes every cell's crop there (not committed)
## The swirl, the vapour and the sheen are frozen at CLOCK (EctoplasmLook.clock), so the stills are one steady moment.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const CLOSE_SIZE := 9.0
const CLOCK := 3.0
const ROOM_R := 8
const WALL_R := 10
const ROOMS: Array[String] = ["wood", "stone"]
const ROOM_AT := {"wood": Vector2i(0, 0), "stone": Vector2i(26, 0)}
const ROOM_NAMES := {"wood": "wood floor (mansion)", "stone": "stone floor (crypt)"}
const LIGHTS: Array[String] = ["bright", "dark"]
const CROP := Vector2i(420, 230)          ## a game-camera cell, 1:1 game pixels
const CLOSE_CROP := Vector2i(440, 400)
const PUDDLE_R := 0.9
const GRUNT := Vector2(1.15, 0.35)        ## the grunt: (screen right, toward the camera) from the puddle, at its edge
const REBAR := Vector2(3.0, 1.1)
const GOO := "goo"
const RIGHT := Vector3(0.7071, 0.0, -0.7071)       ## the game camera's screen right on the floor
const TOWARD := Vector3(0.7071, 0.0, 0.7071)       ## toward the game camera on the floor

var holder: Node3D
var terrain: HexMapView
var spots := {}                     ## "<room>_<light>" -> {at, wall, normal}
var crops := {}
var each_dir := ""


func _ready() -> void:
	each_dir = arg(args, "--each", "")
	make_camera(220.0)
	_build_rooms()
	holder = Node3D.new()
	holder.name = "Subjects"
	add_child(holder)
	if shot_path != "":
		_run()


# --- the rooms ----------------------------------------------------------------------------------------------------------

## Two radius-8 rooms far apart on one map, midpoint walls 3 high: wood boards in wood panelling, and corridor stone flags
## in rough stone blocks. In each, the bright spot and the dark spot lie along the far wall (the one facing the camera), the
## bright one under a warm downlight (DungeonLook's pool), the dark one at the wall's other end, out of the pool.
func _build_rooms() -> void:
	map = HexMap.new()
	var mats := {"wood": FloorMaterials.pack(FloorMaterials.F_WOOD, FloorMaterials.W_PANELLING),
			"stone": FloorMaterials.pack(FloorMaterials.F_CORR_STONE, FloorMaterials.W_STONE)}
	for room: String in ROOMS:
		var c0: Vector2i = ROOM_AT[room]
		for c in Hex.range_cells(c0, WALL_R):
			var d := Hex.distance(c, c0)
			var cell: HexMap.Cell
			if d <= ROOM_R:
				cell = map.set_cell(c, 0)
				cell.tag = "room:%d" % ROOMS.find(room)
			else:
				cell = map.set_cell(c, 6, HexMap.Tile.WALL)
			cell.mat_id = mats[room]
	map.cut_walls()
	GameWorld.begin(map, self, 7)
	terrain = HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self)
	for room: String in ROOMS:
		_find_spots(room)
		var l := OmniLight3D.new()
		l.name = "Downlight_" + room
		l.position = (spots[room + "_bright"]["at"] as Vector3) + Vector3(0.6, DungeonLook.POOL_HEIGHT, 0.6)
		l.light_color = DungeonLook.WARM
		l.light_energy = 11.0
		l.omni_range = 9.5
		l.omni_attenuation = 1.8
		l.light_specular = 0.2
		add_child(l)


## The candidate spots of a room: full floor cells 1.1 - 2.2 from a wall face that faces the camera, with the stage (Wick to
## the left, the grunt and Rebar to the right) all on floor and in the camera's view. The bright spot is the one nearest the
## wall's middle-left; the dark one the farthest from it, the most of it in the key light's wall shadow.
func _find_spots(room: String) -> void:
	var c0: Vector2i = ROOM_AT[room]
	var to_light := Basis.from_euler(Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)).z.normalized()
	var pitch := deg_to_rad(-GAME_PITCH)
	var to_cam := (TOWARD * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	var cands: Array = []
	for c: Vector2i in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type == HexMap.Tile.WALL or cell.wall_mask != 0 or Hex.distance(c, c0) > ROOM_R:
			continue
		var w := Hex.to_world(c)
		var nw := map.nearest_wall(w, 2.6)
		if nw.is_empty() or float(nw["dist"]) < 1.1 or float(nw["dist"]) > 2.2:
			continue
		var n2: Vector2 = nw["normal"]
		var n := Vector3(n2.x, 0, n2.y)
		if n.dot(TOWARD) < 0.85:
			continue
		var ok := true
		var shade := 0
		for p: Vector3 in _stage_points(w):
			var pc := Hex.from_world(p)
			ok = ok and map.cells.has(pc) and map.cells[pc].type != HexMap.Tile.WALL and map.cells[pc].wall_mask == 0
			ok = ok and not _blocked(p + Vector3(0, 0.6, 0), to_cam)
			shade += 1 if _blocked(p + Vector3(0, 0.3, 0), to_light) else 0
		if not ok:
			continue
		var wp: Vector2 = nw["point"]
		cands.append({"at": w, "wall": Vector3(wp.x, 0, wp.y), "normal": n, "shade": shade})
	assert(not cands.is_empty(), "ectoplasm lab: no spot by a camera-facing wall")
	# bright: toward the screen-left end of the far wall (the room's west), dark: farthest along it from the bright one
	var mid := Hex.to_world(c0)
	var bright: Dictionary = cands[0]
	for cd: Dictionary in cands:
		if (cd["at"] as Vector3).dot(-RIGHT) - (cd["at"] as Vector3).distance_to(mid) * 0.2 > (bright["at"] as Vector3).dot(-RIGHT) - (bright["at"] as Vector3).distance_to(mid) * 0.2:
			bright = cd
	var dark: Dictionary = cands[0]
	var best := -INF
	for cd: Dictionary in cands:
		var k := float(cd["shade"]) * 4.0 + (cd["at"] as Vector3).distance_to(bright["at"])
		if k > best:
			best = k
			dark = cd
	spots[room + "_bright"] = bright
	spots[room + "_dark"] = dark


## The stage's floor points round a subject spot: the puddle, Wick, the grunt, Rebar.
func _stage_points(at: Vector3) -> Array[Vector3]:
	return [at, at - RIGHT * 1.9 + TOWARD * 0.5, at + RIGHT * GRUNT.x + TOWARD * GRUNT.y, at + RIGHT * REBAR.x + TOWARD * REBAR.y]


## True when a wall stands between `p` and the direction `dir` (a wall cell or a cut cell's wall side under the ray, below
## the walls' top, 3 up).
func _blocked(p: Vector3, dir: Vector3) -> bool:
	var t := 0.2
	while t < 9.0:
		var q := p + dir * t
		if q.y > 6 * Hex.LEVEL_HEIGHT:
			return false
		if map.wall_at(q):
			return true
		t += 0.15
	return false


# --- subjects -----------------------------------------------------------------------------------------------------------

func _clear() -> void:
	for c in holder.get_children():
		holder.remove_child(c)
		c.free()


## One cell's scene: `variant` (or GOO: today's goo patch) on `spot`'s floor with its drip on the wall behind (none for the
## goo), Wick to the left, a grunt and Rebar to the right. `wash`: Damp washing it (EctoplasmLook.set_wash).
func _stage(variant: String, spot: Dictionary, wash: float = 0.0) -> void:
	_clear()
	var at: Vector3 = spot["at"]
	if variant == GOO:
		var g := GooSoups.patch(GooPatch.RADIUS, 29)
		holder.add_child(g)
		g.position = at + Vector3(0, 0.01, 0)
	else:
		var p := EctoplasmLook.puddle(variant, PUDDLE_R, 17)
		holder.add_child(p)
		p.position = at
		var d := EctoplasmLook.drip(variant, 2.2, 23)
		holder.add_child(d)
		var n: Vector3 = spot["normal"]
		var side := Vector3(-n.z, 0, n.x)
		if side.dot(RIGHT) > 0.0:
			side = -side
		d.position = (spot["wall"] as Vector3) + side * 0.55
		d.basis = Basis(Vector3.UP.cross(n).normalized(), Vector3.UP, n)
		if wash > 0.0:
			EctoplasmLook.set_wash(p, wash)
			EctoplasmLook.set_wash(d, wash)
	_hero("wick", at - RIGHT * 1.9 + TOWARD * 0.5, TOWARD + RIGHT * 0.6)
	var gr := MonsterModels.make("grunt")
	holder.add_child(gr)
	gr.position = at + RIGHT * GRUNT.x + TOWARD * GRUNT.y
	gr.rotation_degrees.y = rad_to_deg(atan2(-RIGHT.x + TOWARD.x * 0.6, -RIGHT.z + TOWARD.z * 0.6))
	gr.idle_enabled = false
	gr.pose_preview("rest", 1.0)
	_hero("rebar", at + RIGHT * REBAR.x + TOWARD * REBAR.y, TOWARD - RIGHT * 0.6)


func _hero(which: String, pos: Vector3, face: Vector3) -> void:
	var m: LowPolyModel = RebarModel.new() if which == "rebar" else WickModel.new()
	holder.add_child(m)
	m.idle_enabled = false
	m.apply_idle(0.6)
	m.position = pos
	m.rotation_degrees = Vector3(0, rad_to_deg(atan2(-face.x, -face.z)), 0)


static func key_of(variant: String, room: String, light: String, colour: String, wash: float, size: float) -> String:
	return "%s_%s_%s_%s_w%02d_s%d" % [variant, room, light, colour.replace(" ", "_"), int(wash * 10.0), int(size)]


## Render (or reuse) one cell: the colour set, the subject staged, the camera on it, the middle crop of the frame.
func _cell(variant: String, room: String, light: String, colour: String = "pale blue", wash: float = 0.0,
		size: float = GAME_SIZE) -> Image:
	var k := key_of(variant, room, light, colour, wash, size)
	if crops.has(k):
		return crops[k]
	GhostLook.colour = colour
	EctoplasmLook.clock = CLOCK
	var spot: Dictionary = spots[room + "_" + light]
	_stage(variant, spot, wash)
	var at: Vector3 = spot["at"]
	var close := size < GAME_SIZE
	var aim_at := at + Vector3(0, 0.6, 0) - (spot["normal"] as Vector3) * (0.5 if close else 0.3) + (RIGHT * 0.6 if not close else Vector3.ZERO)
	aim(GAME_YAW, GAME_PITCH, size, aim_at)
	var img := await grab()
	img.convert(Image.FORMAT_RGBA8)
	var cr := CLOSE_CROP if close else CROP
	var crop := img.get_region(Rect2i(img.get_width() / 2 - cr.x / 2, img.get_height() / 2 - cr.y / 2, cr.x, cr.y))
	crops[k] = crop
	if each_dir != "":
		save_shot(crop, "%s/%s.png" % [each_dir, k])
	return crop


# --- the run ------------------------------------------------------------------------------------------------------------

func _run() -> void:
	await wait_frames(10)
	var dir := shot_path.get_base_dir()
	if each_dir != "":
		DirAccess.make_dir_recursive_absolute(each_dir)
	var subjects: Array[String] = []
	subjects.append_array(EctoplasmLook.VARIANTS)
	subjects.append(GOO)
	var row_names: Array = []
	for s in subjects:
		row_names.append("goo (today)" if s == GOO else s)
	var both := [[ROOM_NAMES["wood"], LIGHTS], [ROOM_NAMES["stone"], LIGHTS]]
	# the main sheet: pale blue, a row per variant and the goo
	var rows: Array = []
	for s in subjects:
		var row: Array[Image] = []
		for room in ROOMS:
			for light in LIGHTS:
				row.append(await _cell(s, room, light))
		rows.append(row)
	await _sheet(shot_path, "Ectoplasm look test: pale blue, at the game camera (size 24, 1:1)  -  docs/design/ectoplasm-look.md",
			row_names, both, rows, CROP.x, CROP.y)
	await _sheet("%s/sheet_2x.png" % dir, "The same at 2x (the middle of each cell)", row_names, both, rows, CROP.x, CROP.y, 2)
	# Damp washing it away
	var washes := [0.0, 0.4, 0.7, 0.9]
	var wash_names := ["fresh", "wash 0.4", "wash 0.7", "wash 0.9"]
	rows = []
	for v: String in EctoplasmLook.VARIANTS:
		var row: Array[Image] = []
		for pair: Array in [["wood", "bright"], ["stone", "dark"]]:
			for w: float in washes:
				row.append(await _cell(v, pair[0], pair[1], "pale blue", w))
		rows.append(row)
	await _sheet("%s/strip_wash.png" % dir, "Damp washing ectoplasm away: fresh, then 0.4 / 0.7 / 0.9 (look only)",
			EctoplasmLook.VARIANTS, [["wood, bright", wash_names], ["stone, dark", wash_names]], rows, 210, CROP.y)
	# the ghosts' colour
	rows = []
	for v: String in EctoplasmLook.VARIANTS:
		var row: Array[Image] = []
		for pair: Array in [["wood", "bright"], ["stone", "dark"]]:
			for col: String in GhostLook.COLOURS:
				row.append(await _cell(v, pair[0], pair[1], col))
		rows.append(row)
	await _sheet("%s/strip_colour.png" % dir, "Ectoplasm in the ghosts' colour: pale blue / ecto green",
			EctoplasmLook.VARIANTS, [["wood, bright", GhostLook.COLOURS], ["stone, dark", GhostLook.COLOURS]], rows, CROP.x, CROP.y)
	# close-ups
	rows = []
	for pair: Array in [["wood", "bright"], ["stone", "dark"]]:
		var row: Array[Image] = []
		for s in subjects:
			row.append(await _cell(s, pair[0], pair[1], "pale blue", 0.0, CLOSE_SIZE))
		rows.append(row)
	await _sheet("%s/close.png" % dir, "Closer (size 9): pale blue", ["wood, bright", "stone, dark"], [["", row_names]], rows,
			CLOSE_CROP.x, CLOSE_CROP.y)
	GhostLook.reset()
	EctoplasmLook.clock = -1.0
	finish()


## A labelled contact sheet (ghost_look_lab's): `row_names` down the left, column blocks [[block title, [column names]],
## ...] across the top, `rows` the images (row-major, each cut to `cw` x `ch` round its middle; `zoom` 2: the middle half,
## doubled), laid out in window pixels and grabbed.
func _sheet(path: String, title: String, row_names: Array, blocks: Array, rows: Array, cw: int, ch: int, zoom: int = 1) -> void:
	_clear()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var layer := Control.new()
	var k := get_viewport().get_visible_rect().size.x / float(get_window().size.x)
	layer.scale = Vector2(k, k)
	canvas.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.11, 0.1)
	bg.size = Vector2(1920, 1080)
	layer.add_child(bg)
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
		for nm in names:
			xs.append(x)
			_label(layer, str(nm), Vector2(x + 4, 56), 15)
			x += cw + gap
		x += block_gap
	var right := x - block_gap - gap
	for r in rows.size():
		var y := y0 + r * (ch + 6)
		_label(layer, str(row_names[r]), Vector2(8, y + ch / 2 - 12), 17)
		var row: Array = rows[r]
		for c in row.size():
			var src: Image = row[c]
			var img: Image = src.get_region(Rect2i((src.get_width() - cw / zoom) / 2, (src.get_height() - ch / zoom) / 2, cw / zoom, ch / zoom))
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
