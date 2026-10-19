class_name OfficeDoorModel
extends Node3D
## The look of an office door (OfficeDoor; docs/design/exploration.md "Decisions: map information, fog and doors",
## 2026-10-19), v3: a door that belongs to the ROOM WALL, not to the hex terrain. It stands on the doorway's door line
## (Doorways: the chord between the two jambs where the corridor's walls end at the room), fills it wall face to wall face
## and is the wall's height, with an off-white architrave (two jamb posts and a header, a touch proud of the wall top) so
## the wall line reads as continuous with a door in it. Faceted like the priced props (PropModels.material: flat facets,
## ink outline). Three STYLES, each shut / opening / open / smashed:
##   single   a centred oak leaf with a narrow wired-glass light and a lever handle, fixed cream side panels with wired
##            glass sidelights. Swings away from whoever opens it. Smashed: the leaf is torn off and lies flat.
##   double   two cream leaves filling the opening, steel push bars across both faces, a small lit sign over the door.
##            Swing apart. Smashed: both leaves flat, the sign hanging askew.
##   slider   a frosted glass suite front: two fixed glass panels at the sides and two sliding ones in the middle that
##            slide behind them, a teal logo band across the glass. Smashed: the glass is gone (shards), the frame stays.
## Local frame: X along the door line (from jamb a to jamb b), Z across it (+Z = the hall side), Y up, origin on the floor
## at the middle of the line. Pure presentation (LOCAL).

const STYLES: Array[String] = ["single", "double", "slider"]
const TRIM := Color(0.9, 0.88, 0.82)
const TRIM_DK := Color(0.62, 0.6, 0.56)
const OAK := Color(0.7, 0.48, 0.27)
const OAK_DK := Color(0.5, 0.33, 0.18)
const CREAM := Color(0.9, 0.84, 0.7)
const CREAM_DK := Color(0.7, 0.64, 0.52)
const STEEL := Color(0.62, 0.65, 0.7)
const STEEL_DK := Color(0.3, 0.32, 0.36)
const WIRED := Color(0.62, 0.78, 0.84)
const FROST := Color(0.84, 0.92, 0.96)
const LOGO := Color(0.1, 0.56, 0.6)
const SIGN := Color(0.35, 1.0, 0.55)
const BRASS := Color(0.95, 0.78, 0.36)

const POST := 0.14               ## jamb post width (along the line)
const DEPTH := 0.32              ## frame depth (across the line)
const HEAD := 0.22               ## header height
const PROUD := 0.04              ## the frame stands this far above the wall top (never flush with its cap)
const LEAF_T := 0.08             ## leaf thickness
const GLASS_T := 0.05
const SINGLE_LEAF := 1.25        ## the single door's leaf width (centred on the corridor's lane)
const SWING_DEG := 92.0

var style := "single"
var width := 3.0                 ## the door line's length, jamb to jamb
var height := 1.5                ## the wall height
var open_k := 0.0
var swing := 1.0                 ## +1: leaves swing toward +Z (the hall), -1 toward the room
var broken := false

var _leaves: Array[Node3D] = []  ## swing pivots (single, double) or slide carriers (slider)
var _leaf_dir: Array[float] = [] ## per leaf: +1 / -1 (which way its free edge points, or which way it slides)
var _glass: Array[Node3D] = []   ## what a smash knocks out
var _sign: Node3D = null
var _inner := 2.7


## Who may write each var (see Net). All of it is presentation.
func net_fields() -> Dictionary:
	return {
		"style": Net.LOCAL, "width": Net.LOCAL, "height": Net.LOCAL, "open_k": Net.LOCAL, "swing": Net.LOCAL, "broken": Net.LOCAL,
		"_leaves": Net.LOCAL, "_leaf_dir": Net.LOCAL, "_glass": Net.LOCAL, "_sign": Net.LOCAL, "_inner": Net.LOCAL,
	}


static func make(door_style: String, door_width: float, wall_height: float) -> OfficeDoorModel:
	var m := OfficeDoorModel.new()
	m.style = door_style
	m.width = door_width
	m.height = wall_height
	m.name = "OfficeDoor_" + door_style
	m._build()
	return m


## Splinter colours for a smash.
func palette() -> Array[Color]:
	match style:
		"double":
			return [CREAM, CREAM_DK, STEEL, TRIM]
		"slider":
			return [FROST, WIRED, LOGO, TRIM]
	return [OAK, OAK_DK, WIRED, TRIM]


