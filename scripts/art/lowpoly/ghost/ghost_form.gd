class_name GhostForm
extends Node
## LOOK-DEV ONLY (docs/design/haunt-look.md): a hero in ghost form, the whole-body transform you cast on yourself
## (new-themes.md "Ghost house", Ghosts: "For now"; later perhaps what a downed hero becomes). Cosmetic only: it changes
## how one hero model is drawn and nothing else (no state on the Hero, nothing networked). The gym's Experiments row
## "Ghost form" (GymDev "hero_ghost") puts the player's own model in it; the haunt look lab poses Wick and Rebar in it.
##
## It must still read as that player's hero (their own colours) and never as an enemy ghost (GhostLook's rim on a host,
## the wisp: cold pale blue or ecto green, no ink). Two treatments:
##   glass    the hero as it is (its own colours under the room's light) at about half opacity, a warm gold rim on its
##            edges, its ink outline kept round the silhouette (translucent), its shadow kept
##   spirit   the hero's own colours glowing from inside and paled a little, more opaque on the edges than in the middle,
##            the legs fading out toward the floor, a soft warm halo in place of the ink, no shadow
## Both draw the figure as one translucent shape: a depth pass first (every part, before any colour), so a part behind
## another part does not show through it, and the outline or halo only shows round the silhouette.
##
## GhostForm is a node put under the model (apply). Each frame it dresses any new mesh under the model (a rebuilt arm, a
## held item), keeps the fade at the model's feet and copies the model's own grey-out (the downed look). Meshes it cannot
## redraw (any other material) are only made see-through (GeometryInstance3D.transparency). "off" puts everything back.

const TREATMENTS: Array[String] = ["off", "glass", "spirit"]
const WARM := Color(1.0, 0.80, 0.45)   ## the hero's ghost edge: warm, never the enemy ghosts' cold colours
const TREATMENT := {
	"glass": {"alpha": 0.55, "edge_alpha": 0.4, "emit": 0.0, "wash": 0.0, "sat": 1.15, "rim": 0.45, "fade_h": 0.0,
		"ink": 0.85, "halo": 0.0, "shadow": true, "other": 0.45},
	"spirit": {"alpha": 0.42, "edge_alpha": 1.0, "emit": 0.75, "wash": 0.0, "sat": 1.35, "rim": 0.6, "fade_h": 0.75,
		"ink": 0.0, "halo": 0.45, "shadow": false, "other": 0.6},
}
const DEPTH_PRIORITY := -20             ## the depth pass draws before every colour pass
const NAME := "GhostForm"

## The gym's pick (GymDev "hero_ghost"): what the player's model wears; "off" none.
static var treatment := "off"
## >= 0 freezes the pulse at this time (the lab's stills); < 0 runs on TIME.
static var clock := -1.0

const BODY_SHADER := """
shader_type spatial;
render_mode specular_disabled, blend_mix, depth_draw_never, cull_back;

uniform float band_edge = 0.30;
uniform float band_soft = 0.03;
uniform float shade_lift = 0.04;
uniform vec4 amber : source_color = vec4(1.0, 0.58, 0.20, 1.0);
uniform float amber_below = 0.55;
uniform float amber_rim = 0.30;
uniform float desat = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0, 0.80, 0.45, 1.0);
uniform float alpha = 0.45;
uniform float edge_alpha = 0.5;
uniform float emit = 0.0;
uniform float wash = 0.0;
uniform float sat = 1.0;
uniform float rim = 0.5;
uniform float feet_y = 0.0;
uniform float fade_h = 0.0;
uniform float pulse = 0.15;
uniform float phase = 0.0;
uniform float clock = -1.0;
varying vec3 wnormal;
varying float wy;

void vertex() {
	wnormal = normalize((MODEL_NORMAL_MATRIX * NORMAL));
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 c = COLOR.rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(g * 0.8), desat);
	c = clamp(mix(vec3(g), c, sat), 0.0, 1.0);
	c = mix(c, vec3(1.0), wash);
	float t = clock < 0.0 ? TIME : clock;
	float p = 1.0 + pulse * sin(t * 1.6 + phase);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fr = pow(1.0 - ndv, 1.5);
	float below = clamp(-wnormal.y * 0.8 + 0.1, 0.0, 1.0);
	ALBEDO = c * (1.0 - emit);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	vec3 e = c * shade_lift + amber.rgb * c * (below * amber_below + fr * amber_rim) * (1.0 - emit);
	e += c * emit;
	e += rim_color.rgb * rim * fr * p;
	EMISSION = e;
	float fade = fade_h > 0.0 ? smoothstep(feet_y, feet_y + fade_h, wy) : 1.0;
	ALPHA = clamp(alpha * (1.0 + edge_alpha * fr) * fade, 0.0, 1.0);
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float band = smoothstep(band_edge - band_soft, band_edge + band_soft, ndl);
	float lit = band * 0.85 + ndl * 0.15;
	float att = smoothstep(0.30, 0.40, ATTENUATION) * 0.65 + ATTENUATION * 0.35;
	DIFFUSE_LIGHT += LIGHT_COLOR * lit * att / PI;
	DIFFUSE_LIGHT = min(DIFFUSE_LIGHT, vec3(0.85));
}
"""

## Depth only: nothing drawn, the figure's nearest surface written (where the legs have faded out, nothing).
const DEPTH_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;

