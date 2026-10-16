extends TestCase
## Pure logic: feed recognizer hypotheses to Incantation, check power/fizzle,
## strictness modes, trigger words, the accidental label, settings and the
## VoiceCaster typed path. No audio and no model needed.

const SPELLS := ["heal", "fireball", "armor", "corn"]
const TMP_SETTINGS := "user://test_voice_settings.cfg"
const TMP_LOG := "user://test_voice_log.csv"


func _inc(overrides: Dictionary = {}) -> Incantation:
	return Incantation.new(PackedStringArray(SPELLS), overrides)


## Run a script of [t, text, final] steps; return all events.
func _run(inc: Incantation, steps: Array, end_t: float = -1.0) -> Array:
	var out: Array = []
	for s in steps:
		out.append_array(inc.feed(s[1], s[2], s[0]))
	if end_t >= 0.0:
		out.append_array(inc.tick(end_t))
	return out


func _casts(evs: Array) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return e["kind"] == "cast")


func _fizzles(evs: Array) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return e["kind"] == "fizzle")


## One typed utterance through a fresh Incantation: the cast events.
func _say(text: String, overrides: Dictionary = {}) -> Array:
	return _casts(_run(_inc(overrides), [[1.0, text, true]]))


func setup() -> void:
	_test_vocabulary()
	_test_clean_streaming()
	_test_homophone_and_compound()
	_test_dedupe()
	_test_negatives()
	_test_split_utterances()
	_test_power_scoring()
	_test_fizzles()
	_test_strictness()
	_test_accidental_label()
	_test_triggers()
	_test_explain()
	_test_misc()
	_test_settings()
	_test_caster_typed()
	finish()


func _test_vocabulary() -> void:
	var v := _inc().vocabulary()
	check(v.has("cast"), "vocab has cast")
	for s in SPELLS:
		check(v.has(s), "vocab has " + s)
	check(_inc({"trigger": "pickle"}).vocabulary().has("pickle"), "vocab follows the trigger")
	check(not _inc({"trigger": "pickle"}).vocabulary().has("cast"), "old trigger leaves the vocab")


func _test_clean_streaming() -> void:
	# Real shape of what the model emits for "cast heal": partials, then final.
	var evs := _run(_inc(), [[1.48, "CAST", false], [1.80, "CAST HEEL", false], [2.12, "CAST HEEL", true]])
	eq(_casts(evs).size(), 1, "one cast from partial+final")
	if _casts(evs).size() == 1:
		eq(_casts(evs)[0]["spell"], "heal", "heel heard as heal")
		check(_casts(evs)[0]["power"] >= 0.99, "clean cast is full power: %s" % _casts(evs)[0]["power"])
		check(not _casts(evs)[0]["accidental"], "deliberate")
	# Fires on the first partial that contains the spell, not on the final.
	var inc := _inc()
	var e1 := inc.feed("CAST", false, 1.0)
	var e2 := inc.feed("CAST COR", false, 1.3)
	var e3 := inc.feed("CAST CORN", false, 1.6)
	eq(e1.size() + e2.size(), 0, "nothing before the spell word")
	eq(_casts(e3).size(), 1, "fires on the partial")
	for sp in SPELLS:
		var ev := _say("cast " + sp)
		eq(ev.size(), 1, "typed cast " + sp)
		if ev.size() == 1:
			check(ev[0]["power"] > 0.99, "typed power " + sp)


func _test_homophone_and_compound() -> void:
	for text in ["cast fireball", "cast fire ball", "castfireball", "CAST FIREBALL"]:
		var ev := _say(text)
		eq(ev.size(), 1, "fireball form: " + text)
		if not ev.is_empty():
			eq(ev[0]["spell"], "fireball", text)
			check(ev[0]["power"] >= 0.99, "fireball form full power: " + text)
	# "fire" must wait for "ball" on a partial.
	var inc := _inc()
	eq(_casts(inc.feed("CAST FIRE", false, 1.0)).size(), 0, "fire waits")
	eq(_casts(inc.feed("CAST FIRE BALL", false, 1.3)).size(), 1, "fire ball completes")
	var bowl := _say("cast fire bowl")
	eq(bowl.size(), 1, "fire bowl casts")
	if bowl.size() == 1:
		check(bowl[0]["power"] < 0.95 and bowl[0]["power"] > 0.7, "fire bowl reduced: %s" % bowl[0]["power"])
	# Weak "fire" never on a partial, but on the final.
	var inc2 := _inc()
	eq(_casts(inc2.feed("CAST FIRE", false, 1.0)).size(), 0, "")
	var fire := _casts(inc2.feed("CAST FIRE", true, 1.3))
	eq(fire.size(), 1, "cast fire at final")
	if fire.size() == 1:
		near(fire[0]["power"], 0.7, 0.01, "fire power")
	eq(_say("CASTCORN").size(), 1, "castcorn split")
	eq(_say("caste corn").size(), 1, "caste is cast")
	var cass := _say("cass eel")
	eq(cass.size(), 1, "cass eel casts")
	if cass.size() == 1:
		check(cass[0]["power"] < 0.8, "cass eel is weak: %s" % cass[0]["power"])


