extends HauntRoomLab
## Haunted mansion rooms lab (docs/design/mansion-rooms.md; a look-dev lab): the library, the portrait gallery, the
## ballroom, the dining hall and the conservatory, each built the way the game draws a room (HauntRoomLab) and dressed with
## HauntProps' mansion pieces, in two material sets (HauntLook.SETS: walnut & damask, oak & stripe; the conservatory keeps
## its terracotta and glazing in both) and two lights (cold moonlight, candle light), at the game camera with Wick, Rebar
## and a grunt standing in each room for scale. The lab itself is look-dev; its rooms, props and walnut & damask
## materials are the game's mansion room themes since haunted-build-plan.md H1 (the oak set stays lab-only).
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/mansion_rooms_lab.tscn --shot <abs dir>/sheet.png [--only <room>]
##
## PNGs, next to --shot (docs/design/mansion_rooms/):
##   sheet.png             every room in moonlight and candle light (walnut set), shrunk to 0.4 (the overview)
##   <room>.png            one room at the game camera, 1:1: moonlight | candle light (walnut set)
##   sets.png              the library, the ballroom and the dining hall in the walnut set and the oak set (candle light), 1:1
##   sheet_2x.png          the middle of every room at 2x (candle light, walnut set)
##   materials.png         the floors and walls close up: walnut, oak, conservatory (candle light, then moonlight)
##   props.png             close-ups of the key props
## --only <room>   writes just <room>.png (for iterating on one room)

const ROOM_IDS: Array[String] = ["library", "gallery", "ballroom", "dining", "conservatory"]
const ROOM_NAMES := {"library": "library", "gallery": "portrait gallery", "ballroom": "ballroom", "dining": "dining hall",
	"conservatory": "conservatory"}
const SIZES := {"library": [3, 5], "gallery": [2, 6], "ballroom": [4, 5], "dining": [3, 5], "conservatory": [3, 5]}
const CLOSE_KINDS: Array[String] = ["bookshelf", "library_ladder", "reading_chair", "globe", "reading_table", "portrait",
	"gallery_screen", "bust", "chandelier", "grand_piano", "wall_mirror", "candelabra", "dining_table", "dining_chair",
	"fireplace", "planter_bed", "potted_palm", "wardian_case"]
const CLOSE_PARAMS := {"dining_table": {"length": 3.4}, "portrait": {"v": 1, "big": true}}


## The room `id` in material set `set_name` (HauntLook.SETS).
static func room(id: String, set_name: String = "walnut") -> Dictionary:
	var sz: Array = SIZES[id]
	var r := {"id": id, "name": ROOM_NAMES[id], "a": int(sz[0]), "L": int(sz[1])}
	var mats: Dictionary = HauntLook.CONSERVATORY if id == "conservatory" else HauntLook.SETS[set_name]
	r["floor"] = int(mats["floor"])
	r["wall"] = int(mats["wall"])
	match id:
		"library": r["props"] = _layout_library(r)
		"gallery": r["props"] = _layout_gallery(r)
		"ballroom": r["props"] = _layout_ballroom(r)
		"dining": r["props"] = _layout_dining(r)
		_: r["props"] = _layout_conservatory(r)
	r["cast"] = _cast(id)
	return r


## Where Wick, Rebar and the grunt stand in each room (the open floor near the middle).
static func _cast(id: String) -> Dictionary:
	match id:
		"library": return {"wick": Vector3(0.4, 0, 2.6), "rebar": Vector3(2.6, 0, 2.9), "grunt": Vector3(1.0, 0, -1.6)}
		"gallery": return {"wick": Vector3(-1.4, 0, 1.6), "rebar": Vector3(1.0, 0, 2.0), "grunt": Vector3(4.6, 0, 1.4)}
		"ballroom": return {"wick": Vector3(-1.6, 0, 2.2), "rebar": Vector3(0.8, 0, 2.8), "grunt": Vector3(2.2, 0, -0.4)}
		"dining": return {"wick": Vector3(3.2, 0, 2.4), "rebar": Vector3(5.0, 0, 2.2), "grunt": Vector3(4.6, 0, -0.4)}
		_: return {"wick": Vector3(1.2, 0, 2.7), "rebar": Vector3(3.2, 0, 2.6), "grunt": Vector3(0.2, 0, -1.2)}


