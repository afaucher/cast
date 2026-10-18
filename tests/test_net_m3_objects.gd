extends NetGameTest
## M3 "done when" (networking-build-plan.md: test_net_m3_objects), three processes, `off` and `coast`: the host arbitrates
## the world's objects, and every machine agrees.
##
## - BREAKABLES: both clients hit the same priced prop at the same shared moment (each on its own screen, through the
##   real Actor.apply_damage, which sends the host a request); the prop breaks ONCE on every machine and is billed ONCE:
##   one damage line, at its price, on all three Ledgers. c1 smashes a crate, c2 a mail box (the host rolls what was
##   inside: a component), and every machine shows them broken and the same pickup with the same id;
## - PICKUP: a component lies between the two clients; both walk onto it at the same shared moment (their screens ask the
##   host); EXACTLY ONE gets its charges, the other is refused, it is gone everywhere, and every machine sees the same
##   slots and charges on every hero (the owner tells the crew);
## - EMPLOYEES: c1 presses E beside an employee: the host grants it, and on every screen the employee follows c1's hero
##   (state FOLLOW, leader seat 2) and walks after it; E again tells it to wait (WAIT, dismissed, on every screen). The host
##   loses one employee and extracts another: dead / extracted everywhere, the clients' trackers show the host's books
##   and the extraction pay is on every Ledger once;
## - E ON THE CLIENT'S WORD (user, 2026-10-18): the host trusts a client's follow / wait for range (its own screen found the
##   employee within reach; the host's picture is ~100 ms old) and judges only the state. Both clients ask the waiting
##   employee to follow at the same shared moment, each from 3.5 units away as the host has it (out of E's 2.2 there: the
##   host refused that before): exactly one is granted, the first, and the other is refused because it now follows
##   someone; its new leader then tells it to wait from as far, granted;
## - every Ledger ends with the same lines.

const PEERS := 3
const SEED := 13
const SPELL := "vines"


