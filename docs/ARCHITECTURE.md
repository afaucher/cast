# Cast: POC architecture and contracts

Co-op, voice-cast, isometric hex dungeon crawler. This is the **proof of concept**:
one PC, one mic, one keyboard/mouse player plus AI allies, and no networking.

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
| no flags, or only `--no-mic`, `--settings-file`, `--menu-shot`, `--menu-screen`, `--menu-say`, `--menu-after` | the main menu |
| any other `--flag` (`--seed`, `--spells`, `--contract`, `--floor`, `--shot`, every `game.gd` flag, flags added later) | `scenes/game.tscn`, as before |

`scripts/ui/main_menu.gd` (`MainMenu`) is the menu: `MenuBackdrop` (a slowly swaying camera over a generated
HexMapView + DungeonLook hall, the three `*Model` heroes idling and a `HellgateModel` in the distance; no GameWorld,
no actors) behind the buttons Start, Voice setup, Settings, Quit. Start calls `game.gd`'s `reset_flow()` and loads
`Boot.GAME_SCENE`, which opens on the job board. Sub-screens are `VoiceSetupScreen` (runs a real `VoiceCaster`
with the mic; edits the cast word, strictness and min-voice through the caster, which persists them via
`VoiceSettings`; live dB meter from `SpeechGate`; "Try it" shows HEARD, the matched spell and its power) and
`SettingsScreen` (`GameSettings`). Styling is shared in `MenuStyle`. Esc goes back (`pause` input action).
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
- **`GameWorld`** (autoload, `scripts/core/game_world.gd`): `map`, `root` (parent for
  actors/projectiles/fx), `time` (the game clock; use it, not wall time), `rng`,
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
- **`Projectile`** (`scripts/combat/projectile.gd`): `Projectile.fire(shooter, from, dir, dmg, speed, range)`.
  Set `color`, `size` or `on_hit` before the first frame for custom behavior.
- **`Combat`** (`scripts/combat/combat.gd`): `melee_arc(attacker, dir, reach, arc_deg, dmg)`,
  `explode(pos, radius, dmg, team, source, edge_mult)`, `chest(actor)`.
- **Input** (`scripts/app/input_setup.gd`): `move_up/down/left/right` (WASD),
  `attack_melee` (LMB), `attack_ranged` (RMB), `cast_slot_1..4` (keys 1-4: ready/hold a spell slot),
  `cast_readied` (E: cast the held spell at power 0.8), `swap_pickup` (F: swap a dropped component into
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
`"exit"` (one cell), `"room:<n>"` for room floors (so monsters can be packed per room),
`"corridor"`. `HexMapView` (`scripts/world/hex_map_view.gd`, extends Node3D): `build(map)`.

Zone layout (tuned so floors are not crowded): 6-9 rooms of radius 5-8 (`DEFAULT_RMIN/RMAX`) at least `DEFAULT_GAP`
(8) apart in an area of radius `DEFAULT_SIZE` (36); tree-link corridors are three wide, extra loops two wide
(the climb shortcut and one short chokepoint stay one wide); about half as many raised features per room, never
within `FEATURE_CENTER_CLEAR` (2) of a room's center or `FEATURE_DOOR_CLEAR` (3) of a door. Generation takes
about 80 ms (limit 300 ms, asserted in `test_dungeon_gen`). `SiteBuilder` then puts at most 6 priced props on a floor
(next to walls, 4+ apart), scales the monster pack budgets by 0.7 and caps a room at one monster per
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

Run the game: `.\run.ps1` (or `--scene res://scenes/arena.tscn` after `--`).
Engine: `$env:CAST_GODOT`, else `..\Hero-Reader\third_party\godot\Godot_v4.7-stable_win64_console.exe`.