func _test_dedupe() -> void:
	var inc := _inc()
	var n := 0
	n += _casts(inc.feed("CAST HEAL", false, 1.0)).size()
	n += _casts(inc.feed("CAST HEAL NOW", false, 1.3)).size()
	n += _casts(inc.feed("CAST HEAL NOW", true, 1.6)).size()
	eq(n, 1, "partial+partial+final fires once")
	# "cast corn corn" stutter: once (the second is reported as ignored).
	var evs := _run(_inc(), [[1.0, "CAST CORN", false], [1.3, "CAST CORN COR", false],
		[1.6, "CAST CORN CORN", false], [1.9, "CAST CORN CORN", true]])
	eq(_casts(evs).size(), 1, "cast corn corn fires once")
	# Same spell again within 1 s: swallowed and reported.
	evs = _run(_inc(), [[1.0, "cast heal", true], [1.6, "cast heal", true]])
	eq(_casts(evs).size(), 1, "repeat within 1s suppressed")
	eq(evs.filter(func(e: Dictionary) -> bool: return e["kind"] == "ignored").size(), 1, "reported as ignored")
	evs = _run(_inc(), [[1.0, "cast heal", true], [2.3, "cast heal", true]])
	eq(_casts(evs).size(), 2, "repeat after 1s allowed")
	evs = _run(_inc(), [[1.0, "cast heal", true], [1.4, "cast armor", true]])
	eq(_casts(evs).size(), 2, "different spells not locked out")
	evs = _run(_inc(), [[1.0, "cast heal cast fireball", true]])
	eq(_casts(evs).size(), 2, "two spells in one breath")
	var inc3 := _inc()
	n = 0
	n += _casts(inc3.feed("CASS", false, 1.0)).size()
	n += _casts(inc3.feed("CAST", false, 1.3)).size()
	n += _casts(inc3.feed("CAST ARMOR", false, 1.6)).size()
	n += _casts(inc3.feed("CAST ARMOR", true, 1.9)).size()
	eq(n, 1, "revised keyword fires once")


func _test_negatives() -> void:
	# Default (loose): chatter without the trigger never casts, corn aside.
	var chatter := [
		"I need a heal over here", "nice fireball", "watch out for the fire ball",
		"put your armor on", "hello", "let's go left", "pop", "of course",
		"behind you", "castle", "the cast of the show", "I cast my vote", "heal", "fireball", "armor", "heel",
	]
	for text in chatter:
		var inc := _inc()
		var evs := inc.feed(text, false, 1.0)
		evs.append_array(inc.feed(text, true, 1.3))
		evs.append_array(inc.tick(10.0))
		eq(_casts(evs).size(), 0, "must not cast: " + text)
	for text in ["the cast of the show", "I cast my vote"]:
		var evs := _run(_inc(), [[1.0, text, true]], 10.0)
		eq(evs.size(), 0, "silent: " + text)
	var inc2 := _inc()
	var evs2 := _run(inc2, [[1.0, "CAST", true], [4.0, "HEAL", true]], 6.0)
	eq(_casts(evs2).size(), 0, "too slow: no cast")
	eq(_fizzles(evs2).size(), 1, "lone cast times out as a fizzle")
	if _fizzles(evs2).size() == 1:
		eq(_fizzles(evs2)[0]["reason"], "no_spell", "reason")


