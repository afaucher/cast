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
## Sound hooks (docs/design/audio-plan.md): trigger_heard (the "cast heard" cue), speech_started and is_speaking() (the
## fizzle is cut by new speech).
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
## signals, gap, cast_q, spell_q, penalty, latency_ms (-1 when typed), speech_ms (-1 when typed), typed.
## latency_ms is audio time from the true end of the voice (SpeechGate.voice_end_sample, raw input)
## to the cast; ~150 ms with the gate's flush on voice end (see SpeechGate). speech_ms is from the
## utterance's voice ONSET (the first voice span after the previous utterance's end,
## SpeechGate.voice_start_sample) to the cast: speaking time plus recognition (online telemetry, M7).
signal cast_detail(info: Dictionary)
## A cast swallowed by the repeat lockout (same spell within ~1 s).
signal ignored(spell_id: String, heard_text: String, reason: String)
## Fires after each final utterance (and each typed line) once its events are
## known. outcome: {kind: "cast"|"fizzle"|"none", casts: [], fizzles: [], ignored: []}.
signal utterance_finished(text: String, outcome: Dictionary, typed: bool)
signal trigger_word_changed(word: String)
## The trigger word was heard and a cast is armed, waiting for its spell word (Incantation.trigger_armed): once per
## trigger, typed lines included. `word` is the token as heard ("CAST", "CASTS").
signal trigger_heard(word: String)
## An armed trigger was let go with no fizzle (Incantation.trigger_dropped: a "cast" buried in chatter, its window run out):
## the cast tell fades (CastTell).
signal trigger_dropped(word: String)
## New speech began: the gate's voice onset on the raw input (SpeechGate.voice_start_sample, ~50 ms into the voice,
## before the recognizer hears it), or with the gate off the recognizer's own voice tracker. Sounds that must not play
## over the player's next words stop here.
signal speech_started
signal strictness_changed(mode: String)
## A voice order (Incantation's VOICE ORDERS): `who` is the name key ("rebar", "everyone", "hench four"), `order` one of
## "go", "attack", "follow". Typed lines too. last_order() has the detail (gap, at_start, accidental, typed).
signal order_spoken(who: String, order: String, heard: String)

## The spells listened for when start() gets none: every castable spell (SpellBook is the one list).
static func default_spells() -> PackedStringArray:
	return PackedStringArray(SpellBook.ids())

## Keyword choices for the UI. Each was measured with TTS clips through the real
## model (tests/test_voice_triggers.gd prints the table). TRIGGER_NOTES flags
## options that misbehave; they stay selectable but the UI warns.
const TRIGGER_OPTIONS := ["cast", "magic", "pickle", "conjure", "invoke", "summon", "presto", "abracadabra"]
## Triggers that measured poorly with the speech model (shown by the UI).
const TRIGGER_NOTES := {
	"abracadabra": "the speech model mangles it (heard as ABERC AT AVERAGE, ABREK HAD EVER ...); 0 of 6 TTS casts worked",
}
const STRICTNESS_OPTIONS := ["strict", "loose", "chaos"]
## Mic watchdog. No input frames for STALL_SEC (the device went to sleep, was unplugged or grabbed by
## another app), or the gate hearing the same audio again (SpeechGate.is_stale), restarts the input
## device, at most every RESTART_EVERY seconds.
const STALL_SEC := 1.0
const RESTART_EVERY := 2.0

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
## A final this soon after a short spell-less final is matched joined to it.
const JOIN_GAP := 0.45
const JOIN_MAX_WORDS := 2
## Keeps room noise and keyboard clicks away from the recognizer (see SpeechGate).
var gate := SpeechGate.new()

var _inc: Incantation
var _spells := PackedStringArray()
var _listener: Object = null     # WordListener (kept untyped: the class may not exist)
var _mic_ok := false
## Times the watchdog restarted the input device (debug panel, voice log).
var mic_restarts := 0
var _last_frames_ms := 0
var _last_restart_ms := -100000
static var _mic_owner: Object = null   ## the caster that turned the input device on
var _voice_active := false
var _applied_saved := false

