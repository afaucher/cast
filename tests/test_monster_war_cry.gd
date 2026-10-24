extends MonsterTestBase
## War cries (playtest feedback 2026-10-24, item 4, batch 2; Monster, "War cries"):
##   1. FIRST SIGHT: a pack woken together yells once, by its lowest key (the same monster on every machine), and that one
##      throws its war cry pose;
##   2. THE COOLDOWN: a monster of the same area spotting the crew 2 s later stays quiet, one in another area yells, and the
##      first area yells again once CRY_PACK_COOLDOWN has passed;
##   3. BORN FIGHTING: a gate's burst of 7 (spawned and sent at the crew on one frame) yells once;
##   4. A PUPPET yells from the state it is shown (net_show, net_tick), the same rule: one per pack, the lowest key;
##   5. THE SWITCH: "off" yells nothing; A / B / C pick each voice's cue, the other kinds the shared one; frozen monsters and
##      the goblin scout never yell;
##   6. CHARGING STAYS RARE: the roll's hash hits about CHARGE_CHANCE of the time, and a hallway of 12 chasing the crew for
##      10 s yells only a couple of times (four runs with different keys).

const HALL_FRAMES := 600


func _init() -> void:
	timeout_sec = 240.0


func setup() -> void:
	Monster.war_cry = "A"
	Monster.reset_war_cries()
	await _first_sight()
	await _born_fighting()
	await _puppets()
	await _switch()
	_roll_rate()
	await _hallways()
	Monster.war_cry = "A"
	Monster.reset_war_cries()
	finish()


func _total(ms: Array) -> int:
	var n := 0
	for m: Monster in ms:
		if is_instance_valid(m):
			n += m.cries
	return n


## `n` grunts on the cells round `at` (ring by ring), looking `facing` (away from the crew).
func _pack(kind: String, at: Vector2i, n: int, facing: Vector3 = Vector3.RIGHT) -> Array[Monster]:
	var out: Array[Monster] = []
	for c in Hex.range_cells(at, 2):
		if out.size() >= n:
			break
		var m := MonsterFactory.spawn(kind, c)
		m.set_spawn_facing(facing)
		out.append(m)
	return out


func _free(ms: Array) -> void:
	for m in ms:
		if is_instance_valid(m):
			m.queue_free()


# --- 1, 2. first sight and the cooldown ------------------------------------------------------------------------------------

func _first_sight() -> void:
	new_world(flat_map(22))
	Monster.reset_war_cries()
	var hero := add_hero(Vector2i(-9, 0))   # 15.6 away, behind them: they see nothing by themselves
	var pack := _pack("grunt", Vector2i(0, 0), 6)
	await frames(3)
	eq(_total(pack), 0, "a resting pack yells nothing")
	var low: Monster = pack[0]
	for m in pack:
		if m.cry_key() < low.cry_key():
			low = m
	pack[3].aggro(hero)   # one spots the crew; _alert_pack wakes the rest on the same frame
	var crying := false
	for _i in 20:
		await frames(1)
		if low.cries > 0 and low.model != null and low.model.is_crying():
			crying = true
	eq(_total(pack), 1, "a pack woken together yells once")
	eq(low.cries, 1, "... by its lowest key (%d)" % low.cry_key())
	check(crying or low.model == null, "... which throws its war cry pose")
	var t0 := GameWorld.time
	_free(pack)
	# 2 s later in the same area: quiet; in another area (21 away): a cry
	await wait_until(func() -> bool: return GameWorld.time >= t0 + 2.0, 200)
	var b := MonsterFactory.spawn("grunt", Vector2i(2, 0))
	var d := MonsterFactory.spawn("grunt", Vector2i(-6, 14))
	b.set_spawn_facing(Vector3.RIGHT)
	d.set_spawn_facing(Vector3.RIGHT)
	check(GameWorld.flat_distance(d.global_position, Vector3.ZERO) > Monster.CRY_PACK_RADIUS, "the other area is beyond the pack radius")
	await frames(2)
	b.aggro(hero)
	d.aggro(hero)
	await frames(20)
	eq(b.cries, 0, "the same area 2 s later: no second first-sight cry")
	eq(d.cries, 1, "another area: its own cry")
	_free([b, d])
	# once the cooldown has passed, the first area yells again
	await wait_until(func() -> bool: return GameWorld.time >= t0 + Monster.CRY_PACK_COOLDOWN + 0.3, 600)
	var c := MonsterFactory.spawn("grunt", Vector2i(1, 0))
	c.set_spawn_facing(Vector3.RIGHT)
	await frames(2)
	c.aggro(hero)
	await frames(20)
	eq(c.cries, 1, "after the cooldown the same area yells again")
	_free([c])
	await frames(2)


# --- 3. born fighting (a gate's burst) -----------------------------------------------------------------------------------

func _born_fighting() -> void:
	new_world(flat_map(22))
	Monster.reset_war_cries()
	var hero := add_hero(Vector2i(-9, 0))
	var burst := _pack("grunt", Vector2i(0, 0), 7)
	for m in burst:
		m.aggro(hero)   # (Hellgate.spawn_burst: spawned and sent at the nearest hero on one frame)
	await frames(20)
	eq(_total(burst), 1, "a gate's burst of 7 yells once")
	_free(burst)
	await frames(2)


# --- 4. puppets ------------------------------------------------------------------------------------------------------------

