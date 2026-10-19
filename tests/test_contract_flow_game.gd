extends TestCase
## The contract flow inside the real game scene: the job board, a floor with its site and objective
## tracker, the elevator menu (go down / exit / stay; exit only on floor 3), the van's clock-out slip (floor 1 only), and
## "crew incapacitated" ending in the invoice.
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
	await _check_van_exit()
	await _check_use_prompt()
	await _check_elevator_floors()
	await _check_downed_stays_behind()
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
		var first_run: ContractRun = board.offers[0]
		var names: Array[String] = []
		for o in board.offers:
			names.append(o.client_name)
		board.sign_hold = 0.0
		board.choose(0)
		await frames(3)
		check(g.get("_session") != null, "taking an offer starts the contract")
		eq(g.get("_session").floor_number, 1, "on floor 1")
		eq(Ledger.contract_value, first_value, "the Ledger carries the contract value")
		check(g.get("hud") != null, "the world was built after picking")
		# Back out of the license checkout: the job is dropped and the board comes back with the same offers.
		var picker: SpellPicker = g.get("_picker")
		check(picker != null, "the license requisition is open")
		if picker != null:
			eq(picker._sheet.header.form_no_label.text, "15", "FORM 15 at a contract start")
			eq(picker._sheet.header.copy_value.text, first_run.invoice_number.replace("INV-", ""), "the job number is typed in")
			eq((picker._fields["client"] as Label).text, first_run.company, "and the client")
			eq((picker._fields["issued_to"] as Label).text, JobBoard.signer_name(), "issued to the player")
		var went: Array[String] = []
		g.set("scene_changer", func(path: String) -> void: went.append(path))
		if picker != null:
			picker.cancelled.emit()
		await frames(2)
		eq(went, ["" as String], "backing out reloads the job board")
		check(g.get("_session") == null and not Ledger.active, "no contract is running after backing out")
		g.queue_free()
		await frames(3)
		var g2: Node3D = load("res://scripts/app/game.gd").new()
		g2.set("opts", {"no_mic": true})     # no seed: the remembered board seed decides
		add_child(g2)
		await frames(2)
		var again: Array[String] = []
		for layer in g2.get_children():
			if layer is CanvasLayer:
				for c in layer.get_children():
					if c is JobBoard:
						for o in (c as JobBoard).offers:
							again.append(o.client_name)
		eq(again, names, "the same three offers are back")
		g2.queue_free()
		await frames(3)
	else:
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

	# The elevator needs a key press. Stepping onto the exit only shows the elevator use prompt; E there opens the
	# menu (and does not cast); E anywhere else does nothing (E never casts).
	var player: Hero = g.get("player")
	var exit_cell: Vector2i = g.get("_exit_cell")
	var lv := GameWorld.map.ground_level(Hex.to_world(exit_cell))
	var held := player.held_spell()
	check(held != "", "a spell is held")
	player.set_charges(held, 5)
	player.global_position = Hex.to_world(exit_cell, lv)
	await frames(6)
	check(g.get("_menu") == null, "stepping on the exit does NOT open the elevator menu")
	eq(_prompt_text(g), "E Elevator", "standing on the exit shows the E prompt")
	player.global_position = Hex.to_world(exit_cell + Hex.DIRS[0], GameWorld.map.ground_level(Hex.to_world(exit_cell + Hex.DIRS[0])))
	await frames(4)
	check(g.get("_menu") == null and _prompt_text(g) != "", "next to the exit: the prompt shows, still no menu")
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
		eq(_prompt_text(g), "", "no prompt away from the elevator")
		await _press_e()
		check(g.get("_menu") == null, "E away from the exit opens nothing")
		eq(player.charges_of(held), 5, "E away from the exit does not cast the held spell")
		near(player.cooldown_left(held), 0.0, 0.0001, "and spends no cooldown")
		# Exit: the invoice appears and matches the Ledger. (The follower walks to the elevator and is dropped off by
		# itself; test_exit_dropoff covers the drop-off and the exit extraction in detail.)
		emp.global_position = Hex.to_world(exit_cell, lv) + Vector3(0.8, 0, 0.5)
		player.global_position = Hex.to_world(exit_cell, lv)
		await frames(4)
		check(g.get("_menu") == null, "walking back does not ask by itself")
		await _press_e()
		menu = g.get("_menu")
		check(menu != null, "E at the exit asks again")
		if menu != null:
			menu.cash_out.emit()
			await frames(3)
			eq(session.extracted_total, 1, "the follower near the elevator was extracted (once)")
			var banner: DispatchBanner = g.get("_banner")
			check(banner != null and not banner.line.is_empty() and not banner.line.contains("$"), "dispatch calls in the rescue on the headset (%s)" % (banner.line if banner != null else "no banner"))
			check(Ledger.earned() >= run.gate_pay + ContractRun.EMPLOYEE_EXTRACTED, "extraction paid $100")
			var inv: InvoiceScreen = g.get("_invoice")
			check(inv != null, "cashing out shows the invoice")
			if inv != null:
				eq(int(inv.inv["payout"]), Ledger.payout(), "the invoice shows the Ledger's payout")
				eq(str(inv.inv["reason"]), ContractSession.END_CASHED_OUT, "reason: cashed out")
				var garage: MenuBackdrop = g.get("_backdrop")
				check(garage != null and garage.camera.current and inv.backdrop_behind, "the garage is behind the invoice")
				check(not (GameWorld.root as Node3D).visible, "and the floor is hidden")
				check(int(inv.inv["earned"]) >= run.gate_pay, "the closed gate is on the invoice")
	g.queue_free()
	await frames(3)
	GAME.reset_flow()


