extends MonsterTestBase
## The acolyte and its procession (docs/design/haunted-build-plan.md, "H4 as built"), solo, on a flat arena:
## - the kind: an Acolyte in the cowl with its lantern light, the dead family's, no attack, slower than the crew, a priority
##   target for the AI allies;
## - it FLEES a hero it sees (never strikes), and calms down back to rest once the crew is far;
## - a PROCESSION (ProcessionPlanner.build: a leader, four zombies GAP apart in file, a rear acolyte) walks its route: the
##   leader reaches the route's spots, the file keeps its places behind it;
## - it STOPS AT A BODY and an acolyte RAISES it (its wind-up: the file stands, the arms go up, the body stands at full HP), and
##   the raised zombie JOINS the back of the file and walks on with it;
## - a BURNT body is passed over;
## - the crew ENGAGES it: the zombies fight, the acolytes flee, the file stands;
## - the leader dies: the rear acolyte leads; both dead: the zombies are ordinary monsters;
## - KILLING ACOLYTES PAYS (ContractSession.acolyte_stopped: the acolyte rate per kill, up to the floor's count);
## - the gym's "Acolyte" and "Procession".

const ROUTE: Array[Vector2i] = [Vector2i(-5, 2), Vector2i(5, -2), Vector2i(0, 5)]
const BODY_CELL := Vector2i(0, 1)       ## beside the leader's first leg (ROUTE[0] -> ROUTE[1])


func _init() -> void:
	timeout_sec = 400.0   # (game seconds at the runner's fixed 60 fps: the walks take a while; set before the timer starts)


func setup() -> void:
	_kind()
	await _flees()
	await _walks_route()
	await _raises_body()
	await _burnt_passed()
	await _engaged()
	_pays()
	await _gym()
	finish()


func _arena() -> HexMap:
	var map := flat_map(14)
	new_world(map)
	return map


func _procession(map: HexMap) -> Procession:
	return ProcessionPlanner.build(map, ROUTE, [], "TestProcession")


func _kind() -> void:
	_arena()
	var a := MonsterFactory.spawn("acolyte", Vector2i(0, 0)) as Acolyte
	if not check(a != null, "the acolyte kind spawns an Acolyte"):
		return
	eq(a.kind, "acolyte", "its kind")
	eq(a.display_name, "Acolyte", "its name")
	check(a.model is AcolyteModel and (a.model as AcolyteModel).variant == "cowl", "it wears the cowl (the user's pick)")
	check(a.model.find_child("LanternLight", true, false) is OmniLight3D, "its lantern lights the floor round it")
	eq(MonsterDefs.family_of("acolyte"), "dead", "the dead family's")
	check(a.is_priority_target(), "the AI allies go for it first")
	eq(a.attack_damage, 0.0, "it has no attack")
	check(a.move_speed < 4.5, "the crew outruns it (%.1f)" % a.move_speed)
	var grunt := MonsterFactory.spawn("grunt", Vector2i(3, 0))
	check(a.max_hp < grunt.max_hp, "frailer than a skeleton (%.0f HP)" % a.max_hp)
	check(not a.can_yell(), "no war cry")
	a.free()
	grunt.free()


func _flees() -> void:
	_arena()
	var a := MonsterFactory.spawn("acolyte", Vector2i(0, 0)) as Acolyte
	var hero := add_hero(Vector2i(3, 0))
	var d0 := fdist(a, hero)
	check(await wait_until(func() -> bool: return a.is_fleeing(), 30), "it sees the hero and runs")
	await frames(240)
	check(fdist(a, hero) > d0 + 3.0, "away from the hero (%.1f -> %.1f)" % [d0, fdist(a, hero)])
	check(a.state != Monster.State.CHASE and a.state != Monster.State.ATTACK, "it never fights")
	check(await wait_until(func() -> bool: return a.state == Monster.State.IDLE, 900), "far from the crew it calms down (%.1f away)" % fdist(a, hero))
	near(hero.hp, hero.max_hp, 0.001, "and never struck the hero")
	# a hit makes it run too
	a.apply_damage(1.0, hero)
	check(a.is_fleeing(), "a hit sends it running")
	a.free()


