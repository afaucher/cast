extends RefCounted
## Water cooler CARRIERS, round 2 of the enemy healer (docs/design/enemy-healer-options.md, "Round 2"). The user kept the
## Water Cooler's prop and its area pulse, but asked for a carrier that reads as a healer or caretaker and has a support
## weight (grunt to archer, lean or soft, never brute-like), and for the jug lower (shoulder or back height, or set down
## and tended). Four rough faceted blockouts for healer_lab.gd. Lab only, like HealerBlockouts: no Monster kind, not in
## MonsterModels, nothing declares gameplay state. In ZFightModels as "carrier/<kind>".
##
##   const CoolerCarriers := preload("res://scripts/art/lowpoly/monsters/cooler_carriers.gd")
##   var m := CoolerCarriers.build("acolyte")      # a HealerBlockouts.HealerModel: set_heal(k), heal_from()
##
## The glow is on the WATER ONLY (the jug, the pour, a filled cup): the enemy chartreuse (HealerBlockouts.BILE). The eyes
## are the monsters' usual small ember. No crosses: the kit boxes are plain.
## Faces local -Z, +X is its right, origin at the feet, built at world size.
##
##   temp      Office Temp: a skeleton intern in a long, soft dusty-rose cardigan, glasses and a lanyard, hugging the jug to
##             its chest. 2.2 tall, the jug at 1.2-1.8.
##   acolyte   Wellness Acolyte: a soft, linen-robed cultist cradling the jug in front like a vessel, pouring into a paper
##             cup in its other hand. 1.85 tall, the jug at 1.1-1.6.
##   waterboy  Water Boy: a goblin in a white polo, ball cap, whistle and towel, wheeling the cooler on a hand truck, a
##             plain first aid box strapped on. 1.7 to the cap, the jug top at 1.5.
##   janitor   Night Janitor: a hunched ghoul in a drab coverall with a mop, tending a cart with a mop bucket and the
##             cooler set down on it. 1.9 tall (hunched), the jug top at 1.4.

const HealerBlockouts := preload("res://scripts/art/lowpoly/monsters/healer_blockouts.gd")

const KINDS: Array[String] = ["temp", "acolyte", "waterboy", "janitor"]
const NAMES := {"temp": "Office Temp", "acolyte": "Wellness Acolyte", "waterboy": "Water Boy", "janitor": "Night Janitor"}

const BILE := HealerBlockouts.BILE
const BILE_HOT := HealerBlockouts.BILE_HOT
const BILE_DEEP := HealerBlockouts.BILE_DEEP


static func build(kind: String) -> HealerBlockouts.HealerModel:
	match kind:
		"temp":
			return TempModel.new()
		"acolyte":
			return AcolyteModel.new()
		"waterboy":
			return WaterboyModel.new()
		"janitor":
			return JanitorModel.new()
	return null


