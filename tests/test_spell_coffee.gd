extends MonsterTestBase
## Coffee, and the speed-modifier system under it. Everyone (monsters too) in a SMALL radius gets +60% move and
## attack speed for about six seconds, twitchy (a slight aim wobble for the local player, tiny random steps for AI
## and monsters), then a crash: -30% for two seconds. The speed system is Actor.set_modifier(id, mult, duration,
## stat): modifiers of a stat multiply (so they stack with goo slows and the like), the same id refreshes, speed
## and attack rate are clamped, and being rooted overrides everything.


func _hero(pos: Vector3, secondary: String = "bolt") -> Hero:
	var h := Hero.new()
	h.secondary_kind = secondary
	GameWorld.spawn(h, pos)
	h.snap_to_ground()
	return h


func _dummy(pos: Vector3, hp: float = 100000.0) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.max_hp = hp
	GameWorld.spawn(d, pos)
	d.snap_to_ground()
	return d


## Distance walked in `secs` of game time pushing right every frame.
func _walk(a: Actor, secs: float) -> float:
	var x0 := a.global_position.x
	for i in int(secs * 60.0):
		a.move(Vector3.RIGHT, 1.0 / 60.0)
	return a.global_position.x - x0


func _init() -> void:
	timeout_sec = 240.0   # about 60 s of game time is played out frame by frame


func setup() -> void:
	_numbers()
	_modifier_system()
	await _speed_and_attack_rate()
	await _timeline()
	await _area_and_teams()
	await _monsters()
	await _twitch_and_jitter()
	await _stacking_and_combos()
	finish()


func _numbers() -> void:
	check(SpellBook.SPELLS.has("coffee") and SpellBook.is_available("coffee"), "coffee exists and is castable")
	eq(SpellBook.spell_name("coffee"), "Coffee")
	eq(SpellBook.incantation("coffee"), "CAST COFFEE")
	eq(SpellBook.component_name("coffee"), "Coffee beans")
	near(SpellBook.cooldown_of("coffee"), 14.0, 0.001, "cooldown 14 s")
	check(SpellBook.color_of("coffee").r > SpellBook.color_of("coffee").b, "coffee brown")
	near(CoffeeSpell.COFFEE_MOVE_MULT, 1.6, 0.0001, "+60% move")
	near(CoffeeSpell.COFFEE_ATTACK_MULT, 1.6, 0.0001, "+60% attack speed")
	near(CoffeeSpell.coffee_duration(1.0), 6.0, 0.001, "six seconds at full power")
	check(CoffeeSpell.coffee_duration(0.2) < 6.0 and CoffeeSpell.coffee_duration(0.2) > 4.0, "weaker casts are a bit shorter")
	near(CoffeeSpell.COFFEE_CRASH_MULT, 0.7, 0.0001, "crash -30%")
	near(CoffeeSpell.COFFEE_CRASH_TIME, 2.0, 0.0001, "for 2 s")
	check(CoffeeSpell.coffee_radius(1.0) < TentaclesSpell.tentacles_radius(0.05), "a SMALL radius: smaller than tentacles (%.2f)" % CoffeeSpell.coffee_radius(1.0))
	near(CoffeeSpell.coffee_radius(1.0), 2.0, 0.001, "radius 1.5 + 0.5 * power")
	var c := Coffee.new()
	var f: Dictionary = c.net_fields()
	eq(f["_haste_end"], Net.OWNER, "the phase clocks belong to the target's owner")
	eq(f["_next_twitch"], Net.PRIVATE, "the twitch is that owner's working state")
	c.free()


# --- The speed-modifier system ------------------------------------------------------------------------------------

