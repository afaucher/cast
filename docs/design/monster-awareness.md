# Monster awareness: alerts, idle life and the out-of-range problem

Status: **audit and options** (2026-10-18). Nothing here is built. Line numbers refer to the working tree on
2026-10-18. Another agent was editing `site_builder.gd`, `actor.gd`, `game_world.gd` and `hex_map.gd` at the time, so
those numbers may drift.

**The observation (user, playtest 2026-10-18):** "You can walk into a room and until you hit a very specific distance,
they can't see you at all. This makes combat kind of boring if you just stand out of range and shoot them. So maybe
there's one enemy type that alerts others, or puts them on alert while running away. Another way to make it more
interesting is goals or periodic movement by the AI, so you can't just stand right out of range, because it might move
into range. We also have a bunch that just face walls."

Follow-ups from the user, all folded in below:
- Idle behaviours that are both flavour and tells: imps playing with each other, archers shooting the client's expensive
  stuff.
- Brutes that pick fights with each other. These should be **rare**, and they should come from the crew **taking long on
  a floor**: idle monsters get restless as floor time passes.
- The alarm type is decided: a **goblin scout** that patrols the halls and sets off **fireworks** when it spots the crew.
  Its look and its own behaviour are designed in `docs/design/goblin-scout.md`, which a separate agent is writing. This
  doc covers only how the alarm it raises spreads.

---

## 1. Audit: what monsters do today

### 1.1 The state machine (`scripts/monsters/monster.gd`)

`enum State { IDLE, CHASE, ATTACK, RETURN, DEAD }` (`monster.gd:21`).

| Piece | Where | What it does |
|---|---|---|
| Idle scan | `_tick_idle`, `monster.gd:239-246` | Every `SCAN_INTERVAL` 0.25 s (`:29`), takes the nearest living hero within `aggro_range` **with** line of sight (`_nearest_hero(aggro_range, true)`, `:359-373`). If it finds one, it calls `aggro()`. Nothing else happens in IDLE: no movement, no turning, no facing test. |
| Aggro | `aggro()`, `:186-192` | Works only from IDLE or RETURN. It enters CHASE and calls `_alert_pack`. |
| Pack alert | `_alert_pack`, `:389-399` | Every **IDLE** monster within `alert_radius` (5.0, `:46`, flat, no line of sight) enters CHASE on the same target. That's the only "communication" there is. |
| Chase knowledge | `_validate_target`, `:403-427` | Once chasing, a monster always knows where its target is: A* straight to it with no line-of-sight test. It retargets to a closer hero within 1.5x aggro and gives up when the target is more than **2.5x aggro** away (`:424`) or it is more than `leash_range` 18 from home (`:410`). |
| Return | `_tick_return`, `:315-326` | Walks home, then **heals to full** (`hp = max_hp`, `:323`) and goes back to IDLE. |
| Hit while idle | `_on_damaged`, `:647-653` | If the monster is **IDLE** and the source is a living enemy Actor, it calls `aggro(source)`. That covers out-of-range hits: arrows, fireballs, corn, teeth and tentacles all pass the caster as `source` (`arrow_shot.gd:78`, `corn_strike.gd:80`, `spell_book.gd:357-362`, `teeth.gd:130`, `tentacles.gd:56`, `burning.gd:298`). Online, a client's hit reaches the host as `obj.req hit` and the host applies it with the hero's puppet as source (`net_objects.gd:493`), so it works there too. |
| **Hole: hit while returning** | `:650` | A monster in RETURN **ignores** damage (the check is `state == State.IDLE` only, although `aggro()` would accept RETURN). It walks home and heals to full while you shoot it. |
| Timers | `_ready`, `:135-137` | Scan, repath and retarget timers are staggered with `GameWorld.rng`, so a pack never scans on the same frame. |

Facing is `Actor.facing := Vector3.FORWARD` (`actor.gd:74`). It only changes when the monster moves or faces a target
(`face_point`, `actor.gd:714`).

### 1.2 Per-type numbers vs. the crew's reach

1 hex step = sqrt(3) = **1.73** world units (`hex.gd:7-10`). Heroes walk at 4.5.

| Kind (name) | HP | Speed | Aggro (LOS) | In hexes | Notes |
|---|---|---|---|---|---|
| grunt (Skeleton) | 40 | 3.2 | **8.0** (`grunt.gd:10`) | 4.6 | melee 1.5 |
| archer | 25 | 3.0 | **10.0** (`archer.gd:12`) | 5.8 | shoots from 5-8 (`:13-14`), arrow range 16, flees inside 3.5 |
| brute | 140 | 2.2 | **9.0** (`brute.gd:17`) | 5.2 | cannot climb, slam radius 2 |
| swarmer (imp) | 12 | 5.5 | **9.0** (`swarmer.gd:11`) | 5.2 | the only kind faster than a hero |

