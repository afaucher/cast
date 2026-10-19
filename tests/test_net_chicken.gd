extends NetGameTest
## The Chicken spell across machines, two processes, `off` and `coast`. Chickens are host-owned actors like monsters: the cast
## is an event that lands on every machine, the HOST spawns the flock and runs it, and a client shows it from the world
## stream (world.spawn kind "chicken", monster-format entries, world.die).
##
## - The host casts chicken: four chickens run on the host; the client shows the same four ids as puppets, near where the
##   host has them.
## - The client casts chicken: the host spawns (and runs) four more; the client never spawned any itself, it shows the
##   host's four new ones as puppets too.
## - The client hits one of them (a request the host applies): two hits kill it on the host, and the client shows it dead.
## - Twelve seconds on, the flocks poof on the host, and the client's puppets go with them.
## - Nothing tripped the OWNER-write guard on either machine.

const PEERS := 2
const SEED := 13


func _init() -> void:
	net_timeout = 85.0


func run_host() -> void:
	if not await enter_floor(SEED, 1, {"spells": "chicken,heal"}):
		return
	if not await wait_sync():
		return
	_freeze_world()
	check(await wait_reports("ready", 1, 30.0), "the client is on the floor")
	var c1 := client_peers()[0]
	eq(my_hero().spell_slots, ["chicken", "heal"] as Array[String], "the host's hero is licensed for chicken")

	# 1. The host's cast.
	var spot := _open_spot(my_hero().global_position, 4.5)
	_cast_here("chicken", spot)
	check(await until(func() -> bool: return _chickens().size() == Chicken.FLOCK, 4.0), "the host's cast spawned four chickens on the host")
	var first := _ids()
	for id in first:
		check(not Net.is_copy(NetRegistry.node(id)), "the host runs chicken %d (it is not a copy)" % id)
		check(id >= NetRegistry.RUNTIME_BASE, "chicken %d has a runtime id" % id)
	command(c1, "look", {"n": Chicken.FLOCK})
	check(await wait_reports("look1", 1, 10.0), "the client looked")
	var seen: Dictionary = reported(c1, "look1")
	eq(seen["ids"], first, "the client shows the host's four chickens (same ids)")
	eq(int(seen["puppets"]), Chicken.FLOCK, "as puppets")
	var pos: Dictionary = seen["pos"]
	for id in first:
		var c := NetRegistry.node(id) as Chicken
		if c != null and pos.has(id):
			var d := GameWorld.flat_distance(c.global_position, pos[id])
			check(d < 2.5, "chicken %d is about where the host has it on the client (%.2f off; a running chicken, ~100 ms behind)" % [id, d])

	# 2. The client's cast: the host spawns its flock.
	command(c1, "cast", {"at": _open_spot(hero_at(2).global_position, 4.0)})
	check(await until(func() -> bool: return _chickens().size() >= 2 * Chicken.FLOCK - 1, 6.0), "the client's cast spawned four more chickens on the host (%d)" % _chickens().size())
	var second: Array = _ids().filter(func(id: int) -> bool: return not first.has(id))
	eq(second.size(), Chicken.FLOCK, "four new ones")
	for id in second:
		check(not Net.is_copy(NetRegistry.node(id)), "the host runs the client's chicken %d too" % id)
	command(c1, "look2", {"ids": second})
	check(await wait_reports("look2", 1, 10.0), "the client looked again")
	var seen2: Dictionary = reported(c1, "look2")
	eq(int(seen2["shown"]), Chicken.FLOCK, "the client shows the four chickens of its own cast, from the host")
	eq(int(seen2["own"]), 0, "and never spawned one itself")

	# 3. The client hits one: a request the host applies (two hits kill it).
	var victim: int = second[0]
	command(c1, "hit", {"id": victim})
	check(await until(func() -> bool: return NetRegistry.node(victim) == null or (NetRegistry.node(victim) as Actor).dead, 4.0), "the client's two hits killed chicken %d on the host" % victim)
	check(await wait_reports("hit", 1, 10.0), "the client reports the hit")
	check(bool(reported(c1, "hit")["dead"]), "and shows it dead")

	# 4. Twelve seconds: everything poofs, everywhere.
	check(await until(func() -> bool: return _chickens().is_empty(), Chicken.LIFETIME + 3.0), "the flocks poofed on the host")
	command(c1, "gone")
	check(await wait_reports("gone", 1, 10.0), "the client reports")
	eq(int(reported(c1, "gone")["left"]), 0, "and none is left on the client")
	command(c1, "end")
	check(await wait_reports("end", 1, 10.0), "the client is done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	eq(int(reported(c1, "end")["guard"]), 0, "... nor on the client")
	print("[chicken] world: %d spawns, %d deaths sent; the client applied %d entries" % [int(Session.world.stats["spawns"]), int(Session.world.stats["deaths"]),
		int(reported(c1, "end")["entries"])])


func run_client() -> void:
	if not await enter_floor(SEED, 1, {"spells": "chicken,heal"}):
		return
	if not await wait_sync():
		return
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"look":
				await until(func() -> bool: return _chickens().size() >= int(cmd["n"]), 6.0)
				await sleep(0.3)
				var pos := {}
				var puppets := 0
				for c in _chickens():
					pos[NetFloor.id_of(c)] = c.global_position
					if Net.is_puppet(c):
						puppets += 1
				report("look1", {"ids": _ids(), "puppets": puppets, "pos": pos})
			"cast":
				_cast_here("chicken", cmd["at"])
				report("cast", true)
			"look2":
				var want: Array = cmd["ids"]
				await until(func() -> bool: return want.all(func(id: int) -> bool: return NetRegistry.node(id) is Chicken), 6.0)
				var shown := 0
				var own := 0
				for c in _chickens():
					if want.has(NetFloor.id_of(c)) and Net.is_puppet(c):
						shown += 1
					if not Net.is_copy(c):
						own += 1
				report("look2", {"shown": shown, "own": own})
			"hit":
				var c := NetRegistry.node(int(cmd["id"])) as Chicken
				if c != null:
					c.apply_damage(5.0, my_hero())   # (a copy: Net.route_hit, a request to the host)
					await sleep(0.4)
					if is_instance_valid(c) and not c.dead:
						c.apply_damage(5.0, my_hero())
				await until(func() -> bool: return c == null or not is_instance_valid(c) or c.dead, 4.0)
				report("hit", {"dead": c == null or not is_instance_valid(c) or c.dead})
			"gone":
				await until(func() -> bool: return _chickens().is_empty(), 4.0)
				report("gone", {"left": _chickens().size()})
			"end":
				report("end", {"guard": Net.guard_hits.size(), "entries": int(Session.world.stats["in_entries"])})
				running = false
			_:
				running = false


# --- Helpers ---------------------------------------------------------------------------------------------------

func _chickens() -> Array[Chicken]:
	var out: Array[Chicken] = []
	for n in get_tree().get_nodes_in_group(Chicken.GROUP):
		var c := n as Chicken
		if c != null and not c.dead and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _ids() -> Array:
	var out: Array = []
	for c in _chickens():
		out.append(NetFloor.id_of(c))
	out.sort()
	return out


func _cast_here(spell: String, at: Vector3) -> void:
	var c := game.get("controller") as PlayerController
	my_hero()._ready_at.clear()   # (no cooldowns in the way)
	c.aim_override = at
	check(c.cast_spell(spell, 1.0), "%s cast %s" % [Session.player_name, spell])
	c.aim_override = Vector3.INF


## Host: the floor's monsters and hellgates stand still (the chickens peck them; nothing should hurt anyone).
func _freeze_world() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster or n is Hellgate:
			n.set_physics_process(false)


## Walkable floor about `dist` from `p` (the first of eight directions that has it), level with it.
func _open_spot(p: Vector3, dist: float) -> Vector3:
	var map := game.get("map") as HexMap
	for k in 8:
		var a := TAU * float(k) / 8.0
		var q := p + Vector3(cos(a), 0.0, sin(a)) * dist
		if map.is_walkable_cell(Hex.from_world(q)) and not map.blocks_point(q, 0.6) and absf(map.ground_height(q) - p.y) < 0.6:
			return Vector3(q.x, map.ground_height(q), q.z)
	return p
