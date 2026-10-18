# Steam playtest checklist: two PCs, two Steam accounts (M7 sign-off)

This is the manual half of networking milestone M7 (`networking-build-plan.md` §3 "Real Steam", turned into a script).
Everything that runs on one machine is covered by `.\test_runner.ps1 -TestAll` (ENet on localhost, and a fake Steam
object for the Steam calls). What only real Steam can prove: lobbies being found, the Steam overlay's invites, the
`SteamMultiplayerPeer` transport, avatars, Steam's fake-lag settings and real relay round trips.

Time: about 75 minutes, most of it the 20-minute lag soak (step 7). Run it once; send back what step 10 lists.

---

## 0. What you need

| | PC **A** (host) | PC **B** (joiner) |
|---|---|---|
| Steam | running, logged in as account 1 | running, logged in as account 2 |
| Friends | B's account is a Steam friend of A's (invites only go to friends) | |
| Mic | yes (voice is checked in step 8) | yes |
| Network | any; the two PCs do NOT need to be on the same network (Steam relays) | |

A third account/PC (**C**) makes step 3 and the "Crew is full" check in step 2 complete. Without it, skip the lines
marked *(C)*: two players still cover everything else.

## 1. Build and copy

On the dev PC, from the repo root in PowerShell:

```powershell
.\build.ps1
```

It runs the whole test gate (about 6 minutes), then exports. The result is **`build\Cast_Windows_v<stamp>.zip`** (the
stamp is the build time, `yyyy-MM-dd.HHmmss`; it is also printed at the start of the build and shown at the bottom of
the main menu and the pause form as `BUILD`).

