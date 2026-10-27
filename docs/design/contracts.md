# Contracts (missions)

Status: 2026-10-16. The user's examples are marked **[decided]**. Everything else is a
**[proposal]**. A contract is a job card from dispatch: a site (luxury bunker or villain lair, see
`environment.md`), a list of paid objectives, and a deduction for damage. The crew gets paid at the
end; the north-star "consistently pretty good" team should clear most objectives most runs.

## Objectives and pay [decided examples]
| Objective | Pay | Notes |
|---|---|---|
| **Extract my employees** | **$100 each** (escorted to an exit) | Staff left behind pay nothing (user, 2026-10-18: the $10 "alive at the end" pay was dropped). |
| **Disinfect the wine cellar** | **$10k** | Clear the room's infestation: the nest, goo and spawners. |
| **Close all hellgates** | **$3k each** | Hellgates are the spawners (summoning circles / portals). |
| **Property damage** | **deducted from pay** | Every broken prop has a price tag. |
| **Crew revival (corporate)** | **-$10,000 per hero down at the end** | Not capped. The one way pay goes negative (see Decisions, 9). |

## How each one plays [proposal]
- **Employees:** NPCs (staff in uniforms, or henchmen in a villain lair) hide in rooms. They panic,
  run around and get in the way, and they can be hit by **your** spells: corn, teeth, tentacle
  shoves into pits. Losing one costs $10, which is funny exactly because it's so little. The
  real cost is the end-of-job report ("Employees lost: 3. Cause: corn.").
  - **Escort [built]:** employees follow a hero to the exit, and joining takes **E**
    (`Employee.JOIN_NEEDS_E`, on): walking past does nothing. E next to a cowering or waiting employee
    (nearest within 2.2) brings them along ("E: bring Beatrice" shows on the HUD); E next to your own
    follower tells them to wait ("E: tell Beatrice to wait"). A waiting employee crouches where they were
    told, still panics at monsters and then walks back, and never rejoins by proximity, so they do not
    chase you into a fight. A waiting employee pays nothing unless extracted; extraction only takes followers
    (see the drop-off and the exits below), so one left behind is not extracted. E (Use) priority: the van exit
    (at the van), then the elevator (at it), then the employee, then nothing; E never casts, so a follower
    inside 2.2 never costs you a spell.
    The press is a **request** (`Employee.request_wait / request_follow`): the host
    owns employees and a player's E asks it. AI allies never recruit. A hero within 2.2 of an employee
    that follows an AI ally can dismiss it.
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
- a **CREW REVIVAL (CORPORATE)** section, one row per hero still down at the end ("Revival - Gasket, -$10,000");
- the net payout (red with a minus sign when negative);
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
1. **Leaving early always works.** Objectives you haven't met don't pay, and damages come out of
   whatever you did earn (see 6). Property damage never takes the pay below $0; only crew revival fees can (see 9).
2. **The invoice IS the summary screen**, and it looks like a real invoice: letterhead, line items,
   deductions, net total due.
3. **Hellgates take damage like anything else.** Auto-spawning only if the balance stays under
   control. Options:
   - a finite reserve per gate;
   - spawning only when heroes are near or the gate is hit;
   - no spawning (guarded only).
4. **Employees:** **$100 each extracted** (escorted to the exit); nothing for one left behind.
5. **No goo cleaning.** It's janitor work, not magic-user work. "Disinfect" becomes
   **exterminate the pest you were hired for**: either *everything* on site, or a *specific* pest
   (e.g. "imps only"). It stays on the magic side of the line.
6. **The property penalty is capped at the contract's value and comes out of earnings. No negative
   money for property damage.** A wrecked run can earn $0, and damage alone never makes the crew owe
   anything. (Revival fees are the exception, see 9.)
   `payout = max(0, earned - min(damages, contract_value)) - revival_fees`.
