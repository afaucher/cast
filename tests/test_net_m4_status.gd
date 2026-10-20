extends NetGameTest
## M4 statuses and shoves across machines (networking-build-plan.md M4b, "vines, damp, coffee"), three processes, `off` and
## `coast`. The target's OWNER applies a status and runs it; the other screens show what the owner announced (NetStatus).
## B is client c2 (seat 3); the host and A (c1, seat 2) cast at it.
##
## - VINES: the host's vines root B on B's machine; the host and A show B rooted (the leg wraps); the host's tentacles
##   then cannot move B (Actor.shove refuses while rooted, on B's machine);
## - TENTACLES: once the root is gone, the host's tentacles shove B ONCE, on B's machine, out of the burst;
## - BURNING: B catches fire (B's own roll: an owner's ignite); the host and A show the flames, and only B's machine
##   ticks the damage (B's HP, as every screen shows it, drops by whole ticks);
## - DAMP: A's damp at B puts the fire out on B's machine and soaks B; every screen shows the fire gone and B damp;
## - COFFEE: A's coffee at B (the aim snaps onto B) hastes B on B's machine; the host and A show the haste (and steam);
## - ARMOR: the host's armor zone at B gives B armor on B's machine; the others show B's shield;
## - PROPS: B, thrown into one of the host's priced props on its own screen, stops against it there, and the prop takes
##   the impact ONCE on the host (the slider's machine saw the contact; the prop's copy has no physics).

const PEERS := 3
const SEED := 13

var shoves := 0


