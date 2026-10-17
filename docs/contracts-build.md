# Contracts: build spec (shared contracts between parallel agents)

The design is in `docs/design/contracts.md`; read it first. This file fixes the **interfaces**,
so four agents can build in parallel without touching each other's files.

## Already in place (lead)
- `GameWorld.TEAM_NEUTRAL = 2`, for employees and priced props. Area effects that use
  `actors_in_radius(pos, r, -1)` (corn, teeth, tentacles shoves) hit them automatically. Monsters
  target `TEAM_HEROES` only, unless the employees agent extends that.
- **Autoload `Ledger`** (`scripts/contracts/contract_ledger.gd`):
  - `begin_contract(value)`, `end_contract()`;
  - `earn(label, amount, who)`, `damage(label, amount, culprit)`;
  - `earned()`, `damages()`, `deducted()`, `payout()`, `damage_by_who()`;
  - `lines`, `floor_number`;
  - signals `changed`, `line_added`.

  Payout = `max(0, earned - min(damages, contract_value))`.

## Ownership (only edit your own files; everything else is read-only)
| Agent | Owns |
|---|---|
| **A: contract flow** | `scripts/contracts/contract*.gd` (not the ledger), `scripts/contracts/client*.gd`, `scripts/contracts/story*.gd`, `scripts/contracts/site*.gd`, `scripts/ui/job_board.gd`, `scripts/ui/invoice*.gd`, `scripts/ui/objective_tracker.gd`, `scripts/ui/elevator_menu.gd`, `scripts/app/game.gd`, `scripts/ui/hud.gd` (small additions), `tests/test_contract_flow*.gd`, `tests/test_contract_gen*.gd` |
| **B: hellgates** | `scripts/contracts/hellgate*.gd`, `scripts/art/lowpoly/props/hellgate_model.gd`, `tests/test_hellgate*.gd` |
| **C: employees** | `scripts/contracts/employee*.gd`, `scripts/art/lowpoly/props/employee_model.gd`, `tests/test_employee*.gd`. May make a small, additive edit to `scripts/monsters/monster.gd` so monsters sometimes target employees. |
| **D: priced props** | `scripts/contracts/priced_prop*.gd`, `scripts/art/lowpoly/props/*` (except hellgate/employee models), `scripts/contracts/damage_ticker.gd`, `tests/test_priced_prop*.gd`. May add props to fireball's and bowl's damage: a small, additive edit to `scripts/spells/spell_book.gd` / `scripts/heroes/bowl_boulder.gd`. |

## Interfaces (each owner implements exactly these; agent A calls them)
### B: `class_name Hellgate extends Actor`
- Team `TEAM_MONSTERS`, so hero attacks and spells damage it like any monster. Immovable
  (`shove_mult = 0`). Doesn't walk or attack.
- `static func spawn(cell: Vector2i, opts: Dictionary) -> Hellgate`. `opts` holds:
  - `difficulty: float` (0..1, the contract difficulty);
  - `depth: int` (floor 1..3);
  - `origin: bool` (the floor-3 big gate);
  - `pest: String` ("" = mixed, or a monster kind like "swarmer");
  - `max_hp` (optional override).
- **Spawning:** spawns monsters via `MonsterFactory.spawn(kind, cell)` near itself.
  - The interval and burst size scale with `difficulty` and `depth`.
  - A cap on its living spawns.
  - The kind comes from `pest`, or a weighted mix.
- **Origin gate:** bigger, with more HP and phases (spawning faster as it weakens) and a defensive
  shove burst at phase changes.
- **Signals:** `closed(gate: Hellgate)`; also `GameWorld.actor_died` as usual.
- **Closing the origin gate** emits `Hellgate.origin_closed` (a static signal on a helper, or a
  group call), and gate spawns stop site-wide. A has to stop, or at least ignore, strays.
- Spawned monsters carry meta `"from_gate"` = the gate.

