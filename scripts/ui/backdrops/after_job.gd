extends RefCounted
## The garage's "morning after a bad job" dressing (MenuBackdrop mood "after"). Presentation only: every piece is
## built once when the mood is applied, nothing allocates per frame, and the random numbers come from local seeded
## RNGs (never GameWorld.rng).
##
## It has to read as a disaster at a glance, and stay funny without explaining itself:
##   - CORN: a giant smug cob wedged in the van roof, whole cobs lying about (kernel-bumped, husked, one scorched),
##     one planted in the floor, kernels and popcorn in clumps, loose husk leaves. Never a word about corn but the sign.
##   - DAMAGE: big char-black scorch marks (brown halo) on the floor and up the back wall, a popped hood with a small fire
##     and a thick smoke column and a door hanging crooked, a failing work lamp.
##   - STORY: an invoice nailed to the wall stamped PAST DUE, the corn sign reading a big red 0, an extinguisher on its
##     side in a puddle of foam, the crew scuffed, sooty, patched and slumping.
##
## No class_name on purpose (like the backdrop kit): the backdrop preloads this file.

const Kit := preload("res://scripts/ui/backdrops/backdrop_kit.gd")

const KERNEL := Color(1.0, 0.80, 0.16)
const KERNEL_DEEP := Color(0.95, 0.64, 0.07)
const KERNEL_PALE := Color(1.0, 0.90, 0.42)
const POP := Color(1.0, 0.95, 0.80)
const CHAR := Color(0.05, 0.045, 0.045)
const SCORCH_RIM := Color(0.36, 0.20, 0.10)
const HUSK := Color(0.34, 0.62, 0.20)
const HUSK_DRY := Color(0.58, 0.50, 0.24)
const STEM := Color(0.46, 0.52, 0.20)
const SOOT_RED := Color(0.78, 0.07, 0.05)
const EMBER := Color(1.0, 0.38, 0.06)
const EXT_RED := Color(0.80, 0.10, 0.08)
const FOAM := Color(0.94, 0.96, 1.0)
const PLASTER := Color(0.95, 0.90, 0.76)


static func _xf(pos: Vector3, euler_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z)))
	return Transform3D(b * Basis.from_scale(scl), pos)


# --- Corn -------------------------------------------------------------------------------------------

