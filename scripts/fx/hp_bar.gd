class_name HpBar
extends Node3D
## A small billboard health bar floating above an actor. Two camera-facing quads
## (background + fill). The fill is resized (not scaled) so billboarding keeps it crisp.

const BAR_W := 0.9
const BAR_H := 0.1

var _fill: MeshInstance3D
var _fill_mesh: QuadMesh
var _fill_mat: StandardMaterial3D
var _frac := -1.0
var width := BAR_W


func _ready() -> void:
	var back_mesh := QuadMesh.new()
	back_mesh.size = Vector2(width + 0.06, BAR_H + 0.06)
	var back := MeshInstance3D.new()
	back.mesh = back_mesh
	back.material_override = _bar_material(Color(0, 0, 0, 0.7), 0)
	back.set_meta("no_flash", true)
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(back)
	_fill_mesh = QuadMesh.new()
	_fill_mesh.size = Vector2(width, BAR_H)
	_fill_mat = _bar_material(Color(0.3, 0.85, 0.35), 1)
	_fill = MeshInstance3D.new()
	_fill.mesh = _fill_mesh
	_fill.material_override = _fill_mat
	_fill.set_meta("no_flash", true)
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill)
	set_fraction(1.0)


static func _bar_material(color: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.albedo_color = color
	m.render_priority = priority
	return m


## Fill amount 0..1. `tint` overrides the automatic green/yellow/red.
func set_fraction(f: float, tint: Color = Color(0, 0, 0, 0)) -> void:
	f = clampf(f, 0.0, 1.0)
	if is_equal_approx(f, _frac) or _fill_mesh == null:
		return
	_frac = f
	var w := maxf(0.001, width * f)
	_fill_mesh.size = Vector2(w, BAR_H)
	_fill_mesh.center_offset = Vector3(-(width - w) * 0.5, 0, 0)
	if tint.a > 0.0:
		_fill_mat.albedo_color = tint
	elif f > 0.5:
		_fill_mat.albedo_color = Color(0.3, 0.85, 0.35)
	elif f > 0.25:
		_fill_mat.albedo_color = Color(0.95, 0.8, 0.2)
	else:
		_fill_mat.albedo_color = Color(0.95, 0.25, 0.2)