static func _back(r: Dictionary, kind: String, x: float, params: Dictionary = {}) -> Array:
	var xb := Hex.SQRT3 * (int(r["L"]) - int(r["a"]) * 0.5)
	return on_wall(r, kind, "back", (x + xb) / (2.0 * xb), params)


static func _layout_library(r: Dictionary) -> Array:
	var out: Array = []
	for i in 6:
		out.append(_back(r, "bookshelf", -4.5 + 1.8 * i, {"seed": 11 + i}))
	out.append(on_wall(r, "bookshelf", "left", 0.3, {"seed": 31}))
	out.append(on_wall(r, "bookshelf", "left", 0.72, {"seed": 32}))
	out.append(["library_ladder", Vector3(1.75, 0, -3.62), 0.0])
	out.append(["bookshelf", Vector3(2.6, 0, 0.2), 0.0, {"seed": 41}])
	out.append(["bookshelf", Vector3(4.4, 0, 0.2), 0.0, {"seed": 42}])
	out.append(["runner", Vector3(-2.0, 0, 0.6), 0.0, {"length": 4.2, "width": 2.8, "color": Color(0.1, 0.24, 0.17), "border": Color(0.5, 0.36, 0.16)}])
	out.append(["reading_table", Vector3(-2.0, 0, 0.3), 0.0, {"seed": 4}])
	out.append(["reading_chair", Vector3(-3.6, 0, 1.4), 60.0])
	out.append(["reading_chair", Vector3(-0.5, 0, 1.6), -30.0, {"color": HauntProps.VELVET_GREEN}])
	out.append(["globe", Vector3(4.2, 0, -2.0), 0.0])
	out.append(["book_stack", Vector3(-0.4, 0, -0.6), 30.0, {"seed": 5}])
	out.append(["book_stack", Vector3(4.6, 0, 0.6), -10.0, {"seed": 6}])
	out.append(["candelabra", Vector3(5.6, 0, -2.6), 0.0])
	out.append(on_wall(r, "sconce", "left", 0.52))
	return out


static func _layout_gallery(r: Dictionary) -> Array:
	var out: Array = []
	var xs: Array[float] = [-7.2, -4.8, -2.4, 0.0, 2.4, 4.8, 7.2]
	for i in xs.size():
		out.append(_back(r, "portrait", xs[i], {"v": i % 5, "big": i % 2 == 1}))
	for x in [-6.0, -3.6, -1.2, 1.2, 3.6, 6.0]:
		out.append(_back(r, "sconce", x))
	out.append(on_wall(r, "portrait", "left", 0.5, {"v": 3, "big": true}))
	out.append(["runner", Vector3(0, 0, 1.0), 0.0, {"length": 16.0, "width": 1.3}])
	out.append(["gallery_screen", Vector3(-3.6, 0, -0.6), 0.0, {"v": 4, "v2": 0}])
	out.append(["gallery_screen", Vector3(3.6, 0, -0.6), 0.0, {"v": 2, "v2": 1}])
	out.append(["bust", Vector3(-7.4, 0, 0.6), 30.0])
	out.append(["bust", Vector3(0.0, 0, -0.9), 0.0])
	out.append(["bust", Vector3(7.4, 0, 0.6), -30.0])
	out.append(["rope_barrier", Vector3(-6.0, 0, -1.9), 0.0, {"length": 2.6}])
	out.append(["rope_barrier", Vector3(6.0, 0, -1.9), 0.0, {"length": 2.6}])
	return out


