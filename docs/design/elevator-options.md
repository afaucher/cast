# Elevator options: making the exit read as an elevator

Status: **built** (2026-10-18), see "Built" below. The rest of this page is the options study it was chosen from.

**The problem (user):** "the elevator doesn't read today. It could either be a service elevator or a fancy
elevator but it should look more elevator-like."

## Built [decided, user, 2026-10-18]

**Decision:** all four combinations of look {service, fancy} x placement {wall (option A), free-standing (option C)}.
**Each job picks one style** and every floor of that job uses it. The lobby dressing (option B) was not requested and
is not built (no lobby room theme; `ElevatorLobbyProps` stays a lab piece).

**How the style is picked.** `ContractRun.make()` deals `elevator_look` and `elevator_place` from the contract seed with
its own generator (`ContractRun.elevator_style_index`), so no other roll of the job moves and every machine agrees (the
two fields are SPAWN and in the floor checksum). The four styles come up about equally (97-107 each over 400 seeds).
`DungeonGen.for_run(run, floor)` passes the job's placement to the generator; `SiteBuilder.plan()` adds the job's look.
Seeds for `--seed N --spells heal,corn` (no `--contract`): 1 fancy wall, 2 fancy free, 3 service free, 7 service wall.

**The four styles:**

| | wall (A): a car in a notch of the room's wall | free (C): free-standing in the middle of the room |
|---|---|---|
| **service** | steel portal, scissor gate, freight car (blankets, caged lamp), headframe over the wall | the **hex freight platform**: a hazard-edged hexagonal deck over a dark gap, railings on five sides, a lifting bar gate on the sixth, a yellow post on every corner with a top ring, motor and sheave |
| **fancy** | marble and brass portal, bi-parting brass doors, deco crown with the fan gauge, wood-and-mirror car | the hexagonal glass shaft with brass posts and doors |

The service free-standing variant **does align with the hex grid** now: the square platform of the study became a
hexagon with the same footprint as the glass shaft (corners on the six neighbour centres, sides on midpoint-wall lines),
so both free-standing looks share one collision and one cell plan.

**Generation** (`scripts/world/elevator_geo.gd`, `ElevatorGeo`; `DungeonGen._place_elevator`), after the start and the
exit room are chosen and before the features and the walls, so the `exit` cell becomes the elevator's **landing** (the
full cell straight in front of its doors, 1.5 out):
- **Wall:** the best slot in the exit room (then the 2nd and 3rd farthest rooms from the start): a straight run of 4
  mouth cells on a camera-facing wall line (15 degrees off the camera preferred, 45 allowed), the 3 cells behind it and
  the 2 beside it empty, **no other floor within 2 cells behind or beside the car**, the landing and the cells round it
  this room's floor. The 3 cells become floor before `_add_walls()`, so `cut_walls()` opens exactly the trapezoid of the
  study; its back wall is a hex wall line. Scoring: the 15-degree walls, then a wall line running straight past the
  jambs, then far from the doors and near the room's middle.
- **Free:** the exit room's centre cell, door toward the camera (yaw 60, else 0); the car, the walk round it and the
  landing must be the room's floor.
- **Fallback:** a wall job whose rooms have no wall slot, or whose notch spoils the layout, gets the free car of the same
  look (`fallback: true` in the record). Over the test's 40 jobs x 3 floors no wall floor needed it.
- **Collision** (`HexMap.solids`, convex polygons that `blocks_point` / `clip_move` / `sweep` / `nearest_wall` see like wall
  faces): the two **jambs** over the slivers beside the notch car (its back wall is a real midpoint wall), or the free
  car's **five closed sides** (glass or railings) with their corner posts. Line of sight and projectiles ignore them.
  The free car's 7 cells are `HexMap.no_stand` (its posts sit on the neighbour centres): not path nodes or standing spots,
  so A* goes round it; ally and employee steering ask `HexMap.crosses_solid` before walking straight.
- **Nothing else on it:** `SiteBuilder` avoids and blocks `ElevatorGeo.keep_cells` (the car, the doorway, the landing,
  the walk round the free car) and adds the elevator as a body in its room, so no gate, employee, note, prop, decor, mail
  package, van or monster lands on it.
- The record is `HexMap.elevator` (`SitePlan.elevator` adds the look): placement, pose, cells, landing, door, the crew's
  spots in the car's front row and outside. The checksum hashes it with the solids and the `no_stand` cells.

