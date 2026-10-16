class_name ArtMesh
extends RefCounted
## Tiny procedural mesh library for the toy characters. Every mesh is an ArrayMesh carrying:
##   NORMAL - shading normals (flat for boxes / prisms, smooth for blobs / lathes)
##   COLOR  - the position-WELDED smooth normal, encoded n*0.5+0.5, read by Toon's outline pass
## Shapes are built from vertex/index lists in any winding; `_build` orients them outward.
## Sizes are full dimensions (diameter, not radius). Characters face -Z, +X is their right.

enum Shading { FLAT, SMOOTH_INDEX, SMOOTH_WELD }


# ---------------------------------------------------------------- core

static func _key(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * 2000.0), roundi(v.y * 2000.0), roundi(v.z * 2000.0))


static func _enc(n: Vector3) -> Color:
	return Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0)


static func _build(verts: PackedVector3Array, idx: PackedInt32Array, mode: int) -> ArrayMesh:
	# Orient: Godot front faces are clockwise. Signed volume > 0 means counter-clockwise outward.
	var vol := 0.0
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		vol += a.dot(b.cross(c))
	if vol > 0.0:
		for t in range(0, idx.size(), 3):
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
	# area-weighted face normals (outward for clockwise triangles)
	var face_n: Array[Vector3] = []
	var weld := {}
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var fn := (c - a).cross(b - a)
		face_n.append(fn)
		for k in 3:
			var key := _key(verts[idx[t + k]])
			var prev: Vector3 = weld[key] if weld.has(key) else Vector3.ZERO
			weld[key] = prev + fn

	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	var out_i := PackedInt32Array()
	if mode == Shading.FLAT:
		for t in range(0, idx.size(), 3):
			var fn: Vector3 = face_n[t / 3].normalized()
			for k in 3:
				out_v.append(verts[idx[t + k]])
				out_n.append(fn)
				out_i.append(out_v.size() - 1)
	else:
		var acc := PackedVector3Array()
		acc.resize(verts.size())
		for t in range(0, idx.size(), 3):
			for k in 3:
				acc[idx[t + k]] += face_n[t / 3]
		for i in verts.size():
			out_v.append(verts[i])
			if mode == Shading.SMOOTH_WELD:
				out_n.append((weld[_key(verts[i])] as Vector3).normalized())
			else:
				out_n.append(acc[i].normalized() if acc[i].length() > 0.00001 else Vector3.UP)
		out_i = idx
	for i in out_v.size():
		var w: Vector3 = weld[_key(out_v[i])]
		w = w.normalized() if w.length() > 0.00001 else Vector3.UP
		out_c.append(_enc(w))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	arrays[Mesh.ARRAY_COLOR] = out_c
	arrays[Mesh.ARRAY_INDEX] = out_i
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## Convert any stock mesh so the outline pass works on it.
static func prep(mesh: Mesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	return _build(verts, idx, Shading.SMOOTH_INDEX)


## Merge meshes (already built by ArtMesh) into one, each with its own transform.
static func merge(meshes: Array, xforms: Array) -> ArrayMesh:
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_c := PackedColorArray()
	var out_i := PackedInt32Array()
	for k in meshes.size():
		var m: Mesh = meshes[k]
		var t: Transform3D = xforms[k]
		var arr := m.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := out_v.size()
		var nb := t.basis.inverse().transposed()
		for i in v.size():
			out_v.append(t * v[i])
			out_n.append((nb * n[i]).normalized())
			var w := Vector3(c[i].r, c[i].g, c[i].b) * 2.0 - Vector3.ONE
			out_c.append(_enc((nb * w).normalized()))
		for i in ix:
			out_i.append(base + i)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	arrays[Mesh.ARRAY_COLOR] = out_c
	arrays[Mesh.ARRAY_INDEX] = out_i
	var res := ArrayMesh.new()
	res.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return res


## Transform helper: position, euler rotation in degrees, scale.
static func xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return Transform3D(b.scaled(scl), pos)


# ---------------------------------------------------------------- shapes

static func _spow(x: float, e: float) -> float:
	return signf(x) * pow(absf(x), e)


## Super-ellipsoid: power 2 = ellipsoid, 3-4 = pillowy chunk, 8+ = nearly a box.
## lumps > 0 roughens the surface (rocks); `seed_value` varies it.
static func blob(size: Vector3, power: float = 2.0, lumps: float = 0.0, seed_value: int = 0, segs: int = 14, rings: int = 9) -> ArrayMesh:
	var e := 2.0 / power
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var noise: FastNoiseLite = null
	if lumps > 0.0:
		noise = FastNoiseLite.new()
		noise.seed = seed_value
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.9
	for i in rings + 1:
		var v := -PI * 0.5 + PI * float(i) / float(rings)
		for j in segs:
			var u := TAU * float(j) / float(segs)
			var cv := cos(v)
			var p := Vector3(_spow(cv, e) * _spow(cos(u), e), _spow(sin(v), e), _spow(cv, e) * _spow(sin(u), e))
			if noise != null:
				p *= 1.0 + lumps * noise.get_noise_3dv(p * 2.2)
			verts.append(p * size * 0.5)
	for i in rings:
		for j in segs:
			var a := i * segs + j
			var b := i * segs + (j + 1) % segs
			var c := (i + 1) * segs + j
			var d := (i + 1) * segs + (j + 1) % segs
			idx.append_array([a, b, c, b, d, c])
	return _build(verts, idx, Shading.SMOOTH_WELD)


## Surface of revolution around Y. profile = (radius, y) points; repeat a point to make a hard edge.
## offset(t) -> Vector3 shifts ring t (0..1 along the profile), for bent hats and the like.
static func lathe(profile: PackedVector2Array, segs: int = 14, offset: Callable = Callable()) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var n := profile.size()
	for i in n:
		var off := Vector3.ZERO
		if offset.is_valid():
			off = offset.call(float(i) / float(n - 1))
		for j in segs:
			var u := TAU * float(j) / float(segs)
			verts.append(Vector3(cos(u) * profile[i].x, profile[i].y, sin(u) * profile[i].x) + off)
	for i in n - 1:
		for j in segs:
			var a := i * segs + j
			var b := i * segs + (j + 1) % segs
			var c := (i + 1) * segs + j
			var d := (i + 1) * segs + (j + 1) % segs
			idx.append_array([a, b, c, b, d, c])
	return _build(verts, idx, Shading.SMOOTH_INDEX)


## Rounded cylinder / frustum with crisp flat caps. bevel rounds the rim.
static func cyl(r_bottom: float, r_top: float, height: float, segs: int = 14, bevel: float = 0.0) -> ArrayMesh:
	var h := height * 0.5
	var b := minf(bevel, minf(r_bottom, r_top) * 0.9)
	var pts := PackedVector2Array([
		Vector2(0, -h), Vector2(r_bottom - b, -h), Vector2(r_bottom - b, -h),
		Vector2(r_bottom, -h + b), Vector2(r_top, h - b),
		Vector2(r_top - b, h), Vector2(r_top - b, h), Vector2(0, h)])
	return lathe(pts, segs)


## Extruded convex polygon (x,z points), flat shaded, centred vertically.
static func prism(poly: PackedVector2Array, height: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var n := poly.size()
	var h := height * 0.5
	for p in poly:
		verts.append(Vector3(p.x, -h, p.y))
	for p in poly:
		verts.append(Vector3(p.x, h, p.y))
	for i in range(1, n - 1):
		idx.append_array([0, i, i + 1, n, n + i, n + i + 1])
	for i in n:
		var j := (i + 1) % n
		idx.append_array([i, j, n + i, j, n + j, n + i])
	return _build(verts, idx, Shading.FLAT)


static func box(size: Vector3) -> ArrayMesh:
	var x := size.x * 0.5
	var z := size.z * 0.5
	return prism(PackedVector2Array([Vector2(-x, -z), Vector2(x, -z), Vector2(x, z), Vector2(-x, z)]), size.y)


## Swept round tube along a polyline, closed with rounded ends. Radius lerps r0 -> r1.
static func tube(points: Array, r0: float, r1: float, segs: int = 6) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var n := points.size()
	var centers: Array[Vector3] = []
	var radii: Array[float] = []
	centers.append(points[0])
	radii.append(0.0)
	for i in n:
		centers.append(points[i])
		radii.append(lerpf(r0, r1, float(i) / float(n - 1)))
	centers.append(points[n - 1])
	radii.append(0.0)
	for i in centers.size():
		var pi := clampi(i - 1, 0, n - 1)
		var pa: Vector3 = points[maxi(pi - 1, 0)]
		var pb: Vector3 = points[mini(pi + 1, n - 1)]
		var tan_v := (pb - pa).normalized() if pb != pa else Vector3.FORWARD
		var ref := Vector3.UP if absf(tan_v.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var s := tan_v.cross(ref).normalized()
		var u := s.cross(tan_v).normalized()
		for j in segs:
			var a := TAU * float(j) / float(segs)
			verts.append(centers[i] + (s * cos(a) + u * sin(a)) * radii[i])
	for i in centers.size() - 1:
		for j in segs:
			var a2 := i * segs + j
			var b2 := i * segs + (j + 1) % segs
			var c2 := (i + 1) * segs + j
			var d2 := (i + 1) * segs + (j + 1) % segs
			idx.append_array([a2, b2, c2, b2, d2, c2])
	return _build(verts, idx, Shading.SMOOTH_WELD)
