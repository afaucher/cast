extends TestCase
## The 3D garage backdrop (scripts/ui/menu_backdrop.gd), behind the main menu and the job board: it builds in every
## mood (dawn / night / after), switches mood at runtime without leaking nodes, picks its mood from the dev flag,
## the last contract and the clock, features the player's hero, stays at about six lights, and costs next to nothing
## per frame (no allocations). Screens that use it are covered by test_main_menu and test_forms.

const LIGHT_BUDGET := 8                ## positional lights a backdrop may switch on ("about six" plus the van's and the gate's)
const FRAME_BUDGET_US := 3000.0        ## script cost of one backdrop _process, microseconds (it is a few vector ops)


func setup() -> void:
	timeout_sec = 150.0
	LastContract.clear()
	_check_mood_logic()
	await _check_garage_moods()
	await _check_garage_switching()
	await _check_garage_hero()
	await _check_garage_cost()
	LastContract.clear()
	finish()


# --- Mood selection -------------------------------------------------------------------------------------

func _check_mood_logic() -> void:
	LastContract.clear()
	var none := PackedStringArray([])
	eq(MenuBackdrop.pick_mood(none, 12), "dawn", "midday is dawn")
	eq(MenuBackdrop.pick_mood(none, 20), "night", "20:00 is night")
	eq(MenuBackdrop.pick_mood(none, 23), "night", "23:00 is night")
	eq(MenuBackdrop.pick_mood(none, 3), "night", "03:00 is night")
	eq(MenuBackdrop.pick_mood(none, 4), "night", "04:59 is still night")
	eq(MenuBackdrop.pick_mood(none, 5), "dawn", "05:00 is dawn")
	eq(MenuBackdrop.pick_mood(none, 19), "dawn", "19:00 is dawn")
	for m in MenuBackdrop.MOODS:
		eq(MenuBackdrop.pick_mood(PackedStringArray(["--backdrop-mood", m]), 12 if m != "dawn" else 23), m, "--backdrop-mood %s wins over the clock" % m)
	eq(MenuBackdrop.pick_mood(PackedStringArray(["--backdrop-mood", "bogus"]), 12), "dawn", "an unknown flag value is ignored")
	eq(MenuBackdrop.pick_mood(PackedStringArray(["--backdrop-mood"]), 12), "dawn", "a flag without a value is ignored")
	# the last contract
	var run := ContractBoard.run_for_seed(5)
	check(not LastContract.was_bad(), "nothing recorded: not bad")
	LastContract.record({"damages": 100, "contract_value": run.contract_value, "reason": ContractSession.END_CASHED_OUT})
	check(not LastContract.was_bad(), "a little damage is a good job")
	eq(MenuBackdrop.pick_mood(none, 12), "dawn", "a good job leaves the morning alone")
	LastContract.record({"damages": int(run.contract_value * LastContract.AFTER_DAMAGE_RATIO), "contract_value": run.contract_value, "reason": ContractSession.END_CASHED_OUT})
	check(LastContract.was_bad(), "damages at the threshold are a bad job")
	eq(MenuBackdrop.pick_mood(none, 12), "after", "after a bad job: the mess")
	eq(MenuBackdrop.pick_mood(none, 23), "after", "the mess beats the night")
	eq(MenuBackdrop.pick_mood(PackedStringArray(["--backdrop-mood", "night"]), 12), "night", "the flag beats the mess")
	LastContract.record({"damages": 0, "contract_value": run.contract_value, "reason": ContractSession.END_INCAPACITATED})
	check(LastContract.was_bad(), "an incapacitated crew is a bad job")
	LastContract.clear()
	check(not LastContract.was_bad(), "cleared")


# --- The garage -----------------------------------------------------------------------------------------

func _garage(mood: String) -> MenuBackdrop:
	var g := MenuBackdrop.new()
	g.mood = mood
	add_child(g)
	return g


func _check_garage_moods() -> void:
	for m in MenuBackdrop.MOODS:
		var g := _garage(m)
		await frames(3)
		eq(g.mood, m, "%s: the mood sticks" % m)
		check(g.camera != null and g.camera.current, "%s: a camera is current" % m)
		check(g.camera.h_offset < 0.0, "%s: the frame is slid right of the left-third menu" % m)
		check(g.wick is WickModel and g.rebar is RebarModel and g.gasket is GasketModel, "%s: the crew is there" % m)
		check(g.gate is HellgateModel, "%s: the hellgate glows" % m)
		check(g.van is VanModel, "%s: the real van is parked" % m)
		near(g.van.door_open_amount(), 1.0, 0.001, "%s: the side door is open" % m)
		near(g.van.lights_amount(), 1.0 if m == "night" else 0.0, 0.001, "%s: headlights only at night" % m)
		check(g.map.cells.size() > 100, "%s: a floor (%d cells)" % [m, g.map.cells.size()])
		check(g.terrain.seam_gain < 1.0 and g.terrain.seam_near_gain < 1.0, "%s: the hex seams are turned down" % m)
		var lights := g.light_count()
		check(lights >= 3 and lights <= LIGHT_BUDGET, "%s: about six lights (%d)" % [m, lights])
		var env := g.environment
		check(env != null, "%s: an environment" % m)
		if env != null:
			match m:
				"night":
					check(env.adjustment_brightness < 1.0 and env.adjustment_color_correction != null, "night is graded (brightness + tone curve), not just fewer lights")
				"after":
					check(env.adjustment_saturation < 1.0, "after is desaturated")
				_:
					check(env.adjustment_color_correction == null, "dawn is the plain look")
		var mood_root := g.get_node_or_null("Mood")
		check(mood_root != null, "%s: the mood node exists" % m)
		check((mood_root != null and mood_root.get_node_or_null("Smoke") != null) == (m == "after"), "%s: smoke only after a bad job" % m)
		check((mood_root != null and mood_root.get_node_or_null("AfterMess") != null) == (m == "after"), "%s: corn and scorch only after a bad job" % m)
		check(mood_root != null and mood_root.find_children("*", "SpotLight3D", true, false).size() == (0 if m == "night" else 1), "%s: the grate spot is a daytime thing" % m)
		# the corn sign
		check(g.corn_days == 0, "the corn counter reads 0")
		var found_sign := false
		for l in g.find_children("*", "Label3D", true, false):
			if (l as Label3D).text.begins_with("DAYS SINCE LAST"):
				found_sign = true
				check((l as Label3D).text.ends_with("0"), "the corn sign says 0")
		check(found_sign, "the corn sign is on the wall")
		g.queue_free()
		await frames(2)
	# with no mood given the garage picks one from context, always a valid one
	var auto := MenuBackdrop.new()
	add_child(auto)
	await frames(2)
	check(MenuBackdrop.MOODS.has(auto.mood), "an unset mood is resolved (%s)" % auto.mood)
	auto.queue_free()
	await frames(2)


