class_name VoiceCaster
extends Node
## Voice -> game bridge: spoken incantations become spell_spoken signals.
##
## Wraps the WordListener GDExtension (sherpa-onnx streaming zipformer, copied
## from Hero-Reader into addons/hero_listen) as a plain speech recognizer and
## hands its hypotheses to Incantation (scripts/voice/incantation.gd), which owns
## the grammar, trigger word, strictness and power scoring. See that file.
##
## Contract (docs/ARCHITECTURE.md): spell_spoken / spell_fizzled / voice_activity,
## start(spell_ids) -> bool, is_ready(), get_level(), inject_text(text).
## Added: heard (raw recognizer text, for subtitles), cast_detail (everything
## about a cast incl. `accidental`), set_trigger_word(), set_strictness(),
## last_cast_accidental(), push_samples()/flush()/poll() for tests.
## If the extension or the model is missing, start() returns false and
## inject_text() keeps working, so the game stays playable from the keyboard.
##
## `accidental` is a heuristic label for callouts and stats only; it changes no
## power or cooldown. Every finished utterance is also appended to
## user://voice_log.csv (VoiceLog), passively.

signal spell_spoken(spell_id: String, power: float, heard: String)
signal spell_fizzled(heard: String, reason: String)
signal voice_activity(active: bool)
## The recognizer's current text, verbatim (partials and finals), including
## everything that matched nothing. Typed text (inject_text) arrives as a final.
signal heard(text: String, final: bool)
## One per cast. Keys: spell, power, heard, accidental, accidental_score, why,
## signals, gap, cast_q, spell_q, penalty, latency_ms (-1 when typed), typed.
signal cast_detail(info: Dictionary)
## A cast swallowed by the repeat lockout (same spell within ~1 s).
signal ignored(spell_id: String, heard_text: String, reason: String)
## Fires after each final utterance (and each typed line) once its events are
## known. outcome: {kind: "cast"|"fizzle"|"none", casts: [], fizzles: [], ignored: []}.
signal utterance_finished(text: String, outcome: Dictionary, typed: bool)
signal trigger_word_changed(word: String)
signal strictness_changed(mode: String)

const DEFAULT_SPELLS := ["heal", "fireball", "armor", "corn"]
## Keyword choices for the UI. Each was measured with TTS clips through the real
## model (tests/test_voice_triggers.gd prints the table). TRIGGER_NOTES flags
## options that misbehave; they stay selectable but the UI warns.
const TRIGGER_OPTIONS := ["cast", "magic", "pickle", "conjure", "invoke", "summon", "presto", "abracadabra"]
## Triggers that measured poorly with the speech model (shown by the UI).
const TRIGGER_NOTES := {
	"abracadabra": "the speech model mangles it (heard as ABERC AT AVERAGE, ABREK HAD EVER ...); 0 of 6 TTS casts worked",
}
const STRICTNESS_OPTIONS := ["strict", "loose", "chaos"]
const MIC_BUS := "VoiceMic"

## Open the microphone in start(). Tests set this to false and use push_samples().
var use_mic := true
## HeroSpeech preset name; "" = the first (default) preset.
var preset := ""
## Incantation tuning overrides (e.g. {"fizzle_below": 0.3}); set before start().
## "trigger" / "strictness" here win over the saved settings.
var tuning: Dictionary = {}
## Apply user://settings.cfg (VoiceSettings) in start(). Tests turn this off.
var use_saved_settings := true
var settings_path := VoiceSettings.DEFAULT_PATH
## Persist set_trigger_word / set_strictness calls (they take a per-call flag too).
var persist_settings := true
## Passive CSV log of every utterance. Tests turn this off.
var voice_log: VoiceLog = VoiceLog.new()
## Human-readable state for the UI ("listening", "speech model missing ...").
var status := "not started"

var _inc: Incantation
var _spells := PackedStringArray()
var _listener: Object = null     # WordListener (kept untyped: the class may not exist)
var _capture: AudioEffectCapture = null
var _mic_player: AudioStreamPlayer = null
var _mic_ok := false
var _voice_active := false
var _applied_saved := false

