class_name VanModel
extends Node3D
## The crew's work van ("Licensed Budget Sorcery"): a beat-up, rust-streaked white-grey panel van with a roof rack
## (orange ladder, copper / PVC / ABS pipes, ratchet straps, a wand antenna), hose coils, a pipe wrench and a plunger on
## the sides, a sliding side door that opens, headlights that can glow, and a wand-and-wrench roundel with the company
## name on the doors. Faceted low-poly in the house style (LowPoly soup, MonsterMaterial: ink outline, amber rim,
## vertex alpha 0.5 = emissive face). About 2.0 wide x 4.2 long x 2.2 tall (VanPlan.W/L/H); origin at the centre of the
## footprint on the floor, the NOSE is +Z, the sliding door is on the -X side (it slides toward the rear, -Z).
##
##   var van := VanModel.new()
##   van.set_door_open(1.0)          # 0 closed .. 1 fully open (the door slides back along the body)
##   van.set_lights(1.0)             # headlights / tail lights glow (0 off)
##   van.set_bounce(-0.12, 0.0)      # chassis offset (y, world units) and body roll (radians): the suspension
##
## Parts (all MeshInstance3D unless noted): Chassis (Node3D) holds Body, Door, Lamps, InnerGlow, Signs and the two
## lights, and rides on the suspension; Wheels stay on the floor. Label3D text sits under Signs and under Door.

const LENGTH := 4.2
const WIDTH := 2.0
const HEIGHT := 2.2
const DOOR_TRAVEL := 1.3          ## how far the sliding door moves toward the rear when fully open
const DOOR_CLOSED_POS := Vector3(-1.095, 1.2, 0.4)
const SEED := 4107

const PAINT := Color(0.80, 0.81, 0.79)
const PAINT_LT := Color(0.89, 0.90, 0.88)
const PAINT_DK := Color(0.62, 0.63, 0.63)
const GRIME := Color(0.44, 0.42, 0.39)
const RUST := Color(0.56, 0.28, 0.13)
const RUST_LT := Color(0.69, 0.39, 0.17)
const RUST_DK := Color(0.37, 0.18, 0.10)
const TRIM := Color(0.20, 0.21, 0.24)
const TRIM_LT := Color(0.34, 0.35, 0.40)
const GLASS := Color(0.16, 0.23, 0.33)
const GLASS_LT := Color(0.38, 0.54, 0.66)
const TYRE := Color(0.09, 0.09, 0.10)
const HUB := Color(0.58, 0.60, 0.66)
const STRIPE := Color(0.46, 0.30, 0.76)
const NAVY := Color(0.12, 0.13, 0.30)
const AMBER := Color(1.0, 0.66, 0.20)
const CREAM := Color(0.97, 0.91, 0.74)
const LADDER := Color(0.93, 0.52, 0.10)
const COPPER := Color(0.80, 0.46, 0.26)
const PVC := Color(0.89, 0.89, 0.85)
const ABS := Color(0.14, 0.14, 0.16)
const HOSE := Color(0.22, 0.60, 0.30)
const HOSE_Y := Color(0.95, 0.76, 0.16)
const STRAP := Color(0.96, 0.78, 0.14)
const INNER := Color(0.12, 0.10, 0.15)
const INNER_FLOOR := Color(0.30, 0.29, 0.33)
const VIOLET := Color(0.72, 0.42, 1.0)

var parts: Dictionary = {}                ## name -> MeshInstance3D
var chassis: Node3D
var door: MeshInstance3D
var _lamp_mat: ShaderMaterial
var _inner_mat: ShaderMaterial
var _head_light: OmniLight3D
var _inner_light: OmniLight3D
var _door_open := 0.0
var _lights := 0.0


func _init() -> void:
	name = "Van"
	PropModels._seed = SEED
	chassis = Node3D.new()
	chassis.name = "Chassis"
	add_child(chassis)
	_add_mesh("Body", _body_soup(), chassis, Vector3.ZERO, _material())
	door = _add_mesh("Door", _door_soup(), chassis, DOOR_CLOSED_POS, _material())
	_lamp_mat = _glow_material(1.8)
	_add_mesh("Lamps", _lamps_soup(), chassis, Vector3.ZERO, _lamp_mat)
	_inner_mat = _glow_material(2.2)
	_add_mesh("InnerGlow", _inner_glow_soup(), chassis, Vector3.ZERO, _inner_mat)
	_add_mesh("Wheels", _wheels_soup(), self, Vector3.ZERO, _material())
	_add_signs()
	_head_light = OmniLight3D.new()
	_head_light.name = "HeadLight"
	_head_light.position = Vector3(0, 1.0, 2.9)
	_head_light.light_color = Color(1.0, 0.92, 0.7)
	_head_light.omni_range = 5.5
	_head_light.omni_attenuation = 1.6
	_head_light.light_specular = 0.0
	_head_light.light_energy = 0.0
	_head_light.shadow_enabled = false
	chassis.add_child(_head_light)
	_inner_light = OmniLight3D.new()
	_inner_light.name = "InnerLight"
	_inner_light.position = Vector3(-0.2, 1.4, 0.2)
	_inner_light.light_color = Color(0.66, 0.4, 1.0)
	_inner_light.omni_range = 3.2
	_inner_light.omni_attenuation = 1.4
	_inner_light.light_specular = 0.0
	_inner_light.light_energy = 0.0
	_inner_light.shadow_enabled = false
	chassis.add_child(_inner_light)
	set_door_open(0.0)
	set_lights(0.0)