func _puppets() -> void:
	new_world(flat_map(10))
	Monster.reset_war_cries()
	var pack := _pack("grunt", Vector2i(0, 0), 4)
	for m in pack:
		m.set_physics_process(false)   # (a puppet: the host simulates it; this screen only shows it)
	var dt := 1.0 / 60.0
	for _i in 3:
		for m in pack:
			m.net_tick(dt)
		await frames(1)
	eq(_total(pack), 0, "resting puppets yell nothing")
	for m in pack:   # the stream's next snapshot: the host's pack is fighting
		m.net_show(m.facing, false, m.hp, Monster.State.CHASE, 0.0, 0)
	for _i in 20:
		for m in pack:
			m.net_tick(dt)
		await frames(1)
	eq(_total(pack), 1, "puppets shown fighting yell once")
	var low: Monster = pack[0]
	for m in pack:
		if m.cry_key() < low.cry_key():
			low = m
	eq(low.cries, 1, "... by the lowest key, as on the host")
	_free(pack)
	await frames(2)


# --- 5. the switch, the cues, who never yells -------------------------------------------------------------------------

func _switch() -> void:
	for pick: String in ["A", "B", "C"]:
		Monster.war_cry = pick
		for voice: String in Monster.CRY_VOICES:
			var cue := Monster.war_cry_cue(voice)
			eq(cue, "cry_%s_%s" % [voice, pick.to_lower()], "%s: %s yells %s" % [pick, voice, cue])
			check(Sfx.CUES.has(cue), "%s is a cue" % cue)
		for other: String in ["archer", "pavise", "goo_imp", "water_boy"]:
			eq(Monster.war_cry_cue(other), "cry_monster", "%s: %s yells the shared cry" % [pick, other])
	check(Sfx.CUES.has("cry_monster"), "cry_monster is a cue")
	Monster.war_cry = "off"
	eq(Monster.war_cry_cue("grunt"), "", "off: no cue")
	new_world(flat_map(22))
	Monster.reset_war_cries()
	var hero := add_hero(Vector2i(-9, 0))
	var pack := _pack("grunt", Vector2i(0, 0), 5)
	await frames(2)
	pack[0].aggro(hero)
	await frames(20)
	eq(_total(pack), 0, "off: a pack's first sight yells nothing")
	_free(pack)
	Monster.war_cry = "A"
	var frozen := _pack("grunt", Vector2i(0, 10), 3)
	for m in frozen:
		m.aggro_range = 0.0
	await frames(2)
	frozen[0].aggro(hero)
	await frames(20)
	eq(_total(frozen), 0, "frozen monsters never yell")
	check(not frozen[0].can_yell(), "... can_yell says so")
	_free(frozen)
	var gob := MonsterFactory.spawn("goblin", Vector2i(10, 0))
	check(not gob.can_yell(), "the goblin scout never yells (his alarm is his own)")
	_free([gob])
	await frames(2)


# --- 6. charging stays rare -------------------------------------------------------------------------------------------------

func _roll_rate() -> void:
	var hits := 0
	var n := 0
	for key in range(1, 201):
		for roll in range(1000, 1100):
			n += 1
			if Monster.charge_roll_hits(key, roll):
				hits += 1
	var rate := float(hits) / n
	print("  charging roll: %d of %d (%.3f, CHARGE_CHANCE %.2f)" % [hits, n, rate, Monster.CHARGE_CHANCE])
	check(absf(rate - Monster.CHARGE_CHANCE) < 0.01, "a charging roll hits about CHARGE_CHANCE of the time (%.3f)" % rate)
	eq(Monster.charge_roll_hits(10042, 77), Monster.charge_roll_hits(10042, 77), "the same key and roll, the same answer")


## A hallway 5 cells wide from x -60 to 6.
func _hall() -> HexMap:
	var m := HexMap.new()
	for x in range(-60, 7):
		for y in range(-2, 3):
			m.set_cell(Vector2i(x - (y >> 1), y), 0)
	return m


func _hallways() -> void:
	var counts: Array[int] = []
	for shift in [0, 3, 7, 12]:
		new_world(_hall())
		Monster.reset_war_cries()
		var spare: Array[Monster] = []
		for i in shift:   # (earlier spawns move the pack's keys along: each run rolls other dice)
			var s := MonsterFactory.spawn("grunt", Vector2i(-60 + i, 2))
			s.aggro_range = 0.0
			s.set_physics_process(false)
			spare.append(s)
		var hero := add_hero(Vector2i(-6, 0))
		var pack: Array[Monster] = []
		for c in Hex.range_cells(Vector2i(2, 0), 2):
			if pack.size() >= 12:
				break
			if GameWorld.map.get_cell(c) == null:
				continue
			var m := MonsterFactory.spawn("grunt", c)
			m.leash_range = 200.0
			m.set_spawn_facing(Vector3.RIGHT)
			pack.append(m)
		await frames(2)
		for m in pack:
			m.aggro(hero)   # (as the gym's hallway packs: every one sent at the crew)
		var charging := 0
		for f in HALL_FRAMES:
			await get_tree().physics_frame
			var front := INF
			for m in pack:
				front = minf(front, m.global_position.x)
			hero.global_position = Vector3(front - 5.0, 0.0, 0.0)   # the crew backs off down the hall: they keep charging
		var chasing := 0
		for m in pack:
			if m.state == Monster.State.CHASE:
				chasing += 1
		charging = _total(pack) - 1
		print("  hallway (keys +%d): %d first-sight cry, %d charging cries in %.0f s; %d of 12 still charging" % [shift, _total(pack) - charging, charging, HALL_FRAMES / 60.0, chasing])
		check(chasing >= 10, "the hallway pack is still charging at the end (%d of 12)" % chasing)
		check(charging <= 5, "a hallway of 12 charging for 10 s is not a choir (%d charging cries)" % charging)
		counts.append(charging)
		_free(pack)
		_free(spare)
		await frames(2)
	var total := 0
	for c in counts:
		total += c
	print("  hallway charging cries: %s, %d in all" % [str(counts), total])
	check(total >= 2 and total <= 16, "over four hallway runs, a couple of charging cries each (%s)" % str(counts))
