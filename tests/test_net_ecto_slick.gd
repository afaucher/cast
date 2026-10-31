extends NetGameTest
## An ecto blob's slick online (docs/design/haunted-build-plan.md, H3b), three processes, `off` and `coast`. Board 9's second
## offer is a haunted mansion (the estate heir). The host and c1 play floor 1; c2 joins later, on the job. The slick is a
## runtime host-arbitrated object (EctoSlick, NetObjects.RUNTIME_OBJECTS): the host lays it a segment at a time, as a crawling
## blob does (EctoSlick.lay -> Net.announce -> obj.new), and decides its one change, washed (obj.slick).
## - THE SLICK, ON A CLIENT: the host lays chain A (eight segments) and one segment B under c1's hero; c1 has every segment (the
##   same ids, ends and drying moment) drawn as the ribbons, and its own hero walks at x EctoSlick.SLOW on B, full speed off it;
## - DAMP, THE HOST DECIDES: c1's Damp at A (a cast every machine runs) washes A on the host (its owner), and c1's copies of A
##   go too; B stays on both;
## - THE LATE JOINER: the host lays chain C as c2 clocks in; c2 arrives with exactly the host's live segments (C, and B if it
##   has not dried), the same ends and drying moments, none of the washed A;
## - nothing tripped the OWNER-write guard on any machine.
## (Three processes, not two: a late joiner needs a crew already on the floor; a host alone on a job admits nobody, NetJoin.)

const PEERS := 3
const SEED := 9
const CONTRACT := 1
const JOINER_SPELLS := ["tentacles", "teeth"]
const CHAIN_A := 900001
const CHAIN_B := 900002
const CHAIN_C := 900003


