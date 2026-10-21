class_name GooBoots
extends Node3D
## Goo on an actor's feet (docs/design/goo-imp.md, "As built"; the look-dev's "a hero stuck in one reads by the goo on his
## boots"): shown on whoever a goo ball hit (for the hit's slow) and on anyone standing in a goo patch. Cosmetic, on every
## screen from what that screen shows: a child of the actor that removes itself once the actor is off the goo and the hit's
## time is up. Never touches gameplay (the slow is GooPatch.speed_mult and the "goo" modifier).

const NODE_NAME := "GooBoots"

var _until := 0.0


## Show the goo on `a` for at least `seconds` (a ball's hit), or keep it while it stands in a patch (GooPatch).
static func show_on(a: Node3D, seconds: float = 0.0) -> void:
	if a == null or not is_instance_valid(a) or not a.is_inside_tree():
		return
	var b := a.get_node_or_null(NODE_NAME) as GooBoots
	if b == null:
		b = GooBoots.new()
		b.name = NODE_NAME
		a.add_child(b)
	b._until = maxf(b._until, GameWorld.time + seconds)


static func has_on(a: Node) -> bool:
	return a != null and is_instance_valid(a) and a.get_node_or_null(NODE_NAME) != null


func _ready() -> void:
	var m := GooSoups.boots()
	add_child(m)
	var host := get_parent() as Node3D
	var k := 1.0
	if host is Actor:
		k = clampf((host as Actor).radius / 0.4, 0.6, 1.3)
	scale = Vector3(k, k, k)


func _process(_delta: float) -> void:
	var host := get_parent() as Node3D
	if host == null or (host is Actor and (host as Actor).dead):
		queue_free()
		return
	global_rotation = Vector3(0.0, host.global_rotation.y, 0.0)
	var slack := (host as Actor).radius * 0.5 if host is Actor else 0.0
	if GameWorld.time > _until and not GooPatch.covers_any(host.global_position, slack + 0.05):
		queue_free()