func _modifier_system() -> void:
	new_world(flat_map(10))
	var a := _hero(Vector3.ZERO)
	# The old call still means "damage taken".
	a.set_modifier("armor", 0.5, 10.0)
	near(a.damage_taken_mult(), 0.5, 0.0001, "set_modifier(id, mult, duration) is still damage taken")
	near(a.move_speed_mult(), 1.0, 0.0001, "and leaves the speeds alone")
	near(a.attack_rate_mult(), 1.0, 0.0001, "")
	check(a.has_modifier("armor") and not a.is_rooted(), "has_modifier / not rooted")
	# Speed modifiers multiply; each stat is separate.
	a.set_modifier("haste", 1.6, 10.0, Actor.STAT_MOVE_SPEED)
	a.set_modifier("goo", 0.5, 10.0, Actor.STAT_MOVE_SPEED)
	near(a.move_speed_mult(), 0.8, 0.0001, "haste 1.6 x goo 0.5 = 0.8")
	near(a.damage_taken_mult(), 0.5, 0.0001, "armor is unaffected by the speed ones")
	near(a.attack_rate_mult(), 1.0, 0.0001, "and so is the attack rate")
	near(a.effective_speed(), a.move_speed * 0.8, 0.0001, "effective speed is the base times the product")
	# The same id refreshes, it never stacks.
	a.set_modifier("haste", 1.6, 10.0, Actor.STAT_MOVE_SPEED)
	near(a.move_speed_mult(), 0.8, 0.0001, "refreshing the same id does not stack")
	a.set_modifier("haste", 2.0, 10.0, Actor.STAT_MOVE_SPEED)
	near(a.move_speed_mult(), 1.0, 0.0001, "a new value replaces the old one (2.0 x 0.5)")
	# Clamped both ways.
	a.set_modifier("a", 2.0, 10.0, Actor.STAT_MOVE_SPEED)
	a.set_modifier("b", 2.0, 10.0, Actor.STAT_MOVE_SPEED)
	near(a.move_speed_mult(), Actor.MOVE_MULT_MAX, 0.0001, "speed is clamped at %.1fx" % Actor.MOVE_MULT_MAX)
	a.clear_modifier("haste")
	a.clear_modifier("a")
	a.clear_modifier("b")
	a.set_modifier("c", 0.1, 10.0, Actor.STAT_MOVE_SPEED)
	near(a.move_speed_mult(), Actor.MOVE_MULT_MIN, 0.0001, "and floored at %.1fx (stacked slows never freeze an actor)" % Actor.MOVE_MULT_MIN)
	# Expiry and clearing.
	a.clear_modifier("c")
	a.clear_modifier("goo")
	near(a.move_speed_mult(), 1.0, 0.0001, "clear_modifier removes it")
	a.set_modifier("brief", 1.5, 1.0, Actor.STAT_ATTACK_RATE)
	near(a.attack_rate_mult(), 1.5, 0.0001, "attack rate")
	near(a.scaled_cooldown(0.6), 0.4, 0.0001, "a cooldown divides by the attack rate")
	near(a.modifier_left("brief"), 1.0, 0.01, "modifier_left")
	GameWorld.time += 1.1
	near(a.attack_rate_mult(), 1.0, 0.0001, "a modifier expires by itself")
	check(not a.has_modifier("brief") and a.modifier_left("brief") == 0.0, "and is gone")
	near(a.scaled_cooldown(0.6), 0.6, 0.0001, "")
	a.set_modifier("slow", 0.25, 5.0, Actor.STAT_ATTACK_RATE)
	a.set_modifier("slower", 0.25, 5.0, Actor.STAT_ATTACK_RATE)
	near(a.attack_rate_mult(), Actor.ATTACK_RATE_MIN, 0.0001, "attack rate is floored too")
	# Root: any live root modifier, whatever its mult; it overrides the speed.
	a.set_modifier("haste2", 2.0, 5.0, Actor.STAT_MOVE_SPEED)
	check(not a.is_rooted() and a.effective_speed() > a.move_speed, "hasted, not rooted")
	a.set_modifier("vines", 1.0, 2.0, Actor.STAT_ROOT)
	check(a.is_rooted(), "a root modifier roots")
	near(a.effective_speed(), 0.0, 0.0001, "and zeroes the speed whatever else applies")
	GameWorld.time += 2.1
	check(not a.is_rooted() and a.effective_speed() > a.move_speed, "it expires and the haste is back")
	# Everything declared is still OWNER state (it replicates).
	eq(a.net_fields()["_modifiers"], Net.OWNER, "modifiers replicate")
	# Combat.modify_radius is the area application.
	new_world(flat_map(10))
	var x := _dummy(Vector3(1, 0, 0))
	var y := _dummy(Vector3(5, 0, 0))
	var hit := Combat.modify_radius(Vector3.ZERO, 2.0, "slime", 0.5, 3.0, Actor.STAT_MOVE_SPEED)
	check(hit.has(x) and not hit.has(y), "Combat.modify_radius reaches the actors in range")
	near(x.move_speed_mult(), 0.5, 0.0001, "and applies the modifier")
	near(y.move_speed_mult(), 1.0, 0.0001, "")


# --- Haste really is faster -----------------------------------------------------------------------------------------

