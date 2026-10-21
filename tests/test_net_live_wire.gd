extends NetGameTest
## The live wire online (docs/design/sewer-concept.md, "Phase 2 as built"), three processes, `off` and `coast`, on the
## `--sewer 1` layout (L1 Reclamation run) in a crew: every process passes the flag, as run.ps1 -Crew passes it to every
## window, and the load barrier's checksum proves they built the same layout. The host and c1 play it; c2 joins later.
## - THE BREAK, THE HOST DECIDES: c1's hit on the electrical panel is a request; the host breaks it and bills it once
##   ("Electrical panel", $250, to c1's hero); obj.break carries the break's moment on the shared clock and the culprit;
## - THE SHOCK, A SCHEDULED EFFECT: every machine drops the cable and fires the shock and the pulses from that moment. c1's
##   wading hero is hit by c1's own machine (18 and a daze, then four pulses of 9: the soaked x1.5); the host applies
##   nothing to it and shows its HP as c1 has it. A host-owned monster and the AI hero wading in reach are hit by the host,
##   exactly once per shock (c1 resolves neither), each hit credited to c1's hero (the breaker). The cable lands, and the
##   first shock fires, at the same moment on both machines (within the clock's error);
## - THE LATE JOINER: c2 joins after the wire went dead and sees the broken panel and its cable lying dark in the water,
##   from the host's break moment, with every shock counted as past: none replays on its hero (it takes the AI's seat, in
##   the water within reach);
## - nothing tripped the OWNER-write guard on any machine.

const PEERS := 3
const SEED := 13
const CONTRACT := 1
const FLOOR := 2
const LAYOUT := 1
const JOINER_SPELLS := ["tentacles", "teeth"]
const SHOCKS := 1 + int(LiveWire.PULSE_FOR / LiveWire.PULSE_EVERY)