func _test_split_utterances() -> void:
	var evs := _run(_inc(), [[1.48, "CAST", false], [1.80, "CAST", true], [2.12, "HE", false],
		[2.44, "HEEL", false], [2.76, "HEEL", true]])
	eq(_casts(evs).size(), 1, "cross-utterance cast")
	if _casts(evs).size() == 1:
		check(_casts(evs)[0]["power"] > 0.9, "short pause barely costs: %s" % _casts(evs)[0]["power"])
		eq(_casts(evs)[0]["heard"], "cast heel", "heard string")
		check(not _casts(evs)[0]["accidental"], "split utterance is still deliberate")
	evs = _run(_inc(), [[1.48, "CAST", true], [2.44, "A", false], [3.08, "A HEEL", false], [3.40, "A HEEL", true]])
	eq(_casts(evs).size(), 1, "cast uh heal across utterances")
	if _casts(evs).size() == 1:
		check(_casts(evs)[0]["power"] < 0.9, "hesitation costs power: %s" % _casts(evs)[0]["power"])


func _test_power_scoring() -> void:
	var clean := _say("cast heal")[0]["power"] as float
	var pre := _say("okay cast heal")[0]["power"] as float
	var chatty := _say("well I think we should cast heal now")[0]["power"] as float
	check(clean > pre and pre > chatty, "more filler, less power: %s %s %s" % [clean, pre, chatty])
	check(pre > 0.9, "short preamble stays high: %s" % pre)
	check(chatty >= 0.7, "penalty is capped: %s" % chatty)
	var last := 2.0
	for gap in [0.5, 0.9, 1.2, 1.5, 1.69]:
		var evs := _run(_inc(), [[1.0, "CAST", false], [1.0 + gap, "CAST HEAL", true]])
		var cs := _casts(evs)
		check(cs.size() == 1, "gap %s casts" % gap)
		if cs.size() == 1:
			check(cs[0]["power"] <= last + 1e-6, "monotonic at gap %s" % gap)
			last = cs[0]["power"]
	check(last < 0.6, "long hesitation is weak: %s" % last)
	var evs2 := _run(_inc(), [[1.0, "CAST", false], [3.5, "CAST HEAL", true]], 3.6)
	eq(_casts(evs2).size(), 0, "past the window")
	var hill := _say("cast hill")
	eq(hill.size(), 1, "weak alias casts")
	if hill.size() == 1:
		check(hill[0]["power"] > 0.0 and hill[0]["power"] <= 0.61, "hill reduced: %s" % hill[0]["power"])
	for text in ["cast heal", "cast hail", "cast healing now please", "cass heel", "kast armour"]:
		for c in _say(text):
			check(c["power"] > 0.0 and c["power"] <= 1.0, "range " + text)


func _test_fizzles() -> void:
	var evs := _run(_inc(), [[1.0, "cast hello", true]])
	eq(_casts(evs).size(), 0, "hello is not a spell")
	eq(_fizzles(evs).size(), 1, "cast hello fizzles")
	if _fizzles(evs).size() == 1:
		eq(_fizzles(evs)[0]["reason"], "garbled", "hello is spell-ish (letters)")
	evs = _run(_inc(), [[1.0, "cast away", true]])
	eq(_fizzles(evs).size(), 1, "cast away fizzles")
	if _fizzles(evs).size() == 1:
		eq(_fizzles(evs)[0]["reason"], "unknown_spell", "unrelated word")
	evs = _run(_inc(), [[1.0, "cast", true]], 5.0)
	eq(_fizzles(evs).size(), 1, "lone cast fizzles after the window")
	var inc := _inc()
	inc.feed("cast", true, 1.0)
	eq(inc.tick(2.0).size(), 0, "still waiting")
	eq(inc.tick(3.5).size(), 1, "then fizzles")
	var inc2 := _inc({"fizzle_below": 0.95})
	evs = _run(inc2, [[1.0, "cast fire bowl", true]])
	eq(_casts(evs).size(), 0, "raised threshold fizzles")
	eq(_fizzles(evs).size(), 1, "fizzle reported")
	if _fizzles(evs).size() == 1:
		eq(_fizzles(evs)[0]["reason"], "too_garbled", "reason")
	var inc3 := _inc()
	_run(inc3, [[1.0, "cast away", true]])
	eq(_casts(_run(inc3, [[3.0, "cast heal", true]])).size(), 1, "recovers")


