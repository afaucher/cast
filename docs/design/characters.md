# Cast: characters

*A design pass on the playable crew, building on north-star.md, exploration.md and
pitch-contract-sorcery.md. Numbers are relative to today's `Hero`: sword 20 dmg / 0.45 s /
1.6 reach / 100°, bolt 8 dmg / 0.6 s / 12 range, 100 HP, speed 4.5, climb ×0.35.*

> **Names (2026-10-16): the stone golem is REBAR, the dwarf is GASKET and the human archer is
> WICK** (formerly Pebble, Dagna and Larkin). The code, UI and this document all use the new
> names; the old ones survive only in this note and in the filenames of old concept art.
>
> **Roster update (2026-10-16): the crew is three heroes: Rebar, Gasket and Wick.**
> Sir Rattles and Gulp were dropped. Their sections below are kept for reference only.
> The art direction changed too: faceted low-poly "contractor wizards"
> (`docs/design/concepts/contractor_wizards_v1.webp`), not the chunky toy toon in section 4.

## 1. The crew concept

The dispatch platform hires anyone who passes the **voice check**, and species isn't on
the form. So each crew is made of misfits someone else turned away:
- a wizard-school dropout;
- a foundation stone that walked off the job;
- a demolition dwarf;
- a suit of armor with nobody inside.

They're cheap, they're licensed, and they share one headset channel. **Portable
version:** "a crew hired by voice, not pedigree." The gags live in the bodies and kits,
not in the bunker.

---

## 2. Roster

There are four core heroes for the POC and the slice, plus a stretch hero. **Heroes are
unique per crew**, so a hero's signature color is also that player's color.

