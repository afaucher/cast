extends NetGameTest
## Explosive props online (docs/design/hazards.md, "Explosive props (as built)"), two processes, `off` and `coast`.
##
## The floor has an oil drum and gas cylinders side by side (the --hazard-near dev flag builds the same two on every machine
## before the barrier). The client's hero (c1, seat 2) stands by the drum, on the far side from the cylinders, and casts a
## fireball at the drum.
## - THE HOST DECIDES: the drum lights on the host (its own run of the client's fireball, or the client's hit request,
##   whichever is first), blamed on the client's hero; the client is told (obj.fuse) and shows the same fuse: the same end
##   on the shared clock, within a few milliseconds;
## - THE BLAST IS A SCHEDULED EFFECT: it goes off on both machines at that moment (within a frame and the clock's error),
##   and the chain lights the cylinders on the host, which both machines then see blow a chain delay later;
## - THE VICTIM DECIDES: the client's hero, standing in the drum's blast and out of the cylinders', loses exactly one blast's
##   damage (its falloff at its own distance) in exactly one hit, on its own machine; the host applied nothing to it and
##   shows its HP as the client has it;
## - THE BILL: the host's Ledger has one line for the drum and one for the cylinders, both billed to the client's hero, and
##   the client's mirrored Ledger (its invoice) is the host's, line for line;
## - nothing tripped the OWNER-write guard on either machine.

const PEERS := 2
const SEED := 13
const FRAME := 1.0 / 60.0
const HAZARDS := "oil_drum,gas_cylinders"

## This machine's view of each explosive: id -> {fuse_end (host_time), blew (host_time), truth (wall), hits (its hero in the
## blast), lost}.
var blasts_seen := {}


