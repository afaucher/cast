extends NetGameTest
## The grimoire online (docs/design/haunted-build-plan.md, "H6 as built"), three processes, `off` and `coast`. Board 9's second
## offer is a haunted mansion (the estate heir); the crew starts on its last floor, where the grimoire stands in the story's
## room. It is a hellgate in shape: the GATE entry of the stream (HP, awake, phase, flare), world.spawn for its bursts,
## world.phase / world.shove for a phase change, world.die when it closes and world.burn after it when it closed on fire. The
## host stills the floor's monsters and holds its AI seats; the grimoire under test runs.
## - DORMANT: c1 shows it asleep (the shut book, the eye alive);
## - A BURST: the host wakes it and a burst lands; c1 shows it awake (the book open) and the risen dead it brought;
## - A PHASE: the host hits it to 60 %; c1 shows phase 1 (the book weakened) at the host's HP;
## - THE LATE JOINER: c2 joins and shows it awake in phase 1, the book weakened, at the host's HP, with its spawns;
## - BURNED: the host sets it alight and the fire finishes it; c1 and c2 show it closed, the book shut and charred, the eye
##   dead, its spawns stopped, the Ledger's "Grimoire burned" line mirrored and the floor's objective met;
## - nothing tripped the OWNER-write guard on any machine.

const PEERS := 3
const SEED := 9
const CONTRACT := 1
const JOINER_SPELLS := ["tentacles", "teeth"]
const HP_SLACK := 1.0


