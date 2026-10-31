extends NetGameTest
## Ghosts online (docs/design/haunted-build-plan.md, "H5 networking" and "H5 as built"), three processes, `off` and `coast`.
## Board 9's second offer is a haunted mansion (the estate heir); its floor 1 has its ghosts in their hosts. Possession is one
## link each way (Wisp.host, HauntHost.ghost) on the host's machine, carried by world.haunt; a host's break is world.die (the
## armour's bill the host's Ledger line). The host stills everything but the ghost under test and its next host.
## - POSSESSION: c1 shows the ghost inside its host (hidden, out of every query) and the host possessed (awake, the ghost look);
## - THE BREAK: the host breaks the possessed host (its player's hero the culprit); c1 shows the host gone, the ghost out where
##   it fell, hurt, and its Ledger mirrors the armour's bill (a suit of armour is picked when the floor has a possessed one);
## - THE MOVE: the ghost flies to the next dormant host (moved near on the host) and gets in; c1 shows it inside that host,
##   which is possessed now, where the host has it;
## - THE LATE JOINER: c2 joins and shows the broken host gone, the ghost in its new host, that host possessed where the host
##   has it, the floor's other ghost still in its first host, a dormant host dormant;
## - nothing tripped the OWNER-write guard on any machine.

const PEERS := 3
const SEED := 9
const CONTRACT := 1
const JOINER_SPELLS := ["tentacles", "teeth"]
const NEAR := 1.2


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
	if not check(run != null and run.family == ClientArchetype.FAMILY_DEAD, "a haunted contract"):
		return
	var site: SiteBuilder.Site = game.get("_site")
	if not check(site.wisps.size() >= 2 and site.hosts.size() > site.wisps.size(), "floor 1 has its ghosts and dormant hosts (%d, %d)" % [site.wisps.size(), site.hosts.size()]):
		return
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	# the ghost under test: one in a suit of armour when there is one (its break bills), else the first
	var w: Wisp = site.wisps[0]
	for x in site.wisps:
		if x.host is ArmourHost:
			w = x
			break
	var other: Wisp = site.wisps[0] if w != site.wisps[0] else site.wisps[1]
	var a := w.host as HauntHost
	var b := _next_host(site, a)
	if not check(b != null, "a dormant host to move on to"):
		return
	_still_world([w, a, b])
	a.aggro_range = 0.0
	b.aggro_range = 0.0
	var dormant_c: HauntHost = null
	for h in site.hosts:
		if h != b and h.is_dormant():
			dormant_c = h
	var armour := a is ArmourHost   # (asked once: the host is freed after it breaks)
	var wid := NetFloor.id_of(w)
	var aid := NetFloor.id_of(a)
	var bid := NetFloor.id_of(b)
	var ids := [wid, aid, bid, NetFloor.id_of(other), NetFloor.id_of(other.host)]
	if dormant_c != null:
		ids.append(NetFloor.id_of(dormant_c))
	check(await wait_reports("ready", 1, 30.0), "c1 is on the floor")
	await sleep(2.0)

	# 1. Possession: c1 shows the ghost in its host.
	command(c1(), "look", {"ids": ids, "tag": "start"})
	if check(await wait_reports("start", 1, 10.0), "c1 looked"):
		var r: Dictionary = reported(c1(), "start")
		check(int(r[wid]["host"]) == aid and not bool(r[wid]["visible"]) and not bool(r[wid]["actor"]), "c1: the ghost in its host, hidden, out of the queries")
		check(int(r[aid]["ghost"]) == wid and bool(r[aid]["possessed_look"]), "c1: its host possessed, in the ghost look")
		check(int(r[bid]["ghost"]) == 0 and not bool(r[bid]["possessed_look"]), "c1: the next host dormant")

	# 2. The break: the host's player breaks the possessed host.
	var bill0 := _bills("Suit of armour")
	var at := a.global_position
	a.apply_damage(a.hp + 1.0, my_hero())
	check(a.dead and w.host == null and not w.dead, "the host broke on the host; the ghost is out")
	near(w.hp, Wisp.HP - Wisp.BREAK_HURT, 0.01, "the ghost is hurt by the break")
	if armour:
		eq(_bills("Suit of armour"), bill0 + 1, "the broken suit is billed on the host")
	await sleep(0.8)
	command(c1(), "look", {"ids": [wid, aid], "tag": "broke"})
	if check(await wait_reports("broke", 1, 10.0), "c1 looked after the break"):
		var r: Dictionary = reported(c1(), "broke")
		check(not bool(r[aid]["valid"]) or bool(r[aid]["dead"]), "c1: the broken host gone")
		check(int(r[wid]["host"]) == 0 and bool(r[wid]["actor"]), "c1: the ghost out in the open (in the queries: it can be hit)")
		check(_flat(r[wid]["pos"], w.global_position) < NEAR + 0.8 and _flat(r[wid]["pos"], at) < 6.0, "c1: where the host has it (%.2f off)" % _flat(r[wid]["pos"], w.global_position))
		near(float(r[wid]["hp"]), Wisp.HP - Wisp.BREAK_HURT, 0.2, "c1: the ghost hurt")
		if armour:
			eq(int(r[wid]["bills"]), bill0 + 1, "c1's Ledger mirrors the suit's bill")

	# 3. The move: it flies to the next host and gets in.
	if check(await until(func() -> bool: return w.host == b, 20.0), "the ghost got into the next host on the host (%.1f away)" % GameWorld.flat_distance(w.global_position, b.global_position)):
		check(b.is_possessed() and b.ghost == w, "that host is possessed on the host")
		await sleep(1.0)
		command(c1(), "look", {"ids": [wid, bid], "tag": "moved"})
		if check(await wait_reports("moved", 1, 10.0), "c1 looked after the move"):
			var r: Dictionary = reported(c1(), "moved")
			check(int(r[wid]["host"]) == bid and not bool(r[wid]["visible"]), "c1: the ghost in its new host")
			check(int(r[bid]["ghost"]) == wid and bool(r[bid]["possessed_look"]), "c1: the new host possessed")
			check(_flat(r[bid]["pos"], b.global_position) < NEAR, "c1: the host where the host has it")

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
		check(not bool(r[aid]["valid"]) or bool(r[aid]["dead"]), "c2: the broken host gone")
		check(int(r[wid]["host"]) == bid and not bool(r[wid]["visible"]) and not bool(r[wid]["actor"]), "c2: the ghost in its new host")
		check(int(r[bid]["ghost"]) == wid and bool(r[bid]["possessed_look"]), "c2: that host possessed")
		check(_flat(r[bid]["pos"], b.global_position) < NEAR, "c2: where the host has it (%.2f off)" % _flat(r[bid]["pos"], b.global_position))
		var oid := NetFloor.id_of(other)
		check(int(r[oid]["host"]) == NetFloor.id_of(other.host) and not bool(r[oid]["visible"]), "c2: the other ghost still in its first host")
		if dormant_c != null:
			check(int(r[NetFloor.id_of(dormant_c)]["ghost"]) == 0 and not bool(r[NetFloor.id_of(dormant_c)]["possessed_look"]), "c2: a dormant host dormant")
		if armour:
			eq(int(r[wid]["bills"]), bill0 + 1, "c2's Ledger has the suit's bill")

	command(c2, "end")
	command(c1(), "end")
	check(await wait_reports("end", 2, 10.0), "the clients are done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	for p in [c1(), c2]:
		eq(int((reported(p, "end") as Dictionary)["guard"]), 0, "... nor on %s" % ("c1" if p == c1() else "c2"))
	print("[haunt] world: %d haunts, %d deaths sent" % [int(Session.world.stats.get("haunts", 0)), int(Session.world.stats.get("deaths", 0))])
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
				var bills := _bills("Suit of armour")
				for id: int in cmd["ids"]:
					var m := NetRegistry.node(id) as Monster
					var valid := m != null and is_instance_valid(m) and m.is_inside_tree() and not m.is_queued_for_deletion()
					var host: Variant = m.get("host") if valid else null
					var ghost: Variant = m.get("ghost") if valid else null
					var look := false
					if valid and m.model != null and m.model.has_method("is_ghost"):
						look = bool(m.model.call("is_ghost")) and bool(m.model.get("awake"))
					out[id] = {"valid": valid, "dead": valid and m.dead, "pos": m.global_position if valid else Vector3.INF,
						"visible": valid and m.visible, "actor": valid and m.is_in_group("actors"), "hp": m.hp if valid else -1.0,
						"host": NetFloor.id_of(host) if host != null and is_instance_valid(host) else 0,
						"ghost": NetFloor.id_of(ghost) if ghost != null and is_instance_valid(ghost) else 0,
						"possessed_look": look, "bills": bills}
				report(str(cmd["tag"]), out)
			"end":
				report("end", {"guard": Net.guard_hits.size()})
				running = false
			_:
				running = false


# --- Helpers ---------------------------------------------------------------------------------------------------

func c1() -> int:
	return peer_named("c1")


func _bills(label: String) -> int:
	return Ledger.lines.filter(func(l: Dictionary) -> bool: return str(l.get("kind", "")) == "damage" and str(l.get("label", "")) == label).size()


## The dormant host nearest `a`; when it is out of a ghost's reach it is moved near `a` (on the host: the stream carries it).
func _next_host(site: SiteBuilder.Site, a: HauntHost) -> HauntHost:
	var best: HauntHost = null
	var best_d := INF
	for h in site.hosts:
		if h == a or not h.is_dormant():
			continue
		var d := GameWorld.flat_distance(h.global_position, a.global_position)
		if d < best_d:
			best_d = d
			best = h
	if best == null:
		return null
	var map: HexMap = game.get("map")
	if best_d > Wisp.SEEK_RANGE - 2.0 or map.find_path(a.current_cell(), best.current_cell(), true, Wisp.SEEK_PATH).is_empty():
		for c in Hex.range_cells(a.current_cell(), 6):
			if Hex.distance(c, a.current_cell()) < 4 or not map.is_walkable_cell(c) or map.find_path(a.current_cell(), c, true, 400).is_empty():
				continue
			best.global_position = Hex.to_world(c, float(map.get_cell(c).level))
			best.reset_physics_interpolation()
			break
	return best


## Everything stands still but `keep` (the ghost under test, its host and the next one); the AI seats hold.
func _still_world(keep: Array) -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster and not keep.has(n):
			n.set_physics_process(false)
		elif n is Hellgate:
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
