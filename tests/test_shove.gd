extends TestCase
## Actor.shove: distance on flat ground, shove_mult, wall slams (+2 rise), ledge falls with fall
## damage, void (monsters die, heroes are pulled back), friendly-fire protection (a hero-caused
## shove never downs a hero) and monsters that neither steer nor attack nor leash while shoved.

var root: Node3D


## Cells whose center satisfies level_of(x) become that level; level_of returns -999 for "void".
func _map(level_of: Callable, radius: int = 9) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		var lv: int = level_of.call(Hex.to_world(c).x)
		if lv != -999:
			m.set_cell(c, lv)
	return m


func _world(m: HexMap) -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(m, root, 3)


func _actor(team: int, pos: Vector3, hp: float = 100.0) -> Actor:
	var a := Actor.new()
	a.team = team
	a.max_hp = hp
	GameWorld.spawn(a, pos)
	a.snap_to_ground()
	return a


func _hero(pos: Vector3, hp: float = 100.0) -> Hero:
	var h := Hero.new()
	GameWorld.spawn(h, pos)
	h.snap_to_ground()
	h.hp = hp
	return h


## Run physics frames until the actor is no longer shoved (or `max_frames`). Returns frames used.
func _settle(a: Actor, max_frames: int = 180) -> int:
	var n := 0
	while is_instance_valid(a) and a.is_shoved() and n < max_frames:
		await frames(1)
		n += 1
	return n