## A corn cob standing along +Y with its TIP at the origin: a golden core under rows of kernel bumps, five husk leaves
## flaring out of the stem end, a stem nub. `burnt` (0..1) chars the tip kernels and dries the husk and pops a few
## kernels off. `eyes`: the corn bomb's smug cartoon face (the spell's giant cob has one), shocked at what it did.
static func cob(length: float, radius: float, seed_value: int, burnt: float = 0.0, eyes: bool = false) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(seed_value, 0.06)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var per := 9 if radius < 0.4 else 11
	var rows := maxi(5, int(length / (radius * 0.62)))
	var row_h := length / float(rows)
	s.merge(LowPoly.cylinder(radius * 0.42, radius * 0.8, length, 8, KERNEL_DEEP, seed_value + 1, 0.0, 1, 0.05), LowPoly.at(Vector3(0.0, length * 0.5, 0.0)))
	s.merge(LowPoly.boulder(Vector3(radius * 0.5, radius * 0.45, radius * 0.5), 0, 0.1, KERNEL_DEEP if burnt < 0.2 else CHAR, seed_value + 2, 0.05), LowPoly.at(Vector3(0.0, radius * 0.18, 0.0)))
	for i in rows:
		var t := (float(i) + 0.5) / float(rows)
		var y := t * length
		var rr := radius * (0.52 + 0.42 * t) * minf(1.0, 0.45 + 4.0 * t)
		var arc := TAU * rr / float(per)
		var stagger := 0.5 if i % 2 == 1 else 0.0
		for k in per:
			if burnt > 0.0 and rng.randf() < burnt * 0.06:
				continue     # popped clean off
			var a := (float(k) + stagger) / float(per) * TAU
			var roll := rng.randf()
			var col := KERNEL if roll < 0.5 else (KERNEL_DEEP if roll < 0.78 else KERNEL_PALE)
			if burnt > 0.0 and t < burnt * 0.6 + rng.randf() * 0.12:
				col = CHAR.lerp(Color(0.34, 0.18, 0.06), rng.randf())
			var rk := rr + radius * 0.04
			var pos := Vector3(cos(a) * rk, y, sin(a) * rk)
			s.merge(LowPoly.box(Vector3(arc * 0.9, row_h * 0.88, radius * 0.3), col, seed_value + 10 + i * 31 + k, 0.0, 1, 0.05),
					LowPoly.at(pos, Vector3(0.0, rad_to_deg(PI * 0.5 - a), 0.0)))
	var leaves := 5
	for j in leaves:
		var a2 := (float(j) + rng.randf_range(-0.2, 0.2)) / float(leaves) * TAU
		var d := Vector3(cos(a2), 0.0, sin(a2))
		var tg := Vector3(-sin(a2), 0.0, cos(a2))
		var phi := deg_to_rad(rng.randf_range(16.0, 40.0))
		var u := (d * sin(phi) - Vector3.UP * cos(phi)).normalized()
		var llen := length * rng.randf_range(0.42, 0.62)
		var base := Vector3(0.0, length * 0.97, 0.0) + d * (radius * 0.8)
		var lcol := HUSK if j % 2 == 0 else HUSK.darkened(0.12)
		lcol = lcol.lerp(HUSK_DRY, burnt * 0.8)
		var w := radius * rng.randf_range(0.9, 1.25)
		var lb := Basis(tg, u, tg.cross(u))
		s.merge(LowPoly.frustum(Vector2(w, radius * 0.07), Vector2(w * 0.22, radius * 0.04), llen, lcol, seed_value + 60 + j, 0.0, 1, Vector2.ZERO, 0.08),
				Transform3D(lb, base + u * llen * 0.5))
	s.merge(LowPoly.cylinder(radius * 0.22, radius * 0.3, radius * 0.7, 6, STEM, seed_value + 80, 0.0, 1, 0.05), LowPoly.at(Vector3(0.0, length + radius * 0.25, 0.0)))
	if eyes:
		var ey := length * 0.6
		var ez := radius * 0.84
		for sx: float in [-1.0, 1.0]:
			s.merge(LowPoly.boulder(Vector3(0.3, 0.38, 0.2) * radius, 0, 0.05, Color(0.98, 0.97, 0.92), seed_value + 90, 0.02), LowPoly.at(Vector3(sx * radius * 0.36, ey, ez)))
			s.merge(LowPoly.boulder(Vector3(0.12, 0.16, 0.1) * radius, 0, 0.05, Color(0.06, 0.05, 0.05), seed_value + 91, 0.02), LowPoly.at(Vector3(sx * radius * 0.30 + sx * 0.04 * radius, ey - radius * 0.06, ez + radius * 0.17)))
		s.merge(LowPoly.boulder(Vector3(0.2, 0.15, 0.1) * radius, 0, 0.1, Color(0.30, 0.08, 0.06), seed_value + 92, 0.04), LowPoly.at(Vector3(0.0, length * 0.46, ez * 1.02)))
	return s


## A cob lying on the floor (axis horizontal) at `center_xz`, turned `yaw` degrees, a quarter turn rolled about its axis.
static func lay_cob(s: LowPoly.Soup, center_xz: Vector3, length: float, radius: float, yaw: float, seed_value: int, burnt: float = 0.0) -> void:
	var c := cob(length, radius, seed_value, burnt)
	var basis := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.BACK, deg_to_rad(-90.0))
	basis = basis * Basis(Vector3.UP, deg_to_rad(float(seed_value % 7) * 51.0))
	var axis := basis * Vector3.UP
	var center := Vector3(center_xz.x, radius * 0.8 + 0.05, center_xz.z)
	s.merge(c, Transform3D(basis, center - axis * length * 0.5))


## A cob driven tip-first into something at `tip`, leaning `lean` (degrees: x forward/back, z left/right), `yaw` about itself.
static func stuck_cob(s: LowPoly.Soup, tip: Vector3, length: float, radius: float, lean: Vector3, yaw: float, seed_value: int, burnt: float = 0.0, eyes: bool = false) -> void:
	var c := cob(length, radius, seed_value, burnt, eyes)
	var basis := Basis.from_euler(Vector3(deg_to_rad(lean.x), 0.0, deg_to_rad(lean.z))) * Basis(Vector3.UP, deg_to_rad(yaw))
	s.merge(c, Transform3D(basis, tip))


