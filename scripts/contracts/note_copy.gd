class_name NoteCopy
extends RefCounted
## Every line of note copy, and the dispatch floor banners (docs/design/notes-rethink.md).
##
## Notes are documents that existed BEFORE the outbreak (memos, signs, tickets, sticky notes,
## voicemails, complaint forms): they foreshadow, they never report. Each line is a Dictionary:
##   {"f": format, "t": text, "event": origin (optional, floor 3), "h": header override (optional)}
## Text may hold {slots} that NoteFacts fills from the generated floor; a line whose slots the floor
## cannot fill is dropped (pick()). Pure data + string helpers: no randomness of its own.

const FORMATS: Array[String] = ["sticky", "report", "sign", "voicemail", "memo", "complaint"]
const MAX_LEN := 140                       ## a filled line never runs longer than this

## The use-prompt verb per format ("[E] Read").
const VERBS := {"voicemail": "Listen"}

## Header per format per client (the slip's title line). "" = no header (a sticky note).
const HEADERS := {
	"report": {"prepper": "Contingency Log", "supervillain": "Maintenance Ticket", "guru": "Energy Report",
		"founder": "Ticket", "influencer": "Brand Safety Review"},
	"memo": {"prepper": "From the desk of {client}", "supervillain": "Henchmen Resources", "guru": "Intention Card",
		"founder": "#general", "influencer": "Brand Brief"},
	"complaint": {"prepper": "Staff Concern Form", "supervillain": "Grievance Form 7B", "guru": "Guest Feedback Card",
		"founder": "Anonymous Feedback (Named)", "influencer": "Comment Moderation Log"},
	"sign": {"prepper": "Bunker Protocol", "supervillain": "Lair Policy", "guru": "Retreat Etiquette",
		"founder": "Office Norms", "influencer": "Studio Rules"},
	"voicemail": {"*": "1 new voicemail · {client}"},
	"sticky": {"*": ""},
}

