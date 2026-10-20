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

func make(cue: String) -> PackedFloat32Array:
	_rng.seed = hash(cue)
	return call("_" + cue)


# ---------------------------------------------------------------- v2 recipes (user feedback, 2026-10-18)
