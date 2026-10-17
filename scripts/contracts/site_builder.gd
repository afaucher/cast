class_name SiteBuilder
extends RefCounted
## Turns a generated floor (HexMap + DungeonGen tags) and a ContractRun into a site: the plan (pure
## data, plan()) and the spawned things (spawn()).
##
## Placement rules (docs/contracts-build.md):
##  - hellgates: floors 1-2 get small ones (ContractRun.floor_gates, spread over rooms other than the
##    start and exit rooms); floor 3 gets only the ORIGIN gate, in the origin room;
##  - origin room: the largest room that is neither the start nor the exit room (ties: farthest from
##    the start). It is also where the story says it happened;
##  - employees (2-4): the rooms farthest from the floor's gates (the origin on floor 3);
##  - priced props: along room edges (next to a wall) on flat floor, never within 3 of the start or the
##    exit, never within 2 cells of a corridor (so doors and corridors stay clear), spaced apart;
##  - monster packs: one per room except the start room, bigger on later floors and harder jobs, denser
##    near the gates (the pests spread outward), biased toward the contract's pest.
##
## Clear zones (hex distance): START_CLEAR / EXIT_CLEAR around the start and exit, CORRIDOR_CLEAR around
## any corridor cell.

const START_CLEAR := 3
const EXIT_CLEAR := 3
const CORRIDOR_CLEAR := 2
const GATE_START_CLEAR := 5
const PROP_SPACING := 3
const MAX_PROPS := 9
const PEST_MIN := 6                     ## at least this many pest-kind monsters per floor (a swarm counts as its imps)
const ROOM_BUDGET_BASE := 5
const ROOM_BUDGET_PER_ROOM := 1
const ROOM_BUDGET_PER_FLOOR := 3
const PEST_WEIGHT_MULT := 3.5

const STAFF_NAMES: Array[String] = [
	"Marguerite (sommelier)", "Dev (IT support)", "Bernadette (wellness)", "Colin (valet)", "Priya (chef)",
	"Hector (security)", "Imogen (concierge)", "Walt (maintenance)", "Tessa (intern)", "Mr. Okafor (accounts)",
]
const HENCHMAN_NAMES: Array[String] = [
	"Gary (Henchman 1)", "Steve (Henchman 2)", "Dwayne (Henchman 3)", "Kevin (Henchman 4)", "Brad (Henchman 5)",
	"Todd (Henchman 6)", "Gordon (Henchman 7)", "Nigel (Henchman 8)", "Craig (Henchman 9)", "Keith (Henchman 10)",
]


# ===========================================================================================
# Planning (pure)
# ===========================================================================================

## Plan one floor. `catalog` is the prop kinds available (PricedProp.catalog(site_type)).
static func plan(map: HexMap, run: ContractRun, floor_n: int, catalog: Array[String]) -> SitePlan:
	var p := SitePlan.new()
	p.floor_number = floor_n
	var rng := RandomNumberGenerator.new()
	rng.seed = run.floor_seed(floor_n) * 131 + floor_n * 17 + 5
	var starts := map.cells_with_tag("start")
	var exits := map.cells_with_tag("exit")
	p.start = starts[0] if not starts.is_empty() else Vector2i.ZERO
	p.exit = exits[0] if not exits.is_empty() else p.start
	_index_rooms(map, p)
	var near_start := _area(p.start, START_CLEAR)
	var near_exit := _area(p.exit, EXIT_CLEAR)
	var near_corr := _corridor_zone(map)
	# Keep a margin around the stairs so nothing is placed on a climb.
	var avoid := {}
	for c in near_start:
		avoid[c] = true
	for c in near_exit:
		avoid[c] = true

	_plan_gates(map, run, floor_n, p, rng, avoid, near_corr)
	_plan_employees(map, run, floor_n, p, rng, avoid)
	_plan_props(map, run, p, rng, avoid, near_corr, catalog)
	_plan_notes(map, run, floor_n, p, near_corr)
	_plan_packs(run, floor_n, p)
	_block_cells(p)
	return p


