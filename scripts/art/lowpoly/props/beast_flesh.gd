class_name BeastFlesh
extends RefCounted
## The flesh of the monster under a hellgate room (HellgateBeast): the ENEMY toon look (the heroes' LowPolyMaterial with
## the monsters' glow faces: vertex alpha < 0.75 is emissive) plus what the GPU does, so a tentacle is one mesh and a
## frame costs a few uniform writes:
##
##   - SKELETAL tubes (path_tube): every tentacle of a beast has its centreline in one small float texture (skeleton():
##     4 rows a limb: the points, the ring frames' x and y, and the limb's numbers; a column every BeastLimbs.STEP). A
##     vertex carries its limb (UV.y), its distance along the limb (UV.x), its offset and normal in the ring frame
##     (CUSTOM1, CUSTOM0) and the tube's radius there (UV2.y), and the vertex shader rebuilds it on the centreline at
##     s' = s - d. With d = 0 that is the tube as built; as d grows the whole tube slides back DOWN ITS OWN PATH, tip
##     first, into the dark under the level, and every vertex keeps its own (smaller, tapering) radius, so the exit never
##     passes through anything the resting limb did not already clear.
##   - EXITS (`exit_t` seconds since the gate closed, each limb waits its own delay): `exit_mode` 0 RETRACT (d eases from
##     0 to the limb's length over `exit_len`) or 1 WHIP (the limb snaps 2 units back down its path in 0.1 s while the
##     free part lashes, rebounds once, then drops along its path in 0.35 s).
##   - MOTION of the free part (0 where it grips, the BeastLimbs.Path `free` curve): the tip's sway, more restless at low
##     gate HP (`writhe`), the hurt FLAIL (`hurt` x the limb's weight: a fast thrash up to `flail_max`), the JERK of a hit
##     (the limb flinches back a little along its own path) and the beat's swell (peristalsis). BeastLimbs' envelope is
##     the bound of all of it, so the clearances hold in every pose.
##   - FADE: flesh below `fade_hi` (world y) darkens towards the background by `fade_lo`: the roots under the slab are
##     lost in the dark. PULSE: the glowing faces brighten with the travelling beat (the gate's `beat_rate`).
## Still pieces (Limb.to_mesh: the eye, the jaw) use the same material with `skeletal` off; `sink` slides them down.
## Faces get a flat normal from screen derivatives, so moving tubes stay faceted. Headless-safe: ordinary spatial shaders.
##
## The shader is the heroes' source text (LowPolyMaterial.SHADER) patched like MonsterMaterial's, but against the
## EMISSION line's stable prefix: MonsterMaterial's own patch no longer matches that line (reported separately).

const FLESH_DARK := Color(0.07, 0.025, 0.045)
const FLESH := Color(0.17, 0.045, 0.06)
const FLESH_HI := Color(0.28, 0.075, 0.09)
const UNDER := Color(0.56, 0.25, 0.24)
const TIP := Color(0.27, 0.075, 0.17)
const SUCKER := Color(1.0, 0.40, 0.09)      ## glow (the gate's LAVA)
const SUCKER_HOT := Color(1.0, 0.70, 0.22)
const OBSIDIAN := Color(0.15, 0.105, 0.19)  ## the gate's shard stone
const OBSIDIAN_LIGHT := Color(0.27, 0.19, 0.33)
## A brighter amber rim than the heroes' (0.30): dark red flesh in a red-carpeted room still has an edge.
const RIM := 0.62
## The beat's swell, x the tube radius (BeastLimbs.ENV_K allows for it).
const SWELL := 0.08
## Seconds a limb takes to withdraw (RETRACT) or to snap, lash and drop (WHIP).
const RETRACT_TIME := 1.8
## A ring of the tube on every this-many skeleton points.
const RING_EVERY := 2
const WHIP_TIME := 0.7

