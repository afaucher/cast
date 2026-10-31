extends NetGameTest
## Zombies and their bodies online (docs/design/haunted-build-plan.md, H3), three processes, `off` and `coast`. Board 9's
## second offer is a haunted mansion (the estate heir) whose pest is zombies. The host and c1 play floor 1; c2 joins later,
## on the job. A zombie is a host monster; its body stays down (`dead` rides world.die), stands back up (world.rise) and
## burns (world.burn). Three of the floor's zombies, A, B and C, are moved apart near the host's hero and the floor stands
## still.
## - THE BODIES: the host kills A, B and C; c1 shows all three down as bodies where the host has them (lying, not freed);
## - THE BURN: the host's fireball over B burns it on the host, and c1 shows B charred;
## - THE RAISE, THE OWNER DECIDES: c1's coffee at A (a cast every machine runs) stands A up on the host (its owner) at the
##   coffee zombie's HP, and c1 shows A standing again, streamed (a puppet), back among the monsters; the coffee at B does
##   nothing (burnt);
## - THE LATE JOINER: c2 joins and sees A standing where the host has it, B a burnt body and C a body, each where it lies;
## - after the join, the host kills A again and burns C: c1 and c2 both show A down and C charred;
## - nothing tripped the OWNER-write guard on any machine.
## (Three processes, not two: a late joiner needs a crew already on the floor; a host alone on a job admits nobody, NetJoin.)

const PEERS := 3
const SEED := 9
const CONTRACT := 1
const JOINER_SPELLS := ["tentacles", "teeth"]
const SPREAD := 5.5                ## the bodies stand this far from the host's hero ...
const APART := 7.5                 ## ... and at least this far from each other (one splash or blast covers one)


