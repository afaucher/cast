class_name SharkBody
extends Node3D
## How a Shark looks on every screen (docs/design/sharks.md, "Smooth movement": the drawing half). LOCAL presentation:
## built from what this screen SHOWS of the shark (its interpolated head position and facing on a client, the real ones on
## the host), so nothing about the body travels on the wire.
##
##   - the bending body: the head joint J0 is the shark's position; the body joint J1 and the tail's end are the points
##     BODY_LEN and BODY_LEN + TAIL_LEN back along the TRAIL J0 has drawn on this screen (follow the leader), so the body
##     curves through a turn and the dorsal fin (on the body) trails the head. Moving backward (the lunge's slide back)
##     retraces the trail instead of folding the body;
##   - each segment banks into the turn (from the shown turn rate), the head lifts onto the coping when J0 is past the rim
##     (the lunge), the fin dips in the bite's wind-up;
##   - a ripple at the fin, a bow wave ahead of the snout, a two-line foam wake;
##   - the laser's emitter swivel and lens glow (set by the Shark), and belly-up once dead.
## top_level: its children are posed in world space (the Shark actor's own transform is ignored).

const SharkModels := preload("res://scripts/art/lowpoly/props/shark_models.gd")
const PoolProps := preload("res://scripts/art/lowpoly/props/pool_props.gd")

const FLOAT := 0.06            ## the belly rides this far over the pool floor
const TRAIL_STEP := 0.05
const TRAIL_KEEP := 80
const BANK := 0.16
const BANK_MAX := 0.42
const OVER := 0.7              ## SharkSteer.LUNGE_OVER: the head's lift reaches 1 there

var shark: Node3D              ## the SharkModels tree
var floor_y := 0.0
var deck_y := 0.5
var surface_y := 0.36
var outline := PackedVector2Array()
var hole := PackedVector2Array()
var telegraph := 0.0           ## the bite's wind-up 0..1 (the fin dips, the bow wave swells)
var dead_k := 0.0              ## 0 alive .. 1 belly-up

var _trail := PackedVector2Array()
var _last_dir := Vector2.RIGHT
var _omega := 0.0
var _speed := 0.0
var _bank := 0.0
var _fin: Node3D
var _bow: Node3D
var _wake: MeshInstance3D
var _mats: Array[ShaderMaterial] = []


func setup(variant: String, rec: Dictionary) -> void:
	top_level = true
	if is_inside_tree():
		global_transform = Transform3D.IDENTITY   # (switched on in the tree, it would keep the parent's place)
	else:
		transform = Transform3D.IDENTITY
	name = "SharkBody"
	shark = SharkModels.build(variant, false)
	add_child(shark)
	for mi: MeshInstance3D in shark.find_children("*", "MeshInstance3D", true, false):
		if mi.material_override is ShaderMaterial and mi.name != "Lens":
			_mats.append(mi.material_override)
	floor_y = float(rec["floor_level"]) * Hex.LEVEL_HEIGHT
	deck_y = float(rec["deck_level"]) * Hex.LEVEL_HEIGHT
	surface_y = float(rec["surface_y"])
	outline = PackedVector2Array(rec["outline"])
	hole = PackedVector2Array(rec.get("hole", []))
	_fin = PoolProps.build("ripple", {"radius": 0.42})
	add_child(_fin)
	_bow = PoolProps.build("ripple", {"radius": 0.3})
	add_child(_bow)
	_wake = MeshInstance3D.new()
	_wake.mesh = ImmediateMesh.new()
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.vertex_color_use_as_albedo = true
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	wm.render_priority = 2
	_wake.material_override = wm
	_wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wake)


## Lay the body straight out behind `p` along `heading` (the first frame, a teleport).
func reset(p: Vector2, heading: Vector2) -> void:
	_trail = PackedVector2Array()
	var h := heading.normalized() if heading.length() > 0.001 else Vector2.RIGHT
	var n := int((SharkModels.BODY_LEN + SharkModels.TAIL_LEN + 0.6) / TRAIL_STEP)
	for i in n:
		_trail.append(p - h * TRAIL_STEP * float(n - i))
	_trail.append(p)
	_last_dir = h


## Follow the shown head position `p` (X/Z) facing `heading`, and pose everything.
func follow(p: Vector2, heading: Vector2, delta: float) -> void:
	if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(p) > 3.0:
		reset(p, heading)
	var last := _trail[_trail.size() - 1]
	var step := p - last
	var h := heading.normalized() if heading.length() > 0.001 else _last_dir
	if step.dot(h) < -0.001:
		_retrace(p)
	elif step.length() >= TRAIL_STEP:
		_trail.append(p)
		if _trail.size() > TRAIL_KEEP:
			_trail = _trail.slice(_trail.size() - TRAIL_KEEP)
	var dt := maxf(delta, 0.0001)
	_omega = lerpf(_omega, _last_dir.angle_to(h) / dt, clampf(dt * 8.0, 0.0, 1.0))
	_speed = lerpf(_speed, step.length() / dt, clampf(dt * 8.0, 0.0, 1.0))
	_last_dir = h
	_bank = lerpf(_bank, clampf(_omega * _speed * BANK, -BANK_MAX, BANK_MAX), clampf(dt * 5.0, 0.0, 1.0))
	_pose(p, h)


func _retrace(p: Vector2) -> void:
	# moving backward (sliding back down its own path): drop the trail points ahead of p
	while _trail.size() > 2 and _trail[_trail.size() - 2].distance_to(p) < _trail[_trail.size() - 1].distance_to(p) + 0.0001:
		_trail.remove_at(_trail.size() - 1)
	_trail[_trail.size() - 1] = p