const SKEL_GLSL := """
uniform float t = 0.0;
uniform float sway_rate = 0.45;      // rad/s of the tip sway
uniform float wave_k = 0.35;         // how much the sway lags along the tube (per world unit)
uniform float sink = 0.0;            // still pieces: slide down into the dark
uniform float beat_rate = 2.6;       // the gate core's beat
uniform float pulse_amp = 0.7;       // how much the glow swells on the travelling beat
uniform float pulse_k = 0.9;         // phase lag of the beat per world unit along the tube
uniform float pulse_base = 1.0;      // the glow between beats
uniform float swell_amp = 0.08;      // how much the beat bulges the tube (x its radius)
uniform float fade_lo = -5.2;        // world y: flesh this deep is lost in the dark
uniform float fade_hi = -1.9;        // world y: flesh this high is fully lit
uniform bool skeletal = false;
uniform sampler2D skel : filter_nearest, repeat_disable;
uniform float step_len = 0.3;
uniform int exit_mode = 0;           // 0 retract along the path, 1 whip away
uniform float exit_t = -1.0;         // seconds since the gate closed (< 0: staying)
uniform float exit_len = 1.8;        // RETRACT: seconds a limb takes to withdraw
uniform float delay_k = 1.0;         // each limb's exit delay is scaled by this (the whip staggers faster)
uniform float hurt = 0.0;            // the gate was hit: flail (x each limb's weight, clamped to 1)
uniform float jerk = 0.0;            // the gate was hit: flinch back along the path (decays fast)
uniform float writhe = 0.0;          // 0..1: the gate's HP is low, the tips never settle
uniform float flail_max = 0.35;      // world units: the flail at a tip (BeastLimbs.FLAIL_MAX)
uniform float flail_k = 0.5;         // the flail's phase lag per world unit along the limb (BeastLimbs.FLAIL_K)
uniform float sway_writhe = 1.6;     // the sway at full writhe (BeastLimbs.SWAY_WRITHE)
varying float v_fade;
varying float v_pulse;

vec4 sk(int row, float col) {
	int c0 = int(floor(col));
	float f = col - float(c0);
	return mix(texelFetch(skel, ivec2(c0, row), 0), texelFetch(skel, ivec2(c0 + 1, row), 0), f);
}

float exit_d(float L, float delay) {
	if (exit_t < 0.0) { return 0.0; }
	float x = exit_t - delay;
	if (x <= 0.0) { return 0.0; }
	if (exit_mode == 0) {
		float u = clamp(x / exit_len, 0.0, 1.0);
		return (L + 0.5) * u * u * (3.0 - 2.0 * u);
	}
	// WHIP: the whole limb snaps 2 units back down its path in 0.1 s, rebounds once, then drops away fast (motion along
	// its own path: violent, and still clear of everything)
	float snap = 2.0 * (1.0 - pow(1.0 - clamp(x / 0.1, 0.0, 1.0), 3.0));
	float rebound = 0.8 * sin(clamp((x - 0.1) / 0.22, 0.0, 1.0) * PI);
	float drop = clamp((x - 0.32) / 0.35, 0.0, 1.0);
	return snap - rebound + (L + 0.5) * drop * drop;
}

float lash_k(float delay) {
	if (exit_mode != 1 || exit_t < 0.0) { return 0.0; }
	float x = exit_t - delay;
	return sin(clamp(x / 0.32, 0.0, 1.0) * PI);
}

// A vertex of limb uv.y at uv.x along it, offset `lo` and normal `ln` in its ring frame: where the shader puts it now.
void skel_vertex(vec2 uv, vec2 uv2, vec3 lo, vec3 ln, out vec3 pos, out vec3 wn) {
	int k = int(uv.y + 0.5);
	vec4 p0 = texelFetch(skel, ivec2(0, 4 * k + 3), 0);   // length, delay, phase, flail weight
	vec4 p1 = texelFetch(skel, ivec2(1, 4 * k + 3), 0);   // grip end, sway, last column
	float L = p0.x;
	float d = exit_d(L, p0.y * delay_k) + jerk * p0.w * 1.2;
	float sp = clamp(uv.x - d, 0.0, L);
	float col = min(sp / step_len, p1.z - 0.001);
	vec3 C = sk(4 * k, col).xyz;
	vec3 X = normalize(sk(4 * k + 1, col).xyz);
	vec3 Y = normalize(sk(4 * k + 2, col).xyz);
	vec3 T = cross(X, Y);
	pos = C + X * lo.x + Y * lo.y + T * lo.z;
	wn = normalize(X * ln.x + Y * ln.y + T * ln.z);
	float b = 0.5 + 0.5 * sin(t * beat_rate - uv.x * pulse_k);
	pos += wn * uv2.y * swell_amp * b * b * b;
	float wf = smoothstep(p1.x, L, sp);
	vec3 side = texelFetch(skel, ivec2(2, 4 * k + 3), 0).xyz;   // the limb's one sway axis
	float amp = p1.y * (1.0 + (sway_writhe - 1.0) * writhe);
	float ang = t * sway_rate * (1.0 + 1.5 * writhe) + p0.z - sp * wave_k;
	float fl = clamp(hurt * p0.w + lash_k(p0.y * delay_k), 0.0, 1.0) * flail_max;
	float fang = t * 13.0 + p0.z * 3.0 - sp * flail_k;
	vec3 off = side * (amp * sin(ang) + fl * sin(fang)) + vec3(0.0, 0.6, 0.0) * (amp * cos(ang * 0.83 + 0.7) + fl * cos(fang * 0.77));
	pos += off * wf;
}
"""

