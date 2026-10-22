class_name RoomFog
extends RefCounted
## ROOM FOG (docs/design/exploration.md, "Decisions: map information, fog and doors", 2026-10-19): what
## the crew knows of a floor, per SPACE (a room, or a hall: one corridor; Doorways), not per cell. Pure logic, built from the
## map alone; deterministic, no rng. Presentation reads it (FogView); nothing in the simulation does.
##
## STATES (per space), from least to most known:
##   UNKNOWN  dark: nothing drawn.
##   NEXT     its LAYOUT is drawn (floor and walls), nothing in it: a space next to one the crew knows (in view now or seen
##            before), and a room one hall away from a known room (the room at the other end of the corridor; not past a
##            long hall cut into segments, see LONG HALLS).
##   SEEN     was in view at some point: layout and its static props (furniture, notes, mail, gates), dimmed. Never anything
##            that moves (monsters, employees, pickups): no last-known ghosts.
##   IN_VIEW  everything in it shows.
##
## IN VIEW, for each hero (shared reveal: the union over the whole crew, so one hero's sight is everyone's):
##   1. the space the hero stands in;
##   2. THROUGH A DOORWAY: a space beyond a doorway of the hero's space whose door is open (or that has none), when the
##      doorway's middle is within DOOR_SIGHT of the hero and in line of sight from its eyes (HexMap.line_of_sight: walls,
##      and shut doors as blockers). One more doorway on (two hops: a room seen down a short straight corridor) on the
##      same terms, measured from the hero. A cut between two segments of a long hall is seen through on the same terms
##      but costs no hop (LONG HALLS);
##   3. VANTAGE: a hero standing VANTAGE_LEVELS (2) or more above its ROOM's floor (a crate tier, a ledge) sees into every
##      space next to that room through an open doorway or an archway, however far (never past a shut door).
## SEEN is sticky: once in view, always at least seen. NEXT follows from what is known; nothing un-sees.
##
## DECISIONS (user, 2026-10-19, after playing the fog lab): look A, the black void, is the game's only look ("that is
## perfect"; B and C stay in the lab); a seen room shows its props as they are now (live); no vantage through a shut door.
##
##   var fog := RoomFog.build(map)
##   fog.set_shut(doorway_id, true)            # a door shut (OfficeDoor tells it)
##   fog.update([hero_a.global_position, ...]) # true when any state changed
##   fog.state_at(pos), fog.shows_contents(pos), fog.shows_static(pos)

signal changed

enum { UNKNOWN, NEXT, SEEN, IN_VIEW }

const NAMES := ["unknown", "next", "seen", "in_view"]
const DOOR_SIGHT := 14.0        ## a doorway this close (flat, from the hero) can be seen through
const EYE := 1.1                ## sight is traced from this far above a hero's feet ...
const DOOR_EYE := 0.9           ## ... to this far above the doorway's floor
const VANTAGE_LEVELS := 2       ## this many levels above the room's floor is a vantage
const HOPS := 2                 ## doorways seen through in a row (the hero's space -> next -> the one after)

var map: HexMap
var tags: Array[String] = []           ## space index -> its tag ("room:3", "hall:0")
var is_hall: Array[bool] = []
var base_level: Array[int] = []        ## the space's modal floor level
var cell_space: Dictionary = {}        ## Vector2i -> space index (floor cells only)
var doorways: Array[Dictionary] = []   ## Doorways.find(): {id, room, hall, mid, axis, a, b, ok, ...} + "ri", "hi" (space indices)
var links: Array = []                  ## space index -> Array of [other space index, doorway id]
var shut: Dictionary = {}              ## doorway id -> true while its door is shut
var state: PackedByteArray = PackedByteArray()
var seen: PackedByteArray = PackedByteArray()
var view: PackedByteArray = PackedByteArray()
var updates := 0                       ## how many update() calls changed something (tests, the lab's numbers)
var hall_group: Array[int] = []        ## space index -> the hall it belongs to (itself, or the hall a long one was cut from); -1: a room
var segmented: PackedByteArray = PackedByteArray()   ## space index -> 1: a segment of a hall that was cut (LONG HALLS)

