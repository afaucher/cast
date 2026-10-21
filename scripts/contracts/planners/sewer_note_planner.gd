class_name SewerNotePlanner
extends RefCounted
## A sewer cluster's notes (docs/design/sewer-concept.md, C3 and "Polish as built"): the service level's own paperwork,
## through the notes system (SitePlan.notes, ClueNote, NoteCopy.SEWER filled from NoteFacts: {sewer_room} is the sewer theme
## row's word, {staff} a real employee of the floor). SiteBuilder.plan calls plan() right after NotePlanner (the floor's story
## note and hint slip keep their spots; the decor steers round these like any note). On a floor without a cluster it returns
## at once, so nothing moves.
##
## One note of each kind, each on a dry deck cell beside the water (within WATER_REACH of a pool cell), the cell nearest its
## anchor where a note fits (ThemeCtx.fits, like NotePlanner), at least APART from every other note and STAIR_CLEAR from the
## stair's foot (where SewerPlanner.dress puts its sign):
##   crossing  GATOR CROSSING, where a flooded hall's water meets a room (the cluster's first hall, else none)
##   rota      the gator's feeding rota, by the water in the stair's room (the first room the crew sees). No line yet (the
##             user, 2026-10-21, rejected the drafts): NoteCopy.SEWER["rota"] is empty, so none is placed
## A kind without a line places nothing.
##   pump      the pump log, beside a sump pump (HazardPlanner.plan_sewer: the room farthest from the stair; none without one)
##   drink     DO NOT DRINK by the outfall (the source), only where the stair's sign is not already the DO NOT DRINK one
## The line of each kind is picked on the cluster's own dice (its seed), so it is the same on every machine.

const WATER_REACH := 2       ## a note's cell is this close to the water (a deck or a ledge)
const APART := 4             ## ... and this far from every other note
const STAIR_CLEAR := 5       ## ... and from the stair's doorway (its foot keeps SewerPlanner's sign, 2-3 from it)
const ANCHOR_MAX := 9        ## a spot farther than this from its anchor is not "by" it
const KIND := "sewer"        ## the plan entry's kind (the floor's own notes are "story" and "hint")


static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan, ctx: ThemeCtx) -> void:
	var rec := SewerPlanner.record(map)
	if rec.is_empty() or ctx == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rec["seed"]) * 409 + floor_n * 71 + 5
	var facts := NoteFacts.from_plan(p, run)
	var st: Dictionary = rec["stair"]
	var stair_door: Vector2i = st["door"]
	var tags: Array = rec["rooms"]
	var wants: Array = []   # [kind, room, anchor]
	var halls: Array = rec["halls"]
	if not halls.is_empty():
		var h: Dictionary = halls[0]
		# the hall's end in the room farther from the stair (the crew meets it on the way in)
		var far_b := Hex.distance(h["door_b"], stair_door) >= Hex.distance(h["door_a"], stair_door)
		wants.append(["crossing", str(h["b"] if far_b else h["a"]), h["door_b"] if far_b else h["door_a"]])
	wants.append(["rota", str(st["room"]), _sump_of(rec, str(st["room"]), stair_door)])
	for pr in p.props:
		if str(pr["kind"]) == "sump_pump" and tags.has(str(pr["room"])):
			wants.append(["pump", str(pr["room"]), pr["cell"]])
			break
	if run.site_type != "bunker":   # (a bunker's stair sign is RECLAIMED WATER: DO NOT DRINK already)
		for e: Dictionary in (rec.get("ends", []) as Array):
			if str(e["kind"]) == "outfall":
				wants.append(["drink", str(e["room"]), e["cell"]])
	for w: Array in wants:
		var line := NoteCopy.pick(NoteCopy.SEWER[w[0]], facts, rng)   # (one roll per kind, in this order)
		if line.is_empty():
			continue
		var cell := _spot(map, p, ctx, str(w[1]), w[2], stair_door)
		if cell == SiteBuilder.NO_SPOT:
			continue
		var entry := NotePlanner._note_entry(p, ctx, run, facts, line, cell, KIND)
		entry["sewer"] = str(w[0])
		p.notes.append(entry)


## The room's sump cell (its gator's water), else `fallback`.
static func _sump_of(rec: Dictionary, tag: String, fallback: Vector2i) -> Vector2i:
	for s: Dictionary in (rec.get("sumps", []) as Array):
		if str(s["room"]) == tag:
			return s["cell"]
	return fallback


## The dry deck cell of room `tag` nearest `anchor` where a note fits (see the header). NO_SPOT when none.
static func _spot(map: HexMap, p: SitePlan, ctx: ThemeCtx, tag: String, anchor: Vector2i, stair_door: Vector2i) -> Vector2i:
	if not ctx.rooms.has(tag):
		return SiteBuilder.NO_SPOT
	var room: ThemeCtx.RoomInfo = ctx.rooms[tag]
	var best := SiteBuilder.NO_SPOT
	var best_d := ANCHOR_MAX + 1
	for c in room.cells:
		var cell: HexMap.Cell = map.get_cell(c)
		if cell == null or cell.type != HexMap.Tile.FLOOR or cell.tag != tag or not map.is_walkable_cell(c) or map.is_pool_cell(c):
			continue
		var d := Hex.distance(c, anchor)
		if d > best_d or (d == best_d and not SiteBuilder._cell_less(c, best)):
			continue
		if Hex.distance(c, stair_door) < STAIR_CLEAR or not _by_water(map, c):
			continue
		if not _clear(p, c) or not ctx.fits(room, ThemeGeo.world(c), 0.0, 0.9, 1.1):
			continue
		best = c
		best_d = d
	return best


static func _by_water(map: HexMap, c: Vector2i) -> bool:
	for n in Hex.range_cells(c, WATER_REACH):
		if map.is_pool_cell(n):
			return true
	return false


## Clear of every note (APART), employee, gate (3) and priced prop or hazard (2) already planned.
static func _clear(p: SitePlan, c: Vector2i) -> bool:
	for nt in p.notes:
		if Hex.distance(c, nt["cell"]) < APART:
			return false
	for e in p.employees:
		if Hex.distance(c, e["cell"]) < 2:
			return false
	for g in p.gates:
		if Hex.distance(c, g["cell"]) < 3:
			return false
	for pr in p.props + p.hazards:
		if Hex.distance(c, pr["cell"]) < 2:
			return false
	return true
