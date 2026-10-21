# Removed code: what it was, and where it still lives in git

Code that only had historical value comes out of the tree (docs/design/refactor-plan.md, bucket 1), and this file keeps
its story. Each entry says what the code did, what replaced it and why, and the commit that removed it.

Getting any of it back: `git show <removal commit>^:<path>` prints a removed file as it was just before removal, and
`git checkout <removal commit>^ -- <path>` restores it. `git log --diff-filter=D --stat -- <path>` finds the removal
commit if you only know the path.

Entries are grouped by the wave that removed them. Newest first.

## H5 (2026-10-20): per-type networking branches, removed in 11de02b..a50ab68
- **Paths:** in `scripts/net/net_objects.gd`: the `is PricedProp / ExplosiveProp / BreakableCrate / MailPackage /
  OfficeDoor` chain in `begin()`, the handlers `_on_prop_hurt`, `_on_broken`, `_on_mail_broken`, `_on_fuse`,
  `_on_douse`, `_on_door`, `_on_door_smashed`, `_client_fuse` and `_client_break` (with its door and mail special
  cases), the `obj.door` / `obj.fuse` / `obj.out` / `obj.hurt` cases of `_on_event`, the `door` and `follow` / `wait`
  cases of `_host_request`, and the per-type loops of `late_join_state` / `apply_late_join` (11de02b, 1343ed5, 6591c44,
  8fe8e81, 6aab8e9). In `scripts/net/net_floor.gd`: `doors_under`, `_collect_doors`, `pickups_under`,
  `_collect_pickups` (c3d6b3f). In `scripts/net/net_world_codec.gd`: `CHICKEN_FIELDS`, `read_chicken`, `write_chicken`;
  in `scripts/net/net_world.gd`: `const CHICKEN` and its branches (015c86a). About 200 lines.
- **What it was:** every host-arbitrated object class had a branch in each of NetObjects' places (links, client events,
  requests, breaks, late join) and a collector in NetFloor; the chicken, the one runtime-spawned host actor, had its own
  kind, field list and read/write in NetWorld and its codec.
- **What replaced it:** the net-object contract on each class (`net_link`, `net_event`, `net_request`,
  `late_join_state` / `apply_late_join`, `net_order`, `net_make_copy`), `NetFloor.objects_under`, and
  `NetWorldCodec.RUNTIME_ACTORS` with `Chicken.net_read` / `net_write` on one `RUNTIME` track (refactor-plan.md H5).
  The code moved into the classes; nothing changes on the wire or in play.

## H6 (2026-10-20): the E key's if/elif chain, removed in 0ba7bbe
- **Path:** in `scripts/app/game.gd`: `class UseTarget` (kind, verb, pos and an `employee` / `note` / `door` field per
  kind), the if/elif chain in `use_target()` that filled it, the `match t.kind` in `_use_key()`, and the
  `PROMPT_ABOVE_VAN` / `_ELEVATOR` / `_PICKUP` constants. About 70 lines.
- **What it was:** the one place that decided what E acts on (the van exit, then the elevator, then an employee, a note,
  an office door, a pickup) and what the press did for each. A new interactable meant editing all three.
- **What replaced it:** the `Usable` contract (`scripts/app/usable.gd`, refactor-plan.md H6). Each kind's branch moved
  into its own class's `use_*` methods (the van and the elevator into `VanExitUse` / `ElevatorUse`), `use_target()`
  ranks one candidate per kind by score bands that keep the old order, and it returns a `Usable.Target`. Nothing changes
  in play.

## Wave 2 (2026-10-20): superseded code that still had callers, removed in fcf91f2

Each piece below still had a caller, and the caller changed with it in the same commit. Nothing changes in play, and
`test_golden_floor` shows every floor unchanged.

### ContractParts, the "soft links"
- **Path:** `scripts/contracts/contract_parts.gd`, about 70 lines.
- **What it was:** while the contract parts were built in parallel (1203fd5), the generator and the game reached Hellgate,
  Employee, PricedProp and DamageTicker through `load()` and `ResourceLoader.exists()`, so everything ran even with a
  part missing. It also kept a `FALLBACK_PROPS` list of props that never shipped (throne, cinema screen, gold bars,
  trophy case).
- **Why it went:** every part has existed since then. The callers now use `Hellgate.spawn`, `Employee.spawn`,
  `PricedProp.spawn` and `PricedProp.catalog`, and `DamageTicker.new()` directly: `SiteBuilder`, `game.gd`, two
  labs, the z-fight registry, the grime bench and about 20 tests.

