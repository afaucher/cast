extends TestCase
## The ectoplasm look test (docs/design/ectoplasm-look.md, LOOK-DEV ONLY): EctoplasmLook's builders make plain cosmetic
## nodes (a puddle, a wall drip) for every variant, see-through and with no ink outline (so it never reads as today's goo),
## in the ghosts' colour; Damp's wash thins them away; the gym's "ecto: <variant>" entries put a puddle down (and a drip on
## a wall within reach); and the look lab's builders (its two rooms, their spots, a staged cell) run headless.

const LAB := "res://scripts/art/lowpoly/ghost/ectoplasm_look_lab.gd"

var root: Node3D


func setup() -> void:
	GhostLook.reset()
	EctoplasmLook.clock = -1.0
	_check_builders()
	await _check_gym_spawns()
	await _check_lab()
	GhostLook.reset()
	finish()


func _check_builders() -> void:
	check(EctoplasmLook.VARIANTS.size() >= 2 and EctoplasmLook.VARIANTS.size() <= 3, "two or three variants")
	for v: String in EctoplasmLook.VARIANTS:
		var p := EctoplasmLook.puddle(v, 0.9, 5)
		check(p.is_in_group(EctoplasmLook.GROUP), "%s: a puddle is in the ectoplasm group" % v)
		check(not (p is Actor), "%s: a cosmetic node" % v)
		var mats := EctoplasmLook.materials_of(p)
		check(not mats.is_empty(), "%s: it has its sheet" % v)
		var sheets := 0
		for m in mats:
			check(m.next_pass == null, "%s: no ink outline" % v)
			if m.get_shader_parameter("a_mid") != null:
				sheets += 1
				check(float(m.get_shader_parameter("a_mid")) < 0.65, "%s: see-through in the middle" % v)
				eq(m.get_shader_parameter("ecto"), GhostLook.COLOUR["pale blue"], "%s: in the ghosts' colour" % v)
		check(sheets >= 1, "%s: a sheet material" % v)
		var aabb := _bounds(p)
		check(aabb.size.x > 1.4 and aabb.size.x < 3.2 and aabb.size.y < 0.25 + 1.6, "%s: about the radius across (%s)" % [v, aabb])
		var d := EctoplasmLook.drip(v, 2.2, 5)
		check(d.is_in_group(EctoplasmLook.GROUP), "%s: a drip is in the group" % v)
		var da := _bounds(d, true)
		check(da.end.y > 1.6 and da.end.y < 2.3, "%s: the drip runs up the wall (top %.2f)" % [v, da.end.y])
		check(da.position.z > -0.01, "%s: nothing behind the wall face (%.3f)" % [v, da.position.z])
		EctoplasmLook.set_wash(d, 0.7)
		for m in EctoplasmLook.materials_of(d):
			near(float(m.get_shader_parameter("wash")), 0.7, 0.0001, "%s: the wash reaches every piece" % v)
		p.free()
		d.free()
	GhostLook.colour = "ecto green"
	var g := EctoplasmLook.puddle("film", 1.0, 2)
	eq(EctoplasmLook.materials_of(g)[0].get_shader_parameter("ecto"), GhostLook.COLOUR["ecto green"], "ecto green follows the ghosts")
	g.free()
	GhostLook.reset()


## The world-space bounds of every Sheet mesh under `n` (wisps left out: they billboard).
func _bounds(n: Node3D, sheets_only: bool = true) -> AABB:
	var out := AABB()
	var first := true
	for c in n.get_children():
		if c is MeshInstance3D and (not sheets_only or c.name.begins_with("Sheet")):
			var a := (c as MeshInstance3D).transform * (c as MeshInstance3D).mesh.get_aabb()
			out = a if first else out.merge(a)
			first = false
	return out


func _check_gym_spawns() -> void:
	root = Node3D.new()
	add_child(root)
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 5):
		var d := Hex.distance(c, Vector2i.ZERO)
		if d <= 3:
			map.set_cell(c, 0).tag = "room:0"
		else:
			map.set_cell(c, 6, HexMap.Tile.WALL)
	map.cut_walls()
	GameWorld.begin(map, root, 3)
	for v: String in EctoplasmLook.VARIANTS:
		var e := GymSpawns.find("crypt:ecto_" + v)
		if not check(not e.is_empty(), "crypt:ecto_%s is a gym entry" % v):
			continue
		eq(str(e["label"]), "ecto: " + v, "its button label")
		var made := GymSpawns.spawn(e, Hex.to_world(Vector2i(0, 2)), 1, null, null)
		var ecto := made.filter(func(x: Node) -> bool: return x.is_in_group(EctoplasmLook.GROUP))
		check(ecto.size() >= 1, "ecto: %s puts ectoplasm down (%d nodes)" % [v, ecto.size()])
		check(ecto.size() >= 2, "... and a drip on the wall within reach")
		for x: Node in ecto:
			check(x.get_parent() == GameWorld.root, "under the world")
			eq(str(x.get_meta("variant", "")), v, "of its variant")
	await frames(2)
	root.queue_free()
	await frames(2)


## The lab's builders, headless: its two rooms, each a bright and a dark spot by a camera-facing wall, a staged cell.
func _check_lab() -> void:
	var lab: Node3D = load(LAB).new()
	add_child(lab)
	await frames(2)
	var spots: Dictionary = lab.get("spots")
	var m: HexMap = lab.get("map")
	for room: String in ["wood", "stone"]:
		for light: String in ["bright", "dark"]:
			var k := room + "_" + light
			if not check(spots.has(k), "the lab has its %s spot" % k):
				continue
			var at: Vector3 = spots[k]["at"]
			var c := Hex.from_world(at)
			check(m.cells.has(c) and m.cells[c].type != HexMap.Tile.WALL, "%s: on floor" % k)
			check((spots[k]["normal"] as Vector3).dot(Vector3(0.7071, 0, 0.7071)) > 0.85, "%s: its wall faces the camera" % k)
		var b: Vector3 = spots[room + "_bright"]["at"]
		var dk: Vector3 = spots[room + "_dark"]["at"]
		check(b.distance_to(dk) > 6.0, "%s: the dark spot is out of the bright one's pool (%.1f)" % [room, b.distance_to(dk)])
		var floor_id := FloorMaterials.floor_of(m.cells[Hex.from_world(b)].mat_id)
		eq(floor_id, FloorMaterials.F_WOOD if room == "wood" else FloorMaterials.F_CORR_STONE, "%s: its floor" % room)
	for v: String in ["film", "goo"]:
		lab.call("_stage", v, spots["wood_bright"], 0.3)
		var holder: Node3D = lab.get("holder")
		var ecto := holder.get_children().filter(func(n: Node) -> bool: return n.is_in_group(EctoplasmLook.GROUP))
		eq(ecto.size(), 0 if v == "goo" else 2, "%s: puddle and drip staged" % v)
		eq(holder.get_child_count(), 3 + (1 if v == "goo" else 2), "%s: with Wick, a grunt and Rebar" % v)
	lab.queue_free()
	await frames(2)
