class_name GymSpawns
extends RefCounted
## The test gym's spawn list (`--gym`, docs/design/test-gym.md): one entry per thing the gym can put down, read from the
## registries at runtime, so new content gets its button with no change here:
##   monster  every MonsterDefs.DEFS kind: MonsterFactory.spawn for the kinds with a model (pack kinds, the goblin, the goo
##            imp, ...); the sharks go into a pool (one entry per billed variant; "jockey", the imp gunner, rides an "imp"
##            shark), the gator into the sewer's water (its home region). A kind that none of those can build is listed with
##            `skip` (the reason) and no button. The zombie also has "Zombie (body)" (id monster:zombie:body): one that goes
##            down as it lands, a body to raise with coffee or burn with a fireball (haunted-build-plan.md H3); the acolyte has
##            "Procession" (id monster:acolyte:procession): a live one, an acolyte, its zombies and a rear acolyte walking a loop
##            round where it is put (ProcessionPlanner.build, haunted-build-plan.md H4); the ghosts' hosts (H5) are "Armour" and
##            "Bones" (dormant: a free "Wisp" nearby flies into one) and "Armour (possessed)" / "Bones (possessed)" (id
##            monster:<kind>:possessed: a wisp gets in as it lands and it wakes)
##   dummy   TrainingDummy: a static post and a walker, both with DUMMY_HP
##   prop     every PricedProp.TABLE kind that is not an explosive (an electrical panel brings its live wire by water)
##   hazard   every explosive kind (PricedProp.hazard_kinds())
##   staff    every EmployeeModel.STYLES style
##   pickup   every spell in SpellBook.SPELLS: its component on the floor (a spell that is not available yet: `skip`)
##   gate     a hellgate and an origin gate
##   decor    every RoomThemeDefs.DECOR kind (set dressing, not an actor)
##   ghost    the ghost look test (docs/design/ghost-look.md, LOOK-DEV ONLY): GhostBody's skeleton, armour and wisp, plain
##            cosmetic nodes (no AI, no combat, nothing networked) that the panel's Ghost look / strength / colour redress
##   haunt    the haunt look test (docs/design/haunt-look.md, LOOK-DEV ONLY): HauntPiece's suit of armour and crypt skeleton,
##            dormant and possessed (plain cosmetic nodes like the ghosts; a skeleton's niche or block faces the camera)
##   necro    the necro look test (docs/design/necro-look.md, LOOK-DEV ONLY): NecroBody's zombies, acolytes and grimoires in
##            each pose, cosmetic like the ghosts (the panel's Necro rim / Grimoire / Ghost colour redress them)
##            and "procession": NecroProcession, an acolyte leading zombies round a loop and raising the downed
##   crypt    the crypt and ectoplasm look tests (LOOK-DEV ONLY, cosmetic nodes, nothing networked): an ectoplasm puddle per
##            EctoplasmLook variant (docs/design/ectoplasm-look.md; plus a drip on a wall within HAUNT_WALL) and the crypt's
##            pieces, CryptProps.GYM_KINDS (docs/design/crypt-section.md; an ossuary goes against a wall within HAUNT_WALL),
##            and the crypt pests (docs/design/crypt-pests-look.md): CryptPest's rats and ecto blobs, each variant in each
##            pose ("pest:<kind>:<variant>:<pose>")
##   rooms    the haunted rooms' key props (docs/design/mansion-rooms.md, church-rooms.md, LOOK-DEV ONLY): HauntProps.GYM_KINDS,
##            plain cosmetic nodes (a wall piece backs onto the nearest wall); the panel's Haunt light relights the gym
## Entries: {id, group, key (the registry key), label, skip ("" or why it has no button)}. spawn() puts `n` of one round a
## world point on valid cells and returns what it made. Dev only: solo, so every spawn is this machine's own (GameWorld).

