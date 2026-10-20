extends MonsterTestBase
## Pool sharks (docs/design/sharks.md "As built"; Shark, SharkSteer, SharkBody, Jockey, SiteBuilder._plan_sharks, PoolGeo's
## lagoon), one process:
##  - confinement: a shark patrolling a convex pool and a moat ring never leaves its water and keeps its centre line off
##    the rim (except the lunge's head, up to LUNGE_OVER onto the deck);
##  - smooth turning: its heading never turns faster than the turning radius allows, nor its speed jumps;
##  - the bite: a hero at the rim takes BITE_DAMAGE once and is pushed back onto the deck, away from the water;
##  - the laser: a hero in the nose cone is charged at, the line locks, the beam lands once (BEAM_DAMAGE) at the fire time;
##    Combat.beam stops at the first body and at a wall; it lights an explosive prop;
##  - the imp gunner: a hard shove knocks it off (it lands, it never remounts), a light one does not; its shark's death
##    throws it to the deck;
##  - status: a hard shove (tentacles) holds the shark, corn in its water is chum, vines root it, it never moves on a shove;
##  - property: the kill bills its price once to the killer ("Shark" $8,400, "Laser shark" $12,600), hits before it are
##    free, a second blow after it bills nothing; it is not a monster (no pest), its gunner is an imp;
##  - placement (generated floors): deterministic per seed and in the plan, none on floor 1, never in a specimen pool or a
##    pool narrower than two rows, rings get a regular shark, the lagoon is dealt and fits (three rows, convex, a shark
##    circles in it), every record with a shark has no decorative fins; and it is cheap (SiteBuilder.last_shark_usec).

const DT := 1.0 / 60.0
const RUN_SEEDS: Array[int] = [1, 2, 3, 4, 5, 7, 42]


func _init() -> void:
	timeout_sec = 400.0   # (game seconds: the timer starts before setup())


func setup() -> void:
	timeout_sec = 240.0
	await _check_confinement("pool")
	await _check_confinement("moat")
	await _check_bite()
	await _check_laser()
	_check_beam()
	await _check_imp()
	await _check_status()
	await _check_billing()
	_check_generated()
	finish()


# --- a synthetic pool room ---------------------------------------------------------------------------------------

## One round room with walls round it and its pool carved by PoolGeo (`theme`'s look). Returns the map.
func _pool_map(theme: String, radius: int = 9) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 0).tag = "room:0"
	for c in Hex.ring(Vector2i.ZERO, radius + 1):
		m.set_cell(c, 3, HexMap.Tile.WALL)
	m.cut_walls()
	var p := SitePlan.new()
	SiteBuilder._index_rooms(m, p)
	p.room_themes = {"room:0": theme}
	PoolGeo.carve(m, p, {}, {}, 11)
	return m


func _shark(variant: String, rec_i: int = 0) -> Shark:
	var rec: Dictionary = GameWorld.map.pools[rec_i]
	var s := Shark.new()
	var start: Vector2 = rec["center"]
	var heading: Vector2 = rec["axis"]
	if not (rec["hole"] as Array).is_empty():
		var mid := PoolGeo.channel(rec)
		start = mid[0].lerp(mid[1], 0.5)
		heading = (mid[1] - mid[0]).normalized()
	s.setup(variant, rec_i, start, heading)
	GameWorld.spawn(s, Vector3(start.x, float(rec["floor_level"]) * Hex.LEVEL_HEIGHT + Shark.FLOAT, start.y))
	return s


## A point on the deck `out` beyond the middle of outline edge i, and that edge's outward normal (X/Z).
func _deck(rec: Dictionary, i: int, out: float) -> Array:
	var ol: Array = rec["outline"]
	var a: Vector2 = ol[i]
	var b: Vector2 = ol[(i + 1) % ol.size()]
	var n: Vector2 = PoolGeo.edge_normals(ol)[i]
	var p := (a + b) * 0.5 + n * out
	return [Vector3(p.x, float(rec["deck_level"]) * Hex.LEVEL_HEIGHT, p.y), n]


func _hero_at(p: Vector3) -> Actor:
	var h := add_hero(Hex.from_world(p))
	h.global_position = p
	return h


# --- confinement and smooth turning --------------------------------------------------------------------------------

