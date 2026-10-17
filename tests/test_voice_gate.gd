extends TestCase
## SpeechGate: room hiss and keyboard clicks never reach the recognizer; speech
## opens the gate with its onset intact (pre-roll) and closes with a silent tail.

const RATE := 16000


func setup() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# 1. Two seconds of room hiss: never opens.
	var g := SpeechGate.new()
	var out := g.process(_hiss(2.0, 0.003, rng), RATE)
	check(not g.is_open and _peak(out) == 0.0, "hiss alone stays closed (silence sent)")
	eq(out.size(), int(2.0 * RATE), "closed gate keeps the stream continuous with silence")

	# 2. Fast typing over hiss (10 keys/s, 30 ms clicks, loud): never opens.
	g = SpeechGate.new()
	g.process(_hiss(1.0, 0.003, rng), RATE)  # learn the floor
	out = g.process(_typing(3.0, 10.0, rng), RATE)
	check(_peak(out) == 0.0, "typing never opens the gate (peak leaked %.3f)" % _peak(out))
	check(g.rejected_bursts > 5, "clicks are counted as rejected bursts (%d)" % g.rejected_bursts)

	# 3. A 'word' (sustained voiced tone 0.5 s) opens it, keeps the onset, then closes with a tail.
	g = SpeechGate.new()
	g.process(_hiss(1.0, 0.003, rng), RATE)
	var word := _voiced(0.5, 0.15, rng)
	out = g.process(word, RATE)
	check(g.is_open, "speech opens the gate")
	eq(out.size(), word.size(), "output stays continuous (same length, delayed by the lookahead)")
	check(_peak(out) > 0.05, "speech passes through")
	var after := g.process(_hiss(1.0, 0.003, rng), RATE)
	check(not g.is_open, "gate closes after the hangover")
	var closed_part := after.slice(int(RATE * (SpeechGate.HANGOVER_SEC + SpeechGate.LOOKAHEAD_SEC + 0.1)))
	check(_peak(closed_part) == 0.0, "after the hangover only silence is sent")
	eq(g.opens, 1, "opened once")

	# 4. "cast <0.4 s pause> heal" stays one open span (hangover covers short pauses).
	g = SpeechGate.new()
	g.process(_hiss(1.0, 0.003, rng), RATE)
	g.process(_voiced(0.35, 0.15, rng), RATE)
	g.process(_hiss(0.4, 0.003, rng), RATE)
	g.process(_voiced(0.35, 0.15, rng), RATE)
	eq(g.opens, 1, "a short pause inside an incantation does not re-open")

	# 5. Steady loud hum/fan noise becomes the floor: the gate may open at first,
	#    but closes and stays closed once the floor is learned.
	g = SpeechGate.new()
	var hum := PackedFloat32Array()
	hum.resize(RATE * 8)
	for i in hum.size():
		hum[i] = 0.05 * sin(TAU * 60.0 * i / RATE) + rng.randf_range(-0.03, 0.03)
	g.process(hum.slice(0, RATE * 5), RATE)
	out = g.process(hum.slice(RATE * 5), RATE)
	check(not g.is_open and _peak(out.slice(RATE)) == 0.0, "steady hum is learned as the floor (still open: %s)" % g.is_open)

	# 6. Distant speech (a TV across the room) below min_voice_db never opens;
	#    the same speech up close does.
	g = SpeechGate.new()
	g.min_voice_db = -40.0
	g.process(_hiss(1.0, 0.0005, rng), RATE)
	out = g.process(_voiced(1.0, 0.012, rng), RATE)   # ~ -48 dBFS
	check(_peak(out) == 0.0 and not g.is_open, "quiet background speech stays below the minimum voice level")
	out = g.process(_voiced(0.6, 0.15, rng), RATE)    # ~ -26 dBFS
	check(g.is_open, "the player's voice up close opens the gate")
	g.process(_hiss(1.2, 0.0005, rng), RATE)
	check(g.last_peak_db > -30.0 and g.last_peak_db < -15.0, "last voice peak is reported (%.1f dB)" % g.last_peak_db)

	# 7. Flush on voice end: ~FLUSH_QUIET_SEC after the voice stops, the delay line and FLUSH_PAD_SEC
	#    of comfort noise come out at once; later output is dropped until it is paid back.
	g = SpeechGate.new()
	g.process(_hiss(1.0, 0.0005, rng), RATE)
	var before := g.samples_in
	out = g.process(_voiced(0.5, 0.15, rng), RATE)
	eq(g.flushes, 0, "no flush while speaking")
	var end_at := g.samples_in
	check(absi(g.voice_end_sample - end_at) <= int(0.04 * RATE), "voice end found at the end of the word (%d ms off)" % [
		(g.voice_end_sample - end_at) * 1000 / RATE])
	var tail := g.process(_hiss(0.15, 0.0005, rng), RATE)
	eq(g.flushes, 1, "flushed after the quiet")
	var pad := int(SpeechGate.FLUSH_PAD_SEC * RATE)
	check(tail.size() >= pad, "the flush hands out the pad at once (%d samples for 0.15 s in)" % tail.size())
	var total := out.size() + tail.size()
	total += g.process(_hiss(2.0, 0.0005, rng), RATE).size()
	eq(total, g.samples_in - before, "the pad is paid back while it stays quiet (stream stays real-time)")

	# 8. A pause longer than the quiet time: the second word cancels the debt and still gets through,
	#    onset included; the voice end moves to the second word.
	g = SpeechGate.new()
	g.process(_hiss(1.0, 0.0005, rng), RATE)
	g.process(_voiced(0.35, 0.15, rng), RATE)
	g.process(_hiss(0.3, 0.0005, rng), RATE)
	eq(g.flushes, 1, "a 0.3 s pause flushes the first word")
	var first_end := g.voice_end_sample
	out = g.process(_voiced(0.35, 0.15, rng), RATE)
	out.append_array(g.process(_hiss(0.05, 0.0005, rng), RATE))
	check(_peak(out) > 0.05, "the second word is not dropped (peak %.3f)" % _peak(out))
	check(g.voice_end_sample > first_end + int(0.3 * RATE), "voice end follows the second word")

	# 9. A quiet ending (a soft "th" 10 dB under the loud word) counts as voice: the end and the
	#    flush wait for it instead of replacing it with padding.
	g = SpeechGate.new()
	g.process(_hiss(1.0, 0.0005, rng), RATE)
	g.process(_voiced(0.4, 0.15, rng), RATE)
	var loud_end := g.samples_in
	g.process(_hiss(0.12, 0.012, rng), RATE)          # ~ -44 dBFS: under the voice rule, over the soft one
	check(g.voice_end_sample >= loud_end + int(0.1 * RATE), "soft ending extends the voice (%d ms past the loud part)" % [
		(g.voice_end_sample - loud_end) * 1000 / RATE])
	eq(g.flushes, 0, "no flush during the soft ending")
	g.process(_hiss(0.2, 0.0005, rng), RATE)
	eq(g.flushes, 1, "flush once it is really quiet")

	# 10. Flush off: same length in and out, no flushes, voice end still tracked.
	g = SpeechGate.new()
	g.flush_on_end = false
	g.process(_hiss(0.5, 0.0005, rng), RATE)
	var w := g.process(_voiced(0.4, 0.15, rng), RATE)
	w.append_array(g.process(_hiss(1.0, 0.0005, rng), RATE))
	eq(w.size(), int(1.4 * RATE), "flush off keeps the stream the same length")
	check(g.flushes == 0 and g.voice_end_sample > 0, "flush off: no flushes, end of voice still found")

	# 11. Disabled gate is a pass-through.
	g = SpeechGate.new()
	g.enabled = false
	var hiss := _hiss(0.5, 0.003, rng)
	eq(g.process(hiss, RATE).size(), hiss.size(), "disabled gate passes everything")
	finish()


