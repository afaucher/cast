class_name CastArmedFx
extends Node3D
## LOOK-DEV ONLY (docs/design/cast-armed-fx.md): the "cast armed" tell, mocked in five styles for the cast FX lab
## (scripts/fx/cast_fx_lab.gd). NOT wired into the game. It shows the gap between the trigger word ("cast", heard by
## VoiceCaster.trigger_heard) and the spell, then hands off to a release when the spell lands, or breaks up when the
## window runs out with no spell word (a fizzle) or quietly expires (a trigger buried in chatter).
##
##   var fx := CastArmedFx.new("rune")      # rune | hand | rune_hand | glyph | sigil
##   fx.setup(hero, model, "wick", camera)  # (the lab adds it to the scene first)
##   fx.arm()                               # the trigger word was heard
##   fx.recognise("fireball")               # the spell word was recognised: its colour (and, for glyph/sigil, its glyph)
##   fx.release(target)                     # the cast lands (solo: the same frame as recognise; online NetCasts.LEAD later)
##   fx.cancel(true)                        # the window ran out: true = a fizzle (cracks), false = a quiet expiry (fades)
##   fx.step(dt, aim_point)                 # every frame: follow the hero, animate
##
## Styles:
##   rune       (A) a rune circle on the floor under the hero that draws itself in from the aim notch, follows the feet
##   hand       (B) a glow at the casting hand (Wick's wand tip, Gasket's and Rebar's off-hand fist with the component),
##                  with a small light that throws a pool on the floor
##   rune_hand  (C) A's rune (dimmer) + B's glow (no light)
##   glyph      (D) A's rune with a neutral hub that rewrites into the spell's own glyph on recognition
##   sigil      (E) a small camera-facing rune disc above the head
##
## Cosmetic only: no gameplay state, no randomness (the crack noise is a hash in the shader). Neutral arming is a cool
## chalk white (the only cool light in a warm amber room); recognition floods it with the spell's SpellBook colour.

const NEUTRAL := Color(0.86, 0.93, 1.0)
const GREY := Color(0.52, 0.52, 0.56)
const WINDOW := 1.8            ## Incantation TUNING.window: the trigger waits this long (recognition time) for a spell word
const COUNTDOWN_FROM := 0.6    ## the outer ring starts receding (the window's countdown) after this long armed
const DRAW_TIME := 0.22        ## the rune draws itself in
const FLOOD_TIME := 0.10       ## the spell colour floods the lines
const RELEASE_TIME := 0.32
const CANCEL_TIME := 0.45
const QUIET_TIME := 0.25
const FOLLOW_RATE := 22.0      ## the floor rune trails the feet (1/s): about 0.2 u behind at a walk
const LIFT := 0.045
## D's seal on the ring, in radii (screen down = +y): the lower right, in front of the hero whatever the aim.
const SEAL_AT := Vector2(0.574, 0.819)