func _walks_route() -> void:
	var map := _arena()
	var pr := _procession(map)
	eq(pr.acolytes.size(), 2, "a procession: two acolytes")
	eq(pr.zombies.size(), Procession.FILE, "... and its file of zombies")
	check(pr.acolytes[0] is Acolyte and pr.zombies[0] is Zombie, "real monsters")
	check(pr.zombies.all(func(z: Monster) -> bool: return z.procession == pr), "each in it")
	var lead := pr.acolytes[0]
	var start := lead.global_position
	near(GameWorld.flat_distance(pr.zombies[pr.zombies.size() - 1].global_position, Hex.to_world(ROUTE[0])), Procession.GAP * 1.5, 1.2, "it starts on its first leg, the file reaching back to its first spot")
	check(GameWorld.flat_distance(start, Hex.to_world(ROUTE[1])) < GameWorld.flat_distance(Hex.to_world(ROUTE[0]), Hex.to_world(ROUTE[1])), "the leader ahead, toward the next")
	var worst := 0.0
	var gaps := []
	var walked := 0.0
	var last := start
	for t in 1300:
		await get_tree().physics_frame
		walked += GameWorld.flat_distance(lead.global_position, last)
		last = lead.global_position
		if t > 120 and t % 30 == 0 and not pr.halted:
			for z in pr.zombies:
				worst = maxf(worst, GameWorld.flat_distance(z.global_position, pr.place_of(z)))
			gaps.append(GameWorld.flat_distance(pr.zombies[0].global_position, pr.zombies[1].global_position))
	check(pr.legs >= 1, "the leader reached the next room on its route (%d)" % pr.legs)
	check(walked > 12.0, "the procession walked (%.1f, now %.1f from where it set out)" % [walked, GameWorld.flat_distance(lead.global_position, start)])
	check(worst < 1.2, "the file keeps its places behind the leader (worst %.2f off)" % worst)
	var mean := 0.0
	for g: float in gaps:
		mean += g / float(gaps.size())
	check(mean > 1.2 and mean < 2.4, "about GAP apart (%.2f)" % mean)
	check(pr.zombies.all(func(z: Monster) -> bool: return z.state == Monster.State.IDLE), "nobody fought")
	# the leader dies: the rear acolyte leads on
	var rear := pr.acolytes[1]
	var rear_at := rear.global_position
	lead.die()
	await frames(2)
	check(pr.leader() == rear, "the rear acolyte leads now")
	# (the leader's death is a noise: the rear acolyte runs from it a moment and the file looks round, then they walk on)
	check(await wait_until(func() -> bool: return GameWorld.flat_distance(rear.global_position, rear_at) > 2.0, 1500), "... and walks on (%s)" % _states(pr))
	rear.die()
	await frames(5)
	check(pr.zombies.is_empty(), "both acolytes dead: the procession is over")
	check(get_tree().get_nodes_in_group("monsters").filter(func(n: Node) -> bool: return n is Zombie and (n as Zombie).procession != null).is_empty(), "... its zombies are ordinary monsters")


## A zombie's body by the leader's way; the procession walks up to it.
func _body(burnt: bool) -> Zombie:
	var z := MonsterFactory.spawn("zombie", BODY_CELL) as Zombie
	z.die()
	if burnt:
		z.burn_body(null)
	return z


func _raises_body() -> void:
	var map := _arena()
	var z := _body(false)   # (down before the procession comes: nobody heard it fall)
	var pr := _procession(map)
	check(z.is_body() and z.procession == null, "a body by the way, nobody's")
	var saw := {"halt": false, "attack": false, "arms": false}
	var raised := await wait_until(func() -> bool:
		saw["halt"] = saw["halt"] or pr.halted
		for a in pr.acolytes:
			if a.state == Monster.State.ATTACK:
				saw["attack"] = true
				saw["arms"] = saw["arms"] or (a.model as AcolyteModel).raise_k() > 0.9
		return not z.dead, 1200)
	check(raised, "an acolyte came across the body and raised it")
	check(saw["halt"] and saw["attack"], "the file stopped while it raised (its wind-up)")
	check(saw["arms"], "arms up (the look test's gesture)")
	near(z.hp, z.max_hp, 0.001, "the body stands at full HP (Zombie.raise)")
	eq(int(pr.acolytes[0].get("raised")) + int(pr.acolytes[1].get("raised")), 1, "one raise")
	check(pr.zombies.has(z) and z.procession == pr and pr.joined == 1, "the raised zombie joined the file")
	eq(pr.zombies.find(z), pr.zombies.size() - 1, "... at its back")
	var lead_at := pr.leader().global_position
	check(await wait_until(func() -> bool: return GameWorld.flat_distance(pr.leader().global_position, lead_at) > 2.0, 900), "the procession walks on (%s)" % _states(pr))
	await frames(120)
	check(GameWorld.flat_distance(z.global_position, pr.place_of(z)) < 1.2, "the raised zombie walks in its place in the file (%.2f off)" % GameWorld.flat_distance(z.global_position, pr.place_of(z)))
	check(not z.is_rising() and z.state == Monster.State.IDLE, "standing, resting with the file")


