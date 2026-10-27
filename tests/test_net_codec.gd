extends TestCase
## M2, single process: the hero snapshot codec (scripts/net/net_codec.gd).
## - the bytes: a snapshot to the host is 24 bytes, the host's to a client 40 (16 per hero, 17 with the bow drawn),
##   far inside the plan's 3 KB/s per client at 30 Hz;
## - randomised round trips (pack, unpack) come back equal within one quantum, ranges clamp, ages restore the sample time;
## - malformed packets give what was complete and never crash;
## - EVERY var in NetCodec.HERO_FIELDS survives a hero -> bytes -> hero round trip (the test names them all, so a field added
##   to the codec without a test here fails), including dying once and the bow.

## The Hero / Actor vars this test round-trips. Must equal NetCodec.HERO_FIELDS' keys.
const TESTED := ["hp", "dead", "facing", "climbing", "pass_through_until", "held_slot", "_draw_start", "zombie"]

var root: Node3D


func setup() -> void:
	root = Node3D.new()
	add_child(root)
	_check_sizes()
	_check_round_trips()
	_check_clamps_and_ages()
	_check_malformed()
	_check_hero_fields()
	finish()


func _state(rng: RandomNumberGenerator, seat: int) -> NetHeroState:
	var s := NetHeroState.new()
	s.seat = seat
	s.t = rng.randf_range(0.0, 2000.0)
	s.pos = Vector3(rng.randf_range(-250.0, 250.0), rng.randf_range(-3.0, 12.0), rng.randf_range(-250.0, 250.0))
	s.vel = Vector2(rng.randf_range(-15.0, 15.0), rng.randf_range(-15.0, 15.0))
	s.angle = rng.randf_range(0.0, TAU)
	s.aim = Vector2(rng.randf_range(-31.0, 31.0), rng.randf_range(-31.0, 31.0))
	s.hp = rng.randf_range(0.0, 160.0)
	s.held_slot = rng.randi_range(0, 3)
	s.dead = rng.randf() < 0.2
	s.climbing = rng.randf() < 0.3
	s.ghost = rng.randf() < 0.3
	s.drawing = rng.randf() < 0.3
	s.draw_age = rng.randf_range(0.0, 2.5) if s.drawing else 0.0
	s.tp = rng.randi_range(0, 15)
	s.epoch = rng.randi_range(0, 15)
	return s


func _check_sizes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var s := _state(rng, 2)
	s.drawing = false
	var one: Array[NetHeroState] = [s]
	eq(NetCodec.encode(one, s.t).size() + NetWire.HEADER, 24, "a client's snapshot (one hero) is 24 bytes on the wire")
	eq(NetCodec.packet_size(one), 24, "packet_size agrees")
	var two: Array[NetHeroState] = [s, _state(rng, 3)]
	two[1].drawing = false
	eq(NetCodec.packet_size(two), 40, "the host's snapshot to a client (two heroes) is 40 bytes")
	two[1].drawing = true
	eq(NetCodec.encode(two, s.t).size() + NetWire.HEADER, NetCodec.packet_size(two), "the bow drawn costs one byte and packet_size knows")
	var per_second := float(NetCodec.packet_size(two)) * NetSnapshot.SEND_RATE
	check(per_second < 3000.0 / 2.0, "the host's stream to one client is %.0f B/s, well inside the 3 KB/s budget" % per_second)
	check(float(NetCodec.packet_size(one)) * NetSnapshot.SEND_RATE < 1000.0, "a client's stream is under 1 KB/s")


