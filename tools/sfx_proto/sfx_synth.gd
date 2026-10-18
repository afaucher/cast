extends RefCounted
## Prototype procedural sound effects (docs/design/audio-plan.md, "Procedural option").
## Every recipe returns mono float samples in [-1, 1] at RATE; `to_wav` wraps them in an AudioStreamWAV (16-bit),
## which a game can play directly or `save_to_wav` writes to disk. Noise comes from a RandomNumberGenerator seeded
## per recipe, so every run makes the same file (and no global randomness is used).
## Prototype only: not loaded by the game. If a recipe is kept, it moves to scripts/fx/ (cosmetic, fx_rng-free since
## it is seeded locally) and is baked once at boot or offline.

const RATE := 44100

var _rng := RandomNumberGenerator.new()


# ---------------------------------------------------------------- building blocks

func _n(sec: float) -> int:
	return int(sec * RATE)


func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(_n(sec))
	return b


## Attack/decay envelope: linear attack, exponential decay with time constant `tau` (seconds).
func _env(t: float, attack: float, tau: float) -> float:
	if t < attack:
		return t / maxf(attack, 1e-5)
	return exp(-(t - attack) / tau)


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


## Adds a sine whose frequency glides from f0 to f1 (exponentially) over `len`, with an attack/decay envelope.
func _add_glide(out: PackedFloat32Array, start: float, length: float, f0: float, f1: float, amp: float,
		attack: float, tau: float, vib_hz: float = 0.0, vib_depth: float = 0.0) -> void:
	var i0 := _n(start)
	var n := mini(_n(length), out.size() - i0)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / length
		var f := f0 * pow(f1 / f0, k)
		if vib_hz > 0.0:
			f *= 1.0 + vib_depth * sin(TAU * vib_hz * t)
		phase += TAU * f / RATE
		out[i0 + i] += amp * sin(phase) * _env(t, attack, tau)


## A struck bell / glass: inharmonic partials, each decaying at its own rate (higher ones faster).
func _add_bell(out: PackedFloat32Array, start: float, f: float, amp: float, tau: float,
		ratios: Array = [1.0, 2.0, 2.76, 4.07, 5.4], gains: Array = [1.0, 0.45, 0.3, 0.18, 0.1]) -> void:
	var i0 := _n(start)
	var n := out.size() - i0
	for p in ratios.size():
		var fp: float = f * float(ratios[p])
		if fp > RATE * 0.45:
			continue
		var tp := tau / (1.0 + 0.8 * p)
		var g: float = amp * float(gains[p])
		for i in n:
			var t := float(i) / RATE
			out[i0 + i] += g * sin(TAU * fp * t) * _env(t, 0.002, tp)


## Chamberlin state-variable filter over a noise source; `cut` maps 0..1 (time fraction) to a cutoff in Hz.
## mode: 0 low-pass, 1 band-pass, 2 high-pass.
func _add_filtered_noise(out: PackedFloat32Array, start: float, length: float, cut: Callable, q: float, mode: int,
		amp: float, attack: float, tau: float) -> void:
	var i0 := _n(start)
	var n := mini(_n(length), out.size() - i0)
	var low := 0.0
	var band := 0.0
	var damp := 1.0 / maxf(q, 0.5)
	for i in n:
		var t := float(i) / RATE
		var fc: float = clampf(cut.call(t / length), 20.0, RATE * 0.2)
		var fk := 2.0 * sin(PI * fc / RATE)
		var x := _noise()
		low += fk * band
		var high := x - low - damp * band
		band += fk * high
		var y := low if mode == 0 else (band if mode == 1 else high)
		out[i0 + i] += amp * y * _env(t, attack, tau)


## Sparse random clicks (fire crackle, popcorn): `rate` per second, each a short decaying noise tick.
func _add_crackle(out: PackedFloat32Array, start: float, length: float, per_sec: float, amp: float) -> void:
	var i0 := _n(start)
	var n := mini(_n(length), out.size() - i0)
	var i := 0
	while i < n:
		i += int(RATE / per_sec * _rng.randf_range(0.3, 1.7))
		var a := amp * _rng.randf_range(0.3, 1.0) * (1.0 - float(i) / n)
		for j in 120:
			if i + j >= n:
				break
			out[i0 + i + j] += a * _noise() * exp(-j / 18.0)


