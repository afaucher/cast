extends RefCounted
## Sewer models (docs/design/sewer-concept.md): LOOK-DEV FOR THE SEWER LAB ONLY (scenes/sewer_lab.tscn). Nothing in the
## game builds these: they are not in DecorModels / PropModels, no theme or site places them, so they stay out of the
## game's kits and the z-fight registry. Same kit as PoolProps (LowPoly soup, MonsterMaterial: ink outline, amber rim,
## vertex alpha 0.5 = an emissive face), origin at the base centre, FRONT = +Z. No class_name (the lab preloads it).
##
##   const SewerProps := preload("res://scripts/art/lowpoly/props/sewer_props.gd")
##   add_child(SewerProps.build("gator", {"bend": 40.0}))
##
## Kinds: gator (bend: degrees the spine curls left, jaw: 0..1 open), salamander (the lava lab: the gator's body, crusted black
##        with glowing cracks and a frill; bend, jaw, crack), rat, rat_swarm (count, radius, seed), outfall
##        (radius, drop: a pipe mouth in a wall pouring into the channel), pipe_bundle (length, col), grate (size),
##        grate_bridge (length, width), sluice (width, open), springer (height, col: a brick arch rib against a wall),
##        ladder_wall (height), duck (a floating rubber duck), bars (width, height: iron bars across a culvert).

const IRON := Color(0.2, 0.21, 0.22)
const RUST := Color(0.5, 0.27, 0.14)
const RUST_DK := Color(0.3, 0.17, 0.1)
const STEEL := Color(0.5, 0.53, 0.56)
const HAZARD := Color(0.98, 0.78, 0.12)
const BRICK := Color(0.5, 0.25, 0.17)
const GATOR := Color(0.27, 0.33, 0.2)        ## olive back
const GATOR_DK := Color(0.16, 0.2, 0.12)     ## scutes and the spine stripe
const GATOR_BELLY := Color(0.78, 0.74, 0.52)
const GATOR_EYE := Color(1.0, 0.72, 0.12)    ## amber (glows)
const TOOTH := Color(0.96, 0.94, 0.84)
const WATER := Color(0.55, 0.72, 0.5)        ## the outfall's stream (glows faintly)

const GATOR_LEN := 2.3                       ## snout tip to tail tip


static func g(c: Color) -> Color:
	return PropModels.glow(c)