func run_host() -> void:
	net_timeout = 170.0
	clear_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	make_game({"spells": "coffee,fireball", "seed": SEED, "contract": CONTRACT, "net_wait": 2, "floor": 3})
	if not check(await wait_floor(45.0), "floor 3 starts") or not await wait_sync():
		return
	(game.get("opts") as Dictionary).erase("net_wait")
	var run: ContractRun = game.get("_run")
	if not check(run != null and run.has_grimoire(), "a haunted contract"):
		return
	var site: SiteBuilder.Site = game.get("_site")
	var g := site.grimoire
	if not check(g != null and not g.is_active(), "its last floor has its grimoire, asleep"):
		return
	g.set_physics_process(false)   # (asleep until the test wakes it: no hero wanders near first)
	_still_world()
	for seat in [1, 2, 3]:
		var h := hero_at(seat)
		if h != null:
			h.set_modifier("test_ward", 0.0, 999.0)
	var gid := NetFloor.id_of(g)
	check(await wait_reports("ready", 1, 30.0), "c1 is on the floor")
	await sleep(1.5)

	# 1. Dormant.
	command(c1(), "look", {"id": gid, "tag": "asleep"})
	if check(await wait_reports("asleep", 1, 10.0), "c1 looked"):
		var r: Dictionary = reported(c1(), "asleep")
		check(bool(r["valid"]) and not bool(r["active"]) and str(r["state"]) == "dormant" and bool(r["eye"]), "c1: asleep, the book shut, the eye alive")

	# 2. A burst.
	g.activate()
	var burst := g.spawn_burst_now()
	check(not burst.is_empty(), "the host's burst (%d)" % burst.size())
	for m in burst:
		m.set_physics_process(false)
	await sleep(1.5)
	command(c1(), "look", {"id": gid, "tag": "awake"})
	if check(await wait_reports("awake", 1, 10.0), "c1 looked after the burst"):
		var r: Dictionary = reported(c1(), "awake")
		check(bool(r["active"]) and str(r["state"]) == "open", "c1: awake, the book open")
		eq(int(r["spawns"]), burst.size(), "c1: the dead it brought, from it")

	# 3. A phase.
	g.apply_damage(g.max_hp * 0.4, my_hero())
	eq(g.phase, 1, "phase 1 on the host")
	await sleep(1.5)
	command(c1(), "look", {"id": gid, "tag": "phase"})
	if check(await wait_reports("phase", 1, 10.0), "c1 looked after the phase"):
		var r: Dictionary = reported(c1(), "phase")
		eq(int(r["phase"]), 1, "c1: phase 1")
		eq(str(r["state"]), "weakened", "c1: the book weakened")
		near(float(r["hp"]), g.hp, HP_SLACK, "c1: the host's HP")

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
	command(c2, "look", {"id": gid, "tag": "joined"})
	if check(await wait_reports("joined", 1, 10.0), "c2 looked"):
		var r: Dictionary = reported(c2, "joined")
		check(bool(r["active"]) and not bool(r["dead"]), "c2: awake")
		eq(int(r["phase"]), 1, "c2: phase 1")
		eq(str(r["state"]), "weakened", "c2: the book weakened")
		near(float(r["hp"]), g.hp, HP_SLACK, "c2: the host's HP")
		check(int(r["spawns"]) >= 1, "c2: its spawns (%d)" % int(r["spawns"]))

	# 5. Burned.
	var lines0 := _lines("Grimoire burned")
	Burning.ignite(g, my_hero(), Grimoire.FIRE_SECONDS)
	g.apply_damage(g.hp - 4.0, my_hero())
	if not check(await until(func() -> bool: return g.dead, 5.0), "the fire finishes it on the host"):
		return
	check(g.burnt and g.book.burnt, "burned on the host")
	eq(_lines("Grimoire burned"), lines0 + 1, "the host's Ledger line")
	await sleep(1.5)
	for p in [c1(), c2]:
		command(p, "look", {"id": gid, "tag": "burned"})
	if check(await wait_reports("burned", 2, 10.0), "c1 and c2 looked after it closed"):
		for p in [c1(), c2]:
			var who := "c1" if p == c1() else "c2"
			var r: Dictionary = reported(p, "burned")
			check(bool(r["valid"]) and bool(r["dead"]), "%s: closed (the shut book stays)" % who)
			check(str(r["state"]) == "shut" and bool(r["burnt"]) and not bool(r["eye"]), "%s: the book shut and charred, the eye dead" % who)
			check(bool(r["stopped"]), "%s: its spawns stopped" % who)
			eq(int(r["lines"]), lines0 + 1, "%s's Ledger mirrors the grimoire's line" % who)
			eq(str(r["closed"]), "burned", "%s: the floor's objective met (burned)" % who)

	command(c2, "end")
	command(c1(), "end")
	check(await wait_reports("end", 2, 10.0), "the clients are done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	for p in [c1(), c2]:
		eq(int((reported(p, "end") as Dictionary)["guard"]), 0, "... nor on %s" % ("c1" if p == c1() else "c2"))
	print("[grimoire] world: %d spawns, %d deaths, %d burns sent" % [int(Session.world.stats.get("spawns", 0)), int(Session.world.stats.get("deaths", 0)), int(Session.world.stats.get("burns", 0))])
	clear_flag("join")


func run_client() -> void:
	net_timeout = 170.0
	if index == 2:
		await _late_joiner()
		return
	if not check(await connect_client() == "", "joined"):
		return
	make_game({"spells": "coffee,fireball", "floor": 3})
	if not check(await wait_floor(45.0), "the floor starts here") or not await wait_sync():
		return
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
				var g := NetRegistry.node(int(cmd["id"])) as Grimoire
				var valid := g != null and is_instance_valid(g) and g.is_inside_tree()
				var spawns := 0
				for id in NetRegistry.ids():
					var m := NetRegistry.node(id) as Monster
					if valid and m != null and not m.dead and m.get_meta("from_gate", null) == g:
						spawns += 1
				var iris: Node3D = g.book.find_child("Iris", true, false) as Node3D if valid and g.book != null else null
				var sess: ContractSession = game.get("_session")
				report(str(cmd["tag"]), {
					"valid": valid, "dead": valid and g.dead, "active": valid and g.is_active(), "phase": g.phase if valid else -1,
					"hp": g.hp if valid else -1.0, "state": g.book.state if valid and g.book != null else "",
					"burnt": valid and g.book != null and g.book.burnt, "eye": iris != null and iris.visible,
					"spawns": spawns, "stopped": HellgateEvents.spawns_are_stopped(), "lines": _lines("Grimoire burned"),
					"closed": str(sess.state().get("grimoire_closed", "")) if sess != null else "",
				})
			"end":
				report("end", {"guard": Net.guard_hits.size()})
				running = false
			_:
				running = false


# --- Helpers ---------------------------------------------------------------------------------------------------

func c1() -> int:
	return peer_named("c1")


func _lines(label: String) -> int:
	return Ledger.lines.filter(func(l: Dictionary) -> bool: return str(l.get("label", "")) == label).size()


## The floor's monsters stand still and the AI seats hold (the grimoire is driven by the test).
func _still_world() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster:
			n.set_physics_process(false)
	for seat in [2, 3]:
		var h := hero_at(seat)
		if h == null:
			continue
		var brain := h.get_node_or_null("AllyBrain")
		if brain != null:
			brain.set_physics_process(false)
