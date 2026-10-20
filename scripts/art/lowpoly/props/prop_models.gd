class_name PropModels
extends RefCounted
## Faceted low-poly models for the priced props (luxury bunker + villain lair), built in code from
## LowPoly primitives like the characters. Flat facet colour, ink outline, amber rim (MonsterMaterial,
## which is the hero look + emissive faces: vertex alpha 0.5 glows, used for screens, LEDs, gold
## highlights, water and flames).
##
## Every model is one merged mesh ("Body"), origin at the base centre, front = +Z (PricedProp turns
## it toward the iso camera). height(kind) is the model's top, for tag and fx placement.
##
##   var node := PropModels.build("gold_toilet")     # Node3D with a MeshInstance3D "Body"
##   PropModels.palette("gold_toilet")                # colours for debris shards
##   PropModels.rubble("gold_toilet")                 # the small broken remnant

const GOLD := Color(0.98, 0.76, 0.24)
const GOLD_DK := Color(0.74, 0.50, 0.13)
const MARBLE := Color(0.91, 0.90, 0.87)
const MARBLE_DK := Color(0.62, 0.62, 0.66)
const WOOD := Color(0.48, 0.29, 0.15)
const WOOD_DK := Color(0.28, 0.16, 0.09)
const IRON := Color(0.23, 0.23, 0.28)
const IRON_LT := Color(0.40, 0.41, 0.48)
const VELVET := Color(0.66, 0.07, 0.12)
const STONE := Color(0.46, 0.46, 0.52)
const BOTTLE_GREEN := Color(0.10, 0.34, 0.18)
const BOTTLE_RED := Color(0.42, 0.08, 0.12)
const CREAM := Color(0.96, 0.90, 0.74)
const OBSIDIAN := Color(0.12, 0.10, 0.15)

const HEIGHTS := {
	"wine_rack": 1.7, "wine_barrel": 1.25, "marble_statue": 2.2, "gold_toilet": 1.35,
	"projector": 1.35, "zen_fountain": 1.15, "server_rack": 1.95, "crystal_lamp": 1.45,
	"doomsday_console": 1.75, "torture_rack": 0.95, "specimen_vat": 2.0, "villain_throne": 2.35,
	"shark_tank": 1.6, "henchman_locker": 1.75, "evil_portrait": 2.0, "brazier": 1.15, "treadmill": 1.5,
	# explosive props (ExplosiveProp, docs/design/hazards.md)
	"oil_drum": 1.05, "gas_cylinders": 1.45, "propane_tank": 1.2, "battery_pack": 1.52,
	# the sewer's (docs/design/sewer-concept.md, phase 1)
	"sump_pump": 1.7, "electrical_panel": 1.8,
}
## The sewer's lab models (scripts/art/lowpoly/props/sewer_props.gd): the sump pump and the electrical panel are built there.
const SewerProps := preload("res://scripts/art/lowpoly/props/sewer_props.gd")
## Where the electrical panel's cable leaves the box (model space): LiveWire drops the live cable from here.
const PANEL_CABLE_ROOT := Vector3(0.0, 1.05, 0.2)

const HAZARD_YELLOW := Color(1.0, 0.8, 0.12)
const DRUM_RED := Color(0.7, 0.15, 0.1)
const DRUM_RED_DK := Color(0.45, 0.08, 0.06)
const TANK_WHITE := Color(0.88, 0.88, 0.84)
const CYL_GREEN := Color(0.16, 0.42, 0.24)
const CYL_MAROON := Color(0.46, 0.1, 0.14)
const CYL_BLUE := Color(0.2, 0.32, 0.5)
## Where a lit explosive's fuse sparks (model space, front = +Z): the bung, the middle valve, the dome, the + terminal.
const FUSE_POINTS := {
	"oil_drum": Vector3(0.16, 1.06, 0.12), "gas_cylinders": Vector3(0.0, 1.42, 0.0),
	"propane_tank": Vector3(0.0, 1.19, 0.0), "battery_pack": Vector3(0.28, 1.51, 0.18),
}

static var _seed := 1


static func height(kind: String) -> float:
	return float(HEIGHTS.get(kind, 1.5))


## The glow convention of MonsterMaterial: alpha 0.5 = emissive face.
static func glow(c: Color) -> Color:
	return Color(c.r, c.g, c.b, MonsterMaterial.GLOW_ALPHA)


static func material() -> ShaderMaterial:
	var m := MonsterMaterial.make(2.3)
	m.set_shader_parameter("glow_gain", 1.6)
	return m