7. **Team pot.** The invoice still names credit and blame per hero.
8. **Generation:** the room-tagging approach is too small. Bigger options are under discussion.
9. **Crew revival fee [decided, user, 2026-10-17]:** corporate revives every crew member who is **down when the contract
   ends**, and bills the client **$10,000 each**. It covers every hero, the player's own included (online every hero is
   a player), and it is charged only at the end: cashing out at the elevator or the van with an ally down bills that
   ally, and an incapacitated ending (all three down) bills 3 x $10,000. Since 2026-10-27 a downed hero CAN get up mid-floor
   (spells.md, "Revive" and "Coffee": a coffee stands them up as a gray, leaking zombie, a Revive at half health), and both
   are free: the fee still applies to whoever is down when the contract ends, whatever happened before. A hero down when the crew takes the elevator
   stays behind with its body (user, 2026-10-18): it does not ride down or show on the next floor, and its player watches a
   living ally (`ContractSession.carried_down`, `Game._apply_carry`); a body left on the floor above cannot be revived from
   below (`GameWorld.downed_in_radius` skips it). A coffee zombie who rides down arrives a zombie (the carry keeps the curse).
   - **Not capped, not floored.** It does not share the property-damage cap and it is not clamped at $0, so the
     **net payout can go negative**. This deliberately changes the old "pay never goes below $0" rule, for revival fees
     only. If you die, you pay.
   - The earned-minus-capped-damages part still floors at $0; the revival fees come off after that floor:
     `payout = max(0, earned - min(damages, contract_value)) - revival_fees`.
   - Built: `Ledger.revival(hero_name)` (line kind `"revival"`, `Ledger.REVIVAL_FEE`), `Ledger.revival_fees()`,
     `ContractSession.finish(reason, downed_heroes)` (called by `Game._end_contract` with the heroes whose `dead` is true;
     it bills once), the invoice's `revivals` / `revival_fees`. FORM 99 prints the "CREW REVIVAL (CORPORATE)"
     section after property damage (only when someone was down) and NET PAYOUT turns red with a minus sign; the
     debrief slip (FORM 99-B) lists "DOWN AT THE END". The running payout in the HUD never shows the fee: it only
     exists once the contract is over. A negative payout is a 1-star job.
   - The garage's "after a bad job" mood (`LastContract.was_bad`) also triggers on any revival fee or a negative net payout.

### Open
- ~~**What the cap is based on**~~ **Decided:** capped at the contract's value and taken out of
  earnings, with no negative money (see decision 6).
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
   - **The elevator is always available** (the early-exit rule). It needs a key press: while the player
     stands on or next to the exit cell (its landing, in front of the doors) or in its car the HUD says "E: use elevator"
     and E opens its menu (E never casts). At each floor the crew decides:
     go down for more pay and more risk, or exit. Unmet objectives don't pay, and damage is
     taken out of earnings (that part never below $0; revival fees for heroes left down can still make the net negative, see Decisions 9).
   - **The invoice** at the end totals every floor.

### Mission structure [decided, user, 2026-10-17]
- **Floors 1-3, no backtracking.** The crew only ever goes down.
- **The van parks on floor 1 only.** It teleports in at the start of floor 1 (see `environment.md`, "Van arrival") and
  stays parked there. Floors 2 and 3 have **no van**: the crew **arrives in the elevator** (user, 2026-10-18): it stands
  in the car's front row, the doors open and it steps out onto the landing (~1.9 s, skippable; `ElevatorArrival`), and
  no pack or employee is planned in that room (`SiteBuilder.arrival_room`).
- **The elevator** is a set piece in one of four styles, one per job, all its floors alike: a service (freight) or fancy
  (brass) look, in a notch of a room's wall or free-standing in the middle of a room. The exit cell is its landing, in
  front of its doors. See `elevator-options.md`, "Built".
