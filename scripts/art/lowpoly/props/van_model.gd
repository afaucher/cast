class_name VanModel
extends Node3D
## The crew's work van ("Cast"): a beat-up, rust-streaked white-grey panel van with a roof rack (orange ladder, copper and
## PVC pipes, two ratchet straps, a wand antenna), a pipe wrench and a wand-and-wrench logo on the sides, a sliding side
## door that opens, headlights that can glow, and the company name, CAST, on the door and on the other side. Faceted
## low-poly in the house style (LowPoly soup, MonsterMaterial: ink outline, amber rim, vertex alpha 0.5 = emissive face).
## About 2.0 wide x 4.2 long x 2.2 tall (VanPlan.W/L/H); origin at the centre of the footprint on the floor, the NOSE is +Z,
## the sliding door is on the -X side (it slides toward the rear, -Z).
##
## Kept deliberately sparse: every attached piece (rack load, logo, wrench, rust patch) has clear air around it and sits
## clear of the wheel arches and of the door opening, so the van reads as a clean silhouette first and detail second.
##
##   var van := VanModel.new()
##   van.set_door_open(1.0)          # 0 closed .. 1 fully open (the door slides back along the body)
##   van.set_lights(1.0)             # headlights / tail lights glow (0 off)
##   van.set_bounce(-0.12, 0.0)      # chassis offset (y, world units) and body roll (radians): the suspension
##
## Parts (all MeshInstance3D unless noted): Chassis (Node3D) holds Body, Door, Lamps, InnerGlow, Signs and the two
## lights, and rides on the suspension; Wheels stay put. Label3D text sits under Signs and under Door.
##
## Ride height: the tyres' lowest points are RIDE_HEIGHT above the origin (the floor); the chalk circle the van is parked
## on is 0.035 proud of the tiles, so the tyres sit ON it instead of vanishing into it. The suspension only moves the
## chassis (never below its rest height by more than the arches clear), the wheels never go lower.

const LENGTH := 4.2
const WIDTH := 2.0
const HEIGHT := 2.2
const DOOR_TRAVEL := 1.3          ## how far the sliding door moves toward the rear when fully open
const DOOR_CLOSED_POS := Vector3(-1.095, 1.2, 0.4)
const RIDE_HEIGHT := 0.045        ## tyre bottoms and the chassis rest this far above the floor (clears the 0.035 chalk circle)
## Flat decals (side plates, logo, stripes, rust) stack in LEVELS: every slab is sunk into the wall and its outer face is
## DECAL_BASE proud of it (more than the 0.005 dents the walls carry), each level a further DECAL_STEP, so no two faces
## of overlapping pieces are ever coplanar (that was the z-fighting).
const DECAL_BASE := 0.016
const DECAL_STEP := 0.01
const DENT := 0.005
const SHELL_TUCK := 0.01          ## the cargo shell's slabs stop this far inside each other's outer faces (see _shell)
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
	chassis.position.y = RIDE_HEIGHT
	add_child(chassis)
	_add_mesh("Body", _body_soup(), chassis, Vector3.ZERO, _material())
	door = _add_mesh("Door", _door_soup(), chassis, DOOR_CLOSED_POS, _material())
	_lamp_mat = _glow_material(1.8)
	_add_mesh("Lamps", _lamps_soup(), chassis, Vector3.ZERO, _lamp_mat)
	_inner_mat = _glow_material(2.2)
	_add_mesh("InnerGlow", _inner_glow_soup(), chassis, Vector3.ZERO, _inner_mat)
	_add_mesh("Wheels", _wheels_soup(), self, Vector3(0.0, RIDE_HEIGHT, 0.0), _material())
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


## The suspension: chassis height offset from its rest (world units, negative = compressed) and a roll about the nose axis
## (radians). The wheels stay on the floor.
func set_bounce(y: float, pitch: float = 0.0) -> void:
	chassis.position.y = RIDE_HEIGHT + y
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


