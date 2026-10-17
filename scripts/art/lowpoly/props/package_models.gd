class_name PackageModels
extends RefCounted
## Faceted low-poly models for the mail packages (MailPackage) and what spills out of them: a taped-up brown
## cardboard box (three sizes) and the loose bits (skulls, yogurt tubs and lids, pickles, cardboard flaps).
## Built from LowPoly primitives and drawn with the prop look (PropModels.material: flat facet colour, ink
## outline, amber rim). Origin at the base centre, front = +Z.
##
##   var node := PackageModels.box("medium", 3)      # Node3D "Model" with a MeshInstance3D "Body"
##   var bit := PackageModels.bit("skull", 5)        # Node3D with one mesh, sitting on y = 0

const CARDBOARD := Color(0.66, 0.46, 0.26)
const CARDBOARD_LT := Color(0.74, 0.54, 0.32)
const CARDBOARD_DK := Color(0.50, 0.34, 0.19)
const TAPE := Color(0.93, 0.82, 0.54)
const LABEL := Color(0.97, 0.97, 0.94)
const INK := Color(0.16, 0.14, 0.14)
const LABEL_RED := Color(0.82, 0.18, 0.14)
const BONE := Color(0.93, 0.89, 0.78)
const BONE_DK := Color(0.76, 0.70, 0.58)
const SOCKET := Color(0.07, 0.05, 0.05)
const YOGURT_CUP := Color(0.96, 0.95, 0.92)
const FOIL := Color(0.80, 0.83, 0.88)
const PICKLE := Color(0.36, 0.56, 0.16)
const PICKLE_DK := Color(0.24, 0.40, 0.11)
const FRUIT: Array[Color] = [Color(0.90, 0.30, 0.45), Color(0.38, 0.40, 0.82), Color(0.98, 0.66, 0.30), Color(0.48, 0.74, 0.34)]

const FLAP_THICK := 0.03              ## the closed top flaps stand this far above the box body

## Box size per kind (width x height x depth); the height does not include the flaps.
const SIZES := {
	"small": Vector3(0.62, 0.46, 0.50),
	"medium": Vector3(0.84, 0.58, 0.64),
	"long": Vector3(1.28, 0.46, 0.52),
}
const KINDS: Array[String] = ["small", "medium", "long"]

static var _bit_material: ShaderMaterial = null


static func size_of(kind: String) -> Vector3:
	return SIZES.get(kind, SIZES["medium"]) as Vector3


## Full height of a box of this kind (body + flaps): what the next box of a stack sits on.
static func height_of(kind: String) -> float:
	return size_of(kind).y + FLAP_THICK


## Colours the burst of cardboard chips is painted with.
static func palette() -> Array[Color]:
	return [CARDBOARD, CARDBOARD_LT, CARDBOARD_DK, TAPE]


## One material shared by every loose bit (a spill can hold a dozen of them).
static func bit_material() -> ShaderMaterial:
	if _bit_material == null:
		_bit_material = PropModels.material()
	return _bit_material


# --------------------------------------------------------------------------- the box

static func box(kind: String, seed_value: int = 1) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = box_soup(kind, seed_value).to_mesh()
	mi.material_override = PropModels.material()
	root.add_child(mi)
	return root


