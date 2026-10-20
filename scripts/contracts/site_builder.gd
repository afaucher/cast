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
##  - ROOM THEMES (scripts/world/themes): every room gets a theme from the site's pool (the start room is the
##    "service entrance", the origin room gets the theme the story names), recorded as SitePlan.room_themes;
##    the themes (and the site type) then pick each cell's floor / wall MATERIAL, written to Cell.mat_id (FloorMaterials);
##  - priced props: at most MAX_PROPS (6) a floor, one per room first (rooms in a shuffled order), the kind
##    picked by the room's theme (wine rack in the cellar, projector in the cinema, ...), only on cells next to
##    a wall on flat floor, never within 3 of the start or the exit, never within 2 cells of a corridor (so
##    doors and corridors stay clear), at least PROP_SPACING (4) apart. Each stands BACK TO THE WALL facing into
##    the room (or in a corner facing the centre) with a clear lane in front: SitePlan.props carry pos / yaw. The
##    anchor cells next to a wall are cut by the midpoint wall (HexMap.cut_walls): the prop stands flush against the
##    flat face and no footprint reaches the wall side (ThemeCtx);
##  - explosive props (ExplosiveProp, docs/design/hazards.md): planned right after the priced props with their own dice, in
##    the rooms whose theme has some (RoomThemeDefs "hazards"), on the same wall cells and poses, at most MAX_HAZARDS a floor,
##    sometimes a chained pair: SitePlan.hazards (HazardPlanner);
##  - standing spots (gates, employees, notes, monsters, the van) are FULL cells only (HexMap.is_walkable_cell);
##  - notes (ClueNote, docs/design/notes-rethink.md): two a floor, a story note and a hint slip in a side room, their
##    text from NoteCopy filled with this floor's facts (NoteFacts), plus the dispatch banner line: SitePlan.notes /
##    SitePlan.dispatch. Own RNG, planned after the props and before the decor (which steers around them);
##  - decor (not priced): each theme's set dressing, vignettes placed as one unit (SitePlan.decor, see RoomThemes);
##  - the crew's work van (VanPlan, SitePlan.van), FLOOR 1 ONLY (VAN_FLOOR): parked in the start room on flat floor beside the
##    start cell, planned before everything else so no prop, note, decor piece or package lands on it; its cells are blocked.
##    Floors 2 and 3 plan no van ({}), so their start rooms are laid out as if it had never existed;
##  - mail packages (MailPackage): 4-6 spots a floor, each 1-3 breakable boxes stacked, on room floor within a few
##    cells of a room's door (never in a corridor, never within START_CLEAR / EXIT_CLEAR of the start / exit, never
##    on a gate, employee, note, prop or decor), backed against a wall so the way through stays open. They roll their
##    own dice (a dedicated RNG), so nothing else on the floor shifts: SitePlan.packages;
##  - monster packs: one per room except the start room, bigger on later floors and harder jobs, denser
##    near the gates (the pests spread outward), biased toward the contract's pest. Budgets are scaled by
##    BUDGET_SCALE (0.7) and each room holds at most one monster per MonsterFactory.CELLS_PER_MONSTER
##    walkable cells, placed spread out.
##
##  - POOLS (PoolGeo, docs/design/pool-options.md "Built"): the indoor pool, science and shark moat rooms get an in-ground pool,
##    carved into the terrain right after the themes are dealt (clear of the doors, the start / exit / elevator zones,
##    the gates and the employees); everything planned after it (props, notes, decor, mail, monsters) keeps to dry floor;
##  - the ELEVATOR (SitePlan.elevator: HexMap.elevator plus the job's look): its car, doorway and landing
##    (ElevatorGeo.keep_cells) are avoided and blocked like the exit zone, and it is a body in its room's ThemeCtx.
##
## Clear zones (hex distance): START_CLEAR / EXIT_CLEAR around the start and exit (the exit is the elevator's landing),
## CORRIDOR_CLEAR around any corridor cell.

