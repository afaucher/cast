class_name LavaSite
extends RefCounted
## LAVA CAVES IN THE GENERATOR (docs/design/lava-playtest.md, "As built: caves on real floors"): WHICH floors get a lava cave
## and with what dice. The cave itself is cut by DungeonGen (its "cave" option, CaveGen: a wing of 2-3 rooms of the room tree
## turned into rock chambers over a lava plane, joined by two-wide bridges) and planned by LavaPlanner (the look, the archers
## on their isles, the packs at the bridgeheads); LavaField runs its rules (lava is void with a bite, damp crusts it).
##
## The user's decisions (2026-10-20 / 2026-10-21):
##   - lava caves appear only on SUPERVILLAIN sites and NEXT TO HELLGATES, not the founder's;
##   - the generator's patterns are the playtest's caves 1-4: Causeway, Fork, Ring, Gauntlet (not 5, the Crag);
##   - bridges two wide, widened to three at the bridgeheads; a damp crust can always reach an archer isle.
## So a floor rolls one of two kinds of cave on dice of its own (seed_for):
##   - VILLAIN: floors 2-3 of a supervillain's volcano lair, RATE_VILLAIN (the lair's lower levels are the volcano);
##   - GATE: floor 2 of any other client but the founder (floor 2 is the last floor of small hellgates: floor 3 holds only
##     the origin gate, in the story's room), RATE_GATE, and the cave's far chamber MUST hold one of the floor's hellgates
##     (needs_gate: GatePlanner puts the floor's first gate there): the cave is where the gate leaks into the level.
## Either look follows the gate: a cave with a hellgate in it is HELLFIRE, else MAGMA (LavaPlanner, the "lava" theme row).
## A floor that rolls none, or whose rooms have no wing that fits, is byte for byte the floor it always was (DungeonGen builds
## it without the option). A floor that rolls a cave and a sewer cluster gets the cave (one set piece a floor); when the cave
## does not fit it gets its cluster.
##
## NETWORKED: true. Every machine builds the same cave from the seed (map.cave and map.lava in NetFloor's checksum), the crust
## is a scheduled effect every machine computes from the damp cast's shared time (LavaField), and every verb is applied only
## where the actor is resolved, so a crew rolls caves exactly as a solo run of the seed does.

const NETWORKED := true
const RATE_VILLAIN := 0.5
const RATE_GATE := 0.3
const VILLAIN := "supervillain"
const VILLAIN_FLOORS: Array[int] = [2, 3]
const GATE_FLOORS: Array[int] = [2]
const NOT_FOR: Array[String] = ["founder"]   ## never a cave (the user, 2026-10-20: "Supervillain + hellgates", not the founder)
const MIN_ROOMS := 2
const MAX_ROOMS := 3
const PATTERNS: Array[String] = ["causeway", "fork", "ring", "gauntlet"]

## Dev (--lava-floor, LavaDev.parse): every floor of a job gets a cave where any wing fits, whatever the site, floor or roll
## (a crew: every window with the flag; the load barrier's checksum sends out one that built a different floor).
static var force := false
## Dev (--lava-pattern NAME): the pattern a forced cave tries first ("" = the dice).
static var force_pattern := ""


## The cave's own seed for floor `floor_n` of `run` (0: no cave). A shared run gets the same as a solo one (NETWORKED).
static func seed_for(run: ContractRun, floor_n: int, shared: bool) -> int:
	if run == null or (shared and not NETWORKED):
		return 0
	var rng := _dice(run, floor_n)
	var roll := rng.randf()
	var s := int(rng.randi() & 0x3fffffff) | 1
	if force:
		return s
	if NOT_FOR.has(run.archetype_id):
		return 0
	if run.archetype_id == VILLAIN:
		return s if VILLAIN_FLOORS.has(floor_n) and roll < RATE_VILLAIN else 0
	return s if GATE_FLOORS.has(floor_n) and roll < RATE_GATE else 0


## Must this floor's cave hold a hellgate (the GATE kind: any client but the supervillain)? A forced cave on a floor with
## small gates holds one too, so the dev flag shows both kinds.
static func needs_gate(run: ContractRun, floor_n: int) -> bool:
	if run == null or floor_n < 1 or floor_n >= ContractRun.FLOOR_COUNT or int(run.floor_gates[floor_n - 1]) <= 0:
		return false
	return run.archetype_id != VILLAIN or force


static func _dice(run: ContractRun, floor_n: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (run.floor_seed(floor_n) * 4129 + floor_n * 211 + 71) & 0x7fffffff
	return rng
