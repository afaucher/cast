class_name HexDoorModel
extends Node3D
## The look of an office door that belongs to the hex world (OfficeDoor; docs/design/exploration.md "Fog and doors as
## built"), in three STYLES, all on the grid of a narrow doorway (Doorways' door place: the doorway cell, the BAND of it and
## the two cut cells beside it, the hex EDGES between the band and the room). Built by the terrain's own mesher
## (HexMapView: the same inset tops, bevels, amber seams, wall material from FloorMaterials and wall height), so a shut door
## reads as a piece of the hex-height terrain.
##   column  the band is a raised block of hex columns (the cut cells' floor halves too), wall high, a bright amber seam
##           round each top. Opens by SINKING into the floor (a low lip with its seam stays: the doorway is marked);
##           shuts by rising. Smashed: hex rubble.
##   edge    a wall piece standing on the band's room-side hex EDGES (the zigzag the cells make), wall thick and high, a
##           seam along its top, glowing jambs where it meets the corridor walls. Opens by sliding DOWN into a floor slot
##           (its seamed top stays flush as a threshold). Smashed: it topples flat.
##   iris    the doorway cell is a shutter of six triangular leaves (the hex's six triangles) with amber seams between
##           them; the cut cells beside it are fixed jambs. Opens radially: each leaf draws back to the rim and down to a
##           low curb. Smashed: the leaves are flung about as hex rubble.
## Origin: the doorway cell's centre on its floor. World-aligned (no rotation). Pure presentation (LOCAL).

const STYLES: Array[String] = ["column", "edge", "iris"]
const LH := Hex.LEVEL_HEIGHT
const LIP := 0.045               ## an open column / slid edge door keeps this much above the floor
const EDGE_T := 0.28             ## the edge door's thickness
const LEAF_GAP := 0.035          ## the seam between two iris leaves
const SEAM_GAIN := 0.95          ## the door seams glow like floor seams (a wall's are 0.2): it says "door"
const DOOR_TINT := Color(1.0, 0.82, 0.6)   ## a warm brass cast over the wall material: a door, not a wall
const BAND := 0.16               ## the glowing band under a door's top edge ...
const BAND_GLOW := 0.55          ## ... and how bright

var style := "column"
var open_k := 0.0
var broken := false
var height := 1.5                ## wall height above the floor
var mat_index := 0               ## the shader's wall material (FloorMaterials) of the corridor

var _moving: Node3D = null       ## column / edge: the part that sinks
var _leaves: Array[Node3D] = []  ## iris: one pivot per leaf (on its rim edge, +Z pointing in)
var _core: MeshInstance3D = null
var _band: Array[Vector3] = []   ## local centres of the band cells
var _rubble: Node3D = null


## Who may write each var (see Net). All of it is presentation.
func net_fields() -> Dictionary:
	return {
		"style": Net.LOCAL, "open_k": Net.LOCAL, "broken": Net.LOCAL, "height": Net.LOCAL, "mat_index": Net.LOCAL,
		"_moving": Net.LOCAL, "_leaves": Net.LOCAL, "_core": Net.LOCAL, "_band": Net.LOCAL, "_rubble": Net.LOCAL,
	}


## A door on a small hand-built narrow corridor (the z-fight scan, ZFightModels): `k` open, or smashed.
static func sample(door_style: String, k: float, smashed: bool) -> Node3D:
	var m := HexMap.new()
	var cells := {}
	for c in Hex.range_cells(Vector2i(0, 0), 3):
		cells[c] = "room:0"
	for c in Hex.range_cells(Vector2i(14, 0), 3):
		cells[c] = "room:1"
	for q in range(3, 12):
		for r in range(-1, 2):
			if not cells.has(Vector2i(q, r)):
				cells[Vector2i(q, r)] = "corridor"
	for c: Vector2i in cells:
		m.set_cell(c, 0).tag = cells[c]
	for c: Vector2i in cells.keys():
		for d in Hex.DIRS:
			if not cells.has(c + d):
				m.set_cell(c + d, 3, HexMap.Tile.WALL)
	m.cut_walls()
	var model := HexDoorModel.new()
	for dw in Doorways.find(m):
		if bool(dw["door_ok"]):
			model.setup(m, dw, door_style)
			break
	model.set_open(k)
	if smashed:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		model.show_broken(Vector3.RIGHT, rng)
	return model


