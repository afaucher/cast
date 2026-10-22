extends RefCounted
## The garage's "morning after a bad job" dressing (MenuBackdrop mood "after"). Presentation only: every piece is
## built once when the mood is applied, nothing allocates per frame, and the random numbers come from local seeded
## RNGs (never GameWorld.rng).
##
## It has to read as a disaster at a glance, and stay funny without explaining itself:
##   - CORN: a giant smug cob wedged in the van roof, whole cobs lying about (kernel-bumped, husked, one scorched),
##     one planted in the floor, kernels and popcorn in clumps, loose husk leaves. Never a word about corn but the sign.
##   - DAMAGE: a popped hood with a small fire and a thick smoke column (soft soot round the nose only if SOOT says so),
##     a door hanging crooked, a failing work lamp.
##   - STORY: an invoice nailed to the wall stamped PAST DUE, the corn sign reading a big red 0, an extinguisher on its
##     side in a puddle of foam, the crew scuffed, sooty, patched (on their faces) and slumping (feet planted).
##
## No class_name on purpose (like the backdrop kit): the backdrop preloads this file.

const Kit := preload("res://scripts/ui/backdrops/backdrop_kit.gd")

const KERNEL := Color(1.0, 0.80, 0.16)
const KERNEL_DEEP := Color(0.95, 0.64, 0.07)
const KERNEL_PALE := Color(1.0, 0.90, 0.42)
const POP := Color(1.0, 0.95, 0.80)
const CHAR := Color(0.05, 0.045, 0.045)
const HUSK := Color(0.34, 0.62, 0.20)
const HUSK_DRY := Color(0.58, 0.50, 0.24)
const STEM := Color(0.46, 0.52, 0.20)
const SOOT_RED := Color(0.78, 0.07, 0.05)
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


# --- Soot -------------------------------------------------------------------------------------------

## The fire's marks. They used to be big char-black splats with a brown rim and black spikes flung out (four on the floor,
## one up the back wall behind the van, a charred post): huge, hard-edged and far from the small hood fire, they read as a
## hole, not as soot. Now: "none" (the default: the smoke, the popped hood and the glow tell the fire) or "soot": soft
## sooty gradients where the hood fire would leave them (the floor under the van's nose, a stain up the van's flank from
## the hood seam). Switch here (the lab: `--soot none|soot`).
const SOOT_NONE := "none"
const SOOT_SOFT := "soot"
const SOOT_STYLES: Array[String] = [SOOT_NONE, SOOT_SOFT]
const SOOT := SOOT_NONE
const SOOT_INK := Color(0.045, 0.038, 0.034)


