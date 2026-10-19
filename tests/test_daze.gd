extends TestCase
## The brute's daze (Actor.daze, through Combat.slam): a DIRECT hit from the slam (a hero's centre within
## Brute.DAZE_RADIUS) dazes the hero for DAZE_TIME; the edge band only hurts. While dazed: no walking, no melee, no
## secondary, the bow draw is lost; a spoken spell still goes off. It ignores shove_mult (Rebar reels too). A daze is
## followed by Actor.DAZE_GUARD of immunity (no stun-lock). The AI ally waits it out. Fight slams never daze. Every screen
## shows it from the daze modifier (stars over the head, the HUD's DAZED tag for your own hero).

const BRUTE := preload("res://scripts/monsters/brute.gd")

var root: Node3D


func _flat_map(radius: int = 9) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 0)
	return m


func _world() -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(_flat_map(), root, 7)


## A brute at `at` that does nothing on its own (the test calls its slam).
func _brute(at: Vector3) -> Monster:
	var b := MonsterFactory.spawn("brute", Hex.from_world(at))
	b.global_position = at
	b.snap_to_ground()
	b.aggro_range = 0.0
	b.set_physics_process(false)
	return b


func _hero(kit: String, at: Vector3) -> Hero:
	var h := HeroFactory.spawn_hero(Hex.from_world(at), kit.capitalize(), Color.ORANGE, "sword", null, kit)
	h.global_position = at
	h.snap_to_ground()
	return h


## Physics frames for `seconds` of GameWorld time (tests run at a fixed 60 fps).
func _secs(seconds: float) -> int:
	return int(ceilf(seconds * 60.0))


func setup() -> void:
	check(BRUTE.DAZE_RADIUS < BRUTE.SLAM_RADIUS, "the daze zone (%.1f) is inside the slam ring (%.1f)" % [BRUTE.DAZE_RADIUS, BRUTE.SLAM_RADIUS])
	near(BRUTE.DAZE_TIME, 0.6, 0.001, "a daze lasts 0.6 s")
	near(Actor.DAZE_GUARD, 1.5, 0.001, "then 1.5 s of immunity")
	await _direct_and_edge()
	await _no_move_no_attack()
	await _rebar()
	await _voice_lands()
	await _guard()
	await _ally_waits()
	await _fight_slams_and_copies()
	finish()


# --- A direct hit dazes, an edge hit does not -------------------------------------------------------------------

func _direct_and_edge() -> void:
	_world()
	var brute := _brute(Vector3.ZERO)
	var direct := _hero("gasket", Vector3(1.2, 0, 0))
	var inner_edge := _hero("gasket", Vector3(0, 0, BRUTE.DAZE_RADIUS - 0.05))
	var edge := _hero("gasket", Vector3(-1.85, 0, 0))
	var hp_edge := edge.hp
	brute._strike()
	check(direct.is_dazed(), "a hero 1.2 from the brute (a direct hit) is dazed")
	check(inner_edge.is_dazed(), "... and one just inside the daze line (%.2f)" % (BRUTE.DAZE_RADIUS - 0.05))
	check(not edge.is_dazed(), "a hero in the edge band (1.85) is not dazed")
	check(edge.hp < hp_edge, "... but the edge hit still hurts (%.1f)" % (hp_edge - edge.hp))
	check(direct.is_helpless(), "a dazed hero is helpless (the controllers and the AI skip it)")
	await frames(_secs(BRUTE.DAZE_TIME - 0.08))
	check(direct.is_dazed(), "still dazed just before 0.6 s")
	await frames(_secs(0.12))
	check(not direct.is_dazed(), "the daze is over just after 0.6 s")
	check(not direct.is_helpless(), "... and the hero acts again")


# --- While dazed: no walking, no melee, no secondary; the draw is cancelled ----------------------------------------

