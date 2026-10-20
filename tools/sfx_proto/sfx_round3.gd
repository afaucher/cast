extends "res://tools/sfx_proto/sfx_synth.gd"
## Round 3 of the audio prototype (docs/design/audio-plan.md): after the user's second listen (2026-10-18), physical
## sounds are built from the CC0 recordings in assets/audio/third_party/ (Rec = sfx_rec.gd: trim, fade, layer,
## pitch, EQ, normalise), and the synth only fills in where no recording fits. Every cue lists its sources in
## SOURCES below, for assets/audio/third_party/SOURCES.md.
## Mic-safety rule (round 2 probe): a "cast heard" cue keeps 300 Hz-4.5 kHz quiet (Rec.notch_band), because noise in
## that band masks the start of the spell word.

const Rec = preload("res://tools/sfx_proto/sfx_rec.gd")

const FIRE_MAGIC := "freesound/442872__qubodup__fire-magic.wav"
const STAMP_3 := "freesound/362624__kermite607__stamp.wav"
const K_IMPACT := "kenney_impact-sounds/"
const K_UI := "kenney_interface-sounds/"
const K_RPG := "kenney_rpg-audio/"
const FIREWORK := "freesound/336008__rudmer_rotteveel__whistle-and-explosion-single_firework.wav"

## cue -> the recordings it is made from ("synth" = generated here).
const SOURCES := {
	"cast_armed_v4a2": [K_RPG + "knifeSlice2.ogg"],
	"fizzle_pfft_v4": ["synth"],
	"spell_fireball_v4b": [FIRE_MAGIC, K_IMPACT + "impactPunch_heavy_001.ogg"],
	"stamp_thunk_v4": [STAMP_3, K_IMPACT + "impactPlank_medium_000.ogg"],
	"elevator_ding_v4b": ["synth"],
	"paper_flip": [K_RPG + "bookFlip3.ogg"],
	"order_click_v1": [K_UI + "tick_002.ogg"],
	"fuse_hiss_v6": ["synth"],
	"firework_v1": [FIREWORK],
}


## A voice order heard (the game's order_heard, 2026-10-19): a radio "click-click", 0.12 s. Two Kenney ticks (tick_002), the
## second three semitones up, only their top: mic-safe like cast heard (the speaker may go on talking: "Rebar go, cast corn").
func _order_click_v1() -> PackedFloat32Array:
	var tk := Rec.trim(Rec.load_mono(K_UI + "tick_002.ogg"), -45.0)
	var a := Rec.highpass(tk, 4500.0, 2)
	var b := Rec.highpass(Rec.pitch(tk, 3.0), 4500.0, 2)
	var s := Rec.fade(Rec.mix(a, b, 0.07), 0.002, 0.02)
	return _mic_safe(s, -9.0)


## The speech band out, then a peak level: every cast-heard cue ends here.
static func _mic_safe(s: PackedFloat32Array, peak_db: float) -> PackedFloat32Array:
	return Rec.normalize(Rec.notch_band(s, 300.0, 4500.0, 3), peak_db)


# ---------------------------------------------------------------- 1. cast heard: four directions

## (a2) The user's pick (v4a) made mic-safe by length: the same swell cut to its last 0.25 s, so it is over before the
## spell word gets going (round 3: a loud high swell over the word's onset masks "h"/"k").
func _cast_armed_v4a2() -> PackedFloat32Array:
	var s := Rec.trim(Rec.load_mono(K_RPG + "knifeSlice2.ogg"), -50.0)
	s = Rec.reverse(s)
	s = Rec.cut(s, maxf(s.size() / float(RATE) - 0.25, 0.0))
	s = Rec.fade(s, 0.06, 0.012, 2.0)
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


## A sizzle that dies: high-passed hiss falling away plus sparse soft crackle, `dur` seconds from `start`.
func _add_sizzle(o: PackedFloat32Array, start: float, dur: float) -> void:
	_add_noise(o, start, dur, func(k: float) -> float: return 6000.0 - 2000.0 * k, 1.0, 2, 0.35,
			func(k: float) -> float: return minf(k * 20.0, 1.0) * pow(1.0 - k, 2.5))
	_add_soft_crackle(o, start, dur * 0.8, 28.0, 0.35, 5000.0)


# ---------------------------------------------------------------- 3. fireball from qubodup's recordings

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


# ---------------------------------------------------------------- paper (the user's pick, 2026-10-18)

## The forms' paper sound: Kenney RPG bookFlip3 as recorded, its silence trimmed and its tail faded, levelled to -3 dB
## peak. No speech-band notch: forms are not open while casting.
func _paper_flip() -> PackedFloat32Array:
	var s := Rec.trim(Rec.load_mono(K_RPG + "bookFlip3.ogg"), -50.0, 0.003)
	return Rec.normalize(Rec.fade(s, 0.002, 0.04), -3.0)


# ---------------------------------------------------------------- 5. elevator: a lobby chime, two soft tones falling

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


# ---------------------------------------------------------------- explosive props (2026-10-19)

## v6, after the probe (C: "cast heal" said over v5 was heard as "CAST VEAL": its hiss, still at 80% when the spell word
## starts, masked the "h"): the same "pssht", then the hiss drops to a quiet, narrow sizzle at 7 kHz (a fifth of the
## attack) that dies over the fuse, with a sparse crackle. The fuse's warning on screen does the rest.
func _fuse_hiss_v6() -> PackedFloat32Array:
	var o := _buf(1.3)
	_add_noise(o, 0.0, 0.14, func(k: float) -> float: return 7200.0 - 1800.0 * k, 1.2, 2, 1.0,
			func(k: float) -> float: return minf(k * 40.0, 1.0) * pow(1.0 - k, 1.5))
	_add_noise(o, 0.06, 1.24, func(k: float) -> float: return 7000.0 + 500.0 * sin(TAU * 11.0 * k), 4.0, 1, 0.22,
			func(k: float) -> float: return minf(k * 30.0, 1.0) * exp(-2.2 * k) * (0.7 + 0.3 * sin(TAU * 23.0 * k)))
	_add_soft_crackle(o, 0.1, 1.15, 14.0, 0.08, 6000.0)
	_fade_out(o, 0.05)
	return _normalize(o, -10.0)


# ---------------------------------------------------------------- goblin scout fireworks (2026-10-20)

## One rocket of the goblin scout's volley (FireworksFx): the recording's whistle and bang (Rudmer_Rotteveel, CC0), its
## start cut so the bang lands 0.77 s in, on the rocket's burst (FireworksFx RISE_TIME + RICOCHET_TIME). The game plays
## it once per rocket with pitch jitter, so a volley of three reads as three (user, 2026-10-20: "use the firework sound
## we have for them. Maybe altered to read as multiple?").
func _firework_v1() -> PackedFloat32Array:
	var s := Rec.cut(Rec.load_mono(FIREWORK), 0.38)
	return Rec.normalize(Rec.fade(s, 0.03, 0.45), -3.0)