func _check_round_trips() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := {"pos": 0.0, "vel": 0.0, "angle": 0.0, "aim": 0.0, "hp": 0.0, "draw": 0.0, "time": 0.0}
	for i in 400:
		var s := _state(rng, rng.randi_range(1, 3))
		var sent := s.t + rng.randf_range(0.0, 0.2)   # an age of up to 200 ms (a forwarded state)
		var one: Array[NetHeroState] = [s]
		var out := NetCodec.decode(NetCodec.encode(one, sent), sent)
		if not check(out.size() == 1, "round trip %d keeps the entry" % i):
			continue
		var d := out[0]
		eq(d.seat, s.seat, "seat")
		eq(d.held_slot, s.held_slot, "held slot")
		eq(d.dead, s.dead, "dead")
		eq(d.climbing, s.climbing, "climbing")
		eq(d.ghost, s.ghost, "ghost")
		eq(d.drawing, s.drawing, "drawing")
		eq(d.tp, s.tp, "teleport counter")
		eq(d.epoch, s.epoch, "ownership epoch (M6, in the flags byte: no extra byte)")
		worst["pos"] = maxf(float(worst["pos"]), maxf(absf(d.pos.x - s.pos.x), maxf(absf(d.pos.y - s.pos.y), absf(d.pos.z - s.pos.z))))
		worst["vel"] = maxf(float(worst["vel"]), maxf(absf(d.vel.x - s.vel.x), absf(d.vel.y - s.vel.y)))
		worst["angle"] = maxf(float(worst["angle"]), absf(angle_difference(d.angle, s.angle)))
		worst["aim"] = maxf(float(worst["aim"]), maxf(absf(d.aim.x - s.aim.x), absf(d.aim.y - s.aim.y)))
		worst["hp"] = maxf(float(worst["hp"]), absf(d.hp - s.hp))
		worst["draw"] = maxf(float(worst["draw"]), absf(d.draw_age - s.draw_age))
		worst["time"] = maxf(float(worst["time"]), absf(d.t - s.t))
	check(float(worst["pos"]) <= NetCodec.quantum("position") + 0.0001, "position within %.3f (worst %.4f)" % [NetCodec.quantum("position"), float(worst["pos"])])
	check(float(worst["vel"]) <= NetCodec.quantum("velocity") + 0.0001, "velocity within %.3f (worst %.4f)" % [NetCodec.quantum("velocity"), float(worst["vel"])])
	check(float(worst["angle"]) <= NetCodec.quantum("angle") + 0.0001, "facing within %.4f rad (worst %.4f)" % [NetCodec.quantum("angle"), float(worst["angle"])])
	check(float(worst["aim"]) <= NetCodec.quantum("aim") + 0.0001, "aim within %.3f (worst %.4f)" % [NetCodec.quantum("aim"), float(worst["aim"])])
	check(float(worst["hp"]) <= NetCodec.quantum("hp") + 0.0001, "hp within %.2f (worst %.4f)" % [NetCodec.quantum("hp"), float(worst["hp"])])
	check(float(worst["draw"]) <= NetCodec.quantum("draw") + 0.0001, "the bow draw within %.3f s (worst %.4f)" % [NetCodec.quantum("draw"), float(worst["draw"])])
	check(float(worst["time"]) <= NetCodec.quantum("time") + 0.0001, "sample time within %.4f s (worst %.4f)" % [NetCodec.quantum("time"), float(worst["time"])])


func _check_clamps_and_ages() -> void:
	var s := NetHeroState.new()
	s.seat = 1
	s.t = 100.0
	s.pos = Vector3(900.0, -900.0, -900.0)
	s.vel = Vector2(80.0, -80.0)
	s.aim = Vector2(500.0, -500.0)
	s.hp = 999999.0
	var one: Array[NetHeroState] = [s]
	var d := NetCodec.decode(NetCodec.encode(one, 100.0), 100.0)[0]
	near(d.pos.x, NetCodec.POS_MAX, 0.01, "a position past the map edge clamps (x)")
	near(d.pos.y, -327.68, 0.01, "... and y")
	near(d.vel.x, NetCodec.VEL_MAX, 0.01, "a velocity past the range clamps")
	near(d.vel.y, -NetCodec.VEL_MAX, 0.01, "... both ways")
	near(d.aim.x, NetCodec.AIM_MAX, 0.01, "an aim point far away clamps to the aim range")
	near(d.hp, NetCodec.HP_MAX, 0.1, "hp clamps at the field's top (15 bits: the top one is the zombie flag)")
	check(not d.zombie, "... and a huge hp never reads as a zombie")
	# The coffee zombie (Hero.zombie) rides the hp field's top bit: both ways, with the hp intact.
	s.hp = 10.0
	s.zombie = true
	var z := NetCodec.decode(NetCodec.encode(one, 100.0), 100.0)[0]
	check(z.zombie, "a zombie reads back as a zombie")
	near(z.hp, 10.0, NetCodec.quantum("hp"), "... with its hp")
	s.zombie = false
	check(not NetCodec.decode(NetCodec.encode(one, 100.0), 100.0)[0].zombie, "and a hero who is not one, not")
	eq(NetCodec.HERO_FIELDS.get("zombie", ""), "hp", "the zombie flag is a hero snapshot field (the hp field)")
	# A forwarded state keeps its own moment: sample time = packet stamp - age.
	s.pos = Vector3.ZERO
	s.vel = Vector2.ZERO
	s.aim = Vector2.ZERO
	s.hp = 50.0
	s.t = 99.88
	var fwd := NetCodec.decode(NetCodec.encode(one, 100.0), 100.0)[0]
	near(fwd.t, 99.88, 0.001, "an age of 120 ms restores the sample time")
	s.t = 90.0
	near(NetCodec.decode(NetCodec.encode(one, 100.0), 100.0)[0].t, 99.745, 0.001, "an age past 255 ms saturates")
	s.t = 100.5
	near(NetCodec.decode(NetCodec.encode(one, 100.0), 100.0)[0].t, 100.0, 0.001, "a sample from the future is stamped now (age 0)")