func _speed_and_attack_rate() -> void:
	new_world(flat_map(14))
	var base := _hero(Vector3(-10, 0, 0))
	var hasted := _hero(Vector3(-10, 0, 4))
	var slowed := _hero(Vector3(-10, 0, -4))
	hasted.set_modifier("coffee_move", 1.6, 100.0, Actor.STAT_MOVE_SPEED)
	slowed.set_modifier("coffee_crash_move", 0.7, 100.0, Actor.STAT_MOVE_SPEED)
	var d0 := _walk(base, 1.0)
	var d1 := _walk(hasted, 1.0)
	var d2 := _walk(slowed, 1.0)
	near(d0, base.move_speed, 0.15, "a normal hero walks %.1f in a second (the default profile's start envelope costs about 0.1)" % d0)
	near(d1 / d0, 1.6, 0.03, "hasted: +60%% (%.2f)" % (d1 / d0))
	near(d2 / d0, 0.7, 0.03, "crashed: -30%% (%.2f)" % (d2 / d0))
	# Wick's draw (the bow, half speed while drawn) is hasted too: the draw time divides by the attack rate.
	new_world(flat_map(10))
	var archer := _hero(Vector3.ZERO, "arrow")
	archer.set_modifier("coffee_rate", 1.6, 100.0, Actor.STAT_ATTACK_RATE)
	check(archer.start_draw(), "start drawing")
	await frames(int(archer.arrow_draw_time / 1.6 * 60.0) + 3)
	check(archer.draw_progress() >= 1.0, "a hasted bow is fully drawn in 0.7 / 1.6 s (%.2f)" % archer.draw_progress())
	archer.cancel_draw()
	var slow_archer := _hero(Vector3(0, 0, 3), "arrow")
	check(slow_archer.start_draw(), "")
	await frames(int(slow_archer.arrow_draw_time / 1.6 * 60.0) + 3)
	check(slow_archer.draw_progress() < 0.99, "an unhasted bow is not (%.2f)" % slow_archer.draw_progress())
	slow_archer.cancel_draw()
	# Attack cooldowns: count the hits landed on a post in 4.5 s of spamming melee.
	new_world(flat_map(10))
	var fast := _hero(Vector3(0, 0, 0))
	var normal := _hero(Vector3(0, 0, 6))
	var slow := _hero(Vector3(0, 0, -6))
	var post_a := _dummy(Vector3(1.0, 0, 0))
	var post_b := _dummy(Vector3(1.0, 0, 6))
	var post_c := _dummy(Vector3(1.0, 0, -6))
	for post: Actor in [post_a, post_b, post_c]:
		post.shove_mult = 0.0   # stay in reach: the nudge from each hit would carry a post out of range
	fast.set_modifier("coffee_rate", 1.6, 100.0, Actor.STAT_ATTACK_RATE)
	slow.set_modifier("crash_rate", 0.7, 100.0, Actor.STAT_ATTACK_RATE)
	var swings := {fast: 0, normal: 0, slow: 0}
	for i in int(4.5 * 60.0):
		for h: Hero in [fast, normal, slow]:
			if h.melee(Vector3.RIGHT):
				swings[h] += 1
		await get_tree().physics_frame
	var base_n := float(swings[normal])
	check(base_n >= 9.0, "a normal hero swings about every 0.45 s (%d swings in 4.5 s)" % int(base_n))
	near(float(swings[fast]) / base_n, 1.6, 0.2, "hasted: +60%% swings (%d vs %d)" % [swings[fast], swings[normal]])
	near(float(swings[slow]) / base_n, 0.7, 0.15, "crashed: -30%% swings (%d vs %d)" % [swings[slow], swings[normal]])
	check(post_a.hp < post_b.hp and post_b.hp < post_c.hp, "and the damage follows (%.0f < %.0f < %.0f)" % [post_a.hp, post_b.hp, post_c.hp])
	# The other attacks use the same scale: the bolt's cooldown.
	var bolter := _hero(Vector3(5, 0, 0))
	bolter.set_modifier("coffee_rate", 1.6, 100.0, Actor.STAT_ATTACK_RATE)
	check(bolter.shoot(Vector3.RIGHT), "bolt")
	near(bolter.cooldown_left(Hero.KEY_RANGED), Hero.RANGED_COOLDOWN / 1.6, 0.01, "the bolt cooldown divides by 1.6")


# --- The timeline: haste, then crash, then normal -----------------------------------------------------------------

