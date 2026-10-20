class_name ElevatorModel
extends Node3D
## The elevator as a set piece (docs/design/elevator-options.md), so the exit reads as an elevator from the iso camera.
## The game builds it through ElevatorArrival from the floor's ElevatorGeo record (every job picks one look and one
## form); scenes/elevator_lab.tscn shows every combination on the real terrain.
##
## Two LOOKS:
##   "service"  freight: steel jambs with hazard stripes, a scissor gate, a diamond-plate car with moving blankets,
##              a caged lamp, a dial indicator, a call box and a clipboard on a nail
##   "fancy"    luxury bunker / villain lair: black marble surround, brass bi-parting doors, a stepped art-deco crown
##              with a fan indicator, a wood-and-mirror car with a brass rail, a lit call button
## Two FORMS:
##   "wall"     the doors sit on a room's wall line and the car is a one-row alcove behind it (placements A and B).
##              Local frame: origin = the middle of the alcove's mouth on the floor, +Z = into the room, the car runs
##              to z = -CAR_DEPTH. It fills exactly the triangles a 3-cell notch in a midpoint wall opens (see the doc).
##   "column"   free-standing in a room (placement C). Both are hexagons whose corners stand on the six neighbour
##              centres of one cell (so their sides lie on midpoint-wall lines, ElevatorGeo's solids): fancy = a glass
##              shaft; service = a freight platform lift: a hazard-edged hex deck over a dark gap, railings on five sides,
##              a lifting bar gate on the sixth and a yellow six-post hoist frame with the motor and sheave on top.
##              Origin = the middle of the footprint, +Z = the door side.
## The floor indicator doubles as a RISK gauge (green / amber / red zones; floors are named by risk, contracts.md).
##
##   var e := ElevatorModel.new("service", "wall")
##   e.set_door_open(1.0)      # 0 closed .. 1 open; the sill strip turns from red to green
##   e.set_indicator(0.5)      # needle 0 (low risk) .. 1 (origin)
##
## Faceted low-poly in the house style: LowPoly soups, MonsterMaterial (ink outline, amber rim, vertex alpha 0.5 = glow).
## No randomness beyond the soups' own seeded paint jitter.

const CAR_HALF := 1.732        ## sqrt(3): half the notch's back edge = the car's inner half width
const CAR_DEPTH := 1.5         ## one hex row
const JAMB_OUT := 2.75         ## the jambs reach a little past the mouth corners (hide the hex wall's corner)
const FRONT := 0.12            ## how far the portal stands proud of the wall line
const SEED := 5309

# service
const STEEL := Color(0.40, 0.43, 0.48)
const STEEL_DK := Color(0.20, 0.215, 0.25)
const STEEL_LT := Color(0.66, 0.70, 0.74)
const PLATE := Color(0.36, 0.40, 0.44)
const HAZ_Y := Color(0.98, 0.74, 0.10)
const HAZ_K := Color(0.07, 0.07, 0.08)
const FRAME_Y := Color(0.86, 0.62, 0.12)
const BLANKET := Color(0.24, 0.33, 0.50)
const BLANKET_DK := Color(0.13, 0.18, 0.29)
const RUST := Color(0.50, 0.26, 0.12)
# fancy
const BRASS := Color(0.95, 0.73, 0.33)
const BRASS_DK := Color(0.60, 0.42, 0.15)
const MARBLE_K := Color(0.12, 0.11, 0.135)
const WOOD := Color(0.42, 0.22, 0.11)
const WOOD_DK := Color(0.24, 0.12, 0.06)
const CARPET := Color(0.46, 0.07, 0.12)
const MIRROR := Color(0.56, 0.66, 0.74)
# shared
const CREAM := Color(0.96, 0.91, 0.76)
const BOARD := Color(0.50, 0.33, 0.18)
const GO := Color(0.35, 1.0, 0.50)
const STOP := Color(1.0, 0.22, 0.14)
const WARN := Color(1.0, 0.62, 0.14)
const LAMP_WARM := Color(1.0, 0.84, 0.56)
const LAMP_COOL := Color(0.82, 0.94, 1.0)

var look := "service"
var form := "wall"
var parts: Dictionary = {}           ## name -> MeshInstance3D
var _door_open := 0.0
var _needle := 0.0
var _body_mat: ShaderMaterial
var _go: MeshInstance3D
var _stop: MeshInstance3D
var _car_light: OmniLight3D
var _font: FontVariation


func _init(look_name: String = "service", form_name: String = "wall") -> void:
	look = look_name
	form = form_name
	name = "Elevator"
	PropModels._seed = SEED + (0 if look == "service" else 400) + (0 if form == "wall" else 900)
	_font = FontVariation.new()
	_font.base_font = ThemeDB.fallback_font
	_font.variation_embolden = 0.9
	_body_mat = _material(1.6)
	var s := LowPoly.Soup.new(SEED, 0.05)
	match [look, form]:
		["service", "wall"]: _service_wall(s)
		["fancy", "wall"]: _fancy_wall(s)
		["service", "column"]: _service_column(s)
		_: _fancy_column(s)
	_add_mesh("Body", s, _body_mat)
	_go = _add_mesh("SillGo", _sill_soup(GO), _material(2.4))
	_stop = _add_mesh("SillStop", _sill_soup(STOP), _material(2.0))
	_car_light = OmniLight3D.new()
	_car_light.name = "CarLight"
	_car_light.light_color = LAMP_COOL if look == "service" else LAMP_WARM
	_car_light.omni_range = 4.6
	_car_light.omni_attenuation = 1.4
	_car_light.light_specular = 0.0
	_car_light.shadow_enabled = false
	_car_light.position = Vector3(0, 2.5, -0.75) if form == "wall" else Vector3(0, 2.2, 0)
	add_child(_car_light)
	if look == "fancy" and form == "column":
		_add_glass()
	set_indicator(0.15)
	set_door_open(0.0)


# --------------------------------------------------------------------------- state

## 0 = closed, 1 = open. The doors / gate move, the sill strip turns green and the car light comes up.
func set_door_open(t: float) -> void:
	_door_open = clampf(t, 0.0, 1.0)
	_set_soup("Doors", _doors_soup(_door_open))
	_go.visible = _door_open > 0.5
	_stop.visible = not _go.visible
	_car_light.light_energy = lerpf(0.9, 3.2, _door_open)


func door_open_amount() -> float:
	return _door_open


## Needle position on the risk gauge: 0 = the low-risk end (green) .. 1 = the origin floor (red).
func set_indicator(t: float) -> void:
	_needle = clampf(t, 0.0, 1.0)
	_set_soup("Needle", _needle_soup(_needle))