## Build for doorway `dw` (Doorways: door_ok) of `map`.
func setup(map: HexMap, dw: Dictionary, door_style: String) -> void:
	style = door_style
	name = "HexDoor_" + style
	var center: Vector3 = dw["center"]
	var band: Array = dw["band"]
	var cell: HexMap.Cell = map.get_cell(band[0])
	var tops := 0
	for c: Vector2i in band:
		var bc: HexMap.Cell = map.get_cell(c)
		if bc.wall_mask != 0:
			tops = maxi(tops, bc.wall_top)
			mat_index = HexMapView._wall_mat(bc)
	height = maxf(1.0, float(tops - cell.level) * LH) if tops > 0 else 1.5
	var cells: Array = []   # [local centre, open kites mask]
	for c: Vector2i in band:
		var bc: HexMap.Cell = map.get_cell(c)
		var lc := Hex.to_world(c) - Vector3(center.x, 0.0, center.z)
		lc.y = 0.0
		_band.append(lc)
		cells.append([lc, HexMap.ALL_KITES & ~bc.wall_mask])
	var edges: Array = []
	for e: Array in dw["edges"]:
		var p: Vector2 = e[0]
		var q: Vector2 = e[1]
		edges.append([Vector3(p.x - center.x, 0.0, p.y - center.z), Vector3(q.x - center.x, 0.0, q.y - center.z)])
	match style:
		"column":
			_build_column(cells)
		"edge":
			_build_edge(edges)
		_:
			_build_iris(cells)
	set_open(open_k)


func set_open(k: float) -> void:
	open_k = clampf(k, 0.0, 1.0)
	if broken:
		return
	var e := open_k * open_k * (3.0 - 2.0 * open_k)
	match style:
		"column", "edge":
			if _moving != null:
				_moving.position.y = -(height - LIP) * e
		"iris":
			for leaf in _leaves:
				leaf.scale = Vector3(1.0, lerpf(1.0, 0.07, e), lerpf(1.0, 0.16, e))
			if _core != null:
				_core.scale = Vector3(1.0, maxf(0.001, 1.0 - e), 1.0)
				_core.visible = e < 0.98


## The door is smashed: rubble on the band, the leaves or the wall piece knocked flat away from `away` (local X/Z).
func show_broken(away: Vector3, rng: RandomNumberGenerator) -> void:
	if broken:
		return
	broken = true
	away.y = 0.0
	away = away.normalized() if away.length() > 0.001 else Vector3.FORWARD
	match style:
		"edge":
			if _moving != null:
				# the wall piece falls flat, its foot on the room side line, toward `away`
				var axis := away.cross(Vector3.UP).normalized()   # (a rotation about it tips +Y toward `away`)
				_moving.basis = Basis(axis, deg_to_rad(-88.0))
				_moving.position = away * 0.2 + Vector3.UP * (EDGE_T * 0.5 + 0.03)
		"column":
			if _moving != null:
				_moving.visible = false
		"iris":
			if _core != null:
				_core.visible = false
			for i in _leaves.size():
				var leaf := _leaves[i]
				var ang := rng.randf() * TAU
				var spot := away * rng.randf_range(0.6, 1.5) + Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(0.2, 0.7)
				leaf.position = Vector3(spot.x, 0.06 + 0.05 * i, spot.z)
				leaf.basis = Basis(Vector3(cos(ang), 0.0, sin(ang)), deg_to_rad(80.0 + rng.randf_range(-10.0, 10.0))) * Basis(Vector3.UP, rng.randf() * TAU)
				leaf.scale = Vector3(0.75, 0.75, 0.75)
	if style != "edge":
		_add_rubble(away, rng)


# --- Builders ------------------------------------------------------------------------------------------------------------