static func build(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var s := LowPoly.Soup.new(7, 0.06)
	_seed = int(kind.hash() % 9973)
	match kind:
		"wine_rack": _wine_rack(s)
		"wine_barrel": _wine_barrel(s)
		"marble_statue": _marble_statue(s)
		"gold_toilet": _gold_toilet(s)
		"projector": _projector(s)
		"zen_fountain": _zen_fountain(s)
		"server_rack": _server_rack(s)
		"crystal_lamp": _crystal_lamp(s)
		"treadmill": _treadmill(s)
		"doomsday_console": _doomsday_console(s)
		"torture_rack": _torture_rack(s)
		"specimen_vat": _specimen_vat(s)
		"villain_throne": _villain_throne(s)
		"shark_tank": _shark_tank(s)
		"henchman_locker": _henchman_locker(s)
		"evil_portrait": _evil_portrait(s)
		"brazier": _brazier(s)
		"oil_drum": _oil_drum(s)
		"gas_cylinders": _gas_cylinders(s)
		"propane_tank": _propane_tank(s)
		"battery_pack": _battery_pack(s)
		"sump_pump": SewerProps._pump(s, Color(0.22, 0.4, 0.55))
		"electrical_panel": SewerProps._junction_box(s, Vector3(0.15, -0.55, 0.9), false)
		_:
			box(s, Vector3(0.8, 0.8, 0.8), Vector3(0, 0.4, 0), GOLD)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = s.to_mesh()
	mi.material_override = material()
	root.add_child(mi)
	if kind == "brazier":
		root.add_child(_embers())
	return root


## Colours a broken prop's shards are painted with.
static func palette(kind: String) -> Array[Color]:
	var out: Array[Color] = []
	match kind:
		"wine_rack": out = [WOOD, WOOD_DK, BOTTLE_GREEN, BOTTLE_RED]
		"wine_barrel": out = [WOOD, WOOD_DK, GOLD, BOTTLE_RED]
		"marble_statue": out = [MARBLE, MARBLE_DK, GOLD]
		"gold_toilet": out = [GOLD, GOLD_DK, Color(1.0, 0.92, 0.55), VELVET]
		"projector": out = [IRON, IRON_LT, Color(0.5, 0.85, 1.0), WOOD_DK]
		"zen_fountain": out = [STONE, Color(0.35, 0.36, 0.4), Color(0.4, 0.85, 0.85)]
		"server_rack": out = [IRON, IRON_LT, Color(0.3, 1.0, 0.5), Color(1.0, 0.6, 0.2)]
		"crystal_lamp": out = [Color(0.85, 0.55, 1.0), Color(1.0, 0.7, 0.95), GOLD, Color(0.6, 0.35, 0.9)]
		"treadmill": out = [IRON, IRON_LT, VELVET, Color(0.3, 0.9, 1.0)]
		"doomsday_console": out = [IRON, IRON_LT, Color(1.0, 0.2, 0.15), Color(0.95, 0.8, 0.2)]
		"torture_rack": out = [WOOD_DK, WOOD, IRON, Color(0.7, 0.62, 0.45)]
		"specimen_vat": out = [IRON, Color(0.3, 1.0, 0.55), Color(0.2, 0.55, 0.4), Color(0.45, 0.2, 0.6)]
		"villain_throne": out = [OBSIDIAN, VELVET, GOLD, Color(0.9, 0.88, 0.8)]
		"shark_tank": out = [IRON, Color(0.3, 0.8, 0.95), Color(0.2, 0.55, 0.7), Color(0.6, 0.65, 0.72)]
		"henchman_locker": out = [Color(0.38, 0.42, 0.5), IRON, Color(0.85, 0.2, 0.15)]
		"evil_portrait": out = [GOLD, GOLD_DK, Color(0.45, 0.07, 0.1), OBSIDIAN]
		"brazier": out = [IRON, IRON_LT, Color(1.0, 0.55, 0.12)]
		"oil_drum": out = [DRUM_RED, DRUM_RED_DK, IRON, HAZARD_YELLOW]
		"gas_cylinders": out = [CYL_GREEN, CYL_MAROON, CYL_BLUE, IRON_LT]
		"propane_tank": out = [TANK_WHITE, IRON, Color(0.85, 0.2, 0.15), HAZARD_YELLOW]
		"battery_pack": out = [OBSIDIAN, IRON, Color(1.0, 0.55, 0.12), Color(0.3, 1.0, 0.5)]
		"sump_pump": out = [Color(0.22, 0.4, 0.55), IRON, Color(0.5, 0.27, 0.14), HAZARD_YELLOW]
		"electrical_panel": out = [Color(0.55, 0.57, 0.55), IRON, HAZARD_YELLOW, Color(1.0, 0.95, 0.55)]
		_: out = [GOLD, IRON]
	return out


## The small remnant left where the prop stood: a scatter of dull shards.
static func rubble(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Rubble"
	var s := LowPoly.Soup.new(11, 0.1)
	_seed = int(kind.hash() % 7919) + 31
	var cols := palette(kind)
	var r := RandomNumberGenerator.new()
	r.seed = _seed
	# a dark scorch plate under it all
	s.merge(LowPoly.cylinder(0.58, 0.5, 0.04, 7, Color(0.15, 0.12, 0.11), _n(), 0.0, 1, 0.04), LowPoly.at(Vector3(0, 0.025, 0)))
	for i in 7:
		var c: Color = cols[i % cols.size()].darkened(0.25)
		var ang := r.randf() * TAU
		var dist := r.randf_range(0.05, 0.55)
		var sz := r.randf_range(0.1, 0.2)
		ball(s, Vector3(sz, sz * r.randf_range(0.4, 0.8), sz * r.randf_range(0.7, 1.1)),
				Vector3(cos(ang) * dist, sz * 0.4, sin(ang) * dist), c, 0, 0.2, Vector3(0, r.randf() * 360.0, 0))
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = s.to_mesh()
	mi.material_override = material()
	root.add_child(mi)
	return root


# ------------------------------------------------------------------ primitives

static func _n() -> int:
	_seed += 1
	return _seed


static func box(s: LowPoly.Soup, size: Vector3, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO, jit: float = 0.0) -> void:
	s.merge(LowPoly.box(size, col, _n(), jit, 1, 0.06), LowPoly.at(pos, rot))


static func cyl(s: LowPoly.Soup, r_bottom: float, r_top: float, h: float, sides: int, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO, jit: float = 0.0) -> void:
	s.merge(LowPoly.cylinder(r_bottom, r_top, h, sides, col, _n(), jit, 1, 0.06), LowPoly.at(pos, rot))


static func frus(s: LowPoly.Soup, bottom: Vector2, top: Vector2, h: float, pos: Vector3, col: Color, top_off: Vector2 = Vector2.ZERO, rot: Vector3 = Vector3.ZERO) -> void:
	s.merge(LowPoly.frustum(bottom, top, h, col, _n(), 0.0, 1, top_off, 0.06), LowPoly.at(pos, rot))


static func ball(s: LowPoly.Soup, radii: Vector3, pos: Vector3, col: Color, detail: int = 1, jit: float = 0.1, rot: Vector3 = Vector3.ZERO) -> void:
	s.merge(LowPoly.boulder(radii, detail, jit, col, _n(), 0.07), LowPoly.at(pos, rot))


## A cylinder / cone between two points.
static func rod(s: LowPoly.Soup, a: Vector3, b: Vector3, r_a: float, r_b: float, sides: int, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.0001:
		return
	var up := d / length
	var axis := Vector3.UP.cross(up)
	var basis := Basis.IDENTITY
	if axis.length() > 0.0001:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(up))
	elif up.y < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	var piece := LowPoly.cylinder(r_a, r_b, length, sides, col, _n(), 0.0, 1, 0.06)
	s.merge(piece, Transform3D(basis, (a + b) * 0.5))


static func _embers() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Embers"
	p.position = Vector3(0, 0.95, 0)
	p.amount = 10
	p.lifetime = 1.1
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, 0.3, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 4
	sm.rings = 2
	sm.material = Fx.glow_material(Color(1.0, 0.62, 0.15, 0.9))
	p.mesh = sm
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0))
	p.scale_amount_curve = c
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = true
	return p


# ------------------------------------------------------------------ bunker

static func _wine_rack(s: LowPoly.Soup) -> void:
	for sx in [-0.62, 0.62]:
		box(s, Vector3(0.09, 1.7, 0.5), Vector3(sx, 0.85, 0), WOOD_DK)
	box(s, Vector3(1.34, 0.09, 0.52), Vector3(0, 1.66, 0), WOOD)
	box(s, Vector3(1.34, 0.08, 0.52), Vector3(0, 0.04, 0), WOOD_DK)
	box(s, Vector3(0.7, 0.12, 0.03), Vector3(0, 1.52, 0.27), glow(GOLD))
	for row in 4:
		var y := 0.3 + 0.36 * float(row)
		box(s, Vector3(1.2, 0.04, 0.46), Vector3(0, y - 0.11, 0), WOOD)
		for j in 4:
			var x := -0.45 + 0.3 * float(j)
			var c := BOTTLE_GREEN if (row + j) % 2 == 0 else BOTTLE_RED
			cyl(s, 0.075, 0.075, 0.36, 6, Vector3(x, y, -0.04), c, Vector3(90, 0, 0))
			cyl(s, 0.05, 0.034, 0.14, 6, Vector3(x, y, 0.21), c, Vector3(90, 0, 0))
			cyl(s, 0.045, 0.045, 0.045, 6, Vector3(x, y, 0.3), GOLD, Vector3(90, 0, 0))


static func _wine_barrel(s: LowPoly.Soup) -> void:
	# cradle
	for cx in [-0.38, 0.38]:
		box(s, Vector3(0.14, 0.34, 0.9), Vector3(cx, 0.17, 0), WOOD_DK)
		box(s, Vector3(0.14, 0.1, 0.62), Vector3(cx, 0.36, 0), WOOD, Vector3(0, 0, 0))
	# the barrel lies along X: bulging middle, narrower ends
	cyl(s, 0.58, 0.58, 0.56, 10, Vector3(0, 0.76, 0), WOOD, Vector3(0, 0, 90))
	cyl(s, 0.5, 0.58, 0.3, 10, Vector3(0.43, 0.76, 0), WOOD, Vector3(0, 0, -90))
	cyl(s, 0.5, 0.58, 0.3, 10, Vector3(-0.43, 0.76, 0), WOOD, Vector3(0, 0, 90))
	# brass hoops
	for hx in [-0.5, -0.2, 0.2, 0.5]:
		cyl(s, 0.6 if absf(hx) < 0.3 else 0.53, 0.6 if absf(hx) < 0.3 else 0.53, 0.07, 10, Vector3(hx, 0.76, 0), GOLD, Vector3(0, 0, 90))
	# end plate with the vintage seal
	cyl(s, 0.38, 0.38, 0.05, 10, Vector3(0.6, 0.76, 0), WOOD_DK, Vector3(0, 0, 90))
	cyl(s, 0.16, 0.16, 0.04, 8, Vector3(0.63, 0.76, 0), glow(GOLD), Vector3(0, 0, 90))
	# gold tap on the front
	cyl(s, 0.06, 0.06, 0.2, 6, Vector3(0, 0.66, 0.6), GOLD, Vector3(90, 0, 0))
	ball(s, Vector3(0.08, 0.08, 0.08), Vector3(0, 0.66, 0.72), glow(GOLD), 0, 0.05)
	# a red wax seal on the bung
	ball(s, Vector3(0.1, 0.06, 0.1), Vector3(0, 1.34, 0.0), VELVET, 0, 0.1)


