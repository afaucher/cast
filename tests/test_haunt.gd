extends MonsterTestBase
## Ghosts and their hosts (docs/design/haunted-build-plan.md, "H5 as built"), solo, on a flat arena:
## - the kinds: a suit of armour (ArmourHost, the knight) and a skeleton (BonesHost) a ghost can possess, and the ghost (Wisp);
## - DORMANT: a host with no ghost is a piece of the room: the priced suit's look and tag, no AI, out of the monsters, a knock
##   does not start a fight, no shout or noise wakes it, the AI allies leave it be;
## - POSSESSED AT SPAWN (HauntPlanner.build_wisp): the wisp is in its host, hidden and out of every query (nothing can hit it),
##   the host awake in the ghost look, its plinth left behind;
## - A POSSESSED HOST FIGHTS: it sees the hero, closes in, winds up and its blow lands; the knight's walk and wind-up are poses
##   of their own (KnightModel);
## - BREAKING IT: the armour bills its price to the culprit (bones bill nothing); the wisp is thrown out where it fell, hurt
##   (BREAK_HURT), and flies to the next dormant host in range and possesses it (it wakes);
## - A FREE WISP with no host in range keeps away from the hero; anyone's hits kill it (it is freed);
## - TENTACLES pass through a wisp (physical only) and shove and smash the hosts;
## - the planner on a haunted floor (HauntPlanner.plan / spawn): the hosts, their ghosts, the same twice.

func _init() -> void:
	timeout_sec = 300.0


func setup() -> void:
	_kinds()
	await _dormant()
	await _possessed_at_spawn()
	await _fights()
	await _break_moves_on()
	await _bones_free()
	await _free_wisp()
	await _tentacles()
	finish()


func _arena(r: int = 12) -> HexMap:
	var map := flat_map(r)
	new_world(map)
	Ledger.lines.clear()
	return map


func _host(map: HexMap, kind: String, cell: Vector2i, dir := Vector2(0.0, 1.0)) -> HauntHost:
	var w := Hex.to_world(cell)
	return HauntPlanner.build_host(map, kind, Vector2(w.x, w.z), dir)


func _kinds() -> void:
	var map := _arena()
	var a := _host(map, "armour", Vector2i(0, 0))
	var b := _host(map, "bones", Vector2i(4, 0))
	var w := MonsterFactory.spawn("wisp", Vector2i(-4, 0)) as Wisp
	check(a is ArmourHost and a.model is KnightModel, "a suit of armour: the knight")
	check(b is BonesHost and b.model is BonesModel, "a skeleton: the bones")
	check(w is Wisp and w.model is WispModel, "a ghost: the wisp")
	eq(a.display_name, PricedProp.name_of("suit_of_armour"), "the armour's name is the priced suit's")
	eq(a.price, PricedProp.price_of("suit_of_armour"), "... and its price")
	eq(b.price, 0, "bones cost nothing")
	near(a.max_hp, float(PricedProp.TABLE["suit_of_armour"]["hp"]), 0.001, "the armour's HP is the priced suit's")
	check(w.move_speed < 4.5, "the crew outruns a wisp (%.1f)" % w.move_speed)
	eq(w.attack_damage, 0.0, "a wisp never attacks")
	check(not w.can_yell(), "... nor yells")
	for n in [a, b, w]:
		eq(MonsterDefs.family_of(n.kind), "dead", "%s: the dead family's" % n.kind)


func _dormant() -> void:
	var map := _arena()
	var a := _host(map, "armour", Vector2i(0, 0))
	var hero := add_hero(Vector2i(3, 0))
	var k := a.model as KnightModel
	check(a.is_dormant() and not a.is_possessed(), "no ghost: dormant")
	check(not k.awake and not k.is_ghost(), "the knight stands as the antique (no ghost look)")
	check(k.parts["stand"].get_parent() == k, "on its plinth")
	check(not a.is_in_group("monsters"), "not one of the monsters (never a pest, the staff are not scared)")
	check(a.is_in_group("actors"), "but still an actor the crew can hit")
	eq(a.tag_label.text, "%s – %s" % [PricedProp.name_of("suit_of_armour"), PricedProp.money(PricedProp.price_of("suit_of_armour"))], "the priced suit's tag")
	await frames(30)
	eq(a.state, Monster.State.IDLE, "a hero in sight: no fight")
	a.apply_damage(10.0, hero)
	await frames(10)
	eq(a.state, Monster.State.IDLE, "a knock: still no fight")
	check(not a.is_hp_bar_visible(), "no HP bar (a prop wobbles)")
	check(not a.alert(hero.global_position) and not a.hear(hero.global_position), "no shout or noise wakes it")
	check(a.hp < a.max_hp, "but it took the knock")
	check(a.is_dormant(), "the AI allies leave it be (Monster.is_dormant)")
	check(not b_moved(a), "it never moved")


