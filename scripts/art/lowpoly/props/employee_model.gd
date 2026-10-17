class_name EmployeeModel
extends LowPolyModel
## A hired-help civilian for contracts, FACETED low-poly like the heroes but built to read as "not a
## hero": short, pear-shaped (wide hips, narrow sloping shoulders), muted clothes, and ONE bright
## identifier that survives the game zoom.
##
##   "staff"     a bunker butler: charcoal-plum waistcoat, grey trousers, a big WHITE collar with a red bow
##               tie, white gloves, a neat grey side-parted comb-over and a mustache. Carries a silver tray
##               with a dome cloche (the cloche hops when he panics).
##   "henchman"  a villain-lair grunt: a drab maroon jumpsuit with a belt and a chest patch, black boots
##               and a goofy lopsided YELLOW hard hat with stubby horns and a wobbly antenna. Carries a
##               clipboard.
##
## Faces local -Z, +X is its right, origin at the feet. About 1.8 units to the top of the head (Wick is
## 2.2 to his hat tip, Gasket 1.74), 2.0 with the yellow helmet.
##
## Rigid named parts (all MeshInstance3D): body, head, brows, mouth, collar, jacket, hat, prop, arm_l,
## arm_r, leg_l, leg_r (staff also has cloche, under the prop). head / collar / jacket / arms / prop hang
## under body; brows / mouth / hat under head; legs under the root. Both sleeves are re-aimed every frame
## at their hand target (the Wick trick), so the tray and the clipboard follow the right hand.
##
## Moods (set_mood): "stand" (nervous fidget), "cower" (crouched, hands over the head, trembling, teeth
## chattering), "panic" (running flat out, arms flailing, mouth wide open), "follow" (a calm trot, tray
## or clipboard in hand) and "cheer" (hands up, hopping: the exit). set_scared(true) adds a worried
## flutter to any mood. Walk speed is read from the node's own motion, like the heroes.

const STYLES: Array[String] = ["staff", "henchman"]
const PART_NAMES: Array[String] = ["body", "head", "brows", "mouth", "collar", "jacket", "hat", "prop", "arm_l", "arm_r", "leg_l", "leg_r"]
const MOODS: Array[String] = ["stand", "cower", "panic", "follow", "cheer"]
const MODEL_SCALE := 1.0

# Palette (sRGB, painted): everything muted except the identifiers.
const WHITE := Color(0.95, 0.94, 0.90)           ## collar, cuffs, gloves, shirt
const WHITE_DARK := Color(0.80, 0.79, 0.76)
const PLUM := Color(0.34, 0.22, 0.28)            ## waistcoat
const PLUM_LIGHT := Color(0.44, 0.30, 0.37)
const PLUM_DARK := Color(0.24, 0.15, 0.20)
const SLATE := Color(0.24, 0.25, 0.30)           ## staff trousers
const SLATE_DARK := Color(0.17, 0.18, 0.22)
const BOW := Color(0.80, 0.20, 0.22)
const SILVER := Color(0.74, 0.76, 0.80)
const SILVER_DARK := Color(0.50, 0.52, 0.58)
const SILVER_LIGHT := Color(0.88, 0.90, 0.94)
const GREY_HAIR := Color(0.64, 0.63, 0.66)
const GREY_HAIR_DARK := Color(0.46, 0.45, 0.49)
const SUIT := Color(0.50, 0.24, 0.25)            ## henchman jumpsuit: drab maroon
const SUIT_LIGHT := Color(0.60, 0.31, 0.31)
const SUIT_DARK := Color(0.36, 0.16, 0.18)
const HELMET := Color(0.98, 0.80, 0.14)          ## the bright identifier
const HELMET_LIGHT := Color(1.00, 0.90, 0.38)
const HELMET_DARK := Color(0.80, 0.60, 0.08)
const BLACK := Color(0.13, 0.12, 0.14)
const BLACK_LIGHT := Color(0.24, 0.23, 0.26)
const PATCH := Color(0.90, 0.88, 0.80)
const PATCH_MARK := Color(0.16, 0.14, 0.16)
const BOARD := Color(0.52, 0.36, 0.20)
const PAPER := Color(0.93, 0.92, 0.86)
const INKLINE := Color(0.30, 0.30, 0.36)
const EYE := Color(0.97, 0.96, 0.92)
const PUPIL := Color(0.10, 0.09, 0.12)
const MOUTH := Color(0.42, 0.14, 0.16)
const SKIN_TONES: Array[Color] = [Color(0.95, 0.78, 0.66), Color(0.78, 0.58, 0.42), Color(0.58, 0.40, 0.29)]

