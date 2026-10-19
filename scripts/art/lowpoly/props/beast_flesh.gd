class_name BeastFlesh
extends RefCounted
## The flesh of the monster under a hellgate room (HellgateBeast): the ENEMY toon look (MonsterMaterial: ink outline,
## amber rim, faces painted with vertex alpha 0.5 glow) plus three things the GPU does, so a limb costs one mesh and no
## CPU work a frame:
##
##   - BEND: a tentacle is built straight up its local +Y (s = rest y, 0 at the base) and the vertex shader bends it
##     along a centreline whose heading at s is two angles: `a` (towards local +Z: the curl, the lean, the sway) and `b`
##     (towards local +X: the side sway). Per-limb numbers ride in the mesh (CUSTOM1 = length, phase, curl, sway;
##     UV = base lean, twitch), so every limb of a room shares ONE material pair (flesh + outline) and a frame costs
##     two uniform writes (`t`, `beat`). The outline pass bends the same way. Faces get a flat normal from screen
##     derivatives, so a bent limb stays faceted.
##   - FADE: flesh below `fade_hi` (world y) darkens towards the background by `fade_lo`: the limbs rise out of the dark
##     under the floor, their roots never show.
##   - PULSE: the glowing faces (suckers, veins) brighten in a wave that leaves the base on the gate's beat and runs up
##     the limb (`beat_rate` is the gate's: HellgateModel beats at 2.6 rad/s, the origin at 1.7).
## A mesh without CUSTOM1 / UV (any LowPoly soup) passes straight through: it only gets the fade and the pulse.
## Headless-safe: ordinary spatial shaders, no textures.

const FLESH_DARK := Color(0.07, 0.025, 0.045)
const FLESH := Color(0.17, 0.045, 0.06)
const FLESH_HI := Color(0.28, 0.075, 0.09)
const UNDER := Color(0.56, 0.25, 0.24)
const TIP := Color(0.27, 0.075, 0.17)
const SUCKER := Color(1.0, 0.40, 0.09)      ## glow (the gate's LAVA)
const SUCKER_HOT := Color(1.0, 0.70, 0.22)
const VEIN := Color(1.0, 0.22, 0.07)        ## glow (the gate's CRACK)
const OBSIDIAN := Color(0.15, 0.105, 0.19)  ## the gate's shard stone
const OBSIDIAN_LIGHT := Color(0.27, 0.19, 0.33)

