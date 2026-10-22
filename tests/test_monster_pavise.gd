extends MonsterTestBase
## The Pavise Crossbowman (docs/design/combat-proposals.md §2, "As built"):
## - the shield blocks from the front, carried and planted: melee, an arrow (it sticks), a shot, a blast in front of the
##   planks, a shove from the front (a bonk); corn from above is never blocked;
## - a hit from the flank or from behind lands;
## - a shove that gets past the planted shield leaves it standing (EXPOSED) or, from behind, trips it (FLAT);
## - the aim telegraph: it plants, the dashed line tracks for 0.8 s, the solid line locks for 0.4 s, then the bolt;
## - the bolt hits (18) and shoves (0.8); a shove during the aim calls it off (no bolt);
## - turning: planted 60 degrees a second; rooted (vines), not at all.

const F := Vector3(1.0, 0.0, 0.0)          ## the pavise faces +X in every case
const SIDE := Vector3(0.0, 0.0, 1.0)


func setup() -> void:
	await _blocks()
	await _shoves()
	await _aim_and_bolt()
	await _shove_cancels()
	await _turning()
	finish()


func _pavise(cell: Vector2i = Vector2i.ZERO) -> Pavise:
	var pv := MonsterFactory.spawn("pavise", cell) as Pavise
	pv.set_spawn_facing(F)
	return pv


func _hero_at(p: Vector3) -> Actor:
	var h := add_hero(Hex.from_world(p))
	h.global_position = Vector3(p.x, 0.0, p.z)
	h.max_hp = 1000.0
	h.hp = 1000.0
	return h


# --- 1. The front blocks, carried and planted; the flank and the back do not -------------------------------------

func _blocks() -> void:
	new_world(flat_map(12))
	var pv := _pavise()
	pv.set_physics_process(false)   # (a statue: its facing and shield are what the test sets)
	await frames(2)
	pv.facing = F
	var front := _hero_at(pv.global_position + F * 1.6)
	var flank := _hero_at(pv.global_position + SIDE * 1.6)
	var rear := _hero_at(pv.global_position - F * 1.6)
	for st in [Pavise.Shield.CARRIED, Pavise.Shield.PLANTED]:
		pv._set_shield(st)
		var label := "carried" if st == Pavise.Shield.CARRIED else "planted"
		var hp0 := pv.hp
		var b0 := pv.blocks_decided
		Combat.melee_arc(front, -F, 2.0, 120.0, 10.0, 0.7)
		near(pv.hp, hp0, 0.001, "%s: a swing from the front does nothing" % label)
		eq(pv.blocks_decided, b0 + 1, "%s: ... and is one block (spark, grey 0)" % label)
		near(GameWorld.flat_distance(pv.global_position, Vector3.ZERO), 0.0, 0.01, "%s: ... and shoves nothing (a clank)" % label)
		var stuck0 := pv.stuck
		var archer := _hero_at(pv.global_position + F * 7.0)
		ArrowShot.shoot(archer, -F, 12.0, 30.0, 14.0, 1, false, Color.WHITE)
		await frames(30)
		near(pv.hp, hp0, 0.001, "%s: an arrow from the front does nothing" % label)
		eq(pv.stuck, stuck0 + 1, "%s: ... it sticks in the planks" % label)
		var pm := pv.model as PaviseModel
		check(pm != null and (pm.parts["arrows"] as MeshInstance3D).visible, "%s: ... and shows there" % label)
		Projectile.fire(archer, Combat.chest(archer) - F * 0.5, -F, 10.0, 20.0, 14.0)
		await frames(30)
		near(pv.hp, hp0, 0.001, "%s: a shot from the front does nothing" % label)
		Combat.explode(pv.global_position + F * 1.2, 1.5, 30.0, GameWorld.TEAM_MONSTERS, archer, 1.0)
		near(pv.hp, hp0, 0.001, "%s: a blast in front of the planks does nothing" % label)
		archer.die()
	# The flank and the back: the body.
	pv._set_shield(Pavise.Shield.PLANTED)
	var hp1 := pv.hp
	Combat.melee_arc(flank, -SIDE, 2.0, 120.0, 10.0, 0.0)
	near(pv.hp, hp1 - 10.0, 0.001, "a swing from the flank lands (10)")
	var back_archer := _hero_at(pv.global_position - F * 7.0)
	ArrowShot.shoot(back_archer, F, 12.0, 30.0, 14.0, 1, false, Color.WHITE)
	await frames(30)
	near(pv.hp, hp1 - 22.0, 0.001, "an arrow from behind lands (12)")
	Combat.explode(pv.global_position + SIDE * 1.2, 1.5, 5.0, GameWorld.TEAM_MONSTERS, rear, 1.0)
	near(pv.hp, hp1 - 27.0, 0.001, "a blast beside it lands")
	Combat.explode(pv.global_position + F * 1.0, 1.5, 6.0, GameWorld.TEAM_MONSTERS, rear, 1.0, 0.0, null, Combat.HIT_ABOVE)
	near(pv.hp, hp1 - 33.0, 0.001, "corn (from above) lands in front of the planks too")
	check(Combat.shielded(pv, pv.global_position + F * 3.0, Combat.HIT_MELEE, null, false), "70 degrees off its facing is still the front ...")
	check(Combat.shielded(pv, pv.global_position + F.rotated(Vector3.UP, deg_to_rad(68.0)) * 3.0, Combat.HIT_MELEE, null, false), "... at 68 degrees")
	check(not Combat.shielded(pv, pv.global_position + F.rotated(Vector3.UP, deg_to_rad(73.0)) * 3.0, Combat.HIT_MELEE, null, false), "... but not at 73")
	pv._set_shield(Pavise.Shield.LEFT, pv.global_position + F * 0.6, 0.0)
	check(not Combat.shielded(pv, pv.global_position + F * 3.0, Combat.HIT_MELEE, null, false), "a pavise standing on its own blocks nothing")