## Each spell's glyph: strokes [x0, y0, x1, y1] in a unit box (y up on screen). At most 12.
const GLYPHS := {
	"fireball": [[0.0, -0.62, -0.42, -0.12], [-0.42, -0.12, -0.12, 0.30], [-0.12, 0.30, 0.0, 0.70], [0.0, 0.70, 0.18, 0.30],
		[0.18, 0.30, 0.42, -0.12], [0.42, -0.12, 0.0, -0.62], [0.0, -0.38, -0.16, -0.06], [-0.16, -0.06, 0.04, 0.24],
		[0.04, 0.24, 0.16, -0.08], [0.16, -0.08, 0.0, -0.38]],
	"heal": [[-0.58, 0.0, 0.58, 0.0], [0.0, -0.58, 0.0, 0.58], [-0.58, -0.16, -0.58, 0.16], [0.58, -0.16, 0.58, 0.16],
		[-0.16, 0.58, 0.16, 0.58], [-0.16, -0.58, 0.16, -0.58]],
	"corn": [[-0.20, -0.55, -0.26, 0.25], [-0.26, 0.25, 0.0, 0.70], [0.0, 0.70, 0.26, 0.25], [0.26, 0.25, 0.20, -0.55],
		[-0.20, -0.55, 0.20, -0.55], [-0.24, 0.0, 0.24, 0.0], [-0.22, -0.28, 0.22, -0.28], [0.0, -0.55, 0.0, 0.55],
		[-0.20, -0.55, -0.58, 0.05], [0.20, -0.55, 0.58, 0.05]],
	"armor": [[-0.50, 0.55, 0.50, 0.55], [0.50, 0.55, 0.46, -0.08], [0.46, -0.08, 0.0, -0.66], [0.0, -0.66, -0.46, -0.08],
		[-0.46, -0.08, -0.50, 0.55], [-0.26, 0.20, 0.0, -0.10], [0.0, -0.10, 0.26, 0.20]],
	"tentacles": [[0.0, -0.70, 0.30, -0.42], [0.30, -0.42, 0.24, -0.06], [0.24, -0.06, -0.08, 0.10], [-0.08, 0.10, -0.30, 0.36],
		[-0.30, 0.36, -0.16, 0.62], [-0.16, 0.62, 0.10, 0.62], [0.10, 0.62, 0.14, 0.42], [0.14, 0.42, -0.02, 0.36]],
	"teeth": [[-0.62, 0.34, 0.62, 0.34], [-0.62, 0.34, -0.40, -0.30], [-0.40, -0.30, -0.18, 0.34], [-0.18, 0.34, 0.0, -0.40],
		[0.0, -0.40, 0.18, 0.34], [0.18, 0.34, 0.40, -0.30], [0.40, -0.30, 0.62, 0.34]],
	"vines": [[0.0, -0.70, 0.0, 0.66], [0.0, -0.20, -0.44, 0.02], [-0.44, 0.02, -0.04, 0.10], [0.0, 0.22, 0.44, 0.46],
		[0.44, 0.46, 0.04, 0.50], [0.0, -0.50, 0.32, -0.34], [0.32, -0.34, 0.02, -0.28]],
	"damp": [[0.0, 0.72, -0.40, -0.10], [-0.40, -0.10, -0.24, -0.52], [-0.24, -0.52, 0.24, -0.52], [0.24, -0.52, 0.40, -0.10],
		[0.40, -0.10, 0.0, 0.72], [-0.14, -0.22, -0.02, -0.36]],
	"coffee": [[-0.46, 0.24, -0.36, -0.52], [-0.36, -0.52, 0.32, -0.52], [0.32, -0.52, 0.42, 0.24], [0.42, 0.24, -0.46, 0.24],
		[0.40, 0.10, 0.66, 0.02], [0.66, 0.02, 0.38, -0.26], [-0.12, 0.40, -0.02, 0.72], [0.12, 0.40, 0.22, 0.72]],
	"chicken": [[0.0, -0.66, 0.0, 0.08], [0.0, 0.08, -0.48, 0.60], [0.0, 0.08, 0.0, 0.72], [0.0, 0.08, 0.48, 0.60],
		[0.0, -0.66, -0.20, -0.52]],
	"revive": [[0.0, -0.70, -0.30, -0.20], [-0.30, -0.20, -0.14, 0.40], [-0.14, 0.40, 0.10, 0.72], [0.0, -0.70, 0.30, -0.20],
		[0.30, -0.20, 0.22, 0.36], [0.22, 0.36, 0.10, 0.72], [-0.26, -0.06, -0.40, 0.02], [0.27, 0.04, 0.42, 0.12],
		[-0.48, -0.40, -0.48, 0.0], [-0.62, -0.20, -0.34, -0.20]],
}

const RUNE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float radius = 0.85;      // world radius of the outer ring
uniform float line_w = 0.06;      // world width of the main lines
uniform float draw = 0.0;         // 0..1: the figure drawn in, clockwise from the aim notch
uniform float remain = 1.0;       // 0..1: the outer ring left (the window's countdown, receding back to the notch)
uniform float spin = 0.0;         // the rune band's rotation (radians)
uniform float aim_ang = 0.0;      // the aim notch's angle (radians, 0 = screen up, clockwise)
uniform vec3 col = vec3(0.8, 0.9, 1.0);
uniform float heat = 1.4;         // HDR multiplier (above 1 the bloom picks the lines up)
uniform float alpha = 1.0;
uniform float fill = 0.0;         // a faint wash inside the ring
uniform float scorch = 0.3;       // a dark wash inside the ring (the lines read against the amber seams)
uniform float outline = 0.85;     // a dark toon outline around every line
uniform float crack = 0.0;        // 0..1: the lines break into pieces (a fizzle)
uniform float chalk = 0.0;        // 0..1: dashed, dimmer chalk lines (neutral, before the spell word)
uniform float flash = 0.0;        // a release flash
uniform float notch = 1.0;        // the aim notch
uniform float rings = 1.0;        // the rings and the rune band (0 = only the glyph / hub)
uniform float band = 1.0;         // the rune band between the rings
uniform vec4 glyph[12];
uniform int glyph_n = 0;
uniform float glyph_draw = 0.0;   // 0..1: the glyph's strokes written in order
uniform float glyph_size = 0.46;  // the glyph's half size, in radii
uniform float hub = 0.0;          // the neutral hub (a small ring and a dot) before the spell word
uniform vec2 glyph_at = vec2(0.0); // the glyph's centre, in radii (screen down = +y): D puts it on the ring's front
uniform float medal = 0.0;        // a dark seal behind the glyph that cuts the ring (D)
uniform float medal_r = 0.36;     // the seal's radius, in radii
varying vec2 pp;

""" + ShaderHash.GLSL + """

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
	return length(pa - ba * h);
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

void vertex() {
	pp = VERTEX.xz / radius;
}

