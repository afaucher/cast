class_name SewerPlanner
extends RefCounted
## SEWER PHASE 3 (docs/design/sewer-concept.md, "Phase 3 as built"): the water of a floor's sewer cluster. DungeonGen cut the
## cluster (its "sewer" option, SewerCluster: 2-4 rooms of a wing at one base level, their links flat, a service stair down
## into them) and left its record in HexMap.sewer; this planner floods it. On a floor without a cluster every step returns at
## once, so nothing on the floor moves.
##
## SiteBuilder.plan calls, in this order:
##   plan()       FIRST, right after the rooms are indexed and before the gates: the water is terrain, and its channels are
##                fixed by the doorways, so the gates, the staff and everything after them keep to the dry decks (they already
##                refuse pool cells). The wet cells (one level down: wading depth), the rims (PoolGeo's kite rule, water up to
##                the walls as in the slice), ONE body record in HexMap.pools ({"body": true}: Wading slows and soaks in it,
##                PoolView skips it), the flows, the sumps and the channel ends (in HexMap.sewer).
##   theme()      after RoomThemes.assign: the cluster's rooms take the RoomThemeDefs "sewer" row (the service level: its
##                floor and walls, its light, its note word, the wet-floor sign; no pool look), so PoolGeo never carves a
##                pool into one.
##   dress()      after the decor: a grate in each sump, an outfall at the source and iron bars at the other channel ends, a
##                sign at the foot of the service stair.
##   materials()  after FloorMaterials.assign: the cluster's own halls and the walls round it in the sewer's stone (its rooms
##                have theirs from the theme row).
##   plan_pack()  last, after the gators: the room and dry deck cells of its goo imp pack.
## SiteBuilder.spawn calls spawn() after the gators: the goo imp pack (MonsterFactory.spawn_sewer_pack), SewerView (the water, the foam, the kerbs, the channel bed in the look,
## only over this body) and a LiveWire on every electrical panel (HazardPlanner.plan_sewer placed them).
##
## THE WATER (the round-2 grammar, built for generated rooms):
##   - a room's channel: from each of its sewer doorways a hex line (or, where the line leaves the room, the shortest walk
##     through it) to a SUMP in its middle (radius 1; 2 in a big room). A room with ONE sewer doorway (the cluster's edge)
##     carries its channel on from the sump to the wall farthest from that doorway: the SOURCE (an outfall pouring in) in the
##     edge room farthest from the stair, a barred culvert in the others. So every room's water runs into its halls.
##   - a NARROW hall (3.0) is flooded wall to wall; a WIDE hall (4.5) floods its route row and the cut row beside it, and its
##     lane stays a 1.5 dry LEDGE (the proposal's default: fully flooded narrow halls, ledged wide ones).
##   - the service stair, its doorway and the cells within KEEP_DRY of it stay dry: the crew steps off the stair onto a deck.
##   - all of it is ONE connected body (test_sewer_gen); a room's water stays under WATER_CAP of its floor.
##   - no bridges (user, 2026-10-20): a deck cut off by a channel is reached by wading; every doorway is reachable.
## Its own dice are none: the layout follows from the cluster's geometry, so it is the same on every machine.

const THEME := RoomThemeDefs.SEWER
const KEEP_DRY := 2                 ## hex cells round the stair's doorway that stay dry (the stair foot's deck)
const SUMP_BIG := 140               ## a room with this many cells or more gets a radius-2 sump
const WATER_CAP := 0.45             ## the most of a room's floor (in kites) that may be water
const END_CLEAR := 3                ## a channel's end keeps this many cells from every doorway and hall
const SIGNS := {
	"bunker": "RECLAIMED WATER: DO NOT DRINK. It is reclaimed.",
	"lair": "DO NOT FEED THE GATOR",
}

## Microseconds the last floor's sewer planning took (plan + theme + dress + materials; not in SiteBuilder.last_plan_usec).
static var last_usec := 0


## The floor's cluster record (HexMap.sewer), {} when it has none or it is not flooded yet.
static func record(map: HexMap) -> Dictionary:
	return map.sewer if map != null and map.sewer.has("body") else {}


