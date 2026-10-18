extends NetGameTest
## M5 (networking-build-plan.md, "M5 Contract flow"), three processes, `off` and `coast`: a crew that started together
## plays whole contracts online, from the board to the invoice and back, every step driven through the game's own
## E key, menus and invoice (M3's test_net_m3_exit covers two players choosing through `_choose_exit` directly; this
## one goes through the keys and the whole contract).
##
## Contract 1 (seed SEED, offer 1):
## - each owner marks its own hero's HP (a different value per seat, HP_BY_SEAT);
## - c1 and c2 stand at the elevator and press E in the same frame, both picking "go down": ONE decision, ONE floor
##   change (every machine reloads once), floor 2 is the same floor everywhere (checksum), and every machine shows
##   every seat's carried HP;
## - on floor 2 the host has an employee follow c1's hero two cells from the elevator and takes the elevator down: the
##   follower rides out with the crew (the host extracts it, $100 once), and floor 3's Ledger is the host's on every
##   machine, line for line;
## - on floor 3 c2 presses E and cashes out: every machine shows the SAME invoice dict (canonical JSON, every key);
## - c1 presses "Next contract" on its invoice: EVERYONE goes back to the host's board in the same lobby (decided: any
##   player's Next takes the crew back, like the first-to-choose exits).
## Contract 2 (offer 0 of the new board, every license signed by hand):
## - c1 clocks out at the van on floor 1: the contract ends for everyone with the same invoice;
## - the host then leaves (the test ends) while the clients are on the invoice: each is told "The host clocked out"
##   and its game asks for the main menu (no host migration).

const PEERS := 3
const SEED := 13
## Each seat's HP, set by that seat's owner on floor 1 (different per seat, so a carry mixed up between seats shows).
const HP_BY_SEAT := {1: 78.0, 2: 71.0, 3: 64.0}

## Every exit decision this machine saw: [choice, seat].
var decisions: Array = []


