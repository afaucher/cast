class_name HexMapView
extends Node3D
## Builds the visible terrain for a HexMap: pointy-top hex prisms merged into ONE
## ArrayMesh (one surface per material) under a single MeshInstance3D. No lights here
## (see DungeonLook).
##
## Look: dark slate columns with a small bevel, and a thin gap around every tile through
## which an emissive amber SEAM surface (a full-size hex sunk just below each top) glows
## like light leaking up through the cracks. Raised floor cells inside rooms (platforms,
## ledges, ziggurats, pillars) read as wooden CRATES, stairs as warm wood planks. Cliff
## sides keep a subtle band at every height level (count them to judge step / climb /
## blocked) plus a faint glow down the column corners; pits get an amber glow at the
## bottom. The "start" / "exit" cells get cyan-green / magenta glowing seams + a ring.

const FLOOR_DEPTH := -2          ## level where columns end (and where pit bottoms are)
const LH := Hex.LEVEL_HEIGHT
const TOP_SCALE := 0.90          ## flat top, as a fraction of the full hex
const BEVEL_SCALE := 0.955       ## outer edge of the bevel; the rest of the hex is the glowing gap
const BEVEL_DROP := 0.035        ## how far the bevel falls below the top
const SEAM_DROP := 0.07          ## depth of the glowing seam surface below the top

const SEAM_COLOR := Color(1.0, 0.40, 0.07)
const START_COLOR := Color(0.2, 1.0, 0.72)
const EXIT_COLOR := Color(1.0, 0.28, 1.0)

enum Surf { FLOOR_TOP, WALL_TOP, CRATE_TOP, STAIRS_TOP, CLIFF, WALL_SIDE, CRATE_SIDE, STAIRS_SIDE, SEAM }

## Filled by build(): triangles, vertices, surfaces, cells, stair_steps, crates.
var stats: Dictionary = {}
var mesh_instance: MeshInstance3D
## How loud the glowing seams are (read by build()). 1 = the game's look. Menu backdrops turn it down because
## bright seams under a UI are noisy: `seam_gain` scales every seam / rim glow, and seams closer to the camera than
## `seam_near_range` (view-space units, 0 = off) are further scaled by `seam_near_gain` (fading back to full at the
## range), so the foreground floor stays calm while the far floor keeps its glow.
var seam_gain := 1.0
var seam_near_gain := 1.0
var seam_near_range := 0.0

static var _tex_cache: Dictionary = {}
static var _terrain_shader: Shader
static var _glow_shader: Shader

var _batches: Array = []
var _map: HexMap
var _stair_steps := 0
var _crates: Dictionary = {}     ## Vector2i -> true for floor cells drawn as crates
var _pits: Dictionary = {}       ## void cells that are enclosed pits


class Batch:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()   ## x = extra glow (0..1) read by the terrain shader
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	## Convex polygon fan; pts must be clockwise when seen from the normal side.
	func poly(pts: Array, normal: Vector3, uv: Array, col: Color) -> void:
		var base := verts.size()
		for i in pts.size():
			verts.append(pts[i])
			normals.append(normal)
			uvs.append(uv[i])
			uv2s.append(Vector2.ZERO)
			colors.append(col)
		_fan(base, pts.size())

	## Same, with a color and a glow value per vertex.
	func polyv(pts: Array, normal: Vector3, uv: Array, cols: Array, glows: Array) -> void:
		var base := verts.size()
		for i in pts.size():
			verts.append(pts[i])
			normals.append(normal)
			uvs.append(uv[i])
			uv2s.append(Vector2(float(glows[i]), 0.0))
			colors.append(cols[i])
		_fan(base, pts.size())

	func _fan(base: int, count: int) -> void:
		for i in range(1, count - 1):
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
	_crates = _find_crates(map)
	_pits = _find_pits(map)
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
		arrays[Mesh.ARRAY_TEX_UV2] = b.uv2s
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
		"cells": map.cells.size(), "stair_steps": _stair_steps, "crates": _crates.size(),
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
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[tex_name] = tex
	return tex