| Crew reach | Range | Beyond grunt aggro by |
|---|---|---|
| Wick tap arrow | **14** (`hero_kit.gd:70`), 12 dmg / 0.55 s | +6.0 (3.5 hexes) |
| Wick drawn arrow | **18** (`hero_kit.gd:74`), 28 dmg, pierce 3 | +10 |
| Every spell's aim point | **12** (`spell_book.gd:62`, `= Hero.BOLT_RANGE`), clamped in `resolve_target` (`:280`) | +4, plus the blast radius |
| Fireball / corn / tentacles blast | +1.4-2.4 / +2.5 / +2.2-3.0 | so a blast reaches monsters **13.4-15** away |
| Rebar bowl | 9 | +1 |
| AI allies engage | within 9 of their leader (`ally_brain.gd:24`) | |

**How far "just out of range" is:** for a skeleton, anywhere from 8 to 14 (Wick) or 8 to about 14.5 (a blast at max
aim). That's a band about **3.5 hexes deep**. For archers it is 10 to 14.

**Can the player always out-range them? Yes.** Every kind is outranged by Wick's tap arrow and by every blast spell, and
only the imp is faster than a hero:
- A grunt hit at 14 needs (14-1.5)/3.2 = **3.9 s** to reach melee. Four taps kill it in **1.65 s**, while it is still
  about 8.7 away.
- An archer needs 2 s to close to its 8-unit band. Three taps (1.1 s) kill it first.
- A brute needs 5.5 s. Twelve taps take 6 s, and you out-walk it (4.5 vs 2.2).
- An imp dies to one tap.

With ~0.5 s of speech plus ~0.15 s of recognition (`voice-mechanic.md:21`) and 10-14 s spell cooldowns, sniping with
Wick's bow is the dominant play, and it does not use the voice pillar at all.

### 1.3 Measured on generated floors

I ran a headless script from the scratchpad (nothing in the repo changed). It covered 8 seeds x 3 floors = 24 contract
floors at difficulty 0.5, with every client archetype and the real `DungeonGen.for_run` + `SiteBuilder.plan/spawn`. Gate
spawns are not counted.

| Measure | Result |
|---|---|
| Pre-placed monsters per floor | **31** on average (min 20, max 53) |
| Kind mix | imps 53%, skeletons 24%, archers 18%, brutes 6% (1.8 brutes per floor) |
| Rooms with a pack | 77% of rooms, **5.7 monsters** per occupied room |
| Room span (farthest cell-to-cell) | median **20.8**, p25 17.3, p75 24.2, max 31 (2-3x aggro) |
| **Pack-mates woken by hitting a skeleton, archer or brute** (roommates within `alert_radius` 5) | **2.9%**. Within 8: 20%. Within 10: 38%. Within 12: 56%. With line of sight: 88% |
| Pack-mates woken by hitting an imp | 64% (its own clump: `_place_kinds` clumps imps within 2 hexes) |
| Monsters with line of sight to their room's main door | 90%, at a mean distance of **11.0** |
| ... that notice a hero standing in that door | **34%** |
| ... visible from the door, not noticing, and inside Wick's 14 | **32%** |
| Monsters with at least one walkable cell in line of sight that is outside their aggro and inside spell range (12) | **100%**, with 19 such cells each on average (+12 more cells out to 14) |
| Monsters facing the default direction | **100%** |
| ... with a wall within 2 hexes (3.5) straight ahead | **33%** (5.6% within 1 hex) |
| ... if they faced the room centre instead | 3.6% (2.5% within 1 hex) |
| Priced props per floor | 6; 47% of archers have one within 10 with line of sight |
| Floors with 2+ brutes | 38%; brute pairs in the same room: 0.3 per floor |

**What this means.** Rooms are wider than the monsters' sight, packs are spread out on purpose (`_pick_spread`,
farthest-point sampling, `monster_factory.gd:133-146`), and the pack call only reaches 5 units. So a hit on anything but
an imp wakes almost nobody else. The crew can stand in or near a door, see most of the room (the camera shows about 29 x
43 units of floor: ortho size 24 at a 56-degree pitch, `camera_rig.gd:6-9`), and pull monsters **one at a time**, each
of which dies before it arrives.

