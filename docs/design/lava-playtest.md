# Lava caves: layouts and a playable prototype

Status: **prototype, solo only, behind a dev flag** (2026-10-20). The normal floor generator does not make caves:
DungeonGen and SiteBuilder never call this code. The concept is `sewer-concept.md`, part 2. This page covers the cave
layouts and the playtest build.

**The user's feedback** on the concept (2026-10-20):
- "My biggest concern is how we fight there. I suspect we need 2x wide paths just to avoid falling in."
- "we can have isolated islands no paths to place ranged enemies on. Forcing the players to engage with range."
- "Damping lava sounds hilarious. Yes."
- "That mild damage sounds fine." This is 15 damage plus Burning; heroes are pulled back and monsters die.
- "For the lava room cluster question - show me some layouts."
- "Can we playtest what we have for lava?"

## Playtest it

```
.\run.ps1 --lava-cave 1 --spells damp,fireball --no-mic
```

- `--lava-cave N` builds cave N (1-5, below) as every floor of the contract, in place of the generated floor.
- `--spells damp,fireball` skips the job board and the spell picker and gives you those two spells.
- Drop `--no-mic` to cast by voice. You can always type a cast: Enter, then `cast damp`.
- Add `--hero rebar` to play Rebar and shove things in yourself. You play Gasket by default; Wick and Rebar are AI allies.
- `--no-fog` shows the whole cave.

**Which spells to bring:**

| Spell | Why |
|---|---|
| **damp** | Crusts the lava (walkable for 8 s); the shortcut to an archer isle. Also soaks the crew so the lava can't set them on fire. |
| **fireball** | Range for the isles, and its blast shoves monsters off the edges. |
| **tentacles** | A shove in an area: a whole pack into the lava. |
| corn | A shove and damage; the bridgehead brawl. |

Recommended runs:
- `--lava-cave 1 --spells damp,fireball`
- `--lava-cave 3 --spells damp,tentacles --hero rebar`
- `--lava-cave 5 --spells damp,fireball --hero wick`

**What to try:**
1. **Damp the lava.**
   - Cast damp at the edge of your rock, toward an archer isle.
   - Walk onto the crust and cross. It flickers and shakes for its last 2 s, then melts.
   - Get caught on it and you are thrown back to the nearest rock, with 15 damage and on fire. A grunt on it sinks.
2. **Shove something in.**
   - Rebar's punch, Gasket's spin, the fireball's blast or tentacles at a skeleton standing at a bridge's edge: it falls in
     and dies.
   - The grunts in caves 1, 2 and 4 come at you on the bridge, two abreast.
3. **Get shoved in.** You are pulled back onto the bridge: "LAVA!", 15 damage, burning. Cast damp on yourself first and
   you take the damage without the burn.
4. **The archers on their isles** have no path to you, and you have none to them. Shoot them from range (Wick's bow, a
   fireball), or damp a crust across to them. In cave 5 the tower is too high for a crust to reach, so only range works.
5. **One-wide spans** (caves 1, 2 and 3) are the short way, but one shove ends the crossing.
6. **Fog:**
   - Each chamber and each bridge is its own space, so the cave reveals itself a section at a time.
   - An archer isle shares the fog space of the chamber it overlooks, so the archers show when that chamber does.

**What the prototype is not:**
- Not online: the flag is ignored in a shared run (see "Co-op").
- No hellgates, employees, props, notes or mail in the cave.
- The contract still rolls its objective. It reads "Exterminate archers" in cave 1 when the seed rolls archers. The exit
  hex (magenta) opens the elevator menu as usual, and the next floor is the same cave again.

## The five layouts

Each layout is 2-3 chambers joined by **two-wide** rough bridges, with **one-wide** spans only as risky shortcuts. Every
layout has at least one **isolated isle** holding archers within bow range (8) of the path, so the crew has to fight at
range.

