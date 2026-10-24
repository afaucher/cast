extends NetGameTest
## The Pavise Crossbowman and the Water Boy online (docs/design/combat-proposals.md §2 / §3, "As built"), three processes,
## `off` and `coast`. Floor 1 of the seed-16 job. The host and c1 play it; c2 joins later, on the job.
## - THE SHIELD, THE ATTACKER'S MACHINE DECIDES: the host spawns a pavise (a runtime spawn: c1 builds it as a puppet) and
##   plants it facing a spot in front of it; c1 stands there and shoots it. c1's machine resolves its arrow: it is blocked
##   once there (no hit request travels, the arrow sticks), and the host, replaying c1's shot, shows the block too and its
##   pavise keeps every HP. From the flank c1's arrow lands: the host takes exactly one arrow's damage, and c1 shows it;
## - THE PULSE, THE HOST DECIDES: a water boy pours on a hurt grunt beside it (its tell is the monsters' wind-up event):
##   the host heals the grunt once (+15); c1 shows the rings from the event and the grunt's HP from the stream;
## - SIZE JITTER (playtest feedback 2026-10-24 item 4): c1 shows every monster (the floor's and the runtime spawns) at the size
##   the host shows it, from its net id (Monster.size_for), never a roll;
## - THE LATE JOINER: c2 joins the floor afterwards and sees both kinds alive, the pavise with its planted shield and its
##   HP as the host has them, and every monster at the host's size;
## - nothing tripped the OWNER-write guard on any machine.

const PEERS := 3
const SEED := 16
const CONTRACT := 2
const JOINER_SPELLS := ["tentacles", "teeth"]


