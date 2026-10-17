# Notes rethink

Status: **proposal**, 2026-10-17. Nothing here is built. It replaces the `clues` in
`client_archetype.gd`, the `SPREAD_LINES` and `floor_notes` in `contract_story.gd`, the floating
"NOTE" label on `SiteBuilder.ClueNote`, and the "A note: " prefix in `game.gd` `_on_note_read`.

## 0. What is wrong today

| Problem | Example |
|---|---|
| **Double framing.** The banner says "A note:", then the text describes the object again. | "A note: A memo: 'Imps are NOT pets.'" |
| **No information.** No line tells you anything about *this* floor. | "Burnt sage on every surface. It did not help." |
| **Not tied to the story.** Clues are shuffled with no link to the rolled event or the floor. | The floor-3 note can be "KR1: find the gate" while you stand at the gate. |
| **No reason to explore.** One note a floor, always 4–8 cells from the start. | |
| **Generic banners.** The four spread lines are shared by all five clients and repeat every run. | "The incident is below. Its tenants are not staying below." |

## 1. What notes are for

**Rule: every note is a joke with a fact in it.** The joke builds the client; the fact helps the crew.
A note that is only a joke is allowed on floor 1. After that it has to earn its spot.

| Job | How |
|---|---|
| **Character and story** | One authored **story note** per floor, voiced by that client's people. Floor 1 sets up, floor 2 escalates, floor 3 explains the rolled event, right at the origin room. |
| **Actionable hints** | Slots filled from the generated floor: where staff are hiding, which room has a gate, the priciest prop and its room, what the pest does. All true for this floor (section 5). |
| **A reason to explore** | One **hint slip** per floor, placed in a side room off the start–exit route. Finding it pays off as information, not as money. |
| **Something to say** | In co-op the slip shows only to the hero who found it. They have to call it out ("Hodges is in the gym"). That's the north-star rule: give the team something to say to each other. |

**Per floor: 2 notes.**

| Floor | Story note (authored, per client) | Hint slip (templated) |
|---|---|---|
| 1 | near the start, as today: **sets up** the client | a **pest advisory**: what this contract's pest does |
| 2 | mid-floor, on the way to the elevator: **escalates**, and carries a hint slot | staff or gate location |
| 3 | at the origin room's doorway: **pays off** the rolled event | staff location or the priciest prop |

### How a note is shown

| Layer | What | Notes |
|---|---|---|
| **In the world** | The object itself: a yellow square on a wall, a clipboard, a laminated sign on a stand, a blinking desk phone, a letterhead sheet, a pink form. Each format has its own silhouette and colour. | **No floating "NOTE" text.** A slow bob plus a soft glint is enough. It is read automatically on proximity (2.2, as today); no key press. |
| **On the HUD** | A **slip** that slides in at the lower left, drawn in the format's own style (section 2). Its header is the format's own title, so the object is the frame: no "Note:" and no "A memo:". It holds 6–9 s (scaled to length) and never blocks input. A second slip stacks above it (max 2). | Reuses `FormSheet` / `FormTheme` carbons and the Caveat hand font. |
| **The top banner** | Reserved for **dispatch** (section 4), not for notes. | |
| **Debug log** | `[note sticky F2] <text>`. Logs only (passive data collection). | |

## 2. Note formats

Six formats. The format sets the visual and the layout; the client sets the header and the voice.

| Format | In the world | HUD slip | Voice | Best for |
|---|---|---|---|---|
| **Sticky note** | yellow square on a wall, monitor or prop | yellow pad, Caveat handwriting, tilted, signed "— {staff}" | a frightened staff member or henchman, first person | where staff are hiding |
| **Incident report** | clipboard on a hook or the floor | white carbon, typed rows, stamped number | flat procedural; the facts are absurd, the tone isn't | gates, what happened |
| **Laminated sign** | A-frame sign or wall plate, hazard-tape border | glossy white, ALL-CAPS rule plus small print; pen added underneath | policy that events have made wrong | pest advice, prop value |
| **Voicemail** | desk phone with a blinking red light, or a dropped phone | phone-shaped card, "1 new · {client}", transcript | **the client**, the only place they speak (the pitch: clients exist as voicemails) | the client's priorities: their prop, their staff |
| **Client memo** | letterhead sheet on a desk, client accent colour (`ClientArchetype.ACCENTS`) | letterhead with company and dept | corporate, the archetype's tone | floor-1 setup |
| **Complaint form** | pink carbon form pinned to a board | pink carbon, tick boxes, one free-text line | an aggrieved employee filing paperwork mid-disaster | staff location, escalation |