const BEND_GLSL := """
uniform float t = 0.0;
uniform float sway_rate = 0.55;      // rad/s of the slow sway
uniform float wave_k = 0.6;          // how much the sway lags up the limb (per world unit)
uniform float twitch_rate = 7.0;
uniform float sink = 0.0;            // 0..1: the limb slides down out of sight by this fraction of its length
uniform float beat_rate = 2.6;       // the gate core's beat
uniform float pulse_amp = 0.7;       // how much the glow swells on the travelling beat
uniform float pulse_k = 0.9;         // phase lag of the beat per world unit up the limb
uniform float pulse_base = 1.0;      // the glow between beats
uniform float fade_lo = -3.6;        // world y: flesh this deep is lost in the dark
uniform float fade_hi = 0.4;         // world y: flesh this high is fully lit
uniform float wiggle = 0.0;          // a still S-curve along the limb (radians), so it reads as a tentacle, not a horn
uniform float wiggle_k = 6.0;
uniform bool path_mode = false;      // PATH tubes: built along their path, CUSTOM1 = sway (xyz) and radius (w), UV = (s, phase)
uniform float swell_amp = 0.14;      // PATH: the beat swells the tube as it travels along it (peristalsis)
varying float v_fade;
varying float v_pulse;

vec2 beast_ang(float s, vec4 P, vec2 Q) {
	float L = max(P.x, 0.01);
	float u = clamp(s / L, 0.0, 1.25);
	float ph = P.y;
	float a = Q.x * (1.0 - u) + P.z * u * u + P.w * u * sin(t * sway_rate + ph - s * wave_k);
	float b = P.w * 0.75 * u * sin(t * sway_rate * 0.71 + ph * 1.7 - s * wave_k * 0.8 + 1.3);
	a += wiggle * u * sin(u * wiggle_k + ph * 1.3);
	b += wiggle * 0.6 * u * sin(u * wiggle_k * 0.8 + ph * 2.1);
	float tw = Q.y * u * u * u * sin(t * twitch_rate + ph * 3.1) * max(0.0, sin(t * 0.9 + ph * 2.3));
	return vec2(a + tw, b + tw * 0.6);
}

vec3 beast_dir(vec2 ab) {
	return vec3(cos(ab.x) * sin(ab.y), cos(ab.x) * cos(ab.y), sin(ab.x));
}

// Rotate a rest-pose offset into the frame at heading ab: about X by a (Y towards Z), then about Z by -b (towards X).
vec3 beast_rot(vec3 v, vec2 ab) {
	float ca = cos(ab.x);
	float sa = sin(ab.x);
	v = vec3(v.x, v.y * ca - v.z * sa, v.y * sa + v.z * ca);
	float cb = cos(ab.y);
	float sb = sin(ab.y);
	return vec3(v.x * cb + v.y * sb, -v.x * sb + v.y * cb, v.z);
}

vec3 beast_center(float s, vec4 P, vec2 Q) {
	vec3 p = vec3(0.0);
	float ds = s / 10.0;
	for (int i = 0; i < 10; i++) {
		p += beast_dir(beast_ang((float(i) + 0.5) * ds, P, Q)) * ds;
	}
	return p;
}

// PATH tubes: the beat bulges the tube along its length; the sway (zero where it grips) moves the free end.
vec3 path_move(vec3 v, vec3 wn, vec2 uv, vec4 c1) {
	float s = uv.x;
	float w = 0.5 + 0.5 * sin(t * beat_rate - s * pulse_k);
	vec3 off = wn * c1.w * swell_amp * w * w * w;
	float ang = t * sway_rate + uv.y - s * wave_k;
	off += c1.xyz * sin(ang);
	off.y += length(c1.xyz) * 0.6 * cos(ang * 0.83 + 0.7);
	off.y -= sink * 4.0;
	return v + off;
}

vec3 beast_bend(vec3 v, vec4 P, vec2 Q) {
	float s = v.y;
	vec2 ab = beast_ang(s, P, Q);
	vec3 p = beast_center(s, P, Q) + beast_rot(vec3(v.x, 0.0, v.z), ab);
	p.y -= sink * (P.x + 1.0);
	return p;
}
"""

static var _flesh_shader: Shader
static var _outline_shader: Shader


## The flesh material (its next_pass is the bending outline). Set `t` / `beat` on both with set_time().
static func make(outline_px: float = 2.4, path: bool = false) -> ShaderMaterial:
	if _flesh_shader == null:
		_flesh_shader = Shader.new()
		_flesh_shader.code = flesh_code()
		_outline_shader = Shader.new()
		_outline_shader.code = outline_code()
	var m := ShaderMaterial.new()
	m.shader = _flesh_shader
	m.set_shader_parameter("glow_gain", 1.9)
	if outline_px > 0.0:
		var o := ShaderMaterial.new()
		o.shader = _outline_shader
		o.set_shader_parameter("outline_color", LowPolyMaterial.INK)
		o.set_shader_parameter("width_px", outline_px)
		m.next_pass = o
	set_both(m, "path_mode", path)
	return m


## Set a uniform on the flesh and its outline pass.
static func set_both(m: ShaderMaterial, key: StringName, value: Variant) -> void:
	m.set_shader_parameter(key, value)
	if m.next_pass != null:
		(m.next_pass as ShaderMaterial).set_shader_parameter(key, value)


