extends NetGameTest
## The procession online (docs/design/haunted-build-plan.md, "H4 as built"), three processes, `off` and `coast`. Board 9's
## second offer is a haunted mansion (the estate heir); its floor 1 has one procession (an acolyte, four zombies, a rear
## acolyte). The procession is the host's: its route and file are PRIVATE, its members are host monsters on the stream, a raise
## is the acolyte's wind-up (world.windup) and the body's world.rise. The host turns its members' senses off (they walk past
## the crew) and stills everything else.
## - THE WALK: c1 shows every member where the host has it, puppets, and walking (two looks apart);
## - THE RAISE: the host drops the file's last zombie; the rear acolyte raises it on the host; c1 shows the acolyte in its
##   gesture (the telegraph, arms up) while it raises, then the zombie standing again, streamed, and walking with the file;
## - THE KILL: the host kills the leader; c1 shows it gone and its Ledger mirrors the host's "Acolyte stopped" line;
## - THE LATE JOINER: c2 joins and shows the living members where the host has them (the raised one standing), the dead
##   leader gone;
## - nothing tripped the OWNER-write guard on any machine.

const PEERS := 3
const SEED := 9
const CONTRACT := 1
const JOINER_SPELLS := ["tentacles", "teeth"]
const NEAR := 1.6                   ## a moving member on a client is this close to where the host has it (the stream's delay)