## A clump of kernels (and a little popcorn) heaped around `center`.
static func kernels(s: LowPoly.Soup, center: Vector3, count: int, spread: float, rng: RandomNumberGenerator) -> void:
	for i in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * spread
		var p := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var sz := rng.randf_range(0.85, 1.2)
		if rng.randf() < 0.3:
			s.merge(LowPoly.boulder(Vector3(0.09, 0.08, 0.09) * sz, 0, 0.3, POP.darkened(rng.randf() * 0.12), Kit.n(), 0.05),
					LowPoly.at(p + Vector3(0.0, 0.07, 0.0), Vector3(rng.randf() * 360.0, rng.randf() * 360.0, 0.0)))
		else:
			var col := KERNEL if rng.randf() < 0.6 else KERNEL_DEEP
			s.merge(LowPoly.boulder(Vector3(0.055, 0.09, 0.055) * sz, 0, 0.12, col, Kit.n(), 0.05),
					LowPoly.at(p + Vector3(0.0, 0.06, 0.0), Vector3(rng.randf_range(65.0, 100.0), rng.randf() * 360.0, rng.randf_range(-20.0, 20.0))))


## A loose husk leaf flat on the floor.
static func loose_leaf(s: LowPoly.Soup, pos: Vector3, yaw: float, length: float, dry: bool) -> void:
	var col := HUSK_DRY if dry else HUSK
	s.merge(LowPoly.frustum(Vector2(length * 0.3, 0.014), Vector2(length * 0.07, 0.01), length, col, Kit.n(), 0.0, 1, Vector2.ZERO, 0.1),
			_xf(pos + Vector3(0.0, 0.04, 0.0), Vector3(84.0, yaw, 0.0)))


# --- Scorch -----------------------------------------------------------------------------------------

## A scorch mark flat on the floor: a brown halo, a char-black core, a few glowing embers and streaks flung outward.
static func scorch_floor(s: LowPoly.Soup, pos: Vector3, rx: float, rz: float, yaw: float, seed_value: int, streaks: int = 6) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var halo := LowPoly.cylinder(1.0, 1.0, 0.012, 12, SCORCH_RIM, seed_value, 0.0, 1, 0.12).jitter(0.16, seed_value, Vector3(1.0, 0.0, 1.0))
	s.merge(halo, _xf(pos + Vector3(0.0, 0.052, 0.0), Vector3(0.0, yaw, 0.0), Vector3(rx * 1.5, 1.0, rz * 1.5)))
	var mid := LowPoly.cylinder(1.0, 1.0, 0.012, 11, Color(0.16, 0.10, 0.065), seed_value + 1, 0.0, 1, 0.1).jitter(0.2, seed_value + 1, Vector3(1.0, 0.0, 1.0))
	s.merge(mid, _xf(pos + Vector3(0.0, 0.058, 0.0), Vector3(0.0, yaw + 20.0, 0.0), Vector3(rx * 0.95, 1.0, rz * 0.95)))
	var core := LowPoly.cylinder(1.0, 1.0, 0.012, 10, Color(0.07, 0.06, 0.055), seed_value + 2, 0.0, 1, 0.1).jitter(0.22, seed_value + 2, Vector3(1.0, 0.0, 1.0))
	s.merge(core, _xf(pos + Vector3(0.0, 0.064, 0.0), Vector3(0.0, yaw + 47.0, 0.0), Vector3(rx * 0.6, 1.0, rz * 0.6)))
	for i in streaks:
		var ang := rng.randf() * TAU
		var slen := rng.randf_range(0.9, 1.5) * maxf(rx, rz) * 1.55
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		var w := rng.randf_range(0.12, 0.26)
		s.merge(LowPoly.frustum(Vector2(w, 0.012), Vector2(w * 0.12, 0.012), slen, CHAR if i % 2 == 0 else Color(0.11, 0.07, 0.05), seed_value + 10 + i, 0.0, 1, Vector2.ZERO, 0.06),
				_xf(pos + Vector3(0.0, 0.06, 0.0) + dir * (maxf(rx, rz) * 0.5 + slen * 0.5), Vector3(90.0, rad_to_deg(ang), 0.0)))
	for i in 7:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.62
		var p := pos + Vector3(cos(a) * r * rx, 0.07, sin(a) * r * rz)
		s.merge(LowPoly.box(Vector3(0.07, 0.02, 0.06) * rng.randf_range(0.8, 1.6), Kit.glow(EMBER if i % 2 == 0 else Color(1.0, 0.62, 0.15)), Kit.n(), 0.0, 1, 0.0),
				LowPoly.at(p, Vector3(0.0, rng.randf() * 180.0, 0.0)))


