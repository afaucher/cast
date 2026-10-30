extends TestCase
## The haunted mansion rooms test (docs/design/mansion-rooms.md, LOOK-DEV ONLY): every mansion prop (HauntProps /
## MansionProps) builds headless inside its footprint, with no text on it, wall pieces with their backs on the wall line,
## candles that HauntLook's lights snuff and relight; HauntLook's lab-only materials patch a copy of the terrain shader and
## table (the game's own are untouched) and dress a built HexMapView; the gym's haunt spawns put cosmetic props down and its
## Haunt light row relights the scene; and the mansion lab's builders (each room, its cast, both material sets) run headless.

const LAB := "res://scripts/art/lowpoly/haunt/mansion_rooms_lab.gd"

var root: Node3D


func setup() -> void:
	HauntLook.reset()
	_check_props("mansion")
	_check_materials()
	await _check_light()
	await _check_gym()
	await _check_lab()
	HauntLook.reset()
	finish()


## Every kind of `set_name`: a Body with triangles, inside its row's footprint, no Label3D, a wall piece's back on z = -d / 2.
func _check_props(set_name: String) -> void:
	var kinds := HauntProps.kinds(set_name)
	check(kinds.size() >= 10, "%s has its props (%d)" % [set_name, kinds.size()])
	for kind in kinds:
		var r := HauntProps.row(kind)
		var m := HauntProps.build(kind, {"seed": 3})
		var body := m.get_node_or_null("Body") as MeshInstance3D
		if not check(body != null and body.mesh != null and body.mesh.get_faces().size() > 0, "%s builds a body" % kind):
			m.free()
			continue
		check(m.is_in_group(HauntLook.PROPS_GROUP), "%s is a haunt prop" % kind)
		check(not _has_text(m), "%s carries no text" % kind)
		var box := body.get_aabb()
		var w := float(r["w"]) + 0.3
		var d := float(r["d"]) + 0.3
		var h := float(r["h"]) + 0.3
		check(box.size.x <= w and box.size.z <= d and box.size.y <= h,
				"%s fits its footprint (%.2f x %.2f x %.2f in %.2f x %.2f x %.2f)" % [kind, box.size.x, box.size.z, box.size.y, w, d, h])
		check(box.position.y >= -0.05, "%s stands on the floor (%.2f)" % [kind, box.position.y])
		if bool(r.get("wall", false)):
			near(box.position.z, -float(r["d"]) * 0.5, 0.06, "%s: its back on the wall line" % kind)
		m.free()
	# the portraits: every picture builds; candle props carry their lights
	for v in 5:
		var p := HauntProps.build("portrait", {"v": v, "big": v % 2 == 0})
		check(p.get_node_or_null("Body") != null, "portrait %d builds" % v)
		p.free()


func _has_text(n: Node) -> bool:
	if n is Label3D or (n is MeshInstance3D and (n as MeshInstance3D).mesh is TextMesh):
		return true
	for c in n.get_children():
		if _has_text(c):
			return true
	return false


func _check_materials() -> void:
	var code := HauntLook.shader_code()
	check(code.contains("if (pat == 9)") and code.contains("pat == 24 || pat == 25") and code.contains("pat == 26"),
			"the test's patterns are in its shader copy")
	check(code.contains("is_wall && pat == 26"), "... and its wall caps")
	check(not HexMapView.MATERIAL_SHADER.contains("pat == 24"), "the game's terrain shader is untouched")
	var t := HauntLook.tables()
	var game := FloorMaterials.table_arrays()
	for slot: int in HauntLook.ROWS:
		check(slot >= 22 and slot < FloorMaterials.TABLE_SIZE, "slot %d is a free one" % slot)
		eq(int((t["base"] as PackedVector4Array)[slot].w + 0.5), int(HauntLook.ROWS[slot]["pat"]), "slot %d's pattern" % slot)
		eq((game["base"] as PackedVector4Array)[slot], Vector4.ZERO, "the game's table has nothing in slot %d" % slot)
	eq((t["base"] as PackedVector4Array)[FloorMaterials.F_WOOD], (game["base"] as PackedVector4Array)[FloorMaterials.F_WOOD], "the game's rows are kept")
	for set_name: String in HauntLook.SET_NAMES:
		var st: Dictionary = HauntLook.SETS[set_name]
		check(HauntLook.ROWS.has(int(st["floor"])) and HauntLook.ROWS.has(HauntLook.wall_slot(int(st["wall"]))), "set %s has its rows" % set_name)
	check(HauntLook.ROWS.has(HauntLook.wall_slot(HauntLook.W_GLAZING)) and HauntLook.ROWS.has(HauntLook.F_TERRACOTTA), "the conservatory's rows")