const DUMMY_HP := 5000.0
const PROP_YAW := 45.0             ## a free-standing prop faces the camera
const GHOST_YAW := -120.0          ## a ghost's host (its front is -Z) turned three-quarters to the camera
const HAUNT_WALL := 3.0            ## a crypt spawn this near a wall face also dresses the wall (a drip, an ossuary)
const PROCESSION_R := 5            ## the gym's procession walks a loop this many cells round where it is put ...
const PROCESSION_SPOTS := 4        ## ... through this many spots
const GROUPS: Array[String] = ["monster", "dummy", "prop", "hazard", "staff", "pickup", "gate", "decor", "ghost", "haunt",
		"necro", "crypt", "rooms"]


## Every entry, in GROUPS order and each registry's own order.
static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind: String in MonsterDefs.DEFS:
		var row: Dictionary = MonsterDefs.DEFS[kind]
		if MonsterFactory.SCRIPTS.has(kind):
			out.append(_e("monster", kind, kind.capitalize()))
			if kind == "zombie":
				out.append(_e("monster", kind, "Zombie (body)", {"id": "monster:zombie:body", "body": true}))
			elif kind == "acolyte":
				out.append(_e("monster", kind, "Procession", {"id": "monster:acolyte:procession", "procession": true}))
			elif kind == "armour" or kind == "bones":
				out.append(_e("monster", kind, "%s (possessed)" % kind.capitalize(), {"id": "monster:%s:possessed" % kind, "possessed": true}))
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
	for kind: String in GhostBody.KINDS:
		out.append(_e("ghost", kind, "ghost: " + kind))
	for kind: String in HauntPiece.KINDS:
		out.append(_e("haunt", kind, "haunt: " + kind.replace("_", " ")))
	for r: Array in NecroBody.entries():
		out.append(_e("necro", NecroBody.key_of(r[0], r[1], r[2]), NecroBody.label_of(r[0], r[1], r[2])))
	out.append(_e("necro", "procession", "procession (acolyte and zombies)"))
	for v: String in EctoplasmLook.VARIANTS:
		out.append(_e("crypt", "ecto_" + v, "ecto: " + v))
	for kind: String in CryptProps.GYM_KINDS:
		out.append(_e("crypt", "crypt_" + kind, "crypt: " + kind))
	for r: Array in CryptPest.entries():
		out.append(_e("crypt", CryptPest.key_of(r[0], r[1], r[2]), CryptPest.label_of(r[0], r[1], r[2])))
	for kind: String in HauntProps.GYM_KINDS:
		out.append(_e("rooms", kind, "%s: %s" % [HauntProps.row(kind)["set"], HauntProps.row(kind)["label"]]))
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
			elif bool(e.get("procession", false)):
				var pr := _procession(map, at)
				if pr != null:
					out.append(pr)
					out.append_array(pr.members())
			else:
				for c in cells_near(map, at, n):
					var m := MonsterFactory.spawn(key, c)
					if m != null:
						out.append(m)
						if bool(e.get("body", false)):
							m.die()   # (a zombie's body: down where it stands, H3; coffee or a fireball on it in the gym)
						elif bool(e.get("possessed", false)) and m is HauntHost:
							var w := HauntPlanner.build_wisp(m as HauntHost, false)   # (a ghost gets in: it wakes, H5)
							if w != null:
								out.append(w)
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
		"ghost":
			for c in cells_near(map, at, n, 1):
				var g := GhostBody.make(key)
				GameWorld.root.add_child(g)
				g.global_position = Hex.to_world(c, _level(map, c))
				g.rotation_degrees.y = GHOST_YAW
				out.append(g)
		"haunt":
			for c in cells_near(map, at, n, 2):
				var hp := HauntPiece.make(key)
				GameWorld.root.add_child(hp)
				hp.global_position = Hex.to_world(c, _level(map, c))
				hp.rotation_degrees.y = HauntPiece.FACING if key.begins_with("skeleton") else GHOST_YAW
				hp.pace = true
				out.append(hp)
		"necro":
			if key == "procession":
				var pr := NecroProcession.new()
				GameWorld.root.add_child(pr)
				pr.global_position = at
				out.append(pr)
				return out
			var f := key.split(":")
			for c in cells_near(map, at, n, 3 if f[0] == "grimoire" else 1):
				var b := NecroBody.make(f[0], f[1], f[2])
				GameWorld.root.add_child(b)
				b.global_position = Hex.to_world(c, _level(map, c))
				b.rotation_degrees.y = -135.0 if f[0] == "grimoire" else GHOST_YAW
				out.append(b)
		"crypt":
			if key.begins_with("pest:"):
				var pf := key.split(":")
				for c in cells_near(map, at, n, 3 if pf[3] == "pack" else 1):
					var cp := CryptPest.make(pf[1], pf[2], pf[3])
					GameWorld.root.add_child(cp)
					cp.global_position = Hex.to_world(c, _level(map, c))
					cp.rotation_degrees.y = GHOST_YAW
					out.append(cp)
				return out
			for c in cells_near(map, at, n, 1):
				out.append_array(_haunt(map, key, Hex.to_world(c, _level(map, c))))
		"rooms":
			for c in cells_near(map, at, n, 2):
				var hp := HauntProps.gym_spawn(key, Hex.to_world(c, _level(map, c)))
				if hp != null:
					out.append(hp)
	return out


