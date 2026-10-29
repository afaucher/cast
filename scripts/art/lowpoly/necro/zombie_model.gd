class_name ZombieModel
extends MonsterModel
## LOOK-DEV ONLY (docs/design/necro-look.md): the haunted contracts' zombie (new-themes.md "Ghost house": "slow and tough,
## and they get back up unless burned"). Nothing in the game spawns it: only NecroBody (the gym's necro spawns and the look
## lab). Two models, both in the necro family's look (NecroLook): grey-green dead flesh, dark ragged clothes, the eyes in the
## ghost colour (never the hell family's ember) and the ghost rim on the body.
##   mourner  a tall, lanky corpse in a rotted black burial coat and a torn shirt, hunched, one arm reaching out in front
##            and the other hanging, the head lolled over and the jaw slack. Reads as "the mansion's dead".
##   digger   a squat, barrel-chested, bloated corpse in a torn burlap shroud bound with rope, its small bald head sunk
##            between hunched shoulders and its long heavy arms hanging to its knees. Reads as "the crypt's dead".
## Both are bigger than the skeleton grunt (tough) and lean forward (slow): the grunt is bone-white, upright and marching
## with a sword; these are fleshy, dark, hunched and empty-handed.
##
## Poses: apply_idle(t, speed) stands (a slow sway) or shambles (a lurch onto a dragged left leg, the body rolling side to
## side, the head lolling) from the walk speed; pose_rise(k) lies it face down and pushes it up on its arms (k 0 flat, 1
## about to stand), with motes rising (the "it will get up" tell; no floor ring: "Drop the ring"); stand_up() goes
## back. `charred` builds the burnt one (it stays down): char black, ember cracks, no eye glow, smoke instead of motes.
## Faces local -Z, +X is its right, origin at the feet. Named rigid parts: body, head, jaw, arm_l, arm_r, leg_l, leg_r.

const VARIANTS: Array[String] = ["mourner", "digger"]
const PART_NAMES: Array[String] = ["body", "head", "jaw", "arm_l", "arm_r", "leg_l", "leg_r"]
const WALK_SPEED := 0.9             ## a shamble: the world speed the stride is drawn for
const STRIDE := 3.2                 ## rad / s of the stride

# the dead
const SKIN := Color(0.56, 0.62, 0.48)
const SKIN_LIGHT := Color(0.66, 0.71, 0.56)
const SKIN_DARK := Color(0.40, 0.47, 0.36)
const SKIN_B := Color(0.46, 0.54, 0.45)           ## the digger's darker, mossier flesh
const SKIN_B_LIGHT := Color(0.54, 0.61, 0.50)
const SKIN_B_DARK := Color(0.33, 0.40, 0.33)
const BRUISE := Color(0.42, 0.36, 0.48)
const WOUND := Color(0.36, 0.12, 0.12)
const BONE := Color(0.86, 0.82, 0.70)
const VOID := Color(0.06, 0.05, 0.06)
const TEETH := Color(0.80, 0.76, 0.58)
const HAIR := Color(0.13, 0.12, 0.12)
const MOSS := Color(0.30, 0.38, 0.20)
const DIRT := Color(0.26, 0.20, 0.15)
# the mourner's burial clothes
const COAT := Color(0.17, 0.16, 0.19)
const COAT_LIGHT := Color(0.25, 0.24, 0.28)
const COAT_DARK := Color(0.10, 0.09, 0.11)
const SHIRT := Color(0.70, 0.68, 0.60)
const SHIRT_DARK := Color(0.54, 0.52, 0.46)
const TROUSERS := Color(0.21, 0.20, 0.21)
const BOOT := Color(0.14, 0.11, 0.10)
# the digger's shroud
const SHROUD := Color(0.46, 0.39, 0.29)
const SHROUD_LIGHT := Color(0.55, 0.48, 0.36)
const SHROUD_DARK := Color(0.33, 0.27, 0.20)
const ROPE := Color(0.46, 0.37, 0.24)
# burnt
const CHAR := Color(0.09, 0.075, 0.07)
const CHAR_LIGHT := Color(0.17, 0.15, 0.14)
const ASH := Color(0.36, 0.34, 0.33)
const EMBER := Color(1.0, 0.42, 0.10)

