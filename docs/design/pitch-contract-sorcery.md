# Pitch: Contract Sorcery

*This builds on the user's premise: contract sorcerers sent on dangerous jobs, such as
clearing demons from rich people's survival bunkers or retrieving treasure. It keeps the two
pillars: **exploration** of a procedural hex world with verticality, and **combat through
spoken spells.***

## Hook

**Gig sorcerers take dangerous jobs in billionaires' survival bunkers: clearing out demons,
recovering treasure, and billing for every hour.**

The working name for the company is **Hex & Sons Contract Sorcery**: hex tiles, hexes, and
a family firm with no actual sons. The player squad is "the crew," so the alternative is
**Cast & Crew**.

## Tone

- **Workplace comedy over real danger.** The demons are lethal, and the paperwork is the
  joke. It plays like a heist crew run through a gig app.
  - Fights are tight and loud; the debrief is deadpan.
- **Satire targets:** prepper billionaires (absurd bunkers, absurd fears) and the gig
  platform (job cards, star ratings, deductions).
  - The crew are the sympathetic ones: skilled tradespeople doing a ridiculous job well.
- **Clients never appear in person.** They exist only in job cards, voicemails, the house
  AI, and the bunker itself. The bunker *is* the joke.

## Why spoken spells work here

- Sorcery is a licensed trade.
- Every crew member wears a **dispatch rig**: a headset tied into the platform, which
  listens on an open channel and turns a clean spoken call into a licensed spell.
- **Fumbles:** a garbled call is a garbled job. The platform half-delivers and logs it.
- **Unison casts:** the crew calling together counts as a "team authorization," so the
  platform delivers more.

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
- **Crew look:** high-vis vests over robes, with tool belts holding wands and a headset
  each. Each crew member gets one team color.
- **Price tags:** valuables carry a faint price-tag icon, so you can see what an AoE spell
  is about to cost you.

---

## Exploration: the bunker as a dungeon

Mansion on top, bunker below, with the run going *down*. The room types map straight onto
the existing hex rules:

| Room | Terrain feature | Exploration role |
|---|---|---|
| Hydroponics terraces | Stepped +1 levels | Easy verticality, sight lines, ambushes |
| Sunken infinity pool | A pit (one-way drop of 3) | A commitment drop; the exit is the service stair |
| Bouldering wall in the home gym | A +2 climb chain | A climb route to a ledge stash |
| Wine vault | A low, cramped level | Priceless breakables, often under a "no AoE" condition |
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
| **Pre-sale inspection** | Visit and log N rooms and crowns | You're paid on map coverage | Sparse but surprising |
| **Demolition** | Destroy marked fixtures | Fixtures are hidden in side areas | **Damages count in your favor** |

---

## Voice grammar in this fiction

Keep the neutral base grammar from voice-mechanic.md, and add a few *crew-level dispatch
calls* on top:
- **Base grammar:** trigger word + spell. The trigger is customizable, and the default is
  "cast".
- **Strictness modes:** strict, loose (the default) and chaos, as described in
  voice-mechanic.md §3.
- **Fiction:** accidental casts fit this world well. The dispatch rig is always listening,
  and the invoice itemizes every "ACCIDENTAL" line.

| Call | Meaning | Notes |
|---|---|---|
| **cast** + spell ("cast heal") | The default trigger word | In strict mode only at the start of the utterance; in loose mode anywhere. See below |
| bare spell word ("heal") | Casts only in chaos mode (or inside push-to-cast) | |
| spell + **callsign** ("heal Fox") | Targeted ally spell | Crew callsigns from the curated list (Fox, Bear, Crow, Moss, Ember, Pike) |
| **Brace** … **Copy** | Call and response | One crew member calls "Brace!", and everyone who answers "Copy!" within 2 s gets armor |
| **evict** | Team ultimate: wipe the room | Needs a full job meter, **or** 2+ crew in unison |

### Speech recognition check

