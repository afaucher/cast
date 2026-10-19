extends TestCase
## End to end: Windows-TTS WAV clips -> real sherpa-onnx model -> VoiceCaster.
## Clean casts must fire at high power; chatter behaves as each strictness
## mode says (strict: never; loose: only corn mentions and trigger-anywhere
## casts; chaos: any spell word).
##
## Clips come from tools/make_voice_clips.ps1 into tests/voice_clips/ (git-ignored).
## If they are missing the test generates them; if it cannot (no PowerShell/TTS)
## or the speech model/extension is missing, it SKIPS with a message and passes.
##
## Audio is fed faster than real time (SPEED x) but timing inside VoiceCaster is
## audio-clock based, so the result does not depend on frame rate.

const RATE := 16000
const STEP := 320              # 20 ms chunks, like the mic
const LEAD := 0.5              # seconds of silence before each clip
const TAIL := 0.8              # and after
const SPEED := 4.0             # audio seconds per wall second
const SPELLS := ["heal", "fireball", "armor", "corn", "tentacles", "teeth", "vines", "damp", "coffee", "chicken"]
const DELIBERATE_GROUPS := ["clean", "rate", "sloppy", "hesitate"]
## Stress clips (fastest TTS rate, long hesitations) sit on the recognizer's edge:
## shifting the audio by 80 ms flips some of them (measured). Their MISSES use a
## per-mode budget (a weak cast counts too: a fumble is meant to cost power);
## wrong spells, false fires and clean misses always fail.
const STRESS_GROUPS := ["rate", "hesitate"]
const STRESS_MISS_BUDGET := 4   # was 2 for six spells; the nine-spell vocabulary adds three more words at the pace extremes
## Clips whose recognizer text is printed in full (the measurement tables for the
## tentacles and teeth spell words and their chatter sound-alikes, and the hero names, which must never cast).
const MEASURE_WORDS := ["gasket", "rebar", "wick", "tentacle", "attack", "ten tickets", "testicles", "tackle", "teeth", "tooth", "these", "tea", "tease", "teach",
	"vine", "wines", "vibes", "fines", "binds", "damp", "damn", "dump", "camp", "coffee", "copy", "cough",
	"chicken", "kitchen", "chick", "check in", "thicken"]
## The spells whose confusion with every other spell is checked, and the text stems
## of their clips ("tentacle" covers tentacles/tentacle, "teeth"/"tooth" the teeth forms).
const FOCUS_STEMS := {"tentacles": ["tentacle"], "teeth": ["teeth", "tooth"], "vines": ["vine"], "damp": ["damp"], "coffee": ["coffee"], "chicken": ["chicken"]}
## Chatter the recognizer writes as a spell word (measured): "binds" comes out as VINES in both voices (and "fines" now and
## then), and Zira's "check in" as CHICKEN, so a cast on it is a true hearing, not a confusion between spells.
const HEARD_AS_SPELL := ["binds", "fines", "check in"]

var caster: VoiceCaster
var _casts: Array = []         # {spell, power, heard, accidental, t}
var _fizzles: Array = []
var _hyps: Array = []
var _voiced_end := 0.0
var _matrix := {}              # clip file -> {mode: text}
var _bad := 0
var _confusions: Array = []    # "file [mode]: clip says X, fired Y" (see _confusion_of)
var _focus_clips := {}         # spell -> deliberate clips about it seen (loose) ...
var _focus_fired := {}         # ... and how many of them fired that spell


func _init() -> void:
	timeout_sec = 600.0   # nine spells: about 40% more clips than with six


