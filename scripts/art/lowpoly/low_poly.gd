class_name LowPoly
extends RefCounted
## Faceted low-poly mesh helper. Everything is built as a triangle "soup" with FLAT per-face
## normals (no vertex is shared between faces, so nothing is ever smoothed) and a painted colour
## per face (small hue / saturation / value jitter, the hand-painted look) baked into vertex COLOR.
##
## Each mesh also carries CUSTOM0 = the position-WELDED smooth normal (n*0.5+0.5). The inverted-hull
## outline pass reads it so hard-edged, chiselled shapes do not split open at their corners.
##
## Primitives are centred on the origin; place them with a Transform3D when merging:
##   var s := LowPoly.boulder(Vector3(0.5, 0.4, 0.45), 1, 0.14, STONE, 3)
##   s.merge(LowPoly.box(Vector3(0.2, 0.2, 0.2), RED), LowPoly.at(Vector3(0, 0.5, 0)))
##   mesh_instance.mesh = s.to_mesh()
## Winding is auto-oriented outward from the origin, so primitives may be built in any order.
## Vertex colour alpha is a "reflective" mask (0 matte .. 1 retro-reflective tape).


## Dev only (ZFightCheck): while true, every triangle remembers the code that made it (LowPoly.origin_name) and
## to_mesh() stores those ids on the mesh as meta ORIGIN_META. Off in the game: then it costs one bool test a triangle.
static var trace := false
const ORIGIN_META := &"lowpoly_origins"
## Wrapper functions skipped when naming a triangle's origin (the call that matters is the one above them).
const _TRACE_SKIP: Array[String] = ["box", "cyl", "frus", "ball", "rod", "_b", "_c", "_cyl", "_rod", "_ball", "_box", "_n", "_dented", "_flat", "mesh"]
static var _origin_names := PackedStringArray()
static var _origin_ids := {}


## A bag of triangles. Three vertices per triangle, one colour per triangle.
class Soup extends RefCounted:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var origins := PackedInt32Array()   ## LowPoly.trace only: per-triangle origin id (LowPoly.origin_name)
	var vary := 0.07                 ## per-face painted variation
	var rng := RandomNumberGenerator.new()

	func _init(seed_value: int = 1, vary_amount: float = 0.07) -> void:
		rng.seed = seed_value
		vary = vary_amount

	func tri_count() -> int:
		return cols.size()

	## One painted triangle, wound outward relative to the soup origin.
	func add_tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var n := (b - a).cross(c - a)
		if n.dot((a + b + c) / 3.0) < 0.0:
			var tmp := b
			b = c
			c = tmp
		verts.append(a)
		verts.append(b)
		verts.append(c)
		cols.append(paint(col))
		if LowPoly.trace:
			_pad_origins(LowPoly._origin_here())

	## A quad (a, b, c, d in ring order) as two triangles, split along a seed-chosen diagonal so the
	## cuts do not all run the same way.
	func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		if rng.randf() < 0.5:
			add_tri(a, b, c, col)
			add_tri(a, c, d, col)
		else:
			add_tri(a, b, d, col)
			add_tri(b, c, d, col)

	## Painted variation of `col`: hue / saturation / value nudged per face.
	func paint(col: Color) -> Color:
		if vary <= 0.0:
			return col
		var h := col.h + rng.randf_range(-1.0, 1.0) * vary * 0.12
		var s := clampf(col.s * (1.0 + rng.randf_range(-1.0, 1.0) * vary * 1.6), 0.0, 1.0)
		var v := clampf(col.v * (1.0 + rng.randf_range(-1.0, 1.0) * vary), 0.0, 1.0)
		return Color.from_hsv(fposmod(h, 1.0), s, v, col.a)

	## Append `other` (already painted) through `xf`.
	func merge(other: Soup, xf: Transform3D = Transform3D.IDENTITY) -> Soup:
		for p in other.verts:
			verts.append(xf * p)
		if LowPoly.trace:
			var here := LowPoly._origin_here()
			_pad_origins(here)
			for i in other.cols.size():
				origins.append(other.origins[i] if i < other.origins.size() else here)
		cols.append_array(other.cols)
		return self

	## Trace only: give every triangle without an origin yet (appended straight to verts / cols) `id`.
	func _pad_origins(id: int) -> void:
		while origins.size() < cols.size():
			origins.append(id)

	## Chisel the surface: every distinct vertex position moves by a deterministic random offset,
	## the same for every triangle that shares it (so the shape stays closed). `axes` scales it per axis.
	func jitter(amount: float, seed_value: int, axes: Vector3 = Vector3.ONE) -> Soup:
		var cache := {}
		var r := RandomNumberGenerator.new()
		for i in verts.size():
			var p := verts[i]
			var k := LowPoly.key(p)
			if not cache.has(k):
				r.seed = hash(k) + seed_value * 7919
				cache[k] = Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)) * axes * amount
			verts[i] = p + (cache[k] as Vector3)
		return self

	## Final mesh: flat normals, painted colours (sRGB -> linear), welded smooth normal in CUSTOM0.
	## `top_light` bakes a hand-painted light: up-facing faces brighter, down-facing darker.
	func to_mesh(top_light: float = 0.22) -> ArrayMesh:
		var weld := {}
		var face_n: Array[Vector3] = []
		for t in range(0, verts.size(), 3):
			var a := verts[t]
			var b := verts[t + 1]
			var c := verts[t + 2]
			# triangles are counter-clockwise outward; Godot front faces are clockwise
			var fn := (b - a).cross(c - a)
			face_n.append(fn)
			for k in 3:
				var wk := LowPoly.key(verts[t + k])
				weld[wk] = (weld[wk] if weld.has(wk) else Vector3.ZERO) + fn
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA8_UNORM)
		var kept := PackedInt32Array()
		if LowPoly.trace:
			_pad_origins(LowPoly._origin_here())
		for t in range(0, verts.size(), 3):
			var fn: Vector3 = face_n[t / 3]
			if fn.length() < 0.0000001:
				continue   # degenerate (jitter collapsed it)
			if LowPoly.trace:
				kept.append(origins[t / 3])
			var n := fn.normalized()
			var col := cols[t / 3]
			var lit := 1.0 + top_light * clampf(n.y, -1.0, 1.0)
			var base := Color(col.r * lit, col.g * lit, col.b * lit, 1.0).srgb_to_linear()
			base.a = col.a
			# emit in the order a, c, b -> clockwise
			for k in [0, 2, 1]:
				var p := verts[t + k]
				var w: Vector3 = weld[LowPoly.key(p)]
				w = w.normalized() if w.length() > 0.00001 else n
				st.set_color(base)
				st.set_normal(n)
				st.set_custom(0, Color(w.x * 0.5 + 0.5, w.y * 0.5 + 0.5, w.z * 0.5 + 0.5, 1.0))
				st.add_vertex(p)
		var mesh := st.commit()
		if LowPoly.trace:
			mesh.set_meta(LowPoly.ORIGIN_META, kept)
		return mesh