func set_open(k: float, swing_dir: float = 1.0) -> void:
	open_k = clampf(k, 0.0, 1.0)
	swing = 1.0 if swing_dir >= 0.0 else -1.0
	if broken:
		return
	var e := open_k * open_k * (3.0 - 2.0 * open_k)
	match style:
		"slider":
			var travel := _inner * 0.25 + 0.02
			for i in _leaves.size():
				_leaves[i].position.x = _leaf_x(i) + _leaf_dir[i] * travel * e
		_:
			for i in _leaves.size():
				# a leaf hinged at its outer edge: its free edge points toward the middle (dir); swinging toward +Z * swing
				_leaves[i].rotation.y = -_leaf_dir[i] * swing * deg_to_rad(SWING_DEG) * e


## Smashed: the leaves torn off and flat on the floor beyond the door on the `away` side (+1: the hall, -1: the room),
## the glass gone. The frame stays.
func show_broken(away: float, rng: RandomNumberGenerator) -> void:
	if broken:
		return
	broken = true
	var sgn := 1.0 if away >= 0.0 else -1.0
	match style:
		"slider":
			for g in _glass:
				g.visible = false
		_:
			for i in _leaves.size():
				var leaf := _leaves[i]
				var yaw := rng.randf_range(-0.35, 0.35)
				# torn off and flat on its face beyond the door, its foot toward the frame, a little scattered
				leaf.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, sgn * PI * 0.5),
						Vector3(leaf.position.x * 0.8, LEAF_T * 0.5 + 0.02 + 0.03 * i, sgn * (0.3 + rng.randf_range(0.0, 0.3))))
			for g in _glass:
				g.visible = false
			if _sign != null:
				_sign.rotation.z = deg_to_rad(18.0)
				_sign.position.y -= 0.12


# --- Builders -----------------------------------------------------------------------------------------------------------

func _build() -> void:
	_inner = width - 2.0 * POST
	var frame := LowPoly.Soup.new(29, 0.05)
	var top := height + PROUD
	for side in [-1.0, 1.0]:
		frame.merge(LowPoly.box(Vector3(POST, top, DEPTH), TRIM, 3), LowPoly.at(Vector3(side * (width * 0.5 - POST * 0.5), top * 0.5, 0.0)))
		# a darker stop bead down the post's inner edge
		frame.merge(LowPoly.box(Vector3(0.03, top - HEAD, DEPTH * 0.45), TRIM_DK, 4),
				LowPoly.at(Vector3(side * (width * 0.5 - POST - 0.015), (top - HEAD) * 0.5, 0.0)))
	frame.merge(LowPoly.box(Vector3(_inner - 0.004, HEAD, DEPTH - 0.02), TRIM, 5), LowPoly.at(Vector3(0.0, top - HEAD * 0.5, 0.0)))
	_mesh(frame, self, "Frame")
	match style:
		"double":
			_build_double(top - HEAD)
		"slider":
			_build_slider(top - HEAD)
		_:
			_build_single(top - HEAD)
	set_open(open_k, swing)


func _leaf_width() -> float:
	match style:
		"double":
			return _inner * 0.5 - 0.02
		"slider":
			return _inner * 0.25 + 0.03
	return minf(SINGLE_LEAF, _inner * 0.6)


func _leaf_x(i: int) -> float:
	match style:
		"slider":
			return (-1.0 if i == 0 else 1.0) * _inner * 0.125
	return 0.0