const HIP_Y := 0.80
const HEAD_Y := 0.85                              ## body-local head centre
const SHOULDER := Vector3(0.25, 0.53, 0.0)         ## body-local shoulder pivot (mirrored for the left)
const ARM_LEN := 0.56
const LEG_X := 0.12
const CROUCH_DROP := 0.34

var style := "staff"
var variant := 0

var _mood := "stand"
var _cower := 0.0
var _panic := 0.0
var _cheer := 0.0
var _follow := 0.0
var _scare := 0.0
var _scare_target := 0.0
var _prev_t := -1.0
var _skin := SKIN_TONES[0]
var _skin_dark := SKIN_TONES[0].darkened(0.14)


func _init(model_style: String = "staff", model_variant: int = 0) -> void:
	style = model_style if STYLES.has(model_style) else "staff"
	variant = absi(model_variant)
	_skin = SKIN_TONES[variant % SKIN_TONES.size()]
	_skin_dark = _skin.darkened(0.14)
	_setup_model("EmployeeModel", MODEL_SCALE)
	ui_height = (2.0 if style == "henchman" else 1.85) * MODEL_SCALE
	_build()


# ------------------------------------------------------------------ build

func _build() -> void:
	var henchman := style == "henchman"
	var body := _add_part("body", _body_soup(), self, Vector3(0, HIP_Y, 0))
	var head := _add_part("head", _head_soup(), body, Vector3(0, HEAD_Y, -0.02))
	_add_part("brows", _brows_soup(), head, Vector3(0, 0.10, -0.17))
	_add_part("mouth", _mouth_soup(), head, Vector3(0, -0.115, -0.165))
	_add_part("collar", _collar_soup(), body, Vector3(0, 0.56, 0.0))
	_add_part("jacket", _jacket_soup(), body, Vector3.ZERO)
	_add_part("hat", _helmet_soup() if henchman else _hair_soup(), head, Vector3(0, 0.17, 0.0))
	var prop := _add_part("prop", _clipboard_soup() if henchman else _tray_soup(), body, Vector3(0.16, 0.08, -0.36))
	if not henchman:
		_add_part("cloche", _cloche_soup(), prop, Vector3(0, 0.0, 0))
	for s: int in [-1, 1]:
		var side := "l" if s < 0 else "r"
		_add_part("arm_" + side, _arm_soup(s), body, Vector3(SHOULDER.x * s, SHOULDER.y, SHOULDER.z))
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(LEG_X * s, HIP_Y, 0.0))
	apply_idle(0.0)


## The pelvis, a pear-shaped torso (wide hips, narrow sloping shoulders) in the uniform colour, a neck.
func _body_soup() -> LowPoly.Soup:
	var henchman := style == "henchman"
	var pants := SUIT_DARK if henchman else SLATE
	var shirt := SUIT if henchman else WHITE
	var s := LowPoly.box(Vector3(0.42, 0.22, 0.30), pants, 501, 0.02, 1, 0.07)
	s.merge(LowPoly.frustum(Vector2(0.48, 0.34), Vector2(0.38, 0.27), 0.54, shirt, 502, 0.02, 2, Vector2.ZERO, 0.07), LowPoly.at(Vector3(0, 0.33, 0)))
	s.merge(LowPoly.cylinder(0.075, 0.07, 0.14, 6, _skin_dark, 503, 0.008), LowPoly.at(Vector3(0, 0.62, 0.0)))
	return s


