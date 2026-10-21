extends TestCase
## Notes (docs/design/notes-rethink.md): the copy tables, the {slot} facts being true for the generated floor,
## lines dropped when their facts are missing, two notes on every floor, no line over 140 characters or framed with
## "Note:", the dispatch line, and in the game: the [E] prompt and the E press agree (read, then close; walking
## away closes the slip too).

const GAME := preload("res://scripts/app/game.gd")
const SEEDS: Array[int] = [1, 2, 3, 7, 42, 99, 1234, 5150]

## The longest value each slot can take, for the length check.
var _longest := {}


func setup() -> void:
	timeout_sec = 120.0
	_build_longest()
	_check_copy_tables()
	_check_drop_and_fill()
	_check_floors()
	_check_seeded()
	await _check_game()
	finish()


func _all_lines() -> Array:
	var out: Array = []
	for id: String in NoteCopy.STORY:
		for f: int in NoteCopy.STORY[id]:
			for ln: Dictionary in NoteCopy.STORY[id][f]:
				out.append(ln)
	for k: String in NoteCopy.HINTS:
		out.append_array(NoteCopy.HINTS[k])
	for pest: String in NoteCopy.PEST_TICKETS:
		out.append({"f": "report", "t": NoteCopy.PEST_TICKETS[pest]})
	for f: int in NoteCopy.DISPATCH:
		for t: String in NoteCopy.DISPATCH[f]:
			out.append({"f": "dispatch", "t": t})
	return out


func _build_longest() -> void:
	var rooms: Array[String] = []
	for k: String in RoomThemeDefs.THEMES:
		if k != RoomThemeDefs.SERVICE:   # the start room: no staff, gate or prop is ever placed there
			rooms.append(NoteFacts.theme_word(k) + " by the entrance")
	for id in ClientArchetype.IDS:
		for ev: Dictionary in ClientArchetype.get_data(id)["events"]:
			rooms.append(str(ev["origin"]))
	var props: Array[String] = []
	var prices: Array[String] = []
	for k: String in PricedProp.TABLE:
		props.append(PricedProp.name_of(k))
		prices.append(ContractRun.money(PricedProp.price_of(k)))
	var staff: Array[String] = []
	for n: String in SiteBuilder.STAFF_NAMES + SiteBuilder.HENCHMAN_NAMES:
		staff.append(NoteFacts.staff_name(n))
	var clients: Array[String] = []
	for id in ClientArchetype.IDS:
		var d := ClientArchetype.get_data(id)
		for a: String in d["first"]:
			for b: String in d["last"]:
				clients.append("%s %s" % [a, b])
	var origins: Array[String] = []
	for id in ClientArchetype.IDS:
		for ev: Dictionary in ClientArchetype.get_data(id)["events"]:
			origins.append(str(ev["origin"]))
	var pests: Array[String] = []
	for p: String in ClientArchetype.PEST_NAMES.values():
		pests.append(p)
	var longest := func(arr: Array[String]) -> String:
		var best := ""
		for s in arr:
			if s.length() > best.length():
				best = s
		return best
	var incidents: Array[String] = []
	for id in ClientArchetype.IDS:
		for ev: Dictionary in ClientArchetype.get_data(id)["events"]:
			incidents.append(str(ev["dispatch"]))
	_longest = {
		"incident": longest.call(incidents),
		"client": longest.call(clients), "staff": longest.call(staff), "staff_room": longest.call(rooms), "staff_count": "4",
		"gate_room": longest.call(rooms), "gate_count": "4", "prop": longest.call(props), "prop_room": longest.call(rooms),
		"prop_price": longest.call(prices), "origin": longest.call(origins), "pest": longest.call(pests),
	}
	for k: String in ["staff", "staff_room", "gate_room", "prop", "origin"]:
		_longest[k.to_upper()] = str(_longest[k]).to_upper()


