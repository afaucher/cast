class_name AcolyteModel
extends MonsterModel
## LOOK-DEV ONLY (docs/design/necro-look.md): the necromancer acolyte (new-themes.md "Ghost house": "mobile host monsters
## that flee and raise bodies"). Nothing in the game spawns it: only NecroBody (the gym's necro spawns and the look lab).
## A living human cultist, so it must read as a person, and not as office staff or a hero: tall and narrow (the staff are
## short and pear-shaped, with one bright identifier), in a floor-length robe and hood (no hero wears one), monochrome
## (soot, ash, bone, iron), and the only colour on it is the ghost colour it channels.
##   cowl   a deep black hood round a pale, gaunt human face with shadowed eyes, a soot-black robe with a bone-white stole,
##          rope belt and a bone ring on its chest, and a tall crooked staff with a cage lantern of ghost-light hanging
##          from its hook.
##   mask   a slate-grey robe under a ragged black mantle and a shallow hood, a smooth white mask over the upper face (the
##          chin and mouth bare: a person under it), the eye holes lit, and a censer on a chain trailing ghost-smoke.
## Poses: apply_idle(t, speed) stands (hands at its chest, swaying) or flees (speed > ~1.5: running hunched, the robe
## flapping, the head turned back over its shoulder); set_raise(k) is raising the dead (both arms up and out, the hands
## and the light flaring, the head back). Faces local -Z, +X is its right, origin at the feet. Named rigid parts: body,
## skirt, head, hood, arm_l, arm_r, leg_l, leg_r, prop (the staff or the censer), aura_l, aura_r (the hands' glow).

const VARIANTS: Array[String] = ["cowl", "mask"]
const PART_NAMES: Array[String] = ["body", "skirt", "head", "hood", "arm_l", "arm_r", "leg_l", "leg_r", "prop", "aura_l", "aura_r"]
const RUN_SPEED := 3.2              ## the world speed the flee is drawn for

const SKIN := Color(0.84, 0.76, 0.68)             ## pale, a little grey: indoors too long
const SKIN_DARK := Color(0.68, 0.58, 0.52)
const SHADOW := Color(0.22, 0.17, 0.17)            ## the eye hollows under the hood
const LIP := Color(0.45, 0.32, 0.32)
const ROBE := Color(0.15, 0.13, 0.13)              ## the cowl's soot black
const ROBE_LIGHT := Color(0.23, 0.20, 0.20)
const ROBE_DARK := Color(0.09, 0.08, 0.08)
const SLATE := Color(0.33, 0.34, 0.37)             ## the mask's robe
const SLATE_LIGHT := Color(0.42, 0.43, 0.46)
const SLATE_DARK := Color(0.23, 0.24, 0.27)
const MANTLE := Color(0.13, 0.12, 0.13)
const BONE := Color(0.88, 0.84, 0.72)
const BONE_DARK := Color(0.70, 0.65, 0.53)
const PORCELAIN := Color(0.93, 0.92, 0.88)
const ROPE := Color(0.62, 0.55, 0.42)
const WOOD := Color(0.26, 0.18, 0.13)
const WOOD_DARK := Color(0.17, 0.12, 0.09)
const IRON := Color(0.26, 0.27, 0.30)
const IRON_LIGHT := Color(0.40, 0.41, 0.45)
const LANTERN := Vector3(0.22, 0.76, 0)           ## the cowl's lantern on its staff (the prop's space)
const VOID := Color(0.04, 0.035, 0.04)
const SHOE := Color(0.12, 0.10, 0.09)

const BODY_Y := 0.98                ## the waist
const SHOULDER := Vector3(0.21, 0.50, 0.0)
const ARM_LEN := 0.62
const LEG_X := 0.10

var variant := "cowl"
var _raise := 0.0


func _init(model_variant: String = "cowl") -> void:
	variant = model_variant if VARIANTS.has(model_variant) else "cowl"
	_setup_model("AcolyteModel", 1.04)
	monster_kind = "acolyte"
	_mat = NecroLook.body_material(outline_px, NecroLook.RIM_ACOLYTE)
	_mat.set_shader_parameter("glow_gain", GLOW_GAIN)
	ui_height = 2.0 * scale.x
	has_own_weapon = true
	_build()
	apply_idle(0.0)


# ------------------------------------------------------------------ build

