extends MonsterTestBase
## M3, single process: the world snapshot codec (scripts/net/net_world_codec.gd) and what NetWorld puts in a packet.
## - the bytes: a monster entry is 16 bytes, an employee 15, a hellgate 7;
## - randomised round trips come back equal within one quantum; a short or malformed section gives what was complete;
## - EVERY var in MONSTER_FIELDS, EMPLOYEE_FIELDS and GATE_FIELDS survives an actor -> bytes -> actor round trip (the test
##   names them all, so a field added to a codec without a test here fails), and a puppet plays what changed: the hit
##   flash, the wind-up, the swing, an employee's mood and leader;
## - the packet budget (networking.md, about 1.2 KB): the world of the worst floor this test finds (the hardest contracts'
##   floor 3, every gate's spawns at their cap, every actor alive and MOVING) never makes a packet bigger than the budget,
##   no entry waits long, a still actor is refreshed at least every REFRESH ticks, and a stop is repeated REDUNDANCY times.

const TESTED_MONSTER := ["hp", "facing", "climbing", "state", "_telegraph", "strikes"]
const TESTED_EMPLOYEE := ["hp", "facing", "climbing", "state", "_dismissed", "_leader"]
const TESTED_GATE := ["hp", "_active", "_telegraphing", "phase", "_next_burst_in", "_shove_t"]


func setup() -> void:
	timeout_sec = 120.0
	Monster.use_proto_visuals = true
	_check_sizes()
	_check_round_trips()
	_check_malformed()
	await _check_monster_fields()
	await _check_employee_fields()
	await _check_gate_fields()
	await _check_budget()
	Monster.use_proto_visuals = false
	NetRegistry.clear()
	finish()


func _mover(rng: RandomNumberGenerator) -> NetHeroState:
	var s := NetHeroState.new()
	s.id = rng.randi_range(100, 65000)
	s.t = 50.0
	s.pos = Vector3(rng.randf_range(-250.0, 250.0), rng.randf_range(-3.0, 12.0), rng.randf_range(-250.0, 250.0))
	s.vel = Vector2(rng.randf_range(-15.0, 15.0), rng.randf_range(-15.0, 15.0))
	s.angle = rng.randf_range(0.0, TAU)
	s.hp = rng.randf_range(0.0, 900.0)
	s.mode = rng.randi_range(0, 4)
	s.climbing = rng.randf() < 0.3
	s.helpless = rng.randf() < 0.3
	s.telegraph = rng.randf()
	s.extra = rng.randi_range(0, 255)
	s.tp = rng.randi_range(0, 7)
	return s


func _check_sizes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	eq(NetWorldCodec.monster_bytes(_mover(rng)).size(), NetWorldCodec.MONSTER_SIZE, "a monster entry is 16 bytes")
	eq(NetWorldCodec.employee_bytes(_mover(rng)).size(), NetWorldCodec.EMPLOYEE_SIZE, "an employee entry is 15 bytes")
	eq(NetWorldCodec.MONSTER_SIZE, 16, "... a monster's 16")
	eq(NetWorldCodec.EMPLOYEE_SIZE, 15, "... an employee's 15")
	var g := NetWorldCodec.GateState.new()
	eq(NetWorldCodec.gate_bytes(g).size(), NetWorldCodec.GATE_SIZE, "a gate entry is 7 bytes")
	var none: Array[PackedByteArray] = []
	eq(NetWorldCodec.encode(none, none, none).size(), NetWorldCodec.SECTION_HEADER, "an empty world section is its three counts")