## LONG HALLS (docs/design/fog-spaces-audit.md; user, 2026-10-20: "Turn it on"). A hall is one space however long, so the
## moment a hero saw into a corridor the whole of it showed: up to 78 units of winding corridor on the audited floors,
## three times the camera's half width. build() cuts a hall of SEGMENT_STEPS * 2 or more steps into SEGMENTS of about
## SEGMENT_STEPS steps, each its own space ("hall:4", "hall:4.1", ...), joined by CUTS: doorways without doors
## ("split": true), appended after Doorways.find's so every door keeps its doorway id. A cut keeps CUT_CLEAR steps from
## every real doorway (and its door) and off the foot of a drop, and a segment is one connected piece (a branching hall's
## band can be two). FogView draws a cut as a soft feather across the hall, not a line.
##   - Sight crosses a cut like a doorway (DOOR_SIGHT and line of sight from the hero) but it costs no hop: the segments
##     are still one corridor. So a hero on either side of a cut sees the same (no flicker), and the hall shows about one
##     segment ahead of the crew.
##   - NEXT: the segment past a known one; a known room marks only the segment at its doorway (an uncut hall still marks
##     the room at its far end).
## Runtime only: Doorways.find, the doors, the floor plan and its checksum are untouched. Off (false): the halls whole.
static var split_long_halls := true
const SEGMENT_STEPS := 8               ## about 14 units of corridor (DOOR_SIGHT) per segment
const CUT_CLEAR := 3                   ## no cut within this many steps of a real doorway's cells
const MIN_SEGMENT := 4                 ## no segment shorter than this many steps
const DROP_LEVELS := 3                 ## no cut this many levels (1.5) or more below the floor ...
const DROP_CLEAR := 2                  ## ... within this many steps of it (the foot of a drop)


## Who may write each var (see Net). Fog is presentation, computed on every machine from the map (SPAWN data) and what it
## already has: every hero's position (theirs or a puppet's) and every door's state. A late joiner starts with what it sees.
func net_fields() -> Dictionary:
	return {
		"map": Net.LOCAL, "tags": Net.LOCAL, "is_hall": Net.LOCAL, "base_level": Net.LOCAL, "cell_space": Net.LOCAL,
		"doorways": Net.LOCAL, "links": Net.LOCAL, "shut": Net.LOCAL, "state": Net.LOCAL, "seen": Net.LOCAL,
		"view": Net.LOCAL, "updates": Net.LOCAL, "hall_group": Net.LOCAL, "segmented": Net.LOCAL,
	}


static func build(m: HexMap) -> RoomFog:
	var f := RoomFog.new()
	f.map = m
	var sp := Doorways.spaces(m)
	var index := {}
	for tag: String in sp["order"]:
		index[tag] = f.tags.size()
		f.tags.append(tag)
		f.is_hall.append(sp["kind"][tag] == "hall")
		var counts := {}
		var best := 0
		var best_n := -1
		for c: Vector2i in (sp["cells"][tag] as Array[Vector2i]):
			var lv: int = m.cells[c].level
			counts[lv] = int(counts.get(lv, 0)) + 1
			if int(counts[lv]) > best_n or (int(counts[lv]) == best_n and lv < best):
				best_n = int(counts[lv])
				best = lv
		f.base_level.append(best)
		f.links.append([])
	for c: Vector2i in sp["cell_space"]:
		f.cell_space[c] = index[sp["cell_space"][c]]
	f.doorways = Doorways.find(m, sp)
	for dw in f.doorways:
		dw["ri"] = index[dw["room"]]
		dw["hi"] = index[dw["hall"]]
		(f.links[dw["ri"]] as Array).append([dw["hi"], dw["id"]])
		(f.links[dw["hi"]] as Array).append([dw["ri"], dw["id"]])
	for s in f.tags.size():
		f.hall_group.append(s if f.is_hall[s] else -1)
	if split_long_halls:
		f._split_halls(m)
	# A door's cells go to the space on their side of its line (a hero in front of a shut door is in the space in front).
	Doorways.settle(m, f.cell_space, f.doorways, "ri", "hi")
	var n := f.tags.size()
	f.segmented.resize(n)
	var group_size := {}
	for s in n:
		group_size[f.hall_group[s]] = int(group_size.get(f.hall_group[s], 0)) + 1
	for s in n:
		f.segmented[s] = 1 if f.hall_group[s] >= 0 and int(group_size[f.hall_group[s]]) > 1 else 0
	f.state.resize(n)
	f.seen.resize(n)
	f.view.resize(n)
	return f


