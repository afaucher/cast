extends TestCase
## Package A "grounded" (MoveFeel, HeroMotion, HeroGait; docs/design/movement-research.md "As built") does what the
## doc's table says, measured frame by frame through the real PlayerController:
##   - the envelope: the first frame moves at the boost, full speed by `start`, a stop slides about 0.16 u, a reversal
##     takes about `reversal`, and the top speed is unchanged;
##   - a +1 step is a hop that peaks hop_peak above the step and never sinks the feet into its face;
##   - a +2 climb is a mantle: held at the lip for the kit's hold, then up; letting go during the hold cancels it;
##   - a walked-off drop falls under gravity (speeding up) and a big landing slows the walk;
##   - the stop slide never carries a hero over a pit's edge;
##   - casting never slows the walk;
##   - the stride matches the ground (the planted foot stays put) at the bow's, a walk's and coffee's speed, and strafing;
##   - footsteps and dust are counted; physics interpolation never changes the simulation;
##   - a puppet (a hero another machine moves) gets its stride from the shown motion and is never moved by HeroMotion.
## It prints the measured numbers ([feel] lines) for the doc.

const DT := 1.0 / 60.0

var root: Node3D


func _row(levels: Array) -> HexMap:
	var m := HexMap.new()
	for i in levels.size():
		if levels[i] != null:
			for r in [-1, 0, 1]:
				m.set_cell(Vector2i(i, r), int(levels[i]))
	return m


func _hero(map: HexMap, kit: String = "wick", model: Node3D = null) -> Array:
	for c in root.get_children():
		c.free()
	var world := Node3D.new()
	root.add_child(world)
	GameWorld.begin(map, world, 99)
	var h := HeroFactory.spawn_hero(Vector2i(0, 0), "Walker", Color.BLUE, "sword", model, kit)
	var pc := HeroFactory.make_player(h, [] as Array[String])
	pc.aim_override = h.global_position + Vector3(0, 0, -6)
	return [h, pc]


## Walk `dir` for `frames` physics frames; returns the X/Z speed of each frame.
func _drive(h: Hero, pc: PlayerController, dir: Vector3, frames: int, ys: Array = []) -> Array[float]:
	var out: Array[float] = []
	for i in frames:
		var p0 := h.global_position
		pc.move_override = dir
		await get_tree().physics_frame
		var d := h.global_position - p0
		d.y = 0.0
		out.append(d.length() / DT)
		ys.append(h.global_position.y)
	return out


func setup() -> void:
	timeout_sec = 120.0
	MoveFeel.reset()
	MoveFeel.set_mode(MoveFeel.GROUNDED)   # (named: the default is grounded_anim)
	root = Node3D.new()
	add_child(root)
	await _envelope()
	await _hop()
	await _mantle()
	await _drop()
	await _edge()
	await _gait()
	await _interp()
	await _puppet()
	await _profiles()
	MoveFeel.reset()
	finish()


func _envelope() -> void:
	var hp: Array = _hero(_row([2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]))
	var h: Hero = hp[0]
	var pc: PlayerController = hp[1]
	await frames(2)
	var start := await _drive(h, pc, Vector3.RIGHT, 40)
	near(start[0], 4.5 * 0.45, 0.05, "the first frame moves at the boost (45%)")
	var full_at := start.find(start.filter(func(v: float) -> bool: return v >= 4.49)[0])
	check(full_at >= 3 and full_at <= 7, "full speed after about 0.08 s (frame %d)" % full_at)
	near(start[30], 4.5, 0.01, "top speed unchanged")
	var x0 := h.global_position.x
	var stop := await _drive(h, pc, Vector3.ZERO, 20)
	var slide := h.global_position.x - x0
	near(slide, 0.16, 0.08, "a stop slides about 0.16 u (%.3f)" % slide)
	var stop_frames := stop.find(0.0)
	check(stop_frames >= 3 and stop_frames <= 6, "at rest after about 0.07 s (frame %d)" % stop_frames)
	await _drive(h, pc, Vector3.RIGHT, 30)
	var rev := await _drive(h, pc, Vector3.LEFT, 20)
	var rev_full := -1
	var last_x := h.global_position.x
	for i in rev.size():
		if rev[i] >= 4.49 and rev_full < 0:
			rev_full = i
	check(rev_full >= 4 and rev_full <= 8, "a reversal reaches full speed the other way in about 0.10 s (frame %d)" % rev_full)
	print("[feel] envelope: first frame %.2f u/s, full at frame %d, stop slide %.3f u in %d frames, reversal full at frame %d" % [
		start[0], full_at, slide, stop_frames, rev_full])
	# casting is free: a cast changes nothing about the walk
	h.spell_slots = ["heal"] as Array[String]
	var before := h.walk_speed()
	check(h.try_cast("heal", 1.0, h.global_position), "the cast goes off")
	near(h.walk_speed(), before, 0.0001, "casting never slows the walk")
	var during := await _drive(h, pc, Vector3.LEFT, 10)
	near(during[9], 4.5, 0.01, "walking at full speed right after a cast")
	check(last_x != 0.0, "")