**Headers by client** (the slip's title line):

| Format | Prepper | Supervillain | Guru | Founder | Influencer |
|---|---|---|---|---|---|
| Incident report | Contingency Log | Lair Incident Report | Energy Report | Postmortem | Brand Safety Incident |
| Client memo | From the desk of {client} | Henchmen Resources memo | Intention card | #general (Slack export) | Brand brief |
| Complaint form | Staff Concern Form | Grievance Form 7B | Guest Feedback Card | Anonymous Feedback (named) | Comment Moderation Log |
| Laminated sign | Bunker Protocol | Lair Policy | Retreat Etiquette | Office Norms | Studio Rules |

## 3. Copy

Slots in `{braces}` are filled from the floor (section 5). `{PROP}` / `{ORIGIN}` are upper-case
fills for signs. **Bold** = the default; the others are alternates. F3 lines with an **event** only
appear when that event rolled. They are the payoff, and the generator prefers them.

Format key: **Stk** sticky · **Rep** incident report · **Sign** laminated sign · **VM** voicemail ·
**Memo** client memo · **Cmp** complaint form.

### Prepper Billionaire (bunker)

| Floor | Fmt | Line |
|---|---|---|
| 1 | Sign | **DOOR DRILL IN PROGRESS. DO NOT OPEN THE DOOR. If the door is open, the drill has failed. Remain calm and below.** |
| 1 | Memo | Staff will shelter in place. Staff will not shelter in MY place. The panic room seats one. |
| 1 | Stk | Sir has gone "up top" to wait it out. Up top is a second bunker. — {staff} |
| 1 | Rep | Stockpile audit: rations, 40 years. Water, 40 years. Corn, do not ask. Exorcism supplies: none. |
| 2 | Stk | **Hiding in the {staff_room} with the good silver. Please send a sorcerer. Not the cheap kind. — {staff}** |
| 2 | VM | It's {client}. Don't touch the {prop} in the {prop_room}. Do whatever you like with the staff. |
| 2 | Rep | Page 2 of 41. Page 1 is missing. So is the sommelier. Last seen near the portal in the {gate_room}. |
| 2 | Sign | IN AN EMERGENCY, SAVE THE {PROP}. VALUE: {prop_price}. STAFF ARE INSURED SEPARATELY, AND LESS. |
| 3 | Rep | *wine cellar:* **Drill debrief: the door was opened to confirm it was sealed. It was not. The 1787 is fine. Priorities met.** |
| 3 | Stk | *home cinema:* **Sir pointed the projector at the floor seal "for ambience". The seal is very ambient now. — {staff}** |
| 3 | Sign | *panic room:* **DRILL CANDLES MUST BE LED. (Underneath, in pen: "we only had the wax ones.")** |
| 3 | Memo | Contingency 7 (demons) has been delegated to Contingency 8 (contractors). You are Contingency 8. |
| 3 | VM | It's me again. The {origin} is humming. If it stops humming, don't tell me. Just invoice. |

### Supervillain (lair)

| Floor | Fmt | Line |
|---|---|---|
| 1 | Memo | **To all henchmen: the imp is NOT a pet. Stop naming it. Its name is Biscuit. Stop calling it Biscuit.** |
| 1 | Sign | DAYS SINCE LAST ACCIDENT: 0. (The 0 is printed on. It came that way.) |
| 1 | Cmp | I was promised dental. I have been bitten by something dental does not cover. — {staff} |
| 1 | VM | This is {client}. Kill the demons. Leave the ambience. The ambience took years. |
| 2 | Cmp | **Hiding in the {staff_room} since lunch. Lunch was not provided. Requesting rescue, then lunch. — {staff}** |
| 2 | Stk | Whoever finds this: I'm in the {staff_room}. Tell the boss I died heroically. Don't tell him where. — {staff} |
| 2 | Rep | The portal in the {gate_room} is classified as a feature. The feature is spawning. Action taken: corn. |
| 2 | Sign | DO NOT DAMAGE THE {PROP} ({prop_price}). HENCHMEN CAN BE REPLACED. THE {PROP} CANNOT. |
| 3 | Cmp | *henchmen barracks:* **Re: Biscuit. Biscuit was tamed. Biscuit brought friends. The barracks belong to Biscuit now. — {staff}** |
| 3 | Sign | *throne room:* **COUNTDOWN REHEARSALS MUST NOT REACH ZERO. (In pen: "nobody said when to stop.")** |
| 3 | Rep | *vat room:* **Vat marked DO NOT OPEN. Opened by: interns. Reason given: "It didn't say why." It says why now.** |
| 3 | Memo | Monologue, draft 6, page 3: "And now, contractor, you will—" The rest is scorched. |
| 3 | VM | It's {client}. Close the thing in the {origin}. Do not sit on my throne. I will know. |

### Wellness Guru (bunker)

| Floor | Fmt | Line |
|---|---|---|
| 1 | Cmp | **The retreat was transformative. I am now partly a different species. 4 stars.** |
| 1 | Sign | THIS IS A SHOE-FREE, PHONE-FREE, FEAR-FREE SPACE. Please leave your fear in the cubbies. |
| 1 | Memo | Today's intention: abundance. Abundance has arrived. It has teeth. |
| 1 | Stk | Burnt sage on every surface. It didn't help. Nobody thought it would help. — {staff} |
| 2 | Stk | **We're in the {staff_room}, breathing in for four, out for four. Please hurry. We are on four. — {staff}** |
| 2 | Rep | Reading, {gate_room}: intense. Source: a hole. The hole is not on the floor plan or the price list. |
| 2 | VM | Hiii, it's {client}. The thing in the {gate_room} isn't evil, it's unaligned. Please align it. With fire. |
| 2 | Sign | PLEASE BE GENTLE WITH THE {PROP}. It holds a lot of energy. It also cost {prop_price}. |
| 3 | Cmp | *yoga studio:* **The closing ceremony opened something. I had hoped it would be my heart. 2 stars.** |
| 3 | Rep | *meditation dome:* **Sound bath, gong strike 108. Something underneath struck back.** |
| 3 | Sign | *cold plunge:* **COLD PLUNGE: 3 MINUTES MAXIMUM. Do not go deeper than the water.** |
| 3 | Memo | The {origin} is closed for a private session. The session is a demon. Please knock. |
| 3 | VM | It's {client}. Close the {origin} gently, please. It's had a very big week. |

### Tech Founder (lair)

| Floor | Fmt | Line |
|---|---|---|
| 1 | Memo | **Q3 OKR: seal the gate. KR1: find the gate. KR2: define "seal". KR3: hire contractors (cheap).** |
| 1 | Memo | is anyone else hearing chanting? asking for the standup |
| 1 | Sign | WE ARE A FAMILY. Families do not discuss the basement. |
| 1 | Rep | Pitch deck review, slide 12: "Summoning. TAM: infinite." Risks identified: none. We did not look. |
| 2 | Memo | **wfh today. by home i mean the {staff_room}. by wfh i mean hiding. — {staff}** |
| 2 | Rep | Incident: portal in the {gate_room}. Severity: P0. Owner: you, apparently. Action items: also you. |
| 2 | Stk | Protect the {prop} in the {prop_room}. It cost {prop_price}. The interns are on a stipend. — {staff} |
| 2 | VM | {client} here. Quick sync: there's a gate in the {gate_room}. Can you take it offline? Love the energy. |
| 3 | Rep | *keynote stage:* **All-hands demo: summoned a stakeholder from below. It asked about equity. It is getting equity.** |
| 3 | Memo | *data center:* **the goat scaled. the goat is still scaling. who approved the goat** |
| 3 | Rep | *ping-pong lounge:* **Offsite retro: broke a seal on sublevel 4. Culture is up. Headcount is down.** |
| 3 | Sign | THE {ORIGIN} IS A NO-MEETING ZONE. (It is currently having a meeting.) |
| 3 | VM | {client} here. Close whatever's in the {origin} and we'll call it a pivot. |

### Influencer (bunker)

| Floor | Fmt | Line |
|---|---|---|
| 1 | Memo | **Caption draft: "Not an ad (it is an ad)." Edited 2:14 a.m.: "also i think the floor is breathing"** |
| 1 | Sign | QUIET: RECORDING. If you hear chanting, that is the sound pack. (It is not the sound pack.) |
| 1 | Stk | Do not film anything. Do not hit anything. Do not tag the portal. — Brand Safety |
| 1 | Memo | Mood board: "ancient". It was supposed to say "aesthetic". The vendor delivered "ancient". |
| 2 | Stk | **Hiding in the {staff_room}. Battery at 4%. Please come before I have to go live. — {staff}** |
| 2 | VM | Heyyy it's {client}. Can you do the {gate_room} first? That's where the good light is. |
| 2 | Rep | Portal in the {gate_room}. Sentiment: negative. Engagement: unbelievable. Do not repost. |
| 2 | Sign | THE {PROP} WAS GIFTED. GIFTED MEANS PRICELESS. (It means {prop_price}. We checked.) |
| 3 | Rep | *content studio:* **Giveaway rules: "must be following to win." Something was following. It won.** |
| 3 | Stk | *gifting suite:* **The unboxing ran long. The box kept going. Please don't open any more boxes. — {staff}** |
| 3 | Memo | *podcast room:* **The collab was announced early. The entity has already posted. It has more followers than us.** |
| 3 | Sign | THE {ORIGIN} IS A NO-FILTER ZONE. Everything in there is real now. |
| 3 | VM | It's {client}. Close the thing in the {origin}. And maybe film it closing? Kidding. Unless? |

### Hint slips (all clients)

The floor's second note. The text is shared, the header comes from the client (section 2), so a
prepper's pest advisory reads "Bunker Protocol" and a founder's reads "Office Norms".

| Hint | Fmt | Line |
|---|---|---|
| Pest: imps | Sign | IMPS TRAVEL IN PACKS AND CIRCLE BETWEEN BITES. Something wide, aimed at the middle, is advised. |
| Pest: skeletons | Sign | SKELETONS RAISE THEIR SWORD BEFORE THEY SWING. It is the only courtesy they extend. |
| Pest: archers | Sign | ARCHERS WANT DISTANCE AND HIGH GROUND. Their arrows fly flat. A ledge between you is a wall. |
| Pest: brutes | Sign | BRUTES CANNOT CLIMB. When the red ring fills, be outside it. Or be on something tall. |
| Pest: everything | Sign | PEST: ALL OF THEM. Facilities apologises for the variety. |
| Staff | Stk | If found: I'm in the {staff_room}. Knock twice. Knock once if you're a demon. — {staff} |
| Staff | Rep | Headcount: {staff_count} missing on this level. Last seen in the {staff_room}, "just grabbing something". |
| Gate | Sign | AUTHORISED PORTALS ONLY. The one in the {gate_room} is not authorised. |
| Gate | Rep | Open portals on this level: {gate_count}. Target: 0. The variance is your job. |
| Prop | Sign | {PROP}: {prop_price}. Please admire from at least one fireball away. |

## 4. Floor banners

**Keep them, but give them to dispatch.** The banner is the one line everyone is guaranteed to see,
so it carries the one fact that matters for the floor. Notes are optional and voiced by the client's
side; the banner is the crew's own side, on the headset. Two voices, no overlap.

- **Shown:** top centre, a canary strip (canary is already dispatch's carbon in `FormTheme`) with a
  small headset glyph as the frame. No "Dispatch:" text prefix. Holds 5–6 s.
- **Cut:** `SPREAD_LINES` and "Something is open and it is not the minibar."
- **Floor 1** is two lines: the client's `event` (unchanged; they are good), then one dispatch line.

| Floor | Line |
|---|---|
| 1 | **It started in the {origin}, three floors down. Work your way to it.** |
| 1 | Staff are worth $100 at an exit and $10 anywhere else. Dispatch is not judging. |
| 1 | The client calls it a {pest} problem. Dispatch calls it a three-floor problem. |
| 2 | **Floor 2. {gate_count} gates on this one. Close them and the floor stops refilling.** |
| 2 | Floor 2. Halfway down. The pay gets better. So do the {pest}. |
| 2 | Floor 2. The elevator still has an exit button, if anyone's asking. |
| 3 | **Floor 3. The big one is in the {origin}. Biggest line on the invoice.** |
| 3 | Floor 3. Closing the {origin} gate doesn't clock you out. The elevator does. |
| 3 | Floor 3. This is where it started. Try to finish it here too. |

Floor-2 and floor-3 lines that name a fact (gate count, origin, the clock-out rule) are the defaults,
because they are useful. Check the gate-refill line against the final hellgate rules before shipping.

**Other text:** the `events` and invoice `footers` are the strongest copy in the file; keep them.

## 5. Data: keeping hints true

Facts come from the `SitePlan` the host has just built, so every hint describes the floor you are on.

**Line data** (replaces `"clues"` in `ClientArchetype.DATA`):

```gdscript
"notes": {
    1: [{"f": "sign", "t": "DOOR DRILL IN PROGRESS. ..."}, ...],
    2: [{"f": "sticky", "t": "Hiding in the {staff_room} with the good silver. ... — {staff}"}, ...],
    3: [{"f": "report", "t": "Drill debrief: ...", "event": "wine cellar"}, ...],
},
```

Hint slips, the pest advisories and the dispatch lines live in one shared table (`NoteCopy`), keyed
by hint type, pest kind and floor.

**Facts** (`NoteFacts.from(plan, run) -> Dictionary`), computed once per floor after `_plan_props`:

| Slot | Source | Missing when |
|---|---|---|
| `{client}` | first + last name from the roll (no suffix: "Admiral Grimsby") | never |
| `{staff}`, `{staff_room}` | one entry of `plan.employees` (`name`, `room` → theme name) | no employees on the floor |
| `{staff_count}` | `plan.employees.size()` | 0 |
| `{gate_room}` | a non-origin entry of `plan.gates` (`room` → theme name) | floor 3, or no small gates |
| `{gate_count}` | `run.floor_gates[floor - 1]` | the floor has 0 gates |
| `{prop}`, `{PROP}`, `{prop_room}`, `{prop_price}` | the highest `PricedProp.price_of` in `plan.props` | no props |
| `{origin}`, `{ORIGIN}` | `run.story.origin` ("yoga studio"), not the theme name | never (all floors may say it) |
| `{pest}` | `ClientArchetype.pest_name(run.pest)` | never |

**Room names.** A room is named by its theme (`plan.room_themes[tag]` → "wine cellar", "gym",
"barracks"; the origin room uses the story's own word). Themes repeat on big floors, so when picking
which employee, gate or prop a hint names, **prefer one in a room whose theme is unique on the floor**.
If none is unique, add a landmark: "the gym by the elevator" / "the gym by the entrance" (whichever of
the exit and start it is nearer).

**Picking a line** (host, the floor's seeded RNG, so it is deterministic and the same for everyone):
1. Candidates = the client's lines for this floor. On floor 3, if any line's `event` matches the rolled
   origin, use only those.
2. Drop any line whose slots are missing on this floor.
3. Pick one; fill it with `text.format(facts)`. If no candidate survives, fall back to the slot-free
   lines (every floor has at least one).

`plan.notes` gets `{"cell", "text", "format", "header", "kind": "story"|"hint"}`. `ClueNote` builds the
format's mesh; the HUD slip reads `format` and `header`. Clients only display what the host sent.

**Placement:**
- **Story note:** F1 as today (`_plan_notes`, near the start). F2 in the room nearest halfway between
  start and exit. F3 on a free cell inside the origin room, nearest its entrance, outside the gate's radius.
- **Hint slip:** a room that is not the start, exit or origin room, preferring rooms off the
  start–exit route and far from the start. Claimed as a `ThemeCtx` body like the other props, so
  packages and decor avoid it.

**Tests** (alongside `tests/test_room_themes.gd`):
- every archetype has at least 3 lines per floor and one slot-free line per floor;
- every `events[].origin` has an F3 line with that `event`;
- every slot in every line is a known slot;
- every line filled with the **longest** values (longest theme, prop name, client name) is at most 140
  characters;
- no line starts with "Note", "A note" or "A memo";
- for a seeded plan, the room a hint names actually contains that employee, gate or prop.

## 6. Open questions

1. **Hint slips only for the finder, in co-op?** Recommended (it makes the finder talk), but a crew of
   strangers may miss it. Fallback: show it to everyone, tinted with the finder's colour.
2. **Notes on the invoice?** Optional: "Documents recovered: 4 of 6. Filed." as a deadpan line, and a
   hook for the north-star "secrets found" bonus later.
3. **Voiced voicemails** later: the voicemail is the obvious place for a recorded client line.
