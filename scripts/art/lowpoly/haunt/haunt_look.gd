class_name HauntLook
extends RefCounted
## The haunted rooms' look test (docs/design/mansion-rooms.md, docs/design/church-rooms.md; LOOK-DEV ONLY): the lab-only
## floor and wall materials (parquet, wallpaper over a dado, glazing, limestone) and the two lightings (cold moonlight,
## candle light). Nothing in the game uses any of it: no room theme, floor or site names these materials, and the game's
## FloorMaterials table and terrain shader are unchanged.
##
## MATERIALS. FloorMaterials' table has 32 shader slots; the game uses floors 0-15 and walls 16-21. The test puts its own
## rows in the free slots 24-31 of a COPY of that table (`tables()`) and adds three patterns to a COPY of the terrain
## shader (`terrain_shader()`: herringbone parquet on floors; damask over a walnut dado, stripes over an oak dado and
## conservatory glazing on walls). `dress_terrain(view)` swaps them onto a built HexMapView, so a map whose cells carry
## these ids draws them. A real build would add rows to FloorMaterials instead (its floor half is full: a table change).
##
## LIGHT. `apply_light(root, mode)` relights a scene lit by DungeonLook (its LookEnvironment, KeyLight, FillLight and
## Downlights nodes, found under `root`): "game" puts DungeonLook's values back, "moonlight" is a cold, low key light with
## the warm pools off and every candle out, "candle" is near-dark with the pools off and every candle lit (each candle
## cluster of a haunt prop carries a small warm OmniLight). Live: the gym's "Haunt light" row calls it.
##
##   HauntLook.dress_terrain(terrain)                     # after terrain.build(map) on a map with HauntLook ids
##   HauntLook.apply_light(self, "candle")

const MODES: Array[String] = ["game", "moonlight", "candle"]
const LIGHTS: Array[String] = ["moonlight", "candle"]
## The gym's current pick (GymDev's "Haunt light" row).
static var light := "game"

const CANDLES_GROUP := "haunt_candles"   ## every haunt prop's "Candles" node (flames and their lights)
const PROPS_GROUP := "haunt_props"       ## every haunt prop's root

# --- materials ---------------------------------------------------------------------------------------------------------
# Wall ids map to shader slot WALL_OFFSET (16) + id; floor ids are their own slot. The test's slots are 24-31.
const W_DAMASK := 8            ## slot 24: oxblood damask over a walnut dado (set "walnut")
const W_STRIPE := 9            ## slot 25: faded sage stripe over an oak dado (set "oak")
const W_LIMESTONE := 10        ## slot 26: pale limestone blocks (the church)
const F_PARQUET_DARK := 27     ## slot 27: dark walnut herringbone (set "walnut")
const F_PARQUET_PALE := 28     ## slot 28: pale oak herringbone (set "oak")
const F_LIMESTONE := 29        ## slot 29: worn limestone flags (the church)
const F_TERRACOTTA := 30       ## slot 30: terracotta tiles (the conservatory)
const W_GLAZING := 15          ## slot 31: white iron glazing bars over dark glass (the conservatory)

## The new patterns (the terrain shader's pattern ids 0-8 and 20-23 are the game's).
const PAT_HERRINGBONE := 9
const PAT_DAMASK := 24
const PAT_STRIPE := 25
const PAT_GLAZING := 26

