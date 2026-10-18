extends NetGameTest
## M1: leaving the shared run from the job board, three processes.
## - Esc on a CLIENT's job board leaves the crew (no confirm; the host drops it);
## - the host takes a job; backing out of its checkout sends the whole crew back to the board (the same three offers);
## - Esc on the HOST's board asks first (it ends the job for everyone): "Stay" keeps the crew, "End the job" ends the
##   session: the client that is left gets "The host clocked out" and goes back to the menu.

const PEERS := 3
const SEED := 41


func _pause_key() -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = "pause"
	ev.pressed = true
	return ev


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
	var offers := offers_signature(board().offers)
	check(await wait_reports("on_board", 2), "both clients see the board")
	var c1 := _peer_named("c1")
	var c2 := _peer_named("c2")
	command(c1, "esc")
	check(await until(func() -> bool: return Session.roster.size() == 2, 10.0), "Esc on c1's board: the host drops it, no questions asked")

	# The host takes the job; the remaining client opens its checkout.
	board().choose(1)
	check(await wait_picker(), "the host has a checkout")
	check(await wait_reports("in_checkout", 1), "c2 is in its checkout")
	# Back out of the checkout (Esc): the crew goes back to the board, with the same three offers.
	game.call("_unhandled_input", _pause_key())
	check(await until(func() -> bool: return scene_changes.size() == 1 and scene_changes[0] == "", 5.0), "backing out asks for the job board again")
	game.queue_free()
	make_game({"seed": SEED})
	check(await wait_board(), "the host's board is back")
	eq(offers_signature(board().offers), offers, "with the same three offers")
	check(await wait_reports("back_on_board", 1), "c2 is back on the board too")
	eq(str(reported(c2, "back_on_board")), offers, "with the same offers")

	# Esc on the host's board: the question. Stay first.
	game.call("_unhandled_input", _pause_key())
	var confirm: CrewConfirm = game.get("_confirm")
	check(confirm != null, "the host is asked before ending the job for the crew")
	if confirm == null:
		return
	confirm.declined.emit()
	await get_tree().process_frame
	check(game.get("_confirm") == null and Session.online() and Session.roster.size() == 2, "Stay: nothing happens")
	game.call("_unhandled_input", _pause_key())
	confirm = game.get("_confirm")
	check(confirm != null, "asked again")
	if confirm == null:
		return
	confirm.confirmed.emit()
	check(not Session.online(), "End the job: the host's session is over")
	eq(Session.last_reason, NetSession.CREW_CLOSED, "closing the crew")
	check(scene_changes.back() == Boot.MENU_SCENE, "the host's game goes back to the menu")
	check(await wait_done(1, 20.0), "c2 is done")


func run_client() -> void:
	if not check(await connect_client() == "", "joined"):
		return
	make_game()
	if not check(await wait_board(), "the client gets the board"):
		return
	var offers := offers_signature(board().offers)
	report("on_board", true)
	if index == 1:
		var cmd := await wait_command(20.0)
		eq(str(cmd.get("cmd", "")), "esc", "the host says when")
		game.call("_unhandled_input", _pause_key())
		await get_tree().process_frame
		check(not Session.online(), "c1 left the crew with Esc on the board")
		eq(Session.last_reason, NetSession.YOU_LEFT, "and says so")
		eq(scene_changes, [Boot.MENU_SCENE] as Array[String], "c1's game goes back to the menu")
		return
	# c2 stays.
	if not check(await wait_picker(), "c2's checkout opens"):
		return
	report("in_checkout", true)
	# The host backed out: the crew.board arrives, c2's game asks for the board again; the test reloads it.
	check(await until(func() -> bool: return scene_changes.size() == 1 and scene_changes[0] == "", 10.0), "c2 is sent back to the board")
	game.queue_free()
	make_game()
	if not check(await wait_board(), "c2's board is back"):
		return
	check(board().read_only, "still read-only")
	report("back_on_board", offers_signature(board().offers))
	# Then the host ends the job.
	scene_changes.clear()


func after_end() -> void:
	check(not scene_changes.is_empty() and scene_changes.back() == Boot.MENU_SCENE, "c2's game goes back to the menu when the host ends the job (%s)" % str(scene_changes))
