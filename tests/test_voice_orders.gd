extends TestCase
## Voice orders end to end (docs/design/combat-proposals.md 1.0, Incantation's VOICE ORDERS): Windows-TTS clips of
## "<name> go | attack | follow" -> the real sherpa-onnx model -> VoiceCaster.order_spoken. Run in loose (the default)
## and strict:
##   pos / alias / pace  every official name with every order (both voices for the crew and the groups), the aliases, the
##                       pace extremes: the right order is heard (recall, reported; held to RECALL_MIN)
##   neg                 chatter that names a teammate or says an order word ("Rebar just goes in", "Gasket's down",
##                       "everyone's dead", "let's go"): no order, ever (a false order fails)
##   every clip          no spell is cast unless the clip says one (the Gasket / "cast" collision; test_voice_audio checks
##                       the other way: no spell clip gives an order)
##   mixed               an order and a cast in one breath: both
##
## Clips come from tools/make_voice_clips.ps1 -OrdersOnly into tests/voice_clips/orders/ (git-ignored; generated here
## when missing). Skips (passes) without the speech extension, the model or Windows TTS.
## CAST_ORDERS_HOTWORDS=1 in the environment runs it with the names and order words as hotwords too (a measurement:
## Incantation's order_hotwords is empty by default, see VOICE ORDERS).

const RATE := 16000
const STEP := 320
const LEAD := 0.5
const TAIL := 0.9
const SPEED := 4.0
const SPELLS := ["heal", "fireball", "armor", "corn", "tentacles", "teeth", "vines", "damp", "coffee", "chicken"]
## The words handed to the recognizer as hotwords in the measurement run (CAST_ORDERS_HOTWORDS=1).
const HOT := ["everyone", "crew", "pym", "hench", "rebar", "wick", "gasket", "reginald", "beatrice", "alphonse", "hodges",
	"dorothea", "gary", "steve", "todd", "kevin", "dennis", "go", "attack", "follow"]
## The share of order clips (pos, alias, pace; loose) that must be heard right.
const RECALL_MIN := 0.9

var caster: VoiceCaster
var _orders: Array = []
var _casts: Array = []
var _hyps: Array = []


func _init() -> void:
	timeout_sec = 700.0


func setup() -> void:
	if not ClassDB.class_exists("WordListener"):
		print("SKIP test_voice_orders: WordListener GDExtension not loaded (addons/hero_listen/bin)")
		finish()
		return
	var cfg := HeroSpeech.config_for(str(HeroSpeech.PRESETS.keys()[0]))
	if not FileAccess.file_exists(str(cfg["encoder"])):
		print("SKIP test_voice_orders: speech model missing under ", HeroSpeech.models_root())
		finish()
		return
	var dir := ProjectSettings.globalize_path("res://tests/voice_clips")
	if not _ensure_clips(dir):
		print("SKIP test_voice_orders: no order clips and could not generate them (run tools/make_voice_clips.ps1 -OrdersOnly)")
		finish()
		return
	var clips := _read_manifest(dir)
	check(clips.size() >= 100, "orders.csv has the clips (%d)" % clips.size())
	var hot := OS.get_environment("CAST_ORDERS_HOTWORDS") == "1"
	caster = VoiceCaster.new()
	caster.use_mic = false
	caster.use_saved_settings = false
	caster.persist_settings = false
	caster.voice_log.enabled = false
	if hot:
		caster.tuning = {"order_hotwords": HOT}
	add_child(caster)
	check(caster.start(PackedStringArray(SPELLS)), "caster.start with the real model")
	print("order hotwords: %s" % ("names + order words (measurement)" if hot else "none (the default)"))
	caster.order_spoken.connect(func(who: String, o: String, _h: String) -> void: _orders.append("%s %s" % [who, o]))
	caster.spell_spoken.connect(func(id: String, _p: float, _h: String) -> void: _casts.append(id))
	caster.heard.connect(func(text: String, is_final: bool) -> void: _hyps.append(("[%s]" if is_final else "%s") % text))
	print("\n=== loose (default) ===")
	var loose := _run_all(clips, "loose")
	print("\n=== strict ===")
	check(caster.set_strictness("strict", false), "strict")
	var strict := _run_all(clips.filter(func(c: Dictionary) -> bool: return c["kind"] in ["neg", "pos", "mixed"] and str(c["file"]).ends_with("_a0.wav")), "strict")
	caster.set_strictness("loose", false)
	print("\n=== summary (%s) ===" % ("hotwords" if hot else "no order hotwords"))
	for res: Dictionary in [loose, strict]:
		print("%-7s orders heard right %d / %d (%.0f%%): pos %s, alias %s, pace %s; false orders %d; wrong orders %d; casts on order clips %d; mixed ok %d / %d" % [
			res["mode"], res["right"], res["want"], 100.0 * res["right"] / maxf(res["want"], 1.0), _frac(res["by_kind"], "pos"),
			_frac(res["by_kind"], "alias"), _frac(res["by_kind"], "pace"), res["false"], res["wrong"], res["stray_casts"],
			res["mixed_ok"], res["mixed"]])
		check(int(res["false"]) == 0, "[%s] no chatter clip gives an order (%d did)" % [res["mode"], res["false"]])
		check(int(res["stray_casts"]) == 0, "[%s] no order clip casts a spell (%d did)" % [res["mode"], res["stray_casts"]])
	var recall := float(loose["right"]) / maxf(float(loose["want"]), 1.0)
	check(recall >= RECALL_MIN, "loose: %.0f%% of the order clips heard right (at least %.0f%%)" % [recall * 100.0, RECALL_MIN * 100.0])
	check(int(loose["wrong"]) == 0, "loose: no clip gives the wrong order (%d did)" % loose["wrong"])
	finish()