func _no_move_no_attack() -> void:
	_world()
	var brute := _brute(Vector3.ZERO)
	var wick := _hero("wick", Vector3(1.1, 0, 0))
	var pc := HeroFactory.make_player(wick, ["heal"])
	pc.aim_override = Vector3(4, 0, 4)
	pc.enabled = false   # (with no RMB held the controller would let the draw go: the test holds it)
	check(wick.start_draw(), "Wick draws his bow")
	await frames(6)
	check(wick.is_drawing(), "... and holds the draw")
	brute._strike()
	check(wick.is_dazed(), "the slam dazes Wick")
	check(not wick.is_drawing(), "the daze cancels the draw in progress")
	pc.enabled = true
	for i in 30:
		if not wick.is_shoved():
			break
		await frames(1)   # (the slam's shove slides him out first; the daze outlasts it)
	check(wick.is_dazed(), "still dazed after the slam's shove ends")
	var at := wick.global_position
	wick._ready_at.clear()
	check(not wick.melee(Vector3.RIGHT), "no melee while dazed")
	check(not wick.shoot(Vector3.RIGHT), "no secondary (an arrow) while dazed")
	check(not wick.start_draw(), "no new draw while dazed")
	check(not wick.move(Vector3.RIGHT, 0.1), "no walking while dazed (move refuses)")
	pc.move_override = Vector3.LEFT
	await frames(12)
	near(GameWorld.flat_distance(wick.global_position, at), 0.0, 0.001, "the player's steering does not move a dazed hero")
	pc.move_override = Vector3.INF
	await frames(_secs(BRUTE.DAZE_TIME))
	check(not wick.is_dazed(), "the daze wore off")
	var free_at := wick.global_position
	pc.move_override = Vector3.RIGHT   # (away from the brute)
	await frames(12)
	check(GameWorld.flat_distance(wick.global_position, free_at) > 0.5, "... and steering walks again")
	pc.move_override = Vector3.INF
	wick._ready_at.clear()
	check(wick.melee(Vector3.RIGHT), "... and swings again")


# --- Rebar: immovable, but dazed all the same ----------------------------------------------------------------------

func _rebar() -> void:
	_world()
	var brute := _brute(Vector3.ZERO)
	var rebar := _hero("rebar", Vector3(1.3, 0, 0))
	near(rebar.shove_mult, 0.0, 0.0001, "Rebar can't be shoved (shove_mult 0)")
	var at := rebar.global_position
	brute._strike()
	await frames(2)
	near(GameWorld.flat_distance(rebar.global_position, at), 0.0, 0.001, "the slam does not move Rebar")
	check(rebar.is_dazed(), "... but it dazes him")
	rebar._ready_at.clear()
	check(not rebar.melee(Vector3.LEFT), "a dazed Rebar can't punch")
	check(not rebar.shoot(Vector3.LEFT), "... or bowl")
	await frames(_secs(BRUTE.DAZE_TIME + 0.05))
	rebar._ready_at.clear()
	check(rebar.melee(Vector3.LEFT), "he punches again once it wears off")


# --- A spell spoken while dazed goes off ---------------------------------------------------------------------------

func _voice_lands() -> void:
	_world()
	var brute := _brute(Vector3.ZERO)
	var gasket := _hero("gasket", Vector3(1.2, 0, 0))
	var hud := Hud.new()
	add_child(hud)
	var pc := HeroFactory.make_player(gasket, ["heal", "fireball"])
	pc.hud = hud
	hud.bind(gasket, [])
	pc.aim_override = gasket.global_position
	brute._strike()
	check(gasket.is_dazed(), "Gasket is dazed")
	await frames(2)
	check(hud._daze_tag.visible, "the HUD shows DAZED for your own hero")
	check(gasket.is_showing_daze(), "stars over the dazed hero's head")
	var hurt := gasket.hp
	var casts := [0]
	gasket.spell_cast.connect(func(_id: String, _p: float) -> void: casts[0] += 1)
	check(pc.cast_spell("heal", 1.0), "a heal spoken while dazed is cast (voice and the typed console both go through cast_spell)")
	await frames(3)
	eq(casts[0], 1, "the cast went off at once (casts are never held or dropped by a daze)")
	check(gasket.is_dazed(), "... while the hero is still dazed")
	check(gasket.hp > hurt, "the heal landed (%.1f -> %.1f)" % [hurt, gasket.hp])
	await frames(_secs(BRUTE.DAZE_TIME))
	check(not hud._daze_tag.visible, "the HUD tag goes away with the daze")
	check(not gasket.is_showing_daze(), "... and so do the stars")
	hud.queue_free()


# --- No stun-lock: a daze is followed by DAZE_GUARD of immunity ----------------------------------------------------

