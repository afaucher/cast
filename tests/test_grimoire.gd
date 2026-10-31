extends MonsterTestBase
## The grimoire (docs/design/haunted-build-plan.md, "H6 as built"): a haunted contract's source on its last floor, a hellgate in
## shape. It spawns on a haunted last floor only (never on floors 1-2 or a hellgate floor), dormant (the shut book, the eye
## alive); a hero near wakes it (the book opens) and it bursts the dead family round it, up to its cap; its phases (weakened,
## failing) come by HP with the blast, which stands the near unburnt zombie bodies back up; hit to 0 it is SLAMMED SHUT (the
## eye dead, every light out, the shut book stays) and stops its spawns; on fire it burns hard (a fireball always lights it)
## and closing burning BURNS it; it pays the grimoire line once, and the haunted invoice adds up. The gym's "Grimoire".

var _closed := 0
var _burnt := 0


func _book(cell: Vector2i, opts: Dictionary) -> Grimoire:
	var g := Grimoire.place(cell, opts)
	g.set_physics_process(false)   # (the test drives the spawner with step())
	g.fx_enabled = false
	return g


func _run(g: Grimoire, seconds: float, kill: bool) -> void:
	for _i in int(seconds * 30.0):
		g.step(1.0 / 30.0)
		if kill:
			for m in g.living_spawns():
				m.free()


func setup() -> void:
	timeout_sec = 200.0
	Monster.use_proto_visuals = true
	_t_floors()
	_t_dormant_and_wake()
	_t_bursts()
	await _t_phases()
	await _t_slam_shut()
	await _t_burn()
	_t_invoice()
	_t_gym()
	Monster.use_proto_visuals = false
	finish()


## Only a haunted contract's last floor has one, in the story's room; floors 1-2 and a hellgate floor never do.
func _t_floors() -> void:
	for pair: Array in [["heir", 3], ["parish", 11]]:
		for f in range(1, ContractRun.FLOOR_COUNT + 1):
			var run := ContractBoard.run_for_client(str(pair[0]), int(pair[1]))
			var b := _build(run, f)
			var site: SiteBuilder.Site = b["site"]
			var plan: SitePlan = b["plan"]
			var tag := "%s/%d floor %d" % [pair[0], pair[1], f]
			if f < ContractRun.FLOOR_COUNT:
				check(site.grimoire == null and plan.grimoire.is_empty(), "%s: no grimoire" % tag)
				continue
			if not check(site.grimoire != null, "%s: the grimoire" % tag):
				continue
			eq(str(plan.grimoire["room"]), plan.origin_room, "%s: in the story's room" % tag)
			check(site.gates.is_empty() and site.origin_gate == null, "%s: and no hellgate" % tag)
			check(Hellgate.open_gates().has(site.grimoire) and site.grimoire.is_origin(), "%s: a gate in shape (the floor's source)" % tag)
			near(site.grimoire.max_hp, float(Grimoire.book_profile(run.difficulty, 3)["hp"]), 0.01, "%s: its HP from its table" % tag)
			check(site.grimoire.depth == 3 and is_equal_approx(site.grimoire.difficulty, run.difficulty), "%s: the contract's difficulty, the last floor's depth" % tag)
	var gate_run := ContractBoard.run_for_seed(3)
	var g := _build(gate_run, ContractRun.FLOOR_COUNT)
	check((g["site"] as SiteBuilder.Site).grimoire == null and (g["plan"] as SitePlan).grimoire.is_empty(), "a hellgate floor 3 has no grimoire")
	check((g["site"] as SiteBuilder.Site).origin_gate != null and not ((g["site"] as SiteBuilder.Site).origin_gate is Grimoire), "... its origin gate instead")


func _build(run: ContractRun, f: int) -> Dictionary:
	var map := DungeonGen.for_run(run, f)
	new_world(map)
	GameWorld.begin(map, world, run.floor_seed(f))
	var plan := SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
	var site := SiteBuilder.spawn(map, run, plan)
	return {"map": map, "plan": plan, "site": site}


