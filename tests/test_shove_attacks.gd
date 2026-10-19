extends TestCase
## Shoves built into attacks: every melee hit nudges its target (hero 0.7, monster 0.35, brute
## slam 1.0), Rebar's bowl (a boulder that shoves everything along its path, damages monsters
## only), Gasket's spin (360 degrees, 2.2 outward, monsters take damage), Rebar being immovable,
## and the AllyBrain using its secondary sensibly.

var root: Node3D


func _map(level_of: Callable = Callable()) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 10):
		var lv := 0
		if level_of.is_valid():
			lv = level_of.call(Hex.to_world(c).x)
		m.set_cell(c, lv)
	return m


func _fresh(level_of: Callable = Callable()) -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(_map(level_of), root, 9)


func _hero(pos: Vector3, secondary: String = "bolt") -> Hero:
	var h := Hero.new()
	h.secondary_kind = secondary
	GameWorld.spawn(h, pos)
	h.snap_to_ground()
	return h


func _dummy(pos: Vector3, hp: float = 1000.0) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.max_hp = hp
	GameWorld.spawn(d, pos)
	d.snap_to_ground()
	return d


func _hd(a: Node3D, b: Vector3) -> float:
	return GameWorld.flat_distance(a.global_position, b)


func setup() -> void:
	# --- Melee nudges.
	_fresh()
	var hero := _hero(Vector3.ZERO)
	var target := _dummy(Vector3(1.2, 0, 0))
	check(hero.melee(Vector3.RIGHT), "hero melee fires")
	await frames(40)
	near(target.global_position.x, 1.2 + Hero.MELEE_SHOVE, 0.08, "a hero's melee hit nudges its target about 0.7 away")
	near(target.global_position.z, 0.0, 0.05, "directly away from the attacker")
	near(target.hp, target.max_hp - Hero.MELEE_DAMAGE, 0.001, "the hit still damages")
	near(hero.global_position.x, 0.0, 0.0001, "the attacker does not move")
	_fresh()
	var grunt := MonsterFactory.spawn("grunt", Vector2i.ZERO) as Monster
	var victim := _hero(Vector3(1.0, 0, 0))
	grunt.aggro_range = 0.0            # stay idle: only the scripted strike lands
	grunt.facing = Vector3.RIGHT
	grunt._strike()
	await frames(30)
	near(victim.global_position.x, 1.0 + Monster.MELEE_SHOVE, 0.06, "a monster's melee nudges 0.35")
	near(victim.hp, victim.max_hp - grunt.attack_damage, 0.001, "and damages")
	_fresh()
	var brute := MonsterFactory.spawn("brute", Vector2i.ZERO) as Monster
	victim = _hero(Vector3(1.2, 0, 0))
	brute.aggro_range = 0.0
	brute._strike()
	await frames(30)
	near(victim.global_position.x, 1.2 + 1.0, 0.1, "the brute's slam shoves 1.0 outward")
	near(brute.shove_mult, 0.4, 0.0001, "brute shove_mult")
	near(MonsterFactory.spawn("swarmer", Vector2i(1, 0)).shove_mult, 1.5, 0.0001, "swarmer shove_mult")
	near(MonsterFactory.spawn("grunt", Vector2i(2, 0)).shove_mult, 1.0, 0.0001, "grunt shove_mult")
	near(MonsterFactory.spawn("archer", Vector2i(3, 0)).shove_mult, 1.0, 0.0001, "archer shove_mult")

	# --- Bowl: shoves EVERY actor it touches out of its path; monsters take damage, heroes none.
	_fresh()
	var rebar := _hero(Vector3(-6, 0, 0), "bowl")
	rebar.shove_mult = 0.0
	var m1 := _dummy(Vector3(-2.0, 0, 0.1))
	var ally := _hero(Vector3(1.0, 0, -0.2))
	var m2 := _dummy(Vector3(3.0, 0, 0.15))
	var off_path := _dummy(Vector3(-3, 0, 6.5))
	var beyond := _dummy(Vector3(7.5, 0, 0))             # past the bowl's range
	var before := {}
	for a in [m1, ally, m2, off_path, beyond]:
		before[a] = a.global_position
	check(rebar.shoot(Vector3.RIGHT), "the bowl is thrown")
	check(not rebar.shoot(Vector3.RIGHT), "and has a cooldown")
	near(rebar.cooldown_left(Hero.KEY_RANGED), Hero.BOWL_COOLDOWN, 0.05, "2 s cooldown")
	await frames(30)
	check(m1.is_shoved() or _hd(m1, before[m1]) > 0.5, "the boulder reaches the first monster quickly")
	await frames(110)
	for a in [m1, ally, m2]:
		var mv: Vector3 = a.global_position - before[a]
		check(mv.length() > 2.8 and mv.length() < 4.2, "%s was shoved about 3.5 (%.2f)" % [a.display_name, mv.length()])
		check(absf(mv.z) > 1.4, "and out of the boulder's path, sideways (%s dz=%.2f)" % [a.display_name, mv.z])
	near(m1.hp, m1.max_hp - Hero.BOWL_DAMAGE, 0.001, "monster takes 6")
	near(m2.hp, m2.max_hp - Hero.BOWL_DAMAGE, 0.001, "monster takes 6")
	near(ally.hp, ally.max_hp, 0.001, "a teammate takes no damage")
	near(rebar.hp, rebar.max_hp, 0.001, "nor does the thrower")
	near(off_path.global_position.distance_to(before[off_path]), 0.0, 0.0001, "off the path is untouched")
	near(beyond.global_position.distance_to(before[beyond]), 0.0, 0.0001, "past the range is untouched")
	check(rebar.cooldown_left(Hero.KEY_RANGED) == 0.0, "cooldown elapsed")
	check(rebar.shoot(Vector3.RIGHT), "and the bowl can be thrown again")
	await frames(10)

	# A heavy (brute-like) actor on the line is moved less.
	_fresh()
	rebar = _hero(Vector3(-6, 0, 0), "bowl")
	var light_m := _dummy(Vector3(-1.5, 0, 0.2))
	var heavy_m := _dummy(Vector3(2.0, 0, 0.2))
	heavy_m.shove_mult = 0.4
	var lp := light_m.global_position
	var hp0 := heavy_m.global_position
	rebar.shoot(Vector3.RIGHT)
	await frames(140)
	var light_d := _hd(light_m, lp)
	var heavy_d := _hd(heavy_m, hp0)
	near(heavy_d, light_d * 0.4, 0.3, "shove_mult 0.4 moves a monster 40%% as far (%.2f vs %.2f)" % [heavy_d, light_d])

	# The boulder stops at a +2 rise ...
	_fresh(func(x: float) -> int: return 2 if x > 1.5 else 0)
	rebar = _hero(Vector3(-4, 0, 0), "bowl")
	var behind_wall := _dummy(Vector3(3.5, 2 * Hex.LEVEL_HEIGHT, 0))
	rebar.shoot(Vector3.RIGHT)
	await frames(140)
	near(behind_wall.global_position.x, 3.5, 0.0001, "the bowl stops at a +2 rise and never reaches the plateau")
	# ... and drops down a ledge, still shoving what it finds below.
	_fresh(func(x: float) -> int: return 3 if x < 1.0 else 0)
	rebar = _hero(Hex.to_world(Vector2i(-1, 0), 3), "bowl")
	var below := _dummy(Vector3(4.0, 0, 0.1))
	var below_pos := below.global_position
	rebar.shoot(Vector3.RIGHT)
	await frames(140)
	check(_hd(below, below_pos) > 2.5, "the bowl rolls off a ledge and shoves a monster below (%.2f)" % _hd(below, below_pos))

	# --- Spin: 360 degrees, 2.2 outward, damage to monsters only, Rebar unaffected.
	_fresh()
	var gasket := _hero(Vector3.ZERO, "spin")
	var ring: Array[TrainingDummy] = []
	for i in 3:
		var ang := TAU * i / 3.0 + 0.3
		ring.append(_dummy(Vector3(sin(ang), 0, cos(ang)) * 1.2))
	var mate := _hero(Vector3(-0.6, 0, 1.55))
	var rock_hero := _hero(Vector3(-0.3, 0, -1.7))
	rock_hero.shove_mult = 0.0
	var outside := _dummy(Vector3(3.0, 0, 2.2))
	var starts := {}
	for a in ring + [mate, rock_hero, outside]:
		starts[a] = a.global_position
	check(gasket.shoot(Vector3.RIGHT), "the spin fires")
	check(not gasket.shoot(Vector3.RIGHT), "and has a cooldown")
	near(gasket.cooldown_left(Hero.KEY_RANGED), Hero.SPIN_COOLDOWN, 0.05, "1.4 s cooldown")
	await frames(40)
	for d in ring:
		var out: Vector3 = starts[d]
		check(_hd(d, Vector3.ZERO) > out.length() + 1.9, "monsters are flung outward (%.2f -> %.2f)" % [out.length(), _hd(d, Vector3.ZERO)])
		near(d.global_position.distance_to(starts[d]), Hero.SPIN_SHOVE, 0.25, "by about 2.2")
		near(d.hp, d.max_hp - Hero.SPIN_DAMAGE, 0.001, "and take 16")
	near(mate.global_position.distance_to(starts[mate]), Hero.SPIN_SHOVE, 0.3, "a teammate is shoved too")
	near(mate.hp, mate.max_hp, 0.001, "but takes no damage")
	near(rock_hero.global_position.distance_to(starts[rock_hero]), 0.0, 0.0001, "Rebar (shove_mult 0) is unaffected by the spin")
	near(outside.global_position.distance_to(starts[outside]), 0.0, 0.0001, "out of reach is untouched")
	near(gasket.global_position.length(), 0.0, 0.0001, "Gasket stays where she is")
	await frames(60)
	check(gasket.shoot(Vector3.RIGHT), "the spin is ready again after 1.4 s")

	# --- AllyBrain: Gasket spins when 2+ enemies are in reach, or 1 and the spin is ready.
	# (The eager AI: idle dummies are fair game. This is about using the kit; the restraint baseline, where the bowl only
	# peels, is test_ally_orders.)
	AllyBrain.restraint = false
	_fresh()
	var d2 := HeroFactory.spawn_hero(Vector2i.ZERO, "Gasket", Color.PURPLE, "sword")
	d2.secondary_kind = "spin"
	var leader := _hero(Vector3(0, 0, -3))
	HeroFactory.make_ally(d2, leader, false, 2.4)
	var e1 := _dummy(Vector3(1.3, 0, 0))
	var e2 := _dummy(Vector3(-0.6, 0, 1.2))
	await frames(3)
	check(d2.cooldown_left(Hero.KEY_RANGED) > 0.5, "the ally brain spins with two enemies in reach")
	check(_hd(e1, Vector3(1.3, 0, 0)) > 0.3, "and the enemies are shoved")
	_fresh()
	d2 = HeroFactory.spawn_hero(Vector2i.ZERO, "Gasket", Color.PURPLE, "sword")
	d2.secondary_kind = "spin"
	leader = _hero(Vector3(0, 0, -3))
	HeroFactory.make_ally(d2, leader, false, 2.4)
	e1 = _dummy(Vector3(1.4, 0, 0))
	await frames(3)
	check(d2.cooldown_left(Hero.KEY_RANGED) > 0.5, "and with one enemy in reach and the spin ready")
	_fresh()
	d2 = HeroFactory.spawn_hero(Vector2i.ZERO, "Gasket", Color.PURPLE, "sword")
	d2.secondary_kind = "spin"
	leader = _hero(Vector3(0, 0, -3))
	HeroFactory.make_ally(d2, leader, false, 2.4)
	e1 = _dummy(Vector3(4.5, 0, 0))
	await frames(3)
	near(d2.cooldown_left(Hero.KEY_RANGED), 0.0, 0.0001, "but not with the enemy out of reach")
	await frames(120)
	check(d2.cooldown_left(Hero.KEY_RANGED) > 0.0 or e1.hp < e1.max_hp, "she closes in and fights (spin or melee) once it is near")

	# --- AllyBrain: Rebar bowls at an enemy 3 to 9 away, but not through another hero, or point blank.
	_fresh()
	var p2 := HeroFactory.spawn_hero(Vector2i.ZERO, "Rebar", Color.ORANGE, "sword")
	p2.secondary_kind = "bowl"
	p2.shove_mult = 0.0
	leader = _hero(Vector3(0, 0, -4))
	HeroFactory.make_ally(p2, leader, false, 2.4)
	var far_foe := _dummy(Vector3(6.0, 0, 0))
	await frames(3)
	check(p2.cooldown_left(Hero.KEY_RANGED) > 1.0, "Rebar bowls at an enemy 6 away")
	await frames(150)
	check(far_foe.hp < far_foe.max_hp or _hd(far_foe, Vector3(6, 0, 0)) > 0.5, "and the boulder gets it")
	_fresh()
	p2 = HeroFactory.spawn_hero(Vector2i.ZERO, "Rebar", Color.ORANGE, "sword")
	p2.secondary_kind = "bowl"
	var player := _hero(Vector3(3.0, 0, 0.3))                  # standing in the lane
	HeroFactory.make_ally(p2, player, false, 2.4)
	far_foe = _dummy(Vector3(6.5, 0, 0))
	await frames(3)
	near(p2.cooldown_left(Hero.KEY_RANGED), 0.0, 0.0001, "Rebar holds the throw when the player is in the lane")
	_fresh()
	p2 = HeroFactory.spawn_hero(Vector2i.ZERO, "Rebar", Color.ORANGE, "sword")
	p2.secondary_kind = "bowl"
	leader = _hero(Vector3(0, 0, -4))
	HeroFactory.make_ally(p2, leader, false, 2.4)
	far_foe = _dummy(Vector3(1.8, 0, 0))
	await frames(3)
	near(p2.cooldown_left(Hero.KEY_RANGED), 0.0, 0.0001, "no bowl at point blank (melee instead)")
	AllyBrain.restraint = true
	finish()