static func _marble_statue(s: LowPoly.Soup) -> void:
	box(s, Vector3(1.05, 0.22, 1.05), Vector3(0, 0.11, 0), MARBLE_DK)
	box(s, Vector3(0.85, 0.5, 0.85), Vector3(0, 0.47, 0), MARBLE)
	box(s, Vector3(0.9, 0.06, 0.9), Vector3(0, 0.75, 0), GOLD_DK)
	box(s, Vector3(0.5, 0.2, 0.03), Vector3(0, 0.45, 0.44), glow(GOLD))
	# legs and a draped hip
	cyl(s, 0.12, 0.1, 0.62, 6, Vector3(-0.14, 1.08, 0), MARBLE)
	cyl(s, 0.12, 0.1, 0.62, 6, Vector3(0.14, 1.08, 0), MARBLE)
	frus(s, Vector2(0.5, 0.34), Vector2(0.36, 0.26), 0.34, Vector3(0, 1.48, 0), MARBLE)
	# chest, shoulders and head
	frus(s, Vector2(0.36, 0.26), Vector2(0.54, 0.3), 0.44, Vector3(0, 1.84, 0), MARBLE)
	ball(s, Vector3(0.15, 0.18, 0.16), Vector3(0, 2.18, 0.02), MARBLE, 1, 0.08)
	# one arm raised high with a gold torch, one tucked
	rod(s, Vector3(0.26, 1.98, 0), Vector3(0.52, 2.3, 0.04), 0.07, 0.06, 5, MARBLE)
	rod(s, Vector3(-0.26, 1.98, 0), Vector3(-0.3, 1.6, 0.1), 0.07, 0.06, 5, MARBLE)
	cyl(s, 0.05, 0.1, 0.2, 6, Vector3(0.54, 2.4, 0.04), GOLD)
	ball(s, Vector3(0.1, 0.15, 0.1), Vector3(0.54, 2.58, 0.04), glow(Color(1.0, 0.75, 0.25)), 0, 0.1)


static func _gold_toilet(s: LowPoly.Soup) -> void:
	# a red velvet plinth with gold trim
	box(s, Vector3(1.0, 0.12, 1.0), Vector3(0, 0.06, 0), VELVET)
	box(s, Vector3(1.06, 0.04, 1.06), Vector3(0, 0.02, 0), GOLD_DK)
	# pedestal and bowl
	cyl(s, 0.3, 0.24, 0.3, 8, Vector3(0, 0.27, 0.05), GOLD)
	cyl(s, 0.4, 0.3, 0.3, 8, Vector3(0, 0.55, 0.08), GOLD)
	# seat ring and the water
	cyl(s, 0.42, 0.42, 0.06, 8, Vector3(0, 0.73, 0.08), glow(Color(1.0, 0.84, 0.4)))
	cyl(s, 0.27, 0.27, 0.065, 8, Vector3(0, 0.735, 0.08), glow(Color(0.35, 0.75, 0.95)))
	# tank, lid and flush
	box(s, Vector3(0.62, 0.62, 0.24), Vector3(0, 0.98, -0.34), GOLD)
	box(s, Vector3(0.68, 0.07, 0.3), Vector3(0, 1.32, -0.34), glow(Color(1.0, 0.84, 0.4)))
	box(s, Vector3(0.7, 0.05, 0.5), Vector3(0, 0.95, -0.4), GOLD_DK, Vector3(-62, 0, 0))
	ball(s, Vector3(0.05, 0.05, 0.05), Vector3(0.22, 1.37, -0.32), glow(Color(1.0, 0.95, 0.6)), 0, 0.05)
	# gem on the lid
	ball(s, Vector3(0.07, 0.09, 0.07), Vector3(0, 1.42, -0.34), glow(Color(1.0, 0.25, 0.4)), 0, 0.05)


static func _projector(s: LowPoly.Soup) -> void:
	# walnut cart
	box(s, Vector3(0.9, 0.08, 0.6), Vector3(0, 0.75, 0), WOOD)
	for lx in [-0.38, 0.38]:
		for lz in [-0.22, 0.22]:
			cyl(s, 0.045, 0.035, 0.7, 5, Vector3(lx, 0.37, lz), GOLD_DK)
	box(s, Vector3(0.8, 0.05, 0.5), Vector3(0, 0.24, 0), WOOD_DK)
	# the projector body, silver with a black face
	box(s, Vector3(0.78, 0.3, 0.5), Vector3(0, 0.95, 0), IRON_LT)
	box(s, Vector3(0.7, 0.04, 0.4), Vector3(0, 1.12, 0), IRON)
	for i in 4:
		box(s, Vector3(0.05, 0.02, 0.3), Vector3(-0.2 + 0.13 * float(i), 1.14, 0), OBSIDIAN)
	box(s, Vector3(0.78, 0.24, 0.04), Vector3(0, 0.95, 0.27), OBSIDIAN)
	# lens and the beam
	cyl(s, 0.14, 0.12, 0.2, 8, Vector3(0, 0.96, 0.38), IRON, Vector3(90, 0, 0))
	cyl(s, 0.1, 0.1, 0.05, 8, Vector3(0, 0.96, 0.49), glow(Color(0.7, 0.92, 1.0)), Vector3(90, 0, 0))
	cyl(s, 0.09, 0.2, 0.3, 8, Vector3(0, 0.96, 0.66), glow(Color(0.45, 0.78, 1.0)), Vector3(90, 0, 0))
	ball(s, Vector3(0.03, 0.03, 0.03), Vector3(0.3, 0.98, 0.3), glow(Color(1.0, 0.25, 0.2)), 0, 0.0)
	# a reel arm on top
	cyl(s, 0.24, 0.24, 0.05, 8, Vector3(-0.2, 1.3, -0.05), IRON_LT, Vector3(0, 0, 90))
	cyl(s, 0.24, 0.24, 0.05, 8, Vector3(0.2, 1.3, -0.05), IRON_LT, Vector3(0, 0, 90))
	cyl(s, 0.04, 0.04, 0.5, 5, Vector3(0, 1.3, -0.05), GOLD, Vector3(0, 0, 90))


