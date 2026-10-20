extends RefCounted
## Enemy healer BLOCKOUTS (docs/design/enemy-healer-options.md): four rough faceted models for the read tests in
## healer_lab.gd. Lab only: no Monster kind uses them, MonsterModels does not make them, nothing declares gameplay state.
## They are in ZFightModels as "healer/<kind>".
##
##   const HealerBlockouts := preload("res://scripts/art/lowpoly/monsters/healer_blockouts.gd")
##   var m: MonsterModel = HealerBlockouts.build("cooler")
##   m.set_heal(1.0)                    # the heal pose (glow flares); 0 = rest
##   m.heal_from()                      # world point the heal effect leaves from (jug tap, IV bag, iris, battery)
##
## The family look: every healer's glow (eyes, fluid, lens, charge) is the ENEMY CHARTREUSE (BILE), never the Heal spell's
## mint (SpellBook "heal" 0.35, 0.95, 0.5) or the Vines leaf green (0.45, 0.78, 0.22). No red cross anywhere.
## Faces local -Z, +X is its right, origin at the feet, built at world size (MODEL_SCALE 1).
##
##   cooler    Water Cooler: a squat, broad facilities demon with the office water cooler strapped to its back; the
##             upside-down jug glows. About 2.5 to the jug top, 1.1 across.
##   iv_nurse  Company Nurse: a tall gangly ghoul in maroon scrubs, cap and mask, pushing a wheeled IV stand; the bag
##             glows at 3.0. About 2.3 to the cap.
##   eye       Night Nurse: a floating eyeball in a paper nurse's cap, tendrils hanging; the iris glows. Orb at 2.45
##             (radius 0.7), cap top 3.5. Its shadow disc is a separate part (shadow) on the floor.
##   orderly   Orderly: a brute-sized orderly in hospital whites behind a gurney with a car battery and jumper cables.
##             About 2.6 tall; the gurney runs 1.9 out in front.

const KINDS: Array[String] = ["cooler", "iv_nurse", "eye", "orderly"]
const NAMES := {"cooler": "Water Cooler", "iv_nurse": "Company Nurse", "eye": "Night Nurse", "orderly": "Orderly"}

## The enemy chartreuse: a sickly yellow-green, yellower and paler than Vines, far from Heal's mint.
const BILE := Color(0.80, 1.0, 0.16)
const BILE_HOT := Color(0.93, 1.0, 0.55)
const BILE_DEEP := Color(0.52, 0.72, 0.06)


static func build(kind: String) -> MonsterModel:
	match kind:
		"cooler":
			return CoolerModel.new()
		"iv_nurse":
			return IvNurseModel.new()
		"eye":
			return EyeModel.new()
		"orderly":
			return OrderlyModel.new()
	return null


## Shared: the heal pose value and its glow flare.
class HealerModel extends MonsterModel:
	var heal_k := 0.0

	func set_heal(k: float) -> void:
		heal_k = clampf(k, 0.0, 1.0)
		if not _downed:
			_mat.set_shader_parameter("glow_gain", GLOW_GAIN * (1.0 + 0.9 * heal_k))
		_refresh()

	func pose_preview(kind: String, k: float = 1.0) -> void:
		heal_k = 0.0
		if kind == "heal":
			set_heal(k)
			apply_idle(0.6, 0.0)
			return
		set_heal(0.0)
		super.pose_preview(kind, k)

	func heal_from() -> Vector3:
		return global_position + Vector3.UP * 2.0


# =============================================================================== cooler

