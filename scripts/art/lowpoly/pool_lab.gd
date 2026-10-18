extends Node3D
## Pool options lab (docs/design/pool-options.md): four ways to put WATER into the hex terrain, on the real terrain look
## (HexMapView with midpoint walls from HexMap.cut_walls(), FloorMaterials, DungeonLook's lights), with the crew for
## scale. Look-dev only: nothing here is used by the game, and every script var is presentation (no gameplay state).
## Scene: scenes/pool_lab.tscn.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/pool_lab.tscn --variant inset [--shot <png>] [--view <name>]
##
## --variant  basin    option A: a sunken basin of hex CELLS (floor cells at levels -2 / -4, a stairs cell as the
##                     shallow-end steps, a ladder at the deep end): the rim follows hex edges
##            inset    option B: a midpoint INSET: the basin cells are WALL cells at level -3, so cut_walls() cuts the
##                     ring around them along midpoint lines (a wall cut downward); inset steps at one end, a ladder,
##                     a shark
##            lab      option C (+B) in a mad-science room: a raised glass shark tank on midpoint lines with a catwalk
##                     and ladder, a green specimen pool (inset) under a gantry, vats, a bench, the escaped specimen
##            flooded  option D: flooded floor: cells one level down with a film of water (wading only), eels, a
##                     burning hero stepping in, steam off a doused one
## --shot <png>   renders every view and writes <base>.png (game) and <base>_<view>.png for the others, then quits
## --view <name>  only that view, written to <png> exactly
## Views (the game camera: ortho yaw 45, pitch -56; size 24 = the game's default zoom; close views are size 9):
##   game   size 24, the whole room
##   close  size 9 on the water's main moment (the swimmer, the shark, the catwalk)
##   edge   size 9 on the way in and out (steps, ladder, the shallow edge)

const PoolProps := preload("res://scripts/art/lowpoly/props/pool_props.gd")

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0          ## CameraRig.SIZE_DEFAULT
const CLOSE_SIZE := 9.0
const VIEWS: Array[String] = ["game", "close", "edge"]
const ROOM_R := 7
const LH := Hex.LEVEL_HEIGHT

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform vec4 shallow_col : source_color = vec4(0.25, 0.8, 0.88, 1.0);
uniform vec4 deep_col : source_color = vec4(0.05, 0.3, 0.42, 1.0);
uniform vec4 glow_col : source_color = vec4(0.4, 0.95, 1.0, 1.0);
uniform float alpha = 0.7;
uniform float glow_gain = 0.5;
uniform float phase = 0.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float t = phase;
	vec2 p = wp.xz;
	float w = sin(p.x * 1.7 + t) + sin(p.y * 2.3 - t * 1.3 + p.x * 0.6) + 0.6 * sin((p.x + p.y) * 3.1 + t * 2.0);
	float band = floor(clamp(w * 0.22 + 0.5, 0.0, 0.999) * 3.0) / 2.0;
	vec3 col = mix(deep_col.rgb, shallow_col.rgb, band);
	float cz = abs(sin(p.x * 2.6 + sin(p.y * 1.9 + t) * 1.5 + t * 0.7) + sin(p.y * 2.9 + sin(p.x * 1.6 - t) * 1.4));
	float lines = 1.0 - smoothstep(0.0, 0.14, cz);
	ALBEDO = col;
	EMISSION = glow_col.rgb * glow_gain * (0.3 + 0.9 * lines);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
	ALPHA = alpha;
}
"""

const TILE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_col : source_color = vec4(0.55, 0.82, 0.86, 1.0);
uniform vec4 grout_col : source_color = vec4(0.9, 0.97, 0.98, 1.0);
uniform float tile = 0.42;
uniform float glow = 0.0;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 uv;
	if (abs(wn.y) > 0.5) { uv = wp.xz; } else { vec2 tg = normalize(vec2(-wn.z, wn.x)); uv = vec2(dot(wp.xz, tg), wp.y); }
	vec2 g = fract(uv / tile);
	float e = min(min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y));
	float line = 1.0 - smoothstep(0.03, 0.08, e);
	ALBEDO = mix(base_col.rgb * COLOR.rgb, grout_col.rgb, line);
	EMISSION = grout_col.rgb * line * glow;
	ROUGHNESS = 0.4;
}
"""

var shot_path := ""
var only_view := ""
var variant := "inset"
var map: HexMap
var camera: Camera3D
var crew: Array[LowPolyModel] = []
var focus := {}                    ## view -> Vector3 camera target
var _water_mats: Array[ShaderMaterial] = []
var _t := 0.0