func _timeline() -> void:
	new_world(flat_map(14))
	var caster := _hero(Vector3(-10, 0, 0))
	var hero := _hero(Vector3(0.5, 0, 0))
	check(SpellBook.cast("coffee", caster, 1.0, hero.global_position), "coffee casts")
	await frames(2)
	check(Coffee.is_hasted(hero) and not Coffee.is_crashing(hero), "hasted at once (no telegraph)")
	near(hero.move_speed_mult(), 1.6, 0.0001, "+60% move")
	near(hero.attack_rate_mult(), 1.6, 0.0001, "+60% attack speed")
	var node := hero.get_node_or_null("Coffee") as Coffee
	check(node != null, "a Coffee status node on the target")
	await frames(int(5.5 * 60.0))
	check(Coffee.is_hasted(hero), "still hasted at 5.5 s")
	near(hero.move_speed_mult(), 1.6, 0.0001, "")
	await frames(60)   # about 6.5 s
	check(Coffee.is_crashing(hero) and not Coffee.is_hasted(hero), "crashing at 6.5 s")
	near(hero.move_speed_mult(), 0.7, 0.0001, "-30% move")
	near(hero.attack_rate_mult(), 0.7, 0.0001, "-30% attack speed")
	await frames(int(1.1 * 60.0))   # about 7.6 s
	check(Coffee.is_crashing(hero), "still crashing at about 7.6 s")
	await frames(45)   # about 8.4 s
	check(not Coffee.is_caffeinated(hero), "back to normal after the 2 s crash")
	near(hero.move_speed_mult(), 1.0, 0.0001, "normal speed")
	near(hero.attack_rate_mult(), 1.0, 0.0001, "normal attack rate")
	await frames(3)
	check(hero.get_node_or_null("Coffee") == null, "the status node is gone")
	# A second dose during the crash cancels it and starts a new haste.
	Coffee.drink(hero, 6.0)
	await frames(int(6.3 * 60.0))
	check(Coffee.is_crashing(hero), "set up: in the crash")
	Coffee.drink(hero, 6.0)
	check(Coffee.is_hasted(hero) and not Coffee.is_crashing(hero), "drinking in the crash cancels it")
	near(hero.move_speed_mult(), 1.6, 0.0001, "and hastes again")
	# A second dose during the haste extends it to the longer time; it never stacks to +120%.
	new_world(flat_map(14))
	var h2 := _hero(Vector3.ZERO)
	Coffee.drink(h2, 6.0)
	await frames(int(3.0 * 60.0))
	Coffee.drink(h2, 6.0)
	near(h2.move_speed_mult(), 1.6, 0.0001, "two coffees are still +60%, not +156%")
	near(h2.modifier_left("coffee_move"), 6.0, 0.1, "the haste restarted at the full six seconds")
	eq(h2.get_children().filter(func(n: Node) -> bool: return n is Coffee).size(), 1, "one status node")
	await frames(int(5.8 * 60.0))
	check(Coffee.is_hasted(h2), "hasted for 3 + 6 s in all")
	await frames(30)
	check(Coffee.is_crashing(h2), "then the crash")
	# A dead actor loses the status.
	new_world(flat_map(14))
	var doomed := _dummy(Vector3.ZERO, 10.0)
	Coffee.drink(doomed, 6.0)
	doomed.apply_damage(100.0)
	await frames(3)
	check(not is_instance_valid(doomed) or doomed.get_node_or_null("Coffee") == null, "a dead actor drops it")
	check(Coffee.drink(null, 6.0) == null, "drinking nothing is fine")


# --- Small radius, every team --------------------------------------------------------------------------------------

