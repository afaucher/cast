extends MonsterTestBase
## The ecto blob and its slick (docs/design/haunted-build-plan.md, H3b), solo: the dead family's slow area denial.
## - the `ecto_blob` kind spawns an EctoBlob wearing the mass of faces (EctoBlobModel "faces", its faces' eyes glowing); a
##   family kind of the dead, one a pack; slower than a zombie;
## - any hit kills it (its HP is under the weakest hero hit; a hero's plain melee through Combat does it);
## - crawling it lays a slick behind it, a segment every SLICK_STEP, one chain numbered without a gap, drawn as ONE ribbon of
##   the ectoplasm look's film (EctoplasmLook.trail);
## - the slick slows a hero (and the staff) standing on it, x SLOW, never a monster;
## - the real Damp washes away the segments its drizzle reaches (the ribbon splits round the gap) and leaves the rest;
## - a segment dries up after LIFE; a copy (online, a client's) is never washed by its own machine's Damp (the host decides);
## - idle with a hero near, it wanders its room slowly (laying slick); killed, it is freed and its slick stays.


func setup() -> void:
	_spawn_and_look()
	await _any_hit_kills()
	await _lays_slick()
	await _slows_heroes()
	await _damp_washes()
	await _dries_and_copies()
	await _idle_wander()
	finish()


func _hero_at(p: Vector3) -> Actor:
	var h := add_hero(Hex.from_world(p))
	h.global_position = Vector3(p.x, 0.0, p.z)
	h.max_hp = 1000.0
	h.hp = 1000.0
	h.move_speed = 4.0
	return h


func _spawn_and_look() -> void:
	new_world(flat_map(12))
	var b := MonsterFactory.spawn("ecto_blob", Vector2i(2, 0)) as EctoBlob
	if not check(b != null, "the ecto_blob kind spawns an EctoBlob"):
		return
	eq(b.kind, "ecto_blob", "its kind")
	eq(b.display_name, "Ecto blob", "its name")
	check(b.model is EctoBlobModel, "it wears EctoBlobModel")
	if b.model is EctoBlobModel:
		eq((b.model as EctoBlobModel).variant, "faces", "the mass of faces (the user's pick)")
		check((b.model as EctoBlobModel).has_part("face_eyes"), "its faces' eyes glow")
	eq(MonsterDefs.family_of("ecto_blob"), "dead", "a dead family kind")
	var z := MonsterFactory.spawn("zombie", Vector2i(-2, 2))
	check(b.move_speed < z.move_speed, "slow: %.2f (a zombie %.2f)" % [b.move_speed, z.move_speed])
	check(b.attack_windup >= 0.8, "a long tell (%.2f s)" % b.attack_windup)
	b.free()
	z.free()


## Any hit kills it: its HP is under the weakest hero hit, and a plain melee arc (no spell) drops it.
func _any_hit_kills() -> void:
	new_world(flat_map(10))
	var weakest := Hero.ARROW_TAP_DAMAGE
	for k: String in HeroKit.DATA:
		weakest = minf(weakest, float((HeroKit.DATA[k] as Dictionary).get("melee_damage", weakest)))
	check(EctoBlob.HP <= weakest, "its HP (%.0f) is no more than the weakest hero hit (%.0f)" % [EctoBlob.HP, weakest])
	var hero := _hero_at(Vector3(0.0, 0.0, 0.0))
	var b := MonsterFactory.spawn("ecto_blob", Hex.from_world(Vector3(0.0, 0.0, -1.2)))
	b.global_position = Vector3(0.0, 0.0, -1.2)
	b.aggro_range = 0.0
	await frames(2)
	Combat.melee_arc(hero, Vector3(0, 0, -1), 1.6, 90.0, weakest, 0.0)
	check(b.dead, "one plain melee hit of %.0f kills it" % weakest)
	var wr: WeakRef = weakref(b)
	check(await wait_until(func() -> bool: return wr.get_ref() == null, 200), "it is freed like any monster (no body)")


