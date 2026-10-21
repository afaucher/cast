extends NetGameTest
## Pool sharks online (docs/design/sharks.md "As built", "Networking"), three processes, `off` and `coast`. Floor 3 of the
## seed-170 job (offer 1) holds a regular shark and an imp-ridden laser shark. (It was floor 3 of the seed-16 job, offer 3,
## until crew floors got sewer clusters, sewer phase 2: that floor now has a cluster and one shark.)
## The host and c1 play it; c2 joins later, on the job.
## - THE BITE, THE VICTIM DECIDES: c1's hero stands at the regular shark's rim; the host's shark hunts it and bites once:
##   c1's own machine resolves it from the wind-up event (one strike, BITE_DAMAGE, its hero pushed back onto the deck, out
##   of the water); the host applied nothing to that hero itself and shows its HP as c1 has it;
## - THE KILL, THE HOST DECIDES: c1's hits on the regular shark are requests; its killing blow kills it on the host, which
##   bills it once ("Shark", $8,400, to c1's hero), and c1's mirrored Ledger is the host's line for line; c1 shows it dead;
## - THE LASER, A SCHEDULED EFFECT: the imp shark charges at c1's hero; the lock (world.lock) carries the shared fire time;
##   both machines fire the beam at that moment (within a frame and the clock's error) and c1's hero takes BEAM_DAMAGE once;
## - THE GUNNER: c1 shoves the imp gunner (a request to the host): the host knocks it off, both machines show it off its
##   shark and off the saddle, and it never remounts;
## - THE LATE JOINER: c2 joins the floor afterwards and sees the same sharks: the regular one gone (a gone id), the laser
##   shark alive with its gunner off it;
## - nothing tripped the OWNER-write guard on any machine.

const PEERS := 3
const SEED := 170
const CONTRACT := 0
const FLOOR := 3
const JOINER_SPELLS := ["tentacles", "teeth"]


