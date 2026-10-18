extends NetGameTest
## M3 "done when" (networking-build-plan.md), two processes, `off` and `coast`: the host-owned world is live on a client.
##
## - MONSTERS: five dev grunts (--spawn-near, the same cells on every machine) and the floor's own monsters chase the
##   crew for several seconds of host-driven fighting (the host's hero walks a loop with the monsters after it and their
##   swings landing on it, the host kills two of them mid-run; the AI Gasket stands by, so every death is the test's). The client records what it SHOWED of each monster and at
##   which shared time; the host records where each one REALLY was: every one stays within 0.5 units at the time shown;
##   every death the host decided reaches the client's screen within 250 ms of it, and at the end the client's set of
##   living monsters is the host's;
## - SPAWNS: a hellgate's burst on the host shows up on the client with the SAME ids (from 10000 up) and kinds, where the
##   host put them;
## - GATE CLOSE: the host closes the gate; it closes on the client (dead, out of the gate list), the client's tracker shows
##   it closed (the host's bookkeeping, mirrored) and the "Hellgate closed" pay is on BOTH Ledgers exactly once;
## - BANDWIDTH: what the world costs per client (bytes/s), and the biggest packet stays under the 1.2 KB budget.

const PEERS := 2
const SEED := 21
const FIGHT := 8.0
const TOL := 0.5
const DEATH_LAG := 0.25
const WATCH_MAX := 10

## Host: id -> [t, x, y, z]* (the truth); client: id -> [render_t, x, y, z, now]* (what it showed).
var world_rec: Dictionary = {}
var watch_ids: Array = []
var recording_world := false
## Host: id -> host_time of the death; client: id -> host_time it showed the death.
var deaths: Dictionary = {}
## Host: every monster's death (id -> host_time).
var all_deaths: Dictionary = {}
var _frame := 0