func _check_confinement(theme: String) -> void:
	var m := _pool_map(theme, 9)
	new_world(m)
	check(not m.pools.is_empty(), "%s: a pool to swim in" % theme)
	if m.pools.is_empty():
		return
	var s := _shark("regular")
	await frames(2)
	var worst := INF
	var dry := 0
	var worst_turn := 0.0
	var worst_dv := 0.0
	var prev_dir := s.steer.dir
	var prev_speed := s.steer.speed
	var dist := 0.0
	var prev_pos := s.steer.pos
	for i in 60 * 20:
		await get_tree().physics_frame
		var d := s.steer.rim(s.steer.pos)
		worst = minf(worst, d)
		if not m.water_at(s.global_position):
			dry += 1
		var omega_cap := maxf(prev_speed / SharkSteer.R_TURN, SharkSteer.OMEGA_FLOOR) + SharkSteer.YAW_ACCEL * DT
		worst_turn = maxf(worst_turn, absf(prev_dir.angle_to(s.steer.dir)) / DT / omega_cap)
		worst_dv = maxf(worst_dv, absf(s.steer.speed - prev_speed) / DT)
		dist += s.steer.pos.distance_to(prev_pos)
		prev_pos = s.steer.pos
		prev_dir = s.steer.dir
		prev_speed = s.steer.speed
	print("sharks: %s: 20 s of patrol, %.1f swum, nearest the rim %.3f, worst turn %.2f of the cap, worst speed change %.2f u/s^2" % [theme, dist, worst, worst_turn, worst_dv])
	check(worst >= SharkSteer.CLEAR - 0.02, "%s: the centre line keeps CLEAR off every rim (nearest %.3f)" % [theme, worst])
	eq(dry, 0, "%s: it never leaves the water" % theme)
	check(worst_turn <= 1.01, "%s: it never turns faster than its turning radius allows (%.2f of the cap)" % [theme, worst_turn])
	check(worst_dv <= SharkSteer.DECEL + 0.01, "%s: its speed ramps, never jumps (%.2f u/s^2)" % [theme, worst_dv])
	check(dist > 18.0, "%s: it patrols (%.1f in 20 s)" % [theme, dist])
	# a shove never moves it; a hard one holds it
	var before := s.global_position
	s.shove(Vector3.RIGHT, 3.0, null)
	await frames(3)
	check(s.state == Shark.HELD, "%s: a hard shove holds it" % theme)
	check(GameWorld.flat_distance(s.global_position, before) < 0.2, "%s: a shove does not move it" % theme)


# --- the bite ----------------------------------------------------------------------------------------------------

func _check_bite() -> void:
	var m := _pool_map("pool", 9)
	new_world(m)
	var rec: Dictionary = m.pools[0]
	var s := _shark("regular")
	var spot: Array = _deck(rec, 0, 0.7)
	var h := _hero_at(spot[0])
	var hp0 := h.hp
	var bitten := await wait_until(func() -> bool: return h.hp < hp0, 60 * 12)
	check(bitten, "the shark bites a hero at its rim")
	near(hp0 - h.hp, Shark.BITE_DAMAGE, 0.01, "the bite does BITE_DAMAGE")
	await frames(30)
	var rim_after := s.steer.rim(Vector2(h.global_position.x, h.global_position.z))
	check(rim_after < -0.7 - 0.5, "the bite pushes the hero back onto the deck, away from the water (%.2f past the rim)" % -rim_after)
	check(not m.water_at(h.global_position), "the hero is not in the water")
	eq(int(h.hp), int(hp0 - Shark.BITE_DAMAGE), "one bite per lunge")
	await wait_until(func() -> bool: return s.state == Shark.CRUISE, 120)
	check(s.state != Shark.BITE, "it slides back and swims on")


# --- the laser -------------------------------------------------------------------------------------------------------

func _check_laser() -> void:
	var m := _pool_map("pool", 10)
	new_world(m)
	var rec: Dictionary = m.pools[0]
	var s := _shark("laser")
	await frames(2)
	# a hero ahead of its snout, out on the deck
	var ahead := s.global_position + s.facing * 7.5
	ahead.y = float(rec["deck_level"]) * Hex.LEVEL_HEIGHT
	var h := _hero_at(ahead)
	var hp0 := h.hp
	var charged := await wait_until(func() -> bool: return s.state == Shark.CHARGE, 120)
	check(charged, "a laser shark charges at a hero in its nose cone")
	eq(s.charge_victim, h, "... at that hero")
	var locked := await wait_until(func() -> bool: return s.fire_at >= 0.0, 120)
	check(locked, "the line locks")
	var fire_t := s.fire_at
	var hit := await wait_until(func() -> bool: return h.hp < hp0, 120)
	check(hit, "the beam lands")
	check(GameWorld.time >= fire_t - 0.001 and GameWorld.time <= fire_t + DT * 2.0, "... at the fire time (%.3f vs %.3f)" % [GameWorld.time, fire_t])
	near(hp0 - h.hp, Shark.BEAM_DAMAGE, 0.01, "the beam does BEAM_DAMAGE once")
	await frames(30)
	near(hp0 - h.hp, Shark.BEAM_DAMAGE, 0.01, "... and only once")


