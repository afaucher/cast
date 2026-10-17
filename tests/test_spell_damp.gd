extends MonsterTestBase
## Damp: a WIDE area gets soggy. Every fire in it goes out, everyone in it (any team) is soaked so it cannot
## ignite for a while (a fireball blast fizzles on them), the floor gets puddles that make shoves slide further
## while they last (and dry out, within the 30 s grime rule), and models drip and leave wet footprints.
## Damage: none.


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


func _damp_nodes() -> int:
	var n := 0
	for c in world.get_children():
		if c is Damp:
			n += 1
	return n


func setup() -> void:
	_numbers()
	await _area_soak_and_fire()
	await _fireball_fizzles()
	await _wet_floor()
	await _wet_look()
	await _grime_and_scheduling()
	finish()


func _numbers() -> void:
	check(SpellBook.SPELLS.has("damp") and SpellBook.is_available("damp"), "damp exists and is castable")
	eq(SpellBook.spell_name("damp"), "Damp")
	eq(SpellBook.incantation("damp"), "CAST DAMP")
	eq(SpellBook.component_name("damp"), "Soggy sponge")
	near(SpellBook.cooldown_of("damp"), 10.0, 0.001, "cooldown 10 s")
	check(SpellBook.color_of("damp").b > 0.85 and SpellBook.color_of("damp").r < 0.4, "water blue")
	check(SpellBook.damp_radius(1.0) > SpellBook.tentacles_radius(1.0) and SpellBook.damp_radius(0.05) >= 4.0, "a WIDE area: wider than tentacles (%.2f)" % SpellBook.damp_radius(1.0))
	near(SpellBook.damp_radius(1.0), 5.0, 0.001, "radius 4 + 1 * power")
	near(SpellBook.DAMP_SOAK, 15.0, 0.001, "soaked for 15 s")
	check(SpellBook.DAMP_PUDDLE_LIFE < Grime.LIFE, "the puddles dry before the 30 s grime marks fade")
	near(SpellBook.DAMP_SLIDE_BONUS, 0.5, 0.001, "+50% slide on a wet cell")
	near(Damp.slide_mult(Actor.new()), 1.0, 0.0001, "no puddles: shoves are normal")
	var d := Damp.new()
	var f: Dictionary = d.net_fields()
	eq(f["start_time"], Net.SPAWN, "the cast's stamp is a SPAWN parameter")
	d.free()
	var w := Wet.new()
	eq(w.net_fields()["target"], Net.SPAWN, "the Wet status")
	w.free()


# --- Soak and put out fire --------------------------------------------------------------------------------

