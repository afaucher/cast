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

| Row | Does |
|---|---|
| **01 Start a job** · *crew can join* | Opens the job board. With Steam running it also opens a crew (a Steam lobby) friends can join; without Steam it is solo, and the board says "Steam not running: solo only". |
| **02 Join a crew** · *first crew hiring* | Joins the first crew hiring for this build, or says "No crews hiring right now". Greyed out ("Steam not running") without Steam. While you're in a crew it reads **Leave the crew**. |
| 03 Voice setup · 04 Settings · 05 Quit | As below. |

1. **Voice setup first.** Pick your cast word and strictness, then say "cast heal" and watch what the
   game HEARD, the matched spell and its power. The mic meter shows your level in dB, the min-voice
   line, the learned noise floor and your last voice peak. Raise the line until the TV stops showing
   up; your own voice should still go past it.
2. **Settings:** volume, fullscreen or windowed, window size, and whether the voice debug panel is
   open when a contract starts. Everything is saved.
3. **Start a job** opens the job board.

### Online play (in progress)
Online co-op is being built in milestones (`docs/design/networking-build-plan.md`). **Today (M2) a crew shares one
run and walks it together**: the host rolls the job board and its three offers appear on every player's board (read-only for
the others, "the host picks the job"); the host takes a job; everyone signs **their own** license checkout (that is
the "ready" step, and the others see "waiting for <name>"); every machine builds the same floor from the contract
seed behind a load barrier, checks that it is the same floor (a floor that differs is refused with "Desync:
different floor"), and the van arrival plays on every screen from the same moment. Then **every player moves their own
hero, with no lag on their own screen, and sees the others walk, turn and animate** (about a tenth of a second behind),
each with the player's name over their head. If a player drops, the AI takes their seat back as the character that seat
started as (Rebar or Gasket), right where they stood. **Monsters, hellgates, employees and pickups are not synced yet**
(M3), and casts, hits and damage across machines come in M4, so on a client the host's world is a frozen copy and
fighting is for later. Exits (elevator, van) and the pause are not shared yet either: while a crew is on a floor, Esc
opens the menu without pausing, and the only way out is Main menu (a client leaves the crew; the host asks first, because
it ends the job for everyone).

Up to 3 players (one per crew slot); a 4th is told "Crew is full", a different build is refused, a crew already on a
job is closed ("That crew is already on a job"), and when the host leaves everyone else is told "The host clocked
out". Invites from the Steam overlay join directly. A host with nobody else in the crew plays exactly the solo game.

**Two or three instances on one PC** (ENet on localhost, no Steam needed):

```powershell
.\run.ps1 -Crew 2                 # a host window (job board) and a joiner window (the same board, read-only)
.\run.ps1 -Crew 3 -Link coast     # three players, each window simulating a coast-to-coast link
.\run.ps1 -Crew 2 --seed 7 --net-wait 2 --contract 1 --spells heal,corn   # the host takes offer 2 once both are in; both sign heal+corn
.\run.ps1 -Crew 2 --seed 7 --net-wait 2 --contract 1 --spells heal,corn -ShotDir C:\shots   # ... and each window saves <Name>.png and quits
.\run.ps1 -Crew 2 -Bot 2 --seed 7 --net-wait 2 --contract 1 --spells heal,corn   # window 2's hero walks a loop by itself (--net-bot); walk window 1 with WASD and watch it move there
```

Or by hand, in two terminals:

```powershell
.\run.ps1 --net-host --net-name Alex                         # host over ENet on port 24600, opens the job board
.\run.ps1 --net-join 127.0.0.1 --net-name Sam --no-mic       # join it: you land on the host's job board
```

Online dev flags (after `--`): `--net-host` (host over ENet), `--net-join <ip[:port]>`, `--net-port <P>` (default
24600), `--net-link off|coast|rough` (simulated lag and loss on everything this process receives: coast is 45 ms each
way, ±15 ms, 1.5% loss), `--net-name <name>` (the roster name; Steam's name otherwise), `--net-steam-probe` (create one
real Steam lobby through the host path, print it, leave and quit: the quick Steam check), `--net-wait N` (the host stays
on the board until the crew has N members, then takes offer `--contract`, default the first). `--spells a,b` signs
that license without the checkout, in every window. `--net-bot` makes this window's hero walk a loop of the start area by itself
(`run.ps1 -Bot N` gives it to window N only; the others see it move). `--shot <png>` saves a screenshot 3 s after the shared start and
quits (`--shot-after S` to change it); `run.ps1 -ShotDir <dir>` gives each window its own file.

**Network telemetry** is passive: one CSV row a second per machine in `%APPDATA%\Godot\app_userdata\Cast\net\`
(the host's file also holds every client's rows). Read a gap as "missing", never as zero.

### A contract
1. **Job board:** dispatch offers three jobs from different clients (prepper billionaire,
   supervillain, wellness guru, tech founder, influencer). Each shows objectives, pay, danger and a
   property warning.
2. **Pick two spells** at the license checkout (a scrolling catalog of every spell with its details), then go down.
3. **Three floors, only ever down.** The crew's work van teleports in on floor 1 and stays parked there;
   floors 2 and 3 have no van, you just start. Close hellgates, exterminate the pest you were hired for, and
   rescue employees. Press **E** next to one to bring them along; once a follower reaches an exit (the van's
   door or the elevator) they leave right away and pay $100, and any still following when you take an exit
   go with you. Floor 3 holds the big **origin gate**.
4. **Two ways out.** The **freight elevator** (press **E** at it, on every floor) goes down a floor or exits
   (floor 3: exit only). The **van** (press **E** at its side door, floor 1 only) clocks out and invoices
   the client. Leaving early always works: unfinished objectives simply do not pay.
5. **The invoice** bills the client: what you earned, minus property damage (capped at the
   contract's value; that part never goes below $0), with the culprit named on every broken gold toilet.
   Then corporate bills **$10,000 for every crew member still down at the end** (revived for you, uncapped),
   so a bad enough job pays a negative NET PAYOUT. If you die, you pay.

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
| E | Use, first match wins: at the van's side door (floor 1), open the clock-out slip; at the freight elevator, open the elevator menu; next to an employee (within about 2), bring a waiting one along or tell your follower to wait; next to a note (a sign, memo, sticky note, voicemail...), read it, and E again closes it; otherwise nothing. E never casts |
| F | Swap a component on the floor into your held slot |
| Enter | Type an incantation instead of speaking |
| F1 | Voice debug panel: what the mic hears and what the game did |
| F5 | Abandon the contract and return to the job board |
| Esc | Pause (Resume, Abandon contract, Main menu) |

### Spells
Nine spells: **heal**, **fireball**, **armor**, **corn** (a corn bomb from the sky that hits
everyone), **tentacles** (neon tentacles burst from the floor and shove everything outward),
**teeth** (too many teeth sprout out of everyone in the area, then pop; a heal pulls them),
**vines** (thorny vines root everyone in the area for about two seconds: no walking, no being shoved, attacks still
work), **damp** (a wide soggy area: fires go out, nobody can ignite for a while, and puddles make shoves slide
further) and **coffee** (+60% move and attack speed for six seconds, twitchy, then a crash; monsters get it too).

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
.\test_runner.ps1 -TestName test_net_clock -Link coast   # a multi-process net test under one link preset
.\build.ps1                               # all tests, then export build\windows\Cast.exe
```

- **Engine:** Godot 4.7. `godot_env.ps1` uses `$env:CAST_GODOT`, or the copy installed in `..\Hero-Reader`.
- **Not committed:** the speech DLLs (`addons/hero_listen/bin`), the zipformer model (`models/`) and
  the pronunciation dictionary (`data/pron_dict.txt`). Copy them from `..\Hero-Reader` (see
  `.gitignore`). The GodotSteam binaries (`addons/godotsteam/win64/*`) come from
  `..\bridge-to-friendship\addons\godotsteam\win64`. Steam (running) supplies the player's name on the HUD;
  `steam_appid.txt` is 480 (Valve's Spacewar test app) until Cast has its own app id. The Godot 4.7 export templates go in `build\deps`.
- **Dev flags** (after `--`) skip the menu, for example `--seed 7 --contract 0 --spells heal,corn
  --no-mic`, `--floor 3`, or `--shot <png> --shot-after 4` for screenshots. They're listed at the
  top of `scripts/app/game.gd`. `--menu` brings the menu back.
- **Labs** (`--scene res://scenes/<name>.tscn`): `terrain_preview`, `voice_lab`, `wick_lab`,
  `gasket_lab`, `rebar_lab`, `monster_lab`, `hellgate_lab`, `employee_lab`, `prop_lab`, `package_lab`, `van_lab` (the crew's work van arriving over its summoning circle), `teeth_lab`, `new_spells_lab` (vines, damp and coffee: `--spell vines|damp|coffee`),
  `backdrop_lab` (the garage behind the main menu and the job board, plus the storefront prototype: `--option garage|storefront`, `--mood dawn|night|after`, `--hero wick|gasket|rebar`, `--board` lays the real job board over the garage).
- **Tests:** the runner fails a test on any `SCRIPT ERROR`. Logs go to `test_logs/`. Net tests (`tests/test_net_*.gd`
  with `const PEERS := N`) run as N headless processes over ENet localhost, after the parallel batch, under each
  link preset; logs are `test_logs/<name>.<link>.host.log`, `.c1.log`, ... (`docs/ARCHITECTURE.md`, Tests).

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