## The story notes: client -> floor -> lines. Floor 1 sets up, floor 2 escalates (usually with a hint
## slot), floor 3 is the plan or warning that led to the rolled event (lines with "event").
const STORY := {
	"prepper": {
		1: [
			{"f": "sign", "t": "DOOR DRILL EVERY SUNDAY. DO NOT OPEN THE DOOR DURING THE DRILL. To confirm the door is sealed, ask Sir."},
			{"f": "memo", "t": "Staff will shelter in place. Staff will not shelter in MY place. The panic room seats one."},
			{"f": "sticky", "t": "Sir says if anything happens he's going \"up top\". Up top is a second bunker. — {staff}"},
			{"f": "report", "t": "Stockpile audit: rations, 40 years. Water, 40 years. Corn, do not ask. Exorcism supplies: none."},
		],
		2: [
			{"f": "memo", "t": "Shelter plan: {staff} to the {staff_room}, with the good silver. The silver has priority."},
			{"f": "voicemail", "t": "Me again. If anything happens, save the {prop} in the {prop_room}. Then the staff, if there's time."},
			{"f": "report", "t": "Scratching behind the {gate_room} wall. Sommelier says it's the 1787 \"breathing\". Closed, no action."},
			{"f": "sign", "t": "PRICE TAG, {PROP}: {prop_price}. STAFF ARE CHEAPER. ACT ACCORDINGLY."},
		],
		3: [
			{"f": "memo", "event": "wine cellar", "t": "Door drill, Sunday: open the cellar door to confirm it is sealed. If it is sealed, it won't open. Simple."},
			{"f": "sticky", "event": "home cinema", "t": "Movie night: Sir wants the projector pointed at the floor seal \"for ambience\". Doing it under protest. — {staff}"},
			{"f": "sign", "event": "panic room", "t": "DOOMSDAY DRILL: LED CANDLES ONLY. (In pen, underneath: \"ordered wax. they came with a book.\")"},
			{"f": "memo", "t": "Contingency 7 (demons) is delegated to Contingency 8 (contractors). Contingency 8 is cheaper."},
			{"f": "voicemail", "t": "It's me. The {origin} has been humming. If it stops humming, don't tell me. Just call someone cheap."},
		],
	},
	"supervillain": {
		1: [
			{"f": "memo", "t": "To all henchmen: the imp is NOT a pet. Stop naming it. Its name is Biscuit. Stop calling it Biscuit."},
			{"f": "sign", "t": "DAYS SINCE LAST ACCIDENT: 0. (The 0 is printed on. It came that way.)"},
			{"f": "complaint", "t": "I was promised dental. I have been bitten twice by Biscuit. Biscuit is not covered by dental. — {staff}"},
			{"f": "voicemail", "t": "This is {client}. The countdown is for rehearsal only. Whoever lets it reach zero becomes the rehearsal."},
		],
		2: [
			{"f": "memo", "t": "Alarm protocol: {staff} shelters in the {staff_room}. Lunch will not be provided. It never is."},
			{"f": "complaint", "t": "Grievance: I'm assigned to shelter in the {staff_room} in an emergency. It has no exit. Please advise. — {staff}"},
			{"f": "report", "t": "The floor in the {gate_room} is warm and humming. Classified as a feature. Action taken: corn."},
			{"f": "sign", "t": "ASSET REGISTER: {PROP}, {prop_price}. HENCHMEN CAN BE REPLACED. THE {PROP} CANNOT."},
		],
		3: [
			{"f": "complaint", "event": "henchmen barracks", "t": "Someone in the barracks keeps Biscuit under a bunk and feeds it. It is bigger now. It has friends over. — {staff}"},
			{"f": "sign", "event": "throne room", "t": "COUNTDOWN REHEARSALS MUST STOP BEFORE ZERO. (In pen: \"who is in charge of stopping?\")"},
			{"f": "memo", "event": "vat room", "t": "Labelling policy: any vat marked DO NOT OPEN must also say why. Interns: this is not a challenge."},
			{"f": "memo", "h": "Monologue, draft 6", "t": "\"...and once the gate is open, none shall close it!\" Margin note: check if contractors can."},
			{"f": "voicemail", "t": "It's {client}. Nobody goes into the {origin} without me. Nobody sits on my throne. I will know."},
		],
	},
	"guru": {
		1: [
			{"f": "complaint", "t": "The retreat was transformative. The basement hums at night. I have never felt so watched. 5 stars."},
			{"f": "sign", "t": "THIS IS A SHOE-FREE, PHONE-FREE, FEAR-FREE SPACE. Please leave your fear in the cubbies."},
			{"f": "memo", "t": "Today's intention: abundance. Say it like you mean it. Say it to the floor."},
			{"f": "sticky", "t": "Re-ordered sage. Third time this week. Whatever is under the floor does not like sage. — {staff}"},
		],
		2: [
			{"f": "memo", "t": "If the energy turns, {staff} leads everyone to the {staff_room} and breathes. In for four. Out for four."},
			{"f": "report", "t": "Reading, {gate_room}: intense. Source: a crack in the floor. Recommended action: more crystals."},
			{"f": "voicemail", "t": "Hiii, it's {client}. Nobody use the {gate_room} this week. Its energy is unaligned. Namaste."},
			{"f": "sign", "t": "PLEASE BE GENTLE WITH THE {PROP}. It holds a lot of energy."},
		],
		3: [
			{"f": "memo", "event": "yoga studio", "t": "Closing ceremony: open your hearts, open your minds, open the circle. Don't worry about closing anything."},
			{"f": "report", "event": "meditation dome", "t": "Sound bath, gong strike 107: something underneath hummed back. Strike 108 is booked for Friday."},
			{"f": "sign", "event": "cold plunge", "t": "COLD PLUNGE: 3 MINUTES MAXIMUM. Do not go deeper than the water. The water is deeper than it was."},
			{"f": "complaint", "t": "The {origin} was lovely, but something kept knocking from below. Is that included? 3 stars."},
			{"f": "voicemail", "t": "It's {client}. Don't book anyone into the {origin} until it stops breathing. Lovely energy, though."},
		],
	},
	"founder": {
		1: [
			{"f": "memo", "t": "is anyone else hearing chanting from sublevel 4? asking for the standup"},
			{"f": "memo", "h": "OKRs", "t": "Q3: open the gate. KR1: find the gate. KR2: define \"open\". KR3: figure out closing later."},
			{"f": "sign", "t": "WE ARE A FAMILY. Families do not discuss the basement."},
			{"f": "report", "h": "Board Notes", "t": "Pitch deck, slide 12: \"Summoning. TAM: infinite.\" Risks identified: none. We did not look."},
		],
		2: [
			{"f": "memo", "t": "fire drill reminder: {staff}, your muster point is the {staff_room}. bring your laptop. you are still on call"},
			{"f": "report", "t": "#4096: the {gate_room} floor is warm and making a noise. Priority: P3. Assignee: unassigned."},
			{"f": "report", "h": "Asset Register", "t": "{prop}, {prop_room}, {prop_price}. Interns are on a stipend. Replace accordingly."},
			{"f": "voicemail", "t": "Quick sync from {client}: the {gate_room} is off-limits pending facilities. Love the energy."},
		],
		3: [
			{"f": "memo", "event": "keynote stage", "h": "All-hands agenda", "t": "1. Demo. 2. Summon a stakeholder, live. 3. Q&A, if it allows questions."},
			{"f": "memo", "event": "data center", "h": "#growth", "t": "idea: put the goat in the data center and see what scales. no downside. thoughts?"},
			{"f": "memo", "event": "ping-pong lounge", "h": "Calendar invite", "t": "Offsite, Friday, sublevel 4. Agenda: break the seal (team building), ping-pong, retro."},
			{"f": "sign", "t": "THE {ORIGIN} IS A NO-MEETING ZONE. Something down there keeps booking it."},
			{"f": "voicemail", "t": "{client} here. Whatever is under the {origin}, let's not tell the board. We'll call it a pivot."},
		],
	},
	"influencer": {
		1: [
			{"f": "memo", "h": "Drafts", "t": "Caption: \"Not an ad (it is an ad).\" Edited 2:14 a.m.: \"also i think the floor is breathing\""},
			{"f": "sign", "t": "QUIET: RECORDING. If you hear chanting, it's the sound pack. (In pen: \"we don't have a sound pack\")"},
			{"f": "sticky", "t": "Do not film the basement. Do not tag the basement. The basement is not on brand. — Brand Safety"},
			{"f": "memo", "t": "Mood board: \"ancient\". It was supposed to say \"aesthetic\". The vendor delivered \"ancient\"."},
		],
		2: [
			{"f": "memo", "t": "Shoot safety: if anything happens, {staff} gets everyone to the {staff_room}. Phones out. Content is content."},
			{"f": "voicemail", "t": "Heyyy it's {client}. No shoots in the {gate_room}, the floor keeps glitching. Like, physically."},
			{"f": "report", "t": "The {gate_room} is on the do-not-film list. Reason given: \"vibes\". Reviewed: no."},
			{"f": "sign", "t": "#GIFTED: {PROP}. RETAIL {prop_price}. DO NOT LEAN ON IT FOR CONTENT."},
		],
		3: [
			{"f": "memo", "event": "content studio", "t": "Giveaway stream, 9 p.m. Rules: anyone following can win. Anyone. Legal says \"anyone\" is fine."},
			{"f": "sticky", "event": "gifting suite", "t": "A box came for the gifting suite with no sender and it hums. Saving it for the unboxing. — {staff}"},
			{"f": "memo", "event": "podcast room", "h": "Drafts", "t": "Collab post, embargoed to Friday: \"the entity and I are SO excited.\" DO NOT POST EARLY."},
			{"f": "sign", "t": "THE {ORIGIN} IS A NO-FILTER ZONE. (In pen: \"it's already like that in there.\")"},
			{"f": "voicemail", "t": "It's {client}. If the {origin} starts glowing again, just, like, film it? Kidding. Unless?"},
		],
	},
}

