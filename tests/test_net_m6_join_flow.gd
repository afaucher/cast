extends NetGameTest
## M6 (networking-build-plan.md, "M6 Join mid-contract and seat handover"): joining at the awkward moments. Four processes,
## `off` and `coast`; the host and c1 start a contract together, c2 and c3 come later (each waits for the host's flag: a
## player who has not joined yet cannot be sent a command).
## - c2 joins DURING A FLOOR CHANGE (the host takes the elevator the moment c2's connection opens, so its hello lands while
##   the crew is loading floor 2): it is a joining member nobody waits for (the barrier starts floor 2 without it), it shows
##   "Clocking in..." saying the crew is riding the elevator, signs its license at once with the dev flag (--spells
##   vines,damp: a joiner's license, user 2026-10-18), and it arrives on floor 2 (not 1) once floor 2 has started, with the
##   host's checksum, in the AI's seat, holding vines and damp on every machine.
## - with three players in, c3's join is refused with "Crew is full" (and seats_free is 0): nothing on the floor changes.
## - c2 leaves (the AI is back, seats_free 1); the crew cashes out; c3 joins ON THE INVOICE: it waits ("Clocking in...", the
##   crew is reading the invoice; there is no license to sign for a finished job), and the host's "Next contract" takes it
##   to the board with everyone, an ordinary member. On the next job c3 signs the ORDINARY license checkout with the crew
##   (not a joiner's) and starts floor 1 in its seat from the barrier, like everyone.

const PEERS := 4
const SEED := 13
## c2's license (the --spells dev flag signs a joiner's license at once) and c3's on the next job.
const C2_SPELLS := ["vines", "damp"]
const C3_SPELLS := ["coffee", "armor"]

## The flow phase the host was in when each joiner's hello was admitted: peer -> [phase, floor_change, floor].
var admitted_in := {}


