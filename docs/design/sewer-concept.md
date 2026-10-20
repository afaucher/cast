# Sewers and lava caves (concept)

Status: **concept only** (2026-10-20). Nothing here is built into the game: no change to the site builder, DungeonGen,
`game.gd`, the monsters or the net layer. Two lab scenes fake both environments on the game's real terrain drawing.

**The user's words:**
- 2026-10-19: "For water monsters - I am wondering if a sewer theme makes sense for some rooms. Like they would be
  connected and the hallways between them would be flooded. Do not build this yet. What might this look like?"
- 2026-10-20: "Lava is the other environment to consider next to the sewer."
- 2026-10-20: "The lava layout should be different then pools. It would be like a lava cave with varied wall heights,
  islands, and a hex bridge (small height variance between hexes to look like rougher rock)."
- 2026-10-20: "The fog in a big room can be managed with multiple adjacent rooms."

**Builds on:**
- `pool-options.md`: water as terrain, wading depth, option B's inset as built, the moat ring, option A ("rough water:
  sewers, caves"), option D (the flooded floor).
- `sharks.md`: the host-owned actor confined to a water polygon, its steering, and the two-row rule.
- `exploration.md`: fog look A, office doors, and rooms vs halls as spaces.
- `environment.md` and the room themes.
- `combat-proposals.md` §4.6 (corruption pools).

Part 1 is the sewer, part 2 the lava cave, and part 3 compares them and recommends an order.

---

# Part 1: the sewer

## Summary

A **sewer cluster** is 2-4 connected rooms on one floor whose halls are flooded. It is not a site and not a whole floor.

- The rooms are ordinary DungeonGen rooms with sewer themes:
  - a **cistern**: a sump in the middle and walkways round it;
  - an **outfall room**: a channel across it, fed by a big pipe;
  - a **junction**: three channels meet over a drain.
- The halls between them are under **wading-depth water**, the same 0.36 as the pools. A **narrow** hall is flooded wall
  to wall. A **wide** hall keeps a 1.5 ledge walkway along one wall over a 3.0 channel.
- All water uses the rules that exist today: 0.75x speed, soaked while in it and for 15 s after, a fire goes out, and
  anyone can step in or out anywhere.
- The new monster is a **sewer gator**, the sewer's shark. It is a SharkSteer actor tuned shorter and bendier so it can
  turn round in the 3.0 water a flooded hall gives it.

## Fit: sites, clients, fiction

| Client (`ClientArchetype`) | Site | The sewer is... | Tone |
|---|---|---|---|
| Prepper billionaire | bunker | **Sublevel water reclamation**: the bunker's grey-water plant and storm drains (concrete look) | "Do not drink from the reclamation channel. It is reclaimed." |
| Supervillain | lair (volcano) | **The lair's sewer**: the moat's overflow, where the gator lives (brick look) | the warning line already says "one (1) irreplaceable shark"; a gator is the obvious sequel |
| Tech founder | lair (data center) | **Cooling culverts**: glowing coolant and steam (the toxic look as coolant) | "Liquid cooling (experimental)" |
| Wellness guru | bunker (basement retreat) | **The spring-fed grotto**: the "cold plunge" origin, gone feral | a sewer that calls itself a grotto |
| Influencer | bunker (studio) | rarely: a flooded basement | low fit |

**Proposal:**
- Make it a **room cluster**, not a theme every room can roll. On floors 2-3, about one floor in three gets a cluster of
  2-4 rooms linked by tree links.
- Each room in the cluster rolls one of three sewer room themes: `cistern`, `outfall`, `junction`.
- Every hall between two cluster rooms is flooded.
- In the fiction it is the **service level** under the client's property. The dispatch line could be: "The crew is
  advised the lower level is wet."

The existing pool themes stay as they are. The moat and the science room are rooms with a pool; a sewer is a network.

## Layout

### Rooms joined by flooded halls (`rooms*.png`, `junction*.png`, `fog*.png`)

- **Cistern** (`rooms.png`, left): a hexagonal sump (wet cells within 2 of the centre) with walkway all round, and a
  one-row channel running from the sump to each doorway.
  - **One wet row is 3.0 wide.** The rims run through the centres of the next rows over. That is exactly the width of a
    narrow hall between its wall lines.
  - So the room's channel runs straight into the hall with no step and no jog: the channel's rims continue as the hall's
    walls.
- **Outfall room** (`rooms.png`, right): the channel crosses the room to a big pipe pouring in from the far wall. A
  **grated bridge** crosses the channel, and there is dry floor on both sides for the fight. It has two lobes, like
  DungeonGen's lobed rooms.
- **Junction** (`junction.png`): three flooded narrow halls meet over a drain. There is a **drain grate** in a small
  sump, three channels to the doors, and three dry walkway wedges between them, joined by a grate bridge. It also has an
  outfall pipe, pipe runs, and a ladder up to a manhole with a light shaft.
- **Water share:** a cistern is about 35-45 % water and a junction about 30 %. The pools cap water at 30 %
  (`PoolGeo.MAX_SHARE`). A sewer room needs a higher cap, about 45 %, and must keep a dry walkway that connects every
  doorway.

### Flooding the halls with today's widths

