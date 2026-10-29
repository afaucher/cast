class_name GhostLook
extends RefCounted
## LOOK-DEV ONLY (docs/design/ghost-look.md): the ghost look the user asked to see before anything is built ("hard to see:
## a soft outline on whatever they possess", new-themes.md "Ghost house"). Nothing in the game, the contracts or the
## network uses it: only the gym's ghost spawns (GhostBody, GymSpawns "ghost") and the look lab (ghost_look_lab.gd).
##
## Three switches, live on every GhostBody in the tree (the gym panel's Experiments rows "Ghost look", "Ghost strength",
## "Ghost colour"; GymDev.set_experiment -> pick):
##   look      outline   a soft, slightly blurred pale outline in place of the ink outline, pulsing slowly (three stacked
##                       translucent inverted hulls, widest faintest, so the edge fades out)
##             rim       a glow on the body's own edges (a faceted fresnel added to the toon body's emission) plus a faint
##                       outline
##             shimmer   the outline plus a faint afterimage: the body again, translucent, pushed behind and offset a few
##                       pixels, drifting and wavering
##   strength  faint | soft | strong: how hard the ghost is to see (STRENGTH)
##   colour    pale blue | ecto green
## A wisp (a free ghost) follows the same switches: its body is the translucent glow (WISP_SHADER) at the strength's alpha in
## the colour, with the look's outline, rim or afterimage on top, and a small light in its colour (none when faint).
##
## The host's body (the skeleton, the suit of armour) keeps the monsters' toon body (MonsterMaterial's code, with a ghost rim
## patched in): only its ink outline is replaced. Every pulse runs on the shader's TIME unless `clock` is set (>= 0: the lab's
## stills freeze it).

const GROUP := &"ghost_look"
const LOOKS: Array[String] = ["outline", "rim", "shimmer"]
const STRENGTHS: Array[String] = ["faint", "soft", "strong"]
const COLOURS: Array[String] = ["pale blue", "ecto green"]
const COLOUR := {"pale blue": Color(0.70, 0.86, 1.0), "ecto green": Color(0.55, 1.0, 0.55)}

## Per strength: the outline's alpha and width (px), the rim's gain, the afterimage's alpha, the wisp body's alpha and the
## wisp light's energy, and the glow gain (above 1 the outline blooms a little).
const STRENGTH := {
	"faint": {"alpha": 0.14, "width": 3.0, "rim": 0.22, "after": 0.12, "wisp": 0.08, "light": 0.0, "glow": 0.9},
	"soft": {"alpha": 0.42, "width": 4.5, "rim": 0.55, "after": 0.28, "wisp": 0.22, "light": 0.5, "glow": 1.0},
	"strong": {"alpha": 0.78, "width": 6.0, "rim": 1.10, "after": 0.45, "wisp": 0.50, "light": 1.4, "glow": 1.35},
}
## The soft outline's three shells: [width share, alpha share], innermost first.
const SHELLS := [[0.4, 0.55], [0.7, 0.4], [1.0, 0.28]]
const PULSE := 0.3                  ## how far the outline breathes (alpha and a little width) on its slow sine

static var look := "outline"
static var strength := "soft"
static var colour := "pale blue"
## >= 0 freezes every ghost shader's clock at this time (the lab's stills); < 0 runs on TIME.
static var clock := -1.0


## The ghost's toon body: the monsters' shader (MonsterMaterial) with a ghost rim on the facets that turn away from the view.
const _RIM_UNIFORMS := "uniform vec4 ghost_color : source_color = vec4(0.70, 0.86, 1.0, 1.0);\n" \
		+ "uniform float ghost_rim = 0.0;\nuniform float ghost_pulse = 0.3;\nuniform float ghost_phase = 0.0;\n" \
		+ "uniform float ghost_clock = -1.0;\n"
const _RIM_EMISSION := "\tfloat g_t = ghost_clock < 0.0 ? TIME : ghost_clock;\n" \
		+ "\tfloat g_fr = pow(1.0 - ndv, 1.6);\n" \
		+ "\tEMISSION += ghost_color.rgb * ghost_rim * g_fr * (1.0 + ghost_pulse * sin(g_t * 1.25 + ghost_phase));\n"

