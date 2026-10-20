# Refactor plan: dead code out, content into units (2026-10-20)

Status: **in progress**. Done so far:
- wave 0: the golden-floor test and the history doc;
- wave 1: D1, except `tools/theme_options/`;
- wave 2: D2, except the beast's peek/whip, SignLine's pen and the factory planner; H1's single spell list; an Actor
  guard in test_net_contract.
- wave 4b: H8 step 1. Each floor feature's planner and spawner moved verbatim from `SiteBuilder` into
  `scripts/contracts/planners/` (`GatePlanner`, `EmployeePlanner`, `PropPlanner`, `HazardPlanner`, `NotePlanner`,
  `PackagePlanner`, `PackPlanner`, `ScoutPlanner`, `SharkPlanner`, `DoorPlanner`), each with `plan(...)` and
  `spawn(...)` on the old parameters. `SiteBuilder.plan` / `spawn` are the explicit ordered call lists; golden floors
  unchanged.

Moved to later waves:
- the factory's pack planner, to H3;
- the beast's peek/whip, which needs a visual check;
- `NoteFacts.ROOM_WORDS`, to H4. It holds the shorter names notes use, so it isn't a copy, and it belongs in the theme
  rows.

The rest is a proposal. Surveys were run against main at c2080ad; the line numbers are from then.

Two buckets, from the user's brief:
1. **Dead code that is only of historical interest** is removed, and each removal is written up in
   [`docs/history/removed-code.md`](../history/removed-code.md) with the commit that removed it (git keeps the code).
2. **Hot spots that collect code for many kinds of content** (creatures, spells, props, environments) are split into
   dedicated units, so new content is added in one place instead of across a dozen lists and switches.

Coordination: the main session has work in flight (lab branches, lava playtest fixes) and a queue (lava into the generator,
the sewer, the Water Cooler and Pavise as real monsters, more radio lines). Each wave below is a small branch, announced to
the main session with its file list before it starts and when it lands, and rebased on main just before merging.

## Why now (the numbers)

| | |
|---|---|
| Code | about 92k lines of GDScript in scripts/, plus 33k lines of tests |
| `game.gd` | 3,600 lines and 185 functions. Changed by 64 commits in the last 7 days, 3x more than any other file. About 850 lines and about 80 command-line flags are dev and screenshot drivers. |
| Other hubs | `site_builder.gd` 1,470 · `monster.gd` 1,350 · `net_session.gd` 1,250 · `hex_map_view.gd` 1,360 |
| Labs | 25 labs, about 10k lines; 22 of them parse their own `--shot` flags |
| Duck typing | about 100 `has_method(...)` and `.call("...")` calls |

What it costs to add one thing today:

| Content | Lists and switches to touch | The worst of them |
|---|---|---|
| Monster kind | about 8 lists (factory, models, LATE_JOIN, REPLICATED, gate weights, drops, pest names, pest tickets, triangle budget) | `"swarmer"` special-cased in 5 places. Pack composition is copied between `MonsterFactory` and `SiteBuilder`. |
| Spell | the `SpellBook.apply` match, the `component_props` match, `NetStatus._show` visuals, and the spell-id list written out in about 15 places | 2 tools are already stale at 9 spells |
| Runtime actor (like the chicken) | `is Chicken` in about 9 places in `net_world.gd`, plus the codec, join and objects | a second one would copy all of it |
| Prop | `TABLE` plus 3 parallel structures in `prop_models` (`HEIGHTS`, the build match, the palette match), plus `BLAST`/`FUSE_POINTS` for hazards | a hazard missing from `BLAST` silently becomes an oil drum |
| Host-arbitrated object (doors) | `NetFloor` collectors, the `NetObjects.begin` if/elif chain, its event and request matches, late join, and 4 net tables | |
| Interactable (E) | `game.gd` `use_target` if/elif, its `UseTarget` fields, the `_use_key` match | |
| Room theme | `THEMES` + `POOLS` + `THEME_FLOOR`/`THEME_WALL` + `ROOM_WORDS` (a copy of the names) + the vignette op match | |
| Origin room | the same string written in 3 places | |

## Bucket 1: dead code

Writing it up: each wave adds a section to `docs/history/removed-code.md` that names the removal commit. For each
item it says what the code did, why it was superseded (with the deciding commit and the decision doc, if any), and how
to get it back (`git show <commit>^:<path>`).

