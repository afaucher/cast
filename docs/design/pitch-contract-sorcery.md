# Pitch: Contract Sorcery

*This develops "Short Order Sorcery" (game-pitch.md #3) using the user's twist. It keeps the
two pillars: **exploration** of a procedural hex world with verticality, and **combat
through spoken spells.***

## Hook

**Gig-economy sorcerers take dangerous jobs in rich people's survival bunkers: clearing
out demons, recovering treasure, and charging for every hour.**

The working name for the company is **Hex & Sons Contract Sorcery**: hex tiles, hexes, and
a family firm with no actual sons. The player squad is "the crew," so the alternative is
**Cast & Crew**.

## Tone

- **Workplace comedy over real danger.** The demons are lethal, and the paperwork is the
  joke.
  - It's a heist crew crossed with a restaurant kitchen line.
  - Fights are tight and loud; the debrief is deadpan.
- **Satire targets:** prepper billionaires (absurd bunkers, absurd fears) and the gig
  platform (tickets, star ratings, deductions).
  - The crew are the sympathetic ones: skilled workers doing a dumb job well.
- **Clients never appear in person.** They exist only in tickets, voicemails, the house
  AI, and the bunker itself. The bunker *is* the joke.

## Why shouting spells works here

- Sorcery is a trade, and a trade has a kitchen line's call-outs.
- The dispatcher's platform turns shouted orders into spells. "**Fire** heal!" means start
  that order now, which is exactly what "fire" means on a real kitchen line.
- A clean call gets a clean plate. A mumbled order gets a sad one: that's the fumble.

## Art direction

- **Luxury interiors:**
  - marble and travertine floors (light tile tops);
  - brass trim;
  - brutalist concrete walls and shafts (dark sides);
  - planter terraces;
  - wine racks.

  All of it is clean, low-clutter and modular, which suits a small team kitbashing
  rooms.
- **Contractor hazard-stripe tape is the visual language for every telegraph.** The
  brute's slam ring, turret arcs and no-go zones all use it. One yellow-black pattern
  means "danger," and it reads instantly in an isometric camera.
- **Price tags:** valuables carry a faint tag icon, so you can see what corn is about to
  cost you.

---

## Exploration: the bunker as a dungeon

Mansion on top, bunker below, with the run going *down*. The room types map straight onto
the existing hex rules:

| Room | Terrain feature | Exploration role |
|---|---|---|
| Hydroponics terraces | Stepped +1 levels | Easy verticality, sight lines, ambushes |
| Sunken infinity pool | A pit (one-way drop of 3) | A commitment drop; the exit is the service stair |
| Bouldering wall in the home gym | A +2 climb chain | A climb route to a ledge stash |
| Wine vault | A low, cramped level | No-fire zone condition; priceless breakables |
| Panic room | A sealed room with turrets | Its control panel sits on a +2 ledge outside |
| Gallery | Flat, open | Safes behind art (breakable walls) |
| Atrium with helipad stairs | The tallest stair stack | A vantage crown, and the extraction point |

**The signature beat:** from the atrium mezzanine you can *see* the vault across a void.
Getting to it is the level.

### Contract types

| Contract | Objective | Why you explore | Combat profile |
|---|---|---|---|
| **Extermination** | Clear all demons and destroy their summoning nests | Nests are hidden; finding them is the job | Heavy waves, swarm-focused |
| **Retrieval** | Recover a named item from a vault or safe | The vault is seen first, then routed to | Light combat, guarded chokepoints |
| **Evacuation** | Get the client's pet or heir out alive | The escort **can't climb**, so you must find a stair route | Defensive; protect a slow walker |
| **Repossession** | Reclaim listed assets for a creditor | Assets are scattered; how much you pocket is up to you | The house security is hostile |
| **Pre-sale inspection** | Visit and photograph N rooms and crowns | You're paid on map coverage | Sparse but surprising |
| **Demolition** | Destroy marked fixtures | Fixtures are hidden in side areas | **Damages count in your favor**: the corn contract |

---

## Voice grammar in this fiction

Kitchen lingo layered over the base grammar in voice-mechanic.md:

| Call | Meaning | Notes |
|---|---|---|
| bare spell word ("heal") | Cast, under "spoken, not mentioned" | Unchanged |
| **fire** + spell ("fire heal") | Cast now; the override keyword, replacing "cast" | See the speech recognition check below |
| **eighty-six** | Team ultimate: wipe the room | Needs a full ticket meter, **or** 2+ crew in unison |
| **corn** ("the house special") | Corn bomb | Hair-trigger, as before |
| **yes chef** | The answer in call and response | Leader: "Brace!" Crew: "Yes chef!" Everyone who answers gets armor |
| **on the fly** | The "quick" modifier | Three words, robust; low chatter risk outside a kitchen |
| **behind** | A dash through an ally (later spell) | Hair-trigger, deliberately |

### Speech recognition check

**"fire" as the cast keyword:**
- **Short:** one syllable, and short words are unreliable *in isolation*. Here it's
  always followed by a spell word, and if "fire" is missed, the spell still casts as a
  bare word. Graceful.
- **Matcher:** under the extra-only sound-alike rule, "fires" and "fired" are accepted,
  while "hire", "tire", "five" and "fine" are rejected (sound swaps, not extra sounds).
- **The real problem is chatter.** "Fire" is one of the most common words in action-game
  talk: "on fire", "cease fire", "fire at the archer", "fire in the hole".
  - The old "cast" override worked *mid-sentence*, so "he's on fire, heal him" would
    hear "fire heal" and cast.
  - **Rule:** "fire" counts as the keyword only if it **starts the utterance or follows a
    pause of at least 0.3 s**, *and* a spell word follows within 0.3 s. Both checks use
    token timestamps.
  - That fixes "on fire, heal him" but keeps "...[pause] fire heal!" working.
- **Spell-name collision:** "fire fireball" is a tongue-twister, and the keyword is a
  prefix of the spell.
  - On the menu, fireball becomes **"flambé"**, with "fireball" still accepted as an
    alias.
  - Flambé is a rare word, so it needs a recognition test. If it fails, fall back to
    "inferno".

**"eighty-six":**
- It comes out of the recognizer as two number words, "EIGHTY SIX": four syllables,
  distinctive.
- It needs a phrase entry in the hotword list and the matcher.
- **Chatter risk:** low, except when players read numbers aloud ("eighty-six gold").
  Requiring a full meter or a unison call makes accidents nearly impossible.
- **Near-misses:** "eighteen", "sixty-six" and "eighty sticks".

**"Corner!", the real kitchen call:**
- It matches corn under the extra-only rule (corn plus one extra sound).
- So **a crew that talks like a real kitchen drops corn on itself.**
- Keep it. It's the best accidental joke in the game, and it costs only the damages.

**"Yes chef":** two words and robust. It's chatter-prone *only* in this fiction, which is
the point.

---

## How the POC's four spells map in

| POC spell | Menu name | Spoken word | Flavor |
|---|---|---|---|
| heal | Staff Meal | heal | A green steam burst; heals the caster and nearby crew |
| fireball | Flambé | fireball (later "flambé") | A thrown pan of burning brandy |
| armor | Hazard Zone | armor | A ring of hazard tape on the hexes; crew inside take less damage |
| corn | The House Special | corn | A catering drone drops a cart-sized buttered cob. **Itemized on your invoice** |

No code changes are needed. These are display names and FX only.

---

## Enemies

| Enemy | POC role | Behavior | Notes |
|---|---|---|---|
| **Manifested Imps** | Swarmer | Demons a wellness guru summoned while "manifesting abundance". Fast packs | They **chant affirmations** and buff each other while chanting; interrupt with AoE |
| **Panic-Room Turret** | Archer | Stationary, with a hazard-tape firing arc; prefers high mounts | Disabled at its control panel, which is always on a +2 ledge (a climb puzzle) |
| **Security Drone** | Archer | Kites and hovers over pits; ignores heights | Tempest or AoE from above |
| **Biohacked Bodyguard** | Brute | Slow, telegraphed slam, can't climb | Climbing is your escape; he takes the stairs |
| **Feral Garden Peacocks** | Grunt or swarmer | A screaming pack from the hydroponics level | Their screams **drown out casts**: while one screams nearby, only Perfect casts land at full power |
| **The Concierge** (rogue house AI) | Voice enemy | Lives in the walls and speakers | "Sorry, I didn't catch that": it **echoes your last order to the house**, so your heal heals the demons. Destroy its speaker nodes |
| **Grandma** | Voice enemy (Listener) | Asleep in the east wing | Voice activity nearby wakes her; awake, she's an unkillable elite. "Don't wake Grandma" is a contract condition |
| **Rival Crew** ("Spellr") | Elite casters | A cheaper rival gig crew racing you for the loot | They shout their spells in subtitles; a well-timed corn stops them |

---

## Run and meta loop

1. **Ticket board.** The dispatcher offers 3 contracts, each with a client rating,
   conditions, fee and bonus.
2. **Drop-in.** The crew's van pulls up, and the run starts at the service entrance.
3. **The run.** Explore down, fight, hit the objective, and extract (helipad or service
   elevator).
4. **Invoice.** A single receipt screen, 10 seconds long and funny:
   - fee and bonuses (secrets found, time, conditions met);
   - **minus damages**, for every priced object your spells destroyed;
   - minus audit findings, if the client audits your pockets.
5. **Review.** The client rates you 1–5 stars, with a one-line review.

**Pocketing:** any valuable can be pocketed with one button. The audit chance rises with
how many you took. Pocketed items sell for credits *or* are what unlock new spells (see
below).

**Meta progression:**
- **Reputation** (average stars) unlocks richer clients. The client ladder: tech founder,
  then hedge-fund manager, then oligarch, then a space billionaire's orbital bunker.
- **New spells are certifications** bought at the guild, paid for with fees and pocketed
  loot.
- **Crew perks:** van upgrades, a better dispatcher, and lower audit odds.

**Damages make corn cost something:**
- Friendly-fire corn on a $4M sculpture comes out of your fee.
- Damages are **capped at 50% of the fee**, so they bite but never ruin a run.
- Demolition contracts flip them into a bonus.

---

## Three sample tickets

```
TICKET #0412 · EXTERMINATION · Client ★★★★☆
SITE: "Serenity Silo" · 7 levels · hydroponics, wine vault, infinity pool
ORDER: 86 all manifested entities. Destroy nests (est. 3).
CONDITIONS: Don't wake Grandma (L4 east wing). No fire spells in the cellar.
FEE $18,000 · BONUS +$4,000 under 12:00
NOTE FROM CLIENT: the peacocks are not ours. Do not engage the peacocks.
```

```
TICKET #0419 · RETRIEVAL · Client ★★☆☆☆ ("slow last time")
SITE: "Bastion 9" · gallery, panic room, helipad
ORDER: Recover 1x heirloom egg from the safe behind the "blue painting."
CONDITIONS: Painting is worth more than the egg. Painting is behind the safe? Unclear.
FEE $26,000 · BONUS +$6,000 zero damages
DISPATCH: house AI is "being weird." Bring earplugs.
```

```
TICKET #0423 · EVACUATION · Client ★★★★★
SITE: "The Ark (Lake House)" · 5 levels · flooded lower deck
ORDER: Extract 1x Pomeranian ("Duchess"). Duchess does not climb.
CONDITIONS: Duchess must not see violence. (Dispatch: ignore this.)
FEE $40,000 · Bonus scales with Duchess's mood on arrival
```

---

## Risks

- **The satire wears thin.**
  - Keep the jokes *systemic* (receipts, conditions, the Concierge, corn damages) rather
    than written gags that repeat.
  - Rotate client archetypes by reputation tier.
  - Keep the clients off-screen.
  - Write a small pool of tickets with procedural conditions so they stay fresh.
- **The business loop fights the action.**
  - If damages make players timid, the combat dies. The 50% cap, Demolition contracts and
    loud, funny destruction FX all push the other way.
  - No inventory management mid-run: pocketing is one button, and all the accounting
    happens on the invoice screen.
- **Tone versus "Diablo-style".** It's lighter than the brief's reference. The danger has
  to stay real: lethal demons, tense extractions, and Grandma.
- **Kitchen lingo collides with chatter.** "Fire", "corner" and "behind" are all common.
  The rules above handle "fire", and "corner" and "behind" are deliberate. **The POC must
  measure the false-cast rate with this grammar on.**
- **Exploration motive.** It's strong, because every contract type sends you through the
  bunker for a different reason. Watch that Pre-sale inspection doesn't turn into a
  checklist.

## Verdict

Contract Sorcery fixes Short Order's two weaknesses:
- **Exploration motive:** bunkers have verticality, secrets and vantage points built in.
- **Shelf life:** it's a contract loop with escalating clients, not a single gag.

It also gives corn a real cost through the damages line. It is the strongest *comedy*
option and a real rival to Warcry. **Prototype both tones with the same POC.** The
setting-neutral art rule and the POC's four spells carry over unchanged.