## Spots (local, on the floor) where a crew of up to four stands inside the car (the arrival point).
func car_spots() -> Array[Vector3]:
	if form == "wall":
		return [Vector3(-1.0, 0, -0.8), Vector3(0.0, 0, -0.78), Vector3(1.05, 0, -0.3), Vector3(-1.1, 0, -0.25)]
	return [Vector3(-0.6, 0, -0.55), Vector3(0.55, 0, -0.6), Vector3(0.35, 0, 0.55), Vector3(-0.6, 0, 0.4)]


func triangle_count() -> int:
	var n := 0
	for p: MeshInstance3D in parts.values():
		if p.mesh != null and p.mesh.get_surface_count() > 0:
			n += (p.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


# --------------------------------------------------------------------------- plumbing

func _add_mesh(part_name: String, soup: LowPoly.Soup, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = soup.to_mesh()
	mi.material_override = mat
	add_child(mi)
	parts[part_name] = mi
	return mi


func _set_soup(part_name: String, soup: LowPoly.Soup) -> void:
	if parts.has(part_name):
		(parts[part_name] as MeshInstance3D).mesh = soup.to_mesh()
	else:
		_add_mesh(part_name, soup, _body_mat)


static func _material(gain: float) -> ShaderMaterial:
	var m := MonsterMaterial.make(2.3)
	m.set_shader_parameter("glow_gain", gain)
	return m


static func _g(c: Color) -> Color:
	return PropModels.glow(c)


static func _b(s: LowPoly.Soup, size: Vector3, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
	PropModels.box(s, size, pos, col, rot)


static func _rod(s: LowPoly.Soup, a: Vector3, b: Vector3, r: float, col: Color, sides: int = 5) -> void:
	PropModels.rod(s, a, b, r, r, sides, col)


static func _cyl(s: LowPoly.Soup, r0: float, r1: float, h: float, sides: int, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
	PropModels.cyl(s, r0, r1, h, sides, pos, col, rot)


## A flat sub-soup in the XY plane (normal +Z) merged through `xf`. Built 0.01 in front of its own origin so the
## outward winding is unambiguous, then pulled back onto the plane.
static func _flat(s: LowPoly.Soup, sub: LowPoly.Soup, xf: Transform3D) -> void:
	s.merge(sub, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.01)))


## Diagonal hazard stripes on a strip `length` x `width` centred on xf's origin (u = +X, v = +Y, facing +Z).
static func _stripes(s: LowPoly.Soup, xf: Transform3D, length: float, width: float, n: int, a: Color = HAZ_Y, b: Color = HAZ_K) -> void:
	var sub := LowPoly.Soup.new(PropModels._n(), 0.05)
	var step := length / n
	var slant := width * 0.9
	var hl := length * 0.5
	for i in range(-2, n + 1):
		var u0 := -hl + i * step
		var col := a if posmod(i, 2) == 0 else b
		var p0 := Vector3(clampf(u0, -hl, hl), -width * 0.5, 0.01)
		var p1 := Vector3(clampf(u0 + step, -hl, hl), -width * 0.5, 0.01)
		var p2 := Vector3(clampf(u0 + step + slant, -hl, hl), width * 0.5, 0.01)
		var p3 := Vector3(clampf(u0 + slant, -hl, hl), width * 0.5, 0.01)
		if p1.x - p0.x < 0.002 and p2.x - p3.x < 0.002:
			continue
		sub.add_tri(p0, p1, p2, col)
		sub.add_tri(p0, p2, p3, col)
	_flat(s, sub, xf)


## An annular sector in the XY plane: radii r0..r1, angles a0..a1 (degrees, 0 = +X, 90 = up).
static func _sector(s: LowPoly.Soup, xf: Transform3D, r0: float, r1: float, a0: float, a1: float, segs: int, col: Color) -> void:
	var sub := LowPoly.Soup.new(PropModels._n(), 0.03)
	for i in segs:
		var t0 := deg_to_rad(lerpf(a0, a1, float(i) / segs))
		var t1 := deg_to_rad(lerpf(a0, a1, float(i + 1) / segs))
		var i0 := Vector3(cos(t0) * r0, sin(t0) * r0, 0.01)
		var i1 := Vector3(cos(t1) * r0, sin(t1) * r0, 0.01)
		var o0 := Vector3(cos(t0) * r1, sin(t0) * r1, 0.01)
		var o1 := Vector3(cos(t1) * r1, sin(t1) * r1, 0.01)
		if r0 < 0.001:
			sub.add_tri(i0, o0, o1, col)
		else:
			sub.add_tri(i0, o0, o1, col)
			sub.add_tri(i0, o1, i1, col)
	_flat(s, sub, xf)


static func _face(pos: Vector3, yaw: float = 0.0) -> Transform3D:
	return LowPoly.at(pos, Vector3(0, yaw, 0))


static func _floor_xf(pos: Vector3, yaw: float = 0.0) -> Transform3D:
	return LowPoly.at(pos, Vector3(-90, yaw, 0))


func _label(text: String, size: int, pixel: float, col: Color, pos: Vector3, yaw: float = 0.0, pitch: float = 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = _font
	l.font_size = size
	l.pixel_size = pixel
	l.shaded = false
	l.double_sided = false
	l.modulate = col
	l.outline_size = 5
	l.outline_modulate = Color(0.04, 0.03, 0.05)
	l.position = pos
	l.rotation_degrees = Vector3(pitch, yaw, 0)
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	add_child(l)
	return l


# --------------------------------------------------------------------------- shared pieces

## The risk-gauge face: a half disc with green / amber / red zones (glowing) and tick marks. `c` = the pivot.
func _gauge(s: LowPoly.Soup, c: Vector3, r: float, yaw: float, face_col: Color, fancy: bool) -> void:
	var xf := _face(c, yaw)
	if fancy:
		# a deco sunburst: alternating brass rays inside the coloured rim
		for i in 9:
			_sector(s, xf, 0.0, r * 0.78, 180.0 - i * 20.0, 180.0 - (i + 1) * 20.0, 2, BRASS if i % 2 == 0 else BRASS_DK)
		_sector(s, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.004)), r * 0.80, r, 180.0, 120.0, 4, _g(GO))
		_sector(s, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.004)), r * 0.80, r, 120.0, 60.0, 4, _g(WARN))
		_sector(s, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.004)), r * 0.80, r, 60.0, 0.0, 4, _g(STOP))
		_sector(s, xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.004)), r * 0.76, r * 1.1, 180.0, 0.0, 12, BRASS_DK)
	else:
		_sector(s, xf, 0.0, r, 180.0, 0.0, 10, face_col)
		var zx := xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.004))
		_sector(s, zx, r * 0.70, r * 0.92, 175.0, 125.0, 3, _g(GO))
		_sector(s, zx, r * 0.70, r * 0.92, 122.0, 62.0, 3, _g(WARN))
		_sector(s, zx, r * 0.70, r * 0.92, 58.0, 5.0, 3, _g(STOP))
		for i in 7:
			var a := deg_to_rad(180.0 - i * 30.0)
			var p := c + Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)) * Vector3(cos(a) * r * 0.95, sin(a) * r * 0.95, 0.012)
			_b(s, Vector3(0.022, 0.07, 0.012), p, HAZ_K, Vector3(0, yaw, rad_to_deg(a) - 90.0))
	_cyl(s, 0.045, 0.045, 0.03, 8, c + Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)) * Vector3(0, 0, 0.02), HAZ_K if not fancy else BRASS_DK, Vector3(90, yaw, 0))