func run_host() -> void:
	net_timeout = 150.0
	clear_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	make_game({"spells": "coffee,fireball", "seed": SEED, "contract": CONTRACT, "net_wait": 2})
	if not check(await wait_floor(45.0), "floor 1 starts") or not await wait_sync():
		return
	(game.get("opts") as Dictionary).erase("net_wait")
	var run: ContractRun = game.get("_run")
	if not check(run != null and run.family == ClientArchetype.FAMILY_DEAD and run.pest == "zombie", "a haunted contract whose pest is zombies (%s)" % (run.archetype_id if run != null else "none")):
		return
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	_freeze_world()
	var zs := _zombies()
	if not check(zs.size() >= 3, "floor 1 has zombies (%d)" % zs.size()):
		return
	var spots := _spots(my_hero().global_position, 3)
	if not check(spots.size() == 3, "three open spots round the host's hero"):
		return
	var za: Zombie = zs[0]
	var zb: Zombie = zs[1]
	var zc: Zombie = zs[2]
	var ids := [NetFloor.id_of(za), NetFloor.id_of(zb), NetFloor.id_of(zc)]
	for i in 3:
		zs[i].global_position = spots[i]
		zs[i].snap_to_ground()
	check(await wait_reports("ready", 1, 30.0), "c1 is on the floor")
	await sleep(1.0)

	# 1. The bodies: the host kills all three; c1 shows them down where they lie.
	for z in [za, zb, zc]:
		z.die()
	check(za.dead and za.is_body() and zb.is_body() and zc.is_body(), "on the host they lie as bodies")
	await sleep(0.8)
	command(c1(), "look", {"ids": ids, "tag": "down"})
	if check(await wait_reports("down", 1, 10.0), "c1 looked at the bodies"):
		var r: Dictionary = reported(c1(), "down")
		for i in 3:
			var row: Dictionary = r[ids[i]]
			check(bool(row["dead"]) and bool(row["lying"]) and bool(row["valid"]), "c1 shows zombie %d down as a body" % ids[i])
			check(_flat(row["pos"], [za, zb, zc][i].global_position) < 0.6, "... where the host has it (%.2f off)" % _flat(row["pos"], [za, zb, zc][i].global_position))
			check(not bool(row["monster"]), "... out of the monsters (the pest count)")

	# 2. The burn: the host's fireball over B.
	_cast_here("fireball", zb.global_position)
	check(await until(func() -> bool: return zb.burnt, 5.0), "the host's fireball burnt body B")
	check(not za.burnt and not zc.burnt, "... and only B")
	await sleep(0.6)
	command(c1(), "look", {"ids": ids, "tag": "burnt"})
	if check(await wait_reports("burnt", 1, 10.0), "c1 looked again"):
		var r: Dictionary = reported(c1(), "burnt")
		check(bool(r[ids[1]]["burnt"]) and bool(r[ids[1]]["charred"]), "c1 shows B charred")
		check(not bool(r[ids[0]]["burnt"]) and not bool(r[ids[2]]["burnt"]), "... and A and C as they were")

	# 3. The raise: c1's coffee at A stands it up on the host; the coffee at B does nothing.
	var rises0 := int(Session.world.stats.get("rises", 0))
	command(c1(), "cast", {"spell": "coffee", "aim": za.global_position})
	check(await until(func() -> bool: return not za.dead, 5.0), "c1's coffee stood A up on the host (its owner)")
	near(za.hp, CoffeeSpell.ZOMBIE_HP, 0.5, "... at the coffee zombie's HP")
	check(int(Session.world.stats.get("rises", 0)) > rises0, "the host sent world.rise")
	command(c1(), "cast", {"spell": "coffee", "aim": zb.global_position})
	await sleep(NetCasts.LEAD + 0.8)
	check(zb.dead and zb.burnt, "the coffee at B: a burnt body stays down")
	await sleep(Zombie.RISE_TIME)
	command(c1(), "look", {"ids": ids, "tag": "raised"})
	if check(await wait_reports("raised", 1, 10.0), "c1 looked at A"):
		var r: Dictionary = reported(c1(), "raised")
		var a: Dictionary = r[ids[0]]
		check(not bool(a["dead"]) and not bool(a["lying"]) and bool(a["puppet"]) and bool(a["monster"]), "c1 shows A standing again, a puppet, a monster")
		eq(int(a["raises"]), 1, "c1 showed it rise once")
		near(float(a["hp"]), za.hp, 0.6, "... at the host's HP")
		check(_flat(a["pos"], za.global_position) < 0.6, "... where the host has it")
		check(bool(r[ids[1]]["dead"]), "c1 shows B still down")

	# 4. The late joiner.
	raise_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 30.0), "c2 joins the crew on the job"):
		return
	var c2 := peer_named("c2")
	if not check(await wait_reports("checkout", 1, 30.0), "c2 opened its license checkout"):
		return
	command(c2, "sign", {"spells": JOINER_SPELLS})
	if not check(await wait_reports("arrived", 1, 40.0), "c2 arrived"):
		return
	var adm: Dictionary = Session.join.admitted.get(c2, {})
	check((adm.get("gone", []) as Array).has(ids[1]) and (adm.get("gone", []) as Array).has(ids[2]), "the snapshot's gone ids hold the bodies")
	await sleep(1.0)
	command(c2, "look", {"ids": ids, "tag": "joined"})
	if check(await wait_reports("joined", 1, 10.0), "c2 looked"):
		var r: Dictionary = reported(c2, "joined")
		check(not bool(r[ids[0]]["dead"]) and _flat(r[ids[0]]["pos"], za.global_position) < 0.6, "c2: A standing where the host has it")
		check(bool(r[ids[1]]["dead"]) and bool(r[ids[1]]["lying"]) and bool(r[ids[1]]["charred"]), "c2: B a burnt body")
		check(_flat(r[ids[1]]["pos"], zb.global_position) < 0.3, "... where it lies (%.2f off)" % _flat(r[ids[1]]["pos"], zb.global_position))
		check(bool(r[ids[2]]["dead"]) and bool(r[ids[2]]["lying"]) and not bool(r[ids[2]]["burnt"]), "c2: C a body, not burnt")
		check(_flat(r[ids[2]]["pos"], zc.global_position) < 0.3, "... where it lies (%.2f off)" % _flat(r[ids[2]]["pos"], zc.global_position))

	# 5. After the join: A down again, C burnt, on both clients.
	za.die()
	_cast_here("fireball", zc.global_position)
	check(await until(func() -> bool: return zc.burnt, 5.0), "the host's fireball burnt C")
	await sleep(0.8)
	for p in [c1(), c2]:
		command(p, "look", {"ids": ids, "tag": "after"})
	if check(await wait_reports("after", 2, 10.0), "both clients looked"):
		for p in [c1(), c2]:
			var r: Dictionary = reported(p, "after")
			var who := "c1" if p == c1() else "c2"
			check(bool(r[ids[0]]["dead"]) and bool(r[ids[0]]["lying"]), "%s shows A down again" % who)
			check(bool(r[ids[2]]["charred"]), "%s shows C charred" % who)
	command(c2, "end")
	command(c1(), "end")
	check(await wait_reports("end", 2, 10.0), "the clients are done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	for p in [c1(), c2]:
		eq(int((reported(p, "end") as Dictionary)["guard"]), 0, "... nor on %s" % ("c1" if p == c1() else "c2"))
	print("[zombies] world: %d rises, %d burns, %d deaths sent" % [int(Session.world.stats.get("rises", 0)), int(Session.world.stats.get("burns", 0)), int(Session.world.stats.get("deaths", 0))])
	clear_flag("join")


func run_client() -> void:
	net_timeout = 150.0
	if index == 2:
		await _late_joiner()
		return
	if not check(await connect_client() == "", "joined"):
		return
	make_game({"spells": "coffee,fireball"})
	if not check(await wait_floor(45.0), "the floor starts here") or not await wait_sync():
		return
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	report("ready", true)
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
					var z := NetRegistry.node(id) as Zombie
					var valid := z != null and is_instance_valid(z)
					out[id] = {"valid": valid, "dead": valid and z.dead, "burnt": valid and z.burnt,
						"lying": valid and z.model is ZombieModel and (z.model as ZombieModel).is_lying(),
						"charred": valid and z.model is ZombieModel and (z.model as ZombieModel).charred,
						"puppet": valid and Net.is_puppet(z), "monster": valid and z.is_in_group("monsters"),
						"raises": z.raises if valid else -1, "hp": z.hp if valid else -1.0,
						"pos": z.global_position if valid else Vector3.INF}
				report(str(cmd["tag"]), out)
			"cast":
				_cast_here(str(cmd["spell"]), cmd["aim"])
			"end":
				report("end", {"guard": Net.guard_hits.size()})
				running = false
			_:
				running = false


# --- Helpers ---------------------------------------------------------------------------------------------------

func c1() -> int:
	return peer_named("c1")


## The floor's living zombies (seed-built), nearest the host's hero first.
func _zombies() -> Array[Zombie]:
	var out: Array[Zombie] = []
	var site: SiteBuilder.Site = game.get("_site")
	for m in site.monsters:
		if m is Zombie and not m.dead:
			out.append(m as Zombie)
	var at := my_hero().global_position
	out.sort_custom(func(a: Zombie, b: Zombie) -> bool: return GameWorld.flat_distance(a.global_position, at) < GameWorld.flat_distance(b.global_position, at))
	return out


## Monsters, gates and the AI seats stand still (the bodies stay where the test puts them).
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


## Up to `n` open floor spots SPREAD from `p` (level with it, in sight of it, nothing standing there), APART from each other.
func _spots(p: Vector3, n: int) -> Array[Vector3]:
	var map := game.get("map") as HexMap
	var out: Array[Vector3] = []
	for dist: float in [SPREAD, SPREAD - 1.0, SPREAD + 1.0]:
		for k in 24:
			if out.size() >= n:
				return out
			var a := TAU * float(k) / 24.0
			var q := p + Vector3(cos(a), 0.0, sin(a)) * dist
			if not map.is_walkable_cell(Hex.from_world(q)) or map.blocks_point(q, 0.7) or absf(map.ground_height(q) - p.y) > 0.3:
				continue
			q.y = map.ground_height(q)
			if not map.line_of_sight(p + Vector3.UP, q + Vector3.UP):
				continue
			var ok := true
			for o in out:
				ok = ok and GameWorld.flat_distance(o, q) >= APART
			for x in GameWorld.actors_in_radius(q, 1.2):
				ok = ok and (x is Zombie)
			if ok:
				out.append(q)
	return out


func _cast_here(spell: String, at: Vector3) -> void:
	var c := game.get("controller") as PlayerController
	my_hero()._ready_at.clear()
	c.aim_override = at
	check(c.cast_spell(spell, 1.0), "%s cast %s" % [Session.player_name, spell])
	c.aim_override = Vector3.INF


static func _flat(a: Variant, b: Vector3) -> float:
	var v: Vector3 = a
	return Vector2(v.x - b.x, v.z - b.z).length()
