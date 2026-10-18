extends RefCounted
## Pool options lab (docs/design/pool-options.md): look-dev models for water rooms. Lab-only and cosmetic: nothing here
## is placed by the game. Same kit as DecorModels / PropModels (LowPoly soup, MonsterMaterial: ink outline, amber rim,
## vertex alpha 0.5 = emissive face), origin at the base centre, FRONT = +Z. No class_name (the lab preloads it).
##
##   const PoolProps := preload("res://scripts/art/lowpoly/props/pool_props.gd")
##   add_child(PoolProps.build("shark"))
##
## Kinds: shark, eel, jellyfish, specimen, ladder (params depth), grab_rails, catwalk (length), gantry (span),
##        ripple (radius), steam, flames (height, radius), lifebuoy, drain_grate, stair_rail (length, drop),
##        hazard_sign, valve_wheel, pipe_run (length), lab_bench.

const SHARK := Color(0.47, 0.53, 0.62)
const BELLY := Color(0.9, 0.92, 0.95)
const STEEL := Color(0.52, 0.56, 0.62)
const STEEL_DK := Color(0.25, 0.27, 0.32)
const HAZARD := Color(0.98, 0.78, 0.12)
const FOAM := Color(0.82, 0.98, 1.0)
const TOXIC := Color(0.45, 1.0, 0.35)


static func g(c: Color) -> Color:
	return PropModels.glow(c)