func _check_round_trips() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var worst := {"pos": 0.0, "vel": 0.0, "angle": 0.0, "hp": 0.0, "tele": 0.0, "burst": 0.0, "shove": 0.0}
	var mons: Array[PackedByteArray] = []
	var emps: Array[PackedByteArray] = []
	var gates: Array[PackedByteArray] = []
	var want_m: Array[NetHeroState] = []
	var want_e: Array[NetHeroState] = []
	var want_g: Array[NetWorldCodec.GateState] = []
	for i in 120:
		var m := _mover(rng)
		var e := _mover(rng)
		e.extra = rng.randi_range(0, 3)
		e.mode = rng.randi_range(0, 4)
		want_m.append(m)
		want_e.append(e)
		mons.append(NetWorldCodec.monster_bytes(m))
		emps.append(NetWorldCodec.employee_bytes(e))
		var g := NetWorldCodec.GateState.new()
		g.id = rng.randi_range(100, 9999)
		g.hp = rng.randf_range(0.0, 800.0)
		g.active = rng.randf() < 0.5
		g.telegraphing = rng.randf() < 0.5
		g.phase = rng.randi_range(0, 2)
		g.burst_in = rng.randf_range(0.0, 5.0) if rng.randf() < 0.6 else -1.0
		g.shove_t = rng.randf_range(0.0, 0.9) if rng.randf() < 0.5 else -1.0
		want_g.append(g)
		gates.append(NetWorldCodec.gate_bytes(g))
	var b := StreamPeerBuffer.new()
	b.data_array = NetWorldCodec.encode(mons, emps, gates)
	var sec := NetWorldCodec.decode(b, 50.0)
	eq(sec.monsters.size(), 120, "120 monsters come back")
	eq(sec.employees.size(), 120, "120 employees come back")
	eq(sec.gates.size(), 120, "120 gates come back")
	for i in mini(sec.monsters.size(), 120):
		for pair: Array in [[sec.monsters[i], want_m[i], "monster"], [sec.employees[i], want_e[i], "employee"]]:
			var d: NetHeroState = pair[0]
			var s: NetHeroState = pair[1]
			eq(d.id, s.id, "%s id" % pair[2])
			eq(d.mode, s.mode, "%s state" % pair[2])
			eq(d.climbing, s.climbing, "%s climbing" % pair[2])
			eq(d.helpless, s.helpless, "%s flag (helpless / dismissed)" % pair[2])
			eq(d.tp, s.tp, "%s teleport counter" % pair[2])
			eq(d.extra, s.extra, "%s extra byte (strikes / leader)" % pair[2])
			worst["pos"] = maxf(float(worst["pos"]), maxf(absf(d.pos.x - s.pos.x), maxf(absf(d.pos.y - s.pos.y), absf(d.pos.z - s.pos.z))))
			worst["vel"] = maxf(float(worst["vel"]), maxf(absf(d.vel.x - s.vel.x), absf(d.vel.y - s.vel.y)))
			worst["angle"] = maxf(float(worst["angle"]), absf(angle_difference(d.angle, s.angle)))
			worst["hp"] = maxf(float(worst["hp"]), absf(d.hp - s.hp))
		worst["tele"] = maxf(float(worst["tele"]), absf(sec.monsters[i].telegraph - want_m[i].telegraph))
		var dg := sec.gates[i]
		var sg := want_g[i]
		eq(dg.id, sg.id, "gate id")
		eq(dg.active, sg.active, "gate active")
		eq(dg.telegraphing, sg.telegraphing, "gate telegraphing")
		eq(dg.phase, sg.phase, "gate phase")
		eq(dg.burst_in < 0.0, sg.burst_in < 0.0, "gate flare present")
		eq(dg.shove_t < 0.0, sg.shove_t < 0.0, "gate shove present")
		worst["hp"] = maxf(float(worst["hp"]), absf(dg.hp - sg.hp))
		if sg.burst_in >= 0.0:
			worst["burst"] = maxf(float(worst["burst"]), absf(dg.burst_in - sg.burst_in))
		if sg.shove_t >= 0.0:
			worst["shove"] = maxf(float(worst["shove"]), absf(dg.shove_t - sg.shove_t))
	check(float(worst["pos"]) <= NetWorldCodec.quantum("position") + 0.0001, "position within a quantum (worst %.4f)" % float(worst["pos"]))
	check(float(worst["vel"]) <= NetWorldCodec.quantum("velocity") + 0.0001, "velocity within a quantum (worst %.4f)" % float(worst["vel"]))
	check(float(worst["angle"]) <= NetWorldCodec.quantum("angle") + 0.0001, "facing within a quantum (worst %.4f)" % float(worst["angle"]))
	check(float(worst["hp"]) <= NetWorldCodec.quantum("hp") + 0.0001, "hp within a quantum (worst %.4f)" % float(worst["hp"]))
	check(float(worst["tele"]) <= NetWorldCodec.quantum("telegraph") + 0.0001, "the wind-up within a quantum (worst %.4f)" % float(worst["tele"]))
	check(float(worst["burst"]) <= NetWorldCodec.quantum("burst_in") + 0.0001, "a gate's flare within a quantum (worst %.4f)" % float(worst["burst"]))
	check(float(worst["shove"]) <= NetWorldCodec.quantum("shove_t") + 0.0001, "a gate's shove wind-up within a quantum (worst %.4f)" % float(worst["shove"]))


