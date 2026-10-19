# Combat proposals: voice orders, the pavise, the medic and hazards

Status: **design only**, 2026-10-19. Nothing here is built. It follows `combat-variety-research.md` (sections 4 and 6:
A1, A3, B6, D11 and the environment notes in 5.3). **[proposal]** marks every number and rule still waiting on the user;
**decided** marks the user's calls, with the date. Open questions are numbered once across the whole doc.

**Decided (user, 2026-10-19), and not designed here:**
- **Rebar's fist is 15 damage with a 1.6 shove** (was 26 / 1.0): a tank, not the killer (`characters.md`).
- **The brute daze is being built** (a worktree): a direct slam hit dazes for about 0.6 s, ignores immovability, and
  voice casts still go off. This doc calls it "the daze status".
- **Explosive props are being built** (a worktree). This doc assumes their shape: a host-arbitrated priced prop that a
  hit, a spell or fire sets off, and that bills the culprit.
- **Hazard rules:** a hazard hurts both sides, warns clearly, can be set off on purpose by the crew (spell, shove or hit),
  and is the client's property, so setting it off bills the invoice.

---

## 1. Voice orders to AI teammates

**The user's direction (2026-10-19): "keep it simple".**

### 1.0 Decided (user, 2026-10-19). This replaces the three-order proposal in 1.1 where they differ.
- **Every named character has one order, or none (its default behaviour).** That includes employees, not only AI heroes.
- **Two orders:**
  - **"<name> go"** sets a waypoint where the speaker aims. The character walks there, then **holds** there until a new
    order: an AI hero fights what comes, an employee stays put. Aimed at a monster, an AI hero attacks it. A new "go"
    replaces the old one.
  - **"<name> follow"** clears the order: the character follows **the speaker** (allies today always follow seat 1's
    hero). There is no way to tell one character to follow another.
- **On a human-played hero** an order is only a world marker on that player's screen ("Fox: go here"); it controls
  nothing and clears when they reach it. "Follow" sends them nothing.
- **Names (official first, then aliases):**

  | Who | Official | Also heard as |
  |---|---|---|
  | Everyone (crew + employees) | **Everyone** | everybody, all hands |
  | Crew (the heroes only) | **Crew** | team, squad |
  | Mrs. Pym | **Pym** | Mrs. Pym, Missus Pym |
  | Every henchman on the floor | **Hench** | henchmen, henchman |
  | Hench #4 | **Hench Four** | Number Four |
  | Rebar / Wick / Gasket | **Rebar / Wick / Gasket** | (Gasket stays the main name despite the "cast"/"GAS" risk; watch it in the logs) |

- **Players are addressed by their hero's name only** (no player names or callsigns).
- **"Everyone" can take "go"** as well as "follow" (employees included).
- The other employee names (Reginald, Beatrice, Alphonse, Hodges, Dorothea, Gary, Steve, Todd, Kevin, Dennis) are one word
  already and are their own official names. "Hench" addresses every henchman; "Hench Four" only #4.

**Why.** The research found the AI ally leads: it picks the nearest monster near the leader with no wait and no line of
sight, so Rebar opens every fight (`combat-variety-research.md` 1.3). Two fixes combine: a **restraint baseline** (the
AI never starts a fight) and **orders** (the player starts it for them). Orders put the AI under the crew's call-outs:
voice chat is the input.

### 1.1 The orders [proposal]
| Say | Order | What the ally does |
|---|---|---|
| "**Rebar, follow**" | FOLLOW (the default) | Stick to the speaker (formation as today) and fight only what fights the speaker or the ally itself |
| "**Rebar, hold**" | HOLD | Stay where it stands now; fight anything that is in the fight within 6 of that spot |
| "**Rebar, go**" | GO | Attack the monster the speaker is aiming at (nearest to the reticle, within 2.5 of it), then go back to FOLLOW |
| "**Crew** ..." / "**everyone** ..." | the same, to every AI seat | Both AI allies take the order |

- **Only AI seats obey.** A human-played hero has no `AllyBrain`, so an order addressed to one does nothing (the human
  heard it over voice chat anyway).
- **Who is addressable:** the AI seats' hero names, Rebar (seat 2) and Gasket (seat 3) by default (`game.gd` `AI_SEATS`).
  If a human also plays a Rebar, "Rebar" means the AI one.
- **Last order wins**, whoever said it. FOLLOW makes the **speaker** the ally's leader (today every ally follows seat 1).
- Orders cost nothing: no cooldown, no power, no fumble scoring. A repeated order within 1.5 s is one order (the
  Zipformer double-fire dedupe).
