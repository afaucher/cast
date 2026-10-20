# Sharks

Status: **design only** (2026-10-19). Nothing in the game changed. There are new lab-only models and a lab scene:
- `scripts/art/lowpoly/props/shark_models.gd`: the three sharks.
- `scenes/shark_lab.tscn`, `scripts/art/lowpoly/shark_lab.gd`: the sharks in the real pools.
- `shark_swim.gd`: the steering prototype.
- `shark_measure.gd`: the tables below.

This builds on `pool-options.md`: its "Built", "Moat [built]" and "Shark (planned, not built)" sections. Where the two
differ, this doc replaces the planned section.

The user's brief (2026-10-19): three variants (a regular shark, a shark with a laser strapped to its head, and the same
ridden by an imp), smooth movement, the pool shapes and the moat, the attack style, whether sharks are priced property,
and pool-compatible room layouts.

## Decisions needed

1. **What a shark is, as property.** Recommended: **the client's shark**. You can't kill it, only drive it off. Each
   drive-off bills the culprit a flat fee: $1,500, or $2,500 for a laser shark. Dents are free (the money rule). The imp
   rider is an ordinary monster: fair game, free to kill, and it counts as an imp. The alternatives are a killable
   monster, a hazard that takes no damage at all, and per-hit billing ("Property, hazard or monster").
2. **The moat.** Recommended: **keep the one-row ring**, with the regular shark as a patrol hazard. It circles one way
   and bites sideways as it passes ("the drive-by snap"). Laser sharks go where they can turn: two-row shark pools and
   a new three-row "lagoon". The exception is the throne island, where the imp swings the laser. A shark in the moat
   room's fallback pool needs a two-row pool: 4 of the 9 fallbacks today are; the other 5 keep the decorative fins.
3. **The imp is the gunner.** It swings the head laser up to 90 degrees off the snout and gives the shark an imp's
   eyes. It doesn't steer or throw. A 1.0 shove knocks it off, 24 HP kills it, and a knocked-off imp wades out and fights
   on foot. Without it the laser locks forward again.
4. **The laser is one straight, locked shot.** It has the pavise's language: a red line that tracks for 0.8 s, then
   locks for 0.4 s. It stops at the first body, prop or wall. It does 22 damage, sets nothing on fire, and does set
   explosives off. There is no sweep.
5. **Where each variant lives.** The bunker gets the regular shark only. The lair gets all three: lasers from floor 2,
   the imp from floor 3 and on the throne island. Floor 1 keeps the decorative fins.
6. **The bite pulls you in.** 18 damage and a 1.5 shove toward the middle of the water, so a hero on the rim ends up
   wading (slow and soaked). Confirm this, or make it a push back onto the deck.

## The three variants

### Models (lab: `SharkModels`)
All three share one body:
- 2.4 from snout to tail stock, plus the crescent tail;
- built in **three segments**: head, body and tail;
- slate-blue back, white belly and a dark spine;
- a tall navy dorsal fin with a pale scar;
- ember-glowing eye slits under a heavy brow, and a jaw of teeth.

The origin sits on the belly. In the game's 0.36-deep wading pools it rides 0.06 off the pool floor, so its back and
fin are out of the water: a land shark in a paddling pool. The monster glow is on the eyes, the lens and the antenna
bulb. Everything else uses the hero toon bands, amber rim and ink outline (MonsterMaterial).

| Variant | Kit | At size 24 (the game camera) | Close up |
|---|---|---|---|
| **Regular** | none | a navy fin with a two-line foam wake and a pale body under the water | the scar, the ember eyes, the teeth just under the surface |
| **Laser** | Leather head straps and a steel plate. A swivel ring carries a chunky gunmetal emitter with two hazard-yellow bands, cooling fins, a flared muzzle, a **glowing red lens** and an antenna bulb. A girth strap carries two **yellow power canisters** on the flanks. The twin trigger grips are lashed forward with a yellow ratchet strap. | a black-and-yellow block on its head and two yellow bars down its sides; the red lens flares while it charges | the strap and buckles, the lashed grips, the cables to the canisters |
| **Imp-ridden** | The laser rig, a leather saddle behind the swivel, and the **imp** (the swarmer model, seated, legs astride, one claw on the rein strap and one on the trigger grip, leaning in as it aims). The grips are free. | a purple spiky dot on the yellow-black rig; the emitter visibly swings off the snout | the imp hunched over the grips, ears back |

Renders: `variants*.png` (game camera, close, per variant, side views). Every render and GIF named in this doc is in
the session scratchpad's `sharks\` folder (see "Lab").

### Roles
| | Regular | Laser | Imp-ridden laser |
|---|---|---|---|
| **Role in a fight** | Terrain with teeth. The water and its rim are a no-go zone while it hunts, and a trap for monsters you shove in. | A room-wide threat that is slow to aim. It turns its whole body to line up and fires along its nose. | The turret. It aims anywhere in its front half from wherever it swims, and the imp is the weak point you shoot first. |
| **At range** | nothing | only down its nose: it must turn to face you, at about 50 degrees a second while aiming, and you can walk round the pool faster than that | anything the imp sees, up to 90 degrees off the snout |
| **At the rim** | the bite (and the drive-by snap in a ring) | the same bite | the same bite; a hero at the rim can also shove the imp off |