func _test_strictness() -> void:
	# strict: the utterance must start with the trigger.
	eq(_say("cast heal", {"strictness": "strict"}).size(), 1, "strict: cast heal")
	eq(_say("okay cast heal", {"strictness": "strict"}).size(), 1, "strict: preamble ok")
	eq(_say("should I cast heal", {"strictness": "strict"}).size(), 0, "strict: mid-sentence trigger does nothing")
	eq(_say("corn", {"strictness": "strict"}).size(), 0, "strict: bare corn does nothing")
	eq(_say("corner", {"strictness": "strict"}).size(), 0, "strict: corner does nothing")
	# loose (default): trigger anywhere; corn fires on any mention.
	var loose := _say("should I cast heal")
	eq(loose.size(), 1, "loose: trigger mid-sentence casts")
	if loose.size() == 1:
		check(loose[0]["accidental"], "mid-sentence is accidental")
	for text in ["corn", "corner", "corn on the cob", "I love cornbread", "that was corny"]:
		var c := _say(text)
		eq(c.size(), 1, "loose: corn mention casts: " + text)
		if c.size() == 1:
			eq(c[0]["spell"], "corn", text)
			check(c[0]["accidental"], "bare corn is accidental: " + text)
			check(c[0]["power"] < 1.0 or text == "corn", "sound-alike weaker: " + text)
	for text in ["heal", "nice fireball", "put your armor on", "I need a heal"]:
		eq(_say(text).size(), 0, "loose: bare non-corn spell does nothing: " + text)
	# chaos: any spell word anywhere.
	for pair in [["I need a heal over here", "heal"], ["nice fireball", "fireball"], ["put your armor on", "armor"], ["watch out for the fire ball", "fireball"], ["heal", "heal"]]:
		var c := _say(pair[0], {"strictness": "chaos"})
		eq(c.size(), 1, "chaos casts: " + pair[0])
		if c.size() == 1:
			eq(c[0]["spell"], pair[1], pair[0])
			check(c[0]["accidental"], "chaos bare is accidental")
	eq(_say("hello there", {"strictness": "chaos"}).size(), 0, "chaos: still not everything")
	# weak aliases never fire bare, even in chaos
	eq(_say("it is a hill", {"strictness": "chaos"}).size(), 0, "chaos: weak alias does not fire bare")
	# bare words wait for the final
	var inc := _inc({"strictness": "chaos"})
	eq(_casts(inc.feed("HEAL", false, 1.0)).size(), 0, "bare waits for the final")
	eq(_casts(inc.feed("HEAL", true, 1.3)).size(), 1, "bare fires at the final")
	# Two heard mentions in one line: corn + trigger spell
	eq(_say("cast heal corn").size(), 2, "trigger cast plus a corn mention")


func _test_accidental_label() -> void:
	var d: Dictionary = _say("cast heal")[0]
	check(not d["accidental"] and d["accidental_score"] < 0.1, "cast heal: deliberate")
	eq(d["signals"]["trigger_first"], true, "signal trigger_first")
	var o: Dictionary = _say("okay cast heal")[0]
	check(not o["accidental"], "preamble is still deliberate")
	var mid: Dictionary = _say("should I cast heal")[0]
	check(mid["accidental"], "mid-sentence trigger: accidental")
	check(mid["accidental_score"] >= 0.5, "score at least threshold")
	check("trigger mid-sentence" in str(mid["why"]), "why explains it: " + str(mid["why"]))
	var corner: Dictionary = _say("I was in the corner of the room")[0]
	check(corner["accidental"], "corner mention: accidental")
	eq(corner["signals"]["kind"], "sound_alike", "corner is a sound-alike")
	check("sound-alike 'corner'" in str(corner["why"]), "why mentions the token: " + str(corner["why"]))
	check("no trigger" in str(corner["why"]) and "words" in str(corner["why"]), "why lists signals")
	# "cast corner" starts with the trigger: deliberate despite the sound-alike.
	check(not _say("cast corner")[0]["accidental"], "cast corner is deliberate")
	# A pause before a mid-sentence trigger reads as a fresh phrase (lower score).
	var inc := _inc()
	inc.feed("I THINK", false, 1.0)
	inc.feed("I THINK CAST", false, 2.0)
	var fresh := _casts(inc.feed("I THINK CAST HEAL", true, 2.3))
	var plain := _say("I think cast heal")
	if fresh.size() == 1 and plain.size() == 1:
		check(fresh[0]["accidental_score"] < plain[0]["accidental_score"], "pause lowers the score")
	# The label never changes power: same words, same power either way.
	var p1 := _say("should I cast heal", {"accidental": {"threshold": 0.99, "no_trigger": 0.6, "mid_trigger": 0.5,
		"fresh_pause": -0.2, "fresh_pause_s": 0.9, "sound_alike": 0.1, "free_words": 3, "per_word": 0.04, "words_cap": 0.3}})
	var p2 := _say("should I cast heal")
	if p1.size() == 1 and p2.size() == 1:
		near(p1[0]["power"], p2[0]["power"], 0.0001, "label does not affect power")
		check(not p1[0]["accidental"] and p2[0]["accidental"], "threshold flips the label only")