class CoolerModel extends HealerModel:
	const SKIN := Color(0.62, 0.34, 0.20)
	const SKIN_DARK := Color(0.46, 0.24, 0.14)
	const HORN := Color(0.90, 0.84, 0.66)
	const POLO := Color(0.20, 0.18, 0.19)
	const POLO_DARK := Color(0.13, 0.11, 0.12)
	const CARD := Color(0.95, 0.94, 0.88)
	const LANYARD := Color(0.86, 0.80, 0.30)
	const PLASTIC := Color(0.90, 0.89, 0.84)
	const PLASTIC_DARK := Color(0.64, 0.63, 0.60)
	const STRAP := Color(0.12, 0.10, 0.10)
	const BUCKLE := Color(0.72, 0.70, 0.66)
	const TAP_HOT := Color(0.95, 0.42, 0.12)
	const VOID := Color(0.08, 0.05, 0.05)
	const HIP_Y := 0.62
	const MODEL_SCALE := 1.25

	func _init() -> void:
		_setup_model("CoolerBlockout", MODEL_SCALE)
		monster_kind = "cooler"
		ui_height = 2.6 * MODEL_SCALE
		_build()
		apply_idle(0.0)

	func heal_from() -> Vector3:
		return (parts["jug"] as Node3D).global_transform * Vector3(0, 0.05, 0)

	func _build() -> void:
		var body := _add_part("body", _body(), self, Vector3(0, HIP_Y, 0))
		_add_part("head", _head(), body, Vector3(0, 0.80, -0.30))
		var cooler := _add_part("cooler", _cooler(), body, Vector3(0, 0.62, 0.50))
		_add_part("jug", _jug(), cooler, Vector3(0, 0.98, 0))
		for s: int in [-1, 1]:
			var side := "l" if s < 0 else "r"
			var arm := _add_part("arm_" + side, _arm(s), body, Vector3(0.50 * s, 0.66, -0.06))
			arm.rotation = Vector3(0.0, 0.0, 0.15 * s)
			_add_part("leg_" + side, _leg(s), self, Vector3(0.24 * s, HIP_Y, 0.0))

	func _body() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3101, 0.07)
		blob(s, Vector3(0, 0.36, -0.06), Vector3(0.52, 0.46, 0.44), POLO, 3102, 0.10, 1)            # belly in the polo
		blob(s, Vector3(0, 0.66, -0.02), Vector3(0.56, 0.20, 0.38), POLO_DARK, 3103, 0.12)           # shoulders
		blob(s, Vector3(0, 0.02, 0.0), Vector3(0.40, 0.14, 0.32), POLO_DARK, 3104, 0.12)             # seat
		slab(s, Vector3(0, 0.72, -0.30), Vector3(0.30, 0.08, 0.10), POLO, 3105, Vector3(20, 0, 0), 0.01)   # collar
		# shoulder straps of the cooler harness, over the front
		for x: int in [-1, 1]:
			slab(s, Vector3(0.24 * x, 0.56, -0.40), Vector3(0.09, 0.42, 0.05), STRAP, 3106 + x, Vector3(-18, 0, 0), 0.0)
			slab(s, Vector3(0.24 * x, 0.42, -0.475), Vector3(0.11, 0.07, 0.03), BUCKLE, 3109 + x, Vector3(-18, 0, 0), 0.0, 0.02)
		# lanyard and ID card (the company's)
		limb(s, Vector3(-0.10, 0.70, -0.33), Vector3(0.0, 0.40, -0.50), 0.018, 0.018, 4, LANYARD, 3112, 0.0, 0.03)
		limb(s, Vector3(0.10, 0.70, -0.33), Vector3(0.0, 0.40, -0.50), 0.018, 0.018, 4, LANYARD, 3113, 0.0, 0.03)
		slab(s, Vector3(0, 0.31, -0.52), Vector3(0.16, 0.20, 0.03), CARD, 3114, Vector3(-14, 0, 0), 0.0, 0.02)
		return s

	func _head() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3121, 0.07)
		blob(s, Vector3(0, 0.10, 0), Vector3(0.24, 0.21, 0.24), SKIN, 3122, 0.12, 1)
		blob(s, Vector3(0, 0.0, -0.12), Vector3(0.20, 0.10, 0.14), SKIN_DARK, 3123, 0.12)                # heavy jaw
		slab(s, Vector3(0, 0.15, -0.20), Vector3(0.34, 0.06, 0.10), SKIN_DARK, 3124, Vector3(-8, 0, 0), 0.02)   # brow
		for x: int in [-1, 1]:
			slab(s, Vector3(0.085 * x, 0.085, -0.225), Vector3(0.09, 0.05, 0.03), glow(BILE), 3125 + x, Vector3(0, 0, -12 * x), 0.0, 0.0)
			limb(s, Vector3(0.16 * x, 0.24, -0.02), Vector3(0.30 * x, 0.40, 0.06), 0.06, 0.0, 5, HORN, 3127 + x, 0.0)   # stubby horns
		slab(s, Vector3(0, -0.03, -0.235), Vector3(0.18, 0.03, 0.03), VOID, 3129, Vector3.ZERO, 0.0, 0.0)    # flat mouth
		return s

	## The cooler: a white plastic cabinet with a dark panel, the hot and cold taps on its back (it faces away).
	func _cooler() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3131, 0.04)
		slab(s, Vector3(0, 0.40, 0.04), Vector3(0.62, 1.06, 0.54), PLASTIC, 3132, Vector3.ZERO, 0.01)
		slab(s, Vector3(0, 0.30, 0.325), Vector3(0.44, 0.40, 0.05), PLASTIC_DARK, 3133, Vector3.ZERO, 0.0)   # drip recess
		slab(s, Vector3(0, 0.12, 0.35), Vector3(0.40, 0.04, 0.12), PLASTIC_DARK, 3134, Vector3.ZERO, 0.0)    # drip tray
		slab(s, Vector3(-0.11, 0.44, 0.37), Vector3(0.07, 0.10, 0.08), glow(BILE), 3135, Vector3.ZERO, 0.0, 0.0)   # the cold tap
		slab(s, Vector3(0.11, 0.44, 0.37), Vector3(0.07, 0.10, 0.08), TAP_HOT, 3136, Vector3.ZERO, 0.0, 0.0)       # the hot tap
		s.merge(LowPoly.cylinder(0.25, 0.27, 0.07, 8, PLASTIC_DARK, 3137, 0.0), LowPoly.at(Vector3(0, 0.965, 0.04)))   # jug seat
		# the harness frame: two straps round the cabinet
		for y: float in [0.05, 0.70]:
			slab(s, Vector3(0, y, 0.04), Vector3(0.66, 0.08, 0.58), STRAP, 3138 + int(y * 10.0), Vector3.ZERO, 0.0)
		return s

	## The 5-gallon jug upside down, glowing: ribbed, with bubbles (hotter glow) and the neck in the seat.
	func _jug() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3141, 0.05)
		s.merge(LowPoly.cylinder(0.10, 0.10, 0.12, 8, glow(BILE_DEEP), 3142, 0.0, 1, 0.0), LowPoly.at(Vector3(0, 0.02, 0)))   # neck
		s.merge(LowPoly.cylinder(0.12, 0.31, 0.14, 10, glow(BILE), 3143, 0.0, 1, 0.03), LowPoly.at(Vector3(0, 0.15, 0)))     # shoulder
		s.merge(LowPoly.cylinder(0.31, 0.31, 0.36, 10, glow(BILE), 3144, 0.0, 2, 0.03), LowPoly.at(Vector3(0, 0.40, 0)))     # barrel
		s.merge(LowPoly.cylinder(0.33, 0.33, 0.05, 10, glow(BILE_DEEP), 3145, 0.0, 1, 0.0), LowPoly.at(Vector3(0, 0.40, 0)))  # rib
		s.merge(LowPoly.cylinder(0.31, 0.26, 0.08, 10, glow(BILE), 3146, 0.0, 1, 0.03), LowPoly.at(Vector3(0, 0.62, 0)))     # base
		for i in 4:
			var a := TAU * float(i) / 4.0 + 0.5
			blob(s, Vector3(cos(a) * 0.30, 0.26 + 0.09 * i, sin(a) * 0.30), Vector3.ONE * (0.045 + 0.01 * (i % 2)), glow(BILE_HOT), 3147 + i, 0.1)
		return s

	func _arm(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3151 + side, 0.07)
		blob(s, Vector3(0, -0.02, 0), Vector3(0.17, 0.15, 0.16), POLO_DARK, 3152 + side, 0.12)             # sleeve
		limb(s, Vector3(0, -0.06, 0), Vector3(0, -0.40, -0.06), 0.13, 0.11, 6, SKIN, 3154 + side)
		limb(s, Vector3(0, -0.40, -0.06), Vector3(0, -0.70, -0.14), 0.11, 0.12, 6, SKIN, 3156 + side)
		blob(s, Vector3(0, -0.78, -0.15), Vector3(0.14, 0.13, 0.14), SKIN_DARK, 3158 + side, 0.15)         # fist
		return s

	func _leg(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3161 + side, 0.07)
		limb(s, Vector3(0, 0.0, 0), Vector3(0, -0.32, -0.02), 0.15, 0.13, 6, POLO_DARK, 3162 + side)
		limb(s, Vector3(0, -0.32, -0.02), Vector3(0, -0.56, 0.0), 0.12, 0.11, 6, SKIN, 3164 + side)
		blob(s, Vector3(0, -0.58, -0.08), Vector3(0.14, 0.06, 0.20), SKIN_DARK, 3166 + side, 0.12)
		return s

	func apply_idle(t: float, speed: float = 0.0) -> void:
		if _downed:
			return
		var walk := clampf(speed / 3.0, 0.0, 1.0)
		var stride := sin(t * 7.0)
		var h := heal_k
		var body := parts["body"] as MeshInstance3D
		body.position.y = HIP_Y + sin(t * 2.0) * 0.01 - absf(stride) * 0.03 * walk - 0.06 * h
		body.rotation = Vector3(0.10 + 0.30 * h, stride * 0.06 * walk, 0.0)
		(parts["head"] as MeshInstance3D).rotation = Vector3(-0.20 * h, 0.0, 0.0)
		# the heal: it leans forward and grabs its harness straps, the jug tips up over its head
		for s: int in [-1, 1]:
			var side := "l" if s < 0 else "r"
			(parts["arm_" + side] as MeshInstance3D).rotation = Vector3(-0.15 * s * stride * walk - 0.9 * h, 0.0, 0.15 * s + 0.25 * s * h)
			(parts["leg_" + side] as MeshInstance3D).rotation.x = s * stride * 0.5 * walk
		(parts["jug"] as MeshInstance3D).rotation = Vector3(0.0, sin(t * 1.3) * 0.2, 0.0)

	func _slump() -> void:
		(parts["body"] as MeshInstance3D).rotation = Vector3(0.45, 0.0, 0.0)


