# Pavise Crossbowman: read test (2026-10-20)

The user (2026-10-19): "The crossbowman - I like the idea of the bigger threat but I am not sure how it will visually
read. Lets test it out." This tests the look of `combat-proposals.md` §2 (and touches §2.8). It is a lab only: no
Monster kind, nothing in `MonsterModels`, no net code.

- Model: `scripts/art/lowpoly/monsters/pavise_model.gd` (`PaviseModel`): the final look, two crossbow carry styles,
  five shield states, the aim and lock, reloading, and stuck arrows. It is in the z-fight registry (`ZFightModels`:
  `pavise/<carry>/<state>`, `/reloading` and `/arrows`) with no findings over 1 cm2.
- `tests/test_pavise_model.gd` checks that the crossbow never passes through the pavise. It covers both carry styles,
  every shield state, a walk cycle and the whole raise from reloading to aiming (21 steps). The check is
  `PaviseModel.bow_shield_overlap()`: every vertex, edge midpoint and face centre of the stock, prod, string and bolt
  is tested against the pavise's solid (the boards, paint and rim, less the notch above its saddle, plus the braces and
  grip on the back).
- Lab: `scenes/pavise_lab.tscn` (`pavise_lab.gd`) uses the game's terrain and light (`HexMapView` + `DungeonLook`) and
  the game camera (orthographic, yaw 45, pitch -56, size 24, 1920x1080). The "close" views are size 9 at the same
  angle.
  `godot --path . --resolution 1920x1080 -- --scene res://scenes/pavise_lab.tscn --shot <dir>/pavise.png`
  Each game-size view also writes a `_crop` file: the area round the pavise at 2x, nearest neighbour, so you see the
  game's own pixels.

## Revision (2026-10-20): decided, and the final look

The user, after the first pass below: "The crossbow man, generally very good. The at-rest crossbow penetrates the
shield. We probably want either to the side or above. No floor arc. The shield should read okay. The shield should
always block while carried. No searchlight version. No armoured one for now, maybe that style would be good for another
enemy." Recorded in `combat-proposals.md` §2.0.

- **Final look:** C's paint on A's build. The pavise has a crimson front with a bone border and a bone skull, and a raw
  pale-wood back. The doc's flat top with its sight notch, iron rim, foot spike and prop leg stay. It is 15% wider than
  the first pass: 1.24 x 1.87 world units. The notch now has an iron saddle the stock rests on. The skeleton wears a
  crimson tabard. The bolt head is oversize and always glows.
- **The shield blocks while carried as well as planted.** The arc and the test are the same; only the turn rate differs
  (150°/s carried, 60°/s planted).
- **No floor arc.** The front is the shield's own read (the painted front, the raw back), with arrows that stay stuck and
  the blocked hit's spark and grey "0".
- **Dropped:** D, the searchlight version, is not built. **Parked:** B, the armoured heavy, is "a style for a different
  enemy later", not built. The first-pass code for A to D is in git history (`489ef45`).
- **The crossbow clipping fixed.** The first pass reloaded with the bow held nose-down behind the shield, through the
  boards. Now the crossbow never passes through the shield in any state, and the test checks it. Two placements:

  | | (a) "side" | (b) "above" |
  |---|---|---|
  | Walking | Slung nose-down at the right hip, the prod along the body, outside the shield's edge | Shouldered: the stock on the right shoulder, nose forward and up over the shield's top |
  | Reloading (planted) | Nose down at the right side, the foot in the stirrup, cranking | Laid over the top rim in the notch, nose up, the butt drawn back, cranking |
  | Raising to aim | A long move: lifted nose-up outside the edge, swung level over the top, lowered into the notch (three steps, or the boards are in the way) | A short tilt: the nose comes down until the stock lies level on the saddle |
  | Aiming | In the notch, the stock on the saddle, the prod and glowing bolt head in front of the boards | the same |
  | Shoved off, dropped, broken | Held low in both hands (the same in both styles) | the same |

### Recommended: (b) "above"

- **The front stays marked in every state.** The glowing bolt head sits above and in front of the shield's top while it
  walks, reloads and aims, so even a carried shield points somewhere. In (a) the bolt head hangs by the right foot, and
  from the front three-quarter view the slung bow is hidden behind the boards.
- **The aim reads as one motion.** Reloading over the rim to aiming is a short tilt down into the notch. In (a), going
  from the hip to the notch without touching the shield takes a three-step swing round its edge, which is busier to
  animate and reads less clearly in the 1.2 s aim.