func run_host() -> void:
	net_timeout = 75.0
	if not await enter_floor(SEED, 1, {"give": "fireball:9", "hazard_near": HAZARDS}):
		return
	if not await wait_sync():
		return
	_freeze_world()
	_probe()
	check(await wait_reports("ready", 1, 30.0), "the client is streaming")
	var a := client_peers()[0]
	var hz: Array = game.get("_dev_hazards")
	if not check(hz.size() == 2 and hz[0] is ExplosiveProp and hz[1] is ExplosiveProp, "the dev flag built the drum and the cylinders (%d)" % hz.size()):
		return
	var drum := hz[0] as ExplosiveProp
	var cyl := hz[1] as ExplosiveProp
	var gap := GameWorld.flat_distance(drum.global_position, cyl.global_position)
	check(gap <= drum.blast_radius + cyl.radius, "they stand inside each other's blast (%.2f apart)" % gap)
	# The AI hero (seat 3) and the host's own hero stand well clear; the client's hero stands by the drum, away from the cylinders.
	var ai := hero_at(3)
	var brain := ai.get_node_or_null("AllyBrain")
	if brain != null:
		brain.set_physics_process(false)
	var spot := _stand_spot(drum, cyl)
	if not check(spot != Vector3.INF, "open floor by the drum, out of the cylinders' blast"):
		return
	var far := _far_spot([drum, cyl], 1)
	var far2 := _far_spot([drum, cyl], 9)
	_put(my_hero(), far)
	_put(ai, far2)
	command(a, "stand", {"at": spot})
	check(await wait_reports("stood", 1, 20.0), "the client's hero stands by the drum")
	await sleep(0.6)
	var host_hp := my_hero().hp
	var client_name := hero_at(2).display_name
	print("[EXP] drum %s, cylinders %s (%.2f apart); the client at %.2f from the drum, %.2f from the cylinders" % [drum.global_position,
		cyl.global_position, gap, GameWorld.flat_distance(spot, drum.global_position), GameWorld.flat_distance(spot, cyl.global_position)])

	# 1. The client's fireball at the drum.
	command(a, "fireball", {"id": NetFloor.id_of(drum)})
	check(await until(func() -> bool: return drum.is_lit() or drum.dead, 6.0), "the host lit the drum")
	check(drum.igniter() == hero_at(2), "blamed on the client's hero (%s)" % str(drum.igniter()))
	check(await until(func() -> bool: return drum.dead and cyl.dead, 8.0), "the drum and then the cylinders blew on the host")
	check(await wait_reports("blasts", 1, 20.0), "the client reports what it saw")
	var r: Dictionary = reported(a, "blasts")
	var mine := {NetFloor.id_of(drum): blasts_seen.get(NetFloor.id_of(drum), {}), NetFloor.id_of(cyl): blasts_seen.get(NetFloor.id_of(cyl), {})}
	for id: int in mine:
		var h: Dictionary = mine[id]
		var c: Dictionary = (r["seen"] as Dictionary).get(id, {})
		var what := "the drum" if id == NetFloor.id_of(drum) else "the cylinders"
		if not check(not h.is_empty() and not c.is_empty(), "both machines saw %s's fuse and blast" % what):
			continue
		print("[EXP] %s: fuse end host %.4f / client %.4f; blew host %.4f / client %.4f (host_time), wall %.4f / %.4f" % [what,
			float(h["fuse_end"]), float(c["fuse_end"]), float(h["blew"]), float(c["blew"]), float(h["truth"]), float(c["truth"])])
		near(float(c["fuse_end"]), float(h["fuse_end"]), 0.02, "the client shows %s's fuse ending when the host does" % what)
		var off := float(c["blew"]) - float(c["fuse_end"])
		check(off >= -0.002 and off <= FRAME + 0.006, "%s blew on the client within a frame of its fuse's end (%+.1f ms)" % [what, off * 1000.0])
		check(absf(float(c["truth"]) - float(h["truth"])) < 0.06, "... and within 60 ms of the host in real time (%.1f ms)" % (absf(float(c["truth"]) - float(h["truth"])) * 1000.0))
	var d_end := float((mine[NetFloor.id_of(cyl)] as Dictionary).get("fuse_end", 0.0)) - float((mine[NetFloor.id_of(drum)] as Dictionary).get("blew", 0.0))
	check(d_end > 0.25 and d_end < 0.7, "the chain: the cylinders lit at the drum's blast, on a short fuse (%.2f s)" % d_end)

	# 2. The client's hero: one hit, its own machine's.
	print("[EXP] the client's hero: %d hit(s), lost %.2f (expected %.2f at %.2f from the drum); in the drum's blast list %s, the cylinders' %s" % [
		int(r["hits"]), float(r["lost"]), float(r["expected"]), float(r["dist"]), r["in_drum"], r["in_cyl"]])
	eq(int(r["hits"]), 1, "the client's hero took exactly one hit")
	near(float(r["lost"]), float(r["expected"]), 0.05, "exactly one blast's damage at its distance")
	check(bool(r["in_drum"]) and not bool(r["in_cyl"]), "from the drum's blast, on its own machine (and not the cylinders')")
	check(not drum.last_hits.has(hero_at(2)), "the host's blast did not apply anything to the client's hero")
	await sleep(0.5)
	near(hero_at(2).hp, float(r["hp"]), 0.15, "the host shows the client's HP as the client has it")
	near(my_hero().hp, host_hp, 0.01, "the host's hero, far away, was not hit")

	# 3. The bill.
	eq(_lines(drum.display_name), 1, "the host billed the %s once" % drum.display_name)
	eq(_lines(cyl.display_name), 1, "and the %s once" % cyl.display_name)
	for l in Ledger.lines:
		if str(l["label"]) in [drum.display_name, cyl.display_name]:
			eq(str(l["who"]), client_name, "%s is billed to the client's hero (%s)" % [str(l["label"]), client_name])
	eq(str(r["ledger"]), ledger_text(), "the client's Ledger (its invoice) is the host's, line for line")
	eq(int(r["drum_lines"]), 1, "the client's invoice has the drum once")

	command(a, "end")
	check(await wait_done(1, 30.0), "the client is done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	eq(int(reported(a, "end")), 0, "... nor on the client")
	print("[EXP] objects: fuses out %d, hit requests in %d" % [int(Session.objects.stats["fuses"]), int(Session.objects.stats["hits_in"])])


func run_client() -> void:
	net_timeout = 75.0
	if not await enter_floor(SEED, 1, {"give": "fireball:9", "hazard_near": HAZARDS}):
		return
	if not await wait_sync():
		return
	_probe()
	var hits := [0, 0.0]
	var blast_srcs: Array = []
	my_hero().damaged.connect(func(amount: float, src: Node) -> void:
		if amount > 0.0:
			hits[0] += 1
			hits[1] += amount
			blast_srcs.append(src))
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"stand":
				my_hero().global_position = cmd["at"]
				my_hero().snap_to_ground()
				await sleep(0.3)
				report("stood", true)
			"fireball":
				var hz: Array = game.get("_dev_hazards")
				var drum := hz[0] as ExplosiveProp
				var cyl := hz[1] as ExplosiveProp
				Burning.set_fireproof(my_hero(), true)   # (the blast may set people alight: this test counts the blast's hit alone)
				var hp := my_hero().hp
				hits[0] = 0
				hits[1] = 0.0
				var c := game.get("controller") as PlayerController
				my_hero()._ready_at.clear()
				# A weak fireball (power 0.3: a 1.7 blast, 12 damage) just short of the drum: its fire reaches the drum and not
				# the cylinders, so the cylinders go up in the chain; its 12 is no hard hit, so the fire is what lights it.
				var to := my_hero().global_position - drum.global_position
				to.y = 0.0
				c.aim_override = drum.global_position + to.normalized() * 0.8
				check(c.cast_spell("fireball", 0.3), "the client cast a fireball")
				c.aim_override = Vector3.INF
				await until(func() -> bool: return drum.dead and cyl.dead, 10.0)
				await sleep(0.6)
				var dist := float((blasts_seen.get(NetFloor.id_of(drum), {}) as Dictionary).get("dist", -1.0))
				var expect := drum.blast_damage * lerpf(1.0, ExplosiveProp.EDGE_MULT, clampf(dist / drum.blast_radius, 0.0, 1.0))
				report("blasts", {"seen": blasts_seen, "hits": hits[0], "lost": hp - my_hero().hp, "expected": expect, "dist": dist,
					"in_drum": drum.last_hits.has(my_hero()), "in_cyl": cyl.last_hits.has(my_hero()), "hp": my_hero().hp,
					"ledger": ledger_text(), "drum_lines": _lines(drum.display_name)})
			"end":
				report("end", Net.guard_hits.size())
				running = false
			_:
				running = false


# --- Helpers ---------------------------------------------------------------------------------------------------

## Record this machine's fuse and blast of each explosive on the shared clock (and its hero's distance at the blast).
func _probe() -> void:
	for e: PricedProp in game.get("_dev_hazards"):
		var x := e as ExplosiveProp
		if x == null:
			continue
		var id := NetFloor.id_of(x)
		x.blew.connect(func(p: ExplosiveProp) -> void:
			var row: Dictionary = blasts_seen.get(id, {})
			row["blew"] = Session.host_time()
			row["truth"] = truth()
			row["fuse_end"] = Session.host_time() + (p.fuse_end - GameWorld.time)
			row["dist"] = GameWorld.flat_distance(my_hero().global_position, p.global_position)
			blasts_seen[id] = row)


## Host: the floor's monsters and hellgates stand still (nothing but the blast should hurt anyone).
func _freeze_world() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster or n is Hellgate:
			n.set_physics_process(false)


func _put(h: Hero, at: Vector3) -> void:
	h.global_position = at
	h.snap_to_ground()


## Open floor 2.0-2.4 from the drum, out of the cylinders' blast by a margin, clear of other actors.
func _stand_spot(drum: ExplosiveProp, cyl: ExplosiveProp) -> Vector3:
	var map := game.get("map") as HexMap
	for r: float in [2.0, 2.2, 2.4]:
		for k in 24:
			var a := TAU * float(k) / 24.0
			var q := drum.global_position + Vector3(cos(a), 0.0, sin(a)) * r
			if GameWorld.flat_distance(q, cyl.global_position) < cyl.blast_radius + 0.8:
				continue
			if not _clear(map, q, drum.global_position, 1.0):
				continue
			# room behind it for the blast's shove (no wall slam, no ledge: one hit only)
			var out := Vector3(cos(a), 0.0, sin(a))
			var room := true
			for s in [0.6, 1.2, 1.8, 2.4]:
				var b: Vector3 = q + out * s
				room = room and map.is_walkable_cell(Hex.from_world(b)) and not map.blocks_point(b, 0.5) and absf(map.ground_height(b) - map.ground_height(q)) < 0.3
			if room:
				return Vector3(q.x, map.ground_height(q), q.z)
	return Vector3.INF


## Open floor far from every one of `props` (out of their blasts by 3), searched from direction `first`.
func _far_spot(props: Array, first: int) -> Vector3:
	var map := game.get("map") as HexMap
	var base: Vector3 = (props[0] as Node3D).global_position
	for r: float in [8.0, 10.0, 12.0, 14.0]:
		for k in 16:
			var a := TAU * float((k + first) % 16) / 16.0
			var q := base + Vector3(cos(a), 0.0, sin(a)) * r
			var ok := true
			for p: ExplosiveProp in props:
				ok = ok and GameWorld.flat_distance(q, p.global_position) > p.blast_radius + 3.0
			if ok and _clear(map, q, base, 1.6):
				return Vector3(q.x, map.ground_height(q), q.z)
	return base + Vector3(20, 0, 0)


func _clear(map: HexMap, q: Vector3, p: Vector3, room: float) -> bool:
	if not map.is_walkable_cell(Hex.from_world(q)) or map.blocks_point(q, 0.6) or absf(map.ground_height(q) - p.y) > 0.6:
		return false
	for a in GameWorld.actors_in_radius(q, room):
		if not (a is Hero):
			return false
	return true


static func _lines(label: String) -> int:
	var n := 0
	for l in Ledger.lines:
		if str(l["kind"]) == "damage" and str(l["label"]) == label:
			n += 1
	return n
