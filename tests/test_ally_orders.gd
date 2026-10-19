extends TestCase
## Voice orders and the AI restraint baseline (docs/design/combat-proposals.md 1.0 and "As built"), one process, flat maps:
##   restraint  the AI never opens a fight on idle monsters (no swing, no bowl), joins a started one only after its reaction
##              delay (REACT_MIN..MAX), goes first for what attacks its leader, needs line of sight, and bowls only to peel
##   orders     go (walks there, holds, a new go replaces it), attack (fights an idle monster on its own, then follows the
##              speaker when the fight is over), follow (the speaker becomes the leader, the order clears)
##   names      VoiceOrders: crew / everyone / hench / hench four / pym / a hero's name / an absent name; employees' go,
##              follow, a henchman's attack (a FIGHT, then following), staff refusing, earshot, a human-played hero's marker
##   voice      the typed console reaches VoiceCaster.order_spoken (the game's path)

var root: Node3D


func _init() -> void:
	timeout_sec = 180.0


func _world(radius: int = 12, walls: Array = [], seed_value: int = 4242) -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 10 if walls.has(c) else 0, HexMap.Tile.WALL if walls.has(c) else HexMap.Tile.FLOOR)
	GameWorld.begin(m, root, seed_value)
	MonsterSenses.restless_override = 0.0


func _hero(kit: String, at: Vector3) -> Hero:
	var h := HeroFactory.spawn_hero(Hex.from_world(at), kit.capitalize(), Color.WHITE, "sword", null, kit)
	h.global_position = at
	h.snap_to_ground()
	h.set_modifier("test_ward", 0.0, 99999.0)   # (nobody goes down: the fights go on)
	return h


func _grunt(at: Vector3, frozen: bool) -> Monster:
	var m := MonsterFactory.spawn("grunt", Hex.from_world(at))
	m.global_position = at
	m.snap_to_ground()
	if frozen:
		m.aggro_range = 0.0   # (idle and unaware: sees nothing, hears nothing)
	m.max_hp = 400.0
	m.hp = 400.0
	return m


func _ally(h: Hero, leader: Hero) -> AllyBrain:
	return HeroFactory.make_ally(h, leader, false, 2.4, 2.6)


func setup() -> void:
	await _test_no_opening()
	await _test_reaction_delay()
	await _test_leader_first()
	await _test_line_of_sight()
	await _test_peel()
	await _test_go()
	await _test_attack()
	await _test_follow()
	await _test_names()
	await _test_employees()
	_test_typed()
	AllyBrain.restraint = true
	finish()


# --- Restraint ---------------------------------------------------------------------------------------------

## Idle, unaware monsters are left alone: no swing, no bowl, the ally stays with its leader. The old eager AI opens on them.
func _test_no_opening() -> void:
	for eager in [false, true]:
		AllyBrain.restraint = not eager
		_world()
		var leader := _hero("wick", Vector3(0, 0, 0))
		var rebar := _hero("rebar", Vector3(-2.0, 0, 0.5))
		_ally(rebar, leader)
		var near_one := _grunt(Vector3(3.0, 0, 0), true)
		var far_one := _grunt(Vector3(-2.0, 0, 6.0), true)
		var bowls := [0]
		var swings := [0]
		rebar.bolt_fired.connect(func() -> void: bowls[0] += 1)
		rebar.melee_swung.connect(func() -> void: swings[0] += 1)
		var bowl_cd := [0.0]
		await frames(60 * 4)
		bowl_cd[0] = rebar.cooldown_left(Hero.KEY_RANGED)
		var touched := near_one.hp < near_one.max_hp or far_one.hp < far_one.max_hp
		if eager:
			check(touched, "eager AI (restraint off) opens on idle monsters (the old behaviour)")
		else:
			check(not touched, "restraint: idle monsters are not attacked (hp %.0f / %.0f)" % [near_one.hp, far_one.hp])
			eq(swings[0], 0, "restraint: no swing at an idle monster")
			check(near_one.state == Monster.State.IDLE and far_one.state == Monster.State.IDLE, "restraint: the idle monsters are still idle")
			check(GameWorld.flat_distance(rebar.global_position, leader.global_position) < AllyBrain.LEASH, "restraint: the ally stays with its leader")
	AllyBrain.restraint = true