## Lit, textured surface. Emission = amber * max(texture alpha, UV2.x): alpha is the glow
## mask baked into the texture, UV2.x is a per-vertex glow (bevels, pit walls).
const TERRAIN_SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 glow_color : source_color = vec3(1.0, 0.5, 0.12);
uniform float glow_energy = 1.8;
uniform float rough = 0.8;
uniform float spec = 0.2;
uniform float near_gain = 1.0;
uniform float near_range = 0.0;
void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ROUGHNESS = rough;
	SPECULAR = spec;
	float k = near_range > 0.0 ? mix(near_gain, 1.0, smoothstep(near_range * 0.5, near_range, length(VERTEX))) : 1.0;
	EMISSION = glow_color * glow_energy * k * max(t.a, UV2.x);
}
"""

## Unlit emissive surface for the seams / rings / pit floors (vertex color * energy, HDR so it blooms).
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform float energy = 1.9;
uniform float near_gain = 1.0;
uniform float near_range = 0.0;
void fragment() {
	float k = near_range > 0.0 ? mix(near_gain, 1.0, smoothstep(near_range * 0.5, near_range, length(VERTEX))) : 1.0;
	ALBEDO = COLOR.rgb * energy * k;
}
"""


func _material(surf: int) -> Material:
	var m := ShaderMaterial.new()
	if surf == Surf.SEAM:
		if _glow_shader == null:
			_glow_shader = Shader.new()
			_glow_shader.code = GLOW_SHADER
		m.shader = _glow_shader
		m.set_shader_parameter("energy", 1.9 * seam_gain)
		m.set_shader_parameter("near_gain", seam_near_gain)
		m.set_shader_parameter("near_range", seam_near_range)
		return m
	if _terrain_shader == null:
		_terrain_shader = Shader.new()
		_terrain_shader.code = TERRAIN_SHADER
	m.shader = _terrain_shader
	var tex := ""
	var glow := 1.1
	var rough := 0.78
	var spec := 0.22
	match surf:
		Surf.FLOOR_TOP: tex = "floor_top"
		Surf.WALL_TOP: tex = "wall_top"
		Surf.CRATE_TOP:
			tex = "crate_top"
			rough = 0.9
			spec = 0.08
		Surf.STAIRS_TOP:
			tex = "stairs_top"
			rough = 0.85
			spec = 0.1
		Surf.CLIFF: tex = "cliff_side"
		Surf.WALL_SIDE: tex = "wall_side"
		Surf.CRATE_SIDE:
			tex = "crate_side"
			rough = 0.9
			spec = 0.08
		Surf.STAIRS_SIDE:
			tex = "stairs_side"
			rough = 0.9
			spec = 0.08
	m.set_shader_parameter("tex", get_texture(tex))
	m.set_shader_parameter("glow_energy", glow * seam_gain)
	m.set_shader_parameter("near_gain", seam_near_gain)
	m.set_shader_parameter("near_range", seam_near_range)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("spec", spec)
	return m


## Brightness of a slate floor top for a given height level (cool grey-blue). Higher levels
## are a touch lighter and odd levels a touch darker so neighbouring heights separate.
static func level_tint(level: int) -> Color:
	var v := lerpf(0.82, 1.08, clampf(level / 8.0, 0.0, 1.0))
	if level % 2 != 0:
		v *= 0.94
	return Color(v * 0.97, v, v * 1.04)


# ---------------------------------------------------------------------- classification

