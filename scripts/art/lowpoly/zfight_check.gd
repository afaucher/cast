class_name ZFightCheck
extends RefCounted
## Finds z-fighting in built models: pairs of visible triangles that are (nearly) coplanar, face the same way and
## overlap with real area, so the depth test cannot decide between them and the picture flickers as the camera moves.
## Dev and test tool (tests/test_zfight.gd, tools/zfight_scan.gd); nothing in the game calls it. It lives here, not in
## tools/ (which the export leaves out), because a test that ships with the project uses it.
##
##   var set := ZFightCheck.TriSet.new()
##   var item := set.add_item("van")
##   set.add_node(VanModel.new(), item)            # every visible MeshInstance3D surface and Label3D quad, in item space
##   set.add_ground(0.0)                           # the hex floor top: an upward plane at y = 0 under it
##   for f in set.find(false): print(ZFightCheck.describe(f))
##
## A FINDING is two pieces (connected bits of one mesh, usually one box / cylinder of a soup) whose faces fight, with the
## fighting area (cm2), the gap between them, their colours, how much of it a camera can see and, when the model was built
## with LowPoly.trace on, the code that made each piece ("van_model.gd:241 _decal < van_model.gd:290 _side_details").
## SEVERITY (shown_cm2) = overlap area, x SAME_LOOK_WEIGHT when both faces have one paint and material, x CROSSING_WEIGHT
## when the faces slant through each other instead of lying flat on each other, x LABEL_WEIGHT for a Label3D, times the
## share of the finding's sample points that a camera direction sees (VISIBILITY: rays toward the game and menu cameras;
## a face that faces that camera and writes depth blocks them).
##
## WHAT FIGHTS
##  - Parallel faces (within PARALLEL_DEG) closer than EPS along the normal, overlapping with more than MIN_AREA_M2
##    once both are projected on one plane. Faces that only share an edge (the two triangles of a quad, neighbouring
##    tiles) overlap with no area and never show up.
##  - Same direction only, unless a material is double-sided (cull_disabled / CULL_DISABLED): every opaque LowPoly
##    material culls back faces, so two coplanar faces back to back never both draw.
##  - Faces that do not write depth (blend_add / depth_draw_never shaders, alpha-blended labels) still test against
##    depth, so they fight opaque faces; two of them never fight each other (that is draw order, not depth).
##  - Faces pointing down more than NEVER_SEEN_Y are never seen by the game camera (pitch -56) or the menu camera
##    (about 15 degrees above the floor), so they are left out.
##  - The floor: add_ground() stands in for the hex tops (HexMapView draws a level's tops at level * LEVEL_HEIGHT, y = 0 for
##    a model's own space); ZFightModels.scan_site / scan_menu use the real terrain mesh, its floor tops and wall faces.
##
## EPS: how close is "the same depth". The game camera is orthographic (CameraRig: near 0.1, far 220, size 24 default,
## 36 zoomed out) on Forward+ (reverse-Z, a 32-bit float or 24-bit depth buffer). Two parallel faces s apart along their
## normal are s / cos(theta) apart along a view ray (theta = view angle to the normal), and the depth test can be wrong by
##   - the depth quantum: (far - near) * 2^-24 = 1.3e-5 (0.013 mm) at this camera's depths (ortho depth is linear), and
##   - the rasteriser snapping each projected vertex to 1/256 pixel: a pixel is size / viewport height = 24 / 1080 =
##     0.022 (0.050 zoomed out on a 720p window), so a vertex moves up to 0.05 / 256 = 2.0e-4 sideways, which moves the
##     depth along a face by 2.0e-4 * tan(theta) (twice that between two independently snapped faces).
## Faces fight when s / cos(theta) < 2 * 2.0e-4 * tan(theta) + 2 * 1.3e-5, i.e. s < 4.0e-4 * sin(theta) + 2.6e-5 * cos(theta)
## < 0.43 mm for any view angle: the worst case. The float maths before the rasteriser (world coordinates up to ~60,
## float32 ulp 4e-6) adds about 0.02 mm; the menu's perspective camera (near 0.2, fov 42, the van 10-15 away) needs less.
## MEASURED (tools/zfight_shots.tscn --calib: plates 0 .. 1 mm under a face, flat, facing the camera and turned 60
## degrees, 40 units from the origin, game camera at sizes 9, 24 and 36, 1920x1080, sub-pixel camera moves): faces 0 to
## 0.05 mm apart flicker, 0.1 mm and more never do. EPS is 0.5 mm: above the 0.43 mm worst case, 10x the measured onset.
## The decal layers of this kit are 4-16 mm apart, far outside it.