func _check_malformed() -> void:
	eq(NetCodec.decode(PackedByteArray(), 1.0).size(), 0, "an empty payload decodes to nothing")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var a := _state(rng, 1)
	var b := _state(rng, 2)
	a.drawing = false
	b.drawing = false
	var two: Array[NetHeroState] = [a, b]
	var full := NetCodec.encode(two, 5.0)
	eq(NetCodec.decode(full, 5.0).size(), 2, "both entries decode")
	eq(NetCodec.decode(full.slice(0, 1 + NetCodec.ENTRY_SIZE + 5), 5.0).size(), 1, "a packet cut inside the second entry gives the first")
	var lying := full.duplicate()
	lying[0] = 9
	eq(NetCodec.decode(lying, 5.0).size(), 2, "a count that lies is bounded by the bytes there")
	var bad_seat := full.duplicate()
	bad_seat[1] = bad_seat[1] & 0xFC    # seat 0
	eq(NetCodec.decode(bad_seat, 5.0).size(), 1, "an entry with seat 0 is skipped")
	var junk := PackedByteArray()
	for i in 200:
		junk.append(rng.randi_range(0, 255))
	var n := NetCodec.decode(junk, 1.0).size()
	check(n >= 0 and n <= 12, "random bytes decode to nothing worse than a few entries, without a crash (%d)" % n)


func _hero(hero_name: String) -> Hero:
	var h := Hero.new()
	h.display_name = hero_name
	root.add_child(h)
	return h


func _check_hero_fields() -> void:
	var fields := (_hero("probe") as Hero).net_fields()
	var carried := NetCodec.HERO_FIELDS.keys()
	carried.sort()
	var tested: Array = TESTED.duplicate()
	tested.sort()
	eq(carried, tested, "this test round-trips exactly the codec's HERO_FIELDS")
	for f: String in NetCodec.HERO_FIELDS:
		check(fields.has(f) and int(fields[f]) == Net.OWNER, "%s is an OWNER var of Hero (a codec streams nothing else)" % f)

	var a := _hero("sender")
	var b := _hero("receiver")
	a.spell_slots = ["heal", "corn", "fireball"]
	b.spell_slots = ["heal", "corn", "fireball"]
	GameWorld.time = 50.0
	a.hp = 37.3
	a.facing = Vector3(0.6, 0.0, -0.8)
	a.climbing = true
	a.pass_through_until = GameWorld.time + 1.0
	a.held_slot = 2
	a._draw_start = GameWorld.time - 0.4
	var st := NetHeroState.new()
	st.seat = 2
	st.pos = Vector3(3.0, 1.0, 4.0)
	NetCodec.read_hero(a, st)
	var back := _through_wire(st)
	NetCodec.write_hero(b, back)
	near(b.hp, 37.3, 0.05, "hp arrives")
	near(atan2(b.facing.z, b.facing.x), atan2(a.facing.z, a.facing.x), NetCodec.quantum("angle"), "facing arrives")
	check(b.climbing, "climbing arrives")
	check(b.pass_through_until > GameWorld.time, "passing through arrives (ghost)")
	eq(b.held_slot, 2, "the held slot arrives")
	check(b.is_drawing(), "the bow drawn arrives")
	near(GameWorld.time - b._draw_start, 0.4, 0.02, "... with how long it has been drawn")
	check(not b.dead, "alive stays alive")
	# Everything back to rest: the receiver follows (the bow comes down, the ghost ends, the climb ends).
	a.climbing = false
	a.pass_through_until = 0.0
	a.cancel_draw()
	NetCodec.read_hero(a, st)
	NetCodec.write_hero(b, _through_wire(st))
	check(not b.climbing and b.pass_through_until <= GameWorld.time and not b.is_drawing(), "the climb, the ghost and the bow end on the receiver too")
	# Dying: once, with the signals and the downed look.
	var deaths := [0, 0]
	b.died.connect(func() -> void: deaths[0] += 1)
	var on_died := func(_who: Actor) -> void: deaths[1] += 1
	GameWorld.actor_died.connect(on_died)
	a.hp = 0.0
	a.dead = true
	NetCodec.read_hero(a, st)
	var dead_state := _through_wire(st)
	NetCodec.write_hero(b, dead_state)
	NetCodec.write_hero(b, dead_state)
	check(b.dead and b.hp == 0.0, "death arrives")
	eq(deaths, [1, 1], "and fires died / actor_died once, however often the state repeats")
	GameWorld.actor_died.disconnect(on_died)
	# Back up (a coffee: Actor.revive on the owner): standing, gray, at its HP; once, however often the state repeats.
	var ups := []
	b.revived.connect(func(cursed: bool) -> void: ups.append(cursed))
	a.dead = false
	a.hp = 10.0
	a.zombie = true
	NetCodec.read_hero(a, st)
	var up_state := _through_wire(st)
	NetCodec.write_hero(b, up_state)
	NetCodec.write_hero(b, up_state)
	check(not b.dead and b.zombie, "standing back up arrives, as a zombie")
	near(b.hp, 10.0, 0.05, "... at its HP")
	eq(ups, [true], "revived fires once (cursed)")
	# The curse lifts on the owner (healed past three quarters): the receiver's gray goes too.
	a.hp = 80.0
	a.zombie = false
	NetCodec.read_hero(a, st)
	NetCodec.write_hero(b, _through_wire(st))
	check(not b.zombie and not b.dead, "the cure arrives")
	near(b.hp, 80.0, 0.05, "... with the HP")


## A state packed into a packet and unpacked again.
func _through_wire(st: NetHeroState) -> NetHeroState:
	var one: Array[NetHeroState] = [st]
	return NetCodec.decode(NetCodec.encode(one, 1.0), 1.0)[0]