static func _zen_fountain(s: LowPoly.Soup) -> void:
	cyl(s, 0.85, 0.8, 0.34, 10, Vector3(0, 0.17, 0), STONE, Vector3.ZERO, 0.03)
	cyl(s, 0.66, 0.66, 0.06, 10, Vector3(0, 0.33, 0), glow(Color(0.35, 0.85, 0.85)))
	# sand ring and raked pebbles
	for i in 8:
		var a := TAU * float(i) / 8.0
		ball(s, Vector3(0.1, 0.07, 0.09), Vector3(cos(a) * 0.74, 0.36, sin(a) * 0.74), Color(0.55, 0.52, 0.5), 0, 0.2)
	# stacked rocks
	ball(s, Vector3(0.34, 0.2, 0.3), Vector3(0, 0.46, 0), Color(0.36, 0.37, 0.42), 1, 0.18)
	ball(s, Vector3(0.26, 0.17, 0.24), Vector3(0.03, 0.7, 0), Color(0.42, 0.42, 0.48), 1, 0.18)
	ball(s, Vector3(0.18, 0.14, 0.17), Vector3(-0.02, 0.9, 0.01), Color(0.5, 0.5, 0.56), 1, 0.18)
	# bamboo spout with a glowing arc of water
	rod(s, Vector3(0.0, 0.85, 0.0), Vector3(0.45, 1.1, 0.2), 0.07, 0.06, 5, Color(0.55, 0.72, 0.28))
	cyl(s, 0.075, 0.075, 0.04, 5, Vector3(0.25, 0.98, 0.1), Color(0.35, 0.5, 0.15))
	rod(s, Vector3(0.45, 1.06, 0.2), Vector3(0.6, 0.5, 0.28), 0.04, 0.05, 5, glow(Color(0.55, 0.92, 1.0)))
	ball(s, Vector3(0.12, 0.05, 0.12), Vector3(0.62, 0.38, 0.29), glow(Color(0.7, 0.95, 1.0)), 0, 0.1)
	# a lotus
	for i in 5:
		var a2 := TAU * float(i) / 5.0
		ball(s, Vector3(0.09, 0.03, 0.05), Vector3(-0.4 + cos(a2) * 0.1, 0.4, 0.3 + sin(a2) * 0.1), Color(1.0, 0.7, 0.8), 0, 0.1, Vector3(0, -rad_to_deg(a2), 0))


static func _server_rack(s: LowPoly.Soup) -> void:
	box(s, Vector3(0.86, 1.95, 0.72), Vector3(0, 0.975, -0.02), IRON)
	box(s, Vector3(0.9, 0.06, 0.76), Vector3(0, 1.95, -0.02), IRON_LT)
	box(s, Vector3(0.9, 0.06, 0.76), Vector3(0, 0.03, -0.02), IRON_LT)
	var leds: Array[Color] = [Color(0.3, 1.0, 0.45), Color(1.0, 0.65, 0.15), Color(0.35, 0.8, 1.0), Color(0.3, 1.0, 0.45), Color(1.0, 0.3, 0.25)]
	for i in 7:
		var y := 0.2 + 0.25 * float(i)
		box(s, Vector3(0.74, 0.19, 0.05), Vector3(0, y, 0.36), Color(0.1, 0.1, 0.13))
		box(s, Vector3(0.42, 0.04, 0.02), Vector3(-0.1, y - 0.04, 0.39), Color(0.2, 0.2, 0.24))
		for j in 4:
			box(s, Vector3(0.045, 0.045, 0.03), Vector3(0.18 + 0.055 * float(j), y + 0.03, 0.385), glow(leds[(i + j) % leds.size()]))
	# cables hanging out of the side
	rod(s, Vector3(0.43, 1.6, 0.2), Vector3(0.56, 1.0, 0.45), 0.03, 0.03, 5, Color(0.9, 0.35, 0.15))
	rod(s, Vector3(0.43, 1.5, 0.1), Vector3(0.55, 0.9, 0.3), 0.03, 0.03, 5, Color(0.2, 0.55, 0.95))


static func _crystal_lamp(s: LowPoly.Soup) -> void:
	# a gold-and-marble pedestal
	cyl(s, 0.55, 0.5, 0.16, 8, Vector3(0, 0.08, 0), MARBLE_DK)
	cyl(s, 0.32, 0.4, 0.46, 8, Vector3(0, 0.39, 0), MARBLE)
	cyl(s, 0.45, 0.45, 0.07, 8, Vector3(0, 0.64, 0), GOLD)
	# the crystal cluster: tall faceted spikes, pale violet with hot cores
	var spikes: Array = [
		[Vector3(0.0, 0.64, 0.0), Vector3(0.02, 1.45, 0.0), 0.2],
		[Vector3(-0.16, 0.64, 0.08), Vector3(-0.45, 1.12, 0.2), 0.14],
		[Vector3(0.16, 0.64, -0.06), Vector3(0.48, 1.05, -0.1), 0.15],
		[Vector3(0.05, 0.64, 0.18), Vector3(0.12, 1.0, 0.5), 0.12],
		[Vector3(-0.08, 0.64, -0.16), Vector3(-0.2, 1.18, -0.42), 0.12],
	]
	for i in spikes.size():
		var sp: Array = spikes[i]
		var col := glow(Color(0.82, 0.55, 1.0)) if i % 2 == 0 else glow(Color(1.0, 0.65, 0.95))
		var base_col := Color(0.6, 0.35, 0.9)
		rod(s, sp[0], sp[1], float(sp[2]), float(sp[2]) * 0.35, 5, base_col)
		rod(s, (sp[0] as Vector3).lerp(sp[1], 0.45), sp[1], float(sp[2]) * 0.62, 0.0, 5, col)


static func _treadmill(s: LowPoly.Soup) -> void:
	# the runner stands on the belt facing +Z (toward the console, i.e. into the room); the belt's rear is at the wall
	box(s, Vector3(0.8, 0.2, 1.85), Vector3(0, 0.22, -0.05), IRON)
	box(s, Vector3(0.62, 0.05, 1.65), Vector3(0, 0.34, -0.05), Color(0.14, 0.14, 0.17))
	for i in 7:
		box(s, Vector3(0.6, 0.02, 0.05), Vector3(0, 0.375, -0.78 + 0.26 * float(i)), Color(0.24, 0.24, 0.3))
	for sx in [-0.42, 0.42]:
		box(s, Vector3(0.1, 0.14, 1.8), Vector3(sx, 0.36, -0.05), IRON_LT)
	box(s, Vector3(0.82, 0.34, 0.3), Vector3(0, 0.34, -0.86), VELVET)
	# uprights, handlebar and a tilted console with a glowing screen
	for sx in [-0.37, 0.37]:
		rod(s, Vector3(sx, 0.36, 0.6), Vector3(sx, 1.18, 0.74), 0.05, 0.04, 5, IRON_LT)
	cyl(s, 0.032, 0.032, 0.84, 5, Vector3(0, 1.1, 0.78), IRON_LT, Vector3(0, 0, 90))
	box(s, Vector3(0.84, 0.36, 0.12), Vector3(0, 1.3, 0.76), IRON, Vector3(-28, 0, 0))
	box(s, Vector3(0.62, 0.22, 0.03), Vector3(0, 1.31, 0.83), glow(Color(0.3, 0.9, 1.0)), Vector3(-28, 0, 0))
	box(s, Vector3(0.16, 0.05, 0.03), Vector3(0.26, 1.2, 0.86), glow(Color(1.0, 0.35, 0.3)), Vector3(-28, 0, 0))
	# a towel over the bar and a water bottle in the holder
	box(s, Vector3(0.3, 0.2, 0.05), Vector3(-0.2, 1.02, 0.8), Color(0.9, 0.92, 0.95))
	cyl(s, 0.05, 0.05, 0.22, 6, Vector3(0.3, 1.04, 0.6), Color(0.3, 0.7, 0.95))


# ------------------------------------------------------------------ lair

