extends TestCase
## Hero melee (arc, reach, cooldown), ranged bolt (weaker than melee), slots,
## downed state, and the ally brain following / fighting.

var root: Node3D


func _flat_map(radius: int = 8) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 0)
	return m


func _dummy(pos: Vector3, hp: float = 500.0) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.max_hp = hp
	GameWorld.spawn(d, pos)
	d.snap_to_ground()
	return d


func setup() -> void:
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(_flat_map(), root)
	var hero := HeroFactory.spawn_hero(Vector2i(0, 0), "Tester", Color.BLUE)
	var origin := hero.global_position

	# --- Melee: front hit, behind and out of reach untouched.
	var front := _dummy(origin + Vector3(1.2, 0, 0))
	var behind := _dummy(origin + Vector3(-1.2, 0, 0))
	var far := _dummy(origin + Vector3(3.5, 0, 0.2))
	var side := _dummy(origin + Vector3(0.1, 0, 1.3))     # ~85 deg off: outside the 100 deg arc
	check(hero.melee(Vector3.RIGHT), "melee fires")
	near(front.hp, front.max_hp - Hero.MELEE_DAMAGE, 0.01, "front dummy took melee damage")
	near(behind.hp, behind.max_hp, 0.01, "dummy behind untouched")
	near(far.hp, far.max_hp, 0.01, "dummy out of reach untouched")
	near(side.hp, side.max_hp, 0.01, "dummy outside the arc untouched")
	check(not hero.melee(Vector3.RIGHT), "melee cooldown blocks an immediate recast")
	near(front.hp, front.max_hp - Hero.MELEE_DAMAGE, 0.01, "no extra damage during cooldown")
	await frames(int(Hero.MELEE_COOLDOWN * 60.0) + 2)
	check(hero.melee(Vector3.RIGHT), "melee ready again after the cooldown")
	near(front.hp, front.max_hp - 2.0 * Hero.MELEE_DAMAGE, 0.01, "second hit lands")
	check(hero.cooldown_left(Hero.KEY_MELEE) > 0.0, "cooldown_left reports the melee cooldown")

	# --- Ranged: weaker than melee, with its own cooldown.
	front.queue_free()
	behind.queue_free()
	far.queue_free()
	side.queue_free()
	await frames(2)
	var target := _dummy(origin + Vector3(5.0, 0, 0))
	check(hero.shoot(Vector3.RIGHT), "ranged fires")
	check(not hero.shoot(Vector3.RIGHT), "ranged cooldown blocks")
	await frames(60)
	near(target.hp, target.max_hp - Hero.RANGED_DAMAGE, 0.01, "bolt damage")
	check(Hero.RANGED_DAMAGE < Hero.MELEE_DAMAGE * 0.6, "ranged is noticeably weaker than melee")
	check(Hero.RANGED_DAMAGE / Hero.RANGED_COOLDOWN < Hero.MELEE_DAMAGE / Hero.MELEE_COOLDOWN, "ranged dps below melee dps")
	target.queue_free()

	# --- Spell slots and cooldown.
	hero.spell_slots = ["heal", "corn"]
	check(not hero.try_cast("fireball", 1.0, origin + Vector3.RIGHT), "refuses a spell that is not slotted")
	check(hero.try_cast("heal", 1.0, origin), "slotted spell casts")
	check(not hero.try_cast("heal", 1.0, origin), "cooldown blocks the recast")
	near(hero.cooldown_left("heal"), SpellBook.cooldown_of("heal") / SpellComponents.HELD_COOLDOWN_DIV, 0.1, "cooldown_left right after cast (slot 1 is held: cooldown / 1.15)")
	near(hero.cooldown_left("corn"), 0.0, 0.001, "other slot unaffected")
	check(not hero.try_cast("nonsense", 1.0, origin), "unknown spell id refused")

	# --- Downed.
	hero.apply_damage(9999.0)
	check(hero.dead, "hero goes down at 0 hp")
	check(not hero.melee(Vector3.RIGHT), "downed hero cannot attack")
	check(not hero.try_cast("corn", 1.0, origin), "downed hero cannot cast")
	check(GameWorld.team_actors(GameWorld.TEAM_HEROES).is_empty(), "downed hero drops out of world queries")
	hero.queue_free()
	await frames(2)

	await _ally_tests()
	finish()


func _ally_tests() -> void:
	# Follow: an ally far from the leader walks back to within follow range.
	var leader := HeroFactory.spawn_hero(Vector2i(0, 0), "Leader", Color.BLUE)
	var ally := HeroFactory.spawn_hero(Vector2i(-6, 3), "Follower", Color.ORANGE)
	HeroFactory.make_ally(ally, leader, false, 2.4)
	await frames(60 * 4)
	var follow_d := GameWorld.flat_distance(ally.global_position, leader.global_position)
	check(follow_d < AllyBrain.FORMATION_HEX_MAX * AllyBrain.HEX_STEP + 1.0, "ally follows the leader (%.1f units)" % follow_d)
	check(follow_d > AllyBrain.FORMATION_HEX_MIN * AllyBrain.HEX_STEP - 1.0, "ally settles at its formation distance, not on top of the leader (%.1f)" % follow_d)

	# Fight: a melee ally kills a nearby dummy; a ranged ally shoots one from range. The leader starts each fight (a dent:
	# the restraint baseline only joins fights already started, AllyBrain).
	var d1 := _dummy(leader.global_position + Vector3(3.0, 0, 0), 60.0)
	d1.apply_damage(1.0, leader)
	await frames(60 * 4)
	check(d1.dead or d1.hp < d1.max_hp, "melee ally engages a nearby monster")
	check(GameWorld.flat_distance(ally.global_position, leader.global_position) < AllyBrain.LEASH + 1.0, "ally stays on its leash")
	d1.queue_free()

	var archer := HeroFactory.spawn_hero(Vector2i(0, 2), "Archer", Color.PURPLE, "staff")
	HeroFactory.make_ally(archer, leader, true, 3.9)
	var d2 := _dummy(leader.global_position + Vector3(-6.0, 0, -2.0), 200.0)
	d2.apply_damage(1.0, leader)
	await frames(60 * 4)
	check(d2.hp < d2.max_hp, "ranged ally hurts a distant monster")
	check(GameWorld.flat_distance(archer.global_position, d2.global_position) > 1.5, "ranged ally keeps its distance")

	# Leash: a monster far from the leader is ignored.
	var far := _dummy(leader.global_position + Vector3(0, 0, 7.5), 100.0)
	far.global_position = Hex.to_world(Vector2i(-3, 7))
	far.apply_damage(1.0, leader)   # (in the fight, but too far from the leader)
	var before := far.hp
	await frames(60 * 2)
	check(GameWorld.flat_distance(ally.global_position, leader.global_position) < AllyBrain.LEASH + 1.0, "ally does not wander off after far monsters")
	near(far.hp, before, 0.01, "far monster ignored")