func run_host() -> void:
	if not await enter_floor(SEED, 1):
		return
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	if not await wait_sync():
		return
	check(await wait_reports("ready", 2, 30.0), "both clients are streaming")
	var site: SiteBuilder.Site = game.get("_site")
	var c1 := _peer_named("c1")
	var c2 := _peer_named("c2")

	# 1. Breakables.
	var prop: PricedProp = null
	for p in site.props:
		if is_instance_valid(p) and not p.dead:
			prop = p
			break
	var crate: BreakableCrate = null
	var mail: MailPackage = null
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if crate == null and n is BreakableCrate and not (n as Actor).dead:
			crate = n
		if mail == null and n is MailPackage and not (n as Actor).dead and (n as MailPackage).stack_index == 0:
			mail = n
	if not check(prop != null and crate != null and mail != null, "the floor has a priced prop, a crate and a mail box"):
		return
	mail.forced_contents = "component"   # (the host rolls the contents; this one holds a component)
	var t_hit := Session.host_time() + 0.6
	var ids := {"prop": NetFloor.id_of(prop), "crate": NetFloor.id_of(crate), "mail": NetFloor.id_of(mail), "t": t_hit}
	command(c1, "hit", ids)
	command(c2, "hit", ids)
	check(await until(func() -> bool: return prop.dead and crate.dead and mail.dead, 5.0), "the host broke the prop, the crate and the mail box")
	await sleep(0.4)
	eq(_damage_lines(prop.display_name), 1, "the host billed the prop once")
	eq(_damage_total(prop.display_name), prop.price, "... at its price (%d)" % prop.price)
	eq(int(Session.objects.stats["hits_in"]), 3, "the host applied three hits (the prop's second hit found it already broken)")
	var mail_pickup := mail.pickup
	check(mail_pickup != null and is_instance_valid(mail_pickup), "the box held a component and the host put it down")
	var mail_pick_id := NetFloor.id_of(mail_pickup) if mail_pickup != null else 0
	check(mail_pick_id >= NetRegistry.RUNTIME_BASE, "... with a host id (%d)" % mail_pick_id)
	check(await wait_reports("hit", 2, 20.0), "both clients report the breaks")
	for p in [c1, c2]:
		var r: Dictionary = reported(p, "hit")
		var who := "c1" if p == c1 else "c2"
		check(bool(r["prop"]) and bool(r["crate"]) and bool(r["mail"]), "%s shows the prop, the crate and the box broken" % who)
		eq(int(r["bills"]), 1, "%s's Ledger bills the prop once" % who)
		eq(int(r["billed"]), prop.price, "%s's Ledger bills its price" % who)
		eq(str(r["contents"]), "component", "%s was told what the box held" % who)
		eq(int(r["mail_pickup"]), mail_pick_id, "%s has the box's pickup, with the host's id" % who)
		eq(str(r["mail_spell"]), mail.component_id, "... the same component (%s)" % mail.component_id)

	# 2. A pickup both clients grab at once.
	bot_stop_all()
	var spot := _open_spot(my_hero().global_position, 4.0)
	var pk := ComponentPickup.drop(SPELL, SpellComponents.PICKUP_CHARGES, spot)
	await sleep(0.2)
	var pk_id := NetFloor.id_of(pk)
	check(pk_id >= NetRegistry.RUNTIME_BASE, "the host announced the pickup (%d)" % pk_id)
	var t_grab := Session.host_time() + 0.8
	command(c1, "grab", {"id": pk_id, "at": pk.global_position, "t": t_grab})
	command(c2, "grab", {"id": pk_id, "at": pk.global_position, "t": t_grab})
	check(await until(func() -> bool: return not is_instance_valid(pk) or pk._used, 6.0), "the pickup was taken")
	check(await wait_reports("grab", 2, 20.0), "both clients report the grab")
	await sleep(0.5)
	var got := 0
	var grants := 0
	var denies := 0
	var views := {1: _loadouts()}
	for p in [c1, c2]:
		var r: Dictionary = reported(p, "grab")
		var who := "c1" if p == c1 else "c2"
		print("[M3] %s: has %s %s with %d charges; %d grant(s), %d refusal(s); requested %s" % [who, SPELL, "yes" if bool(r["has"]) else "no", int(r["charges"]), int(r["grants"]), int(r["denies"]), str(r["asked"])])
		check(bool(r["asked"]), "%s's screen asked the host for it" % who)
		if bool(r["has"]):
			got += 1
			eq(int(r["charges"]), SpellComponents.PICKUP_CHARGES, "%s got all %d charges" % [who, SpellComponents.PICKUP_CHARGES])
		grants += int(r["grants"])
		denies += int(r["denies"])
		check(not bool(r["still_there"]), "%s's copy of the pickup is gone" % who)
	eq(got, 1, "EXACTLY ONE client got the pickup")
	eq(grants, 1, "the host granted it once")
	check(denies >= 1, "and refused the other (%d refusals)" % denies)
	# Everyone sees the same slots and charges on every hero.
	for p in [c1, c2]:
		command(p, "loadouts")
	check(await wait_reports("loadouts", 2, 20.0), "both clients report every hero's slots")
	for p in [c1, c2]:
		views[int(Session.roster[p]["seat"])] = reported(p, "loadouts")
	for owner: int in views:
		var own := str((views[owner] as Dictionary)[owner])
		for viewer: int in views:
			if viewer != owner:
				eq(str((views[viewer] as Dictionary)[owner]), own, "seat %d sees seat %d's slots and charges as its owner has them" % [viewer, owner])

	# 3. Employees.
	var emps: Array = site.employees.filter(func(e: Actor) -> bool: return is_instance_valid(e) and not e.dead)
	if not check(emps.size() >= 3, "the floor has three employees (%d)" % emps.size()):
		return
	for w: Employee in emps:
		w.set_modifier("test_ward", 0.0, 999.0)   # (the floor's monsters may roam near them: only the test loses one)
	var e: Employee = emps[0]
	var eid := NetFloor.id_of(e)
	command(c1, "recruit", {"id": eid})
	check(await until(func() -> bool: return e.is_following() and e.leader() == hero_at(2), 6.0), "c1's E made the employee follow c1's hero, on the host")
	check(await wait_reports("recruit", 1, 20.0), "c1 walked off with it")
	await sleep(1.5)
	for p in [c1, c2]:
		command(p, "employee", {"id": eid})
	check(await wait_reports("employee", 2, 20.0), "both clients report the employee")
	for p in [c1, c2]:
		var r: Dictionary = reported(p, "employee")
		var who := "c1" if p == c1 else "c2"
		eq(int(r["state"]), Employee.State.FOLLOW, "%s shows it following" % who)
		eq(int(r["leader"]), 2, "%s shows it following c1's hero (seat 2)" % who)
		var d := Vector2(r["pos"].x, r["pos"].z).distance_to(Vector2(e.global_position.x, e.global_position.z))
		check(d < 1.5, "%s shows it about where the host has it (%.2f)" % [who, d])
	check(e.global_position.distance_to(hero_at(2).global_position) < 4.0, "it walked after c1's hero on the host")
	command(c1, "dismiss", {"id": eid})
	# (told to wait = dismissed: a monster near makes a waiting employee PANIC within a scan, 0.2 s, so WAIT itself can be
	# gone before this looks; the next check compares every screen's state, whatever it is)
	check(await until(func() -> bool: return e.is_waiting() and e.leader() == null, 6.0), "c1's second E told it to wait, on the host")
	check(await wait_reports("dismiss", 1, 20.0), "c1 pressed E again")
	# Every screen agrees with the host about it (its state can move on: a waiting employee still panics at a monster).
	var agreed := false
	var tries := 0
	while not agreed and tries < 8:
		tries += 1
		await sleep(0.4)
		reports[c1].erase("employee")
		reports[c2].erase("employee")
		for p in [c1, c2]:
			command(p, "employee", {"id": eid})
		var host_state := e.state
		if not await wait_reports("employee", 2, 20.0):
			break
		agreed = e.state == host_state
		for p in [c1, c2]:
			var r: Dictionary = reported(p, "employee")
			agreed = agreed and int(r["state"]) == host_state and bool(r["dismissed"]) and int(r["leader"]) == 0
	check(agreed, "every screen shows it waiting as the host has it: dismissed, following nobody, state %s (after %d looks)" % [e.state_name(), tries])
	await _far_e(e, c1, c2)
	# Lose one, extract one.
	var lost: Employee = emps[1]
	var saved: Employee = emps[2]
	var lost_id := NetFloor.id_of(lost)
	var saved_id := NetFloor.id_of(saved)
	lost.clear_modifier("test_ward")
	lost.apply_damage(9999.0, null)
	var riders: Array[Actor] = [saved]
	game.call("_extract_followers", riders, "thank you!")
	await sleep(0.8)
	var sess: ContractSession = game.get("_session")
	eq(sess.lost.size(), 1, "the host lost one employee")
	eq(sess.extracted_total, 1, "and extracted one")
	for p in [c1, c2]:
		command(p, "books", {"lost": lost_id, "saved": saved_id})
	check(await wait_reports("books", 2, 20.0), "both clients report the books")
	for p in [c1, c2]:
		var r: Dictionary = reported(p, "books")
		var who := "c1" if p == c1 else "c2"
		check(bool(r["lost_dead"]), "%s shows the lost employee dead" % who)
		check(bool(r["saved_out"]), "%s shows the other one extracted" % who)
		eq(int(r["lost"]), 1, "%s's tracker counts one lost (the host's books)" % who)
		eq(int(r["extracted"]), 1, "%s's tracker counts one extracted" % who)
		eq(int(r["extract_pay"]), _lines("Employee extracted"), "%s's Ledger pays the extraction as often as the host's" % who)
		eq(str(r["ledger"]), _ledger_text(), "%s's Ledger is the host's, line for line" % who)
	var st := Session.snap.stats
	var span := maxf(Session.host_time() - float(st["since"]), 0.001)
	print("[M3] per client over %.1f s of this floor (nobody fighting): heroes %.0f B/s + world %.0f B/s; biggest packet %d B" % [
		span, float(st["out_bytes"]) / span / 2.0, float(st["world_out_bytes"]) / span / 2.0, int(st["packet_max"])])
	for p in [c1, c2]:
		command(p, "end")
	check(await wait_done(2, 30.0), "both clients are done")