static func _doomsday_console(s: LowPoly.Soup) -> void:
	# hazard-striped base and the sloped desk
	box(s, Vector3(1.5, 0.3, 0.95), Vector3(0, 0.15, 0), IRON)
	for i in 6:
		box(s, Vector3(0.12, 0.14, 0.02), Vector3(-0.62 + 0.25 * float(i), 0.12, 0.48), Color(0.95, 0.78, 0.15) if i % 2 == 0 else OBSIDIAN)
	frus(s, Vector2(1.5, 0.95), Vector2(1.4, 0.4), 0.55, Vector3(0, 0.575, -0.05), IRON_LT, Vector2(0, -0.2))
	# the button deck on the slope: rows of lit buttons
	var bc: Array[Color] = [Color(0.3, 1.0, 0.45), Color(1.0, 0.75, 0.15), Color(0.3, 0.8, 1.0), Color(1.0, 0.3, 0.2)]
	for r in 3:
		var bz := 0.32 - 0.12 * float(r)
		var by := 0.3 + (0.475 - bz) / 0.525 * 0.55 + 0.03
		for c in 6:
			var lit := (r + c) % 3 != 0
			box(s, Vector3(0.12, 0.05, 0.1), Vector3(-0.55 + 0.22 * float(c), by, bz),
					glow(bc[(r * 3 + c) % bc.size()]) if lit else Color(0.15, 0.15, 0.18), Vector3(44, 0, 0))
	# the big red button under a glass dome on the top ledge
	cyl(s, 0.2, 0.2, 0.06, 8, Vector3(0.45, 0.88, -0.2), GOLD_DK)
	cyl(s, 0.15, 0.13, 0.12, 8, Vector3(0.45, 0.95, -0.2), glow(Color(1.0, 0.15, 0.1)))
	ball(s, Vector3(0.19, 0.12, 0.19), Vector3(0.45, 1.0, -0.2), Color(0.9, 0.95, 1.0), 0, 0.03)
	cyl(s, 0.05, 0.05, 0.12, 5, Vector3(-0.1, 0.92, -0.2), GOLD)
	cyl(s, 0.05, 0.05, 0.12, 5, Vector3(-0.35, 0.92, -0.2), GOLD)
	box(s, Vector3(0.3, 0.3, 0.14), Vector3(0, 1.0, -0.36), IRON)
	# monitor wall: two screens, a skull-green radar and a countdown bar
	box(s, Vector3(1.4, 0.7, 0.14), Vector3(0, 1.38, -0.32), IRON, Vector3(-12, 0, 0))
	box(s, Vector3(0.62, 0.5, 0.04), Vector3(-0.35, 1.38, -0.24), glow(Color(0.2, 1.0, 0.5)), Vector3(-12, 0, 0))
	box(s, Vector3(0.62, 0.5, 0.04), Vector3(0.35, 1.38, -0.24), glow(Color(1.0, 0.25, 0.2)), Vector3(-12, 0, 0))
	box(s, Vector3(0.5, 0.07, 0.03), Vector3(0.35, 1.46, -0.21), Color(0.25, 0.04, 0.04), Vector3(-12, 0, 0))
	box(s, Vector3(0.3, 0.07, 0.03), Vector3(0.25, 1.33, -0.21), glow(Color(1.0, 0.85, 0.7)), Vector3(-12, 0, 0))
	ball(s, Vector3(0.12, 0.12, 0.03), Vector3(-0.35, 1.38, -0.21), Color(0.05, 0.3, 0.12), 0, 0.0, Vector3(-12, 0, 0))
	# warning beacon
	cyl(s, 0.09, 0.09, 0.2, 6, Vector3(0.6, 1.84, -0.32), glow(Color(1.0, 0.2, 0.1)))


static func _torture_rack(s: LowPoly.Soup) -> void:
	# a long timber frame on four posts
	for lx in [-0.62, 0.62]:
		for lz in [-0.34, 0.34]:
			box(s, Vector3(0.12, 0.5, 0.12), Vector3(lx, 0.25, lz), WOOD_DK)
	box(s, Vector3(1.5, 0.1, 0.14), Vector3(0, 0.5, -0.34), WOOD)      # rails 1 cm proud of the posts' faces
	box(s, Vector3(1.5, 0.1, 0.14), Vector3(0, 0.5, 0.34), WOOD)
	for i in 6:
		box(s, Vector3(0.14, 0.06, 0.58), Vector3(-0.55 + 0.22 * float(i), 0.52, 0), WOOD, Vector3(0, 0, 0))
	# rollers with rope and a hand wheel at the head
	cyl(s, 0.09, 0.09, 0.8, 6, Vector3(-0.72, 0.62, 0), Color(0.62, 0.46, 0.28), Vector3(90, 0, 0))
	cyl(s, 0.1, 0.1, 0.18, 6, Vector3(0.72, 0.62, 0), Color(0.62, 0.46, 0.28), Vector3(90, 0, 0))
	cyl(s, 0.27, 0.27, 0.05, 8, Vector3(-0.72, 0.62, 0.46), IRON, Vector3(90, 0, 0))
	for i in 4:
		rod(s, Vector3(-0.72, 0.62, 0.46), Vector3(-0.72 + cos(PI * 0.5 * float(i) + 0.4) * 0.4, 0.62 + sin(PI * 0.5 * float(i) + 0.4) * 0.4, 0.46), 0.035, 0.035, 5, WOOD)
	# rope + iron shackles and spikes
	rod(s, Vector3(-0.72, 0.64, -0.1), Vector3(-0.2, 0.6, -0.1), 0.025, 0.025, 4, Color(0.7, 0.6, 0.4))
	rod(s, Vector3(-0.72, 0.64, 0.1), Vector3(-0.2, 0.6, 0.1), 0.025, 0.025, 4, Color(0.7, 0.6, 0.4))
	for i in 4:
		cyl(s, 0.045, 0.0, 0.16, 4, Vector3(0.25 + 0.14 * float(i), 0.64, 0.0), IRON_LT)
	ball(s, Vector3(0.1, 0.06, 0.1), Vector3(0.7, 0.62, 0.3), IRON, 0, 0.1)
	# a stain, and a skull on the foot post
	ball(s, Vector3(0.22, 0.012, 0.16), Vector3(0.1, 0.571, 0.0), Color(0.45, 0.05, 0.06), 0, 0.0)
	ball(s, Vector3(0.1, 0.1, 0.11), Vector3(0.62, 0.62, -0.34), Color(0.9, 0.88, 0.78), 1, 0.1)
	box(s, Vector3(0.02, 0.025, 0.02), Vector3(0.6, 0.64, -0.24), glow(Color(1.0, 0.25, 0.1)))
	box(s, Vector3(0.02, 0.025, 0.02), Vector3(0.66, 0.64, -0.24), glow(Color(1.0, 0.25, 0.1)))


static func _specimen_vat(s: LowPoly.Soup) -> void:
	# iron base and cap with a ring of bolts
	cyl(s, 0.75, 0.7, 0.3, 8, Vector3(0, 0.15, 0), IRON)
	cyl(s, 0.74, 0.7, 0.14, 8, Vector3(0, 1.75, 0), IRON)
	cyl(s, 0.5, 0.44, 0.18, 8, Vector3(0, 1.91, 0), IRON_LT)
	for i in 8:
		var a := TAU * float(i) / 8.0
		ball(s, Vector3(0.04, 0.04, 0.04), Vector3(cos(a) * 0.62, 0.32, sin(a) * 0.62), GOLD_DK, 0, 0.05)
	# the glowing green fluid, ringed by four iron bars
	cyl(s, 0.5, 0.5, 1.44, 8, Vector3(0, 1.03, 0), glow(Color(0.25, 0.95, 0.5)))
	for i in 4:
		var a2 := TAU * float(i) / 4.0 + PI / 4.0
		cyl(s, 0.045, 0.045, 1.5, 5, Vector3(cos(a2) * 0.58, 1.03, sin(a2) * 0.58), IRON_LT)
	# what is floating in it
	ball(s, Vector3(0.24, 0.3, 0.22), Vector3(0.0, 1.05, 0.38), Color(0.4, 0.15, 0.55), 1, 0.15)
	ball(s, Vector3(0.05, 0.05, 0.05), Vector3(-0.08, 1.15, 0.58), glow(Color(1.0, 0.95, 0.3)), 0, 0.0)
	ball(s, Vector3(0.05, 0.05, 0.05), Vector3(0.1, 1.15, 0.58), glow(Color(1.0, 0.95, 0.3)), 0, 0.0)
	rod(s, Vector3(-0.1, 0.85, 0.4), Vector3(-0.3, 0.45, 0.45), 0.07, 0.025, 5, Color(0.4, 0.15, 0.55))
	rod(s, Vector3(0.1, 0.85, 0.4), Vector3(0.3, 0.5, 0.48), 0.07, 0.025, 5, Color(0.4, 0.15, 0.55))
	# pipes to the control box
	rod(s, Vector3(0.0, 1.98, 0.0), Vector3(-0.7, 1.85, -0.3), 0.06, 0.06, 5, IRON_LT)
	box(s, Vector3(0.3, 0.35, 0.2), Vector3(0.7, 0.18, 0.1), IRON_LT)
	box(s, Vector3(0.18, 0.08, 0.02), Vector3(0.7, 0.24, 0.21), glow(Color(1.0, 0.4, 0.2)))


