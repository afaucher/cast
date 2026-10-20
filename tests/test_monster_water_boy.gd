extends MonsterTestBase
## The Water Boy, the enemy healer (docs/design/enemy-healer-options.md §7; combat-proposals.md §3, "As built"):
## - the pulse heals every monster inside PULSE_RADIUS by PULSE_HEAL (imps too), never itself, a monster outside or a hero;
## - in a fight it raises the whistle (POUR_TELL) and pours when one of its pack is hurt, then waits POUR_COOLDOWN;
## - a shove or a daze during the tell cancels the pour;
## - it keeps KEEP_MIN-KEEP_MAX from the nearest hero, on the far side of its pack;
## - it is a priority target for the AI allies.


func setup() -> void:
	await _heals()
	await _pours_in_a_fight()
	await _cancels()
	await _keeps_back()
	finish()


func _hero_at(p: Vector3) -> Actor:
	var h := add_hero(Hex.from_world(p))
	h.global_position = Vector3(p.x, 0.0, p.z)
	h.max_hp = 1000.0
	h.hp = 1000.0
	return h


# --- 1. The pulse: monsters inside, not itself, not outside, never a hero -------------------------------------------

func _heals() -> void:
	new_world(flat_map(12))
	var wb := MonsterFactory.spawn("water_boy", Vector2i.ZERO) as WaterBoy
	var inside := MonsterFactory.spawn("grunt", Vector2i(2, 0))         # 3.5 away
	var imp := MonsterFactory.spawn("swarmer", Vector2i(0, 2))
	var far := MonsterFactory.spawn("grunt", Vector2i(5, 0))            # 8.7 away
	var hero := _hero_at(Vector3(0.0, 0.0, -3.0))
	await frames(2)
	for m: Monster in [wb, inside, imp, far]:
		m.set_physics_process(false)
	check(wb.is_priority_target() and not inside.is_priority_target(), "the water boy is a priority target (a grunt is not)")
	inside.apply_damage(30.0, hero)
	imp.apply_damage(8.0, hero)
	far.apply_damage(30.0, hero)
	wb.apply_damage(10.0, hero)
	hero.apply_damage(50.0)
	var hp := {"inside": inside.hp, "imp": imp.hp, "far": far.hp, "wb": wb.hp, "hero": hero.hp}
	wb.pulse()
	near(inside.hp, float(hp["inside"]) + WaterBoy.PULSE_HEAL, 0.001, "a grunt inside the rings gets +15")
	near(imp.hp, imp.max_hp, 0.001, "an imp inside gets healed too (up to its max)")
	near(far.hp, float(hp["far"]), 0.001, "a grunt outside the rings gets nothing")
	near(wb.hp, float(hp["wb"]), 0.001, "it never heals itself")
	near(hero.hp, float(hp["hero"]), 0.001, "a hero inside the rings gets nothing")
	eq(wb.pulses, 1, "the rings showed once")
	eq(wb.last_heals.size(), 2, "it healed the two monsters inside")


# --- 2. In a fight: the tell, the pour, the cooldown ---------------------------------------------------------------

