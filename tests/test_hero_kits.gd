extends TestCase
## Per-hero kits (HeroKit): HP, primary (damage / reach / arc / cooldown / shove), Wick's tap vs
## drawn arrow, releasing early, climb rules (Rebar cannot climb +2, Wick is faster than Gasket),
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
	var wick := _kit_hero("wick")
	var gasket := _kit_hero("gasket")
	var rebar := _kit_hero("rebar")
	near(wick.max_hp, 85.0, 0.001, "Wick HP")
	near(gasket.max_hp, 120.0, 0.001, "Gasket HP")
	near(rebar.max_hp, 160.0, 0.001, "Rebar HP")
	near(wick.hp, 85.0, 0.001, "Wick starts at full HP")
	near(rebar.hp, 160.0, 0.001, "Rebar starts at full HP")
	eq(wick.secondary_kind, "arrow", "Wick's secondary")
	eq(gasket.secondary_kind, "spin", "Gasket's secondary")
	eq(rebar.secondary_kind, "bowl", "Rebar's secondary")
	eq(wick.kit_id, "wick", "kit id recorded")
	check(HeroKit.get_kit("Gasket") != null, "kits are looked up case-insensitively")
	check(HeroKit.get_kit("rattles") == null, "dropped heroes have no kit")
	check(not HeroKit.apply_to(wick, "nobody"), "an unknown kit is a no-op")
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
		"wick": {"dmg": 12.0, "cd": 0.4, "reach": 1.3, "arc": 90.0, "shove": 0.7},
		"gasket": {"dmg": 28.0, "cd": 0.65, "reach": 1.5, "arc": 90.0, "shove": 0.9},
		"rebar": {"dmg": 15.0, "cd": 0.8, "reach": 1.8, "arc": 120.0, "shove": 1.6},
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
	# The three feel different: Gasket hits hardest, Rebar reaches farthest and shoves hardest, Wick is quickest.
	check(HeroKit.DATA["gasket"]["melee_damage"] > HeroKit.DATA["rebar"]["melee_damage"] and HeroKit.DATA["rebar"]["melee_damage"] > HeroKit.DATA["wick"]["melee_damage"], "damage order Gasket > Rebar > Wick")
	check(HeroKit.DATA["rebar"]["melee_shove"] > HeroKit.DATA["gasket"]["melee_shove"], "Rebar shoves hardest")
	check(HeroKit.DATA["wick"]["melee_cooldown"] < HeroKit.DATA["gasket"]["melee_cooldown"], "Wick swings faster than Gasket")
	check(HeroKit.DATA["gasket"]["melee_cooldown"] < HeroKit.DATA["rebar"]["melee_cooldown"], "Gasket swings faster than Rebar")


# --- Wick's arrow --------------------------------------------------------------------------

func _line(origin: Vector3, xs: Array) -> Array[TrainingDummy]:
	var out: Array[TrainingDummy] = []
	for x: float in xs:
		out.append(_dummy(origin + Vector3(x, 0, 0)))
	return out


