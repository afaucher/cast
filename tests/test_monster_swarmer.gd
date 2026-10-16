extends MonsterTestBase
## Swarmers: fast, reach the hero, bite, don't all stack on one point.


func setup() -> void:
	new_world(flat_map(12))
	var hero := add_hero(Vector2i(0, 0))
	var imps: Array[Monster] = []
	var ring := Hex.ring(Vector2i.ZERO, 4)
	for i in 5:
		imps.append(MonsterFactory.spawn("swarmer", ring[i]))
	eq(imps.size(), 5, "pack of five")
	for m in imps:
		check(m.move_speed > 5.0, "fast")
	await wait_until(func() -> bool: return hero.hp < 100.0, 240)
	check(hero.hp < 100.0, "a swarmer bit the hero")
	near(fmod(100.0 - hero.hp, 4.0), 0.0, 0.01, "bites are 4")
	await frames(180)
	check(hero.hp <= 84.0, "the pack keeps biting (hp %.1f)" % hero.hp)
	var close := 0
	var min_sep := 99.0
	for i in imps.size():
		if fdist(imps[i], hero) < 2.8:
			close += 1
		for j in range(i + 1, imps.size()):
			min_sep = minf(min_sep, fdist(imps[i], imps[j]))
	check(close >= 4, "pack surrounds the hero (%d close)" % close)
	check(min_sep > 0.25, "imps spread out instead of stacking (min sep %.2f)" % min_sep)
	finish()
