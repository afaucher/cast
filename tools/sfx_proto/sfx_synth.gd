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
		"pickup_bloop", "fuse_hiss"]


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
