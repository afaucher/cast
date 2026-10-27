extends NetGameTest
## Getting back up on a crew floor (docs/design/spells.md, "Revive" and "Coffee"), two processes, `off` and `coast`. Standing
## up is a verb (Actor.revive) the TARGET'S OWNER applies, like a heal: the cast lands on every machine, each stands up only
## the heroes it owns, and the other screens see it from the owner's hero snapshot (dead going false, HP, the zombie flag:
## NetCodec). B is the client's hero (seat 2); the AI seat 3 is the host's.
##
## - COFFEE ON B: B goes down on its own machine; the host's coffee at B's body stands B up AS A ZOMBIE on B's machine (10 HP,
##   no haste), the host shows B standing and gray, and B's controls and camera come back; B leaks on its own machine and the
##   host shows the HP falling;
## - THE CURE: the host's heals take B past three quarters: the curse lifts on B's machine, the host shows the colour back;
## - REVIVE ON THE HOST'S AI: the host downs its AI seat and coffees it (a zombie the host owns, gray on B's screen); B's
##   Revive at it lifts the curse ON THE HOST (the owner) to half health, and B's screen shows it;
## - REVIVE FROM DOWNED: the AI down again; B's Revive stands it up at half health, no curse, on every screen;
## - the OWNER-write guard never fires.

const PEERS := 2
const SEED := 21


