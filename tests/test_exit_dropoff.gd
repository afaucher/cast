extends TestCase
## The two exits and the employee drop-off (docs/design/contracts.md, "Mission structure"):
##  - the van (floor 1 only) and the elevator (every floor) are exits; E opens the exit slip, E never casts;
##  - an employee who is FOLLOWING the crew and walks within DROPOFF_DIST of an exit leaves right away and is paid $100 once,
##    whether or not the crew takes the exit; waiting and cowering employees never do;
##  - a follower still within ~3 cells when the crew takes an exit is extracted at that moment;
##  - the invoice has one "Employee extracted" line per extracted employee and no double count.

const GAME := preload("res://scripts/app/game.gd")

var _g: Node3D


func setup() -> void:
	timeout_sec = 150.0
	await _check_elevator_dropoff()
	await _check_van_dropoff()
	await _check_waiting_and_cowering()
	await _check_exit_extraction()
	await _check_floor2_and_3()
	finish()


# --- helpers ------------------------------------------------------------------------------------------------------------

func _start(extra: Dictionary) -> void:
	_g = load("res://scripts/app/game.gd").new()
	var o := {"no_mic": true, "spells": "heal,corn", "contract": 1, "seed": 5}
	o.merge(extra, true)
	_g.set("opts", o)
	GAME.reset_flow()
	add_child(_g)
	await frames(8)
	var site: SiteBuilder.Site = _g.get("_site")
	for m in site.monsters:
		if is_instance_valid(m):
			m.process_mode = Node.PROCESS_MODE_DISABLED     # nothing interferes with the escort


func _stop() -> void:
	_g.queue_free()
	await frames(3)
	GAME.reset_flow()


func _site() -> SiteBuilder.Site:
	return _g.get("_site")


func _player() -> Hero:
	return _g.get("player")


func _session() -> ContractSession:
	return _g.get("_session")


## Put the employee next to the player and recruit it with the real request (what E does).
func _recruit(emp: Actor) -> bool:
	emp.global_position = _player().global_position + Vector3(1.0, 0.0, 0.0)
	return bool(emp.call("request_follow", _player()))


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, GameWorld.map.ground_level(p) * Hex.LEVEL_HEIGHT, p.z)


func _extracted_lines() -> int:
	var n := 0
	for l in Ledger.lines:
		if str(l["label"]) == "Employee extracted":
			n += 1
	return n


func _alive_lines() -> int:
	var n := 0
	for l in Ledger.lines:
		if str(l["label"]) == "Employee alive at close":
			n += 1
	return n


## At the end, whoever was extracted was paid $100 once, nobody else was paid, and the invoice agrees.
func _check_invoice(extracted: int, tag: String) -> void:
	var s := _session()
	var inv: InvoiceScreen = _g.get("_invoice")
	if not check(inv != null, tag + ": the contract ended with the invoice"):
		return
	eq(str(inv.inv["reason"]), ContractSession.END_CASHED_OUT, tag + ": reason: cashed out")
	eq(s.extracted_total, extracted, tag + ": the session counted %d extracted" % extracted)
	eq(_extracted_lines(), extracted, tag + ": one $100 line per extracted employee")
	eq(_alive_lines(), 0, tag + ": staff left behind pay nothing")
	eq(Ledger.earned(), extracted * ContractRun.EMPLOYEE_EXTRACTED, tag + ": no double count in the total")
	eq(int(inv.inv["payout"]), Ledger.payout(), tag + ": the invoice matches the Ledger")


# --- the elevator drop-off ----------------------------------------------------------------------------------------------