static func build(kind: String, params: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var s := LowPoly.Soup.new(11, 0.05)
	var outline := 2.0
	match kind:
		"shark": _shark(s)
		"eel": _eel(s, float(params.get("phase", 0.0)))
		"jellyfish": _jellyfish(s)
		"specimen": _specimen(s)
		"ladder": _ladder(s, float(params.get("depth", 1.5)))
		"catwalk": _catwalk(s, float(params.get("length", 6.0)), bool(params.get("rail_left", true)), bool(params.get("rail_right", true)))
		"gantry": _gantry(s, float(params.get("span", 5.0)), float(params.get("height", 3.2)))
		"ripple":
			_ripple(s, float(params.get("radius", 0.6)))
			outline = 0.0
		"steam": _steam(s)
		"flames":
			_flames(s, float(params.get("height", 1.8)), float(params.get("radius", 0.32)))
			outline = 0.0
		"lifebuoy": _lifebuoy(s)
		"drain_grate":
			_drain(s)
			outline = 0.0
		"hazard_sign": _hazard_sign(s, params.get("color", HAZARD))
		"valve_wheel": _valve(s)
		"pipe_run": _pipe_run(s, float(params.get("length", 4.0)))
		"lab_bench": _lab_bench(s)
		"stair_rail": _stair_rail(s, float(params.get("length", 2.0)), float(params.get("drop", 1.2)))
		_:
			PropModels.box(s, Vector3(0.5, 0.5, 0.5), Vector3(0, 0.25, 0), PropModels.GOLD)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = s.to_mesh()
	var mat := MonsterMaterial.make(outline)
	mat.set_shader_parameter("glow_gain", 1.6)
	mi.material_override = mat
	if outline == 0.0:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root


# --- water monsters ---------------------------------------------------------------------------------------------

## A 2.4-long shark swimming toward +Z, its back at y = 0 (so the dorsal fin, 0.55 tall, breaks a surface at y = 0
## when the model is placed about 0.25 under it).
static func _shark(s: LowPoly.Soup) -> void:
	PropModels.ball(s, Vector3(0.36, 0.3, 1.05), Vector3(0, -0.3, 0.1), SHARK, 1, 0.06)
	PropModels.ball(s, Vector3(0.3, 0.16, 0.85), Vector3(0, -0.46, 0.2), BELLY, 1, 0.05)
	# snout and jaw with teeth
	PropModels.frus(s, Vector2(0.5, 0.4), Vector2(0.18, 0.12), 0.45, Vector3(0, -0.3, 1.25), SHARK, Vector2.ZERO, Vector3(90, 0, 0))
	PropModels.box(s, Vector3(0.42, 0.06, 0.32), Vector3(0, -0.47, 1.05), Color(0.55, 0.12, 0.16))
	for i in 5:
		var x := -0.16 + 0.08 * float(i)
		PropModels.frus(s, Vector2(0.05, 0.05), Vector2(0.0, 0.0), 0.07, Vector3(x, -0.43, 1.18 - absf(x) * 0.6), Color(0.98, 0.97, 0.9))
	# eyes
	for sx: float in [-0.21, 0.21]:
		PropModels.ball(s, Vector3(0.045, 0.045, 0.045), Vector3(sx, -0.22, 0.95), Color(0.03, 0.03, 0.04), 0, 0.0)
	# tail stock and the crescent tail
	PropModels.frus(s, Vector2(0.4, 0.4), Vector2(0.12, 0.16), 0.75, Vector3(0, -0.3, -1.15), SHARK, Vector2.ZERO, Vector3(-90, 0, 0))
	PropModels.rod(s, Vector3(0, -0.3, -1.5), Vector3(0, 0.25, -1.85), 0.12, 0.02, 4, SHARK)
	PropModels.rod(s, Vector3(0, -0.3, -1.5), Vector3(0, -0.72, -1.72), 0.1, 0.02, 4, SHARK)
	# dorsal fin (the classic), pectorals
	PropModels.frus(s, Vector2(0.08, 0.6), Vector2(0.02, 0.08), 0.6, Vector3(0, 0.0, 0.05), SHARK.darkened(0.08), Vector2(0, -0.28))
	PropModels.rod(s, Vector3(0.28, -0.42, 0.45), Vector3(0.78, -0.6, 0.1), 0.1, 0.02, 4, SHARK)
	PropModels.rod(s, Vector3(-0.28, -0.42, 0.45), Vector3(-0.78, -0.6, 0.1), 0.1, 0.02, 4, SHARK)
	# gills
	for i in 3:
		PropModels.box(s, Vector3(0.02, 0.16, 0.03), Vector3(0.34, -0.3, 0.7 - 0.08 * float(i)), SHARK.darkened(0.35))
		PropModels.box(s, Vector3(0.02, 0.16, 0.03), Vector3(-0.34, -0.3, 0.7 - 0.08 * float(i)), SHARK.darkened(0.35))


## An electric eel: a sinuous chain of segments with glowing yellow spots, head at +Z, its back at y = 0.
static func _eel(s: LowPoly.Soup, phase: float) -> void:
	var n := 9
	for i in n:
		var t := float(i) / float(n - 1)
		var p := Vector3(sin(t * 6.0 + phase) * 0.28, -0.08, 1.0 - t * 2.2)
		var r := lerpf(0.13, 0.04, t)
		PropModels.ball(s, Vector3(r, r * 0.85, 0.2), p, Color(0.22, 0.3, 0.2), 1, 0.05)
		if i % 2 == 1:
			PropModels.ball(s, Vector3(0.04, 0.03, 0.04), p + Vector3(0, r * 0.8, 0), g(Color(0.95, 1.0, 0.3)), 0, 0.0)
	# head and the glowing eyes
	PropModels.ball(s, Vector3(0.15, 0.12, 0.22), Vector3(0.0, -0.06, 1.18), Color(0.25, 0.34, 0.22), 1, 0.06)
	for sx: float in [-0.08, 0.08]:
		PropModels.ball(s, Vector3(0.035, 0.035, 0.035), Vector3(sx, 0.03, 1.28), g(Color(1.0, 0.95, 0.3)), 0, 0.0)
	# a little arc of spark between two spots (it is charged)
	PropModels.rod(s, Vector3(0.1, 0.06, 0.4), Vector3(0.22, 0.25, 0.15), 0.025, 0.01, 3, g(Color(0.7, 0.95, 1.0)))
	PropModels.rod(s, Vector3(0.22, 0.25, 0.15), Vector3(0.08, 0.1, -0.1), 0.025, 0.01, 3, g(Color(0.7, 0.95, 1.0)))


## A glowing jellyfish, dome on top at y = 0.
static func _jellyfish(s: LowPoly.Soup) -> void:
	var c := Color(0.85, 0.4, 1.0)
	PropModels.ball(s, Vector3(0.42, 0.28, 0.42), Vector3(0, -0.05, 0), g(c), 1, 0.06)
	PropModels.cyl(s, 0.44, 0.4, 0.06, 10, Vector3(0, -0.2, 0), g(c.lightened(0.3)))
	for i in 6:
		var a := TAU * float(i) / 6.0
		var p := Vector3(cos(a) * 0.25, -0.22, sin(a) * 0.25)
		PropModels.rod(s, p, p + Vector3(cos(a + 0.8) * 0.15, -0.65, sin(a + 0.8) * 0.15), 0.035, 0.01, 3, g(c.darkened(0.15)))


## The escaped specimen: a purple many-eyed blob with tentacles (the infestation colour), base at y = 0.
static func _specimen(s: LowPoly.Soup) -> void:
	var purple := Color(0.5, 0.18, 0.66)
	PropModels.ball(s, Vector3(0.75, 0.55, 0.7), Vector3(0, 0.5, 0), purple, 1, 0.14)
	PropModels.ball(s, Vector3(0.45, 0.3, 0.42), Vector3(0.1, 0.95, 0.1), purple.lightened(0.1), 1, 0.12)
	var eyes: Array[Vector3] = [Vector3(-0.25, 0.75, 0.55), Vector3(0.18, 0.86, 0.5), Vector3(0.42, 0.6, 0.45), Vector3(0.0, 1.12, 0.35)]
	for e in eyes:
		PropModels.ball(s, Vector3(0.1, 0.1, 0.1), e, Color(0.98, 0.95, 0.85), 0, 0.0)
		PropModels.ball(s, Vector3(0.045, 0.045, 0.045), e + Vector3(0, 0, 0.08), g(Color(1.0, 0.9, 0.2)), 0, 0.0)
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.3
		var p := Vector3(cos(a) * 0.55, 0.25, sin(a) * 0.55)
		var q := p + Vector3(cos(a) * 0.55, 0.3 + 0.2 * float(i % 2), sin(a) * 0.55)
		PropModels.rod(s, p, q, 0.13, 0.04, 5, purple.darkened(0.1))
		PropModels.ball(s, Vector3(0.05, 0.05, 0.05), q, g(Color(0.95, 0.4, 1.0)), 0, 0.0)


# --- pool furniture ---------------------------------------------------------------------------------------------

## A pool ladder hanging into the water: its top (the grab rails) at y = 0 on the coping, the rungs going down `depth`
## on the pool side (+Z), the rails curving back over the deck (-Z).
static func _ladder(s: LowPoly.Soup, depth: float) -> void:
	var steel := Color(0.85, 0.88, 0.92)
	for sx: float in [-0.3, 0.3]:
		PropModels.rod(s, Vector3(sx, -depth, 0.16), Vector3(sx, 0.05, 0.16), 0.035, 0.035, 6, steel)
		PropModels.rod(s, Vector3(sx, 0.05, 0.16), Vector3(sx, 0.75, 0.05), 0.035, 0.035, 6, steel)
		PropModels.rod(s, Vector3(sx, 0.75, 0.05), Vector3(sx, 0.8, -0.3), 0.035, 0.035, 6, steel)
		PropModels.rod(s, Vector3(sx, 0.8, -0.3), Vector3(sx, 0.02, -0.42), 0.035, 0.035, 6, steel)
		PropModels.cyl(s, 0.07, 0.07, 0.04, 6, Vector3(sx, 0.02, -0.42), steel.darkened(0.3))
	var n := maxi(2, int(depth / 0.32))
	for i in n:
		var y := -depth + 0.25 + float(i) * (depth - 0.2) / float(n)
		PropModels.box(s, Vector3(0.6, 0.05, 0.12), Vector3(0, y, 0.2), steel.darkened(0.1))


## Hand rails down a flight of inset steps: `length` along +Z, falling `drop`.
static func _stair_rail(s: LowPoly.Soup, length: float, drop: float) -> void:
	var steel := Color(0.85, 0.88, 0.92)
	PropModels.rod(s, Vector3(0, 0.0, -0.25), Vector3(0, 0.85, -0.1), 0.035, 0.035, 6, steel)
	PropModels.rod(s, Vector3(0, 0.85, -0.1), Vector3(0, 0.85 - drop, length), 0.035, 0.035, 6, steel)
	PropModels.rod(s, Vector3(0, 0.85 - drop, length), Vector3(0, -drop, length + 0.1), 0.035, 0.035, 6, steel)


## A steel-grate catwalk deck along +Z (centred), its walking surface at y = 0, with posts going down 3.0 and
## railings on the chosen sides.
static func _catwalk(s: LowPoly.Soup, length: float, rail_l: bool, rail_r: bool) -> void:
	var w := 1.3
	PropModels.box(s, Vector3(w, 0.08, length), Vector3(0, -0.04, 0), STEEL_DK)
	# the grating: cross bars on top
	var n := int(length / 0.22)
	for i in n:
		var z := -length * 0.5 + (float(i) + 0.5) * length / float(n)
		PropModels.box(s, Vector3(w - 0.06, 0.03, 0.05), Vector3(0, 0.01, z), STEEL)
	# yellow edge stripes
	for sx: float in [-w * 0.5, w * 0.5]:
		PropModels.box(s, Vector3(0.07, 0.11, length), Vector3(sx, -0.02, 0), HAZARD)
	var sides: Array[float] = []
	if rail_l:
		sides.append(-w * 0.5 + 0.04)
	if rail_r:
		sides.append(w * 0.5 - 0.04)
	var posts := maxi(2, int(length / 1.5) + 1)
	for sx in sides:
		for i in posts:
			var z := -length * 0.5 + 0.1 + float(i) * (length - 0.2) / float(posts - 1)
			PropModels.box(s, Vector3(0.06, 1.0, 0.06), Vector3(sx, 0.5, z), HAZARD)
		PropModels.box(s, Vector3(0.07, 0.07, length), Vector3(sx, 1.0, 0), HAZARD)
		PropModels.box(s, Vector3(0.05, 0.05, length), Vector3(sx, 0.55, 0), STEEL)


## A lab gantry over a pool: two A-frame legs `span` apart along X, a beam at `height`, a trolley with a chain and a
## hanging specimen cage dipped toward the water.
static func _gantry(s: LowPoly.Soup, span: float, height: float) -> void:
	for sx: float in [-span * 0.5, span * 0.5]:
		PropModels.rod(s, Vector3(sx, 0, -0.7), Vector3(sx, height, 0), 0.09, 0.07, 5, HAZARD)
		PropModels.rod(s, Vector3(sx, 0, 0.7), Vector3(sx, height, 0), 0.09, 0.07, 5, HAZARD)
		PropModels.box(s, Vector3(0.3, 0.12, 1.7), Vector3(sx, 0.06, 0), STEEL_DK)
		PropModels.rod(s, Vector3(sx, 1.1, -0.45), Vector3(sx, 1.1, 0.45), 0.05, 0.05, 5, STEEL)
	PropModels.box(s, Vector3(span + 0.5, 0.26, 0.3), Vector3(0, height + 0.05, 0), HAZARD)
	for i in int(span / 0.5):
		var x := -span * 0.5 + 0.25 + float(i) * 0.5
		PropModels.box(s, Vector3(0.22, 0.03, 0.32), Vector3(x, height + 0.05, 0), Color(0.12, 0.12, 0.14), Vector3(0, 0, 45))
	# trolley, chain, hook and the cage
	PropModels.box(s, Vector3(0.5, 0.3, 0.45), Vector3(0.6, height - 0.2, 0), STEEL_DK)
	PropModels.box(s, Vector3(0.12, 0.06, 0.02), Vector3(0.6, height - 0.2, 0.23), g(Color(1.0, 0.3, 0.2)))
	var cage_top := 1.15
	for i in 8:
		var y := height - 0.4 - float(i) * (height - 0.4 - cage_top) / 8.0
		PropModels.box(s, Vector3(0.06, 0.16, 0.1), Vector3(0.6, y, 0), STEEL, Vector3(0, 90 * float(i % 2), 0))
	PropModels.cyl(s, 0.48, 0.48, 0.08, 8, Vector3(0.6, cage_top, 0), STEEL_DK)
	PropModels.cyl(s, 0.48, 0.48, 0.08, 8, Vector3(0.6, cage_top - 1.1, 0), STEEL_DK)
	for i in 8:
		var a := TAU * float(i) / 8.0
		PropModels.box(s, Vector3(0.045, 1.1, 0.045), Vector3(0.6 + cos(a) * 0.45, cage_top - 0.55, sin(a) * 0.45), STEEL)
	# something in the cage, dripping
	PropModels.ball(s, Vector3(0.3, 0.32, 0.28), Vector3(0.6, cage_top - 0.6, 0), Color(0.5, 0.18, 0.66), 1, 0.15)
	PropModels.ball(s, Vector3(0.05, 0.05, 0.05), Vector3(0.52, cage_top - 0.5, 0.26), g(Color(1.0, 0.9, 0.2)), 0, 0.0)
	PropModels.ball(s, Vector3(0.05, 0.05, 0.05), Vector3(0.68, cage_top - 0.5, 0.26), g(Color(1.0, 0.9, 0.2)), 0, 0.0)


## A flat glowing ripple ring on a water surface (y = 0).
static func _ripple(s: LowPoly.Soup, radius: float) -> void:
	var n := 18
	for ring in 2:
		var r0 := radius * (0.82 + 0.45 * float(ring))
		var r1 := r0 + 0.07
		for i in n:
			if ring == 1 and i % 3 == 0:
				continue
			var a0 := TAU * float(i) / float(n)
			var a1 := TAU * float(i + 1) / float(n)
			var p00 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, 0.0, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, 0.0, sin(a1) * r1)
			var col := g(FOAM if ring == 0 else FOAM.darkened(0.25))
			s.add_quad(p00, p10, p11, p01, col)
			s.add_quad(p01, p11, p10, p00, col)


