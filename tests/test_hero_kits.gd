extends TestCase
## Per-hero kits (HeroKit): HP, primary (damage / reach / arc / cooldown / shove), Larkin's tap vs
## drawn arrow, releasing early, climb rules (Pebble cannot climb +2, Larkin is faster than Dagna),
## shove_mult, the HUD bars, the ally brain's own primaries, and the kits surviving --proto-heroes
## (no model).

var root: Node3D


func _flat_map(radius: int = 18) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 0)
	return m


func _fresh(map: HexMap = null) -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(map if map != null else _flat_map(), root, 5)


func _dummy(pos: Vector3, hp: float = 1000.0) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.max_hp = hp
	GameWorld.spawn(d, pos)
	d.snap_to_ground()
	return d


func _kit_hero(kit_id: String, cell: Vector2i = Vector2i.ZERO, model: Node3D = null) -> Hero:
	return HeroFactory.spawn_hero(cell, kit_id.capitalize(), Color.CORNFLOWER_BLUE, "sword", model, kit_id)


func _polar(dist: float, deg: float) -> Vector3:
	return Vector3(cos(deg_to_rad(deg)), 0.0, sin(deg_to_rad(deg))) * dist


func setup() -> void:
	_test_hp_and_data()
	await _test_primaries()
	await _test_arrow()
	await _test_climb()
	await _test_shove_mult()
	await _test_proto_and_models()
	await _test_hud_bars()
	await _test_ally_primaries()
	finish()


# --- HP, the data table ----------------------------------------------------------------------

func _test_hp_and_data() -> void:
	_fresh()
	var larkin := _kit_hero("larkin")
	var dagna := _kit_hero("dagna")
	var pebble := _kit_hero("pebble")
	near(larkin.max_hp, 85.0, 0.001, "Larkin HP")
	near(dagna.max_hp, 120.0, 0.001, "Dagna HP")
	near(pebble.max_hp, 160.0, 0.001, "Pebble HP")
	near(larkin.hp, 85.0, 0.001, "Larkin starts at full HP")
	near(pebble.hp, 160.0, 0.001, "Pebble starts at full HP")
	eq(larkin.secondary_kind, "arrow", "Larkin's secondary")
	eq(dagna.secondary_kind, "spin", "Dagna's secondary")
	eq(pebble.secondary_kind, "bowl", "Pebble's secondary")
	eq(larkin.kit_id, "larkin", "kit id recorded")
	check(HeroKit.get_kit("Dagna") != null, "kits are looked up case-insensitively")
	check(HeroKit.get_kit("rattles") == null, "dropped heroes have no kit")
	check(not HeroKit.apply_to(larkin, "nobody"), "an unknown kit is a no-op")
	eq(HeroKit.ids().size(), 3, "three kits")
	# A hero that never got a kit keeps the generic sword numbers.
	var plain := Hero.new()
	GameWorld.spawn(plain, Vector3.ZERO)
	near(plain.max_hp, 100.0, 0.001, "kit-less hero: 100 HP")
	near(plain.melee_damage, Hero.MELEE_DAMAGE, 0.001, "kit-less hero: sword damage")
	eq(plain.secondary_kind, "bolt", "kit-less hero: bolt")
	check(plain.can_climb, "kit-less hero climbs")


# --- Primaries: damage, reach, arc, cooldown, shove -------------------------------------------

