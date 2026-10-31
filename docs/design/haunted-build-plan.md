# Haunted contracts: build plan

Status: **[proposal; H1 built 2026-10-31, see "H1 as built"]**. The design is `new-themes.md` ("Ghost house: haunted contracts"); this is the order to
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
