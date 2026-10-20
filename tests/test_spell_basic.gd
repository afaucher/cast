extends TestCase
## Heal and Armor: radius rules, caps, damage reduction, expiry, power scaling.

var root: Node3D


func _flat_map(radius: int = 8) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 0)
	return m


func _hero(offset: Vector3, hp: float = 100.0) -> Hero:
	var h := Hero.new()
	GameWorld.spawn(h, offset)
	h.snap_to_ground()
	h.hp = hp
	return h


func setup() -> void:
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(_flat_map(), root)

	# --- Metadata sanity
	for id in ["heal", "fireball", "armor", "corn"]:
		check(SpellBook.SPELLS.has(id), "spell exists: " + id)
		check(SpellBook.cooldown_of(id) > 0.0, "cooldown: " + id)
		eq(SpellBook.incantation(id), "CAST " + id.to_upper(), "incantation: " + id)
	near(SpellBook.cooldown_of("heal"), 8.0, 0.001)
	near(SpellBook.cooldown_of("fireball"), 5.0, 0.001)
	near(SpellBook.cooldown_of("armor"), 14.0, 0.001)
	near(SpellBook.cooldown_of("corn"), 12.0, 0.001)
	eq(SpellBook.find_in_text("Cast Fire ball!"), "fireball", "text lookup")
	eq(SpellBook.incantation("heal", "pickle"), "PICKLE HEAL", "custom trigger word")
	eq(SpellBook.find_in_text("hello"), "", "text lookup miss")

	# --- Heal: heroes inside the radius only, capped at max_hp, monsters excluded.
	var caster := _hero(Vector3.ZERO, 40.0)
	var near_ally := _hero(Vector3(3.0, 0, 0), 40.0)
	var far_ally := _hero(Vector3(6.5, 0, 0), 40.0)
	var almost_full := _hero(Vector3(0, 0, 2.5), 95.0)
	var dummy := TrainingDummy.new()
	dummy.max_hp = 100.0
	GameWorld.spawn(dummy, Vector3(1.5, 0, 1.5))
	dummy.hp = 40.0
	check(SpellBook.cast("heal", caster, 1.0, Vector3.ZERO), "heal casts")
	var full_heal := HealSpell.heal_amount(1.0)
	near(full_heal, 35.0, 0.001, "35 at full power")
	near(caster.hp, 40.0 + full_heal, 0.01, "caster healed")
	near(near_ally.hp, 40.0 + full_heal, 0.01, "ally in radius healed")
	near(far_ally.hp, 40.0, 0.01, "ally outside the radius not healed")
	near(almost_full.hp, 100.0, 0.01, "heal capped at max_hp")
	near(dummy.hp, 40.0, 0.01, "monsters not healed")
	# Power scaling: 0.4 + 0.6 * power.
	near(HealSpell.heal_amount(0.5), 35.0 * 0.7, 0.001, "half power heal")
	check(HealSpell.heal_amount(0.2) < HealSpell.heal_amount(0.6) and HealSpell.heal_amount(0.6) < HealSpell.heal_amount(1.0), "heal monotonic in power")
	# Dead (downed) heroes are not revived.
	almost_full.apply_damage(9999.0)
	SpellBook.cast("heal", caster, 1.0, Vector3.ZERO)
	check(almost_full.dead, "heal does not revive the downed")
	for n in [caster, near_ally, far_ally, almost_full, dummy]:
		n.queue_free()
	await frames(2)

	# --- Armor: inside takes reduced damage, outside takes full, buff drops after leaving / expiry.
	var tank := _hero(Vector3.ZERO)
	var inside := _hero(Vector3(2.0, 0, 0))
	var outside := _hero(Vector3(6.0, 0, 0))
	check(SpellBook.cast("armor", tank, 1.0, Vector3.ZERO), "armor casts")
	await frames(20)
	check(tank.has_modifier("armor") and inside.has_modifier("armor"), "heroes inside are armored")
	check(not outside.has_modifier("armor"), "hero outside is not armored")
	var in_dealt := inside.apply_damage(20.0)
	var out_dealt := outside.apply_damage(20.0)
	near(out_dealt, 20.0, 0.001, "no reduction outside")
	near(in_dealt, 20.0 * ArmorSpell.armor_multiplier(1.0), 0.01, "reduced damage inside")
	check(in_dealt < out_dealt * 0.6, "armor roughly halves damage (%f vs %f)" % [in_dealt, out_dealt])
	# Monsters inside the zone get nothing.
	var mob := TrainingDummy.new()
	GameWorld.spawn(mob, Vector3(1.0, 0, 1.0))
	await frames(20)
	check(not mob.has_modifier("armor"), "monsters are not armored")
	mob.queue_free()
	# Leaving the zone drops the buff shortly after.
	inside.global_position = Vector3(6.0, 0, 3.0)
	await frames(30)
	check(not inside.has_modifier("armor"), "buff drops after leaving the zone")
	# Power scaling and duration.
	check(ArmorSpell.armor_multiplier(0.2) > ArmorSpell.armor_multiplier(0.6) and ArmorSpell.armor_multiplier(0.6) > ArmorSpell.armor_multiplier(1.0), "armor stronger with power")
	near(ArmorSpell.armor_multiplier(1.0), 0.4, 0.001)
	near(ArmorSpell.armor_multiplier(0.0), 0.75, 0.001)
	near(ArmorSpell.armor_duration(1.0), 10.0, 0.001)
	near(ArmorSpell.armor_duration(0.5), 7.5, 0.001)
	# Expiry (low power = 5 + 5*0.05 s).
	for z in root.get_children():
		if z is ArmorZone:
			z.queue_free()
	await frames(2)
	var weak_tank := _hero(Vector3(-5.0, 0, 0))
	SpellBook.cast("armor", weak_tank, 0.05, weak_tank.global_position)  # point at your own feet
	await frames(30)
	check(weak_tank.has_modifier("armor"), "weak armor applies")
	await frames(int(ArmorSpell.armor_duration(0.05) * 60.0) + 40)
	check(not weak_tank.has_modifier("armor"), "armor expires with the zone")
	finish()