const EPS := 0.0005                   ## m: plane gap below which overlapping parallel faces fight (see the header)
const PARALLEL_DEG := 3.0             ## faces closer than this in angle are tested (the slab clip measures the real gap)
const MIN_AREA_M2 := 2.0e-6           ## 0.02 cm2: less is a touching edge or the sliver where two faces cross
const SAME_LOOK_WEIGHT := 0.15        ## same paint and material: the flicker swaps two nearly equal shades
const LABEL_WEIGHT := 0.5             ## a Label3D's quad is only partly letters
## Two faces that slant through each other (a dented panel through a flat one) are within EPS only in a band along the
## line where they cross, and only a tenth of that band (the calibration's 0.05 mm of EPS's 0.5) actually flickers; the
## rest is a still, jagged seam. Their area counts this much.
const CROSSING_WEIGHT := 0.1
const NEVER_SEEN_Y := -0.6            ## faces with normal.y below this are never seen by the cameras
const SAME_COLOR := 0.12              ## max channel difference (sRGB, lighting removed) of "the same paint"
const TOP_LIGHT := 0.22               ## LowPoly.Soup.to_mesh's baked top light, divided back out of vertex colours
const CELL := 0.25                    ## spatial hash cell (m)
const NB := 4.0                       ## normal hash bins per unit of each normal component
const SAMPLES := 6                    ## points per finding the visibility pass looks at
## Directions the cameras look from (elevation above the floor): the game camera (pitch -56) and the menu's (about 15).
const VIEW_ELEVATIONS: Array[float] = [56.0, 15.0]
const VIEW_AZIMUTHS := 16

const F_DOUBLE := 1                   ## double-sided material
const F_NODEPTH := 2                  ## does not write depth (additive, depth_draw_never, alpha-blended)
const F_GLOW := 4                     ## emissive face (MonsterMaterial vertex alpha < 0.75)
const F_LABEL := 8                    ## a Label3D quad
const F_TERRAIN := 16                 ## the floor / walls (never tested against itself)
const F_PLANE := 32                   ## add_ground()'s stand-in plane (never an occluder)


