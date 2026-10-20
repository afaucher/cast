extends NetGameTest
## M4 "done when" (networking-build-plan.md: test_net_m4_casts), three processes, `off` and `coast`: casts are events that
## land at the same moment on every machine, and each machine applies only what it resolves.
##
## - CORN: client A (c1, seat 2) casts corn at client B (c2, seat 3). The cob lands on ALL THREE machines within a frame of
##   the same host_time (the cast's moment + NetCasts.LEAD + CornStrike.DELAY), and B, standing in it, loses exactly one
##   corn's damage (B's machine decided it; the host's and A's corn did not hit B's puppet again);
## - HEAL: A's heal aimed at B (the aim snaps onto B) heals B exactly once, by one heal; A and the host are not healed;
##   every screen shows A's charges as A has them (the cast carries them);
## - SIDESTEP: A casts corn at B again, and B walks out of the ring on its own screen just before the cob lands, when the
##   host and A still SHOW B inside it (they show B a tenth of a second or more ago): B is not hit (what you dodged on
##   your screen does not hit you);
## - nothing tripped the OWNER-write guard on any machine.

const PEERS := 3
const SEED := 13
const FRAME := 1.0 / 60.0
const DODGE_LEAD := 0.7   ## B starts walking out of the second corn this long before it lands

## Every corn that landed on this machine: {t (host_time), truth, at (the cast's moment), b_dist (B as shown here, from the
## cob), b_hp (B's HP as shown here, right after)}.
var landings: Array = []
var _cast_at := {}
## Hits this machine's own hero took (its `damaged` signal).
var hits_seen := 0


func _ready_probe() -> void:
	my_hero().damaged.connect(func(amount: float, _src: Node) -> void:
		if amount > 0.0:
			hits_seen += 1)
	Session.casts.cast_applied.connect(func(spell: String, _caster: Actor, node: Node) -> void:
		var at := float((Session.casts.last_applied.get(spell, {}) as Dictionary).get("at", 0.0))
		if node is CornStrike:
			(node as CornStrike).landed.connect(func(pos: Vector3) -> void:
				var b := hero_at(3)
				landings.append({"t": Session.host_time(), "truth": truth(), "at": at, "b_dist": GameWorld.flat_distance(b.global_position, pos),
					"b_hp": b.hp})))


