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
const WALL_TOP_SCALE := 0.93     ## a wall cap's flat top with wall_depth on (its bevel then runs out to the full hex)
const NO_WALL := -999             ## (_top_tile / _run_tile: not a wall's cap)

const SEAM_COLOR := Color(1.0, 0.40, 0.07)
const EXIT_COLOR := Color(1.0, 0.28, 1.0)

enum Surf { FLOOR_TOP, WALL_TOP, CRATE_TOP, STAIRS_TOP, CLIFF, WALL_SIDE, CRATE_SIDE, STAIRS_SIDE, SEAM, POOL, CHANNEL }
## The material name of the CHANNEL surface: a sewer body's pool kites (a HexMap.pools record whose look is "sewer_*"), drawn
## like the pools but on their own surface, so SewerView restyles a generated floor's sewer without touching its pools.
const CHANNEL_MATERIAL := "sewer_channel"

## UNDERGROUND (a crypt: haunted-build-plan.md H2): the cells whose material is an underground row (FloorMaterials.is_under:
## the crypt's) are drawn into a second mesh, `under_instance`, on render layer UNDER_LAYER, which DungeonLook's key and fill
## lights leave out (their light_cull_mask): the crypt's stone is lit only by the ambient (turned down per material, the
## row's "ambient": the shader's AO) and the omni lights (its candles, its accent light, the chapel's shafts), as the look
## test lit it, while the rest of the floor keeps the game's light. A map without such cells builds one mesh, as before.
const UNDER_LAYER := 1 << 1

## Filled by build(): triangles, vertices, surfaces, cells, stair_steps, crates.
var stats: Dictionary = {}
var mesh_instance: MeshInstance3D
var under_instance: MeshInstance3D = null   ## the underground cells' mesh (null without any)
var pool_view: PoolView = null   ## water, coping, foam, ladders, gantries of the map's pools (null without any)
## How loud the glowing seams are (read by build()). 1 = the game's look. Menu backdrops turn it down because
## bright seams under a UI are noisy: `seam_gain` scales every seam / rim glow, and seams closer to the camera than
## `seam_near_range` (view-space units, 0 = off) are further scaled by `seam_near_gain` (fading back to full at the
## range), so the foreground floor stays calm while the far floor keeps its glow.
var seam_gain := 1.0
var seam_near_gain := 1.0
var seam_near_range := 0.0
## WALL DEPTH (docs/design/wall-depth.md; on in the game, the user's call 2026-10-29): the material shader's walls
## get rough ashlar courses locked to the hex grid, per-stone bevels, depth in albedo and AO, a coping band and slab-cut caps,
## and the wall caps close the seam round them (flat to WALL_TOP_SCALE, a bevel out to the full hex and down to the face's
## top). A shader uniform, so it flips live (`set_wall_depth`): the mesh carries both shapes (CUSTOM0, Batch.custom).
## `wall_depth_default` is what a new view starts with (the gym's Experiments row sets it): on, everywhere in the game (the
## user, 2026-10-29, on the second pass: "The second pass is great. This is much better.", then "Everywhere").
static var wall_depth_default := true
var wall_depth := wall_depth_default

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
	## CUSTOM0 per vertex (4 floats; the wall surfaces upload it, the others don't): what the WALL DEPTH look needs
	## (`wall_depth`, MATERIAL_SHADER). A wall face: x = its top (its level line, SEAM_DROP down), y = its bottom, z = how far
	## its top rises with wall_depth on, w = 1 at its top vertices. A wall cap: xyz = how far the vertex moves with
	## wall_depth on, w = 2.
	var custom := PackedFloat32Array()

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
		for _i in pts.size() * 4:
			custom.append(0.0)
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
		for _i in pts.size() * 4:
			custom.append(0.0)
		_fan(base, pts.size())

	## Set the CUSTOM0 of the last `values.size()` vertices added, in the order they were added.
	func set_custom_last(values: Array) -> void:
		var first := verts.size() - values.size()
		for i in values.size():
			var c: Vector4 = values[i]
			custom[(first + i) * 4] = c.x
			custom[(first + i) * 4 + 1] = c.y
			custom[(first + i) * 4 + 2] = c.z
			custom[(first + i) * 4 + 3] = c.w

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
	var any_under := false
	for c in map.cells:
		var mid := (map.cells[c] as HexMap.Cell).mat_id
		if mid != 0:
			_use_mats = true
			any_under = any_under or FloorMaterials.is_under(mid)
	for _i in Surf.size():
		_batches.append(Batch.new())
	var main := _batches
	var under: Array = []
	if any_under:
		for _i in Surf.size():
			under.append(Batch.new())
	under_instance = null

	for c in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if any_under:
			_batches = under if FloorMaterials.is_under(cell.mat_id) else main
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
	_batches = main
	_add_pit_bottoms()

	var counts := [0, 0]   ## triangles, vertices
	var mesh := _make_mesh(main, counts)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = mesh
	add_child(mesh_instance)
	var surfaces := mesh.get_surface_count()
	if any_under:
		var umesh := _make_mesh(under, counts)
		under_instance = MeshInstance3D.new()
		under_instance.name = "UnderMesh"
		under_instance.mesh = umesh
		under_instance.layers = UNDER_LAYER
		add_child(under_instance)
		surfaces += umesh.get_surface_count()
	var tris: int = counts[0]
	var verts: int = counts[1]
	if not map.pools.is_empty():
		pool_view = PoolView.new()
		pool_view.name = "Pools"
		add_child(pool_view)
		pool_view.build(map)
	stats = {
		"triangles": tris, "vertices": verts, "surfaces": surfaces,
		"cells": map.cells.size(), "stair_steps": _stair_steps, "crates": _crates.size(),
	}
	_batches.clear()


