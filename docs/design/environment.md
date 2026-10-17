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

## Implementation of the themes (2026-10-17)
Built in `scripts/world/themes/` (planner, pure data) and `scripts/art/lowpoly/props/decor_*.gd` (models), wired
into `SiteBuilder.plan()`; the result is on the `SitePlan` (`room_themes`, `decor`, `lights`, `entrances`).
- **Themes:** every room gets one from the site's pool; the start room is the **service entrance** (hazard tape,
  a WET FLOOR sign); the floor-3 **origin room** gets the theme the story names (`RoomThemeDefs.ORIGIN_THEMES`,
  e.g. "yoga studio" -> spa, "vat room" -> lab). The exit room and rooms with a hellgate in the middle are not
  dealt a theme whose centrepiece needs the middle (pool).
- **Placement rules** (`RoomThemeDefs`, `PricedProp.TABLE`): wall (back to the nearest wall, facing into the
  room), corner (facing the centre), centre (focal point, facing the door, big rooms only), floor, and vignettes
  placed as ONE unit (`ThemeVignettes`): cinema screen + 2-3 recliner rows, table + chairs, desk + monitor +
  chair, bunk rows, bench + rack, candles in a ring around the chalk circle (drawn around the hellgate when
  there is one), barrel clusters. Jitter is at most 8 degrees; a clear lane is kept in front of facing props; nothing
  within 2 cells of a corridor, 3 of the start / exit / a hellgate; flat floor only; blocking pieces never cut a room
  in two; decor is capped per room by size (`ThemeCtx`) and blocking pieces stay out of the middle.
- **Camera:** placement prefers walls whose pieces face the iso camera (signs only on those), so the front of a
  wall piece is what the player sees.
- **Lighting:** one accent OmniLight per room (`ThemeLight`), colour per theme (cinema blue flicker, spa candle
  warm, lab green, torture red, panic-room red pulse ...). `DungeonLook` keeps its own 12 downlights; the themes add
  at most one per room (8-9 a floor).
- **Dev flag:** `--to-theme <id>` puts the crew in the middle of the first room with that theme.

## Mail packages (interactive set dressing) [built, 2026-10-17]
**The premise:** the client never even opened their mail, so the crew can steal it. Taped-up brown
boxes, sometimes stacked 2–3 high, sit near room entrances as if just delivered: 4–6 stacks per floor.
Any hit breaks one: melee, arrows, spells, shoves, Rebar's bowl. It's unopened mail, so breaking it is
**not** property damage (never `Ledger.damage`).

| Contents | Chance | Effect |
|---|---|---|
| Pile of human skulls | 20% | decorative; tumbles out |
| Tubs of yogurt | 20% | decorative; rolls around |
| Loose pickles | 20% | decorative; scatters |
| Spell component | 25% | a normal component pickup (random castable spell, 3 charges); doesn't count toward the per-floor monster drop cap |
| Crypto cash | 15% | a random $200–$2,000 in whole $10s, earned on the invoice as "Unclaimed crypto (intercepted mail)" and shown as a green "+$1,240 crypto" pop |

Spilled decorative contents (a few skulls, yogurt tubs with their lids, green pickles) and the box's
flattened flaps shrink away so the spill is gone 30 s after the break, like other player-caused marks;
a torn-paper grime mark (`Grime.PAPER`) fades on the same clock.

- **Placement** (`SiteBuilder._plan_packages` → `SitePlan.packages`): a dedicated RNG seeded from the floor
  seed, so no prop, decor piece or pack moves. 4–6 spots a floor on open room floor, backed against a wall
  2–6 cells from the nearest corridor cell (near a door, never in the doorway or a corridor), outside the
  START / EXIT clear zones and hellgate zones, clear of every planned body (employees, notes, priced props,
  decor, the lanes kept open in front of them). One per room first, then two. A spot is 1 (58%), 2 (30%) or
  3 (12%) boxes of kind small / medium / long; an upper box is the same size or a small one, a little twisted
  and shifted. The cells go into `plan.blocked`, so no monster spawns inside them.
- **Actor** (`MailPackage`, scripts/contracts): neutral, immovable, 10 hp, and *any* damage breaks it. Each
  box of a stack is its own breakable (the model sits `lift` above the actor's ground point); when the box
  below breaks, the one above drops onto what is left under it. Group `"breakables"`. Contents are rolled
  from the box's own seed when it breaks (`MailPackage.roll_contents(rng)` is pure). Models:
  `PackageModels` (taped cardboard, shipping label, loose bits), spill: `PackageSpill`.
- **What breaks it:** `Combat.melee_arc`, `Projectile` and `ArrowShot` look at
  `GameWorld.hittable_in_radius` (the foe team plus the breakables group), which covers hero melee,
  Gasket's spin, arrows, Wick's bolt, the fireball projectile and monster swings and shots. Corn and teeth
  already hit every team, the fireball blast hits team neutral, tentacles and Rebar's bowl check the group,
  and an actor shoved into a box breaks it (credited to the shover). Priced props and employees are still
  not hit by melee or arrows.
- **Dev:** `--scene res://scenes/package_lab.tscn` (sizes, stacks, every contents spilled; `--shot`),
  `--to-package` puts the crew next to the first stack of the floor.
