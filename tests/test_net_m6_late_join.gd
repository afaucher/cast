extends NetGameTest
## M6 (networking-build-plan.md, "M6 Join mid-contract and seat handover"), three processes, `off` and `coast`: the host and
## c1 start a contract together; 15 s into floor 2, with the floor already played on (monsters killed, a prop broken and another
## dented, a hellgate closed, an employee lost, two monsters spawned at run time, a pickup on the floor, the host armored and
## the AI in seat 3 hurt and carrying spells), c2 joins the running crew:
## - c2 shows "Clocking in...", then its own license checkout (user, 2026-10-18: a joiner picks its spells; the back row
##   leaves the crew). While c2 is in the checkout the AI keeps the seat and the crew plays on (the floor clock runs, nobody
##   waits). c2 signs tentacles + teeth (the AI holds heal + vines);
## - c2 builds the floor: its floor checksum is the host's (the floor as it was at its barrier), its gone ids and its set of
##   living host-owned actors are the host's at the snapshot, and the Ledger is the host's;
## - c2 takes over seat 3 (the AI, Gasket) only after it signed: it controls that hero (live, not a puppet) where the AI stood,
##   at 100% HP, with the spells IT signed at fresh charges (not the AI's), within 1 s of reporting ready; the AllyBrain is
##   gone; the host and c1 show it as c2 (a Wick) holding those spells and charges, and every screen says "c2 takes over
##   Gasket's seat.";
## - c2 walks and the host sees it move there; a moment later every screen still agrees on the living actors;
## - c2 leaves: the AI takes seat 3 back as Gasket on the host (AllyBrain, live) and on c1.

const PEERS := 3
const SEED := 13
## Seconds the crew has been on floor 2 when c2 joins.
const ON_FLOOR := 15.0
## The license c2 signs (the AI in seat 3 holds heal and vines, so a mix-up shows).
const JOINER_SPELLS := ["tentacles", "teeth"]
## How long the host watches the AI keep the seat while c2 is in its checkout.
const CHECKOUT_HOLD := 1.5


