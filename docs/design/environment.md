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
the crew's van keys, a "WET FLOOR" sign. It sets the tone in one glance. The **exit** is an elevator with its light on:
one style per job, a freight car or a brass one, set in a notch of a room's wall or free-standing in a room (a glass
shaft or a hex freight platform), its doors on a camera-facing side (`ElevatorModel`, `ElevatorGeo`, `ElevatorArrival`;
`elevator-options.md`, "Built"). Its sill strip (red shut, green open) and car light replace the old magenta exit hex.
- **Mesh rules it follows:** the wall car is a 3-cell notch the midpoint walls cut open (its back wall is a hex wall line;
  the slivers beside it sit under the jambs, which are solids); the free cars' corners stand on neighbour centres, so
  their sides lie on midpoint-wall lines. Their thin sides block bodies through `HexMap.solids`, not wall cells, so the
  terrain mesh (walls, caps, UVs) is unchanged.

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

## Materials: floors and walls per theme [built, 2026-10-17]
Rooms look like the place they are, inside the same look (dark hex columns, glowing amber seams). The **floor
material** drives the top face of each hex; the **wall material** drives the flat wall faces and caps of the
midpoint walls. Corridors take a neutral material per site, so the rooms stand out.

| Theme | Floor | Seams | Wall |
|---|---|---|---|
| Service entrance (start room) | concrete slabs | 0.9 | site wall |
| Home cinema | patterned carpet (deep maroon, faint gold lattice) | 0.3 (dim) | wood panelling |
| Wine cellar | wood boards (staggered planks) | 0.6 | wood panelling |
| Wellness spa | travertine tile | 1.0 | concrete |
| Indoor pool | aqua pool tile | 1.0 | concrete |
| Gym | rubber mats (studs, mat joints) | 0.55 | concrete |
| Server room | steel diamond plate | 1.0 | concrete |
| Panic room | diamond plate, dark rust | 1.0 | concrete |
| Throne room | dark marble slabs with pale veins | 0.85 | marble |
| Lab / vat room | pale green lab tile (small tiles) | 1.0 | stone blocks |
| Henchmen barracks | concrete slabs | 0.9 | stone blocks |
| Torture chamber | flagstone | 0.8 | stone blocks |
| Shark moat | flagstone | 0.8 | stone blocks |
| **Bunker corridors** | plain dark concrete | 1.0 | poured concrete (formwork lines, tie holes) |
| **Lair corridors** | dark rough flagstone | 1.0 | rough stone blocks (courses) |

"Seams" is the gain on the glowing seam and bevel glow of that floor (1 = the classic look): carpet and wood dim
them, tile and diamond plate keep them bright. Start seams keep their cyan (the exit's magenta only on a map without an
elevator). Raised ledges stay
wooden crates, stairs stay warm planks, cliff sides keep their slate bands (heights stay countable).
- **Data** (`scripts/world/floor_materials.gd`, `FloorMaterials`): `Cell.mat_id` packs the floor material (bits
  0-7) and the wall material (bits 8-15); 0 / 0 is the classic slate, so a map nobody assigned (menu garage, labs)
  looks as before. `SiteBuilder.plan()` calls `FloorMaterials.assign()` after the themes are dealt: room cells from
  their theme, corridors from the site type (`bunker` / `lair`), start / exit cells from their room, loose ledge
  cells from a neighbouring room, wall cells from the site. One pass over the cells (about 1 ms a floor, timed on
  its own in `FloorMaterials.last_usec`, outside `last_plan_usec`), no random numbers: spawn data from the seed.
  `game.gd` now plans the site in `_build_world()` (before the terrain is built) and spawns that plan after the
  spell picker.
- **Shader** (`HexMapView.MATERIAL_SHADER`): the floor tops and wall surfaces use a variant of the terrain shader.
  The per-vertex material index rides in `UV2.y`; the colours, pattern ids and roughness come from three small
  uniform arrays (`FloorMaterials.table_arrays()`). Patterns are procedural from the world position (floors: XZ;
  walls: along the flat face, taken from its normal, and height, so neighbouring faces continue each other):
  concrete slabs, flagstone (Voronoi), carpet, tile, wood boards, marble, rubber, diamond plate; formwork concrete,
  ashlar blocks, panelling, marble facing. No textures, no new draw calls or triangles (same surfaces as before;
  `tests/test_floor_materials.gd` checks it), and an unassigned map keeps the original shader. The vertex colour
  still tints each hex by height and per-hex variation, so heights and the hex grid read on every material.