func setup() -> void:
	if not ClassDB.class_exists("WordListener"):
		print("SKIP test_voice_audio: WordListener GDExtension not loaded (addons/hero_listen/bin)")
		finish()
		return
	var cfg := HeroSpeech.config_for(str(HeroSpeech.PRESETS.keys()[0]))
	if not FileAccess.file_exists(str(cfg["encoder"])):
		print("SKIP test_voice_audio: speech model missing under ", HeroSpeech.models_root())
		finish()
		return
	var dir := ProjectSettings.globalize_path("res://tests/voice_clips")
	if not _ensure_clips(dir):
		print("SKIP test_voice_audio: no voice clips and could not generate them (run tools/make_voice_clips.ps1)")
		finish()
		return
	var manifest := _read_manifest(dir)
	check(manifest.size() >= 20, "manifest has clips (%d)" % manifest.size())

	caster = VoiceCaster.new()
	caster.use_mic = false
	caster.use_saved_settings = false
	caster.persist_settings = false
	caster.voice_log.enabled = false
	add_child(caster)
	var t0 := Time.get_ticks_msec()
	check(caster.start(PackedStringArray(SPELLS)), "caster.start with the real model")
	print("model loaded in %d ms; status: %s" % [Time.get_ticks_msec() - t0, caster.status])
	check(caster.is_ready(), "is_ready (no mic needed)")
	caster.spell_spoken.connect(func(id: String, power: float, h: String) -> void:
		_casts.append({"spell": id, "power": power, "heard": h, "accidental": caster.last_cast_accidental(), "t": caster.clock(),
			"latency_ms": float(caster.last_cast().get("latency_ms", -1.0))}))
	caster.spell_fizzled.connect(func(h: String, reason: String) -> void:
		_fizzles.append({"heard": h, "reason": reason}))
	caster.heard.connect(func(text: String, is_final: bool) -> void:
		_hyps.append(("[%s]" if is_final else "%s") % text))

	var chatter := manifest.filter(func(c: Dictionary) -> bool: return c["group"] in ["bare", "negative"] and str(c["file"]).ends_with("_a0.wav"))
	print("\n=== loose (default): all clips ===")
	_run_all(manifest, "loose")
	print("\n=== strict: bare + chatter ===")
	_set_mode("strict")
	_run_all(chatter, "strict")
	print("\n=== chaos: bare + chatter + late spell word ===")
	_set_mode("chaos")
	_run_all(chatter + manifest.filter(func(c: Dictionary) -> bool: return str(c["file"]).begins_with("hesitate_cast_b3000")), "chaos")
	_set_mode("loose")
	_print_matrix(manifest)
	_print_confusion()
	_realtime_latency(manifest)
	print("\n%s" % ("all clips behaved" if _bad == 0 else "%d clip(s) misbehaved" % _bad))
	finish()


func _set_mode(mode: String) -> void:
	check(caster.set_strictness(mode, false), "set_strictness " + mode)


## Runs `clips` in the current mode and checks the manifest's expectation for it.
func _run_all(clips: Array, mode: String) -> void:
	print("%-44s %-8s %-9s %-22s %-8s %s" % ["clip", "group", "expect", "fired", "latency", ""])
	var false_fires := 0
	var stress_misses := 0
	var clean_min := 9.0
	for c in clips:
		var expect: String = c[mode]
		var res := _play(c)
		var fired: Array = res["casts"]
		var status := "ok"
		var want_power: float = c["min_power"]
		if expect == "none":
			if not fired.is_empty():
				status = "FALSE FIRE"
				false_fires += 1
		elif expect == "any":
			if fired.size() > 1:
				status = "MULTI"
		else:
			if fired.size() != 1:
				status = "MISS" if fired.is_empty() else "MULTI"
			elif fired[0]["spell"] != expect:
				status = "WRONG"
			elif fired[0]["power"] < want_power:
				status = "WEAK"
			elif bool(fired[0]["accidental"]) != not (c["group"] in DELIBERATE_GROUPS):
				status = "LABEL"
			if c["group"] == "clean" and fired.size() == 1:
				clean_min = minf(clean_min, fired[0]["power"])
		_note_confusion(c, fired, mode)
		if (status == "MISS" or status == "WEAK") and c["group"] in STRESS_GROUPS:
			stress_misses += 1
			status = "%s (stress, budget %d)" % [status, STRESS_MISS_BUDGET]
			print("  soft miss: %s [%s] heard: %s" % [c["file"], mode, " ".join(PackedStringArray(res["hyps"]))])
		elif status != "ok":
			_bad += 1
			_fail("%s [%s] expected %s, got %s -- %s | heard: %s" % [c["file"], mode, expect, _fmt(fired), status, " ".join(PackedStringArray(res["hyps"]))])
		var fz := ""
		if not res["fizzles"].is_empty():
			fz = "fizzle:" + str(res["fizzles"][0]["reason"])
		for w in MEASURE_WORDS:
			if str(c["text"]).to_lower().contains(w):
				print("    measured [%s] %s: heard %s" % [mode, c["file"], " ".join(PackedStringArray(res["hyps"]))])
				break
		var key: String = c["file"]
		if not _matrix.has(key):
			_matrix[key] = {}
		_matrix[key][mode] = (_fmt(fired) if not fired.is_empty() else "-") + (" " + fz if fz != "" else "")
		print("%-44s %-8s %-9s %-22s %-8s %s%s" % [str(c["file"]).get_basename().substr(0, 44), c["group"], expect,
			_fmt(fired), res["latency"], fz, "" if status == "ok" else "  <-- " + status])
	print("false fires: %d; stress misses: %d; lowest clean-cast power: %s" % [false_fires, stress_misses, "%.2f" % clean_min if clean_min < 9.0 else "n/a"])
	check(stress_misses <= STRESS_MISS_BUDGET, "[%s] stress-clip misses %d within budget %d" % [mode, stress_misses, STRESS_MISS_BUDGET])


