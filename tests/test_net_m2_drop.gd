extends NetGameTest
## M2b "done when" (networking-build-plan.md), three processes, `off` and `coast`: a player DROPS mid-floor and the AI takes
## the seat back as the seat's ORIGINAL character (user decision: Gasket in seat 3), via SeatHandover.
##
## c2 (seat 3, a Wick) walks away from the host's hero, stops, tells the host where it stands, and its process quits mid-floor.
## Then, on the host:
## - the roster drops it, and within a second (clean link: well under) seat 3's hero is the SAME node, now Gasket (kit, name,
##   model), simulated here again, with an AllyBrain, where c2 left it (its HP fraction kept);
## - the AI walks it back toward the crew (it was far from the leader), so it MOVES;
## and on c1 (a client):
## - it is told (`seat.ai`), the same hero becomes Gasket on its screen too, still a puppet, and from then on it shows what
##   the HOST streams: the AI's walk, within 0.35 units of where the host's AI really was.

const PEERS := 3
const SEED := 21
const FAR := 6.0                ## c2 walks until it is this far from the host's hero
const OBSERVE := 5.0            ## seconds everyone watches the AI play the seat
const HANDOVER_WITHIN := 1.0


func run_host() -> void:
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	check(await wait_reports("ready", 2, 30.0), "both clients are streaming")
	var h3 := hero_at(3)
	eq(h3.kit_id, HeroKit.WICK, "seat 3 starts as c2's Wick")
	check(Net.is_puppet(h3) and h3.get_node_or_null("AllyBrain") == null, "... a puppet here, with no AI")
	eq(Net.label_of(h3), "c2", "... with c2's name over it")
	var c1 := _peer_named("c1")
	var c2 := _peer_named("c2")
	command(c1, "observe")
	command(c2, "drop")
	check(await wait_reports("dropping", 1, 45.0), "c2 reports where it stands before it quits")
	var drop: Dictionary = reported(c2, "dropping")
	var final_pos: Vector3 = drop["pos"]
	var final_hp := float(drop["hp"])
	print("[M2] c2 leaves from %s (hp %.1f)" % [str(final_pos), final_hp])

	# The roster drops it and the AI takes the seat, fast.
	check(await until(func() -> bool: return Session.roster.size() == 2, 15.0), "the host drops c2 from the roster")
	check(await until(func() -> bool: return h3.get_node_or_null("AllyBrain") != null, 3.0), "the seat gets an AI")
	var at_handover := h3.global_position
	var entry: Dictionary = Session.seats.history[0] if not Session.seats.history.is_empty() else {}
	eq(int(entry.get("seat", 0)), 3, "SeatHandover logged seat 3")
	eq(str(entry.get("character", "")), "gasket", "... handed to its original character")
	eq(int(entry.get("epoch", 0)), 1, "... as ownership epoch 1")
	var took := float(entry.get("t", 1e9)) - float(drop["quit_at"])
	print("[M2] the host handed the seat over %.3f s after c2 quit" % took)
	check(took >= -0.05 and took <= HANDOVER_WITHIN, "the AI has the seat within %.1f s of c2 quitting (%.3f s)" % [HANDOVER_WITHIN, took])
	eq(Session.seats.owner_of(3), 0, "seat 3 is the host's now")
	check(is_instance_valid(h3) and hero_at(3) == h3, "it is the SAME hero node")
	eq(h3.kit_id, HeroKit.GASKET, "now Gasket's kit")
	eq(h3.display_name, "Gasket", "named Gasket")
	eq(Net.label_of(h3), "Gasket", "the nameplate reads Gasket, not c2")
	check(h3.visual_override is GasketModel, "wearing Gasket's model")
	check(Net.simulates(h3) and not Net.is_puppet(h3) and Net.owns(h3), "simulated here again")
	check(Session.snap.is_live(3) and not Session.snap.is_puppet(3), "and streamed to the crew from here")
	near(at_handover.distance_to(final_pos), 0.0, 0.5, "it stands where c2 left it")
	near(h3.hp / h3.max_hp, final_hp / 85.0, 0.01, "with the same fraction of its HP (c2 had %.0f of 85)" % final_hp)
	eq(NetFloor.id_of(h3), 3, "and the same net id")
	check(NetRegistry.node(3) == h3, "the registry still finds it")
	check(Net.crewed(), "the crew is still a crew")

	# The AI plays it: it walks back toward the leader, and c1 sees the same.
	record(true)
	var far_from_leader := hero_at(1).global_position.distance_to(final_pos)
	await sleep(OBSERVE)
	record(false)
	var ring3: PackedFloat64Array = live_rings.get(3, PackedFloat64Array())
	var walked := 0.0
	for i in floori(float(ring3.size()) / 4.0):
		walked = maxf(walked, Vector2(ring3[i * 4 + 1], ring3[i * 4 + 3]).distance_to(Vector2(final_pos.x, final_pos.z)))
	print("[M2] the AI walked %.1f units from where c2 left it (it was %.1f from the leader)" % [walked, far_from_leader])
	check(walked > 1.5, "the AI plays the seat: it moved %.1f units toward the crew" % walked)
	check(await wait_reports("observed", 1, 30.0), "c1 reports what it saw")
	var seen1: Dictionary = reported(c1, "observed")
	eq(str(seen1["kit"]), HeroKit.GASKET, "c1's copy of the hero is Gasket too")
	eq(str(seen1["label"]), "Gasket", "c1 reads Gasket over it")
	check(bool(seen1["puppet"]), "it is still a puppet on c1 (the host plays it)")
	check((seen1["pos"] as Vector3).distance_to(final_pos) <= 0.6, "c1 saw it change at the spot c2 left it (%.2f)" % (seen1["pos"] as Vector3).distance_to(final_pos))
	check(float(seen1["moved"]) > 1.5, "c1 saw the AI move it (%.1f units)" % float(seen1["moved"]))
	var e := series_error(ring3, seen1["series"] as PackedFloat64Array, 0.5)
	print("[M2] c1 sees the AI's walk: %d frames, max err %.3f (beyond walking %.3f)" % [int(e["n"]), float(e["max_err"]), float(e["max_excess"])])
	check(int(e["n"]) > 150, "c1 watched the AI walk (%d frames)" % int(e["n"]))
	check(float(e["max_err"]) <= 0.35, "c1's picture of the AI stays within 0.35 of where it really was (%.3f)" % float(e["max_err"]))
	check(float(e["max_excess"]) <= 0.6, "and does not snap when the stream changes hands (%.3f)" % float(e["max_excess"]))
	check(await wait_done(1, 30.0), "c1 is done")