## Filtered noise with a free-form envelope: `cut(k)` in Hz and `env(k)` in 0..1, k = 0..1 across `length`.
func _add_noise(out: PackedFloat32Array, start: float, length: float, cut: Callable, q: float, mode: int, amp: float,
		env: Callable) -> void:
	var i0 := _n(start)
	var n := mini(_n(length), out.size() - i0)
	var low := 0.0
	var band := 0.0
	var damp := 1.0 / maxf(q, 0.5)
	for i in n:
		var k := float(i) / n
		var fc: float = clampf(cut.call(k), 20.0, RATE * 0.2)
		var fk := 2.0 * sin(PI * fc / RATE)
		low += fk * band
		var high := _noise() - low - damp * band
		band += fk * high
		var y := low if mode == 0 else (band if mode == 1 else high)
		out[i0 + i] += amp * y * float(env.call(k))


## An oscillator with free-form frequency and envelope (k = 0..1 across `length`). shape: 0 sine, 1 saw.
func _add_tone(out: PackedFloat32Array, start: float, length: float, freq: Callable, amp: float, env: Callable,
		shape: int = 0) -> void:
	var i0 := _n(start)
	var n := mini(_n(length), out.size() - i0)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += float(freq.call(k)) / RATE
		phase -= floorf(phase)
		var w := sin(TAU * phase) if shape == 0 else 2.0 * phase - 1.0
		out[i0 + i] += amp * w * float(env.call(k))


## Low-passed crackle: like _add_crackle but each tick goes through a one-pole low-pass at `lp_hz` (no metallic fizz).
func _add_soft_crackle(out: PackedFloat32Array, start: float, length: float, per_sec: float, amp: float,
		lp_hz: float) -> void:
	var i0 := _n(start)
	var n := mini(_n(length), out.size() - i0)
	var a_lp := 1.0 - exp(-TAU * lp_hz / RATE)
	var i := 0
	while i < n:
		i += int(RATE / per_sec * _rng.randf_range(0.3, 1.7))
		var a := amp * _rng.randf_range(0.2, 1.0) * (1.0 - float(i) / n)
		var y := 0.0
		for j in 300:
			if i + j >= n:
				break
			y += a_lp * (_noise() * exp(-j / 40.0) - y)
			out[i0 + i + j] += a * y * 3.0


## Irregular short bursts of band-passed noise whose gaps grow and level falls: a sputter that dies.
func _add_sputter(out: PackedFloat32Array, start: float, length: float, fc_lo: float, fc_hi: float, amp: float) -> void:
	var t := 0.0
	while t < length:
		var k := t / length
		var burst := _rng.randf_range(0.008, 0.035)
		var fc := _rng.randf_range(fc_lo, fc_hi)
		var a := amp * (1.0 - k) * _rng.randf_range(0.4, 1.0)
		_add_filtered_noise(out, start + t, burst, func(_k: float) -> float: return fc, 1.4, 1, a, 0.001, burst * 0.4)
		t += burst + _rng.randf_range(0.01, 0.03) + 0.12 * k * k   # gaps lengthen as it dies


func _fade_out(out: PackedFloat32Array, sec: float) -> void:
	var n := mini(_n(sec), out.size())
	for i in n:
		out[out.size() - 1 - i] *= float(i) / n


## Scale to a peak (dBFS) and soft-clip anything left over.
func _normalize(out: PackedFloat32Array, peak_db: float) -> PackedFloat32Array:
	var peak := 0.0
	for v in out:
		peak = maxf(peak, absf(v))
	var g := db_to_linear(peak_db) / maxf(peak, 1e-6)
	for i in out.size():
		out[i] = tanh(out[i] * g * 1.1) / tanh(1.1)
	_fade_out(out, 0.004)
	return out


func to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


# ---------------------------------------------------------------- recipes (cue name -> samples)

