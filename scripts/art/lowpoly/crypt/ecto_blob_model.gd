class_name EctoBlobModel
extends MonsterModel
## An ecto blob (docs/design/crypt-pests-look.md; the user, 2026-10-31: "ectoplasm monsters or maybe larger than average
## rats"). THE GAME'S since H3b (haunted-build-plan.md "H3b as built"): the `ecto_blob` monster (EctoBlob) wears the mass of
## faces, the user's pick ("Mass of faces", 2026-10-31; the default variant), its faces bigger than the look test's and their
## eyes glowing in the ghost colour (the user: they "show only as dark specks at the game camera"). The other two variants
## stay look-dev: CryptPest (the gym's crypt look-test spawns) and the look lab (crypt_pests_lab.gd) show them.
## The role is area denial: a slow crawling mass of ectoplasm that leaves a slick behind it (the game's: EctoSlick, drawn
## with EctoplasmLook.trail, the film the user picked for ectoplasm, so the blob and its slick read as one family). Damp
## washes the slick away; any hit kills the blob. Its body is the ectoplasm made solid: SEE-THROUGH (what it has swallowed shows through it), glassy,
## no ink outline, glowing faintly in the ghost colour (GhostLook.colour), brightest on its turned-away facets (a fresnel),
## a slow swirl inside, and a small cold light of its own so it can be found in the dark.
##
## Three variants (VARIANTS, their numbers in SPEC):
##   jelly   a clear dome of jelly about 1.2 across, bones suspended in it: a skull whose sockets glow, ribs, a thigh bone,
##           loose teeth and an old brass key. The skull is its face.
##   faces   a lumpy heap of milky ectoplasm, denser than the jelly, three faces pressing out of it from inside (hollow eyes
##           and an open mouth on a bump), one hand pushing out of its side. FACE_K scales the faces up (1.0 is the look
##           test's) and each hollow eye holds a glowing point in the ghost colour (`face_eyes`, FACE_GLOW).
##   puddle  a low puddle 1.9 across (the ectoplasm look's own film) that humps up in its middle: the hump carries two
##           glowing eyes. Mostly slick, a little creature; the hump rears into a wave for its lunge.
##
## Poses (MonsterModel's hooks): apply_idle(t, speed) breathes at rest, or crawls (speed > 0: a slow peristaltic squash
## and stretch, leaning into it; the puddle's hump rolls forward and sinks); windup(k) gathers up tall and leans back,
## flaring brighter (the lunge's tell); attack_swing() throws itself forward, flattened, a pseudopod shooting out in front
## (the puddle's wave falls forward). pose_preview("windup" / "swing") holds them for the lab.
## Faces local -Z, +X is its right, origin at the floor under its middle. Named parts: body (the jelly; the puddle's hump),
## inside (what the bone jelly has swallowed, opaque, under body), pod (the pseudopod; not the puddle's), eyes (the puddle's,
## on its hump), face_eyes (the mass of faces' glowing eyes, under body). The puddle's flat sheet is `sheet`, EctoplasmLook's own film puddle.

const VARIANTS: Array[String] = ["jelly", "faces", "puddle"]
const NAMES := {"jelly": "Bone jelly", "faces": "Mass of faces", "puddle": "Rising puddle"}
## The game's blob's (the mass of faces') named parts.
const GAME_PARTS: Array[String] = ["body", "face_eyes", "pod"]
const CRAWL_SPEED := 0.6            ## the world speed the crawl is drawn for (slow: the zombie shambles 0.9)
const CRAWL_RATE := 4.2             ## rad / s of the crawl's squash and stretch
const LIGHT := 0.55                 ## its own light's energy (a cold pool round it)
## The mass of faces' faces: this much bigger than the look test's (H3b: they read as dark specks at the game camera) ...
const FACE_K := 1.75
## ... and a glowing point in each hollow eye in the ghost colour (NecroLook.glow; brighter would clamp the hue), so a face
## reads as a face from across a room.
const FACE_GLOW := 1.0