## Dormant: the shut book, the live eye, no spawns however long; a hero near wakes it and the book opens.
func _t_dormant_and_wake() -> void:
	new_world(flat_map(24))
	var g := _book(Vector2i(0, 0), {"difficulty": 0.5, "depth": 3})
	eq(g.display_name, "Grimoire", "its name")
	check(g is Hellgate and g.is_origin() and g.team == GameWorld.TEAM_MONSTERS, "a hellgate in shape: the floor's source, on the monsters' side")
	near(g.shove_mult, 0.0, 0.0001, "immovable")
	near(g.max_hp, float(Grimoire.book_profile(0.5, 3)["hp"]), 0.01, "HP from its table")
	check(Grimoire.book_profile(1.0, 3)["hp"] > Grimoire.book_profile(0.0, 1)["hp"], "tougher on a harder, deeper job")
	check(float(Grimoire.book_profile(1.0, 3)["rate"]) > float(Grimoire.book_profile(0.0, 1)["rate"]), "faster on a harder, deeper job")
	check(g.book != null and g.book.state == "dormant" and g.book.is_shut(), "dormant: the book shut")
	var iris := g.book.find_child("Iris", true, false) as Node3D
	check(iris != null and iris.visible, "the live eye on its cover")
	check(g.book.find_child("Column", true, false) == null and g.book.find_child("BookLight", true, false) != null, "no column yet; the candles and a dim light")
	var far := add_hero(Vector2i(16, 0))
	_run(g, 60.0, false)
	check(not g.is_active() and g.spawned_total == 0, "asleep with the crew far off: no spawns")
	far.global_position = g.global_position + Vector3(6.0, 0.0, 0.0)
	_run(g, 0.5, false)
	check(g.is_active(), "a hero near wakes it")
	eq(g.book.state, "open", "the book flies open")
	check(g.book.find_child("Column", true, false) != null, "the column of light up")
	# a hit wakes one too
	var g2 := _book(Vector2i(-10, 6), {"difficulty": 0.5, "depth": 3})
	far.global_position = Hex.to_world(Vector2i(16, 0))
	g2.apply_damage(5.0, far)
	check(g2.is_active() and g2.book.state == "open", "a hit wakes it")


## Bursts: the pages flare first, then the dead family rises in its ring, aggroed; it holds at its cap.
func _t_bursts() -> void:
	new_world(flat_map(24))
	var g := _book(Vector2i(0, 0), {"difficulty": 0.6, "depth": 3})
	var hero := add_hero(Vector2i(5, 0))
	_run(g, 0.3, false)
	check(g.is_active(), "awake")
	var saw_flare := false
	var first: Array = []
	for _i in int(20.0 * 30.0):
		g.step(1.0 / 30.0)
		if g.is_telegraphing():
			g._process(0.0)
			saw_flare = saw_flare or g.book._flare > 0.0
		if g.spawned_total > 0:
			first = g.living_spawns()
			break
	check(saw_flare, "the pages flare before the burst")
	check(not first.is_empty(), "a burst came")
	for m: Monster in first:
		check(Grimoire.KIND_WEIGHTS[0].has(m.kind), "the dead family rises (%s)" % m.kind)
		var d := Hex.distance(m.current_cell(), g.current_cell())
		check(d >= Hellgate.RING_MIN_ORIGIN and d <= Hellgate.RING_MAX_ORIGIN, "in its ring (%d)" % d)
		check(m.get_meta("from_gate", null) == g, "from the grimoire (world.spawn's gate)")
		check(m.state != Monster.State.IDLE or m.target == hero, "aggroed toward the crew")
	eq(first.size(), int(Grimoire.book_profile(0.6, 3)["burst"]), "the burst's size")
	_run(g, 120.0, false)
	check(g.living_spawn_count() <= g.spawn_cap and g.living_spawn_count() >= int(Grimoire.book_profile(0.6, 3)["burst"]), "it holds at its cap (%d of %d)" % [g.living_spawn_count(), g.spawn_cap])
	_run(g, 200.0, true)
	check(g.spawned_total > 20, "keeps pulsing them out (%d)" % g.spawned_total)


