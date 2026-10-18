extends NetGameTest
## M6 (networking-build-plan.md, "M6 Join mid-contract and seat handover"): a player joins while the crew is signing its
## licenses. Three processes, `off` and `coast`. The host and c1 take a job and open their license checkouts; c2 joins then:
## - it is a joining member that nobody waits for: the crew signs and floor 1 starts without it (it gets no crew.job /
##   crew.load / crew.go, and its own license is not one the crew waits on), and seat 3 is built as the AI (Gasket) on every
##   machine;
## - c2's "Clocking in..." says the crew is signing licenses, and c2 opens ITS OWN license checkout (user, 2026-10-18: a
##   joiner picks its spells); it keeps it open until floor 1 has started without it, then signs tentacles + teeth;
## - it is sent onto floor 1 only once the van arrival is over (the hero sync is live: the AI is out of the van), builds
##   floor 1 with the host's checksum (the van parked) and takes seat 3 holding the license it signed, on every machine.

const PEERS := 3
const SEED := 13


func run_host() -> void:
	net_timeout = 80.0
	clear_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	make_game({"seed": SEED, "contract": 1, "net_wait": 2})   # (no --spells: everyone signs by hand)
	if not check(await wait_picker(30.0), "the host's license checkout opens"):
		return
	eq(flow().phase, CrewFlow.LICENSE, "the crew is signing licenses")
	raise_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 30.0), "c2 joins during the license checkout"):
		return
	var c2 := peer_named("c2")
	var c1 := peer_named("c1")
	check(CrewFlow.is_joining(Session.roster[c2]), "c2 is a joining member")
	eq(int(Session.roster[c2]["seat"]), 3, "it holds seat 3 (the AI's)")
	if check(await wait_reports("checkout", 1, 20.0), "c2 opened its own license checkout"):
		check(bool(reported(c2, "checkout")), "... the joiner's checkout (in place of \"Clocking in...\")")
	check(not flow().waiting_names().has("c2"), "nobody waits for c2's license")
	command(c1, "sign")
	await sleep(0.5)
	sign_license(my_license())
	if not check(await wait_floor(40.0), "floor 1 starts without c2 (still in its checkout)"):
		return
	eq(Session.seats.owner_of(3), 0, "seat 3 was built as the AI")
	eq(hero_at(3).kit_id, "gasket", "... Gasket")
	check(not Session.join.admitted.has(c2), "c2 is not sent in before it signs")
	command(c2, "sign")
	check(not Session.join.admitted.has(c2), "c2 is not sent in during the van arrival")
	if not check(await until(func() -> bool: return Session.join.admitted.has(c2), 30.0), "c2 arrives after the van arrival"):
		return
	check(Session.snap.active, "(the hero sync was live: the crew is out of the van)")
	if check(await wait_reports("arrived", 1, 20.0), "c2 reports its arrival"):
		var r: Dictionary = reported(c2, "arrived")
		eq(int(r["floor"]), 1, "c2 is on floor 1")
		eq(str(r["sum"]), str(flow().local_sums.get("all", "")), "c2 built the same floor 1 (the van parked, the same checksum)")
		eq(int(r["seat"]), 3, "c2 took seat 3")
		check(str(r["note"]).contains("licenses"), "c2's \"Clocking in...\" said the crew was signing licenses (\"%s\")" % str(r["note"]))
		eq(str(r["slots"]), str(LICENSES[2]), "c2 arrived with the license it signed")
	eq(Session.seats.owner_of(3), c2, "seat 3 is c2's")
	eq(hero_at(3).kit_id, "wick", "... as Wick")
	eq(str(Array(hero_at(3).spell_slots)), str(LICENSES[2]), "... holding c2's license on the host")
	command(c1, "slots")
	if check(await wait_reports("slots", 1, 10.0), "c1 reports seat 3"):
		eq(str(reported(c1, "slots")), str(LICENSES[2]), "c1 shows c2's license in seat 3")
	for p in [c1, c2]:
		command(p, "end")
	check(await wait_done(2, 20.0), "both clients are done")
	clear_flag("join")


func run_client() -> void:
	if index == 2:
		await _joiner()
		return
	if not check(await connect_client() == "", "joined"):
		return
	make_game({})
	var cmd := await wait_command(40.0)
	if str(cmd.get("cmd", "")) == "sign":
		check(await wait_picker(), "c1's license checkout opens")
		check(sign_license(my_license()), "c1 signs")
		check(await wait_floor(40.0), "floor 1 starts for c1")
	cmd = await wait_command(60.0)
	if str(cmd.get("cmd", "")) == "slots":
		await until(func() -> bool: return hero_at(3) != null and hero_at(3).kit_id == "wick", 10.0)
		report("slots", str(Array(hero_at(3).spell_slots)))
		await wait_command(60.0)


func _joiner() -> void:
	var since := Time.get_unix_time_from_system()
	if not check(await wait_flag("join", since, 60.0), "the host raised the join flag"):
		return
	if not check(await connect_client() == "", "joined the crew at the license checkout"):
		return
	make_game({})
	var seen := {"note": ""}
	var opened := await until(func() -> bool:
		if Session.join.note != "" and str(seen["note"]) == "":
			seen["note"] = Session.join.note
		return picker() != null, 30.0)
	if not check(opened, "c2's license checkout opened"):
		return
	report("checkout", game.get("_join_picker") != null)
	var cmd := await wait_command(60.0)
	if not check(str(cmd.get("cmd", "")) == "sign", "the host says sign"):
		return
	check(sign_license(my_license()), "c2 signs %s" % str(my_license()))
	var arrived := await until(func() -> bool: return Session.join.arrived, 50.0)
	if not check(arrived, "c2 arrived on floor 1"):
		return
	check(await wait_floor(10.0), "the floor started for c2")
	report("arrived", {"floor": int((game.get("_session") as ContractSession).floor_number), "sum": flow().local_sums.get("all", ""),
		"seat": NetFloor.id_of(my_hero()), "note": seen["note"], "slots": str(Array(my_hero().spell_slots))})
	await wait_command(60.0)