## A flat slab on the side face at x = side * 1.0 (u runs along the van, +Z nose, v is height; wu x wv in size, `rot` turns it
## about the face normal in degrees). `level` stacks layers: the outer face sits DECAL_BASE + level * DECAL_STEP proud of the
## wall and the slab is sunk into it, so overlapping layers are always at least DECAL_STEP apart.
static func _decal(s: LowPoly.Soup, side: float, u: float, v: float, wu: float, wv: float, col: Color, rot: float = 0.0, level: int = 0) -> void:
	var outer := 1.0 + DECAL_BASE + DECAL_STEP * float(level)
	var thick := outer - 0.99
	_b(s, Vector3(thick, wv, wu), Vector3(side * (outer - thick * 0.5), v, u), col, Vector3(rot, 0, 0))


## A flat round decal on a side face (axis along X), stacked like _decal.
static func _disc(s: LowPoly.Soup, side: float, u: float, v: float, r: float, col: Color, level: int = 0) -> void:
	var outer := 1.0 + DECAL_BASE + DECAL_STEP * float(level)
	var thick := outer - 0.99
	_cyl(s, r, r, thick, 12, Vector3(side * (outer - thick * 0.5), v, u), col, Vector3(0, 0, 90))


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
## No two slabs share an outer face (ZFightCheck, tests/test_zfight.gd): the walls' tops end inside the roof slab, the roof
## and floor are SHELL_TUCK inside the walls' outer faces, the side walls end inside the rear wall and the pillar ends
## where the cab starts. Flush, the dented faces crossed each other and flickered along the seams.
func _shell(s: LowPoly.Soup) -> void:
	var y0 := 0.5
	var y1 := 1.9
	var t := SHELL_TUCK
	var wy := (y0 + y1 - 6.0 * t) * 0.5             # walls: y0 .. y1 - 6t, their tops inside the roof slab
	var wh := y1 - 6.0 * t - y0
	# roof, floor, rear, +X wall, -X rear segment, header over the door, pillar in front of it
	_dented(s, Vector3(2.0 - 2.0 * t, 0.12, 3.05 - t), Vector3(0, y1 - 0.06, -0.525 + t * 0.5), PAINT_LT, DENT, 3)
	_b(s, Vector3(2.0 - 2.0 * t, 0.12, 3.05 - t), Vector3(0, y0 + 0.06, -0.525 + t * 0.5), TRIM)
	_dented(s, Vector3(2.0 - 2.0 * t, wh, 0.1), Vector3(0, wy, -2.0), PAINT, DENT)
	_dented(s, Vector3(0.08, wh, 3.05 - t), Vector3(0.96, wy, -0.525 + t * 0.5), PAINT, DENT, 3)
	_dented(s, Vector3(0.08, wh, 1.9 - t), Vector3(-0.96, wy, -1.1 + t * 0.5), PAINT, DENT, 3)
	_b(s, Vector3(0.08, 0.1, 1.14), Vector3(-0.96, 1.84, 0.37), PAINT_LT)
	_b(s, Vector3(0.08, wh, 0.06), Vector3(-0.96, wy, 0.97), PAINT)


## The cab: lower body + hood, the sloped windscreen, side windows, door seams.
func _cab(s: LowPoly.Soup) -> void:
	_dented(s, Vector3(2.0, 0.7, 1.05), Vector3(0, 0.85, 1.525), PAINT, DENT)        # lower cab and hood (z 1.0 .. 2.05)
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
		_b(s, Vector3(0.034, 0.14, 0.14), Vector3(side * 0.997, 1.52, 1.13), GLASS_LT)          # glint clear of the pane's edge
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
		_b(s, Vector3(0.84, 0.025, 0.06), Vector3(0, 0.76 + 0.07 * float(i), 2.07), TRIM_LT)
	_b(s, Vector3(0.52, 0.28, 0.05), Vector3(-0.72, 0.9, 2.055), TRIM)        # 1 cm lower than the grille's top
	_b(s, Vector3(0.52, 0.28, 0.05), Vector3(0.72, 0.9, 2.055), TRIM)
	_b(s, Vector3(2.08, 0.22, 0.2), Vector3(0, 0.56, 2.0), TRIM)
	_b(s, Vector3(2.04, 0.07, 0.22), Vector3(0, 0.66, 2.0), PAINT_DK)                         # proud of the cab's sides
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