func _needle_soup(t: float) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(SEED + 3, 0.0)
	var c: Vector3
	var r: float
	var yaw := 0.0
	match [look, form]:
		["service", "wall"]:
			c = Vector3(0, 3.36, FRONT + 0.075)
			r = 0.30
		["fancy", "wall"]:
			c = Vector3(0, 3.28, FRONT + 0.06)
			r = 0.74
		["service", "column"]:
			c = Vector3(0, 3.5, SHAFT_APOTHEM + 0.245)
			r = 0.3
		_:
			c = Vector3(0, SHAFT_H + 0.29, 1.61)
			r = 0.58
	var ang := lerpf(80.0, -80.0, t)   # degrees from straight up, positive = toward the green (left) end
	var length := r * 0.86
	var dir := Vector3(-sin(deg_to_rad(ang)), cos(deg_to_rad(ang)), 0)
	var col := _g(Color(1.0, 0.95, 0.85)) if look == "fancy" else Color(0.9, 0.12, 0.08)
	_b(s, Vector3(0.035, length, 0.018), c + dir * length * 0.5 + Vector3(0, 0, 0.03), col, Vector3(0, 0, ang))
	return s


## The sill status strip: red while the doors are shut, green when the crew can step in.
func _sill_soup(col: Color) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(SEED + 7, 0.0)
	if form == "wall":
		_b(s, Vector3(2.0 * CAR_HALF - 0.2, 0.025, 0.04), Vector3(0, 0.085, FRONT - 0.01), _g(col))
	elif look == "fancy":
		_b(s, Vector3(1.5, 0.025, 0.04), Vector3(0, 0.09, 1.58), _g(col))
	else:
		_b(s, Vector3(1.45, 0.025, 0.04), Vector3(0, 0.085, SHAFT_APOTHEM - 0.08), _g(col))
	return s


## The clipboard on a nail: the floor service log (the elevator's form will be a sign-in sheet). `pos` = its centre.
func _clipboard(s: LowPoly.Soup, pos: Vector3, yaw: float = 0.0) -> void:
	var bs := Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0))
	_b(s, Vector3(0.30, 0.42, 0.025), pos, BOARD, Vector3(0, yaw, 0))
	_b(s, Vector3(0.25, 0.33, 0.012), pos + bs * Vector3(0, -0.02, 0.018), CREAM, Vector3(0, yaw, 0))
	for i in 5:
		_b(s, Vector3(0.19, 0.012, 0.006), pos + bs * Vector3(0.0, 0.09 - i * 0.055, 0.026), Color(0.35, 0.36, 0.45), Vector3(0, yaw, 0))
	_b(s, Vector3(0.012, 0.012, 0.006), pos + bs * Vector3(0.07, 0.035, 0.028), _g(STOP), Vector3(0, yaw, 0))
	_b(s, Vector3(0.13, 0.05, 0.04), pos + bs * Vector3(0, 0.2, 0.02), STEEL_LT, Vector3(0, yaw, 0))
	_rod(s, pos + bs * Vector3(0.15, 0.17, 0.02), pos + bs * Vector3(0.2, -0.1, 0.04), 0.008, HAZ_K, 4)
	_rod(s, pos + bs * Vector3(0.2, -0.1, 0.04), pos + bs * Vector3(0.17, -0.26, 0.05), 0.014, Color(0.2, 0.3, 0.8), 5)
	var l := _label("FLOOR\nSERVICE LOG", 28, 0.0016, Color(0.1, 0.1, 0.15), pos + bs * Vector3(0, 0.12, 0.03), yaw)
	l.outline_size = 0


## One side of the portal (sgn -1 left, +1 right): a full-height facade on the wall line, a low block behind it that
## covers the sliver of floor the notch leaves outside the car (its top just above the room's wall caps), and the
## car's thin side wall.
func _jamb(s: LowPoly.Soup, sgn: float, h: float, facade: Color, low: Color, car_wall: Color) -> void:
	var x0 := CAR_HALF - 0.03
	var fd := 0.3
	_b(s, Vector3(JAMB_OUT - x0, h, fd), Vector3(sgn * (JAMB_OUT + x0) * 0.5, h * 0.5, FRONT - fd * 0.5), facade)
	var back := -CAR_DEPTH - 0.12
	var zf := FRONT - fd
	_b(s, Vector3(2.66 - x0, 1.58, zf - back), Vector3(sgn * (2.66 + x0) * 0.5, 0.79, (zf + back) * 0.5), low)
	_b(s, Vector3(0.08, 3.25, zf - back), Vector3(sgn * (x0 + 0.04), 1.625, (zf + back) * 0.5), car_wall)


# --------------------------------------------------------------------------- service, wall

