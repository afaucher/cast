extends SceneTree
## Staggered-stream latency bench (research prototype, see docs/design/stt-latency-staggered-streams.md).
##
##   Godot --path . --headless --script res://tools/stt_stagger/stagger_bench.gd -- [options]
##
## Options (all optional):
##   --streams N      recognizer streams run side by side on the same audio (0 = no recognizer,
##                    main-thread probe only). Stream k starts with an extra k * 320 / N ms of
##                    comfort noise, so its 320 ms chunk grid is shifted by that much. Default 1.
##   --phases P       base phase offsets swept per clip: 0, s, 2s ... with s = 320 / N / P ms. Default 1.
##   --groups a,b     manifest groups to play (default clean,rate).
##   --limit K        play only the first K clips (0 = all).
##   --flush MS       "flush on voice end": when the raw input has been quiet for --quiet ms after a
##                    voice run, push the gate's 80 ms delay line plus MS of comfort noise straight
##                    into the recognizer (completing the chunk now instead of waiting for real
##                    audio) and drop the same amount of later gate output while it stays quiet.
##                    0 = off (default).
##   --quiet MS       quiet time that counts as end of voice for --flush (default 100).
##   --soft-db DB     a frame within DB below the gate's voice level still counts as voice when
##                    finding the end (keeps quiet endings like "th"; default 15, 0 = gate rule).
##   --gate-flush 0|1 SpeechGate's own flush on voice end (the game's, since 2026-10-17). Default 0,
##                    so the numbers above match the pre-flush game; --flush is the bench prototype.
##   --speed X        audio seconds per wall second (default 1 = real time; the suite's tables use 4).
##   --all            also play clips whose loose expectation is "any" or "none" (chatter).
##   --verbose        print every hypothesis with its time relative to the end of voice.
##   --out PATH       CSV of per-stream and merged results (default user://stagger_<streams>.csv).
##
## Audio is fed like a mic: each 20 ms buffer is pushed when its last sample has been "spoken"
## (real time), and recognizer events are polled every ~1 ms, so latency = wall time of the cast
## minus wall time of the last voiced sample (|x| > 0.02, as tests/test_voice_audio.gd measures).
## A 60 fps game adds about one frame of poll delay on top (half a frame on average).
##
## Each stream is a full VoiceCaster (own gate, own Incantation) via BenchCaster below, so the
## per-stream results are exactly what the game path does today. Merge rule simulated in the CSV:
## first cast wins, the same spell from another stream within 1 s is a duplicate (suppressed).

const RATE := 16000
const STEP := 320                  ## 20 ms mic buffers
const LEAD := 0.5                  ## silence before each clip (pushed at once, not paced)
const TAIL := 0.9                  ## after it (paced)
const CHUNK_MS := 320.0            ## decode_chunk_len 32 feature frames x 10 ms (encoder metadata)
const FIRST_READY := 7480          ## samples before the first decode can run (T = 45 frames, see doc)
const SPELLS := ["heal", "fireball", "armor", "corn", "tentacles", "teeth"]