## The rack, the ladder, two pipes, two straps, the wand antenna. Everything rides on the cross bars with air between the
## lanes (rail | copper | PVC | gap | ladder | rail) and stops short of the cab roof, so the antenna has a clear spot.
func _roof_and_rack(s: LowPoly.Soup) -> void:
	# rack: two rails along the van on legs, four cross bars
	for sx: float in [-1.0, 1.0]:
		_b(s, Vector3(0.07, 0.08, 3.25), Vector3(sx * 0.84, 2.07, -0.55), TRIM_LT)
	for zc: float in [-1.75, -0.9, -0.05, 0.8]:
		_b(s, Vector3(1.78, 0.07, 0.07), Vector3(0, 2.02, zc), TRIM_LT)
		for sx: float in [-1.0, 1.0]:
			_b(s, Vector3(0.06, 0.14, 0.06), Vector3(sx * 0.84, 1.97, zc), TRIM)             # legs thinner than bar and rail
	# the ladder (orange fibreglass) on the +X half of the rack, hanging a little out over the rear
	var lx := 0.4
	for sx: float in [-1.0, 1.0]:
		_b(s, Vector3(0.06, 0.12, 3.2), Vector3(lx + sx * 0.25, 2.115, -0.75), LADDER)
	for i in 10:
		var z := -2.2 + 0.31 * float(i)
		_b(s, Vector3(0.5, 0.04, 0.045), Vector3(lx, 2.115, z), LADDER.lightened(0.18))
	_b(s, Vector3(0.08, 0.1, 0.12), Vector3(lx - 0.25, 2.115, -2.31), TRIM)                   # rubber feet
	_b(s, Vector3(0.08, 0.1, 0.12), Vector3(lx + 0.25, 2.115, -2.31), TRIM)
	# two pipes on the -X half: copper and PVC (resting on the bars: bar top 2.055 + radius)
	_cyl(s, 0.08, 0.08, 3.2, 7, Vector3(-0.6, 2.135, -0.75), COPPER, Vector3(90, 0, 0))
	_cyl(s, 0.07, 0.07, 2.8, 7, Vector3(-0.28, 2.125, -0.95), PVC, Vector3(90, 0, 0))
	# two ratchet straps over ladder + pipes, clear of every cross bar
	for zc: float in [-1.35, 0.35]:
		_b(s, Vector3(1.9, 0.045, 0.075), Vector3(0, 2.24, zc), STRAP)
		_b(s, Vector3(0.12, 0.07, 0.1), Vector3(0.1, 2.27, zc), TRIM)
		_b(s, Vector3(0.03, 0.34, 0.06), Vector3(0.96, 2.1, zc), STRAP)
		_b(s, Vector3(0.03, 0.34, 0.06), Vector3(-0.96, 2.1, zc), STRAP)
	# the wand antenna on the cab roof: a spindly rod with a star on top
	_rod(s, Vector3(-0.78, 1.9, 1.15), Vector3(-0.7, 2.5, 1.05), 0.022, 5, Color(0.26, 0.2, 0.34))


## Side dressing, kept to a handful of pieces. -X (door side): the logo roundel on the rear segment (it stays clear of the
## door when that slides back), the violet stripe, one rust patch. +X: the CAST plate with the logo, a pipe wrench in the band
## under it, the stripe and a rust patch. The wheel arches and the door opening stay empty.
func _side_details(s: LowPoly.Soup) -> void:
	_logo(s, -1.0, -1.78, 1.38, 0.17, 0, true)
	# +X side: a CAST plate (an amber frame plate under a navy plate: a raised border) with the logo at its end; the name goes
	# on as Label3D
	_decal(s, 1.0, -0.525, 1.45, 1.91, 0.56, AMBER, 0.0, 0)
	_decal(s, 1.0, -0.525, 1.45, 1.85, 0.5, NAVY, 0.0, 1)
	_logo(s, 1.0, 0.1, 1.45, 0.17, 1, false)
	_pipe_wrench(s, 1.0, -0.06, 0.9)
	# sliding-door track on the -X side (the door runs on it)
	_b(s, Vector3(0.05, 0.06, 1.8), Vector3(-1.035, 1.86, -1.1), TRIM)
	# the violet stripe along the rear half of the -X side and the cab (the door carries its own), and along the +X side
	_decal(s, -1.0, -1.1, 0.98, 1.75, 0.13, STRIPE)
	_decal(s, -1.0, 1.585, 0.98, 0.87, 0.13, STRIPE)
	_decal(s, 1.0, -0.2, 0.62, 3.2, 0.1, STRIPE)