# =============================================================================== iv nurse

class IvNurseModel extends HealerModel:
	const SKIN := Color(0.56, 0.55, 0.58)
	const SKIN_DARK := Color(0.40, 0.39, 0.43)
	const SCRUBS := Color(0.50, 0.15, 0.21)
	const SCRUBS_DARK := Color(0.36, 0.10, 0.15)
	const CAP := Color(0.92, 0.91, 0.86)
	const MASK := Color(0.84, 0.86, 0.82)
	const STEEL := Color(0.74, 0.77, 0.80)
	const STEEL_DARK := Color(0.42, 0.44, 0.48)
	const RUBBER := Color(0.10, 0.09, 0.09)
	const CLOG := Color(0.92, 0.88, 0.80)
	const HIP_Y := 1.04
	const POLE_AT := Vector3(0.52, 0.0, -0.30)
	const POLE_H := 3.0

	func _init() -> void:
		_setup_model("IvNurseBlockout", 1.0)
		monster_kind = "iv_nurse"
		ui_height = 2.4
		_build()
		apply_idle(0.0)

	func heal_from() -> Vector3:
		return (parts["stand"] as Node3D).global_transform * Vector3(0, POLE_H - 0.55, 0)

	func _build() -> void:
		var body := _add_part("body", _body(), self, Vector3(0, HIP_Y, 0))
		_add_part("head", _head(), body, Vector3(0, 0.90, -0.10))
		for s: int in [-1, 1]:
			var side := "l" if s < 0 else "r"
			_add_part("arm_" + side, _arm(s), body, Vector3(0.24 * s, 0.70, -0.04))
			_add_part("leg_" + side, _leg(s), self, Vector3(0.11 * s, HIP_Y, 0.0))
		_add_part("stand", _stand(), self, POLE_AT)

	## A long thin torso in the scrub top, a stoop.
	func _body() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3201, 0.07)
		limb(s, Vector3(0, -0.02, 0), Vector3(0, 0.72, -0.06), 0.17, 0.20, 6, SCRUBS, 3202, 0.02)
		blob(s, Vector3(0, 0.70, -0.05), Vector3(0.26, 0.10, 0.15), SCRUBS_DARK, 3203, 0.12)          # shoulders
		wedge(s, Vector3(0, 0.66, -0.20), Vector2(0.16, 0.04), Vector2(0.03, 0.04), 0.14, SKIN, 3204, Vector3(-8, 0, 0))   # V neck
		slab(s, Vector3(0.09, 0.42, -0.215), Vector3(0.10, 0.09, 0.03), SCRUBS_DARK, 3205, Vector3.ZERO, 0.0)   # pocket
		limb(s, Vector3(0.07, 0.45, -0.24), Vector3(0.07, 0.56, -0.24), 0.012, 0.012, 3, STEEL, 3206, 0.0, 0.0)   # pen
		limb(s, Vector3(0, 0.71, -0.06), Vector3(0, 0.84, -0.09), 0.06, 0.055, 5, SKIN, 3207)            # long neck
		return s

	## A narrow, long skull: the white cap, a surgical mask, sunken chartreuse eyes.
	func _head() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3211, 0.06)
		blob(s, Vector3(0, 0.08, 0), Vector3(0.15, 0.20, 0.17), SKIN, 3212, 0.12, 1)
		wedge(s, Vector3(0, -0.04, -0.12), Vector2(0.20, 0.10), Vector2(0.26, 0.10), 0.16, MASK, 3213, Vector3(-6, 0, 0), 0.01)   # mask
		for x: int in [-1, 1]:
			slab(s, Vector3(0.06 * x, 0.09, -0.155), Vector3(0.07, 0.05, 0.03), glow(BILE), 3214 + x, Vector3(0, 0, 10 * x), 0.0, 0.0)
			limb(s, Vector3(0.13 * x, -0.02, -0.08), Vector3(0.16 * x, 0.06, 0.02), 0.01, 0.01, 3, MASK, 3216 + x, 0.0, 0.0)   # ear loops
		blob(s, Vector3(0, 0.23, 0.02), Vector3(0.19, 0.10, 0.20), CAP, 3218, 0.14)                    # bouffant cap
		return s

	func _arm(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3221 + side, 0.07)
		blob(s, Vector3(0, -0.04, 0), Vector3(0.09, 0.11, 0.09), SCRUBS, 3222 + side, 0.12)
		limb(s, Vector3(0, -0.04, 0), Vector3(0, -0.40, 0), 0.055, 0.05, 5, SKIN, 3224 + side)
		limb(s, Vector3(0, -0.40, 0), Vector3(0, -0.78, -0.04), 0.05, 0.042, 5, SKIN, 3226 + side)
		blob(s, Vector3(0, -0.84, -0.05), Vector3(0.07, 0.09, 0.06), SKIN_DARK, 3228 + side, 0.15)     # long hand
		return s

	func _leg(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3231 + side, 0.07)
		limb(s, Vector3(0, 0.0, 0), Vector3(0, -0.50, 0.0), 0.085, 0.075, 5, SCRUBS, 3232 + side)
		limb(s, Vector3(0, -0.50, 0.0), Vector3(0, -0.96, 0.0), 0.075, 0.07, 5, SCRUBS_DARK, 3234 + side)
		wedge(s, Vector3(0, -0.99, -0.05), Vector2(0.14, 0.26), Vector2(0.12, 0.20), 0.08, CLOG, 3236 + side, Vector3.ZERO, 0.01)
		return s

	## The IV stand: a five-caster base, a steel pole, a hook bar with the glowing bag, a drip chamber and coiled line.
	func _stand() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3241, 0.04)
		for i in 5:
			var a := TAU * float(i) / 5.0 + 0.3
			var tip := Vector3(cos(a) * 0.34, 0.09, sin(a) * 0.34)
			limb(s, Vector3(0, 0.13, 0), tip, 0.03, 0.025, 4, STEEL_DARK, 3242 + i, 0.0, 0.0)
			blob(s, tip + Vector3(0, -0.045, 0), Vector3(0.045, 0.04, 0.045), RUBBER, 3247 + i, 0.1)
		s.merge(LowPoly.cylinder(0.05, 0.05, 0.08, 6, STEEL_DARK, 3252, 0.0), LowPoly.at(Vector3(0, 0.13, 0)))
		limb(s, Vector3(0, 0.15, 0), Vector3(0, POLE_H, 0), 0.032, 0.026, 6, STEEL, 3253, 0.0, 0.0)
		slab(s, Vector3(0, POLE_H - 0.06, 0), Vector3(0.62, 0.035, 0.035), STEEL, 3254, Vector3.ZERO, 0.0, 0.0)   # hook bar
		for x: int in [-1, 1]:
			limb(s, Vector3(0.28 * x, POLE_H - 0.08, 0), Vector3(0.28 * x, POLE_H - 0.17, 0), 0.012, 0.012, 3, STEEL, 3255 + x, 0.0, 0.0)
		# the bag (big, so it reads) and a smaller second bag
		blob(s, Vector3(-0.28, POLE_H - 0.43, 0), Vector3(0.20, 0.27, 0.08), glow(BILE), 3257, 0.10, 0, Vector3.ZERO, 0.03)
		slab(s, Vector3(-0.28, POLE_H - 0.43, -0.085), Vector3(0.16, 0.12, 0.012), CAP, 3258, Vector3.ZERO, 0.0, 0.0)   # label
		blob(s, Vector3(0.28, POLE_H - 0.36, 0), Vector3(0.13, 0.18, 0.06), glow(BILE_DEEP), 3259, 0.10, 0, Vector3.ZERO, 0.03)
		s.merge(LowPoly.cylinder(0.035, 0.035, 0.12, 6, glow(BILE_HOT), 3260, 0.0, 1, 0.0), LowPoly.at(Vector3(-0.28, POLE_H - 0.80, 0)))   # drip chamber
		# the line, coiled loosely round the pole at rest
		var prev := Vector3(-0.28, POLE_H - 0.87, 0)
		for i in 10:
			var a2 := float(i) * 1.1
			var p := Vector3(cos(a2) * 0.12, POLE_H - 1.05 - 0.10 * i, sin(a2) * 0.12)
			limb(s, prev, p, 0.014, 0.014, 3, glow(BILE_DEEP), 3261 + i, 0.0, 0.0)
			prev = p
		return s

	func apply_idle(t: float, speed: float = 0.0) -> void:
		if _downed:
			return
		var walk := clampf(speed / 3.6, 0.0, 1.0)
		var stride := sin(t * 6.5)
		var h := heal_k
		var body := parts["body"] as MeshInstance3D
		body.position.y = HIP_Y + sin(t * 1.8) * 0.012 - absf(stride) * 0.03 * walk
		body.rotation = Vector3(0.22 - 0.10 * h, -0.20 * h, 0.0)    # the stoop; it straightens to hang the line
		(parts["head"] as MeshInstance3D).rotation = Vector3(-0.10 + 0.04 * sin(t * 1.2), 0.15 * h, 0.0)
		# right hand on the pole, left hand free (lifts the line out toward the patient while healing)
		aim_limb(parts["arm_r"] as MeshInstance3D, Vector3(0.44, 0.38, -0.36), 0.84)
		var arm_l := parts["arm_l"] as MeshInstance3D
		arm_l.rotation = Vector3(-stride * 0.4 * walk - 1.6 * h, 0.0, -0.10 - 0.50 * h)
		arm_l.scale = Vector3.ONE
		(parts["leg_l"] as MeshInstance3D).rotation.x = stride * 0.6 * walk
		(parts["leg_r"] as MeshInstance3D).rotation.x = -stride * 0.6 * walk

	func _slump() -> void:
		(parts["body"] as MeshInstance3D).rotation = Vector3(0.50, 0.0, 0.0)


