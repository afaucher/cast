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
## bottom. The "exit" cell gets magenta glowing seams + a ring, only on a map without an elevator (the elevator's sill
## strip and car light mark its landing). The "start" cell is unmarked (the van or the elevator is the start).
##
## Midpoint walls (HexMap.cut_walls): a cut cell is drawn in two parts. Its floor kites are a floor tile (the
## same inset top, bevel and seam, but only along its hex edges: the floor runs flush into the wall line) and its
## wall kites are raised to the cell's wall_top with a capped top. The wall FACE is a flat quad on the line from
## the cell's center to the edge midpoint, so neighbouring cut cells join into one straight face from center to
## center.
##
## POOLS (HexMap pool cells, PoolGeo; docs/design/pool-options.md "Built"): the INSET drawing mode. A ring cell is drawn
## like a cut cell turned downward: its deck kites are a floor tile running flush into the rim line, its pool kites are
## the tiled pool floor at pool_level (no bevel, no seam glow), and on each rim line (center -> edge midpoint) a tiled
## LINER face runs from the deck down to the pool floor, facing the water. Basin cells are pool floor only. Water,
## coping, foam line, ladder, gantry and a moat's fins are PoolView's (a child node). A moat (a ring of water round an
## island) needs nothing more: its cells are ring cells like any pool's, the island's corners being 4-kite pool runs.

const FLOOR_DEPTH := -2          ## level where columns end (and where pit bottoms are)
const LH := Hex.LEVEL_HEIGHT
const TOP_SCALE := 0.90          ## flat top, as a fraction of the full hex
const BEVEL_SCALE := 0.955       ## outer edge of the bevel; the rest of the hex is the glowing gap
const BEVEL_DROP := 0.035        ## how far the bevel falls below the top
const SEAM_DROP := 0.07          ## depth of the glowing seam surface below the top

const SEAM_COLOR := Color(1.0, 0.40, 0.07)
const EXIT_COLOR := Color(1.0, 0.28, 1.0)

enum Surf { FLOOR_TOP, WALL_TOP, CRATE_TOP, STAIRS_TOP, CLIFF, WALL_SIDE, CRATE_SIDE, STAIRS_SIDE, SEAM, POOL, CHANNEL }
## The material name of the CHANNEL surface: a sewer body's pool kites (a HexMap.pools record whose look is "sewer_*"), drawn
## like the pools but on their own surface, so SewerView restyles a generated floor's sewer without touching its pools.
const CHANNEL_MATERIAL := "sewer_channel"

## Filled by build(): triangles, vertices, surfaces, cells, stair_steps, crates.
var stats: Dictionary = {}
var mesh_instance: MeshInstance3D
var pool_view: PoolView = null   ## water, coping, foam, ladders, gantries of the map's pools (null without any)
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
static var _material_shader: Shader
static var _pool_shader: Shader

var _batches: Array = []
var _map: HexMap
var _stair_steps := 0
var _crates: Dictionary = {}     ## Vector2i -> true for floor cells drawn as crates
var _pits: Dictionary = {}       ## void cells that are enclosed pits
var _use_mats := false           ## some cell has a Cell.mat_id (FloorMaterials): floor / wall surfaces use the material shader
var _pool_looks: Dictionary = {}  ## pool cell -> its pool's look (filled on first use per build)
## A lava cave's rock (HexMap.cave "rock"): never drawn as crates (raised rock is rock), its cliffs tinted with the cave's
## look (HexMap.cave "cliff", LavaPlanner).
var _cave_rock: Dictionary = {}
var _cave_cliff := Color.WHITE


class Batch:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()   ## x = extra glow (0..1), y = material table index (FloorMaterials) read by the terrain shader
	var mat := 0.0                     ## the material index every vertex added next gets (set per cell by the caller)
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	## Polygon fan from pts[0]: the polygon must be convex or star-shaped about pts[0] (every other vertex visible
	## from it); pts must be clockwise when seen from the normal side.
	func poly(pts: Array, normal: Vector3, uv: Array, col: Color) -> void:
		var base := verts.size()
		for i in pts.size():
			verts.append(pts[i])
			normals.append(normal)
			uvs.append(uv[i])
			uv2s.append(Vector2(0.0, mat))
			colors.append(col)
		_fan(base, pts.size())

	## Same, with a color and a glow value per vertex.
	func polyv(pts: Array, normal: Vector3, uv: Array, cols: Array, glows: Array) -> void:
		var base := verts.size()
		for i in pts.size():
			verts.append(pts[i])
			normals.append(normal)
			uvs.append(uv[i])
			uv2s.append(Vector2(float(glows[i]), mat))
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
	_pool_looks.clear()
	pool_view = null
	_cave_rock.clear()
	for c: Vector2i in (map.cave.get("rock", []) as Array):
		_cave_rock[c] = true
	_cave_cliff = map.cave.get("cliff", Color(0.42, 0.36, 0.33)) as Color
	_crates = _find_crates(map)
	for c: Vector2i in _cave_rock:
		_crates.erase(c)
	_pits = _find_pits(map)
	_use_mats = false
	for c in map.cells:
		if (map.cells[c] as HexMap.Cell).mat_id != 0:
			_use_mats = true
			break
	for _i in Surf.size():
		_batches.append(Batch.new())

	for c in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		var wm: int = 0 if cell.type == HexMap.Tile.WALL else cell.wall_mask
		if cell.pool_mask != 0 and cell.type != HexMap.Tile.WALL:
			_add_pool_cell(c, cell)
			continue
		if wm == HexMap.ALL_KITES:
			_add_wall_part(c, cell, wm)       # a cut cell walled in completely
		elif wm != 0:
			if cell.type == HexMap.Tile.STAIRS:
				_add_stairs(c, cell, HexMap.ALL_KITES & ~wm)
			else:
				_add_floor_part(c, cell, HexMap.ALL_KITES & ~wm)
			_add_wall_part(c, cell, wm)
		elif cell.type == HexMap.Tile.STAIRS:
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
	if not map.pools.is_empty():
		pool_view = PoolView.new()
		pool_view.name = "Pools"
		add_child(pool_view)
		pool_view.build(map)
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

