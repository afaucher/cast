extends TestCase
## The contract flow inside the real game scene: the job board, a floor with its site and objective
## tracker, the elevator menu (stay / cash out), and "crew incapacitated" ending in the invoice.
## (Going down reloads the scene, which a test cannot do, so that path is covered by the session tests.)

const GAME := preload("res://scripts/app/game.gd")


func _make_game(extra: Dictionary) -> Node3D:
	var g: Node3D = load("res://scripts/app/game.gd").new()
	var o := {"no_mic": true, "spells": "heal,corn"}
	o.merge(extra, true)
	g.set("opts", o)
	GAME.reset_flow()
	return g


func setup() -> void:
	timeout_sec = 90.0
	await _check_board()
	await _check_floor_and_elevator()
	await _check_incapacitated()
	finish()


func _check_board() -> void:
	var g := _make_game({})
	g.get("opts").erase("spells")
	g.get("opts")["seed"] = 7
	add_child(g)
	await frames(2)
	var board: JobBoard = null
	for layer in g.get_children():
		if layer is CanvasLayer:
			for c in layer.get_children():
				if c is JobBoard:
					board = c
	check(board != null, "the game boots into the job board")
	if board != null:
		eq(board.offers.size(), 3, "three offers on the board")
		check(Ledger.active == false or Ledger.lines.is_empty(), "no contract is running on the board")
		var first_value: int = board.offers[0].contract_value
		board.choose(0)
		await frames(3)
		check(g.get("_session") != null, "taking an offer starts the contract")
		eq(g.get("_session").floor_number, 1, "on floor 1")
		eq(Ledger.contract_value, first_value, "the Ledger carries the contract value")
		check(g.get("hud") != null, "the world was built after picking")
	g.queue_free()
	await frames(3)
	GAME.reset_flow()


