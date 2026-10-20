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

### Online play
Online co-op is built (milestones M0-M7, `docs/design/networking-build-plan.md`); the two-PC Steam sign-off is
`docs/design/steam-playtest-checklist.md`. **A crew shares one run**: the host rolls the job board (read-only for the
others) and takes a job, and everyone signs **their own** license. That is the "ready" step: the others see "waiting
for <name>", and the heroes stay out of the room until the whole crew has signed. Every machine builds the same floor
from the contract seed behind a load barrier (a floor that differs is refused with "Desync: different floor"), and the
van or elevator arrival plays on every screen from the same moment.

- **Movement:** every player moves their own hero with no lag on their own screen and sees the others about a tenth of
  a second behind, with their names overhead. A dropped player's seat goes back to the AI.
- **The world is the host's:** monsters, hellgates, employees, props, crates, mail and pickups. The Ledger, the
  objectives and the invoice are the host's on every screen.
- **Combat crosses machines:** a cast is an event that lands 0.2 s later on every machine, and each machine decides the
  hits on what it owns (your own hero decides the blows you take).
- **Exits:** the first player to choose at the elevator or the van decides for the crew. Esc opens the menu without
  pausing; anyone's "Abandon contract" or "Next contract" takes the whole crew back to the board.
- **Join on the job:** a player can join a crew mid-floor and takes an AI teammate's seat; leaving gives it back.

Up to 3 players (one per crew slot); a 4th is told "Crew is full", a different build is refused, a crew already on a
job is closed ("That crew is already on a job"), and when the host leaves everyone else is told "The host clocked
out". Invites from the Steam overlay join directly. A host with nobody else in the crew plays exactly the solo game.

**Two or three instances on one PC** (ENet on localhost, no Steam needed):