func _test_primaries() -> void:
	var expect := {
		"larkin": {"dmg": 12.0, "cd": 0.4, "reach": 1.3, "arc": 90.0, "shove": 0.7},
		"dagna": {"dmg": 28.0, "cd": 0.65, "reach": 1.5, "arc": 90.0, "shove": 0.9},
		"pebble": {"dmg": 26.0, "cd": 0.8, "reach": 1.8, "arc": 120.0, "shove": 1.0},
	}
	for id: String in expect:
		var e: Dictionary = expect[id]
		_fresh()
		var hero := _kit_hero(id)
		near(hero.melee_damage, e["dmg"], 0.0001, "%s primary damage field" % id)
		near(hero.melee_cooldown, e["cd"], 0.0001, "%s primary cooldown field" % id)
		near(hero.melee_reach, e["reach"], 0.0001, "%s reach field" % id)
		near(hero.melee_arc, e["arc"], 0.0001, "%s arc field" % id)
		near(hero.melee_shove, e["shove"], 0.0001, "%s shove field" % id)
		var reach: float = e["reach"]
		var arc: float = e["arc"]
		var origin := hero.global_position
		var inside := _dummy(origin + _polar(reach + 0.40, 0.0))        # dummy radius 0.45: just inside reach
		var outside := _dummy(origin + _polar(reach + 0.45 + 0.35, 180.0))   # behind AND out of reach
		var edge_in := _dummy(origin + _polar(0.9, arc * 0.5 - 3.0))
		var edge_out := _dummy(origin + _polar(0.9, -(arc * 0.5 + 4.0)))
		var rear := _dummy(origin + _polar(0.9, 180.0))
		var far_edge := _dummy(origin + _polar(reach + 0.45 + 0.30, 20.0))    # right angle, but out of reach
		var start_in := inside.global_position
		var start_edge := edge_in.global_position
		check(hero.melee(Vector3.RIGHT), "%s primary fires" % id)
		near(hero.cooldown_left(Hero.KEY_MELEE), e["cd"], 0.02, "%s primary cooldown" % id)
		check(not hero.melee(Vector3.RIGHT), "%s cooldown blocks an immediate swing" % id)
		near(inside.hp, inside.max_hp - float(e["dmg"]), 0.001, "%s damage" % id)
		near(edge_in.hp, edge_in.max_hp - float(e["dmg"]), 0.001, "%s hits just inside its %d degree arc" % [id, int(arc)])
		near(edge_out.hp, edge_out.max_hp, 0.001, "%s misses just outside its arc" % id)
		near(rear.hp, rear.max_hp, 0.001, "%s misses behind" % id)
		near(outside.hp, outside.max_hp, 0.001, "%s misses out of reach (behind)" % id)
		near(far_edge.hp, far_edge.max_hp, 0.001, "%s misses beyond its reach" % id)
		await frames(40)
		near(inside.global_position.distance_to(start_in), e["shove"], 0.1, "%s shoves its target %.1f" % [id, float(e["shove"])])
		near(edge_in.global_position.distance_to(start_edge), e["shove"], 0.1, "%s shoves the arc-edge target too" % id)
		var frames_cd := int(float(e["cd"]) * 60.0)
		await frames(maxi(0, frames_cd - 40) + 2)
		check(hero.melee(Vector3.RIGHT), "%s swings again once the cooldown is up" % id)
	# The three feel different: Dagna hits hardest, Pebble reaches farthest, Larkin is quickest.
	check(28.0 > 26.0 and 26.0 > 12.0, "damage order Dagna > Pebble > Larkin")
	check(HeroKit.DATA["larkin"]["melee_cooldown"] < HeroKit.DATA["dagna"]["melee_cooldown"], "Larkin swings faster than Dagna")
	check(HeroKit.DATA["dagna"]["melee_cooldown"] < HeroKit.DATA["pebble"]["melee_cooldown"], "Dagna swings faster than Pebble")


# --- Larkin's arrow --------------------------------------------------------------------------

func _line(origin: Vector3, xs: Array) -> Array[TrainingDummy]:
	var out: Array[TrainingDummy] = []
	for x: float in xs:
		out.append(_dummy(origin + Vector3(x, 0, 0)))
	return out