## A round, slightly too big head: box-ish, a nose, ears, eyes with pupils. Hair / helmet hang on top.
func _head_soup() -> LowPoly.Soup:
	var s := LowPoly.box(Vector3(0.36, 0.36, 0.33), _skin, 511, 0.05, 2, 0.05)
	s.merge(LowPoly.boulder(Vector3(0.05, 0.075, 0.07), 0, 0.2, _skin_dark, 512, 0.06), LowPoly.at(Vector3(0, -0.03, -0.18)))   # nose
	for x: int in [-1, 1]:
		s.merge(LowPoly.box(Vector3(0.09, 0.09, 0.03), EYE, 513 + x, 0.0, 1, 0.0), LowPoly.at(Vector3(0.085 * x, 0.03, -0.165)))
		s.merge(LowPoly.box(Vector3(0.04, 0.05, 0.03), PUPIL, 515 + x, 0.0, 1, 0.0), LowPoly.at(Vector3(0.082 * x, 0.025, -0.178)))
		s.merge(LowPoly.boulder(Vector3(0.035, 0.065, 0.045), 0, 0.2, _skin_dark, 517 + x, 0.06), LowPoly.at(Vector3(0.185 * x, -0.01, 0.0)))   # ears
	if style == "staff":
		s.merge(LowPoly.boulder(Vector3(0.11, 0.035, 0.05), 0, 0.2, GREY_HAIR_DARK, 519, 0.07), LowPoly.at(Vector3(0, -0.085, -0.17)))   # mustache
	else:
		s.merge(LowPoly.box(Vector3(0.20, 0.05, 0.03), _skin_dark, 519, 0.01, 1, 0.1), LowPoly.at(Vector3(0, -0.15, -0.16)))   # stubbly chin
	return s


## Two worried eyebrows, slanted up toward the middle. Raised in fear.
func _brows_soup() -> LowPoly.Soup:
	var col := GREY_HAIR_DARK if style == "staff" else BLACK
	var s := LowPoly.Soup.new(521, 0.05)
	for x: int in [-1, 1]:
		s.merge(LowPoly.box(Vector3(0.12, 0.035, 0.03), col, 522 + x, 0.0, 1, 0.05), LowPoly.at(Vector3(0.085 * x, 0.0, 0.0), Vector3(0, 0, -17.0 * x)))
	return s


## A small dark mouth; scaled tall for a scream, wide for a grin.
func _mouth_soup() -> LowPoly.Soup:
	return LowPoly.box(Vector3(0.08, 0.04, 0.03), MOUTH, 525, 0.0, 1, 0.0)


## The collar. Staff: a big white wing collar and a red bow tie (the bright identifier). Henchman: a dark
## mandarin collar with a zip pull.
func _collar_soup() -> LowPoly.Soup:
	if style == "staff":
		var s := LowPoly.frustum(Vector2(0.40, 0.30), Vector2(0.28, 0.21), 0.10, WHITE, 531, 0.012, 1, Vector2.ZERO, 0.04)
		for x: int in [-1, 1]:
			s.merge(LowPoly.box(Vector3(0.15, 0.13, 0.04), WHITE, 532 + x, 0.01, 1, 0.04), LowPoly.at(Vector3(0.095 * x, 0.0, -0.13), Vector3(0, 0, -26.0 * x)))   # wing points
		s.merge(LowPoly.box(Vector3(0.075, 0.06, 0.05), BOW, 534, 0.005, 1, 0.05), LowPoly.at(Vector3(0, -0.01, -0.165)))   # bow tie knot
		for x: int in [-1, 1]:
			s.merge(LowPoly.box(Vector3(0.09, 0.07, 0.04), BOW, 535 + x, 0.005, 1, 0.05), LowPoly.at(Vector3(0.075 * x, -0.01, -0.165), Vector3(0, 0, 18.0 * x)))
		return s
	var h := LowPoly.frustum(Vector2(0.38, 0.28), Vector2(0.26, 0.19), 0.09, SUIT_DARK, 531, 0.012, 1, Vector2.ZERO, 0.05)
	h.merge(LowPoly.box(Vector3(0.035, 0.07, 0.03), SILVER, 532, 0.0, 1, 0.0), LowPoly.at(Vector3(0, -0.01, -0.145)))
	return h


