# Pavise Crossbowman: read test (2026-10-20)

The user (2026-10-19): "The crossbowman - I like the idea of the bigger threat but I am not sure how it will visually
read. Lets test it out." This tests the look of `combat-proposals.md` §2 (and touches §2.8). It is a lab only: no
Monster kind, nothing in `MonsterModels`, no net code.

- Models: `scripts/art/lowpoly/monsters/pavise_model.gd` (`PaviseModel`, four variants, five shield states, the aim, a
  lock, stuck arrows, two front cues). They are in the z-fight registry (`ZFightModels`: `pavise/<v>/<state>` and
  `pavise/<v>/arrows_cues`) with no findings over 1 cm2.
- Lab: `scenes/pavise_lab.tscn` (`pavise_lab.gd`) uses the game's terrain and light (`HexMapView` + `DungeonLook`) and
  the game camera (orthographic, yaw 45, pitch -56, size 24, 1920x1080). The "close" views are size 9 at the same
  angle.
  `godot --path . --resolution 1920x1080 -- --scene res://scenes/pavise_lab.tscn --shot <dir>/pavise.png`
  Each game-size view also writes a `_crop` file: the area round the pavise at 2x, nearest neighbour, so you see the
  game's own pixels.

## The variants

| | Look | How it tries to read |
|---|---|---|
| **A doc** | The grunt skeleton behind a door-sized pavise (1.9 x 1.1) of dark planks, with an iron rim, three red chevrons, a sight notch, a foot spike and a prop leg; a heavy crossbow with a crank | The doc's version: a dark rectangle with a skull over it |
| **B heavy** | A plate-armoured skeleton at 1.42 scale (2.6 tall, close to Rebar), a great helm with an ember slit, spiked pauldrons and a steel arbalest, behind a chest-high mantlet of pale wood | The threat is the body; the shield is light |
| **C painted** | A's skeleton in a crimson tabard. The front is painted crimson with a bone border, a bone skull and a ridge. The back is raw pale wood. Pointed-arch top. The bolt head is twice the size and hot yellow, and glows all the time | Colour says which side you see; the bolt head reads at range |
| **D lamp** (extra) | A security skeleton (peaked cap) behind a steel riot slab with a red-and-white base band and a searchlight. The lamp lights the floor in front. While aiming it turns red and narrows to a spot on its target | Light shows the facing; the telegraph is the light itself |

## What reads at size 24, and what doesn't

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

## Is "the front blocks" legible from the fixed camera?

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

## Recommendation

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

## Questions for the user

1. C's paint (a crimson front, a raw back) or the doc's dark planks with chevrons? C reads far better at 24, but it's
   louder, and close to the brute's reds.
2. Is a red floor arc while planted acceptable? It's the one fix that makes "protected from one angle" legible from
   behind.
3. Should the carried shield block, or only the planted one? A carried block can't be shown cleanly.
4. D's searchlight: worth keeping as a bunker or "security" variant for the luxury interiors (question 11 in the
   proposals), or drop it?
5. B as a later elite (a heavy arbalester), or not at all?

## Renders

All in the session scratchpad, `pavise\` (`pavise_<view>.png` and `pavise_<view>_crop.png`). The main ones:

- `compare_both`, `compare_gray`: the four variants side by side, in colour and in grayscale
- `lineup`: scale against the crew and the monsters
- `solo_<v>`, `close_<v>`
- `pack_<v>_<front|back|side>`, `aim_<mode>_<v>`, `arrows_<v>`, `cues_<none|glint|arc>`
