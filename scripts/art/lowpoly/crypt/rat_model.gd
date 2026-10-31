class_name RatModel
extends MonsterModel
## LOOK-DEV ONLY (docs/design/crypt-pests-look.md): a crypt rat, one of the two pests proposed for the haunted contracts
## (new-themes.md "Ghost house", Other enemies; the user, 2026-10-31: "ectoplasm monsters or maybe larger than average
## rats"). Nothing in the game spawns it: only CryptPest (the gym's crypt spawns) and the look lab (crypt_pests_lab.gd).
## The role is the fast swarm (packs of 5-6, like the swarmer imp), so it is built to read as a low, quick, many-legged
## shape at the game camera: a rat the size of a dog (about 0.5 at the shoulder and 1.0 nose to rump, against a hero's
## 2.0), pink naked tail, ears and feet, orange incisors.
##
## Three variants (VARIANTS, their numbers in SPEC):
##   sewer   Sewer brute: a heavy, hunched brown rat, thick neck and a coarse hackle of fur down its spine, a short thick
##           tail, small ears, dark beady eyes (no glow): the realistic rat, scaled up.
##   runner  Crypt runner: long and lean, ash grey, big pink ears, a very long naked tail, eyes glowing in the ghost colour.
##   grave   Grave rat: mangy, the fur in patches over raw grey skin, its ribs and spine showing through on a sunken flank,
##           a bare bony tail, one torn ear, ghost-colour eyes and the dead's rim (NecroLook): the haunted one.
##
## Poses (MonsterModel's hooks): apply_idle(t, speed) crouches and sniffs at rest, or gallops (speed > 0: a bound, the
## front and hind pairs reaching and gathering, the back flexing, the tail streaming); windup(k) rears up on its hind legs,
## front paws up, jaw open (the bite's tell); attack_swing() snaps down and forward into the bite. pose_preview("windup")
## and pose_preview("swing") hold them for the lab.
## Faces local -Z, +X is its right, origin at the feet. Named rigid parts: body (pivots at the hips), head, jaw, tail,
## tail2, leg_fl, leg_fr, leg_hl, leg_hr (the legs hang from the model root and are aimed at their feet every pose).

const VARIANTS: Array[String] = ["sewer", "runner", "grave"]
const NAMES := {"sewer": "Sewer brute", "runner": "Crypt runner", "grave": "Grave rat"}
const PART_NAMES: Array[String] = ["body", "head", "jaw", "tail", "tail2", "leg_fl", "leg_fr", "leg_hl", "leg_hr"]
const RUN_SPEED := 5.2              ## the world speed the gallop is drawn for (the swarmer runs 5.5)
const GAIT := 15.0                  ## rad / s of the gallop
const REST_PITCH := -0.10           ## nose a little down
const REAR_PITCH := 1.15            ## reared up on its haunches
const FOOT_Y := 0.025

