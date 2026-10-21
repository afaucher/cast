class_name SewerView
extends Node3D
## What a sewer floor shows above its terrain (docs/design/sewer-concept.md, "Phase 1 as built"; the round-2 lab's drawing,
## ported): the connected WATER (one fan per wet kite, murky, the foam streaks drawn out along the flow), the FOAM along
## every edge of the water (rims and walls alike), a stone KERB along every rim (the dry side of an edge that is not a wall),
## the channel bed and liners (HexMapView's pool surface restyled), and the look's materials and light. HexMapView draws the
## terrain as ever (pool cells in its inset mode, water up to the walls); this only dresses it.
##
## Three LOOKS (the lab's): "concrete" (storm drain, the bunker: grey-teal water, a hazard-yellow kerb, sodium light),
## "brick" (Victorian, the lair: murky olive water, a damp green tide line), "toxic" (the lair's overflow: glowing acid
## green). Presentation only: built on every machine from the map (spawn data), no state.
##
##   var v := SewerView.dress(game, map, terrain, "concrete", flows)     # a whole sewer floor (the slice, --sewer N)
##   var v := SewerView.dress_body(root, map, terrain, body, "brick", flows)   # a generated floor's cluster (phase 3)
##   v.flash(at, 8.7, 1.0)    # the live wire's shock lights the water round `at` (LiveWire)

const FOAM_W := 0.16
const KERB_W := 0.26
const KERB_H := 0.06
const BRICK_PAT := 24                                   ## a wall pattern id this adds to the material shader

## The material and lighting looks. floor / wall entries restyle FloorMaterials' rows the sewer uses (rooms: flagstone,
## halls: corridor stone, walls: rough stone); `wall_pat` BRICK_PAT swaps in a brick running bond.
const LOOKS := {
	"brick": {
		"wall_pat": BRICK_PAT, "wall_base": Color(0.46, 0.25, 0.18), "wall_alt": Color(0.13, 0.11, 0.09),
		"floor_base": Color(0.3, 0.29, 0.26), "corr_base": Color(0.24, 0.24, 0.22), "floor_spec": 0.35, "floor_rough": 0.55,
		"liner": 0, "liner_base": Color(0.42, 0.24, 0.18), "liner_alt": Color(0.12, 0.1, 0.08), "bed": Color(0.16, 0.17, 0.11),
		"slime": Color(0.42, 0.55, 0.2), "slime_glow": 0.0,
		"shallow": Color(0.36, 0.42, 0.2), "deep": Color(0.07, 0.1, 0.05), "glow": Color(0.6, 0.75, 0.25), "alpha": 0.7,
		"glow_gain": 0.18, "foam": Color(0.82, 0.84, 0.66), "scum": Color(0.48, 0.5, 0.26),
		"kerb": Color(0.5, 0.48, 0.44), "light": Color(0.78, 0.92, 0.5), "light_k": 0.62, "ambient": Color(0.42, 0.5, 0.4),
		"ambient_k": 0.5, "key": 0.55, "seam": 0.85, "pipe": Color(0.5, 0.27, 0.14),
	},
	"concrete": {
		"wall_pat": 20, "wall_base": Color(0.4, 0.41, 0.42), "wall_alt": Color(0.13, 0.13, 0.14),
		"floor_base": Color(0.42, 0.42, 0.41), "corr_base": Color(0.32, 0.33, 0.34), "floor_spec": 0.3, "floor_rough": 0.6,
		"liner": 1, "liner_base": Color(0.4, 0.41, 0.4), "liner_alt": Color(0.98, 0.78, 0.12), "bed": Color(0.18, 0.2, 0.2),
		"slime": Color(0.3, 0.38, 0.32), "slime_glow": 0.0,
		"shallow": Color(0.36, 0.5, 0.5), "deep": Color(0.06, 0.13, 0.15), "glow": Color(0.5, 0.8, 0.85), "alpha": 0.68,
		"glow_gain": 0.2, "foam": Color(0.85, 0.9, 0.9), "scum": Color(0.42, 0.48, 0.45),
		"kerb": Color(0.98, 0.78, 0.12), "light": Color(1.0, 0.62, 0.28), "light_k": 0.75, "ambient": Color(0.5, 0.5, 0.55),
		"ambient_k": 0.5, "key": 0.7, "seam": 1.0, "pipe": Color(0.35, 0.4, 0.33),
	},
	"toxic": {
		"wall_pat": 21, "wall_base": Color(0.24, 0.23, 0.26), "wall_alt": Color(0.05, 0.05, 0.06),
		"floor_base": Color(0.26, 0.25, 0.27), "corr_base": Color(0.22, 0.22, 0.25), "floor_spec": 0.3, "floor_rough": 0.6,
		"liner": 2, "liner_base": Color(0.26, 0.26, 0.24), "liner_alt": Color(0.06, 0.07, 0.06), "bed": Color(0.08, 0.16, 0.06),
		"slime": Color(0.45, 1.0, 0.3), "slime_glow": 0.7,
		"shallow": Color(0.45, 0.95, 0.3), "deep": Color(0.04, 0.22, 0.08), "glow": Color(0.5, 1.0, 0.35), "alpha": 0.72,
		"glow_gain": 0.75, "foam": Color(0.8, 1.0, 0.6), "scum": Color(0.62, 0.3, 0.75),
		"kerb": Color(0.36, 0.35, 0.36), "light": Color(0.55, 1.0, 0.45), "light_k": 0.45, "ambient": Color(0.35, 0.45, 0.38),
		"ambient_k": 0.45, "key": 0.4, "seam": 0.6, "pipe": Color(0.3, 0.3, 0.33),
	},
}