### The rider (decided here, simple)
- **The imp aims.** It swings the emitter on its swivel, up to 90 degrees either side of the snout (it sits behind the
  emitter, so it can't swing it backward), and pulls the trigger. It also gives the shark an imp's sight: all round 9,
  a front cone of 15, line of sight. A riderless laser shark only notices what is in the water, within 1.2 of the rim,
  or within 16 in its nose's 90-degree cone. The imp doesn't steer (the shark swims its own patrol and turns toward
  targets as every laser shark does) and doesn't throw anything: one attack per variant.
- **Knocked off:** any shove of 1.0 or more on the imp. That covers Rebar's fist (1.6), Gasket's spin, tentacles, the
  bowl, a blast or a brute's slam. A daze does it too. It tumbles into the water, then it is an ordinary imp (the
  swarmer): it wades out and fights on land. It never climbs back on.
- **Killed separately:** 24 HP (an imp has 12). That is two tap arrows, one drawn arrow (28), a fireball or corn. It
  falls in and is gone. It counts as an imp kill.
- **What is left:** a riderless laser shark. The emitter springs back along the snout.
- **Hopping out onto land:** only when knocked off, or when its shark is driven off. It jumps to the nearest rim
  rather than sink, and fights on foot.

## Smooth movement

The prototype is `shark_swim.gd`. It is what the host's shark would run; the drawing part is what every screen runs.

**Continuous steering in the real water polygon.** The water is the pool record's `outline` (convex) and, for a moat,
its `hole` (the island, convex). The shark's centre line keeps `CLEAR` 0.42 off every rim: half its 0.72 width plus a
hair of liner. That uses the distance field `rim_distance(p)`, which is the minimum over the outline's and the island's
edges. It never steps cell to cell: hex cells play no part in its movement at all.
- **Heading, not position, is steered.**
  - The yaw rate is capped by the turning radius at the current speed, `omega <= v / R_TURN` with R_TURN 1.5. A floor of
    0.9 rad/s lets it still turn when nearly stopped.
  - The yaw acceleration is capped at 3.2 rad/s^2, so every turn eases in and out.
- **Speed ramps.** It accelerates at 1.6 u/s^2 and brakes at 3.2. A hard turn slows it to 65 %. It cruises at 1.6 and
  hunts at 2.8. A wading hero does 3.4, so you can always wade away.
- **Where it wants to go.**
  - Patrol: pure pursuit of a point 2.2 ahead on a patrol loop. In a moat the loop is the channel's middle line
    (`PoolGeo.channel`). In a pool it is the outline pulled in to the middle of the water.
  - In a convex pool it now and then turns round: it goes hard over toward the side with more water until it heads the
    other way round the loop.
  - Hunt: swim to a spot 2.8 from the victim, then turn to face them.
- **Rim avoidance.** Three feelers 1.3 + 0.5·v ahead, at -32, 0 and +32 degrees. A feeler that comes within CLEAR + 0.3
  of a rim bends the wanted heading along the distance field's gradient (away from the rim). A hard clamp keeps the
  centre line CLEAR off the rim after every move. A shove on the shark is clipped the same way: it never leaves the
  water.
- **The bending body (the fin trails the body).** The steered point is the head joint J0. The body joint J1 and the
  tail's end are the points 0.95 and 1.55 back along the **trail** J0 has swum (follow the leader). So the body curves
  through a turn instead of turning like a plank. The dorsal fin is on the body segment, 0.42 behind J0, so it lags the
  head through every turn.
  - Each segment **banks** into the turn: roll = 0.16·omega·v, at most 24 degrees, smoothed.
  - The head pitches up as it climbs the rim in a lunge.
  - A two-line foam wake spreads back from the fin along the trail, and a bow wave swells ahead of the snout in the
    wind-up.
