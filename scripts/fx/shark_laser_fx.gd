class_name SharkLaserFx
extends Node3D
## The laser shark's telegraph and beam (docs/design/sharks.md): cosmetic, built on every screen from what it shows.
##   aim()   the red aiming line from the lens (thin and flickering while it tracks; solid and bright once LOCKED), its
##           trace on the deck and a reticle where it would stop
##   fire()  the beam: a hot core in a red sheath for BEAM_LIFE, a flare at the lens, sparks where it stopped and a
##           scorch line on the deck
## top_level: world space (a child of the Shark, so the fog hides it with the shark).

const BEAM_LIFE := 0.3
const RED := Color(1.0, 0.12, 0.08)

var _line: MeshInstance3D
var _trace: MeshInstance3D
var _ret: MeshInstance3D
var _core: MeshInstance3D
var _sheath: MeshInstance3D
var _flare: MeshInstance3D
var _hit: MeshInstance3D
var _scorch: MeshInstance3D
var _fire_left := 0.0
var _locked := false


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_line = _bar(_glow(RED, 0.7, 2.0))
	_trace = _bar(_glow(RED, 0.3, 1.2))
	_ret = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.38
	tm.outer_radius = 0.46
	_ret.mesh = tm
	_ret.material_override = _glow(RED, 0.85, 2.0)
	_ret.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ret)
	_core = _bar(_glow(Color(1.0, 0.85, 0.75), 1.0, 6.0))
	_sheath = _bar(_glow(Color(1.0, 0.12, 0.06), 0.7, 3.5))
	_flare = _ball(0.32, _glow(Color(1.0, 0.3, 0.2), 0.8, 4.0))
	_hit = _ball(0.4, _glow(Color(1.0, 0.55, 0.2), 0.85, 5.0))
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.05, 0.03, 0.02, 0.7)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_scorch = _bar(sm)
	clear()


func _glow(c: Color, alpha: float, energy: float) -> StandardMaterial3D:
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


func _bar(m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _ball(r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Stretch box `mi` from a to b, `w` wide and `h` tall.
static func _span(mi: MeshInstance3D, a: Vector3, b: Vector3, w: float, h: float) -> void:
	var l := a.distance_to(b)
	if l < 0.01:
		mi.visible = false
		return
	(mi.mesh as BoxMesh).size = Vector3(w, h, l)
	mi.global_transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), (a + b) * 0.5)
	mi.visible = true


## The telegraph: the line from the lens to where the beam would stop, its trace on the deck at `deck_y`, the reticle.
func aim(from: Vector3, to: Vector3, deck_y: float, locked: bool) -> void:
	if _fire_left > 0.0:
		return
	_locked = locked
	var flick := 1.0 if locked else 0.7 + 0.3 * sin(GameWorld.time * 40.0)
	_span(_line, from, Vector3(to.x, from.y, to.z), 0.05 if locked else 0.035 * flick, 0.05 if locked else 0.035)
	_span(_trace, Vector3(from.x, deck_y + 0.02, from.z), Vector3(to.x, deck_y + 0.02, to.z), 0.12 if locked else 0.08, 0.01)
	_ret.global_position = Vector3(to.x, deck_y + 0.03, to.z)
	_ret.scale = Vector3(1, 0.15, 1) * (1.0 if locked else 0.8)
	_ret.visible = true
	for n: Node3D in [_core, _sheath, _flare, _hit, _scorch]:
		n.visible = false


## The beam from `from` to where it stopped.
func fire(from: Vector3, to: Vector3, deck_y: float) -> void:
	_fire_left = BEAM_LIFE
	var end := Vector3(to.x, from.y, to.z)
	_span(_core, from, end, 0.08, 0.08)
	_span(_sheath, from, end, 0.26, 0.26)
	_flare.global_position = from
	_hit.global_position = end
	_flare.visible = true
	_hit.visible = true
	var flat := end - from
	flat.y = 0.0
	var s_from := end - flat.normalized() * minf(3.0, flat.length()) if flat.length() > 0.01 else end
	_span(_scorch, Vector3(s_from.x, deck_y + 0.015, s_from.z), Vector3(end.x, deck_y + 0.015, end.z), 0.16, 0.01)
	_line.visible = false
	_trace.visible = false
	_ret.visible = false


func clear() -> void:
	_fire_left = 0.0
	for n: Node3D in [_line, _trace, _ret, _core, _sheath, _flare, _hit, _scorch]:
		n.visible = false


func _process(delta: float) -> void:
	if _fire_left <= 0.0:
		return
	_fire_left -= delta
	var k := clampf(_fire_left / BEAM_LIFE, 0.0, 1.0)
	_sheath.scale = Vector3(k, k, 1.0)
	_core.scale = Vector3(maxf(k, 0.3), maxf(k, 0.3), 1.0)
	if _fire_left <= 0.0:
		for n: Node3D in [_core, _sheath, _flare, _hit]:
			n.visible = false