func space_count() -> int:
	return tags.size()


func index_of(tag: String) -> int:
	return tags.find(tag)


## The space a world point is in (-1 off the floor: a wall, the void outside).
func space_at(pos: Vector3) -> int:
	return int(cell_space.get(Hex.from_world(pos), -1))


func space_of_cell(c: Vector2i) -> int:
	return int(cell_space.get(c, -1))


func state_of(space: int) -> int:
	return int(state[space]) if space >= 0 and space < state.size() else UNKNOWN


func state_at(pos: Vector3) -> int:
	return state_of(space_at(pos))


## Monsters, employees, pickups, anything that moves: only in a space in view.
func shows_contents(pos: Vector3) -> bool:
	return state_at(pos) == IN_VIEW


## Furniture, notes, mail, gates (things that stay put): in view, or seen before (dimmed by the view).
func shows_static(pos: Vector3) -> bool:
	return state_at(pos) >= SEEN


func set_shut(doorway_id: int, is_shut: bool) -> void:
	if is_shut:
		shut[doorway_id] = true
	else:
		shut.erase(doorway_id)


func is_open(doorway_id: int) -> bool:
	return not shut.has(doorway_id)


## The doorways between two spaces (usually one).
func doorways_between(a: int, b: int) -> Array[int]:
	var out: Array[int] = []
	if a < 0 or a >= links.size():
		return out
	for l: Array in links[a]:
		if int(l[0]) == b:
			out.append(int(l[1]))
	return out


## Recompute the states from where the crew's heroes stand (feet positions). True when anything changed.
func update(viewers: Array) -> bool:
	var n := tags.size()
	view.fill(0)
	for v: Variant in viewers:
		_see_from(v as Vector3)
	var next := PackedByteArray()
	next.resize(n)
	for s in n:
		if view[s] == 1:
			seen[s] = 1
	for s in n:
		if seen[s] == 0:
			continue
		for l: Array in links[s]:
			var o := int(l[0])
			next[o] = 1
			# A known room: the room at the other end of each of its halls has its layout too. Not down a cut hall:
			# there the segment at the doorway is next, and each further one once the one before it is known.
			if not is_hall[s] and is_hall[o] and segmented[o] == 0:
				for l2: Array in links[o]:
					next[int(l2[0])] = 1
	var changed_any := false
	for s in n:
		var st := IN_VIEW if view[s] == 1 else (SEEN if seen[s] == 1 else (NEXT if next[s] == 1 else UNKNOWN))
		if state[s] != st:
			state[s] = st
			changed_any = true
	if changed_any:
		updates += 1
		changed.emit()
	return changed_any


## The spaces of hall `o`: itself, or every segment of the hall it was cut from (in space order).
func hall_segments(o: int) -> Array[int]:
	var out: Array[int] = []
	var g := hall_group[o] if o >= 0 and o < hall_group.size() else -1
	if g < 0:
		out.append(o)
		return out
	for s in hall_group.size():
		if hall_group[s] == g:
			out.append(s)
	return out


## Whether doorway `id` is a cut between two segments of a long hall.
func is_cut(id: int) -> bool:
	return id >= 0 and id < doorways.size() and bool(doorways[id].get("split", false))


