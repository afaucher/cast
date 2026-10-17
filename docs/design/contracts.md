# Contracts (missions)

Status: 2026-10-16. The user's examples are marked **[decided]**. Everything else is a
**[proposal]**. A contract is a job card from dispatch: a site (luxury bunker or villain lair, see
`environment.md`), a list of paid objectives, and a deduction for damage. The crew gets paid at the
end; the north-star "consistently pretty good" team should clear most objectives most runs.

## Objectives and pay [decided examples]
| Objective | Pay | Notes |
|---|---|---|
| **Protect my employees** | **$10 each** (alive at the end) | The client values staff at $10. That's the satire. |
| **Disinfect the wine cellar** | **$10k** | Clear the room's infestation: the nest, goo and spawners. |
| **Close all hellgates** | **$3k each** | Hellgates are the spawners (summoning circles / portals). |
| **Property damage** | **deducted from pay** | Every broken prop has a price tag. |

## How each one plays [proposal]
- **Employees:** NPCs (staff in uniforms, or henchmen in a villain lair) hide in rooms. They panic,
  run around and get in the way, and they can be hit by **your** spells: corn, teeth, tentacle
  shoves into pits. Losing one costs $10, which is funny exactly because it's so little. The
  real cost is the end-of-job report ("Employees lost: 3. Cause: corn.").
  - **Option:** an escort variant where employees follow a hero to the exit (call them by voice later?).
- **Disinfect a room:** the room has an infestation meter (nests, goo puddles, a spawner). Destroying
  nests and the spawner drains it, and goo can be cleaned by fireball (burn it) or simply walked
  off over time. It's a big lump sum for one room, so it naturally becomes the main objective.
- **Hellgates:** a spawner with HP that pulses waves until closed. Closing it takes focused damage or
  a specific spell; tentacles could "stuff it shut". Closing it can also deal a shove pulse to the
  area, a natural chaos moment.
- **Property damage:** breakable props (wine racks, the cinema screen, the gold toilet, the doomsday
  console) each carry a price. Damage comes from fireball, corn, teeth pops, shoves into props,
  and Rebar's bowl.
  - Show it live as a running ticker ("-$1,200 wine rack") so players feel it as it happens.
  - **Cap:** deductions can't exceed some share of the job's pay, so chaos stings but never zeroes
    a run (per `north-star.md`).
  - Expensive props are telegraphed, with a price tag when you're near: "Vintage 1787, $4,000".

## End-of-job invoice [proposal]
The run ends at the exit with an **invoice** screen:
- line items earned;
- deductions with the culprit named ("Wick: corn, -$900");
- the net payout;
- a star rating.

The comedy and the "well-oiled team" score live here, and payout could later buy gear or unlock spells.

## Fit with what exists
- **Pits and shoves:** the shove system already lets monsters, and eventually employees, be shoved
  into pits.
- **Spawners:** `environment.md` already plans summoning circles and nests as spawners, which become
  hellgates.
- **Friendly fire:** the friendly-fire-floor rule (spells never down a hero) does NOT apply to
  employees. Protecting them is the skill test.
- **Components:** monster component drops keep working. Hellgates might drop rarer components.

## Open questions
1. Are employees vulnerable to monsters only, or to everything? (Proposed: everything.)
2. Is pay per hero or for the whole team? (Proposed: the team pot, with credit and blame per hero on
   the invoice.)
3. Does a contract have a timer? (Proposed: no hard timer, but a par time bonus.)

## Decisions (user, 2026-10-16)
1. **Leaving early always works.** Objectives you haven't met don't pay, and you may still owe for
   damages, so a run CAN end in the red.
2. **The invoice IS the summary screen**, and it looks like a real invoice: letterhead, line items,
   deductions, net total due.
3. **Hellgates take damage like anything else.** Auto-spawning only if the balance stays under
   control. Options:
   - a finite reserve per gate;
   - spawning only when heroes are near or the gate is hit;
   - no spawning (guarded only).
4. **Employees:** $10 each alive, **$100 each extracted** (escorted to the exit).
5. **No goo cleaning.** It's janitor work, not magic-user work. "Disinfect" becomes
   **exterminate the pest you were hired for**: either *everything* on site, or a *specific* pest
   (e.g. "imps only"). It stays on the magic side of the line.
6. **The property penalty is capped.** The exact basis is still to decide; see the open questions.
7. **Team pot.** The invoice still names credit and blame per hero.
8. **Generation:** the room-tagging approach is too small. Bigger options are under discussion.

### Open
- **What the cap is based on:** a share of the contract's total value (so leaving early with nothing
  earned can still leave you owing up to the cap), or a share of earnings?
- ~~**Hellgate spawning model**~~ **Decided:** hellgates DO spawn monsters, and the **spawn rate scales
  up progressively with contract difficulty**. Easy contracts have slow, sparse gates and hard ones
  pump out waves, so balance is a difficulty curve rather than an on/off switch.
  - **Proposal:** the rate also rises with floor depth inside a contract.
  - **Proposal:** each gate has a cap on living spawns, so an ignored gate builds pressure without
    flooding the level.

## Contract generation [decided directions: 1 client, 2 story, 3 descent, 6 job board]
How they fit together, from the top down:

1. **Job board (6):** before a run, dispatch offers **3 contracts**. Each card shows the client,
   the site, the objectives and prices, the floor count, the danger, and the property warnings.
   The crew picks one together over voice ("I'm not doing the guru again").
2. **Client (1):** each offer is generated from a **client archetype**, which supplies:
   - the site type (bunker or villain lair) and its room theme pool;
   - the **pest** the job is about (exterminate "everything" or one kind);
   - the **priceless props** and their price tags;
   - the objective mix and pay scale;
   - a personality for the job card and invoice text.

   Archetypes to start: prepper billionaire, supervillain, wellness guru, tech founder,
   influencer. (Proposed; add or cut freely.)
3. **Story (2):** generation then rolls **what happened**: an inciting event plus where it
   started. For example, "the closing ceremony opened a gate in the yoga studio", or "the henchmen
   tried to tame an imp".

   The story drives the level:
   - **Origin room:** it's themed for the event and holds the first hellgate.
   - **Spread:** pests spread outward from it, so density rises toward the origin.
   - **Survivors:** employees hide in the rooms farthest from it.
   - **Clues:** environmental storytelling (notes, trashed rituals, broken props) points back to it.

   The story is the reason the map looks the way it does, and exploring reveals it.
4. **Descent (3):** a contract is **several floors** joined by the freight elevator.
   - Each floor is a full generated level from the same client and story. It gets worse further
     down: more pests, more gates, closer to the origin.
   - Objectives can span floors (e.g. "close all 4 gates" across 2 floors), and pay rises with depth.
   - **The elevator is always available** (the early-exit rule). At each floor the crew decides:
     go down for more pay and more risk, or cash out. Unmet objectives don't pay, and damage is
     still owed, up to the cap.
   - **The invoice** at the end totals every floor.

### Open questions
- ~~**Floors:** how many per contract?~~ **Decided: 3 floors per contract.** Still open: do floors
  loop back up (taking employees up the elevator)?
- **Per-floor contents:** does every floor need its own hellgate, or can the origin floor hold the
  "boss" gate?
- **Board refresh:** does the board refresh each time, and is there any persistence between
  contracts (reputation with recurring clients)?