var look: Dictionary = LOOKS["concrete"]
var look_id := "concrete"
var water: MeshInstance3D = null
var foam: MeshInstance3D = null
var kerb: MeshInstance3D = null
var flows: Array = []                 ## PackedVector2Array flow lines (world X/Z), in flow order
var _water_mat: ShaderMaterial = null
var _flash_t := 0.0
var _flash_k := 0.0


## Who may write each var (see Net). All of it is this machine's presentation, built from the map.
func net_fields() -> Dictionary:
	return {"look": Net.LOCAL, "look_id": Net.LOCAL, "water": Net.LOCAL, "foam": Net.LOCAL, "kerb": Net.LOCAL,
		"flows": Net.LOCAL, "_water_mat": Net.LOCAL, "_flash_t": Net.LOCAL, "_flash_k": Net.LOCAL}


## Dress a sewer floor: the terrain's materials and the light in the look, the water, foam and kerbs. `parent` holds the
## DungeonLook lights (the game node).
static func dress(parent: Node3D, map: HexMap, terrain: HexMapView, p_look: String, p_flows: Array) -> SewerView:
	var v := SewerView.new()
	v.name = "SewerView"
	v.look_id = p_look if LOOKS.has(p_look) else "concrete"
	v.look = LOOKS[v.look_id]
	v.flows = p_flows
	parent.add_child(v)
	if terrain != null:
		v.restyle(terrain)
	v.relight(parent)
	v.build_water(map)
	return v


## A sewer cluster on a generated floor (SewerPlanner.spawn, phase 3): ONE body's water, foam and kerbs (its basin and ring
## cells, at its own surface), and the channel bed and liners in the look on HexMapView's CHANNEL surface (a sewer body's
## pool kites), nothing else: the rest of the floor keeps its materials, its pools and its light.
static func dress_body(parent: Node3D, map: HexMap, terrain: HexMapView, body: Dictionary, p_look: String, p_flows: Array) -> SewerView:
	var v := SewerView.new()
	v.name = "SewerView"
	v.look_id = p_look if LOOKS.has(p_look) else "concrete"
	v.look = LOOKS[v.look_id]
	v.flows = p_flows
	parent.add_child(v)
	if terrain != null:
		v.restyle_channel(terrain)
	var only := {}
	for c: Vector2i in (body["basin"] as Array) + (body["ring"] as Array):
		only[c] = true
	v.build_water(map, only, float(body["surface_y"]), int(body["floor_level"]))
	return v


## Only the sewer's channel surface in the look (HexMapView.CHANNEL_MATERIAL), not the floor's pools.
func restyle_channel(terrain: HexMapView) -> void:
	if terrain.mesh_instance == null:
		return
	var mesh := terrain.mesh_instance.mesh as ArrayMesh
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m != null and m.resource_name == HexMapView.CHANNEL_MATERIAL:
			mesh.surface_set_material(i, _channel_material())


## The water's flow direction at p (X/Z): along the nearest flow segment.
func flow_at(p: Vector2) -> Vector2:
	var best := INF
	var dir := Vector2(1, 0)
	for pl: PackedVector2Array in flows:
		for i in pl.size() - 1:
			var a := pl[i]
			var ab := pl[i + 1] - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < best:
				best = d
				dir = ab.normalized()
	return dir


