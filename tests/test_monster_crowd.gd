extends MonsterTestBase
## Crowd variety (playtest feedback 2026-10-24, item 4: packs coming down a hallway in one single-file line; Monster's
## "Crowd variety"):
##   1. SPEED SPREAD: every monster's pace_k is within 1 +/- 8%, spread out, fixed for its life, and its walking speed is
##      move_speed x pace_k; the goblin keeps its own pace; the same floor seed and spawn order give the same paces;
##   2. SIZE JITTER: size_for(id) is within 1 +/- 7%, the same for the same id, and the Visual shows it (from the net id, or
##      the spawn order offline) while the radius and the model's own scale stay as they were;
##   2b. WALK UNSYNC: gait_for(id) rates within 1 +/- 10% and starts over the whole cycle; a pack spawned together walks on
##      clocks of its own;
##   3. PATH JITTER, ON A SMALL MAP: a 1-cell corridor, a wall beside the lane and a climb all take the lane to 0; open
##      floor takes the full lane, square across the direction of travel;
##   4. PATH JITTER, EVERYWHERE IN THE GYM: every waypoint (every cell, straight on and turning, either side) is either 0
##      or a point at most LANE_MAX off its centre, square across the way, with the body clear of every wall and on the
##      cell's own level;
##   5. NO STICKING: hallway packs on the gym's map (12 skeletons down the wide hall, the mixed pack, a narrow hall, the
##      course's pillars, steps and ledges): the no-progress nudges (_on_stuck) stay under ROUTE_MAX en route and
##      TARGET_RATE_MAX round the hero; prints the counts and the pack's spread in the hall.

const SEED := 7
const RUN_FRAMES := 1200          ## 20 s a scenario


func _init() -> void:
	timeout_sec = 400.0


func setup() -> void:
	await _pace()
	await _size()
	await _gait()
	_lanes_small()
	_lanes_gym()
	await _stuck()
	NetRegistry.clear()
	finish()


# --- 1. speed spread ---------------------------------------------------------------------------------------------------

func _spawn_grunts(n: int) -> Array[Monster]:
	var out: Array[Monster] = []
	for c in Hex.range_cells(Vector2i.ZERO, 5):
		if out.size() >= n:
			break
		out.append(MonsterFactory.spawn("grunt", c))
	return out


func _pace() -> void:
	new_world(flat_map(8))
	var ms := _spawn_grunts(40)
	var lo := INF
	var hi := -INF
	var seen := {}
	var paces: Array[float] = []
	for m in ms:
		check(absf(m.pace_k - 1.0) <= Monster.PACE_SPREAD + 0.0001, "pace %.3f within +/- 8%%" % m.pace_k)
		lo = minf(lo, m.pace_k)
		hi = maxf(hi, m.pace_k)
		seen[snappedf(m.pace_k, 0.0001)] = true
		paces.append(m.pace_k)
		near(m.effective_speed(), m.move_speed * m.pace_k, 0.0001, "its walking speed is move_speed x pace")
	print("  pace: %d grunts, %.3f .. %.3f, %d distinct" % [ms.size(), lo, hi, seen.size()])
	check(hi - lo > Monster.PACE_SPREAD, "the paces spread out (%.3f .. %.3f)" % [lo, hi])
	check(seen.size() > 30, "nearly every grunt has its own pace (%d of 40)" % seen.size())
	await frames(30)
	for i in ms.size():
		near(ms[i].pace_k, paces[i], 0.0, "the pace is fixed for its life")
	var gob := MonsterFactory.spawn("goblin", Vector2i(-6, 0))
	near(gob.pace_k, 1.0, 0.0, "the goblin scout keeps its own pace")
	# The same floor (seed and world) and spawn order: the same paces; no GameWorld.rng draw for them.
	new_world(flat_map(8))
	var again := _spawn_grunts(40)
	for i in again.size():
		near(again[i].pace_k, paces[i], 0.0, "a new floor with the same seed and spawn order rolls the same pace")
	GameWorld.rng.seed = SEED + 1
	var other := MonsterFactory.spawn("grunt", Vector2i(6, -1))
	check(other._spawn_n == 1, "a new seed starts the spawn order again")
	GameWorld.rng.seed = SEED