static func _index_rooms(map: HexMap, p: SitePlan) -> void:
	var by_tag: Dictionary = {}
	for c: Vector2i in map.cells:
		var tag: String = map.cells[c].tag
		if tag.begins_with("room:"):
			if not by_tag.has(tag):
				by_tag[tag] = [] as Array[Vector2i]
			(by_tag[tag] as Array[Vector2i]).append(c)
	var tags: Array = by_tag.keys()
	tags.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("room:")) < int(b.trim_prefix("room:")))
	for tag: String in tags:
		var cells: Array[Vector2i] = by_tag[tag]
		cells.sort_custom(_cell_less)
		p.rooms[tag] = cells
		# Centre: the room cell nearest to the mean of the room's cells.
		var sq := 0.0
		var sr := 0.0
		for c in cells:
			sq += c.x
			sr += c.y
		var mean := Hex.round_axial(sq / cells.size(), sr / cells.size())
		var best := cells[0]
		for c in cells:
			if Hex.distance(c, mean) < Hex.distance(best, mean):
				best = c
		p.centers[tag] = best
		# Modal level (the room's floor; platforms and pillars are the odd ones out).
		var counts: Dictionary = {}
		var mode_level := 0
		var mode_n := -1
		for c in cells:
			var lv: int = map.cells[c].level
			counts[lv] = int(counts.get(lv, 0)) + 1
			if int(counts[lv]) > mode_n or (int(counts[lv]) == mode_n and lv < mode_level):
				mode_n = int(counts[lv])
				mode_level = lv
		p.base_levels[tag] = mode_level
	p.start_room = _nearest_room(p, p.start)
	p.exit_room = _nearest_room(p, p.exit)


static func _nearest_room(p: SitePlan, cell: Vector2i) -> String:
	var best := ""
	var best_d := 1 << 20
	for tag: String in p.rooms:
		for c in (p.rooms[tag] as Array[Vector2i]):
			var d := Hex.distance(c, cell)
			if d < best_d:
				best_d = d
				best = tag
	return best