## The live wire's shock (LiveWire): the water lights up within `radius` of `at`, fading over 0.35 s.
func flash(at: Vector3, radius: float, k: float = 1.0) -> void:
	if _water_mat == null:
		return
	_water_mat.set_shader_parameter("flash_pos", at)
	_water_mat.set_shader_parameter("flash_r", radius)
	_flash_k = k
	_flash_t = 0.35


func _process(delta: float) -> void:
	if _flash_t <= 0.0 or _water_mat == null:
		return
	_flash_t = maxf(0.0, _flash_t - delta)
	_water_mat.set_shader_parameter("flash_k", _flash_k * _flash_t / 0.35)


# --- the terrain's materials and the light -------------------------------------------------------------------------

## The terrain's materials in the look: FloorMaterials' rows for flagstone, corridor stone and rough stone recoloured (the
## brick look swaps in a brick pattern: the material shader's code with one more wall pattern), the seams' glow scaled,
## and the pool surface (channel bed and liners) replaced with the channel shader.
func restyle(terrain: HexMapView) -> void:
	if terrain.mesh_instance == null:
		return
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
	var seam := float(look["seam"])
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as ShaderMaterial
		if m == null or m.shader == null:
			continue
		if m.shader.code == HexMapView.POOL_SHADER:
			mesh.surface_set_material(i, _channel_material())
		elif m.shader.code == HexMapView.GLOW_SHADER:
			var gm := m.duplicate() as ShaderMaterial
			gm.set_shader_parameter("energy", 1.9 * seam)
			mesh.surface_set_material(i, gm)
		elif m.get_shader_parameter("m_base") != null:
			var nm := m.duplicate() as ShaderMaterial
			nm.shader = brick_shader
			nm.set_shader_parameter("m_base", base)
			nm.set_shader_parameter("m_alt", alt)
			nm.set_shader_parameter("m_par", par)
			if nm.get_shader_parameter("glow_energy") != null:
				nm.set_shader_parameter("glow_energy", float(nm.get_shader_parameter("glow_energy")) * seam)
			mesh.surface_set_material(i, nm)


## The look's lighting on top of DungeonLook: a tinted ambient and key, the downlights recoloured to the look's light.
func relight(parent: Node) -> void:
	for ch in parent.get_children():
		if ch is WorldEnvironment:
			var env := (ch as WorldEnvironment).environment
			if env != null:
				env.ambient_light_color = look["ambient"]
				env.ambient_light_energy = float(look["ambient_k"])
		elif ch.name == "KeyLight" and ch is DirectionalLight3D:
			(ch as DirectionalLight3D).light_energy = float(look["key"])
			(ch as DirectionalLight3D).light_color = (look["light"] as Color).lerp(Color.WHITE, 0.5)
		elif ch.name == "Downlights":
			for l in ch.get_children():
				if l is OmniLight3D:
					(l as OmniLight3D).light_color = look["light"]
					(l as OmniLight3D).light_energy *= float(look["light_k"])


