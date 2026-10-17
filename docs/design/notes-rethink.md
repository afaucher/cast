# Notes

Status: **built**, 2026-10-17. Code: `scripts/contracts/note_copy.gd` (all the copy),
`note_facts.gd` (the `{slots}`), `site_builder.gd` `_plan_notes` (choice and placement),
`clue_note.gd` (the world object), `scripts/art/lowpoly/props/note_models.gd` (the per-format models),
`scripts/ui/forms/note_slip.gd` (the on-screen slip), `scripts/ui/dispatch_banner.gd` (the floor banner).
Tests: `tests/test_notes.gd`.

## As decided (user, 2026-10-17)

1. **Every note was written BEFORE the outbreak.** Nobody writes notes afterwards. Notes are memos,
   signs, schedules, sticky notes, voicemails, complaint forms and Slack exports that existed when
   the site was normal, so they **foreshadow** rather than report. Hint facts are pre-outbreak truths
   too: a shelter plan names the staff room, an insurance list names the priciest prop, a pest-control
   ticket describes the pest, a "do not enter" sign or maintenance ticket names the gate room.
2. **Notes are plain interactable set dressing.** Anyone nearby can read any note. Nothing tracks who
   read what, and there is no per-player visibility.
3. **No reward, no objective, nothing on the invoice.** The fun is snooping on your employer.
4. **Dispatch floor banners stay** (dispatch talking live on the headset, not a note).

## 0. What was wrong before

| Problem | Example |
|---|---|
| **Double framing.** The banner said "A note:", then the text described the object again. | "A note: A memo: 'Imps are NOT pets.'" |
| **No information.** No line told you anything about *this* floor. | "Burnt sage on every surface. It did not help." |
| **Not tied to the story.** Clues were shuffled with no link to the rolled event or the floor. | The floor-3 note could be "KR1: find the gate" while you stand at the gate. |
| **No reason to explore.** One note a floor, always 4–8 cells from the start. | |
| **Generic banners.** Four spread lines shared by all five clients. | "The incident is below. Its tenants are not staying below." |

## 1. What notes are for

**Every note is a joke with a fact in it.** The joke is the client, caught off guard in their own
paperwork; the fact is a pre-outbreak truth that still helps the crew. A joke-only note is fine on
floor 1. After that it has to earn its spot.

**Two notes per floor:**

| Floor | Story note (written per client) | Hint slip (templated, shared) |
|---|---|---|
| 1 | near the start: **sets up** the client | **pest-control ticket**: what this contract's pest does |
| 2 | in a room roughly halfway to the elevator: **escalates**, usually with a hint slot | shelter plan (staff), else gate, else prop |
| 3 | in the origin room, near its door: **the plan or warning that led to** the rolled event | insurance list (prop), else shelter plan, else pest |

The hint slip goes in a **side room** (not the start, exit or origin room, preferring rooms off the
start–exit route), so it is a reason to look around. A hint never repeats the kind of fact the floor's
story note already gave.

### How a note is shown

| Layer | What |
|---|---|
| **In the world** | The object itself, one look per format (section 2). No floating "NOTE" text: a small twinkling glint above it says "you can read this". |
| **Reading** | **`[E] Read`** (`[E] Listen` for a voicemail) through the shared use prompt (`game.gd` `use_target()`), like the van, elevator and employees. Priority: van, elevator, employee, then note, so a note never steals a rescue. Walking past does **not** read it. |
| **On the HUD** | E opens a slip at the lower left, drawn in the format's own style. Its title is the format's own header ("Grievance Form 7B", "Pest Control · Site Visit"), so the object is the frame: no "Note:". While it is open the prompt says `[E] Close`; E closes it, and so does walking away (`READ_RANGE` + 0.6). One slip at a time. Never blocks input. |
| **Top banner** | Dispatch only (section 4). |
| **Debug log** | `[note sticky F2] <text>`. |

**Why `[E] Read` (user, 2026-10-17).** Notes are interactables, and the game already has one prompt system for
"E does something here". Read-on-walk fired slips mid-fight in rooms you were only crossing; `[E]` makes snooping a
choice, lets you read twice, and costs nothing (E never casts). Notes come after employees in the priority, so
rescuing always wins when both are in reach. `tests/test_notes.gd` checks the prompt and the press agree.

