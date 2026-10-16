extends MonsterTestBase
## Death: `died` fires, the corpse animates then frees itself, and it stops mattering.


func setup() -> void:
	new_world(flat_map(8))
	var hero := add_hero(Vector2i(0, 0))
	var grunt := MonsterFactory.spawn("grunt", Vector2i(5, 0))
	var died := [0]
	grunt.died.connect(func(): died[0] += 1)
	check(not grunt.is_hp_bar_visible(), "no bar before damage")
	grunt.apply_damage(10.0, hero)
	check(grunt.is_hp_bar_visible(), "bar after damage")
	eq(grunt.state, Monster.State.CHASE, "damage aggros")
	grunt.apply_damage(999.0, hero)
	eq(died[0], 1, "died emitted once")
	check(grunt.dead, "dead flag")
	check(not GameWorld.actors().has(grunt), "dead monsters are not listed as actors")
	check(is_instance_valid(grunt), "death animation keeps the node briefly")
	grunt.apply_damage(5.0, hero)
	eq(died[0], 1, "no double death")
	await frames(120)
	check(not is_instance_valid(grunt), "freed after the death animation")

	# Every kind frees on death.
	for k in MonsterFactory.KINDS:
		var m := MonsterFactory.spawn(k, Vector2i(2, 1))
		m.apply_damage(9999.0, hero)
		await frames(120)
		check(not is_instance_valid(m), k + " freed on death")
	finish()