func run_host() -> void:
	net_timeout = 170.0
	clear_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	make_game({"spells": "coffee,fireball", "seed": SEED, "contract": CONTRACT, "net_wait": 2})
	if not check(await wait_floor(45.0), "floor 1 starts") or not await wait_sync():
		return
	(game.get("opts") as Dictionary).erase("net_wait")
	var run: ContractRun = game.get("_run")
	if not check(run != null and run.family == ClientArchetype.FAMILY_DEAD and run.acolytes_on(1) == 2, "a haunted contract with a procession on floor 1"):
		return
	var site: SiteBuilder.Site = game.get("_site")
	if not check(site.processions.size() == 1, "floor 1 has its procession"):
		return
	var pr: Procession = site.processions[0]
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	_still_world(pr)
	ProcessionDev._trace(game, pr)   # (the file in the host's log)
	var lead := pr.acolytes[0]
	var rear := pr.acolytes[1]
	var ids: Array = []
	for m in pr.acolytes + pr.zombies:
		ids.append(NetFloor.id_of(m))
	check(await wait_reports("ready", 1, 30.0), "c1 is on the floor")
	await sleep(2.0)

	# 1. The walk: c1 shows every member where the host has it, and moving.
	command(c1(), "look", {"ids": ids, "tag": "walk1"})
	check(await wait_reports("walk1", 1, 10.0), "c1 looked at the procession")
	var w1 := _host_view(ids)
	await sleep(2.0)
	command(c1(), "look", {"ids": ids, "tag": "walk2"})
	if check(await wait_reports("walk2", 1, 10.0), "c1 looked again"):
		var a: Dictionary = reported(c1(), "walk1")
		var b: Dictionary = reported(c1(), "walk2")
		var w2 := _host_view(ids)
		for id: int in ids:
			check(bool(b[id]["valid"]) and not bool(b[id]["dead"]) and bool(b[id]["puppet"]), "c1: member %d a living puppet" % id)
			check(_flat(b[id]["pos"], w2[id]) < NEAR, "c1: member %d where the host has it (%.2f off)" % [id, _flat(b[id]["pos"], w2[id])])
		check(_flat(b[ids[0]]["pos"], a[ids[0]]["pos"]) > 1.0, "c1: the leader walks (%.2f)" % _flat(b[ids[0]]["pos"], a[ids[0]]["pos"]))
		check(_flat(w2[ids[0]], w1[ids[0]]) > 1.0, "... as on the host")

	# 2. The raise: the file's last zombie drops; the rear acolyte raises it.
	var z: Zombie = pr.zombies[pr.zombies.size() - 1]
	var zid := NetFloor.id_of(z)
	var rises0 := int(Session.world.stats.get("rises", 0))
	z.die()
	var near_hero := INF
	for h in GameWorld.team_actors(GameWorld.TEAM_HEROES):
		near_hero = minf(near_hero, GameWorld.flat_distance(h.global_position, z.global_position))
	if check(await until(func() -> bool: return rear.state == Monster.State.ATTACK and rear._telegraph > 0.45, 8.0), "the rear acolyte raises the body on the host (rear %.1f from it, a hero %.1f, downed %s, state %s)" % [
			GameWorld.flat_distance(rear.global_position, z.global_position), near_hero, z.is_downed(), rear.state_name()]):
		command(c1(), "look", {"ids": [NetFloor.id_of(rear), zid], "tag": "raising"})
		if check(await wait_reports("raising", 1, 10.0), "c1 looked during the raise"):
			var r: Dictionary = reported(c1(), "raising")
			var ra: Dictionary = r[NetFloor.id_of(rear)]
			check(int(ra["state"]) == Monster.State.ATTACK and float(ra["arms"]) > 0.5, "c1 shows the acolyte's gesture (state %d, arms %.2f)" % [int(ra["state"]), float(ra["arms"])])
	check(await until(func() -> bool: return not z.dead, 6.0), "the body stood up on the host")
	check(int(Session.world.stats.get("rises", 0)) > rises0, "the host sent world.rise")
	check(pr.zombies.has(z), "... and it joined the file")
	await sleep(Zombie.RISE_TIME + 2.5)
	command(c1(), "look", {"ids": [zid], "tag": "raised"})
	if check(await wait_reports("raised", 1, 10.0), "c1 looked at the raised zombie"):
		var r: Dictionary = reported(c1(), "raised")[zid]
		check(not bool(r["dead"]) and not bool(r["lying"]) and bool(r["puppet"]), "c1 shows it standing again, a puppet")
		eq(int(r["raises"]), 1, "c1 showed it rise once")
		check(_flat(r["pos"], z.global_position) < NEAR, "... with the file, where the host has it (%.2f off)" % _flat(r["pos"], z.global_position))

	# 3. The kill: the host's leader dies (paid), c1 shows it gone and the line.
	lead.die()
	await sleep(1.5)
	var paid := Ledger.lines.filter(func(l: Dictionary) -> bool: return str(l.get("label", "")) == "Acolyte stopped").size()
	eq(paid, 1, "the host paid the acolyte")
	command(c1(), "look", {"ids": [ids[0]], "tag": "killed"})
	if check(await wait_reports("killed", 1, 10.0), "c1 looked at the leader"):
		var r: Dictionary = reported(c1(), "killed")[ids[0]]
		check(not bool(r["valid"]) or bool(r["dead"]), "c1 shows the leader gone")
		eq(int(r["paid"]), 1, "c1's Ledger mirrors the acolyte line")

	# 4. The late joiner.
	raise_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 30.0), "c2 joins the crew on the job"):
		return
	var c2 := peer_named("c2")
	if not check(await wait_reports("checkout", 1, 30.0), "c2 opened its license checkout"):
		return
	command(c2, "sign", {"spells": JOINER_SPELLS})
	if not check(await wait_reports("arrived", 1, 40.0), "c2 arrived"):
		return
	await sleep(1.5)
	command(c2, "look", {"ids": ids, "tag": "joined"})
	if check(await wait_reports("joined", 1, 10.0), "c2 looked"):
		var r: Dictionary = reported(c2, "joined")
		var w := _host_view(ids)
		check(not bool(r[ids[0]]["valid"]) or bool(r[ids[0]]["dead"]), "c2: the dead leader gone")
		for id: int in ids.slice(1):
			check(bool(r[id]["valid"]) and not bool(r[id]["dead"]) and bool(r[id]["puppet"]), "c2: member %d a living puppet" % id)
			check(_flat(r[id]["pos"], w[id]) < NEAR, "c2: member %d where the host has it (%.2f off)" % [id, _flat(r[id]["pos"], w[id])])
		check(not bool(r[zid]["lying"]), "c2: the raised zombie standing")

	command(c2, "end")
	command(c1(), "end")
	check(await wait_reports("end", 2, 10.0), "the clients are done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	for p in [c1(), c2]:
		eq(int((reported(p, "end") as Dictionary)["guard"]), 0, "... nor on %s" % ("c1" if p == c1() else "c2"))
	print("[procession] world: %d windups, %d rises, %d deaths sent" % [int(Session.world.stats.get("windups", 0)), int(Session.world.stats.get("rises", 0)), int(Session.world.stats.get("deaths", 0))])
	clear_flag("join")


func run_client() -> void:
	net_timeout = 170.0
	if index == 2:
		await _late_joiner()
		return
	if not check(await connect_client() == "", "joined"):
		return
	make_game({"spells": "coffee,fireball"})
	if not check(await wait_floor(45.0), "the floor starts here") or not await wait_sync():
		return
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	report("ready", true)
	await _serve()


func _late_joiner() -> void:
	var since := Time.get_unix_time_from_system()
	if not check(await wait_flag("join", since, 140.0), "the host raised the join flag"):
		return
	if not check(await connect_client() == "", "joined the crew on the job"):
		return
	make_game({})
	if not check(await until(func() -> bool: return picker() != null, 30.0), "c2's license checkout opened"):
		return
	report("checkout", true)
	var sign_cmd := await wait_command(30.0)
	if not check(str(sign_cmd.get("cmd", "")) == "sign", "the host says sign"):
		return
	check(await sign_license(sign_cmd["spells"] as Array), "c2 signs")
	if not check(await until(func() -> bool: return Session.join.arrived, 40.0), "c2 arrived on the crew's floor"):
		return
	await wait_floor(10.0)
	report("arrived", true)
	await _serve()


func _serve() -> void:
	var running := true
	while running:
		var cmd := await wait_command(120.0)
		match str(cmd.get("cmd", "")):
			"look":
				var out := {}
				var paid := Ledger.lines.filter(func(l: Dictionary) -> bool: return str(l.get("label", "")) == "Acolyte stopped").size()
				for id: int in cmd["ids"]:
					var m := NetRegistry.node(id) as Monster
					var valid := m != null and is_instance_valid(m) and m.is_inside_tree()
					out[id] = {"valid": valid, "dead": valid and m.dead, "pos": m.global_position if valid else Vector3.INF,
						"puppet": valid and Net.is_puppet(m), "state": m.state if valid else -1,
						"arms": (m.model as AcolyteModel).raise_k() if valid and m.model is AcolyteModel else 0.0,
						"lying": valid and m.model is ZombieModel and (m.model as ZombieModel).is_lying(),
						"raises": int(m.get("raises")) if valid and m is Zombie else -1, "paid": paid}
				report(str(cmd["tag"]), out)
			"end":
				report("end", {"guard": Net.guard_hits.size()})
				running = false
			_:
				running = false


# --- Helpers ---------------------------------------------------------------------------------------------------

func c1() -> int:
	return peer_named("c1")


## The host's members where they stand now: id -> position.
func _host_view(ids: Array) -> Dictionary:
	var out := {}
	for id: int in ids:
		var n := NetRegistry.node(id) as Node3D
		out[id] = n.global_position if n != null and is_instance_valid(n) else Vector3.INF
	return out


## The procession walks with its senses off; every other monster, gate and AI seat stands still.
func _still_world(pr: Procession) -> void:
	var mine := pr.members()
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster and mine.has(n):
			(n as Monster).aggro_range = 0.0
		elif n is Monster or n is Hellgate:
			n.set_physics_process(false)
	for seat in [2, 3]:
		var h := hero_at(seat)
		if h == null:
			continue
		var brain := h.get_node_or_null("AllyBrain")
		if brain != null:
			brain.set_physics_process(false)


static func _flat(a: Variant, b: Variant) -> float:
	var v: Vector3 = a
	var w: Vector3 = b
	return Vector2(v.x - w.x, v.z - w.z).length()