## Raised floor cells inside rooms are drawn as wooden crates: reachable ones above the room's
## base level (its most common level), and every untagged floor cell (DungeonGen only tags
## cells reachable without climbing, so untagged floor = ledges / pillars / tall tiers).
## Corridors, stairs, start and exit stay slate.
static func _find_crates(map: HexMap) -> Dictionary:
	var counts := {}   ## room tag -> { level -> count }
	for c in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type != HexMap.Tile.FLOOR or not cell.tag.begins_with("room:"):
			continue
		if not counts.has(cell.tag):
			counts[cell.tag] = {}
		var per: Dictionary = counts[cell.tag]
		per[cell.level] = int(per.get(cell.level, 0)) + 1
	var base := {}
	for tag in counts:
		var per: Dictionary = counts[tag]
		var best_n := -1
		var best_l := 0
		for lv in per:
			var n: int = per[lv]
			if n > best_n or (n == best_n and int(lv) < best_l):
				best_n = n
				best_l = int(lv)
		base[tag] = best_l
	var out := {}
	for c in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type != HexMap.Tile.FLOOR:
			continue
		if cell.tag == "" or (base.has(cell.tag) and cell.level > int(base[cell.tag])):
			out[c] = true
	return out


## Void cells surrounded mostly by terrain: pits (as opposed to the open outside).
static func _find_pits(map: HexMap) -> Dictionary:
	var seen := {}
	var pits := {}
	for c in map.cells:
		for d in Hex.DIRS:
			var v: Vector2i = c + d
			if seen.has(v) or map.cells.has(v):
				continue
			seen[v] = true
			var present := 0
			for dd in Hex.DIRS:
				if map.cells.has(v + dd):
					present += 1
			if present >= 4:
				pits[v] = true
	return pits


static func _hash2(c: Vector2i) -> float:
	var h: int = (c.x * 73856093) ^ (c.y * 19349663)
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float((h ^ (h >> 16)) & 0xffff) / 65535.0


static func _scaled(col: Color, k: float) -> Color:
	return Color(minf(col.r * k, 1.0), minf(col.g * k, 1.0), minf(col.b * k, 1.0), 1.0)


# ---------------------------------------------------------------------- geometry helpers

func _hi(cell: HexMap.Cell) -> int:
	return cell.level + (cell.stair_rise if cell.type == HexMap.Tile.STAIRS else 0)


## Edge j runs from corner j to corner j+1 and faces neighbor direction (6 - j) % 6.
static func _edge_dir(j: int) -> int:
	return (6 - j) % 6


## Vertical quad between two XZ points. `n` is the outward normal; winding is fixed up so it faces n.
## `drop` is the SEAM_DROP the caller already subtracted (keeps the level banding aligned);
## g_top / g_bot are per-vertex glow values.
func _side_quad(b: Batch, p0: Vector3, p1: Vector3, y_top: float, y_bot: float, n: Vector3, u0: float, u1: float, col: Color,
		drop: float = 0.0, g_top: float = 0.0, g_bot: float = 0.0) -> void:
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
	var vt := -(y_top + drop) / LH
	var vb := -(y_bot + drop) / LH
	var pts: Array = [
		Vector3(a.x, y_top, a.z), Vector3(c.x, y_top, c.z),
		Vector3(c.x, y_bot, c.z), Vector3(a.x, y_bot, a.z),
	]
	var uv: Array = [Vector2(ua, vt), Vector2(uc, vt), Vector2(uc, vb), Vector2(ua, vb)]
	if g_top == 0.0 and g_bot == 0.0:
		b.poly(pts, n, uv, col)
	else:
		b.polyv(pts, n, uv, [col, col, col, col], [g_top, g_top, g_bot, g_bot])


func _corner(center: Vector3, i: int) -> Vector3:
	return center + Hex.corner(i % 6)


## Point on the hex ring of the given scale, at height y.
func _ring_pt(center: Vector3, i: int, scale: float, y: float) -> Vector3:
	var o := Hex.corner(i % 6)
	return Vector3(center.x + o.x * scale, y, center.z + o.z * scale)


func _uv_for(center: Vector3, p: Vector3, world_uv: bool) -> Vector2:
	if world_uv:
		return Vector2(p.x, p.z) / ProtoTextures.SLATE_PERIOD
	return Vector2((p.x - center.x) * 0.5 + 0.5, (p.z - center.z) * 0.5 + 0.5)