## The terrain shader with MATERIALS (FloorMaterials): UV2.y is the material table index of the cell the vertex belongs to
## (0 = the classic slate texture above). A material is a procedural pattern (concrete slabs, flagstone, carpet, tile,
## wood boards, marble, rubber, diamond plate; formwork concrete, ashlar blocks and panelling on walls) evaluated from
## the world position: floors in the XZ plane, walls along the face (the tangent comes from the flat face's normal) and
## height. Pattern id and colours come from uniform arrays; the pattern branch is uniform across a face, so it is cheap.
## Hex tops keep the per-vertex COLOR (height tint, per-hex variation), so hex heights and the hex grid stay readable.
const MATERIAL_SHADER := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 glow_color : source_color = vec3(1.0, 0.5, 0.12);
uniform float glow_energy = 1.8;
uniform float rough = 0.8;
uniform float spec = 0.2;
uniform float near_gain = 1.0;
uniform float near_range = 0.0;
uniform bool is_wall = false;
uniform vec4 m_base[32];
uniform vec4 m_alt[32];
uniform vec4 m_par[32];
varying vec3 wp;
varying vec3 wn;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 h22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	return 0.5 * vn(p) + 0.3 * vn(p * 2.1 + 7.3) + 0.2 * vn(p * 4.3 + 1.7);
}
// distance (in the units of p) to the nearest line of a grid of the given cell size, offset so lines sit at multiples
float grid_d(vec2 p, vec2 size) {
	vec2 g = abs(fract(p / size + 0.5) - 0.5) * size;
	return min(g.x, g.y);
}
// voronoi cells: x = distance to the nearest point, y = distance to the border, z/w = the cell id
vec4 voro(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 best = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + h22(ip + g) * 0.8 + 0.1 - fp;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				best = ip + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec4(sqrt(d1), sqrt(d2) - sqrt(d1), best);
}
vec3 marble(vec2 p, vec3 base, vec3 alt, float sc, inout float rgh) {
	vec2 q = p / sc;
	vec2 id = floor(q);
	vec2 sp = p + h22(id) * 40.0;
	float v = fbm(sp * 0.9);
	float vein = pow(1.0 - abs(2.0 * v - 1.0), 14.0);
	float vein2 = pow(1.0 - abs(2.0 * vn(sp * 2.3 + 5.0) - 1.0), 28.0);
	vec3 c = base * (0.85 + 0.35 * fbm(sp * 0.5));
	c = mix(c, alt, clamp(vein * 0.6 + vein2 * 0.3, 0.0, 1.0) * 0.55);
	return c;
}
// Floor TEXTURE only: no square joints, grout, board gaps or per-tile colour blocks. Square lines fought the hex
// grid and its seams (user, 2026-10-17); the hex seams are the only lines on a floor.
vec3 material_color(int pat, vec2 p, vec3 base, vec3 alt, float sc, inout float rgh) {
	vec3 c = base;
	if (pat == 1) {                       // concrete slabs
		float m = fbm(p * 1.3);
		c = base * (0.82 + 0.36 * m) * (0.94 + 0.12 * vn(p * 9.0));
	} else if (pat == 2) {                // flagstone
		c = base * (0.78 + 0.4 * fbm(p / sc * 0.8)) * (0.85 + 0.3 * fbm(p * 2.0));
	} else if (pat == 3) {                // carpet: soft pile, a faint lattice
		float n1 = h21(floor(p * 14.0));
		c = base * (0.82 + 0.22 * n1 + 0.18 * vn(p * 3.0));
		rgh = 1.0;
	} else if (pat == 4) {                // glazed tile
		c = base * (0.9 + 0.14 * vn(p / sc * 1.7)) * (0.93 + 0.1 * vn(p * 4.0));
	} else if (pat == 5) {                // wood boards along x
		float grain = vn(vec2(p.x * 0.9, p.y * 18.0));
		c = base * (0.8 + 0.3 * vn(p * 0.35)) * (0.84 + 0.32 * grain);
	} else if (pat == 6) {                // marble slabs
		c = marble(p, base, alt, sc, rgh);
	} else if (pat == 7) {                // rubber gym mats: studs, joints every unit
		vec2 q = p * sc;
		float dd = length(fract(q) - 0.5);
		float stud = smoothstep(0.34, 0.24, dd);
		c = base * (0.78 + 0.3 * stud) * (0.9 + 0.2 * vn(p * 2.0));
	} else if (pat == 8) {                // diamond tread plate in 2-unit panels
		vec2 q = p * sc;
		vec2 id = floor(q);
		vec2 l = fract(q) - 0.5;
		if (mod(id.x + id.y, 2.0) > 0.5) {
			l = l.yx;
		}
		vec2 r = vec2(l.x + l.y, l.x - l.y) * 0.7071;
		float e = (r.x * r.x) / (0.34 * 0.34) + (r.y * r.y) / (0.1 * 0.1);
		float bar = 1.0 - smoothstep(0.55, 1.0, e);
		c = base * (0.78 + 0.2 * vn(p * 1.5)) + alt * bar * 0.4;
	}
	return c;
}
vec3 wall_color(int pat, vec2 p, vec3 base, vec3 alt, float sc, inout float rgh) {
	vec3 c = base;
	float u = p.x;
	float v = p.y;
	if (pat == 20) {                      // poured concrete: formwork panels, tie holes, rain streaks
		vec2 psz = vec2(2.4, 1.2);
		float line = 1.0 - smoothstep(0.0, 0.035, grid_d(p, psz));
		float streak = fbm(vec2(u * 0.8, v * 0.12));
		c = base * (0.78 + 0.45 * streak) * (0.92 + 0.16 * fbm(p * 5.0));
		vec2 f = fract(p / psz + 0.5) * psz;
		vec2 fh = min(f, psz - f);
		float hole = 1.0 - smoothstep(0.04, 0.06, length(fh - vec2(0.3)));
		c = mix(c, alt, line * 0.8);
		c = mix(c, alt * 0.5, hole);
	} else if (pat == 21) {               // rough stone blocks in courses
		float ch = 0.8;
		float row = floor(v / ch);
		float w = 1.3 + 1.3 * h21(vec2(row, 1.0));
		float xx = u + h21(vec2(row, 2.0)) * 5.0;
		vec2 bid = vec2(floor(xx / w), row);
		float lx = fract(xx / w) * w;
		float ly = fract(v / ch) * ch;
		float edge = min(min(lx, w - lx), min(ly, ch - ly));
		float mortar = 1.0 - smoothstep(0.02, 0.07, edge);
		c = base * (0.62 + 0.75 * h21(bid)) * (0.8 + 0.4 * fbm(p * 3.0 + bid * 3.0));
		c *= 0.82 + 0.18 * smoothstep(0.0, 0.16, edge);
		c = mix(c, alt, mortar);
	} else if (pat == 22) {               // wood panelling: vertical boards, rails
		float bw = 0.32;
		float col = floor(u / bw);
		c = base * (0.7 + 0.55 * h21(vec2(col, 9.0))) * (0.8 + 0.4 * vn(vec2(u * 2.0, v * 0.5 + col * 3.0)));
		float lx = fract(u / bw) * bw;
		float groove = 1.0 - smoothstep(0.0, 0.025, min(lx, bw - lx));
		c = mix(c, alt, groove * 0.8);
		float ry = fract(v / 1.6) * 1.6;
		float rail = step(ry, 0.16);
		c = mix(c, base * 1.35, rail * 0.8);
		float redge = 1.0 - smoothstep(0.0, 0.02, min(abs(ry - 0.16), ry));
		c = mix(c, alt, redge * 0.8);
	} else if (pat == 23) {               // marble facing: slabs with thin joints (marble() shifts the veins per slab)
		c = marble(p, base, alt, sc, rgh);
		// the floors dropped their slab joints (no square lines on a floor); a wall facing keeps them, or each slab's
		// shifted veins meet the next one at an invisible, broken line
		float joint = 1.0 - smoothstep(0.004, 0.016, grid_d(p, vec2(sc)));
		c = mix(c, base * 0.35, joint);
		rgh = mix(rgh, 0.8, joint);
	}
	return c;
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	int id = int(UV2.y + 0.5);
	vec3 alb;
	float glow = UV2.x;
	float rgh = rough;
	float spc = spec;
	if (id == 0) {
		vec4 t = texture(tex, UV);
		alb = t.rgb;
		glow = max(glow, t.a);
	} else {
		vec4 b = m_base[id];
		vec4 a = m_alt[id];
		vec4 pr = m_par[id];
		rgh = pr.x;
		spc = pr.y;
		int pat = int(b.a + 0.5);
		if (is_wall && abs(wn.y) < 0.5) {
			vec2 along = vec2(-wn.z, wn.x);
			alb = wall_color(pat, vec2(dot(wp.xz, along), wp.y), b.rgb, a.rgb, a.a, rgh);
		} else if (is_wall) {
			alb = b.rgb * 0.5 * (0.8 + 0.4 * fbm(wp.xz * 3.0));  // the cap of a wall: darker than the floor, like the slate cap
		} else {
			alb = material_color(pat, wp.xz, b.rgb, a.rgb, a.a, rgh);
		}
	}
	ALBEDO = alb * COLOR.rgb;
	ROUGHNESS = rgh;
	SPECULAR = spc;
	float k = near_range > 0.0 ? mix(near_gain, 1.0, smoothstep(near_range * 0.5, near_range, length(VERTEX))) : 1.0;
	EMISSION = glow_color * glow_energy * k * glow;
}
"""

## The pool's tiled floor and liner (the lab's look): square tiles with light grout in world units (floors in XZ, the
## liner along its face from its normal). UV2.y picks the look: 0 the indoor pool (aqua tile, white grout), 1 the
## specimen pool (dark green tile, glowing green grout), 2 the shark moat (mossy stone blocks in a running bond, dark
## joints). Vertex COLOR shades the liner a touch darker than the floor.
const POOL_LOOK_INDEX := {PoolGeo.LOOK_POOL: 0, PoolGeo.LOOK_SPECIMEN: 1, PoolGeo.LOOK_MOAT: 2}
const POOL_SHADER := """
shader_type spatial;
uniform vec4 pool_base : source_color = vec4(0.55, 0.85, 0.9, 1.0);
uniform vec4 pool_grout : source_color = vec4(0.92, 0.98, 1.0, 1.0);
uniform vec4 spec_base : source_color = vec4(0.32, 0.42, 0.38, 1.0);
uniform vec4 spec_grout : source_color = vec4(0.5, 1.0, 0.45, 1.0);
uniform vec4 moat_base : source_color = vec4(0.4, 0.42, 0.37, 1.0);
uniform vec4 moat_grout : source_color = vec4(0.13, 0.15, 0.13, 1.0);
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	bool spec = UV2.y > 0.5 && UV2.y < 1.5;
	vec2 uv;
	if (abs(wn.y) > 0.5) {
		uv = wp.xz;
	} else {
		vec2 tg = normalize(vec2(-wn.z, wn.x));
		uv = vec2(dot(wp.xz, tg), wp.y);
	}
	if (UV2.y > 1.5) {
		// the moat: stone blocks 0.62 x 0.31 in a running bond, each a little lighter or darker
		vec2 bs = vec2(0.62, 0.31);
		vec2 q = uv / bs;
		q.x += 0.5 * floor(q.y);
		vec2 cell = floor(q);
		vec2 f = fract(q);
		float ed = min(min(f.x, 1.0 - f.x) * bs.x, min(f.y, 1.0 - f.y) * bs.y);
		float joint = 1.0 - smoothstep(0.012, 0.03, ed);
		float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
		vec3 stone = moat_base.rgb * (0.82 + 0.3 * h) * COLOR.rgb;
		ALBEDO = mix(stone, moat_grout.rgb, joint);
		ROUGHNESS = 0.85;
		SPECULAR = 0.3;
	} else {
		float tile = spec ? 0.36 : 0.42;
		vec2 g = fract(uv / tile);
		float e = min(min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y));
		float line = 1.0 - smoothstep(0.03, 0.08, e);
		vec3 base = spec ? spec_base.rgb : pool_base.rgb;
		vec3 grout = spec ? spec_grout.rgb : pool_grout.rgb;
		ALBEDO = mix(base * COLOR.rgb, grout, line);
		EMISSION = grout * line * (spec ? 0.6 : 0.0);
		ROUGHNESS = 0.4;
		SPECULAR = 0.5;
	}
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
	if surf == Surf.POOL or surf == Surf.CHANNEL:
		if _pool_shader == null:
			_pool_shader = Shader.new()
			_pool_shader.code = POOL_SHADER
		m.shader = _pool_shader
		if surf == Surf.CHANNEL:
			m.resource_name = CHANNEL_MATERIAL
		return m
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
	var use_mat_shader := _use_mats and (surf == Surf.FLOOR_TOP or surf == Surf.WALL_TOP or surf == Surf.WALL_SIDE)
	if use_mat_shader:
		if _material_shader == null:
			_material_shader = Shader.new()
			_material_shader.code = MATERIAL_SHADER
		m.shader = _material_shader
		var tables := FloorMaterials.table_arrays()
		m.set_shader_parameter("m_base", tables["base"])
		m.set_shader_parameter("m_alt", tables["alt"])
		m.set_shader_parameter("m_par", tables["par"])
		m.set_shader_parameter("is_wall", surf != Surf.FLOOR_TOP)
	else:
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


