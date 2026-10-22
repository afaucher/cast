extends MonsterTestBase
## The sewer and lava sounds (docs/design/audio-plan.md, "Sewers and lava"; the cues in scripts/fx/sfx.gd), solo, from the
## real gameplay events that already run on every machine (no sound crosses the network):
## - the gator: the hiss as a nip winds up, the snap as it bites, a splash going in or out of the water (not again within a
##   second), the thrash as it dies;
## - the goo imp: the throw as the ball leaves its hand, the splat where it lands on the floor, the splash in water, a patch's
##   whoomph as it is lit and its fizz as it is washed away;
## - the live wire: sparks as the panel breaks, the crack of each shock (the first and the pulses), the fizzle when the
##   breaker trips (no buzz: none passed the mic-leak probe);
## - wading: a hero's soft steps in water about every Wading.STEP_EVERY units it walks, none standing, none on dry floor;
## - the lava: the steam as damp crusts it, the cracking as the crust's warning starts, the sizzle of anything that lands in
##   it, and the bubbling bed at most two spots near the ear (none without a camera, none far from lava).
## Streams are put in by the test (Sfx.override_stream): no rendered audio needed. Sfx.played counts each cue's plays.

const TONE_S := 0.4


func _init() -> void:
	timeout_sec = 300.0


func setup() -> void:
	Sfx.enable_for_tests()
	var tone := _tone(TONE_S)
	for cue: String in Sfx.CUES:
		Sfx.override_stream(cue, tone)
	await _check_gator()
	await _check_goo()
	await _check_live_wire()
	await _check_wading()
	await _check_lava()
	for cue: String in Sfx.CUES:
		Sfx.stop_cue(cue, 0.0)
	Sfx.disable_for_tests()
	if world != null:
		world.free()
		world = null
	finish()


func _tone(seconds: float) -> AudioStreamWAV:
	var n := int(seconds * 22050.0)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(1500.0 * sin(TAU * 330.0 * float(i) / 22050.0)))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	w.data = bytes
	return w


## Wait `n` physics frames with the cues' wall-clock min_gap out of the way (headless frames run faster than real time,
## so a gap the game would see in seconds can pass here in milliseconds).
func _run(n: int) -> void:
	for i in n:
		Sfx._last.clear()
		await frames(1)


func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		Sfx._last.clear()
		await frames(1)
	return cond.call()


func _n(cue: String) -> int:
	return int(Sfx.played.get(cue, 0))