func run_host() -> void:
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	_freeze_world()
	my_hero().spell_slots = ["vines", "tentacles", "armor", "heal"] as Array[String]
	check(await wait_reports("ready", 2, 30.0), "both clients are streaming")
	var a := _peer_named("c1")
	var b := _peer_named("c2")
	var base := my_hero().global_position
	var p := _open_spot(base, 7.0, base)
	var a_spot := _open_spot(p, 5.0, base)
	command(b, "stand", {"at": p})
	command(a, "stand", {"at": a_spot})
	check(await wait_reports("stood", 2, 20.0), "A and B stand where the test wants them")
	await sleep(0.5)
	var b_hero := hero_at(3)

	# 1. Vines root B; tentacles can't move it.
	_cast("vines", b_hero.global_position)
	check(await until(func() -> bool: return b_hero.has_modifier("vines"), 3.0), "the host shows B rooted (B's machine announced it)")
	check(b_hero.get_node_or_null("VineWrap") != null, "... with the leg wraps on B's puppet")
	command(a, "look", {"what": "vines"})
	command(b, "look", {"what": "vines"})
	check(await wait_reports("vines", 2, 10.0), "A and B report the root")
	check(bool(reported(b, "vines")["own"]), "B is rooted on its own machine")
	check(bool(reported(a, "vines")["seen"]), "A shows B rooted")
	command(b, "watch_shove")
	await sleep(0.2)
	_cast("tentacles", b_hero.global_position + Vector3(0.6, 0.0, 0.0))
	await sleep(NetCasts.LEAD + Tentacles.TELEGRAPH + 0.6)
	command(b, "shoves")
	check(await wait_reports("shoves", 1, 10.0), "B reports the shoves")
	var r: Dictionary = reported(b, "shoves")
	eq(int(r["n"]), 0, "rooted, B was not shoved by the tentacles (B's machine dropped it)")
	check(float(r["moved"]) < 0.3, "... and did not move (%.2f)" % float(r["moved"]))

	# 2. The root wears off; tentacles shove B once.
	await until(func() -> bool: return not b_hero.has_modifier("vines"), 4.0)
	await sleep(0.4)
	reports[b].erase("shoves")
	command(b, "watch_shove")
	await sleep(0.2)
	_cast("tentacles", b_hero.global_position + Vector3(0.6, 0.0, 0.0))
	await sleep(NetCasts.LEAD + Tentacles.TELEGRAPH + 0.9)
	command(b, "shoves")
	check(await wait_reports("shoves", 1, 10.0), "B reports the second burst")
	r = reported(b, "shoves")
	eq(int(r["n"]), 1, "the tentacles shoved B once, on B's machine")
	check(float(r["moved"]) > 1.5, "... out of the burst (%.2f)" % float(r["moved"]))
	await sleep(0.3)
	near(GameWorld.flat_distance(b_hero.global_position, r["pos"]), 0.0, 0.35, "the host shows B where B landed")
	command(b, "stand", {"at": p})
	await sleep(0.6)

	# 3. B burns (its own roll), every screen shows it; only B ticks it.
	command(b, "ignite")
	check(await until(func() -> bool: return Burning.is_burning(b_hero), 3.0), "the host shows B on fire")
	command(a, "look", {"what": "fire"})
	check(await wait_reports("fire", 1, 10.0), "A reports the fire")
	check(bool(reported(a, "fire")["seen"]), "A shows B on fire")
	await sleep(1.6)

	# 4. A's damp at B: the fire goes out on B's machine, B is soaked; every screen agrees.
	command(a, "cast", {"spell": "damp", "aim": b_hero.global_position})
	check(await until(func() -> bool: return not Burning.is_burning(b_hero), 3.0), "the host shows B's fire out")
	check(await until(func() -> bool: return Wet.is_wet(b_hero), 2.0), "... and B damp")
	command(b, "look", {"what": "damp"})
	command(a, "look", {"what": "damp"})
	check(await wait_reports("damp", 2, 10.0), "A and B report the damp")
	var rb: Dictionary = reported(b, "damp")
	check(not bool(rb["burning"]) and bool(rb["own"]), "on B's machine the fire is out and B is soaked")
	check(bool(reported(a, "damp")["seen"]) and not bool(reported(a, "damp")["burning"]), "A shows B soaked, not burning")
	var burnt := float(rb["burnt"])
	print("[M4] burning: B lost %.1f to its fire (ticks of %.1f), every screen agrees" % [burnt, Burning.TICK_DAMAGE])
	check(burnt >= Burning.TICK_DAMAGE - 0.01, "B's fire ticked on B's machine (%.1f)" % burnt)
	near(fmod(burnt + 0.001, Burning.TICK_DAMAGE), 0.001, 0.02, "... whole ticks only (one machine ticked it)")
	await sleep(0.3)
	near(b_hero.hp, float(rb["hp"]), 0.15, "the host shows B's HP as B has it")

	# 5. A's coffee at B: B hasted on B's machine, shown everywhere.
	command(a, "cast", {"spell": "coffee", "aim": b_hero.global_position})
	check(await until(func() -> bool: return Coffee.is_hasted(b_hero), 3.0), "the host shows B hasted")
	check(b_hero.get_node_or_null("Coffee") != null, "... with the steam (a show-only Coffee)")
	command(b, "look", {"what": "coffee"})
	check(await wait_reports("coffee", 1, 10.0), "B reports the coffee")
	near(float(reported(b, "coffee")["speed"]), CoffeeSpell.COFFEE_MOVE_MULT, 0.01, "B walks %.0f%% faster on its own machine" % ((CoffeeSpell.COFFEE_MOVE_MULT - 1.0) * 100.0))

	# 6. The host's armor at B.
	_cast("armor", b_hero.global_position)
	check(await until(func() -> bool: return b_hero.has_modifier("armor"), 3.0), "the host shows B armored")
	command(b, "look", {"what": "armor"})
	command(a, "look", {"what": "armor"})
	check(await wait_reports("armor", 2, 10.0), "A and B report the armor")
	check(bool(reported(b, "armor")["own"]), "B has the armor on its own machine")
	check(bool(reported(a, "armor")["seen"]), "A shows B armored")

	# 7. B thrown into a priced prop on its own screen: it stops there, the host's prop takes the impact once.
	var prop := _a_prop()
	if check(prop != null, "the floor has a priced prop"):
		var hp0 := prop.hp
		var hits0 := int(Session.objects.stats["hits_in"])
		var at := _open_spot(prop.global_position, prop.radius + 1.0, base)
		command(b, "thrown", {"id": NetFloor.id_of(prop), "at": at})
		check(await wait_reports("thrown", 1, 10.0), "B reports the throw")
		await sleep(0.5)
		var rt: Dictionary = reported(b, "thrown")
		print("[M4] prop: B stopped %.2f from the %s's centre (the throw would have carried it %.1f); the host's prop went from %.1f to %.1f" % [
			float(rt["dist"]), prop.display_name, float(rt["slide"]), hp0, prop.hp if not prop.dead else 0.0])
		check(float(rt["dist"]) < prop.radius + 0.9, "B stopped against the prop on its own screen (%.2f)" % float(rt["dist"]))
		eq(int(Session.objects.stats["hits_in"]) - hits0, 1, "the prop took the impact once, on the host")
		check(prop.dead or prop.hp < hp0 - 1.0, "... and it shows (%.1f -> %.1f)" % [hp0, prop.hp])

	for peer in [a, b]:
		command(peer, "end")
	check(await wait_done(2, 30.0), "both clients are done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	for peer in [a, b]:
		eq(int(reported(peer, "end")), 0, "... nor on %s" % ("A" if peer == a else "B"))
	print("[M4] statuses: host sent %d, got %d; casts applied %d" % [int(Session.status.stats["out"]), int(Session.status.stats["in"]), int(Session.casts.stats["applied"])])


func run_client() -> void:
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	if index == 1:
		my_hero().spell_slots = ["damp", "coffee", "heal", "corn"] as Array[String]
	my_hero().shoved.connect(func(_d: Vector3, _n: float) -> void: shoves += 1)
	var b_hero := hero_at(3)
	var hp_at_fire := 0.0
	var watch_from := Vector3.ZERO
	var n0 := 0
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
			"look":
				var what := str(cmd["what"])
				await sleep(0.2)
				var me := my_hero()
				match what:
					"vines":
						report(what, {"own": me.is_rooted() if index == 2 else false, "seen": b_hero.has_modifier("vines") and b_hero.get_node_or_null("VineWrap") != null})
					"fire":
						report(what, {"seen": Burning.is_burning(b_hero)})
					"damp":
						report(what, {"own": Wet.is_wet(me), "seen": Wet.is_wet(b_hero), "burning": Burning.is_burning(b_hero), "burnt": hp_at_fire - me.hp, "hp": me.hp})
					"coffee":
						report(what, {"speed": me.move_speed_mult()})
					"armor":
						report(what, {"own": me.has_modifier("armor"), "seen": b_hero.has_modifier("armor")})
			"watch_shove":
				n0 = shoves
				watch_from = my_hero().global_position
			"shoves":
				report("shoves", {"n": shoves - n0, "moved": GameWorld.flat_distance(my_hero().global_position, watch_from), "pos": my_hero().global_position})
			"ignite":
				hp_at_fire = my_hero().hp
				Burning.ignite(my_hero(), my_hero(), 8.0)   # (B's own roll came up: the owner sets its hero on fire)
			"cast":
				var c := game.get("controller") as PlayerController
				my_hero()._ready_at.clear()
				c.aim_override = cmd["aim"]
				check(c.cast_spell(str(cmd["spell"]), 1.0), "A cast %s" % str(cmd["spell"]))
				c.aim_override = Vector3.INF
			"thrown":
				var prop := NetRegistry.node(int(cmd["id"])) as PricedProp
				my_hero().global_position = cmd["at"]
				my_hero().snap_to_ground()
				await sleep(0.3)
				var to := prop.global_position - my_hero().global_position
				to.y = 0.0
				var from := my_hero().global_position
				my_hero().shove(to, 3.0, NetRegistry.hero(1))   # (as if the host's hero threw B: on B's machine, the slide is B's)
				await until(func() -> bool: return not my_hero().is_shoved(), 2.0)
				report("thrown", {"dist": GameWorld.flat_distance(my_hero().global_position, prop.global_position), "slide": 3.0 * my_hero().shove_mult,
					"moved": GameWorld.flat_distance(from, my_hero().global_position)})
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


func _freeze_world() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster or n is Hellgate:
			n.set_physics_process(false)


func _a_prop() -> PricedProp:
	var site: SiteBuilder.Site = game.get("_site")
	for pr in site.props:
		if is_instance_valid(pr) and not pr.dead and pr.hp > 30.0:
			return pr
	return null


func _peer_named(n: String) -> int:
	for p: int in Session.roster:
		if str(Session.roster[p]["name"]) == n:
			return p
	return 0


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