## The terrain's mesher, reused for door pieces (same surfaces, materials and seams as HexMapView's walls).
class Mesher extends HexMapView:
	func begin() -> void:
		_batches.clear()
		for _i in HexMapView.Surf.size():
			_batches.append(HexMapView.Batch.new())
		_use_mats = true

	func batch(s: int) -> HexMapView.Batch:
		return _batches[s]

	## A block over the open kites `mask` of the cell at local `c`, top at y_top, sides down to y_bot, seam round the top.
	func block(c: Vector3, mask: int, y_top: float, y_bot: float, mat: float, seam_k: float) -> void:
		var top_b: HexMapView.Batch = _batches[HexMapView.Surf.WALL_TOP]
		var side_b: HexMapView.Batch = _batches[HexMapView.Surf.WALL_SIDE]
		top_b.mat = mat
		side_b.mat = mat
		var hv := HexMapView._hash2(Vector2i(int(c.x * 10.0), int(c.z * 10.0)))
		var col := HexMapView._scaled(DOOR_TINT, 0.92 + 0.12 * hv)
		var rim := col.lerp(Color(0.95, 0.52, 0.22), 0.45)
		var seam := HexMapView._scaled(HexMapView.SEAM_COLOR, seam_k)
		var side_col := Color(0.9, 0.9, 0.9)
		for run: Array in HexMapView._runs(mask):
			_run_tile(top_b, c, int(run[0]), int(run[1]), y_top, col, rim, 0.5 * seam_k, seam, true)
			var outline := HexMapView._run_outline(int(run[0]), int(run[1]))
			var whole := int(run[1]) >= 6
			for i in outline.size():
				var a := outline[i]
				var b := outline[(i + 1) % outline.size()]
				var radial := not whole and (a == Vector3.ZERO or b == Vector3.ZERO)
				var mid := (a + b) * 0.5
				var n := Vector3(mid.x, 0.0, mid.z).normalized()
				if radial:
					var t := (b - a).normalized()
					n = Vector3(-t.z, 0.0, t.x)
					if n.dot(Hex.kite_corner(int(run[0]))) < 0.0:
						n = -n
				var yt := y_top - HexMapView.SEAM_DROP
				if radial:
					_side_quad(side_b, c + a, c + b, yt, y_bot, n, 0.0, (b - a).length(), side_col, HexMapView.SEAM_DROP)
					continue
				# a glowing band under the top edge on the faces into the corridor: "this block is a door"
				_side_quad(side_b, c + a, c + b, yt, yt - BAND, n, 0.0, (b - a).length(), DOOR_TINT, HexMapView.SEAM_DROP, BAND_GLOW, BAND_GLOW)
				_side_quad(side_b, c + a, c + b, yt - BAND, y_bot, n, 0.0, (b - a).length(), side_col, HexMapView.SEAM_DROP)

	## A straight vertical slab between local points p and q (thickness t, from y_bot to y_top) with a seamed cap. Mitered
	## ends: `pn` / `qn` are the unit directions the slab's side lines take at each end (null-length = square).
	func slab(left: PackedVector3Array, right: PackedVector3Array, y_top: float, y_bot: float, mat: float) -> void:
		var top_b: HexMapView.Batch = _batches[HexMapView.Surf.WALL_TOP]
		var side_b: HexMapView.Batch = _batches[HexMapView.Surf.WALL_SIDE]
		var seam_b: HexMapView.Batch = _batches[HexMapView.Surf.SEAM]
		top_b.mat = mat
		side_b.mat = mat
		var col := DOOR_TINT
		var side_col := Color(0.9, 0.9, 0.9)
		var n := left.size()
		for i in n - 1:
			var l0 := left[i]
			var l1 := left[i + 1]
			var r0 := right[i]
			var r1 := right[i + 1]
			var dir := (l1 - l0).normalized()
			var nl := Vector3(-dir.z, 0.0, dir.x)
			if nl.dot(l0 - r0) < 0.0:
				nl = -nl
			for sd: Array in [[l0, l1, nl], [r0, r1, -nl]]:
				_side_quad(side_b, sd[0], sd[1], y_top, y_top - BAND, sd[2], 0.0, (sd[0] as Vector3).distance_to(sd[1]), DOOR_TINT, 0.0, BAND_GLOW, BAND_GLOW)
				_side_quad(side_b, sd[0], sd[1], y_top - BAND, y_bot, sd[2], 0.0, (sd[0] as Vector3).distance_to(sd[1]), side_col)
			var cap: Array = [Vector3(l0.x, y_top, l0.z), Vector3(l1.x, y_top, l1.z), Vector3(r1.x, y_top, r1.z), Vector3(r0.x, y_top, r0.z)]
			if (cap[1] - cap[0]).cross(cap[2] - cap[0]).y > 0.0:
				cap.reverse()
			top_b.poly(cap, Vector3.UP, [Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], col)
			# the seam: a narrow glowing strip along the cap's middle, a hair above it
			var m0 := (l0 + r0) * 0.5
			var m1 := (l1 + r1) * 0.5
			var w := nl * 0.025
			var strip: Array = [Vector3(m0.x + w.x, y_top + 0.006, m0.z + w.z), Vector3(m1.x + w.x, y_top + 0.006, m1.z + w.z),
					Vector3(m1.x - w.x, y_top + 0.006, m1.z - w.z), Vector3(m0.x - w.x, y_top + 0.006, m0.z - w.z)]
			if (strip[1] - strip[0]).cross(strip[2] - strip[0]).y > 0.0:
				strip.reverse()
			seam_b.poly(strip, Vector3.UP, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], HexMapView._scaled(HexMapView.SEAM_COLOR, SEAM_GAIN))
		for ends: Array in [[left[0], right[0]], [left[n - 1], right[n - 1]]]:
			var a: Vector3 = ends[0]
			var b: Vector3 = ends[1]
			var t := (b - a).normalized()
			var en := Vector3(-t.z, 0.0, t.x)
			var inward := ((left[1] + right[1]) * 0.5 - (a + b) * 0.5) if ends[0] == left[0] else ((left[n - 2] + right[n - 2]) * 0.5 - (a + b) * 0.5)
			if en.dot(inward) > 0.0:
				en = -en
			_side_quad(side_b, a, b, y_top, y_bot, en, 0.0, a.distance_to(b), side_col)

	## A flat glowing polygon (local points, any winding; star-shaped about the first) facing `n`.
	func glow_poly(pts: Array, k: float, n: Vector3 = Vector3.UP) -> void:
		var b: HexMapView.Batch = _batches[HexMapView.Surf.SEAM]
		var p := pts.duplicate()
		if (p[1] - p[0]).cross(p[2] - p[0]).dot(n) > 0.0:
			p.reverse()
		var uv: Array = []
		for _i in p.size():
			uv.append(Vector2.ZERO)
		b.poly(p, n, uv, HexMapView._scaled(HexMapView.SEAM_COLOR, k))

	## A glowing box (the seam on a jamb).
	func glow_box(c: Vector3, size: Vector3, k: float) -> void:
		var b: HexMapView.Batch = _batches[HexMapView.Surf.SEAM]
		var col := HexMapView._scaled(HexMapView.SEAM_COLOR, k)
		var h := size * 0.5
		var faces := [
			[Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(0, 0, 1)],
			[Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(0, 0, -1)],
			[Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(1, 0, 0)],
			[Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(-1, 0, 0)],
			[Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(0, 1, 0)],
		]
		for f: Array in faces:
			var pts: Array = [c + f[0], c + f[1], c + f[2], c + f[3]]
			var n: Vector3 = f[4]
			if (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(n) > 0.0:
				pts.reverse()
			b.poly(pts, n, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], col)

	## A triangular prism leaf (local points a, b, c on the floor plane) from 0 to y_top, seam-free (the core glows).
	func leaf(pts: Array, y_top: float, mat: float) -> void:
		var top_b: HexMapView.Batch = _batches[HexMapView.Surf.WALL_TOP]
		var side_b: HexMapView.Batch = _batches[HexMapView.Surf.WALL_SIDE]
		top_b.mat = mat
		side_b.mat = mat
		var top: Array = []
		for p: Vector3 in pts:
			top.append(Vector3(p.x, y_top, p.z))
		if (top[1] - top[0]).cross(top[2] - top[0]).y > 0.0:
			top.reverse()
		top_b.poly(top, Vector3.UP, [Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1)], DOOR_TINT)
		var cen: Vector3 = (pts[0] + pts[1] + pts[2]) / 3.0
		for i in 3:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[(i + 1) % 3]
			var mid := (a + b) * 0.5
			var t := (b - a).normalized()
			var n := Vector3(-t.z, 0.0, t.x)
			if n.dot(mid - cen) < 0.0:
				n = -n
			if absf(mid.z) < 0.1:   # the rim face (the pivot sits on the rim): the glowing band
				_side_quad(side_b, a, b, y_top, y_top - BAND, n, 0.0, a.distance_to(b), DOOR_TINT, 0.0, BAND_GLOW, BAND_GLOW)
				_side_quad(side_b, a, b, y_top - BAND, -0.06, n, 0.0, a.distance_to(b), Color(0.9, 0.9, 0.9))
			else:
				_side_quad(side_b, a, b, y_top, -0.06, n, 0.0, a.distance_to(b), Color(0.9, 0.9, 0.9))

	func mesh() -> MeshInstance3D:
		var m := ArrayMesh.new()
		for s in HexMapView.Surf.size():
			var b: HexMapView.Batch = _batches[s]
			if b.indices.is_empty():
				continue
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = b.verts
			arrays[Mesh.ARRAY_NORMAL] = b.normals
			arrays[Mesh.ARRAY_TEX_UV] = b.uvs
			arrays[Mesh.ARRAY_TEX_UV2] = b.uv2s
			arrays[Mesh.ARRAY_COLOR] = b.colors
			arrays[Mesh.ARRAY_INDEX] = b.indices
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat := _material(s)
			if s == HexMapView.Surf.SEAM:
				(mat as ShaderMaterial).set_shader_parameter("energy", 2.4)
			m.surface_set_material(m.get_surface_count() - 1, mat)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		begin()
		return mi


