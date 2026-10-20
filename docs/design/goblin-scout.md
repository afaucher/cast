# Goblin scout

Status: **built** (monster awareness step 2, 2026-10-18): `scripts/monsters/goblin.gd`, spawned in corridors by
`SiteBuilder`; see "Step 2 as built" at the end. The model (`scripts/art/lowpoly/monsters/goblin_model.gd`), the cosmetic
volley (`scripts/fx/fireworks_fx.gd`) and the look-dev lab (`scenes/goblin_lab.tscn`) came first. Numbers marked
**[proposal]** were proposals; the decisions and "Step 2 as built" say what was built.

> *Building security's idea of an alarm system: one goblin, five rockets, no off switch.*

**Why he exists.** Monsters notice the crew only inside a fixed radius, so the crew stands just outside it and shoots
(`monster-awareness.md` §1, the out-of-range problem). The scout is the alarm half of the answer. He walks the halls
between rooms. When he spots the crew he panics, lights the fireworks on his back and runs for the nearest pack. The
crew wants to catch him quietly, or stop him before the rockets go up.

**What this doc covers, and what it leaves out.** This doc is the scout himself: look, states, numbers, spells, spawning
and networking. **What ALERT means for the monsters the fireworks wake** (who hears them, for how long, how they walk in)
is defined in `monster-awareness.md` (Option 2's ALERT, Option 4's propagation). It isn't repeated here.

---

## 1. Look

*Renders: `godot --path . --resolution 1920x1080 -- --scene res://scenes/goblin_lab.tscn --shot <dir>/goblin.png`
(the views are listed in §9).*

**Silhouette from the game camera** (yaw 45, pitch -56, ortho 24): a **T of ears over a fan of rocket cones and a
pennant**, on a thin hunched body. No other monster has that top shape:

| | Top shape at normal zoom | Colour mass |
|---|---|---|
| Imp (swarmer) | round, upright bat ears, spikes | violet |
| Skeleton (grunt) | bone stick figure plus a sword | bone white |
| Archer | pointed hood plus a long bow | emerald |
| Brute | a wide red mass with horns | red |
| **Goblin scout** | **sideways ears, a red / gold / lime rocket fan, a flag pole** | **chartreuse skin, brown leather, orange pennant** |

**The parts**, from head to feet:
- **Head.** A big head with a long nose, a crooked grin with one snaggle tooth, and a leather aviator cap. His **brass
  goggles have glowing amber lenses**. Those are the enemy glow ("glowing eyes = enemy", `characters.md` §4).
- **Ears.** Huge, long and sideways, pink inside, with a brass ring. They are his mood meter:
  - drooped on patrol;
  - twitching while he looks around;
  - **straight up on the "!"**;
  - swept back in a sprint;
  - flat when he cowers.
- **Body.** A patched leather jerkin over a cream shirt, with an orange scarf. A **bandolier of red firecrackers** crosses
  his chest. He has bare green shins and long pointed feet.
- **The rack.** A wooden backpack frame holding a crate of **five striped rockets** (red, gold, lime; the big one in the
  middle). A fuse runs up the right pole and **sticks up over his right shoulder**, so the lit fuse shows from any side.
  An **orange pennant** on a pole flutters behind him.
- **The long match.** He carries a smouldering slow match in his right hand. Its ember glows.

**Colours.** The scout uses only warm and enemy colours, and so do his fireworks: **red, gold and lime**. Cyan and violet
belong to spells (`north-star.md` §5). The fireworks must never read as a spell.

**Size.** He's lanky but hunched: about **1.8 to the cap, 2.25 to the rocket tips, 2.75 to the pennant**, and about 1.4
across the ears. That puts him taller than an imp (0.92) and about a skeleton's height (2.22) with the rack, but thin. The
HP bar sits at `ui_height` 2.58, above the rack. For comparison: Wick 2.27, Gasket 1.74, Rebar 3.25, brute 2.70.