func _check_elevator_dropoff() -> void:
	await _start({"van_intro": false})
	var site := _site()
	var player := _player()
	var emp: Actor = site.employees[0]
	check(_recruit(emp), "recruited the first employee")
	check(bool(emp.call("is_following")), "it follows")
	var exit_cell: Vector2i = _g.get("_exit_cell")
	var lv := GameWorld.map.ground_level(Hex.to_world(exit_cell))
	var exit_pos := Hex.to_world(exit_cell, lv)
	# walk the crew to the elevator without ever taking it: the follower arrives and leaves by itself
	player.global_position = exit_pos
	emp.global_position = exit_pos + Vector3(2.0, 0.0, 0.0)
	await frames(4)
	check(bool(emp.call("is_extracted")), "a follower at the elevator is extracted without taking it")
	eq(_session().extracted_total, 1, "it was counted as extracted")
	eq(_extracted_lines(), 1, "and paid once, at drop-off time")
	eq(Ledger.earned(), ContractRun.EMPLOYEE_EXTRACTED, "$100 earned so far")
	eq(emp.call("bubble_text"), "I'm out, thanks!", "it barks")
	check(_g.get("_menu") == null and not _g.get("_ended"), "nothing opened and the contract goes on")
	var tracker: ObjectiveTracker = _g.get("_tracker")
	var row := _employee_row(tracker)
	check(row.contains("1 rescued") and row.contains("%d alive" % (site.employees.size() - 1)), "the tracker shows it at once (%s)" % row)
	await frames(60)
	eq(_extracted_lines(), 1, "nothing pays it a second time while it fades out")
	eq(_session().extracted_total, 1, "or counts it twice")
	# clock out at the elevator now: the drop-off is not paid again
	_g.call("_open_elevator")
	await frames(2)
	var menu: ElevatorMenu = _g.get("_menu")
	if check(menu != null, "the elevator menu opens"):
		eq(int(menu.info["followers"]), 0, "it offers nobody to take along: the follower already left")
		menu.cash_out.emit()
		await frames(3)
		_check_invoice(1, "elevator")
	await _stop()


func _employee_row(tracker: ObjectiveTracker) -> String:
	for r in tracker.rows:
		if str(r.get("text", "")) == "Employees":
			return str(r.get("detail", ""))
	return ""


# --- the van drop-off ---------------------------------------------------------------------------------------------------

func _check_van_dropoff() -> void:
	await _start({})
	var site := _site()
	var player := _player()
	var van: Dictionary = site.plan.van
	var door: Vector2 = van["door"]
	var out: Vector2 = van["door_normal"]
	var emp: Actor = site.employees[0]
	check(_recruit(emp), "recruited the first employee")
	player.global_position = _ground(Vector3(door.x + out.x * 2.0, 0.0, door.y + out.y * 2.0))
	# one cell's width away from the van door is still outside the drop-off distance
	emp.global_position = _ground(Vector3(door.x + out.x * 4.5, 0.0, door.y + out.y * 4.5))
	await frames(3)
	check(not bool(emp.call("is_extracted")), "a follower 4.5 from the van is not dropped off yet")
	var near_pos := _ground(Vector3(door.x + out.x * 1.6, 0.0, door.y + out.y * 1.6))
	emp.global_position = near_pos
	await frames(3)
	check(bool(emp.call("is_extracted")), "a follower at the van door is extracted without clocking out")
	eq(_session().extracted_total, 1, "counted once")
	eq(_extracted_lines(), 1, "paid once, when it left")
	eq(emp.call("bubble_text"), "I'm out, thanks!", "with the bark")
	check(not _g.get("_ended"), "the contract goes on")
	# now clock out at the van
	check(_g.call("_player_at_van"), "the player stands at the van")
	_g.call("_open_van_exit")
	await frames(2)
	var menu: VanExitMenu = _g.get("_van_menu")
	if check(menu != null, "the van slip opens"):
		eq(int(menu.info["followers"]), 0, "nobody left to take along")
		menu.clock_out.emit()
		await frames(3)
		_check_invoice(1, "van")
	await _stop()


# --- waiting and cowering employees do not leave ------------------------------------------------------------------------

