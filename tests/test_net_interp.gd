extends TestCase
## M2, single process: the interpolation buffer behind a puppet (scripts/net/net_interp.gd) against a hero whose true path
## is known exactly. A hero walks a zig-zag at 4.5 u/s with stops (a corner every half second, like a hex path), is
## sampled at 30 Hz through the REAL codec (so the wire's quantisation is in), and the samples reach the viewer the way
## ENet + the link simulator deliver them: late by the link's delay and jitter, out of order when the jitter is larger
## than the send interval (the wire drops a sample that is not newer), and some lost. A 60 Hz render loop shows the
## puppet at `now - delay` and is compared with where the hero REALLY was at that time.
##
## - `coast` (45 +- 15 ms, 1.5% loss) direct: within 0.35 units of the truth, never a frame step over 0.6, delay 100 ms;
## - the same hero forwarded through the host (two hops: about 150 ms late): the delay grows by itself and the error holds;
## - `rough` (80 +- 30 ms, 4% loss) and a burst of 6 lost packets: no snapping beyond 0.6;
## - a teleport never blends across the gap; silence holds the hero (it does not run away); the first samples set the delay;
##   a sample that is not newer is refused.

const SPEED := 4.5
const DT := 1.0 / 60.0
const SEND := 1.0 / 30.0

var _legs: Array = []   ## [t0, t1, dir (Vector2), speed]


func setup() -> void:
	_build_path(12345, 40.0)
	_check_basics()
	var r := _run("coast", 0.045, 0.015, 0.015, 0.0, 30.0)
	_report("coast direct", r)
	check(float(r["max_err"]) <= 0.35, "coast, direct: the puppet stays within 0.35 of the truth (%.3f)" % float(r["max_err"]))
	check(float(r["max_step"]) <= 0.6, "coast, direct: no frame step over 0.6 (%.3f)" % float(r["max_step"]))
	near(float(r["delay"]), NetInterp.DELAY, 0.02, "coast, direct: the delay stays about 100 ms")
	var f := _run("forwarded", 0.150, 0.030, 0.015, 0.0, 30.0)
	_report("coast forwarded", f)
	check(float(f["max_err"]) <= 0.35, "coast, forwarded through the host: within 0.35 (%.3f)" % float(f["max_err"]))
	check(float(f["max_step"]) <= 0.6, "forwarded: no frame step over 0.6 (%.3f)" % float(f["max_step"]))
	check(float(f["delay"]) > 0.15 and float(f["delay"]) <= NetInterp.DELAY_MAX, "forwarded: the delay grew to cover the extra hop (%.3f)" % float(f["delay"]))
	var rough := _run("rough", 0.080, 0.030, 0.04, 0.0, 30.0)
	_report("rough", rough)
	check(float(rough["max_err"]) <= 0.5, "rough: within 0.5 (%.3f)" % float(rough["max_err"]))
	check(float(rough["max_step"]) <= 0.6, "rough: no frame step over 0.6 (%.3f)" % float(rough["max_step"]))
	var burst := _run("burst", 0.045, 0.015, 0.0, 12.0, 30.0)   # six packets in a row lost at t = 12 s
	_report("burst of loss", burst)
	check(float(burst["max_err"]) <= 0.6, "six packets lost in a row: within 0.6 (%.3f)" % float(burst["max_err"]))
	check(float(burst["max_step"]) <= 0.6, "... and no snap (%.3f)" % float(burst["max_step"]))
	var clean := _run("off", 0.0, 0.0, 0.0, 0.0, 30.0)
	check(float(clean["max_err"]) <= 0.1, "a perfect link is exact to a hair (%.3f)" % float(clean["max_err"]))
	_check_teleport()
	_check_silence()
	finish()


# --- The true path ------------------------------------------------------------------------------------