func run_host() -> void:
	if not await enter_floor(SEED, 1, {"spawn_near": "grunt,5"}):
		return
	# The host's hero can't go down, and the AI Gasket stands by: the host decides every death in the fight below.
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	hero_at(3).set_modifier("test_ward", 0.0, 999.0)
	if not await wait_sync():
		return
	var brain := hero_at(3).get_node_or_null("AllyBrain")
	if brain != null:
		brain.set_physics_process(false)   # (after the van arrival, which hands the AI its brain back)
	check(await wait_reports("ready", 1, 30.0), "the client is streaming")
	var c1: int = client_peers()[0]
	var r: Dictionary = reported(c1, "ready")
	var mine := _world_ids()
	var theirs_ids: Array = r["ids"]
	var missing := mine.filter(func(i: int) -> bool: return not theirs_ids.has(i))
	var extra := theirs_ids.filter(func(i: int) -> bool: return not mine.has(i) and NetRegistry.node(i) != null and not (NetRegistry.node(i) as Actor).dead)
	check(missing.is_empty() and extra.is_empty() and mine.size() > 20, "the client shows the same host-owned actors (%d monsters, gates and employees; missing %s, extra %s)" % [mine.size(), str(missing), str(extra)])
	check(int(r["puppets"]) == theirs_ids.size() and int(r["acting"]) == 0, "... every one a puppet, none acting (%d puppets, %d acting)" % [int(r["puppets"]), int(r["acting"])])
	check(bool(r["mirror"]), "the client's Ledger mirrors the host's")

	# 1. The fight.
	watch_ids = _pick_watched()
	check(watch_ids.size() >= 4, "monsters to watch near the crew (%d)" % watch_ids.size())
	GameWorld.actor_died.connect(_on_host_death)
	GameWorld.actor_died.connect(func(a: Actor) -> void:
		if a is Monster:
			all_deaths[NetFloor.id_of(a)] = Session.host_time())
	for id: int in watch_ids:
		(NetRegistry.node(id) as Monster).aggro(my_hero())   # everyone after the host's hero
	command(c1, "watch", {"ids": watch_ids})
	await sleep(0.3)
	start_bot()
	_record_world(true)
	var t0 := wall()
	var killed := 0
	while wall() - t0 < FIGHT:
		await get_tree().process_frame
		if killed < 2 and wall() - t0 > 2.5 + 2.0 * killed:
			for id: int in watch_ids:
				var m := NetRegistry.node(id) as Monster
				if m != null and not m.dead:
					m.apply_damage(9999.0, my_hero())
					killed += 1
					break
	_record_world(false)
	bot.stop()
	var host_stats := Session.snap.stats.duplicate()
	var world_stats := Session.world.stats.duplicate()
	var span := maxf(Session.host_time() - float(host_stats["since"]), 0.001)
	check(await wait_reports("watch", 1, 30.0), "the client reports what it showed")
	var seen: Dictionary = reported(c1, "watch")
	_judge_fight(seen)
	await sleep(0.6)
	command(c1, "alive")
	check(await wait_reports("alive", 1, 20.0), "the client reports the monsters it shows alive")
	var al: Dictionary = reported(c1, "alive")
	# What the client shows is the world at its render time: the monsters alive now, and those that died since then.
	var expected := _alive_monsters()
	for id: int in all_deaths:
		if float(all_deaths[id]) > float(al["t"]) and not expected.has(id):
			expected.append(id)
	expected.sort()
	eq(str(al["ids"]), str(expected), "the client's living monsters are the host's at the moment it shows (%d)" % expected.size())

	# 2. A hellgate's burst.
	var site: SiteBuilder.Site = game.get("_site")
	var gate: Hellgate = null
	for g in site.gates:
		if is_instance_valid(g) and not g.dead and g != site.origin_gate:
			gate = g
	if gate == null and not site.gates.is_empty():
		gate = site.gates[0]
	if check(gate != null, "the floor has a hellgate"):
		gate.activate()
		var burst := gate.spawn_burst_now()
		await sleep(0.1)
		var spawned := {}
		for m in burst:
			spawned[NetFloor.id_of(m)] = [m.kind, m.global_position]
		check(not spawned.is_empty(), "the gate's burst spawned monsters (%d)" % spawned.size())
		for id: int in spawned:
			check(id >= NetRegistry.RUNTIME_BASE, "a runtime spawn has a host id from %d up (%d)" % [NetRegistry.RUNTIME_BASE, id])
		command(c1, "spawns", {"ids": spawned.keys()})
		check(await wait_reports("spawns", 1, 20.0), "the client reports the spawns")
		var theirs: Dictionary = reported(c1, "spawns")
		for id: int in spawned:
			if not check(theirs.has(id), "spawn %d exists on the client" % id):
				continue
			eq(str((theirs[id] as Array)[0]), str((spawned[id] as Array)[0]), "spawn %d is the same kind" % id)
			var d := Vector2((theirs[id] as Array)[1].x, (theirs[id] as Array)[1].z).distance_to(Vector2((spawned[id] as Array)[1].x, (spawned[id] as Array)[1].z))
			check(d < 1.0, "spawn %d stands where the host put it (%.2f)" % [id, d])

		# 3. The gate closes.
		var gid := NetFloor.id_of(gate)
		var pay_before := _ledger_count("Hellgate closed")
		gate.apply_damage(gate.hp + 100.0, my_hero())
		var t_close := Session.host_time()
		check(gate.dead, "the host closed the gate")
		await sleep(0.2)
		eq(_ledger_count("Hellgate closed") - pay_before, 1, "the host's Ledger pays the gate once")
		command(c1, "gate", {"id": gid})
		check(await wait_reports("gate", 1, 20.0), "the client reports the gate")
		var g: Dictionary = reported(c1, "gate")
		check(bool(g["closed"]), "the gate closed on the client")
		var lag := float(g["t"]) - t_close
		print("[M3] the gate closed on the client %.3f s after the host" % lag)
		check(lag <= DEATH_LAG + 1.0 / 60.0, "... within %.0f ms (%.0f ms)" % [DEATH_LAG * 1000.0, lag * 1000.0])
		check(not bool(g["listed"]), "... and is no longer an open gate there")
		eq(int(g["paid"]), _ledger_count("Hellgate closed"), "the client's Ledger has the gate's pay exactly as often as the host's")
		eq(int(g["tracker"]), int((game.get("_session") as ContractSession).state()["gates_closed"]), "the client's tracker shows the host's closed gates")
		eq(int(g["ledger_total"]), Ledger.earned(), "the client's Ledger earned what the host's did")

	# 4. The cost.
	var world_rate := float(host_stats["world_out_bytes"]) / span
	var hero_rate := float(host_stats["out_bytes"]) / span
	print("[M3] to one client over %.1f s of fighting: heroes %.0f B/s + world %.0f B/s = %.0f B/s; biggest packet %d B; world sections %d (avg %.0f B, %d entries, at most %d monsters)" % [
		span, hero_rate, world_rate, hero_rate + world_rate, int(host_stats["packet_max"]), int(world_stats["sections"]),
		float(world_stats["bytes"]) / maxf(float(world_stats["sections"]), 1.0), int(world_stats["entries"]), int(world_stats["monsters_max"])])
	check(int(host_stats["packet_max"]) <= NetWorldCodec.PACKET_BUDGET, "the biggest packet is under the %d-byte budget (%d)" % [NetWorldCodec.PACKET_BUDGET, int(host_stats["packet_max"])])
	check(world_rate > 100.0, "the world really streamed (%.0f B/s)" % world_rate)
	check(hero_rate + world_rate < 20000.0, "a client's whole stream stays reasonable (%.0f B/s)" % (hero_rate + world_rate))
	var cs: Dictionary = seen["stats"]
	print("[M3] the client: %d world sections in, %d entries applied, %d for unknown ids, world delay %.3f s" % [int(cs["in_sections"]), int(cs["in_entries"]), int(cs["unknown"]), float(seen["delay"])])
	command(c1, "end")
	check(await wait_done(1, 30.0), "the client is done")