void fragment() {
	vec2 p = pp;
	float r = length(p);
	float tau = 6.2831853;
	// angle: 0 at screen up (local -z), clockwise on screen
	float a = fract(atan(p.x, -p.y) / tau);
	float rel = fract(a - aim_ang / tau);
	float w = line_w / radius;
	float d = 9.0;
	float d_thin = 9.0;

	// the outer ring (it carries the countdown) and the inner ring
	float seen = step(rel, draw * 1.02);
	d = min(d, mix(9.0, abs(r - 1.0), seen * step(rel, remain) * rings));
	d_thin = min(d_thin, mix(9.0, abs(r - 0.76), seen * rings));

	// the rune band between the rings: 7 cells, each 2-3 strokes from a hash, turning slowly
	float ad = fract(a - spin / tau);
	float cells = 7.0;
	float cid = floor(ad * cells);
	vec2 rl = vec2((fract(ad * cells) - 0.5) / cells * tau * 0.88, r - 0.88);
	float in_band = step(abs(rl.x), 0.24) * step(abs(rl.y), 0.075);
	float rune_d = 9.0;
	for (int k = 0; k < 3; k++) {
		float h1 = h21(vec2(cid, float(k) * 7.0 + 1.0));
		float h2 = h21(vec2(cid, float(k) * 7.0 + 2.0));
		float h3 = h21(vec2(cid, float(k) * 7.0 + 3.0));
		float h4 = h21(vec2(cid, float(k) * 7.0 + 4.0));
		vec2 pa = vec2(floor(h1 * 3.0) - 1.0, floor(h2 * 2.0) - 0.5) * vec2(0.085, 0.07);
		vec2 pb = vec2(floor(h3 * 3.0) - 1.0, floor(h4 * 2.0) - 0.5) * vec2(0.085, 0.07);
		pb = mix(pb, pa + vec2(0.0, 0.07), step(length(pb - pa), 0.001));
		rune_d = min(rune_d, seg(rl, pa, pb));
	}
	d_thin = min(d_thin, mix(9.0, rune_d, in_band * seen * band * rings));

	// the aim notch: a chevron just outside the ring, pointing where the spell will go
	vec2 q = rot(p, -aim_ang);      // the aim now points to screen up (-y)
	float dn = min(seg(q, vec2(0.0, -1.24), vec2(-0.13, -1.08)), seg(q, vec2(0.0, -1.24), vec2(0.13, -1.08)));
	d = min(d, mix(9.0, dn, notch * step(0.02, draw)));

	// the seal: the ring and its band stop at its edge; its own outline
	float dm = length(p - glyph_at);
	float inside = step(dm, medal_r) * medal;
	d = mix(d, 9.0, inside);
	d_thin = mix(d_thin, 9.0, inside);
	d_thin = min(d_thin, mix(9.0, abs(dm - medal_r), medal * seen));
	// the glyph (written stroke by stroke) and the neutral hub
	vec2 g = vec2(p.x - glyph_at.x, glyph_at.y - p.y) / glyph_size;
	float dg = 9.0;
	for (int i = 0; i < 12; i++) {
		if (i >= glyph_n) {
			break;
		}
		float qd = clamp(glyph_draw * float(glyph_n) - float(i), 0.0, 1.0);
		vec2 s0 = glyph[i].xy;
		vec2 s1 = mix(s0, glyph[i].zw, qd);
		dg = min(dg, mix(9.0, seg(g, s0, s1), step(0.001, qd)));
	}
	d = min(d, dg * glyph_size * 1.0);
	float dh = min(abs(dm - 0.45 * glyph_size), max(dm - 0.1 * glyph_size, 0.0));
	d_thin = min(d_thin, mix(9.0, dh, hub));

	// lines, a soft halo, and a pen spot riding the front while the figure draws in
	float m = 1.0 - smoothstep(w * 0.5, w, d);
	m = max(m, 1.0 - smoothstep(w * 0.3, w * 0.62, d_thin));
	float br = smoothstep(0.28, 0.55, vn(p * 26.0 + vec2(1.7, 4.2))) * (0.55 + 0.45 * vn(p * 7.0));
	m *= mix(1.0, 0.3 + 0.7 * br, chalk);
	float dd = min(d, d_thin);
	float halo = exp(-dd * 22.0) * step(dd, 8.0) * (1.0 - 0.6 * chalk);
	float pen = 0.0;
	if (draw > 0.0 && draw < 1.0) {
		float da = (rel - draw) * tau;
		pen = exp(-(da * da) / 0.02) * exp(-pow(r - 1.0, 2.0) / 0.004) * rings;
	}
	// a fizzle: pieces drop out (a hash noise over the figure) and the colour goes grey
	float n = vn(p * 6.5 + vec2(3.1, 7.7));
	float keep = mix(1.0, smoothstep(crack - 0.04, crack + 0.04, n * 0.98 + 0.01), step(0.001, crack));
	m *= keep;
	halo *= keep;
	vec3 c = mix(col, vec3(0.52, 0.52, 0.56), clamp(crack * 1.6, 0.0, 1.0));
	float wash = fill * 0.20 * step(r, 1.0) * (0.35 + 0.65 * r * r) * rings;
	float k = heat * (1.0 + flash * 0.8);
	float off = 1.0 - m;
	vec3 rgb = c * (m * k + (halo * k * 0.35 + wash * 0.7) * off) + vec3(1.0) * pen * 1.6;
	float a_l = clamp(m + (halo * 0.35 + wash) * off + pen * 0.8, 0.0, 1.0);
	// the dark layer under the lines: a toon outline, the seal's disc and a scorch inside the ring
	float o1 = 1.0 - smoothstep(w * 1.0, w * 1.7, d);
	float o2 = 1.0 - smoothstep(w * 0.62, w * 1.2, d_thin);
	float ol = max(o1, o2) * keep * outline;
	float disc = inside * seen * 0.7 * keep;
	float sc = scorch * step(r, 1.0) * (0.55 + 0.45 * r) * rings * smoothstep(0.0, 0.3, draw) * (1.0 - crack);
	float a_d = max(max(ol, disc), sc);
	vec3 dark = vec3(0.06, 0.045, 0.04) + c * 0.05;
	float a_out = (a_l + a_d * (1.0 - a_l)) * alpha;
	ALPHA = a_out;
	ALBEDO = (rgb + dark * a_d * (1.0 - a_l)) * alpha / max(a_out, 0.0001);
	if (a_out < 0.008) {
		discard;
	}
}
"""

## A camera-facing soft glow (the hand's orb, its motes, the release's head).
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 col = vec3(0.8, 0.9, 1.0);
uniform float energy = 1.0;
uniform float core = 0.28;        // the bright core's radius (0..1 of the quad)

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float c = 1.0 - smoothstep(core * 0.6, core, d);
	float h = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	ALBEDO = (col * h * 0.9 + mix(col, vec3(1.0), 0.6) * c * 2.2) * energy;
	ALPHA = 1.0;
}
"""