func run_host() -> void:
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	_ready_probe()
	_freeze_world()
	check(await wait_reports("ready", 2, 30.0), "both clients are streaming")
	var a := _peer_named("c1")
	var b := _peer_named("c2")
	var base := my_hero().global_position
	var p := base
	for d in [7.0, 8.5, 10.0]:
		p = _open_spot(base, d, 0)
		if p != base:
			break
	var a_spot := _open_spot_away(p, 4.5, base)
	var q := _open_spot_away(p, 4.5, a_spot)   # where B sidesteps to
	check(GameWorld.flat_distance(p, base) > 5.0 and GameWorld.flat_distance(a_spot, p) > 4.0 and GameWorld.flat_distance(q, p) > 4.0 and GameWorld.flat_distance(a_spot, base) > 3.5,
		"open floor for the three (host %s, B at %s, A at %s, B's sidestep to %s)" % [base, p, a_spot, q])
	command(b, "stand", {"at": p})
	command(a, "stand", {"at": a_spot})
	check(await wait_reports("stood", 2, 20.0), "A and B stand where the test wants them")
	await sleep(0.6)
	var host_hp := my_hero().hp

	# 1. A's corn on B.
	var c1_charges := hero_at(2).charges_of("corn")
	command(a, "cast", {"spell": "corn", "aim": p})
	check(await until(func() -> bool: return landings.size() >= 1, 6.0), "the corn landed on the host")
	check(await wait_reports("corn1", 2, 20.0), "A and B report the corn")
	var host_l: Dictionary = landings[0]
	var expect := float(host_l["at"]) + CornStrike.DELAY
	var views := {"host": host_l, "A": reported(a, "corn1")["landing"], "B": reported(b, "corn1")["landing"]}
	var truths: Array[float] = []
	for who: String in views:
		var l: Dictionary = views[who]
		var off := float(l["t"]) - (float(l["at"]) + CornStrike.DELAY)
		print("[M4] corn on %s: landed at host_time %.4f (cast moment %.4f + lead + delay: off by %+.1f ms), wall %.4f" % [who, float(l["t"]), float(l["at"]), off * 1000.0, float(l["truth"])])
		near(float(l["at"]), float(host_l["at"]), 0.0005, "%s scheduled the same cast moment" % who)
		check(off >= -0.002 and off <= FRAME + 0.004, "%s: the cob lands within a frame of the cast's moment + %.2f s (%+.1f ms)" % [who, NetCasts.LEAD + CornStrike.DELAY, off * 1000.0])
		truths.append(float(l["truth"]))
	var spread: float = truths.max() - truths.min()
	print("[M4] corn: the three landings span %.1f ms of real time (each machine's clock error included)" % (spread * 1000.0))
	check(spread < 0.05, "... and within %.0f ms of each other in real time (%.1f ms)" % [50.0, spread * 1000.0])
	var r_b: Dictionary = reported(b, "corn1")
	var dmg := SpellBook.corn_damage(1.0)
	near(float(r_b["before"]) - float(r_b["after"]), dmg, 0.01, "B, standing in the blast, lost exactly one corn's damage (%.0f): it was hit once, on its own machine" % dmg)
	eq(int(r_b["hits"]), 1, "B's hero took one hit")
	await sleep(0.5)
	near(hero_at(3).hp, float(r_b["after"]), 0.15, "the host shows B's HP as B has it")
	near(float(reported(a, "corn1")["b_hp_later"]), float(r_b["after"]), 0.15, "A shows B's HP as B has it")
	near(my_hero().hp, host_hp, 0.01, "the host, far from the blast, was not hit")
	eq(hero_at(2).charges_of("corn"), c1_charges - 1, "the host shows A's corn charges as A has them (the cast carries them)")

	# 2. A's heal on B.
	var b_before := float(r_b["after"])
	command(a, "cast", {"spell": "heal", "aim": p})
	check(await wait_reports("heal", 2, 20.0), "A and B report the heal")
	var heal := HealSpell.heal_amount(1.0)
	var r_bh: Dictionary = reported(b, "heal")
	near(float(r_bh["hp"]) - b_before, heal, 0.01, "the heal aimed at B healed B once, by one heal (%.0f)" % heal)
	eq(int(r_bh["heals"]), 1, "B's machine healed it once")
	check(not bool(reported(a, "heal")["healed_self"]), "A, outside the ring, was not healed")
	near(my_hero().hp, host_hp, 0.01, "the host was not healed")
	await sleep(0.4)
	near(hero_at(3).hp, float(r_bh["hp"]), 0.15, "the host shows B's healed HP")
	eq(int(reported(b, "heal")["a_heal_charges"]), hero_at(2).charges_of("heal"), "B and the host show A's heal charges alike")

	# 3. A's corn at B again; B sidesteps on its own screen just before the cob lands.
	landings.clear()
	command(b, "dodge", {"to": q})
	command(a, "cast", {"spell": "corn", "aim": p})
	check(await until(func() -> bool: return landings.size() >= 1, 6.0), "the second corn landed on the host")
	check(await wait_reports("corn2", 2, 20.0), "A and B report the second corn")
	var h2: Dictionary = landings[0]
	var r_b2: Dictionary = reported(b, "corn2")
	var r_a2: Dictionary = reported(a, "corn2")
	print("[M4] sidestep: B as shown from the cob when it landed: host %.2f, A %.2f, B itself %.2f (radius %.1f)" % [float(h2["b_dist"]), float(r_a2["landing"]["b_dist"]), float(r_b2["landing"]["b_dist"]), CornStrike.RADIUS])
	var reach := CornStrike.RADIUS + hero_at(3).radius   # (GameWorld.actors_in_radius counts the body's radius)
	check(float(h2["b_dist"]) < reach, "the host still SHOWED B inside the ring when the cob landed (%.2f < %.2f)" % [float(h2["b_dist"]), reach])
	check(float(r_a2["landing"]["b_dist"]) < reach, "so did A (%.2f)" % float(r_a2["landing"]["b_dist"]))
	check(float(r_b2["landing"]["b_dist"]) > reach, "B had walked out on its own screen (%.2f)" % float(r_b2["landing"]["b_dist"]))
	near(float(r_b2["after"]), float(r_b2["before"]), 0.01, "B was not hit: it dodged on its own screen")
	eq(int(r_b2["hits"]), 0, "B took no hit")

	# 4. Bookkeeping.
	for peer in [a, b]:
		command(peer, "end")
	check(await wait_done(2, 30.0), "both clients are done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	for peer in [a, b]:
		eq(int(reported(peer, "end")["guard"]), 0, "... nor on %s" % ("A" if peer == a else "B"))
	print("[M4] casts: host applied %d (late %d, max late %.1f ms); A sent %d" % [int(Session.casts.stats["applied"]), int(Session.casts.stats["late"]),
		float(Session.casts.stats["max_late"]) * 1000.0, int(reported(a, "end")["sent"])])


func run_client() -> void:
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	_ready_probe()
	var heals := [0]
	my_hero().healed.connect(func(_a: float) -> void: heals[0] += 1)
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"stand":
				_stand(cmd["at"])
				await sleep(0.3)
				print("[M4] c%d stands at %s (asked %s)" % [index, my_hero().global_position, cmd["at"]])
				report("stood", true)
			"cast":
				var c := game.get("controller") as PlayerController
				my_hero()._ready_at.clear()   # (the test casts back to back: no cooldowns)
				c.aim_override = cmd["aim"]
				var ok := c.cast_spell(str(cmd["spell"]), 1.0)
				c.aim_override = Vector3.INF
				check(ok, "A cast %s" % str(cmd["spell"]))
				if str(cmd["spell"]) == "corn":
					await _report_corn("corn1" if not _cast_at.has("corn") else "corn2")
					_cast_at["corn"] = true
				else:
					await sleep(NetCasts.LEAD + 0.5)
					report("heal", {"healed_self": heals[0] > 0})
			"dodge":
				# B: watch for A's corn, and step out of the ring 60 ms before the cob lands (on this screen).
				var n := landings.size()
				var hp := my_hero().hp
				var hits_before := hits_seen
				await until(func() -> bool: return Session.casts.last_applied.has("corn") and float(Session.casts.last_applied["corn"]["at"]) > float(_cast_at.get("last", 0.0)), 8.0)
				var at := float(Session.casts.last_applied["corn"]["at"])
				# Walk (a teleport would show on the other screens at once): 0.7 s at a walk is about 3.2 units, out of the
				# ring (2.5 + the hero's 0.4) on this screen, while the others, showing B a tenth of a second or more ago,
				# still have it inside.
				await until(func() -> bool: return Session.host_time() >= at + CornStrike.DELAY - DODGE_LEAD, 4.0)
				var c := game.get("controller") as PlayerController
				var to: Vector3 = cmd["to"] - my_hero().global_position
				to.y = 0.0
				c.move_override = to.normalized()
				await until(func() -> bool: return landings.size() > n, 4.0)
				c.move_override = Vector3.INF
				await sleep(0.5)
				report("corn2", {"landing": landings.back(), "before": hp, "after": my_hero().hp, "hits": hits_seen - hits_before})
			"end":
				report("end", {"guard": Net.guard_hits.size(), "sent": int(Session.casts.stats["casts_out"])})
				running = false
			_:
				running = false
		if index == 2 and str(cmd.get("cmd", "")) == "stand":
			_watch_b()


## B: report each corn and heal that reaches it (the first corn, then the heal).
func _watch_b() -> void:
	var hp := my_hero().hp
	var hits_before := hits_seen
	await until(func() -> bool: return landings.size() >= 1, 15.0)
	_cast_at["last"] = float(landings[0]["at"])
	await sleep(0.3)
	var after := my_hero().hp
	report("corn1", {"landing": landings[0], "before": hp, "after": after, "hits": hits_seen - hits_before})
	var heals := [0]
	my_hero().healed.connect(func(_a: float) -> void: heals[0] += 1)
	await until(func() -> bool: return Session.casts.last_applied.has("heal"), 15.0)
	await sleep(0.4)
	var a_hero := hero_at(2)
	report("heal", {"hp": my_hero().hp, "heals": heals[0], "a_heal_charges": a_hero.charges_of("heal")})


## A: the corn it cast has landed here; report it (and B's HP as A shows it a little later).
func _report_corn(key: String) -> void:
	var n := landings.size()
	await until(func() -> bool: return landings.size() > n, 6.0)
	await sleep(0.8)
	report(key, {"landing": landings.back() if not landings.is_empty() else {}, "b_hp_later": hero_at(3).hp})


# --- Helpers ---------------------------------------------------------------------------------------------------

## Host: the floor's monsters and hellgates stand still (the test is about casts; nothing else should hurt anyone).
func _freeze_world() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster or n is Hellgate:
			n.set_physics_process(false)


func _stand(at: Vector3) -> void:
	my_hero().global_position = at
	my_hero().snap_to_ground()


func _peer_named(n: String) -> int:
	for p: int in Session.roster:
		if str(Session.roster[p]["name"]) == n:
			return p
	return 0


## Open floor at `q`: walkable, off the walls, level with `p`, and nothing standing within 1.6 (decor, the van, props,
## monsters: the soft separation would push a hero placed there out).
func _clear(map: HexMap, q: Vector3, p: Vector3) -> bool:
	if not map.is_walkable_cell(Hex.from_world(q)) or map.blocks_point(q, 0.6) or absf(map.ground_height(q) - p.y) > 0.6:
		return false
	for a in GameWorld.actors_in_radius(q, 1.6):
		if not (a is Hero):
			return false
	return true


## Walkable floor `dist` from `p`, as far as it can be from `away` (of sixteen directions).
func _open_spot_away(p: Vector3, dist: float, away: Vector3) -> Vector3:
	var map := game.get("map") as HexMap
	var best := p
	var best_d := -1.0
	for k in 16:
		var a := TAU * float(k) / 16.0
		var q := p + Vector3(cos(a), 0.0, sin(a)) * dist
		if _clear(map, q, p):
			var d := GameWorld.flat_distance(q, away)
			if d > best_d:
				best_d = d
				best = Vector3(q.x, map.ground_height(q), q.z)
	return best


## Walkable floor about `dist` from `p` (the first of eight directions from `first` that has it).
func _open_spot(p: Vector3, dist: float, first: int) -> Vector3:
	var map := game.get("map") as HexMap
	for k in 8:
		var a := TAU * float((k + first) % 8) / 8.0
		var q := p + Vector3(cos(a), 0.0, sin(a)) * dist
		if _clear(map, q, p):
			return Vector3(q.x, map.ground_height(q), q.z)
	return p
