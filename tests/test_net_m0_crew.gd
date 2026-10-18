extends NetTest
## M0 "done when" (networking-build-plan.md): a crew of 3 over ENet, as separate processes.
## - host + 3 clients start together; the hello handshake admits the first two and refuses the third with
##   "Crew is full" (MAX_CREW = 3: one per crew slot);
## - every admitted process lists the same 3-entry roster (seat, peer, name, character id);
## - a client leaves: the host drops it and the other client sees the 2-entry roster;
## - the host's process exits: the last client's session ends with "The host clocked out".

const PEERS := 4


func run_host() -> void:
	var full := await until(func() -> bool: return Session.roster.size() == 3 and Session.refusals.size() == 1, 25.0)
	if not check(full, "3 in the crew and one refused (crew %d, refusals %d)" % [Session.roster.size(), Session.refusals.size()]):
		return
	eq(str(Session.refusals[0]["reason"]), NetSession.CREW_FULL, "the 4th player is refused with \"Crew is full\"")
	var seats: Array = Session.crew().map(func(e: Dictionary) -> int: return int(e["seat"]))
	eq(seats, [1, 2, 3], "seats 1-3 are taken")
	var crew := Session.crew()
	eq(str(crew[0]["name"]), "host", "the host is seat 1")
	eq(int(crew[0]["peer"]), 1, "the host is peer 1")
	for e: Dictionary in crew:
		eq(str(e["character"]), NetSession.DEFAULT_CHARACTER, "%s plays the default character" % str(e["name"]))
		check(str(e["name"]).begins_with("c") or str(e["name"]) == "host", "a roster name: %s" % str(e["name"]))
	check(int(crew[1]["peer"]) > 1 and int(crew[2]["peer"]) > 1, "clients have peer ids above 1")

	# Every admitted client lists the same roster.
	var mine := roster_signature()
	print("[NetTest] host roster: ", mine)
	if not check(await wait_reports("roster", 2), "both admitted clients report their roster"):
		return
	for p in peers_with("roster"):
		eq(str(reported(p, "roster")), mine, "peer %d lists the same roster as the host" % p)

	# The client in seat 3 leaves; the other one must see it go.
	var leaver := int(crew[2]["peer"])
	var stayer := int(crew[1]["peer"])
	var left: Array[int] = []
	Session.peer_left.connect(func(p: int) -> void: left.append(p))
	command(leaver, "leave")
	check(await until(func() -> bool: return Session.roster.size() == 2, 10.0), "the host drops the client who left")
	eq(left, [leaver] as Array[int], "peer_left fired for the leaver")
	command(stayer, "expect2")
	check(await wait_reports("roster2", 1), "the remaining client reports again")
	eq(str(reported(stayer, "roster2")), roster_signature(), "the remaining client sees the 2-entry roster")
	check(await wait_done(1), "the remaining client is done")
	# No Session.leave(): the host's process just exits (finish -> quit), the "host leaves" path.


func run_client() -> void:
	var why := await connect_client()
	if why != "":
		eq(why, NetSession.CREW_FULL, "the refused client is told the crew is full")
		check(not Session.online() and Session.roster.is_empty(), "a refused client is not in a session")
		return
	check(Session.local_id() > 1, "a client's local id is its peer id (%d)" % Session.local_id())
	eq(Session.host_name(), "host", "the client knows the host's name")
	check(await until(func() -> bool: return Session.roster.size() == 3, 20.0), "the roster fills to 3 (%d)" % Session.roster.size())
	eq(int(Session.local_entry().get("peer", 0)), Session.local_id(), "the roster has this client in it")
	report("roster", roster_signature())
	var cmd := await wait_command(30.0)
	match str(cmd.get("cmd", "")):
		"leave":
			Session.leave()
			eq(Session.last_reason, NetSession.YOU_LEFT, "leaving ends this client's session with its own reason")
			eq(Session.local_id(), 0, "local_id is 0 once out of the session")
		"expect2":
			check(await until(func() -> bool: return Session.roster.size() == 2, 10.0), "the roster drops to 2 here too")
			report("roster2", roster_signature())
		_:
			_fail("no command from the host (%s)" % str(cmd))