| Hall | Between the walls | Flooded as | Water | Dry | Shark / gator rule |
|---|---|---|---|---|---|
| **Narrow** (loops, chokepoint, climb shortcut) | 3.0 | wall to wall | 3.0 (two rows) | none | two rows: a gator turns round (see below); a 2.4 shark only circles |
| **Wide** (tree links) | 4.5 | one side: route row + near cut row (`hall.png`) | 3.0 | a 1.5 ledge on the far side | as above |
| **Wide**, fully | 4.5 | wall to wall | 4.5 (three rows) | none | roomy: lunges anywhere, like the lagoon |
| **Sewer main** (a new width, `main.png`) | 6.0 | the middle row | 3.0 | a 1.5 ledge each side | as above |

How it works in cells (the lab does exactly this):
- **A wet full cell** is a basin cell: pool floor everywhere, one level down.
- **A dry full cell next to water** is a ring cell. Its kites toward the water are pool floor, using PoolGeo's rule
  (neighbour d wet: kites d-1 and d). So every rim runs on a midpoint line, the liner draws, and the kerb sits on it.
- **A wet cut cell** (against a wall) is sunk, so its floor half goes under water and the water reaches the wall.

**The climb shortcut is never flooded.** Its +-2 climb is a step in the floor, and water needs one level along its run.
The same goes for any hall with terraces or stairs; see "Generator implications".

### Ledges, grates, sluices, pipes, flow