## Every visible triangle of one or more models in one space (a model's own space, or the world for compositions).
class TriSet extends RefCounted:
	var pa := PackedVector3Array()
	var pb := PackedVector3Array()
	var pc := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var flags := PackedInt32Array()
	var item := PackedInt32Array()
	var part := PackedInt32Array()
	var origin := PackedInt32Array()     ## LowPoly origin id per triangle (-1 untraced)
	var items: Array[Dictionary] = []    ## {name, terrain, aabb}
	var parts: Array[Dictionary] = []    ## {item, path, look, palette (Script or null)}
	var palettes: Array[Script] = []     ## scripts whose Color constants name the colours in reports

	var _corners := {}                   ## part -> {corner key: [triangles]} (piece flood cache)

	func count() -> int:
		return pa.size()

	static func corner_key(q: Vector3) -> Vector3i:
		return Vector3i(roundi(q.x * 10000.0), roundi(q.y * 10000.0), roundi(q.z * 10000.0))

	var _piece_ids := {}                 ## triangle -> piece number within its part (filled a part at a time)

	## The piece (a run of the part's triangles joined by shared corners: usually one box or cylinder of a soup) a
	## triangle belongs to.
	func piece_of(t: int) -> int:
		if _piece_ids.has(t):
			return int(_piece_ids[t])
		var adj := corners_of_part(part[t])
		var next := 0
		for k in count():
			if part[k] != part[t] or _piece_ids.has(k):
				continue
			var todo: Array[int] = [k]
			_piece_ids[k] = next
			while not todo.is_empty():
				var q: int = todo.pop_back()
				for c: Vector3 in [pa[q], pb[q], pc[q]]:
					for o: int in adj.get(corner_key(c), []):
						if not _piece_ids.has(o):
							_piece_ids[o] = next
							todo.append(o)
			next += 1
		return int(_piece_ids[t])

	## Corner key -> the part's triangles that have that corner (built once per part).
	func corners_of_part(p: int) -> Dictionary:
		if _corners.has(p):
			return _corners[p]
		var m := {}
		for k in count():
			if part[k] != p:
				continue
			for q: Vector3 in [pa[k], pb[k], pc[k]]:
				var key := corner_key(q)
				var arr: Variant = m.get(key)
				if arr == null:
					m[key] = [k]
				else:
					(arr as Array).append(k)
		_corners[p] = m
		return m

	func add_item(item_name: String, terrain: bool = false) -> int:
		items.append({"name": item_name, "terrain": terrain})
		return items.size() - 1

	## Every visible triangle under `node` (itself included), placed by `xf` (node space -> set space).
	func add_node(node: Node, item_id: int, xf: Transform3D = Transform3D.IDENTITY, path: String = "") -> void:
		if node is Node3D and not (node as Node3D).visible:
			return
		var here := path + ("/" if path != "" else "") + String(node.name)
		var sc := node.get_script() as Script
		if sc != null and not palettes.has(sc):
			palettes.append(sc)
		if node is MeshInstance3D:
			_add_mesh(node as MeshInstance3D, item_id, xf, here)
		elif node is Label3D:
			_add_label(node as Label3D, item_id, xf, here)
		for ch in node.get_children():
			if ch is Node3D:
				add_node(ch, item_id, xf * (ch as Node3D).transform, here)
			else:
				add_node(ch, item_id, xf, here)

	## The floor top: an upward quad at height y under everything added so far (the hex tops; HexMapView draws them at
	## level * LEVEL_HEIGHT). Call it after the models.
	func add_ground(y: float = 0.0, margin: float = 0.5) -> void:
		var lo := Vector2(-margin, -margin)
		var hi := Vector2(margin, margin)
		for i in count():
			for q: Vector3 in [pa[i], pb[i], pc[i]]:
				lo = Vector2(minf(lo.x, q.x - margin), minf(lo.y, q.z - margin))
				hi = Vector2(maxf(hi.x, q.x + margin), maxf(hi.y, q.z + margin))
		var it := add_item("floor", true)
		parts.append({"item": it, "path": "hex floor top (y = %.3f)" % y, "look": "terrain"})
		var p := parts.size() - 1
		var c := Color(0.30, 0.32, 0.36)
		var a := Vector3(lo.x, y, lo.y)
		var b := Vector3(hi.x, y, lo.y)
		var cc := Vector3(hi.x, y, hi.y)
		var d := Vector3(lo.x, y, hi.y)
		_tri(a, d, cc, c, F_TERRAIN | F_PLANE, it, p, -1)
		_tri(a, cc, b, c, F_TERRAIN | F_PLANE, it, p, -1)

	func _add_mesh(mi: MeshInstance3D, item_id: int, xf: Transform3D, path: String) -> void:
		var mesh := mi.mesh
		if mesh == null:
			return
		var origins: PackedInt32Array = mesh.get_meta(LowPoly.ORIGIN_META, PackedInt32Array())
		var tri_base := 0
		for s in mesh.get_surface_count():
			if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat: Material = mi.material_override
			if mat == null:
				mat = mi.get_surface_override_material(s)
			if mat == null:
				mat = mesh.surface_get_material(s)
			var info := ZFightCheck.material_info(mat)
			if bool(info["skip"]):
				continue
			var arrays := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var vc: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var vn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var use_vc := not vc.is_empty() and bool(info["vertex_color"])
			parts.append({"item": item_id, "path": "%s#%d" % [path, s] if mesh.get_surface_count() > 1 else path, "look": info["look"]})
			var p := parts.size() - 1
			var tcount := (idx.size() if not idx.is_empty() else v.size()) / 3
			for t in tcount:
				var i0 := idx[t * 3] if not idx.is_empty() else t * 3
				var i1 := idx[t * 3 + 1] if not idx.is_empty() else t * 3 + 1
				var i2 := idx[t * 3 + 2] if not idx.is_empty() else t * 3 + 2
				var c: Color = info["albedo"]
				var fl := int(info["flags"])
				if use_vc:
					var lin := vc[i0]
					c = Color(lin.r, lin.g, lin.b).linear_to_srgb()
					if bool(info["glow_alpha"]) and lin.a < 0.75:
						fl |= F_GLOW
				var o := origins[tri_base + t] if tri_base + t < origins.size() else -1
				# Godot front faces are clockwise: the outward normal is (c - a) x (b - a); the mesh's own normals settle it
				var hint := Vector3.ZERO
				if not vn.is_empty():
					hint = xf.basis * (vn[i0] + vn[i1] + vn[i2])
				_tri(xf * v[i0], xf * v[i2], xf * v[i1], c, fl, item_id, p, o, use_vc, hint)
			tri_base += tcount

	func _add_label(l: Label3D, item_id: int, xf: Transform3D, path: String) -> void:
		if l.no_depth_test or l.billboard != BaseMaterial3D.BILLBOARD_DISABLED or l.text.strip_edges() == "":
			return
		var bb := l.get_aabb()
		if bb.size.x <= 0.0 or bb.size.y <= 0.0:
			return
		var fl := F_LABEL
		if l.double_sided:
			fl |= F_DOUBLE
		if l.alpha_cut == Label3D.ALPHA_CUT_DISABLED:
			fl |= F_NODEPTH
		parts.append({"item": item_id, "path": "%s (Label3D \"%s\")" % [path, l.text.replace("\n", " ")], "look": "label"})
		var p := parts.size() - 1
		var z := bb.position.z + bb.size.z * 0.5
		var a := xf * Vector3(bb.position.x, bb.position.y, z)
		var b := xf * Vector3(bb.end.x, bb.position.y, z)
		var c := xf * Vector3(bb.end.x, bb.end.y, z)
		var d := xf * Vector3(bb.position.x, bb.end.y, z)
		_tri(a, b, c, l.modulate, fl, item_id, p, -1)
		_tri(a, c, d, l.modulate, fl, item_id, p, -1)

	## One triangle, front face counter-clockwise (normal = (b - a) x (c - a)). Lit vertex colours get the baked top
	## light divided back out so two faces of one paint compare equal.
	func _tri(a: Vector3, b: Vector3, c: Vector3, colour: Color, fl: int, item_id: int, p: int, o: int, unlight: bool = false, hint: Vector3 = Vector3.ZERO) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-14:
			return
		n = n.normalized()
		if bool(items[item_id]["terrain"]):
			fl |= F_TERRAIN
		if n.dot(hint) < 0.0:
			n = -n
			var t := b
			b = c
			c = t
		if n.y < ZFightCheck.NEVER_SEEN_Y and (fl & F_DOUBLE) == 0:
			return
		if unlight:
			var k := 1.0 + ZFightCheck.TOP_LIGHT * clampf(n.y, -1.0, 1.0)
			colour = Color(colour.r / k, colour.g / k, colour.b / k)
		pa.append(a)
		pb.append(b)
		pc.append(c)
		nrm.append(n)
		col.append(colour)
		flags.append(fl)
		item.append(item_id)
		part.append(p)
		origin.append(o)

	## Keep only the terrain triangles near a non-terrain triangle (a whole floor's terrain is big; models are small).
	func trim_terrain(margin: float = 0.3) -> void:
		var cells := {}
		for i in count():
			if flags[i] & F_TERRAIN:
				continue
			var lo := _min3(pa[i], pb[i], pc[i]) - Vector3.ONE * margin
			var hi := _max3(pa[i], pb[i], pc[i]) + Vector3.ONE * margin
			for x in range(floori(lo.x), floori(hi.x) + 1):
				for z in range(floori(lo.z), floori(hi.z) + 1):
					cells[Vector2i(x, z)] = true
		var keep := PackedInt32Array()
		for i in count():
			if not (flags[i] & F_TERRAIN):
				keep.append(i)
				continue
			var lo := _min3(pa[i], pb[i], pc[i])
			var hi := _max3(pa[i], pb[i], pc[i])
			var near := false
			for x in range(floori(lo.x), floori(hi.x) + 1):
				for z in range(floori(lo.z), floori(hi.z) + 1):
					if cells.has(Vector2i(x, z)):
						near = true
						break
				if near:
					break
			if near:
				keep.append(i)
		_keep(keep)

	func _keep(keep: PackedInt32Array) -> void:
		var arrs := [pa, pb, pc, nrm, col, flags, item, part, origin]
		var out := []
		for arr in arrs:
			var o2: Variant = arr.duplicate()
			o2.resize(keep.size())
			for k in keep.size():
				o2[k] = arr[keep[k]]
			out.append(o2)
		pa = out[0]
		pb = out[1]
		pc = out[2]
		nrm = out[3]
		col = out[4]
		flags = out[5]
		item = out[6]
		part = out[7]
		origin = out[8]

	static func _min3(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
		return Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z)))

	static func _max3(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
		return Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z)))

	## The fights in this set that a camera can see, worst first (see ZFightCheck.describe). `cross_only`: only pairs
	## from two different items (a composition whose items were each checked on their own already).
	func find(cross_only: bool = false) -> Array[Dictionary]:
		var found := ZFightCheck.find_in(self, cross_only)
		ZFightCheck.apply_visibility(self, found)
		return found

	# ------------------------------------------------------------------ rays (the visibility pass)

	var _grid := {}                      ## cell -> [occluder triangles]
	var _grid_bb := AABB()
	var _stamp := PackedInt32Array()
	var _ray_id := 0

	## Faces that hide what is behind them from a camera: depth-writing, not the stand-in floor plane.
	func _build_grid() -> void:
		_grid = {}
		_stamp.resize(count())
		_stamp.fill(0)
		var first := true
		for i in count():
			if flags[i] & (F_NODEPTH | F_PLANE | F_LABEL):
				continue
			var lo := _min3(pa[i], pb[i], pc[i])
			var hi := _max3(pa[i], pb[i], pc[i])
			if first:
				_grid_bb = AABB(lo, hi - lo)
				first = false
			else:
				_grid_bb = _grid_bb.merge(AABB(lo, hi - lo))
			var c0 := _cell(lo)
			var c1 := _cell(hi)
			for x in range(c0.x, c1.x + 1):
				for y in range(c0.y, c1.y + 1):
					for z in range(c0.z, c1.z + 1):
						var k := Vector3i(x, y, z)
						var arr: Variant = _grid.get(k)
						if arr == null:
							_grid[k] = [i]
						else:
							(arr as Array).append(i)

	static func _cell(p: Vector3) -> Vector3i:
		return Vector3i(floori(p.x / ZFightCheck.CELL), floori(p.y / ZFightCheck.CELL), floori(p.z / ZFightCheck.CELL))

	## True when a face drawn toward a camera looking back along `d` covers `o` (a 3D DDA through the grid).
	func ray_blocked(o: Vector3, d: Vector3) -> bool:
		if _grid.is_empty():
			return false
		_ray_id += 1
		var bb := _grid_bb.grow(0.01)
		var t_end := INF
		for k in 3:
			if d[k] > 1e-9:
				t_end = minf(t_end, (bb.end[k] - o[k]) / d[k])
			elif d[k] < -1e-9:
				t_end = minf(t_end, (bb.position[k] - o[k]) / d[k])
		if t_end <= 0.0:
			return false
		var c := ZFightCheck.CELL
		var cell := _cell(o)
		var step := Vector3i(int(signf(d.x)), int(signf(d.y)), int(signf(d.z)))
		var t_max := Vector3.ZERO
		var t_delta := Vector3.ZERO
		for k in 3:
			if absf(d[k]) < 1e-9:
				t_max[k] = INF
				t_delta[k] = INF
			else:
				var edge := float(cell[k] + (1 if d[k] > 0.0 else 0)) * c
				t_max[k] = (edge - o[k]) / d[k]
				t_delta[k] = c / absf(d[k])
		var t := 0.0
		while t <= t_end:
			var arr: Variant = _grid.get(cell)
			if arr != null:
				for i: int in arr:
					if _stamp[i] == _ray_id:
						continue
					_stamp[i] = _ray_id
					if nrm[i].dot(d) <= 0.0 and not (flags[i] & F_DOUBLE):
						continue   # faces away from that camera: culled, hides nothing
					var hit: Variant = Geometry3D.ray_intersects_triangle(o, d, pa[i], pb[i], pc[i])
					if hit != null and ((hit as Vector3) - o).dot(d) > 1e-4:
						return true
			if t_max.x < t_max.y and t_max.x < t_max.z:
				cell.x += step.x
				t = t_max.x
				t_max.x += t_delta.x
			elif t_max.y < t_max.z:
				cell.y += step.y
				t = t_max.y
				t_max.y += t_delta.y
			else:
				cell.z += step.z
				t = t_max.z
				t_max.z += t_delta.z
		return false


