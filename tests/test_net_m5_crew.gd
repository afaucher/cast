extends NetGameTest
## M5 (networking-build-plan.md, "M5 Contract flow"), three processes, `off` and `coast`: pause, abandon and the end of a
## crew's contract, decided for everyone.
##
## Contract 1 (seed SEED, offer 1):
## - Esc on a client (c2) opens the pause menu WITHOUT pausing the tree (decided: no pause online): the floor clock and
##   the world run on, only c2's own hero stands still, and the form says so (online rows); Esc on the host is the same;
## - c2 picks "Abandon contract": the WHOLE crew goes back to the host's (new) board in the same lobby, and every board
##   says who abandoned it.
## Contract 2 (offer 0 of that board, every license signed by hand):
## - every player's hero goes down on its own machine: the host decides "crew incapacitated" from every hero's
##   replicated `dead` and ends the job for everyone, billing a $10,000 revival per crew member down (uncapped, the
##   payout goes negative) on its Ledger, which every client mirrors; every machine shows the same invoice;
## - the HOST presses "Next contract": everyone goes back to the board (a client's Next is test_net_m5_contract's);
## - the host leaves with the crew on the board: each client is told "The host clocked out" and goes to the menu.

const PEERS := 3
const SEED := 29


func run_host() -> void:
	net_timeout = 85.0
	follow_reloads = true
	if not await enter_floor(SEED, 1):
		return
	(game.get("opts") as Dictionary).erase("net_wait")   # (the next board waits for this test's own pick)
	if not await wait_sync():
		return
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	check(await wait_reports("ready", 2, 30.0), "both clients are on floor 1")
	var c1 := peer_named("c1")
	var c2 := peer_named("c2")

	# 1. Esc on c2, then on the host: the pause menu, and nothing pauses.
	command(c2, "esc")
	check(await wait_reports("paused", 1, 10.0), "c2 opened its pause menu")
	var r: Dictionary = reported(c2, "paused")
	check(bool(r["open"]), "c2: Esc opens the pause menu")
	check(not bool(r["tree_paused"]), "c2: the tree is NOT paused (another player is in the crew)")
	check(float(r["clock_ran"]) > 0.4, "c2: the floor clock ran on behind the menu (%.2f s in 0.6 s)" % float(r["clock_ran"]))
	check(bool(r["world_runs"]), "c2: the world is not frozen")
	check(not bool(r["controls"]), "c2: its own hero stands still")
	check(bool(r["online_form"]), "c2: the form says the job runs on (online rows)")
	eq(str(r["abandon_hint"]), "whole crew", "c2: Abandon takes the whole crew")
	eq(str(r["menu_hint"]), "leave the crew", "c2: Main menu leaves the crew")
	press_esc()
	var pause: PauseMenu = game.get("_pause")
	check(pause != null and pause.online, "the host: Esc opens the online pause menu")
	check(not get_tree().paused, "the host: the tree is not paused")
	eq(pause.menu_button.hint if pause != null else "", "ends the job", "the host: Main menu ends the job for everyone")
	var t0 := GameWorld.time
	await sleep(0.4)
	check(GameWorld.time - t0 > 0.3, "the host's floor clock runs on behind its menu")
	if pause != null:
		pause.resume.emit()
	check(game.get("_pause") == null, "Resume closes it")

	# 2. c2 abandons the contract: the whole crew goes back to the board.
	command(c2, "abandon")
	for p in [c1, c2]:
		command(p, "board", {"key": "board1", "n": 1})
	check(await until(func() -> bool: return reloads >= 1 and board() != null, 10.0), "c2's abandon took the host back to the board")
	check(game.get("_session") == null, "... the contract is dropped")
	var note := "c2 abandoned the job"
	eq(flow().board_note, note, "the host's board says who abandoned it")
	var shown: JobBoard = board()
	eq(shown.notice if shown != null else "", note, "... written on the host's board")
	await _same_board("board1", [c1, c2], c1, note)

	# Contract 2: the host takes offer 0, everyone signs.
	board().sign_hold = 0.0
	board().choose(0)
	for p in [c1, c2]:
		command(p, "sign", {"key": "signed2"})
	if not check(await wait_picker(), "the host's license checkout opens"):
		return
	await sign_license(my_license())
	if not check(await wait_floor(45.0), "contract 2's floor 1 starts for the host"):
		return
	if not await wait_sync():
		return
	check(await wait_reports("signed2", 2, 40.0), "both clients signed and started contract 2")
	eq(flow().board_note, "", "the note went with the job")

	# 3. Every hero goes down, each on its own machine, at one shared moment.
	var t := Session.host_time() + 0.6
	for p in [c1, c2]:
		command(p, "down", {"t": t})
		command(p, "invoice", {"key": "invoice2"})
	await until(func() -> bool: return Session.host_time() >= t, 5.0)
	my_hero().apply_damage(9999.0, null)
	check(await until(func() -> bool: return bool(game.get("_ended")), 10.0), "the host ended the job: crew incapacitated")
	var inv: Dictionary = game.get("_last_invoice")
	eq(str(inv.get("reason", "")), ContractSession.END_INCAPACITATED, "the invoice: crew incapacitated")
	eq(Ledger.revival_fees(), 3 * Ledger.REVIVAL_FEE, "three revivals billed ($10,000 each, uncapped)")
	var who: Array[String] = []
	for l: Dictionary in Ledger.lines:
		if str(l["kind"]) == "revival":
			who.append(str(l["who"]))
	who.sort()
	eq(str(who), str(["c1", "c2", "host"]), "one revival per crew member, named by player")
	eq(int(inv.get("payout", 0)), Ledger.payout_before_revival() - 3 * Ledger.REVIVAL_FEE, "the payout takes the revivals off")
	check(int(inv.get("payout", 0)) < 0, "... and goes negative (%d)" % int(inv.get("payout", 0)))
	check(await wait_reports("invoice2", 2, 20.0), "both clients report their invoice")
	var mine := invoice_text()
	for p in [c1, c2]:
		var ri: Dictionary = reported(p, "invoice2")
		var w := _who(p, c1)
		check(bool(ri["saw_down"]), "%s saw the whole crew down" % w)
		check(bool(ri["ended"]), "%s's contract ended" % w)
		eq(str(ri["inv"]), mine, "%s shows the host's invoice, every key" % w)
		eq(str(ri["ledger"]), ledger_text(), "%s's Ledger is the host's, revivals included" % w)
		eq(int(ri["revival_fees"]), Ledger.revival_fees(), "%s's Ledger bills the same revivals" % w)
		eq(int(ri["payout"]), Ledger.payout(), "%s's payout is the host's" % w)

	# 4. The host presses "Next contract": everyone goes back to the board.
	for p in [c1, c2]:
		command(p, "board", {"key": "board2", "n": 2})
	var inv_screen: InvoiceScreen = game.get("_invoice")
	check(inv_screen != null, "the host shows the invoice")
	if inv_screen != null:
		inv_screen.next_button.pressed.emit()
	check(await until(func() -> bool: return reloads >= 2 and board() != null, 10.0), "the host's Next took it back to the board")
	await _same_board("board2", [c1, c2], c1, "")
	print("[M5] crew: c2 abandoned (note on every board); incapacitated: revivals %d, payout %d; the host's Next took everyone back" % [
		Ledger.revival_fees(), int(inv.get("payout", 0))])
	for p in [c1, c2]:
		command(p, "end")
	check(await wait_done(2, 20.0), "both clients are done")
	# The host leaves now, with the crew on the board (after_end).