### 1.4 Why they face walls

Nobody sets a monster's facing at spawn: `MonsterFactory.spawn` (`monster_factory.gd:26-39`), `SiteBuilder._place_kinds`
(`site_builder.gd:1022-1062`) and `Hellgate._do_burst` (`hellgate.gd:400-424`) all leave it alone. So every monster
keeps `Actor.facing = Vector3.FORWARD` (0, 0, -1) (`actor.gd:74`), and IDLE never turns.

The camera rig is yawed 45 degrees (`camera_rig.gd:6,27`), so world -Z points **up and to the right on screen**. Every
idle monster on the floor stands with its back three-quarters to the camera, staring at the same compass point. That is
toward the room's far walls, which are exactly the walls the camera shows. A third of them have a wall within 2 hexes in
front of them. Priced props already avoid this with orientation rules (`face_center`, `face_entrance`,
`away_from_wall`: `priced_prop.gd:40-43`, `SitePlan.entrances`). Monsters never got one.

A monster that walked home after a RETURN keeps its walking direction, so it ends up facing wherever home happened to
lie. Gate spawns face their path, and then the wall if they give up.

### 1.5 Hellgate spawns vs. pre-placed packs

- **Pre-placed packs** (`SiteBuilder._spawn_packs`, `site_builder.gd:951`) follow every rule above. Budgets grow with
  the room index, the floor and difficulty, and with nearness to a gate (`_plan_packs`, `:821-829`). There's a density
  cap of 1 per 6 walkable cells (`room_cap`, `:1011`).
- **Gate spawns** (`hellgate.gd:400-424`). The gate is dormant until a hero comes within `ACTIVATE_RANGE` 12 (`:50`) or
  it takes damage. Then it bursts 1-4 monsters every 14 to 4.5 s, up to a cap of 3-12, on a ring 2-3 hexes out. Each
  spawn is `aggro`ed at the nearest hero **immediately, with no range or line-of-sight test** (`:420-422`). If that hero
  is more than 2.5x aggro away (20-25), the spawn gives up, walks back to its spawn cell and idles there facing a random
  wall. Gates are already a goal-driven pressure source; packs are not.

### 1.6 Employees, for comparison (`scripts/contracts/employee.gd`)

The civilians already have a more lively brain. PANIC triggers on a monster within 4 (`:38`) or on being hurt (2 s,
`:56`). They then flee by scoring cells up to 5 rings out for "farther from the threat", refusing a first step toward
it, and finding a path of at most 300 nodes (`_replan_flee`, `:594`). They calm down after 1.5 s with 5.5 of room. The
flee scorer is the right shape to reuse for anything that runs to raise an alarm.

### 1.7 How it runs online (and the rules a change must keep)

- Monster AI runs **only on the host**. On a client every monster is a copy with physics off (`Net.make_copy`,
  `net.gd:75-78`), drawn from the host's stream (`NetWorldCodec.write_monster` -> `Monster.net_show`, `monster.gd:759`).
- Each monster is one 16-byte MONSTER entry: id, position, velocity, angle, hp, flags, telegraph, strikes. The `flags`
  byte packs the **state in 3 bits** (`net_world_codec.gd:147,163`). Values 0-4 are used, so **5, 6 and 7 are free**:
  three new states need no wire change. An entry rides only when its bytes change (plus 3 redundant ticks) and otherwise
  once a second (`net_world.gd:41-42`). An idle, still monster is almost free; a walking one costs about 16 B every
  30 Hz tick. The world budget is 1158 B per packet (`NetWorld.WORLD_BUDGET`), and there is **no distance culling**. So
  53 walking monsters plus a gate's 12 would take about 1 KB, nearly all of it. **Idle movement has to be sparse, or
  limited to monsters near the crew.**
- AGENTS.md rules that apply:
  - Every new var goes in `net_fields()` (AI working state is `PRIVATE`; what clients draw is `OWNER`).
  - Gameplay rolls use `GameWorld.rng`; looks use `GameWorld.fx_rng`.
  - Monsters change others only through verbs (`apply_damage`, `shove`, ...).
  - Hits resolve through `Combat`.
  - No network code outside `scripts/net/`.
- Tests freeze monsters by setting `aggro_range = 0.0` (about 20 places: `test_spell_coffee.gd`, `test_shove_attacks.gd`,
  `test_net_m6_late_join.gd`, ...), and the `--idle_monsters` dev flag does the same (`game.gd:2979-2981`). Any idle
  behaviour must also stay off in that case (or get an explicit `Monster.idle_life` switch). Otherwise those tests
  start moving.