## The soft outline: one translucent inverted hull (the ink outline's construction, LowPolyMaterial.OUTLINE_SHADER), pushed
## behind the body so it only shows past the silhouette.
const SHELL_SHADER := """
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled, depth_draw_never, blend_mix;

uniform vec4 ghost_color : source_color = vec4(0.70, 0.86, 1.0, 1.0);
uniform float alpha = 0.4;
uniform float glow = 1.0;
uniform float width_px = 4.5;
uniform float width_world = 0.06;     // used when the camera is a perspective one
uniform float z_push = 0.12;
uniform float pulse = 0.3;
uniform float phase = 0.0;
uniform float clock = -1.0;
varying float v_pulse;

void vertex() {
	float t = clock < 0.0 ? TIME : clock;
	v_pulse = sin(t * 1.25 + phase);
	vec3 sn = CUSTOM0.rgb * 2.0 - 1.0;
	vec3 nv = normalize(MODELVIEW_NORMAL_MATRIX * sn);
	float w = width_world;
	if (PROJECTION_MATRIX[3][3] > 0.5) {
		w = width_px * 2.0 / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	}
	w *= 1.0 + 0.35 * pulse * v_pulse;
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 d = nv.xy;
	d = d / max(length(d), 0.4);
	vp.xy += d * w;
	vp.z -= z_push;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	ALBEDO = ghost_color.rgb * glow;
	ALPHA = clamp(alpha * (1.0 + pulse * v_pulse), 0.0, 1.0);
}
"""

## The shimmer's afterimage: the body again, translucent, behind itself, offset up and to the side and wavering with height.
const AFTER_SHADER := """
shader_type spatial;
render_mode cull_back, unshaded, shadows_disabled, depth_draw_never, blend_mix;

uniform vec4 ghost_color : source_color = vec4(0.70, 0.86, 1.0, 1.0);
uniform float alpha = 0.18;
uniform vec2 drift_px = vec2(15.0, 10.0);
uniform float waver_px = 4.0;
uniform float z_push = 0.25;
uniform float phase = 0.0;
uniform float clock = -1.0;

void vertex() {
	float t = clock < 0.0 ? TIME : clock;
	float px = 0.012;
	if (PROJECTION_MATRIX[3][3] > 0.5) {
		px = 2.0 / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	}
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec2 off = vec2(drift_px.x * (0.65 + 0.35 * sin(t * 0.7 + phase)), drift_px.y * (0.65 + 0.35 * cos(t * 0.53 + phase)));
	off.x += waver_px * sin(vp.y * 4.0 + t * 2.3 + phase);
	vp.xy += off * px;
	vp.z -= z_push;
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = ghost_color.rgb;
	ALPHA = clamp(alpha * (0.55 + 0.6 * (1.0 - ndv)), 0.0, 1.0);
}
"""

## A free ghost's body: translucent, unshaded, brighter and more opaque on the faceted edges (a fresnel), the vertex colour
## its paint (white: the ghost colour; near black: the eye hollows, kept dark and a little more opaque).
const WISP_SHADER := """
shader_type spatial;
render_mode cull_back, unshaded, shadows_disabled, depth_draw_never, blend_mix;

uniform vec4 ghost_color : source_color = vec4(0.70, 0.86, 1.0, 1.0);
uniform float alpha = 0.3;
uniform float edge_k = 1.0;
uniform float glow = 1.0;
uniform float pulse = 0.3;
uniform float phase = 0.0;
uniform float clock = -1.0;

void fragment() {
	float t = clock < 0.0 ? TIME : clock;
	float p = 1.0 + pulse * sin(t * 1.25 + phase);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = pow(1.0 - ndv, 1.4);
	float lum = dot(COLOR.rgb, vec3(0.3333));
	float eye = 1.0 - step(0.25, lum);
	vec3 body = ghost_color.rgb * COLOR.rgb * glow * (0.8 + 0.7 * edge * edge_k);
	ALBEDO = mix(body, vec3(0.03, 0.035, 0.05), eye);
	ALPHA = clamp(mix(alpha * (0.3 + 1.1 * edge * edge_k) * p, min(alpha * 3.0, 0.9), eye), 0.0, 1.0);
}
"""

static var _body_shader: Shader
static var _shell_shader: Shader
static var _after_shader: Shader
static var _wisp_shader: Shader


## Set one switch by the gym's experiment name ("ghost_look", "ghost_strength", "ghost_colour") and redress every ghost in
## the tree. Returns false for an unknown name or value.
static func pick(nm: String, value: String) -> bool:
	match nm:
		"ghost_look":
			if not LOOKS.has(value):
				return false
			look = value
		"ghost_strength":
			if not STRENGTHS.has(value):
				return false
			strength = value
		"ghost_colour":
			if not COLOURS.has(value):
				return false
			colour = value
		_:
			return false
	refresh_all()
	return true


## The defaults (outline, soft, pale blue, live clock): tests and the lab start here.
static func reset() -> void:
	look = "outline"
	strength = "soft"
	colour = "pale blue"
	clock = -1.0


## Redress every GhostBody in the tree with the switches as they are now.
static func refresh_all() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for n in tree.get_nodes_in_group(GROUP):
		if n.has_method("refresh"):
			n.call("refresh")


static func color_now() -> Color:
	return COLOUR[colour]


static func strength_now() -> Dictionary:
	return STRENGTH[strength]


# --- materials ----------------------------------------------------------------------------------------------------------

