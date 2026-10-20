extends Node3D
## Sewer lab (docs/design/sewer-concept.md): what connected sewer rooms with FLOODED HALLS between them could look like, on
## the game's real terrain drawing (HexMap with midpoint walls, HexMapView, DungeonLook) with the crew for scale. LOOK-DEV
## ONLY: nothing here is used by the game, nothing declares gameplay state, and the game's generator, PoolGeo and PoolView
## are untouched. The water is faked in the lab:
##   - a hand-made HexMap: hex-blob rooms joined by corridors cut the way DungeonGen cuts them (narrow: the route and its
##     neighbours, 3.0 between the wall lines; wide: route + one lane, 4.5; "main": route + two lanes, 6.0);
##   - WET cells are sunk one level (the channel floor, like a pool floor); a wet full cell is a pool BASIN cell and a dry
##     full cell next to one is a RING cell whose kites toward the water are pool floor (PoolGeo's rule), so every rim runs
##     on a midpoint line and HexMapView draws its liner. A wet CUT cell (against a wall) is just sunk: its floor half
##     goes down, its wall stays, so the water runs to the wall;
##   - the lab draws the water itself (one kite fan per wet kite, a flowing murky shader), the foam along every edge of
##     the water, a stone kerb along every rim, and restyles the terrain's materials per look (a lab brick pattern).
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/sewer_lab.tscn --case rooms --shot <png> [--look brick|concrete|toxic] [--view <name>]
##
## --case
##   rooms     two sewer rooms (a cistern and an outfall room) joined by a flooded narrow corridor (3.0)
##   hall      a wide hallway (4.5) flooded on one side, a 1.5 ledge walkway along the other
##   main      a 6.0 "sewer main" (a new width): a 3.0 channel between two 1.5 ledges
##   junction  a junction chamber where three flooded corridors meet: a drain grate, an outfall pipe, a grate bridge, pipes
##   fog       the rooms case under the game's room fog, look A (RoomFog + FogView): the crew in the cistern
##   gator     the hall with a sewer gator in the channel and the crew wading
## --look      brick (Victorian brick, green murk), concrete (storm drain, grey-teal water, sodium light), toxic (lair
##             overflow: dark stone, glowing green water)
## --shot <png>   renders every view of the case: <base>.png (game, size 24) and <base>_<view>.png, then quits
## --view <name>  only that view, written to <png> exactly

const SewerProps := preload("res://scripts/art/lowpoly/props/sewer_props.gd")
const PoolProps := preload("res://scripts/art/lowpoly/props/pool_props.gd")

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const CLOSE_SIZE := 9.0
const LH := Hex.LEVEL_HEIGHT
const WALL_LEVEL := 3
const CH_LEVEL := -1                                  ## the channel floor: one level down, like a pool floor
const FLOOR_Y := CH_LEVEL * LH                        ## -0.5
const SURFACE := FLOOR_Y + HexMap.WATER_DEPTH         ## -0.14: wading depth, as the pools
const FOAM_W := 0.16
const KERB_W := 0.26
const KERB_H := 0.06
const GATOR_SCALE := 1.3                              ## the lab model is 2.3 long; at 1.3 (3.0 long, back 0.5 up) it reads above the murk
const LAB_BRICK := 24                                 ## a wall pattern id the lab adds to the material shader

## The material and lighting looks. Floor / wall entries restyle FloorMaterials' table rows the lab uses (rooms: flagstone
## floors, corridors: corridor stone; walls: rough stone blocks); `wall_pat` LAB_BRICK swaps in the lab's brick.
const LOOKS := {
	"brick": {
		"wall_pat": LAB_BRICK, "wall_base": Color(0.46, 0.25, 0.18), "wall_alt": Color(0.13, 0.11, 0.09),
		"floor_base": Color(0.3, 0.29, 0.26), "corr_base": Color(0.24, 0.24, 0.22), "floor_spec": 0.35, "floor_rough": 0.55,
		"liner": 0, "liner_base": Color(0.42, 0.24, 0.18), "liner_alt": Color(0.12, 0.1, 0.08), "bed": Color(0.16, 0.17, 0.11),
		"slime": Color(0.42, 0.55, 0.2), "slime_glow": 0.0,
		"shallow": Color(0.36, 0.42, 0.2), "deep": Color(0.07, 0.1, 0.05), "glow": Color(0.6, 0.75, 0.25), "alpha": 0.7,
		"glow_gain": 0.18, "foam": Color(0.82, 0.84, 0.66), "scum": Color(0.48, 0.5, 0.26),
		"kerb": Color(0.5, 0.48, 0.44), "light": Color(0.78, 0.92, 0.5), "light_k": 0.62, "ambient": Color(0.42, 0.5, 0.4),
		"ambient_k": 0.5, "key": 0.55, "shaft": Color(0.75, 0.9, 1.0), "seam": 0.85, "pipe": Color(0.5, 0.27, 0.14),
	},
	"concrete": {
		"wall_pat": 20, "wall_base": Color(0.4, 0.41, 0.42), "wall_alt": Color(0.13, 0.13, 0.14),
		"floor_base": Color(0.42, 0.42, 0.41), "corr_base": Color(0.32, 0.33, 0.34), "floor_spec": 0.3, "floor_rough": 0.6,
		"liner": 1, "liner_base": Color(0.4, 0.41, 0.4), "liner_alt": Color(0.98, 0.78, 0.12), "bed": Color(0.18, 0.2, 0.2),
		"slime": Color(0.3, 0.38, 0.32), "slime_glow": 0.0,
		"shallow": Color(0.36, 0.5, 0.5), "deep": Color(0.06, 0.13, 0.15), "glow": Color(0.5, 0.8, 0.85), "alpha": 0.68,
		"glow_gain": 0.2, "foam": Color(0.85, 0.9, 0.9), "scum": Color(0.42, 0.48, 0.45),
		"kerb": Color(0.98, 0.78, 0.12), "light": Color(1.0, 0.62, 0.28), "light_k": 0.75, "ambient": Color(0.5, 0.5, 0.55),
		"ambient_k": 0.5, "key": 0.7, "shaft": Color(0.95, 0.95, 1.0), "seam": 1.0, "pipe": Color(0.35, 0.4, 0.33),
	},
	"toxic": {
		"wall_pat": 21, "wall_base": Color(0.24, 0.23, 0.26), "wall_alt": Color(0.05, 0.05, 0.06),
		"floor_base": Color(0.26, 0.25, 0.27), "corr_base": Color(0.22, 0.22, 0.25), "floor_spec": 0.3, "floor_rough": 0.6,
		"liner": 2, "liner_base": Color(0.26, 0.26, 0.24), "liner_alt": Color(0.06, 0.07, 0.06), "bed": Color(0.08, 0.16, 0.06),
		"slime": Color(0.45, 1.0, 0.3), "slime_glow": 0.7,
		"shallow": Color(0.45, 0.95, 0.3), "deep": Color(0.04, 0.22, 0.08), "glow": Color(0.5, 1.0, 0.35), "alpha": 0.72,
		"glow_gain": 0.75, "foam": Color(0.8, 1.0, 0.6), "scum": Color(0.62, 0.3, 0.75),
		"kerb": Color(0.36, 0.35, 0.36), "light": Color(0.55, 1.0, 0.45), "light_k": 0.45, "ambient": Color(0.35, 0.45, 0.38),
		"ambient_k": 0.45, "key": 0.4, "shaft": Color(0.8, 0.55, 1.0), "seam": 0.6, "pipe": Color(0.3, 0.3, 0.33),
	},
}