## The van (floor 1 only) is an exit too: E at its side door opens the clock-out slip, the prompt says so, E never casts, the
## van wins over the elevator, Cancel closes it, and confirming ends the contract like the elevator's exit.
func _check_van_exit() -> void:
	var g := _make_game({"contract": 1, "seed": 5})
	add_child(g)
	await frames(10)
	var run: ContractRun = g.get("_run")
	var site: SiteBuilder.Site = g.get("_site")
	var player: Hero = g.get("player")
	var session: ContractSession = g.get("_session")
	check(bool(g.call("_has_van")), "floor 1 has the van")
	var door: Vector2 = site.plan.van["door"]
	var out: Vector2 = site.plan.van["door_normal"]
	var held := player.held_spell()
	player.set_charges(held, 5)
	var spot := Vector3(door.x + out.x * 2.0, 0.0, door.y + out.y * 2.0)
	player.global_position = Vector3(spot.x, GameWorld.map.ground_level(spot) * Hex.LEVEL_HEIGHT, spot.z)
	await frames(6)
	eq(_prompt_text(g), "E Clock out", "at the van's side door the prompt offers to clock out")
	check(g.get("_van_menu") == null and g.get("_menu") == null, "walking up opens nothing by itself")
	# a gate closed first, so the invoice has something on it
	var gate: Actor = site.gates[0]
	gate.apply_damage(99999.0, player)
	await frames(4)
	await _press_e()
	var vm: VanExitMenu = g.get("_van_menu")
	if not check(vm != null, "E at the van opens the clock-out slip"):
		g.queue_free()
		await frames(3)
		GAME.reset_flow()
		return
	check(g.get("_menu") == null, "(not the elevator's)")
	eq(player.charges_of(held), 5, "E at the van does not cast the held spell")
	eq(GameWorld.root.process_mode, Node.PROCESS_MODE_DISABLED, "the world is frozen while the slip is open")
	vm.cancel.emit()
	await frames(3)
	check(g.get("_van_menu") == null and g.get("_invoice") == null, "Cancel closes the slip and the contract goes on")
	check(GameWorld.root.process_mode != Node.PROCESS_MODE_DISABLED, "and the world runs again")
	# the van wins over the elevator when the crew stands at both
	var door_cell := Hex.from_world(Vector3(door.x, 0.0, door.y))
	g.set("_exit_cell", door_cell)
	await frames(4)
	eq(_prompt_text(g), "E Clock out", "the van's prompt wins over the elevator's")
	await _press_e()
	check(g.get("_van_menu") != null and g.get("_menu") == null, "E opens the van slip first, not the elevator menu")
	vm = g.get("_van_menu")
	var van_allies: Array[Hero] = g.get("allies")
	van_allies[0].apply_damage(99999.0)   # one ally is down when the crew clocks out: corporate revives them, the client pays
	await frames(2)
	vm.clock_out.emit()
	await frames(3)
	var inv: InvoiceScreen = g.get("_invoice")
	if check(inv != null, "clocking out at the van shows the invoice"):
		eq(int(inv.inv["revival_fees"]), Ledger.REVIVAL_FEE, "a cash-out with one ally down bills $10,000")
		eq((inv.inv["revivals"] as Array).size(), 1, "one revival row, naming the downed ally")
		eq(str(inv.inv["reason"]), ContractSession.END_CASHED_OUT, "the van's exit ends the contract like the elevator's")
		eq(int(inv.inv["payout"]), Ledger.payout(), "the invoice matches the Ledger")
		eq(int(inv.inv["earned"]), run.gate_pay, "the closed gate only; staff left behind and unfinished objectives pay nothing")
	check(session.finished, "the session is finished")
	g.queue_free()
	await frames(3)
	GAME.reset_flow()


