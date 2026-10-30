class_name NecroLook
extends RefCounted
## LOOK-DEV ONLY (docs/design/necro-look.md): the shared look of the necromancer family (new-themes.md, "Ghost house:
## haunted contracts"): the zombies (ZombieModel), the acolytes (AcolyteModel) and the grimoire (GrimoireModel). Nothing in
## the game, the contracts or the network uses it: only the gym's necro spawns (NecroBody, GymSpawns "necro") and the look
## lab (necro_look_lab.gd).
##
## The necromantic glow is the ghost look the user picked (ghost-look.md, 2026-10-29: "The rim look is really good"): the
## ghost colour (GhostLook.colour, the gym's "Ghost colour" row: pale blue / ecto green) on the eyes, hands, flames and
## pages, and the rim (GhostLook's faceted fresnel) on the raised dead's bodies. The family's other tell is that it is
## monochrome: grey-green dead flesh, soot and ash robes, bone and iron, against the hell family's obsidian, red and ember.
##
## Two live switches (the gym panel's Experiments rows, GymDev.set_experiment -> pick):
##   necro_rim   off | on: the rim on the zombies and the acolytes (the eyes, hands and flames glow either way)
##   grimoire    open | weakened | failing | shut: the state of every grimoire the panel put down
## Every NecroBody is in GhostLook.GROUP, so a "Ghost colour" pick redresses them too (their glow paint is baked into the
## faces, so a refresh rebuilds them).

const RIM := 0.40                   ## the dead's rim gain (under the ghosts' soft 0.55: they are bodies, not ghosts)
const RIM_ACOLYTE := 0.22           ## a living cultist: a faint edge of what it channels
const STATES: Array[String] = ["open", "weakened", "failing", "shut"]   ## GrimoireModel.STATES

static var rim := true
static var grimoire := "open"
## >= 0 freezes every necro shader's clock at this time (the lab's stills); < 0 runs on TIME.
static var clock := -1.0


## Set one switch by the gym's experiment name ("necro_rim", "grimoire") and redress every necro body in the tree. Returns
## false for an unknown name or value.
static func pick(nm: String, value: String) -> bool:
	match nm:
		"necro_rim":
			if value != "off" and value != "on":
				return false
			rim = value == "on"
		"grimoire":
			if not STATES.has(value):
				return false
			grimoire = value
		_:
			return false
	GhostLook.refresh_all()
	return true


## The defaults (rim on, an open grimoire, a live clock): tests and the lab start here.
static func reset() -> void:
	rim = true
	grimoire = "open"
	clock = -1.0


## The necromantic glow: the ghost colour.
static func glow_colour() -> Color:
	return GhostLook.color_now()


## A glow face in the ghost colour, `k` brighter or dimmer (MonsterMaterial's emissive paint).
static func glow(k: float = 1.0) -> Color:
	var c := glow_colour()
	return MonsterModel.glow(Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0)))


## A toon body for the family: the monsters' shader with the ghost rim patched in (GhostLook.body_code), the rim at
## `rim_k` (when the rim switch is on), and the ordinary ink outline (these are bodies and things, not ghosts).
static func body_material(outline_px: float, rim_k: float) -> ShaderMaterial:
	var m := GhostLook.body_material()
	m.set_shader_parameter("ghost_color", glow_colour())
	m.set_shader_parameter("ghost_rim", rim_k if rim else 0.0)
	m.set_shader_parameter("ghost_pulse", 0.3)
	m.set_shader_parameter("ghost_clock", clock)
	if outline_px > 0.0:
		m.next_pass = LowPolyMaterial.outline(outline_px)
	return m


# --- the floor glow: a rising body's mark and the sigil ----------------------------------------------------------------

## A glow on the floor, added (never darker than the floor). sigil 0: a soft pool with one ring (a body about to rise);
## sigil 1: the necromancer's circle, rings, spokes and dots only (never a letter or a glyph: Cast is not a reading game).
## `broken` knocks arcs out of it (a damaged grimoire), `spin` turns it slowly.
const FLOOR_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.70, 0.86, 1.0, 1.0);
uniform float strength = 1.0;
uniform float sigil = 0.0;
uniform float broken = 0.0;
uniform float spin = 0.0;
uniform float pulse = 0.3;
uniform float phase = 0.0;
uniform float clock = -1.0;

float band(float r, float c, float w) {
	return 1.0 - smoothstep(w * 0.5, w, abs(r - c));
}

""" + ShaderHash.GLSL + """
// a segment's number (a whole number) to [0, 1): ShaderHash's lattice hash, never a sine hash
float hash(float n) {
	return h21(vec2(n, 4.0));
}

