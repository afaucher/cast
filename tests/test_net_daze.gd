extends NetGameTest
## The brute's daze across machines, two processes, `off` and `coast`. A is the client (seat 2).
##
## - The host's brute slams A point-blank. The strike is resolved on A's machine (the victim decides: world.windup ->
##   Monster.net_strike -> Combat.slam), so the daze is A's own: A is dazed for Brute.DAZE_TIME on its own clock, can't
##   walk or swing during it, and a spell A speaks while dazed still goes off (and lands on the host too: NetCasts);
## - A's machine announces the daze like any status (NetStatus "mods"): the host shows the stars over A's puppet for about
##   the same 0.6 s, and never dazes the puppet itself.

const PEERS := 2
const SEED := 13
const DAZE_TIME := 0.6        ## Brute.DAZE_TIME (brute.gd has no class name)


func run_host() -> void:
	net_timeout = 60.0
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	_freeze_world()
	for c in hero_at(3).get_children():
		if c is AllyBrain:
			c.set_physics_process(false)   # (the AI Gasket would come and spin A out of the way)
	check(await wait_reports("ready", 1, 30.0), "the client is streaming")
	var a := client_peers()[0]
	command(a, "stand", {"at": _open_spot(my_hero().global_position, 7.0)})
	check(await wait_reports("stood", 1, 20.0), "A stands in the open")
	await sleep(0.6)
	var a_hero := hero_at(2)
	var brute := _spawn_near(a_hero.global_position, "brute", 1.15)
	if not check(brute != null, "the host spawned a brute beside A"):
		return
	var bid := NetFloor.id_of(brute)
	var slams: Array = []
	brute.connect("slammed", func(pos: Vector3) -> void:
		slams.append(GameWorld.flat_distance(hero_at(2).global_position, pos)))
	await sleep(0.4)
	command(a, "daze", {"id": bid})
	await sleep(0.2)
	brute.aggro(a_hero)
	check(await until(func() -> bool: return slams.size() >= 1, 6.0), "the brute slammed on the host")
	if not slams.is_empty():
		print("[daze] the host showed A %.2f from the brute at its strike" % float(slams[0]))
	check(not a_hero.daze(DAZE_TIME), "the host can't daze A's puppet itself (A's machine decides)")
	# The host shows the stars A announced, for about as long as A is dazed.
	check(await until(func() -> bool: return a_hero.is_showing_daze(), 4.0), "the host shows the stars over A's puppet")
	var shown_at := wall()
	check(await until(func() -> bool: return not a_hero.is_showing_daze(), 3.0), "... and takes them away again")
	var shown_for := wall() - shown_at
	print("[daze] the host showed A dazed for %.2f s" % shown_for)
	check(shown_for > DAZE_TIME - 0.15 and shown_for < DAZE_TIME + 0.25, "... for about the daze's 0.6 s (%.2f)" % shown_for)
	brute.apply_damage(9999.0, my_hero())
	check(await wait_reports("daze", 1, 15.0), "A reports its daze")
	var r: Dictionary = reported(a, "daze")
	print("[daze] A: resolved %d strike(s), dazed for %.2f s, cast while dazed %s (dazed then: %s), moved %.3f, swung %s" % [
		int(r["resolved"]), float(r["dazed_for"]), r["cast_ok"], r["dazed_at_cast"], float(r["moved"]), r["melee"]])
	eq(int(r["resolved"]), 1, "A's machine resolved the slam (the victim decides)")
	near(float(r["dazed_for"]), DAZE_TIME, 0.06, "A was dazed for 0.6 s on its own machine")
	check(bool(r["cast_ok"]) and bool(r["dazed_at_cast"]), "A's spell spoken while dazed was cast")
	near(float(r["moved"]), 0.0, 0.01, "A could not walk while dazed")
	check(not bool(r["melee"]), "... nor swing")
	check(await until(func() -> bool: return Session.casts.last_applied.has("heal") and int(Session.casts.last_applied["heal"]["caster"]) == NetFloor.id_of(a_hero), 3.0),
		"A's heal from the daze landed on the host as well")
	command(a, "end")
	check(await wait_done(1, 20.0), "the client is done")


func run_client() -> void:
	net_timeout = 60.0
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	report("ready", true)
	var c := game.get("controller") as PlayerController
	var running := true
	while running:
		var cmd := await wait_command(50.0)
		match str(cmd.get("cmd", "")):
			"stand":
				my_hero().global_position = cmd["at"]
				my_hero().snap_to_ground()
				await sleep(0.3)
				report("stood", true)
			"daze":
				var h := my_hero()
				var n := Session.world.resolved.size()
				check(await until(func() -> bool: return h.is_dazed(), 8.0), "A gets dazed")
				var t0 := GameWorld.time
				# A spell spoken now (the typed console and voice both go through cast_spell) goes off.
				h._ready_at.clear()
				h.set_charges("heal", 3)
				c.aim_override = h.global_position
				var cast_ok := c.cast_spell("heal", 1.0)
				var dazed_at_cast := h.is_dazed()
				c.aim_override = Vector3.INF
				# Steering and a swing do nothing (wait out the slam's shove first: it slides A out).
				await until(func() -> bool: return not h.is_shoved(), 0.4)
				var at := h.global_position
				var away := at - (NetRegistry.node(int(cmd["id"])) as Node3D).global_position
				away.y = 0.0
				c.move_override = away.normalized() if away.length() > 0.05 else Vector3.RIGHT
				await sleep(0.1)
				var moved := GameWorld.flat_distance(h.global_position, at) if h.is_dazed() else -1.0
				h._ready_at.clear()
				var melee := h.melee(away) if h.is_dazed() else true
				c.move_override = Vector3.INF
				await until(func() -> bool: return not h.is_dazed(), 3.0)
				var dazed_for := GameWorld.time - t0
				report("daze", {"resolved": Session.world.resolved.size() - n, "dazed_for": dazed_for, "cast_ok": cast_ok,
					"dazed_at_cast": dazed_at_cast, "moved": moved, "melee": melee})
			_:
				running = false


## Host: the monsters and gates hold still.
func _freeze_world() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if (n is Monster or n is Hellgate) and not (n as Actor).dead:
			n.set_physics_process(false)


## Host: spawn a monster `dist` from `p` on open floor (it gets a runtime id and every client builds it).
func _spawn_near(p: Vector3, kind: String, dist: float) -> Monster:
	var spot := _open_spot(p, dist)
	if spot == p:
		return null
	var m := MonsterFactory.spawn(kind, Hex.from_world(spot))
	if m != null:
		m.global_position = Vector3(spot.x, m.global_position.y, spot.z)
	return m


## Open floor about `dist` from `p` (of sixteen directions, the first with nothing but heroes standing near it).
func _open_spot(p: Vector3, dist: float) -> Vector3:
	var map := game.get("map") as HexMap
	for k in 16:
		var a := TAU * float(k) / 16.0
		var q := p + Vector3(cos(a), 0.0, sin(a)) * dist
		if not map.is_walkable_cell(Hex.from_world(q)) or map.blocks_point(q, 0.6) or absf(map.ground_height(q) - p.y) > 0.6:
			continue
		var clear := true
		for x in GameWorld.actors_in_radius(q, 1.0):
			if not (x is Hero):
				clear = false
		if clear:
			return Vector3(q.x, map.ground_height(q), q.z)
	return p