func _test_arrow() -> void:
	# Tap: 12 dmg, hits only the first target in line, 0.55 s cooldown.
	_fresh()
	var wick := _kit_hero("wick", Vector2i(-8, 0))
	var o := wick.global_position
	var line := _line(o, [3.0, 5.0, 7.0, 9.0])
	check(wick.shoot(Vector3.RIGHT), "RMB tap (shoot) fires an arrow")
	near(wick.cooldown_left(Hero.KEY_RANGED), 0.55, 0.02, "tap cooldown 0.55 s")
	check(not wick.shoot(Vector3.RIGHT), "tap cooldown blocks")
	await frames(40)
	near(line[0].hp, line[0].max_hp - 12.0, 0.001, "tap does 12")
	near(line[1].hp, line[1].max_hp, 0.001, "a tap shot does not pierce")
	near(line[2].hp, line[2].max_hp, 0.001, "a tap shot does not pierce (3rd)")

	# Drawn: hold 0.7 s, then 28 damage pierces up to 3 targets.
	await frames(10)   # cooldown over
	check(wick.start_draw(), "the bow can be drawn")
	check(wick.is_drawing(), "drawing")
	near(wick.draw_progress(), 0.0, 0.1, "draw starts at 0")
	await frames(21)
	var mid := wick.draw_progress()
	check(mid > 0.3 and mid < 0.6, "draw is half-way after ~0.35 s (%.2f)" % mid)
	await frames(30)
	near(wick.draw_progress(), 1.0, 0.0001, "fully drawn after 0.7 s")
	check(wick.release_draw(Vector3.RIGHT), "releasing a full draw fires")
	check(not wick.is_drawing(), "no longer drawing")
	near(wick.cooldown_left(Hero.KEY_RANGED), 0.55, 0.02, "the drawn shot costs the same recovery")
	await frames(45)
	near(line[0].hp, line[0].max_hp - 12.0 - 28.0, 0.001, "drawn shot: 28 to the 1st")
	near(line[1].hp, line[1].max_hp - 28.0, 0.001, "drawn shot: 28 to the 2nd (pierce)")
	near(line[2].hp, line[2].max_hp - 28.0, 0.001, "drawn shot: 28 to the 3rd (pierce)")
	near(line[3].hp, line[3].max_hp, 0.001, "pierce stops after 3 targets")

	# Releasing early = a tap shot (12, no pierce), even after holding most of the draw.
	_fresh()
	wick = _kit_hero("wick", Vector2i(-8, 0))
	o = wick.global_position
	line = _line(o, [3.0, 5.0, 7.0])
	check(wick.start_draw(), "draw for an early release")
	await frames(30)    # 0.5 s of 0.7 s
	check(wick.draw_progress() < 1.0, "not a full draw yet")
	check(wick.release_draw(Vector3.RIGHT), "early release fires")
	await frames(40)
	near(line[0].hp, line[0].max_hp - 12.0, 0.001, "early release is a 12 damage tap")
	near(line[1].hp, line[1].max_hp, 0.001, "and does not pierce")
	check(not wick.release_draw(Vector3.RIGHT), "nothing to release when not drawing")

	# Cancelling (the melee bash lowers the bow) fires nothing; the bow cannot be drawn during recovery.
	await frames(40)
	check(wick.start_draw(), "draw again")
	check(wick.melee(Vector3.RIGHT), "melee while drawing")
	check(not wick.is_drawing(), "the bash lowers the bow")
	_fresh()
	wick = _kit_hero("wick", Vector2i(-8, 0))
	wick.shoot(Vector3.RIGHT)
	check(not wick.start_draw(), "no drawing while the last shot recovers")
	var plain := Hero.new()
	GameWorld.spawn(plain, Vector3(0, 0, 4))
	check(not plain.start_draw(), "a bolt hero cannot draw")

	# Range: tap 14, drawn 18 (measured from the hero).
	_fresh()
	wick = _kit_hero("wick", Vector2i(-12, 0))
	o = wick.global_position
	var near_t := _dummy(o + Vector3(13.0, 0, 0))     # inside the tap range
	check(wick.shoot(Vector3.RIGHT), "tap at long range")
	await frames(75)
	near(near_t.hp, near_t.max_hp - 12.0, 0.001, "a tap reaches 13")
	_fresh()
	wick = _kit_hero("wick", Vector2i(-12, 0))
	o = wick.global_position
	var beyond_tap := _dummy(o + Vector3(16.5, 0, 0))
	wick.shoot(Vector3.RIGHT)
	await frames(90)
	near(beyond_tap.hp, beyond_tap.max_hp, 0.001, "a tap does not reach 16.5 (range 14)")
	_fresh()
	wick = _kit_hero("wick", Vector2i(-12, 0))
	o = wick.global_position
	var in_draw := _dummy(o + Vector3(17.0, 0, 0))
	var past_draw := _dummy(o + Vector3(21.5, 0, 0.2))
	wick.start_draw()
	await frames(46)
	wick.release_draw(Vector3.RIGHT)
	await frames(100)
	near(in_draw.hp, in_draw.max_hp - 28.0, 0.001, "a drawn shot reaches 17 (range 18)")
	near(past_draw.hp, past_draw.max_hp, 0.001, "a drawn shot stops before 21.5")

	# Stats from the kit.
	near(wick.arrow_tap_damage, 12.0, 0.001, "tap damage field")
	near(wick.arrow_draw_damage, 28.0, 0.001, "drawn damage field")
	eq(wick.arrow_draw_pierce, 3, "drawn pierce field")
	near(wick.arrow_tap_range, 14.0, 0.001, "tap range field")
	near(wick.arrow_draw_range, 18.0, 0.001, "drawn range field")
	near(wick.arrow_draw_time, 0.7, 0.001, "draw time field")

	# Walking while drawing is half speed; the charge ring and the model's bow follow the draw.
	_fresh()
	var model := WickModel.new()
	wick = _kit_hero("wick", Vector2i(-8, 0), model)
	var x0 := wick.global_position.x
	for i in 60:
		wick.move(Vector3.RIGHT, 1.0 / 60.0)
		await get_tree().physics_frame
	var free_run := wick.global_position.x - x0
	wick.start_draw()
	var x1 := wick.global_position.x
	for i in 30:
		wick.move(Vector3.RIGHT, 1.0 / 60.0)
		await get_tree().physics_frame
	var drawn_run := wick.global_position.x - x1
	near(drawn_run, free_run * 0.5 * 0.5, 0.2, "drawing halves walking speed (%.2f vs free %.2f for half the time)" % [drawn_run, free_run])
	near(wick.move_speed, 4.5, 0.0001, "move_speed is restored after the drawn step")
	check(wick._charge_ring != null and wick._charge_ring.visible, "a charge ring shows while drawing")
	var s0 := wick._charge_ring.scale.x
	await frames(15)
	check(wick._charge_ring.scale.x > s0, "the ring grows as the bow is drawn (%.2f -> %.2f)" % [s0, wick._charge_ring.scale.x])
	check(model.arm_kick("draw") > 0.5, "the model's bow is drawn (draw_hold %.2f)" % model.arm_kick("draw"))
	await frames(30)
	near(wick._charge_ring.scale.x, 1.0, 0.15, "full ring at a full draw")
	wick.release_draw(Vector3.RIGHT)
	await frames(2)
	check(not wick._charge_ring.visible, "the ring hides on release")
	# Getting shoved lowers the bow.
	await frames(60)
	wick.start_draw()
	wick.shove(Vector3.RIGHT, 1.0)
	await frames(2)
	check(not wick.is_drawing(), "a shove lowers the bow")


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
	# +1 steps are walked by everyone, Rebar included.
	_fresh(_row_map([0, 0, 1, 1, 1, 1, 1, 1]))
	var rebar := _kit_hero("rebar")
	var r := await _walk_row(rebar, 3.0)
	check(r["x"] > Hex.to_world(Vector2i(3, 0)).x, "Rebar walks up a +1 step (x=%.2f)" % float(r["x"]))
	eq(int(r["frames"]), 0, "and never climbs for it")

	# A +2 ledge: Rebar cannot get up; Gasket and Wick can, Wick faster.
	var ledge := [0, 0, 2, 2, 2, 2, 2, 2, 2, 2]
	_fresh(_row_map(ledge))
	rebar = _kit_hero("rebar")
	check(not rebar.can_climb, "Rebar: can_climb false")
	r = await _walk_row(rebar, 6.0)
	check(r["x"] < Hex.to_world(Vector2i(2, 0)).x, "Rebar is stopped by a +2 ledge (x=%.2f)" % float(r["x"]))
	eq(int(r["frames"]), 0, "Rebar never enters the climbing state")
	near(rebar.global_position.y, 0.0, 0.05, "and stays on the low floor")
	# He also refuses to path over it.
	check(GameWorld.map.find_path(Vector2i(0, 0), Vector2i(5, 0), rebar.can_climb).is_empty(), "no climbing path for Rebar")

	_fresh(_row_map(ledge))
	var gasket := _kit_hero("gasket")
	near(gasket.climb_speed_factor, 0.25, 0.0001, "Gasket climb factor on the hero")
	var rd := await _walk_row(gasket, 10.0)
	_fresh(_row_map(ledge))
	var wick := _kit_hero("wick")
	var rl := await _walk_row(wick, 10.0)
	check(rd["x"] > Hex.to_world(Vector2i(3, 0)).x, "Gasket gets over a +2 ledge (x=%.2f)" % float(rd["x"]))
	check(rl["x"] > Hex.to_world(Vector2i(3, 0)).x, "Wick gets over a +2 ledge")
	check(int(rd["frames"]) > 0 and int(rl["frames"]) > 0, "both were climbing at some point")
	check(float(rl["speed"]) > float(rd["speed"]) * 1.8, "Wick climbs much faster (%.2f vs %.2f u/s)" % [float(rl["speed"]), float(rd["speed"])])
	near(float(rl["speed"]), 4.5 * 0.6, 0.35, "Wick climbs at 0.6 x walking speed")
	near(float(rd["speed"]), 4.5 * 0.25, 0.3, "Gasket climbs at 0.25 x walking speed")
	check(int(rl["frames"]) < int(rd["frames"]), "so Wick spends fewer frames on the climb (%d vs %d)" % [int(rl["frames"]), int(rd["frames"])])
	near(wick.climb_speed_factor, 0.6, 0.0001, "Wick climb factor")
	near(float(HeroKit.DATA["gasket"]["climb_speed_factor"]), 0.25, 0.0001, "Gasket climb factor")
	near(Actor.CLIMB_SPEED_FACTOR, 0.35, 0.0001, "default climb factor unchanged")

	# A +3 ledge is still a wall for everyone.
	_fresh(_row_map([0, 0, 3, 3, 3]))
	wick = _kit_hero("wick")
	r = await _walk_row(wick, 4.0)
	check(r["x"] < Hex.to_world(Vector2i(2, 0)).x, "a +3 ledge still blocks Wick")