### The HUD mic meter and centre text
- **Paths:** in `scripts/ui/hud.gd`: the `MIC` label and bar, the `HudBar` control, `set_mic_level` (and `game.gd` feeding
  it every frame), `show_center` and its label. About 90 lines.
- **What it was:** the mic meter was hidden during play on 2026-10-18 (3534ea5). Voice setup and the F1 panel still show
  the mic. The big centre text carried "FLOOR CLEAN", "ORIGIN GATE CLOSED", "Floor 2 of 3" and "Crew incapacitated",
  and all of those became dispatch calls or went away in 6c06ed1 and fa1d083.
- **What's left:** only the arena test scene still used centre text. Its "You died" is now a toast.

### The monster fight scene
- **Paths:** `scripts/monsters/monster_fight.gd`, `scenes/monster_fight.tscn`, and its line in the
  `test_net_contract` write allowlist. About 107 lines.
- **What it was:** an early screenshot scene that put monsters in front of the crew. It could also show the old
  primitive bodies with `--proto-monsters`.
- **Why it went:** the game's `--spawn-near kind,n` (with `--idle-monsters`, `--zoom` and `--focus`) does the same job on
  a real floor.

### Sound audition rounds 1-3
- **Paths:** in `tools/sfx_proto/sfx_synth.gd` and `sfx_round3.gd`: every recipe the game doesn't render (41 functions)
  and the `CUES`, `V2` and `CUES3` lists. About 510 lines.
- **What they were:** the procedural and recorded sound options the user auditioned on 2026-10-18:
  - round 1: 03f7414;
  - round 2: 2f8d255;
  - round 3: 13ef198 and 435ab0c.
  
  The picks are recorded in `docs/design/audio-plan.md`.
- **What's left:** the recipes named in `render_game_sfx.gd` `GAME_CUES` and everything they call, found by a call-graph
  walk. The rendered cues are byte-identical to before.
- **Tool changes:** `make_sfx` and `mic_leak_probe` now default to `GAME_CUES`. To hear a removed take, check out
  `fcf91f2^` and run `make_sfx` with its name.
- **Recordings:** some recordings under `assets/audio/third_party/` are now used by no recipe. They are untracked; see
  `SOURCES.md`.

### Not removed, on purpose
- **SignLine's "pen" signature:** form-rules.md still lists the grease pencil as a player mark, and it's 12 lines.
- **MonsterFactory's pack planner:** `plan_composition`, `cost_of` and `spawn_pack` go when one pack composer replaces it
  and `SiteBuilder`'s copy (refactor plan H3). They are tested today.
- **The hellgate beast's lab-only "peek" style and "whip" exit:** these share the shipped abyss look's shader, so removing
  them needs a visual check. They are deferred.

## Wave 2, also: single sources (d01ccc6)
Nothing was removed; this records where the duplicate lists went. The spell id list was written out in about 12 places:
- `VoiceCaster.DEFAULT_SPELLS`;
- the `Incantation` and `VoiceSettings` defaults;
- `voice_lab`;
- two tools, two of them stale at 9 spells;
- six voice tests.

All of them now read `SpellBook.ids()`, via `VoiceCaster.default_spells()`.

## Wave 1 (2026-10-20): dead code, removed in 04c4eb4

Nothing here had a caller left when it went. `test_golden_floor` showed every floor unchanged.

### The toy-figure character kit
- **Paths:** `scripts/art/art_mesh.gd`, `toon.gd`, `toy_figure.gd`, `character_kit.gd`, `hero_wick.gd`, `hero_gasket.gd`,
  `hero_rebar.gd`, `hero_gulp.gd`, `hero_sir_rattles.gd`, `lineup.gd`, `scenes/character_lineup.tscn`,
  `tests/test_art_kit.gd`. About 1,420 lines.
- **What it was:** the first procedural character look-dev (fe42ff1): a toon and outline material kit, and five heroes
  built in "toy", "heroic" and "flat" styles, side by side in a lineup scene.
- **Why it went:** the crew became faceted low-poly. 4fcae87 chose that look and dropped Sir Rattles and Gulp, and 7eb955a
  made the faceted crew the default (`scripts/art/lowpoly/`, `LowPoly` + `LowPolyMaterial`). Nothing used the kit after
  that.

### The pool options lab
- **Paths:** `scripts/art/lowpoly/pool_lab.gd`, `scenes/pool_lab.tscn`. 787 lines.
- **What it was:** four pool options on real terrain (basin, inset, lab tank, flooded floor), rendered for the
  `docs/design/pool-options.md` decision (f9e8e34).