## A puff of steam (a fire just went out in the water), base at y = 0.
static func _steam(s: LowPoly.Soup) -> void:
	var puffs: Array[Vector4] = [Vector4(0, 0.3, 0, 0.35), Vector4(0.25, 0.6, 0.1, 0.3), Vector4(-0.2, 0.8, -0.1, 0.32),
			Vector4(0.05, 1.15, 0.05, 0.38), Vector4(0.3, 1.45, -0.15, 0.26), Vector4(-0.25, 1.6, 0.15, 0.22)]
	for p in puffs:
		PropModels.ball(s, Vector3(p.w, p.w * 0.85, p.w), Vector3(p.x, p.y, p.z), Color(0.93, 0.95, 0.97), 1, 0.12)


## Licking flames around a body of the given height (stand-in for Burning's flames, which need an Actor).
static func _flames(s: LowPoly.Soup, h: float, radius: float) -> void:
	var outer := Color(1.0, 0.42, 0.06)
	var inner := Color(1.0, 0.86, 0.25)
	for i in 10:
		var a := TAU * float(i) / 10.0 + 0.4
		var y := h * (0.2 + 0.6 * float((i * 7) % 10) / 10.0)
		var p := Vector3(cos(a) * radius, y, sin(a) * radius)
		var tall := 0.55 + 0.2 * float(i % 3)
		PropModels.frus(s, Vector2(0.3, 0.3), Vector2(0.0, 0.0), tall, p + Vector3(0, tall * 0.5, 0), g(outer))
		PropModels.frus(s, Vector2(0.12, 0.12), Vector2(0.0, 0.0), tall * 0.6, p + Vector3(cos(a) * 0.05, tall * 0.32, sin(a) * 0.05), g(inner))
		PropModels.ball(s, Vector3(0.17, 0.14, 0.17), p + Vector3(0, 0.04, 0), g(outer.lerp(inner, 0.4)), 1, 0.05)


