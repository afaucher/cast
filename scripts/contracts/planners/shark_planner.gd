class_name SharkPlanner
extends RefCounted
## The pool sharks of a floor (docs/design/sharks.md "As built"): plan() chooses them (SitePlan.sharks) and spawn() puts
## them, and the imp gunners of the "imp" ones, into the world. SiteBuilder.plan / spawn call them; moved out of SiteBuilder
## verbatim (refactor plan H8).


## Where sharks live (the design's proposals, built as defaults; the user's rules of 2026-10-19 marked so):
##   - floor 1: none (the moat keeps its decorative fins);
##   - never a specimen pool (a single row: a 2.4 shark cannot turn round in it), and only water at least two rows wide
##     (SHARK_MIN_INRADIUS; user: "sharks go only in fallback pools 2 rows wide") or a moat ring;
##   - a moat ring: always a regular shark, circling (user: "keep the one-row ring for a circling regular shark");
##   - a moat room's two-row shark pool or its lagoon: SHARK_MOAT_MIX by floor (laser from floor 2, the imp from 3);
##   - the bunker's indoor pool: a regular shark in SHARK_POOL_ODDS of them (the bunker gets the regular one only).
## Its own dice (`floor_seed * 4231 + floor * 37 + 19`): it moves nothing else on the floor. Each shark's pool record gets
## `shark` (its variant) so PoolView builds no decorative fins there.
const SHARK_MIN_INRADIUS := 2.0
const SHARK_POOL_ODDS := 0.35
## floor -> [regular, laser, imp] weights for a moat room's pool or lagoon
const SHARK_MOAT_MIX := {2: [0.5, 0.5, 0.0], 3: [0.2, 0.35, 0.45]}


static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan) -> void:
	p.sharks.clear()
	if floor_n < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = run.floor_seed(floor_n) * 4231 + floor_n * 37 + 19
	for i in map.pools.size():
		var rec: Dictionary = map.pools[i]
		var look := str(rec["look"])
		var hole: Array = rec.get("hole", [])
		var variant := ""
		if look == PoolGeo.LOOK_MOAT and not hole.is_empty():
			variant = "regular"
		elif look == PoolGeo.LOOK_MOAT:
			if SharkSteer.inradius(PackedVector2Array(rec["outline"])) < SHARK_MIN_INRADIUS:
				continue
			var mix: Array = SHARK_MOAT_MIX.get(mini(floor_n, 3), SHARK_MOAT_MIX[3])
			var r := rng.randf()
			variant = "regular" if r < float(mix[0]) else ("laser" if r < float(mix[0]) + float(mix[1]) else "imp")
		elif look == PoolGeo.LOOK_POOL:
			var roll := rng.randf()
			if roll >= SHARK_POOL_ODDS or SharkSteer.inradius(PackedVector2Array(rec["outline"])) < SHARK_MIN_INRADIUS:
				continue
			variant = "regular"
		else:
			continue   # (the specimen pool: the escaped specimen's, never a shark's)
		var start := Vector2.ZERO
		var heading := Vector2.RIGHT
		if not hole.is_empty():
			var ol: Array = rec["outline"]
			var k := rng.randi_range(0, hole.size() - 1)
			var a: Vector2 = ((ol[k] as Vector2) + (hole[k] as Vector2)) * 0.5
			var b: Vector2 = ((ol[(k + 1) % ol.size()] as Vector2) + (hole[(k + 1) % hole.size()] as Vector2)) * 0.5
			start = a.lerp(b, 0.5)
			heading = (b - a).normalized()
		else:
			var ax: Vector2 = rec["axis"]
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			start = (rec["center"] as Vector2) - ax * side * 0.6
			heading = ax * side
		rec["shark"] = variant
		p.sharks.append({"pool": i, "variant": variant, "start": start, "heading": heading})


## The planned sharks (and the imp gunners of the "imp" ones), after the scouts and before the doors: seed-built on every
## machine, so their net ids follow the scouts' and no earlier id moves.
static func spawn(run: ContractRun, p: SitePlan, site: SiteBuilder.Site) -> void:
	var map := GameWorld.map
	if map == null:
		return
	for sp in p.sharks:
		var idx := int(sp["pool"])
		if idx < 0 or idx >= map.pools.size():
			continue
		var rec: Dictionary = map.pools[idx]
		var s := Shark.new()
		s.setup(str(sp["variant"]), idx, sp["start"], sp["heading"])
		var at: Vector2 = sp["start"]
		GameWorld.spawn(s, Vector3(at.x, float(rec["floor_level"]) * Hex.LEVEL_HEIGHT + Shark.FLOAT, at.y))
		site.sharks.append(s)
		if str(sp["variant"]) == "imp":
			var j := Jockey.new()
			j.name = "Jockey"
			j.mount = s
			s.rider = j
			GameWorld.spawn(j, s.global_position)
			site.jockeys.append(j)
			site.monsters.append(j)
			if run.pest == "everything" or run.pest == j.kind:
				site.pest_spawned += 1