## Crawling after a hero, it lays a chain of segments behind it, drawn as one ribbon.
func _lays_slick() -> void:
	new_world(flat_map(14))
	var hero := _hero_at(Vector3(6.0, 0.0, 0.0))
	var b := MonsterFactory.spawn("ecto_blob", Hex.from_world(Vector3(-5.0, 0.0, 0.0))) as EctoBlob
	b.global_position = Vector3(-5.0, 0.0, 0.0)
	await frames(2)
	b.aggro(hero)
	check(await wait_until(func() -> bool: return b.slick_laid >= 4, 600), "it lays slick as it crawls (%d segments)" % b.slick_laid)
	await frames(2)
	var segs := EctoSlick.live()
	check(segs.size() >= 4, "the segments are on the floor (%d)" % segs.size())
	var seqs: Array[int] = []
	var chain := -1
	for s in segs:
		seqs.append(s.seq)
		chain = s.chain if chain < 0 else chain
		check(s.chain == chain, "one chain")
		near(s.a.distance_to(s.b), EctoBlob.SLICK_STEP, 0.25, "a segment is about SLICK_STEP long")
	seqs.sort()
	eq(seqs[seqs.size() - 1] - seqs[0], seqs.size() - 1, "numbered without a gap")
	check(GameWorld.flat_distance(segs[segs.size() - 1].b, b.global_position) < EctoBlob.SLICK_STEP + 0.3, "the newest end is under the blob")
	var ribbons: Array = EctoSlick._looks.get(chain, [])
	eq(ribbons.size(), 1, "drawn as one ribbon")
	if ribbons.size() == 1:
		var rib: Node3D = ribbons[0]
		check(rib.is_in_group(EctoplasmLook.GROUP), "the ectoplasm look's own (the film)")
		var sheet: MeshInstance3D = null
		for c in rib.get_children():
			if c.name.begins_with("Sheet"):
				sheet = c
		if check(sheet != null, "a sheet mesh"):
			var span := sheet.mesh.get_aabb()
			check(span.size.x > float(segs.size() - 1) * EctoBlob.SLICK_STEP * 0.8, "it runs the length of the path (%.2f)" % span.size.x)
	b.queue_free()
	await frames(2)


## The slick slows a hero standing on it (and the staff), never a monster.
func _slows_heroes() -> void:
	new_world(flat_map(10))
	var s := EctoSlick.make(Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), GameWorld.time, 1, 0)
	await frames(1)
	var hero := _hero_at(Vector3(0.2, 0.0, 0.3))
	near(EctoSlick.speed_mult(hero), EctoSlick.SLOW, 0.001, "a hero on the slick walks at x%.2f" % EctoSlick.SLOW)
	near(hero.effective_speed(), hero.move_speed * EctoSlick.SLOW, 0.001, "... its walking speed")
	var off := _hero_at(Vector3(0.2, 0.0, 2.0))
	near(EctoSlick.speed_mult(off), 1.0, 0.001, "beside it: no slow")
	var staff := Actor.new()
	staff.team = GameWorld.TEAM_NEUTRAL
	staff.add_to_group("employees")
	GameWorld.spawn(staff, Vector3(-0.5, 0.0, 0.0))
	near(EctoSlick.speed_mult(staff), EctoSlick.SLOW, 0.001, "the staff are slowed too")
	var g := MonsterFactory.spawn("grunt", Vector2i(0, 0))
	g.global_position = Vector3(0.0, 0.0, 0.0)
	near(EctoSlick.speed_mult(g), 1.0, 0.001, "a monster is not (the dead's own ooze)")
	s.queue_free()
	await frames(2)
	near(EctoSlick.speed_mult(hero), 1.0, 0.001, "gone: no slow")


