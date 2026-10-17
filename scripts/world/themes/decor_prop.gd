class_name DecorProp
extends Node3D
## A piece of set dressing in the world (DecorModels model + optional walk-blocking). Not priced and not
## breakable: purely decorative. A "blocking" kind adds invisible neutral DecorBlocker actors (the same soft
## circle separation the priced props use), so heroes and monsters walk around it; a non-blocking one
## (rugs, signs, recliners, candles) is walked through.
##
##   DecorProp.spawn_plan(plan)      # everything SitePlan.decor / SitePlan.lights describes -> Array[Node3D]
##   DecorProp.spawn(entry)          # one decor placement

var kind := ""
var entry: Dictionary = {}
var blockers: Array[DecorBlocker] = []
var model: Node3D = null


static func spawn(e: Dictionary, parent: Node = null) -> DecorProp:
	var root: Node = parent if parent != null else GameWorld.root
	if root == null or not RoomThemeDefs.is_decor(str(e["kind"])):
		return null
	var p := DecorProp.new()
	p.setup(e)
	root.add_child(p)
	var pos: Vector2 = e["pos"]
	var y := 0.0
	var map := GameWorld.map
	if map != null:
		var h := map.ground_height(Vector3(pos.x, 0.0, pos.y))
		if not is_nan(h):
			y = h
	p.global_position = Vector3(pos.x, y + float(e.get("lift", 0.0)), pos.y)
	p._make_blockers()
	return p


func setup(e: Dictionary) -> void:
	entry = e
	kind = str(e["kind"])
	name = kind.capitalize().replace(" ", "")
	rotation_degrees.y = float(e["yaw"])
	var params: Dictionary = (e.get("params", {}) as Dictionary).duplicate()
	var pos: Vector2 = e["pos"]
	params["variant"] = int(absf(pos.x * 7.0 + pos.y * 13.0))
	model = DecorModels.build(kind, params)
	add_child(model)


## The invisible blocker circles of a walk-blocking piece (call once the piece is in the tree and placed).
func _make_blockers() -> void:
	if not bool(entry.get("blocks", false)):
		return
	var pos: Vector2 = entry["pos"]
	var points: Array = entry.get("block_points", [pos])
	var radius := float(entry.get("block_radius", 0.5))
	for bp: Vector2 in points:
		var b := DecorBlocker.new()
		b.radius = radius
		add_child(b)
		b.global_position = Vector3(bp.x, global_position.y, bp.y)
		b.snap_to_ground()
		blockers.append(b)


## Spawn every decor piece and theme light of a plan under GameWorld.root; returns the nodes.
static func spawn_plan(plan: SitePlan) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if GameWorld.root == null:
		return out
	for e in plan.decor:
		var d := spawn(e)
		if d != null:
			out.append(d)
	if not plan.lights.is_empty():
		var holder := Node3D.new()
		holder.name = "ThemeLights"
		GameWorld.root.add_child(holder)
		for l in plan.lights:
			holder.add_child(ThemeLight.make(l))
		out.append(holder)
	return out