static var _flesh_shader: Shader
static var _outline_shader: Shader


## The flesh material (its next_pass is the moving outline). Set uniforms on both with set_both().
static func make(outline_px: float = 2.4) -> ShaderMaterial:
	if _flesh_shader == null:
		_flesh_shader = Shader.new()
		_flesh_shader.code = flesh_code()
		_outline_shader = Shader.new()
		_outline_shader.code = outline_code()
	var m := ShaderMaterial.new()
	m.shader = _flesh_shader
	m.set_shader_parameter("glow_gain", 1.9)
	m.set_shader_parameter("amber_rim", RIM)
	if outline_px > 0.0:
		var o := ShaderMaterial.new()
		o.shader = _outline_shader
		o.set_shader_parameter("outline_color", LowPolyMaterial.INK)
		o.set_shader_parameter("width_px", outline_px)
		m.next_pass = o
	set_both(m, "swell_amp", SWELL)
	set_both(m, "flail_max", BeastLimbs.FLAIL_MAX)
	set_both(m, "flail_k", BeastLimbs.FLAIL_K)
	set_both(m, "wave_k", BeastLimbs.WAVE_K)
	set_both(m, "sway_writhe", BeastLimbs.SWAY_WRITHE)
	set_both(m, "step_len", BeastLimbs.STEP)
	set_both(m, "exit_len", RETRACT_TIME)
	return m


## Set a uniform on the flesh and its outline pass.
static func set_both(m: ShaderMaterial, key: StringName, value: Variant) -> void:
	m.set_shader_parameter(key, value)
	if m.next_pass != null:
		(m.next_pass as ShaderMaterial).set_shader_parameter(key, value)


