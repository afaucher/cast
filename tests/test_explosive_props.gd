extends TestCase
## Explosive props (ExplosiveProp, docs/design/hazards.md "Explosive props (as built)"): the catalog and the models; fire
## lights the fuse (a fireball, a burning walker) and the fuse holds its time; a hard hit, an arrow, a slam or a hard shove
## lights it and a light tap does not; the blast damages and shoves heroes, monsters and employees (falling off, nothing
## outside it); a chain goes off as a sequence; the bill goes to the igniter once (the chain and what it breaks too); a
## soaked one will not light, breaks as a dud, and a soak puts a fuse out in time (not in its last DOUSE_LOCK); the
## placement rules hold on generated floors and are deterministic, and the explosives are in the floor checksum.

var root: Node3D


func _flat_map(radius: int = 12) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 0)
	return m


func _fresh() -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(_flat_map(), root, 5)
	Ledger.begin_contract(1000000)


func _hero(pos: Vector3, hero_name: String = "Wick") -> Hero:
	var h := Hero.new()
	h.display_name = hero_name
	GameWorld.spawn(h, pos)
	h.snap_to_ground()
	return h


func _kit_hero(pos: Vector3, kit: String) -> Hero:
	var h := Hero.new()
	HeroKit.apply_to(h, kit)
	h.display_name = kit.capitalize()
	GameWorld.spawn(h, pos)
	h.snap_to_ground()
	return h


func _prop(kind: String, pos: Vector3) -> PricedProp:
	var p := PricedProp.spawn(Hex.from_world(pos), kind, {})
	p.global_position = Vector3(pos.x, p.global_position.y, pos.z)
	return p


func _boom(kind: String, pos: Vector3) -> ExplosiveProp:
	return _prop(kind, pos) as ExplosiveProp


func _monster(kind: String, pos: Vector3) -> Monster:
	var m := MonsterFactory.spawn(kind, Hex.from_world(pos))
	m.global_position = Vector3(pos.x, m.global_position.y, pos.z)
	m.aggro_range = 0.0
	m.set_physics_process(false)   # (it holds still: the test moves nothing but the blast does)
	return m


func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await frames(1)
	return cond.call()


func _lines(label: String) -> int:
	var n := 0
	for l in Ledger.lines:
		if str(l["label"]) == label:
			n += 1
	return n


func setup() -> void:
	timeout_sec = 400.0
	await _check_catalog()
	await _check_fire()
	await _check_hits()
	await _check_blast()
	await _check_chain_and_bill()
	await _check_damp()
	await _check_placement()
	finish()


# --- The catalog -------------------------------------------------------------------------------------------------------

func _check_catalog() -> void:
	_fresh()
	var kinds := PricedProp.hazard_kinds()
	eq(kinds.size(), 4, "four explosive kinds (%s)" % str(kinds))
	for k in kinds:
		check(not PricedProp.catalog("bunker").has(k) and not PricedProp.catalog("lair").has(k), "%s is never a site's random priced prop" % k)
		check(ExplosiveProp.BLAST.has(k), "%s has blast numbers" % k)
		var e := _boom(k, Vector3(-6.0 + 4.0 * float(kinds.find(k)), 0, -5))
		check(e != null, "%s spawns as an ExplosiveProp" % k)
		if e == null:
			continue
		check(e.is_in_group(ExplosiveProp.HAZARD_GROUP) and e.is_in_group(PricedProp.GROUP), "%s: an explosive and a priced prop" % k)
		check(e.price > 0 and e.team == GameWorld.TEAM_NEUTRAL and e.shove_mult == 0.0, "%s: priced, neutral, immovable" % k)
		check(e.fuse_time >= 1.0 and e.fuse_time <= 1.5, "%s: a fuse of 1.0-1.5 s (%.2f)" % [k, e.fuse_time])
		check(e.blast_radius >= 2.5 and e.blast_damage >= 35.0, "%s: a big blast (%.1f, %.0f)" % [k, e.blast_radius, e.blast_damage])
		var body := e.get_node_or_null("Model/Body") as MeshInstance3D
		check(body != null and body.mesh != null and body.mesh.get_surface_count() > 0, "%s has a model" % k)
		check(PropModels.HEIGHTS.has(k), "%s is in the z-fight registry (PropModels.HEIGHTS)" % k)
	eq(Ledger.lines.size(), 0, "placing them costs nothing")