## The single door: fixed cream panels with a wired-glass sidelight either side, a mullion each side of the leaf, the oak
## leaf in the middle (hinged on the -X mullion) with a narrow wired-glass light and a lever handle.
func _build_single(leaf_top: float) -> void:
	var lw := _leaf_width()
	var side_w := (_inner - lw) * 0.5 - 0.1
	var fixed := LowPoly.Soup.new(31, 0.05)
	for side in [-1.0, 1.0]:
		var cx: float = side * (lw * 0.5 + 0.1 + side_w * 0.5)
		# mullion between the panel and the leaf
		fixed.merge(LowPoly.box(Vector3(0.08, leaf_top, DEPTH * 0.7), TRIM, 7), LowPoly.at(Vector3(side * (lw * 0.5 + 0.05), leaf_top * 0.5, 0.0)))
		if side_w > 0.12:
			fixed.merge(LowPoly.box(Vector3(side_w, leaf_top, LEAF_T), CREAM, 8), LowPoly.at(Vector3(cx, leaf_top * 0.5, 0.0)))
			fixed.merge(LowPoly.box(Vector3(side_w - 0.06, 0.12, LEAF_T + 0.02), CREAM_DK, 9), LowPoly.at(Vector3(cx, 0.1, 0.0)))
	_mesh(fixed, self, "SidePanels")
	if side_w > 0.3:
		for side in [-1.0, 1.0]:
			var cx: float = side * (lw * 0.5 + 0.1 + side_w * 0.5)
			var g := LowPoly.Soup.new(33, 0.03)
			_wired_glass(g, Vector3(cx, leaf_top * 0.6, 0.0), Vector2(minf(0.22, side_w * 0.5), leaf_top * 0.55))
			_glass.append(_mesh(g, self, "Sidelight"))
	var pivot := Node3D.new()
	pivot.name = "Leaf"
	pivot.position = Vector3(-lw * 0.5, 0.0, 0.0)
	add_child(pivot)
	var s := LowPoly.Soup.new(37, 0.05)
	var lc := Vector3(lw * 0.5, leaf_top * 0.5, 0.0)
	s.merge(LowPoly.box(Vector3(lw - 0.02, leaf_top - 0.02, LEAF_T), OAK, 11), LowPoly.at(lc))
	s.merge(LowPoly.box(Vector3(lw - 0.08, 0.14, LEAF_T + 0.02), STEEL_DK, 12), LowPoly.at(Vector3(lw * 0.5, 0.1, 0.0)))   # kick plate
	# lever handles both faces, near the free edge
	for face in [-1.0, 1.0]:
		var z: float = face * (LEAF_T * 0.5 + 0.035)
		s.merge(LowPoly.box(Vector3(0.07, 0.12, 0.05), STEEL, 13), LowPoly.at(Vector3(lw - 0.16, leaf_top * 0.45, z)))
		s.merge(LowPoly.box(Vector3(0.24, 0.045, 0.05), BRASS, 14), LowPoly.at(Vector3(lw - 0.26, leaf_top * 0.45 + 0.03, z + face * 0.03)))
	_mesh(s, pivot, "LeafBody")
	var g2 := LowPoly.Soup.new(39, 0.03)
	_wired_glass(g2, Vector3(lw * 0.3, leaf_top * 0.66, 0.0), Vector2(0.2, leaf_top * 0.42))
	_glass.append(_mesh(g2, pivot, "LeafGlass"))
	_leaves.append(pivot)
	_leaf_dir.append(1.0)


## The double doors: two cream leaves hinged at the posts, push bars across both faces, a lit sign on the header.
func _build_double(leaf_top: float) -> void:
	var lw := _leaf_width()
	for i in 2:
		var dir := 1.0 if i == 0 else -1.0     # the free edge points toward the middle
		var pivot := Node3D.new()
		pivot.name = "Leaf%d" % i
		pivot.position = Vector3(-dir * _inner * 0.5 + dir * 0.005, 0.0, 0.0)
		add_child(pivot)
		var s := LowPoly.Soup.new(41 + i, 0.05)
		var cx := dir * (lw * 0.5)
		s.merge(LowPoly.box(Vector3(lw, leaf_top - 0.02, LEAF_T), CREAM, 15 + i), LowPoly.at(Vector3(cx, leaf_top * 0.5, 0.0)))
		s.merge(LowPoly.box(Vector3(lw - 0.08, 0.14, LEAF_T + 0.02), STEEL_DK, 17), LowPoly.at(Vector3(cx, 0.1, 0.0)))
		# a small vision pane high on the leaf
		s.merge(LowPoly.box(Vector3(0.22, 0.26, LEAF_T + 0.016), WIRED * 0.8, 18), LowPoly.at(Vector3(cx + dir * 0.12, leaf_top * 0.76, 0.0)))
		for face in [-1.0, 1.0]:
			var z: float = face * (LEAF_T * 0.5 + 0.06)
			# the push bar: a bright bar across the leaf on two brackets
			s.merge(LowPoly.box(Vector3(lw - 0.2, 0.07, 0.06), STEEL, 19), LowPoly.at(Vector3(cx, leaf_top * 0.48, z)))
			for bx in [-1.0, 1.0]:
				s.merge(LowPoly.box(Vector3(0.05, 0.1, 0.07), STEEL_DK, 20), LowPoly.at(Vector3(cx + bx * (lw * 0.5 - 0.14), leaf_top * 0.48, face * (LEAF_T * 0.5 + 0.032))))
		_mesh(s, pivot, "LeafBody")
		_leaves.append(pivot)
		_leaf_dir.append(dir)
	# the lit sign on the header, both faces
	_sign = Node3D.new()
	_sign.name = "Sign"
	_sign.position = Vector3(0.0, leaf_top + HEAD * 0.5, 0.0)
	add_child(_sign)
	var sg := LowPoly.Soup.new(45, 0.02)
	for face in [-1.0, 1.0]:
		var z: float = face * (DEPTH * 0.5 + 0.05)
		sg.merge(LowPoly.box(Vector3(0.62, 0.2, 0.08), STEEL_DK, 21), LowPoly.at(Vector3(0.0, 0.0, z)))
		sg.merge(LowPoly.box(Vector3(0.54, 0.13, 0.03), PropModels.glow(SIGN), 22), LowPoly.at(Vector3(0.0, 0.0, z + face * 0.045)))
	_mesh(sg, _sign, "SignBody")