func run_client() -> void:
	if not await enter_floor(SEED, 1):
		return
	# (since M4 the host's monsters hurt a client's hero, decided on the client: ward it like the host's, or a roaming brute
	# can down it mid-test and its E does nothing)
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	if not await wait_sync():
		return
	var asked := {}
	var grants := [0]
	var denies_before := 0
	Session.objects.granted.connect(func(_k: String, _s: String, _n: int) -> void: grants[0] += 1)
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"hit":
				await until(func() -> bool: return Session.host_time() >= float(cmd["t"]), 5.0)
				var prop := NetRegistry.node(int(cmd["prop"])) as PricedProp
				var label := prop.display_name if prop != null else ""
				if prop != null:
					prop.apply_damage(9999.0, my_hero())   # (a copy: the hit goes to the host)
				if index == 1:
					var crate := NetRegistry.node(int(cmd["crate"])) as Actor
					if crate != null:
						crate.apply_damage(1.0, my_hero())
				else:
					var mail := NetRegistry.node(int(cmd["mail"])) as Actor
					if mail != null:
						mail.apply_damage(1.0, my_hero())
				var ids := [int(cmd["prop"]), int(cmd["crate"]), int(cmd["mail"])]
				await until(func() -> bool: return ids.all(func(i: int) -> bool: return NetRegistry.node(i) == null or (NetRegistry.node(i) as Actor).dead), 5.0)
				await sleep(0.6)
				var m := NetRegistry.node(int(cmd["mail"])) as MailPackage
				var pick_id := 0
				var pick_spell := ""
				for id in Session.objects.pickup_ids():
					var pk := NetRegistry.node(id) as ComponentPickup
					if pk != null:
						pick_id = id
						pick_spell = pk.spell_id
				report("hit", {"prop": _gone(ids[0]), "crate": _gone(ids[1]), "mail": _gone(ids[2]), "bills": _damage_lines(label),
					"billed": _damage_total(label), "contents": m.contents if m != null else "(freed)", "mail_pickup": pick_id, "mail_spell": pick_spell})
			"grab":
				var id := int(cmd["id"])
				await until(func() -> bool: return NetRegistry.node(id) != null, 5.0)
				denies_before = int(Session.objects.stats["denies"])
				var requests_before := int(Session.objects.stats["requests"])
				await until(func() -> bool: return Session.host_time() >= float(cmd["t"]), 5.0)
				var at: Vector3 = cmd["at"]
				my_hero().global_position = at + Vector3(0.1 * index, 0.0, 0.0)
				my_hero().snap_to_ground()
				await until(func() -> bool: return int(Session.objects.stats["requests"]) > requests_before, 2.0)
				asked["grab"] = int(Session.objects.stats["requests"]) > requests_before
				await until(func() -> bool: return NetRegistry.node(id) == null or (NetRegistry.node(id) as ComponentPickup)._used, 5.0)
				await sleep(0.4)
				var h := my_hero()
				report("grab", {"has": h.spell_slots.has(SPELL), "charges": h.charges_of(SPELL), "grants": grants[0],
					"denies": int(Session.objects.stats["denies"]) - denies_before, "asked": asked.get("grab", false),
					"still_there": NetRegistry.node(id) != null and not (NetRegistry.node(id) as ComponentPickup)._used})
			"loadouts":
				report("loadouts", _loadouts())
			"recruit":
				var e := NetRegistry.node(int(cmd["id"])) as Employee
				_stand_beside(e.global_position, 1.0)
				await sleep(0.3)
				var used := (game.get("controller") as PlayerController).press_use()
				check(used, "E is used on the employee (it is a request)")
				await until(func() -> bool: return e.is_following(), 4.0)
				# Walk a few steps away: it follows.
				var away := my_hero().global_position + (my_hero().global_position - e.global_position).normalized() * 2.5
				my_hero().global_position = Vector3(away.x, my_hero().global_position.y, away.z)
				my_hero().snap_to_ground()
				report("recruit", true)
			"dismiss":
				var e := NetRegistry.node(int(cmd["id"])) as Employee
				# WALK up to it, to about 1.75: inside the follower's resting band (Employee.FOLLOW_MIN 1.5 .. FOLLOW_SETTLE 2.2), where
				# it stands still. The old way, a jump to 1.0 on any open side, was the M6 flake (networking-build-plan.md, M7 as
				# built): inside FOLLOW_MIN the follower backs off and overshoots to 1.7-2.3, and a jump of under 3 units is no
				# teleport to the snapshot, so the host showed c1's hero LUNGING at the employee at the velocity clamp (15.9 u/s,
				# extrapolated), which pushed the follower further out still; the E then landed on the edge of WAIT_RANGE (2.2),
				# judged by the host against an employee moving away (since 2026-10-18 the host trusts the client's reach: step 3b).
				# A real player walks, and so does this one.
				var c := game.get("controller") as PlayerController
				var used := false
				var tries := 0
				while tries < 3 and not e.is_dismissed():
					tries += 1
					await until(func() -> bool:
						var to := e.global_position - my_hero().global_position
						to.y = 0.0
						if to.length() <= 1.8:
							return true
						c.move_override = to.normalized()
						return false, 3.0)
					c.move_override = Vector3.INF
					await sleep(0.4)
					if c.press_use():
						used = true
						await until(func() -> bool: return e.is_dismissed(), 1.2)   # (the host's answer, in the snapshot)
					else:
						print("[test] E found nothing: c1 shows it %s, %.2f away (try %d)" % [e.state_name(),
							GameWorld.flat_distance(e.global_position, my_hero().global_position), tries])
				check(used, "E is used again (tell it to wait), in %d tries" % tries)
				report("dismiss", true)
			"far_e":
				# Step 3b: stand FAR_E from where the HOST has the employee and ask, as if this screen had found it within
				# reach (the client's word on range is what the host now trusts).
				var e := NetRegistry.node(int(cmd["id"])) as Employee
				var pos: Vector3 = cmd["pos"]
				await until(func() -> bool: return Session.host_time() >= float(cmd["t"]), 5.0)
				my_hero().global_position = _open_spot_from(pos, FAR_E, 0 if index == 1 else 4)   # (placed in the frame it asks)
				my_hero().snap_to_ground()
				var sent := Session.objects.request(e, str(cmd["what"]))
				report("far_e", {"sent": sent, "d": GameWorld.flat_distance(my_hero().global_position, pos)})
			"employee":
				var e := NetRegistry.node(int(cmd["id"])) as Employee
				var ld := e.leader()
				report("employee", {"state": e.state, "leader": NetFloor.id_of(ld) if ld != null else 0, "pos": e.global_position, "dismissed": e.is_dismissed()})
			"books":
				var lost := NetRegistry.node(int(cmd["lost"])) as Employee
				var saved := NetRegistry.node(int(cmd["saved"])) as Employee
				var sess: ContractSession = game.get("_session")
				report("books", {"lost_dead": lost == null or lost.dead, "saved_out": saved == null or saved.is_extracted(), "lost": sess.lost.size(),
					"extracted": sess.extracted_total, "extract_pay": _lines("Employee extracted"), "ledger": _ledger_text()})
			_:
				running = false


