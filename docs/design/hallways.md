# Hallways: landings and set pieces

Status: **built** (2026-10-26), on by default for generated floors behind a dev switch the gym's panel flips
(`DungeonGen.landings`, "Landings" in the gym's Experiments). The switch comes out once the user settles it. Code:
`scripts/world/dungeon_gen.gd` (the landings pass), `scripts/contracts/planners/prop_planner.gd` (`plan_set_pieces`,
`spawn_set_pieces`), `tests/test_landings.gd`, `tests/probe_halls.gd` (the measurements below).

## The problem

The user, 2026-10-26: "Next, lets think about how to make hallways interesting. They have gotten pretty long."

The generator keeps everything out of its halls on purpose: props, explosives, decor, notes and mail stay
`SiteBuilder.CORRIDOR_CLEAR` (2) cells from any corridor cell (`_corridor_zone`), raised features
`DungeonGen.FEATURE_DOOR_CLEAR` (3) cells from one, and the van, the gates and the staff stand in rooms. A hall is an
empty tube between two rooms.

**Measured before** (the brief's numbers, 30 generated floors): 233 corridors, end to end in a straight line median 18
units, p75 25, p90 36, max 88; corridors about 20% of the walkable floor, about 166 units of corridor and about 37 s of
walking a floor.

`tests/probe_halls.gd` measures the same floors the golden test builds (contract seeds 1-10, floors 1-3, as the game
builds them) and counts every carved hall door to door, 240 of them. Its numbers are a little different from the brief's
because it counts differently, but the shape is the same:

| Landings off (before) | median | p75 | p90 | max |
|---|---|---|---|---|
| door to door, straight line (units) | 20.8 | 26.0 | 33.0 | 58.5 |
| door to door along the route (what you walk) | 20.8 | 26.0 | 34.6 | 147.2 |
| hall units a floor (along the routes) | 188.8 | 199.2 | 207.8 | 322.2 |

The 147-unit outlier is a winding extra loop on seed 3's floor 1 (85 steps).

## The decision

The proposal put three ideas to the user: landings partway along long halls, one set piece at each, and explosives in
the halls. The user's answers:

- 2026-10-26: "For 3 lets think which will give the most impact with the fewest props. Lets not just spam to have
  something."
- 2026-10-26: "Build landings and set pieces only, no hall explosives."

So: a long hall widens once (or a few times on a very long one) into a **landing**, and each landing gets **exactly one**
priced prop, a tall landmark of the site's catalog, standing against the landing's back wall. Nothing else goes in a hall.
No explosives, decor, notes or mail, and no new models.

## As built

### Landings (DungeonGen)

- **Which halls.** A hall gets `DungeonGen.landing_count(length)` landings, where `length` is its route door to door in
  world units: none up to `LANDING_MIN_LEN` (22), then one, and one more for every `LANDING_EVERY` (24) beyond. A 46-unit
  hall gets two and an 88-unit hall three. The service stair never gets one (a sewer cluster's way down), nor the one
  short chokepoint (a narrow tree link), nor a sewer cluster's or a lava cave's own halls. Extra loops and the climb
  shortcut (narrow, 3.0 wide, often long) can get them.
- **Where.** Each landing sits nearest its even share of the route (`_landing_centres`). Within `LANDING_WINDOW` (0.3) of
  the spacing, a route cell where the route turns counts `LANDING_TURN_PULL` (2.5) steps nearer, and centres stay
  `LANDING_SPACING` (8) cells apart. The spots are picked **before** the hall's height profile is placed
  (`_landing_profile`). The hall's terraces and stairs then keep off them (from 4 route cells before the centre to 4 past
  it), stay `LANDING_DOOR_CLEAR` (3) steps off both doors so the two cells at each door stay at its level, and stay
  `LANDING_EVENT_GAP` (2) steps apart. A landing is a flat stretch, a stair landing in the literal sense.
  - If the steps don't fit, the spots move together by up to `LANDING_SHIFT` (half their spacing) until they do. If they
    never fit, the steps go where they always went and that hall gets no landing.
  - The profile's dice are drawn exactly as before; only where its steps go moves.
  - The door clearance and the gap came from the tests. Steps crowded against a door left a door whose square place the
    door planner missed (`test_door_span`). Steps back to back left a climb in the hall, so the floor failed validation
    and became another floor (5 of 68 `test_dungeon_gen` seeds before the gap; 0 of 128 after).
- **Shape.** A hexagon of `LANDING_R + 1` (3) rings: full floor out to `LANDING_R` (2), the outer ring cut by the
  midpoint walls. Its middle (the `hub`) is the route cell, or one of its neighbours on the far side from the camera. That
  way the bay opens away from the camera and the piece in it faces the camera instead of hiding behind the near wall
  (`_landing_shape`: the route cell when that gives such a back wall, else the neighbour most away from the camera that
  does, else whatever fits).
- **Clearances.** The hexagon's hall cells are floor at the centre's level, with no stairs within one ring more. Every new
  cell is free, a wall's width (2 cells) from anything that is not its own hall, and `LANDING_ROOM_CLEAR` (4) from every
  room cell. At that distance nothing that measures distance to the halls ever sees a landing: the rooms' raised features
  (3 cells), the rooms' planners' corridor zone (2), the van's and the mail's corridor distance (they walk through wall
  cells, and a landing's walls never touch a room's), and the elevator's notch.
- **No dice, and nothing before it moves.** The pass runs once every link is cut and before the start, the exit, the
  elevator, the features and the walls. It draws no random numbers and adds cells nothing earlier reads. With the
  landings on, every room cell, theme, priced prop, explosive, decor piece, note, mail spot, gate, employee, the van, the
  start, the exit and the elevator is exactly what it is with them off. `test_landings` checks all 30 golden floors, and
  128 plain generator seeds gave the same rooms with and without landings.
  What does move: the new cells and their walls, the heights along a hall with a landing (its terraces and stairs moved
  off the landing), and, on some floors, an office door on such a hall (its place follows the floor's steps) and a goblin
  scout's route.
- **Record.** `HexMap.landings`: per landing its `center` (the route cell), `hub`, `level`, the `cells` it added, its
  `hall` (the two room tags), `step` (its index on the route), `turn`, `dir_in` / `dir_out` and its `backs` (the hexagon's
  sides a set piece may stand against, best first). It is spawn data: `NetFloor`'s map text has a `landings=` line on a
  floor with any.

### How the cells are marked, and why

The cells are tagged **`"corridor"`** and the landings are recorded separately (`HexMap.landings`). A landing is part of
its hall, and every system that reads `tag == "corridor"` should treat it that way. A new tag would have made each of
them decide again. Each reader, checked:

| Reader | What it does with a landing |
|---|---|
| `Doorways.spaces` / `RoomFog` | a landing is part of its hall's fog space. A long-hall cut (`_split_halls`) moves up to `RoomFog.LANDING_CUT_MOVE` (2) steps to stay off a landing, so a landing and its set piece usually show together. When no such spot is near its even share, the cut crosses the landing: moving it further left segments longer than `test_fog_spaces` allows |
| `Doorways.find`, `DoorPlanner`, `DoorFloors` | doorways are where hall meets room; a landing is 4+ cells from every room, so no doorway changes shape |
| `MonsterSenses.room_doors`, `ThemeCtx` (a room's entrance), `SewerPlanner` | read hall cells next to room cells only: never a landing's |
| `SiteBuilder._corridor_zone`, `_corridor_distance` (van, mail) | as above: the landing's cells and walls are too far from every room to change a distance |
| `FloorMaterials`, `GrimePlan` | a landing gets the site's corridor floor and wall material and corridor grime: it looks like the hall it is in |
| `ScoutPlanner` | a scout's route may cross a landing, but never through its set piece or the cells beside it (`_link_path`'s `avoid`) |
| `PackPlanner`, `GatePlanner`, `EmployeePlanner`, `RoomThemes`, `NotePlanner`, `PackagePlanner`, `HazardPlanner`, `PoolGeo` | plan in rooms only: nothing of theirs lands on a landing (`test_landings`: no monster pack, gate, theme, room decor, note, mail or explosive on one) |
| `game_dev` `--to-corridor` | may now land in a landing (it picks the middle corridor cell) |

### Set pieces (PropPlanner)

- `PropPlanner.plan_set_pieces` gives each landing exactly one priced prop, picked from `PropPlanner.LANDING_KINDS`
  (the site catalog's tall pieces, readable from the hall's ends; no new models):
  - bunker: marble statue, crystal lamp, zen fountain
  - lair: evil portrait, brazier, henchman locker

  They are dealt in that order from a start the floor's own dice pick (its seed: no other dice move), so a floor shows
  several kinds. If a kind does not fit, the next one is tried.
- **Pose.** The piece stands flush against the first of the landing's backs where it fits, using ThemeCtx's wall pose
  (the march to the flat face), facing into the landing. Every point of its footprint is on a cell the landing **added**,
  so the hall's own width (4.5 or 3.0 between its walls) stays clear for the crew and a monster pack. It never stands on
  the wall side.
- **Plan and spawn.** `SitePlan.set_pieces` holds the same fields as a priced prop, plus `landing`; `room` is "". The
  pieces are not counted in `props` (`MAX_PROPS` stays the rooms' share). `PropPlanner.spawn_set_pieces` spawns them with
  `PricedProp.spawn` as the **last actors** of `SiteBuilder.spawn`, so no earlier net id moves. They go into `Site.props`,
  which makes them ordinary host-arbitrated world objects: dents, breaks and the bill as any priced prop, the fog's static
  tracking, the late-join `dents`. `_block_cells` blocks them for monsters.

### Networking

The landings come from the floor seed with no dice at all, and the set pieces' kinds come from a generator seeded from
the floor seed. Every machine builds the same floor, and the checksum covers it: the cells, the `landings=` line, the
plan's `set_pieces` and the spawn table. **A crew's floors always have landings** (`DungeonGen.for_run`'s `shared` passes
`"landings": true`). The dev switch is one machine's, so in a crew it is ignored and a desync is impossible.
`test_net_contract` passes, with the new `HexMap.landings` and `SitePlan.set_pieces` declared `Net.SPAWN`.

### Numbers after (the same 30 floors, landings on)

| | median | p75 | p90 | max |
|---|---|---|---|---|
| longest stretch of hall per hall, between doors / landings (route units) | 17.3 | 19.1 | 22.5 | 64.1 |
| every stretch (route units) | 17.3 | 19.1 | 20.8 | 64.1 |
| landings a floor | 3 | 4 | 5 | 8 |

Before, the longest stretch per hall was the whole hall: median 20.8, p75 26.0, p90 34.6, max 147.2.

- **Landings:** 93 on 30 floors, 3.10 a floor (one floor has none, one has 8). 88 of the 240 halls have one (37%).
  88 of the 104 halls long enough, and allowed one, got it. The other 16 are mostly 18-19-step loops with a big climb:
  no room for both a flat landing and steps clear of both doors.
- **Set pieces:** 93, one on every landing. Bunker: statue 18, lamp 20, fountain 18. Lair: portrait 14, brazier 12,
  locker 11. 89 of the 93 face the camera.
- **The longest stretch left:** 64 units, on the 147-unit loop on seed 3's floor 1. Its middle runs too close to rooms and
  other halls for a landing; it got 4 of its 6.
- **Turns are rare.** Only 1 of the 93 landings sits where the hall turns.
  - The routes are turn-penalised A*, so most halls run straight.
  - A stronger pull (twice the window, a 4-step pull) found only one more.
  - Making a hall bend at its landing would mean routing through the landing. That would move every hall, and with them
    the rooms' features. It is not done; it is a follow-up if the halls still read as straight tubes.
- **Floor share and cost.** The corridor share of the walkable floor goes from about 19% to about 22%: the landings add
  floor, and you walk the same distance. Generation goes from 140 to 147 ms a floor; the pass itself takes 2.5 ms.

## The A/B: the gym's panel (no keys)

The gym is one fixed map, so it has no landings. Its panel's **Experiments** has two pickers for this A/B
(`GymDev.experiments()`, `docs/design/test-gym.md`):

- **Landings**: off / **on** (the default). This is the generator's switch, `DungeonGen.landings`. It stays as picked
  for the rest of the session, like the other experiments.
- **Map**: **gym** / generated. "generated" reloads the scene onto the gym contract's **generated** floor (the same
  floor of the same contract, solo), with the gym's panel and tools kept (`GymDev.generated`). There a Landings pick
  rebuilds the floor at once, so the same floor can be walked with and without its landings. The **Go to** buttons are
  the floor's landings (landing_0, landing_1, ...). The elevator goes down to the next generated floor as ever. "gym"
  comes back. Leaving through the main menu forgets it (`reset_flow`).

From the main menu: the garage's dead H opens the gym, then Experiments > Map > generated. From a terminal:
`.\run.ps1 --gym --no-mic`, then the same.

## Dev flags

- `--to-landing [N]`: puts the crew in the hall three steps short of landing N (default 0), its set piece ahead. The
  log lists every landing of the floor with its set piece. `--focus landing` points the camera at the landing instead
  of the player. The screenshots of 2026-10-26 (contract 3 floor 1, lair: landings 0 and 2; contract 4 floor 1, bunker:
  landings 1 and 2) were taken with:
  `godot --path . --resolution 1600x900 -- --contract 3 --floor 1 --spells heal,corn --no-mic --to-landing 0 --focus landing --zoom 16 --shot <png> --shot-after 2`
- `.\test_runner.ps1 -TestName probe_halls`: the tables above (not part of `-TestAll`).

## Open

- Whether the landings and set pieces stay (then the switch comes out), and the thresholds (`LANDING_MIN_LEN`,
  `LANDING_EVERY`).
- Bending the hall at its landing (see "Turns are rare").
- The set pieces are priced props, so a fight in a hall can now break one (a statue is $8,000). That is the point of
  priced props, but it is new in halls.
