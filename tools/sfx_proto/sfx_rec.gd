extends RefCounted
## Recording toolkit for the audio prototype (docs/design/audio-plan.md, round 3): loads the CC0 recordings in
## assets/audio/third_party/ as mono float samples at RATE and processes them (trim, fade, gain, reverse, resample /
## pitch, simple EQ, layering, normalise). Pure GDScript so every processed cue is reproducible from the originals:
## WAV is parsed directly (8/16/24/32-bit PCM and 32-bit float), Ogg Vorbis is decoded through
## AudioStreamPlayback.mix_audio. Prototype only: nothing in the game loads this.

const RATE := 44100
const ROOT := "res://assets/audio/third_party/"


# ---------------------------------------------------------------- loading

## Mono samples at RATE from a file under ROOT (or an absolute/res:// path).
static func load_mono(path: String) -> PackedFloat32Array:
	var p := path if path.begins_with("res://") or path.is_absolute_path() else ROOT + path
	var s := _load_wav(p) if p.get_extension().to_lower() == "wav" else _load_ogg(p)
	if s.is_empty():
		push_error("sfx_rec: could not load " + p)
	return s


static func _load_wav(path: String) -> PackedFloat32Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedFloat32Array()
	f.seek(12)
	var fmt := 1
	var channels := 1
	var rate := RATE
	var bits := 16
	var out := PackedFloat32Array()
	while f.get_position() + 8 <= f.get_length():
		var id := f.get_buffer(4).get_string_from_ascii()
		var size := f.get_32()
		var next := f.get_position() + size + (size & 1)
		if id == "fmt ":
			fmt = f.get_16()
			channels = f.get_16()
			rate = f.get_32()
			f.get_32()
			f.get_16()
			bits = f.get_16()
			if fmt == 0xFFFE and size >= 40:   # WAVE_FORMAT_EXTENSIBLE: the real format is the subformat's first word
				f.get_16()
				f.get_16()
				f.get_32()
				fmt = f.get_16()
		elif id == "data":
			var pcm := f.get_buffer(size)
			var bps := bits / 8
			var frames := size / (bps * channels)
			out.resize(frames)
			for i in frames:
				var acc := 0.0
				for c in channels:
					var o := (i * channels + c) * bps
					var v := 0.0
					if fmt == 3 and bits == 32:
						v = pcm.decode_float(o)
					elif bits == 16:
						v = pcm.decode_s16(o) / 32768.0
					elif bits == 24:
						var x := pcm[o] | (pcm[o + 1] << 8) | (pcm[o + 2] << 16)
						if x & 0x800000:
							x -= 0x1000000
						v = x / 8388608.0
					elif bits == 32:
						v = pcm.decode_s32(o) / 2147483648.0
					elif bits == 8:
						v = (pcm[o] - 128) / 128.0
					acc += v
				out[i] = acc / channels
		f.seek(next)
	return resample(out, float(rate) / RATE) if rate != RATE else out


static func _load_ogg(path: String) -> PackedFloat32Array:
	var stream := AudioStreamOggVorbis.load_from_file(path)
	if stream == null:
		return PackedFloat32Array()
	stream.loop = false
	var pb := stream.instantiate_playback()
	pb.start(0.0)
	# The resampled playback mixes at the AudioServer's rate, whatever the file's own rate is.
	var src_rate := int(AudioServer.get_mix_rate())
	var out := PackedFloat32Array()
	var total := int(stream.get_length() * src_rate) + 1
	var chunk := 4096
	while out.size() < total and pb.is_playing():
		var frames: PackedVector2Array = pb.mix_audio(1.0, mini(chunk, total - out.size()))
		if frames.is_empty():
			break
		for v in frames:
			out.append((v.x + v.y) * 0.5)
	return resample(out, float(src_rate) / RATE) if src_rate != RATE else out


# ---------------------------------------------------------------- processing (all return new arrays)

## Plays `s` at `speed` (2.0 = an octave up and half as long). Linear interpolation; also converts sample rates.
static func resample(s: PackedFloat32Array, speed: float) -> PackedFloat32Array:
	var n := int(s.size() / speed)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var x := i * speed
		var j := int(x)
		var fr := x - j
		var a := s[mini(j, s.size() - 1)]
		var b := s[mini(j + 1, s.size() - 1)]
		out[i] = a + (b - a) * fr
	return out


