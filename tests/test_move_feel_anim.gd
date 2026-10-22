extends TestCase
## The `grounded_anim` profile (MoveFeel, HeroFeel; docs/design/animation-research.md "As built"): grounded plus the
## animation track's treatment B and strike-first melee, measured through the real PlayerController and Hero:
##   - the lean leads the motion (forward on a start, back on a stop) and never passes LEAN_MAX (22 degrees); the squash
##     stays within SQUASH_MIN..SQUASH_MAX; the body layer sits between Hero._visual and the model;
##   - the stride holds still while the hero is shoved or airborne;
##   - strike first: the weapon's impact pose is shown on the frame the hit resolves (+-1), a connecting blow holds the
##     attacker's pose for about 3 frames (the hit-stop), a miss does not, and nothing about the hit's timing changes;
##   - the hit areas: each hero's grounded_anim area (the weapon's shape) against today's wedge, which grounded keeps;
##   - grounded and today are untouched (no body layer, the model's own swing, the kit's wedge);
##   - a puppet (a hero another machine moves) leans from its shown motion and plays a replayed swing strike-first;
##   - shuffle deals grounded and grounded_anim; today stays selectable by name;
##   - (every profile) the held spell component stays in the hero's hand and hand-sized through walk, swing and cast.
## It prints the measured numbers ([anim] lines) for the doc.

const DT := 1.0 / 60.0

var root: Node3D


func _row(levels: Array) -> HexMap:
	var m := HexMap.new()
	for i in levels.size():
		if levels[i] != null:
			for r in range(-3, 4):
				m.set_cell(Vector2i(i, r), int(levels[i]))
	return m


func _model(kit: String) -> LowPolyModel:
	match kit:
		"gasket":
			return GasketModel.new()
		"rebar":
			return RebarModel.new()
	return WickModel.new()


func _hero(map: HexMap, kit: String) -> Array:
	for c in root.get_children():
		c.free()
	var world := Node3D.new()
	root.add_child(world)
	GameWorld.begin(map, world, 99)
	var h := HeroFactory.spawn_hero(Vector2i(0, 0), "Walker", Color.BLUE, "sword", _model(kit), kit)
	var pc := HeroFactory.make_player(h, [] as Array[String])
	pc.aim_override = h.global_position + Vector3(6, 0, 0)
	return [h, pc]


func _dummy(pos: Vector3) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.max_hp = 100000.0
	d.shove_mult = 0.0
	GameWorld.spawn(d, pos)
	d.snap_to_ground()
	return d


func setup() -> void:
	timeout_sec = 150.0
	MoveFeel.reset()
	MoveFeel.set_mode(MoveFeel.GROUNDED_ANIM)
	root = Node3D.new()
	add_child(root)
	for kit in ["wick", "gasket", "rebar"]:
		await _lean(kit)
	await _held()
	for kit in ["wick", "gasket", "rebar"]:
		await _strike(kit)
	for prof: String in [MoveFeel.TODAY, MoveFeel.GROUNDED_ANIM]:
		MoveFeel.set_mode(prof)
		for kit in ["wick", "gasket", "rebar"]:
			await _no_clip(kit, prof)
	MoveFeel.set_mode(MoveFeel.GROUNDED_ANIM)
	await _areas()
	await _others()
	await _puppet()
	for prof: String in [MoveFeel.TODAY, MoveFeel.GROUNDED_ANIM]:
		MoveFeel.set_mode(prof)
		for kit in ["wick", "gasket", "rebar"]:
			await _held_prop(kit, prof)
	MoveFeel.set_mode(MoveFeel.GROUNDED_ANIM)
	_profiles()
	MoveFeel.reset()
	finish()