static func _villain_throne(s: LowPoly.Soup) -> void:
	# dais and red carpet
	cyl(s, 1.0, 0.95, 0.16, 8, Vector3(0, 0.08, 0), OBSIDIAN)
	box(s, Vector3(0.7, 0.04, 1.1), Vector3(0, 0.18, 0.4), VELVET)
	# seat and cushion
	box(s, Vector3(0.95, 0.34, 0.8), Vector3(0, 0.38, 0), OBSIDIAN)
	box(s, Vector3(0.78, 0.1, 0.66), Vector3(0, 0.6, 0.02), VELVET)
	# tall back, gold inlay and horns
	frus(s, Vector2(1.05, 0.2), Vector2(0.8, 0.16), 1.6, Vector3(0, 1.4, -0.34), OBSIDIAN)
	box(s, Vector3(0.52, 1.05, 0.04), Vector3(0, 1.25, -0.22), VELVET)
	box(s, Vector3(0.62, 1.15, 0.03), Vector3(0, 1.26, -0.24), GOLD_DK)
	rod(s, Vector3(-0.28, 2.1, -0.34), Vector3(-0.5, 2.65, -0.34), 0.1, 0.0, 5, OBSIDIAN)
	rod(s, Vector3(0.28, 2.1, -0.34), Vector3(0.5, 2.65, -0.34), 0.1, 0.0, 5, OBSIDIAN)
	rod(s, Vector3(0.0, 2.15, -0.34), Vector3(0.0, 2.7, -0.34), 0.12, 0.0, 5, GOLD)
	# glowing eyes in the back
	box(s, Vector3(0.14, 0.05, 0.03), Vector3(-0.14, 1.78, -0.23), glow(Color(1.0, 0.2, 0.15)), Vector3(0, 0, 18))
	box(s, Vector3(0.14, 0.05, 0.03), Vector3(0.14, 1.78, -0.23), glow(Color(1.0, 0.2, 0.15)), Vector3(0, 0, -18))
	# armrests ending in gold claws
	for sx in [-0.52, 0.52]:
		box(s, Vector3(0.14, 0.4, 0.7), Vector3(sx, 0.9, 0.02), OBSIDIAN)
		ball(s, Vector3(0.12, 0.1, 0.14), Vector3(sx, 1.14, 0.38), GOLD, 1, 0.15)
		ball(s, Vector3(0.08, 0.08, 0.08), Vector3(sx, 1.12, 0.5), glow(Color(1.0, 0.85, 0.4)), 0, 0.1)
	# a skull between the feet
	ball(s, Vector3(0.12, 0.12, 0.13), Vector3(0.0, 0.3, 0.46), Color(0.92, 0.9, 0.8), 1, 0.1)


static func _shark_tank(s: LowPoly.Soup) -> void:
	# iron base, gold rim
	box(s, Vector3(1.5, 0.22, 0.9), Vector3(0, 0.11, 0), IRON)
	box(s, Vector3(1.56, 0.06, 0.96), Vector3(0, 0.25, 0), GOLD_DK)
	# water: a deep box with a bright glowing surface and edges
	box(s, Vector3(1.4, 1.1, 0.8), Vector3(0, 0.85, 0), Color(0.12, 0.45, 0.6))
	box(s, Vector3(1.38, 0.05, 0.78), Vector3(0, 1.41, 0), glow(Color(0.35, 0.9, 1.0)))   # inside the water's sides
	box(s, Vector3(1.0, 0.7, 0.04), Vector3(0, 0.85, 0.41), glow(Color(0.2, 0.7, 0.85)))
	# glass corner posts and top rim
	for sx in [-0.72, 0.72]:
		for sz in [-0.42, 0.42]:
			box(s, Vector3(0.08, 1.25, 0.08), Vector3(sx, 0.87, sz), IRON_LT)
	for sz in [-0.46, 0.46]:
		box(s, Vector3(1.56, 0.07, 0.07), Vector3(0, 1.5, sz), IRON)
	for sx in [-0.75, 0.75]:
		box(s, Vector3(0.07, 0.07, 0.96), Vector3(sx, 1.5, 0), IRON)
	# the shark swimming at the front glass
	ball(s, Vector3(0.52, 0.16, 0.14), Vector3(-0.04, 0.88, 0.3), Color(0.55, 0.6, 0.68), 1, 0.08)
	ball(s, Vector3(0.44, 0.07, 0.12), Vector3(-0.04, 0.82, 0.33), Color(0.92, 0.94, 0.96), 1, 0.06)
	rod(s, Vector3(0.45, 0.9, 0.3), Vector3(0.72, 1.1, 0.3), 0.1, 0.02, 4, Color(0.5, 0.55, 0.62))
	rod(s, Vector3(0.45, 0.88, 0.3), Vector3(0.74, 0.62, 0.3), 0.09, 0.02, 4, Color(0.5, 0.55, 0.62))
	rod(s, Vector3(-0.05, 1.0, 0.3), Vector3(-0.15, 1.38, 0.3), 0.08, 0.0, 4, Color(0.5, 0.55, 0.62))
	rod(s, Vector3(-0.1, 0.82, 0.38), Vector3(-0.1, 0.62, 0.5), 0.06, 0.0, 4, Color(0.5, 0.55, 0.62))
	ball(s, Vector3(0.04, 0.04, 0.04), Vector3(-0.4, 0.94, 0.42), Color(0.02, 0.02, 0.03), 0, 0.0)
	box(s, Vector3(0.16, 0.025, 0.02), Vector3(-0.42, 0.8, 0.42), glow(Color(1.0, 0.25, 0.2)))
	# the fin cutting the surface, as a classic
	rod(s, Vector3(0.1, 1.42, 0.0), Vector3(0.0, 1.9, 0.0), 0.12, 0.0, 4, Color(0.5, 0.55, 0.62))
	# bubbles
	for i in 4:
		ball(s, Vector3(0.05, 0.05, 0.05), Vector3(-0.55 + 0.1 * float(i), 0.5 + 0.18 * float(i), 0.43), glow(Color(0.85, 1.0, 1.0)), 0, 0.0)