## The leader starts the fight: the ally engages that monster REACT_MIN..MAX seconds later, not at once.
func _test_reaction_delay() -> void:
	var delays: Array[float] = []
	for k in 3:
		_world(12, [], 4242 + 17 * k)   # (another floor seed: another roll)
		var leader := _hero("wick", Vector3(0, 0, 0))
		var rebar := _hero("rebar", Vector3(-1.5, 0, -1.5 + float(k)))
		var brain := _ally(rebar, leader)
		var m := _grunt(Vector3(3.5, 0, 0.5), true)
		await frames(5)
		eq(m.state, Monster.State.IDLE, "the monster starts unaware")
		var t0 := GameWorld.time
		m.apply_damage(5.0, leader)   # the player opens the fight
		m.aggro_range = 8.0           # (and from now on it sees: it keeps its target)
		var engaged := -1.0
		for i in 120:
			await get_tree().physics_frame
			if brain._foe == m:
				engaged = GameWorld.time - t0
				break
		check(engaged >= AllyBrain.REACT_MIN - 0.02 and engaged <= AllyBrain.REACT_MAX + 0.05, "the ally joins after its reaction delay (%.2f s)" % engaged)
		delays.append(engaged)
	print("reaction delays: %s" % str(delays))


## Two monsters in the fight: the one attacking the leader goes first, even when the one on a teammate is nearer.
func _test_leader_first() -> void:
	_world()
	var leader := _hero("wick", Vector3(0, 0, 0))
	var gasket := _hero("gasket", Vector3(-4.5, 0, 3.0))
	var rebar := _hero("rebar", Vector3(-2.0, 0, 0))
	var brain := _ally(rebar, leader)
	var on_leader := _grunt(Vector3(2.5, 0, 0), false)
	var on_mate := _grunt(Vector3(-4.0, 0, 1.6), false)
	on_leader.aggro(leader)
	on_mate.aggro(gasket)
	await frames(80)
	check(on_leader.target == leader and on_mate.target == gasket, "set-up: one monster on the leader, one on a teammate")
	check(brain._foe == on_leader, "the monster on the leader goes first (picked %s)" % (brain._foe.name if brain._foe != null else "nothing"))
	# The leader's attacker gone: the one on the teammate is next.
	on_leader.queue_free()
	await frames(70)
	check(brain._foe == on_mate, "then the one on a teammate")


## A monster in the fight behind a wall (and not hitting the ally) is not engaged; in sight, it is.
func _test_line_of_sight() -> void:
	var wall: Array = []
	for r in range(-6, 7):
		wall.append(Vector2i(2, r))
	_world(12, wall)
	var leader := _hero("wick", Vector3(0, 0, 0))
	var rebar := _hero("rebar", Vector3(-1.5, 0, 1.0))
	var brain := _ally(rebar, leader)
	var behind := _grunt(Hex.to_world(Vector2i(4, 0)), true)
	behind.aggro(leader)   # in the fight (CHASE) but behind the wall; frozen, so it stays there
	await frames(80)
	check(not GameWorld.map.line_of_sight(Combat.chest(rebar), Combat.chest(behind)), "set-up: the wall hides it")
	check(brain._foe != behind, "no line of sight: not engaged")
	near(behind.hp, behind.max_hp, 0.001, "and not hurt")


## Rebar's bowl peels a monster off a teammate; it never opens on one that is not on a teammate.
func _test_peel() -> void:
	_world()
	var leader := _hero("wick", Vector3(0, 0, 0))
	var rebar := _hero("rebar", Vector3(-3.3, 0, 3.0))   # (at his formation slot: he does not walk in first)
	var gasket := _hero("gasket", Vector3(-1.8, 0, -3.0))   # (a teammate beside the lane, not behind the monster)
	var brain := _ally(rebar, leader)
	var m := _grunt(Vector3(-3.3, 0, -3.0), false)
	m.move_speed = 0.0   # (it swings at Gasket from where it stands: the lane past it stays clear of him)
	m.aggro(gasket)
	for i in 120:
		await get_tree().physics_frame
		if rebar.cooldown_left(Hero.KEY_RANGED) > 0.0:
			break
	check(rebar.cooldown_left(Hero.KEY_RANGED) > 0.0, "Rebar bowls to peel a monster off a teammate")
	# A monster in the fight but on nobody near (ALERT, walking to a noise): no bowl, however long.
	_world()
	leader = _hero("wick", Vector3(0, 0, -4.0))   # (off the lane: only the rule holds the throw)
	rebar = _hero("rebar", Vector3(-1.0, 0, 0))
	brain = _ally(rebar, leader)
	var alerted := _grunt(Vector3(5.5, 0, 0), true)
	alerted.aggro_range = 8.0
	alerted.alert(Vector3(9.0, 0, 3.0))
	alerted.move_speed = 0.0
	var thrown := false
	for i in 150:
		await get_tree().physics_frame
		thrown = thrown or rebar.cooldown_left(Hero.KEY_RANGED) > 0.0
	check(alerted.state == Monster.State.ALERT or alerted.is_aggro(), "set-up: the monster is in the fight (%s)" % alerted.state_name())
	check(not thrown, "no bowl to open on a monster that is on nobody")
	AllyBrain.restraint = false
	_world()
	leader = _hero("wick", Vector3(0, 0, -4.0))
	rebar = _hero("rebar", Vector3(-1.0, 0, 0))
	_ally(rebar, leader)
	_grunt(Vector3(5.5, 0, 0), true)
	await frames(10)
	check(rebar.cooldown_left(Hero.KEY_RANGED) > 0.0, "(the eager AI bowls to open)")
	AllyBrain.restraint = true