# Clock handed to Incantation: seconds of audio pushed so far (plus idle time
# before any audio flows), so timing is independent of frame rate and of how
# fast a test feeds a WAV.
var _clock_t := 0.0
var _audio_driven := false
var _last_voice_clock := -1e9   ## clock() at the true end of the latest voice (SpeechGate.voice_end_sample)
var _seen_voice_start := -1
var _span_starts: Array[float] = []   ## clock() at the start of recent voice spans (SpeechGate.voice_start_sample)
var _prev_voice_end := -1e9     ## clock() at the end of the voice the previous utterance (or cast) was made of
var _seen_voice_end := -1
var _utt_events: Array = []
var _last_text := ""
var _utt_start := -1.0            ## clock of the current utterance's first hypothesis
var _frag_text := ""              ## last final if it cast nothing and was short (may be half a word)
var _frag_end := -1e9
var _last_cast: Dictionary = {}
var _last_order: Dictionary = {}
var _typed := false
var last_heard_typed := false


func _ready() -> void:
	set_process(true)


## Open the model (and the mic unless use_mic is false). Returns true when
## listening works. Always prepares the typed path (inject_text) first.
func start(spell_ids: PackedStringArray) -> bool:
	_spells = spell_ids if not spell_ids.is_empty() else default_spells()
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
	return gate.level


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


## Voice orders: the floor's own employees' names (one word each: "beatrice", "bloom"), so they answer to them too.
## Rebuilds the grammar like a trigger change (no model reload).
func set_order_names(names: Array[String]) -> void:
	var list: Array = []
	for n in names:
		if n != "" and not list.has(n):
			list.append(n)
	if list == (tuning.get("order_names_extra", []) as Array):
		return
	tuning["order_names_extra"] = list
	_rebuild()


## Quietest level (dBFS) that counts as the player's voice; raise it to ignore
## background speech from a TV or speakers.
func set_min_voice_db(value: float, persist: bool = true) -> void:
	gate.min_voice_db = clampf(value, -70.0, -10.0)
	if persist and persist_settings:
		VoiceSettings.save_settings({"min_voice_db": gate.min_voice_db}, settings_path)


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


## The most recent voice order's event (who, order, heard, gap, at_start, accidental, typed).
func last_order() -> Dictionary:
	return _last_order


# --- audio plumbing ------------------------------------------------------------

## Test hook: feed mono float samples (-1..1) as if they came from the mic.
func push_samples(samples: PackedFloat32Array, sample_rate: int) -> void:
	if _listener == null or samples.is_empty():
		return
	_advance(samples.size(), sample_rate)
	var speech := gate.process(samples, sample_rate)
	_note_voice_end(sample_rate)
	if not speech.is_empty():
		_listener.push_samples(speech, sample_rate)


## End of input (tests): flush pending speech through the recognizer.
func flush() -> void:
	if _listener != null:
		_listener.flush()


## Drop queued audio and the half-heard utterance; forget a pending trigger.
func reset() -> void:
	gate.reset()
	if _listener != null:
		_listener.reset()
	_ensure_incantation()
	_inc.reset()
	_utt_events.clear()
	_last_text = ""
	_frag_text = ""
	_utt_start = -1.0


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



## The player is speaking right now (the gate's raw voice span, no hangover; with the gate off, the recognizer's tracker).
func is_speaking() -> bool:
	return gate.in_voice() if gate.enabled else _voice_active


func get_stats() -> Dictionary:
	return _listener.get_stats() if _listener != null else {}


func get_incantation() -> Incantation:
	_ensure_incantation()
	return _inc


func stop() -> void:
	if _mic_ok and _mic_owner == self:
		AudioServer.set_input_device_active(false)
		_mic_owner = null
	if _listener != null:
		(_listener as Node).queue_free()
		_listener = null
	_mic_ok = false
	status = "stopped"


func _process(delta: float) -> void:
	var fed := false
	if _mic_ok and _listener != null:
		fed = _pump_mic()
	if not _audio_driven or (_mic_ok and not fed and Time.get_ticks_msec() - _last_frames_ms > 200):
		_clock_t += delta         # no audio flowing: keep time moving so pending triggers expire
	_ensure_incantation()
	_dispatch(_inc.tick(clock()), false)
	_update_voice_activity()


func _advance(frames: int, rate: int) -> void:
	_audio_driven = true
	_clock_t += float(frames) / float(maxi(rate, 1))


func _spell_list() -> Array:
	return Array(_spells) if not _spells.is_empty() else Array(default_spells())


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
	gate.min_voice_db = float(s["min_voice_db"])


func _ensure_incantation() -> void:
	if _inc == null:
		if _spells.is_empty():
			_spells = default_spells()
		_apply_saved_settings()
		_rebuild()