static func _cell_less(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


static func _area(c: Vector2i, r: int) -> Dictionary:
	var out := {}
	for n in Hex.range_cells(c, r):
		out[n] = true
	return out


static func _corridor_zone(map: HexMap) -> Dictionary:
	var zone := {}
	for c: Vector2i in map.cells:
		if map.cells[c].tag == "corridor":
			for n in Hex.range_cells(c, CORRIDOR_CLEAR):
				zone[n] = true
	return zone


## A flat, floor-type cell in `room` whose radius-`radius` neighbourhood is all flat floor of the same
## level. Used for gates (they are bigger than a hex).
static func _flat_spot(map: HexMap, p: SitePlan, tag: String, c: Vector2i, radius: int) -> bool:
	var level: int = int(p.base_levels[tag])
	for n in Hex.range_cells(c, radius):
		var cell: HexMap.Cell = map.get_cell(n)
		if cell == null or cell.type != HexMap.Tile.FLOOR or cell.level != level or not cell.tag.begins_with("room:"):
			return false
	return true


# --- gates ----------------------------------------------------------------------------------

static func _plan_gates(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan, rng: RandomNumberGenerator, avoid: Dictionary, near_corr: Dictionary) -> void:
	var cand: Array[String] = []
	for tag: String in p.rooms:
		if tag != p.start_room and tag != p.exit_room:
			cand.append(tag)
	if cand.is_empty():
		for tag: String in p.rooms:
			if tag != p.start_room:
				cand.append(tag)
	if floor_n >= ContractRun.FLOOR_COUNT:
		# The origin gate: the biggest eligible room (ties: farthest from the start); a room with no room
		# for it is skipped for the next biggest.
		var by_size: Array[String] = cand.duplicate()
		by_size.sort_custom(func(a: String, b: String) -> bool:
			var na: int = (p.rooms[a] as Array).size()
			var nb: int = (p.rooms[b] as Array).size()
			if na != nb:
				return na > nb
			var da := Hex.distance(p.centers[a], p.start)
			var db := Hex.distance(p.centers[b], p.start)
			return da > db or (da == db and int(a.trim_prefix("room:")) < int(b.trim_prefix("room:"))))
		var spot := NO_SPOT
		var pick := ""
		for radius in [2, 1, 0]:
			for tag in by_size:
				spot = _gate_spot(map, p, tag, radius, avoid, near_corr, [])
				if spot != NO_SPOT:
					pick = tag
					break
			if spot != NO_SPOT and (radius < 2 or pick == by_size[0]):
				break
		p.origin_room = pick
		if spot != NO_SPOT:
			p.gates.append({"cell": spot, "origin": true, "room": pick})
		return
	var count: int = run.floor_gates[floor_n - 1]
	var chosen: Array[String] = []
	var taken: Array[Vector2i] = []
	var first_pick := rng.randi_range(0, maxi(0, cand.size() - 1))
	for i in count:
		# Rooms in order of preference: the first gate goes to a random room, each next one to the room
		# farthest from the gates already placed (a room repeats only once all are used).
		var ordered: Array[String] = cand.duplicate()
		if chosen.is_empty():
			ordered = ordered.slice(first_pick) + ordered.slice(0, first_pick)
		else:
			var score: Dictionary = {}
			for tag in cand:
				var nearest := 1 << 20
				for ch in chosen:
					nearest = mini(nearest, Hex.distance(p.centers[tag], p.centers[ch]))
				score[tag] = nearest - (1000 if chosen.has(tag) else 0)
			ordered.sort_custom(func(a: String, b: String) -> bool:
				return int(score[a]) > int(score[b]) or (int(score[a]) == int(score[b]) and int(a.trim_prefix("room:")) < int(b.trim_prefix("room:"))))
		var spot := NO_SPOT
		var pick := ""
		for radius in [1, 0]:
			for tag in ordered:
				spot = _gate_spot(map, p, tag, radius, avoid, near_corr, taken)
				if spot != NO_SPOT:
					pick = tag
					break
			if spot != NO_SPOT:
				break
		if spot == NO_SPOT:
			continue
		chosen.append(pick)
		taken.append(spot)
		p.gates.append({"cell": spot, "origin": false, "room": pick})


const NO_SPOT := Vector2i(1 << 20, 1 << 20)


## The flat spot nearest the room centre that keeps clear of the start/exit, corridors and `taken` gates.
static func _gate_spot(map: HexMap, p: SitePlan, tag: String, radius: int, avoid: Dictionary, near_corr: Dictionary, taken: Array) -> Vector2i:
	var center: Vector2i = p.centers[tag]
	var cells: Array[Vector2i] = (p.rooms[tag] as Array[Vector2i]).duplicate()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := Hex.distance(a, center)
		var db := Hex.distance(b, center)
		return da < db or (da == db and _cell_less(a, b)))
	for strict in [true, false]:
		for c in cells:
			if not _flat_spot(map, p, tag, c, radius):
				continue
			if avoid.has(c) or Hex.distance(c, p.start) < GATE_START_CLEAR:
				continue
			if strict and near_corr.has(c):
				continue
			var ok := true
			for t: Vector2i in taken:
				if Hex.distance(t, c) < 5:
					ok = false
					break
			if ok:
				return c
	return NO_SPOT


# --- employees ------------------------------------------------------------------------------

static func _plan_employees(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan, rng: RandomNumberGenerator, avoid: Dictionary) -> void:
	var gate_cells := p.gate_cells()
	var scored: Array[Dictionary] = []
	for tag: String in p.rooms:
		if tag == p.start_room:
			continue
		var d := 1 << 20
		for g in gate_cells:
			d = mini(d, Hex.distance(p.centers[tag], g))
		if gate_cells.is_empty():
			d = Hex.distance(p.centers[tag], p.start)
		scored.append({"tag": tag, "d": d})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["d"]) != int(b["d"]):
			return int(a["d"]) > int(b["d"])
		return int(str(a["tag"]).trim_prefix("room:")) < int(str(b["tag"]).trim_prefix("room:")))
	for s in scored:
		p.ranked_rooms.append(str(s["tag"]))
	if p.ranked_rooms.is_empty():
		return
	var count: int = run.floor_employees[floor_n - 1]
	var style := "staff" if run.site_type == "bunker" else "henchman"
	var pool: Array[String] = STAFF_NAMES.duplicate() if style == "staff" else HENCHMAN_NAMES.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := pool[i]
		pool[i] = pool[j]
		pool[j] = t
	var rooms_used := clampi((count + 1) / 2, 1, p.ranked_rooms.size())
	var taken: Array[Vector2i] = []
	for i in count:
		# The preferred room first, then the next-farthest rooms in order.
		var spot := NO_SPOT
		var tag := ""
		for k in p.ranked_rooms.size():
			tag = p.ranked_rooms[(i % rooms_used + k) % p.ranked_rooms.size()]
			spot = _employee_spot(map, p, tag, avoid, gate_cells, taken, rng)
			if spot != NO_SPOT:
				break
		if spot == NO_SPOT:
			continue
		taken.append(spot)
		p.employees.append({"cell": spot, "name": pool[i % pool.size()], "style": style, "room": tag})


