extends TestCase
## Teeth: "cast teeth" afflicts every living actor (heroes, the caster, monsters) within 2.0 + 0.6 *
## power of the aim point and nobody outside. The teeth grow for 2.0 - power seconds (no damage
## before), then each carrier pops: the carrier takes 25 * power, everyone else within 1.5 takes
## 10 * power and a mild outward shove. A hero's pop never takes a hero below 1 HP, a heal pulls the
## teeth (no pop), a carrier that died or was freed still splashes at its last spot, re-casting
## replaces the affliction (one pop), and power scales radius, speed and damage.

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


func _hero(pos: Vector3) -> Hero:
	var h := Hero.new()
	GameWorld.spawn(h, pos)
	h.snap_to_ground()
	return h


func _dummy(pos: Vector3, hp: float = 1000.0) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.max_hp = hp
	GameWorld.spawn(d, pos)
	d.snap_to_ground()
	return d


func _fx_count() -> int:
	var n := 0
	for c in root.get_children():
		if c is TeethFx:
			n += 1
	return n


## Physics frames (60/s) until `a` loses HP, as seconds; -1 when it never does within `limit` frames.
func _until_hurt(a: Actor, limit: int = 240) -> float:
	var before := a.hp
	for i in limit:
		await get_tree().physics_frame
		if a.hp < before - 0.001:
			return float(i + 1) / 60.0
	return -1.0


func setup() -> void:
	# --- The numbers and the spell's data.
	check(SpellBook.has_spell("teeth") and SpellBook.is_available("teeth"), "teeth is available")
	check(SpellBook.ids().has("teeth"), "the picker offers teeth")
	eq(SpellBook.spell_name("teeth"), "Teeth")
	eq(SpellBook.incantation("teeth"), "CAST TEETH")
	near(SpellBook.cooldown_of("teeth"), 12.0, 0.001)
	near(SpellBook.teeth_radius(1.0), 2.6, 0.001, "radius 2.0 + 0.6 * power")
	near(SpellBook.teeth_radius(0.5), 2.3, 0.001)
	near(SpellBook.teeth_grow_time(1.0), 1.0, 0.001, "grow 2.0 - power")
	near(SpellBook.teeth_grow_time(0.5), 1.5, 0.001)
	near(SpellBook.teeth_damage(1.0), 25.0, 0.001, "carrier 25 * power")
	near(SpellBook.teeth_splash_damage(1.0), 10.0, 0.001, "splash 10 * power")
	near(SpellBook.TEETH_SPLASH_RADIUS, 1.5, 0.001)
	near(SpellBook.TEETH_SHOVE, 1.2, 0.001)
	check(SpellBook.teeth_radius(0.3) < SpellBook.teeth_radius(0.6) and SpellBook.teeth_radius(0.6) < SpellBook.teeth_radius(1.0), "radius monotonic")
	check(SpellBook.teeth_grow_time(0.3) > SpellBook.teeth_grow_time(0.6) and SpellBook.teeth_grow_time(0.6) > SpellBook.teeth_grow_time(1.0), "grow time shrinks with power")
	check(SpellBook.teeth_damage(0.3) < SpellBook.teeth_damage(0.6) and SpellBook.teeth_damage(0.6) < SpellBook.teeth_damage(1.0), "damage monotonic")
	check(SpellBook.find_in_text("cast teeth") == "teeth", "text lookup")

	await _test_afflicts_and_pops()
	await _test_caster_and_timing()
	await _test_splash_and_shove()
	await _test_chain()
	await _test_friendly_floor()
	await _test_heal_cancels()
	await _test_dead_carrier()
	await _test_recast()
	await _test_power_scaling()
	await _test_grunt_drops()
	finish()