func run_host() -> void:
	net_timeout = 110.0
	follow_reloads = true
	clear_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	make_game({"spells": "heal,corn", "seed": SEED, "contract": CONTRACT, "net_wait": 2, "floor": FLOOR})
	if not check(await wait_floor(45.0), "floor %d starts" % FLOOR) or not await wait_sync():
		return
	(game.get("opts") as Dictionary).erase("net_wait")
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	_freeze_world()
	var c1 := peer_named("c1")
	check(await wait_reports("ready", 1, 30.0), "c1 is on the floor")
	var site: SiteBuilder.Site = game.get("_site")
	var regular: Shark = null
	var laser: Shark = null
	for s in site.sharks:
		if s.variant == "regular" and regular == null:
			regular = s
		elif s.variant == "imp" and laser == null:
			laser = s
	if not check(regular != null and laser != null, "the floor has a regular shark and an imp laser shark (%d sharks)" % site.sharks.size()):
		return
	check(not Net.is_copy(regular) and not Net.is_copy(laser), "the host runs its sharks")
	var j := laser.rider
	check(j != null and j.get("mounted") == true, "the imp gunner rides the laser shark")
	var ai := hero_at(3)
	var brain := ai.get_node_or_null("AllyBrain")
	if brain != null:
		brain.set_physics_process(false)
	# the room's pack would be bitten too: clear every monster near the sharks' water (not the gunner)
	for id in NetRegistry.ids():
		var m := NetRegistry.node(id) as Monster
		if m == null or m.dead or m is Shark or m is Jockey:
			continue
		for s: Shark in site.sharks:
			if GameWorld.flat_distance(m.global_position, s.global_position) < 14.0:
				m.die()
				break
	_put(my_hero(), _far_spot(site.sharks))
	_put(ai, _far_spot(site.sharks, 7))
	command(c1, "look", {"ids": [NetFloor.id_of(regular), NetFloor.id_of(laser), NetFloor.id_of(j)]})
	check(await wait_reports("look", 1, 10.0), "c1 looked")
	var lk: Dictionary = reported(c1, "look")
	check(bool(lk["puppets"]), "c1 shows both sharks and the gunner as puppets of the host's")

	# 1. The bite: c1's hero at the regular shark's rim.
	var rim := _deck_spot(regular, 0.6)
	if not check(rim != Vector3.INF, "a deck spot at the regular shark's rim"):
		return
	command(c1, "bite", {"at": rim, "id": NetFloor.id_of(regular)})
	if not check(await wait_reports("bite", 1, 25.0), "c1 reports the bite"):
		return
	var b: Dictionary = reported(c1, "bite")
	eq(int(b["strikes"]), 1, "c1 resolved exactly one bite on its own machine")
	near(float(b["lost"]), Shark.BITE_DAMAGE, 0.05, "c1's hero lost BITE_DAMAGE")
	check(bool(b["out"]), "... and was pushed back onto the deck, out of the water (%.2f past the rim)" % float(b["past"]))
	await sleep(0.4)
	near(hero_at(2).hp, float(b["hp"]), 0.6, "the host shows c1's hero's HP as c1 has it")

	# 2. The kill: c1's blows, the host's bill.
	var lines_before := Ledger.lines.size()
	command(c1, "kill", {"id": NetFloor.id_of(regular)})
	check(await until(func() -> bool: return regular.dead, 10.0), "c1's killing blow killed the shark on the host")
	await sleep(0.5)
	var bills := 0
	for line: Dictionary in Ledger.lines.slice(lines_before):
		if str(line["label"]) == "Shark":
			bills += 1
			eq(int(line["amount"]), 8400, "the kill bills the shark's price ($8,400)")
			eq(str(line["who"]), hero_at(2).display_name, "... to c1's hero")
	eq(bills, 1, "the kill bills once")
	check(await wait_reports("kill", 1, 10.0), "c1 reports the kill")
	var kr: Dictionary = reported(c1, "kill")
	check(bool(kr["dead"]), "c1 shows the shark dead")
	eq(str(kr["ledger"]), ledger_text(), "c1's Ledger is the host's, line for line")

	# 3. The laser: the imp shark charges at c1's hero, out on the deck.
	var lane := _deck_spot(laser, 2.2)
	if not check(lane != Vector3.INF, "a deck spot in the laser shark's sight"):
		return
	command(c1, "stand", {"at": lane})
	check(await wait_reports("stood", 1, 10.0), "c1 stands on the deck")
	await sleep(0.5)
	var fired := [-1.0]
	var shown0 := laser._beam_shown
	laser._begin_charge(hero_at(2))
	command(c1, "laser", {"id": NetFloor.id_of(laser)})
	check(await until(func() -> bool: return laser.fire_at >= 0.0, 4.0), "the line locks on the host")
	check(await until(func() -> bool: return laser._beam_shown > shown0, 4.0), "the host fired the beam")
	fired[0] = Session.host_time() - (GameWorld.time - laser._beam_shown)
	if check(await wait_reports("laser", 1, 12.0), "c1 reports the beam"):
		var lr: Dictionary = reported(c1, "laser")
		check(float(lr["fired"]) > 0.0, "c1 fired the beam too")
		near(float(lr["fired"]), fired[0], 0.06, "... at the same moment on the shared clock (host %.3f, c1 %.3f)" % [fired[0], float(lr["fired"])])
		near(float(lr["lost"]), Shark.BEAM_DAMAGE, 0.05, "c1's hero took BEAM_DAMAGE once")
		eq(int(lr["hits"]), 1, "... in one hit")

	# 4. The gunner: c1 shoves it off.
	command(c1, "knock", {"id": NetFloor.id_of(j), "shark": NetFloor.id_of(laser)})
	check(await until(func() -> bool: return j.get("mounted") == false, 6.0), "c1's shove knocked the gunner off on the host")
	if check(await wait_reports("knock", 1, 10.0), "c1 reports the gunner"):
		var kn: Dictionary = reported(c1, "knock")
		check(not bool(kn["mounted"]), "c1 shows it off its shark")
		check(float(kn["off"]) > 0.6, "... away from the saddle (%.2f)" % float(kn["off"]))
	await sleep(1.0)
	check(j.get("mounted") == false and not laser.ridden(), "it never remounts")

	# 5. The late joiner.
	raise_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 30.0), "c2 joins the crew on the job"):
		return
	var c2 := peer_named("c2")
	if not check(await wait_reports("checkout", 1, 30.0), "c2 opened its license checkout"):
		return
	command(c2, "sign", {"spells": JOINER_SPELLS})
	if not check(await wait_reports("arrived", 1, 40.0), "c2 arrived"):
		return
	var ar: Dictionary = reported(c2, "arrived")
	check(bool(ar["regular_gone"]), "c2: the killed shark is gone")
	check(bool(ar["laser_alive"]), "c2: the laser shark is there")
	check(not bool(ar["mounted"]), "c2: its gunner is off it")
	command(c2, "end")
	command(c1, "end")
	check(await wait_reports("end", 2, 10.0), "the clients are done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	for p in [c1, c2]:
		eq(int((reported(p, "end") as Dictionary)["guard"]), 0, "... nor on %s" % ("c1" if p == c1 else "c2"))


func run_client() -> void:
	follow_reloads = true
	if index == 2:
		await _late_joiner()
		return
	if not check(await connect_client() == "", "joined"):
		return
	make_game({"spells": "heal,corn", "floor": FLOOR})
	if not check(await wait_floor(45.0), "the floor starts here") or not await wait_sync():
		return
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"look":
				var all_puppets := true
				for id: int in cmd["ids"]:
					all_puppets = all_puppets and Net.is_puppet(NetRegistry.node(id))
				report("look", {"puppets": all_puppets})
			"bite":
				var s := NetRegistry.node(int(cmd["id"])) as Shark
				var id := int(cmd["id"])
				var before := Session.world.resolved.size()
				my_hero().global_position = cmd["at"]
				my_hero().snap_to_ground()
				var hp := my_hero().hp
				await until(func() -> bool: return _strikes_of(id, before, NetFloor.id_of(my_hero())) >= 1, 18.0)
				await sleep(1.2)
				var p := Vector2(my_hero().global_position.x, my_hero().global_position.z)
				var past := -s.steer.rim(p) if s != null and s.steer != null else 0.0
				report("bite", {"strikes": _strikes_of(id, before, NetFloor.id_of(my_hero())), "lost": hp - my_hero().hp, "hp": my_hero().hp, "past": past,
					"out": past > 1.2 and not GameWorld.map.water_at(my_hero().global_position)})
				# out of its reach now (the far side of the room) for the rest
				my_hero().global_position = my_hero().global_position + Vector3(p.x - s.global_position.x, 0.0, p.y - s.global_position.z).normalized() * 1.5
				my_hero().snap_to_ground()
			"kill":
				var s := NetRegistry.node(int(cmd["id"])) as Shark
				for _i in 4:
					s.apply_damage(50.0, my_hero())   # (a copy: obj.req hit, the host applies it)
					await sleep(0.15)
				await until(func() -> bool: return s.dead, 8.0)
				await sleep(0.6)
				report("kill", {"dead": s.dead, "ledger": ledger_text()})
			"stand":
				my_hero().global_position = cmd["at"]
				my_hero().snap_to_ground()
				await sleep(0.2)
				report("stood", true)
			"laser":
				var s := NetRegistry.node(int(cmd["id"])) as Shark
				var hp := my_hero().hp
				var hits := [0]
				var last := [hp]
				var shown0 := s._beam_shown
				var t_end := wall() + 6.0
				while wall() < t_end and s._beam_shown <= shown0:
					await get_tree().process_frame
					if my_hero().hp < last[0] - 0.01:
						hits[0] += 1
					last[0] = my_hero().hp
				var fired := Session.host_time() - (GameWorld.time - s._beam_shown) if s._beam_shown > shown0 else -1.0
				for _i in 30:
					await get_tree().process_frame
					if my_hero().hp < last[0] - 0.01:
						hits[0] += 1
					last[0] = my_hero().hp
				report("laser", {"fired": fired, "lost": hp - my_hero().hp, "hits": hits[0]})
			"knock":
				var jk := NetRegistry.node(int(cmd["id"])) as Actor
				var s := NetRegistry.node(int(cmd["shark"])) as Shark
				jk.shove(jk.global_position - my_hero().global_position, 2.0, my_hero())   # (a copy: obj.req shove)
				await until(func() -> bool: return jk.get("mounted") == false, 6.0)
				await sleep(0.8)
				var off := 0.0
				if s.body != null and s.body.shark != null:
					off = jk.global_position.distance_to(s.body.saddle().origin)
				report("knock", {"mounted": jk.get("mounted"), "off": off})
			"end":
				report("end", {"guard": Net.guard_hits.size()})
				running = false
			_:
				running = false


## c2: join the crew on the job and report the sharks it finds.
func _late_joiner() -> void:
	var since := Time.get_unix_time_from_system()
	if not check(await wait_flag("join", since, 90.0), "the host raised the join flag"):
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
	await sleep(1.0)
	var site: SiteBuilder.Site = game.get("_site")
	var regular_gone := false
	var laser_alive := false
	var mounted := true
	for i in site.plan.sharks.size():
		var v := str(site.plan.sharks[i]["variant"])
		var node: Variant = site.sharks[i] if i < site.sharks.size() else null
		var alive: bool = node != null and is_instance_valid(node) and not (node as Shark).dead
		if v == "regular" and not alive:
			regular_gone = true
		if v == "imp" and alive:
			laser_alive = true
			var s := node as Shark
			if s.rider != null and is_instance_valid(s.rider):
				mounted = bool(s.rider.get("mounted"))
	report("arrived", {"regular_gone": regular_gone, "laser_alive": laser_alive, "mounted": mounted})
	var cmd := await wait_command(30.0)
	report("end", {"guard": Net.guard_hits.size()})


func _strikes_of(id: int, before: int, victim: int = 0) -> int:
	var n := 0
	for r: Array in Session.world.resolved.slice(before):
		if int(r[0]) == id and (victim == 0 or int(r[1]) == victim):
			n += 1
	return n


func _freeze_world() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if (n is Monster and not (n is Shark) and not (n is Jockey)) or n is Hellgate:
			n.set_physics_process(false)


func _put(h: Hero, at: Vector3) -> void:
	h.global_position = at
	h.snap_to_ground()


## Dry floor of the shark's room `out` beyond its rim, on the edge facing the camera most (else any edge).
func _deck_spot(s: Shark, out: float) -> Vector3:
	var map := game.get("map") as HexMap
	var rec := s.pool_record()
	var ol: Array = rec["outline"]
	var normals := PoolGeo.edge_normals(ol)
	var order: Array[int] = []
	for i in ol.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return normals[a].dot(ThemeGeo.CAMERA_DIR) > normals[b].dot(ThemeGeo.CAMERA_DIR))
	for i in order:
		var a: Vector2 = ol[i]
		var b: Vector2 = ol[(i + 1) % ol.size()]
		for t: float in [0.5, 0.35, 0.65]:
			var p := a.lerp(b, t) + normals[i] * out
			var w := Vector3(p.x, 0.0, p.y)
			var c := Hex.from_world(w)
			var cell := map.get_cell(c)
			if cell == null or not map.is_walkable_cell(c) or map.is_pool_cell(c) or cell.level != int(rec["deck_level"]):
				continue
			if s.steer.rim(p) > -(out - 0.3):
				continue
			return Vector3(p.x, float(rec["deck_level"]) * Hex.LEVEL_HEIGHT, p.y)
	return Vector3.INF


## Open floor far from every shark's water (`skip` cells on).
func _far_spot(sharks: Array, skip: int = 0) -> Vector3:
	var map := game.get("map") as HexMap
	var cells: Array = map.cells.keys()
	cells.sort()
	var n := 0
	for c: Vector2i in cells:
		if not map.is_walkable_cell(c) or map.is_pool_cell(c):
			continue
		var w := Hex.to_world(c)
		var ok := true
		for s: Shark in sharks:
			if GameWorld.flat_distance(w, s.global_position) < 14.0:
				ok = false
		if ok:
			n += 1
			if n > skip:
				var lv := map.ground_level(w)
				return Hex.to_world(c, 0.0 if is_nan(lv) else lv)
	return Vector3.ZERO
