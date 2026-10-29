extends TestCase
## The church rooms test (docs/design/church-rooms.md, LOOK-DEV ONLY): every church prop (HauntProps / ChurchProps) builds
## headless inside its footprint with no text on it and wall pieces' backs on the wall line; the raised bell frame stands on
## its posts; the church's gym spawns put cosmetic props down; and the church lab's builders (the nave, the vestry, the bell
## tower in the limestone set, with their casts) run headless. (HauntLook's materials and lights: test_mansion_rooms.)

const LAB := "res://scripts/art/lowpoly/haunt/church_rooms_lab.gd"


func setup() -> void:
	HauntLook.reset()
	_check_props()
	await _check_gym()
	await _check_lab()
	finish()


func _check_props() -> void:
	var kinds := HauntProps.kinds("church")
	check(kinds.size() >= 10, "the church has its props (%d)" % kinds.size())
	for kind in kinds:
		var r := HauntProps.row(kind)
		var m := HauntProps.build(kind)
		var body := m.get_node_or_null("Body") as MeshInstance3D
		if not check(body != null and body.mesh != null and body.mesh.get_faces().size() > 0, "%s builds a body" % kind):
			m.free()
			continue
		check(m.find_children("*", "Label3D", true, false).is_empty(), "%s carries no text" % kind)
		var box := body.get_aabb()
		check(box.size.x <= float(r["w"]) + 0.3 and box.size.z <= float(r["d"]) + 0.3 and box.size.y <= float(r["h"]) + 0.3,
				"%s fits its footprint (%.2f x %.2f x %.2f)" % [kind, box.size.x, box.size.z, box.size.y])
		check(box.position.y >= -0.05, "%s stands on the floor" % kind)
		if bool(r.get("wall", false)):
			near(box.position.z, -float(r["d"]) * 0.5, 0.06, "%s: its back on the wall line" % kind)
		m.free()
	# the belfry: lifted onto its deck, the bell above head height, the posts down to the floor
	var bf := HauntProps.build("bell_frame", {"lift": 2.4})
	var bb := (bf.get_node("Body") as MeshInstance3D).get_aabb()
	near(bb.position.y, 0.0, 0.05, "the raised frame's posts stand on the floor")
	check(bb.end.y > 5.0, "the bell hangs above the ringers (top %.2f)" % bb.end.y)
	bf.free()
	var alt := HauntProps.build("altar")
	check(alt.get_node_or_null("Candles") != null, "the altar's candles")
	alt.free()


func _check_gym() -> void:
	var root := Node3D.new()
	add_child(root)
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 6):
		map.set_cell(c, 0).tag = "room:0"
	GameWorld.begin(map, root, 3)
	for kind: String in ["pew", "altar", "stained_window", "bell_frame"]:
		check(HauntProps.GYM_KINDS.has(kind), "%s is a gym prop" % kind)
		var e := GymSpawns.find("haunt:" + kind)
		if check(not e.is_empty(), "haunt:%s is a gym entry" % kind):
			eq(str(e["label"]), "church: " + str(HauntProps.row(kind)["label"]), "its label")
			var made := GymSpawns.spawn(e, Vector3.ZERO, 1, null, null)
			check(made.size() == 1 and made[0].is_in_group(HauntLook.PROPS_GROUP), "haunt:%s puts one prop down" % kind)
	root.queue_free()
	await frames(2)


func _check_lab() -> void:
	var lab: Node3D = load(LAB).new()
	add_child(lab)
	await frames(2)
	var script: GDScript = load(LAB)
	for id: String in script.get("ROOM_IDS"):
		var rm: Dictionary = script.call("room", id)
		lab.call("build_room", rm, "moonlight")
		var m: HexMap = lab.get("map")
		eq(FloorMaterials.floor_of(m.cells[Vector2i.ZERO].mat_id), HauntLook.F_LIMESTONE, "%s: limestone flags" % id)
		eq(FloorMaterials.wall_of(m.cells[Vector2i.ZERO].mat_id), HauntLook.W_LIMESTONE, "%s: limestone walls" % id)
		var placed: Array = lab.get("props")
		eq(placed.size(), (rm["props"] as Array).size(), "%s: every prop placed" % id)
		for p: Node3D in placed:
			check(m.cells.has(Hex.from_world(p.position)), "%s: %s stands inside the map" % [id, p.get_meta("haunt_kind")])
		var stage: Node3D = lab.get("stage")
		eq(stage.get_children().filter(func(n: Node) -> bool: return n is LowPolyModel).size(), 3, "%s: Wick, Rebar and a grunt" % id)
	lab.queue_free()
	await frames(2)
