extends RefCounted
## Goo imp BLOCKOUTS (docs/design/goo-imp.md): three looks for a proposed sewer pest, a ranged cousin of the swarmer imp
## that lobs goo balls. LOOK-DEV ONLY, for goo_imp_lab.gd: no Monster kind uses them, MonsterModels does not make them,
## MonsterDefs has no row, nothing declares gameplay state, and they are not in ZFightModels.
##
##   const GooImpBlockouts := preload("res://scripts/art/lowpoly/monsters/goo_imp_blockouts.gd")
##   var m := GooImpBlockouts.build("sac", GooImpBlockouts.GOO["bile"])   # an ImpBody (MonsterModel)
##   m.pose_preview("windup", 1.0)       # the throw: the ball drawn back over the head; "swing" = the release
##   m.ball_point()                      # world point of the goo ball in its hand (or ladle)
##
## The family: the swarmer's body plan (pot belly, big glowing eyes, a grin, a tail, clawed hands and feet) at about the
## same size, so it reads as its cousin, but a sewer animal: pale axolotl-pink, warty skin, three gill frills each side
## where the swarmer has bat ears, webbed feet, a finned tail, and goo drooling from the grin. Every goo face glows (vertex
## alpha 0.5, MonsterMaterial): the goo is the beacon, the body is matte. The goo colour is a parameter (GOO) so the lab can
## test it against the sewer's greens.
## Faces local -Z, +X is its right, origin at the feet.
##
##   sac     Goo Sac: a big glowing goo bladder grown on its back, a spout on top; it pinches a ball off the spout with its
##           right hand. The rounded hump is the silhouette. About 1.0 tall, 0.75 across with the sac.
##   drip    Gloop: the imp dripping with its own goo: a goo cap running down its head, drips off its chin, elbows and belly,
##           a puddle at its feet, a ball welling up in its cupped hands. No prop; the body itself reads as goo. About 0.95.
##   ladle   Slinger: a yellow mop bucket of goo on its left arm and a long soup ladle carried on its right shoulder, the bowl
##           full of goo up behind its head; the long diagonal handle is the silhouette. About 1.0 tall, the bowl at 1.5.

const KINDS: Array[String] = ["sac", "drip", "ladle"]
const NAMES := {"sac": "Goo Sac", "drip": "Gloop", "ladle": "Slinger"}

## The goo colours under test: bile is the enemy chartreuse (the healers' water), pink a hot bubblegum magenta (no spell
## owns it; Tentacles is violet, Chicken red), tar an amber grease (reads "flammable", but sits next to Fireball's orange).
const GOO := {
	"bile": Color(0.80, 1.0, 0.16),
	"pink": Color(1.0, 0.30, 0.72),
	"tar": Color(1.0, 0.62, 0.10),
}


static func build(kind: String, goo: Color = GOO["bile"]) -> ImpBody:
	match kind:
		"sac":
			return SacImp.new(goo)
		"drip":
			return DripImp.new(goo)
		"ladle":
			return LadleImp.new(goo)
	return null


## A darker, unlit shade of a goo colour (the goo's body where it does not glow).
static func deep(c: Color) -> Color:
	return Color(c.r * 0.55, c.g * 0.55, c.b * 0.55)


## A paler, hotter highlight of a goo colour.
static func hot(c: Color) -> Color:
	return c.lerp(Color(1, 1, 1), 0.45)