## VoiceCaster with sample accounting (and the optional flush-on-voice-end prototype).
class BenchCaster extends VoiceCaster:
	var stream_samples := 0        ## gate output pushed to the recognizer since the last reset
	var flush_ms := 0.0
	var quiet_ms := 100.0
	var soft_db := 15.0            ## end of voice = no frame within this many dB below the voice rule
	var flushes := 0
	var flush_wall_us := -1        ## wall time of the last flush
	var _debt := 0                 ## samples of future gate output to drop (paid back silence)
	var _loud_run := 0
	var _voiced := false
	var _quiet := 0
	var _rng := RandomNumberGenerator.new()

	func push_samples(samples: PackedFloat32Array, sample_rate: int) -> void:
		if _listener == null or samples.is_empty():
			return
		_advance(samples.size(), sample_rate)
		var speech := gate.process(samples, sample_rate)
		_note_voice_end(sample_rate)
		if flush_ms > 0.0:
			_watch_voice(samples)
			if _debt > 0 and not speech.is_empty():
				var drop := mini(_debt, speech.size())
				_debt -= drop
				speech = speech.slice(drop)
		if not speech.is_empty():
			stream_samples += speech.size()
			_listener.push_samples(speech, sample_rate)
		if flush_ms > 0.0 and _voiced and _quiet * 10.0 >= quiet_ms:
			_flush_now(sample_rate)

	## End of voice: hand the recognizer the gate's delay line (the real tail, 80 ms) right away,
	## then flush_ms of comfort noise, and owe that much: later gate output is dropped while it stays
	## quiet (the gate refills its delay line with comfort first, then passes the hangover).
	func _flush_now(sample_rate: int) -> void:
		_voiced = false
		var tail := PackedFloat32Array()
		for fr: PackedFloat32Array in gate._delay:
			tail.append_array(gate._dither(fr))
		gate._delay.clear()
		var n := int(flush_ms / 1000.0 * sample_rate)
		var pad := PackedFloat32Array()
		pad.resize(n)
		var amp := gate.comfort_rms * 1.732
		for i in n:
			pad[i] = _rng.randf_range(-amp, amp)
		tail.append_array(pad)
		stream_samples += tail.size()
		_debt += tail.size()
		flushes += 1
		flush_wall_us = Time.get_ticks_usec()
		_listener.push_samples(tail, sample_rate)

	## Voice runs use SpeechGate's "loud" rule, on the raw (undelayed) input, in 10 ms frames. The end
	## of voice uses a softer rule (soft_db lower, at least 2x the floor) so quiet word endings ("th",
	## "s") still count as voice and are not replaced by the pad.
	func _watch_voice(samples: PackedFloat32Array) -> void:
		var flen := RATE / 100
		var thr := maxf(gate.noise_floor * SpeechGate.LOUD_RATIO, pow(10.0, gate.min_voice_db / 10.0))
		var soft := maxf(gate.noise_floor * 2.0, pow(10.0, (gate.min_voice_db - soft_db) / 10.0))
		var i := 0
		while i + flen <= samples.size():
			var e := 0.0
			for k in flen:
				var s: float = samples[i + k]
				e += s * s
			if e / flen > thr:
				_loud_run += 1
				_quiet = 0
				_debt = 0          # voice is back: stop paying back, keep the inserted pause
				if _loud_run >= SpeechGate.MIN_RUN:
					_voiced = true
			else:
				_loud_run = 0
				if e / flen > soft:
					_quiet = 0
				else:
					_quiet += 1
			i += flen

	func reset() -> void:
		super.reset()
		stream_samples = 0
		_debt = 0
		_loud_run = 0
		_voiced = false
		_quiet = 0
		flush_wall_us = -1


