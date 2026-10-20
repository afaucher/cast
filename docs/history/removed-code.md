# Removed code: what it was, and where it still lives in git

Code that only had historical value comes out of the tree (docs/design/refactor-plan.md, bucket 1), and this file keeps
its story. Each entry says what the code did, what replaced it and why, and the commit that removed it.

Getting any of it back: `git show <removal commit>^:<path>` prints a removed file as it was just before removal, and
`git checkout <removal commit>^ -- <path>` restores it. `git log --diff-filter=D --stat -- <path>` finds the removal
commit if you only know the path.

Entries are grouped by the wave that removed them. Newest first.

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