---

## 2. Options

Each option says what it does, how it fixes "stand out of range and shoot", what it costs, how it plays with voice
casting, what it means for co-op and the host, and its risks. Numbers are starting points for tuning.

A shared piece of vocabulary used below: **room** = the `room:<n>` tag of the cell a monster calls home
(`HexMap.cells_with_tag`). It's cheap to read, and it's the natural "pack". **Corridor** cells carry `"corridor"`.

### Option 0: quick fixes (do these regardless)

1. **Spawn facing.** `MonsterFactory.spawn` takes an optional facing, and `_place_kinds` passes "toward the room's main
   door (`SitePlan.entrances`), else the room centre, +/- 35 degrees", rolled on the **site rng** (the same on every
   machine, like the rest of the plan). Measured: walls within 2 hexes ahead drop from 33% to about 4%. Gate spawns face
   away from the gate. Monsters returning home turn to their spawn facing on arrival.
2. **Idle look-around.** Every 4-9 s (`GameWorld.rng`), an idle monster turns to a new heading: its spawn facing +/- 70
   degrees, the door, or toward a recent noise. It never picks a heading that has a wall within 2 hexes (one LOS probe,
   like the measurement). This is the cheapest "they're alive" tell. A facing change rides the stream for 4 ticks and
   then goes quiet.
3. **Hit while returning.** `_on_damaged` (`monster.gd:650`) should accept RETURN as well as IDLE. Then a monster you
   shoot on its way home turns around instead of walking off to heal.

Cost: about 40 lines, plus a facing test. `site_builder.gd` is shared with the pool/theme work, so coordinate.
Voice: none. Online: facing is already OWNER and streamed. Risk: none.

It fixes the wall-staring, but **not** the out-of-range problem on its own. Facing only matters once vision has a front
(Option 2).

### Option 1: noise, and the room hears a fight

- **Hurt shout.** When a monster is hit by a hero, it shouts. Every IDLE monster **in the same room**, plus any monster
  within **10** (flat, no LOS), goes to **ALERT** toward the attacker's position (Option 2). Its own imp clump (within
  5) still goes straight to CHASE, as today.
- **Combat noise.** Effects that already resolve through `Combat`/`SpellBook` call `MonsterNoise.emit(pos, radius,
  source)`. IDLE monsters inside the radius become SUSPICIOUS toward `pos` (a sound, not a sighting). Suggested radii:

  | Source | Radius |
  |---|---|
  | Corn impact | 14 |
  | Fireball blast | 10 |
  | Teeth pop / tentacles | 8 |
  | A monster's death | 6 |
  | Hero melee hit | 4 |
  | Arrow impact | 3 |

  Through a wall (no LOS), the radius is x0.6.

What it fixes: sniping one skeleton now brings its room, on average about 5 more monsters at walking pace from about 11
away. They arrive as a group, which is what the area spells are for. Measured, the shout's reach goes from 3% of
roommates to 100% (room) or 38% (radius 10).

Cost: about 100 lines (a static `MonsterNoise` in `scripts/monsters/`, hooks in `Combat.explode` / `CornStrike` /
`Teeth` / `Tentacles` / `ArrowShot`), plus tests.

Voice: good. It turns sniping into "pull, then cast", and an ALERT walk-in gives 2-4 s to say an area spell.

Online: casts run on every machine, so the noise call runs everywhere. `MonsterNoise.emit` skips copies
(`Net.is_copy`), so only the host's monsters react. There's no wire change.

Risk: a loud corn on the far side of a wall pulls two rooms. That's mitigated by x0.6 through walls and the per-room
cap (Option 2). Performance: one loop over the `monsters` group per noise event (31-65 monsters), which is negligible.

### Option 2: awareness states (idle -> suspicious -> alert -> combat -> search -> idle)

Replace the hard aggro circle with graded awareness. It uses the free state values, so there's no wire change.