## A brick running bond 0.46 x 0.16 with dark mortar, each brick a little lighter or darker, and a damp green tide line up
## to about half a unit over the floor (one more wall pattern for the material shader).
const BRICK_GLSL := """	} else if (pat == 24) {               // the sewer's brick
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


## The channel bed (dark silt, slime blotches) and the liners (brick, concrete with a hazard stripe, or stone blocks) with a
## slime tide line, in place of the pools' tiles.
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


# --- the water ---------------------------------------------------------------------------------------------------

## Murky moving water: the pools' banded toon water, darker and more opaque, with scum blotches and foam streaks drawn out
## along the local flow (vertex COLOR.rg carries the flow direction, 0.5 + 0.5 * dir), and the live wire's flash.
## THE FLOW'S FRAME: the pattern is drawn in a frame along one of 12 FIXED directions (every 30 degrees), the two either side
## of the local flow cross-faded, never in a frame along the interpolated flow itself. A frame turned by the flow is
## dot(world position, flow): where the flow turns inside a kite (the switch between two flow lines, round a sump) its phase
## swings by |position| x the angle, and on a generated floor, 30-60 m from the origin, that packed dozens of stripes into a
## kite: a moire band along the kites' edges across the channel and rings round a sump (the user's playtest, 2026-10-21; the
## hand layouts sit near the origin, so it hardly showed there). A fixed direction's frame is a plain translation.
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
uniform vec3 flash_pos = vec3(0.0);
uniform float flash_k = 0.0;
uniform float flash_r = 8.0;
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
// The pattern in the frame of fixed direction f: x the band (0, 0.5 or 1), y the scum, z the foam streak.
vec3 flow_look(vec2 p, vec2 f, float t) {
	vec2 n = vec2(-f.y, f.x);
	float along = dot(p, f) - t * 0.8;
	float across = dot(p, n);
	float w = sin(along * 1.6 + sin(across * 1.3) * 0.8) + sin(across * 2.1 + along * 0.5 - t) + 0.5 * sin((along + across) * 3.0 + t * 1.7);
	float band = floor(clamp(w * 0.2 + 0.5, 0.0, 0.999) * 3.0) / 2.0;
	float scum = smoothstep(0.62, 0.7, vn(vec2(along * 0.45, across * 0.9) + 7.0));
	float streak = smoothstep(0.72, 0.8, vn(vec2(along * 0.6, across * 5.5)));
	return vec3(band, scum, streak);
}
void fragment() {
	float t = 1.3 + TIME * 0.5;
	vec2 p = wp.xz;
	float sector = atan(flow.y, flow.x) / (TAU / 12.0);
	float s0 = floor(sector);
	float a0 = s0 * TAU / 12.0;
	float a1 = a0 + TAU / 12.0;
	vec3 look = mix(flow_look(p, vec2(cos(a0), sin(a0)), t), flow_look(p, vec2(cos(a1), sin(a1)), t), sector - s0);
	float band = look.x;
	float scum = look.y;
	float streak = look.z;
	vec3 col = mix(deep_col.rgb, shallow_col.rgb, band * 0.8);
	col = mix(col, scum_col.rgb, scum * 0.7);
	col = mix(col, foam_col.rgb, streak * 0.55);
	float fd = length(p - flash_pos.xz);
	float fl = flash_k * (1.0 - smoothstep(flash_r * 0.55, flash_r, fd)) * (0.55 + 0.45 * sin(TIME * 70.0 + fd * 4.0));
	ALBEDO = mix(col, vec3(1.0, 1.0, 0.8), clamp(fl, 0.0, 1.0) * 0.15);
	EMISSION = glow_col.rgb * glow_gain * (0.4 + 0.8 * band) + foam_col.rgb * streak * 0.08 + vec3(1.0, 0.95, 0.55) * max(fl, 0.0) * 0.9;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	ALPHA = clamp(alpha + scum * 0.15, 0.0, 1.0);
}
"""


static func _kite_poly(center: Vector3, k: int) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for o: Vector3 in [Vector3.ZERO, Hex.edge_mid(k), Hex.kite_corner(k), Hex.edge_mid((k + 1) % 6)]:
		pts.append(Vector2(center.x + o.x, center.z + o.z))
	return pts


## A kite corner's key on the hex lattice: every kite corner (a cell centre, an edge midpoint, a cell corner) has X a whole
## multiple of INNER / 2 and Z of SIZE / 4, so the key is those multiples. NOT millimetres: on a generated floor, far from
## the origin, the same corner reached from two cells differs in the last float bit, and where it sits on a half millimetre
## (X = -51.0955: 118 x INNER / 2) the two cells' keys split, the shared edge counted as an edge of the water on both sides
## and each side drew foam and a kerb along it at the channel floor (ground_level there), under the water.
static func _key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x / (Hex.INNER * 0.5)), roundi(p.y / (Hex.SIZE * 0.25)))