# --- Fire lights it; the fuse holds its time ---------------------------------------------------------------------------

func _check_fire() -> void:
	_fresh()
	var hero := _hero(Vector3(-7, 0, 0), "Wick")
	var drum := _boom("oil_drum", Vector3(0, 0, 0))
	var blew_at := [-1.0]
	drum.blew.connect(func(_p: ExplosiveProp) -> void: blew_at[0] = GameWorld.time)
	await frames(2)
	ExplosiveProp.fire_at(Vector3(0.8, 0, 0), 1.5, hero)
	check(drum.is_lit(), "a fireball's blast lights it")
	near(drum.fuse_end - drum.fuse_start, drum.fuse_time, 0.0001, "the fuse is the kind's (%.2f s)" % drum.fuse_time)
	check(drum.igniter() == hero, "set off by the caster")
	check(drum.get_node_or_null("FuseFx") != null, "the fuse shows (sparks, glow, shake, the blast ring)")
	var lit_at := drum.fuse_start
	ExplosiveProp.fire_at(Vector3(0.8, 0, 0), 1.5, hero)   # (a second fire changes nothing)
	near(drum.fuse_start, lit_at, 0.0001, "lighting it again does not restart the fuse")
	await frames(int(drum.fuse_time * 60.0) - 3)
	check(not drum.blown and not drum.dead, "it is still burning just before its time")
	check(await _until(func() -> bool: return drum.dead, 20), "then it blows")
	check(drum.blown, "blown")
	near(blew_at[0] - lit_at, drum.fuse_time, 1.5 / 60.0, "the blast comes fuse_time after the light (%.3f s)" % (blew_at[0] - lit_at))
	eq(_lines("Oil drum"), 1, "and it is billed")

	# A real fireball at it, from across the room.
	_fresh()
	var caster := _hero(Vector3(-6, 0, 0), "Wick")
	var cyl := _boom("gas_cylinders", Vector3(0, 0, 0))
	await frames(2)
	SpellBook.cast("fireball", caster, 1.0, cyl.global_position)
	check(await _until(func() -> bool: return cyl.is_lit(), 90), "a cast fireball lights the gas cylinders")
	check(cyl.igniter() == caster, "... blamed on the caster")
	check(await _until(func() -> bool: return cyl.dead, 120), "and they blow")
	eq(_lines("Gas cylinders"), 1, "billed once (the fire and the blast's own hit are one bill)")
	eq(str(Ledger.lines.back().get("who", "")), "Wick", "to the caster")

	# A burning monster walking into it lights it; the bill goes to whoever set the monster on fire.
	_fresh()
	var firestarter := _hero(Vector3(-8, 0, 0), "Gasket")
	var tank := _boom("propane_tank", Vector3(0, 0, 0))
	var grunt := _monster("grunt", Vector3(0.95, 0, 0))
	await frames(4)
	check(not tank.is_lit(), "a monster beside it is nothing")
	Burning.ignite(grunt, firestarter, 6.0)
	check(await _until(func() -> bool: return tank.is_lit(), 10), "a burning monster touching it lights it")
	check(tank.igniter() == firestarter, "blamed on whoever set the monster on fire")


# --- Hits and shoves ---------------------------------------------------------------------------------------------------

