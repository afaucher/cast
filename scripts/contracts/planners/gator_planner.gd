class_name GatorPlanner
extends RefCounted
## SEWER PHASE 3 (docs/design/sewer-concept.md, "Phase 3 as built"): the gators of a floor's sewer cluster. plan() chooses
## them (spawn data in HexMap.sewer["gators"]: where each starts, its bask spots and its relocation seed) and keeps the
## packs out of their territory; spawn() puts them into the world after the sharks, so no earlier net id moves. On a floor
## without a cluster both return at once.
##
## The round-2 rules (user, 2026-10-20: billed property like the shark, territorial, moving now and then):
##   - one gator a cluster, two in a cluster of four rooms;
##   - it starts in a room's SUMP, the farthest from the stair first, at least EMPLOYEE_CLEAR from the staff and GATE_CLEAR
##     from a hellgate (else in the middle of a flooded hall); a second one at least APART from the first;
##   - its HOME REGION (Gator, spawn data): the cluster's water and its cells within Gator.HOME_REACH, never the stair or a
##     dry room;
##   - its BASK SPOTS: the other sumps, the middle of each flooded hall and one dry deck cell beside the water in each room
##     (never a doorway: DOOR_CLEAR), all in its region;
##   - no monster pack is placed within PACK_CLEAR of where it starts (SitePlan.blocked): the gator nips anything that lingers.
## Own dice (from the cluster's seed): nothing else on the floor moves.

const EMPLOYEE_CLEAR := 5
const GATE_CLEAR := 6
const APART := 8
const DOOR_CLEAR := 3
const PACK_CLEAR := 4
const FOUR_ROOMS := 4              ## a cluster this big gets a second gator

static var last_usec := 0


static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan) -> void:
	last_usec = 0
	var rec := SewerPlanner.record(map)
	if rec.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rec["seed"]) * 613 + floor_n * 41 + 7
	var region := region_of(map)
	var stair_door: Vector2i = rec["stair"]["door"]
	var count := 2 if (rec["rooms"] as Array).size() >= FOUR_ROOMS else 1
	# where they may start: the sumps, farthest from the stair first, then the middles of the flooded halls
	var starts: Array[Vector2i] = []
	var sumps: Array = (rec["sumps"] as Array).duplicate()
	sumps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := Hex.distance(a["cell"], stair_door)
		var db := Hex.distance(b["cell"], stair_door)
		return da > db or (da == db and SiteBuilder._cell_less(a["cell"], b["cell"])))
	for s: Dictionary in sumps:
		starts.append(s["cell"])
	var mids: Array[Vector2i] = []
	for h: Dictionary in rec["halls"]:
		var route: Array = h["route"]
		var mid: Vector2i = route[route.size() / 2]
		if map.water_at(Hex.to_world(mid)):
			mids.append(mid)
	starts.append_array(mids)
	# the bask spots every gator of the cluster shares
	var spots: Array[Vector2i] = []
	for s: Dictionary in rec["sumps"]:
		spots.append(s["cell"])
	spots.append_array(mids)
	var door_cells: Array = rec.get("all_doors", [])
	for t: String in rec["rooms"]:
		var deck := _deck_spot(map, p, t, region, door_cells, rng)
		if deck != HexMap.NO_CELL:
			spots.append(deck)
	var chosen: Array[Vector2i] = []
	for c in starts:
		if chosen.size() >= count:
			break
		if not region.has(c) or not _clear(p, c):
			continue
		var apart := true
		for o in chosen:
			apart = apart and Hex.distance(o, c) >= APART
		if apart:
			chosen.append(c)
	var out: Array = []
	for c in chosen:
		var at := ThemeGeo.world(c)
		var near := _nearest_door(c, door_cells)
		var face := (ThemeGeo.world(near) - at).normalized() if near != HexMap.NO_CELL else Vector2(0.0, 1.0)
		var mine: Array = []
		for s in spots:
			if s != c and region.has(s):
				mine.append(ThemeGeo.world(s))
		out.append({"at": at, "face": face, "spots": mine, "seed": int(rng.randi() & 0x3fffffff)})
		for n in Hex.range_cells(c, PACK_CLEAR):
			p.blocked[n] = true
	rec["gators"] = out
	last_usec = Time.get_ticks_usec() - t0