## Material facts that matter for depth: {flags (F_DOUBLE, F_NODEPTH), skip (never depth-tested), look (a key: two faces
## with the same key and paint look alike), albedo, vertex_color (vertex COLOR is the albedo), glow_alpha}.
static func material_info(mat: Material) -> Dictionary:
	var out := {"flags": 0, "skip": false, "look": "default", "albedo": Color(0.8, 0.8, 0.8), "vertex_color": false, "glow_alpha": false}
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		var code := sm.shader.code if sm.shader != null else ""
		var mode := ""
		for line in code.split("\n"):
			if line.strip_edges().begins_with("render_mode"):
				mode = line
				break
		if mode.contains("cull_disabled"):
			out["flags"] = int(out["flags"]) | F_DOUBLE
		if mode.contains("depth_draw_never") or mode.contains("blend_add"):
			out["flags"] = int(out["flags"]) | F_NODEPTH
		out["skip"] = mode.contains("depth_test_disabled")
		out["look"] = "shader#%d" % (sm.shader.get_instance_id() if sm.shader != null else 0)
		out["vertex_color"] = code.contains("COLOR.rgb")
		out["glow_alpha"] = code.contains("glow_m")
		var alb: Variant = sm.get_shader_parameter("albedo")
		if alb is Color:
			out["albedo"] = alb
	elif mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		if bm.cull_mode == BaseMaterial3D.CULL_DISABLED:
			out["flags"] = int(out["flags"]) | F_DOUBLE
		if bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA or bm.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED \
				or bm.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
			out["flags"] = int(out["flags"]) | F_NODEPTH
		out["skip"] = bm.no_depth_test
		out["look"] = "std:%s" % bm.albedo_color.to_html()
		out["albedo"] = bm.albedo_color
		out["vertex_color"] = bm.vertex_color_use_as_albedo
	return out