static func pitch(s: PackedFloat32Array, semitones: float) -> PackedFloat32Array:
	return resample(s, pow(2.0, semitones / 12.0))


## Seconds `from`..`to` (to < 0 = the end).
static func cut(s: PackedFloat32Array, from: float, to: float = -1.0) -> PackedFloat32Array:
	var a := clampi(int(from * RATE), 0, s.size())
	var b := s.size() if to < 0.0 else clampi(int(to * RATE), a, s.size())
	return s.slice(a, b)


## Drops leading/trailing audio quieter than `db` (relative to the peak), keeping `pre` seconds before the onset.
static func trim(s: PackedFloat32Array, db: float = -45.0, pre: float = 0.005) -> PackedFloat32Array:
	var th := peak(s) * db_to_linear(db)
	var a := 0
	while a < s.size() and absf(s[a]) < th:
		a += 1
	var b := s.size() - 1
	while b > a and absf(s[b]) < th:
		b -= 1
	return s.slice(maxi(a - int(pre * RATE), 0), b + 1)


static func fade(s: PackedFloat32Array, fade_in: float, fade_out: float, curve: float = 1.0) -> PackedFloat32Array:
	var out := s.duplicate()
	var ni := mini(int(fade_in * RATE), out.size())
	for i in ni:
		out[i] *= pow(float(i) / ni, curve)
	var no := mini(int(fade_out * RATE), out.size())
	for i in no:
		out[out.size() - 1 - i] *= pow(float(i) / no, curve)
	return out


static func gain(s: PackedFloat32Array, db: float) -> PackedFloat32Array:
	var out := s.duplicate()
	var g := db_to_linear(db)
	for i in out.size():
		out[i] *= g
	return out


static func reverse(s: PackedFloat32Array) -> PackedFloat32Array:
	var out := s.duplicate()
	out.reverse()
	return out


## Multiplies by env(k), k = 0..1 across the sound.
static func shape(s: PackedFloat32Array, env: Callable) -> PackedFloat32Array:
	var out := s.duplicate()
	for i in out.size():
		out[i] *= float(env.call(float(i) / out.size()))
	return out


## Two-pole (12 dB/oct) low- or high-pass, `passes` times in series for a steeper slope.
static func lowpass(s: PackedFloat32Array, hz: float, passes: int = 1) -> PackedFloat32Array:
	return _svf(s, hz, 0.707, 0, passes)


static func highpass(s: PackedFloat32Array, hz: float, passes: int = 1) -> PackedFloat32Array:
	return _svf(s, hz, 0.707, 2, passes)


## Cuts (db < 0) or boosts a band around `hz`: s + (g - 1) * bandpass(s).
static func peq(s: PackedFloat32Array, hz: float, db: float, q: float = 1.0) -> PackedFloat32Array:
	var band := _svf(s, hz, q, 1, 1)
	var k := db_to_linear(db) - 1.0
	var out := s.duplicate()
	for i in out.size():
		out[i] += k * band[i] / q
	return out


## Keeps the band hz_lo..hz_hi out of a sound (for the mic-safety rule): s - bandpass, done as LP + HP sum.
static func notch_band(s: PackedFloat32Array, hz_lo: float, hz_hi: float, passes: int = 2) -> PackedFloat32Array:
	var lo := lowpass(s, hz_lo, passes)
	var hi := highpass(s, hz_hi, passes)
	var out := PackedFloat32Array()
	out.resize(s.size())
	for i in s.size():
		out[i] = lo[i] + hi[i]
	return out


static func _svf(s: PackedFloat32Array, hz: float, q: float, mode: int, passes: int) -> PackedFloat32Array:
	var cur := s
	for p in passes:
		var out := PackedFloat32Array()
		out.resize(cur.size())
		# Cytomic/Simper trapezoidal SVF: stable up to Nyquist.
		var g := tan(PI * clampf(hz, 10.0, RATE * 0.45) / RATE)
		var k := 1.0 / q
		var a1 := 1.0 / (1.0 + g * (g + k))
		var a2 := g * a1
		var a3 := g * a2
		var ic1 := 0.0
		var ic2 := 0.0
		for i in cur.size():
			var v0 := cur[i]
			var v3 := v0 - ic2
			var v1 := a1 * ic1 + a2 * v3
			var v2 := ic2 + a2 * ic1 + a3 * v3
			ic1 = 2.0 * v1 - ic1
			ic2 = 2.0 * v2 - ic2
			out[i] = v2 if mode == 0 else (v1 if mode == 1 else v0 - k * v1 - v2)
		cur = out
	return cur


