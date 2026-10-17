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
##  - priced props: at most MAX_PROPS (6) a floor, one per room first (rooms in a shuffled order), the kind
##    picked by the room's theme (wine rack in the cellar, projector in the cinema, ...), only on cells next to
##    a wall on flat floor, never within 3 of the start or the exit, never within 2 cells of a corridor (so
##    doors and corridors stay clear), at least PROP_SPACING (4) apart. Each stands BACK TO THE WALL facing into
##    the room (or in a corner facing the centre) with a clear lane in front: SitePlan.props carry pos / yaw;
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
## Clear zones (hex distance): START_CLEAR / EXIT_CLEAR around the start and exit, CORRIDOR_CLEAR around
## any corridor cell.

const START_CLEAR := 3
const EXIT_CLEAR := 3
const CORRIDOR_CLEAR := 2
const GATE_START_CLEAR := 5
const PROP_SPACING := 4
const MAX_PROPS := 6
const PACKAGE_MIN := 4                  ## mail package spots a floor
const PACKAGE_MAX := 6
const PACKAGE_SPACING := 5              ## hex cells between two spots (relaxed on tight floors)
const PACKAGE_DOOR_MIN := 2             ## a spot is at least this many cells from any corridor cell (the doorway stays clear) ...
const PACKAGE_DOOR_MAX := 6             ## ... and at most this many (near a door)
const PACKAGE_STACK_ODDS := [0.58, 0.30]   ## chance of a single box / a stack of two (otherwise three)
const BUDGET_SCALE := 0.7               ## packs are this fraction of the old budgets (less crowded floors)
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

	_plan_gates(map, run, floor_n, p, rng, avoid, near_corr)
	_plan_employees(map, run, floor_n, p, rng, avoid)
	var theme_seed: int = run.floor_seed(floor_n)
	var t0 := Time.get_ticks_usec()
	RoomThemes.assign(p, run.site_type, run.story, floor_n, theme_seed)
	var ctx := ThemeCtx.make(map, p, avoid, near_corr, theme_seed * 919 + floor_n * 13 + 3)
	last_theme_usec = Time.get_ticks_usec() - t0
	_plan_van(map, p, ctx, floor_n)
	t0 = Time.get_ticks_usec()
	_plan_props(map, run, p, rng, avoid, near_corr, catalog, ctx)
	_plan_notes(map, run, floor_n, p, near_corr)
	last_theme_usec += Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	RoomThemes.plan_decor(ctx)
	last_theme_usec += Time.get_ticks_usec() - t0
	_plan_packages(map, run, floor_n, p, ctx)
	_plan_packs(run, floor_n, p)
	_block_cells(p)
	last_plan_usec = Time.get_ticks_usec() - t_start
	return p


## The crew's work van, parked beside the start cell (VanPlan) on the FIRST floor only: the van stays where it parked, so
## floors 2 and 3 have none (p.van stays {}). Planned before the props, the notes, the decor and the packages, which all see
## it as a body and a solid footprint in the start room. It draws no random numbers, so nothing else on the floor moves
## because of it (apart from keeping out of its way).
const VAN_FLOOR := 1


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
## Microseconds the last plan() spent on room themes + set dressing (assign, props placement included, decor); a
## perf probe for tests/test_room_themes.gd.
static var last_theme_usec := 0
static var last_plan_usec := 0


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
		edges[tag] = edge
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
		if VanPlan.near(p.van, ThemeGeo.world(c), 0.9, 1.1, 1.0):
			continue    # not under the van or in front of its door
		var score := (10 - absi(d - 5)) * 2 + (0 if near_corr.has(c) else 5)
		if score > best_score or (score == best_score and _cell_less(c, best)):
			best_score = score
			best = c
	if best != NO_SPOT:
		p.notes.append({"cell": best, "text": str(clues[(floor_n - 1) % clues.size()])})


# --- mail packages ---------------------------------------------------------------------------