## Per variant: len (hips to chest), girth, hip height, tail length and thickness, ear size, the eyes ("glint": dark beads;
## "ghost": the ghost colour, glowing), mange (0..1: bald patches), bones (ribs and spine through the flank), rim (the
## dead's rim), hackle (the spine's tufts), the fur's three shades and the skin.
const SPEC := {
	"sewer": {"len": 0.56, "girth": 1.22, "hip": 0.47, "tail": 0.78, "tail_r": 0.062, "ear": 0.8, "eyes": "glint",
			"mange": 0.08, "bones": false, "rim": 0.0, "hackle": 1.0, "scale": 1.0,
			"fur": Color(0.40, 0.31, 0.23), "fur_light": Color(0.55, 0.44, 0.33), "fur_dark": Color(0.24, 0.18, 0.14),
			"belly": Color(0.66, 0.58, 0.47), "skin": Color(0.74, 0.52, 0.50)},
	"runner": {"len": 0.66, "girth": 0.86, "hip": 0.43, "tail": 1.50, "tail_r": 0.042, "ear": 1.4, "eyes": "ghost",
			"mange": 0.0, "bones": false, "rim": 0.0, "hackle": 0.35, "scale": 1.0,
			"fur": Color(0.55, 0.54, 0.52), "fur_light": Color(0.70, 0.69, 0.66), "fur_dark": Color(0.36, 0.35, 0.35),
			"belly": Color(0.80, 0.78, 0.74), "skin": Color(0.86, 0.60, 0.60)},
	"grave": {"len": 0.60, "girth": 1.0, "hip": 0.45, "tail": 1.05, "tail_r": 0.05, "ear": 1.0, "eyes": "ghost",
			"mange": 0.75, "bones": true, "rim": NecroLook.RIM, "hackle": 0.6, "scale": 1.0,
			"fur": Color(0.45, 0.43, 0.36), "fur_light": Color(0.57, 0.55, 0.47), "fur_dark": Color(0.28, 0.27, 0.23),
			"belly": Color(0.58, 0.56, 0.50), "skin": Color(0.60, 0.55, 0.56)},
}
const NOSE := Color(0.90, 0.56, 0.58)
const EAR_PINK := Color(0.88, 0.58, 0.58)
const PAW := Color(0.86, 0.62, 0.60)
const TAIL := Color(0.80, 0.60, 0.58)
const TOOTH := Color(0.94, 0.66, 0.26)      ## a rat's incisors are orange
const CLAW := Color(0.20, 0.17, 0.15)
const BEAD := Color(0.10, 0.04, 0.05)
const MOUTH := Color(0.38, 0.12, 0.14)
const WHISKER := Color(0.12, 0.10, 0.10)
const BONE := Color(0.86, 0.82, 0.70)
const SCAB := Color(0.42, 0.16, 0.14)

var variant := "sewer"
var spec: Dictionary
var hip_y := 0.47
var body_len := 0.56
var girth := 1.0
var shoulder := Vector3(0.10, -0.07, -0.47)   ## in the body's space (the hips' pivot)
var hip := Vector3(0.13, -0.03, 0.02)
var fl_len := 0.36
var hl_len := 0.42
var _front_z := -0.47                          ## the feet's rest z in the model's space
var _hind_z := 0.06


func _init(model_variant: String = "sewer") -> void:
	variant = model_variant if VARIANTS.has(model_variant) else "sewer"
	spec = SPEC[variant]
	_setup_model("RatModel", float(spec["scale"]))
	monster_kind = "rat"
	glow_flare = 1.2 if str(spec["eyes"]) == "ghost" else 0.5   # the eyes flare in the tell
	if float(spec["rim"]) > 0.0:
		_mat = NecroLook.body_material(outline_px, float(spec["rim"]))
		_mat.set_shader_parameter("glow_gain", GLOW_GAIN)
	hip_y = float(spec["hip"])
	body_len = float(spec["len"])
	girth = float(spec["girth"])
	shoulder = Vector3(0.10 * girth, -0.07, -body_len * 0.82)
	hip = Vector3(0.13 * girth, -0.03, 0.02)
	# the legs' rest lengths: from their joints at the rest pose down to the floor
	var bt := Transform3D(Basis.from_euler(Vector3(REST_PITCH, 0, 0)), Vector3(0, hip_y, 0))
	var s_at := bt * shoulder
	var h_at := bt * hip
	fl_len = s_at.y - FOOT_Y
	hl_len = h_at.y - FOOT_Y
	_front_z = s_at.z - 0.02
	_hind_z = h_at.z + 0.05
	ui_height = (hip_y + 0.32) * scale.x
	has_own_weapon = true
	_build()
	apply_idle(0.0)


func f(c: String) -> Color:
	return spec[c]


## The eyes: dark beads with a wet glint, or the ghost colour glowing.
func eye() -> Color:
	return NecroLook.glow(1.0) if str(spec["eyes"]) == "ghost" else BEAD


# ------------------------------------------------------------------ build

func _build() -> void:
	var body := _add_part("body", _body_soup(), self, Vector3(0, hip_y, 0))
	var head := _add_part("head", _head_soup(), body, Vector3(0, 0.03, -body_len - 0.06))
	_add_part("jaw", _jaw_soup(), head, Vector3(0, -0.065, -0.13))
	var tail := _add_part("tail", _tail_soup(0), body, Vector3(0, -0.01, 0.20))
	_add_part("tail2", _tail_soup(1), tail, Vector3(0, 0, float(spec["tail"]) * 0.5))
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		_add_part("leg_f" + side, _front_leg(s), self, Vector3.ZERO)
		_add_part("leg_h" + side, _hind_leg(s), self, Vector3.ZERO)