## The company logo: a cream wand crossed over a steel wrench, optionally on an amber-ringed navy disc. `level` is the decal
## level of the first layer; r scales everything (0.3 is the original roundel).
static func _logo(s: LowPoly.Soup, side: float, u: float, v: float, r: float, level: int, disc: bool) -> void:
	var k := r / 0.3
	var lv := level
	if disc:
		_disc(s, side, u, v, r + 0.05, AMBER, lv)
		_disc(s, side, u, v, r, NAVY, lv + 1)
		lv += 1
	var steel := Color(0.72, 0.74, 0.80)
	_decal(s, side, u, v, 0.075 * k, r * 1.7, CREAM, 45.0, lv + 1)                                  # the wand
	_decal(s, side, u, v, 0.085 * k, r * 1.7, steel, -45.0, lv + 2)                                 # the wrench shaft
	var o := r * 0.62
	_decal(s, side, u - o, v + o, 0.2 * k, 0.09 * k, steel, -45.0, lv + 3)                          # its jaws
	_decal(s, side, u + o, v + o, 0.11 * k, 0.11 * k, Color(1.0, 0.85, 0.3), 45.0, lv + 3)          # the wand's star


## A pipe wrench lying on a peg on the +X side: red handle, steel jaw head with a slot.
static func _pipe_wrench(s: LowPoly.Soup, side: float, u: float, v: float) -> void:
	var x := side * 1.065
	_b(s, Vector3(0.05, 0.07, 0.52), Vector3(x, v, u - 0.15), Color(0.78, 0.14, 0.12))
	_b(s, Vector3(0.06, 0.2, 0.16), Vector3(x, v, u + 0.19), TRIM_LT)
	_b(s, Vector3(0.07, 0.06, 0.07), Vector3(x, v + 0.05, u + 0.24), TRIM)
	_cyl(s, 0.03, 0.03, 0.1, 6, Vector3(side * 1.05, v, u - 0.33), TRIM, Vector3(0, 0, 90))      # the peg through the handle end


## Wheel-arch rings and two rust patches, each alone on a clear stretch of panel (none near the cab, the windscreen, the
## roof, the arches, the door opening or a sign).
func _wear(s: LowPoly.Soup) -> void:
	for side: float in [-1.0, 1.0]:
		# the dark arches behind the tyres: they stop above the floor so a compressed chassis never dips them under it.
		# 12 sides against the tyre's 10, so no flat of the arch lines up with a flat of the tyre (they z-fought)
		for wz: float in [1.5, -1.35]:
			_cyl(s, 0.42, 0.42, 0.04, 12, Vector3(side * 1.005, 0.48, wz), TRIM, Vector3(0, 0, 90))
	_decal(s, -1.0, -0.85, 1.55, 0.3, 0.14, RUST, 4.0)
	_decal(s, 1.0, 0.75, 0.82, 0.3, 0.12, RUST_LT, -5.0)


## The inside of the cargo bay, seen through the open door: dark liner, one shelf with two bins, a crate and a hose reel on
## the floor, a hanging lantern. All of it on the far (+X) side or hanging mid-van, set well back from the opening.
func _cargo_interior(s: LowPoly.Soup) -> void:
	# liner panels just inside the shell (the slabs' own inner faces would show the white paint)
	_b(s, Vector3(1.8, 1.16, 0.01), Vector3(0, 1.22, -1.94), INNER)
	_b(s, Vector3(0.01, 1.16, 2.9), Vector3(0.915, 1.22, -0.5), INNER)
	_b(s, Vector3(1.8, 1.16, 0.01), Vector3(0, 1.22, 0.99), INNER)
	_b(s, Vector3(1.8, 0.01, 2.9), Vector3(0, 1.815, -0.5), INNER)
	_b(s, Vector3(1.8, 0.01, 2.9), Vector3(0, 0.625, -0.5), INNER_FLOOR)
	_b(s, Vector3(0.01, 1.16, 1.8), Vector3(-0.915, 1.22, -1.05), INNER)
	# one shelf on the +X wall with two bins, a crate and a coiled hose on the floor below
	_b(s, Vector3(0.36, 0.04, 1.8), Vector3(0.72, 1.1, -0.25), TRIM_LT)
	_b(s, Vector3(0.3, 0.26, 0.5), Vector3(0.74, 1.25, 0.4), Color(0.2, 0.5, 0.85))
	_b(s, Vector3(0.3, 0.3, 0.45), Vector3(0.74, 1.27, -0.55), Color(0.78, 0.16, 0.12))
	_cyl(s, 0.2, 0.2, 0.3, 8, Vector3(0.72, 0.83, -0.9), HOSE, Vector3(0, 0, 90))
	_b(s, Vector3(0.5, 0.3, 0.6), Vector3(0.6, 0.78, 0.4), Color(0.36, 0.38, 0.5))
	# the lantern's hanger from the ceiling
	_b(s, Vector3(0.04, 0.2, 0.04), Vector3(-0.1, 1.71, 0.3), TRIM)


