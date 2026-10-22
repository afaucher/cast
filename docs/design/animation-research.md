# Hero animation feel: research, diagnosis and look-dev

Status: **[research]**, 2026-10-21. **2026-10-22: treatment B and strike-first are built into the game as the A/B profile
`grounded_anim`, with each hero's hit area reshaped to its weapon; see "As built" (section 7.1).** The rest is not built or decided. The user asked: "Lets look at a parallel
topic of how to animate our main characters to have better feel - so it feels like you are really controlling them."
This doc covers ANIMATION: how the heroes' bodies respond to what the player does. Movement itself (speed curves, dodge,
sprint, camera) is in `docs/design/movement-research.md`, written by a parallel agent; section 6 says where the two meet.
Every **[proposal]** is cosmetic. It is derived on each screen from state every screen already has, so it adds no net
traffic (`AGENTS.md`, shape 4 "cosmetic").

Mocks: `scenes/anim_lab.tscn` (`scripts/art/lowpoly/anim_lab.gd`, `scripts/art/lowpoly/anim_lab_feel.gd`) and the
pictures in `docs/design/animation/` (section 5). They are lab-only and touch no gameplay code.

---

## 0. Summary

- **Today the bodies are clocks, not reactions.** Each model's `apply_idle(t, speed)` plays sines on a fixed timer. Speed
  only scales the stride's size. Nothing else about the motion reaches the body: no acceleration, no direction of travel,
  no blow, no voice.
- **The five things that most break "I'm controlling them"**, in order:
  1. The legs ignore the direction of travel. Heroes face the cursor, so most player movement is off-axis.
  2. The melee wind-up plays after the hit has already landed.
  3. The body never reacts to starting, stopping, turning or being shoved: no lean, no settle.
  4. A voice cast has 0.3-1 s of dead air: the hero does nothing until the spell fires.
  5. Getting hit is only a white flash. There is no flinch and no hit-stop.
- **Recommendation: build the locomotion layer (treatment B) first, with the strike-first melee timing.** Both are cheap,
  cosmetic and on screen every second. Next comes the voice channel, then hit reactions (section 7).

---

## 1. How a hero animates today (diagnosis)

**The code.**
- `Hero` (`scripts/heroes/hero.gd`) owns `_visual`, a yaw node.
- The faceted models (`WickModel`, `GasketModel`, `RebarModel`, all `LowPolyModel`, `scripts/art/lowpoly/`) are built
  from rigid named parts and posed in code every frame by `apply_idle(t, speed)`.
- Actions are tweens on per-model "arm kick" scalars (`LowPolyModel._kick_arm`) that `apply_idle` adds to the rest pose.

### 1.1 What each moment does today

| Moment | What the code does | What it looks like |
|---|---|---|
| **Walk / run** | `LowPolyModel._process` measures speed from its own position change (smoothed at 10/s). `apply_idle` swings rigid legs about the hip by `sin(t·ω)·A·walk`, where ω is fixed per model (Wick 9, Gasket 8, Rebar 7 rad/s) and `walk = clamp(speed / 4…4.5, 0, 1)`. The body bobs with `abs(sin)`. The arms counter-swing. | Cadence never changes with speed; only stride size does. Above `walk_ref` (coffee) the stride stops growing. See the stride table below. |
| **Start / stop** | `Actor.move` gives full speed on the first frame and zero on the frame the key is released (no acceleration). The legs follow the smoothed speed. | The body glides off at full speed while the legs ramp up over about 0.2 s. On a stop the legs keep pedalling for about 0.2 s after the body is still. No lean, no settle. |
| **Facing / turning** | `facing` is the cursor (`PlayerController` calls `face_point(aim)` every frame after `move`). `_visual` turns toward it at `TURN_RATE` 18/s (63% in 55 ms, about 95% in 170 ms). | Turning is fast and responsive, which is good. But the legs always swing along `facing`. |
| **Strafe / backpedal** | Legs swing in the model's own forward plane whatever the direction of travel. | Walking sideways reads as a forward walk while gliding sideways (the moonwalk). AI allies kite this way all the time (`AllyBrain`: `move(-dir)` + `face_point(foe)`). |
| **Idle** | Breathing sines. Wick has a nervous fidget (head darts, hat bob, trembling knees). Gasket and Rebar have a slow nod. | Good personality, especially Wick. Nothing reacts to the world (a nearby fight, low HP). |
| **Melee** | The hit resolves on the click frame (`_melee_effect` → `Combat.melee_arc`, `Fx.slash_arc`). Then `attack_swing()` starts its wind-up: Wick `_kick_arm("bash", 1.0, -1.25, 0.10, 0.07, 0.30)`, Gasket `(…, 0.12, 0.08, 0.32)` with a body lean, Rebar `(…, 0.06, 0.07, 0.30)`. | The damage number, flash and arc appear while the weapon is still going **back**. The weapon reaches the target 0.17 s (Wick), 0.20 s (Gasket) or 0.13 s (Rebar) after the hit landed: an anticipation that only adds lag. |
| **Ranged** | Wick's `shoot_pose` raises the bow in 0.07 s, draws in 0.09 s and recoils elastically. The hold-to-draw `draw_hold` and charge ring are good. Gasket's spin turns the model 360°. Rebar's bowl is an underhand swing with a body lean. | Reads well. The arrow is already away when the raise starts (the same problem as melee, but small). |
| **Voice cast** | Between speech onset and the spell, the body does nothing. `trigger_heard` only plays the `cast_heard` sound, on the speaker's machine. On the spell (`try_cast` → `_cast_pose`) the wand or wrench kicks up (peak about 0.18 s, back over 0.5 s). Online the effect lands `NetCasts.LEAD` (0.2 s) later on every machine. The caster's pose peak roughly matches by luck. A puppet's pose plays when the event arrives, so it peaks one network delay late. | The 0.3-1 s the player spends speaking is invisible. The held component (the heal crystal is torso-sized) hides Wick's wand hand (`strip_cast.png`, top row). |
| **Getting hit** | `Fx.flash` (a white overlay for 0.12 s), a damage number and a camera shake for your own hero on slam, landing or daze. No pose change and no hit-stop anywhere in the code. | A white blink. The body never flinches. |
| **Shoved / airborne** | `Actor.shove` slides the whole hero (ease-out over 0.2-0.35 s). The model stays rigid, and its legs **walk** because it measures speed from position. Airborne arcs (gravity 24) only happen over ledges. Landing raises dust and a ring. | A board sliding across the floor while walking in place, then stopping dead. |
| **Climb / drop a level** | `climbing` slows the hero (`climb_speed_factor` 0.25-0.6) and eases Y at 4/s. Walking off a step eases Y down at 14/s. | A slow walk that floats up. No reach or hop. A drop is a smooth slide down. |
| **Wading** | Speed ×0.75, a ripple ring, a step sound. | A slower normal walk, waist-deep. No high-stepping. |
| **Dazed** | Stars, and `_visual` sways (z 0.2·sin 11t, x 0.08·sin 7t). | Reads well. The only reaction pose in the game. |
| **Downed** | `_visual` tips over to 90° in 0.35 s (bounce) and the model desaturates. The idle stops. | Fine, and readable. |
| **AI teammates / puppets** | Same Hero and model code. A puppet's speed comes from its interpolated position, so everything above happens on every screen. Its `damaged` signal does not fire, because the net layer writes its HP. | Same as the owner's hero. Anything we derive from position works on puppets for free. |