func _build() -> void:
	var mask := variant == "mask"
	var body := _add_part("body", _body_soup(), self, Vector3(0, BODY_Y, 0))
	_add_part("skirt", _skirt_soup(), self, Vector3(0, BODY_Y, 0))
	var head := _add_part("head", _head_soup(), body, Vector3(0, 0.70, -0.02))
	_add_part("hood", _hood_soup(), head, Vector3.ZERO)
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var arm := _add_part("arm_" + side, _arm_soup(s), body, Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z))
		var aura := _add_part("aura_" + side, _aura_soup(s), arm, Vector3(0, -ARM_LEN, -0.02))
		aura.scale = Vector3.ONE * 0.001
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(LEG_X * s, BODY_Y - 0.05, 0.0))
	var prop := _add_part("prop", _censer_soup() if mask else _staff_soup(), parts["arm_r"] as Node3D, Vector3(0, -ARM_LEN + 0.02, -0.02))
	if not mask:
		# the lantern lights the floor round it in the ghost colour, with a few motes drifting off it: a pool of cold light
		# that walks with the acolyte, so it stands out at the game camera (the user, 2026-10-29: "the acolyte needs
		# something to make it stand out more. It is too bland.")
		var l := OmniLight3D.new()
		l.name = "LanternLight"
		l.position = LANTERN
		l.light_color = NecroLook.glow_colour()
		l.light_energy = 5.0
		l.omni_range = 5.0
		l.omni_attenuation = 1.1
		l.light_specular = 0.1
		l.shadow_enabled = false
		prop.add_child(l)
		var m := NecroLook.motes(8, 0.14, 0.45, 0.03)
		m.name = "LanternMotes"
		m.position = LANTERN
		prop.add_child(m)


func _robe() -> Color:
	return SLATE if variant == "mask" else ROBE


func _robe_light() -> Color:
	return SLATE_LIGHT if variant == "mask" else ROBE_LIGHT


func _robe_dark() -> Color:
	return SLATE_DARK if variant == "mask" else ROBE_DARK


## The torso: narrow, sloping shoulders, the robe's chest. Cowl: a bone-white stole down the front, a bone ring on a cord.
## Mask: a ragged black mantle over the shoulders and chest.
func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(901, 0.06)
	wedge(s, Vector3(0, 0.27, 0), Vector2(0.36, 0.26), Vector2(0.42, 0.27), 0.54, _robe(), 902, Vector3.ZERO, 0.01)
	for x: float in [-1.0, 1.0]:
		blob(s, Vector3(0.18 * x, 0.50, 0.0), Vector3(0.09, 0.07, 0.12), _robe_light(), 903 + int(x), 0.1)
	limb(s, Vector3(0, 0.52, -0.01), Vector3(0, 0.64, -0.02), 0.055, 0.05, 6, SKIN_DARK, 906)          # neck
	wedge(s, Vector3(0, 0.52, 0.06), Vector2(0.44, 0.34), Vector2(0.30, 0.26), 0.12, MANTLE if variant == "mask" else ROBE, 907, Vector3.ZERO, 0.01)   # the hood's fall
	if variant == "mask":
		# the mantle: a short ragged cape over the shoulders and down the back, open at the front on the robe
		wedge(s, Vector3(0, 0.34, 0.10), Vector2(0.60, 0.18), Vector2(0.46, 0.20), 0.36, MANTLE, 907, Vector3(-6, 0, 0), 0.015)
		for x: float in [-1.0, 1.0]:
			blob(s, Vector3(0.20 * x, 0.49, 0.0), Vector3(0.15, 0.08, 0.17), MANTLE, 908 + int(x), 0.12)
			slab(s, Vector3(0.16 * x, 0.36, -0.12), Vector3(0.09, 0.28, 0.04), MANTLE, 911 + int(x), Vector3(-4, 0, -8.0 * x), 0.01)
		for i in 4:
			var a := PI * 0.5 + 0.55 * (i - 1.5)
			var p := Vector3(cos(a) * 0.26, 0.15 - 0.03 * (i % 2), sin(a) * 0.17 + 0.03)
			wedge(s, p, Vector2(0.15, 0.04), Vector2(0.15, 0.04), 0.12 + 0.04 * (i % 2), MANTLE, 914 + i, Vector3(0, rad_to_deg(-a) + 90.0, 0), 0.02)
		limb(s, Vector3(-0.12, 0.44, -0.145), Vector3(0.12, 0.44, -0.145), 0.012, 0.012, 4, IRON_LIGHT, 918)    # the chain across
		blob(s, Vector3(0, 0.44, -0.15), Vector3(0.04, 0.04, 0.025), IRON_LIGHT, 919, 0.1)                  # the clasp
	else:
		for x: float in [-1.0, 1.0]:
			slab(s, Vector3(0.075 * x, 0.27, -0.135), Vector3(0.07, 0.56, 0.03), BONE, 915 + int(x), Vector3(-3, 0, -4.0 * x))   # the stole
		s.merge(LowPoly.cylinder(0.035, 0.035, 0.012, 8, BONE_DARK, 918, 0.0), LowPoly.at(Vector3(0, 0.33, -0.15), Vector3(90, 0, 0)))  # the ring
		s.merge(LowPoly.cylinder(0.06, 0.06, 0.02, 8, BONE, 919, 0.0), LowPoly.at(Vector3(0, 0.33, -0.142), Vector3(90, 0, 0)))
	s.merge(LowPoly.cylinder(0.20, 0.19, 0.05, 8, ROPE if variant == "cowl" else IRON, 920, 0.005), LowPoly.at(Vector3(0, 0.02, 0)))   # belt
	return s