## A scorch mark flat on a wall (facing +Z) at `pos`: a halo, a black core, flame-lick streaks climbing the wall.
static func scorch_wall(s: LowPoly.Soup, pos: Vector3, rx: float, ry: float, seed_value: int, licks: int = 7) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var halo := LowPoly.cylinder(1.0, 1.0, 0.012, 13, SCORCH_RIM, seed_value, 0.0, 1, 0.12).jitter(0.14, seed_value, Vector3(1.0, 0.0, 1.0))
	s.merge(halo, _xf(pos, Vector3(90.0, 0.0, 0.0), Vector3(rx * 1.3, 1.0, ry * 1.3)))
	var core := LowPoly.cylinder(1.0, 1.0, 0.012, 11, CHAR, seed_value + 1, 0.0, 1, 0.1).jitter(0.2, seed_value + 1, Vector3(1.0, 0.0, 1.0))
	s.merge(core, _xf(pos + Vector3(0.0, 0.0, 0.016), Vector3(90.0, 0.0, 0.0), Vector3(rx * 0.86, 1.0, ry * 0.86)))
	for i in licks:
		var fx := (float(i) / float(licks - 1) - 0.5) * 2.0
		var h := ry * rng.randf_range(1.2, 2.1) * (1.0 - absf(fx) * 0.45)
		var w := rng.randf_range(0.28, 0.5)
		var lean := fx * 7.0 + rng.randf_range(-5.0, 5.0)
		var base := pos + Vector3(fx * rx * 0.8, ry * 0.3, 0.02)
		var up := Vector3(-sin(deg_to_rad(lean)), cos(deg_to_rad(lean)), 0.0)
		s.merge(LowPoly.frustum(Vector2(w * 1.45, 0.012), Vector2(w * 0.1, 0.012), h * 1.12, SCORCH_RIM, seed_value + 20 + i, 0.0, 1, Vector2.ZERO, 0.08),
				_xf(base + up * h * 0.56, Vector3(0.0, 0.0, lean)))
		s.merge(LowPoly.frustum(Vector2(w, 0.012), Vector2(w * 0.08, 0.012), h, CHAR, seed_value + 40 + i, 0.0, 1, Vector2.ZERO, 0.06),
				_xf(base + up * h * 0.5 + Vector3(0.0, 0.0, 0.016), Vector3(0.0, 0.0, lean)))


# --- The van -----------------------------------------------------------------------------------------