# --------------------------------------------------------------------------- the sliding door

## Built around its own centre (the node sits at DOOR_CLOSED_POS): panel, band, rust, handle, roundel text goes in as Label3D.
func _door_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(SEED + 3, 0.055)
	_dented(s, Vector3(0.07, 1.28, 1.14), Vector3.ZERO, PAINT, DENT, 3)
	# the plate the name goes on: a raised amber frame plate (level 0) under the navy plate (level 1)
	_door_slab(s, 0.33, 0.0, 1.02, 0.5, AMBER, 0)
	_door_slab(s, 0.33, 0.0, 0.94, 0.42, NAVY, 1)
	_b(s, Vector3(0.05, 0.08, 0.26), Vector3(-0.05, -0.05, 0.34), TRIM_LT)                       # handle
	_door_slab(s, -0.22, 0.0, 1.12, 0.13, STRIPE, 0)                                               # in line with the body's stripe
	# the same panel seen from inside (dark) so the open door reads as a door, not a floating slab
	_b(s, Vector3(0.01, 1.2, 1.1), Vector3(0.036, 0.0, 0.0), INNER)
	return s


## A flat slab on the door's outer (-X) face, stacked in levels like VanModel._decal (the panel's face is at x = -0.035).
static func _door_slab(s: LowPoly.Soup, y: float, z: float, wz: float, wy: float, col: Color, level: int) -> void:
	var outer := 0.035 + DECAL_BASE + DECAL_STEP * float(level)
	var thick := outer - 0.025
	_b(s, Vector3(thick, wy, wz), Vector3(-(outer - thick * 0.5), y, z), col)


# --------------------------------------------------------------------------- lights and glow

## Head, tail, indicator lights: every face alpha 0.5 (MonsterMaterial glow), driven by the Lamps material's glow_gain.
func _lamps_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(SEED + 5, 0.03)
	var warm := Color(1.0, 0.93, 0.7)
	for sx: float in [-1.0, 1.0]:
		_b(s, Vector3(0.44, 0.22, 0.04), Vector3(sx * 0.72, 0.9, 2.085), PropModels.glow(warm))
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
	s.merge(LowPoly.boulder(Vector3(0.1, 0.17, 0.1), 0, 0.15, PropModels.glow(VIOLET), SEED + 8, 0.0), LowPoly.at(Vector3(-0.1, 1.5, 0.3)))
	_b(s, Vector3(0.012, 0.03, 1.8), Vector3(0.5, 1.1, -0.25), PropModels.glow(Color(0.7, 0.45, 1.0)))   # the shelf's glow strip
	_b(s, Vector3(0.3, 0.012, 0.4), Vector3(0.0, 1.8, 0.4), PropModels.glow(Color(0.85, 0.75, 1.0)))     # ceiling strip
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
	# the door (-X side): the company name on the navy plate (plate face at x -0.061 + a hair); it slides with the door
	_label(door, "CAST", font, 64, 0.0054, CREAM, Vector3(-0.073, 0.33, 0.0), -90.0)
	# the +X side plate
	_label(signs, "CAST", font, 80, 0.0058, CREAM, Vector3(1.039, 1.45, -0.8), 90.0)


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