static func flesh_code() -> String:
	# Built from the heroes' shader like MonsterMaterial's (its own glow patch no longer matches LowPolyMaterial's
	# EMISSION line, so it is done here against the line's stable prefix).
	var code: String = LowPolyMaterial.SHADER.replace("\r", "")
	code = _patch(code, "varying vec3 wnormal;",
			"uniform vec4 tint_color : source_color = vec4(1.0, 0.25, 0.0, 1.0);\n"
			+ "uniform float tint_k = 0.0;\n"
			+ "uniform float glow_gain = 1.9;      // emissive faces (vertex alpha < 0.75)\n"
			+ "varying vec3 wnormal;\n" + BEND_GLSL)
	code = _patch(code, "\twnormal = normalize((MODEL_NORMAL_MATRIX * NORMAL));",
			"\tvec4 P = CUSTOM1;\n"
			+ "\tvec2 Q = UV;\n"
			+ "\tfloat s0 = VERTEX.y;\n"
			+ "\tif (path_mode) {\n"
			+ "\t\ts0 = UV.x;\n"
			+ "\t\tVERTEX = path_move(VERTEX, normalize(CUSTOM0.rgb * 2.0 - 1.0), UV, P);\n"
			+ "\t} else {\n"
			+ "\t\tNORMAL = beast_rot(NORMAL, beast_ang(s0, P, Q));\n"
			+ "\t\tVERTEX = beast_bend(VERTEX, P, Q);\n"
			+ "\t}\n"
			+ "\twnormal = normalize((MODEL_NORMAL_MATRIX * NORMAL));\n"
			+ "\tfloat wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;\n"
			+ "\tv_fade = mix(0.05, 1.0, smoothstep(fade_lo, fade_hi, wy));\n"
			+ "\tfloat w = 0.5 + 0.5 * sin(t * beat_rate - max(s0, 0.0) * pulse_k);\n"
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
	code = _patch(code, "uniform float z_push = 0.04;", "uniform float z_push = 0.04;\n" + BEND_GLSL)
	code = _patch(code, "\tvec3 sn = CUSTOM0.rgb * 2.0 - 1.0;",
			"\tvec4 P = CUSTOM1;\n"
			+ "\tvec2 Q = UV;\n"
			+ "\tvec3 sn = CUSTOM0.rgb * 2.0 - 1.0;\n"
			+ "\tif (path_mode) {\n"
			+ "\t\tVERTEX = path_move(VERTEX, normalize(sn), UV, P);\n"
			+ "\t} else {\n"
			+ "\t\tsn = beast_rot(sn, beast_ang(VERTEX.y, P, Q));\n"
			+ "\t\tVERTEX = beast_bend(VERTEX, P, Q);\n"
			+ "\t}")
	return code


static func _patch(code: String, find: String, repl: String) -> String:
	assert(code.contains(find), "BeastFlesh: shader patch target missing: " + find)
	return code.replace(find, repl)


# ------------------------------------------------------------------ the centreline on the CPU (fitting a pose)

## The same centreline the shader draws, at time t, in the limb's local frame (for placing a limb so its apex and tip
## land where we want them). p = [length, phase, curl, sway], q = [lean, twitch].
static func center(s: float, p: Vector4, q: Vector2, t: float = 0.0, sway_rate: float = 0.55, wave_k: float = 0.6,
		wiggle: float = 0.0, wiggle_k: float = 6.0) -> Vector3:
	var out := Vector3.ZERO
	var ds := s / 10.0
	for i in 10:
		var ab := angles((float(i) + 0.5) * ds, p, q, t, sway_rate, wave_k, wiggle, wiggle_k)
		out += Vector3(cos(ab.x) * sin(ab.y), cos(ab.x) * cos(ab.y), sin(ab.x)) * ds
	return out


static func angles(s: float, p: Vector4, q: Vector2, t: float, sway_rate: float, wave_k: float, wiggle: float = 0.0,
		wiggle_k: float = 6.0) -> Vector2:
	var u := clampf(s / maxf(p.x, 0.01), 0.0, 1.25)
	var a := q.x * (1.0 - u) + p.z * u * u + p.w * u * sin(t * sway_rate + p.y - s * wave_k)
	var b := p.w * 0.75 * u * sin(t * sway_rate * 0.71 + p.y * 1.7 - s * wave_k * 0.8 + 1.3)
	a += wiggle * u * sin(u * wiggle_k + p.y * 1.3)
	b += wiggle * 0.6 * u * sin(u * wiggle_k * 0.8 + p.y * 2.1)
	return Vector2(a, b)


# ------------------------------------------------------------------ building a limb

## A triangle bag like LowPoly.Soup, but wound explicitly (outward from a given inside point: a long bent limb's faces
## are not outward from its origin) and turned into a mesh that also carries the limb's numbers (CUSTOM1, UV).
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
		cols.append(_paint(col))

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

	## A gnarled tube along `pts` (rings of `sides`, radius per point, colour per segment; no caps: its ends sink
	## into something). Cheaper and smoother than a chain of capped cylinders.
	func tube(pts: Array[Vector3], radii: Array[float], seg_cols: Array[Color], sides: int, gnarl: float = 0.12) -> void:
		var n := pts.size()
		if n < 2:
			return
		var rings: Array = []
		var ref := Vector3.UP
		for i in n:
			var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
			if absf(t.dot(ref)) > 0.95:
				ref = Vector3.RIGHT if absf(t.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
			var x := ref.cross(t).normalized()
			var y := t.cross(x).normalized()
			ref = y
			var row: Array[Vector3] = []
			for k in sides:
				var a := TAU * float(k) / sides + 0.4 * i
				var r := radii[i] * (1.0 + rng.randf_range(-gnarl, gnarl))
				row.append(pts[i] + (x * cos(a) + y * sin(a)) * r)
			rings.append(row)
		for i in n - 1:
			var r0: Array[Vector3] = rings[i]
			var r1: Array[Vector3] = rings[i + 1]
			var mid := (pts[i] + pts[i + 1]) * 0.5
			var col: Color = seg_cols[mini(i, seg_cols.size() - 1)]
			for k in sides:
				var k1 := (k + 1) % sides
				quad(r0[k], r0[k1], r1[k1], r1[k], col, mid)

	func _paint(col: Color) -> Color:
		var h := col.h + rng.randf_range(-1.0, 1.0) * vary * 0.12
		var s := clampf(col.s * (1.0 + rng.randf_range(-1.0, 1.0) * vary * 1.6), 0.0, 1.0)
		var v := clampf(col.v * (1.0 + rng.randf_range(-1.0, 1.0) * vary), 0.0, 1.0)
		return Color.from_hsv(fposmod(h, 1.0), s, v, col.a)

	## p = [length, phase, curl, sway] (CUSTOM1), q = [lean, twitch] (UV). reach: how far the bend can carry a vertex
	## from the rest pose (the cull box grows by it).
	func to_mesh(p: Vector4, q: Vector2, reach: float, top_light: float = 0.22) -> ArrayMesh:
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
		st.set_custom_format(1, SurfaceTool.CUSTOM_RGBA_FLOAT)
		var custom1 := Color(p.x, p.y, p.z, p.w)
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
				st.set_uv(q)
				st.set_custom(0, Color(w.x * 0.5 + 0.5, w.y * 0.5 + 0.5, w.z * 0.5 + 0.5, 1.0))
				st.set_custom(1, custom1)
				st.add_vertex(v)
		var mesh := st.commit()
		var aabb := mesh.get_aabb().grow(reach)
		mesh.custom_aabb = aabb
		return mesh


## A tentacle, straight up +Y in its rest pose: `rings` faceted rings (closer towards the tip), radius r_base -> r_tip,
## a pointed tip. The +Z side (the inside of a curl) is the pale underside with a row of glowing suckers; the -Z side
## (the back) can carry obsidian spines like the gate's shards. Colours run from the dark root to the flesh.
## opts: suckers (int), spines (int), sides (int), under (bool), tip_col (Color)
static func tentacle(length: float, r_base: float, r_tip: float, rings: int, seed_value: int, opts: Dictionary = {}) -> Limb:
	var lb := Limb.new(seed_value)
	var sides: int = int(opts.get("sides", 6))
	var twist := 0.18
	var ss: Array[float] = []
	var rs: Array[float] = []
	for i in rings + 1:
		var u := float(i) / rings
		ss.append(length * (1.0 - pow(1.0 - u, 1.35)))
		rs.append(lerpf(r_base, r_tip, pow(u, 0.85)) * (1.0 + lb.rng.randf_range(-0.07, 0.07) * (1.0 if i > 0 and i < rings else 0.0)))
	var tip_col: Color = opts.get("tip_col", TIP)
	var under: bool = bool(opts.get("under", true))
	var ring_pts: Array = []
	for i in rings + 1:
		var row: Array[Vector3] = []
		for k in sides:
			var th := TAU * float(k) / sides + twist * i
			row.append(Vector3(cos(th) * rs[i], ss[i], sin(th) * rs[i]))
		ring_pts.append(row)
	for i in rings:
		var u := (float(i) + 0.5) / rings
		var col := FLESH_DARK.lerp(FLESH, smoothstep(0.0, 0.35, u)).lerp(FLESH_HI, smoothstep(0.35, 0.7, u) * 0.7).lerp(tip_col, smoothstep(0.7, 1.0, u))
		var r0: Array[Vector3] = ring_pts[i]
		var r1: Array[Vector3] = ring_pts[i + 1]
		var axis := Vector3(0.0, (ss[i] + ss[i + 1]) * 0.5, 0.0)
		for k in sides:
			var k1 := (k + 1) % sides
			var mid := (r0[k] + r0[k1]) * 0.5
			var c := col
			if under and mid.z > rs[i] * 0.45:
				c = col.lerp(UNDER, 0.65 * smoothstep(0.15, 0.4, u))
			lb.quad(r0[k], r0[k1], r1[k1], r1[k], c, axis)
	# the tip: a short cone to a point
	var last: Array[Vector3] = ring_pts[rings]
	var apex := Vector3(0.0, length + r_tip * 2.6, 0.0)
	for k in sides:
		lb.tri(last[k], last[(k + 1) % sides], apex, tip_col, Vector3(0.0, length, 0.0))
	# suckers: glowing studs in a double row up the underside
	var n_suck: int = int(opts.get("suckers", 0))
	for i in n_suck:
		var u := lerpf(0.32, 0.93, (float(i) + 0.5) / n_suck)
		var s := length * u
		var r := lerpf(r_base, r_tip, pow(u, 0.85))
		var side := 0.42 if i % 2 == 0 else -0.42
		var pos := Vector3(side * r, s, r * 0.93)
		var rad := maxf(r * 0.4, 0.035)
		var hot := SUCKER_HOT if i % 3 == 0 else SUCKER
		var b := LowPoly.boulder(Vector3(rad, rad * 0.8, rad * 0.55), 0, 0.1, MonsterModel.glow(hot), seed_value * 31 + i, 0.05)
		lb.merge(b, Transform3D(Basis(), pos))
	# obsidian spines down the back (the gate's shards growing out of the limb)
	var n_spine: int = int(opts.get("spines", 0))
	for i in n_spine:
		var u := lerpf(0.22, 0.7, (float(i) + 0.5) / n_spine)
		var s := length * u
		var r := lerpf(r_base, r_tip, pow(u, 0.85))
		var h := r * lb.rng.randf_range(1.4, 2.1)
		var w := r * 0.42
		var sp := LowPoly.cylinder(w, w * 0.06, h, 4, OBSIDIAN if i % 2 == 0 else OBSIDIAN_LIGHT, seed_value * 17 + i, 0.03)
		# lean the spine back (-Z) and a little up the limb
		var xf := Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-68.0)), Vector3(0.0, s + h * 0.18, -r * 0.55 - h * 0.44))
		lb.merge(sp, xf)
	return lb