## Peak above the gate's comfort-noise level (0 = only comfort noise was sent).
func _peak(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, absf(v))
	return 0.0 if m <= SpeechGate.COMFORT_RMS * 1.8 else m


func _hiss(sec: float, amp: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(sec * RATE))
	for i in a.size():
		a[i] = rng.randf_range(-amp, amp)
	return a


## Keyboard: short decaying broadband bursts at `rate` per second over hiss.
func _typing(sec: float, keys_per_sec: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var a := _hiss(sec, 0.003, rng)
	var t := 0.05
	while t < sec - 0.05:
		var start := int(t * RATE)
		var length := int(0.03 * RATE)
		for i in length:
			var env := exp(-float(i) / (0.006 * RATE))
			a[start + i] += rng.randf_range(-0.35, 0.35) * env
		t += 1.0 / keys_per_sec * rng.randf_range(0.6, 1.4)
	return a


## Voiced speech stand-in: a 140 Hz harmonic tone with a slow syllable envelope.
func _voiced(sec: float, amp: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(sec * RATE))
	for i in a.size():
		var t := float(i) / RATE
		var env := clampf(t / 0.03, 0.0, 1.0) * clampf((sec - t) / 0.03, 0.0, 1.0)
		var v := sin(TAU * 140.0 * t) + 0.5 * sin(TAU * 280.0 * t) + 0.3 * sin(TAU * 420.0 * t)
		a[i] = amp * env * v / 1.8 + rng.randf_range(-0.003, 0.003)
	return a
