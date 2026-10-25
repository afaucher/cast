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
const FIRE_SPELL := "freesound/442871__qubodup__fire-spell.wav"
const BOW_DRAWN := "freesound/490556__paveroux__bow-drawn.ogg"
const USER_IMP := "user/imp_raw.wav"
const USER_CLIMB := "user/climb_raw.wav"
const USER_OUCH_1 := "user/ouch1_raw.wav"
const USER_OUCH_2 := "user/ouch2_raw.wav"
const USER_WARCRY := "user/warcry_raw.wav"
const USER_CHICKEN := "user/chicken_raw.wav"

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
	# sewers and lava (2026-10-21): water is all synth (no splash recording in the packs)
	"gator_hiss_v3": ["synth"],
	"gator_snap_v1": [K_IMPACT + "impactWood_light_000.ogg", K_RPG + "metalLatch.ogg", K_IMPACT + "impactSoft_medium_000.ogg"],
	"gator_splash_v2": [K_IMPACT + "impactSoft_heavy_000.ogg"],
	"gator_thrash_v4": [K_IMPACT + "impactSoft_medium_000.ogg", K_IMPACT + "impactSoft_medium_002.ogg"],
	"goo_throw_v2": ["synth"],
	"goo_splat_v1": [K_IMPACT + "impactSoft_heavy_000.ogg"],
	"goo_splash_v1": ["synth"],
	"goo_ignite_v1": [FIRE_SPELL, K_IMPACT + "impactSoft_heavy_000.ogg"],
	"goo_wash_v1": ["synth"],
	"wire_spark_v1": [K_UI + "glitch_001.ogg", K_UI + "glitch_003.ogg", K_IMPACT + "impactMetal_light_000.ogg"],
	"wire_buzz_v4": ["synth"],
	"wire_shock_v1": ["synth"],
	"wire_fizzle_v2": ["synth"],
	"wade_step_v1": ["synth"],
	"lava_bubble_v1": ["synth"],
	"lava_crust_v2": [K_IMPACT + "impactSoft_heavy_000.ogg"],
	"lava_crack_v1": [K_IMPACT + "impactMining_000.ogg", K_IMPACT + "impactMining_002.ogg", K_IMPACT + "impactMining_004.ogg"],
	"lava_sizzle_v1": [K_IMPACT + "impactSoft_heavy_000.ogg"],
	# footsteps, jumps, climbs, falls, ouch, imps, and default attacks/hits (2026-10-22)
	"step_hard_v1": [K_IMPACT + "footstep_concrete_001.ogg"],
	"step_soft_v1": [K_IMPACT + "footstep_carpet_001.ogg"],
	"step_wood_v1": [K_IMPACT + "footstep_wood_001.ogg"],
	"step_metal_v1": [K_IMPACT + "footstep_concrete_003.ogg", K_IMPACT + "impactTin_medium_000.ogg"],
	"land_thud_v1": [K_IMPACT + "impactSoft_heavy_000.ogg", K_IMPACT + "footstep_concrete_002.ogg"],
	"fall_heavy_v1": [K_IMPACT + "impactPunch_heavy_000.ogg", K_IMPACT + "footstep_concrete_002.ogg", K_IMPACT + "impactPlank_medium_000.ogg"],
	"jump_v1": [K_RPG + "cloth1.ogg", K_IMPACT + "footstep_concrete_001.ogg"],
	"climb_v1": [USER_CLIMB, K_RPG + "cloth1.ogg"],
	"ouch_v1": [USER_OUCH_1, K_IMPACT + "impactPunch_medium_001.ogg"],
	"ouch_2_v1": [USER_OUCH_2, K_IMPACT + "impactPunch_medium_001.ogg"],
	"imp_yip_v1": [USER_IMP],
	"imp_chatter_v1": [USER_IMP],
	"imp_hurt_v1": [USER_IMP],
	"swing_light_v1": [K_RPG + "knifeSlice.ogg", K_RPG + "cloth2.ogg"],
	"swing_heavy_v1": [K_IMPACT + "impactPunch_heavy_002.ogg", K_IMPACT + "impactMetal_heavy_001.ogg", K_IMPACT + "impactMining_000.ogg"],
	"swing_spin_v1": [K_RPG + "cloth3.ogg", K_RPG + "cloth1.ogg"],
	"bow_shot_v1": [BOW_DRAWN, K_RPG + "knifeSlice.ogg", K_IMPACT + "impactWood_light_000.ogg"],
	"boulder_roll_v1": [K_IMPACT + "impactMining_001.ogg"],
	"slam_ground_v1": [K_IMPACT + "impactPunch_heavy_001.ogg", K_IMPACT + "impactMining_001.ogg", K_IMPACT + "impactPunch_heavy_000.ogg"],
	"hit_body_v1": [K_IMPACT + "impactPunch_medium_000.ogg", K_IMPACT + "impactSoft_medium_001.ogg"],
	"hit_heavy_v1": [K_IMPACT + "impactPunch_heavy_002.ogg", K_IMPACT + "impactWood_heavy_001.ogg"],
	"hit_arrow_v1": [K_RPG + "chop.ogg", K_IMPACT + "impactWood_light_001.ogg"],
	"hit_shield_v1": [K_IMPACT + "impactMetal_heavy_001.ogg", K_IMPACT + "impactWood_heavy_000.ogg"],
	"prop_dent_v1": [K_IMPACT + "impactWood_medium_001.ogg", K_IMPACT + "impactPlank_medium_002.ogg"],
	"prop_break_v1": [K_IMPACT + "impactWood_heavy_002.ogg", K_IMPACT + "impactPlank_medium_001.ogg", K_IMPACT + "impactPlank_medium_003.ogg"],
	"mailbox_break_v1": [K_IMPACT + "impactMetal_heavy_003.ogg", K_RPG + "metalPot2.ogg", K_IMPACT + "impactPlank_medium_000.ogg"],
	# war cries (2026-10-25: the user's own takes, played as pools; audio-plan.md "War cries") and the chickens' clucks
	"cry_grunt_1": [USER_WARCRY],
	"cry_grunt_2": [USER_WARCRY],
	"cry_brute_1": [USER_WARCRY],
	"cry_brute_2": [USER_WARCRY],
	"cry_swarmer_1": [USER_WARCRY],
	"cry_swarmer_2": [USER_WARCRY],
	"cry_monster_1": [USER_WARCRY],
	"cry_monster_2": [USER_WARCRY],
	"chicken_cluck_1": [USER_CHICKEN],
	"chicken_cluck_2": [USER_CHICKEN],
	"chicken_cluck_3": [USER_CHICKEN],
	"chicken_cluck_4": [USER_CHICKEN],
	"chicken_cluck_5": [USER_CHICKEN],
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


# ---------------------------------------------------------------- sewers and lava (2026-10-21)