## The water surface (a fan per pool kite of the sewer's cells, the flow in the vertex colour), the foam along every edge
## of the water (rims and walls), and a stone kerb along every rim (an edge that is not a wall). Kites: every pool kite of
## the map (the sewer's map has no other pools), or with `only` the kites of those cells (one body of a generated floor) at
## that body's surface over its channel floor (`floor_level`).
func build_water(map: HexMap, only: Dictionary = {}, surface_y: float = SewerLayouts.SURFACE_Y, floor_level: int = SewerLayouts.CH_LEVEL) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges := {}        ## sorted end keys -> [a, b, centre of the kite (inside the water), count]
	var keys: Array = map.cells.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	var n_kites := 0
	for c: Vector2i in keys:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type == HexMap.Tile.WALL or cell.pool_mask == 0 or (not only.is_empty() and not only.has(c)):
			continue
		var m := cell.pool_mask & ~cell.wall_mask
		for k in 6:
			if (m >> k) & 1 == 0:
				continue
			n_kites += 1
			var poly := _kite_poly(Hex.to_world(c), k)
			var cen := (poly[0] + poly[1] + poly[2] + poly[3]) * 0.25
			for tri: Array in [[0, 1, 2], [0, 2, 3]]:
				for j: int in [tri[0], tri[2], tri[1]]:
					var fl := flow_at(poly[j])
					st.set_color(Color(0.5 + 0.5 * fl.x, 0.5 + 0.5 * fl.y, 0.0))
					st.set_normal(Vector3.UP)
					st.add_vertex(Vector3(poly[j].x, surface_y, poly[j].y))
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
	if n_kites == 0:
		return
	water = MeshInstance3D.new()
	water.name = "Water"
	water.mesh = st.commit()
	var sh := Shader.new()
	sh.code = WATER_SHADER
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = sh
	for k: String in ["shallow", "deep", "glow", "foam", "scum"]:
		_water_mat.set_shader_parameter(k + "_col", look[k])
	_water_mat.set_shader_parameter("alpha", float(look["alpha"]))
	_water_mat.set_shader_parameter("glow_gain", float(look["glow_gain"]))
	_water_mat.render_priority = 1
	water.material_override = _water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# foam strips and kerbs along the boundary edges
	var fst := SurfaceTool.new()
	fst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kst := SurfaceTool.new()
	kst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fc: Color = look["foam"]
	var kc: Color = look["kerb"]
	var kerb_ends := {}     ## vertex key -> [vertex, top, [outward normals of the rim edges ending there]]
	var n_kerb := 0
	var floor_y := floor_level * Hex.LEVEL_HEIGHT
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
		var y := surface_y + 0.006
		var a_in := a + n * FOAM_W
		var b_in := b + n * FOAM_W
		var c0 := Color(fc.r, fc.g, fc.b, 0.85)
		var c1 := Color(fc.r, fc.g, fc.b, 0.0)
		_quad(fst, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(b_in.x, y, b_in.y), Vector3(a_in.x, y, a_in.y), [c0, c0, c1, c1])
		var probe := (a + b) * 0.5 - n * 0.08
		var pc := Hex.from_world(Vector3(probe.x, 0, probe.y))
		var is_wall: bool = not map.has_cell(pc) or map.cells[pc].type == HexMap.Tile.WALL or map.wall_at(Vector3(probe.x, 0, probe.y))
		if is_wall:
			continue
		var gl := map.ground_level(Vector3(probe.x, 0, probe.y))
		var top := (0.0 if is_nan(gl) else gl) * Hex.LEVEL_HEIGHT + KERB_H
		var o := -n
		var a2 := a + o * KERB_W
		var b2 := b + o * KERB_W
		var a1 := a - o * 0.04
		var b1 := b - o * 0.04
		_quad(kst, Vector3(a1.x, top, a1.y), Vector3(b1.x, top, b1.y), Vector3(b2.x, top, b2.y), Vector3(a2.x, top, a2.y), [kc, kc, kc, kc])
		var dk := kc.darkened(0.25)
		_quad(kst, Vector3(a1.x, top, a1.y), Vector3(b1.x, top, b1.y), Vector3(b1.x, floor_y + 0.2, b1.y), Vector3(a1.x, floor_y + 0.2, a1.y), [dk, dk, dk, dk])
		n_kerb += 1
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
		_quad(kst, Vector3(v.x, top, v.y), Vector3(p0.x, top, p0.y), Vector3(pm.x, top, pm.y), Vector3(p1.x, top, p1.y), [kc, kc, kc, kc])
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.vertex_color_use_as_albedo = true
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.render_priority = 2
	foam = MeshInstance3D.new()
	foam.name = "Foam"
	foam.mesh = fst.commit()
	foam.material_override = fm
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(foam)
	if n_kerb > 0:
		var km := StandardMaterial3D.new()
		km.vertex_color_use_as_albedo = true
		km.roughness = 0.75
		km.cull_mode = BaseMaterial3D.CULL_DISABLED
		kerb = MeshInstance3D.new()
		kerb.name = "Kerb"
		kerb.mesh = kst.commit()
		kerb.material_override = km
		add_child(kerb)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, cols: Array) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	for idx: int in [0, 1, 2, 0, 2, 3]:
		st.set_color(cols[idx])
		st.set_normal(nrm)
		st.add_vertex([a, b, c, d][idx])
