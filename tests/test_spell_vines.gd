extends TestCase
## Vines: after a short telegraph, thorny vines root EVERYONE in the radius (heroes, the caster, monsters,
## employees) for about two seconds. A rooted actor cannot walk and cannot be shoved by anything (tentacles, the
## bowl, the spin, a melee nudge, a teeth pop, a brute slam, a shove into a priced prop), but it can still attack
## and cast. No damage. Friendly fire is the point (root a fleeing friend next to a teeth carrier).

var root: Node3D


func _flat_map(radius: int = 10) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 0)
	return m


func _fresh() -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(_flat_map(), root, 5)
	Ledger.begin_contract(1000000)


func _hero(pos: Vector3, secondary: String = "bolt") -> Hero:
	var h := Hero.new()
	h.secondary_kind = secondary
	GameWorld.spawn(h, pos)
	h.snap_to_ground()
	return h


func _dummy(pos: Vector3, hp: float = 1000.0) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.max_hp = hp
	GameWorld.spawn(d, pos)
	d.snap_to_ground()
	return d


func _dist(a: Node3D, p: Vector3) -> float:
	return GameWorld.flat_distance(a.global_position, p)


func setup() -> void:
	_numbers()
	await _area_and_duration()
	await _rooted_cannot_move_but_can_act()
	await _no_shove_source_moves_a_rooted_actor()
	await _friendly_fire_and_teeth_combo()
	await _scheduled_effect_and_visuals()
	finish()


# --- The spell's data ----------------------------------------------------------------------------

func _numbers() -> void:
	check(SpellBook.SPELLS.has("vines") and SpellBook.is_available("vines"), "vines exists and is castable")
	eq(SpellBook.spell_name("vines"), "Vines")
	eq(SpellBook.incantation("vines"), "CAST VINES")
	eq(SpellBook.component_name("vines"), "Seed pod")
	near(SpellBook.cooldown_of("vines"), 10.0, 0.001, "cooldown 10 s")
	check(SpellBook.color_of("vines").g > 0.7 and SpellBook.color_of("vines").b < 0.4, "leaf green")
	check(SpellBook.find_in_text("cast vines") == "vines", "text lookup")
	near(SpellBook.vines_radius(1.0), 3.0, 0.001, "radius 2.4 + 0.6 * power")
	near(SpellBook.vines_duration(1.0), 2.2, 0.001, "root 1.6 + 0.6 * power: about two seconds")
	check(SpellBook.vines_radius(0.2) < SpellBook.vines_radius(0.6) and SpellBook.vines_radius(0.6) < SpellBook.vines_radius(1.0), "radius monotonic")
	check(SpellBook.vines_duration(0.2) < SpellBook.vines_duration(1.0), "duration monotonic")
	check(SpellBook.vines_duration(0.05) >= 1.5 and SpellBook.vines_duration(1.0) <= 2.3, "always about two seconds (%.2f..%.2f)" % [SpellBook.vines_duration(0.05), SpellBook.vines_duration(1.0)])
	var v := Vines.new()
	var f: Dictionary = v.net_fields()
	eq(f["start_time"], Net.SPAWN, "the cast's stamp is a SPAWN parameter")
	eq(f["power"], Net.SPAWN, "params are SPAWN")
	v.free()


# --- Who is rooted, and for how long ---------------------------------------------------------------

