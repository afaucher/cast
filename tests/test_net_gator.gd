extends NetGameTest
## The sewer gator online (docs/design/sewer-concept.md, "Phase 2 as built"), three processes, `off` and `coast`. Floor 2 of
## the seed-7 job (offer 2) has a four-room sewer cluster with two gators. The host and c1 play it; c2 joins later, on the job.
## - THE NIP, THE VICTIM DECIDES: c1's hero stands in front of gator A's head, inside its territory; the host's gator winds
##   up and nips (world.windup, the wind-up and the lunge); c1's own machine resolves it on its hero from the event (one
##   strike, NIP_DAMAGE, the hero shoved away from the gator); the host applied nothing to that hero and shows its HP as c1
##   has it;
## - THE SHOVE, A REQUEST: c1 shoves gator A from across the room (Actor.shove on a copy -> obj.req shove); the host's gator
##   slides like any body, and c1's puppet shows it where the host has it;
## - THE LATE JOINER: c2 joins the floor and sees both gators where the host has them (the keyframe), as puppets;
## - THE KILL, THE HOST DECIDES: c1's blows on gator A are requests; its killing blow kills it on the host, which bills it once
##   ("Gator", $6,300, to c1's hero), and c1's and c2's mirrored Ledgers are the host's line for line; both show it dead;
## - nothing tripped the OWNER-write guard on any machine.

const PEERS := 3
const SEED := 7
const CONTRACT := 1
const FLOOR := 2
const JOINER_SPELLS := ["tentacles", "teeth"]
const SHOVE := 2.0