## One ArrayMesh from a set of surface batches (each non-empty one a surface with its material); adds its triangles and
## vertices to counts [triangles, vertices].
func _make_mesh(batches: Array, counts: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for s in Surf.size():
		var b: Batch = batches[s]
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
		var flags := 0
		if s == Surf.WALL_TOP or s == Surf.WALL_SIDE:
			arrays[Mesh.ARRAY_CUSTOM0] = b.custom   # (the wall depth look's data; same vertices, same triangles)
			flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(s))
		counts[0] += b.indices.size() / 3
		counts[1] += b.verts.size()
	return mesh


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
uniform float wall_depth = 0.0;
uniform vec4 m_base[40];
uniform vec4 m_alt[40];
uniform vec4 m_par[40];
varying vec3 wp;
varying vec3 wn;
varying vec4 wface;

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
	} else if (pat == 9) {                // herringbone parquet (the haunted mansion): boards sc wide, five long, in a 45-degree staircase
		vec2 hp = vec2(p.x - p.y, p.x + p.y) * 0.7071 / sc;
		float n = 5.0;
		float dd = hp.x - hp.y;
		float b = floor((dd + n + 1.0) / (2.0 * n));
		vec2 lc = vec2(0.0);
		vec2 bid = vec2(0.0);
		for (int k = 0; k < 2; k++) {
			float bb = b - float(k);
			vec2 q = hp - bb * vec2(n, -n);
			float t = floor(q.y);
			if (q.x - t >= 0.0 && q.x - t < n) {
				lc = vec2(q.x - t, q.y - t);
				bid = vec2(bb, t);
				break;
			}
			t = floor(q.x);
			if (q.y - t - 1.0 >= 0.0 && q.y - t - 1.0 < n) {
				lc = vec2(q.y - t - 1.0, q.x - t);
				bid = vec2(bb + 50.0, t);
				break;
			}
		}
		float grain = vn(vec2(lc.x * 1.2, lc.y * 9.0) + bid * 3.1);
		float tone = 0.9 + 0.16 * h21(bid);
		c = base * tone * (0.84 + 0.3 * grain) * (0.92 + 0.12 * vn(p * 0.4));
		float edge = min(min(lc.y, 1.0 - lc.y), min(lc.x, n - lc.x));
		c = mix(c, alt, (1.0 - smoothstep(0.0, 0.06, edge)) * 0.45);   // (a faint joint: the grain turns per board)
	}
	return c;
}
// `grid` (wall depth on): p.y counts from the level lines, and the formwork panels and the panelling's rails are a whole
// number of levels tall, so a wall's top ends on a line.
vec3 wall_color(int pat, vec2 p, vec3 base, vec3 alt, float sc, inout float rgh, bool grid) {
	vec3 c = base;
	float u = p.x;
	float v = p.y;
	if (pat == 20) {                      // poured concrete: formwork panels, tie holes, rain streaks
		vec2 psz = grid ? vec2(2.4, 1.0) : vec2(2.4, 1.2);
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
		float rp = grid ? 1.5 : 1.6;
		float ry = fract(v / rp) * rp;
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
	} else if (pat == 24 || pat == 25) {  // wallpaper over a panelled dado (the haunted mansion): 24 damask on walnut, 25 stripe on oak
		vec3 wood = pat == 24 ? vec3(0.20, 0.09, 0.04) : vec3(0.42, 0.25, 0.11);
		float dado = 0.55;
		if (v < dado) {
			float pw = 0.62;
			float lx = fract(u / pw) * pw;
			float ly = v - 0.06;
			float fr = min(min(lx, pw - lx), min(ly, dado - 0.06 - ly));
			c = wood * (0.85 + 0.25 * vn(vec2(u * 3.0, v * 0.6)));
			c = mix(c, wood * 1.45, smoothstep(0.05, 0.07, fr) * 0.7);
			c = mix(c, wood * 0.5, (1.0 - smoothstep(0.0, 0.02, abs(fr - 0.06))) * 0.8);
		} else if (v < dado + 0.07) {
			c = wood * (v < dado + 0.02 ? 0.6 : 1.5);
		} else if (v > 1.38) {
			c = wood * (v > 1.44 ? 1.4 : 0.7);
		} else if (pat == 24) {
			vec2 q = vec2(u / 0.38, (v - dado) / 0.42);
			q.x += 0.5 * mod(floor(q.y), 2.0);
			vec2 l = fract(q) - 0.5;
			float body = abs(l.x) * 1.5 + abs(l.y) * 0.95 - 0.06 * cos(l.y * 18.0);
			float motif = 1.0 - smoothstep(0.30, 0.34, body);
			float ring = 1.0 - smoothstep(0.0, 0.035, abs(body - 0.42));
			c = base * (0.88 + 0.18 * vn(vec2(u, v) * 2.0));
			c = mix(c, alt, clamp(motif * 0.75 + ring * 0.4, 0.0, 1.0));
		} else {
			float sw = 0.16;
			float sx = fract(u / (2.0 * sw)) * 2.0 * sw;
			float band = step(sw, sx);
			float pin = 1.0 - smoothstep(0.0, 0.012, abs(sx - sw * 0.5));
			c = mix(base, alt, band * 0.55) * (0.88 + 0.16 * vn(vec2(u * 0.5, v * 4.0)));
			c = mix(c, base * 0.6, pin * 0.6);
		}
	} else if (pat == 26) {               // conservatory glazing: a stone sill, white iron bars, dark glass with a sheen
		if (v < 0.32) {
			c = vec3(0.42, 0.40, 0.37) * (0.8 + 0.3 * fbm(vec2(u, v) * 4.0));
			rgh = 0.9;
		} else {
			vec2 pane = vec2(0.42, 0.36);
			vec2 q = vec2(u, v - 0.32);
			float bar = 1.0 - smoothstep(0.018, 0.03, grid_d(q, pane));
			float sheen = smoothstep(0.55, 1.0, fract((u + v * 0.8) * 0.45)) * 0.5;
			c = base * (1.0 + sheen * 2.2);
			c = mix(c, alt, bar);
			rgh = mix(0.12, 0.6, bar);
		}
	}
	return c;
}
// The colour a wall CAP is drawn from: its material's base, except the papered walls (24, 25), whose caps are their dado's
// wood (a red or sage band round every room read wrong in the look test, HauntLook).
vec3 cap_base(int pat, vec3 base) {
	if (pat == 24) {
		return vec3(0.26, 0.12, 0.06);
	} else if (pat == 25) {
		return vec3(0.52, 0.32, 0.14);
	}
	return base;
}