func b_moved(a: Monster) -> bool:
	return GameWorld.flat_distance(a.global_position, a.home) > 0.05 if a._home_set else false


func _possessed_at_spawn() -> void:
	var map := _arena()
	var a := _host(map, "armour", Vector2i(0, 0))
	var w := HauntPlanner.build_wisp(a)
	check(w != null and w.host == a and a.ghost == w, "the wisp is in its host from the start")
	check(a.is_possessed() and a.is_in_group("monsters"), "the host is possessed: a monster now")
	check(not w.visible and not w.is_in_group("actors") and not w.is_in_group("monsters"), "the wisp is hidden and out of every query")
	check(not GameWorld.actors_in_radius(a.global_position, 2.0).has(w), "nothing finds it")
	var k := a.model as KnightModel
	check(k.awake and k.wake_k() >= 1.0 and k.is_ghost(), "the knight awake at once, in the ghost look")
	check(a.plinth != null and k.parts["stand"].get_parent() == a.plinth.get_child(0).get_parent(), "its plinth left in the world")
	check(k.parts["head"].find_child("Vapour", false, false) != null, "the ghost's vapour round its parts")
	# a hit on the possessed host is the host's, the wisp inside is untouched
	var hero := add_hero(Vector2i(6, 0))
	a.apply_damage(10.0, hero)
	near(w.hp, w.max_hp, 0.001, "a hit on the host leaves the wisp")
	await frames(20)
	check(GameWorld.flat_distance(w.global_position, a.global_position) < 0.05, "the wisp rides its host")


func _fights() -> void:
	for kind in ["armour", "bones"]:
		var map := _arena()
		var h := _host(map, kind, Vector2i(0, 0))
		HauntPlanner.build_wisp(h)
		var hero := add_hero(Vector2i(4, 0))
		check(await wait_until(func() -> bool: return h.state == Monster.State.CHASE or h.state == Monster.State.ATTACK, 120), "%s: possessed, it sees the hero and comes" % kind)
		check(await wait_until(func() -> bool: return h.state == Monster.State.ATTACK, 600), "%s: it winds up a blow (%.1f from the hero)" % [kind, fdist(h, hero)])
		check(await wait_until(func() -> bool: return hero.hp < hero.max_hp, 240), "%s: the blow lands (%.0f)" % [kind, hero.hp])
	# the knight's poses: the walk, the wind-up and the strike are its own
	var k := KnightModel.new()
	add_child(k)
	k.idle_enabled = false
	k.apply_idle(0.6)
	var grip := Vector3(0.0, ArmourModel.GRIP_FROM_POINT, 0.0)   # (the sword's grip, up its blade from the point)
	var rest := (k.parts["weapon"] as Node3D).global_transform * grip
	k.windup(1.0)
	var up := (k.parts["weapon"] as Node3D).global_transform * grip
	check(up.y > rest.y + 0.3, "the knight hauls its sword up in the wind-up (%.2f -> %.2f)" % [rest.y, up.y])
	k.windup(0.0)
	k.apply_idle(0.6, 2.0)
	var leg_a := (k.parts["leg_l"] as Node3D).rotation.x
	k.apply_idle(0.9, 2.0)
	check(absf((k.parts["leg_l"] as Node3D).rotation.x - leg_a) > 0.2, "its legs swing on the march")
	k.set_dormant()
	k.wake()
	k.apply_idle(0.6)
	check(k.wake_k() < 0.05, "a wake starts from the dormant pose")
	k.queue_free()