- **The shield keeps its silhouette.** Nothing hangs off its side. The cost is a busier top (the prod next to the
  skull). At size 24 it still reads as "a skull and a crossbow over a red door".
- (a) is fine if the user wants the cleanest top: the shield's top edge and the skull read alone while it walks.

### The v2 renders

In the session scratchpad, `pavise\v2\`:
- `pavise_states_close.png`, `pavise_states_game.png` (+ `_crop`): walking, raising the bow, aiming (locked) and
  reloading. Top row (a) side, bottom row (b) above.
- `pavise_facings_close.png`, `pavise_facings_game.png` (+ `_crop`): walking, then aiming from the front, side and back,
  in the same rows.
- `pavise_exposed_close.png`: shoved off it, dropped and broken.
- `pavise_aim_track_crop.png`, `pavise_aim_lock_crop.png`: the telegraph on Wick in a pack. A dashed floor line while it
  tracks (0.8 s), then a solid one when it locks (0.4 s).
- `pavise_arrows.png` (+ `_crop`), `pavise_arrows_close.png`: stuck arrows and a blocked hit.
- `pavise_lineup.png` (+ `_crop`): scale against the crew and the monsters.
- `pavise.png`: the contact sheet.

The first pass's renders are in `pavise\`.

---

## First pass (superseded where the revision above differs)

### The variants

| | Look | How it tries to read |
|---|---|---|
| **A doc** | The grunt skeleton behind a door-sized pavise (1.9 x 1.1) of dark planks, with an iron rim, three red chevrons, a sight notch, a foot spike and a prop leg; a heavy crossbow with a crank | The doc's version: a dark rectangle with a skull over it |
| **B heavy** | A plate-armoured skeleton at 1.42 scale (2.6 tall, close to Rebar), a great helm with an ember slit, spiked pauldrons and a steel arbalest, behind a chest-high mantlet of pale wood | The threat is the body; the shield is light |
| **C painted** | A's skeleton in a crimson tabard. The front is painted crimson with a bone border, a bone skull and a ridge. The back is raw pale wood. Pointed-arch top. The bolt head is twice the size and hot yellow, and glows all the time | Colour says which side you see; the bolt head reads at range |
| **D lamp** (extra) | A security skeleton (peaked cap) behind a steel riot slab with a red-and-white base band and a searchlight. The lamp lights the floor in front. While aiming it turns red and narrows to a spot on its target | Light shows the facing; the telegraph is the light itself |

### What reads at size 24, and what doesn't

- **The front reads, in every variant.** A planted pavise facing the camera reads as a flat rectangle with a skull over
  it. No other monster has that shape (`pack_*_front_crop`). **C reads best**: it is the only bright rectangle on the
  floor. **A's dark planks sink into the dark slate floor**, and only the chevrons and the iron rim carry it. **D's grey
  slab** is grey on grey, carried by its striped band. **B's mantlet** is a small box under a big steel body.
- **The back mostly doesn't read.** From behind, A, C and D look like a grunt holding a crossbow up: the skeleton
  covers most of the shield, and the steep camera puts what's left of it above and behind the body
  (`pack_*_back_crop`, `compare_gray`). In gameplay terms that's right, because the side you can hit looks hittable.
  But players won't know it's the pavise unit until it turns. C's pale back helps a little (a light frame round the
  skeleton). B is the exception: its armoured back is distinct from any grunt.
- **Side-on, the shield is a thin line.** The bolt head, sticking out of the front, is what says which way it faces
  (`pack_*_side_crop`).
- **Walking with it reads** (a moving door with a skull and a shouldered crossbow). The difference between planted
  and walking is small at 24: the bow comes up into the notch and the bolt head flares. The prop leg is only visible
  side-on.
- **Grayscale** (`compare_gray`, `compare_both`): A, B and D hold their shapes. C's crimson drops to a mid-grey close
  to A's planks, and the bone border and skull carry it. B is the clearest silhouette without colour. From behind,
  only B is told apart.
- **The aim telegraph** (`aim_<mode>_<v>`):
  - The bolt head's glow alone shows *that* it's aiming, not *at whom*.
  - The dashed floor line while tracking is readable but faint.
  - **The solid floor line when locked reads best**: it is anchored at the target's feet, so "line on you" is
    unambiguous.
  - A raised beam from the bolt head to the chest is thinner and crosses other figures in projection, so it's harder
    to read who it ends on.
  - D's red spot works as "a light is on you", but at a grazing angle it smears into a long ellipse, which is less
    precise than a line. It also costs a real light per monster.
  - **Use glow + dashed line (tracking) + solid line (lock).** C's oversized hot bolt head is the most visible glow.
- **Stuck arrows read** (`arrows_*`). Wick's coloured fletchings make a bright bristle on the front even at 24, and
  they point back at the shooter. The blocked-hit spark plus the grey "0" (the chicken's style) also read at 24.

### Is "the front blocks" legible from the fixed camera?

**Half.** Facing the camera, yes: the painted front is clear. Facing away or side-on, no: from behind, the player sees
a skeleton and nothing says "go round, it's open here", or "it's the shielded one". Fixes, tested in `cues_<cue>`
(variant A in five facings):

1. **A front-arc band on the floor (`cues_arc`): the strongest fix.** A thin red arc at about 2 units round the front
   (the shield's ±70°), with a faint fill. It shows the blocked side from every facing, including edge-on and from
   behind, and it uses the floor language the game already has (slam rings). Show it only while planted; it costs no
   light. This reads best of everything tested.
2. **A front-edge glint (`cues_glint`)**: ember strips round the front's edges. It reads when the front is visible,
   which is when you least need it. A small help, not a fix.
3. **The blocked hit**: the spark, the "0" and arrows that stick. This teaches the rule after one or two wasted shots.
   Keep it; it's cheap.
4. **Front ≠ back colour** (C): a bright painted front and a raw back. It helps any facing that shows a sliver of
   either face.

### Recommendation

**Variant C's paint on A's build, plus the floor arc and the solid lock line.**

- Keep the doc's skeleton and door-sized pavise (A's proportions, the notch, the spike, the prop leg). Paint the front
  bright (crimson, a bone border and skull) and leave the back raw pale wood. Use C's big hot bolt head.
- Make the pavise about 15% wider than now (1.25 instead of 1.08 in world units) so the back keeps a visible frame
  round the skeleton.
- Planted: the red front-arc band on the floor. Aiming: the glowing bolt head, the dashed floor line while tracking
  (0.8 s), then the solid line on lock (0.4 s).
- Blocked hits: the spark, the grey "0", and arrows that stay stuck.
- Keep B in mind as a later "elite" or floor-3 version: it's the best silhouette, but its small shield contradicts
  "the front blocks" (the body sticks out above it).
- D's lamp is a strong mood piece for bunker sites. As a gameplay cue, the floor arc does its job without a light.

**Stat and behaviour tweaks the look implies:**

- **Keep the aim time.** C's glowing bolt head and the floor line make it the most visible thing in a room
  while aiming, so the 1.2 s aim can stay. Don't shorten it.
- **Show the arc only while planted.** It's the planted pavise that blocks from one side; a carried shield turning at
  150°/s would make the arc spin and stop being useful. Consider making the carried shield block only arrows (not
  spells), so the rule the arc teaches is simple: "red arc = blocked".
- **Turn rate 60°/s planted matters for the read**: the arc must visibly lag behind a flanker, or flanking won't feel
  like it worked.
- **From behind it looks like a grunt**, so a crew that flanks it should be rewarded loudly: a bigger hit spark or
  number from behind. A back-stab bonus isn't needed; the 70 HP from the doc is fine.
- **HP 70 / bolt 18** look right for its size next to a grunt (40) and the brute (140): it reads as "bigger than a
  skeleton, smaller than a brute". B's bulk would read as about 120 HP and invite melee, which is another argument
  against B for this role.

### Questions for the user

All five are answered in the revision above: (1) C's paint, (2) no floor arc, (3) the carried shield blocks too, (4)
no searchlight, (5) the armoured style is parked for another enemy.

1. C's paint (a crimson front, a raw back) or the doc's dark planks with chevrons? C reads far better at 24, but it's
   louder, and close to the brute's reds.
2. Is a red floor arc while planted acceptable? It's the one fix that makes "protected from one angle" legible from
   behind.
3. Should the carried shield block, or only the planted one? A carried block can't be shown cleanly.
4. D's searchlight: worth keeping as a bunker or "security" variant for the luxury interiors (question 11 in the
   proposals), or drop it?
5. B as a later elite (a heavy arbalester), or not at all?

### Renders (first pass)

All in the session scratchpad, `pavise\` (`pavise_<view>.png` and `pavise_<view>_crop.png`). The main ones:

- `compare_both`, `compare_gray`: the four variants side by side, in colour and in grayscale
- `lineup`: scale against the crew and the monsters
- `solo_<v>`, `close_<v>`
- `pack_<v>_<front|back|side>`, `aim_<mode>_<v>`, `arrows_<v>`, `cues_<none|glint|arc>`
