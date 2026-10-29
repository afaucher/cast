class_name GhostForm
extends Node
## LOOK-DEV ONLY (docs/design/haunt-look.md): a hero in ghost form, the whole-body transform you cast on yourself
## (new-themes.md "Ghost house", Ghosts: "For now"; later perhaps what a downed hero becomes). Cosmetic only: it changes
## how one hero model is drawn and nothing else (no state on the Hero, nothing networked). The gym's Experiments row
## "Ghost form" (GymDev "hero_ghost") puts the player's own model in it; the haunt look lab poses Wick and Rebar in it.
##
## The hero becomes just the ghost shape (the user, 2026-10-29: "lets actually remove the main body and make it just the
## ghost shape"): every part of the hero drawn in the wisp's vapour (HauntPiece's vapour shader, the possessed hosts' ghost
## body) and nothing else, no body, no ink, no shadow. Its colour is warm (WARM), never the enemy ghosts' cold pale blue or
## ecto green, so a player's ghost is never mistaken for one. (It replaced two earlier treatments, glass and spirit, which
## kept the hero's body see-through.)
##
## GhostForm is a node put under the model (apply). Each frame it dresses any new mesh under the model (a rebuilt arm, a
## held item). Meshes it cannot redraw (any other material) are only made see-through (GeometryInstance3D.transparency).
## "off" puts everything back.

const TREATMENTS: Array[String] = ["off", "ghost"]
const WARM := Color(1.0, 0.80, 0.45)   ## the hero's ghost colour: warm, never the enemy ghosts' cold colours
const ALPHA := 0.32                     ## the vapour's alpha: a little firmer than an enemy wisp's, to find yourself
const OTHER := 0.8                      ## how see-through a mesh it cannot redraw becomes (a held item)
const NAME := "GhostForm"

## The gym's pick (GymDev "hero_ghost"): what the player's model wears; "off" none.
static var treatment := "off"
## >= 0 freezes the pulse at this time (the lab's stills); < 0 runs on TIME.
static var clock := -1.0

var model: Node3D
var which := "ghost"
var vapour: ShaderMaterial       ## what every redrawn part wears
var phase := 0.0
var _orig := {}                  ## GeometryInstance3D -> [material_override, transparency, cast_shadow]


## Put model `m` in treatment `t` ("off" or unknown: back to normal). Returns the GhostForm node (null for off).
static func apply(m: Node3D, t: String) -> GhostForm:
	if m == null:
		return null
	var old := of(m)
	if old != null:
		old.restore()
		m.remove_child(old)
		old.free()
	if t == "off" or not TREATMENTS.has(t):
		return null
	var g := GhostForm.new()
	g.name = NAME
	g.model = m
	g.which = t
	g._make()
	m.add_child(g)
	g.scan()
	return g


## The GhostForm on model `m`, or null.
static func of(m: Node3D) -> GhostForm:
	return m.get_node_or_null(NAME) as GhostForm if m != null else null


## Set the gym's pick and dress `m` (the player's model) for it. False for an unknown treatment.
static func pick(m: Node3D, t: String) -> bool:
	if not TREATMENTS.has(t):
		return false
	treatment = t
	apply(m, t)
	return true


func _make() -> void:
	if GameWorld.fx_rng != null:
		phase = GameWorld.fx_rng.randf_range(0.0, TAU)
	vapour = ShaderMaterial.new()
	vapour.shader = HauntPiece.vapour_shader()
	vapour.set_shader_parameter("ghost_color", WARM)
	vapour.set_shader_parameter("alpha", ALPHA)
	vapour.set_shader_parameter("edge_k", 1.7)
	vapour.set_shader_parameter("glow", 1.0)
	vapour.set_shader_parameter("pulse", GhostLook.PULSE)
	vapour.set_shader_parameter("phase", phase)
	vapour.set_shader_parameter("clock", clock)


func _process(_delta: float) -> void:
	scan()


## Dress every mesh under the model not dressed yet.
func scan() -> void:
	if model == null:
		return
	for gi in _geometry(model):
		if _orig.has(gi):
			continue
		_orig[gi] = [gi.material_override, gi.transparency, gi.cast_shadow]
		var sm := gi.material_override as ShaderMaterial
		if sm != null and sm.shader != null and sm.shader.code == LowPolyMaterial.SHADER:
			gi.material_override = vapour
		else:
			gi.transparency = OTHER
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Put every mesh back as it was.
func restore() -> void:
	for gi: GeometryInstance3D in _orig:
		if not is_instance_valid(gi):
			continue
		var o: Array = _orig[gi]
		gi.material_override = o[0]
		gi.transparency = o[1]
		gi.cast_shadow = o[2]
	_orig.clear()


## How many meshes it redrew (the hero's own parts) and how many it only made see-through.
func counts() -> Vector2i:
	var n := Vector2i.ZERO
	for gi: GeometryInstance3D in _orig:
		if is_instance_valid(gi):
			if gi.material_override == vapour:
				n.x += 1
			else:
				n.y += 1
	return n


static func _geometry(n: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for c in n.get_children():
		if c is GeometryInstance3D:
			out.append(c)
		out.append_array(_geometry(c))
	return out