### D1: safe deletions (about 2,500 lines, low risk)
| Item | Lines | Superseded by |
|---|---|---|
| The toy-figure character kit (`art/art_mesh.gd`, `toon.gd`, `toy_figure.gd`, `character_kit.gd`, five `hero_*.gd`, `lineup.gd`), `character_lineup.tscn`, `test_art_kit.gd` | about 1,420 | the faceted low-poly crew (4fcae87, 7eb955a) |
| `pool_lab.gd` / `.tscn` (the four pool options) | 787 | shipped pools, science room and moat (3bce2d1, 0caf1c2) |
| `monster_preview.gd` / `.tscn` | 111 | `monster_lab`, `--spawn-near` |
| About 45 unreferenced functions and constants (e.g. `Hex.neighbor`, `van_circle.set_chalk_style`, `ContractParts.has_*`, `NetSnapshot.aim_of/out_rate/in_rate`, `Hud.toast_rect/clear_center`, `ThemeGeo.nearest_face`) | about 185 | none; each has one hit, its definition |
| `tools/stt_stagger/` (bench and results) | about 725 + 0.9 MB | flush-on-voice-end (321d96c) |
| `tools/theme_options/` mockups | 12 MB | the chosen forms look. **Ask:** keep these, or keep only the commit link? |

### D2: superseded but still referenced (about 1,100 lines, low to medium risk: callers change)
| Item | Lines | Caller cleanup |
|---|---|---|
| Unchosen sound recipes in `tools/sfx_proto` (rounds 1-3) | about 470 | `mic_leak_probe` and `make_sfx` switch to `GAME_CUES` |
| The `ContractParts` soft-link layer (`script_of`, null guards, stale `FALLBACK_PROPS`) | about 95 | about 10 game and lab call sites, plus about 45 test calls of `prop_catalog`, become direct calls |
| HUD mic meter (always hidden), `HudBar` | about 65 | `game.gd` `set_mic_level` per frame, plus 2 test lines |
| HUD centre text `show_center` | about 40 | `arena.gd` "You died", plus 1 test line |
| `SignLine` "pen" style, `SIGN_STYLE` | about 12 | none |
| `MonsterFactory.plan_composition/cost_of/spawn_pack` (the old pack planner) | about 90 | `test_monster_factory` (merged into the H3 work) |
| `monster_fight.gd` / `.tscn` | about 107 | `test_net_contract` allowlist line |
| Hellgate beast "peek" style and "whip" exit | about 250 | trim `hellgate_beast_lab` |

### D3: needs your decision (parked "for later" on purpose, or a test fixture)
| Item | Lines | Question |
|---|---|---|
| `PersonnelFile` (FORM 31) and `main_menu` `SHOW_FILE=false` branches | about 310 | It was parked "for later" (1f719df). Remove it and cite the commit, or keep it? |
| Storefront title-screen backdrop and `van_stand_in` | about 460 | It was "saved for the title card". Remove or keep? |
| Proto monster bodies (`use_proto_visuals`) and capsule heroes (`--proto-heroes`) | about 185 | Tests use them as a fast headless fixture. Replace them with a no-model path, then delete? |

**Keep (live, despite looking old):**
- the elevator style matrix;
- the `AllyBrain` restraint switch, which is measured;
- test seams such as `use_for_tests`;
- the labs for shipped features (look-dev harnesses; they get the lab base in H9 instead);
- every dev flag. These move to a module (H7), and none is deleted.

## Bucket 2: content into units

The pattern throughout: **a content kind describes itself once; the hubs read registries instead of matching on
strings.** In GDScript that means a small definition script per item, or a typed table row with a callable, in a folder
that a registry loads. Central matches become lookups. Lists derive from the registry, and tests check the registry.

### H1: one source of truth for ids (small, do first)
- **Spell ids:** `SpellBook.ids()` everywhere. That covers `VoiceCaster.DEFAULT_SPELLS`, the `VoiceSettings` and
  `Incantation` defaults, `voice_lab`, about 8 test constants and 4 tools (2 already stale).
- **Net registration:** one table per replicated script (its carriers, late-join kind and codec) in `NetEvents`.
  `test_net_contract.REPLICATED` and `LATE_JOIN` coverage derive from it, which ends the 4 parallel tables.
- **Origin rooms:** declared once, in the archetype event. `NoteCopy.STORY` and `ORIGIN_THEMES` refer to that event.
  `NoteFacts.ROOM_WORDS` derives from `THEMES[].name`.

### H2: spells as units
`scripts/spells/defs/<id>.gd`, one per spell, holds:
- the `SPELLS` row data;
- `apply(caster, power, aim)`;
- the component pickup's mesh and glow;
- the remote-status visual hook (today in `NetStatus._show`);
- the voice tuning aliases (today in `Incantation.TUNING`).

`SpellBook` loads the folder. `apply`, `component_props.make` and `NetStatus._show` become lookups, and `FOLLOWS` and
`_cast_extra` become fields on the def.

### H3: monster kinds as units
`MonsterDef` per kind: script, model builder, triangle budget, pack cost and weight, gate weight, component drop, pest
name and ticket, and a `pack_role` that replaces the `"swarmer"` special cases. The factory, `MonsterModels`,
`Hellgate.kind_weights`, `SpellComponents.DROPS`, `ClientArchetype.PEST_NAMES` and `NoteCopy.PEST_TICKETS` all derive
from it. One pack composer replaces the `MonsterFactory`/`SiteBuilder` copies.