# --- 2. Shoves: a bonk from the front; past the planted shield it is left standing, from behind it trips ----------------

func _shoves() -> void:
	new_world(flat_map(12))
	var pv := _pavise()
	await frames(2)
	pv.set_physics_process(false)   # (its AI off: it keeps still between the shoves; the slides run on their own)
	pv.facing = F
	pv._set_shield(Pavise.Shield.PLANTED)
	var front := _hero_at(pv.global_position + F * 1.2)
	Combat.shove_radius(pv.global_position + F * 1.2, 2.5, 2.0, front)
	await frames(30)
	near(GameWorld.flat_distance(pv.global_position, Vector3.ZERO), 0.0, 0.01, "a shove from the front is a bonk: nothing moves")
	eq(pv.shield_state, Pavise.Shield.PLANTED, "... and the shield stays planted")
	var flank := _hero_at(pv.global_position + SIDE * 1.2)
	Combat.shove_radius(flank.global_position, 2.5, 2.0, flank, GameWorld.TEAM_MONSTERS)
	await frames(2)
	eq(pv.shield_state, Pavise.Shield.LEFT, "a shove from the flank separates it from its pavise (EXPOSED)")
	near(pv.shield_pos.x, Pavise.SHIELD_AHEAD, 0.05, "... which stays where it was planted")
	await frames(30)
	check(GameWorld.flat_distance(pv.global_position, Vector3.ZERO) > 1.0, "... while it slides away")
	check(not Combat.shielded(pv, pv.global_position + F * 2.0, Combat.HIT_MELEE, null, false), "... and then blocks nothing")
	# It walks back and lifts it (a fight: it has a target).
	pv.set_physics_process(true)
	var hero := _hero_at(Vector3(-9.0, 0.0, 0.0))
	pv.aggro(hero)
	check(await wait_until(func() -> bool: return pv.shield_up(), 600), "it walks back and lifts its pavise")
	# A shove from behind into its own planted shield trips it.
	new_world(flat_map(12))
	pv = _pavise()
	await frames(2)
	pv.set_physics_process(false)
	pv.facing = F
	pv._set_shield(Pavise.Shield.PLANTED)
	var rear := _hero_at(pv.global_position - F * 1.2)
	Combat.shove_radius(rear.global_position, 2.5, 2.0, rear, GameWorld.TEAM_MONSTERS)
	await frames(2)
	eq(pv.shield_state, Pavise.Shield.FLAT, "shoved from behind into its own shield it trips (FLAT)")
	check(pv.is_staggered(), "... and goes down for a moment")


# --- 3. The aim: plant, track 0.8 s (dashed), lock 0.4 s (solid), the bolt (18 and a push) ------------------------