// ---- WALL DEPTH (wall_depth = 1; docs/design/wall-depth.md) ----
// The crypt is lit almost only by ambient light, where a bent normal shows little, so the depth goes into the albedo and AO
// too: a fixed "virtual light" (VKEY, from above) shades each stone's bevels, the joints and bevel recesses darken the AO,
// and the foot of a wall darkens. Joints and bevels widen with fwidth so they never go under ~1 px each, and fade out on a
// face seen edge-on (no moire). The terrain has no screen-space ink outline (models ink their own hulls), so the bent
// normals ink nothing.
const float WD_DROP = 0.07;               // HexMapView.SEAM_DROP: every face's top is a level line this far down
const float WD_COPING = 0.125;            // the coping band under the cap: the top half course
const vec3 VKEY = vec3(-0.30, 0.86, 0.41);
// The wall's outline in the dark: the cap's bevel ring and the coping's lip give off this faint cool light, so a wall top
// still reads where no light reaches (the vault: the dim seam round each cap did that before the seam closed). A floor, not
// a glow: under any real light it is lost in the lit stone.
const vec3 WD_EDGE = vec3(0.016, 0.019, 0.025);

// The hex (pointy-top, SIZE 1) centre of a point in XZ.
vec2 hex_center(vec2 p) {
	float q = 0.57735027 * p.x - p.y / 3.0;
	float r = 0.66666667 * p.y;
	vec3 c = vec3(q, r, -q - r);
	vec3 rc = round(c);
	vec3 d = abs(rc - c);
	if (d.x > d.y && d.x > d.z) {
		rc.x = -rc.y - rc.z;
	} else if (d.y > d.z) {
		rc.y = -rc.x - rc.z;
	}
	return vec2(1.7320508 * (rc.x + rc.y * 0.5), 1.5 * rc.y);
}
// The cap's stone (the cap and the coping band): dark, so caps stay darker than floors, like the slate caps.
vec3 cap_stone(vec3 base, vec2 p, float h) {
	return base * 0.44 * (0.8 + 0.4 * fbm(p * 3.0)) * (0.88 + 0.24 * h);
}
// A smoothstep bevel over `w` from the joint edge `m` at distance `e`: x = height (0 in the joint, 1 on the face),
// y = its slope d(height)/d(e).
vec2 bevel(float e, float m, float w) {
	float t = clamp((e - m) / w, 0.0, 1.0);
	return vec2(t * t * (3.0 - 2.0 * t), 6.0 * t * (1.0 - t) / w);
}
// A wall face. Rough stone blocks (pattern 21): rough ashlar locked to the hex grid. Courses a level tall (some bands two
// half-level courses), counted down from the coping (whose band is the top quarter level), so every wall top ends on a whole
// course. Joints keep to the ends and middles of the spans: a hex edge (corners at u = +/-0.5 mod 1.5) or half a wall line
// (hex centres and midpoints at u = 0 mod 0.866). Every other course has a joint on each corner and the courses between
// turn it with one stone (a quoin, hashed by its corner, so it is one colour on both faces); some spans split, some halves
// merge. The other wall patterns keep their own look, aligned to the level lines. Every pattern gets the coping band
// (the cap's stone, joints only at hex corners, a lit lip, a dark line under it) and the darker foot.
vec3 depth_face(int pat, vec3 base, vec3 alt, float sc, vec3 p3, vec3 n3, vec4 fc, vec2 fuv, inout float rgh, out vec3 nrm,
		out float ao, out float edge) {
	vec2 along = vec2(-n3.z, n3.x);
	vec3 T = vec3(along.x, 0.0, along.y);
	float u = dot(p3.xz, along);
	float v = p3.y + WD_DROP;
	float d = dot(p3.xz, n3.xz);
	float fu = max(fuv.x, 1e-4);   // (fwidth of u and v, from fragment())
	float fv = max(fuv.y, 1e-4);
	float ang = mod(degrees(atan(n3.z, n3.x)) + 360.0, 60.0);
	bool on_line = abs(ang - 30.0) < 15.0;   // on a wall line (centre to centre), not a hex edge
	float below = fc.x - p3.y;         // under the face's level line (a raised wall-line face goes 0.07 above it)
	float above = p3.y - fc.y;         // over the face's foot
	float mx = max(0.012, 0.5 * fu);      // half a joint, at least ~1 px wide in all
	float my = max(0.012, 0.5 * fv);
	float k = 1.0 - smoothstep(0.06, 0.15, max(fu, fv));   // bent normals fade out far away
	vec3 c;
	float su = 0.0;                       // the height field's slope along u
	float sv = 0.0;                       // and up
	ao = 1.0;
	edge = 0.0;
	if (below < WD_COPING) {
		// the coping: one stone per hex edge, or per half wall line
		float span = on_line ? 0.8660254 : 1.5;
		float uc = on_line ? span * (floor(u / span) + 0.5) : span * round(u / span);
		float half_w = on_line ? 0.4330127 : 0.5;
		float jd = half_w - abs(u - uc);
		float cy = WD_COPING - below;         // up from its lower joint
		float dtop = below + fc.z;            // down from its top (the cap's edge)
		vec2 key = floor((along * uc + n3.xz * d) * 4.0 + 0.5);
		c = cap_stone(base, vec2(u, v), h21(key + 5.0));
		float jx = 1.0 - smoothstep(mx - fu, mx + fu, jd);
		float jb = 1.0 - smoothstep(my - fv, my + fv, cy);
		float wx = max(0.025, 1.2 * fu);
		float wy = min(max(0.022, 1.2 * fv), 0.04);
		vec2 bx = bevel(jd, mx, wx);
		vec2 bb = bevel(cy, my, wy);
		vec2 bt = bevel(dtop, 0.0, wy);
		float h = bx.x * bb.x * bt.x;
		su = 0.5 * wx * bx.y * -sign(u - uc) * bb.x * bt.x;
		sv = 0.5 * wy * (bb.y * bx.x * bt.x - bt.y * bx.x * bb.x);
		c *= mix(0.8, 1.0, bx.x * bb.x);
		c *= 1.0 + 0.35 * (1.0 - bt.x);       // the lit lip
		c = mix(c, alt, max(jx, jb));
		ao = mix(0.7, 1.0, h) * (1.0 - 0.5 * max(jx, jb));
		edge = (1.0 - bt.x) * (1.0 - jx);    // the lip: part of the wall's outline (WD_EDGE)
	} else if (pat == 21) {
		// rough ashlar. A course is a level tall (0.5), or a band split into two half-level courses; the bands count down
		// from the coping's lower joint, so the course under it is whole (the one at the foot is cut). A span is a hex edge
		// (corner to corner, 1.0) or half a wall line (centre to midpoint, 0.866): the joints keep to its ends and middle.
		float S = on_line ? 0.8660254 : 1.0;
		float H = 0.5 * S;
		float vc = v + WD_COPING;
		float band = floor(vc / 0.5);
		bool thin = h21(vec2(band, 41.0)) < 0.3;
		float sub = thin ? floor((vc - band * 0.5) / 0.25) : 0.0;
		float ch = thin ? 0.25 : 0.5;
		float row = band * 2.0 + sub;
		float ly = vc - band * 0.5 - sub * 0.25;
		float c0 = on_line ? S * (floor(u / S) + 0.5) : 1.5 * round(u / 1.5);   // this span's middle
		float s = u - c0;                                                     // -H .. H
		float pick = h21(floor((along * c0 + n3.xz * d) * 4.0 + 0.5) + vec2(row * 3.0, 5.0));
		// the stone under s: [lo, hi] along the span; an end that is not a joint is a corner it turns (a quoin)
		float lo = -H;
		float hi = H;
		bool lo_j = true;
		bool hi_j = true;
		bool halves = false;
		if (!thin) {
			if (mod(band, 2.0) < 0.5) {
				halves = pick < 0.3;              // a whole span, sometimes split
			} else {
				halves = true;                    // a joint in the middle, a stone turning each corner
				lo_j = s >= 0.0;
				hi_j = s < 0.0;
			}
		} else if (sub < 0.5) {
			halves = pick >= 0.25;               // half spans, sometimes merged
		} else if (s < -0.5 * H) {
			hi = -0.5 * H;                       // a short course: a middle stone, a half span turning each corner
			lo_j = false;
		} else if (s > 0.5 * H) {
			lo = 0.5 * H;
			hi_j = false;
		} else {
			lo = -0.5 * H;
			hi = 0.5 * H;
		}
		if (halves) {
			lo = s < 0.0 ? -H : 0.0;
			hi = s < 0.0 ? 0.0 : H;
		}
		// one colour per stone, hashed by a world-space point of it (a quoin by its corner: the same on both faces)
		float kpos = !lo_j ? lo : (!hi_j ? hi : 0.5 * (lo + hi));
		vec2 key = floor((along * (c0 + kpos) + n3.xz * d) * 4.0 + 0.5) + vec2(row * 7.0, row * 13.0);
		float hb = h21(key);
		vec2 ht = h22(key + 3.7);
		float hh = h21(key + 9.1);
		// rough: the joints wander (from the world position, so both faces of a corner agree) and the corners are chipped
		float wob = vn(vec2(dot(p3.xz, vec2(4.1, 3.3)) + p3.y * 2.0, p3.y * 5.0)) - 0.5;
		float wob2 = vn(vec2(p3.y * 4.0 + 7.0, dot(p3.xz, vec2(3.7, 5.9)))) - 0.5;
		float dl = s - lo;
		float dr = hi - s;
		float ex = min(lo_j ? dl : 9.0, hi_j ? dr : 9.0) + 0.022 * wob;
		float sx = (lo_j && (!hi_j || dl < dr)) ? 1.0 : -1.0;
		float ey = min(ly, ch - ly) + 0.014 * wob2;
		float sy = ly < ch - ly ? 1.0 : -1.0;
		float chip = min(0.012 + 0.03 * ht.x, 0.3 * ch) * step(0.5, h21(key + 2.3));
		float ec = (ex + ey) * 0.7071 - chip;
		// a face seen edge-on packs its stones into a few pixels: their joints and colours fade to their average there (no moire)
		float fx = smoothstep(S / 10.0, S / 5.0, fu);
		float fy = smoothstep(ch / 4.0, ch / 2.0, fv);
		float ff = max(fx, fy);
		hb = mix(hb, 0.5, ff);
		hh = mix(hh, 0.5, ff);
		float mx2 = max(0.018, 0.6 * fu);     // (joints a little wider than the bricks': readable at 1:1)
		float my2 = max(0.018, 0.6 * fv);
		float jx = (1.0 - smoothstep(mx2 - fu, mx2 + fu, ex)) * (1.0 - fx);
		float jy = (1.0 - smoothstep(my2 - fv, my2 + fv, ey)) * (1.0 - fy);
		float jc = (1.0 - smoothstep(mx2 - fu, mx2 + fu, ec)) * (1.0 - ff);
		float mortar = max(max(jx, jy), jc);
		// the bevel: ~1 px at the game's zoom, never more than 0.4 of a short stone's half, slope ~0.75 at any width
		float wx = min(max(0.03, 1.2 * fu), 0.4 * (0.25 * S - mx2));
		float wy = min(max(0.026, 1.2 * fv), 0.4 * (0.5 * ch - my2));
		vec2 bx = mix(bevel(ex, mx2, wx), vec2(1.0, 0.0), fx);
		vec2 by = mix(bevel(ey, my2, wy), vec2(1.0, 0.0), fy);
		float hc = mix(bevel(ec, mx2, wx).x, 1.0, ff);
		float h = bx.x * by.x * hc;
		su = 0.5 * wx * bx.y * sx * by.x + (ht.x - 0.5) * 0.14 * h * (1.0 - ff);
		sv = 0.5 * wy * by.y * sy * bx.x + (ht.y - 0.5) * 0.14 * h * (1.0 - ff);
		// more value and hue between stones than the bricks had: warm and cool ones, light and dark
		vec3 tint = mix(vec3(1.08, 0.98, 0.88), vec3(0.9, 0.98, 1.08), hh);
		c = base * (0.58 + 0.84 * hb) * tint * (0.76 + 0.48 * fbm(vec2(u, v) * 2.3 + vec2(hb * 31.0, hb * 17.0)));
		c *= mix(0.8, 1.0, h);
		c = mix(c, alt, mortar);
		c *= mix(1.0, 0.85, ff);   // (the joints' average)
		ao = mix(0.7, 1.0, h) * (1.0 - 0.5 * mortar);
		// the course under the coping sits in its shadow
		c *= mix(0.6, 1.0, smoothstep(0.0, 0.05, below - WD_COPING));
	} else {
		c = wall_color(pat, vec2(u, v), base, alt, sc, rgh, true);
		c *= mix(0.6, 1.0, smoothstep(0.0, 0.05, below - WD_COPING));
	}
	// the foot of a wall darker, its top a touch lighter
	c *= mix(0.7, 1.0, smoothstep(0.0, 0.45, above)) * (1.0 + 0.1 * (1.0 - smoothstep(0.2, 0.9, below)));
	ao *= mix(0.65, 1.0, smoothstep(0.0, 0.35, above));
	nrm = normalize(n3 - T * su * k - vec3(0.0, 1.0, 0.0) * sv * k);
	c *= clamp(1.0 + 0.55 * (dot(nrm, VKEY) - dot(n3, VKEY)), 0.5, 1.5);
	return c;
}
// A wall cap: the cap's stone in three large slabs per hex, cut on alternate kite lines (centre to the edge midpoints at 0,
// 120 and 240 degrees: never square lines); its bevel ring (out to the full hex) catches the virtual light.
vec3 depth_cap(vec3 base, vec3 alt, vec3 p3, vec3 n3, float fw, float rim, out float ao, out float edge) {
	vec2 hc = hex_center(p3.xz);
	vec2 o = p3.xz - hc;
	float dist = 9.0;
	for (int i = 0; i < 3; i++) {
		float a = radians(120.0 * float(i));
		vec2 dv = vec2(cos(a), sin(a));
		float dd = dot(o, dv) > 0.0 ? abs(o.x * dv.y - o.y * dv.x) : length(o);
		dist = min(dist, dd);
	}
	float sector = floor(mod(degrees(atan(o.y, o.x)) + 360.0, 360.0) / 120.0);
	float h = h21(floor(hc * 4.0 + 0.5) + vec2(sector * 11.0, 3.0));
	vec3 c = cap_stone(base, p3.xz, h);
	fw = max(fw, 1e-4);
	float jw = max(0.012, 0.6 * fw);
	float joint = 1.0 - smoothstep(jw - fw, jw + fw, dist);
	c = mix(c, alt, joint * 0.5);   // (quiet joints: a cap should read as one top, not as floor tiles)
	ao = 1.0 - 0.3 * joint;
	edge = (1.0 - step(0.99, n3.y)) * step(2.5, rim);   // the bevel over a face (_cap_move w = 3): the cap's outline (WD_EDGE)
	return c * clamp(1.0 + 0.55 * (dot(n3, VKEY) - VKEY.y), 0.6, 1.4);
}