# --- Helpers ---------------------------------------------------------------------------------------------------

## Host, step 3b: E on the client's word. The employee is held still on the host (its AI paused for the step), so the distance
## the host measures from each client's spot is exactly FAR_E: out of E's reach as the host sees it.
func _far_e(e: Employee, c1: int, c2: int) -> void:
	var eid := NetFloor.id_of(e)
	e.set_physics_process(false)
	var from := Session.objects.employee_log.size()
	var t_ask := Session.host_time() + 0.8
	for p in [c1, c2]:
		command(p, "far_e", {"id": eid, "pos": e.global_position, "t": t_ask, "what": "follow"})
	check(await wait_reports("far_e", 2, 20.0), "both clients asked the employee to follow from %.1f away" % FAR_E)
	check(await until(func() -> bool: return Session.objects.employee_log.size() >= from + 2, 5.0), "the host judged both requests")
	var judged := Session.objects.employee_log.slice(from)
	var won := judged.filter(func(j: Dictionary) -> bool: return bool(j["granted"]))
	for j: Dictionary in judged:
		check(float(j["d"]) > Employee.RECALL_RANGE + 0.3, "seat %d asked from %.2f away as the host has it, out of E's reach there (refused for range before)" % [int(j["seat"]), float(j["d"])])
	if not check(won.size() == 1, "exactly one follow was granted (%d): the client's word on range is trusted, and the first one wins" % won.size()):
		e.set_physics_process(true)
		return
	var seat := int(won[0]["seat"])
	var lost: Array = judged.filter(func(j: Dictionary) -> bool: return not bool(j["granted"]))
	check(lost.size() == 1 and str(lost[0]["state"]) == "FOLLOW", "the other was refused: by then it followed seat %d (a conflicting request loses)" % seat)
	check(e.is_following() and e.leader() == hero_at(seat), "it follows seat %d's hero on the host" % seat)
	# Its leader tells it to wait, from as far: granted (only the state is judged).
	var leader_peer := Session.seats.owner_of(seat)
	reports[leader_peer].erase("far_e")
	command(leader_peer, "far_e", {"id": eid, "pos": e.global_position, "t": Session.host_time() + 0.3, "what": "wait"})
	check(await wait_reports("far_e", 2, 20.0), "seat %d asked it to wait from %.1f away" % [seat, FAR_E])
	check(await until(func() -> bool: return Session.objects.employee_log.size() >= from + 3, 5.0), "the host judged the wait")
	var w: Dictionary = Session.objects.employee_log.back()
	check(str(w["what"]) == "wait" and bool(w["granted"]) and float(w["d"]) > Employee.WAIT_RANGE + 0.3,
		"the wait from %.2f away was granted (it was following that hero)" % float(w["d"]))
	check(e.is_dismissed() and e.leader() == null, "it waits, on the host")
	e.set_physics_process(true)