static func find_in(ts: TriSet, cross_only: bool) -> Array[Dictionary]:
	var cos_par := cos(deg_to_rad(PARALLEL_DEG))
	var margin := sin(deg_to_rad(PARALLEL_DEG)) * 1.2 * NB
	var buckets := {}
	var cell0 := PackedInt32Array()        # each triangle's lowest hash cell (x, y, z): a pair is judged in one cell only
	cell0.resize(ts.count() * 3)
	for i in ts.count():
		# normal bins (a face near a bin's edge goes in both); a double-sided face also goes in its back's bins, so
		# opposite faces meet only when one of them is double-sided
		var nks: Array[int] = []
		var dirs: Array[Vector3] = [ts.nrm[i]]
		if ts.flags[i] & F_DOUBLE:
			dirs.append(-ts.nrm[i])
		for n in dirs:
			var bins: Array = []
			for k in 3:
				var f := (n[k] + 1.0) * NB
				var b0 := floori(f)
				var opts: Array[int] = [b0]
				if f - float(b0) < margin:
					opts.append(b0 - 1)
				elif float(b0) + 1.0 - f < margin:
					opts.append(b0 + 1)
				bins.append(opts)
			for bx: int in bins[0]:
				for by: int in bins[1]:
					for bz: int in bins[2]:
						nks.append((bx + 1) | ((by + 1) << 5) | ((bz + 1) << 10))
		var lo := TriSet._min3(ts.pa[i], ts.pb[i], ts.pc[i]) - Vector3.ONE * EPS
		var hi := TriSet._max3(ts.pa[i], ts.pb[i], ts.pc[i]) + Vector3.ONE * EPS
		var c0 := Vector3i(floori(lo.x / CELL), floori(lo.y / CELL), floori(lo.z / CELL))
		var c1 := Vector3i(floori(hi.x / CELL), floori(hi.y / CELL), floori(hi.z / CELL))
		cell0[i * 3] = c0.x
		cell0[i * 3 + 1] = c0.y
		cell0[i * 3 + 2] = c0.z
		for nk in nks:
			for x in range(c0.x, c1.x + 1):
				for y in range(c0.y, c1.y + 1):
					for z in range(c0.z, c1.z + 1):
						var key := nk | ((x + 1024) << 15) | ((y + 1024) << 27) | ((z + 1024) << 39)
						var arr: Variant = buckets.get(key)
						if arr == null:
							buckets[key] = [i]
						else:
							(arr as Array).append(i)
	var seen := {}
	var total := ts.count()
	var groups := {}
	# packed arrays in locals: GDScript reads them much faster than through `ts.`
	var flags := ts.flags
	var item := ts.item
	var nrm := ts.nrm
	var pa := ts.pa
	var pb := ts.pb
	var pc := ts.pc
	for key: int in buckets:
		var arr: Array = buckets[key]
		var m := arr.size()
		if m < 2:
			continue
		var kx := ((key >> 15) & 4095) - 1024
		var ky := ((key >> 27) & 4095) - 1024
		var kz := ((key >> 39) & 4095) - 1024
		for x in m:
			var i: int = arr[x]
			for y in range(x + 1, m):
				var j: int = arr[y]
				# two triangles share every cell of their boxes' overlap: judge the pair in the lowest one only
				if (kx != maxi(cell0[i * 3], cell0[j * 3]) or ky != maxi(cell0[i * 3 + 1], cell0[j * 3 + 1])
						or kz != maxi(cell0[i * 3 + 2], cell0[j * 3 + 2])):
					continue
				var fi := flags[i]
				var fj := flags[j]
				if (fi & F_TERRAIN) and (fj & F_TERRAIN):
					continue
				if cross_only and item[i] == item[j]:
					continue
				if (fi & F_NODEPTH) and (fj & F_NODEPTH):
					continue
				var d := nrm[i].dot(nrm[j])
				if absf(d) < cos_par:
					continue
				if d < 0.0 and not ((fi | fj) & F_DOUBLE):
					continue
				# cheap first: all of j on one side of i's plane, farther than EPS, or boxes apart
				var ni := nrm[i]
				var ai := pa[i]
				var s0 := ni.dot(pa[j] - ai)
				var s1 := ni.dot(pb[j] - ai)
				var s2 := ni.dot(pc[j] - ai)
				if (s0 > EPS and s1 > EPS and s2 > EPS) or (s0 < -EPS and s1 < -EPS and s2 < -EPS):
					continue
				if not _boxes_touch(ts, i, j):
					continue
				var pk := mini(i, j) * total + maxi(i, j)
				if seen.has(pk):
					continue
				seen[pk] = true
				var ov := overlap(ts, i, j)
				if ov.x <= 0.0:
					continue
				_add_to_group(ts, groups, i, j, ov)
	var out: Array[Dictionary] = []
	for g: Dictionary in groups.values():
		if float(g["area"]) >= MIN_AREA_M2:
			_finish_group(ts, g)
			out.append(g)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["severity"]) > float(b["severity"]))
	return out