## The use prompt floats over exactly what E acts on: the same UseTarget decides the prompt and the press. Van, elevator,
## employee, nothing in range (hidden), and F's swap prompt over a pickup.
func _check_use_prompt() -> void:
	var g := _make_game({"contract": 1, "seed": 5})
	add_child(g)
	await frames(10)
	var site: SiteBuilder.Site = g.get("_site")
	var player: Hero = g.get("player")
	var pc: PlayerController = g.get("controller")
	var prompt: UsePrompt = g.get("_use_prompt")
	if not check(prompt != null and prompt.get_parent() == g, "the game owns one E use prompt"):
		g.queue_free()
		await frames(3)
		GAME.reset_flow()
		return
	# nothing in range: hidden, and E does nothing
	var exit_cell: Vector2i = g.get("_exit_cell")
	var lv := GameWorld.map.ground_level(Hex.to_world(exit_cell))
	player.global_position = Hex.to_world(exit_cell, lv) + Vector3(8, 0, 8)
	await frames(30)
	check(g.call("use_target") == null, "nothing in range: no use target")
	check(not prompt.wanted and prompt.alpha == 0.0, "nothing in range: the prompt is hidden")
	check(not pc.press_use(), "nothing in range: E does nothing")

	# the van
	var door: Vector2 = site.plan.van["door"]
	var out: Vector2 = site.plan.van["door_normal"]
	var spot := Vector3(door.x + out.x * 2.0, 0.0, door.y + out.y * 2.0)
	player.global_position = Vector3(spot.x, GameWorld.map.ground_level(spot) * Hex.LEVEL_HEIGHT, spot.z)
	await frames(30)
	var t: Object = g.call("use_target")
	if check(t != null and t.kind == "van", "at the van's door E targets the van"):
		check(prompt.wanted and prompt.key == "E" and prompt.verb == t.verb and prompt.verb == "Clock out", "the prompt shows [E] Clock out")
		check(prompt.alpha > 0.95, "and it has faded in")
		near(prompt.global_position.x, door.x, 0.01, "over the van door (x)")
		near(prompt.global_position.z, door.y, 0.01, "over the van door (z)")
		check(pc.press_use() and g.get("_van_menu") != null and g.get("_menu") == null, "E does what the prompt said: opens the clock-out slip")
		check(g.call("use_target") == null, "with the slip open there is no target")
		g.get("_van_menu").cancel.emit()
		await frames(30)
		check(g.get("_van_menu") == null and prompt.wanted and prompt.verb == "Clock out", "the slip closed and the prompt is back over the van")

	# the elevator (away from the van)
	player.global_position = Hex.to_world(exit_cell, lv)
	await frames(30)
	t = g.call("use_target")
	if check(t != null and t.kind == "elevator", "on the exit E targets the elevator"):
		check(prompt.wanted and prompt.key == "E" and prompt.verb == t.verb and prompt.verb == "Elevator", "the prompt shows [E] Elevator")
		var ex := Hex.to_world(exit_cell)
		near(prompt.global_position.x, ex.x, 0.01, "over the elevator (x)")
		check(pc.press_use() and g.get("_menu") != null, "E does what the prompt said: opens the elevator menu")
		g.get("_menu").stay.emit()
		await frames(10)

	# an employee
	var emp: Employee = site.employees[0]
	player.global_position = emp.global_position + Vector3(1.0, 0, 0)
	await frames(6)
	player.global_position = emp.global_position + Vector3(1.0, 0, 0)   # it may have fled a monster: step up again
	await frames(30)
	t = g.call("use_target")
	if check(t != null and t.kind == "employee", "next to an employee E targets them"):
		check(t.employee == Employee.interact_target(player), "the same employee Employee.interact acts on")
		check(prompt.wanted and prompt.key == "E" and prompt.verb == t.verb, "the prompt shows the target's verb")
		check(prompt.verb == "Bring %s" % emp.display_name, "[E] Bring <name> for a cowering employee")
		check(prompt.global_position.y > emp.global_position.y + 1.0, "floating above the employee")
		check(pc.press_use() and emp.is_following(), "E does what the prompt said: brings them along")
		await frames(30)
		t = g.call("use_target")
		if check(t != null and t.kind == "employee", "a follower is still the target"):
			check(prompt.verb == "Tell %s to wait" % emp.display_name, "[E] Tell <name> to wait for your follower")
	g.queue_free()
	await frames(3)
	GAME.reset_flow()

	# E: the swap offer (was F; user, 2026-10-18). Away from the van and the elevator, whose E comes first.
	var g2 := _make_game({"contract": 1, "seed": 5})
	add_child(g2)
	await frames(10)
	var p2: Hero = g2.get("player")
	var fp: UsePrompt = g2.get("_use_prompt")
	var map: HexMap = GameWorld.map
	var start: Vector2i = map.cells_with_tag("start")[0]
	var exit_c: Vector2i = g2.get("_exit_cell")
	for c: Vector2i in map.cells:
		var cell: HexMap.Cell = map.get_cell(c)
		if cell.type != HexMap.Tile.FLOOR or Hex.distance(c, start) < 6 or Hex.distance(c, exit_c) < 4:
			continue
		p2.global_position = Hex.to_world(c, cell.level)
		if g2.call("use_target") == null:
			break   # (nothing else for E here: no note, employee, van or elevator)
	p2.slot_in("fireball", 3)
	p2.slot_in("armor", 3)
	check(p2.spell_slots.size() == SpellComponents.SLOT_COUNT, "all slots are full")
	await frames(30)
	check(fp != null and not _prompt_text(g2).begins_with("E Swap"), "no pickup near: no swap prompt")
	var pickup := ComponentPickup.drop("tentacles", 3, p2.global_position + Vector3(0.9, 0.0, 0.55))
	await frames(30)
	if check(pickup != null and p2.swap_target() == pickup, "the pickup is offered for a swap"):
		eq(_prompt_text(g2), "E Swap in %s" % SpellBook.component_name("tentacles"), "the prompt shows [E] Swap in <component>")
		check(fp.global_position.y > pickup.global_position.y + 1.0, "floating above the pickup")
		await _press_e()
		eq(p2.slot_spell(p2.held_slot), "tentacles", "E does what the prompt said")
		await frames(30)
		check(not _prompt_text(g2).begins_with("E Swap"), "and the prompt goes away")
	g2.queue_free()
	await frames(3)
	GAME.reset_flow()


