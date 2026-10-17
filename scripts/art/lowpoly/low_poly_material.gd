class_name LowPolyMaterial
extends RefCounted
## Material for faceted low-poly characters (meshes from LowPoly):
##  - albedo is the per-face painted vertex COLOR (alpha = retro-reflective tape mask)
##  - a toon-ish 2-band light on the FLAT facet normals (plus a hint of N.L so facets still read),
##    quantised omni falloff so the amber downlight pools read as bands, never above bloom
##  - a warm amber bounce from below and at the silhouette edge, so the figure sits in the glowing
##    amber floor instead of floating on it
##  - a dark ink outline: inverted hull grown in VIEW space, a constant number of screen pixels wide
##    under the orthographic game camera. Reads the welded normal from CUSTOM0.

const INK := Color(0.055, 0.035, 0.03)

const SHADER := """
shader_type spatial;
render_mode specular_disabled;

uniform float band_edge = 0.30;       // N.L above this = the lit band
uniform float band_soft = 0.03;
uniform float shade_lift = 0.04;      // keeps the shaded band painted, not black
uniform float lit_gain = 1.0;
uniform vec4 amber : source_color = vec4(1.0, 0.58, 0.20, 1.0);
uniform float amber_below = 0.55;     // bounce from the glowing floor on down-facing facets
uniform float amber_rim = 0.30;       // glow at the silhouette edge
uniform float rim_edge = 0.55;
uniform float tape_glow = 0.30;       // retro-reflective tape lifts itself (never HDR)
uniform float desat = 0.0;            // downed pose
uniform vec4 glow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);   // neon variant (tentacles): emissive on top
uniform float glow_strength = 0.0;    // 0 = the normal toon look
varying vec3 wnormal;

void vertex() {
	wnormal = normalize((MODEL_NORMAL_MATRIX * NORMAL));
}

void fragment() {
	vec3 c = COLOR.rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(g * 0.8), desat);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(rim_edge, rim_edge + 0.12, 1.0 - ndv);
	float below = clamp(-wnormal.y * 0.8 + 0.1, 0.0, 1.0);
	vec3 e = c * shade_lift;
	e += amber.rgb * c * (below * amber_below + rim * amber_rim);
	e += c * COLOR.a * tape_glow;
	EMISSION = min(e, vec3(0.95)) + glow_color.rgb * glow_strength;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float band = smoothstep(band_edge - band_soft, band_edge + band_soft, ndl);
	float lit = band * 0.85 + ndl * 0.15;
	float att = smoothstep(0.30, 0.40, ATTENUATION) * 0.65 + ATTENUATION * 0.35;
	DIFFUSE_LIGHT += LIGHT_COLOR * lit * att * lit_gain / PI;
	DIFFUSE_LIGHT = min(DIFFUSE_LIGHT, vec3(0.85));
}
"""

const OUTLINE_SHADER := """
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.055, 0.035, 0.03, 1.0);
uniform float width_px = 2.4;
uniform float width_world = 0.035;    // used when the camera is a perspective one
uniform float z_push = 0.04;

void vertex() {
	vec3 sn = CUSTOM0.rgb * 2.0 - 1.0;
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

static var _shader: Shader
static var _outline_shader: Shader


## A fresh material (not cached: per-model so each figure can desaturate on its own).
static func make(outline_px: float = 2.4) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	if outline_px > 0.0:
		m.next_pass = outline(outline_px)
	return m


static func outline(width_px: float = 2.4, color: Color = INK) -> ShaderMaterial:
	if _outline_shader == null:
		_outline_shader = Shader.new()
		_outline_shader.code = OUTLINE_SHADER
	var m := ShaderMaterial.new()
	m.shader = _outline_shader
	m.set_shader_parameter("outline_color", color)
	m.set_shader_parameter("width_px", width_px)
	return m


## The same faceted toon look with a neon emissive on top (glow * strength is added after the
## usual "never above bloom" clamp, so it blooms). The outline takes `outline_color`.
static func make_glow(glow: Color, strength: float = 1.0, outline_px: float = 2.4, outline_color: Color = INK) -> ShaderMaterial:
	var m := make(0.0)
	m.set_shader_parameter("glow_color", glow)
	m.set_shader_parameter("glow_strength", strength)
	if outline_px > 0.0:
		m.next_pass = outline(outline_px, outline_color)
	return m