### C: `class_name Employee extends Actor`
- Team `TEAM_NEUTRAL`, fragile (~30 HP). Hit by everything area-based, friendly fire included,
  with NO hero friendly-fire floor.
- `static func spawn(cell: Vector2i, opts: Dictionary) -> Employee`. `opts` holds:
  - `style: String` ("staff" for a bunker, "henchman" for a lair);
  - `name: String`.
- **Behaviour:**
  - cowers in place;
  - panics and flees when a monster is near;
  - once a hero comes within ~2 they **follow that hero** (an escort), staying close and pathing
    with `HexMap.find_path`.
- `is_following() -> bool`, `leader() -> Actor`.
- **Signals:** `rescued(e)` (A emits this through `extract()` when the employee is at the elevator
  as the crew leaves) and `died`.
- `func extract() -> void`: A calls it for followers within ~3 of the elevator when the crew takes
  it. It plays a little exit and removes the employee. A pays $100 per extracted employee and $10
  per employee alive at the end of the contract (an escort elsewhere counts as alive).

### D: `class_name PricedProp extends Actor`
- Team `TEAM_NEUTRAL`, immovable, with a price in dollars and a display name ("Vintage 1787 wine
  rack").
- `static func spawn(cell: Vector2i, kind: String, opts: Dictionary) -> PricedProp`, where `kind`
  comes from D's prop catalog.
- `static func catalog(site_type: String) -> Array[String]`, for site types "bunker" and "lair".
- Takes damage from area effects and shoves:
  - an actor shoved into it damages it;
  - the bowl damages it;
  - fireball damages it.
- When **broken** (HP ≤ 0), it calls `Ledger.damage(display_name, price, culprit)`, where the
  culprit is the damage source (it may be partial, e.g. a price share per hit; D's call, documented).
- Shows its price tag within ~3 of a hero. Faceted art with a destruction debris effect.
- `DamageTicker` (a Control) shows each new damage line live ("-$1,200 Wine rack (Wick)"). A adds
  it to the HUD.

### A: the flow (it integrates everyone)
- **Boot →** job board (3 new offers) → spell picker → floor 1 → … → invoice → job board.
- Builds the `ContractRun`:
  - client archetype, from a data table;
  - story: the inciting event plus the origin room;
  - pest;
  - objectives, priced;
  - difficulty;
  - 3 floors.
- **Site placement per floor**, using the `DungeonGen` tags (`room:<n>`, `start`, `exit`):
  - hellgates: floors 1–2 small, floor 3 the origin gate in the origin room;
  - employees, in the rooms farthest from the origin;
  - priced props along room edges (from D's catalog);
  - the existing monster packs, biased toward the pest.
- **Elevator** (the exit cell) menu: "Go down to floor N" / "Exit" (floor 3: exit only), and the floor-1 van's clock-out
  slip. The early exit always works; see `docs/design/contracts.md`, "Mission structure".
  - HP and downed state carry between floors; everything resets per contract.
  - Spells are re-picked per contract.
- **Objectives** (exact pay from `contracts.md`): close hellgates ($3k each; origin gate more),
  exterminate the pest, employees ($10 alive, $100 extracted).
- **Objective tracker** on the HUD; the damage ticker comes from D.
- **Invoice screen:** it looks like an actual invoice. Letterhead from the client, line items per
  floor, deductions with culprits, the capped total, and NET PAYOUT. Then back to the board.

## Shared rules
- Faceted low-poly style (`LowPoly`, `LowPolyMaterial`, `MonsterMaterial` for enemy glow).
- Typed GDScript (Variant-inference warnings are errors), UTF-8 files.
- Don't commit.
- The runner fails any test whose output contains "SCRIPT ERROR".
- Run your own tests with `.\test_runner.ps1 -TestName <name>`. Only agent A runs `-TestAll` at the
  end, and it reports other agents' failures rather than fixing them.