## Flood the cluster (see the header). First thing in SiteBuilder.plan, once the rooms are indexed.
static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan) -> void:
	last_usec = 0
	var rec := map.sewer
	if rec.is_empty() or rec.has("body"):
		return
	var t0 := Time.get_ticks_usec()
	var level := int(rec["level"])
	var tags: Array = rec["rooms"]
	var st: Dictionary = rec["stair"]
	var stair_door: Vector2i = st["door"]
	var keep_dry := {}
	for c in Hex.range_cells(stair_door, KEEP_DRY):
		keep_dry[c] = true
	var halls: Array = rec["halls"]
	var doors := {}
	for t: String in tags:
		doors[t] = [] as Array[Vector2i]
	for h: Dictionary in halls:
		(doors[h["a"]] as Array[Vector2i]).append(h["door_a"])
		(doors[h["b"]] as Array[Vector2i]).append(h["door_b"])
	# every doorway and hall cell of the floor (a channel's end keeps clear of them)
	var all_doors: Array[Vector2i] = (rec.get("all_doors", []) as Array).duplicate()
	var wet := {}
	for h: Dictionary in halls:
		for c in _hall_water(map, h):
			_wet(map, wet, c)
		h["flooded"] = "wall_to_wall" if bool(h["narrow"]) else "ledge"
	# the source: the edge room (one sewer doorway) farthest from the stair's room
	var hops := _hops(tags, halls, str(st["room"]))
	var source := ""
	for t: String in tags:
		if (doors[t] as Array).size() == 1 and (source == "" or int(hops[t]) > int(hops[source])):
			source = t
	var sumps: Array = []
	var ends: Array = []
	for t: String in tags:
		var room_cells := {}
		for c: Vector2i in (p.rooms[t] as Array):
			room_cells[c] = true
		var center := _sump_center(map, p, t, room_cells, keep_dry)
		var radius := 2 if room_cells.size() >= SUMP_BIG else 1
		var mine := {}
		var end := HexMap.NO_CELL
		while true:
			mine.clear()
			for c in Hex.range_cells(center, radius):
				if room_cells.has(c) and not keep_dry.has(c) and not _blocked(map, c):
					mine[c] = true
			for d: Vector2i in (doors[t] as Array[Vector2i]):
				for c in _channel(map, room_cells, center, d, keep_dry):
					mine[c] = true
			if (doors[t] as Array).size() == 1:
				end = _end_cell(map, t, room_cells, center, (doors[t] as Array[Vector2i])[0], all_doors, keep_dry)
				if end != HexMap.NO_CELL:
					for c in _channel(map, room_cells, center, end, keep_dry):
						mine[c] = true
			if radius == 0 or _share(map, mine, room_cells) <= WATER_CAP:
				break
			radius -= 1   # (over the cap: a smaller sump)
		for c: Vector2i in mine:
			_wet(map, wet, c)
		sumps.append({"room": t, "cell": center, "r": radius})
		if end != HexMap.NO_CELL:
			var into := ThemeGeo.world(center) - ThemeGeo.world(end)
			ends.append({"room": t, "cell": end, "kind": "outfall" if t == source else "bars", "into": into.normalized()})
	_apply(map, wet, level)
	var look := SewerCluster.look_for(run)
	var basin: Array[Vector2i] = []
	var ring: Array[Vector2i] = []
	for c: Vector2i in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if wet.has(c):
			basin.append(c)
		elif cell.pool_mask != 0 and _in_cluster(map, rec, c):
			ring.append(c)
	basin.sort_custom(SiteBuilder._cell_less)
	ring.sort_custom(SiteBuilder._cell_less)
	map.pools.append({
		"room": "", "look": "sewer_" + look, "body": true, "shape": "sewer", "basin": basin, "ring": ring, "outline": [],
		"hole": [], "center": Vector2.ZERO, "axis": Vector2.RIGHT, "half_wid": 0.0, "deck_level": level,
		"floor_level": level - 1, "surface_y": float(level - 1) * Hex.LEVEL_HEIGHT + HexMap.WATER_DEPTH,
	})
	rec["body"] = map.pools.size() - 1
	rec["look"] = look
	rec["sumps"] = sumps
	rec["ends"] = ends
	rec["source"] = source
	rec["flows"] = _flows(rec, source, sumps, ends)
	last_usec += Time.get_ticks_usec() - t0