func _check_garage_switching() -> void:
	var g := _garage("dawn")
	await frames(2)
	var children := g.get_child_count()
	for m in ["night", "after", "dawn", "after", "night", "dawn"]:
		g.set_mood(m)
		eq(g.mood, m, "set_mood(%s)" % m)
		near(g.van.lights_amount(), 1.0 if m == "night" else 0.0, 0.001, "headlights follow the mood (%s)" % m)
		check(g.light_count() <= LIGHT_BUDGET, "lights stay in budget after switching to %s (%d)" % [m, g.light_count()])
	eq(g.get_child_count(), children, "switching moods rebuilds, it does not pile up nodes")
	g.set_mood("bogus")
	eq(g.mood, "dawn", "an unknown mood is refused")
	g.corn_days = 3
	for l in g.find_children("*", "Label3D", true, false):
		if (l as Label3D).text.begins_with("DAYS SINCE LAST"):
			check((l as Label3D).text.ends_with("3"), "the corn counter is wired to the sign")
	g.queue_free()
	await frames(2)


func _check_garage_hero() -> void:
	eq(MenuBackdrop.hero_from_args(PackedStringArray([])), MenuBackdrop.PLAYER_HERO, "the featured hero defaults to the player's hero")
	eq(MenuBackdrop.hero_from_args(PackedStringArray(["--backdrop-hero", "rebar"])), "rebar", "--backdrop-hero picks the hero")
	eq(MenuBackdrop.hero_from_args(PackedStringArray(["--backdrop-hero", "bogus"])), MenuBackdrop.PLAYER_HERO, "an unknown hero is ignored")
	var g := _garage("dawn")
	await frames(2)
	eq(g.featured_hero, MenuBackdrop.PLAYER_HERO, "the garage features the player's hero")
	var children := g.get_child_count()
	var models := [g.wick, g.gasket, g.rebar]
	var cam := g.camera.global_position
	for id in MenuBackdrop.HEROES:
		g.set_featured_hero(id)
		eq(g.featured_hero, id, "featured: %s" % id)
		var front: Vector3 = g.hero_spot(id)
		for other in MenuBackdrop.HEROES:
			if other == id:
				continue
			var o: Vector3 = g.hero_spot(other)
			check(front.distance_to(cam) < o.distance_to(cam) - 1.0, "%s is nearer the camera than %s when featured" % [id, other])
			check(absf(front.x - o.x) > 1.0 or absf(front.z - o.z) > 1.0, "%s and %s do not stand on each other" % [id, other])
		# nobody stands in front of the open cargo door, and nobody in the clipboard's left third of the world
		for h in MenuBackdrop.HEROES:
			var p: Vector3 = g.hero_spot(h)
			var rel := p - MenuBackdrop.VAN_AT
			check(not (rel.x > -0.4 and rel.x < 1.8 and rel.z > 0.5), "%s keeps clear of the van's cargo door" % h)
	eq(g.get_child_count(), children, "swapping heroes re-poses, it does not rebuild")
	check(g.wick == models[0] and g.gasket == models[1] and g.rebar == models[2], "the same three models are re-used")
	g.set_featured_hero("bogus")
	eq(g.featured_hero, "rebar", "an unknown hero is refused")
	g.queue_free()
	await frames(2)


func _check_garage_cost() -> void:
	var g := _garage("dawn")
	await frames(3)
	check(MenuBackdrop.yaw_at(0.0) != MenuBackdrop.yaw_at(5.0), "the camera sways over time")
	var p0: Vector3 = g.camera.global_position
	await frames(60)
	check(g.camera.global_position.distance_to(p0) > 0.0005, "the camera drifts")
	# Script cost per frame, and nothing allocated: the object count is flat over 300 frames of _process.
	var before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var t0 := Time.get_ticks_usec()
	for _i in 300:
		g._process(1.0 / 60.0)
	var per_frame := float(Time.get_ticks_usec() - t0) / 300.0
	var after := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	check(per_frame < FRAME_BUDGET_US, "the garage's _process is cheap (%.1f us per frame)" % per_frame)
	eq(after, before, "no per-frame allocations (object count %d -> %d)" % [before, after])
	print("[backdrops] garage: %d lights, %.1f us of script per frame, object count %d -> %d" % [g.light_count(), per_frame, before, after])
	g.queue_free()
	await frames(2)