## Start, run, stop, reverse and strafe; the lean and the squash every rendered frame.
func _lean(kit: String) -> void:
	var hp: Array = _hero(_row([2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]), kit)
	var h: Hero = hp[0]
	var pc: PlayerController = hp[1]
	await frames(3)
	var fe := h._feel
	check(fe.active(), "%s: the body layer drives the model" % kit)
	check(h.visual_override.get_parent() == fe.pivot and fe.pivot.get_parent() == h._visual, "%s: between the Visual and the model" % kit)
	var most := 0.0
	var sq_lo := 0.0
	var sq_hi := 0.0
	var fwd := 0.0
	var back := 0.0
	var plan := [[Vector3.RIGHT, 40], [Vector3.ZERO, 40], [Vector3.RIGHT, 30], [Vector3.LEFT, 30], [Vector3(0, 0, 1), 30], [Vector3.ZERO, 40]]
	for step: Array in plan:
		for i in int(step[1]):
			pc.move_override = step[0]
			pc.aim_override = h.global_position + Vector3(6, 0, 0)
			await get_tree().process_frame
			most = maxf(most, fe.lean.length())
			var sy := fe.pivot.scale.y
			sq_lo = minf(sq_lo, 1.0 - sy)
			sq_hi = maxf(sq_hi, 1.0 - sy)
			if step == plan[0] and i < 20:
				fwd = minf(fwd, fe.lean.x)
			if step == plan[1] and i < 25:
				back = maxf(back, fe.lean.x)
	print("[anim] %s: lean up to %.1f deg (start %.1f forward, stop %.1f back), squash %+.2f..%+.2f" % [kit, rad_to_deg(most),
			rad_to_deg(-fwd), rad_to_deg(back), sq_lo, sq_hi])
	check(most <= HeroFeel.LEAN_MAX + 0.0001, "%s: the lean never passes 22 degrees (%.1f)" % [kit, rad_to_deg(most)])
	check(most > deg_to_rad(4.0), "%s: the body does lean (%.1f deg)" % [kit, rad_to_deg(most)])
	check(fwd < -deg_to_rad(2.0), "%s: a start leans forward (%.1f deg)" % [kit, rad_to_deg(-fwd)])
	check(back > deg_to_rad(1.0), "%s: a stop rocks back (%.1f deg)" % [kit, rad_to_deg(back)])
	check(sq_lo >= HeroFeel.SQUASH_MIN - 0.0001 and sq_hi <= HeroFeel.SQUASH_MAX + 0.0001, "%s: squash within -16%%..+20%% (%+.2f..%+.2f)" % [kit, sq_lo, sq_hi])
	check(sq_hi > 0.03 and sq_lo < -0.02, "%s: it does squash on a stop and stretch on a start" % kit)


## The stride holds while shoved and while airborne (a walked-off drop).
func _held() -> void:
	var hp: Array = _hero(_row([5, 5, 5, 5, 2, 2, 2, 2, 2, 2, 2, 2]), "wick")
	var h: Hero = hp[0]
	var pc: PlayerController = hp[1]
	await frames(3)
	for i in 5:
		pc.move_override = Vector3.RIGHT
		await get_tree().process_frame
	var g := h._gait.gait
	var moved_in_air := 0.0
	var air := 0
	var was_air := false
	for i in 150:
		pc.move_override = Vector3.RIGHT
		var t0 := g.t
		await get_tree().process_frame
		if not h._gait._grounded and was_air:
			air += 1
			moved_in_air += absf(g.t - t0)
		was_air = not h._gait._grounded
	check(air >= 5, "the drop is airborne for a while (%d frames)" % air)
	near(moved_in_air, 0.0, 0.0001, "the stride holds while airborne")
	for i in 20:
		pc.move_override = Vector3.LEFT
		await get_tree().process_frame
	h.shove(Vector3.RIGHT, 2.0, null)
	var shoved := 0
	var moved_shoved := 0.0
	for i in 20:
		pc.move_override = Vector3.ZERO
		var t0 := g.t
		await get_tree().process_frame
		if h.is_shoved() and i > 0:
			shoved += 1
			moved_shoved += absf(g.t - t0)
	check(shoved >= 5, "shoved for a while (%d frames)" % shoved)
	near(moved_shoved, 0.0, 0.0001, "the stride holds while shoved")
	print("[anim] stride held: %d airborne frames, %d shoved frames" % [air, shoved])