## 4-6 stacks of taped-up mail near the room doors. Runs after the decor, so it sees every body already placed
## (gates, employees, notes, priced props, decor and the clear lanes in front of them), and draws from its own
## RNG, so adding or changing it never moves a prop, a piece of decor or a pack.
static func _plan_packages(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan, ctx: ThemeCtx) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = run.floor_seed(floor_n) * 6151 + floor_n * 29 + 11
	var want := rng.randi_range(PACKAGE_MIN, PACKAGE_MAX)
	var door_d := _corridor_distance(map, PACKAGE_DOOR_MAX)
	var tags: Array = ctx.rooms.keys()
	tags.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("room:")) < int(b.trim_prefix("room:")))
	# Candidates: wall-backed poses on open room floor, 2-6 cells from the nearest corridor cell.
	var cands: Array[Dictionary] = []
	for tag: String in tags:
		var room: ThemeCtx.RoomInfo = ctx.rooms[tag]
		for c in room.cells:
			var dd := int(door_d.get(c, -1))
			if dd < PACKAGE_DOOR_MIN or ctx.wall_dirs(c).is_empty() or not room.open.has(c):
				continue
			var kind := "small"
			if rng.randf() >= 0.3:
				kind = "medium" if rng.randf() < 0.65 else "long"
			var dims := PackageModels.size_of(kind)
			var pose := ctx.wall_pose(room, c, dims.x, dims.z, rng.randf_range(-12.0, 12.0))
			var score := absf(float(dd) - 3.0) + rng.randf() * 2.5
			if pose.is_empty() or not _package_fits(ctx, room, door_d, pose["pos"], pose["yaw"], dims.x, dims.z):
				continue
			cands.append({"room": tag, "kind": kind, "pose": pose, "score": score, "cell": c})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["score"]) != float(b["score"]):
			return float(a["score"]) < float(b["score"])
		return _cell_less(a["cell"], b["cell"]))
	var picked: Array[Dictionary] = []
	var per_room: Dictionary = {}
	var used: Dictionary = {}
	for pass_n in 3:
		# one per room, well apart; then two a room, a bit closer; then anything that fits (tight floors)
		var spacing := maxi(2, PACKAGE_SPACING - 2 * pass_n)
		var room_cap := 1 + pass_n
		for i in cands.size():
			var cd := cands[i]
			if picked.size() >= want:
				break
			if used.has(i) or int(per_room.get(cd["room"], 0)) >= room_cap:
				continue
			var ok := true
			for other in picked:
				if Hex.distance(other["cell"], cd["cell"]) < spacing:
					ok = false
					break
			if not ok:
				continue
			used[i] = true
			picked.append(cd)
			per_room[cd["room"]] = int(per_room.get(cd["room"], 0)) + 1
	for cd in picked:
		var pose: Dictionary = cd["pose"]
		var kind: String = cd["kind"]
		var dims := PackageModels.size_of(kind)
		var roll := rng.randf()
		var one := float(PACKAGE_STACK_ODDS[0])
		var stack := 1 if roll < one else (2 if roll < one + float(PACKAGE_STACK_ODDS[1]) else 3)
		var sizes: Array[String] = [kind]
		var twists: Array[float] = [0.0]
		var shifts: Array[Vector2] = [Vector2.ZERO]
		for i in range(1, stack):
			# a box on top is the same size or a small one: never wider than what it sits on
			sizes.append(kind if (kind == "small" or rng.randf() < 0.5) else "small")
			twists.append(rng.randf_range(-11.0, 11.0))
			shifts.append(Vector2(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.03, 0.03)))
		var pos: Vector2 = pose["pos"]
		var yaw: float = pose["yaw"]
		var room: ThemeCtx.RoomInfo = ctx.rooms[cd["room"]]
		ctx.add_body(room, pos, yaw, dims.x, dims.z, -1, "package")
		p.packages.append({"cell": ThemeGeo.cell_of(pos), "pos": pos, "yaw": yaw, "stack": stack, "room": cd["room"],
				"seed": rng.randi() & 0x3FFFFFFF, "sizes": sizes, "twists": twists, "shifts": shifts})


