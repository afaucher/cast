extends RefCounted
## Sewer models (docs/design/sewer-concept.md): look-dev for the sewer labs (scenes/sewer_lab.tscn, sewer2_lab.tscn), and
## since the sewer slice (phase 1, "Phase 1 as built") partly the game's: the gator (Gator, scripts/monsters/gator.gd), the
## sump pump and the electrical panel (PropModels), and the decor kit outfall, pipe_bundle, grate, sluice, bars and tool_cart
## (DecorModels) are built from here and checked by the z-fight registry (ZFightModels); the rest stays lab-only. Same kit as PoolProps (LowPoly soup, MonsterMaterial: ink outline, amber rim,
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
## Round 2 (staging, docs/design/sewer-concept.md "Sewer round 2"): pump (col: a sump pump on a skid, a priced prop to
##        be), junction_box (drop: where the live cable's end hangs, relative; dropped: the cable lies in the water), gas
##        (radius, seed: a sewer-gas pocket's bubbles and haze on the water), tool_cart, shock (points: a world-space-free
##        list of Vector3 the arc runs through, local), steam_wall (length: a vented steam wall along +X), corn_float (count,
##        radius: corn kernels floating on the water, y = 0 the surface).

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
		"pump": _pump(s, params.get("col", Color(0.22, 0.4, 0.55)))
		"junction_box": _junction_box(s, params.get("drop", Vector3(0, -1.2, 1.4)), bool(params.get("dropped", false)))
		"gas": _gas(s, float(params.get("radius", 0.9)), int(params.get("seed", 5)))
		"tool_cart": _tool_cart(s)
		"shock": _shock(s, params.get("points", []), int(params.get("seed", 3)))
		"steam_wall": _steam_wall(s, float(params.get("length", 4.0)), int(params.get("seed", 2)))
		"corn_float": _corn_float(s, int(params.get("count", 14)), float(params.get("radius", 1.0)), int(params.get("seed", 9)))
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
		PropModels.box(s, Vector3(0.05, 0.06, 0.24), Vector3(x, 0.55, 0.12), IRON)   # (narrower than the upright: no shared side)
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
		# (the two cross pieces fit between the long ones and stand a hair lower: no shared faces at the corners)
		var long := side % 2 == 0
		PropModels.box(s, Vector3(size if long else size - 0.2, 0.05 if long else 0.046, 0.1), b * Vector3(0, 0.025 if long else 0.023, h - 0.05), IRON, rot)
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


# --- round 2: staging ------------------------------------------------------------------------------------------

## A sump pump on a steel skid (the wall behind it, -Z): a squat motor drum with cooling fins, a pump volute, a riser pipe
## up the wall and a discharge elbow, a pressure gauge and a hazard-striped guard. Footprint about 1.1 x 0.8.
static func _pump(s: LowPoly.Soup, col: Color) -> void:
	PropModels.box(s, Vector3(1.2, 0.12, 0.85), Vector3(0, 0.06, 0.05), IRON)
	PropModels.cyl(s, 0.3, 0.3, 0.62, 10, Vector3(-0.22, 0.45, 0.1), col, Vector3(0, 0, 90))
	for i in 5:
		PropModels.cyl(s, 0.34, 0.34, 0.035, 10, Vector3(-0.44 + float(i) * 0.1, 0.45, 0.1), col.darkened(0.3), Vector3(0, 0, 90))
	PropModels.cyl(s, 0.26, 0.26, 0.3, 10, Vector3(0.28, 0.4, 0.1), STEEL.darkened(0.1), Vector3(90, 0, 0))
	PropModels.rod(s, Vector3(0.28, 0.4, -0.05), Vector3(0.28, 0.4, -0.3), 0.12, 0.12, 8, STEEL.darkened(0.25))
	PropModels.rod(s, Vector3(0.28, 0.55, 0.1), Vector3(0.28, 1.6, 0.1), 0.1, 0.1, 8, RUST)
	PropModels.rod(s, Vector3(0.28, 1.6, 0.1), Vector3(0.28, 1.6, -0.3), 0.1, 0.1, 8, RUST)
	PropModels.cyl(s, 0.14, 0.14, 0.06, 8, Vector3(0.28, 1.0, 0.1), RUST_DK)
	PropModels.cyl(s, 0.09, 0.09, 0.04, 10, Vector3(0.0, 0.85, 0.32), Color(0.9, 0.9, 0.85), Vector3(90, 0, 0))
	PropModels.box(s, Vector3(0.012, 0.07, 0.01), Vector3(0.02, 0.87, 0.35), Color(0.8, 0.1, 0.1), Vector3(0, 0, -40))
	PropModels.box(s, Vector3(1.0, 0.06, 0.04), Vector3(0, 0.22, 0.47), HAZARD)
	PropModels.box(s, Vector3(0.06, 0.12, 0.06), Vector3(-0.44, 0.92, 0.1), g(Color(0.3, 1.0, 0.3)))


