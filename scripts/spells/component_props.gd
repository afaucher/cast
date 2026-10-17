class_name ComponentProps
extends RefCounted
## Small faceted props for the material components, built with LowPoly in the same toon + ink
## outline look as the hero models. Each is one MeshInstance3D under a Node3D, about 0.5 units
## across (readable at the game zoom), origin at its centre, colour-coded to the spell:
##   heal       Grave moss    green clump with pale spore buds
##   fireball   Ember horn    curved charcoal horn with a glowing orange tip
##   armor      Hide plate    tilted blue plate in a leather rim with rivets
##   corn       Corn kernel   one fat golden kernel on a husk leaf
##   tentacles  Neon ichor    glowing purple flask with a cork
##   teeth      Loose teeth   three white molars, one with a gold filling
## Used by ComponentPickup (the world prop) and held in a hero's hand (LowPolyModel.hold_item).

const BONE := Color(0.95, 0.92, 0.80)
const BONE_DARK := Color(0.78, 0.72, 0.58)
const BONE_LIGHT := Color(1.0, 0.98, 0.90)
const GOLD := Color(0.95, 0.76, 0.22)
const LEATHER := Color(0.45, 0.28, 0.15)
const LEATHER_DARK := Color(0.30, 0.18, 0.10)
const HORN := Color(0.17, 0.12, 0.12)
const HORN_LIGHT := Color(0.30, 0.22, 0.20)
const EMBER := Color(1.0, 0.55, 0.12)
const EMBER_HOT := Color(1.0, 0.85, 0.35)
const MOSS := Color(0.28, 0.72, 0.32)
const MOSS_LIGHT := Color(0.50, 0.92, 0.48)
const MOSS_DARK := Color(0.16, 0.45, 0.24)
const SPORE := Color(0.98, 0.95, 0.60)
const PLATE := Color(0.32, 0.55, 0.92)
const PLATE_LIGHT := Color(0.60, 0.80, 1.0)
const PLATE_DARK := Color(0.20, 0.35, 0.65)
const KERNEL := Color(1.0, 0.85, 0.15)
const KERNEL_LIGHT := Color(1.0, 0.96, 0.62)
const KERNEL_DARK := Color(0.85, 0.62, 0.08)
const HUSK := Color(0.45, 0.72, 0.30)
const ICHOR := Color(0.78, 0.22, 1.0)
const ICHOR_LIGHT := Color(0.95, 0.62, 1.0)
const ICHOR_DARK := Color(0.46, 0.10, 0.70)
const GLASS := Color(0.62, 0.40, 0.90)

## How strongly each prop's own colour glows (the neon variant of the shared material).
const GLOW := {"heal": 0.12, "fireball": 0.22, "armor": 0.05, "corn": 0.10, "tentacles": 0.45, "teeth": 0.04}