## Spell confusion: "cast tentacles" / "cast teeth" / vines / damp / coffee (and their sloppy forms) must never fire
## another spell, and no other clip may fire them. Checked on every clip in every mode, including
## the ones whose expectation is only "any".
func _note_confusion(c: Dictionary, fired: Array, mode: String) -> void:
	var text := str(c["text"]).to_lower()
	for w: String in HEARD_AS_SPELL:
		if text.contains(w):
			return
	# Chatter that merely mentions it ("watch out for the tentacles") is judged by its own expectation.
	var deliberate: bool = c["group"] in DELIBERATE_GROUPS
	for sp: String in FOCUS_STEMS:
		var about := false
		for stem: String in FOCUS_STEMS[sp]:
			about = about or text.contains(stem)
		if deliberate and about:
			if mode == "loose":
				_focus_clips[sp] = int(_focus_clips.get(sp, 0)) + 1
			for f in fired:
				if f["spell"] == sp:
					if mode == "loose":
						_focus_fired[sp] = int(_focus_fired.get(sp, 0)) + 1
				else:
					_confusions.append("%s [%s]: \"%s\" fired %s" % [c["file"], mode, c["text"], f["spell"]])
		elif not about:
			for f in fired:
				if f["spell"] == sp:
					_confusions.append("%s [%s]: \"%s\" fired %s" % [c["file"], mode, c["text"], sp])


