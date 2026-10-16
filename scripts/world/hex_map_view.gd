class_name HexMapView
extends Node3D
## Builds the visible terrain for a HexMap: pointy-top hex prisms merged into ONE
## ArrayMesh (one surface per material) under a single MeshInstance3D. No lights here.
##
## Readability aids: tops are tinted by height level, a thin dark hex outline marks tile
## borders, cliff sides have a band at every height level (count them to judge step /
## climb / blocked), STAIRS are drawn as real treads that follow HexMap.ground_level,
## and the "start" / "exit" cells get a glowing ring.

const FLOOR_DEPTH := -2          ## level where columns end (and where pit bottoms are)
const LH := Hex.LEVEL_HEIGHT

enum Surf { FLOOR_TOP, WALL_TOP, STAIRS_TOP, CLIFF, WALL_SIDE, STAIRS_SIDE, MARK }

## Filled by build(): triangles, vertices, surfaces, cells, stair_steps.
var stats: Dictionary = {}
var mesh_instance: MeshInstance3D

static var _tex_cache: Dictionary = {}

var _batches: Array = []
var _map: HexMap
var _stair_steps := 0


class Batch:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	## Convex polygon fan; pts must be clockwise when seen from the normal side.
	func poly(pts: Array, normal: Vector3, uv: Array, col: Color) -> void:
		var base := verts.size()
		for i in pts.size():
			verts.append(pts[i])
			normals.append(normal)
			uvs.append(uv[i])
			colors.append(col)
		for i in range(1, pts.size() - 1):
			indices.append(base)
			indices.append(base + i)
			indices.append(base + i + 1)


## Build (or rebuild) the terrain meshes for `map`.
func build(map: HexMap) -> void:
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	_map = map
	_stair_steps = 0
	_batches.clear()
	for _i in Surf.size():
		_batches.append(Batch.new())

	for c in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type == HexMap.Tile.STAIRS:
			_add_stairs(c, cell)
		else:
			_add_column(c, cell)
	_add_pit_bottoms()

	var mesh := ArrayMesh.new()
	var tris := 0
	var verts := 0
	for s in Surf.size():
		var b: Batch = _batches[s]
		if b.indices.is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b.verts
		arrays[Mesh.ARRAY_NORMAL] = b.normals
		arrays[Mesh.ARRAY_TEX_UV] = b.uvs
		arrays[Mesh.ARRAY_COLOR] = b.colors
		arrays[Mesh.ARRAY_INDEX] = b.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(s))
		tris += b.indices.size() / 3
		verts += b.verts.size()
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = mesh
	add_child(mesh_instance)
	stats = {
		"triangles": tris, "vertices": verts, "surfaces": mesh.get_surface_count(),
		"cells": map.cells.size(), "stair_steps": _stair_steps,
	}
	_batches.clear()


# ---------------------------------------------------------------------- materials / textures

static func get_texture(tex_name: String) -> Texture2D:
	if _tex_cache.has(tex_name):
		return _tex_cache[tex_name]
	var img: Image = null
	var path: String = ProtoTextures.DIR + tex_name + ".png"
	if ResourceLoader.exists(path):
		var res := load(path) as Texture2D
		if res != null:
			img = res.get_image()
	if img == null and FileAccess.file_exists(path):
		img = Image.load_from_file(path)  # not imported yet (dev only)
	if img == null or img.is_empty():
		img = ProtoTextures.make(tex_name)
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[tex_name] = tex
	return tex


func _material(surf: int) -> Material:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var tex := ""
	match surf:
		Surf.FLOOR_TOP: tex = "floor_top"
		Surf.WALL_TOP: tex = "wall_top"
		Surf.STAIRS_TOP: tex = "stairs_top"
		Surf.CLIFF: tex = "cliff_side"
		Surf.WALL_SIDE: tex = "wall_side"
		Surf.STAIRS_SIDE: tex = "stairs_side"
	if tex != "":
		m.albedo_texture = get_texture(tex)
	else:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Tone of a floor top for a given height level: cool grey-blue low, warming to sand/amber high.
static func level_tint(level: int) -> Color:
	var t := clampf(level / 10.0, 0.0, 1.0)
	var col := Color.from_hsv(lerpf(0.60, 0.07, t), lerpf(0.35, 0.70, t), lerpf(0.62, 0.92, t))
	# alternate brightness by level parity so neighbouring heights separate even when hues are close
	return col.darkened(0.10 if level % 2 != 0 else 0.0)


# ---------------------------------------------------------------------- geometry helpers

func _hi(cell: HexMap.Cell) -> int:
	return cell.level + (cell.stair_rise if cell.type == HexMap.Tile.STAIRS else 0)