static func _lifebuoy(s: LowPoly.Soup) -> void:
	var n := 12
	for i in n:
		var a := TAU * (float(i) + 0.5) / float(n)
		var col := Color(0.95, 0.25, 0.18) if (i / 3) % 2 == 0 else Color(0.97, 0.96, 0.94)
		PropModels.box(s, Vector3(0.2, 0.15, 0.13), Vector3(cos(a) * 0.36, 0.0, sin(a) * 0.36), col, Vector3(0, -rad_to_deg(a), 0))


## A square steel drain grate (flat, on the pool floor).
static func _drain(s: LowPoly.Soup) -> void:
	PropModels.box(s, Vector3(0.6, 0.03, 0.6), Vector3(0, 0.015, 0), STEEL_DK)
	for i in 5:
		PropModels.box(s, Vector3(0.06, 0.04, 0.5), Vector3(-0.2 + 0.1 * float(i), 0.03, 0), STEEL)


## A wall-mounted warning sign on a post: a yellow plate with a black fin and wave pictogram.
static func _hazard_sign(s: LowPoly.Soup, col: Color) -> void:
	PropModels.box(s, Vector3(0.08, 1.2, 0.08), Vector3(0, 0.6, 0), STEEL_DK)
	PropModels.box(s, Vector3(0.9, 0.7, 0.05), Vector3(0, 1.45, 0.06), col)
	PropModels.box(s, Vector3(0.82, 0.62, 0.02), Vector3(0, 1.45, 0.09), Color(0.08, 0.08, 0.1))
	PropModels.box(s, Vector3(0.74, 0.54, 0.02), Vector3(0, 1.45, 0.1), col)
	# the fin over a wave
	PropModels.frus(s, Vector2(0.05, 0.3), Vector2(0.02, 0.04), 0.28, Vector3(0, 1.5, 0.12), Color(0.08, 0.08, 0.1), Vector2(0, -0.1), Vector3(-90, 0, 0))
	for i in 3:
		PropModels.box(s, Vector3(0.2, 0.04, 0.02), Vector3(-0.22 + 0.22 * float(i), 1.32 + 0.03 * float(i % 2), 0.12), Color(0.08, 0.08, 0.1), Vector3(0, 0, 15 if i % 2 == 0 else -15))