## The cluster's rooms are sewer rooms (after RoomThemes.assign, before PoolGeo.carve).
static func theme(map: HexMap, p: SitePlan) -> void:
	var rec := record(map)
	if rec.is_empty():
		return
	for t: String in rec["rooms"]:
		p.room_themes[t] = THEME


## The sewer's dressing in the plan, after the decor (see the header).
static func dress(map: HexMap, run: ContractRun, p: SitePlan) -> void:
	var rec := record(map)
	if rec.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var level := int(rec["level"])
	var lh := Hex.LEVEL_HEIGHT
	for s: Dictionary in rec["sumps"]:
		var r := int(s["r"])
		_decor(map, p, "grate", ThemeGeo.world(s["cell"]), 15.0, {"size": 1.8 if r >= 2 else 1.4}, float(level - 1) * lh + 0.01)
	for e: Dictionary in rec["ends"]:
		var into: Vector2 = e["into"]
		var at := ThemeGeo.world(e["cell"])
		if str(e["kind"]) == "outfall":
			_decor(map, p, "outfall", at + into * 0.1, SewerLayouts.yaw_to(into), {"radius": 0.6, "drop": 1.0}, float(level) * lh)
		else:
			_decor(map, p, "bars", at, SewerLayouts.yaw_to(-into), {"width": 2.8, "height": 1.3}, float(level - 1) * lh)
	# the sign at the stair's foot, facing the crew coming down
	var st: Dictionary = rec["stair"]
	var door: Vector2i = st["door"]
	var spot := _sign_cell(map, p, str(st["room"]), door)
	if spot != HexMap.NO_CELL:
		var face := ThemeGeo.world(door) - ThemeGeo.world(spot)
		p.notes.append({"cell": spot, "text": str(SIGNS.get(run.site_type, SIGNS["bunker"])), "format": "sign", "header": "NOTICE",
				"kind": "hint", "yaw": SewerLayouts.yaw_to(face), "room": str(st["room"])})
	last_usec += Time.get_ticks_usec() - t0


## A sluice gate across a flooded narrow hall's doorway (DoorPlanner, in place of an office door): the decor kind "sluice",
## whatever its look is (DecorModels), standing on the doorway's line across the hall, its posts on the jambs.
static func sluice(map: HexMap, p: SitePlan, dw: Dictionary) -> void:
	var rec := record(map)
	if rec.is_empty():
		return
	var mid: Vector3 = dw["mid"]
	var axis: Vector3 = dw["axis"]
	var width := float(dw.get("width", 3.0))
	if width < 2.0 or width > 4.0:
		width = 3.0
	_decor(map, p, "sluice", Vector2(mid.x, mid.z), SewerLayouts.yaw_to(Vector2(axis.x, axis.z)), {"width": width, "open": 0.45},
			float(int(rec["level"])) * Hex.LEVEL_HEIGHT)