## The torso, its pivot at the hips: a big rump, the back arched over the loins, a narrower chest and neck in front, a pale
## belly; a hackle of fur tufts down the spine; bald patches (mange); on the grave rat, ribs and spine through a sunken flank.
func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1101 + VARIANTS.find(variant), 0.08)
	var g := girth
	var L := body_len
	blob(s, Vector3(0, 0.0, 0.04), Vector3(0.19 * g, 0.18 * g, 0.22), f("fur"), 1102, 0.10, 1)                     # rump
	blob(s, Vector3(0, 0.035, -L * 0.42), Vector3(0.17 * g, 0.17 * g, 0.25), f("fur"), 1103, 0.10, 1)              # the arched back
	blob(s, Vector3(0, -0.04, -L * 0.84), Vector3(0.14 * g, 0.15 * g, 0.16), f("fur_light"), 1104, 0.10, 1)        # chest
	blob(s, Vector3(0, -0.09, -L * 0.42), Vector3(0.145 * g, 0.09, 0.28), f("belly"), 1105, 0.12)                  # belly
	blob(s, Vector3(0, 0.0, -L - 0.01), Vector3(0.11 * g, 0.11 * g, 0.12), f("fur"), 1106, 0.12)                   # neck
	# the hackle: tufts lying back along the spine, longer over the shoulders
	var n := 7
	for i in n:
		var u := float(i) / float(n - 1)
		var z := lerpf(0.10, -L * 0.95, u)
		var top := 0.01 + 0.17 * g + 0.03 * sin(u * PI)
		var h := (0.03 + 0.04 * sin(u * PI)) * float(spec["hackle"]) + 0.015
		wedge(s, Vector3(0.012 * ((i % 3) - 1), top - 0.01, z), Vector2(0.09 * g, 0.07), Vector2(0.02, 0.015), h, f("fur_dark").lerp(f("fur"), 1.0 - float(spec["hackle"])), 1110 + i, Vector3(64, 0, 9.0 * ((i % 3) - 1)), 0.01)
	# shaggy flanks: a few tufts down each side
	for sd: int in [-1, 1]:
		for i in 3:
			var z2 := -L * (0.15 + 0.3 * i)
			wedge(s, Vector3(0.165 * g * sd, -0.06, z2), Vector2(0.05, 0.05), Vector2(0.01, 0.01), 0.07, f("fur_dark"), 1120 + i + 3 * (sd + 1), Vector3(40, 0, -100.0 * sd), 0.01)
	# mange: bald patches of raw skin, a scab or two
	var rng := RandomNumberGenerator.new()
	rng.seed = 1131 + VARIANTS.find(variant)
	var patches := roundi(float(spec["mange"]) * 9.0)
	for i in patches:
		var sd := -1.0 if i % 2 == 0 else 1.0
		var p := Vector3(0.165 * g * sd, rng.randf_range(-0.04, 0.12), rng.randf_range(-L * 0.85, 0.08))
		blob(s, p, Vector3(0.035, rng.randf_range(0.05, 0.08), rng.randf_range(0.06, 0.10)), f("skin"), 1140 + i, 0.2)
		if i % 3 == 1:
			blob(s, p + Vector3(0.025 * sd, 0.0, 0.02), Vector3(0.02, 0.025, 0.03), SCAB, 1160 + i, 0.2)
	if bool(spec["bones"]):
		for sd: float in [-1.0, 1.0]:
			blob(s, Vector3(0.15 * g * sd, 0.02, -L * 0.48), Vector3(0.05, 0.12, 0.17), f("skin").darkened(0.35), 1170 + int(sd), 0.15)   # the sunken flank
			for i in 4:
				var z3 := -L * (0.30 + 0.12 * i)
				limb(s, Vector3(0.10 * g * sd, 0.15 * g, z3), Vector3(0.19 * g * sd, -0.05, z3 - 0.03), 0.019, 0.014, 4, BONE, 1175 + i + 4 * int(sd + 1))   # ribs
		for i in 5:
			blob(s, Vector3(0, 0.17 * g + 0.015, 0.05 - L * 0.22 * i), Vector3(0.03, 0.025, 0.035), BONE, 1185 + i, 0.15)   # the spine's knobs
	return s