| State (wire value) | Tell on every screen | Behaviour |
|---|---|---|
| IDLE (0) | none | Idle life (Option 3). Sight: the **front cone** of 120 degrees out to `aggro + 6` (skeleton 14, archer 16, brute/imp 15); all round out to `aggro` (unchanged). |
| **SUSPICIOUS (5)** | yellow **"?"** over the head (LOCAL Label3D or a decal, from the state) | It saw a hero in the outer cone band, or heard a noise. It turns to face, then walks toward the point at 50% speed. If it still sees a hero after **1.5 s** in total, or a hero comes inside `aggro` with LOS: CHASE with the room shout. Nothing seen for **6 s**: back to IDLE. |
| **ALERT** (shares wire value 5; the difference is a `PRIVATE` host flag, so clients show the same "?". A distinct "red ?" would need a spare bit, and the flags byte has none.) | | Raised by a shout or an alarm (goblin fireworks): it **knows roughly where the crew is**. It walks to the alert point at 80% speed. Sight: all round out to `aggro + 4`, front cone `aggro + 8`. Lasts **20 s**, refreshed by new alarms. Sighting a hero means CHASE. Arriving with nothing seen means SEARCH. |
| CHASE (1) / ATTACK (2) | **"!"** flash on entry | As today. |
| **SEARCH (6)** | grey "?" | Lost the target (out of LOS for 3 s, or beyond 2.5x aggro). It walks to the last known position, looks around (two turns over **5 s**), then RETURNs. Hit during SEARCH: CHASE. |
| RETURN (3) | none | As today, but hits re-aggro (Option 0). The full heal stays, so pulling and resetting is still not free. |
| (7) | | Spare: BUSY for idle activities (Option 3). |

What it fixes: the 8-14 band stops being safe. A monster that **faces** you sees you there, and with Option 0 most of
them face the door. You get a visible "?" and **1.5 s** to act before it becomes "!". Off-cone, the old radius still
applies, so sneaking around a monster's back works. That gives exploration a reason to care about where monsters look.

Cost: about 200 lines in `monster.gd` (the states, the cone test, last-known position, alert timer), about 50 for the
tell, plus tests. Every new var is `PRIVATE` except `state` (already `OWNER`). The tell is LOCAL, drawn from the state,
so it costs nothing on the wire. The test with a grunt "idle when the hero is out of range" (`test_monster_grunt.gd:11-26`)
needs its hero placed outside the cone or behind.

Voice: this is the best fit. The "?" beat (1.5 s) is longer than speaking a spell plus recognition (about 0.6-0.8 s),
so a crew can pre-empt with a call-out ("archer's seen us, fireball!"). Nothing becomes instant.

Online: host-only logic. A client sees the "?"/"!" from the state bits within about 100 ms (the world delay).

Risk: CPU. The outer sight runs to 14-16 instead of 8-10, with up to 64 LOS samples per check. Cheap order: distance
squared, then the cone dot product, then LOS, at 4 Hz. Even 65 monsters x 3 heroes all passing the cone is about 50k
`ground_height` lookups a second, which is fine. Readability risk: too many "?" at once. Cap visible tells to the
nearest 8.

### Option 3: idle life, goals and restlessness

