class_name GrimoireModel
extends Node3D
## LOOK-DEV ONLY (docs/design/necro-look.md): the grimoire, the haunted contracts' origin source (new-themes.md "Ghost
## house": "pulsing out the dead until it is slammed shut or burned", a host-arbitrated world object like a hellgate). This
## is only its look: no HP, no phases, nothing networked, and nothing in the game spawns it (only NecroBody, for the gym and
## the look lab). It is a physical object and NEVER text: blank glowing pages, an eye on the cover, rings and spokes on the
## floor, no letter or glyph anywhere (Cast is not a reading game).
##
## To read as the floor's big objective from across a room (the origin gate is about 7 across with horns about 6 up), the
## book is oversized (BOOK) and it is the middle of a set piece: a necromancer's circle on the floor round it (rings,
## spokes and dots in the ghost colour), candles with ghost-light flames, a column of pale light rising off the pages,
## loose pages circling in it, motes rising and a pale light on everything near it.
##   stand   lectern   a heavy dark-wood lectern on a stone step, the book open on its slanted desk
##           altar     a stone altar on a dais, a black runner over it, skulls at its feet, the book open on a rest
##   state   the book is only ever open or shut; how far it is beaten shows in the effects round it (the user, 2026-10-29:
##           "The damaged and burnt don't read correctly. Maybe let's do it with the effects surrounding the book
##           instead. The book itself could go from open to closed.")
##           open      the pages blazing and pulsing, the column up, pages circling, the circle and the candles lit
##           weakened  the book still open: the column thinner and stuttering, fewer pages circling, the circle broken in
##                     places, two candles out
##           failing   the book still open: the column a flickering thread, one page left, most of the circle and four
##                     candles out, the light low, its flicker tending red (FAIL_RED)
##           shut      slammed shut: a closed, chained book with the eye on its cover, every light out, pages fallen
## Faces local -Z (the reader's side), origin on the floor at its middle. freeze_at() holds a moment for the lab.

const STANDS: Array[String] = ["lectern", "altar"]
const STATES: Array[String] = ["open", "weakened", "failing", "shut"]
## How much of the effects each state keeps (1 open, 0 shut).
const POWER := {"open": 1.0, "weakened": 0.6, "failing": 0.3, "shut": 0.0}
## A failing book's flicker turns red (the user, 2026-10-29: "Failing - maybe we have the flicker tend red?"): its lights
## lean toward FAIL_RED, more the weaker it is and most in a stutter's dips.
const FAIL_RED := Color(1.0, 0.16, 0.12)
const BOOK := Vector2(1.7, 1.15)      ## the open book: across both pages, and the page height (front to back)
const PAGES := 7                      ## loose pages circling in the column
const SIGIL := {"lectern": 5.2, "altar": 6.0}   ## the circle across (before SCALE)
## The whole set piece: the altar an outsized tome to hold its own beside an origin gate; the lectern much smaller (the
## user, 2026-10-29: "The lectern should be much smaller").
const SCALE := {"lectern": 0.85, "altar": 1.4}

const WOOD := Color(0.27, 0.17, 0.11)
const WOOD_LIGHT := Color(0.36, 0.24, 0.15)
const WOOD_DARK := Color(0.16, 0.10, 0.07)
const STONE := Color(0.40, 0.39, 0.40)
const STONE_LIGHT := Color(0.50, 0.49, 0.50)
const STONE_DARK := Color(0.27, 0.26, 0.28)
const IRON := Color(0.24, 0.25, 0.28)
const IRON_LIGHT := Color(0.40, 0.41, 0.45)
const LEATHER := Color(0.13, 0.16, 0.15)          ## the cover: a black-green hide, not the hell family's red
const LEATHER_LIGHT := Color(0.20, 0.24, 0.22)
const BONE := Color(0.86, 0.82, 0.70)
const BONE_DARK := Color(0.66, 0.61, 0.50)
const PARCHMENT := Color(0.84, 0.78, 0.62)
const PARCHMENT_DARK := Color(0.66, 0.59, 0.45)
const CLOTH := Color(0.11, 0.13, 0.13)
const WAX := Color(0.86, 0.83, 0.72)
const VOID := Color(0.05, 0.04, 0.05)
const EYE_R := Vector3(0.28, 0.19, 0.23)          ## the live eye's eyeball (radii)
const EYE_AT := Vector3(0.03, 0.34, 0.0)          ## its centre on the shut book
const EYE_REST := Vector3(0, 0.62, -0.78) * (1.0 / 0.99640)   ## where it looks at rest: up and out over the front edge
const EYE_WHITE := Color(0.86, 0.80, 0.62)        ## yellowed, not paper white
const VEIN := Color(0.70, 0.10, 0.10)
const IRIS := Color(0.95, 0.75, 0.15)
const FLESH := Color(0.46, 0.24, 0.24)
const FLESH_DARK := Color(0.30, 0.14, 0.15)