## Damage layered on the van (`root` has the van's transform, so these are in van-local coordinates: nose +Z, camera side -X,
## roof at y 1.9): a popped, bent hood over a small fire, a scorched hole in the roof the cob went through.
static func van_damage(root: Node3D) -> void:
	var s := LowPoly.Soup.new(4242, 0.06)
	# the popped hood: hinged at the windscreen base, thrown up and skewed so the charred underside shows to the camera
	var hb := Basis.from_euler(Vector3(deg_to_rad(-62.0), deg_to_rad(-36.0), deg_to_rad(8.0)))
	var hc := Vector3(0.0, 1.24, 1.8) + hb * Vector3(0.0, 0.0, 0.3)
	s.merge(LowPoly.box(Vector3(1.86, 0.07, 0.6), Color(0.76, 0.76, 0.74), 4243, 0.0, 2, 0.05), Transform3D(hb, hc))
	s.merge(LowPoly.box(Vector3(1.78, 0.05, 0.54), Color(0.16, 0.14, 0.13), 4244, 0.0, 1, 0.05), Transform3D(hb, hc - hb * Vector3(0.0, 0.05, 0.0)))
	# the engine bay: black, with a hot glow
	s.merge(LowPoly.box(Vector3(1.6, 0.03, 0.26), CHAR, 4245, 0.0, 1, 0.04), LowPoly.at(Vector3(0.0, 1.27, 1.93)))
	s.merge(LowPoly.box(Vector3(0.9, 0.03, 0.16), Kit.glow(Color(0.9, 0.3, 0.06)), 4246, 0.0, 1, 0.0), LowPoly.at(Vector3(0.1, 1.29, 1.93)))
	for i in 3:
		var fx := -0.32 + 0.32 * float(i)
		Kit.rod(s, Vector3(fx, 1.3, 1.93), Vector3(fx * 0.7 + 0.04, 2.15 + 0.25 * float(i % 2), 1.93), 0.22 - 0.05 * float(i % 2), 0.0, 5, Kit.glow(Color(1.0, 0.48, 0.1)))
	Kit.rod(s, Vector3(0.0, 1.31, 1.93), Vector3(0.02, 1.85, 1.93), 0.12, 0.0, 5, Kit.glow(Color(1.0, 0.85, 0.4)))
	# the hole in the roof the cob went through: a black ring, torn flaps of roof turned up
	s.merge(LowPoly.cylinder(0.62, 0.62, 0.03, 12, CHAR, 4250, 0.0, 1, 0.08).jitter(0.07, 4250, Vector3(1.0, 0.0, 1.0)), LowPoly.at(Vector3(-0.1, 1.93, -1.3)))
	for i in 6:
		var a := float(i) / 6.0 * TAU + 0.3
		var p := Vector3(-0.1 + cos(a) * 0.46, 1.98, -1.3 + sin(a) * 0.46)
		s.merge(LowPoly.box(Vector3(0.34, 0.03, 0.2), Color(0.66, 0.67, 0.65) if i % 2 == 0 else Color(0.35, 0.34, 0.33), Kit.n(), 0.0, 1, 0.06),
				_xf(p + Vector3(0.0, 0.08, 0.0), Vector3(0.0, rad_to_deg(-a), 0.0)) * Transform3D(Basis(Vector3.BACK, deg_to_rad(-38.0)), Vector3.ZERO))
	root.add_child(Kit.mesh(s, 1.6, "VanDamage"))
	# ... and the corn bomb itself, wedged in it, smug (it has the spell's face), leaning back over the rear
	var c := LowPoly.Soup.new(4260, 0.06)
	stuck_cob(c, Vector3(-0.1, 1.82, -1.3), 2.0, 0.5, Vector3(-17.0, 0.0, 11.0), -90.0, 1401, 0.25, true)
	root.add_child(Kit.mesh(c, 2.0, "RoofCob"))


# --- The room ---------------------------------------------------------------------------------------

