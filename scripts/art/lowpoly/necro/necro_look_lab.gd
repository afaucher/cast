extends LabBase
## Necro look lab (docs/design/necro-look.md): the zombies, the acolytes and the grimoire (NecroBody: ZombieModel,
## AcolyteModel, GrimoireModel) at the game camera (yaw 45, pitch -56, size 24, 1:1 pixels) in a mansion room (the ghost
## look lab's: wood boards, panelling, HexMapView, DungeonLook, one warm downlight pool over the bright spot, the dark
## corner in the walls' shadow), a lineup with the heroes, the grunt, the brute and the staff, and the grimoire next to the
## hellgates. LOOK-DEV ONLY: nothing here is used by the game.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/necro_look_lab.tscn --shot <abs dir>/zombie.png [--set <name>]
##
## PNGs, next to --shot (docs/design/necro_look/):
##   zombie.png, zombie_2x.png       a row per zombie: stand, shamble, about to rise, burnt (bright), stand, rising (dark)
##   acolyte.png, acolyte_2x.png     a row per acolyte: idle, raising, fleeing (bright), idle, raising (dark)
##   grimoire.png, grimoire_2x.png   a row per stand: open, damaged, shut, burnt
##   grimoire_scale.png              the whole game frame: the origin gate, a hellgate and both grimoires, Wick and Rebar
##   lineup.png, lineup_2x.png       Wick, Rebar, the grunt, the brute, the staff, the henchman, both zombies, both acolytes
##   strip_rim.png                   the zombies and the acolytes with the rim off and on, bright and dark
##   close_zombie.png, close_acolyte.png, close_grimoire.png   closer, lower three-quarter views
## --set   all (default) | zombie | acolyte | grimoire | scale | lineup | rim | close
## The glows, the pulse and the grimoire are frozen at one moment (NecroLook.clock, GrimoireModel.freeze_at).

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const CLOSE_YAW := 45.0
const CLOSE_PITCH := -30.0
const CLOCK := 0.0
const ROOM_R := 10
const WALL_R := 12
const CROP := Vector2i(420, 300)          ## a figure's cell, 1:1 game pixels
const CROP_G := Vector2i(440, 380)        ## a grimoire's cell
const CROP_C := Vector2i(360, 540)        ## a close-up's cell
const CROP_S := Vector2i(300, 228)        ## the rim strip's cell
const RIGHT := Vector3(0.7071, 0.0, -0.7071)       ## the game camera's screen right on the floor
const TOWARD := Vector3(0.7071, 0.0, 0.7071)       ## toward the game camera on the floor
const FIG_YAW := -120.0                   ## a figure (its front is -Z) three-quarters to the camera (GymSpawns.GHOST_YAW)
const FACE_YAW := -135.0                  ## square to the camera
const LIGHT_NAMES := {"bright": "bright room", "dark": "dark corner"}

var set_name := "all"
var holder: Node3D
var terrain: HexMapView
var spots := {}                          ## "bright" / "dark" / "middle" -> a floor point


func _ready() -> void:
	set_name = arg(args, "--set", "all")
	make_camera(220.0)
	_build_room()
	holder = Node3D.new()
	holder.name = "Subjects"
	add_child(holder)
	if shot_path != "":
		_run()


# --- the room (the ghost look lab's, a little bigger) -------------------------------------------------------------------

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
	spots["middle"] = _floor_near(Vector3.ZERO)
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


