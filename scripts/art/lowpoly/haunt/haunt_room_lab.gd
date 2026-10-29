class_name HauntRoomLab
extends LabBase
## The shared machinery of the haunted rooms' look labs (MansionRoomsLab, ChurchRoomsLab; LOOK-DEV ONLY): a room built the
## way the game draws one (a HexMap of hex columns with DungeonGen's 3-level walls cut to midpoint lines, HexMapView,
## DungeonLook), dressed with HauntLook's lab-only materials and lit by HauntLook's lights, its HauntProps put down from a
## layout, Wick, Rebar and a grunt standing in it for scale; the game camera on it (yaw 45, pitch -56, ortho size 24,
## 1:1 pixels); and labelled contact sheets composed in the window and grabbed.
##
## A room is {id, name, a, L, floor, wall, props: [[kind, Vector3 pos, yaw, params], ...], cast: {wick, rebar, grunt: pos}}.
## Its floor is an elongated hexagon of hex cells: rows r in [-a, a], q and q + r in [-L, L]. The back wall (far from the
## camera) is the straight line z = -1.5 a; the upper-left wall runs from (-SQRT3 L, 0) to (-SQRT3 (L - a / 2), -1.5 a).
## Both face the camera; `wall_spot` puts a wall piece's back against either.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const WALL_LEVELS := 3                 ## DungeonGen's default wall height (levels above the floor)
const SEAM := 0.35                     ## HexMapView.seam_gain: the seams turned down (the wood floors' is 0.6, carpet's 0.3)
const ROOM_CROP := Vector2i(950, 860)  ## a room at the game camera, 1:1
const TOWARD := Vector3(0.7071, 0.0, 0.7071)       ## toward the game camera on the floor
const RIGHT := Vector3(0.7071, 0.0, -0.7071)       ## the game camera's screen right on the floor

var stage: Node3D
var terrain: HexMapView
var room_now := {}
var props: Array[Node3D] = []
var only := ""                         ## --only <room id>: render just that room's sheet (iteration)


func _ready() -> void:
	only = arg(args, "--only", "")
	make_camera(240.0)
	if shot_path != "":
		_run.call_deferred()


## Override: the lab's sheets.
func _run() -> void:
	finish()


# --- the room ----------------------------------------------------------------------------------------------------------

static func floor_cells(a: int, l: int) -> Dictionary:
	var out := {}
	for r in range(-a, a + 1):
		for q in range(-l - a - 1, l + a + 2):
			if q <= l and q + r <= l and q >= -l and q + r >= -l:
				out[Vector2i(q, r)] = true
	return out


## Build `room` (its map, terrain, lights, props and cast) on a fresh stage, lit `light` (HauntLook.MODES).
func build_room(room: Dictionary, light: String, with_cast: bool = true) -> void:
	_clear_stage()
	room_now = room
	stage = Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	map = HexMap.new()
	var cells := floor_cells(int(room["a"]), int(room["L"]))
	var mat := HauntLook.pack(int(room["floor"]), int(room["wall"]))
	for c: Vector2i in cells:
		var cell := map.set_cell(c, 0)
		cell.tag = "room:0"
		cell.mat_id = mat
	for c: Vector2i in cells:
		for d in Hex.DIRS:
			var n: Vector2i = c + d
			if not map.cells.has(n):
				map.set_cell(n, WALL_LEVELS, HexMap.Tile.WALL).mat_id = mat
	map.cut_walls()
	GameWorld.begin(map, stage, 7)
	GameWorld.fx_rng.seed = hash(str(room["id"]))
	terrain = HexMapView.new()
	terrain.seam_gain = float(room.get("seam", SEAM))
	stage.add_child(terrain)
	terrain.build(map)
	HauntLook.dress_terrain(terrain)
	DungeonLook.apply(stage, map)
	for pr: Array in (room["props"] as Array):
		place(str(pr[0]), pr[1], float(pr[2]), pr[3] if pr.size() > 3 else {})
	if with_cast:
		var cast: Dictionary = room.get("cast", {})
		for who: String in cast:
			cast_member(who, cast[who])
	HauntLook.apply_light(stage, light)


func _clear_stage() -> void:
	props.clear()
	if stage != null:
		remove_child(stage)
		stage.free()
		stage = null


func place(kind: String, pos: Vector3, yaw: float, params: Dictionary = {}) -> Node3D:
	var m := HauntProps.build(kind, params)
	stage.add_child(m)
	m.position = pos
	m.rotation_degrees.y = yaw
	props.append(m)
	return m


## Wick, Rebar or a grunt at `pos`, idling, turned three-quarters to the camera.
func cast_member(who: String, pos: Vector3) -> Node3D:
	var m: LowPolyModel
	match who:
		"rebar": m = RebarModel.new()
		"grunt": m = GruntModel.new()
		_: m = WickModel.new()
	stage.add_child(m)
	m.idle_enabled = false
	m.apply_idle(0.6)
	m.position = pos
	var face := TOWARD + RIGHT * (0.5 if who == "wick" else -0.5)
	m.rotation_degrees = Vector3(0, rad_to_deg(atan2(-face.x, -face.z)), 0)
	return m


## A wall piece's spot: `wall` "back" (z = -1.5 a) or "left" (the upper-left wall), `t` along it (0 = its left end), the
## piece's `depth` (its back on the wall). Returns [pos, yaw].
static func wall_spot(a: int, l: int, wall: String, t: float, depth: float) -> Array:
	var off := depth * 0.5 + 0.04
	if wall == "left":
		var p0 := Vector3(-Hex.SQRT3 * l, 0, 0)
		var p1 := Vector3(-Hex.SQRT3 * (l - a * 0.5), 0, -1.5 * a)
		var n := Vector3(0.866, 0, 0.5)
		return [p0.lerp(p1, t) + n * off, 60.0]
	var xb := Hex.SQRT3 * (l - a * 0.5)
	return [Vector3(lerpf(-xb, xb, t), 0, -1.5 * a + off), 0.0]