## Everyone inside (heroes and monsters), nobody outside; no damage before the grow time; the carrier takes 25.
func _test_afflicts_and_pops() -> void:
	_fresh()
	var center := Vector3.ZERO
	var caster := _hero(Vector3(-7, 0, 0))
	var mon_a := _dummy(Vector3(2.0, 0, 0))
	var mon_b := _dummy(Vector3(-1.0, 0, -1.8))
	var hero_a := _hero(Vector3(-0.5, 0, 1.9))
	var far_mon := _dummy(Vector3(5.0, 0, 0))
	var far_hero := _hero(Vector3(0, 0, -4.5))
	var inside: Array[Actor] = [mon_a, mon_b, hero_a]
	var outside: Array[Actor] = [far_mon, far_hero, caster]
	check(SpellBook.cast("teeth", caster, 1.0, center), "teeth casts")
	for a in inside:
		check(Teeth.is_afflicted(a), "%s is afflicted" % a.display_name)
		check(a.has_meta("teeth_fx"), "and has the fx meta")
	for a in outside:
		check(not Teeth.is_afflicted(a), "%s is not afflicted" % a.display_name)
	eq(_fx_count(), 3, "one TeethFx per afflicted actor")
	await frames(40)     # 0.67 s of a 1.0 s fuse
	for a in inside + outside:
		near(a.hp, a.max_hp, 0.001, "no damage before the grow time (%s)" % a.display_name)
	await frames(50)
	near(mon_a.hp, mon_a.max_hp - 25.0, 0.001, "monster carrier takes 25 * power")
	near(mon_b.hp, mon_b.max_hp - 25.0, 0.001)
	near(hero_a.hp, hero_a.max_hp - 25.0, 0.001, "hero carrier takes 25 * power")
	near(far_mon.hp, far_mon.max_hp, 0.001, "outside: untouched")
	near(far_hero.hp, far_hero.max_hp, 0.001)
	near(caster.hp, caster.max_hp, 0.001, "the caster was outside")
	for a in inside:
		check(not Teeth.is_afflicted(a), "afflictions end at the pop")
	await frames(120)
	eq(_fx_count(), 0, "all effects are freed")
	near(mon_a.hp, mon_a.max_hp - 25.0, 0.001, "no second pop")


## The caster counts as everyone; the pop lands at about 2.0 - power seconds.
func _test_caster_and_timing() -> void:
	_fresh()
	var caster := _hero(Vector3(0.3, 0, 0.2))
	var mon := _dummy(Vector3(-1.5, 0, 1.0))
	SpellBook.cast("teeth", caster, 0.6, Vector3.ZERO)
	check(Teeth.is_afflicted(caster), "the caster standing in it is afflicted")
	check(Teeth.is_afflicted(mon), "and so is the monster")
	var t: float = await _until_hurt(mon)
	near(t, 1.4, 0.15, "pop at about 2.0 - power (power 0.6)")
	near(caster.hp, caster.max_hp - SpellBook.teeth_damage(0.6), 0.001, "the caster takes its own pop")
	near(mon.hp, mon.max_hp - SpellBook.teeth_damage(0.6), 0.001, "carrier damage scales with power (15)")

	_fresh()
	var c2 := _hero(Vector3(-7, 0, 0))
	var m2 := _dummy(Vector3(1.0, 0, 0))
	SpellBook.cast("teeth", c2, 1.0, Vector3.ZERO)
	var t2: float = await _until_hurt(m2)
	near(t2, 1.0, 0.15, "full power pops after 1.0 s")


## A bystander just outside the sprout radius but near a carrier takes 10 * power and a 1.2 shove outward.
func _test_splash_and_shove() -> void:
	_fresh()
	var caster := _hero(Vector3(-7, 0, 0))
	var carrier := _dummy(Vector3(2.0, 0, 0))
	var bystander := _dummy(Vector3(3.7, 0, 0))        # outside 2.6 + 0.45, 1.7 from the carrier
	var bystander_hero := _hero(Vector3(3.1, 0, 1.5))  # outside too (3.44 from the center), 1.86 from the carrier
	var far := _dummy(Vector3(2.0, 0, -3.5))           # more than 1.5 + radius from the carrier
	SpellBook.cast("teeth", caster, 1.0, Vector3.ZERO)
	check(Teeth.is_afflicted(carrier), "carrier afflicted")
	check(not Teeth.is_afflicted(bystander), "bystander outside the sprout radius")
	var carrier_start := carrier.global_position
	var bystander_start := bystander.global_position
	var hero_start := bystander_hero.global_position
	await frames(75)
	near(carrier.hp, carrier.max_hp - 25.0, 0.001, "carrier takes 25")
	near(bystander.hp, bystander.max_hp - 10.0, 0.001, "bystander takes 10 * power")
	near(bystander_hero.hp, bystander_hero.max_hp - 10.0, 0.001, "heroes take the splash too")
	near(far.hp, far.max_hp, 0.001, "far actors take none")
	await frames(40)
	var moved := bystander.global_position - bystander_start
	near(moved.length(), SpellBook.TEETH_SHOVE, 0.15, "shoved 1.2 outward")
	check(moved.normalized().dot(Vector3.RIGHT) > 0.97, "directly away from the carrier")
	var hmoved := bystander_hero.global_position - hero_start
	near(hmoved.length(), SpellBook.TEETH_SHOVE, 0.15, "heroes are shoved too")
	check(hmoved.normalized().dot((hero_start - carrier_start).normalized()) > 0.97, "away from the carrier")
	near(carrier.global_position.distance_to(carrier_start), 0.0, 0.2, "the carrier itself is not shoved")
	near(far.global_position.z, -3.5, 0.0001, "far actors are not shoved")