## Legs of 0.2-0.7 s in a random direction (60 degree turns), a stop now and then.
func _build_path(seed_value: int, length: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_legs = []
	var t := 0.0
	var angle := 0.0
	while t < length:
		var dur := rng.randf_range(0.2, 0.7)
		var speed := SPEED if rng.randf() > 0.12 else 0.0
		angle += float(rng.randi_range(-1, 1)) * PI / 3.0
		_legs.append([t, t + dur, Vector2(cos(angle), sin(angle)), speed])
		t += dur


func _truth(t: float) -> Vector2:
	var p := Vector2.ZERO
	for leg: Array in _legs:
		var t0: float = leg[0]
		var t1: float = leg[1]
		var d: Vector2 = leg[2]
		var v: float = leg[3]
		if t >= t1:
			p += d * v * (t1 - t0)
		else:
			if t > t0:
				p += d * v * (t - t0)
			break
	return p



# --- The simulated stream --------------------------------------------------------------------------------

## Samples at 30 Hz through the codec, delivered after `lag` +- `jitter` (frame-quantised), `loss` of them lost, and
## six in a row at `burst_at` if given. Renders at 60 Hz from `from_t` for `span` seconds.
func _run(label: String, lag: float, jitter: float, loss: float, burst_at: float, span: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(label)
	var arrivals: Array = []   # [arrival, NetHeroState]
	var k := 0
	while float(k) * SEND < span + 2.0:
		var t := float(k) * SEND
		k += 1
		if burst_at > 0.0 and t >= burst_at and t < burst_at + 6.0 * SEND:
			continue
		if loss > 0.0 and rng.randf() < loss:
			continue
		var s := NetHeroState.new()
		s.seat = 2
		s.t = t
		var p := _truth(t - DT)   # (the velocity the sender measured is the last physics frame's)
		var q := _truth(t)
		s.pos = Vector3(q.x, 0.0, q.y)
		s.vel = (q - p) / DT
		s.angle = s.vel.angle() if s.vel.length() > 0.1 else 0.0
		var one: Array[NetHeroState] = [s]
		var wire := NetCodec.decode(NetCodec.encode(one, t), t)[0]
		var delay_s := maxf(lag + rng.randf_range(-jitter, jitter), 0.0)
		arrivals.append([t + delay_s + rng.randf_range(0.0, DT), wire])
	arrivals.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var it := NetInterp.new()
	var max_err := 0.0
	var max_step := 0.0
	var prev := Vector3.INF
	var ai := 0
	var now := 1.0
	var end := span
	var frames_shown := 0
	while now < end:
		while ai < arrivals.size() and float(arrivals[ai][0]) <= now:
			it.push(arrivals[ai][1] as NetHeroState, float(arrivals[ai][0]))
			ai += 1
		it.step_delay(DT)
		var t_r := now - it.delay
		var st := it.sample(t_r)
		if st != null and now > 3.0:   # (the first seconds fill the buffer)
			var truth := _truth(t_r)
			max_err = maxf(max_err, Vector2(st.pos.x, st.pos.z).distance_to(truth))
			if prev != Vector3.INF:
				max_step = maxf(max_step, st.pos.distance_to(prev))
			frames_shown += 1
		if st != null:
			prev = st.pos
		now += DT
	return {"max_err": max_err, "max_step": max_step, "delay": it.delay, "refused": it.refused, "accepted": it.accepted, "frames": frames_shown}


func _report(label: String, r: Dictionary) -> void:
	print("[interp] %-14s err %.3f  step %.3f  delay %.3f  accepted %d refused %d" % [label, float(r["max_err"]), float(r["max_step"]), float(r["delay"]), int(r["accepted"]), int(r["refused"])])


# --- Single behaviours ------------------------------------------------------------------------------------

func _sample(t: float, x: float, vx: float = 0.0, tp: int = 0) -> NetHeroState:
	var s := NetHeroState.new()
	s.seat = 1
	s.t = t
	s.pos = Vector3(x, 0.0, 0.0)
	s.vel = Vector2(vx, 0.0)
	s.tp = tp
	return s


func _check_basics() -> void:
	var it := NetInterp.new()
	check(it.sample(1.0) == null, "no samples, nothing to show")
	check(it.push(_sample(1.0, 0.0, 4.0), 1.05), "the first sample is accepted")
	check(not it.push(_sample(1.0, 9.0), 1.06), "a sample with the same time is refused")
	check(not it.push(_sample(0.9, 9.0), 1.06), "an older sample is refused (a reordered packet)")
	check(it.push(_sample(1.1, 0.4, 4.0), 1.15), "a newer one is accepted")
	eq(it.refused, 2, "two refusals counted")
	near(it.sample(0.5).pos.x, 0.0, 0.0001, "before the first sample the hero is held at the first")
	near(it.sample(1.05).pos.x, 0.2, 0.01, "halfway between two samples with consistent velocity: halfway")
	near(it.sample(1.1).pos.x, 0.4, 0.001, "exactly at a sample: that sample")
	near(it.sample(1.2).pos.x, 0.4 + 4.0 * 0.1, 0.001, "past the newest sample: along the last velocity")
	near(it.sample(5.0).pos.x, 0.4 + 4.0 * NetInterp.EXTRAP_MAX, 0.001, "... but no more than EXTRAP_MAX of it")
	# Hermite follows the velocity: samples 0.2 s apart with a bend in the velocity are not a straight line.
	var h := NetInterp.new()
	h.push(_sample(0.0, 0.0, 10.0), 0.0)
	h.push(_sample(0.2, 1.0, 0.0), 0.2)
	var mid := h.sample(0.1).pos.x
	check(mid > 0.7 and mid < 0.8, "Hermite bends toward the velocities: a hero slowing from 10 to 0 is well past the midpoint (%.3f)" % mid)
	var linear := NetInterp.new()
	linear.push(_sample(0.0, 0.0, 10.0), 0.0)
	linear.push(_sample(0.5, 1.0, 0.0), 0.5)
	near(linear.sample(0.25).pos.x, 0.5, 0.0001, "samples more than LINEAR_GAP apart (a stall) are blended straight")
	# The delay: warmup sets it, the lag raises it, the slew is gentle.
	var d := NetInterp.new()
	for i in 6:
		d.push(_sample(float(i) * SEND, 0.0), float(i) * SEND + 0.2)
	near(d.delay, 0.2 + NetInterp.MARGIN, 0.005, "the first samples set the delay outright from their lag")
	for i in range(6, 90):
		d.push(_sample(float(i) * SEND, 0.0), float(i) * SEND + 0.02)
	var before := d.delay
	d.step_delay(1.0)
	near(before - d.delay, NetInterp.SLEW, 0.001, "once the lag is gone the delay comes back at SLEW per second, not at once")
	d.clear()
	near(d.delay, NetInterp.DELAY, 0.0001, "clear() resets the delay")
	# Pose details ride the earlier sample as a step.
	var st := NetInterp.new()
	var a := _sample(0.0, 0.0)
	a.hp = 50.0
	var b := _sample(0.2, 1.0)
	b.hp = 30.0
	b.dead = true
	st.push(a, 0.0)
	st.push(b, 0.2)
	check(not st.sample(0.19).dead and near(st.sample(0.19).hp, 50.0, 0.001), "hp and death are a step: the earlier sample until the later one is reached")
	check(st.sample(0.2).dead, "... and the later one from then on")
	# Facing takes the short way round the circle.
	var f := NetInterp.new()
	var f0 := _sample(0.0, 0.0)
	f0.angle = TAU - 0.1
	var f1 := _sample(0.1, 0.0)
	f1.angle = 0.1
	f.push(f0, 0.0)
	f.push(f1, 0.1)
	near(angle_difference(f.sample(0.05).angle, 0.0), 0.0, 0.01, "facing goes the short way across the wrap")


func _check_teleport() -> void:
	var it := NetInterp.new()
	var now := 0.0
	var stray := 0
	var jumps := 0
	var prev := 0.0
	var tp := 0
	var x := 0.0
	var k := 0
	while now < 4.0:
		var t_s := float(k) * SEND
		if t_s <= now - 0.045:   # samples arrive 45 ms late
			x += 4.5 * SEND
			if k == 60:   # 2 s: the hero jumps 40 units
				x += 40.0
				tp = 1
			it.push(_sample(t_s, x, 4.5, tp), t_s + 0.045)
			k += 1
			continue
		it.step_delay(DT)
		var s := it.sample(now - it.delay)
		if s != null and now > 1.0:
			var px := s.pos.x
			if prev != 0.0 and absf(px - prev) > 5.0:
				jumps += 1
			prev = px
			# Before the jump the hero is below 9 + 4.5 * 2.5; after, above 40. Nothing may sit in between.
			if px > 20.0 and px < 40.0:
				stray += 1
		now += DT
	eq(it.teleports, 1, "the stream saw one teleport")
	eq(jumps, 1, "the puppet jumped once, in one frame")
	eq(stray, 0, "and never showed a position on the way across the 40 units")


func _check_silence() -> void:
	var it := NetInterp.new()
	for i in 10:
		it.push(_sample(float(i) * SEND, float(i) * SEND * 4.5, 4.5), float(i) * SEND + 0.045)
	var held := it.sample(0.3 + 0.5).pos.x
	var much_later := it.sample(0.3 + 30.0).pos.x
	near(held, much_later, 0.0001, "a hero that goes silent is held after EXTRAP_MAX, it does not run away")
