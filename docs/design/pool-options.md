# Pool options: water as terrain

Status: **option B built** (2026-10-18), wading depth only; see "Built" and "Shark (planned)" below. The rest of this page
is the options study it was chosen from (its renders come from the lab scene).

## Built [decided, user, 2026-10-18]

**Decision:** build **B, the in-ground midpoint inset** (the look of the lab's inset and of its specimen pool), **wading
depth only**, mostly as decoration for now, in the **indoor pool** theme (replacing the flat `pool_basin` decal) and a
new **science** room theme (first built as "mad science lab", renamed by the user the same day). Raised glass tanks (C),
breakable glass and swimming are not built. The **shark moat became real water** the same day (user: "The moat should
become real water"): see "Moat" below.

**Terrain** (`scripts/core/hex_map.gd`, `scripts/world/pool_geo.gd` `PoolGeo`):
- A pool is a convex cluster of **basin** cells sunk **one level** below the room (`Cell.level` = the pool floor,
  `pool_mask` = all six kites). The **ring** cells round it are cut along midpoint lines like a wall cut downward: kites
  d - 1 and d of a ring cell whose neighbour d is a basin cell are pool floor (`pool_mask`, at `pool_level`), the rest
  is deck. So the rim runs from hex centre to hex centre at 0 / 60 / 120 degrees and every corner is 120 degrees.
- The water is `HexMap.WATER_DEPTH` = **0.36** deep over the pool floor (the deck is 0.5 above it): knee deep.
  `HexMap.water_at(p)`, `water_surface(p)`, `is_pool_cell(c)`; `ground_level` returns the pool floor on the pool side.
- **The rim is a step, not a wall** (one level, `STEP_LEVELS`): everybody walks in and out anywhere along it, and
  every pool cell is an ordinary full cell, so `find_path`, the allies, the employees and the monsters need no change.
  No ladder or steps are needed; the indoor pool keeps a chrome **ladder** on its far rim as decoration.
- **Shapes:** rows of 1-4 basin cells and two nested rows (trapezoids 4+3 and 3+2, parallelograms 3+3 and 2+2) in all
  six orientations; each oriented shape is checked once to be convex (its pool kites are exactly the triangles inside
  its outline). The indoor pool rolls its first try among the 7-, 6- and 5-cell shapes (then smaller); the specimen
  pool is a row of 3 or 2 (a single cell last).
- **Placement** (`PoolGeo.carve`, from `SiteBuilder.plan` right after the themes are dealt): the room's own floor at its
  base level, nearest its centre (within 7 units). The water cells (basin and ring) are full cells, not within
  `START_CLEAR` / `EXIT_CLEAR` of the start or the exit (the elevator's landing), not on `ElevatorGeo.keep_cells` (the
  car), not within `CORRIDOR_CLEAR` of a corridor (doorways), not in a hellgate's clear zone, 2+ cells from every
  employee, and at most 30 % of the room; every cell round the ring is the room's floor at base level too (dry deck all
  round, no pillar or pit touching the water). The van and the crew's arrival spots are inside the avoided start / exit
  zones. Props, decor, notes, mail and monster packs are planned after it and keep to dry floor.
  Over the test runs 94 % of the pool rooms get their pool (a room crowded with pillars and platforms gets none).
- Deterministic per floor seed with its own generator: spawn data (`HexMap.pools` is `SPAWN`), and the floor checksum
  (`NetFloor.map_text_of`) hashes the records and every cell's `pool_mask` / `pool_level`.
- A specimen pool's **gantry** stands across its middle basin cell on the two deck cells two rows over: its legs are
  `HexMap.solids` and those cells are `no_stand` (like the elevator's posts), so bodies and paths go round them.

**Look** (`HexMapView`'s inset mode, `scripts/world/pool_view.gd` `PoolView`):
- A ring cell's deck kites are a floor tile running flush into the rim line; its pool kites and the basin cells are
  the tiled pool floor (no bevel, no seam glow); on each rim line a tiled **liner** face runs from the deck down to the
  pool floor, facing the water. One tile shader (`HexMapView.POOL_SHADER`, the lab's look) with two looks: aqua tile and
  white grout (indoor pool), dark green tile with glowing grout (specimen pool).
- `PoolView` adds the **water** (the outline at the surface, the lab's toon water shader on `TIME`, alpha 0.58 indoor,
  0.68 green), the **coping**, a **foam line**, the ladder and the gantry with its dangling cage.
- **The corners (fixed).** The lab built the coping from boxes 0.24 longer than each rim segment, so at every corner
  two boxes crossed and stuck out (the chamfered, misaligned ends in `inset_close.png`, `lab_edge.png`), and its liner
  stood just off the rim over `HexMapView`'s upside-down wall face. Now the coping and the foam line are **mitred
  offsets** of the outline (`PoolGeo.offset`): each edge's strip is a trapezoid whose ends lie on the corner's bisector,
  so neighbouring strips share one seam. The coping overhangs the water by 0.05, runs 0.34 onto the deck and stands
  0.07 high with a nosing. The liner faces stand exactly on the rim lines and meet on the hex centre under each corner,
  and the deck tiles end flush on the same line, so the coping sits on one clean line all round.
- Tests: `tests/test_wall_mesh.gd` checks all 63 pool masks (deck top, seam and pool floor triangulate exactly), the
  liner faces (on rim lines, deck to pool floor, facing the water, one texture density) and the coping (winding, no
  overlap, the exact band area, every corner seam on the bisector `COPING_W` out from both edges).

**Wading** (`scripts/world/wading.gd` `Wading`, run by `GameWorld` every physics frame on a floor with pools):
- **Slow:** any actor (heroes, AI allies, employees, monsters) walks at **0.75x** in the water (`Actor.effective_speed`);
  it stacks with coffee and the other speed modifiers.
- **Casting and weapons** are unchanged in the water (knee deep: nothing about it stops a swing or a bow).
- **Wet:** an actor in the water is soaked the whole time (`Wet.douse(actor, SpellBook.DAMP_SOAK)`, the Damp spell's
  status, re-applied when 2 s of it have run out) and once more as it steps out, so it stays wet the normal **15 s**
  after leaving. The soak puts a fire out and blocks ignition (`Burning.soak`), so wading in is how a burning hero
  puts itself out, and a fireball fizzles on a wader.
- **Down in the water:** nothing special happens.
- **Monsters:** the simplest consistent rule: they wade like everyone else (the same 0.75x, the same soak), and land
  AI paths straight through water cells. Monster packs spawn on dry floor.
- A ripple ring circles every wader on the water surface (cosmetic).
- **Networking:** the water is seed-built terrain on every machine. The soak is an **owner-applied status**: each
  machine soaks only the actors it owns (`Net.resolves`) and `NetStatus` tells the others ("soak"); the slowdown is
  `LOCAL` (from the position and the map); the ripple is cosmetic. No new synced field. `tests/test_net_pools.gd` (two
  processes) checks it: the client's burning hero wades in, its own machine puts the fire out and soaks it, the host's
  screen shows it, and so on.

**Themes** (`RoomThemeDefs`, `ThemeVignettes`):
- **Indoor pool** (bunker): the in-ground pool with loungers along its long sides facing the water, the POOL sign and the
  marble statue. The `pool_basin` decal is gone.
- **Science** (`science`, lair, a room theme; user: "The room should be called science"): a **SCIENCE** neon sign (acid
  green, like POOL / FILM; "LAB" stays the lab theme's), the green specimen pool under the yellow gantry and its cage,
  a hazard sign by the pool, two **specimen tanks** (standing vats, decor), a **pipe run**, a **lab bench**, a doomsday
  **console** and a specimen shelf in bigger rooms; priced specimen vat / doomsday console; lab tile floor, green light.
  The lab's models are reused (`pool_props.gd`: ladder, gantry, ripple, bench, pipes, hazard sign; `PropModels`: vat,
  console).

**Dev flag:** `--to-pool [pool|specimen|moat]` puts the crew at the floor's first pool (the player wading in it, the next
seat at the rim, the third wading by the far rim; at a moat all three wade in the channel nearest the camera; the allies
hold their spots), `--focus pool_corner` looks at its corner farthest from the camera (liner, coping and deck all show
there), `--focus island_corner` at a moat island's corner nearest the camera. Seeds for `--spells heal,corn --to-pool` (no
`--contract`): `--seed 4` (indoor pool, floor 1), `--seed 1` (science, floor 1), `--seed 8` / `--seed 11` (moat rings,
floor 1).

**Tests:** `tests/test_pools.gd` (generated floors: determinism and checksum, convex outlines on the midpoint grid,
clearances, dry props / decor / notes / mail / monsters, gantry legs; walking in and out over every edge; the slowdown;
wet while wading and 15 s after; a fire put out; owner-only soaking; an ally, a grunt and an employee crossing the pool),
`tests/test_net_pools.gd` (its seed's first pool is now a moat ring, so it runs in a moat's channel), and additions to
`test_wall_mesh.gd` and `test_room_themes.gd`.

### Moat [built, 2026-10-18]
**Approach: one annulus, not convex pieces.** The ring could have been six convex trapezoids joined along radial seams,
but every seam would need its coping, liner and foam suppressed and the copings re-mitred where the pieces meet. Instead
`PoolGeo` builds one body of water between a convex **outline** and a convex **island** (`hole` in the record):
- The outline is a lattice hexagon (`MOAT_SIDES`: regular sides 2-6 and elongated ones such as 3,2,2,3,2,2, all six
  rotations), every corner 120 degrees on a hex centre. The island is the same hexagon offset **one row** (`ROW`, 1.5)
  inward, whose corners land on hex centres again (a 120-degree corner moves one lattice step along its bisector), so the
  channel is one row wide and both rims run on midpoint lines.
- A kite is pool exactly when its triangle lies inside the outline and outside the island (`PoolGeo.kite_mask`). The
  water's corners are 120 degrees outside and 240 round the island, never 60, so there are no slivers (the reason
  arbitrary non-convex shapes are refused) and `HexMapView` needed nothing new but a third look (stone blocks in a running
  bond, `POOL_LOOK_INDEX`): its per-cell inset drawing already handles 4-kite pool runs (the island's corners).
- `PoolView`: the water is the band between the two polygons, the coping runs round the outside as before and round the
  island turned inside out (over the water outside the island's rim, `COPING_W` onto the island, nosing facing out), both
  mitred on the bisectors (`coping_edges`), and the foam follows both rims. Murky teal water, stone coping.
- **Fins:** two `shark_fin` models (with a `DecorAnim` path mode) swim the channel's middle line (`PoolGeo.channel`) half
  a lap apart at the water surface; decoration until the shark is built.
- **Bridge:** a bridge over wading water would be walked through, not over, so it is decoration: `moat_bridge`, a plank
  gangway pulled back onto the deck on the door side, pointing at the water, with the fin hazard sign beside it. The old
  `moat_water` decal (and its ring of placement bodies) is gone.
- **Placement:** the same rules as a pool (water cells clear of doors / corridors, start, exit, elevator, van, gates and
  employees; dry deck round the outside and round the island's rim; at most 30 % of the room; near its centre; its own
  generator, spawn data, in the floor checksum). The island's middle may hold anything (a crate there leaves it reachable
  from all round). The moat theme is now `needs_center` (not dealt to a gate room when another room will do), since a ring
  can only circle a hellgate's clear zone in a very big room.
- **Fallback:** a ring needs a clear area about 7-11 cells across; where none fits (crates, platforms or doors in the way)
  the room gets a **shark pool**, a convex pool of the indoor pool's shapes in the moat's look with its fins circling half
  a row inside the rim. Over the `test_pools` floors: 24 rings and 9 shark pools in 44 moat rooms; the other 11
  (mostly rooms with a hellgate in the middle) get no water, like a crowded indoor pool room. **Decided** (user, 2026-10-18):
  keep the shark-pool fallback; the ring does not circle a hellgate.
- Tests: `test_pools.gd` (the ring is one connected, closed ring round a dry island; one body of water: the channel is
  wet all the way round at one surface and every rim line lies on the outline or the island; a step in and out over every
  outer and island edge; A* and a walking body reach the island and leave it, slowed and soaked; the fins stay in the
  water), `test_wall_mesh.gd` (the island's coping: winding, no overlap, band area, bisector seams; the water covers
  exactly the ring), `test_room_themes.gd` (the bridge, the sign, no decal; a path fin follows its loop).

**Open:**
- Deep water and swimming (option B's deep end), tanks (C), the flooded floor (D).
- Whether the indoor pool should keep its decorative ladder.
- Water-only monsters: the shark below.

## Shark (planned, not built)

**Superseded by `sharks.md`** (2026-10-19): the three variants, the moat measured against the shark, the property
question, the networking and the room layouts. The plan below is kept as the starting point it was.

An environmental hazard that lives in a pool. The pools are wading depth, so it is a **land shark in a paddling pool**:
a fin cruising the water, its back breaking the surface.
- **Where:** one shark in some indoor pools (bunker), some specimen pools (science, "the specimen") and the moats (the
  fins are already there), never in a
  pool smaller than 5 basin cells. 30 % of pool rooms from floor 2 on, rolled by the host with `GameWorld.rng`.
- **Shape:** a **host-owned actor** like a monster (`net_fields()`, its state streamed by `NetWorld`, hits through
  `Combat`, shoves and damage through the verbs), confined to its pool: its moves are clipped to the water
  (`HexMap.water_at`), its nav nodes are the pool's cells. It never leaves the water and cannot be shoved out of it (a
  shove stops at the rim).
- **Reads:** a fin and a dark shape circling at 1.5 u/s; it tracks the nearest actor in the water or within 1.2 of the
  rim. **Telegraph** 0.6 s (the fin stops, the water bulges), then a **lunge** 2.5 units: 18 damage and a 1.5 shove
  toward the middle of the pool (a hero at the rim gets pulled in). 3 s cooldown. Monsters wading through are fair game
  too (shove a grunt in and it eats it).
- **Killed or driven off:** driven off, not killed (it is set dressing with teeth). 120 HP of "nerve": at 0 it **sinks**
  for 20 s (gone from the surface, harmless) and comes back at full nerve. No loot, no bounty.
- **Spells:** damp: nothing (it is wet). Fireball: nothing (it is under water). **Corn:** it takes the bait and turns to
  the kernels for 4 s (a distraction). **Tentacles:** grab it and hold it 2 s (no shove). **Vines:** cannot root it (no
  ground). **Teeth / strike:** normal damage to its nerve. **Heal:** nothing. **Coffee:** it is faster (a joke risk).
- **Tuning ideas:** one shark per pool; at most one hit per hero per lunge; no lunge at a downed hero (no consequence
  for going down in water stays true); the fin glows faintly so it reads at size 24; a "fin" hazard sign by the pool
  (the lab's) warns of it.

## The study

**The idea (user):** rethink the swimming pool. Could we have real pool tiles, with water as a kind of floor cell
"for sharks and things"? Could the midpoint-wall machinery make a **pool inset**, a sunken basin whose rim follows the
hex midpoint lines like a wall cut downward? It should give us:
- rules for where you get in and out;
- water that puts out a burning hero;
- places for sharks and other water monsters;
- a **mad science** theme for some zones.

## What existed before the build

All the water today is **flat decor**: `blocks: false`, so you walk straight across it.
- **Indoor pool** (bunker theme `pool`, `RoomThemeDefs`): `ThemeVignettes.pool` puts a `pool_basin` decal at the room's
  focal point and loungers round it. The decal is an oval stone rim, glowing water, lane lines and a ladder, 0.2 high
  (`DecorModels._pool_basin`). The floor is `F_POOL_TILE`.
- **Shark moat** (lair theme `moat`): `ThemeVignettes.moat` lays a `moat_water` ring of boxes round the focal point, with
  a plank bridge and patrolling `shark_fin` decor (`DecorAnim` "fin").
- **Lab / vat room** (lair theme `lab`): `specimen_vat` priced props and `specimen_shelf` decor. `shark_tank` is a small
  priced prop with a shark in it.

`environment.md` says "the pool IS a pit, so shoving monsters in is the point". That was never built.

## Where the options live

- `scripts/art/lowpoly/pool_lab.gd` + `scenes/pool_lab.tscn` (removed in 04c4eb4, see docs/history/removed-code.md;
  `git checkout 04c4eb4^ -- scripts/art/lowpoly/pool_lab.gd scenes/pool_lab.tscn` to run it again): the lab. It has four variants on the real terrain:
  `HexMapView` with midpoint walls from `HexMap.cut_walls()`, `FloorMaterials` and `DungeonLook` lighting. The crew
  stands in each one for scale.
- `scripts/art/lowpoly/props/pool_props.gd`: lab-only models, preloaded with no `class_name`:
  - water monsters: shark, eel, jellyfish, the escaped specimen;
  - pool furniture: ladder, stair rail, catwalk, gantry with a cage, lab bench, pipe run, valve wheel, hazard sign,
    drain grate, lifebuoy;
  - effects: ripple, steam, stand-in flames.

```
godot --path . --resolution 1920x1080 -- --scene res://scenes/pool_lab.tscn --variant basin|inset|lab|flooded --shot <png>
```

The `basin` and `inset` variants print **probes**. A probe is what today's `HexMap.movement_check` says about stepping
across the water's edge. The rules sections below quote them.

## Screenshots

The shots are in the session scratchpad, `...\scratchpad\pool\`. There are three views per variant, all from the game
camera (ortho, yaw 45, pitch -56):

| file | camera |
|---|---|
| `<variant>.png` | size 24, the game's default zoom: the whole room |
| `<variant>_close.png` | size 9 on the water's main moment: the swimmer, the shark, the catwalk |
| `<variant>_edge.png` | size 9 on the way in and out: steps, ladder, the shallow edge |

`contact_sheet.png` has all twelve shots.

| variant | option | what is in the shot |
|---|---|---|
| `basin` | A, the hex-cell basin | <ul><li>A bunker pool with a shallow end and a deep end.</li><li>Stairs cell steps and a ladder.</li><li>Jellyfish glowing in the deep end.</li><li>Gasket wading, Wick treading water, Rebar on the deck.</li></ul> |
| `inset` | B, the midpoint inset | <ul><li>A bunker lap pool with a coping and a tiled liner.</li><li>Straight inset steps on the far side and a ladder.</li><li>A **shark** with its fin cutting the surface, right next to Wick at the ladder.</li><li>Gasket wading on the steps, Rebar on the deck.</li></ul> |
| `lab` | C + B in a mad-science room | <ul><li>A raised **glass shark tank** on midpoint lines, with a catwalk over it and a ladder up.</li><li>A green **specimen pool** (inset) under a gantry with a dangling cage, and the escaped specimen hauling itself out.</li><li>Vats, a bench, the console, shelves, pipes and a LAB neon sign.</li><li>Wick on the catwalk, Gasket at the ladder, Rebar at the pool.</li></ul> |
| `flooded` | D, the flooded floor | <ul><li>A plant room whose low cells are flooded shin-deep.</li><li>Two eels.</li><li>Rebar on fire, running for the water; Gasket just doused, with steam rising; Wick wading.</li></ul> |

## Rules every option shares (proposal)

**Water is terrain.**
- A water cell is a floor cell with a **water surface** above its floor. The surface is per cell or per basin record.
- It is spawn data from the seed, like the cells, `mat_id`, `solids` and the elevator. It goes in the floor checksum.
- Depth (surface minus floor) decides what you do there:
  - **wading**: less than about 1 unit (2 levels). Slow (x0.8), and you are wet.
  - **deep**: more. You swim.

**In and out.**
- **You can always get in.** A step, a fall or a shove off any edge into water is allowed. Water ignores `DROP_LEVELS`.
- **You get out only at an exit:**
  - steps (stairs cells or stepped kites);
  - a ladder, which is a slow climb like `CLIMB`;
  - an edge no more than 1 level above the surface (a step up).
- So the deep edge is a one-way door, the way a 3-level drop is in `exploration.md`.
- Today's rules already give half of this. Probes on option A:

  | hop | today |
  |---|---|
  | deck to deep (4 levels down) | `BLOCKED` |
  | deep to deck | `BLOCKED` |
  | shallow floor (-2) to deck | `CLIMB` |
  | deck to shallow | `OK` |

  Only the "water cushions the fall" exception is new.

**Swimming (proposal).**
- Speed x0.6.
- You can **cast**: the voice is the input, and the north star says no slip ends a run.
- You **can't use your weapon** (bow, hammer, bowl).
- Shoves on you go half as far (water drag).
- No drowning damage. Deep water is a slow, weaponless place with things in it.
- The tension comes from what lives there, not from a timer.

**Fire and damp.**
- Entering any water calls `Wet.douse(actor, 15)`, which is `Burning.soak`. It puts the fire out at once and blocks
  ignition while you are in the water and for 15 s after.
- A fireball blast on a swimmer fizzles. That already works for soaked actors.
- Wading cells count as a permanent wet floor for `Damp.slide_mult`, so a shove that starts in the shallows slides
  further.
- So the pool is a **refuge from fire** and a **hazard from monsters**, which is the point.

**Monsters.**
- Land monsters do not path into water. Water cells are not nodes for them, or carry a high cost.
- A land monster shoved into deep water **flounders**: slow, can't attack, climbs out at an exit. The other choice is
  that it sinks and dies, the pit rule in `environment.md` (open question 5). The brute could walk out along the bottom.
- Water monsters are confined to their water body: their nav nodes are its cells.

**Networking (the four shapes).**

| piece | shape | notes |
|---|---|---|
| water cells, basin, steps, ladders | terrain (spawn data) | from the seed on every machine; checksummed. No new shape. |
| swimming / wading / soaked | owner-applied status | the hero's owner (the host for monsters and employees) tests its own actor's position against the shared map every physics frame and calls `Wet.douse`. A puppet's swim pose is `LOCAL`: every machine can compute it from the streamed position and the map, so no new field. |
| water monsters | owned actor (host) | like every monster; `net_fields()`; damage and grabs through verbs and `Combat`. A shark's "pull in" is a `shove` toward the water, applied by the victim's owner. |
| tank glass that breaks, drain or flood valves, the gantry cage | host-arbitrated world object | a player requests, the host grants with a reliable event. The water level changing is then a **scheduled effect**: every machine computes the level from (start time, rate). |
| ripples, foam, caustics, steam, fin wake | cosmetic | local, `fx_rng`. |

Nothing in the lab declares gameplay state, and `test_net_contract` passes. A real build adds a `water` field to
`HexMap.Cell` (`SPAWN`, through `HexMap.net_fields`) and any swim state the `Hero` needs. That state is `LOCAL` if it
is derived from position. If the `Hero` gains an `OWNER` var, it needs a carrier (`NetCodec.HERO_FIELDS`).

## The options

### A. Hex-cell basin (`basin*.png`)

Pool cells are ordinary **floor cells at negative levels**: shallow at -2 (0.7 deep under a surface at -0.3) and deep
at -4 (1.7 deep). A water surface sits over them.
- **Steps:** an existing `STAIRS` cell.
- **Ladder:** a marker on one hex edge.

**Look.**
- `HexMapView` draws all of it **with no change**: slate cliff sides with level bands, pool-tile tops and wooden stair
  planks.
- The lab adds only the water mesh, one hex fan per cell, with a toon water shader.
- The rim is the **hex zigzag**, and the walls are dark slate columns. It reads as "a flooded pit" more than "a swimming
  pool".
- Good for rough water: sewers, caves, a lair shark pit, a moat.

**Movement.** Covered by the shared rules. The stairs and the climb rule already work; the probes above show it.

**Fire, damp, shoves.** As in the shared rules. Every pool edge is a shove target.

**Water monsters.** All of them; the deep end holds the shark and the jellyfish.

**Cost: lowest.**
- Generation: like pits. Keep 2 cells from walls (`exploration.md`), with a stairs cell and a ladder edge.
- Collision: none new; it is heights.
- Pathing: water cells are excluded or costed for land AI.
- View: one water mesh per basin.

**Pros:**
- No mesh work.
- Uses the stairs and level rules as they are.
- Any shape of cells works.

**Cons:**
- The jagged rim and slate walls do not say "pool".
- The steps are a full wooden cell.

### B. Midpoint inset (`inset*.png`) — recommended

The basin is a cluster of cells that `cut_walls()` treats like **a wall below the floor**. The ring of cells round it is
cut along midpoint lines. Their pool side is a sunken kite at the basin depth, so the rim is a straight line from hex
centre to hex centre, exactly like the walls and the elevator's notch.

**It works in data today.**
- The lab makes the basin cells `WALL` at level -3, and `cut_walls()` produces the right masks.
- `ground_level` on the pool side is -3, and the cut cells are half cells.
- Probe: deck to pool, both ways, is `BLOCKED` (`wall_at`). The rim is already a hard edge in `clip_move` and
  `segments_near`.

**Look.**
- A clean outline at 60 and 120 degrees: one row of cells makes a 10.4 x 3 lap pool; two offset rows (the lab) make one
  about 4.5 wide.
- The lab adds:
  - a tiled liner with a stone coping;
  - a foam line;
  - **steps whose treads are whole triangles of hex centres**, so every tread edge is a midpoint line;
  - a ladder over the coping.
- It reads instantly as a pool at size 24, and the shark under the surface reads at size 9.

**Movement.**
- As in the shared rules: you can't walk in, you can fall or be shoved in anywhere, and you get out at the steps or the
  ladder.
- The rim needs one new flag: it is a **ledge** that blocks a walking hero but lets a shove, a knock-back or a step off
  "into the water" through. The ladder and step segments are open.
- Pathing round the pool already works: the cut cells are half cells, so they are not path nodes.

**Fire, damp, shoves.**
- As in the shared rules.
- The straight rim makes shoves readable: the aim line shows where the monster goes in.

**Water monsters.** All of them. This is the shark's home (`inset_close.png`).

**Cost: medium.**
- **Data:** a basin tile (`Tile.WATER`, or `WALL` with a level below its ring). `cut_walls()` takes `wall_top` from it as
  now. A cut kite takes the depth of the shallowest basin cell in its triangle, which gives the steps.
- **View:** today `HexMapView` draws the cut cells' floor halves flush to the line (good). But it draws their wall part
  as a cap at the basin depth, and the wall face **inverted** (its top is below its bottom). The lab hides that under its
  own liner. A real build has `HexMapView` draw an "inset" wall part instead:
  - a liner face toward the pool, in a pool material;
  - a basin floor;
  - no seam glow under the water.
  That is about 150 lines, plus a mesh test like `test_wall_mesh`.
- **Generation:**
  - a convex cluster (1-2 rows), at least 2 cells from the room's walls;
  - it must stay convex so `_trim_slivers` adds no spikes: a spike would take a 3-level wall top inside the pool;
  - like the elevator's free placement, it claims the room's middle.
- **Collision:** the ledge flag on rim segments.

**Pros:**
- It looks like a pool.
- It uses the same geometry family as the walls and the elevator.
- Its exits are explicit: steps and ladder.

**Cons:**
- Mesh work in `HexMapView`.
- Only convex 60/120-degree shapes.
- At the game camera the near rim hides a strip about 1 unit wide of the near side (depth x tan 34 degrees for a 1.5-deep
  basin). The lab puts the steps on the far side; generation should too.

### C. Raised tank (`lab*.png`)

A tank stands on the floor: glass walls on the **midpoint outline of a cluster**, posts on the hex centres and a
steel/hazard frame, with water inside up to 2.0.
- In data it is `HexMap.solids` (one convex polygon), exactly like the elevator's glass shaft. The cells under it are
  `no_stand`.
- Line of sight passes through the glass. Projectiles do too, unless the glass should stop them.

**Look.** Superb for mad science. The shark reads through the glass at size 24 and is the hero of the close shot.

**Movement.**
- You don't walk in.
- A catwalk over or beside the tank, reached by a ladder, is the way to look down at it.
- A heightfield has one level per cell, so a walkway **over** water can't share cells with it. Two ways round that:
  - the catwalk runs beside the tank (raised cells along its back, a climb chain);
  - the catwalk cells split the tank into two halves.
- Falling off the catwalk drops you into the tank. You swim there (B's rules) and climb out at a ladder inside.

**Fire, damp, shoves.**
- Shoving a monster off the catwalk into the tank works.
- If the tank is **breakable**, the glass is a host object. Smashing it floods the cells round it for about 20 s
  (option D as a scheduled effect) and releases the shark, flopping and biting on land, or the specimen.

**Water monsters.** The shark and specimens. Behind glass they are props until released.

**Cost: low** if it is static: the solids exist and the mesh is glass, a frame and a water box. **Medium** if it is
breakable (host event, flood effect).

**Pros:**
- Strong silhouette.
- No terrain or mesh changes.
- Reuses the elevator's solids.

**Cons:** not a pool you play in, unless you fall in.

### D. Flooded floor (`flooded*.png`)

Low cells (1 level down) carry a thin water film. You **wade only** (0.3 deep here). The hex grid stays visible through
the water.

**Movement.**
- Normal step rules: one level down and up is a walk.
- Wading is slow (x0.8).

**Fire, damp, shoves.**
- Wading soaks you (`Wet.douse`). Rebar runs for the water in the shot.
- Shoves slide further: it is a permanent `Damp` puddle.

**Water monsters.** Eels (shock the whole connected puddle), leeches, jellyfish swarms. No sharks: too shallow.

**Cost: lowest.**
- A water level on some low cells and one water mesh.
- Generation can flood any room's low ground, or a pump room.

**Pros:**
- Cheap.
- Gives every fire fight a "get to the water" move.
- It is also what a broken tank or a drained pool leaves behind.

**Cons:** not deep, so no swimming and no shark.

## Recommendation

**Build B (the midpoint inset) for real pools, with D as its cheap shallow companion and C as mad-science dressing.**
B is the user's idea and it reads as a pool. The rim is a wall line, so it belongs to the same family as the walls and
the elevator. The data already falls out of `cut_walls()`.

Suggested order:
1. **Water rules + D.** Add a water surface per cell, the wading and soaked statuses, `Wet.douse` on entry, wet-floor
   slides and land-AI avoidance. This proves the networking (owner-applied status) cheaply. Flooded plant rooms and the
   pool's shallow end use it.
2. **B.** Add the basin tile, the inset drawing in `HexMapView` with a mesh test, steps and ladders as exits, the ledge
   flag on the rim, and deep water and swimming. The indoor-pool and moat themes switch from decals to real basins.
3. **Water monsters**: the shark first (it is the hook), then eels.
4. **C** in a mad-science lab: static tanks first, breakable glass and flooding later.

Keep A in reserve for rough water (sewers, caves) if those arrive. It needs no mesh work.

## Mad science zone (sketch)

A theme set for the lair, or a third site type (open question 9). Lab tile floors, stone or steel walls, green and
cyan accent lights, hazard yellow.

| room | contains | pool option |
|---|---|---|
| **Specimen pool** | a green glowing inset under a gantry with a dangling cage, a steel coping, a hose reel, specimen shelves | B |
| **Shark tank** | a raised glass tank with a catwalk and ladder, a "fin" hazard sign, a feeding bucket, a control desk | C (the catwalk is a climb route) |
| **Vat hall** | rows of `specimen_vat`; a cracked one leaks green goo onto flooded cells (slow, maybe poison) | D |
| **Pump room** | pipe runs, valve wheels, a flooded floor and eels; turning a valve drains or floods the next room's pool | D (the valve is a host object; the level change is a scheduled effect) |
| **Control room** | `doomsday_console`, a lever bank (the lever wall in `environment.md`), monitors showing the tanks | none |

**Props:**
- **Exist:** `specimen_vat`, `specimen_shelf`, `doomsday_console`, `shark_tank` (small), the neon sign ("LAB").
- **Lab-built here** (`pool_props.gd`): shark, eel, jellyfish, specimen, ladder, stair rail, catwalk, gantry with a
  cage, lab bench, pipe run, valve wheel, fin hazard sign, drain grate, lifebuoy, ripple, steam.
- **Still to make:**
  - tank glass and frame as a prop built from an outline (the lab builds it inline);
  - a cracked-glass variant;
  - a gurney, a tesla coil, a rotating warning light, a hose reel, a lever bank, a feeding bucket.

**Water monsters** (all host-owned actors, confined to their water body except the specimen):
- **Shark:** circles deep water with its fin up. It lunges at swimmers, and at heroes on the rim within 1 cell (a bite,
  plus a shove toward the water). It never leaves the water. Shove grunts in and it eats them.
- **Electric eel:** lives in shallow and flooded water. Every few seconds it glows (the telegraph), then shocks everyone
  standing in its connected water. Wading heroes must get out.
- **Jellyfish swarm:** a few glowing domes drifting with the current. Contact stings (a small damage over time). They are
  shoved like anything else, and corn pops them.
- **Escaped specimen:** an amphibious purple blob, the infestation colour. It crawls out of the specimen pool and heals
  while in green water. It is the only one that follows you onto land.
- **Pool tentacles** (the bunker pool's infestation layer, "tentacle-ish shapes below"): arms rise at the rim and drag
  heroes in (a shove into the water), then sink.
- **Piranha school** (lair moat): fast chip damage to anything swimming. It makes a moat a real "don't fall in".

## Lab findings

- The midpoint inset needs no new data to try. Make the basin cells `WALL` at a negative level and `cut_walls()` cuts
  the ring along midpoint lines with the pool depth as the wall top. `HexMapView` draws the inverted face and the cap,
  which the lab covers with its own liner and floor.
- Steps on the kite grid look jagged (`kite` treads). Steps made of **whole triangles of hex centres** are straight,
  because every tread edge is a midpoint line. The lab uses those.
- At the default zoom a 1.5-deep inset hides about 1 unit of its near side under the rim. Put steps, ladders and
  monsters' favourite spots on the far side or the ends.
- Water needs to be **translucent** (alpha about 0.55-0.65) so that bodies under it read: the shark, a swimmer's legs,
  the steps. A light under the surface blows out at this alpha; the lab has none in the pools.
- A swimmer reads best with the head and shoulders out (about 38% of the model's height above the surface), plus a
  ripple ring.

## Open questions for the user

1. **Can heroes swim at all**, or only wade, with deep water as a no-go hazard?
2. **Does deep water hurt?** The proposal says no drowning: it is slow, weaponless and full of monsters.
3. **Casting while swimming:** yes (the proposal)? Weapons no?
4. **Hazard or refuge?** The proposal is both: a refuge from fire and from the brute, a hazard from sharks.
5. **Land monsters shoved into deep water:** do they die (the pit rule), flounder and climb out, or (the brute) walk out
   along the bottom?
6. **A hero downed in water:** float to the nearest exit, or revive from the rim?
7. Should the **indoor pool and shark moat themes** become real basins? That gives them a gameplay footprint and they
   keep needing the room's middle.
8. **Water level as a mechanic** (valves that drain or flood) in mad-science rooms?
9. **Mad science:** a third site type, or a set of lair themes?
10. **Tank glass:** decorative, or breakable (flood plus a released shark)?