## The prop for spell `id` (the component of that spell). An unknown id gets a plain grey gem.
## `glow` adds a soft additive halo in the spell's colour (used for held props, so they read at a distance).
static func make(id: String, glow: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Component_" + id
	var soup: LowPoly.Soup
	match id:
		"heal": soup = _moss()
		"fireball": soup = _horn()
		"armor": soup = _plate()
		"corn": soup = _kernel()
		"tentacles": soup = _flask()
		"teeth": soup = _teeth()
		_: soup = LowPoly.boulder(Vector3(0.2, 0.2, 0.2), 0, 0.2, Color(0.6, 0.6, 0.65), 1)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = soup.to_mesh()
	var col := SpellBook.color_of(id)
	mi.material_override = LowPolyMaterial.make_glow(col, float(GLOW.get(id, 0.1)), 1.8)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if glow:
		var halo := MeshInstance3D.new()
		halo.name = "Halo"
		var sm := SphereMesh.new()
		sm.radius = 0.30
		sm.height = 0.60
		sm.radial_segments = 10
		sm.rings = 5
		halo.mesh = sm
		halo.material_override = Fx.glow_material(Color(col.r, col.g, col.b, 0.10))
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		halo.set_meta("no_flash", true)
		root.add_child(halo)
	return root


static func _moss() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(701, 0.08)
	s.merge(LowPoly.boulder(Vector3(0.22, 0.13, 0.20), 0, 0.2, MOSS_DARK, 702, 0.08), LowPoly.at(Vector3(0.0, -0.12, 0.0)))
	s.merge(LowPoly.boulder(Vector3(0.17, 0.15, 0.16), 0, 0.2, MOSS, 703, 0.08), LowPoly.at(Vector3(-0.09, -0.03, 0.05)))
	s.merge(LowPoly.boulder(Vector3(0.15, 0.16, 0.15), 0, 0.2, MOSS_LIGHT, 704, 0.08), LowPoly.at(Vector3(0.10, 0.00, -0.04)))
	s.merge(LowPoly.boulder(Vector3(0.13, 0.12, 0.13), 0, 0.2, MOSS, 705, 0.08), LowPoly.at(Vector3(0.01, 0.06, 0.08)))
	s.merge(LowPoly.boulder(Vector3(0.11, 0.10, 0.11), 0, 0.2, MOSS_LIGHT, 706, 0.08), LowPoly.at(Vector3(-0.04, 0.11, -0.05)))
	for p: Vector3 in [Vector3(-0.07, 0.19, -0.03), Vector3(0.09, 0.15, 0.0), Vector3(0.02, 0.20, 0.08)]:
		s.merge(LowPoly.boulder(Vector3(0.035, 0.035, 0.035), 0, 0.15, SPORE, 707 + int(p.x * 100.0)), LowPoly.at(p))
	return s


## A curved horn standing up: five tapering segments bending sideways, glowing ember bands between
## them, an orange-hot cut base and a bright ember tip.
static func _horn() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(711, 0.07)
	var pos := Vector3(-0.08, -0.24, 0.0)
	var bend := 0.0
	var radii: Array[float] = [0.105, 0.088, 0.070, 0.052, 0.036, 0.020]
	for i in 5:
		var h := 0.11
		var mid := pos + Vector3(sin(bend) * h * 0.5, cos(bend) * h * 0.5, 0.0)
		var seg := LowPoly.cylinder(radii[i], radii[i + 1], h * 1.0, 6, HORN if i % 2 == 0 else HORN_LIGHT, 712 + i, 0.012, 1, 0.07)
		s.merge(seg, LowPoly.at(mid, Vector3(0.0, 0.0, -rad_to_deg(bend))))
		if i > 0:
			var band := LowPoly.cylinder(radii[i] * 1.12, radii[i] * 1.12, 0.03, 6, EMBER, 722 + i, 0.006, 1, 0.05)
			s.merge(band, LowPoly.at(pos, Vector3(0.0, 0.0, -rad_to_deg(bend))))
		pos += Vector3(sin(bend) * h, cos(bend) * h, 0.0)
		bend += 0.26
	s.merge(LowPoly.cylinder(0.11, 0.11, 0.04, 6, EMBER, 720, 0.008), LowPoly.at(Vector3(-0.08, -0.255, 0.0)))   # glowing cut base
	s.merge(LowPoly.boulder(Vector3(0.065, 0.075, 0.065), 0, 0.15, EMBER_HOT, 721, 0.04), LowPoly.at(pos + Vector3(0.015, 0.025, 0.0)))   # ember tip
	return s


## A hex plate lying nearly flat so the top shows from the game camera: leather rim, a blue plate, a
## raised boss and rivets.
static func _plate() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(731, 0.07)
	var tilt := Vector3(-22.0, 0.0, 0.0)
	var b := Basis.from_euler(Vector3(deg_to_rad(tilt.x), 0.0, 0.0))
	s.merge(LowPoly.cylinder(0.30, 0.30, 0.09, 6, LEATHER, 732, 0.012, 1, 0.08), LowPoly.at(Vector3.ZERO, tilt))
	s.merge(LowPoly.cylinder(0.25, 0.23, 0.08, 6, PLATE, 733, 0.014, 1, 0.07), LowPoly.at(b * Vector3(0, 0.05, 0), tilt))
	s.merge(LowPoly.boulder(Vector3(0.12, 0.07, 0.12), 0, 0.12, PLATE_LIGHT, 734, 0.05), LowPoly.at(b * Vector3(0, 0.12, 0), tilt))
	for i in 6:
		var a := TAU * i / 6.0 + TAU / 12.0
		s.merge(LowPoly.boulder(Vector3(0.035, 0.035, 0.035), 0, 0.1, PLATE_LIGHT, 735 + i, 0.04), LowPoly.at(b * Vector3(cos(a) * 0.255, 0.1, sin(a) * 0.255)))
	return s


static func _kernel() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(741, 0.07)
	s.merge(LowPoly.boulder(Vector3(0.17, 0.23, 0.15), 0, 0.12, KERNEL, 742, 0.06), LowPoly.at(Vector3(0.0, 0.02, 0.0), Vector3(0, 0, 8)))
	s.merge(LowPoly.boulder(Vector3(0.10, 0.07, 0.09), 0, 0.15, KERNEL_LIGHT, 743, 0.05), LowPoly.at(Vector3(0.0, 0.17, 0.0)))   # pale cap
	s.merge(LowPoly.boulder(Vector3(0.12, 0.08, 0.11), 0, 0.15, KERNEL_DARK, 744, 0.05), LowPoly.at(Vector3(0.01, -0.17, 0.0)))   # pinched base
	# two husk leaves hugging the base
	s.merge(LowPoly.box(Vector3(0.05, 0.22, 0.13), HUSK, 745, 0.01, 1, 0.08), LowPoly.at(Vector3(-0.14, -0.10, 0.0), Vector3(0, 0, 20)))
	s.merge(LowPoly.box(Vector3(0.05, 0.20, 0.12), HUSK.darkened(0.15), 746, 0.01, 1, 0.08), LowPoly.at(Vector3(0.15, -0.11, 0.0), Vector3(0, 0, -20)))
	return s


static func _flask() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(751, 0.06)
	s.merge(LowPoly.boulder(Vector3(0.20, 0.19, 0.20), 1, 0.07, ICHOR, 752, 0.06), LowPoly.at(Vector3(0.0, -0.07, 0.0)))
	s.merge(LowPoly.boulder(Vector3(0.12, 0.05, 0.12), 0, 0.12, ICHOR_LIGHT, 753, 0.05), LowPoly.at(Vector3(-0.02, 0.04, -0.08)))   # glassy highlight
	s.merge(LowPoly.cylinder(0.065, 0.075, 0.13, 6, GLASS, 754, 0.008), LowPoly.at(Vector3(0.0, 0.18, 0.0)))   # neck
	s.merge(LowPoly.cylinder(0.085, 0.085, 0.03, 6, ICHOR_DARK, 755, 0.006), LowPoly.at(Vector3(0.0, 0.12, 0.0)))   # collar
	s.merge(LowPoly.cylinder(0.062, 0.075, 0.08, 6, LEATHER, 756, 0.008), LowPoly.at(Vector3(0.0, 0.27, 0.0)))   # cork
	for p: Vector3 in [Vector3(0.20, 0.10, 0.04), Vector3(-0.19, 0.18, -0.03), Vector3(0.14, 0.26, 0.10)]:
		s.merge(LowPoly.boulder(Vector3(0.030, 0.038, 0.030), 0, 0.12, ICHOR_LIGHT, 757 + int(p.x * 100.0), 0.04), LowPoly.at(p))   # floating drops
	return s


static func _tooth(seed_value: int, size: float) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(seed_value, 0.05)
	s.merge(LowPoly.frustum(Vector2(0.15, 0.13) * size, Vector2(0.19, 0.16) * size, 0.14 * size, BONE, seed_value + 1, 0.02, 1, Vector2.ZERO, 0.04), LowPoly.at(Vector3(0.0, 0.07 * size, 0.0)))   # crown
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			s.merge(LowPoly.boulder(Vector3(0.055, 0.045, 0.05) * size, 0, 0.12, BONE_LIGHT, seed_value + 4, 0.03), LowPoly.at(Vector3(0.055 * cx, 0.15, 0.045 * cz) * size))   # cusps
	for sx: float in [-1.0, 1.0]:
		s.merge(LowPoly.cylinder(0.05 * size, 0.012 * size, 0.2 * size, 5, BONE_DARK, seed_value + 3, 0.01), LowPoly.at(Vector3(0.05 * size * sx, -0.07 * size, 0.0), Vector3(0, 0, 10.0 * sx)))   # roots
	return s


static func _teeth() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(771, 0.05)
	s.merge(_tooth(772, 1.2), LowPoly.at(Vector3(-0.12, 0.0, 0.04), Vector3(0, 20, 12)))
	s.merge(_tooth(776, 1.05), LowPoly.at(Vector3(0.12, -0.03, -0.05), Vector3(0, -15, -18)))
	s.merge(_tooth(780, 0.9), LowPoly.at(Vector3(0.0, 0.02, 0.15), Vector3(-30, 0, 4)))
	s.merge(LowPoly.box(Vector3(0.07, 0.045, 0.035), GOLD, 784, 0.0, 1, 0.03), LowPoly.at(Vector3(-0.12, 0.17, -0.06)))   # gold filling
	return s
