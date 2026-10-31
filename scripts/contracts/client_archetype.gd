class_name ClientArchetype
extends RefCounted
## The client table behind every contract (docs/design/contracts.md, "Contract generation").
## Each archetype supplies: the site type (bunker / lair; mansion / church for the haunted ones), the pest pool, a name generator, the
## objective mix, a pay scale, and the flavour text for the job card and the invoice. The notes and the
## dispatch floor banners live in NoteCopy.
##
## Tone: deadpan corporate. The clients never appear in person; they exist as letterhead.
##
## Pest ids are MonsterFactory kinds ("grunt", "archer", "brute", "swarmer") or "everything".
##
## PEST FAMILIES (docs/design/haunted-build-plan.md, H1): every client's row names its site's family. "gate": the hellgate
## contracts (demons, the five clients of IDS). "dead": the haunted contracts (new-themes.md "Ghost house"): a haunted
## mansion or church, no hellgates, and packs only from FAMILY_KINDS["dead"] (until H3, today's skeleton). The haunting is
## tied to the site, so a mansion or church client is always "dead". One family per contract.

## The hellgate clients. Their order is part of every contract seed (ContractRun.make's dice, ContractBoard.run_for_seed's
## seed % size, the board's shuffle), so a new client never goes in here: the haunted ones are HAUNTED_IDS.
const IDS: Array[String] = ["prepper", "supervillain", "guru", "founder", "influencer"]
## The haunted clients (family "dead"): one per haunted site. The board deals one of them on its own dice (ContractBoard).
const HAUNTED_IDS: Array[String] = ["heir", "parish"]
## Every client, IDS first (an archetype's index here seeds its contracts, so the hellgate clients keep theirs).
const ALL_IDS: Array[String] = ["prepper", "supervillain", "guru", "founder", "influencer", "heir", "parish"]

const FAMILY_GATE := "gate"
const FAMILY_DEAD := "dead"
## The monster kinds a family's packs and pest come from ([] = any kind but a family's own, the hellgate family's mix). The
## dead family (H3) is the skeleton (MonsterDefs "grunt", "skeletons") and the zombie ("zombie", "zombies": a family kind,
## MonsterDefs "family", which no other pack deals).
const FAMILY_KINDS := {FAMILY_GATE: [], FAMILY_DEAD: ["grunt", "zombie"]}

## The SITE line of the job card, per site type.
const SITE_TITLES := {"bunker": "Survival bunker", "lair": "Villain lair", "mansion": "Haunted mansion", "church": "Haunted church"}

## Display names of the monster kinds as the client would write them (each kind's MonsterDefs "pest"), plus "everything".
static var PEST_NAMES: Dictionary = _pest_names()


static func _pest_names() -> Dictionary:
	var out := MonsterDefs.pest_names()
	out["everything"] = "everything"
	return out