## A fresh toon body for a possessed host (per body: the monster glow, a tint and the ghost rim are set per figure).
static func body_material() -> ShaderMaterial:
	if _body_shader == null:
		_body_shader = Shader.new()
		_body_shader.code = body_code()
	var m := ShaderMaterial.new()
	m.shader = _body_shader
	m.set_shader_parameter("glow_gain", MonsterModel.GLOW_GAIN)
	return m


## MonsterMaterial's code with the ghost rim spliced in (at the end of fragment()).
static func body_code() -> String:
	var code := MonsterMaterial._code()
	var light_at := code.find("void light()")
	var close := code.rfind("}", light_at)
	assert(code.contains("varying vec3 wnormal;") and light_at > 0 and close > 0, "GhostLook: the toon shader moved")
	code = code.substr(0, close) + _RIM_EMISSION + code.substr(close)
	return code.replace("varying vec3 wnormal;", _RIM_UNIFORMS + "varying vec3 wnormal;")


static func wisp_material() -> ShaderMaterial:
	if _wisp_shader == null:
		_wisp_shader = Shader.new()
		_wisp_shader.code = WISP_SHADER
	var m := ShaderMaterial.new()
	m.shader = _wisp_shader
	return m


## `n` soft outline shells (the widest faintest), `alpha` and `width` px for the whole stack.
static func shells(col: Color, alpha: float, width: float, glow: float, phase: float, n: int = 3) -> Array[ShaderMaterial]:
	if _shell_shader == null:
		_shell_shader = Shader.new()
		_shell_shader.code = SHELL_SHADER
	var out: Array[ShaderMaterial] = []
	var from := SHELLS.size() - n
	for i in range(from, SHELLS.size()):
		var m := ShaderMaterial.new()
		m.shader = _shell_shader
		m.set_shader_parameter("ghost_color", col)
		m.set_shader_parameter("alpha", alpha * float(SHELLS[i][1]))
		m.set_shader_parameter("width_px", width * float(SHELLS[i][0]))
		m.set_shader_parameter("width_world", 0.014 * width * float(SHELLS[i][0]))
		m.set_shader_parameter("glow", glow)
		m.set_shader_parameter("pulse", PULSE)
		m.set_shader_parameter("phase", phase)
		m.set_shader_parameter("clock", clock)
		out.append(m)
	return out


static func afterimage(col: Color, alpha: float, phase: float) -> ShaderMaterial:
	if _after_shader == null:
		_after_shader = Shader.new()
		_after_shader.code = AFTER_SHADER
	var m := ShaderMaterial.new()
	m.shader = _after_shader
	m.set_shader_parameter("ghost_color", col)
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("phase", phase)
	m.set_shader_parameter("clock", clock)
	return m


## The pass chain after the body for the switches as they are now: the look's outline shells, then (shimmer) the afterimage.
static func chain(phase: float) -> Array[ShaderMaterial]:
	var s := strength_now()
	var col := color_now()
	var out: Array[ShaderMaterial] = []
	match look:
		"rim":
			out = shells(col, float(s["alpha"]) * 0.45, float(s["width"]) * 0.7, float(s["glow"]), phase, 2)
		"shimmer":
			out = shells(col, float(s["alpha"]), float(s["width"]), float(s["glow"]), phase)
			out.append(afterimage(col, float(s["after"]), phase))
		_:
			out = shells(col, float(s["alpha"]), float(s["width"]), float(s["glow"]), phase)
	return out


## Dress `base` (a host's toon body or a wisp's body, shared by all its parts) for the switches now: its own parameters and
## the pass chain hung off it.
static func dress(base: ShaderMaterial, wisp: bool, phase: float) -> void:
	var s := strength_now()
	var col := color_now()
	if wisp:
		base.set_shader_parameter("ghost_color", col)
		base.set_shader_parameter("alpha", float(s["wisp"]))
		base.set_shader_parameter("edge_k", 1.7 if look == "rim" else 1.0)
		base.set_shader_parameter("glow", float(s["glow"]))
		base.set_shader_parameter("pulse", PULSE)
		base.set_shader_parameter("phase", phase)
		base.set_shader_parameter("clock", clock)
	else:
		base.set_shader_parameter("ghost_color", col)
		base.set_shader_parameter("ghost_rim", float(s["rim"]) if look == "rim" else 0.0)
		base.set_shader_parameter("ghost_pulse", PULSE)
		base.set_shader_parameter("ghost_phase", phase)
		base.set_shader_parameter("ghost_clock", clock)
	var passes := chain(phase)
	var prev: Material = base
	for m in passes:
		prev.next_pass = m
		prev = m
	prev.next_pass = null


## The pass chain hung off `base` (tests): [base, its next_pass, ...].
static func passes_of(base: Material) -> Array[Material]:
	var out: Array[Material] = []
	var m := base
	while m != null:
		out.append(m)
		m = m.next_pass
	return out