const CUES := ["cast_armed_a", "cast_armed_b", "spell_whoosh", "spell_fireball", "spell_heal", "fizzle_pfft",
		"out_of_component", "accidental_sting", "elevator_ding", "stamp_thunk", "typewriter_clack", "cha_ching",
		"pickup_bloop", "fuse_hiss",
		# v2, after the user's listen (2026-10-18): two variants each where it helps.
		"cast_armed_v2", "cast_armed_v2b", "fizzle_pfft_v2", "fizzle_pfft_v2b", "spell_fireball_v2",
		"spell_fireball_v2b", "stamp_thunk_v2", "stamp_thunk_v2b", "elevator_ding_v2", "elevator_ding_v2b",
		"accidental_sting_v2", "cast_armed_v3", "cast_armed_v3b"]
const V2 := ["cast_armed_v2", "cast_armed_v2b", "fizzle_pfft_v2", "fizzle_pfft_v2b", "spell_fireball_v2",
		"spell_fireball_v2b", "stamp_thunk_v2", "stamp_thunk_v2b", "elevator_ding_v2", "elevator_ding_v2b",
		"accidental_sting_v2"]


func make(cue: String) -> PackedFloat32Array:
	_rng.seed = hash(cue)
	return call("_" + cue)


## #1 "cast" heard, A: two rising glass pips (A6 -> E7), 0.16 s, energy above ~1.7 kHz so it sits over the
## voice's fundamental and first formant and is short enough to end before the spell word does.
func _cast_armed_a() -> PackedFloat32Array:
	var o := _buf(0.2)
	_add_bell(o, 0.0, 1760.0, 0.5, 0.05, [1.0, 2.0, 3.0], [1.0, 0.25, 0.08])
	_add_bell(o, 0.055, 2637.0, 0.6, 0.07, [1.0, 2.0, 3.0], [1.0, 0.25, 0.08])
	return _normalize(o, -10.0)


## #1 "cast" heard, B: one bright "tink" with a tiny upward bend, 0.12 s. Quieter and less musical than A.
func _cast_armed_b() -> PackedFloat32Array:
	var o := _buf(0.14)
	_add_glide(o, 0.0, 0.14, 3100.0, 3500.0, 0.6, 0.002, 0.03)
	_add_glide(o, 0.0, 0.14, 6200.0, 7000.0, 0.15, 0.001, 0.015)
	return _normalize(o, -12.0)


## #2 spell fired, generic: a band-passed noise whoosh that sweeps up and back down, 0.4 s.
func _spell_whoosh() -> PackedFloat32Array:
	var o := _buf(0.42)
	_add_filtered_noise(o, 0.0, 0.42, func(k: float) -> float: return 350.0 + 2600.0 * sin(PI * minf(k * 1.3, 1.0)),
			3.0, 1, 1.0, 0.09, 0.12)
	return _normalize(o, -6.0)


## #2 fireball: a low-passed roar that opens up, crackle on top and a soft low thump at the start, 0.55 s.
func _spell_fireball() -> PackedFloat32Array:
	var o := _buf(0.6)
	_add_filtered_noise(o, 0.0, 0.6, func(k: float) -> float: return 300.0 + 2200.0 * (1.0 - k) * k * 4.0,
			1.2, 0, 1.4, 0.05, 0.2)
	_add_crackle(o, 0.05, 0.5, 45.0, 0.5)
	_add_glide(o, 0.0, 0.25, 140.0, 55.0, 0.7, 0.004, 0.07)
	return _normalize(o, -5.0)


## #2 heal: a quick rising arpeggio of soft bells with a little shimmer, 0.6 s.
func _spell_heal() -> PackedFloat32Array:
	var o := _buf(0.75)
	var notes := [880.0, 1108.7, 1318.5, 1760.0]
	for i in notes.size():
		_add_bell(o, 0.06 * i, notes[i], 0.35, 0.35, [1.0, 2.0, 3.01], [1.0, 0.2, 0.07])
		_add_bell(o, 0.06 * i + 0.01, notes[i] * 1.004, 0.2, 0.3, [1.0, 2.0], [1.0, 0.15])
	_add_filtered_noise(o, 0.0, 0.7, func(k: float) -> float: return 5000.0 + 3000.0 * k, 6.0, 1, 0.12, 0.2, 0.25)
	return _normalize(o, -8.0)


