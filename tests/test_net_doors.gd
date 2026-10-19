extends NetGameTest
## Office doors online (OfficeDoor, NetObjects "DOORS"; docs/design/exploration.md "Decisions: map information, fog and doors"),
## three processes, `off` and `coast`. The host and c1 start floor 1 of a contract whose floor has three doors (A, B, C, in
## net-id order); the floor's monsters and the AI ally stand still, so only the test opens doors.
## - A CLIENT OPENS A DOOR: c1's hero walks into shut door A from the hall. Its push is a request; the host decides, its
##   copy opens (swinging away from c1's hero, into the room) and c1's copy opens the same way; c1's hero walks through.
## - A HOST'S MONSTER OPENS ONE: a monster walks into shut door B on the host; it stops (MONSTER_DELAY) and opens it, and c1
##   sees door B open the same way.
## - A BRUTE SMASH IS BILLED ONCE: a brute spawned in door C's hall chases the host's hero standing in the room behind it
##   and smashes the door: broken on both machines, one "Office door" Ledger line on the host, and c1's mirrored Ledger is
##   the host's line for line.
## - The host shuts door A again (E); c1 sees it shut.
## - A LATE JOINER SEES THE RIGHT DOOR STATES: c2 joins the running crew and takes the AI's seat; every door on its floor
##   is [shut, swing, broken] as on the host (A shut, B open, C broken), and so is every door on c1's.
## - nothing tripped the OWNER-write guard on any machine.

const PEERS := 3
const SEED := 13          ## floor 1 of contract 1 has three doors
const JOINER_SPELLS := ["tentacles", "teeth"]