## The cluster's halls and walls in the sewer's stone (after FloorMaterials.assign; its rooms have the theme row's): its own
## halls corridor stone, the walls round it rough stone. (SewerView recolours none of them on a generated floor: the rest of
## the floor shares the material table.)
static func materials(map: HexMap, p: SitePlan) -> void:
	var rec := record(map)
	if rec.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var room_mat := FloorMaterials.pack(FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var hall_mat := FloorMaterials.pack(FloorMaterials.F_CORR_STONE, FloorMaterials.W_STONE)
	var mine := _cluster_cells(map, rec)
	for c: Vector2i in mine:
		if str(mine[c]) == "hall":
			map.cells[c].mat_id = hall_mat
	for c: Vector2i in mine:
		for d in Hex.DIRS:
			var nb: Vector2i = c + d
			var cell: HexMap.Cell = map.get_cell(nb)
			if cell == null or cell.type != HexMap.Tile.WALL:
				continue
			var only_ours := true
			for d2 in Hex.DIRS:
				var o: HexMap.Cell = map.get_cell(nb + d2)
				if o != null and o.type != HexMap.Tile.WALL and not mine.has(nb + d2):
					only_ours = false
					break
			if only_ours:
				cell.mat_id = room_mat
	last_usec += Time.get_ticks_usec() - t0


## The cluster's own monster pack (the goo imps: MonsterFactory's sewer packs, MonsterDefs "sewer_pack"), planned last in
## SiteBuilder.plan (after the gators, so it keeps out of their territory): a room of the cluster (not the stair's, when
## another has room), and its dry cells beside the water (a deck or a ledge over a channel: the goo imps refuse to step into
## water), clear of everything planned and of the stair's foot. Spawn data in HexMap.sewer["pack"] {room, cells, seed}; the
## cluster's own dice. Nothing without a cluster or a sewer kind.
static func plan_pack(map: HexMap, floor_n: int, p: SitePlan) -> void:
	var rec := record(map)
	if rec.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	rec["pack"] = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rec["seed"]) * 827 + floor_n * 53 + 3
	var stair: Dictionary = rec["stair"]
	var door: Vector2i = stair["door"]
	var by_room := {}
	for t: String in rec["rooms"]:
		var cells: Array[Vector2i] = []
		for c: Vector2i in (p.rooms[t] as Array):
			var cell: HexMap.Cell = map.cells[c]
			if cell.type != HexMap.Tile.FLOOR or not map.is_walkable_cell(c) or map.is_pool_cell(c) or p.blocked.has(c):
				continue
			if Hex.distance(c, door) <= PACK_STAIR_CLEAR or not _near_pool(map, c, PACK_WATER_REACH):
				continue
			cells.append(c)
		if cells.size() >= PACK_MIN_CELLS:
			by_room[t] = cells
	var rooms: Array = by_room.keys()
	if rooms.size() > 1:
		rooms.erase(str(stair["room"]))
	if rooms.is_empty():
		return
	rooms.sort()
	var t: String = rooms[rng.randi_range(0, rooms.size() - 1)]
	rec["pack"] = {"room": t, "cells": by_room[t], "seed": int(rng.randi() & 0x3fffffff)}
	last_usec += Time.get_ticks_usec() - t0


const PACK_STAIR_CLEAR := 4         ## the pack keeps this far from the stair's foot (the crew steps off there)
const PACK_WATER_REACH := 2         ## its cells are this close to the water: a deck or a ledge over a channel
const PACK_MIN_CELLS := 6


static func _near_pool(map: HexMap, c: Vector2i, r: int) -> bool:
	for n in Hex.range_cells(c, r):
		if map.is_pool_cell(n):
			return true
	return false


## The cluster's goo imp pack (plan_pack), then the look over the water (SewerView, this body only) and a live wire on every
## electrical panel. After the gators: the pack's monsters are the floor's last actors.
static func spawn(map: HexMap, run: ContractRun, p: SitePlan, site: SiteBuilder.Site) -> void:
	var rec := record(map)
	if rec.is_empty() or GameWorld.root == null:
		return
	var pack: Dictionary = rec.get("pack", {})
	if not pack.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = int(pack["seed"])
		var cells: Array[Vector2i] = []
		for c: Vector2i in (pack["cells"] as Array):
			cells.append(c)
		for m in MonsterFactory.spawn_sewer_pack(cells, rng):
			site.monsters.append(m)
			if run.pest == "everything" or run.pest == m.kind:
				site.pest_spawned += 1
	var host := GameWorld.root.get_parent()
	var terrain: HexMapView = host.get_node_or_null("Terrain") as HexMapView if host != null else null
	site.sewer_view = SewerView.dress_body(GameWorld.root, map, terrain, map.pools[int(rec["body"])], str(rec["look"]), rec["flows"])
	for pr in site.props:
		var pp := pr as PricedProp
		if pp == null or pp.kind != "electrical_panel":
			continue
		var drop := LiveWire.drop_point_for(map, Vector2(pp.global_position.x, pp.global_position.z), pp.facing_vector())
		if drop != Vector3.INF:
			site.wires.append(LiveWire.attach(pp, drop, site.sewer_view))


