# Networking: lag management for online co-op

Status: **plan**, 2026-10-17. Option A below is the chosen architecture **[decided]**. There's no
transport yet. The authority declarations and their test are built and enforced now (see "Keeping
authority straight").
Numbers marked *(tunable)* are starting points to be set by measurement.

> **North star:** [`north-star.md`](north-star.md). "Overcooked with magic": the chaos comes from the
> players. Online play must feel as good at coast-to-coast latency as it does on one PC. Cheating is
> **not** a concern (friends only), and that is what makes the plan below possible.

## The requirement
- 2-4 players, one of them hosting, over Steam (GodotSteam).
- Coast-to-coast US: plan for **80-120 ms RTT** through Steam Datagram Relay, plus jitter and 1-2%
  loss. Valve publishes no relay overhead figure, so measure it before tuning anything.
- "Feels great" means: your own hero never waits on the network, what you dodged on your screen does
  not hit you, and a heal aimed at a friend lands on that friend.

## What went wrong in Bridge to Friendship
Its post-mortem (that repo's `design_ideas/netcode_assessment.md`, `physics_and_authority.md`, git log)
gives five lessons, and one more turned up during this research.

1. **Reliable snapshots by accident.** GodotSteam's `SteamMultiplayerPeer` maps
   `TRANSFER_MODE_UNRELIABLE_ORDERED` to `k_nSteamNetworkingSend_Reliable` (source comment: "No
   equivalent"). Bridge sent its 60 Hz snapshots and its inputs as `unreliable_ordered` RPCs, so on
   Steam both were **reliable**: one lost packet stalls every later snapshot for a round trip, and the
   backlog grows. Its latency tests ran on ENet, where `unreliable_ordered` really is unreliable, so
   they never saw this. Snapshots were also up to 2.5× the MTU, so 1% link loss became about 3%
   snapshot loss. This is a likely contributor to "pretty poor" coast-to-coast play and "worse over
   time", not a proven sole cause.
2. **Prediction islands.** The client predicted its own body ahead of the host and drew everyone else
   from the newest snapshot. A fast verb aimed at a body several metres out of date always
   mispredicts. Interpolation doesn't fix that, because an interpolated body is old on purpose.
3. **Engine state you can't rewind.** Platform carry and `is_on_floor` can't be replayed, so a
   predicted rider drifted on every tick.
4. **Host-only state.** Rescue progress, the countdown, the bus, the seeds and hearts each existed only
   on the host until someone noticed.
5. **The infrastructure came last.** The interpolation buffer, the ongoing clock sync, RTT telemetry and
   a two-way lossy link simulator were planned and never finished. Tests passed under perfect network
   conditions.
6. **Diagnosis by reading code was wrong three times.** Each real cause was found by measuring the
   specific scenario.

## What Cast already has going for it
- **No physics bodies.** Terrain and actors are kinematic on a hex heightfield (`Actor.move`). There is
  no engine-internal state that can't be rewound or replayed.
- **Shoves are scripted.** `Actor.shove(dir, distance, source)` is a short kinematic slide with fixed
  rules, so it can travel as a message and be applied by whoever owns the actor.
- **Voice already hides latency.** Speech takes 360-480 ms from the end of the utterance to the cast.
  One-way network time (about 50 ms) is a small fraction of that, and nobody can tell when within the
  utterance a spell "should" have fired.
- **Monster attacks are telegraphed.** Brute 0.9 s, archer 0.5 s, grunt 0.35 s, swarmer 0.3 s
  (lengthened from 0.15 s on 2026-10-18 so it can be dodged on any machine).
- **Aim snaps to a teammate.** `SpellBook.snap_hero` already knows *who* a support spell is for, so the
  network can send an id instead of a point.
- **It's co-op.** Peers can disagree for 100 ms about a near miss and nobody minds, as long as each
  player's own experience is fair to them.

## The options

| | Option | Your hero | Contacts and hits | Cost | Verdict |
|---|---|---|---|---|---|
| **A** | **Owner authority**: each machine owns its hero, the host owns monsters and hazards, and cross-owner effects travel as messages | Instant, never corrected | The victim decides, so disagreements are near misses and nobody gets rubber-banded | Lowest. No rollback, no determinism | **Chosen** |
| B | **Host authority with client prediction** (Bridge's model, done properly) | Instant, corrected on mispredict | Mispredicts at every contact with something that isn't predicted | Medium-high. Re-runnable movement, reconciliation, smoothing | What failed last time |
| C | **A, plus extrapolated remotes** near you | Instant | Remotes look current but overshoot on stops and shoves | A + dead reckoning + error decay | A later upgrade if A's remotes feel late |
| D | **Predict everything** (Rocket League style) | Instant | Best contact feel | Re-simulate every nearby monster 6-10 ticks per correction, in GDScript | Too expensive for packs of monsters |
| E | **Deterministic lockstep or rollback** (GGPO) | Delayed by input delay, or rolled back | Perfectly consistent | Bit-exact determinism; MK/Injustice spent 7-8 man-years switching | No |

Precedent for each:
- **A:** Destiny lets "each player determine how their own movements and abilities play out". Risk of
  Rain Returns made "most enemy attacks client authoritative" after Risk of Rain 2's "dodged on my screen
  and still got hit". Vampire Survivors' online co-op tolerates "a fairly wide margin of desync".
  Fiedler's VR physics demo resolves cross-owner contact by handing authority to whoever touches an
  object.
- **B:** Path of Exile's Predictive mode. GGG calls prediction "mandatory" for ARPGs but says it leaves
  you "slightly out-of-sync almost all of the time", and that other ARPGs avoid desync by making the
  simulation lenient.
- **E:** Path of Exile's Lockstep mode. GGG says Predictive is "probably the best choice" above 100 ms,
  which is exactly our range.

## The plan: option A

### Who owns what
| Thing | Owner | How others see it |
|---|---|---|
| Each human's hero: position, facing, climbing, HP, shoved/staggered state, slots, cooldowns | That player's machine | Interpolated (below) |
| Monsters, hellgates, spawns, AI allies, drops, employees | Host | Interpolated |
| Rebar's boulder, Gasket's spin, tentacles, corn, teeth | Whoever cast or used it; its motion is a pure function of `(params, start_tick)` | Every machine computes the same motion from the shared clock. Nothing streams |
| Contract state: objectives, damage bill, elevator, floor, pay | Host | Reliable events |
| The map | Seed from the host; every machine builds it | Identical by construction (add a checksum test) |

### Rules for effects that cross owners
1. **The victim decides about its own hero.** A monster's swing, a projectile, an AoE or a shove that
   might hit *your* hero is tested on *your* machine against where you are. You send the result (damage
   taken, shove applied) to the host, which forwards it. What you dodged did not hit you.
2. **The attacker decides about monsters.** Your melee arc, arrow or fireball is tested on your machine
   against the monsters as you see them. You send `hit(monster_id, damage, shove)` and the host applies
   it. Shoves on monsters run on the host from the host's current position.
3. **Support spells target an id.** When aim snaps to a teammate, send `cast(spell, power, target_id)`.
   The effect lands on that hero wherever their owner has them. No rewind is needed. Only a point-aimed
   AoE sends a position.
4. **Friendly fire is the victim deciding.** Your corn bomb lands at a point. Each machine tests its own
   hero against the blast, and the host tests monsters and allies. A teammate who sidestepped on their
   screen is fine; that is the feel we want.
5. **Shoves on another player are a request.** `shove(target_id, dir, distance, source)` goes to the
   target's owner, which runs `Actor.shove` locally. On the attacker's screen the shove starts about half
   an RTT late, which a 0.2-0.35 s ease-out slide hides.
6. **Player-to-player bodies are soft.** Each machine separates only *its own* hero from the others, at a
   capped speed. Nobody pushes a remote body, so there's no tug-of-war. Bumping into each other stays
   comic.
7. **One-shot decisions go reliably; continuous motion goes unreliably.** Casts, hits, deaths, pickups,
   spawns and objectives are reliable events. Hero and monster poses are unreliable snapshots, newest
   wins.

### Spells: show it now, resolve it on a short delay
- When speech recognition returns a spell, the caster's machine immediately plays the cast animation,
  sound and the start of the VFX, and sends `cast(spell, power, target, cast_tick)` at the same moment.
- Each spell gets a **150-250 ms** *(tunable)* travel, charge or drop visual before its gameplay effect
  lands. The cast reaches every peer within that window, so everyone sees it land at the same time.
  Corn already falls from the sky; fireball already travels.
- Cosmetics (sparks, particles, screen shake) are local and never corrected. Gameplay (damage, heal,
  armor, shove) follows the ownership rules above.
- Chorus casts (voice-mechanic.md §4) compare local voice-onset ticks on the synced clock, not arrival
  times.

### Monsters chasing non-host players
The host sees a client's hero about half an RTT plus the buffer late, so its monsters chase a slightly
stale position. Helldivers 2 shipped this and its enemies "had trouble attacking non-host players";
when they fixed tracking, everyone got hit hard. With rule 1 the *hit* is fair however the monster
aimed. The host should still aim at each hero's latest received position plus velocity × one-way
latency (a small lead), so monsters pressure every player equally. Measure hits taken per player per
minute, host vs clients, and keep them level.

## Day-one infrastructure (build before any gameplay sync)
1. **Transport settings.** `SteamMultiplayerPeer` via lobbies, with `no_nagle = true`. **Never use
   `unreliable_ordered` on the Steam peer.** Use `unreliable` with our own sequence numbers for motion,
   and `reliable` on a separate channel for events. Add a test that fails if any `@rpc` declares
   `unreliable_ordered`.
2. **Our own snapshot packing.** No `MultiplayerSynchronizer` for monsters (a node state over 1350
   bytes is silently not sent, and there's no interpolation or tick stamp). One packed, quantized
   message per peer per send, under about **1.2 KB** *(tunable)*, sent via `send_bytes`. Godot Variants
   cost 8 bytes even for a bool, so pack by hand.
3. **Rates.** 60 Hz simulation, **30 Hz** sends *(tunable)*.
4. **Clock.** Ongoing NTP-style sync (offset, RTT, jitter), adjusted by stretching the clock rather than
   jumping it. Every message carries a tick. Bridge adopted the host tick once and drifted.
5. **Interpolation buffer.** Remotes render about **100 ms** *(tunable: about 3 send intervals plus
   jitter)* behind, using Hermite interpolation (send position and velocity). Snaps and teleports call
   `reset_physics_interpolation()`.
6. **A lossy link in both directions, from the first test.** Steam's `FakePacketLag_Send/Recv`,
   `FakePacketLoss_*` and `FakePacketJitter_*` config values set through GodotSteam (the jitter enums may
   need their raw ints, 53-58). A "coast" preset of 45 ms each way, ±15 ms jitter and 1.5% loss
   *(tunable)*. ENet tests do not exercise the Steam peer's send-mode mapping, so the Steam path needs its
   own run.
7. **Telemetry.** Per peer once a second: RTT, connection quality, jitter (computed ourselves; Steam's
   `getConnectionRealTimeStatus` doesn't report it), bytes per second, pending reliable bytes, and hits
   taken. All of it goes in a passive log like `voice_log.csv`. Playtest data stays passive: no tester
   keys and no review screens.
8. **A "does a client have this?" checklist** in every system's review: is it owned, is it replicated,
   and how does a late joiner get it.

## Keeping authority straight as content grows
Content gets added faster than anyone re-reads this doc, so the rules live in code and a test enforces
them. Option A's silent failure, a machine writing state it doesn't own, is the same one Photon Fusion
warns "can lead to a permanent desynchronization". Engines that enforce it (Unity Netcode throws on an
unauthorized write) avoid that; engines that rely on convention (Unreal's `HasAuthority()`) don't. We
enforce it.

### Five layers
| Layer | What it is | Status |
|---|---|---|
| **1. Declarations** | Every class with gameplay state has `net_fields() -> {var: Net.KIND}` covering **every** script var. The kinds are in `scripts/net/net.gd`. | **Built** |
| **2. Lint** | `tests/test_net_contract.gd` scans `scripts/` for patterns that break option A. | **Built** |
| **3. Verbs** | Another entity changes only through `apply_damage`, `heal`, `shove`, `set_modifier`, `die`, spawn/despawn and pickup. Once `Net` exists, each verb applies the change if this machine owns the target and otherwise sends a request to the owner. | **Built** (M3/M4): a verb on a copy is a request to its owner (`Net.route_hit` / `route_shove` / `route_modifier`) |
| **4. Hit resolution in `Combat`** | `Combat.melee_arc`, `explode` and projectiles run on every machine, but each one applies hits only to targets it resolves: the hero's owner for heroes, the attacker's machine for everything else. Content that uses `Combat.*` gets the rules for free. | **Built** (M4): `Net.resolves_hit` / `Net.resolves`; test_net_contract checks area loops |
| **5. Runtime guards and agreement tests** | In debug builds, a write to an `OWNER` field on a machine that doesn't own the entity raises a script error, which fails tests. Two-peer headless scenarios with Steam fake lag assert that every peer agrees on HP, deaths and objectives. | **Built** (M4): `Net.guard_write` on a copy's `hp`/`dead`; `test_net_m4_*` |

### The four kinds (`Net`)
| Kind | Meaning | Examples |
|---|---|---|
| `SPAWN` | Fixed when the thing is created (spawn or cast event, or the seed). Same everywhere, never streamed | `team`, `max_hp`, a projectile's direction, `ContractRun` |
| `OWNER` | The owner writes it and everyone else receives it | `hp`, `dead`, `facing`, armor modifiers, a windup others must see |
| `PRIVATE` | The owner's working state. Not replicated; nobody else uses it for gameplay | AI timers, shove-slide internals, input buffers |
| `LOCAL` | Every machine keeps its own copy: presentation, or recomputed from `OWNER`/`SPAWN` state and `GameWorld.time` | model nodes, bob phase, a scheduled effect's current position |

A player owns their hero; the host owns everything else. Position and rotation are `OWNER`.

### What the test enforces
`test_net_contract` fails when:
- **A var is undeclared.** The checked classes are every `Actor` subclass (found automatically), every
  script that defines `net_fields()`, and the `NET_SCRIPTS` list in the test (gameplay classes that
  aren't actors).
- **A declaration is stale:** it names a var that no longer exists.
- **`unreliable_ordered`** appears anywhere. GodotSteam sends it reliably.
- **Network calls appear outside `scripts/net/`:** `@rpc`, `rpc(`, `send_bytes`, `multiplayer_peer`.
- **`MultiplayerSynchronizer` or `MultiplayerSpawner`** appears anywhere.
- **Global randomness:** `randf()`, `randi()` and the like. Gameplay rolls use `GameWorld.rng` or a
  generator seeded from the run. Looks use `GameWorld.fx_rng`.
- **`GameWorld.rng` appears in presentation folders:** `scripts/fx`, `art`, `ui` and `world/grime`.
- **Code writes another actor's `.hp` or `.dead`** instead of calling a verb.

Every allowlist entry carries a reason. Adding one is a design decision, not a way to get a test to pass.

### Randomness
- `GameWorld.rng` is `PRIVATE`: each owner rolls its own and sends the **result**, never the roll.
- Generation (map, site, contract, themes, grime) uses `RandomNumberGenerator`s seeded from the run, so
  every machine builds the same thing.
- `GameWorld.fx_rng` and the effects' own generators are cosmetic. They must never decide anything a
  test or another player could notice.

### Shapes for new content
Make new content one of these four shapes. If it fits none of them, design its networking before
building it.

| Shape | Examples | What it needs |
|---|---|---|
| **Scheduled effect**: one broadcast, then every machine computes it from `(SPAWN params, start time)` | corn, tentacles, boulder, fireball, arrows, Gasket's spin, a damp's lava crust (terrain on a schedule) | Params `SPAWN`, motion `LOCAL`, hits through `Combat` |
| **Owned actor** | heroes, monsters, employees, the Chicken spell's chickens (host-owned: the cast lands everywhere, the host spawns them) | `net_fields()`, changes through verbs. A host-owned actor spawned during play by a cast or an effect is a **runtime actor**: one `NetWorldCodec.RUNTIME_ACTORS` entry (its `world.spawn` kind, group and codec fields) and `net_read` / `net_write` / `make_shown` on the class |
| **Host-arbitrated world object** | pickups, doors, elevator, priced props, explosive props (their blast is a scheduled effect at the host's fuse end: `hazards.md`) | Host-owned. Players request; the host grants with a reliable event. The class implements the **net-object contract** (`NetObjects`): `net_link`, `net_event`, and as needed `net_request`, `late_join_state` / `apply_late_join`, `net_order` (not an Actor) |
| **Cosmetic** | debris, sparks, grime, decor animation | Nothing: local only, `fx_rng` |

### New-content checklist
Use this in every spec and review that adds content:
1. Which shape is it, and who owns it?
2. Is every new var in `net_fields()`, with the kind that's actually right? An `OWNER` that should be
   `PRIVATE` costs bandwidth; a `PRIVATE` that should be `OWNER` desyncs.
3. Does it change other entities only through verbs, and resolve hits only through `Combat`?
4. Who rolls its randomness?
5. Could its motion be a function of `(params, start time)` rather than streamed?
6. What is cosmetic, and what is gameplay?
7. What does a player who joins mid-floor see?
   - An effect that runs from a host-arbitrated object's moment (the live wire from its panel's break) takes that moment from
     the object's event on the shared clock (`obj.break {t, by}`: `PricedProp.broke_at`), never from when the event arrived,
     and a late joiner catches up from it without replaying what is past (`breaks`, `PricedProp.break_synced`).
   - Spawn data that is not in the map, the plan or the spawn table's position (a gator's home region, bask spots and seed)
     goes in the floor checksum through the actor's `net_spawn_text()` (`NetFloor.spawn_text_of`).
   - TERRAIN THAT CHANGES AT RUN TIME (a lava cave: its lava leaves the map once the floor runs, a damp's crust comes back for
     8 s): every machine changes its own `HexMap` from what it already has (the seed, the casts' shared start times, the
     clock), through `HexMap.remove_cell` / `set_cell` (never `cells.erase`: the wall-face cache), the same cells at the same
     shared moment; the floor checksum's map text must not depend on it (`NetFloor` skips `HexMap.lava`, the record is its
     own `cave=` line); a body the change strands gets a verb (`Actor.lose_ground`) from the machine that resolves it; and a
     late joiner gets what is live (the crust sources, on the shared clock: `LavaField.late_join_state`, the game's part of
     `join.snapshot`). Nothing in `scripts/net/` names the class.
8. Which two-peer scenario will cover it, once those exist?
9. If it is a host-arbitrated object, it implements the net-object contract on its own class (`NetObjects`' header has the
   full list; nothing in `scripts/net/` names the class):
   - `net_link(objects, id)`: the host connects the object's signals to the `obj.*` events they become
     (`objects.link`, `objects.tell`, `objects.count`);
   - `net_event(kind, data, objects)`: a client applies those events to its copy;
   - `net_request(what, data, peer, objects)`: the host decides a client's `obj.req` about it, once;
   - `late_join_state(objects, id)` / `apply_late_join(section, row, objects)`: its rows of a late joiner's snapshot;
   - not an Actor: `net_order()` places its net id after the actors (`NetFloor`), and `net_make_copy()` if a client's copy
     must keep its physics. A copy with `net_tick` / `net_contacts` gets them from `NetObjects`.
   Then its `NetEvents.WORLD_CARRIES` and `LATE_JOIN` entries, and `test_net_contract`'s `REPLICATED`.
   - made during play by the host (not built from the seed: a goo imp's ball and patch): a `NetObjects.RUNTIME_OBJECTS` entry,
     `net_spawn_row(objects)` and a static `net_copy(row, objects)`; its maker calls `Net.announce(node)` on the host (`obj.new`),
     and a late joiner's rows go in the section `new` (goo-imp.md, "As built").
10. If it is a runtime actor (host-owned, spawned during play, not by a gate), it is a `NetWorldCodec.RUNTIME_ACTORS` entry and
   implements `net_read(st)` (its mode, telegraph and extra slots), `net_write(st)`, `net_tick(delta)` and
   `static make_shown(at)`; `NetWorld` streams it as a monster-format entry on the one runtime track. `test_net_contract`
   holds its OWNER vars to the entry's fields.

### Known gaps, found while writing the declarations (2026-10-17)
The declarations pass, but today's solo code does these things directly. Each one becomes a message
or a `Combat` resolver call when the `Net` layer is built:
- **Spells and hazards hit every actor in range.** `Tentacles._burst`, `CornStrike` (through
  `Combat.explode`) and `BowlBoulder._check_hits` call `apply_damage`/`shove` on every actor in range,
  heroes included. If every machine runs them, a remote hero gets hit once per machine. These need the
  victim-decides path (layer 4). `Hellgate._fire_shove` shoving heroes from the host is the same case.
- **`ArmorZone._apply`** calls `set_modifier` on every friendly hero, but `_modifiers` is `OWNER`. Each
  hero's owner has to apply its own armor.
- **`Hero._spin`** shoves teammates directly. That should be a shove request to each teammate's owner.
- **`PricedProp`** reads and writes the shoved actor's private slide state (`_slide_t`, `_coast`,
  `_slide_dist`, `_src_ref`) to stop it and price the damage. That needs a message to the slider's
  owner, plus the culprit's id sent with each prop hit.
- **Pickups.** `ComponentPickup` writes `hero.swap_candidate` and consumes charges on the collecting
  machine, and `Hero.swap_in_pickup` drops a pickup from a player's machine. Pickups are host-owned:
  collects and drops become requests the host grants, which also settles two players grabbing at once.
- **`ContractSession.save_carry` / `apply_carry`** read and write every hero's `hp`/`dead`. Each owner
  applies its own carried HP, and the host keeps the record.
- **Scheduled effects start at their own `_ready`.** `ArmorZone`, `CornStrike` and `Tentacles` take
  their start time from `GameWorld.time` in `_ready`. They should take the cast's timestamp as a
  `SPAWN` parameter, so every machine runs the same schedule.
- **Burning** (added on main the same day). `Burning.on_blast` rolls ignition for every actor in the
  blast on the caster's machine. Each actor's owner should roll its own ignition and tick its own fire,
  as `Burning.net_fields()` already assumes.
- **Vines, Damp, Coffee** (added 2026-10-17) call `set_modifier` / `Burning.soak` through area helpers
  (`Combat.modify_radius`, `Wet.douse_in_radius`, `Coffee.cast`) on every machine, so each target's owner has to apply
  its own. `Actor.shove` now also asks `Damp.slide_mult` (a wet floor) and refuses while rooted; both read state every
  machine has from the cast event / the replicated modifier. See M4 in `networking-build-plan.md`.
- **Mail packages** break on any hit from any machine and roll their contents on the spot. The host
  should roll the contents and pay the crypto; a break from a player's machine becomes a "hit package
  X" request.
- **Employee mood is computed on the host.** `_hero_near`/`_scared` are `LOCAL` (they only drive the
  tag, bubble and pose), but today `_scan()` computes them, and `_scan()` will run only on the host.
  Each screen needs its own recompute.

## Open risks
- ~~**Swarmers' 0.15 s windup**~~ Decided 2026-10-18 (user, option A): `Swarmer.WINDUP` is 0.3 s.
- **Real relay RTT is unknown.** Players report bad SDR routes in other games. Measure with
  `estimatePingTimeBetweenTwoLocations` and the in-game telemetry before tuning buffers.
- **Host upload.** Four players and a monster pack with 30 Hz snapshots should fit in tens of KB/s.
  Check it with telemetry, since Magicka and Overcooked both drew "swap the host" folklore.
- **Leaving.** A client that leaves takes its hero with it; the host leaving ends the session. Host
  migration is out of scope.
- **Remotes look about 150 ms old.** If aiming at a moving teammate or dodging alongside one feels late,
  option C (extrapolate nearby remotes with error decay) is the planned upgrade.

## Sources
- Bridge to Friendship: `scratch/bridge-to-friendship`, commits a573b82, 823a100, ef19444, e19d9c5, 5cab202, 68b4367.
- GodotSteam `godotsteam_multiplayer_peer.cpp`, `_get_steam_packet_flags`: https://codeberg.org/godotsteam/godotsteam
- Path of Exile on prediction and desync: https://www.pathofexile.com/forum/view-thread/889669 , lockstep: https://www.pathofexile.com/forum/view-thread/1262596
- Risk of Rain Returns 1.0.4 patch notes: https://support.gearboxsoftware.com/hc/en-us/articles/23066772742925 , RoR2 victim-side fix: https://thunderstore.io/package/Goorakh/PizzaClientLagFix/
- Helldivers 2 enemy tracking fix: https://mein-mmo.de/helldivers-2-bugfix-macht-es-schlimmer/
- Vampire Survivors online co-op: https://coherence.io/blog/tradecraft/vampire-survivors-online-coop-case-study
- Destiny 2 networking: https://www.bungie.net/7/de/News/article/45919
- Fiedler, networked physics in VR (interaction authority): https://gafferongames.com/post/networked_physics_in_virtual_reality/ , snapshot interpolation: https://gafferongames.com/post/snapshot_interpolation/
- Rocket League, "It IS Rocket Science" (prediction timelines): https://media.gdcvault.com/gdc2018/presentations/Cone_Jared_It_Is_Rocket.pdf
- Halo: Reach and Overwatch netcode summaries: https://edgegap.com/blog/game-backend-deep-dive-halo-reach-netcode-host-migration , https://edgegap.com/blog/game-backend-deep-dive-overwatch-2016-netcode-architecture-rollback
- SnapNet netcode architectures: https://www.snapnet.dev/blog/netcode-architectures-part-3-snapshot-interpolation/
- Godot `SceneMultiplayer` / `MultiplayerSynchronizer`: https://docs.godotengine.org/en/latest/classes/class_scenemultiplayer.html
- Steam networking utils (fake lag, ping estimates): https://godotsteam.com/classes/networking_utils/ , https://partner.steamgames.com/doc/api/ISteamNetworkingUtils
- netfox (time sync, interpolation; an option for the clock and buffer): https://github.com/foxssake/netfox