func _check_copy_tables() -> void:
	for id in ClientArchetype.IDS:
		check(NoteCopy.STORY.has(id), "%s has story notes" % id)
		for f in range(1, 4):
			var lines: Array = (NoteCopy.STORY[id] as Dictionary).get(f, [])
			var plain := 0
			for ln: Dictionary in lines:
				if not ln.has("event"):
					plain += 1
			check(plain >= 2, "%s floor %d: at least 2 generic lines (%d)" % [id, f, plain])
			check(lines.size() >= 3, "%s floor %d: at least 3 lines" % [id, f])
		# every event the client can roll has its floor-3 payoff line
		for ev: Dictionary in ClientArchetype.get_data(id)["events"]:
			var keyed := NoteCopy.story_lines(id, 3, str(ev["origin"]))
			var all_keyed := not keyed.is_empty()
			for ln: Dictionary in keyed:
				all_keyed = all_keyed and str(ln.get("event", "")) == str(ev["origin"])
			check(all_keyed, "%s: the '%s' event has its own floor-3 line" % [id, ev["origin"]])
	for pest: String in ["grunt", "archer", "brute", "swarmer", "everything"]:
		check(NoteCopy.PEST_TICKETS.has(pest), "a pest ticket for %s" % pest)
	for ln: Dictionary in _all_lines():
		var t := str(ln["t"])
		check(NoteCopy.FORMATS.has(str(ln["f"])) or str(ln["f"]) == "dispatch", "known format: %s" % ln["f"])
		for s in NoteCopy.slots_in(t):
			check(NoteCopy.SLOTS.has(s), "known slot {%s} in: %s" % [s, t])
		var filled := NoteCopy.fill(t, _longest)
		check(filled.length() <= NoteCopy.MAX_LEN, "at most %d characters with the longest facts (%d): %s" % [NoteCopy.MAX_LEN, filled.length(), filled])
		check(not filled.contains("{"), "every slot fills: %s" % filled)
		var low := t.to_lower()
		check(not (low.begins_with("note") or low.begins_with("a note") or low.begins_with("a memo")), "no 'Note:' framing: %s" % t)
	for fmt: String in NoteCopy.HEADERS:
		check(NoteCopy.FORMATS.has(fmt), "headers for a known format: %s" % fmt)


func _check_drop_and_fill() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var none := {"client": "Sage Oakhaven", "origin": "yoga studio", "ORIGIN": "YOGA STUDIO", "pest": "imps"}
	# prepper floor 2: every line needs staff, a prop or a gate
	eq(NoteCopy.pick(NoteCopy.STORY["prepper"][2], none, rng), {}, "a floor with no staff, props or gates drops every slotted line")
	var with_staff := none.duplicate()
	with_staff.merge({"staff": "Pearl", "STAFF": "PEARL", "staff_room": "gym", "STAFF_ROOM": "GYM", "staff_count": "2"})
	for i in 20:
		var ln := NoteCopy.pick(NoteCopy.STORY["prepper"][2], with_staff, rng)
		check(not ln.is_empty() and NoteCopy.can_fill(str(ln["t"]), with_staff), "only lines whose facts exist survive")
	var t := NoteCopy.fill("Hiding in the {staff_room}. — {staff}", with_staff)
	eq(t, "Hiding in the gym. — Pearl", "fill replaces every slot")
	eq(NoteCopy.kinds_of("{staff} in the {staff_room}, near the {PROP}"), ["staff", "prop"] as Array[String], "a line's hint kinds")
	eq(NoteSlip.split_signature("We are on four. — Pearl"), PackedStringArray(["We are on four.", "— Pearl"]), "the signature splits off")
	var sp := NoteSlip.split_sign("DAYS SINCE LAST ACCIDENT: 0. (The 0 is printed on.) (In pen: \"hi\")")
	eq(sp[0], "DAYS SINCE LAST ACCIDENT: 0.", "a sign's ALL-CAPS rule")
	check(sp[2].begins_with("In pen"), "a sign's pen addition")
	eq(NoteFacts.client_short("Admiral Grimsby of Sector 7", "supervillain"), "Admiral Grimsby", "the client's suffix is dropped")
	eq(NoteFacts.staff_name("Beatrice (sommelier)"), "Beatrice", "the staff's role is dropped")


## Every client, every floor, a few seeds: two notes, true facts.
func _check_floors() -> void:
	for id in ClientArchetype.IDS:
		for s in SEEDS.slice(0, 4):
			var run := ContractRun.make(id, s, 0.5)
			var catalog := PricedProp.catalog(run.site_type)
			for f in range(1, ContractRun.FLOOR_COUNT + 1):
				var map := DungeonGen.generate(run.floor_seed(f))
				var plan := SiteBuilder.plan(map, run, f, catalog)
				_check_plan(run, plan, map, "%s seed %d floor %d" % [id, s, f])


