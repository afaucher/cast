extends MonsterTestBase
## Restless idle life, step 2 (docs/design/monster-awareness.md): archer target practice and brute fights.
##
## Archers: practice on a cheap prop in sight (its ordinary arrow: 8 per hit), at most 2 practice hits a prop and never a
## break; the price limit before R 0.5; never with a hero within its sight, never at a prop in the crew's room, never
## without line of sight; a "?" ends a draw at once; a hero who steps into the arrow is hit like by any arrow; and a whole
## restless floor (R 1, minutes of floor time) never bills a practice break.
## Brutes: no fight before 2 minutes (R 0), p = 0.15 x R^2; a fight walks, squares off and trades 3-5 slams that shove
## but never change anyone's HP (not even against the void or a wall); its noise draws onlookers; a sighting, a noise or a
## hit breaks it up (both CHASE, worked up); a brute alone bullies a skeleton; the 28-unit relevance limit.

const PRACTICE_WAIT := 60 * 30


func _init() -> void:
	timeout_sec = 4000.0   # (game seconds: a restless floor needs minutes of floor time)


func setup() -> void:
	MonsterSenses.restless_override = 1.0
	await _check_practice()
	await _check_practice_price()
	await _check_practice_safety()
	await _check_practice_hits_hero()
	await _check_practice_suspicion()
	await _check_fight_rate()
	await _check_fight()
	await _check_fight_breakups()
	await _check_bully()
	await _check_relevance()
	await _check_restless_floor()
	MonsterSenses.restless_override = -1.0
	finish()


## room:1 west (x <= -2), a corridor (|x| < 2, walls beyond |z| 1.5), room:2 east (x >= 2). Radius 16.
func _rooms() -> HexMap:
	var map := flat_map(16)
	for c in map.cells.keys():
		var p := Hex.to_world(c)
		if absf(p.x) < 2.0 and absf(p.z) > 1.5:
			map.set_cell(c, 12, HexMap.Tile.WALL)
			continue
		map.get_cell(c).tag = "room:1" if p.x <= -2.0 else ("room:2" if p.x >= 2.0 else "corridor")
	return map


func _prop(kind: String, cell: Vector2i) -> PricedProp:
	var p := PricedProp.spawn(cell, kind, {})
	return p


## An archer at (-14, 0) (x -24.2) facing east, a prop at (-10, 0) (x -17.3, 6.9 away), the crew in the corridor (24.2
## away: inside the 28-unit relevance range, beyond its 16-unit sight).
func _range(kind: String = "crystal_lamp", hero_cell: Vector2i = Vector2i(0, 0)) -> Array:
	new_world(_rooms())
	Ledger.begin_contract(1000000)
	var hero := add_hero(hero_cell)
	var a = MonsterFactory.spawn("archer", Vector2i(-14, 0))
	a.set_spawn_facing(Vector3.RIGHT)
	var p := _prop(kind, Vector2i(-10, 0))
	return [a, p, hero]


func _check_practice() -> void:
	var s := _range()
	var a = s[0]
	var p: PricedProp = s[1]
	var shot := await wait_until(func() -> bool: return a.practice_shots >= 1, PRACTICE_WAIT)
	check(shot, "an idle archer near the crew practises on the lamp")
	await frames(60)
	near(p.hp, p.max_hp - 8.0, 0.01, "its ordinary arrow chips the lamp (8)")
	eq(a.state, Monster.State.IDLE, "practice is idle life")
	await wait_until(func() -> bool: return a.practice_shots >= 2, PRACTICE_WAIT)
	await frames(60 * 60)
	eq(a.practice_shots, 2, "at most %d practice hits a prop" % a.PRACTICE_HITS_PER_PROP)
	near(p.hp, p.max_hp - 16.0, 0.01, "two chips")
	check(not p.dead, "it never breaks")
	eq(Ledger.damages(), 0, "and nothing is billed")
	# A prop the next arrow would break: never.
	s = _range()
	a = s[0]
	p = s[1]
	p.apply_damage(p.max_hp - 8.5, null)                             # 8.5 HP left: an arrow would leave 0.5
	await frames(60 * 30)
	eq(a.practice_shots, 0, "no practice on a prop the next arrow would break")


func _check_practice_price() -> void:
	MonsterSenses.restless_override = 0.0
	var s := _range("gold_toilet")
	var a = s[0]
	await frames(60 * 90)
	eq(a.practice_shots, 0, "before R 0.5: never the $15,000 toilet (90 s)")
	s = _range("crystal_lamp")
	a = s[0]
	var shot := await wait_until(func() -> bool: return a.practice_shots >= 1, 60 * 90)
	check(shot, "... but the $600 lamp, every ~40 s")
	MonsterSenses.restless_override = 0.5
	s = _range("gold_toilet")
	a = s[0]
	shot = await wait_until(func() -> bool: return a.practice_shots >= 1, 60 * 60)
	check(shot, "from R 0.5 any prop")
	MonsterSenses.restless_override = 1.0


