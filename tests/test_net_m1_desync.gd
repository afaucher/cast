extends NetGameTest
## M1: a floor that does not match is refused, not played on silently. Three processes: c2 is made to build its floor
## from a DIFFERENT seed (the test seam CrewFlow.debug_seed_shift), so its floor checksum differs from the host's.
## - the host compares the checksums behind the load barrier, logs the desync (which parts differ), and sends c2 out;
## - c2's session ends with the reason "Desync: different floor" and its game goes back to the menu;
## - the host and c1, whose floors match, carry on and start the floor without waiting for c2.

const PEERS := 3
const SEED := 21

func run_host() -> void:
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 20.0), "both clients join"):
		return
	make_game({"seed": SEED})
	if not check(await wait_board(), "the host has a board"):
		return
	await sleep(0.8)   # let the clients draw it
	board().choose(0)
	check(await wait_picker(), "the host has a checkout")
	check(sign_license(my_license()), "the host signs")
	check(await wait_floor(40.0), "the host's floor starts without waiting for the client that built another floor")
	var f := flow()
	eq(f.desyncs.size(), 1, "exactly one client built a different floor")
	if f.desyncs.size() == 1:
		var d: Dictionary = f.desyncs[0]
		eq(str(d["name"]), "c2", "it was c2")
		check((d["parts"] as Array).has("map") or (d["parts"] as Array).has("run"), "the map or the contract differs (%s)" % str(d["parts"]))
	eq(Session.roster.size(), 2, "c2 is out of the crew")
	check(Session.crew().all(func(e: Dictionary) -> bool: return str(e["name"]) != "c2"), "and off the roster")
	check(await wait_reports("floor", 1, 20.0), "c1 reports its floor")
	for p in peers_with("floor"):
		eq(str(reported(p, "floor")), str(f.local_sums["all"]), "c1's floor matches the host's")
	# (c2 checks its own side: a client that was sent out can no longer report to the host, and its own failed
	# checks fail the run through its exit code.)
	check(await wait_done(1, 20.0), "c1 is done")


func run_client() -> void:
	if not check(await connect_client() == "", "joined"):
		return
	var _bad := index == 2   # c2 builds its floor from another seed
	if _bad:
		flow().debug_seed_shift = 1
	make_game()
	if not check(await wait_board(), "the client gets the board"):
		return
	if not check(await wait_picker(40.0), "a license checkout opens"):
		return
	await sleep(0.4 * index)
	check(sign_license(my_license()), "signs")
	if _bad:
		check(await until(func() -> bool: return ended, 30.0), "c2 is sent out")
		eq(ended_reason, NetSession.DESYNC, "with the reason \"Desync: different floor\"")
		check(not bool(game.get("_floor_begun")), "c2's floor never started")
		check(await until(func() -> bool: return not scene_changes.is_empty(), 5.0), "c2's game goes back to the menu")
		eq(scene_changes, [Boot.MENU_SCENE] as Array[String], "c2 asked for the main menu")
		check(Session.last_reason == NetSession.DESYNC, "the menu will say why")
		return
	if not check(await wait_floor(40.0), "c1's floor starts"):
		return
	report("floor", str(flow().local_sums["all"]))
