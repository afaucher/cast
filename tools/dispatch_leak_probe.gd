extends Node
## Mic-leak probe for the dispatch voice: the players speak spells into a mic while the headset clips may play through
## speakers. Feeds every clip (16 kHz mono 16-bit WAVs of the rendered .ogg clips) into the game's own recogniser, the way
## tests/test_voice_audio.gd feeds its clips, and reports every clip where it hears a spell, a trigger word or a fizzle.
##   Godot --path . --headless --fixed-fps 60 res://tools/dispatch_leak_probe.tscn -- <wav_dir> <lines.json> <report.json>
## <wav_dir> holds <key>.wav (tools/render_dispatch.ps1's clips converted with ffmpeg: -ar 16000 -ac 1). It is the worst
## case: the clip arrives at full level, with none of the room between speaker and mic. Needs the speech model.

const RATE := 16000
const STEP := 320              # 20 ms chunks, like the mic
const LEAD := 0.5
const TAIL := 0.8
const SPEED := 8.0
const SPELLS := ["heal", "fireball", "armor", "corn", "tentacles", "teeth", "vines", "damp", "coffee", "chicken"]
const MODES := ["loose", "chaos"]

var caster: VoiceCaster
var _casts: Array = []
var _fizzles: Array = []
var _triggers: Array = []
var _hyps: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: -- <wav_dir> <lines.json> <report.json>")
		get_tree().quit(2)
		return
	if not ClassDB.class_exists("WordListener"):
		push_error("WordListener GDExtension not loaded (addons/hero_listen/bin)")
		get_tree().quit(2)
		return
	var lines: Array = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	caster = VoiceCaster.new()
	caster.use_mic = false
	caster.use_saved_settings = false
	caster.persist_settings = false
	caster.voice_log.enabled = false
	add_child(caster)
	if not caster.start(PackedStringArray(SPELLS)):
		push_error("caster.start failed: %s" % caster.status)
		get_tree().quit(2)
		return
	caster.spell_spoken.connect(func(id: String, power: float, h: String) -> void: _casts.append({"spell": id, "power": snappedf(power, 0.01), "heard": h}))
	caster.spell_fizzled.connect(func(h: String, reason: String) -> void: _fizzles.append({"heard": h, "reason": reason}))
	caster.trigger_heard.connect(func(w: String) -> void: _triggers.append(w))
	caster.heard.connect(func(text: String, is_final: bool) -> void:
		if is_final:
			_hyps.append(text))
	var report := []
	for mode: String in MODES:
		caster.set_strictness(mode, false)
		for l: Dictionary in lines:
			var res := _play(args[0].path_join(str(l["key"]) + ".wav"))
			res["mode"] = mode
			res["key"] = l["key"]
			res["kind"] = l["kind"]
			res["text"] = l["text"]
			res["spoken"] = l["spoken"]
			report.append(res)
		print("mode %s done" % mode)
	var f := FileAccess.open(args[2], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	get_tree().quit(0)


func _play(path: String) -> Dictionary:
	var samples := _load_wav16(path)
	if samples.is_empty():
		return {"error": "unreadable " + path}
	caster.reset()
	OS.delay_msec(40)
	caster.poll()
	_casts.clear()
	_fizzles.clear()
	_triggers.clear()
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
	return {"casts": _casts.duplicate(), "fizzles": _fizzles.duplicate(), "triggers": _triggers.duplicate(), "hyps": _hyps.duplicate()}


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