## Mesh builder for the lab's own surfaces (water, liner, glass): explicit normals, cull disabled materials.
class MB:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()

	func tri(a: Vector3, b: Vector3, d: Vector3, nn: Vector3, col: Color) -> void:
		for p: Vector3 in [a, b, d]:
			v.append(p)
			n.append(nn)
			c.append(col)

	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, nn: Vector3, col: Color) -> void:
		tri(a, b, d, nn, col)
		tri(a, d, e, nn, col)

	func node(mat: Material, shadows: bool = false) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		if v.is_empty():
			return mi
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mi.mesh = m
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	shot_path = _arg(a, "--shot")
	only_view = _arg(a, "--view")
	variant = _arg(a, "--variant", "inset")
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 220.0
	add_child(camera)
	match variant:
		"basin": _build_basin()
		"lab": _build_lab()
		"flooded": _build_flooded()
		_: _build_inset()
	if shot_path != "":
		_run_shots()
	else:
		_prepare("game")


static func _arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := a.find(key)
	if i >= 0 and i + 1 < a.size():
		return a[i + 1]
	return fallback


# --------------------------------------------------------------------------- terrain

## The room (radius ROOM_R, tag room:0) and a corridor off its right-hand side, `special` cells (cell -> [level, type])
## written first, one ring of 3-level wall cells around everything, then cut_walls(), HexMapView and DungeonLook.
func _terrain(floor_mat: int, wall_mat: int, special: Dictionary, lair: bool = false) -> void:
	map = HexMap.new()
	var room_mat := FloorMaterials.pack(floor_mat, wall_mat)
	var corr_mat := FloorMaterials.pack(FloorMaterials.F_CORR_STONE if lair else FloorMaterials.F_CORR_CONCRETE,
			FloorMaterials.W_STONE if lair else FloorMaterials.W_CONCRETE)
	var floor_cells := {}
	for c in Hex.range_cells(Vector2i.ZERO, ROOM_R):
		floor_cells[c] = ["room:0", room_mat]
	for c in Hex.range_cells(Vector2i.ZERO, 14):
		var p := Hex.to_world(c)
		if not floor_cells.has(c) and absf(p.z - 4.5) <= 1.4 and p.x > 8.0:
			floor_cells[c] = ["corridor", corr_mat]
	for c: Vector2i in floor_cells:
		var cell: HexMap.Cell
		if special.has(c):
			var sp: Array = special[c]
			if int(sp[1]) == HexMap.Tile.STAIRS:
				cell = map.set_stairs(c, int(sp[0]), int(sp[2]), int(sp[3]))
			else:
				cell = map.set_cell(c, int(sp[0]), int(sp[1]))
		else:
			cell = map.set_cell(c, 0)
		cell.tag = str(floor_cells[c][0]) if not special.has(c) or int(special[c][1]) != HexMap.Tile.WALL else ""
		cell.mat_id = int(floor_cells[c][1])
	for c: Vector2i in floor_cells:
		for nb in Hex.neighbors(c):
			if not floor_cells.has(nb) and not map.has_cell(nb):
				var w := map.set_cell(nb, 3, HexMap.Tile.WALL)
				w.mat_id = int(floor_cells[c][1])
	map.cut_walls()
	GameWorld.begin(map, self, 1)
	var terrain := HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)


# --------------------------------------------------------------------------- kite regions (midpoint outlines)

static func _kkey(c: Vector2i, k: int) -> Vector3i:
	return Vector3i(c.x, c.y, posmod(k, 6))


## The midpoint region a cluster of cells claims, the way cut_walls() cuts it: every kite of the cluster's cells, and
## for each neighbour of the cluster the two kites that touch it (neighbour d is the corner of kites d - 1 and d).
static func region_of(cluster: Array[Vector2i]) -> Dictionary:
	var out := {}
	var members := {}
	for c in cluster:
		members[c] = true
	for c in cluster:
		for k in 6:
			out[_kkey(c, k)] = true
		for d in 6:
			var nb: Vector2i = c + Hex.DIRS[d]
			if members.has(nb):
				continue
			var back := (d + 3) % 6          # the cluster cell is neighbour `back` of nb
			out[_kkey(nb, back - 1)] = true
			out[_kkey(nb, back)] = true
	return out


static func _kite_pts(k3: Vector3i, y: float) -> Array[Vector3]:
	var center := Hex.to_world(Vector2i(k3.x, k3.y))
	center.y = y
	var k := k3.z
	return [center, center + Hex.edge_mid(k), center + Hex.kite_corner(k), center + Hex.edge_mid((k + 1) % 6)]


## Centre of the triangle of hex centres a kite belongs to (kite k of c is its share of (c, c + DIRS[k], c + DIRS[k+1])).
static func _tri_centroid(k3: Vector3i) -> Vector3:
	var c := Vector2i(k3.x, k3.y)
	return (Hex.to_world(c) + Hex.to_world(c + Hex.DIRS[k3.z]) + Hex.to_world(c + Hex.DIRS[(k3.z + 1) % 6])) / 3.0


static func _kite_centroid(k3: Vector3i) -> Vector3:
	var p := _kite_pts(k3, 0.0)
	return (p[0] + p[1] + p[2] + p[3]) * 0.25