# --- 2. size jitter ----------------------------------------------------------------------------------------------------

func _size() -> void:
	new_world(flat_map(6))
	var lo := INF
	var hi := -INF
	for id in range(1, 3001):
		var k := Monster.size_for(id)
		lo = minf(lo, k)
		hi = maxf(hi, k)
	print("  size: ids 1..3000 give %.3f .. %.3f" % [lo, hi])
	check(lo >= 1.0 - Monster.SIZE_SPREAD - 0.0001 and hi <= 1.0 + Monster.SIZE_SPREAD + 0.0001, "sizes within +/- 7%")
	check(hi - lo > Monster.SIZE_SPREAD * 1.5, "and spread over it")
	eq(Monster.size_for(10042), Monster.size_for(10042), "the same id, the same size")
	var m := MonsterFactory.spawn("grunt", Vector2i(0, 0))
	var r := m.radius
	var model_scale := m.model.scale if m.model != null else Vector3.ONE
	await frames(2)
	near(m.size_k, Monster.size_for(-m._spawn_n), 0.0, "offline: the size comes from its spawn order")
	NetRegistry.register(10042, m)
	await frames(2)
	near(m.size_k, Monster.size_for(10042), 0.0, "with a net id: the size comes from the id")
	near(m._visual.scale.x, m.size_k, 0.0001, "the Visual shows it")
	near(m.radius, r, 0.0, "the radius (collision, hit areas) is unchanged")
	if m.model != null:
		check(m.model.scale.is_equal_approx(model_scale), "the model keeps its own scale")
	NetRegistry.clear()


# --- 2b. walk unsync ---------------------------------------------------------------------------------------------------

func _gait() -> void:
	new_world(flat_map(6))
	var lo := INF
	var hi := -INF
	var starts := {}
	for id in range(1, 3001):
		var g := Monster.gait_for(id)
		lo = minf(lo, g.y)
		hi = maxf(hi, g.y)
		starts[int(g.x * 10.0)] = true
	check(lo >= 1.0 - Monster.GAIT_SPREAD - 0.0001 and hi <= 1.0 + Monster.GAIT_SPREAD + 0.0001, "walk rates within +/- 10%")
	check(starts.size() >= 10, "walk starts spread over the whole cycle")
	eq(Monster.gait_for(10042), Monster.gait_for(10042), "the same id, the same walk")
	# A pack spawned on the same frame: each model's walk clock starts at its own point and runs at its own rate.
	var pack := _spawn_grunts(4)
	await frames(3)
	var clocks := {}
	for m in pack:
		if m.model == null:
			continue
		var g := Monster.gait_for(-m._spawn_n)
		near(m.gait_k, g.y, 0.0, "offline: the walk comes from its spawn order")
		near(m.model.cycle_k, g.y, 0.0, "... and its model runs at that rate")
		clocks[snappedf(m.model._t, 0.01)] = true
	check(clocks.size() == pack.size() or pack[0].model == null, "a pack spawned together is not in step (%d clocks)" % clocks.size())


# --- 3. path jitter on a small map -------------------------------------------------------------------------------------

func _offset(m: Monster, lane: float, prev: Vector2i, c: Vector2i, nxt: Vector2i) -> Vector3:
	m._lane = lane / Monster.LANE_MAX   # (the lane is a fraction of the widest)
	return m.lane_offset(prev, c, nxt)


