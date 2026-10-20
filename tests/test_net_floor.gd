extends MonsterTestBase
## M1, single process: the floor checksum and the net ids (scripts/net/net_floor.gd).
## - two builds of one contract seed agree on every part of the checksum; another seed differs in all of them;
## - ONE changed cell, one moved monster, one different contract field is caught, in the part that owns it;
## - ids come in build order and are the same on a rebuild; heroes get their seat as the id;
## - the canonical text does not depend on dictionary insertion order or float formatting.

const SEED := 5


func setup() -> void:
	timeout_sec = 120.0
	Monster.use_proto_visuals = true
	_check_canon()
	var a := _build(SEED)
	var b := _build(SEED)
	for k in ["all", "map", "plan", "run", "spawn"]:
		eq(str(a[k]), str(b[k]), "two builds of seed %d agree on %s" % [SEED, k])
	eq(NetFloor.differing_parts(a, b), [] as Array[String], "so no part differs")
	check(int(a["cells"]) > 500 and int(a["actors"]) > 30, "the checksum covers a real floor (%d cells, %d actors)" % [int(a["cells"]), int(a["actors"])])
	check((a["plan_keys"] as Dictionary).size() >= 20, "and keeps a hash per site plan field")
	var other := _build(SEED + 1)
	var diff := NetFloor.differing_parts(a, other)
	check(diff.has("map") and diff.has("plan") and diff.has("run") and diff.has("spawn"), "another seed differs in every part (%s)" % str(diff))
	check(str(a["all"]) != str(other["all"]), "and in the whole")
	_check_one_change()
	_check_ids()
	Monster.use_proto_visuals = false
	finish()


## Build seed `s`'s floor 1 (map, plan, spawn) and return its checksum. Leaves the world up.
func _build(s: int, tweak: Callable = Callable()) -> Dictionary:
	var run := ContractBoard.run_for_seed(s)
	var map := DungeonGen.generate(run.floor_seed(1))
	if world != null:
		world.free()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	GameWorld.begin(map, world, run.floor_seed(1))
	var plan := SiteBuilder.plan(map, run, 1, PricedProp.catalog(run.site_type))
	var site := SiteBuilder.spawn(map, run, plan)
	_last = {"map": map, "plan": plan, "run": run, "site": site}
	NetFloor.assign_ids(world, {})
	if tweak.is_valid():
		tweak.call(_last)
	return NetFloor.checksum(map, plan, run, world)


var _last := {}


func _check_one_change() -> void:
	var base := _build(SEED)
	# One cell one level higher: only the map part (and anything standing on it) moves.
	var cell_changed := _build(SEED, func(f: Dictionary) -> void:
		var m: HexMap = f["map"]
		var c: Vector2i = m.walkable_cells()[0]
		m.get_cell(c).level += 1)
	check(NetFloor.differing_parts(base, cell_changed).has("map"), "one cell one level higher changes the map checksum")
	eq(str(base["plan"]), str(cell_changed["plan"]), "... and not the site plan")
	# One monster a little to the left: the spawn table, nothing else.
	var moved := _build(SEED, func(f: Dictionary) -> void:
		var site: SiteBuilder.Site = f["site"]
		site.monsters[0].global_position += Vector3(0.05, 0.0, 0.0))
	eq(NetFloor.differing_parts(base, moved), ["spawn"] as Array[String], "one monster 5 cm off changes the spawn table only")
	# One field of the site plan.
	var planned := _build(SEED, func(f: Dictionary) -> void:
		var p: SitePlan = f["plan"]
		p.dispatch += "!")
	eq(NetFloor.differing_parts(base, planned), ["plan"] as Array[String], "one changed plan field changes the plan only")
	var keys: Array = []
	for k: String in base["plan_keys"]:
		if str(base["plan_keys"][k]) != str(planned["plan_keys"][k]):
			keys.append(k)
	eq(keys, ["dispatch"], "and says which field")
	# A different material on one cell (the plan writes them into the map).
	var mat := _build(SEED, func(f: Dictionary) -> void:
		var m: HexMap = f["map"]
		m.get_cell(m.walkable_cells()[3]).mat_id ^= 1)
	check(NetFloor.differing_parts(base, mat).has("map"), "a different floor material is a different map")
	# A different contract field.
	var run_changed := _build(SEED, func(f: Dictionary) -> void:
		var r: ContractRun = f["run"]
		r.difficulty += 0.01)
	check(NetFloor.differing_parts(base, run_changed).has("run"), "a different contract difficulty changes the run part")


func _check_ids() -> void:
	_build(SEED)
	var hero := Actor.new()
	hero.team = GameWorld.TEAM_HEROES
	var seat2 := Actor.new()
	seat2.team = GameWorld.TEAM_HEROES
	GameWorld.spawn(hero, Hex.to_world(Vector2i.ZERO))
	GameWorld.spawn(seat2, Hex.to_world(Vector2i(1, 0)))
	var n := NetFloor.assign_ids(world, {1: hero, 3: seat2})
	eq(NetFloor.id_of(hero), 1, "a hero's id is its seat")
	eq(NetFloor.id_of(seat2), 3, "seat 3")
	check(n > 30, "every other actor got an id (%d)" % n)
	var ids: Array = NetFloor.actors_under(world).filter(func(a: Actor) -> bool: return a != hero and a != seat2).map(func(a: Actor) -> int: return NetFloor.id_of(a))
	var sorted := ids.duplicate()
	sorted.sort()
	eq(ids, sorted, "ids rise in build order")
	eq(int(ids[0]), NetFloor.ID_BASE, "from ID_BASE")
	eq(int(ids[ids.size() - 1]), NetFloor.ID_BASE + n - 1, "with no gaps")
	var first_run := ids.duplicate()
	_build(SEED)
	var again: Array = NetFloor.actors_under(world).map(func(a: Actor) -> int: return NetFloor.id_of(a))
	eq(again, first_run, "a rebuild gives the same ids to the same actors")


func _check_canon() -> void:
	eq(NetFloor.canon({"a": 1, "b": [1.5, Vector2(1, 2)]}), NetFloor.canon({"b": [1.5, Vector2(1, 2)], "a": 1}), "dictionary order does not matter")
	check(NetFloor.canon({"a": 1}) != NetFloor.canon({"a": 2}), "values do")
	eq(NetFloor.canon(1.0), NetFloor.canon(1.00000001), "floats are compared to four decimals")
	check(NetFloor.canon(1.0) != NetFloor.canon(1.001), "but not coarser than that")
	eq(NetFloor.canon(-0.0), NetFloor.canon(0.0), "negative zero is zero")
	check(NetFloor.canon([1, 2]) != NetFloor.canon([2, 1]), "array order does")
