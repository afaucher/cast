class_name CrewSeats
extends RefCounted
## Which hero each of the crew's three seats plays (the character select, user 2026-10-19). Plain data, no state.
##
## A person plays the hero they picked (the main menu's garage; `Session.character_id`, in the roster as "character"). Two
## people may pick the same hero. The AI seats play the heroes NOBODY human picked: an AI seat keeps its own hero
## (`AI_DEFAULTS`: seat 2 Rebar, seat 3 Gasket, the crew as it was before picks) when no person plays it, and otherwise
## takes the first hero in `FILL_ORDER` that nobody plays. A duplicate only when every hero is already taken (which three
## seats never need: at most as many heroes are taken as there are people). So:
##   solo Wick   -> AI Rebar (2), AI Gasket (3)        solo Rebar -> AI Wick (2), AI Gasket (3)
##   solo Gasket -> AI Rebar (2), AI Wick (3)          Wick + Wick (2 people) -> AI Gasket (3)
## A seat whose player leaves goes back to the AI as `ai_for(seat, the other seats' heroes)`: the same rule, so the hero
## it becomes is the one that seat gets again on the next floor (no swapping between floors).
##
## Every machine runs this on the same roster (the floor's seat table), so the floor checksum agrees.

## The AI seats' own heroes.
const AI_DEFAULTS := {2: "rebar", 3: "gasket"}
## The order an AI seat whose own hero is taken looks for one nobody plays.
const FILL_ORDER: Array[String] = ["rebar", "gasket", "wick"]


## `humans`: seat -> character for every seat a person plays. Returns seat -> character for seats 1..`count`, the AI
## seats filled.
static func fill(humans: Dictionary, count: int = 3) -> Dictionary:
	var out := {}
	var used: Array[String] = []
	for s: Variant in humans:
		out[int(s)] = str(humans[s])
		used.append(str(humans[s]))
	var open: Array[int] = []
	for seat in range(1, count + 1):
		if not out.has(seat):
			open.append(seat)
	for seat in open:   # an AI seat keeps its own hero when nobody plays it
		var own := str(AI_DEFAULTS.get(seat, ""))
		if own != "" and not used.has(own):
			out[seat] = own
			used.append(own)
	for seat in open:   # the others take the heroes nobody plays
		if out.has(seat):
			continue
		out[seat] = _free_hero(seat, used)
		used.append(str(out[seat]))
	return out


## The hero an AI plays in `seat` when it takes the seat now, beside `others` (the heroes in every other seat).
static func ai_for(seat: int, others: Array) -> String:
	var own := str(AI_DEFAULTS.get(seat, ""))
	if own != "" and not others.has(own):
		return own
	return _free_hero(seat, others)


## The first hero in FILL_ORDER not in `used`; when every one is taken, the seat's own hero (a duplicate).
static func _free_hero(seat: int, used: Array) -> String:
	for id in FILL_ORDER:
		if not used.has(id):
			return id
	return str(AI_DEFAULTS.get(seat, FILL_ORDER[0]))