func _area_and_teams() -> void:
	new_world(flat_map(14))
	var caster := _hero(Vector3(-9, 0, 0))
	var mate := _hero(Vector3(1.0, 0, 0))
	var mon := _dummy(Vector3(-1.0, 0, 0.5))
	var worker := Employee.spawn(Hex.from_world(Vector3(0, 0, -1.3)), {"style": "staff"})
	worker.global_position = Vector3(0.0, worker.global_position.y, -1.3)
	var out_hero := _hero(Vector3(3.5, 0, 0))     # outside radius 2.0 + its own 0.4
	var out_mon := _dummy(Vector3(0, 0, 4.0))
	SpellBook.cast("coffee", caster, 1.0, Vector3.ZERO)
	await frames(2)
	for a: Actor in [mate, mon, worker]:
		check(Coffee.is_hasted(a), "%s is caffeinated (any team)" % a.display_name)
	check(not Coffee.is_caffeinated(out_hero) and not Coffee.is_caffeinated(out_mon) and not Coffee.is_caffeinated(caster), "outside the small radius is not")
	near(mate.hp, mate.max_hp, 0.001, "coffee does no damage (friendly fire is just haste)")
	# The caster in the area gets it too.
	new_world(flat_map(14))
	var me := _hero(Vector3(0.5, 0, 0))
	SpellBook.cast("coffee", me, 1.0, Vector3.ZERO)
	await frames(2)
	check(Coffee.is_hasted(me), "the caster in the area is hasted too")
	# A weak cast has a smaller radius and a shorter haste.
	new_world(flat_map(14))
	var c2 := _hero(Vector3(-9, 0, 0))
	var edge := _dummy(Vector3(2.2, 0, 0))
	SpellBook.cast("coffee", c2, 0.05, Vector3.ZERO)
	await frames(2)
	check(not Coffee.is_hasted(edge), "a 5%% cast reaches %.2f (+ 0.45), not 2.2" % CoffeeSpell.coffee_radius(0.05))
	SpellBook.cast("coffee", c2, 1.0, Vector3.ZERO)
	await frames(2)
	check(Coffee.is_hasted(edge), "a full cast does")
	# Aim snaps onto a teammate, like every spell.
	new_world(flat_map(14))
	var caster3 := _hero(Vector3(-8, 0, 0))
	var buddy := _hero(Vector3(2.0, 0, 3.0))
	var buddy_mon := _dummy(Vector3(2.5, 0, 3.8))
	SpellBook.cast("coffee", caster3, 1.0, Vector3(2.4, 0, 3.4))
	await frames(2)
	check(Coffee.is_hasted(buddy) and Coffee.is_hasted(buddy_mon), "aimed at a friend: the friend and the monster beside them")
	# A MISS is still visible: a cast where nobody stands leaves a splash (spill, steam, droplets, the radius ring).
	new_world(flat_map(14))
	var c4 := _hero(Vector3(-8, 0, 0))
	var empty_spot := Vector3(3.0, 0, 3.0)
	var before := get_tree().get_nodes_in_group(CoffeeFx.GROUP).size()
	var hit_nobody := SpellBook.cast("coffee", c4, 1.0, empty_spot)
	check(hit_nobody, "a coffee cast at an empty spot still casts")
	var splashes := get_tree().get_nodes_in_group(CoffeeFx.GROUP)
	eq(splashes.size(), before + 1, "a miss leaves a splash node")
	var sp := splashes[splashes.size() - 1] as Node3D
	check(sp != null and GameWorld.flat_distance(sp.global_position, empty_spot) < 0.01, "... at the aim point")
	check(sp.find_children("*", "CPUParticles3D", true, false).size() >= 2, "... with steam and flying droplets")
	check(sp.find_children("*", "MeshInstance3D", true, false).size() >= 2, "... and the amber ring burst that shows the radius")
	await frames(int((CoffeeFx.SPLASH_LIFE + 0.4) * 60.0))
	check(not is_instance_valid(sp), "the splash cleans itself up")
	# The hasted get steam wisps that are clearly there, and a visible crash.
	new_world(flat_map(14))
	var c5 := _hero(Vector3(-8, 0, 0))
	var jittery := _hero(Vector3(1.0, 0, 0))
	SpellBook.cast("coffee", c5, 1.0, Vector3.ZERO)
	await frames(2)
	var cof := jittery.get_node("Coffee") as Coffee
	var plumes := cof.find_children("*", "CPUParticles3D", false, false)
	check(plumes.size() >= 2 and (plumes[0] as CPUParticles3D).emitting and (plumes[0] as CPUParticles3D).amount >= 20, "a hasted actor has a thick, emitting steam plume")
	check((plumes[0] as CPUParticles3D).mesh.get_aabb().size.x * (plumes[0] as CPUParticles3D).scale_amount_min > 0.4, "whose wisps are big enough to read (%.2f wide)" % ((plumes[0] as CPUParticles3D).mesh.get_aabb().size.x * (plumes[0] as CPUParticles3D).scale_amount_min))
	await frames(int((CoffeeSpell.coffee_duration(1.0) + 0.3) * 60.0))
	check(Coffee.is_crashing(jittery), "the haste ran out into the crash")
	check(not (plumes[0] as CPUParticles3D).emitting, "the steam stops in the crash")
	check(cof.find_children("*", "Label3D", false, false).size() >= 3, "and the crash shows droopy z z Z")
	# Through the slots, with a component.
	var h := _hero(Vector3(-5, 0, 5))
	h.spell_slots = ["coffee", "heal"] as Array[String]
	check(h.try_cast("coffee", 1.0, h.global_position), "cast through the slots")
	eq(h.charges_of("coffee"), 4, "a charge of coffee beans")


