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