func _lanes_small() -> void:
	var D := Hex.DIRS
	# A 1-cell corridor along +X (row r = 0), walls either side.
	var map := flat_map(8)
	wall_where(map, func(p: Vector3) -> bool: return absf(p.z) > 0.5)
	new_world(map)
	var m := MonsterFactory.spawn("grunt", Vector2i(0, 0))
	m.set_physics_process(false)
	for q in range(-5, 6):
		var c := Vector2i(q, 0)
		for lane in [Monster.LANE_MAX, -Monster.LANE_MAX]:
			eq(_offset(m, lane, c - D[0], c, c + D[0]), Vector3.ZERO, "a 1-cell corridor: no lane (%s, %.1f)" % [c, lane])
	# Open floor: the full lane, square across the way.
	new_world(flat_map(8))
	m = MonsterFactory.spawn("grunt", Vector2i(0, 0))
	m.set_physics_process(false)
	for k in 6:
		var c := Vector2i.ZERO
		var off := _offset(m, 0.3, c - D[k], c, c + D[k])
		near(off.length(), 0.3, 0.0001, "open floor: the full lane (dir %d)" % k)
		near(off.dot(Hex.to_world(D[k]).normalized()), 0.0, 0.0001, "... across the way")
		var off2 := _offset(m, -0.2, c - D[k], c, c + D[k])
		near(off2.length(), 0.2, 0.0001, "... either side, as far as the lane is")
		near(off2.dot(off), -0.06, 0.0001, "... and the other side is the other way")
	# A wall beside the way (cells with z > 1.6, the row r = 2 and up): toward it no lane, away from it the lane.
	map = flat_map(8)
	wall_where(map, func(p: Vector3) -> bool: return p.z > 1.6)
	new_world(map)
	m = MonsterFactory.spawn("grunt", Vector2i(0, 0))
	m.set_physics_process(false)
	var c1 := Vector2i(0, 1)   # beside the wall
	var toward := 0
	var away := 0
	for lane in [0.3, -0.3]:
		var off := _offset(m, lane, c1 - D[0], c1, c1 + D[0])
		if off == Vector3.ZERO:
			continue
		if off.z > 0.0:
			toward += 1
		else:
			away += 1
	eq(toward, 0, "beside a wall: never toward it")
	eq(away, 1, "... the lane away from it is kept")
	# A climb: cells x >= 2 (world) two levels up. The waypoints either side of the climb get no lane.
	map = flat_map(8)
	for c in map.cells.keys():
		if Hex.to_world(c).x > 2.0:
			map.set_cell(c, 2)
	new_world(map)
	m = MonsterFactory.spawn("grunt", Vector2i(-2, 0))
	m.set_physics_process(false)
	var a := Vector2i(1, 0)
	var b := Vector2i(2, 0)
	eq(map.cell_transition(a, b), HexMap.Move.CLIMB, "(the step is a climb)")
	for lane in [0.3, -0.3]:
		eq(_offset(m, lane, a - D[0], a, b), Vector3.ZERO, "before a climb: no lane")
		eq(_offset(m, lane, a, b, b + D[0]), Vector3.ZERO, "after a climb: no lane")


# --- 4. path jitter everywhere in the gym ------------------------------------------------------------------------------

func _lanes_gym() -> void:
	var map := GymMap.build_map()
	new_world(map)
	var start: Vector2i = map.cells_with_tag("start")[0]
	var probes := {}
	for kind in ["grunt", "brute", "swarmer"]:
		var pm := MonsterFactory.spawn(kind, start)
		pm.set_physics_process(false)
		probes[kind] = pm
	var D := Hex.DIRS
	var tried := 0
	var leaned := 0
	var bad := 0
	var corridor_tried := 0
	var corridor_leaned := 0
	for c: Vector2i in map.cells.keys():
		if not map.is_walkable_cell(c):
			continue
		var cell := map.get_cell(c)
		for k in 6:
			for turn in [0, 1, 5]:
				var prev: Vector2i = c - D[k]
				var nxt: Vector2i = c + D[(k + turn) % 6]
				if map.cell_transition(prev, c) == HexMap.Move.BLOCKED or map.cell_transition(c, nxt) == HexMap.Move.BLOCKED:
					continue
				for kind: String in probes:
					var m: Monster = probes[kind]
					for lane in [Monster.LANE_MAX, -Monster.LANE_MAX]:
						tried += 1
						var corridor := cell.tag == "corridor"
						if corridor:
							corridor_tried += 1
						var off := _offset(m, lane, prev, c, nxt)
						if off == Vector3.ZERO:
							continue
						leaned += 1
						if corridor:
							corridor_leaned += 1
						var cw := Hex.to_world(c)
						var p := cw + off
						var t := (Hex.to_world(nxt) - Hex.to_world(prev)).normalized()
						var ok := off.length() <= Monster.LANE_MAX + 0.0001 and absf(off.dot(t)) < 0.0001
						ok = ok and not map.blocks_point(p, m.radius)
						ok = ok and absf(map.ground_level(p) - float(cell.level)) < 0.01
						ok = ok and map.is_walkable_cell(Hex.from_world(p))
						ok = ok and not map.crosses_solid(cw, p, m.radius)
						if not ok:
							bad += 1
							if bad <= 5:
								check(false, "a lane off a safe spot: %s at %s (%s -> %s), offset %s" % [kind, c, prev, nxt, off])
	print("  lanes in the gym: %d waypoints judged, %d lean (%.0f%%); hall cells %d judged, %d lean (%.0f%%)" % [tried, leaned,
		100.0 * leaned / maxf(tried, 1), corridor_tried, corridor_leaned, 100.0 * corridor_leaned / maxf(corridor_tried, 1)])
	eq(bad, 0, "every lane in the gym stays on open floor, clear of the walls, on its cell's level")
	check(float(leaned) > float(tried) * 0.25, "open floor leans (%d of %d)" % [leaned, tried])