## Trace only: the id of the code calling into LowPoly right now (the first two frames outside this file and outside
## the plain box / cylinder wrappers, "file:line function").
static func _origin_here() -> int:
	var parts := PackedStringArray()
	for f: Dictionary in get_stack():
		var src := String(f["source"]).get_file()
		var fn := String(f["function"])
		if src == "low_poly.gd" or _TRACE_SKIP.has(fn):
			continue
		parts.append("%s:%d %s" % [src, int(f["line"]), fn])
		if parts.size() == 2:
			break
	var k := " < ".join(parts)
	if not _origin_ids.has(k):
		_origin_ids[k] = _origin_names.size()
		_origin_names.append(k)
	return int(_origin_ids[k])


## The code an origin id (from a traced mesh's ORIGIN_META) points at, e.g. "van_model.gd:241 _decal < van_model.gd:290 _side_details".
static func origin_name(id: int) -> String:
	return _origin_names[id] if id >= 0 and id < _origin_names.size() else "?"


static func key(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))


# --------------------------------------------------------------------------- primitives

## Jittered low-res icosphere: a chunky boulder. radii = half extents. detail 0 = 20 faces
## (very angular), 1 = 80 faces, 2 = 320.
static func boulder(radii: Vector3, detail: int, jitter_amount: float, col: Color, seed_value: int = 1, vary: float = 0.07) -> Soup:
	var s := Soup.new(seed_value, vary)
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized()
	var f: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1)]
	for _d in detail:
		var nf: Array[Vector3i] = []
		var mid := {}
		for tri in f:
			var m: Array[int] = []
			for e in 3:
				var i0: int = tri[e]
				var i1: int = tri[(e + 1) % 3]
				var mk := Vector2i(mini(i0, i1), maxi(i0, i1))
				if not mid.has(mk):
					v.append(((v[i0] + v[i1]) * 0.5).normalized())
					mid[mk] = v.size() - 1
				m.append(mid[mk])
			nf.append(Vector3i(tri.x, m[0], m[2]))
			nf.append(Vector3i(tri.y, m[1], m[0]))
			nf.append(Vector3i(tri.z, m[2], m[1]))
			nf.append(Vector3i(m[0], m[1], m[2]))
		f = nf
	for tri in f:
		s.add_tri(v[tri.x] * radii, v[tri.y] * radii, v[tri.z] * radii, col)
	# jitter scaled to the smallest radius so big and small boulders chisel alike
	return s.jitter(jitter_amount * minf(radii.x, minf(radii.y, radii.z)), seed_value)