func _check_practice_safety() -> void:
	# A hero within its sight (15.6 behind it: unseen, but within 16): no practice.
	var s := _range("crystal_lamp", Vector2i(-5, 0))
	var a = s[0]
	a.set_spawn_facing(Vector3.LEFT)                                # (looking away: it doesn't see the hero, it is just near)
	await frames(60 * 40)
	eq(a.practice_shots, 0, "never with a hero within 16")
	# The crew in the prop's room (far from the archer): no practice.
	new_world(_rooms())
	add_hero(Vector2i(-4, 2))                                       # room:1, 19 from the archer
	a = MonsterFactory.spawn("archer", Vector2i(-14, 0))
	a.set_spawn_facing(Vector3.RIGHT)
	_prop("crystal_lamp", Vector2i(-10, 0))
	await frames(60 * 40)
	eq(a.practice_shots, 0, "never at a prop in the crew's room")
	# No line of sight (a pillar in the way): no practice.
	var map := _rooms()
	map.set_cell(Vector2i(-12, 0), 12, HexMap.Tile.WALL)
	new_world(map)
	add_hero(Vector2i(0, 0))
	a = MonsterFactory.spawn("archer", Vector2i(-14, 0))
	a.set_spawn_facing(Vector3.RIGHT)
	_prop("crystal_lamp", Vector2i(-10, 0))
	await frames(60 * 40)
	eq(a.practice_shots, 0, "never without line of sight")
	# Somebody in the lane at release (an employee, a monster): it holds its shot.
	s = _range()
	a = s[0]
	var blocker := MonsterFactory.spawn("grunt", Vector2i(-12, 0))
	blocker.aggro_range = 0.0
	await frames(60 * 40)
	eq(a.practice_shots, 0, "never with something else in the lane")
	# Frozen (aggro 0): no idle life at all.
	s = _range()
	a = s[0]
	a.aggro_range = 0.0
	await frames(60 * 40)
	eq(a.practice_shots, 0, "a frozen archer never practises")


func _check_practice_hits_hero() -> void:
	var s := _range()
	var a = s[0]
	var p: PricedProp = s[1]
	var shot := await wait_until(func() -> bool: return a.practice_shots >= 1, PRACTICE_WAIT)
	check(shot, "it shoots")
	# Step into the arrow's path right after it was loosed (4 units out; the arrow is still at the archer). The archer
	# sees almost nothing here, so the hit is the practice arrow's, not a fight's.
	a.aggro_range = 0.001
	var walker := add_hero(Vector2i(-12, 0))
	walker.global_position = a.global_position + Vector3.RIGHT * 4.0
	await frames(40)
	near(walker.hp, walker.max_hp - 8.0, 0.01, "a hero who steps into a practice arrow is hit like by any arrow")
	near(p.hp, p.max_hp, 0.01, "and the lamp is spared")


func _check_practice_suspicion() -> void:
	var s := _range()
	var a = s[0]
	var drawing := await wait_until(func() -> bool: return a._practice_draw >= 0.0, PRACTICE_WAIT)
	check(drawing, "it draws on the lamp")
	check(a._telegraph >= 0.0, "the draw shows (the telegraph)")
	a.hear(Hex.to_world(Vector2i(-14, 4)))
	await frames(2)
	eq(a.state, Monster.State.SUSPICIOUS, "a sound: suspicious")
	check(a._practice_draw < 0.0 and a._telegraph <= 0.0, "the draw is dropped at once")
	await frames(60)
	eq(a.practice_shots, 0, "no shot")


# --- Brute fights -----------------------------------------------------------------------------------------------------------

## Two brutes in room:1 near its west edge (the void beyond), a skeleton watching from 8 away, the crew in the corridor.
func _arena() -> Array:
	new_world(_rooms())
	var hero := add_hero(Vector2i(0, 0))
	var b1 = MonsterFactory.spawn("brute", Vector2i(-12, -2))
	var b2 = MonsterFactory.spawn("brute", Vector2i(-13, 2))
	var watcher := MonsterFactory.spawn("grunt", Vector2i(-8, 0))
	b1.set_spawn_facing(Vector3.LEFT)
	b2.set_spawn_facing(Vector3.LEFT)
	watcher.set_spawn_facing(Vector3.LEFT)
	watcher.aggro_range = 0.001                                     # (it hears, but never patrols into the crew and fights)
	hero.set_modifier("ward", 0.0, 9999.0)
	return [b1, b2, watcher, hero]