## Strike first: the impact pose on the damage frame, a hit-stop on contact, none on a miss.
func _strike(kit: String) -> void:
	var hp: Array = _hero(_row([2, 2, 2, 2, 2, 2, 2, 2]), kit)
	var h: Hero = hp[0]
	(hp[1] as PlayerController).queue_free()
	await frames(3)
	var fe := h._feel
	var d := _dummy(h.global_position + Vector3(1.2, 0, 0))
	var hit_frame := [-1]
	d.damaged.connect(func(_a: float, _s: Node) -> void: hit_frame[0] = Engine.get_process_frames())
	await get_tree().physics_frame
	var held0 := fe.held_frames
	check(h.melee(Vector3.RIGHT), "%s swings" % kit)
	await frames(1)
	check(hit_frame[0] >= 0, "%s: the blow lands" % kit)
	eq(fe.strikes, 1, "%s: the strike plays (HeroFeel)" % kit)
	check(absi(fe.impact_frame - hit_frame[0]) <= 1, "%s: the impact pose is shown on the damage frame +-1 (impact %d, damage %d)" % [kit, fe.impact_frame, hit_frame[0]])
	var key: String = {"wick": "bash", "gasket": "smash_a", "rebar": "slam_a"}[kit]
	var want: float = {"wick": -1.2, "gasket": GasketModel.SMASH_DOWN, "rebar": RebarModel.SLAM_DOWN}[kit]
	near(h.visual_override.arm_kick(key), want, 0.05, "%s: the weapon is at its impact on that frame" % kit)
	await frames(8)
	var held := fe.held_frames - held0
	var want_held := roundi(float(HeroFeel.TUNING[kit]["hitstop"]) * 60.0)
	check(absi(held - want_held) <= 1, "%s: a connecting blow holds the attacker's pose about %d frames (%d)" % [kit, want_held, held])
	eq(fe.smashes, 1 if kit == "gasket" else 0, "%s: %s" % [kit, "the smash marks its landing on the floor" if kit == "gasket" else "no smash mark"])
	print("[anim] %s strike: damage on frame %d, impact pose on frame %d, hit-stop %d frames" % [kit, hit_frame[0], fe.impact_frame, held])
	# a miss: no hit-stop; the cooldown is the kit's (strike first changes no timing)
	d.global_position = h.global_position + Vector3(-4, 0, 0)
	await frames(60)
	near(h.cooldown_left(Hero.KEY_MELEE), 0.0, 0.0001, "%s: the cooldown is over" % kit)
	await get_tree().physics_frame
	held0 = fe.held_frames
	check(h.melee(Vector3.RIGHT), "%s swings at nothing" % kit)
	near(h.cooldown_left(Hero.KEY_MELEE), h.melee_cooldown, 0.0001, "%s: the kit's cooldown, unchanged" % kit)
	await frames(10)
	eq(fe.held_frames - held0, 0, "%s: a miss has no hit-stop" % kit)


## No arm sinks into its own body (PoseClip) at any frame of a walk, a stop, two swings (the whole follow-through, with the
## lean, squash and lunge) and a cast. The user (2026-10-22), on Gasket's smash: "the arm penetrates the body and disappears".
func _no_clip(kit: String, prof: String) -> void:
	for style: String in [HeroFeel.FOLLOW, HeroFeel.WIND]:
		HeroFeel.style = style
		var hp: Array = _hero(_row([2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]), kit)
		var h: Hero = hp[0]
		var pc: PlayerController = hp[1]
		_dummy(h.global_position + Vector3(1.2, 0, 0))
		await frames(2)
		var m := h.visual_override as LowPolyModel
		var worst := 0.0
		var what := ""
		for i in 150:
			pc.move_override = Vector3.RIGHT if i < 30 else Vector3.ZERO
			if i == 40 or i == 95:
				h._ready_at.erase(Hero.KEY_MELEE)
				h.melee(Vector3.RIGHT)
			if i == 135:
				h._cast_pose()
			await get_tree().process_frame
			var d: Array = PoseClip.depth(m, kit)
			if float(d[0]) > worst:
				worst = float(d[0])
				what = "frame %d, %s" % [i, d[1]]
		check(worst <= 0.01, "%s %s (%s): no arm inside the body (deepest %.3f: %s)" % [kit, prof, style, worst, what])
		if kit != "gasket" and kit != "rebar":
			break
	HeroFeel.style = HeroFeel.FOLLOW


