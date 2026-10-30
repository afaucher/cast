# Wall depth (look-dev) [prototype, 2026-10-29]

The user, on the crypt section lab (`crypt-section.md`): "The bricks read as a flat texture." And: "consider how we can
better align the texture lines with the hex grid such that the transition to the 'top' layer is smoother."

A research pass read `HexMapView` and found why (below); the user picked four fixes, A to E in its terms, and all four are
built behind one switch. **On everywhere in the game** (the user's call, 2026-10-29); the gym can turn it off.

## What was wrong
- The rough stone blocks (wall pattern 21) had 0.8 courses against 0.5 levels, from absolute height, with a random block
  width and shift per course: every wall top cut a course at an arbitrary height, and blocks were cut at hex corners.
- No relief: the joints were albedo only, the normal was the flat face's.
- The crypt is lit almost only by ambient light (key 0.04-0.08, candles), so bent normals alone barely show there.
- The cap read as a separate tile: the face stopped at `SEAM_DROP` (0.07) under the cap, the cap was inset to 0.90 with a
  bevel to 0.955, and the dim wall seam showed through the gap as a dark ring round every cap. A face on a wall line (a cut
  cell's) stopped 0.07 under a cap that runs right to the line: a slot.

## What changed (`HexMapView`, `MATERIAL_SHADER`; the switch is `wall_depth`)
1. **Grid-locked courses: rough ashlar** (second pass; the first was a brick bond, see below). A course is a level tall
   (0.5); about 3 bands in 10 are two half-level courses instead. The bands count down from the coping's lower joint, so the
   course under the coping is whole (the one at a wall's foot is cut). The joints keep to a span's ends and middle: a
   hex-edge face's span is corner to corner (1.0; corners at u = +/-0.5 mod 1.5), a wall-line face's is centre to midpoint
   (0.866; at u = 0 mod 0.866). Level courses alternate a joint on each corner (a whole span, split in two 3 times in 10)
   with a joint in the middle and a stone turning each corner (a quoin, half a span each way); in a pair of half-level
   courses the lower one is half spans (merged into one a quarter of the time) and the upper one a middle stone with a half
   span turning each corner. On a straight wall line the "corners" are hex centres and midpoints, so a quoin there is just a
   stone a whole span long across them. Each stone is hashed by a world-space point of it (a quoin by its corner, so it is
   one colour on both faces), for its value (0.58-1.42 of the base) and a warm or cool hue shift. Rough: the joints wander
   by up to 0.01 (world noise, so both faces of a corner agree) and half the stones have a chipped corner. Joints are a
   little wider than the bricks' (readable at 1:1). The face kind comes from the normal's angle mod 60. The formwork (20)
   and panelling (22) patterns keep their look, with their panel lines and rails on whole levels (1.0 and 1.5).
2. **The wall seam closed.** A wall cap's flat top runs to 0.93 (`WALL_TOP_SCALE`), then its bevel runs out to the full
   hex and down to `SEAM_DROP`, exactly where the faces' tops are: no gap, no ring. A wall-line face's top rises 0.07 to
   the cap's edge: no slot. Same vertices and triangles: the mesh carries the second shape in CUSTOM0 (`Batch.custom`,
   `_cap_move`) and the vertex shader moves it, so the switch is live. `tests/test_wall_mesh.gd` checks it for all 63 cut
   masks and a wall column (the cap at 0.93 triangulates exactly, cap and bevel cover the kites to the edge, every face top
   meets the bevel or the cap).
3. **Per-stone shading.** Bevel normals from the gradient of a smoothstep bevel (about 1 px wide at the game's zoom, slope
   ~0.75 at any width), a small random tilt per stone (about 4 degrees), `NORMAL` in view space. Because the crypt is
   ambient-lit, the depth goes into the albedo too: a fixed "virtual light" from above (`VKEY`, x `1 + 0.55 * (n.k - n0.k)`)
   lights each stone's top edge and darkens its lower edge under any light; joints and bevel recesses go into `AO`; the
   foot of a wall (its bottom 0.45) is darker, its top a touch lighter. Joints and bevels widen with `fwidth` (never under
   about a pixel), and on a face seen edge-on the joints, per-stone colours and tilts fade to their average (they made a
   moire there). Nothing on the terrain draws ink from normals (models ink their own hulls), so no joint gets inked.
4. **Coping and cap.** The face's top half course (0.125) is a coping band in the cap's stone, with joints only at hex corners
   (on a wall line: at the centres and midpoints, under the cap's grooves), a lit lip at the top and a dark joint and shadow
   under it; the courses count down from it, so the course under it is whole. The cap is the same stone in three large
   slabs per hex, cut on alternate kite lines (centre to the edge midpoints at 0, 120 and 240 degrees: never square lines),
   joints kept quiet so a cap reads as one top. Caps stay darker than floors (the cap stone is the wall's base x 0.44; in
   the chapel set, the palest, sampled patches of the game view measure about 57 on a cap against 92 on a floor). No new
   triangles: no lip.
5. **The outline in the dark** (second pass). The cap's bevel over a face and the coping's lip give off a faint cool light
   (`WD_EDGE`, about 0.02 linear), so a wall's top edges still read where no light reaches. Only the edges over a face:
   `_cap_edge_outer` marks those bevel quads at build (CUSTOM0 w = 3), and a groove between two wall tops stays dark, so it
   draws the walls' silhouettes, not the hex grid the old seam drew, and it is grey-blue, not amber. Under any real light
   it is lost in the lit stone (the chapel, the lair). Caps stay darker than floors. `tests/test_wall_mesh.gd` checks the
   marking (every bevel over a face, none on the groove between two wall columns).

No textures, no new draw calls or triangles (`tests/test_floor_materials.gd` passes unchanged). With the switch off the
shader takes today's path and the mesh is today's (plus the unused CUSTOM0 on the two wall surfaces).

## The switch
- `HexMapView.wall_depth` (a view's own, read when it builds its materials) and `set_wall_depth(on)` (live: the uniform on
  every material of its mesh, restyled duplicates included). `HexMapView.wall_depth_default` is what a new view starts with.
- The gym's Experiments: **Wall depth** (off / on), live on the game's terrain, kept for the floors built after
  (`GymDev._set_wall_depth`). On the gym's own map the course has concrete walls and the cave has stone ones; Map:
  generated walks a real floor.
- The crypt lab (`CryptSectionLab.wall_depth`) builds with it on.

## The sheets (`docs/design/wall_depth/`, `scenes/wall_depth_lab.tscn`)
    godot --path . --resolution 1920x1080 -- --scene res://scenes/wall_depth_lab.tscn --shot <abs dir>/sets.png
- `sets.png`: each set at the game camera (size 24, 1:1), off | on: the vault, the chapel, and the same map as a lair in
  the game's own light (DungeonLook's key, fill and pools; the game's flagstone and rough stone blocks, a torture chamber's
  materials). The full frames are `<set>_off.png` / `<set>_on.png`.
- `close.png` / `close_2x.png`: an outside wall corner and its cap at size 8, off | on, a row per set.

## Second pass (2026-10-29)
Asked "How do the walls look with it on?", the user picked "Bigger blocks": "Good direction, but use larger blocks so it
reads as rough stone, not brick; and fix the vault's outlines". Fix 1 became rough ashlar (above); fix 5, the outline, is new.
- The first pass's stones were 0.5 x 0.25 (0.433 on wall lines) in a plain half bond: brickwork at the game's zoom.
- Tried for the vault's outlines: the brief's three options come to one thing in the vault, since nothing there is lit. A lit
  lip from the virtual light alone does nothing (it scales the albedo, and there is no light to scale), so the lip and the
  cap's bevel get a minimum value instead, as a faint cool emission (option 2 and 3 together). On every bevel ring it
  brought back a grey hex grid over the wall tops, the old seam's pattern in another colour; on the bevels over a face
  only, it draws the walls' outlines, which is what is kept. A first strength (0.012 linear) was too faint at 1:1; it is
  about 0.02 now.

The user's read of the second pass (2026-10-29): "The second pass is great. This is much better." Asked whether to turn it
on for every wall in the game or only in crypts: "Everywhere". So `HexMapView.wall_depth_default` is on; the gym's
"Wall depth" row still turns it off to compare.

## Open questions
- **The vault's outline strength.** About 0.02 linear, cool grey: the walls' silhouettes read at 1:1 in the vault, faint.
  Brighter would start to read as a glow; a warmer tint would read as the old seam. One constant (`WD_EDGE`).
- **Course mix.** 3 bands in 10 are two half-level courses, 3 spans in 10 split; the rest are level-tall stones a span
  long. Every wall shares the same band pattern by height (a course is the same all round a room, so corners agree).
- **The chips** read as rounded corners on the short stones of a half-level course at size 8; at the game's zoom they are
  a pixel or two.
- **Caps as slabs.** Three slabs per hex with quiet joints read as a stone top; with the seam gone a long wall's cap reads
  as one mass with grooves between hexes. Straight slabs along a wall line are the alternative the brief allowed.
- **The game.** In the lair's light the bent normals are moderate (not toned down further). The seam ring round wall caps
  is part of the game's look elsewhere (bunker, lair); whether closing it is wanted outside crypts is the user's call.
- Shimmer was judged from stills (1:1, 2x and 4x crops), not in motion: worth a look in the gym while walking.