# --- Shove multipliers -----------------------------------------------------------------------

func _test_shove_mult() -> void:
	_fresh()
	var wick := _kit_hero("wick", Vector2i(-6, 0))
	var gasket := _kit_hero("gasket", Vector2i(0, -4))
	var rebar := _kit_hero("rebar", Vector2i(6, 0))
	near(wick.shove_mult, 1.3, 0.0001, "Wick is light: shove_mult 1.3")
	near(gasket.shove_mult, 0.6, 0.0001, "Gasket is stout: shove_mult 0.6")
	near(rebar.shove_mult, 0.0, 0.0001, "Rebar is immovable: shove_mult 0")
	var starts := {}
	for h in [wick, gasket, rebar]:
		starts[h] = h.global_position
		h.shove(Vector3.RIGHT, 2.0)
	await frames(60)
	near(wick.global_position.distance_to(starts[wick]), 2.6, 0.2, "Wick is shoved 1.3x")
	near(gasket.global_position.distance_to(starts[gasket]), 1.2, 0.2, "Gasket is shoved 0.6x")
	near(rebar.global_position.distance_to(starts[rebar]), 0.0, 0.0001, "Rebar does not move")


# --- Kits survive without models (--proto-heroes) and with them ------------------------------

func _kit_signature(h: Hero) -> Array:
	return [h.max_hp, h.melee_damage, h.melee_cooldown, h.melee_reach, h.melee_arc, h.melee_shove, h.secondary_kind,
			h.shove_mult, h.can_climb, h.climb_speed_factor, h.arrow_tap_damage, h.arrow_draw_damage, h.arrow_draw_pierce]


