extends TestCase
## Regression for the 2026-10-17 playtest: the mic stopped delivering and AudioStreamMicrophone
## replayed its 4 s ring buffer on a loop, so the recognizer heard the same old words forever
## ("BRIGHT OVATER" every 8 s). VoiceCaster now reads the device directly with a stall watchdog
## (tools/mic_probe.gd shows both paths on a real mic); this checks the gate's repeat guard, the
## backstop that keeps replayed audio away from the recognizer and tells the caster to restart.

const RATE := 48000
const RING := RATE * 4            ## Godot's input ring buffer: 192000 frames = 4 s

var _rng := RandomNumberGenerator.new()


func setup() -> void:
	_rng.seed = 7
	var live := _speechish(RATE * 6)

	# Live audio never trips it, however long.
	var g := _gate()
	_feed(g, live)
	check(not g.is_stale, "unique live audio is not stale")
	eq(g.repeated_frames, 0, "no repeats in live audio")
	check(g.opens > 3, "live speech opens the gate (%d)" % g.opens)
	check(g.flushes >= 3, "word ends are flushed (%d), and the padding is never taken for a repeat" % g.flushes)
	var flushes_live := g.flushes

	# Ring replay, aligned with the live frames: caught after ~0.2 s of replayed words (the replay
	# may start in a gap, so allow 1.5 s), nothing loud gets out after.
	var ring := live.slice(live.size() - RING)
	var out := _feed(g, ring.slice(0, RATE * 3 / 2))
	check(g.flushes <= flushes_live + 1, "replayed words start no voice spans to flush (%d new)" % (g.flushes - flushes_live))
	check(g.is_stale, "replay flagged stale within 1.5 s")
	out = _feed(g, ring.slice(RATE * 3 / 2))
	check(_peak_db(out) < -60.0, "replayed audio does not reach the recognizer (peak %.0f dB)" % _peak_db(out))
	check(g.repeated_frames > 100, "repeats counted (%d)" % g.repeated_frames)
	check(not g.is_open, "gate stays closed on a replay")
	check(g.describe().contains("STALE"), "debug line says STALE")

	# The caster restarts the device and resets the gate: fresh speech passes again.
	g.reset()
	check(not g.is_stale, "reset clears stale")
	out = _feed(g, _speechish(RATE * 3))
	check(not g.is_stale, "fresh audio after the restart is fine")
	check(_peak_db(out) > -30.0, "fresh speech passes (peak %.0f dB)" % _peak_db(out))

	# A replay that starts mid-frame: the first loop is new to the guard, the second matches the
	# first (the ring is a whole number of 10 ms frames), so it is caught one loop later.
	var g2 := _gate()
	_feed(g2, live.slice(0, RATE * 5 + 123))
	_feed(g2, ring)
	_feed(g2, ring.slice(0, RATE * 3 / 2))
	check(g2.is_stale, "unaligned replay caught by the second loop")
	out = _feed(g2, ring.slice(RATE * 3 / 2))
	check(_peak_db(out) < -60.0, "...and silenced (peak %.0f dB)" % _peak_db(out))

	# Off (tests feeding the same WAV twice, typed play): repeats pass untouched.
	var g3 := SpeechGate.new()
	_feed(g3, live)
	_feed(g3, ring)
	check(not g3.is_stale and g3.repeated_frames == 0, "guard off: no stale detection")
	finish()


func _gate() -> SpeechGate:
	var g := SpeechGate.new()
	g.repeat_guard = true
	return g


## Feeds in uneven chunks, like a game frame loop does.
func _feed(g: SpeechGate, a: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var pos := 0
	while pos < a.size():
		var n := mini(a.size() - pos, _rng.randi_range(500, 1700))
		out.append_array(g.process(a.slice(pos, pos + n), RATE))
		pos += n
	return out


## Word-sized bursts of loud noise (~-20 dB) with quiet gaps, unique sample for sample.
func _speechish(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	var i := 0
	while i < n:
		var word := _rng.randi_range(int(RATE * 0.25), int(RATE * 0.6))
		for k in range(i, mini(n, i + word)):
			a[k] = _rng.randf_range(-0.17, 0.17)
		i += word
		var gap := _rng.randi_range(int(RATE * 0.7), int(RATE * 1.1))
		for k in range(i, mini(n, i + gap)):
			a[k] = _rng.randf_range(-0.0005, 0.0005)
		i += gap
	return a


func _peak_db(a: PackedFloat32Array) -> float:
	var best := 0.0
	var e := 0.0
	for k in a.size():
		e += a[k] * a[k]
		if k % 480 == 479:
			best = maxf(best, e / 480.0)
			e = 0.0
	return SpeechGate.db(best)