# =============================================================================== eye

class EyeModel extends HealerModel:
	const SCLERA := Color(0.93, 0.89, 0.80)
	const SCLERA_DARK := Color(0.78, 0.70, 0.62)
	const VEIN := Color(0.70, 0.18, 0.18)
	const FLESH := Color(0.42, 0.13, 0.18)
	const FLESH_DARK := Color(0.28, 0.08, 0.12)
	const PUPIL := Color(0.05, 0.03, 0.04)
	const CAP := Color(0.95, 0.94, 0.89)
	const CAP_BAND := Color(0.20, 0.17, 0.18)
	const ORB_Y := 2.45
	const ORB_R := 0.70

	func _init() -> void:
		_setup_model("EyeBlockout", 1.0)
		monster_kind = "eye"
		ui_height = 3.2
		_build()
		apply_idle(0.0)

	func heal_from() -> Vector3:
		return (parts["orb"] as Node3D).global_transform * Vector3(0, -0.05, -ORB_R)

	## World points of the tendril tips (where the tethers leave from in the lab mock).
	func tendril_tips() -> Array[Vector3]:
		var out: Array[Vector3] = []
		var orb := parts["orb"] as Node3D
		for i in 5:
			out.append(orb.global_transform * _tip(i))
		return out

	func _tip(i: int) -> Vector3:
		var a := TAU * float(i) / 5.0 + 0.6
		return Vector3(cos(a) * 0.50, -1.40 + 0.12 * float(i % 2), sin(a) * 0.50 + 0.10)

	func _build() -> void:
		var orb := _add_part("orb", _orb(), self, Vector3(0, ORB_Y, 0))
		_add_part("cap", _cap(), orb, Vector3(0, ORB_R * 0.78, 0.24)).scale = Vector3.ONE * 1.2
		_add_part("tendrils", _tendrils(), orb, Vector3.ZERO)
		var sh := _add_part("shadow", _shadow(), self, Vector3(0, 0.012, 0))
		sh.material_override = _shadow_mat()

	func _orb() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3301, 0.05)
		blob(s, Vector3.ZERO, Vector3.ONE * ORB_R, SCLERA, 3302, 0.05, 1)
		# the lid: a fleshy hood over the back, the orb's front and top left bare so the iris faces the camera
		blob(s, Vector3(0, 0.02, 0.24), Vector3(ORB_R * 1.04, ORB_R * 0.98, ORB_R * 0.80), FLESH, 3303, 0.10, 1)
		blob(s, Vector3(0, -0.24, 0.16), Vector3(ORB_R * 0.86, ORB_R * 0.55, ORB_R * 0.82), FLESH_DARK, 3304, 0.12)
		# the iris (glowing chartreuse) and the pupil, looking forward and UP (at the crew, and at the game camera)
		var n := Vector3(0, 0.62, -0.78).normalized()
		var look := Transform3D(Basis(Quaternion(Vector3.UP, n)), n * ORB_R * 0.92)
		s.merge(LowPoly.cylinder(0.38, 0.35, 0.07, 10, glow(BILE), 3305, 0.0, 1, 0.02), look)
		s.merge(LowPoly.cylinder(0.15, 0.14, 0.05, 8, PUPIL, 3306, 0.0, 1, 0.0), look * LowPoly.at(Vector3(0, 0.035, 0)))
		# veins on the sclera, round the iris
		for i in 5:
			var a := TAU * float(i) / 5.0 + 0.3
			var side := Vector3(cos(a), sin(a) * 0.8, 0.0)
			var p0 := (n * 0.55 + side * 0.80).normalized() * ORB_R * 1.0
			var p1 := (n * 0.85 + side * 0.45).normalized() * ORB_R * 1.0
			limb(s, p0, p1, 0.018, 0.008, 3, VEIN, 3307 + i, 0.0, 0.0)
		return s

	## A folded paper nurse's cap with a dark band (no cross: the emblem is protected).
	func _cap() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3321, 0.03)
		wedge(s, Vector3(0, 0.12, 0), Vector2(0.62, 0.42), Vector2(0.72, 0.18), 0.30, CAP, 3322, Vector3(-12, 0, 0), 0.0)
		slab(s, Vector3(0, 0.05, -0.02), Vector3(0.66, 0.06, 0.46), CAP_BAND, 3323, Vector3(-12, 0, 0), 0.0)
		wedge(s, Vector3(0, 0.32, 0.06), Vector2(0.70, 0.18), Vector2(0.50, 0.06), 0.12, CAP, 3324, Vector3(-12, 0, 0), 0.0)
		return s

	## Five tapered tendrils hanging from under the orb, glowing tips.
	func _tendrils() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3331, 0.06)
		for i in 5:
			var tip := _tip(i)
			var root := Vector3(tip.x * 0.55, -0.50, tip.z * 0.6 + 0.05)
			var mid := Vector3(tip.x * 1.15, -0.98, tip.z * 1.1)
			limb(s, root, mid, 0.075, 0.05, 5, FLESH, 3332 + i)
			limb(s, mid, tip, 0.05, 0.03, 5, FLESH_DARK, 3337 + i)
			blob(s, tip, Vector3.ONE * 0.05, glow(BILE), 3342 + i, 0.1)
		return s

	func _shadow() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3351, 0.0)
		s.merge(LowPoly.cylinder(0.76, 0.76, 0.004, 12, Color(0, 0, 0), 3352, 0.0, 1, 0.0))
		return s

	func _shadow_mat() -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0, 0, 0, 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		return m

	func apply_idle(t: float, _speed: float = 0.0) -> void:
		if _downed:
			return
		var h := heal_k
		var orb := parts["orb"] as MeshInstance3D
		orb.position.y = ORB_Y + sin(t * 1.6) * 0.08 + 0.10 * h
		orb.rotation = Vector3(0.10 * h, 0.0, sin(t * 0.9) * 0.05)
		# the tendrils spread out to the patients while healing
		(parts["tendrils"] as MeshInstance3D).scale = Vector3(1.0 + 0.45 * h, 1.0 - 0.10 * h, 1.0 + 0.45 * h)
		(parts["shadow"] as MeshInstance3D).position = Vector3(orb.position.x, 0.012, orb.position.z)

	func _slump() -> void:
		(parts["orb"] as MeshInstance3D).position.y = ORB_R


