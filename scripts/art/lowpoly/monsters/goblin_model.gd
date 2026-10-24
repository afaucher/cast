class_name GoblinModel
extends MonsterModel
## Goblin scout ("Lookout"): a lanky, hunched hall-walker in a patched leather jerkin, with brass goggles
## (the glowing enemy eyes), huge sideways ears, a long nose, and a wooden backpack rack of FIREWORKS (five
## striped rockets in a crate) with a little orange pennant on a pole. He carries a long smouldering match
## in his right hand. Design: docs/design/goblin-scout.md.
##
## Silhouette from the iso camera: a T of ears over a fan of red / gold rocket cones and a flag, on a thin
## body. Nothing else on the floor has that top shape (imps are round with upright bat ears, the archer is
## a hood and a bow, the skeleton a sword, the brute a mass).
##
## Live since monster awareness step 2: scripts/monsters/goblin.gd (kind "goblin") drives the hooks below from
## its phases (Goblin._pose).
##
## Hooks (on top of MonsterModel's windup / attack_swing / set_downed / set_tint / set_fade):
##   windup(t)          LIGHTING THE FUSE: crouch, fuse end up in the left hand, the match brought to it
##                      (the ember flares with the enemy glow). The scout's telegraph.
##   attack_swing()     the cornered firecracker toss (left arm snaps forward).
##   set_alert(k)       the "!" moment: a startled hop, ears straight up, arms flung up, the "!" mark pops.
##   set_look(k, phase) a look-around stop: upright, left hand shading the goggles, head sweeping
##                      (phase 0..1 is one sweep, left -> right -> left).
##   set_fuse_lit(on)   sparks spit from the rack while the fuse burns; while running he glances back.
##   set_loaded(on)     rockets in the rack (false after the volley).
##   set_cower(k)       crouched with the arms over the head (after the volley, behind the pack).
##   set_mark(on)       keep the "!" up after the startle (it stays over him until the volley or until he is
##                      stopped: the "!" means the clock is running).
## Walk (patrol amble, ~2.2) and run (flee, ~5.2) come from apply_idle's speed, as for every model.
##
## Faces local -Z, +X is his right. At MODEL_SCALE 1.12: about 1.8 to the cap, ~1.4 across the ears, rocket
## tips ~2.25, the pennant pole ~2.75 (Wick is 2.27 to his hat tip, the skeleton 2.22, an imp 0.92). Rigid named parts (MeshInstance3D): body, head, ear_l, ear_r, arm_l, arm_r, leg_l,
## leg_r, rack, rockets, flag, match, spark, mark. head / arms / rack / match hang under body; ears under
## head; rockets / flag / spark under rack; legs and the "!" mark (kept upright) under the root.

const MODEL_SCALE := 1.12
const PART_NAMES: Array[String] = ["body", "head", "ear_l", "ear_r", "arm_l", "arm_r", "leg_l", "leg_r",
		"rack", "rockets", "flag", "match", "spark", "mark"]

const SKIN := Color(0.56, 0.64, 0.24)
const SKIN_LIGHT := Color(0.68, 0.76, 0.32)
const SKIN_DARK := Color(0.40, 0.48, 0.16)
const EAR_INNER := Color(0.86, 0.52, 0.40)
const LEATHER := Color(0.42, 0.27, 0.15)
const LEATHER_LIGHT := Color(0.56, 0.37, 0.20)
const LEATHER_DARK := Color(0.24, 0.15, 0.09)
const SHIRT := Color(0.80, 0.72, 0.52)
const TROUSERS := Color(0.34, 0.30, 0.28)
const SCARF := Color(0.86, 0.36, 0.12)
const BRASS := Color(0.86, 0.68, 0.30)
const LENS := Color(1.0, 0.70, 0.12)           ## goggle lenses: the enemy glow
const MOUTH := Color(0.16, 0.06, 0.05)
const TOOTH := Color(0.96, 0.92, 0.76)
const WOOD := Color(0.52, 0.35, 0.20)
const WOOD_LIGHT := Color(0.68, 0.50, 0.30)
const WOOD_DARK := Color(0.30, 0.19, 0.11)
const ROCKET_RED := Color(0.86, 0.16, 0.12)
const ROCKET_GOLD := Color(0.98, 0.76, 0.18)
const ROCKET_LIME := Color(0.60, 0.86, 0.20)
const PAPER := Color(0.97, 0.94, 0.84)
const FUSE := Color(0.70, 0.60, 0.40)
const FLAG := Color(0.95, 0.42, 0.10)
const FLAG_STAR := Color(1.0, 0.86, 0.26)
const EMBER := Color(1.0, 0.42, 0.08)
const SPARK := Color(1.0, 0.96, 0.58)
const MARK := Color(1.0, 0.30, 0.10)