## Per variant: the jelly's alpha (see-through), glow, swirl; the body's size (rx, rz, h) and lobes.
const SPEC := {
	"jelly": {"alpha": 0.26, "glow": 0.62, "swirl": 0.45, "rx": 0.62, "rz": 0.56, "h": 0.78, "lobes": 0.10},
	"faces": {"alpha": 0.74, "glow": 0.55, "swirl": 0.30, "rx": 0.66, "rz": 0.60, "h": 0.66, "lobes": 0.18},
	"puddle": {"alpha": 0.34, "glow": 0.62, "swirl": 0.50, "rx": 0.95, "rz": 0.85, "h": 0.10, "lobes": 0.22},
}
## The mass of faces' faces: [angle round the heap (0 is +X, -PI/2 the front), height share, size, how far it leans out].
const FACES := [[-PI * 0.55, 0.55, 1.45, 0.0], [-PI * 0.88, 0.42, 1.25, 0.15], [-PI * 0.20, 0.36, 1.2, -0.1]]
## A dome's profile, top to base: (radius share, height share). It bulges a little above the floor and tucks in at it.
const PROF: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(0.42, 0.95), Vector2(0.72, 0.80), Vector2(0.92, 0.56),
		Vector2(1.0, 0.30), Vector2(0.97, 0.10), Vector2(0.88, 0.0)]
const FLAT: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(0.55, 0.92), Vector2(0.85, 0.62), Vector2(1.0, 0.22), Vector2(0.96, 0.0)]
const SIDES := 16
const BONE := Color(0.86, 0.82, 0.70)
const BONE_DARK := Color(0.62, 0.58, 0.48)
const BRASS := Color(0.78, 0.60, 0.26)
const VOID := Color(0.05, 0.05, 0.06)
const HOLLOW := Color(0.05, 0.05, 0.06)     ## painted on the jelly: a dark, denser hollow (an eye, a mouth)
const WHITE := Color(1, 1, 1)

## The body's see-through jelly: lit (the room's lights give it a wet shine), brighter and more opaque on the facets that
## turn away from the view, a slow swirl of brighter veins (ShaderHash noise), `flare` brightening it in the wind-up.
## Near-black vertex paint is a hollow: dark and nearly opaque.
const JELLY_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 ecto : source_color = vec4(0.70, 0.86, 1.0, 1.0);
uniform float alpha = 0.3;
uniform float glow = 0.6;
uniform float swirl = 0.4;
uniform float flare = 0.0;
uniform float phase = 0.0;
uniform float clock = -1.0;
varying vec3 lpos;