func _service_wall(s: LowPoly.Soup) -> void:
	var cz := -CAR_DEPTH * 0.5
	# the car: diamond-plate floor with scuffs, kick plates, the back wall
	_b(s, Vector3(2.0 * CAR_HALF, 0.06, CAR_DEPTH), Vector3(0, 0.03, cz), PLATE)
	for p: Vector3 in [Vector3(-0.8, 0.062, -0.5), Vector3(0.5, 0.062, -1.0), Vector3(0.9, 0.062, -0.3), Vector3(-0.2, 0.062, -1.2)]:
		_b(s, Vector3(0.5, 0.004, 0.22), p, PLATE.lightened(0.18), Vector3(0, 25.0 * p.x, 0))
	_b(s, Vector3(2.0 * CAR_HALF + 0.02, 3.4, 0.12), Vector3(0, 1.7, -CAR_DEPTH - 0.06), STEEL)
	_b(s, Vector3(2.0 * CAR_HALF, 0.36, 0.03), Vector3(0, 0.24, -CAR_DEPTH + 0.015), STEEL_LT)
	# jambs (they are also the car's side walls): dark steel with a hazard-striped front edge
	for sgn in [-1.0, 1.0]:
		_jamb(s, sgn, 3.02, STEEL_DK, STEEL_DK, STEEL)
		_b(s, Vector3(0.03, 0.36, CAR_DEPTH), Vector3(sgn * (CAR_HALF - 0.045), 0.24, cz), STEEL_LT)
		_stripes(s, _face(Vector3(sgn * (CAR_HALF + 0.12), 1.5, FRONT + 0.004), 0.0) * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO),
				3.0, 0.26, 11)
		# a rust streak under the hinge bolts
		_b(s, Vector3(0.1, 0.5, 0.006), Vector3(sgn * 2.45, 0.6, FRONT + 0.004), RUST)
		for y in [0.5, 1.5, 2.5]:
			_cyl(s, 0.03, 0.03, 0.03, 6, Vector3(sgn * 2.62, y, FRONT + 0.01), STEEL_LT, Vector3(90, 0, 0))
	# the gate's top and bottom tracks
	_b(s, Vector3(2.0 * CAR_HALF, 0.06, 0.08), Vector3(0, 2.78, -0.06), STEEL_DK)
	# the sill: a steel threshold with stripes on top
	_b(s, Vector3(2.0 * CAR_HALF + 0.1, 0.07, 0.2), Vector3(0, 0.035, FRONT - 0.08), STEEL_LT)
	_stripes(s, _floor_xf(Vector3(0, 0.072, FRONT - 0.1)), 2.0 * CAR_HALF, 0.12, 14)
	# the header: steel box, a striped band, the dial in the middle, stencils either side
	_b(s, Vector3(2.0 * JAMB_OUT, 0.7, 0.36), Vector3(0, 3.35, FRONT - 0.18), STEEL_DK)
	_stripes(s, _face(Vector3(0, 3.08, FRONT + 0.004)), 2.0 * JAMB_OUT, 0.14, 22)
	_cyl(s, 0.38, 0.38, 0.06, 12, Vector3(0, 3.36, FRONT + 0.03), STEEL_LT, Vector3(90, 0, 0))
	_gauge(s, Vector3(0, 3.36, FRONT + 0.065), 0.30, 0.0, Color(0.92, 0.9, 0.82), false)
	_label("FREIGHT", 64, 0.0052, HAZ_Y, Vector3(-1.55, 3.42, FRONT + 0.005))
	_label("CREW ONLY", 64, 0.0048, HAZ_Y, Vector3(1.6, 3.42, FRONT + 0.005))
	# the shaft above: guide rails on the back wall, a headframe beam with the sheave, cables down to the crosshead
	for sgn in [-1.0, 1.0]:
		_b(s, Vector3(0.12, 4.9, 0.12), Vector3(sgn * 1.5, 2.45, -CAR_DEPTH + 0.02), STEEL_LT)
		_b(s, Vector3(0.08, 3.2, 0.12), Vector3(sgn * (CAR_HALF - 0.08), 1.62, cz), STEEL)
	_b(s, Vector3(3.3, 0.18, 0.2), Vector3(0, 4.9, -CAR_DEPTH + 0.02), FRAME_Y)
	_cyl(s, 0.32, 0.32, 0.12, 12, Vector3(0, 4.62, -CAR_DEPTH + 0.18), STEEL_DK, Vector3(90, 0, 0))
	_cyl(s, 0.1, 0.1, 0.16, 8, Vector3(0, 4.62, -CAR_DEPTH + 0.18), FRAME_Y, Vector3(90, 0, 0))
	_b(s, Vector3(2.0 * CAR_HALF - 0.1, 0.16, 0.18), Vector3(0, 3.22, cz), FRAME_Y)
	for x in [-0.1, 0.0, 0.1]:
		_rod(s, Vector3(x, 3.3, cz), Vector3(x * 0.6, 4.35, -CAR_DEPTH + 0.18), 0.014, HAZ_K, 4)
	# the caged lamp under the crosshead
	_cyl(s, 0.1, 0.13, 0.08, 8, Vector3(0, 3.1, cz), STEEL_DK)
	PropModels.ball(s, Vector3(0.09, 0.11, 0.09), Vector3(0, 2.98, cz), _g(LAMP_COOL), 0, 0.0)
	for a in 4:
		var d := Vector3(cos(a * PI * 0.5), 0, sin(a * PI * 0.5)) * 0.12
		_rod(s, Vector3(0, 3.08, cz) + d, Vector3(0, 2.86, cz) + d * 0.6, 0.008, STEEL_DK, 3)
	# moving blankets: back wall and the right-hand side wall, quilted
	_quilt(s, Vector3(0, 1.45, -CAR_DEPTH + 0.05), Vector2(2.7, 2.1), 0.0)
	_quilt(s, Vector3(CAR_HALF - 0.08, 1.35, -0.8), Vector2(1.15, 1.8), -90.0)
	# the call box on the right jamb: up (lit green), down (dark), a conduit up to the header
	_b(s, Vector3(0.26, 0.46, 0.08), Vector3(2.3, 1.15, FRONT + 0.04), STEEL_LT)
	_b(s, Vector3(0.2, 0.06, 0.01), Vector3(2.3, 1.33, FRONT + 0.085), HAZ_Y)
	_cyl(s, 0.06, 0.06, 0.04, 10, Vector3(2.3, 1.2, FRONT + 0.09), _g(GO), Vector3(90, 0, 0))
	_cyl(s, 0.06, 0.06, 0.04, 10, Vector3(2.3, 1.03, FRONT + 0.09), Color(0.35, 0.08, 0.06), Vector3(90, 0, 0))
	_rod(s, Vector3(2.3, 1.38, FRONT + 0.02), Vector3(2.3, 3.0, FRONT + 0.02), 0.025, STEEL)
	# the floor service log on a nail on the left jamb
	_clipboard(s, Vector3(-2.28, 1.25, FRONT + 0.02))
	# a worn steel floor plate in front of the car (the crew's landing), striped front edge
	_b(s, Vector3(3.9, 0.02, 1.1), Vector3(0, 0.01, FRONT + 0.6), PLATE.darkened(0.15))
	_stripes(s, _floor_xf(Vector3(0, 0.022, FRONT + 1.08)), 3.9, 0.14, 18)


## A quilted moving blanket: a padded slab with darker stitch lines. `yaw` turns it (0 = facing +Z).
func _quilt(s: LowPoly.Soup, pos: Vector3, size: Vector2, yaw: float) -> void:
	var bs := Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0))
	_b(s, Vector3(size.x, size.y, 0.07), pos, BLANKET, Vector3(0, yaw, 0))
	var nx := maxi(2, int(size.x / 0.45))
	var ny := maxi(2, int(size.y / 0.45))
	for i in range(1, nx):
		_b(s, Vector3(0.02, size.y, 0.012), pos + bs * Vector3(-size.x * 0.5 + i * size.x / nx, 0, 0.04), BLANKET_DK, Vector3(0, yaw, 0))
	for j in range(1, ny):
		_b(s, Vector3(size.x, 0.02, 0.012), pos + bs * Vector3(0, -size.y * 0.5 + j * size.y / ny, 0.04), BLANKET_DK, Vector3(0, yaw, 0))
	# the hanging grommets
	for i in 3:
		_cyl(s, 0.03, 0.03, 0.02, 6, pos + bs * Vector3(-size.x * 0.4 + i * size.x * 0.4, size.y * 0.5 - 0.05, 0.05), STEEL_LT, Vector3(90, yaw, 0))