func _test_arrow() -> void:
	# Tap: 12 dmg, hits only the first target in line, 0.55 s cooldown.
	_fresh()
	var larkin := _kit_hero("larkin", Vector2i(-8, 0))
	var o := larkin.global_position
	var line := _line(o, [3.0, 5.0, 7.0, 9.0])
	check(larkin.shoot(Vector3.RIGHT), "RMB tap (shoot) fires an arrow")
	near(larkin.cooldown_left(Hero.KEY_RANGED), 0.55, 0.02, "tap cooldown 0.55 s")
	check(not larkin.shoot(Vector3.RIGHT), "tap cooldown blocks")
	await frames(40)
	near(line[0].hp, line[0].max_hp - 12.0, 0.001, "tap does 12")
	near(line[1].hp, line[1].max_hp, 0.001, "a tap shot does not pierce")
	near(line[2].hp, line[2].max_hp, 0.001, "a tap shot does not pierce (3rd)")

	# Drawn: hold 0.7 s, then 28 damage pierces up to 3 targets.
	await frames(10)   # cooldown over
	check(larkin.start_draw(), "the bow can be drawn")
	check(larkin.is_drawing(), "drawing")
	near(larkin.draw_progress(), 0.0, 0.1, "draw starts at 0")
	await frames(21)
	var mid := larkin.draw_progress()
	check(mid > 0.3 and mid < 0.6, "draw is half-way after ~0.35 s (%.2f)" % mid)
	await frames(30)
	near(larkin.draw_progress(), 1.0, 0.0001, "fully drawn after 0.7 s")
	check(larkin.release_draw(Vector3.RIGHT), "releasing a full draw fires")
	check(not larkin.is_drawing(), "no longer drawing")
	near(larkin.cooldown_left(Hero.KEY_RANGED), 0.55, 0.02, "the drawn shot costs the same recovery")
	await frames(45)
	near(line[0].hp, line[0].max_hp - 12.0 - 28.0, 0.001, "drawn shot: 28 to the 1st")
	near(line[1].hp, line[1].max_hp - 28.0, 0.001, "drawn shot: 28 to the 2nd (pierce)")
	near(line[2].hp, line[2].max_hp - 28.0, 0.001, "drawn shot: 28 to the 3rd (pierce)")
	near(line[3].hp, line[3].max_hp, 0.001, "pierce stops after 3 targets")

	# Releasing early = a tap shot (12, no pierce), even after holding most of the draw.
	_fresh()
	larkin = _kit_hero("larkin", Vector2i(-8, 0))
	o = larkin.global_position
	line = _line(o, [3.0, 5.0, 7.0])
	check(larkin.start_draw(), "draw for an early release")
	await frames(30)    # 0.5 s of 0.7 s
	check(larkin.draw_progress() < 1.0, "not a full draw yet")
	check(larkin.release_draw(Vector3.RIGHT), "early release fires")
	await frames(40)
	near(line[0].hp, line[0].max_hp - 12.0, 0.001, "early release is a 12 damage tap")
	near(line[1].hp, line[1].max_hp, 0.001, "and does not pierce")
	check(not larkin.release_draw(Vector3.RIGHT), "nothing to release when not drawing")

	# Cancelling (the melee bash lowers the bow) fires nothing; the bow cannot be drawn during recovery.
	await frames(40)
	check(larkin.start_draw(), "draw again")
	check(larkin.melee(Vector3.RIGHT), "melee while drawing")
	check(not larkin.is_drawing(), "the bash lowers the bow")
	_fresh()
	larkin = _kit_hero("larkin", Vector2i(-8, 0))
	larkin.shoot(Vector3.RIGHT)
	check(not larkin.start_draw(), "no drawing while the last shot recovers")
	var plain := Hero.new()
	GameWorld.spawn(plain, Vector3(0, 0, 4))
	check(not plain.start_draw(), "a bolt hero cannot draw")

	# Range: tap 14, drawn 18 (measured from the hero).
	_fresh()
	larkin = _kit_hero("larkin", Vector2i(-12, 0))
	o = larkin.global_position
	var near_t := _dummy(o + Vector3(13.0, 0, 0))     # inside the tap range
	check(larkin.shoot(Vector3.RIGHT), "tap at long range")
	await frames(75)
	near(near_t.hp, near_t.max_hp - 12.0, 0.001, "a tap reaches 13")
	_fresh()
	larkin = _kit_hero("larkin", Vector2i(-12, 0))
	o = larkin.global_position
	var beyond_tap := _dummy(o + Vector3(16.5, 0, 0))
	larkin.shoot(Vector3.RIGHT)
	await frames(90)
	near(beyond_tap.hp, beyond_tap.max_hp, 0.001, "a tap does not reach 16.5 (range 14)")
	_fresh()
	larkin = _kit_hero("larkin", Vector2i(-12, 0))
	o = larkin.global_position
	var in_draw := _dummy(o + Vector3(17.0, 0, 0))
	var past_draw := _dummy(o + Vector3(21.5, 0, 0.2))
	larkin.start_draw()
	await frames(46)
	larkin.release_draw(Vector3.RIGHT)
	await frames(100)
	near(in_draw.hp, in_draw.max_hp - 28.0, 0.001, "a drawn shot reaches 17 (range 18)")
	near(past_draw.hp, past_draw.max_hp, 0.001, "a drawn shot stops before 21.5")

	# Stats from the kit.
	near(larkin.arrow_tap_damage, 12.0, 0.001, "tap damage field")
	near(larkin.arrow_draw_damage, 28.0, 0.001, "drawn damage field")
	eq(larkin.arrow_draw_pierce, 3, "drawn pierce field")
	near(larkin.arrow_tap_range, 14.0, 0.001, "tap range field")
	near(larkin.arrow_draw_range, 18.0, 0.001, "drawn range field")
	near(larkin.arrow_draw_time, 0.7, 0.001, "draw time field")

	# Walking while drawing is half speed; the charge ring and the model's bow follow the draw.
	_fresh()
	var model := LarkinModel.new()
	larkin = _kit_hero("larkin", Vector2i(-8, 0), model)
	var x0 := larkin.global_position.x
	for i in 60:
		larkin.move(Vector3.RIGHT, 1.0 / 60.0)
		await get_tree().physics_frame
	var free_run := larkin.global_position.x - x0
	larkin.start_draw()
	var x1 := larkin.global_position.x
	for i in 30:
		larkin.move(Vector3.RIGHT, 1.0 / 60.0)
		await get_tree().physics_frame
	var drawn_run := larkin.global_position.x - x1
	near(drawn_run, free_run * 0.5 * 0.5, 0.2, "drawing halves walking speed (%.2f vs free %.2f for half the time)" % [drawn_run, free_run])
	near(larkin.move_speed, 4.5, 0.0001, "move_speed is restored after the drawn step")
	check(larkin._charge_ring != null and larkin._charge_ring.visible, "a charge ring shows while drawing")
	var s0 := larkin._charge_ring.scale.x
	await frames(15)
	check(larkin._charge_ring.scale.x > s0, "the ring grows as the bow is drawn (%.2f -> %.2f)" % [s0, larkin._charge_ring.scale.x])
	check(model.arm_kick("draw") > 0.5, "the model's bow is drawn (draw_hold %.2f)" % model.arm_kick("draw"))
	await frames(30)
	near(larkin._charge_ring.scale.x, 1.0, 0.15, "full ring at a full draw")
	larkin.release_draw(Vector3.RIGHT)
	await frames(2)
	check(not larkin._charge_ring.visible, "the ring hides on release")
	# Getting shoved lowers the bow.
	await frames(60)
	larkin.start_draw()
	larkin.shove(Vector3.RIGHT, 1.0)
	await frames(2)
	check(not larkin.is_drawing(), "a shove lowers the bow")