## #3 fizzle: a puff of air that loses its top (low-pass falling 4 kHz -> 300 Hz) plus a deflating squeak, 0.4 s.
func _fizzle_pfft() -> PackedFloat32Array:
	var o := _buf(0.45)
	_add_filtered_noise(o, 0.0, 0.45, func(k: float) -> float: return 4000.0 * pow(0.075, k), 0.8, 0, 1.0, 0.008, 0.12)
	_add_glide(o, 0.03, 0.35, 520.0, 170.0, 0.22, 0.03, 0.15, 11.0, 0.04)
	return _normalize(o, -8.0)


## #3 variant, out of component: the same puff but shorter and with an empty "tok" (an empty jar), 0.3 s.
func _out_of_component() -> PackedFloat32Array:
	var o := _buf(0.32)
	_add_filtered_noise(o, 0.0, 0.25, func(k: float) -> float: return 2500.0 * pow(0.15, k), 0.8, 0, 0.7, 0.005, 0.07)
	_add_bell(o, 0.0, 520.0, 0.6, 0.05, [1.0, 2.3], [1.0, 0.3])
	return _normalize(o, -10.0)


## #4 accidental cast: a slide whistle falling (1.6 kHz -> 450 Hz with vibrato) and a woodblock "bonk", 0.7 s.
func _accidental_sting() -> PackedFloat32Array:
	var o := _buf(0.75)
	_add_glide(o, 0.0, 0.55, 1600.0, 450.0, 0.5, 0.02, 0.6, 7.0, 0.025)
	_add_glide(o, 0.0, 0.55, 3200.0, 900.0, 0.08, 0.02, 0.3, 7.0, 0.025)
	_add_bell(o, 0.56, 760.0, 0.7, 0.04, [1.0, 2.6, 4.1], [1.0, 0.4, 0.15])
	return _normalize(o, -8.0)


## #8 elevator arrival: one struck bell (E6) with a long tail, 1.4 s.
func _elevator_ding() -> PackedFloat32Array:
	var o := _buf(1.4)
	_add_bell(o, 0.0, 1318.5, 1.0, 0.9)
	return _normalize(o, -8.0)


## #7 rubber stamp: a dull low thump with a pitch drop, a rubbery click and a paper slap, 0.2 s.
func _stamp_thunk() -> PackedFloat32Array:
	var o := _buf(0.22)
	_add_glide(o, 0.0, 0.2, 170.0, 60.0, 1.0, 0.002, 0.045)
	_add_filtered_noise(o, 0.0, 0.05, func(_k: float) -> float: return 1800.0, 0.9, 0, 0.8, 0.0005, 0.008)
	_add_filtered_noise(o, 0.004, 0.08, func(_k: float) -> float: return 2400.0, 1.5, 1, 0.5, 0.001, 0.018)
	return _normalize(o, -4.0)


## #7 typewriter key: a sharp click, a short metallic ring from the typebar and a low "thock", 0.09 s.
func _typewriter_clack() -> PackedFloat32Array:
	var o := _buf(0.1)
	_add_filtered_noise(o, 0.0, 0.01, func(_k: float) -> float: return 4500.0, 0.7, 2, 1.0, 0.0002, 0.0015)
	_add_bell(o, 0.002, 3150.0, 0.25, 0.04, [1.0, 1.62, 2.4], [1.0, 0.5, 0.3])
	_add_glide(o, 0.0, 0.05, 260.0, 180.0, 0.5, 0.001, 0.012)
	return _normalize(o, -8.0)


## #9 money on the invoice: two quick drawer clicks, then a register bell, 0.8 s. No voice.
func _cha_ching() -> PackedFloat32Array:
	var o := _buf(0.85)
	_add_filtered_noise(o, 0.0, 0.03, func(_k: float) -> float: return 3500.0, 2.0, 1, 1.0, 0.0005, 0.005)
	_add_filtered_noise(o, 0.07, 0.03, func(_k: float) -> float: return 3000.0, 2.0, 1, 0.9, 0.0005, 0.005)
	_add_bell(o, 0.1, 2093.0, 0.8, 0.45, [1.0, 2.0, 2.76, 3.5], [1.0, 0.5, 0.35, 0.2])
	_add_bell(o, 0.1, 2637.0, 0.5, 0.4, [1.0, 2.0], [1.0, 0.3])
	return _normalize(o, -8.0)


