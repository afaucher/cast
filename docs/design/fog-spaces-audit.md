# Fog spaces audit

How RoomFog / Doorways cut a floor into fog spaces, checked over fixed seeds. Follow-up to the lava playtest (walkways
"only from one side", `lava-playtest.md`). The question was whether the planner makes lobes of a multi-segment room
and whether every dimension of a space makes sense as the edge of the player's view.

**Status (2026-10-20):** the fix below, cutting long halls into segments, is **on in the game** (user: "Turn it on"); see
"Long halls in the game" at the end. The tables first describe the floors as they were (halls whole).

- Test: `tests/test_fog_spaces.gd` (contract seeds 3, 7, 12, 26, 37, 42, floors 1-3, and lava caves 1-5; once with
  halls whole and once with long halls cut, as in the game). It prints one `FOG SPACE` row per space, a `FOG VIS` line
  per floor, a `FOG SUMMARY` / `FOG DIST` line per mode and a `FOG CUTS` line.
- Maps: `scenes/fog_spaces_lab.tscn` (`--maps s3f1,s7f2,c1 --out <dir> [--whole]`): each cell in its space's colour,
  white lines between spaces, dark lines at steps inside a space, white dots on untagged cells (the fill gave them a
  space), yellow rings on doorways, cyan rings on the cuts between segments of a long hall. `--game-shot` takes the
  in-game screenshots (the lab's header has the command).

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

(The prototype as audited; what went into the game differs a little, see "Long halls in the game" below.)
Prototype: `RoomFog.split_long_halls` (static, off by default then). After the doorway links are built, each hall whose
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

**Kind:** runtime only. It touches only `scripts/world/room_fog.gd`; `Doorways.find`, `DoorPlanner.plan`, doors,
the floor plan and the floor checksum are unchanged. **No generator change is needed**: rooms have no necks.

Before and after maps (in the session scratchpad, `sewer/lava2/spaces/`; file names as of the audit): `spaces_s3f1` / `spaces_s3f1_split`,
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
limit, and prints reach and coverage for review. With the halls cut it also asserts that no hall's reach is over 26.

## Long halls in the game (2026-10-20)

The user: "Turn it on." `RoomFog.split_long_halls` is **on** (true); `--whole` in the fog spaces lab, or setting it false,
gives the halls whole again. What changed from the prototype:

- **Where the cuts go.** A hall of 16 or more walking steps gets `round((length + 1) / 8)` segments (at least 2). Each
  cut sits at its even share of the length, moved up to 5 steps (or left out) so it is at least `CUT_CLEAR` (3) steps
  from every real doorway's cells and door, at least `MIN_SEGMENT` (4) steps from the last cut, and never at the foot
  of a drop (`DROP_LEVELS` 3 or more below the floor within 2 steps: from the top, the floor just under a drop is out
  of sight). A segment is one connected piece (a branching hall's band can be two), and there is one cut per patch
  where two pieces touch, with an axis from the nearer piece to the farther.
- **Sight.** A cut is seen like a doorway (within DOOR_SIGHT and in line of sight from the hero's eyes; its middle or
  any of its cells at eye height) but **costs no hop**. So the spaces reached are the same whichever side of a cut a
  hero stands on: **no flicker** on a cut.
- **Next.** The segment past a known one is next. A known room marks only the segment at its doorway (an uncut hall
  still marks the room at its far end); a room at the far end of a cut hall stays dark until the crew gets near.
- **Look.** FogView blends the two segments' levels over a feather about a hex wide (0.9 each side of the cut's line)
  on the floor and the walls next to it, in every look, not the hex-edge step: the hall reads as going on into the
  dark. Only cells of the two segments (and walls beside them) take it, and a cut keeps 3 steps from every doorway, so
  it never draws over a doorway or a door.
- **Every machine.** The cut is made from the map alone (deterministic), and the view from hero positions, so the
  host, every client (puppets included) and a late joiner cut the same segments and have the same in view at once.
  Nothing in the floor plan, the doors or the checksum changes.

| cut halls (the game) | spaces | reach p50 | p90 | p95 | max | coverage p5 | min |
|---|---|---|---|---|---|---|---|
| rooms | 146 | 18.5 | 23.7 | 26.1 | 31.5 | 0.57 | 0.30 |
| halls | 219 | 13.6 | 20.4 | 22.1 | 25.3 | 0.44 | 0.33 |

Spaces 296 -> 365 over the 18 floors and 5 caves (69 cuts). One-sided visibility is at most 0.9 % per map, none of it
across a cut (as before: corner doorways of big rooms). `FOG CUTS`: the nearest real doorway cell is 3 steps from a cut;
no flicker at 125 spots on cuts; 40 walks down every cut hall, the next segment always shows and nothing 3 or more
segments ahead is ever seen (up to 2 ahead: the one ahead in view, sometimes the one after it near a cut).

Tests: `test_room_fog` sections 9-11 (a 96-step hall between two rooms and seed 3 floor 1's 83-step hall: segments,
reveal ahead, no flicker, shared sight, host/client/late joiner), and `test_fog_spaces` (every seed: the cuts' places,
no flicker, the walks, hall reach <= 26).

Screenshots (session scratchpad, `sewer/lava2/spaces/on/`): seed 3 floor 1, the crew 37 steps down `hall:4` (83 steps,
10 segments): `game_walk.png` (the game camera), `game_ahead.png` (the crew and the silhouette ahead), `game_cut.png`
(close up on the cut where the hall in view meets the segment in silhouette), each with a `_whole` twin (the same
spot, halls whole); `spaces_s3f1.png` / `spaces_s3f1_whole.png` (the floor's spaces).
