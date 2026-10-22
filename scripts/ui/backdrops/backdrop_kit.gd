extends RefCounted
## Shared pieces for the 3D menu backdrops (MenuBackdrop, which the job board reuses, and the storefront prototype in the
## options lab). Static helpers plus a few tiny animator nodes. Everything is built from the existing LowPoly kit
## and drawn with the prop look (MonsterMaterial: flat facets, ink outline, amber rim; vertex alpha 0.5 glows).
## Presentation only: no GameWorld, no actors, no global random (animators own a RandomNumberGenerator).
##
## No class_name on purpose: users preload this file, so it never touches the global class cache.

const INK := Color(0.12, 0.11, 0.13)
const PAPER := Color(0.93, 0.89, 0.76)
const PAPER_OLD := Color(0.86, 0.80, 0.62)
const FLAME := Color(1.0, 0.52, 0.12)
const FLAME_HOT := Color(1.0, 0.85, 0.42)
const TORCH_LIGHT := Color(1.0, 0.6, 0.28)

## 5x7 neon glyphs (a superset of DecorModels.GLYPHS: S, T, R, D, H, U ... and the digits we need).
const GLYPHS := {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".####", "#....", "#....", "#..##", "#...#", "#...#", ".###."],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
	"-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
	"!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
	"&": [".##..", "#..#.", "#.#..", ".#...", "#.#.#", "#..#.", ".##.#"],
}

static var _seed := 500


static func n() -> int:
	_seed += 1
	return _seed


static func glow(c: Color) -> Color:
	return Color(c.r, c.g, c.b, MonsterMaterial.GLOW_ALPHA)


