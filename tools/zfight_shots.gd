extends Node3D
## Renders a model from the z-fighting registry (ZFightModels) at the game camera angle and shows where it FLICKERS:
## the same frame is drawn again with the camera moved by fractions of a pixel, and every pixel whose colour jumps
## is painted red over a dimmed copy (a z-fight flips between two colours as the rasteriser's rounding changes; flat
## surfaces keep their colour; edges give thin lines). Pixels that also change when frame 0 is drawn again are animation
## (a shader's TIME, particles) and are painted blue instead. Run windowed (it needs the GPU):
##
##   godot --path . --resolution 1920x1080 -- --scene res://tools/zfight_shots.tscn --entry van/closed --out <dir>/van.png
##         [--at x,y,z] [--normal x,y,z] [--size 6] [--pitch -56] [--yaw 45] [--frames 8] [--no-shadow]
##         [--fov 42 --dist 12]           a perspective camera (the menu's) instead of the game's orthographic one
##   ... --calib --out <dir>/calib.png      the depth-precision strip: faces 0 .. 1 mm apart, at sizes 9, 24 and 36
##   ... --menu --out <dir>/menu.png        the menu garage through its own camera
##
## --at: the point to centre (model space, default the model's middle); --normal: the face to look at (the camera turns
## so it looks at that face; up-facing or none: the game's yaw 45). Writes <out> and <out>_flicker.png and prints
## how many pixels flicker near the centre.

const GAME_PITCH := -56.0
const CALIB_GAPS_MM: Array[float] = [0.0, 0.01, 0.02, 0.05, 0.1, 0.25, 0.5, 1.0]

var camera: Camera3D
var out_path := ""
var frames := 8
var focus := Vector3.ZERO


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_path = _arg(a, "--out", "user://zfight_shot.png")
	frames = int(_arg(a, "--frames", "8"))
	if a.has("--menu"):
		await _menu_shot()
		get_tree().quit()
		return
	_floor()
	DungeonLook.apply(self)
	if a.has("--no-shadow"):
		for l in find_children("*", "DirectionalLight3D", true, false):
			(l as DirectionalLight3D).shadow_enabled = false
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 220.0
	add_child(camera)
	camera.make_current()
	if a.has("--calib"):
		await _calib()
		get_tree().quit()
		return
	var entry := _arg(a, "--entry", "van/closed")
	var node := _build(entry)
	if node == null:
		push_error("no registry entry " + entry)
		get_tree().quit(1)
		return
	add_child(node)
	focus = _vec(_arg(a, "--at", ""), _middle(node))
	var normal := _vec(_arg(a, "--normal", ""), Vector3.UP)
	var yaw := float(_arg(a, "--yaw", "nan"))
	if is_nan(yaw):
		var h := Vector2(normal.x, normal.z)
		yaw = rad_to_deg(atan2(h.x, h.y)) if h.length() > 0.3 else 45.0
	var fov := float(_arg(a, "--fov", "0"))
	if fov > 0.0:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = fov
		camera.near = 0.2
		camera.far = 120.0
	_aim(yaw, float(_arg(a, "--pitch", str(GAME_PITCH))), float(_arg(a, "--size", "6")), float(_arg(a, "--dist", "60")))
	await _shoot(out_path)
	get_tree().quit()


func _build(entry: String) -> Node3D:
	for e in ZFightModels.models():
		if String(e["name"]) == entry:
			return (e["make"] as Callable).call()
	for e in ZFightModels.stacks():
		if String(e["name"]) == entry:
			var holder := Node3D.new()
			for it: Array in (e["make"] as Callable).call():
				holder.add_child(it[1])
			return holder
	return null


## A patch of flat hex floor at level 0 (the real HexMapView look) under the model.
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


func _aim(yaw: float, pitch: float, size: float, dist: float = 60.0) -> void:
	camera.size = size
	var dir := Vector3(sin(deg_to_rad(yaw)) * cos(deg_to_rad(-pitch)), sin(deg_to_rad(-pitch)), cos(deg_to_rad(yaw)) * cos(deg_to_rad(-pitch)))
	camera.position = focus + dir * dist
	camera.look_at(focus, Vector3.UP)