## The robe below the waist, to the floor: a long flared skirt with a ragged hem. The cowl's stole runs on down it.
func _skirt_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(921, 0.06)
	wedge(s, Vector3(0, -0.45, 0.02), Vector2(0.66, 0.50), Vector2(0.38, 0.27), 0.90, _robe(), 922, Vector3.ZERO, 0.015)
	for i in 7:
		var a := -PI + TAU * float(i) / 7.0
		var p := Vector3(sin(a) * 0.30, -0.88 + 0.02 * (i % 2), -cos(a) * 0.23 + 0.02)
		wedge(s, p, Vector2(0.20, 0.05), Vector2(0.20, 0.05), 0.08 + 0.03 * (i % 2), _robe_dark(), 923 + i, Vector3(0, rad_to_deg(-a), 0), 0.02)
	slab(s, Vector3(0, -0.45, -0.21), Vector3(0.05, 0.84, 0.03), _robe_dark(), 931, Vector3(-9, 0, 0))     # a front fold
	if variant == "cowl":
		for x: float in [-1.0, 1.0]:
			slab(s, Vector3(0.075 * x, -0.30, -0.165), Vector3(0.07, 0.58, 0.03), BONE, 932 + int(x), Vector3(-10, 0, 0))   # the stole's ends
			wedge(s, Vector3(0.075 * x, -0.62, -0.215), Vector2(0.07, 0.03), Vector2(0.07, 0.03), 0.06, BONE_DARK, 935 + int(x), Vector3(-10, 0, 0))
	return s


## A pale, gaunt human face: a long narrow head, sharp nose, hollow eyes (the cowl's in shadow with a glint of the ghost
## colour; the mask's behind the mask), a thin mouth.
func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(941, 0.05)
	blob(s, Vector3(0, 0.0, 0), Vector3(0.13, 0.16, 0.14), SKIN, 942, 0.08, 1)
	blob(s, Vector3(0, -0.11, -0.07), Vector3(0.07, 0.05, 0.06), SKIN_DARK, 943, 0.1)                     # the chin
	slab(s, Vector3(0, -0.075, -0.125), Vector3(0.07, 0.015, 0.02), LIP, 944)                             # mouth
	if variant == "mask":
		# the mask: a smooth white oval over the brow, the eyes and the nose, eye holes lit
		blob(s, Vector3(0, 0.035, -0.10), Vector3(0.12, 0.11, 0.06), PORCELAIN, 945, 0.03, 1)
		for x: int in [-1, 1]:
			slab(s, Vector3(0.05 * x, 0.04, -0.158), Vector3(0.05, 0.03, 0.02), VOID, 946 + x, Vector3(0, 0, 12 * x))
			slab(s, Vector3(0.05 * x, 0.04, -0.166), Vector3(0.025, 0.018, 0.01), NecroLook.glow(1.0), 948 + x, Vector3.ZERO, 0.0, 0.0)
		wedge(s, Vector3(0, -0.02, -0.165), Vector2(0.035, 0.02), Vector2(0.015, 0.01), 0.05, PORCELAIN.darkened(0.08), 950, Vector3(-35, 0, 0))
	else:
		wedge(s, Vector3(0, -0.01, -0.14), Vector2(0.04, 0.035), Vector2(0.015, 0.01), 0.08, SKIN_DARK, 951, Vector3(-38, 0, 0))   # nose
		for x: int in [-1, 1]:
			slab(s, Vector3(0.05 * x, 0.035, -0.115), Vector3(0.065, 0.04, 0.03), SHADOW, 952 + x)
			slab(s, Vector3(0.05 * x, 0.033, -0.13), Vector3(0.02, 0.016, 0.01), NecroLook.glow(0.8), 954 + x, Vector3.ZERO, 0.0, 0.0)
	return s


