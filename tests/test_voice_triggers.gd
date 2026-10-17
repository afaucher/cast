extends TestCase
## Measures every VoiceCaster.TRIGGER_OPTIONS keyword with Windows-TTS clips
## through the real model: "<trigger> heal/fireball/armor/corn" must cast,
## chatter that merely mentions the trigger must not, and the default "cast"
## must stop working while another trigger is selected.
## Prints the per-option table (hit rate / average power / false fires / notes).
## Skips (passes) when the model, extension or clips are unavailable.

const RATE := 16000
const STEP := 320
const LEAD := 0.5
const TAIL := 0.8
const SPEED := 4.0
const SPELLS := ["heal", "fireball", "armor", "corn", "tentacles", "teeth"]
## Options expected to work (hit rate >= MIN_HIT_RATE, no false fires). Others
## are only reported: see VoiceCaster.TRIGGER_NOTES for why they are flagged.
const MIN_HIT_RATE := 0.8

var caster: VoiceCaster
var _casts: Array = []
var _hyps: Array = []


func _init() -> void:
	timeout_sec = 290.0


func setup() -> void:
	if not ClassDB.class_exists("WordListener"):
		print("SKIP test_voice_triggers: WordListener GDExtension not loaded")
		finish()
		return
	var cfg := HeroSpeech.config_for(str(HeroSpeech.PRESETS.keys()[0]))
	if not FileAccess.file_exists(str(cfg["encoder"])):
		print("SKIP test_voice_triggers: speech model missing under ", HeroSpeech.models_root())
		finish()
		return
	var dir := ProjectSettings.globalize_path("res://tests/voice_clips")
	if not _ensure_clips(dir):
		print("SKIP test_voice_triggers: no trigger clips and could not generate them (run tools/make_voice_clips.ps1)")
		finish()
		return
	var clips := _read_manifest(dir)
	check(clips.size() >= 40, "trigger manifest has clips (%d)" % clips.size())

	caster = VoiceCaster.new()
	caster.use_mic = false
	caster.use_saved_settings = false
	caster.persist_settings = false
	caster.voice_log.enabled = false
	add_child(caster)
	check(caster.start(PackedStringArray(SPELLS)), "caster.start")
	caster.spell_spoken.connect(func(id: String, power: float, h: String) -> void:
		_casts.append({"spell": id, "power": power, "heard": h, "accidental": caster.last_cast_accidental()}))
	caster.heard.connect(func(text: String, is_final: bool) -> void:
		if is_final:
			_hyps.append(text))

	var rows: Array = []
	for trig in VoiceCaster.TRIGGER_OPTIONS:
		caster.set_trigger_word(trig, false)
		eq(caster.get_trigger_word(), trig, "switched to " + trig)
		var pos := 0
		var hits := 0
		var power_sum := 0.0
		var false_fires := 0
		var cross_fires := 0
		var misses: Array = []
		for c in clips:
			if c["trigger"] != trig:
				continue
			var res := _play(c)
			var fired: Array = res["casts"]
			match c["kind"]:
				"pos":
					pos += 1
					if fired.size() == 1 and fired[0]["spell"] == c["spell"] and not bool(fired[0]["accidental"]):
						hits += 1
						power_sum += float(fired[0]["power"])
					else:
						misses.append("\"%s\" -> %s | heard %s" % [c["text"], _fmt(fired), " / ".join(PackedStringArray(res["hyps"]))])
				"neg":
					if not fired.is_empty():
						false_fires += 1
						misses.append("FALSE \"%s\" -> %s" % [c["text"], _fmt(fired)])
				"cross":
					if not fired.is_empty():
						cross_fires += 1
						misses.append("OLD TRIGGER STILL CASTS \"%s\" -> %s" % [c["text"], _fmt(fired)])
		rows.append({"trigger": trig, "pos": pos, "hits": hits, "avg": power_sum / maxf(float(hits), 1.0),
			"false": false_fires, "cross": cross_fires, "misses": misses})
		eq(cross_fires, 0, "old trigger 'cast' stops casting under " + trig)

	print("\n=== trigger options (TTS, David + Zira; loose mode) ===")
	print("%-12s %-10s %-9s %-12s %s" % ["trigger", "hit rate", "avg pwr", "false fires", "notes"])
	for r in rows:
		var rate: float = float(r["hits"]) / maxf(float(r["pos"]), 1.0)
		var note := str(VoiceCaster.TRIGGER_NOTES.get(r["trigger"], ""))
		print("%-12s %2d/%-2d %3d%%  %-9.2f %-12d %s" % [r["trigger"], r["hits"], r["pos"], int(rate * 100.0), r["avg"], r["false"], note])
		for m in r["misses"]:
			print("      miss: " + str(m))
		if not VoiceCaster.TRIGGER_NOTES.has(r["trigger"]):
			check(rate >= MIN_HIT_RATE, "%s hit rate %.0f%%" % [r["trigger"], rate * 100.0])
			eq(r["false"], 0, "no false fires for " + str(r["trigger"]))
	finish()


func _fmt(fired: Array) -> String:
	if fired.is_empty():
		return "-"
	var parts: Array = []
	for f in fired:
		parts.append("%s%s %.2f" % ["~" if bool(f["accidental"]) else "", f["spell"], f["power"]])
	return ", ".join(parts)


func _play(c: Dictionary) -> Dictionary:
	var dir := ProjectSettings.globalize_path("res://tests/voice_clips/triggers")
	var samples := _load_wav16(dir.path_join(c["file"]))
	if samples.is_empty():
		_fail("unreadable clip " + str(c["file"]))
		return {"casts": [], "hyps": []}
	caster.reset()
	OS.delay_msec(40)
	caster.poll()
	_casts.clear()
	_hyps.clear()
	var stream := PackedFloat32Array()
	stream.resize(int(LEAD * RATE))
	stream.append_array(samples)
	var tail := PackedFloat32Array()
	tail.resize(int(TAIL * RATE))
	stream.append_array(tail)
	var start := Time.get_ticks_usec()
	var pos := 0
	while pos < stream.size():
		caster.push_samples(stream.slice(pos, pos + STEP), RATE)
		pos += STEP
		caster.poll()
		var wait := start + int(float(pos) * 1000000.0 / RATE / SPEED) - Time.get_ticks_usec()
		if wait > 0:
			OS.delay_usec(wait)
	caster.flush()
	for i in 20:
		OS.delay_msec(20)
		caster.poll()
	return {"casts": _casts.duplicate(), "hyps": _hyps.duplicate()}


func _ensure_clips(dir: String) -> bool:
	if FileAccess.file_exists(dir.path_join("triggers.csv")):
		return true
	if OS.get_name() != "Windows":
		return false
	var script := ProjectSettings.globalize_path("res://tools/make_voice_clips.ps1")
	if not FileAccess.file_exists(script):
		return false
	print("generating voice clips with Windows TTS ...")
	var out: Array = []
	var code := OS.execute("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-OutDir", dir], out, true)
	return code == 0 and FileAccess.file_exists(dir.path_join("triggers.csv"))


func _read_manifest(dir: String) -> Array:
	var out: Array = []
	var lines := FileAccess.get_file_as_string(dir.path_join("triggers.csv")).split("\n", false)
	for i in range(1, lines.size()):
		var f := lines[i].strip_edges().split(",", true, 5)
		if f.size() < 6:
			continue
		out.append({"file": f[0], "trigger": f[1], "kind": f[2], "spell": f[3], "voice": f[4],
			"text": f[5].trim_prefix('"').trim_suffix('"')})
	return out


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