## A hero who is down when the crew rides the elevator stays behind (user, 2026-10-18): on the next floor it is still down
## but neither rides the car nor shows, and a downed player watches a living ally. The revival is still billed at the end.
func _check_downed_stays_behind() -> void:
	for who in ["ally", "player"]:
		var g := _make_game({"contract": 1, "seed": 5})
		add_child(g)
		await frames(10)
		var seats: Dictionary = g.get("heroes_by_seat")
		var down: Hero = g.get("player") if who == "player" else seats[2]
		down.apply_damage(999999.0)
		await frames(2)
		check(down.dead, "%s: down on floor 1" % who)
		# what _use_elevator(true) does before the scene reloads
		var s: ContractSession = g.get("_session")
		s.save_carry(g.call("_heroes"))
		s.floor_number += 1
		g.queue_free()
		await frames(2)
		var g2: Node3D = load("res://scripts/app/game.gd").new()   # (the reload: same flow, no reset)
		g2.set("opts", {"no_mic": true, "spells": "heal,corn"})
		add_child(g2)
		await frames(10)
		eq(g2.get("_session").floor_number, 2, "%s: on floor 2" % who)
		var seats2: Dictionary = g2.get("heroes_by_seat")
		var player2: Hero = g2.get("player")
		var down2: Hero = player2 if who == "player" else seats2[2]
		check(down2.dead and not down2.visible, "%s: still down, and the body stayed upstairs (hidden)" % who)
		var lift: ElevatorArrival = g2.get("_lift")
		check(lift != null and lift.crew.size() == 2 and not lift.crew.has(down2), "%s: only the living two rode the elevator" % who)
		for h: Hero in g2.call("_heroes"):
			if h != down2:
				check(h.visible and not h.dead, "%s: %s arrived" % [who, h.display_name])
		if who == "player":
			var rig: Node = g2.get("rig")
			check(rig.target != null and rig.target != player2 and not (rig.target as Hero).dead, "a downed player watches a living ally")
		g2.queue_free()
		await frames(2)
		GAME.reset_flow()