- **The lunge.**
  - It waits 2.8 from the victim and turns to face them.
  - **Wind-up 0.6 s**: the fin dips 0.12, the bow wave swells and the monsters' orange pulse runs over it.
  - It then goes 9 u/s along its heading for up to 2.5. The head may go up to 0.7 over the rim, its belly lifted onto
    the coping, while the body stays in the water.
  - Then it **slides back down its own trail** (0.45 s: sharks don't reverse, the water takes it back) and swims on.

**On clients.** The shark is a host-owned mover, interpolated like the monsters (`NetWorld`):
- **Position** is Hermite from the stream's position and velocity, shown about 0.1 s behind. The lunge's 9 u/s fits the
  MONSTER entry's velocity byte (1/8 u/s steps, up to 15.9), so the lunge interpolates on its 7-8 samples.
- **Facing** turns the short way round.
- **The rest is local.** Every screen keeps its own trail of the *shown* head position and builds the bending chain, the
  bank (from the shown turn rate), the wake and the fin dip from it. Nothing about the body travels; only the head's
  stream does.

GIFs (about 4-5 s each, 20 fps):

| file | what it shows |
|---|---|
| `swim_pool.gif` | patrol and a full turn round in the indoor pool's biggest shape (the 7-cell trapezoid) |
| `swim_lagoon.gif` | the laser shark patrolling and turning round in the 3-row lagoon |
| `swim_moat.gif` | circling a 1-row moat ring |
| `swim_moat2.gif` | circling a 2-row ring |
| `lunge.gif` | hunt, wind-up, the lunge onto the rim at Wick (who is pulled), the slide back |
| `laser_fire.gif` | the imp shark turns, tracks Wick, locks, fires; Wick walks partly out of the locked line |

### Pool shapes against a 2.4-long shark
Measured with `--measure`. The quantities:
- **r_in**: the biggest circle in the water.
- **R circle**: the circle its centre can swim, `r_in - 0.42`, with the bending body.
- **R rigid**: the same for a rigid body, whose nose and tail swing out to `sqrt(R² + 1.2²)`.
- **Run**: the longest straight its centre has.
- **Lap**: its patrol loop.

The verdict compares R circle with the tightest bend (R 1.2) and a roomy turn (R 2.0).

| Shape (basin cells) | Where it is dealt | Outline L x W | Water | r_in | R circle | R rigid | Run | Lap | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| trapezoid 4+3 (7) | indoor pool, shark pool | 8.7 x 4.5 | 32.5 | 2.25 | 1.83 | 1.46 | 7.7 | 15.4 | tight turns only |
| parallelograms 3+3 (6) | indoor pool, shark pool | 7.8 x 4.5 | 28.6 | 2.25 | 1.83 | 1.46 | 7.0 | 13.7 | tight turns only |
| trapezoid 3+2 (5) | indoor pool, shark pool | 6.9 x 4.5 | 24.7 | 2.25 | 1.83 | 1.46 | 6.0 | 12.0 | tight turns only |
| parallelogram 2+2 (4) | indoor pool, shark pool | 6.1 x 4.5 | 20.8 | 2.25 | 1.83 | 1.46 | 5.3 | 10.3 | tight turns only |
| row of 4 | indoor pool, shark pool | 8.7 x 3.0 | 23.4 | 1.50 | 1.08 | none | 7.7 | 14.5 | **no turn: back and forth** |
| row of 3 | indoor, shark pool, **specimen** | 6.9 x 3.0 | 18.2 | 1.50 | 1.08 | none | 6.0 | 11.1 | **no turn** |
| row of 2 | indoor, shark pool, **specimen** | 5.2 x 3.0 | 13.0 | 1.50 | 1.08 | none | 4.2 | 7.6 | **no turn** |
| single cell | specimen | 3.5 x 3.0 | 7.8 | 1.50 | 1.08 | none | 2.5 | 4.2 | **no turn** |
| lagoon 5+6+5 (16) *proposed* | | 12.1 x 6.0 | 62.4 | 3.00 | 2.58 | 2.35 | 11.2 | 24.1 | turns round, circles at R 2.6 |
| lagoon 4+5+4 (13) *proposed* | | 10.4 x 6.0 | 52.0 | 3.00 | 2.58 | 2.35 | 9.4 | 20.6 | turns round |
| lagoon 3+4+3 (10) *proposed* | | 8.7 x 6.0 | 41.6 | 3.00 | 2.58 | 2.35 | 7.7 | 17.2 | turns round |
| lagoon 2+3+2 (7) *proposed* | | 6.9 x 6.0 | 31.2 | 3.00 | 2.58 | 2.35 | 6.0 | 13.7 | turns round |

Moat rings (the channel between the outline and the island):

| Ring | Cells | Outline | Water | Channel | Centre lane (channel - 2 x 0.42) | Corner fillet R | Side | Lap | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| 1 row (built; `MOAT_SIDES` 2-6) | 18-66 | 6.9 x 6.0 to 20.8 x 18.0 | 23-86 | **1.5** | **0.66** | 2.2-2.85 | 2.6-9.5 | 15.6-57.2 | one way round; can't turn round or face a rim |
| 2 rows *proposed* (sides 3-7) | 36-108 | 10.4 x 9.0 to 24.2 x 21.0 | 62-187 | 3.0 | 2.16 | 3.0-6.0 | 3.5-10.4 | 20.8-62.4 | one way round (a turn round needs a lane of 2.4); it can curve to face a rim and lunge |

What the game deals today, over the `test_pools` floors (5 clients x 7 seeds x 3 floors):
- **Indoor pools:** 50 in 54 rooms; 45 are two-row (5-7 cells: 15 x 7, 10 x 6, 20 x 5) and 5 are single rows.
- **Specimen pools:** 44 in 48 rooms, every one a single row.
- **Moat rooms:** 24 rings and 9 shark pools in 44 rooms. Of the 9 shark pools, 4 are two-row and 5 are single rows.

So:
- **A shark needs a pool two rows wide.** A single row (3.0 wide) can't turn a 2.4 shark round at all. A rigid body
  doesn't even fit across it while circling.
- The 2-row pools allow tight turns only: a circle of 1.8, which looks good with the bending body (`swim_pool.gif`)
  and cramped without it.
- The lagoon is the first shape where it cruises round comfortably.

## Moat reconsidered

**In the one-row ring the shark only circles.** The channel is 1.5 wide and its centre line keeps 0.42 off each rim,
which leaves a lane of 0.66. To turn round it needs a lane of 2.4 (R 1.2 each way). To face a rim and lunge, a
2.4-long body has to lie across a 1.5 channel. Neither fits. The corners are fine: the midline's 60-degree turns round
off at R 2.2-2.85, wider than the shark's own turn. So it can:
- circle the island one way at a steady speed (`swim_moat.gif`), which is very readable: you see the fin coming;
- bite **sideways as it passes**: the drive-by snap. A 0.5 s tell: the body curls toward the rim and the fin leans out.
  Then the head whips 50 degrees toward the rim and the snout reaches about 0.2 past it. It bites what is within 1.2 of
  the rim on that side: 14 damage and a 1.2 pull into the channel, every 3 s at most. Waders in the channel are bitten
  head-on as it reaches them.
- A riderless laser shark in a ring fires only along the six straight runs of the channel. Those are six fixed lanes
  that leave the ring at its corners, "lighthouse lanes". An imp-ridden one swings its emitter, so it works there as a
  turret on rails.

| Option | Placement (44 moat rooms; room median 127 cells) | Water / room | What the shark does | Cost |
|---|---|---|---|---|
| **A. Keep the 1-row ring** (now) | 24 rings + 9 shark pools = 33 | 25.4 cells, 19 % | circles; drive-by snap; regular shark and the imp turret only | none |
| A2. Ring, else only a **2-row** shark pool | 24 + 4 = 28 | 27.1, 21 % | as A; every fallback can turn | the 5 single-row fallbacks get fins only, or no water |
| B. 2-row ring, else 1-row ring, else pool | 8 + 16 + 9 = 33 | 26.9, 21 % | 2-row rings: circles, curves in to lunge, still no turn round | two shark behaviours per theme; `PoolGeo` gets a second ring width |
| B2. 2-row ring, else shark pool | 8 + 25 = 33 | 23.4, 18 % | most rooms lose the ring | the moat look is mostly gone |
| C. Shark pools only (2-row shapes) | 28 | 19.7, 15 % | tight turns everywhere | no ring, no island |
| D. Lagoon (3-row), else shark pool | 24 + 9 = 33 | 25.2, 19 % | roomy turns, lunges anywhere | no ring or island in the 24 rooms |
| D2. Lagoon only | 24 | 28.6, 21 % | as D | 9 more rooms without water |

The 2-row ring fits only 8 rooms: its smallest outline is 10.4 x 9.0 and its water 62 or more, against a 30 % budget.
The lagoon fits in exactly the rooms a ring fits in.

**Recommendation: A, plus the lagoon as its own layout.**
- Keep the ring as the moat. It is the user's chosen look, placement is unchanged, and a one-way patrol with a
  drive-by snap is a clean "cross behind the fin" hazard. Crossing the channel is one wading step (1.5 at 3.4 u/s,
  under half a second).
- Put a shark in a moat room's **fallback pool only when it is two rows wide** (A2). The single-row fallbacks keep the
  decorative fins.
- Laser sharks go where they can turn: two-row shark pools and the new **lagoon** (layout 7: the same rooms a ring fits
  in, so it can be rolled instead of the ring).
- The **throne island** (layout 5) keeps the ring and gives it the imp turret.
- No widening: B costs a second ring geometry to gain lunges in 8 rooms.

## Attack style per variant

One clear telegraph per attack. Every number is in the game's scale:

| For scale | Damage | Telegraph | Other |
|---|---|---|---|
| grunt (skeleton) | cleave 10 | 0.35 s | HP 40 |
| archer | arrow 8, range 16 | 0.5 s draw | HP 25 |
| brute | slam 25, radius 2 | 0.9 s ring | HP 140 |
| pavise (proposed) | bolt 18, range 20 | 1.2 s line | |
| Rebar's fist | 15, shove 1.6 | | |
| fireball | 40 | | |

Heroes: Wick 85 HP, Gasket 120, Rebar 160.

| | Regular | Laser | Imp-ridden laser |
|---|---|---|---|
| Nerve (its HP) | 120 | 120 | 120, plus the imp's 24 |
| Cruise / hunt | 1.6 / 2.8 | 1.4 / 2.4 | 1.4 / 2.4 |
| **Bite** | **wind-up 0.6 s** (fin dip, bow wave, orange pulse), then a lunge of up to 2.5 at 9 u/s. The head reaches 0.7 over the rim, so it bites up to about **1.2 onto the deck**. **18**, and a **1.5 pull toward the middle of the water**. One hit per hero per lunge. Cooldown 3 s. | the same, cooldown 4 s, and never while charging | the same as the laser |
| Drive-by snap (1-row ring only) | 0.5 s tell, 14, pull 1.2, cooldown 3 s | the same | the same |
| **Laser** | none | **charge 1.2 s**: the red line tracks the target for 0.8 s, then **locks** for 0.4 s (solid and bright, a reticle on the deck). It fires only within 10 degrees of its nose; it turns to aim at about 50 degrees a second, drifting at 0.45 u/s. Beam **22**, range **20**. **Cooldown 7 s.** | the same charge and beam; the imp swings the emitter up to 90 degrees off the snout (tracking at 180 degrees a second), so it aims without turning. **Cooldown 6 s.** |
| Targets | anything (heroes, monsters, employees, chickens) in the water or within 1.2 of the rim; not a downed hero | + anyone in its nose cone within 16, in sight | + anyone the imp sees (9 all round, 15 in its cone) |

**The laser in detail:**
- **One straight shot along the locked line.** No sweep (two shapes of telegraph are one too many), no tracking after
  the lock. The beam hits a body within about 0.65 of its line, so a hero walking at 4.5 clears it in about 0.3 s:
  the 0.4 s lock is a reflex dodge. The
  tracking 0.8 s is time for a call-out ("line on you, Wick").
- **Line of sight.** The lens rides about 0.33 above the deck, so the beam skims the floor at shin height.
  - It is stopped by walls, solids (pillars, gantry legs, the elevator), a shut office door, a crate, a priced prop,
    and **the first body it meets**: hero, monster, employee or chicken.
  - It passes over the coping.
  - Cover therefore works, and so does body-blocking: Rebar standing in the line takes it for Wick, the pavise's tank
    job again.
- **What it hits.**
  - Whatever stops it takes 22, monsters included: it hurts both sides, so a grunt in the line is a shield.
  - A priced prop takes 22, and if that breaks it, the bill names "the shark" (every break is on the invoice, like an
    archer's arrow).
  - **Explosives:** 22 is a hard hit (15 or more), so it lights one: "get the laser to shoot the drums". A soaked one is
    a dud, as for any hit.
- **No fire.** It sets nobody alight: fire stays the fireball's. It leaves a scorch line on the floor (Grime, cosmetic).
- **Mic safety.** The charge is a rising electric whine, the fuse's family (`FuseFx`): tonal, never voice-like, under
  the cast cues' level. The beam is a short zap. Neither should be able to open the speech gate. Test it with the
  speech gate's probe, as the order cues were tested.

Renders: `laser_aim.png` (tracking), `laser_lock.png`, `laser_fire.png`, `laser_fire_game.png` (size 24),
`throne.png` (the imp aiming at the door).

## Property, hazard or monster

| | How it plays | Ledger and invoice | Spells | "Exterminate" | AI allies |
|---|---|---|---|---|---|
| **(a) A monster you can kill** (HP 120) | The simplest to build (a Monster), and the hazard goes away for good once it dies. It is cheap to solve: three fireballs. | nothing; a lost employee as usual | normal damage | it would count for "everything" | fight it like any monster, under the restraint baseline |
| **(b) A hazard you can't hurt** | It only takes distractions: corn, chicken, tentacles. Damage that does nothing reads as a bug, and against a laser the only answers are cover and its rider. | nothing | most do nothing | no | ignore it |
| **(c) Priced property, every hit billed** | A strong gag ("Please do not hit the shark"). Per-hit bills are a new billing rule (the money rule bills breaks only). Corn on a grunt beside the pool bills too, and the invoice fills with $250 lines. | a line per hit (or one summed line) | all bill | no | never target it |
| (c') Property you can kill, billed in full (say $25,000) | The money rule unchanged: dents free, the kill billed. A permanent fix at the price of most of a contract (the bill is capped at the contract's value). | one line | normal | no | never target it |
| **(d) Recommended: the client's shark (b + c) and a free imp** | It can't die ("irreplaceable"). **Nerve 120**: at 0 it **sinks** for 20 s (gone from the surface, harmless) and resurfaces at full. Dents are free (the money rule). **Each drive-off bills the last damager a flat fee**: $1,500, or $2,500 for a laser shark ("laser recalibration"). Driving it off is the deliberate big play (hazards.md: "every big play is also a money call"). The imp is a monster: free to kill. | "Shark (driven off) — $1,500 — Wick", once per sink. What the shark breaks is billed to "the shark". | see below | the shark never counts; the imp counts as an imp ("Exterminate imps" and "everything") | see below |

**Spells and attacks under (d):**

| Spell or attack | Effect on the shark |
|---|---|
| **Fireball** | 40 to nerve; no fire (it is always soaked) |
| **Corn** | 60 to nerve, and it is **chum**: the shark turns to the kernels in the water for 4 s (no bite, no beam). The joke play is "cast corn in the pool". It can also bill, if it finishes the nerve. |
| **Tentacles** | the shove can't move it out of the water, so it is **held** 1.5 s (no bite, no beam); it knocks the imp off |
| **Teeth** | 25 x power to nerve; the shark with too many teeth is the gag |
| **Vines** | they root it 2 s like anyone (the pool has a floor). A rooted shark still bites what is in reach and fires along its nose; the imp still swings the emitter. This changes `pool-options.md`'s "cannot root it". |
| **Damp** | nothing (it is wet) |
| **Coffee** (an accident) | +60 % speed and attack rate for 6 s; the laser's charge drops to 0.75 s |
| **Chicken** | a chicken that wades in is eaten (a feather burst) after a 2 s chase |
| **Heal, armor** | nothing |
| Weapons, the bowl, explosive blasts | dent its nerve |
| Brute daze | holds it 0.6 s and knocks the imp off |

**AI allies:**
- They **never target the shark**. It is TEAM_NEUTRAL like a prop (`prop_care`), and an "attack" order doesn't change
  that.
- They **avoid its water while it is up**: pool cells cost more in their paths while the pool's shark is not sunk.
  They don't idle within 1.2 of its rim.
- They may shoot the **imp** once it is in the fight (aiming counts), under the restraint baseline. Their
  "prop in the lane" check must skip the imp's own mount, or Wick's AI would never shoot it.
- Stepping out of a locked red line is a follow-up, shared with the pavise.

**Why (d):**
- It keeps the money rule's shape: dents free, one bill for the big event.
- It keeps the "irreplaceable" gag literal.
- Every spell has a legible answer, and the crew gets three real choices: route round it, distract it (corn, chicken),
  or pay to sink it for 20 s. Against the laser there are also cover, body-blocks and shooting the imp.

## Networking shape

**Shape: a host-owned actor, confined to its water** (AGENTS.md shape 2).
- The new class is `Shark` (`scripts/monsters/shark.gd`, kind "shark"). It extends `Monster` to reuse its stream entry,
  wind-up event, puppet and `net_strike`.
- Team `TEAM_NEUTRAL`. Group "sharks", **not** "monsters", so it doesn't count as a pest and monster or AI-ally
  targeting skips it.
- Moves are clipped to its pool record. Its HP is its nerve. Billing is the host's Ledger, like `PricedProp`.

The imp is a `Jockey` (a swarmer subclass, kind "swarmer" so it counts as an imp). It is an ordinary host-owned
monster that is drawn in the saddle while mounted.

**Declarations, roughly (`net_fields`):**

| Kind | Shark | Jockey (on top of Swarmer's) |
|---|---|---|
| SPAWN | `variant`, `pool_index` (its `HexMap.pools` record), nerve max, speeds, bite and laser numbers, drive-off price, sink time | `mount_id` (its shark's net id) |
| OWNER (streamed, MONSTER entry) | position, velocity, `facing`, `hp` (nerve), `state` (3 bits: CRUISE 0, HUNT 1, BITE 2, RECOIL 3, SUNK 4, CHARGE 5, HELD 6, CHUM 7), `_telegraph` (bite wind-up or laser charge, 0..1), `strikes` (bites and shots: a change plays them on puppets) | the usual monster fields |
| OWNER (events) | `target`, `_windup_total` / `_left` (`world.windup`); `lock_origin`, `lock_dir`, `fire_at` (new `world.lock`) | `mounted` (new `world.dismount {id, how}`) |
| PRIVATE | steering (loop sign, carrot, omega, speed ramp, turn side, reverse timer), senses and scan timers, the chum or chicken target, cooldowns, the hunt spot, the last damager (for the bill) | |
| LOCAL | the trail and the bending chain, the bank, the fin dip, the wake and ripples, the emitter's swivel while tracking (aimed at the victim as this screen shows it), the lens glow, the aim line | the saddle pose while mounted |

**Carriers.**
- Snapshot fields: `NetWorldCodec.SHARK_FIELDS` (a MONSTER-format entry, the way chickens use it): hp, facing,
  climbing (always false), state, `_telegraph`, strikes.
- Events, in `NetEvents.WORLD_CARRIES` for `shark.gd`:
  - target, `_windup_*`: `world.windup`;
  - `lock_*`: `world.lock`;
  - `dead`: "never set: a shark sinks, it doesn't die";
  - `_modifiers`: `st` (vines, coffee).
- For `jockey.gd`, `mounted` is carried by `world.dismount`.

**Late join (`NetEvents.LATE_JOIN`).**
- Shark: a keyframe (position, facing, nerve, state; a sunk shark shows sunk). Wind-ups and charges are skipped (under
  1.5 s).
- Jockey: as monster.gd (keyframe, gone ids). A dismounted one is a replay of `world.dismount` in the snapshot.

**The bite** uses the existing path. `world.windup {id, s, l = 0.6, v}` goes out at the wind-up. The lunge is just
streamed motion. Each client resolves the bite on **its own hero** when its render time reaches s + l
(`Monster.net_strike` → `Shark._strike`): `Combat.melee_arc` from the puppet's head. The pull-in is a `shove` applied
by the victim's owner (rule: a hero's owner applies shoves on it). The host resolves monsters, employees, AI heroes and
chickens.

**The laser beam** (a scheduled effect with an explicit lock):
1. `world.windup {id, s, l = 1.2, v}` at the charge start. Every screen draws the tracking line from the puppet's lens
   to **the victim as it shows them** (LOCAL).
2. `world.lock {id, o, d, t}` at s + 0.8: the lens point, the direction, and the fire time t = s + 1.2 on the shared
   clock. Every screen freezes the line on (o, d).
3. At t every machine runs the beam, like an explosive's blast at `obj.fuse.e`. It walks the line from o along d and
   stops at the first thing **as that machine shows it**. Each machine applies only what it resolves:
   - its own hero (the victim decides);
   - on the host: monsters, employees, AI heroes, props and explosives (the prop's `obj.hurt` and `obj.break` as usual).

The lock gives 0.4 s of notice, double `NetCasts.LEAD` (0.2), so on any link in `NetLink`'s presets the event arrives
before the screen's render time reaches t. A separate lock event is needed because the imp's swivel angle isn't in the
stream. The riderless one could fire from the puppet's facing, but one rule for both is simpler.

**Hits on the shark.** A client's hit or shove on it is a request (`Net.route_hit`, `Net.route_shove`). The host
applies the nerve damage, clips shoves to the water, sinks it at 0 and bills the drive-off. The sink rides `state` and
the bill is the host's Ledger (a client mirrors it).

**Flagged (not quite an existing shape):**
1. **An actor riding an actor.** No actor rides another today. While mounted, a client ignores the jockey's stream
   position and draws it in its shark's saddle (LOCAL). `world.dismount` hands it back to the stream with a teleport
   counter bump, so it doesn't slide.
2. **"Stops at the first body" across owners.** Each machine decides blockers from its own view, so an AI ally ~0.1 s
   out of place can shield a client's hero on one screen and not on the host's. That is acceptable under "the victim
   decides", and noted.
3. **A Monster subclass outside the "monsters" group, on the neutral team.** Check the places that assume
   `Monster == pest` (the pest count, `AllyBrain`'s targeting, `Combat`'s team masks).
4. **`world.lock`** is a new event kind in `NetWorld`, and needs a two-peer test: a client dodges a locked beam on its
   own screen and takes nothing; a client hero shielded by a host prop takes nothing; one drive-off bill.

## Pool-compatible room layouts

Common rules for every layout:
- The water follows `PoolGeo.carve`: clear of the start, the exit, the elevator, doors and corridors (CORRIDOR_CLEAR),
  gates and employees (2), at most 30 % of the room, near its centre, with dry deck all round.
- Sharks are rolled by the host on `GameWorld.rng` after the carve, only into **two-row or wider** water.
- **Floor 1 keeps the decorative fins and has no real shark.**

Legend for the sketches (rough hex rows, the camera's top at the top): `#` wall, `.` deck, `~` water, `D` door or
corridor, `C` crew start side, `x` cover (prop or decor), `$` priced prop, `S` shark, `i` imp shark, `T` throne.

### 1. Indoor pool (bunker, `pool`; built)
- **Themes and sites:** bunker indoor pool. Regular shark, from floor 2, 35 % of rooms whose pool is two-row (45 of 50
  today).
- **Pool:** the 7-, 6- or 5-cell two-row shapes (8.7-6.9 x 4.5).
- **Patrol:** the inset loop; it turns round every 6-12 s.
- **Doors and deck:** the deck all round, at least one cell (1.7) between the rim and anything. Loungers along the long
  sides, about 2 from the rim: outside the bite's 1.2.
- **Cover and sight lines:** no laser here.
- **Crossing:** walk round on the deck (always possible), or wade straight across (two seconds of 3.4 u/s, soaked)
  when the fin is at the far end.
- **Placement:** as built (`needs_center`). The marble statue ($8,000) and the propane tank stay on the walls, out of
  the pull-in's path.

```
 # # # # # # # # # #
# . x . x . x . . $ #
 . . ~ ~ ~ ~ ~ . . .      lab: indoor.png, indoor_close.png
D . ~ ~ ~ S ~ ~ ~ . #          swim_pool.gif, lunge.gif
 . . ~ ~ ~ ~ ~ . . .
# . x . x . x . . . #
 # # # # # # # # # #
```

### 2. Science specimen pool (lair, `science`; built)
- **Themes and sites:** lair science room.
- **Pool:** a single row of 1-3 under the gantry (3.0 wide). **No shark** (`specimen.png` shows a shark crammed into
  one: it can't turn). This is the escaped specimen's home instead (pool-options.md).
- **If a shark is wanted here:** a "test pool" variant with the two-row shapes, no gantry (its legs need a single row),
  a console at the end, and a **laser shark** (the experiment). That is a new `PoolGeo` look rolled instead of the
  specimen pool, about one science room in three.
- **Placement:** `needs_center`, as built.

```
 # # # # # # # # #
# x . . G . . . x #        G gantry legs (solids)
 . . ~ ~ ~ ~ ~ . .        lab: specimen.png, specimen_close.png
D . . . G . . . $ #
 # # # # # # # # #
```

### 3. Shark moat (lair, `moat`; built)
- **Themes and sites:** lair shark moat. Floor 1 has fins only; from floor 2 a **regular shark**.
- **Pool:** the one-row ring (18-66 cells).
- **Patrol:** one way round the channel's midline, a lap of 16-57 at 1.6 u/s (10-36 s).
- **Doors and deck:** the bridge decor on the door side, the fin sign. The island holds anything: a priced prop, mail,
  a component.
- **Cover and sight lines:** none needed (no laser).
- **Crossing:** wade the 1.5 channel behind the fin, under half a second. Standing on either rim as the fin comes round
  invites the drive-by snap.
- **Placement:** as built (`needs_center`, `avoid_exit`; no gate in the middle).

```
 # # # # # # # # # # #
# . . . ~ ~ ~ ~ . . . #
 . . ~ . . . . ~ . . .       lab: moat.png, moat_close.png, swim_moat.gif
# . ~ . . $ . . ~ S . #
 . . ~ . . . . ~ . . .
D = . . ~ ~ ~ ~ . . . #      = the bridge decor, pulled back
 # # # # # # # # # # #
```

### 4. Shark pool (lair, `moat` fallback; built)
- **Themes and sites:** a moat room where no ring fits. A **laser shark** from floor 2 (40 %), else regular. Only when
  the fallback pool is two-row (4 of 9 today); single rows keep the fins.
- **Pool:** two-row convex (5-7 cells).
- **Patrol:** the inset loop.
- **Doors and deck:** as the indoor pool. The `shark_tank` priced prop on a wall.
- **Cover and sight lines:** the room's crates and priced props are the cover. Its nose cone covers about a quarter of
  the room at a time.
- **Crossing:** round the deck. Keep something between you and its nose.
- **Placement:** as built; add the two-row rule for a shark.

```
 # # # # # # # # #
# $ . . . . . . . #
 . . . ~ ~ ~ ~ . .        lab: shark_pool.png, shark_pool_close.png
D . . ~ ~ S ~ ~ . #
 . x . . . . . x .
# . . . . . . . . #
 # # # # # # # # #
```

### 5. Throne island (lair, `throne_room` with a ring; new)
- **Themes and sites:** lair throne room, floor 3 (or the origin room when the story's origin is the throne room).
  **Imp-ridden laser shark.**
- **Pool:** a one-row ring of 42 cells or more, so the island is at least 3 cells across round the throne (`throne.png`
  uses the 54-cell ring).
- **Patrol:** the ring. The imp swings the emitter to fire across the room at the door side, a turret on rails.
- **Doors and deck:** the throne ($9,000) on the island, facing the main door, with a red carpet to the island's rim.
  Braziers ($400) and the doomsday console ($20,000) between the door and the ring are the **cover**, and every one is
  billable when the beam hits it.
- **Cover and sight lines:** the door is on the far side of the room from the shark's usual position; the ring itself
  doesn't block the beam.
- **Crossing:** shoot the imp first (24 HP, a drawn arrow), or approach behind cover and cross the channel when the fin
  is round the far side. The throne island is the prize (the gate or the loot).
- **Placement:** a new `throne_room` recipe op (`moat_island`): the ring as `PoolGeo` builds it (LOOK_MOAT), the
  throne snapped to the island's centre (`rec.center`). `needs_center`; no employees on the island; the ring clear of
  corridors as usual. In a room too small for a 42-cell ring, the throne room is dealt without one.

```
 # # # # # # # # # # # # #
# . . . . . . . . . . . . #
 . . . ~ ~ ~ ~ ~ ~ . . . .
# . . ~ . . . . . ~ . . . #     lab: throne.png, throne_close.png
 . x ~ . . = = T . ~ . . .      = carpet
# . . ~ . . . . . ~ . . . #
 . . . ~ ~ ~ i ~ ~ . . . .
# . x . . . . . . . x . . #
 . . . . $ . . . . . . . .
D C . . . . . . . . . . . #
 # # # # # # # # # # # # #
```

### 6. Twin pools with a gangway (bunker `pool` in big rooms, or the spa; new)
- **Themes and sites:** the indoor pool in a room of 160 cells or more; the wellness spa as "the plunge pools". Two
  regular sharks from floor 2, or one shark and one empty pool on floor 2.
- **Pool:** two two-row trapezoids side by side along their long sides, one ROW of deck apart: the rims are 1.5 apart
  (`twin.png`: pool B is pool A moved 6.0 straight across).
- **Patrol:** each shark its own loop.
- **Doors and deck:** deck all round both pools. The gangway is 1.5 of deck between the rims.
- **Cover and sight lines:** none needed (no laser).
- **Crossing:** the gangway is the short way across the room, but its middle is 0.75 from both rims: inside the bite's
  reach from both sides. Run it when both fins are at the far ends, or go round. It is also the place to shove monsters
  in from either side.
- **Placement:** a new `PoolGeo` look (`twin`): two variants of the same shape and axis, the second anchored one ROW
  past the first's rim (a lattice step of 3 rows across the axis). Both rings are full cells; the walk ring of each
  includes the other's ring cells (their deck side is deck). The 30 % budget covers both pools together.

```
 # # # # # # # # # # #
# . . . ~ ~ ~ ~ . . . #
 . . . ~ ~ S ~ ~ . . .       lab: twin.png, twin_close.png
D C . . . . . . . . . #      <- the gangway (1.5)
 . . . ~ ~ ~ ~ S . . .
# . . . ~ ~ ~ ~ . . . #
 # # # # # # # # # # #
```

### 7. Lagoon with a pier (lair, `moat` alternative; new)
- **Themes and sites:** a lair moat room where a ring fits: roll the lagoon instead of the ring about one time in three.
  **Laser shark** (floor 2+) or **imp shark** (floor 3).
- **Pool:** three-row convex, 7-16 basin cells (6.9-12.1 x 6.0), the moat look.
- **Patrol:** roomy: it circles at R 2.6 and turns round anywhere (`swim_lagoon.gif`), so the riderless laser can face
  any part of the room.
- **Doors and deck:** deck all round. A plank **pier** (decor, like the bridge) pointing at the water from the door
  side: the obvious place to stand, and the worst one.
- **Cover and sight lines:** crates and priced props on the deck. The console ($20,000) at the far wall is the classic
  bad cover.
- **Crossing:** round the deck behind cover; the laser decides the pace.
- **Placement:** `lagoon_variants()` from `shark_measure.gd` become a `PoolGeo` shape list (MOAT_POOL's look). It fits
  in the same rooms a ring fits in (24 of 44 here).

```
 # # # # # # # # # # # #
# $ . . . . . . . . . . #
 . . . ~ ~ ~ ~ ~ ~ . . .
# . . ~ ~ ~ ~ ~ ~ ~ . . #      lab: lagoon.png, lagoon_close.png, variants*.png, swim_lagoon.gif
 . . ~ ~ ~ i ~ ~ ~ ~ ~ .
# . . ~ ~ ~ ~ ~ ~ ~ . x #
 . . . ~ ~ ~ ~ ~ ~ . . .
D C = = . . . x . . . . #      = = the pier
 # # # # # # # # # # # #
```

### 8. The shark tank breaks (lair `moat` or `lab`; later)
- **Themes and sites:** any room with the `shark_tank` priced prop ($7,000, 60 HP; the moat theme's priced list).
- **Pool:** none, or the room's own.
- **What happens:** breaking the tank (billed as usual) spills its water as a flooded patch (pool-options option D,
  about 20 s, a scheduled effect) and drops out a **land shark**. It flops for 8 s, snapping at anything within 1.0
  (10 damage). It wriggles toward the room's pool if one is within 8 and becomes that pool's shark (+1), else it lies
  gasping, harmless, until the floor ends ("please put the shark back" is a joke, not an objective).
- **Placement:** nothing new (the tank is placed today). The flop is a runtime spawn (`world.spawn`, kind "shark",
  variant "flop") from the host's break.
- It is listed as a layout because it gives the shark tank a reason to exist. Build it last.

```
 # # # # # # #
# . . $ . . . #      $ the tank on its wall: break it, and a shark flops out
 . . . . . . .
D C . . ~ ~ . #      ~ the spill
 # # # # # # #
```

## Lab

```
godot --path . --resolution 1920x1080 -- --scene res://scenes/shark_lab.tscn --case <case> --shot <png>
godot --path . --headless -- --scene res://scenes/shark_lab.tscn --measure
godot --path . --resolution 960x540 --write-movie <dir>/f.png --fixed-fps 20 --quit-after 100 -- --scene res://scenes/shark_lab.tscn --case swim_pool
```

- **Where the renders are:** the session scratchpad, `...\scratchpad\sharks\`. `contact_sheet.png` has the twelve main
  stills; `measure.txt` has the measurement tables.
- **Still cases:** indoor, moat, shark_pool, specimen, lagoon, throne, twin, moat2, variants, laser.
- **Animated cases:** swim_pool, swim_lagoon, swim_moat, swim_moat2, lunge, laser_fire.
- The pools are the game's own: `PoolGeo` shapes carved into a `HexMap` room, `HexMapView`, `PoolView`, `DungeonLook`
  and the theme light. The lab only removes `PoolView`'s decorative fins.
- The models are in the z-fight registry (`ZFightModels`: `shark/regular`, `shark/laser`, `shark/imp`, and the stack
  `shark_rider`). They are clean.

## Open questions

1. Prices: $1,500 / $2,500 per drive-off, and nerve 120? Should a laser shark's drive-off cost more than its rig?
2. Should corn's hit dent the shark (and so risk the bill), or should corn be pure chum?
3. Can the crew knock the laser rig itself off (a priced "shark-mounted laser"), turning a laser shark into a regular
   one?
4. Is a shark in the bunker on-brand (a billionaire's pet), or is it lair-only?
5. Should a downed hero in the water be left alone (proposed), or dragged to the rim?
6. The throne island and the lagoon: new layouts now, or after the regular shark ships?
7. The shark tank's land shark (layout 8): wanted?