var _n := 1
var _phases := 1
var _flush := 0.0
var _quiet := 100.0
var _verbose := false
var _gate_flush := false
var _speed := 1.0
var _casters: Array[BenchCaster] = []
var _casts: Array = []             ## per stream: Array of Dictionaries
var _hyps: Array = []              ## per stream: Array of Dictionaries
var _cross_us: Array[int] = []     ## per stream: wall time the stream last crossed a decode point
var _cross_n: Array[int] = []
var _clip_start_us := 0
var _clip_pos := 0
var _rows: PackedStringArray = PackedStringArray()
var _grid_res: Array[float] = []   ## ms from the last decode-point crossing to each hypothesis
var _probe_us: Array[float] = []   ## fixed main-thread workload timing, per step
var _io_us: Array[float] = []      ## push + poll time per step


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_n = int(_arg(args, "--streams", "1"))
	_phases = maxi(1, int(_arg(args, "--phases", "1")))
	_flush = float(_arg(args, "--flush", "0"))
	_gate_flush = _arg(args, "--gate-flush", "0") == "1"
	_speed = maxf(0.1, float(_arg(args, "--speed", "1")))
	var all := args.has("--all")
	_quiet = float(_arg(args, "--quiet", "100"))
	var soft_db := float(_arg(args, "--soft-db", "15"))
	_verbose = args.has("--verbose")
	var groups := _arg(args, "--groups", "clean,rate").split(",", false)
	var limit := int(_arg(args, "--limit", "0"))
	var out := _arg(args, "--out", "user://stagger_%d.csv" % _n)
	if not ClassDB.class_exists("WordListener"):
		print("WordListener extension missing")
		quit(1)
		return
	var dir := ProjectSettings.globalize_path("res://tests/voice_clips")
	var clips: Array = _read_manifest(dir).filter(func(c: Dictionary) -> bool: return groups.has(str(c["group"])) and (all or (str(c["loose"]) != "any" and str(c["loose"]) != "none")))
	if limit > 0:
		clips = clips.slice(0, limit)
	print("streams %d, phases %d, flush %.0f ms (quiet %.0f ms), gate flush %s, speed %.1f, %d clips" % [_n, _phases, _flush, _quiet,
		"on" if _gate_flush else "off", _speed, clips.size()])
	if _n == 0:
		_probe_only(30.0)
		quit(0)
		return

	for k in _n:
		var c := BenchCaster.new()
		c.use_mic = false
		c.use_saved_settings = false
		c.persist_settings = false
		c.voice_log.enabled = false
		c.flush_ms = _flush
		c.gate.flush_on_end = _gate_flush
		c.quiet_ms = _quiet
		c.soft_db = soft_db
		root.add_child(c)
		if not c.start(PackedStringArray(SPELLS)):
			print("caster start failed: ", c.status)
			quit(1)
			return
		_casters.append(c)
		_casts.append([])
		_hyps.append([])
		_cross_us.append(0)
		_cross_n.append(-1)
		var idx := k
		c.spell_spoken.connect(func(id: String, power: float, _h: String) -> void:
			var lc: Dictionary = c.last_cast()
			var sg: Dictionary = lc.get("signals", {})
			(_casts[idx] as Array).append({"spell": id, "power": power, "us": Time.get_ticks_usec(), "stream": c.stream_samples,
				"gap": float(lc.get("gap", 0.0)), "acc": bool(lc.get("accidental", false)), "acc_score": float(lc.get("accidental_score", 0.0)),
				"game_lat": float(lc.get("latency_ms", -1.0)), "pause": float(sg.get("pause_before", 0.0)),
				"ready_us": _cross_us[idx], "flush_us": c.flush_wall_us}))
		var l: Node = c.get_child(0)
		l.connect("hypothesis", func(text: String, fin: bool, _d: Array) -> void:
			var now := Time.get_ticks_usec()
			(_hyps[idx] as Array).append({"text": text, "final": fin, "us": now})
			if c.flush_ms <= 0.0 and _cross_us[idx] > 0:
				_grid_res.append((now - _cross_us[idx]) / 1000.0))

	_rows.append("n,flush,clip,group,expect,phase_ms,stream,offset_ms,spell,power,n_casts,lat_ms,ready_ms,compute_ms,status,final_text,gap,accidental,acc_score,game_lat,pause_before,all_casts")
	var step_ms := CHUNK_MS / _n / _phases
	var t_all := Time.get_ticks_msec()
	for c in clips:
		for p in _phases:
			_play(c, dir, p * step_ms)
	var secs := (Time.get_ticks_msec() - t_all) / 1000.0
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("\n".join(_rows) + "\n")
	f.close()
	print("wrote ", ProjectSettings.globalize_path(out))
	for k in _n:
		var st: Dictionary = _casters[k].get_stats()
		print("stream %d: audio %.1f s, busy %.2f s, rtf %.3f, max decode %.1f ms, flushes %d" % [k, float(st["audio_seconds"]),
			float(st["busy_seconds"]), float(st["rtf"]), float(st["max_chunk_ms"]), _casters[k].flushes])
	print("wall %.1f s" % secs)
	_grid_res.sort()
	if not _grid_res.is_empty():
		print("hypothesis arrival after the last decode point: p10 %.1f, p50 %.1f, p90 %.1f, max %.1f ms (n %d)" % [
			_pct(_grid_res, 0.1), _pct(_grid_res, 0.5), _pct(_grid_res, 0.9), _grid_res[_grid_res.size() - 1], _grid_res.size()])
	_print_probe()
	quit(0)