# --------------------------------------------------------------------------- fancy, wall

func _fancy_wall(s: LowPoly.Soup) -> void:
	var cz := -CAR_DEPTH * 0.5
	var open_half := 1.45
	# the car: wood floor, a runner carpet with a gold border, panelled walls, a mirror, a brass rail
	_b(s, Vector3(2.0 * CAR_HALF, 0.05, CAR_DEPTH), Vector3(0, 0.025, cz), WOOD_DK)
	_b(s, Vector3(2.6, 0.02, 1.15), Vector3(0, 0.06, cz - 0.05), PropModels.GOLD_DK)
	_b(s, Vector3(2.48, 0.024, 1.03), Vector3(0, 0.062, cz - 0.05), CARPET)
	_b(s, Vector3(2.0 * CAR_HALF + 0.02, 3.4, 0.12), Vector3(0, 1.7, -CAR_DEPTH - 0.06), WOOD)
	for i in 3:
		_b(s, Vector3(1.0, 2.6, 0.03), Vector3(-1.12 + i * 1.12, 1.5, -CAR_DEPTH + 0.015), WOOD_DK)
	_b(s, Vector3(0.9, 1.7, 0.02), Vector3(0, 1.6, -CAR_DEPTH + 0.035), MIRROR)
	_rod(s, Vector3(-1.62, 0.95, -CAR_DEPTH + 0.12), Vector3(1.62, 0.95, -CAR_DEPTH + 0.12), 0.03, BRASS, 6)
	for sgn in [-1.0, 1.0]:
		_jamb(s, sgn, 2.9, MARBLE_K, MARBLE_K, WOOD)
		_b(s, Vector3(0.03, 2.6, CAR_DEPTH - 0.1), Vector3(sgn * (CAR_HALF - 0.045), 1.35, cz - 0.05), WOOD)
		_rod(s, Vector3(sgn * (CAR_HALF - 0.1), 0.95, -CAR_DEPTH + 0.12), Vector3(sgn * (CAR_HALF - 0.1), 0.95, -0.25), 0.03, BRASS, 6)
		# the surround narrows the opening; brass trims on the opening edges and the outer pilasters
		_b(s, Vector3(CAR_HALF - open_half + 0.04, 2.9, 0.12), Vector3(sgn * (open_half + CAR_HALF + 0.04) * 0.5, 1.45, FRONT - 0.06), MARBLE_K)
		_b(s, Vector3(0.06, 2.82, 0.16), Vector3(sgn * open_half, 1.41, FRONT - 0.06), BRASS)
		_b(s, Vector3(0.1, 2.9, 0.16), Vector3(sgn * (JAMB_OUT - 0.08), 1.45, FRONT - 0.04), BRASS_DK)
		# deco fluting: brass lines up the surround and the facade, a brass chevron at the top
		for v in 3:
			_b(s, Vector3(0.018, 2.5, 0.006), Vector3(sgn * (1.55 + v * 0.07), 1.3, FRONT + 0.003), BRASS_DK)
		for v in 2:
			_b(s, Vector3(0.022, 2.6, 0.006), Vector3(sgn * (1.95 + v * 0.62), 1.35, FRONT + 0.003), BRASS_DK)
		_b(s, Vector3(0.5, 0.03, 0.006), Vector3(sgn * 2.2, 2.72, FRONT + 0.004), BRASS, Vector3(0, 0, sgn * 25.0))
		_b(s, Vector3(0.5, 0.03, 0.006), Vector3(sgn * 2.2, 2.6, FRONT + 0.004), BRASS, Vector3(0, 0, sgn * 25.0))
		# a brass wall sconce on each pilaster
		_b(s, Vector3(0.16, 0.24, 0.08), Vector3(sgn * 2.3, 2.25, FRONT + 0.04), BRASS_DK)
		_sector(s, _face(Vector3(sgn * 2.3, 2.3, FRONT + 0.085)), 0.0, 0.13, 180.0, 0.0, 5, _g(LAMP_WARM))
	# the sill: brass
	_b(s, Vector3(2.0 * CAR_HALF + 0.1, 0.06, 0.2), Vector3(0, 0.03, FRONT - 0.08), BRASS_DK)
	# the crown: a stepped art-deco header with the fan indicator rising out of it
	_b(s, Vector3(2.0 * JAMB_OUT, 0.36, 0.34), Vector3(0, 3.08, FRONT - 0.17), MARBLE_K)
	_b(s, Vector3(2.0 * JAMB_OUT + 0.02, 0.05, 0.36), Vector3(0, 2.9, FRONT - 0.16), BRASS)
	_b(s, Vector3(2.0 * JAMB_OUT + 0.02, 0.04, 0.36), Vector3(0, 3.28, FRONT - 0.16), BRASS_DK)
	_b(s, Vector3(3.2, 0.24, 0.3), Vector3(0, 3.4, FRONT - 0.18), MARBLE_K)
	_b(s, Vector3(1.7, 0.22, 0.26), Vector3(0, 3.63, FRONT - 0.19), MARBLE_K)
	_b(s, Vector3(3.22, 0.03, 0.32), Vector3(0, 3.52, FRONT - 0.18), BRASS)
	_gauge(s, Vector3(0, 3.28, FRONT + 0.03), 0.74, 0.0, BRASS, true)
	# "LIFT" in brass letters on the band, either side of the fan
	_label("LIFT", 80, 0.0055, BRASS, Vector3(-1.75, 3.09, FRONT + 0.005))
	_label("LIFT", 80, 0.0055, BRASS, Vector3(1.75, 3.09, FRONT + 0.005))
	# the shaft behind: brass-capped rails and a slim crosshead with the cables (it reads as a lift from above)
	for sgn in [-1.0, 1.0]:
		_b(s, Vector3(0.1, 4.3, 0.1), Vector3(sgn * 1.5, 2.15, -CAR_DEPTH + 0.02), MARBLE_K)
		_b(s, Vector3(0.14, 0.08, 0.14), Vector3(sgn * 1.5, 4.32, -CAR_DEPTH + 0.02), BRASS)
	_b(s, Vector3(2.0 * CAR_HALF - 0.1, 0.12, 0.12), Vector3(0, 3.3, cz - 0.1), BRASS_DK)
	for x in [-0.08, 0.08]:
		_rod(s, Vector3(x, 3.35, cz - 0.1), Vector3(x, 4.3, -CAR_DEPTH + 0.05), 0.012, HAZ_K, 4)
	# the ceiling lamp: a glowing deco bowl hanging under the crosshead
	_cyl(s, 0.22, 0.1, 0.12, 8, Vector3(0, 3.02, cz - 0.1), _g(LAMP_WARM))
	_cyl(s, 0.24, 0.24, 0.03, 8, Vector3(0, 3.09, cz - 0.1), BRASS)
	_rod(s, Vector3(0, 3.1, cz - 0.1), Vector3(0, 3.24, cz - 0.1), 0.015, BRASS, 4)
	# the call button: a brass plate with one round lit button
	_b(s, Vector3(0.2, 0.34, 0.03), Vector3(2.0, 1.15, FRONT + 0.015), BRASS)
	_cyl(s, 0.085, 0.085, 0.02, 12, Vector3(2.0, 1.18, FRONT + 0.035), BRASS_DK, Vector3(90, 0, 0))
	_cyl(s, 0.06, 0.06, 0.03, 12, Vector3(2.0, 1.18, FRONT + 0.05), _g(LAMP_WARM), Vector3(90, 0, 0))
	# the floor service log, on a brass hook on the left pilaster
	_clipboard(s, Vector3(-2.0, 1.2, FRONT + 0.03))
	# a little brass threshold plate in front (the landing)
	_b(s, Vector3(2.6, 0.015, 0.5), Vector3(0, 0.008, FRONT + 0.3), BRASS_DK)