## The hood. Cowl: deep, drawn forward round the face, its peak falling back to a point between the shoulders, a dark
## inside, a bone-white trim on its edge. Mask: shallow, the mantle's black, framing the white mask.
func _hood_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(961, 0.06)
	var col := MANTLE if variant == "mask" else ROBE
	var deep := variant == "cowl"
	blob(s, Vector3(0, 0.04, 0.05), Vector3(0.19, 0.21, 0.19) * (1.08 if deep else 1.0), col, 962, 0.08, 1)     # the crown and back
	for x: float in [-1.0, 1.0]:
		slab(s, Vector3(0.155 * x, -0.02, -0.07 if deep else -0.04), Vector3(0.05, 0.30, 0.20 if deep else 0.14), col, 963 + int(x), Vector3(0, -12.0 * x, -6.0 * x), 0.012)   # the cheeks
	slab(s, Vector3(0, 0.19, -0.08 if deep else -0.04), Vector3(0.32, 0.06, 0.16), col, 966, Vector3(-14, 0, 0), 0.012)   # the brow of it
	s.merge(LowPoly.cylinder(0.13, 0.0, 0.32 if deep else 0.20, 5, col, 967, 0.01), LowPoly.at(Vector3(0, 0.12, 0.24), Vector3(-62, 0, 0)))  # the peak
	if deep:
		# the trim round the opening, its three runs meeting at the top corners (the user, 2026-10-29: "Lets see if we can
		# get the corners of the cowl's white trim to touch"), and the dark inside above the face
		var top := Vector3(0.165, 0.215, -0.165)
		var foot := Vector3(0.15, -0.17, -0.17)
		limb(s, Vector3(-top.x, top.y, top.z), top, 0.018, 0.018, 4, BONE, 968)
		for x: float in [-1.0, 1.0]:
			limb(s, Vector3(top.x * x, top.y, top.z), Vector3(foot.x * x, foot.y, foot.z), 0.017, 0.017, 4, BONE, 969 + int(x))
			blob(s, Vector3(top.x * x, top.y, top.z), Vector3(0.024, 0.024, 0.022), BONE, 973 + int(x), 0.05)
		slab(s, Vector3(0, 0.13, -0.10), Vector3(0.26, 0.06, 0.06), VOID, 972)
	return s


## A wide bell sleeve from the shoulder and a pale, long-fingered hand.
func _arm_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(981 + side, 0.06)
	limb(s, Vector3(0, 0.0, 0), Vector3(0, -0.30, 0), 0.065, 0.08, 6, _robe(), 982 + side)
	wedge(s, Vector3(0, -0.42, 0), Vector2(0.24, 0.22), Vector2(0.15, 0.14), 0.24, _robe_light(), 984 + side, Vector3.ZERO, 0.012)   # the bell
	wedge(s, Vector3(0, -0.55, 0), Vector2(0.25, 0.23), Vector2(0.24, 0.22), 0.04, _robe_dark(), 986 + side)
	limb(s, Vector3(0, -0.52, -0.01), Vector3(0, -0.60, -0.02), 0.035, 0.035, 5, SKIN_DARK, 988 + side)
	blob(s, Vector3(0, -ARM_LEN, -0.02), Vector3(0.05, 0.065, 0.035), SKIN, 990 + side, 0.12)
	for i in 3:
		limb(s, Vector3(-0.025 + 0.025 * i, -ARM_LEN - 0.03, -0.025), Vector3(-0.03 + 0.03 * i, -ARM_LEN - 0.11, -0.03), 0.012, 0.009, 4, SKIN, 992 + i + side)
	return s


## The glow round a hand while it raises the dead (scaled up from nothing by set_raise).
func _aura_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1001 + side, 0.0)
	blob(s, Vector3(0, -0.04, 0), Vector3(0.10, 0.13, 0.10), NecroLook.glow(1.0), 1002 + side, 0.25)
	return s