# Clock handed to Incantation: seconds of audio pushed so far (plus idle time
# before any audio flows), so timing is independent of frame rate and of how
# fast a test feeds a WAV.
var _clock_t := 0.0
var _audio_driven := false
var _last_voice_clock := -1e9
var _utt_events: Array = []
var _last_text := ""
var _last_cast: Dictionary = {}
var _typed := false
var last_heard_typed := false


func _ready() -> void:
	set_process(true)


## Open the model (and the mic unless use_mic is false). Returns true when
## listening works. Always prepares the typed path (inject_text) first.
func start(spell_ids: PackedStringArray) -> bool:
	_spells = spell_ids if not spell_ids.is_empty() else PackedStringArray(DEFAULT_SPELLS)
	_apply_saved_settings()
	_rebuild()
	if _listener != null:
		return is_ready()
	if not ClassDB.class_exists("WordListener"):
		status = "speech extension not loaded (addons/hero_listen/bin); type to cast"
		push_warning("VoiceCaster: " + status)
		return false
	var p := preset if preset != "" else str(HeroSpeech.PRESETS.keys()[0])
	if not HeroSpeech.PRESETS.has(p):
		status = "unknown speech preset '%s'" % p
		push_warning("VoiceCaster: " + status)
		return false
	var cfg := HeroSpeech.config_for(p)
	if not FileAccess.file_exists(str(cfg.get("encoder", ""))):
		status = "no model (%s); typed input only" % HeroSpeech.models_root()
		push_warning("VoiceCaster: " + status)
		return false
	var l: Object = ClassDB.instantiate("WordListener")
	if l == null:
		status = "could not create WordListener"
		return false
	add_child(l as Node)
	if not l.load_model(cfg):
		(l as Node).queue_free()
		status = "speech model failed to load; typed input only"
		push_warning("VoiceCaster: " + status)
		return false
	_listener = l
	_listener.connect("hypothesis", _on_hypothesis)
	_listener.set_words(_inc.vocabulary())
	if use_mic:
		_mic_ok = _setup_mic()
		if not _mic_ok:
			status = "no microphone found; typed input only"
			return false
	status = "listening" if use_mic else "model ready (no mic)"
	return true


func is_ready() -> bool:
	return _listener != null and (_mic_ok or not use_mic)


## 0..1 loudness of the microphone, for a meter.
func get_level() -> float:
	if _listener == null:
		return 0.0
	return float(_listener.get_level())


## Debug / tests / typed console: act as if `text` had been heard as a complete
## utterance. Needs the same grammar as speech ("cast heal").
func inject_text(text: String) -> void:
	_ensure_incantation()
	_typed = true
	last_heard_typed = true
	heard.emit(text, true)
	_dispatch(_inc.feed(text, true, clock()), true)
	_finish_utterance(text)
	_typed = false


# --- trigger word and strictness ----------------------------------------------

func get_trigger_word() -> String:
	return str(tuning.get("trigger", "cast"))


## Switch the keyword. Rebuilds the vocabulary/hotwords without reloading the
## model and resets the incantation state. Returns VoiceSettings.validate_trigger()
## (ok=false means nothing changed); check "warnings" for the custom-word advice.
func set_trigger_word(word: String, persist: bool = true) -> Dictionary:
	var v := VoiceSettings.validate_trigger(word, _spell_list())
	if not bool(v["ok"]):
		return v
	var w: String = v["word"]
	var changed := w != get_trigger_word()
	tuning["trigger"] = w
	_rebuild()
	if persist and persist_settings:
		VoiceSettings.save_settings({"trigger_word": w}, settings_path)
	if changed:
		trigger_word_changed.emit(w)
	return v


func get_strictness() -> String:
	return str(tuning.get("strictness", "loose"))


func set_strictness(mode: String, persist: bool = true) -> bool:
	if not STRICTNESS_OPTIONS.has(mode):
		return false
	var changed := mode != get_strictness()
	tuning["strictness"] = mode
	_rebuild()
	if persist and persist_settings:
		VoiceSettings.save_settings({"strictness": mode}, settings_path)
	if changed:
		strictness_changed.emit(mode)
	return true


