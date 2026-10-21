class_name GooSoups
extends RefCounted
## The goo imp's goo, as meshes (docs/design/goo-imp.md, "As built"): the ball in flight, the landing marker, a patch on the
## floor (fresh or burnt), the goo on a hero's boots and the flames of a lit patch. Cosmetic only: GooBall and GooPatch build
## their looks from these on every screen. Built from the look-dev lab's mocks (goo_imp_lab.gd: _ball, _throw, _patch, _stuck,
## _fire), so the game shows what the user picked. The shapes' jitter comes from a seed (never GameWorld.rng).

const BILE := Color(0.80, 1.0, 0.16)          ## the user's goo colour (the enemy chartreuse)
const BALL_R := 0.26                          ## the ball in flight: big, so it reads in the air
const FIRE_OUTER := Color(1.0, 0.42, 0.06)    ## Burning's flame colours
const FIRE_INNER := Color(1.0, 0.86, 0.25)
const FIRE_OUTLINE := Color(0.32, 0.04, 0.0)

static var _flame_meshes: Array[ArrayMesh] = []
static var _flame_mats: Array[Material] = []


static func hot(c: Color) -> Color:
	return c.lerp(Color(1, 1, 1), 0.45)


static func deep(c: Color) -> Color:
	return Color(c.r * 0.55, c.g * 0.55, c.b * 0.55)


