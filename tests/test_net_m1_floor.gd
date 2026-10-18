extends NetGameTest
## M1 "done when" (networking-build-plan.md), three processes, `off` and `coast`: the host's job board reaches
## every client, the host takes a job, everyone signs their own license, and the floor starts on every machine
## from the same seed behind a load barrier.
##
## - the board: the host's three offers on every process (clients read-only), and the host's highlighted card;
## - the job: the same contract everywhere; each player signs their OWN two spells, the first signers see
##   "waiting for <name>", and the roster on every process holds everyone's spells;
## - the floor: the checksums (map, site plan, contract, spawn table) match on all three, the floor starts on the
##   shared clock, and clients' GameWorld.time tracks the host's within a frame and the link;
## - the van arrival plays on every machine from that shared start;
## - what the host owns is a non-acting COPY on a client (no AI, no damage), the same entities as on the host; each
##   machine controls exactly one hero and only the host runs the AI heroes. (M3: a copy is no longer frozen: it shows the
##   host's world, so at the end of the watch every copy stands where the host has it and has the host's HP.)

const PEERS := 3
const SEED := 11
const SIGN_AT := [2.6, 0.6, 1.4]      ## seconds after the checkout opens that host / c1 / c2 sign: the host last
const WATCH := 3.2                     ## seconds measured after the floor starts


