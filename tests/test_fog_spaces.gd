extends MonsterTestBase
## Fog SPACES audit (docs/design/fog-spaces-audit.md). The user, 2026-10-20: "I think it is a question of how the planner
## makes lobes of a multi-segment room. Lets double check the results" and "every dimension of a room should make sense as
## the visibility limit of the player because standing just outside and looking across means that the shortest distance
## across might be where the fog starts". Read-only: no generator code and no floor changes; it builds contract floors
## 1-3 for fixed run seeds (DungeonGen.for_run) and the five lava caves (LavaCave), and checks what Doorways / RoomFog make
## of them.
##
## ASSERTED (what must hold):
##   1. one connected room is one space: every "room:N" tag's cells are in one space, and that space's floor is one
##      connected piece (the lava caves' archer isles, the fog link over the lava and the rim are left out: they share a
##      space on purpose);
##   2. no untagged room bit (a cell only a climb reaches) ends up in a hall's or another room's space;
##   3. every doorway sits at its opening: on floor, at that floor's height, next to a corridor cell and a cell of its room.
##   4b. no room has a neck (WAIST below): the generator's opening keeps lobed rooms one blob;
##   7b. one-sided visibility stays under VIS_ONE_SIDED_MAX of the sampled pairs on every map.
## MEASURED (printed as a table, "FOG SPACE |", one row per space; flagged against the thresholds below):
##   4. REACH: per doorway, how far the space runs from the doorway's middle (flat distance to its farthest standable
##      cell), and how far a hero standing just outside that doorway actually sees into it (the farthest cell in line of
##      sight). The space shows WHOLE the moment it is in view, so a reach beyond RoomFog.DOOR_SIGHT (14) reveals what
##      the hero could not plausibly see from there;
##   5. WAIST: the narrowest cross-section of the space along its own length (the cells at one walking distance from one
##      end of it) against its typical cross-section: a narrow neck in the middle says the space is really two lobes;
##   6. COVERAGE: the share of the space's standable cells a hero just outside each doorway has in line of sight (the
##      worst doorway is reported): low coverage means stepping into view shows a room the hero can't see most of;
##   7. one-sided VISIBILITY between adjacent spaces, sampled (two standable spots in each other's sight, in spaces joined
##      by a doorway: does each see the other's space?), with the reason.

const RUN_SEEDS: Array[int] = [3, 7, 12, 26, 37, 42]
const EYE := 1.1
const OUTSIDE := 1.2            ## "just outside" a doorway: this far past its middle, along its axis
const SAMPLE_PER_SPACE := 12
## Flags.
const REACH_MAX := 21.0   ## a space running farther than this from a doorway: past the game camera's half width (size 24: 42.7 x 24 on screen)
const WAIST_RATIO := 0.45               ## the narrowest cross-section under this share of the typical one ...
const WAIST_MIN_LENGTH := 6             ## ... in a space at least this many steps long: a neck between lobes
const COVERAGE_MIN := 0.6               ## seen from just outside its worst doorway, less than this share
const VIS_ONE_SIDED_MAX := 0.03         ## ASSERTED: one-sided pairs per map, at most this share of the sampled ones
const HALL_REACH_CUT := 26.0            ## ASSERTED with long halls cut: no hall space runs farther than this from a doorway


func setup() -> void:
	timeout_sec = 900.0
	# halls whole (as before 2026-10-20), then cut into segments (RoomFog.split_long_halls, the game since: "Turn it on")
	var was := RoomFog.split_long_halls
	for split: bool in [false, true]:
		RoomFog.split_long_halls = split
		var mode := "cut halls" if split else "halls whole"
		print("FOG MODE | ", mode)
		var rows: Array = []
		for s in RUN_SEEDS:
			var run := ContractBoard.run_for_seed(s)
			for f in range(1, ContractRun.FLOOR_COUNT + 1):
				rows.append_array(_audit("seed %d floor %d" % [s, f], DungeonGen.for_run(run, f), {}))
		for id in range(1, LavaCave.COUNT + 1):
			rows.append_array(_audit("cave %d" % id, LavaCave.build_map(id), _cave_skip(id)))
		_summary(rows, mode)
		if split:
			print("FOG CUTS | %d cuts | nearest real doorway cell %d steps | no-flicker spots %d (%d differ) | walks %d, revealed up to %d segment(s) ahead, %d looks 3+ ahead" % [
					_cuts["cuts"], _cuts["clear_min"], _cuts["spots"], _cuts["flicker"], _cuts["walks"], _cuts["lead"], _cuts["far"]])
	RoomFog.split_long_halls = was
	finish()


