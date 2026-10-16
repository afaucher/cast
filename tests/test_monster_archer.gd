extends MonsterTestBase
## Archer: keeps its distance, needs LOS, arrows hurt.


func setup() -> void:
	# --- A: shoots from the firing band ---------------------------------------------------
	new_world(flat_map(12))
	var hero := add_hero(Vector2i(4, 0))                        # 6.9 away
	var archer := MonsterFactory.spawn("archer", Vector2i(0, 0))
	await wait_until(func() -> bool: return hero.hp < 100.0, 300)
	check(hero.hp < 100.0, "arrow hit the hero")
	near(fmod(100.0 - hero.hp, 8.0), 0.0, 0.01, "arrow damage is 8 each")
	var shots_before := hero.hp
	await frames(240)
	check(hero.hp < shots_before, "keeps shooting")
	var d := fdist(archer, hero)
	check(d >= 4.9 and d <= 8.2, "stays in the 5-8 band (d=%.2f)" % d)

	# --- B: hero in its face -> backs away and keeps shooting ------------------------------
	new_world(flat_map(12))
	hero = add_hero(Vector2i(2, 0))                             # 3.46 away (< 3.5)
	archer = MonsterFactory.spawn("archer", Vector2i(0, 0))
	archer.aggro(hero)
	await frames(150)
	d = fdist(archer, hero)
	check(d >= 4.8, "backed away from a close hero (d=%.2f)" % d)
	await frames(200)
	check(hero.hp < 100.0, "shot the hero while kiting")

	# --- C: no line of sight, no arrows ------------------------------------------------------
	var map_c := flat_map(12)
	wall_where(map_c, func(p: Vector3) -> bool: return absf(p.x - 3.5) < 1.0 and absf(p.z) < 6.0)
	new_world(map_c)
	hero = add_hero(Vector2i(4, 0))
	archer = MonsterFactory.spawn("archer", Vector2i(0, 0))
	await frames(150)
	eq(archer.state, Monster.State.IDLE, "idle without LOS")
	near(hero.hp, 100.0, 0.001, "no arrows through the wall (idle)")
	archer.aggro(hero)                                          # even when alerted it must not shoot through stone
	await frames(110)
	near(hero.hp, 100.0, 0.001, "no arrows through the wall (alerted)")
	var moved := GameWorld.flat_distance(archer.global_position, Hex.to_world(Vector2i(0, 0)))
	check(moved > 1.0, "it repositions to find a shot (moved %.1f)" % moved)
	await wait_until(func() -> bool: return hero.hp < 100.0, 1500)
	check(hero.hp < 100.0, "eventually gets a clear shot around the wall")
	finish()