## The mess: scorch marks (floor and back wall), cobs, kernels, husks, the extinguisher in its foam. `van_at` is the
## van's position; `wall_z` the back wall's front face.
static func mess(root: Node3D, van_at: Vector3, wall_z: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var sc := LowPoly.Soup.new(31, 0.05)
	# floor: a blast crater in front of the van, one under the nose, a couple more
	scorch_floor(sc, van_at + Vector3(0.9, 0.0, 3.6), 2.2, 1.35, 8.0, 301, 7)
	scorch_floor(sc, van_at + Vector3(3.1, 0.0, 0.6), 1.5, 1.2, -20.0, 311, 5)
	scorch_floor(sc, van_at + Vector3(-1.6, 0.0, 1.7), 1.1, 0.8, 30.0, 321, 4)
	scorch_floor(sc, van_at + Vector3(5.0, 0.0, 4.0), 1.2, 0.8, 12.0, 331, 4)
	# the back wall: a big blast behind the van, flame licks climbing toward the neon
	scorch_wall(sc, Vector3(van_at.x + 1.0, 3.3, wall_z + 0.03), 2.8, 1.8, 341, 9)
	# ... and up the timber post in front of it, charred from the floor to the neon
	sc.merge(LowPoly.box(Vector3(0.52, 3.8, 0.012), Color(0.14, 0.09, 0.06), 361, 0.0, 1, 0.08), LowPoly.at(Vector3(3.6, 1.9, wall_z + 0.505)))
	sc.merge(LowPoly.box(Vector3(0.52, 2.2, 0.012), CHAR, 362, 0.0, 1, 0.06), LowPoly.at(Vector3(3.6, 1.1, wall_z + 0.51)))
	scorch_wall(sc, Vector3(van_at.x + 5.2, 0.7, wall_z + 0.03), 1.1, 0.7, 351, 4)
	root.add_child(Kit.mesh(sc, 0.0, "Scorch"))
	# corn, husks, foam
	var s := LowPoly.Soup.new(77, 0.07)
	lay_cob(s, van_at + Vector3(-0.2, 0.0, 5.2), 1.0, 0.17, 100.0, 1101)
	lay_cob(s, van_at + Vector3(2.6, 0.0, 4.5), 0.9, 0.16, 8.0, 1102, 0.9)
	lay_cob(s, van_at + Vector3(4.4, 0.0, 2.3), 1.0, 0.17, 58.0, 1103)
	lay_cob(s, van_at + Vector3(-1.9, 0.0, 3.0), 0.9, 0.17, 160.0, 1104, 0.5)
	lay_cob(s, van_at + Vector3(0.7, 0.0, 2.1), 0.85, 0.16, -30.0, 1105)
	stuck_cob(s, van_at + Vector3(4.3, -0.08, 3.9), 1.35, 0.26, Vector3(-24.0, 0.0, 16.0), 40.0, 1201, 0.4)
	for c: Array in [[-0.6, 4.4, 9], [1.9, 5.5, 8], [3.2, 3.0, 8], [-1.2, 2.2, 7], [4.8, 4.2, 7], [0.4, 1.9, 6], [5.5, 0.9, 7], [2.4, 2.0, 5], [-2.0, 5.0, 6], [3.8, 5.6, 5]]:
		kernels(s, van_at + Vector3(float(c[0]), 0.0, float(c[1])), int(c[2]), 0.42, rng)
	for i in 12:
		var p := van_at + Vector3(rng.randf_range(-2.2, 5.6), 0.0, rng.randf_range(0.8, 5.9))
		loose_leaf(s, p, rng.randf() * 360.0, rng.randf_range(0.55, 0.9), i % 3 == 0)
	extinguisher(s, van_at + Vector3(-1.5, 0.0, 4.1), 16.0)
	root.add_child(Kit.mesh(s, 1.6, "AfterMess"))


## A fire extinguisher lying on its side, its foam spat across the floor.
static func extinguisher(s: LowPoly.Soup, pos: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var a := pos + b * Vector3(-0.38, 0.19, 0.0)
	var e := pos + b * Vector3(0.34, 0.19, 0.0)
	Kit.rod(s, a, e, 0.17, 0.17, 8, EXT_RED)
	s.merge(LowPoly.boulder(Vector3(0.17, 0.16, 0.17), 0, 0.05, EXT_RED, 1301, 0.04), LowPoly.at(a - b * Vector3(0.02, 0.0, 0.0)))
	Kit.rod(s, e, e + b * Vector3(0.13, 0.0, 0.0), 0.17, 0.07, 8, Color(0.55, 0.57, 0.6))
	Kit.rod(s, e + b * Vector3(0.1, 0.02, 0.0), e + b * Vector3(0.2, 0.17, 0.0), 0.05, 0.05, 6, Color(0.1, 0.1, 0.11))
	Kit.rod(s, e + b * Vector3(0.2, 0.17, 0.0), e + b * Vector3(0.52, 0.04, 0.12), 0.03, 0.03, 5, Color(0.1, 0.1, 0.11))
	Kit.rod(s, pos + b * Vector3(-0.05, 0.19, 0.0), pos + b * Vector3(0.05, 0.19, 0.0), 0.176, 0.176, 8, Color(0.95, 0.92, 0.82))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1302
	for i in 9:
		var d := b * Vector3(rng.randf_range(0.7, 2.0), 0.0, rng.randf_range(-0.55, 0.55))
		var rad := rng.randf_range(0.14, 0.3)
		s.merge(LowPoly.boulder(Vector3(rad, 0.045, rad * 0.8), 0, 0.2, FOAM.darkened(rng.randf() * 0.08), Kit.n(), 0.04),
				LowPoly.at(pos + d + Vector3(0.0, 0.07, 0.0), Vector3(0.0, rng.randf() * 180.0, 0.0)))


## The paper tacked to the back wall: an invoice, PAST DUE in red across it.
static func invoice(parent: Node3D, pos: Vector3) -> void:
	var inv := Kit.paper_sign("INVOICE #0451\n1x CORN REMOVAL\n$ 9,999.00\nNET 0 DAYS", Vector2(1.25, 1.4), 34, Kit.PAPER)
	Kit.put(parent, inv, pos)
	inv.rotation.z = deg_to_rad(-5.0)
	var stamp := Kit.decal_text("PAST DUE", 62, SOOT_RED, 0.0042)
	stamp.outline_size = 0
	stamp.position = Vector3(0.0, -0.3, 0.034)
	stamp.rotation.z = deg_to_rad(16.0)
	inv.add_child(stamp)


## The corn sign after a bad job: bigger, crooked, in red, with a huge 0 pasted over its number. Returns the extra nodes under `parent`.
static func corn_sign_zero(parent: Node3D, sign_node: Node3D, number: String) -> void:
	var holder := Node3D.new()
	holder.name = "CornZero"
	holder.transform = sign_node.transform
	parent.add_child(holder)
	var s := LowPoly.Soup.new(Kit.n(), 0.03)
	s.merge(LowPoly.box(Vector3(0.9, 0.27, 0.012), Kit.PAPER_OLD, Kit.n(), 0.0, 1, 0.02), LowPoly.at(Vector3(0.0, -0.395, 0.02)))
	var m := Kit.mesh(s, 0.0, "ZeroPatch")
	holder.add_child(m)
	var lbl := Kit.decal_text(number, 92, SOOT_RED, 0.0042)
	lbl.name = "Number"
	lbl.position = Vector3(0.0, -0.38, 0.03)
	holder.add_child(lbl)


## A bare bulb on a cord (the work lamp, failing): returns the root at the ceiling end; `bulb_mat` gets the bulb's material.
static func hanging_bulb(top: Vector3, length: float) -> Node3D:
	var root := Node3D.new()
	root.name = "HangingBulb"
	root.position = top
	var cord := LowPoly.Soup.new(Kit.n(), 0.02)
	Kit.rod(cord, Vector3.ZERO, Vector3(0.0, -length, 0.0), 0.016, 0.016, 4, Color(0.08, 0.08, 0.09))
	cord.merge(LowPoly.cylinder(0.07, 0.085, 0.16, 6, Color(0.22, 0.22, 0.25), Kit.n(), 0.0, 1, 0.04), LowPoly.at(Vector3(0.0, -length - 0.05, 0.0)))
	root.add_child(Kit.mesh(cord, 0.0, "Cord"))
	var bulb := LowPoly.Soup.new(Kit.n(), 0.0)
	bulb.merge(LowPoly.boulder(Vector3(0.14, 0.17, 0.14), 1, 0.04, Kit.glow(Color(1.0, 0.82, 0.5)), Kit.n(), 0.0), LowPoly.at(Vector3(0.0, -length - 0.24, 0.0)))
	var bm := Kit.mesh(bulb, 0.0, "Bulb")
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bm)
	return root


# --- Atmosphere -------------------------------------------------------------------------------------

## A column of smoke. Warm where it leaves the fire, grey in the middle where the work lamp lights it, cool at the top where
## the grate light catches it.
static func smoke(node_name: String, amount: int, sphere: float, size_min: float, size_max: float, speed_min: float, speed_max: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = node_name
	p.amount = amount
	p.lifetime = 3.0
	p.preprocess = 3.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = sphere
	p.direction = Vector3(0.12, 1.0, 0.05)
	p.spread = 16.0
	p.gravity = Vector3(0.08, 0.2, 0.03)
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(1.0, 1.1))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.1, 0.4, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.62, 0.3, 0.0), Color(0.50, 0.33, 0.25, 1.0), Color(0.13, 0.12, 0.12, 1.0), Color(0.24, 0.25, 0.30, 0.8), Color(0.42, 0.47, 0.58, 0.0)])
	p.color_ramp = ramp
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	m.albedo_texture = puff_texture()
	qm.material = m
	p.mesh = qm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Grey ash and a few popcorn flakes drifting down through the room.