## The head, its pivot at the neck: a skull, full cheeks, a long tapering snout with a pink nose, orange incisors under it,
## eyes, round ears (pink inside; the grave rat's left one torn), whiskers.
func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1201 + VARIANTS.find(variant), 0.07)
	var ear := float(spec["ear"])
	blob(s, Vector3(0, 0.0, -0.07), Vector3(0.105, 0.095, 0.12), f("fur"), 1202, 0.10, 1)                          # skull
	blob(s, Vector3(0, -0.035, -0.14), Vector3(0.09, 0.07, 0.09), f("fur_light"), 1203, 0.12)                      # cheeks
	wedge(s, Vector3(0, -0.03, -0.235), Vector2(0.13, 0.11), Vector2(0.05, 0.045), 0.17, f("fur_light"), 1204, Vector3(-90, 0, 0), 0.01)   # snout
	blob(s, Vector3(0, -0.015, -0.322), Vector3(0.032, 0.026, 0.026), NOSE, 1205, 0.1)                             # nose
	for x: int in [-1, 1]:
		var big := 1.25 if str(spec["eyes"]) == "ghost" else 1.0
		blob(s, Vector3(0.062 * x, 0.022, -0.155), Vector3(0.028, 0.028, 0.022) * big, eye(), 1206 + x, 0.0)
		if str(spec["eyes"]) != "ghost":
			blob(s, Vector3(0.066 * x, 0.034, -0.172), Vector3(0.008, 0.008, 0.006), Color(0.95, 0.92, 0.88), 1208 + x, 0.0)   # the glint
		var torn := variant == "grave" and x < 0
		var er := ear * (0.7 if torn else 1.0)
		var at := Vector3(0.085 * x, 0.085, -0.02)
		blob(s, at, Vector3(0.068 * er, 0.075 * er, 0.018), f("fur_dark"), 1210 + x, 0.15, 0, Vector3(0, 28.0 * x, 18.0 * x))
		blob(s, at + Vector3(0.004 * x, 0.004, -0.012), Vector3(0.05 * er, 0.058 * er, 0.01), EAR_PINK, 1212 + x, 0.15, 0, Vector3(0, 28.0 * x, 18.0 * x))
		if torn:
			slab(s, at + Vector3(0.03 * x, 0.06 * er, -0.005), Vector3(0.04, 0.03, 0.03), SCAB, 1214, Vector3(0, 0, 30))
		for i in 3:
			slab(s, Vector3(0.10 * x, -0.03 - 0.012 * i, -0.27), Vector3(0.17, 0.006, 0.006), WHISKER, 1216 + i + 3 * (x + 1), Vector3(0, (14.0 - 12.0 * i) * x, (6.0 - 6.0 * i) * x), 0.0, 0.0)
	for x: float in [-1.0, 1.0]:
		slab(s, Vector3(0.013 * x, -0.075, -0.305), Vector3(0.022, 0.06, 0.016), TOOTH, 1224 + int(x), Vector3(-8, 0, 0))   # incisors
	return s


## The lower jaw, hinged at the back (rotation.x below 0 opens it): a chin, the mouth's dark inside, two lower incisors.
func _jaw_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1231, 0.07)
	blob(s, Vector3(0, -0.012, -0.085), Vector3(0.05, 0.026, 0.09), f("fur_light"), 1232, 0.12)
	slab(s, Vector3(0, 0.008, -0.09), Vector3(0.065, 0.012, 0.12), MOUTH, 1233)
	for x: float in [-1.0, 1.0]:
		slab(s, Vector3(0.011 * x, 0.02, -0.168), Vector3(0.018, 0.045, 0.014), TOOTH, 1234 + int(x), Vector3(10, 0, 0))
	return s


