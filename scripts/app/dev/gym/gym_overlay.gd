class_name GymOverlay
extends MeshInstance3D
## The test gym's hit-area overlay (`--gym`, F3; dev only): every living hero's melee hit area (Hero.melee_area(): the
## movement profile's wedge or lane, the shape the strike lab's --overlay draws, HitAreaShape) and every monster's strike
## (a wedge of attack_reach x attack_arc_deg) drawn flat on the floor where each one faces, every frame. Heroes amber, the
## player brighter, monsters red, its body circle white. Drawing only (one ImmediateMesh): Combat decides the hits.

const LIFT := 0.06
const HERO := Color(1.0, 0.82, 0.3, 0.22)
const PLAYER := Color(1.0, 0.9, 0.35, 0.34)
const MONSTER := Color(1.0, 0.25, 0.2, 0.2)
const EDGE_A := 0.9

var player: Hero = null
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 10
	material_override = mat
	top_level = true
	global_transform = Transform3D.IDENTITY


func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	if not visible:
		return
	var shapes: Array = []   # [actor, area, colour]
	for a in GameWorld.actors():
		if not is_instance_valid(a) or a.dead:
			continue
		if a is Hero:
			shapes.append([a, (a as Hero).melee_area(), PLAYER if a == player else HERO])
		elif a is Monster:
			var m := a as Monster
			shapes.append([a, {"shape": "arc", "reach": m.attack_reach, "arc": m.attack_arc_deg}, MONSTER])
	if shapes.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: Array in shapes:
		var a: Actor = s[0]
		var col: Color = s[2]
		var area: Dictionary = s[1]
		_fan(a, HitAreaShape.outline(area), col)
		var disc := HitAreaShape.end_disc(area)
		if not disc.is_empty():
			_fan(a, HitAreaShape.circle(disc["center"], float(disc["r"]), 24), col)
	_mesh.surface_end()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for s: Array in shapes:
		var a: Actor = s[0]
		var col: Color = s[2]
		_loop(a, HitAreaShape.outline(s[1]), Color(col, EDGE_A))
		_loop(a, HitAreaShape.circle(Vector2.ZERO, a.radius, 16), Color(0.95, 0.95, 1.0, 0.7))
	_mesh.surface_end()


## Actor space (x side, y forward along its facing) -> world, on the floor under it.
func _world(a: Actor, p: Vector2) -> Vector3:
	var fwd := a.facing
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	return a.global_position + side * p.x + fwd * p.y + Vector3.UP * LIFT


func _fan(a: Actor, pts: PackedVector2Array, col: Color) -> void:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= maxf(1.0, float(pts.size()))
	for k in pts.size():
		for v: Vector2 in [c, pts[k], pts[(k + 1) % pts.size()]]:
			_mesh.surface_set_color(col)
			_mesh.surface_add_vertex(_world(a, v))


func _loop(a: Actor, pts: PackedVector2Array, col: Color) -> void:
	for k in pts.size():
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(_world(a, pts[k]))
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(_world(a, pts[(k + 1) % pts.size()]))