static func box(s: LowPoly.Soup, size: Vector3, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
	s.merge(LowPoly.box(size, col, n(), 0.0, 1, 0.06), LowPoly.at(pos, rot))


static func cyl(s: LowPoly.Soup, r_bottom: float, r_top: float, h: float, sides: int, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
	s.merge(LowPoly.cylinder(r_bottom, r_top, h, sides, col, n(), 0.0, 1, 0.06), LowPoly.at(pos, rot))


static func rod(s: LowPoly.Soup, a: Vector3, b: Vector3, r_a: float, r_b: float, sides: int, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.0001:
		return
	var up := d / length
	var axis := Vector3.UP.cross(up)
	var basis := Basis.IDENTITY
	if axis.length() > 0.0001:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(up))
	elif up.y < 0.0:
		basis = Basis(Vector3.RIGHT, PI)
	s.merge(LowPoly.cylinder(r_a, r_b, length, sides, col, n(), 0.0, 1, 0.06), Transform3D(basis, (a + b) * 0.5))


## A soup as a MeshInstance3D with the prop look.
static func mesh(s: LowPoly.Soup, outline: float = 2.2, node_name: String = "Body") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = s.to_mesh()
	var m := MonsterMaterial.make(outline)
	m.set_shader_parameter("glow_gain", 1.6)
	mi.material_override = m
	return mi


static func put(parent: Node3D, node: Node3D, pos: Vector3, yaw_deg: float = 0.0, scl: float = 1.0) -> Node3D:
	parent.add_child(node)
	node.position = pos
	node.rotation.y = deg_to_rad(yaw_deg)
	if scl != 1.0:
		node.scale = Vector3.ONE * scl
	return node


static func omni(parent: Node3D, pos: Vector3, col: Color, energy: float, rng: float, shadow: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.6
	l.light_specular = 0.25
	l.shadow_enabled = shadow
	parent.add_child(l)
	return l


# --- pieces ---------------------------------------------------------------------------------------------------------

## A wall torch: iron bracket, wrapped stick, faceted flame and (with_light) a flickering warm light, named "Light"
## with its Flicker named "Flicker". Faces +Z. A torch without a light still burns (the flame is emissive); lights are
## the backdrops' cost, so only a few torches get one.
static func torch(seed_value: int, energy: float = 2.6, with_light: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Torch"
	var s := LowPoly.Soup.new(seed_value, 0.06)
	box(s, Vector3(0.22, 0.34, 0.06), Vector3(0, 0, -0.03), PropModels.IRON)
	rod(s, Vector3(0, -0.08, 0.0), Vector3(0, 0.05, 0.32), 0.035, 0.035, 5, PropModels.IRON_LT)
	rod(s, Vector3(0, -0.25, 0.30), Vector3(0, 0.32, 0.36), 0.05, 0.065, 6, PropModels.WOOD_DK)
	cyl(s, 0.09, 0.12, 0.14, 6, Vector3(0, 0.33, 0.36), PropModels.IRON)
	rod(s, Vector3(0, 0.38, 0.36), Vector3(0.02, 0.78, 0.38), 0.13, 0.0, 5, glow(FLAME))
	rod(s, Vector3(-0.05, 0.38, 0.38), Vector3(-0.09, 0.64, 0.40), 0.08, 0.0, 5, glow(FLAME_HOT))
	rod(s, Vector3(0.05, 0.38, 0.34), Vector3(0.09, 0.6, 0.33), 0.07, 0.0, 5, glow(Color(1.0, 0.35, 0.08)))
	root.add_child(mesh(s, 1.6))
	if not with_light:
		return root
	var l := omni(root, Vector3(0, 0.75, 0.75), TORCH_LIGHT, energy, 6.5, false)
	l.name = "Light"
	var f := Flicker.new()
	f.name = "Flicker"
	f.light = l
	f.base = energy
	f.phase = float(seed_value) * 1.37
	root.add_child(f)
	return root


## A tacked-up paper sign: a slightly curled sheet, four tacks, Label3D lettering. Faces +Z.
static func paper_sign(text: String, size: Vector2, font_size: int = 64, paper: Color = PAPER, ink: Color = INK) -> Node3D:
	var root := Node3D.new()
	root.name = "PaperSign"
	var s := LowPoly.Soup.new(n(), 0.03)
	box(s, Vector3(size.x, size.y, 0.02), Vector3.ZERO, paper)
	box(s, Vector3(size.x * 0.32, size.y * 0.3, 0.021), Vector3(size.x * 0.34, -size.y * 0.35, 0.004), paper.darkened(0.08), Vector3(0, 0, 0))
	for cx: float in [-0.5, 0.5]:
		for cy: float in [-0.5, 0.5]:
			cyl(s, 0.035, 0.035, 0.03, 6, Vector3(cx * (size.x - 0.12), cy * (size.y - 0.12), 0.02), Color(0.8, 0.15, 0.12), Vector3(90, 0, 0))
	root.add_child(mesh(s, 1.2))
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = font_size
	lbl.pixel_size = 0.0042
	lbl.modulate = ink
	lbl.outline_size = 0
	lbl.shaded = true
	lbl.double_sided = false
	lbl.width = size.x / lbl.pixel_size * 0.92
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.position = Vector3(0, 0, 0.016)
	lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	root.add_child(lbl)
	return root


## Flat lettering (a painted decal) facing +Z.
static func decal_text(text: String, font_size: int, col: Color, pixel: float = 0.004) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = font_size
	lbl.pixel_size = pixel
	lbl.modulate = col
	lbl.outline_size = 0
	lbl.shaded = true
	lbl.double_sided = false
	lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return lbl


## Pixel-tube neon lettering, one mesh per letter so they flicker (and die) one by one. Faces +Z.
## `dead`: indices of burnt-out letters. Returns the root; width = text_width(text, pixel). Letter i's mesh is "Letter<i>".
static func neon(text: String, col: Color, pixel: float = 0.08, dead: Array = [], backing: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Neon"
	var count := text.length()
	var pitch := 6.0 * pixel
	var w := text_width(text, pixel)
	if backing:
		var bs := LowPoly.Soup.new(n(), 0.04)
		box(bs, Vector3(w + pixel * 4.0, pixel * 11.0, 0.06), Vector3(0, 0, -0.06), PropModels.OBSIDIAN)
		root.add_child(mesh(bs, 1.4))
	var mats: Array[ShaderMaterial] = []
	var dead_mask: Array[bool] = []
	for i in count:
		var ch := text.substr(i, 1)
		if ch == " " or not GLYPHS.has(ch):
			continue
		var is_dead := dead.has(i)
		var ls := LowPoly.Soup.new(13 + i, 0.02)
		var rows: Array = GLYPHS[ch]
		for r in 7:
			var line: String = rows[r]
			for c in 5:
				if line.substr(c, 1) == "#":
					var p := Vector3((float(c) - 2.0) * pixel, (3.0 - float(r)) * pixel, 0)
					box(ls, Vector3(pixel * 1.02, pixel * 1.02, 0.05), p, glow(Color(0.25, 0.08, 0.05) if is_dead else col))
		var mi := MeshInstance3D.new()
		mi.name = "Letter%d" % i   # (by its index in `text`: the garage finds the dead H of "WE FIX HEXES" by it)
		mi.mesh = ls.to_mesh(0.0)
		var m := MonsterMaterial.make(0.0)
		m.set_shader_parameter("glow_gain", 0.1 if is_dead else 2.2)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3((float(i) - float(count - 1) * 0.5) * pitch, 0, 0)
		root.add_child(mi)
		mats.append(m)
		dead_mask.append(is_dead)
	var fl := NeonFlicker.new()
	fl.mats = mats
	fl.burnt = dead_mask
	root.add_child(fl)
	return root


static func text_width(text: String, pixel: float) -> float:
	return float(text.length()) * 6.0 * pixel - pixel


## Additive "god ray": a long open cone of dusty light, brightest at the top. `length` downward along -Y.
static func light_shaft(length: float, r_top: float, r_bottom: float, col: Color, strength: float = 0.18) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = length
	cm.radial_segments = 18
	cm.cap_top = false
	cm.cap_bottom = false
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color;
uniform float strength = 0.18;
varying float v_y;
void vertex() { v_y = VERTEX.y; }
void fragment() {
	float h = clamp(0.5 + v_y / %f, 0.0, 1.0);
	float rim = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.6);
	float dust = 0.85 + 0.15 * sin(UV.x * 60.0 + TIME * 0.4) * sin(UV.y * 9.0 - TIME * 0.2);
	ALBEDO = tint.rgb * strength * h * h * rim * dust;
}
""" % length
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("strength", strength)
	var mi := MeshInstance3D.new()
	mi.name = "LightShaft"
	mi.mesh = cm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Drifting dust motes / embers in a box.
static func motes(extent: Vector3, col: Color, amount: int = 60, rise: float = 0.15) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Motes"
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extent
	p.direction = Vector3(0.2, 1.0, 0.0)
	p.spread = 60.0
	p.gravity = Vector3(0, 0, 0)
	p.initial_velocity_min = rise * 0.3
	p.initial_velocity_max = rise
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.04, 0.04)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = col
	qm.material = m
	p.mesh = qm
	return p


# --- animators ------------------------------------------------------------------------------------------------------

## Torch / lamp flicker on a light.
class Flicker extends Node:
	var light: Light3D
	var base := 2.0
	var amount := 0.22
	var speed := 8.0
	var phase := 0.0
	var _t := 0.0

	func _process(delta: float) -> void:
		if light == null:
			return
		_t += delta
		var k := sin(_t * speed + phase) * 0.5 + sin(_t * speed * 2.31 + phase * 1.7) * 0.3 + sin(_t * speed * 5.13 + phase * 0.3) * 0.2
		light.light_energy = base * (1.0 + amount * k)


## Neon letters: a steady buzz, now and then one letter stutters.
class NeonFlicker extends Node:
	var mats: Array[ShaderMaterial] = []
	var burnt: Array[bool] = []
	var _t := 0.0
	var _stutter := -1
	var _until := 0.0
	var _rng := RandomNumberGenerator.new()

	func _process(delta: float) -> void:
		_t += delta
		if _t > _until:
			_stutter = _rng.randi_range(0, maxi(mats.size() - 1, 0)) if _rng.randf() < 0.5 else -1
			_until = _t + _rng.randf_range(0.6, 2.4)
		for i in mats.size():
			if burnt[i]:
				continue
			var g := 2.2 + 0.08 * sin(_t * 37.0 + float(i))
			if i == _stutter and fmod(_t * 13.0, 1.0) < 0.45:
				g = 0.25
			mats[i].set_shader_parameter("glow_gain", g)



## A gentle bob (a hanging sign, a cable).
class Swing extends Node:
	var amount_deg := 2.0
	var speed := 0.9
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		var p := get_parent() as Node3D
		if p != null:
			p.rotation.z = deg_to_rad(amount_deg) * sin(_t * speed)
