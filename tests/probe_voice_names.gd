extends TestCase
## PROBE (not part of -TestAll: it is not test_*): screens a proposed set of employee names against the recognizer, through
## the voice-order grammar (Incantation's VOICE ORDERS), against today's floor names (SiteBuilder) as the baseline.
##   .\test_runner.ps1 -TestName probe_voice_names -TimeoutSec 6000
## Clips: tools/make_voice_clips.ps1 -NamesProbe -> tests/voice_clips/names/ + names.csv (Windows TTS, David + Zira).
## Per name: "<name> go | attack | follow" in both voices (and "Mister <name> ..." for a formal name), "<name> go" at the pace
## extremes; loose and strict: was that order heard? Chatter (the bare name, "<name> is down there", "where's <name>", and the
## four dispatch rescue lines) in both voices, loose and chaos: any order, cast, armed trigger or fizzle is reported.
## Every name in the probe is an order name at once (so a name heard as another one shows as a WRONG order). PROBE_ALIASES
## are the measured spellings each new name needs (the way DENIS / TOD were added for the order names); they live here only.

const RATE := 16000
const STEP := 320
const LEAD := 0.5
const TAIL := 0.9
const SPEED := 4.0
var SPELLS: Array = SpellBook.ids()   # (the game's castable spells: SpellBook is the one list)
## Name key -> {heard phrase: quality}: the measured spellings, from the first pass's misses (2026-10-19). Used only with
## CAST_PROBE_ALIASES=1 (pass 2), so pass 1 (raw) stays reproducible.
const PROBE_ALIASES := {
	# proposed staff
	"penny": {"henny": 0.9}, "bloom": {"blue": 0.8}, "iris": {"iras": 0.9}, "nadia": {"nydia": 0.9, "naudia": 0.9},
	"lionel": {"lion'll": 0.9, "lion all": 0.9, "lion ll": 0.9, "lion or": 0.8}, "sully": {"solly": 0.9, "solely": 0.8},
	"stan": {"stand": 0.8}, "ozzie": {"ozie": 0.9, "oz": 0.8},
	# proposed henchmen
	"barry": {"berry": 0.9}, "lenny": {"liney": 0.9, "line": 0.8}, "mick": {"mic": 0.9, "mc": 0.9, "miko": 0.8},
	"mo": {"m o": 0.8}, "lou": {"lew": 0.9, "lu": 0.9}, "sid": {"cid": 0.9, "cit": 0.8},
	# spares
	"otto": {"auto": 0.9}, "norma": {"norman": 0.8}, "zelda": {"zelder": 0.9, "zelde": 0.9, "zeldo": 0.9}, "bev": {"verb": 0.8},
	# today's floor names (the baseline gets the same treatment)
	"brad": {"bread": 0.9}, "craig": {"creek": 0.8, "cre": 0.8}, "dwayne": {"dwain": 0.9, "duen": 0.8, "duan": 0.8, "dween": 0.8},
	"gordon": {"gording": 0.9}, "colin": {"callin": 0.9, "calling": 0.8, "call an": 0.8}, "dev": {"deb": 0.8, "der": 0.8},
	"imogen": {"image and": 0.8}, "priya": {"pre": 0.8, "preo": 0.8, "pria": 0.9}, "tessa": {"tess": 0.9},
	"walt": {"wald": 0.9, "walde": 0.9, "walled": 0.8}, "okafor": {"occover": 0.8, "archafer": 0.8, "octafer": 0.8, "occopher": 0.8,
		"ocapher": 0.8, "mister octafer": 0.8, "mister occopher": 0.8, "mister ocapher": 0.8},
}
## Pass 2: the order words' measured forms (only as the last word: Incantation's rule for a heard-as form) and the fused
## endings of a name run into "go".
const PROBE_ORDER_WORDS := {
	"go": {"go": 1.0, "goe": 0.9, "goat": 0.9, "girl": 0.9, "got": 0.9},
	"attack": {"attack": 1.0},
	"follow": {"follow": 1.0, "followed": 0.9, "fallow": 0.9},
}
const PROBE_FUSED_GO := ["go", "ko", "co", "ow", "o", "got", "goe", "ga", "gio", "giot"]
## Formal names: their spoken title forms.
const FORMAL := {"bloom": ["mister bloom", "mr bloom"], "okafor": ["mister okafor", "mr okafor"]}