# --- Climbing --------------------------------------------------------------------------------

func _row_map(levels: Array) -> HexMap:
	var m := HexMap.new()
	for i in levels.size():
		m.set_cell(Vector2i(i, 0), levels[i])
	return m


## Walk right for `seconds`; returns {x, climb_speed (avg speed over climbing frames), climbed}.
func _walk_row(hero: Hero, seconds: float) -> Dictionary:
	var climb_dist := 0.0
	var climb_frames := 0
	var prev_x := hero.global_position.x
	for i in int(seconds * 60.0):
		hero.move(Vector3.RIGHT, 1.0 / 60.0)
		if hero.climbing:
			climb_dist += hero.global_position.x - prev_x
			climb_frames += 1
		prev_x = hero.global_position.x
		await get_tree().physics_frame
	return {"x": hero.global_position.x, "speed": climb_dist * 60.0 / maxf(climb_frames, 1), "frames": climb_frames}


func _test_climb() -> void:
	# +1 steps are walked by everyone, Pebble included.
	_fresh(_row_map([0, 0, 1, 1, 1, 1, 1, 1]))
	var pebble := _kit_hero("pebble")
	var r := await _walk_row(pebble, 3.0)
	check(r["x"] > Hex.to_world(Vector2i(3, 0)).x, "Pebble walks up a +1 step (x=%.2f)" % float(r["x"]))
	eq(int(r["frames"]), 0, "and never climbs for it")

	# A +2 ledge: Pebble cannot get up; Dagna and Larkin can, Larkin faster.
	var ledge := [0, 0, 2, 2, 2, 2, 2, 2, 2, 2]
	_fresh(_row_map(ledge))
	pebble = _kit_hero("pebble")
	check(not pebble.can_climb, "Pebble: can_climb false")
	r = await _walk_row(pebble, 6.0)
	check(r["x"] < Hex.to_world(Vector2i(2, 0)).x, "Pebble is stopped by a +2 ledge (x=%.2f)" % float(r["x"]))
	eq(int(r["frames"]), 0, "Pebble never enters the climbing state")
	near(pebble.global_position.y, 0.0, 0.05, "and stays on the low floor")
	# He also refuses to path over it.
	check(GameWorld.map.find_path(Vector2i(0, 0), Vector2i(5, 0), pebble.can_climb).is_empty(), "no climbing path for Pebble")

	_fresh(_row_map(ledge))
	var dagna := _kit_hero("dagna")
	near(dagna.climb_speed_factor, 0.25, 0.0001, "Dagna climb factor on the hero")
	var rd := await _walk_row(dagna, 10.0)
	_fresh(_row_map(ledge))
	var larkin := _kit_hero("larkin")
	var rl := await _walk_row(larkin, 10.0)
	check(rd["x"] > Hex.to_world(Vector2i(3, 0)).x, "Dagna gets over a +2 ledge (x=%.2f)" % float(rd["x"]))
	check(rl["x"] > Hex.to_world(Vector2i(3, 0)).x, "Larkin gets over a +2 ledge")
	check(int(rd["frames"]) > 0 and int(rl["frames"]) > 0, "both were climbing at some point")
	check(float(rl["speed"]) > float(rd["speed"]) * 1.8, "Larkin climbs much faster (%.2f vs %.2f u/s)" % [float(rl["speed"]), float(rd["speed"])])
	near(float(rl["speed"]), 4.5 * 0.6, 0.35, "Larkin climbs at 0.6 x walking speed")
	near(float(rd["speed"]), 4.5 * 0.25, 0.3, "Dagna climbs at 0.25 x walking speed")
	check(int(rl["frames"]) < int(rd["frames"]), "so Larkin spends fewer frames on the climb (%d vs %d)" % [int(rl["frames"]), int(rd["frames"])])
	near(larkin.climb_speed_factor, 0.6, 0.0001, "Larkin climb factor")
	near(float(HeroKit.DATA["dagna"]["climb_speed_factor"]), 0.25, 0.0001, "Dagna climb factor")
	near(Actor.CLIMB_SPEED_FACTOR, 0.35, 0.0001, "default climb factor unchanged")

	# A +3 ledge is still a wall for everyone.
	_fresh(_row_map([0, 0, 3, 3, 3]))
	larkin = _kit_hero("larkin")
	r = await _walk_row(larkin, 4.0)
	check(r["x"] < Hex.to_world(Vector2i(2, 0)).x, "a +3 ledge still blocks Larkin")


