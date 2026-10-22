class_name GymSpawns
extends RefCounted
## The test gym's spawn list (`--gym`, docs/design/test-gym.md): one entry per thing the gym can put down, read from the
## registries at runtime, so new content gets its button with no change here:
##   monster  every MonsterDefs.DEFS kind: MonsterFactory.spawn for the kinds with a model (pack kinds, the goblin, the goo
##            imp, ...); the sharks go into a pool (one entry per billed variant; "jockey", the imp gunner, rides an "imp"
##            shark), the gator into the sewer's water (its home region). A kind that none of those can build is listed with
##            `skip` (the reason) and no button.
##   dummy    TrainingDummy: a static post and a walker, both with DUMMY_HP
##   prop     every PricedProp.TABLE kind that is not an explosive (an electrical panel brings its live wire by water)
##   hazard   every explosive kind (PricedProp.hazard_kinds())
##   staff    every EmployeeModel.STYLES style
##   pickup   every spell in SpellBook.SPELLS: its component on the floor (a spell that is not available yet: `skip`)
##   gate     a hellgate and an origin gate
##   decor    every RoomThemeDefs.DECOR kind (set dressing, not an actor)
## Entries: {id, group, key (the registry key), label, skip ("" or why it has no button)}. spawn() puts `n` of one round a
## world point on valid cells and returns what it made. Dev only: solo, so every spawn is this machine's own (GameWorld).

const DUMMY_HP := 5000.0
const PROP_YAW := 45.0             ## a free-standing prop faces the camera
const GROUPS: Array[String] = ["monster", "dummy", "prop", "hazard", "staff", "pickup", "gate", "decor"]


## Every entry, in GROUPS order and each registry's own order.
static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind: String in MonsterDefs.DEFS:
		var row: Dictionary = MonsterDefs.DEFS[kind]
		if MonsterFactory.SCRIPTS.has(kind):
			out.append(_e("monster", kind, kind.capitalize()))
		elif kind == "shark":
			for v: String in (row.get("billed", {"regular": {}}) as Dictionary):
				out.append(_e("monster", kind, "Shark (%s)" % v, {"variant": v, "id": "monster:shark:" + v}))
		elif kind == "jockey":
			out.append(_e("monster", kind, "Imp gunner", {"variant": "imp"}))
		elif kind == "gator":
			out.append(_e("monster", kind, "Gator"))
		else:
			out.append(_e("monster", kind, kind.capitalize(), {"skip": "no spawner: a seed-built kind the gym does not know"}))
	out.append(_e("dummy", "static", "Dummy"))
	out.append(_e("dummy", "walker", "Dummy (walker)"))
	for kind: String in PricedProp.TABLE:
		out.append(_e("hazard" if PricedProp.is_hazard(kind) else "prop", kind, PricedProp.name_of(kind)))
	for style: String in EmployeeModel.STYLES:
		out.append(_e("staff", style, style.capitalize()))
	for id: String in SpellBook.SPELLS:
		var name := str((SpellBook.SPELLS[id] as Dictionary).get("name", id.capitalize()))
		out.append(_e("pickup", id, name, {} if SpellBook.is_available(id) else {"skip": "not available yet (SpellBook)"}))
	out.append(_e("gate", "hellgate", "Hellgate"))
	out.append(_e("gate", "origin", "Origin gate"))
	for kind: String in RoomThemeDefs.DECOR:
		out.append(_e("decor", kind, kind.capitalize()))
	return out


static func _e(group: String, key: String, label: String, extra: Dictionary = {}) -> Dictionary:
	var e := {"id": "%s:%s" % [group, key], "group": group, "key": key, "label": label, "skip": ""}
	e.merge(extra, true)
	return e


static func find(id: String) -> Dictionary:
	for e in entries():
		if str(e["id"]) == id:
			return e
	return {}


