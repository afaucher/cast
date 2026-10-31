# Haunted contracts: build plan

Status: **[proposal]**, 2026-10-31. The design is `new-themes.md` ("Ghost house: haunted contracts"); this is the order to
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
