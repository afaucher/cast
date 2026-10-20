class_name PackPlanner
extends RefCounted
## The monster packs of a floor: plan() sets each room's budget (SitePlan.pack_budgets), spawn() composes the packs
## (SiteBuilder.biased_composition) and places them on the room's free cells, topping up the contract's pest. SiteBuilder.plan
## / spawn call them; moved out of SiteBuilder verbatim (refactor plan H8).


const BUDGET_SCALE := 0.7               ## packs are this fraction of the old budgets (less crowded floors)
const PEST_MIN := 6                     ## at least this many pest-kind monsters per floor (a swarm counts as its imps)
const ROOM_BUDGET_BASE := 5
const ROOM_BUDGET_PER_ROOM := 1
const ROOM_BUDGET_PER_FLOOR := 3


static func plan(run: ContractRun, floor_n: int, p: SitePlan) -> void:
	var gate_cells := p.gate_cells()
	var bonus_hard := int(roundf(run.difficulty * 3.0))
	for tag: String in p.rooms:
		if tag == p.start_room or tag == SiteBuilder.arrival_room(p):
			continue
		var idx := int(tag.trim_prefix("room:"))
		var budget := ROOM_BUDGET_BASE + ROOM_BUDGET_PER_ROOM * idx + ROOM_BUDGET_PER_FLOOR * (floor_n - 1) + bonus_hard
		# The pests spread outward: denser the closer the room is to a gate.
		var d := 40
		for g in gate_cells:
			d = mini(d, Hex.distance(p.centers[tag], g))
		budget += int(roundf(3.0 * (1.0 - clampf(float(d) / 24.0, 0.0, 1.0))))
		p.pack_budgets[tag] = maxi(2, int(roundf(float(budget) * BUDGET_SCALE)))


static func spawn(map: HexMap, run: ContractRun, p: SitePlan, site: SiteBuilder.Site, rng: RandomNumberGenerator) -> void:
	var tags: Array = p.pack_budgets.keys()
	tags.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("room:")) < int(b.trim_prefix("room:")))
	var rooms_free: Dictionary = {}
	var room_count: Dictionary = {}
	for tag: String in tags:
		var free: Array[Vector2i] = []
		for c in (p.rooms[tag] as Array[Vector2i]):
			if not p.blocked.has(c):
				free.append(c)
		rooms_free[tag] = free
		var plan_kinds := SiteBuilder.biased_composition(int(p.pack_budgets[tag]), rng, run.pest)
		room_count[tag] = _place_kinds(map, free, plan_kinds, rng, site, SiteBuilder.room_cap(map, p.rooms[tag]))
	# Make sure there is something to exterminate: top up the pest if the dice were unkind.
	if run.pest != "everything":
		var guard := 0
		while site.pest_spawned < PEST_MIN and guard < 6 and not tags.is_empty():
			guard += 1
			var tag: String = tags[rng.randi_range(0, tags.size() - 1)]
			var kinds: Array[String] = [run.pest]
			var cap := SiteBuilder.room_cap(map, p.rooms[tag]) - int(room_count[tag])
			if cap > 0:
				room_count[tag] = int(room_count[tag]) + _place_kinds(map, rooms_free[tag], kinds, rng, site, cap)


## Spawn a list of kinds on free walkable cells of one room, spread apart (a swarmer is a clump of its own
## imps), never more than `cap` monsters in all. Returns how many were spawned.
static func _place_kinds(map: HexMap, free: Array[Vector2i], kinds: Array[String], rng: RandomNumberGenerator, site: SiteBuilder.Site, cap: int = 1 << 20) -> int:
	var spawned := 0
	var usable: Array[Vector2i] = []
	for c in free:
		var cell := map.get_cell(c)
		if cell != null and cell.type == HexMap.Tile.FLOOR and map.is_walkable_cell(c) and not map.is_pool_cell(c) and not usable.has(c):   # not a wall-cut cell, not in a pool
			usable.append(c)
	var placed: Array[Vector2i] = []
	for kind in kinds:
		if usable.is_empty() or spawned >= cap:
			break
		var center: Vector2i = MonsterFactory._pick_spread(usable, placed, rng)
		if not MonsterDefs.is_swarm(kind):
			var m := MonsterFactory.spawn(kind, center)
			if m != null:
				MonsterSenses.face_spawn(m, site.plan, rng.seed)   # toward the room's door or centre (monster-awareness.md)
				spawned += 1
				site.monsters.append(m)
				if site.pest == "everything" or kind == site.pest:
					site.pest_spawned += 1
			placed.append(center)
			usable.erase(center)
			continue
		var want := mini(rng.randi_range(MonsterFactory.SWARM_MIN, MonsterFactory.SWARM_MAX), cap - spawned)
		var near: Array[Vector2i] = []
		for c in usable:
			if Hex.distance(c, center) <= 2:
				near.append(c)
		near.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Hex.distance(a, center) < Hex.distance(b, center))
		for i in mini(want, near.size()):
			var sm := MonsterFactory.spawn(kind, near[i])
			if sm != null:
				MonsterSenses.face_spawn(sm, site.plan, rng.seed)
				spawned += 1
				site.monsters.append(sm)
				if site.pest == "everything" or site.pest == kind:
					site.pest_spawned += 1
			usable.erase(near[i])
		placed.append(center)
	return spawned


## Convenience for the game: plan + spawn in one call.