func _test_triggers() -> void:
	# New trigger casts; the old one stops.
	var pickle := {"trigger": "pickle"}
	var c := _say("pickle heal", pickle)
	eq(c.size(), 1, "pickle heal casts")
	eq(_say("cast heal", pickle).size(), 0, "old trigger stops working")
	check(not c[0]["accidental"], "pickle is deliberate at the start")
	eq(_say("PICKLEHEEL", pickle).size(), 1, "run-together pickleheel is split")
	eq(_say("pickle fireball", pickle).size(), 1, "pickle fireball")
	var magic := _say("magic corn", {"trigger": "magic"})
	eq(magic.size(), 1, "magic corn")
	eq(_say("some in heal", {"trigger": "summon"}).size(), 1, "summon heard as 'some in'")
	eq(_say("summon armor", {"trigger": "summon"}).size(), 1, "summon armor")
	# A custom, unlisted word: itself and a plural.
	eq(_say("zorbo heal", {"trigger": "zorbo"}).size(), 1, "custom trigger")
	eq(_say("zorbos heal", {"trigger": "zorbo"}).size(), 1, "custom trigger plural")
	eq(_say("cast heal", {"trigger": "zorbo"}).size(), 0, "custom trigger replaces cast")
	# Strictness applies to whichever trigger is active.
	eq(_say("did you say pickle heal", {"trigger": "pickle", "strictness": "strict"}).size(), 0, "strict + pickle")
	eq(_say("did you say pickle heal", {"trigger": "pickle"}).size(), 1, "loose + pickle")
	# Fuzzy match for a long custom word.
	eq(_say("abracadabras heal", {"trigger": "abracadabra"}).size(), 1, "plural of a long trigger")
	eq(_say("abrakadabra heal", {"trigger": "abracadabra"}).size(), 1, "fuzzy long trigger")
	eq(_say("abrakadabra heal", {"trigger": "cast"}).size(), 0, "fuzzy only for the active trigger")
	# Fizzle text uses the trigger.
	var evs := _run(_inc(pickle), [[1.0, "pickle away", true]])
	eq(_fizzles(evs).size(), 1, "pickle away fizzles")
	if _fizzles(evs).size() == 1:
		check(str(_fizzles(evs)[0]["heard"]).begins_with("pickle"), "fizzle heard text")


func _test_explain() -> void:
	var ex := _inc().explain("CAST HEEL")
	eq(ex.size(), 5, "trigger + four spells")
	eq(ex[0]["word"], "cast", "first is the trigger")
	eq(ex[0]["kind"], "exact", "cast exact")
	eq(ex[1]["kind"], "homophone", "heel is a homophone of heal")
	eq(ex[2]["kind"], "", "fireball not heard")
	var wait := _inc().explain("CAST ARM")
	eq(wait[3]["kind"], "wait", "'arm' could still become armor")
	var near_miss := _inc().explain("CAST HILL")
	eq(near_miss[1]["kind"], "sound_alike", "hill is a near miss for heal")
	check(near_miss[1]["closeness"] > 0.0, "closeness set")
	var tr := _inc({"trigger": "pickle"}).explain("PICKLE CORN")
	eq(tr[0]["word"], "pickle", "explain uses the active trigger")
	eq(tr[0]["kind"], "exact", "pickle exact")


func _test_misc() -> void:
	eq(Incantation.tokenize("Let's GO, left!").size(), 3, "tokenize keeps apostrophes")
	eq(Incantation.tokenize("Let's GO, left!")[0], "let's", "apostrophe word")
	near(Incantation.similarity("heal", "heal"), 1.0, 0.0001, "sim equal")
	check(Incantation.similarity("heal", "hello") < 1.0, "sim differ")
	var inc := Incantation.new(PackedStringArray(["frost"]))
	eq(_casts(inc.feed("cast frost", true, 1.0)).size(), 1, "custom spell id")
	var inc2 := _inc()
	inc2.feed("CAST", false, 1.0)
	inc2.tick(9.0)
	eq(_casts(inc2.feed("CAST HEAL", false, 10.0)).size(), 1, "stale utterance reset")
	var inc3 := _inc()
	inc3.feed("CAST", true, 1.0)
	check(inc3.is_pending(), "pending")
	inc3.reset()
	check(not inc3.is_pending(), "reset clears pending")
	eq(_inc({"strictness": "bogus"}).strictness(), "loose", "bad strictness falls back")