const START_CLEAR := 3
const EXIT_CLEAR := 3
const CORRIDOR_CLEAR := 2
const GATE_START_CLEAR := 5
const PROP_SPACING := 4
const MAX_PROPS := 6
const BUDGET_SCALE := 0.7               ## packs are this fraction of the old budgets (less crowded floors)
const PEST_MIN := 6                     ## at least this many pest-kind monsters per floor (a swarm counts as its imps)
const ROOM_BUDGET_BASE := 5
const ROOM_BUDGET_PER_ROOM := 1
const ROOM_BUDGET_PER_FLOOR := 3
const PEST_WEIGHT_MULT := 3.5

## THE employee names (the one source: Employee.spawn's fallback, the voice orders and the dispatch lines use these too).
## Screened against the speech model for the voice orders (user, 2026-10-19; tests/probe_voice_names.gd): every name is heard
## right for "<name> go / attack / follow", none is an order or a cast in chatter. Nigel is Henchman 4, so "Hench Four"
## (VoiceOrders: "(Henchman 4)") lands on a name the model always hears.
const STAFF_NAMES: Array[String] = [
	"Beatrice (sommelier)", "Mabel (wellness)", "Elsie (chef)", "Lionel (security)", "Pearl (valet)",
	"Penny (concierge)", "Molly (IT support)", "Mr. Bloom (accounts)", "Iris (intern)", "Stan (maintenance)",
]
const HENCHMAN_NAMES: Array[String] = [
	"Gary (Henchman 1)", "Steve (Henchman 2)", "Simon (Henchman 3)", "Nigel (Henchman 4)", "Brad (Henchman 5)",
	"Todd (Henchman 6)", "Gordon (Henchman 7)", "Kevin (Henchman 8)", "Craig (Henchman 9)", "Keith (Henchman 10)",
]


# ===========================================================================================
# Planning (pure)
# ===========================================================================================

## Plan one floor. `catalog` is the prop kinds available (PricedProp.catalog(site_type)).
static func plan(map: HexMap, run: ContractRun, floor_n: int, catalog: Array[String]) -> SitePlan:
	var t_start := Time.get_ticks_usec()
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
	# The elevator (the job's look on the generator's record): its car, doorway and landing stay clear of everything.
	p.elevator = map.elevator.duplicate(true)
	if not p.elevator.is_empty():
		p.elevator["look"] = run.elevator_look
	for c in ElevatorGeo.keep_cells(p.elevator):
		avoid[c] = true

	_plan_gates(map, run, floor_n, p, rng, avoid, near_corr)
	_plan_employees(map, run, floor_n, p, rng, avoid)
	var theme_seed: int = run.floor_seed(floor_n)
	var t0 := Time.get_ticks_usec()
	RoomThemes.assign(p, run.site_type, run.story, floor_n, theme_seed)
	# the in-ground pools of the pool / science / moat rooms: terrain, carved before anything is placed in those rooms
	PoolGeo.carve(map, p, avoid, near_corr, theme_seed * 613 + floor_n * 7 + 1)
	var ctx := ThemeCtx.make(map, p, avoid, near_corr, theme_seed * 919 + floor_n * 13 + 3)
	_elevator_body(p, ctx)
	last_theme_usec = Time.get_ticks_usec() - t0
	_plan_van(map, p, ctx, floor_n)
	t0 = Time.get_ticks_usec()
	_plan_props(map, run, p, rng, avoid, near_corr, catalog, ctx)
	var t_hz := Time.get_ticks_usec()
	HazardPlanner.plan(map, run, floor_n, p, avoid, near_corr, ctx)
	last_hazard_usec = Time.get_ticks_usec() - t_hz
	NotePlanner.plan(map, run, floor_n, p, ctx)
	last_theme_usec += Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	RoomThemes.plan_decor(ctx)
	last_theme_usec += Time.get_ticks_usec() - t0
	PackagePlanner.plan(map, run, floor_n, p, ctx)
	_plan_packs(run, floor_n, p)
	_block_cells(p)
	ScoutPlanner.plan(map, run, floor_n, p)
	last_plan_usec = Time.get_ticks_usec() - t_start
	# The look of the floor: every cell's floor / wall material from its room's theme (FloorMaterials). Not planning, so
	# it is timed on its own (FloorMaterials.last_usec) and not counted in last_plan_usec.
	FloorMaterials.assign(map, p, run.site_type)
	# The office doors and their thresholds (after the materials: a threshold writes its cells' floor). Timed on its own.
	var t_doors := Time.get_ticks_usec()
	DoorPlanner.plan(map, run, floor_n, p)
	last_door_usec = Time.get_ticks_usec() - t_doors
	# The pool sharks (docs/design/sharks.md): after everything else, with dice of their own. Timed on its own.
	var t_sharks := Time.get_ticks_usec()
	SharkPlanner.plan(map, run, floor_n, p)
	last_shark_usec = Time.get_ticks_usec() - t_sharks
	return p