## Phases by HP: weakened, failing, each faster with bigger bursts; each change blasts the crew back and stands the near
## unburnt zombie bodies back up (a burnt one stays down).
func _t_phases() -> void:
	new_world(flat_map(26))
	var g := _book(Vector2i(0, 0), {"difficulty": 0.5, "depth": 3})
	var hero := add_hero(Vector2i(3, 0))
	hero.global_position = g.global_position + Vector3(3.2, 0, 0)
	_run(g, 0.3, false)
	var i0 := g.spawn_interval
	var b0 := g.burst_size
	# two bodies near it (one burnt) and one far off
	var bodies: Array[Zombie] = []
	for c: Vector2i in [Vector2i(-4, 2), Vector2i(-3, -3), Vector2i(-16, 4)]:
		var z := MonsterFactory.spawn("zombie", c) as Zombie
		z.set_physics_process(false)
		z.apply_damage(z.hp + 1.0, hero)
		bodies.append(z)
	await frames(2)
	bodies[1].burn_body(hero)
	check(bodies[0].is_downed() and bodies[1].burnt and bodies[2].is_downed(), "two bodies down near it (one burnt), one far off")
	var hero_d0 := GameWorld.flat_distance(hero.global_position, g.global_position)
	g.apply_damage(g.max_hp * 0.4, hero)
	eq(g.phase, 1, "phase 1 at 60 %")
	eq(g.book.state, "weakened", "the book weakened (the column thins, candles out)")
	check(g.spawn_interval < i0 and g.burst_size >= b0, "faster, bursts as big or bigger")
	check(g._shove_t > 0.0, "the blast winds up")
	_run(g, Hellgate.SHOVE_WINDUP + 0.1, false)
	await frames(40)
	check(GameWorld.flat_distance(hero.global_position, g.global_position) > hero_d0 + 1.0, "the blast throws the crew back (%.1f -> %.1f)" % [hero_d0, GameWorld.flat_distance(hero.global_position, g.global_position)])
	check(not bodies[0].dead, "the near body stands back up")
	near(bodies[0].hp, bodies[0].max_hp, 0.01, "... at full HP")
	check(bodies[1].dead and bodies[2].dead, "the burnt one and the far one stay down")
	eq(g.raised_total, 1, "one raised")
	g.apply_damage(g.max_hp * 0.3, hero)
	eq(g.phase, 2, "phase 2 at 30 %")
	eq(g.book.state, "failing", "the book failing (the flicker tends red)")
	check(Grimoire.KIND_WEIGHTS[2].has("crypt_rat"), "the last phase adds crypt rats")
	check(g.spawn_interval < i0 * 0.7, "faster still")


## Hit to 0: slammed shut (once), the eye dead, every light out; its spawns stop; the shut book stays on its altar.
func _t_slam_shut() -> void:
	new_world(flat_map(20))
	HellgateEvents.reset()
	_closed = 0
	var g := _book(Vector2i(0, 0), {"difficulty": 0.5, "depth": 3, "max_hp": 90.0})
	g.closed.connect(func(_x: Actor) -> void: _closed += 1)
	var hero := add_hero(Vector2i(3, 0))
	hero.global_position = g.global_position + Vector3(2.6, 0, 0)
	_run(g, 0.3, false)
	g.spawn_burst_now()
	var before := g.spawned_total
	var swings := 0
	while not g.dead and swings < 30:
		Combat.melee_arc(hero, Vector3.LEFT, 2.5, 120.0, 20.0)
		swings += 1
	check(g.dead and g.is_closed(), "hero hits close it (%d swings)" % swings)
	eq(_closed, 1, "closed once")
	check(not g.burnt, "slammed shut, not burned")
	check(g.book.state == "shut" and g.book.dead_eye and not g.book.burnt, "the book shut, the eye dead")
	var iris := g.book.find_child("Iris", true, false) as Node3D
	check(iris != null and not iris.visible, "no iris: the dead eye")
	check(g.book.find_child("BookLight", true, false) == null and g.book.find_child("Column", true, false) == null, "every light out")
	check(HellgateEvents.spawns_are_stopped(), "its spawns stop (as the origin gate's)")
	g.step(60.0)
	eq(g.spawned_total, before, "no burst after it shut")
	check(not GameWorld.actors().has(g) and not Hellgate.open_gates().has(g), "off the target lists")
	g.die()
	eq(_closed, 1, "still once")
	await frames(int((Hellgate.CLOSE_TIME + 0.6) * 60.0))
	check(is_instance_valid(g) and g.is_inside_tree(), "the shut book stays on its altar")
	check(g.get_node_or_null("Altar") is DecorBlocker, "its altar still blocks the way")
	HellgateEvents.reset()