# --- Shove multipliers -----------------------------------------------------------------------

func _test_shove_mult() -> void:
	_fresh()
	var larkin := _kit_hero("larkin", Vector2i(-6, 0))
	var dagna := _kit_hero("dagna", Vector2i(0, -4))
	var pebble := _kit_hero("pebble", Vector2i(6, 0))
	near(larkin.shove_mult, 1.3, 0.0001, "Larkin is light: shove_mult 1.3")
	near(dagna.shove_mult, 0.6, 0.0001, "Dagna is stout: shove_mult 0.6")
	near(pebble.shove_mult, 0.0, 0.0001, "Pebble is immovable: shove_mult 0")
	var starts := {}
	for h in [larkin, dagna, pebble]:
		starts[h] = h.global_position
		h.shove(Vector3.RIGHT, 2.0)
	await frames(60)
	near(larkin.global_position.distance_to(starts[larkin]), 2.6, 0.2, "Larkin is shoved 1.3x")
	near(dagna.global_position.distance_to(starts[dagna]), 1.2, 0.2, "Dagna is shoved 0.6x")
	near(pebble.global_position.distance_to(starts[pebble]), 0.0, 0.0001, "Pebble does not move")


# --- Kits survive without models (--proto-heroes) and with them ------------------------------

func _kit_signature(h: Hero) -> Array:
	return [h.max_hp, h.melee_damage, h.melee_cooldown, h.melee_reach, h.melee_arc, h.melee_shove, h.secondary_kind,
			h.shove_mult, h.can_climb, h.climb_speed_factor, h.arrow_tap_damage, h.arrow_draw_damage, h.arrow_draw_pierce]


