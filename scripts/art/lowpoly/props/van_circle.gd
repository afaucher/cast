class_name VanCircle
extends Node3D
## The summoning circle the work van teleports in over: a pentagram inside two rings, tick marks and rune glyphs,
## drawn by a shader on a flat quad lying just above the floor (no outline, no shadows). It has two looks that blend:
##   - GLOW: amber/orange lines with a soft halo, HDR so the bloom picks them up (the arrival flare);
##   - CHALK: the same figure as faint, broken chalk lines (what stays on the floor for the rest of the floor).
## Around it, for the arrival: a column of light (open cylinder), a shock ring that races outward over the floor,
## rising amber sparks and an omni light. Everything is driven by setters, so VanArrival (or the lab) can pose any moment:
##
##   var c := VanCircle.new(2.9)
##   c.set_figure(ignite, glow, chalk)    # ignite 0..1 draws the figure; glow = amber strength; chalk = chalk amount
##   c.set_column(0.8)                    # column of light 0..1
##   c.set_shock(0.3)                     # 0 = not shown, (0..1) the ring expanding, 1 = gone
##   c.set_light(1.0)                     # amber light 0..1
##   c.sparks(true)                       # rising sparks on / off
##   c.settle()                           # the final state: chalk only, everything else off

const LIFT := 0.035                  ## above the hex top
const COLUMN_HEIGHT := 6.0

const FIGURE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float radius = 2.9;          // world radius of the outer ring
uniform float half_size = 3.6;       // the quad's half extent
uniform float ignite = 0.0;          // 0..1: how much of the figure is drawn
uniform float glow = 0.0;            // amber strength
uniform float chalk = 0.0;           // chalk amount
uniform float chalk_alpha = 0.42;
uniform float chalk_width = 1.0;     // multiplies the line width
uniform float chalk_solid = 0.0;     // 0 = broken, smudged chalk (the in-game look); 1 = mostly unbroken lines
uniform float flare = 0.0;           // the filled amber disc inside the ring
uniform vec3 amber = vec3(1.0, 0.52, 0.10);
uniform vec3 chalk_col = vec3(0.90, 0.86, 0.74);
varying vec2 pp;

""" + ShaderHash.GLSL + """

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// distance to a segment; h = position along it (0..1)
float seg(vec2 p, vec2 a, vec2 b, out float h) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

void vertex() {
	pp = VERTEX.xz / radius;
}

