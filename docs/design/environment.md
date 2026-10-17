# Environment: "luxury bunker infested with demons"

Status: plan, 2026-10-16. The terrain look is locked: dark slate hex columns with glowing amber
seams, crates as raised platforms, and warm downlights. This doc covers the dressing on top of it.

Every room is two layers: **opulent bunker** (what it was) plus **infestation** (what the demons did).
The contrast is both the joke and the mood. Dressing must never hurt readability. Walkable hexes stay
clear, and props live on walls, wall tops, corners, pits and raised blocks.

## 1. Room themes (one per generated room)
`DungeonGen` already tags rooms (`room:<n>`). Each room gets a **theme** that picks its props, floor
accents and light colour. All props are faceted low-poly and built in code, like the characters.

| Theme | Bunker layer | Infestation layer | Gameplay hook |
|---|---|---|---|
| **Wine cellar** | barrel racks, bottle walls, a tasting table | shattered bottles, a red-wine "blood" pool, an imp nest in a barrel | barrels as shove targets (they burst, then become a slick floor) |
| **Home cinema** | recliner rows on terraces (heights!), a giant screen showing static, a popcorn machine | a demon silhouette flickering on the screen, torn seats | recliner tiers make natural +1 steps; the screen is a vantage backdrop |
| **Panic room** | a vault door, monitors, gold bars, canned food | the door ripped open, claw marks, a ritual circle | the vault holds rare components (an exploration reward) |
| **Wellness spa / yoga studio** | yoga mats, a zen fountain, crystals, a himalayan salt lamp | a chalk **summoning circle** surrounded by candles: the wellness guru's "manifesting" went wrong | the circle is a demon spawner / portal (the room's objective) |
| **Gym** | dumbbells, a treadmill, a mirror wall | a bent barbell, a brute-sized dent in the mirror | heavy props as shove obstacles |
| **Server room** | rack rows with blinking LEDs, cable trays | cables torn out and sparking, a rogue house-AI eye on the monitors | sparks deal light damage on contact (a hazard), and the racks create corridors |
| **Indoor pool** | a sunken pool (a pit cell cluster), loungers, a towel rack | purple glowing water, tentacle-ish shapes below | the pool IS a pit, so shoving monsters in is the point |

## 1b. Second site type: the villain lair [decided direction]
Same two-layer rule, but the site was **already evil before the demons wrecked it**: a supervillain
or cult boss's lair, overrun by the very demons they were dabbling with.

| Theme | Evil-before layer | Wrecked-by-demons layer | Gameplay hook |
|---|---|---|---|
| **Torture chamber** | racks, cages, hanging chains, iron maiden, a brazier | cages bent open, chains snapped, scorch marks | cages as cover; chains/braziers as shove hazards |
| **Throne room / lair hub** | evil throne, red carpet, a monologue podium, a doomsday-device console | the throne toppled, the console sparking, an imp sitting on the throne | the console is the room objective (shut down or loot) |
| **Lab / vat room** | glowing vats, specimen jars, a lever wall | vats cracked and leaking ichor, jars smashed | leaking vats = goo hazard; pulling levers opens areas |
| **Shark/lava moat** | a moat with a retractable bridge (a classic) | the bridge half-broken | the moat is a pit: shove villains' demons in |
| **Henchmen barracks** | bunk rows, matching jumpsuits, a "days since accident: 0" sign | bunks overturned, jumpsuits shredded | henchmen survivors could be the "employees" to protect |

Contract sites can be either type: a **luxury bunker** (billionaire client) or a **villain lair**
(the villain is the client, which is funnier: "I need my lair back by Thursday").

## 2. The infestation layer (all rooms, intensity grows deeper in)
- **Demon ichor:** neon-purple goo puddles and drips on walls (decals). They glow in the dark,
  matching the tentacles and swarmer colour. Maybe they slow movement later.
- **Hotter seams near nests:** the amber floor seams shift toward red/orange near spawners and the exit.
  It's cheap (a per-cell tint in `HexMapView`) and shows "danger ahead" without UI.