func _pours_in_a_fight() -> void:
	new_world(flat_map(12))
	var wb := MonsterFactory.spawn("water_boy", Vector2i(-2, 0)) as WaterBoy
	var g := MonsterFactory.spawn("grunt", Vector2i(-1, 0))
	var hero := _hero_at(Vector3(6.0, 0.0, 0.0))
	await frames(2)
	g.set_physics_process(false)   # (the patient stands still)
	var tells := [0]
	wb.windup_begun.connect(func(_l: float) -> void: tells[0] += 1)
	wb.aggro(hero)
	await frames(30)
	eq(wb.pulses, 0, "with nobody hurt it does not pour")
	g.apply_damage(25.0, hero)
	var t_hurt := GameWorld.time
	check(await wait_until(func() -> bool: return wb.pulses >= 1, 120), "a hurt pack-mate: it pours")
	check(GameWorld.time - t_hurt >= WaterBoy.POUR_TELL - 0.05, "... after the 0.8 s whistle (%.2f s)" % (GameWorld.time - t_hurt))
	eq(tells[0], 1, "... one tell (a wind-up: the event the other screens see)")
	near(g.hp, g.max_hp - 25.0 + WaterBoy.PULSE_HEAL, 0.001, "the grunt got +15")
	var t_pour := GameWorld.time
	await wait_until(func() -> bool: return wb.pulses >= 2, int(60 * (WaterBoy.POUR_COOLDOWN + 1.0)))
	check(wb.pulses >= 2 and GameWorld.time - t_pour >= WaterBoy.POUR_COOLDOWN - 0.05, "the next pour waits the 5 s cooldown (%.2f s)" % (GameWorld.time - t_pour))


# --- 3. A shove or a daze cancels the pour ---------------------------------------------------------------------------

func _cancels() -> void:
	for how in ["shove", "daze"]:
		new_world(flat_map(12))
		var wb := MonsterFactory.spawn("water_boy", Vector2i(-2, 0)) as WaterBoy
		var g := MonsterFactory.spawn("grunt", Vector2i(-1, 0))
		var hero := _hero_at(Vector3(6.0, 0.0, 0.0))
		await frames(2)
		g.set_physics_process(false)
		var dropped := [0]
		wb.windup_dropped.connect(func() -> void: dropped[0] += 1)
		g.apply_damage(25.0, hero)
		var hp0 := g.hp
		wb.aggro(hero)
		check(await wait_until(func() -> bool: return wb.state == Monster.State.ATTACK, 60), "%s: the whistle goes up" % how)
		await frames(20)
		if how == "shove":
			wb.shove(Vector3.BACK, 1.5, hero)
		else:
			wb.daze(0.8, hero)
		await frames(2)
		eq(dropped[0], 1, "%s: the pour is called off" % how)
		await frames(60)
		eq(wb.pulses, 0, "%s: ... no rings" % how)
		near(g.hp, hp0, 0.001, "%s: ... no heal" % how)


# --- 4. It keeps back: 6-9 from the nearest hero, behind its pack --------------------------------------------------

func _keeps_back() -> void:
	new_world(flat_map(14))
	var hero := _hero_at(Vector3(0.0, 0.0, 0.0))
	var wb := MonsterFactory.spawn("water_boy", Vector2i(2, 0)) as WaterBoy    # 3.5 from the hero: too close
	var pack: Array[Monster] = []
	for c: Vector2i in [Vector2i(3, -1), Vector2i(3, 1), Vector2i(4, 0)]:
		var g := MonsterFactory.spawn("grunt", c)
		pack.append(g)
	await frames(2)
	for g in pack:
		g.set_physics_process(false)   # (the pack holds its ground: the test watches where the water boy goes)
	wb.aggro(hero)
	await frames(60 * 5)
	var d := fdist(wb, hero)
	check(d >= WaterBoy.KEEP_MIN - 0.7 and d <= WaterBoy.KEEP_MAX + 0.7, "it keeps 6-9 from the hero (%.2f)" % d)
	var centre := Vector3.ZERO
	for g in pack:
		centre += g.global_position / pack.size()
	var to_wb := wb.global_position - hero.global_position
	var to_pack := centre - hero.global_position
	to_wb.y = 0.0
	to_pack.y = 0.0
	check(to_wb.length() > to_pack.length() and to_wb.normalized().dot(to_pack.normalized()) > 0.7, "... behind its pack, seen from the hero")
	# The hero walks up to it: it backs off.
	hero.global_position = wb.global_position - to_wb.normalized() * 3.0
	await frames(60 * 4)
	d = fdist(wb, hero)
	check(d >= WaterBoy.KEEP_MIN - 0.7, "a hero steps in: it backs off to 6 again (%.2f)" % d)