func run_host() -> void:
	net_timeout = 100.0
	clear_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	make_game({"spells": "heal,corn", "seed": SEED, "contract": CONTRACT, "net_wait": 2, "floor": 1})
	if not check(await wait_floor(45.0), "floor 1 starts") or not await wait_sync():
		return
	(game.get("opts") as Dictionary).erase("net_wait")
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	_freeze_world()
	var c1 := peer_named("c1")
	check(await wait_reports("ready", 1, 30.0), "c1 is on the floor")
	var ai := hero_at(3)
	var brain := ai.get_node_or_null("AllyBrain")
	if brain != null:
		brain.set_physics_process(false)

	# The pavise: on open floor, facing a clear lane in front, with a clear lane on its flank too.
	var base := my_hero().global_position
	var plan := _pavise_spot(base)
	if not check(not plan.is_empty(), "open floor for the pavise with a front and a flank lane"):
		return
	var pv := MonsterFactory.spawn("pavise", Hex.from_world(plan["at"])) as Pavise
	if not check(pv != null, "the host spawned a pavise"):
		return
	pv.global_position = plan["at"]
	pv.set_physics_process(false)   # (a statue: its facing and shield stay as set)
	var front: Vector3 = plan["front"]
	pv.set_spawn_facing(front - pv.global_position)
	pv._set_shield(Pavise.Shield.PLANTED)
	var pid := NetFloor.id_of(pv)
	_put(my_hero(), pv.global_position - (front - pv.global_position).normalized() * 5.0)
	_put(ai, _far_from(pv.global_position, 12.0))
	await sleep(1.0)
	command(c1, "look", {"id": pid})
	check(await wait_reports("look", 1, 10.0), "c1 looked")
	var lk: Dictionary = reported(c1, "look")
	check(bool(lk["puppet"]), "c1 shows the pavise as a puppet of the host's")
	eq(int(lk["shield"]), Pavise.Shield.PLANTED, "c1 shows its shield planted (world.shield)")

	# 1. The front: c1's arrow is blocked on c1 (it decides) and shown blocked on the host.
	var hp0 := pv.hp
	var hits0 := int(Session.objects.stats["hits_in"])
	var shown0 := pv.blocks_shown
	command(c1, "arrow", {"id": pid, "at": front, "key": "front"})
	if check(await wait_reports("front", 1, 15.0), "c1 shot the pavise's front"):
		var r: Dictionary = reported(c1, "front")
		eq(int(r["decided"]), 1, "c1's machine blocked its arrow once (it resolves its own hits)")
		eq(int(r["stuck"]), 1, "... the arrow sticks in the planks on c1's screen")
		near(float(r["hp"]), hp0, 0.15, "... and c1 shows the pavise unhurt")
	await sleep(1.0)
	near(pv.hp, hp0, 0.001, "the host's pavise kept every HP")
	eq(int(Session.objects.stats["hits_in"]) - hits0, 0, "no hit request reached the host")
	eq(pv.blocks_shown - shown0, 1, "the host shows the block once too (c1's shot, replayed)")
	eq(pv.blocks_decided, 0, "... without deciding it (c1's machine did)")

	# 2. The flank: c1's arrow lands once.
	var hp1 := pv.hp
	command(c1, "arrow", {"id": pid, "at": plan["flank"], "key": "flank"})
	check(await until(func() -> bool: return pv.hp < hp1 - 0.01, 6.0), "c1's arrow from the flank reached the host's pavise")
	if check(await wait_reports("flank", 1, 15.0), "c1 shot the pavise's flank"):
		var r2: Dictionary = reported(c1, "flank")
		eq(int(r2["decided"]), 1, "... nothing blocked it on c1 (still one block in all)")
	near(hp1 - pv.hp, hero_at(2).arrow_tap_damage, 0.01, "the pavise lost exactly one arrow (%.0f)" % hero_at(2).arrow_tap_damage)
	command(c1, "hp", {"id": pid})
	if check(await wait_reports("hp", 1, 10.0), "c1 reports the pavise's HP"):
		near(float(reported(c1, "hp")), pv.hp, 0.15, "c1 shows the host's HP")

	# 3. The water boy pours on a hurt grunt: healed once on the host, the rings and the HP on c1.
	var wb_at := _far_from(pv.global_position, 11.0, base)
	var wb := MonsterFactory.spawn("water_boy", Hex.from_world(wb_at)) as WaterBoy
	var g := _spawn_beside(wb.global_position, "grunt")
	if not check(wb != null and g != null, "the host spawned a water boy and a grunt beside it"):
		return
	wb.set_physics_process(false)
	g.set_physics_process(false)
	await sleep(1.0)
	g.apply_damage(25.0, my_hero())
	var g_hp := g.hp
	command(c1, "pulse", {"wb": NetFloor.id_of(wb), "g": NetFloor.id_of(g)})
	await sleep(0.3)
	wb.target = my_hero()
	wb.set_physics_process(true)
	wb._begin_windup(WaterBoy.POUR_TELL)   # (the tell: world.windup to c1)
	check(await until(func() -> bool: return wb.pulses >= 1, 4.0), "the water boy poured on the host")
	wb.set_physics_process(false)
	near(g.hp - g_hp, WaterBoy.PULSE_HEAL, 0.001, "the host healed the grunt once (+15)")
	if check(await wait_reports("pulse", 1, 15.0), "c1 reports the pulse"):
		var pr: Dictionary = reported(c1, "pulse")
		eq(int(pr["pulses"]), 1, "c1 showed the rings once (from the wind-up event)")
		near(float(pr["g_hp"]), g.hp, 0.15, "c1 shows the grunt's healed HP")

	# 3b. Size jitter (playtest feedback 2026-10-24 item 4): c1 shows every monster at the size the host does, the seed-built
	# ones and the runtime spawns alike (it comes from the net id, never from a roll).
	var sids: Array = []
	var hsizes: Array = []
	for id in NetRegistry.ids():
		var mm := NetRegistry.node(id) as Monster
		if mm != null and not mm.dead:
			sids.append(id)
			hsizes.append(mm._size_now())
	check(sids.size() >= 3 and sids.has(pid) and sids.has(NetFloor.id_of(g)), "monsters to compare (%d)" % sids.size())
	check(hsizes.any(func(k: float) -> bool: return absf(k - 1.0) > 0.005), "the host shows them at their own sizes")
	command(c1, "sizes", {"ids": sids})
	if check(await wait_reports("sizes", 1, 10.0), "c1 reports the sizes"):
		_same_sizes(reported(c1, "sizes") as Dictionary, sids, hsizes, "c1")

	# 4. The late joiner.
	raise_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 30.0), "c2 joins the crew on the job"):
		return
	var c2 := peer_named("c2")
	if not check(await wait_reports("checkout", 1, 30.0), "c2 opened its license checkout"):
		return
	command(c2, "sign", {"spells": JOINER_SPELLS, "pavise": pid, "wb": NetFloor.id_of(wb), "sizes": sids})
	if check(await wait_reports("arrived", 1, 40.0), "c2 arrived"):
		var ar: Dictionary = reported(c2, "arrived")
		_same_sizes(ar["sizes"] as Dictionary, sids, hsizes, "the late joiner c2")
		check(bool(ar["pavise"]), "c2: the pavise is there")
		eq(str(ar["pavise_kind"]), "pavise", "... as a pavise")
		eq(int(ar["shield"]), Pavise.Shield.PLANTED, "... with its shield planted (the snapshot's shields)")
		near(float(ar["pavise_hp"]), pv.hp, 0.15, "... and the host's HP")
		check(bool(ar["water_boy"]), "c2: the water boy is there")
		eq(str(ar["wb_kind"]), "water_boy", "... as a water boy")
	command(c2, "end")
	command(c1, "end")
	check(await wait_reports("end", 2, 10.0), "the clients are done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	for p in [c1, c2]:
		eq(int((reported(p, "end") as Dictionary)["guard"]), 0, "... nor on %s" % ("c1" if p == c1 else "c2"))


func run_client() -> void:
	if index == 2:
		await _late_joiner()
		return
	if not check(await connect_client() == "", "joined"):
		return
	make_game({"spells": "heal,corn", "floor": 1})
	if not check(await wait_floor(45.0), "the floor starts here") or not await wait_sync():
		return
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"look":
				var pv := await _wait_node(int(cmd["id"]))
				await sleep(0.3)
				report("look", {"puppet": pv != null and Net.is_puppet(pv), "shield": int(pv.get("shield_state")) if pv != null else -1})
			"arrow":
				var pv := await _wait_node(int(cmd["id"])) as Pavise
				_put(my_hero(), cmd["at"])
				await sleep(0.5)
				var to := pv.global_position - my_hero().global_position
				my_hero()._ready_at.clear()
				check(my_hero().fire_arrow(to, false), "c1 shot")
				await sleep(1.0)
				report(str(cmd["key"]), {"decided": pv.blocks_decided, "stuck": pv.stuck, "hp": pv.hp})
			"sizes":
				await sleep(0.3)
				report("sizes", _sizes(cmd["ids"] as Array))
			"hp":
				await sleep(0.4)
				var n := NetRegistry.node(int(cmd["id"])) as Actor
				report("hp", n.hp if n != null else -1.0)
			"pulse":
				var wb := await _wait_node(int(cmd["wb"])) as WaterBoy
				var g := await _wait_node(int(cmd["g"]))
				var before := wb.pulses if wb != null else 0
				await until(func() -> bool: return wb != null and wb.pulses > before, 8.0)
				await sleep(0.8)
				report("pulse", {"pulses": (wb.pulses - before) if wb != null else 0, "g_hp": g.hp if g != null else -1.0})
			"end":
				report("end", {"guard": Net.guard_hits.size()})
				running = false
			_:
				running = false


## c2: join the crew on the job and report the new monsters it finds.
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
	var pv := NetRegistry.node(int(sign_cmd["pavise"])) as Monster
	var wb := NetRegistry.node(int(sign_cmd["wb"])) as Monster
	report("arrived", {
		"pavise": pv != null and not pv.dead, "pavise_kind": pv.kind if pv != null else "", "pavise_hp": pv.hp if pv != null else -1.0,
		"shield": int(pv.get("shield_state")) if pv != null else -1,
		"water_boy": wb != null and not wb.dead, "wb_kind": wb.kind if wb != null else "",
		"sizes": _sizes(sign_cmd["sizes"] as Array),
	})
	await wait_command(30.0)
	report("end", {"guard": Net.guard_hits.size()})


# --- Helpers ---------------------------------------------------------------------------------------------------------

## A client: the size each monster in `ids` is shown at here: {"k": its size_k, "shown": its Visual's scale without the
## wind-up swell} per id, in order (-1 when it is not here).
func _sizes(ids: Array) -> Dictionary:
	var k: Array = []
	var shown: Array = []
	for id: Variant in ids:
		var m := NetRegistry.node(int(id)) as Monster
		k.append(m.size_k if m != null else -1.0)
		shown.append(m._visual.scale.x / (1.0 + m.windup_scale * m._telegraph) if m != null else -1.0)
	return {"k": k, "shown": shown}


## Host: a client's sizes (_sizes) against the host's own, monster by monster.
func _same_sizes(r: Dictionary, ids: Array, host: Array, who: String) -> void:
	var k: Array = r.get("k", [])
	var shown: Array = r.get("shown", [])
	if not eq(k.size(), ids.size(), "%s reports a size for every monster" % who):
		return
	var off := 0
	for i in ids.size():
		if absf(float(k[i]) - float(host[i])) > 0.0001 or absf(float(shown[i]) - float(host[i])) > 0.001:
			off += 1
			if off <= 3:
				check(false, "%s shows monster %d at %.4f (drawn %.4f), the host at %.4f" % [who, int(ids[i]), float(k[i]), float(shown[i]), float(host[i])])
	eq(off, 0, "%s shows all %d monsters at the host's sizes (from their net ids)" % [who, ids.size()])
	print("  sizes: %s shows %d monsters at the host's sizes (%d of them off 1.0)" % [who, ids.size() - off,
		host.filter(func(v: float) -> bool: return absf(v - 1.0) > 0.005).size()])

func _freeze_world() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if (n is Monster or n is Hellgate) and not (n as Actor).dead:
			n.set_physics_process(false)


func _put(h: Hero, at: Vector3) -> void:
	h.global_position = at
	h.snap_to_ground()


func _wait_node(id: int) -> Actor:
	await until(func() -> bool: return NetRegistry.node(id) != null, 5.0)
	return NetRegistry.node(id) as Actor


## Host: a spot for the pavise within reach of `base`, with two clear lanes 90 degrees apart: {at, front, flank}.
func _pavise_spot(base: Vector3) -> Dictionary:
	var map := game.get("map") as HexMap
	for r: float in [5.0, 7.0, 9.0, 11.0, 3.5]:
		for k in 12:
			var a := TAU * float(k) / 12.0
			var at := base + Vector3(cos(a), 0.0, sin(a)) * r
			if not _open(map, at, 1.2):
				continue
			at.y = map.ground_height(at)
			for j in 12:
				var f := Vector3(cos(TAU * float(j) / 12.0), 0.0, sin(TAU * float(j) / 12.0))
				var s := f.rotated(Vector3.UP, PI * 0.5)
				var front := at + f * 4.5
				var flank := at + s * 4.5
				if _lane(map, at, front) and _lane(map, at, flank):
					front.y = map.ground_height(front)
					flank.y = map.ground_height(flank)
					return {"at": at, "front": front, "flank": flank}
	return {}


func _open(map: HexMap, p: Vector3, clear: float) -> bool:
	if not map.is_walkable_cell(Hex.from_world(p)) or map.blocks_point(p, 0.7) or map.is_pool_cell(Hex.from_world(p)):
		return false
	for x in GameWorld.actors_in_radius(p, clear):
		if not (x is Hero):
			return false
	return GameWorld.props_in_radius(p, clear).is_empty()


## A level, open lane from `a` to `b` with nothing but heroes near it (an arrow down it meets only what it is aimed at).
func _lane(map: HexMap, a: Vector3, b: Vector3) -> bool:
	if not _open(map, b, 1.2) or absf(map.ground_height(b) - a.y) > 0.3:
		return false
	if not map.line_of_sight(a + Vector3.UP * 0.9, Vector3(b.x, a.y + 0.9, b.z), 0.08):
		return false
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var others: Array = GameWorld.actors()
	others.append_array(GameWorld.props_in_radius((a + b) * 0.5, 6.0))
	others.append_array(GameWorld.breakables_in_radius((a + b) * 0.5, 6.0))
	for n: Variant in others:
		if n == null or not is_instance_valid(n) or n is Hero or n.dead:
			continue
		var p2 := Vector2(n.global_position.x, n.global_position.z)
		if Geometry2D.get_closest_point_to_segment(p2, a2, b2).distance_to(p2) <= float(n.radius) + 0.6:
			return false
	return true


## Open floor at least `dist` from `p` (and near `near_to` when given), first found in a stable order.
func _far_from(p: Vector3, dist: float, near_to: Vector3 = Vector3.INF) -> Vector3:
	var map := game.get("map") as HexMap
	var cells: Array = map.cells.keys()
	cells.sort()
	var best := Vector3.INF
	var best_d := INF
	for c: Vector2i in cells:
		if not map.is_walkable_cell(c) or map.is_pool_cell(c):
			continue
		var w := Hex.to_world(c, float(map.get_cell(c).level))
		if GameWorld.flat_distance(w, p) < dist or not _open(map, w, 1.5):
			continue
		if near_to == Vector3.INF:
			return w
		var d := GameWorld.flat_distance(w, near_to)
		if d < best_d:
			best_d = d
			best = w
	return best if best != Vector3.INF else p


func _spawn_beside(p: Vector3, kind: String) -> Monster:
	var map := game.get("map") as HexMap
	for k in 8:
		var q := p + Vector3(cos(TAU * k / 8.0), 0.0, sin(TAU * k / 8.0)) * 1.4
		if _open(map, q, 0.6):
			var m := MonsterFactory.spawn(kind, Hex.from_world(q))
			if m != null:
				m.global_position = Vector3(q.x, map.ground_height(q), q.z)
			return m
	return null
