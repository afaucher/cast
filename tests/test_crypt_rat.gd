extends MonsterTestBase
## The crypt rat (docs/design/haunted-build-plan.md, H3b), solo: the dead family's fast swarm.
## - the `crypt_rat` kind spawns a CryptRat wearing the sewer brute (RatModel "sewer") with the pounce tell; a family kind of
##   the dead (never a hellgate pack's), not a contract pest; faster than a zombie or a skeleton, low HP;
## - in a fight it winds up the POUNCE (the monsters' wind-up, RAT_WINDUP: flattened and drawn back, the tail up, the wind-up
##   tint on) and only then bites: the hero is untouched through the tell and takes the bite after it;
## - a pack pick is a clump of 5-6 (a dead family's pack, PackPlanner's placing);
## - killed, it dies and is freed like any monster (no body).


func setup() -> void:
	new_world(flat_map(12))
	_spawn_and_stats()
	await _tell_then_bite()
	await _pounce_pose()
	await _pack_clump()
	await _dies_freed()
	finish()


func _hero_at(cell: Vector2i) -> Actor:
	var h := add_hero(cell)
	h.max_hp = 1000.0
	h.hp = 1000.0
	return h


func _spawn_and_stats() -> void:
	var r := MonsterFactory.spawn("crypt_rat", Vector2i(2, 0)) as CryptRat
	if not check(r != null, "the crypt_rat kind spawns a CryptRat"):
		return
	eq(r.kind, "crypt_rat", "its kind")
	eq(r.display_name, "Crypt rat", "its name")
	check(r.model is RatModel, "it wears RatModel")
	if r.model is RatModel:
		eq((r.model as RatModel).variant, "sewer", "the sewer brute (the user's pick)")
		eq((r.model as RatModel).tell, "pounce", "with the pounce tell")
	eq(MonsterDefs.family_of("crypt_rat"), "dead", "a dead family kind")
	check(MonsterDefs.is_swarm("crypt_rat"), "a swarm kind")
	var z := MonsterFactory.spawn("zombie", Vector2i(2, 2))
	var g := MonsterFactory.spawn("grunt", Vector2i(-2, 2))
	check(r.move_speed > g.move_speed * 1.4 and r.move_speed > z.move_speed * 3.0, "fast: %.1f (a skeleton %.1f, a zombie %.1f)" % [r.move_speed, g.move_speed, z.move_speed])
	check(r.max_hp < g.max_hp, "low HP (%.0f, a skeleton %.0f)" % [r.max_hp, g.max_hp])
	check(r.attack_windup > 0.3, "a readable tell (%.2f s, the imp's 0.3)" % r.attack_windup)
	r.free()
	z.free()
	g.free()


## The tell, then the bite: the hero is untouched through the wind-up.
func _tell_then_bite() -> void:
	new_world(flat_map(12))
	var hero := _hero_at(Vector2i(0, 0))
	var r := MonsterFactory.spawn("crypt_rat", Vector2i(4, 0)) as CryptRat
	await frames(2)
	var told := [-1.0]
	var hp_at_tell := [0.0]
	r.windup_begun.connect(func(l: float) -> void:
		if told[0] < 0.0:
			told[0] = GameWorld.time
			hp_at_tell[0] = hero.hp
			near(l, CryptRat.RAT_WINDUP, 0.001, "the tell is the %.2f s wind-up" % CryptRat.RAT_WINDUP))
	r.aggro(hero)
	check(await wait_until(func() -> bool: return told[0] >= 0.0, 300), "it closes in and winds up")
	near(hp_at_tell[0], 1000.0, 0.001, "nothing bit before the tell")
	# through the tell: no damage
	var mid := false
	var early := -1.0
	while GameWorld.time < told[0] + CryptRat.RAT_WINDUP * 0.85:
		if not mid and r.state == Monster.State.ATTACK and r._telegraph > 0.4:
			mid = true
			check(r.model.wind_e() > 0.2, "the model is in its tell")
			check(r._tint_key > 0.0, "the wind-up tint is on")
		if hero.hp < 1000.0:
			early = GameWorld.time - told[0]
			break
		await get_tree().physics_frame
	check(early < 0.0, "untouched through the tell (bitten %.2f s in)" % early)
	check(mid, "the tell was seen half way through")
	check(await wait_until(func() -> bool: return hero.hp < 1000.0, 60), "then the bite lands")
	near(hero.hp, 1000.0 - CryptRat.RAT_DAMAGE, 0.001, "a bite: %.0f" % CryptRat.RAT_DAMAGE)
	check(GameWorld.time - told[0] >= CryptRat.RAT_WINDUP - 0.02, "after the whole tell (%.2f s)" % (GameWorld.time - told[0]))