**"cast" (the keyword):**
- **Short:** one syllable, but it's always followed by a spell word, which gives it
  context. If "cast" is missed, the cast is a Miss: free, with no cooldown spent.
- **Matcher:** under the extra-only sound-alike rule, "casts" is accepted, while "cash",
  "past" and "last" are rejected (sound swaps, not extra sounds).
- **"Cash" is the realistic mishearing in a game about payouts.** It causes a free Miss.
- **Chatter:** "cast" is the game's own name, so players say "did you cast heal?".
  - In **strict** mode that doesn't cast, because the trigger isn't at the start of the
    utterance or after a pause.
  - In **loose** mode it does. That's an accidental heal, flagged and billed on the
    invoice.
  - Crews who want fewer accidents can switch their trigger to a rarer word, such as
    "invoke" or "conjure" (see voice-mechanic.md §1).

**"copy":**
- Two syllables, so robust.
- "Copies" is accepted; "coffee" is rejected.
- It is common in chatter ("copy that"), but it only counts **inside a 2 s window after a
  teammate's "Brace!"**. An accidental "copy" just gives armor, so the risk is negligible.

**"brace":**
- One syllable, and the near-misses "race", "brave" and "breeze" are sound swaps, which
  are rejected.
- It's rare in chatter. It follows the same strictness mode as spells.

**"evict":**
- Two syllables, distinctive, and rare in conversation.
- "Evicts" is accepted, but "evicted" adds two sounds and is not.
- **Risk:** it's an uncommon word for the model, which may split or misspell it, so it
  needs a recognition test. Fallback: "purge".
- Gated by a full meter or unison, so accidental casts are near zero.

**Words to keep out of the grammar:**
- "**clear**" ("room clear!" is constant in action-game chatter), "**go**", "**fire**",
  "**mark**" (a common first name).
- "**pay**" and "**cash**", which this fiction makes chatter-heavy.

---

## How the POC's four spells map in

The spoken words and the code stay unchanged. Only the FX are re-skinned.

| POC spell | FX in this fiction |
|---|---|
| heal | A green pulse from the dispatch rig; heals the caster and nearby crew |
| fireball | A thrown fireball |
| armor | A ring of hazard tape on the hexes; crew inside take less damage |
| corn | Unchanged. A corn bomb drops from the sky and hurts everyone in the blast |

**Property damage (a mechanic):**
- AoE spells (fireball, corn, and later meteor) break priced objects.
- Damages are deducted from the fee, **capped at 50%**.
- Demolition contracts flip them into a bonus.

---

## Enemies

| Enemy | POC role | Behavior | Notes |
|---|---|---|---|
| **Manifested Imps** | Swarmer | Demons a wellness guru summoned while "manifesting abundance." Fast packs | They **chant** and buff each other while chanting; interrupt with AoE |
| **Panic-Room Turret** | Archer | Stationary, with a hazard-tape firing arc; prefers high mounts | Disabled at its control panel, which is always on a +2 ledge (a climb puzzle) |
| **Security Drone** | Archer | Kites and hovers over pits; ignores heights | AoE from above, or knock it into walls |
| **Biohacked Bodyguard** | Brute | Slow, telegraphed slam, can't climb | Climbing is your escape; he takes the stairs |
| **Feral Garden Peacocks** | Grunt or swarmer | A screaming pack from the hydroponics level | Their screams **jam the dispatch channel**: while one screams nearby, only Perfect casts land at full power |
| **The Concierge** (rogue house AI) | Voice enemy | Lives in the walls and speakers | "Sorry, I didn't catch that." It **echoes your last spell to the house**, so your heal heals the demons. Destroy its speaker nodes |
| **Grandma** | Voice enemy (Listener) | Asleep in the east wing | Voice activity nearby wakes her; awake, she's an unkillable elite. "Don't wake Grandma" is a contract condition |
| **Rival Crew** (the "Spellr" app) | Elite casters | A cheaper rival gig crew racing you for the loot | They shout their spells in subtitles; interrupt them mid-cast |

