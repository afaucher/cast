extends "res://tools/sfx_proto/sfx_synth.gd"
## Round 3 of the audio prototype (docs/design/audio-plan.md): after the user's second listen (2026-10-18), physical
## sounds are built from the CC0 recordings in assets/audio/third_party/ (Rec = sfx_rec.gd: trim, fade, layer,
## pitch, EQ, normalise), and the synth only fills in where no recording fits. Every cue lists its sources in
## SOURCES below, for assets/audio/third_party/SOURCES.md.
## Mic-safety rule (round 2 probe): a "cast heard" cue keeps 300 Hz-4.5 kHz quiet (Rec.notch_band), because noise in
## that band masks the start of the spell word.

const Rec = preload("res://tools/sfx_proto/sfx_rec.gd")

const FIRE_SPELL := "freesound/442871__qubodup__fire-spell.wav"
const FIRE_MAGIC := "freesound/442872__qubodup__fire-magic.wav"
const STAMP_1 := "freesound/362622__kermite607__stamp.wav"
const STAMP_3 := "freesound/362624__kermite607__stamp.wav"
const K_IMPACT := "kenney_impact-sounds/"
const K_UI := "kenney_interface-sounds/"
const K_RPG := "kenney_rpg-audio/"

const CUES3 := ["cast_armed_v4a", "cast_armed_v4b", "cast_armed_v4c", "cast_armed_v4d", "fizzle_pfft_v4",
		"fizzle_pfft_v4b", "spell_fireball_v4", "spell_fireball_v4b", "stamp_thunk_v4", "stamp_thunk_v4b",
		"elevator_ding_v4", "elevator_ding_v4b"]

## cue -> the recordings it is made from ("synth" = generated here).
const SOURCES := {
	"cast_armed_v4a": [K_RPG + "knifeSlice2.ogg"],
	"cast_armed_v4a2": [K_RPG + "knifeSlice2.ogg"],
	"cast_armed_v4a3": [K_RPG + "knifeSlice2.ogg"],
	"cast_armed_v4b": ["synth", K_UI + "tick_002.ogg"],
	"cast_armed_v4c": [K_UI + "scratch_001.ogg", K_UI + "tick_002.ogg", FIRE_SPELL],
	"cast_armed_v4d": [FIRE_SPELL, K_UI + "bong_001.ogg"],
	"fizzle_pfft_v4": ["synth"],
	"fizzle_pfft_v4b": ["synth", K_UI + "glitch_001.ogg", K_UI + "glitch_002.ogg", K_UI + "glitch_003.ogg",
			K_UI + "glitch_004.ogg"],
	"spell_fireball_v4": [FIRE_SPELL, K_IMPACT + "impactPunch_heavy_000.ogg"],
	"spell_fireball_v4b": [FIRE_MAGIC, K_IMPACT + "impactPunch_heavy_001.ogg"],
	"stamp_thunk_v4": [STAMP_3, K_IMPACT + "impactPlank_medium_000.ogg"],
	"stamp_thunk_v4b": [STAMP_1, K_IMPACT + "impactPlank_medium_000.ogg"],
	"elevator_ding_v4": [K_IMPACT + "impactBell_heavy_000.ogg"],
	"elevator_ding_v4b": ["synth"],
}


## The speech band out, then a peak level: every cast-heard cue ends here.
static func _mic_safe(s: PackedFloat32Array, peak_db: float) -> PackedFloat32Array:
	return Rec.normalize(Rec.notch_band(s, 300.0, 4500.0, 3), peak_db)


# ---------------------------------------------------------------- 1. cast heard: four directions

## (a) A reversed metal "shing" (Kenney knifeSlice2) as a swell into the moment the cast arms, 0.45 s: the classic
## reverse-cymbal magic build. Only its air above 4.5 kHz (and anything under 300 Hz) is kept.
func _cast_armed_v4a() -> PackedFloat32Array:
	var s := Rec.trim(Rec.load_mono(K_RPG + "knifeSlice2.ogg"), -50.0)
	s = Rec.reverse(s)
	s = Rec.cut(s, maxf(s.size() / float(RATE) - 0.45, 0.0))     # the last 0.45 s of the reversed sound: the swell
	s = Rec.fade(s, 0.12, 0.012, 2.0)
	return _mic_safe(s, -8.0)


