# Sewers and lava caves (concept)

Status: **phase 1 built** (2026-10-20): the sewer's solo slice behind the dev flag `--sewer N`, see "Phase 1 as built" at
the end of part 1. **Phase 3 built** (2026-10-20): sewer clusters in the generator on solo runs, see "Phase 3 as built"
after it. Still concept: the networking (phase 2) and the rest of the scope.

**Round 2** ("Sewer round 2: connected water, staging, fights", after Part 1) answers the user's verdict on round 1.
Where the two differ, round 2 replaces Part 1: the water as one connected body, the gator, grate bridges as dry
crossings, and the eel's reach. The user's answers to round 2, then "Scope and how a sewer fits a floor" (the options
for fitting a sewer into a floor, the build scope and its phases), follow round 2.

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

## Sewer round 2: connected water, staging, fights

Status: **concept only** (2026-10-20). A second lab, `scripts/art/lowpoly/sewer2_lab.gd` (`scenes/sewer2_lab.tscn`),
stages five populated clusters and three fight moments. No change to the generator, `game.gd`, the monsters or the net
layer.

**The user's words:**
- 2026-10-20, on round 1: "For the sewer, we are not there yet. The water channel is the point so the different rooms
  water should always connect to the water filled hallways. We need to look at what these rooms would look like
  populated. What would we stage in them? How would fights work? I am assuming the water is wade deep so players can
  traverse easily."
- 2026-10-20, gators: "Gators should be billed property like sharks. They should also cross land and nip at enemies.
  They should only be aggressive when approached and periodically move."
- 2026-10-20, the bridge: "The sewer bridge is rotated wrong by 90 degrees so it doesn't provide crossing."

**What this round changes:**
- **The water is one body.** In every sewer room a channel comes in through one doorway, crosses the room and leaves
  through another into the next flooded hall. No sewer room has an isolated pool, and every sump sits on a channel.
- **Wading everywhere**, as the user assumed: the pools' depth (0.36), 0.75x for everyone and soaked. No swimming and no
  deep water.
- **The bridge is fixed.** `_dress_rooms` and the junction case added 90 degrees to the yaw, which laid the grate bridge
  along the channel. Both now use `SewerLab._bridge_over(at, axis, ...)`, which spans the channel from bank to bank.
  `_check_bridges()` tests every bridge in both labs. Each bridge's two ends must be on dry floor (not a wet cell, a pool
  kite or a wall part), and the span between them must pass over water. It prints one line per bridge and raises an
  error on a failure. It caught one bad bridge in this round's L3 (over the aquarium basin, where the water is two rows
  wide), which was removed. All 22 bridges in the five layouts and the two in round 1's cases pass. `bridge_fix_rooms.png` and
  `bridge_fix_junction.png` are the round-1 cases re-rendered with the fix.
- **The gator** is now territorial priced property that walks on land as well as swimming (below).

### The connected-water rule (layout grammar)

1. **Every sewer room's channel joins its sewer doorways.** It is a hex line between the door cells, drawn by how far
   apart the doorways are:
   - **opposite corners:** straight through the centre (L1's cistern, L2's pump post);
   - **corners 120 degrees apart:** through the centre with one 60-degree bend (L1's intake, L4's valve room);
   - **adjacent corners:** along the wall between them, two rows wide (ring R-1 plus the cut ring R), so the water runs
     to the wall (L4's overflow chamber and grit chamber);
   - **three doorways:** a Y into a central sump over a drain (L2's junction).
2. **A room at the cluster's edge** has a channel that starts at a **source** (an outfall pipe, the villain's cracked
   aquarium) or ends at a **barred culvert** in the far corner, where the water goes on out of sight. A channel never
   dead-ends in a pool.
3. **Every hall meets its room channel at the doorway with no step and no jog:**
   - a narrow hall: wall to wall, 3.0, one row;
   - a wide hall: the route row and the near cut row, with a 1.5 ledge on the far side;
   - a 6.0 main: the middle row, with a ledge each side. The room's channel row lines up with it.
4. **One body per cluster.** A flood fill over the wet cells must reach every one of them.
5. **Dry decks connect by bridges.** A channel through a room splits its floor. Each split-off deck that holds a doorway
   or a staged thing gets a grate bridge, so every doorway is reachable dry inside the room. Getting **between** rooms
   stays wet down a narrow hall, or dry along a wide hall's ledge.

### The bridge: a dry crossing (proposal; decided 2026-10-20: "Omit the bridges for now")

Round 1 drew the grate bridge as decor you wade through. The user's note ("so it doesn't provide crossing") reads it as
a crossing, which is also what makes ledges and decks worth fighting for. Proposal:
- **The bridge cell is deck-level for walkers.** Heroes, monsters and employees on it are at the deck's height: dry, not
  slowed and not soaked. The water body still includes the cell, so the flow, the gator and eels pass **under** it, and
  shocks and corn pass under it too.
- **Low handrails:** a slide of **1.5 or more** goes over the rail into the channel (Rebar's fist, the gator's nip,
  tentacles, the bowl, a blast). A smaller slide stops at the rail, with no damage. The ends are open.
- **The check that keeps it honest:** both ends on dry floor on opposite banks, the lab's `_check_bridges` as a
  generator assertion.

### The gator (decided 2026-10-20; numbers proposed)

Its look: the playtest found the model a "stiff point"; the diagnosis, the three rebuilds, the user's pick (V3 Mugger, a
rigid-part rig with a swim S-wave, a walk, breathing, head tracking and the gape, decided 2026-10-20) and the build are in
`gator-look.md` (renders in `gator_look/`).

| | Proposal | Why |
|---|---|---|
| **Property** | kill and bill once, to the killer, like the shark. **$6,300**; HP 150; never toward "Exterminate"; AI allies never target it | It is smaller than a regular shark ($8,400) and has no rig. It leaves the water, so a stray blast is more likely to finish it, and a lower price keeps that from wrecking an invoice. 150 HP keeps the kill deliberate, as for the shark |
| **Moves** | water 2.4, land 1.4 (relocating: 1.2 / 0.9); it walks the same cells as anyone | "Cross land": slower out of the water. A hero walks 4.5 and wades 3.4, so it can always walk away |
| **Home region** | the cluster's wet cells plus the dry cells within 2 of the water | It never wanders into a dry room or down a dry hall |
| **Watch** (radius **4.5**) | anything inside: it turns to track it, eyes bright, head up, a low hiss | the tell. You can read the radius before you are in it |
| **Territory** (radius **3.0** from its head) | anything inside for **0.4 s**, or anything that touches or hits it: a **nip** | "only aggressive when approached" |
| **Nip** | wind-up **0.5 s** (jaws gape, the monsters' orange pulse, the hiss swells), a lunge of up to 1.0, a bite within 1.4 of the snout: **10 damage and a 1.6 shove away from the gator**. Cooldown 1.6 s, one victim a nip | A small bite and a big shove, so the threat is where it puts you. It is Rebar's fist shove, so it goes over a bridge rail. From the water it shoves a ledge-walker onto the deck, the shark's rule |
| **Targets** | any body inside the territory: heroes, monsters, employees, chickens. Not a downed hero, another gator or a prop. Nearest to the snout, those in its 120-degree front counted at 0.7 of their distance, the latest arrival breaking ties. It keeps a victim through a nip and picks again after | "Nip at enemies": both sides have to respect it, and a gator between the crew and a pack is a tool |
| **Riled** | after any hit on it: the territory grows to 4.5 for 8 s and it advances up to 2.0 toward its attacker, once. It never chases further | Hitting it has a cost but it never turns into a hunter |
| **Relocation** | every **30-45 s** (rolled per gator from the floor seed), when calm and nobody is within 6, it moves slowly to another **bask spot** within 14 (path) and settles there. Its territory while moving is 2.0 | "Periodically move." The map changes under the crew: a lane that was clear becomes a gator's |
| **Bask spots** | its home sump, channel bends, the middle of a flooded hall, dry deck cells beside the water. Never a doorway, a bridge or a ledge narrower than 1.5 | It never blocks the only route |
| **Tells** | calm: eyes half-lit, slow bubbles. Watch: eyes bright, head tracking, hiss. Wind-up: gape and orange pulse. Riled: tail thrash. Relocating: a tail swish and a grunt, then a V-wake or footprints | one clear telegraph per state |

**Spells and the gator:**
- **Corn:** 60 damage, and chum: it turns to kernels within 6 in its water for 4 s, with no nips. Kernels float
  downstream, so cast corn upstream of it.
- **Fireball:** 40. In the water it can't catch fire (soaked). On land, after 15 s dry it can burn, and a burning gator
  makes straight for the water and doesn't nip (proposal, question 10).
- **Tentacles, the bowl, blasts:** decided 2026-10-20, "gators can be shoved": a shove moves it like any body (see
  "Shoved gators" under "Decided" below). This replaces the proposal to hold it in place like the shark.
- **Vines** root it 2 s. **Coffee** speeds it. **Damp** soaks it.
- A **chicken** in its territory is eaten.

**Monsters and allies:**
- Monsters don't target it, and a monster that gets nipped carries on (the shark's rule). Monsters path straight
  through its territory: that is the tool.
- AI allies treat it as a priced prop: they never target it, keep formation slots out of its territory and never idle
  inside its watch radius.

**Networking shape: a host-owned actor that is not confined to water.**
- It is a `Monster` subclass like `Shark`: team NEUTRAL, groups "gators" and `PricedProp.GROUP`, streamed in the
  MONSTER entry.
- The nip is the shark's bite path. `world.windup {id, s, l = 0.5}` goes out; each client resolves the strike on its
  own hero (`Monster.net_strike`); the host resolves monsters, employees and AI heroes. The shove is applied by the
  victim's owner.
- Death and the bill are the shark's: `world.die`, and `Ledger.damage` once on the host.
- It is a dynamic fog group. Late join gets a keyframe; a dead gator is a gone id.

**What changes from the shark's confinement:**

| | Shark | Gator |
|---|---|---|
| Movement | clipped to its pool record (convex outline), steered by SharkSteer | ordinary walking (`find_path`, `movement_check`) restricted to its **home region**, a SPAWN cell set from the seed that goes in the checksum. It swims with the per-body distance field (round 1) and walks on land like a monster |
| Speed | always water speed | picked each step by `HexMap.water_at` under it. The same pure function runs on every machine; only the host moves it |
| Shoves | held, clipped to the water | **moved** like any body (decided); shoved out of its home region it walks back |
| States (3 bits) | CRUISE, HUNT, BITE, RECOIL, DEAD, CHARGE, HELD, CHUM | CALM 0, RILED 1, NIP 2, MOVE 3, DEAD 4, WATCH 5, HELD 6, CHUM 7 |
| PRIVATE | steering, scans | the territory scan, the relocation timer and target spot, the victim pick |
| SPAWN | variant, pool index | home region index, bask spot list, price |

There is no new shape: it is an owned actor with one new piece of spawn data, the home region.

### Population: what we stage

**Monsters** (the existing kinds; how a sewer changes them):

| Kind | Where in a sewer | What the water does |
|---|---|---|
| Skeletons (grunt) | the pack's body: decks and walkways near bridges, one or two wading as a patrol (the existing skeleton patrol) | They path the shortest way, so they **wade** (0.75x, soaked) and walk through the gator's lanes. Don't teach them to avoid water |
| Archers | **dry decks and ledges with a channel between them and the room's main doorway**, or a main's far ledge | The crew has to wade (slowly) or take the bridge, a chokepoint the archer covers. Archers flee inside 3.5, so a dry deck with its back to a wall pins them |
| Brute | a wide deck or a filter island | Its slam (radius 2, shove 1.0) knocks waders along the channel. On an island it is the "shove it off into the gator's lane" target |
| ~~Rats~~ (omitted, decided 2026-10-20) | decks by outfalls and grates; rafts of them along the walls | Proposal: a sewer **reskin of the swarmer pack**: the same numbers, named "rats", swimming at 0.6x. Fire scatters them; corn distracts them (they eat it) |
| Goblin scout | a hall's ledge (his corridor route runs along it) | On the ledge he is out of the water and sees down the whole hall |
| Eels | channels, a sump, or escaped from the aquarium | Their shock reaches waders within 6 **along the water** (no longer "the whole body": the whole cluster is one body now) |
| Gator | one a cluster, two in a cluster of four rooms | its home sump, a flooded narrow hall, or basking on a deck |