func run_client() -> void:
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	report("ready", true)
	await wait_command(60.0)
	if index == 1:
		await _observe_as_c1()
	elif index == 2:
		await _drop_as_c2()
		return
	else:
		return


## c2: walk away from the host's hero, stand still, say where, and quit the process.
func _drop_as_c2() -> void:
	start_bot()
	var leader := hero_at(1)
	await until(func() -> bool: return my_hero().global_position.distance_to(leader.global_position) > FAR, 20.0)
	bot.stop()
	await sleep(0.8)
	var hero := my_hero()
	hero.apply_damage(17.0)   # (so the HP fraction the AI inherits is not just "full")
	await sleep(0.5)
	report("dropping", {"pos": hero.global_position, "hp": hero.hp, "quit_at": Session.host_time() + 0.35})
	await sleep(0.35)
	get_tree().quit(0)
	await sleep(10.0)   # (the quit happens at the end of the frame: do nothing more)


## c1: keeps walking; when the seat is handed to the AI, watches the hero for OBSERVE seconds.
func _observe_as_c1() -> void:
	start_bot()
	var captured := {}
	Session.seats.to_ai.connect(func(seat: int, character: String) -> void:
		var h := hero_at(seat)
		captured["seat"] = seat
		captured["character"] = character
		captured["pos"] = h.global_position
		captured["kit"] = h.kit_id
		captured["label"] = Net.label_of(h))
	check(await until(func() -> bool: return captured.has("seat"), 40.0), "c1 is told the seat went to the AI")
	eq(int(captured.get("seat", 0)), 3, "seat 3")
	eq(str(captured.get("character", "")), "gasket", "as Gasket")
	var h3 := hero_at(3)
	var start: Vector3 = captured["pos"]
	record(true)
	await sleep(OBSERVE)
	record(false)
	var series: PackedFloat64Array = seen.get(3, PackedFloat64Array())
	var moved := 0.0
	for i in floori(float(series.size()) / 5.0):
		moved = maxf(moved, Vector2(series[i * 5 + 1], series[i * 5 + 3]).distance_to(Vector2(start.x, start.z)))
	report("observed", {"kit": h3.kit_id, "label": Net.label_of(h3), "puppet": Net.is_puppet(h3), "moved": moved,
		"series": series, "pos": start})


func _peer_named(who: String) -> int:
	for e: Dictionary in Session.crew():
		if str(e["name"]) == who:
			return int(e["peer"])
	return 0