func _area_and_duration() -> void:
	_fresh()
	var center := Vector3.ZERO
	var caster := _hero(Vector3(-7, 0, 0))
	var friend := _hero(Vector3(1.4, 0, 0))
	var mon := _dummy(Vector3(-1.0, 0, 1.0))
	var worker := Employee.spawn(Hex.from_world(Vector3(0, 0, -1.8)), {"style": "staff"})
	worker.global_position = Vector3(0.0, worker.global_position.y, -1.8)
	var far_hero := _hero(Vector3(-5, 0, -4))
	var far_mon := _dummy(Vector3(6, 0, -5))
	var inside: Array[Actor] = [friend, mon, worker]
	check(SpellBook.cast("vines", caster, 1.0, center), "vines casts")
	await frames(10)
	for a in inside:
		check(not a.is_rooted(), "nobody is rooted during the telegraph (%s)" % a.display_name)
	await frames(15)   # the telegraph is 0.3 s
	for a in inside:
		check(a.is_rooted() and a.has_modifier("vines"), "%s is rooted" % a.display_name)
		near(a.modifier_left("vines"), SpellBook.vines_duration(1.0), 0.2, "%s is rooted for about 2.2 s" % a.display_name)
	check(not far_hero.is_rooted() and not far_mon.is_rooted() and not caster.is_rooted(), "outside the radius is free (and the caster stood well away)")
	# Everyone is hit regardless of team: a hero, a monster and an employee were all in the list above.
	eq(friend.team, GameWorld.TEAM_HEROES)
	eq(mon.team, GameWorld.TEAM_MONSTERS)
	eq(worker.team, GameWorld.TEAM_NEUTRAL)
	near(friend.hp, friend.max_hp, 0.001, "vines do no damage")
	near(mon.hp, mon.max_hp, 0.001, "to anyone")
	near(worker.hp, worker.max_hp, 0.001, "")
	# The root lets go after about 2.2 s (measured from the burst).
	await frames(60 * 2 - 10)
	check(friend.is_rooted(), "still rooted at about 1.9 s")
	await frames(60)
	check(not friend.is_rooted() and not mon.is_rooted() and not worker.is_rooted(), "free again after the root runs out")
	check(not friend.has_modifier("vines"), "the modifier is gone")
	await frames(60)
	check(not (friend.get_node_or_null("VineWrap") != null), "the leg wrap is gone with it")

	# The aim point can be a teammate: the caster standing inside the area is rooted too (everyone).
	_fresh()
	var me := _hero(Vector3(0.5, 0, 0))
	SpellBook.cast("vines", me, 1.0, me.global_position)
	await frames(25)
	check(me.is_rooted(), "the caster in the area is rooted too")
	# Power scales the radius and the root time.
	_fresh()
	var c2 := _hero(Vector3(-8, 0, 0))
	var near_edge := _dummy(Vector3(3.1, 0, 0))   # inside radius 3.0 (+ its own 0.45) at power 1, outside 2.43 (+ 0.45) at power 0.05
	SpellBook.cast("vines", c2, 0.05, Vector3.ZERO)
	await frames(25)
	check(not near_edge.is_rooted(), "a weak cast has a smaller radius (%.2f)" % SpellBook.vines_radius(0.05))
	SpellBook.cast("vines", c2, 1.0, Vector3.ZERO)
	await frames(25)
	check(near_edge.is_rooted(), "a full-power cast reaches it")
	near(near_edge.modifier_left("vines"), SpellBook.vines_duration(1.0), 0.2, "and holds it 2.2 s")
	# Re-casting refreshes the root; it never stacks into a longer one.
	await frames(60)
	SpellBook.cast("vines", c2, 1.0, Vector3.ZERO)
	await frames(25)
	check(near_edge.modifier_left("vines") <= SpellBook.vines_duration(1.0) + 0.01, "a second cast refreshes, it does not stack")


# --- Rooted: no walking, but attacks and spells still work ----------------------------------------------

