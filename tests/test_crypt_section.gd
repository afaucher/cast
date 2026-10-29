extends TestCase
## The crypt section look test (docs/design/crypt-section.md, LOOK-DEV ONLY): CryptProps builds every piece in both
## material sets as plain cosmetic nodes (lit pieces carry their candle light); CryptLook's sets restyle only a terrain's
## own copy of the material tables; the gym's "crypt: <kind>" entries put a piece down (an ossuary onto a wall within
## reach); and the section lab builds headless in both sets: a room above 6 levels up, stairs down that connect it to the
## crypt, candle light over the burial chamber and none over the ossuary gallery.

const LAB := "res://scripts/art/lowpoly/crypt/crypt_section_lab.gd"


func setup() -> void:
	_check_props()
	_check_look()
	await _check_gym()
	await _check_lab()
	finish()


func _check_props() -> void:
	for set_name: String in CryptProps.SETS:
		for kind: String in CryptProps.KINDS:
			var n := CryptProps.build(kind, {"set": set_name})
			check(n.is_in_group(CryptProps.GROUP) and not (n is Actor), "%s/%s: a cosmetic piece in the crypt group" % [set_name, kind])
			var body := n.get_node_or_null("Body") as MeshInstance3D
			if check(body != null and body.mesh != null, "%s/%s: has its mesh" % [set_name, kind]):
				var tris := body.mesh.get_faces().size() / 3
				check(tris > 10 and tris < 9000, "%s/%s: a cheap blockout (%d tris)" % [set_name, kind, tris])
			var lit := n.find_children("CandleLight", "OmniLight3D", true, false)
			var wants_light := kind in ["candles", "candelabra", "altar"]
			eq(lit.size(), 1 if wants_light else 0, "%s/%s: a candle light only on the lit pieces" % [set_name, kind])
			n.free()
	var dark := CryptProps.build("candles", {"lit": false})
	eq(dark.find_children("CandleLight", "OmniLight3D", true, false).size(), 0, "unlit candles have no light")
	dark.free()
	# a shut gate's leaves stand in the doorway; an open one swings them toward +Z
	var shut := CryptProps.build("gate", {"open": 0.0})
	var open := CryptProps.build("gate", {"open": 1.0})
	var zs := _max_z(shut)
	var zo := _max_z(open)
	check(zs < 0.4 and zo > 1.0, "the gate swings open toward +Z (%.2f -> %.2f)" % [zs, zo])
	shut.free()
	open.free()


func _max_z(n: Node3D) -> float:
	var m := (n.get_node("Body") as MeshInstance3D).mesh
	var z := -INF
	for v in m.get_faces():
		z = maxf(z, v.z)
	return z


func _check_look() -> void:
	var before: PackedVector4Array = (FloorMaterials.table_arrays()["base"] as PackedVector4Array).duplicate()
	for set_name: String in CryptLook.SETS:
		var tb := CryptLook.tables(set_name)
		var base: PackedVector4Array = tb["base"]
		var want: Color = (CryptLook.look(set_name)["floor"] as Color).srgb_to_linear()
		near(base[FloorMaterials.F_FLAGSTONE].x, want.r, 0.0001, "%s: the crypt floor's colour" % set_name)
		eq(base[FloorMaterials.F_WOOD], before[FloorMaterials.F_WOOD], "%s: the mansion's wood is untouched" % set_name)
	eq(FloorMaterials.table_arrays()["base"], before, "FloorMaterials' own tables are untouched")
	check(CryptLook.above_mat("vault") != CryptLook.above_mat("chapel"), "a mansion above the vault, a church above the chapel")


func _check_gym() -> void:
	var root := Node3D.new()
	add_child(root)
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 8):
		if Hex.distance(c, Vector2i.ZERO) <= 6:
			map.set_cell(c, 0).tag = "room:0"
		else:
			map.set_cell(c, 3, HexMap.Tile.WALL)
	map.cut_walls()
	GameWorld.begin(map, root, 5)
	for kind: String in CryptProps.GYM_KINDS:
		var e := GymSpawns.find("haunt:crypt_" + kind)
		if not check(not e.is_empty(), "crypt: %s is a gym entry" % kind):
			continue
		eq(str(e["label"]), "crypt: " + kind, "its button label")
		var made := GymSpawns.spawn(e, Hex.to_world(Vector2i(0, 0)), 1, null, null)
		check(made.size() == 1 and made[0].is_in_group(CryptProps.GROUP), "crypt: %s spawns one crypt piece" % kind)
		check(made.size() == 1 and (made[0] as Node).get_parent() == GameWorld.root, "under the world")
	# by a wall, an ossuary backs onto the wall face
	var at := Hex.to_world(Vector2i(5, 0))
	var oss := GymSpawns.spawn(GymSpawns.find("haunt:crypt_ossuary"), at, 1, null, null)
	if check(oss.size() == 1, "an ossuary by the wall"):
		var o := oss[0] as Node3D
		var wall := map.nearest_wall(o.global_position + o.global_basis.z * 0.3, 1.0)
		check(not wall.is_empty() and float(wall["dist"]) < 0.4, "its back is on the wall face")
		var fwd := Vector2(o.global_basis.z.x, o.global_basis.z.z)
		check(not wall.is_empty() and fwd.dot(wall["normal"]) > 0.95, "facing out of the wall")
	await frames(2)
	root.queue_free()
	GameWorld.end()
	await frames(2)


func _check_lab() -> void:
	var lab: Node3D = load(LAB).new()
	add_child(lab)
	await frames(2)
	for set_name: String in CryptLook.SETS:
		lab.call("build", set_name)
		await frames(1)
		eq(str(lab.get("set_name")), set_name, "%s: built" % set_name)
		var m: HexMap = lab.get("map")
		var keys: Dictionary = lab.get("keys")
		var above: Vector2i = keys["above"]
		eq(m.cells[above].level, 6, "%s: the room above is 3.0 up" % set_name)
		eq(m.cells[above].mat_id, CryptLook.above_mat(set_name), "%s: in the room above's materials" % set_name)
		eq(m.cells[keys["entry"]].mat_id, CryptLook.crypt_room_mat(), "%s: the crypt in its own" % set_name)
		var stairs := 0
		for c: Vector2i in m.cells:
			if m.cells[c].type == HexMap.Tile.STAIRS:
				stairs += 1
		eq(stairs, 2, "%s: two flights of stairs" % set_name)
		var path := m.find_path(above, keys["end"])
		check(path.size() > 20, "%s: the stairs connect the room above to the end vault (%d steps)" % [set_name, path.size()])
		var lights: Array = lab.get("lights")
		var spots: Dictionary = lab.get("spots")
		check(_lit(lights, spots["bright"]) >= 2, "%s: candle light over the burial chamber" % set_name)
		eq(_lit(lights, spots["dark"]), 0, "%s: no light over the ossuary gallery" % set_name)
		var crypt_pieces := (lab.get("holder") as Node).get_children().filter(func(n: Node) -> bool: return n.is_in_group(CryptProps.GROUP))
		check(crypt_pieces.size() > 20, "%s: dressed (%d crypt pieces)" % [set_name, crypt_pieces.size()])
		var display: Array = lab.get("display")
		eq(display.size(), 6, "%s: the display room's six pieces" % set_name)
	lab.queue_free()
	GameWorld.end()
	await frames(2)


## How many of `lights` reach floor point `p` (within their range).
func _lit(lights: Array, p: Vector3) -> int:
	var n := 0
	for l: Light3D in lights:
		if l is OmniLight3D and l.global_position.distance_to(p) < (l as OmniLight3D).omni_range * 0.8:
			n += 1
	return n
