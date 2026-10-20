class_name ContractStory
extends RefCounted
## "What happened": the inciting event and where it started (docs/design/contracts.md, Story).
## The origin room is a theme (e.g. "yoga studio") that names the floor-3 room holding the origin
## hellgate. The notes and the dispatch floor banners are planned per floor (NoteCopy, NotePlanner.plan).
## Pure data + a roller; the rest of the generator reads the Dictionary it returns.
##
## story = {
##   "event": String            the inciting event, one deadpan sentence (the client's voice: the job board)
##   "dispatch": String         the same event as dispatch says it on the floor-1 headset banner: the incident and
##                              what it means for the crew, as one thought (NoteFacts "incident")
##   "origin": String           the origin room theme ("yoga studio")
##   "origin_floor": int        3
##   "summary": String          "Cause: ... Origin: the yoga studio, floor 3."
## }


static func roll(archetype_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var d := ClientArchetype.get_data(archetype_id)
	var events: Array = d["events"]
	var ev: Dictionary = events[rng.randi_range(0, events.size() - 1)]
	var origin: String = str(ev["origin"])
	# Three draws that used to roll the old clue order and spread line. Kept so every existing seed still makes
	# the same contract (the pest, employees and gates are rolled after the story from the same generator).
	rng.randi_range(0, 2)
	rng.randi_range(0, 1)
	rng.randi_range(0, 3)
	return {
		"event": str(ev["text"]),
		"dispatch": str(ev.get("dispatch", ev["text"])),
		"origin": origin,
		"origin_floor": ContractRun.FLOOR_COUNT,
		"summary": "%s Origin: the %s, floor %d." % [str(ev["text"]), origin, ContractRun.FLOOR_COUNT],
	}