## Water droplets: tiny "plinks" (a sine rising half again as it dies, 12-35 ms), `per_sec` on average, f_lo..f_hi Hz,
## fading out across `length`.
func _drops(o: PackedFloat32Array, start: float, length: float, per_sec: float, f_lo: float, f_hi: float, amp: float) -> void:
	var t := start
	while true:
		t += _rng.randf_range(0.3, 1.7) / per_sec
		if t >= start + length:
			break
		var f := _rng.randf_range(f_lo, f_hi)
		var d := _rng.randf_range(0.012, 0.035)
		var a := amp * _rng.randf_range(0.3, 1.0) * (1.0 - (t - start) / length)
		_add_tone(o, t, d, func(k: float) -> float: return f * (1.0 + 0.5 * k), a,
				func(k: float) -> float: return minf(k * 25.0, 1.0) * exp(-4.0 * k))


## Wet texture: short band-passed noise grains (5-25 ms, centres f_lo..f_hi), `per_sec` on average, their level following
## env(k) across `length`. It is what makes noise read as water rather than hiss.
func _slosh(o: PackedFloat32Array, start: float, length: float, per_sec: float, f_lo: float, f_hi: float, amp: float,
		env: Callable) -> void:
	var t := start
	while true:
		t += _rng.randf_range(0.2, 1.8) / per_sec
		if t >= start + length:
			break
		var fc := exp(_rng.randf_range(log(f_lo), log(f_hi)))
		var d := _rng.randf_range(0.005, 0.025)
		var a := amp * _rng.randf_range(0.4, 1.0) * float(env.call((t - start) / length))
		_add_filtered_noise(o, t, d, func(_k: float) -> float: return fc, 2.5, 1, a, 0.002, d * 0.35)


## A splash of `size` (0..1) at `start`: the slap (high-passed noise, a few ms), the wet body (slosh), a low plunge under
## 100 Hz for the big ones, and droplets falling back.
func _splash_at(o: PackedFloat32Array, start: float, size: float, amp: float, slap: float = 0.5, lo: float = 700.0) -> void:
	_add_filtered_noise(o, start, 0.08 + 0.1 * size, func(_k: float) -> float: return 1200.0, 0.7, 2, amp * slap, 0.002,
			0.012 + 0.025 * size)
	_slosh(o, start, 0.15 + 0.3 * size, 160.0 + 220.0 * size, lo, 5000.0, amp * 2.0,
			func(k: float) -> float: return minf(k * 12.0, 1.0) * pow(1.0 - k, 1.6))
	if size > 0.5:
		_add_tone(o, start, 0.16, func(k: float) -> float: return 85.0 - 30.0 * k, amp * 0.6 * size,
				func(k: float) -> float: return minf(k * 30.0, 1.0) * exp(-5.0 * k))
	_drops(o, start + 0.08 + 0.1 * size, 0.2 + 0.35 * size, 18.0 + 20.0 * size, 2500.0, 6500.0, amp * 0.2)


## A soft recorded thud from the Impact pack, trimmed and low-passed at `hz` (cut to `length` s when > 0).
static func _thud(file: String, hz: float, length: float = -1.0) -> PackedFloat32Array:
	var s := Rec.lowpass(Rec.trim(Rec.load_mono(K_IMPACT + file), -45.0, 0.0), hz, 2)
	return Rec.fade(Rec.cut(s, 0.0, length), 0.0, 0.08) if length > 0.0 else s


# --- the gator (scripts/monsters/gator.gd) ---------------------------------------------------------------------------------

func _gator_hiss_v3() -> PackedFloat32Array:
	var o := _buf(0.55)
	_add_noise(o, 0.0, 0.12, func(_k: float) -> float: return 3800.0, 0.8, 2, 0.9,
			func(k: float) -> float: return minf(k * 25.0, 1.0) * pow(1.0 - k, 1.5))
	_add_noise(o, 0.08, 0.45, func(_k: float) -> float: return 9000.0, 5.0, 1, 0.15,
			func(k: float) -> float: return minf(k * 10.0, 1.0) * (1.0 - 0.5 * k))
	for h: Array in [[52.0, 0.7], [104.0, 0.35]]:
		var f: float = h[0]
		_add_tone(o, 0.0, 0.55, func(_k: float) -> float: return f, float(h[1]),
				func(k: float) -> float: return minf(k * 10.0, 1.0) * (0.6 + 0.4 * k) * (0.55 + 0.45 * sin(TAU * 23.0 * 0.55 * k)))
	_fade_out(o, 0.03)
	return _normalize(o, -3.0)


func _gator_snap_v1() -> PackedFloat32Array:
	var clack := Rec.pitch(Rec.trim(Rec.load_mono(K_IMPACT + "impactWood_light_000.ogg"), -45.0, 0.0), 2.0)
	clack = Rec.fade(Rec.cut(clack, 0.0, 0.16), 0.0, 0.1)
	var click := Rec.highpass(Rec.cut(Rec.trim(Rec.load_mono(K_RPG + "metalLatch.ogg"), -30.0, 0.0), 0.0, 0.05), 3000.0, 2)
	var s := Rec.mix(Rec.normalize(clack, -1.0), Rec.normalize(Rec.fade(click, 0.0, 0.03), -1.0), 0.0, -8.0)
	s = Rec.mix(s, Rec.normalize(_thud("impactSoft_medium_000.ogg", 250.0), -1.0), 0.004, -3.0)
	var o := _buf(0.25)
	_drops(o, 0.03, 0.18, 30.0, 3000.0, 6000.0, 1.0)
	s = Rec.mix(s, Rec.normalize(o, -1.0), 0.0, -14.0)
	return Rec.normalize(Rec.fade(s, 0.0, 0.06), -1.0)


func _gator_splash_v2() -> PackedFloat32Array:
	var o := _buf(0.75)
	_splash_at(o, 0.0, 0.85, 1.0, 0.1, 1800.0)
	var s := Rec.mix(Rec.normalize(o, -1.0), Rec.normalize(_thud("impactSoft_heavy_000.ogg", 220.0), -1.0), 0.0, -1.0)
	return Rec.normalize(Rec.fade(s, 0.0, 0.12), -2.0)


func _gator_thrash_v4() -> PackedFloat32Array:
	var o := _buf(1.0)
	_splash_at(o, 0.0, 0.9, 1.0, 0.1, 1800.0)
	_drops(o, 0.35, 0.5, 20.0, 3000.0, 6500.0, 0.2)
	var s := Rec.normalize(o, -1.0)
	var slaps: Array[PackedFloat32Array] = [Rec.normalize(_thud("impactSoft_medium_000.ogg", 250.0), -1.0),
			Rec.normalize(_thud("impactSoft_medium_002.ogg", 250.0), -1.0)]
	s = Rec.mix(s, slaps[0], 0.0, -1.0)
	var at: Array[float] = [0.22, 0.4, 0.62]
	for i in at.size():
		s = Rec.mix(s, slaps[(i + 1) % 2], at[i], -1.0 - 3.0 * float(i))
	return Rec.normalize(Rec.fade(s, 0.0, 0.25), -2.0)


# --- the goo imp (goo_imp.gd, goo_ball.gd, goo_patch.gd) ------------------------------------------------------------------