## The crew's work van, parked beside the start cell (VanPlan) on the FIRST floor only: the van stays where it parked, so
## floors 2 and 3 have none (p.van stays {}). Planned before the props, the notes, the decor and the packages, which all see
## it as a body and a solid footprint in the start room. It draws no random numbers, so nothing else on the floor moves
## because of it (apart from keeping out of its way).
const VAN_FLOOR := 1


## Where the crew arrives on this floor: the start room (the van) on the van floor, the elevator's room on every other
## floor (the crew rides the elevator down and steps out there). No monster pack or employee is placed in it.
static func arrival_room(p: SitePlan) -> String:
	return p.start_room if p.floor_number <= VAN_FLOOR else p.exit_room


static func _plan_van(map: HexMap, p: SitePlan, ctx: ThemeCtx, floor_n: int) -> void:
	if floor_n != VAN_FLOOR:
		p.van = {}
		return
	p.van = VanPlan.plan(map, p, _corridor_distance(map, 4))
	if p.van.is_empty() or not ctx.rooms.has(p.start_room):
		return
	var room: ThemeCtx.RoomInfo = ctx.rooms[p.start_room]
	ctx.add_body(room, p.van["pos"], float(p.van["yaw"]), float(p.van["w"]), float(p.van["d"]), -1, "van")
	for c: Vector2i in p.van["cells"]:
		ctx.solid[c] = true


## The elevator as a body in its room, so no prop, note, decor piece or package overlaps it (its cells are avoided too).
static func _elevator_body(p: SitePlan, ctx: ThemeCtx) -> void:
	if p.elevator.is_empty():
		return
	var room: ThemeCtx.RoomInfo = ctx.rooms.get(p.exit_room)   # (the landing is the exit cell, the elevator's room's)
	if room == null:
		return
	var pos: Vector2 = p.elevator["pos"]
	var yaw := float(p.elevator["yaw"])
	if str(p.elevator["place"]) == ElevatorGeo.PLACE_WALL:
		ctx.add_body(room, ElevatorGeo.to_world(p.elevator, Vector2(0.0, -0.45)), yaw, 2.0 * ElevatorGeo.JAMB_OUT + 0.4, 2.6, -1, "elevator")
	else:
		ctx.add_body(room, pos, yaw, 2.0 * ElevatorGeo.SHAFT_R + 1.6, 2.0 * ElevatorGeo.SHAFT_R + 1.6, -1, "elevator")


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
		if cell == null or cell.type != HexMap.Tile.FLOOR or cell.level != level or not cell.tag.begins_with("room:") or not map.is_walkable_cell(n):
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
const CAMERA_YAW := 45.0                ## a model facing this yaw faces the game camera (CameraRig.YAW_DEG)
## Microseconds the last plan() spent on room themes + set dressing (assign, props placement included, decor); a
## perf probe for tests/test_room_themes.gd.
static var last_theme_usec := 0
static var last_plan_usec := 0
static var last_door_usec := 0   ## the doors' planning and thresholds (not in last_plan_usec, like FloorMaterials.last_usec)
## Microseconds the last plan() spent placing explosive props (HazardPlanner.plan; part of last_theme_usec).
static var last_hazard_usec := 0
## Microseconds the last plan() spent choosing the pool sharks (SharkPlanner.plan; not in last_plan_usec, like the doors).
static var last_shark_usec := 0


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
		if tag == p.start_room or tag == arrival_room(p):
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
		if cell.type != HexMap.Tile.FLOOR or cell.level != level or avoid.has(c) or not map.is_walkable_cell(c):
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

