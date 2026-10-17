class_name ToyFigure
extends Node3D
## A rigid-part toy character: a root, a "rig" node (bobs / breathes), and named part nodes
## ("body", "head", "arm_l", "arm_r", "weapon", "hat", ...) that an animation pass can pose.
## Characters face local -Z; +X is the character's right.
##
## Built by CharacterKit.build(hero_id, style). Idle motion runs in _process (code only, no
## AnimationPlayer); pose(&"melee") etc. freeze a demo pose; pose(&"idle") resumes idling.

var hero_id := ""
var style: StringName = &"toy"
## Proportion multipliers set by the style (toy = 1.0 each): head/hat, legs, torso, width, limb thickness.
var hd := 1.0
var lg := 1.0
var tr := 1.0
var wd := 1.0
var lm := 1.0

var rig: Node3D
var parts: Dictionary = {}     ## String -> Node3D
var rest: Dictionary = {}      ## String -> Transform3D (the pose at build time)
var idle_enabled := true
var idle_speed := 1.0
var idle_fn: Callable          ## (fig: ToyFigure, t: float) -> void   extra per-hero idle motion
var pose_fn: Callable          ## (fig: ToyFigure, pose_name: StringName) -> void
var current_pose: StringName = &"idle"
var _t := 0.0


func _ready() -> void:
	_t = GameWorld.fx_rng.randf() * 6.0     # de-sync neighbouring figures


## An empty named node (a pivot / group) under `parent`.
func pivot(part_name: String, parent: Node3D, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = part_name
	n.position = pos
	parent.add_child(n)
	parts[part_name] = n
	return n


## A mesh part. col is the matte toon colour; opts go to Toon.material (rim, self_light, ...).
func add(part_name: String, parent: Node3D, mesh: Mesh, col: Color, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, opts: Dictionary = {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = Toon.material(col, style, opts)
	mi.transform = ArtMesh.xf(pos, rot_deg, scl)
	parent.add_child(mi)
	parts[part_name] = mi
	return mi


## Snapshot every part's transform as its rest pose. Call once after building.
func seal() -> void:
	rest.clear()
	for k in parts:
		rest[k] = (parts[k] as Node3D).transform


func get_part(part_name: String) -> Node3D:
	return parts.get(part_name)


func has_part(part_name: String) -> bool:
	return parts.has(part_name)


func reset_pose() -> void:
	for k in parts:
		(parts[k] as Node3D).transform = rest[k]


## Rotate a part relative to its rest rotation (degrees, euler XYZ).
func rot(part_name: String, euler_deg: Vector3) -> void:
	var n: Node3D = parts.get(part_name)
	if n == null:
		return
	var r: Transform3D = rest[part_name]
	n.transform = Transform3D(r.basis * Basis.from_euler(Vector3(deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z))), n.position)


## Offset a part's position from its rest position.
func shift(part_name: String, delta: Vector3) -> void:
	var n: Node3D = parts.get(part_name)
	if n == null:
		return
	n.position = (rest[part_name] as Transform3D).origin + delta


## Set rotation and offset together.
func put(part_name: String, euler_deg: Vector3, delta: Vector3 = Vector3.ZERO) -> void:
	rot(part_name, euler_deg)
	shift(part_name, delta)


func pose(pose_name: StringName) -> void:
	reset_pose()
	current_pose = pose_name
	if pose_name == &"idle":
		idle_enabled = true
		return
	idle_enabled = false
	if pose_fn.is_valid():
		pose_fn.call(self, pose_name)


func node_count() -> int:
	var n := 0
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		n += 1
		stack.append_array(cur.get_children())
	return n


func _process(delta: float) -> void:
	if not idle_enabled:
		return
	_t += delta * idle_speed
	apply_idle(_t)


## Pose the figure at idle time `t` seconds (also used by tests / turntables).
func apply_idle(t: float) -> void:
	reset_pose()
	if rig != null:
		var breathe := sin(t * 2.3)
		var r: Transform3D = rest.get("rig", rig.transform)
		rig.position = r.origin + Vector3(0, 0.03 * breathe, 0)
		rig.scale = Vector3(1.0 - 0.012 * breathe, 1.0 + 0.022 * breathe, 1.0 - 0.012 * breathe)
	if idle_fn.is_valid():
		idle_fn.call(self, t)
