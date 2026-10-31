extends HauntRoomLab
## Church rooms lab (docs/design/church-rooms.md; a look-dev lab): the nave (pews either side of a red aisle, the altar on
## its step, lancet windows), the vestry and the bell tower's ringing chamber, built the way the game draws a room
## (HauntRoomLab) in one material set (HauntLook.CHURCH: limestone flags, limestone block walls) and HauntLook's two lights,
## at the game camera with Wick, Rebar and a grunt standing in each room for scale. The lab itself is look-dev; the nave,
## its props and the limestone are the game's church room theme since haunted-build-plan.md H1.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/church_rooms_lab.tscn --shot <abs dir>/sheet.png [--only <room>]
##
## PNGs, next to --shot (docs/design/church_rooms/):
##   sheet.png        every room in moonlight and candle light, shrunk to 0.5 (the overview)
##   <room>.png       one room at the game camera, 1:1: moonlight | candle light
##   sheet_2x.png     the middle of every room at 2x (candle light)
##   props.png        close-ups of the key props
## --only <room>   writes just <room>.png; --only props just props.png

const ROOM_IDS: Array[String] = ["nave", "vestry", "bell_tower"]
const ROOM_NAMES := {"nave": "nave", "vestry": "vestry", "bell_tower": "bell tower"}
const SIZES := {"nave": [3, 6], "vestry": [2, 4], "bell_tower": [3, 3]}
const CLOSE_KINDS: Array[String] = ["pew", "altar", "stained_window", "lectern", "pillar", "candle_rack", "font",
	"vestment_wardrobe", "robe_rack", "vestry_table", "chest", "bell_frame", "bell_ropes", "tower_ladder"]


static func room(id: String) -> Dictionary:
	var sz: Array = SIZES[id]
	var r := {"id": id, "name": ROOM_NAMES[id], "a": int(sz[0]), "L": int(sz[1]),
		"floor": int(HauntLook.CHURCH["floor"]), "wall": int(HauntLook.CHURCH["wall"])}
	match id:
		"nave": r["props"] = _layout_nave(r)
		"vestry": r["props"] = _layout_vestry(r)
		_: r["props"] = _layout_bell_tower(r)
	r["cast"] = _cast(id)
	return r


static func _cast(id: String) -> Dictionary:
	match id:
		"nave": return {"wick": Vector3(1.6, 0, 0.3), "rebar": Vector3(3.8, 0, 0.5), "grunt": Vector3(-4.2, 0, 0.0)}
		"vestry": return {"wick": Vector3(1.4, 0, 2.2), "rebar": Vector3(3.4, 0, 1.9), "grunt": Vector3(-2.2, 0, -1.0)}
		_: return {"wick": Vector3(-1.4, 0, 2.6), "rebar": Vector3(0.8, 0, 3.0), "grunt": Vector3(2.6, 0, 1.4)}


static func _back(r: Dictionary, kind: String, x: float, params: Dictionary = {}) -> Array:
	var xb := Hex.SQRT3 * (int(r["L"]) - int(r["a"]) * 0.5)
	return on_wall(r, kind, "back", (x + xb) / (2.0 * xb), params)


static func _layout_nave(r: Dictionary) -> Array:
	var out: Array = []
	out.append(["runner", Vector3(0.2, 0, 0), 0.0, {"length": 13.6, "width": 1.2, "color": Color(0.5, 0.07, 0.09), "border": Color(0.62, 0.48, 0.2)}])
	out.append(["altar_dais", Vector3(-7.8, 0, 0), 90.0])
	out.append(["altar", Vector3(-8.1, 0.24, 0), 90.0])
	out.append(on_wall(r, "stained_window", "left", 0.5))
	for x in [-3.6, 0.6, 4.8]:
		out.append(_back(r, "stained_window", x))
	for x in [-5.6, -1.5, 2.7]:
		out.append(["pillar", Vector3(x, 0, -3.7), 0.0])
	for i in 8:
		var x := -5.0 + 1.2 * i
		out.append(["pew", Vector3(x, 0, -2.0), -90.0, {"length": 2.4}])
		out.append(["pew", Vector3(x, 0, 2.0), -90.0, {"length": 2.4}])
	out.append(["lectern", Vector3(-6.3, 0.0, 1.7), 90.0])
	out.append(["candle_rack", Vector3(-6.4, 0, -2.6), 60.0])
	out.append(["font", Vector3(6.8, 0, 2.0), 0.0])
	return out


static func _layout_vestry(r: Dictionary) -> Array:
	var out: Array = []
	out.append(_back(r, "vestment_wardrobe", -1.6))
	out.append(["robe_rack", Vector3(1.5, 0, -2.4), 0.0])
	out.append(["vestry_table", Vector3(-0.2, 0, 0.4), 0.0])
	out.append(["chest", Vector3(3.0, 0, 0.9), -30.0])
	out.append(on_wall(r, "sconce", "left", 0.5))
	out.append(["candelabra", Vector3(-3.4, 0, 0.8), 0.0])
	return out


static func _layout_bell_tower(r: Dictionary) -> Array:
	var out: Array = []
	out.append(["bell_frame", Vector3(0.0, 0, -1.2), 0.0, {"lift": 2.4}])
	out.append(["bell_ropes", Vector3(-0.2, 0, 0.4), 0.0, {"count": 3, "radius": 0.8}])
	out.append(on_wall(r, "tower_ladder", "left", 0.5))
	out.append(["chest", Vector3(3.0, 0, 0.4), -40.0])
	out.append(_back(r, "sconce", 1.6))
	out.append(on_wall(r, "sconce", "left", 0.15))
	return out


func _run() -> void:
	await wait_frames(6)
	var dir := shot_path.get_base_dir()
	var shots := {}
	var ids: Array[String] = []
	if only == "":
		ids.assign(ROOM_IDS)
	elif ROOM_IDS.has(only):
		ids.assign([only])
	for id in ids:
		for light: String in HauntLook.LIGHTS:
			build_room(room(id), light)
			shots["%s_%s" % [id, light]] = await room_shot()
		await sheet("%s/%s.png" % [dir, id], "Church: the %s at the game camera (size 24, 1:1), limestone  -  docs/design/church-rooms.md" % ROOM_NAMES[id],
				[["", [["cold moonlight", shots["%s_moonlight" % id]], ["candle light", shots["%s_candle" % id]]]]])
	if only == "":
		var rows: Array = []
		for light: String in HauntLook.LIGHTS:
			var cells: Array = []
			for id in ROOM_IDS:
				var img: Image = (shots["%s_%s" % [id, light]] as Image).duplicate()
				img.resize(475, 430, Image.INTERPOLATE_LANCZOS)
				cells.append(["%s, %s" % [ROOM_NAMES[id], light], img])
			rows.append([light, cells])
		await sheet(shot_path, "Church rooms: moonlight above, candle light below; shrunk to 0.5 (the room sheets are 1:1)", rows)
		var cells2: Array = []
		for id in ROOM_IDS:
			cells2.append([ROOM_NAMES[id] + " (2x)", twice(shots["%s_candle" % id], Vector2i(300, 228))])
		await sheet("%s/sheet_2x.png" % dir, "The middle of each church room at 2x (nearest-neighbour), candle light", [["", cells2]])
	if only == "" or only == "props":
		var prows := await close_rows(room("vestry"), CLOSE_KINDS, "game", 6, {"bell_frame": {"lift": 0.0}})
		await sheet("%s/props.png" % dir, "Church props close up (game angle, DungeonLook's warm light; each zoomed to fit)", prows)
	finish()