# --------------------------------------------------------------------------- service, column (freight platform lift)

const SHAFT_APOTHEM := 1.5    ## a hexagonal car's side lies this far from its middle (the midpoint-wall line)
const FRAME_TOP := 3.9        ## the hoist frame's top ring


## The middle of side k of a hexagonal car (between corners k and k + 1) at height y, and its outward yaw (degrees).
## Side 5 (corners 5 and 0) is the door side, facing +Z.
static func _side(k: int, y: float, out: float = SHAFT_APOTHEM) -> Array:
	var yaw := 60.0 * float(k + 1)
	var bs := Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0))
	return [bs * Vector3(0, y, out), yaw]


func _service_column(s: LowPoly.Soup) -> void:
	# the dark gap round the deck (the platform rides in a hexagonal hole in the floor) and the hex deck: diamond plate,
	# scuffs, a hazard-striped edge along every side
	_cyl(s, SHAFT_R + 0.22, SHAFT_R + 0.22, 0.012, 6, Vector3(0, 0.006, 0), Color(0.03, 0.025, 0.03))
	_cyl(s, SHAFT_R - 0.02, SHAFT_R - 0.02, 0.06, 6, Vector3(0, 0.03, 0), PLATE)
	for p: Vector3 in [Vector3(-0.6, 0.062, 0.3), Vector3(0.5, 0.062, -0.55), Vector3(0.15, 0.062, 0.8)]:
		_b(s, Vector3(0.55, 0.004, 0.22), p, PLATE.lightened(0.18), Vector3(0, 30.0 * p.x, 0))
	for k in 6:
		var sd := _side(k, 0.062, SHAFT_APOTHEM - 0.12)
		_stripes(s, _floor_xf(sd[0], sd[1]), 1.45, 0.16, 8)
	# the hoist frame: a yellow post on every corner (on the neighbour centres), a top ring, a cross beam with the
	# motor, the sheave and an amber beacon
	for k in 6:
		var p := _corner(k)
		_b(s, Vector3(0.18, FRAME_TOP, 0.18), p + Vector3(0, FRAME_TOP * 0.5, 0), FRAME_Y, Vector3(0, 30.0 + 60.0 * k, 0))
		_b(s, Vector3(0.28, 0.1, 0.28), p + Vector3(0, 0.05, 0), STEEL_DK, Vector3(0, 30.0 + 60.0 * k, 0))
		var sd := _side(k, FRAME_TOP, SHAFT_APOTHEM)
		_b(s, Vector3(SHAFT_R + 0.16, 0.2, 0.18), sd[0], FRAME_Y, Vector3(0, sd[1], 0))
	for k in [0, 5]:
		# hazard stripes up the two door posts
		var p := _corner(k)
		_stripes(s, _face(p + Vector3(0, 0.6, 0.095), 0.0) * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO), 1.0, 0.16, 5)
	_b(s, Vector3(2.0 * SHAFT_R, 0.2, 0.22), Vector3(0, FRAME_TOP, 0), FRAME_Y)
	_b(s, Vector3(0.7, 0.45, 0.5), Vector3(-0.85, FRAME_TOP + 0.32, 0), STEEL_DK)
	_cyl(s, 0.36, 0.36, 0.14, 12, Vector3(0, FRAME_TOP - 0.18, 0.3), STEEL_DK, Vector3(0, 0, 90))
	_cyl(s, 0.12, 0.12, 0.2, 8, Vector3(0, FRAME_TOP - 0.18, 0.3), FRAME_Y, Vector3(0, 0, 90))
	_cyl(s, 0.1, 0.08, 0.18, 8, _corner(0) + Vector3(0, FRAME_TOP + 0.2, 0), _g(WARN))
	# the platform's own yoke: two stiles and a crossbeam, cables up to the sheave
	for sx in [-1.0, 1.0]:
		_b(s, Vector3(0.12, 2.5, 0.16), Vector3(sx * 1.38, 1.3, 0), STEEL)
	_b(s, Vector3(2.9, 0.16, 0.2), Vector3(0, 2.55, 0), STEEL)
	for x in [-0.1, 0.0, 0.1]:
		_rod(s, Vector3(x, 2.63, 0), Vector3(x * 0.5, FRAME_TOP - 0.3, 0.3), 0.016, HAZ_K, 4)
	# the caged work lamp under the crossbeam
	_cyl(s, 0.1, 0.13, 0.08, 8, Vector3(0, 2.43, 0), STEEL_DK)
	PropModels.ball(s, Vector3(0.09, 0.11, 0.09), Vector3(0, 2.31, 0), _g(LAMP_COOL), 0, 0.0)
	# railings on the five closed sides (a mid post, a mid rail and a top rail), on the solid lines ElevatorGeo blocks
	for k in 5:
		var a := _corner(k) * 0.97
		var b := _corner(k + 1) * 0.97
		var m := (a + b) * 0.5
		_b(s, Vector3(0.06, 1.1, 0.06), m + Vector3(0, 0.6, 0), FRAME_Y)
		for y in [0.6, 1.15]:
			_rod(s, a + Vector3(0, y, 0), b + Vector3(0, y, 0), 0.03, FRAME_Y, 5)
		_b(s, Vector3(SHAFT_R - 0.3, 0.12, 0.02), m + Vector3(0, 0.12, 0), HAZ_K, Vector3(0, 60.0 * float(k + 1), 0))
	# the control pendant hanging off the right stile
	_rod(s, Vector3(1.38, 2.1, 0.1), Vector3(1.2, 1.2, 0.35), 0.012, HAZ_K, 4)
	_b(s, Vector3(0.12, 0.26, 0.08), Vector3(1.2, 1.07, 0.35), FRAME_Y)
	_cyl(s, 0.03, 0.03, 0.02, 6, Vector3(1.2, 1.12, 0.4), _g(GO), Vector3(90, 0, 0))
	_cyl(s, 0.03, 0.03, 0.02, 6, Vector3(1.2, 1.02, 0.4), STOP.darkened(0.5), Vector3(90, 0, 0))
	# the dial hanging under the front top beam, the stencils on the two beams beside it
	_cyl(s, 0.38, 0.38, 0.06, 12, Vector3(0, 3.5, SHAFT_APOTHEM + 0.18), STEEL_LT, Vector3(90, 0, 0))
	_gauge(s, Vector3(0, 3.5, SHAFT_APOTHEM + 0.215), 0.3, 0.0, Color(0.92, 0.9, 0.82), false)
	_b(s, Vector3(0.06, 0.3, 0.06), Vector3(0, 3.78, SHAFT_APOTHEM + 0.12), STEEL_DK)
	var left := _side(4, FRAME_TOP, SHAFT_APOTHEM + 0.095)
	var right := _side(0, FRAME_TOP, SHAFT_APOTHEM + 0.095)
	_label("FREIGHT", 56, 0.0042, HAZ_K, left[0], left[1])
	_label("CREW ONLY", 56, 0.0036, HAZ_K, right[0], right[1])
	# the call post at the front-right with the call box and the clipboard
	var cp := _corner(0) + Vector3(0.75, 0, 0.55)
	_b(s, Vector3(0.1, 1.5, 0.1), cp + Vector3(0, 0.75, 0), FRAME_Y)
	_b(s, Vector3(0.3, 0.08, 0.3), cp + Vector3(0, 0.04, 0), STEEL_DK)
	_b(s, Vector3(0.26, 0.4, 0.1), cp + Vector3(0, 1.25, 0.08), STEEL_LT)
	_cyl(s, 0.055, 0.055, 0.04, 10, cp + Vector3(0, 1.3, 0.14), _g(GO), Vector3(90, 0, 0))
	_cyl(s, 0.055, 0.055, 0.04, 10, cp + Vector3(0, 1.15, 0.14), Color(0.35, 0.08, 0.06), Vector3(90, 0, 0))
	_clipboard(s, cp + Vector3(0, 0.75, 0.07))