const DATA := {
	"prepper": {
		"title": "Prepper Billionaire",
		"site": "bunker",
		"site_name": "Luxury survival bunker",
		"pests": ["grunt", "swarmer", "swarmer", "brute", "everything"],
		"first": ["Chadwick", "Preston", "Thornton", "Barrett", "Langdon", "Ainsley"],
		"last": ["Vanderkeep", "Aldridge", "Hollis-Crane", "Pemberton", "Strauss-Whitlock"],
		"suffix": ["III", "IV", "Jr.", ""],
		"company": ["%s Continuity Holdings", "%s Resilience Partners", "%s Family Office (Subterranean)"],
		"address": "Sublevel 9, location withheld for your safety",
		"tagline": "Preparedness is a lifestyle.",
		"dept": "Office of Contingency Planning",
		"pay_scale": 1.0,
		"employees": [2, 4],
		"everything_chance": 0.25,
		"warning": "Property: 1787 wine collection and a home cinema. You break it, you pay for it.",
		"events": [
			{"text": "During the annual door drill, someone opened the door to confirm it was sealed.", "dispatch": "Someone opened the door to confirm it was sealed, and the staff are still on the wrong side of it. Bring them out.", "origin": "wine cellar"},
			{"text": "Movie night went ahead with the projector aimed at the wrong seal.", "dispatch": "Movie night ran with the projector aimed at the wrong seal. Some of the staff are still in the audience. Bring them out.", "origin": "home cinema"},
			{"text": "The doomsday drill was run with real candles.", "dispatch": "The doomsday drill ran with real candles. Some of the staff are still down here with them. Bring them out.", "origin": "panic room"},
		],
		"footers": {
			"good": "Thank you. The bunker remains confidential. So do you.",
			"mid": "Results are within the range we budgeted for disappointment.",
			"bad": "We expected a more resilient crew. We have noted this in your file.",
			"incap": "Your crew's incapacitation has been logged. Our lawyers have not been incapacitated.",
		},
	},
	"supervillain": {
		"title": "Supervillain",
		"site": "lair",
		"site_name": "Volcano lair",
		"pests": ["grunt", "swarmer", "archer", "brute", "everything"],
		"first": ["Doctor", "Baron", "Lady", "Count", "Admiral", "Madame"],
		"last": ["Malvolio", "Von Doom-Smythe", "Grimsby", "Nefarious", "Blackwater", "Cruelle"],
		"suffix": ["", "", "the Terrible", "of Sector 7"],
		"company": ["%s Dominion Ltd.", "%s Global Menace Inc.", "The %s Organization"],
		"address": "Hollowed Volcano, Level B, ask for Gary",
		"tagline": "World domination, on time and on budget.",
		"dept": "Henchmen Resources",
		"pay_scale": 1.25,
		"employees": [2, 4],
		"everything_chance": 0.3,
		"warning": "Property: doomsday console, throne, one (1) irreplaceable shark. Please do not hit the shark.",
		"events": [
			{"text": "The henchmen tried to tame an imp. It did not take.", "dispatch": "The henchmen tried to tame an imp and it did not take. Some of the staff are still down here with it. Bring them out.", "origin": "henchmen barracks"},
			{"text": "The doomsday countdown was started as a rehearsal.", "dispatch": "Someone started the doomsday countdown as a rehearsal. Some of the staff are still down here. Bring them out.", "origin": "throne room"},
			{"text": "A vat labelled DO NOT OPEN was opened by interns.", "dispatch": "Interns opened a vat marked DO NOT OPEN. Some of them are still down here. Bring them out.", "origin": "vat room"},
		],
		"footers": {
			"good": "Acceptable. You may keep your lives. Remittance will follow.",
			"mid": "The plan is intact. Mostly. We will invoice you for the difference.",
			"bad": "This was not in the plan. Nothing about this was in the plan.",
			"incap": "Your crew has been incapacitated. Henchmen will be dispatched to collect the equipment.",
		},
	},
	"guru": {
		"title": "Wellness Guru",
		"site": "bunker",
		"site_name": "Wellness retreat (basement)",
		"pests": ["swarmer", "grunt", "archer", "everything"],
		"first": ["Sunny", "Aurelia", "Kai", "Sage", "Luna", "Ocean"],
		"last": ["Wavecrest", "Moonwhistle", "Oakhaven", "Starling-Ray", "Brightwater"],
		"suffix": ["", "", "(they/them)", "PhD (honorary)"],
		"company": ["%s Mindful Living", "%s Holistic Ventures", "The %s Method"],
		"address": "The Stillness Annex, basement level, no shoes",
		"tagline": "Heal from within. Billed from without.",
		"dept": "Guest Harmony and Billing",
		"pay_scale": 0.8,
		"employees": [2, 3],
		"everything_chance": 0.2,
		"warning": "Property: crystal collection, a sound bath dome and 60 candles. Please bring a calm exit.",
		"events": [
			{"text": "The closing ceremony opened a gate in the yoga studio.", "dispatch": "The closing ceremony opened a gate in the yoga studio. Some of the staff are still sitting in the circle. Bring them out.", "origin": "yoga studio"},
			{"text": "A sound bath resonated with something underneath.", "dispatch": "A sound bath got an answer from something underneath. Some of the staff are still listening. Bring them out.", "origin": "meditation dome"},
			{"text": "The cleanse went deeper than the brochure promised.", "dispatch": "The cleanse went deeper than the brochure promised. Some of the staff are still in it. Bring them out.", "origin": "cold plunge"},
		],
		"footers": {
			"good": "We receive your work with gratitude. Payment will be released with intention.",
			"mid": "The energy was fine. We will be sending you a feedback form.",
			"bad": "Your presence disrupted the space. We have rebalanced the invoice.",
			"incap": "Your crew is resting. We encourage them to rest further. Namaste.",
		},
	},
	"founder": {
		"title": "Tech Founder",
		"site": "lair",
		"site_name": "Disrupted data-center campus",
		"pests": ["archer", "swarmer", "brute", "everything"],
		"first": ["Jaxon", "Brinley", "Tanner", "Devon", "Skylar", "Nolan"],
		"last": ["Bytewise", "Stackhouse", "Nakamura-Reyes", "Hackett", "Foundry"],
		"suffix": ["", "(CEO)", "(ex-Google)", "(Series B)"],
		"company": ["%s Labs", "%s Technologies, Inc.", "%s AI (pre-revenue)"],
		"address": "Subbasement 4, next to the server racks, turn left at the beanbags",
		"tagline": "Move fast. Break seals.",
		"dept": "People Operations",
		"pay_scale": 1.5,
		"employees": [3, 4],
		"everything_chance": 0.35,
		"warning": "Property: server racks, a ping-pong table and a $40,000 espresso machine named Kevin.",
		"events": [
			{"text": "The all-hands demo summoned a stakeholder from below.", "dispatch": "The all-hands demo summoned a stakeholder from below. Some of the staff are still in the meeting. Bring them out.", "origin": "keynote stage"},
			{"text": "A growth hack involved a goat. It scaled.", "dispatch": "Someone put a goat in the data center and it scaled. Some of the staff are still down here with it. Bring them out.", "origin": "data center"},
			{"text": "The offsite broke a seal on sublevel 4. Culture is up.", "dispatch": "The offsite broke a seal on sublevel 4. Some of the staff are still on the offsite. Bring them out.", "origin": "ping-pong lounge"},
		],
		"footers": {
			"good": "Great job, team. We are aligning on payment. Please hold.",
			"mid": "This was fine. Let's circle back on the delta.",
			"bad": "Feedback: not a culture add. Net payout reflects the learnings.",
			"incap": "We are sunsetting your crew's engagement, effective immediately.",
		},
	},
	"influencer": {
		"title": "Influencer",
		"site": "bunker",
		"site_name": "Content studio (sub-level)",
		"pests": ["swarmer", "grunt", "archer", "everything"],
		"first": ["Brayden", "Taylor-Rae", "Kaylee", "Jordyn", "Madison", "Tripp"],
		"last": ["Glow", "Vlogsworth", "Sparkle-Jones", "Flexington", "Rayne"],
		"suffix": ["", "", "(@real)", "(verified)"],
		"company": ["%s Creative Studios", "%s x Brand Partners", "%s Media (LLC)"],
		"address": "Content Bunker B2, 'the good light' side",
		"tagline": "Link in bio. Gate in basement.",
		"dept": "Partnerships and Brand Safety",
		"pay_scale": 0.9,
		"employees": [2, 4],
		"everything_chance": 0.25,
		"warning": "Property: ring lights, a gifting suite and a branded wall. Please film nothing. Please hit nothing.",
		"events": [
			{"text": "A giveaway stream opened a gate behind the ring light.", "dispatch": "A giveaway stream opened a gate behind the ring light. Some of the staff are still live. Bring them out.", "origin": "content studio"},
			{"text": "An unboxing unboxed more than intended.", "dispatch": "An unboxing unboxed more than intended. Some of the staff are still holding the box. Bring them out.", "origin": "gifting suite"},
			{"text": "A collab with an entity was announced early.", "dispatch": "A collab with an entity went out early. Some of the staff are still in the collab. Bring them out.", "origin": "podcast room"},
		],
		"footers": {
			"good": "Love this for us! Payment is in the algorithm.",
			"mid": "It's giving 'fine'. We will be tagging you in a story.",
			"bad": "This is not on-brand. We are unfollowing your invoice.",
			"incap": "Your crew has been incapacitated on stream. Engagement is up. Thank you.",
		},
	},
	# The haunted clients (HAUNTED_IDS, family "dead"; haunted-build-plan.md H1). Every player-facing string below is a
	# PROPOSAL awaiting the user's review (listed in the build plan's "H1 as built"). The pest is always one of the family's
	# kinds (skeletons or zombies since H3, rolled per contract), never "everything".
	"heir": {
		"title": "Estate Heir",
		"site": "mansion",
		"family": "dead",
		"site_name": "Ancestral manor",
		"pests": ["grunt", "zombie"],
		"first": ["Peregrine", "Cordelia", "Ambrose", "Octavia", "Bartholomew", "Winifred"],
		"last": ["Ashgrove", "Blackthorne", "Mortlake", "Ravensworth", "Hollowell"],
		"suffix": ["", "", "the Younger", "Esq."],
		"company": ["The %s Estate", "%s Heritage Trust", "%s Family Office (Probate)"],
		"address": "The Hall, up the long drive, ring twice",
		"tagline": "Old money. Older tenants.",
		"dept": "Office of the Executor",
		"pay_scale": 1.1,
		"employees": [2, 4],
		"everything_chance": 0.0,
		"warning": "Property: four centuries of antiques, a suit of armour and the family portraits. Mind the portraits.",
		"events": [
			{"text": "The will was read at midnight, as the will insisted.", "dispatch": "They read the will at midnight and something in the house took it personally. Some of the staff are still in there. Bring them out.", "origin": "library"},
			{"text": "A seance was held in the ballroom to settle who gets the silver.", "dispatch": "Someone held a seance in the ballroom over the silver, and the dead turned up to contest it. Some of the staff are still down here. Bring them out.", "origin": "ballroom"},
			{"text": "The anniversary dinner set a place for great-grandfather.", "dispatch": "The anniversary dinner set a place for great-grandfather, and he came. Some of the staff are still serving. Bring them out.", "origin": "dining hall"},
		],
		"footers": {
			"good": "The family thanks you. The family is large, and not all of it is living.",
			"mid": "Adequate. Great-grandmother has been informed. She is not pleased.",
			"bad": "The estate will be in touch. So, we suspect, will the house.",
			"incap": "Your crew has been incapacitated. The house has asked whether they may stay.",
		},
	},
	"parish": {
		"title": "Parish Council",
		"site": "church",
		"family": "dead",
		"site_name": "Parish church",
		"pests": ["grunt", "zombie"],
		"first": ["Reverend", "Canon", "Deacon", "Mother", "Father", "Archdeacon"],
		"last": ["Whitlow", "Penhallow", "Ashby", "Greaves", "Underhill"],
		"suffix": ["", "", "(retired)", "OBE"],
		"company": ["The %s Restoration Fund", "St. Agatha's Parish Council (%s, chair)", "The %s Bequest"],
		"address": "The vestry door, round the back, past the yews",
		"tagline": "All are welcome. Most are invoiced.",
		"dept": "Parochial Church Council (Finance)",
		"pay_scale": 0.85,
		"employees": [2, 3],
		"everything_chance": 0.0,
		"warning": "Property: a medieval font, the stained glass and the votive stand. The lead on the roof is already gone.",
		"events": [
			{"text": "The bell-ringers rang a peal that is not in any book.", "dispatch": "The bell-ringers rang a peal nobody wrote, and the churchyard got up to listen. Some of the staff are still inside. Bring them out.", "origin": "nave"},
			{"text": "Evensong ran long. Something stayed for the sermon.", "dispatch": "Evensong ran long and something stayed for the sermon. Some of the staff are still in the pews. Bring them out.", "origin": "nave"},
			{"text": "The harvest supper raised more than the roof fund.", "dispatch": "The harvest supper raised more than the roof fund. Some of the staff are still at the tables. Bring them out.", "origin": "refectory"},
		],
		"footers": {
			"good": "Thank you. A collection will be taken. It will not be for you.",
			"mid": "We give thanks for what was saved. A list of what was not is enclosed.",
			"bad": "The council has prayed over your invoice. The answer was no.",
			"incap": "Your crew has been incapacitated. They are in our prayers, and in the minutes.",
		},
	},
}