func _play(c: Dictionary, dir: String, phase_ms: float) -> void:
	var samples := _load_wav16(dir.path_join(str(c["file"])))
	var voiced_end := 0
	for i in range(samples.size() - 1, -1, -1):
		if absf(samples[i]) > 0.02:
			voiced_end = i
			break
	for k in _n:
		_casters[k].reset()
		(_casts[k] as Array).clear()
		(_hyps[k] as Array).clear()
		_cross_us[k] = 0
		_cross_n[k] = -1
	OS.delay_msec(30)
	_poll_all()
	# Instant pre-roll: phase pad + per-stream stagger + LEAD, in 20 ms pushes.
	for k in _n:
		var pre := int((phase_ms + k * CHUNK_MS / _n) / 1000.0 * RATE) + int(LEAD * RATE)
		var z := PackedFloat32Array()
		z.resize(STEP)
		var pushed := 0
		while pushed < pre:
			var m := mini(STEP, pre - pushed)
			_casters[k].push_samples(z.slice(0, m), RATE)
			pushed += m
	OS.delay_msec(150)
	_poll_all()
	for k in _n:
		(_casts[k] as Array).clear()
		(_hyps[k] as Array).clear()
		_update_cross(k, Time.get_ticks_usec())
	var stream := samples.duplicate()
	var tail := PackedFloat32Array()
	tail.resize(int(TAIL * RATE))
	stream.append_array(tail)

	_clip_start_us = Time.get_ticks_usec()
	_clip_pos = 0
	while _clip_pos < stream.size():
		var due := _clip_start_us + int(float(_clip_pos + STEP) * 1000000.0 / RATE / _speed)
		while Time.get_ticks_usec() < due:
			_poll_all()
			OS.delay_usec(1000)
		var t0 := Time.get_ticks_usec()
		var buf := stream.slice(_clip_pos, _clip_pos + STEP)
		for k in _n:
			_casters[k].push_samples(buf, RATE)
			_update_cross(k, t0)
		_clip_pos += STEP
		_poll_all()
		var t1 := Time.get_ticks_usec()
		_io_us.append(float(t1 - t0))
		_probe_us.append(_work())
	for i in 15:
		OS.delay_msec(10)
		_poll_all()
	_record(c, phase_ms, voiced_end)


## Remember when stream k's sample count crossed a decode-ready point (7480 + 5120 n samples of gate
## output since the stream was created). Each pushed buffer lands at most one crossing per stream.
func _update_cross(k: int, us: int) -> void:
	var s := _casters[k].stream_samples
	if s < FIRST_READY:
		return
	var n := (s - FIRST_READY) / int(CHUNK_MS / 1000.0 * RATE)
	if n != _cross_n[k]:
		_cross_n[k] = n
		_cross_us[k] = us


