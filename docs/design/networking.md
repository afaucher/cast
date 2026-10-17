# Networking: lag management for online co-op

Status: **plan, nothing built**, 2026-10-17. Option A below is the chosen architecture **[decided]**.
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
- **Monster attacks are telegraphed.** Brute 0.9 s, archer 0.5 s, grunt 0.35 s. Swarmer 0.15 s is the
  exception (see open risks).
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

## Open risks
- **Swarmers' 0.15 s windup** is shorter than a remote player sees it (one-way plus buffer is about
  150 ms). Rule 1 keeps the hit fair, but the telegraph is invisible to clients. Lengthen it, or accept
  swarmers as undodgeable chip damage.
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