## Shader table index of the floor material of a cell (FloorMaterials; 0 = the classic slate texture).
static func _floor_mat(cell: HexMap.Cell) -> int:
	return FloorMaterials.floor_of(cell.mat_id)


## Shader table index of the wall material of a cell (0 = the classic wall texture).
static func _wall_mat(cell: HexMap.Cell) -> int:
	var w := FloorMaterials.wall_of(cell.mat_id)
	return FloorMaterials.WALL_OFFSET + w if w != 0 else 0


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


## Ground height (levels) of kite k of cell nb: its wall top on the wall side of a cut cell.
func _kite_level(nb: Vector2i, k: int) -> int:
	var cell: HexMap.Cell = _map.cells.get(nb)
	if cell == null:
		return FLOOR_DEPTH
	if cell.pool_mask != 0 and (cell.pool_mask >> posmod(k, 6)) & 1 == 1:
		return cell.pool_level
	if cell.type != HexMap.Tile.WALL and cell.wall_mask != 0 and (cell.wall_mask >> posmod(k, 6)) & 1 == 1:
		return cell.wall_top
	return cell.level


## Height (levels) across a hex-edge half of kite k of cell c: `first` is the half from the midpoint of the edge
## facing DIRS[k] to the kite's corner (it borders kite k + 2 of that neighbour), else the half from the corner to
## the midpoint of the edge facing DIRS[k + 1] (kite k + 4 of that neighbour).
func _across(c: Vector2i, k: int, first: bool) -> int:
	if first:
		return _kite_level(c + Hex.DIRS[posmod(k, 6)], k + 2)
	return _kite_level(c + Hex.DIRS[posmod(k + 1, 6)], k + 4)


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
	top_b.mat = 0.0
	side_b.mat = 0.0
	if is_wall:
		var wm := _wall_mat(cell)
		top_b.mat = float(wm)
		side_b.mat = float(wm)
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
		var fm := _floor_mat(cell)
		var sg := FloorMaterials.seam_gain(fm)
		top_b.mat = float(fm)
		rim = col.lerp(Color(0.95, 0.52, 0.22), 0.45 * sg)
		rim_glow = 0.5 * sg
		seam = _scaled(seam, sg)
		# (no start marker: the van or the elevator is where the crew stands; on floors 2-3 the start cell is just a spot,
		# so a glowing hex there meant nothing: user, 2026-10-21)
		if cell.tag == "exit" and _map.elevator.is_empty():   # (an elevator marks its own landing: sill and car light)
			col = col.lerp(Color(1.0, 0.5, 1.0), 0.14)
			rim = col.lerp(EXIT_COLOR, 0.55)
			seam = EXIT_COLOR
	_top_tile(top_b, center, y, col, rim, rim_glow, not is_crate)
	_seam_hex(center, y, seam)

	var side_col := _shade(cell.level) if not is_crate else _scaled(Color.WHITE, 0.95)
	if is_wall:
		side_col = Color(0.9, 0.9, 0.9)
	elif _cave_rock.has(c):
		side_col = _cave_cliff   # (a lava cave's rock: dark basalt cliffs)
	for j in 6:
		var nb := c + Hex.DIRS[_edge_dir(j)]
		var bottom := _bottom_level(nb)
		var n := Hex.dir_vector(_edge_dir(j))
		var y_top := y - SEAM_DROP
		var p0 := _corner(center, j)
		var p1 := _corner(center, j + 1)
		if _map.midpoint_walls:
			# the two halves of this edge may border different parts of a cut neighbour (its wall or its floor):
			# corner j is kite e's corner, corner j + 1 is kite e - 1's
			var e := _edge_dir(j)
			var b0 := _across(c, e, true)
			var b1 := _across(c, e - 1, false)
			if b0 != b1:
				var mid := center + Hex.edge_mid(e)
				if cell.level > b0:
					_side_quad(side_b, p0, mid, y_top, b0 * LH - SEAM_DROP, n, 0.0, 0.5, side_col, SEAM_DROP)
				if cell.level > b1:
					_side_quad(side_b, mid, p1, y_top, b1 * LH - SEAM_DROP, n, 0.5, 1.0, side_col, SEAM_DROP)
				continue
			bottom = b0
		if cell.level <= bottom:
			continue  # hidden by a taller-or-equal neighbor
		var y_bot := bottom * LH - SEAM_DROP
		if _pits.has(nb):
			# warm glow climbing the last stretch of the pit wall
			var gh := minf(0.9, y_top - y_bot)
			_side_quad(side_b, p0, p1, y_top, y_bot + gh, n, 0.0, 1.0, side_col, SEAM_DROP)
			_side_quad(side_b, p0, p1, y_bot + gh, y_bot, n, 0.0, 1.0, side_col, SEAM_DROP, 0.0, 0.6)
		else:
			_side_quad(side_b, p0, p1, y_top, y_bot, n, 0.0, 1.0, side_col, SEAM_DROP)
	if not is_wall and cell.tag == "exit" and _map.elevator.is_empty():
		_add_ring(center, y + 0.02, EXIT_COLOR)


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