## Letterhead / card accent colour per client.
const ACCENTS := {
	"prepper": Color(0.18, 0.42, 0.28),
	"supervillain": Color(0.72, 0.14, 0.16),
	"guru": Color(0.52, 0.36, 0.72),
	"founder": Color(0.14, 0.5, 0.82),
	"influencer": Color(0.92, 0.3, 0.58),
	"heir": Color(0.36, 0.2, 0.12),
	"parish": Color(0.3, 0.24, 0.5),
}

static func get_data(id: String) -> Dictionary:
	return DATA.get(id, DATA["prepper"])


static func has(id: String) -> bool:
	return DATA.has(id)


static func accent_of(id: String) -> Color:
	return ACCENTS.get(id, Color(0.5, 0.5, 0.55))


static func title_of(id: String) -> String:
	return str(get_data(id)["title"])


static func site_of(id: String) -> String:
	return str(get_data(id)["site"])


## The client's pest family ("gate" for every hellgate client: their rows carry none).
static func family_of(id: String) -> String:
	return str(get_data(id).get("family", FAMILY_GATE))


## The monster kinds a family's packs and pest may use ([] = any).
static func family_kinds(family: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(FAMILY_KINDS.get(family, []))
	return out


## The job card's SITE line for a site type.
static func site_title(site_type: String) -> String:
	return str(SITE_TITLES.get(site_type, site_type.capitalize()))


## A readable pest name ("imps", "everything").
static func pest_name(pest: String) -> String:
	return str(PEST_NAMES.get(pest, pest))


## Round to the nearest $100 (pay is always quoted in whole hundreds).
static func round_pay(amount: float) -> int:
	return int(roundf(amount / 100.0)) * 100


## Roll a client name from the archetype's generator: first + last + suffix, and the matching company.
## Returns {"name", "company"}. Deterministic for a given rng state.
static func roll_name(id: String, rng: RandomNumberGenerator) -> Dictionary:
	var d := get_data(id)
	var first: String = _pick(d["first"], rng)
	var last: String = _pick(d["last"], rng)
	var suffix: String = _pick(d["suffix"], rng)
	var nm := "%s %s" % [first, last]
	if suffix != "":
		nm += " " + suffix
	var company: String = str(_pick(d["company"], rng)) % last
	return {"name": nm, "company": company}


static func _pick(arr: Array, rng: RandomNumberGenerator) -> String:
	return str(arr[rng.randi_range(0, arr.size() - 1)])