static func ash(extent: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Ash"
	p.amount = 36
	p.lifetime = 11.0
	p.preprocess = 11.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extent
	p.direction = Vector3(0.3, -1.0, 0.1)
	p.spread = 25.0
	p.gravity = Vector3(0.0, -0.05, 0.0)
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.45
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	var qm := QuadMesh.new()
	qm.size = Vector2(0.06, 0.04)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.42, 0.4, 0.38, 0.8)
	qm.material = m
	p.mesh = qm
	return p


## A soft round puff (a radial alpha falloff).
static func puff_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	return tex


# --- The crew ---------------------------------------------------------------------------------------

## Scuff the crew up: sooty (greyer, a touch darker) and a plaster and a smudge on each face. Returns the nodes added (the
## caller frees them when the mood changes). The models' own parts are only re-tinted (see `clean_crew`).
static func dress_crew(crew: Array) -> Array[Node]:
	var added: Array[Node] = []
	for entry in crew:
		var m := entry as LowPolyModel
		if m == null:
			continue
		_tint(m, 0.32, 0.86)
		var head := m.get_part("head")
		if head == null or head.mesh == null:
			continue
		var bb := head.mesh.get_aabb()
		var s := LowPoly.Soup.new(Kit.n(), 0.02)
		var z := bb.position.z - 0.004
		var cx := bb.position.x + bb.size.x * 0.7
		var cy := bb.position.y + bb.size.y * 0.3
		s.merge(LowPoly.box(Vector3(bb.size.x * 0.42, bb.size.y * 0.13, 0.02), PLASTER, Kit.n(), 0.0, 1, 0.02), _xf(Vector3(cx, cy, z), Vector3(0.0, 0.0, 38.0)))
		s.merge(LowPoly.box(Vector3(bb.size.x * 0.42, bb.size.y * 0.13, 0.02), PLASTER, Kit.n(), 0.0, 1, 0.02), _xf(Vector3(cx, cy, z - 0.002), Vector3(0.0, 0.0, -38.0)))
		s.merge(LowPoly.boulder(Vector3(bb.size.x * 0.2, bb.size.y * 0.1, 0.012), 0, 0.2, Color(0.1, 0.09, 0.09), Kit.n(), 0.03), LowPoly.at(Vector3(bb.position.x + bb.size.x * 0.28, bb.position.y + bb.size.y * 0.62, z)))
		s.merge(LowPoly.boulder(Vector3(bb.size.x * 0.17, bb.size.y * 0.08, 0.012), 0, 0.2, Color(0.12, 0.1, 0.1), Kit.n(), 0.03), LowPoly.at(Vector3(bb.position.x + bb.size.x * 0.42, bb.position.y + bb.size.y * 0.16, z)))
		var mi := MeshInstance3D.new()
		mi.name = "FaceScuffs"
		mi.mesh = s.to_mesh()
		mi.material_override = LowPolyMaterial.make(0.0)
		head.add_child(mi)
		added.append(mi)
	return added