static func _employee_spot(map: HexMap, p: SitePlan, tag: String, avoid: Dictionary, gate_cells: Array[Vector2i], taken: Array[Vector2i], rng: RandomNumberGenerator) -> Vector2i:
	var level: int = int(p.base_levels[tag])
	var cands: Array[Vector2i] = []
	for c in (p.rooms[tag] as Array[Vector2i]):
		var cell: HexMap.Cell = map.cells[c]
		if cell.type != HexMap.Tile.FLOOR or cell.level != level or avoid.has(c):
			continue
		var ok := true
		for g in gate_cells:
			if Hex.distance(g, c) < 4:
				ok = false
				break
		for t in taken:
			if Hex.distance(t, c) < 2:
				ok = false
				break
		if ok:
			cands.append(c)
	if cands.is_empty():
		return NO_SPOT
	return cands[rng.randi_range(0, cands.size() - 1)]


# --- props ----------------------------------------------------------------------------------

static func _plan_props(map: HexMap, run: ContractRun, p: SitePlan, rng: RandomNumberGenerator, avoid: Dictionary, near_corr: Dictionary, catalog: Array[String]) -> void:
	if catalog.is_empty():
		return
	var gate_cells := p.gate_cells()
	var taken: Array[Vector2i] = []
	for e in p.employees:
		taken.append(e["cell"])
	var tags: Array = p.rooms.keys()
	tags.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("room:")) < int(b.trim_prefix("room:")))
	for tag: String in tags:
		if tag == p.start_room or p.props.size() >= MAX_PROPS:
			continue
		var level: int = int(p.base_levels[tag])
		var edge: Array[Vector2i] = []
		for c in (p.rooms[tag] as Array[Vector2i]):
			var cell: HexMap.Cell = map.cells[c]
			if cell.type != HexMap.Tile.FLOOR or cell.level != level or avoid.has(c) or near_corr.has(c):
				continue
			var by_wall := false
			var flat := true
			for d in Hex.DIRS:
				var nb: HexMap.Cell = map.get_cell(c + d)
				if nb == null:
					flat = false     # a pit edge: leave it alone
					break
				if nb.type == HexMap.Tile.WALL:
					by_wall = true
				elif nb.type == HexMap.Tile.STAIRS or absi(nb.level - level) > 1:
					flat = false
					break
			if by_wall and flat:
				edge.append(c)
		var want := clampi((p.rooms[tag] as Array).size() / 22, 1, 3)
		var placed := 0
		var tries := 0
		while placed < want and not edge.is_empty() and tries < 24 and p.props.size() < MAX_PROPS:
			tries += 1
			var c := edge[rng.randi_range(0, edge.size() - 1)]
			var ok := true
			for g in gate_cells:
				if Hex.distance(g, c) < 4:
					ok = false
					break
			for t in taken:
				if Hex.distance(t, c) < PROP_SPACING:
					ok = false
					break
			if not ok:
				continue
			taken.append(c)
			placed += 1
			p.props.append({"cell": c, "kind": catalog[rng.randi_range(0, catalog.size() - 1)], "room": tag})


# --- clue notes -----------------------------------------------------------------------------

static func _plan_notes(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan, near_corr: Dictionary) -> void:
	var clues: Array = run.story.get("clues", [])
	if clues.is_empty() or p.start_room == "":
		return
	var level: int = int(p.base_levels[p.start_room])
	var best := NO_SPOT
	var best_score := -1
	for c in Hex.range_cells(p.start, 8):
		var d := Hex.distance(c, p.start)
		var cell: HexMap.Cell = map.get_cell(c)
		if d < 4 or cell == null or cell.type != HexMap.Tile.FLOOR or cell.level != level or not cell.tag.begins_with("room:"):
			continue
		var score := (10 - absi(d - 5)) * 2 + (0 if near_corr.has(c) else 5)
		if score > best_score or (score == best_score and _cell_less(c, best)):
			best_score = score
			best = c
	if best != NO_SPOT:
		p.notes.append({"cell": best, "text": str(clues[(floor_n - 1) % clues.size()])})


