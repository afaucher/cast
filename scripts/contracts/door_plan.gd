class_name DoorPlan
extends RefCounted
## Which doorways of a floor get an office door (docs/design/exploration.md, "Decisions: map information, fog and doors", 2026-10-19). Pure and
## deterministic: the floor's doorways (Doorways.find), its SitePlan and its seed in, doorway ids out; no GameWorld.rng.
## The user's rules (2026-10-19):
##   - only a NARROW doorway can have a door (a corridor one full cell wide, 3.0 between its walls); where a wide hallway
##     meets a room it is always open ("Maybe the wide hallways never have a door");
##   - not every doorway: the rest are open archways the fog sees through like an open door;
##   - never on a dead-end corridor, never in the start room or the elevator room;
##   - rooms with something to hide first: the origin gate's room, a hellgate's room, a room with a pack.
## Of the doorways allowed, DOOR_SHARE (rounded up) get one: the best scored, ties broken by a roll on a generator seeded
## from the floor seed. If doors join the real floors this list belongs in the SitePlan (and so in the floor checksum).

## The share of the allowed doorways that get a door. User, 2026-10-19: doors on EVERY narrow doorway (1.0); wide hallways
## stay open, and the exclusions stay (no dead ends, not in the start or elevator room). Planned in SitePlan.doors.
const DOOR_SHARE := 1.0
const SCORE_ORIGIN := 3.0
const SCORE_GATE := 2.0
const SCORE_PACK := 1.0


## The ids of the doorways that get a door. `plan` may be null (a hand-built map: every room scores alike).
static func choose(doorways: Array[Dictionary], plan: SitePlan, floor_seed: int, share: float = DOOR_SHARE) -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([floor_seed, "office_doors"])
	var cands: Array = []
	for dw in doorways:
		var roll := rng.randf()   # (one roll per doorway, in doorway order, whether it is allowed or not)
		if not allowed(dw, plan):
			continue
		cands.append([score(str(dw["room"]), plan), roll, int(dw["id"])])
	cands.sort_custom(func(x: Array, y: Array) -> bool:
		if x[0] != y[0]:
			return x[0] > y[0]
		return x[1] < y[1])
	var n := ceili(share * cands.size())
	var out: Array[int] = []
	for i in mini(n, cands.size()):
		out.append(int(cands[i][2]))
	out.sort()
	return out


## Can this doorway have a door at all?
static func allowed(dw: Dictionary, plan: SitePlan) -> bool:
	if not bool(dw.get("narrow", false)) or not bool(dw.get("door_ok", false)) or bool(dw.get("dead_end", false)):
		return false
	if plan != null and (dw["room"] == plan.start_room or dw["room"] == plan.exit_room):
		return false
	return true


## How much a room has to hide.
static func score(room: String, plan: SitePlan) -> float:
	if plan == null:
		return 0.0
	var s := 0.0
	for g in plan.gates:
		if g["room"] == room:
			s += SCORE_ORIGIN if bool(g["origin"]) else SCORE_GATE
	if int(plan.pack_budgets.get(room, 0)) > 0:
		s += SCORE_PACK
	return s
