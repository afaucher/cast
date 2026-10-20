class_name NotePlanner
extends RefCounted
## The clue notes of a floor (ClueNote, docs/design/notes-rethink.md): plan() picks the story note, the hint slip and the
## dispatch banner line (SitePlan.notes / SitePlan.dispatch) on dice of their own, spawn() puts the notes into the world.
## SiteBuilder.plan / spawn call them; moved out of SiteBuilder verbatim (refactor plan H8).


const NOTE_YAW_SPREAD := 60.0           ## a note turns at most this far from the camera to face its room's door


## Two notes a floor (docs/design/notes-rethink.md): the client's STORY note (floor 1 near the start, floor 2 in a
## room about halfway to the elevator, floor 3 in the origin room by its door) and a HINT slip in a side room. The
## text is picked from NoteCopy and filled from this floor's facts (NoteFacts), so hints are true here; lines whose
## facts the floor lacks are dropped. Also picks the dispatch banner line (p.dispatch). Draws from its OWN generator
## (seeded from the floor seed), so it never moves a gate, prop, decor piece or pack.
static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan, ctx: ThemeCtx) -> void:
	if p.start_room == "":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = run.floor_seed(floor_n) * 613 + floor_n * 29 + 11
	var facts := NoteFacts.from_plan(p, run)
	var origin := str(run.story.get("origin", ""))
	# the story note
	var story := NoteCopy.pick(NoteCopy.story_lines(run.archetype_id, floor_n, origin), facts, rng)
	if story.is_empty():   # this floor lacks every fact its lines need: the client's floor-1 lines, then the pest ticket
		story = NoteCopy.pick(NoteCopy.story_lines(run.archetype_id, 1, origin), facts, rng)
	if story.is_empty():
		story = NoteCopy.hint_lines("pest", run.pest)[0]
	var story_room := _story_note_room(p, floor_n)
	var story_cell := _note_spot(map, p, ctx, story_room, floor_n == 1, [])
	if story_cell == SiteBuilder.NO_SPOT:
		for tag in [story_room] + _hint_note_rooms(p, story_room):
			story_cell = _note_spot(map, p, ctx, tag, false, [])
			if story_cell != SiteBuilder.NO_SPOT:
				break
	if not story.is_empty() and story_cell != SiteBuilder.NO_SPOT:
		p.notes.append(_note_entry(p, ctx, run, facts, story, story_cell, "story"))
	# the hint slip: the first kind (in this floor's order) the facts allow and the story note did not give
	var given := NoteCopy.kinds_of(str(story.get("t", "")))
	var hint: Dictionary = {}
	for kind: String in NoteCopy.HINT_ORDER.get(clampi(floor_n, 1, 3), ["pest"]):
		if given.has(kind):
			continue
		hint = NoteCopy.pick(NoteCopy.hint_lines(kind, run.pest), facts, rng)
		if not hint.is_empty():
			break
	var taken: Array[Vector2i] = []
	if story_cell != SiteBuilder.NO_SPOT:
		taken.append(story_cell)
	var hint_cell := SiteBuilder.NO_SPOT
	for tag in _hint_note_rooms(p, story_room):
		hint_cell = _note_spot(map, p, ctx, tag, false, taken)
		if hint_cell != SiteBuilder.NO_SPOT:
			break
	if not hint.is_empty() and hint_cell != SiteBuilder.NO_SPOT:
		p.notes.append(_note_entry(p, ctx, run, facts, hint, hint_cell, "hint"))
	# the dispatch banner line
	var dispatch_lines: Array = []
	for t: String in NoteCopy.DISPATCH.get(clampi(floor_n, 1, 3), []):
		dispatch_lines.append({"f": "dispatch", "t": t})
	var d := NoteCopy.pick(dispatch_lines, facts, rng)
	p.dispatch = NoteCopy.fill(str(d.get("t", "")), facts)


static func _note_entry(p: SitePlan, ctx: ThemeCtx, run: ContractRun, facts: Dictionary, line: Dictionary, cell: Vector2i, kind: String) -> Dictionary:
	# face the room's door, so the front of a sign or an easel greets whoever walks in, but never turned more than
	# NOTE_YAW_SPREAD away from the game camera, so the front (the text, the stripes) stays readable on screen
	var yaw := SiteBuilder.CAMERA_YAW
	var room := ctx.room_of(cell)
	if room != null:
		var to := room.entrance_w - ThemeGeo.world(cell)
		if to.length() > 0.01:
			var door_yaw := rad_to_deg(atan2(to.x, to.y))
			yaw = SiteBuilder.CAMERA_YAW + clampf(wrapf(door_yaw - SiteBuilder.CAMERA_YAW, -180.0, 180.0), -NOTE_YAW_SPREAD, NOTE_YAW_SPREAD)
	return {"cell": cell, "text": NoteCopy.fill(str(line["t"]), facts), "format": str(line["f"]),
		"header": NoteCopy.header_of(line, run.archetype_id, facts), "kind": kind, "yaw": yaw, "room": p.room_of_cell(cell)}