static func flesh_code() -> String:
	var code: String = LowPolyMaterial.SHADER.replace("\r", "")
	code = _patch(code, "varying vec3 wnormal;",
			"uniform vec4 tint_color : source_color = vec4(1.0, 0.25, 0.0, 1.0);\n"
			+ "uniform float tint_k = 0.0;\n"
			+ "uniform float glow_gain = 1.9;      // emissive faces (vertex alpha < 0.75)\n"
			+ "varying vec3 wnormal;\n" + SKEL_GLSL)
	code = _patch(code, "\twnormal = normalize((MODEL_NORMAL_MATRIX * NORMAL));",
			"\tif (skeletal) {\n"
			+ "\t\tvec3 sp_pos;\n"
			+ "\t\tvec3 sp_n;\n"
			+ "\t\tskel_vertex(UV, UV2, CUSTOM1.xyz, CUSTOM0.rgb * 2.0 - 1.0, sp_pos, sp_n);\n"
			+ "\t\tVERTEX = sp_pos;\n"
			+ "\t\tNORMAL = sp_n;\n"
			+ "\t} else {\n"
			+ "\t\tVERTEX.y -= sink * 4.0;\n"
			+ "\t}\n"
			+ "\twnormal = normalize((MODEL_NORMAL_MATRIX * NORMAL));\n"
			+ "\tfloat wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;\n"
			+ "\tv_fade = mix(0.05, 1.0, smoothstep(fade_lo, fade_hi, wy));\n"
			+ "\tfloat w = 0.5 + 0.5 * sin(t * beat_rate - UV.x * pulse_k);\n"
			+ "\tv_pulse = pulse_base + pulse_amp * (w * w * w * 1.6 - 0.25);")
	code = _patch(code, "void fragment() {\n\tvec3 c = COLOR.rgb;",
			"void fragment() {\n"
			+ "\tvec3 fn = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));\n"
			+ "\tif (dot(fn, VIEW) < 0.0) { fn = -fn; }\n"
			+ "\tNORMAL = fn;\n"
			+ "\tvec3 bwn = (INV_VIEW_MATRIX * vec4(fn, 0.0)).xyz;\n"
			+ "\tvec3 c = COLOR.rgb * v_fade;")
	code = _patch(code, "-wnormal.y", "-bwn.y")
	code = _patch(code, "EMISSION = min(e, vec3(0.95))",
			"float glow_m = 1.0 - step(0.75, COLOR.a);\n"
			+ "\tEMISSION = min(e, vec3(0.95)) * (1.0 - glow_m) + c * glow_m * glow_gain * v_pulse + tint_color.rgb * tint_k * 0.8")
	return code


static func outline_code() -> String:
	var code: String = LowPolyMaterial.OUTLINE_SHADER.replace("\r", "")
	code = _patch(code, "uniform float z_push = 0.04;", "uniform float z_push = 0.04;\n" + SKEL_GLSL)
	code = _patch(code, "\tvec3 sn = CUSTOM0.rgb * 2.0 - 1.0;",
			"\tvec3 sn = CUSTOM0.rgb * 2.0 - 1.0;\n"
			+ "\tif (skeletal) {\n"
			+ "\t\tvec3 sp_pos;\n"
			+ "\t\tvec3 sp_n;\n"
			+ "\t\tskel_vertex(UV, UV2, CUSTOM1.xyz, sn, sp_pos, sp_n);\n"
			+ "\t\tVERTEX = sp_pos;\n"
			+ "\t\tsn = sp_n;\n"
			+ "\t} else {\n"
			+ "\t\tVERTEX.y -= sink * 4.0;\n"
			+ "\t}")
	return code


static func _patch(code: String, find: String, repl: String) -> String:
	assert(code.contains(find), "BeastFlesh: shader patch target missing: " + find)
	return code.replace(find, repl)


# ------------------------------------------------------------------ the skeleton texture

## One texture for every limb of a beast: limb k is rows 4k (points), 4k+1 (frame x), 4k+2 (frame y) and 4k+3 (its
## numbers: col 0 = length, exit delay, phase, flail weight; col 1 = grip end, sway, last column; col 2 = the sway axis).
## `info` per limb:
## {delay, phase, weight}.
static func skeleton(paths: Array, info: Array[Dictionary]) -> ImageTexture:
	var w := 3
	for p: BeastLimbs.Path in paths:
		w = maxi(w, p.size() + 1)
	var img := Image.create(w, maxi(paths.size(), 1) * 4, false, Image.FORMAT_RGBAF)
	for k in paths.size():
		var p: BeastLimbs.Path = paths[k]
		var n := p.size()
		for c in w:
			var i := mini(c, n - 1)
			img.set_pixel(c, 4 * k, Color(p.pts[i].x, p.pts[i].y, p.pts[i].z, 1.0))
			img.set_pixel(c, 4 * k + 1, Color(p.xs[i].x, p.xs[i].y, p.xs[i].z, 0.0))
			img.set_pixel(c, 4 * k + 2, Color(p.ys[i].x, p.ys[i].y, p.ys[i].z, 0.0))
		var inf: Dictionary = info[k]
		img.set_pixel(0, 4 * k + 3, Color(p.length(), float(inf["delay"]), float(inf["phase"]), float(inf["weight"])))
		img.set_pixel(1, 4 * k + 3, Color(p.grip_end, p.sway_amp, float(n - 1), 0.0))
		img.set_pixel(2, 4 * k + 3, Color(p.side.x, p.side.y, p.side.z, 0.0))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ still pieces