const HIP_Y := 0.60
const LEG_X := 0.12
const SHOULDER := Vector3(0.24, 0.42, -0.08)     ## body-local, mirrored for the left arm
const ARM_LEN := 0.60
const HEAD_AT := Vector3(0.0, 0.58, -0.17)
const RACK_AT := Vector3(0.0, 0.26, 0.14)
const MARK_Y := 2.62
const MATCH_LEN := 0.62
const FUSE_AT := Vector3(0.27, 0.60, 0.02)       ## rack-local: the fuse's end, sticking up over his right shoulder
const LIGHT_DIR := Vector3(-0.547, 0.753, 0.365)   ## body-local: the match, arm out to the right, tipped up at the fuse

## Pose state (all 0 / default at rest, so windup(0) and apply_idle return to the same rest pose).
var alert_k := 0.0
var look_k := 0.0
var look_phase := 0.0
var cower_k := 0.0
var fuse_lit := false
var loaded := true
var mark_on := false


func _init() -> void:
	_setup_model("GoblinModel", MODEL_SCALE)
	monster_kind = "goblin"
	ui_height = 2.30 * MODEL_SCALE
	has_own_weapon = true
	glow_flare = 0.9      # the match ember flares hard while he lights the fuse
	_build()
	apply_idle(0.0)


# ------------------------------------------------------------------ public pose hooks

func set_alert(k: float) -> void:
	alert_k = clampf(k, 0.0, 1.0)
	_refresh()


func set_look(k: float, phase: float = 0.0) -> void:
	look_k = clampf(k, 0.0, 1.0)
	look_phase = phase
	_refresh()


func set_cower(k: float) -> void:
	cower_k = clampf(k, 0.0, 1.0)
	_refresh()


func set_fuse_lit(on: bool) -> void:
	fuse_lit = on
	_refresh()


func set_loaded(on: bool) -> void:
	loaded = on
	_refresh()


func set_mark(on: bool) -> void:
	mark_on = on
	_refresh()


## Where the rockets leave the rack, in world space (the FireworksFx launch point).
func launch_point() -> Vector3:
	var rack := parts["rack"] as MeshInstance3D
	return rack.global_transform * Vector3(0.0, 0.75, 0.05)


## Frozen poses for the lab: MonsterModel's "rest" / "windup" / "swing", plus "patrol" (mid-stride amble),
## "look", "alert", "light" (= windup), "fuse_run" (fleeing with the fuse lit), "throw" (= swing), "cower"
## (empty rack). k scales the pose.
func pose_scout(kind: String, k: float = 1.0) -> void:
	alert_k = 0.0
	look_k = 0.0
	look_phase = 0.0
	cower_k = 0.0
	fuse_lit = false
	loaded = true
	mark_on = false
	_wind = 0.0
	_swing = 0.0
	var t := 0.6
	var spd := 0.0
	match kind:
		"patrol":
			t = 0.35
			spd = 2.2
		"look":
			look_k = k
			look_phase = 0.2
		"alert":
			alert_k = k
		"light", "windup":
			_wind = clampf(k, 0.0, 1.0)
			mark_on = true
		"fuse_run":
			fuse_lit = true
			mark_on = true
			t = 0.41
			spd = 5.2
		"run":
			t = 0.41
			spd = 5.2
		"throw", "swing":
			_swing = clampf(k, 0.0, 1.0)
			loaded = false
		"cower":
			cower_k = k
			loaded = false
	_update_glow()
	apply_idle(t, spd)


func pose_preview(kind: String, k: float = 1.0) -> void:
	pose_scout(kind, k)