---

## Run and meta loop

1. **Job board.** The dispatch app offers 3 contracts, each with a client rating,
   conditions, fee and bonus.
2. **Drop-in.** The crew's van pulls up, and the run starts at the service entrance.
3. **The run.** Explore down, fight, hit the objective, and extract (helipad or service
   elevator).
4. **Invoice.** A single 10-second receipt screen:
   - fee and bonuses (secrets found, time, conditions met);
   - **minus damages**;
   - minus audit findings, if the client audits your pockets.
5. **Review.** The client rates you 1–5 stars, with a one-line review.

**Pocketing:** any valuable can be pocketed with one button. The audit chance rises with
how many you took. Pocketed loot sells for credits.

**Meta progression:**
- **Reputation** (average stars) unlocks richer clients. The client ladder: tech founder,
  then hedge-fund manager, then oligarch, then a space billionaire's orbital bunker.
- **New spells are licenses** bought from the guild with fees and loot. Learning a spell
  word means speaking it once at the licensing terminal, which doubles as a calibration
  sample.
- **Crew perks:** van upgrades, a better dispatch rig (for example, a wider unison
  window), and lower audit odds.

---

## Three sample job cards

```
JOB #0412 · EXTERMINATION · Client ★★★★☆
SITE: "Serenity Silo" · 7 levels · hydroponics, wine vault, infinity pool
JOB: Clear all manifested entities. Destroy nests (est. 3).
CONDITIONS: Don't wake Grandma (L4 east wing). No AoE in the wine vault.
FEE $18,000 · BONUS +$4,000 under 12:00
CLIENT NOTE: the peacocks are not ours. Do not engage the peacocks.
```

```
JOB #0419 · RETRIEVAL · Client ★★☆☆☆ ("slow last time")
SITE: "Bastion 9" · gallery, panic room, helipad
JOB: Recover 1x heirloom egg from the safe behind the "blue painting."
CONDITIONS: Painting is worth more than the egg.
FEE $26,000 · BONUS +$6,000 zero damages
DISPATCH: house AI is "being weird." Expect interference.
```

```
JOB #0423 · EVACUATION · Client ★★★★★
SITE: "The Ark (Lake House)" · 5 levels · flooded lower deck
JOB: Extract 1x Pomeranian ("Duchess"). Duchess does not climb.
CONDITIONS: Duchess must not see violence. (Dispatch: ignore this.)
FEE $40,000 · BONUS scales with Duchess's mood on arrival
```

---

## Risks

- **The satire wears thin.**
  - Keep the jokes *systemic* (invoices, conditions, the Concierge, Grandma) rather than
    written gags that repeat.
  - Rotate client archetypes by reputation tier.
  - Keep the clients off-screen.
  - Use a small pool of job cards with procedural conditions.
- **The business loop fights the action.**
  - If damages make players timid, the combat dies. The 50% cap, Demolition contracts and
    loud destruction FX all push the other way.
  - No inventory management mid-run: pocketing is one button, and all the accounting
    happens on the invoice screen.
- **Tone versus "Diablo-style".** It's lighter than the brief's reference. The danger has
  to stay real: lethal demons, tense extractions, and Grandma.
- **Chatter and dispatch calls.** "Cast" and "copy" are common words. The pause rule and
  the response window handle them. **The POC must measure the false-cast rate with this
  grammar on.**
- **Exploration motive.** It's strong, because every contract type sends you through the
  bunker for a different reason. Watch that Pre-sale inspection doesn't turn into a
  checklist.

## Verdict

This is the strongest *structure* of all the pitches: contract types give each run a
different reason to explore, and the job/invoice/reputation loop is built into the
fiction. It's a real rival to Warcry. **Prototype both tones with the same POC.** The
setting-neutral art rule and the POC's four spells carry over unchanged.
