class_name OrderFx
extends RefCounted
## The look of a voice order (VoiceOrders.feedback; cosmetic: every machine draws its own from the events it has).
##   bark(hero, text)               the line an AI hero says when it takes an order, over its head for BARK_TIME
##   waypoint(point, color)         where a "go" sends them, on the SPEAKER's screen for WAYPOINT_TIME
##   marker(point, text, hero, c)   an order to a hero a person plays ("Fox: go here"), on THAT player's screen: a pin and
##                                  its line, until their hero gets within MARKER_REACHED of it or MARKER_TIME runs out
## All of it spawns under GameWorld.root (gone with the floor) and is a no-op without a world.

const BARK_TIME := 1.8
const WAYPOINT_TIME := 3.0
const MARKER_TIME := 12.0
const MARKER_REACHED := 1.5
const BARK_NAME := "OrderBark"


static func _world_ready() -> bool:
	return GameWorld.root != null and GameWorld.root.is_inside_tree()


## The line `actor` says over its head (a newer line replaces the old one).
static func bark(actor: Node3D, text: String) -> Label3D:
	if actor == null or not is_instance_valid(actor) or text == "" or not actor.is_inside_tree():
		return null
	var old := actor.get_node_or_null(BARK_NAME)
	if old != null:
		actor.remove_child(old)
		old.queue_free()
	var top := 1.95
	var model: Variant = actor.get("visual_override")
	if model != null and "ui_height" in (model as Object):
		top = float((model as Object).get("ui_height"))
	var l := Label3D.new()
	l.name = BARK_NAME
	l.text = text
	l.font_size = 42
	l.pixel_size = 0.0085
	l.outline_size = 10
	l.modulate = Color(1.0, 0.98, 0.9)
	l.outline_modulate = Color(0.08, 0.06, 0.1, 0.95)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 12
	l.position = Vector3(0.0, top + 1.1, 0.0)
	actor.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", top + 1.25, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(BARK_TIME - 0.55)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)
	return l


## A ground pin at `point`: a ring and a short post with a flag, in `color`.
static func _pin(point: Vector3, color: Color) -> Node3D:
	var root := Node3D.new()
	var mat := Fx.glow_material(Color(color.r, color.g, color.b, 0.85), false)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.55
	ring.rings = 32
	ring.ring_segments = 6
	var ri := MeshInstance3D.new()
	ri.name = "Ring"
	ri.mesh = ring
	ri.material_override = mat
	ri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ri.position = Vector3(0.0, 0.06, 0.0)
	root.add_child(ri)
	var post := CylinderMesh.new()
	post.top_radius = 0.03
	post.bottom_radius = 0.03
	post.height = 1.1
	var pi := MeshInstance3D.new()
	pi.mesh = post
	pi.material_override = mat
	pi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pi.position = Vector3(0.0, 0.55, 0.0)
	root.add_child(pi)
	var flag := BoxMesh.new()
	flag.size = Vector3(0.36, 0.22, 0.03)
	var fi := MeshInstance3D.new()
	fi.mesh = flag
	fi.material_override = mat
	fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fi.position = Vector3(0.19, 0.98, 0.0)
	root.add_child(fi)
	return root


## Where a "go" sends them, on the speaker's screen: a pin that pops in, pulses and fades after WAYPOINT_TIME.
static func waypoint(point: Vector3, color: Color) -> Node3D:
	if not _world_ready() or point == Vector3.INF:
		return null
	var pin := _pin(point, color)
	pin.name = "OrderWaypoint"
	GameWorld.spawn(pin, point)
	pin.scale = Vector3.ONE * 0.3
	var tw := pin.create_tween()
	tw.tween_property(pin, "scale", Vector3.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(WAYPOINT_TIME - 0.5)
	tw.tween_property(pin, "scale", Vector3.ONE * 0.01, 0.3)
	tw.tween_callback(pin.queue_free)
	Fx.ring(point, 0.9, color, 0.5)
	return pin


## An order to a hero a person plays, on that player's screen: a pin and "<speaker>: go here" over it, until `hero` gets
## within MARKER_REACHED of it or MARKER_TIME passes. A newer marker replaces the old one.
static func marker(point: Vector3, text: String, hero: Node3D, color: Color) -> Node3D:
	if not _world_ready() or point == Vector3.INF:
		return null
	for old in GameWorld.root.get_tree().get_nodes_in_group(Marker.GROUP):
		(old as Node).queue_free()
	var m := Marker.new()
	m.name = "OrderMarker"
	m.hero = hero
	m.add_child(_pin(point, color))
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.009
	l.outline_size = 10
	l.modulate = Color(1.0, 0.98, 0.9)
	l.outline_modulate = Color(0.08, 0.06, 0.1, 0.95)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 12
	l.position = Vector3(0.0, 1.55, 0.0)
	m.add_child(l)
	m.label = l
	GameWorld.spawn(m, point)
	return m


## A player's order marker: clears itself when its hero arrives or after MARKER_TIME.
class Marker extends Node3D:
	const GROUP := "order_markers"
	var hero: Node3D = null
	var label: Label3D = null
	var _age := 0.0

	func _ready() -> void:
		add_to_group(GROUP)

	func _process(delta: float) -> void:
		_age += delta
		var arrived := hero != null and is_instance_valid(hero) \
				and GameWorld.flat_distance(hero.global_position, global_position) <= OrderFx.MARKER_REACHED
		if arrived or _age >= OrderFx.MARKER_TIME:
			queue_free()
			return
		scale = Vector3.ONE * (1.0 + 0.06 * sin(_age * 6.0))

	## What it says (tests).
	func text() -> String:
		return label.text if label != null else ""