## #6 pickup: a rounded upward "bloop", 0.12 s.
func _pickup_bloop() -> PackedFloat32Array:
	var o := _buf(0.14)
	_add_glide(o, 0.0, 0.13, 380.0, 950.0, 1.0, 0.005, 0.06)
	_add_glide(o, 0.0, 0.13, 760.0, 1900.0, 0.15, 0.005, 0.04)
	return _normalize(o, -9.0)


## #10 goblin fuse (loopable bed): a hiss with sputters, 1.5 s (the fuse length in monster-awareness.md).
func _fuse_hiss() -> PackedFloat32Array:
	var o := _buf(1.5)
	_add_filtered_noise(o, 0.0, 1.5, func(k: float) -> float: return 5500.0 + 1500.0 * sin(TAU * 9.0 * k), 2.5, 1,
			0.5, 0.05, 100.0)
	_add_crackle(o, 0.0, 1.5, 30.0, 0.6)
	return _normalize(o, -10.0)


# ---------------------------------------------------------------- v2 recipes (user feedback, 2026-10-18)

## Swell: rises as k^p, then a quick release over the last `rel` of the length.
static func _swell(k: float, p: float = 2.0, rel: float = 0.08) -> float:
	var up := pow(k, p)
	return up if k < 1.0 - rel else up * (1.0 - k) / rel


## #1 cast heard, v2: a magical charge-up, 0.42 s. Band-passed noise rising 500 Hz -> 5 kHz and swelling, a quiet
## high tone pair (a fifth apart, 1.4 -> 4.2 kHz, kept above the voice's formants) with a flutter that speeds up, and
## a soft shimmer as it tops out. Not twinkly: the swell is the sound, the shimmer only an accent.
func _cast_armed_v2() -> PackedFloat32Array:
	var o := _buf(0.5)
	var dur := 0.42
	_add_noise(o, 0.0, dur, func(k: float) -> float: return 500.0 * pow(10.0, k), 2.0, 1, 1.0,
			func(k: float) -> float: return _swell(k, 1.6))
	var flutter := func(k: float) -> float:
		var ph := TAU * dur * (14.0 * k + 15.0 * k * k)   # 14 Hz -> 44 Hz
		return _swell(k, 2.2) * (0.65 + 0.35 * sin(ph))
	_add_tone(o, 0.0, dur, func(k: float) -> float: return 1400.0 * pow(3.0, k), 0.22, flutter)
	_add_tone(o, 0.0, dur, func(k: float) -> float: return 2100.0 * pow(3.0, k), 0.12, flutter)
	_add_filtered_noise(o, dur - 0.03, 0.08, func(_k: float) -> float: return 7000.0, 3.0, 1, 0.35, 0.004, 0.025)
	_add_bell(o, dur - 0.02, 4186.0, 0.12, 0.05, [1.0, 1.5], [1.0, 0.4])
	return _normalize(o, -10.0)


## #1 cast heard, v2b: a shorter "zhzhzh" capacitor charge, 0.34 s. High-passed noise whose pulses speed up
## (12 -> 48 Hz) as it swells, over a quiet airy band rising to 6 kHz; it ends in a soft puff, no bell.
func _cast_armed_v2b() -> PackedFloat32Array:
	var o := _buf(0.4)
	var dur := 0.34
	var pulses := func(k: float) -> float:
		var ph := TAU * dur * (12.0 * k + 18.0 * k * k)
		return _swell(k, 1.8, 0.06) * pow(0.5 + 0.5 * sin(ph), 2.0)
	_add_noise(o, 0.0, dur, func(k: float) -> float: return 1500.0 + 2500.0 * k, 1.0, 2, 0.9, pulses)
	_add_noise(o, 0.0, dur, func(k: float) -> float: return 1200.0 * pow(5.0, k), 3.0, 1, 0.5,
			func(k: float) -> float: return _swell(k, 1.4, 0.06))
	_add_filtered_noise(o, dur - 0.02, 0.06, func(k: float) -> float: return 6000.0 * pow(0.4, k), 1.0, 1, 0.4,
			0.003, 0.02)
	return _normalize(o, -10.0)