func _rooted_cannot_move_but_can_act() -> void:
	_fresh()
	var hero := _hero(Vector3(0, 0, 0))
	var dummy := _dummy(Vector3(1.2, 0, 0))
	hero.set_modifier("vines", 1.0, 30.0, Actor.STAT_ROOT)
	var p0 := hero.global_position
	check(not hero.move(Vector3.RIGHT, 1.0 / 60.0), "a rooted hero cannot walk")
	for i in 30:
		hero.move(Vector3(0, 0, 1), 1.0 / 60.0)
	near(hero.global_position.distance_to(p0), 0.0, 0.0001, "and does not move at all")
	near(hero.effective_speed(), 0.0, 0.0001, "effective speed is zero while rooted")
	check(hero.move_speed > 0.0, "(the base speed is untouched)")
	hero.move(Vector3.LEFT, 1.0 / 60.0)
	check(hero.facing.x < -0.9, "but it can still turn")
	# It can still attack ...
	check(hero.melee(Vector3.RIGHT), "a rooted hero can swing")
	near(dummy.hp, dummy.max_hp - Hero.MELEE_DAMAGE, 0.001, "and the hit lands")
	# ... shoot ...
	await frames(40)
	check(hero.shoot(Vector3.RIGHT), "shoot")
	# ... and cast.
	hero.spell_slots = ["heal", "vines"] as Array[String]
	hero.apply_damage(60.0)
	check(hero.try_cast("heal", 1.0, hero.global_position), "a rooted hero can cast")
	near(hero.hp, hero.max_hp - 60.0 + HealSpell.heal_amount(1.0), 0.5, "the heal landed")
	# A rooted monster cannot chase, but it still strikes what is in reach.
	_fresh()
	var grunt := MonsterFactory.spawn("grunt", Vector2i(0, 0)) as Monster
	var prey := _hero(Vector3(5, 0, 0))
	grunt.aggro(prey)
	grunt.set_modifier("vines", 1.0, 60.0, Actor.STAT_ROOT)
	var g0 := grunt.global_position
	await frames(90)
	near(grunt.global_position.distance_to(g0), 0.0, 0.0001, "a rooted grunt does not chase")
	near(prey.hp, prey.max_hp, 0.001, "and it cannot reach a hero 5 units away")
	prey.global_position = Vector3(1.0, 0, 0)
	await frames(90)
	check(prey.hp < prey.max_hp, "but it still attacks a hero in reach (%.0f / %.0f)" % [prey.hp, prey.max_hp])
	near(grunt.global_position.distance_to(g0), 0.0, 0.0001, "without moving")
	# Roots end: it walks again.
	grunt.clear_modifier("vines")
	prey.global_position = Vector3(8, 0, 0)
	await frames(60)
	check(grunt.global_position.distance_to(g0) > 1.0, "freed, it chases again")


# --- Every shove source does nothing to a rooted actor ----------------------------------------------------