**The arrival** (`scripts/contracts/elevator_arrival.gd`, `ElevatorArrival`, which also builds the model on every floor).
On floors 2 and 3 the crew stands in the car's **front row** (Wick in the middle, Gasket left, Rebar right) with the doors
shut; the needle swings from the floor above to this one, the doors open at 0.35 s, and the crew walks out through the
doorway one after another to its spots (Wick on the landing); control comes back at 1.86 s. A pure function of time, the
same on every machine, held behind the floor barrier and started from the shared clock like the van's; any key skips it;
no randomness. `--no-van-intro` / `--van-intro` switch it like the van's (tests and `--shot` skip it by default). After it
the AI allies re-form out in the room, not back in the car. On floor 1 the crew starts at the van and the elevator is
**shut** (red sill) until a hero comes within 3 of its doorway; then the doors open, and they shut again 1.2 s after the
crew has gone. The doors are presentation only: the doorway's collision is always open.

**E and the drop-off.** E Elevator works on or next to the landing (the doorway cells are next to it) and anywhere in the
car, for both placements. The drop-off (a following employee within 2.5 of an exit) measures to the doorway or the
landing, whichever is nearer. `--to-exit` and the net tests still put the crew on the landing (`_exit_cell`).

**The marker.** The magenta ring, seams and light on the exit cell are **retired** wherever there is an elevator: its sill
strip (red shut, green open), the car light and the model itself mark it. Maps without one (labs) keep the old marker.

**Screenshots** of the real game (1920x1080, `--seed N --spells heal,corn --focus elevator --shot-after 7` for floor 1,
`--floor 2 --van-intro --shot-after 1.6` for the arrival) were taken for the review; the dev flag `--focus elevator`
points the camera at the landing.

**Open:**
- Bias the look by site (fancy for lair / luxury clients, service for bunkers)? Today it is a coin flip per job.
- A fourth player: the front row holds three; a fourth would stand in the second row (the wall car is 1.5 deep).
- The leftover start cell (cyan ring) on floors 2 and 3 now marks nothing the crew uses ("Floors by risk" in
  `contracts.md`).
- The risk gauge's labels, as before.

## The study

**Before:** the exit had no model. It was a single `exit` cell in the middle of the exit room
(`DungeonGen._choose_start_exit`: `exit_cell = rooms[best].center`). `HexMapView` gave it magenta seams and a ring, and
`DungeonLook` added a magenta light. From the camera it read as a glowing hex, not an elevator.

**Where the options live:**
- `scripts/art/lowpoly/props/elevator_model.gd` (`ElevatorModel`)
- `scripts/art/lowpoly/props/elevator_lobby_props.gd` (`ElevatorLobbyProps`)
- `scripts/art/lowpoly/elevator_lab.gd` + `scenes/elevator_lab.tscn`

All of them use the real terrain: `HexMapView` with midpoint walls from `HexMap.cut_walls()`, `FloorMaterials` and
`DungeonLook` lighting.

```
godot --path . --resolution 1920x1080 -- --scene res://scenes/elevator_lab.tscn --look service|fancy \
      --place adjacent|lobby|midfloor --shot <png>
```

## Screenshots

Every look is shown in every placement (6 combinations). Each combination has five views, named
`<look>_<place><view>.png`:

| view suffix | camera | doors | crew |
|---|---|---|---|
| (none) | game camera, size 24 (the default zoom), centred on the car the way the follow camera would be | open | stepping out: one still in the car, one on the sill, one on the landing |
| `_closed` | size 24 | shut | waiting outside, Rebar at the call box |
| `_close` | size 9 | open | the whole crew inside the car (the arrival moment) |
| `_close_out` | size 9 | open | stepping out |
| `_close_closed` | size 9 | shut | waiting |

There is also `contact_sheet.png`, which has every shot in one image.

## The two looks

The elevator must read at size 24. Each look relies on these cues:
- doors on a wall line;
- a portal frame that rises above the 1.5-unit walls;
- a floor indicator above the doors;
- a call panel;
- a lit car interior;
- a sill strip that is red while the doors are shut and green when the crew can step in (it replaces the magenta ring);
- the shaft showing above the car: guide rails, cables and a sheave.

The indicator doubles as a **risk gauge** with green, amber and red zones and a needle. Floors are named by risk
(`contracts.md`, "Floors by risk"), so the dial can point at the risk of the floor the car is on.

