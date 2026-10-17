class_name ContractStory
extends RefCounted
## "What happened": the inciting event and where it started (docs/design/contracts.md, Story).
## The origin room is a theme (e.g. "yoga studio") that names the floor-3 room holding the origin
## hellgate; floors 1-2 only get "spread" flavour, because the pests are drifting up from below.
## Pure data + a roller; the rest of the generator reads the Dictionary it returns.
##
## story = {
##   "event": String            the inciting event, one deadpan sentence
##   "origin": String           the origin room theme ("yoga studio")
##   "origin_floor": int        3
##   "summary": String          "Cause: ... Origin: the yoga studio, floor 3."
##   "floor_notes": Array[String]   one flavour line per floor (index 0 = floor 1)
##   "clues": Array[String]         one note per floor (index 0 = floor 1)
## }


static func roll(archetype_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var d := ClientArchetype.get_data(archetype_id)
	var events: Array = d["events"]
	var ev: Dictionary = events[rng.randi_range(0, events.size() - 1)]
	var origin: String = str(ev["origin"])
	var clues: Array = d["clues"]
	var clue_order: Array[int] = []
	for i in clues.size():
		clue_order.append(i)
	_shuffle(clue_order, rng)
	var floor_clues: Array[String] = []
	for f in ContractRun.FLOOR_COUNT:
		floor_clues.append(str(clues[clue_order[f % clue_order.size()]]))
	var notes: Array[String] = []
	var spread := ClientArchetype.SPREAD_LINES
	var first_spread := rng.randi_range(0, spread.size() - 1)
	notes.append(spread[first_spread])
	notes.append(spread[(first_spread + 1) % spread.size()])
	notes.append("The origin: the %s. Something is open and it is not the minibar." % origin)
	return {
		"event": str(ev["text"]),
		"origin": origin,
		"origin_floor": ContractRun.FLOOR_COUNT,
		"summary": "%s Origin: the %s, floor %d." % [str(ev["text"]), origin, ContractRun.FLOOR_COUNT],
		"floor_notes": notes,
		"clues": floor_clues,
	}


static func _shuffle(arr: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := arr[i]
		arr[i] = arr[j]
		arr[j] = t