const PEST_HEADER := "Pest Control · Site Visit"
const INSURANCE_HEADER := "Insurance Schedule"

## Pest-control tickets (the floor-1 hint slip), by the contract's pest.
const PEST_TICKETS := {
	"swarmer": "Small red things in the vents, in packs. They circle between bites. Technician's advice: aim wide.",
	"grunt": "Bones in the walls, walking. Each one raises its sword before it swings. Technician's advice: step back.",
	"archer": "Hooded things on the high shelves. Arrows fly flat, so a ledge is a wall. Technician's advice: close in.",
	"brute": "Something heavy that can't climb. A red ring fills before it slams. Technician's advice: get on something tall.",
	"everything": "We found one of everything. Quote attached. The quote is also one of everything.",
}

## The other hint slips, by the fact they give.
const HINTS := {
	"staff": [
		{"f": "sign", "t": "SHELTER POINT: {STAFF_ROOM}. ASSIGNED: {STAFF}. Bring water, a torch and a positive attitude."},
		{"f": "memo", "h": "Drill Roster", "t": "{staff_count} staff on this level. {staff} shelters in the {staff_room}. Last drill: {staff} was late."},
	],
	"gate": [
		{"f": "sign", "t": "{GATE_ROOM}: DO NOT ENTER. FLOOR UNDER REVIEW. (In pen: \"it hums.\")"},
		{"f": "report", "t": "{gate_count} warm spots on this level's floor plan, one of them in the {gate_room}. Status: monitoring."},
	],
	"prop": [
		{"f": "report", "h": INSURANCE_HEADER, "t": "{prop}, {prop_room}: {prop_price}. Condition: fine. Please keep it that way."},
		{"f": "sign", "h": INSURANCE_HEADER, "t": "{PROP}: VALUED AT {prop_price}. Please admire from at least one fireball away."},
	],
}