static func _layout_ballroom(r: Dictionary) -> Array:
	var out: Array = []
	out.append(["medallion", Vector3(0, 0, -0.6), 0.0])
	out.append(["chandelier", Vector3(0, 0, -0.6), 0.0])
	for x in [-4.4, -3.6, -1.4, -0.6, 0.6, 1.4, 3.6, 4.4]:
		out.append(_back(r, "gilt_chair", x))
	for x in [-2.5, 2.5]:
		out.append(_back(r, "wall_mirror", x))
	out.append(_back(r, "sconce", 0.0))
	out.append(on_wall(r, "wall_mirror", "left", 0.5))
	out.append(on_wall(r, "gilt_chair", "left", 0.22))
	out.append(on_wall(r, "gilt_chair", "left", 0.78))
	out.append(["grand_piano", Vector3(-5.2, 0, 1.6), 75.0])
	out.append(["candelabra", Vector3(-4.6, 0, -4.4), 0.0])
	out.append(["candelabra", Vector3(4.6, 0, -4.4), 0.0])
	out.append(["candelabra", Vector3(6.6, 0, 1.0), 0.0])
	out.append(["potted_palm", Vector3(-6.4, 0, -1.6), 0.0, {"seed": 3}])
	return out


static func _layout_dining(r: Dictionary) -> Array:
	var out: Array = []
	out.append(["runner", Vector3(0, 0, 0.3), 0.0, {"length": 8.0, "width": 3.6, "color": Color(0.34, 0.1, 0.1)}])
	out.append(["dining_table", Vector3(0, 0, 0.3), 0.0, {"length": 6.0}])
	for i in 6:
		var x := -3.0 + 0.3 + 0.425 + i * 0.85
		out.append(["dining_chair", Vector3(x, 0, 0.3 - 0.95), 0.0])
		out.append(["dining_chair", Vector3(x, 0, 0.3 + 0.95), 180.0])
	out.append(["dining_chair", Vector3(-3.45, 0, 0.3), 90.0])
	out.append(["dining_chair", Vector3(3.45, 0, 0.3), -90.0])
	out.append(_back(r, "fireplace", 0.0))
	out.append(_back(r, "sideboard", -3.6))
	out.append(_back(r, "sideboard", 3.6))
	out.append(on_wall(r, "portrait", "left", 0.5, {"v": 2, "big": true}))
	out.append(on_wall(r, "sconce", "left", 0.15))
	out.append(on_wall(r, "sconce", "left", 0.85))
	out.append(["candelabra", Vector3(6.2, 0, -1.2), 0.0])
	return out


static func _layout_conservatory(r: Dictionary) -> Array:
	var out: Array = []
	out.append(_back(r, "planter_bed", -3.0, {"seed": 21}))
	out.append(_back(r, "planter_bed", 0.8, {"seed": 22}))
	out.append(["planter_bed", Vector3(-1.2, 0, 0.6), 0.0, {"seed": 23}])
	out.append(["potted_palm", Vector3(-5.4, 0, -1.8), 0.0, {"seed": 24}])
	out.append(["potted_palm", Vector3(4.4, 0, -3.0), 0.0, {"seed": 25}])
	out.append(["potted_palm", Vector3(5.6, 0, 1.6), 0.0, {"seed": 26}])
	out.append(["wardian_case", Vector3(2.6, 0, 0.4), 30.0, {"seed": 27}])
	out.append(["fern_stand", Vector3(-4.8, 0, 1.4), 0.0, {"seed": 28}])
	out.append(["fern_stand", Vector3(3.6, 0, -1.4), 0.0, {"seed": 29}])
	out.append(["citrus_tub", Vector3(-7.0, 0, 0.0), 0.0, {"seed": 30}])
	out.append(["citrus_tub", Vector3(7.0, 0, 0.0), 0.0, {"seed": 31}])
	out.append(["garden_bench", Vector3(-2.6, 0, 2.4), 30.0])
	out.append(["candelabra", Vector3(1.4, 0, 2.0), 0.0])
	return out


# --- the run -----------------------------------------------------------------------------------------------------------