func run_host() -> void:
	net_timeout = 88.0
	follow_reloads = true
	for f in ["c2", "c3", "c3b"]:
		clear_flag(f)
	Session.peer_joined.connect(func(peer: int) -> void:
		admitted_in[peer] = [flow().phase, flow().floor_change, flow().floor_n])
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	make_game({"spells": "heal,corn", "seed": SEED, "contract": 1, "net_wait": 2})
	if not check(await wait_floor(45.0), "floor 1 starts") or not await wait_sync():
		return
	(game.get("opts") as Dictionary).erase("net_wait")
	_ward()
	var c1 := peer_named("c1")
	check(await wait_reports("ready", 1, 30.0), "c1 is on floor 1")

	# 1. c2 connects: the host takes the elevator down at once, so c2's hello lands during the floor change.
	var went := [false]
	multiplayer.peer_connected.connect(func(_id: int) -> void:
		if not went[0] and game != null and Session.roster.size() == 2:
			went[0] = true
			command(c1, "floor", {"n": 2})
			game.call("_choose_exit", "down"))
	raise_flag("c2")
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 30.0), "c2 joins"):
		return
	var c2 := peer_named("c2")
	check(went[0], "the crew took the elevator as c2 connected")
	var during: Array = admitted_in.get(c2, ["", false, 0])
	eq(str(during[0]), CrewFlow.LOADING, "c2's hello was admitted while the crew was loading the next floor")
	check(bool(during[1]), "... a floor change")
	check(CrewFlow.is_joining(Session.roster[c2]), "c2 is a joining member")
	if not check(await wait_floor(40.0), "floor 2 starts without waiting for c2") or not await wait_sync():
		return
	_ward()
	eq(int((game.get("_session") as ContractSession).floor_number), 2, "the host is on floor 2")
	check(await wait_reports("floor2", 1, 30.0), "c1 is on floor 2")
	if not check(await until(func() -> bool: return Session.join.admitted.has(c2), 25.0), "c2 arrives once floor 2 runs"):
		return
	if check(await wait_reports("arrived", 1, 20.0), "c2 reports its arrival"):
		var r: Dictionary = reported(c2, "arrived")
		eq(int(r["floor"]), 2, "c2 arrived on floor 2 (the floor after the change), not floor 1")
		eq(str(r["sum"]), str(flow().local_sums.get("all", "")), "c2 built the same floor 2 (checksum)")
		eq(int(r["seat"]), 3, "c2 took seat 3 (Gasket's)")
		check(bool(r["owns"]), "c2 controls it")
		check(str(r["note"]).contains("elevator"), "c2's \"Clocking in...\" said the crew was riding the elevator (\"%s\")" % str(r["note"]))
		check(bool(r["saw_slip"]), "c2 showed the form while it waited")
		eq(str(r["slots"]), str(C2_SPELLS), "c2 arrived with the license it signed (--spells, at once)")
	eq(str(Array(hero_at(3).spell_slots)), str(C2_SPELLS), "the host shows c2's license in seat 3")
	eq(flow().desyncs.size(), 0, "nobody built a different floor")
	eq(Session.seats.owner_of(3), c2, "seat 3 is c2's")
	eq(Session.seats_free(), 0, "seats_free is 0: the lobby stops listing the crew")

	# 2. A 4th player: "Crew is full", and nothing changes on the floor.
	var before := _floor_signature()
	var refused_before := Session.refusals.size()
	raise_flag("c3")
	check(await until(func() -> bool: return Session.refusals.size() > refused_before, 20.0), "c3 says hello")
	var ref: Dictionary = Session.refusals.back() if not Session.refusals.is_empty() else {}
	eq(str(ref.get("reason", "")), NetSession.CREW_FULL, "c3 is refused: Crew is full")
	await sleep(0.5)
	eq(Session.roster.size(), 3, "the crew is still three")
	eq(_floor_signature(), before, "nothing changed on the floor (seats, owners, kits)")
	check(Session.join.joiners.is_empty(), "nobody is joining")

	# 3. c2 leaves: the AI takes seat 3 back.
	command(c2, "leave")
	check(await until(func() -> bool: return hero_at(3).kit_id == "gasket" and Session.seats.owner_of(3) == 0, 6.0), "c2 left: Gasket is back in seat 3")
	eq(Session.seats_free(), 1, "seats_free is 1 again")

	# 4. The crew cashes out; c3 joins on the invoice and waits for the next board.
	command(c1, "invoice")
	game.call("_choose_exit", "out")
	check(await until(func() -> bool: return bool(game.get("_ended")), 8.0), "the job ended (the invoice is up)")
	check(flow().job_ended, "the host's flow knows the job is over")
	raise_flag("c3b")
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 30.0), "c3 joins on the invoice"):
		return
	var c3 := peer_named("c3")
	check(CrewFlow.is_joining(Session.roster.get(c3, {})), "c3 is joining (the crew is on the invoice)")
	if check(await wait_reports("waiting", 1, 15.0), "c3 reports it is waiting"):
		var w: Dictionary = reported(c3, "waiting")
		check(bool(w["slip"]), "c3 shows \"Clocking in...\"")
		check(str(w["note"]).contains("invoice"), "... saying the crew is reading the invoice (\"%s\")" % str(w["note"]))
		check(not bool(w["floor"]), "... and builds no floor")
		check(not bool(w["picker"]), "... and opens no license checkout (the job is over: nothing to sign)")
	check(not Session.join.admitted.has(c3), "c3 does not arrive on the finished job")
	check(await wait_reports("invoice", 1, 10.0), "c1 is on the invoice")
	# The host's Next contract: everyone (c3 too) on the new board.
	game.call("_on_next_contract")
	check(await until(func() -> bool: return reloads >= 2 and board() != null, 10.0), "the host is on a new board")
	for p in [c1, c3]:
		command(p, "board")
	if check(await wait_reports("board", 2, 15.0), "c1 and c3 report the board"):
		for p in [c1, c3]:
			var b: Dictionary = reported(p, "board")
			var who := "c1" if p == c1 else "c3"
			eq(int(b["seed"]), int(game.get("_board_shown")), "%s shows the host's new board" % who)
			check(not bool(b["joining"]), "%s is an ordinary member now" % who)
			check(not bool(b["slip"]), "%s shows no \"Clocking in...\"" % who)
	check(not CrewFlow.is_joining(Session.roster.get(c3, {})), "the host's roster: c3 is a member")
	check(Session.join.joiners.is_empty(), "nobody is joining any more")
	# 5. The next job: c3 signs the ordinary license checkout with the crew and starts in its seat from the barrier.
	board().choose(0)
	for p in [c1, c3]:
		command(p, "license")
	if check(await wait_picker(15.0), "the host's license checkout opens for the next job"):
		await sign_license(my_license())
	if check(await wait_floor(40.0), "the next job's floor 1 starts with the whole crew"):
		var seat3 := int(Session.roster[c3]["seat"])
		eq(Session.seats.owner_of(seat3), c3, "c3 holds seat %d from the barrier" % seat3)
		check(not Session.join.admitted.has(c3), "... as a member, not through a join")
		eq(str(Array(hero_at(seat3).spell_slots)), str(C3_SPELLS), "... with the license it signed")
	if check(await wait_reports("license", 2, 30.0), "c1 and c3 report their checkouts"):
		var l3: Dictionary = reported(c3, "license")
		check(bool(l3["picker"]) and not bool(l3["joiner"]), "c3 signed the ordinary license checkout (not a joiner's)")
		eq(str(l3["back"]), "Leave the crew", "... a client's (its back row leaves the crew)")
	for p in [c1, c3]:
		command(p, "end")
	check(await wait_done(2, 20.0), "c1 and c3 are done")
	for f in ["c2", "c3", "c3b"]:
		clear_flag(f)