## A half of the tail, running +Z from its pivot: the root half (0) thick, the tip half (1) tapering to a point; scaly rings
## (the grave rat's are knobbed vertebrae).
func _tail_soup(half: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1241 + half, 0.12)
	var tl := float(spec["tail"]) * 0.5
	var r0 := float(spec["tail_r"]) * (1.0 if half == 0 else 0.62)
	var r1 := float(spec["tail_r"]) * (0.62 if half == 0 else 0.12)
	var col := TAIL.lerp(f("fur_dark"), 0.35) if variant == "sewer" else (TAIL.lerp(f("skin"), 0.6) if variant == "grave" else TAIL)
	limb(s, Vector3.ZERO, Vector3(0, 0, tl + 0.01), r0, r1, 5, col, 1243 + half)
	if half == 0:
		blob(s, Vector3(0, 0, 0.02), Vector3(r0 * 1.5, r0 * 1.5, 0.06), f("fur"), 1245, 0.1)   # the fur's end
	if variant == "grave":
		for i in 4:
			var u := (float(i) + 0.5) / 4.0
			var r := lerpf(r0, r1, u)
			blob(s, Vector3(0, 0, tl * u), Vector3(r * 1.35, r * 1.35, r * 0.8), BONE.darkened(0.15), 1250 + i + 4 * half, 0.1)
	return s


## A front leg hanging -Y from the shoulder: a furred upper arm, a thin pink-skinned forearm, a small hand with dark claws.
func _front_leg(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1261 + side, 0.07)
	var g := girth
	blob(s, Vector3(0, -0.04, 0), Vector3(0.06 * g, 0.10, 0.07), f("fur"), 1262 + side, 0.12)
	limb(s, Vector3(0, -0.08, 0), Vector3(0, -fl_len + 0.02, -0.01), 0.04 * g, 0.026, 5, f("fur_light"), 1264 + side)
	blob(s, Vector3(0, -fl_len + 0.012, -0.03), Vector3(0.036, 0.016, 0.045), PAW, 1266 + side, 0.15)
	for i in 3:
		limb(s, Vector3(-0.02 + 0.02 * i, -fl_len + 0.01, -0.06), Vector3(-0.024 + 0.024 * i, -fl_len - 0.002, -0.09), 0.008, 0.004, 3, CLAW, 1268 + i + side)
	return s


## A hind leg hanging -Y from the hip: a big furred haunch, a shin, the long pink foot flat along -Z.
func _hind_leg(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1281 + side, 0.07)
	var g := girth
	blob(s, Vector3(0, -0.07, 0.01), Vector3(0.085 * g, 0.13, 0.12), f("fur"), 1282 + side, 0.12)
	limb(s, Vector3(0, -0.16, 0.04), Vector3(0, -hl_len + 0.03, 0.05), 0.045 * g, 0.028, 5, f("fur_light"), 1284 + side)
	slab(s, Vector3(0, -hl_len + 0.012, -0.03), Vector3(0.055, 0.024, 0.17), PAW, 1286 + side, Vector3.ZERO, 0.01)
	for i in 3:
		limb(s, Vector3(-0.02 + 0.02 * i, -hl_len + 0.01, -0.11), Vector3(-0.026 + 0.026 * i, -hl_len - 0.002, -0.145), 0.008, 0.004, 3, CLAW, 1288 + i + side)
	return s


# ------------------------------------------------------------------ animation

