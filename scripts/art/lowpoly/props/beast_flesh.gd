class_name BeastFlesh
extends RefCounted
## The flesh of the monster under a hellgate room (HellgateBeast): the ENEMY toon look (the heroes' LowPolyMaterial with
## the monsters' glow faces: vertex alpha < 0.75 is emissive) plus what the GPU does, so a tentacle is one mesh and a
## frame costs a couple of uniform writes:
##
##   - PATH tubes (path_tube): a long tentacle is built in place along its path. The mesh carries, per vertex, its
##     distance along the path and a phase (UV), its sway (CUSTOM1.xyz: zero where it grips, larger at the free tip) and
##     the tube's radius there (CUSTOM1.w). The vertex shader moves the free part (sway) and swells the tube with a bulge
##     that leaves the root on the gate's beat and travels to the tip (peristalsis). The outline pass moves the same way.
##     Faces get a flat normal from screen derivatives, so the moving tube stays faceted.
##   - FADE: flesh below `fade_hi` (world y) darkens towards the background by `fade_lo`: the roots, under the floor slab,
##     are lost in the dark.
##   - PULSE: the glowing faces (suckers) brighten with the travelling beat (`beat_rate` is the gate's: HellgateModel
##     beats at 2.6 rad/s, the origin at 1.7).
##   - SINK: `sink` 0..1 slides everything down into the dark (the gate closing).
## A mesh without CUSTOM1 / UV (any LowPoly soup, Limb.to_mesh) does not move: it only gets the fade and the pulse.
## Headless-safe: ordinary spatial shaders, no textures.
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