var caster: VoiceCaster
var _orders: Array = []
var _casts: Array = []
var _fizzles: Array = []
var _triggers := 0
var _hyps: Array = []


func _init() -> void:
	timeout_sec = 6000.0


func setup() -> void:
	if not ClassDB.class_exists("WordListener"):
		print("SKIP probe_voice_names: no WordListener")
		finish()
		return
	var dir := ProjectSettings.globalize_path("res://tests/voice_clips")
	var clips := _read_manifest(dir)
	if not check(not clips.is_empty(), "names.csv (run tools/make_voice_clips.ps1 -NamesProbe)"):
		finish()
		return
	var pass2 := OS.get_environment("CAST_PROBE_ALIASES") == "1"
	print("probe pass: %s" % ("2 (measured aliases)" if pass2 else "1 (raw names)"))
	var names: Dictionary = (Incantation.TUNING["order_names"] as Dictionary).duplicate(true)
	for c: Dictionary in clips:
		var key: String = c["key"]
		if key in ["hench", "hench four"]:
			continue
		if not names.has(key):
			names[key] = {key: 1.0}
		for ph in FORMAL.get(key, []):
			names[key][ph] = 1.0
		if pass2:
			for ph in PROBE_ALIASES.get(key, {}):
				names[key][ph] = float(PROBE_ALIASES[key][ph])
	caster = VoiceCaster.new()
	caster.use_mic = false
	caster.use_saved_settings = false
	caster.persist_settings = false
	caster.voice_log.enabled = false
	caster.tuning = {"order_names": names}
	if pass2:
		caster.tuning["order_words"] = PROBE_ORDER_WORDS
		caster.tuning["order_fused_go"] = PROBE_FUSED_GO
	add_child(caster)
	check(caster.start(PackedStringArray(SPELLS)), "caster.start with the real model")
	caster.order_spoken.connect(func(who: String, o: String, _h: String) -> void: _orders.append("%s %s" % [who, o]))
	caster.spell_spoken.connect(func(id: String, _p: float, _h: String) -> void: _casts.append(id))
	caster.spell_fizzled.connect(func(_h: String, reason: String) -> void: _fizzles.append(reason))
	caster.trigger_heard.connect(func(_w: String) -> void: _triggers += 1)
	caster.heard.connect(func(text: String, is_final: bool) -> void:
		if is_final:
			_hyps.append(text))
	var stats := {}   # key -> counters
	var sets := {}    # key -> set label
	var heard_misses := {}   # key -> [heard texts of missed order clips]
	var commands := clips.filter(func(c: Dictionary) -> bool: return c["kind"] != "chatter")
	var chatter := clips.filter(func(c: Dictionary) -> bool: return c["kind"] == "chatter")
	for mode: String in ["loose", "strict"]:
		caster.set_strictness(mode, false)
		print("\n=== orders, %s ===" % mode)
		for c: Dictionary in commands:
			var key: String = c["key"]
			sets[key] = c["set"]
			var st: Dictionary = stats.get(key, _blank())
			var r := _play(c)
			var want := "%s %s" % [key, c["order"]]
			st[mode + "_n"] = int(st[mode + "_n"]) + 1
			var ok: bool = r["orders"].size() == 1 and r["orders"][0] == want
			if ok:
				st[mode + "_hit"] = int(st[mode + "_hit"]) + 1
			elif not r["orders"].is_empty():
				st["wrong"] = int(st["wrong"]) + 1
			if not r["casts"].is_empty():
				st["cmd_casts"] = int(st["cmd_casts"]) + 1
			stats[key] = st
			if not ok:
				var miss: Array = heard_misses.get(key, [])
				miss.append("%s [%s] -> %s | %s" % [c["text"], mode, ",".join(PackedStringArray(r["orders"])), " / ".join(PackedStringArray(r["hyps"]))])
				heard_misses[key] = miss
			print("%-34s %-6s %-22s %-26s %s" % [str(c["file"]).get_basename().substr(0, 34), mode, want, ",".join(PackedStringArray(r["orders"])),
				" / ".join(PackedStringArray(r["hyps"]))])
	for mode: String in ["loose", "chaos"]:
		caster.set_strictness(mode, false)
		print("\n=== chatter, %s ===" % mode)
		for c: Dictionary in chatter:
			var key: String = c["key"]
			var st: Dictionary = stats.get(key, _blank())
			var r := _play(c)
			var bad := ""
			if not r["orders"].is_empty():
				st[mode + "_false"] = int(st[mode + "_false"]) + 1
				bad += " ORDER " + ",".join(PackedStringArray(r["orders"]))
			if not r["casts"].is_empty():
				st[mode + "_casts"] = int(st[mode + "_casts"]) + 1
				bad += " CAST " + ",".join(PackedStringArray(r["casts"]))
			if int(r["triggers"]) > 0:
				st[mode + "_trig"] = int(st[mode + "_trig"]) + 1
				bad += " TRIGGER"
			if not r["fizzles"].is_empty():
				st[mode + "_fizz"] = int(st[mode + "_fizz"]) + 1
				bad += " FIZZLE " + ",".join(PackedStringArray(r["fizzles"]))
			stats[key] = st
			print("%-44s %-6s %-30s %s" % [str(c["file"]).get_basename().substr(0, 44), mode, bad, " / ".join(PackedStringArray(r["hyps"]))])
	print("\n=== NAME TABLE ===")
	print("%-11s %-17s %-8s %-8s %-6s %-14s %-14s %-12s %-10s" % ["name", "set", "loose", "strict", "wrong", "false L/C", "casts L/C", "trig L/C", "fizz L/C"])
	var keys := stats.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return str(sets.get(a, "")) + a < str(sets.get(b, "")) + b)
	for key: String in keys:
		var st: Dictionary = stats[key]
		print("%-11s %-17s %-8s %-8s %-6d %-14s %-14s %-12s %-10s" % [key, sets.get(key, ""), "%d/%d" % [st["loose_hit"], st["loose_n"]],
			"%d/%d" % [st["strict_hit"], st["strict_n"]], st["wrong"], "%d/%d" % [st["loose_false"], st["chaos_false"]],
			"%d/%d" % [st["loose_casts"], st["chaos_casts"]], "%d/%d" % [st["loose_trig"], st["chaos_trig"]],
			"%d/%d" % [st["loose_fizz"], st["chaos_fizz"]]])
	print("\n=== MISSES (heard as) ===")
	for key: String in keys:
		for line in heard_misses.get(key, []):
			print("%-11s %s" % [key, line])
	finish()


