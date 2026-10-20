# Cast: exploration on the hex-height terrain

Exploration is the first pillar; combat through spoken spells is the second. This doc covers
what makes walking around the procedural hex world rewarding by itself. It uses the
terrain rules that already exist:
- a rise of 1 level walks;
- a rise of 2 is a slow climb;
- a rise of 3 or more is blocked;
- a drop of more than 3 is blocked;
- stairs bridge big gaps, and missing cells are void.

## Walls: flat, through the hex centers

Walls don't follow the hex edges. Each wall face runs straight from one hex center to the next, crossing the
shared edge at its midpoint, so every wall is at 0, 60 or 120 degrees and every corner sits on a hex center.
The border cells are cut in half: floor on the room side, wall on the other (`HexMap.cut_walls`, see
ARCHITECTURE.md). What it means on the ground:
- **Rooms read as clean shapes.** A round room is a hexagon with six straight walls; lobed rooms are polygons.
  No zigzag, so it is easy to see where a room ends and where the doors are.
- **Bodies stop at the face.** A hero walking into a wall stops touching it and slides along it; a shove slams
  against the flat face; arrows hit the face, not a tooth of it. Props stand flush against the walls.
- **Corridors.** Tree links are 4.5 wide (two full lanes); extra loops, the climb shortcut and the one chokepoint
  are 3.0 wide. Every corridor has a full centre lane, which is what pathing walks (a cut cell's center is on the
  wall line, so it is never a path step). Doorways are always a full cell in a flared, clean opening.
- **The old one-wide chokepoint is gone:** at 3.0 it is still the narrowest passage on a floor and still a place
  to hold a pack, but two heroes can pass in it. A tighter squeeze would need a corridor with no full lane, which
  pathing could not use.
- Pillars and pits keep two cells from the walls, so there is never a gap too thin to walk between a pillar and a
  wall.

## The key asymmetry: one-way ledges

You can **drop** 3 levels but you can't **climb** 3. That gives every 3-level edge a
direction:
- Dropping off a 3-level ledge is a **commitment.** You're in the lower area until you
  find stairs or a 2-climb route back up.
- The generator can use this on purpose:
  - **Pit rooms:** easy to drop into, with the way out somewhere inside.
  - **Shortcut ledges:** a drop that loops back to the start of a floor, Dark Souls-style.
    Once found, it makes backtracking quick.
- The HUD should mark a 3-level edge the first time a player hovers it: "You can't climb
  back up here."

## Climbing as a traversal skill

Climbing (a rise of 2) is slow on purpose. Make that slowness a decision rather than a
tax:
- **Escape route:** the brute can't climb, and grunts climb slowly. A climbable step is a
  safe spot, and the brute walks around to the nearest stairs.
- **Exposure:** while climbing, a hero can't attack and takes +25% damage from ranged
  attacks. Archers punish careless climbs.
- **High ground pays:** ranged attacks and spells from 2 or more levels above the target
  deal +15%. Falling-object spells like meteor and anvil hit harder on targets below the
  caster.
- **Climb chains:** a sequence of 2-level steps up a cliff face is a mini-route. Put a
  reward at the top so the slow climb feels earned.

## Vantage points

- **Height reveals the map.** Fog of war clears in a radius that grows with the cell's
  height above its surroundings: about +2 hexes per level, using `line_of_sight`.
- **Every region has at least one crown**, a high cell the generator guarantees. Reaching
  it reveals the surrounding rooms and **glints** any secret within range: a loose wall,
  a hidden stair, a ledge cache.
- Vantage points double as **combat positions** to defend: the archer's favorite cells,
  and a place to stand when a swarmer pack arrives.

## Secrets

| Secret | How you reach it | Signal that it exists |
|---|---|---|
| Ledge cache | A 2-climb chain, or a drop from above | A glint seen from a vantage point |
| Hidden stair | A breakable wall section; melee it | A crack decal; dust falling on approach |
| Undercroft | One-way drop into a pit room; stairs out on the far side | A dark hole visible from above |
| Bridge-out | A long bridge across void to an island | Visible from the start, so the hard part is finding the stairs onto it |
| Sealed shrine | A door that opens to a unison cast (optional voice use, below) | A shrine glow behind a barrier |

Rule of thumb: **every secret is visible before it is reachable.** The fun is working out
the route.

## Risk and reward side areas

- **Elite rooms** off the main path: one elite plus a guaranteed spell-word or gear drop.
  They're marked on the map once spotted, so taking the detour is a choice.
- **Collapse rooms:** the floor lowers one level every few seconds after the loot is
  taken. You have to get out before it reaches a one-way drop.
- **Brute gauntlets:** a plateau the brute can't reach, holding treasure, surrounded by
  low ground the brute patrols. Climbing is the only safe way in.
- **Overflow loot:** side areas give the *exploration* rewards (new spell words, gear,
  shortcuts), while the main path gives the *progression* rewards (the exit, checkpoints).
  Skipping side areas is allowed but leaves you weaker.

## Co-op exploration

- **Split up, with a soft leash.** Players can range apart about 2 rooms freely. Beyond
  that, the split-off player's spell cooldowns slow by 25%; in fiction terms, the group's
  shared power weakens. No hard tether.