## The hood fire's soot, in the van's own space (`root` has the van's transform: nose +Z, camera side -X, the hood fire
## at about (0, 1.3, 1.93)): a soft patch on the floor round the nose, a stain rising from the hood seam up the camera
## side. Unshaded alpha gradients (a darkening, no edge, no rim); nothing moves.
static func soot(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Soot"
	root.add_child(holder)
	# the floor: under and in front of the nose, wider than deep, fading out well before the crew
	var floor_q := _soot_quad(Vector2(2.6, 2.6), soot_texture(611, false, 0.8))
	floor_q.name = "FloorSoot"
	floor_q.position = Vector3(-1.1, 0.075, 2.3)
	floor_q.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	holder.add_child(floor_q)
	# the flank: from the hood seam (the front of the camera side, at the hood line) up over the cab side, drifting back
	# (the quad's +x points to the nose: a positive roll leans its top toward the rear)
	var side_q := _soot_quad(Vector2(0.8, 1.05), soot_texture(613, true, 0.85))
	side_q.name = "FlankSoot"
	side_q.position = Vector3(-1.075, 1.12, 1.66)
	side_q.rotation_degrees = Vector3(0.0, -90.0, 12.0)
	holder.add_child(side_q)


static func _soot_quad(size: Vector2, tex: Texture2D) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = SOOT_INK
	m.albedo_texture = tex
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A soft soot gradient (white, the alpha is the soot): a blob, or a `plume` (narrow and dense at the bottom, widening and
## thinning as it rises), its edge broken up by a seeded noise. `peak` is the densest alpha.
static func soot_texture(seed_value: int, plume: bool, peak: float) -> ImageTexture:
	var size := 96
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.06
	noise.fractal_octaves = 3
	for py in size:
		for px in size:
			var u := (float(px) + 0.5) / float(size) * 2.0 - 1.0      # -1 .. 1, left to right
			var v := 1.0 - (float(py) + 0.5) / float(size) * 2.0      # -1 .. 1, bottom to top
			var r: float
			var dense := 1.0
			if plume:
				var t := (v + 1.0) * 0.5                               # 0 at the bottom .. 1 at the top
				var width := lerpf(0.35, 0.95, sqrt(t))
				r = maxf(absf(u) / width, absf(v + 0.1) / 0.95)
				dense = lerpf(1.0, 0.45, t)
			else:
				r = Vector2(u, v).length()
			var nz := noise.get_noise_2d(float(px), float(py)) * 0.5 + 0.5
			var a := (1.0 - smoothstep(0.15, 1.0, r + (nz - 0.5) * 0.35)) * dense * (0.75 + 0.25 * nz)
			img.set_pixel(px, py, Color(1.0, 1.0, 1.0, clampf(a * peak, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


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
	# (its top 1 cm above the roof's, clear of the roof's dents: level with it, the two z-fought)
	s.merge(LowPoly.cylinder(0.62, 0.62, 0.03, 12, CHAR, 4250, 0.0, 1, 0.08).jitter(0.07, 4250, Vector3(1.0, 0.0, 1.0)), LowPoly.at(Vector3(-0.1, 1.94, -1.3)))
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

## The mess: cobs, kernels, husks, the extinguisher in its foam (the fire's soot is `soot`). `van_at` is the van's
## position.
static func mess(root: Node3D, van_at: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
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

## Where the after mood scuffs each hero, in the head part's own space (the model faces -Z, +X is its right, the cheek the
## front spot turns to the camera): the crossed plasters ("at", a strip's "len") and a soot smudge or two (x, y, size).
## "on" says which way they are pasted: "face" (at = x, y on the face, found along +Z) or "top" (at = x, z on the crown,
## found looking down: Gasket's face is all goggles, brows and beard, so her plasters go on a bump on her head). How deep
## each piece sits is found on the head itself (`face_fit`): the face's front is NOT the head mesh's front (a nose and a
## brow stand ~0.1 proud of it), and pasting at the mesh's bounds left the plasters floating in front of the faces.
const FACE_SCUFFS := {
	"WickModel": {"on": "face", "at": Vector2(0.09, -0.14), "len": 0.08, "smudges": [Vector3(-0.085, -0.09, 0.04)]},
	"GasketModel": {"on": "top", "at": Vector2(0.09, -0.09), "len": 0.15, "smudges": [Vector3(-0.17, -0.08, 0.045)]},
	"RebarModel": {"on": "face", "at": Vector2(0.22, -0.10), "len": 0.14, "smudges": [Vector3(-0.15, -0.255, 0.055)]},
}
const SMUDGE := Color(0.3, 0.26, 0.23)   ## soot on skin or stone: dark, but well off the eyes' near-black (or it reads as an eye)
const PLASTER_W := 0.3        ## a plaster strip's width, as a share of its length
const PLASTER_T := 0.014      ## its thickness
const SCUFF_GAP := 0.003      ## air between the face and the back of a plaster or smudge


## Scuff the crew up: sooty (greyer, a touch darker) and a plaster and a smudge on each face, pasted ON the face (under the
## head part, so they follow every nod). Returns the nodes added (the caller frees them when the mood changes). The models'
## own parts are only re-tinted (see `clean_crew`).
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
		var spot: Dictionary = FACE_SCUFFS.get(str(m.name), _default_scuffs(head.mesh.get_aabb()))
		var faces := head.mesh.get_faces()
		var s := LowPoly.Soup.new(Kit.n(), 0.0)
		var at: Vector2 = spot["at"]
		var length := float(spot["len"])
		var w := length * PLASTER_W
		var fit := paste_fit(faces, str(spot.get("on", "face")), at, plaster_half(length), PLASTER_T)
		s.merge(LowPoly.box(Vector3(length, w, PLASTER_T), PLASTER, Kit.n(), 0.0, 1, 0.0), fit * _xf(Vector3.ZERO, Vector3(0.0, 0.0, 38.0)))
		s.merge(LowPoly.box(Vector3(length, w, PLASTER_T), PLASTER.darkened(0.04), Kit.n(), 0.0, 1, 0.0), fit * _xf(Vector3(0.0, 0.0, -PLASTER_T * 0.6), Vector3(0.0, 0.0, -38.0)))
		for sm: Vector3 in spot["smudges"]:
			var sz := sm.z
			var sfit := face_fit(faces, Vector2(sm.x, sm.y), Vector2(sz, sz * 0.7), 0.01)
			s.merge(LowPoly.boulder(Vector3(sz, sz * 0.6, 0.005), 0, 0.25, SMUDGE, Kit.n(), 0.0), sfit * _xf(Vector3.ZERO, Vector3(0.0, 0.0, 14.0)))
		var mi := MeshInstance3D.new()
		mi.name = "FaceScuffs"
		mi.mesh = s.to_mesh()
		mi.material_override = LowPolyMaterial.make(0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.add_child(mi)
		added.append(mi)
	return added


## A head nobody tuned: a cheek right of centre, a little below the middle.
static func _default_scuffs(bb: AABB) -> Dictionary:
	var c := bb.get_center()
	return {"on": "face", "at": Vector2(c.x + bb.size.x * 0.25, c.y - bb.size.y * 0.15), "len": bb.size.x * 0.3,
		"smudges": [Vector3(c.x - bb.size.x * 0.25, c.y - bb.size.y * 0.1, bb.size.x * 0.12)]}


## Half the footprint of the crossed plasters (two strips `length` long crossing at +-38 degrees), on the surface.
static func plaster_half(length: float) -> Vector2:
	var w := length * PLASTER_W
	var a := deg_to_rad(38.0)
	return Vector2(0.5 * length * cos(a) + 0.5 * w * sin(a), 0.5 * length * sin(a) + 0.5 * w * cos(a))


## Turns the head so its crown faces -Z (x stays x, z becomes y): `face_fit` then pastes onto the top of the head.
const _CROWN := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))


## `face_fit` on the face ("face": at = x, y) or on the crown ("top": at = x, z), in the head's own space.
static func paste_fit(faces: PackedVector3Array, on: String, at: Vector2, half: Vector2, thickness: float) -> Transform3D:
	if on != "top":
		return face_fit(faces, at, half, thickness)
	var turned := PackedVector3Array()
	turned.resize(faces.size())
	for i in faces.size():
		turned[i] = _CROWN * faces[i]
	return Transform3D(_CROWN.inverse(), Vector3.ZERO) * face_fit(turned, at, half, thickness)


## The transform that pastes a flat piece `thickness` deep onto a face (a mesh's triangles, `get_faces()`) at `at` (x, y in
## the mesh's space), covering +-`half`: the face's depth is sampled over that footprint (rays along +Z from the front), a
## plane is fitted through the samples so the piece follows the face's slope (a bevel, a cheek turning away), and the piece
## is moved out until nothing of the face pokes through it. The piece's own x / y lie on the face, its z points into it.
static func face_fit(faces: PackedVector3Array, at: Vector2, half: Vector2, thickness: float) -> Transform3D:
	var pts: Array[Vector3] = []
	for iy in 3:
		for ix in 3:
			var p := at + Vector2((float(ix) - 1.0) * half.x, (float(iy) - 1.0) * half.y)
			var z := face_depth(faces, p)
			if z < INF:
				pts.append(Vector3(p.x - at.x, p.y - at.y, z))
	if pts.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(at.x, at.y, 0.0))
	# least squares z = a + b x + c y over the samples (x, y relative to `at`)
	var sx := 0.0
	var sy := 0.0
	var sz := 0.0
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	var sxz := 0.0
	var syz := 0.0
	for q in pts:
		sx += q.x
		sy += q.y
		sz += q.z
		sxx += q.x * q.x
		syy += q.y * q.y
		sxy += q.x * q.y
		sxz += q.x * q.z
		syz += q.y * q.z
	var n := float(pts.size())
	var m := Basis(Vector3(n, sx, sy), Vector3(sx, sxx, sxy), Vector3(sy, sxy, syy))   # (symmetric: columns = rows)
	var abc := Vector3(sz / n, 0.0, 0.0)
	if absf(m.determinant()) > 1e-9:
		abc = m.inverse() * Vector3(sz, sxz, syz)
	# move the plane out to the front-most sample (a sample in front of the plane would poke through the piece)
	var proud := 0.0
	for q in pts:
		proud = maxf(proud, (abc.x + abc.y * q.x + abc.z * q.y) - q.z)
	var zc := abc.x - proud
	var into := Vector3(-abc.y, -abc.z, 1.0).normalized()
	var x_axis := (Vector3.RIGHT - into * into.x).normalized()
	var y_axis := into.cross(x_axis)
	return Transform3D(Basis(x_axis, y_axis, into), Vector3(at.x, at.y, zc) - into * (thickness * 0.5 + SCUFF_GAP))


## The front-most depth (smallest z) of the mesh at (x, y), INF when no triangle covers it.
static func face_depth(faces: PackedVector3Array, p: Vector2) -> float:
	var best := INF
	for i in range(0, faces.size() - 2, 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(d) < 1e-9:
			continue
		var l1 := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / d
		var l2 := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / d
		var l3 := 1.0 - l1 - l2
		if l1 < -1e-5 or l2 < -1e-5 or l3 < -1e-5:
			continue
		best = minf(best, l1 * a.z + l2 * b.z + l3 * c.z)
	return best


## The slump after a bad job, laid over a model's own idle every frame (it processes after the models, `process_priority`):
## the torso stoops a little and goes askew, the head hangs, and the feet stay planted. (It used to tilt the whole model
## about its feet: 12 degrees on Rebar, the tallest and nearest, threw his head ~0.7 forward and down toward the camera.)
## Built per model by the backdrop under its mood node; leaving the tree puts the parts back.
class Slump extends Node:
	var model: LowPolyModel
	var stoop := 0.0        ## rad, the torso forward (about its own pivot, at the hips)
	var droop := 0.0        ## rad, the head down
	var roll := 0.0         ## rad, the torso askew
	var _laid := {}         ## part name -> [the rotation written, the model's own rotation under it]

	func _init() -> void:
		name = "Slump"
		process_priority = 100   # after the models' own _process (their idle writes the parts first)

	func _ready() -> void:
		lay()

	func _process(_delta: float) -> void:
		lay()

	## Lay the slump over the parts' current pose (also callable right after placing, so the first frame is already slumped).
	func lay() -> void:
		if model == null or not is_instance_valid(model):
			return
		_lay("body", Vector3(-stoop, 0.0, roll))
		_lay("head", Vector3(-droop, 0.0, 0.0))

	## The model's own rotation of a part, without the slump (tests).
	func own_rotation(part: String) -> Vector3:
		var p := model.get_part(part) if model != null else null
		if p == null:
			return Vector3.ZERO
		var w: Array = _laid.get(part, [])
		return w[1] if w.size() == 2 and p.rotation.is_equal_approx(w[0]) else p.rotation

	func _lay(part: String, add: Vector3) -> void:
		var p := model.get_part(part)
		if p == null:
			return
		var base := own_rotation(part)   # (an idle that sets the part every frame wrote a fresh pose; one that leaves it keeps the last)
		p.rotation = base + add
		_laid[part] = [p.rotation, base]

	func _exit_tree() -> void:
		if model == null or not is_instance_valid(model):
			return
		for part: String in _laid.keys():
			var p := model.get_part(part)
			if p != null:
				p.rotation = own_rotation(part)
		_laid.clear()


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