func _area_soak_and_fire() -> void:
	new_world(flat_map(10))
	var caster := _hero(Vector3(-8, 0, 0))
	var near_hero := _hero(Vector3(1.0, 0, 0))
	var wide_mon := _dummy(Vector3(-3.6, 0, 2.0))        # 4.1 from the centre: outside a tentacles-sized area, inside damp's
	var worker := Employee.spawn(Hex.from_world(Vector3(0, 0, -3.0)), {"style": "staff"})
	worker.global_position = Vector3(0.0, worker.global_position.y, -3.0)
	var far_mon := _dummy(Vector3(7.5, 0, 6.0))
	var far_hero := _hero(Vector3(-6.0, 0, -6.0))
	var burning_a := _dummy(Vector3(2.0, 0, 1.0))
	var burning_far := _dummy(Vector3(6.5, 0, -6.0))
	check(Burning.ignite(burning_a, caster, 12.0) != null, "set up: a fire inside the area")
	check(Burning.ignite(burning_far, caster, 12.0) != null, "and one outside")
	check(Burning.ignite(near_hero, caster, 12.0) != null, "and a burning hero")
	check(SpellBook.cast("damp", caster, 1.0, Vector3.ZERO), "damp casts")
	await frames(6)
	check(not Burning.is_soaked(near_hero) and Burning.is_burning(burning_a), "nothing happens during the telegraph (0.2 s)")
	await frames(12)
	for a: Actor in [near_hero, wide_mon, worker, burning_a]:
		check(Burning.is_soaked(a), "%s is soaked" % a.display_name)
		check(Wet.is_wet(a) and Wet.remaining(a) > SpellBook.DAMP_SOAK - 0.6, "%s: about 15 s of damp left (%.1f)" % [a.display_name, Wet.remaining(a)])
	check(not Burning.is_soaked(far_mon) and not Burning.is_soaked(far_hero) and not Burning.is_soaked(caster), "outside the radius stays dry")
	check(not Burning.is_burning(burning_a) and not Burning.is_burning(near_hero), "it puts out the fires in the area (any team)")
	check(Burning.is_burning(burning_far), "but not a fire outside it")
	near(near_hero.hp, near_hero.max_hp, 0.5, "no damage (the fire did tick before it was put out)")
	near(wide_mon.hp, wide_mon.max_hp, 0.001, "no damage to monsters either")
	# The soaked cannot ignite until dry ...
	check(Burning.ignite(near_hero, caster, 8.0) == null and Burning.ignite(wide_mon, caster, 8.0) == null, "soaked actors cannot be set alight")
	check(not Burning.can_burn(worker), "an employee cannot burn while soaked")
	# ... and they are dry again after 15 s.
	GameWorld.time += SpellBook.DAMP_SOAK + 0.5
	await frames(2)
	check(not Burning.is_soaked(near_hero) and Burning.can_burn(near_hero), "dry after 15 s: it can burn again")
	check(Burning.ignite(near_hero, caster, 5.0) != null, "and does")
	check(near_hero.get_node_or_null("Wet") == null, "the dripping stops with the damp")

	# Burning.extinguish_in_radius is what the spell uses; soak refreshes to the longer time and never shortens.
	new_world(flat_map(10))
	var a := _dummy(Vector3.ZERO)
	Wet.douse(a, 10.0)
	Wet.douse(a, 3.0)
	check(Wet.remaining(a) > 9.0, "a short second dose does not cut the damp short (%.1f)" % Wet.remaining(a))
	Wet.douse(a, 20.0)
	check(Wet.remaining(a) > 19.0, "a longer one extends it")
	eq(a.get_children().filter(func(n: Node) -> bool: return n is Wet).size(), 1, "one Wet node, never stacked")


# --- A fireball blast on soaked actors fizzles -------------------------------------------------------------

func _fireball_fizzles() -> void:
	new_world(flat_map(10))
	var caster := _hero(Vector3(-8, 0, 0))
	var soaked: Array[Actor] = []
	var dry: Array[Actor] = []
	for i in 30:
		var ang := float(i) * 0.7
		soaked.append(_dummy(Vector3(3.0 + cos(ang) * 0.5, 0, 3.0 + sin(ang) * 0.5)))
		dry.append(_dummy(Vector3(3.0 + cos(ang) * 0.5, 0, -3.0 + sin(ang) * 0.5)))
	for a in soaked:
		Wet.douse(a, 15.0)
	var ignited_soaked := Burning.on_blast(Vector3(3, 0, 3), 3.0, 1.0, caster)
	var ignited_dry := Burning.on_blast(Vector3(3, 0, -3), 3.0, 1.0, caster)
	eq(ignited_soaked.size(), 0, "a blast on 30 soaked actors ignites none: it fizzles")
	check(ignited_dry.size() > 3, "the same blast on dry actors does (%d / 30)" % ignited_dry.size())
	# A real fireball cast at the soaked crowd.
	for a in dry:
		Burning.extinguish(a)
	SpellBook.cast("fireball", caster, 1.0, Vector3(3, 0, 3))
	await frames(90)
	var burning := 0
	for a in soaked:
		if Burning.is_burning(a):
			burning += 1
	eq(burning, 0, "a fireball cast at the soaked crowd sets nobody on fire")
	check(soaked[0].hp < soaked[0].max_hp, "(the blast itself still hurts monsters)")
	# The fizzle is visible: a steam burst and a word over the actor (cosmetic nodes appear).
	var labels := 0
	for c in world.get_children():
		if c is Label3D and (c as Label3D).text == "FIZZLE":
			labels += 1
	# (the numbers float up for 0.9 s, so some are still there)
	check(labels >= 0, "fizzle feedback does not error")
	# Damp after the fire: put out and protected in one cast, then it burns again later.
	new_world(flat_map(10))
	var c2 := _hero(Vector3(-8, 0, 0))
	var victim := _dummy(Vector3(1.0, 0, 0))
	Burning.ignite(victim, c2, 12.0)
	SpellBook.cast("damp", c2, 1.0, Vector3.ZERO)
	await frames(20)
	check(not Burning.is_burning(victim) and Burning.is_soaked(victim), "put out and soaked")
	SpellBook.cast("fireball", c2, 1.0, Vector3(1, 0, 0))
	await frames(90)
	check(not Burning.is_burning(victim), "the next fireball fizzles on it")
	GameWorld.time += 20.0
	await frames(2)
	check(Burning.ignite(victim, c2, 5.0) != null, "dry again: it can burn")


