# Cast: instructions for agents

Cast is a co-op isometric action game in Godot 4.7 where players fight by speaking spells. Start
with `README.md`, then `docs/ARCHITECTURE.md` (code contracts, folder ownership) and
`docs/design/north-star.md`. Hero-Reader (`..\Hero-Reader`) is only where the speech-to-text pipeline
came from. Cast is not a reading game.

## This file overrides `scratch/AGENTS.md` for networking
The `AGENTS.md` one level up describes a different project: a host-only simulation, "spatial sensor
filtering" and a `receive_perceived_state` RPC. **Its Project Context and AI Guardrails 1-3 do not
apply to Cast.** Cast uses owner authority (`docs/design/networking.md`, option A): each player's
machine owns that player's hero and streams its state, and the host owns everything else. Guardrail
4 (run the tests) still applies; see Tests below.

## Networking rules (enforced by `tests/test_net_contract.gd`)
The transport, lobby, crew roster, clock and telemetry exist (M0 of `docs/design/networking-build-plan.md`; the
`Session` autoload), but there is no shared run yet. Every change has to keep co-op possible:
1. **Declare authority.** A class with gameplay state has `net_fields()` classifying **every** script
   var as `Net.SPAWN`, `OWNER`, `PRIVATE` or `LOCAL` (`scripts/net/net.gd`). Adding a var means
   adding it there with the right kind. A new non-actor gameplay class goes in the test's `NET_SCRIPTS`.
2. **Change other entities only through verbs:** `apply_damage`, `heal`, `shove`, `set_modifier` and
   `die`. Never write another actor's `hp`, `dead` or position.
3. **Resolve hits through `Combat`** (`melee_arc`, `explode`, `Projectile`) rather than your own loop
   over actors.
4. **Randomness:** gameplay rolls use `GameWorld.rng` or a generator seeded from the run; looks use
   `GameWorld.fx_rng`. Never use global `randf()`/`randi()`, and never use `GameWorld.rng` in `fx/`,
   `art/`, `ui/` or `world/grime/`.
5. **No network code outside `scripts/net/`**, and no Steam API either (`Engine.get_singleton("Steam")`,
   `SteamMultiplayerPeer`): ask `Net` / `Session`. Never use `unreliable_ordered` (GodotSteam sends it
   reliably), `MultiplayerSynchronizer` or `MultiplayerSpawner`, not even inside `scripts/net/`.
6. **New content takes one of four shapes:** a scheduled effect, an owned actor, a host-arbitrated
   world object, or cosmetic. Run the new-content checklist in `networking.md`. If it fits no shape,
   stop and design its networking first.

When the test fails, fix the code or the declaration. Don't widen an allowlist without a written
reason, and treat adding one as a design decision to report.

## Tests
- `.\test_runner.ps1 -TestAll` runs everything (the voice audio tests take about 5 minutes). Net tests with
  `const PEERS := N` run as N processes over ENet localhost (`NetTest`; `docs/ARCHITECTURE.md`, Tests).
  `.\build.ps1` runs all the tests and then exports.
- Run them after any code change.
- In a worktree, set `$env:CAST_GODOT` to `..\Hero-Reader\third_party\godot\Godot_v4.7-stable_win64_console.exe`
  (an absolute path), and copy the untracked speech files (`addons/hero_listen/bin`, `models/`,
  `data/pron_dict.txt`) from the main checkout.
