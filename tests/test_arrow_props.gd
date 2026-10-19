extends TestCase
## All arrows hit props (user, 2026-10-18: "all arrows hit props"): Wick's arrows, the hero bolt and the archer's arrow
## chip a priced prop they run into and can break it (the last damager's break bills like any other); a projectile that
## is not an arrow (a fireball's flight: Projectile without hits_props) still flies through props, as before. A pierce-1
## arrow stops at the prop. A copy's arrow (a client's puppet archer) never damages anything it does not resolve.

var root: Node3D


func _flat_map(radius: int = 10) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 0)
	return m


func _fresh() -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(_flat_map(), root, 5)
	Ledger.begin_contract(1000000)


func _hero(pos: Vector3, hero_name: String = "Wick", secondary: String = "arrow") -> Hero:
	var h := Hero.new()
	h.display_name = hero_name
	h.secondary_kind = secondary
	GameWorld.spawn(h, pos)
	h.snap_to_ground()
	return h


func _prop(kind: String, pos: Vector3) -> PricedProp:
	var p := PricedProp.spawn(Hex.from_world(pos), kind, {})
	p.global_position = Vector3(pos.x, p.global_position.y, pos.z)
	return p


func _wait_free(n: Node, max_frames: int = 120) -> void:
	for _i in max_frames:
		if not is_instance_valid(n):
			return
		await get_tree().physics_frame


func setup() -> void:
	# Wick's arrow (ArrowShot): chips, then breaks and bills to Wick.
	_fresh()
	var wick := _hero(Vector3(-6, 0, 0), "Wick", "arrow")
	var lamp := _prop("crystal_lamp", Vector3(0, 0, 0))          # $600, 25 HP
	var arrow := ArrowShot.shoot(wick, Vector3.RIGHT, 12.0, 30.0, 14.0, 1, false, Color.WHITE)
	check(arrow.hits_props, "Wick's arrows hit props")
	await _wait_free(arrow)
	near(lamp.hp, 13.0, 0.01, "an arrow chips the lamp (12)")
	eq(Ledger.damages(), 0, "a dent is free")
	for _i in 2:
		arrow = ArrowShot.shoot(wick, Vector3.RIGHT, 12.0, 30.0, 14.0, 1, false, Color.WHITE)
		await _wait_free(arrow)
	check(lamp.dead, "three arrows break it")
	eq(Ledger.damages(), 600, "the break bills the price once")
	eq(str(Ledger.lines.back().get("who", "")), "Wick", "... to Wick, the last damager")
	# A pierce-1 arrow stops at the prop: the monster behind it is safe.
	_fresh()
	wick = _hero(Vector3(-6, 0, 0), "Wick", "arrow")
	var rack := _prop("wine_rack", Vector3(0, 0, 0))
	var behind := MonsterFactory.spawn("grunt", Hex.from_world(Vector3(3.5, 0, 0)))
	behind.aggro_range = 0.0
	arrow = ArrowShot.shoot(wick, Vector3.RIGHT, 12.0, 30.0, 14.0, 1, false, Color.WHITE)
	await _wait_free(arrow)
	near(rack.hp, rack.max_hp - 12.0, 0.01, "the rack takes the arrow")
	near(behind.hp, behind.max_hp, 0.01, "and the grunt behind it does not")

	# The hero bolt (Wick's old secondary, Gasket/Rebar's ranged poke): chips a prop.
	_fresh()
	var bolter := _hero(Vector3(-6, 0, 0), "Wick", "bolt")
	var server := _prop("server_rack", Vector3(0, 0, 0))
	check(bolter.shoot(Vector3.RIGHT), "the bolt flies")
	await frames(60)
	check(server.hp < server.max_hp - 0.5, "a bolt chips a prop (%.1f of %.0f)" % [server.hp, server.max_hp])

	# The archer's arrow: chips a prop, and enough of them break it (billed to the archer: no invoice change).
	_fresh()
	var archer = MonsterFactory.spawn("archer", Hex.from_world(Vector3(-6, 0, 0)))
	archer.aggro_range = 0.0
	var portrait := _prop("crystal_lamp", Vector3(0, 0, 0))
	await frames(2)
	var shot: Projectile = archer._fire_arrow(Vector3.RIGHT, 8.0)
	check(shot.hits_props, "the archer's arrow hits props")
	await _wait_free(shot)
	near(portrait.hp, 17.0, 0.01, "an archer's arrow chips the lamp (8)")
	for _i in 3:
		shot = archer._fire_arrow(Vector3.RIGHT, 8.0)
		await _wait_free(shot)
	check(portrait.dead, "four arrows break it")
	eq(Ledger.damages(), 600, "the break bills like any other")

	# Not an arrow: a plain Projectile (a fireball's flight) still passes props.
	_fresh()
	var caster := _hero(Vector3(-6, 0, 0), "Wick", "arrow")
	var statue := _prop("marble_statue", Vector3(0, 0, 0))
	var ball := Projectile.fire(caster, Vector3(-5, 0.9, 0), Vector3.RIGHT, 10.0, 14.0, 10.0)
	check(not ball.hits_props, "a plain projectile does not hit props")
	await _wait_free(ball)
	near(statue.hp, statue.max_hp, 0.01, "it flies through the statue untouched")

	# A copy's arrow (a client's puppet archer): flies and stops at the prop, but damages nothing it doesn't resolve.
	_fresh()
	archer = MonsterFactory.spawn("archer", Hex.from_world(Vector3(-6, 0, 0)))
	archer.aggro_range = 0.0
	var vase := _prop("crystal_lamp", Vector3(0, 0, 0))
	await frames(2)
	Net.make_copy(archer)
	archer.facing = Vector3.RIGHT
	archer.state = Monster.State.IDLE
	archer._on_strike_visual()                                     # a practice shot's visual (damage on: the victim decides)
	await frames(40)
	near(vase.hp, vase.max_hp, 0.01, "a copy's practice arrow never damages the host's prop")
	archer.state = Monster.State.CHASE
	archer._on_strike_visual()                                     # a fight's visual (harmless)
	await frames(40)
	near(vase.hp, vase.max_hp, 0.01, "... nor does a fight's visual arrow")
	finish()