## LONG HALLS totals over every map (cut mode).
var _cuts := {"cuts": 0, "clear_min": 99, "spots": 0, "flicker": 0, "walks": 0, "lead": 0, "far": 0}


## LONG HALLS, asserted on every map: each cut sits on the floor between its two segments, at least 2 steps from any real
## doorway's cells (a cut never draws over a doorway or its door); a hero on a cut sees the same from either side (no
## flicker; nudged 0.01 each way: a bigger move can carry some other doorway across DOOR_SIGHT, as any step can); walking a cut hall end to end, the next segment always shows, and nothing 3 or more segments ahead is seen
## unless through a room (a room's doorway into a farther segment).
func _audit_cuts(label: String, m: HexMap, fog: RoomFog) -> void:
	var real: Array[Vector2i] = []
	for dw in fog.doorways:
		if fog.is_cut(int(dw["id"])):
			continue
		real.append_array(dw["door_cells"] as Array[Vector2i])
		real.append_array(dw["mouth_cells"] as Array[Vector2i])
		for c: Vector2i in dw.get("band", []):
			real.append(c)
		if dw.has("cell"):
			real.append(dw["cell"])
	for dw in fog.doorways:
		var id := int(dw["id"])
		if not fog.is_cut(id):
			continue
		_cuts["cuts"] = int(_cuts["cuts"]) + 1
		var ri := int(dw["ri"])
		var hi := int(dw["hi"])
		var ok := true
		for c: Vector2i in dw["door_cells"]:
			ok = ok and fog.space_of_cell(c) == ri
		for c: Vector2i in dw["mouth_cells"]:
			ok = ok and fog.space_of_cell(c) == hi
		var mid: Vector3 = dw["mid"]
		var g := m.ground_height(mid)
		check(ok and fog.hall_group[ri] == fog.hall_group[hi], "%s cut %d (%s|%s) joins two segments of one hall" % [label, id, fog.tags[ri], fog.tags[hi]])
		check(not is_nan(g) and absf(g - mid.y) < 0.6, "%s cut %d on the floor: mid %s" % [label, id, mid.snapped(Vector3.ONE * 0.01)])
		var clear := 99
		for c: Vector2i in (dw["door_cells"] as Array[Vector2i]) + (dw["mouth_cells"] as Array[Vector2i]):
			for r in real:
				clear = mini(clear, Hex.distance(c, r))
		_cuts["clear_min"] = mini(int(_cuts["clear_min"]), clear)
		check(clear >= 2, "%s cut %d keeps off real doorways (%d steps)" % [label, id, clear])
		# no flicker
		for a: Vector2i in dw["door_cells"]:
			for d in Hex.DIRS:
				var b: Vector2i = a + d
				if not (dw["mouth_cells"] as Array).has(b) or not m.is_walkable_cell(a) or not m.is_walkable_cell(b):
					continue
				var pa := top(m, a)
				var pb := top(m, b)
				var step := (pb - pa).normalized() * 0.01
				var views: Array = []
				for p: Vector3 in [(pa + pb) * 0.5 - step, (pa + pb) * 0.5 + step]:
					fog.seen.fill(0)
					fog.update([p])
					views.append(fog.view.duplicate())
				_cuts["spots"] = int(_cuts["spots"]) + 1
				if views[0] != views[1]:
					_cuts["flicker"] = int(_cuts["flicker"]) + 1
					check(false, "%s cut %d between %s and %s: the same in view either side" % [label, id, a, b])
	# walks, one per cut hall
	var groups := {}
	for s in fog.space_count():
		if fog.segmented[s] == 1:
			groups[fog.hall_group[s]] = true
	for gid: int in groups:
		var segs := fog.hall_segments(gid)
		var corr: Array[Vector2i] = []
		for c: Vector2i in fog.cell_space:
			if segs.has(fog.space_of_cell(c)) and m.cells[c].tag == "corridor" and standable_cell(m, c):
				corr.append(c)
		if corr.size() < 2:
			continue
		corr.sort()
		var e0 := RoomFog._walk_far(corr, corr[0])[0] as Vector2i
		var e1 := RoomFog._walk_far(corr, e0)[0] as Vector2i
		var path := _walk_path(corr, e0, e1)
		var rank := {}
		for c in path:
			var s := fog.space_of_cell(c)
			if segs.has(s) and not rank.has(s):
				rank[s] = rank.size()
		_cuts["walks"] = int(_cuts["walks"]) + 1
		fog.seen.fill(0)
		fog.state.fill(0)
		for c in path:
			fog.update([top(m, c)])
			var k := int(rank.get(fog.space_of_cell(c), -1))
			if k < 0:
				continue
			for s: int in rank:
				var ahead := int(rank[s]) - k
				if ahead == 1:
					check(fog.state_of(s) >= RoomFog.NEXT, "%s walk down %s at %s: the next segment shows" % [label, fog.tags[gid], c])
				if ahead < 1 or fog.state_of(s) < RoomFog.SEEN:
					continue
				_cuts["lead"] = maxi(int(_cuts["lead"]), ahead)
				if ahead >= 3:
					var by_room := false
					for l: Array in fog.links[s]:
						by_room = by_room or (not fog.is_hall[int(l[0])] and fog.state_of(int(l[0])) >= RoomFog.SEEN)
					_cuts["far"] = int(_cuts["far"]) + 1
					check(by_room, "%s walk down %s at %s: segment %s, %d ahead, seen only through a room" % [label, fog.tags[gid], c, fog.tags[s], ahead])