## The dark corner: the floor cell out of the downlight's pool where the most of a figure stands in the walls' shadow from
## the key light, with no wall between it and the camera (the ghost look lab's rule).
func _dark_corner() -> Vector3:
	var to_light := Basis.from_euler(Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)).z.normalized()
	var pitch := deg_to_rad(-GAME_PITCH)
	var to_cam := (TOWARD * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	var pool: Vector3 = spots["bright"]
	var best := Vector3.ZERO
	var best_k := -INF
	for c: Vector2i in map.cells:
		if map.cells[c].type == HexMap.Tile.WALL or Hex.distance(c, Vector2i.ZERO) < ROOM_R - 3:
			continue
		var w := Hex.to_world(c)
		var shade := 0
		var room := true
		for p: Vector3 in [w, w - RIGHT * 1.2, w + RIGHT * 1.2, w + TOWARD * 1.4, w + Vector3(0, 1.2, 0)]:
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


## A still NecroBody of `kind` / `variant` / `pose` at `at` (a grimoire: `pose` is its state), turned as the gym turns it.
func stage(kind: String, variant: String, pose: String, at: Vector3, yaw: float = INF) -> NecroBody:
	var b := NecroBody.new()
	b.kind = kind
	b.variant = variant
	b.pose = "state" if kind == "grimoire" else pose
	b.state = pose if kind == "grimoire" else ""
	b.live = false
	b._rebuild()
	holder.add_child(b)
	b.position = at
	if yaw == INF:
		yaw = FACE_YAW if kind == "grimoire" else (-60.0 if pose == "flee" else FIG_YAW)
	b.rotation_degrees.y = yaw
	return b


func _figure(m: Node3D, pos: Vector3, yaw: float = FACE_YAW) -> Node3D:
	holder.add_child(m)
	if m is LowPolyModel:
		(m as LowPolyModel).idle_enabled = false
	if m is EmployeeModel:
		(m as EmployeeModel).pose_preview("stand")
	elif m is LowPolyModel:
		(m as LowPolyModel).apply_idle(0.6)
	m.position = pos
	m.rotation_degrees.y = yaw
	return m


## Render one cell: `kind` staged at `light`'s spot, the game camera on it, the middle `crop` of the frame.
func _cell(kind: String, variant: String, pose: String, light: String, crop: Vector2i) -> Image:
	_clear()
	var at: Vector3 = spots[light]
	var b := stage(kind, variant, pose, at)
	var look := at + Vector3(0, 1.1 if kind == "grimoire" else 0.8, 0)
	if kind == "acolyte" and pose == "raise":
		look += b.basis * NecroBody.RAISED_AT * 0.25
	aim(GAME_YAW, GAME_PITCH, GAME_SIZE, look)
	return await _crop(crop)


func _crop(crop: Vector2i) -> Image:
	var img := await grab()
	img.convert(Image.FORMAT_RGBA8)
	return img.get_region(Rect2i(img.get_width() / 2 - crop.x / 2, img.get_height() / 2 - crop.y / 2, crop.x, crop.y))


## A close-up cell: lower and nearer (orthographic, `size` across the frame's height), three-quarters.
func _close(kind: String, variant: String, pose: String, size: float) -> Image:
	_clear()
	var at: Vector3 = spots["bright"]
	var b := stage(kind, variant, pose, at)
	var look := at + Vector3(0, 1.3 if kind == "grimoire" else 0.95, 0)
	if kind == "acolyte" and pose == "raise":
		look += b.basis * NecroBody.RAISED_AT * 0.2
	if kind == "zombie" and (pose == "rising" or pose == "burnt"):
		look = at + Vector3(0, 0.35, 0) + b.basis * Vector3(0, 0, -0.5)
	aim(CLOSE_YAW, CLOSE_PITCH, size, look)
	return await _crop(CROP_C)


# --- the run --------------------------------------------------------------------------------------------------------------

func _run() -> void:
	NecroLook.reset()
	GhostLook.reset()
	NecroLook.clock = CLOCK
	await wait_frames(10)
	var dir := shot_path.get_base_dir()
	var all := set_name == "all"
	if all or set_name == "zombie":
		await _zombie_sheet(dir)
	if all or set_name == "acolyte":
		await _acolyte_sheet(dir)
	if all or set_name == "grimoire":
		await _grimoire_sheet(dir)
	if all or set_name == "scale":
		await _scale_shot(dir)
	if all or set_name == "lineup":
		await _lineup(dir)
	if all or set_name == "rim":
		await _rim_strip(dir)
	if all or set_name == "close":
		await _closeups(dir)
	NecroLook.reset()
	finish()


func _zombie_sheet(dir: String) -> void:
	var rows: Array = []
	var bright: Array[String] = ["stand", "shamble", "rising", "burnt"]
	var dark: Array[String] = ["stand", "rising"]
	for v: String in NecroBody.VARIANTS["zombie"]:
		var row: Array[Image] = []
		for p in bright:
			row.append(await _cell("zombie", v, p, "bright", CROP))
		for p in dark:
			row.append(await _cell("zombie", v, p, "dark", CROP))
		rows.append(row)
	var names := ["stand", "shamble", "about to rise", "burnt (stays down)"]
	var blocks := [[LIGHT_NAMES["bright"], names], [LIGHT_NAMES["dark"], ["stand", "about to rise"]]]
	await _sheet("%s/zombie.png" % dir, "Zombies at the game camera (size 24, 1:1), pale blue  -  docs/design/necro-look.md",
			NecroBody.VARIANTS["zombie"], blocks, rows, CROP, 294)
	await _sheet("%s/zombie_2x.png" % dir, "The same at 2x (the middle of each cell)", NecroBody.VARIANTS["zombie"], blocks, rows, CROP, 294, 2)


func _acolyte_sheet(dir: String) -> void:
	var rows: Array = []
	for v: String in NecroBody.VARIANTS["acolyte"]:
		var row: Array[Image] = []
		for p: String in ["idle", "raise", "flee"]:
			row.append(await _cell("acolyte", v, p, "bright", CROP))
		for p: String in ["idle", "raise"]:
			row.append(await _cell("acolyte", v, p, "dark", CROP))
		rows.append(row)
	var blocks := [[LIGHT_NAMES["bright"], ["idle", "raising the dead", "fleeing"]], [LIGHT_NAMES["dark"], ["idle", "raising the dead"]]]
	await _sheet("%s/acolyte.png" % dir, "Acolytes at the game camera (size 24, 1:1), pale blue  -  docs/design/necro-look.md",
			NecroBody.VARIANTS["acolyte"], blocks, rows, CROP, 340)
	await _sheet("%s/acolyte_2x.png" % dir, "The same at 2x (the middle of each cell)", NecroBody.VARIANTS["acolyte"], blocks, rows, CROP, 340, 2)


func _grimoire_sheet(dir: String) -> void:
	var rows: Array = []
	for v: String in NecroBody.VARIANTS["grimoire"]:
		var row: Array[Image] = []
		for st: String in NecroLook.STATES:
			row.append(await _cell("grimoire", v, st, "bright", CROP_G))
		rows.append(row)
	var blocks := [[LIGHT_NAMES["bright"], ["open (pulsing)", "damaged", "slammed shut", "burnt"]]]
	await _sheet("%s/grimoire.png" % dir, "The grimoire at the game camera (size 24, 1:1), pale blue  -  docs/design/necro-look.md",
			NecroBody.VARIANTS["grimoire"], blocks, rows, CROP_G, 440)
	await _sheet("%s/grimoire_2x.png" % dir, "The same at 2x (the middle of each cell)", NecroBody.VARIANTS["grimoire"], blocks, rows, CROP_G, 440, 2)


## The whole game frame on the room's middle: the origin gate, a hellgate, the grimoire on its lectern and on its altar
## (open), Wick and Rebar in front of them, each labelled under it.
func _scale_shot(dir: String) -> void:
	_clear()
	var c: Vector3 = spots["middle"]
	var tags: Array = []
	var og := HellgateModel.make(true)
	holder.add_child(og)
	og.position = c - RIGHT * 12.5 - TOWARD * 1.0
	og.set_active(true)
	og.freeze_at(1.0)
	tags.append(["origin gate", og.position])
	var hg := HellgateModel.make(false)
	holder.add_child(hg)
	hg.position = c - RIGHT * 5.4 - TOWARD * 0.5
	hg.set_active(true)
	hg.freeze_at(1.0)
	tags.append(["hellgate", hg.position])
	var lec := stage("grimoire", "lectern", "open", c + RIGHT * 1.6 - TOWARD * 0.5)
	tags.append(["grimoire: lectern", lec.position])
	var alt := stage("grimoire", "altar", "open", c + RIGHT * 10.6 - TOWARD * 0.8)
	tags.append(["grimoire: altar", alt.position])
	var wick := _figure(WickModel.new(), c - RIGHT * 1.4 + TOWARD * 4.2)
	tags.append(["Wick", wick.position])
	var rebar := _figure(RebarModel.new(), c + RIGHT * 5.8 + TOWARD * 4.0)
	tags.append(["Rebar", rebar.position])
	aim(GAME_YAW, GAME_PITCH, GAME_SIZE, c + Vector3(0, 0.5, 0) + TOWARD * 0.8)
	var img := await grab()
	img.convert(Image.FORMAT_RGBA8)
	var labels: Array = []
	for tg: Array in tags:
		var p := _screen(tg[1] as Vector3)
		labels.append([str(tg[0]), Vector2(p.x - 40, p.y + 40)])
	await _picture("%s/grimoire_scale.png" % dir, img, Rect2i(0, 0, img.get_width(), img.get_height()), 1,
			"The whole game frame (size 24, 1:1): the grimoire beside the hellgates  -  docs/design/necro-look.md", labels)


## Wick, Rebar, the grunt, the brute, the staff, the henchman, then the zombies and the acolytes, in a row across the
## screen, at the game camera.
func _lineup(dir: String) -> void:
	_clear()
	var c: Vector3 = spots["middle"] - RIGHT * 9.0 + TOWARD * 2.0
	var row := [["Wick", WickModel.new(), 1.3], ["Rebar", RebarModel.new(), 2.0], ["grunt", GruntModel.new(), 1.5],
			["brute", BruteModel.new(), 2.3], ["staff", EmployeeModel.new("staff"), 1.3], ["henchman", EmployeeModel.new("henchman"), 1.4]]
	var x := 0.0
	var placed: Array = []
	for r: Array in row:
		x += float(r[2]) * 0.5
		placed.append([str(r[0]), _figure(r[1] as Node3D, c + RIGHT * x)])
		x += float(r[2]) * 0.5
	for f: Array in [["mourner", "zombie", "mourner", "stand", 1.5], ["digger", "zombie", "digger", "stand", 1.9],
			["cowl", "acolyte", "cowl", "idle", 1.4], ["mask", "acolyte", "mask", "idle", 1.4]]:
		x += float(f[4]) * 0.5
		placed.append([str(f[0]), stage(str(f[1]), str(f[2]), str(f[3]), c + RIGHT * x, FACE_YAW + 15.0)])
		x += float(f[4]) * 0.5
	var mid := c + RIGHT * (x * 0.5)
	aim(GAME_YAW, GAME_PITCH, GAME_SIZE, mid + Vector3(0, 0.9, 0))
	var img := await grab()
	img.convert(Image.FORMAT_RGBA8)
	var w := 880
	var h := 250
	var rect := Rect2i(img.get_width() / 2 - w / 2, img.get_height() / 2 - h / 2 - 10, w, h)
	var labels: Array = []
	for p: Array in placed:
		var sp := _screen((p[1] as Node3D).global_position)
		labels.append([str(p[0]), Vector2(sp.x - rect.position.x - 22, sp.y - rect.position.y + 26)])
	await _picture("%s/lineup.png" % dir, img, rect, 1, "Lineup at the game camera (size 24, 1:1): heroes, the grunt, the brute, the staff, the zombies, the acolytes", labels)
	await _picture("%s/lineup_2x.png" % dir, img, rect, 2, "The same at 2x", labels)


func _rim_strip(dir: String) -> void:
	var rows: Array = []
	var names: Array = []
	for f: Array in [["zombie", "mourner", "stand"], ["zombie", "digger", "rising"], ["acolyte", "cowl", "idle"], ["acolyte", "mask", "raise"]]:
		names.append(str(f[1]))
		var row: Array[Image] = []
		for light: String in ["bright", "dark"]:
			for on: bool in [false, true]:
				NecroLook.rim = on
				row.append(await _cell(str(f[0]), str(f[1]), str(f[2]), light, CROP_S))
		rows.append(row)
	NecroLook.rim = true
	await _sheet("%s/strip_rim.png" % dir, "The rim off / on (pale blue): the mourner standing, the digger rising, the cowl idle, the mask raising", names,
			[[LIGHT_NAMES["bright"], ["rim off", "rim on"]], [LIGHT_NAMES["dark"], ["rim off", "rim on"]]], rows, CROP_S, 300)


func _closeups(dir: String) -> void:
	var sets := {
		"zombie": [["zombie", "mourner", "stand"], ["zombie", "mourner", "rising"], ["zombie", "digger", "stand"], ["zombie", "digger", "shamble"], ["zombie", "mourner", "burnt"]],
		"acolyte": [["acolyte", "cowl", "idle"], ["acolyte", "cowl", "raise"], ["acolyte", "mask", "idle"], ["acolyte", "mask", "raise"], ["acolyte", "cowl", "flee"]],
		"grimoire": [["grimoire", "lectern", "open"], ["grimoire", "altar", "open"], ["grimoire", "lectern", "damaged"], ["grimoire", "altar", "shut"], ["grimoire", "lectern", "burnt"]],
	}
	for k: String in sets:
		var row: Array[Image] = []
		var names: Array = []
		for f: Array in sets[k]:
			row.append(await _close(str(f[0]), str(f[1]), str(f[2]), 12.0 if k == "grimoire" else 4.6))
			names.append("%s: %s" % [f[1], f[2]])
		await _sheet("%s/close_%s.png" % [dir, k], "Close-ups, lower and nearer than the game camera (not how it plays)", [""], [["", names]], [row], CROP_C, 360)


## A labelled contact sheet (the ghost look lab's): `row_names` down the left, column blocks [[title, [names]], ...] across
## the top, `rows` the images (row-major, each `crop`, cut to `cw` wide round its middle; `zoom` 2: the middle half,
## doubled), laid out in window pixels and grabbed.
func _sheet(path: String, title: String, row_names: Array, blocks: Array, rows: Array, crop: Vector2i, cw: int, zoom: int = 1) -> void:
	_clear()
	var layer := _canvas()
	var ch := crop.y
	var gap := 4
	var block_gap := 20
	var x0 := 112 if str(row_names[0]) != "" else 10
	var y0 := 80
	var head := _label(layer, title, Vector2(10, 8), 22)
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
			var img: Image = (row[c] as Image).get_region(Rect2i((crop.x - cw / zoom) / 2, (crop.y - ch / zoom) / 2, cw / zoom, ch / zoom))
			if zoom != 1:
				img.resize(cw, ch, Image.INTERPOLATE_NEAREST)
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.position = Vector2(xs[c], y)
			layer.add_child(tr)
	var bottom := y0 + rows.size() * (ch + 6)
	await _save_canvas(layer, path, Vector2i(right + 10, bottom + 4))


## One picture (`rect` of `img`, `zoom`ed nearest) under a title, with labels [[text, position in the rect]].
func _picture(path: String, img: Image, rect: Rect2i, zoom: int, title: String, labels: Array) -> void:
	_clear()
	var layer := _canvas()
	var head := _label(layer, title, Vector2(10, 8), 22)
	head.modulate = Color(1.0, 0.9, 0.7)
	var y0 := 44
	var part := img.get_region(rect)
	if zoom != 1:
		part.resize(rect.size.x * zoom, rect.size.y * zoom, Image.INTERPOLATE_NEAREST)
	var size := Vector2i(mini(part.get_width(), 1920), mini(part.get_height(), 1080 - y0))
	part = part.get_region(Rect2i(0, 0, size.x, size.y))
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(part)
	tr.position = Vector2(0, y0)
	layer.add_child(tr)
	for l: Array in labels:
		var p: Vector2 = (l[1] as Vector2) * zoom + Vector2(0, y0)
		var lb := _label(layer, str(l[0]), p, 15)
		lb.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		lb.add_theme_constant_override("outline_size", 5)
	await _save_canvas(layer, path, Vector2i(size.x, size.y + y0))


## Where world point `p` lands in the grabbed frame (window pixels: the canvas stretch makes the viewport's own units smaller).
func _screen(p: Vector3) -> Vector2:
	return camera.unproject_position(p) * (float(get_window().size.x) / get_viewport().get_visible_rect().size.x)


func _canvas() -> Control:
	var canvas := CanvasLayer.new()
	canvas.name = "SheetCanvas"
	add_child(canvas)
	var layer := Control.new()
	var k := get_viewport().get_visible_rect().size.x / float(get_window().size.x)
	layer.scale = Vector2(k, k)
	canvas.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.11, 0.1)
	bg.size = Vector2(1920, 1080)
	layer.add_child(bg)
	return layer


func _save_canvas(layer: Control, path: String, size: Vector2i) -> void:
	var shot := await grab(8)
	shot.convert(Image.FORMAT_RGBA8)
	save_shot(shot.get_region(Rect2i(0, 0, mini(size.x, shot.get_width()), mini(size.y, shot.get_height()))), path)
	layer.get_parent().queue_free()
	await wait_frames(2)


func _label(parent: Control, text: String, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l