```powershell
.\run.ps1 -Crew 2                 # a host window (job board) and a joiner window (the same board, read-only)
.\run.ps1 -Crew 3 -Link coast     # three players, each window simulating a coast-to-coast link
.\run.ps1 -Crew 2 -Link coast -Bot 2 --seed 7 --net-wait 2 --contract 1 --spells heal,corn   # the lag test: you play window 1, window 2 walks by itself
.\run.ps1 -Crew 2 -Link rough -Bot 2 --seed 7 --net-wait 2 --contract 1 --spells heal,corn   # the same on a bad evening (80 ms each way, ±30 ms, 4% loss)
.\run.ps1 -Crew 2 --seed 7 --net-wait 2 --contract 1 --spells heal,corn   # the host takes offer 2 once both are in; both sign heal+corn
.\run.ps1 -Crew 2 --seed 7 --net-wait 2 --contract 1 --spells heal,corn -ShotDir C:\shots   # ... and each window saves <Name>.png and quits
.\run.ps1 -Crew 2 -Bot 2 --seed 7 --net-wait 2 --contract 1 --spells heal,corn   # window 2's hero walks a loop by itself (--net-bot); walk window 1 with WASD and watch it move there
.\run.ps1 -Crew 3 -Bot 1 --seed 7 --net-wait 3 --contract 1 --spells heal,corn --spawn-near grunt,5   # five skeletons chase the host's walking hero on every screen
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
(the host's file also holds every client's rows; `net_casts_*` has every cast and how late it landed on each machine,
`net_hits_*` the hits per player per minute). Read a gap as "missing", never as zero.

**Play logs** (passive, every real play, never tests), in `%APPDATA%\Godot\app_userdata\Cast\`: `play_log.csv`
(each contract, each floor's time and how it ended, the money), `combat_log.csv` (first hits, kills, fights, noise,
the goblin's alarms, archer practice, brute fights) and `voice_log.csv` (every utterance).

### A contract
1. **Job board:** dispatch offers three jobs from different clients (prepper billionaire,
   supervillain, wellness guru, tech founder, influencer). Each shows objectives, pay, danger and a
   property warning.
2. **Pick two spells** on the license requisition (a scrolling catalog of every spell, with a spec sheet beside it),
   sign it, then go down.
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

**Fog and doors:** you see the room you stand in and what you can see into through an open doorway; the rooms next to
those show their layout, everything else is black, and rooms you have seen stay dimmed. Narrow doorways have office doors,
shut at the start: walk into one to open it (it makes a noise), E to shut it. Shut, it stops bodies, shots, sight and
sound; monsters open them too, and brutes smash them (billed).

### The crew
| Hero | Primary (LMB) | Secondary (RMB) | Quirk |
|---|---|---|---|
| **Wick** (you, 85 HP) | bow bash | arrows: tap, or hold to draw a piercing shot | climbs fast |
| **Gasket** (ally, 120 HP) | pipe-wrench hammer | 360° spin with heavy knockback | stout, hard to shove |
| **Rebar** (ally, 160 HP) | slam fist (light damage, big knockback: a tank, not the killer) | bowls a boulder that shoves everyone in its path | can't climb +2, can't be shoved |

The AI teammates follow you and fight beside you. Heroes' swings, bolts and arrows chip the client's props and can break
them (a dented prop is free; a break bills its full price to whoever landed it).

### Monsters
- **Skeletons** walk up and swing; **imps** come in fast clumps; **archers** keep their distance and shoot; **brutes**
  wind up a ground slam you can see coming. Hellgates spawn more until you close them.
- **The Pavise Crossbowman** (from floor 2, about one a floor) hides behind a door-sized shield with a crimson front:
  nothing gets through the front, carried or planted. Arrows stick in it and a blocked hit shows a grey "0". It
  plants, draws a dashed red line on the floor to whoever it aims at, locks it solid, and fires a heavy bolt (18 and a
  push, range 20) that outranges the crew. Go round it: hit it from the flank or the back, drop corn on it, root it
  with vines (then it can't turn), or shove it off its shield. Standing in the line takes the bolt for a teammate.
- **The Water Boy** (from floor 2, only with a pack of three or more) wheels the office water cooler around on a hand
  truck behind his pack. When one of them is hurt he raises his whistle and pours: green rings heal every monster
  nearby by 15. A shove or a daze stops the pour. He has 30 HP. Kill him first.
- **Awareness:** monsters see further in front than behind, hear spells and fights, and a hit wakes the ones nearby.
  The longer a floor takes (from 2 minutes, fully by 6), the more restless they get: skeletons patrol, imps roam,
  idle archers take practice shots at the client's cheaper props, and brutes start shoving matches.
- **Pool sharks** (from floor 2, `docs/design/sharks.md`) swim the indoor pools, moats and lagoons. They are the
  client's property, not monsters: a shark bites whatever stands at its rim and throws it back onto the deck. A
  **laser shark** draws a red line at you, locks it and fires one beam; walk out of the line. An **imp gunner** riding
  one swings the laser round; shoot it or shove it off. You can kill a shark, but the client bills the kill ($8,400, or
  $12,600 for a laser shark). Corn in the water distracts it.
- **The goblin scout** patrols the halls. If he sees you he lights a rack of fireworks that brings every monster nearby
  (and wakes a hellgate that's ready to spawn). Kill him before the fuse, or soak the rack with damp.

### Controls
| Input | Action |
|---|---|
| WASD | Move. Step up 1 level, climb 2 (slowly); 3 is a wall. Stairs bridge big gaps |
| Mouse | Aim. Spells and shots land at the ring; it turns green when it locks onto a teammate |
| LMB / RMB | Primary / secondary attack |
| **Say "cast heal"** etc. | Cast any spell in your four slots. Fumbles weaken it or fizzle it |
| 1 – 4 | Hold that slot's spell: it recharges 15% faster, and its component shows in your hand |
| E | Use, first match wins: at the van's side door (floor 1), open the clock-out slip; at the freight elevator, open the elevator menu; next to an employee (within about 2), bring a waiting one along or tell your follower to wait; next to a note (a sign, memo, sticky note, voicemail...), read it, and E again closes it; at an office door, shut it (or open it); next to a component on the floor while your slots are full, swap it into your held slot; otherwise nothing. E never casts |
| Enter | Type an incantation instead of speaking |
| F1 | Voice debug panel: what the mic hears and what the game did |
| F5 | Abandon the contract and return to the job board |
| Esc | Pause (Resume, Abandon contract, Main menu) |

### Spells
Ten spells: **heal**, **fireball**, **armor**, **corn** (a corn bomb from the sky that hits
everyone), **tentacles** (neon tentacles burst from the floor and shove everything outward),
**teeth** (too many teeth sprout out of everyone in the area, then pop; a heal pulls them),
**vines** (thorny vines root everyone in the area for about two seconds: no walking, no being shoved, attacks still
work), **damp** (a wide soggy area: fires go out, nobody can ignite for a while, and puddles make shoves slide
further), **coffee** (+60% move and attack speed for six seconds, twitchy, then a crash; monsters get it too) and
**chicken** (four chickens run about pecking everything for zero; a pecked monster forgets you and chases its chicken).

- **Aiming:** everything lands where you aim, so to heal a friend you point at them.
- **Fire:** a fireball can set anyone near the blast on fire (monsters, teammates, employees) for 5 to 10 seconds of mild damage. It never spreads, and healing doesn't put it out.
- **Charges:** each cast spends a charge of that spell's material component. Monsters
  occasionally drop components. Walk over one to collect it, or press E to swap it into a full
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
  `.gitignore`). `bin` needs both `libhero_listen.windows.template_debug.x86_64.dll` (editor and tests) and
  `libhero_listen.windows.template_release.x86_64.dll` (release exports; the debug one in a release exe corrupts the
  heap on exit). Hero-Reader's `tools/setup.py` builds only the debug one; build the release one in
  `..\Hero-Reader\native\hero_listen` with `SHERPA_ONNX_DIR=../../third_party/sherpa-onnx/windows-x64
  GODOT_CPP_DIR=../../third_party/godot-cpp ../../stt-eval/.venv/Scripts/python.exe -m SCons platform=windows
  target=template_release` (scons finds MSVC itself) and copy it from `..\Hero-Reader\godot\addons\hero_listen\bin`. The GodotSteam binaries (`addons/godotsteam/win64/*`) come from
  `..\bridge-to-friendship\addons\godotsteam\win64`. Steam (running) supplies the player's name on the HUD;
  `steam_appid.txt` is 480 (Valve's Spacewar test app) until Cast has its own app id. The Godot 4.7 export templates go in `build\deps`.
- **Sounds, not committed either:** the CC0 recordings in `assets/audio/third_party/` (where each came from:
  `SOURCES.md` there) and the game's cues rendered from them, `assets/audio/sfx/*.wav`. Copy `assets/audio/third_party/`
  from a checkout that has it, then run `.\tools\render_sfx.ps1` (renders the cues and imports them). Without them the
  game and the tests still run; the missing sounds stay silent. Credits: `assets/audio/sfx/CREDITS.md`.
- **The dispatch headset voice, not committed:** every dispatch line is spoken by Kokoro-82M (voice `af_bella`) through a walkie-talkie radio chain and rendered to `assets/audio/dispatch/<key>.ogg` (the key is a hash of the banner text; `DispatchVoice`). Download `https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2` (the model) and `https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-win-x64-shared-MD-Release.tar.bz2` (the runtime), each into a folder of its own, and unpack them. Set `$env:CAST_KOKORO_EXE` to the runtime's `bin\sherpa-onnx-offline-tts.exe` and `$env:CAST_KOKORO_MODEL` to the unpacked `kokoro-multi-lang-v1_0` folder, have `python` and `ffmpeg` (with libvorbis) on PATH and `assets/audio/third_party/` in place, then run `.\tools\render_dispatch.ps1` (`-Force` re-renders; a couple of minutes for the ~230 clips). A line without a clip stays silent.
- **Dev flags** (after `--`) skip the menu, for example `--seed 7 --contract 0 --spells heal,corn
  --no-mic`, `--floor 3`, or `--shot <png> --shot-after 4` for screenshots. They're listed at the
  top of `scripts/app/game.gd`. `--menu` brings the menu back.
- **Labs** (`--scene res://scenes/<name>.tscn`): `terrain_preview`, `voice_lab`, `wick_lab`,
  `gasket_lab`, `rebar_lab`, `monster_lab`, `hellgate_lab`, `employee_lab`, `prop_lab`, `package_lab`, `van_lab` (the crew's work van arriving over its summoning circle), `teeth_lab`, `new_spells_lab` (vines, damp, coffee and chicken: `--spell vines|damp|coffee|chicken`, and for chicken `--closeup` or `--pickup`),
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