## #1 cast heard, v3: the charge-up with the speech band left empty, 0.42 s. The mic-leak probe showed v2's 1-4 kHz
## noise masks the start of the spell word ("heal" heard as "meal"/"yale"), so this one is built from two layers only:
## a sub swell (a sine rising 70 -> 210 Hz with a speeding pulse: body you feel) and "air" above 5 kHz (high-passed
## noise and a faint tone rising 5 -> 7.5 kHz), with a soft top-out puff. Nothing between ~300 Hz and ~4.5 kHz.
func _cast_armed_v3() -> PackedFloat32Array:
	var o := _buf(0.5)
	var dur := 0.42
	var pulse := func(k: float) -> float:
		var ph := TAU * dur * (10.0 * k + 15.0 * k * k)
		return _swell(k, 1.5) * (0.7 + 0.3 * sin(ph))
	_add_tone(o, 0.0, dur, func(k: float) -> float: return 70.0 * pow(3.0, k), 0.9, pulse)
	_add_noise(o, 0.0, dur, func(k: float) -> float: return 5000.0 + 3000.0 * k, 0.8, 2, 0.8,
			func(k: float) -> float: return _swell(k, 1.8))
	_add_tone(o, 0.0, dur, func(k: float) -> float: return 5000.0 * pow(1.5, k), 0.08, func(k: float) -> float: return _swell(k, 2.5))
	_add_filtered_noise(o, dur - 0.02, 0.06, func(_k: float) -> float: return 8000.0, 1.0, 2, 0.4, 0.002, 0.02)
	return _normalize(o, -9.0)


## #1 cast heard, v3b: v2's shape moved up out of the speech band, 0.38 s: band-passed noise rising 4.5 -> 10 kHz,
## a tone pair rising 4.2 -> 6.3 kHz with the speeding flutter, and a low sine swell underneath for weight.
func _cast_armed_v3b() -> PackedFloat32Array:
	var o := _buf(0.45)
	var dur := 0.38
	_add_noise(o, 0.0, dur, func(k: float) -> float: return 4500.0 * pow(2.2, k), 2.0, 1, 1.0,
			func(k: float) -> float: return _swell(k, 1.6))
	var flutter := func(k: float) -> float:
		var ph := TAU * dur * (14.0 * k + 15.0 * k * k)
		return _swell(k, 2.2) * (0.65 + 0.35 * sin(ph))
	_add_tone(o, 0.0, dur, func(k: float) -> float: return 4200.0 * pow(1.5, k), 0.15, flutter)
	_add_tone(o, 0.0, dur, func(k: float) -> float: return 90.0 * pow(2.0, k), 0.6, func(k: float) -> float: return _swell(k, 1.4))
	return _normalize(o, -10.0)


## #3 fizzle, v2: the spell tries, spits and chokes, 0.75 s. A charge that starts and stalls (0.12 s), spitting
## bursts with growing gaps, soft crackle, a spark falling from 2 kHz that loses its pitch, and a dull thud as it dies.
func _fizzle_pfft_v2() -> PackedFloat32Array:
	var o := _buf(0.8)
	_add_noise(o, 0.0, 0.12, func(k: float) -> float: return 700.0 * pow(3.0, k), 2.0, 1, 0.5,
			func(k: float) -> float: return k * (1.0 - k) * 4.0)
	_add_sputter(o, 0.06, 0.55, 1200.0, 3500.0, 0.9)
	_add_soft_crackle(o, 0.08, 0.5, 35.0, 0.6, 3000.0)
	_add_tone(o, 0.08, 0.4, func(k: float) -> float: return 2000.0 * pow(0.12, k) * (1.0 + 0.08 * _rng.randf_range(-1.0, 1.0)),
			0.12, func(k: float) -> float: return (1.0 - k) * (1.0 - k))
	_add_glide(o, 0.5, 0.25, 130.0, 50.0, 0.7, 0.004, 0.06)
	_add_noise(o, 0.5, 0.25, func(_k: float) -> float: return 300.0, 0.7, 0, 0.6,
			func(k: float) -> float: return exp(-k * 8.0))
	return _normalize(o, -8.0)