## A live procession (haunted-build-plan.md H4: ProcessionPlanner.build, real monsters) round `at`: a loop through
## PROCESSION_SPOTS spots PROCESSION_R cells out (the valid ones it can walk between). Null when fewer than two fit.
static func _procession(map: HexMap, at: Vector3) -> Procession:
	var centre := Hex.from_world(at)
	var ring := Hex.ring(centre, PROCESSION_R)
	var cells: Array[Vector2i] = []
	for i in PROCESSION_SPOTS:
		var c: Vector2i = ring[(i * ring.size()) / PROCESSION_SPOTS]
		if valid_cell(map, c) and (cells.is_empty() or not map.find_path(cells[cells.size() - 1], c, true, 2000).is_empty()):
			cells.append(c)
	if cells.size() < 2:
		return null
	return ProcessionPlanner.build(map, cells, [], "GymProcession")


## One haunt look-test piece at floor point `p` (cosmetic, under the world): an ectoplasm puddle (and a drip on the nearest
## wall face within HAUNT_WALL), or a crypt piece (an ossuary backs onto that wall face when there is one; the rest face
## the camera). Seeds from GameWorld.fx_rng (looks only).
static func _haunt(map: HexMap, key: String, p: Vector3) -> Array[Node]:
	var out: Array[Node] = []
	var seed_value := 1 + GameWorld.fx_rng.randi() % 9973
	var wall := map.nearest_wall(p, HAUNT_WALL)
	var node: Node3D
	if key.begins_with("ecto_"):
		var v := key.trim_prefix("ecto_")
		node = EctoplasmLook.puddle(v, 0.9, seed_value)
		GameWorld.root.add_child(node)
		node.global_position = p
		out.append(node)
		if not wall.is_empty():
			# the drip runs down from just under the wall's top (the game's walls are 1.5 high; the labs' are 3)
			var pt: Vector2 = wall["point"]
			var nrm: Vector2 = wall["normal"]
			var top := map.ground_height(Vector3(pt.x - nrm.x * 0.3, 0.0, pt.y - nrm.y * 0.3))
			var h := clampf((top if not is_nan(top) else p.y + 2.4) - p.y - 0.15, 0.6, 2.2)
			var d := EctoplasmLook.drip(v, h, seed_value)
			GameWorld.root.add_child(d)
			_on_wall(d, wall, p.y)
			out.append(d)
		return out
	var kind := key.trim_prefix("crypt_")
	node = CryptProps.build(kind, {"seed": seed_value})
	GameWorld.root.add_child(node)
	node.global_position = p
	node.rotation_degrees.y = PROP_YAW
	if kind == "ossuary" and not wall.is_empty():
		_on_wall(node, wall, p.y)
	out.append(node)
	return out


## Stand `node` (its back on local z = 0, its front +Z) on a wall face from HexMap.nearest_wall, at floor height `y`.
static func _on_wall(node: Node3D, wall: Dictionary, y: float) -> void:
	var pt: Vector2 = wall["point"]
	var nrm: Vector2 = wall["normal"]
	node.global_position = Vector3(pt.x, y, pt.y)
	node.rotation.y = atan2(nrm.x, nrm.y)


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