static func _plan_props(map: HexMap, run: ContractRun, p: SitePlan, rng: RandomNumberGenerator, avoid: Dictionary, near_corr: Dictionary, catalog: Array[String], ctx: ThemeCtx) -> void:
	if catalog.is_empty():
		return
	var gate_cells := p.gate_cells()
	var taken: Array[Vector2i] = []
	for e in p.employees:
		taken.append(e["cell"])
	var tags: Array = p.rooms.keys()
	tags.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("room:")) < int(b.trim_prefix("room:")))
	# Edge cells per room: next to a wall, flat, out of the corridors' way.
	var edges: Dictionary = {}
	var order: Array[String] = []
	for tag: String in tags:
		if tag == p.start_room:
			continue
		edges[tag] = _edge_cells(map, p, tag, avoid, near_corr)
		order.append(tag)
	# A shuffled room order, so the first rooms do not hog the few props a floor gets.
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := order[i]
		order[i] = order[j]
		order[j] = t
	var placed: Dictionary = {}
	var round_n := 0
	while p.props.size() < MAX_PROPS and round_n < 3:
		round_n += 1
		for tag in order:
			if p.props.size() >= MAX_PROPS:
				break
			var want := clampi((p.rooms[tag] as Array).size() / 40, 1, 3)
			var edge: Array[Vector2i] = edges[tag]
			if int(placed.get(tag, 0)) >= want or edge.is_empty():
				continue
			# The theme picks the kind (a wine rack in the cellar, the projector in the cinema ...); a room
			# whose theme has none in this catalog takes any kind of the site.
			var themed := RoomThemes.priced_kinds(str(p.room_themes.get(tag, "")), catalog)
			var kinds: Array[String] = []
			var n_placed := int(placed.get(tag, 0))
			if themed.is_empty():
				kinds = catalog.duplicate()
				for i in range(kinds.size() - 1, 0, -1):
					var j := rng.randi_range(0, i)
					var t := kinds[i]
					kinds[i] = kinds[j]
					kinds[j] = t
			else:
				# the theme's first choice half the time, any of its props otherwise
				var first := 0 if rng.randf() < 0.5 else rng.randi_range(0, themed.size() - 1)
				for i in themed.size():
					kinds.append(themed[(n_placed + first + i) % themed.size()])
			var done := false
			for kind in kinds:
				for pose in RoomThemes.priced_poses(ctx, tag, kind, edge):
					var c: Vector2i = pose["cell"]
					var ok := true
					for g in gate_cells:
						if Hex.distance(g, c) < 4:
							ok = false
							break
					if ok:
						for t in taken:
							if Hex.distance(t, c) < PROP_SPACING:
								ok = false
								break
					if not ok:
						continue
					taken.append(c)
					placed[tag] = n_placed + 1
					RoomThemes.commit_priced(ctx, tag, kind, pose)
					p.props.append({"cell": c, "kind": kind, "room": tag, "pos": pose["pos"], "yaw": pose["yaw"],
							"place": pose["place"], "orient": pose["orient"], "foot": pose["foot"]})
					done = true
					break
				if done:
					break


## A room's cells a prop may stand in: flat floor at the room's level next to a wall, out of the start / exit zones and
## the corridors' way (the doors), not at a pit edge or a stair.
static func _edge_cells(map: HexMap, p: SitePlan, tag: String, avoid: Dictionary, near_corr: Dictionary) -> Array[Vector2i]:
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
	return edge


# --- room tags (the notes) ---------------------------------------------------------------------

static func _room_tags(p: SitePlan) -> Array[String]:
	var out: Array[String] = []
	for tag: String in p.rooms:
		out.append(tag)
	out.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("room:")) < int(b.trim_prefix("room:")))
	return out


# --- corridor distance (the van and the mail packages) -----------------------------------------

## Hex distance from each cell to the nearest corridor cell, for the cells within `max_d` of one.
static func _corridor_distance(map: HexMap, max_d: int) -> Dictionary:
	var dist: Dictionary = {}
	var frontier: Array[Vector2i] = []
	for c: Vector2i in map.cells:
		if map.cells[c].tag == "corridor":
			dist[c] = 0
			frontier.append(c)
	for step in range(1, max_d + 1):
		var next: Array[Vector2i] = []
		for c in frontier:
			for dir in Hex.DIRS:
				var n: Vector2i = c + dir
				if not dist.has(n) and map.cells.has(n):
					dist[n] = step
					next.append(n)
		frontier = next
	return dist