func _goo_throw_v2() -> PackedFloat32Array:
	var o := _buf(0.24)
	_slosh(o, 0.0, 0.07, 400.0, 900.0, 3500.0, 1.0, func(k: float) -> float: return minf(k * 6.0, 1.0) * pow(1.0 - k, 1.2))
	_add_tone(o, 0.0, 0.06, func(k: float) -> float: return 180.0 - 60.0 * k, 0.25,
			func(k: float) -> float: return minf(k * 15.0, 1.0) * (1.0 - k))
	_add_noise(o, 0.01, 0.14, func(_k: float) -> float: return 8500.0, 1.5, 1, 0.4,
			func(k: float) -> float: return minf(k * 10.0, 1.0) * pow(1.0 - k, 2.0))
	_drops(o, 0.03, 0.12, 25.0, 3000.0, 6000.0, 0.12)
	return _normalize(o, -4.0)


func _goo_splat_v1() -> PackedFloat32Array:
	var o := _buf(0.42)
	_slosh(o, 0.0, 0.14, 500.0, 600.0, 3500.0, 1.0, func(k: float) -> float: return pow(1.0 - k, 1.4))
	_slosh(o, 0.06, 0.25, 60.0, 1500.0, 4500.0, 0.5, func(k: float) -> float: return pow(1.0 - k, 2.0))
	_drops(o, 0.05, 0.25, 22.0, 2500.0, 5500.0, 0.15)
	var s := Rec.mix(Rec.normalize(o, -1.0), Rec.normalize(_thud("impactSoft_heavy_000.ogg", 300.0, 0.3), -1.0), 0.0, -4.0)
	return Rec.normalize(Rec.fade(s, 0.0, 0.08), -2.0)


func _goo_splash_v1() -> PackedFloat32Array:
	var o := _buf(0.5)
	_splash_at(o, 0.0, 0.35, 1.0)
	_fade_out(o, 0.08)
	return _normalize(o, -3.0)


func _goo_ignite_v1() -> PackedFloat32Array:
	var o := _buf(0.1)
	_add_noise(o, 0.0, 0.1, func(_k: float) -> float: return 600.0, 0.7, 0, 1.0, func(k: float) -> float: return k * k)
	var fire := Rec.pitch(Rec.trim(Rec.load_mono(FIRE_SPELL), -50.0, 0.0), -6.0)
	fire = Rec.fade(Rec.lowpass(Rec.cut(fire, 0.0, 0.7), 2000.0, 1), 0.005, 0.3)
	var s := Rec.mix(Rec.normalize(o, -12.0), Rec.normalize(fire, -1.0), 0.09)
	s = Rec.mix(s, Rec.normalize(_thud("impactSoft_heavy_000.ogg", 180.0), -1.0), 0.09, -4.0)
	return Rec.normalize(Rec.fade(s, 0.0, 0.1), -1.0)


func _goo_wash_v1() -> PackedFloat32Array:
	var o := _buf(0.65)
	_add_noise(o, 0.0, 0.18, func(_k: float) -> float: return 5000.0, 0.8, 2, 0.8,
			func(k: float) -> float: return minf(k * 30.0, 1.0) * pow(1.0 - k, 1.5))
	_add_noise(o, 0.05, 0.6, func(_k: float) -> float: return 7500.0, 3.0, 1, 0.5,
			func(k: float) -> float: return minf(k * 10.0, 1.0) * exp(-3.5 * k))
	var fizz := _buf(0.65)
	_add_crackle(fizz, 0.02, 0.55, 90.0, 0.4)
	o = Rec.mix(o, Rec.highpass(fizz, 4000.0, 2), 0.0)
	_drops(o, 0.05, 0.35, 20.0, 3500.0, 7000.0, 0.15)
	_fade_out(o, 0.05)
	return _normalize(o, -5.0)


# --- the live wire (scripts/world/sewer/live_wire.gd) ----------------------------------------------------------------------

func _wire_spark_v1() -> PackedFloat32Array:
	var glitches: Array[PackedFloat32Array] = [Rec.highpass(Rec.load_mono(K_UI + "glitch_001.ogg"), 1500.0, 2),
			Rec.highpass(Rec.load_mono(K_UI + "glitch_003.ogg"), 1500.0, 2)]
	var snaps := _buf(0.6)
	var o := _buf(0.6)
	var t := 0.0
	var i := 0
	while t < 0.3:
		var lvl := 1.0 - 0.6 * t / 0.3
		_add_filtered_noise(snaps, t, 0.012, func(_k: float) -> float: return 2200.0, 0.7, 2, 3.0 * lvl * _rng.randf_range(0.6, 1.0),
				0.0003, 0.003)
		o = Rec.mix(o, glitches[i % 2], t, -2.0 - 1.5 * float(i))
		t += _rng.randf_range(0.02, 0.05) + 0.06 * t
		i += 1
	o = Rec.mix(o, snaps, 0.0)
	var clack := Rec.pitch(Rec.trim(Rec.load_mono(K_IMPACT + "impactMetal_light_000.ogg"), -45.0, 0.0), 3.0)
	o = Rec.mix(o, Rec.fade(Rec.cut(clack, 0.0, 0.18), 0.0, 0.12), 0.0, -6.0)
	var tail := _buf(0.6)
	_add_sizzle(tail, 0.22, 0.36)
	o = Rec.mix(Rec.normalize(o, -1.0), Rec.normalize(tail, -1.0), 0.0, -9.0)
	return Rec.normalize(Rec.fade(o, 0.0, 0.05), -2.0)


func _wire_buzz_v4() -> PackedFloat32Array:
	var dur := 6.0
	var o := _buf(dur)
	var chop := func(k: float) -> float:
		return maxf(sin(TAU * 120.0 * k * dur), 0.0) * (0.85 + 0.15 * sin(TAU * 0.4 * k * dur))
	_add_noise(o, 0.0, dur, func(_k: float) -> float: return 160.0, 0.7, 0, 3.0, chop)
	_add_noise(o, 0.0, dur, func(_k: float) -> float: return 7000.0, 2.0, 1, 0.5, chop)
	var cr := _buf(dur)
	_add_crackle(cr, 0.0, dur, 4.0, 0.35)
	o = Rec.mix(o, Rec.highpass(cr, 5000.0, 2), 0.0)
	o = Rec.fade(Rec.notch_band(o, 300.0, 4500.0, 3), 0.08, 0.6)
	return _normalize(o, -6.0)


func _wire_shock_v1() -> PackedFloat32Array:
	var hi := _buf(0.45)
	_add_filtered_noise(hi, 0.0, 0.01, func(_k: float) -> float: return 1000.0, 0.7, 2, 1.0, 0.0003, 0.003)
	_add_filtered_noise(hi, 0.002, 0.15, func(_k: float) -> float: return 3500.0, 0.7, 2, 0.5, 0.001, 0.04)
	var cr := _buf(0.45)
	_add_crackle(cr, 0.0, 0.35, 90.0, 1.0)
	hi = Rec.mix(hi, Rec.highpass(cr, 4000.0, 2), 0.0)
	var lo := _buf(0.45)
	_add_tone(lo, 0.0, 0.25, func(k: float) -> float: return 75.0 - 20.0 * k, 0.6,
			func(k: float) -> float: return minf(k * 40.0, 1.0) * exp(-5.0 * k))
	for f: float in [60.0, 120.0]:
		_add_tone(lo, 0.0, 0.3, func(_k: float) -> float: return f, 0.35,
				func(k: float) -> float: return minf(k * 30.0, 1.0) * (1.0 - k) * (0.7 + 0.3 * sin(TAU * 31.0 * 0.3 * k)))
	var o := Rec.mix(Rec.normalize(hi, -1.0), Rec.normalize(lo, -1.0), 0.0, -4.0)
	return _normalize(o, -1.0)