# --- packs ----------------------------------------------------------------------------------

static func _plan_packs(run: ContractRun, floor_n: int, p: SitePlan) -> void:
	var gate_cells := p.gate_cells()
	var bonus_hard := int(roundf(run.difficulty * 3.0))
	for tag: String in p.rooms:
		if tag == p.start_room:
			continue
		var idx := int(tag.trim_prefix("room:"))
		var budget := ROOM_BUDGET_BASE + ROOM_BUDGET_PER_ROOM * idx + ROOM_BUDGET_PER_FLOOR * (floor_n - 1) + bonus_hard
		# The pests spread outward: denser the closer the room is to a gate.
		var d := 40
		for g in gate_cells:
			d = mini(d, Hex.distance(p.centers[tag], g))
		budget += int(roundf(3.0 * (1.0 - clampf(float(d) / 24.0, 0.0, 1.0))))
		p.pack_budgets[tag] = budget


static func _block_cells(p: SitePlan) -> void:
	for g in p.gates:
		for n in Hex.range_cells(g["cell"], 2):
			p.blocked[n] = true
	for e in p.employees:
		p.blocked[e["cell"]] = true
	for pr in p.props:
		for n in Hex.range_cells(pr["cell"], 1):
			p.blocked[n] = true
	for nt in p.notes:
		p.blocked[nt["cell"]] = true


# ===========================================================================================
# Spawning
# ===========================================================================================

## What spawn() put into the world.
class Site:
	extends RefCounted
	var plan: SitePlan
	var gates: Array[Actor] = []
	var origin_gate: Actor = null
	var employees: Array[Actor] = []
	var props: Array[Actor] = []
	var monsters: Array[Monster] = []
	var notes: Array[Node3D] = []
	var pest := ""                      ## the contract's pest ("everything" = every monster counts)
	var pest_spawned := 0               ## pest-kind monsters placed by the packs (gate spawns come later)


static func spawn(map: HexMap, run: ContractRun, p: SitePlan) -> Site:
	var site := Site.new()
	site.plan = p
	site.pest = run.pest
	var rng := RandomNumberGenerator.new()
	rng.seed = run.floor_seed(p.floor_number) * 31 + p.floor_number
	var gate_pest := "" if run.pest == "everything" else run.pest
	for g in p.gates:
		var gate := ContractParts.spawn_gate(g["cell"], {"difficulty": run.difficulty, "depth": p.floor_number, "origin": bool(g["origin"]), "pest": gate_pest})
		if gate == null:
			continue
		site.gates.append(gate)
		if bool(g["origin"]):
			site.origin_gate = gate
	for e in p.employees:
		var emp := ContractParts.spawn_employee(e["cell"], {"style": str(e["style"]), "name": str(e["name"])})
		if emp != null:
			site.employees.append(emp)
	for pr in p.props:
		var prop := ContractParts.spawn_prop(pr["cell"], str(pr["kind"]), {"site": run.site_type})
		if prop != null:
			site.props.append(prop)
	for nt in p.notes:
		var note := ClueNote.new()
		note.text = str(nt["text"])
		GameWorld.spawn(note, Hex.to_world(nt["cell"], float(map.get_cell(nt["cell"]).level) + 0.0))
		site.notes.append(note)
	_spawn_packs(map, run, p, site, rng)
	return site


static func _spawn_packs(map: HexMap, run: ContractRun, p: SitePlan, site: Site, rng: RandomNumberGenerator) -> void:
	var tags: Array = p.pack_budgets.keys()
	tags.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("room:")) < int(b.trim_prefix("room:")))
	var rooms_free: Dictionary = {}
	for tag: String in tags:
		var free: Array[Vector2i] = []
		for c in (p.rooms[tag] as Array[Vector2i]):
			if not p.blocked.has(c):
				free.append(c)
		rooms_free[tag] = free
		var plan_kinds := biased_composition(int(p.pack_budgets[tag]), rng, run.pest)
		_place_kinds(map, free, plan_kinds, rng, site)
	# Make sure there is something to exterminate: top up the pest if the dice were unkind.
	if run.pest != "everything":
		var guard := 0
		while site.pest_spawned < PEST_MIN and guard < 6 and not tags.is_empty():
			guard += 1
			var tag: String = tags[rng.randi_range(0, tags.size() - 1)]
			var kinds: Array[String] = [run.pest]
			_place_kinds(map, rooms_free[tag], kinds, rng, site)