# --- Monsters, accidentally ---------------------------------------------------------------------------------------

func _monsters() -> void:
	new_world(flat_map(14))
	var caster := _hero(Vector3(-10, 0, 0))
	var swarmer := MonsterFactory.spawn("swarmer", Vector2i(0, 0)) as Monster
	var plain := MonsterFactory.spawn("swarmer", Vector2i(0, 5)) as Monster
	swarmer.aggro_range = 0.0
	plain.aggro_range = 0.0
	SpellBook.cast("coffee", caster, 1.0, swarmer.global_position)
	await frames(2)
	check(Coffee.is_hasted(swarmer) and not Coffee.is_hasted(plain), "a swarmer in the area is caffeinated by accident")
	# It chases faster: walk both toward +X for a second (twitch off for a clean measure).
	var node := swarmer.get_node("Coffee") as Coffee
	node._next_twitch = 1.0e9
	var x1 := swarmer.global_position.x
	var x2 := plain.global_position.x
	for i in 60:
		swarmer.move(Vector3.RIGHT, 1.0 / 60.0)
		plain.move(Vector3.RIGHT, 1.0 / 60.0)
	near((swarmer.global_position.x - x1) / (plain.global_position.x - x2), 1.6, 0.05, "a hasted swarmer is 60% faster")
	# A hasted grunt swings more often: count the hits on a hero post over 9 s.
	new_world(flat_map(14))
	var grunt := MonsterFactory.spawn("grunt", Vector2i(0, 0)) as Monster
	var grunt2 := MonsterFactory.spawn("grunt", Vector2i(0, 8)) as Monster
	var tank := _hero(Vector3(1.0, 0, 0))
	var tank2 := _hero(Vector3(1.0, 0, Hex.to_world(Vector2i(0, 8)).z))
	tank.max_hp = 100000.0
	tank.hp = tank.max_hp
	tank2.max_hp = 100000.0
	tank2.hp = tank2.max_hp
	grunt.aggro(tank)
	grunt2.aggro(tank2)
	Coffee.drink(grunt, 6.0)
	grunt.get_node("Coffee")._next_twitch = 1.0e9
	await frames(int(5.5 * 60.0))
	var hits := (tank.max_hp - tank.hp) / grunt.attack_damage
	var hits2 := (tank2.max_hp - tank2.hp) / grunt2.attack_damage
	check(hits2 >= 3.0, "set up: a normal grunt landed %d hits" % int(hits2))
	check(hits / hits2 > 1.3, "the hasted grunt swings more: %d vs %d hits in 5.5 s" % [int(hits), int(hits2)])
	# Monsters in the crash are slower and swing less.
	new_world(flat_map(14))
	var m3 := MonsterFactory.spawn("grunt", Vector2i(0, 0)) as Monster
	m3.aggro_range = 0.0
	m3.set_modifier("coffee_crash_move", 0.7, 10.0, Actor.STAT_MOVE_SPEED)
	var xs := m3.global_position.x
	for i in 60:
		m3.move(Vector3.RIGHT, 1.0 / 60.0)
	near((m3.global_position.x - xs) / m3.move_speed, 0.7, 0.05, "a crashed grunt walks 70% as fast")
	near(m3.scaled_cooldown(m3.attack_cooldown), m3.attack_cooldown, 0.0001, "(attack rate is a separate stat)")


# --- Twitchy: tiny random steps for AI, an aim wobble for the player ------------------------------------------------