- Allies still never cast (`voice-mechanic.md` §4's "Fox, heal me" stays out of scope).

### 1.2 Recognition [proposal]
- **The name is the trigger.** No "cast": an order is `<name | crew | everyone> <order word>`, with the order word the
  **very next token**, at most 0.5 s after the name (token timestamps). A trailing "me", "there" or "up" is ignored.
  One utterance can hold an order and a cast ("Rebar, go. Cast corn.").
- **Vocabulary:** the names (rebar, gasket, wick), crew, everyone, follow, hold, go. They go to the recognizer as
  hotwords like the spells, so they need the same measured clips (`tools/make_voice_clips.ps1`,
  `tests/test_voice_audio.gd`). Already measured (`characters.md`): GASKET is heard as GASKET, never "cast"; Rebar as
  REBAR or RIBAR; Wick as WICK, WIG or WHITCOMBE (the flakiest, but no AI seat is Wick today).
- **Strictness** follows the lobby's mode:

  | Mode | An order counts when |
  |---|---|
  | Strict | the name opens the utterance, or follows a pause of 0.3 s or more |
  | Loose (default) | the name and the order word sit together anywhere in the utterance |
  | Chaos | as loose. A bare "go" or "hold" never orders anyone, in any mode |

- **False-trigger risk.** Crew chatter names teammates all the time. The adjacency rule does most of the work:
  - "Rebar just goes in" (the user's own complaint) is safe: "just" sits between the name and "goes".
  - "Rebar goes in first" is the risk. "goes" is "go" plus one sound, so the extra-only matcher accepts it: in loose it
    sends Rebar at your reticle. That is the funny kind of accident (it did what you said), but measure it.
  - "hold" in "Gasket's holding" is safe ("holding" is two extra sounds, and "Gasket's" is not the bare name).
  - **"go" is the weak word:** one syllable (unreliable in isolation, `voice-mechanic.md`), common in chatter ("let's
    go"), and the proposed Ghost spell lists "go"/"goes" as its own risk (`spells.md`). Question 2.
  - **"crew"** may be heard as "true" or "through"; "everyone" (three syllables) is the safe form.
  - Clips to add: each order said cleanly, plus negatives "Rebar just goes in", "Rebar goes first", "hold on",
    "let's go", "follow me guys", "Gasket's holding the door", "crew's dead".
- **Passive data:** every order goes to `user://voice_log.csv` like a cast (heard text, the order, the gap, accepted or
  not), and orders per player per minute go to the telemetry sheet. No prompts.

### 1.3 Feedback [proposal]
| Who | What |
|---|---|
| The speaker (their machine only) | A short **radio click** cue, `order_heard`, the moment the order is parsed. Not `cast_heard`: that cue means "a cast is armed" (`Sfx`, `VoiceCaster.trigger_heard`) and should keep one meaning |
| Everyone | A **bark** over the ally in the employees' speech bubble (`Employee.say`, already sent by `NetWorld`): "On you." (follow), "Holding." (hold), "On it." (go), "Can't reach." (go, no path). Online the bark names the speaker: "On it, Fox." |
| Everyone | A **pose:** a nod and a point toward the GO target, or Rebar planting his fists for HOLD |
| Everyone, while the order lasts | A small **stance chip** by the ally's name tag: footprints (follow), a planted flag (hold), an arrow (go). Question 7: the user turned down "?"/"!" over monsters, so this may be one icon too many |
| Everyone, on GO | A brief ring in the ally's colour under the target (cosmetic) |

No bark at all means the ally didn't hear it, which is the honest read of a miss.

### 1.4 The restraint baseline [proposal] (research A1)
Applies under every order; GO overrides parts of it.
1. **Only fights already started.** A monster is "in the fight" when it is in CHASE or ATTACK on a hero (`Monster.state`,
   `Monster.target`), or a hero hit it in the last 3 s (the host applies every hit, so `_on_damaged` knows).
2. **A reaction delay:** the ally joins 0.6-1.0 s (rolled per engagement on the host's `GameWorld.rng`) after a monster
   came into the fight. Today it is zero.
3. **What attacks the player first:** among candidates, the monster whose target is the ally's leader, then the one
   attacking the ally itself, then the nearest.
4. **Line of sight** to the target, unless the target is attacking the ally.
5. **The bowl peels, it doesn't open:** Rebar bowls only a monster within 3 of a teammate that it is attacking. Gasket's
   spin is unchanged.

So with no orders at all, the AI follows and helps, and the player starts every fight. Question 6 asks about lowering
AI damage as well.

### 1.5 How `ally_brain.gd` changes [proposal]
- New state: `order` (FOLLOW / HOLD / GO), `_hold_point`, `_go_target`, `_go_until` (8 s at most), `_joined_at` (monster
  id -> the time it can be engaged). `leader` becomes "who gave the last FOLLOW" (seat 1's hero until then).
- `order(kind, by, target, point)`: the one entry point, called locally in solo and by the net layer on the host.
- `_pick_target()` is rewritten around 1.4: FOLLOW takes monsters fighting the leader or the ally; HOLD takes any monster
  in the fight within 6 of `_hold_point`; GO takes `_go_target` at once (no delay: the player chose it), plus anything
  hitting the ally on the way.
- Leash: FOLLOW keeps `LEASH` 8 from the leader; HOLD measures it from the hold point (6); GO allows 14 from the speaker.
- `_follow()`: under HOLD the slot is `_hold_point` and the lane-stepping and formation stop; under FOLLOW as today.
- `_try_secondary()`: the bowl rule in 1.4.5.
- Kept as is: prop care, pathing, personal space, the lane check.
- Test: a single-process `test_ally_orders` (restraint delay, each order, each edge case below) and a two-peer case
  (a client's "Rebar, go" lands on the host's ally).

### 1.6 Networking [proposal]
- **Shape:** an order is a **request to the host**, which runs the AI seats. Solo it is a local call.
- The speaker's machine parses the order and resolves the GO target from its own view (the monster id nearest its
  reticle), then sends `Net.request(ally, "order", {o, target_id, point})`. The host checks the seat is still AI
  (`Session.seats`), applies it and announces `crew.order {seat, o, by, target}` reliably, which drives the bark, pose and
  chip on every machine.
- **Declarations:** `order` is `OWNER` (everyone draws the chip), carried by `crew.order` (`NetEvents.CARRIES`); a late
  joiner gets it in the keyframe (`NetEvents.LATE_JOIN`). Everything else is `PRIVATE`. The delay roll uses the host's
  `GameWorld.rng`.
- No new Steam or transport code: it uses `Net.request` and a reliable event.

### 1.7 Edge cases [proposal]
| Case | What happens |
|---|---|
| The ordered ally is downed or dead | Nothing: no bark. It wakes in FOLLOW (seat 1's hero) |
| The speaker is downed | Orders still work (voice). FOLLOW on a downed leader means guarding the body: HOLD at it |
| The GO target dies, despawns or is out of sight for 4 s | GO ends; back to FOLLOW. A kill by someone else is fine |
| GO with nothing within 2.5 of the reticle | "Nothing there." The current order stays |
| GO target with no path, or more than 20 away | "Can't reach." The current order stays |
| The speaker is far away or on another level | FOLLOW walks back by path (as today); HOLD holds where the ally stands |
| The ally is shoved, staggered or dazed | The order is kept and acted on when it is free |
| Two players give different orders | The later one (host time) wins; the bark names who |
| A player takes the seat (`SeatHandover`) | The `AllyBrain` goes, and the order with it |
| A floor change | Every AI seat resets to FOLLOW seat 1's hero at the barrier |

**Why it's fun:** the player decides when a fight starts and who the tank goes for (the Bosco lesson); "Rebar, hold" in a
doorway is a call-out that does something; a mistaken "Rebar goes in" is a recoverable, attributable accident.

---

## 2. The shielded ranged unit: the Pavise crossbowman

**The user's direction (2026-10-19):** "I like the idea of a shielded or protected unit from one angle. But it has to pose
a threat at a distance." Everything below is **[proposal]**.

### 2.1 Look
A skeleton (the grunt's body) behind a **pavise**: a door-sized standing shield of dark planks with an iron rim, painted
with red chevrons, a sight notch at the top and a spike at the foot that it stamps into the floor. It carries a heavy
**crossbow** with a winding crank.
- **Top shape at game zoom:** a tall dark rectangle with a bone skull peeking over it. No other monster has a flat plank
  silhouette (grunt: a stick figure and sword; archer: a hood and bow).
- **Tells:** the crossbow resting in the notch while aiming; arrows that hit the front **stay stuck in the planks**, so a
  pavise bristling with arrows says "stop shooting the front". HUD name: "Pavise Crossbowman" (question 12).

### 2.2 Stats [proposal]
| | **Pavise** | Skeleton (grunt) | Archer | Brute |
|---|---|---|---|---|
| HP | **70** | 40 | 25 | 140 |
| Speed | **2.2** carrying the shield | 3.2 | 3.0 | 2.2 |
| Turn rate | **60°/s planted**, 150°/s carrying (today every monster turns instantly) | instant | instant | instant |
| Sight | front cone 120° out to 16, all round 3 | 8 | 10 | 9 |
| Attack | **bolt 18** (+ a 0.8 shove), range **20**, aim 1.2 s, reload 2.0 s; shield bash 8 + shove 2.0 at 1.8 | cleave 10 | arrow 8, range 16 | slam 25 |

- **Range 20 beats the crew:** Wick's tap reaches 14 and his drawn arrow 18, so standing off and sniping loses. One
  bolt every ~3.2 s takes Wick (85) to the floor in about 15 s if the crew ignores it.
- **HP 70** means corn (60) takes most of it but doesn't kill. From the flank: Gasket's hammer 3 hits, a drawn arrow 3,
  Rebar's fist 5.

### 2.3 Behaviour
| State | Time | What it does | Tell |
|---|---|---|---|
| ADVANCE | | Walks toward a spot 10-14 from its target, shield carried in front (the front still blocks) | shield up, slow walk |
| PLANT | 0.6 s | Stamps the pavise into the floor facing the target | a thud, dust |
| AIM | **1.2 s** | A **red aim line** on the floor from the bow to the target. It tracks for 0.8 s, then **locks** for the last 0.4 s (the line turns solid and bright) | the red line; the bow in the notch |
| LOOSE | | The bolt flies along the locked line at 30 (0.5 s over 15) and stops at the first hero, prop or shield it meets | a bolt streak |
| RELOAD | 2.0 s | Cranks the bow. Still shielded | the crank turning |
| TURN | | Planted, it drags the pavise round at 60°/s toward the nearest hero within 4, else its aim target. Past 90° it lifts and re-plants (0.6 s) | scraping |
| BASH | 0.5 s wind-up | A hero within 1.8 **in its front arc**: a shield bash, 8 damage, shove 2.0 | the grunt's orange pulse |
| EXPOSED | until back | Shoved off its planted pavise (2.4): it walks back and lifts it (1.0 s) | the pavise standing alone |

- **Who it shoots:** the hero in line of sight with no monster within 3 of them (the backline), else whoever cast last,
  else the nearest. That skips the tank in front (research 4.3).
- **Dodging:** the lock leaves 0.4 s plus the flight; a hero walking at 4.5 clears a bolt in it. That is a reflex answer,
  as the research asks for a sub-1 s threat. The 1.2 s line also gives time for a call-out ("line on you, Wick").
- **Body-blocking:** a bolt stops at the first hero in its line, so Rebar (160 HP, immovable) standing in the line takes
  it for Wick. That is a tank job that isn't killing ("Rebar, hold" in the lane, question 10).

### 2.4 How the shield is decided
- **The arc:** the shield covers the front **140°** (±70° from `facing`). It turns slowly, so a hero 70° or more off its
  facing hits the body.
- **The test** (a new `Combat.shielded(target, from_point, kind)`, asked inside every `Combat` helper and `Projectile`):
  | Kind of hit | `from_point` | Blocked when |
  |---|---|---|
  | Melee arc | the attacker | the attacker is inside the arc |
  | Projectile (arrows, bolts, the bowl, the fireball) | the point the projectile came from along its travel | its travel comes from inside the arc |
  | Area blast (`explode`, a teeth pop on a neighbour, an explosive prop) | the blast centre | the centre is in front of the shield plane (0.55 ahead of the body) |
  | From above (corn) or from inside (teeth growing out of it) | none | never |
  | Shoves | as the hit that carries them | a blocked shove is a "bonk": nothing moves |
- A blocked hit shows a **"0"** and a clank (the chicken's peck already shows a "0"); arrows stick, a bowl crumbles.
- **Shoves that get through separate it from the pavise**, which stays planted where it was: EXPOSED until it walks back.
  A shove from behind into its own shield **trips** it over the pavise: both go flat, 1.5 s EXPOSED.

### 2.5 Spells and hero attacks against it
| Spell / attack | From the front | From the flank or behind |
|---|---|---|
| **Corn** | 60 (from above: never blocked) | 60 |
| **Fireball** | Bursts on the planks: no damage to it (the blast still hurts things beside it) | 40, may ignite. A fireball aimed past it from an angle bursts behind the shield plane: hits (question 8) |
| **Tentacles** | Centre in front: bonk | Separates it (EXPOSED), or trips it over the pavise |
| **Teeth** | Grows out of it: always pops for 25 × power | the same |
| **Vines** | **Pavise rule: a rooted pavise can't turn** (the vines bind the shield's foot). Rooted monsters can normally turn (`spells.md`); like the goblin's match-arm rule, this exception reads on screen | Root it, then walk round it |
| **Chicken** | A pecked monster turns on its chicken for 4 s (`Monster.TAUNT_TIME`): the pavise **turns its shield to the chicken**, showing its back to the crew | the same |
| **Damp** | Soaks it. [proposal] A wet string: reload 3.0 s instead of 2.0 while soaked | the same |
| **Coffee** (accident) | Turns at 96°/s, aims and reloads 60% faster | the same |
| **Heal, armor** | nothing (heroes only) | |
| Wick's arrows | Stick in the planks | 12 / 28, a drawn arrow pierces on |
| Gasket's hammer / spin | clank | 28 / 16; a spin from beside it hits |
| Rebar's fist | clank, and the bash shoves nothing back (immovable) | 15, shove 1.6 separates it |
| Rebar's bowl | bonk, the boulder crumbles | 6 and a 3.5 shove: separated, or into a pit |
| Brute daze, explosive props | A blast in front: blocked | hits and separates |

### 2.6 Spawning and packs [proposal]
- **Where:** rooms of 80+ cells with a sightline of 14 or more from the main door (`SitePlan.entrances`) to the far side.
  It stands on the far side, facing the door, on level floor or a +1 tier (never +2: melee must reach it).
- **How many:** none on floor 1; 1 on floor 2; 1-2 on floor 3. One per room at most.
- **Pack:** the pavise plus fodder that rushes (3-4 imps, or 2 skeletons), so the crew is pulled forward into its lane.
  From floor 3, or difficulty 0.6 and up: **the fortress**, the pavise with the medic (section 3) 3-4 hexes behind it.
- **Cost** in the pack budget: about two grunts. Hellgates don't spawn it. It counts toward "exterminate everything".

### 2.7 Networking (new-content checklist)
1. **Shape:** a host-owned actor (`scripts/monsters/pavise.gd`, kind `"pavise"`, a `Monster` subclass). The bolt is a
   **scheduled effect**; the shield test is part of hit resolution.
2. **Declarations:** `facing` is already `OWNER` and streamed. New `OWNER`: `shield_state` (CARRIED / PLANTED / LEFT /
   FLAT) and `shield_pos` / `shield_yaw` (a LEFT pavise stands where it was), carried in `NetWorldCodec.PAVISE_FIELDS`.
   New `SPAWN`: `turn_rate` on `Monster` (default: instant, today's behaviour). Aim timers and the target pick are
   `PRIVATE`. The model is `LOCAL`.
3. **Hits:** the attacker's machine resolves its hits on monsters (rule 2), so it asks `Combat.shielded` with the puppet's
   facing and shield state as it sees them. Its facing is ~100-150 ms old on a client; a flanker right at the arc's
   edge may get a hit the host would have blocked. Co-op accepts that: the attacker decides.
4. **The bolt:** the aim is a wind-up event (`world.windup` with the target id); the lock sends the locked direction;
   the loose is `(origin, dir, start time, speed)` on every machine. **The victim decides:** each machine tests its own
   hero against the bolt; the host tests AI allies, props and chickens.
5. **Randomness:** none beyond the host's AI timers.
6. **Late joiner:** sees the shield state in the keyframe; a bolt in flight is skipped.
7. **Two-peer test:** a client flanks and its hits land; a client in front gets "0"s; a client dodges a locked bolt on
   its own screen and takes nothing.

**Why it's fun:** it asks "who goes round?". The tank in front gets clanks; someone flanks, roots, chickens or corns
it; the red line is something to shout about; Rebar gets a non-killing job, standing in the lane.

### 2.8 Alternative: the riot imp [proposal, brief]
An imp holding a ripped-off office door marked **"SECURITY"** as a shield, throwing **staplers** (three in a burst, 5
damage each, lobbed, range 12). Fast with the door (3.5), so it is harder to flank than the pavise, and funnier, but a
weaker threat at range, and its door would hide most of a 0.9-tall imp. A bunker counterpart if the pavise reads too
"dungeon" for luxury interiors (question 11).

---

## 3. The enemy medic

**The user's direction (2026-10-19):** "Maybe the enemies need a caster that can heal them, making a better early target."
Everything below is **[proposal]**.

### 3.1 Look
An imp (the swarmer's body and bat ears) in a **lab coat** several sizes too big, goggles pushed up, carrying a **glass
jar of glowing green liquid** with a squeeze-bulb nozzle; the beam comes out of the nozzle.
- **Colour:** the green must not read as the Heal spell (spells own the cool, saturated colours): a sickly chartreuse,
  the goblin's and the science room's enemy green. No red cross (a protected emblem): a pocket badge reading "R&D".
  HUD name: "Imp Medic" (question 14).

### 3.2 Stats [proposal]
| | **Medic** | Imp (swarmer) | Goblin scout |
|---|---|---|---|
| HP | **20** | 12 | 24 |
| Speed | 3.6, **4.2 fleeing** (a hero walks 4.5: catchable) | 5.5 | 2.0 / 5.0 |
| Keeps | **6-9** from the nearest hero | | |
| Heal beam | range 7, line of sight; **15 HP/s for 2 s** (30) on one monster; 3 s between channels | | |

- **HP 20 dies to one committed hit:** a drawn arrow (28), Gasket's hammer, corn, a fireball, teeth at full power. Two
  taps, or two Rebar punches.
- **30 HP per beam** undoes Gasket's hammer on a grunt, or a fifth of a brute.

### 3.3 Behaviour
| State | Time | What it does | Tell |
|---|---|---|---|
| HANG BACK | | Stays 6-9 from the nearest hero, behind its pack; prefers the shadow of a pavise or brute | jar sloshing |
| UNCORK | 0.4 s | Picks the **most hurt** monster in range (by missing HP fraction; never an imp, another medic or itself) and raises the jar | the jar glows brighter |
| BEAM | **2 s** | A green beam from the nozzle to the patient; the patient glows and "+" numbers rise | the beam |
| FLEE | | A hero within 4: it runs (4.2) toward its pack or the pavise, using the employees' flee scorer (`Employee._replan_flee`) | coat flapping, jar held high |
| FUMBLE | 0.8 s | After a broken beam: it juggles the jar | juggling |

- **Breaking the beam:** any hit (even a chicken's 0 peck), a shove, a vines root, a stagger or a daze. The heal already
  given stays. Then FUMBLE and the 3 s wait.
- [proposal, question 16] **Body-blocking:** a hero standing within 0.4 of the beam's line cuts it. It gives Rebar
  another non-killing job.

### 3.4 Spells against it
| Spell / attack | Result |
|---|---|
| Corn, fireball, a drawn arrow, the hammer | a kill |
| Teeth | it pops in 1-2 s: kills at most powers; the beam breaks at once (teeth count as a hit) |
| Vines | rooted: no beam, can't flee. **The** setup spell |
| Chicken | a peck breaks the beam every second, and it chases its chicken instead of healing |
| Tentacles, the bowl | breaks the beam and shoves it; into a pit, a ring-out |
| Damp | nothing special (soaked) |
| Coffee (accident) | heals 60% faster, flees at 6.7 |

### 3.5 Spawning [proposal]
- Never alone: only in a pack with a skeleton, archer, pavise or brute (it doesn't heal imps).
- None on floor 1; 1 on floor 2; 2-3 on floor 3 (question 15). Paired with the pavise (the fortress, 2.6) or a brute
  ("the brute's corner man"). Hellgates don't spawn it. It counts toward "exterminate everything".

### 3.6 Networking
1. **Shape:** a host-owned actor (`scripts/monsters/medic.gd`, kind `"medic"`). The heal goes through the `heal` verb on
   the host, which owns every monster.
2. **Declarations:** `beam_target` (id) and `beam_until` are `OWNER`, carried by a reliable `world.beam {id, t, at}`
   (start and stop, `NetEvents.WORLD_CARRIES`); everything else `PRIVATE`; the model `LOCAL`.
3. **Breaking:** a client's hit or shove on the medic is already a request the host applies, so the host breaks the beam.
   Pecks and roots resolve on the host too. A client's break lands about half an RTT late: a few HP of extra heal.
4. **Late joiner:** a beam in progress is skipped (`NetEvents.LATE_JOIN`: nothing); the next one shows.
5. **Two-peer test:** a client's tap breaks the beam on both screens, and the patient's HP agrees.

**Why it's fun:** "kill the medic" is a priority target that isn't the nearest thing. Behind a pavise it is a fortress
no single hero cracks: someone flanks the shield, someone roots or corns the medic.

### 3.7 Alternatives [proposal, brief]
- **Raise instead of heal:** a 2.5 s channel raises a dead imp within 6 (a green column from the corpse). Same breaks.
  Raised imps drop nothing. Needs bodies to linger (today they fade out over `DEATH_TIME`) and spawns through
  `world.spawn`. **I recommend heal:** raising makes more one-hit imps, which is the fight the research wants less of.
- **Skeleton "company nurse"** with a clipboard who "signs off" a monster as fit to work: funnier for the contract
  fiction, but bone white next to the grunt and the pavise, so the priority target reads worst.

---

## 4. Environmental hazards

**Decided (user, 2026-10-19):** hurts both sides; a clear warning; the crew can set it off on purpose (spell, shove or
hit); it is the client's property, so setting it off bills the invoice. Explosive props are being built elsewhere.
Everything below is **[proposal]**.

**Shared plumbing** (from the explosive-props build): a hazard source is a host-arbitrated object; a hit or shove on it is
a request (`Net.hit_object`); the host decides once and announces `world.hazard {id, kind, at}`; the effect runs as a
scheduled effect on every machine, and each machine applies it only to what it resolves (`Net.resolves`); the bill is a
`Ledger.damage` line with the culprit. Hazards are placed from the floor seed and are in the floor checksum.

### 4.1 Live wires + water (size M)
- **What:** a cable torn from a ceiling tray, sparking as it dangles over a pool, a moat, a damp puddle or a permanent
  leak puddle, hung from a junction box on the wall.
- **Sets it off:** any hit on the junction box (priced, HP 1: "Electrical panel"), a fireball blast at it, or anyone
  **shoved into the cable** (a shoved actor's slide touches it). Then the cable drops into the water.
  A **damp cast** whose puddles reach under the cable connects them: the next spark (every 2-4 s) shocks them.
- **Telegraph:** the cable spits yellow-white sparks every 2-4 s with a crackle (never cyan: that's spells); dropping
  takes 0.6 s (it swings down, the water surface flickers).
- **Effect:** a **shock through all connected water**: everyone standing in it takes **12 and the daze status (0.6 s)**;
  soaked actors take x1.5 (waders are always soaked: 18). The cable then pulses 6 damage every 1.5 s for 6 s and the
  breaker trips. One use per cable. Touching the live cable before that: 4 (the sparks rule in `environment.md`).
- **Connected water:** a pool's whole body (`PoolGeo` record), plus damp's wet cells touching it or the drop cell
  (a flood fill over cells; damp's cells are already a pure function of the cast).
- **Themes:** server room (the torn cables of `environment.md`), science (specimen pool, pipes), indoor pool (a fallen pool
  light), moat, service entrance (a wet floor sign and a puddle: a first lesson).
- **Builds on:** `Wading` / `HexMap.water_at`, `Damp`'s puddle field and `slide_mult`, `Wet` / `Burning.is_soaked`, the
  daze status, the explosive-props plumbing. It is the "damp + sparks" combo planned in `spells.md`.
- **Networking:** the box is a host-arbitrated object; the shock is a scheduled effect `(water body, start time)`; each
  owner tests its own actors in the water at the shock time (the victim decides).

### 4.2 Oil and grease slicks (size M)
- **What:** 3-7 cells of glossy black oil from a tipped drum, a leaking lamp or, in the home cinema, a burst
  **popcorn-butter** dispenser.
- **Sets it off:** any fire: a fireball blast on it, a burning actor stepping on it, an explosive prop, a knocked brazier.
- **Telegraph:** the sheen and the spilled source; once lit, a **flame front creeps 4 cells/s** from where it caught.
- **Effect:** unlit, shoves slide x1.5 on it (damp's slide rule). Lit, it burns 8 s: anyone on a burning cell ignites
  (`Burning.ignite`, no roll), soaked actors excepted. Damp puts out the cells it covers and keeps them unlit for 15 s;
  the popcorn-butter slick pops leftover corn kernels (the research's popcorn chain).
- **Themes:** home cinema, barracks (a mess-hall fryer), torture chamber (brazier oil), service entrance, lab.
- **Builds on:** `Burning`, `Damp`'s cell field, `Grime` scorch marks, the fireball's on-hit.
- **Networking:** the cells are spawn data; ignition is a host decision announced `world.hazard {id, cell, at}`; the
  spread is a pure function from there (minus cells soaked by damp casts every machine saw); each owner ignites its own.
- **Bill:** "Floor refinishing" per slick lit, to whoever lit it (question 20).

### 4.3 Ledges and pits: breakable railings and "shove here" spots (size S-M)
- **What:** glass balustrades (bunker) or chain rails (lair) along ledge edges and pit rims, with **gaps**: a missing
  panel with hazard tape across it, or a loose section. Pits and ledges already work: void kills a shoved monster
  (ring-out), drops hurt (`Actor.shove`, `characters.md`).
- **Sets it off:** a shove. A slide that meets a railing stops like a wall slam (8 and a stagger); a single slide of
  **2.0 or more** breaks the panel and goes over (Rebar's bowl 3.5, tentacles, the brute's slam). The gaps let anything
  through. Rebar's fist (1.6) doesn't break a panel but **sends a monster through a gap** (question 21).
- **Telegraph:** the hex floor's glow breaks at the edge; the gaps carry hazard stripes.
- **Effect:** a ring-out, a fall, or a wall slam on the railing. Heroes are fished out as now. The pavise flanked and
  shoved through a gap is the showpiece.
- **Themes:** gym (a mezzanine), home cinema (tiered seats), throne room (a pit before the throne; a later trapdoor lever),
  torture chamber, wine cellar (a cellar hatch).
- **Builds on:** `Actor.shove`, `_enter_void`, fall damage, the generator's ledges and pits, priced props.
- **Networking:** the slide's owner decides the break with a stateless rule (one slide of 2.0+ breaks a panel), so it
  needs no round trip; it reports the break and the host bills it and announces it (the first report wins).
- **Bill:** "Glass balustrade" per panel broken.

### 4.4 Steam pipes (size M)
- **What:** a pressure valve on a pipe run (`pipe_run` decor exists in science) with a gauge.
- **Sets it off:** a timer (every 8-12 s from the seed) or a hit of 10+ on the valve, which bursts it at once; a hit
  burst vents 6 s and then the pipe is spent.
- **Telegraph:** a rising hiss, the gauge needle in the red, wisps from the joint for 1.2 s.
- **Effect:** a **steam wall** 1 hex wide, 4 hexes long out from the pipe, for 3 s: 12 damage per second to anyone in
  it, it puts fires out, and it **blocks line of sight** (archers and the pavise can't target through it).
- **Themes:** science, spa (a sauna door), gym (sauna), barracks (a boiler), service entrance.
- **Builds on:** `pipe_run`, the steam effect in `pool_props.gd`, `Burning.extinguish`. **New:** a dynamic blocker that
  `HexMap.line_of_sight` reads (shared with doors).
- **Networking:** a timed burst is a pure function of `(seed, host_time())`: no message. A hit burst is a host event. Each
  owner applies the damage to its own actors; every machine computes the same wall, so line of sight agrees.
- **Bill:** "Plumbing" when a hit bursts it (timed bursts are free).

### 4.5 Doors (size L)
- **What:** there are no doors in doorways today (corridors open straight into rooms); `networking.md` already lists
  doors as a host-arbitrated object. Proposal: **fire doors** held open by a magnet at 1-2 corridor mouths per floor
  (bunker), and blast doors or a portcullis (lair).
- **Sets it off:** E on the door, or any hit on its door holder: it shuts in 1.0 s.
- **Telegraph:** a buzzer and a flashing amber light while it closes.
- **Effect:** shut, it blocks walking, line of sight and projectiles for everyone. Shut it to split a pack. Monsters path
  round by another corridor or wait. A **brute** chasing a hero behind it smashes through: its slam wind-up (the red
  ring) on the door, 3 slams, the door breaks. E opens it again (0.6 s).
- **Themes:** every bunker room (fire doors), panic room (the vault door), lair rooms (blast doors).
- **Builds on:** the elevator's doors (a host-arbitrated door already), `find_path`, the brute's slam. **New:** a dynamic
  blocked-cell set that `find_path`, `movement_check` and `line_of_sight` read.
- **Networking:** a host-arbitrated object (E is a request, like the elevator); `world.door {id, shut, at}`; every machine
  blocks the same cells from the event; a late joiner gets the state in the keyframe.
- **Bill:** "Fire door" when a brute breaks a door the crew shut (question 19).

### 4.6 Corruption pools near hellgates (size S-M)
- **What:** 2-4 patches (3-6 cells each) of glowing violet demon ichor round each hellgate (`environment.md`'s ichor).
- **Sets it off:** it is always on. The crew's verb is **cleaning** it: corn (the burst) or damp (a wash) clears the cells
  under the blast for good. Shoving a monster out of it ends its buff.
- **Telegraph:** the glow; a monster standing in it steams violet.
- **Effect:** a monster in it regenerates 4 HP/s and attacks 25% faster; a hero in it walks at x0.8 (the goo slow) and
  takes 2 per second.
- **Themes:** any room with a hellgate; strongest in the lair (torture chamber, throne room).
- **Builds on:** hellgate placement, `Damp`'s cell field, `Grime`, `CornStrike`, `heal` and `set_modifier`
  (`STAT_ATTACK_RATE`), the goo slow.
- **Networking:** the cells are spawn data; cleaning follows the cast (which lands on every machine), so no message; the
  host keeps the cleaned list for late joiners. The host applies regen to its monsters; each owner hurts its own hero.
- **Rule 3 and 4 fit loosely:** nothing "sets it off", and cleaning is the opposite of a bill (question 24).

### 4.7 Suggested build order (hazards)
1. **Railings and "shove here" spots** (S-M): the payoff for Rebar's bigger shove, and research item D11.
2. **Live wires + water** (M): after the daze status and the explosive-props plumbing; the pools and damp exist.
3. **Oil slicks** (M): Burning and damp's cell field exist.
4. **Corruption pools** (S-M): gives the hellgates a fight around them.
5. **Steam pipes** (M): needs the dynamic line-of-sight blocker.
6. **Doors** (L): the same blocker plus nav changes, a new model and the brute's smash.

---

## 5. Build order across all four [proposal]

| # | What | Size | Depends on |
|---|---|---|---|
| 1 | AI restraint baseline (1.4) | S | nothing; host-only, no protocol change |
| 2 | Railings and "shove here" spots (4.3) | S-M | Rebar's 1.6 shove (decided) |
| 3 | Voice orders (1.1-1.7) | M | 1; recognizer clips for the names and order words |
| 4 | The medic (3) | M | nothing new (the `heal` verb, the flee scorer) |
| 5 | The pavise (2) | M-L | a `turn_rate` on `Monster`, `Combat.shielded` in every helper and `Projectile`; best after 4 (the fortress) |
| 6 | Live wires + water (4.1) | M | the daze status and the explosive-props plumbing (both in worktrees) |
| 7 | Oil slicks (4.2) | M | the explosive-props plumbing |
| 8 | Corruption pools (4.6) | S-M | nothing new |
| 9 | Steam pipes (4.4) | M | a dynamic line-of-sight blocker in `HexMap` |
| 10 | Doors (4.5) | L | 9's blocker, dynamic nav blocking, the brute's door smash |

Items 1 and 2 fit the next playtest: both are small and change nothing on the wire. Measure first hits per hero again
(`combat_log.csv`) after 1: Rebar's share should fall from 130 of 238.

---

## 6. Open questions for the user

**Voice orders**
1. Are the three orders right: "follow" (default), "hold", "go", plus "crew"/"everyone" for both?
2. "Go" is one syllable, common in chatter and close to the proposed Ghost spell. Keep it, or use "attack" or "get 'em"?
3. Orders without the trigger word (the name is the trigger, the order word must come next): OK?
4. "Hold" holds where the ally stands (my proposal), or at the speaker's reticle?
5. Should "follow" make the speaker the ally's leader (my proposal), or do allies always follow seat 1's hero?
6. Restraint: a 0.6-1.0 s join delay, and only fights already started. Also cut AI damage (x0.6), or not?
7. Feedback: a bark and a pose only, or a stance chip over the ally too?

**The pavise**
8. Shield arc 140°: right? Should a fireball burst on the planks (my proposal) or arc over the shield?
9. The vines exception (a rooted pavise can't turn): keep it?
10. Bolt 18, a 1.2 s aim line locking 0.4 s before the shot, range 20: right? Can Rebar body-block bolts for others?
11. The pavise crossbowman, the riot imp, or both (the pavise in the lair, the riot imp in the bunker)?
12. HUD name: "Pavise Crossbowman", "Crossbowman", or something else?

**The medic**
13. Heal (my recommendation) or raise?
14. The look: the lab-coat imp or the skeleton nurse? And a chartreuse beam rather than the Heal spell's green?
15. How common: none on floor 1, 1 on floor 2, 2-3 on floor 3?
16. Does a hero standing in the beam cut it?
17. Flee at 4.2 (catchable by a walking hero), or faster than the crew?

**Hazards**
18. Live wires: 12 and a 0.6 s daze, x1.5 when soaked, one use per cable: right?
19. Who pays when a monster sets off a hazard, or a brute smashes a door the crew shut: the crew, or nobody?
20. Oil: bill "floor refinishing" per slick lit? Is the popcorn-butter slick in the home cinema in?
21. Railings: should Rebar's fist (1.6) break a panel, or only shoves of 2.0 and more?
22. Steam pipes: on a timer and on a hit (my proposal), or only on a hit?
23. Doors: fire doors in the bunker and blast doors in the lair, 1-2 a floor: worth the L size now?
24. Corruption: should fireball clean it too (contracts already mention goo burned off)? Should heroes take damage in
    it? Since nothing sets it off, does it need a bill, or a small credit for cleaning it?

**Build order**
25. Is the order in section 5 right, with the restraint baseline and railings first?