# --- packs ----------------------------------------------------------------------------------

static func _plan_packs(run: ContractRun, floor_n: int, p: SitePlan) -> void:
	var gate_cells := p.gate_cells()
	var bonus_hard := int(roundf(run.difficulty * 3.0))
	for tag: String in p.rooms:
		if tag == p.start_room or tag == arrival_room(p):
			continue
		var idx := int(tag.trim_prefix("room:"))
		var budget := ROOM_BUDGET_BASE + ROOM_BUDGET_PER_ROOM * idx + ROOM_BUDGET_PER_FLOOR * (floor_n - 1) + bonus_hard
		# The pests spread outward: denser the closer the room is to a gate.
		var d := 40
		for g in gate_cells:
			d = mini(d, Hex.distance(p.centers[tag], g))
		budget += int(roundf(3.0 * (1.0 - clampf(float(d) / 24.0, 0.0, 1.0))))
		p.pack_budgets[tag] = maxi(2, int(roundf(float(budget) * BUDGET_SCALE)))


static func _block_cells(p: SitePlan) -> void:
	for g in p.gates:
		for n in Hex.range_cells(g["cell"], 2):
			p.blocked[n] = true
	for e in p.employees:
		p.blocked[e["cell"]] = true
	for pr in p.props + p.hazards:
		for n in Hex.range_cells(pr["cell"], 1):
			p.blocked[n] = true
	for nt in p.notes:
		p.blocked[nt["cell"]] = true
	for pk in p.packages:
		p.blocked[pk["cell"]] = true
	# The work van and the cells the crew steps out onto.
	for c: Vector2i in (p.van.get("cells", []) as Array):
		p.blocked[c] = true
	for c: Vector2i in (p.van.get("crew_cells", []) as Array):
		p.blocked[c] = true
	# The elevator's car, doorway and landing (the crew steps out there).
	for c in ElevatorGeo.keep_cells(p.elevator):
		p.blocked[c] = true
	# Walk-blocking decor (racks, bunks, barrels, ...): monsters are not placed inside it.
	for dc in p.decor:
		if not bool(dc["blocks"]):
			continue
		var rad: float = float(dc["block_radius"])
		for bp: Vector2 in (dc["block_points"] as Array):
			for n in Hex.range_cells(ThemeGeo.cell_of(bp), 1):
				if ThemeGeo.hex_dist(bp, n) < rad + 0.1:
					p.blocked[n] = true


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
	var hazards: Array[Actor] = []      ## the explosive props (ExplosiveProp), in plan order
	var decor: Array[Node3D] = []       ## set dressing (DecorProp nodes) and the "ThemeLights" holder
	var monsters: Array[Monster] = []
	var notes: Array[ClueNote] = []
	var packages: Array[Actor] = []     ## every MailPackage box (a stack of 3 is three entries)
	var scouts: Array[Monster] = []     ## goblin scouts (not in `monsters`: no pack's, never a pest kind of their own)
	var beasts: Array[Node3D] = []      ## the monster under each gate's room (HellgateBeast: cosmetic, built on every machine)
	var doors: Array[OfficeDoor] = []   ## the office doors (host-arbitrated objects), in plan order
	var sharks: Array[Shark] = []       ## the pool sharks (not monsters: the client's property), in plan order
	var jockeys: Array[Monster] = []    ## their imp gunners (also in `monsters`: imps, a pest kind)
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
		var gate := Hellgate.spawn(g["cell"], {"difficulty": run.difficulty, "depth": p.floor_number, "origin": bool(g["origin"]), "pest": gate_pest})
		if gate == null:
			continue
		site.gates.append(gate)
		if bool(g["origin"]):
			site.origin_gate = gate
		# the monster under the level round the gate's room (cosmetic: every machine builds it from the seed; it sinks away
		# when its gate closes)
		var beast := HellgateBeast.for_gate(gate, map, p, run.floor_seed(p.floor_number))
		if beast != null:
			site.beasts.append(beast)
	for e in p.employees:
		var emp := Employee.spawn(e["cell"], {"style": str(e["style"]), "name": str(e["name"])})
		if emp != null:
			site.employees.append(emp)
	for pr in p.props:
		var opts := {"site": run.site_type}
		if pr.has("pos"):
			opts["pos"] = pr["pos"]     # back to the wall, facing into the room
			opts["yaw"] = pr["yaw"]
		var prop := PricedProp.spawn(pr["cell"], str(pr["kind"]), opts)
		if prop != null:
			site.props.append(prop)
	HazardPlanner.spawn(run, p, site)
	site.decor = DecorProp.spawn_plan(p)
	NotePlanner.spawn(map, run, p, site)
	PackagePlanner.spawn(p, site)
	_spawn_packs(map, run, p, site, rng)
	ScoutPlanner.spawn(map, p, site)
	SharkPlanner.spawn(run, p, site)
	# The office doors, shut (user, 2026-10-19), last: they are not actors, so no actor's net id moves (NetFloor numbers
	# them after the actors).
	DoorPlanner.spawn(p, site)
	return site


