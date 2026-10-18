extends TestCase
## M2, single process: the pieces a crew's seats stand on.
## - NetRegistry: ids -> nodes (heroes by seat, then build order, runtime ids from 10000), a freed node is never returned;
## - the floor carry is keyed by SEAT, so two players who both play Wick keep their own HP and downed state (a hero
##   outside the crew is still keyed by name: the old API);
## - Hero.become(): a seat handed back to the AI is the SAME node as another character (position, id, references stay;
##   kit, name, colour and model change; HP keeps its fraction; a downed hero stays downed);
## - SeatHandover's table, offline: who owns what, which seat a peer sat in, and that release is a host-only verb.

var root: Node3D


func setup() -> void:
	root = Node3D.new()
	add_child(root)
	var map := HexMap.new()
	for i in 12:
		map.set_cell(Vector2i(i, 0), 0)
	GameWorld.begin(map, root)
	_check_registry()
	_check_carry()
	_check_become()
	_check_seat_table()
	finish()


func _check_registry() -> void:
	var a := HeroFactory.spawn_hero(Vector2i(1, 0), "A", Color.BLUE)
	var b := HeroFactory.spawn_hero(Vector2i(2, 0), "B", Color.RED)
	var c := HeroFactory.spawn_hero(Vector2i(3, 0), "C", Color.GREEN)
	var m1 := Actor.new()
	GameWorld.spawn(m1, Hex.to_world(Vector2i(5, 0)))
	var m2 := Actor.new()
	GameWorld.spawn(m2, Hex.to_world(Vector2i(6, 0)))
	var n := NetFloor.assign_ids(root, {1: a, 2: b, 3: c})
	eq(n, 2, "two non-hero actors got ids")
	eq(NetRegistry.node(1), a, "seat 1 is id 1")
	eq(NetRegistry.hero(3), c, "NetRegistry.hero(seat) finds the hero")
	eq(NetRegistry.node(NetFloor.ID_BASE), m1, "build order: the first actor is ID_BASE")
	eq(NetRegistry.node(NetFloor.ID_BASE + 1), m2, "... then the next")
	eq(NetRegistry.id_of(m2), NetFloor.ID_BASE + 1, "id_of agrees")
	eq(str(NetRegistry.ids()), "[1, 2, 3, 100, 101]", "every id, ascending")
	check(NetRegistry.node(9999) == null, "an unknown id finds nothing")
	eq(NetRegistry.next_runtime_id(), NetRegistry.RUNTIME_BASE, "runtime ids start at 10000")
	eq(NetRegistry.next_runtime_id(), NetRegistry.RUNTIME_BASE + 1, "... and count up")
	m2.free()
	check(NetRegistry.node(NetFloor.ID_BASE + 1) == null, "a freed node is never returned")
	eq(NetRegistry.size(), 4, "and it drops out of the table")
	NetFloor.assign_ids(root, {1: a})
	check(NetRegistry.node(2) == null, "a new floor rebuilds the registry from scratch")
	eq(NetRegistry.next_runtime_id(), NetRegistry.RUNTIME_BASE, "... and the runtime counter")
	NetRegistry.clear()
	eq(NetRegistry.size(), 0, "clear() empties it")
	for h in [a, b, c, m1]:
		h.free()


