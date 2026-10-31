extends "res://scripts/art/lowpoly/crypt/crypt_section_lab.gd"
## Wall depth lab (docs/design/wall-depth.md): HexMapView's wall depth look (`wall_depth`, a shader uniform) off vs on, on
## the crypt section lab's map. LOOK-DEV ONLY. The crypt in its two sets (CryptLook: lit almost only by ambient and candles),
## then the same map as a lair in the game's own light (DungeonLook's key, fill and downlight pools; the game's flagstone
## and rough stone blocks rows, a torture chamber's materials), where bent normals show much more.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/wall_depth_lab.tscn --shot <abs dir>/sets.png
##
## PNGs, next to --shot (docs/design/wall_depth/):
##   <set>_off.png, <set>_on.png   the crypt at the game camera (yaw 45, pitch -56, size 24), full frame; set: vault,
##                                 chapel, lair (the lair: the burial chamber's room in the game's light)
##   sets.png                      the middle of each of those, off | on, 1:1
##   close.png                     a wall corner and its cap (size 8), off | on, a row per set
##   close_2x.png                  the same, the middle doubled (nearest)

const CLOSE_SIZE_WD := 8.0
const VIEW_CROP := Vector2i(840, 300)
const CORNER_CROP := Vector2i(840, 300)
const VIEW_AT := Vector2i(1000, 440)   ## where the view crop centres (the entry vault's back wall, the stairs, the gallery)

var lair := false   ## the map in the game's light and materials (no CryptLook restyle or relight, no props)


func _ready() -> void:
	make_camera(260.0)
	build("vault")
	if shot_path != "":
		_compare()


## The crypt lab's build, or the lair: the same map, HexMapView in the game's own tables, DungeonLook with its pools.
func build_lair() -> void:
	lair = true
	set_name = "vault"
	if holder != null:
		remove_child(holder)
		holder.free()
	holder = Node3D.new()
	holder.name = "Section"
	add_child(holder)
	_cells = {}
	levels = {}
	stair_of = {}
	hall_cells = {}
	routes = {}
	crew = {}
	lights = []
	labels = []
	display = []
	_layout()
	_make_map()
	# (the lair's flagstone and rough stone, not the crypt's rows the lab paints with)
	var lair_mat := FloorMaterials.pack(FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	for c: Vector2i in map.cells:
		if map.cells[c].tag != "room:0":
			map.cells[c].mat_id = lair_mat
	GameWorld.begin(map, holder, 11)
	terrain = HexMapView.new()
	terrain.wall_depth = wall_depth
	holder.add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(holder, map)
	var b0: Vector2i = keys["chamber"]
	var gr: Array[Vector2i] = routes["gallery"]
	spots["crypt"] = (_w(b0) + _w(gr[3])) * 0.5 - TOWARD * 1.5


## A wall corner to look at closely: an outside corner (a cut cell with two wall kites, the wall's wedge pointing away from
## the camera, so both its faces and the quoins show) in the crypt's rooms, nearest the burial chamber.
func corner_spot() -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	var target := _w(keys["chamber"])
	for c: Vector2i in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type == HexMap.Tile.WALL or cell.wall_mask == 0 or Hex.distance(c, DISPLAY) <= 8:
			continue
		var n := 0
		var dir := Vector3.ZERO
		for k in 6:
			if (cell.wall_mask >> k) & 1 == 1:
				n += 1
				dir += Hex.kite_corner(k)
		if n != 2 or dir.normalized().dot(TOWARD) > -0.6 or cell.level != 0:
			continue
		var w := Hex.to_world(c)
		var d := w.distance_to(target)
		if d < best_d:
			best_d = d
			best = w
	return best + Vector3(0, float(WALL_LEVEL) * LH * 0.6, 0)


func _set_depth(on: bool) -> void:
	wall_depth = on
	terrain.set_wall_depth(on)


func _compare() -> void:
	await wait_frames(10)
	var dir := shot_path.get_base_dir()
	var view_rows: Array = []
	var close_rows: Array = []
	var names: Array = []
	for s: String in ["vault", "chapel", "lair"]:
		if s == "lair":
			build_lair()
		elif s != set_name:
			build(s)
		await wait_frames(6)
		if not lair:
			_stage("crypt")
		names.append("lair: the game's light" if s == "lair" else str(CryptLook.look(s)["title"]))
		var vrow: Array[Image] = []
		var crow: Array[Image] = []
		var corner := corner_spot()
		for on: bool in [false, true]:
			_set_depth(on)
			aim(GAME_YAW, GAME_PITCH, GAME_SIZE, spots["crypt"])
			var img := await snap("%s/%s_%s.png" % [dir, s, "on" if on else "off"])
			var vi := img.duplicate() as Image
			vi.convert(Image.FORMAT_RGBA8)
			vrow.append(vi.get_region(Rect2i(VIEW_AT - VIEW_CROP / 2, VIEW_CROP)))
			aim(GAME_YAW, GAME_PITCH, CLOSE_SIZE_WD, corner)
			crow.append(_crop(await grab(), CORNER_CROP))
		view_rows.append(vrow)
		close_rows.append(crow)
	var cols := [["", ["wall depth off (today)", "wall depth on"]]]
	await _sheet(shot_path, "Wall depth at the game camera (size 24, 1:1; the full frames are <set>_off / _on.png)  -  docs/design/wall-depth.md", names, cols, view_rows,
			VIEW_CROP, 0)
	await _sheet("%s/close.png" % dir, "A wall corner and its cap, closer (size 8)", names, cols, close_rows, CORNER_CROP, 0)
	await _sheet("%s/close_2x.png" % dir, "The same, the middle at 2x (nearest)", names, cols, close_rows, CORNER_CROP, 0, 2)
	finish()
