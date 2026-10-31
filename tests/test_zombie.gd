extends MonsterTestBase
## The zombie (docs/design/haunted-build-plan.md, H3), solo: a slow melee shamble in the dead family that STAYS DOWN AS A BODY.
## - it spawns as the `zombie` kind wearing ZombieModel (mourner or digger from its spawn cell), slower and tougher than a
##   skeleton;
## - killed, it lies face down where it fell and stays (not freed, not an actor, out of "monsters": the pest count drops), the
##   downed query finds it, and it never gets up by itself;
## - Heal and Revive (allies only) leave it lying; Coffee's splash stands it up at CoffeeSpell.ZOMBIE_HP, not hasted, pushing
##   up over RISE_TIME, back among the monsters; killed again it lies again, its drops rolled only the first time;
## - a fireball's blast over a body burns it (the charred model, smoke), and a burnt body is out of the downed query and
##   never rises (coffee does nothing); a zombie that goes down burning is burnt;
## - burn_body does nothing to a living zombie or a downed hero, and a copy ignores revive and burn_body (its owner decides);
## - every other monster still dies and is freed; the gym's "Zombie (body)" puts a body down.


func setup() -> void:
	new_world(flat_map(10))
	var hero := add_hero(Vector2i(-3, 0))
	_spawn_and_look()
	await _down_and_stays(hero)
	await _raise_and_burn(hero)
	await _dies_burning(hero)
	_copies_and_heroes(hero)
	await _others_free(hero)
	await _gym_body()
	finish()


func _spawn_and_look() -> void:
	var z := MonsterFactory.spawn("zombie", Vector2i(2, 0)) as Zombie
	if not check(z != null, "the zombie kind spawns a Zombie"):
		return
	eq(z.kind, "zombie", "its kind")
	eq(z.display_name, "Zombie", "its name")
	check(z.model is ZombieModel, "it wears ZombieModel")
	eq(z.variant, Zombie.variant_for(Vector2i(2, 0)), "its look comes from its spawn cell")
	eq((z.model as ZombieModel).variant, z.variant, "... and the model is that variant")
	var grunt := MonsterFactory.spawn("grunt", Vector2i(2, 2))
	check(z.move_speed < grunt.move_speed * 0.6 and z.max_hp > grunt.max_hp, "slower and tougher than a skeleton (%.1f vs %.1f speed, %.0f vs %.0f HP)" % [z.move_speed, grunt.move_speed, z.max_hp, grunt.max_hp])
	check(z.attack_windup > grunt.attack_windup, "a longer, readable wind-up")
	var looks := {}
	for q in range(-6, 7):
		for r in range(-6, 7):
			looks[Zombie.variant_for(Vector2i(q, r))] = true
	check(looks.has("mourner") and looks.has("digger"), "both looks turn up across a floor")
	z.free()
	grunt.free()


func _down_and_stays(hero: Actor) -> void:
	var z := MonsterFactory.spawn("zombie", Vector2i(3, 0)) as Zombie
	z.aggro_range = 0.0
	var died := [0]
	z.died.connect(func() -> void: died[0] += 1)
	check(z.is_in_group("monsters"), "a standing zombie is a monster (the pest count)")
	z.apply_damage(9999.0, hero)
	eq(died[0], 1, "it dies once")
	await frames(150)
	check(is_instance_valid(z) and z.dead, "it stays on the floor as a body (not freed)")
	check(z.is_downed() and z.is_body(), "downed: a body that can get up")
	check((z.model as ZombieModel).is_lying(), "lying face down")
	check((z.model as ZombieModel).rise_fx != null and (z.model as ZombieModel).rise_fx.visible, "the motes rise off it (it can get up)")
	check(not GameWorld.actors().has(z) and not z.is_in_group("monsters"), "not an actor, not a monster: the pest count drops")
	check(GameWorld.downed_in_radius(z.global_position, 1.0).has(z), "the downed query finds the body")
	check(not GameWorld.downed_in_radius(z.global_position, 1.0, GameWorld.TEAM_HEROES).has(z), "... but not as an ally of the crew")
	check(z._dropped, "its drops were rolled")
	z.apply_damage(5.0, hero)
	eq(died[0], 1, "a body takes no more hits")
	await frames(300)
	check(z.dead and not z.is_rising(), "it never gets up by itself")
	z.queue_free()
	await frames(2)