- **Scorch marks and claw scratches** on walls and floor (decals or dark faceted strips).
- **Nests:** imp egg clusters (glowing purple pods) on walls and in corners. Some are breakable and
  drop neon ichor.
- **Ritual litter:** candles, chalk symbols, burnt sage, crystals scattered from the spa.
- **Bones and junk:** skeleton bits (they match the grunts), scattered gold coins, receipts.

## 3. Light and atmosphere
- **Flicker:** a few downlights per room flicker or buzz. One room per floor has a dead light and
  only the seam glow, which is very moody.
- **Emergency lighting:** red rotating beacons near the exit or panic rooms (a slow sweep).
- **Neon signs:** a broken neon sign on the wall ("WINE", "PANIC", "OM"), half the letters out.
  It's a strong silhouette, a nice joke, and a light source.
- **Particles:** embers drifting up from seams, dust motes in light pools, steam from vents, and
  purple sparks around nests. All on the CPU, cheap and sparse.
- **Audio** (later): ventilation hum, distant growls, a tinny elevator jazz loop, and imp giggles near nests.

## 4. The surface the contract came through
The first room is the **service entrance**: hazard tape, a dispatcher's job card pinned to the wall,
the crew's van keys, a "WET FLOOR" sign. It sets the tone in one glance. The **exit** is a freight
elevator with its light on.

## 5. Gameplay-tied props (later, but plan the hooks now)
- **Breakables:** crates, barrels and pods. Some contain components, and shoving into them breaks them.
- **Hazards:**
  - sparking cables (light damage);
  - goo (slow);
  - pool/pit edges (shove targets);
  - gas pipes: fireball makes them explode, which is chaos.
- **Spawners:** summoning circles and nests. Destroy them to stop the waves; this is the room objective.
- **Secrets:** a cracked wall that Gasket's hammer breaks, and vault doors in panic rooms
  (`exploration.md`).

## 6. How to build it (production)
1. **Prop kit** (`scripts/art/lowpoly/props/`): faceted props from `LowPoly` primitives. Start with
   about 12: barrel, bottle rack, recliner, screen, yoga mat, candle cluster, summoning circle,
   neon sign, server rack, egg pod, bones, hazard tape.
2. **Room themer:** after generation, assign each room a theme by size and position. Place props on
   wall-adjacent cells and wall tops, with a "keep walkable hexes clear" rule and a density cap.
3. **Infestation pass:**
   - ichor and scorch decals;
   - seam tint by distance to nests or the exit;
   - nests in corners.

   The intensity scales with room depth.
4. **Light pass:** add flicker and colour to `DungeonLook.add_pools`, plus a neon sign as an emissive
   prop with a small OmniLight.
5. **Perf budget:** props merged per room into a few meshes (like the terrain), at most ~3 extra
   lights per room, and CPU particles only.

Suggested order: prop kit + themer with 3 themes (wine cellar, spa, server room), then the
infestation pass, then lights. Generate a concept image or two of themed rooms first, as we did for
the characters, to lock the look before building.

## Decisions (user, 2026-10-17)
- **Set dressing must be logical.** Every prop kind has a placement rule and an orientation rule:
  - wall-backed props face into the room;
  - corner props face the center;
  - centerpieces sit at the focal point and face the entrance;
  - grouped vignettes are placed as one unit (seat rows face the screen; chairs face their table).

  Only ±10° of jitter, a clear hex in front of facing props, and nothing ever blocks doors or
  corridors. No more chairs facing the wall.
- **Full room themes, built now** rather than vignettes first. Each room gets a theme that chooses
  its props and grime.
- **Grime is visual only:**
  - **Ambient grime persists:** story and infestation heat near gates and the origin, trails, and
    theme-specific marks like wine splats in the cellar.
  - **Anything the player causes fades after 30 s:** fireball scorch, corn kernels, teeth debris,
    death stains.