var case_name := "rooms"
var look_name := "brick"
var look: Dictionary = LOOKS["brick"]
var shot_path := ""
var only_view := ""
var map: HexMap
var camera: Camera3D
var terrain: HexMapView
var views := {}
var view_order: Array[String] = []
var _cells := {}           ## Vector2i -> tag (rooms "room:N", halls "corridor"), before the map is made
var wet := {}              ## Vector2i -> true: the cells under water (sunk to the channel floor)
var flow_of: Callable      ## world X/Z -> the water's flow direction there (the shader streaks along it)
var fog: RoomFog
var fog_view: FogView
var crew_at: Array[Vector3] = []
var _contents: Array[Node3D] = []    ## things that move (the gator, rats): shown only in a space in view (fog case)
var _props: Array[Node3D] = []       ## everything placed with _put (the fog shows the static ones in view or seen)
var bridges: Array[Dictionary] = []  ## {node, length}: every grate bridge, checked by _check_bridges()


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	case_name = _arg(a, "--case", "rooms")
	var table := _looks()
	look_name = _arg(a, "--look", str(table.keys()[0]))
	look = table.get(look_name, table.values()[0])
	shot_path = _arg(a, "--shot")
	only_view = _arg(a, "--view")
	flow_of = func(_p: Vector2) -> Vector2: return Vector2(1, 0)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 220.0
	add_child(camera)
	call("_case_" + case_name)
	if view_order.is_empty():
		_view("game", GAME_SIZE, Vector3.ZERO)
	if not bridges.is_empty():
		_check_bridges()
	if shot_path != "":
		_run_shots()
	else:
		_prepare(view_order[0])


## The look table (the lava lab, which extends this one, has its own).
func _looks() -> Dictionary:
	return LOOKS


static func _arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := a.find(key)
	if i >= 0 and i + 1 < a.size():
		return a[i + 1]
	return fallback


# --------------------------------------------------------------------------- the map

## A hex-blob room.
func _room(center: Vector2i, radius: int, tag: String) -> void:
	for c in Hex.range_cells(center, radius):
		if not _cells.has(c):
			_cells[c] = tag


## A straight corridor from door cell `a` (a room cell) `n` steps along DIRS[dir] to the door cell at the other end, cut
## the way DungeonGen cuts one: the CORE is the route plus `lanes` lanes beside it (toward DIRS[dir + 1]); every core
## cell gets all six neighbours (the outer ones become cut cells when the walls go in). lanes 0: narrow (3.0 between the
## walls), 1: wide (4.5), 2: a sewer main (6.0, not a width the game deals). Returns the route (door to door).
func _hall(a: Vector2i, dir: int, n: int, lanes: int) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	for i in n + 1:
		route.append(a + Hex.DIRS[dir] * i)
	var core: Array[Vector2i] = route.duplicate()
	for i in range(1, n):
		if not _cells.has(route[i]):
			_cells[route[i]] = "corridor"
		for k in range(1, lanes + 1):
			var lane: Vector2i = route[i] + Hex.DIRS[(dir + 1) % 6] * k
			if _cells.has(lane) and str(_cells[lane]) != "corridor":
				continue      # a room cell
			_cells[lane] = "corridor"
			core.append(lane)
	for k in core:
		for d in Hex.DIRS:
			if not _cells.has(k + d):
				_cells[k + d] = "corridor"
	return route


## The cells (with walls round them, midpoint-cut) in the look's materials: rooms flagstone, halls corridor stone, the
## walls rough stone (all restyled per look in _restyle()).
func _make_map() -> void:
	map = HexMap.new()
	var room_mat := FloorMaterials.pack(FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var corr_mat := FloorMaterials.pack(FloorMaterials.F_CORR_STONE, FloorMaterials.W_STONE)
	for c: Vector2i in _cells:
		var cell := map.set_cell(c, 0)
		cell.tag = str(_cells[c])
		cell.mat_id = corr_mat if cell.tag == "corridor" else room_mat
	for c: Vector2i in _cells:
		for nb in Hex.neighbors(c):
			if not _cells.has(nb) and not map.has_cell(nb):
				map.set_cell(nb, WALL_LEVEL, HexMap.Tile.WALL).mat_id = room_mat
	map.cut_walls()


## Mark cells wet (only floor cells count).
func _flood(list: Array) -> void:
	for c: Vector2i in list:
		if map.has_cell(c) and map.cells[c].type != HexMap.Tile.WALL:
			wet[c] = true


## Every corridor cell of the map is wet (a fully flooded hall), minus `except`.
func _flood_halls(except: Dictionary = {}) -> void:
	for c: Vector2i in map.cells:
		if map.cells[c].tag == "corridor" and not except.has(c):
			_flood([c])


## Sink the wet cells and cut the rims: a wet full cell is a basin cell (pool floor all over), a wet cut cell is just
## sunk (its floor part to the channel floor), and a dry full cell next to water gets pool kites toward it (PoolGeo's
## rule: neighbour d wet -> kites d - 1 and d), so the rim runs through its centre on a midpoint line.
func _apply_water() -> void:
	for c: Vector2i in wet:
		var cell: HexMap.Cell = map.cells[c]
		cell.level = CH_LEVEL
		if cell.wall_mask == 0:
			cell.pool_mask = HexMap.ALL_KITES
			cell.pool_level = CH_LEVEL
	for c: Vector2i in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type == HexMap.Tile.WALL or wet.has(c) or cell.wall_mask != 0:
			continue
		var m := 0
		for d in 6:
			if wet.has(c + Hex.DIRS[d]):
				m |= (1 << d) | (1 << posmod(d - 1, 6))
		if m != 0:
			cell.pool_mask = m
			cell.pool_level = CH_LEVEL


## The wet kites of the map: [cell centre, kite index] for every kite under water.
func _wet_kites() -> Array:
	var out: Array = []
	for c: Vector2i in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type == HexMap.Tile.WALL:
			continue
		var m := 0
		if wet.has(c):
			m = HexMap.ALL_KITES & ~cell.wall_mask
		elif cell.pool_mask != 0:
			m = cell.pool_mask
		for k in 6:
			if (m >> k) & 1 == 1:
				out.append([Hex.to_world(c), k])
	return out


static func _kite_poly(center: Vector3, k: int) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for o: Vector3 in [Vector3.ZERO, Hex.edge_mid(k), Hex.kite_corner(k), Hex.edge_mid((k + 1) % 6)]:
		pts.append(Vector2(center.x + o.x, center.z + o.z))
	return pts


static func _key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 1000.0), roundi(p.y * 1000.0))


# --------------------------------------------------------------------------- the terrain and the water

