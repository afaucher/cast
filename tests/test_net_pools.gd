extends NetGameTest
## Pool water across machines (docs/design/pool-options.md "Built", Wading), two processes, `off` and `coast`. The water is
## seed-built terrain (both machines carve the same pool, in the floor checksum); the soak is an OWNER-applied status: each
## machine soaks the heroes it owns while they wade, and NetStatus shows it on the other screen.
##
## - the same pool on both machines;
## - FIRE: the client's hero catches fire on the deck (its own roll), then wades in: on its machine the water puts the fire
##   out and soaks it; the host sees the fire go out and the hero damp (the host never soaks a copy itself);
## - WADING: the client's hero is slowed to 0.75x in the water on its own machine;
## - AFTER: stepped out, it stays wet for the damp time (about DAMP_SOAK seconds left a moment later), on both screens;
## - the HOST's hero wades: the host soaks it, the client sees it damp.

const PEERS := 2
const SEED := 13

var _pool: Dictionary = {}


func run_host() -> void:
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	_freeze_world()
	var map := game.get("map") as HexMap
	if not check(not map.pools.is_empty(), "the floor has a pool"):
		return
	_pool = map.pools[0]
	check(await wait_reports("ready", 1, 30.0), "the client is streaming")
	var c := client_peers()[0]
	eq(str(reported(c, "ready")), NetFloor.canon(map.pools).sha256_text(), "both machines carved the same pool")
	var wet := _wet_spot()
	var dry := _dry_spot()
	var b := hero_at(2)
	check(b != null and not Net.resolves(b), "the client's hero is a copy here: its owner soaks it")
	# 1. the client's hero burns on the deck, then wades in
	command(c, "stand", {"at": dry})
	check(await wait_reports("stood", 1, 20.0), "the client stands on the deck")
	command(c, "ignite")
	check(await until(func() -> bool: return Burning.is_burning(b), 5.0), "the host shows the client's hero on fire")
	var in0 := int(Session.status.stats["in"])
	command(c, "wade", {"at": wet})
	check(await until(func() -> bool: return not Burning.is_burning(b) and Wet.is_wet(b), 5.0), "wading in put the fire out and soaked it, on the host's screen too")
	check(int(Session.status.stats["in"]) > in0, "... told by the owner (NetStatus)")
	check(await until(func() -> bool: return map.water_at(b.global_position), 3.0), "the host shows the client's hero in the water")
	check(await wait_reports("waded", 1, 10.0), "the client reports its wader")
	var r: Dictionary = reported(c, "waded")
	check(bool(r["wet"]) and not bool(r["burning"]), "on its own machine the hero is soaked and out")
	near(float(r["speed"]), Wading.SPEED_MULT, 0.01, "and slowed to 0.75x in the water")
	# 2. out of the water: wet for the damp time
	command(c, "out", {"at": dry})
	check(await wait_reports("dried", 1, 10.0), "the client stepped out")
	r = reported(c, "dried")
	check(float(r["left"]) > SpellBook.DAMP_SOAK - 2.0, "a second after stepping out it has almost all the damp time left (%.1f s)" % float(r["left"]))
	near(float(r["speed"]), 1.0, 0.01, "full speed on the deck")
	check(Wet.is_wet(b) and Wet.remaining(b) > SpellBook.DAMP_SOAK - 3.0, "the host shows it still damp (%.1f s)" % Wet.remaining(b))
	# 3. the host's own hero wades: the host soaks it, the client sees it
	var me := my_hero()
	me.global_position = wet + Vector3(0.6, 0.0, 0.0)
	me.snap_to_ground()
	await sleep(0.3)
	check(Wet.is_wet(me), "the host soaks its own wader")
	command(c, "look")
	check(await wait_reports("look", 1, 10.0), "the client looks at the host's hero")
	check(bool(reported(c, "look")), "the client shows the host's hero damp")
	command(c, "end")
	check(await wait_reports("end", 1, 10.0), "the client is done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	eq(int(reported(c, "end")), 0, "... nor on the client")


func run_client() -> void:
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	var map := game.get("map") as HexMap
	report("ready", NetFloor.canon(map.pools).sha256_text())
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		var me := my_hero()
		match str(cmd.get("cmd", "")):
			"stand":
				me.global_position = cmd["at"]
				me.snap_to_ground()
				await sleep(0.3)
				report("stood", true)
			"ignite":
				Burning.ignite(me, me, 8.0)   # (its own roll came up: the owner sets its hero on fire)
			"wade":
				me.global_position = cmd["at"]
				me.snap_to_ground()
				await sleep(0.3)
				report("waded", {"wet": Wet.is_wet(me), "burning": Burning.is_burning(me), "speed": me.effective_speed() / me.move_speed})
			"out":
				me.global_position = cmd["at"]
				me.snap_to_ground()
				await sleep(1.0)
				report("dried", {"left": Wet.remaining(me), "speed": me.effective_speed() / me.move_speed})
			"look":
				await sleep(0.3)
				report("look", Wet.is_wet(hero_at(1)))
			"end":
				report("end", Net.guard_hits.size())
				running = false
			_:
				running = false


func _wet_spot() -> Vector3:
	var c: Vector2 = _pool["center"]
	return Vector3(c.x, 0.0, c.y)


## Deck 2.2 out from the middle of the pool's first edge.
func _dry_spot() -> Vector3:
	var ol: Array = _pool["outline"]
	var a: Vector2 = ol[0]
	var b: Vector2 = ol[1]
	var p := (a + b) * 0.5 + PoolGeo.edge_normals(ol)[0] * 2.2
	return Vector3(p.x, 0.0, p.y)


func _freeze_world() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster or n is Hellgate:
			n.set_physics_process(false)
