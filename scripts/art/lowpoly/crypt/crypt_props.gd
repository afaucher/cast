class_name CryptProps
extends RefCounted
## LOOK-DEV ONLY (docs/design/crypt-section.md): the crypt's architecture kit, for the crypt section lab
## (crypt_section_lab.gd) and the gym's "Haunting (look test)" spawns. Nothing in the game builds a crypt: the floor
## generator, the contracts and the network never see these. Plain nodes: no collision, no HP, nothing networked.
##
## The house kit (LowPoly soups, MonsterMaterial: ink outline, amber rim, vertex alpha 0.5 = an emissive face), origin at
## the base centre, FRONT = +Z (the piece faces (sin yaw, cos yaw) when placed at `yaw`). Every piece comes in the two
## material sets (`set`): "vault" (under a mansion: dark rough stone, black iron, tallow) and "chapel" (under a church:
## pale limestone, brass, beeswax). The shapes' jitter comes from fixed seeds (never GameWorld.rng).
##
##   var s := CryptProps.build("sarcophagus", {"set": "chapel", "lid": "ajar"})
##
## Kinds (params):
##   sarcophagus  a stone chest on a plinth, long along Z (lid: effigy | cross | ajar; default effigy in the vault, cross
##                in the chapel)
##   ossuary      a wall of niches packed with long bones, a skull on each stack and a skull frieze on top; back at z = 0
##                against a wall face, centred on x (width, height)
##   gate         an iron bar gate in a stone arch, spanning x (width: between the wall lines, height, open 0..1: the two
##                leaves swing toward +Z)
##   arch         the same stone arch, no gate (a doorway)
##   candles      a cluster of floor candles (count, radius, seed, lit, light: the light's energy scale)
##   candelabra   a standing five-branch candlestick (lit, light)
##   bones        a fallen skeleton on the floor: a skull, a ribcage, long bones (seed)
##   pew          a church pew, long along X (the church above)
##   altar        a stone altar with a cloth and two candlesticks (the church above; lit, light)
## Lit pieces carry an OmniLight3D named "CandleLight" (warm, short range, no shadow): the candle light the crypt's bright
## parts are made of.

const GROUP := &"crypt_look"
const KINDS: Array[String] = ["sarcophagus", "ossuary", "gate", "arch", "candles", "candelabra", "bones", "pew", "altar"]
## The gym's spawns (GymSpawns "haunt"): the pieces that read on their own.
const GYM_KINDS: Array[String] = ["sarcophagus", "ossuary", "gate", "candles"]
const SETS: Array[String] = ["vault", "chapel"]

## Per set: stone (body), stone_dk (insets, plinths), stone_lt (lids, carving), iron (bars), metal (candlesticks, trim),
## cloth (the altar's), wax, gate and gate_hi (the gate's bars, and its rails and finials: worn iron, lighter than `iron`,
## so a gate reads in the dark; the user, 2026-10-29: "they read _very_ dark when lit in the scene").
const PALETTE := {
	"vault": {
		"stone": Color(0.37, 0.34, 0.31), "stone_dk": Color(0.20, 0.18, 0.17), "stone_lt": Color(0.50, 0.47, 0.42),
		"iron": Color(0.12, 0.11, 0.12), "metal": Color(0.26, 0.24, 0.24),
		"gate": Color(0.40, 0.36, 0.33), "gate_hi": Color(0.62, 0.55, 0.46), "cloth": Color(0.36, 0.10, 0.09),
		"wax": Color(0.90, 0.84, 0.66), "niche": Color(0.08, 0.07, 0.07),
	},
	"chapel": {
		"stone": Color(0.70, 0.66, 0.57), "stone_dk": Color(0.47, 0.44, 0.38), "stone_lt": Color(0.86, 0.83, 0.75),
		"iron": Color(0.16, 0.15, 0.15), "metal": Color(0.74, 0.57, 0.27),
		"gate": Color(0.36, 0.33, 0.31), "gate_hi": Color(0.80, 0.62, 0.30), "cloth": Color(0.32, 0.12, 0.38),
		"wax": Color(0.98, 0.93, 0.80), "niche": Color(0.17, 0.14, 0.12),
	},
}
const BONE := Color(0.87, 0.82, 0.67)
const BONE_DK := Color(0.62, 0.57, 0.44)
const SOCKET := Color(0.05, 0.035, 0.03)
const FLAME := Color(1.0, 0.80, 0.32)
const FLAME_HOT := Color(1.0, 0.95, 0.7)
const CANDLE_LIGHT := Color(1.0, 0.64, 0.30)
const WOOD := Color(0.36, 0.21, 0.11)
const WOOD_DK := Color(0.22, 0.12, 0.06)