# --------------------------------------------------------------------------- fancy, column (glass shaft)

const SHAFT_R := 1.732     ## corner radius: the corners stand on the six neighbour centres
const SHAFT_H := 3.8

## Corner k of the shaft (k = 0..5), the door face is between corners 0 and 5 (facing +Z).
static func _corner(k: int, r: float = SHAFT_R) -> Vector3:
	var a := deg_to_rad(30.0 + 60.0 * k)
	return Vector3(sin(a) * r, 0, cos(a) * r)


func _fancy_column(s: LowPoly.Soup) -> void:
	# plinth and floor: black marble hex, brass edge, a round carpet
	_cyl(s, SHAFT_R + 0.14, SHAFT_R + 0.14, 0.05, 6, Vector3(0, 0.025, 0), MARBLE_K)
	_cyl(s, SHAFT_R + 0.18, SHAFT_R + 0.18, 0.02, 6, Vector3(0, 0.01, 0), BRASS_DK)
	_cyl(s, 1.1, 1.1, 0.02, 12, Vector3(0, 0.06, 0), CARPET)
	_cyl(s, 1.18, 1.18, 0.016, 12, Vector3(0, 0.055, 0), PropModels.GOLD_DK)
	# corner posts, top and bottom rings, an inside brass handrail on the five glass sides
	for k in 6:
		var a := _corner(k)
		var b := _corner((k + 1) % 6)
		_rod(s, a, a + Vector3(0, SHAFT_H, 0), 0.07, BRASS, 6)
		_rod(s, a + Vector3(0, 0.14, 0), b + Vector3(0, 0.14, 0), 0.05, BRASS_DK, 5)
		_rod(s, a + Vector3(0, SHAFT_H, 0), b + Vector3(0, SHAFT_H, 0), 0.07, BRASS, 6)
		_rod(s, a + Vector3(0, 2.55, 0), b + Vector3(0, 2.55, 0), 0.035, BRASS_DK, 5)
		if k != 5:
			_rod(s, a * 0.9 + Vector3(0, 0.95, 0), b * 0.9 + Vector3(0, 0.95, 0), 0.025, BRASS, 5)
	# the crown: an open frieze (a hollow ring, so the camera still sees into the car), the machine beam across the
	# top with its sheave, and the fan indicator standing on the frieze over the doors
	for k in 6:
		var a := _corner(k)
		var b := _corner((k + 1) % 6)
		var mid := (a + b) * 0.5
		var yaw := rad_to_deg(atan2(mid.x, mid.z))
		_b(s, Vector3((b - a).length() + 0.12, 0.26, 0.14), mid + Vector3(0, SHAFT_H + 0.12, 0), MARBLE_K, Vector3(0, yaw, 0))
		_b(s, Vector3((b - a).length() + 0.14, 0.04, 0.17), mid + Vector3(0, SHAFT_H + 0.27, 0), BRASS, Vector3(0, yaw, 0))
	_b(s, Vector3(2.0 * SHAFT_R, 0.14, 0.14), Vector3(0, SHAFT_H + 0.05, 0), BRASS_DK)
	_cyl(s, 0.24, 0.24, 0.08, 10, Vector3(0, SHAFT_H + 0.05, 0.12), BRASS, Vector3(90, 0, 0))
	var face_mid := (_corner(0) + _corner(5)) * 0.5
	_gauge(s, Vector3(0, SHAFT_H + 0.29, face_mid.z + 0.08), 0.58, 0.0, BRASS, true)
	# the car frame inside: a slim brass ring at the car top, cables up into the crown, a hanging lamp
	for k in 6:
		_rod(s, _corner(k, 1.45) + Vector3(0, 2.75, 0), _corner((k + 1) % 6, 1.45) + Vector3(0, 2.75, 0), 0.03, BRASS_DK, 4)
	for k in [0, 2, 4]:
		_rod(s, _corner(k, 1.45) + Vector3(0, 2.75, 0), Vector3(0, 3.0, 0), 0.02, BRASS_DK, 4)
	for x in [-0.07, 0.07]:
		_rod(s, Vector3(x, 3.0, 0), Vector3(x, SHAFT_H, 0), 0.012, HAZ_K, 4)
	_cyl(s, 0.2, 0.08, 0.14, 8, Vector3(0, 2.55, 0), _g(LAMP_WARM))
	_rod(s, Vector3(0, 2.62, 0), Vector3(0, 3.0, 0), 0.012, BRASS, 4)
	# the call pedestal (front-right) and the sign-in lectern with the log (front-left)
	var cp := _corner(0) + Vector3(0.75, 0, 0.55)
	_cyl(s, 0.16, 0.2, 0.06, 8, cp + Vector3(0, 0.03, 0), MARBLE_K)
	_cyl(s, 0.05, 0.05, 1.05, 6, cp + Vector3(0, 0.55, 0), BRASS)
	_b(s, Vector3(0.2, 0.26, 0.06), cp + Vector3(0, 1.15, 0), BRASS, Vector3(-20, 0, 0))
	_cyl(s, 0.055, 0.055, 0.03, 12, cp + Vector3(0, 1.17, 0.04), _g(LAMP_WARM), Vector3(70, 0, 0))
	var lp := _corner(5) + Vector3(-0.8, 0, 0.5)
	_b(s, Vector3(0.36, 0.08, 0.3), lp + Vector3(0, 0.04, 0), MARBLE_K)
	_b(s, Vector3(0.12, 0.95, 0.12), lp + Vector3(0, 0.5, 0), WOOD_DK)
	_b(s, Vector3(0.46, 0.05, 0.36), lp + Vector3(0, 1.0, 0), WOOD, Vector3(-25, 0, 0))
	_clipboard(s, lp + Vector3(0, 1.04, 0.0) + Vector3(0, 0.02, 0.02), 0.0)
	# a brass threshold on the door face
	_b(s, Vector3(1.75, 0.03, 0.22), Vector3(0, 0.06, face_mid.z), BRASS_DK)