var variant := "mourner"
var charred := false
var body_y := 0.86
var hip_y := 0.80
var leg_x := 0.11
var shoulder := Vector3(0.24, 0.56, 0.0)   ## (the mourner's thin torso: the user, 2026-10-29, "let's make it a thin torso")
var arm_len := 0.72
var lie_h := 0.20                   ## the pelvis's height lying down
var rise_fx: CPUParticles3D         ## motes rising (smoke when charred)
var _lying := false
var _rise := 0.0


func _init(model_variant: String = "mourner", is_charred: bool = false) -> void:
	variant = model_variant if VARIANTS.has(model_variant) else "mourner"
	charred = is_charred
	var digger := variant == "digger"
	_setup_model("ZombieModel", 1.30 if digger else 1.22)
	monster_kind = "zombie"
	_mat = NecroLook.body_material(outline_px, 0.0 if charred else NecroLook.RIM)
	_mat.set_shader_parameter("glow_gain", GLOW_GAIN)
	if digger:
		body_y = 0.66
		hip_y = 0.60
		leg_x = 0.19
		shoulder = Vector3(0.42, 0.50, 0.0)
		arm_len = 0.86
		lie_h = 0.30
	ui_height = (1.55 if digger else 1.80) * scale.x
	has_own_weapon = true
	_build()
	apply_idle(0.0)


## The colour `c` as built: itself, or charred.
func k(c: Color) -> Color:
	if not charred:
		return c
	var lum := c.get_luminance()
	return CHAR.lerp(CHAR_LIGHT, clampf(lum * 1.4, 0.0, 1.0))


## The eyes: the ghost colour glowing, or dead ash when charred.
func eye() -> Color:
	return ASH.darkened(0.5) if charred else NecroLook.glow(0.75)


# ------------------------------------------------------------------ build

func _build() -> void:
	var digger := variant == "digger"
	var body := _add_part("body", _body_digger() if digger else _body_mourner(), self, Vector3(0, body_y, 0))
	var head_at := Vector3(0, 0.64, -0.20) if digger else Vector3(0, 0.80, -0.07)
	var head := _add_part("head", _head_digger() if digger else _head_mourner(), body, head_at)
	_add_part("jaw", _jaw_soup(), head, Vector3(0, -0.10, -0.04) if digger else Vector3(0, -0.12, -0.03))
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		_add_part("arm_" + side, _arm_digger(s) if digger else _arm_mourner(s), body, Vector3(shoulder.x * s, shoulder.y, shoulder.z))
		_add_part("leg_" + side, _leg_digger(s) if digger else _leg_mourner(s), self, Vector3(leg_x * s, hip_y, 0.0))
	if charred:
		_add_embers(body)


## The mourner's torso: thin (the user, 2026-10-29: "let's make it a thin torso"): a narrow, shallow chest tapering to a
## thin waist in the black burial coat, a hunched upper back, its front hanging open on a torn shirt with a gash of flesh
## and two ribs showing, bony sagging shoulders.
func _body_mourner() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(701, 0.07)
	blob(s, Vector3(0, -0.02, 0), Vector3(0.16, 0.10, 0.11), k(TROUSERS), 702, 0.12)                              # hips
	wedge(s, Vector3(0, 0.30, 0.0), Vector2(0.26, 0.18), Vector2(0.42, 0.22), 0.58, k(COAT), 703, Vector3(-4, 0, 0), 0.015)   # coat
	slab(s, Vector3(0, 0.30, -0.105), Vector3(0.15, 0.52, 0.04), k(SHIRT), 704, Vector3(-4, 0, 0), 0.01)            # shirt
	slab(s, Vector3(0.02, 0.26, -0.13), Vector3(0.10, 0.20, 0.03), k(SKIN_DARK), 705, Vector3(-4, 0, 12), 0.012)   # the gash
	for i in 2:
		slab(s, Vector3(0.02, 0.22 + 0.075 * i, -0.145), Vector3(0.09, 0.025, 0.02), k(BONE), 706 + i, Vector3(-4, 0, 12))   # ribs
	slab(s, Vector3(-0.05, 0.10, -0.12), Vector3(0.08, 0.12, 0.025), k(SHIRT_DARK), 708, Vector3(-4, 0, -20), 0.02)   # a torn flap
	for x: float in [-1.0, 1.0]:
		wedge(s, Vector3(0.11 * x, 0.36, -0.12), Vector2(0.06, 0.03), Vector2(0.04, 0.03), 0.46, k(COAT_LIGHT), 709 + int(x), Vector3(-4, 0, -10.0 * x))   # lapels
		blob(s, Vector3(0.21 * x, 0.55, 0.01), Vector3(0.09, 0.07, 0.10), k(COAT), 711 + int(x), 0.12)            # sagging shoulders
	blob(s, Vector3(0, 0.47, 0.08), Vector3(0.17, 0.12, 0.09), k(COAT), 713, 0.1)                                  # the hunched upper back
	# (no coat tails: the user, 2026-10-29: "The coattails definitely don't read. Remove them.")
	limb(s, Vector3(0, 0.56, -0.02), Vector3(0, 0.74, -0.06), 0.075, 0.065, 6, k(SKIN_DARK), 718)              # neck
	slab(s, Vector3(0, 0.58, -0.01), Vector3(0.18, 0.07, 0.18), k(SHIRT_DARK), 719, Vector3.ZERO, 0.02)            # a limp collar
	return s