## The release's streak: a flat ribbon from the caster to the target, a bright head and a fading tail.
const STREAK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 col = vec3(1.0);
uniform float energy = 1.0;
varying vec2 lp;

void vertex() {
	lp = vec2(VERTEX.x * 2.0, VERTEX.z + 0.5);   // x across (-1..1), y along (0 = tail, 1 = head)
}

void fragment() {
	float across = 1.0 - smoothstep(0.25, 1.0, abs(lp.x));
	float along = pow(clamp(lp.y, 0.0, 1.0), 1.6);
	float head = smoothstep(0.86, 1.0, lp.y) * (1.0 - smoothstep(0.0, 0.5, abs(lp.x)));
	ALBEDO = (col * across * along * 1.6 + vec3(1.0) * head * 1.5) * energy;
	ALPHA = 1.0;
}
"""

enum Phase { IDLE, ARMING, ARMED, RELEASE, CANCEL }

static var _rune_sh: Shader
static var _glow_sh: Shader
static var _streak_sh: Shader

var style := "rune"
var hero: Hero
var model: LowPolyModel
var kind := "wick"
var camera: Camera3D

var phase := Phase.IDLE
var spell := ""
var _t := 0.0                 ## time in the current phase
var _armed_t := 0.0           ## time since the trigger
var _flood := -1.0            ## time since recognition (-1: not yet)
var _fizzle := true
var _col := NEUTRAL
var _spin := 0.0
var _clock := 0.0
var _aim := Vector3.ZERO
var _target := Vector3.ZERO
var _from := Vector3.ZERO     ## where the release starts (the rune, the hand, the sigil)
var _rune_pos := Vector3.INF

var _rune: MeshInstance3D = null
var _rune_mat: ShaderMaterial = null
var _sigil: MeshInstance3D = null
var _sigil_mat: ShaderMaterial = null
var _rise: MeshInstance3D = null          ## D: the glyph lifting off the floor on release
var _rise_mat: ShaderMaterial = null
var _orb: MeshInstance3D = null
var _orb_mat: ShaderMaterial = null
var _motes: Array[MeshInstance3D] = []
var _light: OmniLight3D = null
var _streak: MeshInstance3D = null
var _streak_mat: ShaderMaterial = null


func _init(s: String = "rune") -> void:
	style = s
	name = "CastArmedFx_" + s


func uses_rune() -> bool:
	return style == "rune" or style == "rune_hand" or style == "glyph"


func uses_hand() -> bool:
	return style == "hand" or style == "rune_hand"


func setup(h: Hero, m: LowPolyModel, k: String, cam: Camera3D) -> void:
	hero = h
	model = m
	kind = k
	camera = cam
	var r := rune_radius()
	if uses_rune():
		_rune_mat = _material(_rune_shader(), {"radius": r, "line_w": 0.065, "heat": 1.12})
		if style == "glyph":
			_rune_mat.set_shader_parameter("medal", 1.0)
			_rune_mat.set_shader_parameter("medal_r", 0.44)
			_rune_mat.set_shader_parameter("glyph_at", SEAL_AT)
			_rune_mat.set_shader_parameter("glyph_size", 0.36)
		_rune = _plane("Rune", r * 1.5, _rune_mat)
	if style == "sigil":
		_sigil_mat = _material(_rune_shader(), {"radius": 0.36, "line_w": 0.05, "heat": 1.6, "notch": 0.0, "band": 0.0,
				"glyph_size": 0.62})
		_sigil = _plane("Sigil", 0.36 * 1.1, _sigil_mat)
	if style == "glyph":
		_rise_mat = _material(_rune_shader(), {"radius": r, "line_w": 0.07, "heat": 1.6, "rings": 0.0, "notch": 0.0,
				"draw": 1.0})
		_rise = _plane("GlyphRise", r * 0.6, _rise_mat)
	if uses_hand():
		_orb_mat = _material(_glow_shader(), {"energy": 0.0})
		_orb = _quad("Orb", 0.8 if style == "hand" else 0.55, _orb_mat)
		if style == "hand":
			for i in 3:
				var mm := _material(_glow_shader(), {"energy": 0.0, "core": 0.45})
				_motes.append(_quad("Mote%d" % i, 0.16, mm))
			_light = OmniLight3D.new()
			_light.name = "HandLight"
			_light.omni_range = 2.0
			_light.omni_attenuation = 1.4
			_light.light_specular = 0.0
			_light.shadow_enabled = false
			_light.light_energy = 0.0
			_light.top_level = true
			add_child(_light)
	_streak_mat = _material(_streak_shader(), {"energy": 0.0})
	_streak = _plane("Streak", 0.5, _streak_mat)
	_streak.visible = false
	_hide_all()


## The rune's outer radius for this hero (Wick's sits inside his bow's charge ring, Hero.CHARGE_RING_RADIUS 1.05, so both
## read; Gasket and Rebar are wider, so theirs are bigger).
func rune_radius() -> float:
	return {"wick": 0.82, "gasket": 0.92, "rebar": 1.05}.get(kind, 0.82) as float


# --- Events ---------------------------------------------------------------------------------------------------------

## The trigger word was heard (VoiceCaster.trigger_heard). Re-arming while armed restarts the draw.
func arm() -> void:
	phase = Phase.ARMING
	_t = 0.0
	_armed_t = 0.0
	_flood = -1.0
	spell = ""
	_col = NEUTRAL
	_rune_pos = _feet()
	_set_glyph(_rune_mat, "")
	_set_glyph(_sigil_mat, "")


## The spell word was recognised (VoiceCaster.spell_spoken / the cast event arriving): take the spell's colour and glyph.
func recognise(id: String) -> void:
	if phase != Phase.ARMING and phase != Phase.ARMED:
		return
	spell = id
	_flood = 0.0
	if style == "glyph":
		_set_glyph(_rune_mat, id)
	if style == "sigil":
		_set_glyph(_sigil_mat, id)


## The cast lands (Hero.spell_cast solo; the cast event's landing time online): snap toward the target and let go.
func release(target: Vector3) -> void:
	if phase == Phase.IDLE or phase == Phase.CANCEL or phase == Phase.RELEASE:
		return
	if _flood < 0.0:
		recognise(spell if spell != "" else "fireball")
	_flood = maxf(_flood, FLOOD_TIME)
	phase = Phase.RELEASE
	_t = 0.0
	_target = target
	var sc := SpellBook.color_of(spell)
	if uses_rune():
		_from = _rune_pos + Vector3.UP * LIFT
	elif style == "sigil":
		_from = _sigil.global_position
	else:
		_from = _orb.global_position
	if uses_rune() and GameWorld.root != null:
		Fx.ring(_rune_pos, rune_radius() * 1.25, Color(sc, 0.7), 0.22, 0.0, false, 0.6)
	if style == "glyph" and _rise != null:
		_set_glyph(_rise_mat, spell)
		_rise_mat.set_shader_parameter("glyph_draw", 1.0)
		_rise_mat.set_shader_parameter("col", _v3(sc))


## The window ran out with no spell word. fizzle = true: the "cast ..." fizzled (garbled, unknown or no spell: the lines
## crack and go grey, SpellBook.fizzle's puff plays); false: a trigger buried in chatter quietly expired (a short fade).
func cancel(fizzle: bool) -> void:
	if phase != Phase.ARMING and phase != Phase.ARMED:
		return
	phase = Phase.CANCEL
	_fizzle = fizzle
	_t = 0.0


func is_busy() -> bool:
	return phase != Phase.IDLE


# --- Per frame ------------------------------------------------------------------------------------------------------

func step(dt: float, aim_point: Vector3) -> void:
	_clock += dt
	_t += dt
	_aim = aim_point
	if phase == Phase.IDLE:
		_hide_all()
		return
	if phase == Phase.ARMING or phase == Phase.ARMED:
		_armed_t += dt
		if phase == Phase.ARMING and _t >= DRAW_TIME:
			phase = Phase.ARMED
	if _flood >= 0.0:
		_flood += dt
	var sc := SpellBook.color_of(spell) if spell != "" else NEUTRAL
	var f := clampf(_flood / FLOOD_TIME, 0.0, 1.0) if _flood >= 0.0 else 0.0
	_col = NEUTRAL.lerp(sc, f)
	# the rune trails the feet a little; it spins fast while drawing in, slowly while it waits
	var feet := _feet()
	if _rune_pos == Vector3.INF:
		_rune_pos = feet
	if phase != Phase.RELEASE:
		_rune_pos = _rune_pos.lerp(feet, 1.0 - exp(-FOLLOW_RATE * dt))
	_spin += dt * (3.2 if phase == Phase.ARMING else 0.9)
	match phase:
		Phase.ARMING, Phase.ARMED:
			_pose_armed(f)
		Phase.RELEASE:
			_pose_release()
		Phase.CANCEL:
			_pose_cancel()


## Armed: drawn in, slowly turning, the notch on the aim, the outer ring counting the window down, a soft pulse.
func _pose_armed(flood: float) -> void:
	var draw := clampf(_armed_t / DRAW_TIME, 0.0, 1.0)
	draw = 1.0 - pow(1.0 - draw, 2.0)
	var remain := 1.0 - clampf((_armed_t - COUNTDOWN_FROM) / (WINDOW - COUNTDOWN_FROM), 0.0, 1.0)
	if flood > 0.0:
		remain = 1.0
	var pulse := 1.0 + 0.08 * sin(_clock * 7.0)
	var heat := lerpf(1.2, 1.0, flood) * pulse   # (a spell colour above ~1.1 blooms and the filmic curve washes it to yellow-white)
	var chalk := 0.6 * (1.0 - flood)
	if style == "rune_hand":
		heat *= 0.8
	if _rune != null:
		_rune.visible = true
		_place_rune(_rune_pos, 1.0)
		_rune_set({"draw": draw, "remain": remain, "spin": _spin, "aim_ang": _aim_angle(_rune_pos), "heat": heat,
				"alpha": 1.0, "fill": 0.35 + 0.65 * flood, "crack": 0.0, "flash": flood * (1.0 - flood) * 1.2,
				"hub": (1.0 if style == "glyph" else 0.0) * (1.0 - flood) * draw, "glyph_draw": flood, "chalk": chalk})
	if _sigil != null:
		_sigil.visible = true
		_place_sigil(0.0, 1.0)
		_sigil_set({"draw": draw, "remain": remain, "spin": _spin, "heat": heat * 1.1, "alpha": 1.0, "fill": 0.5,
				"crack": 0.0, "flash": 0.0, "hub": (1.0 - flood) * draw, "glyph_draw": flood, "chalk": chalk})
	if _orb != null:
		_pose_hand(draw, flood, 1.0)
	_streak.visible = false
	if _rise != null:
		_rise.visible = false


## Release: the figure snaps in toward the feet with a flash, a streak runs to the target, everything lets go.
func _pose_release() -> void:
	var t := _t
	var snap := clampf(t / 0.07, 0.0, 1.0)
	var fade := clampf((t - 0.07) / (RELEASE_TIME - 0.07), 0.0, 1.0)
	var flash := 1.0 - fade
	if _rune != null:
		_rune.visible = fade < 1.0
		_place_rune(_rune_pos, lerpf(1.0, 0.5, snap) - 0.1 * fade)
		_rune_set({"draw": 1.0, "remain": 1.0, "spin": _spin, "aim_ang": _aim_angle(_rune_pos), "heat": 1.6,
				"alpha": 1.0 - fade, "fill": 1.0 - fade, "crack": 0.0, "flash": flash, "hub": 0.0, "glyph_draw": 1.0,
				"chalk": 0.0})
	if _rise != null:
		# the glyph lifts off the floor and swells as it goes
		var up := 1.0 - pow(1.0 - clampf(t / RELEASE_TIME, 0.0, 1.0), 2.0)
		_rise.visible = t < RELEASE_TIME
		var seal := Basis(Vector3.UP, _cam_yaw()) * Vector3(SEAL_AT.x, 0.0, SEAL_AT.y) * rune_radius() * 0.5
		_place_billboard(_rise, _rune_pos + seal + Vector3.UP * (0.15 + 1.0 * up), 0.8 + 0.6 * up)
		_rise_mat.set_shader_parameter("alpha", 1.0 - clampf((t - 0.12) / (RELEASE_TIME - 0.12), 0.0, 1.0))
	var head_k := clampf(t / 0.12, 0.0, 1.0)
	var head := _from.lerp(_target + Vector3.UP * 0.06, 1.0 - pow(1.0 - head_k, 2.0))
	if _sigil != null:
		_sigil.visible = t < RELEASE_TIME
		_sigil.global_position = head if head_k < 1.0 else _target + Vector3.UP * 0.3
		_orient_billboard(_sigil, lerpf(1.0, 0.55, head_k) * (1.0 + flash * 0.4))
		_sigil_set({"draw": 1.0, "remain": 1.0, "spin": _spin, "heat": 1.7, "alpha": 1.0 - fade, "fill": 1.0,
				"crack": 0.0, "flash": flash, "hub": 0.0, "glyph_draw": 1.0, "chalk": 0.0})
	if _orb != null:
		_orb.visible = t < RELEASE_TIME
		_orb.global_position = head
		_orb_mat.set_shader_parameter("energy", 3.2 * (1.0 - fade))
		_orb_mat.set_shader_parameter("col", _v3(_col))
		_orb.scale = Vector3.ONE * (1.0 + 0.5 * flash)
		for mo in _motes:
			mo.visible = false
		if _light != null:
			_light.global_position = head + Vector3.UP * 0.2
			_light.light_color = _col
			_light.light_energy = 2.4 * (1.0 - fade)
	# the streak: from where the tell was to the target, its tail chasing its head
	var tail_k := clampf((t - 0.05) / 0.16, 0.0, 1.0)
	var tail := _from.lerp(_target, tail_k * tail_k)
	_streak.visible = t < 0.24 and head.distance_to(tail) > 0.05
	if _streak.visible:
		_place_streak(tail, head, 0.16 if uses_rune() else 0.12)
		_streak_mat.set_shader_parameter("col", _v3(_col))
		_streak_mat.set_shader_parameter("energy", 1.6 * (1.0 - clampf((t - 0.12) / 0.12, 0.0, 1.0)))
	if t >= RELEASE_TIME + 0.05:
		phase = Phase.IDLE
		_hide_all()


## Cancel: a fizzle cracks the lines, greys them and lets them sag out; a quiet expiry just fades.
func _pose_cancel() -> void:
	var dur := CANCEL_TIME if _fizzle else QUIET_TIME
	var k := clampf(_t / dur, 0.0, 1.0)
	var crack := k if _fizzle else 0.0
	var alpha := 1.0 - (smoothstep(0.45, 1.0, k) if _fizzle else k)
	var remain := 1.0 - clampf((_armed_t - COUNTDOWN_FROM) / (WINDOW - COUNTDOWN_FROM), 0.0, 1.0)
	if _rune != null:
		_place_rune(_rune_pos, 1.0 + 0.1 * k)
		_rune_set({"draw": 1.0, "remain": remain, "spin": _spin, "aim_ang": _aim_angle(_rune_pos), "heat": 1.3 * (1.0 - 0.5 * k),
				"alpha": alpha, "fill": 0.35 * (1.0 - k), "crack": crack, "flash": 0.0,
				"hub": 1.0 if style == "glyph" else 0.0, "glyph_draw": 0.0})
	if _sigil != null:
		_place_sigil(-0.5 * k * k if _fizzle else 0.0, 1.0)
		_sigil_set({"draw": 1.0, "remain": remain, "spin": _spin, "heat": 1.3, "alpha": alpha, "fill": 0.5 * (1.0 - k),
				"crack": crack, "flash": 0.0, "hub": 1.0, "glyph_draw": 0.0})
	if _orb != null:
		var sputter := 0.55 + 0.45 * absf(sin(_clock * 41.0)) if _fizzle else 1.0
		_pose_hand(1.0, 0.0, (1.0 - k) * sputter)
		if _fizzle:
			_orb_mat.set_shader_parameter("col", _v3(NEUTRAL.lerp(GREY, k)))
	if k >= 1.0:
		phase = Phase.IDLE
		_hide_all()


## The hand's orb, motes and light at the casting hand (strength 0..1).
func _pose_hand(draw: float, flood: float, strength: float) -> void:
	var at := _hand_point()
	_orb.visible = strength > 0.01
	_orb.global_position = at
	var swell := (0.35 + 0.65 * draw) * (1.0 + 0.12 * sin(_clock * 23.0)) * (1.0 + 0.35 * flood)
	_orb.scale = Vector3.ONE * maxf(swell * strength, 0.001)
	_orb_mat.set_shader_parameter("col", _v3(_col))
	_orb_mat.set_shader_parameter("energy", (1.6 + 1.2 * flood) * strength)
	for i in _motes.size():
		var mo := _motes[i]
		var a := _clock * 5.0 + TAU * i / _motes.size()
		mo.visible = strength > 0.01
		mo.global_position = at + Vector3(cos(a) * 0.2, 0.05 * sin(a * 2.0) + 0.04, sin(a) * 0.2)
		mo.scale = Vector3.ONE * maxf(draw * strength, 0.001)
		var mm := mo.material_override as ShaderMaterial
		mm.set_shader_parameter("col", _v3(_col))
		mm.set_shader_parameter("energy", 1.8 * strength)
	if _light != null:
		_light.global_position = at + Vector3.UP * 0.15
		_light.light_color = _col
		_light.light_energy = (2.6 + 1.0 * flood) * draw * strength


# --- Placement ------------------------------------------------------------------------------------------------------

func _feet() -> Vector3:
	return hero.global_position


## Where the hand glow sits: Wick's wand tip; Gasket's and Rebar's off-hand fist (where the held component is).
func _hand_point() -> Vector3:
	if kind == "wick" and model.parts.has("wand"):
		var wand := model.parts["wand"] as Node3D
		return wand.global_transform * Vector3(0.0, 0.42, 0.0)
	if model.hold_anchor != null:
		return model.hold_anchor.global_position + Vector3.UP * 0.05
	var host: Node3D = model.parts.get("glove_l", model.parts.get("arm_l", model.parts["body"]))
	return host.global_position


## The rune lies flat, turned with the camera so its glyph reads upright on screen.
func _place_rune(at: Vector3, scale_k: float) -> void:
	_rune.global_position = at + Vector3.UP * LIFT
	_rune.global_basis = Basis(Vector3.UP, _cam_yaw()).scaled(Vector3.ONE * scale_k)


func _place_sigil(drop: float, scale_k: float) -> void:
	# above the name (Hero puts it at _ui_top + 0.65), a fixed distance up the screen so it never sits on the text
	var top := float(hero.get("_ui_top"))
	_sigil.global_position = hero.global_position + Vector3.UP * (top + 0.65) + camera.global_basis.y * (0.62 + drop)
	_orient_billboard(_sigil, scale_k)


func _place_billboard(n: Node3D, at: Vector3, scale_k: float) -> void:
	n.global_position = at
	_orient_billboard(n, scale_k)


## A flat plane (normal +Y) turned to face the camera, its local -Z up on screen.
func _orient_billboard(n: Node3D, scale_k: float) -> void:
	var cb := camera.global_basis
	n.global_basis = Basis(cb.x, cb.z, -cb.y).scaled(Vector3.ONE * scale_k)


func _place_streak(tail: Vector3, head: Vector3, width: float) -> void:
	var dir := head - tail
	var len := maxf(dir.length(), 0.001)
	var z := dir / len
	var x := z.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x).normalized()
	if y.y < 0.0:
		y = -y
		x = -x
	_streak.global_basis = Basis(x * width, y, z * len)
	_streak.global_position = (tail + head) * 0.5 + Vector3.UP * LIFT


## The camera's yaw (the rune's local -Z is then screen up).
func _cam_yaw() -> float:
	var f := -camera.global_basis.z
	f.y = 0.0
	return atan2(-f.x, -f.z)


## The aim's angle in the rune's frame (0 = screen up, clockwise), radians.
func _aim_angle(center: Vector3) -> float:
	var d := _aim - center
	d.y = 0.0
	if d.length() < 0.01:
		return 0.0
	var local := Basis(Vector3.UP, _cam_yaw()).inverse() * d
	return atan2(local.x, -local.z)


# --- Building -------------------------------------------------------------------------------------------------------

func _rune_set(params: Dictionary) -> void:
	params["col"] = _v3(_col)
	for k: String in params:
		_rune_mat.set_shader_parameter(k, params[k])


func _sigil_set(params: Dictionary) -> void:
	params["col"] = _v3(_col)
	for k: String in params:
		_sigil_mat.set_shader_parameter(k, params[k])


func _set_glyph(mat: ShaderMaterial, id: String) -> void:
	if mat == null:
		return
	var strokes: Array = GLYPHS.get(id, [])
	var arr := PackedVector4Array()
	for i in 12:
		if i < strokes.size():
			var s: Array = strokes[i]
			arr.append(Vector4(s[0], s[1], s[2], s[3]))
		else:
			arr.append(Vector4.ZERO)
	mat.set_shader_parameter("glyph", arr)
	mat.set_shader_parameter("glyph_n", strokes.size())


func _hide_all() -> void:
	for n: Node3D in [_rune, _sigil, _rise, _orb, _streak, _light]:
		if n != null:
			n.visible = false
	for mo in _motes:
		mo.visible = false


func _plane(node_name: String, half: float, mat: ShaderMaterial) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = Vector2(half * 2.0, half * 2.0)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.set_meta("no_flash", true)
	add_child(mi)
	return mi


func _quad(node_name: String, size: float, mat: ShaderMaterial) -> MeshInstance3D:
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = qm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.set_meta("no_flash", true)
	add_child(mi)
	return mi


## A colour for the shaders: SpellBook's colours are sRGB, the shaders' ALBEDO is linear.
static func _v3(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


static func _material(sh: Shader, params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	for k: String in params:
		m.set_shader_parameter(k, params[k])
	return m


static func _rune_shader() -> Shader:
	if _rune_sh == null:
		_rune_sh = Shader.new()
		_rune_sh.code = RUNE_SHADER
	return _rune_sh


static func _glow_shader() -> Shader:
	if _glow_sh == null:
		_glow_sh = Shader.new()
		_glow_sh.code = GLOW_SHADER
	return _glow_sh


static func _streak_shader() -> Shader:
	if _streak_sh == null:
		_streak_sh = Shader.new()
		_streak_sh.code = STREAK_SHADER
	return _streak_sh