## Stepped treads rising toward stair_dir; tread i sits at the ramp height of its middle. `open` = the kites to draw
## (a cut staircase only draws its floor side; the wall part is _add_wall_part's).
func _add_stairs(c: Vector2i, cell: HexMap.Cell, open: int = HexMap.ALL_KITES) -> void:
	if open != HexMap.ALL_KITES:
		_add_cut_stairs(c, cell, open)
		return
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
			# u = the part of the edge this tread covers (the edge is one texture repeat), not 0..1 per piece
			_side_quad(side_b, p0, p1, y, bottom - SEAM_DROP, Hex.dir_vector(_edge_dir(j)), lo, hi, Color.WHITE)
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
				_side_quad(side_b, center + lo_p, center + hi_p, y, prev_y, -dirv, lo_p.dot(side) / Hex.SIZE, hi_p.dot(side) / Hex.SIZE, Color(0.9, 0.9, 0.9))
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


# ---------------------------------------------------------------------- midpoint walls (cut cells)

static func _kpt(center: Vector3, off: Vector3, scale: float, y: float) -> Vector3:
	return Vector3(center.x + off.x * scale, y, center.z + off.z * scale)


## Contiguous runs of the kites set in `mask`, each [first kite, count] (count 6 = the whole hex).
static func _runs(mask: int) -> Array:
	var out: Array = []
	if mask == HexMap.ALL_KITES:
		out.append([0, 6])
		return out
	for k in 6:
		if (mask >> k) & 1 == 0 or (mask >> posmod(k - 1, 6)) & 1 == 1:
			continue   # not in the mask, or not the first kite of its run
		var n := 0
		while n < 6 and (mask >> ((k + n) % 6)) & 1 == 1:
			n += 1
		out.append([k, n])
	return out