## A sewer cluster's paperwork (docs/design/sewer-concept.md C3, "Polish as built"; SewerNotePlanner), from before the
## outbreak like every note: by kind, one line of each kind a cluster, on the dry decks by the water. {sewer_room} is the
## sewer theme row's note word (NoteFacts, only on a floor with a cluster). The stair foot's own sign is SewerPlanner.SIGNS.
## The user picked the text (2026-10-21): one line for each kind. The rota has none yet: both drafts were rejected, so
## "rota" is [] and SewerNotePlanner places no rota note until the user picks one.
const SEWER := {
	"crossing": [   # on a deck where a flooded hall meets a room
		{"f": "sign", "h": "Caution", "t": "GATOR CROSSING. Do not make eye contact. Do not make any contact."},
	],
	"rota": [],     # by the water in the stair's room (open: no line picked yet)
	"pump": [       # beside a sump pump
		{"f": "report", "h": "Pump Log", "t": "Pump 2 tripped the panel again. Reset it standing in the water. Do not reset it standing in the water."},
	],
	"drink": [      # by the outfall, where the stair's sign is not already the DO NOT DRINK one
		{"f": "sign", "t": "NON-POTABLE WATER. DO NOT DRINK. Do not fill the coffee machine from here either, {staff}."},
	],
}

## Which hint a floor's slip gives, in order of preference (the first whose facts exist and that the
## story note did not already give). "pest" always exists, so it ends every list.
const HINT_ORDER := {
	1: ["pest"],
	2: ["staff", "gate", "prop", "pest"],
	3: ["prop", "staff", "pest"],
}