func _hop() -> void:
	var hp: Array = _hero(_row([2, 2, 2, 2, 3, 3, 3, 3]))
	var h: Hero = hp[0]
	var pc: PlayerController = hp[1]
	await frames(2)
	var ys := []
	var xs := []
	var top := 3 * Hex.LEVEL_HEIGHT
	var edge := (Hex.to_world(Vector2i(3, 0)).x + Hex.to_world(Vector2i(4, 0)).x) * 0.5
	var sunk := 0.0
	for i in 120:
		pc.move_override = Vector3.RIGHT
		await get_tree().physics_frame
		ys.append(h.global_position.y)
		xs.append(h.global_position.x)
		if h.global_position.x > edge:
			sunk = maxf(sunk, top - h.global_position.y)
	var peak: float = ys.max()
	near(peak, top + 0.15, 0.03, "the hop peaks about 0.15 above the step (%.3f)" % (peak - top))
	check(sunk < 0.06, "the feet never sink into the step's face past its edge (%.3f)" % sunk)
	eq(h._motion.hops, 1, "one hop")
	near(h.global_position.y, top, 0.001, "standing on the step after it")
	print("[feel] hop: peak %.3f above the step, deepest below its top past the edge %.3f" % [peak - top, sunk])


func _mantle() -> void:
	for kit: String in ["wick", "", "gasket"]:
		var hp: Array = _hero(_row([2, 2, 2, 2, 4, 4, 4, 4, 4]), kit)
		var h: Hero = hp[0]
		var pc: PlayerController = hp[1]
		await frames(2)
		var t0 := GameWorld.time
		var target := Hex.to_world(Vector2i(6, 0)).x
		var held := 0
		while h.global_position.x < target and GameWorld.time - t0 < 6.0:
			pc.move_override = Vector3.RIGHT
			await get_tree().physics_frame
			if h._motion.mantle == 1:
				held += 1
		var took := GameWorld.time - t0
		var flat := (target - Hex.to_world(Vector2i(0, 0)).x) / 4.5
		var hold := float((MoveFeel.value("mantle_hold_kits") as Dictionary).get(kit, MoveFeel.num("mantle_hold")))
		eq(h._motion.mantles, 1, "%s: one mantle" % kit)
		near(held * DT, hold, 0.04, "%s: held at the lip for the kit's hold (%.2f s)" % [kit, held * DT])
		near(h.global_position.y, 4 * Hex.LEVEL_HEIGHT, 0.01, "%s: on top" % kit)
		print("[feel] mantle %s: held %.2f s, +2 costs %.2f s over flat" % [kit if kit != "" else "default", held * DT, took - flat])
	# letting go during the hold: no climb
	var hp2: Array = _hero(_row([2, 2, 2, 2, 4, 4, 4]), "")
	var h2: Hero = hp2[0]
	var pc2: PlayerController = hp2[1]
	await frames(2)
	while h2._motion.mantle != 1 and GameWorld.time < 30.0:
		pc2.move_override = Vector3.RIGHT
		await get_tree().physics_frame
	await _drive(h2, pc2, Vector3.ZERO, 30)
	eq(h2._motion.mantle, 0, "letting go cancels the mantle")
	near(h2.global_position.y, 2 * Hex.LEVEL_HEIGHT, 0.01, "still below the ledge")
	check(not h2.climbing, "not climbing")
	# Rebar can't climb: the ledge is a wall
	var hp3: Array = _hero(_row([2, 2, 2, 2, 4, 4, 4]), "rebar")
	var h3: Hero = hp3[0]
	await _drive(h3, hp3[1], Vector3.RIGHT, 90)
	near(h3.global_position.y, 2 * Hex.LEVEL_HEIGHT, 0.01, "Rebar never climbs")


