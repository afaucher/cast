extends NetGameTest
## Ghost form online (docs/design/haunted-build-plan.md, "H7 as built"; GhostSpell), three processes, `off` and `coast`. Board 9's
## haunted contract, floor 1. Ghost form is a STATUS of the caster: the cast lands on every machine, the caster's owner applies
## the modifier and NetStatus announces it; every screen shows the look from it, and a late joiner gets it with the statuses.
## - THE CAST: c1 casts Ghost by its controller: on c1 its hero is in ghost form and wears the look; the host shows c1's hero in
##   ghost form with the look, and the host's monsters walk through it (Actor._walks_through, from the announced status);
## - THE LATE JOINER: c1 is in ghost form (a long one, the spell's own verb on its owner) when c2 joins: c2 shows c1's hero in
##   ghost form with the look, and its own hero not;
## - THE END: c1's form ends on its machine; the host and c2 drop the look;
## - nothing tripped the OWNER-write guard on any machine.

const PEERS := 3
const SEED := 9
const CONTRACT := 1
const JOINER_SPELLS := ["tentacles", "teeth"]


func run_host() -> void:
	net_timeout = 170.0
	clear_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	make_game({"spells": "coffee,fireball", "seed": SEED, "contract": CONTRACT, "net_wait": 2})
	if not check(await wait_floor(45.0), "floor 1 starts") or not await wait_sync():
		return
	(game.get("opts") as Dictionary).erase("net_wait")
	_still_world()
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	check(await wait_reports("ready", 1, 30.0), "c1 is on the floor")
	var b := hero_at(2)
	if not check(b != null and not Net.owns(b), "c1's hero is a puppet here"):
		return
	var bid := NetFloor.id_of(b)
	var mon: Monster = null
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster and not (n is Wisp) and not n.dead and (n as Monster).is_in_group("monsters"):
			mon = n
			break
	await sleep(1.0)
	check(not b.is_ghost_form() and not b.is_showing_ghost_form(), "c1's hero is no ghost yet")

	# 1. The cast: c1 casts Ghost; its machine applies it, the host shows it.
	command(c1(), "cast")
	check(await wait_reports("cast", 1, 10.0), "c1 cast Ghost")
	var r: Dictionary = reported(c1(), "cast")
	check(bool(r["ok"]) and bool(r["ghost"]), "on c1 its own hero is in ghost form")
	check(await until(func() -> bool: return b.is_ghost_form(), 3.0), "the host shows c1's hero in ghost form (the announced status)")
	check(await until(func() -> bool: return b.is_showing_ghost_form(), 1.0), "... wearing the ghost form's look")
	near(b.modifier_left(GhostSpell.MOD), GhostSpell.ghost_duration(1.0), 1.0, "... for the cast's duration (%.1f s left)" % b.modifier_left(GhostSpell.MOD))
	if check(mon != null, "a monster on the floor"):
		check(mon._walks_through(b, false), "the host's monster walks through c1's ghost-form hero")
	check(not my_hero().is_ghost_form() and not my_hero().is_showing_ghost_form(), "the host's own hero is no ghost")
	command(c1(), "look", {"ids": [bid], "tag": "own"})
	if check(await wait_reports("own", 1, 10.0), "c1 looked"):
		check(bool((reported(c1(), "own") as Dictionary)[bid]["showing"]), "c1 shows its own hero in the ghost form's look")

	# 2. The late joiner: c1 in a long ghost form while c2 joins.
	raise_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 30.0), "c2 joins the crew on the job"):
		return
	var c2 := peer_named("c2")
	if not check(await wait_reports("checkout", 1, 30.0), "c2 opened its license checkout"):
		return
	command(c1(), "form", {"secs": 60.0})
	check(await wait_reports("form", 1, 10.0), "c1 is in a long ghost form")
	check(await until(func() -> bool: return b.modifier_left(GhostSpell.MOD) > 30.0, 3.0), "the host has it (%.0f s left)" % b.modifier_left(GhostSpell.MOD))
	command(c2, "sign", {"spells": JOINER_SPELLS})
	if not check(await wait_reports("arrived", 1, 40.0), "c2 arrived"):
		return
	await sleep(1.5)
	var c2_seat := Session.seats.seat_of(c2) if Session.seats != null else 3
	var jid := NetFloor.id_of(hero_at(c2_seat))
	command(c2, "look", {"ids": [bid, jid], "tag": "joined"})
	if check(await wait_reports("joined", 1, 10.0), "c2 looked"):
		var j: Dictionary = reported(c2, "joined")
		check(bool(j[bid]["ghost"]) and bool(j[bid]["showing"]), "c2 (late) shows c1's hero in ghost form, in its look")
		check(float(j[bid]["left"]) > 20.0, "... with the status's time left (%.0f s)" % float(j[bid]["left"]))
		check(not bool(j[jid]["ghost"]) and not bool(j[jid]["showing"]), "c2's own hero is no ghost")

	# 3. The end: c1's form ends on its machine; the others drop the look.
	command(c1(), "unform")
	check(await wait_reports("unform", 1, 10.0), "c1's form ended there")
	check(await until(func() -> bool: return not b.is_ghost_form() and not b.is_showing_ghost_form(), 3.0), "the host drops c1's ghost form")
	await sleep(1.0)
	reports[c2].erase("joined")
	command(c2, "look", {"ids": [bid], "tag": "joined"})
	if check(await wait_reports("joined", 1, 10.0), "c2 looked again"):
		var j: Dictionary = reported(c2, "joined")
		check(not bool(j[bid]["ghost"]) and not bool(j[bid]["showing"]), "c2 drops it too")

	command(c2, "end")
	command(c1(), "end")
	check(await wait_reports("end", 2, 10.0), "the clients are done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	for p in [c1(), c2]:
		eq(int((reported(p, "end") as Dictionary)["guard"]), 0, "... nor on %s" % ("c1" if p == c1() else "c2"))
	clear_flag("join")


func run_client() -> void:
	net_timeout = 170.0
	if index == 2:
		await _late_joiner()
		return
	if not check(await connect_client() == "", "joined"):
		return
	make_game({"spells": "ghost,coffee"})
	if not check(await wait_floor(45.0), "the floor starts here") or not await wait_sync():
		return
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	report("ready", true)
	await _serve()


func _late_joiner() -> void:
	var since := Time.get_unix_time_from_system()
	if not check(await wait_flag("join", since, 140.0), "the host raised the join flag"):
		return
	if not check(await connect_client() == "", "joined the crew on the job"):
		return
	make_game({})
	if not check(await until(func() -> bool: return picker() != null, 30.0), "c2's license checkout opened"):
		return
	report("checkout", true)
	var sign_cmd := await wait_command(30.0)
	if not check(str(sign_cmd.get("cmd", "")) == "sign", "the host says sign"):
		return
	check(await sign_license(sign_cmd["spells"] as Array), "c2 signs")
	if not check(await until(func() -> bool: return Session.join.arrived, 40.0), "c2 arrived on the crew's floor"):
		return
	await wait_floor(10.0)
	report("arrived", true)
	await _serve()


func _serve() -> void:
	var running := true
	while running:
		var cmd := await wait_command(120.0)
		match str(cmd.get("cmd", "")):
			"cast":
				var c := game.get("controller") as PlayerController
				my_hero().reset_spell_cooldowns()
				c.aim_override = my_hero().global_position + Vector3(2.0, 0.0, 0.0)
				var ok := c.cast_spell("ghost", 1.0)
				c.aim_override = Vector3.INF
				await sleep(NetCasts.LEAD + 0.3)
				report("cast", {"ok": ok, "ghost": my_hero().is_ghost_form()})
			"form":
				GhostSpell.transform(my_hero(), float(cmd["secs"]))   # (the spell's own verb, on the owner)
				await sleep(0.2)
				report("form", true)
			"unform":
				my_hero().clear_modifier(GhostSpell.MOD)
				await sleep(0.2)
				report("unform", not my_hero().is_ghost_form())
			"look":
				await sleep(0.2)
				var out := {}
				for id: int in cmd["ids"]:
					var h := NetRegistry.node(id) as Hero
					var valid := h != null and is_instance_valid(h)
					out[id] = {"ghost": valid and h.is_ghost_form(), "showing": valid and h.is_showing_ghost_form(),
						"left": h.modifier_left(GhostSpell.MOD) if valid else 0.0}
				report(str(cmd["tag"]), out)
			"end":
				report("end", {"guard": Net.guard_hits.size()})
				running = false
			_:
				running = false


# --- Helpers ---------------------------------------------------------------------------------------------------

func c1() -> int:
	return peer_named("c1")


## Monsters and gates stand still and the AI seats hold (nothing walks into the test's heroes).
func _still_world() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster or n is Hellgate:
			n.set_physics_process(false)
	for seat in [2, 3]:
		var h := hero_at(seat)
		if h == null:
			continue
		var brain := h.get_node_or_null("AllyBrain")
		if brain != null:
			brain.set_physics_process(false)