- **Readability:** materials stay mid-dark (wall caps are darker than floors, like the slate caps); aim ring, grime
  decals, scorch, puddles and stairs were checked on each theme under its accent light.
- **Mesh rules** (`tests/test_wall_mesh.gd`): every vertical face maps its texture at one repeat per world unit
  across and one per level up, whatever its length or height (midpoint wall faces, half edges, stair sides and
  risers included; the material shader maps walls in world units from the face normal). Cap outlines of 4 or 5
  kites (a room's 120-degree corner seen from the wall side, an inside corner seen from the floor) are concave, so
  caps and seams fan from the hex center; all 63 wall masks are checked.
- **Dev flags:** `--to-theme <id> --zoom 11` (any theme), `--to-corridor` (the middle of the floor's corridors).

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
| Crypto cash | 15% | a random $200–$2,000 in whole $10s, earned on the invoice as "Unclaimed crypto" and shown as a green "+$1,240 crypto" pop |

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

## Breakable crates (decor) [built, 2026-10-17]
Anything that reads as a stack of boxes or crates breaks. Playtest: "a different stack of boxes which is not
breakable". The room themes' `crate_stack` (the panic room's `crates` op) was solid set dressing, so it is now a
`BreakableCrate` (scripts/world/themes), listed in `RoomThemeDefs.BREAKABLE_DECOR` (add a box-like kind there
and it breaks too). Shelves, racks, furniture, barrels and priced props stay solid.
- **Actor:** the piece's first blocker circle is the `BreakableCrate` (neutral, immovable, 10 hp, any damage
  breaks it, group `"breakables"`), so hero melee, arrows, Wick's bolt, Gasket's spin, corn, the fireball blast,
  tentacles, Rebar's bowl and shoves hit it exactly like a mail package. Other circles stay plain `DecorBlocker`s.
- **Breaking:** wood chips, a `PackageSpill` of planks (`"planks"`, no cardboard flaps) that shrinks away at
  30 s, a scuffed `Grime` mark and a little screen shake. The model and every blocker circle of the piece go
  away, so it stops blocking movement. NO contents, NO loot, and NOT property damage (never `Ledger`).
- **Networking:** a host-arbitrated world object. Every machine builds the same crates from the floor plan
  (`SPAWN`), the break is an event (`broke` is `OWNER`) and the debris is cosmetic, seeded from the crate's spot.
- **Terrain is different:** raised floor cells inside rooms (ledges, tiers, ziggurats) are drawn with the wooden
  crate texture (`HexMapView._find_crates`), but they are terrain and do not break.
- **Test:** `tests/test_breakable_crates.gd`. **Dev:** `--to-theme panic_room --break-crates 1.0`.

## Van arrival [built, 2026-10-17]
**The premise:** the crew are Licensed Budget Sorcery contractors, so they don't walk in: at the start of **floor 1** their
beat-up work van teleports in over a summoning circle in the start room and they climb out. Then it stays parked there for
the floor, as solid set dressing **and as one of the contract's two exits** (E at its side door clocks out; see
`contracts.md`, "Mission structure"). **The van parks on floor 1 only:** floors 2 and 3 have no van, no circle and no
arrival (the crew just starts on the start cell and its neighbours, as before the van existed), because the crew only
ever goes down.

- **Van** (`VanModel`, `scripts/art/lowpoly/props/van_model.gd`): about 2.0 x 4.2 x 2.2, a boxy white-grey panel van with a few
  rust patches, a roof rack (orange ladder, a copper and a PVC pipe, two ratchet straps, a wand antenna), a pipe wrench on the
  banner side, a sliding side door (slides rearward, violet glow and one shelf with bins inside), headlights and tail lights
  that can glow, wheels on a bouncing suspension, a small wand-and-wrench logo on both sides and the name as `Label3D` text:
  "CAST" on the door plate and on the other side's plate. Kept sparse on purpose: every attached piece has clear air around it
  and nothing sits in the door opening, on a wheel arch or on another piece. Side decals are stacked in levels
  (`DECAL_BASE` / `DECAL_STEP`, sunk into the wall) so no two faces are coplanar (no z-fighting). The tyres rest
  `RIDE_HEIGHT` (0.045) above the floor, clear of the 0.035 chalk circle; the suspension only moves the chassis. At the game
  camera the name reads; the logo, stripe, ladder and pipes carry the silhouette. Nose = +Z, door on the model's -X side.
- **Circle** (`VanCircle`, `van_circle.gd`): a shader-drawn pentagram in two rings with tick marks and rune glyphs on a flat
  quad. It has a glow look (amber HDR lines and halo, so it blooms) and a chalk look (faint broken lines) and blends between
  them; around it are a column of light, a shock ring, rising sparks and an amber light.