# --- The wet floor -----------------------------------------------------------------------------------------

func _wet_floor() -> void:
	new_world(flat_map(12))
	var caster := _hero(Vector3(-9, 0, 0))
	var wet_cell := _dummy(Vector3(0.1, 0, 0.0))       # the centre cell is always a puddle
	var dry_a := _dummy(Vector3(-6, 0, 6.0))           # a dry control far from the area, same shove
	var dry_b := _dummy(Vector3(-6, 0, -6.0))
	SpellBook.cast("damp", caster, 1.0, Vector3.ZERO)
	await frames(20)
	check(_damp_nodes() == 1, "the damp field exists")
	var field: Damp = null
	for c in world.get_children():
		if c is Damp:
			field = c
	check(field.is_wet_at(Vector3(0.1, 0, 0.0)) and not field.is_wet_at(Vector3(-6, 0, 6)), "the centre is wet, far away is dry")
	near(Damp.slide_mult(wet_cell), 1.0 + SpellBook.DAMP_SLIDE_BONUS, 0.0001, "a fresh puddle: +50% slide")
	near(Damp.slide_mult(dry_a), 1.0, 0.0001, "dry floor: normal")
	# The same shove travels further from a wet cell.
	var wx := wet_cell.global_position.x
	var wz := wet_cell.global_position.z
	wet_cell.shove(Vector3.RIGHT, 2.0, null)
	dry_a.shove(Vector3.RIGHT, 2.0, null)
	await frames(50)
	var d_wet := wet_cell.global_position.x - wx
	var d_dry := dry_a.global_position.x + 6.0
	near(d_dry, 2.0, 0.1, "a dry shove goes 2.0 (%.2f)" % d_dry)
	near(d_wet, 3.0, 0.15, "a wet shove goes 50%% further (%.2f)" % d_wet)
	near(wet_cell.global_position.z, wz, 0.01, "straight along the shove")
	# Tentacles slide further across the puddles too (a fresh room, so nothing stands in the way).
	new_world(flat_map(12))
	var c := _hero(Vector3(-9, 0, 5))
	SpellBook.cast("damp", c, 1.0, Vector3.ZERO)
	await frames(20)
	var runner := _dummy(Vector3(0.0, 0, -1.0))
	var dry_runner := _dummy(Vector3(-6.0, 0, 6.0))
	SpellBook.cast("tentacles", c, 1.0, Vector3(-1.0, 0, -1.0))
	SpellBook.cast("tentacles", c, 1.0, Vector3(-7.0, 0, 6.0))
	await frames(80)
	var run_wet := runner.global_position.x - 0.0
	var run_dry := dry_runner.global_position.x - (-6.0)
	check(run_wet > run_dry * 1.3, "tentacles shove further over a puddle than over dry floor (%.2f vs %.2f)" % [run_wet, run_dry])
	for n in world.get_children():
		if n is Damp:
			field = n
	var rest := _dummy(Vector3(0.0, 0, 0.3))
	# The puddles dry out: the bonus fades over the last DAMP_DRY_TIME seconds, then it is gone.
	var left := field._end - GameWorld.time
	GameWorld.time += left - SpellBook.DAMP_DRY_TIME * 0.5
	near(field.wetness(), 0.5, 0.05, "half dry")
	near(Damp.slide_mult(rest), 1.0 + SpellBook.DAMP_SLIDE_BONUS * 0.5, 0.05, "half the bonus")
	GameWorld.time += SpellBook.DAMP_DRY_TIME
	await frames(3)
	near(Damp.slide_mult(rest), 1.0, 0.0001, "bone dry: back to a normal shove")
	check(_damp_nodes() == 0, "the field frees itself")
	var rest2 := _dummy(Vector3(-5.0, 0, -4.0))
	rest2.shove(Vector3.RIGHT, 2.0, null)
	var rx := rest2.global_position.x
	await frames(50)
	near(rest2.global_position.x - rx, 2.0, 0.1, "and a shove there goes the normal 2.0")

	# Which cells get puddles is a pure function of (centre, radius, stamp), the same on every machine.
	new_world(flat_map(12))
	var a := Damp.plan_cells(Vector3(0.3, 0, 0.2), 5.0, 12.5)
	var b := Damp.plan_cells(Vector3(0.3, 0, 0.2), 5.0, 12.5)
	eq(a, b, "the puddle plan is deterministic")
	check(Damp.plan_cells(Vector3(0.3, 0, 0.2), 5.0, 99.0) != a, "a different cast gets different puddles")
	var all_in := 0
	for cell in Hex.range_cells(Hex.from_world(Vector3(0.3, 0, 0.2)), 6):
		if GameWorld.flat_distance(Hex.to_world(cell), Vector3(0.3, 0, 0.2)) <= 5.0:
			all_in += 1
	check(a.size() >= int(float(all_in) * 0.7) and a.size() <= all_in, "most cells in the area are puddles (%d of %d)" % [a.size(), all_in])
	check(a.has(Hex.from_world(Vector3(0.3, 0, 0.2))), "the centre cell always is")
	# No puddles on void or wall cells.
	var holey := flat_map(8)
	holey.cells.erase(Vector2i(1, 0))
	new_world(holey)
	check(not Damp.plan_cells(Vector3.ZERO, 5.0, 3.0).has(Vector2i(1, 0)), "a pit cell is never wet")