## Shared: the jug and the small props.
class CarrierModel extends HealerBlockouts.HealerModel:
	const CAP_BLUE := Color(0.70, 0.72, 0.74)      ## the jug's cap (plain grey: no glow off the water)
	const PAPER := Color(0.95, 0.94, 0.89)
	const EMBER := Color(1.0, 0.24, 0.08)

	func heal_from() -> Vector3:
		return (parts["jug"] as Node3D).global_position

	## A 5-gallon jug, upright (neck +Y), centred on the origin: `r` radius, `h` tall. Only the water glows.
	static func jug_soup(r: float, h: float, seed_value: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(seed_value, 0.05)
		var hb := h * 0.66
		var y0 := -h * 0.5
		s.merge(LowPoly.cylinder(r, r, hb, 10, glow(BILE), seed_value + 1, 0.0, 2, 0.03), LowPoly.at(Vector3(0, y0 + hb * 0.5, 0)))
		for f: float in [0.30, 0.70]:
			s.merge(LowPoly.cylinder(r * 1.05, r * 1.05, h * 0.05, 10, glow(BILE_DEEP), seed_value + 2 + int(f * 10.0), 0.0, 1, 0.0),
					LowPoly.at(Vector3(0, y0 + hb * f, 0)))
		s.merge(LowPoly.cylinder(r, r * 0.36, h * 0.20, 10, glow(BILE), seed_value + 5, 0.0, 1, 0.03), LowPoly.at(Vector3(0, y0 + hb + h * 0.10, 0)))
		s.merge(LowPoly.cylinder(r * 0.33, r * 0.33, h * 0.10, 8, glow(BILE_DEEP), seed_value + 6, 0.0, 1, 0.0), LowPoly.at(Vector3(0, y0 + hb + h * 0.25, 0)))
		s.merge(LowPoly.cylinder(r * 0.37, r * 0.37, h * 0.05, 8, CAP_BLUE, seed_value + 7, 0.0, 1, 0.0), LowPoly.at(Vector3(0, y0 + hb + h * 0.32, 0)))
		for i in 3:
			var a := 1.2 + 1.9 * i
			blob(s, Vector3(cos(a) * r * 0.98, y0 + hb * (0.20 + 0.25 * i), sin(a) * r * 0.98), Vector3.ONE * r * 0.17, glow(BILE_HOT), seed_value + 8 + i, 0.1)
		return s

	## A paper cup (open top up), optionally filled (glowing water at the brim).
	static func cup(s: LowPoly.Soup, pos: Vector3, filled: bool, seed_value: int) -> void:
		s.merge(LowPoly.cylinder(0.045, 0.06, 0.11, 7, PAPER, seed_value, 0.0, 1, 0.03), LowPoly.at(pos))
		if filled:
			s.merge(LowPoly.cylinder(0.053, 0.053, 0.012, 7, glow(BILE), seed_value + 1, 0.0, 1, 0.0), LowPoly.at(pos + Vector3(0, 0.05, 0)))


# =============================================================================== temp

class TempModel extends CarrierModel:
	const BONE := Color(0.90, 0.85, 0.72)
	const BONE_LIGHT := Color(0.98, 0.95, 0.84)
	const BONE_DARK := Color(0.64, 0.58, 0.46)
	const VOID := Color(0.09, 0.05, 0.05)
	const CARDIGAN := Color(0.66, 0.42, 0.48)
	const CARDIGAN_DARK := Color(0.50, 0.30, 0.36)
	const SHIRT := Color(0.92, 0.91, 0.86)
	const SLACKS := Color(0.27, 0.25, 0.27)
	const SHOE := Color(0.32, 0.20, 0.13)
	const LANYARD := Color(0.90, 0.46, 0.14)
	const FRAME := Color(0.14, 0.11, 0.10)
	const HIP_Y := 0.92
	const JUG_AT := Vector3(0.0, 0.40, -0.38)
	const MODEL_SCALE := 1.12

	func _init() -> void:
		_setup_model("TempCarrier", MODEL_SCALE)
		monster_kind = "temp"
		ui_height = 2.1 * MODEL_SCALE
		_build()
		apply_idle(0.0)

	func _build() -> void:
		var body := _add_part("body", _body(), self, Vector3(0, HIP_Y, 0))
		_add_part("head", _head(), body, Vector3(0, 0.90, -0.04))
		_add_part("jug", jug_soup(0.27, 0.58, 4101), body, JUG_AT)
		for s: int in [-1, 1]:
			var side := "l" if s < 0 else "r"
			_add_part("arm_" + side, _arm(s), body, Vector3(0.30 * s, 0.60, -0.02))
			_add_part("leg_" + side, _leg(s), self, Vector3(0.12 * s, HIP_Y, 0.0))

	## A narrow ribcage in a long, soft cardigan over a shirt; a lanyard and ID card hanging to one side of the jug.
	func _body() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4111, 0.07)
		blob(s, Vector3(0, 0.0, 0.0), Vector3(0.20, 0.10, 0.14), SLACKS, 4112, 0.12)                          # seat
		limb(s, Vector3(0, -0.12, 0.0), Vector3(0, 0.62, -0.02), 0.27, 0.23, 8, CARDIGAN, 4113, 0.02)        # cardigan body (soft, long)
		blob(s, Vector3(0, 0.62, -0.01), Vector3(0.30, 0.09, 0.18), CARDIGAN_DARK, 4114, 0.12)               # shoulders
		wedge(s, Vector3(0, 0.62, -0.20), Vector2(0.14, 0.05), Vector2(0.05, 0.05), 0.14, SHIRT, 4115, Vector3(-10, 0, 0))   # shirt V
		for x: int in [-1, 1]:
			slab(s, Vector3(0.07 * x, 0.25, -0.265), Vector3(0.03, 0.60, 0.02), CARDIGAN_DARK, 4116 + x, Vector3(-3, 0, 6 * x), 0.0)   # placket
		limb(s, Vector3(0, 0.63, -0.02), Vector3(0, 0.80, -0.04), 0.055, 0.05, 5, BONE_DARK, 4119)             # neck bone
		limb(s, Vector3(-0.09, 0.66, -0.12), Vector3(0.20, 0.36, -0.24), 0.014, 0.014, 4, LANYARD, 4120, 0.0, 0.03)
		limb(s, Vector3(0.09, 0.66, -0.12), Vector3(0.20, 0.36, -0.24), 0.014, 0.014, 4, LANYARD, 4121, 0.0, 0.03)
		slab(s, Vector3(0.21, 0.29, -0.25), Vector3(0.11, 0.14, 0.02), PAPER, 4122, Vector3(-8, 0, -12), 0.0, 0.02)   # ID card
		return s

	## The skull with round wire glasses (the kindly intern), ember eyes, a pencil behind the ear socket.
	func _head() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4131, 0.06)
		blob(s, Vector3.ZERO, Vector3(0.20, 0.18, 0.20), BONE, 4132, 0.1, 1)
		for x: int in [-1, 1]:
			slab(s, Vector3(0.075 * x, -0.005, -0.165), Vector3(0.09, 0.08, 0.05), VOID, 4133 + x, Vector3(0, 0, 12 * x), 0.0, 0.0)
			slab(s, Vector3(0.075 * x, -0.01, -0.19), Vector3(0.05, 0.04, 0.02), glow(EMBER), 4135 + x, Vector3(0, 0, 12 * x), 0.0, 0.0)
			s.merge(LowPoly.cylinder(0.065, 0.065, 0.02, 8, FRAME, 4137 + x, 0.0, 1, 0.0), LowPoly.at(Vector3(0.078 * x, -0.005, -0.215), Vector3(90, 0, 0)))
		slab(s, Vector3(0, 0.0, -0.222), Vector3(0.05, 0.015, 0.015), FRAME, 4139, Vector3.ZERO, 0.0, 0.0)          # bridge
		slab(s, Vector3(0, -0.12, -0.12), Vector3(0.18, 0.05, 0.09), BONE_LIGHT, 4140, Vector3.ZERO, 0.01)          # teeth
		limb(s, Vector3(0.17, 0.08, -0.06), Vector3(0.20, 0.02, 0.14), 0.013, 0.008, 4, Color(0.95, 0.76, 0.22), 4141, 0.0, 0.0)   # pencil
		return s

	## Cardigan sleeve to the elbow, a bony forearm and hand; it hangs down local -Y (aimed at the jug every frame).
	func _arm(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4151 + side, 0.07)
		limb(s, Vector3(0, 0.0, 0), Vector3(0, -0.34, 0), 0.09, 0.085, 6, CARDIGAN, 4152 + side, 0.01)
		limb(s, Vector3(0, -0.34, 0), Vector3(0, -0.58, 0), 0.045, 0.04, 5, BONE, 4154 + side)
		blob(s, Vector3(0, -0.62, 0), Vector3(0.06, 0.07, 0.06), BONE_LIGHT, 4156 + side, 0.15)
		return s

	func _leg(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4161 + side, 0.07)
		limb(s, Vector3(0, 0.0, 0), Vector3(0, -0.44, -0.02), 0.08, 0.07, 6, SLACKS, 4162 + side)
		limb(s, Vector3(0, -0.44, -0.02), Vector3(0, -0.84, 0.0), 0.064, 0.058, 6, SLACKS, 4164 + side)
		wedge(s, Vector3(0, -0.88, -0.06), Vector2(0.12, 0.26), Vector2(0.10, 0.18), 0.08, SHOE, 4166 + side, Vector3.ZERO, 0.01)
		return s

	func apply_idle(t: float, speed: float = 0.0) -> void:
		if _downed:
			return
		var walk := clampf(speed / 3.0, 0.0, 1.0)
		var stride := sin(t * 7.0)
		var h := heal_k
		var body := parts["body"] as MeshInstance3D
		body.position.y = HIP_Y + sin(t * 1.9) * 0.01 - absf(stride) * 0.03 * walk
		body.rotation = Vector3(0.10 + 0.20 * h, stride * 0.06 * walk, 0.0)     # leans back under the weight; forward to pour
		(parts["head"] as MeshInstance3D).rotation = Vector3(-0.10 + 0.25 * h, 0.0, 0.08 * sin(t * 1.1))
		# the jug tips forward to pour while it heals
		var jug := parts["jug"] as MeshInstance3D
		jug.position = JUG_AT + Vector3(0, 0.04 * h, -0.08 * h)
		jug.rotation = Vector3(-0.75 * h, 0.0, 0.10)
		for s: int in [-1, 1]:
			var side := "l" if s < 0 else "r"
			aim_limb(parts["arm_" + side] as MeshInstance3D, jug.position + Vector3(0.24 * s, -0.10 + 0.06 * h, 0.04), 0.62)
			(parts["leg_" + side] as MeshInstance3D).rotation.x = s * stride * 0.6 * walk

	func _slump() -> void:
		(parts["body"] as MeshInstance3D).rotation = Vector3(0.5, 0.0, 0.0)