**Model** (`GoblinModel`, a `MonsterModel`):
- 1,722 triangles and 15 nodes; the budget in `test_monster_models` is 1,900.
- 14 rigid parts: body, head, ear_l, ear_r, arm_l, arm_r, leg_l, leg_r, rack, rockets, flag, match, spark and mark.
- `MonsterModels.make("goblin")` builds it. It's listed in `MonsterModels.DESIGN_KINDS`, not in `KINDS`, so nothing in
  the game spawns it yet.

**Pose hooks** (on top of MonsterModel's `windup` / `attack_swing` / `set_downed` / `set_tint` / `set_fade`):

| Hook | Pose |
|---|---|
| walk from speed (about 2.0) | the patrol: a hunched, creeping amble with drooped ears |
| run from speed (about 5.0) | the flee: leaning hard forward, arms flailing back, the match held high, the pennant streaming |
| `set_look(k, phase)` | a look-around stop: upright, left hand shading the goggles, head sweeping, ears twitching |
| `set_alert(k)` | the "!": a startled hop, ears straight up, arms flung up, the **"!" mark** pops over him |
| `windup(t)` | **striking a light**: a crouch, his right arm out with the match tipped up at the fuse over his shoulder, head turned to watch it, sparks catching. This is his telegraph. |
| `set_fuse_lit(on)` | sparks spit from the fuse end; in a run he keeps **glancing back over his shoulder** |
| `set_mark(on)` | the "!" stays up until the volley, or until he's stopped: **"!" means the clock is running** |
| `attack_swing()` | the cornered firecracker toss (left arm) |
| `set_loaded(false)` | the empty rack after the volley |
| `set_cower(k)` | curled up with his arms over his head |

---

## 2. Stats [proposal]

| | **Goblin scout** | Imp (swarmer) | Archer | Skeleton (grunt) | Brute |
|---|---|---|---|---|---|
| HP | **24** | 12 | 25 | 40 | 140 |
| Speed | **2.0** patrol / **5.0** flee | 5.5 | 3.0 | 3.2 | 2.2 |
| Radius, `shove_mult` | 0.32, **1.4** (light: he flies) | 0.26, 1.5 | 0.36, 1 | 0.38, 1 | 0.6, 0.4 |
| Sight | **front cone 110 degrees out to 14**, all round out to 3 | 9 | 10 | 8 | 9 |
| Attack | firecracker toss, only when cornered (§3) | bite 4 | arrow 8 | cleave 10 | slam 25 |

Heroes walk at 4.5. The crew catches a patrolling scout easily, but a **fleeing scout outruns them (5.0)**, though not an
imp (5.5). Coffee on a hero (7.2) runs him down.

**HP 24 is set so that one committed hit kills him and chip damage doesn't:**

| Kills him outright | Takes two | Doesn't kill |
|---|---|---|
| Wick's drawn arrow (28) | Wick's tap arrow (12 + 12) | tentacles (6 × power) |
| Gasket's hammer (28) | Wick's bow bash (12) | Gasket's spin (16) |
| Rebar's slam (26) | | Rebar's bowl (6) |
| corn (60) | | |
| fireball (40), but see §4 | | |
| teeth at full power (25) | | |

**Sight 14 equals Wick's tap range.** Head on, the scout wins the staring contest, so the crew has to come at him from
behind, from the side, or with a drawn shot. A sighting needs **0.35 s of continuous sight** inside the cone (a double
take), so a hero who flickers across the edge of it doesn't trip him. Inside 3 units he notices at once ("he heard you").
A hit that doesn't kill him also counts as being spotted, by the attacker.

---

## 3. Behaviour

```
PATROL --(sees a hero 0.35 s, or is hit)--> TELL "!" 0.6 s --> STRIKE A LIGHT 1.4 s --> FUSE 1.6 s --> LAUNCH
   ^  \--> LOOK (stops)                         |  interrupted: restart           |  soaked: DUD     |
   |                                            |  soaked: no light 15 s -> RUN   |  killed: POP     v
   \------------------------------------------- (nothing to alert, 20 s) <------ HIDE (empty rack) <-+
```

| State | Time | What he does | Tell on screen |
|---|---|---|---|
| **PATROL** | | Walks his corridor route (§5) at 2.0. Every **6-10 s** (host roll) he does a **glance**: he stops and his ears perk **0.4 s before** his head turns, then he looks back for 1.2 s. | drooped ears, a creeping amble |
| **LOOK** | 2.5 s | At each end of the route he stops in the doorway, **facing into the room**, and sweeps his cone plus or minus 80 degrees. | hand to the goggles, head sweeping |
| **TELL** | **0.6 s** | Spotted. He freezes, faces the hero, hops, and squeaks. He records the **sighting point S** (the hero's position). | **"!"** pops, ears straight up |
| **STRIKE A LIGHT** | **1.4 s** | His wind-up (Monster `ATTACK`, so it uses the telegraph byte): he crouches and puts the match to the fuse over his shoulder while sparks catch. **Interruptible**: death, a shove, a stagger, a **root** (§4) or a **soak** stops it. If he lives, he starts over from 0 when he's free. If he's soaked, he can't light for the 15 s soak, so he RUNs and yells instead (below). | crouch, the orange wind-up pulse, sparks catching, "!" held |
| **FUSE** | **1.6 s** | The fuse burns. He legs it at 5.0 toward the **nearest room with an idle pack** (§5), glancing back. When the fuse ends he launches from wherever he is. Only **water** (a DUD) or **death** (a POP) stops it now; a shove or a root only moves where it goes off. | fuse sparks on his shoulder, "!" held, running |
| **LAUNCH** | 0.6 s, plus the 3.5 s show | Three rockets go up 0.3 s apart from his rack at **F** (his position). The host raises the alarm (§3.1). | the volley (§6) |
| **HIDE** | | Empty rack. He runs behind the woken pack (more than 4 from any hero, preferring to stand behind a brute) and cowers. **Cornered** (a hero within 2 and nowhere to run): he tosses a **firecracker** (0.45 s wind-up; a pop at the hero's feet through `Combat.explode`: radius 1.5, **3 damage, shove 1.0**, 3 s cooldown). After 20 s with nothing left to alert he resumes his patrol, still empty. | cowering; the left-arm toss |
| **RUN** (soaked, can't light) | | Runs for the nearest pack's room. When he arrives he **yells**: the awareness doc's room shout (Option 1), not the fireworks alarm. | "!" held, dripping |

**Outcomes, from best to worst for the crew:**

| When he's stopped | What happens |
|---|---|
| Before the "!" (unaware) | **Silent.** Nobody knows. |
| In TELL or STRIKE A LIGHT, by death | **Silent.** The match drops and goes out. |
| In STRIKE A LIGHT, by a shove, stagger or root | He **starts over** when free. That buys time, but isn't a stop. |
| Soaked before the fuse is lit | **No fireworks for 15 s.** He runs and yells: a **room shout** where he arrives. |
| Soaked during the FUSE | **DUD:** "pfft", steam, wet rockets (they stay on the model, wet). He runs and yells, as above. |
| Killed during the FUSE | **POP:** the rack topples and the burning fuse sets off his **firecracker bandolier on the floor** 0.5 s later. It's loud but low: a **room shout from F** (radius 10, Option 1), **not** the fireworks alarm. Soaking the body in that 0.5 s, or killing him over a void (ring-out), makes it silent. |
| Fire on the rack (fireball or Burning) at any time | **Instant LAUNCH** where he stands (§4). |
| Nothing | **LAUNCH** at F: the full alarm. |

The gradient is the fun: clean (silent), late (one room hears), failed (the corridor's rooms come). Every outcome is
caused by players and readable on screen. **No random duds**: a dud is only ever a wet rack (north-star §2: chaos from
players, not dice).

### 3.1 What the fireworks do (gameplay)
The scout supplies **F** (the launch point) and **S** (where he saw the crew), and calls the alarm once at LAUNCH. Who
hears it and what they do is **`monster-awareness.md` Option 4**, built on Option 2's ALERT: within 18 of F, or a door
within 24, the 12 nearest, ALERT toward S for 20 s, on edge for 60 s, and a second scout runs toward S instead of
launching. The rockets themselves **deal no damage**: they ricochet off the ceiling and burst harmlessly (§6).

**Terms across the two docs.** The awareness doc's "fuse" (1.5 s, the kill window) is this doc's **TELL + STRIKE A
LIGHT** (2.0 s). Its rule that killing, rooting or shoving the scout cancels the alarm holds there. This doc's **FUSE**
is a second, messier window after the light has caught.

---

## 4. Spells against him

Timings use `voice-mechanic.md` and `monster-awareness.md` §1.2: about **0.4 s** to react, about **0.6 s** to say
"cast <spell>", and about **0.15 s** of recognition. That's roughly **1.15 s** from the "!" to the cast, plus the spell's
own delay. **The clean-stop window (TELL + STRIKE A LIGHT) is 2.0 s.** The FUSE adds 1.6 s more for the messier outs.

| Spell / attack | What it does to him | Lands (from the "!") | Result |
|---|---|---|---|
| **Vines** | Root 1.6-2.2 s. **Scout rule: a rooted scout can't strike a light**: the vines bind his match arm. Lighting restarts from 0 when the root ends. On a scout in the FUSE: he's stuck, so it goes off **in the corridor**, away from the pack's door (the awareness doc's door-24 rule then reaches fewer rooms). | about 1.45 s (0.3 s telegraph) | **The** stopping spell: about 3.6 s of guaranteed safety (the root plus a fresh 1.4 s light) to kill him |
| **Damp** | Soaks for 15 s (`Burning.soak`): no light, and a burning fuse goes out (DUD). A wide area, so it forgives bad aim. It also makes him fireball-proof (FIZZLE). | about 1.35 s (0.2 s telegraph) | Stops the fireworks; he still runs and yells (one room shout) |
| **Corn** | 60 damage, a kill. The cob falls **1.2 s** after the cast and he runs at 5.0, so the crew has to **lead him**, or drop it during a LOOK stop (he stands for 2.5 s). | about 2.35 s: in the FUSE unless it was called before the "!" | Called early: silent. Called late: **POP**, a room shout |
| **Fireball** | 40 damage kills him, **but the blast lights the rack: an instant LAUNCH at his spot** (no roll; fire always lights fireworks). On an empty rack, it's just a kill. On a soaked scout: FIZZLE, a clean kill. | about 1.9 s (it flies at 11) | **"Don't fireball the goblin."** Damp then fireball is the combo. |
| **Burning** (an earlier fire) | The rack catches **1.0 s** after he ignites: LAUNCH. | | the same lesson |
| **Tentacles** | Shoves him 2.5-4 hexes × 1.4, interrupting the light (he restarts), plus 6 × power damage. Into a pit or the void: a ring-out, **silent**. In the FUSE: it moves F; shove him **back down the corridor**, away from the pack. | about 1.4 s (0.25 s telegraph) | buys time, or a ring-out |
| **Teeth** | Counts as a hit (he notices). It pops for 25 × power after 2.0 s (power ~0) down to 1.0 s (power 1). Full power kills him during the light (silent); weak power pops during the FUSE (POP). | 2.15-3.15 s | power decides: clean or late |
| **Coffee** | **On a hero:** 7.2 speed runs him down. **On him** (by accident, radius 1.5-2): he flees at 8.0 and **strikes a light 60% faster (0.9 s)**. The fuse is chemistry, not hands, so it isn't sped up. Then the crash: 2 s at -30%, a 2.0 s light. | immediate | an accident that hurts; good on your runner |
| **Heal, armor** | nothing (heroes only) | | |
| Wick's **drawn arrow** | 28, a kill, after a 0.7 s draw | about 1.1 s | the head-on answer |
| Wick's **tap arrows** | 12 each, so two taps 0.55 s apart | about 1.0 s | clean, if both hit a scout who is standing still |
| Gasket's hammer, Rebar's slam | a one-hit kill | | the sneak-up kill |
| Rebar's **bowl** | 6 damage plus a 2-hex shove: interrupts the light; bowl him into a pit | | |

**The vines rule is a deliberate exception.** Rooted monsters can still attack today (`spells.md` "Vines"), and the
scout's light is his wind-up. It stays readable because the wrap visibly reaches his arm and the match. The awareness
doc already assumes it ("rooting (vines) ... cancels the alarm").

---

## 5. Spawning and patrol routes [proposal]

**How many:** one scout on floor 1, one on floor 2 (two on jobs at difficulty 0.6 or more), and two on floor 3. Scouts
are **extra**: they come out of no room's pack budget, and they aren't a pest kind (open question 8).

**Routes come from the corridors** (`DungeonGen`, step 3: tree links are three cells wide, loops two). `HexMap` keeps no
link list, so SiteBuilder rebuilds them:
1. Take the connected components of cells tagged `"corridor"`. Corridors never touch each other (each keeps a one-cell
   buffer), so each component is one link.
2. Each component's **doors** are its cells next to a room's cells. A component normally touches two rooms.
3. The route is an A* path from door A to door B **inside the component**: the centre lane, which is the route the
   generator carved.

**Which corridors he gets** (rolled with the site's own generator, so it's deterministic per seed):
- longer than **8 cells**;
- **not touching the start room** (he never sees the crew step out of the elevator);
- preferably both rooms have a pack (he has someone to warn);
- several scouts take different corridors.

The climb shortcut is allowed; goblins climb.

**Patrol:** he walks A to B to A at 2.0, with a 2.5 s **LOOK** in each doorway (facing into the room) and the glances
in between. He spawns at a random point along the route. **One volley per scout per floor**: after LAUNCH the rack stays
empty (open question 6).

**Fleeing:** he runs toward the nearest room (by path) that holds an IDLE monster. With nobody left to warn, he runs
away from the crew along his corridor.

---

## 6. The fireworks (cosmetic)

`FireworksFx` is a pure function of (launch point, start time, `fx_seed`, `drift`). It has its own generator and never
uses `GameWorld.rng`. `sample(t)` poses everything, so labs can freeze it.

- **The volley:** 3 rockets, 0.3 s apart. Each climbs on a fizzing trail with smoke puffs for **0.55 s**, up to
  **4.4 above the rack**. That's the bunker ceiling: the camera shows no ceiling, but the rockets **ricochet** off one with
  a white spark star. Each is then deflected for 0.22 s along `drift` (the way he was running, so over the room) and
  **bursts**:
  - a 2.3-2.9 ball of **40 faceted star streaks** in red, gold or lime that sag and fade over 1.35 s;
  - a white-gold core flash;
  - an **OmniLight in the burst colour** that lights the room below (energy 9, range 11);
  - a comic word: **BANG!**, **FWOOSH!**, **POP!** or **KRAK!**.

  About 3.5 s in all, with the smoke lingering for 2.6 s.
- **Sound (not built):** a rising whistle per rocket, a "tink" on the ricochet, deep bangs, and the goblin's squeak on
  the "!".
- **DUD:** `Fx.fizzle_puff` plus "*pfft*".
- **POP:** a string of floor-level firecracker flashes and the word "POP POP POP!".

---

## 7. Networking (`networking.md`, new-content checklist)

1. **Shape: an owned actor, host-owned.** The scout is a `Monster` subclass (`scripts/monsters/goblin.gd`, kind
   `"goblin"`) whose AI runs on the host only. **The volley is a scheduled cosmetic.** **The alarm is host gameplay**:
   the host owns every monster it wakes, so no message is needed for it.
2. **Declarations** (`net_fields()`):
   - `scout_phase` (PATROL / LOOK / TELL / LIGHT / FUSE / HIDE / RUN) and `loaded` are **`OWNER`**, because clients draw
     the "!", the fuse sparks and the empty rack.
   - The route, the glance timer, the sighting point S, the fuse end time and the flee goal are **`PRIVATE`**.
   - Sight 14, the speeds and the times are **`SPAWN`**.
   - The model is `LOCAL`.
   - **Carrier:** STRIKE A LIGHT rides the existing ATTACK state and telegraph byte. The other phases need bits the
     monster flags byte doesn't have (`monster-awareness.md`, Option 2). So: one reliable `world.scout {id, phase, at}`
     event per phase change, about 5 per scout per floor (`NetEvents.CARRIES`), and `loaded` in the spawn snapshot for
     late joiners.
3. **Verbs:** damage, shoves and soaks reach him through `apply_damage` / `shove` / `set_modifier` / `Burning.soak`. The
   firecracker resolves through **`Combat.explode`**.
4. **Randomness:** the route pick uses the **site's** seeded generator (every machine builds the same one). Glance timing
   uses the host's `GameWorld.rng` and travels as the phase. The fireworks' look uses `fx_seed` from the volley event.
   The model and `FireworksFx` never touch `GameWorld.rng`.
5. **Motion:** the volley is `(F, start, fx_seed, drift)` in **one reliable host event**, `world.fireworks`. Every
   machine spawns `FireworksFx` with `start_time` on the synced clock. The scout's own motion streams like any
   monster's.
6. **Cosmetic or gameplay:**
   - Gameplay: the phases, the light / fuse timers, the alarm, the firecracker damage.
   - Cosmetic: the rockets, bursts, light, words and smoke, plus the DUD and POP effects (each a host event, drawn
     locally).
7. **Late joiner:** sees the scout's phase and `loaded`. A volley already in the air is skipped (cosmetic). Monsters that
   are already ALERT show their state as usual.
8. **Two-peer scenario** (`test_net_goblin`, once built), covering three cases:
   - a client's hero is spotted, and the client sees the "!" within the world delay;
   - the client kills the scout during STRIKE A LIGHT, and **neither** machine gets a volley or an alarm;
   - a volley fires, and both machines draw it while the host's monsters go ALERT.

---

## 8. Why it's fun (north-star filter)

- **Players cause it:** he only fires when the crew is seen, and every stop or failure is the crew's doing.
- **Readable in a second:** the "!", then the crouch with a sparking match, then a running goblin with a fizzing rack.
  Ears and the "!" carry it at game zoom.
- **A coordinated team plays around it:** they spot him first ("goblin in the east hall"), wait for his back, call the
  stop ("vines the goblin!", "damp him!"), and keep the fireball user quiet.
- **Something to say:** "He's turning", "don't fireball him", "he's lit, damp, DAMP!".
- **Recoverable:** the worst case is a wave of ALERT monsters walking in. That's a harder fight, not a lost run.
- **Funny when it goes wrong:** Wick fireballs him and the bunker gets a light show; a coffee meant for Gasket turns him
  into a rocket-powered courier.
- **Both pillars:**
  - **Exploration:** the halls between rooms matter, and so do looks and timing.
  - **Spoken spells:** a 2.0 s window that a spoken spell fits, with 0.5 s or more to spare.

---

## 9. Lab and files

| File | What |
|---|---|
| `scripts/art/lowpoly/monsters/goblin_model.gd` | `GoblinModel`: parts, palette, pose hooks, `pose_scout(name)` for stills, `make_alert_mark()` |
| `scripts/fx/fireworks_fx.gd` | `FireworksFx`: the volley, a pure function of time |
| `scripts/art/lowpoly/monsters/goblin_lab.gd`, `scenes/goblin_lab.tscn` | The lab: a hand-built bit of bunker (room, corridor, room with a pack, lineup room) with the real terrain look |
| `scripts/art/lowpoly/monsters/monster_models.gd` | `make("goblin")`, plus `DESIGN_KINDS` |
| `tests/test_monster_models.gd` | The goblin runs every model check, plus its own pose hooks |

The lab views are written as `<base>_<view>.png` at the resolution given:

| View | What it shows |
|---|---|
| `patrol_game` / `patrol_close` | patrolling the corridor, the crew sneaking up behind (the game view has a faint sight-cone overlay) |
| `alert_game` / `alert_close` | the "!" with Wick drawing on him |
| `light_close` | striking a light |
| `fuse_close` | running with the fuse lit |
| `fireworks_game` / `fireworks_close` | the volley over room B with the pack turned toward it |
| `lineup` / `lineup_game` | the size lineup |
| `turn_*` | the turnaround |
| `pose_*` | the poses; the contact sheet goes to the `--shot` path |

---

## 10. Open questions for the user

1. **The clock:** "!" 0.6 s, then light 1.4 s (the clean stop: 2.0 s), then fuse 1.6 s (3.6 s to launch). The awareness
   doc suggested 1.5 s for the clean window. Tighter, or about right?
2. **A late kill** (during the fuse): a small floor POP that wakes one room (my default), or a full clean stop for any
   kill before the launch?
3. **Fire lights the rack.** Keep "don't fireball the goblin" as a lesson, with damp then fireball as the answer?
4. **The vines exception:** a rooted scout can't light. Keep it, even though rooted monsters can still attack?
5. **A sneak-attack bonus** on an unaware scout? My default is no: HP 24 already dies to any one heavy hit.
6. **One volley per floor,** or does he restock at a supply crate after about 60 s and go back on patrol?
7. **How many:** 1 / 1-2 / 2 on floors 1-3, or none on floor 1 until the crew has seen the mechanic?
8. **A goblin contract pest** ("goblin infestation": every kill pays), and/or a drop such as a "spare rocket" component
   for a future flare or fireworks spell?
9. **Does he hear voices?** Crew speech within about 6 counting as a noise (the "hush zones" idea; awareness doc question 8).
10. **His name in the HUD:** "Goblin Scout", "Lookout", or something else?

## Decisions (user, 2026-10-18)
- **Timing is right** ("!" 0.6 s + lighting 1.4 s + fuse 1.6 s): a good intercept window; confirm in playtest.
- **Killed once the fuse is lit: the fireworks still go off** (the full alarm), unless the rack is soaked (damp)
  first. Only a stop before the fuse catches is silent.
- **No sneak-attack bonus damage.**
- **He restocks** about 60 s after a volley (not one volley per floor).
- **One per floor, sometimes two** (1-2).
- **HUD name: "Goblin Scout".**
- **He counts toward "exterminate everything" contracts** ("Yes, count him", 2026-10-18, after step 2): a living scout
  keeps such a floor from being clean. He is never a pest kind of his own (open question 8 stays open).
- Not answered yet: "fireball lights the rack" and "vines stop him lighting" stay as designed until the playtest says otherwise.

## Step 2 as built (2026-10-18)

`scripts/monsters/goblin.gd` (kind `"goblin"`, HUD name "Goblin Scout"), built with the decisions above. The alarm's
propagation is `MonsterSenses.alarm` (`monster-awareness.md`, "Step 2 as built").

### The scout
| What | As built |
|---|---|
| Stats | HP 24, patrol 2.0 / flee 5.0, radius 0.32, `shove_mult` 1.4; sight: front cone 110 degrees out to 14 with line of sight held **0.35 s**, all round 3 (that is his `aggro_range`: 0 freezes him like any monster) |
| Clock | "!" **0.6 s** -> light **1.4 s** (`scaled_cooldown`: coffee on him speeds it) -> fuse **1.6 s** -> volley |
| Patrol | his corridor route doorway to doorway (waypoints every 3 cells), a **2.5 s** look into the room at each end (+/- 80 degrees), a glance every **6-10 s** (ears perk 0.4 s, then a 1.2 s look 70-120 degrees aside) |
| Stops | killed in "!" or the light: **silent**; shoved / staggered while lighting: starts over when free; rooted: no progress while rooted; soaked before the fuse: runs to the nearest resting pack (30 at most) and **yells** there (a shout: resting monsters within 10 go ALERT toward S); soaked with the fuse lit: **dud** (`Fx.fizzle_puff`, the rockets are spent); **killed with the fuse lit: the volley still goes up where he fell** (user), unless soaked; fire (a fireball's blast, before its damage lands, or burning for 1 s): an instant volley; no bonus damage |
| After a volley | HIDE: behind the nearest monster farther from the crew (else 4-6 hexes away from the crew), cowering; cornered (a hero within 2): a firecracker, a 0.45 s wind-up, a pop 1.2 ahead of him (radius 1.5, 3 damage, shove 1.0) through `Combat`, every 3 s; after **20 s** with nobody within 4 he rejoins his route (rack empty) |
| Restock | **60 s** after a volley or a dud, once he is patrolling or hiding |
| Second scout | within 18 of a volley: runs to S (10 s at most), no volley of his own for 30 s |
| Spawning | 1 on floor 1, 1 on floor 2 (2 at difficulty 0.6 or more), 2 on floor 3 (`SiteBuilder.scout_count`), fewer if the floor lacks corridors: each a different corridor link longer than 8 cells, never touching the start or arrival room, links with packs in both rooms first; a generator of its own seeded from the floor (nothing else in the plan moves). 15 floors measured: 20 scouts, every floor 1-2, the scouts' planning at most about 7 ms, the whole plan at most 160 ms (limit 600). Not in the packs, not in `Site.monsters`; he counts toward an "exterminate everything" contract (user: "Yes, count him") |

### Online (as §7, with these details)
- His wire state stands for the phase: PATROL / LOOK IDLE, TELL SUSPICIOUS, LIGHT ATTACK (with the telegraph byte, so
  the light shows), FUSE / RUN / ASSIST ALERT, HIDE SEARCH. `scout_phase` and `loaded` (OWNER) ride
  `world.scout {id, p, l}` on every change; his route and timers are PRIVATE.
- The volley: `world.fireworks {id, x, y, z, s, f, dx, dz}` (the launch point, its start on the shared clock, the fx seed
  rolled on the host's `fx_rng`, the drift); a client starts its `FireworksFx` at the world's render time. A dud:
  `world.dud`.
- The light is not a `world.windup` (nothing to resolve); the cornered firecracker is.
- A late joiner gets every scout's phase and rack in its snapshot (`NetWorld.scout_states`); a volley in the air is
  skipped.
- `test_net_monster_step2` covers the client seeing his phases in order, the volley and the woken monsters. The kill and
  "client spotted" scenarios of §7.8 are covered by the single-process tests (`test_monster_goblin`), not over the wire.

### Deviations from the design above
- **A kill during the FUSE is the full alarm** (user), so the floor-firecracker POP (a room shout) is not built.
- **The "!" in his animation stays** although the user turned down "?"/"!" indicators for monsters: it is his tell.
- **A hit or shout on a patrolling scout** makes him look toward it (a doorway look); only being seen or hit by the crew
  starts the "!". He never walks on ALERT himself.
- **He patrols whether or not the crew is near** (one or two walkers a floor cost nothing next to the 28-unit limit).
- **Sound cues are not built**; they would hook on `scout_phase_changed` (the squeak on TELL, the fizz on LIGHT/FUSE),
  `fireworks_launched` (whistle, ricochet tink, a recorded whistle and bang per rocket: Sfx "firework") and `fireworks_dud` (pfft).