## Edge j runs from corner j to corner j+1 and faces neighbor direction (6 - j) % 6.
static func _edge_dir(j: int) -> int:
	return (6 - j) % 6


## Vertical quad between two XZ points. `n` is the outward normal; winding is fixed up so it faces n.
func _side_quad(b: Batch, p0: Vector3, p1: Vector3, y_top: float, y_bot: float, n: Vector3, u0: float, u1: float, col: Color) -> void:
	var right := (-n).cross(Vector3.UP)
	var a := p0
	var c := p1
	var ua := u0
	var uc := u1
	if (c - a).dot(right) < 0.0:
		a = p1
		c = p0
		ua = u1
		uc = u0
	var vt := -y_top / LH
	var vb := -y_bot / LH
	b.poly([
		Vector3(a.x, y_top, a.z), Vector3(c.x, y_top, c.z),
		Vector3(c.x, y_bot, c.z), Vector3(a.x, y_bot, a.z),
	], n, [Vector2(ua, vt), Vector2(uc, vt), Vector2(uc, vb), Vector2(ua, vb)], col)


func _corner(center: Vector3, i: int) -> Vector3:
	return center + Hex.corner(i % 6)


func _top_poly(b: Batch, center: Vector3, y: float, col: Color) -> void:
	var pts: Array = []
	var uv: Array = []
	for i in 6:
		var p := _corner(center, i)
		pts.append(Vector3(p.x, y, p.z))
		uv.append(Vector2((p.x - center.x) * 0.5 + 0.5, (p.z - center.z) * 0.5 + 0.5))
	b.poly(pts, Vector3.UP, uv, col)


## Lowest ground height of a neighbor cell (what the side face has to reach down to).
func _bottom_level(nb: Vector2i) -> int:
	var cell: HexMap.Cell = _map.cells.get(nb)
	if cell == null:
		return FLOOR_DEPTH
	return cell.level


func _shade(level: int) -> Color:
	var v := lerpf(0.72, 1.0, clampf(level / 10.0, 0.0, 1.0))
	return Color(v, v, v)


# ---------------------------------------------------------------------- columns

func _add_column(c: Vector2i, cell: HexMap.Cell) -> void:
	var center := Hex.to_world(c)
	var is_wall := cell.type == HexMap.Tile.WALL
	var top_b: Batch = _batches[Surf.WALL_TOP if is_wall else Surf.FLOOR_TOP]
	var side_b: Batch = _batches[Surf.WALL_SIDE if is_wall else Surf.CLIFF]
	var y := cell.level * LH
	var col := Color(0.8, 0.8, 0.8) if is_wall else level_tint(cell.level)
	if not is_wall and cell.tag == "start":
		col = col.lerp(Color(0.35, 1.0, 0.5), 0.55)
	elif not is_wall and cell.tag == "exit":
		col = col.lerp(Color(1.0, 0.35, 0.95), 0.55)
	_top_poly(top_b, center, y, col)
	var side_col := Color(0.85, 0.85, 0.85) if is_wall else _shade(cell.level)
	for j in 6:
		var nb := c + Hex.DIRS[_edge_dir(j)]
		var bottom := _bottom_level(nb)
		if cell.level <= bottom:
			continue  # hidden by a taller-or-equal neighbor
		_side_quad(side_b, _corner(center, j), _corner(center, j + 1), y, bottom * LH,
			Hex.dir_vector(_edge_dir(j)), 0.0, 1.0, side_col)
	if not is_wall and (cell.tag == "start" or cell.tag == "exit"):
		var ring_col := Color(0.3, 1.0, 0.45) if cell.tag == "start" else Color(1.0, 0.3, 0.95)
		_add_ring(center, y + 0.03, ring_col)


## Glowing hex ring just above a cell top.
func _add_ring(center: Vector3, y: float, col: Color) -> void:
	var b: Batch = _batches[Surf.MARK]
	var outer := 0.84
	var inner := 0.62
	for i in 6:
		var o0 := Hex.corner(i) * outer
		var o1 := Hex.corner((i + 1) % 6) * outer
		var i0 := Hex.corner(i) * inner
		var i1 := Hex.corner((i + 1) % 6) * inner
		var pts := [
			center + Vector3(i0.x, y - center.y, i0.z), center + Vector3(o0.x, y - center.y, o0.z),
			center + Vector3(o1.x, y - center.y, o1.z), center + Vector3(i1.x, y - center.y, i1.z),
		]
		var uv := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		b.poly(pts, Vector3.UP, uv, col)