func run_host() -> void:
	net_timeout = 85.0
	follow_reloads = true
	Session.objects.exit_decided.connect(func(c: String, seat: int) -> void: decisions.append([c, seat]))
	if not await enter_floor(SEED, 1):
		return
	(game.get("opts") as Dictionary).erase("net_wait")   # (the next board waits for this test's own pick)
	if not await wait_sync():
		return
	_mark_hero()
	check(await wait_reports("ready", 2, 30.0), "both clients are on floor 1")
	var c1 := peer_named("c1")
	var c2 := peer_named("c2")
	await sleep(0.4)   # (every machine sees every seat's marked HP before the carry is saved)

	# 1. c1 and c2 press E at the elevator in the same frame and both pick "go down".
	var t := Session.host_time() + 0.8
	for p in [c1, c2]:
		command(p, "elevator", {"c": "down", "t": t})
		command(p, "floor", {"n": 2})
	check(await until(func() -> bool: return reloads >= 1, 10.0), "the host followed the crew down")
	eq(decisions.size(), 1, "two E presses in the same frame: one decision")
	var first: Array = decisions[0] if not decisions.is_empty() else ["", 0]
	eq(str(first[0]), "down", "... to go down")
	check(int(first[1]) == 2 or int(first[1]) == 3, "... by one of the two clients (seat %d)" % int(first[1]))
	if not await _on_floor(2, [c1, c2]):
		return
	eq(reloads, 1, "the host changed floor once")

	# 2. Floor 2: an employee follows c1's hero two cells from the elevator; the host takes the elevator down.
	var exit_cell: Vector2i = game.get("_exit_cell")
	var emp := _living_employee()
	check(emp != null, "floor 2 has an employee to bring along")
	var extracted_before := _lines_labelled("Employee extracted")
	if emp != null:
		var spot := cell_at(exit_cell, 2)
		check(spot != Vector2i.MAX, "a floor cell two cells from the elevator")
		var lv := (game.get("map") as HexMap).ground_level(Hex.to_world(spot))
		emp.global_position = Hex.to_world(spot, 0.0 if is_nan(lv) else lv)
		emp.snap_to_ground()
		if not emp.is_following():
			emp.request_follow(hero_at(2), emp.global_position)
		check(emp.is_following(), "the employee follows a hero")
	for p in [c1, c2]:
		command(p, "floor", {"n": 3})
	game.call("_choose_exit", "down")
	if emp != null:
		check(emp.is_extracted(), "the follower near the elevator rides out with the crew (extracted by the host)")
		eq(_lines_labelled("Employee extracted"), extracted_before + 1, "... paid once ($100)")
	check(await until(func() -> bool: return reloads >= 2, 10.0), "the host went down again")
	eq(decisions.size(), 2, "one more decision")
	if not await _on_floor(3, [c1, c2]):
		return
	for p in [c1, c2]:
		eq(str(reported(p, "floor3")["ledger"]), ledger_text(), "%s's Ledger on floor 3 is the host's, line for line" % _who(p, c1))

	# 3. Floor 3: c2 presses E at the elevator and cashes out.
	t = Session.host_time() + 0.6
	command(c2, "elevator", {"c": "out", "t": t})
	for p in [c1, c2]:
		command(p, "invoice", {"key": "invoice1"})
	check(await until(func() -> bool: return bool(game.get("_ended")), 8.0), "c2's cash-out ended the contract on the host")
	eq(str(decisions.back()), str(["out", 3]), "c2 decided it")
	var inv: Dictionary = game.get("_last_invoice")
	eq(str(inv.get("reason", "")), ContractSession.END_CASHED_OUT, "the invoice: cashed out")
	eq(int(inv.get("floor_reached", 0)), 3, "... on floor 3")
	check(int((inv.get("employees", {}) as Dictionary).get("extracted", 0)) >= 1, "... with the employee who rode the elevator")
	await _same_invoice("invoice1", [c1, c2], c1)
	var shown: InvoiceScreen = game.get("_invoice")
	check(shown != null and shown.next_note.contains("whole crew"), "the host's invoice says Next takes the whole crew")

	# 4. c1 presses "Next contract": everyone back to the host's board, same lobby.
	command(c1, "next")
	for p in [c1, c2]:
		command(p, "board", {"key": "board1", "n": 3})
	check(await until(func() -> bool: return reloads >= 3 and board() != null, 10.0), "c1's Next took the host back to the board")
	check(game.get("_session") == null, "... the contract is dropped")
	await _same_board("board1", [c1, c2], c1, "")

	# Contract 2: the host takes offer 0, everyone signs their license.
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
	var run: ContractRun = game.get("_run")
	for p in [c1, c2]:
		eq(str(reported(p, "signed2")["run"]), run_signature(run), "%s took the same contract" % _who(p, c1))

	# 5. c1 clocks out at the van on floor 1: the contract ends for everyone.
	t = Session.host_time() + 0.6
	command(c1, "van", {"t": t})
	for p in [c1, c2]:
		command(p, "invoice", {"key": "invoice2"})
	check(await until(func() -> bool: return bool(game.get("_ended")), 8.0), "c1's van clock-out ended contract 2 on the host")
	eq(str(decisions.back()), str(["van", 2]), "c1 decided it, at the van")
	inv = game.get("_last_invoice")
	eq(str(inv.get("reason", "")), ContractSession.END_CASHED_OUT, "the invoice: cashed out")
	eq(int(inv.get("floor_reached", 0)), 1, "... on floor 1")
	await _same_invoice("invoice2", [c1, c2], c1)
	print("[M5] contract: down by seat %d, the follower rode out, out by seat 3 (payout %d); then a van clock-out by c1 (payout %d)" % [
		int(first[1]), int((reported(c1, "invoice1") as Dictionary).get("payout", 0)), int(inv.get("payout", 0))])
	for p in [c1, c2]:
		command(p, "end")
	check(await wait_done(2, 20.0), "both clients are done")
	# The host leaves now, with the clients on the invoice: no host migration (after_end).