# --- Orders on the AI hero ----------------------------------------------------------------------------------

func _test_go() -> void:
	_world()
	var leader := _hero("wick", Vector3(0, 0, 0))
	var rebar := _hero("rebar", Vector3(-1.5, 0, 1.0))
	var brain := _ally(rebar, leader)
	var spot := Hex.to_world(Vector2i(5, -2))
	eq(brain.give_order("go", leader, spot), "Moving.", "Rebar's go bark")
	eq(brain.order, "go", "the order is go")
	await frames(60 * 3)
	check(GameWorld.flat_distance(rebar.global_position, spot) <= AllyBrain.GO_ARRIVED + 0.1, "Rebar walks to the spot (%.2f away)" % GameWorld.flat_distance(rebar.global_position, spot))
	# The leader walks off the other way: he holds.
	for i in 90:
		leader.move(Vector3.LEFT, get_physics_process_delta_time())
		await get_tree().physics_frame
	check(GameWorld.flat_distance(rebar.global_position, spot) <= AllyBrain.GO_ARRIVED + 0.2, "and holds it when the leader walks away")
	# A monster in the fight near the spot is fought; one far from it is not.
	var near_m := _grunt(spot + Vector3(2.5, 0, 0), true)
	near_m.aggro(leader)
	var far_m := _grunt(spot + Vector3(0, 0, 8.0), true)
	far_m.aggro(leader)
	await frames(60 * 2)
	check(near_m.hp < near_m.max_hp, "holding: fights what is in the fight near the spot")
	near(far_m.hp, far_m.max_hp, 0.001, "but not what is far from it")
	near_m.queue_free()
	far_m.queue_free()
	await frames(60 * 2)
	check(GameWorld.flat_distance(rebar.global_position, spot) <= AllyBrain.GO_ARRIVED + 0.2, "and goes back to the spot")
	# A new go replaces the old one.
	var spot2 := Hex.to_world(Vector2i(-4, 4))
	brain.give_order("go", leader, spot2)
	await frames(60 * 4)
	check(GameWorld.flat_distance(rebar.global_position, spot2) <= AllyBrain.GO_ARRIVED + 0.1, "a new go replaces the old one (%.2f from the new spot)" % GameWorld.flat_distance(rebar.global_position, spot2))


func _test_attack() -> void:
	_world()
	var leader := _hero("wick", Vector3(0, 0, 0))
	var speaker := _hero("wick", Vector3(-3, 0, -3))
	var gasket := _hero("gasket", Vector3(-1.5, 0, 1.0))
	var brain := _ally(gasket, leader)
	var idle := _grunt(Vector3(4.0, 0, 1.0), true)
	idle.max_hp = 60.0
	idle.hp = 60.0
	await frames(60)
	near(idle.hp, idle.max_hp, 0.001, "set-up: nobody touches the idle monster")
	eq(brain.give_order("attack", speaker, Vector3.INF), "Hammer time!", "Gasket's attack bark")
	eq(brain.leader, speaker, "attack: the speaker is who it follows afterwards")
	for i in 60 * 8:
		await get_tree().physics_frame
		if idle.dead:
			break
	check(idle.dead, "attack: Gasket opens on an idle monster and kills it")
	await frames(60 * 2)
	eq(brain.order, "", "the attack ends when the fight is over")
	await frames(60 * 2)
	check(GameWorld.flat_distance(gasket.global_position, speaker.global_position) < AllyBrain.FORMATION_HEX_MAX * AllyBrain.HEX_STEP + 1.5, "then it follows the speaker")