## The pounce pose: flat and drawn back, the jaw open, the tail up off the floor (not the look test's rear-up).
func _pounce_pose() -> void:
	var m := RatModel.new("sewer")
	m.tell = "pounce"
	add_child(m)
	m.idle_enabled = false
	m.pose_preview("rest")
	var body := m.get_part("body") as Node3D
	var rest_y := body.position.y
	var rest_z := body.position.z
	var tail_rest := (m.get_part("tail") as Node3D).global_transform * Vector3(0, 0, 0.4)
	m.pose_preview("windup", 1.0)
	check(body.rotation.x < 0.0, "pounce: flat, not reared (pitch %.2f)" % body.rotation.x)
	check(body.position.y < rest_y - 0.08, "pounce: crouched low (%.2f from %.2f)" % [body.position.y, rest_y])
	check(body.position.z > rest_z + 0.12, "pounce: drawn back (%.2f)" % body.position.z)
	check((m.get_part("jaw") as Node3D).rotation.x < -0.6, "pounce: the jaw open")
	var tail_up := (m.get_part("tail") as Node3D).global_transform * Vector3(0, 0, 0.4)
	check(tail_up.y > tail_rest.y + 0.15, "pounce: the tail up off the floor (%.2f from %.2f)" % [tail_up.y, tail_rest.y])
	m.pose_preview("swing", 1.0)
	check(body.position.z < -0.4, "the bite: a long snap forward (%.2f)" % body.position.z)
	m.queue_free()
	await frames(1)


## A dead family's pack places a rat pick as a clump of 5-6.
func _pack_clump() -> void:
	var map := flat_map(12)
	for c in map.cells:
		map.cells[c].tag = "room:1"
	new_world(map)
	var cells: Array[Vector2i] = []
	cells.assign(map.cells.keys())
	var sizes := {}
	for s in 12:
		var site := SiteBuilder.Site.new()
		site.pest = "zombie"
		var rng := RandomNumberGenerator.new()
		rng.seed = 100 + s
		var kinds: Array[String] = ["crypt_rat"]
		var n := PackPlanner._place_kinds(map, cells, kinds, rng, site)
		sizes[n] = true
		check(n >= 5 and n <= 6, "a rat pick places 5-6 rats (%d)" % n)
		var centre := Vector3.ZERO
		for m in site.monsters:
			centre += m.global_position / float(site.monsters.size())
		for m in site.monsters:
			check(m is CryptRat and GameWorld.flat_distance(m.global_position, centre) < 4.0, "... in a clump")
			m.free()
	check(sizes.has(5) and sizes.has(6), "clumps of 5 and of 6 both happen")
	await frames(1)


## Killed: freed like any monster, no body.
func _dies_freed() -> void:
	new_world(flat_map(8))
	var hero := _hero_at(Vector2i(-3, 0))
	var r := MonsterFactory.spawn("crypt_rat", Vector2i(2, 0))
	var wr: WeakRef = weakref(r)
	r.apply_damage(9999.0, hero)
	check(r.dead, "it dies")
	check(not GameWorld.downed_in_radius(r.global_position, 1.0).has(r), "no body: nothing for the downed query")
	check(await wait_until(func() -> bool: return wr.get_ref() == null, 200), "it is freed (topple, fade, gone)")