func _test_settings() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SETTINGS))
	var d := VoiceSettings.load_settings(TMP_SETTINGS)
	eq(d["trigger_word"], "cast", "default trigger")
	eq(d["strictness"], "loose", "default strictness")
	check(VoiceSettings.save_settings({"trigger_word": "pickle"}, TMP_SETTINGS), "save ok")
	eq(VoiceSettings.load_settings(TMP_SETTINGS)["trigger_word"], "pickle", "persisted trigger")
	eq(VoiceSettings.load_settings(TMP_SETTINGS)["strictness"], "loose", "other keys untouched")
	VoiceSettings.save_settings({"strictness": "chaos"}, TMP_SETTINGS)
	var both := VoiceSettings.load_settings(TMP_SETTINGS)
	eq(both["trigger_word"], "pickle", "trigger survives a later save")
	eq(both["strictness"], "chaos", "strictness persisted")
	# Other sections in the same file are kept.
	var cfg := ConfigFile.new()
	cfg.load(TMP_SETTINGS)
	cfg.set_value("audio", "volume", 0.5)
	cfg.save(TMP_SETTINGS)
	VoiceSettings.save_settings({"trigger_word": "magic"}, TMP_SETTINGS)
	var cfg2 := ConfigFile.new()
	cfg2.load(TMP_SETTINGS)
	eq(cfg2.get_value("audio", "volume", 0.0), 0.5, "foreign section kept")
	eq(cfg2.get_value("voice", "trigger_word", ""), "magic", "section voice, key trigger_word")
	# Validation
	check(VoiceSettings.validate_trigger("pickle")["ok"], "pickle valid")
	check(not VoiceSettings.validate_trigger("two words")["ok"], "single word only")
	check(not VoiceSettings.validate_trigger("")["ok"], "empty rejected")
	check(not VoiceSettings.validate_trigger("hea1")["ok"], "digits rejected")
	check(not VoiceSettings.validate_trigger("heal")["ok"], "spell word rejected")
	check(VoiceSettings.validate_trigger("yo")["warnings"].size() >= 1, "short word warned")
	check(VoiceSettings.validate_trigger("hello")["warnings"].size() >= 1, "chatter word warned")
	var clean := VoiceSettings.validate_trigger("Pickle ")
	eq(clean["word"], "pickle", "normalized")
	for w in VoiceCaster.TRIGGER_OPTIONS:
		check(VoiceSettings.validate_trigger(w)["ok"], "option valid: " + w)
	check("magic" in VoiceCaster.TRIGGER_OPTIONS and "pickle" in VoiceCaster.TRIGGER_OPTIONS, "magic + pickle stay")
	if FileAccess.file_exists(VoiceSettings.PRON_DICT):
		var unknown := VoiceSettings.validate_trigger("zzxqv")
		check(unknown["warnings"].size() >= 1, "word missing from the pron dict is warned")
		var known := VoiceSettings.validate_trigger("pickle")
		eq(known["warnings"].size(), 0, "pickle is in the pron dict: %s" % str(known["warnings"]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SETTINGS))


