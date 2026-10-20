extends TestCase
## Fireball (monsters only, explodes on actor / terrain / range, power scaling)
## and Corn (hits EVERYONE, only after the delay, clamped range, power scaling).

var root: Node3D


func _flat_map(radius: int = 9) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 0)
	return m


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


func _clear() -> void:
	for n in root.get_children():
		n.queue_free()
	await frames(3)


func setup() -> void:
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(_flat_map(), root)

	# --- Fireball direct hit: the monster is hurt, the heroes (incl. one next to the blast) are not.
	var caster := _hero(Vector3.ZERO)
	var buddy := _hero(Vector3(5.5, 0, 1.6))      # stands inside the blast radius, must be spared
	var target := _dummy(Vector3(6.0, 0, 0))
	for a: Actor in [caster, buddy, target]:
		Burning.set_fireproof(a, true)   # this block checks the blast damage exactly; burning is covered by test_burning
	check(SpellBook.cast("fireball", caster, 1.0, target.global_position), "fireball casts")
	await frames(70)
	near(target.hp, target.max_hp - FireballSpell.fireball_damage(1.0), 0.01, "fireball damages the monster")
	near(buddy.hp, buddy.max_hp, 0.01, "fireball spares heroes")
	near(caster.hp, caster.max_hp, 0.01, "fireball spares the caster")
	await _clear()

	# --- Fireball explodes on terrain: a wall in the way, a dummy beside the wall takes splash.
	var m := _flat_map()
	m.set_cell(Vector2i(3, 0), 6, HexMap.Tile.WALL)
	GameWorld.begin(m, root)
	caster = _hero(Vector3.ZERO)
	var splash := _dummy(Vector3(3.9, 0, 1.0))
	SpellBook.cast("fireball", caster, 1.0, Vector3(9, 0, 0))
	await frames(70)
	check(splash.hp < splash.max_hp, "fireball explodes on terrain and splashes nearby monsters")
	await _clear()
	GameWorld.begin(_flat_map(), root)

	# --- Fireball explodes at the aim point when nothing is in the way (not beyond it).
	caster = _hero(Vector3(-8, 0, 0))
	var at_aim := _dummy(Vector3(0, 0, 1.2))
	var beyond := _dummy(Vector3(6, 0, 0))
	SpellBook.cast("fireball", caster, 1.0, Vector3.ZERO)
	await frames(120)
	check(at_aim.hp < at_aim.max_hp, "fireball bursts at the aim point")
	near(beyond.hp, beyond.max_hp, 0.01, "fireball does not fly past the aim point")
	await _clear()

	# --- Fireball power scaling: damage and radius both grow.
	check(FireballSpell.fireball_damage(0.3) < FireballSpell.fireball_damage(0.6) and FireballSpell.fireball_damage(0.6) < FireballSpell.fireball_damage(1.0), "fireball damage monotonic")
	check(FireballSpell.fireball_radius(0.3) < FireballSpell.fireball_radius(0.6) and FireballSpell.fireball_radius(0.6) < FireballSpell.fireball_radius(1.0), "fireball radius monotonic")
	near(FireballSpell.fireball_radius(1.0), 2.4, 0.001)
	near(FireballSpell.fireball_damage(0.5), 20.0, 0.001)
	var damages: Array[float] = []
	for p in [0.3, 0.6, 1.0]:
		caster = _hero(Vector3.ZERO)
		var t := _dummy(Vector3(5.0, 0, 0))
		SpellBook.cast("fireball", caster, p, t.global_position)
		await frames(60)
		damages.append(t.max_hp - t.hp)
		await _clear()
	check(damages[0] < damages[1] and damages[1] < damages[2], "fireball damage in play is monotonic in power: %s" % str(damages))

	# --- Corn: nothing before the delay, then EVERYONE in the radius takes damage.
	caster = _hero(Vector3.ZERO)
	var ally := _hero(Vector3(2.5, 0, 1.5))   # 1.5 from the aim: inside the blast, outside the ally snap
	var mob := _dummy(Vector3(2.5, 0, -0.5))
	var distant := _dummy(Vector3(-5.0, 0, 0))
	var safe_ally := _hero(Vector3(0, 0, 7.5))
	check(SpellBook.cast("corn", caster, 1.0, Vector3(2.5, 0, 0)), "corn casts")
	await frames(int(CornStrike.DELAY * 60.0) - 12)
	near(caster.hp, caster.max_hp, 0.01, "corn: no damage before the delay (caster)")
	near(ally.hp, ally.max_hp, 0.01, "corn: no damage before the delay (ally)")
	near(mob.hp, mob.max_hp, 0.01, "corn: no damage before the delay (monster)")
	await frames(30)
	var dmg := CornSpell.corn_damage(1.0)
	near(dmg, 60.0, 0.001)
	near(ally.hp, ally.max_hp - dmg, 0.01, "corn hits heroes (friendly fire)")
	near(mob.hp, mob.max_hp - dmg, 0.01, "corn hits monsters")
	near(caster.hp, caster.max_hp - dmg, 0.01, "corn hits the caster too (aim 2.5 away, radius 2.5)")
	near(distant.hp, distant.max_hp, 0.01, "corn spares those outside the radius")
	near(safe_ally.hp, safe_ally.max_hp, 0.01, "corn spares far heroes")
	await _clear()

	# --- Spell range clamp: aiming far away lands SPELL_RANGE out (the ranged bolt's reach).
	caster = _hero(Vector3.ZERO)
	var at_clamp := _dummy(Vector3(SpellBook.SPELL_RANGE, 0, 0))
	var at_cursor := _dummy(Vector3(-1.0, 0, 8.0))
	# Aim along +X far beyond range (still inside the map? the aim is off-map; clamp comes first).
	SpellBook.cast("corn", caster, 1.0, Vector3(40.0, 0, 0))
	await frames(int(CornStrike.DELAY * 60.0) + 12)
	check(at_clamp.hp < at_clamp.max_hp, "corn clamped to spell range")
	near(at_cursor.hp, at_cursor.max_hp, 0.01, "corn did not land elsewhere")
	await _clear()

	# --- Pointing at a teammate targets them: corn aimed near an ally lands ON the ally.
	caster = _hero(Vector3.ZERO)
	var pal := _hero(Vector3(6.0, 0, 0))
	var bystander := _dummy(Vector3(3.0, 0, 0))
	SpellBook.cast("corn", caster, 1.0, Vector3(5.2, 0, 0.6))
	await frames(int(CornStrike.DELAY * 60.0) + 12)
	check(pal.hp < pal.max_hp, "corn aimed at a teammate snaps onto them (don't say the wrong spell!)")
	near(bystander.hp, bystander.max_hp, 0.01, "snap moved the strike away from the raw aim")
	await _clear()

	# --- Heal lands where you point: an ally far away is healed, the caster is not.
	caster = _hero(Vector3.ZERO)
	var hurt := _hero(Vector3(8.0, 0, 0))
	caster.apply_damage(30.0)
	hurt.apply_damage(30.0)
	SpellBook.cast("heal", caster, 1.0, hurt.global_position)
	check(hurt.hp > hurt.max_hp - 30.0, "heal aimed at a far ally heals them")
	near(caster.hp, caster.max_hp - 30.0, 0.01, "heal aimed away does not heal the caster")
	await _clear()

	# --- Corn power scaling.
	check(CornSpell.corn_damage(0.3) < CornSpell.corn_damage(0.6) and CornSpell.corn_damage(0.6) < CornSpell.corn_damage(1.0), "corn damage monotonic")

	# --- Fizzle is harmless.
	caster = _hero(Vector3.ZERO)
	SpellBook.fizzle(caster)
	near(caster.hp, caster.max_hp, 0.001, "fizzle does nothing to hp")
	finish()