## 2. Note formats

| Format | In the world | HUD slip | Voice |
|---|---|---|---|
| **Sticky note** | a fan of yellow squares on the floor | yellow pad, Caveat handwriting, tilted, signature right-aligned | a staff member or henchman, first person |
| **Incident report / ticket** | clipboard on the floor | white carbon, typed, stamped number | flat procedural |
| **Laminated sign** | white A-frame floor sign, hazard-stripe band | glossy plate with hazard stripes, ALL-CAPS rule, pen additions in red hand | policy |
| **Voicemail** | desk phone on a little stand, blinking red light | dark phone card, "1 new voicemail", transcript, waveform | **the client** (the only place they speak) |
| **Client memo** | letterhead sheet with the client's accent band | letterhead in the client accent colour | corporate, the archetype's tone |
| **Complaint form** | pink form on a cork-board easel | pink carbon, URGENT ticked, handwritten free text | an aggrieved employee |

**Headers** (a line can override with its own, e.g. "Calendar invite"):

| Format | Prepper | Supervillain | Guru | Founder | Influencer |
|---|---|---|---|---|---|
| Report | Contingency Log | Maintenance Ticket | Energy Report | Ticket | Brand Safety Review |
| Memo | From the desk of {client} | Henchmen Resources | Intention Card | #general | Brand Brief |
| Complaint | Staff Concern Form | Grievance Form 7B | Guest Feedback Card | Anonymous Feedback (Named) | Comment Moderation Log |
| Sign | Bunker Protocol | Lair Policy | Retreat Etiquette | Office Norms | Studio Rules |
| Voicemail | 1 new voicemail · {client} (all clients) |||||

## 3. Copy

Slots in `{braces}` are filled from the floor (section 5); `{PROP}` etc. are upper-case fills. F3 lines
with an *event* only appear when that event rolled, and win over the generic ones when they do.
Format key: **Stk** sticky · **Rep** report · **Sign** · **VM** voicemail · **Memo** · **Cmp** complaint.

### Prepper Billionaire (bunker)

| Floor | Fmt | Line |
|---|---|---|
| 1 | Sign | DOOR DRILL EVERY SUNDAY. DO NOT OPEN THE DOOR DURING THE DRILL. To confirm the door is sealed, ask Sir. |
| 1 | Memo | Staff will shelter in place. Staff will not shelter in MY place. The panic room seats one. |
| 1 | Stk | Sir says if anything happens he's going "up top". Up top is a second bunker. — {staff} |
| 1 | Rep | Stockpile audit: rations, 40 years. Water, 40 years. Corn, do not ask. Exorcism supplies: none. |
| 2 | Memo | Shelter plan: {staff} to the {staff_room}, with the good silver. The silver has priority. |
| 2 | VM | Me again. If anything happens, save the {prop} in the {prop_room}. Then the staff, if there's time. |
| 2 | Rep | Scratching behind the {gate_room} wall. Sommelier says it's the 1787 "breathing". Closed, no action. |
| 2 | Sign | INSURED VALUE, {PROP}: {prop_price}. STAFF ARE INSURED SEPARATELY, AND LESS. |
| 3 | Memo | *wine cellar:* Door drill, Sunday: open the cellar door to confirm it is sealed. If it is sealed, it won't open. Simple. |
| 3 | Stk | *home cinema:* Movie night: Sir wants the projector pointed at the floor seal "for ambience". Doing it under protest. — {staff} |
| 3 | Sign | *panic room:* DOOMSDAY DRILL: LED CANDLES ONLY. (In pen, underneath: "ordered wax. they came with a book.") |
| 3 | Memo | Contingency 7 (demons) is delegated to Contingency 8 (contractors). Contingency 8 is cheaper. |
| 3 | VM | It's me. The {origin} has been humming. If it stops humming, don't tell me. Just call someone cheap. |

### Supervillain (lair)