static func _henchman_locker(s: LowPoly.Soup) -> void:
	var steel := Color(0.36, 0.42, 0.52)
	box(s, Vector3(1.24, 1.7, 0.56), Vector3(0, 0.85, 0), steel)
	box(s, Vector3(1.28, 0.06, 0.6), Vector3(0, 1.72, 0), IRON)
	for sx in [-0.31, 0.31]:
		box(s, Vector3(0.52, 1.5, 0.04), Vector3(sx, 0.85, 0.29), Color(0.42, 0.48, 0.58))
		for i in 4:
			box(s, Vector3(0.34, 0.03, 0.03), Vector3(sx, 1.42 - 0.07 * float(i), 0.32), IRON)
		box(s, Vector3(0.05, 0.16, 0.06), Vector3(sx + (0.18 if sx < 0.0 else -0.18), 0.85, 0.33), GOLD_DK)
	# a hazard stripe, a red jumpsuit sleeve hanging out, and a helmet on top
	for i in 5:
		box(s, Vector3(0.14, 0.08, 0.02), Vector3(-0.5 + 0.25 * float(i), 0.18, 0.32), Color(0.95, 0.78, 0.15) if i % 2 == 0 else OBSIDIAN)
	rod(s, Vector3(0.28, 0.95, 0.3), Vector3(0.36, 0.45, 0.42), 0.08, 0.07, 5, Color(0.85, 0.2, 0.15))
	ball(s, Vector3(0.22, 0.2, 0.22), Vector3(-0.28, 1.9, 0.0), OBSIDIAN, 1, 0.08)
	box(s, Vector3(0.28, 0.06, 0.03), Vector3(-0.28, 1.9, 0.2), glow(Color(1.0, 0.2, 0.15)))


static func _evil_portrait(s: LowPoly.Soup) -> void:
	# an easel
	rod(s, Vector3(-0.4, 0.0, -0.2), Vector3(-0.3, 1.5, -0.1), 0.05, 0.04, 5, WOOD_DK)
	rod(s, Vector3(0.4, 0.0, -0.2), Vector3(0.3, 1.5, -0.1), 0.05, 0.04, 5, WOOD_DK)
	rod(s, Vector3(0.0, 0.0, -0.55), Vector3(0.0, 1.3, -0.15), 0.05, 0.04, 5, WOOD_DK)
	box(s, Vector3(1.0, 0.07, 0.14), Vector3(0, 0.5, 0.0), WOOD)
	# gilded frame
	box(s, Vector3(1.1, 1.4, 0.12), Vector3(0, 1.22, 0.0), GOLD)
	for sx in [-0.5, 0.5]:
		ball(s, Vector3(0.1, 0.1, 0.1), Vector3(sx, 1.88, 0.0), GOLD_DK, 0, 0.1)
		ball(s, Vector3(0.1, 0.1, 0.1), Vector3(sx, 0.56, 0.0), GOLD_DK, 0, 0.1)
	# the canvas: crimson, the villain's black suit, a pale face with glowing eyes and a monocle
	box(s, Vector3(0.88, 1.18, 0.05), Vector3(0, 1.22, 0.07), Color(0.42, 0.06, 0.09))
	frus(s, Vector2(0.84, 0.04), Vector2(0.4, 0.04), 0.5, Vector3(0, 0.88, 0.1), OBSIDIAN)
	box(s, Vector3(0.1, 0.34, 0.03), Vector3(0, 0.92, 0.13), Color(0.85, 0.82, 0.76))
	ball(s, Vector3(0.2, 0.25, 0.04), Vector3(0, 1.3, 0.11), Color(0.9, 0.85, 0.78), 1, 0.05)
	box(s, Vector3(0.07, 0.035, 0.03), Vector3(-0.08, 1.34, 0.15), glow(Color(1.0, 0.2, 0.15)))
	box(s, Vector3(0.07, 0.035, 0.03), Vector3(0.08, 1.34, 0.15), glow(Color(1.0, 0.2, 0.15)))
	box(s, Vector3(0.16, 0.025, 0.03), Vector3(0, 1.2, 0.15), OBSIDIAN)
	cyl(s, 0.07, 0.07, 0.03, 8, Vector3(0.08, 1.34, 0.17), GOLD, Vector3(90, 0, 0))
	# a little brass plaque
	box(s, Vector3(0.4, 0.09, 0.03), Vector3(0, 0.62, 0.08), glow(GOLD))


static func _brazier(s: LowPoly.Soup) -> void:
	# iron tripod, bowl and a pile of burning coal
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.5
		rod(s, Vector3(cos(a) * 0.1, 0.62, sin(a) * 0.1), Vector3(cos(a) * 0.5, 0.0, sin(a) * 0.5), 0.05, 0.07, 5, IRON)
	cyl(s, 0.5, 0.26, 0.28, 8, Vector3(0, 0.66, 0), IRON)
	cyl(s, 0.54, 0.54, 0.05, 8, Vector3(0, 0.82, 0), IRON_LT)
	cyl(s, 0.44, 0.44, 0.05, 8, Vector3(0, 0.83, 0), glow(Color(1.0, 0.35, 0.05)))
	# faceted flames: three cones
	rod(s, Vector3(0.0, 0.84, 0.0), Vector3(0.02, 1.38, 0.0), 0.28, 0.0, 5, glow(Color(1.0, 0.5, 0.08)))
	rod(s, Vector3(-0.15, 0.84, 0.05), Vector3(-0.22, 1.18, 0.1), 0.17, 0.0, 5, glow(Color(1.0, 0.75, 0.2)))
	rod(s, Vector3(0.17, 0.84, -0.04), Vector3(0.26, 1.1, -0.05), 0.15, 0.0, 5, glow(Color(1.0, 0.35, 0.08)))
	rod(s, Vector3(0.0, 0.86, 0.0), Vector3(0.0, 1.12, 0.0), 0.14, 0.0, 5, glow(Color(1.0, 0.92, 0.5)))


# ------------------------------------------------------------------ explosive props (placed by room theme, any site)

## The point a lit fuse sparks from (model space).
static func fuse_point(kind: String) -> Vector3:
	return FUSE_POINTS.get(kind, Vector3(0, height(kind), 0))


## The flame hazard diamond on a front face (facing +Z) at `pos`: a white diamond, a glowing orange one on it, a flame.
static func _flame_sign(s: LowPoly.Soup, pos: Vector3, size: float) -> void:
	box(s, Vector3(size, size, 0.02), pos, Color(0.95, 0.92, 0.85), Vector3(0, 0, 45))
	box(s, Vector3(size * 0.74, size * 0.74, 0.02), pos + Vector3(0, 0, 0.012), glow(Color(1.0, 0.32, 0.08)), Vector3(0, 0, 45))
	box(s, Vector3(size * 0.2, size * 0.34, 0.02), pos + Vector3(0, -0.01, 0.024), glow(Color(1.0, 0.85, 0.3)))


static func _oil_drum(s: LowPoly.Soup) -> void:
	# a 55-gallon drum: red body, two rolling hoops, a dark chime at the foot and an iron rim round the lid
	cyl(s, 0.36, 0.36, 0.92, 10, Vector3(0, 0.5, 0), DRUM_RED)
	cyl(s, 0.37, 0.37, 0.06, 10, Vector3(0, 0.03, 0), DRUM_RED_DK)
	cyl(s, 0.375, 0.375, 0.05, 10, Vector3(0, 0.36, 0), DRUM_RED_DK)
	cyl(s, 0.375, 0.375, 0.05, 10, Vector3(0, 0.68, 0), DRUM_RED_DK)
	cyl(s, 0.37, 0.37, 0.07, 10, Vector3(0, 0.975, 0), IRON)
	cyl(s, 0.33, 0.33, 0.03, 10, Vector3(0, 0.985, 0), Color(0.3, 0.3, 0.34))   # the lid, sunk inside the rim
	# a yellow-and-black hazard band round the shoulder and the flame diamond on the front
	for i in 6:
		var a := deg_to_rad(-50.0 + 20.0 * float(i))
		box(s, Vector3(0.11, 0.1, 0.02), Vector3(sin(a) * 0.365, 0.86, cos(a) * 0.365), HAZARD_YELLOW if i % 2 == 0 else OBSIDIAN, Vector3(0, rad_to_deg(a), 0))
	_flame_sign(s, Vector3(0, 0.53, 0.37), 0.22)
	# the bung caps on the lid and an oily drip down the side
	cyl(s, 0.06, 0.06, 0.05, 6, Vector3(0.16, 1.02, 0.12), GOLD_DK)
	cyl(s, 0.04, 0.04, 0.04, 6, Vector3(-0.18, 1.015, -0.1), GOLD_DK)
	box(s, Vector3(0.05, 0.3, 0.02), Vector3(0.24, 0.8, 0.28), Color(0.08, 0.06, 0.05), Vector3(0, 40, 0))