func run_host() -> void:
	net_timeout = 85.0
	follow_reloads = true
	clear_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	make_game({"spells": "heal,corn", "seed": SEED, "contract": 1, "net_wait": 2})
	if not check(await wait_floor(45.0), "floor 1 starts") or not await wait_sync():
		return
	(game.get("opts") as Dictionary).erase("net_wait")
	_ward()
	var c1 := peer_named("c1")
	check(await wait_reports("ready", 1, 30.0), "c1 is on floor 1")
	# Down to floor 2 (the host takes the elevator).
	command(c1, "floor", {"n": 2})
	game.call("_choose_exit", "down")
	check(await until(func() -> bool: return reloads >= 1, 10.0), "the host went down")
	if not check(await wait_floor(40.0), "floor 2 starts") or not await wait_sync():
		return
	_ward()
	check(await wait_reports("floor2", 1, 30.0), "c1 is on floor 2")
	eq(str(reported(c1, "floor2")), str(flow().local_sums.get("all", "")), "c1 built the same floor 2")

	# The crew plays floor 2 for a while (the AI in seat 3 fights): the late joiner will have to see all of it. It joins
	# ON_FLOOR seconds into floor 2 (the plan's "at 15 s on floor 2").
	var floor2_at := wall()
	var played := _play_floor()
	await until(func() -> bool: return wall() - floor2_at >= ON_FLOOR, ON_FLOOR + 1.0)
	var ai := hero_at(3)
	check(ai != null and ai.kit_id == "gasket" and Session.seats.owner_of(3) == 0 and ai.get_node_or_null("AllyBrain") != null, "seat 3 is the AI, Gasket")

	# c2 joins the running crew.
	raise_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 30.0), "c2 joins the crew on the job"):
		return
	var c2 := peer_named("c2")
	check(CrewFlow.is_joining(Session.roster[c2]), "c2 is joining")
	# c2 is in its license checkout: the AI keeps the seat and the crew plays on meanwhile.
	if not check(await wait_reports("checkout", 1, 30.0), "c2 opened its license checkout"):
		return
	var co: Dictionary = reported(c2, "checkout")
	check(bool(co["joiner_picker"]), "... the joiner's checkout, in place of \"Clocking in...\" (the form is hidden behind it)")
	eq(str(co["back"]), "Leave the crew", "... whose back row leaves the crew")
	check(bool(co["saw_slip"]), "c2 showed \"Clocking in...\" before the checkout")
	var t0 := GameWorld.time
	var held := true
	var hold_end := wall() + CHECKOUT_HOLD
	while wall() < hold_end:
		held = held and Session.seats.owner_of(3) == 0 and hero_at(3).get_node_or_null("AllyBrain") != null and not Session.join.admitted.has(c2) \
				and str((Session.join.joiners.get(c2, {}) as Dictionary).get("state", "")) == NetJoin.WAIT
		await get_tree().process_frame
	check(held, "while c2 is in its checkout the AI keeps seat 3 (Gasket, AllyBrain on) and c2 is not sent in")
	check(GameWorld.time - t0 > CHECKOUT_HOLD - 0.2, "... and the crew plays on: the floor clock ran %.2f s (nobody waits for c2)" % (GameWorld.time - t0))
	check(((Session.join.joiners.get(c2, {}) as Dictionary).get("spells", []) as Array).is_empty(), "... c2 has not signed yet")
	command(c2, "sign", {"spells": JOINER_SPELLS})
	if not check(await until(func() -> bool: return Session.join.admitted.has(c2), 25.0), "c2 signed, built floor 2 and was admitted"):
		return
	var adm: Dictionary = Session.join.admitted[c2]
	eq(int(adm["seat"]), 3, "c2 takes seat 3 (the only AI)")
	check(float(adm["signed_t"]) > 0.0 and float(adm["t"]) > float(adm["signed_t"]), "the seat was handed over only after c2 signed")
	var take_t := -1.0
	for hh: Dictionary in Session.seats.history:
		if str(hh["kind"]) == "player" and int(hh["seat"]) == 3:
			take_t = float(hh["t"])
	check(take_t >= float(adm["signed_t"]), "... the AI played seat 3 until then (the handover at %.2f, signed at %.2f)" % [take_t, float(adm["signed_t"])])
	eq(str(adm["slots"]), str(JOINER_SPELLS), "c2 takes the seat with the spells it signed")
	eq(str(adm["charges"]), str({"tentacles": SpellComponents.START_CHARGES, "teeth": SpellComponents.START_CHARGES}), "... at fresh charges (%d each)" % SpellComponents.START_CHARGES)
	check((adm["ai_slots"] as Array).has("heal") and (adm["ai_slots"] as Array).has("vines"), "... not the AI's (%s)" % str(adm["ai_slots"]))
	check(not (adm["gone"] as Array).is_empty(), "the snapshot carries gone ids (%d)" % (adm["gone"] as Array).size())
	for id: int in played["gone"]:
		check((adm["gone"] as Array).has(id), "... including %d (%s)" % [id, str(played["what"].get(id, ""))])
	check(int(adm["bytes"]) > 0, "the snapshot was %d bytes" % int(adm["bytes"]))
	check((adm["alive"] as Array).any(func(id: int) -> bool: return id >= NetRegistry.RUNTIME_BASE), "... and the runtime monsters are alive in it")
	eq(Session.seats.owner_of(3), c2, "the host's seat table: seat 3 is c2's")
	ai = hero_at(3)
	check(ai.get_node_or_null("AllyBrain") == null, "the AllyBrain stopped")
	check(Net.is_puppet(ai), "the host shows seat 3 as a puppet of c2's stream")
	eq(ai.kit_id, "wick", "seat 3 is c2's character (Wick) on the host")
	eq(Net.label_of(ai), "c2", "... named c2")
	near(ai.hp, ai.max_hp, 0.01, "... at full health on the host")
	eq(str(Array(ai.spell_slots)), str(JOINER_SPELLS), "... holding c2's license on the host")
	eq(str(ai._charges), str(adm["charges"]), "... at c2's charges")
	eq(str(Session.roster[c2].get("spells", [])), str(JOINER_SPELLS), "the roster has c2's license (the next floor builds it on every machine)")
	check((game.get("_seat_notices") as Array).has("c2 takes over Gasket's seat."), "the host's HUD says c2 takes over Gasket's seat")

	if not check(await wait_reports("arrived", 1, 20.0), "c2 reports its arrival"):
		return
	var r: Dictionary = reported(c2, "arrived")
	eq(str(r["sum"]), str(flow().local_sums.get("all", "")), "c2's floor checksum is the host's (floor 2 as at its barrier)")
	eq(int(r["floor"]), 2, "c2 is on floor 2")
	eq(str(r["gone"]), str(_sorted(adm["gone"] as Array)), "c2's gone ids are the host's")
	eq(str(r["alive"]), str(adm["alive"]), "c2's living host-owned actors are the host's at the snapshot")
	eq(int(r["hero_seat"]), 3, "c2 controls the hero in seat 3")
	check(bool(r["owns"]) and not bool(r["puppet"]), "... its own hero there (live, not a puppet)")
	check(bool(r["controller"]), "... with its controller on once the floor started")
	var take: Dictionary = adm["take"]
	var at: Vector3 = r["take_pos"]
	near(at.distance_to(take["p"]), 0.0, 0.01, "... where the AI stood at the handover")
	near(float(r["hp"]), float(r["max"]), 0.01, "... at 100%% HP (%.0f)" % float(r["max"]))
	check(not bool(r["dead"]), "... standing")
	eq(str(r["kit"]), "wick", "... as its own character")
	eq(str(r["slots"]), str(JOINER_SPELLS), "... with the spells it signed")
	eq(str(r["charges"]), str(adm["charges"]), "... at fresh charges")
	eq(str(r["license_on_form"]), "TENTACLES · TEETH", "c2's \"Clocking in...\" came back with its license typed in")
	check(float(r["dt"]) >= 0.0 and float(r["dt"]) < 1.0, "it took the seat %.0f ms after reporting ready (limit 1 s)" % (float(r["dt"]) * 1000.0))
	check(bool(r["saw_slip"]), "c2 showed \"Clocking in...\" while it built")
	check((r["notice"] as Array).has("You take over Gasket's seat."), "c2's HUD says it took over Gasket's seat")
	check(bool(r["armor_on_host"]), "c2 shows the host's armor (a status from before it came)")
	check((r["pickups"] as Array).has(int(played["pickup"])), "c2 has the pickup on the floor (id %d)" % int(played["pickup"]))
	check(float(r["dent"]) < 0.0 or absf(float(r["dent"]) - float(played["dent_hp"])) < 0.05, "c2 shows the dented prop's HP")
	print("[M6] late join: snapshot %d bytes, %d gone ids, %d keyframe entries, %d runtime monsters, ready -> seat %.0f ms" % [
		int(adm["bytes"]), (adm["gone"] as Array).size(), int(r["keyframe"]), int(r["spawns"]), float(r["dt"]) * 1000.0])

	# c1 sees the takeover too.
	command(c1, "seen", {"peer": c2})
	if check(await wait_reports("seen", 1, 10.0), "c1 reports seat 3"):
		var s: Dictionary = reported(c1, "seen")
		eq(str(s["kit"]), "wick", "c1 shows seat 3 as Wick")
		eq(str(s["label"]), "c2", "... named c2")
		near(float(s["hp"]), float(s["max"]), 0.01, "... at full health")
		eq(str(s["slots"]), str(JOINER_SPELLS), "... holding c2's license")
		eq(str(s["charges"]), str(adm["charges"]), "... at c2's charges")
		check((s["notice"] as Array).has("c2 takes over Gasket's seat."), "c1's HUD says c2 takes over Gasket's seat")

	# A quiet moment later: the same living actors and the same Ledger on both.
	await sleep(1.0)
	command(c2, "check")
	if check(await wait_reports("check", 1, 10.0), "c2 reports its floor"):
		var q: Dictionary = reported(c2, "check")
		eq(str(q["alive"]), living_text(), "c2's living host-owned actors are the host's")
		eq(str(q["ledger"]), ledger_text(), "c2's Ledger is the host's line for line")
		eq(int(q["payout"]), Ledger.payout(), "... the same payout (%d)" % Ledger.payout())
		var worst := 0.0
		var pos: Dictionary = q["monsters"]
		for k: Variant in pos:
			var m := NetRegistry.node(int(k)) as Monster
			if m != null and not m.dead:
				var p: Vector2 = pos[k]
				worst = maxf(worst, p.distance_to(Vector2(m.global_position.x, m.global_position.z)))
		check(pos.size() > 0 and worst < 1.2, "c2 shows the host's monsters where the host has them (%d, worst %.2f units with the render delay)" % [pos.size(), worst])

	# c2 walks: the host sees seat 3 move where c2 has it.
	command(c2, "walk", {"to": hero_at(1).global_position})
	if check(await wait_reports("walked", 1, 10.0), "c2 walked"):
		var w: Dictionary = reported(c2, "walked")
		await sleep(0.5)
		var shown := hero_at(3).global_position
		var c2_at: Vector3 = w["pos"]
		check(c2_at.distance_to(take["p"]) > 0.8, "c2 moved its hero (%.2f units)" % c2_at.distance_to(take["p"]))
		near(Vector2(shown.x, shown.z).distance_to(Vector2(c2_at.x, c2_at.z)), 0.0, 0.3, "the host shows seat 3 where c2 has it")

	# c2 leaves: the AI is back.
	var left_at := Session.host_time()
	command(c2, "leave")
	check(await until(func() -> bool: return hero_at(3).kit_id == "gasket", 5.0), "c2 left: seat 3 is Gasket again on the host")
	ai = hero_at(3)
	check(Session.host_time() - left_at < 2.0, "within %.2f s of the leave command" % (Session.host_time() - left_at))
	eq(Session.seats.owner_of(3), 0, "seat 3 is the AI's")
	check(ai.get_node_or_null("AllyBrain") != null and not Net.is_puppet(ai), "the host runs the AI there again")
	command(c1, "ai_back")
	if check(await wait_reports("ai_back", 1, 10.0), "c1 reports seat 3 again"):
		eq(str(reported(c1, "ai_back")), "gasket", "c1 shows Gasket back in seat 3")
	command(c1, "end")
	check(await wait_done(1, 20.0), "c1 is done")
	clear_flag("join")