- **Service (freight).**
  - **Portal and gate:** steel jambs with hazard-striped edges and a scissor gate. You can see through the gate into
    the lit car, so the car reads even when the gate is closed.
  - **Car:** a diamond-plate floor with scuffs, quilted blue moving blankets, kick plates, and a caged work lamp on a
    yellow crosshead.
  - **Header and shaft:** a dial indicator on the header, "FREIGHT" and "CREW ONLY" stencils, and above the car a yellow
    headframe with a sheave and cables.
  - **Outside the car:** a call box (green up button lit, red down button), the *floor service log* clipboard on a
    nail, and a worn steel landing plate with a striped edge.
  - **Fit:** it suits the crew (contractors with a work van). `environment.md` already says "The exit is a freight
    elevator with its light on".
- **Fancy (luxury bunker / villain lair).**
  - **Portal and doors:** black marble with brass fluting, brass bi-parting doors with deco chevrons, and a stepped
    art-deco crown with a brass sunburst fan indicator. "LIFT" is lettered in brass.
  - **Car:** wood panelling, a mirror, a brass handrail, a carpet runner, and a glowing bowl lamp.
  - **Call and log:** a single lit round call button on a brass plate, and the log on a brass hook.
  - **Readability:** at size 24 it reads mainly from its brass doors and the fan, so it is a little less instant than
    the service look.

**Size finding:** Rebar is about 2.3 units tall, and the walls are 1.5. A 3.0-unit opening is the minimum that lets the
camera see a crew member standing in the front half of the car. That puts the header and fan at about 3.0 to 4.0
units, and the service headframe reaches 4.9.
- **Walls facing the camera:** this is fine, because the portal only hides the void behind it. The elevator must
  therefore **only go on walls facing the camera**. These are the north-east to south-west midpoint-wall lines, 15
  degrees off `ThemeGeo.CAMERA_DIR`, or at a pinch the east-west lines, 45 degrees off. The decor planner already
  prefers walls facing the camera.
- **Crew inside the car:** with the 3-cell car, the header hides the head of anyone more than about half a unit
  inside the car. Three heroes in the car (`_close`) overlap a lot. The arrival should therefore place the crew in the
  front row of the car (`ElevatorModel.car_spots()`) and walk them out as the doors open (`_close_out`).

## The three placements

### A. Adjacent: a notch in the wall of an ordinary room
Screenshots: `service_adjacent*.png` (main), `fancy_adjacent*.png`.

**Geometry:** three consecutive WALL cells on a back wall become floor, before `cut_walls()`. Midpoint walls then open
exactly five triangles:
- a trapezoid with a 5.2-unit mouth on the room's wall line, a 3.46-unit back edge, and a depth of one row (1.5);
- the car is the rectangle 3.46 x 1.5 inside it, so its back wall lies exactly on a hex-map wall face;
- the two leftover slanted slivers sit under the portal's jambs, which are a full-height facade plus a low block
  at wall-cap height.

**Pros:**
- It reads clearly as "doors in a wall with a car behind".
- It fits the midpoint walls naturally (no odd angles).
- It costs no room floor, and the room's theme and props stay as they are.

**Cons:**
- The car is tight: three heroes, Rebar included, fill it.
- It needs a wall facing the camera with at least three straight cells and nothing walkable directly behind it.
- It is the most "built-in", so it shows no lobby or sign-in moment.

**Generation (not done):**
- Choose the exit as a wall slot instead of a room centre: three collinear wall cells on a camera-facing line of the
  exit room, with room floor in front and wall or void behind. With one-cell wall rings between rooms, the row behind
  must not be another room or a corridor; otherwise thicken the wall there or reject the slot.
- Convert those cells to floor tagged `exit` and run `cut_walls()`.
- Add blockers or wall kites for the two sliver triangles.
- Reserve the landing (about two cells in front) in `plan.blocked` and in the room's `ThemeCtx`.

### B. Dedicated elevator lobby
Screenshots: `service_lobby*.png`, `fancy_lobby*.png` (main).

**Layout:** a small room (hex radius 4, clipped by the back wall) with a corridor in. The elevator is the same notch as
A, on the back wall. The dressing:
- **Fancy:** a red runner from the corridor to the doors, potted palms, a brass DIRECTORY board that lists floors by
  risk ("PANIC ROOM ... ???"), and a bench.