func _aim_and_bolt() -> void:
	new_world(flat_map(14))
	var pv := _pavise()
	var hero := _hero_at(Vector3(10.0, 0.0, 0.0))
	await frames(2)
	var times := {}
	pv.charge_begun.connect(func(_l: float) -> void: times["charge"] = GameWorld.time)
	pv.beam_locked.connect(func(_o: Vector3, _d: Vector3, at: float) -> void:
		times["lock"] = GameWorld.time
		times["fire_at"] = at)
	pv.shield_changed.connect(func(st: int, _p: Vector3, _y: float) -> void:
		if st == Pavise.Shield.PLANTED and not times.has("planted"):
			times["planted"] = GameWorld.time)
	pv.aggro(hero)
	var t0 := GameWorld.time
	check(await wait_until(func() -> bool: return times.has("charge"), 240), "it plants and aims at the hero 10 away")
	check(times.has("planted") and float(times["planted"]) - t0 >= Pavise.PLANT_TIME - 0.05, "it stamped the pavise in first (%.2f s)" % (float(times.get("planted", 0.0)) - t0))
	check(pv.shield_state == Pavise.Shield.PLANTED, "... planted")
	await frames(10)
	check(pv._fx.showing() == Pavise.SHOW_AIM_LINE and pv.fire_at < 0.0, "tracking: no floor line (removed, 2026-10-22), not locked yet")
	check(await wait_until(func() -> bool: return times.has("lock"), 120), "the line locks")
	near(float(times["lock"]) - float(times["charge"]), Pavise.TRACK_TIME, 1.5 / 60.0, "it tracks for 0.8 s")
	near(float(times["fire_at"]) - float(times["charge"]), Pavise.AIM_TIME, 0.001, "... and looses 1.2 s after it began")
	check(pv.model != null and (pv.model as PaviseModel)._locked, "locked: the bolt head flares hot")
	await frames(2)
	check(pv._fx.showing() == Pavise.SHOW_AIM_LINE and pv.fire_at >= 0.0, "locked: no line either")
	var pos0 := hero.global_position
	check(await wait_until(func() -> bool: return pv.bolts_fired >= 1, 60), "the bolt looses")
	check(await wait_until(func() -> bool: return hero.hp < 1000.0, 60), "the bolt reaches the hero")
	near(hero.hp, 1000.0 - Pavise.BOLT_DAMAGE, 0.001, "the bolt hits for 18")
	await frames(30)
	near(hero.global_position.x - pos0.x, Pavise.BOLT_SHOVE, 0.15, "... and pushes the hero back 0.8 (%.2f)" % (hero.global_position.x - pos0.x))
	check(not pv._fx.showing(), "the line is gone after the shot")
	# It reloads (2 s) before the next aim.
	var c1 := float(times["charge"])
	times.erase("charge")
	check(await wait_until(func() -> bool: return times.has("charge"), 300), "it aims again after reloading")
	check(float(times["charge"]) - c1 >= Pavise.AIM_TIME + Pavise.RELOAD_TIME - 0.05, "... no sooner than aim + reload (%.2f s)" % (float(times["charge"]) - c1))


# --- 4. A shove calls the aim off -----------------------------------------------------------------------------------

func _shove_cancels() -> void:
	for when in ["tracking", "locked"]:
		new_world(flat_map(14))
		var pv := _pavise()
		var hero := _hero_at(Vector3(10.0, 0.0, 0.0))
		await frames(2)
		var dropped := [0]
		pv.charge_dropped.connect(func() -> void: dropped[0] += 1)
		pv.aggro(hero)
		check(await wait_until(func() -> bool: return pv.charge_victim != null, 240), "%s: it aims" % when)
		if when == "locked":
			check(await wait_until(func() -> bool: return pv.fire_at >= 0.0, 120), "locked: the line locks")
		var side := _hero_at(pv.global_position + SIDE * 1.2)
		Combat.shove_radius(side.global_position, 2.0, 1.5, side, GameWorld.TEAM_MONSTERS)
		await frames(2)
		eq(dropped[0], 1, "%s: a shove calls the aim off" % when)
		check(pv.charge_victim == null and pv.fire_at < 0.0, "%s: ... no line, no pending bolt" % when)
		await frames(90)
		eq(pv.bolts_fired, 0, "%s: ... and no bolt flies" % when)
		near(hero.hp, 1000.0, 0.001, "%s: ... the hero is untouched" % when)


# --- 5. Turning: 60 degrees a second planted; rooted, not at all ---------------------------------------------------------

func _turning() -> void:
	new_world(flat_map(12))
	var pv := _pavise()
	await frames(2)
	pv.set_physics_process(false)   # (no AI: the test asks it to turn)
	pv.facing = F
	pv._set_shield(Pavise.Shield.PLANTED)
	var want := F.rotated(Vector3.UP, deg_to_rad(80.0))
	for _i in 30:   # half a second of asking it to face 80 degrees round
		pv.face_point(pv.global_position + want * 3.0)
		await get_tree().physics_frame
	near(rad_to_deg(F.angle_to(pv.facing)), 30.0, 1.5, "planted, it turns 60 degrees a second (%.1f in 0.5 s)" % rad_to_deg(F.angle_to(pv.facing)))
	pv._set_shield(Pavise.Shield.CARRIED)
	var f0 := pv.facing
	for _i in 6:   # a tenth of a second
		pv.face_point(pv.global_position + want.rotated(Vector3.UP, deg_to_rad(60.0)) * 3.0)
		await get_tree().physics_frame
	near(rad_to_deg(f0.angle_to(pv.facing)), 15.0, 1.5, "carried, 150 degrees a second")
	pv.set_modifier("vines", 1.0, 5.0, Actor.STAT_ROOT)
	var f1 := pv.facing
	for _i in 30:
		pv.face_point(pv.global_position - f1 * 3.0)
		await get_tree().physics_frame
	near(rad_to_deg(f1.angle_to(pv.facing)), 0.0, 0.01, "rooted by vines, it cannot turn (the vines bind the shield's foot)")
