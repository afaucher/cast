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
## THE NETWORK SWITCH (sewer phase 2, "Phase 2 as built"): the gator streams (its nip, shove and death go through the net
## layer), the panel's break is an obj.break with its shared moment that every machine's LiveWire runs from, and map.sewer and
## each gator's spawn data are in NetFloor's checksum, so a SHARED run rolls clusters too: every machine builds the same one
## from the seed (the same dice as solo, so a crew floor is the floor a solo run of that seed gets).

## True since phase 2: a shared run rolls clusters like a solo one. False would keep crew floors without one.
const NETWORKED := true
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

## Dev (--sewer-floor, SewerDev.parse): every floor of a job gets a cluster if any wing fits, whatever the site, floor or
## roll. In a crew every window needs the flag (run.ps1 -Crew passes it to all); the load barrier's checksum sends out one
## that built a different floor.
static var force := false


## The cluster's own seed for floor `floor_n` of `run` (0: no cluster). A shared run gets the same as a solo one (NETWORKED).
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