## The shared imp: body, head with gills, arms, legs, finned tail; a goo ball under the right hand. Subclasses add their
## carry and override the throwing arm.
class ImpBody extends MonsterModel:
	const SKIN := Color(0.88, 0.52, 0.50)
	const SKIN_LIGHT := Color(0.96, 0.66, 0.60)
	const SKIN_DARK := Color(0.60, 0.30, 0.34)
	const WART := Color(0.66, 0.36, 0.38)
	const BELLY := Color(0.99, 0.82, 0.68)
	const GILL := Color(0.78, 0.22, 0.34)
	const CLAW := Color(0.98, 0.94, 0.82)
	const VOID := Color(0.10, 0.04, 0.06)
	const EYE := Color(1.0, 0.90, 0.18)
	const BODY_Y := 0.32
	const LEG_X := 0.12
	const HEAD_AT := Vector3(0.0, 0.44, -0.06)
	const SHOULDER := Vector3(0.23, 0.26, -0.05)
	const HAND := Vector3(0.0, -0.31, -0.03)

	var goo := Color(0.80, 1.0, 0.16)
	var model_scale := 0.95

	func _init(goo_colour: Color) -> void:
		goo = goo_colour
		_setup_model("GooImp", model_scale)
		monster_kind = "goo_imp"
		ui_height = 1.1 * model_scale
		_build()
		apply_idle(0.0)

	func ball_point() -> Vector3:
		return (parts["ball"] as Node3D).global_position if parts.has("ball") else global_position + Vector3.UP

	func _build() -> void:
		var body := _add_part("body", _body_soup(), self, Vector3(0, BODY_Y, 0))
		var head := _add_part("head", _head_soup(), body, HEAD_AT)
		for s: int in [-1, 1]:
			var side := "l" if s < 0 else "r"
			_add_part("gill_" + side, _gill_soup(s), head, Vector3(0.25 * s, 0.02, 0.06))
			_add_part("arm_" + side, _arm_soup(s), body, Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z))
			_add_part("leg_" + side, _leg_soup(s), self, Vector3(LEG_X * s, BODY_Y, 0.0))
		_add_part("tail", _tail_soup(), body, Vector3(0, 0.04, 0.18))
		_add_part("ball", _ball_soup(0.12, 961), parts["arm_r"] as Node3D, HAND + Vector3(0, -0.06, -0.02))
		_build_carry()

	func _build_carry() -> void:
		pass

	## Pot belly with a pale plate, warts down the back, a low ridge where the swarmer has spikes.
	func _body_soup() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(901, 0.08)
		blob(s, Vector3(0, 0.15, 0.0), Vector3(0.26, 0.25, 0.23), SKIN, 902, 0.15, 0)
		blob(s, Vector3(0, 0.12, -0.15), Vector3(0.18, 0.19, 0.10), BELLY, 903, 0.15, 0)
		blob(s, Vector3(0, 0.31, 0.05), Vector3(0.20, 0.11, 0.16), SKIN_LIGHT, 904, 0.15, 0)
		for i in 7:
			var a := 0.5 + 0.8 * float(i)
			blob(s, Vector3(cos(a) * 0.17, 0.12 + 0.05 * float(i % 3), 0.12 + sin(a) * 0.05), Vector3.ONE * 0.045, WART, 905 + i, 0.2)
		limb(s, Vector3(0, 0.36, 0.12), Vector3(0, 0.08, 0.26), 0.05, 0.03, 4, SKIN_DARK, 913)
		return s

	## A wide, flat axolotl head: big glowing eyes, a wide grin with goo drooling from it, two nubs of horn.
	func _head_soup() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(921, 0.08)
		blob(s, Vector3.ZERO, Vector3(0.30, 0.20, 0.25), SKIN_LIGHT, 922, 0.1, 1)
		for x: int in [-1, 1]:
			slab(s, Vector3(0.11 * x, 0.06, -0.225), Vector3(0.13, 0.07, 0.04), glow(EYE), 923 + x, Vector3(0, 0, 28 * x), 0.0, 0.0)
			blob(s, Vector3(0.11 * x, 0.13, -0.19), Vector3(0.08, 0.035, 0.05), SKIN_DARK, 926 + x, 0.15)           # brow
			limb(s, Vector3(0.10 * x, 0.15, 0.02), Vector3(0.14 * x, 0.26, 0.04), 0.05, 0.0, 5, CLAW, 928 + x)        # horn nubs
			blob(s, Vector3(0.20 * x, -0.04, -0.06), Vector3.ONE * 0.04, WART, 930 + x, 0.2)
		slab(s, Vector3(0, -0.085, -0.22), Vector3(0.34, 0.07, 0.04), VOID, 932, Vector3.ZERO, 0.0, 0.0)               # the grin
		slab(s, Vector3(0, -0.10, -0.225), Vector3(0.26, 0.03, 0.04), glow(goo), 933, Vector3.ZERO, 0.0, 0.0)          # goo in the mouth
		for i in 4:
			var x := -0.105 + 0.07 * float(i)
			limb(s, Vector3(x, -0.06, -0.235), Vector3(x, -0.11, -0.235), 0.025, 0.0, 4, CLAW, 934 + i, 0.0, 0.03)     # teeth (roots inside the grin: no cap on its top face)
		limb(s, Vector3(-0.12, -0.11, -0.22), Vector3(-0.13, -0.24, -0.21), 0.025, 0.012, 4, glow(goo), 939)            # drool
		blob(s, Vector3(-0.13, -0.245, -0.21), Vector3.ONE * 0.028, glow(goo), 940, 0.1)
		limb(s, Vector3(0.09, -0.11, -0.22), Vector3(0.10, -0.18, -0.22), 0.02, 0.01, 4, glow(goo), 941)
		return s

	## Three gill frills fanning back and out (the swarmer's bat ear, as a sewer animal's gills).
	func _gill_soup(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(951 + side, 0.07)
		var sd := float(side)
		for i in 3:
			var up := 0.16 - 0.13 * float(i)
			var tip := Vector3(0.26 * sd, up + 0.02, 0.10 + 0.05 * float(i))
			limb(s, Vector3.ZERO, tip, 0.05, 0.02, 4, GILL, 953 + i + 3 * side)
			for j in 2:
				var p := tip * (0.45 + 0.3 * float(j))
				blob(s, p + Vector3(0, 0.03, 0), Vector3(0.035, 0.05, 0.02), GILL.lightened(0.15), 960 + i * 2 + j + 6 * side, 0.15)
		return s

	## Stubby arm with a webbed, clawed hand (rest pose raises it).
	func _arm_soup(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(971 + side, 0.07)
		limb(s, Vector3(0, 0, 0), Vector3(0, -0.26, -0.02), 0.075, 0.065, 5, SKIN, 972 + side)
		blob(s, Vector3(0, -0.30, -0.03), Vector3(0.095, 0.08, 0.09), SKIN_LIGHT, 974 + side, 0.15)
		for i in 3:
			var x := (float(i) - 1.0) * 0.05
			limb(s, Vector3(x, -0.34, -0.04), Vector3(x * 1.5, -0.45, -0.07), 0.03, 0.0, 4, CLAW, 976 + i + 3 * side, 0.0, 0.03)
		return s

	func _leg_soup(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(991 + side, 0.07)
		limb(s, Vector3(0, 0, 0), Vector3(0, -0.20, -0.02), 0.095, 0.075, 5, SKIN_DARK, 992 + side)
		slab(s, Vector3(0, -0.29, -0.08), Vector3(0.20, 0.04, 0.22), SKIN, 994 + side, Vector3(0, 0, 0), 0.02)          # webbed foot
		for i in 3:
			var x := (float(i) - 1.0) * 0.075
			limb(s, Vector3(x, -0.28, -0.17), Vector3(x * 1.3, -0.29, -0.24), 0.025, 0.0, 4, CLAW, 996 + i + 3 * side, 0.0, 0.03)
		return s

	## A tail with a tall paddle fin (the swarmer's spade, as a swimmer's tail).
	func _tail_soup() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(1011, 0.07)
		limb(s, Vector3(0, 0.0, 0.0), Vector3(0, -0.06, 0.20), 0.07, 0.05, 5, SKIN, 1012)
		limb(s, Vector3(0, -0.06, 0.20), Vector3(0, -0.02, 0.40), 0.05, 0.03, 5, SKIN, 1013)
		blob(s, Vector3(0, 0.0, 0.30), Vector3(0.025, 0.10, 0.14), GILL, 1014, 0.1, 0, Vector3(-10, 0, 0))              # fin
		return s

	## A goo ball: a glowing lumpy sphere with a hot highlight and a drip.
	func _ball_soup(r: float, seed_value: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(seed_value, 0.05)
		blob(s, Vector3.ZERO, Vector3.ONE * r, glow(goo), seed_value + 1, 0.18, 1)
		blob(s, Vector3(-r * 0.35, r * 0.4, -r * 0.4), Vector3.ONE * r * 0.35, glow(GooImpBlockoutsUtil.hot(goo)), seed_value + 2, 0.1)
		limb(s, Vector3(r * 0.2, -r * 0.8, 0), Vector3(r * 0.3, -r * 1.7, 0.0), r * 0.25, r * 0.08, 4, glow(goo), seed_value + 3)
		return s

	# ------------------------------------------------------------------ animation

	## The walk (active walk, MonsterModel.gait_k): a wet waddle. Its belly rolls from foot to foot, it pitches forward,
	## the gills flutter and the tail swings with each step, the hands bob with the ball. The war cry (cry_k): both arms
	## up (the ball held high), the head back.
	func apply_idle(t: float, speed: float = 0.0) -> void:
		if _downed:
			return
		var walk := clampf(speed / 5.0, 0.0, 1.0)
		var g := gait_k(walk)
		var cr := cry_k()
		var breath := sin(t * 3.0)
		var stride := sin(t * 17.0)
		var wob := sin(t * 8.5)
		var w := wind_e()
		var sw := _swing
		var body := parts["body"] as MeshInstance3D
		body.position = Vector3(wob * 0.03 * g, BODY_Y + breath * 0.012 + absf(stride) * 0.06 * walk - 0.04 * w - 0.03 * g + 0.06 * cr, 0.0)
		body.rotation = Vector3(-0.22 * w + 0.45 * sw - 0.12 * walk - 0.14 * g + 0.20 * cr, 0.35 * w - 0.45 * sw + wob * 0.08 * g,
				sin(t * 2.1) * 0.03 + wob * 0.15 * g)
		(parts["head"] as MeshInstance3D).rotation = Vector3(0.10 * w - 0.10 * sw + sin(t * 1.8) * 0.04 + absf(stride) * 0.10 * g + 0.12 * g + 0.40 * cr,
				-0.25 * w + 0.3 * sw, -wob * 0.12 * g)
		(parts["leg_l"] as MeshInstance3D).rotation.x = stride * 0.9 * walk - 0.35 * w + 0.3 * sw
		(parts["leg_r"] as MeshInstance3D).rotation.x = -stride * 0.9 * walk + 0.30 * w - 0.4 * sw
		var flap := sin(t * 4.0) * 0.12 + stride * 0.15 * g
		(parts["gill_l"] as MeshInstance3D).rotation = Vector3(0.0, -flap - 0.2 * w - 0.3 * cr, 0.0)
		(parts["gill_r"] as MeshInstance3D).rotation = Vector3(0.0, flap + 0.2 * w + 0.3 * cr, 0.0)
		(parts["tail"] as MeshInstance3D).rotation = Vector3(0.2 * w, sin(t * 4.0) * 0.3 + wob * 0.35 * g, 0.0)
		_pose_arms(t, walk, w, sw)
		if g > 0.0 or cr > 0.0:
			for s: int in [-1, 1]:
				var arm := parts["arm_l" if s < 0 else "arm_r"] as MeshInstance3D
				arm.rotation.x = lerpf(arm.rotation.x + stride * 0.15 * g * float(s), -2.6, cr)   # (a small swing: the hands hold the ball)
				arm.rotation.z += 0.30 * cr * float(s)

	## The arms: the left one out for balance (forward on the throw), the right one holding the ball: low at rest, drawn
	## back over the head on the windup, flung forward on the swing.
	func _pose_arms(t: float, walk: float, w: float, sw: float) -> void:
		var claw := sin(t * 3.6) * 0.1
		(parts["arm_l"] as MeshInstance3D).rotation = Vector3(-0.6 + claw + 1.2 * w - 1.0 * sw, 0.0, -0.45 - 0.35 * w)
		var a := lerpf(-0.55 + claw, -2.7, w)
		a = lerpf(a, 1.15, sw)
		(parts["arm_r"] as MeshInstance3D).rotation = Vector3(a, 0.0, 0.40 - 0.25 * w)

	func _slump() -> void:
		(parts["body"] as MeshInstance3D).rotation = Vector3(-0.3, 0.0, 0.0)
		(parts["head"] as MeshInstance3D).rotation = Vector3(-0.4, 0.0, 0.0)
		(parts["arm_l"] as MeshInstance3D).rotation = Vector3(0.1, 0.0, -0.6)
		(parts["arm_r"] as MeshInstance3D).rotation = Vector3(0.1, 0.0, 0.6)


## (static helpers the inner classes can reach without a class_name)
class GooImpBlockoutsUtil:
	static func hot(c: Color) -> Color:
		return c.lerp(Color(1, 1, 1), 0.45)

	static func deep(c: Color) -> Color:
		return Color(c.r * 0.55, c.g * 0.55, c.b * 0.55)


# =============================================================================== sac

## A glowing goo bladder grown on its back, veined, a spout on top drooling.
class SacImp extends ImpBody:
	func _build_carry() -> void:
		_add_part("sac", _sac_soup(), parts["body"] as Node3D, Vector3(0, 0.30, 0.20))

	func _sac_soup() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(1101, 0.06)
		blob(s, Vector3(0, 0.05, 0.10), Vector3(0.30, 0.33, 0.28), glow(goo), 1102, 0.12, 1)
		blob(s, Vector3(-0.10, 0.18, 0.02), Vector3(0.10, 0.08, 0.08), glow(GooImpBlockoutsUtil.hot(goo)), 1103, 0.1)    # shine
		# skin straps and veins over it, so it reads as part of the imp (not a balloon)
		for i in 3:
			var a := -0.9 + 0.9 * float(i)
			var top := Vector3(sin(a) * 0.08, 0.37, 0.08)
			var mid := Vector3(sin(a) * 0.31, 0.06, 0.12 + cos(a) * 0.12)
			var bot := Vector3(sin(a) * 0.18, -0.24, 0.06)
			limb(s, top, mid, 0.04, 0.035, 4, SKIN_DARK, 1104 + i)
			limb(s, mid, bot, 0.035, 0.03, 4, SKIN_DARK, 1108 + i)
		blob(s, Vector3(0, -0.22, 0.0), Vector3(0.22, 0.08, 0.16), SKIN, 1112, 0.12)                     # where it grows from
		limb(s, Vector3(0, 0.30, 0.06), Vector3(0.02, 0.48, 0.02), 0.07, 0.05, 6, SKIN_DARK, 1113)        # spout
		limb(s, Vector3(0.02, 0.47, 0.02), Vector3(0.02, 0.52, 0.0), 0.06, 0.06, 6, glow(goo), 1114)
		limb(s, Vector3(0.05, 0.49, -0.02), Vector3(0.08, 0.36, -0.06), 0.025, 0.01, 4, glow(goo), 1115)  # drip off the spout
		return s


# =============================================================================== drip

## The imp dripping with goo: a goo cap down its head, drips off the chin, elbows and belly, a puddle at its feet, the ball
## welling up in both hands in front of its belly.
class DripImp extends ImpBody:
	func _build_carry() -> void:
		var head := parts["head"] as Node3D
		_add_part("cap", _cap_soup(), head, Vector3.ZERO)
		_add_part("coat", _coat_soup(), parts["body"] as Node3D, Vector3.ZERO)
		_add_part("puddle", _puddle_soup(), self, Vector3(0, 0.0, 0.02))
		for s: int in [-1, 1]:
			var side := "l" if s < 0 else "r"
			_add_part("drips_" + side, _arm_drips(), parts["arm_" + side] as Node3D, Vector3.ZERO)

	func _cap_soup() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(1201, 0.06)
		var dg := GooImpBlockoutsUtil.deep(goo)
		blob(s, Vector3(0, 0.12, 0.04), Vector3(0.27, 0.11, 0.22), glow(goo), 1202, 0.15, 1)
		blob(s, Vector3(0.06, 0.20, 0.02), Vector3(0.10, 0.06, 0.08), glow(GooImpBlockoutsUtil.hot(goo)), 1203, 0.1)
		for i in 6:
			var a := -2.4 + 0.95 * float(i)
			var x := sin(a) * 0.28
			var z := -cos(a) * 0.22 + 0.04
			var ln := 0.10 + 0.06 * float((i * 5) % 3)
			limb(s, Vector3(x, 0.08, z), Vector3(x * 1.05, 0.08 - ln, z * 1.05), 0.05, 0.02, 4, glow(goo), 1204 + i)
			blob(s, Vector3(x * 1.05, 0.06 - ln, z * 1.05), Vector3.ONE * 0.028, glow(goo), 1212 + i, 0.1)
		blob(s, Vector3(0, 0.02, 0.20), Vector3(0.18, 0.12, 0.08), dg, 1220, 0.15)
		limb(s, Vector3(0.02, -0.15, -0.20), Vector3(0.03, -0.34, -0.18), 0.04, 0.015, 4, glow(goo), 1221)       # chin drip
		return s

	func _coat_soup() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(1231, 0.06)
		var dg := GooImpBlockoutsUtil.deep(goo)
		blob(s, Vector3(0, 0.27, 0.08), Vector3(0.24, 0.12, 0.18), dg, 1232, 0.15)                              # shoulders slicked
		for i in 5:
			var a := -1.3 + 0.65 * float(i)
			var p := Vector3(sin(a) * 0.25, 0.05, -cos(a) * 0.20)
			limb(s, p + Vector3(0, 0.12, 0), p * 1.06 + Vector3(0, -0.08 - 0.05 * float(i % 2), 0), 0.045, 0.02, 4, glow(goo), 1233 + i)
		limb(s, Vector3(0.02, 0.25, 0.22), Vector3(0.02, -0.02, 0.30), 0.06, 0.03, 4, glow(goo), 1240)           # down the back
		return s

	func _arm_drips() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(1251, 0.06)
		limb(s, Vector3(0, -0.12, 0.05), Vector3(0, -0.24, 0.07), 0.035, 0.012, 4, glow(goo), 1252)
		blob(s, Vector3(0, -0.25, 0.07), Vector3.ONE * 0.025, glow(goo), 1253, 0.1)
		return s

	func _puddle_soup() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(1261, 0.05)
		var dg := GooImpBlockoutsUtil.deep(goo)
		blob(s, Vector3(0, 0.01, 0), Vector3(0.40, 0.025, 0.34), dg, 1262, 0.12, 1)
		for i in 5:
			var a := TAU * float(i) / 5.0 + 0.3
			blob(s, Vector3(cos(a) * 0.30, 0.02, sin(a) * 0.26), Vector3(0.10, 0.025, 0.08), glow(goo), 1263 + i, 0.15)
		return s

	## Both hands cupped in front of the belly with the ball between them; the windup takes it back in the right.
	func _pose_arms(t: float, walk: float, w: float, sw: float) -> void:
		var bob := sin(t * 3.0) * 0.05
		var al := lerpf(0.85 + bob, -0.4, w)
		(parts["arm_l"] as MeshInstance3D).rotation = Vector3(al - 0.8 * sw, 0.0, lerpf(0.55, -0.5, w))
		var a := lerpf(0.85 + bob, -2.7, w)
		a = lerpf(a, 1.15, sw)
		(parts["arm_r"] as MeshInstance3D).rotation = Vector3(a, 0.0, lerpf(-0.55, 0.15, w))


# =============================================================================== ladle

## A yellow mop bucket of goo on its left arm, a long ladle in its right; the ball sits in the ladle's bowl.
class LadleImp extends ImpBody:
	const BUCKET := Color(0.98, 0.80, 0.16)
	const BUCKET_DARK := Color(0.62, 0.48, 0.10)
	const STEEL := Color(0.70, 0.73, 0.76)
	const STEEL_DARK := Color(0.40, 0.42, 0.46)
	const WOOD := Color(0.44, 0.28, 0.16)
	const LADLE_LEN := 0.92

	func _build() -> void:
		super._build()
		(parts["ball"] as Node3D).visible = false

	func ball_point() -> Vector3:
		return (parts["ladle"] as Node3D).global_transform * Vector3(0, -0.02, -LADLE_LEN)

	func _build_carry() -> void:
		_add_part("bucket", _bucket_soup(), parts["arm_l"] as Node3D, Vector3(-0.02, -0.40, -0.02))
		_add_part("ladle", _ladle_soup(), parts["arm_r"] as Node3D, HAND)

	## A small yellow mop bucket on a bail handle, goo to the brim and slopping over.
	func _bucket_soup() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(1301, 0.05)
		s.merge(LowPoly.cylinder(0.13, 0.17, 0.26, 8, BUCKET, 1302, 0.0, 1, 0.05), LowPoly.at(Vector3(0, -0.20, 0)))
		s.merge(LowPoly.cylinder(0.175, 0.175, 0.03, 8, BUCKET_DARK, 1303, 0.0, 1, 0.03), LowPoly.at(Vector3(0, -0.07, 0)))
		s.merge(LowPoly.cylinder(0.16, 0.16, 0.03, 8, glow(goo), 1304, 0.0, 1, 0.03), LowPoly.at(Vector3(0, -0.065, 0)))
		blob(s, Vector3(0.05, -0.05, -0.03), Vector3(0.08, 0.04, 0.07), glow(goo), 1305, 0.15)
		limb(s, Vector3(0.15, -0.08, 0.0), Vector3(0.16, -0.22, -0.02), 0.035, 0.012, 4, glow(goo), 1306)       # slopping over
		limb(s, Vector3(-0.16, -0.07, 0), Vector3(0.0, 0.03, 0), 0.015, 0.015, 4, STEEL_DARK, 1307, 0.0, 0.02)  # bail
		limb(s, Vector3(0.0, 0.03, 0), Vector3(0.16, -0.07, 0), 0.015, 0.015, 4, STEEL_DARK, 1308, 0.0, 0.02)
		return s

	## A long soup ladle along local -Z from the grip: a wooden grip, a steel shaft, a deep bowl of goo at the end.
	func _ladle_soup() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(1311, 0.05)
		var tip := -LADLE_LEN
		limb(s, Vector3(0, 0, 0.16), Vector3(0, 0, -0.06), 0.04, 0.04, 5, WOOD, 1312)
		limb(s, Vector3(0, 0, -0.06), Vector3(0, -0.03, tip + 0.1), 0.026, 0.026, 4, STEEL, 1313, 0.0, 0.03)
		s.merge(LowPoly.cylinder(0.08, 0.15, 0.12, 8, STEEL_DARK, 1314, 0.0, 1, 0.03), LowPoly.at(Vector3(0, -0.08, tip)))
		blob(s, Vector3(0, -0.01, tip), Vector3(0.15, 0.08, 0.15), glow(goo), 1315, 0.15, 1)
		blob(s, Vector3(-0.04, 0.05, tip - 0.03), Vector3(0.06, 0.035, 0.06), glow(GooImpBlockoutsUtil.hot(goo)), 1316, 0.1)
		limb(s, Vector3(0.10, -0.06, tip - 0.02), Vector3(0.11, -0.22, tip - 0.02), 0.03, 0.01, 4, glow(goo), 1317)
		return s

	## The bucket hangs on the left arm; the ladle rests on the right shoulder, the bowl up behind the head (a long
	## diagonal from the game camera); the windup drops it further back, the swing flings it over and forward.
	func _pose_arms(t: float, walk: float, w: float, sw: float) -> void:
		var bob := sin(t * 3.6) * 0.05
		(parts["arm_l"] as MeshInstance3D).rotation = Vector3(-0.15 + bob + 0.4 * w, 0.0, -0.30)
		(parts["bucket"] as MeshInstance3D).rotation = Vector3(0.15 - 0.4 * w, 0.0, 0.30)
		var a := lerpf(-1.9 + bob, -2.6, w)
		a = lerpf(a, 0.9, sw)
		(parts["arm_r"] as MeshInstance3D).rotation = Vector3(a, 0.0, 0.30 - 0.1 * w)
		# the ladle's own pitch in world terms (from straight forward, up positive)
		var th := lerpf(2.45, 3.3, w)
		th = lerpf(th, 0.25, sw)
		# rolled half a turn about its shaft while it is carried back, so the bowl stays up (the goo stays in)
		(parts["ladle"] as MeshInstance3D).rotation = Vector3(th - a, 0.0, PI * (1.0 - sw))