## LONG HALLS: cut every hall of SEGMENT_STEPS * 2 or more walking steps into segments. The walking distance runs from one
## end of the hall (the corridor cell farthest from its first cell, then the one farthest from that); the cuts fall at
## even shares of it, each moved up to 5 steps to keep CUT_CLEAR from a real doorway and off the foot of a drop (or left out). A segment is a band of
## distance, one connected piece of it: the first piece keeps the hall's space index and tag, the rest are new spaces
## ("hall:3.1", ...). A room's doorway leads into the piece holding its mouth; each patch where two pieces touch is a cut
## (a doorway without a door, its middle on the floor between them, its axis from the nearer piece to the farther).
func _split_halls(m: HexMap) -> void:
	var halls: Array[int] = []
	for s in tags.size():
		if is_hall[s]:
			halls.append(s)
	for s in halls:
		# the hall's own corridor cells set the segments; the cells that only took its space (Doorways.spaces' fill: a
		# lava cave's lava) go with the segment of the nearest corridor cell
		var cells: Array[Vector2i] = []
		var filled: Array[Vector2i] = []
		for c: Vector2i in cell_space:
			if int(cell_space[c]) != s or m.cells[c].type == HexMap.Tile.WALL:
				continue
			if m.cells[c].tag == "corridor":
				cells.append(c)
			else:
				filled.append(c)
		if cells.size() < 3:
			continue
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		var end := _walk_far(cells, cells[0])[0] as Vector2i
		var r := _walk_far(cells, end)
		var dist: Dictionary = r[1]
		var length: int = r[2]
		if length < SEGMENT_STEPS * 2:
			continue
		# the distances of this hall's real doorway cells (and door cells): no cut next to them
		var blocked := {}
		for dw in doorways:
			if int(dw["hi"]) != s:
				continue
			var near: Array = (dw["mouth_cells"] as Array) + (dw["door_cells"] as Array) + (dw.get("band", []) as Array)
			if dw.has("cell"):
				near.append(dw["cell"])
			for c: Vector2i in near:
				if dist.has(c):
					blocked[int(dist[c])] = true
		# ... nor at the foot of a drop (from its top, the floor just below it is out of sight): the lowest and highest
		# floor at each walking distance
		var floor_lo := {}
		var floor_hi := {}
		for c in cells:
			if dist.has(c):
				var d := int(dist[c])
				var lv: int = m.cells[c].level
				floor_lo[d] = mini(int(floor_lo.get(d, lv)), lv)
				floor_hi[d] = maxi(int(floor_hi.get(d, lv)), lv)
		var segs := maxi(2, int(round(float(length + 1) / float(SEGMENT_STEPS))))
		var cuts: Array[int] = []      # a cut at t: the cells at distance t or more are past it
		var last := 0
		for k in range(1, segs):
			var ideal := int(round(float(k) * float(length + 1) / float(segs)))
			for off: int in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5]:
				var t := ideal + off
				if t - last < MIN_SEGMENT or length + 1 - t < MIN_SEGMENT or not _cut_clear(t, blocked) or _below_drop(t, floor_lo, floor_hi):
					continue
				cuts.append(t)
				last = t
				break
		if cuts.is_empty():
			continue
		# bands of distance, then the connected pieces of each band
		var band := {}
		for c in cells:
			if dist.has(c):
				var b := 0
				while b < cuts.size() and int(dist[c]) >= cuts[b]:
					b += 1
				band[c] = b
		var piece := {}
		var pieces: Array = []         # [band, its cells]
		for c in cells:
			if not band.has(c) or piece.has(c):
				continue
			var pc: Array[Vector2i] = [c]
			piece[c] = pieces.size()
			var qi := 0
			while qi < pc.size():
				var cur := pc[qi]
				qi += 1
				for d in Hex.DIRS:
					var nb: Vector2i = cur + d
					if band.has(nb) and not piece.has(nb) and int(band[nb]) == int(band[c]):
						piece[nb] = pieces.size()
						pc.append(nb)
			pieces.append([int(band[c]), pc])
		# along the hall: by band, then by first cell (cells are sorted, so a piece's first cell is its least)
		var order: Array[int] = []
		for i in pieces.size():
			order.append(i)
		order.sort_custom(func(a: int, b: int) -> bool:
			return int(pieces[a][0]) < int(pieces[b][0]) or (int(pieces[a][0]) == int(pieces[b][0]) and a < b))
		var space_of_piece := {}
		var k_name := 0
		for i in order:
			if k_name == 0:
				space_of_piece[i] = s
			else:
				space_of_piece[i] = tags.size()
				tags.append("%s.%d" % [tags[s], k_name])
				is_hall.append(true)
				base_level.append(base_level[s])
				links.append([])
				hall_group.append(s)
			k_name += 1
		for c: Vector2i in piece:
			cell_space[c] = space_of_piece[piece[c]]
		# the corridor cells the walk missed, and the filled cells: the piece of the nearest one
		var frontier: Array[Vector2i] = []
		for c in cells:
			if piece.has(c):
				frontier.append(c)
		var left := {}
		for c in filled:
			left[c] = true
		for c in cells:
			if not piece.has(c):
				left[c] = true
		var fi := 0
		while fi < frontier.size():
			var cur := frontier[fi]
			fi += 1
			for d in Hex.DIRS:
				var nb: Vector2i = cur + d
				if left.has(nb):
					left.erase(nb)
					cell_space[nb] = cell_space[cur]
					frontier.append(nb)
		# room doorways into the piece that holds their mouth
		for dw in doorways:
			if int(dw["hi"]) != s:
				continue
			var votes := {}
			for c: Vector2i in dw["mouth_cells"]:
				if cell_space.has(c):
					var sp := int(cell_space[c])
					votes[sp] = int(votes.get(sp, 0)) + 1
			var best := s
			var best_n := 0
			for sp: int in votes:
				if int(votes[sp]) > best_n or (int(votes[sp]) == best_n and sp < best):
					best = sp
					best_n = int(votes[sp])
			dw["hi"] = best
			dw["hall"] = tags[best]
		# a cut per patch where two pieces touch
		var contacts := {}             # Vector2i(lower piece, higher piece) -> {cell: true}
		for c: Vector2i in piece:
			var pa: int = piece[c]
			for d in Hex.DIRS:
				var nb: Vector2i = c + d
				if not piece.has(nb) or int(piece[nb]) == pa or int(band[nb]) != int(band[c]) + 1:
					continue
				var key := Vector2i(pa, int(piece[nb]))
				if not contacts.has(key):
					contacts[key] = {}
				contacts[key][c] = true
				contacts[key][nb] = true
		var keys: Array = contacts.keys()
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return order.find(a.x) < order.find(b.x) or (a.x == b.x and order.find(a.y) < order.find(b.y)))
		for key: Vector2i in keys:
			for patch: Array in _patches_of(contacts[key]):
				var a_cells: Array[Vector2i] = []
				var b_cells: Array[Vector2i] = []
				for c: Vector2i in patch:
					if int(piece[c]) == key.x:
						a_cells.append(c)
					else:
						b_cells.append(c)
				if a_cells.is_empty() or b_cells.is_empty():
					continue
				var ca := Doorways._centroid(a_cells)
				var cb := Doorways._centroid(b_cells)
				var mid := (ca + cb) * 0.5
				var g := m.ground_height(mid)
				if is_nan(g):
					var lv := 0.0
					for c in a_cells + b_cells:
						lv = maxf(lv, float(m.cells[c].level))
					g = lv * Hex.LEVEL_HEIGHT
				mid.y = g
				var axis := Vector3(cb.x - ca.x, 0.0, cb.z - ca.z)
				axis = axis.normalized() if axis.length() > 0.001 else Vector3.RIGHT
				var ri: int = space_of_piece[key.x]
				var hi: int = space_of_piece[key.y]
				doorways.append({"id": doorways.size(), "room": tags[ri], "hall": tags[hi], "door_cells": a_cells,
						"mouth_cells": b_cells, "mid": mid, "axis": axis, "ok": false, "door_ok": false, "narrow": false,
						"width": 0.0, "dead_end": false, "split": true, "ri": ri, "hi": hi})
	# the links again, from every doorway
	for i in links.size():
		links[i] = []
	for dw in doorways:
		(links[int(dw["ri"])] as Array).append([int(dw["hi"]), int(dw["id"])])
		(links[int(dw["hi"])] as Array).append([int(dw["ri"]), int(dw["id"])])