# --- 5. no more sticking -----------------------------------------------------------------------------------------------

## [name, kinds, the pack's spot, the hero's spot] on the gym's map.
func _scenarios() -> Array:
	var L: Dictionary = GymMap.layout()
	var out: Array = []
	var wide := GymDev.hall_link()
	var D := Hex.DIRS
	var wd: Vector2i = D[int(wide["dir"])]
	var grunts: Array[String] = []
	for _i in GymDev.HALL_COUNT:
		grunts.append("grunt")
	out.append(["wide hall", grunts, (wide["door_b"] as Vector2i) + wd, wide["door_a"]])
	out.append(["wide hall, mixed", GymDev.HALL_MIX, (wide["door_b"] as Vector2i) + wd, wide["door_a"]])
	for lk: Dictionary in (L["links"] as Array):
		if str(lk["a"]) == "cinema" and str(lk["b"]) == "cellar":
			var nd: Vector2i = D[int(lk["dir"])]
			out.append(["narrow hall", grunts, (lk["door_b"] as Vector2i) + nd * 2, (lk["door_a"] as Vector2i) - nd])
	# The course from its pad: the slalom's pillars, the steps up, the top, the 3-level drop, the +2 ledge and down again.
	out.append(["course", grunts, Hex.from_world(Vector3(GymMap.COURSE_X0 + 3.0, 0, 0)), Hex.from_world(Vector3(GymMap.COURSE_X0 + 42.0, 0, 0))])
	return out


## A nudge this far or more from the hero is EN ROUTE (what a lane could cause: the lanes are off within LANE_NEAR and
## ease in to LANE_NEAR + LANE_FADE); closer in it is the crowd jostling round the hero (the ones at the back can get no
## closer), which every arrival pattern has.
const EN_ROUTE := 4.0
const STUCK_SEEDS := [7, 23]


## The limits, from the comparison with the crowd variety off (2026-10-24, lanes of 0.3: en route 0.13 -> 0.00 nudges per
## monster-minute, round the hero 1.13 -> 1.09): the lanes must not make monsters stick on the way, nor much round the hero.
const ROUTE_MAX := 2                ## nudges en route, all scenarios and seeds together
const TARGET_RATE_MAX := 2.5        ## nudges round the hero per monster-minute