## The frosted glass suite front: fixed glass either side, two sliding panels in the middle that slide behind them, a teal
## logo band across all of it with a mark on each sliding panel.
func _build_slider(leaf_top: float) -> void:
	var pw := _inner * 0.25 + 0.03
	var fixed := LowPoly.Soup.new(51, 0.03)
	for side in [-1.0, 1.0]:
		var cx: float = side * (_inner * 0.375 - 0.015)
		_glass_panel(fixed, Vector3(cx, leaf_top * 0.5, -0.045), Vector2(pw, leaf_top - 0.02))
	_glass.append(_mesh(fixed, self, "FixedGlass"))
	# the top track on the header's underside
	var track := LowPoly.Soup.new(53, 0.03)
	track.merge(LowPoly.box(Vector3(_inner - 0.01, 0.05, 0.2), STEEL_DK, 23), LowPoly.at(Vector3(0.0, leaf_top - 0.025, 0.0)))
	_mesh(track, self, "Track")
	for i in 2:
		var dir := -1.0 if i == 0 else 1.0      # slides outward, behind the fixed glass
		var carrier := Node3D.new()
		carrier.name = "Slide%d" % i
		carrier.position = Vector3(_leaf_x(i), 0.0, 0.0)
		add_child(carrier)
		var s := LowPoly.Soup.new(55 + i, 0.03)
		_glass_panel(s, Vector3(0.0, leaf_top * 0.5, 0.045), Vector2(_inner * 0.25 - 0.012, leaf_top - 0.06))   # (a hair apart in the middle)
		# the logo mark on the band: a white diamond
		for face in [-1.0, 1.0]:
			s.merge(LowPoly.box(Vector3(0.14, 0.14, 0.02), Color(0.97, 0.97, 0.95), 25),
					LowPoly.at(Vector3(-dir * pw * 0.2, leaf_top * 0.62, 0.045 + face * (GLASS_T * 0.5 + 0.03)), Vector3(0, 0, 45)))
		var mi := _mesh(s, carrier, "SlideGlass")
		_glass.append(mi)
		_leaves.append(carrier)
		_leaf_dir.append(dir)


## A frosted glass panel at `c` (size w x h) with an aluminium edge and the teal logo band across both faces.
func _glass_panel(s: LowPoly.Soup, c: Vector3, size: Vector2) -> void:
	s.merge(LowPoly.box(Vector3(size.x - 0.04, size.y - 0.04, GLASS_T), FROST, 26), LowPoly.at(c))
	for e: Array in [[Vector3(0, size.y * 0.5 - 0.02, 0), Vector3(size.x, 0.04, GLASS_T + 0.02)],
			[Vector3(0, -size.y * 0.5 + 0.02, 0), Vector3(size.x, 0.04, GLASS_T + 0.02)],
			[Vector3(size.x * 0.5 - 0.02, 0, 0), Vector3(0.04, size.y - 0.08, GLASS_T + 0.02)],
			[Vector3(-size.x * 0.5 + 0.02, 0, 0), Vector3(0.04, size.y - 0.08, GLASS_T + 0.02)]]:
		s.merge(LowPoly.box(e[1], STEEL, 27), LowPoly.at(c + (e[0] as Vector3)))
	s.merge(LowPoly.box(Vector3(size.x - 0.08, 0.16, GLASS_T + 0.012), LOGO, 28), LowPoly.at(Vector3(c.x, size.y * 0.62, c.z)))


## A narrow wired-glass light: the pane and its wire grid, proud of both faces of the panel it sits in.
func _wired_glass(s: LowPoly.Soup, c: Vector3, size: Vector2) -> void:
	s.merge(LowPoly.box(Vector3(size.x, size.y, LEAF_T + 0.014), WIRED, 31), LowPoly.at(c))
	for face in [-1.0, 1.0]:
		var z: float = c.z + face * (LEAF_T * 0.5 + 0.012)
		for k in 3:
			var y: float = c.y - size.y * 0.5 + size.y * (k + 1) / 4.0
			s.merge(LowPoly.box(Vector3(size.x - 0.02, 0.012, 0.008), STEEL_DK, 32), LowPoly.at(Vector3(c.x, y, z)))
		s.merge(LowPoly.box(Vector3(0.012, size.y - 0.02, 0.008), STEEL_DK, 33), LowPoly.at(Vector3(c.x, c.y, z + face * 0.009)))


func _mesh(s: LowPoly.Soup, parent: Node3D, n: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = s.to_mesh()
	mi.material_override = PropModels.material()
	parent.add_child(mi)
	return mi