func _record(c: Dictionary, phase_ms: float, voiced_end: int) -> void:
	var expect: String = c["loose"]
	var end_us := _clip_start_us + int(float(voiced_end) * 1000000.0 / RATE)
	var first: Dictionary = {}
	var first_k := -1
	var spells_all := {}
	for k in _n:
		var casts: Array = _casts[k]
		var finals: PackedStringArray = PackedStringArray()
		for h: Dictionary in _hyps[k]:
			if bool(h["final"]):
				finals.append(str(h["text"]))
		var status := "ok"
		var spell := "-"
		var power := 0.0
		var lat := ""
		var ready := ""
		var compute := ""
		var extra := ",,,,,"
		var all_casts: PackedStringArray = PackedStringArray()
		for cc: Dictionary in casts:
			all_casts.append("%s%s %.2f" % ["~" if bool(cc["acc"]) else "", cc["spell"], float(cc["power"])])
		if _verbose:
			for h: Dictionary in _hyps[k]:
				print("    s%d %+7.1f ms %s%s" % [k, (int(h["us"]) - end_us) / 1000.0, "FINAL " if bool(h["final"]) else "", h["text"]])
		if casts.is_empty():
			status = "MISS"
		else:
			var f0: Dictionary = casts[0]
			spell = str(f0["spell"])
			power = float(f0["power"])
			var us: int = f0["us"]
			lat = "%.1f" % ((us - end_us) / 1000.0)
			var r_us: int = int(f0["flush_us"]) if int(f0["flush_us"]) > 0 and _flush > 0.0 else int(f0["ready_us"])
			ready = "%.1f" % ((r_us - end_us) / 1000.0)
			extra = "%.3f,%d,%.3f,%.1f,%.3f" % [float(f0["gap"]), int(bool(f0["acc"])), float(f0["acc_score"]), float(f0["game_lat"]), float(f0["pause"])]
			compute = "%.1f" % ((us - r_us) / 1000.0)
			if spell != expect:
				status = "WRONG"
			elif casts.size() > 1:
				status = "MULTI"
			if first.is_empty() or us < int(first["us"]):
				first = f0
				first_k = k
			for cc: Dictionary in casts:
				spells_all[str(cc["spell"])] = true
		_rows.append("%d,%.0f,%s,%s,%s,%.1f,%d,%.1f,%s,%.2f,%d,%s,%s,%s,%s,\"%s\",%s,\"%s\"" % [_n, _flush, c["file"], c["group"], expect,
			phase_ms, k, k * CHUNK_MS / _n, spell, power, casts.size(), lat, ready, compute, status, " | ".join(finals), extra, " ; ".join(all_casts)])
	# Merged: first cast wins; other streams' casts of the same spell are duplicates.
	var mstatus := "ok"
	var mlat := ""
	var mspell := "-"
	if first.is_empty():
		mstatus = "MISS"
	else:
		mspell = str(first["spell"])
		mlat = "%.1f" % ((int(first["us"]) - end_us) / 1000.0)
		if mspell != expect:
			mstatus = "WRONG"
		elif spells_all.size() > 1:
			mstatus = "CONFLICT"     # another stream cast a different spell
	_rows.append("%d,%.0f,%s,%s,%s,%.1f,%d,%.1f,%s,%.2f,%d,%s,,,%s,\"winner %d\"" % [_n, _flush, c["file"], c["group"], expect,
		phase_ms, -1, 0.0, mspell, float(first.get("power", 0.0)), spells_all.size(), mlat, mstatus, first_k])
	print("%-34s ph %5.1f  merged %-9s %8s ms  %s" % [str(c["file"]).get_basename().substr(0, 34), phase_ms, mspell, mlat, mstatus])


func _poll_all() -> void:
	for c in _casters:
		c.poll()


## A fixed slice of main-thread work (stands in for a game frame's script time).
func _work() -> float:
	var t0 := Time.get_ticks_usec()
	var a := 0.0
	for i in 20000:
		a += sin(float(i) * 0.001)
	if a == 12345.678:
		print(a)
	return float(Time.get_ticks_usec() - t0)


func _probe_only(secs: float) -> void:
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < t_end:
		OS.delay_msec(20)
		_probe_us.append(_work())
	_print_probe()


func _print_probe() -> void:
	if _probe_us.is_empty():
		return
	_probe_us.sort()
	print("main-thread probe (fixed work): p50 %.0f us, p90 %.0f us, p99 %.0f us (n %d)" % [
		_pct(_probe_us, 0.5), _pct(_probe_us, 0.9), _pct(_probe_us, 0.99), _probe_us.size()])
	if not _io_us.is_empty():
		_io_us.sort()
		print("push+poll per 20 ms buffer, all streams: p50 %.0f us, p90 %.0f us, p99 %.0f us" % [
			_pct(_io_us, 0.5), _pct(_io_us, 0.9), _pct(_io_us, 0.99)])


static func _pct(a: Array[float], q: float) -> float:
	return a[clampi(int(q * (a.size() - 1)), 0, a.size() - 1)]


static func _arg(args: PackedStringArray, key: String, def: String) -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else def


func _read_manifest(dir: String) -> Array:
	var out: Array = []
	var lines := FileAccess.get_file_as_string(dir.path_join("manifest.csv")).split("\n", false)
	for i in range(1, lines.size()):
		var f := lines[i].strip_edges().split(",", true, 8)
		if f.size() < 9:
			continue
		out.append({"file": f[0], "group": f[1], "loose": f[3], "text": f[8].trim_prefix('"').trim_suffix('"')})
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