func _check_plan(run: ContractRun, plan: SitePlan, map: HexMap, tag: String) -> void:
	eq(plan.notes.size(), 2, "%s: two notes" % tag)
	var kinds: Array[String] = []
	for nt in plan.notes:
		kinds.append(str(nt["kind"]))
		var t := str(nt["text"])
		check(t != "" and not t.contains("{") and t.length() <= NoteCopy.MAX_LEN, "%s: a filled line: %s" % [tag, t])
		check(not t.to_lower().begins_with("note"), "%s: no 'Note:' prefix" % tag)
		check(NoteCopy.FORMATS.has(str(nt["format"])), "%s: a format" % tag)
		var cell: HexMap.Cell = map.get_cell(nt["cell"])
		check(cell != null and cell.type == HexMap.Tile.FLOOR and cell.tag.begins_with("room:"), "%s: a note stands on room floor" % tag)
		for g in plan.gates:
			check(Hex.distance(nt["cell"], g["cell"]) >= 3, "%s: a note keeps clear of a gate" % tag)
		for e in plan.employees:
			check(nt["cell"] != e["cell"], "%s: a note is not on an employee" % tag)
	eq(kinds, ["story", "hint"] as Array[String], "%s: a story note and a hint slip" % tag)
	if plan.notes.size() == 2:
		check(Hex.distance(plan.notes[0]["cell"], plan.notes[1]["cell"]) >= 4, "%s: the two notes are apart" % tag)
		var hint_room := str(plan.notes[1]["room"])
		if plan.rooms.size() > 4:
			check(hint_room != plan.start_room and hint_room != plan.exit_room, "%s: the hint slip is in a side room" % tag)
	if plan.floor_number == ContractRun.FLOOR_COUNT and not plan.notes.is_empty():
		eq(str(plan.notes[0]["room"]), plan.origin_room, "%s: floor 3's story note is in the origin room" % tag)
	if plan.floor_number == 1 and not plan.notes.is_empty():
		var d := Hex.distance(plan.notes[0]["cell"], plan.start)
		check(d >= 4 and d <= 8, "%s: floor 1's story note is near the start (%d)" % [tag, d])
	check(plan.dispatch != "" and not plan.dispatch.contains("{"), "%s: a dispatch line: %s" % [tag, plan.dispatch])
	_check_one_thought(run, plan, tag)
	# the facts are true for this floor
	var facts := NoteFacts.from_plan(plan, run)
	if facts.has("staff"):
		var found := false
		for e in plan.employees:
			if NoteFacts.staff_name(str(e["name"])) == str(facts["staff"]) and str(e["room"]) == str(facts["_staff_room"]):
				found = true
		check(found, "%s: %s really is in the %s" % [tag, facts["staff"], facts["staff_room"]])
		eq(str(facts["staff_room"]).begins_with(NoteFacts.room_word(plan, run, str(facts["_staff_room"]))), true, "%s: the staff room is named by its theme" % tag)
	else:
		check(plan.employees.is_empty(), "%s: no staff fact only without employees" % tag)
	if facts.has("gate_room"):
		var gate_there := false
		for g in plan.gates:
			if not bool(g["origin"]) and str(g["room"]) == str(facts["_gate_room"]):
				gate_there = true
		check(gate_there, "%s: a small gate really is in the %s" % [tag, facts["gate_room"]])
		eq(int(facts["gate_count"]), plan.small_gate_count(), "%s: the gate count" % tag)
	else:
		eq(plan.small_gate_count(), 0, "%s: no gate fact only without small gates" % tag)
	if facts.has("prop"):
		var top := 0
		for pr in plan.props:
			top = maxi(top, PricedProp.price_of(str(pr["kind"])))
		eq(str(facts["prop_price"]), ContractRun.money(top), "%s: the prop is the floor's priciest" % tag)
		var in_room := false
		for pr in plan.props:
			if str(pr["kind"]) == str(facts["_prop_kind"]) and str(pr["room"]) == str(facts["_prop_room"]):
				in_room = true
		check(in_room, "%s: the %s really is in the %s" % [tag, facts["prop"], facts["prop_room"]])
	else:
		check(plan.props.is_empty(), "%s: no prop fact only without props" % tag)
	# whatever a note names, it names this floor's facts
	for nt in plan.notes:
		var t := str(nt["text"])
		if t.contains("shelters in the ") and facts.has("staff_room"):
			check(t.contains(str(facts["staff_room"])), "%s: the shelter line names the real staff room" % tag)


## A dispatch banner is ONE thought: no standalone pay tip, no "Dispatch is not judging" button, two sentences at most. Floor 1
## tells the contract's own event (dispatch's wording) and what it means for the crew; floors 2 and 3 are about that floor.
func _check_one_thought(run: ContractRun, plan: SitePlan, tag: String) -> void:
	var t := plan.dispatch
	check(not t.contains("$") and not t.contains("not judging") and not t.contains("worth"), "%s: no glued-on pay tip: %s" % [tag, t])
	check(t.length() <= NoteCopy.MAX_LEN, "%s: the banner fits (%d chars)" % [tag, t.length()])
	var sentences := 0
	for ch in t:
		if ch == "." or ch == "!" or ch == "?":
			sentences += 1
	check(sentences >= 1 and sentences <= 3, "%s: one thought, a few sentences at most (%d)" % [tag, sentences])
	if plan.floor_number == 1:
		eq(t, str(run.story["dispatch"]), "%s: floor 1 tells the contract's event in dispatch's voice" % tag)
		check(t.contains("Bring them out"), "%s: floor 1 ties the event to the staff" % tag)
	elif plan.floor_number == ContractRun.FLOOR_COUNT:
		check(t.contains(str(run.story["origin"])), "%s: floor 3 names the origin room" % tag)


