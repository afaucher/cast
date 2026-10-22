# Rebar's jaw and upper chest

Status: **[proposal]** (2026-10-22). Look-dev only: the game's Rebar is unchanged until the user picks a jaw and a chest.

The user (2026-10-22): "And Rebar needs more of a jaw." Then: "We also need to look at Rebar's upper chest. It doesn't
read well with the orange neck collar but then flesh tone before more vest."

![sheet](rebar_jaw/sheet.png)

`sheet.png`: every jaw (rows) with every chest (columns), three-quarter, head and chest. Pick one row and one column.

## Why he reads this way today

- **No jaw.** The head is a 0.50-wide block with a thin jaw slab tucked under it, the same stone colour as the face. From
  the steep game camera (pitch -56) you see the top of the block and a sliver of brow; there is nothing below it to read.
- **The bare band is a bug.** `LowPoly.frustum` is centred on its origin, but `_vest_soup` places the vest's shell as if it
  started at its hem (`y0`). So the shell sits 0.43 lower than its own collar, top plate and shoulder straps, and the
  stone chest shows between them. The vest also covers most of the belt, so the buckle pokes through it.

## Jaws

![jaws](rebar_jaw/jaws.png)

All three keep his brow, eyes and nose, and tip the head back 8 degrees so the game camera sees more face.

| | What it is | At the game camera |
|---|---|---|
| **A Lantern** | A block that widens downward past the skull and juts forward, a shade darker than the face, with a squared lit chin and the mouth across its front. The classic brute. | A clear jaw and mouth line under the brow. |
| **B Underbite** | The lower jaw pushed out past the upper face, a jutting chin and two lower teeth standing up in front of the lip, in a grey stubble shade. | Reads best: the dark jaw and the two white teeth carry at 1:1 and in greyscale. |
| **C Broad head** | The whole head 1.16x, a broad flush jaw, raised 0.06 on a thick bull neck that flares into the shoulders. | The head stops being dwarfed by the shoulder boulders; the jaw reads less than A or B. |

![lineup](rebar_jaw/lineup.png)

`lineup.png`: Wick, Rebar and Gasket at the game camera at the game's 1080p pixel scale (shown x3), colour and greyscale.

## Chests

![chests](rebar_jaw/chests.png)

| | What it is |
|---|---|
| **1 One vest** | The vest shell runs from the belt up to the collar in one piece (what the code meant). Collar, top plate and straps as today. The belt and its pouches now show below the vest. |
| **2 Open vest** | The same full-height shell without the collar ring or top plate. The straps run out over the shoulders and down onto them, and a dark placket splits the front, so it reads as a vest worn open at the neck. |
| **3 Tee under** | One vest plus a navy tee: a crew neck instead of the collar, and the shoulder boulders become the tee's short sleeves. The stone shows only on his arms. |

![game](rebar_jaw/game.png)

`game.png`: every pair at the game camera (1:1, shown x3). Option 2's white straps over the shoulders read the most
"hi-vis" from above; option 3's navy shoulders change his silhouette's colour the most.

## Checks (every pair)

- Triangles: 1200-1340 (today 1268; budget 2500, `test_rebar_model`).
- `ZFightCheck`: nothing over 5 cm2 (the look-dev tape band stands off the vest a little more than today's).
- `PoseClip`: no arm inside the body over a sweep of the slam (top to bottom, with the forward bend), both punches, the
  bowl, the cast and the walk. `test_move_feel_anim`, `test_rebar_model` and `test_zfight` also pass with the pairs
  broad + tee, lantern + vest and underbite + open made the default (a temporary local change, not committed).

## Looking at them

```
godot --path . --resolution 1600x1600 -- --scene res://scenes/rebar_lab.tscn --jaw underbite --chest vest --shot <abs.png>
```

`--jaw lantern|underbite|broad` and `--chest vest|open|tee` (`RebarModel.JAWS` / `CHESTS`); without them the lab shows the
game's Rebar. Extra views: `head` (face close-up), `crew` (game camera with Wick and Gasket; also writes
`<base>_crew_crop.png`), `slam_up` / `slam`. `--views a,b,c` renders several views in one run.

## Building the pick

Make the chosen jaw and chest the defaults in `RebarModel` (fold their code into `_head_soup` / `_vest_soup`, drop the
options and `JAWS` / `CHESTS`), then check the headshots (`scripts/ui/headshots.gd`) and the menu backdrop, which frame
his head.