## slot -> {name, pat, base, alt (sRGB), scale, rough, spec}, written over FloorMaterials' table copy.
const ROWS := {
	24: {"name": "damask over walnut", "pat": PAT_DAMASK, "base": Color(0.46, 0.12, 0.12), "alt": Color(0.70, 0.32, 0.24), "scale": 1.0, "rough": 0.7, "spec": 0.2},
	25: {"name": "sage stripe over oak", "pat": PAT_STRIPE, "base": Color(0.42, 0.48, 0.38), "alt": Color(0.70, 0.66, 0.52), "scale": 1.0, "rough": 0.75, "spec": 0.15},
	26: {"name": "limestone blocks", "pat": 21, "base": Color(0.60, 0.57, 0.52), "alt": Color(0.27, 0.25, 0.23), "scale": 1.0, "rough": 0.9, "spec": 0.1},
	27: {"name": "walnut herringbone", "pat": PAT_HERRINGBONE, "base": Color(0.40, 0.22, 0.12), "alt": Color(0.12, 0.06, 0.03), "scale": 0.13, "rough": 0.45, "spec": 0.35},
	28: {"name": "oak herringbone", "pat": PAT_HERRINGBONE, "base": Color(0.66, 0.47, 0.28), "alt": Color(0.30, 0.19, 0.10), "scale": 0.13, "rough": 0.5, "spec": 0.3},
	29: {"name": "limestone flags", "pat": 2, "base": Color(0.55, 0.52, 0.47), "alt": Color(0.20, 0.19, 0.17), "scale": 1.5, "rough": 0.88, "spec": 0.12},
	30: {"name": "terracotta tiles", "pat": 4, "base": Color(0.62, 0.31, 0.19), "alt": Color(0.30, 0.15, 0.10), "scale": 0.7, "rough": 0.75, "spec": 0.15},
	31: {"name": "glazing", "pat": PAT_GLAZING, "base": Color(0.10, 0.17, 0.19), "alt": Color(0.86, 0.87, 0.82), "scale": 1.0, "rough": 0.15, "spec": 0.7},
}

## The mansion's material sets: the house rooms' floor and wall (the conservatory keeps its own in both).
const SETS := {
	"walnut": {"name": "walnut & damask", "floor": F_PARQUET_DARK, "wall": W_DAMASK},
	"oak": {"name": "oak & stripe", "floor": F_PARQUET_PALE, "wall": W_STRIPE},
}
const SET_NAMES: Array[String] = ["walnut", "oak"]
const CONSERVATORY := {"floor": F_TERRACOTTA, "wall": W_GLAZING}
const CHURCH := {"floor": F_LIMESTONE, "wall": W_LIMESTONE}

## Shader code added to material_color (floors) before its return.
const FLOOR_PATTERNS := """
	if (pat == 9) {                       // herringbone parquet (HauntLook): boards sc wide, five long, in a 45-degree staircase
		vec2 hp = vec2(p.x - p.y, p.x + p.y) * 0.7071 / sc;
		float n = 5.0;
		float dd = hp.x - hp.y;
		float b = floor((dd + n + 1.0) / (2.0 * n));
		vec2 lc = vec2(0.0);
		float vert = 0.0;
		vec2 bid = vec2(0.0);
		for (int k = 0; k < 2; k++) {
			float bb = b - float(k);
			vec2 q = hp - bb * vec2(n, -n);
			float t = floor(q.y);
			if (q.x - t >= 0.0 && q.x - t < n) {
				lc = vec2(q.x - t, q.y - t);
				vert = 0.0;
				bid = vec2(bb, t);
				break;
			}
			t = floor(q.x);
			if (q.y - t - 1.0 >= 0.0 && q.y - t - 1.0 < n) {
				lc = vec2(q.y - t - 1.0, q.x - t);
				vert = 1.0;
				bid = vec2(bb + 50.0, t);
				break;
			}
		}
		float grain = vn(vec2(lc.x * 1.2, lc.y * 9.0) + bid * 3.1);
		float tone = 0.9 + 0.16 * h21(bid);
		c = base * tone * (0.84 + 0.3 * grain) * (0.92 + 0.12 * vn(p * 0.4));
		float edge = min(min(lc.y, 1.0 - lc.y) * 1.0, min(lc.x, n - lc.x) * 1.0);
		c = mix(c, alt, (1.0 - smoothstep(0.0, 0.06, edge)) * 0.45);
	}
"""

## Shader code added to wall_color (wall faces) before its return. u runs along the face, v is the world height.
const WALL_PATTERNS := """
	if (pat == 24 || pat == 25) {         // wallpaper over a panelled dado (HauntLook): 24 damask on walnut, 25 stripe on oak
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
	} else if (pat == 26) {               // conservatory glazing (HauntLook): a stone sill, white iron bars, dark glass with a sheen
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
"""

