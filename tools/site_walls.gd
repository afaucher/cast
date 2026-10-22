extends Node3D
## Wall pieces on real floors (dev only): generates floors as the game spawns them (SiteBuilder + HexMapView) and, for every
## priced prop, hazard and decor piece placed against a wall, measures how far its back stands off the wall face (rays from
## the model's back-most points along -facing to the terrain) and, with --dir, renders it at the game angle (close).
##
##   godot --path . --resolution 800x800 -- --scene res://tools/site_walls.tscn --out <report.txt> [--dir <abs dir>]
##         [--arch prepper,...] [--seeds 7,38] [--floors 1,2,3] [--sewer] [--only kind,kind]

var camera: Camera3D


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out_path := _arg(a, "--out", "user://site_walls.txt")
	var dir := _arg(a, "--dir", "")
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	var archs := _arg(a, "--arch", ",".join(ClientArchetype.IDS)).split(",", false)
	var seeds := _arg(a, "--seeds", "7,38").split(",", false)
	var floors := _arg(a, "--floors", "1,2,3").split(",", false)
	var only := _arg(a, "--only", "").split(",", false)
	SewerCluster.force = a.has("--sewer")
	DungeonLook.apply(self)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 220.0
	add_child(camera)
	camera.make_current()
	var lines: PackedStringArray = []
	for arch in archs:
		for sd in seeds:
			for fl in floors:
				lines.append_array(await _site(arch, int(sd), int(fl), dir, only))
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("site_walls: %d lines -> %s" % [lines.size(), out_path])
	get_tree().quit()


func _site(arch: String, seed_value: int, floor_n: int, dir: String, only: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	var run := ContractRun.make(arch, seed_value, 0.5)
	var map := DungeonGen.for_run(run, floor_n)
	var plan := SiteBuilder.plan(map, run, floor_n, PricedProp.catalog(run.site_type))
	var root := Node3D.new()
	add_child(root)
	GameWorld.begin(map, root, seed_value)
	var site := SiteBuilder.spawn(map, run, plan)
	var view := HexMapView.new()
	root.add_child(view)
	view.build(map)
	await get_tree().process_frame
	var terrain := ZFightCheck.TriSet.new()
	terrain.add_node(view, terrain.add_item("terrain", true), view.global_transform)
	var things: Array = []
	for n in site.props + site.hazards:
		var pp := n as PricedProp
		if pp != null and str(PricedProp.placement(pp.kind)["place"]) == "wall":
			things.append([pp.kind, pp, (PricedProp.placement(pp.kind)["foot"] as Vector2)])
	for n in site.decor:
		var dp := n as DecorProp
		if dp != null and str(RoomThemeDefs.decor(dp.kind).get("place", "")) == "wall":
			things.append([dp.kind, dp, Vector2(float(RoomThemeDefs.decor(dp.kind)["w"]), float(RoomThemeDefs.decor(dp.kind)["d"]))])
	for t: Array in things:
		var kind: String = t[0]
		if not only.is_empty() and not only.has(kind):
			continue
		var node: Node3D = t[1]
		var m := _gap(node, terrain)
		var tag := "%s#%d/f%d %s @(%.1f,%.1f)" % [arch, seed_value, floor_n, kind, node.global_position.x, node.global_position.z]
		out.append("%s %-60s nearest %.2f  median %.2f  far %.2f  (%d probes, %d miss)" % ["SUSPECT" if m[0] > 0.12 else "ok", tag,
				m[0], m[1], m[2], m[3], m[4]])
		if dir != "":
			var c := node.global_position + Vector3(0, 0.8, 0)
			_aim(c, 45.0, -56.0, 7.0)
			for i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var base := "%s/%s_%s_%d_f%d_%d" % [dir, kind, arch, seed_value, floor_n, int(node.global_position.x * 10)]
			get_viewport().get_texture().get_image().save_png(base + "_game.png")
			_aim(c, node.global_rotation_degrees.y + 90.0, -12.0, 3.5)
			for i in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(base + "_side.png")
			_aim(c, node.global_rotation_degrees.y, -88.0, 4.0)
			for i in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(base + "_top.png")
	GameWorld.end()
	root.queue_free()
	await get_tree().process_frame
	return out


## [nearest, median, farthest, probes, misses]: from the model's back-most points (per 0.2 m lateral x 0.25 m height cell,
## its smallest local z), the distance along -facing to the first terrain face.
func _gap(node: Node3D, terrain: ZFightCheck.TriSet) -> Array:
	var ts := ZFightCheck.TriSet.new()
	var model: Node3D = node.get("model") if node.get("model") != null else node
	ts.add_node(model, ts.add_item("m"), Transform3D.IDENTITY)
	var inv_root := node.global_transform
	var to_model := node.global_transform.affine_inverse() * model.global_transform
	var cells := {}
	for i in ts.count():
		if ts.flags[i] & ZFightCheck.F_LABEL:
			continue
		for q: Vector3 in [ts.pa[i], ts.pb[i], ts.pc[i]]:
			var l := to_model * q
			if l.y < 0.05:
				continue
			var k := Vector2i(floori(l.x / 0.2), floori(l.y / 0.25))
			if not cells.has(k) or l.z < (cells[k] as Vector3).z:
				cells[k] = l
	var back := Vector3(0, 0, -1)
	var d := (inv_root.basis * back).normalized()
	var dists: Array[float] = []
	var miss := 0
	for k in cells:
		var o: Vector3 = inv_root * (cells[k] as Vector3)
		var best := INF
		for i in terrain.count():
			var lo := ZFightCheck.TriSet._min3(terrain.pa[i], terrain.pb[i], terrain.pc[i])
			var hi := ZFightCheck.TriSet._max3(terrain.pa[i], terrain.pb[i], terrain.pc[i])
			if o.x < lo.x - 2.0 or o.x > hi.x + 2.0 or o.z < lo.z - 2.0 or o.z > hi.z + 2.0 or o.y < lo.y - 0.01 or o.y > hi.y + 0.01:
				continue
			var hit: Variant = Geometry3D.ray_intersects_triangle(o, d, terrain.pa[i], terrain.pb[i], terrain.pc[i])
			if hit != null:
				best = minf(best, ((hit as Vector3) - o).length())
		if best == INF or best > 2.0:
			miss += 1
		else:
			dists.append(best)
	dists.sort()
	if dists.is_empty():
		return [INF, INF, INF, cells.size(), miss]
	return [dists[0], dists[dists.size() / 2], dists[-1], cells.size(), miss]


func _aim(focus: Vector3, yaw: float, pitch: float, size: float) -> void:
	camera.size = size
	var dir := Vector3(sin(deg_to_rad(yaw)) * cos(deg_to_rad(-pitch)), sin(deg_to_rad(-pitch)), cos(deg_to_rad(yaw)) * cos(deg_to_rad(-pitch)))
	camera.position = focus + dir * 60.0
	camera.look_at(focus, Vector3.UP)


static func _arg(a: PackedStringArray, flag: String, def: String) -> String:
	var i := a.find(flag)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else def