func _rebuild() -> void:
	_inc = Incantation.new(_spells if not _spells.is_empty() else default_spells(), tuning)
	_inc.trigger_armed.connect(func(token: String) -> void: trigger_heard.emit(token))
	_inc.trigger_dropped.connect(func(token: String) -> void: trigger_dropped.emit(token))
	_utt_events.clear()
	_last_text = ""
	if _listener != null:
		_listener.set_words(_inc.vocabulary())


func _on_hypothesis(text: String, is_final: bool, _detail: Array) -> void:
	_ensure_incantation()
	_typed = false
	last_heard_typed = false
	if _utt_start < 0.0:
		_utt_start = clock()
	if text != _last_text or is_final:
		heard.emit(text, is_final)
	_last_text = "" if is_final else text
	var feed_text := text
	if is_final and _frag_text != "" and _utt_start - _frag_end <= JOIN_GAP and not _starts_with_known_word(text):
		# The recognizer sometimes ends an utterance mid-word ("COR" + "N",
		# "CA" + "STE HEAL"). Rejoin a short, spell-less fragment with what follows.
		feed_text = _frag_text + text
	_dispatch(_inc.feed(feed_text, is_final, clock()), true)
	if is_final:
		var cast_now := false
		for ev in _utt_events:
			if ev["kind"] == "cast" or ev["kind"] == "order":
				cast_now = true
		var words := feed_text.split(" ", false).size()
		_frag_text = feed_text if not cast_now and words <= JOIN_MAX_WORDS else ""
		_frag_end = clock()
		_utt_start = -1.0
		_finish_utterance(feed_text)


## True when the utterance already begins with the trigger or a spell word, so
## it is a fresh phrase rather than the tail of a split word.
func _starts_with_known_word(text: String) -> bool:
	var first := text.strip_edges().get_slice(" ", 0).to_lower()
	if first == "":
		return false
	var cfg := _inc.config()
	var trig: Dictionary = (cfg["triggers"] as Dictionary).get(_inc.trigger_word(), {})
	if trig.has(first) or first == _inc.trigger_word() or _inc.is_order_word(first):
		return true
	for id in (cfg["spells"] as Dictionary):
		if (cfg["spells"][id] as Dictionary).has(first):
			return true
	return false


## in_utterance: events belong to the utterance being heard (logged with it);
## otherwise they are a timeout fizzle and are logged on their own.
func _dispatch(events: Array, in_utterance: bool) -> void:
	for ev in events:
		var kind: String = ev["kind"]
		if kind == "cast":
			var info: Dictionary = ev.duplicate(true)
			info["typed"] = _typed
			info["latency_ms"] = -1.0 if _typed else maxf(0.0, (clock() - _last_voice_clock) * 1000.0)
			var onset := -1.0 if _typed else _utterance_onset()
			info["speech_ms"] = -1.0 if onset < 0.0 else maxf(0.0, (clock() - onset) * 1000.0)
			if not _typed:
				_prev_voice_end = _last_voice_clock
			_last_cast = info
			spell_spoken.emit(str(info["spell"]), float(info["power"]), str(info["heard"]))
			cast_detail.emit(info)
			ev = info
		elif kind == "order":
			var od: Dictionary = ev.duplicate(true)
			od["typed"] = _typed
			_last_order = od
			order_spoken.emit(str(od["who"]), str(od["order"]), str(od["heard"]))
			ev = od
		elif kind == "fizzle":
			spell_fizzled.emit(str(ev["heard"]), str(ev["reason"]))
		elif kind == "ignored":
			ignored.emit(str(ev["spell"]), str(ev["heard"]), str(ev["reason"]))
		if in_utterance:
			_utt_events.append(ev)
		else:
			_log_rows(str(ev.get("heard", "")), [ev], false)


func _finish_utterance(text: String) -> void:
	var outcome := {"kind": "none", "casts": [], "fizzles": [], "ignored": [], "orders": []}
	for ev in _utt_events:
		match ev["kind"]:
			"cast":
				outcome["casts"].append(ev)
			"fizzle":
				outcome["fizzles"].append(ev)
			"ignored":
				outcome["ignored"].append(ev)
			"order":
				outcome["orders"].append(ev)
	if not outcome["casts"].is_empty():
		outcome["kind"] = "cast"
	elif not outcome["fizzles"].is_empty():
		outcome["kind"] = "fizzle"
	elif not outcome["orders"].is_empty():
		outcome["kind"] = "order"
	_log_rows(text, _utt_events, _typed)
	_utt_events = []
	if not _typed:
		_prev_voice_end = maxf(_prev_voice_end, _last_voice_clock)
	utterance_finished.emit(text, outcome, _typed)