func _check_fight_rate() -> void:
	near(float(_brute_script().get("FIGHT_P")), 0.15, 0.0001, "p = 0.15 x R^2 per roll")
	MonsterSenses.restless_override = -1.0
	var s := _arena()
	var b1 = s[0]
	var b2 = s[1]
	await frames(60 * 110)
	near(MonsterSenses.restlessness(), 0.0, 0.0001, "R is 0 for the first 2 minutes")
	eq(b1.fights_started + b2.fights_started, 0, "no brute fight in the first 2 minutes")
	MonsterSenses.restless_override = 1.0
	s = _arena()
	b1 = s[0]
	b2 = s[1]
	var started := await wait_until(func() -> bool: return b1.fights_started + b2.fights_started > 0, 60 * 240)
	check(started, "at R 1 two idle brutes pick a fight within 4 minutes")


func _brute_script() -> GDScript:
	return MonsterFactory.SCRIPTS["brute"]


func _check_fight() -> void:
	var s := _arena()
	var b1 = s[0]
	var b2 = s[1]
	var watcher: Monster = s[2]
	await frames(2)
	var monsters: Array = [b1, b2, watcher]
	var start_pos: Array[Vector3] = [b1.global_position, b2.global_position]
	b1._start_fight(b2)
	var strikes0: int = b1.strikes + b2.strikes
	var saw_ring := false
	var watcher_sus := false
	var min_hp := INF
	var moved := 0.0
	var ended := false
	for _f in 60 * 30:
		await get_tree().physics_frame
		for m in monsters:
			min_hp = minf(min_hp, m.hp / m.max_hp)
		saw_ring = saw_ring or b1._telegraph > 0.5 or b2._telegraph > 0.5
		watcher_sus = watcher_sus or watcher.state == Monster.State.SUSPICIOUS
		moved = maxf(moved, GameWorld.flat_distance(b2.global_position, start_pos[1]))
		if not b1.is_fighting():
			ended = true
			break
	check(ended, "the fight ends on its own")
	var slams: int = b1.strikes + b2.strikes - strikes0
	check(slams >= b1.FIGHT_SLAMS_MIN and slams <= b1.FIGHT_SLAMS_MAX, "3-5 slams (%d)" % slams)
	check(b1.strikes - strikes0 >= 1 and b2.strikes > 0, "two brutes take turns")
	check(saw_ring, "with the slam's telegraph")
	near(min_hp, 1.0, 0.0001, "nobody lost any HP")
	check(not b1.dead and not b2.dead and not watcher.dead, "nobody fell into the void")
	check(watcher_sus, "the noise made the skeleton suspicious (it comes to watch)")
	check(b1.state == Monster.State.IDLE or b1.state == Monster.State.RETURN, "the brutes go back to rest (%s)" % b1.state_name())


func _check_fight_breakups() -> void:
	# A sighting: put the crew in front of them mid-fight.
	var s := _arena()
	var b1 = s[0]
	var b2 = s[1]
	var hero: Actor = s[3]
	await frames(2)
	b1._start_fight(b2)
	var slamming := await wait_until(func() -> bool: return b1._fight_phase == b1.FIGHT_SLAMS, 60 * 15)
	check(slamming, "they trade slams")
	hero.global_position = b1.global_position + Vector3(5.0, 0.0, 0.0)
	var broke := await wait_until(func() -> bool: return b1.state == Monster.State.CHASE and b2.state == Monster.State.CHASE, 60)
	check(broke, "a hero sighting breaks it up: both chase")
	check(b1.has_modifier("worked_up") and b2.has_modifier("worked_up"), "... worked up")
	near(b1.move_speed_mult(), 1.2, 0.001, "+20% speed")
	near(b1.modifier_left("worked_up"), 10.0, 0.3, "for 10 s")
	# A noise.
	s = _arena()
	b1 = s[0]
	b2 = s[1]
	await frames(2)
	b1._start_fight(b2)
	await wait_until(func() -> bool: return b1._fight_phase == b1.FIGHT_SQUARE, 60 * 15)
	MonsterSenses.noise(b2.global_position + Vector3(2, 0, 0), 6.0, "test")
	await frames(1)
	check(b1.state == Monster.State.CHASE and b2.state == Monster.State.CHASE, "a noise breaks it up")
	# A hit.
	s = _arena()
	b1 = s[0]
	b2 = s[1]
	hero = s[3]
	await frames(2)
	b1._start_fight(b2)
	await wait_until(func() -> bool: return b1._fight_phase == b1.FIGHT_SQUARE, 60 * 15)
	b2.apply_damage(1.0, hero)
	await frames(1)
	check(b1.state == Monster.State.CHASE and b2.state == Monster.State.CHASE, "a hit breaks it up")
	eq(b1.target, hero, "... and both go for the attacker")


