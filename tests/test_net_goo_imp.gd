extends NetGameTest
## The goo imp online (docs/design/goo-imp.md, "As built"), two processes, `off` and `coast`. Floor 1 of the seed-16 job; the
## host spawns a goo imp (a runtime spawn: c1 builds it as a puppet) and has it throw (GooImp.throw_at, the host's strike).
## - THE THROW, THE VICTIM DECIDES: the host announces the ball (obj.new "goo_ball"); c1 builds the same ball (same landing
##   point, the same landing moment on the shared clock) and, standing under it, resolves the hit on its own hero: exactly one
##   ball's damage and the goo slow, which the host then shows on its puppet (NetStatus); the host applied nothing to it, and
##   a hit leaves no patch on either machine;
## - THE PATCH, THE HOST DECIDES: a ball that lands on empty floor makes a patch on the host, announced (obj.new
##   "goo_patch"); c1 has the same patch (id, place) and its own hero walks at x GooPatch.SLOW on it, full speed off it;
## - FIRE: c1's fireball on a patch: the host lights it (its run of c1's cast), blamed on c1's hero, and tells c1 (obj.goo):
##   both show it lit at the same shared moment; c1's hero standing in it is hurt by c1's own machine (the burn's ticks),
##   never set Burning, and the host hurt it not at all; it burns out on both;
## - DAMP: c1's Damp on a patch: the host washes it away and c1's copy goes too;
## - nothing tripped the OWNER-write guard on either machine.

const PEERS := 2
const SEED := 16
const SPELLS := {"spells": "fireball,damp", "give": "fireball:9,damp:9"}