## (a2) The user's pick (v4a) made mic-safe by length: the same swell cut to its last 0.25 s, so it is over before the
## spell word gets going (round 3: a loud high swell over the word's onset masks "h"/"k").
func _cast_armed_v4a2() -> PackedFloat32Array:
	var s := Rec.trim(Rec.load_mono(K_RPG + "knifeSlice2.ogg"), -50.0)
	s = Rec.reverse(s)
	s = Rec.cut(s, maxf(s.size() / float(RATE) - 0.25, 0.0))
	s = Rec.fade(s, 0.06, 0.012, 2.0)
	return _mic_safe(s, -8.0)


## (a3) v4a made mic-safe by level: the full 0.45 s swell, 8 dB quieter.
func _cast_armed_v4a3() -> PackedFloat32Array:
	var s := Rec.trim(Rec.load_mono(K_RPG + "knifeSlice2.ogg"), -50.0)
	s = Rec.reverse(s)
	s = Rec.cut(s, maxf(s.size() / float(RATE) - 0.45, 0.0))
	s = Rec.fade(s, 0.12, 0.012, 2.0)
	return _mic_safe(s, -16.0)


## (b) A warm power-up that rises and locks on, 0.45 s: a hum (a saw 55 -> 110 Hz, low-passed at 260 Hz) whose
## pulse speeds up as it swells, a faint air layer, then it holds at 110 Hz and a high "tk" (Kenney tick_002, top
## only) marks the lock. Low-mid weight, nothing in 300 Hz-4.5 kHz.
func _cast_armed_v4b() -> PackedFloat32Array:
	var o := _buf(0.48)
	var rise := 0.36
	var pulse := func(k: float) -> float:
		var ph := TAU * rise * (8.0 * k + 8.0 * k * k)          # 8 -> 24 Hz
		return pow(k, 1.3) * (0.6 + 0.4 * sin(ph))
	_add_tone(o, 0.0, rise, func(k: float) -> float: return 55.0 * pow(2.0, k), 1.0, pulse, 1)
	_add_tone(o, rise, 0.1, func(_k: float) -> float: return 110.0, 1.0, func(k: float) -> float: return 1.0 - k, 1)
	var hum := Rec.lowpass(o, 260.0, 3)
	# Air on top, so small speakers (which drop everything under ~150 Hz) still hear it rise.
	var air := _buf(0.48)
	_add_noise(air, 0.0, rise, func(k: float) -> float: return 6000.0 + 2000.0 * k, 0.8, 2, 0.6,
			func(k: float) -> float: return pow(k, 1.6))
	hum = Rec.mix(hum, air)
	var tk := Rec.highpass(Rec.load_mono(K_UI + "tick_002.ogg"), 4500.0, 2)
	hum = Rec.mix(hum, Rec.gain(tk, 6.0), rise - 0.005)
	return _mic_safe(hum, -8.0)


## (c) A spark igniting, "fssh-tk", 0.38 s: a quick scratch (Kenney scratch_001, pitched up 3 semitones) as the
## strike, a high tick as it catches, and the top of a fire burst (qubodup Fire Spell) flaring briefly.
func _cast_armed_v4c() -> PackedFloat32Array:
	var fssh := Rec.fade(Rec.pitch(Rec.trim(Rec.load_mono(K_UI + "scratch_001.ogg")), 3.0), 0.01, 0.03)
	var tk := Rec.load_mono(K_UI + "tick_002.ogg")
	var flare := Rec.fade(Rec.cut(Rec.load_mono(FIRE_SPELL), 0.0, 0.25), 0.005, 0.15, 2.0)
	var s := Rec.mix(fssh, tk, 0.13, 2.0)
	s = Rec.mix(s, Rec.highpass(flare, 3000.0), 0.14, 0.0)
	return _mic_safe(s, -8.0)


