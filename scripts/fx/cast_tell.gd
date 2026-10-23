class_name CastTell
extends Node3D
## THE CAST TELL (docs/design/cast-armed-fx.md, option C "rune + hand", the game's since 2026-10-23): from the moment the recognizer hears the
## trigger word ("cast": VoiceCaster.trigger_heard) until the spell goes off, a chalk rune circle draws itself in on the
## floor under YOUR hero and follows the feet, and a small glow sits at the casting hand (the held component's fist, else
## Wick's wand tip). Then:
##   - the spell word is recognised (spell_spoken) and the cast goes off (Hero.spell_cast): the RELEASE. The rune snaps in
##     toward the target with a flash and fades, the hand flashes, a shock ring plays in the spell's colour. Online the
##     cast lands NetCasts.LEAD later on every machine, so the release waits for that.
##   - the cast is refused (cooldown, out of components, not slotted: spell_spoken with no cast; or a repeat the recognizer
##     ignored): the rune cracks and greys out.
##   - the window runs out after "cast ..." (spell_fizzled): it cracks and greys out (SpellBook.fizzle's puff as ever).
##   - a "cast" buried in chatter quietly expires (VoiceCaster.trigger_dropped): it fades.
##
## The colour A/B (the user, 2026-10-22: "I'm not sure about if the circle should change color or not") is settled (the
## user, 2026-10-23: "For colors - color is fine actually. It works better then I expected. Lets remove the keybinding."):
## colour is the game's tell in normal play, exported builds and crews, with no flag. The gym's F11 went.
##   colour    (the default) the rune floods with the spell's colour on recognition (solid lines; the release is in colour)
##   neutral   (flag only) the rune stays chalk white through to the release; only the release flash is coloured
##   off       nothing is built or drawn (the game before the tell)
## `--cast-tell off|colour|neutral` (Boot, once per run).
##
## YOUR OWN HERO ONLY: no network event yet (other players see only the release, as today). Cosmetic and LOCAL: no
## gameplay state, no randomness (the crack is a hash in the shader). Cheap: two persistent quads (the rune decal and the
## hand glow), built on the first trigger, hidden when idle, no per-frame allocation. The rune draws under the gym's
## hit-area overlay (render priority below it).

const OFF := "off"
const COLOUR := "colour"
const NEUTRAL_MODE := "neutral"
const MODES: Array[String] = [COLOUR, NEUTRAL_MODE, OFF]

const NEUTRAL := Color(0.86, 0.93, 1.0)    ## chalk white: no spell owns it, and it is not the floor's amber
const WINDOW := 1.8            ## Incantation TUNING.window: the trigger waits this long (recognition time) for a spell word
const COUNTDOWN_FROM := 0.6    ## the outer ring starts receding (the window's countdown) after this long armed
const SAFETY := WINDOW + 1.0   ## armed this long with no end event: fade anyway (a trigger the recognizer revised away)
const DRAW_TIME := 0.22
const FLOOD_TIME := 0.10
const RELEASE_TIME := 0.32
const CANCEL_TIME := 0.45
const QUIET_TIME := 0.25
const FOLLOW_RATE := 22.0      ## the rune trails the feet (1/s): about 0.2 u behind at a walk
const LIFT := 0.045
const FLING := 0.6             ## how far the rune is flung toward the target as it snaps
const RENDER_PRIORITY := -2    ## under other floor effects and the gym's hit-area overlay (10)
const RADIUS := {"wick": 0.82, "gasket": 0.92, "rebar": 1.05}

const RUNE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float radius = 0.85;      // world radius of the outer ring
uniform float line_w = 0.065;     // world width of the main lines
uniform float draw = 0.0;         // 0..1: drawn in, clockwise from the aim notch
uniform float remain = 1.0;       // 0..1: the outer ring left (the window's countdown)
uniform float spin = 0.0;         // the rune band's turn (radians)
uniform float aim_ang = 0.0;      // the notch (radians, 0 = screen up, clockwise)
uniform vec3 col = vec3(0.7, 0.85, 1.0);   // linear
uniform float heat = 1.0;         // HDR multiplier (above ~1.1 the bloom catches it)
uniform float alpha = 1.0;
uniform float fill = 0.0;         // a faint wash of the colour inside
uniform float scorch = 0.3;       // a dark wash inside (the lines read against the amber seams)
uniform float crack = 0.0;        // 0..1: the lines break into pieces and grey out
uniform float chalk = 0.0;        // 0..1: dashed, dimmer chalk lines
uniform float flash = 0.0;
uniform float notch = 1.0;
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