- **Ledge vs fully flooded.**
  - A **ledge** gives a dry route, keeps an ally line, and gives the gator a target (it lunges at the ledge, like the
    shark's rim bite).
  - A **fully flooded** hall is the commitment: everyone wades, at 0.75x and soaked.
  - Mix them: tree links (wide) get a ledge, and loops (narrow) are fully flooded, so the short way round is the wet way.
- **Put the ledge on the far side.** The camera looks from +X+Z. A near-side ledge is half hidden by the near wall
  (`hall.png`: the near wall's cap covers about 1.3 of the hall next to it). Water next to the near wall loses nothing,
  because you see into water anyway.
- **Grates:**
  - a drain grate in a sump (decor, under the water);
  - grate bridges across channels (decor, like the moat's bridge: you walk through wading water, not over it);
  - iron bars across a culvert mouth (decor that blocks a dead end).
- **Sluice gates:**
  - In a doorway (`rooms_close.png`) a sluice is the sewer's **door**. Its posts sit on the jambs and the plate is raised
    so the water runs under it.
  - In data it is the office door (shut = solid, blocks sight and sound; walk into it to open, E to shut), drawn as a
    sluice. The water keeps flowing under a shut sluice; that is cosmetic.
- **Pipes:** outfalls pour into a channel's head; pipe runs and valves go on far walls.
  - A valve wheel could later be the pump-room mechanic in `pool-options.md` (drain or flood). Not proposed now.
- **Flow:**
  - Each body of water has a flow direction per segment, from outfalls toward the drains (the cistern's sump, a junction's
    grate).
  - Flow is **cosmetic**: the foam streaks, floating scum, corn kernels and the duck drift with it. It does not push
    bodies, because a current that moves actors would be a new owner-applied force.

### Doors and fog spaces

- A flooded hall is a **hall** space like any corridor run (`Doorways`).
- The lab feeds its hand-made sewer straight to `RoomFog` and `FogView` with no change (`fog.png`, `fog_hall.png`):
  - from the cistern: the cistern and the hall in view, the outfall room next, the room beyond unknown;
  - walking into the hall: the outfall room in view (two hops), the next hall and room next.
- **Doors:** today every narrow doorway gets an office door. In a sewer cluster it becomes a **sluice gate** with the same
  behaviour, and wide halls stay open, as decided. A brute smashing a sluice is billed like a door.

### Lines of sight down long wet tunnels

- Fog is per space, so standing in a 20-cell flooded hall shows all of it. That suits a sewer: you see the gator's wake
  far down the tunnel.
- Looking into a hall from a room follows the doorway rule (`DOOR_SIGHT` 14, line of sight, two hops). A long straight
  sewer main lets you see the next room from the far end, so sewers reward scouting down tunnels.
- Water and ledges block nothing (they are one level). Grate bridges and sluice frames are decor and do not block sight.

## Movement and spells

- **Wading a long hall** costs 0.75x for its whole length. A 10-cell narrow hall (17.3) takes about 5.1 s instead of 3.8 s.
  You come out soaked, so you can't ignite for 15 s, and a fireball fizzles on you.
- **Shortcuts:**
  - a ledge is the dry long way and the channel the wet short way;
  - a fully flooded loop is the wet shortcut round a dry tree link;
  - a grate bridge is decor, not a dry crossing.
- **Spells:**
  - **Damp:** nothing new on waders (already soaked). It still makes puddles on the walkways, so shoves slide further
    there.
  - **Fireball:** fizzles on soaked waders, as now. A blast over water makes a puff of steam (cosmetic).
  - **Corn:** kernels float and drift downstream (cosmetic). They are **chum** for the gator for 4 s, as for the shark.
  - **Tentacles, bowl, shoves:** shoving a monster off a ledge into the channel slows and soaks it and puts it in the
    gator's reach. The flooded floor counts as a permanent wet floor for `Damp.slide_mult`, as `pool-options.md`
    proposed.
  - **Electric eel + water:** an eel's shock reaches everyone in its **connected** body of water. It is the "live wires +
    water" hazard (`combat-proposals.md` §4.7) with a living source.

## Water monsters

All are host-owned actors (`Shark`'s shape: `net_fields()`, streamed by `NetWorld`, hits through `Combat`, moves clipped to
their water). Their numbers follow `sharks.md`'s style.

### The width problem, measured

- The shark steers its centre line `CLEAR` = half its width + 0.06 off every rim. Turning round needs a lane of
  2 x `R_TURN`.
- A 2.4 shark (`R_TURN` 1.5, `CLEAR` 0.42) in 3.0 water has a lane of 2.16 against the 3.0 it needs, so it can't turn
  round.
- A gator is built to fit:
  - about 3.0 long at the lab scale, half width 0.42 (`CLEAR` 0.48);
  - **R_TURN 1.0**: a crocodile curls its body; the bending chain is SharkBody's follow-the-leader, so it reads as a curl.
- **3.0 water:** lane 3.0 - 0.96 = 2.04, and a U-turn needs 2.0. It turns round in a flooded narrow hall, in a cistern
  channel, and in the 3.0 channel beside a ledge. `gator_close.png` shows it curled 70 degrees mid-turn in that channel.
- **4.5 water:** roomy.
- **1.5 water** (a moat ring, a gutter): no turn. Gators never go in one-row water; eels do.

| Monster | Water | Steering | Attack | Notes |
|---|---|---|---|---|
| **Sewer gator** | 3.0+ bodies (two rows) | SharkSteer on the body's distance field; patrols the channel's centre line, turns round at ends and junctions | **Bite** from the water at waders and at anyone within 1.2 of a rim (the shark's lunge, 0.6 s wind-up, 18, shove away from the water). **Death roll** (new): it holds a wader 1.2 s (a `daze`-like hold, no damage over time) | Only its eyes, nostrils and scutes break the surface, so it needs the eye glow and a V-wake at size 24 (`gator.png`). 150 HP; whether it is billed is an open question |
| **Eels** | any body, one-row gutters included | wiggle along the centre line | Glow telegraph 0.8 s, then a shock: 12 to everyone **in the same connected body** within 6. Each owner applies it to its own (`Net.resolves`) | needs body ids per wet cell |
| **Escaped specimen** | any, and walkways | a land monster that prefers water | as `pool-options.md`: heals 4 HP/s in water | amphibious, the only one that follows you out |
| **Rat swarm** | walkways; swims slowly | a swarm actor (the imp swarm's cousin): one host-owned actor that is many rats | nibble 2 per 0.5 s while on you; fire scatters it; corn distracts it | rats are many small threats; one actor keeps the net cheap |

## Look

- **Materials** (`rooms*.png`), three looks in the lab:

  | Look | Walls | Liner and channel | Water | Light |
  |---|---|---|---|---|
  | **brick** (Victorian, the lair) | red-brown brick in a running bond (a lab pattern), a damp green tide line | brick liner, silty bed with slime | murky olive-green, scum blotches, foam streaks along the flow, alpha 0.7 | sickly yellow-green downlights, cool daylight shafts from grates |
  | **concrete** (storm drain, bunker) | poured concrete (the game's formwork) | concrete liner with a hazard stripe, a yellow kerb | grey-teal | sodium orange |
  | **toxic** (lair overflow, the founder's coolant) | dark stone blocks | stone liner, glowing slime | glowing acid green (the specimen pool's colour) | green, dimmer |

- **Kerb:** a stone kerb runs along every rim, the coping's sewer cousin. In the lab it sits on the rim's dry side, and in
  the concrete look it is hazard yellow. Foam runs along every edge of the water, rims and walls alike.
- **Props** (lab-only, `sewer_props.gd`):
  - an outfall pipe pouring a stream;
  - rusty pipe runs with brackets and a valve;
  - a floor grate and a grate bridge;
  - a sluice gate;
  - brick arch springers (ribs up the walls that start to curl over and stop: the iso camera never shows a ceiling, so the
    springers say "vaulted tunnel");
  - iron bars, rungs up to a manhole, a rubber duck, and the gator and the rats.
- **With the amber hex floor:**
  - The seams stay on the dry walkways, which keeps them the game's language: "where you stand" stays amber.
  - Under water the pool floor has no seams, as the pools already do.
  - In the lab the sunk cut cells next to walls keep a faint seam under the water, a lab shortcut. A real build draws them
    as pool floor.
- **With fog look A** (`fog.png`): next spaces are a dark silhouette with traced edges. The water's surface in a next
  space is restyled like the floor under it, so a flooded hall reads as an outline before you see it.

## Generator implications (what a build would need)

1. **Choosing the cluster:** after DungeonGen and before themes, pick 2-4 rooms joined by tree links.
   - Not the start room (the van), and not the exit room unless its landing stays dry.
   - Prefer rooms at the **same base level**. A link with terraces or stairs can't hold one water level.
   - Either flatten those links when the cluster is picked (DungeonGen's `_profile` already chooses events; a "sewer"
     flag asks for none), or put a **weir** at each terrace: a one-level step in the water with a foam lip, two
     bodies at two surfaces. Flattening is simpler.
2. **Water as cells, not convex outlines.**
   - Today a pool is a record with a convex `outline` (and a `hole` for the moat); PoolView, SharkSteer and the tests lean
     on that convexity.
   - A sewer body is a **set of wet cells** across rooms and halls, which is generally non-convex.
   - The cell data already exists (`pool_mask`, `pool_level`), and `HexMap.water_at` already works per cell. What is
     missing:
     - **`HexMap` and `HexMapView`: water up to a wall.** A cut cell that has both wall kites and pool kites. Today
       `_add_pool_cell` returns before drawing a wall part. This is the one real engine change: the inset drawing plus the
       wall part in one cell, and `test_wall_mesh` over the mixed masks.
     - **The rim kink at a wall.** Where a rim meets a wall, the cut cell beside it keeps a one-kite notch with two
       half-edge steps (visible in the lab where the cistern channel meets the doorway). A build either allows pool kites
       on cut cells (as above) or places a sluice post there, which also dresses it.
     - **PoolView for bodies:** water as a fan per wet kite, foam along every boundary edge, the kerb on rim edges only.
       The lab's `_build_water` is the sketch (about 120 lines).
     - **A body record:** `{id, cells, surface_level, flow segments, look}` per connected water. Body ids per cell serve
       the eels' shock and the monsters' confinement.
3. **Monsters in non-convex water.** SharkSteer measures the distance to a convex outline and a hole. A gator needs a
   **distance field per body**: rim and wall segments gathered once per body, plus a coarse grid (0.25) of distances
   computed at spawn. Or it steers along the body's centre-line graph (channels are corridors, so a graph is natural)
   with the same feelers.
4. **The floor checksum:** `NetFloor.map_text_of` already hashes every cell's `pool_mask` and `pool_level`. Add the body
   records (`canon(map.water_bodies)`) as it does for `pools`.
5. **Perf against the planning budget.**
   - `test_room_themes` checks an average floor plan under 150 ms, and it is close to that.
   - The sewer pass is a flood fill and a few loops over the cluster's cells, about 1-2 ms a floor. The cluster choice is
     a walk of the tree.
   - **Time it on its own** (`SiteBuilder.last_sewer_usec`), the way doors and sharks are timed outside
     `last_plan_usec`, so it never eats the themes' margin.
   - Drawing: one water mesh per body; the foam is a few hundred quads.
6. **Placement rules:**
   - packs, employees, notes, mail and props stay on dry floor (`is_pool_cell`, as now);
   - the walkways must join every doorway of a sewer room (BFS over dry full cells);
   - water capped at about 45 % of a sewer room.

## Networking shape

| Piece | Shape | Notes |
|---|---|---|
| wet cells, bodies, flow, kerbs, grates, sluices | **terrain / spawn data** from the seed | every machine builds the same; in the checksum |
| wading slow, soak | as built | the slow is `LOCAL`; the soak is an owner-applied status |
| sluice gates | the office door's object | host-arbitrated, unchanged |
| gator, eels, specimen, rat swarm | **owned actors (host)** | like `Shark`; a bite or shock is resolved by the victim's owner (`Monster.net_strike`); the eel's body-wide shock is one wind-up event, each machine applying it to what it resolves |
| foam, flow streaks, drips, steam, the duck | **cosmetic** | `fx_rng` |

There is no new shape. The death roll's hold is a status the victim's owner applies, like a daze.

---

# Part 2: the lava cave

**Next step (2026-10-20): `lava-playtest.md`.** It has five cave layouts with the fight flow marked, and a playable solo
prototype behind `--lava-cave N`. It also records the user's answers: two-wide bridges, archers on isles with no path,
damp crust, and 15 damage plus a burn.

## Summary

A **lava cave** is not a pool shape. The cave's floor drops to a **lava plane**, and everything you walk on is raised hex
**rock**:
- **islands and chambers** are clusters of hex columns standing out of the lava, rough because a hex steps a level now and
  then;
- **hex bridges** are one-hex-wide runs of columns with small steps, sometimes kinked, with a two-level climb or a
  split;
- the cave's edge is a **rim of hex columns at varied heights**: low on the camera's side, tall at the back.

All of this is the terrain the game already has (levels, climbing, drops), drawn by `HexMapView` with no change. The lab
only swaps the crate texture for rock. The lava's rule is the **void pit's rule**, which also exists: a shoved hero is
pulled back to the last safe spot and hurt, and a shoved monster falls and dies. Lava adds Burning.

The cave is **several adjacent fog spaces**: each island or chamber is a room and each bridge a hall. The bridge ends are
the doorways, with no door. The cave reveals itself a section at a time, and the lab ran this through `RoomFog` with no
change.

## Fit

- **Supervillain** (site "Volcano lair"): the obvious one. The lair's lower level is the volcano itself, and the throne
  room or the doomsday console's power is "geothermal".
- **Tech founder** (the data center lair): "geothermal cooling" gone wrong. The obsidian look fits: mostly crusted over,
  with glowing cracks.
- **Hellgate-adjacent:**
  - A cave in the **hellfire** look (hell-red rock, red lava, violet embers) is where a hellgate leaks into the level: the
    room under the gate, where the "monster under the level" (`HellgateBeast`) lives.
  - It pairs with **corruption pools** (§4.6): the violet ichor puddles on the islands near a gate, a buff to monsters
    standing in them. The cave adds a place to shove those monsters off the buff and into the lava.
- **Bunker clients:** no fit. A billionaire's bunker has no lava. At most one "decorative magma feature" in the spa, which
  is a joke and not a cave.

**Proposal:**
- Lair floors 2-3, one cave per floor at most, in place of a cluster of 2-4 rooms.
- Hellfire look when a hellgate is in or next to the cave; magma otherwise; obsidian on the founder's floors.

## Terrain

### How a cave is generated (and how it differs from PoolGeo)

| | PoolGeo (pools, moat) | Lava cave |
|---|---|---|
| What sinks | a convex cluster of cells inside a room | the **whole cave's floor**: the lava bed |
| What you walk on | the room's floor, with a basin cut out | raised rock: islands, chambers, bridges |
| Edges | midpoint lines (an inset with a liner and coping) | **hex edges**: rough columns, cliff faces down to the lava |
| Walls | the room's midpoint walls | a **rim of tall hex columns** (no WALL cells, no `cut_walls` in the cave) |
| Shape rules | convex, 60 / 120 degree corners | anything: noise, blobs, paths |
| Walk in? | yes (one-level step) | **no**: the lava is 4+ levels down, so walking off is BLOCKED by today's drop rule |

**A cave pass** (sketch), run in DungeonGen in place of carving a cluster of rooms and their links:
1. **The region:** pick 2-4 neighbouring rooms in the tree. The cave is everything within about 4 cells of the room
   centres and the links between them, with a noisy edge. Every cell in it is **lava** at `LAVA_BED` (4+ levels below the
   lowest rock).
2. **Islands and chambers:** each room's core becomes a rough rock blob.
   - Base level plus a level now and then (the lab: +1 on about a third of the cells, -1 on a few edge cells).
   - A crag of +2 or +3 in a big one, for vantage and as a climb.
   - The room keeps its `room:N` tag, so themes, decor, packs and fog all still see a room.
3. **Bridges:** each tree link becomes a **one-hex-wide path** over the lava (a straight run or a kinked one), tagged
   `corridor`.
   - Its levels are a random walk of +-1 per hex.
   - At most one **two-level climb** per bridge, and never on the only route from start to exit (`exploration.md`: the
     brute always has a walkable way round).
   - Optionally a **split** to an islet.
4. **The rim:** two rings of columns round the region.
   - **3** on the camera's side (+X+Z), which blocks walking from shore rock at 0 and hides little.
   - **6-9** at the back, a cliff that frames the cave.
   - The rim must stand 3+ above any rock beside it, or a hero could climb out.
5. **Validation:** `_validate_and_tag`'s BFS and `find_path` with lava as non-walkable. Every island is reached, and
   start to exit needs no climb.

**Variety and roughness:**
- Neighbouring hexes differ by 0 or 1 level (0.5), the walkable step. That is the rough-rock look in `cave_bridge.png`.
- Finer variance (0.1-0.2 per hex) would need fractional levels, which the terrain does not have. A cosmetic per-hex top
  jitter in `HexMapView` (rock only) could give it without touching movement.
- **The amber seams on dark rock read as columnar basalt**, which is a real hex rock (the Giant's Causeway). The game's
  hex style becomes the cave's geology.

### Is lava impassable or damaging?

**Both.** It is impassable on foot and damaging when you are forced in. The rule is mostly built already:
- **Walking:** lava cells sit 4+ levels below every rock, so `movement_check` blocks walking off any edge (more than
  `DROP_LEVELS` 3). Nobody steps into lava by accident, and pathing never routes through it (not walkable).
- **Shoved in:**
  - A **hero** gets today's void-pit rule (`Actor._enter_void`): it is pulled back to its last safe position
    (`_safe_position`) in 0.3 s and takes damage, plus **Burning** (`Burning.ignite`, 6 s: 3 HP/s, 18 total). Proposed:
    **15 damage plus the burn** instead of the pit's 5, because lava should hurt more than falling.
  - Soaked heroes don't ignite. A damp before the crossing is armour against the burn but not against the 15.
  - A **monster** falls in and dies, the pit rule (`VOID_FALL_TIME` 0.7, a sink and a burst of embers instead of a fall).
- **So shoves are the combat tool.** Rebar's fist, Gasket's spin, tentacles, the bowl and a brute's slam all become
  lethal near an edge, for monsters. For heroes it is a punishment, not a death: the north star's "no slip ends a run"
  holds.
- **Bridges are the stage:** a one-hex bridge is the shove-off-the-ledge fantasy (`cross_close.png`: Rebar punches a
  skeleton off the side). A brute on a bridge is the "do I shove it or does it shove me" moment.
- **Heat:**
  - Proposed: standing on rock **next to lava** does nothing (a damage aura makes bridges a chore).
  - The tell is the **glow**: the lava's light and a glow lapping up every rock face over it (the lab's skirt), embers
    rising, and heat haze (a screen-space wobble over lava pixels, cheap, not in the lab).

### Crossings

- **Rough hex bridges** (`cave_bridge.png`, `cave_kink.png`):
  - straight, small steps;
  - kinked, with a **two-level climb** (the slow `CLIMB`: exposed, as `exploration.md` says);
  - **split**, a fork to an islet.
- **Stepping stones:** a gap of one lava hex is not crossable (no jumping). Stepping stones are a bridge whose hexes
  alternate levels.
- **Damp crust** (spells, below): a temporary crossing.
- No built bridges. The user's direction is natural rock. A built gantry could be one optional set piece (the villain's
  catwalk).

### Movement on rock

- Rough rock costs nothing extra: every step is 0 or 1 level, which is walking. The two-level climb is the only slow
  step.
- **Edge falls:** walking can't take you off an edge. A shove that sends you off rock onto lower rock is a normal shove
  fall (fall damage above 3 levels, as now).
- **Monsters path the bridges single file.** A pack on a bridge is a line, good for corn and for shoving.

### Lines of sight and vantage

- Lava is low, so sight crosses the open lava freely (`line_of_sight` tests the ground height on the ray). Crags and the
  tall back rim block it.
- **Vantage:** a hero 2+ levels above its island's floor sees every adjacent space through its doorways, however far
  (RoomFog's vantage rule). An island's crag is the scout's spot. That is `exploration.md`'s "height reveals the map",
  built.
- Archers on a crag across the lava can shoot you on a bridge, and you can't walk to them except by the bridge.

### Fog: a cave is several spaces (`cave_spaces.png`, `fog.png`)

- **Islands and chambers are rooms; bridges are halls.** Lava and rim cells carry neither tag and take the nearest space
  (`Doorways.spaces`' fill), so the lava between two islands splits between them.
- **Doorways fall at the bridge ends.** `Doorways.find` already makes one where a hall's cells touch a room's (the yellow
  rings). The lab ran the cave through `RoomFog` unmodified:
  - crew at the back of island A: A and the A-B bridge in view, island B **next** (an outline), far chamber C, islet D and
    the B-C bridge **unknown** (`fog.png`);
  - crew on B (`fog_on_b.png`): B, A and the B-C bridge in view, C and D next.
- **What `Doorways` / `RoomFog` would need:**
  - **A doorway with no walls.** The width measure (marching to wall faces) finds none in a cave, so `ok` / `door_ok` come
    out false. That is harmless for fog, but a cave flag should say "an opening, never a door" explicitly, rather than
    rely on a failed measure.
  - **Cave mouths:** where two rock chambers touch with no bridge, a short neck of rock tagged as a hall (one or two hexes)
    is the mouth. That keeps "a doorway is where a hall meets a room", so no new doorway kind is needed.
  - **Sight across the lava between two islands with no bridge between them:** today a space is seen only through its
    doorways or by vantage. Two islands facing each other over open lava, not joined directly, stay unknown until reached.
    That is a choice: either accept it (the cave reveals by bridges), or add a "seen across" rule (an adjacent space in
    line of sight within `DOOR_SIGHT`, no doorway needed). **Proposal: accept it.** The vantage crags give the
    across-the-lava view.

## Spells and interactions

- **Damp** cools a patch of lava into **crust** for 10 s.
  - The lava cells in the damp's area (the same pure function of centre, radius and stamp that `Damp` uses for its
    puddles) rise to one level below the shore rock: walkable, with a crust look.
  - It **cracks** over its last 2 s (the telegraph). Anyone still on it when it melts gets the lava rule (pulled back,
    burned).
  - It is a scheduled effect from the cast, so no message is needed.
- **Explosive props** (`ExplosiveProp`) near lava: a drum shoved into lava **goes off** where it lands, so shove it in
  under the enemies standing at the edge. A drum standing within one hex of lava cooks off when hit by anything (no
  fizzle).
- **Fireball:** no fire in lava (already hot); fire creatures are fireproof (`Burning.set_fireproof`). A blast still
  shoves.
- **Corn over lava pops:** the kernels that land in lava burst into popcorn, a bigger, harmless cosmetic burst. Proposed
  as cosmetic only.
- **Tentacles and the bowl:** shoves, so they kill near an edge.
- **Vines:** can't root in lava; they root on rock as usual.

## Lava creatures

All are host-owned actors in the **open lava between islands**, confined by the same steering and distance field as the
sewer gator. Lava is lit and wide, so they get room: keep at least 4.5 (three rows) of open lava where they swim.

| Creature | Counterpart | Lives | Attack | Notes |
|---|---|---|---|---|
| **Lava salamander** (`cross.png`, lab model) | the shark / gator | open lava, 4.5+ | the shark's lunge onto rock within 1.2 of the edge (18 and a shove **away** from the lava, as decided for the shark's bite); its back crust glows before it lunges | black crusted body, glowing cracks, a spiked frill; only its back and frill show |
| **Magma eel** | the electric eel | narrow lava between close islands, 1.5+ | spits a lava gob in an arc (a projectile, 10 and Burning) at someone on a bridge | it makes bridges dangerous at range |
| **Fire imps** (`cross.png`, bathing) | the imp swarm | lava near islets, bathing | they climb out onto rock and fight as imps; fireproof | the swarmer model, waist deep |
| **Lava elemental / the beast under the level** | the specimen | rises from lava in a hellgate cave | big, slow; the `HellgateBeast` look | ties the cave to the hellgates |

**Width:** the salamander uses the gator's tuning (`R_TURN` 1.0) at about 3.0 long. Open lava 4.5+ wide gives a lane of
3.5, so it circles freely. The lab's cave has 4-8 hexes of lava between islands, which is plenty.

## Look

- **Lava** (`LAVA_SHADER` in the lab):
  - dark crust plates (a cellular pattern) drifting slowly, the glow in the cracks and in slow hot patches;
  - unshaded, HDR, so the cracks bloom with the game's glow;
  - a **skirt** of glow lapping up every rock face over the lava;
  - embers rising.
- **Rock:** dark basalt tops with a speckle, banded column sides, and the **amber seams**. On lava the amber is right at
  home: it reads as cooling cracks.
- **Three looks** (`cave*.png`):
  - **magma**: black basalt, orange lava under a dark crust, warm light, 10 lights;
  - **hellfire**: hell-red rock and lava, violet embers, for the hellgate caves, 10 lights;
  - **obsidian**: mostly crusted over, glowing cracks only, dark and cheap, 4 lights.
- **Lighting:**
  - The lava lights the cave. The lab puts warm OmniLights over the lava by farthest-point picks (10 in a 3-chamber cave)
    and dims DungeonLook's downlights to a warm glow.
  - **Perf:** `environment.md`'s budget is about 3 extra lights a room, with DungeonLook at most 12 a floor. A cave of 3-4
    spaces is within that at 8-10, but they are unshadowed omnis over big areas.
  - Cheaper alternatives, best first:
    1. most of the light comes from the lava's **emission and bloom** and a warm **ambient** tint in the cave's spaces;
    2. 4-6 omnis per cave (the obsidian look's count is enough);
    3. a light only where the crew is (two or three that follow the camera's area), which is a cheat that works in iso.
  - Measure on the min-spec machine before choosing.
- **With fog look A** (`fog.png`): a next island is a dark silhouette and the lava there is restyled to the same
  silhouette, so the glow does not leak into fog. Lava light still falls on in-view rock near a fogged area, which is
  fine (it is light, not information).
- **With the amber floor style:** the seams on rock and the lava's cracks are the same colour family. The hellfire look
  shifts both toward red, which matches "hotter seams near nests" in `environment.md`.

## Generator implications

- **A cave pass in DungeonGen** (above): the region, the islands from the rooms, the bridges from the links, the rim.
  - It runs before the walls, and the cave's cells skip `cut_walls` (no WALL cells inside; the rim is floor columns too
    high to walk onto).
  - Where the cave meets an ordinary hall, the hall's walls end at the rim. That junction is the one new geometry case:
    the hall's last cut cells border rim columns, which needs a check in `_walls_clean`.
- **A lava flag per cell** (`Cell.liquid` = LAVA, or a `Tile.LAVA`): spawn data and in the checksum. `ground_level`
  reports the bed; `water_at`-style `lava_at(p)`.
- **The lava rule** in `Actor`: landing on a lava cell runs `_enter_void` with the lava's damage and burn. It is the
  owner's call, as for pits.
- **Pathing:** lava cells are never path nodes. Bridges are one hex wide, so packs walk single file.
- **Themes:** a cave room's decor is rock-only (stalagmites, a chained cage, the villain's geothermal pipes). Packs and
  props stay off bridges (keep them clear).
- **The checksum** gets the lava flag. **Perf:** the cave pass is a few loops over 300-600 cells, about 2-4 ms. Time it
  on its own (`last_cave_usec`), outside the themes' 150 ms.
- **The HexMapView crate rule:** raised cells in a room are drawn as wooden crates today, and untagged ones too. A cave
  needs its own rule ("rock, not crates"), which the lab faked by swapping the crate textures.

## Networking shape

| Piece | Shape |
|---|---|
| rock levels, lava cells, bridges, rim | **terrain / spawn data** from the seed, in the checksum |
| a hero shoved into lava | the void rule, **applied by the hero's owner** (pull back, damage, burn: an owner-applied status, announced like any burn) |
| a monster shoved into lava | its owner (the host) runs the fall and `die()`, as for pits; billed nothing |
| damp crust | a **scheduled effect** from the cast (start time and the damp's pure cell function); everyone's terrain rises and falls on the shared clock |
| salamander, magma eel, imps | **owned actors (host)**, like `Shark` |
| glow, embers, heat haze, lights | **cosmetic** |

The crust is the one new piece: **terrain that changes on a schedule.** Every machine computes the same crust cells from
the cast, and `ground_level` asks "is this crust now?" from the shared clock. This is how `pool-options.md` proposed water
levels: a scheduled effect, no new kind.

---

# Part 3: sewer vs lava

| | Sewer | Lava cave |
|---|---|---|
| **What it adds to play** | **Wading as a cost**: long wet halls slow and soak you; a dry ledge vs a wet shortcut. A gator that owns the channels. Soaked = fireproof, so it changes fire fights. | **Shoves become lethal**: every edge is a kill for Rebar and Gasket. Bridges are tense single-file lanes. **Vantage and routes**: islands, crags, climbs. The most dramatic set piece. |
| **What it costs (engine)** | **Water up to a wall** in HexMap / HexMapView (pool kites in cut cells) plus a mesh test. Non-convex water bodies (PoolView by kites, body records). A gator steering in non-convex water. | **Nothing in the terrain drawing** (`HexMapView` draws it as is; only the crate texture rule). The lava rule is the void rule plus a burn. Fog works as is. The crust is a new scheduled terrain effect. |
| **What it costs (generator)** | **Small**: flag a cluster, flatten its links, flood cells. | **Big**: a new cave pass (region, islands, bridges, rim, validation), and where a cave meets an ordinary hall. |
| **What it costs (look)** | Kerb, foam, a brick pattern, props. | A lava shader, a skirt, embers, and a **light budget** to measure. |
| **Monsters** | gator (new steering), eels, specimen, rat swarm | salamander (the gator's steering), magma eel, imps, the beast |
| **Risk** | Visual clutter in narrow halls; the near-wall occlusion of a channel; water share in rooms. | Perf of the lights; a bridge or crag layout that soft-locks a route; frustration from repeated shoves into lava. |

**Recommendation: do the sewer first, then the lava cave.**
- The user's question was water monsters, and the sewer answers it with the most built code: wading, the soak, the pool
  cells, SharkSteer and the shark actor, the fog. It is an extension, not a new system.
- Its one engine change (water to the wall) is contained and testable.
- The gator is the shark with a tighter turn.
- The lava cave is the bigger payoff for the combat pillar, because shoves become kills for free (the void rule exists).
  But it needs a whole new generator pass and a light budget, so build it second, for the supervillain and the
  hellgates. Its two pieces that are nearly free could ship early on their own:
  - the lava rule (the void rule plus a burn), in a small **lava pit** inside an ordinary lair room;
  - the lava shader.

---

## Lab

```
godot --path . --resolution 1920x1080 -- --scene res://scenes/sewer_lab.tscn --case <case> [--look brick|concrete|toxic] --shot <png>
godot --path . --resolution 1920x1080 -- --scene res://scenes/lava_lab.tscn  --case <case> [--look magma|hellfire|obsidian] --shot <png>
```

- `scripts/art/lowpoly/sewer_lab.gd`, `scenes/sewer_lab.tscn`:
  - cases: `rooms`, `hall`, `main`, `junction`, `fog`, `gator`;
  - a hand-made HexMap with hex-blob rooms and DungeonGen-cut halls;
  - the lab sinks wet cells and cuts ring kites, then draws the water, foam and kerbs itself;
  - it restyles the terrain's materials per look (a brick pattern added to a copy of the material shader at runtime).
- `scripts/art/lowpoly/lava_lab.gd`, `scenes/lava_lab.tscn`:
  - extends the sewer lab;
  - cases: `cave` (views game, spaces, plan, bridge, kink), `cross`, `fog` (views game, close, on_b);
  - the cave's map, the lava, the skirt, embers and lights, and the fog spaces drawn on it.
- `scripts/art/lowpoly/props/sewer_props.gd`: **lab-only models**, in no game kit and not in the z-fight registry:
  - gator, salamander, rat / rat swarm;
  - outfall, pipe bundle, grate, grate bridge, sluice;
  - springer, wall ladder, duck, bars.
- Nothing in the game references them; `test_net_contract` and `test_zfight` pass.

## Renders

In the session scratchpad: `...\scratchpad\sewer\` (sewer) and `...\scratchpad\sewer\lava\` (lava). Size 24 is the game
camera (ortho, yaw 45, pitch -56); `_close` is size 9.

| File | What |
|---|---|
| `rooms.png`, `rooms_close.png`, `rooms_plan.png` | the cistern and the outfall room joined by a flooded narrow hall (brick); close on Wick wading at the sluice; plan at size 34 |
| `rooms_concrete.png`, `rooms_toxic.png`, `rooms_close_*.png` | the other two looks |
| `hall.png`, `hall_close.png` | a wide hall: a 3.0 channel against the near wall, a 1.5 ledge on the far side |
| `main.png`, `main_close.png` | the 6.0 sewer main: two ledges, a gator in the middle channel |
| `junction.png`, `junction_close.png` | three flooded halls meet over a drain grate; an outfall, a grate bridge, a manhole shaft, an eel |
| `fog.png`, `fog_close.png`, `fog_hall.png` | room fog look A: from the cistern, then from inside the hall |
| `gator.png`, `gator_close.png`, `gator_closer.png`, `gator_close_*.png` | a gator curled mid-turn in the 3.0 channel, Rebar and Wick wading, Gasket on the ledge |
| `lava\cave.png`, `cave_spaces.png`, `cave_plan.png` | the cave overview: islands, a varied rim, two hex bridges; the fog spaces and doorways drawn on it |
| `lava\cave_bridge.png`, `cave_kink.png` | size 9 on the rough straight bridge and the kinked one (the climb, the split) |
| `lava\cave_hellfire.png`, `cave_obsidian.png`, `cave_bridge_*.png` | the other two looks |
| `lava\cross.png`, `cross_close.png`, `cross_hellfire.png` | the crew on the bridge, Rebar punching a skeleton off into the lava, a salamander alongside, imps bathing |
| `lava\fog.png`, `fog_close.png`, `fog_on_b.png` | room fog: A in view, B next, C and D unknown; then from B |

## Open questions for the user

**Sewer:**
1. A **cluster of 2-4 rooms** on some lair and bunker floors (proposed), a whole floor, or a few single rooms?
2. **Fully flooded narrow halls plus ledged wide halls** (proposed), or ledges everywhere?
3. **Sluice gates as the sewer's doors** (same behaviour as office doors), or open archways everywhere in a sewer?
4. **The gator:**
   - property ("kill and bill once", like the shark) or a monster (free, counts as a pest)?
   - is the death-roll hold wanted?
5. Should **flow** stay cosmetic (proposed), or push waders a little (a new owner-applied force)?
6. Which **looks**: brick for the lair, concrete for the bunker, toxic for the founder?

**Lava:**

7. **Lava when shoved in:**
   - heroes pulled back with 15 damage plus a burn, and monsters die (proposed)?
   - or heroes die too (harsher than the north star)?
8. **Damp crust** as a temporary crossing: wanted?
9. **Sight across open lava** between islands that aren't joined: accept that a space is revealed only by bridges and
   crags (proposed), or add a "seen across" rule?
10. **Lights:** OK to measure 8-10 unshadowed omnis per cave, or design for emission plus 4 lights from the start?
11. **Where:** supervillain and hellgate-adjacent only (proposed), or also the founder?

**Both:**

12. Build order: **sewer first** (proposed), or lava first for the combat payoff?