## Was the most recent spell_spoken cast classed accidental? (Valid inside the
## spell_spoken handler and after it.)
func last_cast_accidental() -> bool:
	return bool(_last_cast.get("accidental", false))


func last_cast() -> Dictionary:
	return _last_cast


# --- audio plumbing ------------------------------------------------------------

## Test hook: feed mono float samples (-1..1) as if they came from the mic.
func push_samples(samples: PackedFloat32Array, sample_rate: int) -> void:
	if _listener == null or samples.is_empty():
		return
	_advance(samples.size(), sample_rate)
	_listener.push_samples(samples, sample_rate)


## End of input (tests): flush pending speech through the recognizer.
func flush() -> void:
	if _listener != null:
		_listener.flush()


## Drop queued audio and the half-heard utterance; forget a pending trigger.
func reset() -> void:
	if _listener != null:
		_listener.reset()
	_ensure_incantation()
	_inc.reset()
	_utt_events.clear()
	_last_text = ""


## Deliver recognizer events now (normally automatic from _process). Tests that
## block the main thread while feeding audio call this between chunks.
func poll() -> void:
	if _listener != null:
		_listener.poll()
	_ensure_incantation()
	_dispatch(_inc.tick(clock()), false)
	_update_voice_activity()


## Audio-time clock used for all gap / lockout timing (seconds).
func clock() -> float:
	return _clock_t


func is_voice_active() -> bool:
	return _voice_active


func get_stats() -> Dictionary:
	return _listener.get_stats() if _listener != null else {}


func get_incantation() -> Incantation:
	_ensure_incantation()
	return _inc


func stop() -> void:
	if _mic_player != null:
		_mic_player.stop()
		_mic_player.queue_free()
		_mic_player = null
	if _listener != null:
		(_listener as Node).queue_free()
		_listener = null
	_mic_ok = false
	status = "stopped"


func _process(delta: float) -> void:
	if not _audio_driven:
		_clock_t += delta
	if _capture != null and _listener != null:
		var n := _capture.get_frames_available()
		if n > 0:
			var rate := int(AudioServer.get_mix_rate())
			_advance(n, rate)
			_listener.push_frames(_capture.get_buffer(n), rate)
	_ensure_incantation()
	_dispatch(_inc.tick(clock()), false)
	_update_voice_activity()


func _advance(frames: int, rate: int) -> void:
	_audio_driven = true
	_clock_t += float(frames) / float(maxi(rate, 1))


func _spell_list() -> Array:
	return Array(_spells) if not _spells.is_empty() else DEFAULT_SPELLS


func _apply_saved_settings() -> void:
	if _applied_saved or not use_saved_settings:
		return
	_applied_saved = true
	var s := VoiceSettings.load_settings(settings_path)
	if not tuning.has("trigger"):
		var v := VoiceSettings.validate_trigger(str(s["trigger_word"]), _spell_list())
		tuning["trigger"] = v["word"] if bool(v["ok"]) else "cast"
	if not tuning.has("strictness"):
		tuning["strictness"] = s["strictness"]


func _ensure_incantation() -> void:
	if _inc == null:
		if _spells.is_empty():
			_spells = PackedStringArray(DEFAULT_SPELLS)
		_apply_saved_settings()
		_rebuild()


func _rebuild() -> void:
	_inc = Incantation.new(_spells if not _spells.is_empty() else PackedStringArray(DEFAULT_SPELLS), tuning)
	_utt_events.clear()
	_last_text = ""
	if _listener != null:
		_listener.set_words(_inc.vocabulary())


func _on_hypothesis(text: String, is_final: bool, _detail: Array) -> void:
	_ensure_incantation()
	_typed = false
	last_heard_typed = false
	if text != _last_text or is_final:
		heard.emit(text, is_final)
	_last_text = "" if is_final else text
	_dispatch(_inc.feed(text, is_final, clock()), true)
	if is_final:
		_finish_utterance(text)