## The planned gators, after the sharks: the last actors of the floor.
static func spawn(map: HexMap, p: SitePlan, site: SiteBuilder.Site) -> void:
	var rec := SewerPlanner.record(map)
	if rec.is_empty() or GameWorld.root == null:
		return
	var region := region_of(map)
	for g: Dictionary in (rec.get("gators", []) as Array):
		var spots: Array[Vector2] = []
		for s: Vector2 in (g["spots"] as Array):
			spots.append(s)
		var gator := Gator.spawn(g["at"], g["face"], region, spots, int(g["seed"]))
		if gator != null:
			site.gators.append(gator)


## The gators' home region on this floor: the cluster's water (its body's cells) and every open cell of the cluster within
## Gator.HOME_REACH of it. {} without a cluster.
static func region_of(map: HexMap) -> Dictionary:
	var rec := SewerPlanner.record(map)
	if rec.is_empty():
		return {}
	var body: Dictionary = map.pools[int(rec["body"])]
	var ours := SewerPlanner._cluster_cells(map, rec)
	var dist := {}
	var frontier: Array[Vector2i] = []
	for c: Vector2i in (body["basin"] as Array) + (body["ring"] as Array):
		if not dist.has(c):
			dist[c] = 0
			frontier.append(c)
	for step in range(1, Gator.HOME_REACH + 1):
		var next: Array[Vector2i] = []
		for c in frontier:
			for d in Hex.DIRS:
				var n: Vector2i = c + d
				var cell: HexMap.Cell = map.get_cell(n)
				if dist.has(n) or cell == null or cell.type == HexMap.Tile.WALL or not ours.has(n):
					continue
				dist[n] = step
				next.append(n)
		frontier = next
	var region := {}
	for c: Vector2i in dist:
		region[c] = true
	return region


static func _clear(p: SitePlan, c: Vector2i) -> bool:
	for e in p.employees:
		if Hex.distance(e["cell"], c) < EMPLOYEE_CLEAR:
			return false
	for g in p.gates:
		if Hex.distance(g["cell"], c) < GATE_CLEAR:
			return false
	return true


## A dry full cell of room `tag` two steps from the water (beside it, not on the rim), out of the doorways, not on anything
## planned. NO_CELL if none.
static func _deck_spot(map: HexMap, p: SitePlan, tag: String, region: Dictionary, door_cells: Array, rng: RandomNumberGenerator) -> Vector2i:
	var taken := {}
	for e in p.employees:
		taken[e["cell"]] = true
	for nt in p.notes:
		taken[nt["cell"]] = true
	for pr in p.props + p.hazards:
		for n in Hex.range_cells(pr["cell"], 1):
			taken[n] = true
	for g in p.gates:
		for n in Hex.range_cells(g["cell"], 2):
			taken[n] = true
	var cand: Array[Vector2i] = []
	for c: Vector2i in (p.rooms[tag] as Array):
		if not region.has(c) or not map.is_walkable_cell(c) or map.is_pool_cell(c) or taken.has(c) or p.blocked.has(c):
			continue
		var beside := false
		for d in Hex.DIRS:
			beside = beside or map.is_pool_cell(c + d)
		if not beside:
			continue
		var by_door := false
		for dd: Vector2i in door_cells:
			by_door = by_door or Hex.distance(dd, c) < DOOR_CLEAR
		if not by_door:
			cand.append(c)
	if cand.is_empty():
		return HexMap.NO_CELL
	return cand[rng.randi_range(0, cand.size() - 1)]


static func _nearest_door(c: Vector2i, door_cells: Array) -> Vector2i:
	var best := HexMap.NO_CELL
	var best_d := 1 << 20
	for dd: Vector2i in door_cells:
		var d := Hex.distance(c, dd)
		if d < best_d:
			best_d = d
			best = dd
	return best
