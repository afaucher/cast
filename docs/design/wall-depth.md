# Wall depth (look-dev) [prototype, 2026-10-29]

The user, on the crypt section lab (`crypt-section.md`): "The bricks read as a flat texture." And: "consider how we can
better align the texture lines with the hex grid such that the transition to the 'top' layer is smoother."

A research pass read `HexMapView` and found why (below); the user picked four fixes, A to E in its terms, and all four are
built behind one switch. **Off in the game** (today's look) until the user decides; **on in the crypt lab**.

## What was wrong
- The rough stone blocks (wall pattern 21) had 0.8 courses against 0.5 levels, from absolute height, with a random block
  width and shift per course: every wall top cut a course at an arbitrary height, and blocks were cut at hex corners.
- No relief: the joints were albedo only, the normal was the flat face's.
- The crypt is lit almost only by ambient light (key 0.04-0.08, candles), so bent normals alone barely show there.
- The cap read as a separate tile: the face stopped at `SEAM_DROP` (0.07) under the cap, the cap was inset to 0.90 with a
  bevel to 0.955, and the dim wall seam showed through the gap as a dark ring round every cap. A face on a wall line (a cut
  cell's) stopped 0.07 under a cap that runs right to the line: a slot.

## What changed (`HexMapView`, `MATERIAL_SHADER`; the switch is `wall_depth`)
1. **Grid-locked courses and bond.** Courses are half a level (0.25), so they end on the level lines. Stones are 0.5 long
   on hex-edge faces (corners at u = +/-0.5 mod 1.5) and 0.433 on wall-line faces (hex centres at u = 0 mod 0.866), in a
   half bond: every other course has a joint on each corner, and the courses between turn it with one stone (a quoin). Each
   stone is hashed by its world-space centre, so a quoin is one colour on both faces. The face kind comes from the normal's
   angle mod 60. The formwork (20) and panelling (22) patterns keep their look but their panel lines and rails are now a
   whole number of levels (1.0 and 1.5) from the level lines.
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
   the chapel set, the palest, sampled patches of the game view measure about 57 on a cap against 92 on a floor). No new triangles: no lip.

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

## Open questions
- **The vault loses its wall outlines.** In the vault set the only thing that drew the wall caps in the dark was the dim
  seam showing through the gap round each cap. With the seam closed the caps go black there (the faces facing a candle
  read better than before). A faint glow on the cap's outer bevel would bring the outline back, at the price of a seam-like
  line; not done.
- **Bricks or blocks.** The grid maths makes small stones (0.5 x 0.25; 0.433 on wall lines): at the game's zoom a wall
  reads as brickwork. Larger blocks (a level tall, 1.0 long, still on the grid) would read more like rough ashlar but turn
  fewer corners.
- **Caps as slabs.** Three slabs per hex with quiet joints read as a stone top; with the seam gone a long wall's cap reads
  as one mass with grooves between hexes. Straight slabs along a wall line are the alternative the brief allowed.
- **The game.** In the lair's light the bent normals are moderate (not toned down further). The seam ring round wall caps
  is part of the game's look elsewhere (bunker, lair); whether closing it is wanted outside crypts is the user's call.
- Shimmer was judged from stills (1:1, 2x and 4x crops), not in motion: worth a look in the gym while walking.