void vertex() {
	wface = CUSTOM0;
	if (is_wall && wall_depth > 0.5) {
		if (CUSTOM0.w > 1.5) {
			// a cap vertex (HexMapView._cap_move): the flat top out to WALL_TOP_SCALE, the bevel out to the full hex
			// and down to the face's top; the bevel's normal takes its new slope (0.07 down over 0.07 * INNER out)
			VERTEX += CUSTOM0.xyz;
			if (NORMAL.y < 0.99) {
				vec2 o = normalize(NORMAL.xz);
				NORMAL = normalize(vec3(o.x * 0.07, 0.0606, o.y * 0.07));
			}
		} else {
			VERTEX.y += CUSTOM0.z * CUSTOM0.w;   // a wall-line face's top up to the cap's edge
		}
	}
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	int id = int(UV2.y + 0.5);
	vec3 alb;
	float glow = UV2.x;
	float rgh = rough;
	float spc = spec;
	float ao = 1.0;
	float amb = 1.0;
	float edge = 0.0;
	bool depth = is_wall && wall_depth > 0.5;
	// (screen derivatives taken here, outside the branches: a face's u and height, a cap's XZ)
	vec2 fuv = vec2(fwidth(dot(wp.xz, vec2(-wn.z, wn.x))), fwidth(wp.y));
	float fwc = 0.5 * (fwidth(wp.x) + fwidth(wp.z));
	if (depth) {
		glow = 0.0;   // (the seam round a wall cap is closed: no rim glow)
	}
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
		amb = pr.z > 0.001 ? pr.z : 1.0;   // (an underground row's ambient: FloorMaterials "ambient"; 0 = none set)
		int pat = int(b.a + 0.5);
		if (is_wall && abs(wn.y) < 0.5) {
			vec2 along = vec2(-wn.z, wn.x);
			if (depth) {
				vec3 nrm;
				alb = depth_face(pat, b.rgb, a.rgb, a.a, wp, wn, wface, fuv, rgh, nrm, ao, edge);
				NORMAL = (VIEW_MATRIX * vec4(nrm, 0.0)).xyz;
			} else {
				alb = wall_color(pat, vec2(dot(wp.xz, along), wp.y), b.rgb, a.rgb, a.a, rgh, false);
			}
		} else if (is_wall && pat == 26) {
			// the conservatory's glazing: its cap is a glass roof seen from above (white bars over dark panes), so the
			// glasshouse reads from the camera
			float bar = 1.0 - smoothstep(0.02, 0.035, grid_d(wp.xz + vec2(0.0, 0.3), vec2(0.9, 0.6)));
			float sheen = smoothstep(0.6, 1.0, fract((wp.x - wp.z) * 0.35)) * 0.6;
			alb = mix(b.rgb * (1.2 + sheen * 2.0), a.rgb * 0.8, bar);
			rgh = mix(0.25, 0.7, bar);
			spc = 0.35;
		} else if (depth) {
			alb = depth_cap(cap_base(pat, b.rgb), a.rgb, wp, wn, fwc, wface.w, ao, edge);
		} else if (is_wall) {
			alb = cap_base(pat, b.rgb) * 0.5 * (0.8 + 0.4 * fbm(wp.xz * 3.0));  // the cap of a wall: darker than the floor, like the slate cap
		} else {
			alb = material_color(pat, wp.xz, b.rgb, a.rgb, a.a, rgh);
		}
	}
	AO = ao * amb;
	ALBEDO = alb * COLOR.rgb;
	ROUGHNESS = rgh;
	SPECULAR = spc;
	float k = near_range > 0.0 ? mix(near_gain, 1.0, smoothstep(near_range * 0.5, near_range, length(VERTEX))) : 1.0;
	EMISSION = glow_color * glow_energy * k * glow + WD_EDGE * edge;
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
""" + ShaderHash.GLSL + """
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
		float h = h21(cell);
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
		m.set_shader_parameter("wall_depth", 1.0 if wall_depth else 0.0)
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