func _drop() -> void:
	var hp: Array = _hero(_row([5, 5, 5, 2, 2, 2, 2, 2]))
	var h: Hero = hp[0]
	var pc: PlayerController = hp[1]
	await frames(2)
	await _drive(h, pc, Vector3.RIGHT, 45)
	var ys := []
	var sp := await _drive(h, pc, Vector3.RIGHT, 40, ys)
	var falls: Array[float] = []
	var land_frame := -1
	for i in range(1, ys.size()):
		var dy: float = ys[i - 1] - ys[i]
		if dy > 0.0005:
			falls.append(dy)
		elif not falls.is_empty() and land_frame < 0:
			land_frame = i
	check(falls.size() >= 4, "a fall over several frames (%d)" % falls.size())
	var speeding := true
	for i in range(1, falls.size() - 1):
		speeding = speeding and falls[i] >= falls[i - 1] - 0.0001
	check(speeding, "the fall speeds up (gravity), never eases in: %s" % str(falls))
	eq(h._motion.landings, 1, "one landing")
	check(land_frame > 0 and sp[land_frame] < 4.5 * 0.6, "a 3-level landing costs speed (%.2f u/s)" % (sp[land_frame] if land_frame > 0 else -1.0))
	print("[feel] 3-level drop: %d frames falling (%.2f s), per-frame drops %s, speed after landing %.2f" % [falls.size(), falls.size() * DT,
		str(falls.map(func(f: float) -> String: return "%.3f" % f)), sp[land_frame] if land_frame > 0 else -1.0])


func _edge() -> void:
	var hp: Array = _hero(_row([2, 2, 2, 2, null, null]))
	var h: Hero = hp[0]
	var pc: PlayerController = hp[1]
	await frames(2)
	var over := false
	for i in 120:
		pc.move_override = Vector3.RIGHT if i < 60 else Vector3.ZERO
		await get_tree().physics_frame
		over = over or is_nan(GameWorld.map.ground_height(h.global_position))
	check(not over, "the stop slide never carries the hero over the edge")
	check(not h.is_shoved(), "no pull-back happened")


## The planted foot's backward sweep over the ground speed, at mid-stance (1.00 = no skate), as animation-research.md §1.2.
func _match(h: Hero, pc: PlayerController, dir: Vector3, aim: Vector3, frames_n: int) -> float:
	pc.aim_override = h.global_position + aim * 6.0
	var model := h.visual_override as LowPolyModel
	var best := []
	var last := {}
	for i in frames_n:
		pc.aim_override = h.global_position + aim * 6.0
		pc.move_override = dir
		await get_tree().process_frame
		var body := h.global_position
		for side in ["leg_l", "leg_r"]:
			var leg := model.parts[side] as Node3D
			var sole := leg.global_transform * Vector3(0, -0.90, -0.03)
			if last.has(side) and i > 45:
				var v: Vector3 = (sole - (last[side] as Array)[0]) / DT
				var bv: Vector3 = (body - (last[side] as Array)[1]) / DT
				v.y = 0.0
				bv.y = 0.0
				if bv.length() > 0.5:
					var rel := v - bv
					best.append(-rel.dot(bv.normalized()) / bv.length())   # (the sweep that would plant the foot)
			last[side] = [sole, body]
	if best.is_empty():
		return 0.0
	best.sort()
	return best[maxi(best.size() - 2, 0)]   # (at its fastest, mid-stance, as anim_lab's --measure; one frame's spike dropped)