## Mixes `layer` into `base` at `at` seconds (extends base if needed), scaled by `db`.
static func mix(base: PackedFloat32Array, layer: PackedFloat32Array, at: float = 0.0, db: float = 0.0) -> PackedFloat32Array:
	var out := base.duplicate()
	var i0 := int(at * RATE)
	if i0 + layer.size() > out.size():
		var old := out.size()
		out.resize(i0 + layer.size())
		for i in range(old, out.size()):
			out[i] = 0.0
	var g := db_to_linear(db)
	for i in layer.size():
		out[i0 + i] += layer[i] * g
	return out


static func peak(s: PackedFloat32Array) -> float:
	var m := 0.0
	for v in s:
		m = maxf(m, absf(v))
	return m


## Scales to a peak in dBFS and gently soft-clips; 4 ms fade at the end so nothing clicks.
static func normalize(s: PackedFloat32Array, peak_db: float = -1.0) -> PackedFloat32Array:
	var g := db_to_linear(peak_db) / maxf(peak(s), 1e-6)
	var out := PackedFloat32Array()
	out.resize(s.size())
	for i in s.size():
		out[i] = s[i] * g
	return fade(out, 0.0, 0.004)


## The strongest frequencies in t0..t1 (Goertzel on a 1/24-octave grid, 60 Hz - 12 kHz), as "hz:db" strings, and the
## share of energy below 300 Hz / 300 Hz-4.5 kHz (the speech band the probe cares about) / above 4.5 kHz.
static func spectrum(s: PackedFloat32Array, t0: float = 0.0, t1: float = -1.0, top: int = 4) -> String:
	var x := cut(s, t0, t1)
	var n := mini(x.size(), 16384)
	var bins := []
	var f := 60.0
	while f < 12000.0:
		var w := TAU * f / RATE
		var c := 2.0 * cos(w)
		var s1 := 0.0
		var s2 := 0.0
		for i in n:
			var hann := 0.5 - 0.5 * cos(TAU * i / n)
			var s0 := x[i] * hann + c * s1 - s2
			s2 = s1
			s1 = s0
		bins.append([f, s1 * s1 + s2 * s2 - c * s1 * s2])
		f *= pow(2.0, 1.0 / 24.0)
	var low := 0.0
	var mid := 0.0
	var high := 0.0
	for b: Array in bins:
		var e: float = b[1] * float(b[0])   # per-octave bins: weight by f so the shares are per Hz
		if b[0] < 300.0:
			low += e
		elif b[0] < 4500.0:
			mid += e
		else:
			high += e
	var tot := low + mid + high + 1e-12
	var peaks := []
	for i in range(1, bins.size() - 1):
		if bins[i][1] > bins[i - 1][1] and bins[i][1] >= bins[i + 1][1]:
			peaks.append(bins[i])
	peaks.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var best: float = peaks[0][1] if not peaks.is_empty() else 1.0
	var out := []
	for p: Array in peaks.slice(0, top):
		out.append("%d:%d" % [int(p[0]), int(10.0 * log(p[1] / best + 1e-12) / log(10.0))])
	return "peaks %s | low %d%% speech %d%% high %d%%" % [" ".join(out), int(100 * low / tot), int(100 * mid / tot),
			int(100 * high / tot)]


## A coarse loudness outline (dB per `step` seconds) for deciding where to cut.
static func describe(s: PackedFloat32Array, step: float = 0.05) -> String:
	var parts := []
	var n := int(step * RATE)
	var i := 0
	while i < s.size():
		var e := 0.0
		var m := mini(n, s.size() - i)
		for j in m:
			e += s[i + j] * s[i + j]
		parts.append("%d" % int(round(10.0 * log(e / m + 1e-12) / log(10.0))))
		i += n
	return "%.2fs peak %.1fdB | %s" % [s.size() / float(RATE), linear_to_db(peak(s)), " ".join(parts)]