func _who(p: int, c1: int) -> String:
	return "c1" if p == c1 else "c2"


## Every client is back on the host's board (the same offers), with no contract, still in the crew.
func _same_board(key: String, clients: Array, c1: int, note: String) -> void:
	check(await wait_reports(key, clients.size(), 20.0), "both clients are back on the board (%s)" % key)
	for p: int in clients:
		var r: Dictionary = reported(p, key)
		var w := _who(p, c1)
		eq(int(r["seed"]), int(game.get("_board_shown")), "%s shows the host's new board" % w)
		check(bool(r["no_contract"]), "%s dropped the contract" % w)
		check(not bool(r["mirror"]), "%s's Ledger is no longer a mirror" % w)
		eq(str(r["note"]), note, "%s's board note" % w)
		eq(str(r["written"]), note, "%s's board shows it" % w)
		eq(int(r["crew"]), 3, "%s is still in the crew (the same lobby)" % w)
		eq(int(r["reloads"]), int(r["n"]), "%s reloaded once" % w)
	eq(Session.roster.size(), 3, "the crew is still three")


func run_client() -> void:
	follow_reloads = true
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"esc":
				press_esc()
				var pause: PauseMenu = game.get("_pause")
				var t0 := GameWorld.time
				await sleep(0.6)
				var controller := game.get("controller") as PlayerController
				report("paused", {"open": pause != null, "tree_paused": get_tree().paused, "clock_ran": GameWorld.time - t0,
					"world_runs": GameWorld.root != null and GameWorld.root.process_mode != Node.PROCESS_MODE_DISABLED,
					"controls": controller != null and controller.enabled, "online_form": pause != null and pause.online,
					"abandon_hint": pause.abandon_button.hint if pause != null else "", "menu_hint": pause.menu_button.hint if pause != null else ""})
			"abandon":
				var pause: PauseMenu = game.get("_pause")
				check(pause != null, "the pause menu is still open")
				if pause != null:
					pause.abandon_button.pressed.emit()
			"board":
				var n := int(cmd["n"])
				check(await until(func() -> bool: return reloads >= n and board() != null and game.get("_session") == null, 10.0), "this client is back on the board")
				var shown := board()
				report(str(cmd["key"]), {"seed": int(game.get("_board_shown")), "no_contract": game.get("_session") == null,
					"mirror": Ledger.mirror, "note": flow().board_note, "written": shown.notice if shown != null else "?",
					"crew": Session.roster.size(), "reloads": reloads, "n": n})
			"sign":
				check(await wait_picker(), "this client's license checkout opens")
				check(await sign_license(my_license()), "this client signs its license")
				check(await wait_floor(45.0), "contract 2's floor 1 starts here")
				await wait_sync()
				report(str(cmd["key"]), true)
			"down":
				await until(func() -> bool: return Session.host_time() >= float(cmd["t"]), 5.0)
				my_hero().apply_damage(9999.0, null)
				check(my_hero().dead, "this client's hero is down (its own machine decided)")
			"invoice":
				var saw_down := await until(func() -> bool: return bool(game.get("_ending")) or bool(game.get("_ended")), 8.0)
				await until(func() -> bool: return bool(game.get("_ended")) and game.get("_invoice") != null, 10.0)
				report(str(cmd["key"]), {"saw_down": saw_down, "ended": bool(game.get("_ended")), "inv": invoice_text(), "ledger": ledger_text(),
					"revival_fees": Ledger.revival_fees(), "payout": Ledger.payout()})
			_:
				running = false


## The host left while this client was on the board: the game goes back to the main menu.
func after_end() -> void:
	await until(func() -> bool: return not scene_changes.is_empty() and scene_changes.back() == Boot.MENU_SCENE, 5.0)
	eq(scene_changes.back() if not scene_changes.is_empty() else "", Boot.MENU_SCENE, "the host left: this game asks for the main menu")