## The column of light off the pages: additive bands rising and fading (the hellgate's vortex, in the ghost colour).
const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float t = 0.0;
uniform float amount = 1.0;
uniform vec4 tint : source_color = vec4(0.70, 0.86, 1.0, 1.0);

void fragment() {
	float v = UV.y;
	float fade = pow(1.0 - v, 1.2) * smoothstep(0.0, 0.08, 1.0 - v);
	float s = 0.5 + 0.5 * sin(UV.x * 6.2831 * 4.0 - v * 7.0 + t * 1.6);
	s = floor(s * 3.0) / 3.0;
	float rise = 0.5 + 0.5 * sin(v * 18.0 - t * 3.0);
	float a = clamp(fade * (0.35 + 0.45 * s + 0.25 * rise) * amount, 0.0, 0.75);
	ALBEDO = tint.rgb * a;
	ALPHA = 1.0;
}
"""

static var _beam_shader: Shader

var stand := "lectern"
var state := "open"
var ui_height := 3.0
var book_top := Vector3.ZERO          ## the open pages' middle (local), where the column and the light start

var _mat: ShaderMaterial
var _t := 0.0
var _frozen := false
var _phase := 0.0
var _book: MeshInstance3D
var _iris: MeshInstance3D            ## the shut book's live eye's iris (it looks around)
var _sigil: MeshInstance3D
var _beam: MeshInstance3D
var _beam_mat: ShaderMaterial
var _light: OmniLight3D
var _orbit: Array[Dictionary] = []   ## {node, ang, speed, rad, y, spin}
var _parts: Array[MeshInstance3D] = []


static func make(stand_name: String = "lectern", state_name: String = "open", phase: float = 0.0) -> GrimoireModel:
	var g := GrimoireModel.new()
	g.stand = stand_name if STANDS.has(stand_name) else "lectern"
	g.state = state_name if STATES.has(state_name) else "open"
	g._phase = phase
	g._build()
	return g


func is_lit() -> bool:
	return state != "shut"


## How much of the effects this state keeps (POWER).
func power() -> float:
	return float(POWER[state])


## Lab / screenshots: hold the animation at `seconds`.
func freeze_at(seconds: float) -> void:
	_frozen = true
	_t = seconds
	_animate()


func triangle_count() -> int:
	var n := 0
	for mi in _parts:
		n += (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


# ------------------------------------------------------------------ build

func _build() -> void:
	name = "Grimoire_%s_%s" % [stand, state]
	scale = Vector3.ONE * float(SCALE[stand])
	_mat = NecroLook.body_material(2.6, 0.0)
	_mat.set_shader_parameter("glow_gain", 1.8)
	var pw := power()
	var book_xf: Transform3D
	if stand == "altar":
		_mesh("Altar", _altar_soup(), self)
		book_xf = Transform3D(Basis(Vector3(1, 0, 0), -0.22), Vector3(0, 1.26, 0.02))
	else:
		_mesh("Lectern", _lectern_soup(), self)
		var desk := Node3D.new()
		desk.name = "Desk"
		desk.position = Vector3(0, 1.16, 0.0)
		desk.rotation.x = -0.30
		add_child(desk)
		_mesh("DeskTop", _desk_soup(), desk)
		book_xf = desk.transform * Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0.0))
	var book := Node3D.new()
	book.name = "Book"
	book.transform = book_xf
	add_child(book)
	_book = _mesh("Pages", _shut_soup() if state == "shut" else _open_soup(), book)
	if state == "shut":
		_iris = _mesh("Iris", _iris_soup(), book)
	book_top = book_xf * Vector3(0, 0.2, 0)
	_mesh("Candles", _candles_soup(), self)
	if state == "shut":
		_mesh("Floor", _floor_soup(), self)
	var size: float = SIGIL[stand]
	_sigil = NecroLook.floor_glow(size, true, 1.0, _phase)
	_sigil.position.y = 0.03
	(_sigil.material_override as ShaderMaterial).set_shader_parameter("spin", 0.04)
	(_sigil.material_override as ShaderMaterial).set_shader_parameter("broken", 1.0 - pw)
	_sigil.visible = is_lit()
	add_child(_sigil)
	if is_lit():
		_build_beam(pw)
		_build_orbit()
		var m := NecroLook.motes(maxi(int(26 * pw), 4), 0.55, 0.9, 0.045)
		m.position = book_top
		add_child(m)
		_light = OmniLight3D.new()
		_light.name = "BookLight"
		_light.light_color = NecroLook.glow_colour()
		_light.omni_range = 10.0
		_light.omni_attenuation = 1.4
		_light.light_specular = 0.1
		_light.shadow_enabled = false
		_light.position = book_top + Vector3(0, 0.9, 0)
		add_child(_light)
	ui_height = (3.2 if stand == "lectern" else 3.0) * float(SCALE[stand])
	_animate()


func _mesh(node_name: String, soup: LowPoly.Soup, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = soup.to_mesh(0.26)
	mi.material_override = _mat
	parent.add_child(mi)
	_parts.append(mi)
	return mi


## A quad facing `out` whatever order its corners come in.
static func _face(s: LowPoly.Soup, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out: Vector3) -> void:
	if (b - a).cross(c - b).dot(out) > 0.0:
		s.add_quad(d, c, b, a, col)
	else:
		s.add_quad(a, b, c, d, col)


## The lectern: a stone step, a thick turned post of dark wood with iron bands and a carved knot, brackets up to the desk.
func _lectern_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1101, 0.07)
	s.merge(LowPoly.cylinder(0.70, 0.66, 0.16, 8, STONE_DARK, 1102, 0.01), LowPoly.at(Vector3(0, 0.08, 0)))
	s.merge(LowPoly.cylinder(0.50, 0.47, 0.13, 8, STONE, 1103, 0.01), LowPoly.at(Vector3(0, 0.225, 0)))
	MonsterModel.limb(s, Vector3(0, 0.28, 0), Vector3(0, 1.06, 0), 0.19, 0.14, 8, WOOD_DARK, 1104)
	for y: float in [0.36, 0.98]:
		s.merge(LowPoly.cylinder(0.20, 0.20, 0.06, 8, IRON, 1105, 0.0), LowPoly.at(Vector3(0, y, 0)))
	MonsterModel.blob(s, Vector3(0, 0.66, 0), Vector3(0.23, 0.13, 0.23), WOOD, 1106, 0.12)          # the carved knot
	for x: float in [-1.0, 1.0]:
		MonsterModel.wedge(s, Vector3(0.30 * x, 1.04, 0), Vector2(0.10, 0.20), Vector2(0.10, 0.50), 0.14, WOOD_DARK, 1107 + int(x), Vector3(0, 0, -36.0 * x))   # brackets
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		MonsterModel.wedge(s, Vector3(cos(a) * 0.36, 0.33, sin(a) * 0.36), Vector2(0.16, 0.14), Vector2(0.08, 0.08), 0.10, IRON_LIGHT, 1110 + i, Vector3(0, rad_to_deg(-a), 0))   # claws
	return s


## The lectern's slanted desk (local: flat, tilted by its node), a lip at the front to hold the book, iron corners.
func _desk_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1121, 0.06)
	MonsterModel.slab(s, Vector3(0, 0, 0.0), Vector3(1.95, 0.08, 1.32), WOOD, 1122, Vector3.ZERO, 0.01)
	MonsterModel.slab(s, Vector3(0, 0.07, -0.66), Vector3(1.95, 0.10, 0.07), WOOD_DARK, 1123)
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			MonsterModel.slab(s, Vector3(0.92 * x, 0.045, 0.61 * z), Vector3(0.14, 0.02, 0.14), IRON_LIGHT, 1124, Vector3(0, 45, 0))
	return s


## The altar: a stone dais, the altar block with a carved front panel and a heavy top, a black runner over it and down the
## front with a bone trim, a low book rest, piles of skulls at its feet.
func _altar_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1131, 0.07)
	MonsterModel.slab(s, Vector3(0, 0.11, 0), Vector3(3.7, 0.22, 2.6), STONE_DARK, 1132, Vector3.ZERO, 0.01)
	MonsterModel.slab(s, Vector3(0, 0.30, 0.05), Vector3(3.0, 0.16, 1.9), STONE, 1133, Vector3.ZERO, 0.01)
	MonsterModel.slab(s, Vector3(0, 0.75, 0.08), Vector3(2.4, 0.74, 1.2), STONE_DARK, 1134, Vector3.ZERO, 0.01)
	MonsterModel.slab(s, Vector3(0, 1.17, 0.08), Vector3(2.75, 0.12, 1.45), STONE_LIGHT, 1135, Vector3.ZERO, 0.01)
	MonsterModel.slab(s, Vector3(0, 0.74, -0.53), Vector3(1.9, 0.48, 0.04), STONE, 1136)
	for x: float in [-1.0, 1.0]:
		MonsterModel.slab(s, Vector3(0.62 * x, 0.74, -0.555), Vector3(0.10, 0.40, 0.03), STONE_DARK, 1137 + int(x))   # carved panels
	MonsterModel.slab(s, Vector3(0, 1.24, 0.08), Vector3(0.80, 0.025, 1.47), CLOTH, 1140)
	MonsterModel.slab(s, Vector3(0, 0.92, -0.655), Vector3(0.80, 0.62, 0.025), CLOTH, 1141)
	MonsterModel.slab(s, Vector3(0, 0.62, -0.665), Vector3(0.82, 0.04, 0.02), BONE, 1142)
	MonsterModel.wedge(s, Vector3(0, 1.30, 0.06), Vector2(0.9, 0.7), Vector2(0.9, 0.5), 0.10, WOOD_DARK, 1143)   # the rest
	# skulls at the front corners of the dais
	var k := 0
	for x: float in [-1.0, 1.0]:
		for p: Vector3 in [Vector3(1.45, 0.30, -1.0), Vector3(1.22, 0.30, -1.08), Vector3(1.34, 0.46, -1.02)]:
			_skull(s, Vector3(p.x * x, p.y, p.z), 1150 + k, 25.0 * x)
			k += 4
	return s


func _skull(s: LowPoly.Soup, p: Vector3, seed_value: int, yaw: float) -> void:
	var f := Basis(Vector3.UP, deg_to_rad(yaw))
	MonsterModel.blob(s, p, Vector3(0.12, 0.10, 0.12), BONE, seed_value, 0.1)
	for x: float in [-1.0, 1.0]:
		MonsterModel.slab(s, p + f * Vector3(0.045 * x, 0.0, -0.10), Vector3(0.045, 0.04, 0.03), VOID, seed_value + 1)
	MonsterModel.slab(s, p + f * Vector3(0, -0.07, -0.08), Vector3(0.09, 0.03, 0.04), BONE_DARK, seed_value + 2)


## The open book, its spine along Z, origin under the spine: two covers in a shallow V, two page blocks rising to the
## gutter, iron corners and clasps hanging open. The page tops glow in the ghost colour (no marks on them, ever). It looks
## the same in every open state: how far it is beaten shows in the effects round it.
func _open_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1201, 0.05)
	var hw := BOOK.x * 0.5
	var hd := BOOK.y * 0.5
	var c := NecroLook.glow_colour()
	var page_glow := MonsterModel.glow(c.lerp(Color(1.0, 0.98, 0.92), 0.3) * 0.62)
	var page_soft := MonsterModel.glow(PARCHMENT.lerp(c, 0.35) * 0.48)
	for side: int in [-1, 1]:
		var x := float(side)
		MonsterModel.slab(s, Vector3(x * (hw * 0.5 + 0.02), 0.02, 0), Vector3(hw + 0.06, 0.05, BOOK.y + 0.08), LEATHER, 1202 + side, Vector3(0, 0, 4.0 * x))
		for z: float in [-1.0, 1.0]:
			MonsterModel.wedge(s, Vector3(x * (hw - 0.02), 0.05, z * (hd + 0.0)), Vector2(0.16, 0.16), Vector2(0.10, 0.10), 0.03, IRON_LIGHT, 1204, Vector3(0, 45, 0))
		# the page block: strips from the gutter out, rising to a crown and falling to the edge
		var xs: Array[float] = [0.02, 0.14, 0.42, 0.66, 0.80]
		var ys: Array[float] = [0.10, 0.20, 0.215, 0.18, 0.12]
		for i in xs.size() - 1:
			var x0 := xs[i] * hw / 0.8 * x
			var x1 := xs[i + 1] * hw / 0.8 * x
			var y0 := ys[i]
			var y1 := ys[i + 1]
			# the light wells up from the gutter: glowing there, parchment lit by it at the edges
			var top := page_glow if i < 2 else (page_soft if i == 2 else PARCHMENT)
			_face(s, Vector3(x0, y0, -hd), Vector3(x1, y1, -hd), Vector3(x1, y1, hd), Vector3(x0, y0, hd), top, Vector3.UP)
			_face(s, Vector3(x0, y0, -hd), Vector3(x1, y1, -hd), Vector3(x1, 0.05, -hd), Vector3(x0, 0.05, -hd), PARCHMENT, Vector3(0, 0, -1))
			_face(s, Vector3(x0, y0, hd), Vector3(x1, y1, hd), Vector3(x1, 0.05, hd), Vector3(x0, 0.05, hd), PARCHMENT_DARK, Vector3(0, 0, 1))
		var xe := xs[xs.size() - 1] * hw / 0.8 * x
		var ye := ys[ys.size() - 1]
		_face(s, Vector3(xe, ye, -hd), Vector3(xe, ye, hd), Vector3(xe, 0.05, hd), Vector3(xe, 0.05, -hd), PARCHMENT_DARK, Vector3(x, 0, 0))
		# the clasp straps hanging open off the outer edge
		MonsterModel.slab(s, Vector3(x * (hw + 0.12), -0.02, -0.20), Vector3(0.22, 0.03, 0.10), LEATHER_LIGHT, 1206 + side, Vector3(0, 0, -50.0 * x))
		MonsterModel.slab(s, Vector3(x * (hw + 0.20), -0.10, -0.20), Vector3(0.06, 0.05, 0.12), IRON_LIGHT, 1208 + side)
	# a ribbon hanging from the gutter over the front edge
	MonsterModel.slab(s, Vector3(0.05, 0.02, -hd - 0.05), Vector3(0.05, 0.22, 0.015), BONE_DARK, 1211, Vector3(20, 0, 0))
	return s


## The shut book: a thick closed block lying flat, the page edges showing on three sides, a live eye bulging from the
## cover (a picture, not a letter; its iris is a separate node), iron corners, a clasp shut across it and a chain round it.
func _shut_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1221, 0.05)
	var w := BOOK.x * 0.5 + 0.08
	var d := BOOK.y + 0.08
	MonsterModel.slab(s, Vector3(0.0, 0.03, 0), Vector3(w, 0.06, d), LEATHER, 1222)
	MonsterModel.slab(s, Vector3(0.02, 0.15, 0), Vector3(w - 0.06, 0.20, d - 0.06), PARCHMENT_DARK, 1223)
	MonsterModel.slab(s, Vector3(0.0, 0.28, 0), Vector3(w, 0.06, d), LEATHER_LIGHT, 1224)
	MonsterModel.slab(s, Vector3(-w * 0.5, 0.155, 0), Vector3(0.10, 0.31, d + 0.02), LEATHER, 1225)          # the spine
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			MonsterModel.wedge(s, Vector3(x * (w * 0.5 - 0.05), 0.315, z * (d * 0.5 - 0.05)), Vector2(0.16, 0.16), Vector2(0.10, 0.10), 0.03, IRON_LIGHT, 1226, Vector3(0, 45, 0))
	# the eye: alive, bulging out of the cover (the user, 2026-10-29: "A live eye: keep it fleshy, but make it bulge out of
	# the cover, with veins and a lid half closed. It reads as creepy and alive."): puffy lips of flesh round its socket, a
	# yellowed eyeball with red veins crawling to the iris, a yellow iris with a slit pupil looking out over the front edge
	# (-Z), and a heavy upper lid drooping half over it
	_live_eye(s, EYE_AT - Vector3(0, 0.03, 0))
	# the clasp across the fore edge, and the chain round the middle
	MonsterModel.slab(s, Vector3(w * 0.5 + 0.01, 0.155, -0.18), Vector3(0.04, 0.34, 0.12), LEATHER_LIGHT, 1230)
	MonsterModel.slab(s, Vector3(w * 0.5 + 0.03, 0.20, -0.18), Vector3(0.05, 0.10, 0.10), IRON_LIGHT, 1231)
	for i in 9:
		var x := -w * 0.5 - 0.04 + (w + 0.08) * float(i) / 8.0
		var size := Vector3(0.10, 0.03, 0.05) if i % 2 == 0 else Vector3(0.10, 0.05, 0.03)
		MonsterModel.slab(s, Vector3(x, 0.33, 0.25), size, IRON, 1232 + i)
		MonsterModel.slab(s, Vector3(x, -0.005, 0.25), size, IRON, 1242 + i)
	return s


## The live eye on the shut cover, its base at `c` (on the cover's top): flesh lips, the eyeball, veins, the iris and
## pupil, the drooping lid. The eyeball is an ellipsoid of radii EYE_R centred a little above the cover.
static func _live_eye(s: LowPoly.Soup, c: Vector3) -> void:
	var o := c + Vector3(0, 0.03, 0)
	# the lips: a smooth puffy rim of flesh round the socket (separate lumps read as petals)
	for i in 18:
		var a := TAU * float(i) / 18.0
		var at := c + Vector3(cos(a) * (EYE_R.x + 0.015), 0.025, sin(a) * (EYE_R.z + 0.012))
		MonsterModel.blob(s, at, Vector3(0.06, 0.045, 0.06), FLESH, 1260 + i, 0.04)
	MonsterModel.blob(s, o, EYE_R, EYE_WHITE, 1275, 0.02, 1)
	# the veins: from round the base up toward the iris, along the eyeball's surface, each forking once
	var iris_dir := EYE_REST
	for i in 7:
		var a := TAU * (float(i) + 0.3) / 7.0
		var from := Vector3(cos(a), 0.15, sin(a)).normalized()
		var pts: Array[Vector3] = []
		for k in 4:
			var d := from.slerp(iris_dir, 0.22 * float(k) + 0.05).normalized()
			pts.append(o + d * EYE_R * 1.03)
		for k in 3:
			PropModels.rod(s, pts[k], pts[k + 1], 0.016 - 0.003 * float(k), 0.013 - 0.003 * float(k), 3, VEIN)
		var fork := from.rotated(Vector3.UP, 0.5).slerp(iris_dir, 0.4).normalized()
		PropModels.rod(s, pts[1], o + fork * EYE_R * 1.03, 0.011, 0.007, 3, VEIN)
	# the upper lid: a heavy fold of the cover's hide over the back of the eyeball, its edge above the iris (raised: the
	# user, "Raise the top lid more"). The iris is its own node (`_iris_soup`), so it can look around.
	MonsterModel.blob(s, o + Vector3(0, 0.12, 0.15), Vector3(EYE_R.x * 1.1, 0.09, 0.12), FLESH_DARK, 1292, 0.08, 1)
	MonsterModel.blob(s, o + Vector3(0, 0.15, 0.10), Vector3(EYE_R.x * 0.98, 0.05, 0.05), FLESH, 1293, 0.06)


## The live eye's iris and slit pupil, facing +Z from the origin (`_look` puts it on the eyeball and turns it).
static func _iris_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1289, 0.05)
	MonsterModel.blob(s, Vector3.ZERO, Vector3(0.125, 0.125, 0.04), MonsterModel.glow(IRIS * 0.55), 1290, 0.02)
	MonsterModel.blob(s, Vector3(0, 0, 0.032), Vector3(0.028, 0.10, 0.02), VOID, 1291, 0.02)
	return s


## Where the live eye looks at time `t`: it holds a gaze, then darts to the next (a few per few seconds), round its rest
## direction out over the front edge. Returns the direction from the eyeball's centre (book space).
static func eye_dir(t: float) -> Vector3:
	var slot := floorf(t / 1.1)
	var into := clampf((t - slot * 1.1) / 0.12, 0.0, 1.0)          # a quick dart at the start of each hold
	var a := _gaze(slot - 1.0).lerp(_gaze(slot), into * into * (3.0 - 2.0 * into))
	return EYE_REST.rotated(Vector3.UP, a.x).rotated(Vector3.RIGHT, a.y).normalized()


static func _gaze(slot: float) -> Vector2:
	var h := fposmod(sin(slot * 12.9898) * 43758.5453, 1.0)
	var k := fposmod(sin(slot * 78.233) * 12543.123, 1.0)
	return Vector2((h - 0.5) * 1.3, (k - 0.5) * 0.45)


## Put the iris on the eyeball's surface, facing `d`.
func _look(d: Vector3) -> void:
	var r := 1.0 / sqrt(pow(d.x / EYE_R.x, 2) + pow(d.y / EYE_R.y, 2) + pow(d.z / EYE_R.z, 2))
	_iris.transform = Transform3D(Basis.looking_at(-d, Vector3.UP), EYE_AT + d * (r - 0.012))


## Candles: tall wax stubs with ghost-light flames, round the circle (the lectern) or on the altar's corners and the dais.
## Weakened: two out. Failing: four out. Shut: all out.
func _candles_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1301, 0.06)
	var spots: Array[Vector3] = []
	if stand == "altar":
		spots = [Vector3(-1.2, 1.23, -0.55), Vector3(1.2, 1.23, -0.55), Vector3(-1.2, 1.23, 0.7), Vector3(1.2, 1.23, 0.7),
				Vector3(-1.75, 0.0, -1.55), Vector3(1.75, 0.0, -1.55), Vector3(0.0, 0.0, -1.75)]
	else:
		var r: float = SIGIL["lectern"] * 0.5 * 0.80
		for i in 6:
			var a := TAU * float(i) / 6.0 + PI / 6.0
			spots.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	var out_n: int = {"open": 0, "weakened": 2, "failing": 4}.get(state, spots.size())
	var out_order: Array[int] = [1, 4, 0, 3, 2, 5, 6]
	for i in spots.size():
		var p := spots[i]
		var h := 0.42 + 0.14 * float(i % 3)
		var lit := out_order.find(i) >= out_n
		s.merge(LowPoly.cylinder(0.12, 0.10, 0.04, 6, IRON, 1310 + i, 0.0), LowPoly.at(p + Vector3(0, 0.02, 0)))
		s.merge(LowPoly.cylinder(0.055, 0.05, h, 6, WAX, 1320 + i, 0.004), LowPoly.at(p + Vector3(0, 0.04 + h * 0.5, 0)))
		MonsterModel.blob(s, p + Vector3(0.05, 0.04 + h * 0.75, 0.0), Vector3(0.025, 0.06, 0.025), WAX.darkened(0.08), 1330 + i, 0.2)   # a drip
		if lit:
			MonsterModel.blob(s, p + Vector3(0, 0.04 + h + 0.07, 0), Vector3(0.045, 0.09, 0.045), NecroLook.glow(1.15), 1340 + i, 0.1)
	return s


## On the floor round it once it is shut: the pages that were circling, fallen. Pages are blank.
func _floor_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(1401, 0.06)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1403
	var n := 8
	var r0 := 1.3 if stand == "lectern" else 2.1
	for i in n:
		var a := TAU * float(i) / float(n) + rng.randf_range(-0.3, 0.3)
		var r := r0 + rng.randf_range(0.0, 0.9)
		MonsterModel.slab(s, Vector3(cos(a) * r, 0.012 + 0.004 * i, sin(a) * r), Vector3(0.30, 0.012, 0.40), PARCHMENT, 1404 + i, Vector3(rng.randf_range(-6, 6), rng.randf_range(0, 180), rng.randf_range(-6, 6)))
	return s


## The column off the pages, thinner the weaker the book (`pw`, POWER).
func _build_beam(pw: float) -> void:
	if _beam_shader == null:
		_beam_shader = Shader.new()
		_beam_shader.code = BEAM_SHADER
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = _beam_shader
	_beam_mat.set_shader_parameter("tint", NecroLook.glow_colour())
	var cone := CylinderMesh.new()
	cone.top_radius = lerpf(0.06, 0.30, pw)
	cone.bottom_radius = lerpf(0.22, 0.80, pw)
	cone.height = 5.5
	cone.radial_segments = 10
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	_beam = MeshInstance3D.new()
	_beam.name = "Column"
	_beam.mesh = cone
	_beam.material_override = _beam_mat
	_beam.position = book_top + Vector3(0, cone.height * 0.5 - 0.1, 0)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.set_meta("no_flash", true)
	add_child(_beam)


## Loose pages circling in the column: blank, glowing a little at their edges.
func _build_orbit() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1501
	var n := maxi(roundi(PAGES * power() * power()), 1)
	var page := LowPoly.Soup.new(1502, 0.04)
	MonsterModel.slab(page, Vector3.ZERO, Vector3(0.30, 0.015, 0.40), PARCHMENT, 1503)
	MonsterModel.slab(page, Vector3(0, 0.009, 0), Vector3(0.24, 0.004, 0.34), NecroLook.glow(0.9), 1504)
	var mesh := page.to_mesh(0.26)
	for i in n:
		var holder := Node3D.new()
		holder.name = "Page%d" % i
		add_child(holder)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		_orbit.append({"node": holder, "ang": TAU * float(i) / float(n) + rng.randf_range(-0.3, 0.3), "speed": rng.randf_range(0.35, 0.6),
				"rad": rng.randf_range(0.85, 1.35), "y": rng.randf_range(0.7, 2.1), "spin": rng.randf_range(0.8, 1.6)})


# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	if _frozen:
		return
	_t += delta
	_animate()


func _animate() -> void:
	var t := _t + _phase
	var lit := is_lit()
	var pw := power()
	# the pages' heartbeat (the origin gate's slow pulse); a beaten book stutters, harder the weaker it is
	var beat := 0.5 + 0.5 * sin(t * 1.7)
	var stutter := 1.0
	if lit and pw < 1.0:
		var dip := 1.0 - pw
		stutter = 1.0 - dip * (1.0 - step_f(0.35 - 0.5 * dip, sin(t * 7.3) * sin(t * 2.9 + 1.0)))
	# the lights' colour: the ghost colour, leaning red as the book fails (in a dip most)
	var tint := NecroLook.glow_colour()
	if lit and pw < 0.5:
		var red := (0.5 - pw) * 2.0
		var flash := (1.0 - stutter) / maxf(1.0 - pw, 0.01)   # 1 in a stutter's dip, 0 between
		tint = tint.lerp(FAIL_RED, clampf(red * 1.1 + flash * 0.5, 0.0, 1.0))
	_mat.set_shader_parameter("glow_gain", (1.4 + 0.8 * beat) * stutter if lit else 1.8)
	if _iris != null:
		_look(eye_dir(t))
	if _sigil != null:
		var sm := _sigil.material_override as ShaderMaterial
		sm.set_shader_parameter("clock", t)
		sm.set_shader_parameter("tint", tint)
		sm.set_shader_parameter("strength", (0.85 + 0.25 * beat) * lerpf(0.5, 1.0, pw) * stutter)
	if _beam_mat != null:
		_beam_mat.set_shader_parameter("t", t)
		_beam_mat.set_shader_parameter("tint", tint)
		_beam_mat.set_shader_parameter("amount", (0.85 + 0.35 * beat) * lerpf(0.35, 1.0, pw) * stutter)
	if _light != null and lit:
		_light.light_energy = (3.2 + 1.6 * beat) * lerpf(0.3, 1.0, pw) * stutter
		_light.light_color = tint
	for o in _orbit:
		var node: Node3D = o["node"]
		var a := float(o["ang"]) + float(o["speed"]) * t
		var y := book_top.y + float(o["y"]) + 0.15 * sin(t * 1.3 + float(o["ang"]) * 3.0)
		node.position = Vector3(book_top.x + cos(a) * float(o["rad"]), y, book_top.z + sin(a) * float(o["rad"]))
		node.rotation = Vector3(0.6 * sin(t * float(o["spin"]) + float(o["ang"])), -a, 0.4 * cos(t * float(o["spin"]) * 0.7))


static func step_f(edge: float, x: float) -> float:
	return 0.0 if x < edge else 1.0
