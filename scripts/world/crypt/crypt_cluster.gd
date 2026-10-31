class_name CryptCluster
extends RefCounted
## HAUNTED H2 (docs/design/haunted-build-plan.md, "H2 as built"): WHICH floors get a crypt section and with what dice. The
## crypt itself is cut by DungeonGen (its "crypt" option: the sewer cluster's machinery, a wing of 2-4 rooms of the room tree
## at one base level, their own links flat, a narrow stair of flights down into them) and themed and dressed by CryptPlanner
## (the look test's vault and chapel sets, docs/design/crypt-section.md).
##
## The design (new-themes.md, "Sites"): a haunted site is a room pool plus a section pool; the mansion's sections are the crypt
## and the sewer, the church's only the crypt. The church has one room of its own (the nave), so it leans on its crypt: it may
## roll one on every floor, and more often. A floor rolls its site's RATE on dice of its own (seed_for), so a floor that rolls
## none, or whose rooms have no wing that fits, is byte for byte the floor it always was (DungeonGen builds it without the
## option). Floor data only, like the sewer: every machine builds the same crypt from the seed (map.crypt is in NetFloor's
## checksum), so a shared run rolls it too.

## The share of eligible floors that roll a crypt, by site (before the wing check, which some floors fail).
const RATE := {"mansion": 0.5, "church": 0.75}
## The floors that may have one, by site: the mansion's below its ground floor (like the sewer), the church's on any floor
## (its crypt is what it has instead of more rooms).
const FLOORS := {"mansion": [2, 3], "church": [1, 2, 3]}
## The material set by site (CryptLook.LOOK): the vault under a mansion, the chapel under a church. A forced crypt on any
## other site (--crypt-floor) is a vault.
const SETS := {"mansion": "vault", "church": "chapel"}
const MIN_ROOMS := 2
const MAX_ROOMS := 4
## How far the stair goes down, in levels (the look test's crypt is 6 levels, 3.0, below the room above: two flights of
## three). The crypt's floor stays at level MIN_LEVEL or more.
const DROP_MIN := 4
const DROP_MAX := 6
const FLIGHT_MAX := 3            ## the most levels one STAIRS cell of the crypt stair climbs
const MIN_LEVEL := 0

## Dev (--crypt-floor, CryptDev.parse): every floor of a job gets a crypt if any wing fits, whatever the site, floor or roll.
## In a crew every window needs the flag; the load barrier's checksum sends out one that built a different floor.
static var force := false


## The crypt's own seed for floor `floor_n` of `run` (0: no crypt). A shared run gets the same as a solo one.
static func seed_for(run: ContractRun, floor_n: int, _shared: bool = false) -> int:
	if run == null:
		return 0
	if not force and (not RATE.has(run.site_type) or not (FLOORS[run.site_type] as Array).has(floor_n)):
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = (run.floor_seed(floor_n) * 7919 + floor_n * 443 + 61) & 0x7fffffff
	var roll := rng.randf()
	if not force and roll >= float(RATE[run.site_type]):
		return 0
	return int(rng.randi() & 0x3fffffff) | 1


## The crypt's material set for a site ("vault" or "chapel").
static func set_for(site_type: String) -> String:
	return str(SETS.get(site_type, "vault"))
