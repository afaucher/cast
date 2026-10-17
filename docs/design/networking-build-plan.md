# Networking build plan: online co-op, step by step

Status: **plan for review**, 2026-10-17. Nothing here is built yet. The architecture is fixed by
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

### M1 Shared run *(2 sessions)*
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

### M2 Hero sync *(2 sessions)*
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
returns (*proposal*, see §5). Floor carry gets keyed by **seat**, not `display_name`.
*Done when:* **`test_net_m2_walk`**: a client bot walks a scripted path. Under `off` and under `coast`, the host's
render of that hero stays within 0.35 units of where the client had it at the same `host_time - interp_delay`, with
no gap over 0.6 units in one frame. Each client sends under 3 KB/s. Then the client is killed, and its seat is
AI-driven on the host within 1 s at the same position.
*Playable:* **two or three players walk around the same floor together**, monsters frozen.

### M3 Host-owned world *(3 sessions)* — **Risk**
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

### M4 Spells and combat across owners *(3 sessions)* — **Risk (the biggest)**
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
*Done when:* **`test_net_m4_casts`** (3 processes, `coast`): a corn strike cast by client A lands on all three within
one frame of the same `host_time`; a heal aimed at client B lands on B once; B standing in the blast is hit once (not
once per machine), and B sidestepping on its screen is not hit. **`test_net_m4_hits`**: client damage to a monster
reaches the host once; a brute's swing at client A is decided on A; HP, deaths and the damage bill agree on all
peers after 30 s of scripted fighting; and the debug guard fires in a negative test.
*Playable:* **the real game for two or three, on one floor**: fighting, casting at each other, shoving each other
into pits.

### M5 Contract flow *(2 sessions)* — **Risk (moderate)**
**M5a Floors and exits.** Using the elevator or the van is a **request**; the host arbitrates the first one and
broadcasts `floor_change(n, carry)` or `contract_end(reason)`. Each machine reloads the scene; a **load barrier**
(everyone builds, checksums and reports ready, then the host starts the floor clock) replaces the fade-in.
Followers ride the elevator via the host. Drop-offs, extraction and "crew incapacitated" are decided by the host from
every hero's replicated `dead`.
**M5b The shared invoice, the Ledger and pause.** The host's `Ledger` and `ContractSession` are authoritative; lines
reach clients as events (the ticker and tracker read a mirror). The host builds the invoice and sends the finished
dict. "Next contract" returns **everyone** to the board in the same lobby. **Pause online** *(proposal)*: with
another player present, Esc opens the menu **without** pausing the tree. "Abandon contract" is host-only and takes
the whole crew back to the board; clients get "Leave crew" instead. The elevator and van menus freeze only your own
hero (`_freeze` today stops the whole world). Solo keeps the real pause.
*Done when:* **`test_net_m5_contract`** (3 processes, `coast`, `--auto-elevator`-style bots): down to floor 2, then
3, then out; every process shows the same invoice dict; carried HP is per seat. A client's van clock-out on floor 1
ends it for everyone. Two players pressing E at the elevator in the same frame produce one floor change.
*Playable:* **a full contract online**, from the board to the invoice, for a crew that started together.

### M6 Join mid-contract and seat handover *(2 sessions)* — **Risk**
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
  kit change to the joiner's character, with **HP carried as a fraction of max HP** *(proposal: kits differ, 85/120/160)*.
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

### Agent and manual local play
`run.ps1 -Crew 2|3 [-Link coast]` launches 2-3 **windowed** instances over ENet localhost, tiled, with `--no-mic` on
all but the first. `--shot` works per instance, so an agent can screenshot every screen at the same `host_time`.

### Single-process tests (cheap, run in the normal parallel batch)
`test_enet_loopback`, `test_net_session`, `test_net_puppets` (a non-owner never writes `PRIVATE`/`OWNER`),
`test_net_codec` (round trips and budgets), `test_net_floor_checksum` (two builds from one seed agree).

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
| M2 | **Carrier coverage, driven by `net_fields()`**: every `OWNER` field of every checked class has a carrier, either in that class's codec field list or in `NetEvents.CARRIES` (event-carried, e.g. `dead`). A codec that streams a `SPAWN`/`PRIVATE`/`LOCAL` field fails. A new `OWNER` var without a carrier fails the build, so content can't silently go unreplicated. |
| M2 | Codec round trip for every codec (randomised entity, pack then unpack, equal within its quantum) |
| M3 | Size budget: a worst-case snapshot (floor 3, hardest contract, every actor alive) under 1.2 KB |
| M4 | Lint: no `apply_damage`/`shove`/`set_modifier` loops outside `Combat` and the verbs (closes the known gaps) |
| M6 | Late-join coverage: every host-owned class declares how a joiner gets its state (keyframe, gone-id, or event replay) |

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

**Open questions for the user:**
1. **A player drops:** the AI takes the seat back, but as the seat's original character (Rebar/Gasket) or keeping
   the leaver's character? *(proposal: the original)*
2. **Character swap at handover:** the kits have different max HP (85/120/160). Does the joiner take over the AI's HP
   **as a fraction** of max HP *(proposal)*, or as raw points?
3. **Host migration:** none, so the host leaving ends the session for everyone?
4. **The elevator online:** does the first player to choose decide for the crew, or does the crew vote?
5. **Pause online:** OK that Esc never pauses while someone else is connected, and only the host can abandon?