# --- the water ---------------------------------------------------------------------------------------------------------

## A hall's water: a narrow hall wall to wall; a wide one its route row and the cut row beside it (not the lane side, which
## stays a dry ledge).
static func _hall_water(map: HexMap, h: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cells: Array = h["cells"]
	if bool(h["narrow"]):
		for c: Vector2i in cells:
			out.append(c)
		return out
	var route := {}
	for c: Vector2i in (h["route"] as Array):
		route[c] = true
	var lanes := {}
	for c: Vector2i in (h["lanes"] as Array):
		lanes[c] = true
	for c: Vector2i in cells:
		if route.has(c):
			out.append(c)
			continue
		if lanes.has(c):
			continue
		var by_route := false
		var by_lane := false
		for d in Hex.DIRS:
			by_route = by_route or route.has(c + d)
			by_lane = by_lane or lanes.has(c + d)
		if by_route and not by_lane:
			out.append(c)
	return out


static func _blocked(map: HexMap, c: Vector2i) -> bool:
	var cell: HexMap.Cell = map.get_cell(c)
	return cell == null or cell.type == HexMap.Tile.WALL or cell.wall_mask == HexMap.ALL_KITES


static func _wet(map: HexMap, wet: Dictionary, c: Vector2i) -> void:
	if not _blocked(map, c):
		wet[c] = true


## The room's sump: its centre, or the full cell nearest it that keeps clear of the stair's foot.
static func _sump_center(map: HexMap, p: SitePlan, tag: String, room_cells: Dictionary, keep_dry: Dictionary) -> Vector2i:
	var c0: Vector2i = p.centers[tag]
	if map.is_walkable_cell(c0) and not _near(c0, keep_dry, 1):
		return c0
	var best := c0
	var best_d := 1 << 20
	var keys: Array = room_cells.keys()
	keys.sort_custom(SiteBuilder._cell_less)
	for c: Vector2i in keys:
		if not map.is_walkable_cell(c) or _near(c, keep_dry, 1):
			continue
		var d := Hex.distance(c, c0)
		if d < best_d:
			best_d = d
			best = c
	return best


static func _near(c: Vector2i, cells: Dictionary, r: int) -> bool:
	for n in Hex.range_cells(c, r):
		if cells.has(n):
			return true
	return false


## The channel's cells from `a` to `b` inside a room: the hex line, or the shortest walk through the room's floor when the
## line leaves it or crosses the stair's foot.
static func _channel(map: HexMap, room_cells: Dictionary, a: Vector2i, b: Vector2i, keep_dry: Dictionary) -> Array[Vector2i]:
	var line := Hex.line(a, b)
	var ok := true
	for c in line:
		if not room_cells.has(c) or keep_dry.has(c) or _blocked(map, c):
			ok = false
			break
	if ok:
		return line
	for full_only: bool in [true, false]:
		var path := _walk(map, room_cells, a, b, keep_dry, full_only)
		if not path.is_empty():
			return path
	return [] as Array[Vector2i]


## Breadth-first through the room's cells (full cells only, or any open cell), never through the stair's foot.
static func _walk(map: HexMap, room_cells: Dictionary, a: Vector2i, b: Vector2i, keep_dry: Dictionary, full_only: bool) -> Array[Vector2i]:
	var came := {a: a}
	var queue: Array[Vector2i] = [a]
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		if c == b:
			var path: Array[Vector2i] = [b]
			while path[0] != a:
				path.push_front(came[path[0]])
			return path
		for d in Hex.DIRS:
			var nb: Vector2i = c + d
			if came.has(nb) or not room_cells.has(nb) or keep_dry.has(nb) or _blocked(map, nb):
				continue
			if full_only and nb != b and not map.is_walkable_cell(nb):
				continue
			came[nb] = c
			queue.append(nb)
	return [] as Array[Vector2i]


## Where an edge room's channel runs on to: a cut cell on the room's wall (the water runs up to it), at least END_CLEAR from
## every doorway and hall and out of the stair's foot, as far as can be from the doorway it came in by. NO_CELL if none.
static func _end_cell(map: HexMap, tag: String, room_cells: Dictionary, center: Vector2i, in_door: Vector2i,
		all_doors: Array[Vector2i], keep_dry: Dictionary) -> Vector2i:
	var best := HexMap.NO_CELL
	var best_s := -INF
	var keys: Array = room_cells.keys()
	keys.sort_custom(SiteBuilder._cell_less)
	for c: Vector2i in keys:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type == HexMap.Tile.WALL or cell.wall_mask == 0 or cell.wall_mask == HexMap.ALL_KITES:
			continue
		if _near(c, keep_dry, END_CLEAR - KEEP_DRY + 1):
			continue
		var clear := true
		for dd in all_doors:
			if Hex.distance(dd, c) < END_CLEAR:
				clear = false
				break
		if clear:
			for n in Hex.range_cells(c, END_CLEAR - 1):
				var nc: HexMap.Cell = map.get_cell(n)
				if nc != null and nc.tag == "corridor":
					clear = false
					break
		if not clear:
			continue
		var s := 2.0 * Hex.distance(c, in_door) + Hex.distance(c, center)
		if s > best_s:
			best_s = s
			best = c
	return best


## The share of a room's floor (in kites) the water would take: the wet cells, and a third of each dry cell beside them.
static func _share(map: HexMap, mine: Dictionary, room_cells: Dictionary) -> float:
	var water := 0.0
	var floor_n := 0
	for c: Vector2i in room_cells:
		if _blocked(map, c):
			continue
		floor_n += 1
		if mine.has(c):
			water += 1.0
			continue
		var k := 0
		for d in 6:
			if mine.has(c + Hex.DIRS[d]):
				k += 2
		water += minf(k, 6) / 6.0
	return water / maxf(1.0, float(floor_n))


## Sink the wet cells one level (the channel floor) and give each dry cell beside them its pool kites (PoolGeo's rule: a wet
## neighbour d makes kites d - 1 and d water; wall kites stay wall), so every rim runs on a midpoint line.
static func _apply(map: HexMap, wet: Dictionary, level: int) -> void:
	var keys: Array = wet.keys()
	keys.sort_custom(SiteBuilder._cell_less)
	var rim := {}
	for c: Vector2i in keys:
		var cell: HexMap.Cell = map.cells[c]
		cell.level = level - 1
		cell.pool_level = level - 1
		cell.pool_mask = HexMap.ALL_KITES & ~cell.wall_mask
		for d in Hex.DIRS:
			var nb: Vector2i = c + d
			if not wet.has(nb):
				rim[nb] = true
	var rims: Array = rim.keys()
	rims.sort_custom(SiteBuilder._cell_less)
	for c: Vector2i in rims:
		var cell: HexMap.Cell = map.get_cell(c)
		if cell == null or cell.type == HexMap.Tile.WALL:
			continue
		var m := 0
		for d in 6:
			if wet.has(c + Hex.DIRS[d]):
				m |= (1 << d) | (1 << posmod(d - 1, 6))
		m &= ~cell.wall_mask
		if m != 0:
			cell.pool_mask = m
			cell.pool_level = level - 1


## Room -> hops from `from` over the cluster's halls.
static func _hops(tags: Array, halls: Array, from: String) -> Dictionary:
	var hops := {from: 0}
	var queue: Array[String] = [from]
	var qi := 0
	while qi < queue.size():
		var t := queue[qi]
		qi += 1
		for h: Dictionary in halls:
			var o := ""
			if str(h["a"]) == t:
				o = str(h["b"])
			elif str(h["b"]) == t:
				o = str(h["a"])
			if o != "" and not hops.has(o):
				hops[o] = int(hops[t]) + 1
				queue.append(o)
	for t: String in tags:
		if not hops.has(t):
			hops[t] = 0
	return hops


## The cluster's cells: room cells "room", its own halls' cells "hall" (not the stair's).
static func _cluster_cells(map: HexMap, rec: Dictionary) -> Dictionary:
	var out := {}
	var rooms := {}
	for t: String in rec["rooms"]:
		rooms[t] = true
	for c: Vector2i in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type != HexMap.Tile.WALL and rooms.has(cell.tag):
			out[c] = "room"
	for h: Dictionary in rec["halls"]:
		for c: Vector2i in (h["cells"] as Array):
			out[c] = "hall"
	return out


static func _in_cluster(map: HexMap, rec: Dictionary, c: Vector2i) -> bool:
	var cell: HexMap.Cell = map.get_cell(c)
	if cell == null:
		return false
	if (rec["rooms"] as Array).has(cell.tag):
		return true
	for h: Dictionary in rec["halls"]:
		if (h["cells"] as Array).has(c):
			return true
	return false


## The flow lines (cosmetic: SewerView's streaks), from the source downstream: each hall from the room nearer the source,
## each room's channels from its upstream doorway in to the sump and out to the others, the source's from its outfall.
static func _flows(rec: Dictionary, source: String, sumps: Array, ends: Array) -> Array:
	var from := source if source != "" else str((rec["rooms"] as Array)[0])
	var hops := _hops(rec["rooms"], rec["halls"], from)
	var out: Array = []
	for h: Dictionary in rec["halls"]:
		var route: Array = h["route"]
		var pl := PackedVector2Array()
		for c: Vector2i in route:
			pl.append(ThemeGeo.world(c))
		if int(hops[h["b"]]) < int(hops[h["a"]]):
			pl.reverse()
		out.append(pl)
	var centers := {}
	for s: Dictionary in sumps:
		centers[s["room"]] = s["cell"]
	for h: Dictionary in rec["halls"]:
		for side: Array in [[h["a"], h["door_a"], h["b"]], [h["b"], h["door_b"], h["a"]]]:
			var t: String = side[0]
			var door: Vector2i = side[1]
			var inflow := int(hops[side[2]]) < int(hops[t])
			var pl := PackedVector2Array([ThemeGeo.world(door), ThemeGeo.world(centers[t])])
			if not inflow:
				pl.reverse()
			out.append(pl)
	for e: Dictionary in ends:
		var pl := PackedVector2Array([ThemeGeo.world(e["cell"]), ThemeGeo.world(centers[e["room"]])])
		if str(e["kind"]) != "outfall":
			pl.reverse()
		out.append(pl)
	return out


# --- the dressing ------------------------------------------------------------------------------------------------------

## A decor piece in the plan (as SewerLayouts.plan writes them): `y` is where the model's origin stands.
static func _decor(map: HexMap, p: SitePlan, kind: String, pos: Vector2, yaw: float, params: Dictionary, y: float) -> void:
	var ground := map.ground_height(Vector3(pos.x, 0.0, pos.y))
	var lift := 0.0 if is_nan(y) or is_nan(ground) else y - ground
	var dm: Dictionary = RoomThemeDefs.decor(kind)
	var cell := ThemeGeo.cell_of(pos)
	p.decor.append({"kind": kind, "pos": pos, "yaw": yaw, "cell": cell, "room": p.room_of_cell(cell),
			"place": str(dm.get("place", "wall")), "orient": str(dm.get("orient", "free")), "group": -1, "role": "",
			"blocks": bool(dm.get("blocks", false)), "w": float(dm.get("w", 1.0)), "d": float(dm.get("d", 1.0)), "lift": lift,
			"target": pos, "params": params, "block_points": [pos], "block_radius": 0.45})


## The sign's cell: a dry full cell of the stair's room two or three steps in from its doorway, clear of everything planned.
static func _sign_cell(map: HexMap, p: SitePlan, tag: String, door: Vector2i) -> Vector2i:
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
	var best := HexMap.NO_CELL
	for r: int in [2, 3]:
		var ring := Hex.ring(door, r)
		ring.sort_custom(SiteBuilder._cell_less)
		for c in ring:
			var cell: HexMap.Cell = map.get_cell(c)
			if cell == null or cell.tag != tag or not map.is_walkable_cell(c) or map.is_pool_cell(c) or taken.has(c):
				continue
			if cell.type != HexMap.Tile.FLOOR:
				continue
			return c
	return best