func run_host() -> void:
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	_freeze_world()
	my_hero().spell_slots = ["coffee", "heal", "revive"] as Array[String]
	check(await wait_reports("ready", 1, 30.0), "the client is streaming")
	var b := client_peers()[0]
	var base := my_hero().global_position
	var p := _open_spot(base, 4.0, base)
	command(b, "stand", {"at": p})
	check(await wait_reports("stood", 1, 20.0), "B stands where the test wants it")
	await sleep(0.5)
	var b_hero := hero_at(2)

	# 1. B goes down on its own machine; the host's coffee at the body makes B a zombie there.
	command(b, "down")
	check(await until(func() -> bool: return b_hero.dead, 3.0), "the host shows B down")
	_cast("coffee", b_hero.global_position)
	check(await until(func() -> bool: return not b_hero.dead, 3.0), "the host shows B standing again (B's machine stood it up)")
	check(await until(func() -> bool: return b_hero.zombie, 1.0), "... gray: a zombie")
	check(not Coffee.is_hasted(b_hero), "... and not hasted")
	command(b, "look")
	check(await wait_reports("look", 1, 10.0), "B reports")
	var r: Dictionary = reported(b, "look")
	check(not bool(r["dead"]) and bool(r["zombie"]), "on B's own machine B is up, a zombie")
	check(float(r["hp"]) <= CoffeeSpell.ZOMBIE_HP + 0.01 and float(r["hp"]) > CoffeeSpell.ZOMBIE_HP - 3.0, "at about %.0f HP (%.1f)" % [CoffeeSpell.ZOMBIE_HP, float(r["hp"])])
	check(not bool(r["hasted"]), "no haste for the one coffee stood up")
	check(bool(r["controls"]) and bool(r["camera"]), "B's controls and camera are back")
	eq(int(r["ups"]), 1, "B stood up once")
	var hp_seen := b_hero.hp
	await sleep(1.0)
	check(b_hero.hp < hp_seen - 0.8, "the host shows B leaking (%.1f -> %.1f): B's machine ticks it" % [hp_seen, b_hero.hp])

	# 2. Heals take B past three quarters: the curse lifts on B's machine, the host shows it.
	_cast("heal", b_hero.global_position)
	await sleep(NetCasts.LEAD + 0.3)
	check(b_hero.zombie and b_hero.hp > CoffeeSpell.ZOMBIE_HP, "one heal works (%.1f HP), but under three quarters B is still a zombie" % b_hero.hp)
	var heals := 1
	while b_hero.zombie and heals < 4:
		_cast("heal", b_hero.global_position)
		heals += 1
		await until(func() -> bool: return not b_hero.zombie, NetCasts.LEAD + 0.6)
	check(not b_hero.zombie, "healed past three quarters (%d heals): the host shows the curse lifted (%.1f HP)" % [heals, b_hero.hp])
	reports[b].erase("look")
	command(b, "look")
	check(await wait_reports("look", 1, 10.0), "B reports again")
	r = reported(b, "look")
	check(not bool(r["zombie"]) and float(r["hp"]) >= b_hero.max_hp * CoffeeSpell.ZOMBIE_CURE - 0.5, "on B's machine the curse is gone (%.1f HP)" % float(r["hp"]))

	# 3. The host's AI seat: down, then a zombie (the host owns it); B's Revive lifts the curse on the host.
	var ai := hero_at(3)
	if not check(ai != null and Net.owns(ai), "the host owns the AI seat"):
		return
	ai.global_position = _open_spot(p, 3.0, base)
	ai.snap_to_ground()
	await sleep(0.4)
	ai.die()
	_cast("coffee", ai.global_position)
	check(await until(func() -> bool: return not ai.dead and ai.zombie, 3.0), "the host's coffee: its AI is a zombie")
	command(b, "look_ai")
	check(await wait_reports("look_ai", 1, 10.0), "B reports the AI")
	r = reported(b, "look_ai")
	check(not bool(r["dead"]) and bool(r["zombie"]), "B's screen shows the AI up and gray")
	command(b, "cast", {"spell": "revive", "aim": ai.global_position})
	check(await until(func() -> bool: return not ai.zombie, 3.0), "B's Revive lifted the AI's curse on the host (its owner)")
	near(ai.hp, ai.max_hp * ReviveSpell.REVIVE_HP, 2.0, "... to half health")

	# 4. The AI down again; B's Revive stands it up at half health, no curse.
	ai.die()
	await sleep(0.4)
	command(b, "cast", {"spell": "revive", "aim": ai.global_position})
	check(await until(func() -> bool: return not ai.dead, 3.0), "B's Revive stood the AI up on the host")
	near(ai.hp, ai.max_hp * ReviveSpell.REVIVE_HP, 1.0, "at half health")
	check(not ai.zombie, "no curse")
	await sleep(0.4)
	reports[b].erase("look_ai")
	command(b, "look_ai")
	check(await wait_reports("look_ai", 1, 10.0), "B reports the AI again")
	r = reported(b, "look_ai")
	check(not bool(r["dead"]) and not bool(r["zombie"]), "B's screen shows it up, in colour")
	near(float(r["hp"]), ai.hp, 1.0, "... at the HP the host has")

	command(b, "end")
	check(await wait_done(1, 30.0), "the client is done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	eq(int(reported(b, "end")), 0, "... nor on B")


func run_client() -> void:
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	my_hero().spell_slots = ["revive", "heal", "coffee"] as Array[String]
	var ups := [0]
	my_hero().revived.connect(func(_cursed: bool) -> void: ups[0] += 1)
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"stand":
				my_hero().global_position = cmd["at"]
				my_hero().snap_to_ground()
				await sleep(0.3)
				report("stood", true)
			"down":
				my_hero().die()   # (B's own machine downs its own hero)
			"look":
				await sleep(0.2)
				var me := my_hero()
				var c := game.get("controller") as PlayerController
				var rig: Variant = game.get("rig")
				report("look", {"dead": me.dead, "zombie": me.zombie, "hp": me.hp, "hasted": Coffee.is_hasted(me), "ups": ups[0],
					"controls": c.enabled, "camera": rig != null and rig.get("target") == me})
			"look_ai":
				await sleep(0.2)
				var ai := hero_at(3)
				report("look_ai", {"dead": ai.dead, "zombie": ai.zombie, "hp": ai.hp})
			"cast":
				var c := game.get("controller") as PlayerController
				my_hero()._ready_at.clear()
				c.aim_override = cmd["aim"]
				check(c.cast_spell(str(cmd["spell"]), 1.0), "B cast %s" % str(cmd["spell"]))
				c.aim_override = Vector3.INF
			"end":
				report("end", Net.guard_hits.size())
				running = false
			_:
				running = false


# --- Helpers ---------------------------------------------------------------------------------------------------

## Host: cast from its own hero at `aim` (no cooldowns: the test casts back to back).
func _cast(spell: String, aim: Vector3) -> void:
	var c := game.get("controller") as PlayerController
	my_hero()._ready_at.clear()
	c.aim_override = aim
	check(c.cast_spell(spell, 1.0), "the host cast %s" % spell)
	c.aim_override = Vector3.INF


## Monsters and hellgates stand still, and the host's AI seats stop walking (their brains off; the heroes still tick, so a
## zombie leaks).
func _freeze_world() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster or n is Hellgate:
			n.set_physics_process(false)
	for seat in [3, 4]:
		var h := hero_at(seat)
		if h == null:
			continue
		for ch in h.get_children():
			if ch is AllyBrain:
				ch.set_physics_process(false)


## Open floor `dist` from `p` (of sixteen directions, nothing standing within 1.6), as far as it can be from `away`.
func _open_spot(p: Vector3, dist: float, away: Vector3) -> Vector3:
	var map := game.get("map") as HexMap
	var best := p
	var best_d := -1.0
	for k in 16:
		var a := TAU * float(k) / 16.0
		var q := p + Vector3(cos(a), 0.0, sin(a)) * dist
		if not map.is_walkable_cell(Hex.from_world(q)) or map.blocks_point(q, 0.6) or absf(map.ground_height(q) - p.y) > 0.6:
			continue
		var clear := true
		for x in GameWorld.actors_in_radius(q, 1.6 if dist > 2.5 else 0.5):
			if not (x is Hero) and not (x is PricedProp):
				clear = false
		if clear and GameWorld.flat_distance(q, away) > best_d:
			best_d = GameWorld.flat_distance(q, away)
			best = Vector3(q.x, map.ground_height(q), q.z)
	return best