## The outline of a run of kites as offsets from the center: [center, mid(k0), corner(k0), mid(k0+1), ...,
## corner(k1), mid(k1+1)] (star-shaped about the center, so a fan from it is exact), or the six corners for a whole hex.
static func _run_outline(k0: int, count: int) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	if count >= 6:
		for i in 6:
			pts.append(Hex.kite_corner(i))
		return pts
	pts.append(Vector3.ZERO)
	for i in count:
		var k := (k0 + i) % 6
		pts.append(Hex.edge_mid(k))
		pts.append(Hex.kite_corner(k))
	pts.append(Hex.edge_mid((k0 + count) % 6))
	return pts


## The outline of a run of kites in DRAWING order (the winding of every other top) with the fan hub first: the
## center for a partial run. A run of 4 or 5 kites is CONCAVE (its angle at the center is 240 / 300 degrees: an
## inside corner of a wall, or the floor beside a one- or two-kite wall stub), so a fan from any other vertex
## spills a triangle over the missing kites; the outline is star-shaped about the center, so a fan from the center
## is exact for every run (tests/test_wall_mesh.gd checks all 63 masks).
static func _cap_outline(k0: int, count: int) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var outline := _run_outline(k0, count)
	for i in outline.size():
		pts.append(outline[outline.size() - 1 - i])   # reversed: see _ccw_fix
	if count < 6:
		pts.push_front(pts.pop_back())                 # the center (last after reversing) becomes the hub
	return pts