func _no_shove_source_moves_a_rooted_actor() -> void:
	# The verb itself.
	_fresh()
	var a := _dummy(Vector3(0, 0, 0))
	var shoves := [0]
	a.shoved.connect(func(_d: Vector3, _dist: float) -> void: shoves[0] += 1)
	a.set_modifier("vines", 1.0, 30.0, Actor.STAT_ROOT)
	a.shove(Vector3.RIGHT, 4.0, null)
	await frames(40)
	near(a.global_position.x, 0.0, 0.0001, "Actor.shove does nothing to a rooted actor")
	check(not a.is_shoved(), "it never enters a slide")
	eq(shoves[0], 0, "and the shoved signal never fires")
	a.clear_modifier("vines")
	a.shove(Vector3.RIGHT, 3.0, null)
	await frames(40)
	check(a.global_position.x > 2.5, "the same shove works once the root is gone (%.2f)" % a.global_position.x)

	# Tentacles: shoves everyone, but not a rooted actor (monsters still take the damage).
	_fresh()
	var caster := _hero(Vector3(-7, 0, 0))
	var free_mon := _dummy(Vector3(1.5, 0, 0))
	var rooted_mon := _dummy(Vector3(-1.5, 0, 0))
	var rooted_hero := _hero(Vector3(0, 0, 1.6))
	rooted_mon.set_modifier("vines", 1.0, 30.0, Actor.STAT_ROOT)
	rooted_hero.set_modifier("vines", 1.0, 30.0, Actor.STAT_ROOT)
	SpellBook.cast("tentacles", caster, 1.0, Vector3.ZERO)
	await frames(70)
	check(free_mon.global_position.x > 3.0, "tentacles still shove a free actor")
	near(rooted_mon.global_position.x, -1.5, 0.0001, "tentacles do not move a rooted monster")
	near(rooted_hero.global_position.z, 1.6, 0.0001, "or a rooted hero")
	near(rooted_mon.hp, rooted_mon.max_hp - TentaclesSpell.tentacles_damage(1.0), 0.001, "(their damage is not a shove, so it still lands)")

	# The bowl (Rebar) and the spin (Gasket).
	_fresh()
	var rebar := _hero(Vector3(-6, 0, 0), "bowl")
	rebar.shove_mult = 0.0
	var in_path := _dummy(Vector3(-2.0, 0, 0.1))
	in_path.set_modifier("vines", 1.0, 30.0, Actor.STAT_ROOT)
	var bowl_free := _dummy(Vector3(3.0, 0, 0.1))
	check(rebar.shoot(Vector3.RIGHT), "the bowl is thrown")
	await frames(120)
	near(in_path.global_position.x, -2.0, 0.0001, "the bowl does not push a rooted actor")
	near(in_path.global_position.z, 0.1, 0.0001, "")
	check(in_path.hp < in_path.max_hp, "(its damage still lands)")
	check(bowl_free.global_position.distance_to(Vector3(3.0, bowl_free.global_position.y, 0.1)) > 1.0, "the bowl pushes a free actor")
	_fresh()
	var gasket := _hero(Vector3.ZERO, "spin")
	var spin_rooted := _dummy(Vector3(1.4, 0, 0))
	var spin_mate := _hero(Vector3(-1.4, 0, 0))
	var spin_free := _dummy(Vector3(0, 0, 1.4))
	gasket.facing = Vector3.RIGHT
	spin_rooted.set_modifier("vines", 1.0, 30.0, Actor.STAT_ROOT)
	spin_mate.set_modifier("vines", 1.0, 30.0, Actor.STAT_ROOT)
	check(gasket.shoot(Vector3.RIGHT), "the spin")
	await frames(40)
	near(spin_rooted.global_position.x, 1.4, 0.0001, "the spin does not push a rooted monster")
	near(spin_mate.global_position.x, -1.4, 0.0001, "or a rooted teammate")
	check(spin_free.global_position.z > 1.4 + 1.0, "the spin pushes a free one (%.2f)" % spin_free.global_position.z)

	# The melee nudge, a monster's nudge and the brute's slam.
	_fresh()
	var swinger := _hero(Vector3.ZERO)
	var punching_bag := _dummy(Vector3(1.2, 0, 0))
	punching_bag.set_modifier("vines", 1.0, 30.0, Actor.STAT_ROOT)
	check(swinger.melee(Vector3.RIGHT), "melee")
	await frames(30)
	near(punching_bag.global_position.x, 1.2, 0.0001, "a melee hit does not nudge a rooted target")
	near(punching_bag.hp, punching_bag.max_hp - Hero.MELEE_DAMAGE, 0.001, "(it still hurts)")
	_fresh()
	var grunt := MonsterFactory.spawn("grunt", Vector2i.ZERO) as Monster
	var victim := _hero(Vector3(1.0, 0, 0))
	victim.set_modifier("vines", 1.0, 30.0, Actor.STAT_ROOT)
	grunt.aggro_range = 0.0
	grunt.facing = Vector3.RIGHT
	grunt._strike()
	await frames(30)
	near(victim.global_position.x, 1.0, 0.0001, "a monster's melee does not nudge a rooted hero")
	near(victim.hp, victim.max_hp - grunt.attack_damage, 0.001, "(it still hurts)")
	_fresh()
	var brute := MonsterFactory.spawn("brute", Vector2i.ZERO) as Monster
	victim = _hero(Vector3(1.2, 0, 0))
	victim.set_modifier("vines", 1.0, 30.0, Actor.STAT_ROOT)
	brute.aggro_range = 0.0
	brute._strike()
	await frames(30)
	near(victim.global_position.x, 1.2, 0.0001, "the brute's slam does not shove a rooted hero")

	# Combat.shove_radius (hellgates, teeth pops use it) and Combat.melee_arc.
	_fresh()
	var src := _hero(Vector3(-6, 0, 0))
	var r1 := _dummy(Vector3(1.0, 0, 0))
	var r2 := _dummy(Vector3(-1.0, 0, 0))
	r1.set_modifier("vines", 1.0, 30.0, Actor.STAT_ROOT)
	var pushed := Combat.shove_radius(Vector3.ZERO, 3.0, 3.0, src)
	await frames(40)
	near(r1.global_position.x, 1.0, 0.0001, "Combat.shove_radius skips a rooted actor")
	check(r2.global_position.x < -2.5, "and pushes a free one")
	eq(pushed.size(), 2, "(it reports both, the verb decides)")

	# A shove into a priced prop: a rooted actor is not thrown, so the prop takes no shove damage.
	_fresh()
	var shover := _hero(Vector3(-6, 0, 3))
	var thug := _dummy(Vector3(0, 0, 0))
	var prop := PricedProp.spawn(Hex.from_world(Vector3(2.4, 0, 0)), "wine_rack")
	prop.global_position = Vector3(2.4, prop.global_position.y, 0.0)
	var hp0 := prop.hp
	thug.set_modifier("vines", 1.0, 30.0, Actor.STAT_ROOT)
	thug.shove(Vector3.RIGHT, 3.0, shover)
	await frames(50)
	near(prop.hp, hp0, 0.0001, "a rooted actor shoved at a prop does not damage it")
	thug.clear_modifier("vines")
	thug.shove(Vector3.RIGHT, 3.0, shover)
	await frames(50)
	check(prop.hp < hp0, "the control: a free actor does (%.1f -> %.1f)" % [hp0, prop.hp])


