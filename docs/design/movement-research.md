# Movement feel: research and options

Status: **[research]**, 2026-10-21; package A is **built as an A/B profile** (section 5.3, "As built"), `today` stays the
default until the user picks. Nothing else here is built or decided. It answers the user's note of the same day: "the
movement feels a little too basic but I am not sure what is missing." It measures what the hero's movement does today,
compares it with top-down and isometric action games known for good movement, ranks the gaps for Cast, and proposes
packages to try side by side. **[proposal]** marks every number and rule still waiting on the user.

Related docs: `combat-variety-research.md` §3 (player moves, the dodge as idea 9) and `animation-research.md` (pose,
lean, foot planting and attack/cast animation in depth; this doc mentions animation only where it touches movement).

---

## 1. Diagnosis: what the hero's movement does today

The numbers below come from the code and from a headless probe (a scratch test that drove a hero by `move_override` and
logged every physics frame at 60 Hz; it is not committed).

### 1.1 The pieces
| Piece | Where | What it does |
|---|---|---|
| Input | `PlayerController._physics_process` | WASD only (`InputSetup.KEYS`), 8 directions, camera-relative. **No gamepad bindings exist.** Mouse aims. |
| Walking | `Actor.move` | Kinematic: `position += dir * effective_speed() * delta`. No velocity state, so no acceleration or momentum. |
| Speed | `Hero._init`, `Actor.effective_speed` | **4.5 u/s** for every hero (kits do not set speed). x0.75 wading, x0.5 goo, x0.5 drawing the bow, x1.6 coffee, 0 rooted. |
| Facing | `PlayerController` -> `Actor.face_point(aim_point())` | The hero always faces the **mouse**, never the walking direction (twin-stick style). |
| Visual turn | `Hero._process` | The drawn body lerps to `facing` at `TURN_RATE` 18/s. |
| Walls | `HexMap.clip_move` + 11 tries in `Actor.move` | Slides along wall faces and drop edges, including turned tries of 30-75° (the lava-bridge seam fix). |
| Steps and climbs | `HexMap.movement_check`, `Actor.snap_to_ground` | +1 is a step at full speed. +2 is a climb at `climb_speed_factor` (0.35, Wick 0.6, Gasket 0.25; Rebar can't). +3 is a wall. Drops of up to 3 levels are walked off. Height eases with a lerp (rate 14, 4 while climbing): no hop, no gravity. |
| Attacks | `Hero.melee`, `shoot`, `fire_arrow` | Instant, no root, no lunge, no slowdown (except the bow draw at x0.5). Facing snaps to the swing. |
| Casting | `PlayerController.cast_spell` -> `Hero.try_cast` | **No effect on movement.** A cosmetic cast pose. A cast lands about 0.15 s after the speaker stops (`voice-mechanic.md`; the north star budgets 0.3-0.6 s), and online casts land `NetCasts.LEAD` (0.2 s) later still. The spoken phrase itself takes about 0.5 s. |
| Defence | none | No dodge, dash, block or sprint (`combat-variety-research.md` §1). |
| Being moved | `Actor.shove` | A 0.2-0.35 s ease-out slide; no steering while it runs; slams, falls, the pit/lava pull-back. |
| Walk animation | `LowPolyModel._process`, each model's `apply_idle` | Stride phase is `sin(t * k)` (**driven by time, not distance**). The amplitude follows a smoothed speed (lerp 10/s). |
| Camera | `CameraRig` | Orthographic, yaw 45°, pitch -56°, view 24 u tall. Follows with a lerp at 7/s. No look-ahead. Shake only. |
| Feedback | `Fx`, `Sfx`, `Wading` | Dust only on shoves, slams and landings from a shove. Footsteps only while wading (`wade_step`). No dry footsteps, no start/stop/turn dust. No hit-stop. |
| Timing | `project.godot` | Physics at the default 60 Hz, **physics interpolation off**. The local hero moves in `_physics_process`; puppets (`NetSnapshot._show_puppets`) and the camera move in `_process`. |
| AI allies | `AllyBrain` | The same `move()` at the same 4.5 u/s. Start walking at 1.6 u from the slot, stop at 0.6. **No catch-up speed** (employees have one: 5.2). |

### 1.2 Measured
| Test | Result |
|---|---|
| Start (0 -> full speed) | **1 frame (16 ms)**: 0 then 4.50 u/s. |
| Stop | **1 frame**: 4.50 then 0. |
| 180° reversal | **1 frame**: +4.50 to -4.50, no skid. |
| Facing | The `facing` var flips in 1 frame. The drawn body turns 180° to within 5° in **11 frames (0.18 s)**. |
| Walk blend (Wick's model) | Legs reach 50% stride 0.07 s and 90% 0.25 s **after** the body is already at full speed, so the feet skate at the start. After a stop they keep striding: 50% at 0.08 s, under 10% at 0.27 s, while the body stands still. |
| +1 step | Costs 0.02 s over flat (1.17 s vs 1.15 s for 3 cells). Height eases 0 -> 0.45 -> 0.50 over ~0.2 s, and the body's feet sit inside the step face for about 0.1 s. |
| +2 climb | Costs **0.07 s** (Wick), **0.13 s** (default), **0.20 s** (Gasket) over flat. The 0.35x speed applies only for the 7-15 frames the probe straddles the edge. The README's "climb 2 (slowly)" is barely felt. Height: 0 -> 0.28 -> 0.85 -> 1.0 in 0.3 s: a fast ease, no mantle. |
| 3-level drop (1.5 u) | Height per frame after the edge: 1.15, 0.88, 0.68, 0.52 ... 0.00 in ~0.3 s. **Fastest at the start, slowest at the end**: the reverse of a fall. It reads as being sucked onto the floor. No landing beat on foot. |
| Wall slide, real (midpoint) walls | Speed along the wall = exactly cos(angle): 97% at 15°, 71% at 45°, 50% at 60°, 26% at 75°. No snagging. |
| Wall slide, plain hex walls (arena, labs) | Snags: 58% at 30°, 28% at 45°, **0% at 60° and 75°** (stuck on the zigzag). Real floors cut their walls; the arena does not. |
| Camera | Trails the walking hero by **0.57 u** (behind it), catches up within 0.5 s of a stop. |

### 1.3 What that adds up to
1. **Velocity is a switch.** Start, stop and reversal all take one frame. No acceleration, no deceleration, no skid. It is
   precise, but nothing tells the eye that the body has mass, and every change of direction looks the same.
2. **The body and the legs disagree.** The legs blend in after the body moves and keep striding after it stops. Their
   cadence is fixed in time, so they skate at the 0.5x speeds (water, goo, the bow) and at coffee's 1.6x. Because the
   hero faces the mouse, strafing and backpedalling play the same forward stride, sideways or backwards.
3. **Height changes have no physicality.** Steps and climbs are eased lerps that briefly sink the feet into the ledge.
   Drops start fast and settle slowly, the inverse of gravity. The +2 climb's "slow" is under a fifth of a second.
4. **There is one movement verb.** Walking at a single speed is the whole toolkit. There is no dodge, dash, sprint or
   movement-based attack, so a monster's wind-up has one answer: walk out of it at 4.5 u/s. Swarmers (5.5) and the
   goblin (5.0) are faster than every hero.
5. **The world does not answer your feet.** No footsteps on dry floor, no dust on a start, stop or turn, no landing beat.
6. **The camera only follows.** It trails behind the hero, so slightly less of the room you walk into is on screen than
   the room you left.
7. **Possible judder on fast monitors.** The local hero moves in 60 Hz steps with no interpolation, while the camera and
   the other players' puppets move every rendered frame. On a 120/144 Hz display your own hero is the least smooth
   thing on screen. (Not checked on the user's monitor: open question 1.)
8. **What already works and should stay:** camera-relative input, wall and edge sliding (no snags on real floors), the
   turned tries that walk a hero along a one-wide bridge, the shove slide with its ease-out, wading's 0.75x and its
   splashes, owner authority (your movement never waits for the network), and the instant response itself (the fix is
   to add shape, not delay).

---

## 2. What comparable games do

Few studios publish their movement numbers, so most hard figures below come from wikis and forums. Each is tagged
**[official]** (a developer, patch note or talk), **[press]** or **[wiki/community]**. Nothing citable was found for
Bastion, Tunic, Ravenswatch, V Rising, Synthetik, Archvale or Nuclear Throne.

### 2.1 Games
| Game | What it does with movement | Lesson for Cast |
|---|---|---|
| **Hades** | The dash is the main defence. Zagreus is immune while dashing, but attacking or casting mid-dash ends the immunity for the rest of the dash, so a dash-strike trades safety for damage [wiki]. Supergiant tracks dash invulnerability as its own state and patched a case where it leaked past an attack-cancel [official]. | I-frames that end on an offensive action are the standard trade. |
| **Hades II** | One dash, and holding it sprints. The first Early Access patch made the sprint "innately faster and turning is more responsive", let you "Dash out of many attack recovery animations more reliably", and noted that a faster dash means "very slightly less" invulnerability, so i-frames follow the dash's length [official]. | Even Supergiant's first patch went on turn response and on cancelling attack recovery into the dash. |
| **Enter the Gungeon** | The roll takes about 0.7 s, with immunity for the first half (about 0.35 s). Direction locks at the start: 8 directions on keys, any direction on a stick. The airborne part ignores pits [wiki]. The lead designer compares the i-frames to Dark Souls and says controller aim is assisted so players can focus on moving [official]. | Lock direction, front-load the i-frames, assist aim so the hands can move. |
| **Diablo III (console)** | Blizzard replaced click-to-path with "direct character control and an Evade command on the right analog stick" [official]. Previews put the roll at about 10 yards with no cooldown [press]. A Blizzard developer named the "innate problem" that "Wizards are vulnerable when they're standing still to channel" [official]. | Direct control wants a dodge. Standing still to cast is a known weakness. |
| **Diablo IV** | Evade is on a 5 s cooldown (charges from gear) and repositions with no real i-frames. Kotaku called the result "a sitting duck for over 80 percent of your time in battle" [press, beta era]. | Don't starve the dodge. Prefer charges or a short recharge. |
| **Path of Exile 2** | The roll "can insta-cancel almost any skill", combat is "fundamentally designed around the dodge-roll", and it "does not make you move faster" [official via press]. Players report no i-frames [community]. | A dodge can be pure repositioning if combat is built for it. |
| **Children of Morta** | Dash count is character identity: the father dashes once and waits, the fast kid dashes three times in a row [official]. | Per-hero dashes are a cheap identity knob. |
| **Hyper Light Drifter** | Chain dash: rapid dashes "within certain frames", and three or more add a slide [wiki]. | Rhythm skill for one player. `combat-variety-research.md` already rated it low for Cast. |
| **Death's Door** | The roll gives "brief invincibility", and combat is built around the roll and telegraphed attacks [press]. | Telegraph plus roll is the genre's default loop. |
| **Lost Ark** | Spacebar dodges toward the cursor on a 6-10 s cooldown per class [guides]. | A long cooldown makes it an escape, not a rhythm. |
| **Magicka / Magicka 2** | In Magicka 1 you could not move and cast; Magicka 2 sold "the ability to move and cast spells at the same time" as a headline feature, and slowed beams' turning instead [press, community]. Friendly fire is "at the very core of all Magicka games" [official]. | The closest analog to Cast: let the caster move, and slow the spell rather than the feet. |
| **Helldivers 2** | On default WASD you cannot walk while entering a stratagem, because the code keys are the movement keys; rebinding them to the arrows frees movement [community]. Arrowhead favours caution and teamwork over twitch reflexes [press]. | Cast's voice input doesn't share the movement keys, so the hero can keep moving while casting. That's an edge to keep. |
| **Lara Croft and the Guardian of Light** | Co-op movement is built from each other's tools: the grapple rope becomes a tightrope, spears become ledges [press]. | Movement can be a co-op verb (compare Cast's shoves). |

### 2.2 Craft
- **Swink, *Game Feel*:**
  - It splits feel into input, response, context, polish, metaphor and rules.
  - Mario speeds up and slows down gradually to simulate inertia, and "graded response" (ramping and settling) reads
    as more fluid than on/off.
  - Response within about 100 ms feels immediate.
- **Movement as an envelope (ADSR):** an initial boost, then attack acceleration, max speed and a release, each tuned
  separately. An instant burst feels snappy, a slow ramp feels heavy, and a long release feels slippery (Pomona CS181G).
- **Forgiveness (Celeste, Maddy Thorson):** coyote time, input buffering, corner correction, and a dash that clips a
  ledge pops up onto it. Typical windows are 0.05-0.15 s. Smash Brawl buffers about 10 frames, and a buffer much longer
  feels "sticky".
- **Facing:**
  - The twin-stick convention snaps facing to aim, and players called slow rotation (Weird West) wrong
    [practitioner].
  - Cast already does this: facing is the mouse, and the drawn body catches up in 0.18 s.
- **Thumbstick dead zones (Josh Sutphin):** use a scaled radial dead zone of 0.1-0.2,
  `normalized * (mag - dz) / (1 - dz)`. An axial dead zone snaps to the cardinals, which is worse in an isometric view
  where the cardinals are diagonal on screen.
- **Camera (Itay Keren, "Scroll Back"):**
  - The toolkit includes lerp smoothing, projected focus (lead along velocity), target focus (lead toward aim), dead
    windows that stop a reversal from jerking the view, and position averaging for multiplayer.
  - It is written for side-scrollers. Using it top-down is our inference.
- **Juice (Jonasson and Purho):** easing, squash and stretch, and sound on every change.
- **Hit-stop:** 1-4 frames for light hits, 50-100 ms for heavy ones [practitioner]. Keep it off the mover's own
  locomotion so it never eats input.
- **Arcs (Kyle Pittman, GDC 2016):** derive the arc from its height and time to apex, g = -2h/t², v0 = 2h/t, with
  stronger gravity after the apex.
- **I-frames (critpoints):** i-frames are what let a dodge pass through an attack and prevent forced "checkmate" hits.
  Without them a dodge is only movement, which some designers want on purpose.
- **Animation-driven locomotion:** motion matching (For Honor) is responsive but costs huge mocap sets. Procedural
  animation (Overgrowth) gets far with a few keys and code. Cast's rigid low-poly parts sit in the second camp; see
  `animation-research.md`.
- **Networked movement:**
  - Fiedler's distributed authority (players own what they touch, the host arbitrates, a 100 ms jitter buffer for
    avatars) is the published model closest to Cast's owner authority. Valve's 100 ms remote interpolation is the same
    idea.
  - Cast already does both: the owner simulates, puppets show at about 100 ms with Hermite interpolation, and the victim
    decides hits on its own hero.
- **Accessibility guidelines:** "Do not make precise timing essential to gameplay." Generous buffers and i-frames lower
  the timing bar for players whose attention is split, as a speaking player's is.

### 2.3 Principles for Cast
1. **The first frame moves.** Keep today's instant response; add a short boost-then-ramp rather than a slow start.
2. **Shape the envelope:** a quick start, a short stop and a visible skid on a reversal. Each is tuned on its own and per
   hero.
3. **Face the aim, but let the legs follow the motion.** This is the twin-stick split.
4. **Give the hands a second verb:** a dodge with front-loaded i-frames, charges rather than a long cooldown, and
   direction locked at the start. It cancels attack recovery, and an attack during it ends the immunity.
5. **Never make the voice cost the feet.** Casting stays free to move (Magicka 2, Diablo's channelling problem,
   Helldivers' key clash).
6. **Height and ground have physics and sound:** arcs on steps and drops, a landing beat, footsteps and dust.
7. **The camera leads a little and never jerks.**
8. **Forgiveness:** buffer presses, stop at deadly edges, bend input onto lanes.

---

## 3. Gap analysis for Cast

Ranked by how much each one should change how Cast *feels*, given that:
- **Movement is the hands' main job.** Spells are spoken, so moving, aiming and two attack buttons are everything the
  hands do, moment to moment.
- **It must stay network-friendly.** Owner authority makes anything the owner simulates on its own hero free, while
  anything that touches another owner's actor is a request.
- **The terrain is hexes, ledges, water and lava.**

Size: S is about a day, M a few days, L a week or more.

| # | Gap | Today | Impact | Size | Networking |
|---|---|---|---|---|---|
| 0 | **Check first: 60 Hz movement on a faster monitor** | Own hero steps at 60 Hz with no physics interpolation; camera and puppets are smooth (§1.1) | **High if the monitor is over 60 Hz**, none otherwise | S to try (`physics/common/physics_interpolation` on, then fix whatever teleports or moves in `_process`), M to audit | None. Puppets already move in `_process`, so they would need interpolation off |
| 1 | **No velocity envelope** | Start, stop and reversal in 1 frame (§1.2) | **High.** The single biggest reason a top-down walk reads as "basic": every change of direction looks the same, and nothing has mass | S: a velocity on `Hero` (not `Actor`, so monster tuning is untouched) moved toward the input by start, stop and turn rates | None. Snapshots already carry velocity; puppets' Hermite curves follow any envelope |
| 2 | **The legs disagree with the body** | Time-driven stride; legs lag 0.25 s on start, stride 0.25 s after a stop, skate at 0.5x and 1.6x, and play forward on strafes and backpedals | **High.** The eye reads feet before anything else. Details: `animation-research.md` | S-M: distance-driven stride phase, blend from the real velocity, lower body toward velocity and upper body toward aim | None (cosmetic, from the shown position on every screen) |
| 3 | **One movement verb (no dodge)** | Walking at 4.5 is the only answer to a wind-up; swarmers (5.5) and the goblin (5.0) outrun every hero | **High for play**, medium for feel. Gives the hands a skill while the mouth casts | M | Owner-authoritative by construction: the victim decides hits on its own hero, so an i-frame on my screen is real. Needs a carrier for its state (`NetCodec.HERO_FIELDS` flag) and an `act` event for the puppet's pose |
| 4 | **Height changes without physics** | Steps and climbs are lerps that sink the feet into the ledge; drops fall fastest first; +2 costs 0.07-0.2 s | **Medium-high.** Hex levels are Cast's terrain identity, and every room has them | S-M: a hop arc on +1, a short mantle beat on +2, gravity (24 u/s², the shove's) on drops with a landing squash | Height streams already; puppets interpolate height linearly, so a 0.12 s hop shows as 3-4 samples (fine, or rebuild the arc cosmetically) |
| 5 | **No footfall feedback** | No dry footsteps, no dust on start, stop or turn | **Medium-high.** Cheap and constant, and sound is half of weight | S: a footstep per stride from the stride phase (per floor material), puffs on hard stops, reversals and landings (`GameWorld.fx_rng`) | None (cosmetic, every screen) |
| 6 | **Camera only trails** | 0.57 u behind at a walk, no lead | **Medium.** You see more of the room you walk into, and aiming at range gets easier | S: lead along the smoothed velocity (about 1.2 u) plus a little toward the aim, eased so reversals don't jerk | None (local) |
| 7 | **Keyboard 8 ways on hex lanes; no gamepad** | WASD directions are 15° off 2 of the 3 hex lane angles, so you hug walls; no joypad actions at all | **Medium.** It matters for anyone on a pad and in every 60° corridor | M: joypad actions with a scaled radial dead zone 0.15 and right-stick aim; for keys, "lane assist" bends input within about 15° onto a nearby wall line or bridge axis | None |
| 8 | **Attacks have no body** | A swing is instant, with no lunge, no slow and no recovery | **Medium.** Attacks feel like they come from the cursor, not the hero | S: a small lunge toward the aim (clamped by `movement_check`, never over an edge) and a brief slow | The lunge is the owner's motion (it streams); the swing's hits are unchanged |
| 9 | **Allies start and stop like switches and can't catch up** | Walk at 1.6 u from the slot, stop at 0.6; no catch-up speed (employees have 5.2) | **Medium-low.** It reads as robotic, and allies string out behind a running leader | S: the envelope from gap 1, an arrival slowdown, and about 1.15x speed when far behind a moving leader | None (host-owned AI) |
| 10 | **No input buffer or edge forgiveness** | Not needed while there is one verb | Low today, **required with a dodge** | S | None (local) |
| 11 | **No hit-stop** | None | Low for movement (a combat-feel item) | S: a per-actor visual freeze only, never global time (it's co-op) | Cosmetic only |
| - | **Not a gap: moving while casting** | Casting never slows or roots you | Keep it. Voice already costs the phrase (about 0.5 s), recognition and the 0.2 s online lead; rooting the caster would punish the game's core verb, and Diablo's "standing still to channel" is a known flaw | - | - |
| - | **Not a gap: facing follows aim** | Facing is the mouse, and the body catches up in 0.18 s | Keep it. It's the twin-stick convention, and slow turning is a known complaint (Weird West). Only the legs should follow the motion (gap 2) | - | - |

**Top five:**
1. The velocity envelope (gap 1).
2. Legs that agree with the body (gap 2).
3. A dodge (gap 3).
4. Height physics (gap 4).
5. Footfall feedback (gap 5).

Gap 0 comes before all of them because it may cost a single setting.

---

## 4. Packages to try

How the numbers are given:
- **Envelope times** are from rest to full speed (start), from full speed to rest (stop) and from full one way to full the
  other (reversal). "Boost" is the share of full speed reached on the first frame, so no package ever has a dead first
  frame.
- **Stop distance** is speed x stop time / 2.
- **Base speed** stays 4.5 unless a package says otherwise.

Every number is **[proposal]**.

### Package A: "Grounded" (polish, no new verbs)
Today's game, with weight and ground under it. Gameplay is unchanged.

| Part | Numbers to try |
|---|---|
| Envelope | Boost 45%, start 0.08 s, stop 0.07 s (0.16 u slide), reversal 0.10 s through zero |
| Legs | Stride phase from distance walked (one full cycle per about 1.6 u at 4.5); blend from the real velocity; lower body turns toward the velocity within ±100° of the aim, and beyond that the stride plays backwards (backpedal). Lean about 6° into acceleration and settle back about 4° on a stop (see `animation-research.md`) |
| Height | **+1 step:** a 0.12 s hop arc with its peak 0.15 u above the step. **+2 climb:** a mantle beat (hands up), with the hero held at the lip for 0.15 s (Wick), 0.25 s (default) or 0.40 s (Gasket) before rising over 0.15 s; this makes "climb 2 (slowly)" true. **Drops:** gravity 24 u/s² (`SHOVE_GRAVITY`) with the walk's horizontal speed carried; a landing squash of 0.08 s; drops of 2+ levels get dust and a thud, and lose 0.1 s of speed (landing recovery) |
| Feedback | A dry footstep per stride, keyed to the floor material (carpet, marble, tile, metal grate, rock; wading keeps its splash). Small dust puffs on a reversal, a hard stop from full speed and a landing |
| Camera | Lead 1.2 u along the velocity, smoothed over about 0.35 s, plus 15% of the way toward the aim, capped at 2 u. The lead eases back on a reversal rather than snapping |
| Allies | The same envelope; an arrival slowdown inside 1 u of the slot; 1.15x speed while more than `FOLLOW_MAX`-equivalent behind a moving leader |
| Keys | Lane assist: within 15° of a wall line or a one-wide bridge axis that the hero is next to, bend the input onto it |

- **Cost:** M overall, in slices:
  - the envelope (S);
  - legs and lean (S-M, shared with the animation work);
  - height arcs (S-M);
  - footsteps and dust (S, plus the sound files);
  - camera lead (S);
  - allies (S);
  - lane assist (S).
- **Networking:**
  - Nothing new travels. The envelope, arcs and lead are the owner's motion or local looks, and snapshots already carry
    position and velocity.
  - Footsteps and dust play on every screen from the shown motion, as wading's splashes already do.
  - The mantle hold is the owner's own motion, so it streams like a walk.
- **Risks:**
  - Any envelope adds a little effective latency. The boost keeps the first frame live, and 0.08 s stays under the
    ~100 ms "immediate" line.
  - The stop slide must never carry a hero off an edge. It can't: every step still goes through `movement_check`, which
    refuses lava and void on foot.
  - `test_hero_move` allows 0.4 u on its 1 s walk, and the start costs about 0.1 u.

### Package B: "Snappy + dodge"
A tighter A, plus the second verb.

| Part | Numbers to try |
|---|---|
| Envelope | Boost 60%, start 0.05 s, stop 0.05 s (0.11 u), reversal 0.07 s. The rest of A unchanged |
| Dodge | Space (and the pad's south button). Direction is the movement input, else away from the aim; locked once started. **2.6 u** (1.5 hexes) over **0.22 s**, ease-out like the shove slide. **I-frames from frame 1 to 0.16 s.** Then a 0.08 s recovery at 50% walk speed. **2 charges**, each recharging in 1.6 s (not one long cooldown: D4's "sitting duck") |
| Cancels | A dodge cancels melee and shot recovery and a bow draw. An attack during the dodge ends its i-frames (the Hades trade). A **voice cast never interrupts it and never ends the i-frames**: the mouth is not the hands, and recognition timing can't be aimed anyway |
| Buffer | A dodge or attack pressed up to 0.12 s early fires as soon as it's allowed |
| Terrain | The dodge follows the walking rules: +1 steps (with A's hop), stops at a +2 climb or a wall (sliding along it like a walk), drops up to 3 levels as a hop with gravity. It **stops at the lip of lava or a pit**, so a dodge never kills; the opposite of Gungeon's pit-proof roll, chosen for "chaos costs score, never the run" |
| What i-frames ignore | Damage, shoves and dazes from **everything**, teammates' corn and spins included ("dodge the corn" is a skill and a joke). Heals, armor, coffee and soaks still land: a dodge never refuses help |

- **Cost:** M for the dodge (plus A's pieces it reuses), counted with B's envelope.
- **Networking:**
  - The dodge is an owned action.
  - The owner runs it like a self-made shove slide (`Actor`'s forced-move machinery, a new kind that steers nothing).
  - The owner applies the i-frames, because every hit on a hero is already decided by its owner (`Net.resolves_hit`),
    and so is a monster's strike on it (`Monster.net_strike`).
  - New vars: an `OWNER` `_dodge_until` streamed as a snapshot flag (`NetCodec.HERO_FIELDS`), plus the rest
    `PRIVATE` (charges, recharge).
  - A `Net.hero_acted(self, "dodge", dir)` event plays the roll pose and dust on puppets.
  - A late joiner needs nothing: a dodge lasts 0.22 s, and the next snapshot carries the flag.
  - What others see: the puppet is 0.1-0.2 s behind, so a teammate can see a swing "pass through" a dodging friend.
    That's acceptable and readable, because the roll pose shows it.
  - Telemetry: dodges per player per minute (`Net.note_*`, passive).
- **Risks:**
  - **Balance.** Damage taken drops, which moves the 3-star "damage taken" thresholds. Fast wind-ups (swarmer 0.3 s,
    grunt 0.35 s) become dodgeable reflex checks, which is the intent of `combat-variety-research.md`'s "reflex tier".
  - **AI allies don't dodge** in v1, so the AI looks worse beside players. A later step: dodge on a wind-up aimed at
    them, after the restraint reaction delay.
  - **Space must stay free.** In play it is unbound today (only the invoice screen reads it), and it must not later
    become push-to-talk (`voice-mechanic.md`, "Push-to-talk options").
  - **The mic:** hands and voice are separate channels, so the only cross-talk is acoustic: a hammered Space bar is a
    loud click right by a desk mic. Check that `SpeechGate` drops it and that it never makes a phantom.

### Package C: "Weighty commitment"
The contrast profile: mass and commitment, with no dodge.

| Part | Numbers to try |
|---|---|
| Envelope | Boost 25%, start 0.18 s, stop 0.14 s (0.32 u), reversal 0.22 s; the walking direction itself turns at most 540°/s (the body arcs instead of snapping) |
| Per hero | Wick 4.8 u/s with a 0.10 s start; Gasket 4.4 with 0.18 s; Rebar 4.0 with 0.28 s start and 0.20 s stop |
| Attacks | Melee lunges 0.4 u toward the aim over 0.10 s (clamped at edges) and walks at 40% for the swing's 0.15 s active part (Rebar 0.25 s). The bow is unchanged |
| Casting | Still free (see the "not a gap" row) |
| The rest | A's legs, height, feedback and camera |

- **Cost:** S on top of A (mostly numbers, plus the lunge).
- **Networking:** none new; the lunge is the owner's motion.
- **Risks:**
  - On top of voice's built-in delay, a slow envelope makes the whole game feel late.
  - The turn limit makes 8-way keys draw arcs near lava edges. The edges still refuse the step, but players will feel
    "the game moved me".
  - Per-hero speeds change who can outrun what.
- **Why try it at all:** it brackets the envelope. If A feels a little floaty and C feels mud, the answer lies between
  them, and the user can see that in a minute.

### Package D: "Crew kits" (builds on B)
Per-hero movement verbs, as in `combat-variety-research.md` idea 9:
- **Wick rolls.** B's dodge, with 3 charges.
- **Gasket barges.** A 2.0 u shoulder charge with no i-frames that shoves monsters in her path (`Combat.shove_radius`
  along the path); 3 s recharge.
- **Rebar braces.** Hold Space: he stands still, takes 50% damage, and nearby monsters switch to him (a taunt), which
  makes the tank a choice.

Speeds as in C.
- **Cost:** L.
- **Networking:**
  - The barge's hits on monsters are the owner's hits on host actors, so they travel as requests (`Net.route_hit`, as
    melee does today).
  - The brace is a modifier the owner announces (`NetStatus`) plus host-side targeting.
- **Risks:**
  - It is a design commitment per hero.
  - Rebar's verb isn't movement.
  - It should wait until B shows whether a dodge belongs in Cast at all.

### Package E: "Hands" (input quality, cross-cutting)
- **Gamepad actions:**
  - left stick to move, with a scaled radial dead zone of 0.15 and a 1.5 response curve;
  - right stick to aim, with the reticle at stick deflection x spell range and the existing 1.3 u teammate snap as the
    aim assist;
  - triggers to attack, the south button to dodge (B), the d-pad for slots 1-4.
- **Lane assist for keys** (also in A).
- **The 0.12 s buffer** (also in B).
- **Cost:** M.
- **Networking:** none.
- **Risk:** UI forms and menus also need pad navigation (`form-rules.md`). The game already accepts
  `InputEventJoypadButton` in two places, but nothing maps it.

---

## 5. Recommendation and how to try them side by side

### 5.1 Recommendation [proposal]
1. **First, an hour:** find out whether the user's monitor runs above 60 Hz, and try physics interpolation (gap 0). If
   the hero judders today, nothing else will feel right until that's fixed, and it may be one setting plus a few
   `reset_physics_interpolation()` calls.
2. **Prototype A first.** It answers "too basic but not sure what is missing" most directly: most of what reads as
   basic is the one-frame velocity, the skating legs, the flat height changes, the silent floor and the trailing camera.
   None of those changes balance or networking, and every piece survives whichever way the dodge question goes.
3. **Prototype B's dodge in the same lab, as a toggle on top of A.** It's the largest gameplay change and the one with a
   balance cost, so the user should feel it before deciding. Owner authority makes it lag-free, and the research (Hades,
   Gungeon, Diablo III console, PoE2) says a direct-control action game wants a second verb on the hands.
4. **Keep C as a calibration profile only.** It shows where the envelope sits; it isn't meant to ship.
5. **D waits for a yes on B. E's gamepad half waits for a yes to "do you play on a pad?"**, but lane assist and the
   buffer ride along with A and B.

### 5.2 Trying them side by side [proposal]
- **One data table, like `HeroKit`:** `MoveFeel` (`scripts/heroes/move_feel.gd`, a `RefCounted` with a `const` table)
  holds profiles `today`, `grounded` (A), `snappy` (B), `weighty` (C) and `kits` (D, later). Every number in §4 is a
  key, and `Hero` reads its profile, so `today` reproduces the current game exactly and is the default until the user
  picks one.
- **A dev flag:** `--move-feel today|grounded|snappy|weighty`.
  - Solo, it applies to every hero.
  - In a crew, the **host's** flag wins. The profile goes out with the run like the seed (a `SPAWN` value), because a
    dodge and its i-frames are gameplay and every machine must agree on them. Every window gets the flag anyway, as with
    `--sewer`.
  - This follows `networking.md`'s new-content checklist: the profile is spawn data, and the dodge is an owned action.
- **A movement lab:** `--move-lab` on the existing arena (`scenes/arena.tscn`), with a course laid out for feel:
  - a slalom of pillars;
  - a one-wide bridge at 60° over lava (lane assist, edge stops);
  - a +1 stair run and a +2 ledge wall (hop and mantle);
  - a 3-level drop (gravity and landing);
  - a wading pool (the 0.75x stride);
  - a cut-wall corridor at 60° (wall slide);
  - a grunt and a swarmer behind a gate, for wind-ups and the dodge.
  - **F6 cycles the profile live.** A small dev label names it; this is the arena, not a form, so `form-rules.md`
    doesn't apply.
- **Blind A/B:** `--move-feel shuffle` gives the profiles in a random order as "1", "2" and "3", with no names, so the
  user rates by feel and not by label. The mapping is printed to the log on quit.
- **Passive numbers, no questions mid-play** (the user's data rule):
  - the lab logs, per profile, lap time through the course, hits taken from the grunt and swarmer, edge stops, and
    dodges used;
  - they go to `user://move_lab.csv`, beside the existing telemetry.
- **Crew check:** `.\run.ps1 -Crew 2 --move-lab --move-feel snappy` shows how a teammate's dodge and envelope read
  on a puppet 0.1-0.2 s behind.
- **Order of work:**
  1. The `MoveFeel` table, the `today` profile and the flag, with `test_hero_move` passing unchanged.
  2. The envelope.
  3. Legs and lean (shared with the animation work).
  4. Height arcs.
  5. Footsteps and dust.
  6. Camera lead.
  7. The dodge.
  8. The lab course.

  Each is a separate commit with its own test: the envelope's start and stop distances, an arc's apex height, the
  dodge's i-frame window, the edge stop, and two peers where a monster strike on a dodging client's hero does no
  damage.

### 5.3 As built: package A "grounded" as an A/B profile (2026-10-21)

The user (2026-10-21): "Let's try the package A grounded. Preferably so I can A/B." Built: the profile table, package A, the
judder check, the lab, the log and the tests. **`today` is still the default**: nothing changes for normal play until the
user picks.

#### How to A/B
| Command | What it does |
|---|---|
| `.\run.ps1 --move-lab --move-feel shuffle --no-mic` | The lab (below), with `today` and `grounded` dealt in a random order as **"feel 1" / "feel 2"**. The tag says only the number; which is which is printed to the console and written in every log row. |
| `.\run.ps1 --move-lab --move-feel grounded --no-mic` | The lab, profiles named. `today` is the default. |
| **F6** | The next profile (the tag in the lower left names it, or its number when blind, for about 2 s). In a crew it does nothing (the tag says "set by the host"). |
| **F7** | Physics interpolation of your own heroes on / off (the judder check). `--physics-interp on` starts with it on. |
| `.\run.ps1 --seed 7 --contract 0 --spells heal,corn --move-feel grounded` | Any real floor (F6 / F7 work there too, and in the arena, `--scene res://scenes/arena.tscn`). |
| `.\run.ps1 -Crew 2 --net-wait 2 --move-lab --move-feel grounded` | Two windows: how a teammate's grounded walk reads on a puppet. |

The flags work in any order; MoveFeel reads them once per run (`Boot`, the game and the arena call `MoveFeel.boot`).

#### What was built
| Piece | Where | What |
|---|---|---|
| The table | `scripts/heroes/move_feel.gd` (`MoveFeel`) | Profiles `today` (every key at its "off" value: the old code paths run) and `grounded`. The flag, F6's cycle, shuffle, the crew rule. Every hero, the camera and the AI read the active profile here. |
| The walk | `scripts/heroes/hero_motion.gd` (`HeroMotion`), `Hero.move` | The envelope, the hop, the mantle, gravity. On the machine that moves the hero only. `today`: `Hero.move` is the old walk. |
| The feet | `scripts/heroes/hero_gait.gd` (`HeroGait`) on `scripts/art/lowpoly/gait.gd` (`Gait`) | Stride and legs, footsteps, dust, the big landing. Every screen, from the shown motion. |
| Camera | `CameraRig._lead` | The lead. |
| Allies | `AllyBrain._follow`, `_move_toward` | The arrival slowdown and the catch-up (`Hero.pace`). |
| Judder | `Hero._interp_show` / `_interp_restore` | F7 (below). |
| Lab | `scripts/heroes/move_lab.gd` (`MoveLab`), `--move-lab` | The course, as floor 1 of a contract. |
| Tag, keys, log | `scripts/heroes/move_feel_tag.gd`, `scripts/heroes/move_log.gd` | F6 / F7, the tag, `user://move_lab.csv`. |

**The stride is shared with the animation track.** `animation-research.md`'s lab (`anim_lab_feel.gd`, level 1) already had
a stride matched to the ground and legs turned toward the travel. That logic now lives in `Gait`, and both the lab's lane B
and this profile run it, so the animation work layers on top of it rather than fighting it. Its **lean, squash, landing
squash, strike-first and hit-stop are left to the animation track** (the coordinator's call); so the doc's "lean about 6°
into acceleration" and "a landing squash of 0.08 s" are not in package A.

#### The grounded numbers (measured: `test_move_feel_grounded`, 60 Hz)
| Part | Doc's starting point | As built (measured) |
|---|---|---|
| Start | boost 45%, 0.08 s | First frame 2.02 u/s (45% of 4.5), full speed on frame 6 (**0.083 s**). Top speed unchanged (4.50). |
| Stop | 0.07 s, 0.16 u | **0.067 s** (4 frames), slide **0.12 u** (the doc's 0.16 is the continuous formula; in 60 Hz steps it is 0.12). |
| Reversal | 0.10 s through zero | **0.10 s** (6 frames). Any turn of more than 60° and any speed change while walking (coffee, water) use the same rate: a 90° WASD turn takes 0.07 s. |
| Hop (+1) | 0.12 s, peak 0.15 above the step | 0.12 s, peak **0.149** above the step. Starts `HOP_LEAD` (0.04 s of walking plus half a radius) before the edge, so the feet never sink into the face (deepest 0.000 past the edge; today: about 0.1 s inside it). Stairs are walked as before. |
| Mantle (+2) | held 0.15 / 0.25 / 0.40 s, rise 0.15 s | Held **0.15 s** (Wick), **0.27** (default), **0.42** (Gasket), then a 0.15 s rise. A +2 now costs **0.26 / 0.37 / 0.52 s** over flat (today 0.07 / 0.13 / 0.20). Letting go or turning away during the hold cancels it. Rebar still can't climb. `climbing` is set for the mantle (it streams). |
| Drops | gravity 24 u/s², the walk carried | A 3-level drop falls **0.35 s** (21 frames), speeding up every frame (0.007, 0.013 ... 0.133 u a frame; today: fastest first). A landing from 2+ levels keeps **40%** of the speed and ramps back over `start` (about 0.09 s of lost speed). |
| Edges | the stop slide never goes over | Held: every step still goes through `Actor.move`, so lava and pits refuse it (`test_move_feel_grounded`, the edge case; `test_move_lab`, the bridge). |
| Casting | free | Unchanged: no root, no slow while speaking (tested). |
| Stride | from distance, legs match the body | The planted foot's sweep over the ground speed (1.00 = no skating; the animation doc's measure): walk **0.98**, coffee **0.97**, bow drawn **0.97**, strafe **1.05** (today: Wick 1.08 / 0.67 / 1.22 / 0.00; Gasket 0.45 at a walk). The stride pauses while shoved. |
| Footsteps | a dry step per stride on the floor's material | One per foot plant (`Gait.plants`) on `step_hard` (concrete, slate, tile, marble, stone, basalt), `step_soft` (carpet, rubber), `step_wood`, `step_metal` (diamond plate); none in pool water (Wading's splash). At -27 dB, heard within about 26 units. A legless prototype body steps every 1.1 units. |
| Dust | on a reversal, a hard stop, a landing | Small puffs on a start (kicked back), a stop from 3.5 u/s or more, a turn of 75° or more and a 2+ level landing (with a ring and `land_thud`), at least 0.35 s apart. |
| Camera | lead 1.2 u, smoothed 0.35 s, +15% toward the aim, max 2 | As the doc. |
| Allies | the envelope, slow inside 1 u of the slot, x1.15 when far behind | As the doc: the slowdown never below 35% of full speed; the catch-up while more than 3.2 u from the slot behind a walking leader. |
| Lane assist | within 15° of a wall line or a bridge axis | **Not built** (it is input bending, not feel, and needs its own A/B: open question below). |

A lap of the lab on foot (`test_move_lab`, the path the map's own pathing takes, through the pool): today **23.9 s**,
grounded **24.2 s** (the mantle's hold and the landing recovery).

#### The judder check (gap 0)
`probe_move_judder` (not in the suite: `Godot --path . --headless --fixed-fps <hz> -- --run-test probe_move_judder`) walks a
hero at full speed and reads, every rendered frame, where it is drawn and where the camera is:

| Refresh | F7 off: frames the hero does not move | off: jump against the camera | F7 on: frames still | on: jump |
|---|---|---|---|---|
| 60 Hz | 0 of 240 | 0.9 px | 0 | 0.9 px (identical) |
| 120 Hz | **120 of 240** | **2.1 px** | 0 | 0.5 px |
| 144 Hz | **140 of 240** | **1.9 px** | 0 | 0.4 px |
| 165 Hz | **152 of 240** | **2.1 px** | 0 | 0.3 px |

So on a 60 Hz monitor interpolation changes nothing (it only adds one physics tick, 16 ms, of drawing delay). On a 120-165 Hz
monitor, with it off, your own hero stands still on half or more of the frames and steps about 2 px against the smoothly
following camera every tick: a fine, constant stutter. With it on, the steps are perfectly even. **It is not the default**
(the user decides, after trying F7 on their own monitor; question 1 below).

How it works: not Godot's global `physics_interpolation` (a lot of the game moves things in `_process`: puppets, the camera,
the models' parts, Fx). Instead a hero this machine moves is drawn between its last two physics positions
(`Engine.get_physics_interpolation_fraction()`) and its true position is put back at the start of every physics tick
(`SceneTree.physics_frame`), before anything simulates; a position something else set in between (a teleport, an arrival) is
kept. Monsters and puppets are unchanged (puppets already move every frame). `test_move_feel_grounded` holds that it never
changes where the hero really is.

#### Networking
- **Nothing new on the wire.** The envelope, hops, mantle and falls are the owner's motion and stream as a walk; the mantle
  sets the already-streamed `climbing` flag. Puppets get their stride, footsteps, dust and landing thud on every screen from
  the shown motion (`HeroGait`, like Wading's splashes). The snapshots keep their size (`test_net_move_feel`).
- **The host's profile is everyone's.** It rides the job (`crew.job` gets `feel: {id, blind}`; a late joiner gets the job
  too), as §5.2 recommends: a puppet's stride, hop and landing are drawn with the profile THAT screen has, so the crew must
  agree; an A/B in a crew should compare like with like; and a later profile with a dodge is gameplay every machine must
  agree on. F6 is off while crewed. Interpolation (F7) is each machine's own: it only changes how that screen draws its own
  heroes.
- Declared per AGENTS.md: `Hero.pace` and `_motion` PRIVATE, `_gait` and the interpolation state LOCAL; `HeroMotion` is in
  `test_net_contract`'s `NET_SCRIPTS` (all PRIVATE); `HeroGait` declares its LOCAL vars. No allowlist was widened.

#### What is logged
`user://move_lab.csv` (`%APPDATA%\Godot\app_userdata\Cast\move_lab.csv`), passive, never in tests: one **period** row per
stretch played on one profile (closed by F6 / F7 or leaving the floor) and, in the lab, one **lap** row per START-to-FINISH.
Columns: time, session, scene (lab | floor), mode (today | grounded | shuffle), label (what the tag showed), profile (the real
one), interp, event, seconds, distance, laps, lap_s (the lap, or the period's best), hits and damage taken, edge_stops (walking
stopped at a pit's or the lava's edge), starts, stops, reversals, refresh_hz (the monitor's) and fps.

#### The lab (`--move-lab`)
A hand-built floor played as floor 1 (like `--lava-cave`: the HUD, voice, AI allies and crews all work), west to east: the
start pad, a slalom of three pillars, a +1 stair run up three levels, a 3-level drop, a +2 ledge (and a 2-level drop off it),
a one-wide bridge at 60° over lava, a wading pool, a cut-wall corridor at 60°, and the finish pad with a grunt and a swarmer
in a pen whose gap is the gate. Floors are concrete, carpet, wood, marble, tile, flagstone, pool tile and diamond plate, so
every footstep is heard. `--move-lab` alone goes straight in (heal and damp signed). The lap runs from the start pad to the
finish pad.

#### Tests
`test_move_feel_today` (today against a trace recorded before any profile existed: every frame of a course with steps, a
climb, a reversal, a wall push, the lava edge, wading, coffee, the bow and a drop, the player and an AI ally),
`test_move_feel_grounded` (the numbers above, the profiles, shuffle and the log), `test_move_lab` (the course and a lap per
profile) and `test_net_move_feel` (two processes on the lab, `off` and `coast`).

#### Open questions (added)
- Which feels better, blind? (The CSV keeps the laps per profile; the user's feel is the answer.)
- The stop slide is 0.12 u at 60 Hz. Longer (`stop` 0.09 gives 0.17 u)?
- Lane assist for keys (package A's last row) was not built: try it as its own toggle?
- The lean and landing squash are the animation track's: try them on top of grounded next?

---

## 6. Open questions for the user

1. **What refresh rate is your monitor?** If it's over 60 Hz, gap 0 may be part of what feels off.
2. **Do you, or your playtesters, play on a controller?** No gamepad bindings exist today.
3. **A dodge at all?** If yes:
   - with i-frames, or pure repositioning (PoE2, Diablo IV)?
   - Space or Shift?
   - one shared dodge, or per-hero verbs (Package D)?
4. **Can a dodge pass through a teammate's spell** (dodge the corn), or only monsters' attacks?
5. **Should a dodge ever carry you over lava or a pit,** or always stop at the lip (the proposal)?
6. **Casting stays free to move (the recommendation).** Agreed, or should big spells plant your feet?
7. **Should attacks commit** (a small lunge and slow, Package C), or stay free as now?
8. **Should +2 climbs really be slow** (the README says so; today they cost 0.07-0.2 s), with a visible mantle?
9. **Different speeds per hero?** Today everyone walks at 4.5.
10. **Camera lead:** along your movement, toward your aim, or none?
11. **Should AI allies dodge too,** if heroes get one?

---

## 7. Sources

Tags: [official] developer, patch note or talk; [press] journalism or hands-on; [wiki/community] fan measurement or forum.

| Source | Used for |
|---|---|
| [Hades wiki, Unblockable](https://hades.fandom.com/wiki/Unblockable) [wiki] | Dash immunity; attacking mid-dash ends it |
| [Supergiant, Hades "Blood Price" patch notes](https://www.supergiantgames.com/blog/hades-the-blood-price-update-patch-notes-pt-1) [official] | Dash invulnerability tracked as its own state |
| [PC Gamer, Hades tips](https://pcgamer.com/hades-guide-tips-and-tricks) [press]; [Steam thread](https://steamcommunity.com/app/1145360/discussions/0/5185299686162074064) [community] | Dash i-frames, Athena's extension |
| [Shacknews, Hades II Early Access patch 1](https://www.shacknews.com/article/139921/hades-2-early-access-patch-notes-1) [official notes] | Turn responsiveness, dash out of recovery, i-frames follow dash length |
| [Nintendo Life, Hades II hands-on](https://www.nintendolife.com/features/hands-on-hades-2-is-a-hell-of-a-time-even-in-early-access); [Aftermath](https://aftermath.site/supergiant-hades-2-dash-chronos-difficulty/) [press] | One dash, hold to sprint |
| [Gungeon wiki, Dodge Roll](https://enterthegungeon.wiki.gg/wiki/Dodge_Roll_(Move)) [wiki]; [Steam thread](https://steamcommunity.com/app/311690/discussions/0/368542585858479737) [community] | Roll length, i-frame window, locked direction, pits |
| [Windows Central, Gungeon interview](https://www.windowscentral.com/enter-gungeon-interview); [GameRevolution](https://www.gamerevolution.com/originals/463743-enter-the-gungeon-developer-what-makes-good-roguelike-interview) [official interview] | I-frames by design; assisted controller aim |
| [PlayStation Blog, Diablo III on PlayStation](https://blog.playstation.com/2013/07/01/diablo-iii-on-playstation-hand-crafted-for-consoles/comment-page-2) [official] | Direct control and evade on console |
| [Game Informer, D3 console](https://gameinformer.com/b/news/archive/2013/03/22/diablo-iii-ps3-pax.aspx); [Engadget 2013](https://www.engadget.com/2013-05-16-diablo-iii-devs-talk-about-creating-console-controls.html); [Engadget 2011](https://www.engadget.com/2011-09-22-diablo-3-feels-even-better-with-console-controllers-but-suppo.html) [press/official quotes] | Console roll, "feels even better with direct control" |
| [Softpedia, D3 wizards](https://games.softpedia.com/blog/Blizzard-Plans-Changes-to-Diablo-3-s-Wizards-Arcane-Orb-Evaluated-328625.shtml) [official quote] | "Vulnerable when they're standing still to channel" |
| [Prima, Diablo IV evade](https://primagames.com/tips/how-to-dodge-and-evade-in-diablo-4); [Kotaku, D4 dodge](https://kotaku.com/diablo-4-iv-beta-dodge-roll-controversy-world-boss-1850245274) [press] | 5 s evade; "sitting duck" |
| [Massively OP, PoE2 dodge roll](https://massivelyop.com/2023/07/28/exilecon-2023-path-of-exile-2-introduces-dodge-rolling-and-instant-weapon-skill-swapping/); [Maxroll, Rogers interview](https://maxroll.gg/poe/news/pax-west-path-of-exile-2-interview-with-jonathan-rogers) [official via press]; [Steam thread](https://steamcommunity.com/app/2694490/discussions/0/596260925367943771) [community] | Roll cancels skills; no extra speed; no i-frames |
| [Xbox Wire, Children of Morta](https://news.xbox.com/en-us/2019/09/20/family-personalities-character-classes-children-of-morta/) [official] | Dash count per character |
| [HLD wiki, Abilities](https://hyperlightdrifter.fandom.com/wiki/Abilities_and_Upgrades) [wiki] | Chain dash |
| [Nintendo World Report, Death's Door](https://www.nintendoworldreport.com/review/59014/deaths-door-switch-review) [press] | Roll with brief invincibility |
| [Pro Game Guides, Lost Ark movement skill](https://progameguides.com/lost-ark/how-to-dodge-in-lost-ark-movement-skill-explained/) [guide] | 6-10 s dodge cooldowns |
| [Game Informer, Transistor interview](https://gameinformer.com/games/transistor/b/pc/archive/2014/02/20/transistor-interview-supergiant-greg-kasavin) [official] | Turn() and dodging while it refills |
| [PCGamesN, Magicka 2 hands-on](https://www.pcgamesn.com/magicka-2/hands-on-with-magicka-2) [press]; [Steam thread](https://steamcommunity.com/app/238370/discussions/0/615086038676417453) [community]; [Shacknews, co-op Magicka 2](https://www.shacknews.com/article/89792/co-optimized-magicka-2) [press] | Moving while casting; slow beam turning; pad vs mouse |
| [ESL, Nisshagen interview](https://esl.com/article/id-rather-reward-good-teamplay-than-nerf-it-for-the-sake-of-balance-an-interview-with-magicka-wizard-wars-david-nisshagen/) [official] | Friendly fire at Magicka's core |
| [Steam, Helldivers 2 stratagem movement](https://steamcommunity.com/app/553850/discussions/0/4206994256762464867) [community]; [FandomWire, Warp Pack](https://fandomwire.com/arrowhead-mightve-quietly-slipped-i-frames-into-helldivers-2-with-this-game-breaking-stratagem/) [press]; [Helldivers 1 wiki](https://helldivers.wiki.gg/wiki/Helldivers_1:Encyclopedia) [wiki] | Stratagem input vs walking; no i-frames ethos |
| [Engadget, Guardian of Light](https://www.engadget.com/2010-05-18-hands-on-lara-croft-and-the-guardian-of-light.html); [Co-Optimus](https://www.co-optimus.com/review/542/page/2/lara-croft-and-the-guardian-of-light-co-op-review.html) [press] | Movement built from each other's tools |
| [Swink, "Game Feel: the secret ingredient"](https://www.gamedeveloper.com/design/game-feel-the-secret-ingredient); [Bayreuth GxD lecture](https://medienwissenschaft.uni-bayreuth.de/wp-content/uploads/GxD-07-Interfaces.pdf); ["Principles of virtual sensation"](https://www.gamedeveloper.com/design/principles-of-virtual-sensation) | Six areas of feel; ~100 ms response; graded response |
| [Pomona CS181G, movement notes](https://cs.pomona.edu/classes/cs181g/notes/movement.html) | Movement as an ADSR envelope |
| [Maddy Thorson, Celeste forgiveness thread](https://threadreaderapp.com/thread/1238338574220546049.html); [bugnet, coyote time](https://bugnet.io/blog/coyote-time-and-input-buffering-explained); [WPI DGMI wiki](https://dgmiwiki.wpi.edu/mechanic/coyote_time) | Coyote time, buffering, corner correction, window sizes |
| [Wayline, input buffering](https://www.wayline.io/blog/art-of-input-buffering); [SmashWiki, Buffer](https://www.ssbwiki.com/Buffer) | Buffer windows; "sticky" when too long |
| [Josh Sutphin, "Doing thumbstick dead zones right"](https://www.gamedeveloper.com/disciplines/doing-thumbstick-dead-zones-right) | Scaled radial dead zone, 0.1-0.2 |
| [Itay Keren, "Scroll back"](https://www.gamedeveloper.com/design/scroll-back-the-theory-and-practice-of-cameras-in-side-scrollers) | Camera lead, windows, multiplayer framing |
| [Jonasson and Purho, "Juice it or lose it" (summary)](https://rpgplayground.com/research-making-a-juicy-game/) | Easing, squash and stretch |
| [Lin et al. 2022, impact features](https://faculty.washington.edu/zkwen/articles/lin22features.pdf); [uhiyama-lab, hit feedback](https://uhiyama-lab.com/en/notes/unity/unity-game-feel-hit-feedback/) [practitioner] | Hit-stop sizes and effect |
| [Pittman, "Building a better jump" (GDC Vault)](https://gdcvault.com/play/1023148/Math-for-Game-Programmers-Building); [recap](https://blogs.jccc.edu/dpatter/2016/03/15) | Arcs from height and time to apex |
| [critpoints, "How i-frames augment dodge rolls"](https://critpoints.net/2017/07/25/how-iframes-augment-dodge-rolls/); [itch.io post](https://itch.io/post/10414174) | What i-frames add; a no-i-frame counterpoint |
| [TopDown Engine, CharacterOrientation3D](https://topdown-engine-docs.moremountains.com/API/class_more_mountains_1_1_top_down_engine_1_1_character_orientation3_d.html); [forum thread](https://links.hackliberty.org/post/1999785/3584237) [practitioner] | Instant vs smooth facing; slow-rotation complaints |
| [Clavet, Motion Matching (GDC Vault)](https://gdcvault.com/play/1023280/Motion-Matching-and-The-Road); [Rosen, procedural animation](https://www.gamedeveloper.com/design/video-an-indie-approach-to-procedural-animation) | Animation-driven vs procedural locomotion |
| [Fiedler, networked physics in VR](https://gafferongames.com/post/networked_physics_in_virtual_reality/); [Valve, Source multiplayer networking](https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking); [Edgegap, Overwatch netcode](https://edgegap.com/blog/game-backend-deep-dive-overwatch-2016-netcode-architecture-rollback) | Distributed authority, 100 ms interpolation, ability prediction |
| [Game Accessibility Guidelines, timing](https://gameaccessibilityguidelines.com/do-not-make-precise-timing-essential-to-gameplay-offer-alternatives-actions-that-can-be-carried-out-while-paused-or-a-skip-mechanism/) | Don't make precise timing essential |

Not reached: Nijman's "The Art of Screenshake", the Game Maker's Toolkit dodge-roll video and Swink's book pages. No
source covered i-frames in voice-controlled or co-op games specifically.