func _check_malformed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var mons: Array[PackedByteArray] = [NetWorldCodec.monster_bytes(_mover(rng)), NetWorldCodec.monster_bytes(_mover(rng))]
	var none: Array[PackedByteArray] = []
	var full := NetWorldCodec.encode(mons, none, none)
	var b := StreamPeerBuffer.new()
	b.data_array = full.slice(0, full.size() - 10)
	var sec := NetWorldCodec.decode(b, 1.0)
	eq(sec.monsters.size(), 1, "a cut section gives the entries that were complete")
	b = StreamPeerBuffer.new()
	b.data_array = PackedByteArray()
	eq(NetWorldCodec.decode(b, 1.0).monsters.size(), 0, "an empty section is nothing")
	for i in 200:
		var junk := PackedByteArray()
		for _j in rng.randi_range(0, 80):
			junk.append(rng.randi_range(0, 255))
		b = StreamPeerBuffer.new()
		b.data_array = junk
		NetWorldCodec.decode(b, 1.0)   # must never crash
	check(true, "200 random sections decoded without a crash")


## A small world with a hero to aim at.
func _arena() -> Actor:
	new_world(flat_map(8))
	return add_hero(Vector2i(-4, 0))


func _round_trip_monster(src: Monster, dst: Monster) -> NetHeroState:
	var st := NetHeroState.new()
	st.id = 500
	st.pos = src.global_position
	NetWorldCodec.read_monster(src, st)
	var b := StreamPeerBuffer.new()
	b.data_array = NetWorldCodec.monster_bytes(st)
	var d := NetWorldCodec.get_monster(b, 1.0)
	NetWorldCodec.write_monster(dst, d)
	dst.net_tick(1.0 / 60.0)
	return d


func _check_monster_fields() -> void:
	eq(_sorted(TESTED_MONSTER), _sorted(NetWorldCodec.MONSTER_FIELDS.keys()), "this test covers every var in MONSTER_FIELDS")
	_arena()
	var src := MonsterFactory.spawn("brute", Vector2i(1, 0))
	var dst := MonsterFactory.spawn("brute", Vector2i(3, 0))
	await frames(2)
	Net.make_puppet(dst)
	src.set_physics_process(false)
	src.hp = 77.3
	src.facing = Vector3(0.6, 0.0, -0.8)
	src.climbing = true
	src.state = Monster.State.ATTACK
	src._telegraph = 0.42
	src.strikes = 5
	_round_trip_monster(src, dst)
	near(dst.hp, 77.3, NetWorldCodec.quantum("hp") + 0.001, "monster hp")
	check(dst.facing.distance_to(src.facing) < 0.03, "monster facing")
	eq(dst.climbing, true, "monster climbing")
	eq(dst.state, Monster.State.ATTACK, "monster state")
	near(dst._telegraph, 0.42, 0.005, "monster wind-up")
	eq(dst.strikes, 5, "monster strike count")
	check(dst._flash_t > 0.0, "the hp drop flashes the puppet")
	check(dst._ring != null, "entering the wind-up shows the brute's ring on the puppet")
	src.strikes = 6
	src.state = Monster.State.CHASE
	src._telegraph = 0.0
	_round_trip_monster(src, dst)
	eq(dst.strikes, 6, "the strike count moved on")
	check(dst._strike_t > 0.5, "... and the puppet swung")
	check(dst._ring == null or not is_instance_valid(dst._ring) or dst._ring.is_queued_for_deletion(), "the wind-up ended: the ring is gone")
	check(not dst.is_physics_processing() and Net.is_puppet(dst), "the puppet runs no AI")
	eq(dst.apply_damage(50.0, null), 0.0, "a puppet monster takes no damage on this machine")