func run_client() -> void:
	if not await enter_floor(SEED, 1, {"spawn_near": "grunt,5"}):
		return
	if not await wait_sync():
		return
	await until(func() -> bool: return Session.world.active, 10.0)
	var acting := 0
	var puppets := 0
	for id in _world_ids():
		var n := NetRegistry.node(id)
		puppets += 1 if Net.is_puppet(n) else 0
		acting += 1 if n.is_physics_processing() else 0
	report("ready", {"ids": _world_ids(), "puppets": puppets, "acting": acting, "mirror": Ledger.mirror})
	Session.world.died.connect(func(id: int) -> void: deaths[id] = Session.host_time())
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"watch":
				watch_ids = cmd["ids"]
				_record_world(true)
				await sleep(FIGHT + 0.6)
				_record_world(false)
				var d := {}
				for id: int in watch_ids:
					if deaths.has(id):
						d[id] = deaths[id]
				report("watch", {"rec": world_rec, "deaths": d, "stats": Session.world.stats.duplicate(), "delay": Session.world.delay()})
			"alive":
				report("alive", {"ids": _alive_monsters(), "t": Session.world.render_time()})
			"spawns":
				var ids: Array = cmd["ids"]
				await until(func() -> bool: return ids.all(func(i: int) -> bool: return NetRegistry.node(i) != null), 5.0)
				var out := {}
				for id: int in ids:
					var m := NetRegistry.node(id) as Monster
					if m != null:
						out[id] = [m.kind, m.global_position]
				report("spawns", out)
			"gate":
				var gid := int(cmd["id"])
				await until(func() -> bool: return NetRegistry.node(gid) == null or (NetRegistry.node(gid) as Actor).dead, 5.0)
				var t := float(deaths.get(gid, Session.host_time()))   # (the moment this screen showed it close)
				var g := NetRegistry.node(gid) as Hellgate
				await sleep(0.4)   # (the host's bookkeeping and pay follow the close)
				var sess: ContractSession = game.get("_session")
				report("gate", {"closed": g == null or g.dead, "t": t, "listed": Hellgate.open_gates().has(g) if g != null else false,
					"paid": _ledger_count("Hellgate closed"), "tracker": int(sess.state().get("gates_closed", -1)), "ledger_total": Ledger.earned()})
			_:
				running = false


# --- Recording ---------------------------------------------------------------------------------------------

## The host-owned actors this machine knows (ids from 100 up, living), ascending.
func _world_ids() -> Array[int]:
	var out: Array[int] = []
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if id >= NetFloor.ID_BASE and (n is Monster or n is Hellgate or n is Employee) and not (n as Actor).dead:
			out.append(id)
	return out


func _alive_monsters() -> Array[int]:
	var out: Array[int] = []
	for id in NetRegistry.ids():
		var m := NetRegistry.node(id) as Monster
		if m != null and not m.dead:
			out.append(id)
	return out