func setup() -> void:
	var flat := func(_x: float) -> int: return 0

	# --- Flat ground: about the requested distance, ease-out, ends by itself.
	_world(_map(flat))
	var a := _actor(GameWorld.TEAM_MONSTERS, Vector3.ZERO)
	var shoved_seen := [0]
	a.shoved.connect(func(_d: Vector3, _dist: float) -> void: shoved_seen[0] += 1)
	check(not a.is_shoved(), "idle actor is not shoved")
	a.shove(Vector3.RIGHT, 3.0)
	eq(shoved_seen[0], 1, "shoved signal")
	check(a.is_shoved(), "shove starts at once")
	var x_prev := 0.0
	var steps: Array[float] = []
	for i in 6:
		await frames(1)
		steps.append(a.global_position.x - x_prev)
		x_prev = a.global_position.x
	check(steps[0] > steps[5], "ease-out: it starts fast and slows (%s)" % str(steps))
	var used := await _settle(a)
	check(used > 6 and used < 40, "the slide takes a third of a second or so (%d frames)" % used)
	near(a.global_position.x, 3.0, 0.15, "flat shove carries about the requested distance")
	near(a.global_position.z, 0.0, 0.05, "and stays on its line")
	near(a.global_position.y, 0.0, 0.01, "and on the ground")
	check(not a.is_shoved(), "shove ended")
	near(a.hp, a.max_hp, 0.001, "a flat shove does no damage")

	# --- shove_mult: 0 = immovable, 0.5 = half, 1.5 = further.
	var heavy := _actor(GameWorld.TEAM_MONSTERS, Vector3(0, 0, 3))
	heavy.shove_mult = 0.0
	heavy.shove(Vector3.RIGHT, 3.0)
	check(not heavy.is_shoved(), "immovable never starts a shove")
	await frames(30)
	near(heavy.global_position.x, 0.0, 0.001, "shove_mult 0 does not move")
	var half := _actor(GameWorld.TEAM_MONSTERS, Vector3(0, 0, -3))
	half.shove_mult = 0.5
	half.shove(Vector3.RIGHT, 3.0)
	await _settle(half)
	near(half.global_position.x, 1.5, 0.15, "shove_mult 0.5 moves half as far")
	var light := _actor(GameWorld.TEAM_MONSTERS, Vector3(-4, 0, 3))
	light.shove_mult = 1.5
	light.shove(Vector3.RIGHT, 2.0)
	await _settle(light)
	near(light.global_position.x, -1.0, 0.15, "shove_mult 1.5 moves 1.5x as far")

	# --- A shoved actor ignores its own steering.
	var walker := _actor(GameWorld.TEAM_MONSTERS, Vector3(0, 0, 5))
	walker.shove(Vector3.RIGHT, 2.0)
	var before := walker.global_position
	check(not walker.move(Vector3.LEFT, 0.0166), "move() refuses while shoved")
	near(walker.global_position.x, before.x, 0.0001, "and does not move")
	await _settle(walker)
	check(walker.move(Vector3.LEFT, 0.0166), "move() works again afterwards")
	for n in [a, heavy, half, light, walker]:
		n.queue_free()
	await frames(2)

	# --- A +1 rise is walked up (not a slam); a +2 rise stops the shove: wall slam.
	_world(_map(func(x: float) -> int: return 1 if x > 1.5 else 0))
	var step_up := _actor(GameWorld.TEAM_MONSTERS, Vector3.ZERO)
	step_up.shove(Vector3.RIGHT, 3.0)
	await _settle(step_up)
	check(step_up.global_position.x > 2.5, "a +1 rise does not stop a shove (x=%.2f)" % step_up.global_position.x)
	near(step_up.hp, step_up.max_hp, 0.001, "and costs nothing")
	near(step_up.global_position.y, 0.5, 0.02, "and the actor ends up on the higher ground")

	_world(_map(func(x: float) -> int: return 2 if x > 1.5 else 0))
	var slammed := _actor(GameWorld.TEAM_MONSTERS, Vector3.ZERO)
	var impacts: Array[String] = []
	slammed.shove_impact.connect(func(kind: String, _p: Vector3, _amt: float) -> void: impacts.append(kind))
	slammed.shove(Vector3.RIGHT, 4.0)
	await _settle(slammed)
	check(slammed.global_position.x < 0.9 and slammed.global_position.x > 0.3, "a +2 rise stops the shove at the foot of the wall (x=%.2f)" % slammed.global_position.x)
	near(slammed.hp, slammed.max_hp - Actor.WALL_SLAM_DAMAGE, 0.001, "wall slam does 8 damage")
	check(impacts.has("slam"), "slam impact signalled")
	check(slammed.is_staggered(), "and staggers")
	check(slammed.is_helpless(), "a staggered actor is helpless")
	await frames(int(Actor.WALL_SLAM_STAGGER * 60.0) + 4)
	check(not slammed.is_staggered(), "the stagger lasts about 0.4 s")
	slammed.queue_free()

	# --- Ledges: walking forbids a drop over 3 levels, a shove carries you over and you fall.
	var ledge := func(x: float) -> int: return 5 if x < 0.4 else 0
	_world(_map(ledge))
	var high := _actor(GameWorld.TEAM_MONSTERS, Hex.to_world(Vector2i.ZERO, 5))
	near(high.global_position.y, 2.5, 0.001, "starts on the +5 ledge")
	high.shove(Vector3.RIGHT, 3.5)
	var ys: Array[float] = []
	var guard := 0
	while high.is_shoved() and guard < 200:
		await frames(1)
		ys.append(high.global_position.y)
		guard += 1
	var mid := ys.filter(func(y: float) -> bool: return y > 0.1 and y < 2.4).size()
	check(mid >= 4, "the fall takes several frames, not a teleport (%d frames in between)" % mid)
	near(high.global_position.y, 0.0, 0.001, "lands on the lower ground")
	check(high.global_position.x > 1.7, "and on the lower cell (x=%.2f)" % high.global_position.x)
	near(high.hp, high.max_hp - 12.0, 0.001, "a 5-level fall costs 6 per level beyond 3 = 12")
	check(high.is_staggered(), "a hard landing staggers")
	var monotone := true
	for i in range(1, ys.size()):
		if ys[i] > ys[i - 1] + 0.001 and ys[i - 1] > 0.1:
			monotone = false
	check(monotone, "it only goes down while falling")
	high.queue_free()

	# Drops of 3 are free, 4 costs 6.
	for drop in [3, 4]:
		var d: int = drop
		_world(_map(func(x: float) -> int: return d if x < 0.4 else 0))
		var f := _actor(GameWorld.TEAM_MONSTERS, Hex.to_world(Vector2i.ZERO, d))
		f.shove(Vector3.RIGHT, 3.5)
		await _settle(f)
		near(f.hp, f.max_hp - (0.0 if d == 3 else 6.0), 0.001, "a %d-level drop costs %s" % [d, "nothing" if d == 3 else "6"])
		check(f.global_position.y < 0.01, "and lands")

	# --- Void: a monster is shoved into the pit and dies; a hero is pulled back to safe ground.
	_world(_map(func(x: float) -> int: return 0 if x < 2.0 else -999))
	var grunt := MonsterFactory.spawn("grunt", Vector2i.ZERO)
	var died := [false]
	grunt.died.connect(func() -> void: died[0] = true)
	grunt.shove(Vector3.RIGHT, 5.0)
	var fell := 0
	for i in 150:
		await frames(1)
		if grunt.is_airborne():
			fell += 1
		if died[0]:
			break
	check(died[0], "a monster shoved into the void dies")
	check(fell >= 20, "after a visible fall (%d frames)" % fell)
	_world(_map(func(x: float) -> int: return 0 if x < 2.0 else -999))
	var hero := _hero(Vector3.ZERO)
	hero.shove(Vector3.RIGHT, 5.0)
	var far_x := 0.0
	var h_guard := 0
	while hero.is_shoved() and h_guard < 200:
		await frames(1)
		far_x = maxf(far_x, hero.global_position.x)
		h_guard += 1
	check(far_x > 1.2, "the hero was carried toward the pit (%.2f)" % far_x)
	check(not hero.dead, "a hero in the void is not killed")
	near(hero.global_position.x, 0.0, 0.1, "and ends on the last safe cell")
	near(hero.global_position.y, 0.0, 0.01, "at ground level")
	near(hero.hp, 100.0 - Actor.VOID_TICK_DAMAGE, 0.001, "taking a small damage tick")

	# --- Friendly fire never downs a hero.
	_world(_map(func(x: float) -> int: return 2 if x > 1.5 else 0))
	var src_hero := _hero(Vector3(-4, 0, 4))
	var victim := _hero(Vector3.ZERO, 5.0)
	victim.shove(Vector3.RIGHT, 4.0, src_hero)
	await _settle(victim)
	near(victim.hp, 1.0, 0.001, "a hero-caused wall slam leaves a hero at 1 HP, not dead")
	check(not victim.dead, "and alive")
	victim.free()
	var villain := _actor(GameWorld.TEAM_MONSTERS, Vector3(-4, 0, -4))
	var victim2 := _hero(Vector3.ZERO, 5.0)
	victim2.shove(Vector3.RIGHT, 4.0, villain)
	await _settle(victim2)
	check(victim2.dead, "the same slam caused by a monster can down a hero (hp %.1f)" % victim2.hp)
	victim2.free()
	var victim3 := _hero(Vector3(0, 0, 2), 5.0)
	victim3.shove(Vector3.RIGHT, 4.0)
	await _settle(victim3)
	check(victim3.dead, "and so can an unattributed one")
	# Falls.
	_world(_map(func(x: float) -> int: return 5 if x < 0.4 else 0))
	src_hero = _hero(Vector3(0, 0, 6))
	var faller := _hero(Hex.to_world(Vector2i.ZERO, 5), 10.0)
	faller.shove(Vector3.RIGHT, 3.5, src_hero)
	await _settle(faller)
	near(faller.hp, 1.0, 0.001, "a hero-caused fall (12 damage) leaves a 10 HP hero at 1")
	# Pit.
	_world(_map(func(x: float) -> int: return 0 if x < 2.0 else -999))
	src_hero = _hero(Vector3(-3, 0, 5))
	var pitted := _hero(Vector3.ZERO, 3.0)
	pitted.shove(Vector3.RIGHT, 5.0, src_hero)
	await _settle(pitted)
	near(pitted.hp, 1.0, 0.001, "a hero-caused pit tick leaves a 3 HP hero at 1")

	# --- A shoved monster neither attacks, steers nor leashes home and heals.
	_world(_map(flat))
	var target := _actor(GameWorld.TEAM_HEROES, Vector3.ZERO)
	var gr := MonsterFactory.spawn("grunt", Vector2i(1, 0)) as Monster      # 1.73 away: in striking range
	gr.global_position = Vector3(1.2, 0, 0)
	gr.leash_range = 2.0
	gr.hp = 25.0
	gr.aggro(target)
	var windup := false
	for i in 40:
		await frames(1)
		if gr.state == Monster.State.ATTACK:
			windup = true
			break
	check(windup, "the grunt winds up an attack on the adjacent hero")
	gr.shove(Vector3.RIGHT, 5.0, null)
	check(gr.state != Monster.State.ATTACK, "a shove cancels the wind-up")
	var x_last := gr.global_position.x
	var never_back := true
	while gr.is_shoved():
		await frames(1)
		if gr.global_position.x < x_last - 0.001:
			never_back = false
		x_last = gr.global_position.x
		near(target.hp, 100.0, 0.001, "no attack lands while the monster is shoved")
		check(gr.state != Monster.State.RETURN, "no leashing while shoved")
	check(never_back, "it does not steer back toward the hero while shoved")
	check(gr.global_position.x > 5.0, "it was carried well past its leash radius (%.2f)" % gr.global_position.x)
	near(gr.hp, 25.0, 0.001, "and did not heal")
	check(gr.state != Monster.State.RETURN, "being shoved away is not leashing home")
	near(GameWorld.flat_distance(gr.home, gr.global_position), 0.0, 0.01, "it re-homes where it landed")
	await frames(30)
	near(gr.hp, 25.0, 0.001, "still no heal after the shove")
	check(gr.state != Monster.State.RETURN, "and it still never went home")
	finish()