void fragment() {
	vec2 p = pp;
	float r = length(p);
	float a = fract(atan(p.x, -p.y) / 6.2831853);      // 0 at the top, clockwise
	float sweep = ignite * 1.08;
	float vis_ring = smoothstep(sweep, sweep - 0.06, a);
	float w = 0.032 * chalk_width;
	float d = 9.0;                                      // distance to the nearest line, in radii

	// two rings
	float dr = abs(r - 1.0) - 0.0;
	float dr2 = abs(r - 0.865);
	float ring = min(dr / 1.2, dr2 * 1.6);
	d = min(d, mix(9.0, ring, vis_ring));

	// pentagram: 5 strokes joining every second point of a pentagon on the inner ring
	for (int i = 0; i < 5; i++) {
		float a0 = -1.5707963 + 1.2566371 * float(i);
		float a1 = -1.5707963 + 1.2566371 * float((i + 2) % 5);
		vec2 v0 = vec2(cos(a0), sin(a0)) * 0.865;
		vec2 v1 = vec2(cos(a1), sin(a1)) * 0.865;
		float h;
		float ds = seg(p, v0, v1, h);
		float q = clamp((ignite - 0.12 - 0.11 * float(i)) / 0.5, 0.0, 1.0);
		d = min(d, mix(9.0, ds, step(h, q)));
		// a small circle at each point of the star
		float dc = abs(length(p - v0) - 0.06);
		d = min(d, mix(9.0, dc, step(0.02, q)));
	}

	// tick marks between the rings (24 of them, some missing) and ten rune glyphs in the gap
	float ta = a * 24.0 + 0.5;
	float tid = floor(ta);
	float toff = (fract(ta) - 0.5) / 24.0 * 6.2831853 * 1.07;     // arc length across the tick
	float tick_len = step(1.04, r) * step(r, 1.11);
	float tick = mix(9.0, abs(toff), tick_len * step(0.28, h21(vec2(tid, 3.0))));
	d = min(d, mix(9.0, tick, vis_ring));

	float ra = a * 10.0;
	float rid = floor(ra);
	vec2 rl = vec2((fract(ra) - 0.5) / 10.0 * 6.2831853 * 0.93, (r - 0.932) * 1.0);
	float rune_d = 9.0;
	float inside = step(abs(rl.x), 0.2) * step(abs(rl.y), 0.052);
	for (int k = 0; k < 3; k++) {
		float h1 = h21(vec2(rid, float(k) * 7.0 + 1.0));
		float h2 = h21(vec2(rid, float(k) * 7.0 + 2.0));
		float h3 = h21(vec2(rid, float(k) * 7.0 + 3.0));
		float h4 = h21(vec2(rid, float(k) * 7.0 + 4.0));
		vec2 pa = vec2(floor(h1 * 3.0) - 1.0, floor(h2 * 2.0) - 0.5) * vec2(0.08, 0.075);
		vec2 pb = vec2(floor(h3 * 3.0) - 1.0, floor(h4 * 2.0) - 0.5) * vec2(0.08, 0.075);
		pb = mix(pb, pa + vec2(0.0, 0.07), step(length(pb - pa), 0.001));
		float hh;
		rune_d = min(rune_d, seg(rl, pa, pb, hh));
	}
	d = min(d, mix(9.0, rune_d * 1.15, vis_ring * inside));

	// the line mask and its halo
	float m = 1.0 - smoothstep(w * 0.55, w, d);
	float halo = exp(-d * 11.0) * step(d, 8.0) * smoothstep(1.22, 1.06, r);
	float disc = (1.0 - smoothstep(0.0, 1.02, r)) * flare;

	// glow layer (HDR)
	vec3 col_g = amber * (m * 1.9 + halo * 0.9 + disc * 0.7) * max(glow, 0.0);
	col_g += vec3(1.0, 0.8, 0.5) * m * m * 0.35 * glow;
	float a_g = clamp((m + halo * 0.55 + disc * 0.45) * min(glow, 1.0), 0.0, 1.0);

	// chalk layer: broken lines, smudged
	float n1 = noise(p * 38.0);
	float n2 = noise(p * 9.0 + 3.0);
	float broken = mix(smoothstep(0.30, 0.58, n1) * (0.55 + 0.45 * n2), mix(0.82, 1.0, n2), chalk_solid);
	float smudge = (1.0 - smoothstep(0.0, 0.1, d)) * 0.16 * n2;
	float a_c = (m * broken + smudge) * chalk_alpha * chalk;

	ALPHA = clamp(a_g + a_c, 0.0, 1.0);
	ALBEDO = (col_g + chalk_col * a_c) / max(ALPHA, 0.0001);      // the glow part is HDR: do not clamp it
	if (ALPHA < 0.01) {
		discard;
	}
}
"""

const COLUMN_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float intensity = 0.0;
uniform float height = 6.0;
uniform float scroll = 0.0;
uniform vec3 col : source_color = vec3(1.0, 0.55, 0.14);
varying float vy;

void vertex() {
	vy = VERTEX.y / height + 0.5;
}

void fragment() {
	float fall = pow(clamp(1.0 - vy, 0.0, 1.0), 1.6) * smoothstep(0.0, 0.05, vy);
	float s = 0.55 + 0.45 * sin(UV.x * 62.8318 + scroll * 6.0 + vy * 9.0);
	float s2 = 0.6 + 0.4 * sin(UV.x * 25.1327 - scroll * 4.0 - vy * 5.0);
	ALBEDO = col * intensity * fall * s * s2 * 2.4;
	ALPHA = 1.0;
}
"""

const SHOCK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float t = 0.0;               // 0..1 expansion
uniform float radius = 2.9;
uniform vec3 col : source_color = vec3(1.0, 0.62, 0.2);
varying vec2 pp;

void vertex() {
	pp = VERTEX.xz / radius;
}

void fragment() {
	float r = length(pp);
	float front = mix(0.15, 1.35, 1.0 - (1.0 - t) * (1.0 - t));
	float width = mix(0.08, 0.18, t);
	float ring = exp(-pow((r - front) / width, 2.0));
	float fade = (1.0 - t) * (1.0 - t);
	ALBEDO = col * ring * fade * 3.0;
	ALPHA = 1.0;
}
"""

const SPARK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float core = smoothstep(1.0, 0.0, d);
	ALBEDO = COLOR.rgb * core * core * 3.0;
	ALPHA = COLOR.a;
}
"""

static var _figure_shader: Shader
static var _column_shader: Shader
static var _shock_shader: Shader
static var _spark_shader: Shader

var radius := 2.9
var floor_mat: ShaderMaterial
var column_mat: ShaderMaterial
var shock_mat: ShaderMaterial
var floor_mesh: MeshInstance3D
var column_mesh: MeshInstance3D
var shock_mesh: MeshInstance3D
var spark_fx: CPUParticles3D
var light: OmniLight3D
var _ignite := 0.0
var _glow := 0.0
var _chalk := 0.0
var _flare := 0.0
var _column := 0.0
var _shock := 0.0
var _light := 0.0