## The positions of the voices of `cue` playing now.
func _voices_of(cue: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p: Node in Sfx._voice:
		if Sfx._voice[p][0] == cue and p is AudioStreamPlayer3D and (p as AudioStreamPlayer3D).playing:
			out.append((p as AudioStreamPlayer3D).global_position)
	return out


# --- the gator ------------------------------------------------------------------------------------------------------------

func _check_gator() -> void:
	var L := SewerLayouts.build(1)
	var m: HexMap = L["map"]
	new_world(m)
	var gt: Dictionary = L["gator"]
	var spots: Array[Vector2] = []
	for s: Vector2 in (gt["spots"] as Array):
		spots.append(s)
	var g := Gator.spawn(gt["at"], gt["face"], Gator.region_of(m), spots, 1234)
	g._relocate_at = INF
	await _run(3)
	Sfx.played.clear()
	# a body inside its territory: the wind-up's hiss, then the bite's snap
	var fwd := Vector3(g.facing.x, 0.0, g.facing.z)
	var h := add_hero(Vector2i.ZERO)
	h.max_hp = 1000.0
	h.hp = 1000.0
	var best := Vector2i(1 << 20, 0)
	var best_s := INF
	for c in Hex.range_cells(Hex.from_world(g.head()), 3):
		if not m.is_walkable_cell(c):
			continue
		var w := Hex.to_world(c)
		var s := absf(GameWorld.flat_distance(w, g.head()) - 1.9) - fwd.dot((w - g.head()).normalized())
		if s < best_s:
			best_s = s
			best = c
	h.global_position = Hex.to_world(best)
	h.snap_to_ground()
	check(await _until(func() -> bool: return g.state == Gator.NIP, 90), "a body in its territory: the nip winds up")
	await _run(1)
	eq(_n("gator_hiss"), 1, "the wind-up hisses, once")
	eq(_n("gator_snap"), 0, "no snap before the bite")
	check(await _until(func() -> bool: return g.nips >= 1, 90), "the nip lands")
	eq(_n("gator_snap"), 1, "the bite snaps, once")
	eq(_n("gator_hiss"), 1, "and the hiss is not played again by the bite")
	h.free()
	await _run(5)
	# out of the water and back: a splash each way, not a second one within a second
	var here := Hex.from_world(g.global_position)
	var wet := Vector2i(1 << 20, 0)
	var dry := Vector2i(1 << 20, 0)
	for c: Vector2i in g.home_cells:
		if not m.is_walkable_cell(c) or Hex.distance(c, here) > 4:
			continue
		if m.water_at(Hex.to_world(c)):
			if wet.x >= 1 << 19 or Hex.distance(c, here) < Hex.distance(wet, here):
				wet = c
		elif dry.x >= 1 << 19 or Hex.distance(c, here) < Hex.distance(dry, here):
			dry = c
	if check(wet.x < 1 << 19 and dry.x < 1 << 19, "a wet and a dry cell in its region near it"):
		g.global_position = Hex.to_world(wet)
		g.snap_to_ground()
		await _run(75)
		check(g.in_water(), "the gator in its water")
		var splashes := _n("gator_splash")
		g.global_position = Hex.to_world(dry)
		g.snap_to_ground()
		await _run(2)
		eq(_n("gator_splash"), splashes + 1, "out of the water: a splash")
		g.global_position = Hex.to_world(wet)
		g.snap_to_ground()
		await _run(2)
		eq(_n("gator_splash"), splashes + 1, "back in within a second: no second splash")
		await _run(70)
		g.global_position = Hex.to_world(dry)
		g.snap_to_ground()
		await _run(2)
		eq(_n("gator_splash"), splashes + 2, "out again a second later: a splash")
	# its death: the thrash
	g.apply_damage(10000.0, null)
	await _run(2)
	check(g.dead, "the gator dies")
	eq(_n("gator_thrash"), 1, "its death thrashes, once")


# --- the goo imp -------------------------------------------------------------------------------------------------------------

func _check_goo() -> void:
	new_world(flat_map(12))
	var imp := MonsterFactory.spawn("goo_imp", Vector2i(-5, 0)) as GooImp
	await _run(2)
	imp.set_physics_process(false)
	Sfx.played.clear()
	var patches: Array[GooPatch] = []
	for spot: Vector3 in [Vector3(2.0, 0.0, 0.0), Vector3(2.0, 0.0, -6.0)]:
		var b := imp.throw_at(spot)
		await _run(1)
		eq(_n("goo_throw"), patches.size() + 1, "the ball leaves its hand: the throw")
		check(await _until(func() -> bool: return b.landed, 120), "the ball lands")
		eq(_n("goo_splat"), patches.size() + 1, "it splats on the floor")
		patches.append(b.patch as GooPatch)
	eq(_n("goo_splash"), 0, "no water splash on dry floor")
	var p1 := patches[0]
	var p2 := patches[1]
	if check(p1 != null and p2 != null, "two patches"):
		p1.light(GameWorld.time, null)
		await _run(1)
		eq(_n("goo_ignite"), 1, "a patch lit: the whoomph")
		p1.light(GameWorld.time, null)
		eq(_n("goo_ignite"), 1, "lit once (lighting it again does nothing)")
		p2.wash()
		await _run(1)
		eq(_n("goo_wash"), 1, "a patch washed away: the fizz")
	# into the water
	var wm := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 12):
		if c.x >= -1 and c.x <= 1:
			var cell := wm.set_cell(c, -1)
			cell.pool_mask = HexMap.ALL_KITES
			cell.pool_level = -1
		else:
			wm.set_cell(c, 0)
	wm.pools.append({"body": true})
	new_world(wm)
	var imp2 := MonsterFactory.spawn("goo_imp", Vector2i(-6, 0)) as GooImp
	await _run(2)
	imp2.set_physics_process(false)
	Sfx.played.clear()
	var b3 := imp2.throw_at(Hex.to_world(Vector2i(0, 2), -1.0))
	check(await _until(func() -> bool: return b3.landed, 120), "a ball lands in the channel")
	eq(_n("goo_splash"), 1, "in the water: the splash")
	eq(_n("goo_splat"), 0, "not the floor's splat")