## The shared edges of a kite with its four neighbouring kites: [a, b, neighbour key] (spokes inside the cell, half
## edges across the hex edges).
static func _kite_edges(k3: Vector3i) -> Array:
	var c := Vector2i(k3.x, k3.y)
	var k := k3.z
	var center := Hex.to_world(c)
	var mid0 := center + Hex.edge_mid(k)
	var mid1 := center + Hex.edge_mid((k + 1) % 6)
	var cor := center + Hex.kite_corner(k)
	return [
		[center, mid0, _kkey(c, k - 1)],
		[center, mid1, _kkey(c, k + 1)],
		[mid0, cor, _kkey(c + Hex.DIRS[k], k + 2)],
		[cor, mid1, _kkey(c + Hex.DIRS[(k + 1) % 6], k + 4)],
	]


## Boundary segments of a region: [a, b, out] where `out` is the horizontal unit normal pointing out of the region.
static func outline(region: Dictionary) -> Array:
	var segs: Array = []
	for k3: Vector3i in region:
		var inside := _kite_centroid(k3)
		for e: Array in _kite_edges(k3):
			if region.has(e[2]):
				continue
			var a: Vector3 = e[0]
			var b: Vector3 = e[1]
			var t := (b - a).normalized()
			var nn := Vector3(-t.z, 0, t.x)
			if nn.dot(inside - a) > 0.0:
				nn = -nn
			segs.append([a, b, nn])
	return segs