## Fire: a fireball always lights it, its fire burns hard, Damp puts it out; closing on fire BURNS it (charred, smoking).
func _t_burn() -> void:
	new_world(flat_map(20))
	_burnt = 0
	var g := _book(Vector2i(0, 0), {"difficulty": 0.5, "depth": 3})
	g.burnt_down.connect(func() -> void: _burnt += 1)
	var hero := add_hero(Vector2i(4, 0))
	check(Burning.can_burn(g), "its pages can burn")
	var gate := Hellgate.spawn(Vector2i(8, 8), {"difficulty": 0.5})
	gate.set_physics_process(false)
	check(not Burning.can_burn(gate) and Burning.ignite(gate, hero, 5.0) == null, "a hellgate still never burns")
	Grimoire.fire_at(g.global_position + Vector3(1.0, 0, 0), 1.0, hero)
	check(Burning.is_burning(g), "a fireball over it always lights it")
	near(Burning.remaining(g), Grimoire.FIRE_SECONDS, 0.1, "for a full fire")
	var hp0 := g.hp
	await frames(62)
	var burnt_hp := hp0 - g.hp
	check(burnt_hp >= Burning.TICK_DAMAGE * 2.0 * Grimoire.BURN_MULT * 0.6, "it burns hard (%.1f HP in a second)" % burnt_hp)
	check(Burning.extinguish(g) and not Burning.is_burning(g), "Damp (a soak) puts it out")
	await frames(3)   # (the old fire's node goes before a new one is lit)
	# a fire finishes it: burned
	Burning.ignite(g, hero, Grimoire.FIRE_SECONDS)
	g.apply_damage(g.hp - 5.0, hero)
	check(await wait_until(func() -> bool: return g.dead, 120), "the fire finishes it")
	check(g.burnt, "closed on fire: burned")
	eq(_burnt, 1, "burnt_down once (online: world.burn after its world.die)")
	check(g.book.burnt and g.book.state == "shut" and g.book.find_child("Smoke", true, false) != null, "the book charred and smoking")
	# a copy is told (world.burn): net_burn chars a slammed one
	var g2 := _book(Vector2i(-8, 4), {"difficulty": 0.5, "depth": 3, "max_hp": 10.0})
	g2.apply_damage(20.0, hero)
	check(g2.dead and not g2.burnt and not g2.book.burnt, "slammed shut")
	g2.net_burn()
	check(g2.burnt and g2.book.burnt, "world.burn chars it")
	# a late joiner's rows (NetWorld.book_states / apply_books): every closed grimoire and whether it burned
	var g3 := _book(Vector2i(8, -6), {"difficulty": 0.5, "depth": 3})
	var g4 := _book(Vector2i(-8, -6), {"difficulty": 0.5, "depth": 3, "max_hp": 10.0})
	g4.apply_damage(20.0, hero)
	NetRegistry.clear()
	NetRegistry.register(150, g)
	NetRegistry.register(151, g4)
	NetRegistry.register(152, g3)
	eq(Session.world.book_states(), [[150, true], [151, false]], "the host's rows: the closed ones, burned or not")
	Session.world.apply_books([[152, true]])
	check(g3.dead and g3.burnt and g3.book.burnt and g3.book.state == "shut", "the joiner's copy: shut and charred")
	NetRegistry.clear()