## A tile top over a run of kites: inset top, bevel along the hex-edge parts only (the radial parts lie on the
## wall line and stay flush), the full-size seam below.
func _run_tile(top_b: Batch, center: Vector3, k0: int, count: int, y: float, col: Color, rim: Color, rim_glow: float, seam: Color, world_uv: bool) -> void:
	var outline := _run_outline(k0, count)
	var cap := _cap_outline(k0, count)
	var pts: Array = []
	var uv: Array = []
	for o in cap:
		var p := _kpt(center, o, TOP_SCALE, y)
		pts.append(p)
		uv.append(_uv_for(center, p, world_uv))
	top_b.poly(pts, Vector3.UP, uv, col)
	var m := outline.size()
	var whole := count >= 6
	for i in m:
		var a := outline[i]
		var b := outline[(i + 1) % m]
		if not whole and (a == Vector3.ZERO or b == Vector3.ZERO):
			continue   # a radial edge: on the wall line
		var ia := _kpt(center, a, TOP_SCALE, y)
		var ib := _kpt(center, b, TOP_SCALE, y)
		var oa := _kpt(center, a, BEVEL_SCALE, y - BEVEL_DROP)
		var ob := _kpt(center, b, BEVEL_SCALE, y - BEVEL_DROP)
		var out_n := Hex.dir_vector(_dir_of_offset((a + b) * 0.5))
		var n := (out_n * 0.75 + Vector3.UP * 0.66).normalized()
		var quad: Array = [ia, oa, ob, ib]
		var quv: Array = [_uv_for(center, ia, world_uv), _uv_for(center, oa, world_uv), _uv_for(center, ob, world_uv), _uv_for(center, ib, world_uv)]
		var qcol: Array = [col, rim, rim, col]
		var qglow: Array = [0.0, rim_glow, rim_glow, 0.0]
		top_b.polyv(_ccw_fix(quad), n, _ccw_fix(quv), _ccw_fix(qcol), _ccw_fix(qglow))
	var sp: Array = []
	var suv: Array = []
	for o in cap:
		sp.append(_kpt(center, o, 1.0, y - SEAM_DROP))
		suv.append(Vector2.ZERO)
	var seam_b: Batch = _batches[Surf.SEAM]
	seam_b.poly(sp, Vector3.UP, suv, seam)


## _top_tile walks the hex corners in Hex.corner order; a kite outline walks the other way round. Reverse it so
## every top keeps the same winding (front faces up).
static func _ccw_fix(a: Array) -> Array:
	var out := a.duplicate()
	out.reverse()
	return out


## The hex direction whose edge a point on the hex boundary (offset from the center) lies on.
static func _dir_of_offset(o: Vector3) -> int:
	var best := 0
	var best_d := -INF
	for d in 6:
		var v := Hex.dir_vector(d)
		var dd := o.x * v.x + o.z * v.z
		if dd > best_d:
			best_d = dd
			best = d
	return best


## The floor side of a cut cell: a tile over its open kites, cliff sides on its open half edges.
func _add_floor_part(c: Vector2i, cell: HexMap.Cell, open: int) -> void:
	var center := Hex.to_world(c)
	var is_crate := _crates.has(c)
	var top_b: Batch = _batches[Surf.CRATE_TOP if is_crate else Surf.FLOOR_TOP]
	var side_b: Batch = _batches[Surf.CRATE_SIDE if is_crate else Surf.CLIFF]
	var y := cell.level * LH
	var hv := _hash2(c)
	var col: Color
	var rim: Color
	var rim_glow := 0.5
	var seam: Color = _scaled(SEAM_COLOR, 0.8 + 0.3 * hv)
	top_b.mat = 0.0
	if is_crate:
		col = _scaled(Color.WHITE, 0.9 + 0.12 * hv)
		rim = _scaled(Color(0.55, 0.32, 0.15), 0.8)
		rim_glow = 0.10
		seam = _scaled(seam, 0.45)
	else:
		col = _scaled(level_tint(cell.level), 0.93 + 0.12 * hv)
		var fm := _floor_mat(cell)
		var sg := FloorMaterials.seam_gain(fm)
		top_b.mat = float(fm)
		rim = col.lerp(Color(0.95, 0.52, 0.22), 0.45 * sg)
		rim_glow = 0.5 * sg
		seam = _scaled(seam, sg)
	for run: Array in _runs(open):
		_run_tile(top_b, center, int(run[0]), int(run[1]), y, col, rim, rim_glow, seam, not is_crate)
	var side_col := _shade(cell.level) if not is_crate else _scaled(Color.WHITE, 0.95)
	_kite_sides(c, center, open, cell.level, side_b, side_col)