## The dev grunts and the monsters closest to the crew.
func _pick_watched() -> Array:
	var ids: Array = []
	var dev: Array = game.get("_dev_monsters")
	for m: Variant in dev:
		if is_instance_valid(m) and not (m as Monster).dead:
			ids.append(NetFloor.id_of(m as Monster))
	var others: Array = []
	for id in _alive_monsters():
		if not ids.has(id):
			others.append([NetRegistry.node(id).global_position.distance_to(my_hero().global_position), id])
	others.sort()
	for o: Array in others:
		if ids.size() >= WATCH_MAX:
			break
		ids.append(o[1])
	return ids


func _record_world(on: bool) -> void:
	if on:
		world_rec = {}
	recording_world = on


func _process(delta: float) -> void:
	super._process(delta)
	if not recording_world or game == null:
		return
	_frame += 1
	var now := Session.host_time()
	for id: int in watch_ids:
		var m := NetRegistry.node(id) as Monster
		if m == null or m.dead:
			continue
		var r: PackedFloat64Array = world_rec.get(id, PackedFloat64Array())
		var p := m.global_position
		if is_host():
			r.append_array(PackedFloat64Array([now, p.x, p.y, p.z]))
		else:
			if _frame % 2 != 0:
				continue
			var st := Session.world.shown_state(id)
			if st == null:
				continue
			r.append_array(PackedFloat64Array([st.t, p.x, p.y, p.z, now]))
		world_rec[id] = r


func _on_host_death(a: Actor) -> void:
	var id := NetFloor.id_of(a)
	if watch_ids.has(id) and not deaths.has(id):
		deaths[id] = Session.host_time()


func _judge_fight(seen: Dictionary) -> void:
	var rec: Dictionary = seen["rec"]
	var moved := 0
	var frames := 0
	var worst := 0.0
	for id: int in watch_ids:
		var truth: PackedFloat64Array = world_rec.get(id, PackedFloat64Array())
		var shown: PackedFloat64Array = rec.get(id, PackedFloat64Array())
		if truth.size() < 8 or shown.size() < 10:
			continue
		var e := series_error(truth, shown, 0.3)
		var span := _travel(truth)
		print("[M3] monster %d: %d frames shown, travelled %.1f, max err %.3f (mean %.3f), max step %.3f" % [id, int(e["n"]), span, float(e["max_err"]), float(e["mean_err"]), float(e["max_step"])])
		if int(e["n"]) == 0:
			continue
		frames += int(e["n"])
		worst = maxf(worst, float(e["max_err"]))
		if span > 2.0:
			moved += 1
		check(float(e["max_err"]) <= TOL, "monster %d's puppet stays within %.2f of where the host had it at the time shown (%.3f)" % [id, TOL, float(e["max_err"])])
	print("[M3] %d monsters compared (%d moved more than 2 units), %d frames, worst error %.3f" % [watch_ids.size(), moved, frames, worst])
	check(moved >= 3, "at least three monsters really moved (%d)" % moved)
	check(frames > 400, "the client showed plenty of frames (%d)" % frames)
	# Deaths: each one the host decided shows on the client within DEATH_LAG.
	var theirs: Dictionary = seen["deaths"]
	check(deaths.size() >= 2, "monsters died during the fight (%d)" % deaths.size())
	for id: int in deaths:
		if not check(theirs.has(id), "monster %d's death reached the client" % id):
			continue
		var lag := float(theirs[id]) - float(deaths[id])
		print("[M3] monster %d died on the host at %.3f, on the client %.3f s later" % [id, float(deaths[id]), lag])
		check(lag <= DEATH_LAG + 1.0 / 60.0, "... within %.0f ms (%.0f ms)" % [DEATH_LAG * 1000.0, lag * 1000.0])
	for id: int in theirs:
		check(deaths.has(id), "the client showed no death the host did not decide (%d)" % id)


## How far a ring's actor moved overall (the largest distance from its first position).
static func _travel(r: PackedFloat64Array) -> float:
	var n := r.size() >> 2
	if n == 0:
		return 0.0
	var a := Vector2(r[1], r[3])
	var best := 0.0
	for i in n:
		best = maxf(best, Vector2(r[i * 4 + 1], r[i * 4 + 3]).distance_to(a))
	return best


static func _ledger_count(label: String) -> int:
	var n := 0
	for l in Ledger.lines:
		if str(l["label"]) == label:
			n += 1
	return n