## True when a cut at walking distance `t` (between t - 1 and t) keeps CUT_CLEAR steps from every blocked distance.
static func _cut_clear(t: int, blocked: Dictionary) -> bool:
	for d in range(t - CUT_CLEAR, t + CUT_CLEAR):
		if blocked.has(d):
			return false
	return true


## True when a cut at walking distance `t` sits DROP_LEVELS or more below the hall's floor within DROP_CLEAR steps of it
## (the foot of a drop: a hero up top doesn't see it until the edge). A cut at the top of a drop is seen from below.
static func _below_drop(t: int, lo: Dictionary, hi: Dictionary) -> bool:
	var low := mini(int(lo.get(t - 1, 0)), int(lo.get(t, 0)))
	for d in range(t - 1 - DROP_CLEAR, t + DROP_CLEAR + 1):
		if hi.has(d) and int(hi[d]) - low >= DROP_LEVELS:
			return true
	return false


## The connected patches (by hex adjacency) of a set of cells, each sorted; in order of their least cell.
static func _patches_of(cellset: Dictionary) -> Array:
	var cells: Array[Vector2i] = []
	for c: Vector2i in cellset:
		cells.append(c)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	var done := {}
	var out: Array = []
	for c in cells:
		if done.has(c):
			continue
		var p: Array[Vector2i] = [c]
		done[c] = true
		var i := 0
		while i < p.size():
			var cur := p[i]
			i += 1
			for d in Hex.DIRS:
				var nb: Vector2i = cur + d
				if cellset.has(nb) and not done.has(nb):
					done[nb] = true
					p.append(nb)
		out.append(p)
	return out