## Turn the wall depth look on or off, live: the uniform on every material of the built mesh that has it (the material
## shader's; a restyle's duplicates included, as they are the mesh's materials now). A map without materials (the classic
## slate shader) has nothing to switch.
func set_wall_depth(on: bool) -> void:
	wall_depth = on
	for mi: MeshInstance3D in [mesh_instance, under_instance]:
		if mi == null or mi.mesh == null:
			continue
		var mesh := mi.mesh
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i) as ShaderMaterial
			if m != null and m.get_shader_parameter("m_base") != null:
				m.set_shader_parameter("wall_depth", 1.0 if on else 0.0)


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
## g_top / g_bot are per-vertex glow values. For the wall depth look (Batch.custom) the face runs from `face_top` to
## `face_bot` (INF: this quad's own top / bottom; a face drawn in two quads passes the whole face's), and its top rises
## by `raise` with wall_depth on.
func _side_quad(b: Batch, p0: Vector3, p1: Vector3, y_top: float, y_bot: float, n: Vector3, u0: float, u1: float, col: Color,
		drop: float = 0.0, g_top: float = 0.0, g_bot: float = 0.0, face_top: float = INF, face_bot: float = INF,
		raise: float = 0.0) -> void:
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
	var ft := y_top if face_top == INF else face_top
	var fb := y_bot if face_bot == INF else face_bot
	var top := Vector4(ft, fb, raise, 1.0)
	var bot := Vector4(ft, fb, raise, 0.0)
	b.set_custom_last([top, top, bot, bot])


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
## `wall_c` / `wall_lv` (a wall's cap): its cell and level, so each bevel quad over a face (an outer edge) is marked for the
## wall depth look's outline (`_cap_move`).
func _top_tile(top_b: Batch, center: Vector3, y: float, col: Color, rim: Color, rim_glow: float, world_uv: bool,
		wall_c: Vector2i = Vector2i.ZERO, wall_lv: int = NO_WALL) -> void:
	var pts: Array = []
	var uv: Array = []
	for i in 6:
		var p := _ring_pt(center, i, TOP_SCALE, y)
		pts.append(p)
		uv.append(_uv_for(center, p, world_uv))
	top_b.poly(pts, Vector3.UP, uv, col)
	var moved: Array = []
	for p: Vector3 in pts:
		moved.append(_cap_move(center, p, false))
	top_b.set_custom_last(moved)
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
		var rim_out := wall_lv != NO_WALL and _cap_edge_outer(wall_c, ia - center, ib - center, wall_lv)
		top_b.set_custom_last([_cap_move(center, ia, false, rim_out), _cap_move(center, oa, true, rim_out), _cap_move(center, ob, true, rim_out),
				_cap_move(center, ib, false, rim_out)])