func _check_bully() -> void:
	new_world(_rooms())
	add_hero(Vector2i(0, 0))
	var b = MonsterFactory.spawn("brute", Vector2i(-12, 0))
	var g := MonsterFactory.spawn("grunt", Vector2i(-9, 2))
	b.set_spawn_facing(Vector3.LEFT)
	g.set_spawn_facing(Vector3.LEFT)
	await frames(2)
	eq(b._find_rival(), g, "no other brute: it bullies the skeleton within 12")
	b._start_fight(g)
	var g0 := g.global_position
	var slams0: int = b.strikes
	var moved := 0.0
	var min_hp := 1.0
	for _f in 60 * 30:
		await get_tree().physics_frame
		moved = maxf(moved, GameWorld.flat_distance(g.global_position, g0))
		min_hp = minf(min_hp, g.hp / g.max_hp)
		if not b.is_fighting():
			break
	check(b.strikes - slams0 >= 3, "it slams the skeleton (%d)" % (b.strikes - slams0))
	check(moved > 0.5, "the skeleton is thrown about (%.2f)" % moved)
	near(min_hp, 1.0, 0.0001, "but loses no HP")
	# Too far: no bully.
	new_world(_rooms())
	add_hero(Vector2i(0, 0))
	b = MonsterFactory.spawn("brute", Vector2i(-14, 0))
	MonsterFactory.spawn("grunt", Vector2i(-5, 6))                  # 18+ away
	await frames(2)
	check(b._find_rival() == null, "no skeleton within 12: no fight")


func _check_relevance() -> void:
	new_world(_rooms())
	add_hero(Vector2i(14, 0))                                       # 45+ from the brutes
	var b1 = MonsterFactory.spawn("brute", Vector2i(-12, -2))
	var b2 = MonsterFactory.spawn("brute", Vector2i(-13, 2))
	await frames(60 * 200)
	eq(b1.fights_started + b2.fights_started, 0, "no fights with the crew beyond 28")


# --- A whole restless floor ---------------------------------------------------------------------------------------------

## R 1 for minutes on real floors: archers practise and everything else is frozen; the crew stand-in moves between the
## corridor cells far from every archer (so no fight ever starts and every arrow is a practice arrow). No practice break,
## no bill, never more than 2 practice hits on a prop.
func _check_restless_floor() -> void:
	var shots := 0
	var bills := 0
	var broken := 0
	var worst_hits := 0
	var floors := 0
	for row in [["prepper", 2, 1], ["guru", 7, 2], ["supervillain", 3, 3], ["founder", 11, 1]]:
		var run := ContractRun.make(row[0], row[1], 0.5)
		var map := DungeonGen.for_run(run, row[2])
		new_world(map)
		GameWorld.begin(map, world, run.floor_seed(row[2]))
		Ledger.begin_contract(1000000)
		var site := SiteBuilder.build(map, run, row[2])
		var archers: Array = []
		for n in get_tree().get_nodes_in_group("monsters"):
			if n.kind == "archer":
				n.aggro_range = 0.001                                # (sees nothing: only its idle life runs)
				archers.append(n)
			else:
				n.aggro_range = 0.0                                  # frozen
		for pr in site.props:
			pr.broken.connect(func(_p: PricedProp, _c: Node) -> void: broken += 1)
		var spots: Array[Vector3] = []
		for c in map.cells_with_tag("corridor"):
			if not map.is_walkable_cell(c):
				continue
			var at := Hex.to_world(c, float(map.get_cell(c).level))
			var ok := true
			for a in archers:
				if GameWorld.flat_distance(a.global_position, at) < 12.0:
					ok = false
			for gate in site.gates:
				if GameWorld.flat_distance(gate.global_position, at) < Hellgate.ACTIVATE_RANGE + 2.0:
					ok = false   # (a woken gate's spawns would start real fights)
			if ok:
				spots.append(at)
		if archers.is_empty() or spots.is_empty():
			continue
		floors += 1
		var hero := add_hero(Vector2i.ZERO)
		hero.set_modifier("ward", 0.0, 9999.0)
		for k in 15:                                                 # 15 spots x 20 s = 300 s of floor time
			hero.global_position = spots[(k * 7) % spots.size()]
			await frames(60 * 20)
		for a in archers:
			shots += int(a.practice_shots)
		for pr in site.props:
			worst_hits = maxi(worst_hits, MonsterSenses.practice_hits(pr))
		bills += Ledger.damages()
	print("restless floors: %d floors, %d practice shots, %d props broken, $%d billed, at most %d practice hits on a prop" % [floors, shots, broken, bills, worst_hits])
	check(floors >= 3, "floors with archers measured (%d)" % floors)
	check(shots >= 3, "the archers practised (%d shots)" % shots)
	eq(broken, 0, "practice never broke a prop")
	eq(bills, 0, "and never billed one")
	check(worst_hits <= 2, "never more than 2 practice hits on a prop (%d)" % worst_hits)