# =============================================================================== acolyte

class AcolyteModel extends CarrierModel:
	const ROBE := Color(0.66, 0.60, 0.50)
	const ROBE_LIGHT := Color(0.74, 0.68, 0.57)
	const ROBE_DARK := Color(0.50, 0.45, 0.37)
	const SASH := Color(0.70, 0.36, 0.24)
	const SKIN := Color(0.66, 0.58, 0.62)
	const SKIN_DARK := Color(0.50, 0.43, 0.48)
	const HORN := Color(0.90, 0.84, 0.68)
	const BEAD := Color(0.42, 0.26, 0.15)
	const LID := Color(0.18, 0.11, 0.12)
	const SANDAL := Color(0.40, 0.26, 0.15)
	const BODY_Y := 1.20
	const JUG_AT := Vector3(0.04, 0.16, -0.36)
	const CUP_AT := Vector3(-0.10, -0.16, -0.66)

	func _init() -> void:
		_setup_model("AcolyteCarrier", 1.0)
		monster_kind = "acolyte"
		ui_height = 2.1
		_build()
		apply_idle(0.0)

	## The pour leaves the jug's neck.
	func heal_from() -> Vector3:
		return (parts["jug"] as Node3D).global_transform * Vector3(0, 0.30, 0)

	func _build() -> void:
		_add_part("robe", _robe(), self, Vector3.ZERO)
		var body := _add_part("body", _body(), self, Vector3(0, BODY_Y, 0))
		_add_part("head", _head(), body, Vector3(0, 0.44, -0.04))
		_add_part("jug", jug_soup(0.26, 0.56, 4201), body, JUG_AT)
		_add_part("arm_l", _arm(-1), body, Vector3(-0.24, 0.25, -0.02))
		_add_part("arm_r", _arm(1), body, Vector3(0.24, 0.25, -0.02))
		_add_part("cup", _cup(), body, CUP_AT)

	## A long soft robe to the floor (a bell: the soft, never-bulky shape), the hem and sandal toes showing.
	func _robe() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4211, 0.06)
		s.merge(LowPoly.cylinder(0.42, 0.24, 1.16, 9, ROBE, 4212, 0.015, 2), LowPoly.at(Vector3(0, 0.62, 0)))
		s.merge(LowPoly.cylinder(0.44, 0.44, 0.08, 9, ROBE_DARK, 4213, 0.0, 1), LowPoly.at(Vector3(0, 0.06, 0)))        # hem band
		for x: int in [-1, 1]:
			blob(s, Vector3(0.12 * x, 0.04, -0.40), Vector3(0.07, 0.04, 0.09), SANDAL, 4214 + x, 0.12)
		return s

	## The upper robe, a maroon sash over one shoulder, a string of beads.
	func _body() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4221, 0.06)
		limb(s, Vector3(0, -0.10, 0), Vector3(0, 0.30, -0.02), 0.24, 0.22, 8, ROBE_LIGHT, 4222, 0.015)
		blob(s, Vector3(0, 0.30, -0.01), Vector3(0.26, 0.09, 0.17), ROBE, 4223, 0.12)
		slab(s, Vector3(0.0, 0.10, -0.205), Vector3(0.10, 0.50, 0.04), SASH, 4224, Vector3(-6, 0, 34), 0.01)            # sash
		slab(s, Vector3(0.0, 0.10, 0.205), Vector3(0.10, 0.50, 0.04), SASH, 4225, Vector3(6, 0, -34), 0.01)
		for i in 7:
			var a := PI * (0.15 + 0.7 * float(i) / 6.0)
			blob(s, Vector3(cos(a) * 0.15, 0.30 - sin(a) * 0.16, -0.17 - sin(a) * 0.04), Vector3.ONE * 0.03, BEAD, 4226 + i, 0.1)
		limb(s, Vector3(0, 0.32, -0.02), Vector3(0, 0.40, -0.03), 0.07, 0.065, 6, SKIN, 4233)
		return s

	## A bald, serene head: two small horns, eyes closed (the calm), a small smile. (The eyes do not glow: water only.)
	func _head() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4241, 0.06)
		blob(s, Vector3(0, 0.09, 0), Vector3(0.16, 0.18, 0.17), SKIN, 4242, 0.1, 1)
		for x: int in [-1, 1]:
			slab(s, Vector3(0.065 * x, 0.09, -0.155), Vector3(0.07, 0.016, 0.02), LID, 4243 + x, Vector3(0, 0, -10 * x), 0.0, 0.0)   # closed eyes
			limb(s, Vector3(0.10 * x, 0.22, -0.02), Vector3(0.15 * x, 0.32, 0.02), 0.04, 0.0, 5, HORN, 4245 + x, 0.0)
		slab(s, Vector3(0, 0.0, -0.16), Vector3(0.07, 0.015, 0.02), LID, 4247, Vector3(0, 0, 0), 0.0, 0.0)               # smile
		blob(s, Vector3(0, -0.04, -0.06), Vector3(0.12, 0.07, 0.11), SKIN_DARK, 4248, 0.12)
		return s

	## A wide bell sleeve and a hand; hangs down local -Y (aimed every frame).
	func _arm(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4251 + side, 0.06)
		limb(s, Vector3(0, 0.0, 0), Vector3(0, -0.40, 0), 0.08, 0.14, 7, ROBE, 4252 + side, 0.01)
		limb(s, Vector3(0, -0.40, 0), Vector3(0, -0.50, 0), 0.045, 0.04, 5, SKIN, 4254 + side)
		blob(s, Vector3(0, -0.54, 0), Vector3(0.055, 0.06, 0.055), SKIN_DARK, 4256 + side, 0.15)
		return s

	func _cup() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4261, 0.04)
		cup(s, Vector3.ZERO, true, 4262)
		cup(s, Vector3(0.0, -0.10, 0.0), false, 4264)      # the stack under it
		return s

	func apply_idle(t: float, speed: float = 0.0) -> void:
		if _downed:
			return
		var walk := clampf(speed / 3.0, 0.0, 1.0)
		var h := heal_k
		var body := parts["body"] as MeshInstance3D
		body.position.y = BODY_Y + sin(t * 1.4) * 0.012
		body.rotation = Vector3(0.05 + 0.10 * h, 0.0, -0.06 - 0.06 * h)
		(parts["robe"] as MeshInstance3D).rotation = Vector3(0.0, 0.0, sin(t * 6.0) * 0.03 * walk)
		(parts["head"] as MeshInstance3D).rotation = Vector3(0.10 + 0.15 * h, 0.0, 0.10 + 0.06 * sin(t * 0.8))
		# the jug cradled in front, lying on the right forearm with its neck forward and down; it tips to pour into the cup
		var jug := parts["jug"] as MeshInstance3D
		jug.rotation = Vector3(deg_to_rad(-100.0 - 25.0 * h), deg_to_rad(-25.0), 0.0)
		aim_limb(parts["arm_r"] as MeshInstance3D, JUG_AT + Vector3(0.10, -0.24, 0.02), 0.54)
		var cup_at := CUP_AT + Vector3(0.0, 0.06 * h, 0.0)
		(parts["cup"] as MeshInstance3D).position = cup_at
		aim_limb(parts["arm_l"] as MeshInstance3D, cup_at + Vector3(0.0, -0.07, 0.04), 0.54)

	func _slump() -> void:
		(parts["body"] as MeshInstance3D).rotation = Vector3(0.45, 0.0, 0.0)