## A triangle bag like LowPoly.Soup, but wound explicitly (outward from a given inside point) and turned into a mesh
## the flesh material reads with `skeletal` off (CUSTOM0 = the welded normal for the outline).
class Limb extends RefCounted:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var rng := RandomNumberGenerator.new()
	var vary := 0.08

	func _init(seed_value: int) -> void:
		rng.seed = seed_value

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, inside: Vector3) -> void:
		var n := (b - a).cross(c - a)
		if n.dot((a + b + c) / 3.0 - inside) < 0.0:
			var tmp := b
			b = c
			c = tmp
		verts.append(a)
		verts.append(b)
		verts.append(c)
		cols.append(BeastFlesh._paint(rng, col, vary))

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, inside: Vector3) -> void:
		tri(a, b, c, col, inside)
		tri(a, c, d, col, inside)

	## Append a LowPoly soup (already wound outward and painted) through xf.
	func merge(s: LowPoly.Soup, xf: Transform3D) -> void:
		for p in s.verts:
			verts.append(xf * p)
		cols.append_array(s.cols)

	func tri_count() -> int:
		return cols.size()

	func to_mesh(top_light: float = 0.22) -> ArrayMesh:
		var weld := {}
		var face_n := PackedVector3Array()
		for t in range(0, verts.size(), 3):
			var fn := (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t])
			face_n.append(fn)
			for k in 3:
				var wk := LowPoly.key(verts[t + k])
				weld[wk] = (weld[wk] if weld.has(wk) else Vector3.ZERO) + fn
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA8_UNORM)
		for t in range(0, verts.size(), 3):
			var fn: Vector3 = face_n[t / 3]
			if fn.length() < 0.0000001:
				continue
			var n := fn.normalized()
			var col := cols[t / 3]
			var lit := 1.0 + top_light * clampf(n.y, -1.0, 1.0)
			var base := Color(col.r * lit, col.g * lit, col.b * lit, 1.0).srgb_to_linear()
			base.a = col.a
			for k in [0, 2, 1]:
				var v := verts[t + k]
				var w: Vector3 = weld[LowPoly.key(v)]
				w = w.normalized() if w.length() > 0.00001 else n
				st.set_color(base)
				st.set_normal(n)
				st.set_custom(0, Color(w.x * 0.5 + 0.5, w.y * 0.5 + 0.5, w.z * 0.5 + 0.5, 1.0))
				st.add_vertex(v)
		return st.commit()


# ------------------------------------------------------------------ skeletal tubes

## Vertex streams for path_tube.
class _Streams extends RefCounted:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var limb := 0.0

	## World position p, world normal wn, at path point i of `path` (its frame and s).
	func emit(path: BeastLimbs.Path, i: int, p: Vector3, wn: Vector3, col: Color) -> void:
		var x := path.xs[i]
		var y := path.ys[i]
		var t := path.ts[i]
		var o := p - path.pts[i]
		verts.append(p)
		norms.append(wn)
		colors.append(col)
		uvs.append(Vector2(float(i) * BeastLimbs.STEP, limb))
		uv2s.append(Vector2(0.0, path.radii[i]))
		c0.append(wn.dot(x) * 0.5 + 0.5)
		c0.append(wn.dot(y) * 0.5 + 0.5)
		c0.append(wn.dot(t) * 0.5 + 0.5)
		c0.append(1.0)
		c1.append(o.dot(x))
		c1.append(o.dot(y))
		c1.append(o.dot(t))
		c1.append(0.0)