## A stand-alone "!" for other monsters in a lab (the awareness layer owns the real one).
static func make_alert_mark() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "AlertMark"
	mi.mesh = _mark_soup().to_mesh()
	mi.material_override = MonsterMaterial.make(2.0)
	return mi


# ------------------------------------------------------------------ build

func _build() -> void:
	var body := _add_part("body", _body_soup(), self, Vector3(0, HIP_Y, 0))
	var head := _add_part("head", _head_soup(), body, HEAD_AT)
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		_add_part("ear_" + side, _ear_soup(s), head, Vector3(0.165 * s, 0.12, 0.02))
		_add_part("arm_" + side, _arm_soup(s), body, Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z))
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(LEG_X * s, HIP_Y, 0.0))
	var rack := _add_part("rack", _rack_soup(), body, RACK_AT)
	_add_part("rockets", _rockets_soup(), rack, Vector3.ZERO)
	_add_part("flag", _flag_soup(), rack, Vector3(-0.20, 0.80, 0.10))
	_add_part("spark", _spark_soup(), rack, FUSE_AT)
	_add_part("match", _match_soup(), body, Vector3(0.3, -0.1, -0.2))
	_add_part("mark", _mark_soup(), self, Vector3(0.0, MARK_Y, -0.05))


## Hunched torso in a patched leather jerkin, a scarf, a belt with pouches and a bandolier of firecrackers.
func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1201, 0.08)
	blob(s, Vector3(0, 0.02, 0.0), Vector3(0.19, 0.12, 0.15), TROUSERS, 1202, 0.12)                       # seat
	limb(s, Vector3(0, 0.04, 0.0), Vector3(0, 0.42, -0.10), 0.17, 0.19, 6, LEATHER, 1203, 0.02)          # jerkin
	blob(s, Vector3(0, 0.42, -0.09), Vector3(0.24, 0.11, 0.17), LEATHER_LIGHT, 1204, 0.14)               # shoulders
	slab(s, Vector3(0.07, 0.22, -0.19), Vector3(0.10, 0.10, 0.03), SHIRT, 1205, Vector3(0, 0, 12), 0.01)   # patch
	slab(s, Vector3(0, 0.08, -0.01), Vector3(0.40, 0.06, 0.33), LEATHER_DARK, 1206, Vector3.ZERO, 0.01)   # belt
	slab(s, Vector3(0, 0.08, -0.175), Vector3(0.07, 0.07, 0.03), BRASS, 1207, Vector3.ZERO, 0.0, 0.03)    # buckle
	slab(s, Vector3(-0.20, 0.02, -0.08), Vector3(0.10, 0.13, 0.10), LEATHER, 1208, Vector3(0, 15, 0), 0.01)   # pouch
	slab(s, Vector3(0.20, 0.03, -0.05), Vector3(0.08, 0.11, 0.09), LEATHER_DARK, 1209, Vector3(0, -10, 0), 0.01)
	# bandolier: left shoulder to right hip across the front, four red firecrackers on it
	slab(s, Vector3(0.0, 0.25, -0.185), Vector3(0.06, 0.50, 0.03), LEATHER_DARK, 1210, Vector3(-8, 0, 38), 0.0)
	for i in 4:
		var u := float(i) / 3.0
		var p := Vector3(lerpf(-0.11, 0.10, u), lerpf(0.39, 0.12, u), -0.21)
		limb(s, p + Vector3(-0.012, -0.05, 0), p + Vector3(0.012, 0.05, 0), 0.026, 0.026, 5, ROCKET_RED, 1211 + i, 0.0, 0.04)
		limb(s, p + Vector3(0.012, 0.05, 0), p + Vector3(0.02, 0.085, -0.01), 0.008, 0.008, 3, FUSE, 1215 + i, 0.0, 0.0)
	# scarf and its tail, flapping back over the rack strap
	blob(s, Vector3(0, 0.52, -0.12), Vector3(0.16, 0.06, 0.14), SCARF, 1220, 0.15)
	limb(s, Vector3(0.07, 0.52, -0.02), Vector3(0.14, 0.40, 0.18), 0.05, 0.02, 4, SCARF, 1221, 0.01)
	# rack straps over the shoulders
	for x: int in [-1, 1]:
		slab(s, Vector3(0.13 * x, 0.34, -0.19), Vector3(0.05, 0.22, 0.03), LEATHER_DARK, 1222 + x, Vector3(-10, 0, 0), 0.0)
	return s