func _build_column(cells: Array) -> void:
	var ms := Mesher.new()
	ms.begin()
	for e: Array in cells:
		ms.block(e[0], int(e[1]), height, -0.06, float(mat_index), SEAM_GAIN)
	_moving = Node3D.new()
	_moving.name = "Column"
	add_child(_moving)
	_moving.add_child(ms.mesh())
	ms.free()


func _build_edge(edges: Array) -> void:
	var ms := Mesher.new()
	ms.begin()
	_moving = Node3D.new()
	_moving.name = "EdgeWall"
	add_child(_moving)
	for line: Array in _chain(edges):
		var left := PackedVector3Array()
		var right := PackedVector3Array()
		for i in line.size():
			var p: Vector3 = line[i]
			var d_in: Vector3 = (p - line[i - 1]).normalized() if i > 0 else Vector3.ZERO
			var d_out: Vector3 = (line[i + 1] - p).normalized() if i < line.size() - 1 else Vector3.ZERO
			var n_in := Vector3(-d_in.z, 0.0, d_in.x)
			var n_out := Vector3(-d_out.z, 0.0, d_out.x)
			var off: Vector3
			if d_in == Vector3.ZERO:
				off = n_out * EDGE_T * 0.5
			elif d_out == Vector3.ZERO:
				off = n_in * EDGE_T * 0.5
			else:
				var mn := (n_in + n_out).normalized()
				off = mn * (EDGE_T * 0.5 / maxf(0.35, mn.dot(n_in)))
			left.append(p + off)
			right.append(p - off)
		ms.slab(left, right, height, -0.06, float(mat_index))
	_moving.add_child(ms.mesh())
	# the jambs: a glowing strip up each corridor wall where the piece meets it (fixed: they stay when it slides down)
	var jambs := Mesher.new()
	jambs.begin()
	for line: Array in _chain(edges):
		for end in [line[0], line[line.size() - 1]]:
			jambs.glow_box(Vector3(end.x, height * 0.5 + 0.015, end.z), Vector3(0.06, height + 0.03, 0.06), SEAM_GAIN)   # (a touch proud of the cap: never flush)
	var jm := jambs.mesh()
	jm.name = "Jambs"
	add_child(jm)
	ms.free()
	jambs.free()


