class_name DecorProp
extends Node3D
## A piece of set dressing in the world (DecorModels model + optional walk-blocking). Not priced: purely
## decorative, and solid except for the boxes and crates (RoomThemeDefs.BREAKABLE_DECOR). A "blocking" kind adds
## invisible neutral DecorBlocker actors (the same soft circle separation the priced props use), so heroes and
## monsters walk around it; a non-blocking one (rugs, signs, recliners, candles) is walked through. A crate kind's
## first circle is a BreakableCrate instead: smash it and the model, the circles and the blocking are gone.
##
##   DecorProp.spawn_plan(plan)      # everything SitePlan.decor / SitePlan.lights describes -> Array[Node3D]
##   DecorProp.spawn(entry)          # one decor placement

var kind := ""
var entry: Dictionary = {}
var blockers: Array[Actor] = []   ## DecorBlocker circles, plus the BreakableCrate of a crate kind
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
	if kind == "summoning_circle":
		var rug := VanRug.new(float(params.get("radius", 2.1)) + 0.55)
		rug.set_garage(false)
		rug.set_tone(0.45)          # rooms are lit brighter than the garage; keep the chalk the brightest thing
		add_child(rug)


## The invisible blocker circles of a walk-blocking piece (call once the piece is in the tree and placed).
func _make_blockers() -> void:
	if not bool(entry.get("blocks", false)):
		return
	var pos: Vector2 = entry["pos"]
	var points: Array = entry.get("block_points", [pos])
	var radius := float(entry.get("block_radius", 0.5))
	var plain: Array[DecorBlocker] = []
	var crate: BreakableCrate = null
	for bp: Vector2 in points:
		var b: Actor = null
		if RoomThemeDefs.is_breakable(kind) and crate == null:
			crate = BreakableCrate.new()   # the first circle: the smashable one
			b = crate
		else:
			var plain_b := DecorBlocker.new()
			plain_b.radius = radius
			plain.append(plain_b)
			b = plain_b
		b.radius = radius
		add_child(b)
		b.global_position = Vector3(bp.x, global_position.y, bp.y)
		b.snap_to_ground()
		blockers.append(b)
	if crate != null:
		crate.setup(kind, model, radius, float(RoomThemeDefs.decor(kind).get("h", 1.0)), plain, pos)


## The smashable part of a crate kind (null for solid kinds).
func breakable() -> BreakableCrate:
	for b in blockers:
		if b is BreakableCrate:
			return b
	return null


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
