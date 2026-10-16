class_name Toon
extends RefCounted
## Toon material kit for the character look: a 2-band toon ramp that works under the warm key
## light + downlights of DungeonLook, an inverted-hull outline pass that stays a constant number of
## SCREEN pixels wide under the orthographic game camera, and an optional rim/edge highlight.
##
## Three looks share one shader (style is a parameter, not a separate kit):
##   toy    - chunky toon, 2 shading bands, ~2.4 px dark-brown outline
##   heroic - same toon ramp, thinner (~1.3 px) outline
##   flat   - no outline, near-unlit flat colour, strong rim light (graphic look)
##
## Rules from the style guide: hero colours stay MATTE (nothing here goes above 1.0 so DungeonLook's
## HDR bloom never picks it up); only spells glow, glowing eyes are enemy-only.
##
## Meshes must come from ArtMesh (or ArtMesh.prep): the outline pass reads a welded "smooth normal"
## from the vertex colour so hard-edged boxes do not split open at their corners.

const OUTLINE_COLOR := Color(0.16, 0.085, 0.045)   ## dark warm brown

const STYLES := {
	&"toy":    {"outline_px": 2.4, "flat": 0.0, "rim": 0.40, "rim_edge": 0.60, "edge": 0.13},
	&"heroic": {"outline_px": 1.3, "flat": 0.0, "rim": 0.40, "rim_edge": 0.60, "edge": 0.13},
	&"flat":   {"outline_px": 0.0, "flat": 1.0, "rim": 0.95, "rim_edge": 0.50, "edge": 0.13},
}

const TOON_SHADER := """
shader_type spatial;
render_mode specular_disabled;

uniform vec4 albedo : source_color = vec4(0.7, 0.7, 0.7, 1.0);
uniform float band_edge = 0.34;       // N.L above this = the lit band
uniform float band_soft = 0.025;      // a hair of smoothing so the band edge is not aliased
uniform float lit_gain = 1.0;         // how strongly the lit band takes the light colour
uniform vec4 rim_color : source_color = vec4(1.0, 0.9, 0.8, 1.0);
uniform float rim_amount = 0.4;
uniform float rim_edge = 0.6;         // smaller = a wider rim
uniform float flat_amount = 0.0;      // 1 = ignore lights, flat colour
uniform float self_light = 0.0;       // matte lift (used by the reflective crew strips)

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(rim_edge, rim_edge + 0.07, 1.0 - ndv);
	vec3 e = albedo.rgb * (self_light + flat_amount * 0.78) + rim_color.rgb * rim * rim_amount;
	EMISSION = min(e, vec3(0.95));   // never HDR: only spells bloom
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float band = smoothstep(band_edge - band_soft, band_edge + band_soft, ndl);
	// attenuation (omni falloff, shadows) is quantised too, so downlight pools read as bands.
	float att = smoothstep(0.30, 0.40, ATTENUATION) * 0.65 + ATTENUATION * 0.35;
	DIFFUSE_LIGHT += LIGHT_COLOR * band * att * lit_gain * (1.0 - flat_amount) / PI;
	DIFFUSE_LIGHT = min(DIFFUSE_LIGHT, vec3(0.78));   // matte: stacked lights must not push a hero into bloom
}
"""

## Inverted hull. Grown in VIEW space along the (welded) normal's screen direction, so the line is
## the same pixel width on every part; pushed a hair away from the camera so it hides behind the part.
const OUTLINE_SHADER := """
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.16, 0.085, 0.045, 1.0);
uniform float width_px = 2.4;
uniform float width_world = 0.035;    // used when the camera is a perspective one
uniform float z_push = 0.04;

void vertex() {
	vec3 sn = COLOR.rgb * 2.0 - 1.0;
	vec3 nv = normalize(MODELVIEW_NORMAL_MATRIX * sn);
	float w = width_world;
	if (PROJECTION_MATRIX[3][3] > 0.5) {
		w = width_px * 2.0 / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	}
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 d = nv.xy;
	d = d / max(length(d), 0.4);
	vp.xy += d * w;
	vp.z -= z_push;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
"""

static var _toon_shader: Shader
static var _outline_shader: Shader
static var _cache: Dictionary = {}


static func params(style: StringName) -> Dictionary:
	return STYLES.get(style, STYLES[&"toy"])


## A lit toon material in `color` for `style`. opts: rim (Color), rim_amount (float),
## self_light (float), outline (bool, default true), lit_gain (float).
static func material(color: Color, style: StringName = &"toy", opts: Dictionary = {}) -> ShaderMaterial:
	var key := "%s|%s|%s" % [style, color.to_html(false), str(opts)]
	if _cache.has(key):
		return _cache[key]
	if _toon_shader == null:
		_toon_shader = Shader.new()
		_toon_shader.code = TOON_SHADER
	var sp: Dictionary = params(style)
	var m := ShaderMaterial.new()
	m.shader = _toon_shader
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("band_edge", float(sp["edge"]))
	m.set_shader_parameter("flat_amount", float(sp["flat"]))
	var rim_col: Color = opts.get("rim", color.lightened(0.55))
	m.set_shader_parameter("rim_color", rim_col)
	m.set_shader_parameter("rim_amount", float(opts.get("rim_amount", float(sp["rim"]))))
	m.set_shader_parameter("rim_edge", float(sp["rim_edge"]))
	m.set_shader_parameter("self_light", float(opts.get("self_light", 0.0)))
	m.set_shader_parameter("lit_gain", float(opts.get("lit_gain", 1.0)))
	if bool(opts.get("outline", true)) and float(sp["outline_px"]) > 0.0:
		m.next_pass = outline_material(float(sp["outline_px"]), OUTLINE_COLOR)
	_cache[key] = m
	return m


static func outline_material(width_px: float, color: Color = OUTLINE_COLOR) -> ShaderMaterial:
	var key := "outline|%.2f|%s" % [width_px, color.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	if _outline_shader == null:
		_outline_shader = Shader.new()
		_outline_shader.code = OUTLINE_SHADER
	var m := ShaderMaterial.new()
	m.shader = _outline_shader
	m.set_shader_parameter("outline_color", color)
	m.set_shader_parameter("width_px", width_px)
	_cache[key] = m
	return m