func _build_iris(cells: Array) -> void:
	var c0: Vector3 = cells[0][0]
	# fixed jambs on the cut cells beside the doorway cell
	var fixed := Mesher.new()
	fixed.begin()
	for i in range(1, cells.size()):
		fixed.block(cells[i][0], int(cells[i][1]), height, -0.1, float(mat_index), SEAM_GAIN)
	var fm := fixed.mesh()
	fm.name = "IrisJambs"
	add_child(fm)
	fixed.free()
	# the glowing core the seams show
	var core := Mesher.new()
	core.begin()
	var ring: Array = []
	for i in 6:
		ring.append(c0 + Hex.corner(i) * 0.93 + Vector3(0.0, height - 0.08, 0.0))
	core.glow_poly(ring, SEAM_GAIN * 0.45)
	for i in 6:
		var a: Vector3 = c0 + Hex.corner(i) * 0.93
		var b: Vector3 = c0 + Hex.corner(i + 1) * 0.93
		var quad: Array = [a + Vector3(0, height - 0.08, 0), b + Vector3(0, height - 0.08, 0), b + Vector3(0, 0.02, 0), a + Vector3(0, 0.02, 0)]
		var mid := ((a + b) * 0.5 - c0)
		core.glow_poly(quad, SEAM_GAIN * 0.6, Vector3(mid.x, 0.0, mid.z).normalized())
	_core = core.mesh()
	_core.name = "IrisCore"
	add_child(_core)
	core.free()
	# six leaves: the hex's six triangles, each pulled in from its neighbours by the seam
	for i in 6:
		var a := Hex.corner(i)
		var b := Hex.corner(i + 1)
		var rim_mid := (a + b) * 0.5
		var pivot := Node3D.new()
		pivot.name = "Leaf%d" % i
		pivot.position = c0 + rim_mid
		var inward := -rim_mid.normalized()
		pivot.basis = Basis.looking_at(-inward, Vector3.UP)   # local +Z points inward (looking_at aims -Z)
		add_child(pivot)
		var inv := pivot.basis.inverse()
		var tri: Array = []
		for p in [Vector3.ZERO, a, b]:
			var q: Vector3 = p
			var cen := (Vector3.ZERO + a + b) / 3.0
			q = q + (cen - q).normalized() * LEAF_GAP
			tri.append(inv * (q - rim_mid))
		var lm := Mesher.new()
		lm.begin()
		lm.leaf(tri, height - 0.02, float(mat_index))
		pivot.add_child(lm.mesh())
		lm.free()
		_leaves.append(pivot)