## Big head: a long nose, a crooked grin, brass goggles with glowing amber lenses, an aviator cap.
func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1231, 0.08)
	blob(s, Vector3(0, 0.12, -0.02), Vector3(0.19, 0.16, 0.18), SKIN, 1232, 0.1, 1)                      # skull
	blob(s, Vector3(0, 0.02, -0.08), Vector3(0.14, 0.07, 0.12), SKIN_DARK, 1233, 0.14)                    # jaw
	limb(s, Vector3(0, 0.08, -0.17), Vector3(0, 0.0, -0.37), 0.055, 0.0, 5, SKIN_LIGHT, 1234, 0.0)       # long nose
	slab(s, Vector3(0, 0.0, -0.175), Vector3(0.15, 0.03, 0.04), MOUTH, 1235, Vector3(0, 0, -6), 0.0, 0.0)  # grin
	limb(s, Vector3(0.04, 0.01, -0.19), Vector3(0.045, -0.04, -0.19), 0.018, 0.0, 4, TOOTH, 1236, 0.0, 0.0)   # snaggle tooth
	slab(s, Vector3(0, 0.13, 0.0), Vector3(0.40, 0.045, 0.38), LEATHER_DARK, 1237, Vector3.ZERO, 0.0)    # goggle strap
	for x: int in [-1, 1]:
		var at := Vector3(0.085 * x, 0.135, -0.175)
		s.merge(LowPoly.cylinder(0.068, 0.068, 0.07, 6, BRASS, 1238 + x, 0.0), LowPoly.at(at, Vector3(90, 0, 0)))
		s.merge(LowPoly.cylinder(0.05, 0.05, 0.02, 6, glow(LENS), 1240 + x, 0.0, 1, 0.0), LowPoly.at(at + Vector3(0, 0, -0.035), Vector3(90, 0, 0)))
	blob(s, Vector3(0, 0.22, 0.03), Vector3(0.17, 0.09, 0.17), LEATHER, 1243, 0.12)                     # cap
	limb(s, Vector3(0, 0.27, 0.10), Vector3(0.02, 0.36, 0.20), 0.04, 0.0, 4, LEATHER_DARK, 1244, 0.0)    # cap tuft
	return s


## A long sideways ear (the signature shape from above), with a pink inner and a brass ring.
func _ear_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1251 + side, 0.07)
	var sd := float(side)
	limb(s, Vector3(0, 0, 0), Vector3(0.46 * sd, 0.10, 0.10), 0.085, 0.0, 4, SKIN, 1252 + side, 0.0)
	limb(s, Vector3(0.03 * sd, 0.0, -0.035), Vector3(0.34 * sd, 0.075, 0.05), 0.045, 0.0, 4, EAR_INNER, 1254 + side, 0.0)
	blob(s, Vector3(0.20 * sd, -0.035, 0.05), Vector3(0.03, 0.03, 0.03), BRASS, 1256 + side, 0.1)
	return s


## A long thin arm: cream shirt sleeve, green forearm, a big three-fingered hand. Hangs from the shoulder.
func _arm_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1261 + side, 0.07)
	blob(s, Vector3.ZERO, Vector3(0.08, 0.08, 0.08), LEATHER_LIGHT, 1262 + side, 0.15)
	limb(s, Vector3(0, 0, 0), Vector3(0, -0.27, 0.0), 0.065, 0.055, 5, SHIRT, 1264 + side, 0.01)
	limb(s, Vector3(0, -0.26, 0.0), Vector3(0, -0.52, -0.01), 0.048, 0.042, 5, SKIN, 1266 + side)
	blob(s, Vector3(0, -0.57, -0.02), Vector3(0.07, 0.07, 0.06), SKIN_DARK, 1268 + side, 0.15)
	for i in 3:
		var x := (float(i) - 1.0) * 0.035
		limb(s, Vector3(x, -0.61, -0.03), Vector3(x * 1.3, -0.69, -0.05), 0.022, 0.0, 4, SKIN_DARK, 1270 + i + 3 * side, 0.0, 0.03)
	return s


