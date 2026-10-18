class_name NoteFacts
extends RefCounted
## The {slot} values a note may use, read from the floor that was just planned (docs/design/notes-rethink.md,
## section 5), so every hint is true for the generated floor: the staff named are on it and in that room, the
## gate room has a gate, the prop is the floor's most expensive one.
##
##   var facts := NoteFacts.from_plan(plan, run)
##   NoteCopy.fill("Hiding in the {staff_room}. — {staff}", facts)
##
## A slot is missing (no key) when the floor has no such thing: no employees, no small gates (floor 3), no
## props. Keys starting with "_" are the planner's bookkeeping (which room / cell a fact points at), for tests.
## Pure: no randomness. Choices are deterministic (room order), so every machine fills the same text.

## A room theme as a note names it ("the {staff_room}" -> "the wine cellar").
const ROOM_WORDS := {
	"wine_cellar": "wine cellar", "home_cinema": "home cinema", "spa": "spa", "gym": "gym",
	"server_room": "server room", "panic_room": "panic room", "pool": "pool room",
	"torture_chamber": "torture chamber", "throne_room": "throne room", "lab": "lab", "barracks": "barracks",
	"moat": "shark moat", "mad_science": "specimen lab", "service_entrance": "service entrance",
}


static func from_plan(plan: SitePlan, run: ContractRun) -> Dictionary:
	var f := {}
	f["client"] = client_short(run.client_name, run.archetype_id)
	var origin := str(run.story.get("origin", ""))
	if origin != "":
		f["origin"] = origin
		f["ORIGIN"] = origin.to_upper()
	f["pest"] = ClientArchetype.pest_name(run.pest)
	var incident := str(run.story.get("dispatch", ""))
	if incident != "":
		f["incident"] = incident   # the floor-1 dispatch banner: the event, in dispatch's voice, and what it means for the crew
	# staff: one employee, preferring a room whose name is unique on the floor
	if not plan.employees.is_empty():
		var e: Dictionary = _prefer_unique(plan, run, plan.employees)
		var nm := staff_name(str(e["name"]))
		f["staff"] = nm
		f["STAFF"] = nm.to_upper()
		f["staff_room"] = room_name(plan, run, str(e["room"]))
		f["STAFF_ROOM"] = str(f["staff_room"]).to_upper()
		f["staff_count"] = str(plan.employees.size())
		f["_staff_room"] = str(e["room"])
		f["_staff_cell"] = e["cell"]
	# gate: a small (non-origin) gate
	var small: Array = []
	for g in plan.gates:
		if not bool(g["origin"]):
			small.append(g)
	if not small.is_empty():
		var g: Dictionary = _prefer_unique(plan, run, small)
		f["gate_room"] = room_name(plan, run, str(g["room"]))
		f["GATE_ROOM"] = str(f["gate_room"]).to_upper()
		f["gate_count"] = str(small.size())
		f["_gate_room"] = str(g["room"])
		f["_gate_cell"] = g["cell"]
	# prop: the floor's most expensive priced prop (ties: the first planned)
	var best: Dictionary = {}
	var best_price := -1
	for pr in plan.props:
		var price := PricedProp.price_of(str(pr["kind"]))
		if price > best_price:
			best_price = price
			best = pr
	if not best.is_empty():
		var nm := PricedProp.name_of(str(best["kind"]))
		f["prop"] = nm.substr(0, 1).to_lower() + nm.substr(1)
		f["PROP"] = nm.to_upper()
		f["prop_room"] = room_name(plan, run, str(best["room"]))
		f["prop_price"] = ContractRun.money(best_price)
		f["_prop_room"] = str(best["room"])
		f["_prop_kind"] = str(best["kind"])
	return f


## "Admiral Von Doom-Smythe of Sector 7" -> "Admiral Von Doom-Smythe": the name without the archetype's suffix.
static func client_short(full: String, archetype: String) -> String:
	for suf in (ClientArchetype.get_data(archetype)["suffix"] as Array):
		var tail := " " + str(suf)
		if str(suf) != "" and full.ends_with(tail):
			return full.substr(0, full.length() - tail.length())
	return full


## "Marguerite (sommelier)" -> "Marguerite".
static func staff_name(full: String) -> String:
	var i := full.find(" (")
	return full.substr(0, i) if i > 0 else full


## The bare word for a room: the story's own word for the origin room, else its theme's word.
static func room_word(plan: SitePlan, run: ContractRun, tag: String) -> String:
	if tag != "" and tag == plan.origin_room and str(run.story.get("origin", "")) != "":
		return str(run.story["origin"])
	var theme := plan.theme_of(tag)
	return str(ROOM_WORDS.get(theme, RoomThemeDefs.theme_name(theme).to_lower() if theme != "" else "back room"))


## The room as a note names it. When another room on the floor reads the same, a landmark is added:
## "gym by the elevator" or "gym by the entrance" (whichever of the exit and the start its centre is nearer).
static func room_name(plan: SitePlan, run: ContractRun, tag: String) -> String:
	var word := room_word(plan, run, tag)
	if is_unique(plan, run, tag):
		return word
	var c: Vector2i = plan.centers.get(tag, plan.start)
	return "%s by the %s" % [word, "elevator" if Hex.distance(c, plan.exit) <= Hex.distance(c, plan.start) else "entrance"]


## True when no other room on the floor has the same note word.
static func is_unique(plan: SitePlan, run: ContractRun, tag: String) -> bool:
	var word := room_word(plan, run, tag)
	for other: String in plan.rooms:
		if other != tag and room_word(plan, run, other) == word:
			return false
	return true


## The first entry (in plan order) whose room has a unique name, else the first entry.
static func _prefer_unique(plan: SitePlan, run: ContractRun, entries: Array) -> Dictionary:
	for e: Dictionary in entries:
		if is_unique(plan, run, str(e["room"])):
			return e
	return entries[0]