# =============================================================================== orderly

class OrderlyModel extends HealerModel:
	const SKIN := Color(0.40, 0.36, 0.46)
	const SKIN_DARK := Color(0.28, 0.25, 0.33)
	const WHITES := Color(0.88, 0.87, 0.82)
	const WHITES_DARK := Color(0.66, 0.66, 0.62)
	const SHOE := Color(0.14, 0.12, 0.12)
	const STEEL := Color(0.72, 0.75, 0.78)
	const STEEL_DARK := Color(0.40, 0.42, 0.46)
	const SHEET := Color(0.70, 0.72, 0.68)
	const PILLOW := Color(0.92, 0.91, 0.86)
	const RUBBER := Color(0.10, 0.09, 0.09)
	const BATTERY := Color(0.14, 0.13, 0.14)
	const CABLE := Color(0.08, 0.07, 0.07)
	const HIP_Y := 1.00
	const GURNEY_AT := Vector3(0.0, 0.0, -1.55)
	const DECK_Y := 0.86
	const G_LEN := 1.90
	const G_WID := 0.74

	func _init() -> void:
		_setup_model("OrderlyBlockout", 1.0)
		monster_kind = "orderly"
		glow_flare = 0.9
		ui_height = 2.7
		_build()
		apply_idle(0.0)

	func heal_from() -> Vector3:
		return (parts["gurney"] as Node3D).global_transform * Vector3(0.18, DECK_Y + 0.30, -0.55)

	func _build() -> void:
		var body := _add_part("body", _body(), self, Vector3(0, HIP_Y, 0))
		_add_part("head", _head(), body, Vector3(0, 1.02, -0.30))
		for s: int in [-1, 1]:
			var side := "l" if s < 0 else "r"
			_add_part("arm_" + side, _arm(s), body, Vector3(0.66 * s, 0.78, -0.08))
			_add_part("leg_" + side, _leg(s), self, Vector3(0.30 * s, HIP_Y, 0.0))
		_add_part("gurney", _gurney(), self, GURNEY_AT)

	## A barrel chest in the white tunic, a hunch, a name badge.
	func _body() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3401, 0.06)
		blob(s, Vector3(0, 0.10, 0), Vector3(0.42, 0.20, 0.32), WHITES_DARK, 3402, 0.12)                   # trousers' seat
		blob(s, Vector3(0, 0.55, -0.08), Vector3(0.66, 0.52, 0.46), WHITES, 3403, 0.10, 1)                 # chest
		blob(s, Vector3(0, 0.86, 0.02), Vector3(0.78, 0.26, 0.44), WHITES, 3404, 0.12)                    # shoulders
		blob(s, Vector3(0, 0.88, 0.22), Vector3(0.40, 0.24, 0.26), SKIN, 3405, 0.15)                      # the hump
		slab(s, Vector3(0.24, 0.62, -0.55), Vector3(0.18, 0.08, 0.03), glow(BILE), 3406, Vector3(-14, 0, 0), 0.0, 0.0)   # badge
		slab(s, Vector3(0, 0.18, -0.30), Vector3(0.80, 0.07, 0.10), WHITES_DARK, 3407, Vector3.ZERO, 0.0)  # waistband
		return s

	## A small bald head low between the shoulders, a heavy brow, chartreuse eyes, small horns.
	func _head() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3411, 0.06)
		blob(s, Vector3(0, 0.06, 0), Vector3(0.24, 0.22, 0.24), SKIN, 3412, 0.12, 1)
		blob(s, Vector3(0, -0.06, -0.12), Vector3(0.22, 0.10, 0.14), SKIN_DARK, 3413, 0.12)
		slab(s, Vector3(0, 0.11, -0.20), Vector3(0.36, 0.07, 0.10), SKIN_DARK, 3414, Vector3(-8, 0, 0), 0.02)
		for x: int in [-1, 1]:
			slab(s, Vector3(0.085 * x, 0.04, -0.225), Vector3(0.08, 0.045, 0.03), glow(BILE), 3415 + x, Vector3(0, 0, -10 * x), 0.0, 0.0)
			limb(s, Vector3(0.17 * x, 0.18, 0.0), Vector3(0.22 * x, 0.34, 0.10), 0.05, 0.0, 5, WHITES_DARK, 3417 + x, 0.0)
		return s

	func _arm(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3421 + side, 0.06)
		blob(s, Vector3(0, -0.05, 0), Vector3(0.24, 0.22, 0.22), WHITES, 3422 + side, 0.12)              # short sleeve
		limb(s, Vector3(0, -0.12, 0), Vector3(0, -0.52, -0.04), 0.17, 0.15, 6, SKIN, 3424 + side)
		limb(s, Vector3(0, -0.52, -0.04), Vector3(0, -0.88, -0.10), 0.15, 0.17, 6, SKIN, 3426 + side)
		blob(s, Vector3(0, -0.98, -0.12), Vector3(0.17, 0.15, 0.17), SKIN_DARK, 3428 + side, 0.15)
		return s

	func _leg(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3431 + side, 0.06)
		limb(s, Vector3(0, 0.0, 0), Vector3(0, -0.50, -0.02), 0.19, 0.16, 6, WHITES_DARK, 3432 + side)
		limb(s, Vector3(0, -0.50, -0.02), Vector3(0, -0.92, 0.0), 0.16, 0.14, 6, WHITES_DARK, 3434 + side)
		blob(s, Vector3(0, -0.94, -0.10), Vector3(0.16, 0.07, 0.24), SHOE, 3436 + side, 0.12)
		return s

	## The gurney (its handle end toward the orderly at local +Z): frame, four legs on casters, a grey sheet, a pillow
	## at the far end, a car battery with glowing terminals and jumper cables coiled on the sheet.
	func _gurney() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(3441, 0.04)
		var hz := G_LEN * 0.5
		var hx := G_WID * 0.5
		for x: int in [-1, 1]:
			limb(s, Vector3(hx * x, DECK_Y, -hz), Vector3(hx * x, DECK_Y, hz), 0.035, 0.035, 5, STEEL, 3442 + x, 0.0, 0.0)   # side rails
			for z: int in [-1, 1]:
				var foot := Vector3((hx - 0.06) * x, 0.10, (hz - 0.12) * z)
				limb(s, Vector3((hx - 0.04) * x, DECK_Y - 0.02, (hz - 0.10) * z), foot, 0.03, 0.03, 4, STEEL_DARK, 3445 + x + 3 * z, 0.0, 0.0)
				blob(s, foot + Vector3(0, -0.05, 0), Vector3(0.05, 0.05, 0.05), RUBBER, 3452 + x + 3 * z, 0.1)
		limb(s, Vector3(-hx + 0.04, 0.32, 0), Vector3(hx - 0.04, 0.32, 0), 0.025, 0.025, 4, STEEL_DARK, 3458, 0.0, 0.0)   # cross brace
		limb(s, Vector3(0, 0.32, -hz + 0.14), Vector3(0, 0.32, hz - 0.14), 0.025, 0.025, 4, STEEL_DARK, 3459, 0.0, 0.0)
		slab(s, Vector3(0, DECK_Y + 0.07, 0), Vector3(G_WID - 0.04, 0.10, G_LEN - 0.06), SHEET, 3460, Vector3.ZERO, 0.01)   # mattress
		blob(s, Vector3(0, DECK_Y + 0.16, -hz + 0.25), Vector3(0.26, 0.07, 0.15), PILLOW, 3461, 0.12)
		# the push handle at the orderly's end
		limb(s, Vector3(-hx, DECK_Y, hz), Vector3(-hx, DECK_Y + 0.22, hz + 0.08), 0.03, 0.03, 4, STEEL, 3462, 0.0, 0.0)
		limb(s, Vector3(hx, DECK_Y, hz), Vector3(hx, DECK_Y + 0.22, hz + 0.08), 0.03, 0.03, 4, STEEL, 3463, 0.0, 0.0)
		limb(s, Vector3(-hx, DECK_Y + 0.22, hz + 0.08), Vector3(hx, DECK_Y + 0.22, hz + 0.08), 0.035, 0.035, 5, RUBBER, 3464, 0.0, 0.0)
		# the car battery and its glowing charge strip and terminals
		var b := Vector3(0.12, DECK_Y + 0.27, 0.35)
		slab(s, b, Vector3(0.38, 0.30, 0.26), BATTERY, 3465, Vector3(0, 10, 0), 0.01)
		slab(s, b + Vector3(0, 0.0, -0.135), Vector3(0.30, 0.08, 0.02), glow(BILE), 3466, Vector3(0, 10, 0), 0.0, 0.0)
		for x: int in [-1, 1]:
			s.merge(LowPoly.cylinder(0.04, 0.035, 0.06, 6, glow(BILE_HOT), 3467 + x, 0.0, 1, 0.0), LowPoly.at(b + Vector3(0.10 * x, 0.18, 0.0)))
		# jumper cables coiled beside it, the clamps glowing
		for k: int in [0, 1]:
			var prev := b + Vector3(0.10 * (k * 2 - 1), 0.20, 0.0)
			for i in 9:
				var a := float(i) * 0.9 + k * 0.5
				var p := Vector3(-0.14 + cos(a) * (0.16 + 0.02 * k), DECK_Y + 0.15 + 0.02 * k, -0.15 + sin(a) * (0.22 + 0.02 * k) - 0.03 * i)
				limb(s, prev, p, 0.022, 0.022, 4, CABLE, 3470 + i + 10 * k, 0.0, 0.0)
				prev = p
			wedge(s, prev + Vector3(0, 0.03, -0.06), Vector2(0.08, 0.12), Vector2(0.04, 0.10), 0.06, glow(BILE), 3490 + k, Vector3(0, 30 * k, 0), 0.0, 0.0)
		return s

	func apply_idle(t: float, speed: float = 0.0) -> void:
		if _downed:
			return
		var walk := clampf(speed / 2.4, 0.0, 1.0)
		var stride := sin(t * 5.5)
		var h := heal_k
		var body := parts["body"] as MeshInstance3D
		body.position.y = HIP_Y + sin(t * 1.6) * 0.012 - absf(stride) * 0.03 * walk
		body.rotation = Vector3(0.24 + 0.10 * h, 0.0, 0.0)
		(parts["head"] as MeshInstance3D).rotation = Vector3(-0.15, 0.0, 0.0)
		# both fists on the gurney's handle; while healing the right fist holds up a clamp (the cables run in the lab fx)
		var handle := GURNEY_AT + Vector3(0, DECK_Y + 0.22, G_LEN * 0.5 + 0.08)
		var body_xf := body.transform
		for s: int in [-1, 1]:
			var side := "l" if s < 0 else "r"
			var target := body_xf.affine_inverse() * (handle + Vector3(0.30 * s, 0.0, 0.0))
			if s > 0 and h > 0.0:
				target = target.lerp(body_xf.affine_inverse() * Vector3(0.55, 1.95, -0.90), h)
			aim_limb(parts["arm_" + side] as MeshInstance3D, target, 1.0)
			(parts["leg_" + side] as MeshInstance3D).rotation.x = s * stride * 0.45 * walk
		(parts["gurney"] as MeshInstance3D).rotation = Vector3.ZERO

	func _slump() -> void:
		(parts["body"] as MeshInstance3D).rotation = Vector3(0.55, 0.0, 0.0)
