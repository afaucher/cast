extends MonsterTestBase
## Dismissing and recalling employees with E (PlayerController.press_use -> Employee.interact):
## E near your follower tells it to wait, a waiting one never rejoins by proximity, E recruits it again, the
## elevator wins when the hero stands at it, E with nobody to talk to does nothing (and never casts), another hero's follower is
## not yours to dismiss, a waiting employee still panics and then walks back to its spot, and it stays alive
## (counted for the $10) but is not a follower (so the elevator would not take it).

var casts: Array = []


func _init() -> void:
	timeout_sec = 120.0


## A real player hero (PlayerController, one spell) at `cell`.
func _player(cell: Vector2i) -> Hero:
	var h := HeroFactory.spawn_hero(cell, "Aria", Color.BLUE, "sword", null)
	var pc := HeroFactory.make_player(h, ["heal"] as Array[String])
	pc.enabled = false                      # no keyboard / mouse steering in a test
	pc.aim_override = h.global_position + Vector3(3, 0, 0)
	h.spell_cast.connect(func(id: String, _p: float) -> void: casts.append(id))
	return h


func _pc(h: Hero) -> PlayerController:
	return h.get_node("PlayerController") as PlayerController


func setup() -> void:
	InputSetup.ensure_actions()
	check(Employee.JOIN_NEEDS_E, "joining needs E (JOIN_NEEDS_E is on)")

	# --- A: E dismisses your follower ---------------------------------------------------------
	new_world(flat_map(16))
	casts.clear()
	var hero := _player(Vector2i(0, 0))
	var emp := Employee.spawn(Vector2i(1, 0), {"style": "staff", "name": "Marguerite"})
	await frames(60)
	check(not emp.is_following() and emp.state == Employee.State.COWER, "walking up to an employee does not recruit them")
	check(not emp.is_dismissed(), "(they were never dismissed)")
	eq(Employee.interact_prompt(hero), "E: bring Marguerite", "the prompt offers to bring a cowering employee")
	check(_pc(hero).press_use(), "E near a cowering employee is used")
	check(emp.is_following() and emp.leader() == hero, "E recruits them: the hero is the leader")
	await frames(2)
	eq(emp.bubble_text(), "oh, thank you!", "first contact bark")
	eq(casts.size(), 0, "no cast")
	eq(Employee.interact_prompt(hero), "E: tell Marguerite to wait", "the prompt offers to dismiss your follower")
	var spot := emp.global_position
	check(_pc(hero).press_use(), "E near your follower is used")
	eq(emp.state, Employee.State.WAIT, "the employee waits")
	check(emp.is_waiting() and emp.is_dismissed(), "waiting and dismissed")
	check(not emp.is_following() and emp.leader() == null, "no longer following")
	eq(emp.model.mood(), "cower", "crouched at its spot")
	await frames(2)
	eq(emp.bubble_text(), "Waiting here.", "a bark over the employee")
	eq(casts.size(), 0, "the press did not cast")
	check(Employee.alive().has(emp), "a waiting employee is still alive (still pays the $10)")
	check(not emp.is_following(), "and it is not a follower, so the elevator would not take it")

	# --- B: a dismissed employee does not rejoin by proximity ----------------------------------
	hero.global_position = spot + Vector3(1.0, 0.0, 0.0)          # well inside JOIN_RANGE
	await frames(90)
	eq(emp.state, Employee.State.WAIT, "still waiting with the hero standing right there")
	check(emp.leader() == null and emp.is_dismissed(), "no leader, still dismissed")
	check(emp.global_position.distance_to(spot) < 0.05, "it stays put")
	eq(Employee.interact_prompt(hero), "E: bring Marguerite", "the prompt offers to bring a waiting one")

	# --- C: E recalls ---------------------------------------------------------------------------
	hero.global_position = spot + Vector3(1.9, 0.0, 0.0)          # inside RECALL_RANGE (2.2)
	check(_pc(hero).press_use(), "E near a waiting employee is used")
	check(emp.is_following() and emp.leader() == hero, "it follows again")
	check(not emp.is_dismissed(), "no longer dismissed")
	await frames(2)
	eq(emp.bubble_text(), "Right behind you!", "a bark on the way")
	eq(emp.model.mood(), "follow", "walking pose")
	eq(casts.size(), 0, "still no cast")
	# a waiting employee out of reach is not offered
	check(_pc(hero).press_use(), "dismissed again")
	hero.global_position = emp.global_position + Vector3(3.0, 0.0, 0.0)
	eq(Employee.interact_prompt(hero), "", "no prompt from 3 away")
	check(not Employee.interact(hero), "E from 3 away does nothing to it")
	eq(emp.state, Employee.State.WAIT, "still waiting")

	# --- D: the elevator wins when the hero stands at it ----------------------------------------
	new_world(flat_map(16))
	casts.clear()
	hero = _player(Vector2i(0, 0))
	emp = Employee.spawn(Vector2i(1, 0), {"style": "henchman", "name": "Gary"})
	check(emp.request_follow(hero), "recruit Gary")
	var used := [0]
	_pc(hero).interact = func() -> bool:
		used[0] += 1
		return true
	check(_pc(hero).press_use(), "E at the elevator is used")
	eq(int(used[0]), 1, "by the context action")
	check(emp.is_following(), "the employee was not dismissed")
	eq(casts.size(), 0, "and nothing was cast")
	_pc(hero).interact = func() -> bool: return false   # not at the elevator any more
	check(_pc(hero).press_use(), "away from the elevator E goes to the employee")
	eq(emp.state, Employee.State.WAIT, "dismissed")
	eq(casts.size(), 0, "without a cast")

	# --- E: with no employee nearby, E does nothing and casts nothing --------------------------
	new_world(flat_map(16))
	casts.clear()
	hero = _player(Vector2i(0, 0))
	emp = Employee.spawn(Vector2i(6, 0), {"style": "staff"})        # ~10 away: hiding, out of reach
	_pc(hero).interact = Callable()
	check(Employee.interact_target(hero) == null, "nothing to talk to")
	eq(Employee.interact_prompt(hero), "", "no prompt")
	check(not _pc(hero).press_use(), "E with nothing to use is not used")
	eq(casts.size(), 0, "and casts nothing")
	eq(hero.charges_of("heal"), SpellComponents.START_CHARGES, "no charge spent")
	near(hero.cooldown_left("heal"), 0.0, 0.0001, "no cooldown spent")
	eq(emp.state, Employee.State.COWER, "the far employee was left alone")
	# a follower that trails out of reach is not dismissed either: E does nothing
	new_world(flat_map(16))
	casts.clear()
	hero = _player(Vector2i(0, 0))
	emp = Employee.spawn(Vector2i(1, 0), {"style": "staff"})
	check(emp.request_follow(hero), "recruit")
	emp.set_physics_process(false)
	hero.global_position = emp.global_position + Vector3(Employee.WAIT_RANGE + 1.0, 0.0, 0.0)
	check(not _pc(hero).press_use(), "E does nothing when the follower is too far")
	eq(casts.size(), 0, "and casts nothing")
	check(emp.is_following(), "still following")

	# --- F: another hero's follower is not yours to dismiss -----------------------------------
	new_world(flat_map(16))
	casts.clear()
	var other := add_hero(Vector2i(1, 0))                       # a plain second player's hero, nearest to the employee
	emp = Employee.spawn(Vector2i(2, 0), {"style": "staff"})
	hero = _player(Vector2i(4, 0))                              # ~3.5 from the employee
	check(emp.request_follow(other), "the other hero recruits it")
	check(emp.leader() == other, "it follows the other hero")
	hero.global_position = emp.global_position + Vector3(0.0, 0.0, 1.0)   # right next to it
	check(not emp.can_wait(hero) and not emp.can_follow(hero), "not yours to dismiss or take")
	eq(Employee.interact_prompt(hero), "", "no prompt for somebody else's follower")
	check(not _pc(hero).press_use(), "E does nothing and casts nothing")
	eq(casts.size(), 0, "no cast")
	check(emp.is_following() and emp.leader() == other, "the other hero keeps their follower")
	check(not emp.request_wait(hero) and not emp.request_follow(hero), "the requests are refused too")

	# an employee that picked up an AI ally can be dismissed by the player
	new_world(flat_map(16))
	casts.clear()
	var ally := HeroFactory.spawn_hero(Vector2i(1, 0), "Rebar", Color.ORANGE, "sword", null)
	emp = Employee.spawn(Vector2i(2, 0), {"style": "staff"})
	hero = _player(Vector2i(4, 0))
	check(emp.request_follow(ally), "an employee following an AI ally")
	check(emp.leader() == ally, "led by the ally")
	hero.global_position = emp.global_position + Vector3(0.0, 0.0, 1.2)
	check(_pc(hero).press_use() and emp.state == Employee.State.WAIT, "the player's E dismisses an ally's follower")
	eq(casts.size(), 0, "without a cast")

	# --- G: a waiting employee still panics, then walks back to its spot ---------------------
	new_world(flat_map(18))
	casts.clear()
	hero = _player(Vector2i(0, 0))
	emp = Employee.spawn(Vector2i(1, 0), {"style": "staff", "name": "Hodges"})
	check(emp.request_follow(hero), "recruit Hodges")
	_pc(hero).press_use()
	var home := emp.global_position
	hero.global_position = home + Vector3(-9.0, 0.0, 0.0)      # the crew leaves
	var grunt := MonsterFactory.spawn("grunt", Hex.from_world(home + Vector3(2.5, 0.0, 0.0)))
	grunt.set_physics_process(false)                           # a statue: only its distance matters
	check(await wait_until(func() -> bool: return emp.state == Employee.State.PANIC, 40), "a waiting employee still panics")
	check(emp.is_dismissed(), "and is still dismissed")
	check(await wait_until(func() -> bool: return fdist(emp, grunt) > Employee.PANIC_RANGE + 1.0, 200), "it ran away")
	var strayed := emp.global_position.distance_to(home)
	check(strayed > 1.0, "off its spot (%.2f)" % strayed)
	hero.global_position = emp.global_position + Vector3(1.0, 0.0, 0.0)   # the hero is right there while it flees
	grunt.free()
	check(await wait_until(func() -> bool: return emp.state == Employee.State.WAIT, 600), "calms down into waiting, not cowering")
	check(emp.leader() == null, "it did not latch onto the hero beside it")
	hero.global_position = home + Vector3(-9.0, 0.0, 0.0)
	var back := await wait_until(func() -> bool: return emp.global_position.distance_to(home) < Employee.WAIT_ARRIVED + 0.1, 900)
	check(back, "walked back to its spot (%.2f away)" % emp.global_position.distance_to(home))
	await frames(5)
	eq(emp.model.mood(), "cower", "crouched again once there")
	eq(emp.state, Employee.State.WAIT, "waiting")
	# hit while waiting: it panics too
	emp.apply_damage(3.0, hero)
	eq(emp.state, Employee.State.PANIC, "a hit sends a waiting employee into a panic")
	hero.global_position = emp.global_position + Vector3(1.0, 0.0, 0.0)
	check(_pc(hero).press_use() and emp.is_following(), "E recruits even a panicking dismissed employee")
	finish()