## Frame 0 to `path`; the flicker map to <path>_flicker.png. Returns the flickering pixels (not on an edge) inside each
## region's screen rectangle (a region: the corners of a face; none: 40 px around the focus).
func _shoot(path: String, regions: Array = []) -> Array[int]:
	for i in 8:
		await get_tree().process_frame
	var base := await _grab(Vector2.ZERO)
	base.save_png(path)
	var w := base.get_width()
	var h := base.get_height()
	var px := camera.size / float(h)
	var bd := base.get_data()
	var stride := bd.size() / (w * h)
	var flick := PackedByteArray()
	flick.resize(w * h)
	for k in range(1, frames):
		# fractions of a pixel, never whole ones (a whole-pixel move repeats the same rounding)
		var off := Vector2(fmod(0.37 * float(k), 1.0) - 0.5, fmod(0.61 * float(k), 1.0) - 0.5) * px * 0.6
		var od := (await _grab(off)).get_data()
		for i in w * h:
			var j := i * stride
			var d := maxi(absi(bd[j] - od[j]), maxi(absi(bd[j + 1] - od[j + 1]), absi(bd[j + 2] - od[j + 2])))
			if d > flick[i]:
				flick[i] = d
	# the control: frame 0 again; what changed there is animation (a shader's TIME, particles), not a z-fight
	var cd := (await _grab(Vector2.ZERO)).get_data()
	var anim := PackedByteArray()
	anim.resize(w * h)
	for i in w * h:
		var j := i * stride
		if maxi(absi(bd[j] - cd[j]), maxi(absi(bd[j + 1] - cd[j + 1]), absi(bd[j + 2] - cd[j + 2]))) > 30:
			anim[i] = 1
			flick[i] = 0
	var outd := PackedByteArray()
	outd.resize(w * h * 3)
	for i in w * h:
		var j := i * stride
		if anim[i] == 1:
			outd[i * 3] = 40
			outd[i * 3 + 1] = 90
			outd[i * 3 + 2] = 255
		elif flick[i] > 30:
			outd[i * 3] = 255
			outd[i * 3 + 1] = 25
			outd[i * 3 + 2] = 25
		else:
			outd[i * 3] = bd[j] * 35 / 100
			outd[i * 3 + 1] = bd[j + 1] * 35 / 100
			outd[i * 3 + 2] = bd[j + 2] * 35 / 100
	Image.create_from_data(w, h, false, Image.FORMAT_RGB8, outd).save_png(path.get_basename() + "_flicker.png")
	var counts: Array[int] = []
	var spots: Array = regions if not regions.is_empty() else [[focus]]
	for reg: Array in spots:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		# unproject_position works in the viewport's visible rect (the stretch base size), the image is the window
		var k := float(w) / get_viewport().get_visible_rect().size.x
		for p: Vector3 in reg:
			var sp := camera.unproject_position(p) * k
			lo = Vector2(minf(lo.x, sp.x), minf(lo.y, sp.y))
			hi = Vector2(maxf(hi.x, sp.x), maxf(hi.y, sp.y))
		if reg.size() == 1:
			lo -= Vector2(40, 40)
			hi += Vector2(40, 40)
		else:
			lo += Vector2(2, 2)
			hi -= Vector2(2, 2)
		var n := 0
		for y in range(maxi(0, int(lo.y)), mini(h, int(hi.y))):
			for x in range(maxi(0, int(lo.x)), mini(w, int(hi.x))):
				if flick[y * w + x] > 30 and _edge_free(base, x, y):
					n += 1
		counts.append(n)
	print("shot ", path, " size ", camera.size, " flickering px (away from edges): ", counts)
	return counts


## Not on a colour edge of frame 0 (edges move with any sub-pixel shift; a z-fight flips inside a flat area).
func _edge_free(img: Image, x: int, y: int) -> bool:
	var c := img.get_pixel(x, y)
	for o: Vector2i in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2)]:
		var q := Vector2i(x, y) + o
		if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height():
			return false
		if _diff(c, img.get_pixel(q.x, q.y)) > 0.08:
			return false
	return true


func _grab(off: Vector2) -> Image:
	camera.h_offset = off.x
	camera.v_offset = off.y
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


static func _diff(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))


## A base whose top sits 0 .. 1 mm (CALIB_GAPS_MM) above a plate of another colour, in three orientations: flat (seen from 56 degrees above), a wall
## facing the camera's heading, and a wall turned 60 degrees (seen at about 74 degrees off its normal). The rig stands
## 40 units out on both axes, as far from the origin as a generated floor's rooms.
func _calib() -> void:
	var labels := []
	var regions := []
	var origin := Vector3(40, 0.6, 40)
	for row in 3:
		for i in CALIB_GAPS_MM.size():
			var g := CALIB_GAPS_MM[i] / 1000.0
			var s := LowPoly.Soup.new(3 + i, 0.0)
			s.merge(LowPoly.box(Vector3(0.5, 0.3, 0.5), Color(0.25, 0.3, 0.6)), LowPoly.at(Vector3(0, 0.15, 0)))
			s.merge(LowPoly.box(Vector3(0.36, 0.05, 0.36), Color(0.95, 0.75, 0.2)), LowPoly.at(Vector3(0, 0.3 - g - 0.025, 0)))
			var mi := MeshInstance3D.new()
			mi.mesh = s.to_mesh()
			mi.material_override = PropModels.material()
			var holder := Node3D.new()
			holder.add_child(mi)
			mi.position = Vector3(0, -0.3, 0)         # the base's top face at the holder's origin, normal +Y
			if row >= 1:
				holder.rotation_degrees = Vector3(90, 60.0 if row == 2 else 0.0, 0)
			holder.position = origin + Vector3(float(i) * 0.7 - 2.45, 0, float(row) * 1.2 - 1.2)
			add_child(holder)
			var reg := []
			for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				reg.append(holder.transform * Vector3(c.x * 0.17, 0, c.y * 0.17))
			regions.append(reg)
			labels.append("%s %.2fmm" % [["flat", "wall", "turned"][row], CALIB_GAPS_MM[i]])
	focus = origin
	for sz: float in [9.0, 24.0, 36.0]:
		_aim(0.0, GAME_PITCH, sz)
		var counts := await _shoot(out_path.get_basename() + "_size%d.png" % int(sz), regions)
		for k in labels.size():
			print("  calib size %d  %-16s flicker px %d" % [int(sz), labels[k], counts[k]])


func _menu_shot() -> void:
	var bd: Node3D = ZFightModels.MenuBackdropScript.new()
	bd.set("mood", "dawn")
	add_child(bd)
	camera = bd.get("camera")
	for i in 30:
		await get_tree().process_frame
	bd.set_process(false)
	focus = Vector3(1.4, 1.0, -1.2)
	await _shoot(out_path)


static func _middle(n: Node3D) -> Vector3:
	var bb := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := m.global_transform * m.mesh.get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	return bb.get_center()


static func _vec(s: String, fallback: Vector3) -> Vector3:
	var p := s.split(",")
	if p.size() != 3:
		return fallback
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


static func _arg(a: PackedStringArray, flag: String, def: String = "") -> String:
	var i := a.find(flag)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else def