## A wall cap vertex's move with wall_depth on (Batch.custom, w = 2): the flat top's outline (at TOP_SCALE) out to
## WALL_TOP_SCALE, the bevel's outer edge (at BEVEL_SCALE, BEVEL_DROP down) out to the full hex and down to SEAM_DROP,
## where the wall face's top edge is: no gap round the cap, and no seam shows. A point on a wall line (a cut cell's radial
## edge) stays on it, since the move is along its offset from the center.
static func _cap_move(center: Vector3, p: Vector3, outer: bool, rim_out: bool = false) -> Vector4:
	var off := Vector3(p.x - center.x, 0.0, p.z - center.z)
	var w := 3.0 if rim_out else 2.0
	if outer:
		var d := off * (1.0 / BEVEL_SCALE - 1.0)
		return Vector4(d.x, -(SEAM_DROP - BEVEL_DROP), d.z, w)
	var d2 := off * (WALL_TOP_SCALE / TOP_SCALE - 1.0)
	return Vector4(d2.x, 0.0, d2.z, w)


## Whether a wall cap's hex-edge segment (offsets a -> b from cell c's center) has a face under it: something lower across
## either half of it (the wall depth outline marks those bevel quads, w = 3; a groove between two wall tops stays unmarked).
func _cap_edge_outer(c: Vector2i, a: Vector3, b: Vector3, level: int) -> bool:
	var d := _dir_of_offset((a + b) * 0.5)
	for t: float in [0.25, 0.75]:
		var k := Hex.kite_of(a.lerp(b, t))
		if _across(c, k, k == d) < level:
			return true
	return false


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
	_top_tile(top_b, center, y, col, rim, rim_glow, not is_crate, c, cell.level if is_wall else NO_WALL)
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
			_side_quad(side_b, p0, p1, y_top, y_bot + gh, n, 0.0, 1.0, side_col, SEAM_DROP, 0.0, 0.0, y_top, y_bot)
			_side_quad(side_b, p0, p1, y_bot + gh, y_bot, n, 0.0, 1.0, side_col, SEAM_DROP, 0.0, 0.6, y_top, y_bot)
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
func _run_tile(top_b: Batch, center: Vector3, k0: int, count: int, y: float, col: Color, rim: Color, rim_glow: float, seam: Color, world_uv: bool,
		wall_c: Vector2i = Vector2i.ZERO, wall_lv: int = NO_WALL) -> void:
	var outline := _run_outline(k0, count)
	var cap := _cap_outline(k0, count)
	var pts: Array = []
	var uv: Array = []
	for o in cap:
		var p := _kpt(center, o, TOP_SCALE, y)
		pts.append(p)
		uv.append(_uv_for(center, p, world_uv))
	top_b.poly(pts, Vector3.UP, uv, col)
	var moved: Array = []
	for p: Vector3 in pts:
		moved.append(_cap_move(center, p, false))
	top_b.set_custom_last(moved)
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
		var rim_out := wall_lv != NO_WALL and _cap_edge_outer(wall_c, a, b, wall_lv)
		var qmove: Array = [_cap_move(center, ia, false, rim_out), _cap_move(center, oa, true, rim_out), _cap_move(center, ob, true, rim_out),
				_cap_move(center, ib, false, rim_out)]
		top_b.set_custom_last(_ccw_fix(qmove))
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
		_run_tile(top_b, center, int(run[0]), int(run[1]), y, col, rim, 0.12, seam, true, c, top_lv)
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
		# (with wall_depth on its top rises SEAM_DROP to the cap's edge: the cap's flat top runs right to the wall line, so
		# a face SEAM_DROP lower left a slot along every wall line)
		_side_quad(side_b, center, mid, y - SEAM_DROP, bottom_y, n, 0.0, Hex.INNER / Hex.SIZE, side_col, SEAM_DROP, 0.0, 0.0,
				INF, INF, SEAM_DROP)


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
