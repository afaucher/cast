class_name Grime
extends RefCounted
## The grime / damage decal layer's public face: a static mark() any effect can call, plus the shared
## tuning. VISUAL ONLY: nothing here touches gameplay, the physics or GameWorld.rng.
##
##   Grime.mark("scorch", pos, radius)      # a fireball landed; kinds below. False when there is no layer.
##   GrimeLayer.attach(parent, map, plan, seed)   # build one layer per floor (game.gd does this)
##
## Two kinds of grime (docs/design/environment.md, "Decisions (2026-10-17)"):
##   - AMBIENT grime persists for the whole floor: the infestation heat around hellgates and the floor-3
##     origin room, ichor drag trails along the corridors leading away from each gate, and the theme's own
##     marks (wine splats, popcorn, chalk, oil, rust, green spills). GrimePlan places it, deterministically
##     per floor seed.
##   - PLAYER-CAUSED marks live LIFE seconds and fade over the last FADE seconds: a fireball's scorch, corn's
##     kernels and scorch ring, a teeth pop's tooth bits, tentacle floor cracks, a monster's ichor stain and
##     a shove slam's scuff. At most MAX_LIVE are alive; the oldest is recycled.
##
## Mark kinds for Grime.mark(): SCORCH, CORN, TEETH, CRACKS, STAIN, SCUFF, PAPER, WET. Unknown kinds are ignored.
## With no GrimeLayer in the tree (most tests) every call is a harmless no-op.

const SCORCH := "scorch"      ## fireball impact; size = blast radius
const CORN := "corn"          ## kernels + a scorch ring; size = strike radius
const TEETH := "teeth"        ## a few tooth bits; size = 1 for a pop
const CRACKS := "tentacles"   ## floor cracks; size = burst radius
const STAIN := "stain"        ## a monster's death splat; size = the monster's radius
const SCUFF := "scuff"        ## a shove slam / hard landing; size = 1
const WET := "wet"            ## a damp puddle that dries away; size = the cell radius it fills
const PAPER := "paper"        ## torn packing paper and cardboard from a broken mail package; size = 1

const MAX_LIVE := 120         ## live player marks (each may draw a few decals)
const LIFE := 30.0            ## seconds a player mark lasts
const FADE := 9.0             ## ... it fades out over the last FADE of them
const LIFT := 0.012           ## decals float this far above the hex top (world units)

## Per atlas kind: base alpha (keeps contrast low) and emissive strength (0 = none).
const STYLE := {
	"scorch": [0.72, 0.30], "scratch": [0.60, 0.0], "ichor": [0.85, 0.40], "crack": [0.70, 0.0],
	"rubble": [0.85, 0.0], "paper": [0.80, 0.0], "glass": [0.85, 0.65], "wax": [0.80, 0.0],
	"wine": [0.80, 0.0], "popcorn": [0.90, 0.0], "chalk": [0.65, 0.0], "oil": [0.80, 0.0],
	"rust": [0.75, 0.0], "spill": [0.85, 0.55], "kernel": [1.0, 0.0], "tooth": [1.0, 0.0],
	"ring": [0.80, 0.50], "drag": [0.85, 0.55], "scuff": [0.60, 0.0], "crack_ichor": [0.90, 0.85],
	"stain": [0.90, 0.50], "puddle": [0.85, 0.30],
}

static var _layer: GrimeLayer = null


## Called by GrimeLayer itself (enter/exit tree).
static func register(layer: GrimeLayer) -> void:
	_layer = layer


static func unregister(layer: GrimeLayer) -> void:
	if _layer == layer:
		_layer = null


## The live layer, or null.
static func layer() -> GrimeLayer:
	return _layer if _layer != null and is_instance_valid(_layer) and _layer.is_inside_tree() else null


## Leave a player-caused mark at `pos` (world position, ground height or not; the layer snaps to the
## ground). Returns true when a layer took it.
static func mark(kind: String, pos: Vector3, size: float = 1.0) -> bool:
	var l := layer()
	if l == null:
		return false
	return l.add_mark(kind, pos, size)


static func style_alpha(kind: String) -> float:
	return float((STYLE.get(kind, [1.0, 0.0]) as Array)[0])


static func style_glow(kind: String) -> float:
	return float((STYLE.get(kind, [1.0, 0.0]) as Array)[1])