static func _gas_cylinders(s: LowPoly.Soup) -> void:
	# a wall bracket (two posts, a crossbar) on a steel foot plate, and a chain across the three bottles
	for sx in [-0.5, 0.5]:
		box(s, Vector3(0.07, 1.3, 0.07), Vector3(sx, 0.7, -0.2), IRON)
	box(s, Vector3(1.08, 0.06, 0.06), Vector3(0, 1.12, -0.2), IRON)
	box(s, Vector3(1.1, 0.06, 0.36), Vector3(0, 0.03, -0.02), IRON_LT)
	var cols: Array[Color] = [CYL_GREEN, CYL_MAROON, CYL_BLUE]
	for i in 3:
		var x := -0.32 + 0.32 * float(i)
		var c: Color = cols[i]
		var h := 1.1 if i == 1 else 1.04
		cyl(s, 0.14, 0.14, h, 8, Vector3(x, 0.05 + h * 0.5, 0.0), c)
		# the shoulder, the valve stem, its handwheel
		cyl(s, 0.14, 0.07, 0.12, 8, Vector3(x, 0.1 + h, 0.0), c.lightened(0.15))
		cyl(s, 0.035, 0.035, 0.14, 5, Vector3(x, 0.22 + h, 0.0), GOLD_DK)
		cyl(s, 0.07, 0.07, 0.025, 6, Vector3(x, 0.29 + h, 0.0), IRON_LT)
		# a white band, and the flame diamond lower down
		cyl(s, 0.145, 0.145, 0.08, 8, Vector3(x, 0.05 + h * 0.74, 0.0), Color(0.92, 0.9, 0.86))
		_flame_sign(s, Vector3(x, 0.05 + h * 0.42, 0.15), 0.13)
	box(s, Vector3(1.0, 0.035, 0.035), Vector3(0, 0.95, 0.16), IRON_LT)
	for sx in [-0.49, 0.49]:
		box(s, Vector3(0.035, 0.035, 0.36), Vector3(sx, 0.95, -0.02), IRON_LT)


static func _propane_tank(s: LowPoly.Soup) -> void:
	# a horizontal white tank on two saddles: the body, its rounded ends, a red stripe and the valve dome
	for sx in [-0.38, 0.38]:
		box(s, Vector3(0.12, 0.34, 0.6), Vector3(sx, 0.2, 0), IRON)
		box(s, Vector3(0.16, 0.06, 0.66), Vector3(sx, 0.03, 0), IRON_LT)
	cyl(s, 0.38, 0.38, 0.92, 10, Vector3(0, 0.66, 0), TANK_WHITE, Vector3(0, 0, 90))
	ball(s, Vector3(0.2, 0.37, 0.37), Vector3(0.46, 0.66, 0), TANK_WHITE, 1, 0.0)
	ball(s, Vector3(0.2, 0.37, 0.37), Vector3(-0.46, 0.66, 0), TANK_WHITE, 1, 0.0)
	cyl(s, 0.39, 0.39, 0.1, 10, Vector3(-0.2, 0.66, 0), Color(0.85, 0.2, 0.15), Vector3(0, 0, 90))
	cyl(s, 0.39, 0.39, 0.04, 10, Vector3(0.3, 0.66, 0), HAZARD_YELLOW, Vector3(0, 0, 90))
	# the valve dome, its stem and the hinged cover standing open behind it
	cyl(s, 0.2, 0.17, 0.14, 8, Vector3(0, 1.04, 0), IRON_LT)
	cyl(s, 0.05, 0.05, 0.08, 6, Vector3(0, 1.14, 0), GOLD_DK)
	box(s, Vector3(0.36, 0.03, 0.2), Vector3(0, 1.17, -0.2), IRON, Vector3(35, 0, 0))
	_flame_sign(s, Vector3(0.12, 0.64, 0.395), 0.2)
	# a gauge on the front end
	cyl(s, 0.07, 0.07, 0.04, 8, Vector3(0.645, 0.8, 0.12), Color(0.95, 0.95, 0.9), Vector3(0, 0, 90))
	box(s, Vector3(0.012, 0.06, 0.02), Vector3(0.668, 0.82, 0.12), glow(Color(1.0, 0.25, 0.15)))


static func _battery_pack(s: LowPoly.Soup) -> void:
	# a black UPS cabinet: plinth, body, lid, vent slats on the sides
	box(s, Vector3(0.96, 0.08, 0.66), Vector3(0, 0.04, 0), IRON)
	box(s, Vector3(0.9, 1.3, 0.6), Vector3(0, 0.72, 0), OBSIDIAN)
	box(s, Vector3(0.94, 0.06, 0.64), Vector3(0, 1.395, 0), IRON)
	for i in 5:
		box(s, Vector3(0.02, 0.04, 0.4), Vector3(0.455, 0.5 + 0.12 * float(i), 0), IRON_LT)
		box(s, Vector3(0.02, 0.04, 0.4), Vector3(-0.455, 0.5 + 0.12 * float(i), 0), IRON_LT)
	# the battery modules behind a front window: four rows of cells with orange tags, then the green charge strip
	box(s, Vector3(0.72, 0.84, 0.02), Vector3(0, 0.66, 0.305), Color(0.18, 0.2, 0.24))
	for r in 4:
		for c in 3:
			box(s, Vector3(0.2, 0.16, 0.03), Vector3(-0.23 + 0.23 * float(c), 0.36 + 0.2 * float(r), 0.325), Color(0.32, 0.34, 0.4))
			box(s, Vector3(0.06, 0.04, 0.02), Vector3(-0.23 + 0.23 * float(c), 0.41 + 0.2 * float(r), 0.345), Color(1.0, 0.55, 0.12))
	for i in 5:
		box(s, Vector3(0.08, 0.05, 0.02), Vector3(-0.31 + 0.1 * float(i), 1.2, 0.312), glow(Color(0.3, 1.0, 0.5)) if i < 3 else Color(0.08, 0.2, 0.1))
	# the warning triangle and two fat terminals on top, red and black, with their cables
	box(s, Vector3(0.16, 0.14, 0.02), Vector3(0.3, 1.2, 0.312), glow(HAZARD_YELLOW))
	cyl(s, 0.05, 0.05, 0.08, 6, Vector3(0.28, 1.46, 0.18), Color(0.85, 0.15, 0.12))
	cyl(s, 0.05, 0.05, 0.08, 6, Vector3(-0.28, 1.46, 0.18), Color(0.1, 0.1, 0.12))
	rod(s, Vector3(0.28, 1.5, 0.18), Vector3(0.2, 1.47, -0.3), 0.025, 0.025, 4, Color(0.85, 0.15, 0.12))
	rod(s, Vector3(-0.28, 1.5, 0.18), Vector3(-0.2, 1.47, -0.3), 0.025, 0.025, 4, Color(0.1, 0.1, 0.12))