static func build(kind: String, params: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var s := LowPoly.Soup.new(17, 0.06)
	var outline := 2.0
	match kind:
		"gator": _gator(s, float(params.get("bend", 0.0)), float(params.get("jaw", 0.0)))
		"salamander": _gator(s, float(params.get("bend", 0.0)), float(params.get("jaw", 0.0)), Color(0.13, 0.1, 0.1),
				Color(0.06, 0.05, 0.05), Color(0.55, 0.2, 0.08), Color(1.0, 0.85, 0.2), params.get("crack", Color(1.0, 0.42, 0.06)))
		"rat": _rat(s, Vector3.ZERO, 0.0, 1.0)
		"rat_swarm": _rat_swarm(s, int(params.get("count", 9)), float(params.get("radius", 0.8)), int(params.get("seed", 3)))
		"outfall": _outfall(s, float(params.get("radius", 0.42)), float(params.get("drop", 1.2)))
		"pipe_bundle": _pipe_bundle(s, float(params.get("length", 4.0)), params.get("col", RUST))
		"grate":
			_grate(s, float(params.get("size", 1.6)))
			outline = 0.0
		"grate_bridge": _grate_bridge(s, float(params.get("length", 3.6)), float(params.get("width", 1.3)))
		"sluice": _sluice(s, float(params.get("width", 3.0)), float(params.get("open", 0.6)))
		"springer": _springer(s, float(params.get("height", 1.5)), params.get("col", BRICK))
		"ladder_wall": _ladder_wall(s, float(params.get("height", 1.6)))
		"duck": _duck(s)
		"bars": _bars(s, float(params.get("width", 1.6)), float(params.get("height", 1.0)))
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


# --- the sewer gator --------------------------------------------------------------------------------------------

## A point on the gator's spine, t = 0 at the snout tip and 1 at the tail tip, the spine curled `bend` degrees to the
## left over its length (a circular arc; straight along -Z from the snout when bend is 0). Returns [pos, forward].
static func _spine(t: float, bend: float) -> Array:
	var length := GATOR_LEN
	var s := t * length
	var k := deg_to_rad(bend) / length          # curvature (rad per unit)
	if absf(k) < 0.0001:
		return [Vector3(0, 0, 1.0 - s), Vector3(0, 0, 1)]
	var r := 1.0 / k
	var a := s * k
	# start at (0, 0, 1) heading -Z (walking back from the snout), turning toward +X as it goes (the tail swings right,
	# so the head looks left of the body)
	var pos := Vector3(r * (1.0 - cos(a)), 0.0, 1.0 - r * sin(a))
	var back := Vector3(sin(a), 0.0, -cos(a))
	return [pos, -back]


## The gator: origin on its belly (y = 0 is the channel floor), snout toward +Z. Its back is about 0.38 up, the scutes
## and the eye bumps 0.44-0.5: in wading water (0.36 over the channel floor) only the eyes, the nostrils and the ridge of
## scutes break the surface, like a real one. Long flat snout, a jaw of teeth, splayed legs, a long ridged tail.
static func _gator(s: LowPoly.Soup, bend: float, jaw: float, skin: Color = GATOR, dark: Color = GATOR_DK, belly: Color = GATOR_BELLY, eye: Color = GATOR_EYE, crack: Color = Color(0, 0, 0, 0)) -> void:
	# body: overlapping flat ellipsoids along the spine, widest at the shoulders, tapering down the tail
	var stations: Array[Vector4] = [   # t, half width, half height, centre height
		Vector4(0.03, 0.09, 0.06, 0.14), Vector4(0.09, 0.12, 0.07, 0.15), Vector4(0.16, 0.16, 0.1, 0.18),
		Vector4(0.24, 0.22, 0.13, 0.2), Vector4(0.32, 0.29, 0.16, 0.21), Vector4(0.41, 0.32, 0.17, 0.21),
		Vector4(0.5, 0.29, 0.16, 0.2), Vector4(0.58, 0.22, 0.13, 0.18), Vector4(0.66, 0.16, 0.11, 0.17),
		Vector4(0.74, 0.12, 0.09, 0.16), Vector4(0.82, 0.09, 0.08, 0.15), Vector4(0.9, 0.06, 0.07, 0.14),
		Vector4(0.97, 0.035, 0.05, 0.13),
	]
	for st in stations:
		var sp: Array = _spine(st.x, bend)
		var p: Vector3 = sp[0]
		var f: Vector3 = sp[1]
		var yaw := rad_to_deg(atan2(f.x, f.z))
		var col := skin if st.x > 0.12 else skin.lightened(0.05)
		PropModels.ball(s, Vector3(st.y, st.z, 0.2), p + Vector3(0, st.w, 0), col, 1, 0.04, Vector3(0, yaw, 0))
		# pale belly band under the body
		if st.x > 0.2 and st.x < 0.62:
			PropModels.ball(s, Vector3(st.y * 0.85, st.z * 0.5, 0.18), p + Vector3(0, st.w - st.z * 0.55, 0), belly, 1, 0.03, Vector3(0, yaw, 0))
	# scutes: two rows down the back, one row down the tail (dark ridges that break the surface)
	for i in 22:
		var t := 0.22 + float(i) * 0.034
		var sp: Array = _spine(t, bend)
		var p: Vector3 = sp[0]
		var f: Vector3 = sp[1]
		var side := Vector3(f.z, 0, -f.x)
		var yaw := rad_to_deg(atan2(f.x, f.z))
		var hw := 0.1 if t < 0.6 else 0.0
		var top := 0.36 if t < 0.6 else 0.3 - (t - 0.6) * 0.25
		var h := 0.09 if t < 0.6 else 0.11
		for sx: float in ([-1.0, 1.0] if hw > 0.0 else [0.0]):
			PropModels.frus(s, Vector2(0.07, 0.06), Vector2(0.015, 0.03), h, p + side * hw * sx + Vector3(0, top, 0), dark, Vector2.ZERO, Vector3(0, yaw, 0))
	# the head: a flat wedge snout on a broad skull, the eye bumps standing up
	var hp: Array = _spine(0.13, bend)
	var hpos: Vector3 = hp[0]
	var hf: Vector3 = hp[1]
	var hyaw := rad_to_deg(atan2(hf.x, hf.z))
	var hside := Vector3(hf.z, 0, -hf.x)
	PropModels.box(s, Vector3(0.24, 0.07, 0.42), hpos + hf * 0.12 + Vector3(0, 0.2, 0), skin.lightened(0.04), Vector3(-4, hyaw, 0))
	# lower jaw, dropped open by `jaw`
	var jaw_tilt := 6.0 + 26.0 * jaw
	PropModels.box(s, Vector3(0.2, 0.05, 0.4), hpos + hf * 0.12 + Vector3(0, 0.1 - 0.05 * jaw, 0), belly.darkened(0.15), Vector3(jaw_tilt, hyaw, 0))
	if jaw > 0.05:
		PropModels.box(s, Vector3(0.17, 0.02, 0.34), hpos + hf * 0.1 + Vector3(0, 0.14 - 0.02 * jaw, 0), Color(0.6, 0.16, 0.16), Vector3(jaw_tilt * 0.5, hyaw, 0))
	# teeth along both sides of the upper jaw
	for i in 6:
		var along := -0.06 + float(i) * 0.065
		for sx: float in [-1.0, 1.0]:
			var tp := hpos + hf * along + hside * sx * 0.11 + Vector3(0, 0.15, 0)
			PropModels.frus(s, Vector2(0.025, 0.025), Vector2(0.0, 0.0), 0.05, tp, TOOTH, Vector2.ZERO, Vector3(180, hyaw, 0))
	# nostrils at the snout tip, eye bumps with glowing slits behind the snout
	for sx: float in [-1.0, 1.0]:
		PropModels.ball(s, Vector3(0.03, 0.025, 0.03), hpos + hf * 0.3 + hside * sx * 0.04 + Vector3(0, 0.25, 0), dark, 0, 0.0)
		var ep := hpos - hf * 0.08 + hside * sx * 0.09 + Vector3(0, 0.3, 0)
		PropModels.ball(s, Vector3(0.07, 0.06, 0.08), ep, skin, 1, 0.03)
		PropModels.box(s, Vector3(0.05, 0.03, 0.02), ep + Vector3(0, 0.04, 0) + hf * 0.05, g(eye), Vector3(0, hyaw, 0))
	# four splayed legs: elbows out, feet flat on the floor
	for leg in [[0.3, 1.0], [0.3, -1.0], [0.55, 1.0], [0.55, -1.0]]:
		var lp: Array = _spine(float(leg[0]), bend)
		var lpos: Vector3 = lp[0]
		var lf: Vector3 = lp[1]
		var lside := Vector3(lf.z, 0, -lf.x) * float(leg[1])
		var hip := lpos + lside * 0.22 + Vector3(0, 0.16, 0)
		var elbow := lpos + lside * 0.42 + Vector3(0, 0.13, 0) + lf * 0.04
		var foot := lpos + lside * 0.46 + Vector3(0, 0.02, 0) + lf * 0.1
		PropModels.rod(s, hip, elbow, 0.06, 0.05, 5, skin)
		PropModels.rod(s, elbow, foot, 0.05, 0.04, 5, skin)
		PropModels.box(s, Vector3(0.13, 0.03, 0.12), foot + Vector3(0, -0.005, 0), dark, Vector3(0, rad_to_deg(atan2(lf.x, lf.z)), 0))
	if crack.a <= 0.0:
		return
	# the lava salamander: glowing cracks between the back plates and a spiked frill behind the head
	for i in 16:
		var t := 0.2 + float(i) * 0.045
		var sp: Array = _spine(t, bend)
		var p: Vector3 = sp[0]
		var f: Vector3 = sp[1]
		var side := Vector3(f.z, 0, -f.x)
		var yaw := rad_to_deg(atan2(f.x, f.z))
		var w := 0.22 if t < 0.55 else 0.1
		var top := 0.37 if t < 0.55 else 0.3 - (t - 0.55) * 0.3
		PropModels.box(s, Vector3(0.025, 0.02, 0.07), p + side * w * 0.55 + Vector3(0, top - 0.04, 0), g(crack), Vector3(0, yaw + 20.0, 0))
		PropModels.box(s, Vector3(0.025, 0.02, 0.07), p - side * w * 0.55 + Vector3(0, top - 0.04, 0), g(crack), Vector3(0, yaw - 20.0, 0))
		if i % 2 == 0:
			PropModels.box(s, Vector3(0.05, 0.022, 0.05), p + Vector3(0, top + 0.02, 0), g(crack.lightened(0.3)), Vector3(0, yaw, 0))
	var fp: Array = _spine(0.2, bend)
	var fpos: Vector3 = fp[0]
	var ff: Vector3 = fp[1]
	var fside := Vector3(ff.z, 0, -ff.x)
	for i in 5:
		var a := (float(i) - 2.0) * 0.5
		var base := fpos + fside * a * 0.14 + Vector3(0, 0.32, 0)
		var tip := base + fside * a * 0.2 + Vector3(0, 0.26 - absf(a) * 0.08, 0) - ff * 0.12
		PropModels.rod(s, base, tip, 0.05, 0.01, 4, dark)
		PropModels.ball(s, Vector3(0.025, 0.025, 0.025), tip, g(crack), 0, 0.0)


# --- rats -------------------------------------------------------------------------------------------------------

## One rat at `at` facing yaw (degrees), scaled by k: a grey-brown teardrop with pink ears and tail, glowing red eyes.
static func _rat(s: LowPoly.Soup, at: Vector3, yaw: float, k: float) -> void:
	var fur := Color(0.36, 0.31, 0.28)
	var pink := Color(0.86, 0.55, 0.55)
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	PropModels.ball(s, Vector3(0.1, 0.08, 0.16) * k, at + b * (Vector3(0, 0.08, 0) * k), fur, 1, 0.04, Vector3(0, yaw, 0))
	PropModels.ball(s, Vector3(0.06, 0.055, 0.09) * k, at + b * (Vector3(0, 0.09, 0.16) * k), fur.lightened(0.05), 1, 0.03, Vector3(0, yaw, 0))
	for sx: float in [-1.0, 1.0]:
		PropModels.ball(s, Vector3(0.035, 0.035, 0.012) * k, at + b * (Vector3(0.045 * sx, 0.15, 0.12) * k), pink, 0, 0.0, Vector3(0, yaw, 0))
		PropModels.ball(s, Vector3(0.014, 0.014, 0.014) * k, at + b * (Vector3(0.035 * sx, 0.115, 0.22) * k), g(Color(1.0, 0.2, 0.15)), 0, 0.0)
	PropModels.rod(s, at + b * (Vector3(0, 0.06, -0.14) * k), at + b * (Vector3(0.12, 0.02, -0.42) * k), 0.018 * k, 0.008 * k, 3, pink)


## A pack of rats milling about (the imp swarm's sewer cousin): `count` rats in a disc of `radius`, seeded.
static func _rat_swarm(s: LowPoly.Soup, count: int, radius: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var at := Vector3(cos(a) * r, 0.0, sin(a) * r)
		_rat(s, at, rng.randf_range(-40.0, 40.0) + 180.0 * float(i % 2), rng.randf_range(0.85, 1.15))


# --- sewer furniture --------------------------------------------------------------------------------------------

## A big round pipe mouth sticking out of a wall (the wall is behind it, -Z), its bore `drop` above the water, pouring a
## stream down into the channel (+Z): a pipe stub with a rusted flange and a falling ribbon of water that fans out.
static func _outfall(s: LowPoly.Soup, radius: float, drop: float) -> void:
	var y := drop + radius
	PropModels.cyl(s, radius, radius, 0.6, 10, Vector3(0, y, 0.0), Color(0.42, 0.4, 0.37), Vector3(90, 0, 0))
	PropModels.cyl(s, radius + 0.08, radius + 0.08, 0.1, 10, Vector3(0, y, 0.28), RUST, Vector3(90, 0, 0))
	PropModels.cyl(s, radius * 0.8, radius * 0.8, 0.04, 10, Vector3(0, y, 0.34), Color(0.05, 0.06, 0.05), Vector3(90, 0, 0))
	# the stream: a curved ribbon of slabs from the lip down to the surface, widening as it falls
	var n := 7
	for i in n:
		var t0 := float(i) / float(n)
		var t1 := float(i + 1) / float(n)
		var z0 := 0.32 + 0.45 * t0 * t0 + 0.12 * t0
		var z1 := 0.32 + 0.45 * t1 * t1 + 0.12 * t1
		var y0 := y - radius * 0.6 - drop * t0
		var y1 := y - radius * 0.6 - drop * t1
		var w := radius * (1.1 + 0.6 * t0)
		var mid := Vector3(0, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
		var seg_len := Vector2(z1 - z0, y1 - y0).length()
		var tilt := rad_to_deg(atan2(z1 - z0, y0 - y1))
		PropModels.box(s, Vector3(w * 2.0, seg_len + 0.04, 0.07), mid, g(WATER) if i % 2 == 0 else g(WATER.lightened(0.25)), Vector3(tilt, 0, 0))
	# the splash where it lands
	for i in 6:
		var a := TAU * float(i) / 6.0
		var p := Vector3(cos(a) * 0.32, 0.03, 0.32 + 0.45 + 0.12 + sin(a) * 0.32)
		PropModels.ball(s, Vector3(0.12, 0.08, 0.12), p, g(Color(0.85, 0.92, 0.8)), 0, 0.0)


## A run of rusty pipes along +X on wall brackets (the wall is behind, -Z), with flanges, a T going down and a leak.
static func _pipe_bundle(s: LowPoly.Soup, length: float, col: Color) -> void:
	var rows: Array[Vector2] = [Vector2(0.55, 0.13), Vector2(0.9, 0.09), Vector2(1.18, 0.07)]
	for k in rows.size():
		var y := rows[k].x
		var r := rows[k].y
		var c: Color = col if k != 1 else Color(0.33, 0.4, 0.3)
		PropModels.rod(s, Vector3(-length * 0.5, y, 0.18), Vector3(length * 0.5, y, 0.18), r, r, 7, c)
		for i in int(length / 1.4) + 1:
			var x := -length * 0.5 + 0.3 + float(i) * 1.4
			PropModels.cyl(s, r + 0.04, r + 0.04, 0.07, 7, Vector3(x, y, 0.18), c.darkened(0.3), Vector3(0, 0, 90))
	for i in int(length / 1.4) + 1:
		var x := -length * 0.5 + 0.7 + float(i) * 1.4
		PropModels.box(s, Vector3(0.06, 0.85, 0.06), Vector3(x, 0.8, 0.04), IRON)
		PropModels.box(s, Vector3(0.06, 0.06, 0.24), Vector3(x, 0.55, 0.12), IRON)
	# a T down to the floor with a valve wheel, at one end
	var tx := length * 0.5 - 0.5
	PropModels.rod(s, Vector3(tx, 0.55, 0.18), Vector3(tx, 0.05, 0.18), 0.1, 0.1, 7, col)
	for i in 6:
		var a := TAU * float(i) / 6.0
		PropModels.box(s, Vector3(0.16, 0.04, 0.04), Vector3(tx + cos(a) * 0.17, 0.3, 0.32 + sin(a) * 0.17), Color(0.75, 0.14, 0.1), Vector3(-rad_to_deg(a), 0, 90))
	PropModels.box(s, Vector3(0.05, 0.05, 0.16), Vector3(tx, 0.3, 0.26), IRON)


## A square floor grate: an iron frame and bars (flat; under the water it reads as the drain).
static func _grate(s: LowPoly.Soup, size: float) -> void:
	var h := size * 0.5
	for side in 4:
		var rot := Vector3(0, 90.0 * float(side), 0)
		var b := Basis.from_euler(rot * PI / 180.0)
		PropModels.box(s, Vector3(size, 0.05, 0.1), b * Vector3(0, 0.025, h - 0.05), IRON, rot)
	var n := int(size / 0.16)
	for i in n:
		var x := -h + 0.12 + float(i) * (size - 0.24) / float(n - 1)
		PropModels.box(s, Vector3(0.05, 0.05, size - 0.12), Vector3(x, 0.03, 0), IRON.lightened(0.1))
	PropModels.box(s, Vector3(size - 0.12, 0.05, 0.06), Vector3(0, 0.035, 0), IRON)


## A grated catwalk across a channel (along X, `length` long, `width` wide), its deck `0.0` at the ledge height, on two
## channel-floor legs per end, with a hazard-yellow handrail on both sides.
static func _grate_bridge(s: LowPoly.Soup, length: float, width: float) -> void:
	var hw := width * 0.5
	var hl := length * 0.5
	for sz: float in [-1.0, 1.0]:
		PropModels.box(s, Vector3(length, 0.08, 0.08), Vector3(0, -0.04, sz * (hw - 0.04)), IRON)
	var n := int(length / 0.14)
	for i in n:
		var x := -hl + 0.06 + float(i) * (length - 0.12) / float(n - 1)
		PropModels.box(s, Vector3(0.035, 0.05, width - 0.1), Vector3(x, -0.03, 0), IRON.lightened(0.15))
	for sx: float in [-1.0, 0.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx * (hl - 0.1), 0.0, sz * (hw - 0.05))
			PropModels.box(s, Vector3(0.05, 0.85, 0.05), p + Vector3(0, 0.42, 0), HAZARD)
			if sx != 0.0:
				PropModels.box(s, Vector3(0.07, 0.55, 0.07), p + Vector3(0, -0.3, 0), IRON)
	for sz: float in [-1.0, 1.0]:
		PropModels.box(s, Vector3(length - 0.1, 0.05, 0.05), Vector3(0, 0.84, sz * (hw - 0.05)), HAZARD)
		PropModels.box(s, Vector3(length - 0.1, 0.04, 0.04), Vector3(0, 0.45, sz * (hw - 0.05)), HAZARD.darkened(0.2))


## A sluice gate across a channel (along X, `width` wide): two steel guide posts in the walls' line, a lintel with a
## wheel, and the gate plate raised `open` (0 shut, 1 fully up) so the water runs under it.
static func _sluice(s: LowPoly.Soup, width: float, open: float) -> void:
	var hw := width * 0.5
	var top := 2.0
	for sx: float in [-1.0, 1.0]:
		PropModels.box(s, Vector3(0.16, top, 0.22), Vector3(sx * hw, top * 0.5 - 0.5, 0), STEEL.darkened(0.2))
		PropModels.box(s, Vector3(0.06, top, 0.06), Vector3(sx * (hw - 0.1), top * 0.5 - 0.5, 0), HAZARD)
	PropModels.box(s, Vector3(width + 0.3, 0.2, 0.3), Vector3(0, top - 0.5, 0), STEEL.darkened(0.15))
	# hazard chevrons on the lintel
	for i in int(width / 0.4):
		PropModels.box(s, Vector3(0.18, 0.12, 0.02), Vector3(-hw + 0.25 + float(i) * 0.4, top - 0.5, 0.16), HAZARD if i % 2 == 0 else Color(0.08, 0.08, 0.1))
	var plate_bottom := -0.5 + open * 0.9
	PropModels.box(s, Vector3(width - 0.2, 0.9, 0.08), Vector3(0, plate_bottom + 0.45, 0), RUST, Vector3.ZERO, 0.0)
	for i in 3:
		PropModels.box(s, Vector3(width - 0.2, 0.05, 0.1), Vector3(0, plate_bottom + 0.15 + 0.3 * float(i), 0.02), RUST_DK)
	# the screw and the wheel on top
	PropModels.rod(s, Vector3(0, plate_bottom + 0.9, 0), Vector3(0, top + 0.1, 0), 0.04, 0.04, 6, STEEL)
	for i in 8:
		var a := TAU * float(i) / 8.0
		PropModels.box(s, Vector3(0.2, 0.05, 0.05), Vector3(cos(a) * 0.28, top + 0.05, sin(a) * 0.28), Color(0.75, 0.14, 0.1), Vector3(0, -rad_to_deg(a) + 90.0, 0))
	PropModels.box(s, Vector3(0.6, 0.04, 0.04), Vector3(0, top + 0.05, 0), Color(0.75, 0.14, 0.1))
	PropModels.box(s, Vector3(0.04, 0.04, 0.6), Vector3(0, top + 0.05, 0), Color(0.75, 0.14, 0.1))


## A brick arch rib springing from a wall (the wall is behind it, -Z): a pier up the wall and the first course of the
## vault curling out over the channel, cut off (the camera sees no ceiling; the springers say "vaulted tunnel").
static func _springer(s: LowPoly.Soup, height: float, col: Color) -> void:
	PropModels.box(s, Vector3(0.5, height, 0.22), Vector3(0, height * 0.5, 0.11), col)
	PropModels.box(s, Vector3(0.56, 0.08, 0.28), Vector3(0, height, 0.14), col.lightened(0.12))
	var n := 4
	for i in n:
		var a0 := deg_to_rad(float(i) * 14.0)
		var r := 1.2
		var p := Vector3(0, height + sin(a0 + 0.12) * r * 0.42, 0.14 + (1.0 - cos(a0 + 0.12)) * r)
		PropModels.box(s, Vector3(0.5, 0.2, 0.3), p, col.darkened(0.05 * float(i % 2)), Vector3(-rad_to_deg(a0) - 8.0, 0, 0))


## Iron rungs up a wall (the wall behind, -Z) from the floor to `height`, then the rim of a manhole above.
static func _ladder_wall(s: LowPoly.Soup, height: float) -> void:
	var n := int(height / 0.3)
	for i in n:
		var y := 0.25 + float(i) * 0.3
		PropModels.box(s, Vector3(0.42, 0.04, 0.04), Vector3(0, y, 0.16), RUST)
		for sx: float in [-1.0, 1.0]:
			PropModels.box(s, Vector3(0.04, 0.04, 0.16), Vector3(sx * 0.21, y, 0.08), RUST_DK)


## A yellow rubber duck bobbing on the water (its waterline at y = 0).
static func _duck(s: LowPoly.Soup) -> void:
	var yellow := Color(1.0, 0.85, 0.12)
	PropModels.ball(s, Vector3(0.16, 0.11, 0.2), Vector3(0, 0.04, 0), yellow, 1, 0.02)
	PropModels.ball(s, Vector3(0.1, 0.1, 0.1), Vector3(0, 0.19, 0.1), yellow, 1, 0.02)
	PropModels.box(s, Vector3(0.07, 0.03, 0.08), Vector3(0, 0.18, 0.21), Color(1.0, 0.45, 0.1))
	for sx: float in [-1.0, 1.0]:
		PropModels.ball(s, Vector3(0.018, 0.018, 0.018), Vector3(sx * 0.055, 0.23, 0.17), Color(0.05, 0.05, 0.05), 0, 0.0)


## Iron bars across a culvert mouth (along X), rusted, one bent aside.
static func _bars(s: LowPoly.Soup, width: float, height: float) -> void:
	var n := int(width / 0.2)
	for i in n:
		var x := -width * 0.5 + 0.1 + float(i) * (width - 0.2) / float(n - 1)
		var lean := 0.18 if i == n / 2 else 0.0
		PropModels.rod(s, Vector3(x, 0.0, 0), Vector3(x + lean, height, lean * 0.6), 0.025, 0.025, 4, RUST if i % 3 else RUST_DK)
	PropModels.box(s, Vector3(width, 0.06, 0.06), Vector3(0, height, 0), IRON)
	PropModels.box(s, Vector3(width, 0.05, 0.05), Vector3(0, height * 0.45, 0), IRON)