## A soup as a node with the monsters' material (outline px, glow gain): the goo glows like a monster's face.
static func node_of(s: LowPoly.Soup, outline: float, gain: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = s.to_mesh()
	var mat := MonsterMaterial.make(outline)
	mat.set_shader_parameter("glow_gain", gain)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_flash", true)
	return mi


## The ball in flight: a glowing lumpy sphere with a hot highlight and a drip tail along +Z (the node faces its velocity
## with its tail behind: look_at points -Z forward).
static func ball(col: Color = BILE) -> MeshInstance3D:
	var r := BALL_R
	var s := LowPoly.Soup.new(71, 0.05)
	MonsterModel.blob(s, Vector3.ZERO, Vector3.ONE * r, MonsterModel.glow(col), 72, 0.18, 1)
	MonsterModel.blob(s, Vector3(-r * 0.3, r * 0.45, -r * 0.2), Vector3.ONE * r * 0.35, MonsterModel.glow(hot(col)), 73, 0.1)
	MonsterModel.limb(s, Vector3(0, 0, r * 0.6), Vector3(0, 0, r * 2.4), r * 0.45, r * 0.05, 5, MonsterModel.glow(col), 74)
	return node_of(s, 2.0, 1.8)


## An unlit, see-through material (the marker's shadow) or an additive glowing one (its ring, the droplets).
static func shade_mat(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = 2
	return m


static func glow_mat(c: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.render_priority = 3
	return m


## The landing marker: a dark shadow disc (its node is scaled as the ball comes down) and a bile ring, both just above the
## floor. Returns [root, shadow, ring].
static func marker(radius: float, col: Color = BILE) -> Array:
	var root := Node3D.new()
	root.name = "GooMarker"
	var sh := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.01
	cm.radial_segments = 32
	cm.rings = 1
	sh.mesh = cm
	sh.material_override = shade_mat(Color(0.0, 0.0, 0.0), 0.55)
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.position = Vector3(0, 0.02, 0)
	root.add_child(sh)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.07
	tm.outer_radius = radius
	tm.rings = 40
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = glow_mat(col, 0.9, 1.6)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0, 0.04, 0)
	ring.scale = Vector3(1.0, 0.1, 1.0)
	root.add_child(ring)
	return [root, sh, ring]


## A goo patch of radius r: a lumpy sheet with lobes round the edge, splats beyond it, glowing wet spots and bubbles.
## `burnt`: charred black with glowing embers (a lit patch's bed).
static func patch(r: float, seed_value: int, burnt: bool = false, col: Color = BILE) -> MeshInstance3D:
	var s := LowPoly.Soup.new(seed_value, 0.04)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var body := col.darkened(0.15) if not burnt else Color(0.10, 0.08, 0.06)
	var rim := deep(col) if not burnt else Color(0.05, 0.04, 0.03)
	MonsterModel.blob(s, Vector3(0, 0.0, 0), Vector3(r * 1.02, 0.035, r * 0.9), rim, seed_value + 1, 0.10, 1)
	MonsterModel.blob(s, Vector3(0, 0.025, 0), Vector3(r * 0.86, 0.035, r * 0.76), body, seed_value + 2, 0.10, 1)
	for i in 7:
		var a := TAU * float(i) / 7.0 + rng.randf_range(-0.3, 0.3)
		var d := r * rng.randf_range(0.75, 0.95)
		MonsterModel.blob(s, Vector3(cos(a) * d, 0.01, sin(a) * d), Vector3(r * 0.30, 0.03, r * 0.24), rim if i % 2 == 0 else body, seed_value + 10 + i, 0.15, 0, Vector3(0, rad_to_deg(-a), 0))
	for i in 6:
		var a := rng.randf_range(0.0, TAU)
		var d := r * rng.randf_range(1.15, 1.45)
		MonsterModel.blob(s, Vector3(cos(a) * d, 0.01, sin(a) * d), Vector3.ONE * r * rng.randf_range(0.07, 0.12) * Vector3(1, 0.4, 1), body, seed_value + 20 + i, 0.15)
	var shine := MonsterModel.glow(col) if not burnt else MonsterModel.glow(FIRE_OUTER)
	for i in 5:
		var a := rng.randf_range(0.0, TAU)
		var d := r * rng.randf_range(0.0, 0.6)
		MonsterModel.blob(s, Vector3(cos(a) * d, 0.05, sin(a) * d), Vector3(r * 0.16, 0.02, r * 0.12), shine, seed_value + 30 + i, 0.15)
	for i in 4:
		var a := rng.randf_range(0.0, TAU)
		var d := r * rng.randf_range(0.1, 0.7)
		var hb := MonsterModel.glow(hot(col)) if not burnt else Color(0.25, 0.2, 0.15)
		MonsterModel.blob(s, Vector3(cos(a) * d, 0.06, sin(a) * d), Vector3.ONE * r * 0.07, hb, seed_value + 40 + i, 0.1)
	return node_of(s, 1.6, 1.3)


## Goo over a hero's feet and shins with strands to the floor (a hero hit by a ball, or wading through a patch).
static func boots(col: Color = BILE) -> MeshInstance3D:
	var s := LowPoly.Soup.new(81, 0.05)
	for x: float in [-0.17, 0.17]:
		MonsterModel.blob(s, Vector3(x, 0.10, 0.0), Vector3(0.17, 0.13, 0.20), col.darkened(0.15), 82 + int(x * 10.0), 0.18)
		MonsterModel.blob(s, Vector3(x, 0.22, -0.02), Vector3(0.12, 0.10, 0.12), MonsterModel.glow(col), 84 + int(x * 10.0), 0.18)
		for k in 3:
			var a := float(k) * 2.1 + x * 4.0
			var top := Vector3(x + cos(a) * 0.10, 0.36, sin(a) * 0.10)
			var bot := Vector3(x + cos(a) * 0.32, 0.0, sin(a) * 0.30)
			MonsterModel.limb(s, top, bot, 0.035, 0.015, 4, MonsterModel.glow(col), 86 + k + int(x * 20.0))
	return node_of(s, 1.6, 1.2)


## The two shared flame meshes and materials (Burning's recipe: an outer orange cone and an inner yellow one).
static func flame_mesh(big: bool) -> ArrayMesh:
	_ensure_flames()
	return _flame_meshes[0] if big else _flame_meshes[1]


static func flame_mat(big: bool) -> Material:
	_ensure_flames()
	return _flame_mats[0] if big else _flame_mats[1]


static func _ensure_flames() -> void:
	if not _flame_meshes.is_empty():
		return
	_flame_meshes.append(LowPoly.cylinder(0.24, 0.0, 1.0, 5, FIRE_OUTER, 3, 0.04, 2).to_mesh(0.0))
	_flame_meshes.append(LowPoly.cylinder(0.15, 0.0, 0.7, 4, FIRE_INNER, 5, 0.03, 2).to_mesh(0.0))
	_flame_mats.append(LowPolyMaterial.make_glow(FIRE_OUTER, 0.9, 1.2, FIRE_OUTLINE))
	_flame_mats.append(LowPolyMaterial.make_glow(FIRE_INNER, 1.2, 0.0))