Seed-built specials (scout, shark, and soon the Pavise and Water Cooler) declare a planner (see H8).
**Do this before the Water Cooler and the Pavise become real monsters.**

### H4: props and decor as units
- **Props:** each prop def keeps its row, build function, palette, height, and for hazards `BLAST`/`FUSE_POINTS` in one
  place. That ends `prop_models`' three parallel structures, and a missing blast becomes an error, not an oil drum.
- **Decor:** the same for `DECOR` and `decor_models`.
- **Themes:** the vignette op match becomes a table of ops.
- **Floors:** `THEME_FLOOR`/`THEME_WALL`/`THEME_LOOK` move into the theme row.

### H5: networked objects and runtime actors as units
- **Host-arbitrated objects:** they implement one interface: `net_link(objects)`, `net_event(kind, data)`,
  `net_request(what, data)`, `late_join_state()` and `apply_late_join()`.
  - `NetFloor` collects them by group, not by per-type recursion, and keeps tree order so ids don't move.
  - `NetObjects` dispatches through the interface instead of the `is X` chain.
- **Runtime actors:** the chicken is the template. One "runtime actor" track in `NetWorld`, with a codec field list
  per class, replaces the about 9 `is Chicken` branches.

### H6: interactables
A `Usable` contract on the van, elevator, employee, note, door and pickup: `use_priority(hero)`, `prompt()` and
`use(hero)`. `game.gd` `use_target` becomes a query, and `UseTarget` and the `_use_key` match go away.

### H7: split `game.gd` (3,600 lines down to about 1,200)
1. **`scripts/app/dev/`:** the flag parser, its header docs, and every dev and demo function, about 850 lines.
   - `game.gd` keeps one `_dev.on_floor_start(self)`-style hook per phase.
   - Lava keeps its `_lava_cave()` gate (live).
   - `test_main_menu`'s flag regex follows the parser.
2. Child nodes, each owning its phase:
   - `FloorStart`: build world, crew, arrivals, the barrier.
   - `ExitFlow`: elevator, van, drop-offs, invoice.
   - `JoinFlow` (M6).
   - `PauseFlow`: pause, abandon, leave, invite.
   - `ObjectiveFlow`: objectives, books, dispatch calls.

`game.gd` keeps the scene root, shared state and the phase order. Move code as-is first and refactor in place after.
**Do this before the lava and sewer go into the generator**: those builds land in these files.

### H8: `SiteBuilder` planners as units
Step 1 is done (wave 4b): the planners are their own files, with their old parameters, called in order by `SiteBuilder`.
Still to do: one `plan(p, ctx)` interface, the ordered registry and the loops.

Each feature becomes a planner script: gates, employees, props, hazards, notes, packages, packs, scouts, sharks, doors,
and next lava and the sewer. The interface is `plan(p, ctx)` with its own seeded dice, and `spawn(site)`.
- An ordered registry makes the spawn order, which is also the net-id order, explicit and tested.
- `plan()` and `spawn()` become loops.
- A new environment adds a planner, not edits across 1,470 lines.
- **Do this before lava and the sewer go into the generator.**

### H9: a lab base class
`--shot`/`--shot-after`/camera/resolution/quit handling moves into one `LabBase`, used by the 25 labs (22 parse this
themselves today). Low risk, and it shrinks every new lab.

## Guard rails for every wave
- **Golden-floor test, added first, before H3/H4/H8:**
  - Plan and build floors 1-3 for about 20 fixed seeds and record the `NetFloor` checksum, actor ids in order, and
    `SitePlan` contents.
  - Every refactor branch must reproduce them byte for byte.
  - Network and seed compatibility hang on rng draw order and spawn order, so this is the safety net.
- Move first, change after: a pure move commit (behaviour identical, tests green), then the cleanup commit.
- One hotspot per branch: full `-TestAll`, the known timing flakes rerun alone, `.import` churn restored.
- Each branch is announced to the main session with its file list, rebased on main right before merging, and its landing
  announced.

## Proposed order
| Wave | What | Size | Unblocks |
|---|---|---|---|
| 0 | Golden-floor test, `docs/history/removed-code.md` | S | the safety net |
| 1 | D1 deletions | S | |
| 2 | H1 single ids, and D2 (incl. the ContractParts inline and the old pack planner) | M | |
| 3 | H7 step 1: dev flags out of `game.gd` | M | every later `game.gd` change |
| 4 | H8 planners, and H3 monster defs (one composer) | L | lava/sewer in the generator; Water Cooler and Pavise as monsters |
| 5 | H7 step 2: phase nodes | L | |
| 6 | H2 spells, H5 net objects and runtime actors, H6 usables | L | new spells, new objects |
| 7 | H4 props/decor/themes, H9 lab base | M | |

Waves 3 and 4 should land before the main session's queued generator work, or be ordered with it.