func _check_hits() -> void:
	# A light tap (Wick's bow bash, 12) dents it for free; Gasket's hammer (28) lights it.
	_fresh()
	var wick := _kit_hero(Vector3(-1.2, 0, 0), "wick")
	var drum := _boom("oil_drum", Vector3(0.0, 0, 0))
	await frames(2)
	check(wick.melee(Vector3.RIGHT), "Wick bashes it")
	check(not drum.is_lit() and drum.hp < drum.max_hp, "a light tap dents it (%.0f of %.0f) and does not light it" % [drum.hp, drum.max_hp])
	eq(Ledger.lines.size(), 0, "a dent is free")
	var gasket := _kit_hero(Vector3(1.2, 0, 0.0), "gasket")
	await frames(2)
	check(gasket.melee(Vector3.LEFT), "Gasket swings his hammer at it")
	check(drum.is_lit(), "a hard hit (%.0f) lights it" % gasket.melee_damage)
	check(drum.hp >= 1.0 and not drum.dead, "and it does not break before the blast")
	var hp_lit := drum.hp
	drum.apply_damage(500.0, gasket)
	near(drum.hp, hp_lit, 0.001, "hits on a burning fuse do nothing")

	# Enough small dents light it instead of breaking it.
	_fresh()
	var tapper := _hero(Vector3(-5, 0, 0))
	var cyl := _boom("gas_cylinders", Vector3(0, 0, 0))
	var taps := 0
	while not cyl.is_lit() and taps < 10:
		cyl.apply_damage(10.0, tapper)
		taps += 1
	check(cyl.is_lit() and not cyl.dead, "small dents that would break it light it instead (after %d)" % taps)

	# A shove on it: a nudge does nothing, a hard one lights it.
	_fresh()
	var tank := _boom("propane_tank", Vector3(0, 0, 0))
	tank.shove(Vector3.RIGHT, 1.0, null)
	check(not tank.is_lit(), "a 1.0 shove on it does not light it")
	tank.shove(Vector3.RIGHT, ExplosiveProp.HARD_SHOVE + 0.5, null)
	check(tank.is_lit(), "a hard shove on it does")

	# An actor shoved into it: a nudge dents it, a hard slide lights it.
	_fresh()
	var pusher := _hero(Vector3(-6, 0, 3))
	var pack := _boom("battery_pack", Vector3(0, 0, 0))
	var dummy := TrainingDummy.new()
	dummy.max_hp = 1000.0
	GameWorld.spawn(dummy, Vector3(-1.3, 0, 0))
	dummy.snap_to_ground()
	await frames(2)
	dummy.shove(Vector3.RIGHT, 0.7, pusher)
	await frames(30)
	check(not pack.is_lit(), "a nudged dummy bumping it does not light it")
	dummy.global_position = Vector3(-1.6, dummy.global_position.y, 0)
	dummy.shove(Vector3.RIGHT, 3.0, pusher)
	check(await _until(func() -> bool: return pack.is_lit(), 40), "a dummy slammed into it lights it")
	check(pack.igniter() == pusher, "blamed on the shover")

	# Monsters: an archer's arrow punctures it; a brute's slam sets it off.
	_fresh()
	var archer = MonsterFactory.spawn("archer", Hex.from_world(Vector3(-6, 0, 0)))
	archer.aggro_range = 0.0
	var target := _boom("oil_drum", Vector3(0, 0, 0))
	await frames(2)
	var arrow: Projectile = archer._fire_arrow(Vector3.RIGHT, 8.0)
	var shot: WeakRef = weakref(arrow)
	arrow = null
	check(await _until(func() -> bool: return shot.get_ref() == null, 90), "the arrow lands")
	check(target.is_lit(), "an archer's arrow (8) punctures it: it lights")
	eq(Ledger.culprit_name(target.igniter()), "demons", "... set off by the demons")
	_fresh()
	var brute := _monster("brute", Vector3(-1.2, 0, 0))
	var slammed := _boom("gas_cylinders", Vector3(0.2, 0, 0.0))
	var lamp := _prop("crystal_lamp", Vector3(-1.2, 0, 1.2))
	Combat.slam(brute.global_position, 2.0, 25.0, 0.5, 1.0, 1.0, GameWorld.TEAM_HEROES, brute)
	check(slammed.is_lit(), "a brute's slam beside it lights it")
	near(lamp.hp, lamp.max_hp, 0.001, "(a slam leaves the other priced props alone)")
	check(ExplosiveProp.shot_damage(lamp, 8.0) == 8.0 and ExplosiveProp.shot_damage(slammed, 0.0) == 0.0, "only a real shot at an explosive punctures")


# --- The blast ---------------------------------------------------------------------------------------------------------

