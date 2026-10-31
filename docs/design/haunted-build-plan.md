# Haunted contracts: build plan

Status: **[proposal; H1, H2, H3, H3b, H4, H5, H6 and H7 built 2026-10-31, see "H1 as built", "H2 as built", "H3 as built", "H3b
as built", "H4 as built", "H5 as built", "H6 as built" and "H7 as built"]**. The design is `new-themes.md` ("Ghost house: haunted contracts"); this is the order to
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
  bodies from the keyframe. (Built: see "H3 as built"; the downed state is `Actor.dead`, the late joiner's bodies ride rows of
  their own beside the keyframe.)

### H3b. Crypt rats and the ecto blob [decided 2026-10-31, built: see "H3b as built"]
The user (2026-10-31, "Yes"): the two crypt pests of the look test (`docs/design/crypt-pests-look.md` on the branch
`worktree-agent-ac83d600a5bfe9b8a`, "The user's read") become real monsters of the dead family, built after H3:
- **Crypt rats**, the **"Sewer brute"** variant (the realistic rat scaled up; dark bead eyes for now): a **fast swarm** in
  packs of **5-6**, like the imps' clump in a pack roll.
- **The ecto blob**, the **"Mass of faces"** variant (its faces need to read bigger or brighter at the game camera): **slow area
  denial**, leaving an **ectoplasm slick** behind it that **Damp washes away** (the goo patch's shape: a runtime object the host
  announces, washed by a soak).
- Both are `MonsterDefs` rows with `"family": "dead"` (dealt only by the dead family's packs, as the zombie is), so hellgate floors
  stay byte for byte. Their tuning, pack weights, drops, the slick's effect and the player-facing names are proposals to make
  when it is built.

### H4. Acolytes and the procession
- An `acolyte` monster kind on floors 1-2: it flees heroes, travels the floor in a **procession** (a leader, its zombies
  and a rear acolyte, as in the look test) between rooms, and raises the bodies it passes. Paid per kill; the objective on
  floors 1-2 is the acolytes. **To revisit here:** the procession in the game (the user: "We will try it in the game when
  it is ready").
- Networking: host monsters; the procession is a host-owned group (its route is PRIVATE to the host, its members
  replicate as usual). A raise is a world event like a monster wind-up. (Built: see "H4 as built".)

### H5. Ghosts and possession
- **Hosts:** a suit of armour and a skeleton spawn dormant as host monsters, priced like props. Breaking a possessed
  antique bills the crew; bones do not. **Wisps:** a ghost keeps away from heroes unless it holds a host; breaking the
  host hurts it and sends it to the next host. Tentacles pass through ghosts. The soft outline is cosmetic per machine (the
  look the user picks from `ghost-look.md`). **To revisit here:** the possessed knight, animated.
- Networking: a dormant, priced host monster with a possessed state is a new shape ("a prop turning into a monster fits
  no shape yet"): designed and written up before it is built. Designed: "H5 networking" below.

#### H5 networking (the design, written before the code, 2026-10-31)
Checked against the code, possession needs **no new shape**: nothing turns from a prop into a monster.
- **A host is an owned actor from spawn**: a host monster (`HauntHost`, the kinds `armour` and `bones`), seed-built like the
  procession's members (planned on its own dice by `HauntPlanner`, `SitePlan.haunts`, spawned after the processions so no
  earlier net id moves). Its team is the monsters' (SPAWN, as every monster's). DORMANT it has no AI, is out of the
  "monsters" group (no pest count, the staff are not scared of it, no shout or noise wakes it, a chicken leaves it) and the
  AI allies leave it alone (`Monster.is_dormant`), but the crew can still hit it: it is the client's property.
- **A ghost is an owned actor too**: a host monster (`Wisp`, kind `wisp`), seed-built inside its first host. Who possesses
  what is one OWNER link on each side, `Wisp.host` and `HauntHost.ghost`, written on the host's machine only (the wisp's
  possess and eject; the host's own `take_ghost`), carried by ONE reliable world event, `world.haunt {id: the wisp, h: its
  host or 0, x, y, z}`, queued with the deaths so a client applies it on the host's beat and in order with the host's break
  (`world.die`). Inside a host the wisp is hidden on every machine and out of "actors" and "monsters" (no query finds it:
  nothing hits it), and the host's machine keeps it on its host (its stream entry moves with the host, so it pops out where
  the host broke).
- **The break**: on the host's machine a possessed host's death (`world.die`) ejects its wisp (`world.haunt` h 0) and hurts it
  through the verb (`apply_damage`, the culprit as the source; the wisp's owner is the same machine). The wisp's flight to
  the next dormant host, its keep-away and its pick are the host's AI (PRIVATE). A possession is `world.haunt` again.
- **Billing** is the shark's and the gator's (billed monsters): the owner bills on death, `Ledger.damage(name, price,
  culprit)`, and every client's Ledger mirrors it. The armour's row is `MonsterDefs` "billed" at the priced suit's price; the
  bones have none.
- **The priced suit of armour (H1) stays a PricedProp**: a plain antique, a host-arbitrated object, never possessed. The armour
  hosts are separate actors that look exactly like it while dormant (the same model, material and price tag), so a haunted
  antique sits among the real ones unnoticed until it moves. Converting the planned priced suits instead was rejected: it
  would move PropPlanner's spawns into another shape and change H1's plan.
- **Cosmetic, per machine (LOCAL)**: the possessed look (the rim, the ghost's vapour body and seep, the wisp's light), the
  wake, the left-behind plinth and the rubble, from the possession state every machine has.
- **Tentacles pass through a wisp**: physical only (`Tentacles.covers` is false for one); they shove and smash the hosts.
- **A late joiner**: the keyframe (every living host and wisp: where, HP, state), the gone ids (a broken host and a dead
  wisp are freed), and `haunts` rows `[wisp id, host id or 0]` (`NetWorld.haunt_states`): each wisp put in its host or out.
- **The checksum**: `SitePlan.haunts` in the plan part (left out at `[]`, `NetFloor.PLAN_DEFAULTS`), the hosts and wisps in
  the spawn part; bunker and lair floors plan none, so they hash as before.

### H6. The grimoire and the haunted invoice
- The last floor's source: a `Grimoire` actor in the hellgate's shape (tuning by difficulty and depth, phases, bursts of
  the dead, `closed`), slammed shut or burned. The `grimoire_model.gd` look (the altar, the live eye) becomes its model.
  Objective kinds and Ledger lines for acolytes and the grimoire; the invoice reads like a hellgate contract's.
- Networking: the hellgate's (a state codec, world events, a REPLICATED row and a LATE_JOIN entry). (Built: see "H6 as built";
  the grimoire is a `Hellgate` subclass, so the codec and events are the gate's own.)

### H7. Ghost form
- The Ghost spell cast on yourself: a whole-body transform; you pass through regular enemies but still get hit by their
  attacks; it is for fighting ghosts. Open: whether a ghost-form hero can hit regular enemies, its duration and cooldown.
- Networking: a status on the hero (its owner resolves and announces it); the pass-through flag already replicates. (Built: see
  "H7 as built"; the status is a modifier of its own, `Actor.STAT_GHOST`, not the pass-through flag.)

### Later
- Ectoplasm as the infestation layer (slicks the floor, Damp washes it away). The crypt rats and the ecto blob are step H3b now.
- Evicting a ghost without breaking its host (wanted, deferred). Ghost mode after a hero dies (a big build, later; H7's ghost form
  and its look are what it would start from).

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
4. **Pay without gates:** (retired in H6: the grimoire pays the source's line, the pest the standard rate) the pest objective adds `DEAD_PEST_BONUS` ($10,000, before the client's scale), so a haunted
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

## H3 as built (2026-10-31)

The user (2026-10-31), as for H1 and H2: "Just build it now. We can revisit the decisions after it's built." Every open call
below was made on the spot, the simplest sound choice, and is listed to revisit. (First, in its own commit: H1's ten
`test_zfight` failures are fixed by nudging the coplanar faces apart, as H2 did for the crypt kit: the bookshelf's plinth, the
wingback's back, the wall mirror's backing, glass and frame corners, the fireplace's lintel, the altar's frontal bands and
crosses, the suit of armour's brass rim, the piano's band, the stained glass panes and head, the lectern's lip and the votive
stand's tiers. `test_zfight` passes.)

### Play it

```
.\run.ps1 --client heir --seed 3 --floor 1 --spells coffee,fireball --no-mic                 # a haunted mansion whose pest is zombies
.\run.ps1 --client heir --seed 3 --floor 1 --spells coffee,fireball --no-mic --spawn-near zombie,5,cluster --slay-near --focus dev
         # five bodies by the van (1.5 s in); add --autocast fireball --autocast-after 2.2 to burn them, or --autocast coffee to raise them
.\run.ps1 --gym --no-mic                                                                      # Spawn > Monster > "Zombie" and "Zombie (body)"
```

Screenshots (the game camera at zoom 12, 1920x1080, heir 3 floor 1): `docs/design/zombie_bodies/standing.png` (four zombies, the
grey-green digger and three mourners, shambling at the crew), `bodies.png` (five bodies lying where they fell, away from the wall,
greyed, the motes rising off them), `burnt.png` (a fireball over the middle three: charred and smoking; the two at the ends still
grey), `rising.png` (a coffee spilt on them: three push up on their arms together; the two outside the splash stay down).

### What was built

| Piece | Where | What |
|---|---|---|
| The kind | `scripts/monsters/zombie.gd` (`Zombie`), `MonsterDefs` "zombie" | A `Monster`: HP 70 (a skeleton 40), speed 1.5 (3.2), a 0.7 s wind-up (0.35) into Monster's melee cone (12 damage, reach 1.35, 110 degrees), 1.8 s cooldown, aggro 7. The row: pack cost 3, weight 5, drops fireball 10 % / heal 8 %, pest "zombies", and the new field `"family": "dead"` |
| Its look | `ZombieModel` (the look test's, now the game's) | The mourner, or the digger for one zombie in three: `Zombie.variant_for(spawn cell)`, a hash, SPAWN, the same on every machine. `ZombieModel.MODEL_SCALE` / `DIGGER_SCALE` |
| The dead family | `ClientArchetype.FAMILY_KINDS["dead"]` = grunt, zombie; heir and parish `"pests"` = grunt, zombie | A dead contract's packs deal skeletons and zombies; its pest is rolled between them per contract. `MonsterFactory.compose` deals a `family` kind only when the pack asks for its family (`only`), so every hellgate floor rolls exactly as before (`test_golden_floor` unchanged, `test_monster_defs`) |
| The body | `Zombie._on_death`, `Actor.is_downed`, `GameWorld.downed_in_radius` | Down, a zombie is `dead` (as a downed hero is) but stays: no topple, fade or free. It lies face down (`ZombieModel.pose_rise(0)`: greyed, eyes out, the motes) where it fell, away from a wall within `LIE_LEN` (it falls back or sideways instead). It leaves `monsters` (the pest count drops). `downed_in_radius` now finds every `Actor.is_downed` (dead and `_can_revive`): downed heroes and unburnt bodies. It never gets up by itself. A zombie that dies with no floor under it (a pit, lava) leaves no body: freed like any monster |
| The raise | `Actor.revive` (the verb), `Zombie._on_revived`, `Zombie.raise` | Coffee's splash (`Combat.revive_radius`, any team) stands a body up at `CoffeeSpell.ZOMBIE_HP` (10), not hasted. It pushes up on its arms over `RISE_TIME` (1.4 s, helpless: a stagger), facing the way it lay, then is an IDLE monster where it rose. `raise()` is H4's hook (full HP). Heal and Revive stay allies-only (their team filter) |
| The burn | `Actor.burn_body` (a NEW verb), `Zombie._burn_down`, `Burning.on_blast` / `ignite` | A fireball blast burns every body it covers, no roll (`on_blast` asks `Net.resolves` per body); a fire lit on a body (`Burning.ignite`) burns it; a zombie that goes down burning is burnt. Burnt: the charred `ZombieModel` replaces the body's (smoke, embers), `_can_revive` false (out of the downed query: never rises). The verb is in AGENTS.md rule 2 and `test_net_contract`'s area-verb lint |
| Drops | `Zombie._on_death` | Rolled the first time it goes down only (`_dropped`): coffee and a cleaver cannot farm components |
| Networking | `NetWorld`, `NetJoin`, `Net.remote_revive`, `NetEvents`, `test_net_contract` | See the checklist below |
| Gym | `GymSpawns` | "Zombie" (the factory kind, as every kind gets) and "Zombie (body)" (`monster:zombie:body`: one that goes down as it lands), in the existing Monster group; no keybinding. `GameDev._dev_centroid` counts the `--spawn-near` bodies, so `--autocast` and `--focus dev` find them after `--slay-near` |

### The networking checklist (networking.md)
1. **Shape: an owned actor**, a host monster (the host owns and simulates it; a client shows a puppet). Not a new shape.
2. **Vars:** `variant` SPAWN; `burnt` OWNER (carrier `world.burn`); `raises` and `_rise_t` LOCAL (the stand-up's look on every
   machine); `_dropped` PRIVATE. `dead` is Actor's OWNER var; its zombie carrier is `world.die` plus `world.rise`
   (`NetEvents.WORLD_CARRIES["zombie.gd"]`). No separate `downed` var: the downed state is `dead` on a body that `_can_revive`.
3. **Verbs:** `revive` (the raise) and the new `burn_body`, each applied by the body's owner (`Net.resolves`); its strike is
   Monster's `Combat.melee_arc`.
4. **Randomness:** its drops on the host's `GameWorld.rng` (as every monster); its look is a hash; nothing new is rolled.
5. **Motion:** standing, a monster entry in the stream as ever; a body does not move; the stand-up's pose is LOCAL from the event.
6. **Cosmetic:** the lying pose and which way it lies, the motes and smoke, the charred model, the stand-up. **Gameplay:**
   `dead`, `burnt`, `hp`.
7. **A late joiner:** a standing zombie is in the keyframe (a runtime one: the `world.spawn` replay); a body's seed-built id is a
   gone id shown dead (`NetJoin.gone_ids`: "die" for a body, "free" for other monsters), then the snapshot's `bodies` rows
   (`NetWorld.body_states` / `apply_bodies`: id, kind, where it lies, which way, burnt) lay it where the host has it; a runtime
   body the joiner never built is built from its row. A stand-up under way is skipped (under 1.5 s). `NetEvents.LATE_JOIN`.
8. **The scenario:** `tests/test_net_zombies.gd` (below).
- The events: `world.die` as before; `world.rise {id, hp, x, y, z}` (the host streams the zombie again: a fresh track, its signals
  still linked) and `world.burn {id}`. A client queues both with the deaths, on the host's beat, one actor's in the order they
  came (`NetWorld._apply_deaths`), and applies them inside the net layer's scope (`Net.remote_revive`, `Zombie.net_burn`).

### The calls made (to revisit)
1. **The downed state is `Actor.dead`**, as a downed hero's is, not a separate `downed` var: every query and verb that skips the
   dead skips a body (no target, no hit, no blocking, no AI ally aims at it), and only the downed query finds it.
2. **The late joiner's bodies ride rows of their own** (`bodies`) beside the keyframe, not in it: the keyframe holds the living
   movers, and the monster entry's flag bits are all used (its state needs all 3; `burnt` would need a fourth).
3. **The pest:** a haunted contract names skeletons or zombies, rolled per contract (heir and parish `"pests"`). On a skeleton
   contract the zombies are in the way but not the objective, and the other way round.
4. **The count when a body rises:** a body is not alive, so a downed zombie counts as exterminated; raised, it is alive again and
   counts as left again ("N left" on the tracker goes back up). Once a floor's pest pay is in, it stays paid
   (`ContractSession.check_clean` pays once): raising zombies after that costs a fight, not money.
5. **Stats:** HP 70, speed 1.5, damage 12, wind-up 0.7, cooldown 1.8, aggro 7 (above). Slow and tough; the crew outwalks it.
6. **The mix:** a zombie costs 3 to a skeleton's 2, at the same weight, so a dead floor holds fewer monsters than H1's
   skeleton-only one (measured on heir and parish 3 and 11: 12-17 on floors 1-2 and 26-35 on floor 3, against 17-21 and 34-42
   with skeletons only).
7. **Both looks, one kind:** the mourner, and the digger for one zombie in three, with the same stats (the digger is a look).
8. **A raised zombie stands at the HP its raiser gives:** coffee's `ZOMBIE_HP` (10, the coffee zombie's), not hasted; an
   acolyte's `raise()` (H4) full health. It gets up over 1.4 s, helpless, where it lay, and is then an ordinary IDLE monster
   there (it finds the crew by its senses, as any monster).
9. **Burning:** every body a fireball's blast covers burns, with no roll (a living actor rolls to ignite); a fire lit on a body
   burns it; a zombie that goes down burning is burnt. Other fires (the goo's, lava's) do not seek bodies out.
10. **The drops roll once** (the first time down).
11. **No body despawns** on its own: a floor's bodies stay until it ends (a body is one static model; watch the frame rate on a
    long fight).
12. **A pit or lava leaves no body** (the zombie is freed as any monster).
13. **A body falls away from a wall** within 1.3 (the look; it rises facing the way it lies).
14. **Heal and Revive stay allies-only** (the decision to revisit before the milestone ends: whether Heal raises zombies).
15. **Its cry** is the shared monster cry (`cry_monster`); no zombie voice yet.
16. **The late-join test runs three processes, not two:** a late joiner needs a crew already on the floor (a host alone on a job
    admits nobody, `NetJoin`), so c1 watches live and c2 joins.

### New player-facing strings (proposals for review)
- Monster name **Zombie** (the combat log's "Zombie died"); pest name **zombies**: the objective **Exterminate zombies**, the
  Ledger's **Pest cleared (zombies)**, the dispatch banners' `{pest}` ("The zombies on this floor are still getting up. Put them
  down and keep going.", H1's lines).
- The floor-1 pest ticket (`NoteCopy.PEST_TICKETS["zombie"]`): **"Slow ones in burial clothes. Knocked down, they lie there until
  something gets them up. Technician's advice: burn them where they lie."**
- Dev only: the gym's **Zombie (body)** button.

### Tests
- `tests/test_zombie.gd` (new, solo): the kind, its look from its cell (both looks turn up), slower and tougher than a skeleton;
  killed it stays a body (lying, the motes, not an actor or a monster, in the downed query but not an ally's) and never gets up by
  itself; Heal and Revive leave it; Coffee raises it at `ZOMBIE_HP`, not hasted, helpless while it rises, then standing; down
  again; a fireball's blast burns the body (charred, out of the downed query) and coffee or `revive` no longer raise it; a zombie
  that goes down burning is burnt and a fire lit on a body burns it; a copy ignores `revive` and `burn_body`; skeletons, archers
  and brutes still free; the gym's body button.
- `tests/test_net_zombies.gd` (new, NetTest, `const PEERS := 3`, `off` and `coast`): board 9's heir contract (pest zombies); the host
  kills three zombies and c1 shows three bodies where they lie; the host's fireball burns one and c1 shows it charred; c1's coffee
  raises another ON THE HOST (its owner) and c1 shows it standing again, streamed; the coffee does not raise the burnt one; c2 joins
  late and shows the standing one where the host has it and the two bodies where they lie, one burnt; then the host downs the
  standing one again and burns the last, and both clients show it; no OWNER-write guard on any machine.
- Updated: `test_monster_defs` (the zombie row in every table; a family kind is never in a hellgate pack, dead packs deal both),
  `test_monster_models` (its parts), `test_monster_integration` (its scale; it stays a body), `test_monster_death` (every kind
  frees but the zombie), `test_haunted_contract` (the dead family is skeletons and zombies; the pest one of them; a sane total),
  `test_crypt_gen` (the crypt's packs are the family's), `test_net_contract` (`zombie.gd` in REPLICATED; `burn_body` in the
  area-verb lint).

## H3b as built (2026-10-31)

The user (2026-10-31): the rat is the **"Sewer brute"** and the blob the **"Mass of faces"** (its faces "show only as dark specks
at the game camera", so they read bigger or brighter), "Yes" to both as real monsters of the dead family after H3, and as for
H1-H3: "Just build it now. We can revisit the decisions after it's built." Every open call below was made on the spot, the
simplest sound choice, and is listed to revisit. (First, the look test's branch was merged in: `crypt-pests-look.md`, the rat
and blob models, `CryptPest`, the lab, `EctoplasmLook.trail` and `test_crypt_pests`; git merged it with no conflict.)

### Play it

```
.\run.ps1 --client parish --seed 2 --floor 1 --spells damp,fireball --no-mic --spawn-near crypt_rat,6,cluster --idle-monsters --monster-demo wake
         # six crypt rats by the van wake on the player 1 s in (the allies hold): the stream, the pounce, the bite
.\run.ps1 --client parish --seed 2 --floor 2 --spells damp,fireball --no-mic --spawn-near ecto_blob,1 --idle-monsters --monster-demo wake --focus dev
         # an ecto blob crawls at the crew from beside the elevator, its slick behind it; cast damp on the slick
.\run.ps1 --client heir --seed 1 --floor 2 --spells damp,fireball --no-mic --to-crypt lit    # a crypt (the rats are favoured there)
.\run.ps1 --gym --no-mic                                                                       # Spawn > Monster > "Crypt Rat", "Ecto Blob"
```

`--monster-demo wake` is new (dev only, no keybinding): every `--spawn-near` monster wakes on the player while the AI allies hold.

Screenshots (the game camera, size 24, 1920x1080), `docs/design/crypt_pests_game/`: `rat_pack.png` (parish 2 floor 1: six rats
stream in along the wall at Rebar, one tinted in its pounce), `rat_pack_pounce_2x.png` (a 2x crop: two rats in the pounce, flat,
tails up, the wind-up tint on), `blob_slick.png` (parish 2 floor 2: the blob crawling at the crew by the elevator, five metres of
slick behind it narrowing to its old end), `blob_slick_3x.png` (a 3x crop: the faces' glowing eyes and dark mouths, the film's
bright edges), `blob_slick_mansion.png` (heir 11 floor 2: the same on the mansion's parquet).

### What was built

| Piece | Where | What |
|---|---|---|
| The crypt rat | `scripts/monsters/crypt_rat.gd` (`CryptRat`, extends the swarmer), `MonsterDefs` "crypt_rat" | The swarmer imp's AI (close in, dart in for a bite off cooldown, circle while it recharges; idle, a clump plays round its centre), a little slower and tougher: HP 14 (imp 12), speed 5.0 (5.5), bite 5 (4), wind-up 0.5 s (0.3), cooldown 0.9, aggro 9, reach 0.8, arc 140, radius 0.3. Dies and is freed like any monster (no body). The row: `"family": "dead"`, a swarm pick (`"swarm": true`) of **5-6** (`"swarm_min"` / `"swarm_max"`, new row fields, `MonsterFactory.swarm_range`: the imps' 4-6 draw is unchanged), cost 6, weight 1, drops teeth 3 % / chicken 3 % per rat. No `"pest"`: never a contract's pest |
| Its look | `RatModel` "sewer" (the user's pick), `RatModel.tell` "pounce" | The bite's tell is a **pounce**: it flattens and draws back, hind legs bunched, the head low and the jaw open, the tail up off the floor and lashing side to side; the bite snaps a long way forward. With the monsters' wind-up tint (orange-red, pulsing) and a small swell (0.12). The look test's rear-up stays the model's default (`tell` "rear") for `CryptPest` and the lab. Its dark bead eyes keep a glowing glint (`MonsterModel.glow`, the monsters' "enemies glow" rule: the beads glow nowhere else). `monster_kind` "crypt_rat" |
| The ecto blob | `scripts/monsters/ecto_blob.gd` (`EctoBlob`), `MonsterDefs` "ecto_blob" | Slow area denial: HP 10 (under the weakest hero hit, 12: **any hit kills it**, no spell needed), speed 0.85, a lunge of 8 after a 0.9 s gather-up tell (`EctoBlobModel`'s windup: tall, leaning back, flaring), cooldown 2.4, aggro 7, reach 1.25, arc 100, radius 0.55. Idle with the crew within `LIFE_RANGE`, it **wanders its room** (a cell within 3 of home at 0.7 pace, resting 2.5-5 s), so its room fills with slick before anyone arrives. Freed when it dies; its slick stays. The row: `"family": "dead"`, cost 3, weight 1.5, **one a pack** (`"max": 1`), drops damp 20 % / heal 6 % |
| Its look | `EctoBlobModel` "faces" (the user's pick; now the default variant) | The faces are `FACE_K` (1.75) times the look test's, and each hollow eye holds a glowing point in the ghost colour (`face_eyes`, a part under the body, `FACE_GLOW` 1.0: brighter would clamp the pale blue's hue). At the game camera a face reads as a pair of bright dots over a dark mouth |
| The slick | `scripts/monsters/ecto_slick.gd` (`EctoSlick`) | The blob's owner lays a **segment** every `SLICK_STEP` (0.6) it crawls, from the last segment's end to where it is (`EctoBlob._trail` -> `EctoSlick.lay`): WIDTH 1.0, LIFE 14 s. A shove, fall or climb farther than a crawl (1.8, or 0.45 up or down) breaks the run instead of bridging it. **Slows** the living whose feet are on it (heroes and the staff, never a monster: the dead's own ooze) to x0.6 (`Actor.effective_speed` x `EctoSlick.speed_mult`, the goo patch's LOCAL rule). **Damp** washes every segment its drizzle reaches (`Damp._burst` -> `EctoSlick.wash_at`, the owner's decision); the rest of the ribbon stays. Fire does nothing to it |
| Its look | `EctoSlick._flush` / `_draw_run`, `EctoplasmLook.trail("film")` | Every screen draws a blob's live segments as **ribbons of the film** (the user's ectoplasm): each run of consecutive segments (one `chain`, `seq` without a gap) is one ribbon through their points, narrowing to a point at its old end, under its oldest segment; a segment laid, washed or dried redraws its chain once that frame. A washed segment's own piece fades out with `EctoplasmLook.set_wash`, with the goo's wash fizz and sound (`goo_wash`) |
| Where they come from | `ClientArchetype.FAMILY_KINDS["dead"]` = grunt, zombie, crypt_rat, ecto_blob; `PackPlanner.CRYPT_BIAS` | A dead contract's packs deal all four; a crypt room's packs weigh the rats x2 (`SiteBuilder.biased_composition`'s new `more`). The pest stays a skeleton or a zombie (heir and parish `"pests"` unchanged). Hellgate packs never deal a family kind, so every bunker and lair floor rolls as before (`test_golden_floor` passes against the recorded floors, not re-recorded) |
| Dev | `GameDev._monster_demo` "wake" | `--monster-demo wake`: every `--spawn-near` monster wakes on the player, the allies hold (screenshots) |
| Gym | `GymSpawns` (unchanged) | "Crypt Rat" and "Ecto Blob" in the Monster group, as every factory kind gets; the look test's 18 crypt buttons stay |

The totals (`test_haunted_contract`, heir and parish 3 and 11, floors 1-3): **12-22 monsters on floors 1-2 and 30-40 on floor 3**
(H3: 12-17 and 26-35). A rat pick is 5-6 small bodies (14 HP each, about 80 HP a clump) for 6 points, the brute's cost, where
three skeletons (120 HP) cost the same; the rats came in at cost 4 and weight 2.5 first, the swarmer's numbers, and floors reached
56 (32 rats), so they were raised to 6 and 1. The 40 cap of H3's test holds.

### The networking checklist (networking.md)
1. **Shapes.** The rat and the blob: **owned actors**, host monsters (Monster's shape; no OWNER var of their own; their tells are
   `world.windup`; a puppet's strike is resolved by each client on its own hero, as every monster's). The slick: a
   **host-arbitrated world object made during play** (`NetObjects.RUNTIME_OBJECTS` "ecto_slick", the goo patch's shape). Not a new
   shape.
2. **Vars.** `CryptRat`: none of its own (the swarmer's). `EctoBlob`: `slick_laid`, `_slick_from`, `_slick_seq`, `_slick_chain`,
   `_wander_goal`, `_wander_t` PRIVATE (the host's AI and bookkeeping). `EctoSlick`: `a`, `b`, `width`, `start_time`, `look_seed`,
   `chain`, `seq` SPAWN (the `obj.new` row); `washed` OWNER (carrier `obj.slick {id, st}`, `NetEvents.WORLD_CARRIES`); `_end`,
   `_gone_at`, `_wash_look` LOCAL. In `test_net_contract`'s `NET_SCRIPTS` and `REPLICATED`.
3. **Verbs.** The rat's bite and the blob's lunge are Monster's `Combat.melee_arc`. The slick applies no verb: its slow is LOCAL
   (every screen derives it from the segments it has; each hero's own machine moves it). Washing is the owner's decision
   (`wash_at` acts only on segments `Net.owns`; Damp's burst runs on every machine).
4. **Randomness.** The blob's wander on the host's `GameWorld.rng` (AI, as every monster's idle life); the segments' look seed is a
   hash of (chain, seq); the ribbons are drawn from it. Nothing else is rolled.
5. **Motion.** The monsters stream as ever. A segment never moves.
6. **Cosmetic:** the ribbons, the wash's fade and fizz, the pounce and the tail lash, the faces' glow. **Gameplay:** the segments
   (where, when, washed), the monsters' HP and state.
7. **A late joiner.** The monsters: the keyframe and gone ids (a dead rat or blob is freed). The slick: every live segment (not
   washed, not dried) as an `obj.new` row (`EctoSlick.late_join_state`, section `new`), built as a client builds it, drying at the
   host's moment. `NetEvents.LATE_JOIN` has `crypt_rat.gd`, `ecto_blob.gd` and `ecto_slick.gd`.
8. **The scenario:** `tests/test_net_ecto_slick.gd` (below).
- Who disagrees, and how much: nobody decides a slow, so nothing is disagreed over; a client sees a segment about half a round
  trip after the host laid it (the blob's puppet is as late). A client's Damp is a cast every machine runs; the host's run of it
  washes, and the client's copies go when `obj.slick` arrives.

### The calls made (to revisit)
1. **The rat is the swarmer's AI** (`CryptRat` extends `swarmer.gd`): darts, circles, clump play. A little slower and tougher, a
   longer tell (0.5 s against 0.3), a bite of 5.
2. **The tell is a pounce**, not the look test's rear-up (from the game camera a rearing rat gets shorter): flat, drawn back, the
   tail up and lashing, with the wind-up tint and the imp's swell. The rear-up stays in the look test.
3. **Packs of 5-6 a pick, at most one rat clump a pack** (a swarm kind), **cost 6, weight 1**, x2 in a crypt's rooms. Rats are
   never a contract pest (no pest name, no objective, no pest ticket).
4. **No rat voice or squeak:** the bite plays the light swing (`swing_light`, as the imp's); its war cry is the shared monster cry.
5. **The bead eyes glint** (a glowing white point; the user kept the dark beads "for now").
6. **The blob: one a pack** (`"max": 1`), cost 3, weight 1.5. HP 10, under every hero's plain hit (Wick's 12).
7. **The blob wanders its room when the crew is near** (its idle life), laying slick; it fights by crawling at the crew and
   lunging (Monster's chase). It does not seek to cut the crew off.
8. **The slick slows heroes and the staff to x0.6**, never a monster; no damage, no slip. LIFE 14 s, WIDTH 1.0, a segment every 0.6.
9. **Fire does nothing to the slick** (ectoplasm does not burn); only Damp washes it, per segment.
10. **A shove or fall breaks the ribbon** (no slick bridging a gap the blob did not crawl).
11. **The slick is segments, not one growing object**: each segment is one `obj.new` (about one a second a crawling blob); the
    look joins them into ribbons per chain on every screen.
12. **The faces: 1.75x the look test's, with glowing eyes** in the ghost colour; the jelly and the slick stay the look test's.
13. **Drops:** a rat: teeth 3 %, chicken 3 % (about the imp's); a blob: damp 20 % (its counter), heal 6 %.
14. **The wash's fizz and sound are the goo's** (`goo_wash`): no new sound.
15. **`--monster-demo wake`** is the dev way to stage either (no keybinding).

### New player-facing strings (proposals for review)
- Monster names **Crypt rat** and **Ecto blob** (the combat log: "Crypt rat died", "Ecto blob died").
- No pest names, objectives, Ledger lines, notes, tickets or dispatch lines (neither is a contract pest).
- Dev only: the gym's **Crypt Rat** and **Ecto Blob** buttons (the factory kinds' capitalized names).

### Tests
- `tests/test_crypt_rat.gd` (new, solo): the kind (a CryptRat in the sewer brute with the pounce tell, a dead family swarm kind,
  faster than a skeleton or a zombie, less HP than a skeleton); in a fight it winds up and the hero is untouched through the
  whole tell (the model in its tell, the tint on), then the bite lands for 5; the pounce pose (flat, crouched, drawn back, the
  jaw open, the tail up; the bite a long snap forward); a pick placed by `PackPlanner` is a clump of 5-6 (both sizes happen);
  killed, it is freed (no body).
- `tests/test_ecto_blob.gd` (new, solo): the kind (the mass of faces with its faces' eyes, slower than a zombie, a long tell); its
  HP is under the weakest hero hit and one plain melee hit kills it (then freed); crawling after a hero it lays segments about
  SLICK_STEP long, numbered without a gap, the newest under it, drawn as one film ribbon the length of the path; the slick
  slows a hero and the staff x0.6 and never a monster; the real Damp washes the segments its drizzle reaches, both ends stay and
  the ribbon splits in two; a segment dries after LIFE; a copy is never washed by its own machine and goes on the owner's
  `obj.slick`; idle with a hero near it wanders off its spot laying slick, and killed its slick stays.
- `tests/test_net_ecto_slick.gd` (new, NetTest, `const PEERS := 3`, `off` and `coast`): board 9's heir contract, floor 1. The host
  lays chain A (eight segments) and a segment B under c1's hero; c1 has every one (same ids, ends, drying moment), draws A as one
  ribbon, and its own hero walks at x0.6 on B; c1's Damp at A washes A on the host (eight `obj.slick`) and on c1, B stays on
  both; the host lays chain C as c2 clocks in, and c2 arrives with exactly the host's live segments, the same ends and drying
  moments, none of A's; no OWNER-write guard on any machine.
- Updated: `test_monster_defs` (the two rows in every table, the dead family's four kinds, the 5-6 swarm range, neither a pest,
  no hellgate pack deals any family kind, dead packs deal rats and blobs, at most one rat clump and one blob a pack),
  `test_monster_models` (their parts: `RatModel.PART_NAMES`, `EctoBlobModel.GAME_PARTS`), `test_monster_integration` (their
  model scales), `test_haunted_contract` (the family's four kinds, rats and blobs turn up over the floors, rat clumps of at most 6,
  the sane total), `test_crypt_gen` (a crypt's packs are the family's; crypt rats turn up in the crypts), `test_crypt_pests` (the
  mass of faces' glowing eyes), `test_ectoplasm_look` (header), `test_net_contract` (`ecto_slick.gd` in `NET_SCRIPTS`; the three
  scripts in `REPLICATED`).
- Run and passing: `test_net_contract`, `test_golden_floor`, `test_haunted_contract`, `test_crypt_gen`, `test_monster_defs`,
  `test_monster_factory`, `test_monster_death`, `test_monster_models`, `test_monster_integration`, `test_spell_damp`, `test_zombie`,
  `test_crypt_pests`, `test_ectoplasm_look`, `test_net_world_codec`, `test_net_m3_world`, `test_net_m3_objects`,
  `test_net_m6_late_join`, `test_net_zombies`, `test_gym`, `test_zfight`, `test_shader_hash`, `test_crypt_rat`, `test_ecto_blob`,
  `test_net_ecto_slick` (off and coast). The full suite was not run.

### Not done in H3b
- No crew (two-PC) play; the net test covers the slick, and the monsters are the swarmer's and Monster's shapes.
- No rat or blob sounds of their own (a squeak, a squelch); the wash borrows the goo's.
- The slick's ribbon is redrawn whole on every change (about once a second a crawling blob, plus each drying segment): cheap at
  one or two blobs a floor; watch it if a floor ever holds many.
- The tell and the faces were judged on stills at the game camera only (`crypt_pests_game/`), not in play.

## H4 as built (2026-10-31)

The user (2026-10-31), as for H1-H3b: "Just build it now. We can revisit the decisions after it's built." Every open call below
was made on the spot, the simplest sound choice, and is listed to revisit. **To revisit (the user): "We will try it in the game
when it is ready."** See "Play it".

### Play it

```
.\run.ps1 --client heir --seed 3 --floor 1 --spells coffee,fireball --no-mic --to-procession --focus procession
         # the crew a few cells ahead of floor 1's procession, the camera on its leader; it walks into the crew and the fight is on
.\run.ps1 --client heir --seed 3 --floor 1 --spells coffee,fireball --no-mic --to-procession --procession-demo walk --focus procession
         # every monster's senses off: the procession walks its route past the crew (the allies hold)
.\run.ps1 --client heir --seed 11 --floor 1 --spells coffee,fireball --no-mic --no-fog --to-procession --procession-demo raise --demo-after 4 --focus procession
         # as walk, then the file's last two zombies drop: the rear acolyte raises them (arms up, they push up) and they rejoin
.\run.ps1 --client heir --seed 3 --floor 2 --spells coffee,fireball --no-mic --to-procession 1 --focus procession
         # floor 2: two processions on a job at difficulty 0.5 or more (1 picks the second; the last when there is one)
.\run.ps1 --gym --no-mic                                                                   # Spawn > Monster > "Acolyte" and "Procession"
```

- Every haunted contract has processions: floor 1 one, floor 2 one (two on a job at difficulty 0.5 or more), floor 3 none. The
  log names each one's rooms ("procession: Procession0, 2 acolytes, 4 zombies, round room:4, room:1, room:3").
- `--to-procession [n]` (solo) starts the crew 5-8 cells ahead of procession n's leader, on its way; `--focus procession` follows
  its leader (the rear acolyte with the raise demo); `--procession-demo walk|raise|fight` stages it (`--demo-after`, default 1 s; the
  AI allies hold; it prints the file every 1.5 s for 15 s: "[procession] ..."). `scripts/app/dev/procession_dev.gd`. No keybinding.
  Add `--no-fog` when the camera follows it out of what the crew has seen.
- Screenshots (the game camera at zoom 12, 1920x1080), `docs/design/procession_game/`: `walk.png` / `walk_crop.png` (heir 3 floor 1:
  the leader stepping out of the ballroom, four zombies in file behind it, the rear acolyte at the back), `raise.png` /
  `raise_crop.png` (heir 11 floor 1: the rear acolyte arms up, the hands and the staff lit, a zombie pushing up in front of it and
  the second body beside, the file standing round them), `raise_church.png` (parish 3 floor 1: the same in the nave, among the pews).

### What was built

| Piece | Where | What |
|---|---|---|
| The kind | `scripts/monsters/acolyte.gd` (`Acolyte`), `MonsterDefs` "acolyte" | A `Monster` with **no attack**: HP 30 (a skeleton 40), runs at 3.2 (the crew walks 4.5), sees a hero within 9 in line of sight or within 4 at all. The row: `"family": "dead"`, **no `pack`** (no pack deals it), no pest, drops fireball 25 % / heal 10 %. `is_priority_target()` (the AI allies rank it with the Water Boy). In `Monster.CRY_SKIP` (no war cry) |
| Its states | `Acolyte` | IDLE: marching in its procession (`Monster._march`), or standing without one. ALERT: **fleeing** to a spot 3-6 cells off, as far from the nearest hero as it can reach (picked again every 1.2 s), until no hero is within 12 for 3 s, then back to IDLE (its place in the file). ATTACK: **raising** (below). A hit, a pack-mate's call, a shout, a chicken or a noise within 8 sends it running; any other state goes back to rest |
| The raise | `Acolyte._find_body` / `_go_raise` / `_tick_attack` | Resting, it notices a zombie's body within 4 (in sight, not burnt: `Actor.is_downed`; no hero within 7 of the body; no other acolyte's claim), walks to 1.5 of it (the file stops) and **raises it in its wind-up**, `RAISE_T` 3.0 s (`Monster._begin_windup`: `world.windup` with the body as the "victim"). 0.9 s in the body is raised (`Zombie.raise`: `Actor.revive` at full HP, `world.rise`; it pushes up over `RISE_TIME` 1.4 s) and joins the back of the file (`Procession.join`); the arms come down over the last 0.6 s. A hero within 4, a shove or a stagger breaks it off (`world.unwind`); a body burnt or raised meanwhile is let go. The strike at the end is nothing (on a client too: `net_strike`) |
| Its look | `AcolyteModel` "cowl" (the game's now), `Acolyte._pose`, `Acolyte.arms_at` | The cowl with its lantern light (the look test's `LanternLight`, 5.0 over 5 units). The gesture is `set_raise(arms_at(telegraph * RAISE_T))` on every screen (the telegraph rides the stream); `arms_at` is the look test's curve, which `NecroProcession` now uses. The wind-up's orange tint is off (its hands glow instead); `AcolyteModel.windup` does nothing. Fleeing is the model's run (from its speed). A new `_slump` for its death (it is freed like any monster: a living cultist leaves no body) |
| The procession | `scripts/monsters/procession.gd` (`Procession`, a `Node` under the world) | The **leader** (the first living acolyte) walks to the route's next spot (`Monster.march_to`, 1.0) and leaves a **trail** (`ProcessionPath`); walker i of the file (the zombies, then the rear acolyte) walks to the trail's head arc minus `GAP` (1.8) x (i + 1), hurrying (x1.5) when more than 0.8 behind, and **never back along the trail** (a joiner's place behind it comes to it). The file **stands** while an acolyte is away or raising, or a zombie is not resting or more than 3 from its place; stragglers that are not fighting are left behind after 20 s (ordinary monsters); a fight holds it as long as it lasts. `engage`: an acolyte that sees the crew turns its resting zombies on them. The leader dead, the rear leads (back to the trail's head first); both dead, the zombies are ordinary monsters where they stand. A dead member leaves the file (`Monster.procession` null); an acolyte's raise puts a zombie back (coffee's does not) |
| `Monster` | `monster.gd` | `procession` (PRIVATE): a resting member asks it for its place (`_march` from `_tick_idle`, also while frozen: a frozen monster only has no senses) and does no look-arounds; `march_to(pos, delta, speed)` (home follows it, so it leashes to and walks back to where it marched) |
| The route | `scripts/contracts/planners/procession_planner.gd` (`ProcessionPlanner`), `SitePlan.processions` | Own dice (the floor seed), planned after the scouts: rooms but the start, arrival and exit rooms and a crypt's, each at its **spot** (the free full cell nearest its centre). The first procession starts in the room farthest from the crew's arrival, a second farthest from both; each walks to the nearest room it can reach not on its route yet, up to 3 (at least 2), and round. `{rooms, route}` records; `[]` elsewhere |
| The spawn | `ProcessionPlanner.spawn` / `build` | The **last actors** (after the landings' set pieces: no earlier net id moves): the Procession, then the leader the file's length along its first leg, four zombies `GAP` apart behind it and the rear acolyte, back to the first spot (a first leg shorter than the file starts on the leg before), so it walks on from the start. Zombies in `Site.monsters` (pest-counted), acolytes in `Site.acolytes`, processions in `Site.processions` |
| The objective | `ContractRun.floor_processions` / `acolyte_pay` / `ACOLYTE_PAY`, `ContractSession.acolyte_stopped`, game.gd | **Beside the pest**: an "acolyte" objective per acolyte (`ACOLYTE_PAY` $2,500 x the client's scale each; floors 1-2), in `objectives`, the contract value and the job card. The game pays on an acolyte's death where the books are kept (`_on_acolyte_stopped`; a client mirrors it), up to the floor's count (`acolytes_total` / `acolytes_stopped` in the floor's state). The tracker's "Stop acolytes  n / m" row and the elevator form's line |
| The fog | `GameWorld.downed_in_radius(..., hidden_too)` | An acolyte finds bodies out in the fog too (a monster the crew cannot see is hidden on the host's screen, and the downed query skipped hidden actors; found by the net test) |
| The checksum | `NetFloor.RUN_DEFAULTS` (`floor_processions` [0, 0, 0], `acolyte_pay` 0), `PLAN_DEFAULTS` (`processions` []) | The new fields are left out of the run and plan parts at the value every hellgate floor has (compared through `canon`): `test_golden_floor` passes against the recorded floors, not re-recorded. A haunted floor hashes them in |
| Look-dev | `NecroProcession`, `ProcessionPath` | The look test's procession now runs on `ProcessionPath` (its oval), takes `GAP` and its four zombies from `Procession` and the arm curve from `Acolyte.arms_at`; its own timing, loop and stand-in for the crew stay. Headers and `necro-look.md` say what is the game's |
| Gym | `GymSpawns` | "Acolyte" (the factory kind) and "Procession" (`monster:acolyte:procession`: a live one round where it is put, a loop through 4 spots 5 cells out, `ProcessionPlanner.build`), in the Monster group; no keybinding |

The totals (`test_haunted_contract`, heir and parish 3 and 11): **floors 1-2 hold 18-34 with the processions** (16-30 in `monsters`,
which now has the processions' zombies, plus 2 or 4 acolytes); floor 3 is as in H3b (30-40). The 40 cap holds.

### The networking checklist (networking.md)
1. **Shapes.** The acolyte: an **owned actor**, a host monster (Monster's shape; no OWNER var of its own). The procession: a
   **host-owned group of owned actors**, not a new shape: no replicated state of its own (every var SPAWN or PRIVATE), so it is in
   `test_net_contract`'s `NET_SCRIPTS` and not in `REPLICATED`. Every machine builds it from the seed and only the host walks it
   (`Procession.drive` is called from a member's own AI, which runs only where the member is simulated; its `_physics_process`
   only on the host).
2. **Vars.** `Acolyte`: `raised`, `_body`, `_did_raise`, `_flee_goal`, `_flee_pick_t`, `_calm_t`, `_from`, `_skip` PRIVATE; `_arms`
   LOCAL (the gesture, from `state` and `_telegraph`). `Monster.procession` PRIVATE. `Procession`: `rooms` SPAWN, the rest PRIVATE.
   `ContractRun.floor_processions` / `acolyte_pay` and `SitePlan.processions` SPAWN.
3. **Verbs.** The raise is `Actor.revive` (through `Zombie.raise`), applied by the body's owner (`Net.resolves`: the host). The acolyte
   applies nothing else; its body search loop calls no verb.
4. **Randomness.** The route on the planner's own generator from the floor seed; the flee spot and the march are deterministic host
   AI (no dice). Nothing else is rolled.
5. **Motion.** The members stream as any monster. The acolyte's state rides the stream's state bits (IDLE marching, ALERT fleeing,
   ATTACK raising) and the raise's progress the telegraph byte.
6. **Cosmetic:** the gesture, the lantern light, the run. **Gameplay:** who is where, the raise (the body's `dead`), HP.
7. **A late joiner.** The members: the keyframe and gone ids (a dead acolyte is freed); a raised zombie is standing (the keyframe);
   a raise under way shows from its state and telegraph (its `world.windup` is skipped). The procession needs nothing (the host's).
   `NetEvents.LATE_JOIN` has `acolyte.gd`.
8. **The scenario:** `tests/test_net_procession.gd` (below).
- The events: none new. `world.windup {v: the body}` and `world.unwind` for the raise (a client's strike at its end is nothing),
  `world.rise` for the body, `world.die` for a dead acolyte. Nobody but the host decides anything.

### The calls made (to revisit)
1. **No attack at all.** The acolyte only runs; cornered it keeps trying to get away. The AI allies rank it first.
2. **Its numbers:** HP 30, runs 3.2 (the crew 4.5: it can be run down), sight 9 in line of sight / 4 at all, stops running with no
   hero within 12 for 3 s, flees to a spot 3-6 cells off. A death or a noise within 8 makes it run too.
3. **The raise:** notices a body within 4 in sight, only with no hero within 7 of it, raises from 1.5; a 3 s wind-up, the body up
   0.9 s in at **full HP**, standing 1.4 s later. A hero within 4, a shove or a stagger breaks it off. No orange tint.
4. **Who raises:** either acolyte, whichever comes across the body first (the rear one raises what falls behind the file). Only
   unburnt zombie bodies; never a hero, never a burnt body.
5. **The procession:** a leader acolyte, **four zombies** and a **rear acolyte** (the approved look test's), `GAP` 1.8, walking 1.0
   (a zombie's shamble), hurrying x1.5 to its place.
6. **How many:** floor 1 one procession, floor 2 one (two at difficulty 0.5 or more), the last floor none (the grimoire's, H6).
7. **The route:** a loop of up to 3 rooms (at least 2): never the start, arrival or exit room, nor a crypt's; the first starting
   farthest from the crew's arrival, a second farthest from both; the nearest room next. No pause in a room.
8. **The spawn:** on its first leg with the file behind it (no turn back through its own file at the start). No bodies are laid for
   it: the bodies are the fight's (its own zombies, and any pack zombie the crew drops on its route).
9. **The halt:** the file stands for an acolyte away or raising and a zombie away or not resting; stragglers that are not fighting
   are dropped after 20 s; a fight holds it.
10. **Engagement:** an acolyte that sees the crew calls its file on them (the zombies' own senses do too, and their call sends the
    acolytes running).
11. **The leader dies:** the rear acolyte leads; both dead: the zombies are ordinary monsters.
12. **The objective: beside the pest**, $2,500 an acolyte (x the client's scale), floors 1-2; the pest objective and
    `DEAD_PEST_BONUS` stay until the grimoire (H6). A haunted contract's value grows by 4-6 acolytes' pay (a hellgate contract's
    small gates pay $3,000 each for 3-5).
13. **Acolytes are not in `Site.monsters`** (like the scouts) and never a pest; the processions' zombies are (they count toward a
    zombie pest).
14. **Drops:** fireball 25 % (it burns what the acolytes raise), heal 10 %.
15. **No sound of its own** (no war cry, a silent raise).
16. **Bodies in the fog are raised** (`downed_in_radius`'s `hidden_too`): the procession goes on where the crew is not looking.
17. **Its lantern light** is the look test's, one per acolyte: it pools in the candle-lit and dark rooms and is lost in a bright one.

### New player-facing strings (proposals for review)
- Monster name **Acolyte** (the combat log: "Acolyte died").
- Tracker row **Stop acolytes** "n / m"; objective label **Stop an acolyte (floor N)**; the job card's **Stop N acolytes** (each);
  the Ledger's **Acolyte stopped**; the elevator form's **Acolytes stopped on this floor: a of b.**
- Dev only: the gym's **Procession** button (and "Acolyte", the factory kind's name).

### Tests
- `tests/test_acolyte.gd` (new, solo): the kind (the cowl, its lantern light, the dead family's, no attack, slower than the crew,
  frailer than a skeleton, a priority target, no war cry); it flees a hero it sees, never strikes, calms down once far, and a hit
  sends it running; a procession (`ProcessionPlanner.build`) of two acolytes and four zombies starts on its first leg and walks its
  route (a route spot reached), the file in its places about `GAP` apart; the leader dies and the rear leads on; both dead, the
  zombies are ordinary monsters; a body by the way: the file stops, an acolyte raises it in its wind-up (arms up), at full HP, and
  it joins the back of the file and walks on in its place; a burnt body is passed over; a hero in sight: the zombies fight, both
  acolytes run, the file stands; killing acolytes pays the acolyte rate up to the floor's count (two Ledger lines); the gym's
  "Acolyte" and "Procession" (it walks its loop).
- `tests/test_net_procession.gd` (new, NetTest, `const PEERS := 3`, `off` and `coast`): board 9's heir contract, floor 1, the host's
  procession walking with its senses off. c1 shows every member a living puppet where the host has it, walking; the host drops the
  file's last zombie, the rear acolyte raises it, and c1 shows the acolyte in its gesture (ATTACK, arms up) mid-raise, then the zombie
  standing, risen once, with the file; the host kills the leader (paid) and c1 shows it gone and mirrors the Ledger line; c2 joins
  late and shows the living members where the host has them, the raised zombie standing, the leader gone; no OWNER-write guard on any
  machine.
- Updated: `test_haunted_contract` (acolyte objectives per floor and their pay, the card's line; each floor's processions as the
  contract says, two acolytes and four zombies each, a route of 2-3 rooms never through the start, arrival or exit room, the file in
  line on its trail; the total with the acolytes under 40), `test_monster_defs` (the acolyte in the factory, model and drop tables,
  the dead family's, no pack kind, no pest), `test_monster_models` (the acolyte's parts; a kind with no strike poses its raise for
  the wind-up check and skips the swing), `test_net_contract` (`acolyte.gd` in `REPLICATED`, `procession.gd` in `NET_SCRIPTS`).
- Run and passing: `test_net_contract`, `test_golden_floor` (not re-recorded), `test_haunted_contract`, `test_crypt_gen`,
  `test_monster_defs`, `test_monster_factory`, `test_monster_death`, `test_monster_models`, `test_monster_integration`, `test_zombie`,
  `test_crypt_rat`, `test_ecto_blob`, `test_net_world_codec`, `test_necro_look`, `test_gym`, `test_zfight`, `test_contract_flow`,
  `test_forms`, `test_net_floor`, `test_play_log`, `test_spell_revive`, `test_explosive_props`, `test_acolyte`, and the net tests
  `test_net_zombies`, `test_net_m3_world`, `test_net_m6_late_join`, `test_net_procession` (each `off` and `coast`). The full suite was
  not run.

### Not done in H4
- No crew (two-PC) play of a procession; the net test covers the stream, the raise and the late join.
- No acolyte sounds (a chant for the raise would help it read); no pause in a room; no procession through a crypt.
- The procession was judged on stills at the game camera (`procession_game/`) and the dev trace, not in play. In a bright room
  the acolytes are small dark figures whose lantern pool is lost (as the look test warned); a raise under a chandelier is hidden.
- The H3 decision still open: whether Heal raises zombies.
- Twice in about twenty screenshot runs with `--procession-demo` the game exited with code 255 (once before its screenshot); eight
  more runs of the same commands exited cleanly, and plain haunted runs never did. Not tracked down: watch for it.

## H5 as built (2026-10-31)

The user (2026-10-31), as for H1-H4: "Just build it now. We can revisit the decisions after it's built." Every open call below
was made on the spot, the simplest sound choice, and is listed to revisit. The networking was designed first ("H5 networking"
under H5 above) and built as designed. **To revisit (the user): the possessed knight animated** ("I'll want to see it animated"):
it walks, winds up and strikes now; see "Play it" and the screenshots.

### Play it

```
.\run.ps1 --client heir --seed 3 --floor 1 --spells coffee,fireball --no-mic --to-haunt 0 --focus haunt --zoom 9
         # the crew beside a possessed suit of armour (the camera on it); it sees the crew and comes
.\run.ps1 --client heir --seed 3 --floor 1 --spells coffee,fireball --no-mic --to-haunt 0 --haunt-demo fight --demo-after 0.1 --focus haunt --zoom 9
         # the knight marches at the player and chops (the allies held back, the monsters round it still)
.\run.ps1 --client heir --seed 3 --floor 1 --spells coffee,fireball --no-mic --to-haunt 0 --haunt-demo break --demo-after 1 --focus haunt --zoom 9
         # the player breaks it (billed $6,000 to Wick): its ghost pops out, hurt, and the camera follows it to the next suit
.\run.ps1 --client parish --seed 3 --floor 1 --spells coffee,fireball --no-mic --to-haunt 0 --focus haunt --zoom 9
         # a possessed skeleton in the church (the church and the crypts have bones only)
.\run.ps1 --gym --no-mic   # Spawn > Monster: "Armour", "Bones" (dormant), "Wisp" (free: it flies into a dormant host near it),
                           # "Armour (possessed)", "Bones (possessed)" (a ghost gets in as it lands: it wakes)
```

- Every haunted floor has ghosts: floor 1 two, floor 2 two, floor 3 three, each in a host from the start, and more dormant hosts
  than ghosts. The log names every host ("haunts: 2 ghosts, 4 hosts: armour (ghost) in room:1, armour in room:4, ...").
- `--to-haunt [n]` (solo) puts the crew beside possessed host n, across the screen from it (neither hides the other);
  `--focus haunt` follows it (after a break, its ghost); `--haunt-demo fight|break` stages it after `--demo-after` (the AI allies
  hold a few steps behind the player, the other monsters near it stand still). `scripts/app/dev/haunt_dev.gd`. No keybinding.
- Screenshots (the game camera at zoom 9, 1920x1080), `docs/design/haunt_game/`: `march.png` / `march_2x.png` (heir 3 floor 1,
  the wine cellar: the possessed knight on its march, the sword carried low at the hip, a leg forward, the ghost's vapour round
  it), `chop.png` / `chop_2x.png` (the same: its chop, the lunge onto the left foot, the sword down and forward; the price tag over
  it near the player; its plinth left behind by the wall), `wisp_free.png` / `wisp_free_2x.png` (the same suit broken: the
  scatter of plate and its plinth, "-$6,000 Suit of armour (Wick)" and the work order's property damage, the ghost out, its HP
  bar down a third, flying off to the next suit), `bones_fight.png` (parish 3 floor 1: a possessed skeleton in the crew's fight).
- No exit code 255 in this step's eleven screenshot runs (every one exited 0).

### What was built

| Piece | Where | What |
|---|---|---|
| A host | `scripts/monsters/haunt_host.gd` (`HauntHost`, a `Monster`) | DORMANT (no ghost): no AI (`_physics_process` only its look), out of the "monsters" group, `aggro` / `alert` / `hear` / a peck do nothing, a knock is a dent (no fight, no shout, no HP bar), `is_dormant()` true. POSSESSED (`ghost`, a Wisp): back in the monsters, it wakes (helpless `WAKE_T` 1.2 s, its model standing up) and is a monster of its kind's stats from its spot. BROKEN: the owner bills a priced kind (`Ledger.damage(name, price, culprit)`: the last thing that hurt or shoved it) and throws its wisp out (`Wisp.eject`) |
| The suit of armour | `scripts/monsters/armour_host.gd` (`ArmourHost`, kind `armour`), `MonsterDefs` "armour" (`"billed"` $6,000, "Suit of armour") | Dormant exactly the priced suit: the same model, look and size (`Monster.SIZE_FIXED`), the same price tag near this screen's own hero, the props' wobble and chips. Possessed: HP 90 (the suit's), speed 2.0, a chop of 16 after a 0.8 s wind-up, cooldown 1.9, reach 1.7, a 120-degree cone, aggro 8. It leaves its plinth where it stood (a cosmetic node in the world) and stands on it until it steps off (`KnightModel.lift`). Broken: the props' break (debris, dust, the red price), a scatter of plate left, the knight folds and goes |
| The skeleton | `scripts/monsters/bones_host.gd` (`BonesHost`, kind `bones`), `MonsterDefs` "bones" (no bill) | Dormant: slumped against its wall, the eyes out. Possessed: a skeleton's numbers (HP 40, speed 3.2, 10 a cleave). Broken: a skeleton's topple; no bill |
| The ghost | `scripts/monsters/wisp.gd` (`Wisp`, kind `wisp`, "Ghost"), `MonsterDefs` "wisp" | HP 36, flies at 3.4 (the crew walks 4.5), never attacks or yells. INSIDE a host: hidden, out of "actors" and "monsters" (no query finds it, nothing hits it), riding its host. EJECTED: out where its host fell, hurt `BREAK_HURT` 12 (a third; the verb, the culprit its source), helpless 0.5 s. FREE: flies to the nearest dormant host within 16 it can reach (two wisps never go for one: claims) and gets in (`possess`); with none, keeps 7 from the heroes (a spot away, the acolyte's way) and drifts. Anyone's hit hurts it (a plain swing, an arrow, a spell); at 0 HP it bursts and is freed |
| The knight, animated | `scripts/art/lowpoly/ghost/knight_model.gd` (`KnightModel`), `ArmourModel`'s soups (now static) | The rest: the guard (a wide stance, leaning in, the sword point-up across the body in both hands, breathing). The march: the legs swing from the hip, the body rolls over each step and leans into it, the sword carried low at the right hip, point leading. The wind-up: the sword hauled over the right shoulder in both hands, leaning back, twisting. The strike: a chop down and forward, a lunge onto the left foot. The war cry: the sword thrust up. Downed: folded forward, the sword flat by it. The wake: every part eased from the dormant pose to the awake one over 1.2 s |
| The skeleton's model | `scripts/art/lowpoly/ghost/bones_model.gd` (`BonesModel`, a `GruntModel`) | Dormant: `HauntPiece`'s slumped pose, the eyes out; awake: the grunt's walk, wind-up and swing; the wake eased over 1.4 s |
| The wisp's model | `scripts/art/lowpoly/ghost/wisp_model.gd` (`WispModel`) | The look test's wisp (the head with its eyes and mouth, five tail puffs, its light) in the rim look; the tail trails behind its heading, longer and flatter the faster it goes; the wisp shader with the monsters' hooks (a hit flash, the downed grey); no light while hidden |
| The possessed look | `scripts/art/lowpoly/ghost/haunt_dress.gd` (`HauntDress`) | The user's picks from the look tests on a game model: the ghost toon body in the rim look (always rim, at soft, pale blue), the vapour body round every part but the plinth, and the toned-down seep off the head and shoulders. Per machine, from `ghost` |
| Where they stand | `scripts/contracts/planners/haunt_planner.gd` (`HauntPlanner`), `SitePlan.haunts`, `SiteBuilder` | Own dice from the floor seed, planned after the processions, spawned last of the actors (the hosts, then a wisp in each possessed one: no earlier net id moves). Ghosts `WISPS` 2 / 2 / 3; hosts twice that plus one, at most one a room, every room but the start, arrival and exit rooms (a crypt's included); a full floor cell against a wall (two wall sides or more, a midpoint wall's cut cells counted; not in a doorway), clear of the plan, 4 cells from another host, standing toward its wall's face (`HexMap.nearest_wall`, 0.6 off it), facing into the room. A mansion house room's host is armour 65 % of the time, else bones; the church's and the crypt's are bones. The possessed ones: the first in the seeded order, then the farthest from those picked |
| Networking | `NetWorld` (`world.haunt`, `haunt_states` / `apply_haunts`), `NetJoin` (`haunts`), `NetEvents`, `NetFloor.PLAN_DEFAULTS` | As designed ("H5 networking"); the checklist below |
| Tentacles | `Tentacles.covers` | False for a wisp: they pass through it; a host is shoved and smashed as any monster |
| AI allies | `AllyBrain._pick_eager` / `_pick_free`, `Monster.is_dormant` | They never pick a dormant host; a possessed one and a free wisp are foes |
| The fog | `game.gd` (`_setup_fog`), `FogView._apply_contents` | Hosts follow the props' rule (shown once seen) while dormant, the movers' once possessed (the static pass skips a node in "monsters"); a free wisp is a mover |
| Gym | `GymSpawns` | "Armour", "Bones" and "Wisp" (the factory kinds) and "Armour (possessed)" / "Bones (possessed)" (`monster:<kind>:possessed`: a wisp gets in as it lands and it wakes), in the existing Monster group; no keybinding |

### The networking checklist (networking.md)
1. **Shapes.** The hosts and the wisp: **owned actors**, host monsters, seed-built (no new shape: nothing turns from a prop into
   a monster; the priced suit of armour stays a PricedProp, a plain antique). Possession: one reliable world event.
2. **Vars.** `HauntHost`: `ghost` OWNER (carrier `world.haunt`), `price` SPAWN, `_last_by` PRIVATE (the bill's culprit),
   `possessions`, `phase`, `_woke_at` LOCAL. `ArmourHost`: its tag, plinth and wobble LOCAL. `Wisp`: `host` OWNER (carrier
   `world.haunt`), its AI (`_goal`, `_seek_t`, `_flee_goal`, `_flee_pick_t`, `_drift_goal`, `_drift_t`, `_stuck_at`) PRIVATE,
   `entered` / `ejected` LOCAL. `SitePlan.haunts` SPAWN. In `test_net_contract`'s `REPLICATED` (`haunt_host.gd`, `armour_host.gd`,
   `bones_host.gd`, `wisp.gd`, `NetEvents.WORLD_CARRIES` and `LATE_JOIN`).
3. **Verbs.** The break's hurt on the wisp is `apply_damage` (the wisp's owner, the host, applies it); the hosts' blows are
   Monster's `Combat.melee_arc`; possession writes only the possessing pair's own links on the owner (`possess`, `take_ghost`).
4. **Randomness.** The plan on the planner's own generator from the floor seed; the wisp's drift on the host's `GameWorld.rng`
   (AI); looks (the pulse phase) on `fx_rng`.
5. **Motion.** Hosts and free wisps stream as any monster; a wisp inside rides its host on the owner, so its entry moves with it.
6. **Cosmetic:** the ghost look and the wake, the wisp's light, the plinth and the rubble, the price tag, the dent's wobble.
   **Gameplay:** who possesses what, HP, the break and its bill.
7. **A late joiner.** The keyframe (every living host and wisp), the gone ids (a broken host, a dead wisp: freed), and `haunts`
   `[wisp id, host id or 0, x, y, z]` (`NetWorld.haunt_states`): each ghost put in its host (which wakes on the joiner) or out.
8. **The scenario:** `tests/test_net_haunt.gd` (below).
- The event: `world.haunt {id: the wisp, h: its host or 0, x, y, z}`, queued with the deaths (`NetWorld._apply_deaths`, kind
  "haunt"), so a client applies a break's `world.die` and its ghost's ejection on the host's beat, in order. Nobody but the host
  decides anything.

### The calls made (to revisit)
1. **No new shape**: a host is a host monster from spawn with a dormant state; possession is a link on each side carried by one
   world event (above).
2. **The priced suit of armour stays a plain antique** (a PricedProp, never possessed); the armour hosts are separate actors that
   look exactly like it while dormant (the same model, material, size and price tag) and bill the same when broken.
3. **A dormant host is a piece of the room**: no AI, out of the monsters (never a pest, the staff are not scared of it), the AI
   allies never pick it, a knock is a dent (a flash, the armour's wobble and chips; no HP bar, no fight, no shout). The crew can
   still break it, and a broken suit is billed, possessed or not.
4. **How many:** ghosts 2 / 2 / 3 on floors 1 / 2 / 3; hosts twice the ghosts plus one (so each ghost has a dormant host to flee
   to), at most one a room, never in the start, arrival or exit room. A small floor gets fewer (heir 3 floor 1: four hosts).
5. **Where:** against a wall, 0.6 off its face, facing into the room, 4 cells apart; the possessed ones spread out (the farthest
   from those already picked).
6. **Which kind:** the mansion's house rooms a suit of armour 65 % of the time, else bones; the church's rooms and every crypt
   room bones (the armour is the mansion's antique).
7. **The armour's numbers:** HP 90 (the priced suit's), a heavy march 2.0, a slow chop (0.8 s wind-up) of 16, reach 1.7.
   **The bones':** a skeleton's.
8. **The wisp's numbers:** HP 36, flies 3.4 (it can be run down), a break costs it 12 (three breaks kill it, or a few hits), it
   flies only to a dormant host within 16 it can reach, keeps 7 from the heroes when it has none, never attacks.
9. **Possessed at spawn: awake at once** (no wake), standing at its spot like any resting monster; no ambush or guard state of its
   own (it wakes on sight, as a monster does).
10. **The wake:** helpless 1.2 s while its model stands up (the knight eased out of its antique pose, the skeleton up off the
    floor); a ghost getting in shows a puff of its colour.
11. **The plinth stays behind** (a cosmetic node where the suit stood); the knight stands on it until it steps off.
12. **Broken:** the armour breaks like a prop (debris, dust, the red price) and leaves a scatter of plate; the bones topple as a
    skeleton; both are then freed (a late joiner sees neither the plinth nor the plate of one broken before it joined).
13. **The bill's culprit** is the last thing that hurt or shoved the host (a tentacle's caster, a hero's swing, a shove into a pit).
14. **No objective or pay line for ghosts**: a haunted floor's paid work stays the pest and the acolytes (H6 brings the grimoire
    and reworks the haunted invoice). Hosts and ghosts are not in `Site.monsters` (no pest count).
15. **The ghost's look is the user's picks** (rim, soft, pale blue; the vapour and the toned-down seep on a host); its light at
    soft, none while it is inside a host.
16. **The knight's animation** (the user's "to revisit"): the guard at rest, the march with the sword at the hip, the overhead
    wind-up, the chop with a lunge; no knees (plate: rigid legs from the hip), as the look test's rig.
17. **Tentacles** pass through a wisp (it is not covered at all: no damage, no shove) and shove and smash the hosts.
18. **The fog:** dormant hosts are shown once seen (the props' rule), possessed ones and free wisps only in view (the movers').
19. **War cries:** none for a wisp; a host yells the shared monster cry. The skeleton's swing plays the light swing.
20. **Model tests:** the knight and the wisp have no ember faces (no glowing visor, the user's call; the wisp is all glow), and
    the wisp has no tell (`test_monster_models`' `NO_GLOW`, `NO_TELL`).
21. **A ghost thrown out over the void** (its host shoved into a pit or the lava) comes out where the host last stood on floor.
22. **The dev flags** `--to-haunt`, `--haunt-demo fight|break`, `--focus haunt`; the gym's "(possessed)" buttons.

### New player-facing strings (proposals for review)
- Monster names **Suit of armour**, **Skeleton** (the bones) and **Ghost** (the wisp) (the combat log: "Ghost died").
- The armour's price tag **Suit of armour – $6,000** and its Ledger line **Suit of armour** $6,000 (the priced suit's name and
  price, H1's).
- No objective, tracker row, note, ticket or dispatch line.
- Dev only: the gym's **Armour**, **Bones**, **Wisp**, **Armour (possessed)**, **Bones (possessed)** buttons; the log's "haunts: ...".

### Tests
- `tests/test_haunt.gd` (new, solo): the kinds (the knight, the bones, the wisp; the armour's name, price and HP are the priced
  suit's, bones cost nothing, the crew outruns a wisp, it never attacks or yells); dormant: the antique on its plinth, out of
  the monsters, the priced suit's tag, a hero in sight and a knock start no fight, no HP bar, no shout or noise wakes it;
  possessed at spawn: the wisp in its host, hidden and out of every query, the host awake in the ghost look with the vapour, its
  plinth left, a hit on the host leaves the wisp, the wisp rides it; a possessed armour and skeleton see the hero, wind up and
  land a blow; the knight's wind-up raises its sword, its legs swing on the march, a wake starts from the dormant pose; breaking
  a possessed suit bills it once to the culprit, throws the wisp out hurt where it fell, and it flies to the next dormant host and
  possesses it (it wakes); a dormant suit broken bills too; a skeleton bills nothing and throws its wisp out hurt; a free wisp
  with no host keeps away from the hero and never strikes, a hit hurts it (no fight back), hits kill it and it is freed, a plain
  swing hits it; tentacles never cover a wisp (no damage, no shove) but smash the suit beside it.
- `tests/test_net_haunt.gd` (new, NetTest, `const PEERS := 3`, `off` and `coast`): board 9's heir contract, floor 1. c1 shows the
  ghost in its suit (hidden, out of the queries) and the suit possessed in the ghost look, the next host dormant; the host's
  player breaks the suit (billed on the host), c1 shows it gone, the ghost out and hurt where the host has it, and mirrors the
  bill; the ghost flies to the next host (moved near on the host) and gets in, and c1 shows it inside and that host possessed
  where the host has it; c2 joins late and shows the broken suit gone, the ghost in its new host, that host possessed where the
  host has it, the other ghost still in its first host, a dormant host dormant, and the bill; no OWNER-write guard on any machine.
- Updated: `test_haunted_contract` (every haunted floor's ghosts each in a possessed host, more hosts than ghosts, armour only in
  the mansion's house rooms, none in the start, arrival or exit room, against a wall on a full cell, apart; a ghost in its host
  hidden), `test_monster_defs` (the three rows: the dead family's, no pack, no pest; the armour's bill is the priced suit's, bones
  bill nothing; the factory and model kind lists), `test_monster_models` (the three models' parts; `NO_GLOW`, `NO_TELL`),
  `test_net_contract` (the four scripts in `REPLICATED`).
- Run and passing: `test_haunt`, `test_net_haunt` (off and coast), `test_net_contract`, `test_golden_floor` (not re-recorded),
  `test_haunted_contract`, `test_crypt_gen`, `test_monster_defs`, `test_monster_factory`, `test_monster_death`,
  `test_monster_models`, `test_monster_integration`, `test_zombie`, `test_acolyte`, `test_priced_prop`, `test_ghost_look`,
  `test_haunt_look`, `test_net_world_codec`, `test_zfight`, `test_contract_ledger`, `test_spell_tentacles`, `test_gym`, and the net
  tests `test_net_m3_world`, `test_net_m3_objects`, `test_net_m6_late_join`, `test_net_procession` (each `off` and `coast`). The
  full suite was not run.

### Not done in H5
- Evicting a ghost without breaking its host (wanted, deferred by the user).
- No crew (two-PC) play; the net test covers possession, the break, the move and the late join.
- No sounds of their own (a ghost's moan, plate clanking on the march): the armour's knock and break are the props' sounds.
- A client's knock on a dormant suit flashes it but does not wobble it (the wobble is the host's look); a late joiner does not see
  the plinth or the plate of a suit broken before it joined.
- The AI allies' prop care does not know a dormant suit (a spin beside one can break it, as it can a monster near it).
- A wisp flies the floor's paths (it does not pass through walls).
- The knight was judged on stills at the game camera (`haunt_game/`), not in play.

## H6 as built (2026-10-31)

The user (2026-10-31), as for H1-H5: "Just build it now. We can revisit the decisions after it's built." Every open call below
was made on the spot, the simplest sound choice, and is listed to revisit. The decided frame: "the plan was acolytes on floor one
and two, and the grimoire on the last [floor]", the grimoire "pulsing out the dead until it is slammed shut or burned", a physical
object on its altar with the live eye (necro-look.md: the altar, "I like the bigger size"; the live eye, its pupil darting).

### Play it

```
.\run.ps1 --client heir --seed 3 --floor 3 --spells coffee,fireball --no-mic --to-grimoire --focus grimoire
         # the crew in sight of the grimoire, just outside its wake range: walk in and it opens
.\run.ps1 --client heir --seed 3 --floor 3 --spells coffee,fireball --no-mic --to-grimoire --focus grimoire --grimoire-demo burst
         # it wakes and a burst comes at once (also: hold, wake, phase, shut, burn; --demo-after S, default 1)
.\run.ps1 --client heir --seed 3 --invoice-demo                                 # a haunted invoice (acolytes, the grimoire burned)
.\run.ps1 --gym --no-mic                                                         # Spawn > Gate > "Grimoire" (dormant)
```

- Every haunted contract's last floor has one, in the story's room (where a hellgate contract's origin gate stands). The log says
  where ("grimoire: in room:N, 600 HP").
- `--to-grimoire` (solo) starts the crew about 9 cells from it, in its sight and outside its wake range (with the allies round the player); `--focus grimoire`
  puts the camera on it; `--grimoire-demo hold|wake|burst|phase|shut|burn` stages it after `--demo-after` (the AI allies hold, the
  floor's monsters stand still). `scripts/app/dev/grimoire_dev.gd`. No keybinding.
- Screenshots (the game camera at zoom 16, 1920x1080, heir 3 floor 3, the library), `docs/design/grimoire_game/`: `dormant.png`
  (asleep: the shut green book on its altar, the live eye on its cover, the candles and a dim whole circle), `flare.png` (awake,
  the book open, the column up and the pages circling, the light swelling a moment before a burst), `burst.png` (the burst: two
  skeletons and a zombie risen in its ring, a pale ring and motes at each), `failing.png` (hit to 30 %: its last phase, the
  circle broken and red, the candles out, a crypt rat among the dead), `shut.png` (slammed shut: the eye dead, every light out,
  the pages fallen; the tracker's "shut", "+$11,000 Grimoire slammed shut" on the ticker and the banner), `burned.png` (burned:
  the book and the fallen pages charred, smoke; "Grimoire burned"), `invoice.png` (`--invoice-demo --client heir --seed 3`: the
  acolytes on floors 1-2, "Grimoire burned" on floor 3, the pest per floor), `job_card.png` (board 9: the heir's card, "Stop 4
  acolytes", "Shut the grimoire", "Exterminate zombies", the staff, beside two hellgate cards).
- No exit code 255 in this step's fifteen screenshot runs (every one exited 0).

### What was built

| Piece | Where | What |
|---|---|---|
| The grimoire | `scripts/contracts/grimoire.gd` (`Grimoire`, **extends `Hellgate`**) | The hellgate's spawner, phases, phase-change shove, HP bar and networking, with its own tuning table, look and closing. Team monsters, immovable, `origin` (the floor's source: the origin gate's phases, spawn ring and bar), radius 2.2 (its altar). `Grimoire.place(cell, {difficulty, depth, yaw})` |
| Asleep | `Hellgate.step` (unchanged) | DORMANT until a hero comes within `ACTIVATE_RANGE` (12), it is hit, or a monster's alarm reaches it (`MonsterSenses`, the gates' group). The book lies shut on its altar, the live eye on its cover darting about, the candles and a dim, whole circle lit, a dim light, a slow breath |
| Awake | `Grimoire.book_profile`, `KIND_WEIGHTS` | The book flies open (the column of light, the circling pages) and bursts: every `interval` (12 s at pressure 0 to 5.5 s at 1) the pages flare for a second (`set_flare`), then 2-4 (+1 / +2 by phase) of the dead rise in its ring 3-4 cells out, aggroed on the nearest hero, a pale ring and motes at each, the book surging (`pulse`); up to its cap of living spawns (5-12, +2 / +4 by phase). The mix: skeletons and zombies (3:2, then 3:3), crypt rats in its last phase (2:3:2). HP 450-750 on the hellgate's pressure (difficulty and depth: the last floor's) |
| Phases | `Hellgate._on_damaged` (the origin gate's thresholds) | Open (> 66 %), weakened (<= 66 %), failing (<= 33 %): the look test's states (the column thins and stutters, the circle breaks, candles go out, the flicker tends red), each faster with bigger bursts and a higher cap. Each change winds up 0.9 s (a pale ring) and blasts the crew back (the origin gate's shove, `Combat.shove_radius`) AND stands every unburnt zombie body within `RAISE_RADIUS` (9) back up at full HP (`Zombie.raise`, the body's owner: `Net.resolves`) |
| Slammed shut | `Grimoire._on_death`, `GrimoireModel.close_look` | At 0 HP it closes once: the book shut, the eye dead (no iris: the bare eyeball rolled back), every light out, the pages fallen round it. Its spawns stop (`HellgateEvents.stop_spawns`, as the origin gate's). The shut book stays on its altar (no free; a `DecorBlocker` keeps the altar solid). `closed` fires once |
| Burned | `Grimoire.fire_at` (from `FireballSpell` before its blast lands), `Hellgate.is_flammable` / `burn_mult`, `Burning` | Its pages burn: a fireball over it always lights it (no roll, a full 10 s fire), and a fire on it ticks `BURN_MULT` (6) times as hard (18 HP a second against a fire's usual 3). Damp puts it out, as any fire. If it was on fire when the killing blow landed it closes BURNED: the shut book charred, smoke and embers off it (`burnt`, `burnt_down`). A hellgate still never burns |
| Its look | `GrimoireModel` (the game's now) | The altar (1.4) facing the game camera (`Grimoire.FACING`). New in the model: the `dormant` state (shut, the live eye, candles lit, the circle dim and whole), `set_state` (rebuilt in place), `set_flare` / `pulse` (every light swells), `close_look(burnt)` (`dead_eye`, `burnt`: charred colours, smoke and embers). The look test's four states build as before (`test_necro_look`) |
| Where it stands | `GatePlanner.plan` / `spawn_grimoire`, `SitePlan.grimoire` | The spot the origin gate's rule picks on the last floor (the biggest eligible room, which is the story's origin room, no dice), recorded as `{cell, room}`; spawned LAST of the actors (after the ghosts: no earlier net id moves). Kept clear as the origin gate: `SitePlan.gate_cells` (employees, props, hazards, packs keep off), `ThemeCtx` (decor keeps off; a 5.8 body), `SiteBuilder._block_cells`, `RoomThemes`' crowded rooms, `DoorPlan.score` (as the origin gate) |
| The hellgate | `scripts/contracts/hellgate.gd` | Its model calls moved into overridable look hooks (`_build_look`, `_look_awake`, `_look_flare`, `_look_pulse`, `_look_hurt`, `_look_phase`, `_look_shove`, `_look_close`) and its numbers into `_profile_now` / `_weights_now`, unchanged for a hellgate (same values, same dice); `is_flammable` (false) and `burn_mult` (1) |
| The invoice | `ContractRun` (`GRIMOIRE_PAY`, `grimoire_pay`, `has_grimoire`), `ContractSession` (`grimoire_closed`, `GRIMOIRE_LINES`, `gates_open`), game.gd | A haunted contract reads like a hellgate contract's: the acolytes where the small gates are (H4: $2,500 each, floors 1-2), the GRIMOIRE where the origin gate is (**$10,000**, the origin gate's pay, x the client's scale; a "grimoire" objective on the last floor), the pest at the standard **$10,000** (30/30/40; H1's `DEAD_PEST_BONUS` is retired), the staff. The floor's state has `grimoire` and `grimoire_closed` ("", "shut" or "burned"); an open grimoire keeps the floor from clean (`gates_open`), so floor 3's pest pays once it is shut, as once the origin gate is. Its Ledger line pays once where the books are kept; a client mirrors it |
| The forms | `ContractRun.card_lines`, game.gd (`_update_tracker`, `_elevator_lines`, `_on_grimoire_closed`), `NoteCopy`, `DamageTicker` | The job card's line "Shut the grimoire", the tracker's row (OPEN / shut / burned), the exit form's line, the banner when it closes; its pay (and the acolytes', which H4 left off) rides the ticker. Floor 3's dispatch lines name the book |
| Networking | `NetWorld`, `NetJoin`, `NetEvents`, `test_net_contract` | See the checklist below |
| Dev | `GrimoireDev`, `GameDev._grimoire_floor_ready`, `GameDev._invoice_demo_haunted` | The flags above; `--invoice-demo` with `--client heir` / `parish` shows a haunted invoice |
| Gym | `GymSpawns` | "Grimoire" in the existing Gate group (beside Hellgate and Origin gate): it lands dormant, the gym's difficulty, depth 3. No keybinding |

### The networking checklist (networking.md)
1. **Shape: the hellgate's** (an owned actor of the host's: the host simulates it and streams its state; a client shows a puppet;
   the design docs' "host-arbitrated object like a hellgate" is this, the shape the hellgate already has). It IS a `Hellgate`, so
   `NetWorld` tracks it as a gate: its state rides the snapshot's GATE entry (`NetWorldCodec.GateState`: HP, awake, flare, phase,
   the shove's wind-up), its bursts `world.spawn` (gate: it), its phase `world.phase`, its blast `world.shove`, its closing
   `world.die`. Not a new shape.
2. **Vars.** `Grimoire`: `yaw` SPAWN; `burnt` OWNER (carrier `world.burn {id}`, after its `world.die`); `_burn_seen` and
   `raised_total` PRIVATE; `book` LOCAL. Hellgate's OWNER vars ride the GATE entry (`NetWorldCodec.GATE_FIELDS`). `SitePlan.grimoire`
   and `ContractRun.grimoire_pay` SPAWN. In `test_net_contract`'s `REPLICATED` (`grimoire.gd`: the GATE fields and its
   `NetEvents.WORLD_CARRIES` row) and `NetEvents.LATE_JOIN`.
3. **Verbs.** Hits on it are hits on a host-owned actor (a client's are requests); its blast is `Combat.shove_radius`; its raise is
   `Zombie.raise` (`Actor.revive`) on each body its owner resolves (`Net.resolves`), whose `world.rise` the zombie already sends;
   its fire is `Burning.ignite` on its owner (`Grimoire.fire_at` asks `Net.resolves`), the status announced as any fire.
4. **Randomness.** Its kind picks and spawn cells on its own generator seeded from its cell (as a gate's), only on the host. Its
   look's phase is a hash of where it stands. Nothing else is rolled.
5. **Motion.** None: it never moves (`facing`, `climbing` fixed).
6. **Cosmetic:** the book's states, the eye, the flare and the surge, the rings and motes, the char and smoke. **Gameplay:** HP,
   awake, phase, the burst timer, `burnt` (which Ledger line and banner), the shut book's blocker.
7. **A late joiner.** A living one: the keyframe (its GATE entry: awake, phase, HP; the book follows), its living spawns by the
   `world.spawn` replay (from it). A closed one: a gone id shown shut (`Net.remote_die`: the shut book stays), then the snapshot's
   `books` rows `[id, burnt]` (`NetWorld.book_states` / `apply_books`) char a burned one. A fire on a living one: statuses, replay.
8. **The scenario:** `tests/test_net_grimoire.gd` (below).
- Ordering: the host's `world.die` goes out from `GameWorld.actor_died` before its `_on_death`, which emits `burnt_down`, so
  `world.burn` follows it; a client applies both through the death queue in order (its `_burn` needs the copy dead).
- **Hellgate floors are byte-identical:** `test_golden_floor` passes against the recorded floors, not re-recorded. `SitePlan.grimoire`
  is left out of the plan part at `{}` (`NetFloor.PLAN_DEFAULTS`) and `ContractRun.grimoire_pay` out of the run part at 0
  (`RUN_DEFAULTS`); a haunted last floor hashes both in.

### The calls made (to revisit)
1. **A Hellgate subclass**, not a class of its own: the spawner, phases, blast, bar and the whole of its networking are the gate's;
   what differs (its table, its kinds, its look, its closing, fire) is overridden. The hellgate's model calls became overridable
   hooks for it (no change for a hellgate).
2. **Slammed shut = hit to 0 HP**; **burned = closed while on fire.** Both close it and pay the same; only the look, the Ledger line
   and the banner differ. Fire is the fast way: a fireball always lights its pages (no roll, 10 s) and its fire burns 6 times as
   hard (18 HP/s, about 90-180 HP a fire on a 450-750 HP book). Damp puts it out.
3. **Its numbers:** HP 450-750 (the origin gate's 480-780, a little under), a burst every 12-5.5 s of 2-4 (+1 / +2 by phase), a cap
   of 5-12 (+2 / +4), all on the hellgate's pressure (difficulty and depth; it is always on floor 3). Phases at the origin gate's
   66 % / 33 %, intervals x0.75 / x0.55.
4. **Its dead:** skeletons and zombies, crypt rats in its last phase; never ecto blobs (one a pack), acolytes or ghosts. Bursts
   bring the standing dead; **no bodies are laid** for anyone to raise (floor 3 has no acolytes, H4's call).
5. **The phase blast raises the near zombie bodies** (within 9, unburnt, full HP), besides the origin gate's shove: the dead family's
   twist on the phase change, and a reason to burn the bodies round it.
6. **Its phases show in the book** (the look test's open / weakened / failing, from the user's "do it with the effects surrounding
   the book"), its flare and surge in every light (column, circle, light, pages' glow).
7. **Asleep it is the shut book with the live eye** (the user's eye, darting), candles lit and a dim whole circle; it opens when it
   wakes. **Closed, the eye is dead** (no iris), every light out; burned, the cover and fallen pages are charred and smoke rises.
8. **It wakes by the hellgate's rule** (a hero within 12, a hit, a monster's alarm), not by entering its room.
9. **The shut book stays** on its altar (a hellgate collapses and is freed), solid (a `DecorBlocker`).
10. **The altar faces the game camera** (`FACING`), whatever the room, so the book and its eye read; the lectern is not used.
11. **Where it stands:** the origin gate's spot rule on the last floor (the story's room, kept clear as the origin gate's).
12. **Closing it stops the floor's spawns** (`HellgateEvents.stop_spawns`, the origin gate's flag); its risen dead stay and fight on.
13. **The haunted invoice:** `GRIMOIRE_PAY` $10,000 (= `ORIGIN_PAY`), the pest at the standard `PEST_PAY` (H1's `DEAD_PEST_BONUS`
    removed: it stood in for the source the contract lacked), the acolytes as H4 built them. A haunted contract's value is now
    acolytes (4-6 x $2,500) + grimoire + pest + staff, against a hellgate contract's small gates (3-5 x $3,000) + origin + pest +
    staff, before the client's scale.
14. **Ghosts and hosts pay nothing:** they are the client's property and a hazard (a broken suit bills, H5), not an objective.
15. **Floor 3 is clean** only once the grimoire is shut and no pest is left (the origin gate's rule), so its pest share waits for it.
16. **The ticker** shows the grimoire's and the acolytes' pay (H4 had left the acolytes' off), as the gates'.
17. **A client's banner** waits one frame after the death (its `world.burn` lands in the same pass) to say shut or burned.
18. **No sound of its own** (its bursts, blast and close are silent beyond the shake; the slam is a look).
19. **`test_haunted_contract`'s floor-total sanity bound** went from 40 to 42: keeping the grimoire's cell clear moves floor 3's pack
    draws (parish 11 floor 3 holds 41 monsters before the grimoire wakes).

### New player-facing strings (proposals for review)
- Name **Grimoire** (the log's "Grimoire died", as a hellgate's; its HP bar has no label).
- Objective **Shut the grimoire (floor 3)**; the job card's **Shut the grimoire**; the tracker's **Shut the grimoire** OPEN / shut /
  burned; the exit form's **Grimoire: still open (the biggest line on the invoice).** / **Grimoire: slammed shut.** / **Grimoire:
  burned.**
- Ledger and invoice lines **Grimoire slammed shut** and **Grimoire burned**.
- Banners (`NoteCopy.GRIMOIRE_SHUT`, `GRIMOIRE_BURNED`): **"The book is shut. The house goes quiet. The invoice does not."** /
  **"The book is ash. The house goes quiet. The invoice does not."** (silent until `tools/render_dispatch.ps1` runs).
- Floor 3's dispatch lines (`NoteCopy.DISPATCH_DEAD[3]`, reworked): **"This is where it started, in the {origin}. There's a book on
  the altar raising them. Slam it shut or burn it."** / **"The {origin}'s on this floor, and so is the book that started it. Shut
  it, then put the {pest} back down."** (they were H1's "This is where it started, in the {origin}. Put the {pest} down and get
  everyone out." / "The {origin}'s on this floor. Whatever got up down here, put it back down.")
- Dev only: the gym's **Grimoire** button; the log's "grimoire: in room:N, ... HP".

### Tests
- `tests/test_grimoire.gd` (new, solo): only a haunted last floor has one (heir 3 and parish 11, floors 1-3; a hellgate floor 3 has
  its origin gate instead), in the story's room, HP from its table; dormant (the shut book, the live eye, no column) and no spawns
  however long with the crew far off; a hero near or a hit wakes it and the book opens; the pages flare before a burst, a burst
  of its size of the dead family rises in its ring from it, aggroed, and it holds at its cap; phase 1 at 60 % (weakened, faster,
  the blast throws the crew back, the near body stands up at full HP, the burnt one and a far one stay down), phase 2 at 30 %
  (failing); hit to 0 it is slammed shut once (the eye dead, every light out), its spawns stop, it stays with its altar solid; a
  fireball always lights it, it burns hard, Damp puts it out, a fire that finishes it burns it (charred, smoking, `burnt_down`
  once), `net_burn` chars a copy, the late joiner's `books` rows; a hellgate still never burns; the haunted invoice (the grimoire
  pays an origin gate's worth, the value is acolytes + grimoire + pest + staff, floor 3's pest waits for the grimoire, it pays once
  with its line on the ticker, every objective met pays the contract value); the gym's Grimoire.
- `tests/test_net_grimoire.gd` (new, NetTest, `const PEERS := 3`, `off` and `coast`): board 9's heir contract, its last floor. c1
  shows the grimoire asleep (the shut book, the eye alive); the host wakes it and a burst lands: c1 shows it open and the dead it
  brought; the host hits it to 60 %: c1 shows phase 1, the book weakened, at the host's HP; c2 joins late and shows it awake in
  phase 1, weakened, at the host's HP, with its spawns; the host sets it alight and the fire finishes it: c1 and c2 show it closed,
  the book shut and charred, the eye dead, the spawns stopped, the Ledger's "Grimoire burned" mirrored and the floor's objective met
  ("burned"); no OWNER-write guard on any machine.
- Updated: `test_haunted_contract` (the grimoire objective on the last floor, its pay, the card line, the pest at the standard rate;
  each last floor's grimoire in the story's room, dormant, its cell kept clear; none on floors 1-2), `test_net_contract`
  (`grimoire.gd` in `REPLICATED`), `test_dispatch_voice` (the grimoire's banners are listed).
- Run and passing: `test_grimoire`, `test_net_grimoire` (off and coast), `test_net_contract`, `test_golden_floor` (not re-recorded),
  `test_haunted_contract`, `test_crypt_gen`, `test_hellgate`, `test_hellgate_flow`, `test_contract_gen`, `test_contract_flow`,
  `test_contract_flow_game`, `test_contract_ledger`, `test_monster_defs`, `test_zombie`, `test_acolyte`, `test_haunt`,
  `test_necro_look`, `test_forms`, `test_gym`, `test_zfight`, `test_dispatch_voice`, `test_burning`, `test_net_floor`,
  `test_room_themes`, `test_net_world_codec`, and the net tests `test_net_m3_world`, `test_net_m5_contract`, `test_net_m6_late_join`,
  `test_net_zombies`, `test_net_haunt` (each off and coast). The full suite was not run.

### Not done in H6
- No crew (two-PC) play; the net test covers the stream, the burst, the phase, the burn and the late join.
- No sounds of its own (a page-flutter for the burst, a slam, a roar of flame); its banners' voice clips are not rendered.
- It was judged on stills at the game camera (`grimoire_game/`), not in play. Its numbers (HP, rate, the 6x fire) are untried.
- The H3 decision still open: whether Heal raises zombies. H7 (Ghost form) is next.

## H7 as built (2026-10-31)

The user (2026-10-31), as for H1-H6: "Just build it now. We can revisit the decisions after it's built." The decided frame: ghost
form "makes ghosts easier", not possible; a whole-body transform ("For now"); "ghost form makes it so that you can pass through
regular enemies, because you can walk through them[.] So it's for fighting ghosts"; "A hero in ghost form can be hit by regular
enemies. You can pass through them but if you wind up in their attack[,] you get hit." The old "make an enemy lose its target"
use is skipped; ghost mode after death is a later build. Every open call below was made on the spot, the simplest sound choice,
and is listed to revisit.

### Play it

```
.\run.ps1 --client heir --seed 3 --floor 1 --spells ghost,coffee --no-mic --to-haunt 0 --haunt-demo ghost --demo-after 0.5 --focus haunt --zoom 9
         # the player casts Ghost and walks at the possessed knight, straight through it as it comes (its chop still lands)
.\run.ps1 --client heir --seed 3 --floor 1 --spells ghost,coffee --no-mic --to-haunt 0 --haunt-demo ghost_wisp --demo-after 0.5 --focus haunt --zoom 9
         # the player breaks the knight and casts Ghost: its ghost out shows clearly and flies on to its next host, not away
.\run.ps1 --client heir --seed 3 --spells ghost,coffee --no-mic        # a haunted contract with Ghost slotted: say "cast ghost"
.\run.ps1 --gym --no-mic   # the gym's spell rows have Ghost (slot it); Spawn > Monster "Wisp" or "Armour (possessed)" to try it on
```

- `--spells ghost,...` starts with it slotted (any contract; the license requisition offers it too, its twelfth line). On a haunted
  floor its component drops from the ghosts, the ecto blobs and the acolytes.
- `--haunt-demo ghost|ghost_wisp` (`scripts/app/dev/haunt_dev.gd`) are the two new stages beside H5's `fight` and `break`: the player
  casts Ghost through its own controller (as a voice cast) and walks by the controller's scripted walk. No keybinding.
- Screenshots (the game camera at zoom 9, heir 3 floor 1, the wine cellar), `docs/design/ghost_form_game/`: `into_knight.png` (Wick
  in ghost form, the pale corpse in its warm ghost, walking into the possessed knight), `through_knight.png` (inside it: the two
  overlap, neither pushed), `past_knight.png` (out the far side, the knight behind; the chop took a bite of the HP bar on the way),
  `wisp_near.png` (the knight broken, "-$6,000 Suit of armour (Wick)"; Wick in ghost form right beside the ghost out on its plinth,
  the ghost in the clear look), `wisp_clear.png` (the same ghost flying on to its next host in the clear look, Wick back with
  Rebar; compare `haunt_game/wisp_free.png`, H5's soft look of the same moment).
- No exit code 255 in this step's six screenshot runs (every one exited 0).

### What was built

| Piece | Where | What |
|---|---|---|
| The spell | `scripts/spells/defs/ghost.gd` (`GhostSpell`), `SpellBook.DEFS` (the twelfth) | "cast ghost". The CASTER, wherever the aim is (a self-buff: no target, no snap onto a teammate): ghost form for `ghost_duration(power)` (6 s + 4 x power: 10 s at full power). Cooldown 20 s. Colour a pale spectral blue |
| Ghost form | `Actor.STAT_GHOST`, `Actor.is_ghost_form`, `GhostSpell.transform` / `MOD` | A modifier (the verb `set_modifier`, presence only), so it is a status like armor's or coffee's: refreshed by a new cast, never stacked, gone when it runs out. Going down ends it (`Hero._on_death`) |
| Walking through | `Actor._separate` / `_walks_through` | An actor in ghost form and a regular monster neither push nor are pushed by each other, both ways (the hero's separation skips the monster, the monster's skips the hero). Movement only: every attack still lands, theirs and the hero's. A ghost (a `Wisp`) is no regular enemy: it bumps a ghost-form hero. Teammates, staff, props and gates bump as ever |
| The look | `Hero._update_ghost_form` (`_ghost_shown`), `GhostForm` (the look test's, now in the game) | While `is_ghost_form()` the hero's model wears GhostForm (the pale corpse in a warm ghost of its own shape, never the enemy ghosts' cold blue; no shadow), on every screen from the status; a warm puff as it comes and goes (`GhostSpell.puff`). A seat handover (`become`) dresses the new model. The gym's own "Ghost form" experiment is unchanged |
| The edge against ghosts | `Wisp._nearest_to_flee`, `Wisp._process` / `seen_by_ghost`, `WispModel.set_clear` | A free ghost never keeps away from a hero in ghost form (it keeps away from the others as before; with a host in range it flies to it as before). While THIS screen's own hero is in ghost form every free ghost on it shows clearly: GhostLook's "strong" (alpha 0.5 against soft's 0.22, its light 1.4 against 0.5) |
| The component | `GhostSpell.component_soup`, `MonsterDefs` drops | **Ectoplasm**: a quivering glob of pale blue ectoplasm with a drip and its bead. Drops (rolled after each kind's older entries, so their dice stay put): the ghost (`wisp`) 50 %, the ecto blob 15 %, the acolyte 15 %. Only the dead family has them, so a hellgate floor never drops it (a mail package can hold any spell's component, this one too) |
| Voice | `GhostSpell.VOICE`, `tools/make_voice_clips.ps1`, Incantation's GHOST note | "ghost" and "ghosts"; the measurements below |
| Dev | `HauntDev` | `--haunt-demo ghost`, `--haunt-demo ghost_wisp` (above). The gym's spell rows list it (`SpellBook.ids()`) |

### The networking checklist (networking.md)
1. **Shape: a status of the caster** (the shape of armor's and coffee's modifiers): the cast is an event that lands on every machine at
   the same moment (`SpellBook.apply`); only the caster's owner applies it (`Net.resolves`) through the verb `set_modifier`, and
   `NetStatus` announces it (`st` "mods"). No new shape, event or request.
2. **Vars.** `Hero._ghost_shown` LOCAL (each screen's look). The state itself is Actor's `_modifiers` (OWNER, carried by `st`).
   `GhostSpell` is a def (consts and static funcs: no state). `WispModel.clear` / `_lit` are cosmetic (art). Nothing else new.
3. **Verbs.** `set_modifier` / `clear_modifier` on the owner only; nobody writes another actor's state.
4. **Randomness.** None (the puff is Fx's own).
5. **Motion.** Each machine moves what it owns: the owner's hero walks through the monsters it has (its copies of the host's), the
   host's monsters walk through the hero's copy from its announced modifier. A copy is placed by its owner's stream anyway.
6. **Cosmetic:** the ghost form's look and puff, the clear ghosts (per screen: only a screen whose own hero is a ghost). **Gameplay:**
   the status (who walks through what; who a ghost keeps away from, decided by the host's ghost AI from the announced status).
7. **A late joiner** gets it with the statuses (`NetStatus.late_join_state`: the host's copy of the player's hero carries the modifier
   it was told; `NetEvents.LATE_JOIN`'s "statuses: replay" for heroes); its screen then shows the look from it.
8. **The scenario:** `tests/test_net_ghost.gd` (below).
- **Not the pass-through flag.** The plan said "the pass-through flag already replicates" (`Actor.pass_through_until`, NetCodec's
  FLAG_GHOST). It is the AI allies' squeeze past each other, and through EVERYTHING (teammates, props); ghost form is through regular
  monsters only and must reach a late joiner and show a look, which a status does already. So the flag stays the squeeze, untouched.

### The calls made (to revisit)
1. **Self only:** the cast is always on the caster, wherever the aim points (the old design's "nearest actor to the aim, a teammate or
   an enemy" is skipped with the enemy use). Pointing it at a teammate could come later.
2. **A ghost-form hero hits regular enemies as ever** (swings, arrows, spells): passing through is movement only, both ways; it is
   "for fighting ghosts" because of the edge below, not because it is weak elsewhere. It walks through monsters, so it is also a way
   out of a crowd, whose blows still land.
3. **Duration 6-10 s** by power (10 at full power), **cooldown 20 s** (17 s held), the Revive/coffee tier; a cast while in ghost form
   refreshes it.
4. **What "easier" means against ghosts:** a free ghost never keeps away from a hero in ghost form (it still flies to a dormant host
   in range: it is not running from you), and a screen whose own hero is in ghost form sees free ghosts clearly (the "strong" look).
   Your hits do the same damage. Pulling a ghost out of its host is not built (eviction is deferred).
5. **A ghost bumps a ghost-form hero** (it is no regular enemy); teammates, staff and props bump as ever; hellgates and the grimoire
   are not monsters, so they block as ever.
6. **The look is the look test's GhostForm** (the pale corpse inside a warm ghost of the hero's shape), with no changes; the puff is
   the ghost form's warm colour. Downed, it ends (and the look with it).
7. **The component is Ectoplasm** (spells.md's "ectoplasm, a future ghost enemy"), a pale blue glob; it drops from the ghosts (50 %),
   the ecto blobs and the acolytes (15 % each), so a crew meets it on floor 1 of a haunted contract. Not on hellgate floors.
8. **The requisition keeps its eleven visible lines** (`SpellPicker.MAX_LINES`): the twelfth, Ghost, scrolls, as designed past the
   line count (chicken and Revive each raised it; it was left alone this time, so the sheet's height is unchanged).
9. **No sound of its own** (the cast and the puff are silent beyond the cast cue every spell has).
10. **Voice:** "ghost" and "ghosts" only, no aliases (see below).

### New player-facing strings (proposals for review)
- Spell name **Ghost**; the spoken word **ghost** ("CAST GHOST" on the card).
- Component **Ectoplasm** (the card, the pickup's label "Ectoplasm x3", the toasts "+3 Ectoplasm", "You have no Ectoplasm").
- Description (the requisition's spec sheet): **"You turn into a ghost for ten seconds: you walk through monsters, but their blows
  still land. Ghosts stop running from you."**
- No form text, banner or dispatch line. Dev only: `--haunt-demo ghost|ghost_wisp`, the warning "HauntDev: the player could not cast
  ghost (slot it: --spells ghost,...)".

### Voice
"ghost" is an ordinary English word, so the model needs no change: it is a hotword like every spell word (`Incantation.vocabulary`;
`data/pron_dict.txt` only vets custom trigger words). Measured with TTS (David + Zira; the GHOST note in Incantation's header):
- 13 of 13 deliberate clips (clean, rates -3 / +3 in both voices, "okay / please cast ghost", "cast ghost now", "cast ghosts",
  "cast ghost on me", 300 / 500 ms pauses) fire ghost and nothing else at 0.96-1.00, about 160-330 ms after the voice stops; no
  other spell's clip fires it.
- The look-alikes are heard as themselves and never cast: "host", "post", "toast", "most", "coast" ("cast host / post" fizzle as
  garbled, "cast coast / toast" as an unknown spell). **"goes" is heard as GHOST** in both voices (the hotword's pull): like "binds"
  for vines, a bare "goes" casts in chaos only, and "cast goes" would cast (nobody says it). Chatter that says it ("watch out for the
  ghost", "there's a ghost") casts in chaos only. David's bare "ghost" (no trigger) is sometimes cut to "GHO", so chaos cannot count
  on it (as his bare "vines"); "gho" is not aliased.
- The voice orders are untouched (`test_voice_orders`: 98 % of the order clips heard right in loose, no cast, no false order, no
  "<name> ghost"); no phantoms from idle noise (`test_voice_noise`); "summon ghost" is heard "SOMEONE GHOST" (the summon trigger's
  known weak spot, as "summon heal"), within the triggers' budget (`test_voice_triggers`).

### Tests
- `tests/test_spell_ghost.gd` (new, solo): the spell's row, word, component, prop, numbers and drops (the ghost about half the time,
  never a hellgate kind); the cast transforms the CASTER (aimed at a teammate, who is untouched) for 10 s at full power, the look on
  its model, a copy shows and drops it from the announced status; walking into a standing monster a plain hero bumps, a ghost-form
  hero walks through and out the far side with the monster never pushed, a monster's own separation leaves the ghost be (and pushes
  off a plain hero), a ghost (wisp) bumps it, teammates bump; a monster's strike still hits a ghost-form hero and its swing still hits
  the monster; it ends after its duration (the look with it), a weak cast lasts about 6 s, going down ends it; the cooldown (20 s, the
  second cast waits and spends nothing; 17.4 s held); a free ghost drifts beside a hero in ghost form instead of keeping away, shows
  clearly (the strong look) on a screen whose own hero is the ghost and not for another player's, and keeps away again once it ends.
- `tests/test_net_ghost.gd` (new, NetTest, `const PEERS := 3`, `off` and `coast`): board 9's heir contract, floor 1. c1 casts Ghost:
  c1's hero is a ghost on c1 and in the look there; the host shows it in ghost form, in the look, for the cast's time, and its
  monsters walk through it; c1 in a long ghost form while c2 joins: c2 (late) shows c1's hero in ghost form and in the look, with its
  time left, and its own hero not; c1's form ends on c1: the host and c2 drop it; no OWNER-write guard on any machine.
- Updated: `test_license_checkout`, `test_spell_slots` (twelve spells; Ectoplasm; mail can hold all twelve), `test_voice_incantation`
  (the trigger and twelve spells: thirteen cards, five rows), `test_monster_defs` (the wisp drops components), `test_voice_audio`
  (the ghost clips: the stems and the measured words).
- Run and passing: `test_spell_ghost`, `test_net_ghost` (off and coast), `test_net_contract`, `test_golden_floor` (not re-recorded),
  `test_haunted_contract`, `test_haunt`, `test_net_haunt` (off and coast), `test_spell_coffee`, `test_spell_revive`,
  `test_spell_tentacles`, `test_spell_basic`, `test_spell_damp`, `test_spell_teeth`, `test_spell_vines`, `test_chicken`,
  `test_spell_slots`, `test_license_checkout`, `test_ghost_look`, `test_haunt_look`, `test_gym`, `test_forms`, `test_main_menu`,
  `test_monster_defs`, `test_monster_models`, `test_daze`, `test_net_codec`, `test_voice_incantation`, the real-model voice tests
  `test_voice_audio`, `test_voice_orders`, `test_voice_triggers`, `test_voice_noise`, and the net tests `test_net_m4_casts`,
  `test_net_m6_late_join` (each off and coast). The full suite was not run.

### Not done in H7
- No crew (two-PC) play; the net test covers the cast, the look on every screen, the walk-through on the host and the late join.
- No sound of its own; the look and the clear ghosts were judged on stills at the game camera (`ghost_form_game/`), not in play.
- Ghost mode after death (the user's later big build) and evicting a ghost without breaking its host (deferred) are not built.
- The H3 decision still open: whether Heal raises zombies.