## The torso garment. Staff: a waistcoat over the shirt, buttons, a pocket watch chain. Henchman: the
## jumpsuit belt, zip, pocket flaps and a chest patch with a villain-ish mark.
func _jacket_soup() -> LowPoly.Soup:
	if style == "staff":
		var s := LowPoly.frustum(Vector2(0.51, 0.37), Vector2(0.40, 0.29), 0.40, PLUM, 541, 0.025, 2, Vector2.ZERO, 0.07)
		s = _moved(s, Vector3(0, 0.25, 0))
		s.merge(LowPoly.box(Vector3(0.04, 0.34, 0.02), PLUM_DARK, 542, 0.0, 1, 0.05), LowPoly.at(Vector3(0, 0.27, -0.17)))
		for y: float in [0.14, 0.26, 0.38]:
			s.merge(LowPoly.box(Vector3(0.035, 0.035, 0.025), SILVER_LIGHT, 543, 0.0, 1, 0.0), LowPoly.at(Vector3(0.035, y, -0.18)))
		s.merge(LowPoly.box(Vector3(0.09, 0.025, 0.02), PLUM_LIGHT, 544, 0.0, 1, 0.05), LowPoly.at(Vector3(-0.12, 0.34, -0.172), Vector3(0, 0, 8)))   # pocket
		s.merge(LowPoly.box(Vector3(0.14, 0.012, 0.015), SILVER, 545, 0.0, 1, 0.0), LowPoly.at(Vector3(-0.07, 0.30, -0.18), Vector3(0, 0, -22)))   # watch chain
		return s
	var j := LowPoly.box(Vector3(0.50, 0.075, 0.37), BLACK, 541, 0.01, 1, 0.07)   # belt
	j = _moved(j, Vector3(0, 0.12, 0))
	j.merge(LowPoly.box(Vector3(0.08, 0.08, 0.03), SILVER, 542, 0.0, 1, 0.0), LowPoly.at(Vector3(0, 0.12, -0.19)))   # buckle
	j.merge(LowPoly.box(Vector3(0.03, 0.40, 0.02), SUIT_DARK, 543, 0.0, 1, 0.05), LowPoly.at(Vector3(0, 0.36, -0.145)))   # zip
	for x: int in [-1, 1]:
		j.merge(LowPoly.box(Vector3(0.11, 0.08, 0.03), SUIT_LIGHT, 544 + x, 0.005, 1, 0.07), LowPoly.at(Vector3(0.12 * x, 0.22, -0.18)))   # pocket flaps
	j.merge(LowPoly.box(Vector3(0.12, 0.12, 0.02), PATCH, 546, 0.004, 1, 0.04), LowPoly.at(Vector3(-0.12, 0.44, -0.145)))   # chest patch
	j.merge(LowPoly.box(Vector3(0.06, 0.06, 0.02), PATCH_MARK, 547, 0.0, 1, 0.0), LowPoly.at(Vector3(-0.12, 0.44, -0.158), Vector3(0, 0, 45)))   # the mark
	j.merge(LowPoly.box(Vector3(0.07, 0.04, 0.02), HELMET, 548, 0.0, 1, 0.0), LowPoly.at(Vector3(0.12, 0.44, -0.15)))   # name badge
	return j


## Staff: a neat grey comb-over (sides and back, a shiny bald top) with one stray strand.
func _hair_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(551, 0.07)
	for x: int in [-1, 1]:
		s.merge(LowPoly.boulder(Vector3(0.05, 0.13, 0.15), 0, 0.15, GREY_HAIR, 552 + x, 0.07), LowPoly.at(Vector3(0.18 * x, -0.07, 0.01)))
	s.merge(LowPoly.boulder(Vector3(0.17, 0.12, 0.07), 0, 0.15, GREY_HAIR_DARK, 554, 0.07), LowPoly.at(Vector3(0, -0.07, 0.15)))
	s.merge(LowPoly.box(Vector3(0.22, 0.02, 0.2), GREY_HAIR, 555, 0.0, 1, 0.08), LowPoly.at(Vector3(-0.02, 0.02, -0.02), Vector3(0, 0, 4)))   # the comb-over strands
	s.merge(LowPoly.box(Vector3(0.02, 0.1, 0.02), GREY_HAIR, 556, 0.0, 1, 0.08), LowPoly.at(Vector3(0.05, 0.08, -0.02), Vector3(0, 0, -35)))   # stray strand
	return s


