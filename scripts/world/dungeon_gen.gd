class_name DungeonGen
extends RefCounted
## Procedural hex dungeon: rooms at varied heights joined by terraced / stair corridors.
##
## Algorithm (all randomness from one seeded RandomNumberGenerator):
##  1. Scatter 6-9 hex-blob rooms (radius 5-8: round, lobed or bitten shapes) keeping a wide gap between them.
##  2. Prim spanning tree over the room centers, then assign base levels by walking the tree
##     (random deltas, clamped 0..8).
##  3. Carve each tree link (plus 1-2 extra loops) with a turn-penalised A*: tree links three cells
##     wide (a lane on each side of the route), extra loops two wide, and one-wide only for the climb
##     shortcut and at most one short chokepoint. Height along the
##     corridor is a list of events: +-1 terraces, STAIRS cells (rise <= 4, chained) on straight
##     stretches, and on one loop a +-2 climb, which makes it a shortcut that needs climbing.
##  4. Decorate rooms (sparsely, about 3 features a room): platforms (+1), ziggurats (+1..+3 tiers),
##     climbable ledges (+2), blocked pillars (+3..+5) and void pits, all kept one cell away from
##     walls, away from the doors, and out of the middle of the room (FEATURE_CENTER_CLEAR) and the start/exit.
##  5. Ring everything walkable with WALL cells, BFS-validate (start reaches exit and every
##     room without climbing), tag cells, and retry with a derived seed on failure.
##
## THE ELEVATOR (ElevatorGeo, docs/design/elevator-options.md): after the start and the exit room are chosen and before
## the features and the walls, the elevator takes its spot, so the "exit" cell is the LANDING in front of its doors:
##   - "wall" (the default): a 3-cell notch behind a straight, camera-facing stretch of the exit room's wall (nothing
##     walkable behind it); the three cells become floor, so cut_walls() opens the car. If the exit room has no such wall
##     the next-farthest rooms are tried; if none has one, or the notch spoils the layout, the floor gets the free car
##     instead (`fallback` in the record);
##   - "free": the hexagonal car on the exit room's centre cell (door toward the camera), solid sides, no_stand cells.
## The record goes to HexMap.elevator, the jambs / sides to HexMap.solids. It draws no random numbers.
##
## THE SEWER CLUSTER (params "sewer": a seed, SewerCluster.seed_for; docs/design/sewer-concept.md "Phase 3 as built"): once
## the tree and its base levels are made, a WING of the tree (a room and everything beyond it, 2-4 rooms, never the start)
## becomes the cluster, on dice of its own (`srng`). Its rooms share one base level DROP_MIN..DROP_MAX below the room it
## hangs off (at least MIN_LEVEL); its own links are flat (no terraces or stairs: one water level), a loop between two of its
## rooms is a flat loop (never the climb shortcut), a loop from it to the rest of the floor is not cut (the stair is the one
## way in), its rooms get no raised features or pits, and neither the exit nor the elevator goes in it. The tree link into
## it is the SERVICE STAIR: a NARROW hall (one lane, 3.0 between its walls; the user's accepted default, 2026-10-21: its
## head takes the "service" office door, DoorPlanner) of flights of STAIRS cells (at most FLIGHT_MAX a cell) down from the
## room above. The main dice draw
## as they would without the cluster (the flattened links' profiles are drawn and thrown away, the skipped features rolled
## and not built), so the rest of the floor mostly stays as it was. The record goes to HexMap.sewer; SewerPlanner floods it.
## ANY failure (no wing fits, the stair finds no straight run, validation) builds the attempt again without the option, so a
## floor without a cluster is byte for byte the floor it always was (tests/test_sewer_gen.gd, test_golden_floor).
##
## THE LAVA CAVE (params "cave": a seed, LavaSite.seed_for; docs/design/lava-playtest.md "As built"): CaveGen turns a wing of
## 2-3 rooms into rock chambers over a lava plane joined by two-wide bridges, on dice of its own (`crng`): choose() with the
## tree and its levels (the wing's rooms at its root's level, so the hall in is unchanged), carve() once every link is cut
## (the loops into the cave are not cut: its pattern adds its own ways), raise_rim() before cut_walls, finish() after the
## validation (HexMap.cave, HexMap.lava). Its rooms get no features and never the exit. A cave and a sewer cluster are never
## on one floor: generate() tries the floor's cluster first (when it rolled one), then the cave, then plain, attempt by attempt.
##
## LANDINGS (docs/design/hallways.md; the user, 2026-10-26: "Build landings and set pieces only, no hall explosives."): once
## every link is cut, a hall whose route is longer than LANDING_MIN_LEN gets a LANDING partway along it, and one more for
## every LANDING_EVERY beyond that (the stretches between landings are at most about that long): the hall widens to a
## hexagon of LANDING_R + 1 rings (full floor out to LANDING_R, its outer ring cut by the walls) round its HUB, a route cell
## or the neighbour of it away from the camera (the bay opens on the far side, its set piece faces the camera). The centre is
## the route cell nearest the even share of the route, preferring one where the route turns (then the hall changes
## direction there); it is chosen before the hall's height profile is placed, whose terraces and stairs keep off it (and off
## both doors, and apart: _landing_profile; when they cannot, the hall gets none), so a landing is FLAT (the hexagon one
## level, no stairs a ring beyond); its new cells keep LANDING_ROOM_CLEAR from every room and
## a wall's width from every other hall; never on the service stair, the chokepoint, a sewer cluster's or a lava cave's
## halls. It draws NO random numbers (the profile's dice are drawn as ever) and adds cells nothing earlier reads, so the
## rooms, the features, the elevator and every other cell are as without it (only the halls' heights round a landing move):
## the cells are tagged "corridor" (a landing is part of its hall: fog, doors, materials, senses read it as hall) and the
## record goes to HexMap.landings, which PropPlanner.plan_set_pieces reads to stand one priced prop against each landing's
## back wall. `landings` is the dev switch (the gym's "Landings" experiment); a crew's floors (for_run's `shared`) always
## have them, so every machine builds the same floor.
##
## params (all optional): rooms, size, room_radius_min, room_radius_max, gap, loops, wall_height, elevator ("wall" |
## "free"; a contract's floors use for_run(), which passes the job's choice), sewer (a cluster's seed, 0: none),
## sewer_force (dev: try the cluster on every attempt before building without it), cave (a cave's seed, 0: none), cave_gate
## (its far chamber holds a hellgate: the record says so for GatePlanner), cave_force (dev: try the cave on every attempt first),
## landings (bool: overrides the `landings` switch for this floor; for_run passes true for a crew's floors).

const MAX_ATTEMPTS := 24
const MAX_BASE_LEVEL := 8
const KEY_OFF := 128
const KEY_W := 256
const PIT_MARK := -999
const NARROW_CHANCE := 0.3      ## per eligible link, until one narrow chokepoint exists
const NARROW_MAX_LEN := 7       ## only short links may be one hex wide
const DEFAULT_SIZE := 36        ## default radius of the area room centers are scattered in
const DEFAULT_RMIN := 5
const DEFAULT_RMAX := 8
const DEFAULT_GAP := 8          ## minimum empty cells between two rooms
const FEATURE_CENTER_CLEAR := 2 ## no raised feature / pit within this many cells of a room's center
const FEATURE_DOOR_CLEAR := 3   ## ... nor within this many cells of a corridor cell (the doors)
const EXIT_ROOM_TRIES := 3      ## the elevator tries the farthest rooms from the start, this many
const WALL_DOOR_CAP := 10.0     ## a notch's distance from the doors counts up to this many cells
# LANDINGS (see the header; docs/design/hallways.md "As built")
const LANDING_MIN_LEN := 22.0   ## a hall whose route (door to door) is longer than this many world units gets a landing ...
const LANDING_EVERY := 24.0     ## ... and one more for every this many beyond (no stretch of hall between landings longer)
const LANDING_R := 2            ## full floor this many rings round the landing's centre (its next ring is cut by the walls)
const LANDING_ROOM_CLEAR := 4   ## a landing's new cells keep this many cells from every room cell (nothing in a room moves)
const LANDING_SPACING := 8      ## two landings' centres are at least this many cells apart
const LANDING_TURN_PULL := 2.5  ## a centre where the route turns counts this many steps nearer the ideal spot
const LANDING_WINDOW := 0.3     ## the centre is looked for within this share of the spacing either side of the ideal spot
const LANDING_DOOR_CLEAR := 3   ## a hall with landings keeps its terraces and stairs this many steps off both doors
const LANDING_SHIFT := 0.5      ## ... its landings move together up to this share of their spacing to let them fit
const LANDING_EVENT_GAP := 2    ## ... and its terraces and stairs stay this many steps apart

## The dev switch for landings (the gym's "Landings" experiment, docs/design/test-gym.md); solo floors read it, a crew's
## floors always have landings (for_run). On by default.
static var landings := true
## Diagnostics of the last floor built (tools and tests: tests/probe_halls.gd): one row per hall, {a, b, steps, path (world
## units along the route, door to door), straight (door to door), narrow, loop, shortcut, stair, landings}.
static var last_halls: Array[Dictionary] = []
## Microseconds the landings pass has taken, summed over every attempt since it was last zeroed (a perf probe).
static var landing_usec := 0