func _water_mat(shallow: Color, deep: Color, glow: Color, alpha: float, gain: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("shallow_col", shallow)
	m.set_shader_parameter("deep_col", deep)
	m.set_shader_parameter("glow_col", glow)
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("glow_gain", gain)
	m.set_shader_parameter("phase", 1.3)
	m.render_priority = 1
	_water_mats.append(m)
	return m


func _tile_mat(base: Color, grout: Color, tile: float, glow: float = 0.0) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = TILE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("base_col", base)
	m.set_shader_parameter("grout_col", grout)
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("glow", glow)
	return m


## An inset basin over a kite region: tiled floor at floor_of(kite) (risers between kites at different depths), tiled
## liner walls on the outline from the floor up to `top`, a water surface at `water_y` with a foam line along the rim,
## and a stone coping on the deck side. Returns the outline.
func _inset_basin(region: Dictionary, floor_of: Callable, top: float, water_y: float, liner: ShaderMaterial,
		water: ShaderMaterial, coping: Color, foam: Color) -> Array:
	var segs := outline(region)
	var fl := MB.new()
	var wa := MB.new()
	var nose := MB.new()
	for k3: Vector3i in region:
		var y: float = floor_of.call(k3)
		var p := _kite_pts(k3, y)
		fl.quad(p[0], p[1], p[2], p[3], Vector3.UP, Color.WHITE)
		var q := _kite_pts(k3, water_y)
		wa.quad(q[0], q[1], q[2], q[3], Vector3.UP, Color.WHITE)
		# risers toward shallower neighbours inside the region
		for e: Array in _kite_edges(k3):
			if not region.has(e[2]):
				continue
			var y2: float = floor_of.call(e[2])
			if y2 <= y + 0.001:
				continue
			var a: Vector3 = e[0]
			var b: Vector3 = e[1]
			fl.quad(Vector3(a.x, y2, a.z), Vector3(b.x, y2, b.z), Vector3(b.x, y, b.z), Vector3(a.x, y, a.z), Vector3.UP.cross(b - a).normalized(), Color(0.3, 0.42, 0.7))
			# a bright nosing strip on the edge of the higher tread, so the steps read through the water
			var into := (_kite_centroid(e[2]) - (a + b) * 0.5)
			into.y = 0.0
			into = into.normalized() * 0.14
			nose.quad(Vector3(a.x, y2 + 0.01, a.z), Vector3(b.x, y2 + 0.01, b.z), Vector3(b.x, y2 + 0.01, b.z) + into, Vector3(a.x, y2 + 0.01, a.z) + into, Vector3.UP, Color(1.0, 1.0, 1.0))
	for s: Array in segs:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var out: Vector3 = s[2]
		var inset := -out * 0.012
		var ya: float = floor_of.call(_region_kite_at(region, a, b, out))
		fl.quad(Vector3(a.x, top, a.z) + inset, Vector3(b.x, top, b.z) + inset, Vector3(b.x, ya, b.z) + inset, Vector3(a.x, ya, a.z) + inset, -out, Color(0.92, 0.92, 0.92))
	add_child(fl.node(liner, true))
	add_child(wa.node(water))
	var nmat := StandardMaterial3D.new()
	nmat.albedo_color = Color(0.95, 0.97, 1.0)
	nmat.emission_enabled = true
	nmat.emission = Color(0.5, 0.6, 0.65)
	nmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(nose.node(nmat))
	# foam line and coping
	var fm := MB.new()
	for s: Array in segs:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var out: Vector3 = s[2]
		var y := water_y + 0.006
		fm.quad(Vector3(a.x, y, a.z), Vector3(b.x, y, b.z), Vector3(b.x, y, b.z) - out * 0.12, Vector3(a.x, y, a.z) - out * 0.12, Vector3.UP, foam)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.vertex_color_use_as_albedo = true
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(fm.node(fmat))
	_coping(segs, top, coping)
	return segs


## The kite of `region` that lies on the inner side of the outline segment (a, b) with outward normal `out`.
static func _region_kite_at(region: Dictionary, a: Vector3, b: Vector3, out: Vector3) -> Vector3i:
	var probe := (a + b) * 0.5 - out * 0.05
	var c := Hex.from_world(probe)
	var k := Hex.kite_of(probe - Hex.to_world(c))
	var key := _kkey(c, k)
	if region.has(key):
		return key
	for k3: Vector3i in region:
		return k3
	return key


## A stone coping along the outline, on the deck side, its top just above `top`: the game's mitred coping (PoolView), so
## the corners meet on one seam (the lab's first version used overlong boxes that crossed at every corner).
func _coping(segs: Array, top: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for sg: Array in segs:
		for p: Vector3 in [sg[0], sg[1]]:
			pts.append(Vector2(p.x, p.z))
	var hull := PoolGeo._clean_hull(Geometry2D.convex_hull(pts))
	var outline: Array = []
	for p in hull:
		outline.append(p)
	var mi := MeshInstance3D.new()
	mi.mesh = PoolView.coping_mesh(outline, top, col, col.darkened(0.15), false)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.55
	mi.material_override = mat
	add_child(mi)


# --------------------------------------------------------------------------- placing things

func _put(node: Node3D, pos: Vector3, yaw: float = 0.0) -> Node3D:
	add_child(node)
	node.position = pos
	node.rotation_degrees.y = yaw
	return node


## Yaw that turns a model whose FRONT is +Z toward the X/Z direction v.
static func yaw_to(v: Vector3) -> float:
	return rad_to_deg(atan2(v.x, v.z))


## A crew member at pos facing the X/Z direction `face` (the hero models face -Z).
func _hero(which: String, pos: Vector3, face: Vector3, tilt: float = 0.0) -> LowPolyModel:
	var m: LowPolyModel
	match which:
		"gasket": m = GasketModel.new()
		"rebar": m = RebarModel.new()
		_: m = WickModel.new()
	add_child(m)
	m.idle_enabled = false
	m.apply_idle(0.6)
	m.position = pos
	m.rotation_degrees = Vector3(tilt, rad_to_deg(atan2(-face.x, -face.z)), 0)
	crew.append(m)
	return m


## A hero's height from its meshes (world AABB, standing at y = 0).
func _height(m: Node3D) -> float:
	var lo := INF
	var hi := -INF
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		lo = minf(lo, box.position.y)
		hi = maxf(hi, box.end.y)
	return maxf(0.5, hi - lo)


## Put a hero in deep water: treading water with the head and shoulders out, a ripple ring round them.
func _swimmer(which: String, xz: Vector3, face: Vector3, water_y: float) -> LowPolyModel:
	var m := _hero(which, Vector3(xz.x, 0, xz.z), face, -12.0)
	var h := _height(m)
	m.position.y = water_y - h * 0.62
	_put(PoolProps.build("ripple", {"radius": 0.55}), Vector3(xz.x, water_y + 0.01, xz.z))
	return m


func _light(pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.light_specular = 0.4
	l.shadow_enabled = false
	add_child(l)


static func _w(q: int, r: int, y: float = 0.0) -> Vector3:
	var p := Hex.to_world(Vector2i(q, r))
	p.y = y
	return p


## Prints what today's HexMap rules say about stepping across the water's edge (from -> to: ground levels, Move).
func _probe(label: String, hops: Array) -> void:
	for h: Array in hops:
		var a: Vector3 = h[0]
		var b: Vector3 = h[1]
		print("probe %s %s (lv %s) -> %s (lv %s): %s" % [label, a, map.ground_level(a), b, map.ground_level(b),
				["OK", "CLIMB", "BLOCKED"][map.movement_check(a, b)]])


# --------------------------------------------------------------------------- A: hex-cell basin

func _build_basin() -> void:
	var water_y := -0.3
	var special := {}
	var pool: Array[Vector2i] = []
	for c in Hex.range_cells(Vector2i.ZERO, 4):
		var p := Hex.to_world(c)
		if absf(p.x) <= 4.4 and absf(p.z) <= 1.6:
			pool.append(c)
	var stair := Vector2i(-2, 0)
	for c in pool:
		var p := Hex.to_world(c)
		if c == stair:
			special[c] = [-2, HexMap.Tile.STAIRS, 3, 2]   # level -2, climbing toward DIRS[3] (west), rise 2
		elif p.x < -1.0:
			special[c] = [-2, HexMap.Tile.FLOOR]          # shallow end: 0.7 deep
		else:
			special[c] = [-4, HexMap.Tile.FLOOR]          # deep end: 1.7 deep
	_terrain(FloorMaterials.F_POOL_TILE, FloorMaterials.W_CONCRETE, special)
	_probe("basin", [[Vector3(4.45, 0, 0), Vector3(4.2, 0, 0)], [Vector3(4.2, 0, 0), Vector3(4.45, 0, 0)],
			[Vector3(-2.165, 0, 2.15), Vector3(-2.165, 0, 2.35)], [Vector3(-2.165, 0, 2.35), Vector3(-2.165, 0, 2.15)]])
	# the water: a full hex over every pool cell (the rim is the hex edges, the cliff sides are the pool walls)
	var wa := MB.new()
	for c in pool:
		var ctr := Hex.to_world(c)
		ctr.y = water_y
		for i in 6:
			wa.tri(ctr, ctr + Hex.corner(i), ctr + Hex.corner((i + 1) % 6), Vector3.UP, Color.WHITE)
	add_child(wa.node(_water_mat(Color(0.3, 0.85, 0.92), Color(0.05, 0.32, 0.45), Color(0.45, 0.95, 1.0), 0.66, 0.45)))
	# ladder at the deep (east) end: on the hex edge between the last deep cell and the deck
	var east := Vector2i(2, 0)
	var lad := Hex.to_world(east) + Hex.edge_mid(0)
	_put(PoolProps.build("ladder", {"depth": 2.0}), lad + Vector3(-0.05, 0, 0), -90.0)
	# loungers along the north and south sides, facing the water
	for x: float in [-3.0, 0.0, 3.0]:
		_put(DecorModels.build("pool_lounger"), Vector3(x, 0, -3.9), 0.0)
	for x: float in [-1.6, 1.6]:
		_put(DecorModels.build("pool_lounger"), Vector3(x, 0, 3.9), 180.0)
	_put(PoolProps.build("lifebuoy"), Vector3(5.6, 0.08, 2.4), 20.0)
	_put(DecorModels.build("wet_floor_sign"), Vector3(-5.6, 0, 1.8), 45.0)
	# the infestation layer: jellyfish glowing down in the deep end
	for p: Vector3 in [Vector3(0.6, -1.05, -0.4), Vector3(2.4, -1.25, 0.6), Vector3(1.4, -0.95, 1.0)]:
		_put(PoolProps.build("jellyfish"), p, 0.0)
	# crew: Rebar on the deck by the ladder, Gasket wading in the shallow end, Wick treading water in the deep end
	_hero("rebar", Vector3(5.9, 0, 0.5), Vector3(-1, 0, -0.2))
	_hero("gasket", _w(-1, 1, -1.0) + Vector3(0.2, 0, -0.3), Vector3(1, 0, -0.2))
	_put(PoolProps.build("ripple", {"radius": 0.5}), _w(-1, 1, water_y + 0.01) + Vector3(0.2, 0, -0.3))
	_swimmer("wick", Vector3(1.0, 0, 0.0), Vector3(1, 0, 1), water_y)
	focus = {"game": Vector3(0, 0, 0.5), "close": Vector3(1.2, -0.2, 0.3), "edge": Vector3(-3.0, -0.3, 0.6)}


# --------------------------------------------------------------------------- B: midpoint inset

func _build_inset() -> void:
	var water_y := -0.3
	var cluster: Array[Vector2i] = []
	for q in range(-2, 3):
		cluster.append(Vector2i(q, 0))
	for q in range(-3, 2):
		cluster.append(Vector2i(q, 1))
	var special := {}
	for c in cluster:
		special[c] = [-3, HexMap.Tile.WALL]   # a WALL cell BELOW the floor: cut_walls cuts its ring along midpoint lines
	_terrain(FloorMaterials.F_POOL_TILE, FloorMaterials.W_CONCRETE, special)
	_probe("inset", [[Vector3(0, 0, -1.6), Vector3(0, 0, -1.4)], [Vector3(0, 0, -1.4), Vector3(0, 0, -1.6)]])
	var region := region_of(cluster)
	# inset steps on the far (north) side of the west half: whole triangles of hex centres step down, so every tread
	# edge is a midpoint line (straight, 0 / 60 / 120 degrees) like the walls
	var floor_of := func(k3: Vector3i) -> float:
		var tc := _tri_centroid(k3)
		if tc.x < 0.2:
			if tc.z < 0.0:
				return -0.5
			if tc.z < 1.5:
				return -1.0
		return -1.5
	var liner := _tile_mat(Color(0.55, 0.85, 0.9), Color(0.92, 0.98, 1.0), 0.42)
	var water := _water_mat(Color(0.3, 0.86, 0.93), Color(0.04, 0.3, 0.44), Color(0.45, 0.95, 1.0), 0.56, 0.4)
	_inset_basin(region, floor_of, 0.0, water_y, liner, water, Color(0.88, 0.86, 0.8), Color(0.85, 0.98, 1.0))
	_put(PoolProps.build("drain_grate"), Vector3(1.0, -1.49, 0.8), 15.0)
	# a ladder on the near (south) side and hand rails down the steps
	var lad_p := Vector3(1.73, 0, 3.0)
	_put(PoolProps.build("ladder", {"depth": 1.5}), lad_p + Vector3(0, 0, -0.05), 180.0)
	_put(PoolProps.build("stair_rail", {"length": 1.5, "drop": 0.9}), Vector3(-0.2, 0, -1.75), 0.0)
	# the shark, fin up, cruising the deep end
	var shark_p := Vector3(2.4, water_y - 0.18, 0.7)
	_put(PoolProps.build("shark"), shark_p, -70.0)
	_put(PoolProps.build("ripple", {"radius": 0.42}), Vector3(shark_p.x + 0.02, water_y + 0.01, shark_p.z))
	_put(PoolProps.build("hazard_sign"), Vector3(4.6, 0, -2.6), yaw_to(Vector3(1, 0, 1)))
	_put(DecorModels.build("pool_lounger"), Vector3(-1.5, 0, -3.3), 0.0)
	_put(DecorModels.build("pool_lounger"), Vector3(0.6, 0, -3.3), 0.0)
	_put(PoolProps.build("lifebuoy"), Vector3(4.4, 0.08, 3.6), 10.0)
	# crew: Rebar on the deck at the edge, Gasket on the steps (wading), Wick swimming for the ladder
	_hero("rebar", Vector3(6.9, 0, 1.6), Vector3(-1, 0, -0.1))
	_hero("gasket", Vector3(-2.2, -1.0, 0.75), Vector3(1, 0, 0.6))
	_put(PoolProps.build("ripple", {"radius": 0.5}), Vector3(-2.2, water_y + 0.01, 0.75))
	_swimmer("wick", Vector3(1.2, 0, 2.35), Vector3(0.3, 0, 1), water_y)
	focus = {"game": Vector3(0, 0, 1.0), "close": Vector3(1.4, -0.3, 1.6), "edge": Vector3(-1.8, -0.5, 0.4)}


# --------------------------------------------------------------------------- C (+B): mad-science lab

func _build_lab() -> void:
	var water_y := -0.25
	# the specimen pool: an inset (option B) in the front right
	var spool: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2)]
	var special := {}
	for c in spool:
		special[c] = [-3, HexMap.Tile.WALL]
	_terrain(FloorMaterials.F_LAB_TILE, FloorMaterials.W_STONE, special, true)
	var region := region_of(spool)
	var liner := _tile_mat(Color(0.32, 0.42, 0.38), Color(0.5, 1.0, 0.45), 0.36, 0.6)
	var toxic := _water_mat(Color(0.45, 1.0, 0.35), Color(0.05, 0.3, 0.12), Color(0.5, 1.0, 0.35), 0.72, 0.8)
	_inset_basin(region, func(_k: Vector3i) -> float: return -1.5, 0.0, water_y, liner, toxic,
			Color(0.62, 0.66, 0.66), Color(0.75, 1.0, 0.6))
	# the gantry over it, its cage dipped into the vat
	var pc := (Hex.to_world(spool[0]) + Hex.to_world(spool[1])) * 0.5
	_put(PoolProps.build("gantry", {"span": 6.4, "height": 3.4}), pc + Vector3(-0.6, 0, 0), 0.0)
	# the escaped specimen hauling itself out over the rim
	_put(PoolProps.build("specimen"), pc + Vector3(1.0, -0.35, 1.6), yaw_to(Vector3(0.3, 0, 1)))
	_put(PoolProps.build("ripple", {"radius": 0.8}), pc + Vector3(1.0, water_y + 0.01, 1.2))
	# the raised shark tank: glass on the midpoint lines round two cells at the back
	var tank: Array[Vector2i] = [Vector2i(-1, -2), Vector2i(0, -2)]
	var tregion := region_of(tank)
	var tsegs := outline(tregion)
	var t_top := 2.3
	var t_water := 2.0
	var t_floor := 0.3
	# tank floor (dark gravel) and water surface + water walls just inside the glass
	var fl := MB.new()
	var wa := MB.new()
	for k3: Vector3i in tregion:
		var p := _kite_pts(k3, t_floor)
		fl.quad(p[0], p[1], p[2], p[3], Vector3.UP, Color.WHITE)
		var q := _kite_pts(k3, t_water)
		wa.quad(q[0], q[1], q[2], q[3], Vector3.UP, Color.WHITE)
	for s: Array in tsegs:
		var a: Vector3 = s[0] - s[2] * 0.03
		var b: Vector3 = s[1] - s[2] * 0.03
		wa.quad(Vector3(a.x, t_water, a.z), Vector3(b.x, t_water, b.z), Vector3(b.x, t_floor, b.z), Vector3(a.x, t_floor, a.z), s[2], Color.WHITE)
	add_child(fl.node(_tile_mat(Color(0.2, 0.24, 0.26), Color(0.1, 0.12, 0.13), 0.3)))
	add_child(wa.node(_water_mat(Color(0.25, 0.75, 0.9), Color(0.04, 0.22, 0.36), Color(0.4, 0.9, 1.0), 0.5, 0.5)))
	# the glass
	var gl := MB.new()
	for s: Array in tsegs:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		gl.quad(Vector3(a.x, t_top, a.z), Vector3(b.x, t_top, b.z), Vector3(b.x, t_floor, b.z), Vector3(a.x, t_floor, a.z), s[2], Color.WHITE)
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.75, 0.95, 1.0, 0.16)
	gmat.roughness = 0.05
	gmat.metallic_specular = 1.0
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gmat.render_priority = 2
	add_child(gl.node(gmat))
	# the steel frame: a plinth, posts on the hex centres (the outline's corners), a top rim
	var fr := LowPoly.Soup.new(3, 0.03)
	var seen := {}
	for s: Array in tsegs:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var out: Vector3 = s[2]
		var seg_len := a.distance_to(b)
		var mid := (a + b) * 0.5
		var yaw := rad_to_deg(atan2(out.x, out.z))
		PropModels.box(fr, Vector3(seg_len + 0.1, t_floor, 0.22), Vector3(mid.x, t_floor * 0.5, mid.z) + out * 0.05, PoolProps.STEEL_DK, Vector3(0, yaw, 0))
		PropModels.box(fr, Vector3(seg_len + 0.1, 0.12, 0.16), Vector3(mid.x, t_top + 0.03, mid.z), PoolProps.HAZARD, Vector3(0, yaw, 0))
		for p: Vector3 in [a, b]:
			var key := Vector2i(roundi(p.x * 100.0), roundi(p.z * 100.0))
			var cc := Hex.from_world(p)
			if seen.has(key) or Hex.to_world(cc).distance_to(Vector3(p.x, 0, p.z)) > 0.01:
				continue
			seen[key] = true
			PropModels.box(fr, Vector3(0.16, t_top + 0.1, 0.16), Vector3(p.x, (t_top + 0.1) * 0.5, p.z), PoolProps.STEEL)
	var frm := MeshInstance3D.new()
	frm.mesh = fr.to_mesh()
	frm.material_override = MonsterMaterial.make(1.8)
	add_child(frm)
	# the shark inside, and bubbles
	var tc := (Hex.to_world(tank[0]) + Hex.to_world(tank[1])) * 0.5
	_put(PoolProps.build("shark"), tc + Vector3(0.2, 1.55, 0.25), 95.0)
	# the catwalk over the tank (deck 2.8 up) and the ladder up to it at the east end
	var cw_y := 2.8
	var cw := PoolProps.build("catwalk", {"length": 7.4})
	_put(cw, tc + Vector3(-0.6, cw_y, -1.0), 90.0)
	for x: float in [-3.9, 2.7]:
		var leg := LowPoly.Soup.new(2, 0.0)
		PropModels.box(leg, Vector3(0.14, cw_y, 0.14), Vector3(0, cw_y * 0.5, -0.55), PoolProps.HAZARD)
		PropModels.box(leg, Vector3(0.14, cw_y, 0.14), Vector3(0, cw_y * 0.5, 0.55), PoolProps.HAZARD)
		var lm := MeshInstance3D.new()
		lm.mesh = leg.to_mesh()
		lm.material_override = MonsterMaterial.make(1.6)
		_put(lm, tc + Vector3(x, 0, -1.0), 0.0)
	var lad := PoolProps.build("ladder", {"depth": cw_y})
	_put(lad, tc + Vector3(3.4, cw_y, -1.0), -90.0)
	_put(PoolProps.build("hazard_sign"), tc + Vector3(-1.6, 0, 2.1), yaw_to(Vector3(1, 0, 1)))
	# the rest of the lab: vats, bench, console, shelves, pipes, sign
	_put(PropModels.build("specimen_vat"), Vector3(-6.6, 0, 2.6), yaw_to(Vector3(1, 0, 0.2)))
	_put(PropModels.build("specimen_vat"), Vector3(-6.2, 0, 5.2), yaw_to(Vector3(1, 0, -0.3)))
	_put(PropModels.build("specimen_vat"), Vector3(6.6, 0, -4.4), yaw_to(Vector3(-0.5, 0, 1)))
	_put(PoolProps.build("lab_bench"), Vector3(-3.2, 0, 4.6), yaw_to(Vector3(0.3, 0, -1)))
	_put(PropModels.build("doomsday_console"), Vector3(4.9, 0, -6.6), yaw_to(Vector3(0, 0, 1)))
	_put(DecorModels.build("specimen_shelf"), Vector3(-8.6, 0, -1.0), yaw_to(Vector3(1, 0, 0.3)))
	_put(PoolProps.build("pipe_run", {"length": 5.0}), Vector3(-0.8, 0, -9.9), 0.0)
	_put(DecorModels.build("neon_sign", {"text": "LAB", "color": Color(0.35, 1.0, 0.5), "dead": []}), Vector3(1.9, 0.3, -10.3), 0.0)
	# crew: Wick on the catwalk over the shark, Gasket at the foot of the ladder, Rebar at the specimen pool
	_hero("wick", tc + Vector3(-0.6, cw_y, -1.0), Vector3(0.4, 0, 1))
	_hero("gasket", tc + Vector3(4.1, 0, -0.4), Vector3(-1, 0, 0.2))
	_hero("rebar", pc + Vector3(-1.0, 0, 2.7), Vector3(0.6, 0, -1))
	_light(pc + Vector3(0, 0.6, 0), Color(0.45, 1.0, 0.4), 2.2, 7.0)
	_light(tc + Vector3(0, 1.2, 0), Color(0.4, 0.85, 1.0), 1.8, 6.0)
	focus = {"game": Vector3(0, 0.6, 0), "close": tc + Vector3(0.3, 1.6, 0.4), "edge": pc + Vector3(0.6, -0.1, 1.2)}