static func _frac(by_kind: Dictionary, kind: String) -> String:
	var k: Array = by_kind.get(kind, [0, 0])
	return "%d/%d" % [k[0], k[1]]


func _run_all(clips: Array, mode: String) -> Dictionary:
	var res := {"mode": mode, "want": 0, "right": 0, "false": 0, "wrong": 0, "stray_casts": 0, "mixed": 0, "mixed_ok": 0, "by_kind": {}}
	print("%-40s %-6s %-20s %-26s %-10s %s" % ["clip", "kind", "expect", "heard order", "casts", "recognizer"])
	for c: Dictionary in clips:
		var want: String = c[mode]
		var r := _play(c)
		var got: Array = r["orders"]
		var casts: Array = r["casts"]
		var status := "ok"
		if want == "none":
			if not got.is_empty():
				status = "FALSE ORDER"
				res["false"] = int(res["false"]) + 1
		elif want != "any":
			res["want"] = int(res["want"]) + 1
			var bk: Array = res["by_kind"].get(c["kind"], [0, 0])
			bk[1] += 1
			if got.has(want) and got.size() == 1:
				res["right"] = int(res["right"]) + 1
				bk[0] += 1
			elif got.is_empty():
				status = "MISS"
			else:
				status = "WRONG"
				res["wrong"] = int(res["wrong"]) + 1
			res["by_kind"][c["kind"]] = bk
		var spell: String = c["spell"]
		if spell == "none" and not casts.is_empty():
			status += " +CAST"
			res["stray_casts"] = int(res["stray_casts"]) + 1
		if c["kind"] == "mixed":
			res["mixed"] = int(res["mixed"]) + 1
			if casts.has(spell) and (want == "any" or got.has(want)):
				res["mixed_ok"] = int(res["mixed_ok"]) + 1
			else:
				status += " (mixed: %s)" % spell
		print("%-40s %-6s %-20s %-26s %-10s %s%s" % [str(c["file"]).get_basename().substr(0, 40), c["kind"], want, ", ".join(PackedStringArray(got)),
			",".join(PackedStringArray(casts)), " ".join(PackedStringArray(r["hyps"])), "" if status == "ok" else "  <-- " + status])
	return res


## Stream one clip (LEAD silence + clip + TAIL silence) at SPEED x real time.
func _play(c: Dictionary) -> Dictionary:
	var dir := ProjectSettings.globalize_path("res://tests/voice_clips/orders")
	var samples := _load_wav16(dir.path_join(c["file"]))
	if samples.is_empty():
		_fail("unreadable clip " + str(c["file"]))
		return {"orders": [], "casts": [], "hyps": []}
	caster.reset()
	OS.delay_msec(40)
	caster.poll()
	_orders.clear()
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
	return {"orders": _orders.duplicate(), "casts": _casts.duplicate(), "hyps": _hyps.duplicate()}


func _ensure_clips(dir: String) -> bool:
	if FileAccess.file_exists(dir.path_join("orders.csv")):
		return true
	if OS.get_name() != "Windows":
		return false
	var script := ProjectSettings.globalize_path("res://tools/make_voice_clips.ps1")
	if not FileAccess.file_exists(script):
		return false
	print("generating the voice-order clips with Windows TTS ...")
	var out: Array = []
	var code := OS.execute("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-OutDir", dir, "-OrdersOnly"], out, true)
	print(" ".join(PackedStringArray(out)).strip_edges())
	return code == 0 and FileAccess.file_exists(dir.path_join("orders.csv"))


func _read_manifest(dir: String) -> Array:
	var out: Array = []
	var lines := FileAccess.get_file_as_string(dir.path_join("orders.csv")).split("\n", false)
	for i in range(1, lines.size()):
		var f := lines[i].strip_edges().split(",", true, 7)
		if f.size() < 8:
			continue
		out.append({"file": f[0], "kind": f[1], "strict": f[2], "loose": f[3], "spell": f[4], "voice": f[5], "rate": int(f[6]),
			"text": f[7].trim_prefix('"').trim_suffix('"')})
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
