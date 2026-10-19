class_name RoomFog
extends RefCounted
## ROOM FOG (docs/design/exploration.md, "Decisions: map information, fog and doors", 2026-10-19): what
## the crew knows of a floor, per SPACE (a room, or a hall: one corridor; Doorways), not per cell. Pure logic, built from the
## map alone; deterministic, no rng. Presentation reads it (FogView); nothing in the simulation does.
##
## STATES (per space), from least to most known:
##   UNKNOWN  dark: nothing drawn.
##   NEXT     its LAYOUT is drawn (floor and walls), nothing in it: a space next to one the crew knows (in view now or seen
##            before), and a room one hall away from a known room (the room at the other end of the corridor).
##   SEEN     was in view at some point: layout and its static props (furniture, notes, mail, gates), dimmed. Never anything
##            that moves (monsters, employees, pickups): no last-known ghosts.
##   IN_VIEW  everything in it shows.
##
## IN VIEW, for each hero (shared reveal: the union over the whole crew, so one hero's sight is everyone's):
##   1. the space the hero stands in;
##   2. THROUGH A DOORWAY: a space beyond a doorway of the hero's space whose door is open (or that has none), when the
##      doorway's middle is within DOOR_SIGHT of the hero and in line of sight from its eyes (HexMap.line_of_sight: walls,
##      and shut doors as blockers). One more doorway on (two hops: a room seen down a short straight corridor) on the
##      same terms, measured from the hero;
##   3. VANTAGE: a hero standing VANTAGE_LEVELS (2) or more above its ROOM's floor (a crate tier, a ledge) sees into every
##      space next to that room, doors or not (a crown looks over the partitions).
## SEEN is sticky: once in view, always at least seen. NEXT follows from what is known; nothing un-sees.
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


## Who may write each var (see Net). Fog is presentation, computed on every machine from the map (SPAWN data) and what it
## already has: every hero's position (theirs or a puppet's) and every door's state. A late joiner starts with what it sees.
func net_fields() -> Dictionary:
	return {
		"map": Net.LOCAL, "tags": Net.LOCAL, "is_hall": Net.LOCAL, "base_level": Net.LOCAL, "cell_space": Net.LOCAL,
		"doorways": Net.LOCAL, "links": Net.LOCAL, "shut": Net.LOCAL, "state": Net.LOCAL, "seen": Net.LOCAL,
		"view": Net.LOCAL, "updates": Net.LOCAL,
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
	var n := f.tags.size()
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
			# A known room: the room at the other end of each of its halls has its layout too.
			if not is_hall[s] and is_hall[o]:
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


## Mark what one hero at `pos` has in view.
func _see_from(pos: Vector3) -> void:
	var s := space_at(pos)
	if s < 0:
		return
	view[s] = 1
	var eye := pos + Vector3.UP * EYE
	# Through doorways, up to HOPS deep, each one judged from the hero.
	var frontier: Array[int] = [s]
	var visited := {s: true}
	for hop in HOPS:
		var nxt: Array[int] = []
		for u in frontier:
			for l: Array in links[u]:
				var o := int(l[0])
				var dw_id := int(l[1])
				if visited.has(o) or shut.has(dw_id):
					continue
				var mid: Vector3 = doorways[dw_id]["mid"]
				if Vector2(mid.x - pos.x, mid.z - pos.z).length() > DOOR_SIGHT:
					continue
				if map != null and not map.line_of_sight(eye, mid + Vector3.UP * DOOR_EYE):
					continue
				visited[o] = true
				view[o] = 1
				nxt.append(o)
		frontier = nxt
	# Vantage: high above its room's floor, a hero sees into every space next to that room.
	if not is_hall[s] and map != null:
		var lv := map.ground_level(pos)
		if not is_nan(lv) and lv >= float(base_level[s] + VANTAGE_LEVELS) - 0.01:
			for l: Array in links[s]:
				view[int(l[0])] = 1


## Counts per state (the lab's readout, tests).
func census() -> Dictionary:
	var out := {"unknown": 0, "next": 0, "seen": 0, "in_view": 0}
	for s in tags.size():
		out[NAMES[state[s]]] = int(out[NAMES[state[s]]]) + 1
	return out