# --------------------------------------------------------------------------- D: flooded floor

func _build_flooded() -> void:
	var water_y := -0.18
	var wet := {}
	for c in Hex.range_cells(Vector2i(-1, 1), 2):
		wet[c] = true
	for c in Hex.range_cells(Vector2i(2, -1), 1):
		wet[c] = true
	wet.erase(Vector2i(-3, 1))
	wet.erase(Vector2i(1, 3))
	var special := {}
	for c: Vector2i in wet:
		special[c] = [-1, HexMap.Tile.FLOOR]
	_terrain(FloorMaterials.F_CONCRETE, FloorMaterials.W_CONCRETE, special)
	var wa := MB.new()
	for c: Vector2i in wet:
		var ctr := Hex.to_world(c)
		ctr.y = water_y
		for i in 6:
			wa.tri(ctr, ctr + Hex.corner(i), ctr + Hex.corner((i + 1) % 6), Vector3.UP, Color.WHITE)
	add_child(wa.node(_water_mat(Color(0.32, 0.62, 0.66), Color(0.1, 0.24, 0.28), Color(0.45, 0.85, 0.95), 0.62, 0.3)))
	# the burst pipe that flooded it, and a valve
	_put(PoolProps.build("pipe_run", {"length": 6.0}), Vector3(-1.0, 0, -9.9), 0.0)
	_put(PoolProps.build("valve_wheel"), Vector3(-4.6, 0, -8.9), 0.0)
	_put(DecorModels.build("wet_floor_sign"), Vector3(-5.0, 0, -1.6), yaw_to(Vector3(1, 0, 1)))
	_put(DecorModels.build("crate_stack"), Vector3(7.4, 0, 0.6), 20.0)
	# eels just under the surface
	_put(PoolProps.build("eel", {"phase": 0.0}), Vector3(-2.0, water_y - 0.12, 2.2), 60.0)
	_put(PoolProps.build("eel", {"phase": 1.8}), Vector3(2.6, water_y - 0.12, -1.6), -110.0)
	# crew: Rebar on fire, running for the water; Gasket just doused (steam); Wick wading
	var rb := _hero("rebar", Vector3(5.0, 0, 3.4), Vector3(-1, 0, -0.5))
	_put(PoolProps.build("flames", {"height": _height(rb), "radius": 0.85}), rb.position, 0.0)
	_light(rb.position + Vector3(0, 1.4, 0), Color(1.0, 0.55, 0.2), 1.6, 4.0)
	_hero("gasket", _w(0, 1, -0.5) + Vector3(0.3, 0, 0.2), Vector3(1, 0, 0.6))
	_put(PoolProps.build("steam"), _w(0, 1, 0.2) + Vector3(0.3, 0, 0.2), 0.0)
	_put(PoolProps.build("ripple", {"radius": 0.45}), _w(0, 1, water_y + 0.01) + Vector3(0.3, 0, 0.2))
	_hero("wick", _w(-2, 2, -0.5), Vector3(1, 0, -0.2))
	_put(PoolProps.build("ripple", {"radius": 0.4}), _w(-2, 2, water_y + 0.01))
	focus = {"game": Vector3(0, 0, 0.5), "close": _w(0, 1) + Vector3(0.8, 0, 0.6), "edge": Vector3(3.6, 0, 2.6)}


# --------------------------------------------------------------------------- views

func _prepare(view: String) -> void:
	var close := view != "game"
	var tgt: Vector3 = focus.get(view, Vector3.ZERO)
	_aim(GAME_YAW, GAME_PITCH, CLOSE_SIZE if close else GAME_SIZE, tgt)


func _aim(yaw_deg: float, pitch_deg: float, size: float, tgt: Vector3) -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	camera.size = size
	camera.global_position = tgt + Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * 60.0
	camera.look_at(tgt, Vector3.UP)


func _run_shots() -> void:
	for i in 10:
		await get_tree().process_frame
	var base := shot_path.get_basename()
	var list: Array[String] = []
	if only_view == "":
		list.append_array(VIEWS)
	else:
		list.append(only_view)
	for v in list:
		_prepare(v)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var out := shot_path if only_view != "" else ("%s.png" % base if v == "game" else "%s_%s.png" % [base, v])
		var img := get_viewport().get_texture().get_image()
		print("shot ", out, " ", img.save_png(out), " ", img.get_size())
	get_tree().quit()


func _process(delta: float) -> void:
	if shot_path != "":
		return
	_t += delta
	for m in _water_mats:
		m.set_shader_parameter("phase", 1.3 + _t * 0.6)
