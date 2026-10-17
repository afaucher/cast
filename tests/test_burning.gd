extends TestCase
## Burning (scripts/spells/burning.gd): a fireball blast gives everyone near it a chance to catch fire; the fire
## burns 5-10 s for mild damage over time, refreshes without stacking, never spreads, ends on death or
## extinguish, and respects fireproof / soaked actors.

var root: Node3D


func _init() -> void:
	timeout_sec = 240.0   # the burns are played out in real game time (about 90 s of physics frames, run headless in seconds)


func _flat_map(radius: int = 9) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 0)
	return m


func _fresh(seed_value: int = 5) -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(_flat_map(), root, seed_value)
	Ledger.begin_contract(1000000)


func _hero(pos: Vector3, hero_name: String = "Wick") -> Hero:
	var h := Hero.new()
	h.display_name = hero_name
	GameWorld.spawn(h, pos)
	h.snap_to_ground()
	return h


func _dummy(pos: Vector3, hp: float = 1000.0) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.max_hp = hp
	GameWorld.spawn(d, pos)
	d.snap_to_ground()
	return d


func setup() -> void:
	# --- The chance formula: 35% at the centre of a full-power blast, less at the rim and at low power.
	near(Burning.ignite_chance(1.0, 0.0), 0.35, 0.0001, "35% at the centre of a full-power fireball")
	near(Burning.ignite_chance(1.0, 1.0), 0.35 * Burning.EDGE_CHANCE_MULT, 0.0001, "less at the rim")
	check(Burning.ignite_chance(0.2, 0.0) < Burning.ignite_chance(1.0, 0.0), "less for a weak cast")
	check(Burning.ignite_chance(0.0, 0.0) > 0.1 and Burning.ignite_chance(1.0, 0.0) <= 0.35, "bounded")

	# --- Durations always land in 5-10 s.
	_fresh(11)
	var lo := 99.0
	var hi := 0.0
	for i in 300:
		var d := Burning.roll_duration()
		lo = minf(lo, d)
		hi = maxf(hi, d)
	check(lo >= 5.0 and hi <= 10.0, "rolled durations stay in 5-10 s (%.2f..%.2f)" % [lo, hi])
	check(hi - lo > 3.0, "and they vary")

	# --- The ignite rate over many actors, with a seeded rng, matches the formula.
	_fresh(1234)
	var crowd: Array[Actor] = []
	for i in 300:
		crowd.append(_dummy(Vector3(cos(float(i)) * 0.3, 0, sin(float(i)) * 0.3)))
	var radius := SpellBook.fireball_radius(1.0)
	var expected := 0.0
	for a in crowd:
		expected += Burning.ignite_chance(1.0, GameWorld.flat_distance(a.global_position, Vector3.ZERO) / radius)
	var caught := Burning.on_blast(Vector3.ZERO, radius, 1.0, null)
	var rate := float(caught.size()) / float(crowd.size())
	near(rate, expected / float(crowd.size()), 0.08, "ignite rate %.3f is near the formula %.3f" % [rate, expected / float(crowd.size())])
	check(rate > 0.2 and rate < 0.5, "about a third of a crowd ignites (%.3f)" % rate)
	var in_range := true
	for a in caught:
		var r := Burning.remaining(a)
		in_range = in_range and r > 4.9 and r <= 10.0
	check(in_range, "every new fire has 5-10 s on the clock")

	# The same seed gives the same fires.
	_fresh(1234)
	var crowd2: Array[Actor] = []
	for i in 300:
		crowd2.append(_dummy(Vector3(cos(float(i)) * 0.3, 0, sin(float(i)) * 0.3)))
	eq(Burning.on_blast(Vector3.ZERO, radius, 1.0, null).size(), caught.size(), "a seeded run is repeatable")

	# --- A real fireball: friendly fire (a hero next to the target can burn), the caster is credited.
	_fresh(77)
	var caster := _hero(Vector3(-6, 0, 0), "Wick")
	var pack: Array[Actor] = []
	for i in 40:
		pack.append(_dummy(Vector3(2.0 + 0.04 * float(i % 8), 0, -1.0 + 0.1 * float(i / 8))))
	SpellBook.cast("fireball", caster, 1.0, Vector3(2.1, 0, -0.8))
	await frames(60 * 2)
	var burning_now := 0
	for a in pack:
		if Burning.is_burning(a):
			burning_now += 1
	check(burning_now >= 4 and burning_now < 36, "a fireball sets some of a crowd on fire, not all (%d / 40)" % burning_now)
	near(caster.hp, caster.max_hp, 0.001, "the caster was never in the blast")

	# Heroes in the blast can ignite (friendly fire); employees too.
	_fresh(3)
	caster = _hero(Vector3(-6, 0, 0), "Wick")
	var buddy_hits := 0
	var workers_hit := 0
	for i in 60:
		var buddy := _hero(Vector3(3.0, 0, 0), "Gasket")
		var worker := Employee.spawn(Hex.from_world(Vector3(3, 0, 0)), {"style": "staff"})
		worker.global_position = Vector3(3.1, worker.global_position.y, 0.1)
		for a in Burning.on_blast(Vector3(3, 0, 0), 2.4, 1.0, caster):
			if a == buddy:
				buddy_hits += 1
			elif a == worker:
				workers_hit += 1
		buddy.free()
		worker.free()
	check(buddy_hits > 5, "a teammate in the blast can catch fire (%d / 60)" % buddy_hits)
	check(workers_hit > 5, "so can an employee (%d / 60)" % workers_hit)

	# --- Damage over time: 15 HP at 5 s, 30 HP at 10 s, credited to the caster.
	_fresh(9)
	caster = _hero(Vector3(-6, 0, 0), "Wick")
	var d5 := _dummy(Vector3(0, 0, 0))
	var d7 := _dummy(Vector3(0, 0, 3))
	var d10 := _dummy(Vector3(0, 0, -3))
	var sources: Array[Node] = []
	d5.damaged.connect(func(_amt: float, src: Node) -> void: sources.append(src))
	check(Burning.ignite(d5, caster, 5.0) != null, "ignite returns the fire")
	Burning.ignite(d7, caster, 7.0)
	Burning.ignite(d10, caster, 10.0)
	await frames(60 * 11)
	var l5 := d5.max_hp - d5.hp
	var l7 := d7.max_hp - d7.hp
	var l10 := d10.max_hp - d10.hp
	near(l5, 15.0, 2.0, "a 5 s fire burns about 15 HP (%.1f)" % l5)
	near(l7, 21.0, 2.0, "a 7 s fire burns about 21 HP (%.1f)" % l7)
	near(l10, 30.0, 2.0, "a 10 s fire burns about 30 HP (%.1f)" % l10)
	check(not Burning.is_burning(d5) and not Burning.is_burning(d10), "and it burns out")
	check(d5.get_node_or_null("Burning") == null, "the status node is gone")
	check(sources.size() > 0 and sources.all(func(s: Node) -> bool: return s == caster), "every tick is credited to the caster")

	# A full burn cannot kill a full-HP hero (Wick, the frailest, has 85).
	_fresh(10)
	caster = _hero(Vector3(-6, 0, 0), "Gasket")
	var wick := _hero(Vector3(0, 0, 0), "Wick")
	Burning.ignite(wick, caster, 10.0)
	await frames(60 * 11)
	check(not wick.dead and wick.hp > wick.max_hp - 32.0, "a 10 s burn leaves a full-HP hero standing (%.1f / %.1f)" % [wick.hp, wick.max_hp])
	# ... and a hero's fire never downs a hero.
	var weak := _hero(Vector3(0, 0, 3), "Rebar")
	weak.hp = 4.0
	Burning.ignite(weak, caster, 10.0)
	await frames(60 * 11)
	check(not weak.dead and weak.hp >= 1.0 - 0.001, "a teammate's fire stops at 1 HP (%.2f)" % weak.hp)

	# Rebar is immovable (shove_mult 0) but still flammable: only gates, props and packages are exempt.
	var rebar_hero := HeroFactory.spawn_hero(Vector2i(0, 5), "Rebar", Color(0.85, 0.5, 0.25), "sword", null, HeroKit.REBAR)
	near(rebar_hero.shove_mult, 0.0, 0.0001, "Rebar cannot be shoved")
	check(Burning.ignite(rebar_hero, caster, 5.0) != null, "but he can burn")

	# --- Refresh, never stack.
	_fresh(12)
	caster = _hero(Vector3(-6, 0, 0), "Wick")
	var r := _dummy(Vector3(0, 0, 0))
	var first := Burning.ignite(r, caster, 5.0)
	await frames(60 * 2)
	near(Burning.remaining(r), 3.0, 0.1, "2 s into a 5 s fire: 3 s left")
	var second := Burning.ignite(r, caster, 2.0)
	eq(second, first, "re-igniting returns the same fire")
	near(Burning.remaining(r), 3.0, 0.1, "a shorter new fire does not shorten the burn")
	Burning.ignite(r, caster, 8.0)
	near(Burning.remaining(r), 8.0, 0.1, "a longer one extends it to the new length")
	var burners := 0
	for c in r.get_children():
		if c is Burning:
			burners += 1
	eq(burners, 1, "only one fire node")
	# damage rate is that of a single fire even when ignited three times at once
	var s1 := _dummy(Vector3(0, 0, 4))
	var s2 := _dummy(Vector3(0, 0, -4))
	Burning.ignite(s1, caster, 6.0)
	for i in 3:
		Burning.ignite(s2, caster, 6.0)
	await frames(60 * 3)
	near(s2.hp, s1.hp, 0.01, "three ignitions burn no faster than one")
	near(s1.max_hp - s1.hp, 9.0, 1.6, "3 s of one fire is about 9 HP (%.1f)" % (s1.max_hp - s1.hp))

	# --- No spread: a burning actor next to others sets nothing else alight.
	_fresh(13)
	caster = _hero(Vector3(-6, 0, 0), "Wick")
	var torch := _dummy(Vector3(0, 0, 0))
	var next_to := _dummy(Vector3(0.6, 0, 0))
	var near_hero := _hero(Vector3(-0.6, 0, 0.4), "Gasket")
	Burning.ignite(torch, caster, 8.0)
	await frames(60 * 8)
	check(not Burning.is_burning(next_to) and not Burning.is_burning(near_hero), "fire does not spread to neighbours")
	near(next_to.hp, next_to.max_hp, 0.001, "the neighbour took nothing")
	near(near_hero.hp, near_hero.max_hp, 0.001, "nor did the hero beside it")

	# --- Extinguish, and the ended signal.
	_fresh(14)
	caster = _hero(Vector3(-6, 0, 0), "Wick")
	var wet := _dummy(Vector3(0, 0, 0))
	var also := _dummy(Vector3(1.0, 0, 0))
	var far_one := _dummy(Vector3(6.0, 0, 0))
	var reasons: Array[String] = []
	var fire := Burning.ignite(wet, caster, 8.0)
	fire.ended.connect(func(why: String) -> void: reasons.append(why))
	Burning.ignite(also, caster, 8.0)
	Burning.ignite(far_one, caster, 8.0)
	check(Burning.is_burning(wet), "burning")
	check(Burning.extinguish(wet), "extinguish reports it was burning")
	check(not Burning.is_burning(wet), "no longer burning, at once")
	check(not Burning.extinguish(wet), "extinguishing a cool actor does nothing")
	eq(reasons, ["extinguished"] as Array[String], "ended(extinguished)")
	var hp_out := wet.hp
	await frames(60 * 3)
	near(wet.hp, hp_out, 0.0001, "an extinguished actor takes no more damage")
	eq(Burning.extinguish_in_radius(Vector3.ZERO, 3.0), 1, "an area extinguish puts out what is inside it")
	check(not Burning.is_burning(also) and Burning.is_burning(far_one), "and leaves what is outside")
	# Heal does not put it out.
	wick = _hero(Vector3(0, 0, 4), "Wick")
	wick.hp = 50.0
	Burning.ignite(wick, caster, 8.0)
	wick.heal(10.0)
	check(Burning.is_burning(wick), "healing does not extinguish")
	check(get_tree().get_nodes_in_group("burning").size() >= 2, "live fires are in the group 'burning'")

	# --- Fireproof and soaked actors do not ignite; a fire dies when the actor turns fireproof.
	_fresh(15)
	caster = _hero(Vector3(-6, 0, 0), "Wick")
	var proof := _dummy(Vector3(0, 0, 0))
	Burning.set_fireproof(proof, true)
	check(Burning.is_fireproof(proof), "fireproof")
	check(Burning.ignite(proof, caster, 8.0) == null and not Burning.is_burning(proof), "fireproof actors do not ignite")
	var crowd3: Array[Actor] = []
	for i in 80:
		crowd3.append(_dummy(Vector3(cos(float(i)) * 0.3, 0, sin(float(i)) * 0.3)))
		Burning.set_fireproof(crowd3[i], true)
	eq(Burning.on_blast(Vector3.ZERO, 2.4, 1.0, caster).size(), 0, "a fireproof crowd never catches in a blast")
	Burning.set_fireproof(proof, false)
	check(Burning.ignite(proof, caster, 8.0) != null, "and can burn again once it is not fireproof")
	var damp := _dummy(Vector3(3, 0, 0))
	Burning.ignite(damp, caster, 8.0)
	Burning.soak(damp, 4.0)
	check(not Burning.is_burning(damp), "soaking puts the fire out")
	check(Burning.ignite(damp, caster, 8.0) == null, "and keeps it from catching again")
	await frames(60 * 5)
	check(Burning.ignite(damp, caster, 8.0) != null, "until it dries")
	var other_proof := _dummy(Vector3(3, 0, 3))
	Burning.ignite(other_proof, caster, 8.0)
	other_proof.add_to_group("fireproof")
	await frames(3)
	check(not Burning.is_burning(other_proof), "an actor that turns fireproof stops burning")

	# --- Things that never burn: hellgates, priced props, a dead actor.
	_fresh(16)
	caster = _hero(Vector3(-6, 0, 0), "Wick")
	var gate := Hellgate.spawn(Vector2i(3, 0), {})
	var prop := PricedProp.spawn(Vector2i(0, 3), "wine_rack")
	check(gate != null and prop != null, "gate and prop exist")
	if gate != null:
		check(Burning.ignite(gate, caster, 8.0) == null, "a hellgate does not burn")
	if prop != null:
		check(Burning.ignite(prop, caster, 8.0) == null, "a priced prop does not burn")
	var hurt_gate_hp := gate.hp if gate != null else 0.0
	Burning.on_blast(Vector3.ZERO, 12.0, 1.0, caster)
	if gate != null:
		near(gate.hp, hurt_gate_hp, 0.0001, "and a blast never burns it")
	var worker2 := Employee.spawn(Hex.from_world(Vector3(0, 0, -3)), {"style": "staff"})
	check(Burning.ignite(worker2, caster, 8.0) != null, "an employee can burn")

	# --- Death stops it. A burning swarmer burns to death, credited to the caster.
	_fresh(17)
	caster = _hero(Vector3(-6, 0, 0), "Wick")
	var swarmer := MonsterFactory.spawn("swarmer", Vector2i(2, 2))
	swarmer.global_position = Vector3(0, swarmer.global_position.y, 6)
	var killed_by: Array[Node] = []
	swarmer.damaged.connect(func(_amt: float, src: Node) -> void: killed_by.append(src))
	var f2 := Burning.ignite(swarmer, caster, 10.0)
	var why: Array[String] = []
	f2.ended.connect(func(w: String) -> void: why.append(w))
	await frames(60 * 12)
	check(not is_instance_valid(swarmer) or swarmer.dead,"a 12 HP swarmer burns to death")
	eq(why, ["died"] as Array[String], "the fire ends with 'died'")
	check(killed_by.size() > 0 and killed_by[killed_by.size() - 1] == caster, "kill credit goes to the caster")
	# A target killed by something else stops burning at once.
	var other := _dummy(Vector3(0, 0, -6))
	Burning.ignite(other, caster, 10.0)
	other.apply_damage(5000.0, caster)
	check(other.dead and not Burning.is_burning(other), "a dead target is not burning")
	check(Burning.ignite(other, caster, 5.0) == null, "and cannot be set alight")
	# A downed hero stops burning (and stays down).
	var downed := _hero(Vector3(3, 0, 0), "Rebar")
	Burning.ignite(downed, caster, 10.0)
	downed.apply_damage(5000.0, null)
	await frames(3)
	check(downed.dead and not Burning.is_burning(downed), "a downed hero is not burning")
	check(Burning.ignite(downed, caster, 5.0) == null, "and a downed hero does not ignite")

	# --- Flames are cheap: a burning actor owns a handful of meshes and one light.
	_fresh(18)
	caster = _hero(Vector3(-6, 0, 0), "Wick")
	var visual := _dummy(Vector3(0, 0, 0))
	var fx_fire := Burning.ignite(visual, caster, 5.0)
	var meshes := 0
	var lights := 0
	for c in fx_fire.get_children():
		if c is MeshInstance3D:
			meshes += 1
		elif c is OmniLight3D:
			lights += 1
	check(meshes >= 4 and meshes <= 8 and lights == 1, "a few flames and one light (%d meshes, %d lights)" % [meshes, lights])
	await frames(10)
	finish()