## The real Damp washes away the segments its drizzle reaches; the ribbon splits round the gap.
func _damp_washes() -> void:
	new_world(flat_map(14))
	var segs: Array[EctoSlick] = []
	for i in 20:
		segs.append(EctoSlick.make(Vector3(-16.0 + i, 0.0, 0.0), Vector3(-15.0 + i, 0.0, 0.0), GameWorld.time, 7, i))
	await frames(2)
	eq((EctoSlick._looks.get(7, []) as Array).size(), 1, "twenty segments: one ribbon")
	var caster := _hero_at(Vector3(0.0, 0.0, 6.0))
	var d := DampSpell.cast(caster, 1.0, Vector3(-4.5, 0.0, 0.0), GameWorld.time, {}) as Damp
	var mid := segs[11]
	var wm: WeakRef = weakref(mid)
	check(await wait_until(func() -> bool: return wm.get_ref() == null or (wm.get_ref() as EctoSlick).washed, 90), "Damp washes the slick under it")
	await frames(40)
	var left := EctoSlick.live()
	check(left.size() > 0 and left.size() < 20, "only the segments the drizzle reached (%d of 20 left)" % left.size())
	check(is_instance_valid(segs[0]) and not segs[0].washed, "the old end stays")
	check(is_instance_valid(segs[19]) and not segs[19].washed, "... and the new end")
	var radius := DampSpell.damp_radius(1.0)
	for s in left:
		check(s.line_distance(Vector3(-4.5, 0.0, 0.0)) > radius + s.width * 0.5 - 0.01, "a live segment is out of the drizzle")
	eq((EctoSlick._looks.get(7, []) as Array).size(), 2, "the ribbon split in two round the gap")
	var walker := _hero_at(Vector3(-4.5, 0.0, 0.0))
	near(EctoSlick.speed_mult(walker), 1.0, 0.001, "no slow where it was washed")
	check(is_instance_valid(d), "Damp's own wet floor stays")
	await frames(2)


## A segment dries up after LIFE; a copy is not washed by this machine's Damp (its owner decides).
func _dries_and_copies() -> void:
	new_world(flat_map(10))
	var old := EctoSlick.make(Vector3(-3.0, 0.0, 2.0), Vector3(-2.0, 0.0, 2.0), GameWorld.time - EctoSlick.LIFE + 0.2, 3, 0)
	var wo: WeakRef = weakref(old)
	check(await wait_until(func() -> bool: return wo.get_ref() == null, 40), "a segment dries up after %.0f s" % EctoSlick.LIFE)
	var copy := EctoSlick.make(Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), GameWorld.time, 4, 0)
	copy.net_make_copy()
	eq(EctoSlick.wash_at(Vector3(0.5, 0.0, 0.0), 2.0), 0, "a copy is not this machine's to wash")
	check(not copy.washed, "... it stays until its owner says")
	copy.net_event("obj.slick", {"id": 1, "st": EctoSlick.STATE_WASHED}, NetObjects.new())
	check(copy.washed, "the owner's obj.slick washes it")
	await frames(40)
	check(not is_instance_valid(copy), "... and it goes")


## Idle with a hero near (not in sight), it wanders its room slowly, laying slick; killed, its slick stays.
func _idle_wander() -> void:
	var map := flat_map(12)
	for c in map.cells:
		map.cells[c].tag = "room:1"
	new_world(map)
	var b := MonsterFactory.spawn("ecto_blob", Vector2i(0, 0)) as EctoBlob
	b.aggro_range = 0.5   # (blind to a hero 9 away behind it; 0 would freeze it: no idle life)
	b.set_spawn_facing(Vector3(0, 0, -1))
	var hero := _hero_at(Vector3(0.0, 0.0, 9.0))
	await frames(2)
	var start := b.global_position
	var moved := [0.0]
	await wait_until(func() -> bool:
		moved[0] = maxf(moved[0], GameWorld.flat_distance(b.global_position, start))
		return b.slick_laid >= 2, 1200)
	check(moved[0] > 0.6, "it wanders off its spot (%.2f)" % moved[0])
	check(b.slick_laid >= 2, "laying slick as it goes (%d)" % b.slick_laid)
	var n := EctoSlick.live().size()
	b.apply_damage(9999.0, hero)
	await frames(5)
	eq(EctoSlick.live().size(), n, "killed: its slick stays")