## Undo dress_crew's tint.
static func clean_crew(crew: Array) -> void:
	for entry in crew:
		var m := entry as LowPolyModel
		if m != null:
			_tint(m, 0.0, 1.0)


static func _tint(m: LowPolyModel, desat: float, gain: float) -> void:
	for part in m.parts.values():
		var mi := part as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("desat", desat)
			mat.set_shader_parameter("lit_gain", gain)


# --- Animators --------------------------------------------------------------------------------------

## A failing work lamp: mostly dim and sagging, a long dropout every few seconds, then a stutter of on/off flashes. Drives a
## light and (optionally) the glow of a bulb's material. Allocates nothing per frame.
class FailingLamp extends Node:
	var light: Light3D
	var bulb_mat: ShaderMaterial
	var base := 3.0
	var bulb_gain := 2.2
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		var cyc := fmod(_t, 4.3)
		var k := 0.55 + 0.1 * sin(_t * 2.7) + 0.08 * sin(_t * 9.1)
		if cyc > 3.1 and cyc < 3.9:
			k = 1.0 if fmod(cyc * 11.0, 1.0) < 0.4 else 0.04
		elif cyc > 1.6 and cyc < 1.95:
			k = 0.06
		if light != null:
			light.light_energy = base * k
		if bulb_mat != null:
			bulb_mat.set_shader_parameter("glow_gain", bulb_gain * (0.15 + 0.85 * k))