- Copy that **same zip** to every PC and unzip it into a fresh folder (e.g. `C:\CastPlaytest\`). Every player must run
  the same build: lobbies are matched on the build stamp, so a different build never finds the crew (that is checked
  in step 2).
- The folder must hold `Cast.exe`, `Cast.pck`, `steam_api64.dll` and **`steam_appid.txt` containing `480`** (the build
  copies it). 480 is Valve's "Spacewar" test app, which Cast uses until it has its own app id. Steam will show you as
  "playing Spacewar": that is expected.
- First launch: Windows may ask about the firewall; allow it (Steam's relay does not need open ports, but allow anyway).

Where things land on each PC (`%APPDATA%` = `C:\Users\<you>\AppData\Roaming`):

| What | Where |
|---|---|
| Net telemetry, one row a second (`net_host_*.csv` / `net_client_*.csv`) | `%APPDATA%\Godot\app_userdata\Cast\net\` |
| Every cast, sent and applied (`net_casts_*.csv`) | same folder |
| Hits taken per player per minute (`net_hits_*.csv`) | same folder |
| Voice log, one row per utterance (`voice_log.csv`) | `%APPDATA%\Godot\app_userdata\Cast\` |
| The game's console log (`godot.log`, plus older ones) | `%APPDATA%\Godot\app_userdata\Cast\logs\` |

The host's three `net_*` files hold the whole crew: every client sends its rows to the host as it plays. Nothing here
needs a key press or a review screen during play: it is all written passively.

## 2. Lobby: find, refuse, leave (checklist items 1 and 5)

1. **A**: launch `Cast.exe`, **Start a job**. The job board opens; under the cards the crew strip shows A's **Steam
   avatar** and name ("1  <A's name> · Wick (you)") and "seats open: friends can Join a crew".
   *Look for:* the avatar picture (not a letter in a coloured square; a letter is the fallback when Steam has no picture).
2. **B**: launch, **Join a crew**. The status line says "Looking for a crew that's hiring...", then B lands on A's job
   board (read-only, "THE HOST PICKS THE JOB").
   *Look for:* both boards show the same three offers and the same crew strip, with **both avatars**; A's highlight moves
   on B's board when A presses Left/Right.
3. *(C)* **C** joins the same way: three badges on every board. Then a **fourth** launch (any PC, a second copy is fine
   only with a fourth account) presses Join a crew: it reads "No crews hiring right now" (a full crew stops listing
   itself) or "Crew is full".
4. **B**: Esc on the board ("leave the crew"): B is back on the menu with "You left the crew"; A's strip drops B.
   B joins again.
5. **A**: Esc on the board, answer **End the job**: B reads "The host clocked out" on its menu. A starts a new job, B
   joins again (step 2) before going on.
6. **Different build** (optional, 5 minutes): run `.\build.ps1 -SkipTests` again on the dev PC (a new stamp), give that
   zip to B only. B's Join a crew finds nothing ("No crews hiring right now"). Back to the same zip afterwards.

## 3. Invites from the Steam overlay (checklist item 2)

1. **A** (hosting, on the board): click **Invite crew (I)** under the cards (or press I). The Steam overlay's invite
   dialog opens; invite B. *(While on a floor, the same is the pause form's last row, "Invite crew".)*
2. **B**, game running and **on the main menu**: accept the invite in the overlay. B joins at once (no question: nothing
   to lose on the menu).
3. **B**, game running and **on a floor of its own solo job** (B: Start a job alone, take a job; A invites again): when B
   accepts, B's game shows the carbon copy **"Leave this job and join?"** (FORM 27-C, "Rosa's crew" style line naming A).
   - **Stay** (the default, Esc): nothing happens, B keeps playing.
   - A invites again; **Leave and join**: B drops its job and lands in A's crew.
4. **B, game closed**: on app 480, accepting an invite while the game is closed makes Steam launch Spacewar, not Cast
   (known: `+connect_lobby` only works once Cast has its own app id). Check the code path by hand instead: on A, find the
   lobby id in A's `godot.log` (`[Steam] created lobby <id>`), close B's game, then on B run
   `Cast.exe +connect_lobby <id>` from a terminal in B's folder. *Look for:* B opens on the menu, says "Joining the
   crew...", and lands on A's board.

## 4. Three players, a whole contract (checklist item 3)

With A + B (+ C), A takes a job, everyone signs their license, the floor starts.

1. Walk around together; fight; cast at each other (a heal on a teammate, a corn on a monster near a teammate); shove
   (Gasket's spin, Rebar's bowl) if anyone plays them.
2. Take the elevator down (first to choose decides), play floor 2, go down to floor 3, cash out.
3. *Look for:* everyone sees the same invoice; teammates move smoothly (about a tenth of a second behind, no
   teleporting); a monster's swing that you dodged on your screen does not hit you; a hit lands once (one number, one
   HP drop) on every screen.

## 5. Join mid-floor and leave again (checklist item 4)

1. A (and C) start a contract with B **not** in the crew (B on the menu). Go down to floor 2, play 15 seconds.
2. **B**: Join a crew (or A invites B). B sees **"Clocking in..."** (FORM 12-C) for a moment, then arrives in one of the
   AI's seats: every screen says "<B> takes over <Rebar|Gasket>'s seat."
   *Look for:* B arrives at full HP, where the AI stood, with the same monsters, broken props and Ledger lines as A.
3. While B is in: *(C)* or a fourth account presses Join a crew: it must find nothing / "Crew is full" when no AI seat
   is left.
4. **B** quits the game (close the window). *Look for:* on A, within about a second, B's hero turns back into the AI
   character ("<B> left the crew. Gasket takes the seat.").
5. Note how long step 2 took from pressing Join to playing (rough is fine).

## 6. The host quits (checklist item 5)

On a floor with B (and C) in: **A** closes the game window (not Esc: the window's X). *Look for:* B (and C) land on the
main menu with **"The host clocked out"** within about 6 seconds.

## 7. The lag soak, 20 minutes (checklist item 6)

1. **A** (host only): main menu, **Settings**, section **4. Diagnostics**, "Simulate a long link": **Coast to coast**
   (it reads CREW-WIDE). Back, Start a job; B joins.
   *Look for:* the crew strip on the board says "simulated link: coast (Settings > Diagnostics)" on **both** PCs (B got
   it from the host; B's own setting does not matter).
2. Play normally for **20 minutes** (two contracts, or one long one). Fight a lot: swarmers especially (step 9).
3. Afterwards, on **A**, open the newest `net_host_*.csv` in Excel or a text editor and look at the client's rows
   (`role` = client): `rtt_ms` should sit around 100-180 ms (the simulated 90 ms plus Steam's real route) and stay
   **flat** from the first minute to the last; `jitter_ms` flat; `quality` near 0.98; `bytes_in` / `bytes_out` flat.
   A column that climbs over the 20 minutes is the thing to report. (`pending_rel` is blank: Steam's peer does not
   expose it.)
4. **A**: Settings > Diagnostics back to **Off**.

## 8. Voice per player (checklist item 7)

1. On a floor together, each player casts by **voice** a few times (their own mic, their own trigger word). Press F1 to
   see the voice debug panel.
2. *Look for:* each player's panel says "THIS MACHINE'S MIC · <their name>, seat N" and lists only **their own** casts;
   a teammate's cast appears in the world (and lands once) but never in your panel's HEARD / transcript.
3. *Look for:* nobody's cast fires twice on another machine (one heal = one heal on every screen).
4. Afterwards, on **A**: the newest `net_casts_host_*.csv` lists every cast once as `sent` (from the caster's peer, with
   `speech_ms` and `recog_ms` for spoken casts) and once as `applied` per machine (`late_ms` small). Each player's own
   `voice_log.csv` has rows with `net` = host/client and their `seat`.

## 9. Swarmers (the open design question)

During the soak, stand in a pack of swarmers (the small purple spiky imps) on purpose for a minute, on A and on B.
*Report:* can you see their bite coming before it lands, on A (host) and on B (client)? Does one feel worse than the
other? The measured numbers and the three options are in `networking-build-plan.md`, "M7 as built", "Swarmer wind-up".
The `net_hits_host_*.csv` file then shows hits per minute per player, with `sources` saying how many were swarmers.

## 10. What to send back

From **A** (the host), zipped together:
- `%APPDATA%\Godot\app_userdata\Cast\net\` — the newest `net_host_*.csv`, `net_casts_host_*.csv`, `net_hits_host_*.csv`
  (they hold the whole crew);
- `%APPDATA%\Godot\app_userdata\Cast\logs\godot.log` (and the `godot*.log` files from the session's time);
- `%APPDATA%\Godot\app_userdata\Cast\voice_log.csv`.

From **B** (and C): their `logs\godot.log` and `voice_log.csv` (their own net files too, if easy).

And a few lines per step: pass / fail / odd, with the time it happened (the CSVs and logs are timestamped), plus
your answer to step 9. The host's log ends with one line, "hits taken per minute this session: ...", which is the
"keep them level" summary: paste it too.