## A tile top: flat hex plus a sloped bevel ring. `rim` / `rim_glow` colour and light the outer
## edge of the bevel (warm light spilling from the seam below).
func _top_tile(top_b: Batch, center: Vector3, y: float, col: Color, rim: Color, rim_glow: float, world_uv: bool) -> void:
	var pts: Array = []
	var uv: Array = []
	for i in 6:
		var p := _ring_pt(center, i, TOP_SCALE, y)
		pts.append(p)
		uv.append(_uv_for(center, p, world_uv))
	top_b.poly(pts, Vector3.UP, uv, col)
	for j in 6:
		var ia := _ring_pt(center, j, TOP_SCALE, y)
		var ib := _ring_pt(center, j + 1, TOP_SCALE, y)
		var oa := _ring_pt(center, j, BEVEL_SCALE, y - BEVEL_DROP)
		var ob := _ring_pt(center, j + 1, BEVEL_SCALE, y - BEVEL_DROP)
		var out_n := Hex.dir_vector(_edge_dir(j))
		var n := (out_n * 0.75 + Vector3.UP * 0.66).normalized()
		var quad: Array = [ia, oa, ob, ib]
		var quv: Array = [_uv_for(center, ia, world_uv), _uv_for(center, oa, world_uv), _uv_for(center, ob, world_uv), _uv_for(center, ib, world_uv)]
		top_b.polyv(quad, n, quv, [col, rim, rim, col], [0.0, rim_glow, rim_glow, 0.0])


## Full-size emissive hex sunk just below the tile top: what shows through the gap.
func _seam_hex(center: Vector3, y: float, col: Color) -> void:
	var pts: Array = []
	var uv: Array = []
	for i in 6:
		pts.append(_ring_pt(center, i, 1.0, y - SEAM_DROP))
		uv.append(Vector2.ZERO)
	var b: Batch = _batches[Surf.SEAM]
	b.poly(pts, Vector3.UP, uv, col)


# ---------------------------------------------------------------------- columns

## Lowest ground height of a neighbor cell (what the side face has to reach down to).
func _bottom_level(nb: Vector2i) -> int:
	var cell: HexMap.Cell = _map.cells.get(nb)
	if cell == null:
		return FLOOR_DEPTH
	return cell.level


func _shade(level: int) -> Color:
	var v := lerpf(0.80, 1.0, clampf(level / 10.0, 0.0, 1.0))
	return Color(v, v, v)