func run_host() -> void:
	net_timeout = 150.0
	follow_reloads = true
	clear_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	make_game({"spells": "heal,corn", "seed": SEED, "contract": CONTRACT, "net_wait": 2, "floor": FLOOR, "sewer": LAYOUT})
	if not check(await wait_floor(45.0), "floor %d (the --sewer %d layout) starts" % [FLOOR, LAYOUT]) or not await wait_sync():
		return
	eq(flow().desyncs, [], "every machine built the same layout (no desync at the barrier)")
	(game.get("opts") as Dictionary).erase("net_wait")
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	var site: SiteBuilder.Site = game.get("_site")
	var map := game.get("map") as HexMap
	var w := _wire(site)
	if not check(w != null, "the layout's electrical panel has its live wire"):
		return
	var panel := w.panel
	check(not Net.is_copy(panel), "the host owns the panel")
	# Everyone else holds still; a monster and the AI hero wade near where the cable lands.
	var spots := _water_spots(map, w.drop_cell, 3)
	if not check(spots.size() >= 3, "three water cells within 3 of the cable's landing (%d)" % spots.size()):
		return
	var mon: Monster = null
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster or n is Hellgate or n is Employee:
			n.set_physics_process(false)
			if mon == null and n is Monster and not (n is Gator) and not (n as Monster).dead and (n as Monster).max_hp >= 60.0:
				mon = n as Monster
	if not check(mon != null, "a host-owned monster to wade in reach"):
		return
	_put(mon, spots[1])
	var ai := hero_at(3)
	var brain := ai.get_node_or_null("AllyBrain")
	if brain != null:
		brain.set_physics_process(false)
	_put(ai, spots[2])
	_put(my_hero(), _dry_far(map, w.drop_point))
	var mon_hits: Array = []
	var ai_hits: Array = []
	mon.damaged.connect(func(amount: float, src: Node) -> void: mon_hits.append([amount, src]))
	ai.damaged.connect(func(amount: float, src: Node) -> void: ai_hits.append([amount, src]))
	check(await wait_reports("ready", 1, 30.0), "c1 is on the floor")
	command(c1(), "stand", {"at": spots[0]})
	check(await wait_reports("stood", 1, 10.0), "c1 wades in reach of the cable's landing")
	await sleep(0.6)

	# The break: c1's hit, the host's decision.
	var lines_before := Ledger.lines.size()
	command(c1(), "break", {"id": NetFloor.id_of(panel), "wire": true})
	check(await until(func() -> bool: return panel.dead, 6.0), "c1's hit broke the panel on the host")
	var host_broke := _shared_t(w.broke_at)
	var first := [-1.0]
	check(await until(func() -> bool:
		if first[0] < 0.0 and w.shocks >= 1:
			first[0] = Session.host_time()
		return w.shocks >= SHOCKS, LiveWire.DROP_T + LiveWire.PULSE_FOR + 3.0), "the host's wire fired the shock and its pulses (%d)" % w.shocks)
	var bills := 0
	for line: Dictionary in Ledger.lines.slice(lines_before):
		if str(line["label"]) == panel.display_name:
			bills += 1
			eq(int(line["amount"]), 250, "the break bills the panel's price ($250)")
			eq(str(line["who"]), hero_at(2).display_name, "... to c1's hero")
	eq(bills, 1, "the panel is billed once")
	eq(mon_hits.size(), SHOCKS, "the wading monster was hit once per shock, by the host alone (%s)" % str(mon_hits.map(func(h: Array) -> float: return h[0])))
	eq(ai_hits.size(), SHOCKS, "... and the wading AI hero (%s)" % str(ai_hits.map(func(h: Array) -> float: return h[0])))
	if not mon_hits.is_empty():
		check(mon_hits.all(func(h: Array) -> bool: return h[1] == hero_at(2)), "every hit on them is credited to c1's hero, the breaker")
	if check(await wait_reports("break", 1, 15.0), "c1 reports the shock"):
		var r: Dictionary = reported(c1(), "break")
		print("[wire] c1: %s; host broke %.3f, first shock %.3f" % [str(r), host_broke, first[0]])
		var hits: Array = r["hits"]
		eq(hits.size(), SHOCKS, "c1's hero was hit once per shock, by its own machine")
		if not hits.is_empty():
			near(float(hits[0]), LiveWire.SHOCK_DAMAGE * LiveWire.SOAKED_MULT, 0.05, "the shock: 18 on the soaked wader")
			check(hits.slice(1).all(func(h: float) -> bool: return absf(h - LiveWire.PULSE_DAMAGE * LiveWire.SOAKED_MULT) < 0.05), "... then pulses of 9")
		check(bool(r["dazed"]), "c1's hero was dazed by the shock")
		near(float(r["broke"]), host_broke, 0.08, "c1's cable drops from the host's break moment (host %.3f, c1 %.3f)" % [host_broke, float(r["broke"])])
		near(float(r["first"]), first[0], 0.1, "... and the first shock lands at the same moment (host %.3f, c1 %.3f)" % [first[0], float(r["first"])])
		eq(str(r["ledger"]), ledger_text(), "c1's Ledger is the host's, line for line")
		await sleep(0.5)
		near(hero_at(2).hp, float(r["hp"]), 0.6, "the host shows c1's hero's HP as c1 has it (it applied none of the shocks)")
	await until(func() -> bool: return not w.is_live(), 3.0)

	# The late joiner: the dead wire, nothing replayed.
	raise_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 30.0), "c2 joins the crew on the job"):
		return
	var c2 := peer_named("c2")
	if not check(await wait_reports("checkout", 1, 30.0), "c2 opened its license checkout"):
		return
	command(c2, "sign", {"spells": JOINER_SPELLS})
	if not check(await wait_reports("arrived", 1, 40.0), "c2 arrived"):
		return
	command(c2, "wire", {"id": NetFloor.id_of(panel)})
	if check(await wait_reports("wire", 1, 15.0), "c2 reports the wire"):
		var jr: Dictionary = reported(c2, "wire")
		print("[wire] c2: %s" % str(jr))
		check(bool(jr["broken"]), "c2: the panel is broken")
		near(float(jr["broke"]), host_broke, 0.15, "c2: its wire runs from the host's break moment (host %.3f, c2 %.3f)" % [host_broke, float(jr["broke"])])
		eq(int(jr["shocks"]), SHOCKS, "c2: every shock counted as past")
		check(not bool(jr["live"]) and not bool(jr["running"]), "c2: the wire is dead")
		check(bool(jr["down"]), "c2: the cable lies in the water")
		check(bool(jr["wading"]), "c2's hero stands in the water within reach (the AI's spot)")
		near(float(jr["lost"]), 0.0, 0.01, "c2's hero took nothing: no shock replayed")
		eq(str(jr["ledger"]), ledger_text(), "c2's Ledger is the host's (the panel's line)")
	command(c2, "end")
	command(c1(), "end")
	check(await wait_reports("end", 2, 10.0), "the clients are done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	for p in [c1(), c2]:
		eq(int((reported(p, "end") as Dictionary)["guard"]), 0, "... nor on %s" % ("c1" if p == c1() else "c2"))


func run_client() -> void:
	net_timeout = 150.0
	follow_reloads = true
	if index == 2:
		await _late_joiner()
		return
	if not check(await connect_client() == "", "joined"):
		return
	make_game({"spells": "heal,corn", "floor": FLOOR, "sewer": LAYOUT})
	if not check(await wait_floor(45.0), "the floor starts here") or not await wait_sync():
		return
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(90.0)
		match str(cmd.get("cmd", "")):
			"stand":
				_put(my_hero(), cmd["at"])
				await sleep(0.3)
				report("stood", true)
			"break":
				var panel := NetRegistry.node(int(cmd["id"])) as PricedProp
				var w := panel.get_node_or_null("LiveWire") as LiveWire
				var hits: Array = []
				var last := [my_hero().hp]
				var first := [-1.0]
				var dazed := [false]
				panel.apply_damage(5.0, my_hero())   # (a copy: obj.req hit; the host breaks it)
				var t_end := wall() + LiveWire.DROP_T + LiveWire.PULSE_FOR + 4.0
				while wall() < t_end and (w == null or w.shocks < SHOCKS or hits.size() < SHOCKS):
					await get_tree().process_frame
					if my_hero().hp < last[0] - 0.01:
						hits.append(last[0] - my_hero().hp)
						if first[0] < 0.0:
							first[0] = Session.host_time()
							dazed[0] = my_hero().is_dazed()
					last[0] = my_hero().hp
				await sleep(0.3)
				report("break", {"hits": hits, "first": first[0], "dazed": dazed[0], "hp": my_hero().hp,
					"broke": _shared_t(w.broke_at) if w != null else -1.0, "ledger": ledger_text()})
			"end":
				report("end", {"guard": Net.guard_hits.size()})
				running = false
			_:
				running = false


## c2: join the crew on the job and report the wire it finds.
func _late_joiner() -> void:
	var since := Time.get_unix_time_from_system()
	if not check(await wait_flag("join", since, 110.0), "the host raised the join flag"):
		return
	if not check(await connect_client() == "", "joined the crew on the job"):
		return
	make_game({"sewer": LAYOUT})
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
	var hp := my_hero().hp
	report("arrived", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"wire":
				await sleep(1.5)
				var panel := NetRegistry.node(int(cmd["id"])) as PricedProp
				var w := panel.get_node_or_null("LiveWire") as LiveWire if panel != null else null
				var map := game.get("map") as HexMap
				var down := false
				if w != null and not w._links.is_empty():
					var end_link := w._links[w._links.size() - 1]
					down = end_link.visible and _flat(end_link.global_position, w.drop_point) < 0.8
				report("wire", {"broken": panel != null and panel.dead, "broke": _shared_t(w.broke_at) if w != null else -1.0,
					"shocks": w.shocks if w != null else -1, "live": w != null and w.is_live(), "running": w != null and w.is_physics_processing(),
					"down": down, "lost": hp - my_hero().hp, "ledger": ledger_text(),
					"wading": map.water_at(my_hero().global_position) and w != null and Hex.distance(my_hero().current_cell(), w.drop_cell) <= LiveWire.REACH_CELLS})
			"end":
				report("end", {"guard": Net.guard_hits.size()})
				running = false
			_:
				running = false


func c1() -> int:
	return peer_named("c1")


## A GameWorld.time on this machine as a time on the shared clock.
static func _shared_t(t: float) -> float:
	return Session.host_time() - (GameWorld.time - t)


## The live wire on the floor's (first) electrical panel.
static func _wire(site: SiteBuilder.Site) -> LiveWire:
	for p in site.props:
		var pp := p as PricedProp
		if pp != null and pp.kind == "electrical_panel" and pp.get_node_or_null("LiveWire") != null:
			return pp.get_node("LiveWire") as LiveWire
	return null


## Walkable water cells within `reach` of `c`, nearest first (world points on their floor).
static func _water_spots(map: HexMap, c: Vector2i, reach: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for d in range(0, reach + 1):
		for n in Hex.range_cells(c, d):
			if Hex.distance(n, c) != d or not map.is_walkable_cell(n):
				continue
			var lv := map.ground_level(Hex.to_world(n))
			var p := Hex.to_world(n, 0.0 if is_nan(lv) else lv)
			if map.water_at(p):
				out.append(p)
	return out


## Dry open floor well out of the wire's reach.
static func _dry_far(map: HexMap, from: Vector3) -> Vector3:
	var cells: Array = map.cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		if not map.is_walkable_cell(c) or map.is_pool_cell(c):
			continue
		var w := Hex.to_world(c)
		if GameWorld.flat_distance(w, from) < 16.0 or map.water_at(w):
			continue
		var lv := map.ground_level(w)
		return Hex.to_world(c, 0.0 if is_nan(lv) else lv)
	return from


func _put(a: Actor, at: Vector3) -> void:
	a.global_position = at
	a.snap_to_ground()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
