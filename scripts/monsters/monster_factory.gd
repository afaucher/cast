class_name MonsterFactory
extends RefCounted
## Spawns monsters and builds varied packs for a room from a point budget. The kinds, their costs and pick weights are
## MonsterDefs rows (grunt 2, archer 3, brute 6, swarmer PACK (4-6 imps) 4); a pack never holds more than one swarm.

## The pack kinds, in the roll's order (MonsterDefs order).
static var KINDS: Array[String] = MonsterDefs.pack_kinds()
static var COSTS: Dictionary = MonsterDefs.pack_field("cost")
## Relative pick weights; repeats of a kind are halved each time so rooms vary.
static var WEIGHTS: Dictionary = MonsterDefs.pack_field("weight")
const SWARM_MIN := 4
const SWARM_MAX := 6
const CELLS_PER_MONSTER := 6      ## density cap for a room: at most one monster per this many walkable cells
const SPREAD_CANDIDATES := 16     ## farthest-point sampling tries when placing a pack member (more = more spread)

## Every kind spawn() can build: the MonsterDefs kinds with a model (the pack kinds and the goblin scout; the sharks are
## built by SiteBuilder).
static var SCRIPTS: Dictionary = _factory_scripts()


static func _factory_scripts() -> Dictionary:
	var out := {}
	var all := MonsterDefs.scripts()
	for k in MonsterDefs.model_kinds():
		out[k] = all[k]
	return out


## Spawn one monster of `kind` standing on `cell`. Null for an unknown kind.
static func spawn(kind: String, cell: Vector2i) -> Monster:
	if not SCRIPTS.has(kind) or GameWorld.root == null:
		push_warning("MonsterFactory.spawn: unknown kind '%s' or no world" % kind)
		return null
	var m: Monster = SCRIPTS[kind].new()
	m.name = kind.capitalize()
	var level := 0.0
	var map := GameWorld.map
	if map != null:
		var l := map.ground_level(Hex.to_world(cell))
		if not is_nan(l):
			level = l
	GameWorld.spawn(m, Hex.to_world(cell, level))
	return m


## Pick a varied composition (list of kinds; a swarm kind appears at most once and means a whole clump). `bias`
## multiplies a kind's pick weight ({kind: factor}: SiteBuilder favours the contract's pest). The one pack composer: the
## floor plan depends on its exact rolls.
static func compose(budget: int, rng: RandomNumberGenerator, bias: Dictionary = {}) -> Array[String]:
	var plan: Array[String] = []
	var counts := {}
	var left := budget
	while true:
		var kinds: Array[String] = []
		var weights: Array[float] = []
		var total := 0.0
		for k in KINDS:
			if COSTS[k] > left or (MonsterDefs.is_swarm(k) and counts.get(k, 0) > 0):
				continue
			var w: float = WEIGHTS[k] * pow(0.5, counts.get(k, 0))
			if bias.has(k):
				w *= float(bias[k])
			kinds.append(k)
			weights.append(w)
			total += w
		if kinds.is_empty():
			break
		var roll := rng.randf() * total
		var pick := kinds[kinds.size() - 1]
		for i in kinds.size():
			roll -= weights[i]
			if roll <= 0.0:
				pick = kinds[i]
				break
		plan.append(pick)
		counts[pick] = counts.get(pick, 0) + 1
		left -= COSTS[pick]
	return plan


## Point cost of a list of spawned monsters (a swarm counts its cost per SWARM_MAX members).
static func cost_of(monsters: Array) -> int:
	var total := 0
	var swarms := {}
	for m in monsters:
		var k: String = m.kind
		if MonsterDefs.is_swarm(k):
			swarms[k] = int(swarms.get(k, 0)) + 1
		else:
			total += COSTS.get(k, 0)
	for k: String in swarms:
		total += COSTS[k] * int(ceil(float(swarms[k]) / SWARM_MAX))
	return total


## Fill a room. Only walkable, non-stairs cells from `room_cells` are used, spread apart.
## Monsters are spawned (added to the world) and returned.
## `max_count` (>= 0) caps the monsters in the pack (the room's density cap); -1 = no cap.
static func spawn_pack(room_cells: Array[Vector2i], budget: int, rng: RandomNumberGenerator, max_count: int = -1) -> Array[Monster]:
	var out: Array[Monster] = []
	var map := GameWorld.map
	var free: Array[Vector2i] = []
	for c in room_cells:
		if free.has(c):
			continue
		if map != null:
			var cell := map.get_cell(c)
			if cell == null or not map.is_walkable_cell(c) or cell.type == HexMap.Tile.STAIRS:   # full floor only (not a wall-cut cell)
				continue
		free.append(c)
	if free.is_empty() or budget < 2:
		return out

	var placed: Array[Vector2i] = []
	for kind in compose(budget, rng):
		if free.is_empty() or (max_count >= 0 and out.size() >= max_count):
			break
		var center := _pick_spread(free, placed, rng)
		if not MonsterDefs.is_swarm(kind):
			out.append(spawn(kind, center))
			placed.append(center)
			free.erase(center)
			continue
		# A swarm: a tight clump around the chosen cell.
		var want := rng.randi_range(SWARM_MIN, SWARM_MAX)
		if max_count >= 0:
			want = mini(want, max_count - out.size())
		var near: Array[Vector2i] = []
		for c in free:
			if Hex.distance(c, center) <= 2:
				near.append(c)
		near.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Hex.distance(a, center) < Hex.distance(b, center))
		for i in mini(want, near.size()):
			out.append(spawn(kind, near[i]))
			free.erase(near[i])
		placed.append(center)
	return out


## Farthest-point sampling over a few random candidates: spreads packs across the room.
static func _pick_spread(free: Array[Vector2i], placed: Array[Vector2i], rng: RandomNumberGenerator) -> Vector2i:
	var best := free[rng.randi_range(0, free.size() - 1)]
	if placed.is_empty():
		return best
	var best_score := -1
	for _i in SPREAD_CANDIDATES:
		var c := free[rng.randi_range(0, free.size() - 1)]
		var nearest := 1 << 20
		for p in placed:
			nearest = mini(nearest, Hex.distance(c, p))
		if nearest > best_score:
			best_score = nearest
			best = c
	return best