## Thin bent leg in patched trousers, a bare green shin and a long pointed bare foot.
func _leg_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1281 + side, 0.07)
	limb(s, Vector3(0, 0.0, 0), Vector3(0, -0.29, -0.07), 0.075, 0.058, 5, TROUSERS, 1282 + side)
	blob(s, Vector3(0, -0.29, -0.07), Vector3(0.065, 0.06, 0.065), TROUSERS, 1284 + side, 0.12)
	limb(s, Vector3(0, -0.30, -0.06), Vector3(0, -0.54, 0.02), 0.05, 0.04, 5, SKIN, 1286 + side)
	blob(s, Vector3(0, -0.57, -0.05), Vector3(0.075, 0.04, 0.15), SKIN_DARK, 1288 + side, 0.12)
	limb(s, Vector3(0, -0.57, -0.17), Vector3(0, -0.55, -0.29), 0.045, 0.0, 4, SKIN_DARK, 1290 + side, 0.0)   # pointed toes
	return s


## The backpack rack: two poles, slats, a crate at the bottom holding the rockets, a coil of fuse.
func _rack_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1301, 0.07)
	for x: int in [-1, 1]:
		slab(s, Vector3(0.20 * x, 0.30, 0.06), Vector3(0.05, 1.10, 0.05), WOOD, 1302 + x, Vector3.ZERO, 0.01)
		limb(s, Vector3(0.20 * x, 0.85, 0.06), Vector3(0.20 * x, 0.92, 0.06), 0.04, 0.0, 4, WOOD_DARK, 1304 + x)
	slab(s, Vector3(0, 0.62, 0.06), Vector3(0.46, 0.05, 0.05), WOOD_LIGHT, 1306, Vector3(0, 0, 3), 0.01)
	slab(s, Vector3(0, 0.30, 0.04), Vector3(0.46, 0.05, 0.05), WOOD_LIGHT, 1307, Vector3(0, 0, -4), 0.01)
	slab(s, Vector3(0, -0.10, 0.10), Vector3(0.44, 0.24, 0.26), WOOD_LIGHT, 1308, Vector3.ZERO, 0.015)   # crate
	slab(s, Vector3(0, -0.10, 0.10), Vector3(0.46, 0.05, 0.28), WOOD_DARK, 1309, Vector3.ZERO, 0.0)      # band
	slab(s, Vector3(0, 0.025, 0.10), Vector3(0.40, 0.02, 0.22), WOOD_DARK, 1310, Vector3.ZERO, 0.0)      # crate mouth
	blob(s, Vector3(0.25, -0.02, 0.10), Vector3(0.07, 0.07, 0.05), FUSE, 1311, 0.15, 0, Vector3(0, 90, 0))   # fuse coil
	limb(s, Vector3(0.25, 0.0, 0.06), Vector3(0.25, 0.52, 0.03), 0.014, 0.014, 3, FUSE, 1312, 0.0, 0.0)     # up the pole
	limb(s, Vector3(0.25, 0.52, 0.03), Vector3(0.27, 0.60, 0.02), 0.018, 0.012, 3, FUSE, 1313, 0.0, 0.0)    # the end
	return s


## Five striped rockets standing in the crate, fanned a little (the big one in the middle). Hidden once fired.
func _rockets_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1321, 0.06)
	var body_cols: Array[Color] = [ROCKET_GOLD, ROCKET_RED, ROCKET_RED, ROCKET_LIME, ROCKET_GOLD]
	var cone_cols: Array[Color] = [ROCKET_RED, PAPER, ROCKET_GOLD, ROCKET_RED, ROCKET_RED]
	var lens: Array[float] = [0.40, 0.50, 0.62, 0.48, 0.38]
	for i in 5:
		var x := (float(i) - 2.0) * 0.085
		var z := 0.10 + (0.03 if i % 2 == 0 else -0.03)
		var lean := Vector3(x * 0.55, 1.0, (z - 0.10) * 0.8 + 0.06).normalized()
		var base := Vector3(x, 0.0, z)
		var top := base + lean * lens[i]
		limb(s, base, top, 0.052, 0.052, 6, body_cols[i], 1322 + i, 0.0, 0.05)
		var mid := base + lean * (lens[i] * 0.55)
		limb(s, mid, mid + lean * 0.07, 0.056, 0.056, 6, PAPER, 1328 + i, 0.0, 0.03)   # stripe
		limb(s, top, top + lean * 0.15, 0.06, 0.0, 6, cone_cols[i], 1334 + i, 0.0, 0.04)   # nose cone
	return s