static func _valve(s: LowPoly.Soup) -> void:
	PropModels.cyl(s, 0.08, 0.08, 0.5, 6, Vector3(0, 0.25, 0), STEEL_DK)
	var n := 8
	for i in n:
		var a := TAU * float(i) / float(n)
		PropModels.box(s, Vector3(0.18, 0.05, 0.05), Vector3(cos(a) * 0.25, 0.55, sin(a) * 0.25), Color(0.8, 0.15, 0.12), Vector3(0, -rad_to_deg(a) + 90, 0))
	for i in 4:
		var a := TAU * float(i) / 4.0
		PropModels.box(s, Vector3(0.5, 0.04, 0.04), Vector3(0, 0.55, 0), Color(0.8, 0.15, 0.12), Vector3(0, rad_to_deg(a) * 0.5, 0))


## A run of fat pipes along +X at the foot of a wall, with flanges and a glowing gauge.
static func _pipe_run(s: LowPoly.Soup, length: float) -> void:
	for k in 2:
		var y := 0.35 + 0.42 * float(k)
		PropModels.rod(s, Vector3(-length * 0.5, y, 0), Vector3(length * 0.5, y, 0), 0.14, 0.14, 7, STEEL if k == 0 else Color(0.3, 0.5, 0.35))
		for i in int(length / 1.2) + 1:
			var x := -length * 0.5 + 0.2 + float(i) * 1.2
			PropModels.cyl(s, 0.19, 0.19, 0.08, 7, Vector3(x, y, 0), STEEL_DK, Vector3(0, 0, 90))
	PropModels.cyl(s, 0.14, 0.14, 0.06, 8, Vector3(0.3, 0.77, 0.16), Color(0.9, 0.9, 0.85), Vector3(90, 0, 0))
	PropModels.box(s, Vector3(0.02, 0.1, 0.02), Vector3(0.32, 0.8, 0.2), g(Color(1.0, 0.25, 0.15)), Vector3(0, 0, -35))