func _wire_fizzle_v2() -> PackedFloat32Array:
	var o := _buf(0.8)
	var gate := func(k: float) -> float: return minf(k * 20.0, 1.0) * minf((1.0 - k) * 20.0, 1.0)
	var t := 0.0
	while t < 0.5:
		var on := _rng.randf_range(0.03, 0.08) * (1.0 - t)
		var lvl := 1.0 - t / 0.6
		for f: float in [60.0, 120.0]:
			_add_tone(o, t, on, func(_k: float) -> float: return f, 0.45 * lvl, gate)
		_add_noise(o, t, on, func(_k: float) -> float: return 8500.0, 5.0, 1, 0.5 * lvl, gate)
		_add_filtered_noise(o, t + on, 0.004, func(_k: float) -> float: return 3000.0, 0.7, 2, 0.5 * lvl, 0.0003, 0.0015)
		t += on + _rng.randf_range(0.03, 0.06) + 0.25 * t
	_add_filtered_noise(o, 0.6, 0.01, func(_k: float) -> float: return 2000.0, 0.7, 2, 0.45, 0.0003, 0.003)
	_add_noise(o, 0.6, 0.18, func(_k: float) -> float: return 8000.0, 4.0, 1, 0.2, func(k: float) -> float: return pow(1.0 - k, 2.0))
	return _normalize(o, -4.0)


# --- wading (scripts/world/wading.gd) --------------------------------------------------------------------------------------

func _wade_step_v1() -> PackedFloat32Array:
	var o := _buf(0.26)
	_slosh(o, 0.0, 0.16, 260.0, 500.0, 3000.0, 1.0, func(k: float) -> float: return minf(k * 6.0, 1.0) * pow(1.0 - k, 1.5))
	_add_tone(o, 0.0, 0.08, func(k: float) -> float: return 150.0 - 40.0 * k, 0.25,
			func(k: float) -> float: return minf(k * 20.0, 1.0) * (1.0 - k))
	_drops(o, 0.06, 0.18, 18.0, 2500.0, 5000.0, 0.12)
	_fade_out(o, 0.04)
	return _normalize(o, -3.0)


# --- lava (scripts/world/lava/) ---------------------------------------------------------------------------------------------

func _lava_bubble_v1() -> PackedFloat32Array:
	var dur := 4.0
	var o := _buf(dur)
	_add_noise(o, 0.0, dur, func(_k: float) -> float: return 110.0, 0.7, 0, 3.0,
			func(k: float) -> float: return 0.6 + 0.4 * sin(TAU * 0.45 * dur * k + 0.7))
	var t := 0.15
	while t < dur - 0.3:
		var f0 := _rng.randf_range(55.0, 85.0)
		var d := _rng.randf_range(0.08, 0.16)
		var a := _rng.randf_range(0.35, 0.8)
		_add_tone(o, t, d, func(k: float) -> float: return f0 * (1.0 + k), a,
				func(k: float) -> float: return minf(k * 12.0, 1.0) * exp(-3.0 * k))
		_add_filtered_noise(o, t + d * 0.8, 0.03, func(_k: float) -> float: return 500.0, 0.7, 0, a * 0.8, 0.001, 0.008)
		t += _rng.randf_range(0.18, 0.55)
	o = Rec.fade(Rec.lowpass(o, 600.0, 2), 0.4, 0.5)
	return _normalize(o, -3.0)


func _lava_crust_v2() -> PackedFloat32Array:
	var o := _buf(1.3)
	_add_noise(o, 0.0, 0.12, func(_k: float) -> float: return 3500.0, 0.8, 2, 1.0,
			func(k: float) -> float: return minf(k * 40.0, 1.0) * pow(1.0 - k, 1.5))
	_add_noise(o, 0.06, 1.2, func(_k: float) -> float: return 7500.0, 4.0, 1, 0.45,
			func(k: float) -> float: return minf(k * 30.0, 1.0) * exp(-2.4 * k))
	var cr := _buf(1.3)
	_add_crackle(cr, 0.06, 1.0, 18.0, 0.25)
	o = Rec.mix(o, Rec.highpass(cr, 5000.0, 2), 0.0)
	o = Rec.mix(Rec.normalize(o, -1.0), Rec.normalize(_thud("impactSoft_heavy_000.ogg", 160.0), -1.0), 0.0, -5.0)
	return Rec.normalize(Rec.fade(o, 0.0, 0.15), -2.0)


func _lava_crack_v1() -> PackedFloat32Array:
	var o := _buf(2.05)
	_add_noise(o, 0.0, 2.05, func(_k: float) -> float: return 90.0, 0.8, 0, 1.0,
			func(k: float) -> float: return 0.2 + 0.8 * pow(k, 1.5))
	o = Rec.normalize(o, -12.0)
	var rocks: Array[PackedFloat32Array] = []
	for n: String in ["000", "002", "004"]:
		rocks.append(Rec.trim(Rec.load_mono(K_IMPACT + "impactMining_%s.ogg" % n), -45.0, 0.0))
	var at: Array[float] = [0.0, 0.62, 1.05, 1.36, 1.6, 1.78, 1.92]
	for i in at.size():
		var hit := Rec.pitch(rocks[i % 3], -2.0 * float(i % 3))
		hit = Rec.normalize(Rec.fade(Rec.cut(hit, 0.0, 0.14), 0.0, 0.08), -1.0)
		var lvl := -9.0 + 8.0 * float(i) / float(at.size() - 1)
		o = Rec.mix(o, hit, at[i], lvl - 3.0)
		var grit := _buf(0.06)
		for j in _rng.randi_range(3, 4):
			_add_filtered_noise(grit, float(j) * _rng.randf_range(0.006, 0.011), 0.02, func(_k: float) -> float: return 2000.0,
					0.7, 2, _rng.randf_range(0.5, 1.0), 0.0003, 0.003)
		o = Rec.mix(o, Rec.normalize(grit, -1.0), at[i], lvl)
	return Rec.normalize(Rec.fade(o, 0.0, 0.05), -2.0)