## How far (as the host has the employee) the clients stand when they ask in step 3b: out of E's reach (2.2) and of any slack.
const FAR_E := 3.5


## Walkable floor `dist` from `p`, trying the eight directions from `k0` on (two clients asking at once stand apart).
func _open_spot_from(p: Vector3, dist: float, k0: int) -> Vector3:
	var map := game.get("map") as HexMap
	for i in 8:
		var a := TAU * float((k0 + i) % 8) / 8.0
		var q := p + Vector3(cos(a), 0.0, sin(a)) * dist
		var c := Hex.from_world(q)
		if map.is_walkable_cell(c) and not map.blocks_point(q, 0.5) and absf(map.ground_height(q) - p.y) < 0.6:
			return Vector3(q.x, map.ground_height(q), q.z)
	return p


func _peer_named(n: String) -> int:
	for p: int in Session.roster:
		if str(Session.roster[p]["name"]) == n:
			return p
	return 0


func bot_stop_all() -> void:
	if bot != null:
		bot.stop()


func _gone(id: int) -> bool:
	var n := NetRegistry.node(id) as Actor
	return n == null or n.dead


## Every hero's slots and charges as this machine sees them: seat -> "slots|charges".
func _loadouts() -> Dictionary:
	var out := {}
	for seat in [1, 2, 3]:
		var h := hero_at(seat)
		if h == null:
			continue
		var parts: PackedStringArray = []
		for id in h.spell_slots:
			parts.append("%s:%d" % [id, h.charges_of(id)])
		out[seat] = ",".join(parts)
	return out


