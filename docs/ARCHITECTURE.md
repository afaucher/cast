# Cast: POC architecture and contracts

Co-op, voice-cast, isometric hex dungeon crawler. This is the **proof of concept**:
one PC, one mic, one keyboard/mouse player plus AI allies. Online co-op is being built in milestones
(`docs/design/networking-build-plan.md`); M0 (transport, lobby, crew roster, clock, telemetry) and M1 (the shared run:
the host's board and job, each player's license checkout, the same floor from the seed behind a load barrier, the floor
clock), M2 (hero sync) and M3 (the host's world: monsters, hellgates, employees, props, crates, mail, pickups, the Ledger, the
exits), M4 (combat across machines: casts and attacks as events, hits resolved by the victim or the attacker, statuses by
their owner, monster wind-ups resolved on the victim's machine, the OWNER-write guard), M5 (the whole contract online: exits,
floor changes, the shared invoice, pause and abandon) and M6 (joining a crew on the job: a late joiner takes an AI's seat) are
in; M7 (polish, real Steam) is next.

Godot 4.7, GDScript, 3D with an orthographic isometric camera. Terrain is
**kinematic on a hex heightfield** (no physics bodies for terrain or actors).

## Folder ownership (parallel agents: only touch your own files)

| Area | Files | Owner |
|---|---|---|
| Core contracts | `scripts/core/*`, `scripts/combat/projectile.gd`, `scripts/combat/combat.gd`, `scripts/app/*`, `scripts/test_support/*`, runner scripts | lead (ask before changing; additive helpers OK if noted in your report) |
| Terrain gen + rendering | `scripts/world/*`, `assets/textures/*`, `scenes/terrain_preview.tscn`, `tests/test_dungeon*.gd`, `tests/test_terrain*.gd` | terrain agent |
| Voice casting | `scripts/voice/*`, `addons/hero_listen/*` (copied from Hero-Reader), `tools/make_voice_clips.ps1`, `tests/test_voice*.gd`, `scenes/voice_lab.tscn` | voice agent |
| Heroes, allies, spells, HUD, camera | `scripts/heroes/*`, `scripts/spells/*`, `scripts/ui/*`, `scripts/fx/*`, `scenes/arena.tscn`, `tests/test_hero*.gd`, `tests/test_spell*.gd` | heroes agent |
| Monsters | `scripts/monsters/*`, `tests/test_monster*.gd` | monsters agent |
| Game scene integration | `scenes/game.tscn`, `scripts/app/game.gd` (the game), `scripts/app/dev/game_dev.gd` (GameDev: the dev and screenshot drivers behind the `--` flags, the script the scene runs; new dev drivers go there) | lead |
| Networking: authority kinds, the net contract test | `scripts/net/*`, `tests/test_net_contract.gd` | lead. Every owner adds `net_fields()` entries for its own vars |
| Floor features (the site plan) | `scripts/contracts/site_builder.gd` (`SiteBuilder`: the ORDER of `plan()` and `spawn()`, which is the rng draw order and the net-id order, the van and the elevator body, the shared helpers and clear zones, `Site`), `scripts/contracts/planners/*` (one planner per floor feature, each with `plan(...)` and `spawn(...)`: `GatePlanner`, `EmployeePlanner`, `PropPlanner`, `HazardPlanner`, `NotePlanner`, `PackagePlanner`, `PackPlanner`, `ScoutPlanner`, `SharkPlanner`, `DoorPlanner`), `tests/test_golden_floor.gd` | lead. A new floor feature or environment adds a planner file and one line in each of `SiteBuilder.plan` / `spawn`, with its own dice; `test_golden_floor` must pass unchanged unless the change is meant to change floors |
| Design docs | `docs/design/*` | design agent |

## Boot flow and the main menu

`scenes/boot.tscn` (`scripts/app/boot.gd`, `class_name Boot`) is the main scene. It registers the input actions,
applies the saved game settings (`GameSettings.apply`: master volume and, unless a screenshot flag is present, the
window mode and size) and then changes scene to `Boot.route(args)`:

| Command line (after `--`) | Opens |
|---|---|
| `--run-test <name>` | the test (headless harness, nothing else runs) |
| `--scene <res path>` | that scene |
| `--menu` | `scenes/main_menu.tscn`, even with other flags (they still reach the game) |
| no flags, or only `--no-mic`, `--settings-file`, `--menu-shot`, `--menu-screen`, `--menu-say`, `--menu-after`, `--menu-void`, `--menu-hover`, `--menu-focus-file`, `--backdrop-mood`, `--backdrop-hero` | the main menu |
| `--net-join <ip[:port]>`, `--net-port`, `--net-link`, `--net-name` (online dev flags, see Networking) | the main menu (a joiner goes on to the host's job board; with other game flags it goes straight to the game scene and waits for the connection there) |
| any other `--flag` (`--seed`, `--spells`, `--contract`, `--floor`, `--shot`, every `game.gd` flag, `--net-host`, `--net-steam-probe`, flags added later) | `scenes/game.tscn`, as before |

`scripts/ui/main_menu.gd` (`MainMenu`) is the menu: `MenuBackdrop` (`scripts/ui/menu_backdrop.gd`: the crew's bunker
garage, a slowly drifting camera over the three `*Model` heroes idling around the real `VanModel` on its chalk circle,
torches, a `HellgateModel` glowing through a breach; mood dawn / night / after, see `MenuBackdrop.pick_mood` and
`LastContract`; no GameWorld, no actors) behind the rows 01 Start a job, 02 Join a crew, 03 Voice setup, 04 Settings,
05 Quit, a status line and (while joined) the crew list, and under the clipboard FORM 31, the personnel file
(`PersonnelFile`, `scripts/ui/personnel_file.gd`) of the hero the player picked. **Character select (2026-10-19):** a click
on a hero in the garage picks it (`MenuBackdrop.hero_at`: the camera ray against each model's mesh bounds; `set_hover`
outlines the hero under the pointer), as does the card's NAME line (Left / Right / Enter, last in the focus chain). The pick
is `Session.character_id` (the hello and the roster carry it), saved as `GameSettings` "character" and loaded by `Boot` at
start (`--hero` / `--backdrop-hero` override it for one run). Seats: `CrewSeats` (`scripts/heroes/crew_seats.gd`, below).
Start a job hosts a Steam lobby when Steam is up, else plays
solo; Join a crew joins the first lobby hiring (see Networking). The job board uses
the same garage: `game.gd`'s `_show_board` adds its own `MenuBackdrop` (the menu scene is already gone after Start's
scene change, so it is a fresh one that picks the same mood and hero) and sets `board.backdrop_behind`, which swaps
the board's opaque dark shade for a light dim; the board's crew strip shows the roster while hosting. Start calls `game.gd`'s `reset_flow()` and loads
`Boot.GAME_SCENE`, which opens on the job board. Sub-screens are `VoiceSetupScreen` (runs a real `VoiceCaster`
with the mic; edits the cast word, strictness and min-voice through the caster, which persists them via
`VoiceSettings`; live dB meter from `SpeechGate`; "Try it" shows HEARD, the matched spell and its power) and
`SettingsScreen` (`GameSettings`). Styling is the carbon-copy form system in `scripts/ui/forms/` (`FormTheme`, `PaperPanel`, `FormSheet`, `FormRow`, ...; see `docs/design/ui-theme-options.md`). Esc goes back (`pause` input action).
Dev: `--menu-screen voice|settings`, `--menu-shot <png> [--menu-after s]`, `--menu-say "cast heal"`,
`--settings-file <path>` (so screenshots never touch the player's settings).

Settings live in `user://settings.cfg`: `[voice]` (`trigger_word`, `strictness`, `min_voice_db`: `VoiceSettings`) and
`[game]` (`master_volume` 0..1, the Master bus, the only player volume: `GameSettings.BUS_VOLUMES`; `fullscreen`, `resolution` "WxH", `voice_panel_visible`: `GameSettings`). The game reads
both: `VoiceCaster.start()` applies `[voice]`, `game.gd` reads `voice_panel_visible` when it builds the debug panel.

In game (`game.gd`): **Esc** during a contract (no picker, elevator menu, invoice or "crew incapacitated" under way)
opens `PauseMenu` and sets `get_tree().paused`, so the whole world (GameWorld clock, actors, tweens, voice) stops while
the overlay (process mode ALWAYS) runs. Resume unpauses; Abandon contract does what F5 does (back to the job board);
Main menu drops the contract and changes scene to `Boot.MENU_SCENE`. Esc on the job board also goes to the menu.
`game.scene_changer` is a test seam for those two scene changes.

## Networking (`scripts/net/`)

Option A, owner authority (`docs/design/networking.md`); the order of work is `docs/design/networking-build-plan.md`.
Everything that sends, and everything that touches Steam, lives in `scripts/net/` (test_net_contract enforces it).
Gameplay and UI only ask: `Net.is_host()` (true offline: solo is hosting with nobody joining), `Net.online()`,
`Session.online()`, `Session.crew()`, `Session.host_time()`.

| File | What |
|---|---|
| `net.gd` (`Net`) | the authority kinds (`net_fields()`) and the static facade: `is_host`, `online`, `crewed` (someone else is in the crew), `simulates(node)` / `owns(node)` / `is_copy` / `make_copy` (M1: on a client the host's things are inert copies) and `is_puppet` / `make_puppet` / `label_of(hero)` (M2: a hero another player owns) |
| `net_session.gd` (autoload **Session**, `NetSession`) | the crew session: ENet or Steam transport, hello handshake, roster, refusals, leaving, clock pings, telemetry rows, dev flags |
| `net_wire.gd` (`NetWire`, child `Session/Wire`) | the reliable event RPC (its own channel) and unreliable `send_bytes` packets with our own u16 sequence numbers; stale packets are dropped |
| `net_link.gd` (`NetLink`) | the lag/loss simulator on each process's inbound side (presets `off`, `coast`, `rough`) |
| `net_clock.gd` (`NetClock`) | `host_time()`: NTP-style pings, interval intersection of the window's bounds, slewed (never backwards) |
| `net_telemetry.gd` (`NetTelemetry`) | one CSV row a second per machine, clients' rows collected on the host (`user://net/`) |
| `crew_flow.gd` (`CrewFlow`, child `Session/Flow`, `Session.flow`) | the shared run's state machine: board, job, license checkout, load barrier, floor start and the floor clock (`crew.*` events); see below |
| `net_floor.gd` (`NetFloor`) | net ids in build order, the floor checksum (map, site plan, contract, spawn table) and `freeze_copies` |
| `net_snapshot.gd` (`NetSnapshot`, child `Session/Snap`, `Session.snap`) | hero sync (M2): streams the heroes this machine owns at 30 Hz (`NetWire.T_SNAP`, unreliable) and shows everyone else's as puppets |
| `net_codec.gd` (`NetCodec`), `net_hero_state.gd` (`NetHeroState`) | the hand-packed hero snapshot (16 bytes a hero) and how a hero's OWNER fields go in and out; `HERO_FIELDS` is what the contract test holds it to |
| `net_interp.gd` (`NetInterp`) | the buffer behind a puppet: Hermite on position and velocity, about 100 ms behind `host_time()`, an adaptive delay, extrapolation up to 120 ms, teleports never blend |
| `seat_handover.gd` (`SeatHandover`, child `Session/Seats`, `Session.seats`) | who owns each seat's hero and its ownership epoch (in every hero snapshot); a dropped player's seat goes back to the AI as the seat's original character (`to_ai`); M6: which AI seat a joiner takes (`choose_seat`) and the handover to it (`take`, `to_player`) |
| `net_join.gd` (`NetJoin`, child `Session/Join`, `Session.join`) | joining mid-contract (M6): a joiner waits (`join.wait`) until the crew is on a running floor, builds that floor as it was at its barrier (`join.go`), reports its checksum (`join.built`) and gets the late-join snapshot (`join.snapshot`: the seat table, gone ids, a world keyframe, runtime spawns, pickups, dents, statuses, the Ledger, its own seat's state) |
| `net_registry.gd` (`NetRegistry`), `net_events.gd` (`NetEvents`) | the id -> node registry (runtime spawns and pickups get host ids from 10000); the tables of OWNER fields an event carries instead of a snapshot (`CARRIES` for heroes, `WORLD_CARRIES` for the host-owned classes) |
| `net_world.gd` (`NetWorld`, child `Session/World`, `Session.world`), `net_world_codec.gd` (`NetWorldCodec`) | the host-owned world (M3): the host packs its monsters (16 B), employees (15 B) and hellgates (7 B) once a tick after the heroes in the same packets (changed entries plus a spread keyframe, under 1.2 KB); a client shows them as puppets on one adaptive delay; spawns, deaths, speech, extraction and a gate's phase are `world.*` events. The Chicken spell's chickens are host-owned runtime spawns too (`world.spawn` kind "chicken"), streamed as monster-format entries (`CHICKEN_FIELDS`) |
| `net_objects.gd` (`NetObjects`, child `Session/Objects`, `Session.objects`) | host-arbitrated objects (M3): a client's hits on props, crates and mail, its pickups (collect / swap / drop), its E on an employee and its exit choice are `obj.req` requests; the host decides once and tells everyone (`obj.*`); loadouts; the Ledger and objectives mirror; the first-to-choose exits and the host's invoice; an explosive prop's fuse (`obj.fuse {id, s, e, by}` on the shared clock, `obj.out`: every machine runs the blast itself at `e`) |
| `net_casts.gd` (`NetCasts`, child `Session/Casts`, `Session.casts`) | casts and hero attacks as events (M4): a cast is resolved on the caster's machine and lands `LEAD` (0.2 s) later on every machine (`SpellBook.apply`); a hero's swing, shot, bowl or spin (`act`) is replayed on its puppet everywhere at the moment the puppet shows |
| `net_status.gd` (`NetStatus`, child `Session/Status`, `Session.status`) | statuses (M4): the target's owner applies a modifier, a fire or a soak and announces it (`st`); the other screens show it (`Actor.net_set_modifiers`, `Burning.show_remote`, `Coffee.show_remote`, `Wet.douse`) |
| `net_orders.gd` (`NetOrders`, child `Session/Orders`, `Session.orders`) | voice orders (combat-proposals.md 1.8): the speaker's machine sends `ord.req`, the host applies it once (`VoiceOrders.apply`: the AI seats and the employees) and sends `ord.ok` to everyone (the AI heroes' barks, the players it names for a marker) |
| `steam_identity.gd` (`SteamIdentity`) | the one Steam init per process, the persona name |
| `steam_lobby.gd` (`SteamLobby`, child `Session/Lobby`) | lobbies: create, list, join, leave, invites, lobby data |

**The shared run (M1).** With another player in the crew (`Net.crewed()`; a host alone plays the plain solo game) `game.gd`
runs a SHARED run: the host rolls the board seed and every machine draws the same three offers (`JobBoard.read_only`
on clients; the host's highlighted card follows); the host's pick (`crew.job`) opens everyone's own license checkout
(`SpellPicker`; a client's back row is "Leave the crew"); signing is the ready step (`crew.signed`, the roster entries
gain `signed`, `spells`, `ready`); when all have signed (`crew.load`) every machine builds the floor from the contract seed
behind a barrier (`game.gd` `_start` then `_enter_barrier`: ids, copies, world frozen, `NetFloor.checksum`,
`crew.ready`); the host compares the checksums (a client that built another floor is sent out with "Desync: different
floor") and sends `crew.go {start_at, floor_start}`; at `start_at` on the shared clock every machine unfreezes and the
van arrival plays (`CrewFlow.floor_started`), and each client's `GameWorld.time` is slewed to `host_time() - floor_start`.
Heroes are built per seat (`game.gd` `_spawn_crew`, `heroes_by_seat`): you control your seat's hero (solo: seat 1, the hero
picked on the menu); an EMPTY seat is an AI ally that only the host runs, playing a hero NOBODY human picked (`CrewSeats.fill`:
seat 2 keeps Rebar and seat 3 Gasket when free, else the first free of Rebar, Gasket, Wick; `AI_SEATS` is only the formation),
and a seat its player leaves goes back to the AI as `CrewSeats.ai_for` (`SeatHandover.ai_character`); on a client every
host-owned actor is a copy (`Net.make_copy`: no physics process, no damage, no shove, no E).
While crewed there is no local pause (M5); the exits are first-to-choose (M3, below). `NetFloor`, `CrewFlow`, `CrewConfirm` (the host's leave question)
and `NetGameTest` are the pieces to read first.

**Hero sync (M2).** Each machine OWNS its own seat's hero and moves it locally, with full responsiveness; no input crosses
the wire. From the shared start (and once its own van arrival is over: the arrival places the heroes itself) `Session.snap`
sends the state of every hero it owns 30 times a second as an unreliable, sequence-numbered `T_SNAP` packet: a client to
the host (24 bytes: position, velocity, facing, aim point, HP, dead, climbing, the held slot, the bow draw, a teleport
counter), the host to each client (the host's hero, the AI ones and the OTHER client's, forwarded with its age so every
sample keeps its moment on `host_time()`; 40 bytes for two heroes). Every other hero is a PUPPET (`Net.make_puppet`): a
copy that applies the interpolated state (`NetInterp`) about 100 ms behind the shared clock and keeps animating
(the model tracks its own walk from the movement; the aim reticle belongs to the local controller, so a puppet has none).
Its nameplate and HUD row read the player's roster name (`Net.label_of`). The hero a puppet shows is the same node
the game built from the seed, with an id equal to its seat (`NetRegistry.hero(seat)`).
**A player drops:** the host's `SeatHandover` lets go of the puppet and the game re-kits the SAME hero node in place as the
seat's original character (`Hero.become`: kit, name, colour, model; HP keeps its fraction; a downed hero stays downed) and
attaches an `AllyBrain`; the clients get `seat.ai` and re-kit the same node on their screens, and show the host's stream
from then on. The floor carry is keyed by seat (`ContractSession.carry_key`): two players may both be Wick. New `OWNER`
vars of `Hero` must be in `NetCodec.HERO_FIELDS` or `NetEvents.CARRIES` (test_net_contract).

**The host's world (M3).** At the barrier `Session.world.begin()` and `Session.objects.begin(player)` take the registry. The host
simulates everything it owns as ever and `NetWorld.section()` packs it into every snapshot to the clients; on a client monsters,
hellgates and employees are PUPPETS (`Net.make_puppet`) shown on the shared clock (`Monster/Employee/Hellgate.net_show` play what
changed: the hit flash, the wind-up, the swing, the mood; `net_tick` runs their look), and props, crates, mail and pickups are
copies whose look runs from `NetObjects` (`net_tick`). What a client does to the host's things is a request: `Actor.apply_damage`
on a copy calls `Net.route_hit` (breakables only until M4), a pickup's copy asks to `collect`, F asks to `swap`
(`Hero.apply_swap` runs on the grant), E on an employee asks `follow` / `wait`; the host grants the FIRST request (one player gets
each pickup) and the owner changes its own hero (`obj.loadout` tells the crew). Deaths and breaks go through `Net.remote_die`
(the visuals of `die()`, deciding nothing: drops, contents and bills are the owner's). The money is the host's: a client's `Ledger`
is a mirror (`Ledger.mirror`, `mirror_line`), the objectives are kept on the host (`game._keeps_books`) and mirrored
(`ContractSession.mirror_state`), and the invoice a client shows is the host's. The elevator and the van are first-to-choose
(`game._choose_exit` -> `NetObjects.decide_exit` -> `_on_exit_decided`): down reloads every machine onto the next floor behind the
barrier again (`CrewFlow.host_next_floor`, `crew.next`), out ends the job with the host's invoice. Monsters aim at another player's
hero where its newest snapshot says it is now (`Monster.target_point()`, `Net.lead_point`).

**Combat across owners (M4).** Effects run on every machine (a cast lands on every machine at the same shared moment, a hero's
attack is replayed on its puppet, a monster's wind-up is an event) and each machine applies only what it RESOLVES (layer 4):
a hero's hits by its owner (the victim decides: `Net.resolves_hit`, every `Combat.*` helper and `Projectile` ask it), anything
else's hits by the attacker's machine (a client's hit, shove or modifier on the host's actor is a request:
`Net.route_hit` / `route_shove` / `route_modifier`, `NetObjects`), statuses by the target's owner (`Net.resolves`). A monster's
strike on a client's hero is resolved on that client when its screen shows the strike (`world.windup`, `Monster.net_strike`); a
shoved hero's own machine sees it hit a prop (`Net.hit_object`). In debug builds a write to a copy's `hp`/`dead` outside the net
layer raises a script error (`Net.guard_write`, layer 5).

**Joining mid-contract (M6).** A hello while the crew is on a job is admitted as a JOINING roster member (`joining` true, an AI's
seat): nobody waits for it (`CrewFlow` skips it at the license and the barrier and sends it none of their events) and its seat
stays the AI's on every floor built meanwhile. `Session.join` holds it at "Clocking in..." (`ClockInSlip`) until the crew is on
a running floor (a floor change: the next floor; the invoice: the next board, which makes it an ordinary member), then sends
the floor and the seat table the host built it with at its barrier (`CrewFlow.floor_seats`), so the joiner's fresh build has
the barrier's checksum. On a match the host sends the late-join snapshot and hands the seat over (`SeatHandover.take`): the
SAME hero node becomes the joiner's character at full health (`Hero.become(..., full)`), the AllyBrain stops, the epoch goes
up (hero snapshots carry it, `NetCodec` flags bits 4-7, so a sample from the old owner is dropped), and everyone sees "<name>
takes over Gasket's seat". Leaving is the M2 drop. Every replicated class names how a joiner gets its state in
`NetEvents.LATE_JOIN` (test_net_contract).

RPC endpoints live under the autoload (`/root/Session/Wire`), never in `game.tscn`, because every floor change is a
scene reload and an RPC needs the same node path on every peer. `Session` runs with process mode ALWAYS, so pausing
the tree never stops the network.

Lessons carried over from Bridge to Friendship (its `CLAUDE.md`):
- **`get_unique_id() == 1` does not mean "I am the host".** Offline, Godot's MultiplayerAPI holds an
  `OfflineMultiplayerPeer` whose id is also 1. Ask `Session.local_id()` (0 offline) or `Net.is_host()`.
- **The two ends of a connection become ready on different frames.** The client's `connected_to_server` fires a frame
  or two before the host's `peer_connected`; an RPC broadcast on the client's signal alone goes to an empty peer list
  and is lost silently. Cast's handshake has the host speak first (`sys.ask` on `peer_connected`).
- **`@rpc` mode is a security boundary, not a hint** (`"authority"` drops packets from anyone else). Ours is one
  `any_peer` reliable event RPC; each handler checks who sent it (`from == 1`, or a roster member).
- **Test over ENet, but know where it differs:** GodotSteam sends `unreliable_ordered` reliably (never use it), and
  the Steam peer's send-mode mapping can only be checked on real Steam (the manual checklist in the build plan).
- **Never free the multiplayer peer inside its own poll** (an RPC handler or a disconnect signal): Cast crashed doing
  that; `NetSession._end` defers the close.
- Two peers can share a process (`SceneTree.set_multiplayer` with a node per peer; RPC paths are relative to that
  root): `test_enet_loopback`, `test_net_session`, `test_main_menu`. A whole game can't (GameWorld and Ledger are
  autoloads, `game.gd` has static vars), so multi-world tests run as separate processes (Tests, below).

## Core contracts (already written, see the source)

- **`Hex`** (`scripts/core/hex.gd`): pointy-top axial `Vector2i(q, r)`. `Hex.SIZE = 1.0`
  (center to corner), `Hex.LEVEL_HEIGHT = 0.5` world units per height level.
  `to_world(cell, level)`, `from_world(pos)`, `DIRS[0..5]`, `neighbor`, `distance`,
  `line`, `range_cells`, `ring`, `corner(i)`, `dir_vector(dir)`.
- **`HexMap`** (`scripts/core/hex_map.gd`): `cells: {Vector2i: Cell}`. A missing cell is void.
  `Cell.level:int`, `Cell.type: Tile.{FLOOR, WALL, STAIRS, BRIDGE}`, `stair_dir`,
  `stair_rise`, `tag:String`. Queries: `ground_level(pos)` / `ground_height(pos)`
  (NAN over void), `movement_check(from, to) -> Move.{OK, CLIMB, BLOCKED}`,
  `cell_transition(a, b)`, `line_of_sight(from, to)`, `find_path(a, b, allow_climb)`.
  - Rule (in levels): rise ≤1 walks, rise 2 climbs (slow), rise ≥3 is blocked, and a drop of more than 3 is blocked.
  - STAIRS ramp from `level` at the back edge to `level + stair_rise` at the edge facing `stair_dir`.
  - WALL is a tall cell that blocks movement and line of sight.
  - **Midpoint walls** (`cut_walls()`, run by `DungeonGen`): wall faces run along the lines that join adjacent hex
    CENTERS, so every wall is straight (0/60/120 degrees), crosses a hex edge at its midpoint and turns on a hex
    center. A floor cell next to a WALL cell is **cut** (`is_half(c)`): `Cell.wall_mask` has a bit per kite (the six
    sectors around the center, `Hex.kite_of`, kite k between `DIRS[k]` and `DIRS[k+1]`) that is wall, `wall_top` is
    that part's height. A straight wall cuts a cell in half, a room corner leaves a 120-degree floor wedge, an inside
    corner a 240-degree one. Walls block whole triangles of hex centers, so neighbouring cells always agree; slivers
    (a floor triangle between two faces, a pocket touching no full cell) are walled in. `Cell.mat_id` packs the floor material
    (bits 0-7) and the wall material (bits 8-15) of the cell, 0 = classic slate; `SiteBuilder.plan()` writes it from the
    room themes (`FloorMaterials`, docs/design/environment.md "Materials") and `HexMapView` draws it. Hand-built maps that never call `cut_walls()`
    (labs, the arena, most tests) keep plain hex walls; every query below works on both.
  - `is_walkable_cell(c)` means a FULL floor cell (present, not a wall, not cut). Those are the path nodes and the
    spots for spawns, gates, employees, notes and the van. `find_path` never routes through a cut cell (its center lies
    on the wall line) but accepts one as the start (the path steps out of it into a full neighbour) or the goal (the path ends at the
    full cell beside it; the caller steers on to its goal point).
  - **Collision lives in HexMap only**: `wall_at(p)` (the point is on the wall side), `blocks_point(p, radius)`,
    `clip_move(from, to, radius)` (a body stops touching the face, slides along it, settles in corners without
    jitter), `sweep(from, to, radius)` (how far a body gets before contact), `solid_contact(from, to)` (where a
    projectile meets a face or cliff), `nearest_wall(p, max_dist)`, `wall_segments(c)` / `segments_near(p, r)`
    (the faces as `[a, b, normal]` triples). `ground_level` returns the wall top on the wall side, so
    `movement_check`, `line_of_sight` and projectiles already see the wall LINE as the boundary. `Actor.move`,
    shoves (`_advance`: a slam stops with the body against the face), separation, `Monster.move`, `Projectile`,
    `ArrowShot`, `BowlBoulder`, `SpellBook.resolve_target` and `ComponentPickup` call these, never `type == WALL`.
- **`GameWorld`** (autoload, `scripts/core/game_world.gd`): `map`, `root` (parent for
  actors/projectiles/fx), `time` (the game clock; use it, not wall time), `rng` (gameplay rolls),
  `fx_rng` (cosmetic rolls only),
  `spawn(node, at)`, `actors()`, `team_actors(team)`, `actors_in_radius(pos, r, team)`,
  `nearest_actor(pos, team, max_range)`, `flat_distance`, `TEAM_HEROES = 0`, `TEAM_MONSTERS = 1`.
  `hittable_in_radius(pos, r, team)` is `actors_in_radius` plus every actor in the group `"breakables"` (mail
  packages) and the chickens (group `"chickens"`, the Chicken spell; the crew's swings and shots only while
  `Chicken.WEAPONS_HIT`): `Combat.melee_arc`, `Projectile` and `ArrowShot` use it, so swings and shots also break the
  mail and swat chickens, but never hit employees. With `props` (`Projectile.hits_props`: the archer's arrow, Wick's
  arrows, the hero bolt; and `Combat.melee_arc` for a hero's swing) it adds the priced props (`props_in_radius`, group
  `"priced_props"`): the crew's weapons and every arrow hit props (user, 2026-10-18); a monster's swing and a fireball's
  flight do not.
  A test or scene calls `GameWorld.begin(map, root_node3d)` first.
- **`Actor`** (`scripts/core/actor.gd`, extends Node3D): `team`, `max_hp`, `hp`,
  `move_speed`, `radius`, `dead`, `facing`, `climbing`. `move(dir, delta)` does the terrain
  rules, slide, climb slow-down, separation and ground snap. Also `apply_damage(amount, source)`,
  `heal(amount)`, `set_modifier(id, mult, duration)` (damage-taken multiplier; the same id
  refreshes), `peck(source)` (the Chicken spell's hit for nothing: no damage, a monster turns on the pecker; through
  `Combat.peck`), `daze(seconds, source)` (the brute's direct slam through `Combat.slam`: a `STAT_DAZE` modifier, so
  `is_dazed()` / `is_helpless()` are true, `move()` refuses and the hero can't attack, but casts go off; then
  `DAZE_GUARD` 1.5 s of immunity; the owner applies it, a copy refuses; `docs/design/characters.md`, "The daze"),
  `has_modifier`, `face_point`, `current_cell`. Signals: `damaged`, `healed`, `died`, `pecked`.
  Override `_on_death()` for death visuals (the default is `queue_free`). Actors join the group `"actors"`.
  `net_fields()` says who may write each var (`Net.SPAWN/OWNER/PRIVATE/LOCAL`, `scripts/net/net.gd`);
  subclasses merge theirs into `super()`, and `test_net_contract` fails on any undeclared var.
  See `docs/design/networking.md` and `AGENTS.md`.
- **`Projectile`** (`scripts/combat/projectile.gd`): `Projectile.fire(shooter, from, dir, dmg, speed, range)`.
  Set `color`, `size` or `on_hit` before the first frame for custom behavior.
- **`Combat`** (`scripts/combat/combat.gd`): `melee_arc(attacker, dir, reach, arc_deg, dmg)`,
  `explode(pos, radius, dmg, team, source, edge_mult, shove = 0, decider = null)` (`shove`: pushed out, falling off like
  the damage; `decider`: whose machine decides the non-hero hits when that is not `source`'s, an explosive prop's blast),
  `slam(...)` (also lights an explosive prop in its ring), `chest(actor)`.
- **Explosive props** (`ExplosiveProp extends PricedProp`, `scripts/contracts/explosive_prop.gd`;
  `docs/design/hazards.md`): fire, a hard hit, any arrow or a hard shove lights a short fuse (`FuseFx`: hiss, sparks,
  glow, shake, the blast ring); at its end a `Combat.explode` blast on everyone (team -1) with a shove, chained to the
  explosives in reach, billed once to whoever set it off. A soaked one is a dud and a soak puts a fuse out. Placed by
  the room themes (`RoomThemeDefs` "hazards", `HazardPlanner.plan`, `SitePlan.hazards`, `Site.hazards`).
- **`Usable`** (`scripts/app/usable.gd`, the E key's contract; its header is the reference): anything E acts on has
  `use_kind()`, `use_score(hero, game)` (-INF when not usable now), `use_prompt(hero, game)` (the prompt's verb),
  `use_point(hero, game)` and `use_press(hero, game)`. `game.gd` `use_target()` collects one candidate per kind
  (`_use_candidates()`: each kind's own nearest-in-reach finder) and `Usable.pick` takes the best score, the first on a
  tie; the prompt (`_update_use_prompts`) and the press (`_use_key`) read that one `Usable.Target {node, kind, verb, pos}`.
  The scores are per-kind bands (`Usable.VAN` .. `PICKUP`): the van exit, the elevator, an employee, a note, an office
  door, a component pickup. Implemented by `Employee`, `ClueNote`, `OfficeDoor` and `ComponentPickup`, and by two thin
  adapters over `game.gd`'s exit state, `VanExitUse` and `ElevatorUse` (`scripts/app/usables/`). A new interactable is a
  class with the five methods, a band, and one line in `_use_candidates()`. A client's E keeps its own request path
  inside each `use_press` (`Employee.interact`, `OfficeDoor.use`, `Hero.swap_in_pickup`: `Net.request`).
- **Input** (`scripts/app/input_setup.gd`): `move_up/down/left/right` (WASD),
  `attack_melee` (LMB), `attack_ranged` (RMB), `cast_slot_1..4` (keys 1-4: ready/hold a spell slot),
  `use` (E: the best `Usable` in reach: the van's clock-out slip, the elevator, an employee, a note, an office door or a
  pickup swap, in that order; never casts), `swap_pickup` (F: swap a dropped component into
  the held slot), `toggle_voice_debug` (F1), `restart` (F5), `pause` (Esc).

## Cross-agent contracts (implemented by the owning agent)

### Voice → game (`scripts/voice/voice_caster.gd`, `class_name VoiceCaster extends Node`)
```gdscript
signal spell_spoken(spell_id: String, power: float, heard: String)  # power in (0, 1]
signal spell_fizzled(heard: String, reason: String)                  # heard something spell-ish, too garbled
signal voice_activity(active: bool)                                  # someone started/stopped talking
func start(spell_ids: PackedStringArray) -> bool   # opens mic + loads model; false if unavailable
func is_ready() -> bool
func get_level() -> float                          # 0..1 mic level for a meter
func inject_text(text: String) -> void             # debug: act as if `text` was heard (typed console / tests)
signal trigger_heard(word: String)                 # the trigger word armed a cast (Incantation.trigger_armed): the "cast heard" cue
signal speech_started                              # the gate's voice onset (raw input, ~50 ms in): cuts the fizzle
func is_speaking() -> bool                         # inside a voice span right now (no hangover)
signal order_spoken(who: String, order: String, heard: String)  # a voice order: "rebar" / "everyone" / "hench four", "go" / "attack" / "follow"
```
Voice orders (`docs/design/combat-proposals.md` 1.8): `game.gd` hands an order to `VoiceOrders.give(who, order, player,
aim point)` (`scripts/heroes/voice_orders.gd`), which applies it (solo) or sends it to the host (`Net.send_order` ->
`NetOrders`): `AllyBrain.give_order` for an AI hero, `Employee.order` for an employee, a marker (`OrderFx`) for a hero a
person plays. With no order an AI ally follows the restraint baseline (`AllyBrain.restraint`): it never opens a fight.
Spell ids are lowercase: `heal`, `fireball`, `armor`, `corn`, `tentacles`, `teeth`, `vines`, `damp`, `coffee`, `chicken`.
The voice layer listens for **all**
spells. The game decides whether the local hero knows the spell (and fizzles it if not).

### Sound (`scripts/fx/sfx.gd`, autoload **Sfx**; `docs/design/audio-plan.md`, "As built")
Cosmetic: `Sfx.play(cue)`, `Sfx.play_at(cue, pos)`, `Sfx.stop_cue(cue)`, `Sfx.listen_to_voice(caster)`. The cue table
(`Sfx.CUES`) names each cue's file under `assets/audio/sfx/` (rendered by `tools/render_sfx.ps1`, not in git; a missing
file is a silent cue with one warning), its bus (`default_bus_layout.tres`: Master > SFX > World / Stings, UI,
VoiceFeedback, Music), voice limit and gap. Callers only listen (Game, forms, `Fx`); every machine plays its own sounds
from the events it already has, and no RPC carries a sound. Off headless (tests: `Sfx.enable_for_tests()`).

### Spells (`scripts/spells/spell_book.gd`, `class_name SpellBook`)
```gdscript
const SPELLS := { "heal": {"name": "Heal", "cooldown": 8.0, "color": Color(...), "desc": "..."}, ... }
static func cast(id: String, caster: Actor, power: float, aim: Vector3) -> bool
```

### Forced movement (`Actor.shove`)
`Actor.shove(dir, distance, source = null)` starts a short (0.2-0.35 s, ease-out) kinematic slide of
`distance * shove_mult` along `dir` on X/Z (`shove_mult` 0 = immovable: Rebar; brute 0.4, swarmer 1.5).
It is driven by the tree's `physics_frame` signal only while active. While `is_shoved()` the actor ignores
`move()`; `is_helpless()` (shoved, staggered or dazed) is what the player controller, `AllyBrain`, `Monster` and the
training dummy check before steering or attacking (voice casts still work). Terrain rules differ from walking:
- a wall, or a rise of 2+ levels, stops the slide: "slam", 8 damage + 0.4 s stagger (shoves under 1.0 just stop);
- drops of up to 3 levels are free; a higher ledge is fine too: the actor falls under gravity and takes 6 damage
  per level beyond 3 on landing (+ stagger);
- void: heroes are pulled back to the last cell they stood on (5 damage); everyone else falls in and dies;
- a shove caused by a hero (`source` team) never takes a hero below 1 HP (slam, fall or pit).
Monsters cancel a wind-up when shoved and re-home where they land (no leash-heal). Signals: `shoved`, `shove_impact`.
Built on it: every melee hit nudges (hero 0.7, monster 0.35, brute slam 1.0: `Combat.melee_arc(..., shove)`),
the Tentacles spell, and the heroes' `secondary_kind`: `"bolt"` (Wick), `"bowl"` (Rebar: `BowlBoulder` rolls
through everything, shoving each actor 3.5 sideways/forward, 6 damage to monsters only) and `"spin"` (Gasket: 360 degrees,
reach 1.9, 16 damage to monsters, everything in reach shoved 2.2, teammates included).

### Heroes (`scripts/heroes/hero.gd`, `class_name Hero extends Actor`)
`spell_slots: Array[String]` (up to `SpellComponents.SLOT_COUNT` = 4 entries, no gaps), `held_slot`,
`charges_of(id)`, `try_cast(id, power, aim) -> bool` (checks the slot, the charges (0 = fizzle, no cooldown)
and the cooldown, then spends 1 charge), `cooldown_left(id) -> float`, `cooldown_total(id)` (held spell
/ 1.15). Material components: see `docs/design/spells-and-components.md` (`SpellComponents` holds the
numbers and the drop table; `Monster._on_death` rolls the drops; `ComponentPickup` is the world prop).
The player-controlled hero has `is_player = true`.
`PlayerController` reads input. `AllyBrain` drives AI allies.

### Monsters (`scripts/monsters/*.gd`, each extends `Monster extends Actor`)
`MonsterFactory.spawn(kind: String, cell: Vector2i) -> Monster`. Kinds: `grunt`, `archer`, `brute`, `swarmer` (the packs), `pavise` and
`water_boy` (packs from floor 2: the shielded crossbowman and the healer, `docs/design/combat-proposals.md` §2.9 / §3.8), and
`goblin` (the scout: never in a pack, `SiteBuilder` puts one or two in corridors; `docs/design/goblin-scout.md`). Every kind is a
`MonsterDefs` row (`MonsterFactory.compose` deals a pack kind from its row's `min_floor`, at most `max` a pack, `after` that
many others). A shield is a target's `blocks_hit(from_point, kind)`, asked through `Combat.shielded` by every hit helper.
`MonsterFactory.spawn_pack(room_cells: Array[Vector2i], budget: int, rng) -> Array[Monster]`.
Monsters idle until a hero is within aggro range with line of sight, then act.

### Terrain (`scripts/world/dungeon_gen.gd`, `class_name DungeonGen`)
`DungeonGen.generate(seed: int, params := {}) -> HexMap`. Cells are tagged: `"start"` (one cell),
`"exit"` (one cell), `"room:<n>"` for room floors (so monsters can be packed per room; a room's cut border cells
carry its tag too), `"corridor"`. `HexMapView` (`scripts/world/hex_map_view.gd`, extends Node3D): `build(map)`.
A contract's floor is `DungeonGen.for_run(run, floor)` (the job's elevator placement). The `"exit"` cell is the
elevator's landing: `ElevatorGeo` (`scripts/world/elevator_geo.gd`) places the car (a notch cut into a wall, or
free-standing) and writes `HexMap.elevator`, its solids (`HexMap.solids`: convex polygons the collision queries treat
like wall faces) and its `HexMap.no_stand` cells; `ElevatorArrival` (`scripts/contracts/elevator_arrival.gd`) builds the
model and the crew's arrival. See `docs/design/elevator-options.md`, "Built".
Pools: `PoolGeo` (`scripts/world/pool_geo.gd`) carves an in-ground pool into the indoor pool and science rooms and a
moat ring (water between a convex outline and a convex island, its `hole`) into the shark moat rooms (`SiteBuilder.plan`,
after the themes are dealt): basin cells one level down and ring cells cut along midpoint lines
(`Cell.pool_mask` / `pool_level`, `HexMap.pools`, `HexMap.water_at`). `HexMapView` draws them in its inset mode and
`PoolView` (`scripts/world/pool_view.gd`) adds the water, coping and dressing; `Wading` (`scripts/world/wading.gd`) slows
and soaks whoever stands in the water. See `docs/design/pool-options.md`, "Built". A cut cell may hold pool kites too
(water up to a wall: the sewer slice, `--sewer N`, `SewerLayouts` / `SewerView` / `Gator` / `LiveWire`, dev and solo only;
`docs/design/sewer-concept.md`, "Phase 1 as built").

Midpoint walls (see `HexMap` above): the generator rings everything with WALL cells as before, then `cut_walls()`.
To keep that clean:
- room shapes are opened (the full interior grown back by one ring), so no one-cell neck or peninsula becomes a sliver;
- a corridor's route (and on a tree link one lane beside it) is its CORE, and `_fill` gives every core cell all six
  neighbours (copying the step of the earliest core cell they touch, so stairs get twins). Tree links are 4 cells
  across (4.5 units between the walls, two full lanes), loops, the climb shortcut and the chokepoint 3 across (3.0);
- routes keep 3 cells from other rooms and corridors (`near_room`, `corr_buffer2`) and fill cells 2 (`corr_buffer`),
  so a wall always separates them; a door cell must have its outside neighbours free (`_door_ok`) and is filled
  round, so every doorway is a full cell inside a clean flared opening;
- pillars and pits keep two cells from the room's border (no strip of floor too thin to walk);
- validation also wants every door cell full and every full cell joined to the start through full cells.
`HexMapView` draws a cut cell as a floor tile over its open kites (seams and bevels only along its hex edges, flush
into the wall line) plus a capped wall part at `wall_top` whose face is one flat quad per center-to-midpoint spoke.

Zone layout (tuned so floors are not crowded): 6-9 rooms of radius 5-8 (`DEFAULT_RMIN/RMAX`) at least `DEFAULT_GAP`
(8) apart in an area of radius `DEFAULT_SIZE` (36); tree-link corridors are four cells across (4.5 wide between the
midpoint walls), extra loops, the climb shortcut and the one short chokepoint three (3.0); about half as many raised features per room, never
within `FEATURE_CENTER_CLEAR` (2) of a room's center or `FEATURE_DOOR_CLEAR` (3) of a door. Generation takes
about 130 ms (limit 300 ms, asserted in `test_dungeon_gen`). `SiteBuilder`'s planners (`scripts/contracts/planners/`) then put at most 6 priced props on a floor (`PropPlanner`:
next to walls, 4+ apart, flush and square against the flat face: `ThemeCtx.wall_pose_at` marches to the face and
refuses a pose that would not stand flush; footprints must stay off the wall side, `ThemeCtx.rect_clear`) and at most 3
explosive props (`HazardPlanner.plan`, own dice, the same wall poses), scale the monster pack budgets by 0.7 (`PackPlanner`) and cap a room at one monster per
`MonsterFactory.CELLS_PER_MONSTER` (6) walkable cells. Allies (`AllyBrain`) trail the player 2.5-3.5 hexes away at
distinct angles and step out of the player's lane.

## Tests

`tests/test_*.gd` extend `TestCase` (`scripts/test_support/test_case.gd`): override `setup()`,
use `check / eq / near / frames(n)`, then call `finish()`. Run with:

```powershell
.\test_runner.ps1 -TestName test_hex
.\test_runner.ps1 -TestAll
.\build.ps1            # import + every test
```

Tests run headless with `--fixed-fps 60` (deterministic and fast). Use `GameWorld.time` for
durations. Logs go to `test_logs/<name>.log` and `.err.log`. **Read the .err.log for parse errors.**

**Multi-process net tests.** A test that extends `NetTest` (`scripts/test_support/net_test.gd`) and declares
`const PEERS := N` runs as N headless processes over ENet on localhost (a host and N-1 clients), once per link in
`const LINKS` (default `off` and `coast`), after the parallel batch, at most two runs at a time, in real time
(`--max-fps 60`, not `--fixed-fps`). The host is the judge: clients `report()` what they saw; the host asserts and
prints the PASS marker. Every process must exit 0. Logs: `test_logs/<name>.<link>.host.log`, `.c1.log`, ...
Single-process network tests that need wall time stop the TestCase timer and keep their own (see `test_net_session`).
A test that extends `NetGameTest` (`scripts/test_support/net_game_test.gd`) also puts a real `game.gd` node under the test on every
process and drives it through its own screens (job board, license checkout): `make_game()`, `sign_license()`, `truth()` (the
shared clock as the one machine's wall clock sees it), `scene_changes` (the game's scene changer is a seam, so a test sees
"back to the menu" without losing the process). `NetTest.after_end()` runs after a client's session ended as expected.
M2 added to it: `enter_floor(seed)` (the whole crew onto a running floor through the game's own `--net-wait` / `--spells` dev
flags), `wait_sync()`, `start_bot()` (a `NetBot`, `scripts/test_support/net_bot.gd`: steers the real `PlayerController` through
its `move_override` seam along a route of real floor), and a recorder: `record(true)` keeps every frame of this machine's own hero
(the TRUTH) and of what each puppet showed with the shared time it showed (`render_time`); `series_error(ring, series)` holds
a viewer's series against the owner's ring (error, biggest step, and the step beyond what walking covers in the frame gap).
M3 added `follow_reloads` (a scene reload the game asks for, the elevator down, is DONE: the game node is replaced with the
contract kept, `reloads` counts them) and `make_game(extra, fresh)`; the world tests record monsters the same way
(`NetWorld.shown_state(id)` is what a client showed and at which shared time).

Run the game: `.\run.ps1` (or `--scene res://scenes/arena.tscn` after `--`).
Engine: `$env:CAST_GODOT`, else `..\Hero-Reader\third_party\godot\Godot_v4.7-stable_win64_console.exe`.