func _check_employee_fields() -> void:
	eq(_sorted(TESTED_EMPLOYEE), _sorted(NetWorldCodec.EMPLOYEE_FIELDS.keys()), "this test covers every var in EMPLOYEE_FIELDS")
	var hero := _arena()
	NetRegistry.clear()
	var h := HeroFactory.spawn_hero(Vector2i(-2, 2), "Wick", Color.WHITE, "sword", null, "wick")
	NetRegistry.register(2, h)
	var src := Employee.spawn(Vector2i(0, 2), {"style": "staff", "name": "Beatrice"})
	var dst := Employee.spawn(Vector2i(2, -2), {"style": "staff", "name": "Beatrice"})
	await frames(2)
	Net.make_puppet(dst)
	src.set_physics_process(false)
	src.hp = 21.5
	src.facing = Vector3(-1.0, 0.0, 0.0)
	src.climbing = true
	src._leader = h
	src._dismissed = false
	src.state = Employee.State.FOLLOW
	var st := NetHeroState.new()
	st.id = 600
	st.pos = src.global_position
	NetWorldCodec.read_employee(src, st)
	var b := StreamPeerBuffer.new()
	b.data_array = NetWorldCodec.employee_bytes(st)
	NetWorldCodec.write_employee(dst, NetWorldCodec.get_employee(b, 1.0))
	dst.net_tick(1.0 / 60.0)
	near(dst.hp, 21.5, NetWorldCodec.quantum("hp") + 0.001, "employee hp")
	check(dst.facing.distance_to(Vector3(-1, 0, 0)) < 0.03, "employee facing")
	eq(dst.climbing, true, "employee climbing")
	eq(dst.state, Employee.State.FOLLOW, "employee state")
	check(dst.leader() == h and dst.is_following(), "employee leader (the hero in seat 2)")
	eq(dst.model.mood(), "follow", "the puppet's mood follows its state")
	src._dismissed = true
	src._leader = null
	src.state = Employee.State.WAIT
	NetWorldCodec.read_employee(src, st)
	b = StreamPeerBuffer.new()
	b.data_array = NetWorldCodec.employee_bytes(st)
	NetWorldCodec.write_employee(dst, NetWorldCodec.get_employee(b, 1.0))
	check(dst.is_dismissed() and dst.is_waiting() and dst.leader() == null, "employee dismissed (told to wait)")
	eq(dst.state, Employee.State.WAIT, "... in WAIT")
	# The puppet works out its own mood against this screen's heroes.
	hero.global_position = dst.global_position + Vector3(1.5, 0.0, 0.0)
	for i in 20:
		dst.net_tick(1.0 / 60.0)
		await get_tree().process_frame
	check(dst._hero_near, "a puppet employee notices a hero near it on this screen (_hero_near is LOCAL)")
	eq(dst.apply_damage(5.0, null), 0.0, "a puppet employee takes no damage on this machine")