## Two carriers side by side: each takes its own pop (25) and the other's splash (10); pops never re-afflict.
func _test_chain() -> void:
	_fresh()
	var caster := _hero(Vector3(-7, 0, 0))
	var a := _dummy(Vector3(0, 0, 0))
	var b := _dummy(Vector3(1.0, 0, 0))
	SpellBook.cast("teeth", caster, 1.0, Vector3(0.5, 0, 0))
	await frames(75)
	near(a.hp, a.max_hp - 35.0, 0.001, "own pop + neighbour's splash")
	near(b.hp, b.max_hp - 35.0, 0.001)
	await frames(60)
	check(not Teeth.is_afflicted(a) and not Teeth.is_afflicted(b), "pops do not afflict again")
	await frames(120)
	near(a.hp, a.max_hp - 35.0, 0.001, "nothing pops a second time")
	eq(_fx_count(), 0, "no stray effects")


## Friendly fire from a hero never takes a hero below 1 HP (carrier or splash); monsters are not protected.
func _test_friendly_floor() -> void:
	_fresh()
	var caster := _hero(Vector3(-7, 0, 0))
	var carrier := _hero(Vector3(2.0, 0, 0))
	carrier.hp = 20.0
	var bystander := _hero(Vector3(3.7, 0, 0))          # outside the sprout radius, 1.7 from the carrier
	bystander.hp = 5.0
	var tough := _hero(Vector3(2.0, 0, -1.6))           # inside the radius? 2.56 from the center: yes, a carrier too
	tough.hp = 1.0
	var weak_mon := _dummy(Vector3(-1.2, 0, 1.8), 20.0)
	check(Teeth.is_afflicted(carrier) == false, "not yet")
	SpellBook.cast("teeth", caster, 1.0, Vector3.ZERO)
	check(Teeth.is_afflicted(carrier) and Teeth.is_afflicted(tough), "hero carriers")
	check(not Teeth.is_afflicted(bystander), "the bystander is outside")
	await frames(75)
	check(not carrier.dead and not bystander.dead and not tough.dead, "nobody was downed")
	near(carrier.hp, 1.0, 0.001, "the carrier (20 HP, pop 25) ends at 1 HP")
	near(bystander.hp, 1.0, 0.001, "the bystander (5 HP, splash 10) ends at 1 HP")
	near(tough.hp, 1.0, 0.001, "a hero at 1 HP stays at 1 HP")
	check(weak_mon.dead, "a monster is not protected: 20 HP, pop 25")

	# Armor halves nothing here, but the floor must account for damage_taken_mult.
	_fresh()
	var c2 := _hero(Vector3(-7, 0, 0))
	var armored := _hero(Vector3(2.0, 0, 0))
	armored.hp = 12.0
	armored.set_modifier("armor", 0.5, 10.0)
	SpellBook.cast("teeth", c2, 1.0, Vector3.ZERO)
	await frames(75)
	check(not armored.dead, "armored hero survives")
	near(armored.hp, 1.0, 0.001, "armored hero floors at 1 HP")

	# A monster-credited pop is not protected (the floor is for hero-caused damage): afflict directly.
	_fresh()
	var mc := _dummy(Vector3(-7, 0, 0))
	var victim := _hero(Vector3(0, 0, 0))
	victim.hp = 10.0
	Teeth.afflict(victim, mc, 1.0, 0.3)
	await frames(40)
	check(victim.dead, "damage that did not come from a hero can down a hero")


## A heal that lands on an afflicted hero pulls the teeth: no pop for that victim.
func _test_heal_cancels() -> void:
	_fresh()
	var caster := _hero(Vector3(-7, 0, 0))
	var healer := _hero(Vector3(-6, 0, 2))
	var hero_a := _hero(Vector3(1.8, 0, 0))
	hero_a.hp = 50.0
	var hero_b := _hero(Vector3(-1.5, 0, 1.5))
	hero_b.hp = 100.0
	var mon := _dummy(Vector3(0, 0, -2.0))
	SpellBook.cast("teeth", caster, 1.0, Vector3.ZERO)
	check(Teeth.is_afflicted(hero_a) and Teeth.is_afflicted(hero_b) and Teeth.is_afflicted(mon), "all three afflicted")
	await frames(20)
	var fx_a: TeethFx = hero_a.get_meta("teeth_fx") as TeethFx
	var fx_mon: TeethFx = mon.get_meta("teeth_fx") as TeethFx
	SpellBook.cast("heal", healer, 1.0, Vector3(0.2, 0, 0.8))     # heal radius 3: covers both heroes, not the monster
	check(not Teeth.is_afflicted(hero_a), "the heal pulled hero_a's teeth")
	check(not Teeth.is_afflicted(hero_b), "and hero_b's, at full HP")
	check(Teeth.is_afflicted(mon), "heals do not touch monsters")
	check(not fx_a.is_growing(), "fx cancelled")
	check(fx_mon.is_growing(), "the monster's fx keeps growing")
	await frames(90)
	near(hero_a.hp, 50.0 + HealSpell.heal_amount(1.0), 0.01, "healed and no pop damage")
	near(hero_b.hp, 100.0, 0.001, "no pop damage")
	near(mon.hp, mon.max_hp - 25.0, 0.001, "the monster still pops")
	eq(Teeth.cancel_on(hero_a), false, "nothing left to pull")
	await frames(60)
	eq(_fx_count(), 0, "all effects are freed")