- **Placement** (`VanPlan`, `scripts/contracts/van_plan.gd`, called from `SiteBuilder._plan_van` right after the themes are
  dealt, **floor 1 only**: floors 2 and 3 plan `{}` and their start rooms are laid out without it; pure data in
  `SitePlan.van`, deterministic per floor, no random numbers). The pose is searched over every flat
  start-room cell within 5 cells of the start, 18 yaws:
  - the whole body plus a 0.4 x 0.55 margin is flat floor of the start room's base level (strictly flat cells first), at
    least 2 cells from any corridor cell (a cramped room relaxes this to 1 and shrinks the margin; it still fits 600 of 600 floors tried);
  - the crew's three standing spots beside the door are flat, outside the body and spaced out;
  - the van's blocked cells never include the start cell, and removing them strands no walkable cell (a BFS around the
    start before and after);
  - best score wins: the door faces the iso camera (3.0 x the dot product with `ThemeGeo.CAMERA_DIR`), the nose points toward
    the elevator, near the start, away from the corridors.
  It is registered as a body and as solid cells in the start room's `ThemeCtx` before the props, notes, decor and packages
  are planned, so none of them lands on it (notes also keep a metre away); its cells and the crew spots go into
  `plan.blocked` so no monster spawns there. Across 5 archetypes x 40 seeds x 3 floors it always fits.
- **Solid, not priced:** `VanArrival` adds four invisible `DecorBlocker` circles (r 0.98) along its axis, the same actors
  blocking decor uses, so heroes and monsters walk around it. It is not an `Actor`, not in the priced-prop list and takes
  no damage (the blockers return 0), so no property damage is ever charged. The van is also an **exit**: `game.gd` opens
  the clock-out slip (`VanExitMenu`) on E within 2.8 of the plan's `door` point (floor 1 only), a request the host arbitrates
  like the elevator's. The elevator and its menu keep working as before.
- **Arrival** (`VanArrival`, `scripts/contracts/van_arrival.gd`, wired in `game.gd`'s `_arrive_by_van()` after the site is
  built; it returns at once on floors 2 and 3): a plain timeline, every moment a function of `time`:

  | t (s) | what happens |
  |---|---|
  | 0.00 | the circle ignites: a ring of amber light draws itself around, then the star; sparks rise, a column of light grows |
  | 0.80 | POP: flash, smoke, camera nudge; the van appears as a tall thin streak above the circle and drops |
  | 1.06 | it lands (squash and stretch, dust ring, shake, a shock ring races over the floor); signal `landed` |
  | 1.22 | two honks and headlight flashes; signal `honked` (the audio hook, no sound assets exist yet) |
  | 1.32-1.78 | the side door slides open, violet light spills out; signal `door_opened` |
  | 1.55-2.4 | Wick, Gasket and Rebar step out one after another (0.15 s apart) to their spots beside the door |
  | 2.50 | `finished`: control goes back to the player; the headlights dim to a parked glow |
  | 2.1-3.5 | the circle fades from glowing amber to a faint chalk mark that stays for the floor (non-blocking) |

  The crew is hidden and the controller and ally brains are off until then; the player is never stuck: any key, click or
  pad button calls `skip()` (jumps to the parked state), and the timeline ends by itself at 2.5 s. Pause and the elevator
  freeze stop it like everything else.
- **Flags:** `--no-van-intro` skips the animation (the van is still parked and the crew stands beside it); tests (`--run-test`)
  and `--shot` screenshots skip it by default; `--van-intro` plays it anyway (`--shot-after 1.2` catches the landing). The
  dev teleports (`--to-gate`, `--to-theme`, ...) also skip it.
- **Lab:** `--scene res://scenes/van_lab.tscn` (`--shot <png>`, `--t <seconds into the arrival>`, `--view game|close|far|side|other|rear|front|top`,
  `--van-yaw`, `--no-crew`). Without `--shot` the arrival replays every 8 s.
- **Networking** (checklist in `networking.md`): shape = a host-arbitrated world object planned from the seed (`SitePlan.van` and
  the blockers are `SPAWN`, identical on every machine) plus a **cosmetic** arrival (the timeline and every visual are
  `LOCAL`). Each player's machine walks its own hero out; allies and everything else follow the host as usual. A player who
  joins mid-floor sees the parked van (`park()`: door open, chalk circle) and no animation. No randomness (the model's
  noise uses seeded generators).