## Pennant on a thin pole off the rack's left side.
func _flag_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1341, 0.06)
	limb(s, Vector3(0, 0, 0), Vector3(-0.03, 0.80, 0.04), 0.02, 0.016, 4, WOOD_DARK, 1342)
	blob(s, Vector3(-0.03, 0.82, 0.04), Vector3(0.03, 0.03, 0.03), BRASS, 1343, 0.1)
	s.merge(LowPoly.frustum(Vector2(0.025, 0.28), Vector2(0.012, 0.02), 0.46, FLAG, 1344, 0.0, 1, Vector2.ZERO, 0.06),
			LowPoly.at(Vector3(-0.03, 0.64, 0.27), Vector3(90, 0, 0)))
	for x: float in [-1.0, 1.0]:
		slab(s, Vector3(-0.03 + 0.016 * x, 0.66, 0.17), Vector3(0.01, 0.08, 0.08), FLAG_STAR, 1345 + int(x), Vector3(45, 0, 0), 0.0, 0.0)
	return s


## Fuse sparks: a spiky glowing star (only shown while the fuse burns).
func _spark_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1351, 0.05)
	blob(s, Vector3.ZERO, Vector3(0.08, 0.08, 0.08), glow(SPARK), 1352, 0.1, 0, Vector3.ZERO, 0.0)
	var dirs: Array[Vector3] = [Vector3(1, 0.6, 0), Vector3(-0.8, 0.9, 0.2), Vector3(0.1, 1, -0.6), Vector3(0.3, 0.4, 1),
			Vector3(-0.5, 0.2, -0.9), Vector3(0.9, -0.2, -0.5)]
	for i in dirs.size():
		limb(s, Vector3.ZERO, dirs[i].normalized() * (0.26 + 0.08 * float(i % 2)), 0.045, 0.0, 3, glow(SPARK if i % 2 == 0 else EMBER), 1353 + i, 0.0, 0.0)
	return s


## The long match: a stick with a cord wrap and a glowing ember at the tip. Grip at the origin, along +Y.
func _match_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1361, 0.06)
	limb(s, Vector3(0, -0.10, 0), Vector3(0, MATCH_LEN - 0.06, 0), 0.022, 0.018, 5, WOOD_DARK, 1362)
	limb(s, Vector3(0, MATCH_LEN - 0.14, 0), Vector3(0, MATCH_LEN - 0.04, 0), 0.03, 0.03, 5, FUSE, 1363)
	blob(s, Vector3(0, MATCH_LEN, 0), Vector3(0.045, 0.05, 0.045), glow(EMBER), 1364, 0.1, 0, Vector3.ZERO, 0.0)
	return s


## The "!" mark: a tapered spike over a dot; round, so it reads from any facing.
static func _mark_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1371, 0.03)
	limb(s, Vector3(0, 0.19, 0), Vector3(0, 0.78, 0), 0.055, 0.15, 6, glow(MARK), 1372, 0.0, 0.0)
	blob(s, Vector3(0, 0.0, 0), Vector3(0.095, 0.095, 0.095), glow(MARK), 1373, 0.0, 0, Vector3.ZERO, 0.0)
	return s


# ------------------------------------------------------------------ animation