func _raise_and_burn(hero: Actor) -> void:
	var z := MonsterFactory.spawn("zombie", Vector2i(3, 1)) as Zombie
	z.aggro_range = 0.0
	z.apply_damage(9999.0, hero)
	await frames(5)
	var at := z.global_position
	# Heal and Revive are allies-only: the body stays down.
	HealSpell.cast(hero, 1.0, at, 0.0, {})
	ReviveSpell.cast(hero, 1.0, at, 0.0, {})
	await frames(5)
	check(z.dead, "Heal and Revive leave a zombie's body lying (allies only)")
	# Coffee's splash raises it.
	var rises := [0]
	z.revived.connect(func(_c: bool) -> void: rises[0] += 1)
	Coffee.cast(hero, 1.0, at)
	check(not z.dead, "Coffee raises the body")
	near(z.hp, CoffeeSpell.ZOMBIE_HP, 0.001, "at the coffee zombie's HP")
	check(not Coffee.is_hasted(z), "not hasted (the living drink first)")
	check(z.is_in_group("monsters") and GameWorld.actors().has(z), "a monster again (the pest count is back up)")
	check(z.is_rising() and z.is_helpless(), "it pushes itself up, helpless meanwhile")
	eq(rises[0], 1, "revived once")
	await frames(int(Zombie.RISE_TIME * 60.0) + 10)
	check(not z.is_rising() and not (z.model as ZombieModel).is_lying() and not z.is_helpless(), "it stands")
	eq(z.raises, 1, "one rise")
	# Down again: a body again, the drops not rolled twice.
	z.apply_damage(9999.0, hero)
	await frames(30)
	check(is_instance_valid(z) and z.dead and z.is_downed(), "killed again, it lies again")
	# A fireball's blast over it burns it, and a burnt body never rises.
	var burns := [0]
	z.burnt_down.connect(func() -> void: burns[0] += 1)
	Burning.on_blast(z.global_position + Vector3(0.5, 0, 0), 2.0, 1.0, hero)
	check(z.burnt, "a fireball's blast over the body burns it")
	eq(burns[0], 1, "burnt once")
	check((z.model as ZombieModel).charred, "the charred look")
	await frames(2)
	check(not z.is_downed() and not GameWorld.downed_in_radius(z.global_position, 1.0).has(z), "a burnt body is out of the downed query")
	Coffee.cast(hero, 1.0, z.global_position)
	await frames(2)
	check(z.dead, "coffee does not raise a burnt body")
	check(not z.revive(z.max_hp), "nor does any raise (an acolyte's, H4)")
	check(not z.burn_body(hero), "it burns once")
	z.queue_free()
	await frames(2)


func _dies_burning(hero: Actor) -> void:
	var z := MonsterFactory.spawn("zombie", Vector2i(4, -1)) as Zombie
	z.aggro_range = 0.0
	check(Burning.ignite(z, hero, 8.0) != null, "a standing zombie catches fire like anyone")
	z.apply_damage(9999.0, hero)
	await frames(2)
	check(z.dead and z.burnt and (z.model as ZombieModel).charred, "a zombie that goes down burning is burnt")
	check(not z.revive(50.0), "and stays down")
	z.queue_free()
	# A fire lit on a body (Burning.ignite) burns it too.
	var b := MonsterFactory.spawn("zombie", Vector2i(4, 1)) as Zombie
	b.aggro_range = 0.0
	b.apply_damage(9999.0, hero)
	check(Burning.ignite(b, hero, 6.0) == null and b.burnt, "a fire lit on a body burns it (no flames on a body)")
	b.queue_free()
	await frames(2)


func _copies_and_heroes(hero: Actor) -> void:
	var z := MonsterFactory.spawn("zombie", Vector2i(-2, 3)) as Zombie
	z.aggro_range = 0.0
	check(not z.burn_body(hero), "a standing zombie does not burn down (it is not a body)")
	z.apply_damage(9999.0, hero)
	Net.make_copy(z)
	check(not z.revive(z.max_hp), "a copy ignores revive (its owner applies it)")
	check(not z.burn_body(hero), "... and burn_body")
	z.free()
	var h := add_hero(Vector2i(-4, 3))
	h.die()
	check(not h.burn_body(null), "a plain downed actor does not burn down")
	h.free()


func _others_free(hero: Actor) -> void:
	for k: String in ["grunt", "archer", "brute"]:
		var m := MonsterFactory.spawn(k, Vector2i(-1, -3))
		m.apply_damage(9999.0, hero)
		await frames(120)
		check(not is_instance_valid(m), "%s still dies and is freed" % k)


func _gym_body() -> void:
	var e := GymSpawns.find("monster:zombie:body")
	if not check(not e.is_empty() and str(e["skip"]) == "", "the gym has a zombie body button"):
		return
	var out := GymSpawns.spawn(e, Vector3.ZERO, 1, null, null)
	if check(out.size() == 1 and out[0] is Zombie, "it spawns a zombie"):
		var z := out[0] as Zombie
		await frames(5)
		check(z.dead and z.is_downed(), "... down as a body")
		z.queue_free()
	check(not GymSpawns.find("monster:zombie").is_empty(), "and a standing zombie button")