## The floor changes the late joiner must see: two monsters killed, a prop broken and one dented, a gate closed, an employee
## lost, two monsters spawned now, a pickup dropped, the host's armor, the AI hurt and holding spells.
func _play_floor() -> Dictionary:
	var out := {"gone": [], "what": {}, "pickup": 0, "dent_hp": -1.0}
	var killed := 0
	var broke := false
	var dented := false
	var gate_done := false
	var emp_done := false
	for id in range(NetFloor.ID_BASE, NetRegistry.seed_top):
		var n := NetRegistry.node(id)
		if n == null or not (n is Actor) or (n as Actor).dead:
			continue
		if n is Monster and killed < 2:
			(n as Monster).die()
			killed += 1
			out["gone"].append(id)
			out["what"][id] = "a monster"
		elif n is PricedProp and not broke:
			(n as PricedProp).apply_damage((n as PricedProp).hp + 10.0, hero_at(1))
			broke = true
			out["gone"].append(id)
			out["what"][id] = "a broken prop"
		elif n is PricedProp and not dented and (n as PricedProp).hp > 2.0:
			(n as PricedProp).apply_damage(1.0, hero_at(1))
			if not (n as PricedProp).dead:
				dented = true
				out["dent_hp"] = (n as PricedProp).hp
				out["dent"] = id
		elif n is Hellgate and not gate_done:
			(n as Hellgate).die()
			gate_done = true
			out["gone"].append(id)
			out["what"][id] = "a closed gate"
		elif n is Employee and not emp_done:
			(n as Employee).die()
			emp_done = true
			out["gone"].append(id)
			out["what"][id] = "a lost employee"
	check(killed == 2, "two monsters killed on floor 2")
	var start: Vector2i = hero_at(1).current_cell()
	var spawned := 0
	for dist in range(8, 14):
		var c := cell_at(start, dist)
		if c == Vector2i.MAX or spawned >= 2:
			continue
		var m := MonsterFactory.spawn("grunt", c)
		if m != null:
			m.aggro_range = 0.0                     # (they stand there: alive when c2 comes, whatever the AI does)
			m.set_modifier("test_ward", 0.0, 999.0)
			spawned += 1
	check(spawned == 2 and Session.world.runtime_spawns().size() >= 2, "two monsters spawned at run time (ids from %d)" % NetRegistry.RUNTIME_BASE)
	var p := ComponentPickup.drop("corn", 2, hero_at(1).global_position + Vector3(3.0, 0.0, 0.0), 60.0)
	if p != null:
		Session.objects.call("_host_pickups")
		out["pickup"] = NetFloor.id_of(p)
	hero_at(1).set_modifier("armor", 0.5, 40.0)
	var ai := hero_at(3)
	ai.apply_damage(30.0, null)
	ai.slot_in("heal", 3)
	ai.slot_in("vines", 2)
	return out