## Side faces down from the hex-edge halves of the kites in `mask` (top at `level`) to whatever is across.
func _kite_sides(c: Vector2i, center: Vector3, mask: int, level: int, side_b: Batch, side_col: Color) -> void:
	var y_top := level * LH - SEAM_DROP
	for k in 6:
		if (mask >> k) & 1 == 0:
			continue
		var corner := center + Hex.kite_corner(k)
		for first: bool in [true, false]:
			var bottom := _across(c, k, first)
			if level <= bottom:
				continue
			var d := k if first else (k + 1) % 6
			var mid := center + Hex.edge_mid(d)
			var y_bot := bottom * LH - SEAM_DROP
			var n := Hex.dir_vector(d)
			if first:
				_side_quad(side_b, mid, corner, y_top, y_bot, n, 0.5, 1.0, side_col, SEAM_DROP)
			else:
				_side_quad(side_b, corner, mid, y_top, y_bot, n, 0.0, 0.5, side_col, SEAM_DROP)


## The wall side of a cut cell: its wall kites raised to wall_top with a capped, seamed top like a wall column,
## the flat FACE on each wall line (center -> edge midpoint) down to the floor, and outer sides where the
## neighbouring wall is lower.
func _add_wall_part(c: Vector2i, cell: HexMap.Cell, mask: int) -> void:
	var center := Hex.to_world(c)
	var top_lv := cell.wall_top
	var y := top_lv * LH
	var hv := _hash2(c)
	var col := _scaled(Color(0.95, 0.97, 1.0), 0.9 + 0.2 * hv)
	var rim := _scaled(col, 0.7)
	var seam := _scaled(_scaled(SEAM_COLOR, 0.8 + 0.3 * hv), 0.20)
	var top_b: Batch = _batches[Surf.WALL_TOP]
	var side_b: Batch = _batches[Surf.WALL_SIDE]
	var wm := float(_wall_mat(cell))
	top_b.mat = wm
	side_b.mat = wm
	for run: Array in _runs(mask):
		_run_tile(top_b, center, int(run[0]), int(run[1]), y, col, rim, 0.12, seam, true)
	var side_col := Color(0.9, 0.9, 0.9)
	_kite_sides(c, center, mask, top_lv, side_b, side_col)
	if mask == HexMap.ALL_KITES:
		return
	# the faces on the wall lines: spoke d separates kites d - 1 and d
	var floor_y := cell.level * LH - SEAM_DROP
	for d in 6:
		var here := (mask >> d) & 1
		var prev := (mask >> posmod(d - 1, 6)) & 1
		if here == prev:
			continue
		var mid := center + Hex.edge_mid(d)
		var t := Hex.dir_vector(d)
		var n := Vector3(-t.z, 0.0, t.x)
		var open_k := d if here == 0 else posmod(d - 1, 6)
		if n.dot(Hex.kite_corner(open_k)) < 0.0:
			n = -n
		# beside a pool kite (water up to the wall, the sewer) the face runs on down to the pool floor
		var bottom_y := floor_y if (cell.pool_mask >> open_k) & 1 == 0 else cell.pool_level * LH - SEAM_DROP
		# u is the distance from the hex center in side-texture repeats (one per SIZE, like every hex-edge face: the
		# texture is one world unit wide and one level tall). It mirrors at the midpoint, so the neighbouring cell's
		# half of the face continues it seamlessly, and the texture's corner glow lands on the hex centers, where
		# wall corners are. (It was scaled by 0.5 here, which drew these faces at half the horizontal density of
		# every other side: stretched 2x, with the corner glow in the middle of a face.)
		_side_quad(side_b, center, mid, y - SEAM_DROP, bottom_y, n, 0.0, Hex.INNER / Hex.SIZE, side_col, SEAM_DROP)


## Treads of a cut staircase over its open kites only (each kite clipped to each tread strip), with the outer faces
## on the open half edges.
func _add_cut_stairs(c: Vector2i, cell: HexMap.Cell, open: int) -> void:
	var center := Hex.to_world(c)
	var dirv := Hex.dir_vector(cell.stair_dir)
	var side := Vector3(-dirv.z, 0.0, dirv.x)
	var n := clampi(cell.stair_rise * 2, 2, 8)
	var top_b: Batch = _batches[Surf.STAIRS_TOP]
	var side_b: Batch = _batches[Surf.STAIRS_SIDE]
	var span := 2.0 * Hex.INNER
	var prev_y := 0.0
	for s in n:
		var u0 := -Hex.INNER + span * s / n
		var u1 := -Hex.INNER + span * (s + 1) / n
		var y := (cell.level + (s + 0.5) * cell.stair_rise / n) * LH
		var drew := false
		for k in 6:
			if (open >> k) & 1 == 0:
				continue
			var kite: Array[Vector3] = [Vector3.ZERO, Hex.edge_mid(k), Hex.kite_corner(k), Hex.edge_mid((k + 1) % 6)]
			var poly: Array[Vector3] = _clip(kite, dirv, u0, u1)
			if poly.size() < 3:
				continue
			drew = true
			var pts: Array = []
			var uv: Array = []
			for p in poly:
				pts.append(center + Vector3(p.x, y - center.y, p.z))
				uv.append(Vector2(p.dot(side) * 0.8, (p.dot(dirv) - u0) / (u1 - u0)))
			top_b.poly(_ccw_fix(pts), Vector3.UP, _ccw_fix(uv), Color.WHITE)
			# outer faces on this kite's hex-edge halves
			for first: bool in [true, false]:
				var d := k if first else (k + 1) % 6
				var seg := _strip_seg(Hex.edge_mid(d), Hex.kite_corner(k), dirv, u0, u1)
				if seg.is_empty():
					continue
				var bottom := _across(c, k, first) * LH
				if y <= bottom + 0.0001:
					continue
				# u as _kite_sides lays it out (0.5 at the midpoint, 0 / 1 at the corner), in world units
				var hm := Hex.edge_mid(d)
				var sg := 1.0 if first else -1.0
				var su0 := 0.5 + sg * seg[0].distance_to(hm) / Hex.SIZE
				var su1 := 0.5 + sg * seg[1].distance_to(hm) / Hex.SIZE
				_side_quad(side_b, center + seg[0], center + seg[1], y, bottom - SEAM_DROP, Hex.dir_vector(d), su0, su1, Color.WHITE)
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
					if lo_p.distance_to(hi_p) > 0.001:
						_side_quad(side_b, center + lo_p, center + hi_p, y, prev_y, -dirv, lo_p.dot(side) / Hex.SIZE, hi_p.dot(side) / Hex.SIZE, Color(0.9, 0.9, 0.9))
		if drew:
			_stair_steps += 1
		prev_y = y