func _gait() -> void:
	var hp: Array = _hero(_row([2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]), "wick", WickModel.new())
	var h: Hero = hp[0]
	var pc: PlayerController = hp[1]
	await frames(2)
	var walk := await _match(h, pc, Vector3.RIGHT, Vector3.RIGHT, 90)
	h.set_modifier("test_coffee", 1.6, 5.0, Actor.STAT_MOVE_SPEED)
	var coffee := await _match(h, pc, Vector3.LEFT, Vector3.LEFT, 90)
	h.clear_modifier("test_coffee")
	h._draw_start = GameWorld.time   # (the bow drawn: x0.5)
	var bow := await _match(h, pc, Vector3.RIGHT, Vector3.RIGHT, 90)
	h._draw_start = -1.0
	var strafe := await _match(h, pc, Vector3.LEFT, Vector3(0, 0, -1), 90)
	print("[feel] stride match (1.00 = the planted foot stays put): walk %.2f, coffee %.2f, bow %.2f, strafe %.2f" % [walk, coffee, bow, strafe])
	for pair: Array in [["walk", walk], ["coffee", coffee], ["bow", bow], ["strafe", strafe]]:
		check(float(pair[1]) > 0.8 and float(pair[1]) < 1.2, "stride matches the ground: %s %.2f" % [pair[0], pair[1]])
	check(h._gait.steps > 6, "footsteps were counted (%d)" % h._gait.steps)
	# a reversal at speed scuffs dust
	var puffs := h._gait.puffs
	await _drive(h, pc, Vector3.RIGHT, 40)
	await _drive(h, pc, Vector3.LEFT, 30)
	check(h._gait.puffs > puffs, "a reversal puffs dust")
	# back to today: the model's own clock again, the legs straight
	MoveFeel.set_mode(MoveFeel.TODAY)
	await frames(3)
	check((h.visual_override as LowPolyModel).idle_enabled, "today: the model runs its own clock")
	check(h._gait.gait == null, "today: no gait")
	MoveFeel.set_mode(MoveFeel.GROUNDED)


func _interp() -> void:
	var traces := []
	for on in [false, true]:
		MoveFeel.interp = on
		var hp: Array = _hero(_row([2, 2, 2, 2, 3, 3, 3, 3, 2, 2, 2]))
		var h: Hero = hp[0]
		var pc: PlayerController = hp[1]
		await frames(2)
		var tr := PackedStringArray()
		for i in 90:
			pc.move_override = Vector3.RIGHT if i < 70 else Vector3.ZERO
			await get_tree().physics_frame
			tr.append("%.5f %.5f" % [h._ip_cur.x if false else h.global_position.x, h.global_position.y])
		traces.append(tr)
	MoveFeel.interp = false
	eq(traces[0], traces[1], "physics interpolation never changes where the hero really is")


func _puppet() -> void:
	var hp: Array = _hero(_row([2, 2, 2, 2, 2, 2, 2, 2, 2, 2]), "wick", WickModel.new())
	var h: Hero = hp[0]
	(hp[1] as PlayerController).queue_free()
	await frames(1)
	Net.make_puppet(h)
	var y0 := h.global_position.y
	for i in 60:
		h.global_position += Vector3(4.5 * DT, 0.3 * DT if i == 10 else 0.0, 0)   # (a stream moves it; one odd y sample)
		await get_tree().process_frame
	check(h._gait.gait != null and h._gait.gait.t > 0.5, "a puppet strides from its shown motion")
	check(h._gait.steps > 2, "a puppet's footsteps play (%d)" % h._gait.steps)
	near(h.global_position.y, y0 + 0.3 * DT, 0.0001, "HeroMotion never moves a puppet (its y is the stream's)")
	Net.release_copy(h)