## Which findings a camera can see: from each sample point of a finding, rays toward the game camera (56 degrees up)
## and the menu camera (15) at VIEW_AZIMUTHS headings (models stand at any yaw). A ray is blocked by a face that would
## be drawn over the point (it faces that camera and writes depth). f["visible"] = the fraction of samples with a clear
## ray; f["shown_cm2"] = severity * visible, the number findings are ranked and judged by.
static func apply_visibility(ts: TriSet, found: Array[Dictionary]) -> void:
	# (findings below visibility_floor_cm2 keep visible = 1: a test that only judges bigger ones skips their rays)
	if found.is_empty():
		return
	ts._build_grid()
	var dirs: Array[Vector3] = []
	for el: float in VIEW_ELEVATIONS:
		var e := deg_to_rad(el)
		for k in VIEW_AZIMUTHS:
			var az := TAU * float(k) / float(VIEW_AZIMUTHS)
			dirs.append(Vector3(cos(e) * cos(az), sin(e), cos(e) * sin(az)))
	for f in found:
		if float(f["severity_cm2"]) < visibility_floor_cm2:
			continue   # can never reach the caller's threshold: left at 100 % (an upper bound)
		var n: Vector3 = f["normal"]
		var sides: Array[Vector3] = [n]
		if bool(f["piece_a"]["double"]) or bool(f["piece_b"]["double"]):
			sides.append(-n)
		var samples: Array = f["samples"]
		var seen := 0
		for p: Vector3 in samples:
			var clear := false
			for side in sides:
				for d in dirs:
					if side.dot(d) < 0.05:
						continue
					if not ts.ray_blocked(p + side * EPS * 2.0, d):
						clear = true
						break
				if clear:
					break
			if clear:
				seen += 1
		f["visible"] = float(seen) / float(maxi(samples.size(), 1))
		f["shown_cm2"] = float(f["severity_cm2"]) * float(f["visible"])
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["shown_cm2"]) > float(b["shown_cm2"]))


## Findings with less severity than this skip the visibility pass (tests/test_zfight.gd sets its threshold; 0 = all).
static var visibility_floor_cm2 := 0.0
static var _last_mid := Vector3.ZERO


static func _boxes_touch(ts: TriSet, i: int, j: int) -> bool:
	var a := ts.pa[i]
	var b := ts.pb[i]
	var c := ts.pc[i]
	var p := ts.pa[j]
	var q := ts.pb[j]
	var r := ts.pc[j]
	for k in 3:
		if maxf(a[k], maxf(b[k], c[k])) + EPS < minf(p[k], minf(q[k], r[k])):
			return false
		if maxf(p[k], maxf(q[k], r[k])) + EPS < minf(a[k], minf(b[k], c[k])):
			return false
	return true
static var _last_cross := false          ## overlap(): the faces slant through each other (not within EPS all over)    ## overlap(): the middle of the last fighting patch (set space)