func _check_blast() -> void:
	_fresh()
	var igniter := _hero(Vector3(-9, 0, 0), "Wick")
	var drum := _boom("oil_drum", Vector3(0, 0, 0))
	var gasket := _hero(Vector3(1.4, 0, 0), "Gasket")
	var grunt := _monster("grunt", Vector3(-1.5, 0, 0.8))
	grunt.max_hp = 500.0
	grunt.hp = 500.0
	var emp := Employee.spawn(Hex.from_world(Vector3(0, 0, 2.2)), {"style": "staff", "name": "Pat"})
	var far := _monster("grunt", Vector3(0, 0, -6.0))
	await frames(3)
	if emp != null:
		emp.global_position = Vector3(0, emp.global_position.y, 2.2)
		emp.set_physics_process(false)
	var before := {}
	for a: Actor in [gasket, grunt, emp, far]:
		if a != null:
			before[a] = [a.hp, a.global_position]
	drum.ignite(igniter)
	check(await _until(func() -> bool: return drum.dead, 120), "it blows")
	var lost_g := float(before[gasket][0]) - gasket.hp
	var expect := drum.blast_damage * lerpf(1.0, ExplosiveProp.EDGE_MULT, 1.4 / drum.blast_radius)
	near(lost_g, expect, 0.5, "a hero 1.4 away takes the blast with its falloff (%.1f)" % lost_g)
	check(grunt.hp < float(before[grunt][0]) - 10.0, "a monster in it is hurt (%.0f)" % (float(before[grunt][0]) - grunt.hp))
	if check(emp != null, "an employee spawned"):
		check(emp.hp < float(before[emp][0]) - 5.0 or emp.dead, "an employee in it is hurt")
	near(far.hp, float(before[far][0]), 0.001, "a monster outside it is untouched")
	await frames(30)
	for a: Actor in [gasket, grunt, emp]:
		if a == null or a.dead:
			continue
		var d0 := GameWorld.flat_distance(before[a][1], drum.global_position)
		var d1 := GameWorld.flat_distance(a.global_position, drum.global_position)
		check(d1 > d0 + 0.4, "%s is shoved out (%.2f -> %.2f)" % [a.display_name, d0, d1])
	check(drum.last_hits.has(gasket) and drum.last_hits.has(grunt) and not drum.last_hits.has(far), "the blast's own hit list")
	check(drum.get_node_or_null("Rubble") != null, "it leaves a scorched wreck")


# --- Chains and the bill -----------------------------------------------------------------------------------------------

func _check_chain_and_bill() -> void:
	_fresh()
	var hero := _hero(Vector3(-9, 0, 0), "Rebar")
	var a := _boom("oil_drum", Vector3(0, 0, 0))
	var b := _boom("gas_cylinders", Vector3(2.5, 0, 0))
	var c := _boom("propane_tank", Vector3(7.6, 0, 0))
	var lamp := _prop("crystal_lamp", Vector3(1.2, 0, 1.6))
	var times := {}
	for e: ExplosiveProp in [a, b, c]:
		e.blew.connect(func(p: ExplosiveProp) -> void: times[p] = GameWorld.time)
	await frames(2)
	a.ignite(hero)
	check(await _until(func() -> bool: return a.dead, 120), "the first one blows")
	check(b.is_lit(), "it lights the next one in reach")
	near(b.fuse_end - b.fuse_start, ExplosiveProp.chain_delay(2.5), 0.0001, "on a short chain fuse (%.2f s)" % ExplosiveProp.chain_delay(2.5))
	check(b.igniter() == hero, "the chain keeps the first igniter")
	check(not c.is_lit(), "the third, out of reach, is not lit yet")
	check(await _until(func() -> bool: return b.dead, 60), "the second blows")
	near(float(times[b]) - float(times[a]), ExplosiveProp.chain_delay(2.5), 1.5 / 60.0, "a beat after the first: a sequence")
	await frames(90)
	check(not c.dead and not c.is_lit(), "the one out of reach of both stands")
	check(lamp.dead, "the lamp beside them is broken")
	eq(_lines("Oil drum"), 1, "the first is billed once")
	eq(_lines("Gas cylinders"), 1, "the second is billed once")
	eq(_lines("Crystal lamp"), 1, "the lamp is billed once")
	for l in Ledger.lines:
		eq(str(l["who"]), "Rebar", "%s is billed to whoever set it off" % str(l["label"]))
	eq(Ledger.damages(), 800 + 1800 + 600, "the whole chain's bill")
	a.apply_damage(100.0, hero)
	b.die()
	eq(Ledger.lines.size(), 3, "never billed twice")


# --- Damp ----------------------------------------------------------------------------------------------------------------