## Put this machine's hero `dist` from `p`, on open floor.
func _stand_beside(p: Vector3, dist: float) -> void:
	var spot := _open_spot(p, dist)
	my_hero().global_position = spot
	my_hero().snap_to_ground()


## Walkable floor about `dist` from `p` (the first of eight directions that has it).
func _open_spot(p: Vector3, dist: float) -> Vector3:
	var map := game.get("map") as HexMap
	for k in 8:
		var a := TAU * float(k) / 8.0
		var q := p + Vector3(cos(a), 0.0, sin(a)) * dist
		var c := Hex.from_world(q)
		if map.is_walkable_cell(c) and not map.blocks_point(q, 0.5) and absf(map.ground_height(q) - p.y) < 0.6:
			return Vector3(q.x, map.ground_height(q), q.z)
	return p


static func _lines(label: String) -> int:
	var n := 0
	for l in Ledger.lines:
		if str(l["label"]) == label:
			n += 1
	return n


static func _damage_lines(label: String) -> int:
	var n := 0
	for l in Ledger.lines:
		if str(l["kind"]) == "damage" and str(l["label"]) == label:
			n += 1
	return n


static func _damage_total(label: String) -> int:
	var t := 0
	for l in Ledger.lines:
		if str(l["kind"]) == "damage" and str(l["label"]) == label:
			t += int(l["amount"])
	return t


## The Ledger as one comparable text: kind|label|amount|who|floor per line.
static func _ledger_text() -> String:
	var parts: PackedStringArray = []
	for l in Ledger.lines:
		parts.append("%s|%s|%d|%s|%d" % [str(l["kind"]), str(l["label"]), int(l["amount"]), str(l["who"]), int(l["floor"])])
	return "\n".join(parts)