## A wall piece of `kind` on a wall (HauntProps' depth), as a layout row.
static func on_wall(room: Dictionary, kind: String, wall: String, t: float, params: Dictionary = {}) -> Array:
	var d := float(HauntProps.row(kind).get("d", 0.5))
	var s := wall_spot(int(room["a"]), int(room["L"]), wall, t, d)
	return [kind, s[0], s[1], params]


# --- shots -------------------------------------------------------------------------------------------------------------

## The game camera on the room's middle; returns the frame's centre crop of `size`.
func room_shot(size: Vector2i = ROOM_CROP, zoom: float = GAME_SIZE, at: Vector3 = Vector3(0, 0.8, 0)) -> Image:
	aim(GAME_YAW, GAME_PITCH, zoom, at)
	var img := await grab(8)
	img.convert(Image.FORMAT_RGBA8)
	return img.get_region(Rect2i(img.get_width() / 2 - size.x / 2, img.get_height() / 2 - size.y / 2, size.x, size.y))


## A close-up of one prop node: the game angle, zoomed so its bounds fill a `size` square.
func prop_shot(m: Node3D, size: int = 300) -> Image:
	var box := AABB()
	var first := true
	for c in m.get_children():
		if c is MeshInstance3D:
			var b: AABB = (c as MeshInstance3D).get_aabb()
			b = (m.global_transform * (c as MeshInstance3D).transform) * b
			box = b if first else box.merge(b)
			first = false
		elif c is Node3D:
			for cc in c.get_children():
				if cc is MeshInstance3D:
					var b2: AABB = (m.global_transform * (c as Node3D).transform * (cc as MeshInstance3D).transform) * (cc as MeshInstance3D).get_aabb()
					box = b2 if first else box.merge(b2)
					first = false
	aim(GAME_YAW, GAME_PITCH, 10.0, box.get_center())
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var ex := 0.0
	var ey := 0.0
	for i in 8:
		var p := box.get_endpoint(i) - box.get_center()
		ex = maxf(ex, absf(p.dot(right)))
		ey = maxf(ey, absf(p.dot(up)))
	var vh := float(get_window().size.y)
	var zoom := maxf(ex, ey) * 2.0 * vh / (size * 0.86)
	aim(GAME_YAW, GAME_PITCH, maxf(zoom, 1.5), box.get_center())
	var img := await grab(8)
	img.convert(Image.FORMAT_RGBA8)
	return img.get_region(Rect2i(img.get_width() / 2 - size / 2, img.get_height() / 2 - size / 2, size, size))


## The middle `src` of an image, doubled with nearest-neighbour scaling (the pixels as the game draws them, larger).
static func twice(img: Image, src: Vector2i) -> Image:
	var c := img.get_region(Rect2i(img.get_width() / 2 - src.x / 2, img.get_height() / 2 - src.y / 2, src.x, src.y))
	c.resize(src.x * 2, src.y * 2, Image.INTERPOLATE_NEAREST)
	return c


## A labelled grid sheet: `title` on top, `rows` of [label, [[caption, Image], ...]], laid out in window pixels, grabbed
## and saved to `path`. Row labels down the left when `left` > 0.
func sheet(path: String, title: String, rows: Array, left: int = 0) -> void:
	_clear_stage()
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
	var head := _label(layer, title, Vector2(10, 6), 20)
	head.modulate = Color(1.0, 0.9, 0.7)
	var y := 38
	var right := 0
	for row: Array in rows:
		var cells: Array = row[1]
		var x := 10 + left
		var h := 0
		if left > 0:
			_label(layer, str(row[0]), Vector2(10, y + 30), 17)
		for cell: Array in cells:
			var img: Image = cell[1]
			var cap := _label(layer, str(cell[0]), Vector2(x + 2, y), 15)
			cap.modulate = Color(1.0, 0.85, 0.45)
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.position = Vector2(x, y + 20)
			layer.add_child(tr)
			x += img.get_width() + 6
			h = maxi(h, img.get_height())
		right = maxi(right, x)
		y += h + 26
	var shot := await grab(8)
	shot.convert(Image.FORMAT_RGBA8)
	save_shot(shot.get_region(Rect2i(0, 0, mini(right + 4, shot.get_width()), mini(y, shot.get_height()))), path)
	canvas.queue_free()
	await wait_frames(2)


func _label(parent: Control, text: String, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


## Close-ups of `kinds` (each alone on `room`'s floor, against its back wall when it is a wall piece), lit `light`,
## `cols` across. Returns the sheet rows.
func close_rows(room: Dictionary, kinds: Array, light: String, cols: int, params: Dictionary = {}) -> Array:
	var bare := room.duplicate()
	bare["props"] = []
	bare["cast"] = {}
	build_room(bare, light, false)
	var rows: Array = []
	var cells: Array = []
	for kind: String in kinds:
		var r := HauntProps.row(kind)
		var pos := Vector3(0, 0, 0)
		var yaw := 0.0
		if bool(r.get("wall", false)):
			var s := wall_spot(int(room["a"]), int(room["L"]), "back", 0.5, float(r.get("d", 0.5)))
			pos = s[0]
		var m := place(kind, pos, yaw, params.get(kind, {}))
		HauntLook.apply_light(stage, light)
		var img := await prop_shot(m)
		cells.append([str(r.get("label", kind)), img])
		props.erase(m)
		stage.remove_child(m)
		m.free()
		if cells.size() == cols:
			rows.append(["", cells])
			cells = []
	if not cells.is_empty():
		rows.append(["", cells])
	return rows