func _test_proto_and_models() -> void:
	_fresh()
	var models := {"wick": WickModel.new(), "gasket": GasketModel.new(), "rebar": RebarModel.new()}
	var n := 0
	for id: String in ["wick", "gasket", "rebar"]:
		var proto := _kit_hero(id, Vector2i(-4 + n, 2), null)
		var faceted := _kit_hero(id, Vector2i(-4 + n, -2), models[id])
		check(proto.visual_override == null, "%s --proto-heroes: no model" % id)
		check(faceted.visual_override != null, "%s faceted: model" % id)
		eq(_kit_signature(proto), _kit_signature(faceted), "%s kit is the same with and without a model" % id)
		n += 2
	# Every model has the hooks the kits drive.
	for id: String in models:
		check(models[id].has_method("attack_swing"), "%s model has attack_swing" % id)
	check(models["wick"].has_method("draw_hold"), "Wick's model can draw")
	check(models["gasket"].has_method("spin"), "Gasket's model spins")
	check(models["rebar"].has_method("bowl_pose"), "Rebar's model bowls")
	# The proto Wick still draws, shoots and shows the ring; the proto bodies still swing.
	_fresh()
	var wick := _kit_hero("wick", Vector2i(-8, 0), null)
	var d := _dummy(wick.global_position + Vector3(4, 0, 0))
	wick.start_draw()
	await frames(50)
	check(wick._charge_ring != null and wick._charge_ring.visible, "proto Wick shows the charge ring")
	check(wick.release_draw(Vector3.RIGHT), "proto Wick releases a drawn shot")
	await frames(30)
	near(d.hp, d.max_hp - 28.0, 0.001, "proto Wick's drawn shot does 28")
	var rebar := _kit_hero("rebar", Vector2i(2, 0), null)
	var d2 := _dummy(rebar.global_position + Vector3(1.6, 0, 0))
	check(rebar.melee(Vector3.RIGHT), "proto Rebar punches")
	near(d2.hp, d2.max_hp - 15.0, 0.001, "for 15")


