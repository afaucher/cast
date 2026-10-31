# Haunted contracts: build plan

Status: **[proposal; H1 and H2 built 2026-10-31, see "H1 as built" and "H2 as built"]**. The design is `new-themes.md` ("Ghost house: haunted contracts"); this is the order to
build it in. The user (2026-10-31): "Let's build it as is" (today's roster; more enemy types are worked out in parallel).

Today none of it is game code: the mansion and church rooms, the crypt, the zombies, acolytes, ghosts, hosts and the
grimoire are look-dev (labs, gym spawns, cosmetic nodes; the look tests assert it). Each step below ends playable, solo and
crewed, and keeps the floor checksum and `test_net_contract` whole. One step at a time; each is reviewed in the game before
the next.

## What the game has to change (the map)
- **Site and pest come from the client.** `ContractRun.make` (`contract_run.gd:67-99`) takes `site_type` ("bunker" or
  "lair") from `ClientArchetype.DATA` and rolls one `pest` kind. Many places switch on `site_type`: `RoomThemeDefs.POOLS`
  and `ORIGIN_THEMES`, `PricedProp.catalog`, `FloorMaterials.SITE_WALL` / `SITE_CORRIDOR`, `SewerCluster.SITES`,
  `EmployeePlanner`, `PropPlanner.LANDING_KINDS`, the job card. There is no pest family: any pack kind can appear anywhere.
- **Objectives are gates.** `ContractRun._build_objectives` makes "gate", "origin" and "pest"; `ContractSession` and the
  Ledger count gates. Closing the origin gate stops its spawns; the contract still ends at the elevator or van.
- **Sections** (sewer, lava cave) roll in `DungeonGen.for_run` / `generate`, plan in their planners inside
  `SiteBuilder.plan` (a checksummed draw order), and join the checksum through `NetFloor.map_text_of` (`sewer=`, `cave=`).
- **Monsters die and are freed.** `Monster._on_death` topples, fades and frees; no monster can be revived
  (`Actor._can_revive` is false, `downed_in_radius` finds heroes only). A body that stays down is new work.
- **No Ghost spell exists.** `Actor.pass_through_until` (carried by `NetCodec` FLAG_GHOST) is the nearest mechanic.

## The steps

### H1. Haunted sites and the dead family
- Two new site types, **mansion** and **church**, from new client rows in `ClientArchetype.DATA`, with a new SPAWN field on
  `ContractRun`: **`family`** ("gate" or "dead"). One family per contract: a "dead" contract has no hellgates
  (`GatePlanner` skips it) and its packs come only from its family.
- Each `site_type` switch gets mansion and church rows: room pools from the decided rooms (mansion: library, portrait
  gallery, ballroom, dining hall, conservatory, the wine cellar; church: the nave), priced antiques in `PricedProp.TABLE`,
  wall and corridor materials, employees, the job card.
- Until H3 the family's only monster is today's skeleton (`grunt`, shown as "Skeleton"), and the objective is the pest
  kind. Bunker and lair floors stay byte-identical (`test_golden_floor`).
- Networking: nothing new in shape (site and family are SPAWN on the run, so in the checksum's run part).
- Open: the church has one room (the vestry and bell tower were dropped), so a church floor needs more rooms or leans on
  its crypt. The client names and card text are proposals for the user to review first.

### H2. The crypt section
- A `CryptCluster` like `SewerCluster`: it rolls on mansion and church floors, a `DungeonGen.Builder` hook carves it, a
  `CryptPlanner` themes and dresses it (the vault and chapel sets of `CryptLook`, sarcophagi, ossuaries, candles), and
  `map.crypt` joins the checksum as a `crypt=` line in `NetFloor.map_text_of`.
- Networking: floor data only (the sewer's shape). Crypt props that break are `PricedProp` rows.

### H3. Zombies and bodies
- A `zombie` monster kind (the mourner and digger looks): a slow melee shamble. **A zombie that dies stays down as a body**
  (a downed state on the monster, not `queue_free`); only an acolyte or Coffee stands it back up, and burning a body keeps
  it down. Coffee's splash raises a downed zombie (`downed_in_radius` learns monster bodies; the target's owner applies it,
  like a revive). Heal stays allies-only. **To revisit here:** whether Heal raises zombies too.
- Networking: an owned actor (a host monster); `downed` and `burnt` are OWNER fields with carriers; a late joiner gets the
  bodies from the keyframe.

### H4. Acolytes and the procession
- An `acolyte` monster kind on floors 1-2: it flees heroes, travels the floor in a **procession** (a leader, its zombies
  and a rear acolyte, as in the look test) between rooms, and raises the bodies it passes. Paid per kill; the objective on
  floors 1-2 is the acolytes. **To revisit here:** the procession in the game (the user: "We will try it in the game when
  it is ready").
- Networking: host monsters; the procession is a host-owned group (its route is PRIVATE to the host, its members
  replicate as usual). A raise is a world event like a monster wind-up.

### H5. Ghosts and possession
- **Hosts:** a suit of armour and a skeleton spawn dormant as host monsters, priced like props. Breaking a possessed
  antique bills the crew; bones do not. **Wisps:** a ghost keeps away from heroes unless it holds a host; breaking the
  host hurts it and sends it to the next host. Tentacles pass through ghosts. The soft outline is cosmetic per machine (the
  look the user picks from `ghost-look.md`). **To revisit here:** the possessed knight, animated.
- Networking: a dormant, priced host monster with a possessed state is a new shape ("a prop turning into a monster fits
  no shape yet"): designed and written up before it is built.

### H6. The grimoire and the haunted invoice
- The last floor's source: a `Grimoire` actor in the hellgate's shape (tuning by difficulty and depth, phases, bursts of
  the dead, `closed`), slammed shut or burned. The `grimoire_model.gd` look (the altar, the live eye) becomes its model.
  Objective kinds and Ledger lines for acolytes and the grimoire; the invoice reads like a hellgate contract's.
- Networking: the hellgate's (a state codec, world events, a REPLICATED row and a LATE_JOIN entry).

### H7. Ghost form
- The Ghost spell cast on yourself: a whole-body transform; you pass through regular enemies but still get hit by their
  attacks; it is for fighting ghosts. Open: whether a ghost-form hero can hit regular enemies, its duration and cooldown.
- Networking: a status on the hero (its owner resolves and announces it); the pass-through flag already replicates.

### Later
- Ectoplasm as the infestation layer (slicks the floor, Damp washes it away), and the new enemy types from the look tests
  under way (crypt rats, the ecto blob).
- Evicting a ghost without breaking its host (wanted, deferred). Ghost mode after a hero dies (a big build, later).

## Tests per step
Each step runs its touched tests plus `test_net_contract`, `test_golden_floor` and the generation tests it touches; the
full suite runs before it merges.

## H1 as built (2026-10-31)

The user (2026-10-31): "Just build it now. We can revisit the decisions after it's built." So every open call below was made
on the spot, the simplest sound choice, and is listed here to revisit.

### What was built
- **Two haunted clients** (`ClientArchetype.HAUNTED_IDS`): `heir` (the estate heir, a **mansion**) and `parish` (the parish
  council, a **church**). Their rows carry `"family": "dead"`; every hellgate client is `"gate"` (`ClientArchetype.family_of`).
  `ClientArchetype.IDS` is still the five hellgate clients, untouched; `ALL_IDS` is the seven (IDS first, so every hellgate
  client keeps its index in `ContractRun.make`'s dice).
- **The pest family** is a SPAWN field, `ContractRun.family`. A dead contract (`has_gates()` false): `floor_gates` [0, 0, 0],
  no gate or origin objective, its pest is the family's (`FAMILY_KINDS["dead"]` = `["grunt"]`, "skeletons"), its packs come
  only from those kinds (`MonsterFactory.compose(..., only)`, `SiteBuilder.biased_composition`), no goblin scouts
  (`SiteBuilder.scout_count`), no lava cave (`LavaSite.seed_for`) and no sewer cluster (`SewerCluster.SITES`). `GatePlanner`
  places no gate; on the last floor it still picks the origin room (the story's room: its theme and its story note), with
  no gate in it. The contract ends at the elevator and the van as today; the tracker and the elevator form already show only
  the rows a floor has.
- **Getting one:** the board deals one haunted offer on `ContractBoard.HAUNTED_CHANCE` (half) of its boards, on dice of its
  own; the slot keeps its seed and difficulty tier, and every other offer is the one that board always dealt
  (`test_haunted_contract` replays the old board). The dev flag **`--client heir`** / **`--client parish`**
  (`ContractBoard.run_for_client`, with `--seed`) starts one without the board; no new keybinding.
- **Rooms** (`RoomThemeDefs`): mansion pool = library, portrait gallery, ballroom, dining hall, conservatory and the wine
  cellar; church pool = nave plus the library, dining hall and portrait gallery. New themes `library`, `gallery`, `ballroom`,
  `dining_hall`, `conservatory`, `nave`; origins `library`, `ballroom`, `dining hall`, `nave`, `refectory` in
  `ORIGIN_THEMES` (and keywords). Their decor is the look test's props through the existing decor system: DECOR rows with
  `"haunt"` (a HauntProps kind; `DecorModels._haunt` builds it, seeded from the placement), placed by the recipes' ops
  (`HauntVignettes`: reading nook, runner, dance floor with the chandelier over the medallion, banquet, planters, the nave's
  altar on its step with two blocks of pews; plus the small makers: bookshelves, portraits, gilt chairs, candelabra,
  sconces, mirror, fireplace, palms, citrus, ferns, garden bench, pillars). A `"moonlit"` theme (conservatory, nave) puts
  its candles out (`RoomThemes.plan_decor` sets `params.unlit`) and has a cold accent light; the house rooms are candle-lit
  (their candles' small warm lights, a warm accent light).
- **Materials:** walnut & damask, terracotta and glazing, and limestone are the game's now: rows in `FloorMaterials.HIGH`
  (the free shader slots 24-31, the look test's layout: floors 27, 29, 30; walls 8, 10, 15) and their patterns in
  `HexMapView.MATERIAL_SHADER` (herringbone, damask / stripe over a dado, glazing; wall caps from `cap_base`, the glazing's
  cap a glass roof). Halls: the mansion's are wood boards between damask walls, the church's limestone flags and blocks
  (`SITE_CORRIDOR` / `SITE_WALL`). `HauntLook` now draws with the game's shader and table; only the oak & stripe set stays
  lab-only (`HauntLook.LAB_ROWS`, on a copy of the table).
- **Priced antiques** (`PricedProp.TABLE`): a row's look may be `"haunt"` (a HauntProps kind) or `"node"` (the suit of armour:
  `PropModels._suit_of_armour`, the ghost look test's `ArmourModel`, dormant). A new optional `"sites"` puts a row in other
  site catalogs (the wine cellar's racks in the mansion; the parish rooms' antiques in the church). Landing set pieces:
  `PropPlanner.LANDING_KINDS` mansion / church. Bones are no row (free to smash).
- **Employees:** the haunted sites have staff (`EmployeePlanner.STYLES`: the staff look and `STAFF_NAMES`).
- **Notes and dispatch:** story notes and slip headers for both clients (`NoteCopy.STORY` / `HEADERS`), and
  `NoteCopy.DISPATCH_DEAD` (floor banners without a gate; `NotePlanner` picks it for a dead contract). The gate hint slips
  never fill on a gate-less floor. `DispatchVoice.all_lines` lists the new lines (their clips are not rendered yet: the
  banners are silent until `tools/render_dispatch.ps1` runs).
- **Job card:** the SITE line from `ClientArchetype.SITE_TITLES`; a dead contract's objectives table is the pest and the staff.
- **Networking:** nothing new in shape. `family` is SPAWN, derived like the rest of the run from (archetype, seed,
  difficulty), which the crew already sends. The floor checksum's run part leaves `family` out while it is `"gate"`
  (`NetFloor.RUN_DEFAULTS`), so every hellgate floor hashes as before; a haunted floor hashes it in. The haunted floors are
  plain floors plus decor and priced props (host-arbitrated objects, as before).
- **Bunker and lair floors are byte-identical:** `test_golden_floor` passes against the recorded `tests/golden/floors.json`,
  unchanged (`run_for_seed` still deals from `IDS`; the board's hellgate offers are unchanged per board seed).
- **Look-dev headers** (HauntProps, MansionProps, ChurchProps, the two room labs, ArmourModel, HauntLook) and the look docs'
  status lines say what is now the game's; the look tests check the game's shader and table instead of "untouched".
- **Tests:** `tests/test_haunted_contract.gd` (new): the tables, the runs (no gates, pest-only objectives, skeletons), the
  board (haunted offers on their own dice, every other slot unchanged), and each client's floors 1-3 built as the game does
  (no gate, no section, skeletons only, haunted rooms dressed with the look test's props, site antiques, staff, notes and a
  dispatch line naming no gate, the room materials, the same checksum on two builds, the family hashed in).
  `test_room_themes` (the haunted themes' signature vignettes place), `test_priced_prop` (the antiques spawn priced),
  `test_floor_materials` (the haunted slots) and `test_mansion_rooms` (the game's shader and table) were extended.

### The calls made (to revisit)
1. **The client set.** One client per haunted site: the estate heir (mansion) and the parish council (church).
2. **IDS stays the hellgate clients**; the haunted ones are `HAUNTED_IDS` (else `run_for_seed`'s `seed % IDS` and the board's
   shuffle would move every recorded floor and board).
3. **How often the board deals one:** half the boards, in one slot (`HAUNTED_CHANCE` 0.5), replacing that slot's client.
4. **Pay without gates:** the pest objective adds `DEAD_PEST_BONUS` ($10,000, before the client's scale), so a haunted
   contract's one paid objective is worth about what an origin gate adds (H4 / H6 bring the acolyte and grimoire pay
   lines). Its contract value (the damage cap) is still under a hellgate job's.
5. **The church's rooms:** the nave plus the mansion's library, dining hall (the "refectory" origin) and portrait gallery, as
   parish rooms, until the church has more rooms of its own or its crypt (H2). They keep the mansion's walnut & damask.
6. **Moonlight and candle light are per room**, through the existing accent light and the candles; the scene's light stays the
   game's (no global relight). The conservatory and the nave have their candles out and a cold accent light; the house rooms
   their candles lit (each candle cluster has a small warm OmniLight: many lights on a mansion floor, watch the frame rate).
7. **Seats and pews are walked through** (like the cinema's recliners); shelves, tables, the altar, planters, palms and
   pillars block. The altar stands on its step (lifted 0.25).
8. **The ballroom and dining hall need the room's middle** (`needs_center`): never dealt to the exit room or a crowded room.
9. **Halls:** the mansion's are plain wood boards between damask walls (the parquet is the rooms'); the church's are
   limestone. The service entrance keeps its concrete.
10. **Antique prices and HP**, and which antiques the church shares (`"sites"`). Wall pieces: armour, piano, sideboard,
   Wardian case, stained glass, votive stand; corner pieces: globe, bust, candelabra, font, lectern.
11. **Landing set pieces:** mansion armour / bust / candelabra; church bust / votive stand / candelabra.
12. **Staff:** the haunted sites have staff (the bunker's names and look), not henchmen.
13. **No goblin scouts** on a haunted floor (the goblin is a demon). No sewer or lava on haunted sites in H1.
14. **The origin room still exists on the last floor** of a haunted contract (the story's room, its note), with no gate.
15. **The checksum:** `family` is left out of the run part at its hellgate value (`NetFloor.RUN_DEFAULTS`) rather than
   re-recording the golden floors.
16. **The portrait's picture** is the placement's variant (`v` = variant % 5), so a gallery shows a mix.

### New player-facing strings (proposals for review)
- **Estate Heir**: site name "Ancestral manor"; names Peregrine / Cordelia / Ambrose / Octavia / Bartholomew / Winifred +
  Ashgrove / Blackthorne / Mortlake / Ravensworth / Hollowell, suffixes "the Younger", "Esq."; companies "The %s Estate",
  "%s Heritage Trust", "%s Family Office (Probate)"; address "The Hall, up the long drive, ring twice"; tagline "Old money.
  Older tenants."; dept "Office of the Executor"; warning "Property: four centuries of antiques, a suit of armour and the
  family portraits. Mind the portraits."
  - Events (card / dispatch / origin): "The will was read at midnight, as the will insisted." / "They read the will at
    midnight and something in the house took it personally. Some of the staff are still in there. Bring them out." /
    library. "A seance was held in the ballroom to settle who gets the silver." / "Someone held a seance in the ballroom
    over the silver, and the dead turned up to contest it. Some of the staff are still down here. Bring them out." /
    ballroom. "The anniversary dinner set a place for great-grandfather." / "The anniversary dinner set a place for
    great-grandfather, and he came. Some of the staff are still serving. Bring them out." / dining hall.
  - Footers: "The family thanks you. The family is large, and not all of it is living." / "Adequate. Great-grandmother has
    been informed. She is not pleased." / "The estate will be in touch. So, we suspect, will the house." / "Your crew has
    been incapacitated. The house has asked whether they may stay."
- **Parish Council**: site name "Parish church"; names Reverend / Canon / Deacon / Mother / Father / Archdeacon + Whitlow /
  Penhallow / Ashby / Greaves / Underhill, suffixes "(retired)", "OBE"; companies "The %s Restoration Fund", "St. Agatha's
  Parish Council (%s, chair)", "The %s Bequest"; address "The vestry door, round the back, past the yews"; tagline "All
  are welcome. Most are invoiced."; dept "Parochial Church Council (Finance)"; warning "Property: a medieval font, the
  stained glass and the votive stand. The lead on the roof is already gone."
  - Events: "The bell-ringers rang a peal that is not in any book." / "The bell-ringers rang a peal nobody wrote, and the
    churchyard got up to listen. Some of the staff are still inside. Bring them out." / nave. "Evensong ran long. Something
    stayed for the sermon." / "Evensong ran long and something stayed for the sermon. Some of the staff are still in the
    pews. Bring them out." / nave. "The harvest supper raised more than the roof fund." / "The harvest supper raised more
    than the roof fund. Some of the staff are still at the tables. Bring them out." / refectory.
  - Footers: "Thank you. A collection will be taken. It will not be for you." / "We give thanks for what was saved. A list
    of what was not is enclosed." / "The council has prayed over your invoice. The answer was no." / "Your crew has been
    incapacitated. They are in our prayers, and in the minutes."
- Job card SITE line: **Haunted mansion**, **Haunted church**. The objective is "Exterminate skeletons" (the existing pest name).
- Rooms (name / note word): Library / library, Portrait gallery / portrait gallery, Ballroom / ballroom, Dining hall /
  dining hall, Conservatory / conservatory, Nave / nave.
- Antiques (name, price): Suit of armour $6,000; Grand piano $14,000; Antique globe $2,200; Marble bust $4,500; Silver
  candelabra $1,800; Mahogany sideboard $5,200; Wardian case $3,200; Stained glass window $12,000; Baptismal font $9,000;
  Brass lectern $2,600; Votive stand $900.
- Note headers: heir "Household Ledger", "From the desk of {client}", "Below Stairs", "House Rules"; parish "Verger's Book",
  "Parish Notice", "Suggestion Box", "Church Notice".
- Story notes: `NoteCopy.STORY["heir"]` and `NoteCopy.STORY["parish"]` (13 and 12 lines, `scripts/contracts/note_copy.gd`).
- Dispatch banners (`NoteCopy.DISPATCH_DEAD`): "The {pest} on this floor are still getting up. Put them down and keep
  going." / "Halfway down and the {pest} are thicker. Some of the staff made it this far. Find them, then find the
  elevator." / "This is where it started, in the {origin}. Put the {pest} down and get everyone out." / "The {origin}'s on
  this floor. Whatever got up down here, put it back down."

### Not done in H1
- The dispatch voice clips for the new lines (silent banners until `tools/render_dispatch.ps1` is run).
- No crew (two-PC) play of a haunted contract yet; the checksum test covers the floor build.
- The church has one room of its own; its crypt is H2.

## H2 as built (2026-10-31)

The user (2026-10-31), as for H1: "Just build it now. We can revisit the decisions after it's built." Every open call below
was made on the spot, the simplest sound choice, and is listed to revisit.

### Play it

```
.\run.ps1 --client heir --seed 1 --floor 2 --spells heal,fireball --no-mic --to-crypt lit     # a vault under the mansion
.\run.ps1 --client parish --seed 2 --floor 1 --spells heal,fireball --no-mic --to-crypt lit   # a chapel under the church
.\run.ps1 --client parish --seed 1 --floor 3 --crypt-floor --to-crypt dark                     # forced, in its dark room
```

- **Natural crypts** (`ContractBoard.run_for_client`, seed/floor): heir 1/2, 1/3, 2/2, 5/2; parish 1/2, 1/3, 2/1, 2/2. The log
  names the crypt, its set, its lit and dark rooms and the stair's head ("crypt: ...").
- `--crypt-floor` (`CryptDev`, `CryptCluster.force`): every floor gets a crypt where a wing fits, whatever the site, floor or
  roll (a hellgate site gets a vault); every window of a crew needs it. `--to-crypt head|foot|lit|dark` (solo) starts the crew
  at the stair's head (in the room above), its foot, or in the first lit or dark room. `--crypt-perf` measures the crypt's
  lights and quits. No keybinding.
- Screenshots (the game camera, 1920x1080): `docs/design/crypt_section/game_vault.png` (heir 1, floor 2: the burial vault),
  `game_chapel.png` (parish 2, floor 1: the crypt chapel), `game_stair.png` (heir 1, floor 2: the arch at the stair's head in
  the mansion room above, the dark stair down with its landing candles).

### What was built

| Piece | Where | What |
|---|---|---|
| Which floors | `scripts/world/crypt/crypt_cluster.gd` (`CryptCluster`) | `seed_for(run, floor, shared)` on dice of its own (the same shared or solo): the mansion's floors 2-3 at `RATE` 0.5, the church's floors 1-3 at 0.75. `set_for(site)`: the vault under a mansion, the chapel under a church |
| The cut | `DungeonGen` "crypt" option (`for_run` asks for it on a floor that rolled no sewer cluster; no cave beside it) | The sewer cluster's machinery with CryptCluster's numbers: a wing of 2-4 rooms (never the start or the elevator's room) lowered 4-6 levels to one base level, its own links flat, no features, the narrow stair of STAIRS flights (at most 3 levels a cell) the one way in. Any failure builds the attempt without it. The record is `HexMap.crypt` (the sewer record's shape plus the stair's `route`), a SPAWN var |
| The checksum | `NetFloor.map_text_of` | A `crypt=` line on a floor with one (the record, with the planners' `set`, `lit`, `dark`, `tombs`); every other floor's text is as before |
| Themes | `CryptPlanner.theme`, `RoomThemeDefs.CRYPT` | The crypt's rooms take the crypt themes of the set, LIT and DARK by turns from the stair's foot (the foot's room lit). Vault: `burial_vault` (lit) and `bone_vault` (dark); chapel: `crypt_chapel` and `chapel_ossuary`. Never dealt from a pool |
| The origin room | `GatePlanner` | A crypt's rooms are never the origin room (nor a gate's): the story's room stays a house room |
| Sarcophagi | `CryptPlanner.plan_tombs`, `PricedProp` "vault_sarcophagus" / "chapel_sarcophagus" | In each lit room a ROW of 1-3 (by the room's size) priced sarcophagi head to one wall, side by side 1.7 apart, facing into the room (the vault's effigy lid, the chapel's cross): `SitePlan.props`, on the crypt's own dice (lent to the ThemeCtx), after the floor's priced props and set pieces (extra to `MAX_PROPS`). Site "crypt": no site's catalog |
| Dressing | `CryptVignettes` (ops in `ThemeVignettes.OPS`), DECOR rows with "crypt" (`DecorModels._crypt` builds `CryptProps` in the room's set) | `vigil`: a lit candelabra at each end of the row, candles at each sarcophagus's foot. `ossuary`: a bone wall on a straight run of wall, centred and no wider than it (`CryptProps.wall_run`, the lab's placement, moved there from the lab). `crypt_candles` (a corner cluster), `bones` (a fallen skeleton off the middle), `open_tomb` (an opened sarcophagus, decor), `shaft` (the chapel's pale light from above, `CryptLook.shaft`). Lit rooms: vigil, ossuary, candles, bones (a second ossuary in a big room); dark rooms: two or three ossuaries, an opened tomb, bones; the chapel's rooms a shaft each |
| Doorways | `DoorPlanner`, `CryptPlanner.doorways` / `gate` | No office door on a crypt doorway or at the stair's head. A stone arch at the head (in the room above), an open iron gate at the foot (0.85), a half-open gate into a lit room (0.45), an arch into a dark one: decor across the doorway (`crypt_gate`, `crypt_arch`; nothing shuts) |
| The stair | `CryptPlanner.dress` | Lit candles on the landing between its flights (the flat route cell nearest its middle) |
| Materials | `FloorMaterials` slots 32-37 (`F_VAULT`, `F_VAULT_HALL`, `F_CHAPEL`, `F_CHAPEL_HALL`, `W_VAULT`, `W_CHAPEL`), `CryptPlanner.materials` | The look test's colours as game rows (the table grew from 32 to 40 slots; `HexMapView.MATERIAL_SHADER`'s arrays with it). Rooms from their theme rows; the crypt's halls and stair in the hall rows; the walls only the crypt touches in its blocks |
| Light | `HexMapView` (`UNDER_LAYER`, `under_instance`), `FloorMaterials.is_under` / "ambient", `DungeonLook`, `CryptPlanner.spawn` | The crypt rows are "under": HexMapView draws those cells into a second mesh on its own render layer, which the key and fill lights leave out (`light_cull_mask`), and the shader's AO takes the row's share of the ambient (vault 0.5, chapel 0.9: the lab's dim warm vault and cooler chapel). No downlight over a crypt room. `CryptPlanner.spawn` puts the decor and priced props standing on the crypt's floor on that layer too. So the candles, the rooms' dim accent lights and the chapel's shafts light the crypt, as the look test lit it, while the crew, the monsters, the staff and the rest of the floor keep the game's light. A floor without a crypt builds one mesh, as before |
| Dev | `scripts/app/dev/crypt_dev.gd` (`CryptDev`), `GameDev._crypt_floor_ready` | The flags above |
| Look-dev | `CryptLook`, `CryptProps`, `crypt_section_lab.gd`, `wall_depth_lab.gd` | Headers say what is the game's now. `CryptLook`'s sets name the game's rows (`restyle` / `tables` are gone; the lab paints with the rows, the room above in H1's walnut & damask or limestone, and the lab's view keeps the seam gain at 1 since the rows carry it). The wall depth lab's "lair" view repaints its map in the lair's rows. The kit's ossuary back and shelf, the arch's keystone, the gate's meeting bars and the cross lid moved apart by a centimetre or two where faces were coplanar (`test_zfight`) |

### The calls made (to revisit)
1. **The crypt is the sewer cluster's twin in the generator**: a wing of 2-4 rooms at one level, flat links, reached only by
   its stair; a floor gets a sewer cluster or a crypt, never both (haunted floors roll no sewer yet, so this never bites).
2. **How often:** the mansion's floors 2-3 at 0.5, the church's floors 1-3 at 0.75, so the church leans on its crypt
   (measured over 24 contracts each: 14 of 48 mansion floors 2-3 have one, 29 %; 36 of 72 church floors, 50 %).
3. **How deep:** 4-6 levels (2.0-3.0) under the room above, in flights of up to 3 levels (the look test's was 6, two flights).
4. **The set by site:** a vault under the mansion, a chapel under the church; a forced crypt on a hellgate site is a vault.
5. **Lit and dark rooms by turns from the stair's foot** (the look test's burial chamber, then its dark gallery). The lit
   room is the burial room; the dark room the bone room.
6. **Sarcophagi bill, in a row against the wall**, not in the room's middle as in the lab (every room keeps its middle clear
   for the fight; a row head to the wall still reads as the lab's chamber). $7,500 each, HP 140 (stone: a fireball dents it,
   it takes a fight to break one). The opened one in the dark rooms is decor (already broken open). Extra to `MAX_PROPS`.
7. **Candelabra in the crypt are decor** (lit, unpriced), the vigil's. A lit crypt room may also get the site's priced silver
   candelabra or a marble bust by a wall (its theme's "priced"); a dark room only the bust (no flame in the dark), never a
   piano.
8. **Gates are open decor**, never shut and never an office door: 0.85 open at the stair's foot, half open into a lit room,
   an arch into a dark room and at the stair's head. A locked gate needs a design (a key, a lever, a shove).
9. **Bones are decor**: free in the design, and nothing breaks them yet (H5's possessed skeletons are the bones that matter).
10. **The origin room is never a crypt room** (nor a hellgate's room on a forced crypt): the story's room stays a house room.
11. **Light: the crypt is out of the key light** (its own render layer), with a share of the ambient per set and no
   downlight, its pieces too; the crew, monsters and staff keep the key light so a fight stays readable. Without it the chapel
   read as a pale sunlit room (the game's key light is 0.9; the lab's was 0.04-0.08). Each crypt room has a dim accent light
   (lit rooms warm, 2.2-2.4; dark rooms cool, 1.0-1.2).
12. **Seams as the lab showed them** (its view-wide gain times the recoloured rows' own): 0.064 / 0.08 in the vault, 0.08 /
   0.1 in the chapel. Out of the key light the amber seams carry the dark rooms' floors, as in the lab's sheets.
13. **Materials:** the table grew to 40 slots (slots 22, 23 were the only free ones in the game's table); the halls have rows
   of their own (a shade darker), as in the lab.
14. **Packs:** the crypt's rooms get the floor's packs like any room (the contract's family: skeletons until H3); staff, notes
   and mail may land there too, as in a sewer cluster.
15. **No crypt room in the gym** (the look test's loose pieces stay in its panel); `--crypt-floor` is the dev way in.

### New player-facing strings (proposals for review)
- Rooms (name / note word): **Burial vault** / burial vault, **Bone vault** / bone vault (under a mansion); **Crypt chapel** /
  crypt chapel, **Ossuary** / ossuary (under a church).
- Priced prop: **Stone sarcophagus**, $7,500 (both sets).
- No new notes, signs or dispatch lines.

### Tests
- `tests/test_crypt_gen.gd` (new): the tables (both sites roll, the church more; the crypt themes, their recipes and their
  rows; the sarcophagi priced and in no catalog; every crypt decor kind builds in both sets; candles carry their light); no
  bunker or lair floor rolls one (seeds 1-40); 24 contracts of each haunted client, floors 1-3: the crew rolls the solo
  floor's crypt; every crypt has 2-4 rooms at one level 4+ levels under the room above, never the start or the elevator's
  room, a stair of flights from its head to its foot, every room reachable; its rooms are the set's crypt rooms in the set's
  floor, lit and dark by turns; sarcophagi in the lit rooms, heads at a wall; bone walls backed by wall along their width;
  candles; an arch or a gate in every crypt doorway, no office door; the chapel's shafts; `crypt=` in the map text and no
  sewer or cave beside it. Three crypt floors per client spawned and built twice: the same checksum and net ids, the
  sarcophagi spawn priced, only skeletons in the crypt, candle lights, the pieces and the stone on the underground layer, the
  key and fill leaving it out, no downlight over it. A haunted floor that rolled a crypt but got none is the generator's
  floor without the option (map and plan checksums), with nothing underground. `--crypt-floor` forces one (a vault on a
  hellgate site) and the floor is as before without it.
- **H1's haunted floors without a crypt are byte for byte H1's**: every floor 1-3 of heir and parish contracts 1-24 was built
  as the game builds it on H1 (7c05fe5) and on H2 and its NetFloor checksum parts compared: all 94 floors without a crypt
  match in map, plan, run and spawn (50 have a crypt). `test_golden_floor` passes against the recorded floors (bunker and
  lair floors never roll a crypt).
- Updated: `test_haunted_contract` (a crypt's rooms are crypt rooms, its sarcophagi not the site's catalog), `test_crypt_section`
  (the sets are the game's rows), `test_priced_prop` (a "crypt" row's model), `test_room_themes` (a "crypt" decor row).
- Frame rate (`--crypt-perf`, RTX 3080, 1600x900 view): 9 crypt lights on heir 1 floor 3 (25 other lights on the floor) cost
  0.05 ms of GPU (4.75 against 4.70 ms); 13 on parish 1 floor 3 (23 others) 0.02 ms. 60 fps.

### Not done in H2
- No crew (two-PC) play of a crypt; `test_crypt_gen` covers the checksum on two builds and the shared roll.
- No crypt dispatch line, sign or note; bones do not break; no locked gate; no gym crypt room.
- `test_zfight` still fails on ten of H1's pieces (decor bookshelf, reading chair, wall mirror, fireplace, altar; props suit
  of armour, grand piano, stained glass, brass lectern, votive stand), exactly as it does on H1's commit; the crypt's pieces
  pass.