## The box as a triangle soup: dented cardboard body, two closed top flaps, a cross of tape over the seams
## (wrapped a little way down the sides) and a white shipping label with a barcode.
static func box_soup(kind: String, seed_value: int = 1) -> LowPoly.Soup:
	var dims := size_of(kind)
	var w := dims.x
	var h := dims.y
	var d := dims.z
	var s := LowPoly.Soup.new(seed_value * 31 + 7, 0.05)
	var n := seed_value * 101
	var fl := FLAP_THICK
	_box(s, Vector3(w, h, d), Vector3(0, h * 0.5, 0), CARDBOARD, n + 1, 0.014)
	# a darker band along the bottom edge, so the box reads as sitting on the floor
	_box(s, Vector3(w + 0.012, 0.05, d + 0.012), Vector3(0, 0.025, 0), CARDBOARD_DK, n + 2)
	# the closed flaps: two halves meeting over the middle seam (along Z)
	for sx in [-1.0, 1.0]:
		_box(s, Vector3(w * 0.5 - 0.008, fl, d - 0.03), Vector3(sx * w * 0.25, h + fl * 0.5 - 0.004, 0), CARDBOARD_LT, n + 3 + int(sx))
	var top := h + fl
	var tape_w := clampf(minf(w, d) * 0.19, 0.08, 0.13)
	var tape_t := 0.016
	# tape along the seam, over the top and down the front and back faces
	_box(s, Vector3(tape_w, tape_t, d + 0.014), Vector3(0, top + tape_t * 0.5 - 0.004, 0), TAPE, n + 6)
	for sz in [-1.0, 1.0]:
		_box(s, Vector3(tape_w, h * 0.34, 0.012), Vector3(0, h - h * 0.17 + 0.01, sz * (d * 0.5 + 0.004)), TAPE, n + 7 + int(sz))
	# the cross strip over the middle, down the left and right faces
	_box(s, Vector3(w + 0.014, tape_t, tape_w), Vector3(0, top + tape_t * 0.5 - 0.004 + 0.003, 0), TAPE, n + 9)
	for sx in [-1.0, 1.0]:
		_box(s, Vector3(0.012, h * 0.34, tape_w), Vector3(sx * (w * 0.5 + 0.004), h - h * 0.17 + 0.01, 0), TAPE, n + 10 + int(sx))
	# shipping label on top, in the front-left quarter (clear of the tape) and a small one on the front face
	var lw := minf(0.24, w * 0.3)
	var ld := minf(0.17, d * 0.3)
	var lpos := Vector3(-w * 0.26, top + 0.006, d * 0.2)
	_box(s, Vector3(lw, 0.012, ld), lpos, LABEL, n + 12)
	_box(s, Vector3(lw * 0.82, 0.016, ld * 0.16), lpos + Vector3(0, 0.002, -ld * 0.28), INK, n + 13)
	_box(s, Vector3(lw * 0.55, 0.016, ld * 0.12), lpos + Vector3(-lw * 0.12, 0.002, ld * 0.05), INK, n + 14)
	_box(s, Vector3(lw * 0.2, 0.016, ld * 0.22), lpos + Vector3(lw * 0.32, 0.002, ld * 0.22), LABEL_RED, n + 15)
	_box(s, Vector3(0.17, 0.12, 0.012), Vector3(w * 0.2, h * 0.5, d * 0.5 + 0.004), LABEL, n + 16)
	_box(s, Vector3(0.12, 0.018, 0.014), Vector3(w * 0.2, h * 0.5 + 0.03, d * 0.5 + 0.008), INK, n + 17)
	_box(s, Vector3(0.08, 0.018, 0.014), Vector3(w * 0.2 - 0.02, h * 0.5 - 0.01, d * 0.5 + 0.008), INK, n + 18)
	return s


static func _box(s: LowPoly.Soup, size: Vector3, pos: Vector3, col: Color, seed_value: int, jit: float = 0.0) -> void:
	s.merge(LowPoly.box(size, col, seed_value, jit, 1, 0.05), LowPoly.at(pos))


# --------------------------------------------------------------------------- loose bits

## How much bigger than its modelled size each loose bit is drawn (they have to read from the game camera).
const BIT_SCALE := {"skull": 1.35, "tub": 1.4, "lid": 1.4, "pickle": 1.3, "flap": 1.0}


## Half the thickness of a bit lying on the floor (so it rests on it); "tub_up" is a tub standing upright.
static func rest_height(kind: String) -> float:
	var k := float(BIT_SCALE.get(kind, 1.0))
	match kind:
		"skull": return 0.127 * k
		"tub": return 0.09 * k
		"tub_up": return 0.07 * k
		"lid": return 0.008 * k
		"pickle": return 0.052 * k
		"flap": return 0.008
	return 0.05


## One loose bit as its own node (a single mesh, origin at its centre), sized for the game camera.
static func bit(kind: String, seed_value: int = 1) -> Node3D:
	var s := LowPoly.Soup.new(seed_value * 17 + 3, 0.06)
	var n := seed_value * 53
	match kind:
		"skull": _skull(s, n)
		"tub": _tub(s, n, seed_value)
		"lid": _lid(s, n, seed_value)
		"pickle": _pickle(s, n)
		_: _flap(s, n, seed_value)
	var root := Node3D.new()
	root.name = kind.capitalize()
	var mi := MeshInstance3D.new()
	mi.mesh = s.to_mesh()
	mi.material_override = bit_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_flash", true)
	mi.scale = Vector3.ONE * float(BIT_SCALE.get(kind, 1.0))
	root.add_child(mi)
	return root