## The tube of limb `limb_index` along `path` (world space; the mesh sits at the origin): rings of `sides` on the path's
## own frames, a pointed tip, suckers every `sucker_gap` (a third glowing, all within the envelope's ENV_K) and the
## path's obsidian spines. Colours run from the dark root through the flesh to the tip; the underside is pale.
static func path_tube(path: BeastLimbs.Path, limb_index: int, seed_value: int, sides: int = 7, sucker_gap: float = 0.55) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := path.size()
	var out := _Streams.new()
	out.limb = float(limb_index)
	var total := path.length()
	# rings on every RING_EVERY-th skeleton point (and the last): each ring sits exactly on its point's frame
	var at_pts: Array[int] = []
	for i in range(0, n, RING_EVERY):
		at_pts.append(i)
	if at_pts[at_pts.size() - 1] != n - 1:
		at_pts.append(n - 1)
	var ring := PackedVector3Array()
	for ri in at_pts.size():
		var i := at_pts[ri]
		for k in sides:
			var a := TAU * float(k) / sides + 0.35 * ri
			var r := path.radii[i] * (1.0 + rng.randf_range(-0.07, 0.07))
			ring.append(path.xs[i] * (cos(a) * r) + path.ys[i] * (sin(a) * r))
	for ri in at_pts.size() - 1:
		var i := at_pts[ri]
		var i1 := at_pts[ri + 1]
		var u := float(i) * BeastLimbs.STEP / maxf(total, 0.01)
		var base_col := FLESH_DARK.lerp(FLESH, smoothstep(0.0, 0.25, u)).lerp(FLESH_HI, 0.5 * smoothstep(0.3, 0.8, u)).lerp(TIP, smoothstep(0.85, 1.0, u))
		for k in sides:
			var k1 := (k + 1) % sides
			var o00 := ring[ri * sides + k]
			var o01 := ring[ri * sides + k1]
			var o11 := ring[(ri + 1) * sides + k1]
			var o10 := ring[(ri + 1) * sides + k]
			var a := path.pts[i] + o00
			var b := path.pts[i] + o01
			var c := path.pts[i1] + o11
			var d := path.pts[i1] + o10
			var mid_n := (o00 + o01).normalized()
			var col := base_col.lerp(UNDER, 0.55) if mid_n.y < -0.35 else base_col
			var lin := _paint(rng, col).srgb_to_linear()
			lin.a = 1.0
			# Godot's front faces are clockwise: (a, c, b), (a, d, c) when a, b, c, d run counter-clockwise outward, else
			# (c, a, b), (c, d, a)
			if (b - a).cross(d - a).dot(mid_n) >= 0.0:
				_tri(out, path, [i, i1, i], [a, c, b], [o00, o11, o01], lin)
				_tri(out, path, [i, i1, i1], [a, d, c], [o00, o10, o11], lin)
			else:
				_tri(out, path, [i1, i, i], [c, a, b], [o11, o00, o01], lin)
				_tri(out, path, [i1, i1, i], [c, d, a], [o11, o10, o00], lin)
	# the tip: a cone to a point
	var last := n - 1
	var last_ring := at_pts.size() - 1
	var apex := path.pts[last] + path.ts[last] * path.radii[last] * 2.5
	var tip_lin := _paint(rng, TIP).srgb_to_linear()
	for k in sides:
		var oa := ring[last_ring * sides + k]
		var ob := ring[last_ring * sides + (k + 1) % sides]
		var a := path.pts[last] + oa
		var b := path.pts[last] + ob
		var tri := PackedVector3Array([a, apex, b])
		if (b - a).cross(apex - a).dot(oa + ob) <= 0.0:
			tri = PackedVector3Array([a, b, apex])
		for v in tri:
			out.emit(path, last, v, (v - path.pts[last]).normalized(), tip_lin)
	# suckers along the top (within the envelope: their outer side at radius x 1.1)
	if sucker_gap > 0.0:
		var at := total * 0.12
		while at < total * 0.97:
			var i := clampi(roundi(at / BeastLimbs.STEP), 0, last)
			var r := path.radii[i]
			if path.pts[i].y < HexMapView.FLOOR_DEPTH * Hex.LEVEL_HEIGHT - r:
				at += sucker_gap   # (under the slab: nobody sees it)
				continue
			var up := path.ys[i] if path.ys[i].y >= 0.0 else -path.ys[i]
			var side := path.xs[i] if path.xs[i].y >= 0.0 else -path.xs[i]
			var off := (up * 0.75 + side * (0.5 if rng.randf() < 0.5 else -0.5)).normalized()
			var rad := maxf(r * 0.28, 0.04)
			var roll := rng.randf()
			# a third of the suckers glow (the beat runs through them); the rest are pale, matte rings
			var kind := (2 if roll < 0.1 else 1) if roll < 0.34 else 0
			var soup := _stud_soup(kind, int(rng.randi() % 3))
			var basis := Basis(Quaternion(Vector3.UP, off)) * Basis.from_scale(Vector3(rad, rad * 0.7, rad))
			_stud(out, path, i, soup, Transform3D(basis, path.pts[i] + off * r * 0.82))
			at += sucker_gap * rng.randf_range(0.8, 1.25) * (0.7 if at > total * 0.6 else 1.0)
	# obsidian spines (BeastLimbs placed and checked them)
	for sp in path.spines:
		var i: int = sp["i"]
		var dir: Vector3 = sp["dir"]
		var h: float = sp["h"]
		var r := path.radii[i]
		var soup := _stud_soup(3 if rng.randf() < 0.5 else 4, int(rng.randi() % 3))
		var sr := float(sp["r"])
		var basis := Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(sr, h, sr))
		_stud(out, path, i, soup, Transform3D(basis, path.pts[i] + dir * (r * 0.8 + h * 0.5)))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = out.verts
	arr[Mesh.ARRAY_NORMAL] = out.norms
	arr[Mesh.ARRAY_COLOR] = out.colors
	arr[Mesh.ARRAY_TEX_UV] = out.uvs
	arr[Mesh.ARRAY_TEX_UV2] = out.uv2s
	arr[Mesh.ARRAY_CUSTOM0] = out.c0
	arr[Mesh.ARRAY_CUSTOM1] = out.c1
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	# (the motion stays inside the envelopes, and the exits slide back along the path, inside its own box)
	mesh.custom_aabb = mesh.get_aabb().grow(path.motion() + 0.5)
	return mesh