- **Service:** a SERVICE ELEVATOR / AUTHORIZED CREW ONLY sign, a fire extinguisher, a KEEP CLEAR striped floor box, a
  pallet of boxes, a bench with a hard hat, and a dying palm.
- **The log:** the floor service log hangs on the left jamb next to the call panel, where the elevator's sign-in form
  will live.

**Pros:**
- It is the strongest read: the whole room says "elevator".
- It gives the sign-in sheet a physical home.
- The arrival on a new floor starts in a calm, legible room.

**Cons:**
- It costs a room per floor, a small and fairly empty one.
- Generation has to plan for it.

**Generation (not done):**
- Make the exit room a small leaf room and give it a new room theme, `elevator_lobby`, with floor and wall materials
  and decor rules in `RoomThemeDefs` / `ThemeVignettes`, then apply A's notch on its camera-facing back wall.
- Once A exists, this is mostly theme data plus a "prefer a small room" rule in `_choose_start_exit`.

### C. Mid-floor: free-standing
Screenshots: `fancy_midfloor*.png` (main: the glass shaft), `service_midfloor*.png` (the freight platform).

- **Fancy: hexagonal glass shaft.**
  - **Footprint:** the corners stand on the six neighbour centres of one cell, so its sides lie exactly on
    midpoint-wall lines. That is a perfect fit for the hex grid: 7 cells, about 3.0 across.
  - **Faces:** five glass faces with brass posts and an open marble frieze on top (no roof, so the camera sees in).
    The machine beam and sheave sit on the frieze, and the fan indicator stands over the door face.
  - **Doors:** the brass doors slide round the corner posts into the neighbouring faces.
  - **Fixtures:** a call pedestal and a sign-in lectern stand outside.
- **Service: freight platform lift.**
  - **Platform:** a hazard-edged diamond-plate deck over a dark gap.
  - **Frame:** railings on three sides, a front bar gate that lifts, and a yellow four-post hoist frame with the motor,
    sheave, cables, dial and amber beacon.
  - **Fixtures:** a call post with the clipboard.
  - **Footprint:** it is square, so it does not align with the hex grid and needs its own collision circles.

**Pros:**
- This is closest to today's generation: the exit already sits in the middle of its room, and `RoomThemes` already
  keeps centrepieces out of the exit room. It needs almost no layout change.
- You can walk all the way round it.
- The glass shaft is the most "luxury lair" option.

**Cons:**
- A tall column in the middle of a room hides what is behind it and breaks up the fighting space.
- A free-standing glass shaft (or a platform lift) is less obviously "the elevator out of here" than doors in a wall.
- Its thin walls can't be expressed as midpoint walls (those block whole triangles), so they need blocker segments or
  circles.

**Generation (not done):**
- Keep the exit at the room centre.
- Block the ring of 7 cells except the door face's approach.
- Add blockers for the glass sides or railings.
- Keep a radius of 2 to 3 clear, as the exit clear zone already does.

## Networking
None expected, for every option. The elevator is a set piece at the exit, built from the floor plan on every machine
(`SPAWN`, like the van and the decor). Its door, sill light and needle are cosmetic (`LOCAL`) and are driven by events
that already exist:
- the arrival behind the floor barrier;
- the elevator menu;
- the host-arbitrated "down" / "out" choice.

Any blockers are deterministic from the seed, like `DecorBlocker`.

## Recommendation
**A as the base, with B as its dressing, using the service look by default.**
- **Base:** always put the elevator in a three-cell notch on a camera-facing wall of the exit room. That reads as
  "doors in a wall", fits the midpoint walls exactly, and keeps the arrival (crew in the front row of the car, doors
  open, walk out) readable.
- **Lobby:** when the exit room is small, theme it as the lobby (B). That is cheap once A exists, and it gives the
  floor sign-in sheet its clipboard and call panel.
- **Looks:** use the service (freight) look by default, since it is the crew's world and reads most instantly. Use the
  fancy look on lair or luxury floors, for example the origin floor.
- **C:** keep the glass shaft as an occasional showpiece, not the default.

## Open
- **Exit-cell marker:** keep the magenta ring and seams on the exit cell, or retire them for the sill strip (red
  while the doors are shut, green when open) and the car light?
- **Indicator labels:** should the risk gauge show labels, and in which words? This follows the open question in
  `contracts.md` about what the floors are called.
- **A fourth player:** with four players plus Rebar, the 3-cell car is full. Is a 4-cell notch worth it? It needs four
  straight wall cells.