func _check_carry() -> void:
	var run := ContractRun.make("prepper", 5, 0.5)
	var session := ContractSession.begin(run)
	var wick1 := HeroFactory.spawn_hero(Vector2i(1, 0), "Wick", Color.BLUE, "sword", null, HeroKit.WICK)
	var wick2 := HeroFactory.spawn_hero(Vector2i(2, 0), "Wick", Color.BLUE, "sword", null, HeroKit.WICK)
	var gasket := HeroFactory.spawn_hero(Vector2i(3, 0), "Gasket", Color.PURPLE, "sword", null, HeroKit.GASKET)
	wick1.set_meta(ContractSession.CREW_SEAT_META, 1)
	wick2.set_meta(ContractSession.CREW_SEAT_META, 2)
	gasket.set_meta(ContractSession.CREW_SEAT_META, 3)
	wick1.hp = 60.0
	wick2.apply_damage(9999.0)
	check(wick2.dead, "the second Wick is downed")
	var crew: Array[Hero] = [wick1, wick2, gasket]
	session.save_carry(crew)
	eq(session.carry.size(), 3, "two Wicks and a Gasket are three carry entries, not two")
	eq(ContractSession.carry_key(wick2), 2, "the key is the seat")
	var new1 := HeroFactory.spawn_hero(Vector2i(4, 0), "Wick", Color.BLUE, "sword", null, HeroKit.WICK)
	var new2 := HeroFactory.spawn_hero(Vector2i(5, 0), "Wick", Color.BLUE, "sword", null, HeroKit.WICK)
	new1.set_meta(ContractSession.CREW_SEAT_META, 1)
	new2.set_meta(ContractSession.CREW_SEAT_META, 2)
	session.apply_carry(new1)
	session.apply_carry(new2)
	near(new1.hp, 60.0, 0.01, "seat 1's Wick keeps his HP")
	check(new2.dead, "seat 2's Wick is still down, though both are Wick")
	# A hero outside the crew (tests, the arena) has no seat: keyed by name, as before.
	var loner := HeroFactory.spawn_hero(Vector2i(6, 0), "Loner", Color.WHITE)
	loner.hp = 12.0
	var solo: Array[Hero] = [loner]
	session.save_carry(solo)
	eq(ContractSession.carry_key(loner), "Loner", "a hero without a seat is keyed by name")
	var again := HeroFactory.spawn_hero(Vector2i(7, 0), "Loner", Color.WHITE)
	session.apply_carry(again)
	near(again.hp, 12.0, 0.01, "and carries as before")
	for h in [wick1, wick2, gasket, new1, new2, loner, again]:
		h.free()


func _check_become() -> void:
	var hero := HeroFactory.spawn_hero(Vector2i(8, 0), "Wick", Color(0.3, 0.55, 0.95), "sword", WickModel.new(), HeroKit.WICK)
	hero.set_player_name("Sam")
	check(hero._name_label != null and hero._name_label.text == "Sam", "a player's name shows over the hero")
	eq(Net.label_of(hero), "Sam", "Net.label_of is the player's name")
	hero.hp = hero.max_hp * 0.5
	var spot := hero.global_position
	var id_before := hero.get_instance_id()
	hero.become(HeroKit.REBAR, "Rebar", Color(0.85, 0.5, 0.25), RebarModel.new())
	eq(hero.get_instance_id(), id_before, "the node is the same one")
	check(hero.global_position.is_equal_approx(spot), "it stands where it stood")
	eq(hero.kit_id, HeroKit.REBAR, "its kit is Rebar's")
	near(hero.max_hp, 160.0, 0.01, "with Rebar's HP")
	near(hero.hp, 80.0, 0.01, "the same half of it")
	eq(hero.display_name, "Rebar", "its name is Rebar")
	eq(Net.label_of(hero), "Rebar", "the player's name is gone from it")
	eq(hero.secondary_kind, "bowl", "its secondary is the bowl")
	check(hero._name_label != null and hero._name_label.text == "Rebar", "the nameplate reads Rebar")
	check(hero._visual != null and is_instance_valid(hero._visual) and hero.visual_override is RebarModel, "it has Rebar's body")
	eq(hero.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Visual")).size(), 1, "and only one body (the old one is gone)")
	# A downed hero stays downed.
	hero.apply_damage(9999.0)
	check(hero.dead, "downed")
	hero.become(HeroKit.GASKET, "Gasket", Color(0.7, 0.4, 0.85), GasketModel.new())
	check(hero.dead and hero.hp == 0.0, "a downed hero stays downed when the seat changes character")
	eq(hero.kit_id, HeroKit.GASKET, "and is now Gasket")
	hero.free()


func _check_seat_table() -> void:
	var seats := Session.seats
	check(seats != null and Session.snap != null, "the Session has its Seats and Snap nodes")
	seats.begin({1: 1, 2: 5, 3: 0}, {2: "rebar", 3: "gasket"})
	eq(seats.owner_of(1), 1, "seat 1 is the host's")
	eq(seats.owner_of(2), 5, "seat 2 belongs to peer 5")
	eq(seats.owner_of(3), 0, "seat 3 is AI")
	eq(seats.seat_of(5), 2, "peer 5 sits in seat 2")
	eq(seats.seat_of(0), 0, "no peer 0 owns a seat (0 means AI)")
	eq(seats.seat_of(77), 0, "an unknown peer has none")
	eq(seats.epoch_of(2), 0, "epoch starts at 0")
	seats.release(2)
	eq(seats.owner_of(2), 5, "release is a host-only verb: offline it does nothing")
	seats.reset()
	eq(seats.owner_of(2), 0, "reset() forgets the table")