func _ward() -> void:
	my_hero().set_modifier("test_ward", 0.0, 999.0)


static func _sorted(a: Array) -> Array[int]:
	var out: Array[int] = []
	for v: Variant in a:
		out.append(int(v))
	out.sort()
	return out


func run_client() -> void:
	follow_reloads = true
	if index == 2:
		await _late_joiner()
		return
	if not check(await connect_client() == "", "joined"):
		return
	make_game({"spells": "heal,corn"})
	if not check(await wait_floor(45.0), "floor 1 starts here") or not await wait_sync():
		return
	_ward()
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"floor":
				check(await until(func() -> bool: return reloads >= int(cmd["n"]) - 1, 10.0), "c1 followed the crew down")
				check(await wait_floor(40.0), "floor %d starts here" % int(cmd["n"]))
				await wait_sync()
				_ward()
				report("floor%d" % int(cmd["n"]), flow().local_sums.get("all", ""))
			"seen":
				var p := int(cmd["peer"])
				await until(func() -> bool: return Session.seats.owner_of(3) == p and hero_at(3).kit_id == "wick", 10.0)
				var h := hero_at(3)
				report("seen", {"kit": h.kit_id, "label": Net.label_of(h), "hp": h.hp, "max": h.max_hp, "notice": (game.get("_seat_notices") as Array).duplicate(),
					"slots": str(Array(h.spell_slots)), "charges": str(h._charges)})
			"ai_back":
				await until(func() -> bool: return hero_at(3).kit_id == "gasket", 5.0)
				report("ai_back", hero_at(3).kit_id)
			_:
				running = false


