# Cast

**Licensed Budget Sorcery.** A co-op exploration game where you fight with spoken spells. You are a
crew of cut-rate contract sorcerers sent to clear demons out of billionaires' survival bunkers and
villain lairs. Say "cast heal" out loud, aim at your friend, and try not to say "corn".

The tone is "Overcooked with magic": the chaos comes from the players, and a well-oiled crew still
gets paid. Speech recognition runs on-device (the sherpa-onnx `WordListener` extension from Hero-Reader).

## Play

- **Exe:** `build\windows\Cast.exe` (made by `.\build.ps1`). Keep the DLLs and `Cast.pck` beside it.
- **From source:** `.\run.ps1`.

The game opens on the **main menu** (arrows or Tab and Enter, or the mouse; Esc goes back):

1. **Voice setup first.** Pick your cast word and strictness, then say "cast heal" and watch what the
   game HEARD, the matched spell and its power. The mic meter shows your level in dB, the min-voice
   line, the learned noise floor and your last voice peak. Raise the line until the TV stops showing
   up; your own voice should still go past it.
2. **Settings:** volume, fullscreen or windowed, window size, and whether the voice debug panel is
   open when a contract starts. Everything is saved.
3. **Start** opens the job board.

### A contract
1. **Job board:** dispatch offers three jobs from different clients (prepper billionaire,
   supervillain, wellness guru, tech founder, influencer). Each shows objectives, pay, danger and a
   property warning.
2. **Pick two spells**, then go down.
3. **Three floors.** Close hellgates, exterminate the pest you were hired for, and rescue employees.
   They follow you, and pay $100 each if you get them out. Floor 3 holds the big **origin gate**.
4. **The freight elevator** (press **E** at it) goes down a floor or cashes out. Leaving early always
   works.
5. **The invoice** bills the client: what you earned, minus property damage (capped at the
   contract's value, and never below $0), with the culprit named on every broken gold toilet.

HP carries between floors; everything resets between contracts.

### The crew
| Hero | Primary (LMB) | Secondary (RMB) | Quirk |
|---|---|---|---|
| **Wick** (you, 85 HP) | bow bash | arrows: tap, or hold to draw a piercing shot | climbs fast |
| **Gasket** (ally, 120 HP) | pipe-wrench hammer | 360° spin with heavy knockback | stout, hard to shove |
| **Rebar** (ally, 160 HP) | slam fist | bowls a boulder that shoves everyone in its path | can't climb +2, can't be shoved |

### Controls
| Input | Action |
|---|---|
| WASD | Move. Step up 1 level, climb 2 (slowly); 3 is a wall. Stairs bridge big gaps |
| Mouse | Aim. Spells and shots land at the ring; it turns green when it locks onto a teammate |
| LMB / RMB | Primary / secondary attack |
| **Say "cast heal"** etc. | Cast any spell in your four slots. Fumbles weaken it or fizzle it |
| 1 – 4 | Hold that slot's spell: it recharges 15% faster, and its component shows in your hand |
| E | Cast the held spell. At the freight elevator, open the elevator menu instead |
| F | Swap a component on the floor into your held slot |
| Enter | Type an incantation instead of speaking |
| F1 | Voice debug panel: what the mic hears and what the game did |
| F5 | Abandon the contract and return to the job board |
| Esc | Pause (Resume, Abandon contract, Main menu) |

### Spells
Six spells: **heal**, **fireball**, **armor**, **corn** (a corn bomb from the sky that hits
everyone), **tentacles** (neon tentacles burst from the floor and shove everything outward) and
**teeth** (too many teeth sprout out of everyone in the area, then pop; a heal pulls them).

- **Aiming:** everything lands where you aim, so to heal a friend you point at them.
- **Fire:** a fireball can set anyone near the blast on fire (monsters, teammates, employees) for 5 to 10 seconds of mild damage. It never spreads, and healing doesn't put it out.
- **Charges:** each cast spends a charge of that spell's material component. Monsters
  occasionally drop components. Walk over one to collect it, or press F to swap it into a full
  slot.

### Voice
- **Cast word:** "cast" by default. The alternatives are magic, pickle, conjure, invoke, summon,
  presto, or a custom word.
- **Strictness:** strict, loose (the default) or chaos. Accidental casts are a feature, and in loose
  mode corn fires on any mention.
- **Speech gate:** it only lets speech-like audio through to the recognizer, so typing, fans and the
  digital silence of noise-suppressed mics don't produce phantom words. If a TV or voice chat still
  shows up as heard text, raise **min voice** in Voice setup.
- **Log:** every utterance is logged to `%APPDATA%\Godot\app_userdata\Cast\voice_log.csv`.

## Develop

```powershell
.\test_runner.ps1 -TestAll                # every headless test (the voice audio tests take ~5 min)
.\test_runner.ps1 -TestName test_hex      # one test
.\build.ps1                               # all tests, then export build\windows\Cast.exe
```

- **Engine:** Godot 4.7. `godot_env.ps1` uses `$env:CAST_GODOT`, or the copy installed in `..\Hero-Reader`.
- **Not committed:** the speech DLLs (`addons/hero_listen/bin`), the zipformer model (`models/`) and
  the pronunciation dictionary (`data/pron_dict.txt`). Copy them from `..\Hero-Reader` (see
  `.gitignore`). The Godot 4.7 export templates go in `build\deps`.
- **Dev flags** (after `--`) skip the menu, for example `--seed 7 --contract 0 --spells heal,corn
  --no-mic`, `--floor 3`, or `--shot <png> --shot-after 4` for screenshots. They're listed at the
  top of `scripts/app/game.gd`. `--menu` brings the menu back.
- **Labs** (`--scene res://scenes/<name>.tscn`): `terrain_preview`, `voice_lab`, `wick_lab`,
  `gasket_lab`, `rebar_lab`, `monster_lab`, `hellgate_lab`, `employee_lab`, `prop_lab`, `package_lab`, `van_lab` (the crew's work van arriving over its summoning circle), `teeth_lab`,
  `backdrop_lab` (the garage behind the main menu and the job board, plus the storefront prototype: `--option garage|storefront`, `--mood dawn|night|after`, `--hero wick|gasket|rebar`, `--board` lays the real job board over the garage).
- **Tests:** the runner fails a test on any `SCRIPT ERROR`. Logs go to `test_logs/`.

### Docs
- `docs/ARCHITECTURE.md`: code contracts and the boot flow.
- `docs/design/north-star.md`: the pillars ("Overcooked with magic"). Start here.
- `docs/design/`:
  - `contracts.md`: jobs, pay, the invoice.
  - `spells.md`, `spells-and-components.md`: spells, slots, drops.
  - `characters.md`: the crew.
  - `environment.md`: bunkers, lairs, set dressing, grime.
  - `voice-mechanic.md`: grammar, accidents, the speech gate.
  - `exploration.md`: terrain, climbing, secrets.
  - `networking.md`: the online co-op plan (owner authority) and how it handles lag.
  - `poc-backlog.md`: what's next.