func _check_beam() -> void:
	var m := flat_map(8)
	wall_where(m, func(p: Vector3) -> bool: return p.x > 9.0)
	new_world(m)
	var src := Actor.new()
	src.team = GameWorld.TEAM_NEUTRAL
	GameWorld.spawn(src, Vector3(-6, 0, 0))
	var a := add_hero(Hex.from_world(Vector3(-2, 0, 0)))
	a.global_position = Vector3(-2, 0, 0.1)
	var b := add_hero(Hex.from_world(Vector3(2, 0, 0)))
	b.global_position = Vector3(2, 0, 0)
	var r := Combat.beam(src, Vector3(-5, 0.4, 0), Vector3.RIGHT, 20.0, 22.0)
	eq(r["hit"], a, "the beam stops at the first body")
	near(100.0 - a.hp, 22.0, 0.01, "... which takes the hit")
	near(b.hp, 100.0, 0.01, "... and shields the one behind")
	a.die()
	b.die()
	var r2 := Combat.beam(src, Vector3(-5, 0.4, 0), Vector3.RIGHT, 30.0, 22.0)
	check(r2["hit"] == null and (r2["end"] as Vector3).x < 9.6, "a wall stops it (%.1f)" % (r2["end"] as Vector3).x)
	var drum := PricedProp.spawn(Hex.from_world(Vector3(3, 0, 0)), "oil_drum", {})
	check(drum is ExplosiveProp, "an oil drum to shoot")
	var r3 := Combat.beam(src, Vector3(-5, 0.4, drum.global_position.z), Vector3.RIGHT, 20.0, 22.0)
	eq(r3["hit"], drum, "the beam meets the drum")
	check((drum as ExplosiveProp).is_lit(), "... and lights it (a hard hit)")


# --- the imp gunner -------------------------------------------------------------------------------------------------

func _check_imp() -> void:
	var m := _pool_map("moat", 9)
	new_world(m)
	var s := _shark("imp")
	var j := Jockey.new()
	j.mount = s
	s.rider = j
	GameWorld.spawn(j, s.global_position)
	await frames(5)
	check(j.mounted and s.ridden(), "the imp sits in the saddle")
	check(GameWorld.flat_distance(j.global_position, s.global_position) < 1.0, "... on its shark")
	check(j.is_in_group("monsters") and j.kind == "swarmer" and not s.is_in_group("monsters"), "the gunner is an imp (a pest); the shark is not a monster")
	j.shove(Vector3.RIGHT, 0.5, null)
	await frames(3)
	check(j.mounted, "a light shove: it hangs on")
	j.shove(Vector3.RIGHT, 2.0, null)
	await frames(40)
	check(not j.mounted and not j.dead, "a hard shove knocks it off")
	check(GameWorld.flat_distance(j.global_position, s.global_position) > 0.5, "... it lands off its shark")
	await frames(60)
	check(not j.mounted, "it never climbs back on")
	check(not s.ridden(), "the shark is riderless now")
	# a shark's death throws a mounted gunner to the deck
	var m2 := _pool_map("pool", 9)
	new_world(m2)
	var s2 := _shark("imp")
	var j2 := Jockey.new()
	j2.mount = s2
	s2.rider = j2
	GameWorld.spawn(j2, s2.global_position)
	await frames(5)
	Ledger.begin_contract(1000000)
	s2.apply_damage(500.0, null)
	await frames(5)
	check(not j2.mounted and not j2.dead, "its shark killed: the gunner jumps off")
	check(not m2.water_at(j2.global_position), "... onto the deck")


# --- status ------------------------------------------------------------------------------------------------------

func _check_status() -> void:
	var m := _pool_map("pool", 9)
	new_world(m)
	var s := _shark("regular")
	await frames(5)
	Shark.corn_at(s.global_position + s.facing)
	await frames(2)
	eq(s.state, Shark.CHUM, "corn in its water is chum")
	await frames(int(Shark.CHUM_T * 60.0) + 10)
	check(s.state != Shark.CHUM, "... for CHUM_T")
	s.set_modifier("vines", 1.0, 2.0, Actor.STAT_ROOT)
	var p0 := s.global_position
	await frames(30)
	check(GameWorld.flat_distance(p0, s.global_position) < 0.05, "vines root it")
	check(s.is_in_group(Burning.FIREPROOF), "it never burns (always wet)")


# --- property ------------------------------------------------------------------------------------------------------