func run_host() -> void:
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 20.0), "both clients join"):
		return
	make_game({"seed": SEED})
	if not check(await wait_board(), "the host has a job board"):
		return
	var b := board()
	check(not b.read_only, "the host's board is its to pick from")
	var mine := offers_signature(b.offers)
	eq(mine, offers_signature(ContractBoard.offers(SEED)), "the host's offers are the board's offers for its seed")
	check(await wait_reports("board", 2, 25.0), "both clients report their board")
	for p in peers_with("board"):
		var r: Dictionary = reported(p, "board")
		eq(str(r["offers"]), mine, "peer %d draws the host's three offers" % p)
		eq(int(r["seed"]), SEED, "peer %d's board was dealt from the host's seed" % p)
		check(bool(r["read_only"]), "peer %d's board is read-only" % p)
		check(bool(r["note"]), "peer %d's board says the host picks" % p)
		check(not bool(r["picked"]), "peer %d clicking a card picks nothing" % p)

	# The host's highlighted card follows to the clients.
	b.set_highlight(2)
	check(await wait_reports("hi", 2), "both clients follow the host's highlighted card")

	# The host takes a job: everyone moves to their own license checkout with the same contract.
	b.choose(1)
	check(await wait_reports("job", 2), "both clients report the contract they built")
	var run: ContractRun = game.get("_run")
	var job := run_signature(run)
	eq(run_signature(ContractBoard.offers(SEED)[1]), job, "the host took the second offer")
	for p in peers_with("job"):
		eq(str(reported(p, "job")), job, "peer %d builds the host's contract" % p)
	check(await wait_picker(), "the host has a license checkout")
	check(not picker().back_text.begins_with("Leave"), "the host's checkout goes back to the board")
	await sleep(SIGN_AT[0])
	check(await sign_license(my_license()), "the host signs its license last")
	check(await wait_reports("waited", 2), "both clients report what they saw while waiting")
	for p in peers_with("waited"):
		check(bool(reported(p, "waited")), "peer %d saw 'waiting for ...' while the others signed" % p)

	# Load barrier -> shared start.
	check(await wait_floor(), "the host's floor starts")
	var mine_floor := await measure()
	check(await wait_reports("floor", 2, 30.0), "both clients report the floor")
	var limit := 33.0 if link == "off" else 50.0
	var host_sums: Dictionary = flow().local_sums
	var ours: Dictionary = mine_floor
	check(float(ours["time_err_ms"]) < 20.0, "the host's own floor clock follows the shared clock (%.1f ms)" % float(ours["time_err_ms"]))
	eq(flow().desyncs, [], "the host saw no desync")
	for p in peers_with("floor"):
		var r: Dictionary = reported(p, "floor")
		print("[NetTest] peer %d floor: %s" % [p, str(r)])
		eq(str(r["all"]), str(host_sums["all"]), "peer %d's floor checksum matches the host's" % p)
		for part in ["map", "plan", "run", "spawn"]:
			eq(str(r[part]), str(host_sums[part]), "peer %d: %s checksum matches" % [p, part])
		eq(int(r["cells"]), int(host_sums["cells"]), "peer %d: the same number of cells" % p)
		eq(int(r["actors"]), int(host_sums["actors"]), "peer %d: the same number of actors" % p)
		eq(r["counts"], ours["counts"], "peer %d: the same monsters, gates, employees, props and packages" % p)
		check(float(r["time_err_ms"]) < limit, "peer %d: GameWorld.time tracks the host within %.0f ms (%.1f ms)" % [p, limit, float(r["time_err_ms"])])
		check(float(r["arrival_err_ms"]) < limit, "peer %d: the van arrival plays from the shared start within %.0f ms (%.1f ms)" % [p, limit, float(r["arrival_err_ms"])])
		check(int(r["arrival_samples"]) > 20, "peer %d watched the arrival (%d frames)" % [p, int(r["arrival_samples"])])
		check(bool(r["arrival_done"]), "peer %d: the van arrival finished" % p)
		check(float(r["first_adjust_s"]) < 30.0, "peer %d: the first clock adjustment was sane (%.2f s)" % [p, float(r["first_adjust_s"])])
		# Copies, heroes, licenses.
		check(bool(r["copies_ok"]), "peer %d: everything the host owns is a non-acting copy" % p)
		var off_by := 0
		for i in mini((r["poses"] as Array).size(), (ours["poses"] as Array).size()):
			var theirs_p: Vector3 = (r["poses"] as Array)[i]
			var ours_p: Vector3 = (ours["poses"] as Array)[i]
			if Vector2(theirs_p.x, theirs_p.z).distance_to(Vector2(ours_p.x, ours_p.z)) > 0.6 or absf(float((r["hps"] as Array)[i]) - float((ours["hps"] as Array)[i])) > 0.1:
				off_by += 1
		eq((r["poses"] as Array).size(), (ours["poses"] as Array).size(), "peer %d has the host's world" % p)
		eq(off_by, 0, "peer %d: after %.1f s every copy stands where the host has it, with its HP (M3: the host's world, shown)" % [p, WATCH])
		check(bool(r["local_simulates"]), "peer %d simulates its own hero" % p)
		eq(int(r["heroes"]), 3, "peer %d has all three crew heroes" % p)
		eq(int(r["controllers"]), 1, "peer %d controls exactly one hero" % p)
		eq(int(r["brains"]), 0, "peer %d runs no AI heroes" % p)
		eq(int(r["seat"]), int(Session.roster[p]["seat"]), "peer %d controls the hero in its own seat" % p)
		eq(r["spells"], ours["spells"], "peer %d's roster holds everyone's spells, the same as the host's" % p)
	eq(int(ours["controllers"]), 1, "the host controls one hero")
	eq(int(ours["brains"]), 0, "the host runs no AI: all three seats are players (M2: an AI only plays an empty seat)")
	eq(int(ours["seat"]), 1, "the host sits in seat 1")
	check(bool(ours["host_simulates"]), "the host simulates the monsters, gates and employees")
	# Everyone's own license is in the roster, and on the hero this machine holds for that seat.
	var expected := {}
	for e: Dictionary in Session.crew():
		var idx := 0 if int(e["peer"]) == 1 else int(str(e["name"]).trim_prefix("c"))
		expected[int(e["seat"])] = LICENSES[idx]
	for seat: int in expected:
		eq((ours["spells"] as Dictionary)[seat], expected[seat], "seat %d signed its own two spells" % seat)
	check(await wait_done(2, 30.0), "both clients are done")


func run_client() -> void:
	if not check(await connect_client() == "", "joined"):
		return
	make_game()
	if not check(await wait_board(), "the client gets the host's job board"):
		return
	var b := board()
	var board_note := b.find_child("HostPicks", true, false) != null
	b.choose(0)   # a click on a card: the host picks, so this must do nothing
	var picked := game.get("_session") != null
	report("board", {"offers": offers_signature(b.offers), "seed": int(game.get("_board_shown")), "read_only": b.read_only,
		"note": board_note, "picked": picked})
	if not check(await until(func() -> bool: return b.highlighted() == 2, 15.0), "the host's highlighted card shows here"):
		return
	report("hi", true)

	if not check(await until(func() -> bool: return game.get("_session") != null, 15.0), "the host's job arrives"):
		return
	report("job", run_signature(game.get("_run")))
	if not check(await wait_picker(), "a license checkout opens"):
		return
	check(picker().back_text == "Leave the crew", "a client's checkout leaves the crew instead of going back")
	await sleep(SIGN_AT[index])
	check(await sign_license(my_license()), "this player signs their own license")
	await sleep(0.3)
	var label: Label = game.get("_wait_label")
	var waited := label != null and label.visible and label.text.begins_with("License signed. Waiting for") and label.text.contains("host")
	check(waited, "after signing: waiting for the others (%s)" % (label.text if label != null else "no label"))
	report("waited", waited)

	if not check(await wait_floor(), "the floor starts"):
		return
	var r := await measure()
	report("floor", r)