func run_host() -> void:
	net_timeout = 150.0
	follow_reloads = true
	clear_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	make_game({"spells": "heal,corn", "seed": SEED, "contract": CONTRACT, "net_wait": 2, "floor": FLOOR})
	if not check(await wait_floor(45.0), "floor %d starts" % FLOOR) or not await wait_sync():
		return
	(game.get("opts") as Dictionary).erase("net_wait")
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	var site: SiteBuilder.Site = game.get("_site")
	if not check(site.gators.size() == 2, "the floor has two gators (%d)" % site.gators.size()):
		return
	var ga: Gator = site.gators[0]
	var gb: Gator = site.gators[1]
	check(not Net.is_copy(ga) and not Net.is_copy(gb), "the host runs its gators")
	_quiet_floor(site)
	var ai := hero_at(3)
	var brain := ai.get_node_or_null("AllyBrain")
	if brain != null:
		brain.set_physics_process(false)
	var far := _far_spot(site.gators)
	_put(my_hero(), far)
	_put(ai, _far_spot(site.gators, 7))
	check(await wait_reports("ready", 1, 30.0), "c1 is on the floor")
	command(c1(), "look", {"ids": [NetFloor.id_of(ga), NetFloor.id_of(gb)]})
	check(await wait_reports("look", 1, 10.0), "c1 looked")
	check(bool((reported(c1(), "look") as Dictionary)["puppets"]), "c1 shows both gators as puppets of the host's")

	# 1. The nip: c1's hero in front of gator A's head.
	var spot := _nip_spot(ga)
	if not check(spot != Vector3.INF, "a spot in front of gator A with room to be shoved"):
		return
	var windups0 := int(Session.world.stats.get("windups", 0))
	command(c1(), "nip", {"id": NetFloor.id_of(ga), "at": spot, "away": _far_spot(site.gators, 3)})
	if not check(await wait_reports("nip", 1, 25.0), "c1 reports the nip"):
		return
	var b: Dictionary = reported(c1(), "nip")
	print("[gator] c1's nip: %s" % str(b))
	check(int(Session.world.stats.get("windups", 0)) > windups0, "the host's gator wound up a nip (world.windup)")
	eq(int(b["strikes"]), 1, "c1 resolved exactly one nip on its own machine")
	near(float(b["lost"]), Gator.NIP_DAMAGE, 0.05, "c1's hero lost NIP_DAMAGE")
	check(float(b["pushed"]) > 0.8, "... and was shoved away from the gator (%.2f)" % float(b["pushed"]))
	await sleep(0.5)
	near(hero_at(2).hp, float(b["hp"]), 0.6, "the host shows c1's hero's HP as c1 has it")

	# 2. The shove: c1 shoves gator A from where it stands (far off): a request the host's gator slides on.
	var dir := _open_dir(ga)
	if not check(dir != Vector3.ZERO, "gator A has room to slide"):
		return
	var from := ga.global_position
	command(c1(), "shove", {"id": NetFloor.id_of(ga), "d": dir})
	check(await until(func() -> bool: return (ga.global_position - from).dot(dir) > 1.0, 5.0), "c1's shove slid the host's gator (%.2f along it)" % (ga.global_position - from).dot(dir))
	check(await until(func() -> bool: return not ga.is_shoved(), 3.0), "... and it stands again")
	await sleep(0.3)
	var landed := ga.global_position
	command(c1(), "where", {"id": NetFloor.id_of(ga)})
	if check(await wait_reports("where", 1, 10.0), "c1 reports where its gator stands"):
		var w: Vector3 = reported(c1(), "where")
		check(_flat(w, landed) < 0.6, "c1's puppet stands where the host's gator landed (%.2f off)" % _flat(w, landed))

	# 3. The late joiner sees both gators where the host has them.
	ga._relocate_at = GameWorld.time + 9999.0
	gb._relocate_at = GameWorld.time + 9999.0
	raise_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 30.0), "c2 joins the crew on the job"):
		return
	var c2 := peer_named("c2")
	if not check(await wait_reports("checkout", 1, 30.0), "c2 opened its license checkout"):
		return
	command(c2, "sign", {"spells": JOINER_SPELLS})
	if not check(await wait_reports("arrived", 1, 40.0), "c2 arrived"):
		return
	await sleep(1.0)
	command(c2, "gators", {"ids": [NetFloor.id_of(ga), NetFloor.id_of(gb)]})
	if check(await wait_reports("gators", 1, 10.0), "c2 reports its gators"):
		var gr: Dictionary = reported(c2, "gators")
		check(bool(gr["puppets"]), "c2 shows both gators as puppets")
		var at: Array = gr["at"]
		check(_flat(at[0], ga.global_position) < 0.6, "c2: gator A where the host has it (%.2f off)" % _flat(at[0], ga.global_position))
		check(_flat(at[1], gb.global_position) < 0.6, "c2: gator B where the host has it (%.2f off)" % _flat(at[1], gb.global_position))

	# 4. The kill: c1's blows, the host's bill.
	var lines_before := Ledger.lines.size()
	command(c1(), "kill", {"id": NetFloor.id_of(ga)})
	check(await until(func() -> bool: return ga.dead, 10.0), "c1's killing blow killed gator A on the host")
	await sleep(0.6)
	var bills := 0
	for line: Dictionary in Ledger.lines.slice(lines_before):
		if str(line["label"]) == "Gator":
			bills += 1
			eq(int(line["amount"]), 6300, "the kill bills the gator's price ($6,300)")
			eq(str(line["who"]), hero_at(2).display_name, "... to c1's hero")
	eq(bills, 1, "the kill bills once")
	print("[gator] the kill: %d Gator line(s) on the host; Ledger %s" % [bills, ledger_text()])
	check(not gb.dead, "gator B lives on")
	check(await wait_reports("kill", 1, 10.0), "c1 reports the kill")
	var kr: Dictionary = reported(c1(), "kill")
	check(bool(kr["dead"]), "c1 shows gator A dead")
	eq(str(kr["ledger"]), ledger_text(), "c1's Ledger is the host's, line for line")
	command(c2, "after", {"id": NetFloor.id_of(ga)})
	if check(await wait_reports("after", 1, 10.0), "c2 reports the kill"):
		var ar: Dictionary = reported(c2, "after")
		check(bool(ar["dead"]), "c2 shows gator A dead")
		eq(str(ar["ledger"]), ledger_text(), "c2's Ledger is the host's, line for line (one Gator line)")
	command(c2, "end")
	command(c1(), "end")
	check(await wait_reports("end", 2, 10.0), "the clients are done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	for p in [c1(), c2]:
		eq(int((reported(p, "end") as Dictionary)["guard"]), 0, "... nor on %s" % ("c1" if p == c1() else "c2"))


func run_client() -> void:
	net_timeout = 150.0
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
		var cmd := await wait_command(90.0)
		match str(cmd.get("cmd", "")):
			"look":
				var all_puppets := true
				for id: int in cmd["ids"]:
					all_puppets = all_puppets and Net.is_puppet(NetRegistry.node(id))
				report("look", {"puppets": all_puppets})
			"nip":
				var id := int(cmd["id"])
				var g := NetRegistry.node(id) as Gator
				var before := Session.world.resolved.size()
				_put(my_hero(), cmd["at"])
				var start := my_hero().global_position
				var hp := my_hero().hp
				await until(func() -> bool: return _strikes_of(id, before, NetFloor.id_of(my_hero())) >= 1, 18.0)
				await sleep(1.0)
				var out := my_hero().global_position - start
				var away := start - g.global_position
				away.y = 0.0
				out.y = 0.0
				report("nip", {"strikes": _strikes_of(id, before, NetFloor.id_of(my_hero())), "lost": hp - my_hero().hp,
					"hp": my_hero().hp, "pushed": out.dot(away.normalized()) if away.length() > 0.01 else 0.0})
				_put(my_hero(), cmd["away"])   # (out of its reach for the rest)
			"shove":
				var g := NetRegistry.node(int(cmd["id"])) as Gator
				g.shove(cmd["d"], SHOVE, my_hero())   # (a copy: obj.req shove; the host slides it)
			"where":
				await sleep(0.6)
				report("where", (NetRegistry.node(int(cmd["id"])) as Node3D).global_position)
			"kill":
				var g := NetRegistry.node(int(cmd["id"])) as Gator
				for _i in 4:
					if g.dead:
						break
					g.apply_damage(50.0, my_hero())   # (a copy: obj.req hit, the host applies it)
					await sleep(0.15)
				await until(func() -> bool: return g.dead, 8.0)
				await sleep(0.6)
				report("kill", {"dead": g.dead, "ledger": ledger_text()})
			"end":
				report("end", {"guard": Net.guard_hits.size()})
				running = false
			_:
				running = false


## c2: join the crew on the job and report the gators it finds.
func _late_joiner() -> void:
	var since := Time.get_unix_time_from_system()
	if not check(await wait_flag("join", since, 110.0), "the host raised the join flag"):
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
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"gators":
				var at: Array = []
				var puppets := true
				for id: int in cmd["ids"]:
					var g := NetRegistry.node(id) as Gator
					puppets = puppets and g != null and Net.is_puppet(g) and not g.dead
					at.append(g.global_position if g != null else Vector3.INF)
				report("gators", {"at": at, "puppets": puppets})
			"after":
				var g := NetRegistry.node(int(cmd["id"])) as Gator
				await until(func() -> bool: return g == null or g.dead, 6.0)
				await sleep(0.4)
				report("after", {"dead": g == null or g.dead, "ledger": ledger_text()})
			"end":
				report("end", {"guard": Net.guard_hits.size()})
				running = false
			_:
				running = false


func c1() -> int:
	return peer_named("c1")


func _strikes_of(id: int, before: int, victim: int = 0) -> int:
	var n := 0
	for r: Array in Session.world.resolved.slice(before):
		if int(r[0]) == id and (victim == 0 or int(r[1]) == victim):
			n += 1
	return n


## Nothing but the gators acts: the other monsters and the gates hold still, the employees too, and none stands near a
## gator (it would be nipped, or nip c1's hero first). The gators never relocate during the test.
func _quiet_floor(site: SiteBuilder.Site) -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if (n is Monster and not (n is Gator)) or n is Hellgate or n is Employee:
			n.set_physics_process(false)
			for g: Gator in site.gators:
				if GameWorld.flat_distance((n as Node3D).global_position, g.global_position) < 9.0:
					if n is Employee:
						_put(n as Actor, _far_spot(site.gators, 11))
					else:
						(n as Actor).die()
					break
	for g: Gator in site.gators:
		g._relocate_at = GameWorld.time + 9999.0


func _put(a: Actor, at: Vector3) -> void:
	a.global_position = at
	a.snap_to_ground()


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


## Where c1's hero stands to be nipped: 1.2 in front of the gator's head (any side, its front first), on open floor about
## its level, with a clear run beyond it (so the nip's shove slides free: no wall slam on top of the bite).
func _nip_spot(g: Gator) -> Vector3:
	var map := game.get("map") as HexMap
	var f := Vector2(g.facing.x, g.facing.z).normalized()
	for i in 16:
		var k := (i + 1) / 2 * (1 if i % 2 == 0 else -1)
		var d2 := f.rotated(float(k) * TAU / 16.0)
		var dir := Vector3(d2.x, 0.0, d2.y)
		var p := g.global_position + dir * (Gator.HEAD + 1.2)
		if _clear_run(map, p, dir, 2.6, g.global_position.y):
			var gh := map.ground_height(p)
			return Vector3(p.x, gh, p.z)
	return Vector3.INF


## A direction the gator can slide SHOVE along freely, or zero.
func _open_dir(g: Gator) -> Vector3:
	var map := game.get("map") as HexMap
	for i in 12:
		var a := float(i) * TAU / 12.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		if _clear_run(map, g.global_position + dir * 0.3, dir, SHOVE + 0.6, g.global_position.y):
			return dir
	return Vector3.ZERO


## Open, walkable floor from `p` for `length` along `dir`, never more than a step from `y`.
static func _clear_run(map: HexMap, p: Vector3, dir: Vector3, length: float, y: float) -> bool:
	var prev := p
	var t := 0.0
	while t <= length:
		var q := p + dir * t
		var c := Hex.from_world(q)
		var gh := map.ground_height(q)
		if not map.is_walkable_cell(c) or is_nan(gh) or absf(gh - y) > 0.6:
			return false
		if t > 0.0 and map.movement_check(prev, q) != HexMap.Move.OK:
			return false
		prev = q
		t += 0.25
	return true


## Open floor far from every gator (`skip` cells on).
func _far_spot(gators: Array, skip: int = 0) -> Vector3:
	var map := game.get("map") as HexMap
	var cells: Array = map.cells.keys()
	cells.sort()
	var n := 0
	for c: Vector2i in cells:
		if not map.is_walkable_cell(c) or map.is_pool_cell(c):
			continue
		var w := Hex.to_world(c)
		var ok := true
		for g: Gator in gators:
			if GameWorld.flat_distance(w, g.global_position) < 14.0:
				ok = false
		if ok:
			n += 1
			if n > skip:
				var lv := map.ground_level(w)
				return Hex.to_world(c, 0.0 if is_nan(lv) else lv)
	return Vector3.ZERO
