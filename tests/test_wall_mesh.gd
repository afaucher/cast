extends TestCase
## The terrain mesh of walls (HexMapView), read back from the built ArrayMesh:
##  - CAPS: every flat top over a run of kites (the cap of a cut cell's wall part, the floor tile beside it, and the
##    glowing seam under each) triangulates exactly, for all 63 wall_mask values: all triangles wind the same way as
##    the full hex tops, none overlaps another, each lies over its own kites, and their areas add up to the polygon's.
##    A run of 4 or 5 kites is concave (an inside corner), and a fan from the wrong vertex spilled a triangle over
##    the missing kites (a wall cap hanging over the floor).
##  - TEXTURE DENSITY: every vertical face (wall faces on the midpoint lines and the hex edges, cliffs, crates,
##    stair sides and risers) maps one side-texture repeat to SIZE world units across and one LEVEL up, whatever its
##    length or height, so long and short, tall and low faces show the texture at the same size. Midpoint wall faces
##    used to get half that horizontally (stretched 2x). Tops (floors and wall caps) are sampled in world XZ at one
##    rate, and the face normals are true (the material shader takes a wall's along-axis from its normal).

const LH := Hex.LEVEL_HEIGHT
const FLOOR_LV := 2
const WALL_LV := 9
const KITE_AREA := Hex.SIZE * Hex.SIZE * 1.7320508075688772 / 4.0   ## one sixth of the hex
const SEEDS: Array[int] = [3, 7, 42, 1234]

var _faces := 0
var _midpoint_faces := 0
var _caps := 0


func setup() -> void:
	timeout_sec = 180.0
	check(HexMapView.MATERIAL_SHADER.contains("vec2(dot(wp.xz, along), wp.y)"), "the material shader maps wall faces in world units")
	for mask in range(1, HexMap.ALL_KITES + 1):
		var view := _build(_cut_cell_map(mask))
		_check_caps(view.mesh_instance.mesh, mask)
		_check_sides(view.mesh_instance.mesh, "mask %d" % mask)
		view.free()
	for s in SEEDS:
		var view := _build(DungeonGen.generate(s))
		_check_sides(view.mesh_instance.mesh, "seed %d" % s)
		_check_tops(view.mesh_instance.mesh, "seed %d" % s)
		view.free()
	print("wall mesh: %d caps over 63 masks, %d vertical faces (%d on midpoint wall lines) at one texture density" % [_caps, _faces, _midpoint_faces])
	check(_midpoint_faces > 100, "the generated floors have midpoint wall faces to measure (%d)" % _midpoint_faces)
	finish()


## One cut cell (raised floor, a wall part `mask`) in a patch of lower floor.
func _cut_cell_map(mask: int) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 2):
		m.set_cell(c, 0).tag = "room:0"
	var cell := m.set_cell(Vector2i.ZERO, FLOOR_LV)
	cell.tag = "room:0"
	cell.wall_mask = mask
	cell.wall_top = WALL_LV
	m.midpoint_walls = true
	return m


func _build(m: HexMap) -> HexMapView:
	var view := HexMapView.new()
	view.build(m)
	return view


# --- caps ---------------------------------------------------------------------------------------------------------