func _run() -> void:
	await wait_frames(6)
	var dir := shot_path.get_base_dir()
	var shots := {}   ## "<room>_<set>_<light>" -> Image (ROOM_CROP)
	var ids: Array[String] = []
	if only == "":
		ids.assign(ROOM_IDS)
	elif ROOM_IDS.has(only):
		ids.assign([only])
	for id in ids:
		for light: String in HauntLook.LIGHTS:
			build_room(room(id), light)
			shots["%s_walnut_%s" % [id, light]] = await room_shot()
		await sheet("%s/%s.png" % [dir, id], "Haunted mansion: the %s at the game camera (size 24, 1:1), walnut & damask  -  docs/design/mansion-rooms.md" % ROOM_NAMES[id],
				[["", [["cold moonlight", shots["%s_walnut_moonlight" % id]], ["candle light", shots["%s_walnut_candle" % id]]]]])
	if only != "" and only != "materials" and only != "props":
		finish()
		return
	if only == "":
		await _overview(dir, shots)
	if only == "" or only == "materials":
		await _materials(dir)
	if only == "" or only == "props":
		var prows := await close_rows(room("library"), CLOSE_KINDS, "game", 6, CLOSE_PARAMS)
		await sheet("%s/props.png" % dir, "Mansion props close up (game angle, DungeonLook's warm light; each zoomed to fit)", prows)
	finish()


func _overview(dir: String, shots: Dictionary) -> void:
	# the overview: every room, both lights, shrunk to 0.4
	var rows: Array = []
	for light: String in HauntLook.LIGHTS:
		var cells: Array = []
		for id in ROOM_IDS:
			var img: Image = (shots["%s_walnut_%s" % [id, light]] as Image).duplicate()
			img.resize(380, 344, Image.INTERPOLATE_LANCZOS)
			cells.append([ROOM_NAMES[id], img])
		rows.append([light, cells])
	await sheet(shot_path, "Haunted mansion rooms (walnut & damask): moonlight above, candle light below; shrunk to 0.4 (the room sheets are 1:1)", rows)
	# the material sets: three rooms in both sets, candle light, the middle at 1:1
	rows = []
	for set_name: String in HauntLook.SET_NAMES:
		var cells: Array = []
		for id: String in ["library", "ballroom", "dining"]:
			var key := "%s_%s_candle" % [id, set_name]
			if not shots.has(key):
				build_room(room(id, set_name), "candle")
				shots[key] = await room_shot()
			var img: Image = shots[key]
			cells.append(["%s: %s" % [ROOM_NAMES[id], HauntLook.SETS[set_name]["name"]], img.get_region(Rect2i(165, 195, 620, 470))])
		rows.append([set_name, cells])
	await sheet("%s/sets.png" % dir, "Material sets, candle light, 1:1 (the middle of each room): walnut & damask above, oak & stripe below", rows)
	# 2x: the middle of every room, candle light
	var cells2: Array = []
	for id in ROOM_IDS:
		cells2.append([ROOM_NAMES[id] + " (2x)", twice(shots["%s_walnut_candle" % id], Vector2i(300, 228))])
	await sheet("%s/sheet_2x.png" % dir, "The middle of each room at 2x (nearest-neighbour), candle light, walnut & damask",
			[["", cells2.slice(0, 3)], ["", cells2.slice(3)]])


func _materials(dir: String) -> void:
	# materials close up: a back corner of a bare room per set, zoomed in (size 9)
	var rows: Array = []
	for light: String in HauntLook.LIGHTS:
		var cells: Array = []
		for set_name: String in ["walnut", "oak", "conservatory"]:
			var rm := room("conservatory") if set_name == "conservatory" else room("library", set_name)
			rm["props"] = [["candelabra", Vector3(-1.6, 0, -1.4), 0.0]]
			rm["cast"] = {}
			build_room(rm, light, false)
			var label := "conservatory: terracotta & glazing" if set_name == "conservatory" else str(HauntLook.SETS[set_name]["name"])
			cells.append([label, await room_shot(Vector2i(600, 440), 9.0, Vector3(-3.4, 0.6, -3.2))])
		rows.append([light, cells])
	await sheet("%s/materials.png" % dir, "Floors and walls close up (ortho size 9): moonlight above, candle light below", rows)