## The digger's torso: a bloated barrel of bruised flesh in a torn burlap shroud wrapped over one shoulder and bound with
## rope, moss and grave dirt on it, hunched shoulders high round a short neck.
func _body_digger() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(731, 0.08)
	# a barrel of dead flesh, hunched, a burlap shroud wrapped round its hips and belly and over its left shoulder
	blob(s, Vector3(0, 0.30, 0.0), Vector3(0.38, 0.32, 0.30), k(SKIN_B), 732, 0.10, 1)
	blob(s, Vector3(0.0, 0.46, 0.14), Vector3(0.30, 0.12, 0.20), k(SKIN_B_DARK), 733, 0.16)                        # the hump of its back
	blob(s, Vector3(0.14, 0.50, 0.18), Vector3(0.10, 0.04, 0.08), k(BRUISE), 734, 0.2)                             # bruises
	blob(s, Vector3(-0.10, 0.36, -0.28), Vector3(0.08, 0.07, 0.03), k(BRUISE), 735, 0.15)
	blob(s, Vector3(0.32, 0.50, 0.02), Vector3(0.17, 0.12, 0.19), k(SKIN_B_LIGHT), 736, 0.14)                      # the bare shoulder
	blob(s, Vector3(-0.30, 0.50, 0.02), Vector3(0.19, 0.13, 0.22), k(SHROUD_LIGHT), 737, 0.14)                     # the shrouded one
	slab(s, Vector3(-0.10, 0.32, -0.27), Vector3(0.16, 0.50, 0.06), k(SHROUD), 755, Vector3(12, 0, -30), 0.02)      # the shroud's fall over the chest
	slab(s, Vector3(-0.12, 0.34, 0.27), Vector3(0.16, 0.48, 0.06), k(SHROUD_DARK), 756, Vector3(-12, 0, -30), 0.02)
	wedge(s, Vector3(0, 0.07, 0.0), Vector2(0.80, 0.62), Vector2(0.74, 0.58), 0.30, k(SHROUD), 757, Vector3.ZERO, 0.03)   # the wrap
	blob(s, Vector3(0.05, 0.18, -0.27), Vector3(0.22, 0.10, 0.08), k(SKIN_B_LIGHT), 758, 0.12)                     # the belly bulging over it
	for i in 5:
		var x := -0.32 + 0.16 * i
		wedge(s, Vector3(x, -0.08 - 0.03 * (i % 2), -0.27), Vector2(0.15, 0.05), Vector2(0.16, 0.05), 0.18 + 0.06 * (i % 2), k(SHROUD_DARK), 738 + i, Vector3(10, 0, (i - 2) * 7), 0.02)   # ragged hem
		wedge(s, Vector3(x, -0.06 - 0.03 * ((i + 1) % 2), 0.27), Vector2(0.15, 0.05), Vector2(0.16, 0.05), 0.16 + 0.06 * (i % 2), k(SHROUD_DARK), 744 + i, Vector3(-10, 0, (i - 2) * 7), 0.02)
	s.merge(LowPoly.cylinder(0.43, 0.41, 0.06, 8, k(ROPE), 750, 0.01), LowPoly.at(Vector3(0, 0.04, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.76)))   # rope belt
	blob(s, Vector3(0.20, 0.02, -0.33), Vector3(0.05, 0.08, 0.04), k(ROPE), 751, 0.1)                              # its knot
	blob(s, Vector3(-0.24, 0.40, -0.26), Vector3(0.10, 0.06, 0.05), k(MOSS), 752, 0.2)                             # moss
	blob(s, Vector3(0.26, -0.02, -0.29), Vector3(0.10, 0.05, 0.05), k(DIRT), 753, 0.2)                             # grave dirt
	limb(s, Vector3(0, 0.46, -0.08), Vector3(0, 0.58, -0.16), 0.10, 0.09, 6, k(SKIN_B_DARK), 754)                 # the stub of a neck
	return s


