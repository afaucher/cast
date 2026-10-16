extends MonsterTestBase
## Grunt: idles out of range / without LOS, then chases + damages; paths around a wall.


func setup() -> void:
	# --- A: hero out of aggro range -> stays idle ---------------------------------------
	new_world(flat_map(12))
	var hero := add_hero(Vector2i(6, 0))                       # ~10.4 units away
	var grunt := MonsterFactory.spawn("grunt", Vector2i(0, 0))
	eq(grunt.team, GameWorld.TEAM_MONSTERS, "monster team")
	check(grunt.aggro_range < 10.0, "aggro range below distance")
	var start := grunt.global_position
	await frames(90)
	eq(grunt.state, Monster.State.IDLE, "idle when hero out of range")
	check(grunt.global_position.distance_to(start) < 0.01, "did not move")
	near(hero.hp, 100.0, 0.001, "hero untouched (out of range)")
	check(not grunt.is_hp_bar_visible(), "hp bar hidden when undamaged")

	# --- B: hero in range but behind a wall -> still idle -------------------------------
	var map_b := flat_map(12)
	wall_where(map_b, func(p: Vector3) -> bool: return absf(p.x - 3.46) < 0.5 and absf(p.z) < 1.0)
	new_world(map_b)
	hero = add_hero(Vector2i(4, 0))                            # 6.9 units away, wall at (2,0)
	grunt = MonsterFactory.spawn("grunt", Vector2i(0, 0))
	await frames(90)
	eq(grunt.state, Monster.State.IDLE, "idle with no line of sight")
	near(hero.hp, 100.0, 0.001, "hero untouched behind wall")

	# --- C: hero visible -> chase -> windup telegraph -> damage -------------------------
	new_world(flat_map(12))
	hero = add_hero(Vector2i(4, 0))
	grunt = MonsterFactory.spawn("grunt", Vector2i(0, 0))
	var seen_windup := false
	var windup_before_hit := false
	for i in 400:
		await get_tree().physics_frame
		if grunt.state == Monster.State.ATTACK:
			seen_windup = true
		if hero.hp < 100.0:
			windup_before_hit = seen_windup
			break
	check(hero.hp < 100.0, "grunt damaged the hero")
	check(windup_before_hit, "a visible windup (ATTACK state) preceded the first hit")
	near(hero.hp, 90.0, 0.001, "one grunt hit is 10")
	check(fdist(grunt, hero) < 2.0, "grunt closed in")
	# It keeps swinging on cooldown.
	await frames(200)
	check(hero.hp <= 80.0, "repeated hits on cooldown")

	# --- D: damage wakes an idle grunt; it paths around a wall ---------------------------
	var map_d := flat_map(12)
	wall_where(map_d, func(p: Vector3) -> bool: return absf(p.x - 3.5) < 1.0 and absf(p.z) < 6.0)
	new_world(map_d)
	hero = add_hero(Vector2i(4, 0))                            # other side of the wall
	grunt = MonsterFactory.spawn("grunt", Vector2i(0, 0))
	await frames(30)
	eq(grunt.state, Monster.State.IDLE, "walled off: idle")
	check(map_d.find_path(Vector2i(0, 0), Vector2i(4, 0)).size() > 6, "route exists but is long")
	grunt.apply_damage(1.0, hero)                              # hero plinks it
	check(grunt.is_hp_bar_visible(), "hp bar shows once damaged")
	var max_z := 0.0
	for i in 1500:
		await get_tree().physics_frame
		max_z = maxf(max_z, absf(grunt.global_position.z))
		if hero.hp < 100.0:
			break
	check(hero.hp < 100.0, "grunt reached the hero around the wall")
	check(max_z > 5.0, "it walked around the wall end (max |z| = %.1f)" % max_z)
	finish()