func _check_gate_fields() -> void:
	eq(_sorted(TESTED_GATE), _sorted(NetWorldCodec.GATE_FIELDS.keys()), "this test covers every var in GATE_FIELDS")
	_arena()
	var src := Hellgate.spawn(Vector2i(4, 0), {"difficulty": 0.5, "depth": 3, "origin": true})
	var dst := Hellgate.spawn(Vector2i(-4, 4), {"difficulty": 0.5, "depth": 3, "origin": true})
	await frames(2)
	Net.make_puppet(dst)
	src.set_physics_process(false)
	src.hp = src.max_hp * 0.5
	src._active = true
	src._telegraphing = true
	src.phase = 1
	src._next_burst_in = 0.64
	src._shove_t = 0.31
	var g := NetWorldCodec.GateState.new()
	g.id = 700
	NetWorldCodec.read_gate(src, g)
	var b := StreamPeerBuffer.new()
	b.data_array = NetWorldCodec.gate_bytes(g)
	NetWorldCodec.write_gate(dst, NetWorldCodec.get_gate(b, 1.0))
	near(dst.hp, src.hp, NetWorldCodec.quantum("hp") + 0.001, "gate hp")
	eq(dst._active, true, "gate active")
	eq(dst._telegraphing, true, "gate telegraphing")
	eq(dst.phase, 1, "gate phase")
	near(dst._next_burst_in, 0.64, 0.011, "gate burst timer (the flare)")
	near(dst._shove_t, 0.31, 0.006, "gate shove wind-up")
	check(dst._bar != null and dst._bar.visible, "the puppet gate's bar shows the damage")
	src._telegraphing = false
	src._shove_t = -1.0
	NetWorldCodec.read_gate(src, g)
	b = StreamPeerBuffer.new()
	b.data_array = NetWorldCodec.gate_bytes(g)
	NetWorldCodec.write_gate(dst, NetWorldCodec.get_gate(b, 1.0))
	check(not dst._telegraphing and dst._shove_t < 0.0, "the flare and the shove end on the puppet too")


## A sorted copy, as text (the comparison is about membership, not order).
static func _sorted(names: Array) -> String:
	var a := names.duplicate()
	a.sort()
	return str(a)


# --- The packet budget -----------------------------------------------------------------------------------