## Dark floors at the bottom of enclosed pits (void cells with plenty of neighbours).
func _add_pit_bottoms() -> void:
	var seen := {}
	for c in _map.cells:
		for d in Hex.DIRS:
			var v: Vector2i = c + d
			if seen.has(v) or _map.cells.has(v):
				continue
			seen[v] = true
			var present := 0
			for dd in Hex.DIRS:
				if _map.cells.has(v + dd):
					present += 1
			if present >= 4:
				_top_poly(_batches[Surf.FLOOR_TOP], Hex.to_world(v), FLOOR_DEPTH * LH, Color(0.16, 0.16, 0.2))


# ---------------------------------------------------------------------- stairs

## Stepped treads rising toward stair_dir; tread i sits at the ramp height of its middle.
func _add_stairs(c: Vector2i, cell: HexMap.Cell) -> void:
	var center := Hex.to_world(c)
	var dirv := Hex.dir_vector(cell.stair_dir)
	var side := Vector3(-dirv.z, 0.0, dirv.x)
	var n := clampi(cell.stair_rise * 2, 2, 8)
	var top_b: Batch = _batches[Surf.STAIRS_TOP]
	var side_b: Batch = _batches[Surf.STAIRS_SIDE]
	var span := 2.0 * Hex.INNER
	var corners: Array[Vector3] = []
	for i in 6:
		corners.append(Hex.corner(i))
	var prev_y := 0.0
	for s in n:
		var u0 := -Hex.INNER + span * s / n
		var u1 := -Hex.INNER + span * (s + 1) / n
		var y := (cell.level + (s + 0.5) * cell.stair_rise / n) * LH
		# clip the hexagon to the strip u0 <= u <= u1
		var poly: Array[Vector3] = _clip(corners, dirv, u0, u1)
		if poly.size() < 3:
			continue
		var pts: Array = []
		var uv: Array = []
		for p in poly:
			pts.append(center + Vector3(p.x, y - center.y, p.z))
			uv.append(Vector2(p.dot(side) * 0.8, (p.dot(dirv) - u0) / (u1 - u0)))
		top_b.poly(pts, Vector3.UP, uv, Color.WHITE)
		_stair_steps += 1
		# outer faces on the hex boundary
		for j in 6:
			var a := corners[j]
			var e := corners[(j + 1) % 6]
			var ua := a.dot(dirv)
			var ue := e.dot(dirv)
			var lo := 0.0
			var hi := 1.0
			if absf(ua - ue) < 0.00001:
				if ua < u0 - 0.0001 or ua > u1 + 0.0001:
					continue
			else:
				lo = clampf(inverse_lerp(ua, ue, u0), 0.0, 1.0)
				hi = clampf(inverse_lerp(ua, ue, u1), 0.0, 1.0)
				if lo > hi:
					var t := lo
					lo = hi
					hi = t
				if hi - lo < 0.0001:
					continue
			var p0 := center + a.lerp(e, lo)
			var p1 := center + a.lerp(e, hi)
			var bottom := _bottom_level(c + Hex.DIRS[_edge_dir(j)]) * LH
			if y <= bottom + 0.0001:
				continue
			_side_quad(side_b, p0, p1, y, bottom, Hex.dir_vector(_edge_dir(j)), 0.0, 1.0, Color.WHITE)
		# riser between this tread and the lower one behind it
		if s > 0:
			var cut: Array[Vector3] = []
			for p in poly:
				if absf(p.dot(dirv) - u0) < 0.0001:
					cut.append(p)
			if cut.size() >= 2:
				var lo_p := cut[0]
				var hi_p := cut[0]
				for p in cut:
					if p.dot(side) < lo_p.dot(side):
						lo_p = p
					if p.dot(side) > hi_p.dot(side):
						hi_p = p
				_side_quad(side_b, center + lo_p, center + hi_p, y, prev_y, -dirv, 0.0, 1.0, Color(0.9, 0.9, 0.9))
		prev_y = y


## Sutherland-Hodgman clip of a convex XZ polygon to u0 <= dot(p, axis) <= u1.
func _clip(poly: Array[Vector3], axis: Vector3, u0: float, u1: float) -> Array[Vector3]:
	var out := _clip_half(poly, axis, u0, true)
	return _clip_half(out, axis, u1, false)


func _clip_half(poly: Array[Vector3], axis: Vector3, limit: float, keep_above: bool) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var cnt := poly.size()
	for i in cnt:
		var a := poly[i]
		var b := poly[(i + 1) % cnt]
		var da := a.dot(axis) - limit
		var db := b.dot(axis) - limit
		if not keep_above:
			da = -da
			db = -db
		var a_in := da >= -0.00001
		var b_in := db >= -0.00001
		if a_in:
			out.append(a)
		if a_in != b_in:
			var t := da / (da - db)
			out.append(a.lerp(b, t))
	return out