A ranged sewer pest that lobs goo from the walkways, the **goo imp**, is proposed in `goo-imp.md` (look-dev only; the
user picked the Gloop look, 2026-10-20).

**Priced props and decor:**

| Fits a sewer | Kind | Status |
|---|---|---|
| Sump pump | **new** priced prop, **$3,500** (lab model `pump`) | the pump room's money call |
| Electrical panel | **new**, **$250** (lab model `junction_box`): the live-wire source of `combat-proposals.md` §4.1 | |
| The villain's aquarium (`shark_tank`, $7,000), specimen vat ($5,000) | existing | the aquarium overflow's source |
| Henchman locker ($300), evil portrait ($2,000), brazier ($400) | existing | lair pump posts |
| Oil drum, gas cylinders, propane tank | existing explosives | **only on dry deck cells, never wet or rim cells** (a soaked drum is a dud) |
| Outfall, pipe bundles, valve wheels, grates, springers, ladder and light shaft, iron bars, rubber duck | lab decor (round 1) | |
| Tool cart (new lab model), wet-floor sign, crate stacks, barrels, `lab_console` as a pump or filter console | decor | |

**Employees:**
- **Bunker:** maintenance staff on duty: "Stan (maintenance)" (existing), and proposed "Doug (pumps)" and "Rhonda (water
  quality)".
- **Lair:** henchmen on pump duty with their clipboards, and an aquarium keeper.
- They cower on decks next to their machines.
- Escorting one out is a route problem: proposal, employees cost water at x3 in their paths, so a follower takes the
  bridges and ledges.

**Notes** (existing formats):
- sign: "RECLAIMED WATER: DO NOT DRINK";
- sign: "GATOR CROSSING";
- sign: "LEVEL RISES WITHOUT WARNING";
- memo: the gator feeding rota;
- complaint: "Who keeps putting the gator in the aquarium?";
- report: the pump log;
- voicemail: the plumber who will not come back.

**Hazards:**
- **Live wire + water** (§4.1, the electrical panel): 12 damage (18 on soaked waders) and a 0.6 s daze, both sides; dry
  ground is safe. **Decided 2026-10-20 ("lets just have it distance based"):** it hits everyone in the water within N
  cells of where the cable lands (proposed N = 5). This replaces the round-2 proposal of 8 cells along the water,
  stopped by a shut sluice.
- **Steam valves** (§4.4) on pipe runs: in a hall or a main, the steam wall vents **across** it (one hex wide, wall to
  wall). It blocks sight and passage for 3 s.
- **Sewer gas pocket** (new): bubbles on a sump. Any fire sets it off (a fireball, a burning actor, a blast): a 1.0 s
  boil, then a flash of radius 3.0, 30 damage and a 2.0 shove. One use. It isn't property, so it bills nothing
  (question 6).
- **Explosive drums** on decks over the channel: the blast shoves into the water, toward the gator.

**Loot:** mail packages on dry decks near doorways (never in the water) and component pickups as now. The sewer's own
gag: the rubber duck, which is decor.

### The five layouts

All five are at the game camera (size 24, 1920 x 1080) with a top-down plan. The plan shows:
- the water body (blue), dry room decks (green), ledges (yellow) and dry halls (grey);
- bridges (white), sluices and doors (red) and open arches (green bars);
- the fog spaces as `RoomFog` builds them, unchanged (cyan edges, names);
- the gator's territory and watch rings, bask spots and relocation route (orange);
- labels for everything staged.

#### L1 Reclamation run (bunker, concrete): `reclaim.png`, `reclaim_game2.png`, `reclaim_plan.png`

**Layout:**
- A **intake** (an outfall in the back corner; the channel bends through) -> a narrow flooded hall (sluices at both
  ends) -> B **settling cistern** (straight through a radius-2 sump) -> a wide hall with a ledge (open arches) -> C
  **pump room** (the channel ends in a drain sump under the pumps).
- Dry halls lead in at A's south corner and out of C's north corner.
- Bridges: 5. Fog spaces: 5 rooms and 4 halls.

**Staging:**
- A: rats on the intake deck, the "do not drink" sign.
- The hall: one skeleton wading.
- B: the gator in the sump, three skeletons on the decks, an archer on the north deck, a gas pocket.
- The ledge: the goblin scout.
- C: two sump pumps ($3,500), the electrical panel over the drain, a brute and two archers on the pump deck, Stan
  cowering by the pumps, the pump log on the tool cart, an oil drum.

**Fight:**
- **Entry:** dry, from the stair onto A's south deck. A's channel separates the crew from the rats. The bridges are the
  only dry way to the hall.
- **Positioning:** the A-B hall is a 3.1 s wade, and a soaked arrival can't burn, so fire can't punish the crew. B's
  decks are split by the sump; the two bridges are the dry crossings, and the gator sits between them.