# --------------------------------------------------------------------------- state

## 0 = closed, 1 = fully open: the door slides toward the rear along the body; the cargo glows violet as it opens.
func set_door_open(t: float) -> void:
	_door_open = clampf(t, 0.0, 1.0)
	door.position = DOOR_CLOSED_POS + Vector3(0.0, 0.0, -DOOR_TRAVEL * _door_open)
	_inner_mat.set_shader_parameter("glow_gain", 2.2 * _door_open)
	_inner_light.light_energy = 1.8 * _door_open


func door_open_amount() -> float:
	return _door_open


## 0 = lights off, 1 = full glow (headlights, tail lights; the front light pools on the floor ahead of the nose).
func set_lights(t: float) -> void:
	_lights = clampf(t, 0.0, 1.0)
	_lamp_mat.set_shader_parameter("glow_gain", 2.6 * _lights)
	_head_light.light_energy = 2.4 * _lights


func lights_amount() -> float:
	return _lights


## The suspension: chassis height offset (world units, negative = compressed) and a roll about the nose axis (radians).
func set_bounce(y: float, pitch: float = 0.0) -> void:
	chassis.position.y = y
	chassis.rotation.x = pitch


## Total triangle count over all meshes (tests, budgets).
func triangle_count() -> int:
	var n := 0
	for p: MeshInstance3D in parts.values():
		var arrays := p.mesh.surface_get_arrays(0)
		n += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _add_mesh(part_name: String, soup: LowPoly.Soup, parent: Node3D, pos: Vector3, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = soup.to_mesh()
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	parts[part_name] = mi
	return mi


static func _material() -> ShaderMaterial:
	var m := MonsterMaterial.make(2.3)
	m.set_shader_parameter("glow_gain", 1.5)
	return m


static func _glow_material(gain: float) -> ShaderMaterial:
	var m := MonsterMaterial.make(2.0)
	m.set_shader_parameter("glow_gain", gain)
	return m


# --------------------------------------------------------------------------- soup helpers

static func _b(s: LowPoly.Soup, size: Vector3, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO, jit: float = 0.0) -> void:
	PropModels.box(s, size, pos, col, rot, jit)


## A box with its faces subdivided so the jitter dents it (panels that took a few knocks).
static func _dented(s: LowPoly.Soup, size: Vector3, pos: Vector3, col: Color, jit: float, seg: int = 2) -> void:
	PropModels._seed += 1
	s.merge(LowPoly.box(size, col, PropModels._seed, jit, seg, 0.06), LowPoly.at(pos))


static func _cyl(s: LowPoly.Soup, r_bottom: float, r_top: float, h: float, sides: int, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
	PropModels.cyl(s, r_bottom, r_top, h, sides, pos, col, rot)


static func _rod(s: LowPoly.Soup, a: Vector3, b: Vector3, r: float, sides: int, col: Color) -> void:
	PropModels.rod(s, a, b, r, r, sides, col)


## A thin decal slab on the side face at x = side * 1.0: u runs along the van (+Z nose), v is height; wu x wv in size,
## `rot` turns it about the face normal (degrees) and `lift` stacks decals (each layer a hair proud of the last).
static func _decal(s: LowPoly.Soup, side: float, u: float, v: float, wu: float, wv: float, col: Color, rot: float = 0.0, lift: float = 0.0) -> void:
	var thick := 0.014
	_b(s, Vector3(thick, wv, wu), Vector3(side * (1.0 + thick * 0.5 + lift), v, u), col, Vector3(rot, 0, 0))


## A flat round decal on a side face (axis along X).
static func _disc(s: LowPoly.Soup, side: float, u: float, v: float, r: float, col: Color, lift: float = 0.0) -> void:
	_cyl(s, r, r, 0.014, 12, Vector3(side * (1.0 + 0.007 + lift), v, u), col, Vector3(0, 0, 90))


# --------------------------------------------------------------------------- the body

func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(SEED, 0.055)
	_shell(s)
	_cab(s)
	_front_and_rear(s)
	_roof_and_rack(s)
	_side_details(s)
	_wear(s)
	_cargo_interior(s)
	return s


## Cargo box as slabs around the door opening on the -X side (so the open door shows a real interior).
func _shell(s: LowPoly.Soup) -> void:
	var y0 := 0.5
	var y1 := 1.9
	# roof, floor, rear, +X wall, -X rear segment, header over the door, pillar in front of it
	_dented(s, Vector3(2.0, 0.12, 3.05), Vector3(0, y1 - 0.06, -0.525), PAINT_LT, 0.012, 3)
	_b(s, Vector3(2.0, 0.12, 3.05), Vector3(0, y0 + 0.06, -0.525), TRIM)
	_dented(s, Vector3(2.0, 1.4, 0.1), Vector3(0, (y0 + y1) * 0.5, -2.0), PAINT, 0.012)
	_dented(s, Vector3(0.08, 1.4, 3.05), Vector3(0.96, (y0 + y1) * 0.5, -0.525), PAINT, 0.014, 3)
	_dented(s, Vector3(0.08, 1.4, 1.9), Vector3(-0.96, (y0 + y1) * 0.5, -1.1), PAINT, 0.012, 3)
	_b(s, Vector3(0.08, 0.1, 1.2), Vector3(-0.96, 1.85, 0.4), PAINT_LT)
	_b(s, Vector3(0.08, 1.4, 0.1), Vector3(-0.96, (y0 + y1) * 0.5, 0.99), PAINT)


## The cab: lower body + hood, the sloped windscreen, side windows, door seams.
func _cab(s: LowPoly.Soup) -> void:
	_dented(s, Vector3(2.0, 0.7, 1.05), Vector3(0, 0.85, 1.525), PAINT, 0.012)        # lower cab and hood (z 1.0 .. 2.05)
	# cabin: a frustum rising from the belt line to the roof, its top flush with the cargo roof
	s.merge(LowPoly.frustum(Vector2(2.0, 0.8), Vector2(1.98, 0.38), 0.7, PAINT_LT, SEED + 11, 0.0, 1, Vector2(0, -0.21), 0.05),
			LowPoly.at(Vector3(0, 1.55, 1.4)))
	# windscreen on the slope from (z 1.39, y 1.9) down to (z 1.8, y 1.2)
	_b(s, Vector3(1.76, 0.82, 0.04), Vector3(0, 1.55, 1.6), GLASS, Vector3(-30, 0, 0))
	_b(s, Vector3(0.08, 0.7, 0.045), Vector3(0.45, 1.55, 1.605), GLASS_LT, Vector3(-30, 0, 18))
	_b(s, Vector3(0.05, 0.6, 0.045), Vector3(0.62, 1.55, 1.605), GLASS_LT, Vector3(-30, 0, 18))
	_b(s, Vector3(0.9, 0.035, 0.04), Vector3(0.15, 1.32, 1.76), TRIM, Vector3(-30, 0, 4))      # wiper
	# side windows (both sides) and door seams
	for side: float in [-1.0, 1.0]:
		_b(s, Vector3(0.03, 0.34, 0.46), Vector3(side * 0.995, 1.44, 1.28), GLASS)
		_b(s, Vector3(0.034, 0.14, 0.14), Vector3(side * 0.997, 1.52, 1.12), GLASS_LT)
		_b(s, Vector3(0.03, 0.62, 0.025), Vector3(side * 0.998, 1.42, 1.64), TRIM)           # B-pillar seams
		_b(s, Vector3(0.03, 0.74, 0.025), Vector3(side * 0.998, 1.0, 1.06), TRIM)
		_b(s, Vector3(0.03, 0.025, 0.58), Vector3(side * 0.998, 0.66, 1.34), TRIM)
		_b(s, Vector3(0.04, 0.05, 0.2), Vector3(side * 1.0, 1.1, 1.52), TRIM_LT)             # handle
		_b(s, Vector3(0.12, 0.1, 0.08), Vector3(side * 1.07, 1.18, 1.85), PAINT_DK)          # wing mirror
		_b(s, Vector3(0.04, 0.11, 0.06), Vector3(side * 1.1, 1.18, 1.85), TRIM)


func _front_and_rear(s: LowPoly.Soup) -> void:
	# front: grille, bumper, plate, the (dark) lamp housings the Lamps mesh sits in
	_b(s, Vector3(1.5, 0.34, 0.05), Vector3(0, 0.88, 2.06), TRIM)
	for i in 5:
		_b(s, Vector3(1.4, 0.025, 0.06), Vector3(0, 0.76 + 0.07 * float(i), 2.07), TRIM_LT)
	_b(s, Vector3(0.52, 0.3, 0.05), Vector3(-0.72, 0.9, 2.055), TRIM)
	_b(s, Vector3(0.52, 0.3, 0.05), Vector3(0.72, 0.9, 2.055), TRIM)
	_b(s, Vector3(2.08, 0.22, 0.2), Vector3(0, 0.56, 2.0), TRIM)
	_b(s, Vector3(2.0, 0.07, 0.22), Vector3(0, 0.66, 2.0), PAINT_DK)
	_b(s, Vector3(0.5, 0.2, 0.03), Vector3(0, 0.52, 2.13), PAINT_LT)
	_b(s, Vector3(0.36, 0.03, 0.035), Vector3(0, 0.54, 2.145), TRIM)
	_b(s, Vector3(1.9, 0.07, 0.3), Vector3(0, 1.22, 1.9), PAINT_LT)                           # hood lip
	# rear: doors with a seam, handles, a step bumper, plate, spare roll, the wand-in-a-tube
	_b(s, Vector3(0.03, 1.2, 0.03), Vector3(0, 1.2, -2.06), TRIM)
	_b(s, Vector3(0.12, 0.05, 0.05), Vector3(-0.1, 1.15, -2.07), TRIM_LT)
	_b(s, Vector3(0.12, 0.05, 0.05), Vector3(0.1, 1.15, -2.07), TRIM_LT)
	_b(s, Vector3(2.08, 0.26, 0.3), Vector3(0, 0.56, -2.04), TRIM)
	_b(s, Vector3(1.9, 0.06, 0.34), Vector3(0, 0.7, -2.04), TRIM_LT)
	_b(s, Vector3(0.5, 0.24, 0.03), Vector3(0, 0.88, -2.07), PAINT_LT)
	_b(s, Vector3(0.38, 0.04, 0.035), Vector3(-0.03, 0.9, -2.09), TRIM)
	for sx: float in [-1.0, 1.0]:
		_b(s, Vector3(0.2, 0.6, 0.05), Vector3(sx * 0.9, 1.15, -2.045), TRIM)                # tail light housings
		_b(s, Vector3(0.3, 0.12, 0.05), Vector3(sx * 0.82, 1.85, -2.045), PAINT_DK)
	_b(s, Vector3(1.9, 0.08, 0.08), Vector3(0, 1.78, -2.07), TRIM)


## Roof plate details, the rack, the ladder, the pipes, the straps, the wand antenna.
func _roof_and_rack(s: LowPoly.Soup) -> void:
	_b(s, Vector3(0.7, 0.05, 0.6), Vector3(0.45, 1.93, -1.6), PAINT_DK)                       # roof vent hatch
	_b(s, Vector3(0.62, 0.04, 0.5), Vector3(0.45, 1.965, -1.6), PAINT)
	# rack: two rails along the van on legs, four cross bars
	for sx: float in [-1.0, 1.0]:
		_b(s, Vector3(0.07, 0.08, 3.25), Vector3(sx * 0.84, 2.07, -0.55), TRIM_LT)
	for zc: float in [-1.75, -0.9, -0.05, 0.8]:
		_b(s, Vector3(1.78, 0.07, 0.07), Vector3(0, 2.02, zc), TRIM_LT)
		for sx: float in [-1.0, 1.0]:
			_b(s, Vector3(0.07, 0.14, 0.07), Vector3(sx * 0.84, 1.97, zc), TRIM)
	# the ladder (orange fibreglass), strapped on the +X half of the rack, hanging out over the rear
	var lx := 0.38
	for sx: float in [-1.0, 1.0]:
		_b(s, Vector3(0.06, 0.12, 3.7), Vector3(lx + sx * 0.25, 2.16, -0.5), LADDER)
	for i in 12:
		var z := -2.2 + 0.31 * float(i)
		_b(s, Vector3(0.5, 0.04, 0.045), Vector3(lx, 2.16, z), LADDER.lightened(0.18))
	_b(s, Vector3(0.08, 0.1, 0.12), Vector3(lx - 0.25, 2.16, -2.38), TRIM)                    # rubber feet
	_b(s, Vector3(0.08, 0.1, 0.12), Vector3(lx + 0.25, 2.16, -2.38), TRIM)
	# pipes on the -X half: copper, PVC, black ABS and a fat flexi duct, longer than the van
	_cyl(s, 0.08, 0.08, 4.3, 7, Vector3(-0.74, 2.17, -0.35), COPPER, Vector3(90, 0, 0))
	_cyl(s, 0.07, 0.07, 3.8, 7, Vector3(-0.55, 2.16, -0.7), PVC, Vector3(90, 0, 0))
	_cyl(s, 0.085, 0.085, 3.9, 7, Vector3(-0.36, 2.17, -0.1), ABS, Vector3(90, 0, 0))
	_cyl(s, 0.095, 0.095, 3.4, 7, Vector3(-0.16, 2.18, -0.55), Color(0.52, 0.54, 0.58), Vector3(90, 0, 0))
	for zend: float in [1.8, -2.5]:                                                               # capped / threaded ends
		_cyl(s, 0.09, 0.09, 0.08, 7, Vector3(-0.74, 2.17, zend), COPPER.darkened(0.3), Vector3(90, 0, 0))
	_cyl(s, 0.075, 0.075, 0.1, 7, Vector3(-0.55, 2.16, 1.2), PVC.darkened(0.25), Vector3(90, 0, 0))
	# ratchet straps over ladder + pipes
	for zc: float in [-1.35, 0.35]:
		_b(s, Vector3(1.9, 0.045, 0.075), Vector3(0, 2.29, zc), STRAP)
		_b(s, Vector3(0.12, 0.07, 0.1), Vector3(0.1, 2.31, zc), TRIM)
		_b(s, Vector3(0.03, 0.3, 0.06), Vector3(0.96, 2.1, zc), STRAP)
		_b(s, Vector3(0.03, 0.3, 0.06), Vector3(-0.96, 2.1, zc), STRAP)
	# the wand antenna on the cab roof: a spindly rod with a star on top
	_rod(s, Vector3(-0.78, 1.9, 1.15), Vector3(-0.7, 2.5, 1.05), 0.022, 5, Color(0.26, 0.2, 0.34))


func _side_details(s: LowPoly.Soup) -> void:
	# -X (door) side, rear segment: the roundel (wand + wrench) with a coiled hose under it
	_roundel(s, -1.0, -1.68, 1.58, 0.3)
	_hose_coil(s, -1.0, -1.66, 1.02, 0.27, HOSE)
	# the other side: a long navy banner (the text goes on as Label3D), the roundel again, a pipe wrench and a
	# plunger on pegs, a yellow hose coil
	_decal(s, 1.0, -0.55, 1.52, 2.7, 0.62, NAVY)
	_decal(s, 1.0, -0.55, 1.84, 2.7, 0.035, AMBER, 0.0, 0.004)
	_decal(s, 1.0, -0.55, 1.2, 2.7, 0.035, AMBER, 0.0, 0.004)
	_roundel(s, 1.0, 0.62, 0.9, 0.3)
	_hose_coil(s, 1.0, -1.5, 0.88, 0.27, HOSE_Y)
	_pipe_wrench(s, 1.0, -0.85, 0.9)
	_plunger(s, 1.0, -0.15, 0.9)
	# a rust-red toolbox bolted under the +X side
	_b(s, Vector3(0.22, 0.26, 0.9), Vector3(1.11, 0.43, -0.9), Color(0.74, 0.16, 0.12))
	_b(s, Vector3(0.24, 0.04, 0.5), Vector3(1.11, 0.57, -0.9), TRIM_LT)
	# a mud-flap and the fuel flap
	_b(s, Vector3(0.03, 0.2, 0.2), Vector3(1.0, 0.92, 0.55), PAINT_DK)
	# sliding-door track on the -X side (the door runs on it)
	_b(s, Vector3(0.05, 0.06, 1.95), Vector3(-1.03, 1.86, -1.2), TRIM)
	_b(s, Vector3(0.05, 0.06, 1.95), Vector3(-1.03, 0.58, -1.2), TRIM)
	_b(s, Vector3(0.05, 0.05, 1.5), Vector3(-1.03, 1.2, -1.28), TRIM)
	# the violet stripe along the rear half of the -X side and the cab (the door carries its own)
	_decal(s, -1.0, -1.1, 0.98, 1.75, 0.13, STRIPE, 0.0, 0.004)
	_decal(s, -1.0, 1.52, 0.98, 1.0, 0.13, STRIPE, 0.0, 0.004)
	_decal(s, 1.0, -0.2, 0.62, 3.2, 0.1, STRIPE, 0.0, 0.002)


## The company roundel: an amber ring around a navy disc with a cream wand crossed over a steel wrench.
static func _roundel(s: LowPoly.Soup, side: float, u: float, v: float, r: float) -> void:
	_disc(s, side, u, v, r + 0.05, AMBER)
	_disc(s, side, u, v, r, NAVY, 0.006)
	_decal(s, side, u, v, 0.075, r * 1.7, CREAM, 45.0, 0.014)                                      # the wand
	_decal(s, side, u, v, 0.085, r * 1.7, Color(0.72, 0.74, 0.80), -45.0, 0.02)                    # the wrench shaft
	var o := r * 0.62
	_decal(s, side, u - o, v + o, 0.2, 0.09, Color(0.72, 0.74, 0.80), -45.0, 0.026)                # its jaws
	_decal(s, side, u + o, v + o, 0.11, 0.11, Color(1.0, 0.85, 0.3), 45.0, 0.03)                   # the wand's star


## A coil of hose hanging on a peg: a ring of short capsule-ish boxes with a loose end drooping below.
static func _hose_coil(s: LowPoly.Soup, side: float, u: float, v: float, r: float, col: Color) -> void:
	var segs := 12
	for ring in 2:
		var rr := r - 0.05 * float(ring)
		for i in segs:
			var a := TAU * (float(i) + 0.5) / float(segs)
			var cu := u + cos(a) * rr
			var cv := v + sin(a) * rr
			var seg_len := TAU * rr / float(segs) * 1.12
			var x := side * (1.0 + 0.045 + 0.05 * float(ring))
			_b(s, Vector3(0.085, 0.085, seg_len), Vector3(x, cv, cu), col if i % 5 != 0 else col.lightened(0.25), Vector3(-(rad_to_deg(a) + 90.0), 0, 0))
	_cyl(s, 0.03, 0.03, 0.2, 6, Vector3(side * 1.1, v, u), TRIM, Vector3(0, 0, 90))            # the peg
	_b(s, Vector3(0.085, 0.24, 0.085), Vector3(side * 1.045, v - r - 0.1, u + r * 0.55), col)   # the drooping end
	_b(s, Vector3(0.1, 0.07, 0.1), Vector3(side * 1.045, v - r - 0.25, u + r * 0.55), TRIM_LT)   # nozzle


static func _pipe_wrench(s: LowPoly.Soup, side: float, u: float, v: float) -> void:
	# hangs from a peg, tilted: red-handled, steel jaws at the bottom
	var x := side * 1.07
	_b(s, Vector3(0.05, 0.62, 0.1), Vector3(x, v - 0.06, u), Color(0.78, 0.14, 0.12), Vector3(14, 0, 0))
	_b(s, Vector3(0.07, 0.2, 0.2), Vector3(x, v - 0.4, u - 0.1), TRIM_LT, Vector3(14, 0, 0))
	_b(s, Vector3(0.07, 0.08, 0.14), Vector3(x, v - 0.5, u - 0.04), TRIM_LT, Vector3(14, 0, 0))
	_b(s, Vector3(0.06, 0.1, 0.1), Vector3(x, v + 0.26, u + 0.02), TRIM_LT, Vector3(14, 0, 0))
	_cyl(s, 0.03, 0.03, 0.18, 6, Vector3(side * 1.1, v + 0.2, u + 0.02), TRIM, Vector3(0, 0, 90))


static func _plunger(s: LowPoly.Soup, side: float, u: float, v: float) -> void:
	var x := side * 1.08
	_rod(s, Vector3(x, v + 0.3, u), Vector3(x, v - 0.25, u), 0.03, 5, Color(0.55, 0.38, 0.2))
	s.merge(LowPoly.cylinder(0.02, 0.17, 0.18, 8, Color(0.82, 0.14, 0.1), SEED + 21, 0.0, 1, 0.05), LowPoly.at(Vector3(x, v - 0.34, u), Vector3(0, 0, 90)))


## Rust patches, grime and mud: low flat slabs proud of the paint, bigger and darker toward the bottom and the wheels.
func _wear(s: LowPoly.Soup) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = SEED
	# grime band along both sides' bottoms, over the rear and the front
	for side: float in [-1.0, 1.0]:
		_decal(s, side, -0.6, 0.64, 2.9, 0.14, GRIME, 0.0, 0.002)
		_decal(s, side, 1.5, 0.66, 1.0, 0.12, GRIME, 0.0, 0.002)
		# wheel-arch flares and the dark rings behind the tyres
		for wz: float in [1.5, -1.35]:
			_cyl(s, 0.52, 0.52, 0.04, 10, Vector3(side * 1.005, 0.42, wz), TRIM, Vector3(0, 0, 90))
	_b(s, Vector3(1.9, 0.14, 0.02), Vector3(0, 0.62, -2.06), GRIME)
	# rust: bubbling patches along the bottom edges, the arches, the roof seams, around the door rails
	for i in 15:
		var side := -1.0 if i % 3 != 0 else 1.0
		var u := r.randf_range(-1.95, 1.9)
		var v := r.randf_range(0.6, 1.0) if r.randf() < 0.7 else r.randf_range(1.0, 1.75)
		var w := r.randf_range(0.14, 0.55)
		var h := r.randf_range(0.1, 0.34)
		var col := RUST if r.randf() < 0.5 else (RUST_LT if r.randf() < 0.5 else RUST_DK)
		_decal(s, side, u, v, w, h, col, r.randf_range(-12.0, 12.0), 0.003 + 0.002 * float(i % 3))
	# rust on the rear and the front bumper corners, the hood and the roof
	for sx: float in [-1.0, 1.0]:
		_b(s, Vector3(0.45, 0.3, 0.02), Vector3(sx * 0.5, 0.78, -2.07), RUST_DK)
		_b(s, Vector3(0.3, 0.18, 0.02), Vector3(sx * 0.7, 1.55, -2.075), RUST)
		_b(s, Vector3(0.3, 0.02, 0.4), Vector3(sx * 0.6, 1.915, 1.9 - 1.0), GRIME)
	_b(s, Vector3(0.5, 0.012, 0.35), Vector3(0.1, 1.215, 1.92), RUST)
	_b(s, Vector3(0.7, 0.02, 0.5), Vector3(-0.3, 1.91, -0.6), GRIME)
	_b(s, Vector3(0.4, 0.02, 0.3), Vector3(0.6, 1.91, -1.2), RUST)
	# a dent and a dangling bit of bumper
	_b(s, Vector3(0.5, 0.2, 0.04), Vector3(-0.55, 0.52, -2.2), TRIM, Vector3(0, 0, 28))


## The inside of the cargo bay, seen through the open door: dark liner, shelves with bins, a hose reel, a coil of cable.
func _cargo_interior(s: LowPoly.Soup) -> void:
	# liner panels just inside the shell (the slabs' own inner faces would show the white paint)
	_b(s, Vector3(1.8, 1.16, 0.01), Vector3(0, 1.22, -1.94), INNER)
	_b(s, Vector3(0.01, 1.16, 2.9), Vector3(0.915, 1.22, -0.5), INNER)
	_b(s, Vector3(1.8, 1.16, 0.01), Vector3(0, 1.22, 0.99), INNER)
	_b(s, Vector3(1.8, 0.01, 2.9), Vector3(0, 1.815, -0.5), INNER)
	_b(s, Vector3(1.8, 0.01, 2.9), Vector3(0, 0.625, -0.5), INNER_FLOOR)
	_b(s, Vector3(0.01, 1.16, 1.8), Vector3(-0.915, 1.22, -1.05), INNER)
	# a shelving rack on the +X wall with colourful bins, a toolbox and a coiled hose
	for y: float in [0.95, 1.4]:
		_b(s, Vector3(0.36, 0.04, 2.4), Vector3(0.72, y, -0.5), TRIM_LT)
	_b(s, Vector3(0.3, 0.26, 0.5), Vector3(0.74, 1.09, 0.5), Color(0.2, 0.5, 0.85))
	_b(s, Vector3(0.3, 0.2, 0.4), Vector3(0.74, 1.06, -0.1), Color(0.95, 0.75, 0.15))
	_b(s, Vector3(0.3, 0.3, 0.45), Vector3(0.74, 1.57, 0.3), Color(0.78, 0.16, 0.12))
	_b(s, Vector3(0.3, 0.22, 0.5), Vector3(0.74, 1.51, -0.5), Color(0.25, 0.62, 0.4))
	_cyl(s, 0.2, 0.2, 0.3, 8, Vector3(0.72, 0.8, -0.9), HOSE, Vector3(0, 0, 90))
	_b(s, Vector3(0.5, 0.3, 0.6), Vector3(0.6, 0.78, 0.4), Color(0.36, 0.38, 0.5))
	# a chunky wall-mounted cable drum and a hanging lantern frame
	_b(s, Vector3(0.12, 0.5, 0.12), Vector3(-0.1, 1.55, -0.6), TRIM)


# --------------------------------------------------------------------------- the sliding door

## Built around its own centre (the node sits at DOOR_CLOSED_POS): panel, band, rust, handle, roundel text goes in as Label3D.
func _door_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(SEED + 3, 0.055)
	_dented(s, Vector3(0.07, 1.28, 1.14), Vector3.ZERO, PAINT, 0.012, 3)
	_b(s, Vector3(0.012, 0.13, 1.12), Vector3(-0.04, -0.27, 0), STRIPE)
	_b(s, Vector3(0.012, 0.1, 1.0), Vector3(-0.04, -0.52, 0), GRIME)
	_b(s, Vector3(0.05, 0.08, 0.26), Vector3(-0.05, -0.12, 0.34), TRIM_LT)         # handle
	_b(s, Vector3(0.014, 0.28, 0.3), Vector3(-0.04, -0.36, -0.3), RUST)
	_b(s, Vector3(0.014, 0.16, 0.18), Vector3(-0.042, -0.4, -0.2), RUST_DK)
	_b(s, Vector3(0.014, 0.18, 0.26), Vector3(-0.04, 0.52, 0.3), RUST_LT)
	# the plaque the name goes on
	_b(s, Vector3(0.014, 0.76, 1.0), Vector3(-0.04, 0.26, 0), NAVY)
	_b(s, Vector3(0.016, 0.03, 1.0), Vector3(-0.042, 0.62, 0), AMBER)
	_b(s, Vector3(0.016, 0.03, 1.0), Vector3(-0.042, -0.1, 0), AMBER)
	# the same panel seen from inside (dark) so the open door reads as a door, not a floating slab
	_b(s, Vector3(0.01, 1.2, 1.1), Vector3(0.036, 0, 0), INNER)
	return s


# --------------------------------------------------------------------------- lights and glow

## Head, tail, indicator lights: every face alpha 0.5 (MonsterMaterial glow), driven by the Lamps material's glow_gain.
func _lamps_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(SEED + 5, 0.03)
	var warm := Color(1.0, 0.93, 0.7)
	for sx: float in [-1.0, 1.0]:
		_b(s, Vector3(0.44, 0.22, 0.04), Vector3(sx * 0.72, 0.9, 2.085), PropModels.glow(warm))
		_b(s, Vector3(0.14, 0.12, 0.04), Vector3(sx * 0.93, 0.7, 2.085), PropModels.glow(AMBER))
		_b(s, Vector3(0.14, 0.52, 0.04), Vector3(sx * 0.9, 1.15, -2.085), PropModels.glow(Color(1.0, 0.16, 0.1)))
		_b(s, Vector3(0.1, 0.1, 0.04), Vector3(sx * 0.4, 0.62, -2.2), PropModels.glow(Color(1.0, 0.95, 0.85)))
	# the star on the wand antenna
	var star := PropModels.glow(Color(1.0, 0.86, 0.35))
	for rz: float in [0.0, 45.0, 90.0, 135.0]:
		_b(s, Vector3(0.03, 0.22, 0.03), Vector3(-0.7, 2.56, 1.05), star, Vector3(0, 0, rz))
	return s


## A violet crystal lantern in the cargo and the glow strips on the shelves (shown when the door opens).
func _inner_glow_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(SEED + 7, 0.04)
	s.merge(LowPoly.boulder(Vector3(0.1, 0.17, 0.1), 0, 0.15, PropModels.glow(VIOLET), SEED + 8, 0.0), LowPoly.at(Vector3(-0.1, 1.4, -0.6)))
	_b(s, Vector3(0.012, 0.03, 2.3), Vector3(0.5, 1.5, -0.5), PropModels.glow(Color(0.7, 0.45, 1.0)))
	_b(s, Vector3(0.012, 0.03, 2.3), Vector3(0.5, 1.0, -0.5), PropModels.glow(Color(0.7, 0.45, 1.0)))
	_b(s, Vector3(0.3, 0.012, 0.4), Vector3(0.0, 1.8, 0.4), PropModels.glow(Color(0.85, 0.75, 1.0)))   # ceiling strip
	return s


# --------------------------------------------------------------------------- wheels

func _wheels_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(SEED + 9, 0.045)
	for sx: float in [-1.0, 1.0]:
		for wz: float in [1.5, -1.35]:
			var x := sx * 0.97
			_cyl(s, 0.42, 0.42, 0.3, 10, Vector3(x, 0.42, wz), TYRE, Vector3(0, 0, 90))
			_cyl(s, 0.27, 0.27, 0.34, 8, Vector3(x, 0.42, wz), HUB, Vector3(0, 0, 90))
			_cyl(s, 0.1, 0.1, 0.38, 6, Vector3(x, 0.42, wz), TRIM, Vector3(0, 0, 90))
			for i in 5:
				var a := TAU * float(i) / 5.0
				_b(s, Vector3(0.38, 0.05, 0.05), Vector3(x, 0.42 + sin(a) * 0.18, wz + cos(a) * 0.18), TRIM_LT)
	return s


# --------------------------------------------------------------------------- the writing

func _add_signs() -> void:
	var signs := Node3D.new()
	signs.name = "Signs"
	chassis.add_child(signs)
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.9
	# the door (-X side): the company name, on the navy plaque; it slides with the door
	_label(door, "LICENSED
BUDGET
SORCERY", font, 38, 0.0052, CREAM, Vector3(-0.05, 0.28, 0.0), -90.0)
	# the +X side banner
	_label(signs, "BUDGET SORCERY", font, 52, 0.0056, CREAM, Vector3(1.026, 1.62, -0.55), 90.0)
	_label(signs, "LICENSED  -  24/7 DISPATCH", font, 26, 0.0056, AMBER, Vector3(1.026, 1.37, -0.55), 90.0)
	# the rear doors: a tagline and a phone number
	_label(signs, "HOW'S MY SORCERY?", font, 26, 0.0052, TRIM, Vector3(0.0, 1.45, -2.075), 180.0)
	_label(signs, "CALL 555-WAND-FIX", font, 24, 0.0052, TRIM, Vector3(0.0, 1.3, -2.075), 180.0)


func _label(parent: Node3D, text: String, font: Font, size: int, pixel: float, col: Color, pos: Vector3, yaw: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = pixel
	l.shaded = false
	l.double_sided = false
	l.modulate = col
	l.outline_size = 6
	l.outline_modulate = Color(0.04, 0.03, 0.08)
	l.line_spacing = -6.0
	l.position = pos
	l.rotation_degrees.y = yaw
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	parent.add_child(l)
	return l