## The reshaped areas (grounded_anim) against today's wedge (grounded): a target each one hits and the other misses.
func _areas() -> void:
	# kit -> [[forward, side, hit under grounded, hit under grounded_anim], ...]
	var cases := {
		"wick": [[1.2, 0.0, true, true], [0.0, 1.2, false, false]],
		"gasket": [[2.25, 0.0, false, true], [1.0, 0.85, true, false], [0.8, 0.0, true, true], [1.95, 0.9, false, true], [3.1, 0.0, false, false]],
		"rebar": [[1.0, 1.5, true, false], [2.0, 0.0, true, true], [0.7, 0.0, true, true]],
	}
	for kit: String in cases:
		for c: Array in cases[kit]:
			for prof: String in [MoveFeel.GROUNDED, MoveFeel.GROUNDED_ANIM]:
				MoveFeel.set_mode(prof)
				var hp: Array = _hero(_row([2, 2, 2, 2, 2, 2, 2, 2]), kit)
				var h: Hero = hp[0]
				(hp[1] as PlayerController).queue_free()
				await frames(1)
				var d := _dummy(h.global_position + Vector3(float(c[0]), 0, float(c[1])))
				await get_tree().physics_frame
				h.melee(Vector3.RIGHT)
				var hit := d.hp < d.max_hp
				var want: bool = c[2] if prof == MoveFeel.GROUNDED else c[3]
				eq(hit, want, "%s %s: a target %.2f ahead, %.2f aside is %s" % [kit, prof, c[0], c[1], "hit" if want else "missed"])
	MoveFeel.set_mode(MoveFeel.GROUNDED_ANIM)
	for kit in ["wick", "gasket", "rebar"]:
		var hp: Array = _hero(_row([2, 2]), kit)
		print("[anim] %s area: %s" % [kit, str((hp[0] as Hero).melee_area())])


## grounded and today: no body layer, the model's own swing, the kit's wedge.
func _others() -> void:
	for prof: String in [MoveFeel.TODAY, MoveFeel.GROUNDED]:
		MoveFeel.set_mode(prof)
		var hp: Array = _hero(_row([2, 2, 2, 2, 2, 2]), "gasket")
		var h: Hero = hp[0]
		(hp[1] as PlayerController).queue_free()
		await frames(3)
		check(not h._feel.active() and h.visual_override.get_parent() == h._visual, "%s: no body layer" % prof)
		eq(h.melee_area(), {"shape": "arc", "reach": h.melee_reach, "arc": h.melee_arc}, "%s: the kit's own wedge" % prof)
		await get_tree().physics_frame
		h.melee(Vector3.RIGHT)
		await frames(4)
		eq(h._feel.strikes, 0, "%s: the model's own swing (no strike-first)" % prof)
		check(h.visual_override.arm_kick("weapon") > 0.2, "%s: Gasket winds up as before" % prof)
	# switching profiles hands the model back
	MoveFeel.set_mode(MoveFeel.GROUNDED_ANIM)
	var hp2: Array = _hero(_row([2, 2, 2, 2]), "rebar")
	var h2: Hero = hp2[0]
	await frames(3)
	check(h2._feel.active(), "grounded_anim: the layer is on")
	MoveFeel.set_mode(MoveFeel.GROUNDED)
	await frames(2)
	check(not h2._feel.active() and h2.visual_override.get_parent() == h2._visual, "F6 away: the model is back under the Visual")
	MoveFeel.set_mode(MoveFeel.GROUNDED_ANIM)