uniform float feet_y = 0.0;
uniform float fade_h = 0.0;
varying float wy;

void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	if (fade_h > 0.0 && smoothstep(feet_y, feet_y + fade_h, wy) < 0.4) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
"""

## The ink outline's hull (LowPolyMaterial.OUTLINE_SHADER), translucent: behind the depth pass it only shows past the
## silhouette.
const INK_SHADER := """
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, blend_mix, depth_draw_never;

uniform vec4 outline_color : source_color = vec4(0.055, 0.035, 0.03, 1.0);
uniform float alpha = 0.8;
uniform float width_px = 2.4;
uniform float width_world = 0.035;
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
	ALPHA = alpha;
}
"""

static var _body_shader: Shader
static var _depth_shader: Shader
static var _ink_shader: Shader

var model: Node3D
var which := "glass"
var head: ShaderMaterial         ## the chain every redrawn part wears: the depth pass, then the body, then ink or halo
var body: ShaderMaterial
var phase := 0.0
var _orig := {}                  ## GeometryInstance3D -> [material_override, transparency, cast_shadow]


## Put model `m` in treatment `t` ("off" or unknown: back to normal). Returns the GhostForm node (null for off).
static func apply(m: Node3D, t: String) -> GhostForm:
	if m == null:
		return null
	var old := of(m)
	if old != null:
		old.restore()
		m.remove_child(old)
		old.free()
	if not TREATMENT.has(t):
		return null
	var g := GhostForm.new()
	g.name = NAME
	g.model = m
	g.which = t
	g._make()
	m.add_child(g)
	g.scan()
	return g


## The GhostForm on model `m`, or null.
static func of(m: Node3D) -> GhostForm:
	return m.get_node_or_null(NAME) as GhostForm if m != null else null


## Set the gym's pick and dress `m` (the player's model) for it. False for an unknown treatment.
static func pick(m: Node3D, t: String) -> bool:
	if not TREATMENTS.has(t):
		return false
	treatment = t
	apply(m, t)
	return true


func _make() -> void:
	var tr: Dictionary = TREATMENT[which]
	if _body_shader == null:
		_body_shader = Shader.new()
		_body_shader.code = BODY_SHADER
		_depth_shader = Shader.new()
		_depth_shader.code = DEPTH_SHADER
		_ink_shader = Shader.new()
		_ink_shader.code = INK_SHADER
	if GameWorld.fx_rng != null:
		phase = GameWorld.fx_rng.randf_range(0.0, TAU)
	head = ShaderMaterial.new()
	head.shader = _depth_shader
	head.render_priority = DEPTH_PRIORITY
	body = ShaderMaterial.new()
	body.shader = _body_shader
	for k: String in ["alpha", "edge_alpha", "emit", "wash", "sat", "rim", "fade_h"]:
		body.set_shader_parameter(k, float(tr[k]))
	body.set_shader_parameter("rim_color", WARM)
	body.set_shader_parameter("phase", phase)
	body.set_shader_parameter("clock", clock)
	head.set_shader_parameter("fade_h", float(tr["fade_h"]))
	head.next_pass = body
	if float(tr["ink"]) > 0.0:
		var ink := ShaderMaterial.new()
		ink.shader = _ink_shader
		ink.set_shader_parameter("alpha", float(tr["ink"]))
		ink.render_priority = 1
		body.next_pass = ink
	elif float(tr["halo"]) > 0.0:
		var prev: Material = body
		for m in GhostLook.shells(WARM, float(tr["halo"]), 4.5, 1.0, phase, 2):
			m.set_shader_parameter("pulse", 0.15)
			m.render_priority = 1
			prev.next_pass = m
			prev = m


func _process(_delta: float) -> void:
	scan()


## Dress every mesh under the model not dressed yet, and keep the feet fade and the grey-out up to date.
func scan() -> void:
	if model == null:
		return
	var tr: Dictionary = TREATMENT[which]
	for gi in _geometry(model):
		if _orig.has(gi):
			continue
		_orig[gi] = [gi.material_override, gi.transparency, gi.cast_shadow]
		var sm := gi.material_override as ShaderMaterial
		if sm != null and sm.shader != null and sm.shader.code == LowPolyMaterial.SHADER:
			gi.material_override = head
		else:
			gi.transparency = float(tr["other"])
		if not bool(tr["shadow"]):
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var y := model.global_position.y if model.is_inside_tree() else 0.0
	head.set_shader_parameter("feet_y", y)
	body.set_shader_parameter("feet_y", y)
	var own := model.get("_mat") as ShaderMaterial
	if own != null:
		body.set_shader_parameter("desat", own.get_shader_parameter("desat"))


## Put every mesh back as it was.
func restore() -> void:
	for gi: GeometryInstance3D in _orig:
		if not is_instance_valid(gi):
			continue
		var o: Array = _orig[gi]
		gi.material_override = o[0]
		gi.transparency = o[1]
		gi.cast_shadow = o[2]
	_orig.clear()


## How many meshes it redrew (the hero's own parts) and how many it only made see-through.
func counts() -> Vector2i:
	var n := Vector2i.ZERO
	for gi: GeometryInstance3D in _orig:
		if is_instance_valid(gi):
			if gi.material_override == head:
				n.x += 1
			else:
				n.y += 1
	return n


static func _geometry(n: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for c in n.get_children():
		if c is GeometryInstance3D:
			out.append(c)
		out.append_array(_geometry(c))
	return out