## Put `n` of entry `e` down round world point `at` (valid cells only). `site` is the floor's (the sewer's look for a live
## wire), `run` the contract (a gate's difficulty). Returns the nodes made (an empty list when nothing fits there).
static func spawn(e: Dictionary, at: Vector3, n: int, site: SiteBuilder.Site, run: ContractRun) -> Array[Node]:
	var out: Array[Node] = []
	var map := GameWorld.map
	if map == null or GameWorld.root == null or str(e.get("skip", "")) != "":
		return out
	var key := str(e["key"])
	match str(e["group"]):
		"monster":
			if key == "shark" or key == "jockey":
				for i in n:
					out.append_array(_shark(map, at, str(e["variant"]), i))
			elif key == "gator":
				for i in n:
					var g := _gator(map, at, i)
					if g != null:
						out.append(g)
			else:
				for c in cells_near(map, at, n):
					var m := MonsterFactory.spawn(key, c)
					if m != null:
						out.append(m)
		"dummy":
			for c in cells_near(map, at, n, 1):
				var d := TrainingDummy.new()
				d.mode = TrainingDummy.Mode.WALKER if key == "walker" else TrainingDummy.Mode.STATIC
				d.max_hp = DUMMY_HP
				d.name = "GymDummy"
				out.append(GameWorld.spawn(d, Hex.to_world(c, _level(map, c))))
		"prop", "hazard":
			for c in cells_near(map, at, n, 1):
				var w := Hex.to_world(c)
				var pp := PricedProp.spawn(c, key, {"yaw": PROP_YAW, "pos": Vector2(w.x, w.z)})
				if pp == null:
					continue
				out.append(pp)
				if key == "electrical_panel":
					var drop := LiveWire.drop_point_for(map, Vector2(pp.global_position.x, pp.global_position.z), pp.facing_vector())
					if drop != Vector3.INF:
						var wire := LiveWire.attach(pp, drop, site.sewer_view if site != null else null)
						if site != null:
							site.wires.append(wire)
		"staff":
			for c in cells_near(map, at, n):
				var emp := Employee.spawn(c, {"style": key})
				if emp != null:
					out.append(emp)
		"pickup":
			var cells := cells_near(map, at, n)
			for c in cells:
				var p := ComponentPickup.drop(key, SpellComponents.PICKUP_CHARGES, Hex.to_world(c, _level(map, c)), 0.0)
				if p != null:
					out.append(p)
		"gate":
			for c in cells_near(map, at, n, 2):
				var g := Hellgate.spawn(c, {"difficulty": run.difficulty if run != null else 0.5, "depth": 1,
						"origin": key == "origin", "pest": ""})
				if g != null:
					out.append(g)
		"decor":
			var dm: Dictionary = RoomThemeDefs.decor(key)
			for c in cells_near(map, at, n, 1):
				var w := Hex.to_world(c)
				var pos := Vector2(w.x, w.z)
				var entry := {"kind": key, "pos": pos, "yaw": PROP_YAW, "cell": c, "room": "", "place": str(dm.get("place", "floor")),
						"orient": "free", "group": -1, "role": "", "blocks": bool(dm.get("blocks", false)), "w": float(dm.get("w", 1.0)),
						"d": float(dm.get("d", 1.0)), "lift": 0.0, "target": pos, "params": {}, "block_points": [pos], "block_radius": 0.45}
				var dp := DecorProp.spawn(entry)
				if dp != null:
					out.append(dp)
	return out


## A mixed pack round `at` (MonsterFactory.spawn_pack's composer and spread, a floor-3 budget).
static func spawn_pack(at: Vector3, budget: int) -> Array[Node]:
	var out: Array[Node] = []
	var map := GameWorld.map
	if map == null:
		return out
	var cells := cells_near(map, at, 24)
	for m in MonsterFactory.spawn_pack(cells, budget, GameWorld.rng):
		out.append(m)
	return out


## Up to `n` full, dry, free floor cells nearest world point `at` (none under a set piece, no actor on it), `apart` cells
## between them; the nearest first. Searched out to SEARCH cells.
const SEARCH := 7
static func cells_near(map: HexMap, at: Vector3, n: int, apart: int = 0) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c0 := Hex.from_world(at)
	for r in SEARCH + 1:
		var ring: Array[Vector2i] = [c0]
		if r > 0:
			ring = Hex.ring(c0, r)
		for c in ring:
			if out.size() >= n:
				return out
			if not valid_cell(map, c):
				continue
			var ok := true
			for o in out:
				ok = ok and Hex.distance(o, c) > apart
			if ok:
				out.append(c)
	return out


static func valid_cell(map: HexMap, c: Vector2i) -> bool:
	if not map.is_walkable_cell(c) or map.no_stand.has(c):
		return false
	var cell: HexMap.Cell = map.get_cell(c)
	if cell.pool_mask != 0 or map.is_lava(c):
		return false
	return GameWorld.actors_in_radius(Hex.to_world(c, float(cell.level)), 0.8).is_empty()


static func _level(map: HexMap, c: Vector2i) -> float:
	var l := map.ground_level(Hex.to_world(c))
	return 0.0 if is_nan(l) else l


## A shark (and the imp on an "imp" one) in the pool under `at`, else in the floor's first pool. Nothing without a pool.
static func _shark(map: HexMap, at: Vector3, variant: String, i: int) -> Array[Node]:
	var out: Array[Node] = []
	var idx := -1
	var c := Hex.from_world(at)
	for k in map.pools.size():
		var rec: Dictionary = map.pools[k]
		if bool(rec.get("body", false)):
			continue
		if idx < 0 or (rec["basin"] as Array).has(c):
			idx = k
	if idx < 0:
		return out
	var pool: Dictionary = map.pools[idx]
	var start := Vector2(at.x, at.z) if (pool["basin"] as Array).has(c) else (pool["center"] as Vector2)
	var heading: Vector2 = pool["axis"]
	start += heading.orthogonal() * 0.3 * float(i)
	var s := Shark.new()
	s.setup(variant, idx, start, heading)
	GameWorld.spawn(s, Vector3(start.x, float(pool["floor_level"]) * Hex.LEVEL_HEIGHT + Shark.FLOAT, start.y))
	out.append(s)
	if variant == "imp":
		var j := Jockey.new()
		j.name = "Jockey"
		j.mount = s
		s.rider = j
		GameWorld.spawn(j, s.global_position)
		out.append(j)
	return out


## A gator in the sewer's water: at `at` when it is in the gators' home region, else in the cluster's first sump.
static func _gator(map: HexMap, at: Vector3, i: int) -> Gator:
	var region := GatorPlanner.region_of(map)
	if region.is_empty():
		return null
	var c := Hex.from_world(at)
	var spot := Vector2(at.x, at.z)
	if not region.has(c):
		var sumps: Array = SewerPlanner.record(map).get("sumps", [])
		if sumps.is_empty():
			return null
		spot = ThemeGeo.world((sumps[0] as Dictionary)["cell"])
	spot += Vector2(0.4, 0.0) * float(i)
	var spots: Array[Vector2] = []
	return Gator.spawn(spot, Vector2(0.0, 1.0), region, spots, 7919 + i)
