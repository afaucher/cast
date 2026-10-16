class_name Actor
extends Node3D
## Base for everything that has hit points and walks the hex terrain:
## heroes, allies and monsters. Movement is kinematic on GameWorld.map
## (no physics bodies): step up 1 level, climb 2 (slowly), blocked above.
##
## Subclasses drive it by calling move(dir, delta) from _physics_process and
## build their own visuals as children.

signal damaged(amount: float, source: Node)
signal healed(amount: float)
signal died

@export var team: int = 0
@export var max_hp: float = 100.0
@export var move_speed: float = 4.0
@export var radius: float = 0.4
@export var display_name: String = "Actor"

const CLIMB_SPEED_FACTOR := 0.35

var hp: float
var dead := false
var facing := Vector3.FORWARD     ## unit X/Z vector the actor faces
var climbing := false             ## true while crossing a climb ledge
var _modifiers := {}              ## id -> {"mult": float, "until": float}


func _ready() -> void:
	hp = max_hp
	add_to_group("actors")
	snap_to_ground()


# --- Health -------------------------------------------------------------------

## Multiplier on incoming damage from active modifiers (e.g. Armor zone 0.5).
func damage_taken_mult() -> float:
	var now := _now()
	var m := 1.0
	for id in _modifiers.keys():
		var e: Dictionary = _modifiers[id]
		if e["until"] < now:
			_modifiers.erase(id)
		else:
			m *= e["mult"]
	return m


## Add or refresh a damage-taken modifier. Same id refreshes, never stacks.
func set_modifier(id: String, mult: float, duration: float) -> void:
	_modifiers[id] = {"mult": mult, "until": _now() + duration}


func has_modifier(id: String) -> bool:
	return _modifiers.has(id) and _modifiers[id]["until"] >= _now()


## Returns the damage actually dealt.
func apply_damage(amount: float, source: Node = null) -> float:
	if dead or amount <= 0.0:
		return 0.0
	var dealt := amount * damage_taken_mult()
	hp = maxf(0.0, hp - dealt)
	damaged.emit(dealt, source)
	if hp <= 0.0:
		die()
	return dealt


## Returns the HP actually restored.
func heal(amount: float) -> float:
	if dead or amount <= 0.0:
		return 0.0
	var before := hp
	hp = minf(max_hp, hp + amount)
	if hp > before:
		healed.emit(hp - before)
	return hp - before


func die() -> void:
	if dead:
		return
	dead = true
	died.emit()
	GameWorld.actor_died.emit(self)
	_on_death()


## Override for death visuals. Default: vanish.
func _on_death() -> void:
	queue_free()


# --- Movement -----------------------------------------------------------------

## Move along X/Z direction `dir` (length <= 1 scales speed) for one frame.
## Slides along blocked edges, slows on climbs, and keeps Y on the ground.
## Returns true if the actor moved.
func move(dir: Vector3, delta: float) -> bool:
	dir.y = 0.0
	if dir.length() < 0.001 or dead:
		climbing = false
		return false
	if dir.length() > 1.0:
		dir = dir.normalized()
	facing = dir.normalized()
	var map: HexMap = GameWorld.map
	var step := dir * move_speed * delta
	var from := global_position
	var moved := false
	for attempt in [step, Vector3(step.x, 0, 0), Vector3(0, 0, step.z)]:
		if attempt.length() < 0.0001:
			continue
		var probe: Vector3 = from + attempt + attempt.normalized() * radius * 0.5
		var mv := map.movement_check(from, probe) if map else HexMap.Move.OK
		if mv == HexMap.Move.BLOCKED:
			continue
		climbing = mv == HexMap.Move.CLIMB
		var s: Vector3 = attempt * (CLIMB_SPEED_FACTOR if climbing else 1.0)
		global_position = from + s
		moved = true
		break
	if not moved:
		climbing = false
	_separate()
	snap_to_ground(delta)
	return moved


## Keep Y on the ground. With delta, eases (so climbs and drops look smooth).
func snap_to_ground(delta: float = -1.0) -> void:
	var map: HexMap = GameWorld.map
	if map == null or not is_inside_tree():
		return
	var g := map.ground_height(global_position)
	if is_nan(g):
		return
	if delta < 0.0:
		global_position.y = g
	else:
		var rate := 4.0 if climbing else 14.0
		global_position.y = lerpf(global_position.y, g, clampf(rate * delta, 0.0, 1.0))
		if absf(global_position.y - g) < 0.01:
			global_position.y = g


## Push apart from overlapping actors (cheap circle separation).
func _separate() -> void:
	var map: HexMap = GameWorld.map
	for other in GameWorld.actors_in_radius(global_position, radius):
		if other == self:
			continue
		var d := global_position - other.global_position
		d.y = 0.0
		var overlap := radius + other.radius - d.length()
		if overlap <= 0.0:
			continue
		var push := (d.normalized() if d.length() > 0.001 else Vector3.RIGHT) * overlap * 0.5
		var target := global_position + push
		if map == null or map.movement_check(global_position, target) == HexMap.Move.OK:
			global_position = target


## Turn to face a world point (X/Z only).
func face_point(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.001:
		facing = d.normalized()


func current_cell() -> Vector2i:
	return Hex.from_world(global_position)


func _now() -> float:
	return GameWorld.time
