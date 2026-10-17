class_name ClientArchetype
extends RefCounted
## The client table behind every contract (docs/design/contracts.md, "Contract generation").
## Each archetype supplies: the site type (bunker / lair), the pest pool, a name generator, the
## objective mix, a pay scale, and the flavour text for the job card and the invoice.
##
## Tone: deadpan corporate. The clients never appear in person; they exist as letterhead.
##
## Pest ids are MonsterFactory kinds ("grunt", "archer", "brute", "swarmer") or "everything".

const IDS: Array[String] = ["prepper", "supervillain", "guru", "founder", "influencer"]

## Display names of the monster kinds as the client would write them.
const PEST_NAMES := {
	"grunt": "skeletons",
	"archer": "archers",
	"brute": "brutes",
	"swarmer": "imps",
	"everything": "everything",
}

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
		"warning": "Property: 1787 wine collection and a home cinema. Insured, but not by us.",
		"events": [
			{"text": "During the annual door drill, someone opened the door to confirm it was sealed.", "origin": "wine cellar"},
			{"text": "Movie night went ahead with the projector aimed at the wrong seal.", "origin": "home cinema"},
			{"text": "The doomsday drill was run with real candles.", "origin": "panic room"},
		],
		"clues": [
			"A laminated sign: DO NOT OPEN THE DOOR DURING THE DRILL (the drill is ongoing).",
			"An incident log, page 2 of 41. Page 1 is missing. So is the sommelier.",
			"A chalk circle where the rug used to be. The rug has been returned to inventory.",
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
			{"text": "The henchmen tried to tame an imp. It did not take.", "origin": "henchmen barracks"},
			{"text": "The doomsday countdown was started as a rehearsal.", "origin": "throne room"},
			{"text": "A vat labelled DO NOT OPEN was opened by interns.", "origin": "vat room"},
		],
		"clues": [
			"A memo: 'Imps are NOT pets. Stop naming them.' It is signed by the imps.",
			"A clipboard: days since last accident, crossed out, then crossed out again.",
			"A monologue draft, 14 pages. The demon interrupted on page 3.",
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
			{"text": "The closing ceremony opened a gate in the yoga studio.", "origin": "yoga studio"},
			{"text": "A sound bath resonated with something underneath.", "origin": "meditation dome"},
			{"text": "The cleanse went deeper than the brochure promised.", "origin": "cold plunge"},
		],
		"clues": [
			"A vision board. Someone has added 'a door' in red marker. It is a door.",
			"Burnt sage on every surface. It did not help. It was never going to help.",
			"A feedback card: 'The energy was intense. 4 stars, would manifest again.'",
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
			{"text": "The all-hands demo summoned a stakeholder from below.", "origin": "keynote stage"},
			{"text": "A growth hack involved a goat. It scaled.", "origin": "data center"},
			{"text": "The offsite broke a seal on sublevel 4. Culture is up.", "origin": "ping-pong lounge"},
		],
		"clues": [
			"A whiteboard: 'Q3 OKR: seal the gate. KR1: find the gate. KR2: define seal.'",
			"A Slack export: 'is anyone else hearing chanting? asking for the standup'",
			"A pitch deck, slide 12: 'Summoning (TAM: infinite).'",
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
			{"text": "A giveaway stream opened a gate behind the ring light.", "origin": "content studio"},
			{"text": "An unboxing unboxed more than intended.", "origin": "gifting suite"},
			{"text": "A collab with an entity was announced early.", "origin": "podcast room"},
		],
		"clues": [
			"A sponsored post, 4.2M views: 'Not an ad (it is an ad). Also, I think the floor is breathing.'",
			"A mood board. The mood is 'ancient'. It was supposed to be 'aesthetic'.",
			"A brand deal contract. Clause 9 grants the entity 'creative control'.",
		],
		"footers": {
			"good": "Love this for us! Payment is in the algorithm.",
			"mid": "It's giving 'fine'. We will be tagging you in a story.",
			"bad": "This is not on-brand. We are unfollowing your invoice.",
			"incap": "Your crew has been incapacitated on stream. Engagement is up. Thank you.",
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
}

## Generic lines for floors 1-2 ("the incident is spreading").
const SPREAD_LINES: Array[String] = [
	"Residue from the incident is migrating upward. Treat as billable.",
	"Stray pests have followed the freight shaft up from the origin.",
	"Early signs of the incident: scorch marks, a smell, a lawsuit.",
	"The incident is below. Its tenants are not staying below.",
]


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