## The dispatch floor banners (dispatch talking live on the headset, not a note). Each banner is ONE thought: the
## incident or the situation, leading straight into what it means for the crew on THIS floor. No generic tips (the
## pay is on the job board and the tracker). Floor 1 is always {incident}: the contract's event as dispatch tells
## it, with the staff tied to it (ClientArchetype events, "dispatch"). Checked against hellgate.gd: a closed gate
## stops spawning; closing the origin gate stops every gate's spawns.
const DISPATCH := {
	1: [
		"{incident}",
	],
	2: [
		"The gates on this floor are feeding the {pest} problem. Close them and it stops coming.",
		"The {origin} is still a floor below, so every gate up here keeps sending more. Close the gates.",
		"Halfway down and the {pest} problem has gates now. Close them and this floor goes quiet.",
		"Some of the staff made it this far before the {pest} did. Find them, then find the elevator.",
	],
	3: [
		"The {origin}'s on this floor. Close the big gate and the whole site goes quiet.",
		"This is where it started, in the {origin}. Close the gate there and every other gate stops with it.",
		"The big gate is in the {origin}. Closing it stops the site.",
	],
}

## The headset line when the origin gate closes (Game).
const ORIGIN_SHUT := "The origin gate is shut. The site calms down. The invoice does not."
## The whole crew is down: dispatch on the headset, not a line of screen text (user, 2026-10-20).
const WIPE := "Guys? You okay? I'm calling the medics."
## More of what used to be screen text, now dispatch on the headset (user, 2026-10-20: "Fix the screen messages you
## recommend switching to radio"). No names, like the rescue calls.
const FLOOR_CLEAN := "Floor's clean. Nice work."
const STAFF_LOST := "We lost one of the staff."
const YOU_DOWN := "You're down. Sit tight, they'll get you up."
const EXIT_DOWN := "Copy, heading down."
const EXIT_OUT := "Copy, clocking you out."

## The sewer's calls (docs/design/sewer-concept.md, "Polish as built"; user, 2026-10-21: "the service level, the gator, the
## live wire"): each one at most once a floor, on the machine that sees it happen (SewerCalls). No names; one read each.
## Reviewed by the user (2026-10-21). The gator call says "expensive": "insured" "extends the fiction too far".
const SEWER_DOWN := "You're on the service level. Everything down there is wet, including the wiring."   ## a hero goes down the service stair
const GATOR_SEEN := "That's the client's gator. It's expensive and it bites."                             ## a gator comes into view
const GATOR_BILLED := "Gator's down. The client will want that itemized."                                ## a gator dies (billed to its killer)
const WIRE_LIVE := "Somebody broke the panel. The water's live, so stay on the decks."                   ## a panel's cable hits the water
const WIRE_SHOCK := "That was the panel. Get out of the water."                                          ## ... and shocks a hero
const SEWER_CALLS: Array[String] = [SEWER_DOWN, GATOR_SEEN, GATOR_BILLED, WIRE_LIVE, WIRE_SHOCK]

## Dispatch calls in on the headset to confirm a rescue (user, 2026-10-19: "a headset call bubble ... control calling
## in confirming"), in the DispatchBanner rather than loose text on the screen. One line, dispatch's deadpan voice. No
## pay in the line (user, 2026-10-19: "trim all the mentions of {pay}"): every line can be voiced ahead of time
## (DispatchVoice enumerates them). %d is how many rode out together. No employee names, until the voice is right (user,
## 2026-10-20: a clip per employee made the render slow); the banner and the HUD still name them elsewhere.
const RESCUE_ONE: Array[String] = [
	"Copy, one out.",
	"Somebody just walked past my desk.",
	"Got one. All fingers accounted for.",
	"One more topside, asking for a lawyer.",
]
const RESCUE_MANY: Array[String] = [
	"Copy, %d staff out.",
	"%d of them just came through.",
	"Headcount up by %d.",
]