## Area (m2) of the part of triangle j that lies within EPS of triangle i's plane, over triangle i (x), and the mean
## gap over it (y). Zero when they only touch along an edge.
static func overlap(ts: TriSet, i: int, j: int) -> Vector2:
	var n := ts.nrm[i]
	var a0 := ts.pa[i]
	var e1 := ts.pb[i] - a0
	var u := e1.normalized()
	var v := n.cross(u)
	var e2 := ts.pc[i] - a0
	var A: Array[Vector2] = [Vector2.ZERO, Vector2(e1.dot(u), e1.dot(v)), Vector2(e2.dot(u), e2.dot(v))]
	var poly: Array[Vector3] = []
	var smin := INF
	var smax := -INF
	for p: Vector3 in [ts.pa[j], ts.pb[j], ts.pc[j]]:
		var dp := p - a0
		var s := dp.dot(n)
		smin = minf(smin, s)
		smax = maxf(smax, s)
		poly.append(Vector3(dp.dot(u), dp.dot(v), s))
	if smin > EPS or smax < -EPS:
		return Vector2.ZERO
	var orient := signf((A[1] - A[0]).cross(A[2] - A[0]))
	for e in 3:
		var p0 := A[e]
		var ed := A[(e + 1) % 3] - p0
		var inward := Vector2(-ed.y, ed.x) * orient
		poly = _clip(poly, Vector3(inward.x, inward.y, 0.0), inward.dot(p0))
		if poly.size() < 3:
			return Vector2.ZERO
	var reach := 0.0
	for p in poly:
		reach = maxf(reach, absf(p.z))
	_last_cross = reach > EPS
	poly = _clip(poly, Vector3(0, 0, -1), -EPS)      # s <= EPS
	if poly.size() < 3:
		return Vector2.ZERO
	poly = _clip(poly, Vector3(0, 0, 1), -EPS)       # s >= -EPS
	if poly.size() < 3:
		return Vector2.ZERO
	var area := 0.0
	var gap := 0.0
	var mid := Vector3.ZERO
	for k in poly.size():
		var p := poly[k]
		var q := poly[(k + 1) % poly.size()]
		area += p.x * q.y - q.x * p.y
		gap += absf(p.z)
		mid += p
	mid /= float(poly.size())
	_last_mid = a0 + u * mid.x + v * mid.y + n * mid.z
	return Vector2(absf(area) * 0.5, gap / float(poly.size()))


## Sutherland-Hodgman: keep the part of `poly` where dir . p >= c (z carries the plane gap, interpolated).
static func _clip(poly: Array[Vector3], dir: Vector3, c: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := poly.size()
	for k in n:
		var p := poly[k]
		var q := poly[(k + 1) % n]
		var dp := dir.dot(p) - c
		var dq := dir.dot(q) - c
		if dp >= 0.0:
			out.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			out.append(p + (q - p) * (dp / (dp - dq)))
	return out


# --------------------------------------------------------------------------- grouping into pieces

static func _add_to_group(ts: TriSet, groups: Dictionary, i: int, j: int, ov: Vector2) -> void:
	var a := i
	var b := j
	var pa_id := ts.piece_of(a)
	var pb_id := ts.piece_of(b)
	if ts.part[a] > ts.part[b] or (ts.part[a] == ts.part[b] and pa_id > pb_id):
		a = j
		b = i
	var nn := ts.nrm[i]
	var plane := Vector3i(roundi(nn.x * 20.0), roundi(nn.y * 20.0), roundi(nn.z * 20.0))
	var dist := roundi(nn.dot(ts.pa[i]) / 0.02)
	# a group: the two pieces (connected bits of a part) and the shared plane, the same whether or not LowPoly.trace is on
	var key := "%d|%d|%d|%d|%s|%d" % [ts.part[a], ts.part[b], ts.piece_of(a), ts.piece_of(b), plane, dist]
	var same := _same_look(ts, i, j)
	var w := SAME_LOOK_WEIGHT if same else 1.0
	if (ts.flags[i] | ts.flags[j]) & F_LABEL:
		w *= LABEL_WEIGHT
	if _last_cross:
		w *= CROSSING_WEIGHT
	var cen := _last_mid
	var g: Dictionary = groups.get(key, {})
	if g.is_empty():
		g = {"tris_a": {}, "tris_b": {}, "area": 0.0, "severity": 0.0, "gap_sum": 0.0, "cen_sum": Vector3.ZERO,
				"normal": ts.nrm[a], "a": a, "b": b, "same_look": true, "crossing": false, "pairs": 0, "samples": [], "sample_area": []}
		groups[key] = g
	# keep the middles of the biggest fighting patches: the points the visibility pass looks at
	var samples: Array = g["samples"]
	var sarea: Array = g["sample_area"]
	if samples.size() < SAMPLES:
		samples.append(_last_mid)
		sarea.append(ov.x)
	else:
		var low := 0
		for k in sarea.size():
			if float(sarea[k]) < float(sarea[low]):
				low = k
		if ov.x > float(sarea[low]):
			samples[low] = _last_mid
			sarea[low] = ov.x
	(g["tris_a"] as Dictionary)[a] = true
	(g["tris_b"] as Dictionary)[b] = true
	g["area"] = float(g["area"]) + ov.x
	g["severity"] = float(g["severity"]) + ov.x * w
	g["gap_sum"] = float(g["gap_sum"]) + ov.y * ov.x
	g["cen_sum"] = (g["cen_sum"] as Vector3) + cen * ov.x
	g["same_look"] = bool(g["same_look"]) and same
	g["crossing"] = bool(g["crossing"]) or _last_cross
	g["pairs"] = int(g["pairs"]) + 1


static func _same_look(ts: TriSet, i: int, j: int) -> bool:
	if String(ts.parts[ts.part[i]]["look"]) != String(ts.parts[ts.part[j]]["look"]):
		return false
	if (ts.flags[i] & F_GLOW) != (ts.flags[j] & F_GLOW):
		return false
	var a := ts.col[i]
	var b := ts.col[j]
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) <= SAME_COLOR