## The wall CAPS (the tops of wall cells) of the test's walls: wood for the papered walls, a dark lead roof for the glazing.
## (The glazing's cap is a glass roof seen from above: white bars over dark panes, so the glasshouse reads from the camera.)
const CAP_PATCH := """} else if (is_wall && (pat == 24 || pat == 25)) {
			vec3 capc = pat == 24 ? vec3(0.13, 0.06, 0.03) : vec3(0.26, 0.16, 0.07);
			alb = capc * (0.8 + 0.4 * fbm(wp.xz * 3.0));
			rgh = 0.7;
		} else if (is_wall && pat == 26) {
			float bar = 1.0 - smoothstep(0.02, 0.035, grid_d(wp.xz + vec2(0.0, 0.3), vec2(0.9, 0.6)));
			float sheen = smoothstep(0.6, 1.0, fract((wp.x - wp.z) * 0.35)) * 0.6;
			alb = mix(b.rgb * (1.2 + sheen * 2.0), a.rgb * 0.8, bar);
			rgh = mix(0.25, 0.7, bar);
			spc = 0.35;
		} else if (is_wall) {"""

static var _shader: Shader
static var _tables: Dictionary = {}


static func pack(floor_id: int, wall_id: int) -> int:
	return FloorMaterials.pack(floor_id, wall_id)


## The material name of a slot (a test's floor id, or WALL_OFFSET + a test's wall id).
static func slot_name(slot: int) -> String:
	return str((ROWS.get(slot, {}) as Dictionary).get("name", ""))


static func wall_slot(wall_id: int) -> int:
	return FloorMaterials.WALL_OFFSET + wall_id


## The terrain material shader with the test's patterns (a copy of HexMapView.MATERIAL_SHADER).
static func terrain_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = shader_code()
	return _shader


static func shader_code() -> String:
	var code := HexMapView.MATERIAL_SHADER
	code = _insert_before_return(code, "vec3 wall_color(", FLOOR_PATTERNS)
	code = _insert_before_return(code, "void vertex()", WALL_PATTERNS)
	assert(code.contains("} else if (is_wall) {"), "HauntLook: the terrain shader's wall cap changed shape")
	code = code.replace("} else if (is_wall) {", CAP_PATCH)
	return code


## `extra` inserted at the start of the line of the last "return c;" before `anchor` (the end of the function above it).
static func _insert_before_return(code: String, anchor: String, extra: String) -> String:
	var at := code.find(anchor)
	var ret := code.rfind("return c;", at)
	assert(at > 0 and ret > 0, "HauntLook: the terrain shader changed shape")
	if at < 0 or ret < 0:
		return code
	var line := code.rfind("\n", ret) + 1
	return code.substr(0, line) + extra.strip_edges(false, true) + "\n" + code.substr(line)


## FloorMaterials' shader tables with the test's rows in slots 24-31 (linear colour, like table_arrays()).
static func tables() -> Dictionary:
	if not _tables.is_empty():
		return _tables
	var src := FloorMaterials.table_arrays()
	var base: PackedVector4Array = (src["base"] as PackedVector4Array).duplicate()
	var alt: PackedVector4Array = (src["alt"] as PackedVector4Array).duplicate()
	var par: PackedVector4Array = (src["par"] as PackedVector4Array).duplicate()
	for slot: int in ROWS:
		var d: Dictionary = ROWS[slot]
		var b: Color = (d["base"] as Color).srgb_to_linear()
		var a: Color = (d["alt"] as Color).srgb_to_linear()
		base[slot] = Vector4(b.r, b.g, b.b, float(int(d["pat"])))
		alt[slot] = Vector4(a.r, a.g, a.b, float(d["scale"]))
		par[slot] = Vector4(float(d["rough"]), float(d["spec"]), 0.0, 0.0)
	_tables = {"base": base, "alt": alt, "par": par}
	return _tables