func _check_damp() -> void:
	_fresh()
	var hero := _hero(Vector3(-9, 0, 0), "Wick")
	var drum := _boom("oil_drum", Vector3(0, 0, 0))
	var bystander := _hero(Vector3(1.4, 0, 0), "Gasket")
	await frames(2)
	Wet.douse(drum, 10.0)
	check(Burning.is_soaked(drum), "a soak takes")
	ExplosiveProp.fire_at(drum.global_position, 2.0, hero)
	check(not drum.is_lit(), "a soaked one does not light from fire")
	drum.apply_damage(30.0, hero)
	check(not drum.is_lit() and not drum.dead, "nor from a hard hit: just a dent")
	eq(Ledger.lines.size(), 0, "a free dent")
	var hp0 := bystander.hp
	drum.apply_damage(30.0, hero)
	check(drum.dead and not drum.blown, "smashed while wet it breaks as a dud")
	await frames(20)
	near(bystander.hp, hp0, 0.001, "no blast")
	eq(_lines("Oil drum"), 1, "but it is still billed")

	# A soak on a burning fuse puts it out, in time.
	_fresh()
	var lighter := _hero(Vector3(-9, 0, 0), "Wick")
	var saved := _boom("gas_cylinders", Vector3(0, 0, 0))
	await frames(2)
	saved.ignite(lighter)
	await frames(10)
	Wet.douse(saved, 10.0)
	await frames(2)
	check(not saved.is_lit(), "a soak puts the fuse out")
	await frames(int(saved.fuse_time * 60.0) + 20)
	check(not saved.dead and not saved.blown, "and it never blows")
	eq(Ledger.lines.size(), 0, "nothing to bill")

	# Too late: in the fuse's last DOUSE_LOCK it goes up anyway.
	var late := _boom("oil_drum", Vector3(0, 0, 5))
	await frames(2)
	late.ignite(lighter)
	await _until(func() -> bool: return late.fuse_left() < ExplosiveProp.DOUSE_LOCK * 0.5, 120)
	Wet.douse(late, 10.0)
	check(await _until(func() -> bool: return late.dead, 30), "a soak in its last %.1f s is too late" % ExplosiveProp.DOUSE_LOCK)
	check(late.blown, "it blew")

	# Dry again, it lights again; and the Damp spell itself soaks it.
	_fresh()
	var caster := _hero(Vector3(-4, 0, 0), "Wick")
	var tank := _boom("propane_tank", Vector3(0, 0, 0))
	await frames(2)
	Wet.douse(tank, 0.4)
	await frames(40)
	check(not Burning.is_soaked(tank), "it dries")
	ExplosiveProp.fire_at(tank.global_position, 2.0, caster)
	check(tank.is_lit(), "dry, it lights again")
	var pack := _boom("battery_pack", Vector3(0, 0, -5))
	SpellBook.cast("damp", caster, 1.0, pack.global_position)
	check(await _until(func() -> bool: return Burning.is_soaked(pack), 120), "the Damp spell soaks it")


# --- Placement --------------------------------------------------------------------------------------------------------