## The lights on a DungeonLook scene with a candle prop in it: moonlight snuffs the candles and turns the pools off, candle
## light lights them, game puts DungeonLook's key back.
func _check_light() -> void:
	root = Node3D.new()
	add_child(root)
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 4):
		map.set_cell(c, 0).tag = "room:0"
	DungeonLook.apply(root, map)
	var cb := HauntProps.build("candelabra")
	root.add_child(cb)
	var candles := cb.get_node_or_null("Candles") as Node3D
	if check(candles != null and candles.is_in_group(HauntLook.CANDLES_GROUP), "the candelabra carries candles"):
		check(candles.get_children().any(func(n: Node) -> bool: return n is OmniLight3D), "... with a light")
	var dl := root.find_child("Downlights", true, false) as Node3D
	var key := root.find_child("KeyLight", true, false) as DirectionalLight3D
	check(HauntLook.apply_light(root, "moonlight"), "moonlight applies")
	check(candles != null and not candles.visible, "moonlight: the candles are out")
	check(dl != null and not dl.visible, "moonlight: the warm pools are off")
	check(key.light_color.b > key.light_color.r, "moonlight: a cold key light")
	check(HauntLook.apply_light(root, "candle"), "candle light applies")
	check(candles != null and candles.visible, "candle light: the candles are lit")
	check(key.light_energy < 0.5, "candle light: the key light is low")
	check(HauntLook.apply_light(root, "game"), "game applies")
	near(key.light_energy, 0.9, 0.001, "game: DungeonLook's key light back")
	check(dl.visible, "game: the pools back")
	check(not HauntLook.apply_light(root, "noon"), "an unknown light is refused")
	# a prop built while the gym is in moonlight starts with its candles out
	HauntLook.light = "moonlight"
	var late := HauntProps.build("sconce")
	check(not (late.get_node("Candles") as Node3D).visible, "a prop put down in moonlight has its candles out")
	late.free()
	HauntLook.reset()
	root.queue_free()
	await frames(2)


func _check_gym() -> void:
	var rows := {}
	for row: Array in GymDev.experiments():
		rows[str(row[0])] = row
	if check(rows.has("haunt_light"), "the panel has a Haunt light picker"):
		eq(str(rows["haunt_light"][1]), "Haunt light", "its label")
		eq(str(rows["haunt_light"][2]), str(["game", "moonlight", "candle"]), "its lights")
	check(GymSpawns.GROUPS.has("haunt"), "the haunt group is listed")
	root = Node3D.new()
	add_child(root)
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 6):
		map.set_cell(c, 0).tag = "room:0"
	for c in Hex.range_cells(Vector2i.ZERO, 7):
		if Hex.distance(c, Vector2i.ZERO) == 7:
			map.set_cell(c, 3, HexMap.Tile.WALL)
	map.cut_walls()
	GameWorld.begin(map, root, 3)
	for kind: String in HauntProps.GYM_KINDS:
		var e := GymSpawns.find("rooms:" + kind)
		if not check(not e.is_empty(), "rooms:%s is a gym entry" % kind):
			continue
		eq(str(e["skip"]), "", "%s has a button" % kind)
		var made := GymSpawns.spawn(e, Hex.to_world(Vector2i(1, 1)), 1, null, null)
		if check(made.size() == 1 and made[0].is_in_group(HauntLook.PROPS_GROUP), "rooms:%s puts one prop down" % kind):
			check(not (made[0] is Actor) and made[0].get_parent() == GameWorld.root, "%s: a cosmetic node under the world" % kind)
	# a wall piece put down near a wall backs onto it
	var near_wall := Hex.to_world(Vector2i(5, 0))
	var pf := GymSpawns.spawn(GymSpawns.find("rooms:portrait"), near_wall, 1, null, null)
	if check(pf.size() == 1, "a portrait near the wall"):
		var w := map.nearest_wall((pf[0] as Node3D).global_position, 3.0)
		if check(not w.is_empty(), "... a wall within reach"):
			near(float(w["dist"]), float(HauntProps.row("portrait")["d"]) * 0.5 + 0.04, 0.05, "... its back on the wall")
	check(HauntLook.pick("candle", root), "the Haunt light pick")
	eq(HauntLook.light, "candle", "remembered")
	check(not HauntLook.pick("noon", root), "an unknown pick is refused")
	HauntLook.reset()
	root.queue_free()
	await frames(2)


## The lab's builders, headless: every room in both sets builds its map with the test's materials, its props and its cast.
func _check_lab() -> void:
	var lab: Node3D = load(LAB).new()
	add_child(lab)
	await frames(2)
	var script: GDScript = load(LAB)
	for id: String in script.get("ROOM_IDS"):
		for set_name: String in HauntLook.SET_NAMES:
			var rm: Dictionary = script.call("room", id, set_name)
			lab.call("build_room", rm, "candle")
			var m: HexMap = lab.get("map")
			var floor_id := FloorMaterials.floor_of(m.cells[Vector2i.ZERO].mat_id)
			var want := HauntLook.F_TERRACOTTA if id == "conservatory" else int(HauntLook.SETS[set_name]["floor"])
			eq(floor_id, want, "%s (%s): its floor" % [id, set_name])
			var placed: Array = lab.get("props")
			eq(placed.size(), (rm["props"] as Array).size(), "%s: every prop placed" % id)
			for p: Node3D in placed:
				var c := Hex.from_world(p.position)
				check(m.cells.has(c), "%s: %s stands inside the map" % [id, p.get_meta("haunt_kind")])
			var stage: Node3D = lab.get("stage")
			var cast := stage.get_children().filter(func(n: Node) -> bool: return n is LowPolyModel)
			eq(cast.size(), 3, "%s: Wick, Rebar and a grunt" % id)
			var mesh := (lab.get("terrain") as HexMapView).mesh_instance.mesh
			var dressed := 0
			for i in mesh.get_surface_count():
				var sm := mesh.surface_get_material(i) as ShaderMaterial
				if sm != null and sm.shader == HauntLook.terrain_shader():
					dressed += 1
			check(dressed >= 2, "%s: the floor and walls wear the test's materials (%d)" % [id, dressed])
	lab.queue_free()
	await frames(2)
