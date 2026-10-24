class_name LowPolyModel
extends Node3D
## Shared base for the faceted low-poly hero models (RebarModel, GasketModel): the named-parts
## dictionary, the LowPolyMaterial, idle / walk speed tracking, the arm-kick tween helper, the
## downed look, and budget helpers for tests.
##
## Subclasses call _setup_model() from their _init(), then build their parts with _add_part() and
## override apply_idle() (called every frame while idle_enabled). They face local -Z; +X is their
## right; the origin is at the feet.
##
## Hero hooks (all optional on the hero side): attack_swing(), cast_pose(), set_downed(), ui_height,
## hold_item() (shows the held spell's material component in the free hand).

## Height of the top of the head, so a hero can park its health bar above.
var ui_height := 2.0

## True when the model carries its own weapon part, so the hero skips its inert weapon stand-in.
var has_own_weapon := false

var parts: Dictionary = {}                 ## name -> MeshInstance3D
var idle_enabled := true
var outline_px := 2.4

## Where hold_item() parents its prop: a Node3D under the free hand (see _hold_host()). Null until used.
var hold_anchor: Node3D = null
var hold_scale := 1.0                      ## scale of a held prop in this model's space
var hold_offset := Vector3.ZERO            ## prop position relative to the host part

var cycle_k := 1.0                         ## the idle / walk clock's rate (a monster's walk unsync)

var _mat: ShaderMaterial
var _t := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _swing_tween: Tween
var _arm_kick := {}                        ## arm part name -> extra x rotation from swings / casts


## Call first thing in a subclass _init(): names the node, applies the model scale and makes the
## shared toon + rim + outline material.
func _setup_model(model_name: String, model_scale: float) -> void:
	name = model_name
	scale = Vector3.ONE * model_scale
	_mat = LowPolyMaterial.make(outline_px)


func _ready() -> void:
	_last_pos = global_position


func has_part(part_name: String) -> bool:
	return parts.has(part_name)


func get_part(part_name: String) -> MeshInstance3D:
	return parts.get(part_name)


## Total triangle count over all parts (for tests / budgets).
func triangle_count() -> int:
	var n := 0
	for p: MeshInstance3D in parts.values():
		var arrays := p.mesh.surface_get_arrays(0)
		n += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


## Add one rigid part (a soup meshed with the shared material) under `parent` and register it.
func _add_part(part_name: String, soup: LowPoly.Soup, parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = soup.to_mesh()
	mi.material_override = _mat
	mi.position = pos
	parent.add_child(mi)
	parts[part_name] = mi
	return mi


# ------------------------------------------------------------------ held item

## Put `node` in the free hand (replacing whatever was there); null empties the hand. The previous
## prop is freed. Models choose the hand with _hold_host() and tune hold_offset / hold_scale.
func hold_item(node: Node3D) -> void:
	if hold_anchor == null:
		hold_anchor = Node3D.new()
		hold_anchor.name = "HoldAnchor"
		_hold_host().add_child(hold_anchor)
		hold_anchor.position = hold_offset
		hold_anchor.scale = Vector3.ONE * hold_scale
	for c in hold_anchor.get_children():
		hold_anchor.remove_child(c)
		c.queue_free()
	if node != null:
		hold_anchor.add_child(node)


## The prop currently in the hand, or null.
func held_item() -> Node3D:
	if hold_anchor == null or hold_anchor.get_child_count() == 0:
		return null
	return hold_anchor.get_child(0) as Node3D


## The node the held prop hangs under: the hand that is not busy (a part that follows that hand).
## Default: the body. Override per model.
func _hold_host() -> Node3D:
	return parts["body"] as Node3D if parts.has("body") else self


# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	if not idle_enabled or not is_inside_tree():
		return
	_t += delta * cycle_k
	var gp := global_position
	var moved := Vector2(gp.x - _last_pos.x, gp.z - _last_pos.z).length()
	_last_pos = gp
	var spd := moved / maxf(delta, 0.0001)
	_speed = lerpf(_speed, minf(spd, 6.0), clampf(delta * 10.0, 0.0, 1.0))
	apply_idle(_t, _speed)


## Move the idle / walk clock `seconds` ahead (a monster's walk unsync: a pack spawned together does not stride in step).
func offset_clock(seconds: float) -> void:
	_t += seconds


## Pose the idle / walk cycle at time t. Subclasses override.
func apply_idle(_time: float, _walk: float = 0.0) -> void:
	pass


## Extra x rotation currently kicked onto an arm part (0 when none).
func arm_kick(key: String) -> float:
	return float(_arm_kick.get(key, 0.0))


## Tween an arm's kick value: wind up, strike, recover. apply_idle() adds arm_kick() to the rest pose.
func _kick_arm(key: String, windup: float, punch: float, t_wind: float, t_hit: float, t_back: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _arm_kick[key] = v, 0.0, windup, t_wind).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(v: float) -> void: _arm_kick[key] = v, windup, punch, t_hit).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: _arm_kick[key] = v, punch, 0.0, t_back).set_trans(Tween.TRANS_BACK)


## Downed: greyed out; the hero lies the whole model down.
func set_downed(downed: bool) -> void:
	_mat.set_shader_parameter("desat", 0.85 if downed else 0.0)
	idle_enabled = not downed