## Under the robe: a shin and a soft shoe that shows at the hem when it runs.
func _leg_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1011 + side, 0.06)
	limb(s, Vector3(0, -0.40, 0), Vector3(0, -0.86, 0), 0.06, 0.05, 5, _robe_dark(), 1012 + side)
	slab(s, Vector3(0, -0.89, -0.05), Vector3(0.10, 0.07, 0.22), SHOE, 1014 + side, Vector3.ZERO, 0.01)
	return s


## The cowl's staff: a tall crooked shaft of dark wood (held at the middle; it stands on the floor), iron bands, a hook at
## the top and a small cage lantern of ghost-light hanging from it. Origin at the grip, the shaft along +Y.
func _staff_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1021, 0.07)
	limb(s, Vector3(0.0, -0.86, 0), Vector3(0.02, 0.0, 0), 0.03, 0.035, 5, WOOD_DARK, 1022)
	limb(s, Vector3(0.02, 0.0, 0), Vector3(-0.02, 0.78, 0), 0.035, 0.03, 5, WOOD, 1023)
	limb(s, Vector3(-0.02, 0.78, 0), Vector3(0.06, 0.98, 0), 0.03, 0.025, 5, WOOD, 1024)
	limb(s, Vector3(0.06, 0.98, 0), Vector3(0.20, 0.98, 0), 0.025, 0.02, 5, WOOD_DARK, 1025)          # the hook
	limb(s, Vector3(0.20, 0.98, 0), Vector3(0.22, 0.90, 0), 0.02, 0.016, 4, WOOD_DARK, 1026)
	for y: float in [0.3, 0.62]:
		s.merge(LowPoly.cylinder(0.045, 0.045, 0.04, 6, IRON, 1027, 0.0), LowPoly.at(Vector3(0.0, y, 0)))
	# the lantern: an iron cap, four bars and a base round a glowing core
	var c := LANTERN
	limb(s, Vector3(0.22, 0.90, 0), c + Vector3(0, 0.10, 0), 0.008, 0.008, 3, IRON, 1029)
	s.merge(LowPoly.cylinder(0.09, 0.04, 0.05, 6, IRON_LIGHT, 1030, 0.0), LowPoly.at(c + Vector3(0, 0.09, 0)))
	s.merge(LowPoly.cylinder(0.08, 0.08, 0.03, 6, IRON, 1031, 0.0), LowPoly.at(c - Vector3(0, 0.09, 0)))
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		limb(s, c + Vector3(cos(a) * 0.075, -0.08, sin(a) * 0.075), c + Vector3(cos(a) * 0.075, 0.08, sin(a) * 0.075), 0.01, 0.01, 3, IRON, 1032 + i)
	blob(s, c, Vector3(0.07, 0.085, 0.07), NecroLook.glow(1.4), 1036, 0.15)
	return s


## The mask's censer: a short chain from the fist to a round iron censer with a lit band and a lid. Origin at the fist.
func _censer_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1041, 0.06)
	for i in 5:
		var y := -0.03 - 0.07 * i
		slab(s, Vector3(0, y, 0), Vector3(0.025, 0.06, 0.012) if i % 2 == 0 else Vector3(0.012, 0.06, 0.025), IRON_LIGHT, 1042 + i)
	var c := Vector3(0, -0.47, 0)
	blob(s, c, Vector3(0.10, 0.08, 0.10), IRON, 1048, 0.08, 1)
	s.merge(LowPoly.cylinder(0.105, 0.105, 0.035, 8, NecroLook.glow(1.0), 1049, 0.0), LowPoly.at(c + Vector3(0, 0.02, 0)))
	s.merge(LowPoly.cylinder(0.08, 0.03, 0.07, 8, IRON_LIGHT, 1050, 0.0), LowPoly.at(c + Vector3(0, 0.09, 0)))
	blob(s, c - Vector3(0, 0.08, 0), Vector3(0.04, 0.03, 0.04), IRON, 1051, 0.1)
	return s


# ------------------------------------------------------------------ animation

## Raising the dead, 0..1: both arms up and out, the hands lit, the head back, the staff (the censer) held high.
func set_raise(k_raise: float) -> void:
	_raise = clampf(k_raise, 0.0, 1.0)
	_refresh()


func raise_k() -> float:
	return _raise


