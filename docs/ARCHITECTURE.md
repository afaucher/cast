# Cast: POC architecture and contracts

Co-op, voice-cast, isometric hex dungeon crawler. This is the **proof of concept**:
one PC, one mic, one keyboard/mouse player plus AI allies. Online co-op is being built in milestones
(`docs/design/networking-build-plan.md`); M0 (transport, lobby, crew roster, clock, telemetry) is in, so players
can form a crew, but there is no shared run yet.

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
| Game scene integration | `scenes/game.tscn`, `scripts/app/game.gd` | lead |
| Networking: authority kinds, the net contract test | `scripts/net/*`, `tests/test_net_contract.gd` | lead. Every owner adds `net_fields()` entries for its own vars |
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
| no flags, or only `--no-mic`, `--settings-file`, `--menu-shot`, `--menu-screen`, `--menu-say`, `--menu-after`, `--backdrop-mood` | the main menu |
| `--net-join <ip[:port]>`, `--net-port`, `--net-link`, `--net-name` (online dev flags, see Networking) | the main menu (a joiner waits there in M0) |
| any other `--flag` (`--seed`, `--spells`, `--contract`, `--floor`, `--shot`, every `game.gd` flag, `--net-host`, `--net-steam-probe`, flags added later) | `scenes/game.tscn`, as before |

`scripts/ui/main_menu.gd` (`MainMenu`) is the menu: `MenuBackdrop` (`scripts/ui/menu_backdrop.gd`: the crew's bunker
garage, a slowly drifting camera over the three `*Model` heroes idling around the real `VanModel` on its chalk circle,
torches, a `HellgateModel` glowing through a breach; mood dawn / night / after, see `MenuBackdrop.pick_mood` and
`LastContract`; no GameWorld, no actors) behind the rows 01 Start a job, 02 Join a crew, 03 Voice setup, 04 Settings,
05 Quit, a status line and (while joined) the crew list. Start a job hosts a Steam lobby when Steam is up, else plays
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
`[game]` (`master_volume` 0..1, `fullscreen`, `resolution` "WxH", `voice_panel_visible`: `GameSettings`). The game reads
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
| `net.gd` (`Net`) | the authority kinds (`net_fields()`) and the static facade |
| `net_session.gd` (autoload **Session**, `NetSession`) | the crew session: ENet or Steam transport, hello handshake, roster, refusals, leaving, clock pings, telemetry rows, dev flags |
| `net_wire.gd` (`NetWire`, child `Session/Wire`) | the reliable event RPC (its own channel) and unreliable `send_bytes` packets with our own u16 sequence numbers; stale packets are dropped |
| `net_link.gd` (`NetLink`) | the lag/loss simulator on each process's inbound side (presets `off`, `coast`, `rough`) |
| `net_clock.gd` (`NetClock`) | `host_time()`: NTP-style pings, interval intersection of the window's bounds, slewed (never backwards) |
| `net_telemetry.gd` (`NetTelemetry`) | one CSV row a second per machine, clients' rows collected on the host (`user://net/`) |
| `steam_identity.gd` (`SteamIdentity`) | the one Steam init per process, the persona name |
| `steam_lobby.gd` (`SteamLobby`, child `Session/Lobby`) | lobbies: create, list, join, leave, invites, lobby data |

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
  packages): `Combat.melee_arc`, `Projectile` and `ArrowShot` use it, so swings and shots also break the mail
  but still never hit priced props or employees.
  A test or scene calls `GameWorld.begin(map, root_node3d)` first.