static func _spawn_packs(map: HexMap, run: ContractRun, p: SitePlan, site: Site, rng: RandomNumberGenerator) -> void:
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
		var plan_kinds := biased_composition(int(p.pack_budgets[tag]), rng, run.pest)
		room_count[tag] = _place_kinds(map, free, plan_kinds, rng, site, room_cap(map, p.rooms[tag]))
	# Make sure there is something to exterminate: top up the pest if the dice were unkind.
	if run.pest != "everything":
		var guard := 0
		while site.pest_spawned < PEST_MIN and guard < 6 and not tags.is_empty():
			guard += 1
			var tag: String = tags[rng.randi_range(0, tags.size() - 1)]
			var kinds: Array[String] = [run.pest]
			var cap := room_cap(map, p.rooms[tag]) - int(room_count[tag])
			if cap > 0:
				room_count[tag] = int(room_count[tag]) + _place_kinds(map, rooms_free[tag], kinds, rng, site, cap)


# --- goblin scouts (monster awareness step 2, docs/design/goblin-scout.md §5; planned and spawned by ScoutPlanner) ---

const SCOUT_HARD := 0.6                 ## floor 2 gets a second scout at this difficulty or more


## How many scouts a floor gets (user, 2026-10-18: one, sometimes two): 1 on floor 1, 1 on floor 2 (2 on jobs at
## difficulty 0.6 or more), 2 on floor 3. Fewer when the floor has fewer good corridors.
static func scout_count(run: ContractRun, floor_n: int) -> int:
	if floor_n >= 3:
		return 2
	if floor_n == 2 and run.difficulty >= SCOUT_HARD:
		return 2
	return 1


## MonsterFactory.plan_composition with the pest's weight multiplied (a swarmer is still at most one
## group per pack).
static func biased_composition(budget: int, rng: RandomNumberGenerator, pest: String) -> Array[String]:
	return MonsterFactory.compose(budget, rng, {pest: PEST_WEIGHT_MULT})


## The most monsters one room may hold: one per MonsterFactory.CELLS_PER_MONSTER walkable floor cells (at least 2).
static func room_cap(map: HexMap, room_cells: Array) -> int:
	var walkable := 0
	for c: Vector2i in room_cells:
		var cell := map.get_cell(c)
		if cell != null and cell.type == HexMap.Tile.FLOOR and map.is_walkable_cell(c):
			walkable += 1
	return maxi(2, walkable / MonsterFactory.CELLS_PER_MONSTER)


## Spawn a list of kinds on free walkable cells of one room, spread apart (a swarmer is a clump of its own
## imps), never more than `cap` monsters in all. Returns how many were spawned.
static func _place_kinds(map: HexMap, free: Array[Vector2i], kinds: Array[String], rng: RandomNumberGenerator, site: Site, cap: int = 1 << 20) -> int:
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
static func build(map: HexMap, run: ContractRun, floor_n: int) -> Site:
	var p := plan(map, run, floor_n, PricedProp.catalog(run.site_type))
	return spawn(map, run, p)
