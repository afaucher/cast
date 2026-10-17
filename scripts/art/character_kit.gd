class_name CharacterKit
extends RefCounted
## Procedural "chunky toy toon" characters for Cast, assembled from rigid primitive parts.
##
##   var fig: ToyFigure = CharacterKit.build("gasket", &"toy")   # styles: toy | heroic | flat
##
## One file per hero (HeroRebar, HeroGasket, HeroWick, HeroSirRattles, HeroGulp) holds the
## shapes; this file holds the roster, the palette, the style -> proportions table and the
## shared helpers. Style is a parameter, not a separate kit: proportions come from PROPORTIONS
## (heroic = taller / slimmer, ~5.5 heads) and the shading from Toon.STYLES.

const HEROES: Array[String] = ["rebar", "gasket", "wick", "sir_rattles", "gulp"]
const STYLE_IDS: Array[StringName] = [&"toy", &"heroic", &"flat"]

## Per-style proportion multipliers: head/hat, legs, torso, width, limb thickness.
const PROPORTIONS := {
	&"toy":    {"hd": 1.0, "lg": 1.0, "tr": 1.0, "wd": 1.0, "lm": 1.0},
	&"heroic": {"hd": 0.72, "lg": 1.9, "tr": 1.35, "wd": 0.84, "lm": 0.8},
	&"flat":   {"hd": 1.0, "lg": 1.0, "tr": 1.0, "wd": 1.0, "lm": 1.0},
}

# ---- palette. Hero colours are matte and mid-saturation; none of these is emissive.
const MOSS := Color(0.40, 0.62, 0.22)
const SANDSTONE := Color(0.84, 0.72, 0.52)
const SANDSTONE_DK := Color(0.74, 0.61, 0.42)
const DENIM := Color(0.20, 0.38, 0.72)
const DENIM_LT := Color(0.30, 0.52, 0.88)
const PLUM := Color(0.50, 0.25, 0.62)
const PLUM_DK := Color(0.36, 0.18, 0.46)
const MUSTARD := Color(0.86, 0.62, 0.12)
const CORAL := Color(0.96, 0.54, 0.50)
const SKIN := Color(0.96, 0.77, 0.62)
const SKIN_DK := Color(0.90, 0.60, 0.48)
const STEEL := Color(0.56, 0.59, 0.66)
const STEEL_DK := Color(0.40, 0.42, 0.49)
const WOOD := Color(0.55, 0.36, 0.18)
const LEATHER := Color(0.42, 0.26, 0.14)
const GINGER := Color(0.74, 0.40, 0.16)
const STRIP := Color(0.95, 0.96, 0.93)       ## white retroreflective crew strip
const VOID := Color(0.035, 0.03, 0.03)       ## the nothing inside Sir Rattles
const EYE := Color(0.10, 0.07, 0.06)
const HARDHAT := Color(0.98, 0.80, 0.16)
const STRIP_OPTS := {"self_light": 0.30, "rim_amount": 0.15}


## Build a hero figure facing -Z. Unknown ids return an empty ToyFigure.
static func build(hero_id: String, style: StringName = &"toy") -> Node3D:
	var fig := ToyFigure.new()
	fig.name = hero_id.to_pascal_case()
	fig.hero_id = hero_id
	fig.style = style if PROPORTIONS.has(style) else &"toy"
	var p: Dictionary = PROPORTIONS[fig.style]
	fig.hd = float(p["hd"])
	fig.lg = float(p["lg"])
	fig.tr = float(p["tr"])
	fig.wd = float(p["wd"])
	fig.lm = float(p["lm"])
	var rig := Node3D.new()
	rig.name = "rig"
	fig.add_child(rig)
	fig.rig = rig
	fig.parts["rig"] = rig
	match hero_id:
		"rebar": HeroRebar.build(fig)
		"gasket": HeroGasket.build(fig)
		"wick": HeroWick.build(fig)
		"sir_rattles": HeroSirRattles.build(fig)
		"gulp": HeroGulp.build(fig)
		_: push_warning("CharacterKit: unknown hero '%s'" % hero_id)
	fig.seal()
	return fig


## A mesh with its origin moved: used so a limb node sits at the shoulder but the mesh hangs below.
static func shifted(mesh: Mesh, offset: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> ArrayMesh:
	return ArtMesh.merge([mesh], [ArtMesh.xf(offset, rot_deg, scl)])


## Smoothstep-ish 0..1 envelope for demo poses.
static func ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 2.0)