## A grey electrical junction box on a wall (the wall behind, -Z, its bottom 1.0 up) and the live cable torn out of it,
## sagging to `drop` (relative to the box's base) where its bare end spits sparks. `dropped`: the end lies in the water.
static func _junction_box(s: LowPoly.Soup, drop: Vector3, dropped: bool) -> void:
	var grey := Color(0.55, 0.57, 0.55)
	PropModels.box(s, Vector3(0.6, 0.75, 0.22), Vector3(0, 1.4, 0.11), grey)
	PropModels.box(s, Vector3(0.52, 0.66, 0.03), Vector3(0, 1.4, 0.235), grey.lightened(0.1))
	PropModels.box(s, Vector3(0.22, 0.2, 0.02), Vector3(0, 1.5, 0.255), HAZARD)
	PropModels.box(s, Vector3(0.1, 0.1, 0.02), Vector3(0, 1.5, 0.265), Color(0.06, 0.06, 0.06), Vector3(0, 0, 45))
	PropModels.box(s, Vector3(0.05, 0.05, 0.04), Vector3(0.18, 1.68, 0.25), g(Color(1.0, 0.25, 0.1)))
	var a := Vector3(0.0, 1.05, 0.2)
	var end := drop + Vector3(0, 1.0, 0)
	var n := 8
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var p := a.lerp(end, t)
		p.y -= sin(t * PI) * (0.15 if dropped else 0.35)
		PropModels.rod(s, prev, p, 0.035, 0.035, 5, Color(0.06, 0.06, 0.07))
		prev = p
	PropModels.rod(s, end, end + Vector3(0, -0.12, 0.04), 0.02, 0.01, 4, Color(0.85, 0.5, 0.2))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in (14 if not dropped else 6):
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var r0 := end + Vector3(0, -0.12, 0)
		var r1 := r0 + d * rng.randf_range(0.12, 0.35)
		PropModels.rod(s, r0, r1, 0.018, 0.004, 3, g(Color(1.0, 0.95, 0.55)))
	PropModels.ball(s, Vector3(0.07, 0.07, 0.07), end + Vector3(0, -0.12, 0), g(Color(1.0, 1.0, 0.8)), 0, 0.0)


## A sewer-gas pocket on the water (y = 0 the surface): domes of bubbles breaking the surface over a sickly yellow-green
## haze disc. Seeded for the look.
static func _gas(s: LowPoly.Soup, radius: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in 18:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var k := rng.randf_range(0.04, 0.1)
		var col := Color(0.78, 0.82, 0.45) if i % 3 else g(Color(0.7, 0.8, 0.3))
		PropModels.ball(s, Vector3(k, k * 0.7, k), Vector3(cos(a) * r, k * 0.2, sin(a) * r), col, 0, 0.0)
	# a thin ring of scummy froth where the gas breaks the surface
	for i in 10:
		var a := TAU * float(i) / 10.0
		PropModels.ball(s, Vector3(0.16, 0.03, 0.1), Vector3(cos(a) * radius * 0.85, 0.01, sin(a) * radius * 0.85), Color(0.62, 0.66, 0.36), 0, 0.02, Vector3(0, -rad_to_deg(a), 0))


## A maintenance tool cart: two shelves on casters, a toolbox, a coil of hose, a red wrench.
static func _tool_cart(s: LowPoly.Soup) -> void:
	var blue := Color(0.2, 0.32, 0.55)
	for y: float in [0.25, 0.7]:
		PropModels.box(s, Vector3(0.8, 0.05, 0.45), Vector3(0, y, 0), blue)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			PropModels.box(s, Vector3(0.04, 0.6, 0.04), Vector3(sx * 0.37, 0.45, sz * 0.2), IRON)
			PropModels.ball(s, Vector3(0.05, 0.05, 0.05), Vector3(sx * 0.35, 0.05, sz * 0.18), Color(0.08, 0.08, 0.08), 0, 0.0)
	PropModels.box(s, Vector3(0.42, 0.18, 0.24), Vector3(-0.12, 0.82, 0), Color(0.8, 0.15, 0.1))
	PropModels.cyl(s, 0.17, 0.17, 0.1, 10, Vector3(0.22, 0.33, 0), Color(0.15, 0.4, 0.2))
	PropModels.box(s, Vector3(0.3, 0.03, 0.06), Vector3(0.2, 0.74, 0.08), STEEL, Vector3(0, 30, 0))


## An electric arc through `points` (local), jagged, glowing white-yellow: the live wire's shock running along the water.
static func _shock(s: LowPoly.Soup, points: Array, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var n := maxi(2, int(a.distance_to(b) / 0.35))
		var prev := a
		for k in range(1, n + 1):
			var p := a.lerp(b, float(k) / float(n))
			if k < n:
				p += Vector3(rng.randf_range(-0.22, 0.22), rng.randf_range(0.0, 0.16), rng.randf_range(-0.22, 0.22))
			PropModels.rod(s, prev, p, 0.035, 0.035, 3, g(Color(1.0, 0.97, 0.6)))
			prev = p


## A vented steam wall along +X (`length`, about one hex wide), from the floor up to 1.8: stacked white puffs, densest
## near the vent at x = 0.
static func _steam_wall(s: LowPoly.Soup, length: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(length / 0.3)
	for i in n:
		var x := float(i) * 0.3 + rng.randf_range(-0.1, 0.1)
		for j in 3:
			var r := rng.randf_range(0.25, 0.45) * (1.0 - 0.3 * x / length)
			PropModels.ball(s, Vector3(r, r * 0.8, r), Vector3(x, 0.3 + float(j) * 0.5 + rng.randf_range(-0.1, 0.1), rng.randf_range(-0.25, 0.25)), Color(0.93, 0.95, 0.96).darkened(rng.randf_range(0.0, 0.12)), 1, 0.08)


## Corn kernels floating on the water (y = 0 the surface), spread in a disc, drifting into a streak downstream (+X).
static func _corn_float(s: LowPoly.Soup, count: int, radius: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var p := Vector3(cos(a) * r * 1.8 + 0.5 * radius, 0.02, sin(a) * r * 0.6)
		PropModels.ball(s, Vector3(0.07, 0.05, 0.08), p, g(Color(1.0, 0.82, 0.2)), 0, 0.03, Vector3(0, rng.randf() * 180.0, 0))