func _check_caps(mesh: ArrayMesh, mask: int) -> void:
	var groups := {}   ## y (rounded) -> Array of [a, b, c] Vector2 triangles
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var t := 0
		while t < idx.size():
			var p0 := v[idx[t]]
			var p1 := v[idx[t + 1]]
			var p2 := v[idx[t + 2]]
			t += 3
			if n[idx[t - 3]].y < 0.999 or absf(p0.y - p1.y) > 1e-5 or absf(p0.y - p2.y) > 1e-5:
				continue   # not a flat top (bevels slope, sides stand)
			var key := snappedf(p0.y, 0.001)
			if not groups.has(key):
				groups[key] = []
			groups[key].append([Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), Vector2(p2.x, p2.z)])
	var walls := _bits(mask)
	var open := 6 - walls
	var top2 := HexMapView.TOP_SCALE * HexMapView.TOP_SCALE
	# the neighbours' full hex tops (level 0) give the winding every top must have
	var ref_sign := _sign_of(groups.get(0.0, []))
	check(ref_sign != 0, "mask %d: the plain hex tops wind one way" % mask)
	_cap(groups, WALL_LV * LH, walls * KITE_AREA * top2, mask, ref_sign, "mask %d wall cap" % mask)
	_cap(groups, WALL_LV * LH - HexMapView.SEAM_DROP, walls * KITE_AREA, mask, ref_sign, "mask %d wall seam" % mask)
	_cap(groups, FLOOR_LV * LH, open * KITE_AREA * top2, HexMap.ALL_KITES & ~mask, ref_sign, "mask %d floor top" % mask)
	_cap(groups, FLOOR_LV * LH - HexMapView.SEAM_DROP, open * KITE_AREA, HexMap.ALL_KITES & ~mask, ref_sign, "mask %d floor seam" % mask)


## The triangles at height y: same winding as ref_sign, inside the kites of `kites`, pairwise disjoint, total `area`.
func _cap(groups: Dictionary, y: float, area: float, kites: int, ref_sign: int, tag: String) -> void:
	var tris: Array = groups.get(snappedf(y, 0.001), [])
	if area <= 0.0:
		check(tris.is_empty(), "%s: nothing drawn where there are no kites" % tag)
		return
	_caps += 1
	var total := 0.0
	var wrong_winding := 0
	var outside := 0
	for tri: Array in tris:
		var a := _signed_area(tri)
		if absf(a) < 1e-9:
			continue   # a degenerate triangle covers nothing
		if (1 if a > 0.0 else -1) != ref_sign:
			wrong_winding += 1
		total += absf(a)
		var ctr: Vector2 = (tri[0] + tri[1] + tri[2]) / 3.0
		if (kites >> Hex.kite_of(Vector3(ctr.x, 0.0, ctr.y))) & 1 == 0:
			outside += 1
	var overlap := 0.0
	for i in tris.size():
		for j in range(i + 1, tris.size()):
			for poly: PackedVector2Array in Geometry2D.intersect_polygons(_pv(tris[i]), _pv(tris[j])):
				overlap += absf(_poly_area(poly))
	check(wrong_winding == 0, "%s: %d of %d triangles wind the wrong way (a fan over a concave outline)" % [tag, wrong_winding, tris.size()])
	check(outside == 0, "%s: %d triangles lie over kites that are not part of it" % [tag, outside])
	check(overlap < 1e-5, "%s: triangles overlap by %.5f" % [tag, overlap])
	near(total, area, 1e-4, "%s: the triangles cover the polygon's area exactly" % tag)


# --- side faces ---------------------------------------------------------------------------------------------------