""" + ShaderHash.GLSL + """
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vn(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float t = clock < 0.0 ? TIME : clock;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = pow(1.0 - ndv, 1.5);
	float lum = dot(COLOR.rgb, vec3(0.3333));
	float hollow = 1.0 - smoothstep(0.02, 0.06, lum);
	vec2 p = vec2(lpos.x + lpos.y * 0.6, lpos.z - lpos.y * 0.4) * 3.2 + vec2(phase, phase * 0.37);
	vec2 wv = vec2(fbm(p + vec2(t * 0.12, -t * 0.09)), fbm(p + vec2(5.2 - t * 0.10, 1.3 + t * 0.07)));
	float n = fbm(p + 1.8 * wv);
	float vein = pow(1.0 - abs(n * 2.0 - 1.0), 6.0);
	ALBEDO = mix(ecto.rgb * 0.30, vec3(0.015, 0.02, 0.03), hollow);
	EMISSION = ecto.rgb * glow * (0.30 + 1.2 * edge + 1.1 * vein * swirl) * (1.0 + flare) * (1.0 - hollow);
	ROUGHNESS = 0.1;
	SPECULAR = 0.6;
	METALLIC = 0.0;
	float a = alpha * (0.55 + 1.3 * edge) * (1.0 - swirl * 0.4 + swirl * 0.8 * n) + vein * swirl * 0.3;
	ALPHA = clamp(mix(a, 0.9, hollow), 0.0, 1.0);
}
"""

## >= 0 freezes every blob's swirl at this time (the lab's stills); < 0 runs on TIME.
static var clock := -1.0
static var _jelly_shader: Shader

var variant := "faces"
var spec: Dictionary
var jelly: ShaderMaterial            ## the body's (and pod's, hump's) material
var light: OmniLight3D
var sheet: Node3D                    ## the puddle's flat sheet (EctoplasmLook's film puddle)
var _hump_h := 0.50


func _init(model_variant: String = "faces") -> void:
	variant = model_variant if VARIANTS.has(model_variant) else "faces"
	spec = SPEC[variant]
	_setup_model("EctoBlobModel", 1.0)
	monster_kind = "ecto_blob"
	_mat = MonsterMaterial.make(0.0)    # what it has swallowed: no ink (it is under the jelly)
	_mat.set_shader_parameter("glow_gain", GLOW_GAIN)
	glow_flare = 0.8
	jelly = jelly_material(float(spec["alpha"]), float(spec["glow"]), float(spec["swirl"]), 1.3 + 2.1 * VARIANTS.find(variant))
	ui_height = 1.0 if variant != "puddle" else 0.8
	has_own_weapon = true
	_build()
	apply_idle(0.0)


## A fresh jelly material in the ghost colour now.
static func jelly_material(a: float, g: float, sw: float, phase: float) -> ShaderMaterial:
	if _jelly_shader == null:
		_jelly_shader = Shader.new()
		_jelly_shader.code = JELLY_SHADER
	var m := ShaderMaterial.new()
	m.shader = _jelly_shader
	m.set_shader_parameter("ecto", EctoplasmLook.color_now())
	m.set_shader_parameter("alpha", a)
	m.set_shader_parameter("glow", g)
	m.set_shader_parameter("swirl", sw)
	m.set_shader_parameter("phase", phase)
	m.set_shader_parameter("clock", clock)
	return m


func is_jelly(part: MeshInstance3D) -> bool:
	return part.material_override == jelly


# ------------------------------------------------------------------ build

func _build() -> void:
	match variant:
		"faces":
			var heap := _jelly_part("body", _faces_soup(), self, Vector3.ZERO)
			_add_part("face_eyes", _face_eyes_soup(), heap, Vector3.ZERO)
		"puddle":
			# the sheet is the ectoplasm look's own film (the slick it leaves; slime's milky sheet hid the hump), the hump its body
			sheet = EctoplasmLook.puddle("film", float(spec["rx"]), 1501)
			sheet.name = "Sheet"
			add_child(sheet)
			var hump := _jelly_part("body", _dome_soup(Vector3.ZERO, 0.42, 0.38, _hump_h, 0.08, 1502), self, Vector3(0, 0.02, -0.05))
			_add_part("eyes", _eyes_soup(), hump, Vector3(0, _hump_h * 0.62, -0.30))
		_:
			var body := _jelly_part("body", _dome_soup(Vector3.ZERO, float(spec["rx"]), float(spec["rz"]), float(spec["h"]), float(spec["lobes"]), 1503), self, Vector3.ZERO)
			_add_part("inside", _bones_soup(), body, Vector3.ZERO)
	if variant != "puddle":
		_jelly_part("pod", _dome_soup(Vector3(0, 0, -0.42), 0.17, 0.42, 0.24, 0.06, 1504), self, Vector3(0, 0, -float(spec["rz"]) * 0.55))
	light = OmniLight3D.new()
	light.name = "EctoLight"
	light.light_color = EctoplasmLook.color_now()
	light.light_energy = LIGHT
	light.omni_range = 2.4
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.position = Vector3(0, 0.45, 0)
	add_child(light)


func _jelly_part(part_name: String, soup: LowPoly.Soup, parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var mi := _add_part(part_name, soup, parent, pos)
	mi.material_override = jelly
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A faceted dome standing on the floor at `c` (its base at c.y): `rx` x `rz` across its widest, `h` tall, its outline
## wobbled by up to `lobes`, the profile `prof` (top to base). A soup of its own (wound outward from its own middle), merged
## at `c`; `col` paints it (white: the ecto colour).
static func _dome_soup(c: Vector3, rx: float, rz: float, h: float, lobes: float, seed_value: int, col: Color = WHITE, prof: Array[Vector2] = PROF) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(seed_value, 0.05)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var k1 := rng.randi_range(2, 3)
	var k2 := rng.randi_range(4, 5)
	var p1 := rng.randf_range(0.0, TAU)
	var p2 := rng.randf_range(0.0, TAU)
	var mid := h * 0.4
	var rings := []
	for ri in prof.size():
		var ring: Array[Vector3] = []
		for i in SIDES:
			var a := TAU * float(i) / float(SIDES)
			var lob := 1.0 + lobes * (0.6 * sin(a * k1 + p1) + 0.4 * sin(a * k2 + p2))
			var r := prof[ri].x * lob
			var y := h * prof[ri].y * (1.0 + 0.5 * lobes * sin(a * k1 + p1) * prof[ri].y) - mid
			var j := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.012 * prof[ri].x
			ring.append(Vector3(cos(a) * rx * r, y, sin(a) * rz * r) + j)
		rings.append(ring)
	var top := Vector3(0, h * (1.0 + 0.5 * lobes) - mid, 0)
	var base := Vector3(0, -mid, 0)
	for i in SIDES:
		var jn := (i + 1) % SIDES
		s.add_tri(top, rings[1][i], rings[1][jn], col)
		for ri in range(1, prof.size() - 1):
			s.add_quad(rings[ri][i], rings[ri][jn], rings[ri + 1][jn], rings[ri + 1][i], col)
		s.add_tri(base, rings[prof.size() - 1][jn], rings[prof.size() - 1][i], col)
	var out := LowPoly.Soup.new(seed_value)
	return out.merge(s, LowPoly.at(c + Vector3(0, mid, 0)))


## The bone jelly's swallowed things: a skull (its sockets glowing in the ghost colour, the jaw hanging), three ribs on a
## bit of spine, a thigh bone, loose teeth and a brass key, all well inside the dome.
func _bones_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1511, 0.06)
	var skull := LowPoly.Soup.new(1512, 0.06)
	blob(skull, Vector3(0, 0.0, 0), Vector3(0.17, 0.155, 0.18), BONE, 1513, 0.10, 1)
	blob(skull, Vector3(0, -0.10, -0.09), Vector3(0.11, 0.07, 0.10), BONE_DARK, 1514, 0.12)
	for x: float in [-1.0, 1.0]:
		blob(skull, Vector3(0.066 * x, 0.0, -0.15), Vector3(0.052, 0.05, 0.035), VOID, 1515 + int(x), 0.1)
		blob(skull, Vector3(0.066 * x, 0.0, -0.172), Vector3(0.028, 0.028, 0.014), NecroLook.glow(1.15), 1517 + int(x), 0.0)
	wedge(skull, Vector3(0, -0.06, -0.18), Vector2(0.036, 0.024), Vector2(0.014, 0.012), 0.05, VOID, 1519)
	for i in 4:
		slab(skull, Vector3(-0.054 + 0.036 * i, -0.125, -0.155), Vector3(0.026, 0.036, 0.024), BONE, 1520 + i)
	# (turned to its front-left and up a little, so a blob facing the crew shows its face to the camera)
	s.merge(skull, LowPoly.at(Vector3(0.04, 0.42, -0.10), Vector3(22, 40, 6)))
	# the ribs on a short spine
	limb(s, Vector3(-0.30, 0.22, 0.05), Vector3(-0.08, 0.30, 0.24), 0.022, 0.02, 5, BONE_DARK, 1525)
	for i in 3:
		var a := Vector3(-0.26 + 0.08 * i, 0.24 + 0.028 * i, 0.09 + 0.06 * i)
		limb(s, a, a + Vector3(0.06, -0.14, -0.10), 0.016, 0.012, 4, BONE, 1526 + i)
		limb(s, a, a + Vector3(-0.12, -0.12, 0.02), 0.016, 0.012, 4, BONE, 1530 + i)
	# a thigh bone, its two knobs
	var fa := Vector3(0.10, 0.14, 0.30)
	var fb := Vector3(0.38, 0.26, 0.02)
	limb(s, fa, fb, 0.03, 0.026, 5, BONE, 1534)
	blob(s, fa, Vector3(0.05, 0.045, 0.05), BONE, 1535, 0.12)
	blob(s, fb, Vector3(0.05, 0.045, 0.05), BONE, 1536, 0.12)
	# loose teeth, a brass key
	var rng := RandomNumberGenerator.new()
	rng.seed = 1537
	for i in 5:
		var p := Vector3(rng.randf_range(-0.32, 0.30), rng.randf_range(0.10, 0.50), rng.randf_range(-0.28, 0.25))
		slab(s, p, Vector3(0.022, 0.04, 0.02), BONE, 1538 + i, Vector3(rng.randf_range(-60, 60), 0, rng.randf_range(-60, 60)))
	var key := LowPoly.Soup.new(1545, 0.05)
	key.merge(LowPoly.cylinder(0.05, 0.05, 0.02, 8, BRASS, 1546), LowPoly.at(Vector3(0, 0, 0), Vector3(90, 0, 0)))
	slab(key, Vector3(0.12, 0, 0), Vector3(0.18, 0.024, 0.02), BRASS, 1547)
	slab(key, Vector3(0.19, -0.03, 0), Vector3(0.024, 0.05, 0.02), BRASS, 1548)
	s.merge(key, LowPoly.at(Vector3(-0.24, 0.46, -0.16), Vector3(20, 40, -30)))
	return s


## The mass of faces: a lumpy heap (a big dome and two smaller ones grown into it), three faces pressing out of it (a bump
## with two hollow eyes and an open mouth: dark paint the jelly draws dense) and a hand pushing out of its left side.
func _faces_soup() -> LowPoly.Soup:
	var s := _dome_soup(Vector3.ZERO, 0.66, 0.60, 0.66, 0.18, 1551)
	s.merge(_dome_soup(Vector3(0.40, 0, 0.22), 0.34, 0.32, 0.46, 0.12, 1552))
	s.merge(_dome_soup(Vector3(-0.40, 0, -0.08), 0.30, 0.30, 0.42, 0.12, 1553))
	for i in FACES.size():
		s.merge(_face_soup(float(FACES[i][2]) * FACE_K, 1560 + 10 * i), _face_xf(i))
	# a hand pushing out (fingers spread under the surface)
	var hand := LowPoly.Soup.new(1590, 0.05)
	blob(hand, Vector3.ZERO, Vector3(0.09, 0.10, 0.05), WHITE, 1591, 0.12)
	for i in 4:
		var fa := -0.6 + 0.4 * i
		limb(hand, Vector3(sin(fa) * 0.05, cos(fa) * 0.06, 0), Vector3(sin(fa) * 0.16, cos(fa) * 0.17, -0.02), 0.022, 0.016, 4, WHITE, 1592 + i)
	var hp := Vector3(-0.62, 0.30, 0.10)
	s.merge(hand, Transform3D(Basis.looking_at(Vector3(-1, 0.2, 0.2).normalized(), Vector3.UP), hp))
	return s


## Where face `i` sits on the heap (its front -Z out of the surface).
static func _face_xf(i: int) -> Transform3D:
	var fc: Array = FACES[i]
	var a := float(fc[0])
	var p := Vector3(cos(a) * 0.62, 0.66 * float(fc[1]), sin(a) * 0.56)
	var nrm := (p - Vector3(0, 0.18, 0)).normalized()
	return Transform3D(Basis.looking_at(nrm, Vector3.UP).rotated(nrm, float(fc[3])), p)


## The glowing points in the faces' hollow eyes (opaque, the monster material's glow), just inside each hollow.
func _face_eyes_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1581, 0.04)
	for i in FACES.size():
		var k := float(FACES[i][2]) * FACE_K
		var f := LowPoly.Soup.new(1582 + i, 0.04)
		for x: float in [-1.0, 1.0]:
			blob(f, Vector3(0.056 * x, 0.045, -0.12) * k, Vector3(0.03, 0.032, 0.012) * k, NecroLook.glow(FACE_GLOW), 1584 + 2 * i + int(x), 0.0)
		s.merge(f, _face_xf(i))
	return s


## One face pressing out (its front -Z, origin on the heap's surface): a bump, brow ridges, two hollow eyes, an open mouth.
func _face_soup(k: float, seed_value: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(seed_value, 0.05)
	blob(s, Vector3(0, 0, -0.03), Vector3(0.15, 0.18, 0.10) * k, WHITE, seed_value + 1, 0.12, 1)
	for x: float in [-1.0, 1.0]:
		blob(s, Vector3(0.056 * x, 0.045, -0.10) * k, Vector3(0.042, 0.048, 0.022) * k, HOLLOW, seed_value + 2 + int(x), 0.1)
		blob(s, Vector3(0.06 * x, 0.09, -0.09) * k, Vector3(0.05, 0.02, 0.025) * k, WHITE, seed_value + 4 + int(x), 0.1)
	blob(s, Vector3(0, -0.08, -0.10) * k, Vector3(0.042, 0.06, 0.022) * k, HOLLOW, seed_value + 6, 0.1)
	blob(s, Vector3(0, -0.01, -0.10) * k, Vector3(0.018, 0.03, 0.02) * k, WHITE, seed_value + 7, 0.1)
	return s


## The puddle's two eyes on its hump: glowing in the ghost colour, a dark slit in each.
func _eyes_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1601, 0.04)
	for x: float in [-1.0, 1.0]:
		blob(s, Vector3(0.10 * x, 0, 0), Vector3(0.07, 0.075, 0.055), NecroLook.glow(1.1), 1602 + int(x), 0.05, 1)
		slab(s, Vector3(0.10 * x, 0, -0.052), Vector3(0.018, 0.09, 0.014), VOID, 1604 + int(x))
	return s


# ------------------------------------------------------------------ animation

## Rest (breathing) or the crawl (speed > 0: a slow squash and stretch, leaning in), with the wind-up (gathered up tall,
## leaning back, flaring) and the lunge (thrown forward and flat, the pseudopod out) blended over it.
func apply_idle(t: float, speed: float = 0.0) -> void:
	if _downed:
		return
	var crawl := clampf(speed / CRAWL_SPEED, 0.0, 1.0)
	var w := wind_e()
	var sw := _swing
	var ph := t * CRAWL_RATE
	var breath := sin(t * 1.4) * 0.03 * (1.0 - crawl)
	var wave := sin(ph) * crawl
	var flare := 0.8 * w + 0.5 * sw
	jelly.set_shader_parameter("flare", flare)
	if light != null:
		light.light_energy = LIGHT * (1.0 + flare)
	if variant == "puddle":
		# the sheet only stretches (forward in the lunge); the hump does the rest
		sheet.scale = Vector3(1.0 + 0.04 * wave, 1.0, (1.0 + 0.08 * wave) * (1.0 + 0.30 * sw))
		sheet.position = Vector3(0, 0, -0.22 * sw)
		_pose_hump(t, crawl, w, sw)
		return
	var sc := Vector3(1.0 + breath * 0.5 + 0.05 * wave, 1.0 + breath - 0.10 * wave, 1.0 - breath * 0.3 + 0.13 * wave)
	var pz := -0.05 * wave
	var rx := -0.06 * crawl
	sc *= Vector3(1.0 - 0.16 * w, 1.0 + 0.42 * w, 1.0 - 0.16 * w)
	rx += 0.22 * w
	pz += 0.10 * w
	sc *= Vector3(1.0 + 0.08 * sw, 1.0 - 0.38 * sw, 1.0 + 0.45 * sw)
	pz -= 0.26 * sw
	rx -= 0.10 * sw
	var body := parts["body"] as MeshInstance3D
	body.scale = sc
	body.position = Vector3(0, 0, pz)
	body.rotation = Vector3(rx, 0.0, 0.0)
	if parts.has("inside"):
		var inside := parts["inside"] as MeshInstance3D
		inside.rotation.y = 0.25 * sin(t * 0.35)
		inside.position.y = 0.02 * sin(t * 0.8)
	# the pseudopod: out of the front in the lunge only
	var pod := parts["pod"] as MeshInstance3D
	pod.visible = sw > 0.02
	pod.scale = Vector3(1.0, 1.0, maxf(sw, 0.01))
	pod.position = Vector3(0, 0, -float(spec["rz"]) * 0.55 + pz)


## The puddle's hump: rolling forward and sinking in the crawl, rearing into a tall leaning wave in the wind-up, falling
## forward flat in the lunge. Its eyes ride its front.
func _pose_hump(t: float, crawl: float, w: float, sw: float) -> void:
	var hump := parts["body"] as MeshInstance3D
	var roll := fposmod(t * CRAWL_RATE / TAU, 1.0)
	var hz := lerpf(-0.05 + 0.02 * sin(t * 1.1), 0.28 - 0.62 * roll, crawl)
	var hy := lerpf(1.0 + 0.06 * sin(t * 1.4), 0.55 + 0.75 * sin(roll * PI), crawl)
	var sc := Vector3(1.0, hy, 1.0)
	var rx := 0.0
	sc = sc.lerp(Vector3(0.78, 2.3, 0.72), w)
	rx = lerpf(rx, 0.32, w)
	hz = lerpf(hz, 0.10, w)
	sc = sc.lerp(Vector3(0.95, 1.1, 1.9), sw)
	rx = lerpf(rx, -0.55, sw)
	hz = lerpf(hz, -0.42, sw)
	hump.scale = sc
	hump.rotation = Vector3(rx, 0.0, 0.0)
	hump.position = Vector3(0, 0.02, hz)
	var eyes := parts["eyes"] as MeshInstance3D
	eyes.scale = Vector3(1.0 / maxf(sc.x, 0.1), 1.0 / maxf(sc.y, 0.1), 1.0 / maxf(sc.z, 0.1))


func _slump() -> void:
	var body := parts["body"] as MeshInstance3D
	body.scale = Vector3(1.2, 0.25, 1.2)
	jelly.set_shader_parameter("flare", -0.6)