- **The gator's lane:** the sump, with a bask spot on B's south deck and one in the wide hall. When it relocates into the
  wide hall, the ledge is the only dry way past, 1.5 wide and within its territory (it turns, hisses and nips whoever
  hugs the ledge's water edge).
- **Spells in water:** corn cast upstream (A's side) drifts toward B's sump and chums the gator off the bridges. A
  fireball on B's gas pocket flashes the skeletons on the decks.
- **Ranged:** C's two archers on the pump deck shoot across the channel at anyone in the wide hall.
- **Shoves:** Rebar's fist on a bridge sends a skeleton over the rail into the sump.
- **The money call:** the panel over C's drain. Tripping it shocks every wader within 8 cells (the brute's side has to
  wade to reach the crew), but a blast near the pumps is $3,500 each.

#### L2 The Y junction (lair, brick): `junction.png`, `junction_plan.png`, fight: `fight_shove.png`, `fight_shove_close.png`

**Layout:**
- J **drain junction**: three channels meet over a drain sump, with three dry wedges joined by three bridges.
- Three flooded narrow halls lead to three small rooms:
  - E **pump post** (straight through, out by a barred culvert);
  - N **aquarium overflow** (the cracked tank is the source);
  - W **storeroom** (through, out by a culvert).
- The crew comes in down a dry wide hall onto J's south wedge.
- Bridges: 6. Sluices: 6. Fog spaces: 5 rooms and 4 halls.

**Staging:**
- J: the gator in the sump; three skeletons on the NE wedge and one wading; an archer on the NW wedge; the "do not feed
  the gator" note.
- E: two archers and Gary (Henchman 1) on pump duty; the feeding rota memo.
- N: rats and an escaped eel.
- W: a brute by two oil drums and the gas cylinders.

**Fight** (`fight_shove`):
- **Entry:** the south wedge is dry, but each wedge is an island between two channels.
- **Positioning:** the pack on the NE wedge wades the east channel to reach the crew, under the east bridge and through
  the gator's 3.0. The crew holds the south wedge and the bridges.
- **Shoves:** Rebar on the east bridge punches the lead skeleton back over the rail. It lands inside the gator's
  territory, and the gator's nip (10 and a 1.6 shove) sends it on, into the next wader or back up the hall.
- **The gator is a wall that both sides respect.** Nobody crosses the sump. Relocation moves it to the NW wedge (on
  land) or into the north hall, which opens the sump and closes another route.
- **Spells in water:** corn on the east channel stacks the pack in the water and chums the gator onto them.
- **Ranged:** the NW archer has a free line over the sump at the south wedge. W's brute is the explosive play: a
  fireball on the drums while he stands by them.
- **What's different:** the room is three islands. Fights happen at the bridges, and the gator decides which bridge is
  safe.

#### L3 Aquarium overflow (lair, toxic): `aquarium.png`, `aquarium_game2.png`, `aquarium_plan.png`, fight: `fight_wire.png`, `fight_wire_close.png`

**Layout:**
- A **aquarium gallery**: three tanks ($7,000) on the north walls. The cracked one pours into an overflow basin, whose
  channel bends east out of A.
- A wide ledged hall leads to B **filtration**, where the channel splits round a filter island (bridges on and off).
- A flooded narrow hall (sluices) leads to a weir with a culvert.
- Dry entry from A's south corner. Bridges: 3. Fog spaces: 4 rooms and 3 halls.

**Staging:**
- A: two eels in the channel; two archers and Keith (Henchman 10, panicking) on the west deck by the tanks; two skeletons
  (one wading); the electrical panel over the channel's mouth; the complaint note.
- The ledge: the goblin scout.
- B: the brute on the filter island, the gator **basking on land** on the south deck, rats, a gas pocket, gas cylinders.

**Fight** (`fight_wire`):
- **Entry:** dry, onto A's south deck, with the archers across the basin.
- **Positioning:** A's dry ground is the south deck, the west deck and one bridge. The eels make the channel the worst
  place to stand.
- **Live wire:** Wick shoots the panel ($250); the cable drops into the channel. The shock runs 8 cells along the water
  both ways: into the basin and down the hall. It hits every wader (two skeletons, the eel, Rebar if he is in) for 18
  and a 0.6 s daze. Gasket on the bridge is dry and untouched.
- **The gator on land:** in B it basks on the south deck, beside the bridge to the island. Its 3.0 covers the bridge's
  south end, so going for the brute means passing it.
- **Shoves:** tentacles or the bowl on the brute shove him off the island into the ring channel. Rebar's fist knocks the
  scout off the ledge into the hall's channel.
- **What's different:** the water is a conductor. One hit turns the crew's own route into a trap for whoever is in it.

#### L4 Storm-drain loop (bunker, concrete): `loop.png`, `loop_plan.png`

**Layout:**
- Four rooms in a ring:
  - P0 **overflow chamber**: the outfall; its channel runs along the north wall;
  - P1 **valve room**: through, bent;
  - P2 **grit chamber**: the drain; its channel runs along the south wall;
  - P3 **generator nook**: through, bent.
- **Two ledged wide halls** (P0-P1, P3-P2) are the dry long way. **Two fully flooded narrow halls** (P0-P3, P1-P2,
  sluices) are the wet short way.
- The water runs both ways round from P0's outfall to P2's drain.
- Bridges: 4. Fog spaces: 5 rooms and 5 halls.

**Staging:**
- P0: the crew and the "level rises" sign.
- The P0-P1 ledge: the goblin scout.
- P1: two skeletons; Doug (pumps) panicking on the east deck; the pipes and the steam valve.
- The gator in the flooded P1-P2 hall.
- P2: the brute and rats.
- P3: two archers, a propane tank and an oil drum.

**Fight:**
- **The route choice is the fight.** Every way to P3 crosses one flooded hall.
  - **The short way** is the P0-P3 hall: 4 hexes of water (2.0 s wading instead of 1.5 s walking), coming out soaked
    in front of P3's archers.
  - **The long way** is P0-P1 on the ledge, past the scout, then the P1-P2 hall past the gator, then the P2-P3 ledge.
    It is about three times as far with the same 4 hexes of water, and it comes in behind the archers.
- **The gator relocates round the ring** (its route is drawn on the plan). The shortcut it sits in today is open in 40
  seconds, and the ledge it moves next to is not.
- **Ranged:** P3's archers have a deck behind the bend. Wading in means crossing in front of them.
- **Hazards:** a fireball on P3's propane tank goes off on a dry deck, which works. The same blast on the soaked wader
  beside it does 40 but sets nothing alight.
- **What's different:** a loop gives the crew and the pack two ways round, and the gator makes one of them dangerous at a
  time.

#### L5 The sewer main (lair, brick): `main.png`, `main_plan.png`, fight: `fight_ledge.png`, `fight_ledge_close.png`

**Layout:**
- A **grand cistern** (radius 6): an outfall on its west wall and a big sump on the channel.
- A **6.0 main** 13 hexes long: the middle channel, a ledge each side, a grate bridge halfway.
- B **outfall gallery**: the channel crosses it and leaves by a barred culvert.
- Dry halls lead in and out. Bridges: 4. Fog spaces: 4 rooms and 3 halls.

**Staging:**
- A: three skeletons and rats on the north deck; Dave (Henchman 4) cowering; lockers, a portrait and a brazier; the
  "gator crossing" sign at the main's mouth.
- The main: the gator in the channel, two archers on the far ledge, a steam valve on the far wall.
- B: the brute, a gas pocket, an oil drum.

**Fight** (`fight_ledge`):
- **Entry:** the near ledge of the main, from A.
- **Ranged:** the far ledge is the archers' ground. There is no dry way over except the bridge halfway, which they
  cover. Wading over takes about a second, in the gator's lane.
- **Steam:** the steam valve vents across the main and walls one archer off for 3 s, a voice play ("hit the valve!").
- **The gator's lane:** the main is its lane: 13 hexes of water, which it patrols between A's sump and the far end.
  Wick's corn, cast upstream, floats down the channel and holds it on the kernels for 4 s while Rebar wades to the
  bridge.
- **Shoves:** an archer on a 1.5 ledge is one shove from the water, and the water is the gator's.
- **What's different:** long sightlines (a main is one fog space, so the whole tunnel is in view), ranged enemies
  across water, and a crossing that has to be bought with a spell.

### How fights work in a sewer (all layouts)

1. **Everyone is slow in the water**, monsters too (0.75x). Monsters path the short way, so they wade; the crew can choose
   not to. **Dry ground is the high ground:** bridges, ledges, decks and islands.
2. **Fire changes.** Waders are soaked, so a fireball still does its 40 but sets nobody alight. Fire plays on the decks
   (drums, gas pockets, burning dry targets). Steam puffs over water are cosmetic.
3. **Shoves have destinations:** into the channel (slowed and soaked), into the gator's territory, over a bridge rail
   (1.5+), off a ledge.
4. **A neutral third party.** The gator nips whoever comes close, so it is a wall, a trap for the pack, and a hazard to
   the crew, and it moves.
5. **The water conducts.** A live wire or an eel turns connected water into damage. The crew stays dry or shuts a sluice.
6. **Long sightlines.** A flooded hall is one fog space, so you see the gator's wake and the archers at the far end
   before you commit.

### Generator implications of always-connected water

These are on top of round 1's list:
1. **Route channels per room** from its sewer doorways (the grammar above): a hex line between door cells through the
   centre, along the wall for adjacent corners, a Y for three doorways, a source or a culvert at the cluster's edge.
2. **Assert one body:** a flood fill over the cluster's wet cells reaches all of them, and every flooded hall touches a
   room channel at both ends. A `test_sewer` runs it over many seeds.
3. **Bridges by rule:** for each deck a channel cuts off that holds a doorway or a placement, pick a channel cell where
   both banks are dry full cells across the channel. If none exists, reroute. Bridges are a new **deck-level cell
   flag** over water: `ground_level` gives the deck for walkers, and the water body keeps the cell. Keep the lab's
   two-ends check as the assertion.
4. **Doors:** sluices at both ends of every flooded narrow hall; open arches on wide halls and mains; office doors on the
   dry halls leaving the cluster.
5. **Placement on dry cells only**, as round 1 said, plus:
   - explosives never on wet or rim cells;
   - archers prefer decks with water between them and the main doorway;
   - packs never on bridges;
   - bask spots are listed per gator (sumps, bends, mid-hall, dry deck cells beside water; never doorways or bridges);
   - the gator's home region is the wet cells plus the dry cells within 2.
6. **Hazard spawn data:**
   - each electrical panel's shock reach (a BFS of 8 wet cells, stopped by sluice cells);
   - gas pockets on sumps (one per cluster at most).
7. **Checksum:** body records, bridge cells, home regions, bask spots and shock reaches.
8. **Perf:** routing is a few hex lines per room; the flood fill and the BFS are a few hundred cells. Time it with the
   round-1 sewer pass (`last_sewer_usec`).

### Lab (round 2)

```
godot --path . --resolution 1920x1080 -- --scene res://scenes/sewer2_lab.tscn --case <case> --shot <png> [--view <name>] [--look brick|concrete|toxic]
```

- `scripts/art/lowpoly/sewer2_lab.gd` extends the round-1 lab.
  - Layout cases (views `game`, sometimes `game2`, and `plan`): `reclaim`, `junction`, `aquarium`, `loop`, `main`.
  - Fight cases (views `game` and `close`): `fight_shove`, `fight_wire`, `fight_ledge`.
  - Transition cases ("Scope and how a sewer fits a floor"): `trans_stair` (views `game`, `fog`), `trans_elevator`. The
    lab builds them with levels and STAIRS cells (`_make_map_levels`).
- The actors are static models: the heroes, `MonsterModels`, `EmployeeModel`, `NoteModels`, `PropModels`,
  `DecorModels`, `PoolProps` and `SewerProps`.
- New lab-only `SewerProps` kinds: `pump`, `junction_box` (with its cable, hanging or dropped), `gas`, `tool_cart`,
  `shock`, `steam_wall`, `corn_float`.

### Renders (round 2)

In `...\scratchpad\sewer\sewer2\`:

| File | What |
|---|---|
| `reclaim.png`, `reclaim_game2.png`, `reclaim_plan.png` | L1 Reclamation run |
| `junction.png`, `junction_plan.png` | L2 The Y junction |
| `aquarium.png`, `aquarium_game2.png`, `aquarium_plan.png` | L3 Aquarium overflow |
| `loop.png`, `loop_plan.png` | L4 Storm-drain loop |
| `main.png`, `main_plan.png` | L5 The sewer main |
| `fight_shove.png`, `fight_shove_close.png` | L2: Rebar shoves a skeleton into the gator's territory; the nip winds up |
| `fight_wire.png`, `fight_wire_close.png` | L3: the panel is shot; the shock runs 8 cells along the channel; Gasket dry on the bridge |
| `fight_ledge.png`, `fight_ledge_close.png` | L5: archers on the far ledge, a steam wall across the main, corn as chum |
| `bridge_fix_rooms.png`, `bridge_fix_junction.png` | the round-1 cases with the bridge fixed |
| `trans_stair.png`, `trans_stair_fog.png` | "Scope": option (a), the service stair down six levels into the first sewer room; the same in fog look A from the room above |
| `trans_elevator.png` | "Scope": option (b), the freight elevator opening onto a dry landing deck on a sewer floor |

### Questions for the user (round 2)

1. **Bridges as dry crossings** (deck-level over the water, the gator passing under, rails a 1.5 shove goes over), or
   decor you wade through as in round 1?
2. **Gator price $6,300** (a quarter less than the shark), or the shark's $8,400?
3. **Gator numbers:** watch 4.5, territory 3.0, nip 10 and a 1.6 shove after 0.5 s, relocating every 30-45 s, slower
   on land (1.4) than in water (2.4). Right feel?
4. **Shoving a gator:** hold it in place like the shark (proposed), or let a big shove move it, so the crew can push the
   gator into a pack?
5. **Live-wire reach:** 8 cells of connected water, stopped by a shut sluice (proposed), or the whole body (the whole
   cluster)?
6. **Sewer gas pocket:** a hazard that bills nothing (it isn't anyone's property), or bill it as "Sewer remediation"?
7. **Rats:** reskin the imp swarm for sewers (same numbers, swims slowly), or a separate swarm actor?
8. **Which layouts first?** Proposal: L2 (junction) and L1 (linear run), the generator's two basic shapes; then L4 (the
   loop needs a cycle in the cluster); L5 last (the 6.0 main is a new width).
9. **Employees prefer dry routes** when following (water costs x3 in their paths)?
10. **A gator on land dries out after 15 s and can be set on fire** (it then runs for the water), or is it always
    fireproof like the shark?

### Decided (user, 2026-10-20: answers to round 2)

| Question | The user | What it means |
|---|---|---|
| 1. Bridges | "Omit the bridges for now." | **No grate bridges in the build.** A deck cut off by a channel is reached by wading (the rim is a one-level step, walkable anywhere). Round 1's rule that "a dry walkway joins every doorway" becomes "**every doorway is reachable; dry where the layout allows**". The lab's bridges stay as look-dev, and `_check_bridges` stays for any bridge that comes back. |
| 2. Gator price | "6300" | **$6,300**, killed and billed once, to the killer. |
| 4. Shoving a gator | "gators can be shoved." | A shove **moves the gator like any body**. It is not anchored the way the shark is. The crew can push a gator into a monster pack, and it nips whatever is in its territory there, the crew included. See "Shoved gators" below. |
| 5. Live wire | "lets just have it distance based" | The shock reaches the water cells within **N cells of the cable's end, by distance** (proposed N = 5, about 8.7 units), and hits everyone standing in water there. There is **no sluice rule** and no flood fill. |
| 7. Rats | "Omit for now because it is either a new monster or environment decoration." | **No rats.** Sewer packs use the existing kinds, the imp swarm included, unchanged. |
| 8. Which layouts first | "You decide" | **L1, then L2, then L4, then L5** (below). |

Still open: 3 (the gator's numbers), 6 (whether the gas pocket bills), 9 (employees prefer dry routes) and 10 (whether
a gator on land can burn). Each keeps its proposal as the default until answered.

**The layout order, and why.** Each layout adds one new shape to the generator, so each step tests one thing:
1. **L1 Reclamation run:** a **chain** of rooms, which is what a path through DungeonGen's spanning tree already gives.
   It proves channel to hall to room continuity, a sump, a ledged wide hall and a room at the end (the pump room's
   drain).
2. **L2 The Y junction:** a room with **three doorways**, so the channel splits into a Y over a sump. Without bridges
   its wedges are islands you wade between, which tests the "no bridges" decision hardest.
3. **L4 Storm-drain loop:** a **cycle** in the cluster. That needs one of DungeonGen's extra loop links to fall inside
   the cluster, so its rooms and the gator's route round the ring are built from the generator's loops.
4. **L5 The sewer main:** a **new hall width** (6.0, the middle row wet) that DungeonGen doesn't make today.

L3 (the aquarium overflow) is L1's chain with a different source and a ring channel. It comes with L1 as a theme
variant, not as a step of its own.

**Shoved gators** (the decision, worked through):
- **The shove:** `Actor.shove` as for any body: its slide, a wall slam (8 damage, billed to nobody: hits are free), and
  a shove into a priced prop or an explosive as for anyone. A client's shove is a request (`Net.route_shove`); the host
  moves it and streams it.
- **It riles the gator.** A shove counts as a hit: its territory grows to 4.5 for 8 s and the first nip goes to the
  nearest body where it lands. That is the play: shove it into the pack and it bites the pack. It is also the risk.
- **The risk of a shove onto the crew:**
  - A short shove (Rebar's fist, 1.6) or one at a bad angle leaves it inside the crew's 3.0, riled, so it nips a
    hero.
  - A brute's slam (shove 1.0 in radius 2) and an explosive's blast move it too, so the pack and the room can push a
    gator onto the crew.
  - AI allies already treat it as a priced prop: they keep it out of their spins, bowls and shoves (`prop_care`).
  - Nothing stops a player doing it, and that is the joke.
- **Getting home:** its **home region** is the cluster's wet cells plus the dry cells within 2 of water.
  - Shoved out of it (through a doorway into a dry room, or down a dry hall), it switches to MOVE.
  - It paths back (`find_path`, land speed 1.4) to its nearest bask spot, with its territory at 2.0 and nipping only
    what touches it.
  - Shoved within the region (onto another deck, into another channel), it stays and settles there. That spot is its
    new resting spot until the next relocation.
- **Stuck on land:** if no path home exists (a platform it can't climb down from, an island of dry floor), it **settles
  where it is**. That spot becomes a temporary bask spot, and it tries again at each relocation (30-45 s). It never
  teleports: a client would see it jump.
- **Into a pit or off a high edge:** the void rule. It falls and dies, and the kill **bills $6,300 to whoever shoved
  it**. That is `PricedProp`'s culprit rule and the same as killing it any other way. It is a money call, and the
  doc's warning line for the user.
- **Size:** M on top of the gator actor: the riled-on-shove rule, the out-of-region return, the stuck fallback, the
  void bill, and their tests (shove it out of a doorway and it walks home; shove it onto a platform and it settles;
  shove it into a pit and the shover is billed once).

---

## Scope and how a sewer fits a floor

The user, 2026-10-20: "lets look at the scope before we build it. And how would sewers fit into a level, do we need a
transition? Is that transition mid-level or right at the elevator?"

Two mock-ups at the game camera, in `...\scratchpad\sewer\sewer2\`:
- `trans_stair.png`, `trans_stair_fog.png`: option (a)'s service stair, then the same view in fog look A from the
  stair head;
- `trans_elevator.png`: option (b), the elevator opening onto a sewer floor.

### How a sewer fits a floor: the options

What exists today:
- **A floor** is 6-9 DungeonGen rooms on a spanning tree with 1-2 loops.
- **Heights:** each room has a base level (0-8), and the links between rooms step with terraces and **STAIRS cells**
  (rise up to 4, chained).
- **Floor 1** has the van. Floors 2 and 3 start in the elevator. The elevator is the exit on every floor, and its room
  stays clear of packs.
- **Transitions** need nothing new: a STAIRS link is already a transition, and a drop of up to 3 levels is already a
  one-way edge (`exploration.md`).

| | (a) **A cluster mid-floor, down a service stair** (recommended) | (b) **The whole floor is the service level** | (c) **The sewer is the route between two halves** | (d) **A one-way drop in** (a variant, added to a or c) |
|---|---|---|---|---|
| **What it is** | 2-4 of the floor's rooms form the cluster, at one base level **4-6 levels below** the room they hang off | every room of the floor is a sewer room; the elevator opens onto a dry landing deck in the first one | the cluster sits on the start-to-exit path, so the crew has to cross it | a broken drain grate or a collapsed floor in a dry room drops 3 levels into a channel |
| **The transition** | a **service stair**: the link into the cluster is a narrow dry hall of STAIRS cells (two flights of 2-3 levels). At its head stands an office door styled as a **service door** (hazard stripes, a "SERVICE LEVEL" stencil), at its foot the first sewer room's dry deck. The stair is never wet | **none on the floor**: the elevator ride is the transition. The sign-in sheet's row says "Service level" | two service stairs, one down and one back up | the drop itself, with a dangling grate and water pouring down |
| **One-way?** | **two-way**: walk down, walk back up | the elevator as usual | two-way | **one-way**: you can't climb 3 levels. It is a shortcut **in**, and the stair is still the way out |
| **Fog look A** (`trans_stair_fog.png`) | the stair is its own hall space. From the room above, the stair is in view through the open door and the sewer room below is **next**, a dark silhouette with its channel traced. Step onto the stair and the room comes into view through the doorway at the bottom. **The service door is the threshold**, and from the room above the drop in height is what says "down" | an ordinary floor's fog, every space a sewer space | as (a), both ends | the drop's room is next from the edge; you see where you'll land before you jump |
| **Objectives** | gates, packs and employees are planned across the whole floor as now, so **a gate or staff may be down there**. That makes going down a money call, and leaving it a choice. The elevator, its landing and the van are never in the cluster | everything is wet: every gate, every pack, the origin gate on floor 3 in a cistern. Every fight is a sewer fight, fire is weak all floor, and there are 2-3 gators | **the escort is the challenge**: staff from the far half have to be brought through the water, at 0.75x, past the gator | as (a) |
| **Dispatch line** (new; each needs a rendered clip) | at floor start: "There's a service level under this floor, down the maintenance stairs. It floods." | at arrival: "This floor's the service level. Everything down here is wet." | at floor start: "The only way to the elevator is through the service tunnels." | none (the drop is found, not announced) |
| **Sites and clients** | prepper's bunker (water reclamation), supervillain's lair (the lair's sewer), tech founder (cooling culverts); floors 2-3 | the prepper's "sublevel B" or the lair's lower level, as a rare floor style | bunker wings joined by a utility tunnel; lair | any of a's sites |
| **Generator cost** | the cluster choice, one stair link, flattening the cluster's own links | a whole-floor builder; the lava prototype shows the hand-authored version | as (a), plus the cluster has to be a cut vertex of the tree (only one way through) | a 3-level edge between a dry room and the cluster: a placement rule |
| **Risk** | none new | monotony: the sewer is special because it is under a dry floor; and every escort is wet | a forced wade every time on those floors; escorts get hard | a crew can split, one player jumping in alone |

**Recommendation: (a), a cluster mid-floor down a service stair, on floors 2-3. Not at the elevator.**
- **Why mid-floor:**
  - The sewer reads as a place **under** the client's property that you choose to go into. The contrast with the dry
    floor above is the point.
  - The elevator room stays as it is: dry, no pack, the landing clear. Drop-offs at the elevator (within 2.5) stay
    quick, and nobody has to escort staff through the water to get out.
- **Why a stair, not a hatch:**
  - It is two-way. Nobody gets stuck downstairs, and the crew can retreat up it.
  - It is terrain the generator already makes (STAIRS cells).
  - A narrow stair is a natural chokepoint to fight from.
- **Placement:** the cluster hangs off the floor by **one** stair link in most floors, as a wing holding a gate or staff
  (the money call). Variant (c), the cluster on the only path, comes later, once escorting through water has been
  played.
- **(d), the drop-in,** is a cheap later addition to (a): one placement rule.
- **(b) is the first playable slice**, not the shipping form. A hand-authored whole floor behind a dev flag needs no
  generator, exactly like `--lava-cave N`.
  - The elevator lands on a dry deck in the first room (`trans_elevator.png`).
  - Once (a) is in the generator, (b) can stay as a rare "service level" floor style if the playtest likes it.

### Build scope

S is under a day of agent work, M a few days, L a week or more. "Slice" marks what the first playable version keeps.

**Terrain and drawing**

| # | Piece | Size | Slice |
|---|---|---|---|
| T1 | **Water up to a wall** in `HexMap`/`HexMapView`: a cut cell with both wall kites and pool kites (today `_add_pool_cell` returns before the wall part), `water_at` true on its pool kites, and `test_wall_mesh` over the mixed masks | M | **cut**. The lab just sinks a wet cut cell and draws the water over it. The cost is a one-kite notch where a rim meets a wall, and `water_at` false on those half-cells (nobody standing against the wall counts as wading). Fine for a playtest |
| T2 | **Water bodies:** non-convex water as cells; body records `{id, cells, surface, flow, look}`; a `SewerView` that draws the water per kite, the foam, the kerbs and the flow (the lab's `_build_water`, about 120 lines) | M | **keep** (as the lab's drawing, ported) |
| T3 | The channel bed and liner shader and the three looks (brick, concrete, toxic) from the lab | S | keep one look (concrete) |
| T4 | The checksum: body records, home regions and bask spots in `NetFloor.map_text_of` | S | cut (solo slice) |

**Generator**

| # | Piece | Size | Slice |
|---|---|---|---|
| G1 | **Cluster choice in DungeonGen**: 2-4 rooms on tree links, floors 2-3, never the start or exit room. They share one base level 4-6 below the room they hang off. Their own links are flattened (no terraces), and the link in becomes a **service stair** (STAIRS events on a narrow link). Its own seeded rng, so floors without a cluster are byte-identical (the golden-floor test) | L | cut (hand-authored) |
| G2 | **SewerGeo:** routing each room's channel by the grammar (straight, bent, along the wall, a Y, a source, a culvert); flooding halls by width; sumps; the 45 % water cap; the **one-body assertion** | M | cut (the five lab layouts, hand-authored) |
| G3 | **Doors:** sluice gates on flooded narrow halls (the office door's behaviour, the sluice's look); the service door at the stair head (an office-door style) | S | keep the sluice look only |
| G4 | **Staging rules** in the planners: dry-only placement (exists); explosives never wet or on a rim; archers on decks across water; the gator's bask spots and home region; panels within 2.5 of water | M | hand-placed |

**Actors**

| # | Piece | Size | Slice |
|---|---|---|---|
| A1 | **The gator:** a `Monster` subclass; land and water movement in its home region; watch, territory, nip; riled; relocation; billing ($6,300 once, never toward Exterminate); fog group; AI allies' prop care | L | **keep** (solo: no net) |
| A2 | **Shoved gators:** riled on a shove, walking home when shoved out of its region, the stuck fallback, the void bill | M | keep |
| A3 | **The gator's look:** the lab model as a game model (triangle budget, z-fight registry), a bending body (SharkBody's follow-the-leader), a wake in water and footprints on land, the tells (eye glow, gape) | M | keep (no footprints) |
| A4 | **The gator's net shape:** a MONSTER stream entry, `world.windup` for the nip, `world.die`, the Ledger line, shoves as requests, late join (keyframe; a dead one is a gone id), `NetEvents` carriers, a 3-process test | M | cut (solo) |
| A5 | Eels as actors (a shock within 6 along the water) | M | cut (later) |

**Props and hazards**

| # | Piece | Size | Slice |
|---|---|---|---|
| P1 | **Sump pump**, priced $3,500 (the lab model) | S | keep |
| P2 | **Electrical panel** ($250) and the **live wire**: a host-arbitrated box; the drop (0.6 s); the shock to waders within N cells of the cable's end (12, x1.5 soaked, a 0.6 s daze), both sides, a scheduled effect each owner applies; one use | M | keep (solo) |
| P3 | **Steam valve** across a hall or main: needs the dynamic line-of-sight blocker `combat-proposals.md` §4.4 asks for | M-L | cut |
| P4 | **Gas pocket** (fire sets it off: a 3.0 flash) | S-M | cut |
| P5 | The **decor kit** into the game: outfall, pipe bundle, grate, sluice, springer, wall ladder, bars, duck, tool cart (DecorModels entries, the z-fight registry) | S-M | keep the six that read most: outfall, pipe bundle, grate, sluice, bars, tool cart |

**Content and tests**

| # | Piece | Size | Slice |
|---|---|---|---|
| C1 | Sewer room themes (cistern, outfall room, junction, pump room, aquarium overflow) as `RoomThemeDefs` rows with their props, decor and looks | S-M | cut (hand-placed) |
| C2 | **Dispatch lines** (3-4) in `NoteCopy`, rendered clips (`tools/render_dispatch.ps1`) | S | one line |
| C3 | Notes ("DO NOT DRINK", "GATOR CROSSING", the feeding rota, the pump log) and the new staff names | S | the two signs |
| X1 | `test_sewer_geo`: one body, every flooded hall meets a channel at both ends, doors, the water cap, many seeds, the timing (`last_sewer_usec`) | M | cut |
| X2 | `test_gator`: territory, nip, relocation, shove and return home, stuck, the void bill, billed once | M | keep |
| X3 | `test_live_wire`: the distance reach, both sides, dry ground safe | S | keep |
| X4 | `test_net_gator`, `test_net_live_wire` (3 processes, `off` and `coast`) | M | cut |
| D1 | **`--sewer N`**: the five lab layouts (bridges removed) built as whole floors, solo only, ignored in a shared run, like `--lava-cave N` | M | **this is the slice** |

**Phases**
1. **Slice, solo, behind `--sewer N`** (about 2 weeks of agent work; M-L):
   - D1, T2, T3 (concrete), G3 (the sluice look), A1-A3, P1, P2, P5 (the six), C2-C3 (a line, two signs), X2, X3.
   - The question it answers: is wading plus a territorial gator plus a live wire fun?
   - It needs no generator and no net, and touches `game.gd` in one hook (as the lava cave does).
2. **Networked** (M): A4, P2's net half, X4, T4.
   - The gator becomes a host-owned actor that late joiners get.
   - Its shove is a request. It plays in a crew, still on the hand-authored floors.
3. **In the generator** (L, after the refactor's waves 3-4):
   - G1, G2, G4, T1, C1, X1, and the dispatch lines.
   - Option (a) with a service stair, floors 2-3.
4. **Later** (each S-M): the steam valve (P3, with the line-of-sight blocker), the gas pocket (P4), eels (A5), variant
   (c), variant (d), and (b) as a rare floor style.

**What the slice can skip and still be honest:**
- T1's wall-meets-water cell (a visual notch);
- the checksum and net (solo);
- the generator (hand-authored);
- steam, gas and eels;
- every theme but one look.

What it cannot skip:
- the gator's territory, nip and shove behaviour;
- the live wire;
- the water drawn connected through rooms and halls. That is the point the user made, and the playtest has to show it.

### Coordination with the refactor (`docs/design/refactor-plan.md`)

The refactor will split `game.gd` (H7), split `SiteBuilder` into per-feature planners (H8) and add `MonsterDef` units
(H3). The sewer is written against that structure:

| Sewer piece | Lands in | Notes |
|---|---|---|
| `--sewer N` and its floor hook | **`scripts/app/dev/`** (H7 step 1) and a `FloorStart` hook, the same shape as `_lava_cave()` | wait for wave 3 (H7 step 1) to land first; everything else in the slice is new files |
| Cluster choice and the service stair | **DungeonGen**, not a planner: heights and STAIRS links are made before `SiteBuilder` runs. A `sewer` option on `DungeonGen.generate` picks the cluster after the base levels, with its own seeded rng | outside the planner registry; the golden-floor test must stay byte-identical with the option off |
| Channels, flooding, bodies (G2) | **`SewerPlanner`** (H8), run where `PoolGeo.carve` runs today (right after the themes, before props): `plan(p, ctx)` writes the wet cells, the body records and the sluice flags into the plan; `spawn` draws `SewerView` | a planner that changes terrain, like the pool carve today; register it before the props planner |
| The gator | **`GatorPlanner`** (H8, next to `SharkPlanner`): the home region, bask spots and the spawn | spawn order (= net-id order) after sharks, in the ordered registry |
| The gator kind | **`MonsterDef` "gator"** (H3): script `gator.gd`, the model builder, the triangle budget, `pack_role` = special (seed-built: never in a pack and never from a gate), no pest name or ticket, `planner` = GatorPlanner, and a **price** field for billed property | the shark should get the same `price` field; both are property, not pests |
| Pump, panel | the props planner's `TABLE` rows now; they become **prop defs** when H4 (wave 7) lands. The panel's blast-free hazard data lives with its def | the panel is a host-arbitrated object; if H5 lands first it implements that interface |
| Live wire, sluice styling | the **hazards planner** (placement: walls within 2.5 of water) and the **doors planner** (a `style` on flooded narrow halls) | |
| Sewer themes | `RoomThemeDefs` rows (H4 moves floors and walls into the theme row) | |
| The lab | `sewer2_lab.gd` moves onto `LabBase` (H9) with the other labs | |

**Order:**
- Phase 1 (the slice) can start now in new files (the gator, `SewerView`, the panel and live wire, the hand-authored
  layouts). It adds one hook to `game.gd` after wave 3.
- Phase 3 (the generator) waits for waves 3-4 (H7 step 1, H8 and H3). That is the refactor plan's own advice: "Do this
  before lava and the sewer go into the generator."

## Phase 1 as built (2026-10-20)

The solo slice: option (b) as a dev flag, the five round-2 layouts built as whole floors with the bridges removed, the gator,
the sump pump, the electrical panel and its live wire, and the decor kit. No generator, no networking.

### Play it

```
.\run.ps1 --sewer 2 --spells damp,fireball --no-mic
```

- `--sewer N`: **1** L1 Reclamation run (bunker, concrete), **2** L2 The Y junction (lair, brick), **3** L1's layout in the
  toxic look, staged for a lair (L3 as L1's theme variant), **4** L4 Storm-drain loop (bunker, concrete), **5** L5 The sewer
  main (lair, brick). Every floor of the contract is that layout.
- The flag starts the contract on **floor 2** (unless `--floor` says otherwise), so the crew rides the freight elevator down
  and steps out onto the layout's dry landing deck. The landing is the exit: E there opens the elevator menu as usual, and
  the next floor is the same layout again.
- Solo only in phase 1; since phase 2 a crew too, every window with the same flag ("Phase 2 as built").
- Screenshots: `--sewer-demo overview|gator|nip|wire|sluice[:n]|outfall[:n]` (with `--demo-after S`): the crew on the
  first room's deck and the camera on the layout; the gator relocating at once with the camera on it (it swims, climbs
  out and walks); the player stepping into the gator's territory; the crew by a panel, the player breaking it; the player
  wading through a sluice doorway; the camera on an outfall.

**What to try:**
1. **Wade.** Every channel is one body of water: 0.75x, soaked (a fireball fizzles on you, a fire goes out).
2. **Walk up to the gator.** Inside 4.5 of its head it turns to watch you, eyes bright. Step inside 3.0 and stay 0.4 s:
   it gapes (0.5 s, the orange pulse) and nips: 10 and a 1.6 shove away. It nips skeletons too: lead the pack past it.
3. **Hit it** and it is riled for 8 s: its territory is 4.5 and it advances up to 2.0 toward you, once.
4. **Shove it** (Rebar's fist, Gasket's spin, tentacles, a fireball's blast): it slides like any body, riled, and its first
   nip goes to whoever is nearest where it lands. Shove it into the pack. Shove it out of the water into a dry room and it
   walks home; shove it off a ledge into nothing and it dies, and you pay $6,300.
5. **Kill it** and the invoice says Gator $6,300, to whoever landed the kill.
6. **Corn in its water** (within 6 of it) holds it on the kernels for 4 s, no nips.
7. **Wait 30-45 s** with nobody near it: it moves slowly to another bask spot. The lane that was safe isn't.
8. **The electrical panel** ($250, any hit breaks it: an arrow, a swing, a blast). The cable drops into the water 0.6 s
   later and shocks everyone in the water within 5 cells of where it lands: 18 (12 x1.5, waders are soaked) and a 0.6 s
   daze, then 9 every 1.5 s for 6 s. Dry ground is safe. Shoot it when the skeletons are wading, not when Rebar is.
9. **The sump pumps** are $3,500 each, and they stand right where the fight is.

### How it is built

| Piece | Where | Notes |
|---|---|---|
| The layouts | `scripts/world/sewer/sewer_layouts.gd` (`SewerLayouts`) | The lab's builder made game-ready: hex-blob rooms, halls cut as DungeonGen cuts them (narrow, wide, a 6.0 main), midpoint walls; wet cells sunk one level (wading depth). Each layout adds a dry landing room (radius 4) with a free-standing elevator (`ElevatorGeo.make_free`, door toward the camera) and a dry hall to the first sewer room. The water is a `HexMap.pools` record with `body: true` (Wading slows and soaks in it; PoolView skips it). `plan()` makes a minimal `SitePlan` (rooms, start, exit, the elevator, props, explosives, decor, notes, the employee) that `SiteBuilder.spawn` puts in the world. Props and explosives are placed against a wall and slid along it until their whole footprint is dry deck (`_dry_wall_spot`). Deterministic |
| **Water up to a wall** (T1) | `scripts/world/hex_map_view.gd` `_add_pool_cell` / `_add_wall_part` | A cut cell may now have pool kites: its wall part is drawn as on any cut cell (its faces on the wall lines run down to the pool floor beside a pool kite), its pool kites as pool floor, the rest deck; a liner only between pool and deck kites. `HexMap.water_at` was already per kite, so wading reaches the wall. No change to normal floors (no generated cell has both masks). `test_wall_mesh` covers every wall mask with water on all its open kites and on one |
| The look | `scripts/world/sewer/sewer_view.gd` (`SewerView`) | The lab's drawing, ported: the water as a fan per pool kite (flow streaks), foam on every water edge, a kerb on every rim, the channel bed and liner shader in place of the pool tiles, the look's floor and wall colours (a brick pattern for brick), the light. Three looks: concrete, brick, toxic. The live wire's flash on the water |
| Fog | unchanged | RoomFog / FogView look A as on every floor (long-hall cuts on); the gator hides like any mover (group "sharks", a FogView dynamic group) |
| **The gator** | `scripts/monsters/gator.gd` (`Gator extends Monster`), `MonsterDefs` "gator" (`billed`: $6,300) | Host-owned actor, team NEUTRAL, groups "gators", "sharks" (the priced water creatures: monsters shrug off its bites, archers don't practise on it, the bowl bills it, fog hides it) and `PricedProp.GROUP`; not "monsters". No pack, gate, model or pest row: never from the factory. Its home region (`Gator.region_of`: the water and the cells within 2) and bask spots are spawn data from the layout. States CALM / RILED / NIP / MOVE / DEAD / WATCH / HELD / CHUM ride `state` (3 bits). Its own pathing inside the region for relocations (a BFS over its walkable cells), `find_path` to walk home. Its speeds ignore the wading slow (2.4 water, 1.4 land; relocating 1.2 / 0.9). Fireproof in the water and for 15 s after; burning on land it runs for the water |
| Its look | `GatorModel` at 1.3 (V3 Mugger, `gator-look.md`; it replaced the lab's `SewerProps` "gator", 2026-10-20) | Toon material (`MonsterMaterial`: ink outline, amber rim), the ember eyes its monster glow (`glow_gain` by state: half lit calm, bright watching, hot nipping). A rigid-part rig posed every frame (`Gator._pose_rig`): the curl from its turning, the swim S-wave, the high walk on land, a breath, the head tracking what it watches, the jaws through the wind-up and the gape, a tail thrash when riled; a V wake and a ripple on the water. Z-fight clean (its poses in `ZFightModels`) |
| The props | `PricedProp.TABLE` "sump_pump" ($3,500, HP 70) and "electrical_panel" ($250, HP 1), site "sewer" (no site's catalog has them) | Models: `PropModels` builds them from the lab's `pump` and `junction_box` |
| The live wire | `scripts/world/sewer/live_wire.gd` (`LiveWire`), a child of each panel | On the panel's `broken` (billed to the breaker like any prop): the cable swings down (0.6 s) to the first water in front of the panel, then the shock: everyone standing in water within **5 hex cells** of the drop (`Combat.hits_in_radius`, then the hex distance and `water_at`): 12, x1.5 soaked, a 0.6 s daze (by the target's owner); then 6 (x1.5) every 1.5 s for 6 s; one use. Its damage is credited to the breaker (a gator it kills bills them) |
| Decor | `RoomThemeDefs.DECOR` + `DecorModels`: outfall, pipe_bundle, grate, sluice, bars, tool_cart | The six from the scope, built from `SewerProps`; the sluice gates stand in the flooded doorways as decor (no door behaviour). Since the playtest fixes below, the gate is wound up overhead (style "roof") and the outfall pours a stream that reads as falling water. In the z-fight registry with every other decor kind |
| Staging | `scripts/app/dev/sewer_dev.gd` (`SewerDev.stage`) | Round 2's lists without rats, eels, gas pockets, steam or bridges: skeletons on the decks and one or two wading, archers on decks across the channels (L5: the main's far ledge), a brute, a goblin scout on a wide hall's ledge (L1, L4) or at his post (L5), one gator, one employee (Stan in the bunker, Gary / Keith / Nigel on pump duty in a lair), notes (the signs DO NOT DRINK, DO NOT FEED THE GATOR, LEVEL RISES WITHOUT WARNING, GATOR CROSSING; the feeding rota, the pump log, the aquarium complaint), the pumps, a panel in every layout, explosives on dry decks, the villain's tanks and lockers in the lair layouts. Their pest-kind monsters count toward the floor's pest objective |
| The flag | `scripts/app/dev/game_dev.gd` (`GameDev`): `_parse_args` (SewerDev.parse), `_dev_floor`, `_spawn_near`, `_dev_on_floor_ready` | `game.gd` gained ONE hook, `_dev_floor()` (a call after the plan in `_build_world` and its no-op), where GameDev swaps in the layout's map and plan |
| Corn | `scripts/spells/corn_strike.gd` | One line beside `Shark.corn_at`: `Gator.corn_at` (chum) |
| Tests | `tests/test_sewer.gd` | Every layout: the same map every build, ONE body of water, every flooded hall joining two rooms' channels, water up to the walls, everything staged reachable from the landing, the employee and notes on dry floor, the gator's spots walkable inside its region, every panel with water to drop into. The gator: watch without nipping, the nip's timing, damage and shove, monsters nipped, one victim a nip, relocation (never leaving its region), shoves (settles riled inside its region, walks home from outside it), no way home (settles, never teleports), a 60 s run never stuck, chum, kill and bill once, the pit kill billed to the shover. The live wire: the bill, the drop's 0.6 s, 18 and a daze within 5 cells, both sides, a wader 7 cells away and the dry floor untouched, the pulses, one use |

### Decisions made in the build

- **The crew arrives on floor 2.** The flag defaults the contract to floor 2 so the elevator ride is the transition (option
  (b)); `--floor 1` starts on the landing deck with the elevator shut.
- **A shove riles the gator without the advance.** A hit riles it and it advances up to 2.0 toward the attacker; a shove
  riles it and sends its first nip to the nearest body where it lands, but it does not walk back toward the shover (the
  play "shove it into the pack" needs it to stay there). After an advance it rests where the advance ended.
- **Its body is a circle.** Its collision is a 0.55 circle round its shoulders, its jaws 1.15 ahead (the head 0.9 ahead is
  where its territory and watch are measured from); the 3.0 body is the look.
- **A panel in every layout.** The doc puts one in L1 and L3; L2, L4 and L5 got one too (the pump post, the valve room,
  the cistern's west wall), so the live wire can be tried on every layout.
- **The shock reaches 5 hex cells** (`Hex.distance`) from the cell the cable lands in, only bodies standing in water, and
  the pulses keep the x1.5 for the soaked.
- **The gator shares the sharks' group** for the four places that treat a shark as priced water life (monsters ignore its
  bites, the archers' practice, the bowl's bill, the fog), rather than editing each of them; it has its own "gators" group too.
- **One look per layout** as in the lab (L1, L4 concrete; L2, L5 brick; L3 toxic) rather than only concrete: the looks
  are data.

### What phase 2 (networking) still needs

All of it is built: "Phase 2 as built" (2026-10-21), after Phase 3.

- The gator: its MONSTER stream entry (it has no OWNER var beyond Monster's, so the monster carriers hold), `world.windup`
  for the nip with each client resolving it on its own hero (`Monster.net_strike` calls its `_strike`), a client's shove as
  a request (`Actor.shove` already routes a copy's), `world.die` and the host's Ledger line, `Gator.corn_at` on the host
  only, the late-join keyframe (its `NetEvents.LATE_JOIN` entry is written), its spawn data (home region, bask spots,
  seed) in the floor checksum, `test_net_gator` (three processes).
- The live wire: the panel's break is an `obj.break`; every machine runs the drop, the shock and the pulses from the break's
  shared moment (the code already applies each hit only where it resolves); `test_net_live_wire`.
- The water body record and the layout in `NetFloor`'s checksum, and the flag allowed in a shared run.

### Playtest fixes: the sluice and the outfall (2026-10-20)

The user, playtesting `--sewer 2`:
- "The gates with the red wheels and what look like pipes also don't read well because you walk through them. Just skip
  the pipes or stack them horizontally, like a roof you can't see under."
- "Also - the pipe in the sewer map, I can't tell what it is doing. There are horizontal lines coming out. Is that water?"

What changed (`SewerProps._sluice` / `_outfall` in `scripts/art/lowpoly/props/sewer_props.gd`). The shots are taken at the
game camera, before and after, in `sewer_fixes/`; `sheet.png` shows them all:
- **The sluice: nothing in the opening at body height.** The old gate's plate hung at waist height across the doorway
  (open 0.45), its posts stood just inside the jambs and the lintel sat at head height, so heroes waded through all three.
  Two styles were built (`SewerProps.build("sluice", {"style": ...})`):
  - **B "roof" (the default, the game's look):** the gate is wound fully up. The jamb posts stand flush in the walls'
    line (a dark guide slot and hazard bands on them), and a steel header with hazard chevrons sits on them at the wall
    top (1.5 over the deck, 2.0 over the channel floor; a wader's head is about 1.3). On the header, stacked horizontally,
    are the raised rusted plate, a pipe along its back and the red wheel lying flat. At the game camera it hides no more
    than an office door's header does.
  - **A "skip":** no header. Only the jamb posts in the walls' line remain, a little taller, with a gearbox and the red
    wheel on one of them.
  - Why B: at the game camera B still reads as a gate across the doorway (a lintel with chevrons, the raised plate and
    the wheel, like an office door's header). A, at the overview zoom, is a lone valve post beside an open doorway. The
    old look stays selectable as `"plate"` for the labs.
  - The sluice is decor that blocks nothing (`RoomThemeDefs` "sluice": `blocks: false`), so heroes, monsters and the
    gator walk through the doorway as before.
  - `DecorModels` passes the decor's `style` param on, so a layout can choose a style per placement (`SewerLayouts._sluice`
    gives none: the default).
- **The outfall: the stream reads as falling water.** The old stream was seven slabs in two alternating tones, so it
  looked like horizontal bars. It also ended above the water. The new stream:
  - one continuous ribbon in one water tone that arcs off the lip and falls into the channel (it runs on under the
    surface, 0.14 under the deck);
  - pale streaks running down the fall;
  - white water where it lands: a boil of foam, spray, a foam ring and a broken ripple ring on the surface.
  - A concrete headwall now holds the pipe, because the room's walls are cut low for the camera and the pipe used to
    float above them.
  - It is static: the decor kit has one material and no animation hook for a decor model. An animated scroll down the
    fall would need its own shader and is left for later.
  - Checked in L2 (brick) and L4 (concrete). The user allowed dropping the outfall if the stream still didn't read (the
    water would come from "under" for now). It reads, so the layouts keep it.
- Screenshots: `--sewer-demo sluice[:n]` (the player wading through the layout's n-th sluice doorway, Rebar just beyond it)
  and `--sewer-demo outfall[:n]`, with `--zoom 10 --no-fog` (`GameDev._sewer_demo`).

### Known limits

- Water drawn per kite has no seams to hide: where a channel turns at a room's border the rim keeps a short diagonal kink.
- The relocation's "within 14" is the walking length inside the region; on the biggest layouts some bask spots are out of
  each other's reach, so it shuttles between the near ones.
- The goblin scout on a ledge walks the ledge's middle; a 6.0 main's ledges are half rim cells, so in L5 he holds a post.
- No footprints on land, no eels, rats, gas pockets or steam (the scope's cuts).

## Phase 3 as built (2026-10-20)

The user's decide-now answers: phase 3 next, sewer before lava, and a **cluster of 2-4 rooms on some lair and bunker floors
(floors 2-3), reached by a service stair; the rest of the floor stays normal**. Option (a) of "How a sewer fits a floor".
Solo runs only when built: a shared run got no cluster until phase 2 ("Phase 2 as built": now it gets the same one).

### Play it

```
.\run.ps1 --seed 5 --floor 2 --spells damp,fireball --no-mic                         # a natural cluster (prepper, bunker)
.\run.ps1 --seed 5 --floor 2 --spells damp,fireball --no-mic --to-sewer foot         # ... starting at the stair's foot
.\run.ps1 --sewer-floor --seed 12 --spells damp,fireball --no-mic --to-sewer head    # force one on any floor
```

- **Natural seeds** (contract seed N = `--seed N` with `--floor`/`--spells`, `ContractBoard.run_for_seed`): floor 2 of
  seeds **2, 3, 5, 6, 7** has a cluster (5: the prepper's bunker, two rooms, a pump room with two pumps and the panel; 3:
  the founder's toxic culverts; 6: the supervillain's brick). The log names the cluster's rooms and the stair's head
  ("sewer cluster: ...").
- `--sewer-floor` (`SewerDev.parse`, `SewerCluster.force`): every floor of a solo job gets a cluster wherever a wing of
  rooms fits, whatever the site, floor or roll; it starts the job on floor 2 unless `--floor` says otherwise. Never in a
  shared run.
- `--to-sewer head|foot|sump[:n]`: the crew starts at the head of the service stair (default), at its foot in the first
  sewer room, or in sump n's water (the planner's order, 0 first).
- What is there: the stair down (a hall of STAIRS cells), a goo imp pack on a deck by the water, a sign at its foot ("RECLAIMED WATER: DO NOT DRINK" in a bunker,
  "DO NOT FEED THE GATOR" in a lair), the rooms flooded by one connected channel, flooded narrow halls with sluice gates at
  both ends, ledged wide halls, a gator (two in a cluster of four rooms), the electrical panel by the water (shoot it when
  the pack wades), sump pumps ($3,500) in the room farthest from the stair, sometimes an oil drum on a deck, and the
  floor's own packs, gates, staff, notes and mail wherever the planners put them, on the dry decks.

### How it is built

| Piece | Where | Notes |
|---|---|---|
| Which floors | `scripts/world/sewer/sewer_cluster.gd` (`SewerCluster`) | `seed_for(run, floor, shared)`: floors 2-3 (`FLOORS`), bunker and lair (`SITES`: every client today), `RATE` **0.5** on dice of its own (`floor_seed * 6151 + floor * 389 + 23`), 0 in a shared run while `NETWORKED` is false. The look per client: concrete (bunker), brick (lair), toxic (the tech founder) |
| The cluster | `DungeonGen` "sewer" option (`for_run(run, floor, shared)` passes it) | After the tree and its base levels: a **wing** of the tree (a room and everything beyond it from the start: 2-4 rooms, at least three rooms left outside) hanging off a room high enough. Its rooms drop to one level `DROP_MIN..DROP_MAX` (3-5) below that room (at least level 1: the water is one level lower). Its own links are flat; a loop between two of its rooms is cut flat (never the climb shortcut); a loop from it to the rest is not cut, so the **service stair** (the tree link in: flights of STAIRS cells, at most 3 levels a cell, no terraces) is the one way in. No raised features or pits in its rooms; never the start or the exit / elevator room. Its own dice (`srng`); the main dice draw as without the cluster (the flattened links' profiles drawn and thrown away, the skipped features rolled), so the floor around mostly stays as it was. `HexMap.sewer` holds the record (rooms, level, seed, stair, halls with route / lanes / cells / narrow, every doorway) |
| Byte-identical floors | `DungeonGen.generate` | Each attempt tries the cluster first and on any failure (no wing, no straight run for the stair, validation) builds the attempt without the option, so a floor without a cluster is exactly today's floor (`test_sewer_gen`, every floor; `test_golden_floor`) |
| The water | `scripts/contracts/planners/sewer_planner.gd` (`SewerPlanner.plan`) | **First** in `SiteBuilder.plan`, before the gates (the doc proposed where `PoolGeo.carve` runs; the channels are fixed by the doorways, so everything else must see them: the gates and the staff now refuse pool cells, which changes nothing on a floor without one). Narrow halls flooded wall to wall, wide halls their route row and the cut row beside it (the lane is a 1.5 dry ledge). Each room: a sump in the middle (radius 1, 2 in a room of 140+ cells, smaller if over `WATER_CAP` 45 %), a hex line (or the shortest walk inside the room) from each sewer doorway to it; an edge room (one sewer doorway) carries on to the wall farthest from it: the **source** (an outfall) in the edge room farthest from the stair, a **barred culvert** in the others. The stair's doorway and the cells within 2 stay dry. Wet cells sink one level, dry neighbours get pool kites (PoolGeo's rule, water up to the walls as in the slice); ONE `HexMap.pools` record with `body` true. No dice |
| Room theme | `RoomThemeDefs.THEMES` "sewer" (`SEWER`), `SewerPlanner.theme` | The H4 theme row: "Service level", note word "service level", flagstone floor and rough-stone walls, its downlight, the wet-floor sign as its recipe; not in any site's `POOLS` (only the cluster gets it), so PoolGeo never carves a pool there. Its halls and the walls round it are stone too (`SewerPlanner.materials`, after `FloorMaterials.assign`) |
| Dressing | `SewerPlanner.dress` (after the decor) | A grate in each sump, the outfall at the source, iron bars at the culverts, the sign at the stair's foot |
| Sluices | `DoorPlanner` (`_sluiced`, `SewerPlanner.sluice`) | Every doorway of a flooded narrow hall gets the decor kind "sluice" across it (whatever its model is: it is looked up by kind) and never an office door; wide halls stay open; the stair's doorway is an ordinary doorway (an office door when `DoorPlan` picks it) |
| Panel and pumps | `HazardPlanner.plan_sewer` | The **electrical panel** on a wall within 4 cells of the water whose cable lands within 3.5 (`LiveWire.drop_point_for`); up to two **sump pumps** on the walls by the water of the room farthest from the stair; an **oil drum** on a dry deck in 60 %. Priced props in `SitePlan.props`, the drum in `hazards`, after the floor's own; own dice; the clearances of the floor's explosives |
| The goo imps | `SewerPlanner.plan_pack` / `spawn` (`MonsterFactory.spawn_sewer_pack`, the goo imp's `"sewer_pack"` row) | One sewer pack (3-4 goo imps) a cluster, planned after the gators (so it keeps out of their territory, `SitePlan.blocked`) on the cluster's own dice: a room of the cluster other than the stair's when another has room, on its dry full cells within 2 of the water (a deck or a ledge over a channel) and more than 4 from the stair's foot. Spawned after the gators (the floor's last actors); they count toward the floor's pest objective like any pack. Spawn data in `HexMap.sewer["pack"]` |
| The gators | `scripts/contracts/planners/gator_planner.gd` (`GatorPlanner`) | Planned last (own dice), spawned **after the sharks** (the last actors, so no earlier net id moves). One a cluster, two in a cluster of four rooms, in a room's sump (farthest from the stair first, 5+ from staff, 6+ from a gate; else mid-hall), a second 8+ from the first. Home region: the body's cells and the cluster's cells within 2 (never the stair). Bask spots: the sumps, the middle of each flooded hall, a dry deck cell by the water in each room. No pack monster within 4 of where one starts (`SitePlan.blocked`). Spawn data in `HexMap.sewer["gators"]` |
| The look | `SewerView.dress_body` (`SewerPlanner.spawn`), `HexMapView` `Surf.CHANNEL` | A sewer body's pool kites are drawn on their own CHANNEL surface (material name `HexMapView.CHANNEL_MATERIAL`), so the view restyles only the sewer's bed and liners; the water, foam and kerbs of that body only, at its own surface. The floor's other materials, pools and lights are untouched (the slice's `dress` still restyles a whole sewer floor). The water's pattern is drawn in frames along 12 fixed directions, the two either side of the local flow cross-faded, the water's edges are found with corner keys on the hex lattice, and the kerb's faces are wound front side out (see "The water's moire" below) |
| Live wires | `SewerPlanner.spawn` | A `LiveWire` on every electrical panel (distance-based shock, N = 5, as built in phase 1) |
| Timing | `SiteBuilder.last_sewer_usec`, `SewerPlanner.last_usec` | Outside `last_plan_usec`. Measured: about 10 ms of planning on the biggest cluster; generation of a sewer floor up to about 240 ms (a failed cluster attempt is built again without it) |
| Tests | `tests/test_sewer_gen.gd` | Contract seeds 1-40, floors 2-3 (and floor 1 of 1-8): 2-4 rooms at one level, never the start or exit room, floors 2-3 of a bunker or lair; the stair has steps, goes down 3+ levels, its doorway dry; one body; every flooded hall's water joins both rooms'; every wide hall keeps a dry ledge; each room's water under the cap (in kites) and present; every doorway and room reachable from the start; nothing planned in the water; the panel's cable lands in water; one or two gators in their water, their spots in the region, the stair not theirs; no office door in the water, a sluice per flooded narrow doorway; the gators spawned after the sharks with a live wire per panel and the water drawn; a shared run gets none and builds exactly the floor without the option; a floor without a cluster has the same map and plan texts as `DungeonGen.generate` without the option; `--sewer-floor` forces one on most floors and still none when shared; the goo pack on dry deck by the water, spawned after the gators; the water as drawn: no foam strip with more of the body's water beyond it, no kerb top under the water, every kerb face wound to face its normal (every cluster, and the playtest's floor: board 7, offer 2, floor 2). Measured over the 80 floors 2-3: **27 have a cluster (34 %)**, all with a panel and a goo imp pack; sizes 2 rooms 14, 3 rooms 7, 4 rooms 6; 4 flooded narrow halls and 1 loop inside a cluster. `test_pools` skips the sewer's body record and its water decor (grates, bars, outfall, sluices: in the water on purpose); `test_hellgate_beast` builds its fixture floor without the option (its gate rooms changed with the cluster) |

**Why RATE 0.5:** about a third of the rolls find no wing that fits (no 2-4 room wing under a room high enough for the
stair), so a roll of 0.5 gives about one floor 2-3 in three with a cluster, the proposal's "about one floor in three". A cluster on every other
floor would stop it being special; rarer and a two-floor job may never show one. One const to tune after a playtest.

**Golden floors re-recorded** (`tests/golden/floors.json`): exactly the 12 golden floors that now have a cluster changed:
1/3, 2/2, 3/2, 5/2, 5/3, 6/2, 6/3, 7/2, 7/3, 8/2, 9/2, 10/3 (seed/floor): the terrain, the plan and the spawn (the cluster, its
props, gators and goo imps). The other 18 are byte for byte as recorded.

### The water's moire (user playtest, 2026-10-21: "What happened to this water")

On a generated floor the water showed striped moire under its surface: a zigzag band along the kites' edges across a
channel, and rings round a sump. Not z-fighting: hiding the water left a clean channel bed, and drawing it with one flow
direction cleared it. **The cause:** `SewerView.WATER_SHADER` drew its waves, scum and streaks in a frame along the
interpolated per-vertex flow, `dot(world position, flow)`. Where the flow turns inside a kite (the switch between two flow
lines, round a sump) that phase swings by |position| x the angle; the hand layouts sit near the origin, a cluster 30-60 m
from it, so a kite held dozens of stripes. **The fix:** the pattern is drawn in frames along 12 fixed directions (every 30
degrees), the two either side of the local flow cross-faded: a fixed frame is a plain translation, whatever the distance.
**Also found:** the water's edges were found by corner keys rounded to the millimetre; far from the origin the same corner
reached from two cells can land either side of a half millimetre (a column at X = +-51.0955), so the shared edge counted as
an edge of the water on both sides and drew foam and a kerb along it at the channel floor, under the water (about half of
the clusters in `test_sewer_gen`). The keys are now the corner's multiples of INNER / 2 and SIZE / 4. `test_sewer_gen` checks the
drawn water (above); the shader's frame has no headless test (no renderer). Before and after at the game camera (board 7,
offer 2, floor 2, `--to-sewer foot`): `sewer_fixes/water_moire_before.png`, `sewer_fixes/water_moire_after.png`.

**The water's edge** ("We also have z fighting on the water edge here", the same floor): the kerb along the rim fought at
its corners, a striped wedge where two strips and the corner fan overlap flush. The kerb is double-sided, and `SewerView._quad`
flipped only the normal of a face that came out pointing down, never its winding, so about half the kerb's faces were back
faces; Godot lights a double-sided back face with its normal flipped, from below, dark, and where a lit and a dark face lie
flush they fought (on the brick look every front face of the kerb was dark). Now `_quad` winds each quad to face its normal
(up for the tops and corner fans, toward the water for the front faces); `test_sewer_gen` checks every kerb face's winding.
Close-ups of a rim corner, concrete (board 7, offer 2, floor 2) and brick (seed 6, floor 2), before and after:
`sewer_fixes/water_rim_before.png`, `sewer_fixes/water_rim_after.png`. Left as is: the small notch at a corner's water-side tip
(the two front faces stop 4 cm into the water, so the liner shows between them) is a seam, not a fight.

### Known limits

- Rooms keep their blob shapes: a lobed or bitten room's channel takes the shortest walk inside it, so some channels jog;
  no L2 Y-junction or L5 6.0 main shapes (the main is a new hall width DungeonGen doesn't make). A loop inside a cluster
  (L4) happens but rarely (1 in 27).
- A wide hall's ledge is on its lane's side, not always the far side from the camera.
- The stair is a tree link, so it is usually a wide (4.5) hall, not the doc's narrow service stair, and a narrow one's
  head door is an ordinary office door (no "SERVICE LEVEL" stencil style yet). **Done: "Polish as built" (narrow, the service door).**
- A sewer floor is otherwise a different floor from its seed's old one (the exit cannot be in the cluster, its loops to the
  rest are not cut), though most rooms and links come out the same.
- No dispatch line for the service level yet (each needs a rendered radio clip, `tools/render_dispatch.ps1`). **Done: "Polish as built" (dispatch's sewer calls).**
- Gates and staff may land in the cluster (as the doc wanted: going down is a money call); the gator keeps 5-6 cells from
  them, so with staff in every sump it starts mid-hall.
- Influencer floors (low fit per the client table) can roll a cluster like any bunker.

### What phase 2 must flip

`SewerCluster.NETWORKED` to true, once: the gator streams and its nip / shove / death go through the net layer (phase 1's
"What phase 2 still needs"); the panel's break is an `obj` event that every machine's `LiveWire` runs from; **`HexMap.sewer`
is in `NetFloor.map_text_of`** (the water is already there as cells and the body record; the gators' spawn data and the
record are not); a 3-process test builds a sewer floor on every machine with the same checksum. `game.gd` already passes
`_shared` to `DungeonGen.for_run`, so nothing else changes. **Done: "Phase 2 as built" below.**

## Phase 2 as built (2026-10-21)

The user said yes to starting it (2026-10-21). A crew's floors 2-3 now roll sewer clusters exactly as a solo run of the same
seed does, and `--sewer N` works in a crew. There is no new networking shape: the gator is an owned actor (the host's, like
the shark), the panel a host-arbitrated object, and the live wire a scheduled effect from the panel's break.

### Play it (a crew on one PC)

```
.\run.ps1 -Crew 2 --seed 7 --net-wait 2 --contract 1 --floor 2 --spells damp,fireball   # a natural cluster: floor 2 of board 7, offer 2 (two gators)
.\run.ps1 -Crew 2 --sewer 2 --spells damp,fireball                                     # the L2 layout as every floor, in a crew
.\run.ps1 -Crew 2 --sewer-floor --spells damp,fireball                                 # a forced cluster on every floor
```

Extra args go to every window (run.ps1), and every window must have the same sewer flags: each builds the floor from the seed
before the load barrier, and the barrier's checksum sends out a window that built a different one ("Desync: different
floor"). `--to-sewer` still only moves the crew in a solo run (it would move heroes other machines own). Add `-Link coast` for
a coast-to-coast link, `-JoinLate 25` for a third window that joins on the job.

What to try with two windows: stand in front of a gator in one window (it nips that hero, decided on that window); shove it
from the other (it slides on both); kill it from the client (the invoice on both says Gator $6,300, to the client's hero,
once); wade the client's hero near the panel and shoot it from the host (both windows see the cable drop at the same moment;
each hero is shocked by its own window).

### How it is built

| Piece | Where | Notes |
|---|---|---|
| The switch | `SewerCluster.NETWORKED` = true | `seed_for(run, floor, shared)` rolls the same dice shared or solo, so a crew floor is the solo floor of that seed. `--sewer-floor` (`SewerCluster.force`) applies in a crew too (every window with the flag) |
| `--sewer N` in a crew | `GameDev._sewer()` | No longer gated on `_shared`. Every window builds the layout (`_dev_floor`) and stages it (`SewerDev.stage` from `_spawn_near`, before the barrier), so the staged monsters, gator and wires get their net ids in build order on every machine |
| The checksum | `NetFloor.map_text_of`, `spawn_text_of` | The map text gains a `sewer=` line with the whole `HexMap.sewer` record (rooms, stair, halls, sumps, the gators' and the goo pack's spawn data) on a floor that has one; the water body was already in `pools=`. Each spawn line gains the actor's own spawn data when it has a `net_spawn_text()`: the gator's home region, bask spots, relocation seed and price (this covers the `--sewer` layouts, which have no `HexMap.sewer`). A floor without a cluster or a gator has exactly its old text |
| The gator's stream | `NetWorld` (unchanged), `Gator` | A `Monster`, so `NetWorld` streams it as a MONSTER entry: position, facing, HP, state (its 3 bits: CALM, RILED, NIP, MOVE, DEAD, WATCH, HELD, CHUM), `_telegraph` and its strikes. No OWNER var beyond Monster's, so the monster carriers hold (`test_net_contract`). A client's copy is a puppet (`Net.make_puppet`) |
| The nip | `Gator._begin_nip`, `_strike` | The wind-up is `world.windup {id, s, l, v}` with `l = NIP_WINDUP + LUNGE_T` (0.5 s and the longest lunge, 1.0 at 9 units/s): a client resolves the bite when its screen reaches that moment, after the host's lunge has streamed, with the jaws where its puppet shows them (`Monster.net_strike` -> `_strike`; `Combat.bite` applies it only to what that machine resolves: its own hero). The host resolves monsters, employees, chickens and the AI heroes. On a puppet `_strike` stops after the bite: its state, strikes and cooldown come with the stream |
| Shoves and hits | `Actor.shove` / `apply_damage` on a copy | Requests (`Net.route_shove`, `Net.route_hit`): the host's `Gator.shove` riles it and slides it, its `_on_damaged` riles it and starts the advance; the walk home, the stuck fallback and the void bill are the host's AI |
| Death and the bill | `Gator._on_death` (unchanged) | `world.die`; the host's `Ledger.damage` once, to the culprit; every client's Ledger mirrors it (`obj.ledger`) |
| Corn | `Gator.corn_at` (unchanged) | Runs where `Net.simulates` the gator: the host. The corn itself lands on every machine (a scheduled effect) |
| Relocation, riling | `Gator` PRIVATE state | The host's AI; the stream shows where it goes and its state |
| The look | `Gator._pose_rig` | LOCAL and driven only by what a puppet has: its shown position (the speed, so the swim or the walk), its facing (the curl), the streamed state (watch, the riled thrash, chum, held) and `_telegraph` (the jaws: they no longer read the host-only lunge timer) |
| Late join | `NetEvents.LATE_JOIN` | The keyframe (position, facing, HP, state); a dead gator is a gone id (removed); a nip under way is skipped |
| The panel's break | `PricedProp` (`broke_at`, `_break_by`, `break_synced`) | `obj.break {id, t, by}`: the break's moment on the shared clock and the culprit (any priced prop; two OWNER vars with their carriers). A copy sets them before it is shown broken, so its `LiveWire` runs from the host's moment and credits the breaker |
| The live wire | `LiveWire` | A scheduled effect from the panel's `broke_at` on every machine: the drop (0.6 s), the shock and the pulses at the same beats. Hits are decided with the panel as the decider (`Combat.hits_in_radius(drop, r, panel)`): a hero by its owner, everything else by the host, like an explosive's blast. Before, the culprit decided, so when a client broke the panel nobody resolved the monsters in the water. The damage is credited to the breaker on every machine; the daze is applied by the target's owner. The arcs reach everyone in the water on every screen (`reached()`, the look) |
| The wire's late join | `PricedProp.late_join_state` `breaks` row, `LiveWire._on_synced` | A broken panel is a gone id, so the joiner breaks it first (the wire would start now); the `breaks` row [id, t, by] then gives the host's moment and the culprit, and the wire counts the shocks already past as fired: a dead wire lies dark in the water, a live one pulses on at the host's beats. Only a prop whose break something runs from (`break_synced` has a listener) sends the row |
| Pumps, drums, sluices, the goo pack | unchanged | Pumps and the drum are priced / explosive props (host-arbitrated, billed once); the sluices are decor (in the plan's checksum); the goo imps are networked monsters (`goo-imp.md`) |

### Tests

- `tests/test_net_gator.gd` (three processes, `off` and `coast`; floor 2 of board 7, offer 2: two gators): c1's hero in
  front of a gator is nipped once, resolved by c1 (10, shoved away), and the host shows c1's HP; c1's shove slides the host's
  gator and c1's puppet shows it where it landed; a late joiner sees both gators where the host has them; c1 kills one: billed
  once ($6,300 to c1's hero) and every Ledger is the host's; the OWNER-write guard never fires.
- `tests/test_net_live_wire.gd` (three processes, `off` and `coast`; `--sewer 1` in the crew): c1 breaks the panel (a
  request, $250 to c1's hero, once); c1's wading hero takes 18 and a daze, then four pulses of 9, by its own machine; a
  host-owned monster and the AI hero wading in reach are hit by the host once per shock, credited to c1's hero; the cable
  drops and the first shock fires at the same shared moment on both; a late joiner (in the water, in reach) sees the dead
  wire from the host's moment with every shock past and takes nothing; the guard never fires.
- `tests/test_net_sewer_floor.gd` (three processes, `off` and `coast`; the same floor as the gator test): every checksum part
  matches, with the same rooms, gators (their spawn data), live wires and goo imp pack on every machine; the gators and the goo
  imps are puppets; c1 smashes a sump pump (billed once, every Ledger the host's).
- `tests/test_sewer_gen.gd`: a shared run now gets the same cluster (the same map text, with the record in it); `--sewer-floor`
  forces the same in a crew.

### Fixtures that changed

- **Golden floors** (`tests/golden/floors.json`): the 12 floors with a cluster (1/3, 2/2, 3/2, 5/2, 5/3, 6/2, 6/3, 7/2, 7/3,
  8/2, 9/2, 10/3) changed their `map`, `spawn` and `all` hashes only, because the checksum's text now covers `HexMap.sewer` and
  each gator's spawn data. The floors themselves are unchanged: with the old checksum text all 30 golden floors still match
  (checked before re-recording), and their `plan` and `run` hashes, ids, cells and actors are as recorded. The other 18 are
  byte for byte as recorded.
- **`test_net_sharks`** moved from floor 3 of board 16, offer 3, to floor 3 of board 170, offer 1: the old floor now rolls a
  four-room cluster in a crew (the shark pools moved and one shark is left). Board 170's floor 3 has a regular and an imp
  laser shark and no cluster.

### Known limits

- The nip's moment on a client is the wind-up plus the longest lunge (0.61 s), so a short lunge lands up to 0.1 s later on a
  client than on the host; the bite still lands only if the client's hero is within reach of the jaws its screen shows.
- A late joiner who arrives while the wire still pulses runs the remaining pulses from the host's moment (they hit its hero if
  it wades in reach); `test_net_live_wire` covers the dead wire, not this case.
- The `--sewer N` and `--sewer-floor` flags must be the same in every window; a window without them is sent out at the barrier.

## Polish as built (2026-10-21)

The user's push to finish the sewer ("Decided (user, 2026-10-21 ...)" at the end of this doc). This is the sewer track's
share of it: the narrow stair and its door, dispatch's sewer calls, and the C3 notes. The sounds and the fix for the water's
z-fighting are separate tracks.

### Play it

```
.\run.ps1 --seed 5 --floor 2 --spells damp,fireball --no-mic --to-sewer head   # the SERVICE LEVEL door at the stair head
.\run.ps1 --seed 5 --floor 2 --spells damp,fireball --no-mic --to-sewer foot   # the service level call, the notes by the water
```

On seed 5 floor 2, walk down the stair to hear the service level call. Stand near the gator for the gator call, then kill it
for the bill call. Wade near the panel and shoot it for the wire call. The crossing sign and the pump log stand on the decks
by the water.

### How it is built

| Piece | Where | Notes |
|---|---|---|
| Narrow service stair | `DungeonGen` `_carve` | The stair link is always narrow: one lane, 3.0 between its walls. The main dice draw the chokepoint roll as before, so the floor around it moves no more than the cluster already moves it. A cluster whose narrow stair fails is built without the cluster, like any other failure. Over contract seeds 1-40, 26 of 80 floors 2-3 have a cluster (27 before): 9/2 lost its cluster |
| SERVICE LEVEL door | `DoorPlanner.service_head`, `OfficeDoorModel` style `"service"` | The office door at the stair's head, in the room above. It swings, smashes and is networked like the double door. Its look: plant green steel leaves, hazard-striped kick bands and header, and the stencil "SERVICE" / "LEVEL" across the leaves on both faces. The stripes use fixed soup seeds, so building it never moves PropModels' seed counter. It is placed on every stair head, including the 9 of 26 whose head is in the start or elevator room, where `DoorPlan` puts no door (the user, 2026-10-21: yes) |
| Dispatch's sewer calls | `SewerCalls` (`scripts/world/sewer/sewer_calls.gd`), `NoteCopy.SEWER_CALLS`, `DispatchVoice.all_lines` (kind "sewer") | Each call at most once per floor, on the banner (`game.gd`: `SewerCalls.attach` after the floor is set up). The service level call fires when a hero first stands in a cluster room. The gator call fires when a gator is within 11 of this machine's hero and the fog shows it. The bill call fires when a gator dies. The wire calls fire on a wire's first shock: one if a hero is in reach, the other if not, and only within 2 s of the shock, so a late joiner hears nothing about an old wire. A call waits while the banner holds another line and is dropped after 12 s. **Cosmetic and local**: each machine reacts to what it already receives (hero positions, `world.die`, the panel's `obj.break` moment), like the staff-lost call. Nothing is sent |
| Sewer notes (C3) | `SewerNotePlanner` (in `SiteBuilder.plan` after `NotePlanner`, before the decor), `NoteCopy.SEWER`, `NoteFacts` `{sewer_room}` | One note of each kind on a dry deck within 2 cells of the water. Each keeps 4 from every other note and 5 from the stair's doorway, where the stair-foot sign stays. The kinds: a GATOR CROSSING sign where the first flooded hall meets a room, the feeding rota in the stair's room (no line yet, so none is placed), the pump log beside a sump pump, and DO NOT DRINK by the outfall (not in a bunker, whose stair sign already says it). A kind with several lines picks one on the cluster's dice. `{sewer_room}` is the sewer theme row's note word, filled only on a cluster floor. Over seeds 1-40: crossing 25, pump 25, drink 8 |

### The text (the user's review, 2026-10-21)

The user (2026-10-21): "Stop, review all of the text with me before using it." Then their answers:

| # | Where | Text | The user |
|---|---|---|---|
| 1 | Dispatch: a hero first goes down the stair | "You're on the service level. Everything down there is wet, including the wiring." | as drafted ("leave them as is for now") |
| 2 | Dispatch: a gator in view | "That's the client's gator. It's expensive and it bites." | changed from "It's insured, and it bites": "insured" "extends the fiction too far" |
| 3 | Dispatch: a gator dies | "Gator's down. The client will want that itemized." | as drafted |
| 4 | Dispatch: a wire's first shock, no hero in reach | "Somebody broke the panel. The water's live, so stay on the decks." | as drafted |
| 5 | Dispatch: the same, a hero in reach | "That was the panel. Get out of the water." | as drafted |
| 6 | Sign "Caution" where a flooded hall meets a room | "GATOR CROSSING. Do not make eye contact. Do not make any contact." | this one only (the other draft dropped) |
| 7 | Memo "Feeding Rota" in the stair's room | none | both drafts rejected, no new line yet: **open**. `NoteCopy.SEWER["rota"]` is empty, so no rota is placed; the planner places one again once it has a line |
| 8 | Report "Pump Log" beside a sump pump | "Pump 2 tripped the panel again. Reset it standing in the water. Do not reset it standing in the water." | this one only |
| 9 | Sign (the client's sign header) by the outfall, not in a bunker | "NON-POTABLE WATER. DO NOT DRINK. Do not fill the coffee machine from here either, {staff}." | this one only |
| 10 | The service door's stencil | "SERVICE" / "LEVEL" | kept |
| - | The service door in the start and elevator rooms | (placement) | yes: on every stair head |

`{sewer_room}` (the sewer theme row's note word, "service level") stays a slot NoteFacts fills on a cluster floor; no line
uses it now. Unchanged and already shipped: the stair-foot sign, "RECLAIMED WATER: DO NOT DRINK. It is reclaimed." (bunker)
and "DO NOT FEED THE GATOR" (lair). The five calls are rendered by `tools/render_dispatch.ps1` like every dispatch line.

### Tests

- `tests/test_sewer_calls.gd` (new), on seed 5 floor 2:
  - nothing is called up top;
  - each call fires once per floor;
  - no sighting call after the gator's death;
  - the shock call when a hero wades in reach;
  - a call waits for the banner and is dropped when stale;
  - a floor with no cluster, gator or wire gets no SewerCalls.
- `test_sewer_gen`:
  - the stair is narrow;
  - exactly one service door, at the stair's head in the room above;
  - head and foot are reachable from the start;
  - every sewer note is on a cluster room's dry floor, by the water, apart from the other notes, and filled;
  - most clusters have the crossing sign, and no rota is placed while it has no line;
  - a floor without a cluster has no service door and no sewer notes.
- `test_dispatch_voice`: the "sewer" kind, every call listed once, and the spoken text of calls 1 and 5.
- `test_notes`: the `NoteCopy.SEWER` lines pass the length, slot and format checks.

**Golden floors re-recorded**: the same 12 floors with a cluster changed (1/3, 2/2, 3/2, 5/2, 5/3, 6/2, 6/3, 7/2, 7/3, 8/2,
9/2, 10/3). The narrow stair moves their cells, and the door and notes change their plans. 9/2 now builds without a cluster.
The other 18 are byte for byte as recorded.

### Open questions

- The feeding rota's line (item 7): the user rejected both drafts (2026-10-21) and has not picked one yet.

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

### Decided (user, 2026-10-20: the "decide now" set)

| Question | The user | What it means |
|---|---|---|
| The sewer's next step | "Into the generator" | **Phase 3 is next**: sewer clusters on real floors, solo first; networking (phase 2) after. |
| 12. Build order | "Sewer first" | The sewer goes into the generator before lava. |
| 1. Where sewers appear | "2-4 room cluster" | A **cluster of 2-4 rooms** on some lair and bunker floors (floors 2-3), reached by a service stair; the rest of the floor stays normal. |
| 11. Where lava appears | "Supervillain + hellgates" | Lava caves only on **supervillain** sites and **next to hellgates**; not the founder. |

The lava playtest answers from the same set are in `lava-playtest.md` ("Decided after the playtest").

### Decided (user, 2026-10-21: "finish up the lava and sewers ... get them in the game fully")

- **In scope for "finished":** sounds (gator hiss and nip, goo throw and splat, live wire buzz, wading) and dispatch lines
  (the service level, the gator, the live wire), rendered with the Kokoro voice.
- **Not in this push:** the steam valve, the gas pocket and eels.
- **My defaults for the phase 3 follow-ups, accepted:** about one floor in three (influencer floors included); the service
  stair forced narrow with a "SERVICE LEVEL" door; gates and staff may land in the sewer.