void vertex() {
	pp = VERTEX.xz / radius;
}

void fragment() {
	vec2 p = pp;
	float r = length(p);
	float tau = 6.2831853;
	float a = fract(atan(p.x, -p.y) / tau);
	float rel = fract(a - aim_ang / tau);
	float w = line_w / radius;
	float seen = step(rel, draw * 1.02);
	float d = mix(9.0, abs(r - 1.0), seen * step(rel, remain));
	float d_thin = mix(9.0, abs(r - 0.76), seen);

	// the rune band: 7 cells of 2-3 hashed strokes, turning slowly
	float ad = fract(a - spin / tau);
	float cid = floor(ad * 7.0);
	vec2 rl = vec2((fract(ad * 7.0) - 0.5) / 7.0 * tau * 0.88, r - 0.88);
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
	d_thin = min(d_thin, mix(9.0, rune_d, in_band * seen));

	// the aim notch: a chevron just outside the ring
	float c0 = cos(-aim_ang);
	float s0 = sin(-aim_ang);
	vec2 q = vec2(c0 * p.x - s0 * p.y, s0 * p.x + c0 * p.y);
	float dn = min(seg(q, vec2(0.0, -1.24), vec2(-0.13, -1.08)), seg(q, vec2(0.0, -1.24), vec2(0.13, -1.08)));
	d = min(d, mix(9.0, dn, notch * step(0.02, draw)));

	float m = 1.0 - smoothstep(w * 0.5, w, d);
	m = max(m, 1.0 - smoothstep(w * 0.3, w * 0.62, d_thin));
	float br = smoothstep(0.28, 0.55, vn(p * 26.0 + vec2(1.7, 4.2))) * (0.55 + 0.45 * vn(p * 7.0));
	m *= mix(1.0, 0.3 + 0.7 * br, chalk);
	float dd = min(d, d_thin);
	float halo = exp(-dd * 22.0) * step(dd, 8.0) * (1.0 - 0.6 * chalk);
	float pen = 0.0;
	if (draw > 0.0 && draw < 1.0) {
		float da = (rel - draw) * tau;
		pen = exp(-(da * da) / 0.02) * exp(-pow(r - 1.0, 2.0) / 0.004);
	}
	float n = vn(p * 6.5 + vec2(3.1, 7.7));
	float keep = mix(1.0, smoothstep(crack - 0.04, crack + 0.04, n * 0.98 + 0.01), step(0.001, crack));
	m *= keep;
	halo *= keep;
	vec3 c = mix(col, vec3(0.25, 0.25, 0.27), clamp(crack * 1.6, 0.0, 1.0));
	float wash = fill * 0.20 * step(r, 1.0) * (0.35 + 0.65 * r * r);
	float k = heat * (1.0 + flash * 0.8);
	float off = 1.0 - m;
	vec3 rgb = c * (m * k + (halo * k * 0.35 + wash * 0.7) * off) + vec3(1.0) * pen * 1.6;
	float a_l = clamp(m + (halo * 0.35 + wash) * off + pen * 0.8, 0.0, 1.0);
	// the dark layer under the lines: a toon outline and a scorch inside the ring
	float o1 = 1.0 - smoothstep(w * 1.0, w * 1.7, d);
	float o2 = 1.0 - smoothstep(w * 0.62, w * 1.2, d_thin);
	float ol = max(o1, o2) * keep * 0.85;
	float sc = scorch * step(r, 1.0) * (0.55 + 0.45 * r) * smoothstep(0.0, 0.3, draw) * (1.0 - crack);
	float a_d = max(ol, sc);
	vec3 dark = vec3(0.06, 0.045, 0.04) + c * 0.05;
	float a_out = (a_l + a_d * (1.0 - a_l)) * alpha;
	ALPHA = a_out;
	ALBEDO = (rgb + dark * a_d * (1.0 - a_l)) * alpha / max(a_out, 0.0001);
	if (a_out < 0.008) {
		discard;
	}
}
"""

## A camera-facing soft glow (the hand).
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 col = vec3(0.7, 0.85, 1.0);   // linear
uniform float energy = 1.0;
uniform float core = 0.28;

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

enum Phase { IDLE, ARMED, RELEASE, CANCEL }

## The mode (`--cast-tell`; colour without it). Static: it outlives the scene reload between floors.
static var mode := COLOUR
static var _rune_sh: Shader
static var _glow_sh: Shader

var hero: Hero
var aim := Callable()              ## () -> Vector3: where the player aims (PlayerController.aim_point)
var phase := Phase.IDLE
var spell := ""                    ## the recognised spell ("" before the spell word)
var refused := false               ## the current cancel is a refusal (the spell's colour, then the crack)
var rune: MeshInstance3D = null
var glow: MeshInstance3D = null
var _rune_mat: ShaderMaterial = null
var _glow_mat: ShaderMaterial = null
var _t := 0.0                      ## time in the current phase
var _armed_t := 0.0
var _flood := -1.0                 ## time since recognition (-1: not yet)
var _release_in := -1.0            ## online: the cast lands this much later (-1: no release waiting)
var _fizzle := true
var _spin := 0.0
var _clock := 0.0
var _pos := Vector3.ZERO           ## the rune's centre (it trails the feet)
var _target := Vector3.ZERO
var _aim_ang := 0.0
var _remain := 1.0
var _was_mode := COLOUR


## Set the mode ("color" is accepted). False for an unknown name (the mode is unchanged).
static func set_mode(m: String) -> bool:
	var k := m.strip_edges().to_lower()
	if k == "color":
		k = COLOUR
	if not MODES.has(k):
		return false
	mode = k
	return true


## `--cast-tell off|colour|neutral` (Boot, once per run; a menu flag: the menu still opens). An unknown value warns.
static func boot() -> void:
	var v := Boot.arg_value(OS.get_cmdline_user_args(), "--cast-tell")
	if v != "" and not set_mode(v):
		push_warning("--cast-tell: off, colour or neutral (got '%s')" % v)


## Put the tell on `parent` for the local `h`, driven by `caster`'s signals (a VoiceCaster, or any object with
## trigger_heard / spell_spoken / spell_fizzled and optionally trigger_dropped / ignored). `aim_fn` gives the aim point.
static func attach(parent: Node, h: Hero, caster: Object, aim_fn: Callable = Callable()) -> CastTell:
	var t := CastTell.new()
	t.name = "CastTell"
	t.hero = h
	t.aim = aim_fn
	parent.add_child(t)
	t.listen(caster)
	return t


func listen(caster: Object) -> void:
	if caster == null:
		return
	caster.connect(&"trigger_heard", _on_trigger)
	caster.connect(&"spell_spoken", _on_spoken)
	caster.connect(&"spell_fizzled", _on_fizzled)
	if caster.has_signal(&"trigger_dropped"):
		caster.connect(&"trigger_dropped", _on_dropped)
	if caster.has_signal(&"ignored"):
		caster.connect(&"ignored", _on_ignored)
	if hero != null:
		hero.spell_cast.connect(_on_cast)


func _ready() -> void:
	top_level = true
	_was_mode = mode


# --- Events -----------------------------------------------------------------------------------------------------------

## The trigger word was heard. Re-arming while armed restarts the draw.
func arm() -> void:
	if mode == OFF or hero == null or hero.dead:
		return
	_build()
	_fit(_radius())
	phase = Phase.ARMED
	_t = 0.0
	_armed_t = 0.0
	_flood = -1.0
	_release_in = -1.0
	spell = ""
	refused = false
	_pos = hero.global_position
	_update_armed(0.0)


## The spell word was recognised (before or after the cast went off: the order of the handlers doesn't matter). If no
## cast follows in this frame, the cast was refused.
func recognise(id: String) -> void:
	if phase != Phase.ARMED:
		return
	if spell == "":
		spell = id
		_flood = 0.0
	_check_refused.call_deferred()


## The cast went off (Hero.spell_cast): release now, or when it lands online.
func cast_went_off(id: String, online: bool = false) -> void:
	if phase != Phase.ARMED:
		return
	if spell == "":
		spell = id
		_flood = 0.0
	if online:
		if _release_in < 0.0:
			_release_in = NetCasts.LEAD
		return
	release()


func release() -> void:
	if phase != Phase.ARMED:
		return
	phase = Phase.RELEASE
	_t = 0.0
	_release_in = -1.0
	_target = _aim_point()
	var sc := SpellBook.color_of(spell) if spell != "" else NEUTRAL
	if GameWorld.root != null:
		Fx.ring(_pos, _radius() * 1.25, Color(sc, 0.7), 0.22, 0.0, false, 0.6)


## The window ran out (fizzle = true: cracks; false: a quiet fade), or the cast was refused (refuse()).
func cancel(fizzle: bool) -> void:
	if phase != Phase.ARMED:
		return
	phase = Phase.CANCEL
	_fizzle = fizzle
	_t = 0.0
	_release_in = -1.0


## Heard the spell but it can't go off (cooldown, out of components, not slotted, a repeat): the spell's colour (in the
## colour mode), then the crack.
func refuse() -> void:
	if phase != Phase.ARMED:
		return
	refused = true
	cancel(true)


func is_drawn() -> bool:
	return (rune != null and rune.visible) or (glow != null and glow.visible)


func _check_refused() -> void:
	if phase == Phase.ARMED and spell != "" and _release_in < 0.0:
		refuse()


func _on_trigger(_word: String) -> void:
	arm()


func _on_spoken(id: String, _power: float, _heard: String) -> void:
	recognise(id)


func _on_cast(id: String, _power: float) -> void:
	cast_went_off(id, Net.shares_cast(hero))


func _on_fizzled(_heard: String, _reason: String) -> void:
	cancel(true)


func _on_dropped(_word: String) -> void:
	cancel(false)


func _on_ignored(id: String, _heard: String, _reason: String) -> void:
	if phase == Phase.ARMED and spell == "":
		spell = id
		_flood = FLOOD_TIME
	refuse()


# --- Per frame ----------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if mode != _was_mode:
		_was_mode = mode
		if mode == OFF:
			_idle()
	if phase == Phase.IDLE:
		return
	if hero == null or not is_instance_valid(hero) or hero.dead:
		_idle()
		return
	step(delta)


## Advance by `dt` (the tests call it directly).
func step(dt: float) -> void:
	_clock += dt
	_t += dt
	if phase == Phase.ARMED:
		_armed_t += dt
		if _flood >= 0.0:
			_flood += dt
		if _release_in >= 0.0:
			_release_in -= dt
			if _release_in <= 0.0:
				release()
		elif _armed_t > SAFETY:
			cancel(false)
	if phase != Phase.RELEASE:
		_pos = _pos.lerp(hero.global_position, 1.0 - exp(-FOLLOW_RATE * dt))
	_spin += dt * (3.2 if _armed_t < DRAW_TIME else 0.9)
	match phase:
		Phase.ARMED:
			_update_armed(dt)
		Phase.RELEASE:
			_update_release()
		Phase.CANCEL:
			_update_cancel()


func _flood_k() -> float:
	if _flood < 0.0:
		return 0.0
	return clampf(_flood / FLOOD_TIME, 0.0, 1.0)


## The colour the rune shows now: the spell's in the colour mode once recognised, else chalk white.
func rune_color() -> Color:
	if mode == COLOUR and spell != "":
		return NEUTRAL.lerp(SpellBook.color_of(spell), _flood_k() if phase == Phase.ARMED else 1.0)
	return NEUTRAL


func _update_armed(_dt: float) -> void:
	var draw := 1.0 - pow(1.0 - clampf(_armed_t / DRAW_TIME, 0.0, 1.0), 2.0)
	var flood := _flood_k() if mode == COLOUR else 0.0
	_remain = 1.0 if flood > 0.0 else 1.0 - clampf((_armed_t - COUNTDOWN_FROM) / (WINDOW - COUNTDOWN_FROM), 0.0, 1.0)
	var pulse := 1.0 + 0.08 * sin(_clock * 7.0)
	_aim_ang = _facing_angle()
	_place_rune(_pos, 1.0)
	var m := _rune_mat
	m.set_shader_parameter(&"draw", draw)
	m.set_shader_parameter(&"remain", _remain)
	m.set_shader_parameter(&"spin", _spin)
	m.set_shader_parameter(&"aim_ang", _aim_ang)
	m.set_shader_parameter(&"col", _lin(rune_color()))
	m.set_shader_parameter(&"heat", lerpf(1.2, 1.0, flood) * pulse * 0.85)   # (C's rune is a little dimmer: the hand glows too)
	m.set_shader_parameter(&"alpha", 1.0)
	m.set_shader_parameter(&"fill", 0.35 + 0.65 * flood)
	m.set_shader_parameter(&"crack", 0.0)
	m.set_shader_parameter(&"chalk", 0.6 * (1.0 - flood))
	m.set_shader_parameter(&"flash", flood * (1.0 - flood) * 1.2)
	rune.visible = true
	_pose_glow(draw, flood, 1.0, rune_color())


func _update_release() -> void:
	var t := _t
	var snap := clampf(t / 0.07, 0.0, 1.0)
	var fade := clampf((t - 0.07) / (RELEASE_TIME - 0.07), 0.0, 1.0)
	var flash := 1.0 - fade
	var sc := SpellBook.color_of(spell) if spell != "" else NEUTRAL
	var toward := _target - _pos
	toward.y = 0.0
	var fling := toward.limit_length(FLING) * (1.0 - pow(1.0 - clampf(t / RELEASE_TIME, 0.0, 1.0), 2.0))
	_place_rune(_pos + fling, lerpf(1.0, 0.5, snap) - 0.1 * fade)
	var m := _rune_mat
	m.set_shader_parameter(&"draw", 1.0)
	m.set_shader_parameter(&"remain", 1.0)
	m.set_shader_parameter(&"spin", _spin)
	m.set_shader_parameter(&"col", _lin(sc if mode == COLOUR else NEUTRAL))
	m.set_shader_parameter(&"heat", 1.5)
	m.set_shader_parameter(&"alpha", 1.0 - fade)
	m.set_shader_parameter(&"fill", (1.0 - fade) if mode == COLOUR else 0.0)
	m.set_shader_parameter(&"crack", 0.0)
	m.set_shader_parameter(&"chalk", 0.0)
	m.set_shader_parameter(&"flash", flash)
	rune.visible = fade < 1.0
	_pose_glow(1.0, 1.0, (1.0 - fade) * 1.8, sc)   # the hand flashes in the spell's colour (both modes)
	if t >= RELEASE_TIME:
		_idle()


func _update_cancel() -> void:
	var dur := CANCEL_TIME if _fizzle else QUIET_TIME
	var k := clampf(_t / dur, 0.0, 1.0)
	var alpha := 1.0 - (smoothstep(0.45, 1.0, k) if _fizzle else k)
	var col := rune_color() if refused else NEUTRAL
	_place_rune(_pos, 1.0 + 0.1 * k)
	var m := _rune_mat
	m.set_shader_parameter(&"remain", _remain)
	m.set_shader_parameter(&"spin", _spin)
	m.set_shader_parameter(&"col", _lin(col))
	m.set_shader_parameter(&"heat", 1.0 - 0.4 * k)
	m.set_shader_parameter(&"alpha", alpha)
	m.set_shader_parameter(&"fill", 0.35 * (1.0 - k))
	m.set_shader_parameter(&"crack", k if _fizzle else 0.0)
	m.set_shader_parameter(&"flash", 0.0)
	var sputter := 0.55 + 0.45 * absf(sin(_clock * 41.0)) if _fizzle else 1.0
	_pose_glow(1.0, 0.0, (1.0 - k) * sputter, col.lerp(Color(0.52, 0.52, 0.56), k if _fizzle else 0.0))
	if k >= 1.0:
		_idle()


## The hand's glow: `strength` 0..1 (above 1 flashes).
func _pose_glow(draw: float, flood: float, strength: float, col: Color) -> void:
	glow.visible = strength > 0.01
	if not glow.visible:
		return
	glow.global_position = _hand_point()
	var swell := (0.35 + 0.65 * draw) * (1.0 + 0.12 * sin(_clock * 23.0)) * (1.0 + 0.35 * flood)
	glow.scale = Vector3.ONE * maxf(swell * minf(strength, 1.0) + 0.4 * maxf(strength - 1.0, 0.0), 0.001)
	_glow_mat.set_shader_parameter(&"col", _lin(col))
	_glow_mat.set_shader_parameter(&"energy", 1.4 * strength)


func _idle() -> void:
	phase = Phase.IDLE
	_release_in = -1.0
	if rune != null:
		rune.visible = false
	if glow != null:
		glow.visible = false


# --- Placement ----------------------------------------------------------------------------------------------------------

func _radius() -> float:
	return float(RADIUS.get(hero.kit_id, 0.82)) if hero != null else 0.82


## Where the hand glow sits: the held component (it is in the free hand), else Wick's wand tip, else chest height.
func _hand_point() -> Vector3:
	var model := hero.visual_override as LowPolyModel
	if model != null:
		if model.hold_anchor != null and model.hold_anchor.get_child_count() > 0:
			return model.hold_anchor.global_position + Vector3.UP * 0.05
		var wand := model.parts.get("wand") as Node3D
		if wand != null:
			return wand.global_transform * Vector3(0.0, 0.42, 0.0)
	return hero.global_position + Vector3.UP * 1.0


func _aim_point() -> Vector3:
	var p: Vector3 = aim.call() if aim.is_valid() else hero.global_position + hero.facing * 4.0
	return SpellBook.resolve_target(hero, p) if GameWorld.map != null else p


## The rune lies flat, turned with the camera so its notch angle is measured on screen.
func _place_rune(at: Vector3, scale_k: float) -> void:
	rune.global_position = at + Vector3.UP * LIFT
	rune.global_basis = Basis(Vector3.UP, _cam_yaw()).scaled(Vector3.ONE * scale_k)


func _cam_yaw() -> float:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return deg_to_rad(45.0)
	var f := -cam.global_basis.z
	return atan2(-f.x, -f.z)


## The hero's facing (it faces the aim) in the rune's frame: 0 = screen up, clockwise.
func _facing_angle() -> float:
	var d := hero.facing
	d.y = 0.0
	if d.length() < 0.01:
		return _aim_ang
	var local := Basis(Vector3.UP, _cam_yaw()).inverse() * d
	return atan2(local.x, -local.z)


## SpellBook's colours are sRGB; the shaders work in linear.
static func _lin(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


# --- Building (once, on the first trigger) ------------------------------------------------------------------------------

func _build() -> void:
	if rune != null:
		return
	if _rune_sh == null:
		_rune_sh = Shader.new()
		_rune_sh.code = RUNE_SHADER
		_glow_sh = Shader.new()
		_glow_sh.code = GLOW_SHADER
	_rune_mat = ShaderMaterial.new()
	_rune_mat.shader = _rune_sh
	_rune_mat.render_priority = RENDER_PRIORITY
	rune = MeshInstance3D.new()
	rune.name = "Rune"
	rune.mesh = PlaneMesh.new()
	rune.material_override = _rune_mat
	rune.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rune.top_level = true
	rune.visible = false
	add_child(rune)
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = _glow_sh
	var qm := QuadMesh.new()
	qm.size = Vector2(0.55, 0.55)
	glow = MeshInstance3D.new()
	glow.name = "HandGlow"
	glow.mesh = qm
	glow.material_override = _glow_mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.top_level = true
	glow.visible = false
	add_child(glow)


## Size the rune for the hero (the gym's character switch changes it): only when the size changed.
func _fit(r: float) -> void:
	var pm := rune.mesh as PlaneMesh
	if is_equal_approx(pm.size.x, r * 2.64):
		return
	pm.size = Vector2(r * 2.64, r * 2.64)
	_rune_mat.set_shader_parameter(&"radius", r)