# --- Friendly fire, and the teeth combo ---------------------------------------------------------------

func _friendly_fire_and_teeth_combo() -> void:
	_fresh()
	var caster := _hero(Vector3(-7, 0, 0))
	var mate := _hero(Vector3(0.5, 0, 0))
	var other := _hero(Vector3(0, 0, -1.0))
	# Aim at a teammate: the aim snaps onto them and the area is around them.
	SpellBook.cast("vines", caster, 1.0, Vector3(0.9, 0, 0.3))
	await frames(25)
	check(mate.is_rooted() and other.is_rooted(), "vines root teammates (friendly fire is the game)")
	near(mate.hp, mate.max_hp, 0.001, "without hurting them")
	check(not caster.is_rooted(), "the caster, far away, is free")

	# Vines then teeth: nobody escapes the pop, friends included.
	_fresh()
	var c := _hero(Vector3(-7, 0, 0))
	var pack: Array[Actor] = []
	for i in 4:
		pack.append(_dummy(Vector3(cos(float(i) * 1.6) * 1.2, 0, sin(float(i) * 1.6) * 1.2)))
	var runner := _hero(Vector3(0.0, 0, 0.0))
	pack.append(runner)
	var start := {}
	for m in pack:
		start[m] = m.global_position
	SpellBook.cast("vines", c, 1.0, Vector3.ZERO)
	await frames(25)
	SpellBook.cast("teeth", c, 1.0, Vector3.ZERO)
	await frames(15)
	# Carriers try to run: nobody can.
	for m in pack:
		m.move(Vector3.RIGHT, 1.0 / 60.0)
	runner.move(Vector3(0, 0, 1), 1.0 / 60.0)
	for m in pack:
		check(Teeth.is_afflicted(m) or m.hp < m.max_hp, "%s has teeth" % m.display_name)
		near(m.global_position.distance_to(start[m]), 0.0, 0.0001, "%s could not step away from the pop" % m.display_name)
	await frames(100)
	for m in pack:
		check(m.hp < m.max_hp, "%s was popped (%.0f / %.0f)" % [m.display_name, m.hp, m.max_hp])
	# The pops' shove did nothing to rooted actors: they are exactly where they started.
	for m in pack:
		near(m.global_position.distance_to(start[m]), 0.0, 0.0001, "the pop did not shove %s" % m.display_name)
	check(runner.hp >= 1.0, "friendly fire never downs a hero")