| Floor | Fmt | Line |
|---|---|---|
| 1 | Memo | To all henchmen: the imp is NOT a pet. Stop naming it. Its name is Biscuit. Stop calling it Biscuit. |
| 1 | Sign | DAYS SINCE LAST ACCIDENT: 0. (The 0 is printed on. It came that way.) |
| 1 | Cmp | I was promised dental. I have been bitten twice by Biscuit. Biscuit is not covered by dental. — {staff} |
| 1 | VM | This is {client}. The countdown is for rehearsal only. Whoever lets it reach zero becomes the rehearsal. |
| 2 | Memo | Alarm protocol: {staff} shelters in the {staff_room}. Lunch will not be provided. It never is. |
| 2 | Cmp | Grievance: I'm assigned to shelter in the {staff_room} in an emergency. It has no exit. Please advise. — {staff} |
| 2 | Rep | The floor in the {gate_room} is warm and humming. Classified as a feature. Action taken: corn. |
| 2 | Sign | ASSET REGISTER: {PROP}, {prop_price}. HENCHMEN CAN BE REPLACED. THE {PROP} CANNOT. |
| 3 | Cmp | *henchmen barracks:* Someone in the barracks keeps Biscuit under a bunk and feeds it. It is bigger now. It has friends over. — {staff} |
| 3 | Sign | *throne room:* COUNTDOWN REHEARSALS MUST STOP BEFORE ZERO. (In pen: "who is in charge of stopping?") |
| 3 | Memo | *vat room:* Labelling policy: any vat marked DO NOT OPEN must also say why. Interns: this is not a challenge. |
| 3 | Memo | (Monologue, draft 6) "...and once the gate is open, none shall close it!" Margin note: check if contractors can. |
| 3 | VM | It's {client}. Nobody goes into the {origin} without me. Nobody sits on my throne. I will know. |

### Wellness Guru (bunker)

| Floor | Fmt | Line |
|---|---|---|
| 1 | Cmp | The retreat was transformative. The basement hums at night. I have never felt so watched. 5 stars. |
| 1 | Sign | THIS IS A SHOE-FREE, PHONE-FREE, FEAR-FREE SPACE. Please leave your fear in the cubbies. |
| 1 | Memo | Today's intention: abundance. Say it like you mean it. Say it to the floor. |
| 1 | Stk | Re-ordered sage. Third time this week. Whatever is under the floor does not like sage. — {staff} |
| 2 | Memo | If the energy turns, {staff} leads everyone to the {staff_room} and breathes. In for four. Out for four. |
| 2 | Rep | Reading, {gate_room}: intense. Source: a crack in the floor. Recommended action: more crystals. |
| 2 | VM | Hiii, it's {client}. Nobody use the {gate_room} this week. Its energy is unaligned. Namaste. |
| 2 | Sign | PLEASE BE GENTLE WITH THE {PROP}. It holds a lot of energy. It is insured for {prop_price}. |
| 3 | Memo | *yoga studio:* Closing ceremony: open your hearts, open your minds, open the circle. Don't worry about closing anything. |
| 3 | Rep | *meditation dome:* Sound bath, gong strike 107: something underneath hummed back. Strike 108 is booked for Friday. |
| 3 | Sign | *cold plunge:* COLD PLUNGE: 3 MINUTES MAXIMUM. Do not go deeper than the water. The water is deeper than it was. |
| 3 | Cmp | The {origin} was lovely, but something kept knocking from below. Is that included? 3 stars. |
| 3 | VM | It's {client}. Don't book anyone into the {origin} until it stops breathing. Lovely energy, though. |

### Tech Founder (lair)