## The haunted invoice: acolytes on floors 1-2, the grimoire on floor 3 (paid once, as the origin gate), the pest at the
## standard rate; floor 3's pest pays only once the grimoire is shut; everything adds up to the contract value.
func _t_invoice() -> void:
	for id: String in ClientArchetype.HAUNTED_IDS:
		for s in [3, 11, 42]:
			var run := ContractRun.make(id, s, float(s % 10) / 10.0 + 0.05)
			var tag := "%s/%d" % [id, s]
			eq(run.grimoire_pay, run.origin_pay, "%s: the grimoire pays what an origin gate would (%d)" % [tag, run.grimoire_pay])
			var want := run.total_acolytes() * run.acolyte_pay + run.grimoire_pay + run.pest_pay + run.total_employees() * ContractRun.EMPLOYEE_EXTRACTED
			eq(run.contract_value, want, "%s: the contract value is acolytes + grimoire + pest + staff" % tag)
			var sess := ContractSession.begin(run, 1)
			for f in range(1, ContractRun.FLOOR_COUNT + 1):
				sess.enter_floor(f, 0, false, run.floor_employees[f - 1], 6, run.acolytes_on(f), f == ContractRun.FLOOR_COUNT)
				for _i in run.acolytes_on(f) + 1:
					sess.acolyte_stopped()
				if f == ContractRun.FLOOR_COUNT:
					eq(sess.gates_open(), 1, "%s: the open grimoire keeps floor 3 open" % tag)
					eq(sess.check_clean(0), 0, "%s: no pest pay while the grimoire is open" % tag)
					eq(sess.grimoire_closed("burned"), run.grimoire_pay, "%s: the grimoire pays" % tag)
					eq(sess.grimoire_closed("shut"), 0, "%s: once" % tag)
					eq(str(sess.state()["grimoire_closed"]), "burned", "%s: it went up in flames" % tag)
					eq(Ledger.lines.filter(func(l: Dictionary) -> bool: return str(l["label"]) == "Grimoire burned").size(), 1, "%s: the Ledger's line" % tag)
					check(DamageTicker.shows_earning(Ledger.lines.filter(func(l: Dictionary) -> bool: return str(l["label"]) == "Grimoire burned")[0]), "%s: it rides the ticker" % tag)
				else:
					eq(sess.grimoire_closed("shut"), 0, "%s floor %d: no grimoire to pay" % [tag, f])
				eq(sess.check_clean(0), int(run.pest_floor_pay[f - 1]), "%s floor %d: the pest pays" % [tag, f])
				sess.extract(run.floor_employees[f - 1])
			eq(Ledger.payout(), run.contract_value, "%s: every objective met, every employee out: the contract value" % tag)
			sess.finish(ContractSession.END_CASHED_OUT)
	var gate_run := ContractRun.make("prepper", 3, 0.5)
	var gs := ContractSession.begin(gate_run, 3)
	gs.enter_floor(3, 0, true, 2, 5)
	eq(gs.grimoire_closed("shut"), 0, "a hellgate floor has no grimoire to pay")
	eq(gs.gates_open(), 1, "... its origin gate is its source")
	gs.finish(ContractSession.END_CASHED_OUT)
	eq(ContractSession.GRIMOIRE_LINES["shut"], "Grimoire slammed shut", "the slam's Ledger line")


func _t_gym() -> void:
	new_world(flat_map(12))
	var e := GymSpawns.find("gate:grimoire")
	check(not e.is_empty() and str(e["label"]) == "Grimoire" and str(e["skip"]) == "", "the gym's Gate group has the Grimoire")
	var out := GymSpawns.spawn(e, Vector3.ZERO, 1, null, null)
	check(out.size() == 1 and out[0] is Grimoire and (out[0] as Grimoire).book.state == "dormant", "it spawns dormant")
