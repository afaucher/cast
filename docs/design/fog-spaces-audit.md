# Fog spaces audit

How RoomFog / Doorways cut a floor into fog spaces, checked over fixed seeds. Follow-up to the lava playtest (walkways
"only from one side", `lava-playtest.md`). The question was whether the planner makes lobes of a multi-segment room
and whether every dimension of a space makes sense as the edge of the player's view.

- Test: `tests/test_fog_spaces.gd` (contract seeds 3, 7, 12, 26, 37, 42, floors 1-3, and lava caves 1-5; once as
  merged and once with the hall-split prototype). It prints one `FOG SPACE` row per space, a `FOG VIS` line per floor
  and a `FOG SUMMARY` / `FOG DIST` line per mode.
- Maps: `scenes/fog_spaces_lab.tscn` (`--maps s3f1,s7f2,c1 --out <dir> [--split]`): each cell in its space's colour,
  white lines between spaces, dark lines at steps inside a space, white dots on untagged cells (the fill gave them a
  space), yellow rings on doorways, cyan rings on the split prototype's segment doorways.

## Invariants (asserted, all hold)

Over 18 generated floors and 5 caves:

- every room tag is in exactly one space, and every space's floor is one connected piece (lava fog-link cells count);
- no untagged cell of a room (a cell only a climb reaches) went to a neighbour's space;
- every doorway sits at its opening: its door cells touch both its room and its hall.

The doorway rule merged with the lava fixes (only own-tagged cells make a contact) changed **0 doorways** over 60
generated floors, so it does not alter floor plans.

## Lobes: not the problem

DungeonGen's rooms are blobs that pass through `_open_shape` (a morphological opening) and `_component` (one piece),
so a lobed room comes out without a neck. The waist measure (BFS bands from one end of the room's diameter; a band
narrower than both the widest band before it and after it, in the middle 15-85 % of the length) finds:

- rooms (146): waist ratio min 0.75, p5 0.83, p50 1.00; **no room has a neck under 0.45**;
- caves: every space is a 37-cell round, a 19-cell round or a walkway.

So a room is not two lobes in one space anywhere in the sample.

## Symmetry (sampled, asserted <= 3 %)

Pairs of standable cells in adjacent spaces, within DOOR_SIGHT and with mutual eye-height line of sight: is each
side's space shown from the other? As merged, one-sided pairs are 0-1.4 % per floor (seed 37 floor 1 is the worst, 6
of 417) and 0-0.9 % per cave. Every one comes from RoomFog's own rule that a hero must see the doorway (DOOR_SIGHT 14,
from eye height): the doorway is round a wall corner of a big room or behind a step, or (2 cases) past 14. That is by
design, not a cutting error.

## Reach, waist, coverage

For each space and each of its doorways, with the viewer just outside the doorway (on the other side's contact
cells, 1.2 out):

- **reach**: the farthest cell of the space with line of sight from the doorway's middle (and "seen": from just
  outside);
- **waist**: as above;
- **coverage**: the share of the space's cells in line of sight from just outside; a row shows its worst doorway.

The game camera shows about 42.7 x 24 world units (ortho 24 at -56 deg), so about 21 is the half-width and 14.5 the
ground half-depth.

| as merged | spaces | reach p50 | p90 | p95 | max | coverage p5 | min |
|---|---|---|---|---|---|---|---|
| rooms | 146 | 18.5 | 23.7 | 26.1 | 31.5 | 0.57 | 0.30 |
| halls | 150 | 18.2 | 30.9 | 36.0 | 78.3 | 0.33 | 0.06 |

### Outliers

Halls (the real outliers: a long corridor is one space and reveals all at once):

| seed | floor | space | cells | reach (seen) | waist | coverage |
|---|---|---|---|---|---|---|
| 3 | 1 | hall:4 | 84 | 78.3 (26.6) | 1 across, 83 long | 6 % (doorway 9) |
| 37 | 3 | hall:3 | 29 | 44.3 (35.3) | 1, 28 long | 21 % |
| 7 | 2 | hall:0 | 26 | 43.2 (43.1) | 1, 25 long | 12 % |
| 12 | 3 | hall:5 | 25 | 42.9 (35.7) | 1, 24 long | 32 % |
| 3 | 1 | hall:0 | 28 | 42.8 (34.9) | 1, 27 long | 36 % |
| 3 | 3 | hall:2 | 22 | 37.5 | 1, 21 long | 86 % |
| 12 | 3 | hall:3 | 19 | 32.6 | 1, 18 long | 16 % |
| 26 | 1 | hall:6 | 18 | 29.0 (28.0) | 1, 17 long | 22 % |
| 42 | 2 | hall:2 | 20 | 31.8 (29.7) | 1, 19 long | 25 % |

