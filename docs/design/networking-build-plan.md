# Networking build plan: online co-op, step by step

Status: **M0 and M1 built** 2026-10-17 (see [M0 as built](#m0-as-built-2026-10-17) and [M1 as built](#m1-as-built-2026-10-17)
after the milestones); M2 onward is still the plan. The architecture is fixed by
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
returns (decided, see §5). Floor carry gets keyed by **seat**, not `display_name`.
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

### M5 Contract flow *(2 sessions)* — **Risk (moderate)**
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
`test_net_codec` (round trips and budgets), `test_net_floor` (built in M1: the checksum and ids), `test_net_board` (M1: the read-only board, the confirm).

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

- **A player drops:** the AI takes the seat back as the seat's **original** character (Rebar/Gasket).
- **A joiner takes over an AI** at **100% health** (not the AI's HP).
- **No host migration:** the host leaving ends the session for everyone.
- **The elevator online:** the **first** player to choose decides for the crew.
- **Pause online:** no pause while someone else is connected; **anyone** can abandon the contract (it ends it for the
  whole crew).

No open questions remain. The main menu in §1 is still a proposal.