func _twitch_and_jitter() -> void:
	# An idle monster on coffee takes small random steps; one without does not move.
	new_world(flat_map(14))
	var mon := MonsterFactory.spawn("grunt", Vector2i(0, 0)) as Monster
	mon.aggro_range = 0.0
	var calm := MonsterFactory.spawn("grunt", Vector2i(0, 6)) as Monster
	calm.aggro_range = 0.0
	var home := mon.global_position
	var calm_home := calm.global_position
	Coffee.drink(mon, 6.0)
	var far := 0.0
	var steps := 0
	var prev := mon.global_position
	for i in int(5.0 * 60.0):
		await get_tree().physics_frame
		far = maxf(far, GameWorld.flat_distance(mon.global_position, home))
		if mon.global_position.distance_to(prev) > 0.001:
			steps += 1
		prev = mon.global_position
	check(steps > 6, "a caffeinated monster twitches (%d moving frames in 5 s)" % steps)
	check(far > 0.2, "it drifts a little (%.2f)" % far)
	check(far < 4.0, "but only a little (%.2f)" % far)
	near(calm.global_position.distance_to(calm_home), 0.0, 0.0001, "an uncaffeinated idle monster stays put")
	# Each step is tiny.
	var biggest := 0.0
	var m2 := MonsterFactory.spawn("grunt", Vector2i(0, -6)) as Monster
	m2.aggro_range = 0.0
	Coffee.drink(m2, 6.0)
	var last := m2.global_position
	for i in 240:
		await get_tree().physics_frame
		biggest = maxf(biggest, m2.global_position.distance_to(last))
		last = m2.global_position
	check(biggest < 0.25, "no single frame jumps (%.3f)" % biggest)
	# The twitch is a gameplay roll on GameWorld.rng: the same seed gives the same wander.
	var trails: Array = []
	for run in 2:
		new_world(flat_map(14))
		GameWorld.rng.seed = 4242
		var m := MonsterFactory.spawn("grunt", Vector2i(0, 0)) as Monster
		m.aggro_range = 0.0
		Coffee.drink(m, 6.0)
		for i in 180:
			await get_tree().physics_frame
		trails.append(m.global_position)
	check((trails[0] as Vector3).distance_to(trails[1]) < 0.001, "a seeded run twitches the same way twice")
	# A rooted twitcher does not move; a monster winding up an attack stands still.
	new_world(flat_map(14))
	var rooted := MonsterFactory.spawn("grunt", Vector2i(0, 0)) as Monster
	rooted.aggro_range = 0.0
	var rp := rooted.global_position
	rooted.set_modifier("vines", 1.0, 30.0, Actor.STAT_ROOT)
	Coffee.drink(rooted, 6.0)
	await frames(180)
	near(rooted.global_position.distance_to(rp), 0.0, 0.0001, "coffee cannot move a rooted actor")
	# AI allies twitch; the player does not (they get the aim wobble instead).
	new_world(flat_map(14))
	var ally := _hero(Vector3(0, 0, 0))
	var player := _hero(Vector3(0, 0, 6))
	var pc := PlayerController.new()
	player.add_child(pc)
	pc.enabled = false
	check(player.is_player and not ally.is_player, "set up: a player and an AI ally")
	var ap := ally.global_position
	var pp := player.global_position
	Coffee.drink(ally, 6.0)
	Coffee.drink(player, 6.0)
	await frames(240)
	check(ally.global_position.distance_to(ap) > 0.1, "an AI ally on coffee twitches")
	near(player.global_position.distance_to(pp), 0.0, 0.0001, "the local player does not (it is their hands that shake)")
	# The aim wobble: only while hasted, small, smooth and deterministic (no random numbers).
	pc.aim_override = Vector3(8, 0, 6)
	var seen_min := 9.0
	var seen_max := -9.0
	var worst := 0.0
	for i in 240:
		await get_tree().physics_frame
		var aim := pc.aim_point()
		var from := player.global_position
		var want := (Vector3(8, 0, 6) - from)
		var got := (aim - from)
		var ang := want.signed_angle_to(got, Vector3.UP)
		seen_min = minf(seen_min, ang)
		seen_max = maxf(seen_max, ang)
		worst = maxf(worst, absf(ang))
		near(got.length(), want.length(), 0.01, "the wobble rotates the aim, it does not stretch it")
	check(worst <= Coffee.AIM_JITTER + 0.001, "the wobble never exceeds %.2f rad (%.3f)" % [Coffee.AIM_JITTER, worst])
	check(seen_max - seen_min > 0.03, "and it really wobbles (%.3f .. %.3f)" % [seen_min, seen_max])
	# Melee and shots follow the wobbly point; a voice cast too (they all call aim_point()).
	check(pc.aim_point() != Vector3(8, 0, 6) or Coffee.aim_jitter_angle(player) == 0.0, "aim_point carries the wobble")
	# Crashed or sober: exact.
	player.clear_modifier("coffee_move")
	near(Coffee.aim_jitter_angle(player), 0.0, 0.0, "no wobble without the haste")
	check(pc.aim_point().is_equal_approx(Vector3(8, 0, 6)), "an exact aim again")
	check(Coffee.jitter_aim(ally, Vector3(3, 0, 3)).is_equal_approx(Vector3(3, 0, 3)), "and for anyone not hasted")
	# The same clock gives the same wobble (no rng).
	player.set_modifier("coffee_move", 1.6, 5.0, Actor.STAT_MOVE_SPEED)
	var j1 := Coffee.aim_jitter_angle(player)
	var j2 := Coffee.aim_jitter_angle(player)
	near(j1, j2, 0.0, "the wobble is a function of the game clock")