func _test_proto_and_models() -> void:
	_fresh()
	var models := {"larkin": LarkinModel.new(), "dagna": DagnaModel.new(), "pebble": PebbleModel.new()}
	var n := 0
	for id: String in ["larkin", "dagna", "pebble"]:
		var proto := _kit_hero(id, Vector2i(-4 + n, 2), null)
		var faceted := _kit_hero(id, Vector2i(-4 + n, -2), models[id])
		check(proto.visual_override == null, "%s --proto-heroes: no model" % id)
		check(faceted.visual_override != null, "%s faceted: model" % id)
		eq(_kit_signature(proto), _kit_signature(faceted), "%s kit is the same with and without a model" % id)
		n += 2
	# Every model has the hooks the kits drive.
	for id: String in models:
		check(models[id].has_method("attack_swing"), "%s model has attack_swing" % id)
	check(models["larkin"].has_method("draw_hold"), "Larkin's model can draw")
	check(models["dagna"].has_method("spin"), "Dagna's model spins")
	check(models["pebble"].has_method("bowl_pose"), "Pebble's model bowls")
	# The proto Larkin still draws, shoots and shows the ring; the proto bodies still swing.
	_fresh()
	var larkin := _kit_hero("larkin", Vector2i(-8, 0), null)
	var d := _dummy(larkin.global_position + Vector3(4, 0, 0))
	larkin.start_draw()
	await frames(50)
	check(larkin._charge_ring != null and larkin._charge_ring.visible, "proto Larkin shows the charge ring")
	check(larkin.release_draw(Vector3.RIGHT), "proto Larkin releases a drawn shot")
	await frames(30)
	near(d.hp, d.max_hp - 28.0, 0.001, "proto Larkin's drawn shot does 28")
	var pebble := _kit_hero("pebble", Vector2i(2, 0), null)
	var d2 := _dummy(pebble.global_position + Vector3(1.6, 0, 0))
	check(pebble.melee(Vector3.RIGHT), "proto Pebble punches")
	near(d2.hp, d2.max_hp - 26.0, 0.001, "for 26")


# --- HUD bars use the hero's own max HP ------------------------------------------------------

func _test_hud_bars() -> void:
	_fresh()
	var pebble := _kit_hero("pebble", Vector2i(0, 0))
	var larkin := _kit_hero("larkin", Vector2i(1, 0))
	var dagna := _kit_hero("dagna", Vector2i(-1, 0))
	var hud := Hud.new()
	add_child(hud)
	var allies: Array[Hero] = [larkin, dagna]
	hud.bind(pebble, allies)
	pebble.apply_damage(40.0)
	larkin.apply_damage(17.0)
	dagna.apply_damage(30.0)
	await frames(3)
	near(hud._player_bar.value, 120.0 / 160.0, 0.001, "player bar uses Pebble's 160 max HP")
	eq(hud._player_bar.text, "120 / 160", "player bar text")
	near(hud._ally_bars[0].value, 68.0 / 85.0, 0.001, "ally bar uses Larkin's 85 max HP")
	eq(hud._ally_bars[0].text, "68 / 85", "ally bar text")
	near(hud._ally_bars[1].value, 90.0 / 120.0, 0.001, "ally bar uses Dagna's 120 max HP")
	hud.queue_free()


# --- AllyBrain melee uses the hero's own primary ---------------------------------------------

func _test_ally_primaries() -> void:
	var cases := {"dagna": 28.0, "pebble": 26.0}
	for id: String in cases:
		_fresh()
		var leader := Hero.new()
		GameWorld.spawn(leader, Vector3(0, 0, -2))
		leader.snap_to_ground()
		var ally := _kit_hero(id, Vector2i.ZERO)
		HeroFactory.make_ally(ally, leader, false, 2.4)
		ally._ready_at[Hero.KEY_RANGED] = GameWorld.time + 1000.0   # no secondary: melee only
		var dummy := _dummy(Vector3(2.0, 0, -1.0))
		var swings := [0]
		ally.melee_swung.connect(func() -> void: swings[0] += 1)
		await frames(60 * 4)
		var lost := dummy.max_hp - dummy.hp
		check(swings[0] >= 3, "%s's ally brain swings its primary (%d swings)" % [id, swings[0]])
		near(lost, float(cases[id]) * swings[0], 0.001, "%s ally melee does %.0f per swing (lost %.0f over %d swings)" % [id, cases[id], lost, swings[0]])
		# Swing rate follows the kit's cooldown: ~4 s of fighting, minus the walk-in.
		var cd: float = ally.melee_cooldown
		check(swings[0] <= int(4.0 / cd) + 1, "%s cannot swing faster than its cooldown" % id)