func _guard() -> void:
	_world()
	var brute := _brute(Vector3.ZERO)
	var rebar := _hero("rebar", Vector3(1.2, 0, 0))   # Rebar stays put, so every slam is a direct hit
	brute._strike()
	check(rebar.is_dazed(), "the first slam dazes")
	await frames(_secs(0.2))
	var left: float = rebar.modifier_left(Actor.DAZE_ID)
	brute._strike()
	check(rebar.modifier_left(Actor.DAZE_ID) <= left + 0.001, "a second slam during the daze does not extend it (%.2f s left)" % left)
	await frames(_secs(BRUTE.DAZE_TIME - 0.2 + 0.1))
	check(not rebar.is_dazed(), "the daze ended on time")
	check(rebar.daze_guard_left() > 1.0, "the immunity runs on (%.2f s left)" % rebar.daze_guard_left())
	var hp := rebar.hp
	brute._strike()
	check(rebar.hp < hp, "a slam during the immunity still hurts")
	check(not rebar.is_dazed(), "... but does not daze (two brutes can't chain it)")
	await frames(_secs(rebar.daze_guard_left() + 0.05))
	brute._strike()
	check(rebar.is_dazed(), "after the immunity a direct hit dazes again")


# --- The AI ally waits out its daze --------------------------------------------------------------------------------

func _ally_waits() -> void:
	_world()
	var leader := _hero("wick", Vector3(-4.0, 0, 0))
	var foe := _brute(Vector3(1.4, 0, 0))   # frozen: it only stands there to be punched (and slams when told)
	foe.max_hp = 5000.0
	foe.hp = 5000.0
	foe.shove_mult = 0.0   # (Rebar's punches would knock it out of reach)
	var rebar := _hero("rebar", Vector3(0, 0, 0))
	HeroFactory.make_ally(rebar, leader, false, 2.4)
	var swings := [0]
	rebar.melee_swung.connect(func() -> void: swings[0] += 1)
	var ok := false
	for i in 120:
		await frames(1)
		if swings[0] > 0:
			ok = true
			break
	check(ok, "the AI Rebar punches the brute next to him")
	await frames(_secs(0.85))   # (past his punch's cooldown, so a swing would show at once)
	var at := rebar.global_position
	var before: int = swings[0]
	foe._strike()
	check(rebar.is_dazed(), "the brute's slam dazes the AI Rebar")
	var moved := 0.0
	while rebar.is_dazed():
		await frames(1)
		moved = maxf(moved, GameWorld.flat_distance(rebar.global_position, at))
	eq(swings[0], before, "the AI threw no punch while dazed")
	near(moved, 0.0, 0.001, "... and did not step")
	ok = false
	for i in _secs(1.2):
		await frames(1)
		if swings[0] > before:
			ok = true
			break
	check(ok, "it fights again once the daze wears off")


# --- Fight slams never daze; a copy shows the owner's daze ---------------------------------------------------------

func _fight_slams_and_copies() -> void:
	_world()
	var brute := _brute(Vector3.ZERO)
	var grunt := MonsterFactory.spawn("grunt", Hex.from_world(Vector3(1.2, 0, 0)))
	grunt.global_position = Vector3(1.2, 0, 0)
	grunt.set_physics_process(false)
	brute._fight_slam(grunt)
	check(not grunt.is_dazed(), "a restless-fight slam never dazes a monster")
	# A copy (another machine's hero): it shows the daze its owner announced, and never dazes itself.
	var copy := _hero("wick", Vector3(-3.0, 0, 0))
	Net.make_puppet(copy)
	check(not copy.daze(0.6), "a copy refuses a daze (its owner decides)")
	copy.net_set_modifiers({Actor.DAZE_ID: [1.0, 0.6, Actor.STAT_DAZE]}, NetStatus.GRACE)
	check(copy.is_dazed(), "the announced daze shows on the copy")
	near(copy.modifier_left(Actor.DAZE_ID), 0.6, 0.02, "... for the owner's time, with no grace added")
	await frames(2)
	check(copy.is_showing_daze(), "... with the stars over its head")
	await frames(_secs(0.65))
	check(not copy.is_showing_daze(), "the stars go when the daze does")
	Net.release_copy(copy)