### 1.2 Stride match (measured)

These numbers come from the lab's `--measure` mode. It walks each hero for 1.5 s and tracks the soles. The value is the
planted foot's backward sweep relative to the hip at its fastest, divided by the ground speed. **1.00 means the foot is
still at mid-stance.** Below 1 the feet skate along with the body (ice skating). Above 1 they paddle backward. 0 means the
legs swing across the direction of travel (strafing).

| Case | Wick today | Gasket today | Rebar today | Treatment B (all three) |
|---|---|---|---|---|
| Bow drawn, 2.25 u/s | 1.22 | 0.51 | 0.96 | 0.98 / 1.00 / 1.05 |
| Wading, 3.4 | 1.22 | 0.51 | 0.96 | 0.97 / 1.00 / 1.05 |
| Walk, 4.5 | 1.08 | **0.45** | 0.96 | 0.97 / 1.00 / 1.05 |
| Coffee, 7.2 | 0.67 | **0.28** | 0.60 | 0.97 / 1.00 / 1.05 |
| Strafe, aim 90° off | **0.00** | **0.00** | **0.00** | 0.95 / 0.98 / 1.03 |
| Backpedal | 1.08 | 0.45 | 0.96 | 0.97 / 0.99 / 1.05 |

Gasket's short legs (hip at 0.48) cycle at the same 8 rad/s as everyone else's, so her feet slide at more than half the
ground speed. Every hero skates when strafing. This is the gap the player sees most, because aiming with the mouse while
walking means walking off-axis.

### 1.3 Screen size