func _lava_sizzle_v1() -> PackedFloat32Array:
	var o := _buf(0.95)
	_add_noise(o, 0.0, 0.12, func(_k: float) -> float: return 3000.0, 0.8, 2, 1.0,
			func(k: float) -> float: return minf(k * 40.0, 1.0) * pow(1.0 - k, 1.5))
	_add_noise(o, 0.03, 0.9, func(_k: float) -> float: return 6000.0, 2.0, 1, 0.8,
			func(k: float) -> float: return minf(k * 15.0, 1.0) * exp(-3.2 * k) * (0.75 + 0.25 * sin(TAU * 17.0 * k)))
	var cr := _buf(0.95)
	_add_crackle(cr, 0.02, 0.85, 120.0, 0.6)
	o = Rec.mix(o, Rec.highpass(cr, 4000.0, 2), 0.0)
	for b: Array in [[0.15, 70.0], [0.4, 60.0]]:
		var f0: float = b[1]
		_add_tone(o, float(b[0]), 0.12, func(k: float) -> float: return f0 * (1.0 + k), 0.35,
				func(k: float) -> float: return minf(k * 12.0, 1.0) * exp(-3.0 * k))
	o = Rec.mix(Rec.normalize(o, -1.0), Rec.normalize(_thud("impactSoft_heavy_000.ogg", 250.0, 0.35), -1.0), 0.0, -4.0)
	return Rec.normalize(Rec.fade(o, 0.0, 0.12), -1.5)


# --- footsteps, jumps, climbs, falls, ouch, imps, and default attacks/hits (2026-10-22) -----------------------------------

## One dry footstep on a material (0.13 s): Kenney footstep cut to its heel strike, 1-pole low-pass so surface transient
## reads clearly while staying gentle under speech.
static func _step(file: String, lp: float, semis: float = 0.0) -> PackedFloat32Array:
	var s := Rec.trim(Rec.load_mono(K_IMPACT + file), -42.0, 0.002)
	s = Rec.cut(s, 0.0, 0.13)
	if semis != 0.0:
		s = Rec.pitch(s, semis)
	s = Rec.lowpass(s, lp, 1)
	return Rec.normalize(Rec.fade(s, 0.001, 0.045), -1.5)


## Concrete, slate, tile, marble, stone, basalt: a crisp heel.
func _step_hard_v1() -> PackedFloat32Array:
	return _step("footstep_concrete_001.ogg", 2800.0, -0.5)


## Carpet and rubber: a soft pat.
func _step_soft_v1() -> PackedFloat32Array:
	return _step("footstep_carpet_001.ogg", 1600.0)


## Wood: a hollow knock.
func _step_wood_v1() -> PackedFloat32Array:
	return _step("footstep_wood_001.ogg", 3000.0)


## Diamond plate (4A): dry boot heel + short 38 ms damped dead-plate thud (<1800 Hz), zero bell ring.
func _step_metal_v1() -> PackedFloat32Array:
	var heel := Rec.trim(Rec.load_mono(K_IMPACT + "footstep_concrete_003.ogg"), -42.0, 0.002)
	heel = Rec.lowpass(Rec.cut(heel, 0.0, 0.068), 2200.0, 1)
	var tin := Rec.trim(Rec.load_mono(K_IMPACT + "impactTin_medium_000.ogg"), -42.0, 0.0)
	tin = Rec.lowpass(Rec.cut(tin, 0.0, 0.038), 1800.0, 2)
	tin = Rec.fade(tin, 0.001, 0.020)
	var s := Rec.mix(Rec.normalize(heel, -1.0), Rec.normalize(tin, -1.0), 0.002, -9.0)
	return Rec.normalize(Rec.fade(s, 0.002, 0.022), -2.0)


## A landing from 1-2 levels (0.25 s): a soft body thud under 300 Hz and both heels at once.
func _land_thud_v1() -> PackedFloat32Array:
	var body := _thud("impactSoft_heavy_000.ogg", 300.0, 0.25)
	var heel := _step("footstep_concrete_002.ogg", 1600.0, -2.0)
	return Rec.normalize(Rec.fade(Rec.mix(Rec.normalize(body, -1.0), heel, 0.0, -5.0), 0.0, 0.08), -2.0)


## A heavy landing from 3+ levels or a shove landing (0.28 s): sub-bass punch, heel impact, and floor thud.
func _fall_heavy_v1() -> PackedFloat32Array:
	var sub := Rec.pitch(Rec.trim(Rec.load_mono(K_IMPACT + "impactPunch_heavy_000.ogg"), -45.0, 0.0), -4.0)
	sub = Rec.lowpass(Rec.cut(sub, 0.0, 0.28), 260.0, 2)
	var heel := _step("footstep_concrete_002.ogg", 1800.0, -3.0)
	var plank := Rec.lowpass(Rec.cut(Rec.trim(Rec.load_mono(K_IMPACT + "impactPlank_medium_000.ogg"), -45.0, 0.0), 0.0, 0.20), 1400.0, 2)
	var s := Rec.mix(Rec.normalize(sub, -1.0), heel, 0.0, -3.0)
	s = Rec.mix(s, Rec.normalize(plank, -1.0), 0.012, -5.0)
	return Rec.normalize(Rec.fade(s, 0.001, 0.09), -1.0)


## A +1 step hop (0.12 s): cloth rustle + toe push-off.
func _jump_v1() -> PackedFloat32Array:
	var cloth := Rec.cut(Rec.trim(Rec.load_mono(K_RPG + "cloth1.ogg"), -42.0, 0.002), 0.0, 0.12)
	var toe := _step("footstep_concrete_001.ogg", 1800.0, 2.5)
	var s := Rec.mix(Rec.normalize(cloth, -2.0), toe, 0.0, -3.0)
	return Rec.normalize(Rec.fade(s, 0.002, 0.04), -2.5)


## A +2 climb / mantle (0.125 s): user's Recording (4) trimmed to 0.595..0.720 s, high-passed at 140 Hz, with a light cloth scuff.
func _climb_v1() -> PackedFloat32Array:
	var raw := Rec.load_mono(USER_CLIMB)
	var clean := Rec.highpass(Rec.cut(raw, 0.595, 0.720), 140.0, 2)
	clean = Rec.normalize(Rec.fade(clean, 0.004, 0.018), -2.0)
	var scuff := Rec.lowpass(Rec.cut(Rec.trim(Rec.load_mono(K_RPG + "cloth1.ogg"), -40.0, 0.002), 0.0, 0.11), 2200.0, 1)
	return Rec.normalize(Rec.mix(clean, Rec.normalize(scuff, -1.0), 0.0, -11.0), -2.0)


## Hero / Employee hurt ("ouch" 1): user's Recording (5) trimmed to 0.195..0.335 s, high-passed at 140 Hz, over a low body thump.
func _ouch_v1() -> PackedFloat32Array:
	var raw := Rec.load_mono(USER_OUCH_1)
	var vox := Rec.highpass(Rec.cut(raw, 0.195, 0.335), 140.0, 2)
	vox = Rec.fade(vox, 0.004, 0.018)
	var body := Rec.lowpass(Rec.cut(Rec.trim(Rec.load_mono(K_IMPACT + "impactPunch_medium_001.ogg"), -45.0, 0.0), 0.0, 0.13), 260.0, 2)
	var s := Rec.mix(Rec.normalize(vox, -1.0), Rec.normalize(body, -1.0), 0.0, -6.0)
	return Rec.normalize(Rec.fade(s, 0.002, 0.02), -1.5)