## (d) The spell breathing in, 0.48 s: qubodup's Fire Spell reversed, so the burst's tail rushes *into* the moment
## the cast arms, with only its sub body and its air kept, and a soft low "lock" (Kenney bong_001, under 300 Hz).
## Ties the cue to the spells that follow it.
func _cast_armed_v4d() -> PackedFloat32Array:
	var s := Rec.reverse(Rec.trim(Rec.load_mono(FIRE_SPELL), -40.0))
	s = Rec.fade(s, 0.1, 0.01, 2.0)
	var air := _buf(s.size() / float(RATE))
	_add_noise(air, 0.0, s.size() / float(RATE), func(k: float) -> float: return 5500.0 + 2500.0 * k, 0.8, 2, 0.5,
			func(k: float) -> float: return _swell(k, 1.8, 0.05))
	s = Rec.mix(s, air)
	var lock := Rec.lowpass(Rec.load_mono(K_UI + "bong_001.ogg"), 280.0, 2)
	s = Rec.mix(s, lock, s.size() / float(RATE) - 0.01, -3.0)
	return _mic_safe(s, -8.0)


# ---------------------------------------------------------------- 2. fizzle: v2b's short circuit, a dying sizzle

## The first 0.45 s of fizzle_pfft_v2b exactly (same seed and calls): a buzz cutting in and out, sparks at each cut.
func _short_circuit(o: PackedFloat32Array) -> Array:
	_rng.seed = hash("fizzle_pfft_v2b")
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
	return gate


## v4: v2b's start, then a short dying sizzle (high hiss and a few soft crackles fading out over 0.3 s). No thud,
## no clunk, no low-pass puff.
func _fizzle_pfft_v4() -> PackedFloat32Array:
	var o := _buf(0.8)
	var gate := _short_circuit(o)
	for g: Array in gate:
		_add_filtered_noise(o, minf(float(g[1]), 1.0) * 0.45, 0.02, func(_k: float) -> float: return 4500.0, 1.0, 2,
				0.5, 0.0005, 0.004)
	_add_sizzle(o, 0.42, 0.36)
	return _normalize(o, -8.0)


## v4b: the same, but each cut sparks with a real (recorded) glitch from Kenney's Interface Sounds instead of a
## synthesized click. Kenney has no recorded electrical spark; these short glitches are the closest.
func _fizzle_pfft_v4b() -> PackedFloat32Array:
	var o := _buf(0.8)
	var gate := _short_circuit(o)
	var glitches := []
	for i in 4:
		glitches.append(Rec.highpass(Rec.load_mono(K_UI + "glitch_%03d.ogg" % (i + 1)), 1500.0))
	var out := o
	for gi in gate.size():
		var at := minf(float(gate[gi][1]), 1.0) * 0.45
		out = Rec.mix(out, glitches[gi % glitches.size()], at, -6.0 - 2.0 * gi)
	_add_sizzle(out, 0.42, 0.36)
	return _normalize(out, -8.0)


## A sizzle that dies: high-passed hiss falling away plus sparse soft crackle, `dur` seconds from `start`.
func _add_sizzle(o: PackedFloat32Array, start: float, dur: float) -> void:
	_add_noise(o, start, dur, func(k: float) -> float: return 6000.0 - 2000.0 * k, 1.0, 2, 0.35,
			func(k: float) -> float: return minf(k * 20.0, 1.0) * pow(1.0 - k, 2.5))
	_add_soft_crackle(o, start, dur * 0.8, 28.0, 0.35, 5000.0)


# ---------------------------------------------------------------- 3. fireball from qubodup's recordings

## v4: qubodup "Fire Spell" (0.43 s, mostly 70-180 Hz body), with Kenney's heavy punch low-passed under the attack
## for a WHOOMPH, a touch of 2.5 kHz cut against any brassiness, and a gentle tail fade.
func _spell_fireball_v4() -> PackedFloat32Array:
	var fire := Rec.trim(Rec.load_mono(FIRE_SPELL), -50.0, 0.0)
	fire = Rec.peq(fire, 2500.0, -4.0, 0.8)
	var thump := Rec.lowpass(Rec.trim(Rec.load_mono(K_IMPACT + "impactPunch_heavy_000.ogg"), -50.0, 0.0), 180.0, 2)
	var s := Rec.mix(fire, Rec.fade(thump, 0.0, 0.2), 0.0, -4.0)
	return Rec.normalize(Rec.fade(s, 0.002, 0.12), -1.0)