func _print_confusion() -> void:
	print("
=== spell confusion (the focus spells vs the rest) ===")
	for sp: String in FOCUS_STEMS:
		print("deliberate %s clips (loose): %d, fired %s: %d" % [sp, int(_focus_clips.get(sp, 0)), sp, int(_focus_fired.get(sp, 0))])
	print("confusions: %d" % _confusions.size())
	for line in _confusions:
		_fail("spell confusion: " + str(line))


func _print_matrix(manifest: Array) -> void:
	print("\n=== chatter under each strictness (voice a) ===")
	print("%-34s %-14s %-24s %-24s" % ["clip", "strict", "loose", "chaos"])
	for c in manifest:
		if not (c["group"] in ["bare", "negative"]) or not str(c["file"]).ends_with("_a0.wav"):
			continue
		var m: Dictionary = _matrix.get(c["file"], {})
		print("%-34s %-14s %-24s %-24s" % [("\"%s\"" % c["text"]).substr(0, 34), str(m.get("strict", "?")).substr(0, 14),
			str(m.get("loose", "?")).substr(0, 24), str(m.get("chaos", "?")).substr(0, 24)])


## A few clean casts at true real time (SPEED 1) for an honest latency number:
## accelerated feeding inflates it because the recognizer thread lags the audio.
## Two measures per clip: "wave" is from the clip's last sample above |0.02| (independent of the
## game), "game" is the cast's own latency_ms (the voice log and debug panel figure, measured from
## SpeechGate's end of voice). Both must agree, and the median must stay under MAX_P50_MS: with
## SpeechGate's flush on voice end it is ~150-200 ms (it was ~800 ms before, see
## docs/design/stt-latency-staggered-streams.md).
const MAX_P50_MS := 300.0
const MAX_METRIC_DIFF_MS := 80.0


func _realtime_latency(manifest: Array) -> void:
	print("\n=== latency at real-time pacing (ms after the voice stops) ===")
	print("%-44s %-18s %8s %8s" % ["clip", "fired", "wave", "game"])
	var lats: Array[float] = []
	var game: Array[float] = []
	for c in manifest:
		if c["group"] != "clean":
			continue
		var res := _play(c, 1.0)
		var fired: Array = res["casts"]
		var g := "-"
		if fired.size() == 1 and fired[0]["spell"] == c["loose"]:
			lats.append((float(fired[0]["t"]) - _voiced_end) * 1000.0)
			game.append(float(fired[0]["latency_ms"]))
			g = "%+.0fms" % float(fired[0]["latency_ms"])
		else:
			_fail("real-time clip %s did not cast" % c["file"])
		print("%-44s %-18s %8s %8s" % [str(c["file"]).get_basename(), _fmt(fired), res["latency"], g])
	if not lats.is_empty():
		lats.sort()
		game.sort()
		var p50 := lats[lats.size() / 2]
		var g50 := game[game.size() / 2]
		print("median latency %.0f ms (p90 %.0f ms); game metric median %.0f ms; flushes %d" % [
			p50, lats[mini(lats.size() - 1, int(lats.size() * 0.9))], g50, caster.gate.flushes])
		check(p50 < MAX_P50_MS, "median end-of-voice -> cast latency %.0f ms under %.0f ms" % [p50, MAX_P50_MS])
		check(absf(g50 - p50) < MAX_METRIC_DIFF_MS, "game latency metric (%.0f ms) matches the waveform measure (%.0f ms)" % [g50, p50])


func _fmt(fired: Array) -> String:
	if fired.is_empty():
		return "-"
	var parts: Array = []
	for f in fired:
		parts.append("%s%s %.2f" % ["~" if bool(f["accidental"]) else "", f["spell"], f["power"]])
	return ", ".join(parts)


## Stream one clip (LEAD silence + clip + TAIL silence) at `speed` x real time.
func _play(c: Dictionary, speed: float = SPEED) -> Dictionary:
	var dir := ProjectSettings.globalize_path("res://tests/voice_clips")
	var samples := _load_wav16(dir.path_join(c["file"]))
	if samples.is_empty():
		_fail("unreadable clip " + str(c["file"]))
		return {"casts": [], "fizzles": [], "hyps": [], "latency": "-"}
	caster.reset()
	OS.delay_msec(40)
	caster.poll()
	_casts.clear()
	_fizzles.clear()
	_hyps.clear()
	var stream := PackedFloat32Array()
	stream.resize(int(LEAD * RATE))
	stream.append_array(samples)
	var tail := PackedFloat32Array()
	tail.resize(int(TAIL * RATE))
	stream.append_array(tail)
	var clip_start_clock := caster.clock() + LEAD
	var last_loud := 0
	for i in range(samples.size() - 1, -1, -1):
		if absf(samples[i]) > 0.02:
			last_loud = i
			break
	_voiced_end = clip_start_clock + float(last_loud) / RATE
	var start := Time.get_ticks_usec()
	var pos := 0
	while pos < stream.size():
		caster.push_samples(stream.slice(pos, pos + STEP), RATE)
		pos += STEP
		caster.poll()
		var wait := start + int(float(pos) * 1000000.0 / RATE / speed) - Time.get_ticks_usec()
		if wait > 0:
			OS.delay_usec(wait)
	caster.flush()
	for i in 20:
		OS.delay_msec(20)
		caster.poll()
	var lat := "-"
	if not _casts.is_empty():
		lat = "%+.0fms" % ((float(_casts[0]["t"]) - _voiced_end) * 1000.0)
	return {"casts": _casts.duplicate(), "fizzles": _fizzles.duplicate(), "hyps": _hyps.duplicate(), "latency": lat}


# --- clips -----------------------------------------------------------------

func _ensure_clips(dir: String) -> bool:
	if FileAccess.file_exists(dir.path_join("manifest.csv")) and FileAccess.file_exists(dir.path_join("triggers.csv")):
		# Clips made before a spell was added have no "cast <spell>" clip for it: make them again (the clips are generated).
		var text := FileAccess.get_file_as_string(dir.path_join("manifest.csv"))
		if SPELLS.all(func(id: String) -> bool: return text.contains("\"cast %s\"" % id)):
			return true
		print("the voice clips predate a spell in SPELLS: generating them again")
	if OS.get_name() != "Windows":
		return false
	var script := ProjectSettings.globalize_path("res://tools/make_voice_clips.ps1")
	if not FileAccess.file_exists(script):
		return false
	print("generating voice clips with Windows TTS ...")
	var out: Array = []
	var code := OS.execute("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-OutDir", dir], out, true)
	print(" ".join(PackedStringArray(out)).strip_edges())
	return code == 0 and FileAccess.file_exists(dir.path_join("manifest.csv"))


func _read_manifest(dir: String) -> Array:
	var out: Array = []
	var lines := FileAccess.get_file_as_string(dir.path_join("manifest.csv")).split("\n", false)
	for i in range(1, lines.size()):
		var f := lines[i].strip_edges().split(",", true, 8)
		if f.size() < 9:
			continue
		out.append({"file": f[0], "group": f[1], "strict": f[2], "loose": f[3], "chaos": f[4],
			"min_power": float(f[5]), "voice": f[6], "rate": int(f[7]), "text": f[8].trim_prefix('"').trim_suffix('"')})
	return out


## Minimal 16-bit PCM mono WAV reader.
static func _load_wav16(path: String) -> PackedFloat32Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedFloat32Array()
	f.seek(12)
	var out := PackedFloat32Array()
	while f.get_position() + 8 <= f.get_length():
		var id := f.get_buffer(4).get_string_from_ascii()
		var size := f.get_32()
		if id == "data":
			var pcm := f.get_buffer(size)
			out.resize(size / 2)
			for i in out.size():
				out[i] = pcm.decode_s16(i * 2) / 32768.0
			break
		f.seek(f.get_position() + size + (size & 1))
	return out