## A puppet: leans from the position the stream shows; a replayed swing plays strike-first.
func _puppet() -> void:
	var hp: Array = _hero(_row([2, 2, 2, 2, 2, 2, 2, 2, 2, 2]), "gasket")
	var h: Hero = hp[0]
	(hp[1] as PlayerController).queue_free()
	await frames(1)
	Net.make_puppet(h)
	h.facing = Vector3.RIGHT
	var most := 0.0
	for i in 40:
		h.global_position += Vector3(4.5 * DT, 0, 0)   # (a stream moves it)
		await get_tree().process_frame
		most = maxf(most, h._feel.lean.length())
	check(h._feel.active(), "a puppet gets the body layer")
	check(most > deg_to_rad(3.0), "a puppet leans from its shown motion (%.1f deg)" % rad_to_deg(most))
	h.net_act("melee", Vector3.RIGHT, false)
	await frames(1)
	eq(h._feel.strikes, 1, "a replayed swing plays strike-first on the puppet")
	eq(h._feel.smashes, 1, "a puppet Gasket's replayed smash marks its landing on this floor")
	Net.release_copy(h)


## The held spell component sits in the hand (a bug fix, every profile: it floated beside Gasket and Rebar, and above
## Wick's hand at torso size): within reach of the fist through standing, walking, a swing and a cast, and small.
func _held_prop(kit: String, prof: String) -> void:
	var hp: Array = _hero(_row([2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]), kit)
	var h: Hero = hp[0]
	var pc: PlayerController = hp[1]
	h.spell_slots = ["heal"] as Array[String]
	await frames(2)
	var m := h.visual_override as LowPolyModel
	var prop := m.held_item()
	check(prop != null, "%s %s holds the heal moss" % [kit, prof])
	if prop == null:
		return
	var far := 0.0
	var size := 0.0
	for i in 110:
		pc.move_override = Vector3.RIGHT if i >= 10 and i < 50 else Vector3.ZERO
		if i == 60:
			h.melee(Vector3.RIGHT)
		if i == 90:
			h._cast_pose()
		await get_tree().process_frame
		far = maxf(far, prop.global_position.distance_to(_fist(m, kit)))
		size = maxf(size, prop.global_basis.get_scale().x * 0.5)
	print("[anim] held moss, %s %s: at most %.2f from the fist, %.2f across" % [kit, prof, far, size])
	var reach := 0.45 if kit == "rebar" else 0.3   # (Rebar's "fist" is the centre of a glove 0.9 across: the palm is 0.4 out)
	check(far <= reach, "%s %s: the component stays in the hand (%.2f from the fist)" % [kit, prof, far])
	check(size <= 0.6, "%s %s: the component is hand-sized (%.2f across)" % [kit, prof, size])


## Where the hand that holds the component is (world).
func _fist(m: LowPolyModel, kit: String) -> Vector3:
	match kit:
		"gasket":
			return (m.parts["arm_l"] as Node3D).global_transform * Vector3(0, -0.76, 0)
		"rebar":
			return (m.parts["glove_l"] as Node3D).global_position
	return (m.parts["arm_r"] as Node3D).global_transform * Vector3(0, -WickModel.ARM_LEN, 0)


func _profiles() -> void:
	MoveFeel.reset()
	var seen := {}
	for s in 20:
		MoveFeel.set_mode(MoveFeel.SHUFFLE, s)
		seen[MoveFeel.active()] = true
		check(MoveFeel.active() in MoveFeel.BLIND, "shuffle deals only the blind pair")
		MoveFeel.cycle()
		seen[MoveFeel.active()] = true
	eq(seen.size(), 2, "shuffle deals grounded and grounded_anim")
	check(seen.has(MoveFeel.GROUNDED) and seen.has(MoveFeel.GROUNDED_ANIM), "... those two")
	MoveFeel.set_mode(MoveFeel.TODAY)
	eq(MoveFeel.active(), MoveFeel.TODAY, "today is still selectable by name")
	MoveFeel.cycle()
	MoveFeel.cycle()
	eq(MoveFeel.active(), MoveFeel.GROUNDED_ANIM, "F6 by name: today, grounded, grounded_anim")
	MoveFeel.set_mode(MoveFeel.GROUNDED_ANIM)
	eq(MoveFeel.crew_data(), {"id": "grounded_anim", "blind": false}, "the host sends grounded_anim with the job")
	MoveFeel.reset()
	MoveFeel.apply_crew({"feel": {"id": "grounded_anim", "blind": true}})
	eq(MoveFeel.crew_id, "grounded_anim", "a client takes the host's grounded_anim")
	MoveFeel.reset()