func apply_idle(t: float, speed: float = 0.0) -> void:
	if _downed:
		return
	var walk := clampf(speed / 2.2, 0.0, 1.0)
	var run := clampf((speed - 2.6) / 2.4, 0.0, 1.0)
	# The active walk (MonsterModel.gait_k): on his patrol amble only (the sprint and the poses are his own), a sly
	# side-to-side shuffle under the rack and a nodding head.
	var g := gait_k(walk) * (1.0 - run) * (1.0 - alert_k) * (1.0 - cower_k) * (1.0 - look_k)
	var w := wind_e()
	var sw := _swing
	var al := alert_k * alert_k * (3.0 - 2.0 * alert_k)
	var lk := look_k
	var cw := cower_k
	var freq := lerpf(7.0, 13.5, run)
	var stride := sin(t * freq)
	var breath := sin(t * 2.2)
	var sweep := sin(look_phase * TAU) * lk
	var glance := smoothstep(0.2, 0.8, sin(t * 2.6)) * run * (1.0 if fuse_lit else 0.0)

	# body: hunched amble, a forward-leaning sprint, crouch to light, hop on the alert, curl up to cower
	var body := parts["body"] as MeshInstance3D
	body.position = Vector3(stride * 0.03 * g, HIP_Y + breath * 0.01 + absf(stride) * (0.03 * walk + 0.06 * run) - 0.11 * w + 0.12 * al - 0.20 * cw, -0.05 * sw)
	body.rotation = Vector3(-0.08 * walk - 0.38 * run - 0.22 * w + 0.22 * al + 0.10 * lk - 0.45 * cw - 0.30 * sw - 0.06 * g,
			stride * 0.08 * walk + stride * 0.10 * run + 0.25 * sweep - 0.30 * w,
			sin(t * 1.1) * 0.015 + stride * 0.04 * walk + stride * 0.07 * g)
	var head := parts["head"] as MeshInstance3D
	head.rotation = Vector3(sin(t * 1.4) * 0.03 + 0.30 * run + 0.30 * al + 0.20 * w - 0.25 * cw + 0.1 * sw + absf(stride) * 0.10 * g,
			0.75 * sweep + 1.3 * glance - 0.95 * w,
			sin(t * 0.9) * 0.04 * (1.0 - al) - stride * 0.08 * g)

	# ears: droopy and twitchy on patrol, straight up on the alert, swept back in a sprint, flat when cowering
	var twitch := sin(t * 3.3) * 0.06 + sin(t * 8.0 + 1.0) * 0.03 * lk
	var flap := stride * 0.18 * run
	var up := -0.12 + 0.95 * al - 0.55 * cw + 0.15 * lk
	(parts["ear_l"] as MeshInstance3D).rotation = Vector3(0.0, 0.55 * run + 0.4 * cw, -up + twitch + flap)
	(parts["ear_r"] as MeshInstance3D).rotation = Vector3(0.0, -0.55 * run - 0.4 * cw, up - twitch + flap)

	# legs
	var amp := 0.55 * walk + 1.05 * run
	var bend := 0.35 * w + 0.70 * cw - 0.10 * al
	(parts["leg_l"] as MeshInstance3D).rotation = Vector3(stride * amp + bend, 0.0, -0.08 * al)
	(parts["leg_r"] as MeshInstance3D).rotation = Vector3(-stride * amp + bend, 0.0, 0.08 * al)

	# hands (body-local targets), blended per pose
	var hl := Vector3(-0.30, -0.12, -0.12 + stride * 0.16 * walk)
	var hr := Vector3(0.30, -0.06, -0.22 - stride * 0.12 * walk)
	hl = hl.lerp(Vector3(-0.42, 0.05, 0.22 + stride * 0.22), run)                       # flailing back
	hr = hr.lerp(Vector3(0.30, 0.38 - stride * 0.08, -0.36), run)                      # match held up, pumping
	hl = hl.lerp(Vector3(-0.07, 0.86, -0.42), lk)                                       # hand shading the goggles
	hl = hl.lerp(Vector3(-0.55, 0.92, -0.06), al)                                       # arms flung up
	hr = hr.lerp(Vector3(0.55, 0.92, -0.10), al)
	hl = hl.lerp(Vector3(-0.16, 0.40, -0.30), w)                                        # clutching the strap
	hr = hr.lerp(_fuse_body() + LIGHT_DIR * -(MATCH_LEN - 0.02), w)                     # arm out, match up at the fuse
	hl = hl.lerp(Vector3(-0.16, 0.86, -0.04), cw)                                       # arms over the head
	hr = hr.lerp(Vector3(0.18, 0.84, -0.02), cw)
	hl = hl.lerp(Vector3(-0.22, 0.78, -0.58), clampf(sw * 1.3, 0.0, 1.0))                # the toss
	_aim_arm(parts["arm_l"] as MeshInstance3D, hl)
	_aim_arm(parts["arm_r"] as MeshInstance3D, hr)

	# the match follows the right hand: carried forward-up, held high in a sprint, tipped to the fuse
	var mdir := Vector3(0.12, 0.55, -0.82)
	mdir = mdir.lerp(Vector3(0.0, 0.92, -0.38), run)
	mdir = mdir.lerp(Vector3(0.35, 0.90, 0.25), al)
	mdir = mdir.lerp(LIGHT_DIR, w)
	mdir = mdir.lerp(Vector3(0.2, 0.5, 0.85), cw)
	var match_mi := parts["match"] as MeshInstance3D
	match_mi.position = hr + Vector3(0.0, -0.02, -0.02)
	match_mi.basis = Basis(Quaternion(Vector3.UP, mdir.normalized()))

	# the rack bounces; the pennant sways and flutters (hard in a sprint)
	var rack := parts["rack"] as MeshInstance3D
	rack.position = RACK_AT + Vector3(0.0, absf(stride) * 0.02 * (walk + run), 0.0)
	rack.rotation = Vector3(stride * 0.03 * run + 0.06 * cw, 0.0, stride * 0.03 * walk)
	var flag := parts["flag"] as MeshInstance3D
	flag.rotation = Vector3(0.30 * run + sin(t * 2.0) * 0.05, sin(t * (3.5 + 9.0 * run)) * (0.18 + 0.30 * run), sin(t * 1.7) * 0.05)
	(parts["rockets"] as MeshInstance3D).visible = loaded

	var spark := parts["spark"] as MeshInstance3D
	# sparks spit from the fuse end while it burns, and already while the match is on it (the telegraph's
	# brightest cue, visible from any side since the fuse end sticks up over his shoulder)
	var catching := smoothstep(0.35, 0.9, _wind)
	spark.visible = loaded and (fuse_lit or catching > 0.0)
	var fizz := 1.25 if fuse_lit else lerpf(0.6, 1.5, catching)
	spark.scale = Vector3.ONE * maxf(fizz * (0.85 + 0.35 * absf(sin(t * 37.0))), 0.001)
	spark.rotation = Vector3(t * 9.0, t * 13.0, 0.0)

	var mark := parts["mark"] as MeshInstance3D
	mark.visible = alert_k > 0.02 or mark_on
	var pop := alert_k * (1.0 + 0.25 * sin(alert_k * PI))
	if mark_on:
		pop = maxf(pop, 0.85)
	mark.scale = Vector3.ONE * maxf(pop, 0.001)
	mark.position = Vector3(0.0, MARK_Y + 0.05 * sin(t * 6.0), -0.05)