func _test_follow() -> void:
	_world()
	var leader := _hero("wick", Vector3(0, 0, 0))
	var other := _hero("wick", Vector3(-7, 0, 3))
	var rebar := _hero("rebar", Vector3(1.5, 0, 1.0))
	var brain := _ally(rebar, leader)
	brain.give_order("go", leader, Hex.to_world(Vector2i(4, 0)))
	eq(brain.give_order("follow", other, Vector3.INF), "Right behind you.", "follow bark")
	eq(brain.order, "", "follow clears the order")
	eq(brain.leader, other, "follow: the speaker is the leader")
	await frames(60 * 4)
	check(GameWorld.flat_distance(rebar.global_position, other.global_position) < AllyBrain.FORMATION_HEX_MAX * AllyBrain.HEX_STEP + 1.0, "it follows the speaker")
	# A downed ally takes no order (no bark).
	rebar.set_modifier("test_ward", 1.0, 99999.0)   # (the ward off: the same id refreshes)
	rebar.apply_damage(99999.0, null)
	check(rebar.dead, "set-up: Rebar is down")
	eq(brain.give_order("go", other, Vector3.ZERO), "", "a downed ally takes no order (no bark)")


# --- Names (VoiceOrders) -------------------------------------------------------------------------------------

func _test_names() -> void:
	_world(14)
	var speaker := _hero("wick", Vector3(0, 0, 0))
	speaker.is_player = true
	var rebar := _hero("rebar", Vector3(-2, 0, 1))
	var gasket := _hero("gasket", Vector3(2, 0, 1))
	_ally(rebar, speaker)
	_ally(gasket, speaker)
	var pym := Employee.spawn(Vector2i(3, -3), {"style": "staff", "name": "Mrs. Pym"})
	var gary := Employee.spawn(Vector2i(-3, -2), {"style": "henchman", "name": "Gary (Henchman 1)"})
	var four := Employee.spawn(Vector2i(-4, 2), {"style": "henchman", "name": "Hench #4"})
	var far_steve := Employee.spawn(Vector2i(13, 0), {"style": "henchman", "name": "Steve"})
	far_steve.global_position = Vector3(30, 0, 0)   # (out of earshot)
	await frames(2)
	eq(_ids(VoiceOrders.targets("crew", speaker)), _ids([rebar, gasket]), "crew: the heroes but the speaker")
	eq(_ids(VoiceOrders.targets("everyone", speaker)), _ids([rebar, gasket, pym, gary, four]), "everyone: heroes and employees in earshot")
	eq(_ids(VoiceOrders.targets("hench", speaker)), _ids([gary, four]), "hench: every henchman in earshot")
	eq(_ids(VoiceOrders.targets("hench four", speaker)), _ids([four]), "hench four: only Hench #4")
	eq(_ids(VoiceOrders.targets("pym", speaker)), _ids([pym]), "pym: Mrs. Pym")
	eq(_ids(VoiceOrders.targets("gary", speaker)), _ids([gary]), "gary: Gary (Henchman 1)")
	eq(_ids(VoiceOrders.targets("rebar", speaker)), _ids([rebar]), "rebar: Rebar")
	eq(VoiceOrders.targets("wick", speaker).size(), 0, "the speaker's own name: nobody (he is not told)")
	eq(VoiceOrders.targets("steve", speaker).size(), 0, "an employee out of earshot does not hear it")
	eq(VoiceOrders.targets("dennis", speaker).size(), 0, "a name not on the floor: nobody")
	var r := VoiceOrders.apply("dennis", "go", speaker, Vector3(3, 0, 3))
	check(int(r["took"]) == 0 and (r["barks"] as Array).is_empty(), "an absent name does nothing, quietly")
	eq(VoiceOrders.call_name("Mr. Okafor (accounts)"), "okafor", "call names skip titles")
	eq(VoiceOrders.call_name("Marguerite (sommelier)"), "marguerite", "a floor's staff name is its first word")
	# A hero a person plays (here: one with a player name, as online) gets a marker, never an order.
	var human := _hero("wick", Vector3(0, 0, -3))
	human.set_meta(Net.NAME_META, "Fox")
	var g := VoiceOrders.apply("wick", "go", rebar, Vector3(4, 0, -4))
	check((g["marks"] as Array).has(human) and (g["marks"] as Array).has(speaker), "go to Wick: both Wicks (people) get a marker")
	eq(int(g["took"]), 0, "a marker controls nothing")
	var f := VoiceOrders.apply("wick", "follow", rebar, Vector3.INF)
	check((f["marks"] as Array).is_empty(), "follow sends a person nothing")
	# The marker on the player's screen (OrderFx), cleared on arrival.
	VoiceOrders.feedback({"o": "go", "p": Vector3(4, 0, -4), "by": rebar, "barks": [], "marks": [speaker], "took": 0}, speaker)
	await frames(2)
	var markers := get_tree().get_nodes_in_group(OrderFx.Marker.GROUP)
	eq(markers.size(), 1, "the player sees a marker")
	if markers.size() == 1:
		check(str(markers[0].call("text")).begins_with("Rebar: go here"), "it names the speaker (%s)" % markers[0].call("text"))
	speaker.global_position = Vector3(4, 0, -4)
	await frames(3)
	eq(get_tree().get_nodes_in_group(OrderFx.Marker.GROUP).size(), 0, "it clears when the player gets there")
	# Everyone go: the AI heroes walk, the employees go and wait, the human gets a marker.
	var spot := Hex.to_world(Vector2i(-6, -4))
	var e := VoiceOrders.apply("everyone", "go", speaker, spot)
	eq(int(e["took"]), 5, "everyone go: two AI heroes and three employees take it")
	eq((e["barks"] as Array).size(), 2, "the AI heroes bark")
	VoiceOrders.feedback({"o": "go", "p": spot, "by": speaker, "barks": e["barks"], "marks": e["marks"], "took": e["took"]}, speaker)
	await frames(2)
	check(rebar.get_node_or_null(OrderFx.BARK_NAME) != null, "the bark shows over Rebar")
	check(root.get_node_or_null("OrderWaypoint") != null, "the speaker sees the waypoint")