## The host's checks once floor `n` has started everywhere: one more reload, the same floor (checksum), every seat's
## carried HP on every machine, and the same decisions.
func _on_floor(n: int, clients: Array) -> bool:
	if not check(await wait_floor(40.0), "floor %d starts for the host" % n):
		return false
	eq(int((game.get("_session") as ContractSession).floor_number), n, "the host is on floor %d" % n)
	if not check(await wait_reports("floor%d" % n, clients.size(), 40.0), "both clients reached floor %d" % n):
		return false
	eq(flow().desyncs.size(), 0, "nobody built a different floor %d" % n)
	for seat: int in HP_BY_SEAT:
		near(hero_at(seat).hp, float(HP_BY_SEAT[seat]), 0.2, "the host shows seat %d's carried HP on floor %d" % [seat, n])
	for p: int in clients:
		var r: Dictionary = reported(p, "floor%d" % n)
		var who := _who(p, clients[0])
		eq(int(r["floor"]), n, "%s is on floor %d" % [who, n])
		eq(str(r["sum"]), str(flow().local_sums.get("all", "")), "%s built the same floor %d" % [who, n])
		eq(int(r["reloads"]), n - 1, "%s changed floor once per descent" % who)
		eq(str(r["decisions"]), str(decisions), "%s saw the same decisions" % who)
		for seat: int in HP_BY_SEAT:
			near(float((r["hp"] as Dictionary).get(seat, -1.0)), float(HP_BY_SEAT[seat]), 0.2, "%s shows seat %d's carried HP on floor %d" % [who, seat, n])
	_mark_hero()
	return await wait_sync()


## Every client's invoice is the host's, key for key.
func _same_invoice(key: String, clients: Array, c1: int) -> void:
	check(await wait_reports(key, clients.size(), 20.0), "both clients report their invoice (%s)" % key)
	var mine := invoice_text()
	check(mine != "", "the host shows its invoice")
	for p: int in clients:
		var r: Dictionary = reported(p, key)
		var who := _who(p, c1)
		check(bool(r["ended"]), "%s's contract ended" % who)
		eq(str(r["inv"]), mine, "%s shows the host's invoice, every key" % who)
		eq(str(r["ledger"]), ledger_text(), "%s's Ledger is the host's" % who)
		check(str(r["hint"]).contains("whole crew"), "%s's invoice says Next takes the whole crew" % who)
		eq(str(r["decisions"]), str(decisions), "%s saw the same decisions" % who)


## Every client is back on the host's board (the same offers), with no contract, still in the crew.
func _same_board(key: String, clients: Array, c1: int, note: String) -> void:
	check(await wait_reports(key, clients.size(), 20.0), "both clients are back on the board (%s)" % key)
	for p: int in clients:
		var r: Dictionary = reported(p, key)
		var who := _who(p, c1)
		eq(int(r["seed"]), int(game.get("_board_shown")), "%s shows the host's new board" % who)
		check(bool(r["no_contract"]), "%s dropped the contract" % who)
		check(not bool(r["mirror"]), "%s's Ledger is no longer a mirror" % who)
		eq(str(r["note"]), note, "%s's board note" % who)
		eq(int(r["crew"]), 3, "%s is still in the crew (the same lobby)" % who)
	eq(Session.roster.size(), 3, "the crew is still three")


func _who(p: int, c1: int) -> String:
	return "c1" if p == c1 else "c2"


## This machine's own hero: its seat's HP, and a ward so the floor's monsters change nothing.
func _mark_hero() -> void:
	var me := my_hero()
	me.hp = float(HP_BY_SEAT[my_seat()])
	me._refresh_bar()
	me.set_modifier("test_ward", 0.0, 999.0)


func _living_employee() -> Employee:
	var site: Variant = game.get("_site")
	if site == null:
		return null
	for e: Variant in site.employees:
		var emp := e as Employee
		if emp != null and is_instance_valid(emp) and not emp.dead and not emp.is_extracted():
			return emp
	return null


func _lines_labelled(label: String) -> int:
	var n := 0
	for l: Dictionary in Ledger.lines:
		if str(l["label"]) == label:
			n += 1
	return n