enum Ev { TERRACE, CLIMB, STAIRS }
enum Feature { PLATFORM, ZIGGURAT, LEDGE, PILLAR, PIT }


## Generate a dungeon. Deterministic per seed (and params).
static func generate(seed: int, params: Dictionary = {}) -> HexMap:
	# A lava cave asked for (CaveGen, LavaSite): each attempt tries the floor's sewer cluster first when it rolled one (one set
	# piece a floor, and a cluster floor stays the floor it was), then the cave, then the plain floor; so a floor that ends up
	# without a cave is exactly the floor these params without "cave" give.
	if int(params.get("cave", 0)) != 0:
		var no_cave := params.duplicate()
		for k in CAVE_KEYS:
			no_cave.erase(k)
		var cave_only := params.duplicate()
		cave_only.erase("sewer")
		cave_only.erase("sewer_force")
		var plain_floor := no_cave.duplicate()
		plain_floor.erase("sewer")
		plain_floor.erase("sewer_force")
		if bool(params.get("cave_force", false)):
			for attempt in MAX_ATTEMPTS:   # (dev, --lava-floor: any attempt with a cave first)
				var mf := _attempt(_attempt_seed(seed, attempt), cave_only)
				if mf != null:
					return mf
		for attempt in MAX_ATTEMPTS:
			var s := _attempt_seed(seed, attempt)
			if int(no_cave.get("sewer", 0)) != 0:
				var ms := _attempt(s, no_cave)
				if ms != null:
					return ms
			var mc := _attempt(s, cave_only)
			if mc != null:
				return mc
			var mp := _attempt(s, plain_floor)
			if mp != null:
				return mp
		push_warning("DungeonGen: no valid map for seed %d after %d attempts; using fallback" % [seed, MAX_ATTEMPTS])
		return _fallback()
	# A sewer cluster asked for: each attempt tries it first and, if anything fails, builds the attempt without it, so a floor
	# that ends up without one is exactly the floor these params without "sewer" give.
	var sewer := int(params.get("sewer", 0)) != 0
	var plain := params
	if params.has("sewer") or params.has("sewer_force"):
		plain = params.duplicate()
		plain.erase("sewer")
		plain.erase("sewer_force")
	if sewer and bool(params.get("sewer_force", false)):
		for attempt in MAX_ATTEMPTS:   # (dev, --sewer-floor: any attempt with a cluster first)
			var mf := _attempt(_attempt_seed(seed, attempt), params)
			if mf != null:
				return mf
	for attempt in MAX_ATTEMPTS:
		var s := _attempt_seed(seed, attempt)
		if sewer:
			var ms := _attempt(s, params)
			if ms != null:
				return ms
		var m := _attempt(s, plain)
		if m != null:
			return m
	push_warning("DungeonGen: no valid map for seed %d after %d attempts; using fallback" % [seed, MAX_ATTEMPTS])
	return _fallback()


const CAVE_KEYS: Array[String] = ["cave", "cave_gate", "cave_force"]


## How many landings a hall `length` world units long (door to door along its route) gets: none up to LANDING_MIN_LEN,
## then one, and one more for every LANDING_EVERY beyond.
static func landing_count(length: float) -> int:
	if length <= LANDING_MIN_LEN:
		return 0
	return 1 + int(floorf((length - LANDING_MIN_LEN) / LANDING_EVERY))


static func _attempt_seed(seed: int, attempt: int) -> int:
	return seed if attempt == 0 else ((seed * 1103515245 + attempt * 12345 + 1) & 0x7fffffff)


## One attempt: the layout of seed `s`, or null.
static func _attempt(s: int, params: Dictionary) -> HexMap:
	var b := Builder.new(s, params)
	var m: HexMap = b.build()
	if m == null and b.notched:
		# the notch spoiled this layout: the same layout with the free-standing car (the documented fallback)
		var free := params.duplicate()
		free["elevator"] = ElevatorGeo.PLACE_FREE
		free["fallback"] = true
		b = Builder.new(s, free)
		m = b.build()
	return m


## Floor `floor_n` of a contract: its floor seed and the job's elevator placement (every floor of a job alike), and a sewer
## cluster when the floor rolls one (SewerCluster.seed_for). `shared`: a crew's run, which rolls the same cluster as a
## solo run since the sewer is networked (SewerCluster.NETWORKED, sewer phase 2).
static func for_run(run: ContractRun, floor_n: int, shared: bool = false) -> HexMap:
	var params := {"elevator": run.elevator_place}
	if shared:
		params["landings"] = true   # (a crew's floors always have landings: the dev switch is one machine's, solo only)
	var sewer := SewerCluster.seed_for(run, floor_n, shared)
	if sewer != 0:
		params["sewer"] = sewer
		if SewerCluster.force:
			params["sewer_force"] = true
	# a lava cave (LavaSite), on a floor that rolled no sewer cluster (one set piece a floor, and a cluster floor stays the floor
	# it was; so a cave floor costs at most two attempts, the cave's and the plain one); --lava-floor forces one anyway (after
	# the cluster, generate()), --sewer-floor alone keeps its clusters
	var cave := LavaSite.seed_for(run, floor_n, shared)
	if cave != 0 and (LavaSite.force or (not SewerCluster.force and sewer == 0)):
		params["cave"] = cave
		params["cave_gate"] = LavaSite.needs_gate(run, floor_n)
		if LavaSite.force:
			params["cave_force"] = true
	return generate(run.floor_seed(floor_n), params)


## Tiny always-valid map (a lone room with stairs), used only if every attempt fails. It has no elevator.
static func _fallback() -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 5):
		m.set_cell(c, 0).tag = "room:0"
	m.set_stairs(Vector2i(3, 0), 0, 0, 3)
	m.get_cell(Vector2i(3, 0)).tag = "corridor"
	for c in Hex.range_cells(Vector2i.ZERO, 6):
		if not m.has_cell(c):
			m.set_cell(c, 6, HexMap.Tile.WALL)
	m.get_cell(Vector2i(-2, 0)).tag = "start"
	m.get_cell(Vector2i(0, 3)).tag = "exit"
	m.cut_walls()
	return m


class Room:
	var index: int = 0
	var center: Vector2i = Vector2i.ZERO
	var cells: Dictionary = {}          ## Vector2i -> true
	var boundary: Array[Vector2i] = []
	var level: int = 0
	var extent: int = 0                 ## max distance from center to any cell


class Link:
	var a: int = 0
	var b: int = 0
	var shortcut: bool = false
	var length: int = 0                 ## steps from room a to room b along the corridor
	var door_a: Vector2i = Vector2i.ZERO
	var door_b: Vector2i = Vector2i.ZERO
	var loop := false
	var narrow := false                 ## three cells across (the route only); else four (route and lane)
	var route: Array[Vector2i] = []     ## [door_a, the route cells .., door_b]
	var lanes: Array[Vector2i] = []     ## a tree link's lane cells (beside the route)
	var cells: Array[Vector2i] = []     ## every corridor cell it added
	var centres: Array[int] = []        ## where its landings were meant to go (route indices; its profile kept them flat)


class Step:
	var level: int = 0
	var stairs: bool = false
	var rise: int = 0
	var dir: int = 0