## Watch the first WATCH seconds of the floor and describe this machine's view of it.
func measure() -> Dictionary:
	var f := flow()
	var site: SiteBuilder.Site = game.get("_site")
	var copies := _copies(site)
	var t_end := wall() + WATCH
	var max_time_err := 0.0
	var max_arr_err := 0.0
	var arr_samples := 0
	var arrival: VanArrival = game.get("_arrival")
	while wall() < t_end:
		await get_tree().process_frame
		var now := truth()
		max_time_err = maxf(max_time_err, absf(GameWorld.time - (now - f.floor_start)))
		if arrival != null and arrival.is_running():
			max_arr_err = maxf(max_arr_err, absf(arrival.time - (now - f.start_at)))
			arr_samples += 1
	var sums: Dictionary = f.local_sums
	var out := {
		"all": sums["all"], "map": sums["map"], "plan": sums["plan"], "run": sums["run"], "spawn": sums["spawn"],
		"cells": sums["cells"], "actors": sums["actors"],
		"counts": {"gates": site.gates.size(), "employees": site.employees.size(), "props": site.props.size(),
			"monsters": site.monsters.size(), "packages": site.packages.size(), "notes": site.notes.size(), "decor": site.decor.size()},
		"time_err_ms": max_time_err * 1000.0, "arrival_err_ms": max_arr_err * 1000.0, "arrival_samples": arr_samples,
		"arrival_done": arrival != null and arrival.is_done(), "first_adjust_s": absf(f.first_adjust),
		"spells": _roster_spells(), "seat": _seat_of_player(),
	}
	var heroes := (game.get("heroes_by_seat") as Dictionary).values()
	out["heroes"] = heroes.size()
	out["controllers"] = heroes.filter(func(h: Hero) -> bool: return h.get_node_or_null("PlayerController") != null).size()
	out["brains"] = heroes.filter(func(h: Hero) -> bool: return h.get_node_or_null("AllyBrain") != null).size()
	out["poses"] = _poses(copies)
	out["hps"] = _hps(copies)
	if is_host():
		out["host_simulates"] = copies.all(func(a: Actor) -> bool: return Net.simulates(a) and a.is_physics_processing())
	else:
		out["copies_ok"] = copies.size() > 5 and copies.all(func(a: Actor) -> bool: return Net.is_copy(a) and not Net.simulates(a) and not a.is_physics_processing())
		out["local_simulates"] = Net.simulates(my_hero()) and not Net.is_copy(my_hero())
	return out


func _copies(site: SiteBuilder.Site) -> Array[Actor]:
	var out: Array[Actor] = []
	for a in site.monsters:
		out.append(a)
	out.append_array(site.gates)
	out.append_array(site.employees)
	out.append_array(site.props)
	out.append_array(site.packages)
	return out


func _poses(list: Array[Actor]) -> Array:
	return list.map(func(a: Actor) -> Vector3: return a.global_position)


func _hps(list: Array[Actor]) -> Array:
	return list.map(func(a: Actor) -> float: return a.hp)


## seat -> that hero's spell slots, as this machine's heroes hold them.
func _roster_spells() -> Dictionary:
	var out := {}
	for e: Dictionary in Session.crew():
		var signed: Array = []
		for s in e.get("spells", []) as Array:
			signed.append(str(s))
		out[int(e["seat"])] = signed
	for seat: int in (game.get("heroes_by_seat") as Dictionary):
		var h: Hero = hero_at(seat)
		if out.has(seat):
			var slots: Array = []
			for s in h.spell_slots:
				slots.append(s)
			if slots != out[seat]:
				out[seat] = ["MISMATCH", slots, out[seat]]
	return out


func _seat_of_player() -> int:
	for seat: int in (game.get("heroes_by_seat") as Dictionary):
		if hero_at(seat) == my_hero():
			return seat
	return 0