## Each member: kind, state, how far from its place (diagnostics).
func _states(pr: Procession) -> String:
	var out: Array[String] = ["halted %s" % pr.halted]
	for m in pr.members():
		var p := pr.place_of(m)
		out.append("%s %s %.1f" % [m.kind, m.state_name(), GameWorld.flat_distance(m.global_position, p) if p != Vector3.INF else -1.0])
	return ", ".join(out)


func _burnt_passed() -> void:
	var map := _arena()
	var z := _body(true)
	var pr := _procession(map)
	check(z.burnt and not z.is_downed(), "a burnt body by the way")
	await frames(1200)
	check(z.dead and z.burnt and z.raises == 0, "the procession passed it over (burnt bodies never rise)")
	eq(int(pr.acolytes[0].get("raised")) + int(pr.acolytes[1].get("raised")), 0, "no raise")
	check(pr.legs >= 1, "it walked on past")


func _engaged() -> void:
	var map := _arena()
	var pr := _procession(map)
	var hero := add_hero(Vector2i(0, 0))
	hero.max_hp = 100000.0
	hero.hp = hero.max_hp
	var lead := pr.leader()
	var d0 := fdist(lead, hero)
	var fought := func() -> int:
		return pr.zombies.filter(func(m: Monster) -> bool: return m.state == Monster.State.CHASE or m.state == Monster.State.ATTACK).size()
	check(await wait_until(func() -> bool: return lead.state == Monster.State.ALERT and fought.call() >= 3, 120), "the crew is seen: the acolytes run and the zombies fight (%d)" % fought.call())
	await frames(2)
	check(pr.halted, "the file stands while they fight")
	await frames(240)
	check(fdist(lead, hero) > d0, "the leader ran from the crew (%.1f -> %.1f)" % [d0, fdist(lead, hero)])
	check(pr.acolytes.all(func(a: Monster) -> bool: return a.state == Monster.State.ALERT), "both acolytes run")
	check(hero.hp < hero.max_hp, "the zombies got to the crew")


func _pays() -> void:
	var run := ContractRun.make("heir", 3, 0.55)
	eq(run.acolytes_on(1), 2, "floor 1: one procession, two acolytes")
	var s := ContractSession.begin(run, 1)
	s.enter_floor(1, 0, false, 2, 5, run.acolytes_on(1))
	eq(s.acolyte_stopped(), run.acolyte_pay, "killing an acolyte pays")
	eq(s.acolyte_stopped(), run.acolyte_pay, "... and the second")
	eq(s.acolyte_stopped(), 0, "no more than the floor's count")
	eq(int(s.state()["acolytes_stopped"]), 2, "the floor's tally")
	var lines := Ledger.lines.filter(func(l: Dictionary) -> bool: return str(l.get("label", "")) == "Acolyte stopped")
	eq(lines.size(), 2, "two Ledger lines")


func _gym() -> void:
	var map := _arena()
	var one := GymSpawns.find("monster:acolyte")
	check(not one.is_empty(), "the gym's Acolyte")
	var out := GymSpawns.spawn(one, Vector3.ZERO, 1, null, null)
	check(out.size() == 1 and out[0] is Acolyte, "spawns an acolyte")
	var e := GymSpawns.find("monster:acolyte:procession")
	if not check(not e.is_empty(), "the gym's Procession"):
		return
	var made := GymSpawns.spawn(e, Hex.to_world(Vector2i(2, 2)), 1, null, null)
	check(made.size() == 7 and made[0] is Procession, "a procession and its six members")
	var pr := made[0] as Procession
	var lead_at := pr.leader().global_position
	await frames(300)
	check(GameWorld.flat_distance(pr.leader().global_position, lead_at) > 2.0, "it walks its loop")
	check(map != null, "")
