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
  `attack_melee` (LMB), `attack_ranged` (RMB), `cast_slot_1/2` (keys 1/2, keyboard fallback
  for voice), `toggle_voice_debug` (F1), `restart` (F5).

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
Spell ids are lowercase: `heal`, `fireball`, `armor`, `corn`. The voice layer listens for **all**
spells. The game decides whether the local hero knows the spell (and fizzles it if not).

### Spells (`scripts/spells/spell_book.gd`, `class_name SpellBook`)
```gdscript
const SPELLS := { "heal": {"name": "Heal", "cooldown": 8.0, "color": Color(...), "desc": "..."}, ... }
static func cast(id: String, caster: Actor, power: float, aim: Vector3) -> bool
```

### Heroes (`scripts/heroes/hero.gd`, `class_name Hero extends Actor`)
`spell_slots: Array[String]` (2 entries), `try_cast(id, power, aim) -> bool` (checks the slot
and the cooldown), `cooldown_left(id) -> float`. The player-controlled hero has `is_player = true`.
`PlayerController` reads input. `AllyBrain` drives AI allies.

### Monsters (`scripts/monsters/*.gd`, each extends `Monster extends Actor`)
`MonsterFactory.spawn(kind: String, cell: Vector2i) -> Monster`. Kinds: `grunt`, `archer`, `brute`, `swarmer`.
`MonsterFactory.spawn_pack(room_cells: Array[Vector2i], budget: int, rng) -> Array[Monster]`.
Monsters idle until a hero is within aggro range with line of sight, then act.

### Terrain (`scripts/world/dungeon_gen.gd`, `class_name DungeonGen`)
`DungeonGen.generate(seed: int, params := {}) -> HexMap`. Cells are tagged: `"start"` (one cell),
`"exit"` (one cell), `"room:<n>"` for room floors (so monsters can be packed per room),
`"corridor"`. `HexMapView` (`scripts/world/hex_map_view.gd`, extends Node3D): `build(map)`.

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