func _stuck() -> void:
	var sums := {"route": 0, "target": 0, "min": 0.0}
	print("  hallway packs, %d seeds each:" % STUCK_SEEDS.size())
	for sc: Array in _scenarios():
		var acc := {"route": 0, "target": 0, "min": 0.0, "arrived": 0, "spread": 0.0, "gaps": 0.0}
		for s: int in STUCK_SEEDS:
			var r := await _run(sc, s)
			for k: String in ["route", "target", "arrived"]:
				acc[k] = int(acc[k]) + int(r[k])
			for k: String in ["min", "spread", "gaps"]:
				acc[k] = float(acc[k]) + float(r[k]) / (1.0 if k == "min" else float(STUCK_SEEDS.size()))
		for k: String in ["route", "target", "min"]:
			sums[k] += acc[k]
		print("  %-17s nudges en route %d, at the hero %2d; arrived %2d; in the hall at 6 s: across %.2f, spacing sd %.2f" % [
			sc[0], acc["route"], acc["target"], acc["arrived"], acc["spread"], acc["gaps"]])
	var mins := maxf(float(sums["min"]), 0.001)
	print("  nudges per monster-minute: en route %.2f, at the hero %.2f" % [sums["route"] / mins, sums["target"] / mins])
	check(int(sums["route"]) <= ROUTE_MAX, "the lanes do not make monsters stick on the way (%d nudges)" % sums["route"])
	check(float(sums["target"]) / mins <= TARGET_RATE_MAX, "nor much round the hero (%.2f a monster-minute)" % [sums["target"] / mins])


## One hallway run on floor seed `s`: the pack at sc[2], a stand-in hero at sc[3], everyone sent at it for RUN_FRAMES.
## Returns {route, target (the nudges en route and round the hero), min (monster-minutes), arrived (within 3.5 of the hero
## at the end), spread (the pack's sideways spread in the wide hall at 6 s: the std dev across it), gaps (the std dev of
## the spacing along it)}.
func _run(sc: Array, s: int) -> Dictionary:
	var map := GymMap.build_map()
	new_world(map)
	GameWorld.rng.seed = s
	var hero := add_hero(sc[3] as Vector2i, map.ground_level(Hex.to_world(sc[3] as Vector2i)))
	hero.max_hp = 1.0e9
	hero.hp = hero.max_hp
	var kinds: Array = sc[1]
	var cells := GymSpawns.cells_near(map, Hex.to_world(sc[2] as Vector2i), kinds.size())
	var ms: Array[Monster] = []
	for i in cells.size():
		var m := MonsterFactory.spawn(str(kinds[i]), cells[i])
		m.aggro_range = 60.0
		m.leash_range = 90.0
		ms.append(m)
	for m in ms:
		m.aggro(hero)
	var route := 0
	var target := 0
	var seen := {}
	var spread := 0.0
	var gaps := 0.0
	var alive_frames := 0
	for f in RUN_FRAMES:
		await get_tree().physics_frame
		hero.hp = hero.max_hp
		for m in ms:
			if is_instance_valid(m) and not m.dead:
				alive_frames += 1
				var n := m._stuck_n - int(seen.get(m, 0))
				if n > 0:
					if fdist(m, hero) >= EN_ROUTE:
						route += n
					else:
						target += n
				seen[m] = m._stuck_n
		if f == 360 and str(sc[0]).begins_with("wide hall"):
			var sg := _hall_spread(ms)
			spread = sg.x
			gaps = sg.y
	var arrived := 0
	for m in ms:
		if is_instance_valid(m) and not m.dead and fdist(m, hero) < 3.5:
			arrived += 1
	return {"route": route, "target": target, "min": alive_frames / 60.0 / 60.0, "arrived": arrived, "spread": spread, "gaps": gaps}


## The pack in the wide hall (dir 3: it runs along X): (std dev of Z, std dev of the X spacing between neighbours).
func _hall_spread(ms: Array[Monster]) -> Vector2:
	var lk := GymDev.hall_link()
	var xa := Hex.to_world(lk["door_a"] as Vector2i).x
	var xb := Hex.to_world(lk["door_b"] as Vector2i).x
	var zs: Array[float] = []
	var xs: Array[float] = []
	for m in ms:
		var p := m.global_position
		if p.x <= maxf(xa, xb) and p.x >= minf(xa, xb):
			zs.append(p.z)
			xs.append(p.x)
	if zs.size() < 3:
		return Vector2.ZERO
	xs.sort()
	var dx: Array[float] = []
	for i in range(1, xs.size()):
		dx.append(xs[i] - xs[i - 1])
	return Vector2(_std(zs), _std(dx))


func _std(v: Array[float]) -> float:
	var mean := 0.0
	for x in v:
		mean += x
	mean /= float(v.size())
	var s := 0.0
	for x in v:
		s += (x - mean) * (x - mean)
	return sqrt(s / float(v.size()))