func _ids(a: Array) -> Array:
	var ids: Array = []
	for n: Node in a:
		ids.append(n.get_instance_id())
	ids.sort()
	return ids


# --- Employees ---------------------------------------------------------------------------------------------

func _test_employees() -> void:
	_world(14)
	var speaker := _hero("wick", Vector3(0, 0, 0))
	var pym := Employee.spawn(Vector2i(2, 2), {"style": "staff", "name": "Mrs. Pym"})
	var gary := Employee.spawn(Vector2i(-2, 2), {"style": "henchman", "name": "Gary"})
	await frames(2)
	# go: walks to the spot and waits there.
	var spot := Hex.to_world(Vector2i(6, -3))
	eq(pym.order("go", speaker, spot), "took", "Pym takes go")
	await frames(60 * 4)
	eq(pym.state, Employee.State.WAIT, "Pym waits")
	check(GameWorld.flat_distance(pym.global_position, spot) < 0.6, "at the spot (%.2f away)" % GameWorld.flat_distance(pym.global_position, spot))
	# follow: follows the speaker.
	eq(pym.order("follow", speaker, Vector3.INF), "took", "Pym takes follow")
	check(pym.is_following() and pym.leader() == speaker, "Pym follows the speaker")
	# attack: staff refuse, henchmen fight.
	var was := pym.state
	eq(pym.order("attack", speaker, Vector3.INF), "refused", "staff refuse attack")
	eq(pym.state, was, "and keep doing what they did")
	await frames(2)
	check(Employee.REFUSE_LINES.has(pym.bubble_text()), "with a refusal (%s)" % pym.bubble_text())
	var m := _grunt(Vector3(-4.5, 0, 3.0), true)
	m.max_hp = 9.0
	m.hp = 9.0
	eq(gary.order("attack", speaker, Vector3.INF), "took", "a henchman takes attack")
	eq(gary.state, Employee.State.FIGHT, "and fights")
	var hit := [0.0]
	m.damaged.connect(func(a: float, src: Node) -> void:
		if src == gary:
			hit[0] += a)
	for i in 60 * 8:
		await get_tree().physics_frame
		if m.dead:
			break
	check(hit[0] >= Employee.HENCH_PUNCH, "the henchman punches the monster (%.0f)" % hit[0])
	check(m.dead, "three weak punches kill a weakened grunt")
	await frames(60 * 2)
	check(gary.is_following() and gary.leader() == speaker, "when the fight is over he follows the speaker (%s)" % gary.state_name())


# --- Voice --------------------------------------------------------------------------------------------------

## Typed console input reaches the order signal, like a spoken one (the game's _on_console -> inject_text path).
func _test_typed() -> void:
	var vc := VoiceCaster.new()
	vc.use_mic = false
	vc.use_saved_settings = false
	vc.persist_settings = false
	vc.voice_log.enabled = false
	add_child(vc)
	var got: Array = []
	vc.order_spoken.connect(func(who: String, o: String, _h: String) -> void: got.append("%s %s" % [who, o]))
	vc.inject_text("Rebar go")
	vc.inject_text("hench attack")
	vc.inject_text("Mrs. Pym follow")
	eq(got, ["rebar go", "hench attack", "pym follow"], "typed orders reach order_spoken")
	check(bool(vc.last_order().get("typed", false)), "marked typed")
	vc.queue_free()