static func standable_cell(m: HexMap, c: Vector2i) -> bool:
	var cell: HexMap.Cell = m.cells[c]
	return m.is_walkable_cell(c) and cell.tag != "rim" and cell.tag != "lava" and cell.tag != "isle" and cell.level != LavaCave.LAVA_BED and not m.is_lava(c)


## The shortest walk from `a` to `b` over `cells`.
static func _walk_path(cells: Array[Vector2i], a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var inside := {}
	for c in cells:
		inside[c] = true
	var parent := {a: a}
	var queue: Array[Vector2i] = [a]
	var i := 0
	while i < queue.size():
		var cur := queue[i]
		i += 1
		if cur == b:
			break
		for d in Hex.DIRS:
			var n: Vector2i = cur + d
			if inside.has(n) and not parent.has(n):
				parent[n] = cur
				queue.append(n)
	if not parent.has(b):
		return [a]
	var out: Array[Vector2i] = [b]
	while out[0] != a:
		out.push_front(parent[out[0]])
	return out


## A lava cave's cells that are no standable part of a space: the archers' isles (no path), the lava, the rim.
static func _cave_skip(id: int) -> Dictionary:
	var skip := {}
	for il: Array in LavaCave.layout(id)["isles"]:
		for c in Hex.range_cells(il[1], int(il[2])):
			skip[c] = true
	return skip


## The standable cells of each space: {space index: Array[Vector2i]} (no wall, no lava, no rim, nothing in `skip`).
static func standable(m: HexMap, fog: RoomFog, skip: Dictionary) -> Dictionary:
	var out := {}
	for c: Vector2i in fog.cell_space:
		var cell: HexMap.Cell = m.cells[c]
		# (a generated lava cave's isles are out of reach on purpose and its lava is no floor: test_lava_gen's)
		if skip.has(c) or not m.is_walkable_cell(c) or cell.tag == "rim" or cell.tag == "lava" or cell.tag == "isle" or cell.level == LavaCave.LAVA_BED or m.is_lava(c):
			continue
		var s := fog.space_of_cell(c)
		if not out.has(s):
			out[s] = [] as Array[Vector2i]
		(out[s] as Array[Vector2i]).append(c)
	for s: int in out:
		(out[s] as Array[Vector2i]).sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out


static func top(m: HexMap, c: Vector2i) -> Vector3:
	return Hex.to_world(c, float(m.cells[c].level))


func _audit(label: String, m: HexMap, skip: Dictionary) -> Array:
	var fog := RoomFog.build(m)
	var cells := standable(m, fog, skip)
	# 1. a room is one space, in one piece
	var frag: Array[String] = []
	var rooms := {}
	for c: Vector2i in m.cells:
		var tag: String = m.cells[c].tag
		if tag.begins_with("room:") and not skip.has(c):
			if not rooms.has(tag):
				rooms[tag] = {}
			(rooms[tag] as Dictionary)[fog.space_of_cell(c)] = true
	for tag: String in rooms:
		check((rooms[tag] as Dictionary).size() == 1, "%s: %s's cells are all in one space (%s)" % [label, tag, (rooms[tag] as Dictionary).keys()])
	for s: int in cells:
		var with_links: Array[Vector2i] = (cells[s] as Array[Vector2i]).duplicate()
		for c: Vector2i in fog.cell_space:
			if int(fog.cell_space[c]) == s and m.cells[c].tag == "corridor" and (m.cells[c].level == LavaCave.LAVA_BED or m.is_lava(c)):
				with_links.append(c)   # (a lava cave's fog link between parallel walkways: one space on purpose)
		var pieces := _pieces(with_links)
		if pieces > 1:
			frag.append("%s in %d pieces" % [fog.tags[s], pieces])
	check(frag.is_empty(), "%s: every space's floor is one connected piece%s" % [label, (": " + ", ".join(frag)) if not frag.is_empty() else ""])
	# 2. no untagged room bit in another space
	var stray: Array[String] = []
	for c: Vector2i in m.cells:
		var cell: HexMap.Cell = m.cells[c]
		if cell.type == HexMap.Tile.WALL or cell.tag != "" or not fog.cell_space.has(c):
			continue
		var votes := {}
		for d in Hex.DIRS:
			var nc: HexMap.Cell = m.cells.get(c + d)
			if nc != null and nc.tag.begins_with("room:"):
				votes[nc.tag] = int(votes.get(nc.tag, 0)) + 1
		var home := ""
		for t: String in votes:
			if home == "" or int(votes[t]) > int(votes[home]):
				home = t
		if home != "" and fog.tags[fog.space_of_cell(c)] != home:
			stray.append("%s %s (lv %d) in %s, beside %s" % [label, c, cell.level, fog.tags[fog.space_of_cell(c)], home])
	check(stray.is_empty(), "%s: no untagged room bit ends up in another space%s" % [label, (": " + "; ".join(stray.slice(0, 6))) if not stray.is_empty() else ""])
	# 3. doorways at their openings
	for dw in fog.doorways:
		if dw.get("split", false):
			continue   # (a cut between segments of one long hall: _audit_cuts)
		var mid: Vector3 = dw["mid"]
		var g := m.ground_height(mid)
		var near_corr := false
		var near_room := false
		for c in Hex.range_cells(Hex.from_world(mid), 1):
			var cell: HexMap.Cell = m.cells.get(c)
			if cell != null:
				near_corr = near_corr or cell.tag == "corridor"
				near_room = near_room or cell.tag == dw["room"]
		check(not is_nan(g) and absf(g - mid.y) < 0.6 and near_corr and near_room, "%s doorway %d (%s/%s) at its opening: mid %s, floor %.2f" % [label, dw["id"], dw["room"], dw["hall"], mid.snapped(Vector3.ONE * 0.01), g])
	# 4-6. per space
	var rows: Array = []
	for s: int in cells:
		rows.append(_space_row(label, m, fog, s, cells[s]))
	# 7. one-sided visibility, sampled
	var vis := _visibility(m, fog, cells, label)
	print("FOG VIS %s | pairs %d | one-sided %d (%.1f %%) | %s" % [label, vis["pairs"], vis["one_sided"], 100.0 * float(vis["one_sided"]) / maxf(1.0, float(vis["pairs"])), vis["why"]])
	for ex: String in vis["examples"]:
		print("FOG VIS EXAMPLE ", ex)
	check(float(vis["one_sided"]) <= VIS_ONE_SIDED_MAX * float(maxi(1, int(vis["pairs"]))), "%s: one-sided visibility between adjacent spaces at most %.0f %% of sampled pairs (%d of %d)" % [label, VIS_ONE_SIDED_MAX * 100.0, vis["one_sided"], vis["pairs"]])
	for r: Array in rows:
		if str(r[1]).begins_with("room:"):
			check(not (r[2] as Array).has("WAIST"), "%s: %s has no neck (a room is not two lobes in one space): waist %d of %d" % [label, r[1], r[5], r[6]])
		elif RoomFog.split_long_halls:
			check(float(r[4]) <= HALL_REACH_CUT, "%s: %s, cut, runs at most %.0f from a doorway (%.1f)" % [label, r[1], HALL_REACH_CUT, r[4]])
	if RoomFog.split_long_halls:
		_audit_cuts(label, m, fog)
	return rows


## One space's numbers: reach (farthest standable cell from each doorway's middle; the farthest a hero just outside
## sees), waist (narrowest cross-section along the space against its median), coverage (the share seen from just
## outside the worst doorway). Prints the table row; returns [label, tag, flags].
func _space_row(label: String, m: HexMap, fog: RoomFog, s: int, cells: Array[Vector2i]) -> Array:
	var reach_any := 0.0
	var reach_seen := 0.0
	var coverage := 1.0
	var worst_dw := -1
	for l: Array in fog.links[s]:
		var dw: Dictionary = fog.doorways[int(l[1])]
		var mid: Vector3 = dw["mid"]
		var into_hall := int(dw["hi"]) == s
		# just outside: on the other side of the opening (the contact cells there, a little back from the middle), looking
		# in. (Not the doorway's `axis`: in a lava cave whose two walkways are one hall it points across the lava.)
		var other_side: Array[Vector2i] = dw["door_cells"] if into_hall else dw["mouth_cells"]
		var oc := Vector3.ZERO
		for c in other_side:
			oc += Hex.to_world(c)
		oc /= float(other_side.size())
		var back := Vector3(oc.x - mid.x, 0, oc.z - mid.z)
		var out_pos: Vector3 = oc + (back.normalized() * (OUTSIDE - back.length()) if back.length() < OUTSIDE and back.length() > 0.01 else Vector3.ZERO)
		var g := m.ground_height(out_pos)
		if is_nan(g):
			out_pos = oc
			g = m.ground_height(oc)
		var eye := Vector3(out_pos.x, (mid.y if is_nan(g) else g) + EYE, out_pos.z)
		var seen := 0
		for c in cells:
			var p := top(m, c)
			var dist := Vector2(p.x - mid.x, p.z - mid.z).length()
			reach_any = maxf(reach_any, dist)
			if m.line_of_sight(eye, p + Vector3.UP * 0.6):
				seen += 1
				reach_seen = maxf(reach_seen, dist)
		var share := float(seen) / float(maxi(1, cells.size()))
		if share < coverage:
			coverage = share
			worst_dw = int(l[1])
	var w := waist(cells)
	var flags: Array[String] = []
	if reach_any > REACH_MAX:
		flags.append("REACH")
	if int(w["length"]) >= WAIST_MIN_LENGTH and float(w["waist"]) < WAIST_RATIO * float(w["median"]):
		flags.append("WAIST")
	if coverage < COVERAGE_MIN:
		flags.append("COVERAGE")
	print("FOG SPACE | %s | %s | %d cells | reach %.1f (seen %.1f) | waist %d of %d across, %d long | coverage %.0f %% (doorway %d) | %s" % [label,
			fog.tags[s], cells.size(), reach_any, reach_seen, int(w["waist"]), int(w["median"]), int(w["length"]), coverage * 100.0, worst_dw,
			",".join(flags) if not flags.is_empty() else "-"])
	return [label, fog.tags[s], flags, cells.size(), reach_any, int(w["waist"]), int(w["median"]), int(w["length"]), coverage]


## The space's length and cross-sections: from one end of it (the cell farthest from any cell, twice over), the cells at
## each walking distance (hex steps within the space) form a cross-section. {length (steps), waist (the smallest
## cross-section in the middle 60 %), median (the median cross-section), at (the walking distance of the waist)}.
static func waist(cells: Array[Vector2i]) -> Dictionary:
	if cells.size() < 3:
		return {"length": 0, "waist": cells.size(), "median": cells.size(), "at": 0}
	var a := _far(cells, cells[0])[0] as Vector2i
	var r := _far(cells, a)
	var dist: Dictionary = r[1]
	var length: int = r[2]
	var bands: Array[int] = []
	bands.resize(length + 1)
	for c: Vector2i in dist:
		bands[int(dist[c])] += 1
	# A NECK: a cross-section narrower than the widest one before it AND the widest one after it (a convex room's
	# cross-sections only grow and then shrink, so it has none). Reported against the smaller of those two.
	var best_ratio := 1.0
	var waist_n := 0
	var around := 0
	var at := 0
	var lo := int(floor(length * 0.15))
	var hi := int(ceil(length * 0.85))
	for d in range(lo, hi + 1):
		var before := 0
		for k in range(0, d + 1):
			before = maxi(before, bands[k])
		var after := 0
		for k in range(d, length + 1):
			after = maxi(after, bands[k])
		var side := mini(before, after)
		var ratio := float(bands[d]) / float(maxi(1, side))
		if ratio < best_ratio:
			best_ratio = ratio
			waist_n = bands[d]
			around = side
			at = d
	if best_ratio >= 1.0:
		var sorted := bands.duplicate()
		sorted.sort()
		waist_n = sorted[sorted.size() - 1]
		around = waist_n
	return {"length": length, "waist": waist_n, "median": around, "at": at}


## Breadth first over `cells` from `from`: [the farthest cell, {cell: steps}, its steps].
static func _far(cells: Array[Vector2i], from: Vector2i) -> Array:
	var inside := {}
	for c in cells:
		inside[c] = true
	var dist := {from: 0}
	var queue: Array[Vector2i] = [from]
	var i := 0
	var far := from
	while i < queue.size():
		var cur := queue[i]
		i += 1
		if int(dist[cur]) > int(dist[far]):
			far = cur
		for d in Hex.DIRS:
			var n: Vector2i = cur + d
			if inside.has(n) and not dist.has(n):
				dist[n] = int(dist[cur]) + 1
				queue.append(n)
	return [far, dist, int(dist[far])]


static func _pieces(cells: Array[Vector2i]) -> int:
	var left := {}
	for c in cells:
		left[c] = true
	var n := 0
	for c in cells:
		if not left.has(c):
			continue
		n += 1
		var queue: Array[Vector2i] = [c]
		left.erase(c)
		var i := 0
		while i < queue.size():
			var cur := queue[i]
			i += 1
			for d in Hex.DIRS:
				if left.has(cur + d):
					left.erase(cur + d)
					queue.append(cur + d)
	return n


## Pairs of standable spots in spaces joined by a doorway, within DOOR_SIGHT and in each other's line of sight: does
## each see the other's space? {pairs, one_sided, why: {reason: count}, examples}.
func _visibility(m: HexMap, fog: RoomFog, cells: Dictionary, label: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(label)
	var sample := {}
	for s: int in cells:
		var list: Array[Vector2i] = cells[s]
		var pick: Array[Vector2i] = []
		for i in mini(SAMPLE_PER_SPACE, list.size()):
			pick.append(list[rng.randi_range(0, list.size() - 1)])
		sample[s] = pick
	var seen_from := {}
	for s: int in sample:
		for c: Vector2i in sample[s]:
			fog.seen.fill(0)
			fog.update([top(m, c)])
			seen_from[c] = fog.state.duplicate()
	var pairs := 0
	var one := 0
	var why := {}
	var examples: Array[String] = []
	for dw in fog.doorways:
		var a := int(dw["ri"])
		var b := int(dw["hi"])
		if not sample.has(a) or not sample.has(b):
			continue
		for p: Vector2i in sample[a]:
			for q: Vector2i in sample[b]:
				var pp := top(m, p)
				var qq := top(m, q)
				if Vector2(pp.x - qq.x, pp.z - qq.z).length() > RoomFog.DOOR_SIGHT or not m.line_of_sight(pp + Vector3.UP * EYE, qq + Vector3.UP * EYE):
					continue
				pairs += 1
				var pb: bool = (seen_from[p] as PackedByteArray)[b] == RoomFog.IN_VIEW
				var qa: bool = (seen_from[q] as PackedByteArray)[a] == RoomFog.IN_VIEW
				if pb == qa:
					continue
				one += 1
				var blind := p if not pb else q
				var reason := _why_blind(m, fog, blind, b if blind == p else a)
				why[reason] = int(why.get(reason, 0)) + 1
				if examples.size() < 3:
					examples.append("%s: %s (%s) and %s (%s) see each other; %s doesn't have the other's space in view: %s" % [label, p, fog.tags[a], q, fog.tags[b], blind, reason])
	return {"pairs": pairs, "one_sided": one, "why": why, "examples": examples}


static func _why_blind(m: HexMap, fog: RoomFog, c: Vector2i, other: int) -> String:
	var here := fog.space_of_cell(c)
	var p := top(m, c)
	var dws := fog.doorways_between(here, other)
	if dws.is_empty():
		return "no direct doorway"
	if fog.is_cut(dws[0]):
		return "a cut of a long hall hidden from it"
	for dw_id in dws:
		var mid: Vector3 = fog.doorways[dw_id]["mid"]
		if Vector2(mid.x - p.x, mid.z - p.z).length() <= RoomFog.DOOR_SIGHT:
			return "doorway hidden from it (round a lobe or a wall corner, or behind a step)"
	return "doorway beyond DOOR_SIGHT"


func _summary(rows: Array, mode: String) -> void:
	var n := rows.size()
	var counts := {"REACH": 0, "WAIST": 0, "COVERAGE": 0}
	for r: Array in rows:
		for f: String in r[2]:
			counts[f] = int(counts[f]) + 1
	print("FOG SUMMARY | %s | %d spaces | reach over %.0f: %d | waist under %.0f %% of typical: %d | coverage under %.0f %%: %d" % [mode, n, REACH_MAX,
			counts["REACH"], WAIST_RATIO * 100.0, counts["WAIST"], COVERAGE_MIN * 100.0, counts["COVERAGE"]])
	# the distributions, rooms and halls apart (to set the thresholds on)
	for kind: String in ["room", "hall"]:
		var reach: Array[float] = []
		var ratio: Array[float] = []
		var cover: Array[float] = []
		for r: Array in rows:
			if not str(r[1]).begins_with(kind):
				continue
			reach.append(float(r[4]))
			ratio.append(float(r[5]) / maxf(1.0, float(r[6])) if int(r[7]) >= WAIST_MIN_LENGTH else 1.0)
			cover.append(float(r[8]))
		reach.sort()
		ratio.sort()
		cover.sort()
		print("FOG DIST %s | %ss (%d) | reach p50 %.1f p90 %.1f p95 %.1f max %.1f | waist ratio p5 %.2f p10 %.2f p50 %.2f min %.2f | coverage p5 %.2f p10 %.2f p50 %.2f min %.2f" % [
				mode, kind, reach.size(), _pct(reach, 0.5), _pct(reach, 0.9), _pct(reach, 0.95), reach[-1], _pct(ratio, 0.05), _pct(ratio, 0.1), _pct(ratio, 0.5), ratio[0],
				_pct(cover, 0.05), _pct(cover, 0.1), _pct(cover, 0.5), cover[0]])


static func _pct(sorted: Array[float], q: float) -> float:
	return sorted[clampi(int(round(q * float(sorted.size() - 1))), 0, sorted.size() - 1)]