## Standing (hands at the chest, the light swinging a little) or fleeing (speed: running hunched, the robe flapping back,
## the head turned back over its shoulder), with raising (set_raise) blended over the standing pose.
func apply_idle(t: float, speed: float = 0.0) -> void:
	if _downed:
		return
	var mask := variant == "mask"
	var run := clampf(speed / RUN_SPEED, 0.0, 1.0)
	var r := _raise * _raise * (3.0 - 2.0 * _raise) * (1.0 - run)
	var w := wind_e()
	var ph := t * 11.0
	var stride := sin(ph)
	var breath := sin(t * 1.9)
	var body := parts["body"] as MeshInstance3D
	body.position = Vector3(0.0, BODY_Y + breath * 0.008 + absf(cos(ph)) * 0.05 * run + 0.04 * r, 0.0)
	body.rotation = Vector3(-0.05 - 0.40 * run + 0.22 * r - 0.1 * w, stride * 0.12 * run, sin(t * 0.8) * 0.03)
	var skirt := parts["skirt"] as MeshInstance3D
	skirt.position = Vector3(0.0, BODY_Y + absf(cos(ph)) * 0.04 * run, 0.0)
	skirt.rotation = Vector3(0.28 * run + sin(ph * 2.0) * 0.05 * run + 0.05 * r, 0.0, stride * 0.05 * run)
	skirt.scale = Vector3(1.0 + 0.08 * run, 1.0 - 0.10 * run, 1.0 + 0.18 * run)
	var head := parts["head"] as MeshInstance3D
	head.rotation = Vector3(0.10 + sin(t * 1.3) * 0.03 + 0.35 * run - 0.45 * r, 1.05 * run + sin(t * 0.7) * 0.10 * (1.0 - run), 0.0)
	for s: int in [-1, 1]:
		var leg := parts["leg_l" if s < 0 else "leg_r"] as MeshInstance3D
		leg.rotation = Vector3(stride * 0.75 * run * s, 0.0, 0.0)
	# hands: at the chest (idle), pumping (run), up and out (raise)
	var l := Vector3(-0.08, 0.28 + breath * 0.01, -0.22)
	var rr := Vector3(0.20, 0.06, -0.18) if not mask else Vector3(0.12, 0.30, -0.24)
	l = l.lerp(Vector3(-0.22, 0.18 - stride * 0.08, 0.10 + stride * 0.22), run)
	rr = rr.lerp(Vector3(0.24, 0.20 + stride * 0.08, -0.10 - stride * 0.22), run)
	l = l.lerp(Vector3(-0.50, 0.98 + sin(t * 2.2) * 0.03, -0.18), r)
	rr = rr.lerp(Vector3(0.46, 1.04 + sin(t * 2.0 + 1.0) * 0.03, -0.20), r)
	aim_limb(parts["arm_l"] as MeshInstance3D, l, ARM_LEN)
	aim_limb(parts["arm_r"] as MeshInstance3D, rr, ARM_LEN)
	# the hands' glow, swelling and pulsing with the raise
	for side: String in ["l", "r"]:
		var aura := parts["aura_" + side] as MeshInstance3D
		var a := r * (0.9 + 0.12 * sin(t * 5.0 + (0.0 if side == "l" else 1.7)))
		aura.scale = Vector3.ONE * maxf(a, 0.001)
		aura.visible = a > 0.01
	# the prop: the staff stands (idle), slants across (run), goes up (raise); the censer hangs and swings
	var prop := parts["prop"] as MeshInstance3D
	var arm_r := parts["arm_r"] as MeshInstance3D
	var up := arm_r.basis.inverse()
	if mask:
		var swing := sin(t * 2.4) * 0.35 * (1.0 - r) + stride * 0.4 * run
		var hang := Basis(Vector3(0, 0, 1), swing * 0.6) * Basis(Vector3(1, 0, 0), swing)
		if r > 0.0:
			hang = hang.slerp(Basis(Vector3(1, 0, 0), PI * 0.92), r)
		prop.basis = up * hang
	else:
		var want := Basis(Vector3(0, 0, 1), 0.05)
		want = want.slerp(Basis(Vector3(1, 0, 0), -1.0) * Basis(Vector3(0, 0, 1), 0.6), run)
		want = want.slerp(Basis(Vector3(0, 0, 1), -0.25), r)
		prop.basis = up * want
	_glow_now = GLOW_GAIN * (1.0 + 0.7 * r)
	_mat.set_shader_parameter("glow_gain", _glow_now)