## Hero / Employee hurt ("ouch" 2): user's Recording (6) trimmed to 0.340..0.485 s, high-passed at 140 Hz, over a low body thump.
func _ouch_2_v1() -> PackedFloat32Array:
	var raw := Rec.load_mono(USER_OUCH_2)
	var vox := Rec.highpass(Rec.cut(raw, 0.340, 0.485), 140.0, 2)
	vox = Rec.fade(vox, 0.004, 0.018)
	var body := Rec.lowpass(Rec.cut(Rec.trim(Rec.load_mono(K_IMPACT + "impactPunch_medium_001.ogg"), -45.0, 0.0), 0.0, 0.13), 260.0, 2)
	var s := Rec.mix(Rec.normalize(vox, -1.0), Rec.normalize(body, -1.0), 0.0, -6.0)
	return Rec.normalize(Rec.fade(s, 0.002, 0.02), -1.5)


static func _imp_slice(t0: float, t1: float) -> PackedFloat32Array:
	var s := Rec.cut(Rec.load_mono(USER_IMP), t0, t1)
	s = Rec.highpass(s, 180.0, 2)
	s = Rec.fade(s, 0.004, 0.015)
	return Rec.normalize(s, -2.0)


## Swarmer imp bite wind-up: user's Recording (3) burst 1 (0.440..0.565 s).
func _imp_yip_v1() -> PackedFloat32Array:
	return _imp_slice(0.440, 0.565)


## Goo imp throw tell: user's Recording (3) burst 2 (0.825..0.975 s).
func _imp_chatter_v1() -> PackedFloat32Array:
	return _imp_slice(0.825, 0.975)


## Imp hurt squeak: user's Recording (3) burst 3 (1.280..1.400 s).
func _imp_hurt_v1() -> PackedFloat32Array:
	return _imp_slice(1.280, 1.400)


## Fast melee swing (Wick bow bash, monster melee): crisp air slice + cloth snap.
func _swing_light_v1() -> PackedFloat32Array:
	var sw := Rec.pitch(Rec.trim(Rec.load_mono(K_RPG + "knifeSlice.ogg"), -45.0, 0.003), -3.0)
	sw = Rec.lowpass(Rec.cut(sw, 0.0, 0.16), 3200.0, 1)
	var cloth := Rec.lowpass(Rec.cut(Rec.trim(Rec.load_mono(K_RPG + "cloth2.ogg"), -42.0, 0.0), 0.0, 0.12), 1800.0, 1)
	var s := Rec.mix(Rec.normalize(sw, -1.0), Rec.normalize(cloth, -1.0), 0.0, -6.0)
	return Rec.normalize(Rec.fade(s, 0.008, 0.04), -2.0)


## Gasket's overhead wrench smash (2A): short downward swing whoosh into a weighty punch + damped low iron/rock smash.
func _swing_heavy_v1() -> PackedFloat32Array:
	var whoosh := _buf(0.09)
	_add_noise(whoosh, 0.0, 0.085, func(k: float) -> float: return 680.0 - 380.0 * k, 1.3, 1, 0.85,
			func(k: float) -> float: return sin(PI * k))
	var punch := Rec.pitch(Rec.trim(Rec.load_mono(K_IMPACT + "impactPunch_heavy_002.ogg"), -45.0, 0.0), -3.0)
	punch = Rec.lowpass(Rec.cut(punch, 0.0, 0.21), 1600.0, 1)
	var metal := Rec.pitch(Rec.trim(Rec.load_mono(K_IMPACT + "impactMetal_heavy_001.ogg"), -45.0, 0.0), -5.0)
	metal = Rec.lowpass(Rec.cut(metal, 0.0, 0.18), 1100.0, 2)
	var rock := Rec.pitch(Rec.trim(Rec.load_mono(K_IMPACT + "impactMining_000.ogg"), -45.0, 0.0), -3.0)
	rock = Rec.lowpass(Rec.cut(rock, 0.0, 0.19), 1800.0, 1)
	var hit := Rec.mix(Rec.normalize(punch, -1.0), Rec.normalize(metal, -1.0), 0.0, -3.5)
	hit = Rec.mix(hit, Rec.normalize(rock, -1.0), 0.005, -3.0)
	var s := Rec.mix(Rec.normalize(whoosh, -3.0), Rec.normalize(hit, -1.0), 0.045, 0.0)
	return Rec.normalize(Rec.fade(s, 0.003, 0.05), -1.0)


## Gasket's 360° wrench spin (1A): continuous 480 ms full-circle Doppler air whirl + coat whip, zero impact thud.
func _swing_spin_v1() -> PackedFloat32Array:
	var o := _buf(0.48)
	_add_noise(o, 0.0, 0.46,
		func(k: float) -> float:
			return 210.0 + 320.0 * sin(PI * k) + 130.0 * sin(TAU * k),
		1.25, 1, 0.9,
		func(k: float) -> float:
			var env := sin(PI * pow(k, 0.8))
			var rot_mod := 0.76 + 0.24 * sin(TAU * k - 0.5)
			return env * rot_mod
	)
	var cloth1 := Rec.pitch(Rec.trim(Rec.load_mono(K_RPG + "cloth3.ogg"), -42.0, 0.002), -3.0)
	cloth1 = Rec.lowpass(Rec.cut(cloth1, 0.0, 0.24), 1500.0, 1)
	var cloth2 := Rec.pitch(Rec.trim(Rec.load_mono(K_RPG + "cloth1.ogg"), -42.0, 0.002), -2.0)
	cloth2 = Rec.lowpass(Rec.cut(cloth2, 0.0, 0.22), 1600.0, 1)
	var s := Rec.mix(Rec.normalize(o, -1.0), Rec.normalize(cloth1, -1.0), 0.02, -4.0)
	s = Rec.mix(s, Rec.normalize(cloth2, -1.0), 0.22, -5.0)
	return Rec.normalize(Rec.fade(s, 0.018, 0.065), -1.5)


## Bow & crossbow release (Wick, Archer, Pavise): taut bowstring twang + wood flex + arrow zip.
func _bow_shot_v1() -> PackedFloat32Array:
	var bow := Rec.trim(Rec.load_mono(BOW_DRAWN), -42.0, 0.002)
	var twang := Rec.pitch(Rec.cut(bow, maxf(0.0, bow.size() / float(RATE) - 0.22)), 5.0)
	twang = Rec.lowpass(Rec.cut(twang, 0.0, 0.16), 2800.0, 1)
	var zip := Rec.pitch(Rec.trim(Rec.load_mono(K_RPG + "knifeSlice.ogg"), -45.0, 0.0), 4.0)
	zip = Rec.lowpass(Rec.cut(zip, 0.0, 0.14), 3800.0, 1)
	var wood := Rec.lowpass(Rec.cut(Rec.trim(Rec.load_mono(K_IMPACT + "impactWood_light_000.ogg"), -45.0, 0.0), 0.0, 0.08), 1600.0, 1)
	var s := Rec.mix(Rec.normalize(wood, -1.0), Rec.normalize(twang, -1.0), 0.0, -2.0)
	s = Rec.mix(s, Rec.normalize(zip, -1.0), 0.015, -2.0)
	return Rec.normalize(Rec.fade(s, 0.002, 0.04), -1.5)