## Henchman: the goofy lopsided yellow hard hat. Origin is the centre of the brim line. A dome, a brim
## with a peak, a ridge, stubby horns (the lair's dress code) and a short antenna with a red ball.
func _helmet_soup() -> LowPoly.Soup:
	var s := LowPoly.boulder(Vector3(0.25, 0.17, 0.25), 1, 0.12, HELMET, 561, 0.06)
	s = _moved(s, Vector3(0, 0.07, 0))
	s.merge(LowPoly.cylinder(0.30, 0.30, 0.04, 8, HELMET_DARK, 562, 0.01), LowPoly.at(Vector3(0, -0.015, 0.0)))   # brim
	s.merge(LowPoly.box(Vector3(0.24, 0.04, 0.16), HELMET_DARK, 563, 0.005, 1, 0.06), LowPoly.at(Vector3(0, -0.01, -0.28), Vector3(-10, 0, 0)))   # peak
	s.merge(LowPoly.box(Vector3(0.07, 0.05, 0.4), HELMET_LIGHT, 564, 0.005, 1, 0.06), LowPoly.at(Vector3(0, 0.235, 0.0)))   # ridge
	for x: int in [-1, 1]:
		s.merge(LowPoly.cylinder(0.0, 0.055, 0.2, 5, PATCH, 565 + x, 0.01), LowPoly.at(Vector3(0.22 * x, 0.2, 0.0), Vector3(0, 0, -35.0 * x)))   # horns
	s.merge(LowPoly.cylinder(0.012, 0.012, 0.24, 4, SILVER_DARK, 567, 0.0), LowPoly.at(Vector3(0.1, 0.36, 0.08), Vector3(8, 0, -10)))   # antenna
	s.merge(LowPoly.boulder(Vector3(0.045, 0.045, 0.045), 0, 0.1, BOW, 568, 0.04), LowPoly.at(Vector3(0.12, 0.49, 0.08)))   # ball
	return s


## A round silver serving tray; origin is the tray centre (the cloche sits on top).
func _tray_soup() -> LowPoly.Soup:
	var s := LowPoly.cylinder(0.27, 0.27, 0.035, 8, SILVER, 571, 0.006, 1, 0.05)
	s.merge(LowPoly.cylinder(0.24, 0.24, 0.02, 8, SILVER_LIGHT, 572, 0.004, 1, 0.04), LowPoly.at(Vector3(0, 0.014, 0)))
	return s


## The dome cloche on the tray, with a knob.
func _cloche_soup() -> LowPoly.Soup:
	var s := LowPoly.boulder(Vector3(0.17, 0.12, 0.17), 1, 0.10, SILVER_LIGHT, 575, 0.05)
	s = _moved(s, Vector3(0, 0.06, 0))
	s.merge(LowPoly.boulder(Vector3(0.04, 0.04, 0.04), 0, 0.1, SILVER_DARK, 576, 0.04), LowPoly.at(Vector3(0, 0.19, 0)))
	return s


## A clipboard: a brown board, paper with scribbled lines, a steel clip. Origin is its centre; the face
## looks along local -Z.
func _clipboard_soup() -> LowPoly.Soup:
	var s := LowPoly.box(Vector3(0.28, 0.38, 0.03), BOARD, 581, 0.006, 1, 0.06)
	s.merge(LowPoly.box(Vector3(0.23, 0.31, 0.012), PAPER, 582, 0.0, 1, 0.03), LowPoly.at(Vector3(0, -0.01, -0.02)))
	for y: float in [-0.10, -0.04, 0.02, 0.08]:
		s.merge(LowPoly.box(Vector3(0.17, 0.014, 0.01), INKLINE, 583, 0.0, 1, 0.1), LowPoly.at(Vector3(-0.01, y, -0.03)))
	s.merge(LowPoly.box(Vector3(0.12, 0.06, 0.04), SILVER, 584, 0.004, 1, 0.04), LowPoly.at(Vector3(0, 0.18, -0.02)))
	return s