## Swap the test's shader and tables onto every material-shader surface of a built HexMapView. Returns how many.
static func dress_terrain(view: HexMapView) -> int:
	if view.mesh_instance == null or view.mesh_instance.mesh == null:
		return 0
	var n := 0
	var mesh := view.mesh_instance.mesh
	var t := tables()
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as ShaderMaterial
		if m == null or m.shader == null or m.shader.code != HexMapView.MATERIAL_SHADER:
			continue
		m.shader = terrain_shader()
		m.set_shader_parameter("m_base", t["base"])
		m.set_shader_parameter("m_alt", t["alt"])
		m.set_shader_parameter("m_par", t["par"])
		n += 1
	return n


# --- light -------------------------------------------------------------------------------------------------------------

## mode -> the environment and the two directional lights. "game" is DungeonLook's own values.
const LOOKS := {
	"game": {"bg": DungeonLook.BACKGROUND, "ambient": Color(0.50, 0.50, 0.60), "ambient_e": 0.55, "exposure": 1.0, "sat": 1.08,
		"key": Color(1.0, 0.86, 0.68), "key_e": 0.9, "key_rot": Vector3(-50, -30, 0), "fill_e": 0.22, "pools": true, "candles": true},
	"moonlight": {"bg": Color(0.02, 0.03, 0.06), "ambient": Color(0.42, 0.54, 0.92), "ambient_e": 0.8, "exposure": 1.15, "sat": 0.8,
		"key": Color(0.66, 0.78, 1.0), "key_e": 1.35, "key_rot": Vector3(-42, -62, 0), "fill_e": 0.14, "pools": false, "candles": false},
	"candle": {"bg": Color(0.035, 0.022, 0.015), "ambient": Color(0.58, 0.52, 0.52), "ambient_e": 0.4, "exposure": 1.0, "sat": 0.95,
		"key": Color(1.0, 0.86, 0.72), "key_e": 0.25, "key_rot": Vector3(-50, -30, 0), "fill_e": 0.06, "pools": false, "candles": true},
}

## A candle cluster's light (one per cluster of flames).
const CANDLE_COLOR := Color(1.0, 0.74, 0.48)
const CANDLE_ENERGY := 2.6
const CANDLE_RANGE := 5.0


## Relight the DungeonLook scene under `root` for `mode` (MODES) and light or snuff every haunt candle in the tree.
## Returns false for an unknown mode.
static func apply_light(root: Node, mode: String) -> bool:
	if not LOOKS.has(mode):
		return false
	var look: Dictionary = LOOKS[mode]
	var we := root.find_child("LookEnvironment", true, false) as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.background_color = look["bg"]
		env.ambient_light_color = look["ambient"]
		env.ambient_light_energy = float(look["ambient_e"])
		env.tonemap_exposure = float(look["exposure"])
		env.adjustment_saturation = float(look["sat"])
	var key := root.find_child("KeyLight", true, false) as DirectionalLight3D
	if key != null:
		key.light_color = look["key"]
		key.light_energy = float(look["key_e"])
		key.rotation_degrees = look["key_rot"]
	var fill := root.find_child("FillLight", true, false) as DirectionalLight3D
	if fill != null:
		fill.light_energy = float(look["fill_e"])
	var pools := root.find_child("Downlights", true, false) as Node3D
	if pools != null:
		pools.visible = bool(look["pools"])
	if root.is_inside_tree():
		for c in root.get_tree().get_nodes_in_group(CANDLES_GROUP):
			(c as Node3D).visible = bool(look["candles"])
	else:
		_set_candles(root, bool(look["candles"]))
	return true


static func _set_candles(n: Node, on: bool) -> void:
	if n.is_in_group(CANDLES_GROUP):
		(n as Node3D).visible = on
	for c in n.get_children():
		_set_candles(c, on)


## The gym's "Haunt light" row: remember the pick and relight the running scene.
static func pick(mode: String, root: Node) -> bool:
	if not MODES.has(mode):
		return false
	light = mode
	return apply_light(root, mode)


static func reset() -> void:
	light = "game"