func _profiles() -> void:
	MoveFeel.reset()
	eq(MoveFeel.active(), MoveFeel.GROUNDED_ANIM, "the default is grounded_anim (the user, 2026-10-23)")
	eq(MoveFeel.DEFAULT, MoveFeel.GROUNDED_ANIM, "MoveFeel.DEFAULT")
	check(not MoveFeel.interp, "the judder smoothing is off by default")
	MoveFeel.boot(PackedStringArray(["--move-feel", "today"]))
	eq(MoveFeel.active(), MoveFeel.GROUNDED_ANIM, "boot reads the flags once per run (reset() counts as the read)")
	MoveFeel._booted = false
	MoveFeel.boot(PackedStringArray(["--move-feel", "today", "--physics-interp", "on"]))
	eq(MoveFeel.active(), MoveFeel.TODAY, "--move-feel today still plays today")
	check(MoveFeel.interp, "--physics-interp on")
	MoveFeel.reset()
	MoveFeel._booted = false
	MoveFeel.boot(PackedStringArray([]))
	eq(MoveFeel.active(), MoveFeel.GROUNDED_ANIM, "no flag: grounded_anim (an exported build)")
	MoveFeel.set_mode("shuffle")
	eq(MoveFeel.active(), MoveFeel.GROUNDED_ANIM, "an unknown profile (the old shuffle) plays the default")
	check(MoveFeel.pick(MoveFeel.GROUNDED), "the gym's picker switches solo")
	eq(MoveFeel.active(), MoveFeel.GROUNDED, "... to grounded")
	eq(MoveFeel.switches, 1, "a switch is counted")
	check(not MoveFeel.pick("bogus"), "an unknown pick is refused")
	eq(MoveFeel.crew_data(), {"id": "grounded"}, "the host sends its profile with the job")
	MoveFeel.reset()
	eq(MoveFeel.crew_data(), {"id": "grounded_anim"}, "a host with no flag sends grounded_anim")
	MoveFeel.set_mode(MoveFeel.TODAY)
	MoveFeel.apply_crew({"feel": {"id": "grounded"}})
	eq(MoveFeel.active(), MoveFeel.TODAY, "a crew's profile only counts in a crew (solo here)")
	# the log: one row per stretch, with the profile
	MoveFeel.reset()
	MoveFeel.set_mode(MoveFeel.GROUNDED)
	var hp: Array = _hero(_row([2, 2, 2, 2, 2, 2]))
	var log := MoveLog.new()
	log.player = hp[0]
	root.add_child(log)
	await _drive(hp[0], hp[1], Vector3.RIGHT, 50)
	MoveFeel.pick(MoveFeel.GROUNDED_ANIM)
	log.switched()
	eq(log.rows.size(), 1, "a switch writes the stretch's row")
	var cells := log.rows[0].split(",")
	eq(cells[4], "grounded", "the label column names the profile")
	eq(cells[5], "grounded", "the profile column")
	eq(cells[7], "period", "a period row")
	check(float(cells[9]) > 1.0, "distance walked is logged (%s)" % cells[9])
	# the tag: names a flag's profile at the start, nothing for the default; no keys switch anything any more
	MoveFeel.reset()
	var tag := MoveFeelTag.attach(root, hp[0])
	await frames(2)
	check(tag.label.modulate.a < 0.01, "the default profile shows no tag")
	var f6 := InputEventKey.new()
	f6.physical_keycode = KEY_F6
	f6.pressed = true
	tag.propagate_call("_unhandled_input", [f6])
	var f7 := InputEventKey.new()
	f7.physical_keycode = KEY_F7
	f7.pressed = true
	tag.propagate_call("_unhandled_input", [f7])
	eq(MoveFeel.active(), MoveFeel.GROUNDED_ANIM, "F6 no longer switches the profile")
	check(not MoveFeel.interp, "F7 no longer turns the smoothing on")
	tag.queue_free()
	MoveFeel.set_mode(MoveFeel.TODAY)
	var tag2 := MoveFeelTag.attach(root, hp[0])
	await frames(2)
	eq(tag2.label.text, "today", "a flag's profile is named at the start")
	tag2.queue_free()
	# the camera leads along the walk and a little toward the aim, at most cam_lead_max
	MoveFeel.reset()
	MoveFeel.set_mode(MoveFeel.GROUNDED)
	var hc: Array = _hero(_row([2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2]))
	var rig := CameraRig.new()
	root.add_child(rig)
	rig.target = hc[0]
	(hc[1] as PlayerController).aim_override = Vector3(1000, 0, 0)
	rig.aim_source = (hc[1] as PlayerController).aim_point
	await _drive(hc[0], hc[1], Vector3.RIGHT, 60)
	near(rig.lead.length(), 2.0, 0.05, "the lead is capped at 2 (%.2f)" % rig.lead.length())
	(hc[1] as PlayerController).aim_override = (hc[0] as Hero).global_position
	await frames(5)
	check(rig.lead.x > 0.6 and rig.lead.x < 1.25, "about 1.2 along the walk with the aim on the hero (%.2f)" % rig.lead.x)
	MoveFeel.set_mode(MoveFeel.TODAY)
	await frames(2)
	eq(rig.lead, Vector3.ZERO, "today: no lead")
	MoveFeel.reset()