## The elevator on floors 2 and 3: floor 2 offers going down and exit, floor 3 offers exit only. Neither floor has a van or an
## arrival: the crew starts at the elevator it rode down in (user, 2026-10-18), and closing the floor-3 origin gate does not
## end the contract by itself.
func _check_elevator_floors() -> void:
	for f in [2, 3]:
		var g := _make_game({"contract": 1, "seed": 5, "floor": f})
		add_child(g)
		await frames(10)
		var site: SiteBuilder.Site = g.get("_site")
		var player: Hero = g.get("player")
		eq(g.get("_session").floor_number, f, "floor %d: started there" % f)
		check(g.get("_arrival") == null and not bool(g.call("_has_van")) and site.plan.van.is_empty(), "floor %d: no van and no arrival" % f)
		check(g.get("controller").enabled and player.visible, "floor %d: the crew simply starts, in control" % f)
		check(_prompt_text(g) != "E Clock out", "floor %d: no van prompt at the start" % f)
		check(Hex.distance(player.current_cell(), g.get("_exit_cell")) <= 2, "floor %d: the crew starts at the elevator" % f)
		eq(_prompt_text(g), "E Elevator", "floor %d: standing at the elevator on arrival" % f)
		var lift: ElevatorArrival = g.get("_lift")
		check(lift != null and lift.is_done() and lift.crew.size() == 3, "floor %d: the crew came down in the elevator (its beat is skipped in tests)" % f)
		# E works in the doorway and in the car too, for either placement
		var e: Dictionary = site.plan.elevator
		for spot: Vector2 in [e["door"], (e["inside"] as Array)[1]]:
			player.global_position = Vector3(spot.x, player.global_position.y, spot.y)
			await frames(4)
			eq(_prompt_text(g), "E Elevator", "floor %d: E Elevator at %s" % [f, "the door" if spot == e["door"] else "a spot in the car"])
		if f == 3:
			var origin: Actor = site.origin_gate
			if check(origin != null, "floor 3 has the origin gate"):
				origin.apply_damage(9999999.0, player)
				await frames(30)
				check(g.get("_session").state()["origin_closed"], "the origin gate closed")
				check(g.get("_invoice") == null and not g.get("_ended"), "closing the origin gate does not end the contract by itself")
		var exit_cell: Vector2i = g.get("_exit_cell")
		var lv := GameWorld.map.ground_level(Hex.to_world(exit_cell))
		player.global_position = Hex.to_world(exit_cell, lv)
		await frames(6)
		eq(_prompt_text(g), "E Elevator", "floor %d: the elevator prompt" % f)
		await _press_e()
		var menu: ElevatorMenu = g.get("_menu")
		if check(menu != null, "floor %d: E at the exit opens the elevator menu" % f):
			if f == 2:
				check(menu.can_descend() and menu._rows.size() == 3, "floor 2: go down / exit / stay")
			else:
				check(not menu.can_descend() and menu._rows.size() == 2, "floor 3: exit / stay, nothing further down")
			menu.cash_out.emit()
			await frames(3)
			var inv: InvoiceScreen = g.get("_invoice")
			check(inv != null, "floor %d: the elevator's exit ends the contract with the invoice" % f)
			if inv != null:
				eq(str(inv.inv["reason"]), ContractSession.END_CASHED_OUT, "floor %d: reason: cashed out" % f)
				eq(int(inv.inv["payout"]), Ledger.payout(), "floor %d: the invoice matches the Ledger" % f)
		g.queue_free()
		await frames(3)
		GAME.reset_flow()


## What the E use prompt says ("E Clock out") while it is up, "" while it is hidden or fading out.
func _prompt_text(g: Node) -> String:
	var p: UsePrompt = g.get("_use_prompt")
	return "" if p == null or not p.wanted else "%s %s" % [p.key, p.verb]


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
		eq(int(inv.inv["revival_fees"]), 3 * Ledger.REVIVAL_FEE, "all three heroes down: corporate bills 3 x $10,000")
		eq((inv.inv["revivals"] as Array).size(), 3, "one revival row per hero, the player's included")
		check(int(inv.inv["payout"]) < 0, "so the net payout is negative")
		eq(int(inv.inv["payout"]), Ledger.payout(), "and it matches the Ledger")
	g.queue_free()
	await frames(3)
	GAME.reset_flow()