## Rest (a crouch, the head sniffing, the tail curled on the floor) or the gallop (speed > 0), with the wind-up (reared up,
## paws raised, jaw open) and the bite (snapped down and forward, the jaw shutting) blended over it.
func apply_idle(t: float, speed: float = 0.0) -> void:
	if _downed:
		return
	var walk := clampf(speed / RUN_SPEED, 0.0, 1.0)
	var w := wind_e()
	var sw := _swing
	var ph := t * GAIT
	var sniff := maxf(0.0, sin(t * 0.9)) * (1.0 - walk)
	# the body: the bound pitches and lifts it and stretches the back
	var pitch := REST_PITCH + 0.17 * walk * sin(ph) + 0.015 * sin(t * 1.7) * (1.0 - walk)
	var by := hip_y - 0.03 * (1.0 - walk) + 0.05 * walk * (0.5 - 0.5 * cos(2.0 * ph)) + 0.004 * sin(t * 2.3)
	var bz := 0.0
	var stretch := 1.0 + 0.08 * walk * cos(ph)
	pitch = lerpf(pitch, REAR_PITCH, w)
	by = lerpf(by, hip_y - 0.08, w)
	bz = lerpf(bz, 0.08, w)
	pitch = lerpf(pitch, 0.18, sw)
	by = lerpf(by, hip_y - 0.04, sw)
	bz = lerpf(bz, -0.36, sw)
	stretch = lerpf(stretch, 1.1, sw)
	var body := parts["body"] as MeshInstance3D
	body.position = Vector3(0.0, by, bz)
	body.rotation = Vector3(pitch, 0.05 * sin(t * 0.6) * (1.0 - walk), 0.06 * walk * sin(ph + 0.5))
	body.scale = Vector3(1.0, 1.0, stretch)
	# the head: level in the gallop, sniffing at rest, down at the hero when reared, thrust out in the bite
	var head := parts["head"] as MeshInstance3D
	var hx := 0.10 + 0.05 * sin(t * 11.0) * sniff - pitch * 0.6 * walk
	hx = lerpf(hx, -0.55, w)
	hx = lerpf(hx, -0.20, sw)
	head.rotation = Vector3(hx, 0.3 * sin(t * 0.5) * (1.0 - walk) * (1.0 - w), 0.0)
	(parts["jaw"] as MeshInstance3D).rotation.x = lerpf(lerpf(-0.04 - 0.05 * sniff, -1.05, w), -0.12, sw)
	# the tail: down to the floor and curled along it at rest (and reared: a prop behind it), streaming in the gallop. The
	# angles are the world's (below the horizontal), so a long tail and a short one both just reach the floor.
	var tail := parts["tail"] as MeshInstance3D
	var tail2 := parts["tail2"] as MeshInstance3D
	var root := body.transform * tail.position
	var down := asin(clampf((root.y - 0.04) / (float(spec["tail"]) * 0.5), 0.0, 0.98))
	var a1 := lerpf(down, minf(0.24, down), walk)
	var a2 := lerpf(-0.04, 0.06, walk)
	a1 = lerpf(a1, down, w)
	a2 = lerpf(a2, -0.04, w)
	a1 = lerpf(a1, minf(0.30, down), sw)
	a2 = lerpf(a2, 0.04, sw)
	var t1y := lerpf(0.25, 0.28 * sin(ph * 0.5), walk)
	var t2y := lerpf(0.55, 0.35 * sin(ph * 0.5 - 0.9), walk)
	tail.rotation = Vector3(a1 - pitch, t1y, 0.0)
	tail2.rotation = Vector3(a2 - a1, t2y, 0.0)
	# the legs, aimed at their feet: the gallop's reach and gather, the reared stance, the bite's planted reach
	var bt := body.transform
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var lf := parts["leg_f" + side] as MeshInstance3D
		var lh := parts["leg_h" + side] as MeshInstance3D
		var sh := bt * Vector3(shoulder.x * s, shoulder.y, shoulder.z)
		var hp := bt * Vector3(hip.x * s, hip.y, hip.z)
		lf.position = sh
		lh.position = hp
		var pf := ph + (0.35 if s > 0 else 0.0)
		var phh := ph + 0.7 + (0.3 if s > 0 else 0.0)
		var front := Vector3(shoulder.x * s * 1.05, FOOT_Y + maxf(0.0, sin(pf)) * 0.14 * walk, _front_z + bz - 0.24 * walk * cos(pf))
		var hind := Vector3(hip.x * s * 1.05, FOOT_Y + maxf(0.0, sin(phh)) * 0.12 * walk, _hind_z + bz + 0.24 * walk * cos(phh))
		front = front.lerp(sh + Vector3(0.13 * s, -0.10, -0.12), w)     # paws up and spread, claws out
		hind = hind.lerp(Vector3(hip.x * s * 1.3, FOOT_Y, hp.z - 0.10), w)
		front = front.lerp(Vector3(shoulder.x * s * 1.15, FOOT_Y, sh.z - 0.24), sw)
		hind = hind.lerp(Vector3(hip.x * s * 1.05, FOOT_Y, _hind_z + 0.10), sw)
		aim_limb(lf, front, fl_len)
		aim_limb(lh, hind, hl_len)


func _slump() -> void:
	var body := parts["body"] as MeshInstance3D
	body.position = Vector3(0, 0.2, 0)
	body.rotation = Vector3(0, 0, 1.4)