func run_client() -> void:
	follow_reloads = true
	Session.objects.exit_decided.connect(func(c: String, seat: int) -> void: decisions.append([c, seat]))
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	_mark_hero()
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"elevator":
				# Stand at the elevator (c1 on it, c2 beside it) and press E at the shared moment, then pick the row.
				await until(func() -> bool: return Session.host_time() >= float(cmd["t"]) - 0.3, 5.0)
				var exit_cell: Vector2i = game.get("_exit_cell")
				place_hero(my_hero(), exit_cell if index == 1 else cell_at(exit_cell, 1))
				await until(func() -> bool: return Session.host_time() >= float(cmd["t"]), 5.0)
				var used := (game.get("controller") as PlayerController).press_use()
				var menu: ElevatorMenu = game.get("_menu")
				check(used and menu != null, "E at the elevator opens its menu")
				if menu != null:
					if str(cmd["c"]) == "down":
						menu.go_down.emit()
					else:
						menu.cash_out.emit()
			"van":
				await until(func() -> bool: return Session.host_time() >= float(cmd["t"]) - 0.3, 5.0)
				var door: Vector2 = game.call("_van_door_pos")
				check(door.x != INF, "floor 1 has the van")
				var map := game.get("map") as HexMap
				var h := map.ground_height(Vector3(door.x, 0.0, door.y))
				my_hero().global_position = Vector3(door.x, 0.0 if is_nan(h) else h, door.y)
				my_hero().snap_to_ground()
				await until(func() -> bool: return Session.host_time() >= float(cmd["t"]), 5.0)
				var used := (game.get("controller") as PlayerController).press_use()
				var van: VanExitMenu = game.get("_van_menu")
				check(used and van != null, "E at the van opens the clock-out slip")
				if van != null:
					van.clock_out.emit()
			"floor":
				var n := int(cmd["n"])
				check(await until(func() -> bool: return reloads >= n - 1, 10.0), "this client followed the crew down to floor %d" % n)
				check(await wait_floor(40.0), "floor %d starts here" % n)
				var hp := {}
				for seat in [1, 2, 3]:
					if hero_at(seat) != null:
						hp[seat] = hero_at(seat).hp
				report("floor%d" % n, {"floor": int((game.get("_session") as ContractSession).floor_number), "sum": flow().local_sums.get("all", ""),
					"decisions": decisions.duplicate(), "hp": hp, "reloads": reloads, "ledger": ledger_text()})
				_mark_hero()
				await wait_sync()
			"invoice":
				await until(func() -> bool: return bool(game.get("_ended")) and game.get("_invoice") != null, 8.0)
				var shown: InvoiceScreen = game.get("_invoice")
				var inv: Dictionary = game.get("_last_invoice")
				report(str(cmd["key"]), {"ended": bool(game.get("_ended")), "inv": invoice_text(), "ledger": ledger_text(),
					"hint": shown.next_note if shown != null else "", "decisions": decisions.duplicate(), "payout": int(inv.get("payout", 0))})
			"next":
				var shown: InvoiceScreen = game.get("_invoice")
				check(shown != null and shown.next_button != null, "the invoice has its Next contract row")
				if shown != null:
					shown.next_button.pressed.emit()
			"board":
				var n := int(cmd["n"])
				check(await until(func() -> bool: return board() != null and game.get("_session") == null, 10.0), "this client is back on the board")
				report(str(cmd["key"]), {"seed": int(game.get("_board_shown")), "no_contract": game.get("_session") == null,
					"mirror": Ledger.mirror, "note": flow().board_note, "crew": Session.roster.size(), "reloads": reloads, "n": n})
			"sign":
				check(await wait_picker(), "this client's license checkout opens")
				check(await sign_license(my_license()), "this client signs its license")
				check(await wait_floor(45.0), "contract 2's floor 1 starts here")
				await wait_sync()
				report(str(cmd["key"]), {"run": run_signature(game.get("_run") as ContractRun)})
			_:
				running = false


## The host left while this client was on the invoice: the game goes back to the main menu.
func after_end() -> void:
	await until(func() -> bool: return not scene_changes.is_empty() and scene_changes.back() == Boot.MENU_SCENE, 5.0)
	eq(scene_changes.back() if not scene_changes.is_empty() else "", Boot.MENU_SCENE, "the host left during the invoice: this game asks for the main menu")