| | **Rebar** (rock) | **Gasket** (dwarf) | **Wick** (human) | **Sir Rattles** (armor) | *Gulp* (stretch) |
|---|---|---|---|---|---|
| Name options | Rebar, Cobble, Tor | Gasket, Gorm, Brun | Wick, Wendell, Sprig | Sir Rattles, Hollis, Dame Vacancy | Gulp, Marsh |
| Kind | Stonekin golem | Dwarf | Human | Animated armor (empty) | Frogfolk |
| Role | Anchor / control | Brawler / AoE | Ranged / climber | Protector / drop scout | Puller / rescuer |
| HP · speed · radius | 160 · 3.6 · 0.6 | 120 · 4.0 · 0.45 | 85 · 5.0 · 0.35 | 130 · 4.2 · 0.45 | 90 · 4.8 · 0.4 |
| Melee (LMB) | Slam fist | Hammer smash | Bow bash | Sword (today's) | Slap |
| Secondary (RMB) | **Bowl**: rolling shove | **Spin**: 360° whirl | **Arrow**: tap or draw | **Shield**: hold; bash on tap | **Tongue**: pull |
| Quirk | Heavy | Stout + wall-breaker | Light | Hollow | Hops |
| Color | Moss green | Denim blue | Plum | Mustard | Coral |

**As implemented (2026-10-16).** The three kits are data in `scripts/heroes/hero_kit.gd`
(`HeroKit.DATA` and `HeroKit.ARROW`), applied by `HeroFactory.spawn_hero(..., kit_id)` and
therefore also under `--proto-heroes`. Anything not in the table below is unchanged.

| | **Rebar** | **Gasket** | **Wick** |
|---|---|---|---|
| Max HP | 160 | 120 | 85 |
| Primary (LMB / ally melee) | Slam fist: 15 dmg / 0.8 s / reach 1.8 / 120° / shove 1.6 (was 26 / 1.0 until 2026-10-19) | Hammer: 28 dmg / 0.65 s / reach 1.5 / 90° / shove 0.9 | Bow bash: 12 dmg / 0.4 s / reach 1.3 / 90° / shove 0.7 |
| Secondary (RMB / ally ranged) | Bowl (6 dmg to monsters, shoves 3.5, 2.0 s, range 9) | Spin (16 dmg to monsters, reach 1.9, shoves 2.2, 1.4 s) | Arrow, below |
| `shove_mult` | 0 (immovable) | 0.6 | 1.3 |
| Climb +2 | Cannot (`can_climb` false; allies path without climbs) | ×0.25 | ×0.6 |
| Walking speed | 4.5 for everyone (the per-hero speeds in the roster table are not applied yet) | | |

**Wick's arrow (as implemented).**
- **Tap** (RMB pressed and released before 0.7 s): 12 dmg, range 14, speed 22, pierces 1.
- **Draw** (RMB held 0.7 s or more): the next release fires a **drawn shot**: 28 dmg, range 18,
  **pierces up to 3 targets** (each is hit once).
- Both shots share one 0.55 s recovery, and the bow cannot be drawn while it recovers.
- Releasing early fires a tap. Melee, a shove, a stagger or going down lowers the bow without a shot.
- While drawn Wick walks at half speed. A **charge ring** grows under him and turns gold when
  full, and the model's `draw_hold(amount)` pulls the string.
- Not yet: the +30% high-ground bonus, shooting while climbing.

**Names can double as voice callsigns** ("heal Rebar"), so two syllables with a
distinctive vowel work best. Rebar, Cobble, Gasket, Wick, Rattles and Hollis are all
good. **Avoid "Tor"** as a callsign: "Tor", "core" and "corn" sit too close to the corn
hair-trigger.

**Voice check (2026-10-16).** `tools/make_voice_clips.ps1` renders "Gasket heal me", "Rebar watch out",
"Wick come here" and the bare names as negatives: none casts in strict, loose or chaos
(`tests/test_voice_audio.gd`). The recognizer hears "gasket" as GASKET (never "cast"), "rebar" as
REBAR or RIBAR, and "wick" as WICK, WIG or WHITCOMBE, so "Wick" will be the flakiest callsign.

**Character select (as built, 2026-10-19; the user's decisions).** The player picks their hero on the main menu itself.
- **Click a hero in the garage to pick them.** No confirm step. The picked hero walks to the front spot, turned to the camera,
  and strikes its cast pose; the other two step back (`MenuBackdrop.set_featured_hero(id, true)`). Hovering a hero gives it a
  warm outline and a faint lift (`set_hover`), and the pointer becomes a hand. The hit test is the camera's ray against each
  model's own mesh bounds (`MenuBackdrop.hero_at`; the nearest hit wins), with no physics.
- **Keyboard and controller:** the personnel file's NAME line is the last stop of the menu's focus chain (after Quit); Left /
  Right step through the three, Enter steps on. The key strip under the forms says "Left Right HERO" while it has focus; the
  paper says nothing about keys.
- **FORM 31, Personnel file** (`PersonnelFile`, `scripts/ui/personnel_file.gd`, green carbon) lies under the work order's
  clipboard on the left third. Printed captions, typed values: NAME, ROLE (one deadpan line per hero, the only text kept in
  the card: "Tank. Immovable. Not a closer."), HP, PRIMARY (name and damage), SPEED (the primary's cooldown), SECONDARY
  (name, damage, cooldown), CLIMBING, WEIGHT. Every number is read from `HeroKit` (and, for bowl and spin, `Hero`'s
  constants). Box bars (ten printed boxes, typed X's) put the three on one scale per stat: the best of the three fills all
  ten (HP, primary damage, swings per second, +2 climb pace, and weight, where immovable fills all ten). The card is retyped
  (with the paper sound) whenever the pick changes.
- **Saved:** `GameSettings` key "character" in user://settings.cfg; `Boot` loads it into `Session.character_id` at start
  and the menu reads it again from its own settings file. `--backdrop-hero <id>` (menu) and `--hero <id>` (game) pick for
  one run without saving. Picking is locked while a crew is opening or open (the roster already carries the pick).
- **Solo:** seat 1 is the pick; the AI seats are the other two (`CrewSeats.fill`): an AI seat keeps its own hero (seat 2
  Rebar, seat 3 Gasket) when nobody plays it, else takes the first free one of Rebar, Gasket, Wick. Wick: AI Rebar (2) and
  Gasket (3), as before. Rebar: AI Wick (2) and Gasket (3). Gasket: AI Rebar (2) and Wick (3). The formation spots stay per
  seat (`game.gd` `AI_SEATS`); an AI Wick keeps its distance and shoots (`AllyBrain.prefers_ranged`, from the arrow kit).
- **Online:** the roster carries each player's pick (`hello` -> roster "character"). Two players may pick the same hero
  (allowed). The AI seats play the heroes nobody human picked, the same `CrewSeats.fill` over the roster on every machine (so
  the floor checksum agrees); a duplicate only if all three are taken, which three seats never need. A player who leaves
  gives the seat back to the AI as a hero nobody else plays (`CrewSeats.ai_for`, `SeatHandover.ai_character`), which is the
  hero the next floor gives that seat too. A late joiner still takes an AI already playing its pick first
  (`SeatHandover.pick_seat`).
- **What assumed Wick:** seat 1's character in solo (`game.gd` `_crew_seats`), the fixed AI table (`AI_SEATS` held each seat's
  character), the "original character" a dropped seat went back to, the AI brains (always melee), the `--kit-demo` and
  `--give-allies` dev flags (seat order), and comments about the van and elevator spots (they are by seat, whoever plays it).
  The HP carry between floors was already keyed by seat. `PlayLog` gained a `hero` column. Tests: `tests/test_character_select.gd`.

### Rebar: the rock
*A gentle, slow-talking boulder, formerly the bunker's foundation stone. Loves the team and
never notices what it's standing on.*

- **Silhouette:** the widest footprint, a lumpy boulder disc.
  - The 62° pitch shows mostly **tops**, so Rebar reads as a moss cap with a tiny hard
    hat.
  - It's **pale sandstone**, never slate, which would vanish into the dark hex columns.
  - No glowing eyes: glowing eyes mean "enemy".
- **Melee, Slam fist:** 15 dmg / 0.8 s / 1.8 reach / 120° / shove 1.6 (trimmed from 26 on 2026-10-19: a tank, not the killer).
- **Secondary, Bowl:** Rebar tears a boulder off its shoulder and bowls it at the aim
  point.
  - 6 dmg, or **0 to teammates**. Cooldown 2.0 s, range 9 (about 5 hexes), speed 8,
    hit radius 0.6.
  - **Pierces** and hits each actor once, shoving it **2 hexes along the roll**.
  - That includes **teammates**. The brute moves only 1 hex, and bosses are immune.
  - The boulder rides the terrain: it rolls off drops and crumbles at a +2 rise or a wall.
  - The shoulder boulder regrows over the cooldown, so the cooldown reads on the model.
- **Quirk, Heavy:** steps up +1 only, so **no +2 climbs** (like the brute): `Hero.can_climb` is
  false and the ally brain paths without climbs. It can't be shoved (`shove_mult` 0).
  - *P2 "Leg-up":* an ally next to a still Rebar can use it as a step onto +3 ledges.
- **Weakness, the brute's daze** (as built 2026-10-19, see "The daze" below): being immovable doesn't help. A direct
  slam stops Rebar swinging for 0.6 s, so face-tanking a brute costs him his punches. Standing at arm's length (his fist
  reaches 1.8, the daze line is 1.6) keeps him swinging.

#### The daze (as built, 2026-10-19)
The brute's slam **dazes** a hero it hits squarely. It's the first status that takes control away from a hero, and so
far only the brute deals it.

| | |
|---|---|
| Trigger | The brute's slam, a **direct hit**: the hero's centre within **1.6** of the brute (`Brute.DAZE_RADIUS`, of the 2.0 ring). The band from 1.6 to 2.0 only hurts. The slam's damage still falls off linearly from 25 at the centre to 12.5 at the rim (there was never a flat full-damage zone), so a dazing hit deals about 15-25 |
| Telegraph | A fainter amber inner ring at 1.6 inside the brute's red wind-up ring: inside it you get dazed. The brute stops at 1.5 from its target, so its target is inside unless it steps back during the 0.9 s wind-up |
| Length | **0.6 s** (`Brute.DAZE_TIME`) |
| While dazed | No walking, no melee, no secondary (bolt, bowl, spin, arrow), no new bow draw. A draw in progress is cancelled. A swing or spin is instant, so there's nothing in flight to cancel; the weapon's swing animation is cut |
| Immovable doesn't help | The daze ignores `shove_mult`: Rebar stays put but stops punching |
| Voice | **Casts are never blocked.** A spell spoken during the daze goes off at once, exactly as it would otherwise (nothing is held or dropped) |
| No stun-lock | After a daze ends, **1.5 s** of immunity (`Actor.DAZE_GUARD`): two brutes can't chain it. A slam in that window still hurts and shoves |
| Monsters | Never dazed. The slam only hits heroes, and a brute's restless-fight slams (on a rival brute or a skeleton) shove without dazing, so those fights stay posturing |
| Readable | Three yellow stars spin over the hero's head, the model reels from side to side, and "*bonk*" pops up with a few sparks as it lands (`DazeFx`). Your own hero also gets a small camera bump and **DAZED** beside your name on the HUD |
| AI allies | `AllyBrain` waits it out (a dazed hero is `is_helpless()`), then fights on |

Networking: the daze is a status on the hero, so the hero's owner applies it. The brute's wind-up is an event, each machine
resolves the strike on its own hero (`Monster.net_strike` -> `Combat.slam` -> `Actor.daze`), and the daze is a modifier
(`Actor.STAT_DAZE`, id `daze`) that the owner announces like armor or a root (`NetStatus` "mods"). The other screens show
the stars from it, with no grace period added, so the stars leave every screen together. The 1.5 s immunity is the owner's
private bookkeeping. `test_daze` and `test_net_daze` cover it.

**Shoving teammates: yes.** It's the roster's main source of player-caused chaos *and* a
skill tool. Bowling a friend out of the brute's slam ring is a rescue. It passes the
north-star filter:
- **Readable:** a big rolling ball.
- **Attributable:** there's one rock per crew.
- **Recoverable:** 0 damage, and a fall caused by a teammate never downs anyone.

| Shoved across… | Result |
|---|---|
| Flat, or a rise of 1 | Slides on |
| A rise of 2+, or a wall | Stops. **Wall slam:** +8 dmg and a 0.5 s stagger (enemies only) |
| A drop of 1–3 | Falls. A 2–3 drop staggers for 0.6 s, with no damage (walking allows these drops) |
| A drop of 4+ (walking forbids it) | Allowed. 0.6 s stagger and **6 dmg per level beyond 3** (max 40). A teammate-caused fall leaves a hero at least 1 HP |
| Void | Monster: **ring-out**, dies (not bosses). Hero: "fished out" to the last safe cell after 3 s, 10 dmg, never downed |

**Uses:**
- Bowl archers off their perches.
- Bowl the brute into a 3-deep pit. It can't climb, so it walks round to the stairs.

### Gasket: the dwarf
*A demolition foreman who believes every problem is a wall. Cheerful, loud, slightly
singed.*

- **Silhouette:** two-thirds of a human's height and wide.
  - From above: a round denim hard hat, a beard spilling forward (that shows facing), and a
    big hammer head.
  - The hammer glows ember only during swings.
- **Melee, Hammer smash:** 28 dmg / 0.65 s / 1.5 reach / 90°.
- **Secondary, Spin.** Gasket has **no ranged attack.**
  - **Tap:** a 360° spin. 16 dmg, reach 1.9, 0.35 s, cooldown 1.4 s.
  - **Hold:** whirl for up to 2.5 s at 70% speed, dealing 10 dmg every 0.3 s. It knocks
    swarmers 1 hex outward.
  - A full whirl leaves Gasket **dizzy** for 1 s (steering wobbles ±40°).
  - No spinning while climbing, and the spin never hurts teammates.
- **Quirk, Stout:**
  - Shoved at ×0.6 (`shove_mult`), and climbs +2 slowly (×0.25).
  - **Wall-breaker:** cracked secret walls glint for her from 6 hexes and break in one
    swing (others need about 5).

### Wick: the human
*A lanky wizard-school dropout who kept the hat and took up the bow. Points first, aims
second.*

- **Silhouette:** tall and thin.
  - A long, crooked wizard hat, the tallest diagonal on screen.
  - A **headlamp** on the hat throws a short cone that shows facing.
  - An improvised bow (a bent tent pole). The concept art's ladle-wand becomes a taped-up
    wand, so nothing reads as kitchenware.
- **Melee, Bow bash:** 12 dmg / 0.4 s / 1.3 reach / 90°. Pushes the target back 0.5 hex.
- **Secondary, Arrow:**
  - **Tap:** 12 dmg / 0.55 s / range 14 / speed 22.
  - **Hold to draw (0.7 s):** 28 dmg, pierces 3, range 18.
  - High ground gives Wick +30% (others get +15%).
- **Quirk, Light:**
  - Climbs +2 at ×0.6, and is the only hero who **can shoot while climbing**.
  - Shoves carry Wick ×1.3 as far (`shove_mult` 1.3).

### Sir Rattles: the armor (DROPPED)
*An empty suit of armor honoring a 400-year-old contract. Very polite, very literal.*

- **Silhouette:** medium height.
  - From above: a cross of big pauldrons, with a mustard plume and tabard.
  - The visor glows faint warm, never spell-cool.
  - **Plates fall off as HP drops.**
- **Melee, Sword:** today's exactly, 20 / 0.45 s / 1.6 / 100°.
- **Secondary, Shield:**
  - **Hold:** blocks all projectiles in a 120° front arc, which covers allies behind it.
    Frontal melee damage −60%, move at 40%.
  - Shield up, it can't be shoved from the front: a bowled boulder stops with a "bonk".
  - **Tap, Bash:** 6 dmg, a 1-hex shove, and it interrupts grunt and archer wind-ups (not
    the brute's). Cooldown 1.0 s.
- **Quirk, Hollow:**
  - Walks off drops of **up to 6 levels** (others: 3) and never takes fall damage.
  - It **falls apart on landing** and reassembles over 1.2 s: it can't act, and takes +25%
    damage meanwhile.
  - Downed, it's a pile of plates; a revive puts the helmet back on.

### Gulp: the frog (stretch, DROPPED)
*A damp, unbothered frogfolk who joined for the dental plan.*
- **Tongue,** within 5 hexes. It pulls one of these 2 hexes toward Gulp:
  - an enemy;
  - a teammate in trouble.
  - Or it pulls Gulp itself onto a ledge up to +3.
- It's the pull to Rebar's push.
- **Slap:** 14 / 0.4 s / 1.4 / 90°.
- **Quirk, Hops:** climbs +2 at walking speed.

### How they play together

**Each hero moves differently, so every floor is a route puzzle:**
- Rebar is ground-only (+1 steps).
- Gasket climbs slowly.
- Wick climbs fast.
- Sir Rattles takes drops nobody else can.

"Who can get up there?" becomes a voice call.

| Well-oiled combos | Fun chaos |
|---|---|
| **Spinning top:** Gasket holds Spin and Rebar bowls her through the pack, hitting all the way | Rebar bowls Gasket into the brute *mid-wind-up*, not spinning |
| **Bowling for archers:** perched archers get bowled off, straight into Gasket's spin | Rebar bowls Sir Rattles off a 5-level ledge: "you knocked my head off" |
| **Pool party:** the brute gets shoved into a 3-deep pit, and Wick snipes from the rim at +30% | Wick (light, 3 hexes) gets bowled into the infinity pool |
| **Shield wall:** Sir Rattles shields, Wick draws full shots from behind, and someone armors the knight | Gasket whirls the full 2.5 s, gets dizzy and wobbles off a ledge |
| **Rescue bowl:** a friend gets bowled out of the slam ring for 0 damage | The rescue bowl shoves the *other* friend in |
| **Drop scout:** the knight takes the 5-level drop and calls the stair route | The knight lands in a nest and falls apart in the middle of it |

**Guardrails:**
- Shoves never damage teammates.
- The reticle turns hazard-yellow when a bowl's path crosses a teammate. It's a warning,
  not a block.
- The end screen shows "Teammates bowled: Rebar, 7".

---

## 3. Spells vs heroes

**Recommendation: open loadouts.** Any hero can slot any spell, with no affinities in the
POC.
- **Voice is personal.** Gating a word behind a hero forces some players onto words they
  say badly. Rebindable words only work if players own their vocabulary.
- **Two axes give more combos.** The hero sets the *body role*, and the spells set the
  *voice role* (Warden, Cantor, Evoker, Cornjurer). A healing Rebar is a valid crew.
- **P2 signature twists:** a small bonus when a hero slots one particular spell. These are
  flavor, not restrictions:
  - **Rebar + armor:** allies in the zone can't be shoved, so you can bowl straight
    through them.
  - **Gasket + armor:** a spin reflects arrows.
  - **Wick + fireball:** range 16 → 20.
  - **Sir Rattles + heal:** reattaches plates and adds a 15-point shield.
  - **Corn gets no twist**, ever.

---

## 4. Visual style

### Recommendation: chunky toy toon, built from rigid parts

- **Proportions:** "heroic chibi", about **3 heads tall**. Big hats, hands and weapons,
  and short legs.
  - A 2-unit hero is about **45 px tall at 1080p** at default zoom.
  - The pitch shows more top than side, so **hats, shoulders and weapons carry identity**;
    faces don't.
- **Rigid chunks:** every hero is built from separate parts (plates, boulders, hat, beard,
  limbs). That gives:
  - the improvised-gear look;
  - cheap animation;
  - a shared "falls apart" gag.
- **Shading:**
  - A 2-band toon ramp.
  - An inverted-hull outline in **dark warm brown**, constant in screen space (about
    2 px).
  - A thin rim light in the hero color to separate the hero from the slate.
  - Heroes take the warm downlights like the crates do.

**Color language:**

| Layer | Owns | Rule |
|---|---|---|
| Spells | Cyan, violet, heal green, armor blue, fire orange, corn yellow | Only spells are **emissive and saturated** |
| Enemies | Red-orange skin, glowing eyes | Glowing eyes = enemy |
| Environment | Slate, amber seams, wood, brass | Heroes never use these as a main color |
| Hero / player | Moss, denim, plum, mustard, coral | **Matte**, mid-saturation, on the biggest top-visible shape |
| Crew | White retroreflective strips (vest, sash, tabard) | Reads "friendly" against red imps |

Test mustard against the hazard tape and denim against armor blue with a **grayscale
screenshot**: each hero must still read from its top silhouette alone.

**States:**

| State | How it shows |
|---|---|
| Hit | White flash (exists) plus a squash |
| Low HP | On the model: missing plates, rock cracks, a dented hard hat, a bent wizard hat |
| Armored | A hazard-tape ring at the feet; the outline turns emissive blue |
| Climbing | A climb pose and dust, plus a small ↑ chevron (exposed to +25% ranged damage) |
| Shoved, dizzy | Tumble and streaks; orbiting stars |
| Downed | Desaturated, with a revive ring in the hero color. Rebar becomes a cairn and Sir Rattles a pile; Gasket slumps; Wick's hat covers his face |

**Alternatives:**
- **Paper-cutout billboards.** The most "comic", crisp at small sizes.
  - Lighting clashes with the 3D terrain.
  - Awkward at the steep pitch.
  - Huge frame counts.
- **Flat low-poly, no outlines.** The fastest, but generic, and the heroes separate poorly
  from the busy floor.

---

## 5. How we build them

| | (a) Code primitives (today) | (b) Blender low-poly + toon | (c) 2D sprites | (d) AI image-to-3D | (e) Asset packs |
|---|---|---|---|---|---|
| Cost | ~1 day/hero, agent-writable | 2–5 days/hero (non-specialist) | ~240 frames/hero (8 anims × 5 dirs × 6) | Mesh cheap; cleanup isn't | Lowest, for humanoids |
| Animation | Rigid-part tweens (swings exist) | Rigid parts or simple skinning → AnimationPlayer | Every frame drawn | Auto-rig is humanoid-only | Shared humanoid sets; no golem |
| Consistency | High | High (shared template) | Hard | **Low**: style drifts per generation | Medium; mixing packs clashes |
| Readability at 45 px | Good if silhouettes are designed | **Best** | Very good, but unlit | Poor: noisy, baked lighting | Good (chunky) |
| Iteration | Fastest | Medium | Slow | Fast, then slow | Fast |
| Risk | "Toy" ceiling | Skill bottleneck | Volume; sorting on height levels | License terms; cleanup overruns | Asset-flip look |

**Licenses:**
- KayKit, Quaternius and Kenney character packs are published as **CC0** (commercial use,
  no attribution). Confirm the license file in each download.
- Image-to-3D terms vary by tool and tier. Some free tiers restrict ownership, and
  Hunyuan3D's license excludes some regions. Check before anything ships.

**(i) Next 2 weeks (POC): (a), upgraded.**
- Build a **`HeroRig`**: rigid parts behind `play(&"melee")` / `set_state(&"climbing")`,
  animated by tweens. A glTF with an AnimationPlayer can replace it later behind the same
  API.
- Add a shared toon-ramp and outline material.
- Build all 4 heroes as primitives.
- Run a **one-day spike**: KayKit's knight next to ours at the default zoom, to see whether
  real models buy anything at 45 px.

**(ii) Vertical slice: (b), rigid-part low-poly, toon-shaded.**
- **AI images for concept sheets only**, never for final meshes.
- One proportion template, about 1.5–3k triangles, palette-texture colors.
- Rigid parts mean no skin weights, and they keep the falling-apart gags.
- Kitbash CC0 helmets and weapons where they fit. Model Rebar and Sir Rattles custom.
- Budget about 1 week per hero, with animation.

**Animation set (every hero; POC and slice unless marked):**
1. idle
2. walk
3. climb +2 (Rebar: a "can't" shrug)
4. drop/land (Sir Rattles: fall apart and reassemble)
5. melee
6. secondary: bowl; spin tap and loop; draw and release; shield up and bash
7. cast gather loop: starts on `voice_activity(true)` to hide recognition latency
8. cast release
9. hit react
10. shoved tumble, stagger and dizzy
11. downed (fall and loop)
12. revive
13. *(slice only)* a victory emote for the end screen

---

## 6. Feasibility: the shove against today's code

**Today:**
- `Actor.move()` is **voluntary** movement.
  - It probes with `HexMap.movement_check`: a rise above 2.05 levels or a drop above 3.05
    is blocked.
  - It slides along blocked edges, and `snap_to_ground` lerps Y.
- `Combat.melee_arc` already works at 360°.
- Melee and projectiles only hit the other team.

**A shove needs:**
1. **`Actor.knockback(dir, hexes, source)` and `tick_forced(delta) -> bool`.** Hero and
   Monster call `tick_forced` first in their physics tick and skip AI and input while it
   returns true. Don't route shoves through `move()`, which refuses drops.
2. **`HexMap.shove_check(from, to)`** → OK / WALL_HIT / FALL(levels) / VOID. Walking rules
   stay unchanged.
3. **A short gravity fall state.** The 14/s lerp looks floaty for big drops. Apply the §2
   damage and stagger on landing.
4. **Void handling.** Over void, `ground_height` is NAN and `snap_to_ground` returns, so a
   shoved actor would **hover**. Ring-out and fish-out must be explicit.
5. **A leash fix.** A monster shoved beyond `leash_range` (18) goes to RETURN and **heals to
   full** at home. Re-home it on a forced fall, or pause the leash after a shove.
6. **Monster stagger.** Add `stagger_until`: it cancels the wind-up and freezes the state
   machine.
7. **The Bowl projectile.** `Projectile` stops at the first hit and only targets the other
   team. Bowl needs pierce, a hit-once set, both teams minus the caster, and ground riding.
8. **Re-pathing after a fall** already works. But a brute in a pit with no stair route
   gets stuck, so the **generator must guarantee a no-climb way back from every one-way
   drop**. That also keeps Rebar from being stranded.

---

## 7. Next steps (in order)

1. **`HeroDef` resource:** per-hero stats, climb factor, shove weight, attack parameters,
   color and rig. `HeroFactory` spawns by id.
2. **Shove physics:** knockback, `shove_check`, falls, void, stagger and the leash fix.
   Test a +3 drop, a +5 drop, a +2 wall, void, and the brute.
3. **Rebar's Bowl,** plus the reticle warning when its path crosses a teammate.
4. **Gasket's Spin:** tap, hold, dizzy.
5. **Wick's draw shot** and shooting while climbing; **Sir Rattles' shield** and bash.
6. **Movement quirks:** Heavy, Stout, Light and Hollow. AI-ally pathing respects them.
7. **`HeroRig`** with toon and outline materials. A placeholder art pass on **Sir Rattles
   first** (closest to today's hero), then the other three.
8. **KayKit comparison spike.**
9. **Generator:** a no-climb way back from every one-way drop.