## Same seed, same notes; and the notes' generator does not move anything else on the floor.
func _check_seeded() -> void:
	var run := ContractRun.make("guru", 42, 0.4)
	var map := DungeonGen.generate(run.floor_seed(2))
	var catalog := PricedProp.catalog(run.site_type)
	var a := SiteBuilder.plan(map, run, 2, catalog)
	var b := SiteBuilder.plan(map, run, 2, catalog)
	eq(str(a.notes), str(b.notes), "the same seed plans the same notes")
	eq(a.dispatch, b.dispatch, "and the same dispatch line")


func _make_game(extra: Dictionary) -> Node3D:
	var g: Node3D = load("res://scripts/app/game.gd").new()
	var o := {"no_mic": true, "spells": "heal,corn", "no_van_intro": true}
	o.merge(extra, true)
	g.set("opts", o)
	GAME.reset_flow()
	return g


## In the game: no "NOTE" label, the dispatch banner, and [E] Read / Close agree with the E press.
func _check_game() -> void:
	var g := _make_game({"contract": 1, "seed": 5})
	add_child(g)
	await frames(10)
	var site: SiteBuilder.Site = g.get("_site")
	var player: Hero = g.get("player")
	var pc: PlayerController = g.get("controller")
	var prompt: UsePrompt = g.get("_use_prompt")
	var slip: NoteSlip = g.get("_note_slip")
	if not check(site != null and site.notes.size() == 2 and slip != null, "the floor has two notes and the game a note slip"):
		g.queue_free()
		await frames(3)
		GAME.reset_flow()
		return
	for n in site.notes:
		var labels := n.find_children("*", "Label3D", true, false)
		for l in labels:
			check((l as Label3D).text != "NOTE", "no floating NOTE label")
	var banner: DispatchBanner = g.get("_banner")
	check(banner != null and banner.line == site.plan.dispatch, "the dispatch banner shows the floor's line")
	check(not ("lead" in banner), "and it is one message: no separate incident line above it")
	for f in range(1, 4):
		for t: String in NoteCopy.DISPATCH[f]:
			check(not t.contains("$") and not t.contains("not judging"), "no old pay tip in floor %d banner: %s" % [f, t])
	# the monsters stay out of it
	for m in site.monsters:
		m.process_mode = Node.PROCESS_MODE_DISABLED
	var note: ClueNote = null
	for n in site.notes:
		player.global_position = n.global_position + Vector3(0.8, 0.0, 0.0)
		await frames(4)
		if Employee.interact_target(player) == null and not g.call("_player_at_elevator") and not g.call("_player_at_van"):
			note = n
			break
	if not check(note != null, "a note with nothing else in E's reach"):
		g.queue_free()
		await frames(3)
		GAME.reset_flow()
		return
	await frames(20)
	var t: Object = g.call("use_target")
	if check(t != null and t.kind == "note" and t.node == note, "next to a note E targets it"):
		check(prompt.wanted and prompt.key == "E" and prompt.verb == t.verb and prompt.verb == note.verb(), "the prompt shows [E] %s" % note.verb())
		check(prompt.verb == ("Listen" if note.format == "voicemail" else "Read"), "Read, or Listen for a voicemail")
		check(not slip.is_open(), "walking up does not open it")
		check(pc.press_use(), "E is used")
		await frames(2)
		check(slip.is_open() and slip.text == note.text and slip.format == note.format, "E does what the prompt said: the slip opens with the note")
		check(g.get("_open_note") == note, "and the game knows which note is open")
		await frames(20)
		t = g.call("use_target")
		check(t != null and t.kind == "note" and t.verb == "Close" and prompt.verb == "Close", "with it open the prompt says [E] Close")
		check(pc.press_use(), "E is used again")
		await frames(2)
		check(not slip.is_open() and g.get("_open_note") == null, "E closes the slip")
		await frames(20)
		check(prompt.verb == note.verb(), "and the prompt reads [E] %s again" % note.verb())
		# open it again, then walk away
		pc.press_use()
		await frames(2)
		check(slip.is_open(), "open again")
		player.global_position = note.global_position + Vector3(ClueNote.READ_RANGE + 1.5, 0.0, 0.0)
		await frames(4)
		check(not slip.is_open() and g.get("_open_note") == null, "walking away closes the slip")
	g.queue_free()
	await frames(3)
	GAME.reset_flow()