## A short sleeve (pivot at the shoulder, hanging down -Y) ending in a hand: a white glove for the staff.
func _arm_soup(side: int) -> LowPoly.Soup:
	var henchman := style == "henchman"
	var sleeve := SUIT if henchman else WHITE
	var cuff := SUIT_DARK if henchman else WHITE_DARK
	var hand := BLACK_LIGHT if henchman else WHITE
	var s := LowPoly.boulder(Vector3(0.10, 0.085, 0.10), 0, 0.15, sleeve, 591 + side, 0.07)
	s.merge(LowPoly.frustum(Vector2(0.15, 0.15), Vector2(0.12, 0.12), 0.36, sleeve, 593 + side, 0.02, 1, Vector2.ZERO, 0.07), LowPoly.at(Vector3(0, -0.20, 0)))
	s.merge(LowPoly.cylinder(0.072, 0.072, 0.06, 6, cuff, 595 + side, 0.008), LowPoly.at(Vector3(0, -0.40, 0)))
	s.merge(LowPoly.boulder(Vector3(0.075, 0.085, 0.075), 0, 0.15, hand, 597 + side, 0.05), LowPoly.at(Vector3(0, -0.49, 0)))
	return s


## A trouser leg with a shoe, pivot at the hip. Stubby, so the figure reads short and round.
func _leg_soup(side: int) -> LowPoly.Soup:
	var henchman := style == "henchman"
	var trouser := SUIT_DARK if henchman else SLATE
	var trouser_low := SUIT_DARK.darkened(0.1) if henchman else SLATE_DARK
	var shoe := BLACK
	var s := LowPoly.Soup.new(601, 0.07)
	s.merge(LowPoly.frustum(Vector2(0.18, 0.18), Vector2(0.20, 0.20), 0.40, trouser, 602 + side, 0.02), LowPoly.at(Vector3(0, -0.20, 0)))
	s.merge(LowPoly.frustum(Vector2(0.15, 0.15), Vector2(0.18, 0.18), 0.30, trouser_low, 604 + side, 0.02), LowPoly.at(Vector3(0, -0.52, 0)))
	s.merge(LowPoly.frustum(Vector2(0.18, 0.28), Vector2(0.15, 0.18), 0.16, shoe, 606 + side, 0.02, 1, Vector2(0, -0.03), 0.08), LowPoly.at(Vector3(0, -0.71, -0.03)))
	s.merge(LowPoly.box(Vector3(0.20, 0.035, 0.32), BLACK_LIGHT, 608 + side, 0.0, 1, 0.05), LowPoly.at(Vector3(0, -0.785, -0.04)))   # sole
	if henchman:
		s.merge(LowPoly.cylinder(0.105, 0.105, 0.04, 6, HELMET, 610 + side, 0.008), LowPoly.at(Vector3(0, -0.62, 0)))   # a yellow stripe at the boot top
	return s


# ------------------------------------------------------------------ soup helpers

## `s` shifted by `off` (a fresh soup carrying the same painted faces).
static func _moved(s: LowPoly.Soup, off: Vector3) -> LowPoly.Soup:
	var out := LowPoly.Soup.new(1, 0.0)
	return out.merge(s, LowPoly.at(off))


# ------------------------------------------------------------------ moods

## Switch mood. `snap` jumps straight there (lab / tests / spawn); otherwise it blends in about 0.25 s.
func set_mood(mood: String, snap: bool = false) -> void:
	if not MOODS.has(mood):
		return
	_mood = mood
	if snap:
		_cower = 1.0 if mood == "cower" else 0.0
		_panic = 1.0 if mood == "panic" else 0.0
		_cheer = 1.0 if mood == "cheer" else 0.0
		_follow = 1.0 if mood == "follow" else 0.0


func mood() -> String:
	return _mood


## A worried flutter (hands to the chest, trembling), blended on top of any mood.
func set_scared(scared: bool) -> void:
	_scare_target = 1.0 if scared else 0.0


## The little exit cheer.
func cheer() -> void:
	set_mood("cheer")


## Frozen pose for the lab / tests: any mood, optionally walking (`walk_speed` > 0 drives the stride).
func pose_preview(mood_name: String, time: float = 0.6, walk_speed: float = 0.0) -> void:
	set_mood(mood_name, true)
	_scare = _scare_target
	_prev_t = time
	apply_idle(time, walk_speed)


