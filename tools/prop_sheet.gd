extends Node3D
## Prop look sheet (dev only): renders models of the z-fight registry (ZFightModels) and the sewer kit one at a time on a
## patch of real hex floor, a wall-placed row (DECOR / PricedProp "place": "wall") with a wall slab where its pose puts the
## wall (the footprint's back + ThemeGeo.GAP), from the game angle and from the side. One PNG per model and view in --dir.
## Run windowed (it needs the GPU):
##
##   godot --path . --resolution 900x900 -- --scene res://tools/prop_sheet.tscn --dir <abs dir> [--only a,b,c] [--views game,side,front]

const SewerProps := preload("res://scripts/art/lowpoly/props/sewer_props.gd")

var camera: Camera3D
var wall: MeshInstance3D


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var dir := _arg(a, "--dir", "user://prop_sheet")
	DirAccess.make_dir_recursive_absolute(dir)
	var only := _arg(a, "--only", "").split(",", false)
	var views := _arg(a, "--views", "game,side").split(",", false)
	_floor()
	DungeonLook.apply(self)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 220.0
	add_child(camera)
	camera.make_current()
	wall = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(8.0, 3.2, 0.3)
	wall.mesh = bm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.42, 0.4, 0.38)
	wall.material_override = wm
	add_child(wall)
	var entries := ZFightModels.models()
	for k: String in ["outfall", "pipe_bundle", "grate_bridge", "sluice", "springer", "ladder_wall", "duck", "bars", "pump",
			"junction_box", "tool_cart", "rat_swarm"]:
		entries.append({"name": "sewer/" + k, "make": SewerProps.build.bind(k, {})})
	for e in entries:
		var nm := String(e["name"])
		var want := only.is_empty()
		for o in only:
			want = want or nm.contains(o)
		if not want:
			continue
		var n: Node3D = (e["make"] as Callable).call()
		add_child(n)
		var back := _wall_back(nm)
		wall.visible = not is_nan(back)
		if wall.visible:
			wall.position = Vector3(0, 1.6, back - ThemeGeo.GAP - 0.15)
		var bb := _bounds(n)
		var focus := bb.get_center()
		var size := maxf(bb.size.length() * 1.15, 1.2)
		for v in views:
			match v:
				"game": _aim(focus, 45.0, -56.0, size)
				"side": _aim(focus, 90.0, -10.0, size)
				"front": _aim(focus, 0.0, -15.0, size)
				"back": _aim(focus, 180.0, -20.0, size)
				"top": _aim(focus, 0.0, -89.0, size)
			for i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/%s__%s.png" % [dir, nm.replace("/", "~"), v])
		remove_child(n)
		n.queue_free()
	print("prop_sheet done -> ", dir)
	get_tree().quit()


## The footprint's back (local z) of a wall-placed row, NAN for anything else.
func _wall_back(nm: String) -> float:
	if nm.begins_with("decor/"):
		var row := RoomThemeDefs.decor(nm.trim_prefix("decor/"))
		if str(row.get("place", "")) == "wall":
			return -float(row["d"]) * 0.5
	elif nm.begins_with("prop/"):
		var row := PricedProp.placement(nm.trim_prefix("prop/"))
		if str(row.get("place", "")) == "wall":
			return -(row["foot"] as Vector2).y * 0.5
	return NAN


func _bounds(n: Node3D) -> AABB:
	var bb := AABB()
	var first := true
	for mi: VisualInstance3D in n.find_children("*", "VisualInstance3D", true, false):
		if not mi.is_visible_in_tree():
			continue
		var b := mi.global_transform * mi.get_aabb()
		if b.size.length() > 30.0:
			continue
		bb = b if first else bb.merge(b)
		first = false
	return bb if not first else AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))


func _floor() -> void:
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 7):
		var cell := HexMap.Cell.new()
		cell.level = 0
		cell.type = HexMap.Tile.FLOOR
		map.cells[c] = cell
	var view := HexMapView.new()
	add_child(view)
	view.build(map)


func _aim(focus: Vector3, yaw: float, pitch: float, size: float) -> void:
	camera.size = size
	var dir := Vector3(sin(deg_to_rad(yaw)) * cos(deg_to_rad(-pitch)), sin(deg_to_rad(-pitch)), cos(deg_to_rad(yaw)) * cos(deg_to_rad(-pitch)))
	camera.position = focus + dir * 60.0
	camera.look_at(focus, Vector3.UP if absf(pitch) < 85.0 else Vector3(0, 0, -1))


static func _arg(a: PackedStringArray, flag: String, def: String) -> String:
	var i := a.find(flag)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else def
