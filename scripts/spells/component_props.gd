class_name ComponentProps
extends RefCounted
## Small faceted props for the material components, built with LowPoly in the same toon + ink
## outline look as the hero models. Each is one MeshInstance3D under a Node3D, about 0.5 units
## across (readable at the game zoom), origin at its centre, colour-coded to the spell. Each spell's def
## (scripts/spells/defs/, SpellDef) builds its own prop (component_soup()) and says how much it glows (GLOW):
##   heal       Grave moss    green clump with pale spore buds
##   fireball   Ember horn    curved charcoal horn with a glowing orange tip
##   armor      Hide plate    tilted blue plate in a leather rim with rivets
##   corn       Corn kernel   one fat golden kernel on a husk leaf
##   tentacles  Neon ichor    glowing purple flask with a cork
##   teeth      Loose teeth   three white molars, one with a gold filling
##   vines      Seed pod      split green pod with pale seeds, a curled tendril and a thorn
##   damp       Soggy sponge  yellow porous sponge with a dripping blue bead
##   coffee     Coffee beans  three roasted beans with their grooves
##   chicken    Chicken feather  a long white tail feather with a rust-red tip, curling at the end
##   revive     Aloe leaf     a fat, fleshy, curling leaf with pale teeth along its edges and gel at the cut
## Used by ComponentPickup (the world prop) and held in a hero's hand (LowPolyModel.hold_item).

## Colours more than one prop uses (the hide plate's rim, the ichor flask's cork).
const LEATHER := Color(0.45, 0.28, 0.15)
const LEATHER_DARK := Color(0.30, 0.18, 0.10)


## The prop for spell `id` (the component of that spell). An unknown id gets a plain grey gem.
## `glow` adds a soft additive halo in the spell's colour (used for held props, so they read at a distance).
static func make(id: String, glow: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Component_" + id
	var def := SpellBook.def_of(id)
	var soup: LowPoly.Soup = def.component_soup() if def != null else null
	if soup == null:
		soup = LowPoly.boulder(Vector3(0.2, 0.2, 0.2), 0, 0.2, Color(0.6, 0.6, 0.65), 1)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = soup.to_mesh()
	var col := SpellBook.color_of(id)
	mi.material_override = LowPolyMaterial.make_glow(col, float(def.GLOW) if def != null else 0.1, 1.8)
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