func run_host() -> void:
	net_timeout = 110.0
	clear_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	make_game({"spells": "heal,corn", "seed": SEED, "contract": 1, "net_wait": 2})
	if not check(await wait_floor(45.0), "floor 1 starts") or not await wait_sync():
		return
	(game.get("opts") as Dictionary).erase("net_wait")
	_still()
	var c1 := peer_named("c1")
	check(await wait_reports("ready", 1, 30.0), "c1 is on the floor")
	var doors := _doors()
	if not check(doors.size() >= 3, "the floor has three doors (%d)" % doors.size()):
		return
	var da := doors[0]
	var db := doors[1]
	var dc := doors[2]
	for d in doors:
		check(d.shut and not d.broken, "door %d starts shut" % NetFloor.id_of(d))
	print("[DOORS] ids %s" % str(doors.map(func(d: OfficeDoor) -> int: return NetFloor.id_of(d))))

	# 1. c1's hero walks into door A from the hall.
	var reqs0 := int(Session.objects.stats.get("door_reqs", 0))
	command(c1, "push", {"id": NetFloor.id_of(da)})
	check(await until(func() -> bool: return not da.shut, 8.0), "the host opened door A for c1's push")
	check(int(Session.objects.stats.get("door_reqs", 0)) > reqs0, "... on c1's request (%d)" % (int(Session.objects.stats.get("door_reqs", 0)) - reqs0))
	eq(da.swing, -1, "... swinging away from c1's hero (into the room)")
	if not check(await wait_reports("pushed", 1, 20.0), "c1 reports its push"):
		return
	var r: Dictionary = reported(c1, "pushed")
	check(bool(r["opened"]), "c1's copy of door A opened")
	eq(int(r["swing"]), da.swing, "... the same way as the host's")
	check(bool(r["through"]), "c1's hero walked through door A")
	print("[DOORS] c1's push: open on c1 %.0f ms after it walked into the door" % (float(r["ms"])))

	# 2. A host monster walks into door B from the hall.
	var m := _a_monster()
	if not check(m != null, "a monster to walk into door B"):
		return
	var opened_b := await _monster_walks_in(m, db)
	check(opened_b, "the monster opened door B")
	eq(db.swing, -1, "... swinging away from it (into the room)")
	command(c1, "watch", {"id": NetFloor.id_of(db)})
	if check(await wait_reports("watched", 1, 15.0), "c1 reports door B"):
		var w: Dictionary = reported(c1, "watched")
		check(not bool(w["shut"]), "c1 sees door B open")
		eq(int(w["swing"]), db.swing, "... the same way")

	# 3. A brute smashes door C.
	var lines0 := _door_lines()
	var hero := my_hero()
	hero.global_position = _stand(dc, -3.0)
	hero.snap_to_ground()
	var br := MonsterFactory.spawn("brute", Hex.from_world(dc.center() + dc.axis * 5.0))
	if not check(br != null, "a brute in door C's hall"):
		return
	await get_tree().physics_frame
	br.aggro(hero)
	check(await until(func() -> bool: return dc.broken, 14.0), "the brute smashed door C")
	br.set_physics_process(false)   # (it would go on to the host's hero)
	eq(_door_lines() - lines0, 1, "one \"Office door\" Ledger line on the host")
	command(c1, "smash", {"id": NetFloor.id_of(dc)})
	if check(await wait_reports("smashed", 1, 15.0), "c1 reports door C"):
		var s: Dictionary = reported(c1, "smashed")
		check(bool(s["broken"]), "c1's door C is broken")
		eq(int(s["lines"]), _door_lines(), "c1's invoice has the door once")
		eq(str(s["ledger"]), ledger_text(), "c1's Ledger is the host's, line for line")

	# 4. The host shuts door A (E).
	check(da.use(hero), "the host's E shuts door A")
	check(da.shut, "door A is shut on the host")

	# 5. c2 joins the running crew.
	raise_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 30.0), "c2 joins the crew on the job"):
		return
	var c2 := peer_named("c2")
	if not check(await wait_reports("checkout", 1, 30.0), "c2 opened its license checkout"):
		return
	command(c2, "sign", {"spells": JOINER_SPELLS})
	if not check(await until(func() -> bool: return Session.join.admitted.has(c2), 30.0), "c2 was admitted"):
		return
	if not check(await wait_reports("arrived", 1, 30.0), "c2 reports its doors"):
		return
	var mine := _states()
	print("[DOORS] host: %s" % mine)
	eq(str((reported(c2, "arrived") as Dictionary)["doors"]), mine, "the late joiner's doors are the host's [shut, swing, broken]")
	command(c1, "states")
	if check(await wait_reports("states", 1, 15.0), "c1 reports its doors"):
		eq(str(reported(c1, "states")), mine, "c1's doors are the host's (door A shut again)")
	var st := Session.objects.stats
	print("[DOORS] objects: doors out %d, requests in %d" % [int(st.get("doors_out", 0)), int(st.get("door_reqs", 0))])

	command(c1, "end")
	command(c2, "end")
	check(await wait_done(2, 30.0), "the clients are done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	eq(int(reported(c1, "end")), 0, "... nor on c1")
	eq(int(reported(c2, "end")), 0, "... nor on c2")


func run_client() -> void:
	net_timeout = 110.0
	if index == 2:
		await _late_joiner()
		return
	if not check(await connect_client() == "", "joined"):
		return
	make_game({"spells": "heal,corn"})
	if not check(await wait_floor(45.0), "floor 1 starts here") or not await wait_sync():
		return
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(80.0)
		match str(cmd.get("cmd", "")):
			"push":
				report("pushed", await _push(_door(int(cmd["id"]))))
			"watch":
				var d := _door(int(cmd["id"]))
				await until(func() -> bool: return not d.shut, 6.0)
				report("watched", {"shut": d.shut, "swing": d.swing})
			"smash":
				var d := _door(int(cmd["id"]))
				await until(func() -> bool: return d.broken, 6.0)
				await sleep(0.4)   # (the bill follows the break)
				report("smashed", {"broken": d.broken, "lines": _door_lines(), "ledger": ledger_text()})
			"states":
				await sleep(0.3)
				report("states", _states())
			"end":
				report("end", Net.guard_hits.size())
				running = false
			_:
				running = false


## c2: wait for the host's flag, join the crew on the job, sign, and report every door's state once it is on the floor.
func _late_joiner() -> void:
	var since := Time.get_unix_time_from_system()
	if not check(await wait_flag("join", since, 90.0), "the host raised the join flag"):
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
	if not check(await until(func() -> bool: return Session.join.arrived, 30.0), "c2 arrived on the crew's floor"):
		return
	if not check(await wait_floor(10.0), "the floor started for c2"):
		return
	await sleep(0.3)
	report("arrived", {"doors": _states()})
	await wait_command(30.0)
	report("end", Net.guard_hits.size())


# --- Helpers ---------------------------------------------------------------------------------------------------

## The floor's doors in net-id order.
func _doors() -> Array[OfficeDoor]:
	var out := OfficeDoor.all()
	out.sort_custom(func(x: OfficeDoor, y: OfficeDoor) -> bool: return NetFloor.id_of(x) < NetFloor.id_of(y))
	return out


func _door(id: int) -> OfficeDoor:
	for d in OfficeDoor.all():
		if NetFloor.id_of(d) == id:
			return d
	return null


## Every door as "id:[shut, swing, broken]", in id order.
func _states() -> String:
	var parts: PackedStringArray = []
	for d in _doors():
		parts.append("%d:[%s, %d, %s]" % [NetFloor.id_of(d), d.shut, d.swing, d.broken])
	return " ".join(parts)


## A point on the line through the door's middle, `out` along its axis (+: the hall side, -: the room side).
func _stand(d: OfficeDoor, out: float) -> Vector3:
	var p := d.center() + d.axis * out
	return Vector3(p.x, (game.get("map") as HexMap).ground_height(p), p.z)


## Host: the floor's monsters, hellgates, employees and the AI ally stand still (only the test opens doors).
func _still() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster or n is Hellgate or n is Employee:
			n.set_physics_process(false)
	var ai := hero_at(3)
	var brain := ai.get_node_or_null("AllyBrain") if ai != null else null
	if brain != null:
		brain.set_physics_process(false)
	# (the monsters roamed while the crew arrived: one may have opened a door already)
	for d in OfficeDoor.all():
		if not d.shut and not d.broken:
			print("[DOORS] door %d was opened before the test: shut again" % NetFloor.id_of(d))
			d.host_decide(true, null)


func _a_monster() -> Monster:
	for id in NetRegistry.ids():
		var m := NetRegistry.node(id) as Monster
		if m != null and not m.dead and m.kind != "brute":
			return m
	return null


## Host: walk monster `m` (its own AI off) from door `d`'s hall into the door, as its chase would; true once it opened it.
func _monster_walks_in(m: Monster, d: OfficeDoor) -> bool:
	m.global_position = _stand(d, 1.6)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var t0 := GameWorld.time
	var ok := await until(func() -> bool:
		var gap := absf(d.local_flat(m.global_position).y) - d.half - m.radius
		if d.shut and gap > 0.05:
			m.global_position -= d.axis * minf(gap - 0.04, 3.0 / 60.0)
		return not d.shut, 5.0)
	var took := GameWorld.time - t0
	check(took >= OfficeDoor.MONSTER_DELAY - 0.05, "... after stopping at it (%.2f s)" % took)
	m.global_position = _stand(d, 6.0)
	return ok


## c1: walk this machine's hero into shut door `d` from its hall side and on through it.
func _push(d: OfficeDoor) -> Dictionary:
	var h := my_hero()
	var c := game.get("controller") as PlayerController
	h.global_position = _stand(d, 1.8)
	h.snap_to_ground()
	await sleep(0.3)
	c.move_override = -d.axis
	var touch := [-1.0]
	var opened := await until(func() -> bool:
		if touch[0] < 0.0 and absf(d.local_flat(h.global_position).y) - d.half - h.radius <= OfficeDoor.TOUCH:
			touch[0] = truth()
		return not d.shut, 6.0)
	var ms := (truth() - float(touch[0])) * 1000.0
	var through := await until(func() -> bool: return d.local_flat(h.global_position).y < -1.6, 4.0)
	c.move_override = Vector3.INF
	await sleep(0.3)
	return {"opened": opened, "swing": d.swing, "through": through, "ms": ms}


static func _door_lines() -> int:
	var n := 0
	for l in Ledger.lines:
		if str(l["label"]) == OfficeDoor.LABEL:
			n += 1
	return n