## Rebar's sandstone boulder launch: stony thud + low rolling rumble.
func _boulder_roll_v1() -> PackedFloat32Array:
	var hit := Rec.pitch(Rec.trim(Rec.load_mono(K_IMPACT + "impactMining_001.ogg"), -45.0, 0.0), -5.0)
	hit = Rec.lowpass(Rec.cut(hit, 0.0, 0.24), 1200.0, 2)
	var roll := _buf(0.38)
	_add_noise(roll, 0.0, 0.36, func(k: float) -> float: return 190.0 - 60.0 * k, 1.1, 0, 0.9,
			func(k: float) -> float: return minf(k * 12.0, 1.0) * pow(1.0 - k, 1.3) * (0.75 + 0.25 * sin(TAU * 14.0 * k)))
	var s := Rec.mix(Rec.normalize(hit, -1.0), Rec.normalize(roll, -1.0), 0.0, -2.0)
	return Rec.normalize(Rec.fade(s, 0.003, 0.07), -1.5)


## Rebar's stone-gloved pound / Brute ground slam (3A): short downward fist rush into a deep, dry stone-and-leather pound.
func _slam_ground_v1() -> PackedFloat32Array:
	var rush := _buf(0.08)
	_add_noise(rush, 0.0, 0.075, func(k: float) -> float: return 520.0 - 280.0 * k, 1.2, 1, 0.7,
			func(k: float) -> float: return sin(PI * k))
	var sub := Rec.pitch(Rec.trim(Rec.load_mono(K_IMPACT + "impactPunch_heavy_001.ogg"), -45.0, 0.0), -5.0)
	sub = Rec.lowpass(Rec.cut(sub, 0.0, 0.22), 240.0, 2)
	var stone := Rec.pitch(Rec.trim(Rec.load_mono(K_IMPACT + "impactMining_001.ogg"), -45.0, 0.0), -6.0)
	stone = Rec.lowpass(Rec.cut(stone, 0.0, 0.20), 950.0, 2)
	var glove := Rec.pitch(Rec.trim(Rec.load_mono(K_IMPACT + "impactPunch_heavy_000.ogg"), -45.0, 0.0), -3.0)
	glove = Rec.lowpass(Rec.cut(glove, 0.0, 0.16), 1300.0, 1)
	var impact := Rec.mix(Rec.normalize(sub, -1.0), Rec.normalize(stone, -1.0), 0.0, -1.5)
	impact = Rec.mix(impact, Rec.normalize(glove, -1.0), 0.0, -2.5)
	var s := Rec.mix(Rec.normalize(rush, -4.0), Rec.normalize(impact, -1.0), 0.035, 0.0)
	return Rec.normalize(Rec.fade(s, 0.002, 0.05), -1.0)


## Default body hit (< 22 dmg): punchy medium impact.
func _hit_body_v1() -> PackedFloat32Array:
	var p := Rec.trim(Rec.load_mono(K_IMPACT + "impactPunch_medium_000.ogg"), -45.0, 0.001)
	p = Rec.lowpass(Rec.cut(p, 0.0, 0.14), 2200.0, 1)
	var soft := Rec.trim(Rec.load_mono(K_IMPACT + "impactSoft_medium_001.ogg"), -45.0, 0.0)
	soft = Rec.lowpass(Rec.cut(soft, 0.0, 0.15), 1400.0, 1)
	var s := Rec.mix(Rec.normalize(p, -1.0), Rec.normalize(soft, -1.0), 0.0, -3.0)
	return Rec.normalize(Rec.fade(s, 0.001, 0.04), -1.5)


## Heavy body hit (>= 22 dmg, wall slam, boulder hit): deep heavy punch + wood crunch.
func _hit_heavy_v1() -> PackedFloat32Array:
	var p := Rec.pitch(Rec.trim(Rec.load_mono(K_IMPACT + "impactPunch_heavy_002.ogg"), -45.0, 0.001), -2.0)
	p = Rec.lowpass(Rec.cut(p, 0.0, 0.22), 2000.0, 1)
	var w := Rec.pitch(Rec.trim(Rec.load_mono(K_IMPACT + "impactWood_heavy_001.ogg"), -45.0, 0.0), -3.0)
	w = Rec.lowpass(Rec.cut(w, 0.0, 0.18), 1200.0, 1)
	var s := Rec.mix(Rec.normalize(p, -1.0), Rec.normalize(w, -1.0), 0.0, -3.0)
	return Rec.normalize(Rec.fade(s, 0.001, 0.05), -1.0)


## Arrow / bolt thunk into target or wall.
func _hit_arrow_v1() -> PackedFloat32Array:
	var ch := Rec.trim(Rec.load_mono(K_RPG + "chop.ogg"), -45.0, 0.001)
	ch = Rec.lowpass(Rec.cut(ch, 0.0, 0.14), 2800.0, 1)
	var w := Rec.trim(Rec.load_mono(K_IMPACT + "impactWood_light_001.ogg"), -45.0, 0.0)
	w = Rec.lowpass(Rec.cut(w, 0.0, 0.10), 2200.0, 1)
	var s := Rec.mix(Rec.normalize(ch, -1.0), Rec.normalize(w, -1.0), 0.0, -3.0)
	return Rec.normalize(Rec.fade(s, 0.001, 0.035), -1.5)


## Pavise shield block: heavy wood + metal clank.
func _hit_shield_v1() -> PackedFloat32Array:
	var m := Rec.trim(Rec.load_mono(K_IMPACT + "impactMetal_heavy_001.ogg"), -45.0, 0.001)
	m = Rec.lowpass(Rec.cut(m, 0.0, 0.18), 3000.0, 1)
	var w := Rec.trim(Rec.load_mono(K_IMPACT + "impactWood_heavy_000.ogg"), -45.0, 0.0)
	w = Rec.lowpass(Rec.cut(w, 0.0, 0.18), 1600.0, 1)
	var s := Rec.mix(Rec.normalize(w, -1.0), Rec.normalize(m, -1.0), 0.0, -2.0)
	return Rec.normalize(Rec.fade(s, 0.001, 0.05), -1.5)


## Priced prop dented (non-lethal): wood/plank knock.
func _prop_dent_v1() -> PackedFloat32Array:
	var w := Rec.trim(Rec.load_mono(K_IMPACT + "impactWood_medium_001.ogg"), -45.0, 0.001)
	w = Rec.lowpass(Rec.cut(w, 0.0, 0.16), 2600.0, 1)
	var pl := Rec.trim(Rec.load_mono(K_IMPACT + "impactPlank_medium_002.ogg"), -45.0, 0.0)
	pl = Rec.lowpass(Rec.cut(pl, 0.0, 0.16), 2000.0, 1)
	var s := Rec.mix(Rec.normalize(w, -1.0), Rec.normalize(pl, -1.0), 0.01, -4.0)
	return Rec.normalize(Rec.fade(s, 0.001, 0.04), -1.5)