| Floor | Fmt | Line |
|---|---|---|
| 1 | Memo | is anyone else hearing chanting from sublevel 4? asking for the standup |
| 1 | Memo | (OKRs) Q3: open the gate. KR1: find the gate. KR2: define "open". KR3: figure out closing later. |
| 1 | Sign | WE ARE A FAMILY. Families do not discuss the basement. |
| 1 | Rep | (Board notes) Pitch deck, slide 12: "Summoning. TAM: infinite." Risks identified: none. We did not look. |
| 2 | Memo | fire drill reminder: {staff}, your muster point is the {staff_room}. bring your laptop. you are still on call |
| 2 | Rep | #4096: the {gate_room} floor is warm and making a noise. Priority: P3. Assignee: unassigned. |
| 2 | Rep | (Asset register) {prop}, {prop_room}, {prop_price}. Interns are on a stipend. Replace accordingly. |
| 2 | VM | Quick sync from {client}: the {gate_room} is off-limits pending facilities. Love the energy. |
| 3 | Memo | *keynote stage:* (All-hands agenda) 1. Demo. 2. Summon a stakeholder, live. 3. Q&A, if it allows questions. |
| 3 | Memo | *data center:* (#growth) idea: put the goat in the data center and see what scales. no downside. thoughts? |
| 3 | Memo | *ping-pong lounge:* (Calendar invite) Offsite, Friday, sublevel 4. Agenda: break the seal (team building), ping-pong, retro. |
| 3 | Sign | THE {ORIGIN} IS A NO-MEETING ZONE. Something down there keeps booking it. |
| 3 | VM | {client} here. Whatever is under the {origin}, let's not tell the board. We'll call it a pivot. |

### Influencer (bunker)

| Floor | Fmt | Line |
|---|---|---|
| 1 | Memo | (Drafts) Caption: "Not an ad (it is an ad)." Edited 2:14 a.m.: "also i think the floor is breathing" |
| 1 | Sign | QUIET: RECORDING. If you hear chanting, it's the sound pack. (In pen: "we don't have a sound pack") |
| 1 | Stk | Do not film the basement. Do not tag the basement. The basement is not on brand. — Brand Safety |
| 1 | Memo | Mood board: "ancient". It was supposed to say "aesthetic". The vendor delivered "ancient". |
| 2 | Memo | Shoot safety: if anything happens, {staff} gets everyone to the {staff_room}. Phones out. Content is content. |
| 2 | VM | Heyyy it's {client}. No shoots in the {gate_room}, the floor keeps glitching. Like, physically. |
| 2 | Rep | The {gate_room} is on the do-not-film list. Reason given: "vibes". Reviewed: no. |
| 2 | Sign | #GIFTED: {PROP}. INSURED FOR {prop_price}. DO NOT LEAN ON IT FOR CONTENT. |
| 3 | Memo | *content studio:* Giveaway stream, 9 p.m. Rules: anyone following can win. Anyone. Legal says "anyone" is fine. |
| 3 | Stk | *gifting suite:* A box came for the gifting suite with no sender and it hums. Saving it for the unboxing. — {staff} |
| 3 | Memo | *podcast room:* (Drafts) Collab post, embargoed to Friday: "the entity and I are SO excited." DO NOT POST EARLY. |
| 3 | Sign | THE {ORIGIN} IS A NO-FILTER ZONE. (In pen: "it's already like that in there.") |
| 3 | VM | It's {client}. If the {origin} starts glowing again, just, like, film it? Kidding. Unless? |

(A bracketed lead such as "(Drafts)" above is the line's own header, not part of its text.)

### Hint slips (all clients)

| Hint | Fmt | Line |
|---|---|---|
| Pest: imps | Rep | Small red things in the vents, in packs. They circle between bites. Technician's advice: aim wide. |
| Pest: skeletons | Rep | Bones in the walls, walking. Each one raises its sword before it swings. Technician's advice: step back. |
| Pest: archers | Rep | Hooded things on the high shelves. Arrows fly flat, so a ledge is a wall. Technician's advice: close in. |
| Pest: brutes | Rep | Something heavy that can't climb. A red ring fills before it slams. Technician's advice: get on something tall. |
| Pest: everything | Rep | We found one of everything. Quote attached. The quote is also one of everything. |
| Staff | Sign | SHELTER POINT: {STAFF_ROOM}. ASSIGNED: {STAFF}. Bring water, a torch and a positive attitude. |
| Staff | Memo | Drill roster: {staff_count} staff on this level. {staff} shelters in the {staff_room}. Last drill: {staff} was late. |
| Gate | Sign | {GATE_ROOM}: DO NOT ENTER. FLOOR UNDER REVIEW. (In pen: "it hums.") |
| Gate | Rep | {gate_count} warm spots on this level's floor plan, one of them in the {gate_room}. Status: monitoring. |
| Prop | Rep | {prop}, {prop_room}: insured for {prop_price}. Coverage excludes fire and acts of demon. |
| Prop | Sign | {PROP}: INSURED FOR {prop_price}. Please admire from at least one fireball away. |

Pest tickets carry the header "Pest Control · Site Visit", insurance lines "Insurance Schedule".

## 4. Floor banners (dispatch)

Dispatch talks live on the headset, so the banner is not a note. It is a canary strip at the top centre
with a headset glyph as its frame, no text prefix. **Each banner is ONE thought** in one text block: the
incident or situation leads straight into what it means for the crew on this floor. No generic pay tips
(pay is on the job board and the tracker), and no second line above it.

Floor 1 is the contract's event told in dispatch's voice, tied to the staff (`events[].dispatch` in
`ClientArchetype`, exposed as the `{incident}` fact), e.g. "Interns opened a vat marked DO NOT OPEN. Some of
them are still down here. Bring them out." Floors 2 and 3 use the floor's own facts:

| Floor | Line |
|---|---|
| 1 | {incident} (15 events, one per client event) |
| 2 | The gates on this floor are feeding the {pest} problem. Close them and it stops coming. |
| 2 | The {origin} is still a floor below, so every gate up here keeps sending more. Close the gates. |
| 2 | Halfway down and the {pest} problem has gates now. Close them and this floor goes quiet. |
| 2 | Some of the staff made it this far before the {pest} did. Find them, then find the elevator. |
| 3 | The {origin}'s on this floor. Close the big gate and the whole site goes quiet. |
| 3 | This is where it started, in the {origin}. Close the gate there and every other gate stops with it. |
| 3 | The big gate is in the {origin}. Closing it stops the site; only the elevator clocks you out. |

**Checked against `hellgate.gd`:** a gate spawns until it is closed (killed), so a closed gate stops
spawning; closing the origin gate stops every gate's spawns site-wide (`HellgateEvents.stop_spawns`).
Monsters already out stay out, which is why no line says the floor "clears".

The `events` and invoice `footers` are unchanged.

## 5. Data: keeping hints true

- **Copy** lives in `NoteCopy`: per client `{floor: [{"f": format, "t": text, "event"?, "h"?}]}`, plus
  the shared hint slips, pest tickets and dispatch lines.
- **Facts** (`NoteFacts.from_plan(plan, run)`), read from the `SitePlan` once the props are planned:

| Slot | Source | Missing when |
|---|---|---|
| `{client}` | first + last name (no suffix) | never |
| `{staff}`, `{STAFF}`, `{staff_room}`, `{STAFF_ROOM}` | one `plan.employees` entry: its name and its room | no employees |
| `{staff_count}` | `plan.employees.size()` | 0 |
| `{gate_room}`, `{GATE_ROOM}` | a non-origin `plan.gates` entry's room | no small gates (always on floor 3) |
| `{gate_count}` | `plan.small_gate_count()` | 0 |
| `{prop}`, `{PROP}`, `{prop_room}`, `{prop_price}` | the most expensive `plan.props` entry | no props |
| `{origin}`, `{ORIGIN}` | `run.story.origin` ("yoga studio") | never |
| `{pest}` | `ClientArchetype.pest_name(run.pest)` | never |

- **Room names** come from the room's theme ("wine cellar", "gym", "barracks"); the origin room uses the
  story's own word. Targets in rooms whose theme is unique on the floor are preferred; otherwise the name
  gets "by the elevator" / "by the entrance".
- **Picking** (host, a generator seeded from the floor seed, so every machine plans the same notes and no
  other roll moves): drop lines whose slots are missing, prefer event lines on floor 3, pick, fill.
- `plan.notes` = `{cell, text, format, header, kind: "story"|"hint", yaw}` and `plan.dispatch` (the banner
  line), both `Net.SPAWN`. `ClueNote` and the slip are LOCAL presentation.