func run_host() -> void:
	net_timeout = 150.0
	clear_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	make_game({"spells": "damp,fireball", "seed": SEED, "contract": CONTRACT, "net_wait": 2})
	if not check(await wait_floor(45.0), "floor 1 starts") or not await wait_sync():
		return
	(game.get("opts") as Dictionary).erase("net_wait")
	var run: ContractRun = game.get("_run")
	if not check(run != null and run.family == ClientArchetype.FAMILY_DEAD, "a haunted contract (%s)" % (run.archetype_id if run != null else "none")):
		return
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	_freeze_world()
	if not check(await wait_reports("ready", 1, 30.0), "c1 is on the floor"):
		return
	var c1_at: Vector3 = reported(c1(), "ready")
	var base := my_hero().global_position
	var dir := _away(base, c1_at)

	# 1. The slick on c1: chain A by the host's hero, segment B under c1's hero.
	var a_ids: Array[int] = []
	var p := base + dir * 6.0   # (far enough that a drizzle on A's middle never reaches c1's B)
	for i in 8:
		var q := p + dir * EctoBlob.SLICK_STEP
		a_ids.append(NetFloor.id_of(EctoSlick.lay(_floor(p), _floor(q), CHAIN_A, i)))
		p = q
	var b := EctoSlick.lay(_floor(c1_at - Vector3(0.4, 0, 0)), _floor(c1_at + Vector3(0.4, 0, 0)), CHAIN_B, 0)
	var b_id := NetFloor.id_of(b)
	check(a_ids.min() >= NetRegistry.RUNTIME_BASE and b_id >= NetRegistry.RUNTIME_BASE, "the host gave every segment a runtime id")
	await sleep(0.8)
	var ids: Array[int] = a_ids.duplicate()
	ids.append(b_id)
	command(c1(), "look", {"ids": ids, "tag": "laid"})
	if check(await wait_reports("laid", 1, 10.0), "c1 looked at the slick"):
		var r: Dictionary = reported(c1(), "laid")
		for id in ids:
			var s := NetRegistry.node(id) as EctoSlick
			var row: Dictionary = r[id]
			check(bool(row["has"]), "c1 has segment %d (obj.new, same id)" % id)
			if bool(row["has"]):
				check((row["a"] as Vector3).distance_to(s.a) < 0.01 and (row["b"] as Vector3).distance_to(s.b) < 0.01, "... with the host's ends")
				near(float(row["end"]), _shared_end(s), 0.15, "... drying at the host's moment")
		eq(int(r["ribbons_a"]), 1, "c1 draws chain A as one ribbon")
		near(float(r["on"]), EctoSlick.SLOW, 0.001, "c1's own hero walks at x%.2f on B (its machine decides)" % EctoSlick.SLOW)
		if bool(r["off_clear"]):
			near(float(r["off"]), 1.0, 0.001, "... full speed off it")

	# 2. Damp: c1's cast at A washes it on the host; c1's copies go; B stays.
	var a_mid := NetRegistry.node(a_ids[4]) as EctoSlick
	command(c1(), "cast", {"spell": "damp", "aim": a_mid.global_position})
	check(await until(func() -> bool: return _all_gone_or_washed(a_ids), 8.0), "c1's Damp washed chain A on the host (its owner)")
	check(is_instance_valid(b) and not b.washed, "B, out of the drizzle, stays")
	check(int(Session.objects.stats.get("slick_out", 0)) >= 8, "the host told every wash (obj.slick)")
	await sleep(1.0)
	command(c1(), "look", {"ids": ids, "tag": "washed"})
	if check(await wait_reports("washed", 1, 10.0), "c1 looked again"):
		var r2: Dictionary = reported(c1(), "washed")
		for id in a_ids:
			check(not bool(r2[id]["live"]), "c1: A's segment %d washed away" % id)
		check(bool(r2[b_id]["live"]), "c1: B still there")

	# 3. The late joiner.
	raise_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 30.0), "c2 joins the crew on the job"):
		return
	var c2 := peer_named("c2")
	if not check(await wait_reports("checkout", 1, 30.0), "c2 opened its license checkout"):
		return
	var c_ids: Array[int] = []
	p = base - dir * 1.5
	for i in 6:
		var q := p - dir * EctoBlob.SLICK_STEP
		c_ids.append(NetFloor.id_of(EctoSlick.lay(_floor(p), _floor(q), CHAIN_C, i)))
		p = q
	command(c2, "sign", {"spells": JOINER_SPELLS})
	if not check(await wait_reports("arrived", 1, 40.0), "c2 arrived"):
		return
	await sleep(1.0)
	var live_ids := _live_ids()
	command(c2, "look", {"ids": live_ids + a_ids, "tag": "joined"})
	if check(await wait_reports("joined", 1, 10.0), "c2 looked"):
		var r3: Dictionary = reported(c2, "joined")
		for id in c_ids:
			if NetRegistry.node(id) is EctoSlick:
				check(bool(r3[id]["live"]), "c2 has chain C's segment %d" % id)
		for id in live_ids:
			var s := NetRegistry.node(id) as EctoSlick
			check(bool(r3[id]["live"]), "c2 has the host's live segment %d" % id)
			if bool(r3[id]["live"]):
				check((r3[id]["a"] as Vector3).distance_to(s.a) < 0.01 and (r3[id]["b"] as Vector3).distance_to(s.b) < 0.01, "... with its ends")
				near(float(r3[id]["end"]), _shared_end(s), 0.2, "... drying at the host's moment")
		for id in a_ids:
			check(not bool(r3[id]["has"]), "c2 never got washed segment %d" % id)
		eq(int(r3["count"]), live_ids.size(), "c2 has exactly the host's live segments (%d)" % live_ids.size())
		check(int(r3["ribbons_c"]) >= 1, "c2 draws chain C")
	command(c2, "end")
	command(c1(), "end")
	check(await wait_reports("end", 2, 10.0), "the clients are done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	for pr in [c1(), c2]:
		eq(int((reported(pr, "end") as Dictionary)["guard"]), 0, "... nor on %s" % ("c1" if pr == c1() else "c2"))
	print("[slick] objects: %d slick washes sent" % int(Session.objects.stats.get("slick_out", 0)))
	clear_flag("join")


func run_client() -> void:
	net_timeout = 150.0
	if index == 2:
		await _late_joiner()
		return
	if not check(await connect_client() == "", "joined"):
		return
	make_game({"spells": "damp,fireball"})
	if not check(await wait_floor(45.0), "the floor starts here") or not await wait_sync():
		return
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	await sleep(0.5)
	report("ready", my_hero().global_position)
	await _serve()


## c2: join the crew on the job, sign, arrive, then answer the host.
func _late_joiner() -> void:
	var since := Time.get_unix_time_from_system()
	if not check(await wait_flag("join", since, 120.0), "the host raised the join flag"):
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
		var cmd := await wait_command(90.0)
		match str(cmd.get("cmd", "")):
			"look":
				var out := {}
				for id: int in cmd["ids"]:
					var s := NetRegistry.node(id) as EctoSlick
					var has := s != null and is_instance_valid(s)
					out[id] = {"has": has, "live": has and not s.washed and EctoSlick.live().has(s),
						"a": s.a if has else Vector3.INF, "b": s.b if has else Vector3.INF,
						"end": _shared_end(s) if has else -1.0}
				out["count"] = EctoSlick.live().size()
				out["ribbons_a"] = _ribbons(CHAIN_A)
				out["ribbons_c"] = _ribbons(CHAIN_C)
				var h := my_hero()
				out["on"] = EctoSlick.speed_mult(h)
				var at := h.global_position
				h.global_position = at + Vector3(0, 0, 3.0)
				out["off"] = EctoSlick.speed_mult(h)
				out["off_clear"] = not EctoSlick.covers_any(h.global_position, h.radius)
				h.global_position = at
				report(str(cmd["tag"]), out)
			"cast":
				var c := game.get("controller") as PlayerController
				my_hero()._ready_at.clear()
				c.aim_override = cmd["aim"]
				check(c.cast_spell(str(cmd["spell"]), 1.0), "%s cast %s" % [Session.player_name, cmd["spell"]])
				c.aim_override = Vector3.INF
			"end":
				report("end", {"guard": Net.guard_hits.size()})
				running = false
			_:
				running = false


# --- Helpers ---------------------------------------------------------------------------------------------------

func c1() -> int:
	return peer_named("c1")


## A segment's drying moment on the shared clock (comparable across machines).
static func _shared_end(s: EctoSlick) -> float:
	return Session.host_time() + (s._end - GameWorld.time)


static func _ribbons(chain: int) -> int:
	var n := 0
	for r in (EctoSlick._looks.get(chain, []) as Array):
		if is_instance_valid(r):
			n += 1
	return n


func _live_ids() -> Array[int]:
	var out: Array[int] = []
	for s in EctoSlick.live():
		out.append(NetFloor.id_of(s))
	return out


func _all_gone_or_washed(ids: Array[int]) -> bool:
	for id in ids:
		var s := NetRegistry.node(id) as EctoSlick
		if s != null and is_instance_valid(s) and not s.washed:
			return false
	return true


## A level direction away from c1 (so the host's chains stay out of a drizzle aimed at c1's segment, and the other way round).
func _away(base: Vector3, other: Vector3) -> Vector3:
	var d := base - other
	d.y = 0.0
	if d.length() < 0.5:
		d = Vector3(1, 0, 0)
	return d.normalized()


## `p` on the floor there (the floor's height where there is one).
func _floor(p: Vector3) -> Vector3:
	var map := game.get("map") as HexMap
	var g := map.ground_height(p)
	return Vector3(p.x, g if not is_nan(g) else p.y, p.z)


## Monsters, gates and the AI seats stand still (nothing crawls, nothing walks onto the slick).
func _freeze_world() -> void:
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