**Renders** are in the session scratchpad, `...\scratchpad\sewer\lava2\`:
- `layoutN_plan.png`: top down, the rim left off. The marks:
  - cyan lines between the fog spaces and their names;
  - yellow rings on the doorways (bridge ends);
  - ENTRY and EXIT;
  - a red ring round each archer isle;
  - the melee pack;
  - "cover" on crags;
  - SHOVE! rings where a shove into the lava tempts;
  - cyan dashed DAMP lines where a crust opens a shortcut;
  - "1-wide (risky)" on the spans.
- `layoutN.png`: the game camera (size 24), unmarked.
- `layoutN_marked.png`: the game camera with the marks.
- `game_N.png`: the playable prototype itself, with the HUD.
- `game_crust.png`: a damp cast toward the lava: the crust, just made.
- `game_crust_warn.png`: the same crust 6 s later, cracking.

### 1. The Causeway (`layout1*`)
Two chambers, one long two-wide bridge, an archer isle off the bridge's near side, and a one-wide goat path round the
back.
- **Entry:** A. The archers open up as soon as A is in view, about 7 from the bridge.
- **Cover:** A's crag, to shoot the isle first. The far chamber's crag, for the bridgehead fight.
- **Melee:** three grunts hold the far bridgehead. The bridge is two wide, so there is room to fight, and both edges are
  kill zones.
- **Shove:** the middle of the bridge and the bridgehead.
- **Damp:** across the 2-hex gap to the isle, to rush it; or across the 2 hexes from the bridge to the goat path.
- **The goat path** is out of arrow range, but it is one wide.

### 2. The Fork (`layout2*`)
A bridge to a hub island with a crag, then two ways on: a short one-wide span straight to the exit chamber, or a long
two-wide loop round the near side. An archer isle sits between the two routes and covers both.
- **Entry:** A, then the bridge to the hub B. The grunts on B come at you on the bridge, so shove them off.
- **Cover:** B's crag, which is also the vantage over both routes.
- **The short way:** three hexes of one-wide span, archers 3 away. Fast, exposed, one shove from the lava.
- **The long way:** the two-wide loop, longer under the isle, but with room to fight the imps waiting at C.
- **Damp:** from B's east edge across the gap to the isle, so melee can clear it.

### 3. The Ring (`layout3*`)
Three chambers round a lava lake, with an archer isle in the middle. Two-wide bridges run A-B and B-C round the back, and
a one-wide span runs A-C straight across the front, under the isle. A brute holds the B-C bridge.
- **Entry:** A. The isle covers the front span and both bridges; nowhere is fully out of reach.
- **The front:** a sprint under fire on the one-wide span.
- **The back:**
  - over the A-B bridge into the grunts at B (crag cover);
  - then the brute on the B-C bridge: shove it off before it shoves you. Its slam shoves too.
- **Damp:** from the span or from bridge A-B, a crust across the lake to the isle (2 hexes).

### 4. The Gauntlet (`layout4*`)
One long two-wide bridge between two chambers, with an archer isle on each side, and the pack charges down the bridge
from the far end. There is no way round: the fight is the bridge.
- **Entry:** A. The near isle shoots into A, so clear it from A's crags (bow, fireball) before stepping out.
- **Melee:** grunts and a brute come down the bridge two abreast. The middle third is where everyone gets shoved.
- **Damp:** the far isle covers the last third and the bridgehead; damp from the bridge reaches it (one hex).

### 5. The Crag (`layout5*`)
A short bridge into a big middle chamber with crag pillars, then a two-wide ramp up to the exit shelf, with a two-level
climb in it, under an archer tower.
- **Entry:** A, then the short bridge into B. Grunts among the pillars, and the pillars block the tower's arrows.
- **The climb:** slow and exposed, in the tower's sights. Shoot the tower first.
- **Damp:** crusts the gap to the tower's foot, but the tower is 3 levels above the crust, which is a wall: **a crust
  can't climb it.** The tower is range-only by design.
- **At the top:** the imps swarm the climb. Fight at the top of the ramp, not on it.

### What the layouts show about fighting

- **Two wide is enough to fight on.**
  - A pack meets you two abreast, and you can step aside from a swing.
  - Each edge is still one step away, so a brute's slam or a stray shove matters. That is the tension.
  - Three wide would make the bridges safe and the lava decor.
- **One wide is a choice, not the route.** Every layout has a two-wide way to the exit; the one-wide spans are
  shortcuts.
- **Isles force range.** The isles sit 3-4 hexes from the path: in bow range (the archer's 5-8) and in the crew's (the
  bow, fireball, corn).
  - Damp crosses most gaps (1-2 hexes) for a melee rush.
  - The tower in cave 5 is the exception.
- **Chambers are where the fights land:** bridgeheads and crags. Bridges are where the shoves happen.

## How the prototype works

- **`LavaCave`** (`scripts/world/lava/lava_cave.gd`): the five layouts as data.
  - Chambers and isles are rough blobs: a level up here and there, never a climb between neighbours inside a blob.
  - Crags; bridges as waypoint runs with a lane beside the route when two wide; small level steps.
  - The lava round the rock, and the rim: tall (6-9) at the back. On the camera's side there is no wall: the lava runs on
    out of view. In an earlier pass a low near wall hid the near edge and read as floor.
  - `build_map`, `plan` (a minimal SitePlan), `spawn_monsters`, and `check` (used by the test).
- **`LavaLook`** (`scripts/world/lava/lava_look.gd`): the magma look from the lab.
  - Rock restyle, and the crate texture swapped for rock.
  - The lava surface: unshaded crust over glowing cracks.
  - The glow skirt up the rock faces, embers, and 10 warm omni lights.
  - DungeonLook dimmed.
- **`LavaField`** (`scripts/world/lava/lava_field.gd`): the rules.
  - **Lava is void.** Once the floor runs, the lava cells leave the map, so the game's own pit rule applies
    (`Actor._enter_void`): walking can't enter, a shoved hero is pulled back (5), and a shoved monster falls and dies.
  - LavaField adds **10 more damage and Burning (6 s)** to the hero's pull: 15 in all, the burn unless soaked.
  - **Damp crust:** each damp cast crusts the lava within 90 % of its radius.
    - Crust is real cells at level -1: walkable from rock at 0, a climb to rock at 1, and a wall below rock at 2+.
    - It lasts 8 s; for the last 2 s its cracks flare and it shakes. Then the cells leave again.
    - A hero on it is put back on the nearest rock (15 damage and a burn); a monster sinks.
    - A damp aimed at the lava lands on the nearest rock edge (SpellBook pulls it back), so the crust grows out from the
      shore. That is the shape you want for a shortcut.
- **Fog:** RoomFog and FogView are built while the lava cells still exist, so every lava cell keeps the fog space of its
  nearest rock. Then LavaField removes them. Without this, open lava more than two cells from rock would draw as
  unknown (black).
- **game.gd hooks** (all behind `--lava-cave`, solo only; `_lava_cave()` returns 0 in a shared run):
  - `_build_world` builds the cave map, its plan and the look;
  - `_populate_site` spawns the cave's monsters;
  - `_start_lava` (after `_setup_fog`) starts LavaField.
- **Tests:** `tests/test_lava_cave.gd` checks:
  - each layout: a way from entry to exit on two-wide bridges, archers on rock no path reaches, every two-wide row with its
    lane, the same map every build;
  - a grunt shoved off a bridge dies;
  - a hero shoved off is pulled back with 15 and burning;
  - a damp crusts the lava, a path leads onto it, it melts after 8 s, a hero on it is put back on rock and hurt, and a
    grunt on it sinks.
- **Lab:** `scenes/lava_layouts_lab.tscn` (`scripts/art/lowpoly/lava_layouts_lab.gd`) renders the plans and the game
  views from the same layouts.

## Co-op

- **The flag is not used online.** `game.gd` builds a cave only when the run is not shared, so a crew never gets one.
  Nothing else in the game changed.
- `LavaField` declares its fields (`net_fields()`, listed in `test_net_contract`'s `NET_SCRIPTS`):
  - the lava set is SPAWN;
  - the crusts, the hooks and the state are LOCAL (they follow from the damp casts).
- It applies every verb (damage, burn, shove) only where this machine resolves the actor (`Net.resolves`), so it would
  not double-apply online.
- **What a real co-op build needs** (`sewer-concept.md` part 2's networking shape):
  - **The crust is terrain that changes on a schedule.** Every machine must compute the same crust from the damp's
    stamped start time, and `HexMap`'s cells change at run time, which nothing else does today. The cave's lava set and
    the crust state belong in the floor checksum and in what a late joiner gets.
  - **A prototype shortcut to replace:** when a crust melts under a hero, LavaField writes the hero's private
    `Actor._safe_cell` (on the hero's owner only), so the pit pull lands on rock rather than on the melted crust. A real
    build adds a verb or a hook in `Actor` for this.
- `test_net_contract` passes.

## Known limits

- The lava's damage and burn are layered on the pit rule's signal (`shove_impact` "void"). A real build would give
  `Actor` a lava kind of void (the damage and burn in one place, a sink instead of a fall).
- Monsters and AI allies path over the crust while it lasts and can be caught on it. That is part of the fun.
- No lava creatures yet (the salamander is lab-only). The ranged threat is the archers on isles.
- Ten unshadowed omni lights per cave. The frame cost on the min-spec machine is not measured yet.

## Questions for the user after the playtest

1. Do **two-wide bridges** feel right to fight on, or do they need to be three wide in places (bridgeheads)?
2. **Archers on isles:** fun or frustrating? Should a crust always be able to reach an isle (no towers like cave 5)?
3. **Damp crust:** is 8 s the right length? Should it be the whole radius (as now) or patchy like damp's puddles?
4. **Lava damage:** 15 plus a burn. After playing, still mild enough?
5. Which layouts should become the generator's **cave patterns**?