## Floor 1: the start room. Floor 3: the origin room. Floor 2: the room whose centre is nearest halfway between
## the start and the exit (not the start or exit room). Falls back to the start room.
static func _story_note_room(p: SitePlan, floor_n: int) -> String:
	if floor_n >= ContractRun.FLOOR_COUNT and p.origin_room != "":
		return p.origin_room
	if floor_n == 1:
		return p.start_room
	var best := ""
	var best_score := 1 << 30
	for tag: String in SiteBuilder._room_tags(p):
		if tag == p.start_room or tag == p.exit_room or tag == p.origin_room:
			continue
		var c: Vector2i = p.centers[tag]
		var score := absi(Hex.distance(c, p.start) - Hex.distance(c, p.exit)) * 2 + Hex.distance(c, p.start) + Hex.distance(c, p.exit)
		if score < best_score:
			best_score = score
			best = tag
	return best if best != "" else p.start_room


## Rooms for the hint slip, best first: side rooms (the biggest detour off the start-exit line), never the start,
## exit or origin room or the story note's room; then those as a last resort.
static func _hint_note_rooms(p: SitePlan, story_room: String) -> Array[String]:
	var side: Array[String] = []
	var rest: Array[String] = []
	for tag: String in SiteBuilder._room_tags(p):
		if tag == p.start_room or tag == p.exit_room or tag == p.origin_room or tag == story_room:
			rest.append(tag)
		else:
			side.append(tag)
	var line := Hex.distance(p.start, p.exit)
	side.sort_custom(func(a: String, b: String) -> bool:
		var ca: Vector2i = p.centers[a]
		var cb: Vector2i = p.centers[b]
		var da := Hex.distance(ca, p.start) + Hex.distance(ca, p.exit) - line
		var db := Hex.distance(cb, p.start) + Hex.distance(cb, p.exit) - line
		return da > db or (da == db and int(a.trim_prefix("room:")) < int(b.trim_prefix("room:"))))
	side.append_array(rest)
	return side


## A free spot for a note in room `tag`: flat room floor where a 0.9 x 1.1 note fits (clear of the gate zone,
## corridors, the start / exit clear zones, the van, employees and priced props), at least 4 cells from any
## `taken` note. Near the start (`by_start`, floor 1: 4-8 cells from the start cell, about 5 preferred), otherwise
## the spot nearest the room's door, so it is seen on the way in. SiteBuilder.NO_SPOT if the room has none.
static func _note_spot(map: HexMap, p: SitePlan, ctx: ThemeCtx, tag: String, by_start: bool, taken: Array[Vector2i]) -> Vector2i:
	if not ctx.rooms.has(tag):
		return SiteBuilder.NO_SPOT
	var room: ThemeCtx.RoomInfo = ctx.rooms[tag]
	var cells: Array[Vector2i] = room.cells.duplicate()
	if by_start:
		for c in Hex.range_cells(p.start, 8):
			if not cells.has(c) and p.room_of_cell(c) != "":
				cells.append(c)
	var best := SiteBuilder.NO_SPOT
	var best_score := -(1 << 30)
	for c in cells:
		var cell: HexMap.Cell = map.get_cell(c)
		if cell == null or cell.type != HexMap.Tile.FLOOR or not cell.tag.begins_with("room:") or not map.is_walkable_cell(c):
			continue
		var cr := ctx.room_of(c)
		if cr == null or not ctx.fits(cr, ThemeGeo.world(c), 0.0, 0.9, 1.1):
			continue
		if VanPlan.near(p.van, ThemeGeo.world(c), 0.9, 1.1, 1.0):
			continue    # not under the van or in front of its door
		var far := true
		for t in taken:
			if Hex.distance(c, t) < 4:
				far = false
		if not far:
			continue
		var score := 0
		if by_start:
			var d := Hex.distance(c, p.start)
			if d < 4 or d > 8 or cell.level != int(p.base_levels.get(p.start_room, cell.level)):
				continue
			score = -absi(d - 5) * 2
		else:
			score = -Hex.distance(c, room.entrance)
		if score > best_score or (score == best_score and SiteBuilder._cell_less(c, best)):
			best_score = score
			best = c
	return best


## The planned notes, in plan order.
static func spawn(map: HexMap, run: ContractRun, p: SitePlan, site: SiteBuilder.Site) -> void:
	for nt in p.notes:
		var note := ClueNote.make(nt, run.archetype_id)
		GameWorld.spawn(note, Hex.to_world(nt["cell"], float(map.get_cell(nt["cell"]).level) + 0.0))
		site.notes.append(note)