const PATH_GLSL := """
uniform float t = 0.0;
uniform float sway_rate = 0.45;      // rad/s of the tip sway
uniform float wave_k = 0.35;         // how much the sway lags along the tube (per world unit)
uniform float sink = 0.0;            // 0..1: everything slides down into the dark
uniform float beat_rate = 2.6;       // the gate core's beat
uniform float pulse_amp = 0.7;       // how much the glow swells on the travelling beat
uniform float pulse_k = 0.9;         // phase lag of the beat per world unit along the tube
uniform float pulse_base = 1.0;      // the glow between beats
uniform float swell_amp = 0.14;      // how much the beat bulges the tube (x its radius)
uniform float fade_lo = -5.2;        // world y: flesh this deep is lost in the dark
uniform float fade_hi = -1.9;        // world y: flesh this high is fully lit
varying float v_fade;
varying float v_pulse;

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
			+ "varying vec3 wnormal;\n" + PATH_GLSL)
	code = _patch(code, "\twnormal = normalize((MODEL_NORMAL_MATRIX * NORMAL));",
			"\tVERTEX = path_move(VERTEX, normalize(CUSTOM0.rgb * 2.0 - 1.0), UV, CUSTOM1);\n"
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
	code = _patch(code, "uniform float z_push = 0.04;", "uniform float z_push = 0.04;\n" + PATH_GLSL)
	code = _patch(code, "\tvec3 sn = CUSTOM0.rgb * 2.0 - 1.0;",
			"\tvec3 sn = CUSTOM0.rgb * 2.0 - 1.0;\n"
			+ "\tVERTEX = path_move(VERTEX, normalize(sn), UV, CUSTOM1);")
	return code


static func _patch(code: String, find: String, repl: String) -> String:
	assert(code.contains(find), "BeastFlesh: shader patch target missing: " + find)
	return code.replace(find, repl)


# ------------------------------------------------------------------ still pieces

## A triangle bag like LowPoly.Soup, but wound explicitly (outward from a given inside point) and turned into a mesh
## the flesh material reads (CUSTOM0 = the welded normal for the outline; no CUSTOM1: it does not move).
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


# ------------------------------------------------------------------ PATH tubes

## Vertex streams for path_tube.
class _Streams extends RefCounted:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()

	func emit(p: Vector3, wn: Vector3, col: Color, s: float, phase: float, sway: Vector3, r: float) -> void:
		verts.append(p)
		norms.append(wn)
		colors.append(col)
		uvs.append(Vector2(s, phase))
		c0.append(wn.x * 0.5 + 0.5)
		c0.append(wn.y * 0.5 + 0.5)
		c0.append(wn.z * 0.5 + 0.5)
		c0.append(1.0)
		c1.append(sway.x)
		c1.append(sway.y)
		c1.append(sway.z)
		c1.append(r)


## A long tube along `pts` (world space; the mesh sits at the origin): rings of `sides`, a radius and a sway amplitude
## per point (0 where it grips, up to ~0.4 at a free tip), a pointed tip. Colours run from the dark root through the
## flesh to the tip; the side facing down is the pale underside. Studs (suckers, a third of them glowing) every
## `sucker_gap` along the top; obsidian spines along the back every `spine_gap` (0 = none) of the first 60 %.
static func path_tube(pts: Array[Vector3], radii: Array[float], sway: Array[float], seed_value: int, sides: int = 7,
		sucker_gap: float = 0.55, spine_gap: float = 0.0, phase: float = 0.0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := pts.size()
	var out := _Streams.new()
	var s_at := PackedFloat32Array([0.0])
	for i in range(1, n):
		s_at.append(s_at[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total := s_at[n - 1]
	# ring frames (parallel transport) and each point's sway vector (sideways to the path)
	var xs := PackedVector3Array()
	var ys := PackedVector3Array()
	var ts := PackedVector3Array()
	var sw := PackedVector3Array()
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
		var side := Vector3(-t.z, 0.0, t.x)
		side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
		sw.append(side * sway[i])
	# ring offsets (from the path point), one row per point
	var ring := PackedVector3Array()
	for i in n:
		for k in sides:
			var a := TAU * float(k) / sides + 0.35 * i
			var r := radii[i] * (1.0 + rng.randf_range(-0.07, 0.07))
			ring.append(xs[i] * (cos(a) * r) + ys[i] * (sin(a) * r))
	for i in n - 1:
		var u := s_at[i] / maxf(total, 0.01)
		var base_col := FLESH_DARK.lerp(FLESH, smoothstep(0.0, 0.25, u)).lerp(FLESH_HI, 0.5 * smoothstep(0.3, 0.8, u)).lerp(TIP, smoothstep(0.85, 1.0, u))
		for k in sides:
			var k1 := (k + 1) % sides
			var o00 := ring[i * sides + k]
			var o01 := ring[i * sides + k1]
			var o11 := ring[(i + 1) * sides + k1]
			var o10 := ring[(i + 1) * sides + k]
			var a := pts[i] + o00
			var b := pts[i] + o01
			var c := pts[i + 1] + o11
			var d := pts[i + 1] + o10
			var mid_n := (o00 + o01).normalized()
			var col := base_col.lerp(UNDER, 0.55) if mid_n.y < -0.35 else base_col
			var lin := _paint(rng, col).srgb_to_linear()
			lin.a = 1.0
			# Godot's front faces are clockwise: emit (a, c, b), (a, d, c) when a, b, c, d run counter-clockwise outward,
			# else (c, a, b), (c, d, a)
			if (b - a).cross(d - a).dot(mid_n) >= 0.0:
				_quad_out(out, a, c, b, d, o00, o11, o01, o10, i, i + 1, i, i + 1, lin, s_at, phase, sw, radii)
			else:
				_quad_out(out, c, a, b, d, o11, o00, o01, o10, i + 1, i, i, i + 1, lin, s_at, phase, sw, radii)
	# the tip: a cone to a point
	var last := n - 1
	var apex := pts[last] + ts[last] * radii[last] * 2.5
	var tip_lin := _paint(rng, TIP).srgb_to_linear()
	for k in sides:
		var oa := ring[last * sides + k]
		var ob := ring[last * sides + (k + 1) % sides]
		var a := pts[last] + oa
		var b := pts[last] + ob
		var tri := PackedVector3Array([a, apex, b])
		if (b - a).cross(apex - a).dot(oa + ob) <= 0.0:
			tri = PackedVector3Array([a, b, apex])
		for v in tri:
			out.emit(v, (v - pts[last]).normalized(), tip_lin, s_at[last], phase, sw[last], radii[last])
	# studs and spines, placed by distance along the tube
	var studs: Array[Vector2] = []     # (s, 1 = sucker / 0 = spine)
	if sucker_gap > 0.0:
		var at := total * 0.12
		while at < total * 0.97:
			studs.append(Vector2(at, 1.0))
			at += sucker_gap * rng.randf_range(0.8, 1.25) * (0.7 if at > total * 0.6 else 1.0)
	if spine_gap > 0.0:
		var at := total * 0.15
		while at < total * 0.62:
			studs.append(Vector2(at, 0.0))
			at += spine_gap * rng.randf_range(0.8, 1.2)
	var i := 0
	for st in studs:
		i = 0
		while i < n - 2 and s_at[i + 1] < st.x:
			i += 1
		var f := clampf((st.x - s_at[i]) / maxf(s_at[i + 1] - s_at[i], 0.001), 0.0, 1.0)
		var center := pts[i].lerp(pts[i + 1], f)
		var r := lerpf(radii[i], radii[i + 1], f)
		var up := ys[i] if ys[i].y >= 0.0 else -ys[i]
		var side := xs[i] if xs[i].y >= 0.0 else -xs[i]
		var soup: LowPoly.Soup
		var place: Transform3D
		if st.y > 0.5:
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
				out.emit(v, (v - center).normalized(), lin, s_at[i], phase, sw[i], radii[i])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = out.verts
	arr[Mesh.ARRAY_NORMAL] = out.norms
	arr[Mesh.ARRAY_COLOR] = out.colors
	arr[Mesh.ARRAY_TEX_UV] = out.uvs
	arr[Mesh.ARRAY_CUSTOM0] = out.c0
	arr[Mesh.ARRAY_CUSTOM1] = out.c1
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
	var max_sway := 0.0
	for s in sway:
		max_sway = maxf(max_sway, s)
	mesh.custom_aabb = mesh.get_aabb().grow(max_sway * 1.7 + 0.5)   # (the sway and the beat move it outside its rest box)
	return mesh


## One quad as two clockwise triangles (p0, p1, p2) and (p0, p3, p1), with each corner's ring offset (its weld normal)
## and path index.
static func _quad_out(out: _Streams, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, o0: Vector3, o1: Vector3,
		o2: Vector3, o3: Vector3, i0: int, i1: int, i2: int, i3: int, lin: Color, s_at: PackedFloat32Array, phase: float,
		sw: PackedVector3Array, radii: Array[float]) -> void:
	out.emit(p0, o0.normalized(), lin, s_at[i0], phase, sw[i0], radii[i0])
	out.emit(p1, o1.normalized(), lin, s_at[i1], phase, sw[i1], radii[i1])
	out.emit(p2, o2.normalized(), lin, s_at[i2], phase, sw[i2], radii[i2])
	out.emit(p0, o0.normalized(), lin, s_at[i0], phase, sw[i0], radii[i0])
	out.emit(p3, o3.normalized(), lin, s_at[i3], phase, sw[i3], radii[i3])
	out.emit(p1, o1.normalized(), lin, s_at[i1], phase, sw[i1], radii[i1])


static func _paint(rng: RandomNumberGenerator, col: Color, vary: float = 0.08) -> Color:
	var h := col.h + rng.randf_range(-1.0, 1.0) * vary * 0.12
	var s := clampf(col.s * (1.0 + rng.randf_range(-1.0, 1.0) * vary * 1.6), 0.0, 1.0)
	var v := clampf(col.v * (1.0 + rng.randf_range(-1.0, 1.0) * vary), 0.0, 1.0)
	return Color.from_hsv(fposmod(h, 1.0), s, v, col.a)


## Catmull-Rom through `ctrl`, resampled to points about `step` apart (with their radius and sway interpolated):
## [points, radii, sways].
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