## Every vertical triangle: a true horizontal normal, and the texture mapped at 1 / SIZE across and 1 / LEVEL up.
func _check_sides(mesh: ArrayMesh, tag: String) -> void:
	var bad_normal := 0
	var bad_density := 0
	var worst := ""
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var t := 0
		while t < idx.size():
			var i0 := idx[t]
			var i1 := idx[t + 1]
			var i2 := idx[t + 2]
			t += 3
			var nn := n[i0]
			if absf(nn.y) > 0.01:
				continue   # a top or a bevel
			_faces += 1
			if absf((v[i1] - v[i0]).dot(nn)) > 2e-3 or absf((v[i2] - v[i0]).dot(nn)) > 2e-3:
				bad_normal += 1
				continue
			# face coordinates: s along the face (the shader's along-axis), y up
			var along := Vector3(-nn.z, 0.0, nn.x)
			var s0 := Vector2(v[i0].dot(along), v[i0].y)
			var e1 := Vector2(v[i1].dot(along), v[i1].y) - s0
			var e2 := Vector2(v[i2].dot(along), v[i2].y) - s0
			var det := e1.x * e2.y - e1.y * e2.x
			if absf(det) < 1e-6:
				continue   # a sliver: no area to texture
			var d1 := uv[i1] - uv[i0]
			var d2 := uv[i2] - uv[i0]
			# [du/ds du/dy; dv/ds dv/dy] = [d1 d2] * inverse([e1 e2])
			var du_ds := (d1.x * e2.y - d2.x * e1.y) / det
			var du_dy := (d2.x * e1.x - d1.x * e2.x) / det
			var dv_ds := (d1.y * e2.y - d2.y * e1.y) / det
			var dv_dy := (d2.y * e1.x - d1.y * e2.x) / det
			var ok := absf(absf(du_ds) - 1.0 / Hex.SIZE) < 2e-3 and absf(du_dy) < 2e-3 and absf(dv_ds) < 2e-3 \
					and absf(dv_dy + 1.0 / LH) < 2e-3
			if not ok:
				bad_density += 1
				if worst == "":
					worst = "u/s %.3f u/y %.3f v/s %.3f v/y %.3f at %s" % [du_ds, du_dy, dv_ds, dv_dy, str(v[i0])]
			if _on_midpoint_line(v[i0], v[i1], v[i2]):
				_midpoint_faces += 1
	check(bad_normal == 0, "%s: %d vertical faces have a normal that is not square to the face" % [tag, bad_normal])
	check(bad_density == 0, "%s: %d vertical faces map the texture at the wrong density (first: %s; want |u/s| = %.2f, v/y = %.2f)" \
			% [tag, bad_density, worst, 1.0 / Hex.SIZE, -1.0 / LH])


## A face on a midpoint wall line has a corner on a hex center.
func _on_midpoint_line(a: Vector3, b: Vector3, c: Vector3) -> bool:
	for p: Vector3 in [a, b, c]:
		var h := Hex.to_world(Hex.from_world(p))
		if Vector2(p.x - h.x, p.z - h.z).length() < 1e-4:
			return true
	return false


## Floor tops and wall caps (the classic textures) are sampled in world XZ, both at 1 / SLATE_PERIOD.
func _check_tops(mesh: ArrayMesh, tag: String) -> void:
	var tex_floor := HexMapView.get_texture("floor_top")
	var tex_wall := HexMapView.get_texture("wall_top")
	var seen := 0
	var bad := 0
	for s in mesh.get_surface_count():
		var sm := mesh.surface_get_material(s) as ShaderMaterial
		var tx: Variant = sm.get_shader_parameter("tex")
		if tx != tex_floor and tx != tex_wall:
			continue
		seen += 1
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		for i in v.size():
			if uv[i].distance_to(Vector2(v[i].x, v[i].z) / ProtoTextures.SLATE_PERIOD) > 1e-4:
				bad += 1
	eq(seen, 2, "%s: floor tops and wall caps are both drawn" % tag)
	check(bad == 0, "%s: %d floor / wall-cap vertices are not sampled in world XZ" % [tag, bad])


# --- helpers ------------------------------------------------------------------------------------------------------

static func _bits(mask: int) -> int:
	var n := 0
	for k in 6:
		n += (mask >> k) & 1
	return n


static func _signed_area(tri: Array) -> float:
	var a: Vector2 = tri[0]
	var b: Vector2 = tri[1]
	var c: Vector2 = tri[2]
	return 0.5 * ((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y))


func _sign_of(tris: Array) -> int:
	var sgn := 0
	for tri: Array in tris:
		var a := _signed_area(tri)
		if absf(a) < 1e-9:
			continue
		var s := 1 if a > 0.0 else -1
		if sgn == 0:
			sgn = s
		elif s != sgn:
			return 0
	return sgn


static func _pv(tri: Array) -> PackedVector2Array:
	return PackedVector2Array([tri[0], tri[1], tri[2]])


static func _poly_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return 0.5 * a
