class_name MonsterFactory
extends RefCounted
## Spawns monsters and builds varied packs for a room from a point budget.
##
##   grunt 2, archer 3, brute 6, swarmer PACK (4-6 imps) 4.
## A pack never contains more than one swarmer group.

const KINDS: Array[String] = ["grunt", "archer", "brute", "swarmer"]
const COSTS := {"grunt": 2, "archer": 3, "brute": 6, "swarmer": 4}
## Relative pick weights; repeats of a kind are halved each time so rooms vary.
const WEIGHTS := {"grunt": 5.0, "archer": 3.0, "brute": 1.5, "swarmer": 2.5}
const SWARM_MIN := 4
const SWARM_MAX := 6
const CELLS_PER_MONSTER := 6      ## density cap for a room: at most one monster per this many walkable cells
const SPREAD_CANDIDATES := 16     ## farthest-point sampling tries when placing a pack member (more = more spread)

const SCRIPTS := {
	"grunt": preload("res://scripts/monsters/grunt.gd"),
	"archer": preload("res://scripts/monsters/archer.gd"),
	"brute": preload("res://scripts/monsters/brute.gd"),
	"swarmer": preload("res://scripts/monsters/swarmer.gd"),
	"goblin": preload("res://scripts/monsters/goblin.gd"),   ## the scout: never in a pack (SiteBuilder puts him in a corridor)
}


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


## Pick a varied composition (list of kinds; "swarmer" appears at most once and means a whole pack).
static func plan_composition(budget: int, rng: RandomNumberGenerator) -> Array[String]:
	var plan: Array[String] = []
	var counts := {}
	var left := budget
	while true:
		var kinds: Array[String] = []
		var weights: Array[float] = []
		var total := 0.0
		for k in KINDS:
			if COSTS[k] > left or (k == "swarmer" and counts.get("swarmer", 0) > 0):
				continue
			var w: float = WEIGHTS[k] * pow(0.5, counts.get(k, 0))
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


## Point cost of a list of spawned monsters (a swarmer group counts as 4 per 6 imps).
static func cost_of(monsters: Array) -> int:
	var total := 0
	var swarmers := 0
	for m in monsters:
		var k: String = m.kind
		if k == "swarmer":
			swarmers += 1
		else:
			total += COSTS.get(k, 0)
	if swarmers > 0:
		total += COSTS["swarmer"] * int(ceil(float(swarmers) / SWARM_MAX))
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
	for kind in plan_composition(budget, rng):
		if free.is_empty() or (max_count >= 0 and out.size() >= max_count):
			break
		var center := _pick_spread(free, placed, rng)
		if kind != "swarmer":
			out.append(spawn(kind, center))
			placed.append(center)
			free.erase(center)
			continue
		# Swarmers: a tight clump around the chosen cell.
		var want := rng.randi_range(SWARM_MIN, SWARM_MAX)
		if max_count >= 0:
			want = mini(want, max_count - out.size())
		var near: Array[Vector2i] = []
		for c in free:
			if Hex.distance(c, center) <= 2:
				near.append(c)
		near.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Hex.distance(a, center) < Hex.distance(b, center))
		for i in mini(want, near.size()):
			out.append(spawn("swarmer", near[i]))
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