## Terrain, lights, the water and its foam and kerbs, every material in the look.
func _finish() -> void:
	_apply_water()
	GameWorld.begin(map, self, 1)
	terrain = HexMapView.new()
	terrain.seam_gain = float(look["seam"])
	add_child(terrain)
	terrain.build(map)
	_restyle()
	DungeonLook.apply(self, map)
	_relight()
	_build_water()


## The terrain's materials in the look: FloorMaterials' rows for flagstone, corridor stone and rough stone recoloured (the
## brick look swaps in a lab brick pattern: the material shader's code with one more wall pattern), and the pool surface
## (channel floor and liners) replaced with the lab's channel shader.
func _restyle() -> void:
	var mesh := terrain.mesh_instance.mesh as ArrayMesh
	var tables := FloorMaterials.table_arrays()
	var base: PackedVector4Array = (tables["base"] as PackedVector4Array).duplicate()
	var alt: PackedVector4Array = (tables["alt"] as PackedVector4Array).duplicate()
	var par: PackedVector4Array = (tables["par"] as PackedVector4Array).duplicate()
	var fb: Color = (look["floor_base"] as Color).srgb_to_linear()
	var cb: Color = (look["corr_base"] as Color).srgb_to_linear()
	var wb: Color = (look["wall_base"] as Color).srgb_to_linear()
	var wa: Color = (look["wall_alt"] as Color).srgb_to_linear()
	base[FloorMaterials.F_FLAGSTONE] = Vector4(fb.r, fb.g, fb.b, base[FloorMaterials.F_FLAGSTONE].w)
	base[FloorMaterials.F_CORR_STONE] = Vector4(cb.r, cb.g, cb.b, base[FloorMaterials.F_CORR_STONE].w)
	for f: int in [FloorMaterials.F_FLAGSTONE, FloorMaterials.F_CORR_STONE]:
		par[f] = Vector4(float(look["floor_rough"]), float(look["floor_spec"]), 0.0, 0.0)
	var wi := FloorMaterials.WALL_OFFSET + FloorMaterials.W_STONE
	base[wi] = Vector4(wb.r, wb.g, wb.b, float(look["wall_pat"]))
	alt[wi] = Vector4(wa.r, wa.g, wa.b, alt[wi].w)
	var brick_shader := Shader.new()
	brick_shader.code = HexMapView.MATERIAL_SHADER.replace("\t} else if (pat == 21) {", BRICK_GLSL + "\t} else if (pat == 21) {")
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as ShaderMaterial
		if m == null:
			continue
		if m.shader != null and m.shader.code == HexMapView.POOL_SHADER:
			mesh.surface_set_material(i, _channel_material())
		elif m.get_shader_parameter("m_base") != null:
			var nm := m.duplicate() as ShaderMaterial
			nm.shader = brick_shader
			nm.set_shader_parameter("m_base", base)
			nm.set_shader_parameter("m_alt", alt)
			nm.set_shader_parameter("m_par", par)
			mesh.surface_set_material(i, nm)


## The lab's brick (one more wall pattern for the material shader): a running bond 0.46 x 0.16 with dark mortar, each
## brick a little lighter or darker, and a damp green tide line up to about half a unit over the floor.
const BRICK_GLSL := """	} else if (pat == 24) {               // LAB: sewer brick
		vec2 bs = vec2(0.46, 0.16);
		vec2 q = vec2(u, v) / bs;
		q.x += 0.5 * floor(q.y);
		vec2 bid = floor(q);
		vec2 f = fract(q);
		float ed = min(min(f.x, 1.0 - f.x) * bs.x, min(f.y, 1.0 - f.y) * bs.y);
		float mortar = 1.0 - smoothstep(0.008, 0.024, ed);
		c = base * (0.66 + 0.55 * h21(bid)) * (0.84 + 0.3 * fbm(p * 4.0));
		c = mix(c, alt, mortar);
		float tide = 1.0 - smoothstep(-0.05, 0.45, v);
		c = mix(c, c * vec3(0.5, 0.72, 0.36), tide * 0.75);
"""


const CHANNEL_SHADER := """
shader_type spatial;
uniform vec4 liner_base : source_color;
uniform vec4 liner_alt : source_color;
uniform int liner_pat = 0;
uniform vec4 bed : source_color;
uniform vec4 slime : source_color;
uniform float slime_glow = 0.0;
varying vec3 wp;
varying vec3 wn;
float h21(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 c;
	float em = 0.0;
	if (abs(wn.y) > 0.5) {
		// the channel bed: dark silt, slime blotches
		float n = vn(wp.xz * 1.3) * 0.6 + vn(wp.xz * 4.0) * 0.4;
		c = bed.rgb * (0.7 + 0.6 * n);
		float s = smoothstep(0.55, 0.75, vn(wp.xz * 0.8 + 3.0));
		c = mix(c, slime.rgb * 0.6, s * 0.6);
		em = s * slime_glow;
		ROUGHNESS = 0.6;
	} else {
		vec2 tg = normalize(vec2(-wn.z, wn.x));
		vec2 uv = vec2(dot(wp.xz, tg), wp.y);
		if (liner_pat == 0) {
			vec2 bs = vec2(0.46, 0.16);
			vec2 q = uv / bs;
			q.x += 0.5 * floor(q.y);
			vec2 f = fract(q);
			float ed = min(min(f.x, 1.0 - f.x) * bs.x, min(f.y, 1.0 - f.y) * bs.y);
			c = liner_base.rgb * (0.66 + 0.55 * h21(floor(q)));
			c = mix(c, liner_alt.rgb, 1.0 - smoothstep(0.008, 0.024, ed));
		} else if (liner_pat == 1) {
			// poured concrete with a hazard stripe along the top edge
			c = liner_base.rgb * (0.8 + 0.3 * vn(uv * vec2(0.8, 6.0)));
			float top = smoothstep(-0.08, -0.04, uv.y);
			float stripe = step(0.5, fract((uv.x + uv.y) * 2.2));
			c = mix(c, mix(liner_alt.rgb, vec3(0.05), stripe), top);
		} else {
			vec2 bs = vec2(0.62, 0.31);
			vec2 q = uv / bs;
			q.x += 0.5 * floor(q.y);
			vec2 f = fract(q);
			float ed = min(min(f.x, 1.0 - f.x) * bs.x, min(f.y, 1.0 - f.y) * bs.y);
			c = liner_base.rgb * (0.75 + 0.4 * h21(floor(q)));
			c = mix(c, liner_alt.rgb, 1.0 - smoothstep(0.012, 0.03, ed));
		}
		float tide = 1.0 - smoothstep(-0.3, -0.12, uv.y);
		c = mix(c, slime.rgb * 0.5, tide * 0.7);
		em = tide * slime_glow * 0.5;
		ROUGHNESS = 0.7;
	}
	ALBEDO = c * COLOR.rgb;
	EMISSION = slime.rgb * em;
	SPECULAR = 0.4;
}
"""


func _channel_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = CHANNEL_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("liner_base", look["liner_base"])
	m.set_shader_parameter("liner_alt", look["liner_alt"])
	m.set_shader_parameter("liner_pat", int(look["liner"]))
	m.set_shader_parameter("bed", look["bed"])
	m.set_shader_parameter("slime", look["slime"])
	m.set_shader_parameter("slime_glow", float(look["slime_glow"]))
	return m