## Unit studs, built once: kind 0 a pale sucker, 1 a glowing one, 2 a hot one, 3 / 4 an obsidian spine (radius 1, height
## 1); three painted variants of each.
static var _studs := {}


static func _stud_soup(kind: int, variant: int) -> LowPoly.Soup:
	var key := kind * 10 + variant
	if _studs.has(key):
		return _studs[key]
	var soup: LowPoly.Soup
	match kind:
		0, 1, 2:
			var col := UNDER if kind == 0 else MonsterModel.glow(SUCKER if kind == 1 else SUCKER_HOT)
			soup = LowPoly.boulder(Vector3.ONE, 0, 0.08, col, 17 + key, 0.05)
		_:
			soup = LowPoly.cylinder(1.0, 0.08, 1.0, 4, OBSIDIAN if kind == 3 else OBSIDIAN_LIGHT, 29 + key, 0.02)
	_studs[key] = soup
	return soup


static func _tri(out: _Streams, path: BeastLimbs.Path, idx: Array, ps: Array, os: Array, lin: Color) -> void:
	for k in 3:
		out.emit(path, int(idx[k]), ps[k], (os[k] as Vector3).normalized(), lin)


static func _stud(out: _Streams, path: BeastLimbs.Path, i: int, soup: LowPoly.Soup, place: Transform3D) -> void:
	var center := place.origin
	for tri_i in soup.cols.size():
		var col := soup.cols[tri_i]
		var lin := col.srgb_to_linear()
		lin.a = col.a
		for kk in [0, 2, 1]:
			var v: Vector3 = place * soup.verts[tri_i * 3 + kk]
			out.emit(path, i, v, (v - center).normalized(), lin)


static func _paint(rng: RandomNumberGenerator, col: Color, vary: float = 0.08) -> Color:
	var h := col.h + rng.randf_range(-1.0, 1.0) * vary * 0.12
	var s := clampf(col.s * (1.0 + rng.randf_range(-1.0, 1.0) * vary * 1.6), 0.0, 1.0)
	var v := clampf(col.v * (1.0 + rng.randf_range(-1.0, 1.0) * vary), 0.0, 1.0)
	return Color.from_hsv(fposmod(h, 1.0), s, v, col.a)
