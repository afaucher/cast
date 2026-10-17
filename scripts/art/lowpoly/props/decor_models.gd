class_name DecorModels
extends RefCounted
## Faceted low-poly set dressing for the room themes: purely decorative, not priced (the priced props live in
## PropModels). Same look as the rest of the kit: LowPoly soup, MonsterMaterial (ink outline, amber rim,
## emissive faces = vertex alpha 0.5), origin at the base centre, FRONT = +Z (the piece faces
## (sin yaw, cos yaw) when placed at `yaw`). Built to read at game zoom (ortho size 24): chunky shapes, saturated
## colour, nothing finer than ~0.08.
##
##   var node := DecorModels.build("recliner")                       # Node3D "Model" with a "Body" MeshInstance3D
##   DecorModels.build("neon_sign", {"text": "EVIL", "color": Color(1, .2, .15), "dead": [3]})
##
## Animated pieces (neon sign letters, the cinema screen, the patrolling shark fin) carry a DecorAnim child.
## Flat floor decals (chalk circle, pool, moat, carpet, mats) have no ink outline.

const GLYPHS := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".####", "#....", "#....", "#..##", "#...#", "#...#", ".###."],
	"I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
}
const PIXEL := 0.085                ## neon sign: world size of one glyph pixel
const LETTER_GAP := 0.12
const FLAT_KINDS: Array[String] = ["summoning_circle", "pool_basin", "moat_water", "red_carpet", "yoga_mat"]

const CHALK := Color(0.93, 0.9, 0.82)
const WATER := Color(0.2, 0.8, 0.92)
const MAT_COLORS: Array[Color] = [Color(0.2, 0.75, 0.7), Color(0.62, 0.42, 0.92), Color(0.95, 0.5, 0.7), Color(0.95, 0.75, 0.25)]
const BLANKET := Color(0.85, 0.36, 0.14)
const STEEL_BLUE := Color(0.18, 0.24, 0.34)


static func sign_width(text: String) -> float:
	return float(text.length()) * (5.0 * PIXEL + LETTER_GAP) - LETTER_GAP + 0.3


## Footprint (w, d) and height of a kind, from the decor table.
static func footprint(kind: String) -> Vector2:
	var m: Dictionary = RoomThemeDefs.decor(kind)
	return Vector2(float(m.get("w", 1.0)), float(m.get("d", 1.0)))


static func height(kind: String) -> float:
	return float((RoomThemeDefs.decor(kind) as Dictionary).get("h", 1.0))