static func _finish_group(ts: TriSet, g: Dictionary) -> void:
	var area := float(g["area"])
	g["center"] = (g["cen_sum"] as Vector3) / area
	g["gap"] = float(g["gap_sum"]) / area
	g["area_cm2"] = area * 10000.0
	g["severity_cm2"] = float(g["severity"]) * 10000.0
	g["piece_a"] = _piece(ts, int(g["a"]), (g["tris_a"] as Dictionary).keys())
	g["piece_b"] = _piece(ts, int(g["b"]), (g["tris_b"] as Dictionary).keys())
	g["item_a"] = String(ts.items[ts.item[int(g["a"])]]["name"])
	g["item_b"] = String(ts.items[ts.item[int(g["b"])]]["name"])
	g["visible"] = 1.0
	g["shown_cm2"] = g["severity_cm2"]
	g.erase("tris_a")
	g.erase("tris_b")
	g.erase("cen_sum")
	g.erase("gap_sum")
	g.erase("sample_area")


## What a side of a finding is: the part (node path), the code that made it (traced builds), the extent of the
## fighting triangles' piece (every triangle of the part connected to them through shared corners) and its paint.
static func _piece(ts: TriSet, t: int, tris: Array) -> Dictionary:
	var p := ts.part[t]
	var flag := ts.flags[t]
	var adj := ts.corners_of_part(p)
	var picked := {}
	var todo: Array = tris.duplicate()
	for k: int in tris:
		picked[k] = true
	while not todo.is_empty() and picked.size() < 6000:
		var k: int = todo.pop_back()
		for q: Vector3 in [ts.pa[k], ts.pb[k], ts.pc[k]]:
			for o: int in adj.get(TriSet.corner_key(q), []):
				if not picked.has(o):
					picked[o] = true
					todo.append(o)
	var members: Array[int] = []
	var bb := AABB(ts.pa[tris[0]], Vector3.ZERO)
	for k: int in picked.keys():
		members.append(k)
		bb = bb.expand(ts.pa[k]).expand(ts.pb[k]).expand(ts.pc[k])
	var origins := {}
	for k: int in tris:
		origins[ts.origin[k]] = int(origins.get(ts.origin[k], 0)) + 1
	var best := -1
	var best_n := -1
	for o: int in origins:
		if int(origins[o]) > best_n:
			best_n = int(origins[o])
			best = o
	return {"item": String(ts.items[ts.item[t]]["name"]), "path": String(ts.parts[p]["path"]), "aabb": bb,
			"color": ts.col[t], "color_name": color_name(ts, ts.col[t]), "origin": LowPoly.origin_name(best) if best >= 0 else "",
			"glow": (flag & F_GLOW) != 0, "label": (flag & F_LABEL) != 0, "terrain": (flag & F_TERRAIN) != 0,
			"nodepth": (flag & F_NODEPTH) != 0, "double": (flag & F_DOUBLE) != 0}


## The nearest Color constant of the scripts that built the set ("STRIPE"), or the colour's hex.
static func color_name(ts: TriSet, c: Color) -> String:
	var best := ""
	var best_d := 0.09
	for sc: Script in ts.palettes:
		var consts := sc.get_script_constant_map()
		for k: String in consts:
			var v: Variant = consts[k]
			if v is Color:
				var cc := v as Color
				var d := maxf(absf(cc.r - c.r), maxf(absf(cc.g - c.g), absf(cc.b - c.b)))
				if d < best_d:
					best_d = d
					best = k
	return best if best != "" else "#" + c.to_html(false)


## Three lines per finding: shown severity (cm2: overlap, weighted by look, times the visible fraction), the overlap,
## how much of it a camera sees, the gap, where; then both pieces.
static func describe(f: Dictionary) -> String:
	var s := "%7.2f cm2 shown | %7.2f cm2 overlap | %3d%% visible | gap %.2f mm | %sat %s n %s\n" % [float(f["shown_cm2"]),
			float(f["area_cm2"]), roundi(float(f["visible"]) * 100.0), float(f["gap"]) * 1000.0,
			("same look | " if bool(f["same_look"]) else "") + ("crossing | " if bool(f["crossing"]) else ""), _v(f["center"]), _v(f["normal"])]
	s += "      A: " + describe_piece(f["piece_a"]) + "\n"
	s += "      B: " + describe_piece(f["piece_b"])
	return s


static func describe_piece(pc: Dictionary) -> String:
	var bb: AABB = pc["aabb"]
	var tags := ""
	for t: String in ["glow", "label", "terrain", "nodepth", "double"]:
		if bool(pc[t]):
			tags += " [%s]" % t
	var s := "%s %s %s piece %s at %s%s" % [pc["item"], pc["path"], pc["color_name"], _v(bb.size), _v(bb.get_center()), tags]
	if String(pc["origin"]) != "":
		s += "  <- " + String(pc["origin"])
	return s


static func _v(p: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [p.x, p.y, p.z]