## c2: wait for the host's flag, join the crew on the job, sign its own license, and take the AI's seat.
func _late_joiner() -> void:
	var since := Time.get_unix_time_from_system()
	if not check(await wait_flag("join", since, 70.0), "the host raised the join flag"):
		return
	if not check(await connect_client() == "", "joined the crew on the job"):
		return
	make_game({})   # (no --spells: c2 signs its license by hand)
	var arrival := {}
	var saw_slip := [false]
	var opened := await until(func() -> bool:
		if game != null and game.get("_join_slip") != null and (game.get("_join_slip") as Control).visible:
			saw_slip[0] = true
		return picker() != null, 30.0)
	if not check(opened, "c2's license checkout opened"):
		return
	var slip := game.get("_join_slip") as ClockInSlip
	report("checkout", {"joiner_picker": game.get("_join_picker") != null and slip != null and not slip.visible,
		"back": picker().back_text, "saw_slip": saw_slip[0]})
	var sign_cmd := await wait_command(30.0)
	if not check(str(sign_cmd.get("cmd", "")) == "sign", "the host says sign"):
		return
	# (hooked before signing, so the arrival is caught however long the name stamp holds)
	Session.join.changed.connect(func() -> void:
		if Session.join.arrived and arrival.is_empty():
			var h := my_hero()
			arrival["alive"] = living_text()
			arrival["take_pos"] = h.global_position
			arrival["hp"] = h.hp
			arrival["max"] = h.max_hp
			arrival["dead"] = h.dead
			arrival["slots"] = str(Array(h.spell_slots))
			arrival["charges"] = str(h._charges))
	check(await sign_license(sign_cmd["spells"] as Array), "c2 signs %s" % str(sign_cmd["spells"]))
	await get_tree().process_frame
	slip = game.get("_join_slip") as ClockInSlip
	var license_on_form := slip.license_value.text if slip != null and slip.visible else "(no form)"
	var waited := await until(func() -> bool:
		if game != null and game.get("_join_slip") != null:
			saw_slip[0] = true
		return Session.join.arrived, 30.0)
	if not check(waited, "c2 arrived on the crew's floor"):
		return
	if not check(await wait_floor(10.0), "the floor started for c2") or not await wait_sync():
		return
	var h := my_hero()
	var dent := -1.0
	for id in NetRegistry.ids():
		var prop := NetRegistry.node(id) as PricedProp
		if prop != null and not prop.dead and prop.hp < prop.max_hp - 0.001:
			dent = prop.hp
	report("arrived", {"sum": flow().local_sums.get("all", ""), "floor": int((game.get("_session") as ContractSession).floor_number),
		"gone": str(Session.join.applied.get("gone", [])), "alive": arrival.get("alive", ""), "hero_seat": NetFloor.id_of(h),
		"owns": Net.owns(h), "puppet": Net.is_puppet(h), "controller": (game.get("controller") as PlayerController).enabled,
		"take_pos": arrival.get("take_pos", Vector3.INF), "hp": arrival.get("hp", 0.0), "max": arrival.get("max", 1.0), "dead": arrival.get("dead", true),
		"kit": h.kit_id, "slots": arrival.get("slots", ""), "charges": arrival.get("charges", ""), "license_on_form": license_on_form,
		"dt": Session.join.taken_at - Session.join.ready_at, "saw_slip": saw_slip[0], "notice": (game.get("_seat_notices") as Array).duplicate(),
		"armor_on_host": hero_at(1).has_modifier("armor"), "pickups": Session.objects.pickup_ids(), "dent": dent,
		"keyframe": int(Session.join.applied.get("keyframe", 0)), "spawns": int(Session.join.applied.get("spawns", 0))})
	_ward()
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"check":
				var mons := {}
				for id in NetRegistry.ids():
					var m := NetRegistry.node(id) as Monster
					if m != null and not m.dead:
						mons[id] = Vector2(m.global_position.x, m.global_position.z)
				report("check", {"alive": living_text(), "ledger": ledger_text(), "payout": Ledger.payout(), "monsters": mons})
			"walk":
				var pc := game.get("controller") as PlayerController
				var to: Vector3 = cmd["to"]
				var d := to - my_hero().global_position
				d.y = 0.0
				pc.move_override = d.normalized() if d.length() > 0.1 else Vector3(1.0, 0.0, 0.0)
				await sleep(0.45)
				pc.move_override = Vector3.ZERO
				await sleep(0.3)
				pc.move_override = Vector3.INF
				report("walked", {"pos": my_hero().global_position})
			"leave":
				Session.leave()
				running = false
			_:
				running = false
