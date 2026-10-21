class_name SewerCluster
extends RefCounted
## SEWER PHASE 3 (docs/design/sewer-concept.md, "Phase 3 as built"): WHICH floors get a sewer cluster and with what dice. The
## cluster itself is cut by DungeonGen (its "sewer" option: 2-4 rooms of a wing of the room tree, one base level, their own
## links flattened, a service stair down into them) and flooded by SewerPlanner; the gator, the panel and the sluices come
## from GatorPlanner, HazardPlanner and DoorPlanner.
##
## The user's decision (2026-10-20): a cluster of 2-4 rooms on some lair and bunker floors, floors 2-3, reached by a service
## stair; the rest of the floor stays normal. A floor rolls RATE on dice of its own (seed_for), so a floor that rolls none,
## or whose rooms have no wing that fits, is byte for byte the floor it always was (DungeonGen builds it without the option).
##
## THE NETWORK SWITCH: the gator and the live wire have no network shape yet (phase 2), so a SHARED run never gets a cluster
## (NETWORKED false: crew floors, and their checksum, stay exactly as before). Phase 2 flips NETWORKED once the gator streams,
## the panel's break is an obj event and map.sewer is in NetFloor's checksum.

## Phase 2 sets this true: then a shared run rolls clusters too (every machine builds the same one from the seed).
const NETWORKED := false
## The share of eligible floors that roll a cluster (before the wing check, which some floors fail: see the doc for the
## measured share of floors 2-3 that end up with one).
const RATE := 0.5
## The floors that may have one (floor 1 is the van's: the crew has not gone down yet).
const FLOORS: Array[int] = [2, 3]
## The site types that may have one (all five clients build on a bunker or a lair today).
const SITES: Array[String] = ["bunker", "lair"]
const MIN_ROOMS := 2
const MAX_ROOMS := 4
## How far the service stair goes down, in levels (two flights of two or three). The cluster's floor stays at level 1 or
## more (its water is one level lower).
const DROP_MIN := 3
const DROP_MAX := 5
const FLIGHT_MAX := 3            ## the most levels one STAIRS cell of the service stair climbs
const MIN_LEVEL := 1

## Dev (--sewer-floor, SewerDev.parse): every floor of a solo job gets a cluster if any wing fits, whatever the site, floor or
## roll. Never in a shared run.
static var force := false


## The cluster's own seed for floor `floor_n` of `run` (0: no cluster). A shared run never gets one until NETWORKED.
static func seed_for(run: ContractRun, floor_n: int, shared: bool) -> int:
	if run == null or (shared and not NETWORKED):
		return 0
	if not force and (not FLOORS.has(floor_n) or not SITES.has(run.site_type)):
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = (run.floor_seed(floor_n) * 6151 + floor_n * 389 + 23) & 0x7fffffff
	var roll := rng.randf()
	if not force and roll >= RATE:
		return 0
	return int(rng.randi() & 0x3fffffff) | 1


## The water's look for a site (SewerView.LOOKS): the bunker's storm drain in concrete, the lair's sewer in brick, the tech
## founder's cooling culverts toxic.
static func look_for(run: ContractRun) -> String:
	if run == null:
		return "concrete"
	if run.archetype_id == "founder":
		return "toxic"
	return "brick" if run.site_type == "lair" else "concrete"