static func _skull(s: LowPoly.Soup, n: int) -> void:
	# cranium, jaw, two dark sockets and a nose notch; front = +Z, scaled up so it reads from the camera
	var k := 1.3
	s.merge(LowPoly.boulder(Vector3(0.10, 0.09, 0.105) * k, 0, 0.1, BONE, n + 1, 0.06), LowPoly.at(Vector3(0, 0.01 * k, 0)))
	s.merge(LowPoly.box(Vector3(0.105, 0.045, 0.075) * k, BONE_DK, n + 2, 0.0, 1, 0.06), LowPoly.at(Vector3(0, -0.075 * k, 0.03 * k)))
	for sx in [-1.0, 1.0]:
		s.merge(LowPoly.boulder(Vector3(0.028, 0.032, 0.02) * k, 0, 0.05, SOCKET, n + 3 + int(sx), 0.0), LowPoly.at(Vector3(sx * 0.04 * k, -0.002 * k, 0.088 * k)))
	s.merge(LowPoly.box(Vector3(0.018, 0.03, 0.02) * k, SOCKET, n + 5, 0.0, 1, 0.0), LowPoly.at(Vector3(0, -0.04 * k, 0.098 * k)))
	# teeth: a pale row on the jaw
	s.merge(LowPoly.box(Vector3(0.085, 0.014, 0.01) * k, BONE, n + 6, 0.0, 1, 0.04), LowPoly.at(Vector3(0, -0.058 * k, 0.07 * k)))


static func _tub(s: LowPoly.Soup, n: int, seed_value: int) -> void:
	var fruit: Color = FRUIT[seed_value % FRUIT.size()]
	s.merge(LowPoly.cylinder(0.062, 0.086, 0.13, 8, YOGURT_CUP, n + 1, 0.0, 1, 0.04), LowPoly.at(Vector3.ZERO))
	s.merge(LowPoly.cylinder(0.070, 0.080, 0.05, 8, fruit, n + 2, 0.0, 1, 0.05), LowPoly.at(Vector3(0, -0.005, 0)))
	s.merge(LowPoly.cylinder(0.092, 0.092, 0.014, 8, FOIL, n + 3, 0.0, 1, 0.04), LowPoly.at(Vector3(0, 0.07, 0)))


static func _lid(s: LowPoly.Soup, n: int, seed_value: int) -> void:
	var fruit: Color = FRUIT[seed_value % FRUIT.size()]
	s.merge(LowPoly.cylinder(0.092, 0.092, 0.014, 8, FOIL, n + 1, 0.0, 1, 0.04), LowPoly.at(Vector3.ZERO))
	s.merge(LowPoly.box(Vector3(0.05, 0.006, 0.03), fruit, n + 2, 0.0, 1, 0.04), LowPoly.at(Vector3(0.02, 0.01, 0.0)))


static func _pickle(s: LowPoly.Soup, n: int) -> void:
	s.merge(LowPoly.boulder(Vector3(0.17, 0.052, 0.052), 1, 0.12, PICKLE, n + 1, 0.07), LowPoly.at(Vector3.ZERO))
	for i in 3:
		s.merge(LowPoly.boulder(Vector3(0.02, 0.012, 0.014), 0, 0.2, PICKLE_DK, n + 2 + i, 0.05), LowPoly.at(Vector3(-0.08 + 0.08 * i, 0.04, 0.012 * (i - 1))))


static func _flap(s: LowPoly.Soup, n: int, seed_value: int) -> void:
	var big := seed_value % 2 == 0
	var fw := 0.40 if big else 0.30
	var fd := 0.24 if big else 0.2
	s.merge(LowPoly.box(Vector3(fw, 0.014, fd), CARDBOARD_LT if big else CARDBOARD, n + 1, 0.0, 1, 0.06), LowPoly.at(Vector3.ZERO))
	s.merge(LowPoly.box(Vector3(0.07, 0.018, fd * 1.02), TAPE, n + 2, 0.0, 1, 0.04), LowPoly.at(Vector3(fw * 0.15, 0.002, 0)))