## The part of segment a -> e (offsets) inside the strip u0 <= dot(p, axis) <= u1, as [p0, p1], or [].
static func _strip_seg(a: Vector3, e: Vector3, axis: Vector3, u0: float, u1: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var ua := a.dot(axis)
	var ue := e.dot(axis)
	var lo := 0.0
	var hi := 1.0
	if absf(ua - ue) < 0.00001:
		if ua < u0 - 0.0001 or ua > u1 + 0.0001:
			return out
	else:
		lo = clampf(inverse_lerp(ua, ue, u0), 0.0, 1.0)
		hi = clampf(inverse_lerp(ua, ue, u1), 0.0, 1.0)
		if lo > hi:
			var t := lo
			lo = hi
			hi = t
		if hi - lo < 0.0001:
			return out
	out.append(a.lerp(e, lo))
	out.append(a.lerp(e, hi))
	return out


# ---------------------------------------------------------------------- pools (the inset drawing mode)

## A pool cell: its deck kites as a floor tile flush with the rim (a ring cell), its pool kites as the tiled pool floor,
## and the liner on every rim line through its center, from the deck down to the pool floor, facing the water.
## WATER UP TO A WALL (the sewer, docs/design/sewer-concept.md "Phase 1 as built"): a cut cell may have pool kites too (a
## channel running to the wall). Its wall kites are the wall part as on any cut cell (its faces on the wall lines reach
## down to the pool floor beside a pool kite), its pool kites the pool floor, its other kites deck; a liner stands only
## between a pool kite and a deck kite (never against the wall).
func _add_pool_cell(c: Vector2i, cell: HexMap.Cell) -> void:
	var wall := cell.wall_mask
	var pool := cell.pool_mask & ~wall
	var deck := HexMap.ALL_KITES & ~pool & ~wall
	if deck != 0:
		_add_floor_part(c, cell, deck)
	if wall != 0:
		_add_wall_part(c, cell, wall)
	var center := Hex.to_world(c)
	var look := _pool_look(c)
	var b: Batch = _batches[Surf.CHANNEL if look.begins_with("sewer") else Surf.POOL]
	b.mat = float(POOL_LOOK_INDEX.get(look, 0))
	var y_pool := cell.pool_level * LH
	for run: Array in _runs(pool):
		var pts: Array = []
		var uv: Array = []
		for o in _cap_outline(int(run[0]), int(run[1])):
			var p := _kpt(center, o, 1.0, y_pool)
			pts.append(p)
			uv.append(Vector2(p.x, p.z))
		b.poly(pts, Vector3.UP, uv, Color.WHITE)
	if deck == 0:
		return
	var y_deck := cell.level * LH
	var liner_col := Color(0.86, 0.86, 0.86)
	for d in 6:
		var here := (pool >> d) & 1
		var prev := (pool >> posmod(d - 1, 6)) & 1
		if here == prev:
			continue
		if ((wall >> d) & 1) == 1 or ((wall >> posmod(d - 1, 6)) & 1) == 1:
			continue   # (pool against the wall part: the wall's own face runs down to the pool floor there)
		# spoke d separates kites d - 1 and d: the liner faces the pool kite
		var mid := center + Hex.edge_mid(d)
		var t := Hex.dir_vector(d)
		var n := Vector3(-t.z, 0.0, t.x)
		var wet_k := d if here == 1 else posmod(d - 1, 6)
		if n.dot(Hex.kite_corner(wet_k)) < 0.0:
			n = -n
		_side_quad(b, center, mid, y_deck, y_pool, n, 0.0, Hex.INNER / Hex.SIZE, liner_col)


## The look of the pool a cell belongs to (PoolGeo.LOOK_*), cached per build.
func _pool_look(c: Vector2i) -> String:
	if _pool_looks.is_empty():
		for rec in _map.pools:
			for pc: Vector2i in (rec["basin"] as Array) + (rec["ring"] as Array):
				_pool_looks[pc] = str(rec["look"])
	return str(_pool_looks.get(c, PoolGeo.LOOK_POOL))