## in_utterance: events belong to the utterance being heard (logged with it);
## otherwise they are a timeout fizzle and are logged on their own.
func _dispatch(events: Array, in_utterance: bool) -> void:
	for ev in events:
		var kind: String = ev["kind"]
		if kind == "cast":
			var info: Dictionary = ev.duplicate(true)
			info["typed"] = _typed
			info["latency_ms"] = -1.0 if _typed else maxf(0.0, (clock() - _last_voice_clock) * 1000.0)
			_last_cast = info
			spell_spoken.emit(str(info["spell"]), float(info["power"]), str(info["heard"]))
			cast_detail.emit(info)
			ev = info
		elif kind == "fizzle":
			spell_fizzled.emit(str(ev["heard"]), str(ev["reason"]))
		elif kind == "ignored":
			ignored.emit(str(ev["spell"]), str(ev["heard"]), str(ev["reason"]))
		if in_utterance:
			_utt_events.append(ev)
		else:
			_log_rows(str(ev.get("heard", "")), [ev], false)


func _finish_utterance(text: String) -> void:
	var outcome := {"kind": "none", "casts": [], "fizzles": [], "ignored": []}
	for ev in _utt_events:
		match ev["kind"]:
			"cast":
				outcome["casts"].append(ev)
			"fizzle":
				outcome["fizzles"].append(ev)
			"ignored":
				outcome["ignored"].append(ev)
	if not outcome["casts"].is_empty():
		outcome["kind"] = "cast"
	elif not outcome["fizzles"].is_empty():
		outcome["kind"] = "fizzle"
	_log_rows(text, _utt_events, _typed)
	_utt_events = []
	utterance_finished.emit(text, outcome, _typed)


func _log_rows(text: String, events: Array, typed: bool) -> void:
	var base := {
		"clock": "%.2f" % clock(), "source": "typed" if typed else "voice", "final": "1",
		"heard": text, "mode": get_strictness(), "trigger": get_trigger_word(),
	}
	if events.is_empty():
		var row := base.duplicate()
		row["label"] = "none"
		voice_log.add(row)
		return
	for ev in events:
		var row := base.duplicate()
		match ev["kind"]:
			"cast":
				row["spell"] = ev["spell"]
				row["power"] = "%.3f" % float(ev["power"])
				row["label"] = "accidental" if bool(ev["accidental"]) else "deliberate"
				row["signals"] = _signals_text(ev)
			"fizzle":
				row["label"] = "fizzle:" + str(ev["reason"])
				row["spell"] = ev.get("spell", "")
			"ignored":
				row["label"] = "ignored:" + str(ev["reason"])
				row["spell"] = ev["spell"]
		voice_log.add(row)


static func _signals_text(ev: Dictionary) -> String:
	var s: Dictionary = ev.get("signals", {})
	return "trigger=%d;first=%d;pause=%.2f;kind=%s;words=%d;score=%.2f;gap=%.2f;pen=%.2f;lat=%d" % [
		int(bool(s.get("trigger_present", false))), int(bool(s.get("trigger_first", false))),
		float(s.get("pause_before", 0.0)), str(s.get("kind", "")), int(s.get("words", 0)),
		float(ev.get("accidental_score", 0.0)), float(ev.get("gap", 0.0)), float(ev.get("penalty", 0.0)),
		int(float(ev.get("latency_ms", -1.0)))]


func _update_voice_activity() -> void:
	if _listener == null:
		return
	var active: bool = _listener.is_hearing_voice()
	if active:
		_last_voice_clock = clock()
	if active != _voice_active:
		_voice_active = active
		voice_activity.emit(active)


func _setup_mic() -> bool:
	if AudioServer.get_input_device_list().is_empty():
		return false
	# Mic -> muted bus with a capture effect: raw samples, no playback.
	var bus := AudioServer.get_bus_index(MIC_BUS)
	if bus < 0:
		bus = AudioServer.bus_count
		AudioServer.add_bus(bus)
		AudioServer.set_bus_name(bus, MIC_BUS)
		AudioServer.set_bus_mute(bus, true)
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 0.5
		AudioServer.add_bus_effect(bus, cap)
	_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	if _capture == null:
		return false
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = MIC_BUS
	add_child(_mic_player)
	_mic_player.play()
	return true
