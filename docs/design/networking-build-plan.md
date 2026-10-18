# Networking build plan: online co-op, step by step

Status: **M0, M1 and M2 built** 2026-10-17, **M3, M4 and M5 built** 2026-10-18, **M6 built** 2026-10-18 (see
[M0 as built](#m0-as-built-2026-10-17), [M1 as built](#m1-as-built-2026-10-17), [M2 as built](#m2-as-built-2026-10-17),
[M3 as built](#m3-as-built-2026-10-18), [M4 as built](#m4-as-built-2026-10-18), [M5 as built](#m5-as-built-2026-10-18) and
[M6 as built](#m6-as-built-2026-10-18) after the milestones); M7 is still the plan. The architecture is fixed by
[`networking.md`](networking.md) (option A: each player's machine owns that player's hero, and the host owns
everything else). This doc is about the **order of work**: what to port from Bridge to Friendship, the milestones,
how they get tested, and what is still the user's call.

**Decided by the user:**
- Host/Join work the way they do in Bridge. Join takes the **first** lobby Steam returns for the game key, there is
  no server browser, and Steam invites join directly.
- **Joining mid-contract is in.** A joiner arrives on any floor and **replaces one of the AI crew** with their own
  character, taking over that hero's HP, spells, components and anything it carries.
- Testing is **local only** for now: several instances on one machine (ENet on localhost) for automated and agent
  tests, plus a manual checklist for real Steam play.
- Voice: each player speaks into their own mic, recognition runs on that player's machine, and a cast travels as an
  event.
- **Two players may use the same character.** Duplicates are fine (two Wicks).
- **At most 3 players for now**, one per crew slot. When no AI is left to replace, the crew is full and a join is
  refused with "Crew is full".
- **Character select is out of scope.** Everyone plays the default character (Wick today), but **the protocol carries
  each player's character id** (in the hello message and the roster), so a future character select only has to set
  it (`MenuBackdrop.featured_hero` is the local source).

**Proposed, not yet confirmed:** the main menu below, everything marked *(proposal)*, and the open questions in §5.

---

## 0. Ground rules (they apply to every milestone)
- **The networking rules in Cast's `AGENTS.md` apply.** The `scratch/AGENTS.md` guardrails 1-3 (host-only
  simulation, `receive_perceived_state`, `intersect_ray` scanning) belong to a different project. Guardrail 4 (run the
  tests) applies.
- **All net code lives in `scripts/net/`**: `@rpc`, `rpc(`, `send_bytes`, `multiplayer_peer`, and also any
  `Engine.get_singleton("Steam")`. Gameplay code may only *ask*: `Net.is_host()`, `Net.owns(node)`, and
  `Net.request(...)`/verbs. The new lint in M0 enforces the Steam part.
- **Never `unreliable_ordered`, `MultiplayerSynchronizer` or `MultiplayerSpawner`.** Motion is `unreliable` plus our
  own sequence numbers, sent with `send_bytes`. Events are `reliable`.
- **Solo stays the default path.** With no session, `Net.owns()` is true for everything and `Net.is_host()` is true,
  so the 58 existing tests must pass **unchanged** after every milestone.
- **RPC endpoints live in autoloads**, never in `game.tscn`. Every floor change is `reload_current_scene()`, and an
  RPC needs the same node path on every peer, so it has to live at a path that survives the reload
  (`/root/Session/...`).

## 1. What to port from Bridge to Friendship

GodotSteam is **the same build** in both projects: the GDExtension 4.17.1 (Cast's `addons/godotsteam/win64` was
copied from Bridge, and `SteamMultiplayerPeer` is inside that DLL). The differences are around the API, not in it:

| Difference | Consequence for Cast |
|---|---|
| Godot 4.4.1 → **4.7** | The extension's `compatibility_minimum` is 4.4 and it already loads in 4.7 (the HUD name works). Re-verify `SteamMultiplayerPeer` there in M0. |
| Bridge names `Steam` and `SteamMultiplayerPeer` as globals | Those are **parse errors** when the extension is missing, as in a worktree or any machine without the untracked binaries. Cast keeps `SteamIdentity`'s pattern: `Engine.get_singleton("Steam")`, `ClassDB.instantiate("SteamMultiplayerPeer")`, `ClassDB.class_get_integer_constant("Steam", "LOBBY_TYPE_PUBLIC")`, and `steam.connect("lobby_created", ...)` with a string signal name. |
| Bridge ships every platform | Cast ships **win64 only** for now. |
| Steam is initialised once in Bridge's `SteamManager` | `SteamIdentity` already initialises it for the HUD. Merge the two so there is **one** init per process. |

| Bridge file | Port | Changes for Cast |
|---|---|---|
| `scripts/net/steam_manager.gd` | **Nearly as-is** → `scripts/net/steam_lobby.gd` (absorbs `steam_identity.gd`) | The singleton access above. `LOBBY_GAME_KEY = "cast_licensed_sorcery"` (on app 480 Spacewar a short key collides). Lobby data: `game`, `version` (from `version.txt`, so mismatched builds never pair), `seats_free` and `state` (`board` / `job`). `request_lobby_list` filters on game key + version + `seats_free > 0`. `lobby_max_members = 3`. **New:** read `+connect_lobby <id>` from the command line, which is how an invite launches a game that wasn't running (Bridge only handled `join_requested` while running). Avatars: port in M7, not before. Keep `run_callbacks()` every frame. |
| `scripts/net/network_manager.gd` | **Nearly as-is** → `scripts/net/net_session.gd`, autoload `Session` | Same two transports (STEAM, ENET), same `peers`/`local_id()`/"wait for both sides" logic. The Steam peer gets `no_nagle = true`. Add `join_first()`, which runs Bridge's `main.gd` Join flow (list → first → join → peer) so the menu never touches Steam. Add a **disconnect reason** to `session_ended`. Add the crew roster (peer → seat → **character id** → Steam name), filled from each peer's `hello(version, name, character_id)`. |
| `scripts/app/main.gd` (Host / Join / Local) | **The flow only** | Cast's menu is `scripts/ui/main_menu.gd`, so the rows call `Session.host()` and `Session.join_first()`. "Local" disappears, since solo is hosting with nobody joining. Bridge's `--run-test` entry stays Cast's `Boot.route`. |
| `scripts/net/snapshot_delta.gd` | **Same contract, rewritten** | Keep the design: an id **manifest** plus changed entries, and a **keyframe** every N sends instead of acked baselines. Rewrite it over hand-packed bytes (`StreamPeerBuffer`, quantised) instead of Variant arrays. |
| `scripts/net/net_telemetry.gd` | **Nearly as-is** | Same idea: one CSV row per second per peer, clients' rows sent unreliably to the host, a gap counts as missing (never as zero). Columns from `networking.md` §7. **Drop the F4 "mark" key**: Cast's playtest data is passive (no mid-play keys, no review screens). |
| `scripts/debug/debug_settings.gd` link presets + `game_world.gd` `_sim_link_ticks`/`_sim_drops_packet` | **The idea, extended** → `scripts/net/net_link.gd` | Bridge delayed only inbound unreliable packets on clients, so the input path to the host was never simulated (its own post-mortem). Cast applies the link on **every process's inbound side**, which covers both directions, and delays reliable messages too (no loss on those). Presets: `off`, `coast` (45 ms each way, ±15 ms jitter, 1.5% loss), `rough`. |
| `scripts/test_support/net_harness.gd`, `tests/test_enet_loopback.gd`, `pinger.gd` | **The loopback test as-is; the world harness can't be ported** | The loopback test (two `SceneMultiplayer`s in one process via `set_multiplayer`) ports straight away as M0's transport test. Put `pinger.gd` under `tests/`, because the lint forbids `@rpc` in `scripts/` outside `scripts/net/`. Bridge's *world* harness needs a `GameWorld` per peer, but Cast's `GameWorld` and `Ledger` are **autoloads** and `game.gd` keeps static vars, so Cast tests worlds with **several processes** instead (§3). |
| `CLAUDE.md` "Multiplayer" notes | **Copy into Cast's `docs/ARCHITECTURE.md`** | `get_unique_id() == 1` doesn't mean host; the two ends become ready on different frames; `@rpc` mode is a security boundary; test over ENet. |

**Not ported:** the `unreliable_ordered` RPCs (`_submit_input`, `_apply_snapshot`); input prediction and
reconciliation (`_predicted`, `_pending_inputs`, the input inbox), because option A sends state, not input; the clock
adopted once (`_adopt_server_tick`); full snapshots at 60 Hz; game logic RPCs spread across a 6,800-line world
script; and host-only state such as Bridge's rescue progress and countdown.

### New files in `scripts/net/` *(proposal)*
`steam_lobby.gd`, `net_session.gd` (autoload `Session`), `net_wire.gd` (the event RPC and `send_bytes` with sequence
numbers), `net_link.gd`, `net_clock.gd`, `net_ids.gd` (net id registry), `net_codec.gd` (packing driven by
`net_fields()`), `net_snapshot.gd`, `net_interp.gd`, `net_events.gd` (event kinds and handlers), `net_telemetry.gd`,
`crew_flow.gd` (board → license → ready → floor barrier → seats), `seat_handover.gd`, `net_probe.gd` (the test
reporting channel). `Net` (`net.gd`) gains the static facade (`is_host`, `owns`, `request`).

### Main menu *(proposal)*
| Row | Does |
|---|---|
| **01 Start a job** · *crew can join* | Hosts: creates the Steam lobby and opens the job board. Solo is just this with nobody joining. Without Steam, it is an offline session and the status line says "Steam not running: solo only". |
| **02 Join a crew** · *first crew hiring* | `Session.join_first()`: the first lobby with a free seat for this game key and version. It may be on the board or mid-contract. "No crew is hiring" if the list is empty. Greyed out without Steam. |
| 03 Voice setup · 04 Settings · 05 Quit | As today. |

Dev flags (not in the menu): `--net enet --host [--port P]`, `--net enet --join 127.0.0.1:P`,
`--net-link coast|rough`, `--seat N`.

---

## 2. Milestones in build order

Each step below is one agent session, and each ends with the full suite green. **Risk** marks the ones most likely
to overrun or to need a design change.

### M0 Transport and lobby *(2 sessions)*
**M0a Transport, lobby, menu.** `steam_lobby.gd` and `net_session.gd` as above, the menu rows, the ENet dev
flags, the **hello handshake** (`version`, Steam name, `character_id`: the default character for now; the host answers
with the seat or a refusal: "Crew is full", "Different build"), a crew roster strip on the job board (names, seats
and characters), and the disconnect story:
- a client leaves: the host drops the client from the roster (heroes come in M2);
- the host leaves: clients get "The host clocked out" and go back to the main menu, and the Steam lobby is left;
- a join fails, or the versions differ: the menu status line says why.

Lint: `Engine.get_singleton("Steam")` / `ClassDB...Steam` only inside `scripts/net/`.
*Done when:* `test_enet_loopback` (ported) passes; `test_net_session` (in one process: host, client, peer ids,
`local_id()` is 0 offline, the leave and host-gone signals) passes; and **`test_net_m0_crew`** (3 processes, §3)
shows every process listing the same 3-entry roster (name, seat, character id), a 4th client refused with "Crew is
full", and the clients back at the menu with the right reason after the host is killed.

**M0b Day-one infrastructure** (`networking.md` items 1, 4, 6, 7; build it before any gameplay sync).
`net_wire.gd`: one reliable event RPC (`@rpc("any_peer", "call_remote", "reliable")` on a channel of its own) and
unreliable `send_bytes` with a u16 sequence number and a tick header (stale or reordered packets are dropped).
`net_clock.gd`: NTP-style pings every 0.5 s, a min-RTT filter, and a slewed `host_time()`; clients slew
`GameWorld.time` toward it (it is already declared `OWNER`, host-written). `net_link.gd`. Telemetry rows.
The **multi-process harness** (§3).
*Done when:* `test_net_clock` holds client clock error under 5 ms (no link) and under 20 ms (`coast`) after 3 s,
with no backward jumps; `test_net_link` measures about 1.5% loss and the expected delay; and telemetry CSVs appear
for host and clients with RTT about 90 ms under `coast`.

### M1 Shared run *(2 sessions)* — built, see [M1 as built](#m1-as-built-2026-10-17)
**M1a Board, contract, seed.** The host rolls the board seed (the `global_random` allowlist entry for `game.gd`
already says this) and sends it. Every machine renders the same 3 offers from `ContractBoard.offers(seed)`. Only the
host picks; clients see the host's highlighted card. The pick sends `contract(seed, k)`, and each machine builds the
`ContractRun` (SPAWN).
**M1b License, ready, floor build.** Each player fills in their own **license checkout** (`SpellPicker`) and the host
learns each crew member's spells. Signing the license is the **ready** step, and the host starts floor 1 once
everyone has signed. Every machine runs `DungeonGen` + `SiteBuilder` from the floor seed. Both are already seeded
from the run, so monsters, gates, employees, props and mail come out identical. `net_ids.gd` gives seed-built actors
ids in build order, and heroes get ids from their seats. A **floor checksum** (map cells, site plan, the spawn table
of kind/id/cell) is sent to the host, and a mismatch fails loudly instead of playing on a different map. Clients
build host-owned actors as **puppets** (`Net.owns()` false: no AI, no brain ticks). The van intro plays on each
machine from the floor start time.
*Done when:* **`test_net_m1_floor`** (3 processes, contracts 0-2 plus a `--contract` seed on floors 1-3) has
matching checksums; each process's roster has its own spells; and the single-process `test_net_puppets` passes: a
monster/employee/hellgate with `owns = false` run 120 frames with no change to any `PRIVATE` field.
*Playable:* everyone sees the same board, picks spells and stands on the same floor, frozen and unsynced.

### M2 Hero sync *(2 sessions)* — built, see [M2 as built](#m2-as-built-2026-10-17)
**M2a Owner-authoritative heroes.** Seats: the host takes seat 1, and a player who joins on the board takes the next
seat. Each human seat spawns that player's **character id** from the roster (Wick for everyone today, and duplicates
are fine). Unfilled seats stay **AI allies owned by the host** (Rebar, Gasket; `AllyBrain` runs only there). Every machine spawns all three heroes. The local hero keeps its
`PlayerController`; every other hero is a puppet. Each owner packs its hero's `OWNER` fields (`net_codec.gd`, driven
by `net_fields()`) at **30 Hz**, unreliable, to the host, and the host forwards them inside its own snapshot.
**No input crosses the wire**: E presses and casts are events (M4/M5). Rule 6: each machine separates only its own
hero from the others. Animation and pose come from replicated state.
**M2b Interpolation, and drops.** `net_interp.gd`: a buffer about 100 ms behind on `host_time()`, Hermite
interpolation with position and velocity, and `reset_physics_interpolation()` on teleports. **A player drops → the
AI takes the seat back** through `seat_handover` (the reverse of the M6 handover, built here because drops happen in
every playtest): the host takes the last received state, attaches `AllyBrain`, and the seat's original character
returns (decided, see §5). Floor carry gets keyed by **seat**, not `display_name`.
*Done when:* **`test_net_m2_walk`**: a client bot walks a scripted path. Under `off` and under `coast`, the host's
render of that hero stays within 0.35 units of where the client had it at the same `host_time - interp_delay`, with
no gap over 0.6 units in one frame. Each client sends under 3 KB/s. Then the client is killed, and its seat is
AI-driven on the host within 1 s at the same position.
*Playable:* **two or three players walk around the same floor together**, monsters frozen.

### M3 Host-owned world *(3 sessions)* — **Risk** — built, see [M3 as built](#m3-as-built-2026-10-18)
**M3a Monsters.** The host snapshot: an id manifest, changed entries, a keyframe every 15 sends, quantised
(position to a centimetre in i16, velocity in i8, facing in u8, HP in u16, a state/windup flags byte), **under 1.2 KB**.
Monster AI runs only on the host and aims at each hero's latest position plus velocity × one-way latency
(networking.md). Deaths, despawns and wind-up starts (the telegraph) are reliable events.
**M3b Hellgates, spawns, pickups.** A gate wave sends a spawn event carrying host-assigned ids (from 10000 up). Gate
closes. Component drops are host-rolled; **pickups** become requests (collect, swap, drop) that the host grants,
which settles two players grabbing at once (known gap: `ComponentPickup`, `Hero.swap_in_pickup`).
**M3c Employees, props, mail, crates.** Employee E presses go through the existing `Employee.request_follow` /
`request_wait` as a request event. Mood (`_hero_near`/`_scared`) is recomputed on each screen. Priced props, crates
and mail packages: a hit from any machine sends a "hit object X by culprit Y" request; the host breaks the object,
prices it, rolls mail contents and broadcasts the result (known gaps: mail packages, `PricedProp`).
*Done when:* **`test_net_m3_world`** (2 processes, `coast`): over 20 s of host-driven fighting with dev
`--spawn-near` monsters, the client's monster render error is under 0.5 units, the set of alive monsters agrees
within 250 ms of every death, and a hellgate's spawned imps exist on the client with the same ids.
`test_net_m3_objects`: both processes request the same pickup in the same frame and exactly one gets it; a broken
prop shows up on both Ledgers once. `test_net_contract` budget check: a worst-case floor-3 snapshot is under 1.2 KB.
*Playable:* players walk among live monsters that fight back (only on the host's hero until M4), and pick things up.

### M4 Spells and combat across owners *(3 sessions)* — **Risk (the biggest)** — built, see [M4 as built](#m4-as-built-2026-10-18)
**M4a Casts as events.** Voice recognition stays local, and a cast sends `cast(spell, power, target_id | point,
onset_host_time)`. The caster plays the start of the cast at once, and the gameplay effect lands **150-250 ms**
*(tunable)* later on every machine. Scheduled effects take their start time as a `SPAWN` parameter instead of reading
it in `_ready` (known gap: `ArmorZone`, `CornStrike`, `Tentacles`). Support spells target an id (`SpellBook.snap_hero`).
**M4b Hit and shove routing (layers 3 and 4).** A verb on a target you don't own becomes a request to its owner.
`Combat.melee_arc`/`explode`/`Projectile` apply hits only to targets this machine resolves: **the victim decides**
for heroes, **the attacker decides** for monsters. Monster swings against a client's hero resolve on that client
from the wind-up event. Shoves on another player are requests (`Hero._spin` hitting teammates, `Hellgate._fire_shove`).
`Burning`: each owner rolls its own ignition and ticks its own fire. `ArmorZone`: each hero's owner applies its own
modifier. `PricedProp` stops a slider through a message to the slider's owner.
**M4c Runtime guards and agreement (layer 5).** In debug builds, a write to an `OWNER` field on a non-owner raises
a script error. Agreement tests.
**New spells (vines, damp, coffee; built 2026-10-17 to fit this milestone).** Each is a **scheduled effect**: one cast
event, then every machine runs it from `SPAWN` params and a `start_time` stamp (`Vines` and `Damp` already take the
stamp as a `SPAWN` parameter and burst on the first frame if it is in the past; `ArmorZone`/`CornStrike`/`Tentacles`
still have to be moved to the same pattern). What each one does to *other* entities goes through verbs, applied by the
target's owner:
- **Vines** roots with `set_modifier("vines", 1, dur, STAT_ROOT)` through `Combat.modify_radius`: each machine runs the
  burst, and each target's owner applies and replicates its own root (`_modifiers` is `OWNER`). `Actor.shove`
  refuses while rooted, so a shove request that reaches the owner of a rooted hero is simply dropped there. The vines
  and the leg wraps are cosmetic.
- **Damp** soaks through `Wet.douse` -> `Burning.soak` (a status the target's owner applies; the soak end time is the
  owner's, like the fire). Fires are put out by each owner. **Puddles are cosmetic plus one factor:** which cells are wet
  is a pure function of (centre, radius, stamp), so no list is sent, and `Damp.slide_mult` scales a shove where *its
  owner* applies it (the shoved actor's machine), so every machine needs the damp field, which it has from the cast
  event. The Grime decals are cosmetic. Nothing about puddles is host-arbitrated.
- **Coffee** applies `coffee_move`/`coffee_rate` (and later the crash pair) as speed modifiers on each target's owner,
  where `Coffee` also runs the haste to crash schedule and the twitch (`GameWorld.rng` on the owner: a hero's machine
  for an AI-less player, the host for monsters and allies). The aim wobble is the local player's input (a sum of
  sines of the game clock, no rolls). Remote machines see only the replicated modifiers, enough to draw the steam.
- **Hit resolution gap, same as tentacles:** `Combat.modify_radius`/`each_in_radius` run on every machine today; at M4b
  they apply only to the targets that machine resolves (the owner for a hero, the host for everything else).
  `Burning.extinguish_in_radius` and `Wet.douse_in_radius` are the same kind of loop and move with them.

*Done when:* **`test_net_m4_casts`** (3 processes, `coast`): a corn strike cast by client A lands on all three within
one frame of the same `host_time`; a heal aimed at client B lands on B once; B standing in the blast is hit once (not
once per machine), and B sidestepping on its screen is not hit. **`test_net_m4_hits`**: client damage to a monster
reaches the host once; a brute's swing at client A is decided on A; HP, deaths and the damage bill agree on all
peers after 30 s of scripted fighting; and the debug guard fires in a negative test.
*Playable:* **the real game for two or three, on one floor**: fighting, casting at each other, shoving each other
into pits.

### M5 Contract flow *(2 sessions)* — **Risk (moderate)** — built, see [M5 as built](#m5-as-built-2026-10-18)
**M5a Floors and exits.** Using the elevator or the van is a **request**; the host arbitrates the first one and
broadcasts `floor_change(n, carry)` or `contract_end(reason)`. Each machine reloads the scene; a **load barrier**
(everyone builds, checksums and reports ready, then the host starts the floor clock) replaces the fade-in.
Followers ride the elevator via the host. Drop-offs, extraction and "crew incapacitated" are decided by the host from
every hero's replicated `dead`.
**M5b The shared invoice, the Ledger and pause.** The host's `Ledger` and `ContractSession` are authoritative; lines
reach clients as events (the ticker and tracker read a mirror). The host builds the invoice and sends the finished
dict. "Next contract" returns **everyone** to the board in the same lobby. **Pause online** (decided): with
another player present, Esc opens the menu **without** pausing the tree. **Anyone** can "Abandon contract", which
takes the whole crew back to the board. The elevator is **first to choose**: whoever picks a row first decides for
the crew. The elevator and van menus freeze only your own
hero (`_freeze` today stops the whole world). Solo keeps the real pause.
*Done when:* **`test_net_m5_contract`** (3 processes, `coast`, `--auto-elevator`-style bots): down to floor 2, then
3, then out; every process shows the same invoice dict; carried HP is per seat. A client's van clock-out on floor 1
ends it for everyone. Two players pressing E at the elevator in the same frame produce one floor change.
*Playable:* **a full contract online**, from the board to the invoice, for a crew that started together.

### M6 Join mid-contract and seat handover *(2 sessions)* — **Risk** — built, see [M6 as built](#m6-as-built-2026-10-18)
Its own milestone: it needs everything above, and it is the part the user decided most recently.
- **Which AI gets replaced** *(proposal)*: first an AI already playing the joiner's character, then the **living**
  AI with the most HP (tie: lower seat), and a downed AI only if none is alive. **No AI left → the join is refused
  with "Crew is full"** (decided; the lobby also stops listing itself at `seats_free = 0`). The joiner keeps their own
  character id even when another player already plays it (duplicates are decided fine).
- **The late-join world snapshot** (reliable, sent once, fragmented as needed). The joiner builds the floor from the
  seed exactly as in M1. The host then sends: `GameWorld.time`; the seed-built ids that are **gone** (dead monsters,
  closed gates, broken props and crates, opened mail, extracted or dead employees); a full keyframe of every surviving
  host-owned entity; replayed spawn events for runtime entities (gate spawns, pickups on the floor); employee
  follow/wait targets; the van (parked, arrival done, so the joiner skips the intro); the `ContractSession` state and
  every Ledger line so far; the other heroes' states. Active scheduled effects are skipped (they last under 2 s).
  Grime decals are cosmetic and missing (accepted).
- **The handover**, host-owned AI → joiner. The joiner shows "Clocking in…" while it builds; the seat stays AI until
  it reports ready. Then the host stops `AllyBrain` at tick T and sends `seat_handover(hero_id, peer, character,
  epoch+1, state)`. The state is position, facing, HP, dead, modifiers, burning, slots, charges, cooldowns, the held
  slot and followers. The hero node and **net id stay the same** (followers and targets keep working); its model and
  kit change to the joiner's character, at **full health** (decided: a joiner always arrives at 100% HP).
  Snapshots carry an **ownership epoch**, so everyone ignores stale states for that hero from the old owner. No
  license screen mid-contract: the joiner inherits the AI's spells.
- **Joining during a floor change** waits for the next load barrier and arrives with the new floor.
- **Leaving** is the M2b reverse handover. The lobby's `seats_free` is updated on every join and leave, so "Join a
  crew" only finds crews with an AI seat.
*Done when:* **`test_net_m6_late_join`** (host + 1 client start; at 15 s on floor 2, client 2 joins): client 2's
checksum and entity set match the host's, its gone-ids match, the Ledger totals are equal, and it controls the
replaced hero at the same position with the same HP fraction, spells and charges within 1 s of ready. Then client 2
leaves and the AI is back. Plus a negative case: with 3 players in, a 4th join gets "Crew is full" and nothing
changes on the floor.
*Playable:* drop-in, drop-out co-op.

### M7 Polish *(2 sessions)*
Voice debug per player (each panel shows only its own recognizer; casts in telemetry with onset and recognition
latency; `voice_log.csv` per machine, with the host collecting cast summary rows passively). Steam overlay invites:
`join_requested` mid-game ("Leave this job and join?"), `+connect_lobby`, and an "Invite crew" row
(`activateGameOverlayInviteDialog`). Avatars and names on the roster. The in-game **link simulator**: Settings >
Diagnostics "Simulate a long link" (off / coast / rough), set on the host and broadcast; on Steam it sets
`FakePacketLag_*` / `FakePacketLoss_*` / `FakePacketJitter_*` (raw enum ints 53-58 if GodotSteam lacks the names), on
ENet it uses `net_link.gd`. Swarmer windup decision (open risk in networking.md). Hits taken per player per minute,
host vs clients, in telemetry.
*Done when:* the manual Steam checklist (§3) passes once with two real machines.

### M0 as built (2026-10-17)
One session (M0a and M0b together). Everything in M0's "done when" passes except the clock's 5 ms target with no
link, which polling makes unreachable (see Clock); the test holds 10 ms.

**Files.** `scripts/net/`: `net_session.gd` (autoload **Session**, `NetSession`), `net_wire.gd` (child
`Session/Wire`), `net_link.gd`, `net_clock.gd`, `net_telemetry.gd`, `steam_lobby.gd` (child `Session/Lobby`),
`steam_identity.gd` (kept: still the one Steam init, now also hands the singleton to the others), `net.gd` (gained
`Net.is_host()`, `Net.online()`, `Net.session()`). Tests: `test_enet_loopback`, `test_net_session`, `test_net_m0_crew`,
`test_net_link`, `test_net_clock`, plus `tests/pinger.gd`, `scripts/test_support/net_test.gd` (`NetTest`) and new checks in
`test_net_contract` and `test_main_menu`. UI: `main_menu.gd` (rows, status line, crew view), `job_board.gd` (crew strip).
`boot.gd`: online flags added to `MENU_FLAGS`. `project.godot`: the `Session` autoload. `run.ps1 -Crew N [-Link L]`.
Not built yet (later milestones): `net_ids`, `net_codec`, `net_snapshot`, `net_interp`, `net_events`, `crew_flow`,
`seat_handover`, `Net.owns()`/`Net.request()`. `net_probe.gd` became `NetTest`'s report/command events instead.

**Ported from Bridge, and what changed.**
| Bridge | Cast | Changed |
|---|---|---|
| `steam_manager.gd` | `steam_lobby.gd` | Steam reached through `SteamIdentity.steam()` and string names (no `Steam` global). Game key `cast_licensed_sorcery`; lobby data `name`, `game`, `version` (`BuildVersion.text()`), `protocol`, `seats_free`, `state` (`board`/`job`). The list filters on game, version, `seats_free != "0"` and one free slot. Max 3 members (Steam's "lobby full" maps to "Crew is full"). `+connect_lobby <id>` read at start. Steam also sends `lobby_joined` to a lobby's creator: ignored unless we asked to join. Avatars not ported (M7). `run_callbacks()` every frame once Steam is up. |
| `network_manager.gd` | `net_session.gd` | Same STEAM/ENET transports and `local_id()` (0 offline). Added: `join_first()` (Bridge's main.gd Join flow), the hello handshake, the roster with character ids, refusals with a reason, a reason on every `session_ended`, `host_time()`, telemetry. `server_relay = false` (clients only talk to the host). The Steam peer gets `no_nagle = true`. ENet admits `MAX_CREW + 2` peers so a 4th can be told why before it is dropped. The peer is closed **deferred**: closing it inside its own poll (the "bye" RPC) crashed Godot. Watchdogs: a client that hears nothing from the host for 6 s ends with "The host clocked out"; the host drops a client silent for 10 s. |
| `main.gd` Host / Join / Local | `main_menu.gd` rows | "Local" is gone (solo = Start a job with nobody joining). |
| `net_telemetry.gd` | `net_telemetry.gd` | Same shape (one row a second, clients' rows filed on the host under `from`, gaps are missing). New columns (below); no F4 mark key. Files in `user://net/` (tests: `user://net_tests/`), newest 40 kept. |
| `_sim_link_ticks` / `_sim_drops_packet` | `net_link.gd` | On **every** process's inbound side, so both directions; reliable events are delayed too (in order, never dropped); wall-clock microseconds, not ticks. |
| `test_enet_loopback.gd`, `pinger.gd` | same names | Pinger lives in `tests/`; waits are wall-clock; also checks `SteamMultiplayerPeer` exists in 4.7 when the extension does. |
| CLAUDE.md "Multiplayer" | `docs/ARCHITECTURE.md` "Networking" | Plus Cast's own lesson (don't free the peer inside its poll). |

**Protocol (version 1).** Reliable events ride one RPC, `NetWire._ev(kind, data, stamp)`
(`@rpc("any_peer", "call_remote", "reliable", 1)`, channel 1); `stamp` is the sender's `host_time()`.
| Event | From → to | Data |
|---|---|---|
| `sys.ask` | host → a new peer, on `peer_connected` | `protocol`, `build` |
| `sys.hello` | joiner → host | `protocol`, `build`, `name` (`--net-name`, else the Steam persona, else the host names it "Crew N"), `character` (`Session.character_id`, default `wick`), `steam_id` |
| `sys.welcome` | host → joiner | `seat`, `peer`, `entries` (the roster), `host_unix` (the host's unix time at `host_time` 0; tests use it) |
| `sys.refuse` | host → joiner | `reason`: "Crew is full", or "Different build (crew on X, you on Y)" for a protocol or build mismatch |
| `sys.roster` | host → every crew member, after each join and leave | `entries`: `[{peer, seat, name, character, steam_id}]` by seat |
| `sys.bye` | host → crew, when the host leaves on purpose | `reason` ("The host clocked out") |
| anything else | either way | gameplay / test events, delivered through `Session.event_received` only from crew members (and only from the host, on a client) |

Unreliable packets: `send_bytes(..., TRANSFER_MODE_UNRELIABLE, 2)` with a 7-byte header, `u8 type | u16 seq | u32
stamp_ms`. One sequence stream per (sender, type) on the receiver, per (type, target) on the sender; a packet not
newer than the last accepted (u16 wrap-aware) is dropped as stale. Types: 1 `PING` (`u64` client send time),
2 `PONG` (`u64` echo, `f64` host time), 3 `ROW` (a client's telemetry row), 15 `TEST`, 16+ gameplay (16 = `SNAP`,
reserved for M2/M3 snapshots). `Session.send_event(0, ...)` / `send_packet(0, ...)` on the host go to each crew
member (a broadcast would reach peers still saying hello or being refused).

**Roster and seats.** The host is seat 1; a joiner takes the lowest free seat; at 3 the next hello is refused with
"Crew is full". Leaving frees the seat. Names, seats, peer ids and character ids are identical on every machine.

**Clock.** Pings every 0.5 s (the first 20 every 50 ms). Each pong bounds the offset (`host_t - t2 <= offset <=
host_t - t0`); the client intersects the last 24 samples' bounds (the best outbound and the best return leg, even from
different round trips) and slews to the midpoint at up to 5%, never backwards. Measured on one machine at 60 fps:
2-8 ms error with no link, 2-17 ms under `coast`. **Why not 5 ms:** each side only sees packets when it polls, once a
frame, and two processes at the same frame rate keep a fixed frame phase that no exchange of timestamps can observe,
so the error sits anywhere within half a frame (8.3 ms) and up to a frame while the window lacks a lucky sample (round
trips come out in whole frames: 100 / 117 / 133 ms under coast). The tests hold 10 ms (off) and 20 ms (coast). A frame
is the resolution anything in the game can act on, so this is enough for interpolation and scheduled spells, but M1+
tests that compare "the same host_time" across machines need a one-frame tolerance. `GameWorld.time` is **not** slewed
yet (there is no shared floor in M0): see "Changes for M1".

**Telemetry columns.** `t` (host_time), `role`, `from`, `seat`, `crew`, `rtt_ms`, `rtt_min_ms`, `jitter_ms`,
`clock_fix_ms` (correction still being slewed in), `quality` (share of unreliable packets that arrived), `bytes_out`,
`bytes_in`, `pkts_out`, `pkts_in`, `events_out`, `events_in`, `gaps`, `stale`, `link`, `link_held`, `link_dropped`,
`pending_rel` (blank: needs Steam's connection status, which `SteamMultiplayerPeer` doesn't expose; M7), `hits` (blank
until M4). Under `coast` the clients' rows read 100-150 ms RTT: 90 ms of link plus about a frame of polling per hop.

**Main menu (built as proposed).** 01 Start a job · *crew can join* (Steam: `Session.host_steam()`, then the job board;
no Steam, or the lobby fails: solo, and the board's crew strip says why), 02 Join a crew · *first crew hiring*
(`Session.join_first()`; greyed "Steam not running" without Steam; "Leave the crew" while joined, "Stop looking" while
searching), 03 Voice setup, 04 Settings, 05 Quit. A typed status line shows progress and every end reason. A joined
client stays on the menu with "Connected to <host>'s crew. Shared jobs arrive in a later build." and the crew list.
The host's job board shows the crew under the cards. Opening the menu as a host closes the crew (Esc on the board, or
Main menu from pause, ends the session for everyone with "The host clocked out"). An overlay invite while running
leaves the current session and joins (no prompt yet; M7).

**Dev flags (differ from the proposal's `--net enet --host` form).** `--net-host`, `--net-join <ip[:port]>`,
`--net-port <P>` (24600), `--net-link off|coast|rough`, `--net-name <name>`, `--net-steam-probe`. `--seat` was not
needed (seats come from join order). `run.ps1 -Crew 2|3 [-Link coast]` opens a host window and joiner windows
(only the host has the mic). The harness flags are `--net-role host|client --net-index i --net-port P --net-peers N
--net-link L`.

**The multi-process harness, as built.** `test_runner.ps1` treats a test with `const PEERS := N` (N = processes) as a
net test, runs it once per entry of `const LINKS` (default `["off", "coast"]`; `-Link` overrides) on port
`28000 + 10 * slot`, starts the host, waits 0.4 s, starts the clients (they also retry), and kills every process of a
run at 90 s. A run passes when every process exits 0, the host printed the PASS marker and no log has a SCRIPT ERROR.
Net runs go after the parallel batch, at most 2 at a time, before the serial voice tests. Changed from the plan:
**real time is `--max-fps 60` without `--fixed-fps`** (under `--fixed-fps` a headless process runs flat out and game
time races ahead of the wall clock, which broke the first run), and `NetTest` replaces the TestCase timer with a
wall-clock timeout. `NetTest` gives `report(key, value)`, `wait_reports`, `command(peer, cmd)` / `wait_command`,
`wait_done`, `until(cond, seconds)` and `roster_signature()`; a client's failed checks are forwarded to the host.
Runtime in `-TestAll`: the 5 net runs (`test_net_m0_crew` off/coast about 2 s each, `test_net_clock` off/coast about 6.5 s each, `test_net_link` coast about 9 s) take about 16 s of wall time, two at a time, after the parallel batch. The single-process `test_net_session` (about 18 s, mostly the 6 s silence watchdog) and `test_enet_loopback` (1 s) run inside the parallel batch.

**Tests and what they prove.**
- `test_enet_loopback` (1 process): two SceneMultiplayers, an RPC crosses ENet; `SteamMultiplayerPeer` exists in 4.7.
- `test_net_session` (1 process, about 18 s): offline facade (`local_id` 0, `Net.is_host()` true); two NetSessions:
  hello, seats, same roster, names, characters, clock sync, events both ways; "Different build"; client leave; a
  silent host (100% inbound loss) gives "The host clocked out" after 6 s; host leave (bye) reaches the client at once;
  units for u16 wrap, link loss/delay/order and the clock's interval intersection and slewing.
- `test_net_m0_crew` (4 processes, off and coast): 3 admitted with seats 1-3, the 4th refused "Crew is full", the same
  3-entry roster on every admitted process; a client leaves and both remaining ends see 2; the host's process exits and
  the last client ends with "The host clocked out".
- `test_net_link` (2 processes, coast): 300 reliable events each way arrive once and in order with about 55-75 ms one-
  way delay; 3000 sequenced packets each way (12 a frame, so jitter reorders them) lose about 1.5%, stale ones are
  dropped (none accepted out of order) and the u16 sequence wraps.
- `test_net_clock` (3 processes, off and coast): clock error from 3 s after joining, never backwards; telemetry CSVs on
  all three, the clients' rows in the host's file, RTT matching the link.
- `test_net_contract`: new rules `steam_api` (Steam singleton, `ClassDB` Steam calls, `Steam.` and
  `SteamMultiplayerPeer` only in `scripts/net/`), `send_bytes_mode` (every `send_bytes` in `scripts/net/` names
  `TRANSFER_MODE_UNRELIABLE`), `rpc_reliable` (every `@rpc` is reliable); `unreliable_ordered` and high-level sync are
  now checked **inside** `scripts/net/` too (before, the lint skipped that folder entirely); each rule is run against
  lines that must fail.
- `test_main_menu`: the five rows, Join greyed without Steam, Start plays solo with the note, and a joined client's
  crew view (over ENet in-process), "The host clocked out", Leave the crew.

**Manual Steam check (2026-10-17, this machine, Steam running, app 480).** `--net-steam-probe` ran the real host path:
lobby created, data set (`game=cast_licensed_sorcery`, `version`, `protocol=1`, `seats_free=2`, `state=board`),
`SteamMultiplayerPeer.create_host` OK, roster with the Steam persona, lobby left. Four lobbies were created in total
while building this, each left within seconds. The lobby list with Join's filters came back empty: Steam doesn't seem
to list a lobby to its own member (or the data hadn't propagated). So **Join a crew, invites and the Steam peer's
connection are only proven by the two-account checklist (§3)**. M0 items for that checklist:
1. A: Start a job; B: Join a crew finds A's crew; both see the roster (B on the menu, A on the board strip).
2. C joins (3 in the crew); D's Join is refused "Crew is full" (or finds nothing, since the lobby is full).
3. B leaves: A's strip drops B. A presses Esc on the board: B and C read "The host clocked out".
4. A invites B from the Steam overlay while B's game runs: B joins directly.
5. A build with a different `version.txt` can't find A's crew (the version filter), and a forced join says
   "Different build".

**Changes for M1 (found while building M0).**
1. **`GameWorld.time` needs a floor start on the shared clock.** `host_time()` counts from the session's start;
   `GameWorld.time` counts physics time per scene. M1 should send `floor_start_host_time` with the floor and have each
   client slew `GameWorld.time` toward `host_time() - floor_start` (NetClock's slew is reusable).
2. **One-frame tolerance** for every cross-machine "same host_time" check (clock section).
3. **Where a joined client lives.** In M0 it waits on the menu, and opening the menu as a host ends the crew. M1 moves
   joined clients onto the job board (the host's offers, the highlighted card), so Esc on the board for a client should
   mean "leave the crew", and the host leaving the board probably wants a confirm.
4. The job board already publishes `state` (`board`/`job`) to the lobby; M6's mid-contract join reads it.
5. `Session.event_received` delivers Variant dictionaries; fine for events, but M2's snapshots should go through
   `send_packet` on type 16 with the planned hand-packed codec.
6. `+connect_lobby` only matters once Cast has its own app id (on 480 Steam launches Spacewar).

### M1 as built (2026-10-17)
One session (M1a and M1b together). Everything in M1's "done when" passes (the plan's three tests, plus the leave, desync and
host-leave cases below); the run is playable as the plan says: everyone sees the same board, signs their own license and
stands on the same floor, frozen and unsynced.

**Files.** `scripts/net/`: `crew_flow.gd` (`CrewFlow`, child `Session/Flow`, `Session.flow` / `Net.flow()`: the state machine
and the floor clock slew), `net_floor.gd` (`NetFloor`: ids in build order, the checksum, `freeze_copies`), and in `net.gd`
`Net.crewed()`, `Net.simulates(node)`, `Net.is_copy(node)`, `Net.make_copy(node)`; `net_session.gd` gained `kick(peer, reason)`,
`set_members(peer, fields)`, `JOB_RUNNING` / `DESYNC`, the `flow` child and `_tune_enet` (note 11). The plan's `crew_flow.gd` is this one (it owns the
whole run state, not just the barrier); `net_ids.gd` became `NetFloor.assign_ids` (below). UI: `crew_confirm.gd` (`CrewConfirm`,
the host's "this ends the job for everyone"), `job_board.gd` (`read_only`, `highlight_changed`, the "THE HOST PICKS THE JOB"
note), `spell_picker.gd` (`back_text` / `back_hint`: a client's back row says "Leave the crew"), `main_menu.gd` (a joined client
goes straight to the game scene; `WAITING_NOTE` now says "Opening the job board..."). Game: `game.gd` (the shared run, below;
`Actor` also learned `Net.is_copy` in `apply_damage`, `die` and `shove`). Test support: `scripts/test_support/net_game_test.gd`
(`NetGameTest`) and `NetTest.after_end()`. Tests: `test_net_m1_floor`, `test_net_m1_desync`, `test_net_m1_leave`,
`test_net_m1_hostleft` (3 processes each), `test_net_floor`, `test_net_puppets`, `test_net_board` (single process);
`test_main_menu` changed (a joined client now asks to go to the game scene). `run.ps1`: `-ShotDir`. Dev flags in `game.gd`:
`--net-wait N`, `--shot-at board|license|wait|floor`.

**New protocol events (all reliable, `Session.send_event`).** The protocol version stays 1 (the handshake did not change).
| Event | From → to | Data |
|---|---|---|
| `crew.board` | host → clients (on every `host_board`, and to a member who joins while the board is up) | `seed` (the board seed), `hi` (highlighted card) |
| `crew.hi` | host → clients | `i` |
| `crew.job` | host → clients | `archetype`, `seed`, `difficulty`: `ContractRun.make(...)` rebuilds the contract anywhere |
| `crew.signed` | client → host | `spells` (exactly 2 available ids; anything else is ignored with a warning) |
| `crew.load` | host → clients, once every roster member has signed | (empty): build the floor behind the barrier |
| `crew.ready` | client → host | `sums` (the `NetFloor.checksum` dict) |
| `crew.go` | host → clients, once every remaining member is ready and none differs | `start_at` (host_time, `START_LEAD` = 0.5 s ahead; 0 for a crew of one), `floor_start` (host_time minus the host's `GameWorld.time`) |
| `sys.refuse {reason}` (reused) | host → one client | "Desync: different floor" for a floor that does not match; "That crew is already on a job" for a hello once the host has taken a job |
| `sys.roster` entries gain | host → crew | `signed` (bool), `spells` (array), `ready` (bool), reset on every `crew.board` / `crew.job` |

Only the host decides; clients draw what they are told. Nothing else changed on the wire.

**The shared run.**
- **Who is "shared".** `Net.crewed()` = online with someone else in the roster. A host alone (a Steam lobby nobody joined) takes
  the plain solo path through every function below, unchanged; `_shared` is decided when the host picks the job, and a
  client's is always true. While `_crewed()` (shared and someone still in the crew): no local pause (Esc opens the menu with the
  world running: M5b's rule, built early because a paused tree stops `GameWorld.time` and would break the clock), no exits (the
  elevator and van prompts do not show and `_open_elevator` is a no-op: M5), and no host-only checks on clients
  (`_check_objectives`, drop-offs, the elevator).
- **Board.** `game.gd` `_show_board` rolls the seed (the allowlisted `randi()`) and the host calls `Flow.host_board(seed, hi)`;
  a client's `_start_as_client` waits for `crew.board`, then draws `ContractBoard.offers(seed)` read-only. Hover, keys and clicks do
  nothing on a client's board; the host's highlight follows. `--net-wait N` (dev) makes the host wait for the crew.
- **Job and checkout.** The host's pick (`board.picked` -> `_begin_contract` -> `Flow.host_pick(run)`) reaches each client as
  `crew.job`, which builds the same `ContractRun` and opens that player's license checkout (`_build_world`, voice, picker).
  Signing sends `crew.signed`; the roster flags drive "License signed. Waiting for <names>..." (`CrewFlow.waiting_text()`, the
  label `_wait_label`). `--spells` signs at once on every machine.
- **Esc.** On a client's board or checkout (or while it still waits for the board) it leaves the crew (`_request_leave` ->
  `_to_main_menu` -> `Session.leave()`; the menu shows "You left the crew"). On the host's board, and from the pause menu's Main
  menu, a host with a crew gets the `CrewConfirm` ("Stay" is the default, "End the job"); a host alone just goes. Esc on the host's
  checkout goes back to the board and takes the whole crew with it (`crew.board`: a client mid-checkout or mid-floor reloads to the
  board); F5 / "Abandon contract" on the host does the same with a new board; for a client both mean leave. When the session ends
  under a client (the host left, it was sent out) its game asks for the main menu, which shows `Session.last_reason`.
- **Load barrier.** `crew.load` runs `_start()` on every machine: slots, the other seats' spells from the roster, `_populate_site`,
  `_arrive_by_van` (held at its first frame), grime, dev flags; then `_enter_barrier()` assigns ids (`NetFloor.assign_ids`), makes the
  host's things copies on a client (`NetFloor.freeze_copies`), freezes the world (`_freeze(true)`, which also stops the controller),
  takes the checksum (11-12 ms for about 2,000 cells and 80 actors) and reports `crew.ready`. The floor line, the dispatch banner
  and the `--shot` timer wait for the start.
- **Checksum.** `NetFloor.checksum` hashes four parts: `map` (every cell: level, type, stairs, tag, midpoint-wall mask and top,
  material), `plan` (every `SitePlan.net_fields()` field: rooms, themes, notes, props, decor, the van, ...; a hash per field is kept
  for diagnostics), `run` (every `ContractRun.net_fields()` field) and `spawn` (net id, script, name, team, cell, position to 1 cm and
  max HP of every actor in build order). The text is canonical (sorted dictionary keys, fixed decimals, `-0` is `0`). The host
  compares each client's `all` with its own: a different one is printed (`[Net] DESYNC: <name> built a different floor (differs: map,
  plan / plan fields: ...)`), recorded in `Flow.desyncs`, and the client is sent out with "Desync: different floor"; the rest
  start without it.
- **Floor clock.** `crew.go` carries `start_at` and `floor_start`. At `start_at` (`CrewFlow._process`, `floor_started(elapsed)`) every
  machine unfreezes and the van arrival plays from `elapsed` (`VanArrival.time`). `GameWorld.time` is written in one place,
  `CrewFlow._physics_process` (after `GameWorld`'s own tick), on clients only: it JUMPS once when `crew.go` arrives (`first_adjust`
  says by how much), then follows `host_time() - floor_start` at up to 5% (a snap past 1 s). The host's clock is not touched:
  `floor_start` is `host_time() - GameWorld.time` at the moment of `crew.go`, so nothing the host stamped during the build moves.
- **Seats and heroes.** `_crew_seats()` / `_spawn_crew()` build three heroes by seat on every machine: seat 1 is the host's, a human
  takes their seat with the character id from the roster (Wick for everyone today: two or three Wicks is right), an empty seat is an
  AI ally (seat 2 Rebar, seat 3 Gasket, the same formation numbers as solo). `player` is the hero this machine controls (the one with
  a `PlayerController`; on a client its own seat's), `allies` the other two in seat order, `heroes_by_seat` the map. On the host every
  other hero gets an `AllyBrain` following seat 1's hero (a client's seat is an AI until M2); on a client they are copies. Solo builds
  exactly Wick, Rebar and Gasket as before.
- **Copies.** `Net.make_copy(node)` sets the meta `net_copy` and stops `_physics_process` (AI and logic); `Actor.apply_damage`, `die`
  and `shove` refuse on a copy. `NetFloor.freeze_copies(root, keep)` marks every actor under the world except the local hero, and the
  component pickups. The employee prompt skips copies (no E on a frozen employee). `Net.simulates(node)` is the check M3 builds on:
  true for everything offline and on the host.

**What the tests prove** (timings are this machine's).
- `test_net_m1_floor` (3 processes, `off` and `coast`): all three draw the same offers (read-only, "host picks", a click picks nothing),
  follow the host's highlight, build the same contract, sign different licenses (the host last: the first signers read "License signed.
  Waiting for host..."), and every process's roster holds all three licenses and each machine's heroes hold them; the four checksum
  parts and the cell and actor counts match on all three; each client's `GameWorld.time` tracks the shared clock within 33 ms (`off`) /
  50 ms (`coast`) over the first 3.2 s (measured 1-6 ms in both), and so does the van arrival's own time; every host-owned actor on a
  client is a copy that did not move or change; each machine controls exactly one hero, in its own seat, and only the host runs AI heroes.
- `test_net_m1_desync` (3): c2 builds another seed (`CrewFlow.debug_seed_shift`): the host logs it and sends c2 out with "Desync:
  different floor", c2's game goes back to the menu and never starts the floor, the host and c1 start theirs without it.
- `test_net_m1_leave` (3): c2 leaves in its checkout through the row, nobody waits for it, the two who stay start with matching
  checksums; then the host's process exits and c1's session ends with "The host clocked out" and its game asks for the menu.
- `test_net_m1_hostleft` (3): Esc on a client's board leaves with no question; the host takes a job, backs out of its checkout and the
  remaining client is back on the board with the same offers; Esc on the host's board asks, "Stay" keeps the crew, "End the job" ends it
  and the client is told "The host clocked out".
- `test_net_floor` (1 process): the checksum is the same for two builds and differs in the right part for one changed cell, a material,
  a monster moved 5 cm, a plan field (it names the field) and a contract field; ids come in build order, are the same on a rebuild, and
  heroes get their seat. `test_net_puppets`: over 120 frames no PRIVATE or OWNER field of any copy changes and none takes damage, while a
  control floor does change. `test_net_board`: the read-only board, the leave row, the confirm.

**Notes for M2 (what M1 changes in its plan).**
1. **Hero copies on a client are inert today** (`Net.make_copy`: physics process off, no damage). M2 must turn them into puppets that
   apply the interpolated state each frame and keep animating (`Hero._process` still runs); `make_copy` is the M1 stand-in, and
   `Net.simulates()` stays the question.
2. **The host's AI heroes for human seats.** `_spawn_crew` puts an `AllyBrain` on every non-local hero on the host. M2a must not keep one
   on a client's seat: that hero becomes a puppet of the client's stream, and only unfilled seats keep their brain; a dropped player's
   seat gets it back (M2b). `AI_SEATS` (seat 2 Rebar, seat 3 Gasket, the formation numbers) is the "original character" table the drop
   story needs; a human seat spawns the roster's character (Wick) but uses that seat's AI formation numbers.
3. **Ids exist.** `NetFloor.assign_ids` (at the barrier) gives heroes 1-3 by seat and every other actor 100+ in build order, as the meta
   `net_id` (`NetFloor.id_of`); M3's runtime spawns start at 10000 as planned. There is no registry yet (no id -> node map); M2 needs one for
   the snapshot manifest. The spawn table is in the checksum, so a different id order is a desync.
4. **Seats and spells are on every machine.** The roster entries carry `spells` per seat, so M4's "heal aimed at B" can read them; `signed`
   and `ready` are floor-start bookkeeping.
5. **`GameWorld.time` is on the floor clock from `crew.go`.** A client jumps once, then slews, so a time stamp a client made BEFORE `crew.go`
   (nothing in M1 does) is in its own pre-floor time. Scheduled effects (M4) may treat `GameWorld.time` as shared. The slew is in
   `CrewFlow`, not `GameWorld`; if M5's floor changes reuse the barrier, send a fresh `crew.go` (a new `floor_start`) per floor.
6. **The barrier is reusable.** `crew.load` / `ready` / `go` and `_enter_barrier` / `_begin_floor` are what M5's floor change needs;
   missing: a way to start a barrier without the board (`Flow.phase` only goes BOARD -> LICENSE -> LOADING -> PENDING -> FLOOR) and a
   per-floor `crew.go`. The static vars in `game.gd` survive a reload as before; `_shared` does not (recomputed in `_begin_contract`: a
   reloaded host with a crew in the roster is shared again, and a client's `_start_as_client` follows the flow).
7. **A joiner mid-contract is refused** with "That crew is already on a job" (`NetSession._host_sys`, when `crew_state == "job"`) until
   M6; the lobby `state` was already published. `crew_state` goes back to "board" with the board.
8. **Pause and exits are off while crewed.** `_crewed()` gates them; M5 replaces both. Esc opens the pause menu without pausing, which is
   already the M5b rule.
9. **Accuracy.** The measured error of `GameWorld.time` and of the arrival against the shared wall clock is 1-6 ms (the clock's own 2-17 ms
   band), so M2's interpolation can trust `host_time()`; the tests allow one frame plus the link (33 / 50 ms).
10. **Test pattern.** `NetGameTest` gives M2 a bot with a real game scene (`make_game()`, `my_hero()`, `hero_at(seat)`, `truth()`); it
    needs only the plan's scripted move intent. A client that was sent out cannot report to the host any more, so it checks its own side
    (its exit code carries the failed checks).
11. **ENet throttles unreliable packets under jitter, on purpose.** Found because `test_net_link` [coast] had been failing about half of its runs on this machine (the baseline M0 build too: 6 of 6 failed in isolation today): ENet's congestion control lowers a connection's packet throttle when round trips vary and then drops unreliable packets, so the receiver lost more than the simulated 1.5%. `NetSession._tune_enet` now configures every ENet packet peer so its throttle never falls (`throttle_configure(5000, 2, 0)`); unreliable loss on ENet is the link simulator's alone, and `test_net_link` passed 6 of 6 after it. M2's snapshot tests ride the same path: keep it. (Steam has its own congestion control; this is the dev and test transport only.)
12. **Left out on purpose (M1 scope):** no hero movement sync, no puppet interpolation, no `net_codec` / `net_snapshot`, no pause or exit
    sharing, no mid-contract join. A client's attacks and spells act on copies and do nothing (copies take no damage), so combat on a
    client is silent until M3/M4.


### M2 as built (2026-10-17)
One session (M2a and M2b together). Everything in M2's "done when" passes under `off` and `coast`, and the run is playable as
the plan says: **two or three players walk around the same floor together**, each moving their own hero with no lag on their own
screen, seeing the others walk, turn and animate about a tenth of a second behind, with the player's name over them; a player
who drops is replaced by the seat's AI. Monsters are still the host's frozen copies on a client (M3).

**Files.** `scripts/net/`: `net_snapshot.gd` (`NetSnapshot`, child `Session/Snap`, `Session.snap`: the streams and the puppets),
`net_codec.gd` (`NetCodec`) and `net_hero_state.gd` (`NetHeroState`) (the bytes), `net_interp.gd` (`NetInterp`),
`seat_handover.gd` (`SeatHandover`, child `Session/Seats`, `Session.seats`), `net_registry.gd` (`NetRegistry`), `net_events.gd`
(`NetEvents.CARRIES`); `net.gd` gained `owns`, `is_puppet`, `make_puppet`, `release_copy`, `label_of`; `net_floor.gd`
`assign_ids` fills the registry. Game: `game.gd` (`_begin_hero_sync`, `_update_hero_sync`, `_drop_departed_seats`,
`_on_seat_to_ai`, `--net-bot`), `Hero.become()` / `Hero.set_player_name()`, `PlayerController.move_override`,
`ContractSession.carry_key`; the HUD ally rows read `Net.label_of`. Test support: `net_bot.gd` (`NetBot`) and the recorder in
`NetGameTest` (`enter_floor`, `wait_sync`, `start_bot`, `record`, `series_error`). Tests: `test_net_m2_walk`, `test_net_m2_drop` (3
processes each), `test_net_codec`, `test_net_interp`, `test_net_seats` (single process), and the carrier checks in
`test_net_contract`. `run.ps1`: `-Bot N`, `-Size WxH`, and a fix: `--spells heal,corn` reached the game as two arguments (PowerShell hands a script `heal,corn` as an array), so the M1 README example never signed the license; it is joined back now.

**Ownership.** Each machine owns its own seat's hero (its `PlayerController`) and streams it; on the host the AI heroes of EMPTY
seats (`AllyBrain`, the seat's original character: seat 2 Rebar, seat 3 Gasket) are streamed too. Every other hero is a **puppet**
(`Net.make_puppet`: a copy with no controller, brain, damage or shoves, plus the meta `net_puppet`). The host keeps no brain on a
human's seat any more (M1's host ran `AllyBrain` on every other hero). No input crosses the wire.

**The snapshot (`NetWire.T_SNAP` = 16, unreliable, with the wire's u16 sequence and stale-drop as for every packet).**
The payload after the 7-byte wire header is `u8 count`, then per hero a 16-byte entry (17 with the bow drawn):

| bytes | field |
|---|---|
| 1 | `head`: seat (bits 0-1), held slot (2-3), **teleport counter** (4-7) |
| 1 | `flags`: dead 1, climbing 2, ghost (passing through other heroes) 4, drawing 8 |
| 1 | `age`: ms between the sample and the packet's stamp (0 for the sender's own hero, more for a hero the host forwards), so every sample keeps its moment on `host_time()` |
| 6 | position x, z, y: i16 centimetres each |
| 2 | velocity x, z: i8 in 1/8 u/s (+-15.9): the Hermite tangents and the extrapolation |
| 1 | facing: u8, 256 steps of a turn |
| 2 | aim point relative to the hero: i8 in 1/4 unit (+-31.75) |
| 2 | hp: u16, tenths |
| (1) | bow draw time: u8 centiseconds, only with the drawing flag |

**Sizes (measured):** a client's packet is **24 bytes** (7 + 1 + 16); the host's to a client, with two heroes, is **40 bytes**. At
30 Hz that is **725 B/s up** from a client and **1.2 KB/s down** to each (2.4 KB/s out of the host to two clients); the plan's
budget is 3 KB/s per client. Quantisation error: position under 5 mm, facing under 0.7 degrees.
Direction: a client sends only its own hero to the host (clients never talk to each other); the host sends each client every hero
but that client's own: its own, the AI ones (live), and the OTHER client's, forwarded as the newest state received (left out when
older than 0.3 s). The first payload byte is a hero count; M3 appends the world after the heroes.

**Which `Hero` OWNER vars are carried.** In the snapshot (`NetCodec.HERO_FIELDS`): `hp`, `dead`, `facing`, `climbing`,
`pass_through_until` (as the ghost flag), `held_slot`, `_draw_start` (as the draw time); plus position, velocity, aim and the
teleport counter, which are not vars. **Not in M2** (`NetEvents.CARRIES`, each naming its carrier): `spell_slots` and `_charges` (the
roster has them at the floor start; pickups in M3 and casts in M4 are events) and `_modifiers` (armor, coffee, vines: M4). A puppet
therefore shows its owner's HP, death, held spell and drawn bow, but not a swing, a cast or a status until M4.

**Showing it (`NetInterp`).** Each puppet has a buffer of samples and shows the hero at `host_time() - delay`: Hermite on x and z
(positions and velocities), linear on height, the short way round for facing, a step for hp/dead/the bow. Past the newest sample
it extrapolates along the velocity for up to 120 ms, then holds. The delay starts at 100 ms and follows the 90th percentile of how
late the samples arrive (+30 ms), slewed at 10% a second: measured **100 ms on a clean link, 100-120 ms for a direct stream over
`coast`, 170-190 ms for the other client's hero (two hops)**. A **teleport** is a jump of more than 3 units between two samples,
decided where the sample is taken, never from a physics-frame difference (the first version did that, and under `coast` one sample
could carry the new place with the old counter, so the puppet smeared for a frame); the counter changes, the receiver empties the
buffer and calls `reset_physics_interpolation()`, and the puppet jumps in one frame.

**Arrival and floor start.** Streaming and showing start at the shared start and only when this machine's own van arrival is over
(`_update_hero_sync`: `VanArrival` places and hides the heroes itself for 2.5 s, and skipping it with a key is local). The first frame
of a puppet is a jump (it was standing at the van door a moment ago).

**A player drops** (`SeatHandover`, event `seat.ai`). The host's `peer_left` for a seat's owner: the table's owner for the seat becomes
0 and its epoch goes up; `NetSnapshot.seat_released` lets go of the puppet (the hero stands where the newest sample put it and acts
again, `Net.release_copy`); `to_ai(seat, character)` fires and the game re-kits **the same hero node** in place (`Hero.become`: kit,
name, colour, model; HP keeps its fraction; a downed hero stays downed) and attaches an `AllyBrain` with the seat's formation numbers;
the host sends `seat.ai {seat, character, epoch}` (reliable) to the clients, whose `to_ai` re-kits their copy of the node (a puppet
still, now of the host's stream). The node and the net id never change, so followers, the HUD and every reference stay valid (M6's
join will run the same `become` the other way). A player who left **before the barrier** (during the license checkout, after the
heroes were built at the job pick) is converted by every machine at the barrier from its own roster (`_drop_departed_seats`; the host's
roster update travels ahead of `crew.load` on the same ordered channel, so all of them see the same roster and the checksum agrees:
`test_net_m1_leave` caught the first version, which converted on the host only). The **floor carry is keyed by seat**
(`ContractSession.carry_key`, the meta `crew_seat`; a hero outside the crew keeps its name key, so the old tests are unchanged).

**Registry.** `NetRegistry`: `register(id, node)`, `node(id)` (never a freed node), `hero(seat)`, `id_of`, `ids()`, and
`next_runtime_id()` from 10000 (the host will hand those out in M3). `NetFloor.assign_ids` clears and fills it at every barrier.

**What the tests prove** (timings are this machine's; three real-time processes).
- `test_net_m2_walk` [off, coast]: roles (each machine simulates exactly its own hero and shows the other two as puppets with the
  roster names `host` / `c1` / `c2`; nobody runs an AI); then 9 s of all three walking a scripted loop at once (a `NetBot` steering the
  real controller; routes avoid the van and the furniture): for every pair, about 500 frames each, the puppet is within **0.07 units** of
  where the hero really was at the time shown (limit 0.35) under `off` and `coast`, and the biggest step beyond what walking covers
  in the frame gap is 0.04 (limit 0.6), including the pairs that go through the host's forward; the budget (24 / 40 bytes, 725 B/s,
  under 3 KB/s); `coast` really lost snapshots (4-16 gaps a process, 1-2 refused as stale) and the walk held; a teleport of 15 units
  is ONE jump on the host's screen and on the other client's, with no frame anywhere between the two ends; HP, the held spell and a
  death arrive on every screen and agree with the owner.
- `test_net_m2_drop` [off, coast]: c2 walks away, stands still, tells the host where and quits its process; the host drops it and
  seat 3's hero is the same node, now Gasket (kit, name, model, nameplate, id 3, registry), simulated, with an AllyBrain, at c2's
  spot, with its HP fraction, **about 40 ms after the process quit** (the limit is 1 s; ENet's disconnect is not delayed by the link
  simulator); the AI walks it 7 units back toward the crew; c1 is told, re-kits the same node, keeps it a puppet, and its picture of
  the AI's walk stays within 0.03 units of where the AI really was.
- `test_net_codec`: sizes, 400 randomised round trips within one quantum, clamping, ages, truncated or random packets, and every var
  in `HERO_FIELDS` through hero -> bytes -> hero (the test names them, so a codec field without a test fails).
- `test_net_interp`: a known zig-zag path with stops, sampled through the real codec and delivered the way a link would: `coast`
  direct 0.09 max error (0.155 step), forwarded through the host 0.05 (the delay grew to 214 ms), `rough` 0.05, six packets lost in a
  row 0.21 (0.29 step), a perfect link exact; a teleport never shows a position on the way; silence holds the hero.
- `test_net_seats`: the registry, the carry keyed by seat (two Wicks, one downed), `Hero.become`, the seat table.
- `test_net_contract`: **carrier coverage** driven by `net_fields()`: every OWNER var of `Hero` is in `NetCodec.HERO_FIELDS` or
  `NetEvents.CARRIES`, the codec streams only OWNER vars (a SPAWN / PRIVATE / LOCAL var, a stale name or a var with two carriers
  fails), and the check is run against declarations that must fail.
- `test_net_m1_floor` changed in one place: the host runs no AI when all three seats are players.

**Notes for M3.**
1. **Monsters are still `make_copy` on a client**, so a monster on the host that attacks a client's hero hits a puppet, which takes no
   damage. That is by design until M4 ("the victim decides"). The host's monsters do chase and hurt the host's hero and the AI heroes,
   and the AI heroes' HP reaches the clients through the snapshot.
2. **Reuse:** `NetRegistry` (ids); `NetInterp` (it works on `NetHeroState`; M3 needs the same buffer over a monster state: generalise
   the sample class or add a second one, the delay logic and Hermite carry over); `NetWire.T_SNAP` and the packet shape (the first
   byte is a hero count, put the world sections after the heroes and add a section byte if the layout needs it); the teleport
   counter (a spawn or a respawn is a discontinuity); the age field for forwarded state.
3. **`Net.owns(node)` is `simulates(node)` for now.** M3 must answer it for the host-owned world too (monsters on a client are copies,
   not puppets of a stream yet); `Net.make_puppet` is what a monster that applies a snapshot should become.
4. **Sampling happens in `_process`** (render frame, 30 Hz on the wall clock) from the latest physics state, with the velocity of the
   last physics frame. What M3 streams from the host should be sampled at the same place so a hero and a monster share one moment.
5. **Pickups:** `ComponentPickup` collects only for `is_player` heroes, and a puppet is never one, so the host does not collect for a
   client's hero. M3b's request / grant is still needed (a client's pickups are frozen copies today).
6. **A hard kill takes 10 s to notice.** A process that quits (and, to be checked on Steam, a clean leave) is dropped at once, but a
   crash or a pulled cable is dropped by `CLIENT_SILENCE` (10 s); with a 30 Hz stream the host could tighten that for a hero that was
   streaming (M7).
7. **The roster at the job pick still decides who is a person** (heroes are built in `_build_world` when the job is picked, before the
   license); `_drop_departed_seats` covers the ones who left since. A *joiner* during the checkout is refused anyway (`JOB_RUNNING`).
8. **The van arrival** is the only thing that moves a hero other than its owner (the dev warps are detected as teleports). If M5 adds
   an arrival on floor changes it must gate `_update_hero_sync` the same way.
9. **Revival** (the invoice's "revived for you") is not a snapshot concern yet: `NetCodec.write_hero` ignores a dead -> alive flip.
10. **Test pattern for M3/M4:** `NetGameTest.enter_floor()` + `wait_sync()` put three processes on a running floor in about 8 s with
    the game's own dev flags; `start_bot()` walks a hero; `record()` / `series_error()` hold what a viewer showed against the owner's
    truth at the shared time shown. A monster's render error (M3's "under 0.5 units") can use the same recorder with the host's ring.

### M3 as built (2026-10-18)
One session (M3a, M3b and M3c together, plus the exits' first-to-choose rule, which the plan had in M5). Everything in M3's
"done when" passes under `off` and `coast`, and the run is playable as the plan says: **players walk among live monsters that fight
back** (on the host's hero and the AI's: a client's hero is a puppet on the host and takes no hit until M4's victim rule), see
hellgates wake, flare, burst and close, recruit and dismiss employees, break props, crates and mail, pick things up (exactly one
player gets each), and take the elevator down or clock out together (the first player to choose decides for the crew).

**Files.** `scripts/net/`: `net_world.gd` (`NetWorld`, child `Session/World`, `Session.world`: the host streams its monsters,
hellgates and employees; a client shows them as puppets), `net_world_codec.gd` (`NetWorldCodec`: the bytes, the field tables and
how each class's OWNER fields go in and out), `net_objects.gd` (`NetObjects`, child `Session/Objects`, `Session.objects`: hits on
props, crates and mail, pickups, employee requests, loadouts, the Ledger and objectives mirror, the exits and the invoice);
`net.gd` gained `remote_die`, `routes_hits`, `route_hit`, `request`, `request_drop`, `world_live`, `lead_point`; `net_snapshot.gd`
appends the world after the heroes (and `lead_point(seat)`), `net_codec.gd` `decode_from` (the world follows the heroes in the
same buffer), `net_hero_state.gd` (`id`, `mode`, `telegraph`, `extra`, `helpless`: the sample class of every interpolated actor),
`net_interp.gd` (the wind-up blends within one state), `net_floor.gd` (`assign_ids` also numbers the pickups already on the floor),
`net_events.gd` (`WORLD_CARRIES`, the event kinds), `crew_flow.gd` (`host_next_floor`, `crew.next`, `floor_change`),
`net_session.gd` (the two children). Gameplay: `Actor.apply_damage` (a hit on a copy goes to `Net.route_hit`), `Monster`
(`strikes`, `net_show`/`net_tick`, `target_point()` = `Net.lead_point`, drops only on the owner, `_on_strike_visual`; brute: the
shockwave, archer: a harmless arrow), `Hellgate` (`net_show`, `net_phase`, `net_shove_fx`, `net_burst_fx`; `_burst_fx`/`_shove_fx`
split out), `Employee` (`said`, `net_show`/`net_tick`, `_look_around` (the LOCAL mood), requests judged at the position a client
gives, `interact` routes to the host, `_is_person`), `PricedProp`/`MailPackage` (`net_tick`; mail hands out only on the owner),
`ComponentPickup` (`copy_at`, `net_tick`, `drop` becomes a request on a client), `Hero` (`swap_in_pickup` asks the host;
`apply_swap`), `Ledger` (`mirror`, `mirror_line`), `ContractSession` (`mirror_state`, `apply_mirror`). `game.gd`: the barrier begins
`Session.world` and `Session.objects`; the books are kept on the host (`_keeps_books`, `_publish_contract`, `_on_contract_mirror`,
`_end_from_host`); the exits (`_choose_exit`, `_on_exit_decided`, `_descend_shared`; a menu freezes only your own hero while crewed);
a host reloaded onto the next floor rejoins the barrier; `--spawn-near` anchors on seat 1 in a shared run (same cells everywhere);
`_last_invoice` (test seam). Test support: `NetGameTest.make_game(extra, fresh)`, `follow_reloads` / `reloads` (a scene reload the
game asks for is done, keeping the contract). Tests: `test_net_m3_world` (2 processes), `test_net_m3_objects`, `test_net_m3_exit`
(3 each), `test_net_world_codec` (single process); `test_net_contract` gained the world's carriers and the budget check.

**Ownership.** `Net.owns(node)` is still `simulates(node)`, and that is now the whole answer: on the host everything but a client's
hero is its own; on a client every host-owned thing (monsters, hellgates, employees, props, crates, mail, pickups) is a copy
(`freeze_copies` at the barrier, as in M1), and the movers are puppets of the host's stream (`Net.make_puppet`). Copies keep taking
no damage; a hit from this machine on a **host-arbitrated object** (prop, crate, mail box: `Net.routes_hits`) becomes a request
(`Actor.apply_damage` -> `Net.route_hit`), which is the one combat path M3 opens across owners. A hit on a monster or a gate from a
client still does nothing (M4, "the attacker decides").

**The world in the snapshot (`NetWire.T_SNAP`, host -> client only, after the hero entries).**
`u8 n_monsters, n x MONSTER (16 B) | u8 n_employees, n x EMPLOYEE (15 B) | u8 n_gates, n x GATE (7 B)`:

| entry | bytes |
|---|---|
| MONSTER | `u16 id`, `i16 x, z, y` (cm), `i8 vx, vz` (1/8 u/s), `u8 angle`, `u16 hp` (tenths), `u8 flags` (state 0-2, climbing 8, helpless 16, teleport counter bits 5-7), `u8 telegraph` (the wind-up, 1/255), `u8 strikes` (attacks struck, mod 256: a change plays the swing) |
| EMPLOYEE | `u16 id`, the same 11 bytes of motion, facing and hp, `u8 head` (state 0-2, dismissed 8, climbing 16, teleport counter 5-7), `u8 leader` (the seat it follows, 0 none) |
| GATE | `u16 id`, `u16 hp`, `u8 flags` (active 1, flare 2, phase bits 2-3), `u8 burst_in` (1/50 s while the flare is up, 255 none), `u8 shove_t` (centiseconds of the origin gate's shove wind-up, 255 none) |

Which entries ride (`NetWorld.section`, built ONCE per 30 Hz tick and appended to every client's packet): an entry whose bytes
changed rides that tick and the next `REDUNDANCY` (3) ticks (one lost packet never strands a stop); every entry rides at least
every `REFRESH` (30) ticks, the overdue ones first and a thirtieth of the rest each tick (the keyframe is spread over the ticks, so
no packet carries the whole floor at once; the plan said a keyframe every 15 sends: 30 halves what a still floor costs, about
16 B per actor per second, and the redundancy already covers loss); oldest first, up to the packet budget (`NetWorldCodec.PACKET_BUDGET` 1200 B for the
whole packet: `NetWorld.WORLD_BUDGET` 1158 B after the wire header and two heroes). Packed bytes are compared, so an idle monster
costs nothing between its refreshes. There is no id manifest: spawns and deaths are reliable events, and an entry for an id a client
does not know is skipped (counted as `unknown`; 0 in every test).

**Showing it.** A client's movers share ONE delay, measured on the world packets (`NetInterp`'s adaptive delay on a stream of
per-packet samples), so the whole floor is shown at one moment: 100 ms on a clean link, 100-110 ms under `coast`. Each mover has a
`NetInterp` buffer of `NetHeroState` samples (Hermite, extrapolation for 120 ms, teleports never blend). A sample that arrives
after a quiet spell (the actor stood still and was not sent) gets a "held still" sample one tick before it, so the puppet does not
start walking early. `NetWorldCodec.write_monster/write_employee/write_gate` put the state on the node and the class plays what
changed (`net_show`): an HP drop flashes and updates the bar, entering ATTACK begins the wind-up (the brute's ring), leaving it ends
it, a new strike count swings (the archer's puppet looses a harmless arrow, the brute's a shockwave); an employee's state sets its
mood and pose, and its LOCAL mood (`_hero_near`, `_scared`: the name tag, the cower bubble) is worked out on each screen
(`net_tick` -> `_look_around`); a gate wakes, flares, cracks and changes phase. A death is applied when the render time reaches the
host's stamp (or 0.6 s after it arrived), through `Net.remote_die` (the visuals and signals of `die()`, deciding nothing: a
monster's drops, a box's contents and a prop's bill are the owner's, checked with `Net.owns` in `_on_death`).

**Events (reliable).**
| Event | From -> to | Data |
|---|---|---|
| `world.spawn` | host -> clients | `g` (the gate's id, 0 for none), `m`: `[[id, kind, x, y, z], ...]`: one event per burst, ids from `NetRegistry.RUNTIME_BASE` (10000) up; the client builds the monsters (`MonsterFactory`), registers the ids, makes them puppets and plays the gate's burst |
| `world.die` | host -> clients | `id` (a monster, gate or employee; the stamp is the moment) |
| `world.say` / `world.extract` | host -> clients | an employee's bubble (`id`, `s`, `d`) / its extraction (`id`, `s` the bark) |
| `world.phase` / `world.shove` | host -> clients | the origin gate's phase change and its shove wind-up / the shove going off (the look) |
| `obj.req` | client -> host | `what`: `hit {id, a, by}`, `collect {id, want, at}`, `swap {id, at}`, `drop {s, n, at, l}`, `follow` / `wait {id, at}`, `exit {c}` (`at` is where the player says its hero stands) |
| `obj.break` / `obj.hurt` | host -> clients | a prop, crate or box broke (`id`; a box adds `c` contents, `cr` crypto, `cid` component) / a prop was dented (`id`, `hp`, `a`) |
| `obj.pickup` / `obj.pick` / `obj.gone` | host -> clients | a pickup appeared (`id`, `s`, `n`, `at`, `l` lifetime, `age`) / its charges changed / it is gone |
| `obj.grant` / `obj.deny` | host -> the asking client | `id`, `k` (collect / swap), `s`, `n`, `at` / `id` |
| `obj.loadout` | owner -> host -> the others | `seat`, `sl` (slots), `ch` (charges): after a pickup or a swap changes a hero's slots |
| `obj.ledger` / `obj.contract` | host -> clients | every Ledger line / `ContractSession.mirror_state()` (the floor's objective dict, the lost list, extracted) after each change |
| `obj.exit` / `obj.end` | host -> clients | the crew's exit (`c` down / out / van, `seat` who chose) / the host's finished invoice |
| `crew.next` | host -> clients | the crew goes down: build the next floor behind the barrier (CrewFlow LOADING with `floor_change`; then `crew.ready` and `crew.go` as in M1) |

**Host-arbitrated objects (`NetObjects`).** *Breakables*: the host applies a client's hit to its own object (the culprit is that
player's hero); a prop broken by two players at once is broken and billed once (the second hit finds it dead). *Pickups*: the host
numbers every pickup it puts down (monster drops, mail, swaps, `--drop-near` ones are numbered at the barrier) and polls them each
frame for charge changes and ends. A client's copy runs `net_tick` (it ages and blinks, shows its label, offers the F swap) and
walking onto it asks; the host grants the first request it reads (up to what that player can take; a swap takes all) and refuses
the rest; the player's own machine changes its own hero (`collect_component` / `apply_swap`) and tells the crew its slots and
charges. The host's own hero still collects locally (first by construction: its pickups run in its physics frame). *Employees*: E
on a client goes through the same `use_target` / `Employee.interact`, which asks the host when it does not own the employee; the
host runs `request_follow` / `request_wait` judged from the position the client gives. The leader travels as a seat.
*Money*: a client's Ledger is a **mirror** (`Ledger.mirror`, set at the job pick on a client, cleared by `end_contract`): its own
writes are dropped and the host's lines arrive as they are written; the objective bookkeeping (`ContractSession`) is kept on the host
only (`game._keeps_books`) and mirrored. The invoice a client shows is the host's dict.

**Exits: first to choose.** While crewed the van and the elevator prompts are back; opening their menu stops only your own hero
(the M5b rule, `_freeze`). A row picked is a choice (`_choose_exit`): the host takes the first it sees (`NetObjects.decide_exit`,
its own included) and every machine follows that one (`_on_exit_decided`, with "<name> takes the elevator down / clocks the crew
out" on every screen); later choices are dropped. *Down*: every machine keeps its heroes' HP and downed state by seat, bumps the
floor and reloads; the host starts the barrier (`CrewFlow.host_next_floor` -> `crew.next`), a reloaded host or client builds the
next floor behind it with no board and no license, the checksums are compared and `crew.go` starts it for everyone. *Out / van*:
the host extracts the followers at that exit, ends the contract and sends its invoice; "crew incapacitated" also ends on the host
only. A client's "Next contract" waits for the host's board.

**Monsters aim at players fairly (M3a).** `Monster.target_point()` is `Net.lead_point(target)`: for another player's hero on the host
it is the newest snapshot's position carried along its velocity for that snapshot's age (at most 0.25 s), not the ~100 ms old puppet
the host draws; offline and for everything else it is the target's position (solo play is unchanged). Chasing, facing, the wind-up's
tracking and the archer's aim use it.

**Sizes and bandwidth (measured).** Entries: a monster 16 B, an employee 15 B, a gate 7 B; an empty world section 3 B.
`test_net_world_codec` builds the worst floor it finds (founder floor 3 at difficulty 1.0: 62 monsters, 3 employees, the origin gate
with its 19 spawns at the cap, 85 entries) and moves EVERYTHING every tick: the biggest packet is 1194 B (the budget holds; about
36 KB/s per client at worst) and no entry waits more than 2 ticks; the same floor standing still costs at most 51 B a tick and every
entry is refreshed within 30 ticks. **A typical fight** (`test_net_m3_world`, floor 1, about 22 monsters on the floor, 10 of them
chasing the host's hero): **about 3.8 KB/s down per client: heroes 1.2 KB/s + world 2.6 KB/s** (87 B world sections on average); the biggest packet 462 B.
**A typical floor** (`test_net_m3_objects`: three players on a floor 1 breaking things, grabbing a pickup and leading an
employee, nobody fighting): **about 4.2 KB/s down per client: heroes 1.2 KB/s + world 3.0 KB/s**; the biggest packet 757 B (the
stream's first ticks, when every entry is new). Telemetry's `bytes_in` / `bytes_out` columns carry the same totals per second. Up: a client still sends only its hero (725 B/s) plus the odd request. Reliable events are a few
dozen bytes each and rare (spawns, deaths, breaks, pickups, Ledger lines).

**What the tests prove** (timings are this machine's; real-time processes).
- `test_net_m3_world` [off, coast] (2 processes): the client shows every host-owned actor as a non-acting puppet and its Ledger is a
  mirror; over 8.5 s of host-driven fighting (five dev grunts and the nearest floor monsters chasing the host's hero walking a loop,
  two killed by the host), ten monsters (nine of them moving 2-9 units) are within **0.04 units** (`off`) / **0.03** (`coast`) of
  where the host had them at the time shown (limit 0.5); each death reaches the client's screen **about 110 ms** after the host
  decided it (limit 250 ms: the render delay, under both links); the client's living monsters are the host's at the moment it shows; a gate's burst exists on the client with the
  same ids (10000+), kinds and spots; the gate closes on the client within the death limit, leaves the open-gate list, the client's
  tracker shows the host's closed count and both Ledgers hold the gate's pay once; the cost (above), the biggest packet under 1.2 KB.
- `test_net_m3_objects` [off, coast] (3 processes): both clients hit the same priced prop at one shared moment: it breaks once on all
  three and is billed once at its price on all three Ledgers (the host applied three hits: the second on the prop found it broken);
  c1 smashes a crate and c2 a mail box (the host rolled a component): broken everywhere, the same contents and the same pickup id;
  both clients walk onto one pickup at one shared moment: exactly one gets its 3 charges (either one, depending on the frame), the
  other is refused, the pickup is gone everywhere, and every machine sees every hero's slots and charges as their owner has them;
  c1's E recruits an employee (FOLLOW, leader seat 2, on every screen, walking after c1's hero), its second E tells it to wait (every
  screen agrees with the host); the host loses one employee and extracts another: dead / extracted everywhere, the clients' trackers
  show the host's books, and every Ledger is the host's line for line.
- `test_net_m3_exit` [off, coast] (3 processes): both clients pick "go down" at one shared moment: one decision (by whichever reached
  the host first), seen identically on all three; everyone reloads onto floor 2 through the barrier with the same checksum (no
  desync), each hero's HP carried by seat; then the host and c2 clock out at once: one decision, every client shows the host's
  invoice (payout, earned, damages, floor, reason, number, stars) and its Ledger mirrors the host's to the dollar.
- `test_net_world_codec` (1 process): sizes; 120 randomised round trips per entry kind within one quantum; cut and random sections;
  every field of the three field tables through a real actor -> bytes -> puppet (and the puppet plays the flash, the wind-up ring, the
  swing, the mood); the worst-floor budget above.
- `test_net_contract`: carriers for the world (every monster kind, the hellgate, the employee, the priced prop, the crate, the mail box
  and the pickup: their OWNER vars ride `NetWorldCodec.*_FIELDS` or name their event in `NetEvents.WORLD_CARRIES`) and the budget
  constant check. No allowlist was widened.
- `test_net_m1_floor` changed in one check, on purpose: M1 asserted a client's copies "did not move or change" for 3.2 s; from M3
  they show the host's world, so it now asserts that after 3.2 s every copy stands where the host has it (0.6 units) with its HP.
- Unchanged and passing: every other M0-M2 net test (M2's 40-byte hero packet is measured on the hero part alone:
  `NetSnapshot.stats` counts the world separately in `world_out_bytes` / `packet_max`), `test_net_puppets` (copies are still inert
  without a session), and the solo suite. Full run: **All 96 test(s) passed.**

**Try it.** `.\run.ps1 -Crew 3 -Bot 1 --seed 7 --net-wait 3 --contract 1 --spells heal,corn --spawn-near grunt,5` (add
`-Link coast` for a coast-to-coast link): five skeletons chase the host's walking hero on all three screens; walk a client onto a
pickup, press E beside an employee, smash a crate (LMB), or open the elevator / the van (E) from any window: the first choice
takes the crew. `-ShotDir <dir> --shot-after 5.5` saves each window's picture.

**Known gaps (left for later, on purpose).**
1. **Combat across owners is M4.** A client's melee, arrows and spells do nothing to the host's monsters and gates (copies), and the
   host's monsters cannot hurt a client's hero (a puppet on the host). Only breakables route a hit to the host. A swing, a slam and an
   archer's arrow are SHOWN on a client (the strike count), harmless.
2. **Shoves on the world from a client** (Rebar's bowl through a crate, a hero shoved into a prop on its own screen) are not sent:
   `MailPackage` / `BreakableCrate` / `PricedProp._check_shove_contacts` run on the host only (M4, with shove requests).
3. **Spells' effects on the world**: a client's corn on a prop is a routed hit only because `Combat.explode` calls `apply_damage`;
   modifiers (vines on monsters, coffee) and burning are M4 (the target's owner applies them; `_modifiers` is in `WORLD_CARRIES`).
4. **Monster wind-ups are a snapshot field, not an event**: fine to look at (the telegraph grows on the client), but M4's "the victim
   decides" needs the wind-up event (start, length, victim). `target`, `_windup_total`, `_windup_left` name it in `WORLD_CARRIES`.
5. **The floor clock across a floor change**: a client's `GameWorld.time` jumps again at each floor's `crew.go` (the M1 rule), so a
   timer a client stamped on the old floor is in the old floor's time (nothing does today).
6. **A pickup's lifetime** runs on the host; a client's copy blinks on its own clock from the age the host sent (cosmetic).
7. **Late join (M6)** has more to replay now: the gone ids, the broken objects, the pickups, the employees' wait spots.
8. A hard kill is still noticed after `CLIENT_SILENCE` (10 s) and revival is still not a snapshot concern (M2 notes 6 and 9).
9. Hellgate spawns before the host's world stream starts (the van arrival) are announced at once (spawn events do not wait for the
   stream); a death in that window is shown when the client's stream starts.

**Notes for M4.**
1. **Route the verbs.** `Actor.apply_damage` on a copy already calls `Net.route_hit`; widen `Net.routes_hits` to monsters and gates
   ("the attacker decides") and add `shove` / `set_modifier` the same way. `NetObjects._host_request` "hit" is where the host applies
   it (add the shove, and an id for the spell/attack so a double send is dropped).
2. **The victim decides**: a monster's strike on a client's hero should be resolved on that client from a wind-up event. The host
   already counts `strikes` and knows `target`; send `world.windup {id, target, start, length}` and let the victim's machine run
   `Combat.melee_arc` against its own hero only (layer 4).
3. **Casts as events** will run effects on every machine: filter `Combat.melee_arc` / `explode` / `Projectile` hits to the targets
   this machine resolves (its own hero; the host for the world), or the routed hits above become double hits.
4. **Loadouts** already travel on pickups (`obj.loadout`); a cast's charge spend can reuse it or ride the cast event.
5. **Reuse**: `NetWorld` for any new host-owned mover (add a kind and a codec entry), `NetObjects` for any host-arbitrated object
   (a `request` kind and a grant), `Ledger.mirror` for money, `game._keeps_books` for host-only bookkeeping.
6. **Exits** (built here, early): M5 still owns the load-barrier polish (a fade on every machine at once, joining during a floor
   change) and the pause rules; the elevator's first-to-choose and the shared invoice are done.

### M4 as built (2026-10-18)
One session (M4a, M4b and M4c together). Everything in M4's "done when" passes under `off` and `coast`, and the run is playable
as the plan says: **the real game for two or three, on one floor**: every player's casts land on every screen at the same
moment, a client's swings, arrows and spells hurt the host's monsters (once), the host's monsters hurt a client's hero (decided on
that client, so what it dodged on its screen does not hit it), heals and support land once on the teammate they were aimed at,
teammates' corn, tentacles, spins and boulders throw each other around (into pits and props), and burning, damp, vines, coffee
and armor zones show on every screen as their owner has them.

**The one rule (layer 4).** Effects run on EVERY machine (a cast is scheduled everywhere, a hero's attack is replayed on its
puppet, a monster's wind-up is an event), and each machine applies only what it RESOLVES:
| Target | Hits (damage, a shove) | Statuses (modifiers, a heal, a fire, a soak, coffee) |
|---|---|---|
| a hero | its owner: **the victim decides** (rule 1) | its owner |
| anything else (monsters, gates, employees, props, crates, mail) | **the attacker's machine**, the owner of the source (rule 2); the host when the source is gone | its owner: the host |

`Net.resolves_hit(target, source)` and `Net.resolves(target)` are the two questions; every `Combat` helper (`melee_arc`,
`explode`, `shove_radius`, `each_in_radius`/`modify_radius`, the new `slam`, `heal_radius`, `hits_in_radius`) and
`Projectile`/`ArrowShot` ask them, and so do the spells' own loops (tentacles, teeth, the boulder, burning's ignition and
extinguish). Offline everything resolves, so solo play is unchanged. A hit the attacker's machine decides on something the host
owns goes through the verbs on the copy: `Actor.apply_damage` -> `Net.route_hit` (widened from M3's breakables to every
non-hero actor), `Actor.shove` -> `Net.route_shove`, `Actor.set_modifier` -> `Net.route_modifier`; the host applies its own and
passes a shove or modifier aimed at a player's hero on to that player's machine (rule 5; a rooted hero drops it there). A hit is
never routed to a hero: its owner decides it.

**Files.** `scripts/net/`: `net_casts.gd` (`NetCasts`, child `Session/Casts`: casts and hero attacks as events),
`net_status.gd` (`NetStatus`, child `Session/Status`: statuses from their owners); `net.gd` (`resolves`, `resolves_hit`,
`routes_hits` widened, `route_shove`, `route_modifier`, `hit_object`, `shares_cast`, `send_cast`, `hero_acted`,
`status_changed`, `note_hit`, and the guard: `apply_begin`/`apply_end`, `guard_write`, `guard_capture`, `guard_hits`);
`net_world.gd` (`world.windup`/`world.unwind`, client strike resolution, `pending_strike`, `resolved`); `net_objects.gd`
(hit requests on any host-owned actor, `shove`/`mod` requests and their pass-on, the client's prop-contact check, `hit_reqs`);
`net_session.gd` (the two children, the apply scope around every event and packet, the telemetry `hits` column);
`net_snapshot.gd` (apply scope); `net_events.gd` (carriers). Gameplay: `Actor` (guarded `hp`/`dead` setters, verbs that route
on a copy, `net_set_modifiers`/`modifiers_snapshot`, `slide_impact`/`stop_slide`/`shove_source`), `Combat` (the filter and
the new helpers), `Projectile`, `ArrowShot`, `BowlBoulder`, `Hero` (`_melee_effect`/`_arrow_effect`/`_bolt_effect`/
`_spin_effect` split out, `net_act`, `Net.hero_acted`; the spin's teammate shove is `Combat.shove_radius`), `SpellBook`
(`cast` resolves once and either sends or applies; `apply(caster, spec, start)`; `FOLLOWS`), `CornStrike`/`Tentacles`/
`ArmorZone` (`start_time` SPAWN; corn's `landed` signal), `Teeth`, `Burning` (owner rolls and ticks, `show_remote`,
announcements), `Coffee` (`show_remote`, `_remote`), `Monster` (`windup_begun`/`windup_dropped`, `net_strike`, `net_flash`,
the strike-visual dedupe), `Brute` (`Combat.slam`), `Hellgate` (a client throws its own hero at the gate's shove),
`PricedProp`/`MailPackage`/`BreakableCrate` (contacts checked by the slider's owner, `net_contacts`, `Net.hit_object`),
`VanArrival` (once the crew is out the van no longer pins them: it held every hero, puppets included, for another second, which
overrode a teleport or a puppet's stream), `game.gd` (begins/ends the two children; `--autocast` waits for the shared start,
`--autocast-after S`). Tests: `test_net_m4_casts`, `test_net_m4_hits`, `test_net_m4_status` (3 processes each);
`test_net_contract` (the area-loop rule).

**Casts as events (M4a, `NetCasts`).** The caster's machine resolves the cast once (`SpellBook.cast`: the target point, the
teammate the aim snapped onto, a fireball's launch point, direction and reach) and sends
`cast {c caster id, s spell, p power, t target, h followed hero id, x extra, at, ch}` (client -> host -> the other clients;
the host checks a client speaks only for its own seat). The caster plays the cast pose at once (and every other screen
does on arrival); the effect lands at `at` = the cast's host_time + `NetCasts.LEAD` (**0.2 s**, tunable) on every machine,
the caster's too, through `SpellBook.apply(caster, spec, start)` with `start` = the cast's moment in that machine's
`GameWorld.time` (a late arrival starts in the past: scheduled effects catch up, as Vines and Damp already did). `ArmorZone`,
`CornStrike` and `Tentacles` now take `start_time` as a SPAWN parameter like Vines and Damp. `heal` and `coffee` FOLLOW the
teammate the aim snapped onto (`SpellBook.FOLLOWS`: the effect lands where that teammate's owner has it, rule 3); every other
spell lands on the point (a teammate who sidesteps a corn is fine, rule 4). `ch` carries the caster's charges after the spend
(the `_charges` carrier for casts). Measured (`test_net_m4_casts`): a corn cast by a client lands on all three machines
2-17 ms after `at + LEAD + DELAY` on each one's own clock (a frame), and 3-13 ms apart in real time; no cast arrived late on
the host (max 11 ms after `at`, i.e. inside the frame) under `coast`.

**Hero attacks (`act`).** A swing, an arrow, a bolt, Rebar's bowl and Gasket's spin from a hero this machine owns (the
player's, and the host's AI heroes) go out as `act {c, a kind, d direction, r drawn, t}`; every other machine replays it on its
puppet when the puppet shows the moment `t` (`Hero.net_act`: the swing and the shot show; no cooldown, facing or other OWNER
field is touched). The attacker already decided every monster (rule 2), so the replay resolves only this machine's own hero:
that is how a teammate's spin or boulder throws you (rule 5: the victim applies the shove).

**Monster strikes: the victim decides (M4b).** `Monster.windup_begun(length)` / `windup_dropped` (shoved, staggered, the
target gone) become `world.windup {id, s, l, v victim}` / `world.unwind {id}` to every client. The host's own strike applies
only to the heroes the host owns (`Combat` skips a player's hero). Each client resolves the strike when ITS screen shows the
strike's moment (render time >= `s + l`, 20 ms early so the snapshot's strike count never plays it first): `Monster.net_strike`
runs the kind's own blow (a cleave, the brute's slam, the archer's real arrow) against its own hero only, from where it shows the
monster and where its own hero really is. The strike count in the snapshot then skips the look it already played.
Measured (`test_net_m4_hits`): the brute's slam on a client was resolved on that client (it lost 17.5, exactly one slam at that
distance, all of it in its own resolution); a second slam that client walked out of on its screen (2.45 from the brute there) did
not hit it, although the host showed it 1.47 from the brute at its strike. In 24 s of fighting the clients resolved 26-29 strikes
of 28-33 wind-ups in three runs (the rest were called off: shoved, staggered or the target gone).

**Statuses (`NetStatus`).** The target's owner applies and runs a status: a modifier (`Combat.each_in_radius` /
`modify_radius` filter by owner), a fire (`Burning.on_blast` rolls ignition only for the actors this machine owns, with its own
`GameWorld.rng`; only the owner ticks the damage), a soak and extinguishing (`Wet.douse_in_radius`,
`Burning.extinguish_in_radius`), coffee (its schedule and twitch on the owner), a heal (`Combat.heal_radius`). The owner announces
`st {id, k: "mods" | "burn" | "soak", v}` (owner -> host -> the others), flushed once a physics frame; a modifier is re-announced
only when its end moves by more than 0.2 s (an armor zone renews armor every 0.25 s), and copies keep each one 0.35 s past its
announced end, so nothing blinks. On a copy: the armor shield, a show-only `Coffee` (steam and ring), the vines' leg wraps,
flames that deal nothing (`Burning.show_remote`), drips (`Wet.douse`). Damp's puddles stay a pure function of the cast
(`Damp.plan_cells`), and `Damp.slide_mult` applies where the shove is applied (the shoved actor's owner).

**Props and shoves (`PricedProp` stops a slider).** A slide is its owner's, so the contact check runs on the machine that owns
the slider: the host for its actors (as before), a client for its own hero (the host's props, crates and mail are copies with no
physics there, so `NetObjects` calls their `net_contacts` while the hero is shoved). The hero stops dead against the prop on its
own screen (`Actor.stop_slide`; the prop no longer writes the actor's private slide state) and the impact goes to the host
(`Net.hit_object`, with the shove's culprit), which dents or breaks and bills the prop once. This replaces the plan's "message to
the slider's owner": the owner sees the contact itself, so nothing has to travel back.

**Runtime guard and agreement (M4c).** `Actor.hp` and `Actor.dead` have setters that, in a debug build while online, call
`Net.guard_write` when a COPY's value changes outside the net layer applying its owner's state (`Net.apply_begin/end` wrap
`NetSession`'s event and packet emission, the puppets' and the world's per-frame showing, the copies' look and a released seat's
last state). A violation is a `push_error` plus a failed `assert` (a SCRIPT ERROR: every test fails on it); `Net.guard_capture`
(a test seam) records it instead. The client-side strike resolution, the cast application and the attack replays run OUTSIDE
that scope on purpose, so the guard watches them. It never fired in any test run; the negative test trips it on both sides.

**Packets and events (all reliable; nothing new is unreliable).**
| Event | From -> to | Data |
|---|---|---|
| `cast` | caster -> host -> the other clients | `c`, `s`, `p`, `t` (Vector3), `h`, `x` (fireball: `o` origin, `d` dir, `r` reach), `at`, `ch` |
| `act` | owner -> host -> the other clients | `c`, `a` (melee / arrow / bolt / bowl / spin), `d` (Vector2), `r`, `t` |
| `st` | owner -> host -> the other clients | `id`, `k` (mods / burn / soak), `v` (`{mod: [mult, left, stat]}` or seconds) |
| `world.windup` / `world.unwind` | host -> clients | `id`, `s` (start), `l` (length), `v` (victim id) / `id` |
| `obj.req` gains | client -> host | `hit` on any host-owned actor; `shove {id, d, n, by}`; `mod {id, m, x, u, s}` |
| `obj.shove` / `obj.mod` | host -> the owner of a player's hero | the request, passed on |
The snapshot did not change. Telemetry's `hits` column (blank since M0) now counts the hits this machine's own heroes took.

**Bandwidth (measured, `test_net_m4_hits` under `coast`: three players fighting about 18 monsters sent at them for 24 s; the
host's telemetry CSV).** The snapshot is unchanged: **heroes 1.2 KB/s + world 1.9 KB/s down to each client** on average over the
test (the biggest packet stays under the 1.2 KB budget). Everything the host sends, events included, rose from about 5.5 KB/s
(two clients, quiet) to **7-13 KB/s during the fight, i.e. 3.5-6.6 KB/s per client**, at up to 26 reliable events a second out
of the host at the peak (casts, `act`s, wind-ups, statuses, Ledger lines and their relays). As serialised by `NetWire` (a Variant
dictionary, before the transport's own header): a cast 216 B (a fireball 300 B), an `act` 156 B, a status 172 B, a wind-up
136 B, a hit request 128 B. A client sends about **1.25 KB/s** up (its hero at 30 Hz plus its
casts, attacks and hit requests). The fight's totals: about 38 replayed attacks, 30 wind-ups, 13 casts, 44 hit requests, 7
statuses; the clients' telemetry counted 39 hits taken. The reliable events are Variant dictionaries (`NetWire`); if M7's
Steam measurements show the event rate matters, `act` and `world.windup` are the ones to hand-pack.

**What the tests prove** (three real-time processes each, `off` and `coast`).
- `test_net_m4_casts`: client A's corn at client B lands on all three within a frame of `at + LEAD + DELAY` on each machine's
  clock (measured 2-17 ms), within 13 ms of each other in real time; B, standing in it, loses exactly one corn (60) and takes one
  hit; every screen shows B's HP; the host is untouched; the host shows A's charges. A's heal aimed at B heals B once, by one
  heal (35), and nobody else. A's second corn: B walks out on its own screen 0.7 s before it lands; the host and A still SHOW B
  inside the ring (2.3-2.6 from the cob, the ring reaches 2.9) when it lands, B (3.15 away on its own screen) is not hit. The
  guard never fired.
- `test_net_m4_hits`: A's swing and arrow on a frozen grunt of the host's each reach the host once (exactly the swing's and the
  arrow's damage; one hit request each) and B shows the grunt's HP; the brute's slam on A is resolved on A, and A dodges the
  second on its screen (above); A's corn breaks a priced prop, billed once; then 24 s of all three fighting (swings, arrows,
  corn, fireball, heals) against monsters the host keeps sending: afterwards every machine shows every hero's HP and downed state
  as its owner has it, the same living monsters with the host's HP, the Ledger line for line, and every hit request a client
  sent arrived at the host once (40-42 of them); the guard never fired, and a deliberate write to a copy's HP trips it on the
  host and on a client.
- `test_net_m4_status`: the host's vines root B on B's machine and the others show the root and its wraps; the host's tentacles
  cannot move rooted B, and once the root is gone shove B once, out of the burst, where every screen shows it; B's fire (its own
  ignite) shows everywhere and ticks only on B (whole ticks); A's damp puts it out on B's machine and soaks B, shown everywhere;
  A's coffee hastes B (1.6x) on B's machine, shown with steam everywhere; the host's armor zone armors B, shown everywhere; B
  thrown into a priced prop on its own screen stops against it (0.95 from its centre instead of sliding on) and the host's prop
  takes the impact once.
- `test_net_contract`: rule 6, the area-loop rule (the M4 row of the table below): a loop over the actors in an area that calls a
  verb on them must ask `Combat.resolves` / `Net.resolves` in that loop; run against loops that must fail too. **No allowlist**:
  every loop in `scripts/` asks.
- Unchanged and passing: every M0-M3 net test and the whole solo suite (the guard is online-only, so the single-process tests
  that stand in for the net layer, like `test_net_world_codec`, are not affected).

**Try it.** `.\run.ps1 -Crew 3 -Size 1280x720 --seed 7 --net-wait 3 --contract 1 --spells corn,fireball --spawn-near grunt,5
--autocast fireball --autocast-after 1.0 --zoom 11` (add `-Link coast`): five skeletons come for the crew; once everyone is out of
the van every window casts a fireball at them (each lands on all three screens; the skeletons' damage is decided by the window
that cast it), and the skeletons' swings hurt whichever hero they reach, decided on that hero's own window: every window's HUD
shows the same HP for each player. `--autocast corn` instead drops three cobs on the pack, and on the crew standing in it
(friendly fire, each hero's own window deciding). In a live crew type `cast heal` (Enter) with the cursor on a teammate, or
`cast tentacles` beside them, and watch their window. `-ShotDir <dir> --shot-after 3.9` saves each window's picture.

**Known gaps (left for later, on purpose).**
1. **Disagreement is near misses, by design**: a fireball explodes on whatever it meets on each screen, so a monster the
   caster's screen showed in its path may be a step aside on the host's; the caster's screen decides the damage (rule 2) and the
   host's the ignition (the owner rolls). Teeth sprout on whoever each screen sees in the circle (the pop is resolved as a hit).
2. **The lead is fixed** (0.2 s). A cast that arrives later than that on some machine (a `rough` link) starts in the past there
   and catches up (a corn still lands on time; an instant spell lands late on that machine only). Measured lateness: none.
3. **A swarmer's 0.15 s wind-up** is still shorter than a client sees (the networking.md open risk): it is resolved fairly on the
   victim's machine, but the telegraph is mostly invisible there. M7 decides.
4. **A routed hit's HP drop** shows on the attacker's screen a round trip later (the hit flash is immediate, `Monster.net_flash`).
5. **No dedupe id on hit requests**: reliable events never duplicate, and only the attacker's machine routes (the filter), so
   the plan's "id per spell/attack" was not needed; the test counts requests sent against requests received.
6. **Coffee on a copy** shows the steam and the ring, not the twitch (that is the owner's motion, which the stream carries).
7. **The guard covers `hp` and `dead`** (the two fields the lint protects); other OWNER fields of a copy are only written by the
   net layer by construction, not checked at run time.
8. Late join (M6) must replay live statuses (`st`), pending wind-ups (they last under a second: skip) and active scheduled
   effects (skipped, as the plan says).

**Notes for M5.**
1. **Floor changes and casts**: `NetCasts`/`NetStatus` begin at the barrier and end with the scene, like `NetWorld`; a cast whose
   `at` falls after a floor change is dropped with the scene (fine). A load barrier per floor must call `Session.casts.begin()`
   and `Session.status.begin()` again (`game._enter_barrier` already does).
2. **Pause online** stays off (M3): the cast schedule runs on `host_time()`, which a paused tree would not stop.
3. **Hits taken per player** are now in telemetry (`hits`); M7's "keep them level" can read them.
4. **Reuse**: a new spell is a `SpellBook.apply` case plus, if it is scheduled, a `start_time` SPAWN param; a new status is a
   `Net.status_changed(actor, kind)` on the owner and a case in `NetStatus._on_event`; a new monster attack only needs `_strike()`
   to go through `Combat` (the wind-up event and the client resolution come with `Monster`).

### M5 as built (2026-10-18)
One session (M5a and M5b together). Much of M5 was already in place: M3 built the first-to-choose exits, the floor change
through the barrier (`crew.next`, a fresh `crew.go` per floor), HP and downed state carried by seat, the cash-out and van ending
with the host's invoice on every client, the host's authoritative Ledger with every client mirroring it, the host-only drop-offs
and extraction, and exit menus that freeze only your own hero; M1 built "no local pause while crewed". M5 adds what was left,
proves the whole loop end to end, and everything in M5's "done when" passes under `off` and `coast`. Playable as the plan says:
**a full contract online, from the board to the invoice and back to the board**, for a crew that started together.

**What M5 added.**
- **Back to the board, by anyone (decided).** A client's "Abandon contract" (the pause menu, or F5) and its "Next contract" on
  the invoice used to leave the crew / wait for the host. Now they are requests to the host: `CrewFlow.request_abandon()` sends
  `crew.abandon`, `request_again()` sends `crew.again`; the host's flow emits `abandon_requested(peer)` /
  `again_requested(peer)` and the host's game does exactly what its own press does (`_abandon_now`, `_on_next_contract`): it
  reloads onto a new board and its `crew.board` brings every client (M1's `_on_flow_board` -> `_back_to_board_local`). The
  host ignores an abandon once the job has ended and a Next while it is not on the invoice, so two presses at once make one
  board. The crew stays in the same lobby (the roster and the Steam lobby are untouched; the host's board sets the lobby back
  to "board").
- **"Next contract": any player's Next takes everyone (the choice M5 had to make).** Picked because it is the rule the crew
  already plays by (the first player to choose an exit decides) and it matches "anyone can abandon"; the cost is that a player
  still reading the invoice is taken to the board by a teammate's press (the invoice says so: "Takes the whole crew back to the
  board." under the row while crewed).
- **The board says who abandoned.** `crew.board` carries `note` (`CrewFlow.board_note`, cleared when a job is taken); the host
  sets it from the asking peer's roster name (`_board_note`, a static that survives the reload), and every board shows it in
  the red grease pencil on the side ("c2 abandoned the job", `JobBoard.notice`).
- **Pause online (decided, M1 had the mechanism).** `PauseMenu.online` / `hosting` (set by `game._open_pause` from `_crewed()`):
  the same FORM 27-B, titled "On break", status "ON THE CLOCK", a "LIVE" stamp, "Nothing is paused: the job runs on and only you
  stand still. Abandoning sends the whole crew to the board."; the rows' hints are "whole crew" (Abandon) and "ends the job"
  (host) / "leave the crew" (client) (Main menu). Solo, and a host alone in a lobby, keep the real pause and the old form.
- **Crew incapacitated (confirmed, one fix).** `_check_crew` already ran on the host over every hero, puppets included, whose
  `dead` comes from the owners' snapshots; a client only shows "Crew incapacitated" and waits for the host's invoice. Fixed: the
  revival lines are named by player while crewed (`game._crew_label`: the seat's owner's roster name; the AI seats and solo keep
  the hero's name). Before, three Wicks were billed as "Revival - Wick" three times, and the host's own hero was always "Wick".
- **The pause overlay closes** when an exit is decided or the job ends (`_on_exit_decided`, `_end_contract`, `_end_from_host`
  call `_close_pause`): online it is not modal, and it stayed under the invoice.
- `_on_next_contract` reloads through `_change_scene("")` like every other scene change (the same reload solo; the test seam
  saw `reload_current_scene()` reload the TEST scene instead).
- Dev: `--shot-at pause|invoice`, `--shot-floor N` (the floor picture after the elevator), `--pause-demo` waits for the shared
  start in a crew, `--auto-elevator` waits for the shared start (it opened the menu behind the barrier and its `_freeze(false)`
  unfroze the world early), and the dev crew teleports (`--to-exit`, `--to-gate`, ...) place heroes in SEAT order (they used the
  local player first, so every machine put different heroes on the cells and the floor checksum disagreed; solo is the same order
  as before).

**Files.** `scripts/net/crew_flow.gd` (`board_note`, `request_abandon`, `request_again`, the two signals, `crew.abandon`,
`crew.again`, `note` on `crew.board`); `scripts/app/game.gd` (above); `scripts/ui/pause_menu.gd` (`online`, `hosting`),
`scripts/ui/invoice_screen.gd` (`next_note`), `scripts/ui/job_board.gd` (`notice`); test support
`scripts/test_support/net_game_test.gd` (`place_hero`, `cell_at`, `press_esc`, `canon`, `invoice_text`, `ledger_text`,
`peer_named`; `board()`, `picker()` and `wait_floor()` are safe while a reload is under way). Tests: `test_net_m5_contract`,
`test_net_m5_crew` (3 processes each).

**Events (reliable; the protocol version did not change).**
| Event | From -> to | Data |
|---|---|---|
| `crew.abandon` | client -> host | (empty): this player abandons the contract for the crew (ignored on the board and once the job has ended) |
| `crew.again` | client -> host | (empty): this player pressed "Next contract" on the invoice (ignored unless the host is on the invoice) |
| `crew.board` gains | host -> clients | `note`: a short line every board shows ("" for none) |
Nothing else changed on the wire: the exits (`obj.exit`), the floor change (`crew.next` / `crew.ready` / `crew.go`), the money
(`obj.ledger`, `obj.contract`) and the invoice (`obj.end`) are M3's.

**Followers and the elevator.** "Riding the elevator" is extraction, as solo (contracts.md): employees FOLLOWING the crew within
`FOLLOW_EXTRACT_CELLS` (3) of the exit being used are extracted, $100 each, and do not appear on the next floor; one within
`DROPOFF_DIST` (2.5 units) of the van door or the elevator leaves at once (the drop-off). Both are decided on the host only
(`_descend_shared`, `_use_elevator`, `_use_van`, `_check_dropoffs` run there), whoever the employee follows; the extraction reaches
the clients as `world.extract`, the pay as Ledger lines.

**What the tests prove** (three real-time processes each; this machine's timings).
- `test_net_m5_contract` [off 20.0 s, coast 21.8 s]: each owner marks its hero's HP (78 / 71 / 64 by seat). c1 and c2 stand at the
  elevator and press **E in the same frame** (the controller's `press_use`, the menu's own "go down" row): ONE decision (by
  whichever reached the host first), ONE floor change (every process reloaded exactly once), floor 2 is the same floor everywhere
  (checksum) and every process shows every seat's carried HP. On floor 2 an employee follows c1's hero two cells from the elevator
  and the host takes the elevator: the follower rides out (extracted by the host, one $100 line), and on floor 3 every client's
  Ledger is the host's line for line. On floor 3 c2 presses E and cashes out: every process shows the **same invoice dict**
  (canonical JSON, every key: lines, floors, blame, employees, payout, stars, date). c1 presses "Next contract": all three are
  back on the host's new board (same seed), with no contract, no Ledger mirror, the crew still three. Contract 2 (offer 0, every
  license signed by hand): **c1 clocks out at the van on floor 1** (E at the van door, the slip's row): the contract ends for
  everyone with the same invoice. The host then quits with the clients on the invoice: both are told "The host clocked out" and
  their game asks for the main menu.
- `test_net_m5_crew` [off 18.0 s, coast 19.6 s]: **Esc on c2** opens the online pause menu and the tree is NOT paused: c2's floor
  clock ran 0.6 s behind the menu, the world is not frozen, only c2's hero stopped, the form's rows say "whole crew" / "leave the
  crew"; the same on the host ("ends the job"), and Resume closes it. **c2 picks "Abandon contract"**: the host and both clients
  are back on a new board (reloaded once each), the contract dropped, the crew still three, and every board says "c2 abandoned the
  job". Contract 2: every player's hero goes down on its own machine at one shared moment: the host decides **crew incapacitated**
  from the replicated `dead`, bills **three revivals of $10,000** named host / c1 / c2 (payout -$30,000: uncapped, negative), every
  client saw the crew down, shows the host's invoice key for key and holds the same Ledger, revival fees and payout. **The host's
  "Next contract"** takes everyone back to the board (the board note cleared). The host then quits with the crew on the board: the
  clients go to the menu with "The host clocked out".
- Single-player is unchanged: `test_main_menu` (the real pause, Abandon, Main menu), `test_contract_flow_game` (the elevator, the
  invoice, revivals by hero name) and the rest of the suite pass as before. M3's `test_net_m3_exit` still covers two choices sent
  through `_choose_exit` at once (the same rule, without the keys) and is unchanged.

**Try it.** `.\run.ps1 -Crew 3 --seed 7 --net-wait 3 --contract 1 --spells heal,corn` (add `-Link coast`): walk to the elevator in
any window and press E: whoever picks a row first takes the crew down (every window reloads onto floor 2 behind the barrier);
Esc in a client window: the menu opens and the game keeps running; "Abandon contract" there sends all three windows to a new board
that says who did it; at the end, "Next contract" in any window takes all three back to the board. Screenshots of client windows:
`--shot <png> --shot-at floor --shot-floor 2` / `--shot-at pause --pause-demo` / `--shot-at invoice` on that window, with the
same `--van-intro` (or `--no-van-intro`) and dev teleport flags on every window (they decide where the heroes stand, which is in
the floor checksum).

**Known gaps (left for later, on purpose).**
1. **Abandon has no confirm**: one press ends the job for the whole crew (decided: anyone can abandon). F5 on a client now
   abandons for everyone too (it used to leave the crew); a client leaves through the pause menu's Main menu.
2. **No shared fade**: each machine fades out when it learns the decision and fades in on its own reload; the floor itself
   starts at one shared moment (`crew.go`). M3's note had "a fade on every machine at once"; it is cosmetic and left.
3. **A client's objective mirror can miss one update during a floor reload** (`obj.contract` arriving between the old scene and
   the new one): the tracker catches up at the next change and the invoice is the host's dict, so nothing visible is wrong.
4. **"Crew incapacitated" on a client** is shown from its own view (about 100 ms behind for the others' heroes); the host's view
   decides the end and the bill.
5. **A crashed host** is noticed after `CLIENT_SILENCE` (10 s); a host that quits is noticed at once (M2 note 6).
6. **Mixed screenshot flags desync a crew** (`--shot` skips the van arrival, `--to-exit` moves heroes): dev only; pass the same
   flags to every window (above).
7. Joining mid-contract (M6) is still refused (`JOB_RUNNING`), including on the invoice.

**Notes for M6.**
1. **Where a joiner can arrive.** On a floor (the plan), during a floor change (wait for the next barrier: `CrewFlow._judge` waits
   for a checksum from EVERY roster member, so a joiner mid-`LOADING` must either build that floor or be left out of the wait),
   or on the invoice (simplest: refuse until the board, or put them on the host's next board: `_on_peer_joined` already sends
   `crew.board` with the note).
2. **Seats and names.** `_seat_info` is taken at the job pick and only refreshed at a barrier (`_drop_departed_seats`); a handover
   must update it (`_begin_hero_sync` reads it every floor). Revival names read `Session.seats.owners` (`_crew_label`), so a joiner
   who took a seat is billed by name once the seat table says so.
3. **The static run state** (`_run`, `_session`, `_spells`, `_board_seed`, `_board_note`, `_dev_released`, `_fade_in` in
   `game.gd`) is what survives a reload; a joiner builds `_run` from `Flow.job` (as a client does) and its `_session` from the
   host's mirror (`ContractSession.apply_mirror`, carry by seat) plus every Ledger line so far.
4. **Pause and abandon need nothing new**: a joiner is crewed, so its Esc does not pause and its Abandon / Next go to the host.
5. **Test pattern.** `test_net_m5_*` drive whole contracts through the game's own keys in about 20 s; `NetGameTest.place_hero`,
   `cell_at`, `invoice_text` / `ledger_text` (canonical JSON) and the reload-safe getters are there for the late-join test.

### M6 as built (2026-10-18)
One session. Everything in M6's "done when" passes under `off` and `coast`, and the run is playable as the plan says:
**drop-in, drop-out co-op**. A player who joins a crew on the job sees "Clocking in..." until the crew is on a running floor,
then arrives in one of the AI's seats: the same hero node becomes their character at full health, with the AI's spells,
charges and spot, and every screen says "<name> takes over Gasket's seat." A fourth player is told "Crew is full"; a player
who leaves gives the seat back to the AI (M2b).

**Files.** `scripts/net/`: `net_join.gd` (new: `NetJoin`, child `Session/Join`, `Session.join`: the joiner's wait, the floor
it is sent onto, the checksum check and the late-join snapshot), `seat_handover.gd` (`choose_seat` / `pick_seat`, `take`,
`take_local`, `hero_state` / `apply_state`, `apply_table` / `table`, the `to_player` signal, `seat.take`, `kind` in
`history`), `net_session.gd` (a hello mid-job is admitted as a joiner instead of refused; `seats_free()`; the `join` child),
`crew_flow.gd` (`is_joining`; joiners are skipped by every wait and get none of the barrier's events, `_to_members`;
`job_ended` / `host_job_ended`; `floor_n` / `floor_seats` / `note_floor`; `join_floor`), `net_snapshot.gd` (`seat_taken`, the
epoch on every sample and `epoch_current`), `net_codec.gd` / `net_hero_state.gd` (the epoch in the flags byte),
`net_world.gd` (`keyframe`, `runtime_spawns`, `apply_spawns`, `apply_keyframe`; a quiet spawn replay; a monster spawned
outside a gate no longer errors on its missing `from_gate` meta), `net_objects.gd` and `net_status.gd` (`late_join_state` /
`apply_late_join`), `net_registry.gd` (`seed_top`, set by `NetFloor.assign_ids`), `net_events.gd` (`KIND_SEAT_TAKE`,
`LATE_JOIN`). Gameplay: `Hero.become(..., full)` (a joiner arrives at 100%, standing even from downed),
`Ledger.mirror_all`. UI: `scripts/ui/clock_in_slip.gd` (new: `ClockInSlip`, FORM 12-C "Clocking in..."). Game: `game.gd`
(the joiner's path: `_on_join_changed`, `_join_floor`, `_joined_seats`, `_on_join_snapshot`, `_refresh_join_slip`; every
machine's `_on_seat_to_player`; the host's `_on_join_ready` and `note_floor` at its barrier; joiners skipped in `_crew_seats`
and `_assign_crew_spells`; a shared floor change no longer opens the license picker for a player who holds no spells; dev flags
`--join-hold S`, `--shot-at clockin|takeover`; `_seat_notices` test seam). `run.ps1 -JoinLate S`. Test support:
`NetGameTest` flag files (`raise_flag`, `wait_flag`, `clear_flag`: a player who has not joined cannot be sent a command) and
`living_text`. Tests: `test_net_m6_late_join`, `test_net_m6_join_flow` (4 processes), `test_net_m6_join_license`;
`test_net_seats` (the seat order, `become(full)`), `test_net_codec` (the epoch), `test_net_contract` (late-join coverage), `test_forms` (the
"Clocking in..." form).

**Where a joiner can arrive (decided here).** The hello is admitted whenever the roster has room and the crew is on a job
(`crew_state == "job"`; on the board it is M1's plain join). The joiner is a roster member with `joining` true and a seat
that is still the AI's. Nobody waits for it (CrewFlow's license and barrier waits skip it) and it gets none of the barrier's
events (`crew.job`, `crew.load`, `crew.next`, `crew.go`), so every floor built meanwhile builds its seat as the AI on every
machine (`_crew_seats` skips joiners: the checksums agree). NetJoin sends it onto a floor only when the crew is on a RUNNING
one: CrewFlow FLOOR, the hero sync live (the van arrival is over, so the AI is out of the van), the job not over, no exit
taken. So:
| The crew is... | The joiner |
|---|---|
| on the board | joins the board as in M1 (an ordinary member) |
| signing licenses | waits ("signing licenses"); arrives on floor 1 after the van arrival; signs no license |
| on a floor (after the van arrival) | arrives within a second or so |
| in the van arrival | waits ("stepping out of the van") until it is over |
| changing floors | waits ("riding the elevator"); arrives on the NEW floor once it has started (a build for the old floor is dropped: its ticket is stale) |
| on the invoice | waits ("reading the invoice"); the next `crew.board` (anyone's Next contract) makes it an ordinary member on the board |
| a host playing solo (no crew when it picked) | waits ("on a job alone"); starts together at the next board |
An abandon sends the joiner to the board with everyone (`crew.board`); a joiner that leaves while waiting is simply
forgotten; a joiner whose checksum differs is sent out with "Desync: different floor" as at a barrier.

**Which AI.** `SeatHandover.choose_seat`, the plan's order: an AI already playing the joiner's character, then the LIVING AI
with the most HP (absolute; tie: the lower seat), a downed AI only when none is alive. It is applied when the hello is
admitted (the roster needs a seat) and AGAIN when the joiner is sent onto a floor (`join.go`), so the order holds at the
moment the seat is reserved; the roster seat follows (`set_members`). Between floors (no heroes to look at) it is the lowest
free seat. The joiner keeps its character id (Wick today; duplicates are fine).

**The handover.**
1. `join.go {ticket, job, floor, seat, seats, start_at, floor_start}`: the seat table is the one the host built THIS floor
   with at its barrier (`CrewFlow.floor_seats`, after any departed player's seat went to the AI), with the joiner's seat as
   its own hero. The joiner builds the floor from the seed exactly as at the barrier (dev flags included; the van parked and
   skipped after the checksum), every hero a puppet of the host's stream (its own too: the AI still has it) and every
   host-owned thing a copy, and takes the checksum.
2. `join.built {ticket, sums}`, sent only once the joiner's clock has synced (a fast joiner builds before its first pong). The
   host compares with ITS barrier checksum (`CrewFlow.local_sums`).
3. On a match the host's game answers `built_ready` with `NetJoin.admit(peer, {contract})`: in ONE frame it takes the AI hero's
   state (`SeatHandover.hero_state`: position, facing, slots, charges, cooldowns left, held slot, modifiers, fire, soak),
   sends the snapshot to the joiner, then `SeatHandover.take`: the epoch goes up, `to_player` re-kits the same node as the
   joiner's character at full health and frees the `AllyBrain` (the AI stops at this tick), NetSnapshot makes the hero a
   puppet of the joiner's stream, every other client gets `seat.take {seat, peer, character, epoch, state}`, and the roster
   entry becomes an ordinary member (`joining` false, `spells` the AI's, so the next floor's build agrees everywhere).
4. The joiner applies the snapshot in order: the floor clock first (`CrewFlow.join_floor`: one jump of `GameWorld.time`, then
   the slew), the seat table, the game's part (`snapshot_received`: the objective mirror, every other seat's kit and player
   name as it is NOW), the other heroes' states, the gone ids, runtime monsters, the keyframe, the employees' wait spots,
   pickups, dents, statuses, the Ledger, and last its own seat (`take_local`: the same re-kit, then the hero is live here with
   the handed-over state). The floor starts on the next frame (`floor_started`, start_at is in the past); control comes back
   then.
**The ownership epoch** rides every hero sample in the flags byte's free high nibble (bits 4-7, mod 16: no extra byte, the
24 / 40-byte packets are unchanged). A receiver drops a sample from an OLDER epoch than it knows for that seat (wrap-aware,
`NetSnapshot.epoch_current`); a newer one is taken (the reliable handover event is behind it). The host also still takes a
client's state only for the seat that client owns. On a handover every other screen empties the puppet's buffer.

**The late-join snapshot (`join.snapshot`, one reliable event).**
| Part | What |
|---|---|
| `start_at`, `floor_start`, `at`, `job` | the floor clock and the moment (every time below is on it) |
| `seats` | seat -> [owner, epoch] |
| `kits`, `heroes` | each seat's kit and player name; every other hero's position, facing, HP, downed, slots, charges, held slot |
| `gone` | the seed-built ids (ID_BASE .. `NetRegistry.seed_top`) gone on the host: `die` (show it dead: a closed gate, a broken prop or crate, a lost employee) or `free` (remove it quietly: a dead monster, an extracted employee, an opened mail box, a used pickup) |
| `spawns` | every runtime monster alive: a quiet `world.spawn` replay (no burst); a runtime monster the joiner heard spawn but that is not listed died before the snapshot and is removed |
| `world` | a full NetWorldCodec section of every surviving monster, employee and hellgate (`NetWorld.keyframe`, no budget); it goes into the puppets' buffers (not the stream's delay) and the positions are set at once |
| `waits` | the employees told to wait: their wait spots |
| `objects` | every pickup on the floor (an `obj.pickup` replay with charges and age; a seed-built one keeps its id) and every dented prop's HP |
| `status` | every live status as its owner last announced it: `[id, mods, burn, soak]` |
| `ledger` | every Ledger line (`Ledger.mirror_all` replaces the mirror: lines that came before the snapshot are in it) |
| `take` | the joiner's own seat: seat, character, epoch, the hero's state |
| `contract` (the game's) | `ContractSession.mirror_state()` |
Not in it, as planned: scheduled effects in flight and monsters' wind-ups (under 2 s; a wind-up in progress is simply not
resolved on the joiner), grime decals. Events about the floor that reach the joiner before the snapshot (it is in the roster
while it builds) are harmless: the snapshot is later on the same ordered channel and replaces or skips what they did.
**Measured size** (as `var_to_bytes`, before the transport's header): 3.9 KB on floor 2 of `test_net_m6_late_join` (45
keyframe entries, 5 gone ids, 2 runtime monsters, 2 Ledger lines), 2.8 KB at the start of a floor (`test_net_m6_join_flow`).
The keyframe costs 16 / 15 / 7 bytes an entry; a gone id about 20; a Ledger line about 150. A worst floor (85 entries, every
seed-built id gone, 40 Ledger lines) stays near 10 KB: one reliable message, which ENet fragments and Steam's 512 KB message
limit should take whole (to confirm on real Steam, M7), so no fragmentation of our own was needed. **Ready to seat:** 47-62 ms (`off`), 127-171 ms (`coast`):
one round trip plus a frame.

**Events (all reliable; the protocol version did not change).**
| Event | From -> to | Data |
|---|---|---|
| `join.wait` | host -> a joiner (on its hello, and whenever the reason changes) | `note` (what the crew is doing, for the form), `job`, `floor` |
| `join.go` | host -> a joiner | `ticket`, `job`, `floor`, `seat`, `seats` (the barrier's table), `start_at`, `floor_start` |
| `join.built` | joiner -> host | `ticket`, `sums` (NetFloor.checksum) |
| `join.snapshot` | host -> the joiner | above |
| `seat.take` | host -> every other client | `seat`, `peer`, `character`, `epoch`, `state` |
| `sys.roster` entries gain | host -> crew | `joining` (true until the seat is taken; cleared by `crew.board` too) |
`sys.refuse {reason: "That crew is already on a job"}` is no longer sent (the constant stays for the logs); "Crew is full" is
unchanged. The lobby's `seats_free` is `NetSession.seats_free()` (every member holds a seat; 0 = full), published on every
join and leave, and "Join a crew" already skips `seats_free == "0"` (M0).

**UI.** "Clocking in..." is a white FORM 12-C on a clipboard (`ClockInSlip`, like the pause form): the crew ("host's crew"),
the job (company and invoice number), the floor ("2 of 3"), the seat ("Gasket's, seat 3"), typed in as they become known, and
one short line: what the crew is doing, "Building floor 2...", "Catching up with the crew...". Its only row is "Leave the
crew" (Esc). Every screen shows "<name> takes over <character>'s seat." in the HUD's message line when a seat changes hands
("You take over Gasket's seat." on the joiner's).

**What the tests prove** (real-time processes; this machine's timings).
- `test_net_m6_late_join` [off 31 s, coast 33 s] (3 processes): the host and c1 go down to floor 2 and play it for 15 s (two
  monsters killed, a prop broken and one dented, a hellgate closed, an employee lost, two monsters spawned at run time, a
  pickup dropped, the host armored, the AI in seat 3 hurt and given heal and vines); then c2 joins. c2 showed "Clocking in...";
  its checksum is the host's floor-2 barrier checksum; its gone ids and its living host-owned actors equal the host's at the
  snapshot (the runtime monsters included); it controls seat 3 (live, its controller on) where the AI stood (within 1 cm), at
  100% HP, standing, as Wick, with the AI's spells and charges, 47-152 ms after reporting ready (limit 1 s); it shows the host's
  armor, the pickup and the dent; the host's AllyBrain is gone and it shows seat 3 as c2's puppet (Wick, "c2", full HP); the
  host, c1 and c2 each say who took Gasket's seat. A second later the living actors and the Ledger are equal line for line and
  c2 shows the host's monsters within 1.2 units (the render delay); c2 walks and the host shows seat 3 where c2 has it (0.3).
  c2 leaves: seat 3 is Gasket again on the host (AllyBrain, live) within a fraction of a second, and on c1.
- `test_net_m6_join_flow` [off 16 s, coast 17 s] (4 processes): c2's connection opens and the host takes the elevator at once,
  so c2's hello is admitted while the crew is LOADING floor 2: c2 is joining, floor 2 starts without waiting for it, c2's form
  said the crew was riding the elevator, and it arrives on floor 2 (not 1) with the host's checksum, in seat 3. With three in,
  c3's hello is refused "Crew is full", `seats_free` is 0, and nothing on the floor changes (owners, kits, names, epochs). c2
  leaves (Gasket back, `seats_free` 1); the crew cashes out; c3 joins on the invoice: it waits ("reading the invoice"), builds
  no floor and is not admitted to the finished job; the host's Next contract puts c1 and c3 on the same new board, c3 an
  ordinary member.
- `test_net_m6_join_license` [off 12 s, coast 13 s] (3 processes): c2 joins while the host and c1 are in their license checkouts: nobody
  waits for it, floor 1 starts with seat 3 as Gasket, c2 is not sent in during the van arrival, then arrives on floor 1 with
  the host's checksum (its van parked, the arrival skipped), in seat 3; it never opened a license checkout.
- `test_net_seats`: the seat order on plain data (most HP, the tie, the joiner's character first, downed passed over unless all
  are, the lowest free seat between floors, none when full); `become(..., full)` stands a downed hero up at 100%.
- `test_net_codec`: the epoch survives every round trip (the packet sizes are unchanged).
- `test_net_contract`: rule 7, late-join coverage (`NetEvents.LATE_JOIN` names a way for every replicated class; run against
  tables that must fail). No allowlist was widened.
- `test_forms`: the "Clocking in..." form (focus on its one row, values typed in, a dash for unknown, Leave the crew).
- Unchanged and passing: every M0-M5 net test and the single-player suite. One flake seen: `test_net_m3_objects` [coast]
  failed 2 of 21 runs on this build at "c1's second E told it to wait, on the host" (the employee's wait request is judged
  from where c1 says it stands, next to a follower that is ~150 ms behind on c1's screen); the baseline (M5) passed 10 of 10,
  and no M6 path runs in that test (no joiner, every epoch 0), so it is noted rather than changed.
  Full run: **All 112 test(s) passed.**

**Try it.** `.\run.ps1 -Crew 3 -JoinLate 25 --seed 13 --net-wait 2 --contract 1 --spells heal,corn` (add `-Link coast`): the
host and Crew2 take the job; 25 s later the third window joins mid-floor, shows "Clocking in...", and takes over the AI's seat
(every window says so). Close the third window: the AI takes the seat back. Start it again while the crew rides the elevator, or
sits on the invoice, to see it wait. Screenshots: `-ShotDir <dir> --shot-at takeover --shot-after 2.5` (every window, 2.5 s
after the handover; add `-Bot 3` to see the joiner walk) or `--shot-at clockin --join-hold 4` (the joiner's form).

**Known gaps (left for later, on purpose).**
1. **A joiner inherits the AI's spells** (the plan: no license mid-contract). The AI heroes cast nothing and usually hold no
   spells, so a joiner usually arrives with empty slots until a pickup, a later contract's license, or the dev `--give-allies`.
   A license on arrival (or giving the AI seats licenses) is a design call for the user.
2. Scheduled effects in flight and monster wind-ups are not in the snapshot (planned: under 2 s); grime decals are missing;
   an opened mail box's spill debris is not rebuilt (the box is just gone); the kill counter and logs start at the join.
3. A joiner's build must reproduce the barrier exactly, dev flags included (`--spawn-near`, `--to-*`, `--drop-near` pickups are
   placed next to the joiner's own hero, not the host's: their positions differ, which only a dev run notices). Real play has
   none of them. A different checksum sends the joiner out with "Desync: different floor".
4. A hard-crashed joiner is noticed after `CLIENT_SILENCE` (10 s), as for any client (M2 note 6).
5. The epoch is mod 16 on the wire: more than 7 handovers of one seat while a stale packet is in flight would be misread; a
   floor has a handful at most.
6. Invites (`join_requested` mid-game) still leave the current session and join without asking (M7), but a crew on the job now
   takes the invited player in.

**Notes for M7.**
1. **Steam checklist item 4** ("B joins mid-floor 2 and takes an AI seat; B quits and the AI takes it back") is now buildable;
   check the lobby's `seats_free` filter there (a full crew must not be listed) and the snapshot's size over Steam's relays.
2. **Character select** only has to set `Session.character_id`: the hello and the roster carry it, `choose_seat`'s first rule
   (an AI already playing that character) and the re-kit (`CREW_LOOKS`) use it.
3. **Voice debug per player**: a joiner builds its voice caster with the floor; nothing in M6 touches it.
4. **Telemetry**: a join could log its wait, build and ready-to-seat times on the host (`NetJoin.admitted` has them).
5. **Reuse**: a new replicated class needs a `NetEvents.LATE_JOIN` entry and, if it has state the seed does not rebuild, a
   part in the snapshot (`late_join_state` / `apply_late_join` is the pattern in NetObjects and NetStatus).

---

## 3. Test strategy

### The multi-process harness (built in M0b)
Cast can't put two worlds in one process (`GameWorld` and `Ledger` are autoloads), so each peer is **its own headless
Godot process**, which is also what the user wants agents to be able to run.
- **Naming:** `tests/test_net_*.gd` that declare `const PEERS := 2` or `3` are net tests. Everything else is
  unchanged.
- **Launch:** `test_runner.ps1` gives each net test a free port (28000 + slot) and starts the host
  (`--run-test X -- --net enet --net-role host --net-port P --net-peers N [--net-link coast]`), then N-1 clients
  (`--net-role client --net-index i`). Logs go to `test_logs/X.host.log`, `X.c1.log`, and so on.
- **Real time, not lockstep.** Each process runs `--fixed-fps 60` (deterministic deltas) and the harness sets
  `Engine.max_fps = 60` so game time tracks wall time. The clock sync, the interpolation buffer and the link
  simulator only mean anything in real time; lockstep would hide exactly the bugs Bridge shipped. Assertions are
  "within T seconds" polls and comparisons at a shared `host_time`, never "on frame N".
- **Scheduling:** net tests run in their own group, at most 2 at a time, after the parallel batch (like the voice
  audio tests), so starved CPUs don't fake lag. `-TestAll` runs each net test twice: `off` and `coast`.
- **The host is the judge.** Every process runs the same script with its role. Clients send
  `NetProbe.report(key, value, host_time)` on a test-only reliable event; the host asserts `agree(key, tolerance)`;
  a client's own `check()` failures are forwarded. Each side keeps a 2 s ring of its entities' poses keyed by
  `host_time`, so "what did the client draw at T" can be compared with "where was it at T - delay" on the owner.
  The host prints the one `[TEST PASSED]` marker after every client reports `done`. Clients quit when the host says
  so or the host disappears.
- **Pass rule:** every process exits 0, the host log has the PASS marker, and **no** `SCRIPT ERROR` in any log.
  The runner kills every process of a test at its timeout.
- **Bots:** `NetBot` drives a role through seams that already exist (`PlayerController.aim_override`,
  `press_use()`, `cast_spell()`, `VoiceCaster.inject_text`) plus one new seam: a scripted move intent. Instances use
  `--no-mic` (one mic and three speech models on one box is neither realistic nor cheap).

`NetGameTest` (M1, `scripts/test_support/net_game_test.gd`) is `NetTest` with a real `game.gd` under the test on every process: the board and
the license checkout are driven through their own screens, scene changes are recorded (a seam) instead of done.

### Agent and manual local play
`run.ps1 -Crew 2|3 [-Link coast]` launches 2-3 **windowed** instances over ENet localhost, tiled, with `--no-mic` on
all but the first. `--shot` works per instance, so an agent can screenshot every screen at the same `host_time`.

### Single-process tests (cheap, run in the normal parallel batch)
`test_enet_loopback`, `test_net_session`, `test_net_puppets` (built in M1: a copy never changes a `PRIVATE`/`OWNER` field),
`test_net_codec` (M2: round trips, budgets, every carried field), `test_net_interp` and `test_net_seats` (M2), `test_net_floor` (built in M1: the checksum and ids), `test_net_board` (M1: the read-only board, the confirm), `test_net_world_codec` (M3: the world entries, every carried field through a real actor, the packet budget on the worst floor).

### Lag and loss
- **ENet:** `net_link.gd` on every process's inbound side, covering both directions: `coast` = 45 ms ±15 ms, 1.5%
  loss on unreliable traffic; reliable traffic is delayed, never dropped.
- **Steam:** `FakePacket*` config values, used only in manual runs (the Steam peer's send-mode mapping can't be
  exercised over ENet).
- **Soak** (`test_net_soak`, manual or nightly): 5 minutes, 3 processes, `rough`. Fails if any telemetry level
  **climbs** (snapshot age, pending reliable bytes, bytes per second, render error). That is Bridge's "worse over
  time", caught by a test.

### How `test_net_contract` grows
| Added in | Check |
|---|---|
| M0 | `Steam` singleton / `ClassDB` Steam use only in `scripts/net/`; `send_bytes` must name `TRANSFER_MODE_UNRELIABLE` |
| M2 (built) | **Carrier coverage, driven by `net_fields()`**: every `OWNER` field of every checked class has a carrier, either in that class's codec field list or in `NetEvents.CARRIES` (event-carried, e.g. `dead`). A codec that streams a `SPAWN`/`PRIVATE`/`LOCAL` field fails. A new `OWNER` var without a carrier fails the build, so content can't silently go unreplicated. |
| M2 (built) | Codec round trip for every codec (randomised entity, pack then unpack, equal within its quantum): `test_net_codec` |
| M3 (built) | Size budget: the host's packet fits 1.2 KB by construction (test_net_contract); test_net_world_codec fills it with the worst floor 3 it finds (every actor alive and moving: 1194 B) |
| M3 (built) | Carrier coverage for the host-owned world: every monster kind, hellgate, employee, priced prop, crate, mail box and pickup (NetWorldCodec field tables, NetEvents.WORLD_CARRIES) |
| M4 (built) | Lint: an area loop over actors that calls `apply_damage`/`shove`/`set_modifier`/`heal` must ask `Combat.resolves` / `Net.resolves` (rule 6; no allowlist) |
| M6 (built) | Late-join coverage: every replicated class declares how a joiner gets its state (`NetEvents.LATE_JOIN`: keyframe, gone ids, an event replay or the seat handover); run against tables that must fail |

### Real Steam (manual checklist, two PCs and two accounts)
1. Both on the same build; A: **Start a job**; B: **Join a crew** finds it. A different build is refused with a reason.
2. Invite from the overlay while B's game runs, and while it's closed (`+connect_lobby`).
3. Three players: walk, fight, cast at each other, go down a floor, invoice.
4. B joins mid-floor 2 and takes an AI seat; B quits and the AI takes it back.
5. A (host) quits: B and C land on the menu with "The host clocked out".
6. The `coast` fake-lag preset for 20 minutes; read the host's telemetry CSV: RTT, jitter and pending bytes stay flat.
7. Voice: each player's casts work from their own mic; nobody's casts fire on another machine twice.

---

## 4. Effort and order

| Milestone | Sessions | Playable after it |
|---|---|---|
| M0 Transport and lobby | 2 | Host/Join/invite builds a crew in the lobby; drops are handled |
| M1 Shared run | 2 | Everyone picks spells and stands on the same floor (nothing moves) |
| M2 Hero sync | 2 | **Two or three players walk around the same floor**; a dropped player's hero becomes AI |
| M3 Host-owned world | 3 | Live monsters, gates, employees, pickups and props for everyone |
| M4 Spells and combat | 3 | **The real game on one floor**: fighting, casting, shoving |
| M5 Contract flow | 2 | **A full contract online**, board to invoice |
| M6 Join mid-contract | 2 | Drop-in, drop-out on any floor |
| M7 Polish | 2 | Invites, per-player voice debug, lag toggle; real-Steam sign-off |
| **Total** | **about 18** | |

**Riskiest:**
1. **M4**: it touches every combat path, and the failure mode, double hits or a hit decided twice, is silent
   without the guards.
2. **M3**: the puppet mode across Monster, Hellgate, Employee and the props, plus the snapshot budget.
3. **M6**: the ownership epoch at handover, and making the late-join snapshot complete. It goes stale whenever new
   content forgets it, which is why the M6 coverage check exists.
4. **The real Steam path**: it can't be automated on one machine, so the M0 Steam code and the send-mode mapping are
   only proven by the manual checklist.
5. **M5**: the networked scene reload per floor (the load barrier, and static vars in `game.gd`).

---

## 5. Decided, and still open

**Decided (user, 2026-10-17):**
- Joining mid-contract is in: the joiner replaces an AI crew member with their own character (M6).
- Two players may use the same character.
- At most 3 players for now, one per crew slot; with no AI left the join is refused with "Crew is full".
- Character select is out of scope. Everyone uses the default character, and the hello message and roster carry a
  `character_id` from M0 on, so a future character select only has to set it.

- **A player drops:** the AI takes the seat back as the seat's **original** character (Rebar/Gasket).
- **A joiner takes over an AI** at **100% health** (not the AI's HP).
- **No host migration:** the host leaving ends the session for everyone.
- **The elevator online:** the **first** player to choose decides for the crew.
- **Pause online:** no pause while someone else is connected; **anyone** can abandon the contract (it ends it for the
  whole crew).
- **"Next contract" online** (chosen in M5, like the exits): **any** player's Next on the invoice takes the whole crew back
  to the host's board.

No open questions remain. The main menu in §1 is still a proposal.