## The mourner's head: long and gaunt, sunken dark sockets with the ghost-light eyes, a sharp nose, lank dark hair with a
## bald patch, one ragged ear.
func _head_mourner() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(761, 0.06)
	blob(s, Vector3(0, 0.0, 0), Vector3(0.14, 0.17, 0.15), k(SKIN), 762, 0.10, 1)
	slab(s, Vector3(0, 0.045, -0.12), Vector3(0.24, 0.045, 0.07), k(SKIN_DARK), 763, Vector3(-8, 0, 0), 0.01)        # brow
	for x: int in [-1, 1]:
		blob(s, Vector3(0.058 * x, 0.0, -0.125), Vector3(0.042, 0.036, 0.03), VOID, 764 + x, 0.1)                   # sockets
		blob(s, Vector3(0.058 * x, -0.004, -0.148), Vector3(0.016, 0.016, 0.012), eye(), 766 + x, 0.0)
		blob(s, Vector3(0.10 * x, -0.07, -0.10), Vector3(0.045, 0.04, 0.045), k(SKIN_LIGHT), 768 + x, 0.2)         # cheekbones
	blob(s, Vector3(0.15, 0.0, 0.0), Vector3(0.03, 0.055, 0.04), k(SKIN_DARK), 770, 0.3)                         # the ear
	wedge(s, Vector3(0, -0.04, -0.15), Vector2(0.045, 0.035), Vector2(0.02, 0.02), 0.06, k(SKIN_DARK), 771, Vector3(-30, 0, 0))   # nose
	# lank dark hair: a thin cap with a patch gone, strands hanging down the sides and the back
	blob(s, Vector3(0, 0.09, 0.025), Vector3(0.15, 0.095, 0.15), k(HAIR), 772, 0.12)
	blob(s, Vector3(-0.06, 0.16, -0.02), Vector3(0.06, 0.03, 0.06), k(SKIN_LIGHT), 773, 0.2)                    # the patch
	for i in 5:
		var a := -1.3 + 0.65 * i
		var p := Vector3(sin(a) * 0.135, -0.02, cos(a) * 0.135)
		slab(s, p, Vector3(0.06, 0.22, 0.04), k(HAIR), 774 + i, Vector3(0, rad_to_deg(a), 0), 0.02)
	return s


## The digger's head: small, bald and lumpy, a heavy brow over the ghost-light eyes, stitched across the crown.
func _head_digger() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(781, 0.06)
	blob(s, Vector3.ZERO, Vector3(0.16, 0.15, 0.16), k(SKIN_B), 782, 0.14, 1)
	slab(s, Vector3(0, 0.035, -0.13), Vector3(0.28, 0.06, 0.08), k(SKIN_B_DARK), 783, Vector3(-6, 0, 0), 0.02)       # brow
	for x: int in [-1, 1]:
		blob(s, Vector3(0.062 * x, -0.01, -0.14), Vector3(0.042, 0.032, 0.03), VOID, 784 + x, 0.1)
		blob(s, Vector3(0.062 * x, -0.012, -0.162), Vector3(0.016, 0.016, 0.012), eye(), 786 + x, 0.0)
	blob(s, Vector3(0, -0.06, -0.15), Vector3(0.05, 0.04, 0.04), k(SKIN_B_DARK), 788, 0.2)                       # nose
	for i in 3:
		slab(s, Vector3(-0.08 + 0.08 * i, 0.15, -0.02), Vector3(0.015, 0.02, 0.09), k(VOID.lightened(0.15)), 789 + i, Vector3(0, 20, 0))   # stitches
	slab(s, Vector3(0, 0.15, -0.02), Vector3(0.22, 0.015, 0.015), k(WOUND), 792, Vector3(0, 20, 0))
	return s