func _check_budget() -> void:
	# The worst floor 3 among the hardest contracts: most monsters, gates and employees.
	var best_run: ContractRun = null
	var best_n := -1
	for arch in ClientArchetype.IDS:
		for s in [3, 17, 41]:
			var run := ContractRun.make(arch, s, 1.0)
			var plan_map := DungeonGen.generate(run.floor_seed(3))
			new_world(plan_map)
			var site := SiteBuilder.build(plan_map, run, 3)
			var n := site.monsters.size() + site.employees.size()
			for g in site.gates:
				n += int(Hellgate.profile(1.0, 3, g == site.origin_gate, 2)["cap"])
			if n > best_n:
				best_n = n
				best_run = run
	var map := DungeonGen.generate(best_run.floor_seed(3))
	new_world(map)
	var site := SiteBuilder.build(map, best_run, 3)
	var w := NetWorld.new()
	add_child(w)
	var ids := 100
	var movers: Array[Actor] = []
	for m in site.monsters:
		w.track_for_test(ids, m)
		movers.append(m)
		ids += 1
	for e in site.employees:
		w.track_for_test(ids, e)
		movers.append(e)
		ids += 1
	for g in site.gates:
		w.track_for_test(ids, g)
		ids += 1
		var cap := int(Hellgate.profile(1.0, 3, g == site.origin_gate, 2)["cap"])
		for i in cap:
			var m := MonsterFactory.spawn("swarmer", Hex.from_world(g.global_position) + Vector2i(i % 4 - 2, i / 4 - 2))
			if m == null:
				continue
			w.track_for_test(ids, m)
			movers.append(m)
			ids += 1
	for a in movers:
		a.set_physics_process(false)
	var tracked := w.tracked_ids().size()
	print("[M3] worst floor: %s floor 3, %d monsters, %d employees, %d gates (spawns at their caps): %d entries" % [
		best_run.archetype_id, site.monsters.size(), site.employees.size(), site.gates.size(), tracked])
	check(tracked > 60, "the worst floor has plenty of actors (%d)" % tracked)
	w.active = true
	var hero_bytes := NetWire.HEADER + 1 + 2 * NetCodec.ENTRY_SIZE_DRAWING
	var biggest := 0
	var last_seen: Dictionary = {}
	var worst_wait := 0
	# 1. Everything moves, every tick, for 2 s: the packet stays inside the budget and every entry still rides often.
	for tick in 60:
		for a in movers:
			a.global_position += Vector3(0.05, 0.0, 0.03)
		w._physics_process(1.0 / 60.0)
		var sec := w.section(float(tick) / 30.0)
		biggest = maxi(biggest, sec.size() + hero_bytes)
		for id in _ids_in(sec):
			if last_seen.has(id) and tick > 10:
				worst_wait = maxi(worst_wait, tick - int(last_seen[id]))
			last_seen[id] = tick
	print("[M3] all %d moving: biggest packet %d bytes, the longest any entry waited %d ticks" % [tracked, biggest, worst_wait])
	check(biggest <= NetWorldCodec.PACKET_BUDGET, "a worst-case floor-3 packet (heroes and world) stays under %d bytes (%d)" % [NetWorldCodec.PACKET_BUDGET, biggest])
	eq(last_seen.size(), tracked, "every entry rode")
	check(worst_wait <= ceili(float(tracked * NetWorldCodec.MONSTER_SIZE) / float(NetWorld.WORLD_BUDGET)) + 1, "no moving entry waits more than its turn (%d ticks)" % worst_wait)
	# 2. Everything stands still: after the redundant repeats, each entry rides at least every REFRESH ticks and the
	# packets are small.
	last_seen.clear()
	var max_gap := 0
	var still_bytes := 0
	for tick in range(60, 150):
		w._physics_process(1.0 / 60.0)
		var sec := w.section(float(tick) / 30.0)
		if tick >= 60 + NetWorld.REDUNDANCY + 1:
			still_bytes = maxi(still_bytes, sec.size())
		for id in _ids_in(sec):
			if last_seen.has(id):
				max_gap = maxi(max_gap, tick - int(last_seen[id]))
			last_seen[id] = tick
	print("[M3] all still: biggest section %d bytes, an entry rides every %d ticks at most" % [still_bytes, max_gap])
	eq(last_seen.size(), tracked, "every still entry is refreshed")
	check(max_gap <= NetWorld.REFRESH, "a still entry is refreshed at least every %d ticks (%d)" % [NetWorld.REFRESH, max_gap])
	check(still_bytes < 260, "a still floor costs a small section (%d bytes)" % still_bytes)
	# 3. One actor stops: its last state is sent REDUNDANCY times in a row.
	var one := movers[0]
	var one_id := 100
	var rides := 0
	one.global_position += Vector3(0.4, 0.0, 0.0)
	for tick in range(150, 150 + NetWorld.REDUNDANCY + 2):
		w._physics_process(1.0 / 60.0)
		if _ids_in(w.section(float(tick) / 30.0)).has(one_id):
			rides += 1
	check(rides >= NetWorld.REDUNDANCY, "a stop rides %d times in a row (%d)" % [NetWorld.REDUNDANCY, rides])
	w.queue_free()


## The ids in a world section (every kind).
func _ids_in(sec: PackedByteArray) -> Array[int]:
	var b := StreamPeerBuffer.new()
	b.data_array = sec
	var d := NetWorldCodec.decode(b, 0.0)
	var out: Array[int] = []
	for s in d.monsters:
		out.append(s.id)
	for s in d.employees:
		out.append(s.id)
	for g in d.gates:
		out.append(g.id)
	return out