# --- It is a scheduled effect, with its look --------------------------------------------------------------

func _scheduled_effect_and_visuals() -> void:
	# A cast that arrives late (its stamp is in the past) runs from the stamp: it bursts at once.
	_fresh()
	var target := _dummy(Vector3(0.5, 0, 0))
	var late := Vines.new()
	late.power = 1.0
	late.start_time = GameWorld.time - Vines.TELEGRAPH - 0.01
	GameWorld.spawn(late, Vector3.ZERO)
	await frames(2)
	check(target.is_rooted(), "a cast stamped in the past bursts on the first frame (every machine runs the same schedule)")
	# The vines and the wrap are built, and everything cleans itself up.
	_fresh()
	var caster := _hero(Vector3(-7, 0, 0))
	var victim := _hero(Vector3(0.5, 0, 0))
	SpellBook.cast("vines", caster, 1.0, victim.global_position)
	await frames(30)
	var fx := _find(root, "VinesFx")
	check(fx != null and fx is VinesFx and (fx as VinesFx).get_child_count() > 10, "the vines are built")
	var wrap := victim.get_node_or_null("VineWrap") as VineWrap
	check(wrap != null and wrap.get_child_count() == 1 and (wrap.get_child(0) as MeshInstance3D).mesh != null, "a wrap grows on the rooted actor")
	await frames(60 * 3)
	check(victim.get_node_or_null("VineWrap") == null, "the wrap is gone when the root ends")
	await frames(60)
	check(_find(root, "VinesFx") == null and _count_class(root, "Vines") == 0, "the spell node frees itself")
	# A dead actor loses its wrap at once.
	_fresh()
	var doomed := _dummy(Vector3(0, 0, 0), 10.0)
	SpellBook.cast("vines", _hero(Vector3(-7, 0, 0)), 1.0, Vector3.ZERO)
	await frames(25)
	check(doomed.get_node_or_null("VineWrap") != null, "wrapped")
	doomed.apply_damage(50.0)
	await frames(3)
	check(doomed.get_node_or_null("VineWrap") == null, "a dead actor drops its wrap")
	# Casting through a hero's slots spends a Seed pod.
	_fresh()
	var h := _hero(Vector3(-5, 0, 0))
	h.spell_slots = ["vines", "heal"] as Array[String]
	eq(h.charges_of("vines"), 5)
	check(h.try_cast("vines", 1.0, Vector3.ZERO), "cast through the slots")
	eq(h.charges_of("vines"), 4, "a charge of Seed pod is spent")
	check(not h.try_cast("vines", 1.0, Vector3.ZERO), "on cooldown")
	near(h.cooldown_left("vines"), SpellBook.cooldown_of("vines") / SpellComponents.HELD_COOLDOWN_DIV, 0.1, "the held spell recharges 15% faster")


func _find(n: Node, cls: String) -> Node:
	for c in n.get_children():
		if c.get_script() != null and str(c.get_script().get_global_name()) == cls:
			return c
		var deep := _find(c, cls)
		if deep != null:
			return deep
	return null


func _count_class(n: Node, cls: String) -> int:
	var k := 0
	for c in n.get_children():
		if c.get_script() != null and str(c.get_script().get_global_name()) == cls:
			k += 1
		k += _count_class(c, cls)
	return k