## Fade-out at the end of a rescue / death: shrink away (the opaque toon shader cannot alpha-fade).
func set_fade(a: float) -> void:
	scale = Vector3.ONE * MODEL_SCALE * maxf(a, 0.001)


# ------------------------------------------------------------------ animation

func apply_idle(t: float, speed: float = 0.0) -> void:
	var dt := clampf(t - _prev_t, 0.0, 0.1) if _prev_t >= 0.0 else 0.0
	_prev_t = t
	_cower = move_toward(_cower, 1.0 if _mood == "cower" else 0.0, dt * 4.5)
	_panic = move_toward(_panic, 1.0 if _mood == "panic" else 0.0, dt * 6.0)
	_cheer = move_toward(_cheer, 1.0 if _mood == "cheer" else 0.0, dt * 6.0)
	_follow = move_toward(_follow, 1.0 if _mood == "follow" else 0.0, dt * 4.0)
	_scare = move_toward(_scare, _scare_target, dt * 5.0)

	var henchman := style == "henchman"
	var walk := clampf(speed / 3.2, 0.0, 1.0) * (1.0 - _cower)
	var run := clampf(speed / 3.6, 0.0, 1.0) * _panic
	var stride_f := lerpf(9.0, 15.0, _panic)
	var stride := sin(t * stride_f)
	var breath := sin(t * 2.4)
	var flutter := sin(t * 31.0) * (0.45 * _cower + 0.25 * _scare + 0.2 * _panic)
	var hop := absf(sin(t * 10.0)) * _cheer

	# body: crouched and shaking when cowering, bounding when running, hopping when cheering
	var body := parts["body"] as MeshInstance3D
	var body_y := HIP_Y - CROUCH_DROP * _cower + breath * 0.008 - absf(stride) * 0.045 * walk + hop * 0.22
	body.position = Vector3(flutter * 0.03, body_y, 0.0)
	body.rotation = Vector3(
			-0.06 - 0.55 * _cower - 0.20 * run - 0.05 * walk + breath * 0.01,
			sin(t * 1.1) * 0.05 * (1.0 - walk),
			stride * 0.07 * walk + sin(t * 8.0) * 0.10 * _panic * (1.0 - walk) + flutter * 0.06)

	# head: darts about while hiding, shakes in panic, looks up at the sky in a cheer
	var head := parts["head"] as MeshInstance3D
	head.rotation = Vector3(
			0.04 + 0.50 * _cower + 0.10 * _scare - 0.08 * _cheer + sin(t * 1.7) * 0.02,
			(sin(t * 1.3) * 0.28 + sin(t * 3.3) * 0.08) * (1.0 - _panic) * (1.0 + _cower * 0.8),
			sin(t * 17.0) * 0.16 * _panic + flutter * 0.05)
	var brows := parts["brows"] as MeshInstance3D
	brows.position = Vector3(0, 0.10 + 0.035 * (_cower + _panic + 0.5 * _scare) - 0.01 * _cheer, -0.17)
	brows.rotation = Vector3(0, 0, sin(t * 6.0) * 0.06 * _panic)
	var mouth := parts["mouth"] as MeshInstance3D
	var chatter := (0.5 + 0.5 * sin(t * 26.0)) * _cower
	mouth.scale = Vector3(1.0 + 1.3 * _cheer - 0.2 * _panic, 1.0 + 3.0 * _panic + 1.8 * chatter + 0.2 * _scare - 0.2 * _cheer, 1.0)
	mouth.position = Vector3(0, -0.115 + 0.01 * _cheer, -0.165)

	# legs: scissor strides, bent and squashed when cowering, kicked apart in a cheer
	var swing := (0.55 + 0.45 * _panic) * walk
	for s: int in [-1, 1]:
		var leg := parts["leg_l" if s < 0 else "leg_r"] as MeshInstance3D
		leg.position = Vector3(LEG_X * s, body_y, 0.0)
		leg.scale = Vector3(1.0, lerpf(1.0, 0.62, _cower), 1.0)
		leg.rotation = Vector3(stride * swing * -s - 0.26 * _cower + flutter * 0.05, 0.0, 0.14 * s * _cheer)

	# hat: the helmet is loose and bounces; the comb-over just sits
	var hat := parts["hat"] as MeshInstance3D
	if henchman:
		hat.position = Vector3(0, 0.17 + absf(sin(t * stride_f)) * 0.035 * (walk + _panic) + hop * 0.04, 0)
		hat.rotation = Vector3(sin(t * stride_f + 1.0) * 0.08 * (walk + _panic), 0.0, 0.14 + sin(t * 1.9) * 0.05 + stride * 0.10 * walk)
	else:
		hat.rotation = Vector3(0, 0, 0)

	# hands
	var l_rest := Vector3(-0.30, 0.02 + breath * 0.008, -0.02 - stride * 0.20 * walk)
	var r_rest := (Vector3(0.18, 0.30, -0.34) if henchman else Vector3(0.16, 0.10, -0.36)) + Vector3(0.0, absf(stride) * 0.025 * walk + breath * 0.008, 0.0)
	var l := l_rest
	var r := r_rest
	# scared: hands wring at the chest
	var wring := Vector3(sin(t * 9.0) * 0.04, sin(t * 7.0) * 0.03, 0.0)
	l = l.lerp(Vector3(-0.10, 0.28, -0.32) + wring, _scare * 0.8)
	r = r.lerp(Vector3(0.10, 0.30, -0.34) - wring, _scare * 0.8)
	# cowering: both hands clamped over the head
	l = l.lerp(Vector3(-0.15, 0.84, -0.24) + Vector3(flutter * 0.03, 0, 0), _cower)
	r = r.lerp(Vector3(0.15, 0.84, -0.24) - Vector3(flutter * 0.03, 0, 0), _cower)
	# panic: both arms up and flailing
	var fl := Vector3(-0.36 + sin(t * 13.0) * 0.14, 0.98 + sin(t * 11.0) * 0.28, -0.08 + sin(t * 9.0) * 0.12)
	var fr := Vector3(0.38 + sin(t * 12.0 + 1.0) * 0.14, 0.98 + sin(t * 10.0 + 2.0) * 0.28, -0.08 + sin(t * 8.0 + 1.0) * 0.12)
	l = l.lerp(fl, _panic)
	r = r.lerp(fr, _panic)
	# cheer: both arms high in a V, waving
	l = l.lerp(Vector3(-0.46 + sin(t * 14.0) * 0.07, 1.20, -0.04), _cheer)
	r = r.lerp(Vector3(0.46 + sin(t * 14.0 + 1.5) * 0.07, 1.22, -0.04), _cheer)
	_aim_arm(parts["arm_l"] as MeshInstance3D, l)
	_aim_arm(parts["arm_r"] as MeshInstance3D, r)

	# the prop rides the right hand: tilted for reading / carrying, wildly in a panic
	var prop := parts["prop"] as MeshInstance3D
	var tilt := sin(t * 12.0) * 0.55 * _panic + sin(t * 7.0) * 0.12 * _scare
	if henchman:
		prop.position = r + Vector3(-0.03, 0.04, -0.04)
		prop.rotation = Vector3(0.9 + tilt, 0.0, tilt * 0.8 + 0.1)
	else:
		prop.position = r + Vector3(0.0, 0.05, 0.0)
		prop.rotation = Vector3(tilt * 0.8, 0.0, tilt)
		var cloche := parts["cloche"] as MeshInstance3D
		cloche.position = Vector3(0, 0.02 + maxf(0.0, sin(t * 15.0)) * 0.12 * _panic, 0.0)
		cloche.rotation = Vector3(0, 0, sin(t * 13.0) * 0.25 * _panic)

	if hold_anchor != null:
		hold_anchor.position = l + Vector3(-0.1, 0.2, 0.0)


## Re-aim a sleeve from the shoulder at `hand`, stretching it a little so it always reaches.
func _aim_arm(arm: MeshInstance3D, hand: Vector3) -> void:
	var d := hand - arm.position
	var dist := d.length()
	if dist < 0.01:
		return
	arm.quaternion = Quaternion(Vector3.DOWN, d / dist)
	arm.scale = Vector3(1.0, clampf(dist / ARM_LEN, 0.55, 1.45), 1.0)