func _check_waiting_and_cowering() -> void:
	await _start({})
	var site := _site()
	var player := _player()
	var exit_cell: Vector2i = _g.get("_exit_cell")
	var exit_pos := Hex.to_world(exit_cell, GameWorld.map.ground_level(Hex.to_world(exit_cell)))
	var waiter: Actor = site.employees[0]
	var cower: Actor = site.employees[1]
	check(_recruit(waiter), "recruited one employee")
	check(bool(waiter.call("request_wait", player)), "and told it to wait")
	waiter.global_position = exit_pos + Vector3(1.0, 0.0, 0.0)
	cower.global_position = exit_pos + Vector3(-1.0, 0.0, 0.0)
	player.global_position = exit_pos + Vector3(0.0, 0.0, 1.0)
	await frames(30)
	check(not bool(waiter.call("is_extracted")), "a waiting employee at the elevator stays")
	check(not bool(cower.call("is_extracted")), "a cowering employee at the elevator stays")
	eq(_session().extracted_total, 0, "nobody was extracted")
	eq(_extracted_lines(), 0, "and nothing was paid")
	# leaving now: they are alive ($10), not extracted ($100)
	_g.call("_open_elevator")
	await frames(2)
	var menu: ElevatorMenu = _g.get("_menu")
	if check(menu != null, "the elevator menu opens"):
		eq(int(menu.info["followers"]), 0, "it takes no one along")
		menu.cash_out.emit()
		await frames(3)
		_check_invoice(0, "waiting")
	await _stop()


# --- followers still with the crew when it takes an exit ----------------------------------------------------------------

func _check_exit_extraction() -> void:
	# the elevator: a follower 4 units away (inside ~3 cells, outside the drop-off distance)
	await _start({})
	var site := _site()
	var player := _player()
	var exit_cell: Vector2i = _g.get("_exit_cell")
	var exit_pos := Hex.to_world(exit_cell, GameWorld.map.ground_level(Hex.to_world(exit_cell)))
	var emp: Actor = site.employees[0]
	check(_recruit(emp), "recruited an employee")
	player.global_position = exit_pos
	var far := exit_pos + Vector3(4.0, 0.0, 0.0)
	if GameWorld.map.get_cell(Hex.from_world(far)) == null or GameWorld.map.get_cell(Hex.from_world(far)).type != HexMap.Tile.FLOOR:
		far = exit_pos + Vector3(-4.0, 0.0, 0.0)
	emp.global_position = _ground(far)
	_g.call("_open_elevator")           # same frame: the world has not stepped, the follower is still 4 units away
	var menu: ElevatorMenu = _g.get("_menu")
	if check(menu != null, "the elevator menu opens"):
		eq(int(menu.info["followers"]), 1, "the menu counts the follower riding along")
		menu.cash_out.emit()
		await frames(3)
		check(bool(emp.call("is_extracted")), "the follower is extracted when the crew exits")
		_check_invoice(1, "elevator exit")
	await _stop()
	# the van
	await _start({})
	site = _site()
	player = _player()
	var van: Dictionary = site.plan.van
	var door: Vector2 = van["door"]
	var out: Vector2 = van["door_normal"]
	emp = site.employees[0]
	check(_recruit(emp), "recruited an employee")
	player.global_position = _ground(Vector3(door.x + out.x * 2.0, 0.0, door.y + out.y * 2.0))
	emp.global_position = _ground(Vector3(door.x + out.x * 4.0, 0.0, door.y + out.y * 4.0))
	_g.call("_open_van_exit")
	menu = null
	var vmenu: VanExitMenu = _g.get("_van_menu")
	if check(vmenu != null, "the van slip opens"):
		eq(int(vmenu.info["followers"]), 1, "the slip counts the follower riding along")
		vmenu.clock_out.emit()
		await frames(3)
		check(bool(emp.call("is_extracted")), "the follower is extracted when the crew clocks out at the van")
		_check_invoice(1, "van exit")
	await _stop()


# --- floors 2 and 3 -----------------------------------------------------------------------------------------------------

func _check_floor2_and_3() -> void:
	for f in [2, 3]:
		await _start({"floor": f})
		var site := _site()
		var player := _player()
		var emp: Actor = site.employees[0]
		check(not bool(_g.call("_has_van")), "floor %d: no van" % f)
		check(_recruit(emp), "floor %d: recruited an employee" % f)
		var exit_cell: Vector2i = _g.get("_exit_cell")
		var exit_pos := Hex.to_world(exit_cell, GameWorld.map.ground_level(Hex.to_world(exit_cell)))
		player.global_position = exit_pos
		emp.global_position = exit_pos + Vector3(1.5, 0.0, 0.0)
		await frames(4)
		check(bool(emp.call("is_extracted")), "floor %d: the elevator drop-off works" % f)
		eq(_extracted_lines(), 1, "floor %d: paid once" % f)
		await _stop()