## Priced prop broken: staggered multi-plank crash.
func _prop_break_v1() -> PackedFloat32Array:
	var heavy := Rec.trim(Rec.load_mono(K_IMPACT + "impactWood_heavy_002.ogg"), -45.0, 0.001)
	heavy = Rec.lowpass(Rec.cut(heavy, 0.0, 0.24), 2600.0, 1)
	var p1 := Rec.pitch(Rec.trim(Rec.load_mono(K_IMPACT + "impactPlank_medium_001.ogg"), -45.0, 0.0), 2.0)
	p1 = Rec.lowpass(Rec.cut(p1, 0.0, 0.18), 2800.0, 1)
	var p2 := Rec.pitch(Rec.trim(Rec.load_mono(K_IMPACT + "impactPlank_medium_003.ogg"), -45.0, 0.0), -2.0)
	p2 = Rec.lowpass(Rec.cut(p2, 0.0, 0.20), 2400.0, 1)
	var s := Rec.mix(Rec.normalize(heavy, -1.0), Rec.normalize(p1, -1.0), 0.035, -2.5)
	s = Rec.mix(s, Rec.normalize(p2, -1.0), 0.095, -4.0)
	return Rec.normalize(Rec.fade(s, 0.001, 0.06), -1.0)


## Mail package broken: hollow cardboard/tin pop.
func _mailbox_break_v1() -> PackedFloat32Array:
	var m := Rec.trim(Rec.load_mono(K_IMPACT + "impactMetal_heavy_003.ogg"), -45.0, 0.001)
	m = Rec.lowpass(Rec.cut(m, 0.0, 0.24), 3200.0, 1)
	var pot := Rec.pitch(Rec.trim(Rec.load_mono(K_RPG + "metalPot2.ogg"), -45.0, 0.0), -2.0)
	pot = Rec.lowpass(Rec.cut(pot, 0.0, 0.22), 2800.0, 1)
	var plank := Rec.trim(Rec.load_mono(K_IMPACT + "impactPlank_medium_000.ogg"), -45.0, 0.0)
	plank = Rec.lowpass(Rec.cut(plank, 0.0, 0.18), 1800.0, 1)
	var s := Rec.mix(Rec.normalize(m, -1.0), Rec.normalize(plank, -1.0), 0.0, -3.0)
	s = Rec.mix(s, Rec.normalize(pot, -1.0), 0.055, -3.5)
	return Rec.normalize(Rec.fade(s, 0.001, 0.06), -1.0)


# ---------------------------------------------------------------- war cries and clucks (2026-10-25; audio-plan.md "War cries")
# The user's own takes (user/warcry_raw.wav, seven yells; user/chicken_raw.wav, five clucks), after the synthesized
# candidates were turned down ("I don't like the audio. I will record one."). The user picked "war_cry_6 & war_cry_7 and
# all the chicken sounds" (2026-10-25). Each is cut from WARCRY_PRE before the take to WARCRY_POST after, scaled to a
# -1 dBFS peak first (the takes are quiet) and faded over TAKE_FADE; the voices are the two yells pitched (the brute down
# with a little drive, the imp up, every other kind a touch down). Sfx plays each cue as a pool: one file at random.
const TAKE_PRE := 0.06
const TAKE_POST := 0.15
const TAKE_FADE := 0.03
## The two chosen yells in warcry_raw.wav (takes 6 and 7), seconds.
const WARCRY_TAKES: Array[Vector2] = [Vector2(10.75, 11.23), Vector2(14.08, 14.65)]
## The five clucks in chicken_raw.wav, seconds.
const CLUCK_TAKES: Array[Vector2] = [Vector2(0.40, 0.53), Vector2(0.98, 1.23), Vector2(1.83, 1.93), Vector2(3.00, 3.12),
	Vector2(3.62, 3.73)]
const BRUTE_SEMIS := -5.0
const SWARMER_SEMIS := 5.0
const MONSTER_SEMIS := -2.0


## A take: `span` of `path` padded by TAKE_PRE / TAKE_POST, normalised to -1 dBFS, then faded in and out over TAKE_FADE.
static func _user_take(path: String, span: Vector2) -> PackedFloat32Array:
	var s := Rec.cut(Rec.load_mono(path), maxf(span.x - TAKE_PRE, 0.0), span.y + TAKE_POST)
	return Rec.fade(Rec.normalize(s, -1.0), TAKE_FADE, TAKE_FADE)


## War cry take `i` (0 or 1) pitched `semis`, back at -1 dBFS.
static func _cry(i: int, semis: float = 0.0) -> PackedFloat32Array:
	var s := _user_take(USER_WARCRY, WARCRY_TAKES[i])
	return Rec.normalize(Rec.pitch(s, semis), -1.0) if semis != 0.0 else s


## The brute: the take BRUTE_SEMIS down with a touch of drive (an overdriven copy 8 dB under it; the old brute roars were
## all driven) and a little more chest.
static func _brute(i: int) -> PackedFloat32Array:
	var v := _cry(i, BRUTE_SEMIS)
	var s := Rec.mix(v, _drive(v, 2.5), 0.0, -8.0)
	s = Rec.peq(s, 160.0, 2.5, 1.0)
	return Rec.normalize(Rec.fade(s, 0.0, TAKE_FADE), -1.0)


## Overdrive: tanh at `drive` (x the level).
static func _drive(src: PackedFloat32Array, drive: float) -> PackedFloat32Array:
	var out := Rec.normalize(src, -1.0)
	for i in out.size():
		out[i] = tanh(out[i] * drive)
	return out


## Skeleton (grunt): takes 6 and 7 as recorded.
func _cry_grunt_1() -> PackedFloat32Array:
	return _cry(0)


func _cry_grunt_2() -> PackedFloat32Array:
	return _cry(1)


## Brute: BRUTE_SEMIS down, a touch of drive.
func _cry_brute_1() -> PackedFloat32Array:
	return _brute(0)


func _cry_brute_2() -> PackedFloat32Array:
	return _brute(1)


## Imp (swarmer): SWARMER_SEMIS up.
func _cry_swarmer_1() -> PackedFloat32Array:
	return _cry(0, SWARMER_SEMIS)


func _cry_swarmer_2() -> PackedFloat32Array:
	return _cry(1, SWARMER_SEMIS)


## Every other kind (archer, pavise, goo imp, Water Boy): MONSTER_SEMIS down.
func _cry_monster_1() -> PackedFloat32Array:
	return _cry(0, MONSTER_SEMIS)


func _cry_monster_2() -> PackedFloat32Array:
	return _cry(1, MONSTER_SEMIS)


## The chickens' clucks (Chicken: landing, pecks, now and then): the five takes as recorded.
func _chicken_cluck_1() -> PackedFloat32Array:
	return _user_take(USER_CHICKEN, CLUCK_TAKES[0])


func _chicken_cluck_2() -> PackedFloat32Array:
	return _user_take(USER_CHICKEN, CLUCK_TAKES[1])


func _chicken_cluck_3() -> PackedFloat32Array:
	return _user_take(USER_CHICKEN, CLUCK_TAKES[2])


func _chicken_cluck_4() -> PackedFloat32Array:
	return _user_take(USER_CHICKEN, CLUCK_TAKES[3])


func _chicken_cluck_5() -> PackedFloat32Array:
	return _user_take(USER_CHICKEN, CLUCK_TAKES[4])