# --- Drips and footprints ------------------------------------------------------------------------------------

func _wet_look() -> void:
	new_world(flat_map(10))
	var hero := _hero(Vector3(0, 0, 0))
	var mon := MonsterFactory.spawn("grunt", Vector2i(3, 0)) as Monster
	mon.aggro_range = 0.0
	check(Wet.douse(hero, 10.0) != null and Wet.douse(mon, 10.0) != null, "heroes and monsters get the dripping look")
	var wet := hero.get_node("Wet") as Wet
	check(wet._drips != null and wet._drips.emitting, "drips fall off the body")
	check(wet.target == hero, "it knows its actor")
	var feet0 := world.get_child_count()
	for i in 90:
		hero.move(Vector3.RIGHT, 1.0 / 60.0)
		await get_tree().physics_frame
	check(wet._feet.size() >= 2, "a hero walking leaves wet footprints (%d)" % wet._feet.size())
	check(world.get_child_count() > feet0, "they are in the world")
	for i in 400:
		hero.move(Vector3(0, 0, -1), 1.0 / 60.0)
		if i % 20 == 0:
			await get_tree().physics_frame
	await frames(10)
	check(wet._feet.size() <= Wet.MAX_FEET, "at most %d prints at a time (%d)" % [Wet.MAX_FEET, wet._feet.size()])
	# A standing actor leaves none.
	var still := _dummy(Vector3(-4, 0, 4))
	var still_wet := Wet.douse(still, 10.0)
	await frames(60)
	eq(still_wet._feet.size(), 0, "no walking, no footprints")
	# Inanimate things are soaked but do not drip: a mail package.
	var box := MailPackage.spawn(Vector2(3.5, 3.5), {"seed": 3})
	if box != null:
		check(Wet.douse(box, 10.0) == null and box.get_node_or_null("Wet") == null, "a mail package gets no drips")
	# The look ends with the damp.
	GameWorld.time += 11.0
	await frames(3)
	check(hero.get_node_or_null("Wet") == null and mon.get_node_or_null("Wet") == null, "the drips stop when the damp does")
	# A dead actor loses it at once.
	var doomed := _dummy(Vector3(2, 0, 4), 10.0)
	Wet.douse(doomed, 10.0)
	doomed.apply_damage(100.0)
	await frames(3)
	check(not is_instance_valid(doomed) or doomed.get_node_or_null("Wet") == null, "a dead actor stops dripping")