Rooms (big, or with features or corner doorways; none is lobed):

| seed | floor | space | cells | reach (seen) | waist | coverage | why |
|---|---|---|---|---|---|---|---|
| 3 | 3 | room:3 | 163 | 31.5 (28.2) | 13 of 14 | 61 % | the largest room |
| 37 | 3 | room:4 | 147 | 27.4 | 8 of 9 | 58 % | big, platforms |
| 7 | 3 | room:3 | 166 | 27.4 | 13 of 14 | 61 % | big |
| 7 | 1 | room:0 | 157 | 26.9 (25.9) | 10 of 12 | 53 % | big |
| 42 | 2 | room:7 | 82 | 17.6 | 12 of 12 | 30 % | doorway 15 in a corner, raised features |
| 37 | 2 | room:0 | 111 | 23.7 (22.9) | 15 of 15 | 36 % | platforms and pillars by doorway 0 |
| 37 | 1 | room:4 | 72 | 21.1 (18.4) | 10 of 10 | 39 % | corner doorway 7 |
| 7 | 3 | room:4 | 47 | 16.8 | 8 of 8 | 40 % | corner doorway 9 |
| 37 | 2 | room:4 | 110 | 22.6 | 14 of 14 | 42 % | features |

Low coverage in a room means things in it block the view from a corner doorway; the room still shows whole when the
hero steps in, which is how RoomFog works. Low coverage in a hall means the hall bends.

Caves: rooms reach 7.4-11.3, walkways up to 16.4, coverage 84-100 %. The lava caves are fine.

## The fix: cut long halls into segments (runtime RoomFog only)

Prototype: `RoomFog.split_long_halls` (static, **off by default**). After the doorway links are built, each hall whose
corridor-tagged cells are at least 16 steps long (`SEGMENT_STEPS` 8 x 2) is cut along its length into segments of
about 8 steps: new spaces `hall:N.k`; the filled cells go to the nearest segment; each real doorway is re-pointed to
the segment holding most of its mouth cells; consecutive segments get a doorless doorway (`split: true`) at the cut.
`hall_group` remembers which hall a segment came from, and the NEXT rule marks a known room's whole linked hall (every
segment) as before.

| split halls | spaces | reach p50 | p90 | p95 | max | coverage p5 | min |
|---|---|---|---|---|---|---|---|
| rooms | 146 | 18.5 | 23.7 | 26.1 | 31.5 | 0.57 | 0.30 |
| halls | 244 | 11.5 | 19.9 | 21.9 | 25.3 | 0.50 | 0.17 |

Spaces 296 -> 390. One-sided pairs stay at most 2.2 % per floor (seed 26 floor 1), 0.9 % in caves.

**Kind:** runtime only. It touches only `scripts/world/room_fog.gd`; `Doorways.find`, `SiteBuilder._plan_doors`, doors,
the floor plan and the floor checksum are unchanged. **No generator change is needed**: rooms have no necks.

Before and after maps (in the session scratchpad, `sewer/lava2/spaces/`): `spaces_s3f1` / `spaces_s3f1_split`,
`s7f2`, `s12f3`, `s37f3` and cave `c2` the same way; plus `s7f3`, `s12f1`, `s26f1`, `s37f1`, `s37f2`, `s42f2`, `c1`-`c5`
as merged.

Not done in the prototype: FogView's look of a doorless cut (the segment ahead is shown dimmed as NEXT, the same as a
real doorway) and a playtest. Rooms over ~150 cells (reach 26-31) would be the next candidates if the user wants every
space inside one screen; cutting a room is a bigger change (it needs a cut that reads, e.g. along a row of features)
and is not proposed.

## Thresholds

- reach <= 21 (the camera's half-width) as a flag; with the split, halls stay under ~26. Rooms run to 31.5: big rooms
  are a design call, so report, don't assert.
- waist: no room neck under 0.45 of its typical width (asserted).
- coverage >= 0.6 from every doorway as a flag (rooms p5 0.57).
- one-sided visibility <= 3 % of sampled pairs per floor (asserted).

`test_fog_spaces` stays as a test over the fixed seeds: it asserts the invariants, the no-neck rule and the one-sided
limit, and prints reach and coverage for review. If the split goes in, add an assertion that no hall's reach is over 26.