void fragment() {
	float t = clock < 0.0 ? TIME : clock;
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) + t * spin;
	float pl = 1.0 + pulse * sin(t * 1.25 + phase);
	float v;
	if (sigil < 0.5) {
		float pool = (1.0 - smoothstep(0.0, 0.85, r)) * 0.45;
		float ring = band(r, 0.82, 0.07);
		v = pool + ring * 0.8;
	} else {
		float rings = band(r, 0.94, 0.05) + band(r, 0.85, 0.032) + band(r, 0.56, 0.038) + band(r, 0.24, 0.04) * 0.8;
		float sector = 6.2831853 / 6.0;
		float sa = mod(a + sector * 0.5, sector) - sector * 0.5;
		float spoke = (1.0 - smoothstep(0.016, 0.028, abs(sa) * r)) * step(0.56, r) * step(r, 0.85);
		float da = mod(a, sector) - sector * 0.5;
		vec2 dp = vec2(cos(da), sin(da)) * r - vec2(0.72, 0.0);
		float dot_ = 1.0 - smoothstep(0.045, 0.06, length(dp));
		float tri = (1.0 - smoothstep(0.01, 0.018, abs(abs(sa) * r - (0.56 - r) * 0.55))) * step(0.24, r) * step(r, 0.56);
		float pool = (1.0 - smoothstep(0.1, 1.0, r)) * 0.32;
		v = clamp(rings + spoke + dot_ + tri * 0.7, 0.0, 1.0) + pool;
		float seg = floor((a + 3.14159265) / (6.2831853 / 28.0));
		v *= step(broken, hash(seg)) * 0.85 + 0.15 * (1.0 - step(0.01, broken));
		v = max(v, pool * 0.6);
	}
	v = floor(v * 4.0 + 0.5) / 4.0;
	ALBEDO = tint.rgb * v * strength * pl * 1.25;
	ALPHA = 1.0;
}
"""

static var _floor_shader: Shader


## A floor glow disc `size` across (a PlaneMesh at y 0, lift it a little), its material set for `sigil` and `strength`.
static func floor_glow(size: float, sigil: bool, strength: float, phase: float = 0.0) -> MeshInstance3D:
	if _floor_shader == null:
		_floor_shader = Shader.new()
		_floor_shader.code = FLOOR_SHADER
	var m := ShaderMaterial.new()
	m.shader = _floor_shader
	m.set_shader_parameter("tint", glow_colour())
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("sigil", 1.0 if sigil else 0.0)
	m.set_shader_parameter("phase", phase)
	m.set_shader_parameter("clock", clock)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * size
	var mi := MeshInstance3D.new()
	mi.name = "Sigil" if sigil else "RiseMark"
	mi.mesh = plane
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_flash", true)
	return mi


## Small rising motes in the ghost colour (a body about to rise, a raising, the grimoire's pages): `amount` of them from a
## sphere `radius` round the node, rising `speed`.
static func motes(amount: int, radius: float, speed: float, size: float = 0.05) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Motes"
	p.amount = amount
	p.lifetime = 2.2
	p.preprocess = 2.2
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 18.0
	p.initial_velocity_min = speed * 0.6
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, 0.1, 0)
	var c := glow_colour()
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(c, 0.0), Color(c, 0.9), Color(c, 0.6), Color(c, 0.0)])
	p.color_ramp = ramp
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 4
	sm.rings = 2
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.6, 1.6, 1.6, 1.0)
	sm.material = m
	p.mesh = sm
	p.emitting = true
	p.set_meta("no_flash", true)
	return p


## Grey smoke (a burnt body, a burnt grimoire), or ember sparks when `embers`.
static func smoke(amount: int, radius: float, embers: bool = false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Embers" if embers else "Smoke"
	p.amount = amount
	p.lifetime = 2.8 if not embers else 1.4
	p.preprocess = p.lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 14.0
	p.initial_velocity_min = 0.25 if not embers else 0.5
	p.initial_velocity_max = 0.55 if not embers else 1.1
	p.gravity = Vector3(0.05, 0.12, 0)
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	if embers:
		ramp.colors = PackedColorArray([Color(1.0, 0.8, 0.35, 1.0), Color(1.0, 0.42, 0.1, 0.9), Color(0.5, 0.1, 0.05, 0.0)])
	else:
		ramp.colors = PackedColorArray([Color(0.30, 0.28, 0.27, 0.0), Color(0.30, 0.28, 0.27, 0.55), Color(0.42, 0.40, 0.40, 0.0)])
	p.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5 if not embers else 1.0))
	curve.add_point(Vector2(1.0, 1.6 if not embers else 0.3))
	p.scale_amount_curve = curve
	var sm := SphereMesh.new()
	sm.radius = 0.11 if not embers else 0.03
	sm.height = sm.radius * 2.0
	sm.radial_segments = 5
	sm.rings = 2
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if embers:
		m.albedo_color = Color(2.0, 1.4, 0.8, 1.0)
	sm.material = m
	p.mesh = sm
	p.emitting = true
	p.set_meta("no_flash", true)
	return p