class Builder:
	extends RefCounted

	var rng := RandomNumberGenerator.new()
	var p_rooms: int = 0
	var p_size: int = DEFAULT_SIZE
	var p_rmin: int = DEFAULT_RMIN
	var p_rmax: int = DEFAULT_RMAX
	var p_gap: int = DEFAULT_GAP
	var p_loops: int = -1
	var p_wall: int = 3

	var map := HexMap.new()
	var rooms: Array[Room] = []
	var room_of: Dictionary = {}        ## cell -> room index
	var links: Array[Link] = []
	var corr_cells: Dictionary = {}     ## every corridor cell
	var corr_buffer: Dictionary = {}    ## cells within 1 of a corridor (no other corridor's cell may go there)
	var corr_buffer2: Dictionary = {}   ## cells within 2 of a corridor (no other corridor's ROUTE may go there)
	var near_room: Dictionary = {}      ## cell -> bitmask of the rooms within 2 cells of it
	var pits: Dictionary = {}
	var tree_adj: Array = []
	var stairs_count := 0
	var climb_features := 0
	var start: Vector2i = Vector2i.ZERO
	var exit_cell: Vector2i = Vector2i.ZERO
	var narrow_used := false
	var p_elevator := ElevatorGeo.PLACE_WALL
	var p_fallback := false
	var exit_order: Array[int] = []     ## room indices by walking distance from the start, farthest first (start room left out)
	var elevator: Dictionary = {}       ## the elevator's record (ElevatorGeo)
	var notched := false                ## the wall notch was cut (a failure afterwards is retried with the free car)
	# the sewer cluster (see the header): its own dice, its rooms, their level and the stair link into them
	var p_sewer := 0
	var srng := RandomNumberGenerator.new()
	var cluster: Dictionary = {}        ## room index -> true
	var cluster_level := 0
	var stair_pair := Vector2i(-1, -1)  ## (the room above, the cluster's first room): the service stair's tree link
	var orig_level: Array[int] = []     ## every room's base level before the cluster was lowered (the burnt profiles)
	# the lava cave (CaveGen, scripts/world/lava/cave_gen.gd): its own dice, its rooms, and what the pass works out
	var p_cave := 0
	var p_cave_gate := false
	var crng := RandomNumberGenerator.new()
	var cave: Dictionary = {}           ## room index -> true
	var cave_info: Dictionary = {}
	# the landings (see the header): on or off for this floor, and what the pass made
	var p_landings := true
	var landing_recs: Array[Dictionary] = []
	var landings_of: Dictionary = {}    ## link index -> how many landings it got

	func _init(s: int, params: Dictionary) -> void:
		rng.seed = s
		p_landings = bool(params.get("landings", DungeonGen.landings))
		p_sewer = int(params.get("sewer", 0))
		srng.seed = (p_sewer * 31 + s) & 0x7fffffff
		p_cave = int(params.get("cave", 0))
		p_cave_gate = bool(params.get("cave_gate", false))
		crng.seed = (p_cave * 37 + s * 3 + 1) & 0x7fffffff
		p_rooms = int(params.get("rooms", 0))
		p_size = int(params.get("size", DEFAULT_SIZE))
		p_rmin = int(params.get("room_radius_min", DEFAULT_RMIN))
		p_rmax = maxi(p_rmin, int(params.get("room_radius_max", DEFAULT_RMAX)))
		p_gap = int(params.get("gap", DEFAULT_GAP))
		p_loops = int(params.get("loops", -1))
		p_wall = int(params.get("wall_height", 3))
		p_elevator = str(params.get("elevator", ElevatorGeo.PLACE_WALL))
		p_fallback = bool(params.get("fallback", false))

	# ------------------------------------------------------------------ build

	func build() -> HexMap:
		if not _place_rooms():
			return null
		if not _plan_and_carve():
			return null
		if p_landings:
			var t0 := Time.get_ticks_usec()
			_add_landings()   # (no dice; nothing before it moves, and nothing after it reads its cells: see the header)
			DungeonGen.landing_usec += Time.get_ticks_usec() - t0
		_choose_start_exit()
		if not _place_elevator():
			return null
		_decorate()
		_add_walls()
		if not cave.is_empty():
			CaveGen.raise_rim(self)
		map.cut_walls()
		_add_elevator()
		if not _validate_and_tag():
			return null
		if not cluster.is_empty():
			_sewer_record()
		if not cave.is_empty():
			CaveGen.finish(self)
		map.landings = landing_recs
		DungeonGen.last_halls = _hall_stats()
		return map

	# ------------------------------------------------------------------ rooms

	func _place_rooms() -> bool:
		var want: int = p_rooms if p_rooms > 0 else rng.randi_range(6, 9)
		var buffer := {}
		var tries := 0
		while rooms.size() < want and tries < 900:
			tries += 1
			var center := _random_cell(p_size)
			var cells := _room_shape(center, rng.randi_range(p_rmin, p_rmax))
			var clash := false
			for c in cells:
				if buffer.has(c):
					clash = true
					break
			if clash:
				continue
			var room := Room.new()
			room.index = rooms.size()
			room.center = center
			room.cells = cells
			for c in cells:
				room.extent = maxi(room.extent, Hex.distance(center, c))
				for d in Hex.DIRS:
					if not cells.has(c + d):
						room.boundary.append(c)
						break
			for bc in room.boundary:
				for n in Hex.range_cells(bc, p_gap - 1):
					buffer[n] = true
			for c in cells:
				room_of[c] = room.index
			rooms.append(room)
		for room in rooms:
			for bc in room.boundary:
				for n in Hex.range_cells(bc, 2):
					near_room[n] = int(near_room.get(n, 0)) | (1 << room.index)
		return rooms.size() >= mini(want, 5)

	func _random_cell(radius: int) -> Vector2i:
		while true:
			var c := Vector2i(rng.randi_range(-radius, radius), rng.randi_range(-radius, radius))
			if Hex.distance(c, Vector2i.ZERO) <= radius:
				return c
		return Vector2i.ZERO

	## Round, lobed (merged blobs) or bitten hex blob around center.
	func _room_shape(center: Vector2i, radius: int) -> Dictionary:
		var cells := {}
		var style := rng.randi_range(0, 3)
		if style == 0:
			for c in Hex.range_cells(center, radius):
				cells[c] = true
		elif style <= 2:
			var main := maxi(4, radius - 1)
			for c in Hex.range_cells(center, main):
				cells[c] = true
			for _i in rng.randi_range(1, 2):
				var lc: Vector2i = center + Hex.DIRS[rng.randi_range(0, 5)] * rng.randi_range(2, main)
				var lr := rng.randi_range(2, maxi(2, mini(4, radius - 1)))
				for c in Hex.range_cells(lc, lr):
					cells[c] = true
		else:
			for c in Hex.range_cells(center, radius):
				cells[c] = true
			for _i in rng.randi_range(5, 12):
				var cand: Array[Vector2i] = []
				for c in cells:
					if Hex.distance(c, center) <= 2:
						continue   # the middle stays whole (the start / exit stand there)
					var inside := 0
					for d in Hex.DIRS:
						if cells.has(c + d):
							inside += 1
					if inside >= 4 and inside < 6:
						cand.append(c)
				if cand.is_empty():
					break
				cells.erase(cand[rng.randi_range(0, cand.size() - 1)])
		return _open_shape(_component(cells, center), center)

	## Morphological opening: the cells with all six neighbours in the shape (the ones that stay FULL once the
	## walls run through the boundary cells' centers), the part of them connected to the center, grown back by
	## one ring. Every boundary cell then touches a full cell: no one-cell peninsula or neck turns into a sliver.
	func _open_shape(cells: Dictionary, center: Vector2i) -> Dictionary:
		var inner := {}
		for c: Vector2i in cells:
			var all_in := true
			for d in Hex.DIRS:
				if not cells.has(c + d):
					all_in = false
					break
			if all_in:
				inner[c] = true
		if not inner.has(center):
			return cells
		var out := {}
		for c: Vector2i in _component(inner, center):
			out[c] = true
			for d in Hex.DIRS:
				out[c + d] = true
		return out

	func _component(cells: Dictionary, from: Vector2i) -> Dictionary:
		var seen := {from: true}
		var queue: Array[Vector2i] = [from]
		var i := 0
		while i < queue.size():
			var c: Vector2i = queue[i]
			i += 1
			for d in Hex.DIRS:
				var n: Vector2i = c + d
				if cells.has(n) and not seen.has(n):
					seen[n] = true
					queue.append(n)
		return seen

	# ------------------------------------------------------------------ links

	func _plan_and_carve() -> bool:
		var n := rooms.size()
		# Prim spanning tree; levels are assigned as rooms join the tree.
		rooms[0].level = rng.randi_range(1, 4)
		var in_tree: Array[int] = [0]
		var deltas := [-4, -3, -2, -2, -1, -1, 0, 1, 1, 2, 2, 3, 4, 5]
		var tree_pairs: Array[Vector2i] = []
		tree_adj.clear()
		for _i in n:
			tree_adj.append([])
		while in_tree.size() < n:
			var best := Vector2i(-1, -1)
			var best_d := 1 << 30
			for i in in_tree:
				for j in n:
					if in_tree.has(j):
						continue
					var d := Hex.distance(rooms[i].center, rooms[j].center)
					if d < best_d:
						best_d = d
						best = Vector2i(i, j)
			var parent := rooms[best.x]
			rooms[best.y].level = clampi(parent.level + deltas[rng.randi_range(0, deltas.size() - 1)], 0, MAX_BASE_LEVEL)
			in_tree.append(best.y)
			tree_pairs.append(best)
			tree_adj[best.x].append(best.y)
			tree_adj[best.y].append(best.x)
		var lo := 99
		var hi := -99
		var big_gap := false
		for r in rooms:
			lo = mini(lo, r.level)
			hi = maxi(hi, r.level)
		for pr in tree_pairs:
			if absi(rooms[pr.x].level - rooms[pr.y].level) >= 3:
				big_gap = true
		if hi - lo < 4 or not big_gap:
			return false
		for r in rooms:
			orig_level.append(r.level)
		if p_sewer != 0 and not _choose_cluster():
			return false   # (no wing fits: generate() builds this attempt without the option)
		if p_cave != 0 and not CaveGen.choose(self):
			return false   # (no wing fits a cave: likewise)
		for r in rooms:
			for c in r.cells:
				map.set_cell(c, r.level)

		for pr in tree_pairs:
			if not _carve(pr.x, pr.y, false):
				return false

		# Extra loops: the first is the climb shortcut.
		var loops: int = p_loops if p_loops >= 0 else rng.randi_range(1, 2)
		var cand := _loop_candidates()
		var made := 0
		for pr in cand:
			if made >= loops:
				break
			if not cluster.is_empty() and (cluster.has(pr.x) or cluster.has(pr.y)):
				# the stair is the one way into the cluster, and the climb shortcut is never flooded
				if cluster.has(pr.x) != cluster.has(pr.y) or made == 0:
					continue
			if cave.has(pr.x) or cave.has(pr.y):
				continue   # (a cave's own extra ways are its pattern's: CaveGen.carve)
			if _carve(pr.x, pr.y, made == 0, true):
				made += 1
		if p_cave != 0 and not CaveGen.carve(self):
			return false
		return true

	# ------------------------------------------------------------------ the sewer cluster

	## Pick the cluster (see the header): a wing of 2-4 rooms hanging off a room high enough for the stair, on the cluster's
	## own dice. Lowers its rooms to one level. False when no wing fits.
	func _choose_cluster() -> bool:
		var n := rooms.size()
		var parent: Array[int] = []
		for _i in n:
			parent.append(-1)
		var order: Array[int] = [0]
		var seen := {0: true}
		var qi := 0
		while qi < order.size():
			var c: int = order[qi]
			qi += 1
			for nb: int in tree_adj[c]:
				if not seen.has(nb):
					seen[nb] = true
					parent[nb] = c
					order.append(nb)
		var cands: Array[int] = []
		for v in range(1, n):
			var wing := _wing(v, parent)
			if wing.size() < SewerCluster.MIN_ROOMS or wing.size() > SewerCluster.MAX_ROOMS or n - wing.size() < 3:
				continue
			if rooms[parent[v]].level - SewerCluster.DROP_MIN < SewerCluster.MIN_LEVEL:
				continue
			cands.append(v)
		if cands.is_empty():
			return false
		var root: int = cands[srng.randi_range(0, cands.size() - 1)]
		var up: int = parent[root]
		var drop := srng.randi_range(SewerCluster.DROP_MIN, SewerCluster.DROP_MAX)
		cluster_level = maxi(SewerCluster.MIN_LEVEL, rooms[up].level - drop)
		for r in _wing(root, parent):
			cluster[r] = true
			rooms[r].level = cluster_level
		stair_pair = Vector2i(up, root)
		return true

	## Room v and every room beyond it (away from the start) in the tree.
	func _wing(v: int, parent: Array[int]) -> Array[int]:
		var out: Array[int] = [v]
		var i := 0
		while i < out.size():
			for nb: int in tree_adj[out[i]]:
				if nb != parent[out[i]] and not out.has(nb):
					out.append(nb)
			i += 1
		return out

	## The cluster for HexMap.sewer: its rooms, level and seed, the service stair, its own halls, and every doorway of its
	## rooms (SewerPlanner, GatorPlanner).
	func _sewer_record() -> void:
		var tags: Array[String] = []
		var idx: Array = cluster.keys()
		idx.sort()
		for i: int in idx:
			tags.append("room:%d" % i)
		var halls: Array = []
		var stair := {}
		var doors: Array[Vector2i] = []
		for l in links:
			var ia := cluster.has(l.a)
			var ib := cluster.has(l.b)
			if not ia and not ib:
				continue
			doors.append(l.door_a)
			doors.append(l.door_b)
			var cells: Array[Vector2i] = l.cells.duplicate()
			cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
			if ia and ib:
				halls.append({"a": "room:%d" % l.a, "b": "room:%d" % l.b, "door_a": l.door_a, "door_b": l.door_b,
						"route": l.route.duplicate(), "lanes": l.lanes.duplicate(), "cells": cells, "narrow": l.narrow, "loop": l.loop})
			else:
				var inside_a := ia
				stair = {"room": "room:%d" % (l.a if inside_a else l.b), "from": "room:%d" % (l.b if inside_a else l.a),
						"door": l.door_a if inside_a else l.door_b, "door_up": l.door_b if inside_a else l.door_a, "cells": cells,
						"narrow": l.narrow}
		map.sewer = {"seed": p_sewer, "level": cluster_level, "rooms": tags, "stair": stair, "halls": halls, "all_doors": doors}

	## Non-tree room pairs sorted so far-apart-in-tree but close-in-space pairs come first.
	func _loop_candidates() -> Array[Vector2i]:
		var n := rooms.size()
		var scored: Array = []
		for i in n:
			var hops := _tree_hops(i)
			for j in range(i + 1, n):
				if tree_adj[i].has(j) or hops[j] < 2:
					continue
				var d := Hex.distance(rooms[i].center, rooms[j].center)
				if d > p_size + 8:
					continue
				scored.append([ (0 if hops[j] >= 3 else 1000) + d, Vector2i(i, j) ])
		scored.sort_custom(func(x, y): return x[0] < y[0])
		var out: Array[Vector2i] = []
		for s in scored:
			out.append(s[1])
		return out

	func _tree_hops(from: int) -> Array:
		var hops: Array = []
		for _i in rooms.size():
			hops.append(-1)
		hops[from] = 0
		var queue: Array[int] = [from]
		var qi := 0
		while qi < queue.size():
			var c: int = queue[qi]
			qi += 1
			for nb in tree_adj[c]:
				if hops[nb] == -1:
					hops[nb] = hops[c] + 1
					queue.append(nb)
		return hops

	# ------------------------------------------------------------------ corridors

	func _key(c: Vector2i, d: int) -> int:
		return ((c.x + KEY_OFF) * KEY_W + (c.y + KEY_OFF)) * 6 + d

	## Extra cost to enter c with a corridor's ROUTE, or -1 if it may not. A route keeps 3 cells from other rooms
	## and other corridors, so the ring of cells _fill() adds around it (its walls run through their centers)
	## never touches them.
	func _penalty(c: Vector2i, a_idx: int, b_idx: int) -> int:
		if room_of.has(c) or corr_buffer2.has(c) or map.has_cell(c) or pits.has(c):
			return -1
		if Hex.distance(c, Vector2i.ZERO) > p_size + 14:
			return -1
		if int(near_room.get(c, 0)) & ~((1 << a_idx) | (1 << b_idx)) != 0:
			return -1
		var pen := 0
		for d in Hex.DIRS:
			var ri: int = room_of.get(c + d, -1)
			if ri == -1:
				continue
			if ri != a_idx and ri != b_idx:
				return -1
			pen = 25
		return pen

	## A* with a turn penalty from room a to room b. Returns [door_a, p1..pn, door_b] or [].
	func _route(a: Room, b: Room) -> Array[Vector2i]:
		var empty: Array[Vector2i] = []
		var srcs: Array[Vector2i] = []
		for src in a.boundary:
			if _door_ok(src, a.index, b.index):
				srcs.append(src)
		var bc: Vector2i = b.center
		srcs.sort_custom(func(x, y): return Hex.distance(x, bc) < Hex.distance(y, bc))
		if srcs.size() > 10:
			srcs.resize(10)
		var dist := {}
		var came := {}
		var start_of := {}
		var buckets: Array = []
		for src in srcs:
			for d in 6:
				var nc: Vector2i = src + Hex.DIRS[d]
				var pen := _penalty(nc, a.index, b.index)
				if pen < 0:
					continue
				var k := _key(nc, d)
				var g := 10 + pen
				if g < dist.get(k, 1 << 30):
					dist[k] = g
					came[k] = -1
					start_of[k] = src
					_push(buckets, g + _h(nc, b), k)
		var f := 0
		while f < buckets.size():
			var bucket: Array = buckets[f]
			var bi := 0
			while bi < bucket.size():
				var k: int = bucket[bi]
				bi += 1
				var d := k % 6
				var idx := k / 6
				var c := Vector2i(idx / KEY_W - KEY_OFF, idx % KEY_W - KEY_OFF)
				var g: int = dist[k]
				if g + _h(c, b) != f:
					continue  # stale entry
				var door := _touching(c, d, b.index, a.index)
				if door != Vector2i(1 << 20, 0):
					var path: Array[Vector2i] = []
					var cur := k
					while cur != -1:
						var ci: int = cur / 6
						path.push_front(Vector2i(ci / KEY_W - KEY_OFF, ci % KEY_W - KEY_OFF))
						var prev: int = came[cur]
						if prev == -1:
							path.push_front(start_of[cur])
						cur = prev
					path.append(door)
					return path
				for turn in [0, 1, -1, 2, -2]:
					var nd: int = posmod(d + turn, 6)
					var nc: Vector2i = c + Hex.DIRS[nd]
					var pen := _penalty(nc, a.index, b.index)
					if pen < 0:
						continue
					var cost: int = g + 10 + pen + (0 if turn == 0 else (6 if absi(turn) == 1 else 12))
					var nk := _key(nc, nd)
					if cost < dist.get(nk, 1 << 30):
						dist[nk] = cost
						came[nk] = k
						_push(buckets, cost + _h(nc, b), nk)
			f += 1
		return empty

	## May a corridor cell that is not on the route (a lane, a fill cell) go at c? It must be empty and keep one
	## cell (a wall) between itself and other rooms and corridors.
	func _fill_ok(c: Vector2i, a_idx: int, b_idx: int) -> bool:
		if room_of.has(c) or corr_buffer.has(c) or map.has_cell(c) or pits.has(c):
			return false
		if Hex.distance(c, Vector2i.ZERO) > p_size + 16:
			return false
		for d in Hex.DIRS:
			var ri: int = room_of.get(c + d, -1)
			if ri != -1 and ri != a_idx and ri != b_idx:
				return false
		return true

	## Can room cell `door` be a doorway? Its cells outside the room get filled (so the door cell is FULL and the
	## corridor joins the room's floor through a clean opening), so they must be free.
	func _door_ok(door: Vector2i, a_idx: int, b_idx: int) -> bool:
		var own: int = room_of.get(door, -1)
		for d in Hex.DIRS:
			var x: Vector2i = door + d
			if room_of.get(x, -1) == own:
				continue
			if not _fill_ok(x, a_idx, b_idx):
				return false
		return true

	func _push(buckets: Array, f: int, k: int) -> void:
		while buckets.size() <= f:
			buckets.append([])
		buckets[f].append(k)

	func _h(c: Vector2i, b: Room) -> int:
		return maxi(0, Hex.distance(c, b.center) - b.extent - 1) * 10

	## A cell of room `idx` adjacent to c that can be a doorway (preferring straight ahead), or a sentinel.
	func _touching(c: Vector2i, d: int, idx: int, other: int) -> Vector2i:
		var ahead: Vector2i = c + Hex.DIRS[d]
		if room_of.get(ahead, -1) == idx and _door_ok(ahead, other, idx):
			return ahead
		for dd in Hex.DIRS:
			if room_of.get(c + dd, -1) == idx and _door_ok(c + dd, other, idx):
				return c + dd
		return Vector2i(1 << 20, 0)

	func _carve(ai: int, bi: int, shortcut: bool, loop: bool = false) -> bool:
		var ra := rooms[ai]
		var rb := rooms[bi]
		var S := _route(ra, rb)
		if S.size() < 3:
			return false
		var steps: Array = []
		var inside := (cluster.has(ai) and cluster.has(bi)) or (cave.has(ai) and cave.has(bi))
		var stair := stair_pair == Vector2i(ai, bi) or stair_pair == Vector2i(bi, ai)
		# the landings' spots on a long hall (see the header): its terraces and stairs keep off them, so each sits on a flat
		# stretch (the profile's dice are the same either way; only where its events go moves)
		var centres: Array[int] = []
		if p_landings and not inside and not stair and not cluster.has(ai) and not cluster.has(bi) and not cave.has(ai) and not cave.has(bi):
			centres = _landing_centres(S)
		if inside or stair:
			# (the dice this link's profile draws without the cluster, drawn and thrown away: the floor around stays the same)
			_profile(S, orig_level[ai], orig_level[bi], shortcut)
			steps = _flat_steps(S.size() - 2, ra.level) if inside else _stair_profile(S, ra.level, rb.level)
		elif not centres.is_empty():
			var lp := _landing_profile(S, ra.level, rb.level, _profile_events(ra.level, rb.level, shortcut), centres)
			steps = lp[0]
			centres = lp[1]
		else:
			steps = _profile(S, ra.level, rb.level, shortcut)
		if steps.is_empty():
			return false
		var n := S.size() - 2
		var added: Array[Vector2i] = []
		for i in range(1, n + 1):
			_put(S[i], steps[i - 1])
			added.append(S[i])
		# Walls run through the centers of a corridor's outer cells, so the route (and, on a tree link, one lane
		# beside it) is the CORE: every core cell gets all six neighbours (_fill), which makes it a full cell and
		# the corridor's floor one clean strip. Tree links: route + lane = 4 cells across, 4.5 wide between the
		# walls. Extra loops, the climb shortcut and the chokepoint: route only = 3 across, 3.0 wide.
		var narrow := shortcut or loop
		if not narrow and not narrow_used and n <= NARROW_MAX_LEN and rng.randf() < NARROW_CHANCE:
			narrow = true
			narrow_used = true
		if stair:
			narrow = true   # the service stair is always one lane wide (user, 2026-10-21); the main dice drew as without it
		var core: Array[Vector2i] = []
		var core_idx: Dictionary = {}     # core cell -> index into S (0 and n + 1 are the doors)
		for i in n + 2:
			core.append(S[i])
			core_idx[S[i]] = i
		var lanes: Array[Vector2i] = []
		if not narrow:
			for i in range(1, n + 1):
				var lane: Vector2i = S[i] + Hex.DIRS[posmod(Hex.dir_to(S[i], S[i + 1]) + 1, 6)]
				if core_idx.has(lane):
					continue
				if not map.has_cell(lane):
					if not _fill_ok(lane, ai, bi):
						continue
					_put(lane, steps[i - 1])
					added.append(lane)
				elif not corr_cells.has(lane) and not added.has(lane):
					continue   # a room cell
				core.append(lane)
				core_idx[lane] = i
				lanes.append(lane)
		added.append_array(_fill(core, core_idx, steps, ra, rb, ai, bi))
		for c in added:
			map.get_cell(c).tag = "corridor"
			corr_cells[c] = true
		for c in added:
			for nb in Hex.range_cells(c, 2):
				corr_buffer2[nb] = true
				if Hex.distance(nb, c) <= 1:
					corr_buffer[nb] = true
		var link := Link.new()
		link.a = ai
		link.b = bi
		link.shortcut = shortcut
		link.length = n + 1
		link.door_a = S[0]
		link.door_b = S[n + 1]
		link.loop = loop
		link.narrow = narrow
		link.route = S
		link.lanes = lanes
		link.cells = added
		link.centres = centres
		links.append(link)
		if shortcut:
			climb_features += 1
		return true

	## One corridor cell from a height-profile step (a flat cell or a staircase).
	func _put(c: Vector2i, st: Step) -> void:
		if st.stairs:
			map.set_stairs(c, st.level, st.dir, st.rise)
			stairs_count += 1
		else:
			map.set_cell(c, st.level)

	## Give every core cell all six neighbours: the empty ones become corridor floor that copies the step of the
	## EARLIEST core cell it touches (so a cell beside a staircase is its twin, one behind it is the flat floor
	## before it). Door cells (indices 0 and n + 1) copy their room's level. Returns the cells added.
	func _fill(core: Array[Vector2i], core_idx: Dictionary, steps: Array, ra: Room, rb: Room, ai: int, bi: int) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		var n := steps.size()
		for k in core:
			for d in Hex.DIRS:
				var x: Vector2i = k + d
				if map.has_cell(x) or not _fill_ok(x, ai, bi):
					continue
				var idx := 1 << 20
				for dd in Hex.DIRS:
					if core_idx.has(x + dd):
						idx = mini(idx, int(core_idx[x + dd]))
				var st := Step.new()
				if idx <= 0:
					st.level = ra.level
				elif idx > n:
					st.level = rb.level
				else:
					st = steps[idx - 1]
				_put(x, st)
				out.append(x)
		return out

	func _straight(S: Array[Vector2i], i: int) -> bool:
		return Hex.dir_to(S[i - 1], S[i]) == Hex.dir_to(S[i], S[i + 1])

	## Height profile for cells S[1..n]; [] when the events cannot be placed.
	func _profile(S: Array[Vector2i], la: int, lb: int, shortcut: bool) -> Array:
		return _place_events(S, la, lb, _profile_events(la, lb, shortcut))

	## The events of a link's height profile from la to lb ([kind, delta], in order): its dice.
	func _profile_events(la: int, lb: int, shortcut: bool) -> Array:
		var diff := lb - la
		var events: Array = []   # [kind, delta]
		var rest := diff
		var climb_ev: Array = []
		var bump := false
		if shortcut:
			var cd := 2
			if diff <= -2:
				cd = -2
			bump = absi(diff) < 2
			climb_ev = [Ev.CLIMB, cd]
			rest = diff - cd
		var r := absi(rest)
		var sg := signi(rest)
		if r > 0:
			if r <= 2:
				if rng.randf() < 0.35:
					events.append([Ev.STAIRS, rest])
				else:
					for _i in r:
						events.append([Ev.TERRACE, sg])
			else:
				var t := rng.randi_range(0, 1 if r < 5 else 2)
				var st := r - t
				var m := ceili(st / 4.0)
				for k in m:
					var rise: int = st / m + (1 if k < st % m else 0)
					events.append([Ev.STAIRS, sg * rise])
				for _i in t:
					events.append([Ev.TERRACE, sg])
		# shuffle (own rng so it stays deterministic)
		for i in range(events.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = events[i]
			events[i] = events[j]
			events[j] = tmp
		if not climb_ev.is_empty():
			events.insert(0 if bump else rng.randi_range(0, events.size()), climb_ev)
		return events

	## A long hall's profile with its landings (see the header): the events keep off the landings' flat stretches and
	## LANDING_DOOR_CLEAR steps off both doors (a step at a door's mouth moves where its office door can stand). The spots are
	## shifted together, 0, 1, -1, 2, -2 ... steps, until the events fit; [steps, the spots used]. When they never fit, the
	## events go where they always went and the hall gets no landing ([steps, []]). No dice.
	func _landing_profile(S: Array[Vector2i], la: int, lb: int, events: Array, centres: Array[int]) -> Array:
		var n := S.size() - 2
		var win := maxi(2, roundi(float(n + 1) / float(centres.size() + 1) * LANDING_SHIFT))
		for d in range(0, 2 * win + 1):
			var shift := (d + 1) / 2 * (1 if d % 2 == 1 else -1)
			var spots: Array[int] = []
			for c in centres:
				spots.append(c + shift)
			if spots[0] < LANDING_R + 2 or spots[spots.size() - 1] > n - LANDING_R - 1:
				continue
			var keep := {}
			for c in spots:
				for k in range(c - LANDING_R - 2, c + LANDING_R + 3):
					keep[k] = true
			# (an event at k changes cell k and every cell after it, so the CLEAR - 1 cells at each door stay at its level: no
			# event at 1 .. CLEAR - 1 by door a, nor at n + 2 - CLEAR .. n + 1 by door b)
			for k in range(1, LANDING_DOOR_CLEAR + 1):
				keep[n + 2 - k] = true
				if k < LANDING_DOOR_CLEAR:
					keep[k] = true
			var steps := _place_events(S, la, lb, events, keep)
			if not steps.is_empty():
				return [steps, spots]
		var none: Array[int] = []
		return [_place_events(S, la, lb, events), none]

	## A flat link (the sewer cluster's own halls): every cell at `level`.
	func _flat_steps(n: int, level: int) -> Array:
		var steps: Array = []
		for _i in n:
			var st := Step.new()
			st.level = level
			steps.append(st)
		return steps

	## The service stair from la to lb: only STAIRS, in flights of at most SewerCluster.FLIGHT_MAX levels, spread along the
	## straight stretches. No dice. [] when they do not fit.
	func _stair_profile(S: Array[Vector2i], la: int, lb: int) -> Array:
		var diff := lb - la
		var r := absi(diff)
		var m := ceili(float(r) / SewerCluster.FLIGHT_MAX)
		var events: Array = []
		for k in m:
			var rise: int = r / m + (1 if k < r % m else 0)
			events.append([Ev.STAIRS, signi(diff) * rise])
		return _place_events(S, la, lb, events)

	## Put the profile's events on cells S[1..n] (stairs only on straight stretches), spread evenly; [] when they do not fit.
	## No event goes on an index in `keep`.
	func _place_events(S: Array[Vector2i], la: int, lb: int, events: Array, keep: Dictionary = {}) -> Array:
		var n := S.size() - 2
		var e := events.size()
		if e > n + 1:
			return []
		var ev_at := {}
		var prev := 0
		# (crowded off a landing, two events keep LANDING_EVENT_GAP apart: back to back, a stair's twins and the next step
		# leave a climb in the hall)
		var gap := 1 if keep.is_empty() else LANDING_EVENT_GAP
		for j in e:
			var kind: int = events[j][0]
			var target := int(round((j + 1.0) * (n + 1.0) / (e + 1.0)))
			var lo_i := prev + (gap if j > 0 else 1)
			var hi_i := n + 1 - (e - 1 - j) * gap
			var found := -1
			for off in range(0, n + 2):
				for sgn in [1, -1]:
					var i: int = target + off * sgn
					if i < lo_i or i > hi_i or keep.has(i):
						continue
					if kind == Ev.STAIRS and (i > n or not _straight(S, i)):
						continue
					found = i
					break
				if found != -1:
					break
			if found == -1:
				return []
			ev_at[found] = events[j]
			prev = found
		var steps: Array = []
		var cur := la
		for i in range(1, n + 1):
			var st := Step.new()
			if not ev_at.has(i):
				st.level = cur
			else:
				var ev: Array = ev_at[i]
				var delta: int = ev[1]
				if ev[0] == Ev.STAIRS:
					st.stairs = true
					st.rise = absi(delta)
					if delta > 0:
						st.level = cur
						st.dir = Hex.dir_to(S[i], S[i + 1])
						cur += delta
					else:
						st.level = cur + delta
						st.dir = Hex.dir_to(S[i], S[i - 1])
						cur += delta
				else:
					cur += delta
					st.level = cur
			if st.level < 0:
				return []
			steps.append(st)
		if ev_at.has(n + 1):
			cur += int(ev_at[n + 1][1])
		if cur != lb:
			return []
		return steps

	# ------------------------------------------------------------------ landings

	## The LANDINGS (see the header): how many each long hall gets, where, and the cells they add. No dice.
	func _add_landings() -> void:
		for li in links.size():
			var l := links[li]
			if not _landing_link(l) or l.centres.is_empty():
				continue
			var own := {}                   # the hall's own cells (its doors are room cells: they stay out)
			for c in l.cells:
				own[c] = true
			var n := l.route.size() - 2
			var win := maxi(2, roundi(float(n + 1) / float(l.centres.size() + 1) * LANDING_WINDOW))
			var lanes: Array[Vector2i] = []   # the hall's lanes (its route and lane cells): a back keeps two cells from them
			for k in range(1, l.route.size() - 1):
				lanes.append(l.route[k])
			lanes.append_array(l.lanes)
			var placed: Array[int] = []
			for c0 in l.centres:
				# the spot its profile kept flat; else the best that fits nearby
				var best := -1
				var shape := {}
				if _spaced(l.route, placed, c0):
					shape = _landing_shape(l, c0, own, lanes)
					if not shape.is_empty():
						best = c0
				var best_s := INF
				if best < 0:
					for i in range(c0 - win, c0 + win + 1):
						if i < LANDING_R + 2 or i > n - LANDING_R - 1:
							continue
						var s := absf(float(i - c0)) - (LANDING_TURN_PULL if _turns(l.route, i) else 0.0)
						if s >= best_s - 0.0001 or not _spaced(l.route, placed, i):
							continue
						var sh := _landing_shape(l, i, own, lanes)
						if sh.is_empty():
							continue
						best = i
						best_s = s
						shape = sh
				if best < 0:
					continue
				placed.append(best)
				_make_landing(l, best, shape, own)
			landings_of[li] = placed.size()

	## Where a hall of route S means its landings (route indices): DungeonGen.landing_count of its length, each nearest the
	## even share of the route, a spot where the route turns counted LANDING_TURN_PULL steps nearer, LANDING_SPACING apart
	## and the hexagon off the doors. Empty for a short hall. No dice.
	func _landing_centres(S: Array[Vector2i]) -> Array[int]:
		var out: Array[int] = []
		var n := S.size() - 2
		var want := DungeonGen.landing_count(float(n + 1) * Hex.SQRT3)
		if want == 0:
			return out
		var spacing := float(n + 1) / float(want + 1)
		var win := maxi(2, roundi(spacing * LANDING_WINDOW))
		for j in want:
			var ideal := roundi(float(j + 1) * spacing)
			var best := -1
			var best_s := INF
			for i in range(ideal - win, ideal + win + 1):
				if i < LANDING_R + 2 or i > n - LANDING_R - 1 or not _spaced(S, out, i):
					continue
				var s := absf(float(i - ideal)) - (LANDING_TURN_PULL if _turns(S, i) else 0.0)
				if s < best_s - 0.0001:
					best = i
					best_s = s
			if best >= 0:
				out.append(best)
		return out

	## Is route index i LANDING_SPACING from every index in `placed` (along the route and on the map)?
	func _spaced(S: Array[Vector2i], placed: Array[int], i: int) -> bool:
		for pi in placed:
			if absi(pi - i) < LANDING_SPACING or Hex.distance(S[pi], S[i]) < LANDING_SPACING:
				return false
		return true

	## May this hall have landings? Not the service stair, not the one short chokepoint (a narrow tree link), not a sewer
	## cluster's or a lava cave's halls.
	func _landing_link(l: Link) -> bool:
		if stair_pair == Vector2i(l.a, l.b) or stair_pair == Vector2i(l.b, l.a):
			return false
		if l.narrow and not l.loop and not l.shortcut:
			return false
		if cluster.has(l.a) or cluster.has(l.b) or cave.has(l.a) or cave.has(l.b):
			return false
		return true

	## Does the route turn at S[i]?
	func _turns(S: Array[Vector2i], i: int) -> bool:
		return i >= 1 and i + 1 < S.size() and not _straight(S, i)

	## The landing's shape at route cell S[i]: its HUB (the hexagon's middle: S[i], or a neighbour of it on the side the
	## camera looks at, so the bay opens away from the camera and its set piece faces it instead of hiding behind the near
	## wall) and its BACKS. {hub, backs} or {} when no hub fits. The hub is S[i] when that gives a back away from the camera,
	## else the first neighbour (most away from the camera first) that does, else S[i] or the first neighbour that fits.
	func _landing_shape(l: Link, i: int, own: Dictionary, lanes: Array[Vector2i]) -> Dictionary:
		var c: Vector2i = l.route[i]
		var cc: HexMap.Cell = map.get_cell(c)
		if cc == null or cc.type != HexMap.Tile.FLOOR:
			return {}
		var hubs: Array[Vector2i] = [c]
		var ks: Array[int] = [0, 1, 2, 3, 4, 5]
		ks.sort_custom(func(a: int, b: int) -> bool:
			var da := Hex.dir_vector(a).dot(Vector3(ThemeGeo.CAMERA_DIR.x, 0.0, ThemeGeo.CAMERA_DIR.y))
			var db := Hex.dir_vector(b).dot(Vector3(ThemeGeo.CAMERA_DIR.x, 0.0, ThemeGeo.CAMERA_DIR.y))
			return da < db - 0.001 or (absf(da - db) <= 0.001 and a < b))
		for k in ks:
			hubs.append(c + Hex.DIRS[k])
		var fallback := {}
		for h in hubs:
			if not _landing_fits(h, cc.level, own):
				continue
			var backs := _backs(h, lanes)
			if backs.is_empty():
				continue
			if _back_far(h, backs[0]):
				return {"hub": h, "backs": backs}
			if fallback.is_empty():
				fallback = {"hub": h, "backs": backs}
		return fallback

	## Can a landing's hexagon stand round `hub` at level `lv`? The hall's cells in it (LANDING_R + 1 round the hub) are floor
	## at that level and none within one ring more is a stair; every new cell of it is free, a wall's width from anything
	## that is not the hall and LANDING_ROOM_CLEAR from every room (so nothing that reads distances to the halls, the rooms'
	## features, the elevator's notch, the van, the mail, sees it).
	func _landing_fits(hub: Vector2i, lv: int, own: Dictionary) -> bool:
		for x in Hex.range_cells(hub, LANDING_R + 2):
			if own.has(x):
				var xc: HexMap.Cell = map.get_cell(x)
				if xc.type != HexMap.Tile.FLOOR or (xc.level != lv and Hex.distance(x, hub) <= LANDING_R + 1):
					return false
		for x in Hex.range_cells(hub, LANDING_R + 1):
			if map.has_cell(x):
				if not own.has(x):
					return false
				continue
			if room_of.has(x) or pits.has(x) or Hex.distance(x, Vector2i.ZERO) > p_size + 16:
				return false
			if _room_zone().has(x):
				return false
			for d in Hex.DIRS:
				var y: Vector2i = x + d
				if map.has_cell(y) and not own.has(y):
					return false
		return true

	var _room_zone_cache: Dictionary = {}

	## The cells closer than LANDING_ROOM_CLEAR to a room cell (from the room cells on an edge: the nearest room cell to
	## anything outside the rooms is one of those). Built once, when the landings pass first asks.
	func _room_zone() -> Dictionary:
		if _room_zone_cache.is_empty():
			for c: Vector2i in room_of:
				var edge := false
				for d in Hex.DIRS:
					if not room_of.has(c + d):
						edge = true
						break
				if not edge:
					_room_zone_cache[c] = true
					continue
				for y in Hex.range_cells(c, LANDING_ROOM_CLEAR - 1):
					_room_zone_cache[y] = true
		return _room_zone_cache

	## The sides of the hexagon round `hub` a set piece may stand against (side k: its middle cell hub + DIRS[k] + DIRS[k + 1]
	## two cells or more from every lane cell), best first: its back wall farthest from the camera (so the piece faces it),
	## then farthest from the lanes.
	func _backs(hub: Vector2i, lanes: Array[Vector2i]) -> Array[int]:
		var sides: Array = []   # [k, distance to the lanes, camera dot]
		for k in 6:
			var bc: Vector2i = hub + Hex.DIRS[k] + Hex.DIRS[(k + 1) % 6]
			var dmin := 1 << 20
			for q in lanes:
				dmin = mini(dmin, Hex.distance(bc, q))
			if dmin < 2:
				continue
			sides.append([k, dmin, _side_normal(hub, k).dot(ThemeGeo.CAMERA_DIR)])
		sides.sort_custom(func(a: Array, b: Array) -> bool:
			if absf(float(a[2]) - float(b[2])) > 0.001:
				return float(a[2]) < float(b[2])
			return int(a[1]) > int(b[1]) or (int(a[1]) == int(b[1]) and int(a[0]) < int(b[0])))
		var out: Array[int] = []
		for s: Array in sides:
			out.append(int(s[0]))
		return out

	## Side k's outward normal (world X/Z) of the hexagon round `hub`.
	func _side_normal(hub: Vector2i, k: int) -> Vector2:
		var w := Hex.to_world(hub + Hex.DIRS[k] + Hex.DIRS[(k + 1) % 6]) - Hex.to_world(hub)
		return Vector2(w.x, w.z).normalized()

	## Is side k's back wall on the far side from the camera (the piece in front of it faces the camera)?
	func _back_far(hub: Vector2i, k: int) -> bool:
		return _side_normal(hub, k).dot(ThemeGeo.CAMERA_DIR) <= -0.25

	## Cut the landing at route cell S[i] (its hexagon round shape's hub) and record it (HexMap.landings): its centre (S[i]),
	## hub, level, new cells, the hall it is on, and its backs.
	func _make_landing(l: Link, i: int, shape: Dictionary, own: Dictionary) -> void:
		var c: Vector2i = l.route[i]
		var hub: Vector2i = shape["hub"]
		var lv: int = map.get_cell(c).level
		var added: Array[Vector2i] = []
		for x in Hex.range_cells(hub, LANDING_R + 1):
			if map.has_cell(x):
				continue
			map.set_cell(x, lv).tag = "corridor"
			corr_cells[x] = true
			added.append(x)
		added.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		for x in added:
			own[x] = true
		landing_recs.append({"center": c, "hub": hub, "level": lv, "cells": added, "hall": ["room:%d" % l.a, "room:%d" % l.b],
				"step": i, "turn": _turns(l.route, i), "dir_in": Hex.dir_to(l.route[i - 1], c), "dir_out": Hex.dir_to(c, l.route[i + 1]),
				"backs": shape["backs"]})

	## One row per hall for DungeonGen.last_halls (diagnostics).
	func _hall_stats() -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for li in links.size():
			var l := links[li]
			var wa := Hex.to_world(l.door_a)
			var wb := Hex.to_world(l.door_b)
			out.append({"a": l.a, "b": l.b, "steps": l.length, "path": float(l.length) * Hex.SQRT3,
					"straight": Vector2(wa.x - wb.x, wa.z - wb.z).length(), "narrow": l.narrow, "loop": l.loop, "shortcut": l.shortcut,
					"stair": stair_pair == Vector2i(l.a, l.b) or stair_pair == Vector2i(l.b, l.a),
					"special": cluster.has(l.a) or cluster.has(l.b) or cave.has(l.a) or cave.has(l.b),
					"landings": int(landings_of.get(li, 0))})
		return out

	# ------------------------------------------------------------------ start / exit

	func _choose_start_exit() -> void:
		start = rooms[0].center
		# farthest room by walking distance over non-climb links
		var n := rooms.size()
		var dist: Array = []
		for _i in n:
			dist.append(1 << 20)
		dist[0] = 0
		for _pass in n:
			for l in links:
				if l.shortcut:
					continue
				var w := l.length + Hex.distance(rooms[l.a].center, l.door_a) + Hex.distance(rooms[l.b].center, l.door_b)
				if dist[l.a] + w < dist[l.b]:
					dist[l.b] = dist[l.a] + w
				if dist[l.b] + w < dist[l.a]:
					dist[l.a] = dist[l.b] + w
		# (never a sewer cluster's room: the elevator and its landing stay dry; without a cluster this is room 1 on)
		var best := 1
		while cluster.has(best) or cave.has(best):
			best += 1
		for i in range(1, n):
			if dist[i] > dist[best] and not cluster.has(i) and not cave.has(i):
				best = i
		exit_cell = rooms[best].center
		# the rooms the elevator may go in, farthest first (ties: lower index); the farthest is the exit room unless the
		# wall elevator needs another
		exit_order.clear()
		for i in range(1, n):
			if not cluster.has(i) and not cave.has(i):
				exit_order.append(i)
		exit_order.sort_custom(func(a: int, b: int) -> bool: return dist[a] > dist[b] or (dist[a] == dist[b] and a < b))
		exit_order.erase(best)
		exit_order.push_front(best)
		if exit_order.size() > EXIT_ROOM_TRIES:
			exit_order.resize(EXIT_ROOM_TRIES)

	# ------------------------------------------------------------------ the elevator

	## Put the elevator in the exit room (or the next-farthest one, for a wall slot): the exit cell becomes its landing. A
	## wall job whose rooms have no wall slot gets the free car (fallback). False when not even the free car fits.
	func _place_elevator() -> bool:
		if p_elevator == ElevatorGeo.PLACE_WALL:
			for ri in exit_order:
				var slot := _best_wall_slot(rooms[ri])
				if slot.is_empty():
					continue
				var room := rooms[ri]
				var g := ElevatorGeo.notch_cells(slot["m0"], int(slot["k"]))
				for nc: Vector2i in (g["n"] as Array):
					map.set_cell(nc, room.level)
					room.cells[nc] = true
					room_of[nc] = room.index
				elevator = ElevatorGeo.make_wall(slot["m0"], int(slot["k"]), room.level, room.index)
				exit_cell = elevator["landing"]
				notched = true
				return true
		for ri in exit_order:
			var room := rooms[ri]
			for j in ElevatorGeo.FREE_JS:
				if ElevatorGeo.free_ok(room.cells, room.center, j):
					elevator = ElevatorGeo.make_free(room.center, j, room.level, room.index)
					elevator["fallback"] = p_fallback or p_elevator == ElevatorGeo.PLACE_WALL
					exit_cell = elevator["landing"]
					return true
		return false

	## The best notch for `room`: back walls 15 degrees off the camera first, then a wall line that runs straight past
	## the jambs, then far from the doors and near the room's middle. {m0, k} or {}.
	func _best_wall_slot(room: Room) -> Dictionary:
		var door_d := _corridor_dist()
		var cand: Array[Vector2i] = room.boundary.duplicate()
		cand.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		var best := {}
		var best_s := -INF
		for m0 in cand:
			for k in ElevatorGeo.WALL_KS:
				var ok := ElevatorGeo.wall_slot(map, room.cells, m0, k)
				if ok.is_empty():
					continue
				var land: Vector2i = ElevatorGeo.notch_cells(m0, k)["landing"]
				var s := (100.0 if k == ElevatorGeo.WALL_KS[0] else 0.0) + (20.0 if bool(ok["strict"]) else 0.0) \
						+ 2.0 * minf(float(door_d.get(land, WALL_DOOR_CAP)), WALL_DOOR_CAP) - 0.5 * Hex.distance(land, room.center)
				if s > best_s + 0.0001:
					best_s = s
					best = {"m0": m0, "k": k}
		return best

	var _corr_d: Dictionary = {}

	## Hex steps from each floor cell to the nearest corridor cell (up to WALL_DOOR_CAP), through the floor.
	func _corridor_dist() -> Dictionary:
		if not _corr_d.is_empty():
			return _corr_d
		var frontier: Array[Vector2i] = []
		for c: Vector2i in corr_cells:
			_corr_d[c] = 0
			frontier.append(c)
		for step in range(1, int(WALL_DOOR_CAP) + 1):
			var next: Array[Vector2i] = []
			for c in frontier:
				for d in Hex.DIRS:
					var nb: Vector2i = c + d
					if not _corr_d.has(nb) and map.has_cell(nb):
						_corr_d[nb] = step
						next.append(nb)
			frontier = next
		return _corr_d

	## After the walls are cut: the elevator's solids (the jambs, or the free car's sides), its no_stand cells and its record.
	func _add_elevator() -> void:
		if elevator.is_empty():
			return
		for poly in ElevatorGeo.solids(elevator):
			map.add_solid(poly)
		if str(elevator["place"]) == ElevatorGeo.PLACE_FREE:
			for c: Vector2i in (elevator["cells"] as Array):
				map.no_stand[c] = true
		map.elevator = elevator

	## The car opened as planned: the landing is full floor, and so is the doorway (the notch's two middle mouth cells,
	## with the car's cells cut by its back wall) or the walk round the free car.
	func _elevator_intact() -> bool:
		if elevator.is_empty():
			return true
		if not map.is_walkable_cell(elevator["landing"]):
			return false
		if str(elevator["place"]) == ElevatorGeo.PLACE_WALL:
			var ms: Array = elevator["mouth"]
			if not map.is_walkable_cell(ms[1]) or not map.is_walkable_cell(ms[2]):
				return false
			for c: Vector2i in (elevator["cells"] as Array):
				if not map.is_half(c):
					return false
			return true
		var c0: Vector2i = (elevator["cells"] as Array)[0]
		for c in Hex.ring(c0, 2):
			if not map.is_walkable_cell(c):
				return false
		return true

	# ------------------------------------------------------------------ decoration

	func _decorate() -> void:
		var clear := {}
		for c in Hex.range_cells(start, 2):
			clear[c] = true
		for c in Hex.range_cells(exit_cell, 2):
			clear[c] = true
		for c in ElevatorGeo.keep_cells(elevator):
			clear[c] = true
		var near_corr := {}
		for c in corr_cells:
			for n in Hex.range_cells(c, FEATURE_DOOR_CLEAR):
				near_corr[n] = true
		for room in rooms:
			var valid := {}
			var keys: Array[Vector2i] = []
			for c in room.cells:
				if near_corr.has(c) or clear.has(c) or Hex.distance(c, room.center) <= FEATURE_CENTER_CLEAR:
					continue
				var inner := true
				for d in Hex.DIRS:
					if not room.cells.has(c + d):
						inner = false
						break
				if inner:
					valid[c] = true
					keys.append(c)
			if keys.is_empty():
				continue
			# Pillars and pits keep two cells from the walls: next to a wall line they would leave a strip of
			# floor too thin to walk (the wall runs through the boundary cells' centers).
			var deep := {}
			for c: Vector2i in valid:
				var ok := true
				for fc in Hex.range_cells(c, 2):
					if not room.cells.has(fc):
						ok = false
						break
				if ok:
					deep[c] = true
			var plan: Array[int] = []
			# About half the raised features the rooms used to get, in rooms that are twice the size.
			var scale := 1 + room.cells.size() / 120
			for _i in rng.randi_range(0, scale):
				plan.append(Feature.ZIGGURAT if rng.randf() < 0.4 else Feature.PLATFORM)
			for _i in rng.randi_range(1 if room.index == 1 else 0, 1):
				plan.append(Feature.LEDGE)
			for _i in rng.randi_range(0, 1):
				plan.append(Feature.PILLAR)
			if room.index % 3 == 1 or rng.randf() < 0.2:
				plan.append(Feature.PIT)
			var occupied := {}
			# a sewer cluster's room rolls its features as ever (the dice stay in step) but builds none: one water level
			var dry_run := cluster.has(room.index) or cave.has(room.index)   # (a cave's chambers: CaveGen's rock)
			for kind in plan:
				for _try in 14:
					var c: Vector2i = keys[rng.randi_range(0, keys.size() - 1)]
					var fp := _footprint(kind, c)
					var ok := true
					var need_deep := kind == Feature.PILLAR or kind == Feature.PIT
					for fc in fp:
						if not valid.has(fc) or occupied.has(fc) or (need_deep and not deep.has(fc)):
							ok = false
							break
					if not ok:
						continue
					for fc in fp:
						occupied[fc] = true
						for d in Hex.DIRS:
							occupied[fc + d] = true
						if dry_run:
							continue
						if fp[fc] == PIT_MARK:
							map.cells.erase(fc)
							pits[fc] = true
						else:
							map.get_cell(fc).level = room.level + int(fp[fc])
					if kind == Feature.LEDGE and not dry_run:
						climb_features += 1
					break

	## cell -> level delta (PIT_MARK = remove the cell).
	func _footprint(kind: int, c: Vector2i) -> Dictionary:
		var fp := {}
		match kind:
			Feature.PLATFORM:
				for fc in Hex.range_cells(c, rng.randi_range(1, 2)):
					fp[fc] = 1
			Feature.ZIGGURAT:
				var tiers := rng.randi_range(2, 3)
				for fc in Hex.range_cells(c, tiers - 1):
					fp[fc] = tiers - Hex.distance(c, fc)
			Feature.LEDGE:
				for fc in Hex.range_cells(c, rng.randi_range(0, 1)):
					fp[fc] = 2
			Feature.PILLAR:
				var h := rng.randi_range(3, 6)
				fp[c] = h
				for _i in rng.randi_range(0, 2):
					fp[c + Hex.DIRS[rng.randi_range(0, 5)]] = h
			Feature.PIT:
				for fc in Hex.range_cells(c, 0 if rng.randf() < 0.7 else 1):
					fp[fc] = PIT_MARK
		return fp

	# ------------------------------------------------------------------ walls

	func _add_walls() -> void:
		var wall_level := {}
		for c in map.cells:
			var cell: HexMap.Cell = map.cells[c]
			var top: int = cell.level + (cell.stair_rise if cell.type == HexMap.Tile.STAIRS else 0)
			for d in Hex.DIRS:
				var nb: Vector2i = c + d
				if map.cells.has(nb) or pits.has(nb):
					continue
				wall_level[nb] = maxi(wall_level.get(nb, -99), top)
		for c in wall_level:
			map.set_cell(c, int(wall_level[c]) + p_wall, HexMap.Tile.WALL)

	# ------------------------------------------------------------------ validate

	func _validate_and_tag() -> bool:
		if stairs_count == 0 or climb_features == 0:
			return false
		var reached := {start: true}
		var queue: Array[Vector2i] = [start]
		var qi := 0
		while qi < queue.size():
			var c: Vector2i = queue[qi]
			qi += 1
			for d in Hex.DIRS:
				var nb: Vector2i = c + d
				if reached.has(nb) or not map.is_walkable_cell(nb):
					continue
				if map.cell_transition(c, nb) == HexMap.Move.OK:
					reached[nb] = true
					queue.append(nb)
		if not reached.has(exit_cell) or exit_cell == start:
			return false
		var per_room: Array = []
		for _i in rooms.size():
			per_room.append(0)
		for c in reached:
			if room_of.has(c):
				per_room[room_of[c]] += 1
		for r in rooms:
			if per_room[r.index] < 6:
				return false
		if map.find_path(start, exit_cell, false).is_empty():
			return false
		if not _walls_clean() or not _elevator_intact():
			return false
		for c in reached:
			var cell: HexMap.Cell = map.cells[c]
			if cell.tag == "" and room_of.has(c):
				cell.tag = "room:%d" % room_of[c]
		# Cut cells (part floor, part wall) and the cells under the free elevator belong to their room too: placement
		# reads the tag, then checks the wall.
		for c: Vector2i in map.cells:
			var cell: HexMap.Cell = map.cells[c]
			if cell.tag == "" and room_of.has(c) and cell.type != HexMap.Tile.WALL and (cell.wall_mask != 0 or map.no_stand.has(c)):
				cell.tag = "room:%d" % room_of[c]
		map.cells[start].tag = "start"
		map.cells[exit_cell].tag = "exit"
		return true


	## Midpoint walls left the floor in one piece: every doorway cell is full (the corridor meets the room's floor
	## through an open gap) and every full cell joins the start's through full cells (heights aside), so no
	## pocket of floor is cut off by a wall line.
	func _walls_clean() -> bool:
		for l in links:
			if not map.is_walkable_cell(l.door_a) or not map.is_walkable_cell(l.door_b):
				return false
		var seen := {start: true}
		var queue: Array[Vector2i] = [start]
		var qi := 0
		while qi < queue.size():
			var c: Vector2i = queue[qi]
			qi += 1
			for d in Hex.DIRS:
				var nb: Vector2i = c + d
				if not seen.has(nb) and map.is_walkable_cell(nb):
					seen[nb] = true
					queue.append(nb)
		for c: Vector2i in map.cells:
			if map.is_walkable_cell(c) and not seen.has(c):
				return false
		return true