func _add_column(c: Vector2i, cell: HexMap.Cell) -> void:
	var center := Hex.to_world(c)
	var is_wall := cell.type == HexMap.Tile.WALL
	var is_crate := _crates.has(c)
	var top_b: Batch = _batches[Surf.WALL_TOP if is_wall else (Surf.CRATE_TOP if is_crate else Surf.FLOOR_TOP)]
	var side_b: Batch = _batches[Surf.WALL_SIDE if is_wall else (Surf.CRATE_SIDE if is_crate else Surf.CLIFF)]
	var y := cell.level * LH
	var hv := _hash2(c)
	var col: Color
	var rim: Color
	var rim_glow := 0.0
	var seam: Color = _scaled(SEAM_COLOR, 0.8 + 0.3 * hv)
	if is_wall:
		col = _scaled(Color(0.95, 0.97, 1.0), 0.9 + 0.2 * hv)
		rim = _scaled(col, 0.7)
		rim_glow = 0.12
		seam = _scaled(seam, 0.20)
	elif is_crate:
		col = _scaled(Color.WHITE, 0.9 + 0.12 * hv)
		rim = _scaled(Color(0.55, 0.32, 0.15), 0.8)
		rim_glow = 0.10
		seam = _scaled(seam, 0.45)
	else:
		col = _scaled(level_tint(cell.level), 0.93 + 0.12 * hv)
		rim = col.lerp(Color(0.95, 0.52, 0.22), 0.45)
		rim_glow = 0.5
		if cell.tag == "start":
			col = col.lerp(Color(0.4, 1.0, 0.8), 0.14)
			rim = col.lerp(START_COLOR, 0.55)
			seam = START_COLOR
		elif cell.tag == "exit":
			col = col.lerp(Color(1.0, 0.5, 1.0), 0.14)
			rim = col.lerp(EXIT_COLOR, 0.55)
			seam = EXIT_COLOR
	_top_tile(top_b, center, y, col, rim, rim_glow, not is_crate)
	_seam_hex(center, y, seam)

	var side_col := _shade(cell.level) if not is_crate else _scaled(Color.WHITE, 0.95)
	if is_wall:
		side_col = Color(0.9, 0.9, 0.9)
	for j in 6:
		var nb := c + Hex.DIRS[_edge_dir(j)]
		var bottom := _bottom_level(nb)
		if cell.level <= bottom:
			continue  # hidden by a taller-or-equal neighbor
		var n := Hex.dir_vector(_edge_dir(j))
		var y_top := y - SEAM_DROP
		var y_bot := bottom * LH - SEAM_DROP
		var p0 := _corner(center, j)
		var p1 := _corner(center, j + 1)
		if _pits.has(nb):
			# warm glow climbing the last stretch of the pit wall
			var gh := minf(0.9, y_top - y_bot)
			_side_quad(side_b, p0, p1, y_top, y_bot + gh, n, 0.0, 1.0, side_col, SEAM_DROP)
			_side_quad(side_b, p0, p1, y_bot + gh, y_bot, n, 0.0, 1.0, side_col, SEAM_DROP, 0.0, 0.6)
		else:
			_side_quad(side_b, p0, p1, y_top, y_bot, n, 0.0, 1.0, side_col, SEAM_DROP)
	if not is_wall and (cell.tag == "start" or cell.tag == "exit"):
		_add_ring(center, y + 0.02, START_COLOR if cell.tag == "start" else EXIT_COLOR)


## Thin glowing hex ring just above a cell top (start / exit marker).
func _add_ring(center: Vector3, y: float, col: Color) -> void:
	var b: Batch = _batches[Surf.SEAM]
	var outer := 0.76
	var inner := 0.66
	for i in 6:
		var pts: Array = [
			_ring_pt(center, i, inner, y), _ring_pt(center, i, outer, y),
			_ring_pt(center, i + 1, outer, y), _ring_pt(center, i + 1, inner, y),
		]
		var uv: Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		b.poly(pts, Vector3.UP, uv, col)


## Dark floors at the bottom of enclosed pits, edged with a dim amber glow.
func _add_pit_bottoms() -> void:
	var b: Batch = _batches[Surf.SEAM]
	var dark := Color(0.02, 0.012, 0.01)
	var glow := _scaled(SEAM_COLOR, 0.4)
	var zero4: Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	for v in _pits:
		var center := Hex.to_world(v)
		var y := FLOOR_DEPTH * LH - SEAM_DROP
		var pts: Array = []
		var uv: Array = []
		for i in 6:
			pts.append(_ring_pt(center, i, 1.0, y))
			uv.append(Vector2.ZERO)
		b.poly(pts, Vector3.UP, uv, dark)
		for j in 6:
			var ring: Array = [
				_ring_pt(center, j, 0.5, y + 0.005), _ring_pt(center, j, 1.0, y + 0.005),
				_ring_pt(center, j + 1, 1.0, y + 0.005), _ring_pt(center, j + 1, 0.5, y + 0.005),
			]
			b.polyv(ring, Vector3.UP, zero4, [dark, glow, glow, dark], [0.0, 0.0, 0.0, 0.0])


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
			_side_quad(side_b, p0, p1, y, bottom - SEAM_DROP, Hex.dir_vector(_edge_dir(j)), 0.0, 1.0, Color.WHITE)
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