## The voice onset of the utterance being cast: the first voice span that began after the previous utterance's voice
## ended (-1 when none is known: no gate, or a typed line).
func _utterance_onset() -> float:
	for t in _span_starts:
		if t >= _prev_voice_end - 0.001:
			return t
	return -1.0


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
			"order":
				row["spell"] = "%s %s" % [ev["who"], ev["order"]]
				row["label"] = "order:accidental" if bool(ev.get("accidental", false)) else "order"
				row["signals"] = "first=%d;gap=%.2f" % [int(bool(ev.get("at_start", false))), float(ev.get("gap", 0.0))]
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


## latency_ms is measured from the TRUE end of voice: the gate's raw (undelayed) last voiced frame,
## mapped onto the audio clock. (It used to be the last frame WordListener.is_hearing_voice() was true,
## which runs ~230 ms late: the gate's 80 ms delay plus its 150 ms hold.)
func _note_voice_end(rate: int) -> void:
	if gate.voice_start_sample >= 0 and gate.voice_start_sample != _seen_voice_start:
		_seen_voice_start = gate.voice_start_sample
		_span_starts.append(_clock_t - float(gate.samples_in - gate.voice_start_sample) / float(maxi(rate, 1)))
		if _span_starts.size() > 16:
			_span_starts.pop_front()
		speech_started.emit()
	if gate.voice_end_sample < 0 or gate.voice_end_sample == _seen_voice_end:
		return
	_seen_voice_end = gate.voice_end_sample
	_last_voice_clock = _clock_t - float(gate.samples_in - gate.voice_end_sample) / float(maxi(rate, 1))


func _update_voice_activity() -> void:
	if _listener == null:
		return
	var active: bool = _listener.is_hearing_voice()
	if active and not gate.enabled:
		if not _voice_active:
			_span_starts.append(clock())   # (no gate: the recognizer's own voice tracker marks the onset)
			if _span_starts.size() > 16:
				_span_starts.pop_front()
			speech_started.emit()
		_last_voice_clock = clock()   # no gate: fall back to the recognizer's own voice tracker
	if active != _voice_active:
		_voice_active = active
		voice_activity.emit(active)


## The mic is read straight from the input device (AudioServer.get_input_frames). NOT through
## AudioStreamMicrophone: when the device stops delivering, that stream keeps replaying its 4 s
## ring buffer forever, at full volume, and the recognizer hears the same old words on a loop
## (playtest 2026-10-17: "BRIGHT OVATER" every 8 s, "OH NO" every 4 s; reproduced with
## tools/mic_probe). The direct path just goes quiet, which the watchdog notices.
func _setup_mic() -> bool:
	if AudioServer.get_input_device_list().is_empty():
		return false
	if AudioServer.set_input_device_active(true) != OK:
		return false
	_mic_owner = self
	_last_frames_ms = Time.get_ticks_msec()
	gate.repeat_guard = true
	return true


## Moves waiting mic frames through the gate into the recognizer. Returns true if any came.
func _pump_mic() -> bool:
	var now := Time.get_ticks_msec()
	var n := AudioServer.get_input_frames_available()
	var fed := n > 0
	if fed:
		var rate := int(AudioServer.get_input_mix_rate())
		_advance(n, rate)
		var speech := gate.process_frames(AudioServer.get_input_frames(n), rate)
		_note_voice_end(rate)
		if not speech.is_empty():
			_listener.push_samples(speech, rate)
		_last_frames_ms = now
	var reason := ""
	if now - _last_frames_ms > int(STALL_SEC * 1000.0):
		reason = "stopped sending audio"
	elif gate.is_stale:
		reason = "repeating old audio"
	if reason != "" and now - _last_restart_ms > int(RESTART_EVERY * 1000.0):
		_restart_mic(reason, now)
	elif reason == "" and fed and status.begins_with("mic "):
		status = "listening"
	return fed


func _restart_mic(reason: String, now: int) -> void:
	mic_restarts += 1
	_last_restart_ms = now
	_last_frames_ms = now
	# Reassigning the device reopens it; the toggle restarts capture.
	AudioServer.input_device = AudioServer.input_device
	AudioServer.set_input_device_active(false)
	AudioServer.set_input_device_active(true)
	_mic_owner = self
	reset()                       # drop anything half-heard from the bad audio
	status = "mic %s; restarted it (%d)" % [reason, mic_restarts]
	push_warning("VoiceCaster: " + status)