## Murky moving water: the pools' banded toon water, darker and more opaque, with scum blotches and foam streaks drawn
## out along the local flow (vertex COLOR.rg carries the flow direction, 0.5 + 0.5 * dir).
const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform vec4 shallow_col : source_color;
uniform vec4 deep_col : source_color;
uniform vec4 glow_col : source_color;
uniform vec4 foam_col : source_color;
uniform vec4 scum_col : source_color;
uniform float alpha = 0.8;
uniform float glow_gain = 0.2;
varying vec3 wp;
varying vec2 flow;
float h21(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow = normalize(COLOR.rg * 2.0 - 1.0 + vec2(0.0001));
}
void fragment() {
	vec2 f = normalize(flow);
	vec2 n = vec2(-f.y, f.x);
	float t = 1.3 + TIME * 0.5;
	vec2 p = wp.xz;
	float along = dot(p, f) - t * 0.8;
	float across = dot(p, n);
	float w = sin(along * 1.6 + sin(across * 1.3) * 0.8) + sin(across * 2.1 + along * 0.5 - t) + 0.5 * sin((along + across) * 3.0 + t * 1.7);
	float band = floor(clamp(w * 0.2 + 0.5, 0.0, 0.999) * 3.0) / 2.0;
	vec3 col = mix(deep_col.rgb, shallow_col.rgb, band * 0.8);
	float scum = smoothstep(0.62, 0.7, vn(vec2(along * 0.45, across * 0.9) + 7.0));
	col = mix(col, scum_col.rgb, scum * 0.7);
	float streak = smoothstep(0.72, 0.8, vn(vec2(along * 0.6, across * 5.5)));
	col = mix(col, foam_col.rgb, streak * 0.55);
	ALBEDO = col;
	EMISSION = glow_col.rgb * glow_gain * (0.4 + 0.8 * band) + foam_col.rgb * streak * 0.08;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	ALPHA = clamp(alpha + scum * 0.15, 0.0, 1.0);
}
"""


## The water surface (a fan per wet kite, the flow in the vertex colour), the foam along every edge of the water (rims
## and walls), and a stone kerb along every rim (the dry side of an edge that is not a wall).
func _build_water() -> void:
	var kites := _wet_kites()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges := {}        ## sorted end keys -> [a, b, inward (toward the water), count]
	for kv: Array in kites:
		var poly := _kite_poly(kv[0], int(kv[1]))
		var cen := (poly[0] + poly[1] + poly[2] + poly[3]) * 0.25
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			for j: int in [tri[0], tri[2], tri[1]]:
				var fl: Vector2 = flow_of.call(poly[j])
				st.set_color(Color(0.5 + 0.5 * fl.x, 0.5 + 0.5 * fl.y, 0.0))
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(poly[j].x, SURFACE, poly[j].y))
		for i in 4:
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % 4]
			var ka := _key(a)
			var kb := _key(b)
			var key := [ka, kb] if (ka.x < kb.x or (ka.x == kb.x and ka.y < kb.y)) else [kb, ka]
			if edges.has(key):
				edges[key][3] = int(edges[key][3]) + 1
			else:
				edges[key] = [a, b, cen, 1]
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = st.commit()
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var wm := ShaderMaterial.new()
	wm.shader = sh
	for k: String in ["shallow", "deep", "glow", "foam", "scum"]:
		wm.set_shader_parameter(k + "_col", look[k])
	wm.set_shader_parameter("alpha", float(look["alpha"]))
	wm.set_shader_parameter("glow_gain", float(look["glow_gain"]))
	wm.render_priority = 1
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# foam strips and kerbs along the boundary edges
	var foam := SurfaceTool.new()
	foam.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kerb := SurfaceTool.new()
	kerb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fc: Color = look["foam"]
	var kc: Color = look["kerb"]
	var kerb_ends := {}     ## vertex key -> Array of outward normals of the rim edges ending there
	for key: Array in edges:
		var e: Array = edges[key]
		if int(e[3]) != 1:
			continue
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var t := (b - a).normalized()
		var n := Vector2(-t.y, t.x)
		var cen: Vector2 = e[2]
		if n.dot(cen - (a + b) * 0.5) < 0.0:
			n = -n      # n points into the water
		var y := SURFACE + 0.006
		var a_in := a + n * FOAM_W
		var b_in := b + n * FOAM_W
		var c0 := Color(fc.r, fc.g, fc.b, 0.85)
		var c1 := Color(fc.r, fc.g, fc.b, 0.0)
		_quad(foam, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(b_in.x, y, b_in.y), Vector3(a_in.x, y, a_in.y), [c0, c0, c1, c1])
		var probe := (a + b) * 0.5 - n * 0.08
		var pc := Hex.from_world(Vector3(probe.x, 0, probe.y))
		var is_wall: bool = not map.has_cell(pc) or map.cells[pc].type == HexMap.Tile.WALL or map.wall_at(Vector3(probe.x, 0, probe.y))
		if is_wall:
			continue
		var top := float(map.cells[pc].level) * LH + KERB_H
		var o := -n
		var a2 := a + o * KERB_W
		var b2 := b + o * KERB_W
		var a1 := a - o * 0.04
		var b1 := b - o * 0.04
		_quad(kerb, Vector3(a1.x, top, a1.y), Vector3(b1.x, top, b1.y), Vector3(b2.x, top, b2.y), Vector3(a2.x, top, a2.y), [kc, kc, kc, kc])
		var dk := kc.darkened(0.25)
		_quad(kerb, Vector3(a1.x, top, a1.y), Vector3(b1.x, top, b1.y), Vector3(b1.x, FLOOR_Y + 0.2, b1.y), Vector3(a1.x, FLOOR_Y + 0.2, a1.y), [dk, dk, dk, dk])
		for v: Vector2 in [a, b]:
			var vk := _key(v)
			if not kerb_ends.has(vk):
				kerb_ends[vk] = [v, top, []]
			(kerb_ends[vk][2] as Array).append(o)
	# fill the outside of each kerb corner: a fan from the corner over the two strips' ends
	for vk: Vector2i in kerb_ends:
		var ent: Array = kerb_ends[vk]
		var ns: Array = ent[2]
		if ns.size() != 2:
			continue
		var v: Vector2 = ent[0]
		var top: float = ent[1]
		var n0: Vector2 = ns[0]
		var n1: Vector2 = ns[1]
		var mid := (n0 + n1).normalized() * KERB_W / maxf(0.3, cos(n0.angle_to(n1) * 0.5))
		var p0 := v + n0 * KERB_W
		var p1 := v + n1 * KERB_W
		var pm := v + mid
		_quad(kerb, Vector3(v.x, top, v.y), Vector3(p0.x, top, p0.y), Vector3(pm.x, top, pm.y), Vector3(p1.x, top, p1.y), [kc, kc, kc, kc])
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.vertex_color_use_as_albedo = true
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.render_priority = 2
	var fmi := MeshInstance3D.new()
	fmi.name = "Foam"
	fmi.mesh = foam.commit()
	fmi.material_override = fm
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fmi)
	var km := StandardMaterial3D.new()
	km.vertex_color_use_as_albedo = true
	km.roughness = 0.75
	km.cull_mode = BaseMaterial3D.CULL_DISABLED
	var kmi := MeshInstance3D.new()
	kmi.name = "Kerb"
	kmi.mesh = kerb.commit()
	kmi.material_override = km
	add_child(kmi)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, cols: Array) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.y < 0.0 or (absf(nrm.y) < 0.01 and false):
		nrm = -nrm
	for idx: int in [0, 1, 2, 0, 2, 3]:
		st.set_color(cols[idx])
		st.set_normal(nrm)
		st.add_vertex([a, b, c, d][idx])


## The look's lighting on top of DungeonLook: dimmer, tinted ambient and key, the downlights recoloured to the look's
## sickly light.
func _relight() -> void:
	for ch in get_children():
		if ch is WorldEnvironment:
			var env := (ch as WorldEnvironment).environment
			env.ambient_light_color = look["ambient"]
			env.ambient_light_energy = float(look["ambient_k"])
		elif ch.name == "KeyLight":
			(ch as DirectionalLight3D).light_energy = float(look["key"])
			(ch as DirectionalLight3D).light_color = (look["light"] as Color).lerp(Color.WHITE, 0.5)
		elif ch.name == "Downlights":
			for l in ch.get_children():
				if l is OmniLight3D:
					(l as OmniLight3D).light_color = look["light"]
					(l as OmniLight3D).light_energy *= float(look["light_k"])


## A light shaft down through a street grate far overhead: a pale additive column and a spot light making a bright patch.
func _shaft(at: Vector3, radius: float = 0.7) -> void:
	var col: Color = look["shaft"]
	var spot := SpotLight3D.new()
	spot.light_color = col
	spot.light_energy = 9.0
	spot.spot_range = 9.0
	spot.spot_angle = 11.0
	spot.shadow_enabled = false
	add_child(spot)
	spot.position = at + Vector3(0.6, 7.0, 0.6)
	spot.look_at(at, Vector3.FORWARD)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * 0.55
	cm.bottom_radius = radius
	cm.height = 6.0
	cm.radial_segments = 10
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color;
varying float h;
void vertex() { h = VERTEX.y / 6.0 + 0.5; }
void fragment() {
	float edge = pow(abs(dot(NORMAL, VIEW)), 1.5);
	ALBEDO = col.rgb;
	ALPHA = 0.16 * (1.0 - h) * edge;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col", col)
	beam.material_override = m
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var tip := at + Vector3(0.6, 6.0, 0.6)
	beam.position = (at + tip) * 0.5
	beam.look_at(tip, Vector3.FORWARD)
	beam.rotate_object_local(Vector3.RIGHT, -PI * 0.5)


# --------------------------------------------------------------------------- placing things

func _put(node: Node3D, pos: Vector3, yaw: float = 0.0) -> Node3D:
	add_child(node)
	_props.append(node)
	node.position = pos
	node.rotation_degrees.y = yaw
	return node


static func yaw_to(v: Vector3) -> float:
	return rad_to_deg(atan2(v.x, v.z))


## A crew member at pos facing the X/Z direction `face` (the hero models face -Z). In the water (pos.y on the channel
## floor) it gets a ripple ring at the surface.
func _hero(which: String, pos: Vector3, face: Vector3) -> LowPolyModel:
	var m: LowPolyModel
	match which:
		"gasket": m = GasketModel.new()
		"rebar": m = RebarModel.new()
		_: m = WickModel.new()
	add_child(m)
	m.idle_enabled = false
	m.apply_idle(0.6)
	m.position = pos
	m.rotation_degrees = Vector3(0, rad_to_deg(atan2(-face.x, -face.z)), 0)
	crew_at.append(pos)
	if pos.y < -0.2:
		_ripple(pos, 0.42)
	return m


func _ripple(pos: Vector3, radius: float) -> Node3D:
	var r := PoolProps.build("ripple", {"radius": radius})
	add_child(r)
	r.position = Vector3(pos.x, SURFACE + 0.012, pos.z)
	return r


## A world point at a cell's centre, on its floor (or on the channel floor when it is wet).
func _at(c: Vector2i, off: Vector3 = Vector3.ZERO) -> Vector3:
	var p := Hex.to_world(c) + off
	p.y = FLOOR_Y if wet.has(Hex.from_world(p)) or map.water_at(p) else 0.0
	return p


## A spot on the hall's ledge walkway beside route cell r: the lane cell's dry half, toward the far wall.
func _ledge(r: Vector2i) -> Vector3:
	var ax := Hex.dir_vector(1)
	var far := Vector3(-ax.z, 0, ax.x)
	if far.dot(Hex.dir_vector(2)) < 0.0:
		far = -far
	var lane_axis := Hex.to_world(r + Hex.DIRS[2]) - Hex.to_world(r)
	return Hex.to_world(r) + far * (lane_axis.dot(far) + 0.45)


## A grate bridge over a channel at `at` (a point in the channel), spanning ACROSS the channel whose flow axis is `axis`:
## the model's length runs along its local X, and a yaw of yaw_to(axis) turns its local Z onto the axis, so X spans from
## bank to bank. (Round 1 added 90 degrees, which laid the bridge along the channel: no crossing.) Every bridge is recorded
## for _check_bridges().
func _bridge_over(at: Vector3, axis: Vector3, length: float, width: float) -> Node3D:
	var yaw := yaw_to(Vector3(axis.x, 0, axis.z).normalized())
	var b := _put(SewerProps.build("grate_bridge", {"length": length, "width": width}), Vector3(at.x, 0.0, at.z), yaw)
	bridges.append({"node": b, "length": length})
	return b


## Every bridge must cross the water: its two ends on DRY floor (not a wet cell, not a pool kite, not a wall), on opposite
## banks (the span between them passes over water). Prints one line per bridge; pushes an error on a failure.
func _check_bridges() -> bool:
	var ok := true
	for i in bridges.size():
		var rec: Dictionary = bridges[i]
		var b: Node3D = rec["node"]
		var half := float(rec["length"]) * 0.5 - 0.12
		var x := b.global_transform.basis.x.normalized()
		var p := b.global_position
		var ends: Array[Vector3] = [p - x * half, p + x * half]
		var dry := _dry_floor(ends[0]) and _dry_floor(ends[1])
		var crosses := false
		for k in range(1, 20):
			if not _dry_floor(ends[0].lerp(ends[1], float(k) / 20.0)):
				crosses = true
		var good := dry and crosses
		ok = ok and good
		print("bridge %d at %s: ends on dry floor %s, spans water %s -> %s" % [i, Hex.from_world(p), dry, crosses, "OK" if good else "FAIL"])
		if not good:
			push_error("sewer lab: bridge %d does not cross the water" % i)
	return ok


## A dry floor point: a floor cell (not a wall or a wall part), not sunk, not over a pool kite.
func _dry_floor(p: Vector3) -> bool:
	var c := Hex.from_world(p)
	if not map.has_cell(c) or map.cells[c].type == HexMap.Tile.WALL or wet.has(c):
		return false
	if map.wall_at(Vector3(p.x, 0.0, p.z)):
		return false
	return not map.water_at(Vector3(p.x, 0.0, p.z))


func _gator(pos: Vector3, yaw: float, bend: float, jaw: float = 0.0) -> Node3D:
	var gt := SewerProps.build("gator", {"bend": bend, "jaw": jaw})
	_put(gt, Vector3(pos.x, FLOOR_Y + 0.16, pos.z), yaw)   # (up on its legs: the back and head ride out of the murk)
	gt.scale = Vector3.ONE * GATOR_SCALE
	var fwd := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
	_contents.append(_ripple(pos + fwd * 0.9, 0.3))
	_contents.append(_ripple(pos - fwd * 0.2, 0.55))
	_contents.append(gt)
	return gt


# --------------------------------------------------------------------------- cases

## Two sewer rooms joined by a flooded narrow corridor (3.0 wall to wall, the whole hall under water). Room A (left) is a
## CISTERN: a hexagonal sump in the middle, its channel running out to the doorway, dry walkway all round. Room B (right,
## two lobes) is an OUTFALL room: the channel crosses it to a big pipe pouring in from the far wall, a grate bridge over
## it. A short dry passage leads on out of B (to room C, off to the side) so the fog case has an unknown space.
func _layout_rooms() -> Dictionary:
	var a0 := Vector2i(-7, 4)
	var b0 := a0 + Hex.DIRS[1] * 16
	_room(a0, 5, "room:0")
	_room(b0, 5, "room:1")
	_room(b0 + Hex.DIRS[0] * 2 + Hex.DIRS[5] * 1, 4, "room:1")
	var c0 := b0 + Hex.DIRS[2] * 14
	_room(c0, 3, "room:2")
	var route := _hall(a0 + Hex.DIRS[1] * 5, 1, 6, 0)
	_hall(b0 + Hex.DIRS[2] * 5, 2, 6, 0)
	_make_map()
	# wet: the sump (radius 2), the channel out to the door, the corridor A-B, and the channel across room B to the outfall
	var cells: Array[Vector2i] = []
	cells.append_array(Hex.range_cells(a0, 2))
	for i in range(3, 6):
		cells.append(a0 + Hex.DIRS[1] * i)
	for i in range(0, 6):
		cells.append(b0 - Hex.DIRS[1] * i)
	for i in range(1, 6):
		cells.append(b0 + Hex.DIRS[1] * i)
	_flood(cells)
	var hall_ab := {}
	for c: Vector2i in map.cells:
		if map.cells[c].tag == "corridor" and Hex.distance(c, b0) > 6 and Hex.distance(c, c0) < Hex.distance(c, a0):
			hall_ab[c] = true     # the B-C passage stays dry
	_flood_halls(hall_ab)
	var axis := Vector2(Hex.dir_vector(1).x, Hex.dir_vector(1).z)
	flow_of = func(_p: Vector2) -> Vector2: return -axis      # from the outfall in B, through the hall, into the sump
	return {"a0": a0, "b0": b0, "c0": c0, "route": route}


func _case_rooms() -> void:
	var L := _layout_rooms()
	_finish()
	_dress_rooms(L)
	var a0: Vector2i = L["a0"]
	var b0: Vector2i = L["b0"]
	var mid := (Hex.to_world(a0) + Hex.to_world(b0)) * 0.5
	_hero("wick", _at(a0 + Hex.DIRS[1] * 7, Vector3(0.2, 0, 0.3)), Hex.dir_vector(1))
	_hero("gasket", _at(a0 + Hex.DIRS[0] * 3 + Hex.DIRS[1], Vector3(0.0, 0, 0.0)), Hex.dir_vector(2))
	_hero("rebar", _at(b0 + Hex.DIRS[4] * 2 + Hex.DIRS[3], Vector3(0.0, 0, 0.0)), Hex.dir_vector(4))
	_view("game", GAME_SIZE, mid + Vector3(0, 0, 1.0))
	_view("close", CLOSE_SIZE, Hex.to_world(a0 + Hex.DIRS[1] * 7) + Vector3(0, 0, 0.5))
	_view("plan", 34.0, mid + Vector3(-1.0, 0, -3.0))


func _dress_rooms(L: Dictionary) -> void:
	var a0: Vector2i = L["a0"]
	var b0: Vector2i = L["b0"]
	var ax := Hex.dir_vector(1)
	# room A: a ladder down into the sump, a pipe run on the far wall, a light shaft over the sump, a valve
	_put(SewerProps.build("pipe_bundle", {"length": 5.0, "col": look["pipe"]}), Hex.to_world(a0 + Hex.DIRS[2] * 5) + Hex.dir_vector(5) * 0.45, yaw_to(Hex.dir_vector(5)))
	_put(PoolProps.build("valve_wheel"), Hex.to_world(a0 + Hex.DIRS[3] * 4 + Hex.DIRS[2]) + Vector3(0.2, 0, 0.2), 0.0)
	_shaft(Hex.to_world(a0) + Vector3(0.3, FLOOR_Y, -0.2), 0.8)
	_put(SewerProps.build("duck"), Vector3(Hex.to_world(a0).x - 0.9, SURFACE, Hex.to_world(a0).z + 0.6), 70.0)
	_put(SewerProps.build("grate", {"size": 1.4}), Hex.to_world(a0) + Vector3(0, FLOOR_Y + 0.01, 0), 15.0)
	# the sluice gate in A's doorway (its posts on the jambs), raised
	var door_a := Hex.to_world(a0 + Hex.DIRS[1] * 5) + ax * 0.9
	_put(SewerProps.build("sluice", {"width": 3.0, "open": 0.45}),Vector3(door_a.x, 0, door_a.z), yaw_to(ax))
	# springers along the hall walls
	# (the far wall only: the camera sees its face; the near wall's would stand in the water in front of it)
	var far_n := Vector3(-ax.z, 0, ax.x)
	if far_n.dot(Hex.dir_vector(2)) < 0.0:
		far_n = -far_n
	for i in [2, 4]:
		var c: Vector2i = a0 + Hex.DIRS[1] * (5 + i) + Hex.DIRS[2]
		var w := Hex.to_world(c) + far_n * (Hex.to_world(Hex.DIRS[2]).dot(far_n) * 0.0)
		# onto the wall line (through the far cut cells' centres), facing into the hall
		_put(SewerProps.build("springer", {"height": 1.9, "col": look["wall_base"]}), Vector3(w.x, FLOOR_Y, w.z), yaw_to(-far_n))
	# room B: the outfall pouring in at the channel's head, a grate bridge across the channel, rats on the walkway
	var head := Hex.to_world(b0 + Hex.DIRS[1] * 6)
	_put(SewerProps.build("outfall", {"radius": 0.62, "drop": 1.3}), Vector3(head.x, FLOOR_Y + 0.36, head.z) - ax * 0.15, yaw_to(-ax))
	var br := Hex.to_world(b0 + Hex.DIRS[1] * 2)
	_bridge_over(br, ax, 4.2, 1.3)
	var rats := SewerProps.build("rat_swarm", {"count": 9, "radius": 0.8, "seed": 4})
	_put(rats, Hex.to_world(b0 + Hex.DIRS[0] * 3 + Hex.DIRS[5]), 0.0)
	_contents.append(rats)
	_put(SewerProps.build("pipe_bundle", {"length": 4.0, "col": look["pipe"]}), Hex.to_world(b0 + Hex.DIRS[2] * 4 + Hex.DIRS[1] * 2) + Hex.dir_vector(5) * 0.45, yaw_to(Hex.dir_vector(5)))
	_put(PoolProps.build("hazard_sign"), Hex.to_world(b0 + Hex.DIRS[4] * 3 + Hex.DIRS[3]) + Vector3(0, 0, -0.3), yaw_to(Vector3(1, 0, 1)))
	_shaft(Hex.to_world(b0 + Hex.DIRS[0] * 3 + Hex.DIRS[5]), 0.6)


## A wide hallway (4.5 between the walls) flooded on its near side: a 3.0 channel against the near wall, a 1.5 ledge walkway
## along the far wall (the camera sees the far side whole). Rooms at both ends, dry.
func _layout_hall(lanes: int) -> Dictionary:
	var a0 := Vector2i(-8, 5)
	var b0 := a0 + Hex.DIRS[1] * 22
	_room(a0, 4, "room:0")
	_room(b0, 4, "room:1")
	var route := _hall(a0 + Hex.DIRS[1] * 4, 1, 14, lanes)
	_make_map()
	var cells: Array[Vector2i] = []
	for i in range(1, 14):
		var r: Vector2i = route[i]
		if lanes == 2:
			cells.append(r + Hex.DIRS[2])            # the main: the middle row (lane 1) only, a ledge each side
		else:
			cells.append(r)                          # the route row
			cells.append(r + Hex.DIRS[0])            # and the near cut row (its floor half): water to the near wall
			cells.append(r + Hex.DIRS[5])
	_flood(cells)
	var axis := Vector2(Hex.dir_vector(1).x, Hex.dir_vector(1).z)
	flow_of = func(_p: Vector2) -> Vector2: return axis
	return {"a0": a0, "b0": b0, "route": route}


func _dress_hall(L: Dictionary, lanes: int) -> void:
	var route: Array = L["route"]
	var ax := Hex.dir_vector(1)
	var far := Vector3(-ax.z, 0, ax.x)
	if far.dot(Hex.dir_vector(2)) < 0.0:
		far = -far
	for i in [3, 6, 9, 12]:
		var c: Vector2i = route[i] + Hex.DIRS[2] * (lanes + 1)
		var w := Hex.to_world(c)
		_put(SewerProps.build("springer", {"height": 1.5, "col": look["wall_base"]}), Vector3(w.x, 0.0, w.z), yaw_to(-far))
	var pc: Vector2i = route[7] + Hex.DIRS[2] * (lanes + 1)
	_put(SewerProps.build("pipe_bundle", {"length": 6.0, "col": look["pipe"]}), Hex.to_world(pc) - far * 0.0 + ax * 0.0, yaw_to(-far))
	_shaft(Hex.to_world(route[10]) + Vector3(0, FLOOR_Y, 0), 0.65)
	if lanes == 2:
		_put(SewerProps.build("ladder_wall", {"height": 1.6}), Hex.to_world(route[4] + Hex.DIRS[5]) + Vector3(0, 0, 0), yaw_to(-Hex.dir_vector(5)))


func _case_hall() -> void:
	var L := _layout_hall(1)
	_finish()
	_dress_hall(L, 1)
	var route: Array = L["route"]
	var ax := Hex.dir_vector(1)
	_hero("wick", _at(route[5] + Hex.DIRS[2], Vector3(0, 0, 0)), ax)
	_hero("gasket", _ledge(route[6]), ax)
	_hero("rebar", _at(route[8], Vector3(0.3, 0, 0.3)), ax)
	_view("game", GAME_SIZE, Hex.to_world(route[7]) + Vector3(0, 0, 1.0))
	_view("close", CLOSE_SIZE, Hex.to_world(route[6] + Hex.DIRS[2]) + Vector3(0, 0, 0.5))


func _case_main() -> void:
	var L := _layout_hall(2)
	_finish()
	_dress_hall(L, 2)
	var route: Array = L["route"]
	var ax := Hex.dir_vector(1)
	_hero("wick", _at(route[5] + Hex.DIRS[2] * 2, Vector3(-0.39, 0, -0.225)), ax)
	_hero("gasket", _at(route[6] + Hex.DIRS[2], Vector3(0.0, 0, 0.0)), ax)
	_hero("rebar", _at(route[8], Vector3(0.3, 0, 0.3)), -ax)
	_gator(Hex.to_world(route[9] + Hex.DIRS[2]), yaw_to(-ax), 10.0)
	_view("game", GAME_SIZE, Hex.to_world(route[7]) + Vector3(0, 0, 1.0))
	_view("close", CLOSE_SIZE, Hex.to_world(route[7] + Hex.DIRS[2]) + Vector3(0, 0, 0.5))


## A junction chamber where three flooded narrow corridors meet (a Y): a drain sump in the middle under a big grate, the
## three channels running out of it to the doors, dry walkway wedges between them joined by a grate bridge; an outfall pipe
## pouring in from the wall, pipe runs, a ladder up to a manhole with daylight coming down the shaft.
func _case_junction() -> void:
	var j0 := Vector2i(0, 0)
	_room(j0, 5, "room:0")
	var dirs: Array[int] = [0, 2, 4]
	var ends: Array[Vector2i] = []
	for i in dirs.size():
		var d: int = dirs[i]
		var far_room: Vector2i = j0 + Hex.DIRS[d] * 13
		_room(far_room, 3, "room:%d" % (i + 1))
		ends.append(far_room)
	for d: int in dirs:
		_hall(j0 + Hex.DIRS[d] * 5, d, 5, 0)
	_make_map()
	var cells: Array[Vector2i] = []
	cells.append_array(Hex.range_cells(j0, 1))
	for d: int in dirs:
		for i in range(2, 6):
			cells.append(j0 + Hex.DIRS[d] * i)
	_flood(cells)
	_flood_halls()
	flow_of = func(p: Vector2) -> Vector2:
		var v := -p
		return v.normalized() if v.length() > 0.2 else Vector2(1, 0)    # everything drains to the middle
	_finish()
	var c := Hex.to_world(j0)
	_put(SewerProps.build("grate", {"size": 1.8}), c + Vector3(0, FLOOR_Y + 0.01, 0), 30.0)
	_ripple(c, 0.9)
	_ripple(c, 0.5)
	# the outfall between two channels, on the room wall at DIRS[1]
	var wall := Hex.to_world(j0 + Hex.DIRS[1] * 5)
	var into := -Hex.dir_vector(1)
	_put(SewerProps.build("outfall", {"radius": 0.6, "drop": 1.0}), Vector3(wall.x, 0.0, wall.z) + into * 0.1, yaw_to(into))
	# a grate bridge across the DIRS[0] channel, pipe runs on the walls, a ladder and the light shaft at DIRS[3]
	var br := Hex.to_world(j0 + Hex.DIRS[0] * 3)
	_bridge_over(br, Hex.dir_vector(0), 4.2, 1.2)
	var pw := Hex.to_world(j0 + Hex.DIRS[3] * 5 + Hex.DIRS[2] * 0)
	_put(SewerProps.build("pipe_bundle", {"length": 3.5, "col": look["pipe"]}), Hex.to_world(j0 + Hex.DIRS[2] * 4 + Hex.DIRS[3] * 1) + Hex.dir_vector(5) * 0.0, yaw_to(-Hex.dir_vector(2)) )
	var lad := Hex.to_world(j0 + Hex.DIRS[3] * 5)
	_put(SewerProps.build("ladder_wall", {"height": 1.6}), lad + Hex.dir_vector(0) * 0.3, yaw_to(Hex.dir_vector(0)))
	_shaft(lad + Hex.dir_vector(0) * 0.9, 0.7)
	_put(PoolProps.build("valve_wheel"), Hex.to_world(j0 + Hex.DIRS[5] * 4 + Hex.DIRS[4]), 0.0)
	_put(SewerProps.build("bars", {"width": 2.6, "height": 1.3}), Hex.to_world(j0 + Hex.DIRS[2] * 9) + Vector3(0, FLOOR_Y, 0), yaw_to(Hex.dir_vector(2)) + 90.0)
	var eel := PoolProps.build("eel", {"phase": 0.8})
	_put(eel, Hex.to_world(j0 + Hex.DIRS[4] * 3) + Vector3(0, SURFACE - 0.02, 0), yaw_to(Hex.dir_vector(1)))
	_hero("wick", _at(j0 + Hex.DIRS[5] * 3 + Hex.DIRS[0], Vector3(0, 0, 0)), Hex.dir_vector(2))
	_hero("gasket", _at(j0 + Hex.DIRS[2] * 3, Vector3(0.2, 0, 0.2)), Hex.dir_vector(5))
	_hero("rebar", br + Vector3(0.0, 0.0, 0.0), Hex.dir_vector(3))
	_view("game", GAME_SIZE, c + Vector3(0, 0, 1.0))
	_view("close", CLOSE_SIZE, c + Vector3(0.6, 0, 0.6))


## The rooms case under the game's room fog (look A): the crew in the cistern, the flooded hall seen through its doorway,
## room B one hall away (next: a silhouette), the B-C passage and room C unknown (not drawn). Things that move hide where
## no hero sees (the rats in B).
func _case_fog() -> void:
	var L := _layout_rooms()
	_finish()
	_dress_rooms(L)
	var a0: Vector2i = L["a0"]
	var b0: Vector2i = L["b0"]
	_hero("wick", _at(a0 + Hex.DIRS[2] * 3 + Hex.DIRS[1]), Hex.dir_vector(1))
	_hero("gasket", _at(a0 + Hex.DIRS[3] * 3), Hex.dir_vector(0))
	_hero("rebar", _at(a0 + Hex.DIRS[5] * 3 + Hex.DIRS[0]), Hex.dir_vector(2))
	_gator(Hex.to_world(b0 - Hex.DIRS[1] * 1), yaw_to(-Hex.dir_vector(1)), 15.0)
	fog = RoomFog.build(map)
	fog_view = FogView.new()
	fog_view.name = "Fog"
	add_child(fog_view)
	fog_view.setup(map, fog, camera)
	fog_view.viewers = crew_at.duplicate()
	fog_view.track_static(_static_nodes())
	var mid := (Hex.to_world(a0) + Hex.to_world(b0)) * 0.5
	var self_ref := self
	var apply_fog := func() -> void:
		self_ref.fog_view.refresh_now(true)
		for n: Node3D in self_ref._contents:
			n.visible = self_ref.fog.shows_contents(n.global_position)
		print("fog states: ", self_ref.fog.tags, " ", self_ref.fog.state)
	_view("game", GAME_SIZE, mid + Vector3(0, 0, 1.0), GAME_YAW, GAME_PITCH, apply_fog)
	_view("close", CLOSE_SIZE * 1.4, Hex.to_world(a0 + Hex.DIRS[1] * 6), GAME_YAW, GAME_PITCH, apply_fog)
	# the crew walks into the hall: the hall in view, room B seen through the far doorway (two hops)
	var into_hall := func() -> void:
		self_ref.fog_view.viewers = [self_ref._at(a0 + Hex.DIRS[1] * 8)]
		self_ref.fog_view.refresh_now(true)
		for n: Node3D in self_ref._contents:
			n.visible = self_ref.fog.shows_contents(n.global_position)
		print("fog states (hall): ", self_ref.fog.tags, " ", self_ref.fog.state)
	_view("hall", GAME_SIZE, mid + Vector3(0, 0, 1.0), GAME_YAW, GAME_PITCH, into_hall)


func _static_nodes() -> Array:
	var out: Array = []
	for n in _props:
		if not _contents.has(n):
			out.append(n)
	return out


## The hall with a sewer gator in the 3.0 channel, curled mid-turn (it turns round in two-row water), and the crew wading:
## Rebar in the water ahead of it, Wick wading up behind, Gasket on the ledge.
func _case_gator() -> void:
	var L := _layout_hall(1)
	_finish()
	_dress_hall(L, 1)
	var route: Array = L["route"]
	var ax := Hex.dir_vector(1)
	var gpos := Hex.to_world(route[7]) + Hex.dir_vector(0) * 0.35
	var gt := _gator(gpos, yaw_to(-ax) - 25.0, 70.0, 0.7)
	_hero("rebar", _at(route[5], Vector3(0.0, 0, 0.0)) + Hex.dir_vector(0) * 0.3, ax)
	_hero("wick", _at(route[10], Vector3(0.0, 0, 0.0)) + Hex.dir_vector(0) * 0.2, -ax)
	_hero("gasket", _ledge(route[6]), ax)
	_view("game", GAME_SIZE, Hex.to_world(route[7]) + Vector3(0, 0, 1.0))
	_view("close", CLOSE_SIZE, gt.position + Vector3(0, 0.5, 0.2))
	_view("closer", 5.0, gt.position + Vector3(0, 0.4, 0))


# --------------------------------------------------------------------------- views

func _view(view_name: String, size: float, at: Vector3, yaw: float = GAME_YAW, pitch: float = GAME_PITCH, setup: Callable = Callable()) -> void:
	views[view_name] = {"size": size, "at": at, "yaw": yaw, "pitch": pitch, "setup": setup}
	view_order.append(view_name)


func _prepare(view_name: String) -> void:
	var v: Dictionary = views[view_name]
	var yaw := deg_to_rad(float(v["yaw"]))
	var pitch := deg_to_rad(float(v["pitch"]))
	camera.size = float(v["size"])
	var tgt: Vector3 = v["at"]
	camera.global_position = tgt + Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * 60.0
	camera.look_at(tgt, Vector3.UP)
	if (v["setup"] as Callable).is_valid():
		(v["setup"] as Callable).call()


func _run_shots() -> void:
	for i in 10:
		await get_tree().process_frame
	var base := shot_path.get_basename()
	var list: Array[String] = []
	if only_view == "":
		list.append_array(view_order)
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
