class_name AimReticle
extends Node3D
## Ground marker showing where the player's spells (and bolt) will land: a small
## ring at the aim point, clamped to spell range. When the aim snaps onto a
## teammate, a bright ring hugs that hero instead, so "point at a friend, then
## say the spell" is readable (and so is pointing corn at them by mistake).

const RING_COLOR := Color(1.0, 1.0, 1.0, 0.55)
const SNAP_COLOR := Color(0.45, 1.0, 0.6, 0.9)
const LIFT := 0.06

var controller: PlayerController
var _ring: MeshInstance3D
var _snap: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	top_level = true
	_ring = _make_ring(0.32, 0.42, RING_COLOR)
	_snap = _make_ring(0.62, 0.78, SNAP_COLOR)
	add_child(_ring)
	add_child(_snap)


func _process(delta: float) -> void:
	_t += delta
	var hero := controller.hero if controller else null
	if hero == null or not is_instance_valid(hero) or hero.dead or not controller.enabled:
		visible = false
		return
	visible = true
	var aim := controller.aim_point()
	var target := SpellBook.resolve_target(hero, aim)
	var buddy := SpellBook.snap_hero(aim)
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