# ------------------------------------------------------------------ PATH tubes

## A long tube along `pts` (world space; the mesh sits at the origin) for the PATH material: rings of `sides`,
## radius per point, sway amplitude per point (0 where it grips, up to ~0.4 at a free tip). Colours run from the dark
## root through the flesh to the tip; the side facing down is the pale underside. Glowing studs (suckers) every
## `sucker_gap` along the top, obsidian spines along the back every `spine_gap` (0 = none) of the gripping stretch.
static func path_tube(pts: Array[Vector3], radii: Array[float], sway: Array[float], seed_value: int, sides: int = 7,
		sucker_gap: float = 0.55, spine_gap: float = 0.0, phase: float = 0.0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := pts.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var c0 := PackedFloat32Array()      # RGBA float: weld normal * 0.5 + 0.5 (read as CUSTOM0)
	var c1 := PackedFloat32Array()      # RGBA float: sway direction * amplitude, radius
	var s_at: Array[float] = [0.0]
	for i in range(1, n):
		s_at.append(s_at[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total := s_at[n - 1]
	# ring frames (parallel transport)
	var xs: Array[Vector3] = []
	var ys: Array[Vector3] = []
	var ts: Array[Vector3] = []
	var ref := Vector3.UP
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		if absf(t.dot(ref)) > 0.97:
			ref = Vector3.RIGHT if absf(t.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		var x := ref.cross(t).normalized()
		var y := t.cross(x).normalized()
		ref = y
		xs.append(x)
		ys.append(y)
		ts.append(t)
	var rings: Array = []
	for i in n:
		var row: Array[Vector3] = []
		for k in sides:
			var a := TAU * float(k) / sides + 0.35 * i
			var r := radii[i] * (1.0 + rng.randf_range(-0.07, 0.07))
			row.append(xs[i] * cos(a) * r + ys[i] * sin(a) * r)
		rings.append(row)
	var sway_dir := func(i: int) -> Vector3:
		var side := Vector3(-ts[i].z, 0.0, ts[i].x)
		side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
		return side * sway[i]
	var emit := func(p: Vector3, wn: Vector3, col: Color, i: int) -> void:
		verts.append(p)
		norms.append(wn)
		colors.append(col)
		uvs.append(Vector2(s_at[i], phase))
		c0.append_array([wn.x * 0.5 + 0.5, wn.y * 0.5 + 0.5, wn.z * 0.5 + 0.5, 1.0])
		var sd: Vector3 = sway_dir.call(i)
		c1.append_array([sd.x, sd.y, sd.z, radii[i]])
	for i in n - 1:
		var u := s_at[i] / maxf(total, 0.01)
		var base_col := FLESH_DARK.lerp(FLESH, smoothstep(0.0, 0.25, u)).lerp(FLESH_HI, 0.5 * smoothstep(0.3, 0.8, u)).lerp(TIP, smoothstep(0.85, 1.0, u))
		var r0: Array[Vector3] = rings[i]
		var r1: Array[Vector3] = rings[i + 1]
		for k in sides:
			var k1 := (k + 1) % sides
			var a := pts[i] + r0[k]
			var b := pts[i] + r0[k1]
			var c := pts[i + 1] + r1[k1]
			var d := pts[i + 1] + r1[k]
			var mid_n := (r0[k] + r0[k1]).normalized()
			var col := base_col
			if mid_n.y < -0.35:
				col = base_col.lerp(UNDER, 0.55)
			col = _paint(rng, col)
			var lin := col.srgb_to_linear()
			lin.a = 1.0
			# outward winding: (b - a) x (d - a) points out for this ring order; emit clockwise for Godot
			var fn := (b - a).cross(d - a)
			var flip := fn.dot(mid_n) < 0.0
			var quad: Array = [[a, r0[k], i], [b, r0[k1], i], [c, r1[k1], i + 1], [d, r1[k], i + 1]]
			var order: Array = [0, 2, 1, 0, 3, 2] if not flip else [0, 1, 2, 0, 2, 3]
			for o: int in order:
				var e: Array = quad[o]
				emit.call(e[0], (e[1] as Vector3).normalized(), lin, e[2])
	# a closed tip cone
	var last: Array[Vector3] = rings[n - 1]
	var apex := pts[n - 1] + ts[n - 1] * radii[n - 1] * 2.5
	var tip_lin := _paint(rng, TIP).srgb_to_linear()
	for k in sides:
		var a := pts[n - 1] + last[k]
		var b := pts[n - 1] + last[(k + 1) % sides]
		var fn := (b - a).cross(apex - a)
		var out := (last[k] + last[(k + 1) % sides]).normalized()
		var tri: Array = [a, apex, b] if fn.dot(out) > 0.0 else [a, b, apex]
		for v: Vector3 in tri:
			emit.call(v, (v - pts[n - 1]).normalized(), tip_lin, n - 1)
	# studs and spines, placed by arc length
	var studs: Array = []
	if sucker_gap > 0.0:
		var sg := sucker_gap
		var at := total * 0.12
		while at < total * 0.97:
			studs.append([at, true])
			at += sg * rng.randf_range(0.8, 1.25) * (0.7 if at > total * 0.6 else 1.0)
	if spine_gap > 0.0:
		var at := total * 0.15
		while at < total * 0.62:
			studs.append([at, false])
			at += spine_gap * rng.randf_range(0.8, 1.2)
	for st: Array in studs:
		var sa: float = st[0]
		var i := 0
		while i < n - 2 and s_at[i + 1] < sa:
			i += 1
		var f := clampf((sa - s_at[i]) / maxf(s_at[i + 1] - s_at[i], 0.001), 0.0, 1.0)
		var center := pts[i].lerp(pts[i + 1], f)
		var r := lerpf(radii[i], radii[i + 1], f)
		var up := ys[i]
		if up.y < 0.0:
			up = -up
		var side := xs[i] if xs[i].y >= 0.0 else -xs[i]
		var soup: LowPoly.Soup
		var place: Transform3D
		if bool(st[1]):
			var off := (up * 0.75 + side * (0.5 if rng.randf() < 0.5 else -0.5)).normalized()
			var rad := maxf(r * 0.3, 0.05)
			var roll := rng.randf()
			# a third of the suckers glow (the beat runs through them); the rest are pale, matte rings
			var col := MonsterModel.glow(SUCKER_HOT if roll < 0.1 else SUCKER) if roll < 0.34 else UNDER
			soup = LowPoly.boulder(Vector3(rad, rad * 0.7, rad), 0, 0.08, col, rng.randi(), 0.05)
			place = Transform3D(Basis(Quaternion(Vector3.UP, off)), center + off * r * 0.92)
		else:
			var h := r * rng.randf_range(1.1, 1.7)
			soup = LowPoly.cylinder(r * 0.36, r * 0.03, h, 4, OBSIDIAN if rng.randf() < 0.5 else OBSIDIAN_LIGHT, rng.randi(), 0.02)
			var dir := (up - ts[i] * 0.55).normalized()
			place = Transform3D(Basis(Quaternion(Vector3.UP, dir)), center + up * r * 0.8 + dir * h * 0.45)
		for tri_i in soup.cols.size():
			var col := soup.cols[tri_i]
			var lin := col.srgb_to_linear()
			lin.a = col.a
			for kk in [0, 2, 1]:
				var v: Vector3 = place * soup.verts[tri_i * 3 + kk]
				emit.call(v, (v - center).normalized(), lin, i)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_CUSTOM0] = c0
	arr[Mesh.ARRAY_CUSTOM1] = c1
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	var max_sway := 0.0
	for sw in sway:
		max_sway = maxf(max_sway, sw)
	mesh.custom_aabb = mesh.get_aabb().grow(max_sway * 1.7 + 0.5)
	return mesh


static func _paint(rng: RandomNumberGenerator, col: Color, vary: float = 0.08) -> Color:
	var h := col.h + rng.randf_range(-1.0, 1.0) * vary * 0.12
	var s := clampf(col.s * (1.0 + rng.randf_range(-1.0, 1.0) * vary * 1.6), 0.0, 1.0)
	var v := clampf(col.v * (1.0 + rng.randf_range(-1.0, 1.0) * vary), 0.0, 1.0)
	return Color.from_hsv(fposmod(h, 1.0), s, v, col.a)


## Catmull-Rom through `ctrl`, resampled to points about `step` apart (with their radius and sway interpolated).
static func smooth_path(ctrl: Array[Vector3], rad: Array[float], sw: Array[float], step: float) -> Array:
	var dense: Array[Vector3] = []
	var dr: Array[float] = []
	var ds: Array[float] = []
	var n := ctrl.size()
	for i in n - 1:
		var p0 := ctrl[maxi(i - 1, 0)]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[mini(i + 2, n - 1)]
		for j in 8:
			var u := float(j) / 8.0
			var u2 := u * u
			var u3 := u2 * u
			dense.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3))
			dr.append(lerpf(rad[i], rad[i + 1], u))
			ds.append(lerpf(sw[i], sw[i + 1], u))
	dense.append(ctrl[n - 1])
	dr.append(rad[n - 1])
	ds.append(sw[n - 1])
	var out_p: Array[Vector3] = [dense[0]]
	var out_r: Array[float] = [dr[0]]
	var out_s: Array[float] = [ds[0]]
	var acc := 0.0
	for i in range(1, dense.size()):
		acc += dense[i].distance_to(dense[i - 1])
		if acc >= step or i == dense.size() - 1:
			out_p.append(dense[i])
			out_r.append(dr[i])
			out_s.append(ds[i])
			acc = 0.0
	return [out_p, out_r, out_s]