- **Voice callouts are the core co-op exploration tool.** Players are already on voice:
  "Stairs over here!", "There's a chest on the ledge, I can't get up", "Brute's coming,
  climb!". Support it with:
  - a **ping key** that drops a world marker and shows the player's name over it;
  - a minimap showing teammates' positions and the vantage points they've climbed.
- **Shared reveal:** fog of war cleared by one player clears for everyone, so a scout
  climbing a crown is a team action.
- **Split-route rooms:** two pressure plates on different levels, or two levers on either
  side of a gap. Someone has to take the climb route while someone else takes the stairs.

## Non-combat voice uses (light, optional)

Spells stay mainly about combat. These are small extras that cost little:
- **Unison doors:** a sealed shrine opens when 2 or more players cast *any* spell in
  unison at it. It's practice for combat chorus casts.
- **Shout to scout:** a loud, sustained shout (using voice activity and mic level, with no
  words needed) sends a short pulse that outlines the walls of the current room through
  the fog. It also **wakes sleeping enemies nearby.** That's the risk.
- **"Mark" by voice:** saying "mark" while pointing places a ping. It is gated by the
  same strictness mode as spells (see voice-mechanic.md §3), and push-to-cast players get it
  for free.
- **Silent rooms:** areas where any voice activity wakes enemies, so sneaking means the
  team going quiet. This is the one place where *not* speaking is a mechanic.

## What the generator needs

- Tag regions so every region gets at least one crown.
- Spread one-way drops and loops evenly through a floor.
- Place secrets with an approach route checked by `find_path`, with climbing allowed,
  and make sure each secret is visible from at least one vantage point.
- Check that every one-way drop has a way back up (stairs or a climb route), so a hero
  can never get stuck.
- Keep at least one walkable route into each region with no climbing, so the brute
  always has a long way round and climbing stays an escape, not a hiding place.

## Decisions: map information, fog and doors (user, 2026-10-19)
- **What the player knows:** no site plan, no extra UI. The **next room** (any room next to one the crew can see or has
  seen) has its layout drawn even before anyone sees into it; rooms beyond that are dark. Contents (monsters, props,
  loot, employees, hazards, secrets) show only when a hero can see them.
- **Room fog, not per-cell line of sight.** A room is in view when a hero is in it, or sees into it through an open
  doorway or from height. A room seen before keeps its layout and last-seen props, dimmed.
- **Monsters out of sight are hidden** (no last-known ghosts).
- **No minimap.**
- **Doors, first pass: office doors only.** Walk into one to open it, E to shut it; a shut door blocks sight and
  muffles noise, and a brute smashes through (billed). Fire/blast doors and locked doors are later.
- The vantage-point and shared-reveal ideas above still apply (a reveal by one player is everyone's).
- **Door look (2026-10-19, after three lab rounds):** doors belong to the room wall, not the hex terrain: the door
  stands on the chord between the corridor's two jambs, at the wall's height. Built from hex parts they "looked even
  more off". The **double door** (cream leaves, push bars, lit green sign) with a **gunmetal** frame is the default.
  Only narrow corridors get doors; wide hallways always meet their room open; opening a door is a noise.
- **Doorway floor (2026-10-19):** the cells the door line passes through get a **diamond tread-plate threshold**, with
  the room's floor on one side and the corridor's on the other. Open archways keep their floors as they are, for now.
- **Fog look (2026-10-19, played in the fog lab):** look **A, black void**: unknown spaces are the background, next
  spaces a dark silhouette with traced edges, seen spaces desaturated and darkened. The user: "that is perfect."
- **In the game (2026-10-19):** look A is the game's only look (blueprint and smoke stay in the lab), drawn on every
  machine from every crew hero's sight, puppets included. **Every narrow doorway gets a door** (no dead ends, not the
  start or elevator room); wide hallways stay open. Doors **start shut** and a shut door is **solid**: bodies, shoves,
  arrows and projectiles stop at it, as do sight and sound. Heroes and employees open one by walking into it; a monster
  stops for half a second first; a chasing brute smashes it (billed once). Seen rooms show their furniture live. A
  vantage two levels up sees into the next space through an open doorway, never through a shut door. Online the host
  decides every door (a client's walk-in or E is a request), and a late joiner gets every door's state.
- **Long halls (2026-10-20, after the fog spaces audit, `fog-spaces-audit.md`):** a hall was one fog space however
  long, so a hero seeing into a corridor saw all of it, up to 78 units round corners. Long halls are now **cut into
  segments** of about 8 steps, never cut within 3 steps of a doorway or its door. The user: "Turn it on."
  Walking down a long hall shows it about one segment ahead; the segment after that is next (silhouette), and a room at
  the far end of a cut hall stays dark until the crew gets near. Where a segment in view meets one that is not, the fog
  fades over about a hex (a soft edge across the hall, not a line), so the hall reads as going on into the dark, not as
  a wall. Seeing across a cut counts like a doorway (in range and in sight of the hero) but never uses up a hop, so a
  hero standing on a cut sees the same from either side (no flicker). It is local presentation like the rest of the
  fog: every machine cuts the same segments from the map, puppets and late joiners included; the floor plan, the doors
  and the checksum do not change.