## Who sits where on this floor, as one string: each seat's owner, kit and name.
func _floor_signature() -> String:
	var parts: PackedStringArray = []
	for seat in [1, 2, 3]:
		var h := hero_at(seat)
		parts.append("%d:%d:%s:%s:%d" % [seat, Session.seats.owner_of(seat), h.kit_id if h != null else "", Net.label_of(h) if h != null else "", Session.seats.epoch_of(seat)])
	return " ".join(parts)


func _ward() -> void:
	if my_hero() != null:
		my_hero().set_modifier("test_ward", 0.0, 999.0)


func run_client() -> void:
	follow_reloads = true
	match index:
		2:
			await _c2()
			return
		3:
			await _c3()
			return
	if not check(await connect_client() == "", "joined"):
		return
	make_game({"spells": "heal,corn"})
	if not check(await wait_floor(45.0), "floor 1 starts here") or not await wait_sync():
		return
	_ward()
	report("ready", true)
	await _commands()


func _commands() -> void:
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"floor":
				check(await until(func() -> bool: return reloads >= int(cmd["n"]) - 1, 10.0), "followed the crew down")
				check(await wait_floor(40.0), "floor %d starts here" % int(cmd["n"]))
				await wait_sync()
				_ward()
				report("floor%d" % int(cmd["n"]), flow().local_sums.get("all", ""))
			"invoice":
				check(await until(func() -> bool: return bool(game.get("_ended")), 10.0), "the job ended here")
				report("invoice", true)
			"board":
				check(await until(func() -> bool: return board() != null and game.get("_session") == null, 15.0), "on the board")
				report("board", {"seed": int(game.get("_board_shown")), "joining": CrewFlow.is_joining(Session.local_entry()),
					"slip": game != null and game.get("_join_slip") != null})
			"license":
				var opened := await wait_picker(15.0)
				var info := {"picker": opened, "joiner": game.get("_join_picker") != null, "back": picker().back_text if opened else ""}
				if opened:
					check(await sign_license(C3_SPELLS if index == 3 else my_license()), "signed the next job's license")
				check(await wait_floor(40.0), "the next job's floor starts here")
				report("license", info)
			"leave":
				Session.leave()
				running = false
			_:
				running = false


## c2: joins as the crew rides the elevator, arrives on floor 2.
func _c2() -> void:
	var since := Time.get_unix_time_from_system()
	if not check(await wait_flag("c2", since, 60.0), "the host raised c2's flag"):
		return
	if not check(await connect_client() == "", "c2 joined the crew on the job"):
		return
	make_game({"spells": ",".join(C2_SPELLS)})
	var seen := {"slip": false, "note": ""}
	var arrived := await until(func() -> bool:
		if game != null and game.get("_join_slip") != null:
			seen["slip"] = true
		if Session.join.note != "" and str(seen["note"]) == "":
			seen["note"] = Session.join.note
		return Session.join.arrived, 40.0)
	if not check(arrived, "c2 arrived on the crew's floor"):
		return
	if not check(await wait_floor(10.0), "the floor started for c2") or not await wait_sync():
		return
	_ward()
	report("arrived", {"floor": int((game.get("_session") as ContractSession).floor_number), "sum": flow().local_sums.get("all", ""),
		"seat": NetFloor.id_of(my_hero()), "owns": Net.owns(my_hero()) and not Net.is_puppet(my_hero()), "note": seen["note"], "saw_slip": seen["slip"],
		"slots": str(Array(my_hero().spell_slots))})
	await _commands()


## Longer than the beat a joiner's form shows before its license checkout opens (game.gd JOIN_LICENSE_BEAT).
const JOIN_BEAT := 1.0


## c3: refused while the crew is full, then joins on the invoice and goes to the board with everyone.
func _c3() -> void:
	var since := Time.get_unix_time_from_system()
	if not check(await wait_flag("c3", since, 70.0), "the host raised c3's flag"):
		return
	eq(await connect_client(), NetSession.CREW_FULL, "a 4th player is refused: Crew is full")
	check(not Session.online(), "... and is not in the crew")
	if not check(await wait_flag("c3b", since, 60.0), "the host raised c3's second flag"):
		return
	if not check(await connect_client() == "", "c3 joined the crew on the invoice"):
		return
	make_game({})   # (no --spells: c3 signs the next job's license by hand)
	check(await until(func() -> bool: return game.get("_join_slip") != null and Session.join.note != "", 10.0), "c3 shows \"Clocking in...\"")
	await sleep(JOIN_BEAT)
	report("waiting", {"slip": game.get("_join_slip") != null, "note": Session.join.note, "floor": game.get("map") != null, "picker": picker() != null})
	await _commands()