## The point `back` units back along the trail from p.
func behind(p: Vector2, back: float) -> Vector2:
	var left := back
	var cur := p
	var i := _trail.size() - 1
	while i >= 0:
		var q := _trail[i]
		var seg := cur.distance_to(q)
		if seg >= left:
			return cur + (q - cur).normalized() * left if seg > 0.0001 else cur
		left -= seg
		cur = q
		i -= 1
	var tail_dir := (_trail[0] - _trail[mini(1, _trail.size() - 1)]).normalized() if _trail.size() > 1 else -_last_dir
	return cur + tail_dir * left


func _pose(p: Vector2, h: Vector2) -> void:
	var j1 := behind(p, SharkModels.BODY_LEN)
	var j2 := behind(p, SharkModels.BODY_LEN + SharkModels.TAIL_LEN)
	var rim := SharkSteer.rim_distance(p, outline, hole)
	var lift := clampf((0.25 - rim) / (0.25 + OVER), 0.0, 1.0)
	var dip := 0.12 * telegraph
	var base := floor_y + FLOAT
	var y0 := base + lift * (deck_y - base + 0.02) - dip
	var y1 := base + lift * 0.18 - dip * 0.6
	var p0 := Vector3(p.x, y0, p.y)
	var p1 := Vector3(j1.x, y1, j1.y)
	var p2 := Vector3(j2.x, base, j2.y)
	var head_fwd := Vector3(h.x, -0.18 * lift - 0.1 * telegraph, h.y).normalized()
	var roll := _bank + PI * dead_k
	var sink := -0.25 * dead_k
	SharkModels.pose(shark, _xf(p0 + Vector3(0, sink, 0), head_fwd, roll * 0.6 if dead_k <= 0.0 else roll),
		_xf(p0 + Vector3(0, sink, 0), (p0 - p1).normalized(), roll), _xf(p1 + Vector3(0, sink, 0), (p1 - p2).normalized(), roll * 0.7 if dead_k <= 0.0 else roll))
	var fp := behind(p, 0.42)
	_fin.position = Vector3(fp.x, surface_y + 0.012, fp.y)
	_fin.scale = Vector3.ONE * (0.8 + 0.5 * clampf(_speed / 3.0, 0.0, 1.0))
	_fin.visible = dead_k <= 0.0
	var nose := Vector3(p.x, 0, p.y) + Vector3(h.x, 0, h.y) * (SharkModels.HEAD_LEN + 0.15)
	_bow.position = Vector3(nose.x, surface_y + 0.014, nose.z)
	_bow.visible = dead_k <= 0.0 and (telegraph > 0.0 or _speed > 1.2)
	_bow.scale = Vector3.ONE * (0.7 + 1.6 * telegraph + 0.2 * clampf(_speed / 3.0, 0.0, 1.0))
	_draw_wake(p)


static func _xf(at: Vector3, fwd: Vector3, roll: float) -> Transform3D:
	var f := fwd.normalized() if fwd.length() > 0.0001 else Vector3.FORWARD
	var b := Basis.looking_at(-f, Vector3.UP)
	b = Basis(f, -roll) * b
	return Transform3D(b, at)


func _draw_wake(p: Vector2) -> void:
	var im := _wake.mesh as ImmediateMesh
	im.clear_surfaces()
	var k_speed := clampf(_speed / 2.4, 0.0, 1.0)
	if k_speed < 0.05 or dead_k > 0.0:
		return
	var y := surface_y + 0.016
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	var prev: Array = []
	for k in n + 1:
		var d := 0.3 + float(k) * 0.24
		var a := behind(p, d)
		var b := behind(p, d + 0.1)
		var t := (a - b).normalized() if a.distance_to(b) > 0.0001 else Vector2.RIGHT
		var nv := Vector2(-t.y, t.x)
		var spread := 0.18 + float(k) * 0.055
		var alpha := 0.75 * k_speed * (1.0 - float(k) / float(n))
		var cur: Array = []
		for side: float in [-1.0, 1.0]:
			var c := a + nv * spread * side
			cur.append([Vector3(c.x, y, c.y), Vector3(c.x + nv.x * 0.07 * side, y, c.y + nv.y * 0.07 * side), alpha])
		if not prev.is_empty():
			for j in 2:
				var q0: Array = prev[j]
				var q1: Array = cur[j]
				var c0 := Color(0.88, 0.98, 1.0, float(q0[2]))
				var c1 := Color(0.88, 0.98, 1.0, float(q1[2]))
				for vv: Array in [[q0[0], c0], [q0[1], c0], [q1[1], c1], [q0[0], c0], [q1[1], c1], [q1[0], c1]]:
					im.surface_set_color(vv[1])
					im.surface_add_vertex(vv[0])
		prev = cur
	im.surface_end()


## The monsters' hit flash / wind-up pulse on every segment (Monster._apply_tint).
func set_tint(color: Color, k: float) -> void:
	for m in _mats:
		m.set_shader_parameter("tint_color", color)
		m.set_shader_parameter("tint_k", k)


## The emitter's swivel (degrees off the snout) and the lens's heat (0..1).
func aim(yaw_deg: float, charge: float) -> void:
	SharkModels.aim(shark, yaw_deg, charge)


## Where the beam starts and which way it points now: [lens position, direction (X/Z unit, as a Vector3)].
func muzzle() -> Array:
	var m: Array = SharkModels.muzzle(shark)
	var d: Vector3 = m[1]
	d.y = 0.0
	return [m[0], d.normalized() if d.length() > 0.0001 else Vector3.FORWARD]


## The saddle's world transform (the rider sits here, facing the snout).
func saddle() -> Transform3D:
	var body := SharkModels.segments(shark)["body"] as Node3D
	return body.global_transform * Transform3D(Basis(Vector3.UP, PI), SharkModels.SADDLE_AT + Vector3(0, -0.16, -0.02))