## #3 fizzle, v2b: an electrical short, 0.7 s. A low buzz that cuts in and out (zaps) with a spark at each cut,
## then a dying low-passed puff and a soft thud.
func _fizzle_pfft_v2b() -> PackedFloat32Array:
	var o := _buf(0.75)
	var gate: Array = []
	var t := 0.0
	while t < 0.45:
		var on := _rng.randf_range(0.02, 0.07)
		gate.append([t / 0.45, (t + on) / 0.45])
		t += on + _rng.randf_range(0.02, 0.06) + 0.1 * t
	var zap := func(k: float) -> float:
		for g: Array in gate:
			if k >= float(g[0]) and k < float(g[1]):
				return 1.0 - 0.6 * k
		return 0.0
	_add_tone(o, 0.0, 0.45, func(k: float) -> float: return 95.0 * (1.0 - 0.25 * k), 0.35, zap, 1)
	_add_noise(o, 0.0, 0.45, func(_k: float) -> float: return 2500.0, 1.5, 1, 0.5, zap)
	for g: Array in gate:
		_add_filtered_noise(o, minf(float(g[1]), 1.0) * 0.45, 0.02, func(_k: float) -> float: return 4500.0, 1.0, 2,
				0.5, 0.0005, 0.004)
	_add_filtered_noise(o, 0.45, 0.25, func(k: float) -> float: return 1500.0 * pow(0.15, k), 0.8, 0, 0.6, 0.005, 0.07)
	_add_glide(o, 0.47, 0.2, 110.0, 45.0, 0.5, 0.004, 0.05)
	return _normalize(o, -8.0)


## #2 fireball, v2: a fire WHOOMPH, 0.8 s. A short suck of air rising into the burst, a deep low-passed boom with a
## sub thump, then a flickering low roar and soft (low-passed) crackle. Nothing bright rings.
func _spell_fireball_v2() -> PackedFloat32Array:
	var o := _buf(0.85)
	_add_noise(o, 0.0, 0.1, func(k: float) -> float: return 200.0 * pow(6.0, k), 0.8, 0, 0.5,
			func(k: float) -> float: return k * k)
	_add_filtered_noise(o, 0.09, 0.6, func(k: float) -> float: return 1400.0 * pow(0.25, k), 0.7, 0, 1.6, 0.008, 0.16)
	_add_glide(o, 0.09, 0.4, 75.0, 38.0, 1.0, 0.005, 0.12)
	_add_noise(o, 0.12, 0.7, func(_k: float) -> float: return 520.0, 0.7, 0, 0.9,
			func(k: float) -> float: return minf(k * 12.0, 1.0) * exp(-k * 3.5) * (0.75 + 0.25 * sin(TAU * 5.0 * k) * sin(TAU * 8.0 * k)))
	_add_soft_crackle(o, 0.15, 0.65, 22.0, 0.45, 2200.0)
	return _normalize(o, -4.0)


## #2 fireball, v2b: no suck-in, a bigger boom and a longer burning tail with more crackle, 1.1 s.
func _spell_fireball_v2b() -> PackedFloat32Array:
	var o := _buf(1.1)
	_add_filtered_noise(o, 0.0, 0.7, func(k: float) -> float: return 1100.0 * pow(0.3, k), 0.7, 0, 1.8, 0.006, 0.2)
	_add_glide(o, 0.0, 0.5, 65.0, 32.0, 1.1, 0.004, 0.16)
	_add_noise(o, 0.03, 1.05, func(k: float) -> float: return 650.0 - 250.0 * k, 0.7, 0, 1.0,
			func(k: float) -> float: return minf(k * 15.0, 1.0) * exp(-k * 2.2) * (0.75 + 0.25 * sin(TAU * 9.0 * k)))
	_add_soft_crackle(o, 0.08, 1.0, 34.0, 0.5, 2500.0)
	return _normalize(o, -4.0)