func _check_billing() -> void:
	eq(int(Shark.PRICES["regular"]), 8400, "a shark is $8,400 (the design's $12,000 less 30 %)")
	eq(int(Shark.PRICES["laser"]), 12600, "a laser shark is $12,600 ($18,000 less 30 %)")
	for v: String in ["regular", "laser"]:
		var m := _pool_map("pool", 9)
		new_world(m)
		Ledger.begin_contract(1000000)
		var s := _shark(v)
		var h := add_hero(Vector2i(8, 0))
		h.display_name = "Wick"
		await frames(2)
		s.apply_damage(60.0, h)
		eq(Ledger.lines.size(), 0, "%s: a hit that does not kill it is free" % v)
		s.apply_damage(200.0, h)
		check(s.dead, "%s: it can be killed (HP %d)" % [v, int(Shark.HP)])
		eq(Ledger.lines.size(), 1, "%s: the kill bills once" % v)
		if Ledger.lines.size() == 1:
			var line: Dictionary = Ledger.lines[0]
			eq(str(line["kind"]), "damage", "%s: a damage line" % v)
			eq(int(line["amount"]), int(Shark.PRICES[v]), "%s: its full price" % v)
			eq(str(line["label"]), str(Shark.NAMES[v]), "%s: worded like a prop" % v)
			eq(str(line["who"]), "Wick", "%s: billed to the killer" % v)
		s.apply_damage(50.0, h)
		eq(Ledger.lines.size(), 1, "%s: nothing more after the kill" % v)
		check(is_instance_valid(s), "%s: the corpse floats on (not freed)" % v)


# --- generated floors ---------------------------------------------------------------------------------------------

func _check_generated() -> void:
	var counts := {"regular": 0, "laser": 0, "imp": 0}
	var lagoons := 0
	var lagoon_sharks := 0
	var floor1 := 0
	var bad := 0
	var worst_us := 0
	var total_us := 0
	var plans := 0
	var finds: Array[String] = []
	for id in ClientArchetype.IDS:
		for s in RUN_SEEDS:
			var run := ContractRun.make(id, s, float(s % 10) / 10.0 + 0.05)
			var catalog := PricedProp.catalog(run.site_type)
			for f in range(1, ContractRun.FLOOR_COUNT + 1):
				var map := DungeonGen.for_run(run, f)
				var plan := SiteBuilder.plan(map, run, f, catalog)
				plans += 1
				worst_us = maxi(worst_us, SiteBuilder.last_shark_usec)
				total_us += SiteBuilder.last_shark_usec
				var tag := "%s/%d floor %d" % [id, s, f]
				if f == 1:
					floor1 += plan.sharks.size()
				for rec in map.pools:
					if str(rec.get("shape", "")) == PoolGeo.LAGOON:
						lagoons += 1
						check(SharkSteer.inradius(PackedVector2Array(rec["outline"])) > 2.9, "%s: a lagoon is three rows wide" % tag)
				var again := DungeonGen.for_run(run, f)
				var plan2 := SiteBuilder.plan(again, run, f, catalog)
				check(NetFloor.canon(plan.sharks) == NetFloor.canon(plan2.sharks), "%s: the sharks are the same from the same seed" % tag)
				for sp in plan.sharks:
					var rec: Dictionary = map.pools[int(sp["pool"])]
					var v := str(sp["variant"])
					counts[v] = int(counts[v]) + 1
					finds.append("%s %s %s" % [tag, v, "lagoon" if str(rec.get("shape", "")) == PoolGeo.LAGOON else ("ring" if not (rec["hole"] as Array).is_empty() else str(rec["look"]))])
					if str(rec.get("shape", "")) == PoolGeo.LAGOON:
						lagoon_sharks += 1
					eq(str(rec.get("shark", "")), v, "%s: its pool record carries the shark (no decorative fins)" % tag)
					if str(rec["look"]) == PoolGeo.LOOK_SPECIMEN:
						bad += 1
					elif (rec["hole"] as Array).is_empty() and SharkSteer.inradius(PackedVector2Array(rec["outline"])) < SiteBuilder.SHARK_MIN_INRADIUS:
						bad += 1
					elif not (rec["hole"] as Array).is_empty() and v != "regular":
						bad += 1
					if run.site_type == "bunker" and v != "regular":
						bad += 1
					if v == "imp" and f < 3:
						bad += 1
	print("sharks: %s over %d floors, %d lagoons (%d with a shark); planning %.2f ms a floor on average, worst %.2f ms" % [str(counts), plans, lagoons, lagoon_sharks, float(total_us) / float(plans) / 1000.0, float(worst_us) / 1000.0])
	for line in finds:
		print("  shark: " + line)
	eq(floor1, 0, "no shark on floor 1")
	eq(bad, 0, "never in a specimen pool or a pool under two rows, a ring's is regular, the bunker's regular, the imp from floor 3")
	check(int(counts["regular"]) > 0 and int(counts["laser"]) > 0 and int(counts["imp"]) > 0, "every variant is dealt somewhere (%s)" % str(counts))
	check(lagoons > 0, "the lagoon is dealt and fits (%d)" % lagoons)
	check(float(worst_us) / 1000.0 < 20.0, "placing the sharks is cheap (worst %.2f ms)" % (float(worst_us) / 1000.0))