func _init(r: float = 2.9) -> void:
	name = "VanCircle"
	radius = r
	var half := r * 1.25
	floor_mat = _shader_material(_figure(), {"radius": r, "half_size": half})
	floor_mesh = _plane("Figure", half, floor_mat, LIFT)
	shock_mat = _shader_material(_shock_sh(), {"radius": r, "t": 0.0})
	shock_mesh = _plane("Shock", r * 1.6, shock_mat, LIFT + 0.01)
	shock_mesh.visible = false
	var cyl := CylinderMesh.new()
	cyl.top_radius = r * 0.62
	cyl.bottom_radius = r * 0.66
	cyl.height = COLUMN_HEIGHT
	cyl.radial_segments = 24
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	column_mat = _shader_material(_column_sh(), {"height": COLUMN_HEIGHT, "intensity": 0.0})
	column_mesh = MeshInstance3D.new()
	column_mesh.name = "Column"
	column_mesh.mesh = cyl
	column_mesh.material_override = column_mat
	column_mesh.position = Vector3(0, COLUMN_HEIGHT * 0.5 + LIFT, 0)
	column_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	column_mesh.visible = false
	add_child(column_mesh)
	light = OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, 1.8, 0)
	light.light_color = Color(1.0, 0.58, 0.2)
	light.omni_range = r * 2.4
	light.omni_attenuation = 1.3
	light.light_specular = 0.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	add_child(light)
	spark_fx = _make_sparks(r)
	add_child(spark_fx)
	set_figure(0.0, 0.0, 0.0)


func _plane(node_name: String, half: float, mat: ShaderMaterial, y: float) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(half * 2.0, half * 2.0)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = pm
	mi.material_override = mat
	mi.position = Vector3(0, y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _make_sparks(r: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Sparks"
	p.emitting = false
	p.amount = 46
	p.lifetime = 1.3
	p.one_shot = false
	p.explosiveness = 0.0
	p.local_coords = true
	p.draw_order = CPUParticles3D.DRAW_ORDER_INDEX
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = r * 0.85
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 4.2
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.angle_max = 0.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var sm := ShaderMaterial.new()
	if _spark_shader == null:
		_spark_shader = Shader.new()
		_spark_shader.code = SPARK_SHADER
	sm.shader = _spark_shader
	quad.material = sm
	p.mesh = quad
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
	ramp.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	p.color_ramp = ramp
	p.position = Vector3(0, LIFT + 0.05, 0)
	# emit from the ring on the floor, not the whole sphere: flatten the emission to the floor plane
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_height = 0.05
	p.emission_ring_radius = r * 0.92
	p.emission_ring_inner_radius = r * 0.15
	return p


static func _figure() -> Shader:
	if _figure_shader == null:
		_figure_shader = Shader.new()
		_figure_shader.code = FIGURE_SHADER
	return _figure_shader


static func _column_sh() -> Shader:
	if _column_shader == null:
		_column_shader = Shader.new()
		_column_shader.code = COLUMN_SHADER
	return _column_shader


static func _shock_sh() -> Shader:
	if _shock_shader == null:
		_shock_shader = Shader.new()
		_shock_shader.code = SHOCK_SHADER
	return _shock_shader


static func _shader_material(sh: Shader, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m


# --------------------------------------------------------------------------- posing

## ignite 0..1 draws the figure around; glow = amber strength (1 = full, above 1 blooms harder); chalk = chalk amount.
func set_figure(ignite: float, glow: float, chalk: float, flare: float = -1.0) -> void:
	_ignite = clampf(ignite, 0.0, 1.0)
	_glow = maxf(glow, 0.0)
	_chalk = clampf(chalk, 0.0, 1.0)
	if flare >= 0.0:
		_flare = flare
	floor_mat.set_shader_parameter("ignite", _ignite)
	floor_mat.set_shader_parameter("glow", _glow)
	floor_mat.set_shader_parameter("chalk", _chalk)
	floor_mat.set_shader_parameter("flare", _flare)
	floor_mesh.visible = _glow > 0.001 or _chalk > 0.001


func set_column(k: float) -> void:
	_column = clampf(k, 0.0, 1.0)
	column_mat.set_shader_parameter("intensity", _column)
	column_mat.set_shader_parameter("scroll", float(Time.get_ticks_msec()) * 0.001)
	column_mesh.visible = _column > 0.003


## 0 hides the ring; (0, 1) is the shock ring racing outward over the floor; 1 is gone.
func set_shock(t: float) -> void:
	_shock = clampf(t, 0.0, 1.0)
	shock_mat.set_shader_parameter("t", _shock)
	shock_mesh.visible = _shock > 0.001 and _shock < 0.999


func set_light(k: float) -> void:
	_light = maxf(k, 0.0)
	light.light_energy = 9.0 * _light


func sparks(on: bool) -> void:
	spark_fx.emitting = on



## The final state: a faint chalk mark and nothing else.
func settle() -> void:
	set_figure(1.0, 0.0, 1.0, 0.0)
	set_column(0.0)
	set_shock(0.0)
	set_light(0.0)
	sparks(false)