## A carrier that dies (or is freed) before the pop still splashes at its last position; it takes nothing itself.
func _test_dead_carrier() -> void:
	_fresh()
	var caster := _hero(Vector3(-7, 0, 0))
	var dying := _dummy(Vector3(2.0, 0, 0))
	var near_dying := _dummy(Vector3(3.7, 0, 0))          # outside the sprout radius
	var freed := _dummy(Vector3(-2.0, 0, 0))
	var near_freed := _dummy(Vector3(-3.7, 0, 0))
	SpellBook.cast("teeth", caster, 1.0, Vector3.ZERO)
	check(Teeth.is_afflicted(dying) and Teeth.is_afflicted(freed), "both afflicted")
	check(not Teeth.is_afflicted(near_dying) and not Teeth.is_afflicted(near_freed), "bystanders outside")
	await frames(20)
	dying.apply_damage(99999.0)
	check(dying.dead, "the carrier died before the pop")
	freed.free()      # gone entirely
	await frames(10)
	near(near_dying.hp, near_dying.max_hp, 0.001, "no damage yet")
	await frames(60)
	near(near_dying.hp, near_dying.max_hp - 10.0, 0.001, "a dead carrier still splashes at its last position")
	near(near_freed.hp, near_freed.max_hp - 10.0, 0.001, "a freed carrier splashes from its stored position")
	await frames(40)
	check(near_dying.global_position.x > 3.7 + 0.8, "and shoves outward (x=%.2f)" % near_dying.global_position.x)
	check(near_freed.global_position.x < -3.7 - 0.8, "on the other side too (x=%.2f)" % near_freed.global_position.x)
	await frames(120)
	eq(_fx_count(), 0, "effects freed")


## Casting again on an afflicted actor replaces its affliction: one pop, from the second cast.
func _test_recast() -> void:
	_fresh()
	var caster := _hero(Vector3(-7, 0, 0))
	var mon := _dummy(Vector3(1.0, 0, 0))
	SpellBook.cast("teeth", caster, 1.0, Vector3.ZERO)
	eq(_fx_count(), 1, "one effect")
	await frames(30)     # 0.5 s in
	SpellBook.cast("teeth", caster, 1.0, Vector3.ZERO)
	await get_tree().physics_frame
	eq(_fx_count(), 1, "still one effect on the carrier (the old one was replaced)")
	check(Teeth.is_afflicted(mon), "still afflicted")
	await frames(40)     # t = 1.2 s: the first fuse would be over
	near(mon.hp, mon.max_hp, 0.001, "the replaced teeth never popped")
	await frames(40)     # t = 1.9 s: the second fuse (0.5 + 1.0) is over
	near(mon.hp, mon.max_hp - 25.0, 0.001, "one pop only")
	await frames(180)
	near(mon.hp, mon.max_hp - 25.0, 0.001, "and never a second one")
	eq(_fx_count(), 0)


## Higher power: bigger radius, shorter fuse, more damage.
func _test_power_scaling() -> void:
	var fuse: Array[float] = []
	var hurt: Array[float] = []
	var reach: Array[bool] = []
	for p in [0.3, 0.6, 1.0]:
		_fresh()
		var c := _hero(Vector3(-8, 0, 0))
		var m := _dummy(Vector3(0, 0, 1.0))
		var edge := _dummy(Vector3(2.85, 0, -0.2))        # inside only at the higher powers (2.6 + 0.45 at 1.0)
		SpellBook.cast("teeth", c, p, Vector3.ZERO)
		reach.append(Teeth.is_afflicted(edge))
		var t: float = await _until_hurt(m)
		fuse.append(t)
		hurt.append(m.max_hp - m.hp)
	check(fuse[0] > fuse[1] and fuse[1] > fuse[2], "the fuse shortens with power %s" % str(fuse))
	check(hurt[0] < hurt[1] and hurt[1] < hurt[2], "damage grows with power %s" % str(hurt))
	check(not reach[0] and reach[2], "the radius grows with power %s" % str(reach))


## The drop table's teeth entry is live now: grunts drop "Loose teeth" that a hero can use.
func _test_grunt_drops() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var seen := 0
	for i in 400:
		if SpellComponents.roll_drops("grunt", rng).has("teeth"):
			seen += 1
	check(seen > 20 and seen < 85, "grunts drop teeth about 12%% of the time (%d / 400)" % seen)