const GATE_W := 3.0          ## a narrow hall's width between the wall lines (the doorway a gate fills)
const GATE_H := 1.78         ## to the top of the arch's lintel (the game's walls are 1.5)
const SPRING := 1.18         ## where the arch springs from the jambs
const RISE := 0.32           ## the arch's rise over its span (a segmental arch)
const JAMB := 0.32           ## jamb width
const DEPTH := 0.42          ## the arch's depth (through the doorway)
const SARC_SCALE := 0.8      ## the sarcophagus smaller (the user, 2026-10-29: "It just takes too much of the room")


static func pal(set_name: String) -> Dictionary:
	return PALETTE.get(set_name, PALETTE["vault"])


static func build(kind: String, params: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Crypt_" + kind
	root.add_to_group(GROUP)
	root.set_meta("crypt_kind", kind)
	var set_name := str(params.get("set", "vault"))
	var p := pal(set_name)
	var s := LowPoly.Soup.new(31 + kind.hash() % 97, 0.06)
	PropModels._seed = absi(kind.hash()) % 9973 + 7
	var light_at := Vector3.INF
	match kind:
		"sarcophagus":
			var sc := LowPoly.Soup.new(31, 0.06)
			_sarcophagus(sc, p, str(params.get("lid", "cross" if set_name == "chapel" else "effigy")))
			s.merge(sc, Transform3D(Basis.from_scale(Vector3.ONE * SARC_SCALE), Vector3.ZERO))
		"ossuary": _ossuary(s, p, float(params.get("width", 3.0)), float(params.get("height", 1.45)))
		"gate": _arch(s, p, float(params.get("width", GATE_W)), true, float(params.get("open", 0.0)))
		"arch": _arch(s, p, float(params.get("width", GATE_W)), false, 0.0)
		"candles":
			_candles(s, p, int(params.get("count", 7)), float(params.get("radius", 0.42)), int(params.get("seed", 3)))
			light_at = Vector3(0, 0.75, 0)
		"candelabra":
			_candelabra(s, p)
			light_at = Vector3(0, 1.75, 0)
		"bones": _bones(s, p, int(params.get("seed", 5)))
		"pew": _pew(s, float(params.get("length", 2.4)))
		"altar":
			_altar(s, p)
			light_at = Vector3(0, 1.5, 0)
		_:
			PropModels.box(s, Vector3(0.5, 0.5, 0.5), Vector3(0, 0.25, 0), PropModels.GOLD)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = s.to_mesh()
	var mat := MonsterMaterial.make(2.0)
	mat.set_shader_parameter("glow_gain", 1.7)
	mi.material_override = mat
	root.add_child(mi)
	if light_at != Vector3.INF and bool(params.get("lit", true)):
		root.add_child(candle_light(light_at, float(params.get("light", 1.0)), kind == "candelabra"))
	return root


## The warm light of a lit piece: short range, soft falloff, no shadow (the crypt's bright parts are these pools).
static func candle_light(at: Vector3, k: float = 1.0, tall: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "CandleLight"
	l.position = at
	l.light_color = CANDLE_LIGHT
	l.light_energy = (4.5 if tall else 3.8) * k
	l.omni_range = 6.0 if tall else 5.0
	l.omni_attenuation = 1.3
	l.light_specular = 0.15
	l.shadow_enabled = false
	return l


static func _g(c: Color) -> Color:
	return PropModels.glow(c)


static func _box(s: LowPoly.Soup, size: Vector3, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
	PropModels.box(s, size, pos, col, rot)


# --- sarcophagus --------------------------------------------------------------------------------------------------

## A chest 1.0 x 2.05 on a plinth, carved panels on its sides, a lid with an effigy (a recumbent figure, hands on a
## sword), a relief cross, or pushed aside showing the dark inside.
static func _sarcophagus(s: LowPoly.Soup, p: Dictionary, lid: String) -> void:
	var st: Color = p["stone"]
	var dk: Color = p["stone_dk"]
	var lt: Color = p["stone_lt"]
	_box(s, Vector3(1.18, 0.12, 2.28), Vector3(0, 0.06, 0), dk)
	PropModels.frus(s, Vector2(1.02, 2.08), Vector2(1.06, 2.12), 0.56, Vector3(0, 0.12 + 0.28, 0), st)
	for x: float in [-1.0, 1.0]:
		for z: float in [-0.62, 0.0, 0.62]:
			_box(s, Vector3(0.03, 0.3, 0.46), Vector3(0.52 * x, 0.42, z), dk)
	for z: float in [-1.0, 1.0]:
		_box(s, Vector3(0.62, 0.3, 0.03), Vector3(0, 0.42, 1.045 * z), dk)
	var top := 0.68
	if lid == "ajar":
		_box(s, Vector3(0.9, 0.04, 1.9), Vector3(0, top - 0.01, 0), SOCKET)            # the dark inside
		_box(s, Vector3(1.12, 0.11, 2.2), Vector3(0.42, top + 0.1, 0.18), lt, Vector3(0, 9.0, -7.0))
		return
	_box(s, Vector3(1.14, 0.11, 2.2), Vector3(0, top + 0.055, 0), lt)
	_box(s, Vector3(1.04, 0.05, 2.1), Vector3(0, top + 0.13, 0), st)
	var y := top + 0.155
	if lid == "cross":
		_box(s, Vector3(0.14, 0.05, 1.5), Vector3(0, y + 0.02, 0.05), lt)
		_box(s, Vector3(0.62, 0.05, 0.14), Vector3(0, y + 0.02, -0.35), lt)
		return
	# the effigy, lying on its back: the head on a cushion at the back (-Z), shoulders, a body narrowing to the feet,
	# hands together on a sword along it, the feet standing up
	_box(s, Vector3(0.5, 0.08, 0.32), Vector3(0, y + 0.04, -0.8), dk)
	PropModels.ball(s, Vector3(0.14, 0.13, 0.15), Vector3(0, y + 0.19, -0.76), lt, 1, 0.08)
	PropModels.ball(s, Vector3(0.3, 0.13, 0.22), Vector3(0, y + 0.13, -0.45), lt, 1, 0.08)        # shoulders and chest
	PropModels.frus(s, Vector2(0.5, 0.24), Vector2(0.3, 0.18), 0.95, Vector3(0, y + 0.12, 0.12), lt, Vector2.ZERO, Vector3(90, 0, 0))
	for x: float in [-1.0, 1.0]:
		PropModels.rod(s, Vector3(0.24 * x, y + 0.2, -0.45), Vector3(0.07 * x, y + 0.27, -0.2), 0.06, 0.05, 5, st)   # the arms
	_box(s, Vector3(0.06, 0.035, 0.95), Vector3(0, y + 0.26, 0.22), Color(0.62, 0.62, 0.66))         # the sword along the body
	_box(s, Vector3(0.3, 0.045, 0.06), Vector3(0, y + 0.28, -0.22), Color(0.62, 0.62, 0.66))          # its guard
	PropModels.ball(s, Vector3(0.1, 0.07, 0.09), Vector3(0, y + 0.3, -0.16), lt, 0, 0.05)            # the hands
	for x: float in [-0.1, 0.1]:
		_box(s, Vector3(0.1, 0.2, 0.09), Vector3(x, y + 0.2, 0.66), lt)


# --- ossuary ------------------------------------------------------------------------------------------------------

## A bone wall: a stone frame of niches in two tiers, each packed the way a charnel house stacks them: bands of long bones
## laid lengthwise (knobbed ends) between rows of skulls facing out. No board on top: the upper tier is open with a row of
## skulls on its stack like the rows below (the user, 2026-10-29: "remove the top shelf and randomize the placement a bit
## more", "leave the top open. It can have a pile of skulls on it. Just no top board", "The little dots also don't sell as
## skulls", then "just a slightly jittered row of skulls"). Back at z = 0 (against the wall face), front at +DEPTH.
static func _ossuary(s: LowPoly.Soup, p: Dictionary, width: float, height: float) -> void:
	var st: Color = p["stone"]
	var dk: Color = p["stone_dk"]
	var n := maxi(2, roundi(width / 0.78))
	var w := width / float(n)
	var d := 0.44
	var top := height - 0.12                                                                # the piers' tops
	_box(s, Vector3(width, top, 0.08), Vector3(0, top * 0.5, 0.04), p["niche"])            # the niches' dark backs
	_box(s, Vector3(width + 0.1, 0.16, d + 0.04), Vector3(0, 0.08, d * 0.5), dk)           # the plinth
	var mid := 0.16 + (height - 0.3) * 0.5
	_box(s, Vector3(width, 0.08, d), Vector3(0, mid, d * 0.5), st)                          # the middle shelf
	for i in n + 1:
		var x := -width * 0.5 + w * float(i)
		_box(s, Vector3(0.12, top - 0.08, d), Vector3(x, (top + 0.08) * 0.5, d * 0.5), st)    # the piers
	var rng := RandomNumberGenerator.new()
	rng.seed = 41 + n
	for i in n:
		var cx := -width * 0.5 + w * (float(i) + 0.5)
		_niche(s, cx, w - 0.12, 0.16, mid - 0.04, d, rng)
		var y := _niche(s, cx, w - 0.12, mid + 0.04, top, d, rng)
		_skull_row(s, cx, w - 0.12, y, d - 0.11, rng)              # the open top: one more row of skulls


## Fill a niche `w` wide from y0 up to y1: a band of long bones, a row of skulls, again, as far as fits. Returns the top
## of the stack.
static func _niche(s: LowPoly.Soup, cx: float, w: float, y0: float, y1: float, d: float, rng: RandomNumberGenerator) -> float:
	var y := y0
	var skulls := rng.randf() < 0.5        # which band comes first
	while true:
		if skulls and y + 0.2 <= y1:
			_skull_row(s, cx, w, y, d - 0.11, rng)
			y += 0.2
		elif not skulls and y + 0.07 <= y1:
			var layers := 2 if y + 0.13 <= y1 else 1
			for l in layers:
				_bone_layer(s, cx, w, y + 0.035 + 0.06 * float(l), d - 0.07, rng)
			y += 0.065 * float(layers)
		else:
			break
		skulls = not skulls
	return y


## Long bones lying along X, end to end across `w` at height `y`, their knobbed ends showing.
static func _bone_layer(s: LowPoly.Soup, cx: float, w: float, y: float, z: float, rng: RandomNumberGenerator) -> void:
	var x := cx - w * 0.5 + rng.randf_range(-0.08, 0.0)
	while x < cx + w * 0.5 - 0.08:
		var l := rng.randf_range(0.24, 0.36)
		var a := Vector3(maxf(x, cx - w * 0.5 + 0.04), y, z + rng.randf_range(-0.03, 0.02))
		var b := Vector3(minf(x + l, cx + w * 0.5 - 0.04), y + rng.randf_range(-0.01, 0.01), z + rng.randf_range(-0.03, 0.02))
		var col := BONE if rng.randf() > 0.3 else BONE_DK
		PropModels.rod(s, a, b, 0.026, 0.024, 4, col)
		PropModels.ball(s, Vector3(0.042, 0.036, 0.042), a, col, 0, 0.1)
		PropModels.ball(s, Vector3(0.042, 0.036, 0.042), b, col, 0, 0.1)
		x += l + rng.randf_range(0.0, 0.04)


## A row of skulls facing out across `w`, sitting on `y`.
static func _skull_row(s: LowPoly.Soup, cx: float, w: float, y: float, z: float, rng: RandomNumberGenerator) -> void:
	var m := maxi(1, int(w / 0.2))
	for i in m:
		var x := cx - w * 0.5 + w * (float(i) + 0.5) / float(m) + rng.randf_range(-0.02, 0.02)
		_skull(s, Vector3(x, y + 0.1, z), rng.randf_range(0.92, 1.05), rng.randf_range(-20.0, 20.0))


## A skull facing +Z at `at` (its middle), `k` its scale, turned `yaw` degrees: the cranium, a jaw, dark sockets and nose.
static func _skull(s: LowPoly.Soup, at: Vector3, k: float, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var piece := LowPoly.Soup.new(97, 0.05)
	piece.merge(LowPoly.boulder(Vector3(0.1, 0.095, 0.11) * k, 0, 0.1, BONE, 98), LowPoly.at(Vector3.ZERO))
	piece.merge(LowPoly.box(Vector3(0.11, 0.05, 0.08) * k, BONE_DK, 99), LowPoly.at(Vector3(0, -0.075, 0.04) * k))
	for x: float in [-0.042, 0.042]:
		piece.merge(LowPoly.box(Vector3(0.045, 0.04, 0.03) * k, SOCKET, 100), LowPoly.at(Vector3(x, 0.0, 0.092) * k))
	piece.merge(LowPoly.box(Vector3(0.022, 0.03, 0.03) * k, SOCKET, 101), LowPoly.at(Vector3(0, -0.04, 0.1) * k))
	s.merge(piece, Transform3D(b, at))


# --- arch and gate ------------------------------------------------------------------------------------------------

## A stone doorway spanning x: two jambs standing inside the wall ends, a segmental arch of voussoirs with a keystone,
## a lintel over it. With `gate`: two iron leaves of bars with spear finials and rails, hinged on the jambs, `open` 0..1
## (each swings up to 100 degrees toward +Z), and a lock on the meeting bars.
static func _arch(s: LowPoly.Soup, p: Dictionary, width: float, gate: bool, open: float) -> void:
	var st: Color = p["stone"]
	var dk: Color = p["stone_dk"]
	var lt: Color = p["stone_lt"]
	var a := width * 0.5 - JAMB          # half the clear opening
	for x: float in [-1.0, 1.0]:
		_box(s, Vector3(JAMB, SPRING, DEPTH), Vector3(x * (a + JAMB * 0.5), SPRING * 0.5, 0), st)
		_box(s, Vector3(JAMB + 0.06, 0.1, DEPTH + 0.06), Vector3(x * (a + JAMB * 0.5), SPRING - 0.02, 0), lt)   # the impost
		_box(s, Vector3(JAMB + 0.08, 0.12, DEPTH + 0.08), Vector3(x * (a + JAMB * 0.5), 0.06, 0), dk)          # the base
	var r := (a * a + RISE * RISE) / (2.0 * RISE)
	var cy := SPRING + RISE - r
	var half := asin(a / r)
	var segs := 7
	for i in segs:
		var t0 := -half + 2.0 * half * float(i) / float(segs)
		var t1 := -half + 2.0 * half * float(i + 1) / float(segs)
		var tm := (t0 + t1) * 0.5
		var inner := Vector3(sin(tm) * r, cy + cos(tm) * r, 0)
		var seg_len := 2.0 * r * sin((t1 - t0) * 0.5)
		var th := 0.3 if i != segs / 2 else 0.38
		var col := st if i != segs / 2 else lt
		var pos := inner + Vector3(sin(tm), cos(tm), 0) * th * 0.5
		_box(s, Vector3(seg_len + 0.02, th, DEPTH + (0.04 if i == segs / 2 else 0.0)), pos, col, Vector3(0, 0, -rad_to_deg(tm)))
	var apex := SPRING + RISE
	# spandrels and the lintel over the arch
	for x: float in [-1.0, 1.0]:
		_box(s, Vector3(a * 0.62, GATE_H - SPRING - 0.16, DEPTH - 0.04), Vector3(x * (a * 0.69 + 0.1), (SPRING + GATE_H - 0.16) * 0.5 + 0.04, 0), st)
	_box(s, Vector3(width, 0.18, DEPTH + 0.04), Vector3(0, GATE_H - 0.09, 0), dk)
	if not gate:
		return
	var under := func(x: float) -> float:
		return cy + sqrt(maxf(r * r - x * x, 0.0)) - 0.06
	for side: float in [-1.0, 1.0]:
		# the leaf in its own space: the hinge at x = 0, the leaf running toward the middle (-side), shut along x
		var leaf := LowPoly.Soup.new(120 + int(side), 0.04)
		var nb := 6
		for i in nb + 1:
			var lx := a * float(i) / float(nb)            # along the leaf from the hinge
			var h: float = under.call(side * (a - lx))     # the arch over where that bar stands when shut
			var bar_top := h - 0.1
			var x := -side * lx
			leaf.merge(LowPoly.cylinder(0.03, 0.03, bar_top - 0.04, 5, p["gate"], 130 + i), LowPoly.at(Vector3(x, (bar_top + 0.04) * 0.5, 0)))
			leaf.merge(LowPoly.cylinder(0.05, 0.0, 0.13, 4, p["gate_hi"], 140 + i), LowPoly.at(Vector3(x, bar_top + 0.06, 0)))
		for y: float in [0.16, 0.92]:
			leaf.merge(LowPoly.box(Vector3(a, 0.06, 0.05), p["gate_hi"], 150), LowPoly.at(Vector3(-side * a * 0.5, y, 0)))
		# a band of scrolls between the rails: a zigzag of short bars
		for i in nb:
			var mid := Vector3(-side * a * (float(i) + 0.5) / float(nb), 0.54, 0)
			leaf.merge(LowPoly.box(Vector3(0.035, 0.5, 0.03), p["gate"], 160 + i), LowPoly.at(mid, Vector3(0, 0, 32.0 if i % 2 == 0 else -32.0)))
		if side > 0.0:
			leaf.merge(LowPoly.box(Vector3(0.16, 0.2, 0.08), p["metal"], 170), LowPoly.at(Vector3(-(a - 0.04), 0.95, 0.04)))
		# swung on the hinge toward +Z
		s.merge(leaf, Transform3D(Basis(Vector3.UP, side * open * deg_to_rad(100.0)), Vector3(side * a, 0, 0.06)))


# --- candles ------------------------------------------------------------------------------------------------------

## `count` floor candles of mixed heights, each with a drip, a wick and a two-tone flame. No wax spill (the user,
## 2026-10-29: "the wax spill doesn't read, just leave the candles").
static func _candles(s: LowPoly.Soup, p: Dictionary, count: int, radius: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var wax: Color = p["wax"]
	for i in count:
		var ang := TAU * float(i) / float(count) + rng.randf_range(-0.4, 0.4)
		var d := radius * (0.25 + 0.75 * sqrt(rng.randf())) if i > 0 else 0.0
		var at := Vector3(cos(ang) * d, 0, sin(ang) * d)
		var h := rng.randf_range(0.14, 0.5) if i > 0 else 0.55
		var rr := rng.randf_range(0.04, 0.065)
		_candle(s, at, h, rr, wax, rng)


static func _candle(s: LowPoly.Soup, at: Vector3, h: float, rr: float, wax: Color, rng: RandomNumberGenerator) -> void:
	PropModels.cyl(s, rr * 1.05, rr, h, 6, at + Vector3(0, h * 0.5, 0), wax)
	PropModels.ball(s, Vector3(rr * 0.6, rr * 1.2, rr * 0.6), at + Vector3(rr * 0.9, h - rr * 1.6, 0), wax.darkened(0.08), 0, 0.1)
	PropModels.rod(s, at + Vector3(0, h, 0), at + Vector3(0, h + 0.03, 0), 0.008, 0.008, 3, SOCKET)
	PropModels.rod(s, at + Vector3(0, h + 0.02, 0), at + Vector3(0, h + 0.15, 0), 0.045, 0.0, 5, _g(FLAME))
	PropModels.rod(s, at + Vector3(0, h + 0.025, 0), at + Vector3(0, h + 0.09, 0), 0.025, 0.0, 4, _g(FLAME_HOT))


## A standing candlestick, about 1.6 tall: three feet, a turned shaft, a crossbar with five cups and candles.
static func _candelabra(s: LowPoly.Soup, p: Dictionary) -> void:
	var m: Color = p["metal"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 3:
		var a := TAU * float(i) / 3.0
		PropModels.rod(s, Vector3(0, 0.22, 0), Vector3(cos(a) * 0.32, 0.0, sin(a) * 0.32), 0.03, 0.02, 4, m)
	PropModels.cyl(s, 0.05, 0.04, 1.15, 6, Vector3(0, 0.78, 0), m)
	PropModels.ball(s, Vector3(0.08, 0.06, 0.08), Vector3(0, 0.6, 0), m, 0, 0.05)
	_box(s, Vector3(0.9, 0.05, 0.05), Vector3(0, 1.32, 0), m)
	for x: float in [-0.42, -0.21, 0.0, 0.21, 0.42]:
		var cup_y := 1.36 + (0.1 if x == 0.0 else 0.0)
		if x == 0.0:
			PropModels.cyl(s, 0.03, 0.03, 0.1, 5, Vector3(0, 1.36, 0), m)
		PropModels.cyl(s, 0.05, 0.07, 0.05, 6, Vector3(x, cup_y, 0), m)
		_candle(s, Vector3(x, cup_y + 0.025, 0), rng.randf_range(0.16, 0.26), 0.035, p["wax"], rng)


# --- bones -------------------------------------------------------------------------------------------------------

## A fallen skeleton, bigger and bolder than a scatter (the user, 2026-10-29: "The bones are a little weak"): a skull, a
## ribcage of arched ribs on a spine, a pelvis, and long bones thrown about with fat knobbed ends.
static func _bones(s: LowPoly.Soup, _p: Dictionary, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_skull(s, Vector3(0.0, 0.13, -0.5), 1.45, rng.randf_range(-40.0, 40.0))
	PropModels.rod(s, Vector3(0, 0.04, -0.36), Vector3(0, 0.04, 0.2), 0.03, 0.03, 4, BONE_DK)     # the spine
	for i in 4:
		var z := -0.3 + 0.1 * float(i)
		var w := 0.22 - 0.02 * float(i)
		for x: float in [-1.0, 1.0]:
			PropModels.rod(s, Vector3(0, 0.05, z), Vector3(x * w * 0.75, 0.14, z + 0.02), 0.024, 0.022, 4, BONE)
			PropModels.rod(s, Vector3(x * w * 0.75, 0.14, z + 0.02), Vector3(x * w, 0.03, z + 0.05), 0.022, 0.02, 4, BONE)
	PropModels.ball(s, Vector3(0.17, 0.06, 0.1), Vector3(0, 0.06, 0.27), BONE, 1, 0.1)                # the pelvis
	for i in 4:
		var a := rng.randf_range(0.0, TAU)
		var c := Vector3(rng.randf_range(-0.45, 0.45), 0.045, rng.randf_range(0.05, 0.65))
		var half := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.2, 0.3)
		PropModels.rod(s, c - half, c + half, 0.04, 0.035, 5, BONE)
		PropModels.ball(s, Vector3(0.07, 0.055, 0.07), c - half, BONE, 0, 0.1)
		PropModels.ball(s, Vector3(0.07, 0.055, 0.07), c + half, BONE, 0, 0.1)


# --- the church above: pew, altar ---------------------------------------------------------------------------------

## A pew, `length` along X: a seat, a back (toward -Z), two carved ends.
static func _pew(s: LowPoly.Soup, length: float) -> void:
	_box(s, Vector3(length, 0.07, 0.42), Vector3(0, 0.45, 0.02), WOOD)
	_box(s, Vector3(length, 0.5, 0.06), Vector3(0, 0.72, -0.2), WOOD, Vector3(-8.0, 0, 0))
	for x: float in [-1.0, 1.0]:
		_box(s, Vector3(0.07, 0.95, 0.55), Vector3(x * length * 0.5, 0.475, -0.02), WOOD_DK)
	_box(s, Vector3(length - 0.1, 0.06, 0.05), Vector3(0, 0.12, -0.15), WOOD_DK)


## A stone altar, long along X: a block on a step, a cloth runner hanging down the front, two candlesticks.
static func _altar(s: LowPoly.Soup, p: Dictionary) -> void:
	_box(s, Vector3(2.3, 0.14, 1.2), Vector3(0, 0.07, 0), p["stone_dk"])
	_box(s, Vector3(1.9, 0.82, 0.86), Vector3(0, 0.55, 0), p["stone"])
	_box(s, Vector3(2.0, 0.08, 0.95), Vector3(0, 1.0, 0), p["stone_lt"])
	_box(s, Vector3(1.5, 0.03, 0.97), Vector3(0, 1.055, 0), Color(0.9, 0.88, 0.82))
	_box(s, Vector3(0.6, 0.5, 0.03), Vector3(0, 0.8, 0.49), p["cloth"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for x: float in [-0.7, 0.7]:
		PropModels.cyl(s, 0.08, 0.05, 0.05, 6, Vector3(x, 1.09, -0.15), p["metal"])
		PropModels.cyl(s, 0.025, 0.025, 0.3, 5, Vector3(x, 1.25, -0.15), p["metal"])
		_candle(s, Vector3(x, 1.4, -0.15), 0.28, 0.035, p["wax"], rng)