## v4b: qubodup "Fire Magic" (0.87 s, the same burst with a longer roar), pitched down 2 semitones for size, the
## other heavy punch under it, and its tail shortened to ~0.8 s.
func _spell_fireball_v4b() -> PackedFloat32Array:
	var fire := Rec.pitch(Rec.trim(Rec.load_mono(FIRE_MAGIC), -50.0, 0.0), -2.0)
	fire = Rec.cut(Rec.peq(fire, 2500.0, -4.0, 0.8), 0.0, 0.82)
	var thump := Rec.lowpass(Rec.trim(Rec.load_mono(K_IMPACT + "impactPunch_heavy_001.ogg"), -50.0, 0.0), 160.0, 2)
	var s := Rec.mix(fire, Rec.fade(thump, 0.0, 0.25), 0.0, -3.0)
	return Rec.normalize(Rec.fade(s, 0.002, 0.25), -1.0)


# ---------------------------------------------------------------- 4. stamp from kermite607's takes

## One stamp: the first hit of a take (each take also has the stamp lifting off ~0.35 s later, which is cut),
## its room tail faded, a low shelf of weight (+5 dB at 90 Hz) and a quiet low-passed wooden thud (Kenney plank)
## under it for the desk.
func _stamp_from(path: String, hit_end: float) -> PackedFloat32Array:
	var s := Rec.trim(Rec.load_mono(path), -40.0, 0.003)
	s = Rec.fade(Rec.cut(s, 0.0, hit_end), 0.001, hit_end * 0.5, 1.5)
	s = Rec.peq(s, 90.0, 5.0, 0.7)
	var desk := Rec.lowpass(Rec.trim(Rec.load_mono(K_IMPACT + "impactPlank_medium_000.ogg"), -50.0, 0.0), 220.0, 2)
	s = Rec.mix(s, Rec.fade(Rec.cut(desk, 0.0, 0.2), 0.0, 0.12), 0.0, -9.0)
	return Rec.normalize(s, -1.0)


## v4: take 3 (362624), the loudest and lowest hit.
func _stamp_thunk_v4() -> PackedFloat32Array:
	return _stamp_from(STAMP_3, 0.24)


## v4b: take 1 (362622), crisper (more top), a little shorter.
func _stamp_thunk_v4b() -> PackedFloat32Array:
	return _stamp_from(STAMP_1, 0.2)


# ---------------------------------------------------------------- 5. elevator: a lobby chime, two soft tones falling

## v4: a real bell (Kenney impactBell_heavy_000, ~380 Hz) pitched up into chime range: E5-ish then C5-ish (a falling
## major third, 0.45 s apart), its strike softened (5 ms fade-in, low-passed at 3.5 kHz) so it reads as a chime.
func _elevator_ding_v4() -> PackedFloat32Array:
	var bell := Rec.trim(Rec.load_mono(K_IMPACT + "impactBell_heavy_000.ogg"), -55.0, 0.0)
	var hi := Rec.fade(Rec.pitch(bell, 10.0), 0.005, 0.15)
	var lo := Rec.fade(Rec.pitch(bell, 6.0), 0.005, 0.2)
	var s := Rec.mix(hi, lo, 0.45, 0.0)
	return Rec.normalize(Rec.lowpass(s, 3500.0), -6.0)


## v4b: v2b refined into a lobby chime: two soft vibraphone-like tones (a sine with a faint 4x overtone and a gentle
## 5 Hz tremolo), A5 then F5 (falling major third, 0.5 s apart), soft 6 ms attack, ~1 s decay each.
func _elevator_ding_v4b() -> PackedFloat32Array:
	var o := _buf(2.1)
	for note: Array in [[0.0, 880.0], [0.5, 698.46]]:
		var f: float = note[1]
		var env := func(k: float) -> float:
			var t := k * 1.6
			return minf(t / 0.006, 1.0) * exp(-t / 0.33) * (0.9 + 0.1 * sin(TAU * 5.0 * t))
		_add_tone(o, float(note[0]), 1.6, func(_k: float) -> float: return f, 1.0, env)
		_add_tone(o, float(note[0]), 1.6, func(_k: float) -> float: return f * 4.0, 0.12,
				func(k: float) -> float: return minf(k * 1.6 / 0.004, 1.0) * exp(-k * 1.6 / 0.12))
	return _normalize(o, -8.0)