func _break_moves_on() -> void:
	var map := _arena(14)
	var a := _host(map, "armour", Vector2i(0, 0))
	var b := _host(map, "armour", Vector2i(6, -3))
	var w := HauntPlanner.build_wisp(a)
	var hero := add_hero(Vector2i(-6, 3))
	a.aggro_range = 0.0   # (it stands: the test breaks it)
	a.apply_damage(a.max_hp + 1.0, hero)
	check(a.dead, "the possessed suit breaks")
	var bills := Ledger.lines.filter(func(l: Dictionary) -> bool: return l["kind"] == "damage")
	eq(bills.size(), 1, "it is billed once")
	if bills.size() == 1:
		eq(str(bills[0]["label"]), "Suit of armour", "as the suit of armour")
		eq(int(bills[0]["amount"]), PricedProp.price_of("suit_of_armour"), "at its price")
		eq(str(bills[0]["who"]), hero.display_name, "to the one who broke it")
	check(w.host == null and w.ejected == 1, "the wisp is thrown out")
	near(w.hp, Wisp.HP - Wisp.BREAK_HURT, 0.001, "hurt by the break")
	check(w.visible and w.is_in_group("actors") and w.is_in_group("monsters"), "out in the open: it can be hit")
	check(GameWorld.flat_distance(w.global_position, a.global_position) < 0.3, "where its host fell")
	check(await wait_until(func() -> bool: return w.host == b, 900), "it flies to the next dormant host and gets in (%.1f away)" % GameWorld.flat_distance(w.global_position, b.global_position))
	check(b.is_possessed() and b.ghost == w and (b.model as KnightModel).is_ghost(), "that host is possessed now")
	check(b.is_waking() or (b.model as KnightModel).wake_k() < 1.0 or b.state != Monster.State.DEAD, "it wakes")
	eq(w.entered, 2, "two hosts in all")
	# broken dormant: billed too (possessed or not), nothing thrown out
	Ledger.lines.clear()
	var c := _host(map, "armour", Vector2i(-3, -3))
	c.apply_damage(c.max_hp + 1.0, hero)
	eq(Ledger.lines.size(), 1, "a dormant suit broken is billed too")
	await frames(70)
	check(not is_instance_valid(a), "the broken suit is gone")


func _bones_free() -> void:
	var map := _arena()
	var bo := _host(map, "bones", Vector2i(0, 0))
	var w := HauntPlanner.build_wisp(bo)
	var hero := add_hero(Vector2i(6, 0))
	bo.aggro_range = 0.0
	bo.apply_damage(bo.max_hp + 1.0, hero)
	check(bo.dead, "the possessed skeleton breaks")
	eq(Ledger.lines.filter(func(l: Dictionary) -> bool: return l["kind"] == "damage").size(), 0, "bones bill nothing")
	check(w.host == null and w.hp < w.max_hp, "its wisp is thrown out, hurt")
	await frames(10)


func _free_wisp() -> void:
	var map := _arena(14)
	var w := MonsterFactory.spawn("wisp", Vector2i(0, 0)) as Wisp
	var hero := add_hero(Vector2i(3, 0))
	var d0 := fdist(w, hero)
	check(await wait_until(func() -> bool: return w.state == Monster.State.ALERT, 60), "no host in range: it sees the hero and keeps away")
	await frames(240)
	check(fdist(w, hero) > d0 + 1.0 and fdist(w, hero) >= Wisp.KEEP_AWAY - 0.6, "away from the hero (%.1f -> %.1f)" % [d0, fdist(w, hero)])
	near(hero.hp, hero.max_hp, 0.001, "it never strikes")
	# anyone's hits: it dies and is freed
	w.apply_damage(10.0, hero)
	check(not w.dead and w.state != Monster.State.CHASE, "a hit hurts it (it does not fight back)")
	w.apply_damage(w.hp + 1.0, hero)
	check(w.dead, "hits kill it")
	await frames(90)
	check(not is_instance_valid(w), "and it is gone")
	# a hero's swing reaches a free wisp (it is a monster: Combat's foe team)
	var w2 := MonsterFactory.spawn("wisp", Vector2i(0, 0)) as Wisp
	w2.set_physics_process(false)
	var h2 := add_hero(Vector2i(1, 0))
	var hit := Combat.melee_arc(h2, w2.global_position - h2.global_position, 1.6, 120.0, 12.0)
	check(hit.has(w2) and w2.hp < w2.max_hp, "a plain swing hits a wisp: no spell needed")


func _tentacles() -> void:
	var map := _arena()
	var hero := add_hero(Vector2i(-6, 0))
	var a := _host(map, "armour", Vector2i(0, 0))
	var w := MonsterFactory.spawn("wisp", Vector2i(1, 0)) as Wisp
	w.set_physics_process(false)
	var wp := w.global_position
	var t := Tentacles.new()
	t.caster = hero
	t.power = 1.0
	t.aim = Vector3.RIGHT
	GameWorld.spawn(t, Hex.to_world(Vector2i(0, 0)) + Vector3(0.5, 0.0, 0.0))
	check(not t.covers(w), "the tentacles never cover a wisp")
	check(t.covers(a), "... but the host beside it")
	await frames(40)
	near(w.hp, w.max_hp, 0.001, "they pass through the wisp: no damage")
	check(not w.is_shoved() and GameWorld.flat_distance(w.global_position, wp) < 0.05, "... no shove")
	check(a.hp < a.max_hp, "they smash the suit of armour")
