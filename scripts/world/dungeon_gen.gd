class_name DungeonGen
extends RefCounted
## Procedural hex dungeon: rooms at varied heights joined by terraced / stair corridors.
##
## Algorithm (all randomness from one seeded RandomNumberGenerator):
##  1. Scatter 6-9 hex-blob rooms (round, lobed or bitten shapes) keeping a gap between them.
##  2. Prim spanning tree over the room centers, then assign base levels by walking the tree
##     (random deltas, clamped 0..8).
##  3. Carve each tree link (plus 1-2 extra loops) with a turn-penalised A*, two cells wide
##     (one-wide only for the climb shortcut and at most one short chokepoint). Height along the
##     corridor is a list of events: +-1 terraces, STAIRS cells (rise <= 4, chained) on straight
##     stretches, and on one loop a +-2 climb, which makes it a shortcut that needs climbing.
##  4. Decorate rooms: platforms (+1), ziggurats (+1..+3 tiers), climbable ledges (+2),
##     blocked pillars (+3..+5) and void pits, all kept one cell away from walls/doors/start/exit.
##  5. Ring everything walkable with WALL cells, BFS-validate (start reaches exit and every
##     room without climbing), tag cells, and retry with a derived seed on failure.
##
## params (all optional): rooms, size, room_radius_min, room_radius_max, gap, loops, wall_height.

const MAX_ATTEMPTS := 24
const MAX_BASE_LEVEL := 8
const KEY_OFF := 128
const KEY_W := 256
const PIT_MARK := -999
const NARROW_CHANCE := 0.3      ## per eligible link, until one narrow chokepoint exists
const NARROW_MAX_LEN := 7       ## only short links may be one hex wide

enum Ev { TERRACE, CLIMB, STAIRS }
enum Feature { PLATFORM, ZIGGURAT, LEDGE, PILLAR, PIT }


## Generate a dungeon. Deterministic per seed (and params).
static func generate(seed: int, params: Dictionary = {}) -> HexMap:
	for attempt in MAX_ATTEMPTS:
		var s: int = seed if attempt == 0 else ((seed * 1103515245 + attempt * 12345 + 1) & 0x7fffffff)
		var b := Builder.new(s, params)
		var m: HexMap = b.build()
		if m != null:
			return m
	push_warning("DungeonGen: no valid map for seed %d after %d attempts; using fallback" % [seed, MAX_ATTEMPTS])
	return _fallback()


## Tiny always-valid map (a lone room with stairs), used only if every attempt fails.
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


class Step:
	var level: int = 0
	var stairs: bool = false
	var rise: int = 0
	var dir: int = 0