# --- the live wire -------------------------------------------------------------------------------------------------------------

func _check_live_wire() -> void:
	var L := SewerLayouts.build(1)
	var m: HexMap = L["map"]
	new_world(m)
	Ledger.begin_contract(1000000)
	var pe: Dictionary = {}
	for e: Dictionary in L["props"]:
		if str(e["kind"]) == "electrical_panel":
			pe = e
	if not check(not pe.is_empty(), "layout 1 has an electrical panel"):
		return
	var panel := PricedProp.spawn(ThemeGeo.cell_of(pe["pos"]), "electrical_panel", {"pos": pe["pos"], "yaw": pe["yaw"]})
	var w := LiveWire.attach(panel, LiveWire.drop_point_for(m, pe["pos"], panel.facing_vector()))
	await _run(3)
	Sfx.played.clear()
	panel.apply_damage(1.0, null)
	await _run(1)
	eq(_n("wire_spark"), 1, "the panel breaks: sparks")
	eq(_n("wire_shock"), 0, "no shock while the cable falls")
	check(await _until(func() -> bool: return w.shocks >= 1, int(LiveWire.DROP_T * 60.0) + 10), "the cable lands")
	eq(_n("wire_shock"), 1, "the landing's shock cracks")
	var pulses := int(LiveWire.PULSE_FOR / LiveWire.PULSE_EVERY)
	check(await _until(func() -> bool: return not w.is_physics_processing(), int((LiveWire.PULSE_FOR + 1.0) * 60.0)), "the breaker trips")
	eq(_n("wire_shock"), 1 + pulses, "a crack for each pulse too (%d in all)" % (1 + pulses))
	eq(_n("wire_fizzle"), 1, "the dying fizzle when it trips")
	eq(_n("fuse"), 0, "the wire no longer borrows the fuse's hiss")


# --- wading ----------------------------------------------------------------------------------------------------------------------

func _check_wading() -> void:
	var wm := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 12):
		if c.x >= -1 and c.x <= 1:
			var cell := wm.set_cell(c, -1)
			cell.pool_mask = HexMap.ALL_KITES
			cell.pool_level = -1
		else:
			wm.set_cell(c, 0)
	wm.pools.append({"body": true})
	new_world(wm)
	var a := Hex.to_world(Vector2i(0, -4), -1.0)
	var b := Hex.to_world(Vector2i(0, 4), -1.0)
	var h := HeroFactory.spawn_hero(Vector2i(0, -4), "Wader", Color.WHITE)
	h.set_physics_process(false)
	h.global_position = a
	await _run(3)
	check(Wading.is_wading(h), "the hero wades")
	Sfx.played.clear()
	# walk 9 units through the water at about wading speed
	var dist := 9.0
	check(GameWorld.flat_distance(a, b) >= dist, "a channel long enough to walk")
	var dir := (b - a).normalized()
	for i in int(dist / 0.05):
		h.global_position = a + dir * 0.05 * float(i + 1)
		Sfx._last.clear()
		await frames(1)
	var n := _n("wade_step")
	var want := dist / Wading.STEP_EVERY
	check(n >= int(want) - 1 and n <= int(want) + 1, "%d steps walking %.0f units in water (about one every %.1f)" % [n, dist, Wading.STEP_EVERY])
	await _run(120)
	eq(_n("wade_step"), n, "standing in the water: no steps")
	# on dry floor: none
	var dry_a := Hex.to_world(Vector2i(5, -4))
	for i in 120:
		h.global_position = dry_a + Vector3(0.0, 0.0, 0.05 * float(i))
		Sfx._last.clear()
		await frames(1)
	eq(_n("wade_step"), n, "walking on dry floor: no wading steps")
	# a plain actor (a monster, an employee) wading splashes too (user, 2026-10-21: "should probably play for all
	# characters, not just the player")
	var other := add_hero(Vector2i(0, -4), -1.0)
	for i in 120:
		other.global_position = a + Vector3(0.0, 0.0, 0.05 * float(i))
		Sfx._last.clear()
		await frames(1)
	check(_n("wade_step") > n, "a non-hero wading makes steps too")