## Faceted box (full size). seg subdivides each face so jitter can chisel it.
static func box(size: Vector3, col: Color, seed_value: int = 1, jitter_amount: float = 0.0, seg: int = 1, vary: float = 0.07) -> Soup:
	return frustum(Vector2(size.x, size.z), Vector2(size.x, size.z), size.y, col, seed_value, jitter_amount, seg, Vector2.ZERO, vary)


## Rectangular frustum: bottom (w, d) and top (w, d) sizes, height h, optional top offset (x, z).
static func frustum(bottom: Vector2, top: Vector2, h: float, col: Color, seed_value: int = 1, jitter_amount: float = 0.0, seg: int = 1, top_off: Vector2 = Vector2.ZERO, vary: float = 0.07) -> Soup:
	var s := Soup.new(seed_value, vary)
	var hy := h * 0.5
	var b: Array[Vector3] = [
		Vector3(-bottom.x * 0.5, -hy, -bottom.y * 0.5), Vector3(bottom.x * 0.5, -hy, -bottom.y * 0.5),
		Vector3(bottom.x * 0.5, -hy, bottom.y * 0.5), Vector3(-bottom.x * 0.5, -hy, bottom.y * 0.5)]
	var tp: Array[Vector3] = [
		Vector3(-top.x * 0.5 + top_off.x, hy, -top.y * 0.5 + top_off.y), Vector3(top.x * 0.5 + top_off.x, hy, -top.y * 0.5 + top_off.y),
		Vector3(top.x * 0.5 + top_off.x, hy, top.y * 0.5 + top_off.y), Vector3(-top.x * 0.5 + top_off.x, hy, top.y * 0.5 + top_off.y)]
	for i in 4:
		var j := (i + 1) % 4
		_grid(s, b[i], b[j], tp[j], tp[i], seg, col)
	_grid(s, b[0], b[1], b[2], b[3], seg, col)
	_grid(s, tp[0], tp[1], tp[2], tp[3], seg, col)
	if jitter_amount > 0.0:
		s.jitter(jitter_amount, seed_value)
	return s


## Faceted cylinder / cone frustum with `sides` sides, rings subdivide the height.
static func cylinder(r_bottom: float, r_top: float, h: float, sides: int, col: Color, seed_value: int = 1, jitter_amount: float = 0.0, rings: int = 1, vary: float = 0.07) -> Soup:
	var s := Soup.new(seed_value, vary)
	var hy := h * 0.5
	var bc := Vector3(0, -hy, 0)
	var tc := Vector3(0, hy, 0)
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var b0 := Vector3(cos(a0) * r_bottom, -hy, sin(a0) * r_bottom)
		var b1 := Vector3(cos(a1) * r_bottom, -hy, sin(a1) * r_bottom)
		var t0 := Vector3(cos(a0) * r_top, hy, sin(a0) * r_top)
		var t1 := Vector3(cos(a1) * r_top, hy, sin(a1) * r_top)
		for r in rings:
			var f0 := float(r) / rings
			var f1 := float(r + 1) / rings
			s.add_quad(b0.lerp(t0, f0), b1.lerp(t1, f0), b1.lerp(t1, f1), b0.lerp(t0, f1), col)
		s.add_tri(bc, b1, b0, col)
		s.add_tri(tc, t0, t1, col)
	if jitter_amount > 0.0:
		s.jitter(jitter_amount, seed_value)
	return s


static func _grid(s: Soup, p00: Vector3, p10: Vector3, p11: Vector3, p01: Vector3, n: int, col: Color) -> void:
	for i in n:
		for j in n:
			var u0 := float(i) / n
			var u1 := float(i + 1) / n
			var v0 := float(j) / n
			var v1 := float(j + 1) / n
			s.add_quad(_bil(p00, p10, p11, p01, u0, v0), _bil(p00, p10, p11, p01, u1, v0),
					_bil(p00, p10, p11, p01, u1, v1), _bil(p00, p10, p11, p01, u0, v1), col)


static func _bil(p00: Vector3, p10: Vector3, p11: Vector3, p01: Vector3, u: float, v: float) -> Vector3:
	return p00.lerp(p10, u).lerp(p01.lerp(p11, u), v)


## A Transform3D at `pos` with an Euler rotation in degrees and optional scale.
static func at(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return Transform3D(b.scaled(scl), pos)
