class_name AimReticle
extends Node3D
## Ground marker showing where the player's spells (and bolt) will land: a small
## ring at the aim point, clamped to spell range. When the aim snaps onto a
## teammate, a bright ring hugs that hero instead, so "point at a friend, then
## say the spell" is readable (and so is pointing corn at them by mistake). While Tentacles is the held spell, its
## full-power oval shows round the landing point, turned across the line of aim the way the cast will lay it.

const RING_COLOR := Color(1.0, 1.0, 1.0, 0.55)
const SNAP_COLOR := Color(0.45, 1.0, 0.6, 0.9)
const LIFT := 0.06
## While Tentacles is the held spell: its full-power oval round the landing point, lying across the line of aim as the
## cast will (Tentacles: the depth along the aim, the width across it).
const OVAL_ALPHA := 0.5
const OVAL_THICK := 0.09

var controller: PlayerController
var _ring: MeshInstance3D
var _snap: MeshInstance3D
var _oval: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	top_level = true
	_ring = _make_ring(0.32, 0.42, RING_COLOR)
	_snap = _make_ring(0.62, 0.78, SNAP_COLOR)
	_oval = _make_oval()
	add_child(_ring)
	add_child(_snap)
	add_child(_oval)


func _process(delta: float) -> void:
	_t += delta
	var hero := controller.hero if controller else null
	if hero == null or not is_instance_valid(hero) or hero.dead or not controller.enabled:
		visible = false
		return
	visible = true
	var aim := controller.aim_point()
	var downed := SpellBook.snaps_downed(hero.slot_spell(hero.held_slot))   # (holding Revive or coffee: a body is a friend too)
	var target := SpellBook.resolve_target(hero, aim, downed)
	var buddy := SpellBook.snap_hero(aim, downed)
	if buddy != null and buddy != hero:
		_snap.visible = true
		_ring.visible = false
		_snap.global_position = buddy.global_position + Vector3.UP * LIFT
		var s := 1.0 + 0.08 * sin(_t * 8.0)
		_snap.scale = Vector3(s, 1.0, s)
	else:
		_snap.visible = false
		_ring.visible = true
		_ring.global_position = target + Vector3.UP * LIFT
	_oval.visible = hero.held_spell() == TentaclesSpell.ID
	if _oval.visible:
		var d := TentaclesSpell.aim_dir(hero, target)
		_oval.global_position = target + Vector3.UP * LIFT
		_oval.rotation = Vector3(0.0, atan2(d.x, d.z), 0.0)   # (local +Z along the aim: TentaclesFx's frame)


## Tentacles' full-power oval as a thin rim (TentaclesFx.oval_rim), local X across the aim and Z along it.
static func _make_oval() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "TentaclesOval"
	mi.mesh = TentaclesFx.oval_rim(TentaclesSpell.tentacles_width(1.0), TentaclesSpell.tentacles_depth(1.0), OVAL_THICK, 72)
	var col := SpellBook.color_of(TentaclesSpell.ID)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(col.r, col.g, col.b, OVAL_ALPHA)
	mat.no_depth_test = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	return mi


static func _make_ring(inner: float, outer: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 32
	torus.ring_segments = 6
	mi.mesh = torus
	mi.scale = Vector3(1.0, 0.15, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.no_depth_test = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