## Does a box footprint stand on open room floor clear of everything already planned (bodies, lanes, the
## start / exit zones, hellgate zones, blocking decor) and out of the doorway (corridor distance >= PACKAGE_DOOR_MIN)?
static func _package_fits(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, door_d: Dictionary, pos: Vector2, yaw: float, w: float, d: float) -> bool:
	for pt in ThemeGeo.foot_points(pos, yaw, w, d):
		var pc := ThemeGeo.cell_of(pt)
		if not room.open.has(pc) or ctx.avoid.has(pc) or ctx.gate_zone.has(pc) or ctx.solid.has(pc) or int(door_d.get(pc, 99)) < PACKAGE_DOOR_MIN:
			return false
	for b in room.bodies:
		if ThemeGeo.overlap(pos, yaw, w, d, b.pos, b.yaw, b.w, b.d, 0.0):
			return false
	return true


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
		if tag == p.start_room:
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
	for pr in p.props:
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
	var decor: Array[Node3D] = []       ## set dressing (DecorProp nodes) and the "ThemeLights" holder
	var monsters: Array[Monster] = []
	var notes: Array[Node3D] = []
	var packages: Array[Actor] = []     ## every MailPackage box (a stack of 3 is three entries)
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
		var opts := {"site": run.site_type}
		if pr.has("pos"):
			opts["pos"] = pr["pos"]     # back to the wall, facing into the room
			opts["yaw"] = pr["yaw"]
		var prop := ContractParts.spawn_prop(pr["cell"], str(pr["kind"]), opts)
		if prop != null:
			site.props.append(prop)
	site.decor = DecorProp.spawn_plan(p)
	for nt in p.notes:
		var note := ClueNote.new()
		note.text = str(nt["text"])
		GameWorld.spawn(note, Hex.to_world(nt["cell"], float(map.get_cell(nt["cell"]).level) + 0.0))
		site.notes.append(note)
	for pk in p.packages:
		site.packages.append_array(_spawn_package(pk))
	_spawn_packs(map, run, p, site, rng)
	return site


## One stack of mail: each box is its own MailPackage, resting on the one below (same or smaller size, a little
## twisted and shifted so it looks stacked by hand).
static func _spawn_package(pk: Dictionary) -> Array[Actor]:
	var out: Array[Actor] = []
	var sizes: Array = pk["sizes"]
	var twists: Array = pk["twists"]
	var shifts: Array = pk["shifts"]
	var base_pos: Vector2 = pk["pos"]
	var base_yaw: float = pk["yaw"]
	var seed_base: int = pk["seed"]
	var below: MailPackage = null
	var lift := 0.0
	for i in int(pk["stack"]):
		var kind: String = sizes[i]
		var shift: Vector2 = shifts[i]
		var m := MailPackage.spawn(base_pos + shift, {"size": kind, "yaw": base_yaw + float(twists[i]), "lift": lift,
				"below": below, "stack": i, "seed": seed_base + i * 7919})
		if m == null:
			break
		out.append(m)
		lift += PackageModels.height_of(kind)
		below = m
	return out


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


## The most monsters one room may hold: one per MonsterFactory.CELLS_PER_MONSTER walkable floor cells (at least 2).
static func room_cap(map: HexMap, room_cells: Array) -> int:
	var walkable := 0
	for c: Vector2i in room_cells:
		var cell := map.get_cell(c)
		if cell != null and cell.type == HexMap.Tile.FLOOR:
			walkable += 1
	return maxi(2, walkable / MonsterFactory.CELLS_PER_MONSTER)


## Spawn a list of kinds on free walkable cells of one room, spread apart (a swarmer is a clump of its own
## imps), never more than `cap` monsters in all. Returns how many were spawned.
static func _place_kinds(map: HexMap, free: Array[Vector2i], kinds: Array[String], rng: RandomNumberGenerator, site: Site, cap: int = 1 << 20) -> int:
	var spawned := 0
	var usable: Array[Vector2i] = []
	for c in free:
		var cell := map.get_cell(c)
		if cell != null and cell.type == HexMap.Tile.FLOOR and not usable.has(c):
			usable.append(c)
	var placed: Array[Vector2i] = []
	for kind in kinds:
		if usable.is_empty() or spawned >= cap:
			break
		var center: Vector2i = MonsterFactory._pick_spread(usable, placed, rng)
		if kind != "swarmer":
			var m := MonsterFactory.spawn(kind, center)
			if m != null:
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
			var sm := MonsterFactory.spawn("swarmer", near[i])
			if sm != null:
				spawned += 1
				site.monsters.append(sm)
				if site.pest == "everything" or site.pest == "swarmer":
					site.pest_spawned += 1
			usable.erase(near[i])
		placed.append(center)
	return spawned


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