Idle monsters get something to do. Each behaviour is **flavour** (it shows what the kind is) and a **tell or goal that
moves them**, so the edge of range is never fixed. Every choice is a host roll on `GameWorld.rng`; purely visual bits
(an imp's tossed bone, dust) use `fx_rng`. Everything here runs only from IDLE: any SUSPICIOUS, ALERT or CHASE ends it
at once.

**Restlessness, a floor-wide ramp.** R(t) = clamp((t - 120 s) / (480 s - 120 s), 0, 1), with t = `GameWorld.time` on
the floor (host clock):
- **Nothing** restless happens in the first 2 minutes.
- Full restlessness comes at 8 minutes.
- A room that **heard** combat (Option 1) without seeing the crew gets +0.25 on its own R for 60 s (it's agitated).
- Goblin fireworks (Option 4) add +0.25 floor-wide.

The 120/480 numbers are placeholders until we know how long a floor takes (open question 4). R scales the behaviours
below. This is the general pressure against camping: the longer the crew takes, the more the floor moves.

| Kind | Idle behaviour | Tell from the game camera | Ramp with R | Cost |
|---|---|---|---|---|
| **Skeleton** (grunt) | **Patrol**: walks between 2-3 points in its room (points picked once from its room cells, at least 3 hexes apart), pauses 3-6 s at each, and turns to look. | Slow, deliberate walking; the bobbing skull | Walk 60% -> 80% speed; pauses 6 s -> 2.5 s. At R >= 0.5, 1 skeleton in 3 extends its route into the next room through the corridor (a "visitor"). | ~100 lines |
| **Imps** (swarmer clump) | **Play**: two imps chase each other in a loop around the clump centre (radius 2-3 hexes), tussle (bump and bounce: a 0.3 shove each, a real verb, so tiny), or one tosses a bone in an arc (cosmetic, `fx_rng`). The **clump centre drifts** 1 hex every 15-25 s, within its room. | A fast purple scramble; they read as a pack of kids | The drift radius grows from 2 to 5 hexes, and play gets wider and more frequent. | ~120 lines plus poses |
| **Archer** | **Target practice**: an archer with LOS to a priced prop within 10 (47% of archers have one) draws (the usual 0.5 s telegraph) and shoots it every 40 s -> 12 s. Its arrows damage the prop (`prop.apply_damage(8, archer)` on the host); 4-17 arrows break one (prop HP 25-140, `priced_prop.gd:44-61`). | A visible bow draw and an arrow thunking into the wine rack. On a client, the puppet's existing harmless arrow (`archer.gd:_on_strike_visual`) plays it for free. | Interval 40 s -> 12 s. At R < 0.5 it only shoots props priced at $3,000 or less. **Billing is a question (Q1).** | ~60 lines, plus a small `Projectile` change (it only hits heroes and breakables today, `projectile.gd:71`; props are excluded on purpose, `game_world.gd:105-106`) |
| **Brute** | **Restless fights (rare)**: an idle brute rolls every 20 s with p = 0.15 x R^2 (0 for the first 2 min; ~4% a roll at R 0.5; 15% at R 1, about 39% a minute). If it hits, it **walks to a rival**: the nearest idle brute within a 400-node path. Brutes are rare (1.8 per floor, 0.3 same-room pairs), so the fallback is bullying the nearest skeleton within 12. They square off for 2 s (a roar, a chest thump), then trade 3-5 slams over about 8 s, using the existing slam telegraph ring and real **shoves** (`Combat.slam` with team MONSTERS, skipping itself), so both are thrown around the room. | Big, loud and readable: the red slam rings, bodies flying. The walk across rooms is the "it moved into range" moment. | The roll rate rises with R; fights also emit noise radius 14, so nearby monsters go SUSPICIOUS and **gather to watch** (a crowd forms, so positions shift again). | ~150 lines |

How a fight interacts with the crew and the alert states:
- A hero sighting either brute (or any hit or noise from the crew) breaks it up at once. **Both** brutes go to CHASE
  together and are "worked up" for 10 s (+20% speed).
- Slams that hit a priced prop break it like any slam would (see Q1).
- **Damage between monsters is a question (Q2).** My default is **posturing with real shoves and no HP loss**. Real
  damage rewards exactly the waiting we want to discourage ("let them weaken each other"). If the user wants real
  damage, cap it so neither drops below 60% and the winner gets a 30 s "enraged" buff, so waiting is a gamble rather
  than a free win.

**Relevance limit (CPU and bandwidth).** Idle life runs only for monsters within **28** of a hero (about one screen).
Others stand still and keep only their restlessness. This mirrors the gate's "never builds pressure out of sight" rule.
The one exception is a brute walking to a rival that is itself near the crew. The worst case is then about two rooms of
walkers, 12 x 16 B = 192 B a tick.

What it fixes: positions stop being fixed. Patrol points and drifting clumps carry monsters across the 8-14 band, and
restlessness makes waiting cost something: props get shot, brutes wander over, and visitors walk the corridors.

Voice: low intensity. Idle life never forces a fight; it creates openings and tells ("brute fight in the pool room,
corn them both"). Restlessness gives a crew that talks and moves an edge over one that camps.

Online: host-only movement through `move()`/`_nav_to`. The BUSY state (wire value 7) lets clients pick a pose (play,
practice, square-off) from the kind without new bytes. Shoves and prop hits are host verbs on host-owned actors
(`Net.resolves_hit` -> the host). A client sees the prop break via the existing `obj.break`.

Risks:
- Busy idles make a room look chaotic. Keep to at most 1-2 activities per room at a time.
- Patrols pathing into each other. Use short paths (150 nodes) and re-roll on stuck.
- `GameWorld.rng` draws shift other host rolls (e.g. drops). That's harmless, but any seed-locked test expectations need
  updating.

### Option 4: the alarm, the goblin scout (decided by the user)

The goblin's look, model and own behaviour (patrolling the corridors between rooms, spotting the crew, lighting the
fireworks) are in **`docs/design/goblin-scout.md`** (another agent). This section is only **how its alarm spreads**,
built on Option 2's ALERT.

- **The trigger.** The goblin sees a hero (its own sight rules) and records the **sighting point** S, the hero's position
  at that moment. It then lights the fireworks at its own position F after a fuse. That fuse is the kill window: I
  suggest **1.5 s**, longer than a spoken spell plus recognition, so "vines the goblin!" can stop it. The fuse is the
  goblin's ATTACK wind-up, so clients get the telegraph through the existing `windup_begun` / telegraph byte. Killing,
  rooting (vines) or shoving it during the fuse cancels the alarm (`_on_interrupted` already cancels wind-ups).
- **The burst (host).** All monsters that are **IDLE, SUSPICIOUS or RETURN** go to **ALERT toward S** (where the crew
  was seen, not where the goblin stands) if either:
  1. they are within **18** of F (flat, no LOS: fireworks are loud and seen over walls), or
  2. their room has a door within **24** of F. These are the rooms next to the corridor the goblin patrols. Measured
     room spans are a median of 21, so this is typically 1-2 rooms.

  Cap: the **12 nearest** of them, so one alarm never wakes the whole floor (31 monsters on average).
- **What ALERT means for them.** They walk to S at 80% speed with the wider sight (all round `aggro + 4`), for **20 s**.
  They arrive staggered by distance, so a crew holding a doorway sees them come in waves over about 3-8 s.
  - Seeing a hero: CHASE, plus the room shout.
  - Nothing seen at S: SEARCH for 5 s, then RETURN.
  - They then stay **"on edge" for 60 s**: front-cone sight +2 and suspicion confirms in 1.0 s instead of 1.5 s.
- **Side effects.**
  - Floor restlessness gets +0.25 (Option 3).
  - A **dormant hellgate within 18 of F** is not woken. I suggest gates stay crew-woken only (`hellgate.gd:11-14`); that
    is open question 6.
  - The fireworks themselves are a scheduled effect: one host event (position and start time), drawn on every machine
    with `fx_rng`.
- **Second goblin.** A goblin that hears another's fireworks within 18 runs toward S instead of setting off its own. No
  chain reactions.

What it fixes: the room-by-room snipe now has a roaming witness in the halls. The crew has to deal with the goblin first
(a priority target and a voice moment), or accept a pulled wave.

Cost: the propagation itself is about 60 lines on top of Option 2's ALERT. The goblin is its own work item (see its doc):
a new kind in `MonsterFactory.SCRIPTS/COSTS/WEIGHTS`, its model, and spawning in corridors, which needs a corridor
placement step in `SiteBuilder` since packs only use room cells today.

Online: host-run; the alarm event is one reliable host event. No wire change beyond the kind string at spawn (already
a string).

Risk: an alarm that lands while the crew is mid-fight could snowball. That's why there's the cap of 12, the ALERT walk
(not a sprint), and the fuse.

### Option 5: ranged counterplay per type

Make the kinds answer range themselves:
- **Skeletons charge**: hit by something they can't reach or see, they sprint at 1.35x (4.3) for 3 s, about hero speed.
- **Archers out-range when alerted**: from 10-14 they loose a slower, lobbed "volley" arrow (speed 9, range 16), which
  is dodgeable.
- **Imps flank**: an alerted clump splits and paths to two different cells beside the target.
- **Brutes take cover**: a brute shot from out of reach walks out of LOS (a pillar, the doorway side) and waits for the
  crew to come.

Each is about 60-100 lines in its kind's file. It fixes the snipe locally, but it doesn't make the floor feel alive, and
it adds pressure that can feel frantic (charging skeletons plus imps). Better as tuning after Options 1-3.

---

## 3. Recommendation

**First step: Options 0 + 1 + 2, with the lighter half of Option 3.** Then the goblin (Option 4) and the rest of
Option 3 as step 2, once ALERT exists.

### Step 1 (about 450 lines plus tests, all in `scripts/monsters/` plus small hooks)

1. **Quick fixes:**
   - Spawn facing toward the door or centre (+/- 35 degrees, site rng).
   - Idle look-arounds every 4-9 s, never at a wall.
   - Hits wake a RETURNing monster.
2. **Noise and room shout:**
   - A hit shouts to the whole room plus 10 units (to ALERT).
   - Spell blasts make noise: corn 14, fireball 10, teeth/tentacles 8, death 6, melee 4, arrow 3; x0.6 through walls.
3. **Awareness states:**
   - SUSPICIOUS "?" on the front cone (120 degrees, aggro + 6) with a **1.5 s** confirm.
   - ALERT walk (80%) for 20 s.
   - SEARCH 5 s.
   - Tells drawn from the state bits (wire values 5/6/7).
4. **Idle life, the movement half:**
   - Skeleton patrols.
   - Imp play and clump drift.
   - Restlessness R(t) (0 until 2 min, full at 8 min) scaling patrol speed and pauses, drift radius and corridor visitors.
   - The relevance limit (28).

### Step 2 (after the answers below and a playtest)

5. The goblin scout with the fireworks propagation above (radius 18 / door 24 / 12 monsters / ALERT 20 s / on edge
   60 s / fuse 1.5 s).
6. Archer target practice (depends on Q1) and brute restless fights (depends on Q2), both on the R ramp.

Option 5 is held back as a tuning lever.

**Why this package.** Option 2 makes facing and distance matter, which the facing fix then pays off. Option 1 makes a
snipe pull the room. Option 3 makes the edge of range move and puts a clock on camping. Together they turn "pick off
one at a time from 13" into "spot, call it, and cast into the group", which is the voice pillar. None of it is instant:
every escalation has a visible beat (the "?", the ALERT walk-in, the goblin's fuse) of 1.5 s or more.

### What to measure in the playtest (passive logs only, no prompts)

Add a host-side `user://combat_log.csv` (like `VoiceLog`). Per kill and per engagement:

| Metric | What it tells us | Target |
|---|---|---|
| Distance from killer to victim at the first hit, and the victim's state at that moment (IDLE / SUSPICIOUS / ALERT / CHASE) | The "sniped while idle beyond aggro" share | Expect it to be high today; aim for under 30% |
| Peak concurrent aggroed monsters per engagement | Do fights come in groups? | From about 1-2 to 3-5 |
| Seconds from first "?" to "!", and how often a "?" ends without a fight | Is the beat readable and fair? | |
| Area-spell casts per minute, and the share of damage from spells vs. arrows | Is the voice pillar used? | |
| Times a monster reached melee; hero downs per floor | Did it get frantic? | Downs should not double |
| Floor duration; R when the floor was cleared; restless events (patrol visitors, brute fights, props shot by monsters, and their $) | Calibrates the 120 s / 480 s ramp | |
| Wall-facing check: share of idle monsters with a wall within 2 hexes ahead | Confirms the facing fix | Under 5% |

---

## 4. Open questions for the user

1. **Monster-broken props:** do they bill the crew? Today any break bills the full price to the last damager, whoever
   it is (`priced_prop.gd:345-346`, `Ledger.damage` -> `_add`, `contract_ledger.gd:76,139`). An archer breaking the
   $15,000 gold toilet would be about half a contract's pay (gates $3,000 each, origin and pest $10,000). The choices:
   - (a) Bill it: "you let it happen". This is the strongest anti-camping push. My suggestion is to bill, but let
     archers target only props of $3,000 or less until R >= 0.5, and show it on the invoice as "shot by an Archer".
   - (b) Bill half.
   - (c) Don't bill; it's flavour only.
2. **Brute fights:** posturing with real shoves (my default), or real damage (capped at 60% with an enraged winner)?
   And should the brute bully a skeleton when no other brute is around (brutes are 1.8 per floor, rarely two in one
   room)?
3. **The tells:** show "?" and "!" over monsters' heads (my default), or keep it diegetic (turning heads and a bark
   sound only)?
4. **How long does a floor take today?** This sets the restlessness ramp (0 until 2 min, full at 8 min are guesses).
5. **How hard should a pull be?** Should the room shout reach the whole room (my default), or only within 10? The
   "forgiving floor" in the north star argues for the 10-unit version in solo.
6. **Fireworks and hellgates:** should the goblin's alarm also wake a dormant gate within 18? My default is no; gates
   stay crew-woken.
7. **Should restlessness eventually hunt?** At R = 1, should a room send its patrol toward the crew's last noise
   (a sweep), or stop short of that?
8. **Speaking as noise** (the "hush zones" idea in `voice-mechanic.md:301`): later, or never?

---

## Appendix: the measurement

The script was a throwaway in the session scratchpad. It used `extends SceneTree`, loaded at runtime so the autoloads
resolve. For seeds [1, 2, 3, 7, 42, 99, 1234, 555] x floors 1-3 (archetypes cycled, difficulty 0.5), it built
`DungeonGen.for_run` + `SiteBuilder.plan/spawn` and, for each placed monster, measured:
- the first sight blocker along its facing, and along the direction to the room centre or entrance (`HexMap.line_of_sight`
  from chest height in 0.25 steps);
- roommate distances and line of sight;
- line of sight and distance from the room's main door (`SitePlan.entrances`);
- the walkable cells within 9 hexes, in line of sight, split by the bands (0, aggro], (aggro, 12] and (12, 14].

It ran against the working tree of 2026-10-18 (including the in-progress pool and theme changes) and took about 15 s.