func run_host() -> void:
	net_timeout = 100.0
	if not await enter_floor(SEED, 1, SPELLS):
		return
	if not await wait_sync():
		return
	_freeze_world()
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	check(await wait_reports("ready", 1, 30.0), "c1 is on the floor")
	var c1 := client_peers()[0]
	var ai := hero_at(3)
	if ai != null and ai.get_node_or_null("AllyBrain") != null:
		ai.get_node("AllyBrain").set_physics_process(false)
	var site := _site(my_hero().global_position)
	if not check(not site.is_empty(), "open floor for the imp, c1 and two patches"):
		return
	var p: Vector3 = site["p"]
	_put(my_hero(), site["host"])
	if ai != null:
		_put(ai, site["host"] + Vector3(1.0, 0.0, 0.0))
	command(c1, "stand", {"at": p})
	check(await wait_reports("stood", 1, 10.0), "c1 stands at its spot")
	var imp := MonsterFactory.spawn("goo_imp", Hex.from_world(site["q"])) as GooImp
	if not check(imp != null, "the host spawned a goo imp"):
		return
	imp.global_position = site["q"]
	imp.set_physics_process(false)   # (a statue: it throws when the test says)
	imp.aggro_range = 0.0
	var iid := NetFloor.id_of(imp)
	await sleep(1.0)
	var c1_hero := hero_at(2)

	# 1. The throw: c1's machine resolves the hit on its own hero.
	command(c1, "hit", {"imp": iid})
	await sleep(0.5)
	imp.target = c1_hero
	imp.face_point(c1_hero.global_position)
	var ball := imp.throw_at(c1_hero.global_position)
	var bid := NetFloor.id_of(ball)
	check(bid >= NetRegistry.RUNTIME_BASE, "the host gave the ball a runtime id (%d)" % bid)
	var land_shared := Session.host_time() + (ball.land_time() - GameWorld.time)
	await until(func() -> bool: return ball.landed, 3.0)
	check(ball.hit_any and ball.patch == null, "the host saw c1's hero under it: a hit, no patch")
	eq(ball.hits_applied, 0, "the host applied nothing to c1's hero (the victim decides)")
	check(await until(func() -> bool: return c1_hero.has_modifier(GooPatch.SLOW_ID), 1.2), "the host shows the slow on c1's hero (NetStatus)")
	if check(await wait_reports("hit", 1, 15.0), "c1 reports the hit"):
		var r: Dictionary = reported(c1, "hit")
		eq(int(r["ball"]), bid, "c1 built the host's ball (obj.new, same id)")
		near(float(r["to_err"]), 0.0, 0.01, "... landing on the same point")
		near(float(r["land"]), land_shared, 0.05, "... at the same shared moment (%.3f s apart)" % absf(float(r["land"]) - land_shared))
		eq(int(r["hits"]), 1, "c1's hero was hit once")
		near(float(r["lost"]), GooBall.DAMAGE, 0.001, "... for one ball's damage (%.0f)" % GooBall.DAMAGE)
		check(bool(r["slowed"]), "... and the goo slow, on c1's machine")
		eq(int(r["patches"]), 0, "c1: a hit leaves no patch")
	eq(GooPatch.live().size(), 0, "the host has no patch either")
	await sleep(2.0)   # (the hit's slow wears off)

	# 2. A miss: the host's patch, on c1 too, slows c1's hero there.
	var s1: Vector3 = site["s1"]
	var b2 := imp.throw_at(s1)
	await until(func() -> bool: return b2.landed, 3.0)
	var patch := b2.patch as GooPatch
	if not check(patch != null, "a miss on empty floor: the host made a patch"):
		return
	var pid := NetFloor.id_of(patch)
	check(pid >= NetRegistry.RUNTIME_BASE, "... with a runtime id (%d)" % pid)
	command(c1, "patch", {"id": pid, "at": s1, "off": p})
	if check(await wait_reports("patch", 1, 15.0), "c1 reports the patch"):
		var r2: Dictionary = reported(c1, "patch")
		check(bool(r2["has"]), "c1 has the host's patch (obj.new, same id)")
		near(float(r2["err"]), 0.0, 0.01, "... in the same place")
		near(float(r2["ratio"]), GooPatch.SLOW, 0.001, "c1's own hero walks at x%.2f on it" % GooPatch.SLOW)
		near(float(r2["off_ratio"]), 1.0, 0.001, "... and at full speed off it")

	# 3. Fire: c1's fireball lights the patch on the host (blamed on c1), and both show it lit at once.
	var host_burns := [-1]
	patch.tree_exiting.connect(func() -> void: host_burns[0] = patch.burns_applied)
	var wpatch: WeakRef = weakref(patch)
	command(c1, "fire", {"id": pid, "at": s1, "from": site["fire_from"]})
	check(await until(func() -> bool: return wpatch.get_ref() == null or (wpatch.get_ref() as GooPatch).is_lit(), 10.0), "c1's fireball lit the host's patch")
	if wpatch.get_ref() != null:
		check(patch.lit_by == c1_hero, "... blamed on c1's hero")
		var lit_shared := Session.host_time() + (patch.lit_at - GameWorld.time)
		if check(await wait_reports("fire", 1, 20.0), "c1 reports the fire"):
			var r3: Dictionary = reported(c1, "fire")
			check(bool(r3["lit"]), "c1 shows it lit (obj.goo)")
			near(float(r3["lit_at"]), lit_shared, 0.05, "... from the same shared moment (%.3f s apart)" % absf(float(r3["lit_at"]) - lit_shared))
			check(float(r3["lost"]) > 0.0, "the burn hurt c1's hero standing in it (%.0f)" % float(r3["lost"]))
			check(int(r3["burns"]) >= 2, "... c1's own machine applied it (%d ticks)" % int(r3["burns"]))
			check(not bool(r3["burning"]), "... and never set it Burning (no fire spread)")
			check(bool(r3["gone"]), "it burnt out on c1")
	check(await until(func() -> bool: return wpatch.get_ref() == null, 5.0), "it burnt out on the host")
	eq(host_burns[0], 0, "the host burnt nobody: c1's hero in it is c1's to decide")

	# 4. Damp: c1's Damp washes a patch away on the host, and c1's copy goes too.
	var s2: Vector3 = site["s2"]
	var b3 := imp.throw_at(s2)
	await until(func() -> bool: return b3.landed, 3.0)
	var patch2 := b3.patch as GooPatch
	if not check(patch2 != null, "another patch"):
		return
	var pid2 := NetFloor.id_of(patch2)
	var wp: WeakRef = weakref(patch2)
	command(c1, "damp", {"id": pid2, "at": s2, "from": p})
	check(await until(func() -> bool: return wp.get_ref() == null or (wp.get_ref() as GooPatch).washed, 10.0), "c1's Damp washed the host's patch away")
	if check(await wait_reports("damp", 1, 20.0), "c1 reports the damp"):
		var r4: Dictionary = reported(c1, "damp")
		check(bool(r4["had"]), "c1 had the patch")
		check(bool(r4["gone"]), "... and it is gone on c1 too")
		check(bool(r4["wet"]), "... Damp's own wet floor is what is left")
	check(int(Session.objects.stats.get("goo_out", 0)) >= 2, "the host told the patches' changes (obj.goo: lit, washed)")

	command(c1, "end")
	check(await wait_reports("end", 1, 10.0), "c1 is done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	eq(int(reported(c1, "end")), 0, "... nor on c1")


func run_client() -> void:
	net_timeout = 100.0
	if not await enter_floor(SEED, 1, SPELLS):
		return
	if not await wait_sync():
		return
	var hits := [0, 0.0]
	my_hero().damaged.connect(func(amount: float, _src: Node) -> void:
		if amount > 0.0:
			hits[0] += 1
			hits[1] += amount)
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"stand":
				_put(my_hero(), cmd["at"])
				await sleep(0.4)
				report("stood", true)
			"hit":
				hits[0] = 0
				hits[1] = 0.0
				var news := int(Session.objects.stats.get("news", 0))
				await until(func() -> bool: return int(Session.objects.stats.get("news", 0)) > news, 10.0)
				var b := _newest_ball()
				var row := {"ball": NetFloor.id_of(b) if b != null else 0, "to_err": 99.0, "land": -1.0}
				if b != null:
					row["to_err"] = 0.0   # (filled below by the host's comparison of the landing point)
					row["land"] = Session.host_time() + (b.land_time() - GameWorld.time)
					var landing := b.to
					var wb: WeakRef = weakref(b)
					await until(func() -> bool: return wb.get_ref() == null or (wb.get_ref() as GooBall).landed, 3.0)
					row["to_err"] = GameWorld.flat_distance(landing, my_hero().global_position)
				await sleep(0.3)
				row["hits"] = hits[0]
				row["lost"] = hits[1]
				row["slowed"] = my_hero().has_modifier(GooPatch.SLOW_ID)
				row["patches"] = GooPatch.live().size()
				report("hit", row)
			"patch":
				await until(func() -> bool: return NetRegistry.node(int(cmd["id"])) is GooPatch, 10.0)
				var gp := NetRegistry.node(int(cmd["id"])) as GooPatch
				var off := my_hero().effective_speed()
				_put(my_hero(), cmd["at"])
				var on := my_hero().effective_speed()
				_put(my_hero(), cmd["off"])
				var off2 := my_hero().effective_speed()
				report("patch", {"has": gp != null, "err": GameWorld.flat_distance(gp.global_position, cmd["at"]) if gp != null else 99.0,
					"ratio": on / maxf(off, 0.001), "off_ratio": off2 / maxf(off, 0.001)})
			"fire":
				var gp2 := NetRegistry.node(int(cmd["id"])) as GooPatch
				var wp: WeakRef = weakref(gp2)
				_put(my_hero(), cmd["from"])
				await sleep(0.3)
				var c := game.get("controller") as PlayerController
				my_hero()._ready_at.clear()
				c.aim_override = cmd["at"]
				check(c.cast_spell("fireball", 0.5), "c1 cast a fireball at the patch")
				c.aim_override = Vector3.INF
				await until(func() -> bool: return wp.get_ref() == null or (wp.get_ref() as GooPatch).is_lit(), 6.0)
				var lit: bool = wp.get_ref() != null and (wp.get_ref() as GooPatch).is_lit()
				var lit_at := -1.0
				if lit:
					lit_at = Session.host_time() + ((wp.get_ref() as GooPatch).lit_at - GameWorld.time)
				# step into the burning goo (the blast is over)
				_put(my_hero(), cmd["at"])
				var hp := my_hero().hp
				await sleep(1.6)
				var burns := (wp.get_ref() as GooPatch).burns_applied if wp.get_ref() != null else 0
				var burning := Burning.is_burning(my_hero())
				var lost := hp - my_hero().hp
				_put(my_hero(), cmd["from"])
				await until(func() -> bool: return wp.get_ref() == null, 5.0)
				report("fire", {"lit": lit, "lit_at": lit_at, "lost": lost, "burns": burns, "burning": burning, "gone": wp.get_ref() == null})
			"damp":
				await until(func() -> bool: return NetRegistry.node(int(cmd["id"])) is GooPatch, 10.0)
				var gp3 := NetRegistry.node(int(cmd["id"])) as GooPatch
				var had := gp3 != null
				var wp3: WeakRef = weakref(gp3)
				_put(my_hero(), cmd["from"])
				await sleep(0.3)
				var c2 := game.get("controller") as PlayerController
				my_hero()._ready_at.clear()
				c2.aim_override = cmd["at"]
				check(c2.cast_spell("damp", 0.5), "c1 cast damp at the patch")
				c2.aim_override = Vector3.INF
				await until(func() -> bool: return wp3.get_ref() == null, 6.0)
				var wet := false
				for n in get_tree().get_nodes_in_group(Damp.GROUP):
					if (n as Damp).is_wet_at(cmd["at"]):
						wet = true
				report("damp", {"had": had, "gone": wp3.get_ref() == null, "wet": wet})
			"end":
				report("end", Net.guard_hits.size())
				running = false
			_:
				running = false


# --- Helpers ---------------------------------------------------------------------------------------------------------

func _newest_ball() -> GooBall:
	var best: GooBall = null
	for id in NetRegistry.ids():
		var b := NetRegistry.node(id) as GooBall
		if b != null and (best == null or id > NetFloor.id_of(best)):
			best = b
	return best


func _freeze_world() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if (n is Monster or n is Hellgate) and not (n as Actor).dead:
			n.set_physics_process(false)


func _put(h: Hero, at: Vector3) -> void:
	h.global_position = at
	h.snap_to_ground()


## Host: a level, open stretch of floor near `base`: c1's spot p, the imp's q 7 away with a clear lob, two empty spots s1 and
## s2 3.2 to either side of p, where c1 casts its fireball from (fire_from, 4 off s1) and where the host's heroes wait.
func _site(base: Vector3) -> Dictionary:
	var map := game.get("map") as HexMap
	var cells: Array = map.cells.keys()
	cells.sort()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return GameWorld.flat_distance(Hex.to_world(a), base) < GameWorld.flat_distance(Hex.to_world(b), base))
	for c: Vector2i in cells:
		if not map.is_walkable_cell(c) or map.is_pool_cell(c):
			continue
		var p := Hex.to_world(c, float(map.get_cell(c).level))
		if not _open(map, p, 1.2):
			continue
		for k in 12:
			var f := Vector3(cos(TAU * float(k) / 12.0), 0.0, sin(TAU * float(k) / 12.0))
			var side := f.rotated(Vector3.UP, PI * 0.5)
			var q := _level(map, p + f * 7.0, p.y)
			var s1 := _level(map, p + side * 3.2, p.y)
			var s2 := _level(map, p - side * 3.2, p.y)
			var ff := _level(map, s1 + f * 4.0, p.y)
			var host := _level(map, p - f * 9.0, p.y)
			if q == Vector3.INF or s1 == Vector3.INF or s2 == Vector3.INF or ff == Vector3.INF or host == Vector3.INF:
				continue
			if not map.line_of_sight(q + Vector3.UP * 0.9, p + Vector3.UP * 0.9) or not map.line_of_sight(ff + Vector3.UP * 0.9, s1 + Vector3.UP * 0.9):
				continue
			return {"p": p, "q": q, "s1": s1, "s2": s2, "fire_from": ff, "host": host}
	return {}


func _level(map: HexMap, p: Vector3, y: float) -> Vector3:
	var h := map.ground_height(p)
	if is_nan(h) or absf(h - y) > 0.05 or not _open(map, Vector3(p.x, h, p.z), 1.0):
		return Vector3.INF
	return Vector3(p.x, h, p.z)


func _open(map: HexMap, p: Vector3, clear: float) -> bool:
	if not map.is_walkable_cell(Hex.from_world(p)) or map.blocks_point(p, 0.7) or map.is_pool_cell(Hex.from_world(p)):
		return false
	for x in GameWorld.actors_in_radius(p, clear):
		if not (x is Hero):
			return false
	return GameWorld.props_in_radius(p, clear).is_empty() and GameWorld.breakables_in_radius(p, clear).is_empty()
