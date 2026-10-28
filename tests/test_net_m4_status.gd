extends NetGameTest
## M4 statuses and shoves across machines (networking-build-plan.md M4b, "vines, damp, coffee"), three processes, `off` and
## `coast`. The target's OWNER applies a status and runs it; the other screens show what the owner announced (NetStatus).
## B is client c2 (seat 3); the host and A (c1, seat 2) cast at it.
##
## - VINES: the host's vines root B on B's machine; the host and A show B rooted (the leg wraps); the host's tentacles
##   then cannot move B (Actor.shove refuses while rooted, on B's machine);
## - TENTACLES: once the root is gone, the host's tentacles lay the same sideways oval on all three machines (the aim
##   travels in the cast); the burst shoves B once and the swats shove it again on their ticks of the shared schedule,
##   each once, on B's machine;
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
var shove_times: Array[float] = []   ## Session.host_time() of each of this machine's hero's shoves


func _init() -> void:
	net_timeout = 95.0   # (two casts of tentacles stay up 6 s each, waited out)


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
	await sleep(NetCasts.LEAD + Tentacles.TELEGRAPH + 0.5)
	command(b, "shoves")
	check(await wait_reports("shoves", 1, 10.0), "B reports the shoves")
	var r: Dictionary = reported(b, "shoves")
	eq(int(r["n"]), 0, "rooted, B was not shoved by the tentacles (B's machine dropped it)")
	check(float(r["moved"]) < 0.3, "... and did not move (%.2f)" % float(r["moved"]))

	# 2. The root wears off and those tentacles retract; B stands back at its spot. The host's tentacles land beside B,
	# across the host's line of aim: every machine lays the same oval (the aim travels in the cast event), the burst
	# shoves B once and then the swats shove it on their ticks, each on B's machine.
	check(await until(func() -> bool: return not b_hero.has_modifier("vines") and not _tentacles_up(), 12.0), "the root and the first tentacles are gone")
	await sleep(0.4)
	reports[a].erase("stood")
	reports[b].erase("stood")
	command(b, "stand", {"at": p})
	check(await wait_reports("stood", 1, 20.0), "B stands back at its spot")
	await sleep(0.4)
	reports[b].erase("shoves")
	command(b, "watch_shove")
	await sleep(0.2)
	var to_b := b_hero.global_position - my_hero().global_position
	to_b.y = 0.0
	var side := Vector3(-to_b.z, 0.0, to_b.x).normalized()
	var aim_at := b_hero.global_position + side * (SpellBook.ALLY_SNAP + 0.3)   # (B off the middle along the oval's WIDTH; no snap onto B)
	var want_aim := SpellBook.resolve_target(my_hero(), aim_at) - my_hero().global_position
	want_aim.y = 0.0
	_cast("tentacles", aim_at)
	check(await until(_tentacles_up, 2.0), "the host runs the tentacles")
	var mine := _tentacles()
	if check(mine != null, "the host's tentacles node"):
		check(mine.aim.dot(want_aim.normalized()) > 0.995, "the oval lies across the host's aim (%s vs %s)" % [str(mine.aim), str(want_aim.normalized())])
		command(a, "look", {"what": "tentacles"})
		command(b, "look", {"what": "tentacles"})
		check(await wait_reports("tentacles", 2, 10.0), "A and B report their tentacles")
		for peer in [a, b]:
			var o: Dictionary = reported(peer, "tentacles")
			var who := "A" if peer == a else "B"
			if not check(bool(o.get("up", false)), "%s runs the tentacles" % who):
				continue
			near(GameWorld.flat_distance(o["c"], mine.global_position), 0.0, 0.02, "%s's oval is centred where the host's is" % who)
			check((o["aim"] as Vector3).dot(mine.aim) > 0.9999, "%s's oval lies the same way (%s vs %s)" % [who, str(o["aim"]), str(mine.aim)])
			near(float(o["w"]), mine.width(), 0.001, "%s's oval is as wide" % who)
			near(float(o["d"]), mine.depth(), 0.001, "%s's oval is as deep" % who)
	check(await until(func() -> bool: return not _tentacles_up(), 12.0), "the tentacles retract")
	await sleep(0.4)
	command(b, "shoves")
	check(await wait_reports("shoves", 1, 10.0), "B reports the second cast's shoves")
	r = reported(b, "shoves")
	var times: Array = r["times"]
	print("[M4] tentacles: B was shoved at %s s after the cast's moment (burst at %.2f, swats every %.1f)" % [str(times), Tentacles.TELEGRAPH, TentaclesSpell.TENTACLES_SWAT_EVERY])
	check(times.size() >= 2, "the burst and at least one swat shoved B, on B's machine (%d)" % times.size())
	if not times.is_empty():
		near(float(times[0]), Tentacles.TELEGRAPH, 0.07, "the first is the burst")
	var ticks := {}
	var on_tick := true
	for t: float in times:
		var k := roundi((t - Tentacles.TELEGRAPH) / TentaclesSpell.TENTACLES_SWAT_EVERY)
		if absf(t - (Tentacles.TELEGRAPH + float(k) * TentaclesSpell.TENTACLES_SWAT_EVERY)) > 0.07 or k > TentaclesSpell.tentacles_swats(1.0):
			on_tick = false
		ticks[k] = int(ticks.get(k, 0)) + 1
	check(on_tick, "every shove on a tick of the shared schedule %s" % str(times))
	eq(ticks.size(), times.size(), "each tick shoved B once (one machine resolved it) %s" % str(ticks))
	check(float(r["moved"]) > 1.5, "... out of the oval (%.2f)" % float(r["moved"]))
	await sleep(0.3)
	near(GameWorld.flat_distance(b_hero.global_position, r["pos"]), 0.0, 0.35, "the host shows B where B landed")
	command(b, "stand", {"at": p, "mend": true})   # (and B heals itself: swats against a wall slam, and the fire below must not hit the 1 HP floor)
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
	my_hero().shoved.connect(func(_d: Vector3, _n: float) -> void:
		shoves += 1
		shove_times.append(Session.host_time()))
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
				if bool(cmd.get("mend", false)):
					my_hero().heal(my_hero().max_hp)
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
					"tentacles":
						var tn := _tentacles()
						if tn == null:
							report(what, {"up": false})
						else:
							report(what, {"up": true, "c": tn.global_position, "aim": tn.aim, "w": tn.width(), "d": tn.depth()})
			"watch_shove":
				n0 = shoves
				watch_from = my_hero().global_position
			"shoves":
				# (when, after the last tentacles cast's moment on the shared clock, each shove since watch_shove landed)
				var at := float((Session.casts.last_applied.get("tentacles", {}) as Dictionary).get("at", 0.0))
				var times: Array[float] = []
				for i in range(n0, shove_times.size()):
					times.append(snappedf(shove_times[i] - at, 0.001))
				report("shoves", {"n": shoves - n0, "moved": GameWorld.flat_distance(my_hero().global_position, watch_from), "pos": my_hero().global_position,
					"times": times})
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


## This machine's live Tentacles node, or null.
func _tentacles() -> Tentacles:
	if GameWorld.root == null:
		return null
	for n in GameWorld.root.get_children():
		if n is Tentacles and not n.is_queued_for_deletion():
			return n
	return null


func _tentacles_up() -> bool:
	return _tentacles() != null


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