# --- Stacking with other modifiers, and combos ------------------------------------------------------------------------

func _stacking_and_combos() -> void:
	new_world(flat_map(14))
	var caster := _hero(Vector3(-10, 0, 0))
	var slimed := _hero(Vector3(0.5, 0, 0))
	slimed.set_modifier("goo", 0.5, 30.0, Actor.STAT_MOVE_SPEED)
	var plain := _hero(Vector3(0.5, 0, 3.0))
	SpellBook.cast("coffee", caster, 1.0, Vector3(0.5, 0, 1.5))
	await frames(2)
	near(slimed.move_speed_mult(), 0.8, 0.0001, "coffee on a goo-slowed hero: 1.6 x 0.5 = 0.8")
	near(plain.move_speed_mult(), 1.6, 0.0001, "and on a free one: 1.6")
	await frames(int(6.5 * 60.0))
	near(slimed.move_speed_mult(), 0.35, 0.0001, "in the crash the goo is still there: 0.7 x 0.5")
	await frames(120)
	near(slimed.move_speed_mult(), 0.5, 0.0001, "after the crash only the goo remains")
	# Armor (damage taken) and haste are independent.
	var armored := _hero(Vector3(0, 0, -3.0))
	armored.set_modifier("armor", 0.4, 30.0)
	Coffee.drink(armored, 6.0)
	near(armored.damage_taken_mult(), 0.4, 0.0001, "coffee does not touch armor")
	near(armored.move_speed_mult(), 1.6, 0.0001, "")
	# Vines beat coffee: rooted and hasted is still rooted; the haste is back when the roots let go.
	new_world(flat_map(14))
	var c := _hero(Vector3(-10, 0, 0))
	var wired := _hero(Vector3(0.5, 0, 0))
	Coffee.drink(wired, 6.0)
	SpellBook.cast("vines", c, 1.0, wired.global_position)
	await frames(25)
	check(wired.is_rooted(), "vines root a hasted hero")
	near(_walk(wired, 1.0), 0.0, 0.0001, "and coffee does not help it walk")
	near(wired.move_speed_mult(), 1.6, 0.0001, "(the haste is still ticking underneath)")
	await frames(60 * 3)
	check(not wired.is_rooted(), "roots end")
	var step := _walk(wired, 1.0)
	check(step > wired.move_speed * 1.5, "and it runs at the hasted speed again (%.2f)" % step)
	# A hasted spinner (Gasket) spins more often; the bowl too.
	new_world(flat_map(14))
	var gasket := _hero(Vector3.ZERO, "spin")
	gasket.set_modifier("coffee_rate", 1.6, 30.0, Actor.STAT_ATTACK_RATE)
	check(gasket.shoot(Vector3.RIGHT), "spin")
	near(gasket.cooldown_left(Hero.KEY_RANGED), Hero.SPIN_COOLDOWN / 1.6, 0.01, "the spin recharges 60% faster")
	var rebar := _hero(Vector3(0, 0, 5), "bowl")
	rebar.set_modifier("coffee_rate", 1.6, 30.0, Actor.STAT_ATTACK_RATE)
	check(rebar.shoot(Vector3.RIGHT), "bowl")
	near(rebar.cooldown_left(Hero.KEY_RANGED), Hero.BOWL_COOLDOWN / 1.6, 0.01, "so does the bowl")
	# Spell cooldowns are NOT sped up (coffee is about the body, not the voice).
	var caster2 := _hero(Vector3(5, 0, 5))
	caster2.spell_slots = ["heal", "corn"] as Array[String]
	caster2.set_modifier("coffee_rate", 1.6, 30.0, Actor.STAT_ATTACK_RATE)
	check(caster2.try_cast("corn", 1.0, Vector3(9, 0, 9)), "cast")
	near(caster2.cooldown_left("corn"), SpellBook.cooldown_of("corn"), 0.05, "spell cooldowns are untouched by attack speed")