## A steel lab bench with glowing flasks and a monitor.
static func _lab_bench(s: LowPoly.Soup) -> void:
	PropModels.box(s, Vector3(1.8, 0.08, 0.75), Vector3(0, 0.9, 0), Color(0.75, 0.78, 0.8))
	for sx: float in [-0.82, 0.82]:
		for sz: float in [-0.3, 0.3]:
			PropModels.box(s, Vector3(0.06, 0.9, 0.06), Vector3(sx, 0.45, sz), STEEL_DK)
	PropModels.box(s, Vector3(1.7, 0.05, 0.65), Vector3(0, 0.25, 0), STEEL_DK)
	var flasks: Array[Color] = [TOXIC, Color(0.3, 0.8, 1.0), Color(0.95, 0.4, 1.0)]
	for i in 3:
		var x := -0.6 + 0.3 * float(i)
		PropModels.cyl(s, 0.12, 0.05, 0.22, 6, Vector3(x, 1.05, 0.1), g(flasks[i]))
		PropModels.cyl(s, 0.04, 0.04, 0.12, 5, Vector3(x, 1.22, 0.1), Color(0.85, 0.9, 0.95))
	PropModels.box(s, Vector3(0.6, 0.42, 0.06), Vector3(0.45, 1.2, -0.2), STEEL_DK)
	PropModels.box(s, Vector3(0.52, 0.34, 0.02), Vector3(0.45, 1.2, -0.16), g(Color(0.35, 1.0, 0.5)))
	for i in 3:
		PropModels.box(s, Vector3(0.36, 0.025, 0.01), Vector3(0.42, 1.28 - 0.08 * float(i), -0.145), Color(0.05, 0.2, 0.08))