- **Two exits, and leaving early is always allowed at either** (unfinished objectives simply don't pay):
  - **The elevator**, on every floor, offers **go down to the next floor** and **exit** (clock out and invoice). On
    floor 3 it offers only exit. HUD prompt "E: use elevator".
  - **The van**, floor 1 only. **E** within 2.8 of its side door (HUD prompt "E: clock out at the van") opens a small
    canary slip (`VanExitMenu`): "Clock out: drive off and invoice the client" and Cancel. Confirming ends the contract
    exactly like the elevator's exit. It is a request the host arbitrates, like the elevator.
  - Closing the floor-3 **origin gate does not end the contract**; the crew still has to leave at the elevator or the van.
- **Extraction:** employees FOLLOWING the crew within ~3 cells of the exit being used (van door or elevator) when the crew
  leaves are extracted, **$100 each**. Staff left behind pay nothing (user, 2026-10-18). Going down the elevator extracts its
  followers too, before the floor changes.
- **`use` (E) priority:** the van exit (at the van), then the elevator (at it), then employees, otherwise nothing. E never
  casts.
- **Drop-off [decided, user]:** an employee who is following the crew and gets within 2.5 world units of an exit (the
  floor-1 van's door area, or the elevator on any floor) **leaves right away** and counts as extracted ($100), whether or
  not the crew ever takes the exit and with no key press. Waiting and cowering employees never do. It reuses
  `Employee.extract()` (the exit animation) with the bark "I'm out, thanks!" and the usual HUD money line. It is recorded
  once: the Ledger line "Employee extracted" is written at drop-off time through `ContractSession.extract`, an employee that
  left is no longer a follower (nothing extracts it again at the exit) and `ContractSession.employees_alive()` already
  excludes it. The objective tracker's employee row shows it at once ("1 rescued · 2 alive").
  Tests: `tests/test_exit_dropoff.gd`.
- **Not part of this:** restocking spell components at the van (see `poc-backlog.md`).

### Floors by risk: spawn, origin and the elevator [direction, user, 2026-10-18; NOT built]
A rework of "Mission structure" above, to be built later. Floors are named by **risk**, not by number.
- **Spawn floor (lowest risk):** the crew always starts here, **in the van**. Only this floor has a starting point.
- **Exits:** on the spawn floor, the **elevator or the van**. On every other floor, **only the elevator**.
- **The elevator is the arrival point.** Taking it puts the crew **inside the elevator** on the new floor. There is no
  start cell ("blue hex") anywhere.
- **The elevator offers:** Exit, go to the medium-risk floor, go to the origin floor (the floors other than the one
  you are on).
- **Nothing ties the spawn floor to "floor 1" or the origin to "floor 3".** The spawn floor isn't necessarily the top
  of the building and the origin isn't necessarily the bottom.

**The elevator's form: a floor sign-in sheet [design, user, 2026-10-18; NOT built, wording not final].**
Like the cleaning log on a restroom door, but you sign in to *start* servicing a floor. One row per floor of the site;
the crew's marks are the record of the job.
- **Row states:**
  - **Open:** nobody has signed in. Selecting it signs the crew in (the player's red name stamp in the IN column) and
    the elevator goes there.
  - **In progress:** the floor you are on: signed in, not signed out. Not selectable.
  - **Serviced:** the floor's work is done, so it is signed out (stamp in the OUT column). Not selectable.
  - **Left unfinished**, depending on the backtracking decision (still open, see below):
    - *no backtracking:* an **ABANDONED** stamp across the row; not selectable;
    - *backtracking allowed:* signed in with no sign-out; still selectable to sign in again.
- **Leaving the job** is the sheet's last line (the van offers the same on the spawn floor): sign off the job.
- **Wording candidates** (to choose):
  - title: "Floor service log" / "Site sign-in sheet" / "Service record";
  - columns: FLOOR · RISK · IN · OUT (or "Started by" / "Serviced by");
  - the floor's name: the room theme of its origin or a site name ("Wine cellar level"), or only its risk;
  - the exit line: "Sign off the job" / "Job complete: clock out" / "Close the job";
  - whether IN and OUT carry a time (the site clock) next to the stamp, like a real log.
- What "serviced" means (the condition for signing a floor out) is not decided yet: every gate on it closed, or every
  objective on it met.

**How it works today (for comparison):** floor 1 starts the crew at the van on its start cell (the blue-bordered hex,
tag `start`); floors 2 and 3 start it inside the elevator, which steps it out onto its landing (the `exit` cell). The
start cell still exists on every floor (generation uses it). The van is on floor 1 only. The elevator offers down and
exit, and only exit on floor 3.

**Open:**
- Backtracking: can the crew go back to a floor it has already visited (the earlier rule was "down only")? The sheet
  handles both: an ABANDONED stamp if not, an unsigned row if so.
- What the elevator panel and the floor tracker call the floors (by risk, by a site-specific name, by number?).
- What happens to the start cell's role in generation (room layout, gate placement and the van spot use it today).
- Networking: the floor barrier and the join-mid-job flow assume "the next floor"; going to any floor changes that.

### Open questions
- ~~**Floors:** how many per contract?~~ **Decided: 3 floors per contract, and no backtracking** (the crew only ever goes
  down; see "Mission structure").
- ~~**Per-floor contents**~~ **Decided (option B, the descent builds to a climax):**
  - **Floors 1–2:** smaller hellgates and stray pests spreading up from below.
  - **Floor 3:** the **origin gate**, one big, tough hellgate where it all started, worth the
    largest payout. Closing it is the contract's finale.
  - **Proposals:**
    - the origin gate has phases, getting faster spawns and a defensive burst as it weakens;
    - closing it calms the rest of the site (its stray spawns stop);
    - leaving before floor 3 forfeits the biggest line on the invoice.
- **Between contracts:** **decided: everything heals and resets** (HP, downed heroes, cooldowns,
  statuses). Within a contract, damage carries from floor to floor, so taking the elevator down
  hurt is part of the push-your-luck.
  - **Spells:** decided: re-picked at the start of every contract for now. Components and charges
    don't carry over.
  - **Money:** decided: it has no purpose yet. The invoice total is the score.
  - **Reputation:** decided: none.
  - **Job board:** decided: always 3 new offers each time.