func _check_placement() -> void:
	var total := 0
	var pairs := 0
	var by_kind := {}
	var floors := 0
	var bad := 0
	var hz_usec := 0
	for id in ClientArchetype.IDS:
		for s in [3, 42]:
			var run := ContractRun.make(id, s, 0.5)
			var catalog := PricedProp.catalog(run.site_type)
			for f in range(1, ContractRun.FLOOR_COUNT + 1):
				var map := DungeonGen.generate(run.floor_seed(f))
				var plan := SiteBuilder.plan(map, run, f, catalog)
				floors += 1
				hz_usec += SiteBuilder.last_hazard_usec
				var tag := "%s#%d/%d" % [id, s, f]
				if plan.hazards.size() > HazardPlanner.MAX_HAZARDS:
					bad += 1
					_fail("%s: %d explosives (max %d)" % [tag, plan.hazards.size(), HazardPlanner.MAX_HAZARDS])
				var near_corr := SiteBuilder._corridor_zone(map)
				var keep := ElevatorGeo.keep_cells(plan.elevator)
				var per_room := {}
				for hz in plan.hazards:
					var c: Vector2i = hz["cell"]
					var room := str(hz["room"])
					var kind := str(hz["kind"])
					total += 1
					by_kind[kind] = int(by_kind.get(kind, 0)) + 1
					per_room[room] = (per_room.get(room, []) as Array) + [hz]
					var ok := room != plan.start_room
					ok = ok and RoomThemes.hazard_kinds(plan.theme_of(room)).has(kind)
					ok = ok and Hex.distance(c, plan.start) > SiteBuilder.START_CLEAR and Hex.distance(c, plan.exit) > SiteBuilder.EXIT_CLEAR
					ok = ok and not near_corr.has(c) and not keep.has(c)
					ok = ok and not (plan.van.get("cells", []) as Array).has(c)
					for g in plan.gate_cells():
						ok = ok and Hex.distance(g, c) >= HazardPlanner.HAZARD_GATE_CLEAR
					for e in plan.employees:
						ok = ok and Hex.distance(e["cell"], c) >= HazardPlanner.HAZARD_EMPLOYEE_CLEAR
					if not ok:
						bad += 1
						_fail("%s: %s at %s in %s (%s) breaks a placement rule" % [tag, kind, c, room, plan.theme_of(room)])
				for room: String in per_room:
					var list: Array = per_room[room]
					check(list.size() <= 2, "%s: at most a pair in %s" % [tag, room])
					if list.size() == 2:
						pairs += 1
						var d := (list[0]["pos"] as Vector2).distance_to(list[1]["pos"] as Vector2)
						check(d >= HazardPlanner.HAZARD_PAIR_MIN - 0.001 and d <= HazardPlanner.HAZARD_PAIR_MAX + 0.001, "%s: a pair %.2f apart (inside each other's blast)" % [tag, d])
				# Deterministic per seed, and the floor's other things do not move (the decor still places the same way).
				if f == 1 and s == 3:
					var again := SiteBuilder.plan(DungeonGen.generate(run.floor_seed(f)), run, f, catalog)
					eq(str(again.hazards), str(plan.hazards), "%s: the same explosives from the same seed" % tag)
					eq(str(again.props), str(plan.props), "%s: and the same priced props" % tag)
	var hz_ms := float(hz_usec) / 1000.0 / float(floors)
	print("explosives: %d over %d floors (%s), %d chained pairs; placing them %.2f ms a floor" % [total, floors, str(by_kind), pairs, hz_ms])
	check(hz_ms < 15.0, "placing the explosives is cheap (%.2f ms a floor)" % hz_ms)
	check(total >= floors / 2, "floors do get explosives (%d on %d floors)" % [total, floors])
	check(by_kind.size() == 4, "every kind turns up somewhere (%s)" % str(by_kind))
	check(pairs > 0, "some come in chained pairs")
	eq(bad, 0, "every placement rule holds")

	# Spawned with the floor, and in the floor checksum.
	var run := ContractRun.make("supervillain", 17, 0.5)
	var plan: SitePlan = null
	var map: HexMap = null
	for f in range(1, ContractRun.FLOOR_COUNT + 1):
		map = DungeonGen.generate(run.floor_seed(f))
		plan = SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
		if not plan.hazards.is_empty():
			break
	if not check(plan != null and not plan.hazards.is_empty(), "a lair floor with explosives"):
		return
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(map, root, 1)
	var site := SiteBuilder.spawn(map, run, plan)
	eq(site.hazards.size(), plan.hazards.size(), "every planned explosive is spawned")
	for i in site.hazards.size():
		var e := site.hazards[i] as ExplosiveProp
		check(e != null and e.kind == str(plan.hazards[i]["kind"]), "an ExplosiveProp of the planned kind")
		if e != null:
			var want: Vector2 = plan.hazards[i]["pos"]
			near(Vector2(e.global_position.x, e.global_position.z).distance_to(want), 0.0, 0.01, "standing where the plan says")
			check(map.blocks_point(e.global_position, 0.05) == false, "not inside a wall")
	var sums := NetFloor.checksum(map, plan, run, root)
	check((sums["plan_keys"] as Dictionary).has("hazards"), "the plan's explosives are in the floor checksum")
	check(NetFloor.spawn_text_of(root).contains("explosive_prop.gd"), "and so are the spawned ones (the spawn table)")
	var first := site.hazards[0]
	first.free()
	await frames(1)
	check(str(NetFloor.checksum(map, plan, run, root)["spawn"]) != str(sums["spawn"]), "a missing explosive changes the checksum")
	GameWorld.end()