# =============================================================================== water boy

class WaterboyModel extends CarrierModel:
	const SKIN := Color(0.56, 0.64, 0.24)
	const SKIN_LIGHT := Color(0.68, 0.76, 0.32)
	const SKIN_DARK := Color(0.40, 0.48, 0.16)
	const EAR_INNER := Color(0.86, 0.52, 0.40)
	const POLO := Color(0.93, 0.92, 0.88)
	const POLO_DARK := Color(0.72, 0.72, 0.70)
	const SHORTS := Color(0.22, 0.22, 0.30)
	const SOCK := Color(0.94, 0.93, 0.90)
	const SHOE := Color(0.18, 0.14, 0.13)
	const CAP := Color(0.82, 0.30, 0.14)
	const WHISTLE := Color(0.80, 0.80, 0.84)
	const CORD := Color(0.82, 0.30, 0.14)
	const STEEL := Color(0.72, 0.75, 0.78)
	const STEEL_DARK := Color(0.40, 0.42, 0.46)
	const GRIP := Color(0.82, 0.30, 0.14)
	const RUBBER := Color(0.10, 0.09, 0.09)
	const CABINET := Color(0.90, 0.89, 0.84)
	const CABINET_DARK := Color(0.62, 0.61, 0.58)
	const KIT := Color(0.94, 0.93, 0.88)
	const KIT_LID := Color(0.20, 0.36, 0.26)
	const MOUTH := Color(0.16, 0.06, 0.05)
	const HIP_Y := 0.60
	const TRUCK_AT := Vector3(0.0, 0.0, -0.95)
	const TRUCK_TILT := 24.0
	const RAIL_H := 1.15

	func _init() -> void:
		_setup_model("WaterboyCarrier", 1.1)
		monster_kind = "waterboy"
		ui_height = 2.0 * 1.1
		_build()
		apply_idle(0.0)

	func _build() -> void:
		var body := _add_part("body", _body(), self, Vector3(0, HIP_Y, 0))
		var head := _add_part("head", _head(), body, Vector3(0, 0.62, -0.10))
		for s: int in [-1, 1]:
			var side := "l" if s < 0 else "r"
			_add_part("ear_" + side, _ear(s), head, Vector3(0.17 * s, 0.10, 0.02))
			_add_part("arm_" + side, _arm(s), body, Vector3(0.23 * s, 0.44, -0.04))
			_add_part("leg_" + side, _leg(s), self, Vector3(0.12 * s, HIP_Y, 0.0))
		var truck := _add_part("truck", _truck(), self, TRUCK_AT)
		truck.rotation = Vector3(deg_to_rad(TRUCK_TILT), 0.0, 0.0)
		_add_part("jug", jug_soup(0.24, 0.54, 4301), truck, Vector3(0, 0.90 + 0.27, -0.20))
		(parts["jug"] as MeshInstance3D).rotation = Vector3(PI, 0.0, 0.0)          # the cooler's jug sits neck down

	## A small goblin torso in a white team polo, a towel over the left shoulder, the whistle on its cord.
	func _body() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4311, 0.07)
		blob(s, Vector3(0, 0.02, 0), Vector3(0.19, 0.12, 0.15), SHORTS, 4312, 0.12)
		limb(s, Vector3(0, 0.02, 0), Vector3(0, 0.44, -0.06), 0.18, 0.20, 7, POLO, 4313, 0.02)
		blob(s, Vector3(0, 0.45, -0.05), Vector3(0.24, 0.09, 0.15), POLO_DARK, 4314, 0.12)
		wedge(s, Vector3(0, 0.50, -0.14), Vector2(0.16, 0.06), Vector2(0.20, 0.08), 0.06, POLO_DARK, 4315, Vector3(-20, 0, 0))   # collar
		# the towel, draped over the left shoulder: front and back flaps and the fold on top
		slab(s, Vector3(-0.16, 0.50, -0.02), Vector3(0.16, 0.05, 0.36), PAPER, 4316, Vector3(0, 0, 16), 0.01)
		slab(s, Vector3(-0.15, 0.33, -0.205), Vector3(0.15, 0.32, 0.04), PAPER, 4317, Vector3(-6, 0, 4), 0.01)
		slab(s, Vector3(-0.16, 0.30, 0.18), Vector3(0.15, 0.36, 0.04), PAPER, 4318, Vector3(6, 0, 4), 0.01)
		# the whistle cord and the whistle
		limb(s, Vector3(0.10, 0.50, -0.12), Vector3(0.05, 0.28, -0.215), 0.010, 0.010, 3, CORD, 4319, 0.0, 0.0)
		limb(s, Vector3(-0.05, 0.50, -0.14), Vector3(0.05, 0.28, -0.215), 0.010, 0.010, 3, CORD, 4320, 0.0, 0.0)
		slab(s, Vector3(0.05, 0.25, -0.225), Vector3(0.07, 0.04, 0.05), WHISTLE, 4321, Vector3(0, 0, 0), 0.0, 0.02)
		return s

	## The goblin's big head: a long nose, a grin, ember eyes, a ball cap with its brim forward.
	func _head() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4331, 0.08)
		blob(s, Vector3(0, 0.10, -0.02), Vector3(0.18, 0.15, 0.17), SKIN, 4332, 0.1, 1)
		blob(s, Vector3(0, 0.0, -0.08), Vector3(0.13, 0.07, 0.11), SKIN_DARK, 4333, 0.14)
		limb(s, Vector3(0, 0.08, -0.16), Vector3(0, 0.02, -0.32), 0.05, 0.0, 5, SKIN_LIGHT, 4334, 0.0)
		slab(s, Vector3(0, -0.01, -0.165), Vector3(0.13, 0.03, 0.04), MOUTH, 4335, Vector3(0, 0, 6), 0.0, 0.0)
		for x: int in [-1, 1]:
			slab(s, Vector3(0.075 * x, 0.12, -0.17), Vector3(0.05, 0.04, 0.03), glow(EMBER), 4336 + x, Vector3.ZERO, 0.0, 0.0)
		blob(s, Vector3(0, 0.21, 0.0), Vector3(0.18, 0.08, 0.18), CAP, 4338, 0.1)                       # cap crown
		wedge(s, Vector3(0, 0.18, -0.20), Vector2(0.26, 0.18), Vector2(0.24, 0.16), 0.025, CAP, 4339, Vector3(-8, 0, 0), 0.0)   # brim
		blob(s, Vector3(0, 0.29, 0.0), Vector3(0.03, 0.02, 0.03), PAPER, 4340, 0.1)                     # cap button
		return s

	func _ear(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4341 + side, 0.07)
		var sd := float(side)
		s.merge(LowPoly.frustum(Vector2(0.10, 0.04), Vector2(0.02, 0.02), 0.28, SKIN, 4342 + side, 0.01), LowPoly.at(Vector3(0.13 * sd, 0.02, 0), Vector3(0, 0, -80 * sd)))
		s.merge(LowPoly.frustum(Vector2(0.06, 0.02), Vector2(0.01, 0.01), 0.20, EAR_INNER, 4344 + side, 0.0), LowPoly.at(Vector3(0.12 * sd, 0.02, -0.025), Vector3(0, 0, -80 * sd)))
		return s

	func _arm(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4351 + side, 0.07)
		blob(s, Vector3(0, -0.03, 0), Vector3(0.08, 0.09, 0.08), POLO, 4352 + side, 0.12)
		limb(s, Vector3(0, -0.06, 0), Vector3(0, -0.30, 0), 0.05, 0.045, 5, SKIN, 4353 + side)
		limb(s, Vector3(0, -0.30, 0), Vector3(0, -0.50, 0), 0.045, 0.04, 5, SKIN, 4355 + side)
		blob(s, Vector3(0, -0.54, 0), Vector3(0.06, 0.06, 0.06), SKIN_DARK, 4357 + side, 0.15)
		return s

	func _leg(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4361 + side, 0.07)
		limb(s, Vector3(0, 0.0, 0), Vector3(0, -0.18, 0.0), 0.09, 0.08, 6, SHORTS, 4362 + side)
		limb(s, Vector3(0, -0.18, 0.0), Vector3(0, -0.34, 0.0), 0.05, 0.045, 5, SKIN, 4364 + side)
		limb(s, Vector3(0, -0.34, 0.0), Vector3(0, -0.54, 0.0), 0.05, 0.05, 5, SOCK, 4366 + side)
		wedge(s, Vector3(0, -0.565, -0.05), Vector2(0.12, 0.22), Vector2(0.10, 0.16), 0.07, SHOE, 4368 + side, Vector3.ZERO, 0.01)
		return s

	## The hand truck (upright in its own space; the part is tilted back toward the goblin): two rails with red grips,
	## the nose plate, two wheels at the back, the cooler cabinet strapped on (its jug is the separate "jug" part on top),
	## a paper-cup tube on the side and a plain first aid box.
	func _truck() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4371, 0.04)
		for x: int in [-1, 1]:
			limb(s, Vector3(0.24 * x, 0.06, 0.04), Vector3(0.24 * x, RAIL_H, 0.04), 0.025, 0.025, 5, STEEL, 4372 + x, 0.0, 0.0)
			limb(s, Vector3(0.24 * x, RAIL_H, 0.04), Vector3(0.24 * x, RAIL_H + 0.04, 0.16), 0.025, 0.025, 5, STEEL, 4375 + x, 0.0, 0.0)
			s.merge(LowPoly.cylinder(0.11, 0.11, 0.06, 8, RUBBER, 4378 + x, 0.0), LowPoly.at(Vector3(0.30 * x, 0.11, 0.12), Vector3(0, 0, 90)))
			s.merge(LowPoly.cylinder(0.05, 0.05, 0.07, 6, STEEL_DARK, 4381 + x, 0.0), LowPoly.at(Vector3(0.30 * x, 0.11, 0.12), Vector3(0, 0, 90)))
		limb(s, Vector3(-0.24, RAIL_H + 0.04, 0.16), Vector3(0.24, RAIL_H + 0.04, 0.16), 0.035, 0.035, 6, GRIP, 4384, 0.0, 0.0)   # handle
		for y: float in [0.45, 0.95]:
			limb(s, Vector3(-0.24, y, 0.04), Vector3(0.24, y, 0.04), 0.018, 0.018, 4, STEEL_DARK, 4385 + int(y * 10.0), 0.0, 0.0)
		limb(s, Vector3(-0.30, 0.11, 0.12), Vector3(0.30, 0.11, 0.12), 0.02, 0.02, 4, STEEL_DARK, 4396, 0.0, 0.0)   # axle
		slab(s, Vector3(0, 0.025, -0.16), Vector3(0.50, 0.03, 0.34), STEEL_DARK, 4397, Vector3.ZERO, 0.0)              # nose plate
		# the cooler cabinet (a short counter-top cooler) on the plate
		slab(s, Vector3(0, 0.47, -0.20), Vector3(0.44, 0.84, 0.40), CABINET, 4398, Vector3.ZERO, 0.01)
		slab(s, Vector3(0, 0.55, -0.42), Vector3(0.30, 0.26, 0.05), CABINET_DARK, 4399, Vector3.ZERO, 0.0)          # tap recess
		slab(s, Vector3(-0.07, 0.62, -0.45), Vector3(0.05, 0.07, 0.06), CABINET_DARK, 4400, Vector3.ZERO, 0.0, 0.0)
		slab(s, Vector3(0.07, 0.62, -0.45), Vector3(0.05, 0.07, 0.06), CABINET_DARK, 4401, Vector3.ZERO, 0.0, 0.0)
		for y: float in [0.22, 0.78]:
			slab(s, Vector3(0, y, -0.20), Vector3(0.47, 0.05, 0.43), RUBBER, 4402 + int(y * 10.0), Vector3.ZERO, 0.0)   # straps
		# the cup tube on the right side, cups in it
		s.merge(LowPoly.cylinder(0.055, 0.055, 0.42, 7, PAPER, 4410, 0.0, 1, 0.02), LowPoly.at(Vector3(0.285, 0.55, -0.24)))
		# the first aid box hooked on the left rail (plain: no cross)
		slab(s, Vector3(-0.36, 0.62, -0.10), Vector3(0.12, 0.24, 0.30), KIT, 4411, Vector3.ZERO, 0.01)
		slab(s, Vector3(-0.36, 0.76, -0.10), Vector3(0.13, 0.05, 0.31), KIT_LID, 4412, Vector3.ZERO, 0.0)
		limb(s, Vector3(-0.36, 0.79, -0.16), Vector3(-0.36, 0.79, -0.04), 0.015, 0.015, 4, KIT_LID, 4413, 0.0, 0.0)   # handle
		return s

	func apply_idle(t: float, speed: float = 0.0) -> void:
		if _downed:
			return
		var walk := clampf(speed / 3.5, 0.0, 1.0)
		# The active walk (MonsterModel.gait_k): a hustle behind the truck, the hips rolling over each step and the head
		# bobbing. The war cry (cry_k): it straightens and the whistle comes up, as for the pour.
		var g := gait_k(walk)
		var cr := cry_k()
		var stride := sin(t * 8.0)
		var h := maxf(heal_k, cr)
		var body := parts["body"] as MeshInstance3D
		body.position = Vector3(stride * 0.025 * g, HIP_Y + sin(t * 2.2) * 0.01 - absf(stride) * 0.03 * walk - absf(stride) * 0.02 * g, body.position.z)
		body.rotation = Vector3(0.28 - 0.18 * h + 0.06 * g, stride * 0.05 * g, -stride * 0.06 * g)      # leaning into the truck; straightens to blow the whistle
		(parts["head"] as MeshInstance3D).rotation = Vector3(-0.25 + 0.10 * h - absf(stride) * 0.08 * g - 0.15 * cr, 0.0, stride * 0.07 * g)
		var truck := parts["truck"] as MeshInstance3D
		var tx := truck.transform
		var bx := body.transform.affine_inverse()
		for s: int in [-1, 1]:
			var side := "l" if s < 0 else "r"
			var grip := bx * (tx * Vector3(0.18 * s, RAIL_H + 0.04, 0.16))
			if s > 0 and h > 0.0:
				grip = grip.lerp(Vector3(0.10, 0.40, -0.30), h)    # the right hand brings the whistle up: the pour's tell
			aim_limb(parts["arm_" + side] as MeshInstance3D, grip, 0.54)
			(parts["leg_" + side] as MeshInstance3D).rotation.x = s * stride * 0.7 * walk

	func _slump() -> void:
		(parts["body"] as MeshInstance3D).rotation = Vector3(0.6, 0.0, 0.0)