func _add_glass() -> void:
	var g := LowPoly.Soup.new(SEED + 11, 0.0)
	for k in 5:
		var a := _corner(k)
		var b := _corner(k + 1)
		var inset := 0.0
		g.add_tri(a + Vector3(0, 0.15, inset), b + Vector3(0, 0.15, inset), b + Vector3(0, SHAFT_H, inset), Color.WHITE)
		g.add_tri(a + Vector3(0, 0.15, inset), b + Vector3(0, SHAFT_H, inset), a + Vector3(0, SHAFT_H, inset), Color.WHITE)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.6, 0.85, 0.9, 0.2)
	m.roughness = 0.05
	m.metallic = 0.3
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.rim_enabled = true
	m.rim = 0.6
	var mi := MeshInstance3D.new()
	mi.name = "Glass"
	mi.mesh = g.to_mesh(0.0)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	parts["Glass"] = mi


# --------------------------------------------------------------------------- doors

func _doors_soup(t: float) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(SEED + 21, 0.03)
	match [look, form]:
		["service", "wall"]:
			_scissor_gate(s, t)
		["fancy", "wall"]:
			var w := 1.47
			for sgn in [-1.0, 1.0]:
				var x: float = sgn * (w * 0.5 + t * (w - 0.08))
				_door_panel(s, Vector3(x, 1.42, FRONT - 0.18), w, 2.78, sgn)
		["service", "column"]:
			# the bar gate across the door side lifts up the two door posts
			var y := lerpf(0.0, 2.2, t)
			var w := SHAFT_R - 0.16
			for h in [0.6, 1.15]:
				var c := Vector3(0, h + y, SHAFT_APOTHEM - 0.02)
				_b(s, Vector3(w, 0.08, 0.06), c, HAZ_Y)
				_stripes(s, _face(c + Vector3(0, 0, 0.031)), w, 0.08, 7)
			for sx in [-1.0, 1.0]:
				_b(s, Vector3(0.07, 0.75, 0.07), Vector3(sx * (w * 0.5 - 0.04), 0.88 + y, SHAFT_APOTHEM - 0.02), FRAME_Y)
		_:
			# two brass panels on the door face; opening, each runs round the corner post to stand inside the
			# glass of the neighbouring face
			var a := _corner(5)
			var b := _corner(0)
			var mid := (a + b) * 0.5
			var along := (b - a).normalized()
			var w := (b - a).length() * 0.5
			for sgn in [-1.0, 1.0]:
				var closed: Vector3 = mid + along * sgn * (w * 0.5) + Vector3(0, 1.36, -0.04)
				var side_mid: Vector3 = ((_corner(1) + _corner(0)) * 0.5) if sgn > 0 else ((_corner(4) + _corner(5)) * 0.5)
				var open_pos: Vector3 = side_mid.normalized() * 1.36 + Vector3(0, 1.36, 0)
				var side_yaw := rad_to_deg(atan2(side_mid.x, side_mid.z))
				_door_panel(s, closed.lerp(open_pos, t), w - 0.04, 2.5, sgn, lerpf(0.0, side_yaw, t))
	return s


## A brass door panel (width w, height h) with a dark inlay and a deco chevron; `sgn` mirrors it, `yaw` turns it.
func _door_panel(s: LowPoly.Soup, c: Vector3, w: float, h: float, sgn: float, yaw: float = 0.0) -> void:
	var p := LowPoly.Soup.new(PropModels._n(), 0.03)
	_b(p, Vector3(w, h, 0.05), Vector3.ZERO, BRASS)
	_b(p, Vector3(w - 0.16, h - 0.2, 0.012), Vector3(0, 0, 0.03), BRASS_DK)
	_b(p, Vector3(w - 0.3, 0.04, 0.016), Vector3(0, -0.25, 0.035), BRASS)
	for i in 3:
		var y := 0.25 + i * 0.22
		_b(p, Vector3(0.04, w * 0.55, 0.016), Vector3(-sgn * 0.12, y, 0.035), BRASS, Vector3(0, 0, sgn * 55.0))
	_b(p, Vector3(0.03, h - 0.3, 0.02), Vector3(-sgn * (w * 0.5 - 0.06), 0, 0.04), BRASS.lightened(0.2))
	s.merge(p, LowPoly.at(c, Vector3(0, yaw, 0)))


## The scissor gate across the car mouth: bars on a lattice of crossed diagonals, folding to the left as it opens.
func _scissor_gate(s: LowPoly.Soup, t: float) -> void:
	var n := 10
	var x0 := -CAR_HALF + 0.1
	var full := 2.0 * CAR_HALF - 0.2
	var w := lerpf(full, 0.36, t)
	var step := w / (n - 1)
	var z := -0.06
	for i in n:
		var x := x0 + i * step
		_b(s, Vector3(0.04, 2.6, 0.04), Vector3(x, 1.39, z), STEEL_LT if i < n - 1 else HAZ_Y)
	for i in n - 1:
		var xa := x0 + i * step
		var xb := xa + step
		for tier in 3:
			var y0 := 0.14 + tier * 0.84
			var y1 := y0 + 0.84
			_rod(s, Vector3(xa, y0, z + 0.03), Vector3(xb, y1, z + 0.03), 0.014, STEEL, 4)
			_rod(s, Vector3(xa, y1, z + 0.05), Vector3(xb, y0, z + 0.05), 0.014, STEEL, 4)
	# the handle on the leading bar
	var xl := x0 + w
	_b(s, Vector3(0.05, 0.3, 0.08), Vector3(xl, 1.15, z + 0.08), HAZ_K)
