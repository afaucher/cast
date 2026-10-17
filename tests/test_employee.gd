extends MonsterTestBase
## Employee: a neutral, fragile civilian. Cowers, panics away from monsters, is recruited by E (request_follow, within 2.2; walking past does nothing) and trails the hero (pathing, no +2 climbs), switches leader when the leader goes down, dies to
## friendly-fire area damage with no floor (and to shoves into pits), can be targeted by monsters, and
## leaves through extract() emitting `rescued` once.


## A world with a +2 ledge: cells with world x > 3 are level 2.
func _ledge_map() -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 12):
		m.set_cell(c, 2 if Hex.to_world(c).x > 3.0 else 0)
	return m


func _init() -> void:
	timeout_sec = 240.0


func setup() -> void:
	# --- A: spawns neutral, fragile, cowering ------------------------------------------------
	new_world(flat_map(14))
	var emp := Employee.spawn(Vector2i(0, 0), {"style": "staff", "name": "Reginald"})
	var hench := Employee.spawn(Vector2i(0, 4), {"style": "henchman", "name": "Gary"})
	eq(emp.team, GameWorld.TEAM_NEUTRAL, "staff is neutral")
	eq(hench.team, GameWorld.TEAM_NEUTRAL, "henchman is neutral")
	near(emp.max_hp, 30.0, 0.001, "about 30 hp")
	near(emp.hp, 30.0, 0.001, "starts at full hp")
	eq(emp.display_name, "Reginald", "name from opts")
	eq(hench.style, "henchman", "style from opts")
	check(emp.move_speed < 4.5, "slow-ish (slower than a hero)")
	check(emp.is_in_group("employees") and emp.is_in_group("actors"), "in the employees and actors groups")
	check(emp.model is EmployeeModel and emp.model.style == "staff", "staff model")
	check(hench.model.style == "henchman", "henchman model")
	eq(Employee.alive().size(), 2, "two living employees")
	check(not emp.is_following() and emp.leader() == null, "not following anyone")
	var start := emp.global_position
	await frames(90)
	eq(emp.state, Employee.State.COWER, "cowers")
	eq(emp.model.mood(), "cower", "the model is crouched")
	check(emp.global_position.distance_to(start) < 0.01, "stays put while cowering")
	eq(emp.bubble_text(), "", "no bubble with nobody near")
	# a hero nearby (but not within 2): still cowering, now with a bubble and a name tag
	var hero := add_hero(Vector2i(3, 0))   # ~5.2 away
	await frames(30)
	eq(emp.state, Employee.State.COWER, "still cowering with a hero 5 away")
	check(emp.bubble_text() != "", "a help bubble shows when a hero is near (%s)" % emp.bubble_text())
	check(emp._name_label.visible, "name tag shows when a hero is near")
	hero.queue_free()
	hench.free()

	# --- B: panics away from a nearby monster --------------------------------------------------
	new_world(flat_map(12))
	emp = Employee.spawn(Vector2i(0, 0), {"style": "staff"})
	var far_hero := add_hero(Vector2i(8, 0))                 # far away: the grunt stays asleep
	var grunt := MonsterFactory.spawn("grunt", Vector2i(2, 0))
	var d0 := fdist(emp, grunt)
	check(d0 < Employee.PANIC_RANGE, "the grunt starts inside panic range (%.2f)" % d0)
	var panicked := await wait_until(func() -> bool: return emp.state == Employee.State.PANIC, 30)
	check(panicked, "panics when a monster is within range")
	eq(emp.model.mood(), "panic", "the model flails")
	await frames(60)
	var d1 := fdist(emp, grunt)
	check(d1 > d0 + 1.5, "ran away: distance grew %.2f -> %.2f" % [d0, d1])
	eq(grunt.state, Monster.State.IDLE, "the grunt is still asleep (employees do not wake monsters)")
	var calmed := await wait_until(func() -> bool: return emp.state == Employee.State.COWER, 400)
	check(calmed, "calms down and hides again once clear of the monster")
	check(fdist(emp, grunt) >= Employee.PANIC_RANGE, "hiding well away from the monster")
	far_hero.queue_free()

	# --- C: follows the first hero within 2 and stays within ~3 ------------------------------
	new_world(flat_map(14))
	emp = Employee.spawn(Vector2i(0, 0), {"style": "henchman"})
	hero = add_hero(Vector2i(1, 0))                          # ~1.7 away
	hero.move_speed = 4.5
	var other := add_hero(Vector2i(-4, 3))                   # a second hero, far away
	await frames(60)
	check(not emp.is_following(), "a hero within 2 does NOT recruit by standing there (joining needs E)")
	check(not emp.request_follow(other), "a hero 6 away cannot recruit")
	check(emp.request_follow(hero), "E from a hero within reach recruits")
	check(emp.is_following(), "latches onto the hero who asked")
	check(emp.leader() == hero, "the near hero is the leader")
	eq(emp.model.mood(), "follow", "the model switches to its follow walk")
	var max_d := 0.0
	var moved_total := 0.0
	var last := emp.global_position
	for i in 190:
		var dir := Vector3(1, 0, 0) if i < 100 else Vector3(0, 0, 1)
		hero.move(dir, 1.0 / 60.0)
		await get_tree().physics_frame
		max_d = maxf(max_d, fdist(emp, hero))
		moved_total += emp.global_position.distance_to(last)
		last = emp.global_position
	check(moved_total > 8.0, "it walked along with the hero (%.1f units)" % moved_total)
	check(max_d <= 3.7, "stayed within ~3 of the walking hero (max %.2f)" % max_d)
	await frames(90)
	var rest_d := fdist(emp, hero)
	check(rest_d >= Employee.FOLLOW_MIN - 0.15 and rest_d <= Employee.FOLLOW_MAX + 0.1, "settles 1.5-3 behind (%.2f)" % rest_d)
	check(emp.is_following() and emp.leader() == hero, "still following the same hero")

	# --- C2: paths around a wall -----------------------------------------------------------------
	var map_w := flat_map(14)
	wall_where(map_w, func(p: Vector3) -> bool: return absf(p.x - 3.46) < 0.9 and absf(p.z) < 3.5)
	new_world(map_w)
	emp = Employee.spawn(Vector2i(0, 0), {"style": "staff"})
	hero = add_hero(Vector2i(1, 0))
	emp.request_follow(hero)
	check(emp.is_following(), "latched before the wall test")
	hero.global_position = Vector3(8.0, hero.global_position.y, 0.0)   # the far side of the wall
	var rounded := await wait_until(func() -> bool: return fdist(emp, hero) < 3.4, 900)
	check(rounded, "found its way around the wall (dist %.2f)" % fdist(emp, hero))

	# --- C3: cannot climb +2 ----------------------------------------------------------------------
	new_world(_ledge_map())
	emp = Employee.spawn(Vector2i(0, 0), {"style": "staff"})
	hero = add_hero(Vector2i(1, 0))
	emp.request_follow(hero)
	check(emp.is_following(), "latched before the ledge test")
	hero.global_position = Hex.to_world(Vector2i(5, 0), 2.0)   # up on the +2 ledge
	await frames(420)
	check(emp.global_position.x < 3.3, "did not climb the +2 ledge (x %.2f)" % emp.global_position.x)
	check(emp.is_following(), "still wants to follow")

	# --- D: switches leader when the leader goes down ------------------------------------------
	new_world(flat_map(14))
	emp = Employee.spawn(Vector2i(0, 0), {"style": "staff"})
	var h1 := add_hero(Vector2i(1, 0))
	var h2 := add_hero(Vector2i(-4, 0))                       # ~6.9 away: not a leader yet
	emp.request_follow(h1)
	check(emp.leader() == h1, "follows the hero who recruited it, not the far one")
	h1.dead = true                                            # downed (stays in the tree)
	check(emp.leader() == null, "a downed leader is no leader")
	var switched := await wait_until(func() -> bool: return emp.leader() == h2, 40)
	check(switched, "switches to the nearest other hero")
	check(emp.is_following(), "still following")
	h2.dead = true
	var hid := await wait_until(func() -> bool: return emp.state == Employee.State.COWER, 40)
	check(hid, "goes back to cowering when every hero is down")
	check(not emp.is_following() and emp.leader() == null, "no leader left")

	# --- E: hit by area damage, no friendly-fire floor -------------------------------------------
	new_world(flat_map(10))
	emp = Employee.spawn(Vector2i(0, 0), {"style": "staff"})
	hero = add_hero(Vector2i(4, 0))
	var died_count := [0]
	emp.died.connect(func() -> void: died_count[0] += 1)
	var hit := Combat.explode(emp.global_position, 3.0, 20.0, -1, hero, 1.0)   # a corn-style blast (team -1)
	check(hit.has(emp), "an everyone-blast hits the employee")
	near(emp.hp, 10.0, 0.001, "20 damage off 30 hp")
	await frames(2)
	check(emp.bubble_text() == "OW!", "yelps when hit (%s)" % emp.bubble_text())
	check(emp.state == Employee.State.PANIC, "a hit makes it panic")
	Combat.explode(emp.global_position, 3.0, 20.0, -1, hero, 1.0)
	check(emp.dead, "dies with no floor at 1 hp")
	eq(died_count[0], 1, "died emitted once")
	check(Employee.alive().is_empty(), "no longer counted alive")
	await frames(90)
	check(not is_instance_valid(emp), "removed after the fall-over")
	# teeth / tentacles style: a shove, and a shove into a pit
	var map_p := flat_map(8)
	for c in map_p.cells.keys():
		if Hex.to_world(c).x > 3.0:
			map_p.cells.erase(c)
	new_world(map_p)
	emp = Employee.spawn(Vector2i(0, 0), {"style": "henchman"})
	hero = add_hero(Vector2i(-3, 0))
	var before := emp.global_position
	Combat.shove_radius(before + Vector3(-0.6, 0, 0), 3.0, 1.0, hero, -1)
	check(emp.is_shoved(), "an area shove moves it")
	await frames(40)
	check(emp.global_position.distance_to(before) > 0.5, "shoved away (%.2f)" % emp.global_position.distance_to(before))
	emp.set_physics_process(false)   # keep it from running back out of the way
	Combat.shove_radius(emp.global_position + Vector3(-0.6, 0, 0), 3.0, 6.0, hero, -1)
	var fell := await wait_until(func() -> bool: return emp.dead, 240)
	check(fell, "shoved into the pit: dies")

	# --- F: monsters target employees (only when closer than the hero and inside aggro range) ------
	new_world(flat_map(14))
	emp = Employee.spawn(Vector2i(2, 0), {"style": "staff"})
	emp.set_physics_process(false)                           # a sitting duck
	hero = add_hero(Vector2i(5, 0))                          # ~8.7 from the grunt, farther than the employee
	grunt = MonsterFactory.spawn("grunt", Vector2i(0, 0))
	eq(grunt.employee_chance, 0.3, "about a 30% roll")
	grunt.employee_chance = 1.0
	grunt.aggro(hero)
	var picked := await wait_until(func() -> bool: return grunt.target == emp, 120)
	check(picked, "targets the closer employee when the roll lands")
	var killed := await wait_until(func() -> bool: return emp.dead, 600)
	check(killed, "the grunt killed the employee")
	near(hero.hp, 100.0, 0.001, "the hero was never touched")
	await wait_until(func() -> bool: return grunt.target == hero, 120)
	check(grunt.target == hero, "back to the hero once the employee is gone")
	# roll off: it never switches
	new_world(flat_map(14))
	emp = Employee.spawn(Vector2i(2, 0), {"style": "staff"})
	emp.set_physics_process(false)
	hero = add_hero(Vector2i(5, 0))
	grunt = MonsterFactory.spawn("grunt", Vector2i(0, 0))
	grunt.employee_chance = 0.0
	grunt.aggro(hero)
	await frames(100)
	check(grunt.target == hero, "with the roll off, it keeps chasing the hero")
	# default odds: it happens eventually (seeded, deterministic)
	new_world(flat_map(14))
	seed(4242)
	emp = Employee.spawn(Vector2i(2, 0), {"style": "staff"})
	emp.set_physics_process(false)
	hero = add_hero(Vector2i(5, 0))
	grunt = MonsterFactory.spawn("grunt", Vector2i(0, 0))
	grunt.move_speed = 0.1                                   # stays put, so every retarget roll sees the same picture
	grunt.aggro(hero)
	picked = await wait_until(func() -> bool: return grunt.target == emp, 1200)
	check(picked, "targets an employee within ~20 rolls at the default 30% (seeded)")
	# an employee farther than the hero is ignored, and one beyond aggro range too
	new_world(flat_map(16))
	hero = add_hero(Vector2i(2, 0))                          # ~3.5 from the grunt
	emp = Employee.spawn(Vector2i(-5, 0), {"style": "staff"})   # ~8.7 away, behind the grunt
	emp.set_physics_process(false)
	grunt = MonsterFactory.spawn("grunt", Vector2i(0, 0))
	grunt.employee_chance = 1.0
	grunt.aggro(hero)
	await frames(240)
	check(grunt.target != emp, "ignores an employee that is farther than the hero / out of range")
	# an archer with an employee target: the shot lands as direct damage
	new_world(flat_map(14))
	emp = Employee.spawn(Vector2i(3, 0), {"style": "staff"})
	emp.set_physics_process(false)
	hero = add_hero(Vector2i(6, 0))
	var archer := MonsterFactory.spawn("archer", Vector2i(-2, 0))
	archer.employee_chance = 1.0
	archer.aggro(hero)
	var shot := await wait_until(func() -> bool: return emp.hp < emp.max_hp, 900)
	check(shot, "an archer can hit an employee it targets")

	# --- G: extract -------------------------------------------------------------------------
	new_world(flat_map(10))
	emp = Employee.spawn(Vector2i(0, 0), {"style": "staff"})
	hero = add_hero(Vector2i(1, 0))
	emp.request_follow(hero)
	var rescued_count := [0]
	var rescued_who := [null]
	emp.rescued.connect(func(e: Employee) -> void:
		rescued_count[0] += 1
		rescued_who[0] = e)
	check(not emp.is_extracted(), "not extracted yet")
	emp.extract()
	emp.extract()
	eq(rescued_count[0], 1, "rescued emitted once")
	check(rescued_who[0] == emp, "rescued carries the employee")
	check(emp.is_extracted() and not emp.dead, "extracted, not dead")
	check(Employee.alive().is_empty(), "extracted employees are not counted alive")
	check(not emp.is_in_group("employees"), "left the employees group")
	eq(emp.model.mood(), "cheer", "cheers on the way out")
	await frames(2)
	check(emp.bubble_text() != "", "says thanks")
	check(not Combat.explode(emp.global_position, 3.0, 5.0, -1, hero, 1.0).has(emp), "area blasts no longer reach an extracted employee")
	await frames(120)
	check(not is_instance_valid(emp), "removed after the exit")
	eq(rescued_count[0], 1, "still emitted exactly once")
	# a dead one cannot be extracted
	emp = Employee.spawn(Vector2i(3, 0), {"style": "henchman"})
	var r2 := [0]
	emp.rescued.connect(func(_e: Employee) -> void: r2[0] += 1)
	emp.apply_damage(100.0, hero)
	emp.extract()
	eq(r2[0], 0, "a dead employee is not rescued")
	finish()