## A slack lower jaw, hinged at the back (rotation.x opens it), with a few crooked teeth.
func _jaw_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(801, 0.06)
	var skin := SKIN_B_DARK if variant == "digger" else SKIN_DARK
	wedge(s, Vector3(0, -0.03, -0.07), Vector2(0.15, 0.14), Vector2(0.22, 0.16), 0.07, k(skin), 802)
	slab(s, Vector3(0, 0.005, -0.12), Vector3(0.14, 0.03, 0.04), VOID, 803)
	for i in 3:
		slab(s, Vector3(-0.04 + 0.04 * i, 0.02, -0.135), Vector3(0.025, 0.035, 0.02), k(TEETH), 804 + i, Vector3(0, 0, (i - 1) * 12.0))
	return s


## The mourner's arm: a coat sleeve torn off at the elbow, a thin bare forearm and a long-fingered hand.
func _arm_mourner(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(811 + side, 0.07)
	limb(s, Vector3(0, 0.0, 0), Vector3(0, -0.34, -0.01), 0.080, 0.075, 6, k(COAT), 812 + side)
	wedge(s, Vector3(0, -0.36, -0.01), Vector2(0.17, 0.16), Vector2(0.15, 0.15), 0.06, k(COAT_DARK), 814 + side, Vector3(0, 0, 8.0 * side), 0.02)   # torn cuff
	limb(s, Vector3(0, -0.36, -0.01), Vector3(0, -0.62, -0.02), 0.050, 0.042, 5, k(SKIN), 816 + side)
	blob(s, Vector3(0, -0.66, -0.02), Vector3(0.06, 0.06, 0.05), k(SKIN_LIGHT), 818 + side, 0.15)
	for i in 3:
		limb(s, Vector3(-0.035 + 0.035 * i, -0.68, -0.03), Vector3(-0.045 + 0.045 * i, -0.78, -0.05), 0.016, 0.012, 4, k(SKIN_DARK), 820 + i + side)
	return s


## The digger's arm: a thick bare arm hanging long, a swollen forearm, a big blunt hand.
func _arm_digger(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(831 + side, 0.08)
	limb(s, Vector3(0, -0.02, 0), Vector3(0, -0.38, -0.01), 0.10, 0.09, 6, k(SKIN_B), 832 + side)
	blob(s, Vector3(0, -0.40, -0.01), Vector3(0.09, 0.08, 0.09), k(SKIN_B_DARK), 834 + side, 0.15)
	limb(s, Vector3(0, -0.42, -0.01), Vector3(0, -0.72, -0.02), 0.115, 0.09, 6, k(SKIN_B_LIGHT), 836 + side)
	blob(s, Vector3(0, -0.80, -0.03), Vector3(0.12, 0.11, 0.11), k(SKIN_B), 838 + side, 0.18)
	blob(s, Vector3(0.02 * side, -0.55, -0.10), Vector3(0.06, 0.05, 0.03), k(BRUISE), 840 + side, 0.2)
	return s


## The mourner's leg: a trouser leg, a boot on the right and a bare grey foot on the left (its dragged leg).
func _leg_mourner(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(851 + side, 0.07)
	limb(s, Vector3(0, -0.02, 0), Vector3(0, -0.42, -0.02), 0.085, 0.075, 6, k(TROUSERS), 852 + side)
	limb(s, Vector3(0, -0.42, -0.02), Vector3(0, -0.74, 0.0), 0.075, 0.062, 6, k(TROUSERS.darkened(0.15)), 854 + side)
	if side > 0:
		slab(s, Vector3(0, -0.77, -0.06), Vector3(0.13, 0.08, 0.26), k(BOOT), 856, Vector3.ZERO, 0.01)
	else:
		slab(s, Vector3(0, -0.77, -0.05), Vector3(0.11, 0.06, 0.22), k(SKIN_DARK), 857, Vector3(0, 0, 0), 0.015)
		limb(s, Vector3(0, -0.68, 0), Vector3(0, -0.75, 0), 0.055, 0.05, 5, k(SKIN), 858)
	return s


## The digger's leg: short and thick, the shroud's rags over the knee, a bare broad foot.
func _leg_digger(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(871 + side, 0.08)
	limb(s, Vector3(0, -0.02, 0), Vector3(0, -0.30, -0.02), 0.13, 0.11, 6, k(SKIN_B_DARK), 872 + side)
	blob(s, Vector3(0, -0.24, -0.06), Vector3(0.13, 0.08, 0.11), k(SHROUD_DARK), 874 + side, 0.2)
	limb(s, Vector3(0, -0.30, -0.02), Vector3(0, -0.54, 0.0), 0.11, 0.09, 6, k(SKIN_B), 876 + side)
	slab(s, Vector3(0, -0.57, -0.07), Vector3(0.17, 0.07, 0.28), k(SKIN_B_DARK), 878 + side, Vector3(0, 8.0 * side, 0), 0.02)
	return s


## Burnt: ember cracks glowing in the char on its back and shoulders.
func _add_embers(body: MeshInstance3D) -> void:
	var s := LowPoly.Soup.new(891, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 892 + (7 if variant == "digger" else 0)
	var w := 0.40 if variant == "digger" else 0.26
	for i in 9:
		var p := Vector3(rng.randf_range(-w, w), rng.randf_range(-0.1, 0.55), 0.17 if variant == "mourner" else 0.31)
		slab(s, p, Vector3(rng.randf_range(0.04, 0.08), 0.018, 0.03), glow(EMBER), 893 + i, Vector3(0, 0, rng.randf_range(-70, 70)), 0.0, 0.0)
		slab(s, p * Vector3(1, 1, -1), Vector3(rng.randf_range(0.03, 0.06), 0.016, 0.03), glow(EMBER.darkened(0.2)), 905 + i, Vector3(0, 0, rng.randf_range(-70, 70)), 0.0, 0.0)
	var mi := MeshInstance3D.new()
	mi.name = "Embers"
	mi.mesh = s.to_mesh()
	mi.material_override = _mat
	body.add_child(mi)


# ------------------------------------------------------------------ animation

## Standing (a slow sway, the head lolled) or shambling (speed > 0: a lurch onto the dragged left leg, the body rolling,
## the head lolling with each step). The mourner reaches one arm out in front; the digger's arms hang and swing.
func apply_idle(t: float, speed: float = 0.0) -> void:
	if _downed or _lying:
		return
	var digger := variant == "digger"
	var walk := clampf(speed / WALK_SPEED, 0.0, 1.0)
	var w := wind_e()
	var sw := _swing
	var ph := t * STRIDE
	var stride := sin(ph)
	var breath := sin(t * 1.3)
	var sway := sin(t * 0.7)
	var body := parts["body"] as MeshInstance3D
	var hunch := -0.42 if digger else -0.34
	body.position = Vector3(stride * 0.07 * walk + sway * 0.015, body_y - 0.03 * walk - absf(cos(ph)) * 0.05 * walk + breath * 0.008, 0.0)
	body.rotation = Vector3(hunch - 0.10 * walk - 0.15 * w + 0.30 * sw, stride * 0.16 * walk + sway * 0.05, -stride * 0.24 * walk + (0.06 if not digger else 0.0) + sway * 0.03)
	var head := parts["head"] as MeshInstance3D
	head.rotation = Vector3(0.30 + sin(t * 0.9) * 0.05 + 0.15 * w, sin(t * 0.6) * 0.18, (0.32 if not digger else 0.10) + sin(ph + 0.6) * 0.16 * walk)
	(parts["jaw"] as MeshInstance3D).rotation.x = -0.30 - 0.08 * sin(t * 1.1) - 0.35 * w - 0.2 * sw
	# the right leg strides, the left drags (a stiff short swing, toes out)
	var leg_l := parts["leg_l"] as MeshInstance3D
	var leg_r := parts["leg_r"] as MeshInstance3D
	leg_r.position = Vector3(leg_x, hip_y, 0.0)
	leg_l.position = Vector3(-leg_x, hip_y, 0.0)
	leg_r.rotation = Vector3(stride * 0.55 * walk, 0.0, 0.03)
	leg_l.rotation = Vector3(-stride * 0.22 * walk + 0.10 * walk, 0.35 * walk + 0.1, -0.05)
	var arm_l := parts["arm_l"] as MeshInstance3D
	var arm_r := parts["arm_r"] as MeshInstance3D
	arm_l.scale = Vector3.ONE
	arm_r.scale = Vector3.ONE
	if digger:
		var swing := stride * 0.30 * walk
		arm_r.rotation = Vector3(lerpf(lerpf(0.30 - swing, 2.7, w), 0.7, sw), 0.0, lerpf(0.22, 0.1, w))
		arm_l.rotation = Vector3(lerpf(lerpf(0.30 + swing, 2.7, w), 0.7, sw), 0.0, lerpf(-0.22, -0.1, w))
	else:
		arm_r.rotation = Vector3(lerpf(lerpf(1.75 + sin(t * 0.8) * 0.07 + stride * 0.10 * walk, 2.3, w), 1.3, sw), 0.0, 0.10)
		arm_l.rotation = Vector3(lerpf(lerpf(0.42 - stride * 0.25 * walk, 2.3, w), 1.3, sw), 0.0, -0.14 - 0.05 * sway)


func is_lying() -> bool:
	return _lying


func rise_k() -> float:
	return _rise


## Downed, about to rise: lying face down (k 0, sprawled, cheek on the floor) up to pushed up on both arms with its head
## up and its eyes on you (k 1). The motes rising (or, charred, the smoke) come with it.
func pose_rise(k_rise: float) -> void:
	_lying = true
	_rise = clampf(k_rise, 0.0, 1.0)
	var kk := _rise * _rise * (3.0 - 2.0 * _rise)
	var body := parts["body"] as MeshInstance3D
	var tilt := deg_to_rad(90.0 - 40.0 * kk)
	body.position = Vector3(0.0, lie_h + 0.06 * kk, 0.0)
	body.rotation = Vector3(-tilt, 0.0, 0.12 * (1.0 - kk))
	for s: int in [-1, 1]:
		var leg := parts["leg_l" if s < 0 else "leg_r"] as MeshInstance3D
		leg.position = Vector3(leg_x * s, lie_h * 0.8, 0.02)
		leg.rotation = Vector3(-PI * 0.5 + 0.05, 0.14 * s - 0.06, 0.0)
	var head := parts["head"] as MeshInstance3D
	head.rotation = Vector3(deg_to_rad(25.0 + 55.0 * kk), 0.75 * (1.0 - kk), 0.35 * (1.0 - kk))
	(parts["jaw"] as MeshInstance3D).rotation.x = -0.25 - 0.25 * kk
	# hands: sprawled (one flung forward, one along the side) to planted under the shoulders
	var bt := body.transform
	var inv := bt.affine_inverse()
	for s: int in [-1, 1]:
		var arm := parts["arm_l" if s < 0 else "arm_r"] as MeshInstance3D
		var sh := bt * Vector3(shoulder.x * s, shoulder.y, shoulder.z)
		var flat := Vector3(sh.x + 0.20 * s, 0.06, sh.z - 0.55) if s > 0 else Vector3(sh.x - 0.12, 0.06, sh.z + 0.42)
		var push := Vector3(sh.x * 1.15, 0.05, sh.z - 0.16)
		arm.rotation = Vector3.ZERO
		arm.scale = Vector3.ONE
		aim_limb(arm, inv * flat.lerp(push, kk), arm_len)
	_show_rise(true)


## Back on its feet (out of pose_rise).
func stand_up() -> void:
	_lying = false
	_rise = 0.0
	_show_rise(false)
	apply_idle(_t, 0.0)


func _show_rise(on: bool) -> void:
	# (no glow ring on the floor under it: the user, 2026-10-29, "Drop the ring"; the motes are the tell)
	if on and rise_fx == null:
		if not charred:
			rise_fx = NecroLook.motes(10, 0.4, 0.5, 0.035)
		else:
			rise_fx = NecroLook.smoke(10, 0.35)
		rise_fx.position = Vector3(0.0, 0.25, -0.35)
		add_child(rise_fx)
	if rise_fx != null:
		rise_fx.visible = on
		rise_fx.emitting = on


func _slump() -> void:
	pose_rise(0.0)