static func _blank() -> Dictionary:
	return {"loose_n": 0, "loose_hit": 0, "strict_n": 0, "strict_hit": 0, "wrong": 0, "cmd_casts": 0,
		"loose_false": 0, "chaos_false": 0, "loose_casts": 0, "chaos_casts": 0, "loose_trig": 0, "chaos_trig": 0,
		"loose_fizz": 0, "chaos_fizz": 0}


func _play(c: Dictionary) -> Dictionary:
	var samples := _load_wav16(ProjectSettings.globalize_path("res://tests/voice_clips/names").path_join(c["file"]))
	caster.reset()
	OS.delay_msec(40)
	caster.poll()
	_orders.clear()
	_casts.clear()
	_fizzles.clear()
	_hyps.clear()
	_triggers = 0
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
	return {"orders": _orders.duplicate(), "casts": _casts.duplicate(), "fizzles": _fizzles.duplicate(), "triggers": _triggers,
		"hyps": _hyps.duplicate()}


func _read_manifest(dir: String) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(dir.path_join("names.csv")):
		return out
	var lines := FileAccess.get_file_as_string(dir.path_join("names.csv")).split("\n", false)
	for i in range(1, lines.size()):
		var f := lines[i].strip_edges().split(",", true, 7)
		if f.size() < 8:
			continue
		out.append({"file": f[0], "set": f[1], "key": f[2], "kind": f[3], "order": f[4], "voice": f[5], "rate": int(f[6]),
			"text": f[7].trim_prefix('"').trim_suffix('"')})
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