# --- HUD bars use the hero's own max HP ------------------------------------------------------

func _test_hud_bars() -> void:
	_fresh()
	var rebar := _kit_hero("rebar", Vector2i(0, 0))
	var wick := _kit_hero("wick", Vector2i(1, 0))
	var gasket := _kit_hero("gasket", Vector2i(-1, 0))
	var hud := Hud.new()
	add_child(hud)
	var allies: Array[Hero] = [wick, gasket]
	hud.bind(rebar, allies)
	rebar.apply_damage(40.0)
	wick.apply_damage(17.0)
	gasket.apply_damage(30.0)
	await frames(3)
	if hud.party != null:   # the party frame (Hud.PARTY_LOOK clean / paper): each row reads its hero's own max HP
		var v: Array[Dictionary] = hud.party.views
		near(float(v[0]["hp"]) / float(v[0]["max_hp"]), 120.0 / 160.0, 0.001, "your row uses Rebar's 160 max HP")
		near(float(v[1]["hp"]) / float(v[1]["max_hp"]), 68.0 / 85.0, 0.001, "Wick's row uses his 85 max HP")
		near(float(v[2]["hp"]) / float(v[2]["max_hp"]), 90.0 / 120.0, 0.001, "Gasket's row uses her 120 max HP")
	else:
		near(hud._player_bar.value, 120.0 / 160.0, 0.001, "player bar uses Rebar's 160 max HP")
		eq(hud._player_bar.text, "120 / 160", "player bar text")
		near(hud._ally_bars[0].value, 68.0 / 85.0, 0.001, "ally bar uses Wick's 85 max HP")
		eq(hud._ally_bars[0].text, "68 / 85", "ally bar text")
		near(hud._ally_bars[1].value, 90.0 / 120.0, 0.001, "ally bar uses Gasket's 120 max HP")
	hud.queue_free()


# --- AllyBrain melee uses the hero's own primary ---------------------------------------------

func _test_ally_primaries() -> void:
	var cases := {"gasket": 28.0, "rebar": 15.0}
	AllyBrain.restraint = false   # (the eager AI: an idle dummy is fair game; this is about the kit, test_ally_orders the restraint)
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
	AllyBrain.restraint = true