## Which hint kind a slot belongs to (so a hint slip never repeats what the story note gave).
const SLOT_KIND := {
	"staff": "staff", "STAFF": "staff", "staff_room": "staff", "STAFF_ROOM": "staff", "staff_count": "staff",
	"gate_room": "gate", "GATE_ROOM": "gate", "gate_count": "gate",
	"prop": "prop", "PROP": "prop", "prop_room": "prop", "prop_price": "prop",
}

## Every slot a line may use (NoteFacts provides them).
const SLOTS: Array[String] = ["client", "staff", "STAFF", "staff_room", "STAFF_ROOM", "staff_count", "gate_room", "GATE_ROOM",
	"gate_count", "prop", "PROP", "prop_room", "prop_price", "origin", "ORIGIN", "pest", "incident", "sewer_room"]


## The story lines for a client and floor; on the origin floor, the lines keyed to the rolled event
## win when there are any (the payoff), otherwise the generic ones.
static func story_lines(archetype: String, floor_n: int, origin: String) -> Array:
	var by_floor: Dictionary = STORY.get(archetype, STORY["prepper"])
	var lines: Array = by_floor.get(clampi(floor_n, 1, 3), [])
	var keyed: Array = []
	var plain: Array = []
	for ln: Dictionary in lines:
		if ln.has("event"):
			if str(ln["event"]) == origin:
				keyed.append(ln)
		else:
			plain.append(ln)
	return keyed if not keyed.is_empty() else plain


## The candidate hint lines of one kind ("pest" needs the contract's pest kind).
static func hint_lines(kind: String, pest: String) -> Array:
	if kind == "pest":
		return [{"f": "report", "h": PEST_HEADER, "t": str(PEST_TICKETS.get(pest, PEST_TICKETS["everything"]))}]
	return HINTS.get(kind, [])


## The {slot} names in a text, in order (duplicates kept once).
static func slots_in(text: String) -> Array[String]:
	var out: Array[String] = []
	var i := text.find("{")
	while i >= 0:
		var j := text.find("}", i)
		if j < 0:
			break
		var s := text.substr(i + 1, j - i - 1)
		if not out.has(s):
			out.append(s)
		i = text.find("{", j)
	return out


## True when every slot of `text` has a fact.
static func can_fill(text: String, facts: Dictionary) -> bool:
	for s in slots_in(text):
		if not facts.has(s) or str(facts[s]) == "":
			return false
	return true


static func fill(text: String, facts: Dictionary) -> String:
	var out := text
	for s in slots_in(text):
		out = out.replace("{%s}" % s, str(facts.get(s, "")))
	return out


## The hint kinds a line's slots give away ("staff", "gate", "prop").
static func kinds_of(text: String) -> Array[String]:
	var out: Array[String] = []
	for s in slots_in(text):
		var k := str(SLOT_KIND.get(s, ""))
		if k != "" and not out.has(k):
			out.append(k)
	return out


## Keep the lines whose slots this floor can fill, then pick one with `rng`. {} when none survive.
static func pick(lines: Array, facts: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var ok: Array = []
	for ln: Dictionary in lines:
		if can_fill(str(ln["t"]), facts):
			ok.append(ln)
	if ok.is_empty():
		return {}
	return ok[rng.randi_range(0, ok.size() - 1)]


## The slip header for a line: its own "h", else the format's header for this client. Filled.
static func header_of(line: Dictionary, archetype: String, facts: Dictionary) -> String:
	var h := ""
	if line.has("h"):
		h = str(line["h"])
	else:
		var per: Dictionary = HEADERS.get(str(line["f"]), {})
		h = str(per.get(archetype, per.get("*", "")))
	return fill(h, facts)


## The verb on the use prompt for a format.
static func verb_of(format: String) -> String:
	return str(VERBS.get(format, "Read"))