- **`Actor`** (`scripts/core/actor.gd`, extends Node3D): `team`, `max_hp`, `hp`,
  `move_speed`, `radius`, `dead`, `facing`, `climbing`. `move(dir, delta)` does the terrain
  rules, slide, climb slow-down, separation and ground snap. Also `apply_damage(amount, source)`,
  `heal(amount)`, `set_modifier(id, mult, duration)` (damage-taken multiplier; the same id
  refreshes), `has_modifier`, `face_point`, `current_cell`. Signals: `damaged`, `healed`, `died`.
  Override `_on_death()` for death visuals (the default is `queue_free`). Actors join the group `"actors"`.
  `net_fields()` says who may write each var (`Net.SPAWN/OWNER/PRIVATE/LOCAL`, `scripts/net/net.gd`);
  subclasses merge theirs into `super()`, and `test_net_contract` fails on any undeclared var.
  See `docs/design/networking.md` and `AGENTS.md`.
- **`Projectile`** (`scripts/combat/projectile.gd`): `Projectile.fire(shooter, from, dir, dmg, speed, range)`.
  Set `color`, `size` or `on_hit` before the first frame for custom behavior.
- **`Combat`** (`scripts/combat/combat.gd`): `melee_arc(attacker, dir, reach, arc_deg, dmg)`,
  `explode(pos, radius, dmg, team, source, edge_mult)`, `chest(actor)`.
- **Input** (`scripts/app/input_setup.gd`): `move_up/down/left/right` (WASD),
  `attack_melee` (LMB), `attack_ranged` (RMB), `cast_slot_1..4` (keys 1-4: ready/hold a spell slot),
  `use` (E: the van's clock-out slip, the elevator or an employee, in that order; never casts), `swap_pickup` (F: swap a dropped component into
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
```
Spell ids are lowercase: `heal`, `fireball`, `armor`, `corn`, `tentacles`. The voice layer listens for **all**
spells. The game decides whether the local hero knows the spell (and fizzles it if not).

### Spells (`scripts/spells/spell_book.gd`, `class_name SpellBook`)
```gdscript
const SPELLS := { "heal": {"name": "Heal", "cooldown": 8.0, "color": Color(...), "desc": "..."}, ... }
static func cast(id: String, caster: Actor, power: float, aim: Vector3) -> bool
```

### Forced movement (`Actor.shove`)
`Actor.shove(dir, distance, source = null)` starts a short (0.2-0.35 s, ease-out) kinematic slide of
`distance * shove_mult` along `dir` on X/Z (`shove_mult` 0 = immovable: Rebar; brute 0.4, swarmer 1.5).
It is driven by the tree's `physics_frame` signal only while active. While `is_shoved()` the actor ignores
`move()`; `is_helpless()` (shoved or staggered) is what the player controller, `AllyBrain`, `Monster` and the
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
`MonsterFactory.spawn(kind: String, cell: Vector2i) -> Monster`. Kinds: `grunt`, `archer`, `brute`, `swarmer`.
`MonsterFactory.spawn_pack(room_cells: Array[Vector2i], budget: int, rng) -> Array[Monster]`.
Monsters idle until a hero is within aggro range with line of sight, then act.

### Terrain (`scripts/world/dungeon_gen.gd`, `class_name DungeonGen`)
`DungeonGen.generate(seed: int, params := {}) -> HexMap`. Cells are tagged: `"start"` (one cell),
`"exit"` (one cell), `"room:<n>"` for room floors (so monsters can be packed per room; a room's cut border cells
carry its tag too), `"corridor"`. `HexMapView` (`scripts/world/hex_map_view.gd`, extends Node3D): `build(map)`.

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
about 130 ms (limit 300 ms, asserted in `test_dungeon_gen`). `SiteBuilder` then puts at most 6 priced props on a floor
(next to walls, 4+ apart, flush and square against the flat face: `ThemeCtx.wall_pose_at` marches to the face and
refuses a pose that would not stand flush; footprints must stay off the wall side, `ThemeCtx.rect_clear`), scales the monster pack budgets by 0.7 and caps a room at one monster per
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

Run the game: `.\run.ps1` (or `--scene res://scenes/arena.tscn` after `--`).
Engine: `$env:CAST_GODOT`, else `..\Hero-Reader\third_party\godot\Godot_v4.7-stable_win64_console.exe`.