class Builder:
	extends RefCounted

	var rng := RandomNumberGenerator.new()
	var p_rooms: int = 0
	var p_size: int = 22
	var p_rmin: int = 3
	var p_rmax: int = 6
	var p_gap: int = 5
	var p_loops: int = -1
	var p_wall: int = 3

	var map := HexMap.new()
	var rooms: Array[Room] = []
	var room_of: Dictionary = {}        ## cell -> room index
	var links: Array[Link] = []
	var corr_cells: Dictionary = {}     ## every corridor cell
	var corr_buffer: Dictionary = {}    ## cells within 1 of a corridor
	var pits: Dictionary = {}
	var tree_adj: Array = []
	var stairs_count := 0
	var climb_features := 0
	var start: Vector2i = Vector2i.ZERO
	var exit_cell: Vector2i = Vector2i.ZERO
	var narrow_used := false

	func _init(s: int, params: Dictionary) -> void:
		rng.seed = s
		p_rooms = int(params.get("rooms", 0))
		p_size = int(params.get("size", 22))
		p_rmin = int(params.get("room_radius_min", 3))
		p_rmax = maxi(p_rmin, int(params.get("room_radius_max", 6)))
		p_gap = int(params.get("gap", 5))
		p_loops = int(params.get("loops", -1))
		p_wall = int(params.get("wall_height", 3))

	# ------------------------------------------------------------------ build

	func build() -> HexMap:
		if not _place_rooms():
			return null
		if not _plan_and_carve():
			return null
		_choose_start_exit()
		_decorate()
		_add_walls()
		if not _validate_and_tag():
			return null
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
			var main := maxi(3, radius - 1)
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
					if c == center:
						continue
					var inside := 0
					for d in Hex.DIRS:
						if cells.has(c + d):
							inside += 1
					if inside >= 4 and inside < 6:
						cand.append(c)
				if cand.is_empty():
					break
				cells.erase(cand[rng.randi_range(0, cand.size() - 1)])
		return _component(cells, center)

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
			if _carve(pr.x, pr.y, made == 0):
				made += 1
		return true

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

	## Extra cost to enter c, or -1 if a corridor may not use it.
	func _penalty(c: Vector2i, a_idx: int, b_idx: int) -> int:
		if room_of.has(c) or corr_buffer.has(c) or map.has_cell(c) or pits.has(c):
			return -1
		if Hex.distance(c, Vector2i.ZERO) > p_size + 14:
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
		var srcs: Array[Vector2i] = a.boundary.duplicate()
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
				var door := _touching(c, d, b.index)
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

	func _push(buckets: Array, f: int, k: int) -> void:
		while buckets.size() <= f:
			buckets.append([])
		buckets[f].append(k)

	func _h(c: Vector2i, b: Room) -> int:
		return maxi(0, Hex.distance(c, b.center) - b.extent - 1) * 10

	## A cell of room `idx` adjacent to c (preferring straight ahead), or a sentinel.
	func _touching(c: Vector2i, d: int, idx: int) -> Vector2i:
		var ahead: Vector2i = c + Hex.DIRS[d]
		if room_of.get(ahead, -1) == idx:
			return ahead
		for dd in Hex.DIRS:
			if room_of.get(c + dd, -1) == idx:
				return c + dd
		return Vector2i(1 << 20, 0)

	func _carve(ai: int, bi: int, shortcut: bool) -> bool:
		var ra := rooms[ai]
		var rb := rooms[bi]
		var S := _route(ra, rb)
		if S.size() < 3:
			return false
		var steps := _profile(S, ra.level, rb.level, shortcut)
		if steps.is_empty():
			return false
		var n := S.size() - 2
		for i in range(1, n + 1):
			var st: Step = steps[i - 1]
			var c := S[i]
			if st.stairs:
				map.set_stairs(c, st.level, st.dir, st.rise)
				stairs_count += 1
			else:
				map.set_cell(c, st.level)
			map.get_cell(c).tag = "corridor"
			corr_cells[c] = true
		# Corridors are two wide: a parallel lane beside the routed path, stairs
		# included (each lane gets its own matching staircase). One-wide passages
		# are reserved for special cases: the climb shortcut and one short chokepoint.
		var narrow := shortcut
		if not shortcut and not narrow_used and n <= NARROW_MAX_LEN and rng.randf() < NARROW_CHANCE:
			narrow = true
			narrow_used = true
		if not narrow:
			_widen(S, steps, ai, bi)
		for c in corr_cells:
			corr_buffer[c] = true
			for d in Hex.DIRS:
				corr_buffer[c + d] = true
		var link := Link.new()
		link.a = ai
		link.b = bi
		link.shortcut = shortcut
		link.length = n + 1
		link.door_a = S[0]
		link.door_b = S[n + 1]
		links.append(link)
		if shortcut:
			climb_features += 1
		return true

	## Add the second lane: for each path cell S[i], its neighbor one turn to the
	## left of the travel direction, at the same height. A stairs cell's twin is
	## only added when the lane cells before and after it exist too, so a twin
	## staircase never dead-ends into a wall.
	func _widen(S: Array[Vector2i], steps: Array, ai: int, bi: int) -> void:
		var n := S.size() - 2
		var side := {}   # i -> side cell, for cells whose side is free
		for i in range(1, n + 1):
			var d := Hex.dir_to(S[i], S[i + 1])
			var c: Vector2i = S[i] + Hex.DIRS[posmod(d + 1, 6)]
			if _penalty(c, ai, bi) >= 0 and not corr_cells.has(c):
				side[i] = c
		for i in range(1, n + 1):
			if not side.has(i):
				continue
			var st: Step = steps[i - 1]
			var c: Vector2i = side[i]
			if st.stairs:
				# Lane neighbours along the stairs: before (or room a) and after (or room b).
				# (cells are processed in order, so a skipped earlier twin is simply absent)
				var before_ok := i == 1 or (side.has(i - 1) and corr_cells.has(side[i - 1]))
				var after_ok := i == n or side.has(i + 1)
				if not (before_ok and after_ok):
					continue
				map.set_stairs(c, st.level, st.dir, st.rise)
				stairs_count += 1
			else:
				map.set_cell(c, st.level)
			map.get_cell(c).tag = "corridor"
			corr_cells[c] = true

	func _straight(S: Array[Vector2i], i: int) -> bool:
		return Hex.dir_to(S[i - 1], S[i]) == Hex.dir_to(S[i], S[i + 1])

	## Height profile for cells S[1..n]; [] when the events cannot be placed.
	func _profile(S: Array[Vector2i], la: int, lb: int, shortcut: bool) -> Array:
		var n := S.size() - 2
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
		var e := events.size()
		if e > n + 1:
			return []
		var ev_at := {}
		var prev := 0
		for j in e:
			var kind: int = events[j][0]
			var target := int(round((j + 1.0) * (n + 1.0) / (e + 1.0)))
			var lo_i := prev + 1
			var hi_i := n + 1 - (e - 1 - j)
			var found := -1
			for off in range(0, n + 2):
				for sgn in [1, -1]:
					var i: int = target + off * sgn
					if i < lo_i or i > hi_i:
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
		var best := 1
		for i in range(1, n):
			if dist[i] > dist[best]:
				best = i
		exit_cell = rooms[best].center

	# ------------------------------------------------------------------ decoration

	func _decorate() -> void:
		var clear := {}
		for c in Hex.range_cells(start, 2):
			clear[c] = true
		for c in Hex.range_cells(exit_cell, 2):
			clear[c] = true
		var near_corr := {}
		for c in corr_cells:
			for n in Hex.range_cells(c, 2):
				near_corr[n] = true
		for room in rooms:
			var valid := {}
			var keys: Array[Vector2i] = []
			for c in room.cells:
				if near_corr.has(c) or clear.has(c):
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
			var plan: Array[int] = []
			var scale := 1 + room.cells.size() / 60
			for _i in rng.randi_range(1, scale + 1):
				plan.append(Feature.ZIGGURAT if rng.randf() < 0.4 else Feature.PLATFORM)
			for _i in rng.randi_range(1 if room.index == 1 or rng.randf() < 0.6 else 0, scale + 1):
				plan.append(Feature.LEDGE)
			for _i in rng.randi_range(0, scale + 1):
				plan.append(Feature.PILLAR)
			for _i in rng.randi_range(1 if room.index % 3 == 1 else 0, scale):
				plan.append(Feature.PIT)
			var occupied := {}
			for kind in plan:
				for _try in 14:
					var c: Vector2i = keys[rng.randi_range(0, keys.size() - 1)]
					var fp := _footprint(kind, c)
					var ok := true
					for fc in fp:
						if not valid.has(fc) or occupied.has(fc):
							ok = false
							break
					if not ok:
						continue
					for fc in fp:
						occupied[fc] = true
						for d in Hex.DIRS:
							occupied[fc + d] = true
						if fp[fc] == PIT_MARK:
							map.cells.erase(fc)
							pits[fc] = true
						else:
							map.get_cell(fc).level = room.level + int(fp[fc])
					if kind == Feature.LEDGE:
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
		for c in reached:
			var cell: HexMap.Cell = map.cells[c]
			if cell.tag == "" and room_of.has(c):
				cell.tag = "room:%d" % room_of[c]
		map.cells[start].tag = "start"
		map.cells[exit_cell].tag = "exit"
		return true