func _check_floor_and_elevator() -> void:
	var g := _make_game({"contract": 1, "seed": 5})
	add_child(g)
	await frames(10)
	var session: ContractSession = g.get("_session")
	check(session != null and session.floor_number == 1, "--contract starts floor 1")
	var run: ContractRun = g.get("_run")
	var site: SiteBuilder.Site = g.get("_site")
	check(site != null, "the floor has a site")
	check(site.gates.size() > 0, "hellgates are on the floor (if the part exists)")
	check(site.employees.size() >= 2, "employees are on the floor")
	check(site.props.size() > 0, "priced props are on the floor")
	check(site.monsters.size() > 0, "monsters are on the floor")
	eq(session.state()["gates_total"], run.floor_gates[0], "the session expects this floor's gates")
	var tracker: ObjectiveTracker = g.get("_tracker")
	check(tracker != null and tracker.rows.size() >= 3, "the objective tracker lists gates, the pest and the employees")
	check(g.get("_ticker") != null, "the damage ticker is on the HUD")
	eq(tracker.title, "FLOOR 1 / 3", "the tracker shows the floor")

	# Closing a gate pays and ticks the tracker.
	var gate: Actor = site.gates[0]
	gate.apply_damage(99999.0, g.get("player"))
	await frames(4)
	eq(Ledger.earned(), run.gate_pay, "closing a hellgate pays the gate rate")
	eq(session.state()["gates_closed"], 1, "the session counted it")

	# An employee follows a hero who presses E next to them, and rides the elevator out for $100.
	var emp: Actor = site.employees[0]
	var hero_pos: Vector3 = g.get("player").global_position
	var emp_pos := emp.global_position
	g.get("player").global_position = emp_pos + Vector3(1.0, 0, 0)
	await frames(40)
	check(not bool(emp.call("is_following")), "walking up to an employee does not recruit them")
	g.get("player").global_position = emp.global_position + Vector3(1.0, 0, 0)   # it may have fled a monster: step up to it again
	await _press_e()
	check(bool(emp.call("is_following")), "E next to an employee brings them along")

	# The elevator needs a key press. Stepping onto the exit only shows "E: use elevator"; E there opens the
	# menu (and does not cast); E anywhere else does nothing (E never casts).
	var player: Hero = g.get("player")
	var exit_cell: Vector2i = g.get("_exit_cell")
	var lv := GameWorld.map.ground_level(Hex.to_world(exit_cell))
	var hud: Hud = g.get("hud")
	var held := player.held_spell()
	check(held != "", "a spell is held")
	player.set_charges(held, 5)
	player.global_position = Hex.to_world(exit_cell, lv)
	await frames(6)
	check(g.get("_menu") == null, "stepping on the exit does NOT open the elevator menu")
	eq(hud.context_prompt, "E: use elevator", "standing on the exit shows the E prompt")
	player.global_position = Hex.to_world(exit_cell + Hex.DIRS[0], GameWorld.map.ground_level(Hex.to_world(exit_cell + Hex.DIRS[0])))
	await frames(4)
	check(g.get("_menu") == null and hud.context_prompt != "", "next to the exit: the prompt shows, still no menu")
	player.global_position = Hex.to_world(exit_cell, lv)
	await frames(3)
	await _press_e()
	var menu: ElevatorMenu = g.get("_menu")
	check(menu != null, "E at the exit opens the elevator menu")
	eq(player.charges_of(held), 5, "E at the exit does not cast the held spell")
	if menu != null:
		check(menu.can_descend(), "floor 1 offers going down")
		eq(GameWorld.root.process_mode, Node.PROCESS_MODE_DISABLED, "the world is frozen while the menu is open")
		menu.stay.emit()
		await frames(3)
		check(g.get("_menu") == null, "Stay closes the menu")
		check(GameWorld.root.process_mode != Node.PROCESS_MODE_DISABLED, "and the world runs again")
		await frames(5)
		check(g.get("_menu") == null, "the menu does not reopen by itself while the crew stands on the elevator")
		# E away from the elevator does nothing, and certainly casts nothing.
		player.global_position = Hex.to_world(exit_cell, lv) + Vector3(8, 0, 8)
		await frames(10)
		eq(hud.context_prompt, "", "no prompt away from the elevator")
		await _press_e()
		check(g.get("_menu") == null, "E away from the exit opens nothing")
		eq(player.charges_of(held), 5, "E away from the exit does not cast the held spell")
		near(player.cooldown_left(held), 0.0, 0.0001, "and spends no cooldown")
		# Cash out: the invoice appears and matches the Ledger.
		emp.global_position = Hex.to_world(exit_cell, lv) + Vector3(0.8, 0, 0.5)
		player.global_position = Hex.to_world(exit_cell, lv)
		await frames(4)
		check(g.get("_menu") == null, "walking back does not ask by itself")
		await _press_e()
		menu = g.get("_menu")
		check(menu != null, "E at the exit asks again")
		if menu != null:
			var before := Ledger.earned()
			menu.cash_out.emit()
			await frames(3)
			eq(session.extracted_total, 1, "the follower near the elevator was extracted")
			check(Ledger.earned() >= before + ContractRun.EMPLOYEE_EXTRACTED, "extraction paid $100")
			var inv: InvoiceScreen = g.get("_invoice")
			check(inv != null, "cashing out shows the invoice")
			if inv != null:
				eq(int(inv.inv["payout"]), Ledger.payout(), "the invoice shows the Ledger's payout")
				eq(str(inv.inv["reason"]), ContractSession.END_CASHED_OUT, "reason: cashed out")
				check(int(inv.inv["earned"]) >= run.gate_pay, "the closed gate is on the invoice")
	g.queue_free()
	await frames(3)
	GAME.reset_flow()


## One E key press (the action is held for two physics frames, like a real tap).
func _press_e() -> void:
	Input.action_press("use")
	await frames(2)
	Input.action_release("use")
	await frames(3)


func _check_incapacitated() -> void:
	var g := _make_game({"contract": 2, "seed": 9})
	add_child(g)
	await frames(8)
	var player: Hero = g.get("player")
	var allies: Array[Hero] = g.get("allies")
	player.apply_damage(99999.0)
	await frames(3)
	check(g.get("_invoice") == null, "the contract goes on while an ally is up")
	for a in allies:
		a.apply_damage(99999.0)
	await frames(3)
	check(g.get("_ending") == true, "all heroes down: the contract is ending")
	await get_tree().create_timer(GAME.INCAP_DELAY + 0.5).timeout
	var inv: InvoiceScreen = g.get("_invoice")
	check(inv != null, "all heroes down ends the contract with the invoice")
	if inv != null:
		eq(str(inv.inv["reason"]), ContractSession.END_INCAPACITATED, "the reason is 'crew incapacitated'")
		eq(int(inv.inv["stars"]), 1, "one star")
		eq(int(inv.inv["payout"]), Ledger.payout(), "and it matches the Ledger")
	g.queue_free()
	await frames(3)
	GAME.reset_flow()