# =============================================================================== janitor

class JanitorModel extends CarrierModel:
	const SKIN := Color(0.54, 0.54, 0.52)
	const SKIN_DARK := Color(0.40, 0.40, 0.39)
	const COVERALL := Color(0.42, 0.40, 0.28)
	const COVERALL_DARK := Color(0.30, 0.28, 0.20)
	const CAPCOL := Color(0.26, 0.24, 0.20)
	const BOOT := Color(0.16, 0.12, 0.10)
	const BUCKET := Color(0.40, 0.42, 0.46)
	const BUCKET_DARK := Color(0.28, 0.30, 0.33)
	const STEEL := Color(0.72, 0.75, 0.78)
	const RUBBER := Color(0.10, 0.09, 0.09)
	const WOOD := Color(0.62, 0.46, 0.28)
	const MOP := Color(0.86, 0.82, 0.70)
	const DIRTY := Color(0.30, 0.30, 0.22)
	const CABINET := Color(0.90, 0.89, 0.84)
	const RAG := Color(0.70, 0.30, 0.22)
	const HIP_Y := 1.00
	const CART_AT := Vector3(0.20, 0.0, -0.95)

	func _init() -> void:
		_setup_model("JanitorCarrier", 1.0)
		monster_kind = "janitor"
		ui_height = 2.1
		_build()
		apply_idle(0.0)

	func _build() -> void:
		var body := _add_part("body", _body(), self, Vector3(0, HIP_Y, 0))
		_add_part("head", _head(), body, Vector3(0, 0.80, -0.16))
		for s: int in [-1, 1]:
			var side := "l" if s < 0 else "r"
			_add_part("arm_" + side, _arm(s), body, Vector3(0.24 * s, 0.66, -0.06))
			_add_part("leg_" + side, _leg(s), self, Vector3(0.12 * s, HIP_Y, 0.0))
		var cart := _add_part("cart", _cart(), self, CART_AT)
		cart.rotation = Vector3(0.0, deg_to_rad(-12.0), 0.0)
		_add_part("jug", jug_soup(0.24, 0.54, 4501), cart, Vector3(-0.22, 0.82 + 0.27, 0.0))
		(parts["jug"] as MeshInstance3D).rotation = Vector3(PI, 0.0, 0.0)
		_add_part("mop", _mop(), self, Vector3(0.55, 0.0, -0.45))

	func _body() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4511, 0.07)
		blob(s, Vector3(0, 0.0, 0), Vector3(0.20, 0.12, 0.15), COVERALL_DARK, 4512, 0.12)
		limb(s, Vector3(0, 0.0, 0), Vector3(0, 0.66, -0.05), 0.18, 0.21, 7, COVERALL, 4513, 0.02)
		blob(s, Vector3(0, 0.66, -0.04), Vector3(0.25, 0.09, 0.15), COVERALL_DARK, 4514, 0.12)
		slab(s, Vector3(0.09, 0.44, -0.215), Vector3(0.11, 0.10, 0.03), COVERALL_DARK, 4515, Vector3.ZERO, 0.0)   # chest pocket
		slab(s, Vector3(-0.08, 0.46, -0.225), Vector3(0.09, 0.04, 0.02), PAPER, 4516, Vector3.ZERO, 0.0, 0.02)   # name patch
		slab(s, Vector3(0.10, -0.05, 0.16), Vector3(0.10, 0.22, 0.03), RAG, 4517, Vector3(8, 0, 6), 0.01)       # rag in the back pocket
		limb(s, Vector3(0, 0.66, -0.05), Vector3(0, 0.76, -0.12), 0.06, 0.055, 5, SKIN, 4518)
		return s

	func _head() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4521, 0.07)
		blob(s, Vector3(0, 0.06, -0.02), Vector3(0.15, 0.18, 0.17), SKIN, 4522, 0.12, 1)
		blob(s, Vector3(0, -0.06, -0.08), Vector3(0.12, 0.07, 0.10), SKIN_DARK, 4523, 0.12)
		for x: int in [-1, 1]:
			slab(s, Vector3(0.06 * x, 0.06, -0.17), Vector3(0.045, 0.035, 0.03), glow(EMBER), 4524 + x, Vector3.ZERO, 0.0, 0.0)
		blob(s, Vector3(0, 0.18, 0.0), Vector3(0.17, 0.07, 0.18), CAPCOL, 4526, 0.1)                       # flat cap
		wedge(s, Vector3(0, 0.15, -0.18), Vector2(0.22, 0.12), Vector2(0.20, 0.10), 0.03, CAPCOL, 4527, Vector3(-10, 0, 0), 0.0)
		return s

	func _arm(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4531 + side, 0.07)
		limb(s, Vector3(0, 0.0, 0), Vector3(0, -0.36, 0), 0.07, 0.06, 6, COVERALL, 4532 + side)
		limb(s, Vector3(0, -0.36, 0), Vector3(0, -0.66, 0), 0.045, 0.04, 5, SKIN, 4534 + side)
		blob(s, Vector3(0, -0.70, 0), Vector3(0.06, 0.07, 0.06), SKIN_DARK, 4536 + side, 0.15)
		return s

	func _leg(side: int) -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4541 + side, 0.07)
		limb(s, Vector3(0, 0.0, 0), Vector3(0, -0.48, -0.02), 0.085, 0.075, 6, COVERALL, 4542 + side)
		limb(s, Vector3(0, -0.48, -0.02), Vector3(0, -0.90, 0.0), 0.068, 0.064, 6, COVERALL_DARK, 4544 + side)
		wedge(s, Vector3(0, -0.94, -0.06), Vector2(0.14, 0.28), Vector2(0.12, 0.20), 0.09, BOOT, 4546 + side, Vector3.ZERO, 0.01)
		return s

	## The cart: a low frame on four casters, the mop bucket with its wringer, and a short cooler cabinet set down on the
	## other end (its jug is the "jug" part).
	func _cart() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4551, 0.04)
		slab(s, Vector3(0, 0.12, 0), Vector3(0.96, 0.05, 0.50), BUCKET_DARK, 4552, Vector3.ZERO, 0.0)
		for x: int in [-1, 1]:
			for z: int in [-1, 1]:
				blob(s, Vector3(0.42 * x, 0.05, 0.20 * z), Vector3(0.05, 0.05, 0.05), RUBBER, 4553 + x + 3 * z, 0.1)
		# the bucket and its grey water, the wringer on top
		s.merge(LowPoly.cylinder(0.20, 0.24, 0.38, 9, BUCKET, 4560, 0.0, 1), LowPoly.at(Vector3(0.24, 0.335, 0)))
		s.merge(LowPoly.cylinder(0.215, 0.215, 0.012, 9, DIRTY, 4561, 0.0, 1, 0.0), LowPoly.at(Vector3(0.24, 0.47, 0)))
		slab(s, Vector3(0.24, 0.60, 0.10), Vector3(0.30, 0.12, 0.16), BUCKET_DARK, 4562, Vector3.ZERO, 0.0)
		limb(s, Vector3(0.24, 0.66, 0.10), Vector3(0.24, 0.95, 0.24), 0.02, 0.02, 4, STEEL, 4563, 0.0, 0.0)          # wringer lever
		# the cooler cabinet set down on the cart
		slab(s, Vector3(-0.22, 0.48, 0), Vector3(0.40, 0.68, 0.40), CABINET, 4564, Vector3.ZERO, 0.01)
		slab(s, Vector3(-0.22, 0.52, -0.215), Vector3(0.26, 0.22, 0.04), BUCKET_DARK, 4565, Vector3.ZERO, 0.0)
		s.merge(LowPoly.cylinder(0.05, 0.05, 0.36, 7, PAPER, 4566, 0.0, 1, 0.02), LowPoly.at(Vector3(-0.46, 0.50, -0.06)))   # cup sleeve
		cup(s, Vector3(0.0, 0.205, -0.17), true, 4567)                                                                    # a filled cup
		return s

	## The mop: a long handle leaning from the floor up into the right hand, the string head on the floor.
	func _mop() -> LowPoly.Soup:
		var s := LowPoly.Soup.new(4571, 0.05)
		limb(s, Vector3(0, 0.12, 0), Vector3(-0.18, 1.55, 0.30), 0.025, 0.025, 5, WOOD, 4572, 0.0, 0.0)
		blob(s, Vector3(0, 0.08, 0), Vector3(0.20, 0.08, 0.20), MOP, 4573, 0.25)
		for i in 6:
			var a := TAU * float(i) / 6.0
			limb(s, Vector3(cos(a) * 0.08, 0.10, sin(a) * 0.08), Vector3(cos(a) * 0.26, 0.02, sin(a) * 0.26), 0.035, 0.025, 4, MOP, 4574 + i, 0.0)
		return s

	func apply_idle(t: float, speed: float = 0.0) -> void:
		if _downed:
			return
		var walk := clampf(speed / 3.0, 0.0, 1.0)
		var stride := sin(t * 6.0)
		var h := heal_k
		var body := parts["body"] as MeshInstance3D
		body.position.y = HIP_Y + sin(t * 1.5) * 0.012 - absf(stride) * 0.03 * walk
		body.rotation = Vector3(0.45 + 0.10 * h, -0.15, 0.0)      # the hunch, turned a little toward the cart
		(parts["head"] as MeshInstance3D).rotation = Vector3(-0.35, 0.20, 0.0)
		var bx := body.transform.affine_inverse()
		var mop := parts["mop"] as MeshInstance3D
		aim_limb(parts["arm_r"] as MeshInstance3D, bx * (mop.transform * Vector3(-0.15, 1.30, 0.25)), 0.70)
		# the left hand on the cooler's tap (it fills a cup while healing)
		var cart := parts["cart"] as MeshInstance3D
		var tap := cart.transform * Vector3(-0.22, 0.56 + 0.10 * h, -0.30)
		aim_limb(parts["arm_l"] as MeshInstance3D, bx * tap, 0.70)
		(parts["leg_l"] as MeshInstance3D).rotation.x = stride * 0.5 * walk
		(parts["leg_r"] as MeshInstance3D).rotation.x = -stride * 0.5 * walk

	func _slump() -> void:
		(parts["body"] as MeshInstance3D).rotation = Vector3(0.7, 0.0, 0.0)