## Chain edge segments that share ends into polylines (each an Array of local points).
static func _chain(edges: Array) -> Array:
	var left := edges.duplicate()
	var out: Array = []
	while not left.is_empty():
		var seg: Array = left.pop_front()
		var line: Array = [seg[0], seg[1]]
		var grew := true
		while grew:
			grew = false
			for i in left.size():
				var s: Array = left[i]
				if (s[0] as Vector3).distance_to(line[line.size() - 1]) < 0.01:
					line.append(s[1])
				elif (s[1] as Vector3).distance_to(line[line.size() - 1]) < 0.01:
					line.append(s[0])
				elif (s[1] as Vector3).distance_to(line[0]) < 0.01:
					line.push_front(s[0])
				elif (s[0] as Vector3).distance_to(line[0]) < 0.01:
					line.push_front(s[1])
				else:
					continue
				left.remove_at(i)
				grew = true
				break
		out.append(line)
	return out


## Hex rubble on the band: broken chunks of the door in its own wall colours, low, scattered toward `away`.
func _add_rubble(away: Vector3, rng: RandomNumberGenerator) -> void:
	_rubble = Node3D.new()
	_rubble.name = "Rubble"
	add_child(_rubble)
	var s := LowPoly.Soup.new(rng.randi(), 0.08)
	var stone := Color(0.62, 0.63, 0.67)
	var dark := Color(0.4, 0.41, 0.45)
	for c in _band:
		for j in 4:
			var r := rng.randf_range(0.14, 0.3)
			var spot := c + away * rng.randf_range(-0.2, 0.7) + Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
			var chunk := LowPoly.cylinder(r, r * 0.8, r * rng.randf_range(0.7, 1.3), 6, stone if j % 2 == 0 else dark, rng.randi(), 0.12)
			s.merge(chunk, LowPoly.at(spot + Vector3(0.0, r * 0.45, 0.0), Vector3(rng.randf_range(-35, 35), rng.randf() * 360.0, rng.randf_range(-35, 35))))
	var mi := MeshInstance3D.new()
	mi.mesh = s.to_mesh()
	mi.material_override = PropModels.material()
	_rubble.add_child(mi)