# --- Puddles are player-caused grime; the cast is a scheduled effect ---------------------------------------------

func _grime_and_scheduling() -> void:
	var m := flat_map(10)
	new_world(m)
	var layer := GrimeLayer.attach(world, m, null, 3)
	var caster := _hero(Vector3(-8, 0, 0))
	eq(layer.live_count(), 0, "no marks yet")
	SpellBook.cast("damp", caster, 1.0, Vector3(1.0, 0, 0.0))
	await frames(20)
	var puddles := 0
	for mk in layer.live_marks():
		if mk["recipe"] == Grime.WET:
			puddles += 1
	var field: Damp = null
	for c in world.get_children():
		if c is Damp:
			field = c
	check(puddles > 8 and puddles == field.wet_cells().size(), "one puddle decal per wet cell (%d marks, %d cells)" % [puddles, field.wet_cells().size()])
	for mk in layer.live_marks():
		if mk["recipe"] == Grime.WET:
			check(field.is_wet_at(mk["pos"]), "every puddle lies on a wet cell")
			break
	# They fade by themselves inside the 30 s player-mark rule.
	layer.advance(Grime.LIFE + 1.0)
	var left := 0
	for mk in layer.live_marks():
		if mk["recipe"] == Grime.WET:
			left += 1
	eq(left, 0, "the puddle decals are gone after %d s" % int(Grime.LIFE))
	check(SpellBook.DAMP_PUDDLE_LIFE <= Grime.LIFE, "and the wet floor itself ends first")
	# No layer: casting damp is harmless.
	new_world(flat_map(10))
	var c3 := _hero(Vector3(-8, 0, 0))
	var t3 := _dummy(Vector3(0.5, 0, 0))
	SpellBook.cast("damp", c3, 1.0, Vector3.ZERO)
	await frames(15)
	check(Burning.is_soaked(t3), "damp works with no grime layer")

	# A cast whose stamp is in the past bursts at once (every machine runs the same schedule).
	new_world(flat_map(10))
	var t4 := _dummy(Vector3(0.5, 0, 0))
	var late := Damp.new()
	late.power = 1.0
	late.start_time = GameWorld.time - Damp.TELEGRAPH - 0.05
	GameWorld.spawn(late, Vector3.ZERO)
	await frames(2)
	check(Burning.is_soaked(t4) and late.is_wet_at(Vector3(0.5, 0, 0)), "a late cast bursts on the first frame")
	# The field expires and frees itself.
	GameWorld.time += SpellBook.DAMP_PUDDLE_LIFE + 1.0
	await frames(3)
	check(not is_instance_valid(late), "the node frees itself")

	# Casting through the slots spends a Sponge charge.
	new_world(flat_map(10))
	var h := _hero(Vector3(-5, 0, 0))
	h.spell_slots = ["damp", "heal"] as Array[String]
	check(h.try_cast("damp", 1.0, Vector3.ZERO), "cast through the slots")
	eq(h.charges_of("damp"), 4, "a charge is spent")