## Breadth first over `cells` from `from`: [the farthest cell, {cell: steps}, its steps].
static func _walk_far(cells: Array[Vector2i], from: Vector2i) -> Array:
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


## Mark what one hero at `pos` has in view: its space, then through doorways up to HOPS deep, each judged from the hero
## (DOOR_SIGHT, line of sight, never a shut door). A cut is judged the same way but costs no hop, so the spaces reached are
## the same whichever side of a cut the hero stands on.
func _see_from(pos: Vector3) -> void:
	var s := space_at(pos)
	if s < 0:
		return
	view[s] = 1
	var eye := pos + Vector3.UP * EYE
	var judged := {}                   # doorway id -> seen from here
	var hops_at := {s: 0}
	var level: Array[int] = [s]
	for h in HOPS + 1:
		# along the hall: through cuts, at the same hop
		var i := 0
		while i < level.size():
			var u := level[i]
			i += 1
			for l: Array in links[u]:
				var o := int(l[0])
				var id := int(l[1])
				if not is_cut(id) or hops_at.has(o) or not _sees(pos, eye, id, judged):
					continue
				hops_at[o] = h
				view[o] = 1
				level.append(o)
		if h == HOPS:
			break
		# one more doorway on
		var nxt: Array[int] = []
		for u in level:
			for l: Array in links[u]:
				var o := int(l[0])
				var id := int(l[1])
				if is_cut(id) or hops_at.has(o) or shut.has(id) or not _sees(pos, eye, id, judged):
					continue
				hops_at[o] = h + 1
				view[o] = 1
				nxt.append(o)
		level = nxt
	# Vantage: high above its room's floor, a hero sees into every space next to that room.
	if not is_hall[s] and map != null:
		var lv := map.ground_level(pos)
		if not is_nan(lv) and lv >= float(base_level[s] + VANTAGE_LEVELS) - 0.01:
			for l: Array in links[s]:
				if not shut.has(int(l[1])):   # (user, 2026-10-19: height does not see past a shut door)
					view[int(l[0])] = 1


## Whether a hero at `pos` (eyes at `eye`) sees doorway `id`'s middle: within DOOR_SIGHT, flat, and in line of sight. A
## cut is as wide as its hall, so any of its cells will do too, at a hero's eye height (its middle can sit by the wall at
## a bend, and the hall can step there): who would see a hero standing on the cut sees it.
func _sees(pos: Vector3, eye: Vector3, id: int, judged: Dictionary) -> bool:
	if judged.has(id):
		return judged[id]
	var dw: Dictionary = doorways[id]
	var spots: Array[Vector3] = [dw["mid"] + Vector3.UP * DOOR_EYE]
	if is_cut(id) and map != null:
		for c: Vector2i in (dw["door_cells"] as Array[Vector2i]) + (dw["mouth_cells"] as Array[Vector2i]):
			if map.is_walkable_cell(c):
				spots.append(Hex.to_world(c, float(map.cells[c].level)) + Vector3.UP * EYE)
	var ok := false
	for p in spots:
		if Vector2(p.x - pos.x, p.z - pos.z).length() > DOOR_SIGHT:
			continue
		if map == null or map.line_of_sight(eye, p):
			ok = true
			break
	judged[id] = ok
	return ok


## Counts per state (the lab's readout, tests).
func census() -> Dictionary:
	var out := {"unknown": 0, "next": 0, "seen": 0, "in_view": 0}
	for s in tags.size():
		out[NAMES[state[s]]] = int(out[NAMES[state[s]]]) + 1
	return out