## The fuse coil in body space (the rack's rest placement; the rack only bounces a little).
func _fuse_body() -> Vector3:
	return RACK_AT + FUSE_AT


## Re-aim a hanging arm at a body-local hand target (the arm's pivot is its shoulder).
func _aim_arm(arm: MeshInstance3D, hand: Vector3) -> void:
	aim_limb(arm, hand, ARM_LEN)


func _slump() -> void:
	(parts["body"] as MeshInstance3D).rotation = Vector3(-0.35, 0.0, 0.1)
	(parts["head"] as MeshInstance3D).rotation = Vector3(-0.45, 0.2, 0.0)
	(parts["ear_l"] as MeshInstance3D).rotation = Vector3(0.0, 0.2, 0.6)
	(parts["ear_r"] as MeshInstance3D).rotation = Vector3(0.0, -0.2, -0.6)
	(parts["arm_l"] as MeshInstance3D).basis = Basis(Vector3(0, 0, 1), -0.4)
	(parts["arm_r"] as MeshInstance3D).basis = Basis(Vector3(0, 0, 1), 0.4)
	(parts["leg_l"] as MeshInstance3D).rotation = Vector3.ZERO
	(parts["leg_r"] as MeshInstance3D).rotation = Vector3.ZERO
	var match_mi := parts["match"] as MeshInstance3D
	match_mi.position = Vector3(0.45, -0.45, -0.2)
	match_mi.basis = Basis(Vector3(0, 0, 1), 1.4)
	(parts["spark"] as MeshInstance3D).visible = false
	(parts["mark"] as MeshInstance3D).visible = false