# --- lava ---------------------------------------------------------------------------------------------------------------------

func _check_lava() -> void:
	var m := LavaCave.build_map(1)
	new_world(m)
	var f := LavaField.new()
	world.add_child(f)
	f.setup(m)
	f.activate()
	# no camera: no ear, no bed
	Sfx.played.clear()
	await _run(int(LavaField.BED_EVERY * 60.0 * 2.0))
	eq(_n("lava_bubble"), 0, "no camera: no bed")
	# a camera over the causeway (the ear is where its view meets the ground)
	var bridge: Dictionary = LavaCave.layout(1)["bridges"][0]
	var rows := LavaCave.bridge_rows(bridge)
	var cell: Vector2i = rows[3][0]
	var over := Hex.to_world(cell, float(m.get_cell(cell).level))
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.global_position = over + Vector3(0.0, 20.0, 12.0)
	cam.look_at(over, Vector3.UP)
	cam.make_current()
	await _run(2)
	var ear := Sfx.ear()
	check(ear != Vector3.INF and GameWorld.flat_distance(ear, over) < 1.0, "the ear is where the camera looks (%s)" % ear)
	await _run(int(LavaField.BED_EVERY * 60.0 * 3.5))
	check(_n("lava_bubble") >= 2, "near lava the bed plays again and again (%d plays)" % _n("lava_bubble"))
	var spots := {}
	for p in _voices_of("lava_bubble"):
		check(GameWorld.flat_distance(p, ear) <= LavaField.BED_REACH + 0.01, "a bed spot near the ear (%.1f)" % GameWorld.flat_distance(p, ear))
		spots[Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0))] = true
	check(spots.size() >= 1 and spots.size() <= 2, "at most two spots play (%d)" % spots.size())
	check(_voices_of("lava_bubble").size() <= int(Sfx.CUES["lava_bubble"]["max_voices"]), "within its voice limit")
	# far from any lava: silence
	cam.global_position = Vector3(500.0, 20.0, 512.0)
	cam.look_at(Vector3(500.0, 0.0, 500.0), Vector3.UP)
	await _run(3)
	var far_n := _n("lava_bubble")
	await _run(int(LavaField.BED_EVERY * 60.0 * 2.5))
	eq(_n("lava_bubble"), far_n, "far from the lava: no bed")
	cam.queue_free()
	# damp crusts it: the steam; the crust's warning: the cracking
	var at := over
	var d := Damp.new()
	d.power = 1.0
	GameWorld.spawn(d, at)
	check(await _until(func() -> bool: return f.crusts.size() == 1, 60), "a damp at the bridge's edge crusts the lava")
	eq(_n("lava_crust"), 1, "the crust forms: the steam")
	eq(_n("lava_crack"), 0, "no cracking yet")
	var end := float(f.crusts[0]["end"]) if not f.crusts.is_empty() else GameWorld.time
	await _until(func() -> bool: return GameWorld.time >= end - LavaField.CRUST_WARN + 0.1, int((LavaField.CRUST_LIFE + 1.0) * 60.0))
	eq(_n("lava_crack"), 1, "the crust's warning starts: the cracking, once")
	await _until(func() -> bool: return f.crusts.is_empty(), int((LavaField.CRUST_WARN + 1.0) * 60.0))
	eq(_n("lava_crack"), 1, "still once when it melts")
	# a grunt shoved into the lava: the sizzle
	var grunt := MonsterFactory.spawn("grunt", cell)
	grunt.aggro_range = 0.0
	await _run(2)
	var sizzles := _n("lava_sizzle")
	grunt.shove(Hex.dir_vector(5), 3.0, null)
	check(await _until(func() -> bool: return not is_instance_valid(grunt) or grunt.dead, 240), "the grunt falls in")
	check(_n("lava_sizzle") >= sizzles + 1, "it lands in the lava: the sizzle")