## MonsterFactory.plan_composition with the pest's weight multiplied (a swarmer is still at most one
## group per pack).
static func biased_composition(budget: int, rng: RandomNumberGenerator, pest: String) -> Array[String]:
	var plan: Array[String] = []
	var counts := {}
	var left := budget
	while true:
		var kinds: Array[String] = []
		var weights: Array[float] = []
		var total := 0.0
		for k in MonsterFactory.KINDS:
			if MonsterFactory.COSTS[k] > left or (k == "swarmer" and counts.get("swarmer", 0) > 0):
				continue
			var w: float = MonsterFactory.WEIGHTS[k] * pow(0.5, counts.get(k, 0))
			if k == pest:
				w *= PEST_WEIGHT_MULT
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
		left -= MonsterFactory.COSTS[pick]
	return plan


## Spawn a list of kinds on free walkable cells of one room, spread apart (a swarmer is a clump).
static func _place_kinds(map: HexMap, free: Array[Vector2i], kinds: Array[String], rng: RandomNumberGenerator, site: Site) -> void:
	var usable: Array[Vector2i] = []
	for c in free:
		var cell := map.get_cell(c)
		if cell != null and cell.type == HexMap.Tile.FLOOR and not usable.has(c):
			usable.append(c)
	var placed: Array[Vector2i] = []
	for kind in kinds:
		if usable.is_empty():
			break
		var center: Vector2i = MonsterFactory._pick_spread(usable, placed, rng)
		if kind != "swarmer":
			var m := MonsterFactory.spawn(kind, center)
			if m != null:
				site.monsters.append(m)
				if site.pest == "everything" or kind == site.pest:
					site.pest_spawned += 1
			placed.append(center)
			usable.erase(center)
			continue
		var want := rng.randi_range(MonsterFactory.SWARM_MIN, MonsterFactory.SWARM_MAX)
		var near: Array[Vector2i] = []
		for c in usable:
			if Hex.distance(c, center) <= 2:
				near.append(c)
		near.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Hex.distance(a, center) < Hex.distance(b, center))
		for i in mini(want, near.size()):
			var sm := MonsterFactory.spawn("swarmer", near[i])
			if sm != null:
				site.monsters.append(sm)
				if site.pest == "everything" or site.pest == "swarmer":
					site.pest_spawned += 1
			usable.erase(near[i])
		placed.append(center)


## Convenience for the game: plan + spawn in one call.
static func build(map: HexMap, run: ContractRun, floor_n: int) -> Site:
	var p := plan(map, run, floor_n, ContractParts.prop_catalog(run.site_type))
	return spawn(map, run, p)


## A pinned note (a clue): a small paper on the floor that shows its text when a hero is near.
class ClueNote:
	extends Node3D
	signal read(text: String)
	const READ_RANGE := 2.2
	var text := ""
	var seen := false
	var _label: Label3D
	var _paper: MeshInstance3D

	func _ready() -> void:
		_paper = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.7, 0.04, 0.9)
		_paper.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.93, 0.9, 0.78)
		mat.roughness = 0.9
		_paper.material_override = mat
		_paper.position = Vector3(0, 0.05, 0)
		_paper.rotation.y = 0.4
		add_child(_paper)
		_label = Label3D.new()
		_label.text = "NOTE"
		_label.font_size = 48
		_label.pixel_size = 0.012
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.modulate = Color(1.0, 0.95, 0.7)
		_label.outline_modulate = Color(0, 0, 0, 0.9)
		_label.outline_size = 10
		_label.position = Vector3(0, 0.9, 0)
		add_child(_label)

	func _process(_delta: float) -> void:
		if GameWorld.root == null:
			return
		var near := GameWorld.nearest_actor(global_position, GameWorld.TEAM_HEROES, READ_RANGE)
		if near != null and not seen:
			seen = true
			read.emit(text)