static func build(kind: String, params: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	if kind == "neon_sign":
		_neon_sign(root, params)
		return root
	var s := LowPoly.Soup.new(7, 0.06)
	PropModels._seed = int(kind.hash() % 9973)
	match kind:
		"recliner": _recliner(s)
		"cinema_screen": _cinema_screen(s)
		"popcorn_machine": _popcorn_machine(s)
		"yoga_mat": _yoga_mat(s, int(params.get("variant", 0)))
		"summoning_circle": _summoning_circle(s, float(params.get("radius", 2.1)))
		"candle": _candle(s)
		"dumbbell_rack": _dumbbell_rack(s)
		"weight_bench": _weight_bench(s)
		"bunk_bed": _bunk_bed(s)
		"chains_cage": _chains_cage(s)
		"specimen_shelf": _specimen_shelf(s)
		"hazard_tape": _hazard_tape(s)
		"wet_floor_sign": _wet_floor_sign(s)
		"pool_lounger": _pool_lounger(s)
		"pool_basin": _pool_basin(s)
		"moat_water": _moat_water(s, float(params.get("radius", 3.0)), float(params.get("width", 0.95)), float(params.get("gap", 48.0)))
		"shark_fin": _shark_fin(s)
		"red_carpet": _red_carpet(s, float(params.get("length", 5.0)))
		"tasting_table": _tasting_table(s)
		"chair": _chair(s)
		"barrel": _barrel(s)
		"desk": _desk(s)
		"monitor": _monitor(s, params.get("color", Color(0.3, 0.95, 0.9)))
		"office_chair": _office_chair(s)
		"rack_cab": _rack_cab(s)
		"crate_stack": _crate_stack(s)
		_:
			PropModels.box(s, Vector3(0.6, 0.6, 0.6), Vector3(0, 0.3, 0), PropModels.GOLD)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = s.to_mesh()
	var mat := MonsterMaterial.make(0.0 if FLAT_KINDS.has(kind) else 2.0)
	mat.set_shader_parameter("glow_gain", 1.5)
	mi.material_override = mat
	if FLAT_KINDS.has(kind):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	match kind:
		"cinema_screen":
			var screen := DecorScreen.make_quad(Vector2(2.9, 1.58))
			screen.position = Vector3(0, 1.45, 0.095)
			root.add_child(screen)
			var anim := DecorAnim.new()
			anim.mode = "screen"
			anim.screen = screen
			root.add_child(anim)
		"shark_fin":
			var fa := DecorAnim.new()
			fa.mode = "fin"
			fa.fin_center = params.get("center", Vector2.ZERO)
			fa.fin_radius = float(params.get("radius", 3.0))
			fa.fin_gap_yaw = float(params.get("gap_yaw", 0.0))
			fa.fin_phase = float(params.get("phase", 0.0))
			fa.fin_speed = float(params.get("speed", 0.6))
			root.add_child(fa)
		"wet_floor_sign":
			root.add_child(_wet_label())
		"candle":
			root.add_child(_flame_light_free())
	return root


# --- small wrappers over the PropModels primitives --------------------------------------------------------------

static func _b(s: LowPoly.Soup, size: Vector3, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
	PropModels.box(s, size, pos, col, rot)


static func _c(s: LowPoly.Soup, r_bottom: float, r_top: float, h: float, sides: int, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
	PropModels.cyl(s, r_bottom, r_top, h, sides, pos, col, rot)


static func _ball(s: LowPoly.Soup, radii: Vector3, pos: Vector3, col: Color, detail: int = 1, jit: float = 0.1, rot: Vector3 = Vector3.ZERO) -> void:
	PropModels.ball(s, radii, pos, col, detail, jit, rot)


static func _rod(s: LowPoly.Soup, a: Vector3, b: Vector3, r_a: float, r_b: float, sides: int, col: Color) -> void:
	PropModels.rod(s, a, b, r_a, r_b, sides, col)


static func _g(c: Color) -> Color:
	return PropModels.glow(c)


## A flat strip on the floor from a to b (X/Z), `width` wide, `h` tall, its underside at y.
static func _seg(s: LowPoly.Soup, a: Vector2, b: Vector2, width: float, h: float, y: float, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var yaw := rad_to_deg(atan2(-d.y, d.x))
	_b(s, Vector3(length, h, width), Vector3((a.x + b.x) * 0.5, y + h * 0.5, (a.y + b.y) * 0.5), col, Vector3(0, yaw, 0))


## A cylinder scaled to an ellipse (rx, rz) merged into the soup.
static func _oval(s: LowPoly.Soup, rx: float, rz: float, h: float, sides: int, pos: Vector3, col: Color) -> void:
	var piece := LowPoly.cylinder(1.0, 1.0, h, sides, col, PropModels._n(), 0.0, 1, 0.05)
	s.merge(piece, LowPoly.at(pos, Vector3.ZERO, Vector3(rx, 1.0, rz)))


# --- the theme pieces ------------------------------------------------------------------------------------------------

static func _recliner(s: LowPoly.Soup) -> void:
	var vel := PropModels.VELVET
	_b(s, Vector3(0.84, 0.2, 0.84), Vector3(0, 0.1, 0.0), PropModels.WOOD_DK)
	_b(s, Vector3(0.78, 0.22, 0.68), Vector3(0, 0.31, 0.04), vel)
	_b(s, Vector3(0.64, 0.13, 0.42), Vector3(0, 0.33, 0.6), vel.darkened(0.2), Vector3(8, 0, 0))
	_b(s, Vector3(0.8, 0.82, 0.2), Vector3(0, 0.78, -0.36), vel.lightened(0.04), Vector3(-14, 0, 0))
	_b(s, Vector3(0.5, 0.24, 0.17), Vector3(0, 1.28, -0.47), vel.lightened(0.15), Vector3(-14, 0, 0))
	for sx: float in [-0.47, 0.47]:
		_b(s, Vector3(0.13, 0.34, 0.66), Vector3(sx, 0.5, 0.02), PropModels.WOOD_DK)
		_b(s, Vector3(0.17, 0.06, 0.62), Vector3(sx, 0.69, 0.02), vel.darkened(0.3))
	_b(s, Vector3(0.09, 0.03, 0.09), Vector3(0.47, 0.73, 0.2), _g(Color(1.0, 0.7, 0.25)))


static func _cinema_screen(s: LowPoly.Soup) -> void:
	# plinth, black frame (the picture is a separate animated quad), drapes and a gold-trimmed valance
	_b(s, Vector3(3.4, 0.3, 0.5), Vector3(0, 0.15, 0.0), PropModels.IRON)
	_b(s, Vector3(3.1, 1.76, 0.16), Vector3(0, 1.45, 0.0), PropModels.OBSIDIAN)
	for sx: float in [-1.7, 1.7]:
		_b(s, Vector3(0.4, 2.3, 0.4), Vector3(sx, 1.4, 0.04), PropModels.VELVET)
		_b(s, Vector3(0.06, 2.3, 0.42), Vector3(sx * 0.9, 1.4, 0.04), PropModels.VELVET.darkened(0.3))
	_b(s, Vector3(3.8, 0.28, 0.44), Vector3(0, 2.55, 0.04), PropModels.VELVET)
	_b(s, Vector3(3.8, 0.05, 0.46), Vector3(0, 2.4, 0.04), PropModels.GOLD)
	_b(s, Vector3(0.9, 0.05, 0.4), Vector3(0, 0.33, 0.12), _g(Color(1.0, 0.8, 0.3)))
	# speakers
	for sx: float in [-1.4, 1.4]:
		_b(s, Vector3(0.28, 0.5, 0.25), Vector3(sx, 0.55, 0.28), PropModels.IRON)


static func _popcorn_machine(s: LowPoly.Soup) -> void:
	_b(s, Vector3(0.8, 0.72, 0.62), Vector3(0, 0.4, 0), PropModels.VELVET)
	_b(s, Vector3(0.82, 0.12, 0.64), Vector3(0, 0.5, 0), PropModels.CREAM)
	for sx: float in [-0.34, 0.34]:
		for sz: float in [-0.2, 0.2]:
			_c(s, 0.1, 0.1, 0.07, 6, Vector3(sx, 0.1, sz), PropModels.IRON, Vector3(0, 0, 90))
	_b(s, Vector3(0.7, 0.04, 0.24), Vector3(0, 0.78, 0.4), PropModels.IRON_LT)
	# the glass box, full of popcorn, with gold posts and a red roof
	_b(s, Vector3(0.7, 0.66, 0.54), Vector3(0, 1.1, 0), _g(Color(1.0, 0.86, 0.45)))
	for sx: float in [-0.37, 0.37]:
		for sz: float in [-0.29, 0.29]:
			_b(s, Vector3(0.05, 0.7, 0.05), Vector3(sx, 1.1, sz), PropModels.GOLD)
	for i in 7:
		var a := float(i) * 0.9
		_ball(s, Vector3(0.1, 0.09, 0.1), Vector3(cos(a) * 0.22, 1.42 + 0.03 * float(i % 3), sin(a) * 0.16), PropModels.CREAM, 0, 0.2)
	PropModels.frus(s, Vector2(0.84, 0.7), Vector2(0.4, 0.34), 0.28, Vector3(0, 1.58, 0), PropModels.VELVET)
	_b(s, Vector3(0.62, 0.17, 0.08), Vector3(0, 1.8, 0), _g(Color(1.0, 0.3, 0.25)))


static func _yoga_mat(s: LowPoly.Soup, variant: int) -> void:
	var col := MAT_COLORS[posmod(variant, MAT_COLORS.size())]
	_b(s, Vector3(0.72, 0.045, 1.8), Vector3(0, 0.0225, 0), col)
	_b(s, Vector3(0.12, 0.05, 1.7), Vector3(0, 0.026, 0), col.lightened(0.2))
	_c(s, 0.075, 0.075, 0.72, 6, Vector3(0, 0.075, -0.93), col.darkened(0.1), Vector3(0, 0, 90))


static func _summoning_circle(s: LowPoly.Soup, radius: float) -> void:
	# double chalk ring, a five-pointed star, tick marks and hot red sigils. The floor under it is a worn ritual
	# rug (VanRug, added by DecorProp), not a dark disc: an opaque disc read as a flat black hole in the floor.
	var segs := 36
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		_seg(s, Vector2(cos(a0), sin(a0)) * radius, Vector2(cos(a1), sin(a1)) * radius, 0.13, 0.03, 0.03, CHALK)
		_seg(s, Vector2(cos(a0), sin(a0)) * (radius - 0.28), Vector2(cos(a1), sin(a1)) * (radius - 0.28), 0.07, 0.03, 0.03, CHALK)
	var star_r := radius - 0.4
	var pts: Array[Vector2] = []
	for i in 5:
		var a := TAU * float(i) / 5.0 - PI * 0.5
		pts.append(Vector2(cos(a), sin(a)) * star_r)
	for i in 5:
		_seg(s, pts[i], pts[(i + 2) % 5], 0.1, 0.03, 0.03, CHALK)
	for i in 5:
		_b(s, Vector3(0.2, 0.05, 0.2), Vector3(pts[i].x, 0.05, pts[i].y), _g(Color(1.0, 0.18, 0.12)), Vector3(0, 45, 0))
	for i in 20:
		var a2 := TAU * float(i) / 20.0 + 0.1
		var p0 := Vector2(cos(a2), sin(a2)) * (radius - 0.06)
		var p1 := Vector2(cos(a2), sin(a2)) * (radius - 0.26)
		_seg(s, p0, p1, 0.05, 0.03, 0.03, CHALK)
	_c(s, 0.22, 0.22, 0.05, 8, Vector3(0, 0.05, 0), _g(Color(1.0, 0.2, 0.15)))


static func _candle(s: LowPoly.Soup) -> void:
	_c(s, 0.1, 0.12, 0.05, 6, Vector3(0, 0.025, 0), Color(0.95, 0.9, 0.78))
	_c(s, 0.065, 0.07, 0.34, 6, Vector3(0, 0.2, 0), PropModels.CREAM)
	_rod(s, Vector3(0, 0.37, 0), Vector3(0, 0.56, 0), 0.06, 0.0, 5, _g(Color(1.0, 0.78, 0.28)))


static func _dumbbell_rack(s: LowPoly.Soup) -> void:
	for sx: float in [-0.8, 0.8]:
		_b(s, Vector3(0.09, 0.98, 0.56), Vector3(sx, 0.49, 0), PropModels.IRON)
	var plates: Array[Color] = [Color(0.85, 0.2, 0.18), Color(0.2, 0.45, 0.9), Color(0.25, 0.75, 0.4), Color(0.95, 0.75, 0.2), Color(0.5, 0.5, 0.56), Color(0.85, 0.2, 0.18)]
	for tier in 2:
		var y := 0.34 + 0.38 * float(tier)
		_b(s, Vector3(1.6, 0.06, 0.52), Vector3(0, y, 0), PropModels.IRON_LT)
		for i in 6:
			var x := -0.65 + 0.26 * float(i)
			var col := plates[(i + tier) % plates.size()]
			_c(s, 0.025, 0.025, 0.4, 5, Vector3(x, y + 0.1, 0), PropModels.IRON_LT, Vector3(90, 0, 0))
			for z: float in [-0.17, 0.17]:
				_c(s, 0.1, 0.1, 0.09, 6, Vector3(x, y + 0.11, z), col, Vector3(90, 0, 0))


static func _weight_bench(s: LowPoly.Soup) -> void:
	# head end (and the barbell on its uprights) at +Z
	_b(s, Vector3(0.34, 0.1, 0.66), Vector3(0, 0.45, -0.4), Color(0.12, 0.12, 0.15))
	_b(s, Vector3(0.34, 0.1, 0.62), Vector3(0, 0.55, 0.28), Color(0.7, 0.1, 0.12), Vector3(-16, 0, 0))
	_b(s, Vector3(0.1, 0.4, 0.1), Vector3(0, 0.2, -0.55), PropModels.IRON)
	_b(s, Vector3(0.1, 0.45, 0.1), Vector3(0, 0.22, 0.3), PropModels.IRON)
	_b(s, Vector3(0.5, 0.05, 0.1), Vector3(0, 0.025, -0.55), PropModels.IRON)
	_b(s, Vector3(0.5, 0.05, 0.1), Vector3(0, 0.025, 0.3), PropModels.IRON)
	for sx: float in [-0.28, 0.28]:
		_b(s, Vector3(0.06, 0.62, 0.06), Vector3(sx, 0.55, 0.6), PropModels.IRON_LT)
		_b(s, Vector3(0.06, 0.05, 0.3), Vector3(sx, 0.025, 0.6), PropModels.IRON_LT)
	_c(s, 0.03, 0.03, 1.2, 6, Vector3(0, 0.86, 0.6), PropModels.IRON_LT, Vector3(0, 0, 90))
	for sx: float in [-0.5, -0.43, 0.43, 0.5]:
		_c(s, 0.2, 0.2, 0.06, 8, Vector3(sx, 0.86, 0.6), Color(0.2, 0.2, 0.24) if absf(sx) > 0.45 else Color(0.8, 0.18, 0.15), Vector3(0, 0, 90))


static func _bunk_bed(s: LowPoly.Soup) -> void:
	for sx: float in [-0.96, 0.96]:
		for sz: float in [-0.46, 0.46]:
			_b(s, Vector3(0.09, 1.6, 0.09), Vector3(sx, 0.8, sz), PropModels.IRON)
	for tier in 2:
		var y := 0.34 + 0.64 * float(tier)
		var blanket := BLANKET if tier == 0 else Color(0.22, 0.5, 0.8)
		for sz: float in [-0.46, 0.46]:
			_b(s, Vector3(1.96, 0.07, 0.07), Vector3(0, y - 0.1, sz), PropModels.IRON_LT)
		_b(s, Vector3(1.86, 0.14, 0.88), Vector3(0, y, 0), Color(0.9, 0.88, 0.82))
		_b(s, Vector3(1.2, 0.17, 0.9), Vector3(0.32, y + 0.02, 0), blanket)
		_b(s, Vector3(0.36, 0.1, 0.4), Vector3(-0.7, y + 0.1, 0), PropModels.CREAM)
	_b(s, Vector3(1.96, 0.06, 0.06), Vector3(0, 1.5, 0.46), PropModels.IRON_LT)
	# the ladder at the right-hand end, and a hazard stripe on the foot rail
	for sz: float in [0.28, 0.5]:
		_b(s, Vector3(0.05, 1.3, 0.05), Vector3(1.04, 0.7, sz), PropModels.IRON_LT)
	for i in 4:
		_b(s, Vector3(0.05, 0.05, 0.28), Vector3(1.04, 0.3 + 0.28 * float(i), 0.39), PropModels.IRON_LT)
	for i in 6:
		_b(s, Vector3(0.14, 0.07, 0.02), Vector3(-0.8 + 0.3 * float(i), 0.2, 0.5), Color(0.95, 0.78, 0.15) if i % 2 == 0 else PropModels.OBSIDIAN)


static func _chains_cage(s: LowPoly.Soup) -> void:
	_b(s, Vector3(1.2, 0.1, 1.2), Vector3(0, 0.05, 0), PropModels.IRON)
	_b(s, Vector3(1.2, 0.08, 1.2), Vector3(0, 1.82, 0), PropModels.IRON)
	var bars: Array[Vector2] = [Vector2(-0.55, -0.55), Vector2(0, -0.55), Vector2(0.55, -0.55), Vector2(-0.55, 0.0), Vector2(0.55, 0.0), Vector2(-0.55, 0.55), Vector2(0.55, 0.55)]
	for b in bars:
		_c(s, 0.035, 0.035, 1.72, 5, Vector3(b.x, 0.95, b.y), PropModels.IRON_LT)
	# the front bars were bent wide open by whatever was inside
	_rod(s, Vector3(-0.27, 0.1, 0.55), Vector3(-0.62, 1.15, 0.95), 0.035, 0.03, 5, PropModels.IRON_LT)
	_rod(s, Vector3(0.0, 0.1, 0.55), Vector3(-0.15, 1.2, 1.0), 0.035, 0.03, 5, PropModels.IRON_LT)
	_rod(s, Vector3(0.27, 0.1, 0.55), Vector3(0.62, 1.1, 0.9), 0.035, 0.03, 5, PropModels.IRON_LT)
	for hy: float in [0.5, 1.2]:
		_b(s, Vector3(1.14, 0.05, 0.05), Vector3(0, hy, -0.55), PropModels.IRON)
		_b(s, Vector3(0.05, 0.05, 1.14), Vector3(-0.55, hy, 0), PropModels.IRON)
		_b(s, Vector3(0.05, 0.05, 1.14), Vector3(0.55, hy, 0), PropModels.IRON)
	# a skull and a broken shackle on the floor of the cage, and a hot glint in its eyes
	_ball(s, Vector3(0.12, 0.11, 0.13), Vector3(-0.15, 0.17, -0.1), Color(0.92, 0.9, 0.8), 1, 0.1)
	_b(s, Vector3(0.025, 0.03, 0.02), Vector3(-0.2, 0.19, 0.02), _g(Color(1.0, 0.25, 0.1)))
	_b(s, Vector3(0.025, 0.03, 0.02), Vector3(-0.11, 0.19, 0.02), _g(Color(1.0, 0.25, 0.1)))
	# chains snapped off the top: a few links hang down, the rest rise out of sight
	for i in 9:
		var y := 1.86 + 0.12 * float(i)
		_b(s, Vector3(0.07, 0.11, 0.035), Vector3(0.0, y, 0.0), PropModels.IRON_LT, Vector3(0, 90 if i % 2 == 0 else 0, 0))
	for i in 4:
		_b(s, Vector3(0.07, 0.11, 0.035), Vector3(0.5, 1.7 - 0.12 * float(i), 0.55), PropModels.IRON_LT, Vector3(0, 90 if i % 2 == 0 else 0, 0))


static func _specimen_shelf(s: LowPoly.Soup) -> void:
	for sx: float in [-0.86, 0.0, 0.86]:
		_b(s, Vector3(0.08, 1.95, 0.5), Vector3(sx, 0.975, 0), PropModels.IRON)
	var glows: Array[Color] = [Color(0.3, 1.0, 0.5), Color(0.7, 0.35, 1.0), Color(1.0, 0.8, 0.3), Color(0.3, 1.0, 0.5)]
	for tier in 4:
		var y := 0.1 + 0.5 * float(tier)
		_b(s, Vector3(1.78, 0.05, 0.5), Vector3(0, y, 0), PropModels.IRON_LT)
		if tier == 0:
			_b(s, Vector3(0.5, 0.3, 0.4), Vector3(-0.45, 0.28, 0), PropModels.WOOD)
			_b(s, Vector3(0.4, 0.2, 0.36), Vector3(0.4, 0.23, 0.02), PropModels.WOOD_DK)
			continue
		for i in 5:
			var x := -0.7 + 0.35 * float(i)
			var col := glows[(i + tier) % glows.size()]
			if (i + tier) % 5 == 3:
				# smashed: a stump of glass, a green puddle
				_c(s, 0.1, 0.1, 0.1, 6, Vector3(x, y + 0.08, 0.0), Color(0.55, 0.75, 0.7))
				_b(s, Vector3(0.26, 0.012, 0.2), Vector3(x, y + 0.035, 0.05), _g(col))
				continue
			_c(s, 0.11, 0.11, 0.3, 6, Vector3(x, y + 0.18, 0.0), _g(col))
			_c(s, 0.12, 0.12, 0.05, 6, Vector3(x, y + 0.36, 0.0), PropModels.IRON)
			_ball(s, Vector3(0.05, 0.05, 0.05), Vector3(x, y + 0.18, 0.02), Color(0.2, 0.1, 0.25), 0, 0.2)


static func _hazard_tape(s: LowPoly.Soup) -> void:
	var yel := Color(0.98, 0.8, 0.12)
	for sx: float in [-1.1, 1.1]:
		for i in 4:
			_c(s, 0.06, 0.06, 0.22, 5, Vector3(sx, 0.11 + 0.22 * float(i), 0), yel if i % 2 == 0 else PropModels.OBSIDIAN)
		_c(s, 0.14, 0.16, 0.05, 6, Vector3(sx, 0.025, 0), PropModels.IRON)
	for row in 2:
		var y := 0.74 - 0.18 * float(row)
		for i in 14:
			var x := -1.04 + 0.16 * float(i)
			var sag := 0.03 * sin(PI * float(i) / 13.0)
			_b(s, Vector3(0.17, 0.12, 0.02), Vector3(x, y - sag, 0.0), yel if i % 2 == 0 else PropModels.OBSIDIAN, Vector3(0, 0, 18 if i % 2 == 0 else -18))


static func _wet_floor_sign(s: LowPoly.Soup) -> void:
	var yel := Color(0.98, 0.82, 0.1)
	_b(s, Vector3(0.5, 0.82, 0.04), Vector3(0, 0.45, 0.12), yel, Vector3(-12, 0, 0))
	_b(s, Vector3(0.5, 0.82, 0.04), Vector3(0, 0.45, -0.12), yel.darkened(0.15), Vector3(12, 0, 0))
	_b(s, Vector3(0.56, 0.06, 0.18), Vector3(0, 0.88, 0.0), yel.darkened(0.2))
	_b(s, Vector3(0.5, 0.04, 0.36), Vector3(0, 0.02, 0.0), yel.darkened(0.3))
	# the slipping stick-figure on the front panel
	_ball(s, Vector3(0.05, 0.05, 0.03), Vector3(0.04, 0.78, 0.17), PropModels.OBSIDIAN, 0, 0.1)
	_b(s, Vector3(0.07, 0.2, 0.025), Vector3(0.0, 0.62, 0.165), PropModels.OBSIDIAN, Vector3(-12, 0, 24))
	_b(s, Vector3(0.05, 0.2, 0.025), Vector3(-0.1, 0.46, 0.15), PropModels.OBSIDIAN, Vector3(-12, 0, -40))
	_b(s, Vector3(0.05, 0.18, 0.025), Vector3(0.08, 0.45, 0.15), PropModels.OBSIDIAN, Vector3(-12, 0, 20))


static func _wet_label() -> Label3D:
	var l := Label3D.new()
	l.text = "WET\nFLOOR"
	l.font_size = 40
	l.pixel_size = 0.0065
	l.shaded = false
	l.modulate = Color(0.08, 0.06, 0.04)
	l.outline_size = 0
	l.position = Vector3(0, 0.31, 0.15)
	l.rotation_degrees = Vector3(-12, 0, 0)
	return l


static func _pool_lounger(s: LowPoly.Soup) -> void:
	# the sitter faces +Z (feet end); the backrest is at -Z
	for sx: float in [-0.34, 0.34]:
		for sz: float in [-0.8, 0.7]:
			_b(s, Vector3(0.07, 0.26, 0.07), Vector3(sx, 0.13, sz), PropModels.IRON_LT)
	_b(s, Vector3(0.72, 0.1, 1.0), Vector3(0, 0.3, 0.3), Color(0.96, 0.96, 0.98))
	_b(s, Vector3(0.72, 0.1, 0.74), Vector3(0, 0.5, -0.5), Color(0.96, 0.96, 0.98), Vector3(-30, 0, 0))
	for i in 3:
		_b(s, Vector3(0.74, 0.115, 0.1), Vector3(0, 0.31, 0.0 + 0.3 * float(i)), Color(0.2, 0.7, 0.9))
	_b(s, Vector3(0.5, 0.1, 0.34), Vector3(0, 0.66, -0.7), Color(1.0, 0.55, 0.45), Vector3(-30, 0, 0))


static func _pool_basin(s: LowPoly.Soup) -> void:
	# a stone rim, glowing water, lane lines and a ladder
	_oval(s, 2.2, 1.6, 0.14, 18, Vector3(0, 0.07, 0), Color(0.86, 0.84, 0.8))
	_oval(s, 1.98, 1.38, 0.05, 18, Vector3(0, 0.155, 0), _g(WATER))
	_oval(s, 1.7, 1.1, 0.03, 18, Vector3(0, 0.185, 0), _g(Color(0.5, 0.95, 1.0)))
	for i in 5:
		var x := -1.3 + 0.65 * float(i)
		_b(s, Vector3(0.45, 0.04, 0.08), Vector3(x, 0.21, -0.3 + 0.28 * float(i % 3)), _g(Color(0.85, 1.0, 1.0)), Vector3(0, 18 * float(i), 0))
	for sx: float in [-0.3, 0.3]:
		_rod(s, Vector3(sx, 0.16, 1.5), Vector3(sx, 0.62, 1.5), 0.03, 0.03, 5, PropModels.IRON_LT)
		_rod(s, Vector3(sx, 0.62, 1.5), Vector3(sx, 0.64, 1.18), 0.03, 0.03, 5, PropModels.IRON_LT)


static func _moat_water(s: LowPoly.Soup, radius: float, width: float, gap_deg: float) -> void:
	# the ring is built around local +Z (the door side); the gap there carries a plank bridge
	var segs := 40
	var gap := deg_to_rad(gap_deg) * 0.5
	var seg_len := TAU * radius / float(segs) * 1.08
	for i in segs:
		var phi := TAU * (float(i) + 0.5) / float(segs) - PI      # 0 = +Z
		if absf(wrapf(phi, -PI, PI)) < gap:
			continue
		var pos := Vector2(sin(phi) * radius, cos(phi) * radius)
		var col := WATER if i % 2 == 0 else WATER.lightened(0.15)
		_b(s, Vector3(seg_len, 0.1, width), Vector3(pos.x, 0.05, pos.y), _g(col), Vector3(0, rad_to_deg(phi), 0))
		for edge: float in [-1.0, 1.0]:
			var rr := radius + edge * (width * 0.5 + 0.06)
			_b(s, Vector3(seg_len, 0.15, 0.13), Vector3(sin(phi) * rr, 0.075, cos(phi) * rr), Color(0.4, 0.38, 0.42), Vector3(0, rad_to_deg(phi), 0))
	# the bridge: planks laid across the ring where the gap is
	for i in 5:
		var x := (float(i) - 2.0) * 0.3
		_b(s, Vector3(0.26, 0.12, width + 0.8), Vector3(x, 0.14, radius), PropModels.WOOD if i % 2 == 0 else PropModels.WOOD_DK)
	for sx: float in [-0.78, 0.78]:
		_b(s, Vector3(0.07, 0.07, width + 0.7), Vector3(sx, 0.22, radius), PropModels.IRON)


static func _shark_fin(s: LowPoly.Soup) -> void:
	var grey := Color(0.5, 0.55, 0.62)
	PropModels.frus(s, Vector2(0.07, 0.5), Vector2(0.02, 0.07), 0.5, Vector3(0, 0.25, 0), grey, Vector2(0, -0.22))
	PropModels.frus(s, Vector2(0.05, 0.22), Vector2(0.015, 0.04), 0.22, Vector3(0, 0.11, -0.45), grey.darkened(0.1), Vector2(0, -0.08))
	_c(s, 0.34, 0.36, 0.03, 8, Vector3(0, 0.015, 0.05), _g(Color(0.6, 0.98, 1.0)))


static func _red_carpet(s: LowPoly.Soup, length: float) -> void:
	_b(s, Vector3(1.3, 0.04, length), Vector3(0, 0.02, 0), PropModels.VELVET)
	for sx: float in [-0.62, 0.62]:
		_b(s, Vector3(0.1, 0.05, length), Vector3(sx, 0.025, 0), PropModels.GOLD)
	var n := maxi(2, int(length / 1.1))
	for i in n:
		var z := -length * 0.5 + (float(i) + 0.5) * length / float(n)
		_b(s, Vector3(0.34, 0.05, 0.34), Vector3(0, 0.026, z), PropModels.GOLD_DK, Vector3(0, 45, 0))
		_b(s, Vector3(0.18, 0.055, 0.18), Vector3(0, 0.028, z), PropModels.VELVET.darkened(0.2), Vector3(0, 45, 0))


static func _tasting_table(s: LowPoly.Soup) -> void:
	_c(s, 0.4, 0.4, 0.07, 10, Vector3(0, 0.035, 0), PropModels.WOOD_DK)
	_c(s, 0.13, 0.15, 0.82, 8, Vector3(0, 0.45, 0), PropModels.WOOD_DK)
	_c(s, 0.78, 0.78, 0.09, 10, Vector3(0, 0.92, 0), PropModels.WOOD)
	_c(s, 0.6, 0.6, 0.02, 10, Vector3(0, 0.975, 0), PropModels.VELVET)
	# bottles, a decanter and glasses
	_c(s, 0.05, 0.05, 0.3, 6, Vector3(-0.2, 1.13, 0.05), PropModels.BOTTLE_GREEN)
	_c(s, 0.05, 0.05, 0.3, 6, Vector3(-0.08, 1.13, -0.12), PropModels.BOTTLE_RED)
	_c(s, 0.09, 0.07, 0.22, 6, Vector3(0.22, 1.1, -0.05), _g(Color(0.95, 0.2, 0.3)))
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.5
		_c(s, 0.04, 0.025, 0.12, 5, Vector3(cos(a) * 0.4, 1.04, sin(a) * 0.4), _g(Color(1.0, 0.9, 0.9)))
	_b(s, Vector3(0.3, 0.04, 0.2), Vector3(0.05, 1.0, 0.32), PropModels.CREAM, Vector3(0, 20, 0))


static func _chair(s: LowPoly.Soup) -> void:
	_b(s, Vector3(0.46, 0.07, 0.46), Vector3(0, 0.5, 0), PropModels.WOOD)
	_b(s, Vector3(0.4, 0.07, 0.4), Vector3(0, 0.56, 0.01), PropModels.VELVET)
	for sx: float in [-0.2, 0.2]:
		for sz: float in [-0.2, 0.2]:
			_b(s, Vector3(0.06, 0.5, 0.06), Vector3(sx, 0.25, sz), PropModels.WOOD_DK)
	_b(s, Vector3(0.46, 0.5, 0.06), Vector3(0, 0.82, -0.21), PropModels.WOOD, Vector3(-6, 0, 0))
	_b(s, Vector3(0.36, 0.3, 0.04), Vector3(0, 0.84, -0.17), PropModels.VELVET, Vector3(-6, 0, 0))


static func _barrel(s: LowPoly.Soup) -> void:
	_c(s, 0.37, 0.46, 0.5, 10, Vector3(0, 0.25, 0), PropModels.WOOD)
	_c(s, 0.46, 0.37, 0.5, 10, Vector3(0, 0.75, 0), PropModels.WOOD)
	for hy: float in [0.12, 0.5, 0.88]:
		_c(s, 0.47 if hy > 0.2 and hy < 0.8 else 0.4, 0.47 if hy > 0.2 and hy < 0.8 else 0.4, 0.06, 10, Vector3(0, hy, 0), PropModels.IRON_LT if hy == 0.5 else PropModels.GOLD_DK)
	_c(s, 0.36, 0.36, 0.04, 10, Vector3(0, 1.0, 0), PropModels.WOOD_DK)
	_b(s, Vector3(0.1, 0.05, 0.1), Vector3(0.1, 1.04, 0.05), PropModels.VELVET)


static func _desk(s: LowPoly.Soup) -> void:
	_b(s, Vector3(1.7, 0.07, 0.82), Vector3(0, 0.82, 0), PropModels.WOOD_DK)
	for sx: float in [-0.7, 0.7]:
		_b(s, Vector3(0.36, 0.78, 0.72), Vector3(sx, 0.39, 0), PropModels.IRON)
		for i in 3:
			_b(s, Vector3(0.3, 0.2, 0.03), Vector3(sx, 0.18 + 0.24 * float(i), 0.37), PropModels.IRON_LT)
			_b(s, Vector3(0.12, 0.03, 0.03), Vector3(sx, 0.2 + 0.24 * float(i), 0.39), PropModels.GOLD)
	_b(s, Vector3(1.0, 0.5, 0.04), Vector3(0, 0.5, -0.34), PropModels.IRON)
	_b(s, Vector3(0.5, 0.025, 0.17), Vector3(0, 0.865, 0.22), Color(0.12, 0.12, 0.15))
	_b(s, Vector3(0.44, 0.012, 0.1), Vector3(0, 0.882, 0.22), _g(Color(0.35, 0.8, 1.0)))
	_c(s, 0.05, 0.05, 0.1, 6, Vector3(0.6, 0.91, 0.1), Color(0.95, 0.95, 0.9))
	_b(s, Vector3(0.28, 0.05, 0.36), Vector3(-0.58, 0.88, 0.12), PropModels.CREAM, Vector3(0, 14, 0))


static func _monitor(s: LowPoly.Soup, glow_col: Color) -> void:
	_b(s, Vector3(0.24, 0.03, 0.18), Vector3(0, 0.015, 0), PropModels.IRON)
	_b(s, Vector3(0.06, 0.22, 0.05), Vector3(0, 0.13, -0.02), PropModels.IRON)
	_b(s, Vector3(0.74, 0.44, 0.06), Vector3(0, 0.45, 0), PropModels.OBSIDIAN, Vector3(-6, 0, 0))
	_b(s, Vector3(0.66, 0.36, 0.03), Vector3(0, 0.45, 0.04), _g(glow_col), Vector3(-6, 0, 0))
	_b(s, Vector3(0.3, 0.04, 0.025), Vector3(-0.12, 0.55, 0.06), _g(glow_col.lightened(0.5)), Vector3(-6, 0, 0))


static func _office_chair(s: LowPoly.Soup) -> void:
	_c(s, 0.05, 0.05, 0.3, 5, Vector3(0, 0.25, 0), PropModels.IRON)
	for i in 5:
		var a := TAU * float(i) / 5.0
		_rod(s, Vector3(0, 0.1, 0), Vector3(cos(a) * 0.3, 0.07, sin(a) * 0.3), 0.04, 0.03, 4, PropModels.IRON_LT)
		_ball(s, Vector3(0.05, 0.05, 0.05), Vector3(cos(a) * 0.3, 0.05, sin(a) * 0.3), PropModels.OBSIDIAN, 0, 0.1)
	_b(s, Vector3(0.52, 0.09, 0.5), Vector3(0, 0.5, 0.02), Color(0.18, 0.18, 0.22))
	_b(s, Vector3(0.48, 0.6, 0.08), Vector3(0, 0.88, -0.25), Color(0.18, 0.18, 0.22), Vector3(-10, 0, 0))
	_b(s, Vector3(0.38, 0.25, 0.04), Vector3(0, 1.0, -0.2), PropModels.VELVET, Vector3(-10, 0, 0))
	for sx: float in [-0.3, 0.3]:
		_b(s, Vector3(0.05, 0.05, 0.3), Vector3(sx, 0.68, -0.02), PropModels.IRON)


static func _rack_cab(s: LowPoly.Soup) -> void:
	_b(s, Vector3(0.92, 2.0, 0.8), Vector3(0, 1.0, -0.02), STEEL_BLUE)
	_b(s, Vector3(0.96, 0.06, 0.84), Vector3(0, 2.0, -0.02), PropModels.IRON_LT)
	var leds: Array[Color] = [Color(0.3, 1.0, 0.45), Color(0.35, 0.8, 1.0), Color(1.0, 0.65, 0.15), Color(0.3, 1.0, 0.45)]
	for i in 6:
		var y := 0.25 + 0.3 * float(i)
		_b(s, Vector3(0.8, 0.24, 0.05), Vector3(0, y, 0.38), Color(0.08, 0.09, 0.12))
		for j in 5:
			_b(s, Vector3(0.05, 0.05, 0.03), Vector3(-0.28 + 0.07 * float(j), y + 0.04, 0.41), _g(leds[(i + j) % leds.size()]))
		_b(s, Vector3(0.3, 0.04, 0.02), Vector3(0.18, y - 0.04, 0.41), Color(0.22, 0.24, 0.3))


static func _crate_stack(s: LowPoly.Soup) -> void:
	_b(s, Vector3(1.0, 0.6, 1.0), Vector3(0, 0.3, 0), PropModels.WOOD)
	for sx: float in [-0.45, 0.45]:
		_b(s, Vector3(0.1, 0.62, 1.02), Vector3(sx, 0.3, 0), PropModels.WOOD_DK)
	_b(s, Vector3(0.84, 0.5, 0.84), Vector3(0.04, 0.85, 0.0), PropModels.WOOD.lightened(0.05), Vector3(0, 22, 0))
	_b(s, Vector3(0.12, 0.52, 0.86), Vector3(0.04, 0.85, 0.0), PropModels.WOOD_DK, Vector3(0, 22, 0))
	_b(s, Vector3(0.4, 0.06, 0.02), Vector3(0, 0.45, 0.52), _g(PropModels.GOLD))
	for i in 4:
		var a := float(i) * 1.7
		_c(s, 0.07, 0.07, 0.13, 6, Vector3(0.04 + cos(a) * 0.18, 1.16, sin(a) * 0.18), Color(0.75, 0.78, 0.82))
		_c(s, 0.072, 0.072, 0.05, 6, Vector3(0.04 + cos(a) * 0.18, 1.16, sin(a) * 0.18), PropModels.VELVET)


# --- animated pieces ------------------------------------------------------------------------------------------------

## A flickering candle flame is just the glow facets; this hook is kept for pieces that get a light later.
static func _flame_light_free() -> Node3D:
	var n := Node3D.new()
	n.name = "Flame"
	return n


## A standing neon sign: two posts, a dark backing and one tube-glass mesh per letter (each with its own
## material, so DecorAnim can flicker letters one by one). params: text, color, dead (indices of dead letters).
static func _neon_sign(root: Node3D, params: Dictionary) -> void:
	var text := String(params.get("text", "SIGN"))
	var col: Color = params.get("color", Color(1.0, 0.2, 0.3))
	var dead: Array = params.get("dead", [])
	var n := text.length()
	var w := sign_width(text)
	var s := LowPoly.Soup.new(11, 0.05)
	PropModels._seed = int(text.hash() % 9973)
	for sx: float in [-0.5, 0.5]:
		_b(s, Vector3(0.08, 1.25, 0.08), Vector3(sx * (w - 0.2), 0.625, -0.04), PropModels.IRON)
		_b(s, Vector3(0.3, 0.05, 0.3), Vector3(sx * (w - 0.2), 0.025, -0.04), PropModels.IRON)
	_b(s, Vector3(w, 0.92, 0.07), Vector3(0, 1.72, -0.05), PropModels.OBSIDIAN)
	_b(s, Vector3(w + 0.08, 0.05, 0.1), Vector3(0, 2.2, -0.05), PropModels.IRON_LT)
	_b(s, Vector3(w + 0.08, 0.05, 0.1), Vector3(0, 1.25, -0.05), PropModels.IRON_LT)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = s.to_mesh()
	var bm := MonsterMaterial.make(1.8)
	body.material_override = bm
	root.add_child(body)
	var letters: Array[MeshInstance3D] = []
	var mats: Array[ShaderMaterial] = []
	var pitch := 5.0 * PIXEL + LETTER_GAP
	for i in n:
		var ch := text.substr(i, 1)
		var is_dead := dead.has(i)
		var ls := LowPoly.Soup.new(13 + i, 0.03)
		var rows: Array = GLYPHS.get(ch, GLYPHS["O"])
		for r in 7:
			var line: String = rows[r]
			for c in 5:
				if line.substr(c, 1) == "#":
					var px := (float(c) - 2.0) * PIXEL
					var py := (3.0 - float(r)) * PIXEL
					PropModels.box(ls, Vector3(PIXEL * 1.02, PIXEL * 1.02, 0.05), Vector3(px, py, 0), PropModels.glow(Color(0.3, 0.1, 0.06) if is_dead else col))
		var mi := MeshInstance3D.new()
		mi.name = "Letter%d" % i
		mi.mesh = ls.to_mesh(0.0)
		var m := MonsterMaterial.make(0.0)
		m.set_shader_parameter("glow_gain", 0.12 if is_dead else 1.9)
		mi.material_override = m
		mi.position = Vector3((float(i) - float(n - 1) * 0.5) * pitch, 1.72, 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		letters.append(mi)
		mats.append(m)
	var anim := DecorAnim.new()
	anim.mode = "neon"
	anim.mats = mats
	anim.dead = dead.duplicate()
	root.add_child(anim)
