extends NetGameTest
## M1: people leaving the shared run, three processes.
## - a client leaves in the license checkout (the checkout's "Leave the crew" row / Esc): the host drops it from the
##   roster, nobody waits for it, and the floor starts for the two who stay, with matching checksums;
## - the host leaves while the floor runs: the client's session ends with "The host clocked out" and its game goes
##   back to the menu.

const PEERS := 3
const SEED := 31


func _peer_named(who: String) -> int:
	for e: Dictionary in Session.crew():
		if str(e["name"]) == who:
			return int(e["peer"])
	return 0


func run_host() -> void:
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 20.0), "both clients join"):
		return
	make_game({"seed": SEED})
	if not check(await wait_board(), "the host has a board"):
		return
	await sleep(0.8)
	board().choose(2)
	check(await wait_picker(), "the host has a checkout")
	check(await wait_reports("in_checkout", 2), "both clients are in their checkout")
	var c2 := _peer_named("c2")
	check(c2 != 0, "found c2 in the roster")
	command(c2, "leave")
	check(await until(func() -> bool: return Session.roster.size() == 2, 10.0), "the host drops the client who left the checkout")
	check(not Session.roster.has(c2), "c2 is off the roster")
	check(flow().waiting_names().all(func(n: String) -> bool: return n != "c2"), "nobody waits for c2")
	check(sign_license(my_license()), "the host signs")
	check(await wait_floor(40.0), "the floor starts for the two who stay")
	check(await wait_reports("floor", 1, 20.0), "c1 reports its floor")
	for p in peers_with("floor"):
		eq(str(reported(p, "floor")), str(flow().local_sums["all"]), "c1's floor checksum matches the host's")
	eq(flow().desyncs, [], "no desync")
	eq(Session.roster.size(), 2, "two in the crew on the floor")
	check(await wait_done(1, 20.0), "c1 is done")
	# The host's process exits now: c1 is on the floor and is told so.


func run_client() -> void:
	if not check(await connect_client() == "", "joined"):
		return
	make_game()
	if not check(await wait_board(), "the client gets the board"):
		return
	if not check(await wait_picker(), "a license checkout opens"):
		return
	var leaving := index == 2
	report("in_checkout", true)
	if leaving:
		var cmd := await wait_command(20.0)
		eq(str(cmd.get("cmd", "")), "leave", "the host says when")
		# The checkout's Leave the crew row (Esc does the same through the game).
		picker().cancelled.emit()
		await get_tree().process_frame
		check(not Session.online(), "c2 left the crew")
		eq(Session.last_reason, NetSession.YOU_LEFT, "and says so")
		eq(scene_changes, [Boot.MENU_SCENE] as Array[String], "c2's game goes back to the menu")
		return
	await sleep(1.5)
	check(sign_license(my_license()), "c1 signs and waits for the host")
	var label: Label = game.get("_wait_label")
	check(label != null and label.visible, "c1 is shown the wait")
	if not check(await wait_floor(40.0), "c1's floor starts"):
		return
	eq(Session.roster.size(), 2, "c1 sees a crew of two")
	report("floor", str(flow().local_sums["all"]))


func after_end() -> void:
	# The host left while the floor ran.
	eq(scene_changes, [Boot.MENU_SCENE] as Array[String], "c1's game goes back to the menu when the host leaves")
