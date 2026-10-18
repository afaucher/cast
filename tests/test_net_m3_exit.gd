extends NetGameTest
## M3 (the user's "the elevator goes with the first player to choose"), three processes, `off` and `coast`: the exits are
## first-to-choose and the crew follows the one decision.
##
## - both clients pick "go down" in the elevator menu at the same shared moment: the host takes the FIRST choice and
##   drops the other, so every machine sees exactly one decision, by the same player; every machine reloads onto floor 2
##   (the game's own scene reload, done by the test seam), builds it behind the barrier again (no board, no license),
##   with the same checksum, and the floor starts for all three (crew.next, crew.ready, crew.go); each hero's HP carried
##   over by seat;
## - on floor 2 the host and c2 both clock out at once: one decision, and every machine shows the HOST's invoice (the same
##   payout, earnings, damages, floor reached and reason) while the clients' Ledgers mirror the host's to the dollar.

const PEERS := 3
const SEED := 13

## Every exit decision this machine saw: [choice, seat].
var decisions: Array = []


func run_host() -> void:
	follow_reloads = true
	Session.objects.exit_decided.connect(func(c: String, seat: int) -> void: decisions.append([c, seat]))
	if not await enter_floor(SEED, 1):
		return
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	if not await wait_sync():
		return
	check(await wait_reports("ready", 2, 30.0), "both clients are on floor 1")
	var c1 := _peer_named("c1")
	var c2 := _peer_named("c2")
	var hurt := {1: 85.0 - 7.0}
	my_hero().hp = hurt[1]   # (this test's own hero: a mark to find on floor 2)

	# 1. Both clients choose "down" at once.
	var t := Session.host_time() + 0.7
	command(c1, "choose", {"c": "down", "t": t})
	command(c2, "choose", {"c": "down", "t": t})
	check(await until(func() -> bool: return reloads >= 1, 10.0), "the host followed the decision onto the next floor")
	eq(decisions.size(), 1, "the host made exactly one decision")
	var decided: Array = decisions[0] if not decisions.is_empty() else ["", 0]
	eq(str(decided[0]), "down", "... to go down")
	check(int(decided[1]) == 2 or int(decided[1]) == 3, "... chosen by a client (seat %d)" % int(decided[1]))
	if not check(await wait_floor(40.0), "floor 2 starts for the host"):
		return
	eq(int((game.get("_session") as ContractSession).floor_number), 2, "the host is on floor 2")
	check(await wait_reports("floor2", 2, 40.0), "both clients reached floor 2")
	eq(flow().desyncs.size(), 0, "nobody built a different floor 2")
	for p in [c1, c2]:
		var r: Dictionary = reported(p, "floor2")
		var who := "c1" if p == c1 else "c2"
		eq(int(r["floor"]), 2, "%s is on floor 2" % who)
		eq(str(r["sum"]), str(flow().local_sums.get("all", "")), "%s built the same floor 2 (checksum)" % who)
		eq(str(r["decisions"]), str(decisions), "%s saw the same one decision" % who)
		near(float((r["hp"] as Dictionary)[1]), my_hero().hp, 0.2, "%s shows the host's hero with its carried HP" % who)
		eq(int(r["reloads"]), 1, "%s reloaded once" % who)
	near(my_hero().hp, float(hurt[1]), 0.2, "the host's hero kept its HP on floor 2 (carry by seat)")
	# floor 2 starts with the crew stepping out of the elevator (its beat, from the shared clock): over on every machine
	var lift: ElevatorArrival = game.get("_lift")
	check(lift != null and lift.crew.size() == 3, "floor 2: the crew came down in the elevator")
	check(lift != null and await until(func() -> bool: return lift.is_done(), 6.0), "floor 2: and stepped out")
	for p in [c1, c2]:
		eq(str((reported(p, "floor2") as Dictionary).get("elev", "")), _elev_text(), "%s shows the same elevator, done arriving" % ("c1" if p == c1 else "c2"))
	if not await wait_sync():
		return
	check(Session.world.active and Session.world.tracked_ids().size() > 10, "the host streams floor 2's world (%d actors)" % Session.world.tracked_ids().size())

	# 2. The host and c2 clock out at once.
	decisions.clear()
	command(c1, "reset")
	command(c2, "reset")
	await sleep(0.3)
	t = Session.host_time() + 0.6
	command(c2, "choose", {"c": "out", "t": t})
	await until(func() -> bool: return Session.host_time() >= t, 5.0)
	game.call("_choose_exit", "out")
	check(await until(func() -> bool: return bool(game.get("_ended")), 6.0), "the contract ended on the host")
	eq(decisions.size(), 1, "one decision")
	var inv: Dictionary = game.get("_last_invoice")
	check(not inv.is_empty(), "the host shows its invoice")
	for p in [c1, c2]:
		command(p, "invoice")
	check(await wait_reports("invoice", 2, 20.0), "both clients report their invoice")
	for p in [c1, c2]:
		var r: Dictionary = reported(p, "invoice")
		var who := "c1" if p == c1 else "c2"
		check(bool(r["ended"]), "%s's contract ended" % who)
		for k in ["payout", "earned", "damages", "floor_reached", "reason", "number", "stars"]:
			eq(str((r["inv"] as Dictionary).get(k, "?")), str(inv.get(k, "")), "%s's invoice shows the host's %s" % [who, k])
		eq(int(r["ledger_payout"]), Ledger.payout(), "%s's Ledger mirrors the host's to the dollar" % who)
		eq(str(r["decisions"]), str(decisions), "%s saw the same one decision" % who)
	print("[M3] exits: down chosen by seat %d; the invoice: floor %d, payout %d" % [int(decided[1]), int(inv.get("floor_reached", 0)), int(inv.get("payout", 0))])
	for p in [c1, c2]:
		command(p, "end")
	check(await wait_done(2, 30.0), "both clients are done")


func run_client() -> void:
	follow_reloads = true
	Session.objects.exit_decided.connect(func(c: String, seat: int) -> void: decisions.append([c, seat]))
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(90.0)
		match str(cmd.get("cmd", "")):
			"choose":
				var c := str(cmd["c"])
				await until(func() -> bool: return Session.host_time() >= float(cmd["t"]), 5.0)
				game.call("_choose_exit", c)
				if c == "down":
					check(await until(func() -> bool: return reloads >= 1, 10.0), "this client followed the crew down")
					check(await wait_floor(40.0), "floor 2 starts here")
					await wait_sync()
					var hp := {}
					for seat in [1, 2, 3]:
						if hero_at(seat) != null:
							hp[seat] = hero_at(seat).hp
					report("floor2", {"floor": int((game.get("_session") as ContractSession).floor_number), "sum": flow().local_sums.get("all", ""),
						"decisions": decisions.duplicate(), "hp": hp, "reloads": reloads, "elev": _elev_text()})
			"reset":
				decisions.clear()
			"invoice":
				await until(func() -> bool: return bool(game.get("_ended")), 6.0)
				report("invoice", {"ended": bool(game.get("_ended")), "inv": game.get("_last_invoice"), "ledger_payout": Ledger.payout(),
					"decisions": decisions.duplicate()})
			_:
				running = false


## This machine's elevator on the floor: look, placement, landing and whether its arrival is over.
func _elev_text() -> String:
	var lift: ElevatorArrival = game.get("_lift")
	if lift == null:
		return "none"
	return "%s/%s/%s/%s" % [lift.plan["look"], lift.plan["place"], str(lift.plan["landing"]), str(lift.is_done())]


func _peer_named(n: String) -> int:
	for p: int in Session.roster:
		if str(Session.roster[p]["name"]) == n:
			return p
	return 0