- **Why it went:** the game shipped in-ground wading pools, the science room tank and the moat (3bce2d1, 0caf1c2), built
  by `PoolGeo`, `PoolView` and `PoolProps`. The lab was look-dev only. The shark, sewer and lava labs grew from the
  same idea, but none extends it.

### The monster preview scene
- **Paths:** `scripts/monsters/monster_preview.gd`, `scenes/monster_preview.tscn`. 111 lines.
- **What it was:** a first-day scene (1fa8af4) that stood the monster kinds in a row.
- **Why it went:** `monster_lab` (f50d42f) and the game's `--spawn-near` flag do the same job with the real models.

### The STT stagger bench
- **Paths:** `tools/stt_stagger/` (`stagger_bench.gd`, `analyze.py`, `compare.py`, `run_bench.ps1`, `run_all.ps1`, and 44 result
  CSVs and logs). About 725 lines of code and 0.9 MB of results.
- **What it was:** the research prototype behind `docs/design/stt-latency-staggered-streams.md`. It ran 1-N recognizer
  streams started at staggered times, to cut the delay before a spell word is heard.
- **Why it went:** flush-on-voice-end (321d96c) gave the latency win with one stream, so staggered streams were never built.
  The doc keeps the findings. Its reproduction commands work against `04c4eb4^`.

### Unreferenced functions and constants (about 145 lines)
Each had exactly one hit across scripts, tests, tools, scenes and docs: its own definition.

| Where | What |
|---|---|
| `art/lowpoly/props/decor_models.gd` | `_oval` |
| `art/lowpoly/props/elevator_model.gd` | `MOUTH_HALF`, `MARBLE_V` |
| `art/lowpoly/props/van_model.gd` | `GRIME`, `ABS`, `HOSE_Y` |
| `art/lowpoly/props/van_circle.gd` | `set_chalk_style`: the bold-chalk look for the rug (2267bf1), dropped when the garage went back to the plain chalk circle (fa4af24) |
| `art/lowpoly/props/van_rug.gd` | `set_van_yaw`, `set_scorch`; the shader's `scorch` uniform stays at 0 |
| `contracts/contract_parts.gd` | `has_hellgate`, `has_employee`, `has_prop`, `has_ticker` (from when the parts were built in parallel, 1203fd5) |
| `contracts/contract_session.gd` | `floor_clean` (its "FLOOR CLEAN" screen text became a dispatch call in fa1d083) |
| `contracts/hellgate_events.gd`, `package_spill.gd`, `van_lab.gd` | `on_gate_closed`, `bit_count`, `_shot_done` |
| `fx/chicken_fx.gd`, `fx/fireworks_fx.gd` | `ZERO_COLOR`; `burst_time` (the fireworks play a recorded bang per rocket since e32ef06) |
| `heroes/arena.gd`, `spells/component_props.gd`, `spells/spell_book.gd` | `_shot_frame`, `PLATE_DARK`, `FIREBALL_RANGE` |
| `net/net_codec.gd`, `net_interp.gd`, `net_snapshot.gd`, `net_world.gd` | `EXTRA_CARRIERS`, `target_delay`, `aim_of`, `out_rate`, `in_rate`, `is_shown` |
| `ui/backdrops/backdrop_kit.gd`, `ui/forms/form_stamp.gd`, `ui/hud.gd` | `class Spinner`, `set_lines`, `toast_rect`, `clear_center` |
| `voice/voice_caster.gd` | `is_voice_active` |
| `world/floor_materials.gd`, `grime/grime_layer.gd`, `pool_geo.gd`, `pool_view.gd` | `W_SLATE`, `GRID_COLS`, `GANTRY_SPAN`, `strip_mesh` |
| `world/themes/room_themes.gd`, `theme_geo.gd` | `facing_of`, `yaw_diff`, `nearest_face` (all from f3752d8) |
| `tests/test_net_interp.gd` | `_truth_vel` |

**Kept on purpose:** a few small API pieces with no caller today, which are part of an obvious interface:
- `Hex.neighbor` (listed in ARCHITECTURE.md);
- `Net.applying`, beside the write guard;
- `NetSession.JOB_RUNNING`, named in the networking build plan;
- `LowPolyModel._swing_tween`, which subclasses use.

### Not removed yet
`tools/theme_options/` (12 MB of mockups of the rejected UI and backdrop options) waits for the user's call.