## #8 stamp, v2: a heavy wooden thunk, 0.25 s. A very short click, a deep thud (120 -> 48 Hz), a low-passed impact
## body, three short desk resonances (165/240/410 Hz) and a small rubber/ink slap on top.
func _stamp_thunk_v2() -> PackedFloat32Array:
	var o := _buf(0.25)
	_add_filtered_noise(o, 0.0, 0.006, func(_k: float) -> float: return 3000.0, 0.7, 0, 0.35, 0.0002, 0.0012)
	_add_glide(o, 0.0, 0.22, 120.0, 48.0, 1.2, 0.0015, 0.07)
	_add_filtered_noise(o, 0.0, 0.1, func(_k: float) -> float: return 400.0, 0.7, 0, 1.6, 0.001, 0.02)
	_add_glide(o, 0.0, 0.15, 165.0, 165.0, 0.45, 0.001, 0.05)
	_add_glide(o, 0.0, 0.12, 240.0, 240.0, 0.3, 0.001, 0.035)
	_add_glide(o, 0.0, 0.08, 410.0, 410.0, 0.18, 0.001, 0.02)
	_add_filtered_noise(o, 0.002, 0.05, func(_k: float) -> float: return 1600.0, 1.2, 1, 0.25, 0.0008, 0.012)
	return _normalize(o, -2.0)


## #8 stamp, v2b: heavier and woodier: a lower thud (100 -> 40 Hz) plus a hollow handle knock (720/1130 Hz).
func _stamp_thunk_v2b() -> PackedFloat32Array:
	var o := _buf(0.28)
	_add_filtered_noise(o, 0.0, 0.006, func(_k: float) -> float: return 2500.0, 0.7, 0, 0.3, 0.0002, 0.0012)
	_add_glide(o, 0.0, 0.25, 100.0, 40.0, 1.3, 0.0015, 0.085)
	_add_filtered_noise(o, 0.0, 0.12, func(_k: float) -> float: return 350.0, 0.7, 0, 1.8, 0.001, 0.025)
	_add_glide(o, 0.0, 0.15, 150.0, 150.0, 0.5, 0.001, 0.055)
	_add_glide(o, 0.0, 0.12, 225.0, 225.0, 0.3, 0.001, 0.04)
	_add_glide(o, 0.0, 0.06, 720.0, 720.0, 0.22, 0.0008, 0.016)
	_add_glide(o, 0.0, 0.05, 1130.0, 1130.0, 0.12, 0.0008, 0.011)
	_add_filtered_noise(o, 0.002, 0.05, func(_k: float) -> float: return 1500.0, 1.2, 1, 0.2, 0.0008, 0.01)
	return _normalize(o, -2.0)


## #10 elevator, v2: ding-ding, two struck bells a major third apart, rising (C6 then E6, 0.32 s later), 1.8 s.
func _elevator_ding_v2() -> PackedFloat32Array:
	var o := _buf(1.8)
	_add_bell(o, 0.0, 1046.5, 0.9, 0.85)
	_add_bell(o, 0.32, 1318.5, 1.0, 0.9)
	return _normalize(o, -8.0)


## #10 elevator, v2b: the classic falling "ding-dong" (E6 then C6, 0.38 s later), warmer (quieter upper partials).
func _elevator_ding_v2b() -> PackedFloat32Array:
	var o := _buf(1.9)
	var warm := [1.0, 0.3, 0.18, 0.08, 0.04]
	_add_bell(o, 0.0, 1318.5, 1.0, 0.9, [1.0, 2.0, 2.76, 4.07, 5.4], warm)
	_add_bell(o, 0.38, 1046.5, 1.0, 1.0, [1.0, 2.0, 2.76, 4.07, 5.4], warm)
	return _normalize(o, -8.0)


## #6 accidental, v2 (an alternative, not a replacement): a record scratch ("wait, what?") and the woodblock bonk, 0.6 s.
func _accidental_sting_v2() -> PackedFloat32Array:
	var o := _buf(0.62)
	_add_noise(o, 0.0, 0.09, func(k: float) -> float: return 600.0 * pow(5.0, k), 2.5, 1, 1.0,
			func(k: float) -> float: return sin(PI * k))
	_add_noise(o, 0.09, 0.13, func(k: float) -> float: return 3000.0 * pow(0.15, k), 2.5, 1, 1.0,
			func(k: float) -> float: return sin(PI * k))
	_add_soft_crackle(o, 0.0, 0.25, 40.0, 0.25, 4000.0)
	_add_bell(o, 0.36, 760.0, 0.8, 0.04, [1.0, 2.6, 4.1], [1.0, 0.4, 0.15])
	return _normalize(o, -8.0)