- At the game camera (ortho 24, pitch -56°, 1080p) a hero is about 55-75 px tall, and a hand or wand is 3-6 px.
- In the game-zoom strip (`strip_game_zoom.png`), arm-level poses (the cast's wand raise, the bash) barely register.
- What reads at that size:
  - **whole-body** motion: lean, squash, the bob, a hop;
  - **the silhouette** of a big weapon (the wrench's overhead arc);
  - **ground-plane FX** (rings, the slash wedge).
- This matches Riot's rule that silhouette comes first and animation second (sources 27, 28 below).

---

## 2. Research: what makes a character feel controlled

Source numbers refer to the list in section 8. Where a page could not be opened, the list says so.

1. **The first frame must move.**
   - Mick West measures good responsiveness as about 3-4 frames from input to the screen at 60 fps. Every frame that
     animation adds before the impulse is lag. [21, 22]
   - In Heavenly Sword attacks responded in 7/60 s, but turning took 18/60 s: the turn animations were the lag. [22]
   - Halo: Reach starts the grenade throw on the button press and hides up to about 150 ms of network wait inside it. [30]
2. **The player's wind-up is near zero; the enemy's wind-up is a telegraph.**
   - Give player attacks short anticipation and spend the frames on follow-through and recoil. NPCs get long
     anticipation so the player can react. [23]
   - Cast's monsters already telegraph (the brute's slam, the pavise's line). The heroes copied the monster pattern.
3. **Recovery is cancellable.**
   - Supergiant's first Hades II patch made the dash cancel out of attack recoveries "more reliably" because it felt
     unresponsive. [1, 2]
   - In Dota, the backswing after a cast can be cancelled freely. [26]
4. **Visual acceleration, not mechanical.**
   - Diablo IV added start and stop animations without changing the actual movement speed. [3]
   - The body can lag and overshoot the true velocity through springs while the simulation stays instant. [11]
5. **Springs over lerps.**
   - Holden's critically damped spring and half-life damper are stable and independent of the frame rate. [11]
   - t3ssel8r's second-order follower (frequency f, damping ζ, response r) gives personality: ζ < 1 wobbles and
     overshoots; r < 0 anticipates. [10]
   - Inertialization snaps to the new pose at once and decays the leftover offset, so there is no blend lag. [12]
6. **Phase the gait by distance, not time.**
   - Rosen's "stride wheel" (Overgrowth, GDC 2014) does this with about 4 poses per cycle, interpolated by springs. It is
     the closest reference for rigid parts posed in code. [8]
   - Unreal's stride warping does the same: stride scale = speed / authored speed. Its orientation warping turns the legs
     toward the travel direction while the torso keeps facing. That is exactly our strafe gap. [15]
7. **Hit-stop is a short freeze, scaled to the blow and capped.**
   - Vlambeer: a 10-20 ms pause on every hit, plus 1 white frame and 2 hurt frames. [17]
   - Sakurai (Smash): attacker and victim freeze together, scaled by damage and capped. Projectiles get less, and
     4-player fights get less. The victim shakes side to side on the ground and up and down in the air. [24]
   - A study puts the best hit-stop for a big blow at 0.1-0.2 s. [25]
8. **Squash, stretch, overshoot.**
   - Overshoot the extreme poses, hold the key poses a beat, offset the limbs' timing, and break the rig (smears). [29]
   - Juice comes from tweening, squash and stretch, particles and shake, not from slower moves. [16, 17]
9. **Readability at small size.**
   - Silhouette is first. Facing must read at a glance. The hit area must match the VFX. Visual weight follows
     gameplay importance. [27, 28]
10. **Hide latency in a motion that starts at once.**
    - Halo's grenade throw [30], Dota's cast point [26] and WoW's ~400 ms spell queue [31] all do this.
    - People expect a conversational reply within about 100-300 ms [32]. Cast's 0.3-1 s from speech to spell needs a
      visible "I'm hearing you".
11. **Animate puppets locally from smoothed state.**
    - Show remote characters about one send interval in the past, interpolated with velocity. [33, 34, 35]
    - Derive their gait, lean and turn locally from the smoothed velocity rather than streaming animation state. [36]
    - Replay discrete actions as events. [36, 37]
    - Cast already streams heroes at 30 Hz with position, velocity and facing, and replays actions as `act` events.

Gaps in the research: I found no primary developer talk on animation responsiveness for Hades, Diablo IV, Tunic, Lost Ark,
Ravenswatch or Hyper Light Drifter, only patch notes, reviews and second-hand quotes. GDC Vault was down for maintenance,
so the Vault links are unverified.

---

## 3. Gap analysis for Cast

Ranked by expected effect on "it feels like I'm controlling them". The cost is for the game version, not the mock.

| # | Gap | Why it hurts control | Fix (treatment) | Net cost | Perf | Effort |
|---|---|---|---|---|---|---|
| 1 | **Legs ignore the direction of travel** (strafe 0.00, backpedal moonwalk). AI allies kite this way constantly. | Most player movement is off-axis because the hero faces the cursor. The feet contradict the input every second. | B: turn the legs toward the travel direction, mirror the swing past 110° | none (velocity and facing are shown on every screen) | a basis per leg | S |
| 2 | **Melee wind-up after the hit** (hit-to-impact 0.13-0.20 s) | The click's result (number, flash, arc) arrives before the body does it. Every swing feels late. | C: strike first: wind in 1 frame, impact on frame 3-4, a long follow-through, a small lunge | none (`act` already replays it) | none | XS (tween arguments) |
| 3 | **No body response to acceleration** (start, stop, turn, shove) | The input lands but the body never commits. The hero is a board on rails. | B: a lean that leads the velocity (spring), squash on start and stop, a bank in turns, legs still while shoved | none | 2 springs | S |
| 4 | **Voice cast dead air** (0.3-1 s) | Speaking is the main verb, and nothing shows it was heard until the spell lands. Network and recognizer latency are not hidden. | C: channel: listen on speech onset, gather on the trigger word (a wand or wrench up, a hand glow, a ring on the floor drawing in), release on the spell (snap, stretch, flash) | the owner's own screen for free; showing other players' channels needs a 1-byte "armed" event (open question) | 2 meshes while casting | M |
| 5 | **Hits have no body reaction** | Taking damage reads as a UI event, not a blow. The attacker's blows feel weightless too. | C: a flinch away from the blow (lean and head springs), a 4-frame victim hit-stop with a shake, a 3-frame attacker hit-stop on contact | none (on a puppet, derive it from the HP dropping in its snapshot) | none | S |
| 6 | Stride not matched (Gasket 0.45, coffee 0.28-0.67, Wick paddles 1.22 when slow) | Ice skating reads as "not touching the floor". | B: run the model's clock at `speed / (leg · amplitude)`; Gasket's swing ×1.45 | none | none | XS |
| 7 | Legs walk during a shove | The body is being pushed but pedals. | B's lean, plus pausing the stride while `is_shoved()` (not in the mock yet) | none | none | XS |
| 8 | The held component hides the cast hand | The cast pose is invisible behind a torso-sized crystal. | Make the component the focus: it lifts and glows during the channel. Or move it to the off-hand. | none | none | S |
| 9 | No climb, drop or landing poses | Height changes, a pillar of Cast's exploration, have no physicality. | A reach-and-hop on climb, a drop hop, landing squash (the spring in B takes impulses) | none | none | S-M |
| 10 | Secondary motion is timer-driven (Wick's hat and quiver bob on sines) | Accessories don't trail turns or stops, so the body reads as one rigid piece. | Drive the hat tip, beard braids, vest and quiver off the lean spring (one spring each) | none | 1 spring per accessory | S |
| 11 | Wading has no pose | The water is only a speed number. | Shorter, higher steps and a lowered body while `Wading.is_wading` | none | none | XS |

---

## 4. Treatments (as built in the mock)

All three lanes use the **same real Hero** with its faceted model, moved by `Hero.move`, hit by `apply_damage`, shoved by
`Actor.shove` and swinging by `Hero.melee`. The lab inserts a "feel" node between `Hero._visual` and the model.

- **A "Today".** The game as it is.
- **B "grounded" (locomotion layer).** Driven only by the hero's shown position and facing:
  - **Lean.**
    - `head offset = v_smooth · lean + (v_raw − v_smooth) · kick`, where `v_smooth` approaches the raw velocity at 9/s.
      The result is mapped to pitch and roll, clamped at ±0.38 rad (22°) and passed through a spring.
    - Wick: lean 0.032, kick 0.075, spring f 2.6 Hz, ζ 0.42 (wobbly, nervous).
    - Gasket: 0.028 / 0.065 / 3.2 Hz / ζ 0.5 (snappy).
    - Rebar: 0.018 / 0.045 / 1.7 Hz / ζ 0.65 (heavy, slow).
    - Starting leans the body forward and stopping throws it back, then it settles. Turning banks it. A shove tips it
      back against the slide.
  - **Squash.**
    - A spring at 4.5 Hz, ζ 0.32, clamped −0.16 to +0.2, scaled `(1 + s/2, 1 − s, 1 + s/2)` about the feet.
    - Impulses: −0.9 (a stretch) on starting, +1.3 (a squash) on stopping. Per-hero multiplier: Wick 1.0, Gasket 1.2,
      Rebar 0.6.
  - **Stride clock.**
    - The model's own `apply_idle` clock runs at `rate = lerp(ω_model, speed / (leg · A · walk), smoothstep(0, 0.25, walk))`.
    - The legs (hip-to-sole) are Wick 0.92, Gasket 0.46 and Rebar 1.17. Gasket's swing is ×1.45.
    - It is a one-line change to `LowPolyModel._process` plus a per-model leg length.
  - **Legs follow the travel direction.**
    - Leg yaw is −0.85 × the angle between travel and facing, clamped at ±1.35 rad.
    - Past 110° (backpedal) the swing is mirrored and the legs face forward.
    - It fades in from 0.2 to 1.2 u/s and turns at 14/s.
    - The torso keeps facing the cursor, like Unreal's orientation warping.
- **C "actions" (B + the action layer).**
  - **Strike-first melee.**
    - Wick `_kick_arm("bash", 0.9, -1.3, 0.017, 0.05, 0.34)`, Gasket `("weapon", 1.0, -1.35, 0.017, 0.06, 0.36)`,
      Rebar `(arm, -0.4, 1.6, 0.017, 0.05, 0.32)`.
    - The impact lands on frame 3-4 instead of 8-12.
    - A forward lunge of 0.16 u that decays at 10/s, plus a −3.2 rad/s pitch kick and a −0.6 stretch.
    - A 3-frame attacker hit-stop 4 frames after the click when the blow connects.
  - **Hit reaction.**
    - A flinch impulse away from the blow: lean 9 rad/s and head 14 rad/s, × damage/12, clamped 0.4-1.6.
    - Squash +1.6, then a **4-frame victim hit-stop** (the model and its tweens freeze) with a ±0.08 u shake.
  - **Voice channel.**
    - Speech onset sets the channel target to 0.35 (listen). The trigger word sets it to 0.75 (gather). It ramps up at
      2.6/s and down at 4/s.
    - While channelling:
      - the wand, wrench or fists rise to 0.95·c, with a 47 Hz tremble;
      - the body crouches (squash 0.07·c);
      - a cool glow at the casting hand grows to a radius of (0.08 + 0.45c)·0.5;
      - **a ring on the floor** shrinks from radius 1.6 to 0.8 while its alpha rises from 0.25 to 0.85.
    - **Release** on the spell:
      - the arm snaps from 0.7 to 1.15 in 1 frame plus 0.05 s;
      - the body stretches (−1.6) and throws forward (−2.6 rad/s);
      - a flash sphere and an outward ring play.

### What the mocks show (look at the strips)

- **`strip_attack.png`**
  - Today: the slash wedge is on the floor at t=0.32-0.38 s while the bow is still swinging back.
  - C: the bow is through the wedge at 0.35 s.
  - It is the clearest single difference, and it reads at game zoom too (`strip_game_zoom.png`, third block).
- **`strip_strafe.png` / `gif_strafe.gif`.** Today: the legs scissor forward and back while Wick glides sideways. B and C:
  the legs turn into the walk, and the body leans into it and back on the stop.
- **`strip_startstop.png`**
  - B leans into the start (t=0.45-0.75) and rocks back on the stop (1.38) before settling.
  - Today stays bolt upright.
  - At game zoom the lean is the one change that still reads clearly.
- **`strip_cast.png` / `gif_cast.gif`**
  - C shows the floor ring from 0.40 s (listen), drawing in by 1.0 s (armed), and the burst at 1.12-1.35 s.
  - Today and B show nothing until 1.12 s.
  - At game zoom only the ring reads; the hand glow is a few pixels. In the close-up the heal crystal hides the wand
    (gap 8).
- **`strip_hit.png`**
  - The 0.12 s white flash already covers the first frames; C's flinch shows after it (0.45 s).
  - On the shove (1.05-1.2 s) B and C tip back against the slide. Today walks in place while sliding.
- **`sheet_gasket.png`**
  - Gasket's coat hides most of her legs, so stride matching matters less for her visually than the lean.
  - Strike-first **loses her best silhouette**: Today's overhead wrench wind-up (t=0.35-0.38 s) is the biggest, most
    readable shape in her kit. Proposal: keep a 2-frame wind, or move the overhead arc to the follow-through
    (overshoot past the floor and lift back over the shoulder).

---

## 5. Mock files

| File | What |
|---|---|
| `scenes/anim_lab.tscn`, `scripts/art/lowpoly/anim_lab.gd` | The lab: three lanes of one real hero (Today / B / C) playing a scripted clip (`--clip startstop\|strafe\|turn\|cast\|hit\|attack`, `--hero wick\|gasket\|rebar`, `--zoom close\|game`, `--frames-dir` for GIF frames, `--measure` for the stride table). Run it with `--fixed-fps 60`; the usage is in its header. |
| `scripts/art/lowpoly/anim_lab_feel.gd` | The proposed feel layer (levels 1 and 2), with every parameter above. It is a plain Node3D between `_visual` and the model, written to be lifted into the game almost as is. |
| `docs/design/animation/strip_startstop.png`, `strip_strafe.png`, `strip_cast.png`, `strip_attack.png`, `strip_hit.png` | Wick close-ups (ortho 8, pitch -32°): rows Today / B / C, 8 times each (labelled). |
| `docs/design/animation/strip_game_zoom.png` | Start/stop, cast and bash at the real game zoom (ortho 24, pitch -56°, pixels ×2). |
| `docs/design/animation/sheet_gasket.png` | Gasket: start/stop, strafe, cast, wrench smash. |
| `docs/design/animation/gif_strafe.gif`, `gif_cast.gif`, `gif_attack.gif` | The three lanes side by side at 30 fps. |

To regenerate, run:

```
godot --path . --fixed-fps 60 --resolution 1920x1080 -- --scene res://scenes/anim_lab.tscn --hero wick --clip cast --shot <abs>.png [--zoom game] [--frames-dir <abs dir>]
```

The strips in the docs folder were labelled and palette-reduced afterwards with a small PIL script, and the GIFs made with
ffmpeg's palettegen. Neither script is committed.

---

## 6. Where animation meets movement (`movement-research.md`)

- **If the movement doc adds real acceleration or deceleration to `Actor.move`**, B's lean still works and gets subtler:
  its kick term is the gap between the shown velocity and its smoothed copy. Turn the `kick` gains down so the body
  doesn't double up.
- **The movement doc should keep the first-frame response instant**, or have it come from motion (principle 1). The
  animation layer then supplies the weight (principle 4: visual acceleration, not mechanical).
- **A dodge or dash, if added, needs a pose.**
  - A tuck or roll with a squash at the start and the end, driven by `is_shoved()`-style forced-motion state, so puppets
    get it free.
  - Its recovery should cancel into walking (Hades II, source 1).
- **Sprint** would push the speed past every model's `walk_ref`. B's stride clock already handles any speed, and the lean
  grows with speed (clamped at 22°).
- **Camera.** A follow camera with look-ahead makes the lean read better, because the hero stays put on screen.
  Screenshake is already used for slams, landings and dazes. Hit-stop should never freeze the camera or the simulation,
  only the model.

---

## 7. Recommendation

1. **First: treatment B plus strike-first, as one change (about a day).**
   - What to do:
     - Add a feel node per hero (lift `anim_lab_feel.gd`'s level 1) between `_visual` and the model.
     - Move the stride clock into `LowPolyModel`, and give each model `leg_len` and tuning.
     - Pause the stride while `is_shoved()`.
     - (2026-10-21: these two are built, as `Gait` (`scripts/art/lowpoly/gait.gd`, the per-model tuning in its table): the
       movement feel's `grounded` profile runs it in the game (`HeroGait`, `movement-research.md` 5.3) and this lab's lane B
       runs the same code. The lean, the squash and strike-first are still this track's to add on top.)
     - Change the three `attack_swing()` tween timings, plus Wick's `shoot_pose` raise.
   - Why first: it is purely cosmetic, derived from the position and facing every screen already shows, so puppets and AI
     allies get it free, and it adds no new net state. It also costs a few springs per hero per frame.
   - The test to add: a lab measure like section 1.2 as a headless test (stride match within 0.85-1.15 and strafe above
     0.8 for all three heroes).
2. **Second: the voice channel** on your own hero: `speech_started`, `trigger_heard` and `spell_cast` from `VoiceCaster`
   and `Hero`.
   - The ring on the floor is what reads at game zoom.
   - Make the held component the glowing focus.
   - Online, aim the release peak at the cast's landing time (`at`). Puppets can play their release when the event lands
     instead of when it arrives.
3. **Third: hit reactions and hit-stop.**
   - Victim: derive the flinch from the HP dropping on every screen, with its direction from the nearest hostile.
   - Attacker: a hit-stop on contact on the attacker's own screen.
   - Keep the stops at 3-4 frames: four players and dozens of imps means many hits (Sakurai's caution).
4. **Later:** climb, drop and landing poses, the wading step, accessory springs (Wick's hat, Gasket's braids, Rebar's vest
   tape), and idle reactions (looking toward noise, a slump at low HP).

### 7.1 As built: `grounded_anim` (2026-10-22)

The user, after the blind A/B of package A: "Grounded is better. Not there yet." They picked **"Animation B +
strike-first"** on top of grounded, then (same day) "We might want to rework the attack damage areas as part of this. For
Gasket the attack area doesn't match the weapon" and "We might want to change the weapon animation to be more of a centered
hammer strike." Built as a third MoveFeel profile, **`grounded_anim`** = grounded + B + strike-first + the reshaped hit
areas. **`today` is still the default**; nothing changes in normal play until the user picks.

#### How to A/B
| Command | What |
|---|---|
| `.\run.ps1 --move-lab --move-feel shuffle --no-mic` | `grounded` and `grounded_anim` dealt blind as "feel 1" / "feel 2"; **F6** switches. |
| `.\run.ps1 --move-lab --move-feel grounded_anim --no-mic` | Named (`today` and `grounded` too; F6 cycles today, grounded, grounded_anim). |
| `.\run.ps1 -Crew 2 --net-wait 2 --move-lab --move-feel grounded_anim` | A crew: the host's profile is everyone's (it rides the job), so the lean, the strike and the hit areas agree on every screen. |
| `godot --path . --fixed-fps 60 --resolution 1920x1080 -- --scene res://scenes/strike_lab.tscn --hero gasket --clip attack --strike both --shot <png>` | The lab: one lane per profile, each played by the game's own code (`--clip startstop\|strafe\|attack`, `--zoom game`, `--frames-dir`). `--overlay` draws the hit area and the weapon's path top-down and prints the numbers. |

#### What was built
| Piece | Where | What |
|---|---|---|
| The profile | `MoveFeel` (`scripts/heroes/move_feel.gd`) | `grounded_anim`: grounded's keys plus `body`, `strike_first` and `melee_areas`. `BLIND` is what shuffle deals. |
| The body (B) | `HeroFeel` (`scripts/heroes/hero_feel.gd`), ticked from `Hero._process` before `HeroGait` | A pivot node between `Hero._visual` and the model (added and removed as the profile switches). The lab's lean and squash, per hero, from the shown position: lean = smoothed velocity x `lean` + (quick - smoothed velocity) x `kick`, through a spring, clamped at 22 degrees; a shove tips the body back against the slide. Squash springs on a start (a stretch) and a stop (a squash sized by the speed just had). |
| Stride held | `HeroGait`, `Gait.hold` | Under `body`, the stride clock stops while the hero is shoved or airborne (a hop, a fall): the legs keep their pose instead of walking on air. grounded is unchanged (its shove case still settles the legs). |
| Strike first | `HeroFeel.STRIKES`, `Hero._swing_pose` | The swing's pose is a timeline of the model's kick channels: the weapon is at its impact on the frame the hit resolves (the click's frame), then a small lunge, a forward pitch and a squash; when the blow touched something, a **50 ms (3-frame) hit-stop of the attacker's pose only** (the simulation, the hero's motion, the damage and the cooldown are untouched). Puppets play it from the replayed `act`. |
| The weapons | `WickModel` (`follow`), `GasketModel` (`smash_w`, `smash_a`), `RebarModel` (`slam_w`, `slam_a`) | New channels, at rest unless HeroFeel drives them (today's poses are unchanged). Wick's bash carries through to his right front. **Gasket: an overhead smash onto her centre line**: the wrench comes straight down and the head lands about 2.0 ahead on her centre line (first built two-handed; since the user's playtest one-handed beside her right shoulder, see "Gasket after the playtest" below). **Rebar: a centred double-fist slam** (my call, since his alternating punches landed 0.8 ahead at his sides while his wedge reached 1.8 at 120 degrees): both fists come down together in front of him with a forward bend and a crouch. |
| Hit areas | `Hero.melee_area`, `Combat.melee_lane` / `lane_targets` / `arc_targets`, `Fx.slam_lane` | Each kit's area under the profile. A lane is everything within `radius` of the segment from `near` to `far` ahead (near = far: a disc). The floor mark matches the area (`Fx.slam_lane`: the stadium plus a ring where the blow lands). The AI's prop check and its "turn the swing" use the area (`AllyBrain._area_clear`, `Hero.melee_half_angle`). |
| Lab | `scripts/art/lowpoly/strike_lab.gd`, `scenes/strike_lab.tscn` | Built on the anim lab: lanes are profiles, `--strike follow\|wind\|both`, `--overlay`. |

#### The numbers
Body (measured, `test_move_feel_anim`, 60 Hz, a walk at 4.5 u/s through grounded's envelope):

| | Wick | Gasket | Rebar |
|---|---|---|---|
| Tuning (lean / kick / spring f, zeta / squash x) | 0.032 / 0.075 / 2.6 Hz, 0.42 / 1.0 | 0.028 / 0.065 / 3.2 Hz, 0.50 / 1.2 | 0.018 / 0.045 / 1.7 Hz, 0.65 / 0.6 |
| Lean at most (limit 22 deg) | 19.9 deg | 16.1 deg | 8.1 deg |
| Into a start / back on a stop | 14.0 / 6.1 deg | 11.5 / 4.7 deg | 6.3 / 1.7 deg |
| Stretch / squash (limit -16% / +20%) | -5% / +6% | -6% / +7% | -3% / +3% |
| Strike: lunge, pitch kick | 0.16 u, 3.2 rad/s | 0.14 u, 2.6 rad/s | 0.10 u, 1.8 rad/s |

Strike first: damage and the impact pose on the **same frame** for all three (the test allows +-1), a 3-frame hit-stop on a
connecting blow, none on a miss. Today's impact came 14 (Wick), 17 (Gasket) and 18 (Rebar) frames after the damage (the
overlay's measure: the weapon's farthest reach).

**Gasket and Rebar's big shape: the follow-through ("follow"), picked.** Both were built (`--strike wind` is the 2-frame
wind-up: the wrench or the fists go up over the head on frames 0-2 and land on frame 3). The wind-up reads a little more like
a classic hammer blow in the strips, but its impact lands 3 frames after the number, which breaks strike-first's rule (the
damage frame +-1); the follow-through lands on the damage frame and then lifts the wrench (or both fists) back over the head,
so the big overhead silhouette is still on screen for about 0.3 s. Open question 3 below for the user.

#### Hit areas: today vs proposed (a balance proposal, behind the profile)
Measured with `strike_lab --overlay` (`docs/design/animation/ga_overlay_*.png`): the weapon's tracked points every frame
of the swing (Gasket: the wrench head; Rebar: both gloves' knuckles; Wick: the bow's grip and tips), drawn on the floor
(blue before the impact, white at it, orange after; faint above 1.6, over a grunt's head), with the area (filled) and the
area a grunt (radius 0.38) can stand in and be hit (the thin outline). "Grunt hit area" is that second area's size.

| Hero | Today's area (today, grounded) | Where today's weapon lands | Proposed area (grounded_anim) | Where the new weapon lands | Grunt hit area | Farthest hit (grunt centre) |
|---|---|---|---|---|---|---|
| Wick (bow bash) | wedge 1.3, 90 deg | 0.8 ahead, centred (inside) | **unchanged**: wedge 1.3, 90 deg | 0.9 ahead, the bow across his front +-0.8 (inside) | 2.22 -> 2.22 | 1.68 -> 1.68 |
| Gasket (hammer) | wedge 1.5, 90 deg | **2.3 ahead, 0.9 to her right, 1.2 up: outside the wedge** (2% of the swing's low path inside it) | **lane** 0.6 -> 1.95 ahead, 0.25 wide each side, **ending in a disc of 0.6 round the head's landing** (the smash; first built as the lane alone, 0.6 -> 1.9) | 2.0 ahead, centred, on the floor (inside) | 2.78 -> 4.20 (+51%; the lane alone was 2.88) | 1.88 -> 2.93 (the lane alone 2.53) |
| Rebar (slam fist) | wedge 1.8, 120 deg | 0.8 ahead, 1.0 to the side (the punching fist; the wedge reaches 1.8) | **disc** of 0.85 centred 1.05 ahead (the shockwave where both fists land) | 1.0 ahead, centred, 0.8 up (inside) | 4.98 -> 4.75 (-5%) | 2.18 -> 2.28 (+0.10) |

What changes in play: **damage, cooldowns and shoves are unchanged, so DPS is unchanged** (Wick 30, Gasket 43, Rebar 19
per second on one target). Gasket trades width for reach: she hits a target up to 0.65 farther straight ahead but nothing
more than 0.63 to the side of her line (today: anything within 45 degrees), so she aims her hammer and a crowd at her flanks
is no longer hit. Rebar's area is a little smaller and rounder: about the same reach ahead, narrower at his far corners
(today's wedge reached 60 degrees out to 1.8), still the whole front of him up close. The floor mark is the area in both
cases. The AI uses the same areas (its swing distance is unchanged: every shape covers a target straight ahead from contact
to the kit's reach).

#### The held component sits in the hand (a bug fix, every profile)
The user: "The other floating prop is the 'held in hand' spell which for Gasket at least just floats to the side." It did
for all three: Gasket's hung 0.66 outside her left arm at 0.8 across, Rebar's off the outside of his left glove, and Wick's
floated 0.34 above his right hand at torso size (gap 8: it hid the wand hand). Now each is gripped at the hand part's own
transform and sized to the hand, so it follows every pose (walk, the swings, the cast, the lean, squash and strike-first):

| Hero | Hand part | Grip (part-local) | Across (was) |
|---|---|---|---|
| Wick | the right fist (`hand`, the arm's aim point) | just under the knuckles, so the wand stands clear above | 0.35 (0.75) |
| Gasket | `arm_l`, the bare fist at (0, -0.76, 0) | just past the knuckles; its scale undoes the sleeve's stretch in the smash | 0.45 (0.80) |
| Rebar | `glove_l` | half in the palm, in front of the knuckles | 0.55 (0.83) |

`test_move_feel_anim` holds it within 0.3 of the fist (0.45 of Rebar's glove centre) and at most 0.6 across through
standing, walking, a swing and a cast, under today and grounded_anim. Before / after: `ga_held_<hero>.png` (`strike_lab
--clip held`). The "cast armed" look (a floor rune / hand glow while speaking) is a separate look-dev track and not built here.

#### Gasket after the playtest (2026-10-22)
The user played `grounded_anim` as Gasket: **"Gasket feels MUCH better. The animation has a problem though, the arm
penetrates the body and disappears when the hammer comes down. The impact of the hammer should be a little bigger too. It is
a smash weapon. But the point is MUCH better than the 'swing arc' that was there before."** Fixed:

- **No arm in the body.** Measured with `PoseClip` (each arm's centre line against the body parts' boxes; `strike_lab
  --clipcheck` prints it per frame): the two-handed smash buried her left arm 0.27 deep in her coat at the impact and her
  right arm 0.22 in her head at the top of the follow-through. A straight arm from her shoulder to a fist on her centre line
  has to cross her coat, so the smash is now **one-handed**: her right fist rides an arc in the plane of her right shoulder
  (outside the coat and the beard), the handle is turned in (0.39 rad) so the head still lands on her centre line, and her
  left arm swings back and out for balance (the held component stays in that hand, in view). Deepest now: **0.000** for
  every frame of a walk, a stop, two swings (follow-through and wind-up, with the lean, squash and lunge) and a cast, for
  Gasket, Rebar (0.005 before; his clasp is 0.46 now) and Wick (`test_move_feel_anim`, `_no_clip`).
- **A bigger smash.** The aimed lane stays and ends in a disc of 0.6 round the head (2.0 ahead): a grunt is hit within
  0.98 of the landing. Grunt hit area **4.20** (today's wedge 2.78, the lane alone 2.88); farthest hit 2.93 (1.88, 2.53).
  Damage and cooldown are unchanged, so one target takes the same DPS; the extra area is more targets per swing (a crowd
  ahead of her). The floor mark draws the disc.
- **Weight.** At the impact, on every screen (a puppet's replayed smash too): a fast pale shock ring and a puff of dust
  (`Fx.ground_smash`). (First built with dark cracks radiating from the head too; the user, 2026-10-22: **"Lets also
  remove the crack from Gasket's primary. Just the white effects you have."** Removed; `test_move_feel_anim` checks no dark
  mark is left on the floor.) A connecting smash holds her pose **83 ms (5 frames)** instead of 50. The attacker's own
  screen gets a small camera nudge (`Fx.shake(0.12)`; a puppet's smash shakes no one). Strike-first timing is unchanged:
  the impact is still on the damage frame.
- Evidence: `ga_overlay_gasket.png`, `ga_gasket_close.png`, `ga_gasket_game.png`, `ga_gif_gasket_attack.gif` (redone),
  `ga_held_gasket.png`.

#### The secondaries (2026-10-22)
The user: **"Gasket's primary attack is better. What about the secondary?"** Measured with `strike_lab --overlay
--secondary` (the RMB attack; a projectile's first frames in cyan) and `--clipcheck`:

| Hero | Secondary | Today (and grounded) | grounded_anim |
|---|---|---|---|
| Gasket | spin: every monster within the spin's reach hit at once, on the click | the wrench sweeps round **25 frames** after the hits (0.1 s to swing out, a 0.5 s turn); its head runs 2.1-2.2 from her, the area is 1.9 | **strike-first whirl**: the wrench is out on the click's frame and she turns a full circle in **7 frames**, then brings it back; the area is **2.1** (the head's sweep: grunt hit area 16.3 -> 19.3, +18%); a pale ring and dust thrown out low at her feet (`Fx.spin_dust`, white effects only); a spin that touches something holds **2 frames**; no arm in her body (0.000) |
| Wick | tap arrow: flies from his chest on the click | the arrow leaves while the bow is still at his hip (0.9 from the arrow), raised **5 frames later**; a drawn shot dipped the bow to his hip and back up | **strike-first shot**: the bow is up and the string snaps forward on the click's frame (no dip after a draw); the arrow starts under the raised bow (0.6 below it: it flies at chest height, the bow is held at the eye) |
| Rebar | bowl: the boulder rolls out 1.1 ahead of him on the click | the boulder appears **1.6 from his hand** (his glove hangs at his side) and the underhand swing comes 14-27 frames later | **strike-first release**: he stoops and his right glove is down and in at the boulder (**0.8** from its centre) on the click's frame, then follows through up; no arm in his body (0.007) |

- Damage, cooldowns, the arrow's and the boulder's paths are unchanged: only the poses (and the spin's radius, a proposal
  behind the profile) changed. The AI's "use the spin" check uses the same radius (`Hero.spin_area`).
- **Proposed, not built:** Wick's drawing hand reaches into his face at full draw in his aim pose (0.18 deep today, 0.06
  with the string at rest: an archer's anchor at the cheek, but it hides the hand). A little more room between the bow and
  his face (`WickModel.BOW_AIM_POS`) would fix it in every profile; and the arrow could start at the bow's height. Both
  change today's look, so they wait for the user.
- Evidence: `ga_overlay_secondary_{gasket,wick,rebar}.png`, `ga_secondary_{gasket,wick,rebar}.png` (grounded vs
  grounded_anim, close and game zoom), `ga_gif_gasket_spin.gif` (half speed).
- Tests: `test_move_feel_anim` (`_secondary`: the release pose on the click's frame, the full turn, the spin's hit-stop and
  dust ring, a dummy 2.45 out missed today and hit now, no arm in the body, today untouched).

#### Gasket's spin, a timed sweep (2026-10-22)
The user played the 7-frame whirl: **"It's too fast! It doesn't read as a spin it is so fast."** (The table above is that
first version.) Now:

**Speed decided (user, 2026-10-22, after trying 20/25/30 in the gym with F10): "25 is fine."** 25 frames stays the
default. The spin radius (2.1 vs 1.9) is still open.

- **A slower turn that reads**: a 3-frame twist back with a crouch (the wind-up), the full turn in **25 frames** (0.42 s,
  quick through the middle: a smoothstep), then a **stagger** (she overshoots by 0.35 rad and settles over 12 frames, a
  roll of the body) before the wrench comes back to her side. 0.52 s of whirl from the click.
- **The hit lands where the wrench is**: instead of every target on the click, each target is hit **as the head passes its
  angle**, once per spin (`SpinSweep`, a scheduled effect: the head starts out at her right and goes counter-clockwise from
  above). Measured on eight dummies round her: every hit on the very frame the drawn head passes it (the test allows +-1),
  the last 23 frames after the click, none on the click. Teammates the head passes are shoved as before.
- **Networking**: the spin's start is the `act` every other screen already replays on its puppet at the moment it shows
  the act's time (NetCasts), so each machine runs the same schedule from the same shared moment and applies only what it
  resolves (`Combat.land_melee` / `shove_actors`: the attacker's machine for the monsters and props, each teammate's own
  machine for its hero). Nothing new on the wire; `SpinSweep` is in `test_net_contract`'s scripts (all SPAWN / LOCAL).
- Kept: the radius 2.1 (not decided), the white effects (dust dragged round under the head, a pale ring at the end), and
  a 1-frame hold each time the head passes a target (at most 3 per spin).
- **Try the speed in the gym** (the user: "Rather than render a GIF, can we just test in the gym?"): `.\run.ps1 --gym
  --move-feel grounded_anim`, play Gasket (F2), RMB; **F10** (or the panel's "Spin speed") cycles the turn through 20 /
  **25** / 30 frames live (`SpinSweep.DEV_SPEEDS`; 25 is the pick). No GIF was rendered for this version.

#### Networking
Nothing new on the wire. HeroFeel is cosmetic and declares every var LOCAL (`test_net_contract`); a puppet leans from its
streamed position and plays a replayed swing strike-first (`test_net_move_feel_anim`, two processes: the client takes the
host's `grounded_anim`, each screen leans the other's puppet up to 15-17 degrees, replays both of its swings, snapshots keep
their size). The hit areas are part of the profile, which the host's job sets for the crew, so every machine resolves the
same shape; a hero's hits are still resolved by its owner (`Combat._land_melee`, unchanged rules).

#### Tests
`test_move_feel_anim` (lean / squash bounds, the stride held while shoved and airborne, strike-first timing and hit-stop,
the areas against today's wedge target by target, today and grounded untouched, a puppet, shuffle and the crew data),
`test_net_move_feel_anim` (above). `test_move_feel_today`, `test_move_feel_grounded`, `test_net_move_feel`,
`test_hero_combat`, `test_hero_kits` and `test_net_contract` pass unchanged.

#### Evidence (`docs/design/animation/`)
- `ga_overlay_wick.png`, `ga_overlay_gasket.png`, `ga_overlay_rebar.png`: the hit areas and the weapons' paths, top-down
  (grounded | grounded_anim, and for Gasket and Rebar the wind-up variant).
- `ga_<hero>_close.png` and `ga_<hero>_game.png`: start / stop, strafe and the melee, grounded against grounded_anim (the
  melee also with the wind-up), close and at the game's zoom.
- `ga_gif_<hero>_attack.gif`: the melee lanes side by side, at half speed.
- `ga_held_<hero>.png`: the held component before and after the fix (today and grounded_anim each).

#### Open questions (added)
1. Blind: does `grounded_anim` feel better than `grounded`?
2. Gasket's smash disc at 0.6 (grunt area +51% over today): right, or smaller (0.5: about +35%)?
3. Follow-through (built) or the 2-frame wind-up (`--strike wind`: reads more like a hammer, lands 3 frames after the number)?
4. Squash at 6-7% reads at the close zoom; at the game zoom only the lean reads. More (up to the 16-20% limits)?
5. Should hit-stop scale with the blow (Gasket longer, Wick shorter) and skip in crowd fights (Sakurai's caution)?

---

## 8. Sources

[V] means I opened the page and checked it. [S] means I saw it only through search results or secondary coverage (403,
GDC Vault maintenance, or a video with no readable text). No quote here is longer than 15 words.

1. Hades II Early Access Patch 1 notes (Supergiant, 2024-05-16, via Shacknews): a dash out of attack recoveries "more
   reliably", more responsive turning. https://www.shacknews.com/article/139921/hades-2-early-access-patch-notes-1 [S]
2. Steam thread, Hades II dash complaints: blames locking into attack animations. https://steamcommunity.com/app/1145350/discussions/0/4357872738330399478 [S]
3. Prima Games, "Blizzard reveals how Diablo IV will be different from Diablo III" (2019): added blend, stop and turn animations. https://primagames.com/news/blizzard-reveals-how-diablo-iv-will-be-different-diablo-iii [S]
4. Diablo III animation talk summary (Icy Veins); Julian Love, GDC 2012: responsiveness as a core value. https://www.icy-veins.com/forums/topic/27128-lightning-talk-animation-support/ [S]
5. Stevivor interview, Acid Nerve on Death's Door (2021): kept 2D-action responsiveness in 3D. https://stevivor.com/features/interviews/acid-nerve-talks-deaths-door-interview/ [S]
6. TechRaptor, "How Dead Mage created the art for Children of Morta": a few keyframes, timed in engine first. https://techraptor.net/content/how-dead-mage-created-the-art-for-children-of-morta [S]
7. Passtech, "Behind the Scene Ep. 2" (Ravenswatch, 2024): top-down animation (a teaser only). https://passtechgames.com/?p=4451 [V]
8. David Rosen, "An Indie Approach to Procedural Animation", GDC 2014: few poses, springs, the stride wheel. https://gamedeveloper.com/design/video-an-indie-approach-to-procedural-animation [V]
9. Game Developer, "Crafting the complex, chaotic ecosystem of Rain World" (2017): physics points drive the drawn parts. https://gamedeveloper.com/design/crafting-the-complex-chaotic-ecosystem-of-i-rain-world-i- [V]
10. t3ssel8r, "Giving Personality to Procedural Animations using Math" (2022): second-order f, ζ, r follower. https://www.youtube.com/watch?v=KPoeNZZ6H4s [V, title only]
11. Daniel Holden, "Spring-It-On: The Game Developer's Spring-Roll-Call": dampers, critically damped springs, inertialization. https://theorangeduck.com/page/spring-roll-call [V]
12. David Bollo, "Inertialization", GDC 2018 (Gears of War): snap, then decay the offset. https://www.gdcvault.com/play/1025165/Inertialization-High-Performance-Animation-Transitions [S]
13. Simon Clavet, "Motion Matching and The Road to Next-Gen Animation", GDC 2016: transition clips cut for responsiveness. https://gdcvault.com/play/1023280/Motion-Matching-and-The-Road [S]
14. Alexander Bereznyak, "IK Rig: Procedural Pose Animation", GDC 2016. https://gdcvault.com/play/1022984/IK-Rig-Procedural-Pose [S]
15. Epic, Pose Warping docs: stride warping (scale = speed / authored speed) and orientation warping. https://dev.epicgames.com/documentation/en-us/unreal-engine/pose-warping-in-unreal-engine [V]
16. Jonasson and Purho, "Juice it or lose it" (2012). https://www.youtube.com/watch?v=Fy0aCDmgnxg [V, title only]
17. Jan Willem Nijman, "The Art of Screenshake" (2013); the breakdown at infovore.org: 10-20 ms hit pause, a white frame. https://infovore.org/?p=5275 [V]
18. Mark Brown, "Secrets of Game Feel and Juice" (GMTK). https://amara.org/v/C3BGA [S]
19. Steve Swink, "Game Feel: The Secret Ingredient". https://www.gamedeveloper.com/design/game-feel-the-secret-ingredient [S]
20. GameSpot, Celeste's forgiveness mechanics (2020). https://www.gamespot.com/articles/celeste-dev-explains-how-they-made-their-game-feel/1100-6474775/ [S]
21. Mick West, "Programming Responsiveness" (2008): 3 frames best case; the impulse goes on frame 1. https://www.gamedeveloper.com/programming/programming-responsiveness [V]
22. Mick West, "Measuring Responsiveness in Video Games" (2008): Heavenly Sword attacks 7/60 s, turns 18/60 s. https://www.gamedeveloper.com/design/measuring-responsiveness-in-video-games [V]
23. gameanim.com, "Basics: Fast vs Slow" (2005): short player anticipation, long NPC anticipation. https://www.gameanim.com/?p=115 [V]
24. Sakurai, "Thoughts on Hitstop" (Famitsu, translated by Source Gaming, 2015): scaled, capped, the victim shakes. https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/ [V]
25. SciTePress hit-stop study (2024): best at about 0.1-0.2 s for a 3D attack scene. https://www.scitepress.org/Papers/2024/124614/124614.pdf [S]
26. Liquipedia / Dota 2 wiki: cast point, a cancellable backswing, turn rate (180° in about 0.15-0.19 s). https://liquipedia.net/dota2/Cast_point, https://dota2.fandom.com/wiki/Turn_rate [S]
27. Riot, "Gameplay Clarity in League" (2021): silhouette first, facing at a glance, hit areas match the VFX. https://www.leagueoflegends.com/en-us/news/dev/clarity-in-league/ [V]
28. Riot, "Ask Riot: Let's Talk Clarity" (2021). https://www.leagueoflegends.com/en-us/news/dev/ask-riot-let-s-talk-clarity/ [V]
29. David Gibson, Overwatch character animation, GDC 2016 (summary): overshoot, hold, offset, smears. https://babel.speldesign.uu.se/?p=113918 [V]
30. David Aldridge, "I Shot You First" (Halo: Reach netcode), GDC 2011 (summary): animate on press, hide about 150 ms. https://edgegap.com/blog/game-backend-deep-dive-halo-reach-netcode-host-migration [V]
31. WoW spell queue window (community): about 400 ms. https://us.forums.blizzard.com/en/wow/t/input-lag-spellqueuewindow-and-spell-batching/1210379 [S]
32. Picovoice, latency in speech recognition: conversational gaps of about 100-300 ms. https://picovoice.ai/blog/latency-in-speech-recognition [S]
33. Glenn Fiedler, "Snapshot Interpolation". https://gafferongames.com/post/snapshot_interpolation/ [V]
34. Gabriel Gambetta, "Entity Interpolation". https://gabrielgambetta.com/entity-interpolation.html [V]
35. Valve, Source Multiplayer Networking: a 100 ms interpolation delay, extrapolation capped at 0.25 s. https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking [S]
36. Unreal CharacterMovementComponent proxy smoothing: proxies animate from replicated velocity. https://docs.unrealengine.com/4.27/en-US/API/Runtime/Engine/GameFramework/UCharacterMovementComponent/MoveSmooth/index.html [S]
37. Tim Ford, "Overwatch Gameplay Architecture and Netcode", GDC 2017. https://gdcvault.com/play/1024001/-Overwatch-Gameplay-Architecture-and [S]

---

## 9. Open questions for the user

1. **When should the channel start?**
   - On **speech onset**: it hides the most latency, but every sentence to your friends makes your hero twitch a little.
   - On **the trigger word**: about 0.3 s later, and only when you mean it.
   - The mock does both, at 0.35 and 0.75. Is a small "listening" tell on all talk OK?
2. **Should other players see your channel?** Locally it is free. On puppets it needs a tiny reliable "armed" event
   (about 1 byte per cast attempt), or puppets only show the release.
3. **Gasket's overhead wind-up**: strike-first everywhere, or keep a 2-frame wind for the heavy hitters (Gasket, Rebar) and
   move the big arc into the follow-through?
4. **Exaggeration.** The mock leans up to 22° and squashes up to 16-20%. More cartoon, or less?
5. **Hit-stop on your own screen only** (cosmetic, the model only), or never for the crowd fights (imp clumps)?
6. **The held component during a cast**: make it the glowing focus that lifts, or move it to the off-hand?