func _test_caster_typed() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_LOG))
	var caster := VoiceCaster.new()
	caster.use_mic = false
	caster.settings_path = TMP_SETTINGS
	caster.voice_log = VoiceLog.new(TMP_LOG)
	add_child(caster)
	var casts: Array = []
	var fizzles: Array = []
	var heard_log: Array = []
	var finished: Array = []
	var trig_changes: Array = []
	caster.spell_spoken.connect(func(id: String, power: float, h: String) -> void:
		casts.append({"id": id, "power": power, "heard": h, "acc": caster.last_cast_accidental()}))
	caster.spell_fizzled.connect(func(h: String, reason: String) -> void: fizzles.append(reason))
	caster.heard.connect(func(text: String, final: bool) -> void: heard_log.append([text, final, caster.last_heard_typed]))
	caster.utterance_finished.connect(func(text: String, outcome: Dictionary, typed: bool) -> void: finished.append([text, outcome["kind"], typed]))
	caster.trigger_word_changed.connect(func(w: String) -> void: trig_changes.append(w))
	# Without a model: start() is false but typed input works.
	var started := caster.start(PackedStringArray(SPELLS))
	if not started:
		check(not caster.is_ready(), "not ready without a model")
	caster.inject_text("cast heal")
	eq(casts.size(), 1, "typed cast works")
	eq(casts[0]["id"], "heal", "typed spell")
	eq(casts[0]["acc"], false, "last_cast_accidental false for a plain cast")
	eq(heard_log[0], ["cast heal", true, true], "typed text is shown as heard, marked typed")
	eq(finished[0], ["cast heal", "cast", true], "utterance_finished")
	caster.inject_text("blah blah")
	eq(finished[1][1], "none", "unmatched chatter still reported, outcome none")
	eq(heard_log[1][0], "blah blah", "unmatched text still heard verbatim")
	caster.inject_text("I said corner there")
	eq(casts.size(), 2, "loose corn mention casts from typed text")
	eq(casts[1]["acc"], true, "corner is accidental")
	# Switching triggers: old stops, new casts, state reset.
	var v := caster.set_trigger_word("pickle")
	check(v["ok"], "set_trigger_word ok")
	eq(caster.get_trigger_word(), "pickle", "get_trigger_word")
	eq(trig_changes, ["pickle"], "trigger_word_changed emitted")
	var before := casts.size()
	caster.inject_text("cast fireball")
	eq(casts.size(), before, "old trigger stops casting")
	caster.inject_text("pickle fireball")
	eq(casts.size(), before + 1, "new trigger casts")
	eq(casts[before]["id"], "fireball", "pickle fireball spell")
	check(caster.get_incantation().vocabulary().has("pickle"), "vocabulary rebuilt")
	# Persisted
	eq(VoiceSettings.load_settings(TMP_SETTINGS)["trigger_word"], "pickle", "trigger persisted to settings.cfg")
	# Invalid word changes nothing
	var bad := caster.set_trigger_word("two words")
	check(not bad["ok"], "invalid trigger rejected")
	eq(caster.get_trigger_word(), "pickle", "unchanged after a rejected word")
	# Custom word with warnings
	var custom := caster.set_trigger_word("zxqv", false)
	check(custom["ok"], "custom word accepted")
	caster.set_trigger_word("pickle", false)
	# Strictness
	check(caster.set_strictness("strict"), "set_strictness")
	var b2 := casts.size()
	caster.inject_text("did you say pickle heal")
	eq(casts.size(), b2, "strict: mid-sentence does not cast")
	caster.set_strictness("loose")
	caster.inject_text("did you say pickle armor")
	eq(casts.size(), b2 + 1, "loose casts mid-sentence")
	check(not caster.set_strictness("bogus"), "bad mode rejected")
	# A new caster reads the saved choice at start().
	var caster2 := VoiceCaster.new()
	caster2.use_mic = false
	caster2.settings_path = TMP_SETTINGS
	caster2.voice_log = VoiceLog.new(TMP_LOG)
	add_child(caster2)
	caster2.start(PackedStringArray(SPELLS))
	eq(caster2.get_trigger_word(), "pickle", "saved trigger applied at start")
	eq(caster2.get_strictness(), "loose", "saved strictness applied at start")
	# Passive log
	var rows := VoiceLog.read_all(TMP_LOG)
	check(rows.size() >= 5, "utterances were logged: %d" % rows.size())
	var heals := rows.filter(func(r: Dictionary) -> bool: return r["heard"] == "cast heal")
	eq(heals.size(), 1, "cast heal logged once")
	if heals.size() == 1:
		eq(heals[0]["spell"], "heal", "log spell")
		eq(heals[0]["label"], "deliberate", "log label")
		eq(heals[0]["source"], "typed", "log source")
		check("trigger=1" in heals[0]["signals"], "log signals")
		eq(heals[0]["trigger"], "cast", "log trigger word")
		eq(heals[0]["mode"], "loose", "log mode")
	var none_rows := rows.filter(func(r: Dictionary) -> bool: return r["label"] == "none")
	check(none_rows.size() >= 1, "unmatched chatter logged too")
	caster.queue_free()
	caster2.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_LOG))
