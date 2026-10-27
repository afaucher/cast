extends TestCase
## Pure logic: feed recognizer hypotheses to Incantation, check power/fizzle,
## strictness modes, trigger words, the accidental label, settings and the
## VoiceCaster typed path. No audio and no model needed.

var SPELLS: Array = SpellBook.ids()   # (the game's castable spells: SpellBook is the one list)
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
	_test_tentacles()
	_test_teeth()
	_test_vines_damp_coffee()
	_test_chicken()
	_test_orders()
	_test_panel_cards()
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
		near(fire[0]["power"], 0.84, 0.01, "fire power (0.84 since the voice log, 2026-10-24)")
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
	_test_log_aliases()


## The aliases added from the voice log (2026-10-24): each casts after the trigger, none casts bare even in chaos, and a cut-off
## "CAST HE" casts heal at once (the user: "It's getting repeated because it didn't fire"); a "CAST HEEL" right after is the
## same heal, not a second one.
func _test_log_aliases() -> void:
	for pair: Array in [["cast he", "heal"], ["cast tenacles", "tentacles"], ["cast temicals", "tentacles"], ["cast stamp", "damp"],
			["cast fibal", "fireball"], ["cast fibrel", "fireball"], ["cast fireb", "fireball"], ["gaste corn", "corn"],
			["gaste heal", "heal"]]:
		var cs := _say(pair[0])
		eq(cs.size(), 1, "'%s' casts" % pair[0])
		if cs.size() == 1:
			eq(cs[0]["spell"], pair[1], "'%s' is %s" % [pair[0], pair[1]])
	var fire := _say("cast fire")
	check(fire.size() == 1 and float(fire[0]["power"]) > 0.8, "'cast fire' is a strong fireball now (%s)" % str(fire))
	for word in ["he", "fire", "stamp", "tenacles", "fibal"]:
		eq(_say(word, {"strictness": "chaos"}).size(), 0, "bare '%s' never casts, even in chaos" % word)
	for text in ["he said so", "he is here", "gas station", "the gas is on", "gas fireball"]:
		eq(_say(text).size(), 0, "chatter '%s' casts nothing" % text)
	var evs := _run(_inc(), [[1.0, "CAST HE", true], [1.04, "CAST HEEL", true]], 3.5)
	var cs := _casts(evs)
	eq(cs.size(), 1, "a cut-off 'CAST HE' then 'CAST HEEL' is one heal")
	if cs.size() == 1:
		check(float(cs[0]["power"]) >= 0.75, "... fired on the first half, at a good strength (%.2f)" % float(cs[0]["power"]))


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
	eq(ex.size(), 12, "trigger + eleven spells")
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


func _test_tentacles() -> void:
	# Exact forms, as the model writes them ("CAST TENTACLES", "CAST TENTACLE").
	for text in ["cast tentacles", "cast tentacle", "castTENTACLES", "CAST TENTACLE", "okay cast tentacles"]:
		var c := _say(text)
		eq(c.size(), 1, "tentacles form: " + text)
		if c.size() == 1:
			eq(c[0]["spell"], "tentacles", text)
			check(c[0]["power"] >= 0.95, "tentacles form is near full power: %s %s" % [text, c[0]["power"]])
			check(not c[0]["accidental"], "deliberate: " + text)
	# Streaming: fires on the first partial that holds the word (TENT/TENTA do nothing).
	var inc := _inc()
	eq(_casts(inc.feed("CAST", false, 1.0)).size(), 0, "cast alone waits")
	eq(_casts(inc.feed("CAST TENT", false, 1.3)).size(), 0, "tent is not the spell")
	eq(_casts(inc.feed("CAST TENTA", false, 1.5)).size(), 0, "tenta is not the spell")
	eq(_casts(inc.feed("CAST TENTACLES", false, 1.8)).size(), 1, "fires on the partial")
	eq(_casts(inc.feed("CAST TENTACLES", true, 2.1)).size(), 0, "and not again on the final")
	# Singular partial then plural: one cast.
	var evs := _run(_inc(), [[1.0, "CAST TENTACLE", false], [1.3, "CAST TENTACLES", false], [1.6, "CAST TENTACLES", true]])
	eq(_casts(evs).size(), 1, "tentacle -> tentacles fires once")
	# Measured mishearings (TTS at the fastest rate; split "cast | caste ... acles"): reduced power.
	for pair in [["cast headacles", 0.8], ["cast headacle", 0.75], ["cast headagle", 0.75], ["cast acles", 0.75]]:
		var c := _say(pair[0])
		eq(c.size(), 1, "alias casts: " + pair[0])
		if c.size() == 1:
			eq(c[0]["spell"], "tentacles", pair[0])
			near(c[0]["power"], pair[1], 0.001, "alias quality " + pair[0])
	# The caster rejoins the finals "CA" + "STE" + "ACLES" into one token (JOIN_GAP); it must split.
	eq(_say("casteacles").size(), 1, "run-together casteacles is split and casts")
	# Never a mention word: bare or buried in chatter does nothing in strict/loose.
	for text in ["tentacles", "tentacle", "watch out for the tentacles", "tentacles tentacles", "headacles", "acles"]:
		eq(_say(text).size(), 0, "loose: bare does nothing: " + text)
		eq(_say(text, {"strictness": "strict"}).size(), 0, "strict: bare does nothing: " + text)
	# Chaos: the exact word anywhere casts (like every spell), the weak aliases never do bare.
	eq(_say("watch out for the tentacles", {"strictness": "chaos"}).size(), 1, "chaos: tentacles anywhere")
	for text in ["it gives me headacles", "what acles", "the headagle"]:
		eq(_say(text, {"strictness": "chaos"}).size(), 0, "chaos: weak alias does not fire bare: " + text)
	# Sound-alikes of the word in chatter (measured TTS: "TESTACLES", "TEN TICKETS", "ATTACK") do nothing.
	for text in ["testicles", "testacles", "ten tickets", "attack", "I can't tackle this", "tent tackles", "tentative", "tenticles"]:
		eq(_say(text).size(), 0, "no bare cast: " + text)
		eq(_say(text, {"strictness": "chaos"}).size(), 0, "no chaos cast: " + text)
	# No confusion with the other spells, both directions (cast <spell> fires exactly that spell).
	for sp in SPELLS:
		var c := _say("cast " + sp)
		eq(c.size(), 1, "one spell for cast " + sp)
		if c.size() == 1:
			eq(c[0]["spell"], sp, "cast %s fires %s" % [sp, sp])
	for text in ["cast tentacles", "cast tentacle", "cast headacles"]:
		for c in _say(text):
			eq(c["spell"], "tentacles", "only tentacles: " + text)
	# The nearest other spell words stay put.
	var garbled := _run(_inc(), [[1.0, "cast tent", true]])
	eq(_casts(garbled).size(), 0, "cast tent is not a spell")
	eq(_fizzles(garbled).size(), 1, "cast tent fizzles")
	# Not a hair-trigger: only corn is a mention spell.
	var mentions: Array = Incantation.TUNING["mention_spells"]
	check(not mentions.has("tentacles"), "tentacles is not a mention spell")
	# Both words join the recognizer's vocabulary, and it is in the explain cards.
	check(_inc().vocabulary().has("tentacles"), "vocab has tentacles")
	eq(_inc().explain("CAST TENTACLES")[5]["kind"], "exact", "card kind exact")
	eq(_inc().explain("CAST TENTACLE")[5]["kind"], "homophone", "tentacle is a homophone card")
	eq(_inc().explain("CAST HEADACLES")[5]["kind"], "sound_alike", "headacles is a sound-alike card")
	# The caster's own default list has all nine.
	eq(Array(VoiceCaster.default_spells()), Array(SpellBook.ids()), "the default spells are SpellBook's castable spells")
	check(VoiceCaster.default_spells().has("tentacles"), "VoiceCaster default spells include tentacles")
	check(not VoiceSettings.validate_trigger("tentacles")["ok"], "tentacles cannot be the trigger word")


## TEETH: one syllable, the riskiest spell word. Measured with TTS through the real model (see the
## Incantation header and tests/test_voice_audio.gd): it writes "TEETH"/"TOOTH" for every clip, so
## there are no sound-alike aliases except the one fused "CASTOOTH" at the fastest rate, and the
## look-alikes ("these", "tea", "tease", "teach") must never cast.
func _test_teeth() -> void:
	for text in ["cast teeth", "cast tooth", "castTEETH", "CAST TOOTH", "okay cast teeth", "cast the teeth", "cast teeth teeth"]:
		var c := _say(text)
		eq(c.size(), 1, "teeth form: " + text)
		if c.size() == 1:
			eq(c[0]["spell"], "teeth", text)
			check(c[0]["power"] >= 0.9, "teeth form is near full power: %s %s" % [text, c[0]["power"]])
			check(not c[0]["accidental"], "deliberate: " + text)
	# Streaming: TE/TEE do nothing, the word fires on the first partial that holds it, once.
	var inc := _inc()
	eq(_casts(inc.feed("CAST", false, 1.0)).size(), 0, "cast alone waits")
	eq(_casts(inc.feed("CAST TE", false, 1.3)).size(), 0, "te is not the spell")
	eq(_casts(inc.feed("CAST TEE", false, 1.5)).size(), 0, "tee is not the spell")
	eq(_casts(inc.feed("CAST TEETH", false, 1.8)).size(), 1, "fires on the partial")
	eq(_casts(inc.feed("CAST TEETH", true, 2.1)).size(), 0, "and not again on the final")
	# The measured partial ladder ("CAST CAST TE CAST TEETH [CAST TEETH]") is one cast.
	var ladder := _run(_inc(), [[1.0, "CAST", false], [1.3, "CAST TE", false], [1.6, "CAST TEETH", false], [1.9, "CAST TEETH", true]])
	eq(_casts(ladder).size(), 1, "the real partial ladder casts once")
	# The one measured mishearing: the fastest "tooth" is fused to "CASTOOTH" (alias "ooth", 0.75).
	var fused := _say("castooth")
	eq(fused.size(), 1, "fused castooth casts")
	if fused.size() == 1:
		eq(fused[0]["spell"], "teeth", "castooth is teeth")
		near(fused[0]["power"], 0.75, 0.001, "alias quality")
	# Never a mention word, bare or buried in chatter does nothing in strict/loose.
	for text in ["teeth", "tooth", "ooth", "nice teeth", "brush your teeth", "my teeth hurt", "the tooth fairy"]:
		eq(_say(text).size(), 0, "loose: bare does nothing: " + text)
		eq(_say(text, {"strictness": "strict"}).size(), 0, "strict: bare does nothing: " + text)
	# Chaos: the exact word anywhere casts (like every spell), the weak alias never does bare.
	eq(_say("nice teeth", {"strictness": "chaos"}).size(), 1, "chaos: teeth anywhere")
	eq(_say("brush your teeth", {"strictness": "chaos"}).size(), 1, "chaos: teeth anywhere")
	eq(_say("ooth", {"strictness": "chaos"}).size(), 0, "chaos: the weak alias does not fire bare")
	# The look-alikes, as the model writes them (measured: "cast these" -> THESE, "cast tea" -> TEA/TIT/T,
	# "cast tease" -> TIES, "cast teach" -> TEACH), must not cast in any mode. Deliberately NOT aliased.
	for text in ["cast these", "cast tea", "cast tit", "cast tease", "cast ties", "cast tees", "cast tee", "cast teach", "cast teach me",
			"cast teen", "cast t", "cast tea tea", "cast teeth's", "cast tenth", "cast teethe", "these", "tea", "teach me", "tease", "ties"]:
		eq(_say(text).size(), 0, "loose: no cast: " + text)
		eq(_say(text, {"strictness": "chaos"}).size(), 0, "chaos: no cast: " + text)
		eq(_say(text, {"strictness": "strict"}).size(), 0, "strict: no cast: " + text)
	# "cast these" fizzles (the player is told), it does not stay silent or cast something else.
	var these := _run(_inc(), [[1.0, "CAST THESE", true]])
	eq(_casts(these).size(), 0, "cast these casts nothing")
	eq(_fizzles(these).size(), 1, "cast these fizzles")
	# No confusion with the other spells, both directions.
	for sp in SPELLS:
		var c := _say("cast " + sp)
		eq(c.size(), 1, "one spell for cast " + sp)
		if c.size() == 1:
			eq(c[0]["spell"], sp, "cast %s fires %s" % [sp, sp])
	for text in ["cast teeth", "cast tooth", "cast ooth"]:
		for c in _say(text):
			eq(c["spell"], "teeth", "only teeth: " + text)
	for text in ["cast tentacles", "cast heal", "cast corn", "cast armor", "cast fireball", "cast tenth"]:
		for c in _say(text):
			check(c["spell"] != "teeth", "never teeth: " + text)
	# Not a hair-trigger: only corn is a mention spell.
	var mentions: Array = Incantation.TUNING["mention_spells"]
	check(not mentions.has("teeth"), "teeth is not a mention spell")
	# Vocabulary, explain cards and the caster's own default list.
	check(_inc().vocabulary().has("teeth"), "vocab has teeth")
	eq(_inc().explain("CAST TEETH")[6]["kind"], "exact", "card kind exact")
	eq(_inc().explain("CAST TOOTH")[6]["kind"], "homophone", "tooth is a homophone card")
	eq(_inc().explain("CAST OOTH")[6]["kind"], "sound_alike", "ooth is a sound-alike card")
	eq(_inc().explain("CAST THESE")[6]["kind"], "", "these is not a teeth card")
	check(VoiceCaster.default_spells().has("teeth"), "VoiceCaster default spells include teeth")
	check(not VoiceSettings.validate_trigger("teeth")["ok"], "teeth cannot be the trigger word")


## Vines, damp and coffee: their spoken forms and the measured mishearings cast with the trigger; the look-alikes and
## chatter ("damn" is everywhere) never do, and none of the words is a mention word (only corn is).
func _test_vines_damp_coffee() -> void:
	var forms := {
		"vines": ["cast vines", "cast vine", "okay cast vines", "castbines", "cast bines", "cast vines now"],
		"damp": ["cast damp", "okay cast damp", "cast damp now", "please cast damp"],
		"coffee": ["cast coffee", "cast coughing", "cast cough", "okay cast coffee", "cast coffee now"],
	}
	for id: String in forms:
		for text: String in forms[id]:
			var c := _say(text)
			eq(c.size(), 1, "%s form: %s" % [id, text])
			if c.size() == 1:
				eq(c[0]["spell"], id, text)
				check(float(c[0]["power"]) >= 0.7, "%s is not weak: %s" % [text, c[0]["power"]])
				check(not bool(c[0]["accidental"]), "%s is deliberate" % text)
	# Exact words are full power; the measured mishearings are a little less.
	near(float(_say("cast vines")[0]["power"]), 1.0, 0.001, "cast vines is full power")
	near(float(_say("cast damp")[0]["power"]), 1.0, 0.001, "cast damp is full power")
	near(float(_say("cast coffee")[0]["power"]), 1.0, 0.001, "cast coffee is full power")
	check(float(_say("cast coughing")[0]["power"]) < 0.9, "coughing is a sound-alike: a bit weaker")
	# Without the trigger nothing casts in loose or strict, whatever is said.
	for text in ["vines", "damp", "coffee", "nice vines", "damp towel", "I need coffee", "coffee break", "coughing", "bines",
			"damn", "that was damn good", "goddamn it", "dump", "camp", "dam", "wines", "vibes", "fines", "binds", "copy", "I am coughing"]:
		eq(_say(text).size(), 0, "no trigger, no cast (loose): " + text)
		eq(_say(text, {"strictness": "strict"}).size(), 0, "no trigger, no cast (strict): " + text)
	# Look-alikes after the trigger are not casts either ("damn" is not aliased: it is chatter, not a mishearing).
	for text in ["cast damn", "cast dam", "cast dump", "cast camp", "cast wines", "cast vibes", "cast fines", "cast binds", "cast copy", "cast cop", "cast fine", "cast wine"]:
		eq(_say(text).size(), 0, "look-alike does not cast: " + text)
	# Chaos: the real words anywhere.
	for pair in [["nice vines", "vines"], ["damp towel", "damp"], ["I need coffee", "coffee"]]:
		var c := _say(pair[0], {"strictness": "chaos"})
		eq(c.size(), 1, "chaos: " + pair[0])
		if c.size() == 1:
			eq(c[0]["spell"], pair[1], "chaos picks " + pair[1])
			check(bool(c[0]["accidental"]), "chaos cast of '%s' is flagged accidental" % pair[0])
	# The mishearings (below the 0.85 bare floor) never fire without a trigger, even in chaos.
	for text in ["coughing", "bines", "damn", "wines"]:
		eq(_say(text, {"strictness": "chaos"}).size(), 0, "chaos ignores a bare mishearing: " + text)
	# The spells are in the vocabulary, cannot be trigger words, are not mention spells and have cards.
	for id in ["vines", "damp", "coffee"]:
		check(_inc().vocabulary().has(id), "vocab has " + id)
		check(not VoiceSettings.validate_trigger(id)["ok"], id + " cannot be the trigger word")
		check(VoiceCaster.default_spells().has(id), "VoiceCaster default spells include " + id)
	var mentions: Array = _inc().config()["mention_spells"]
	for id in ["vines", "damp", "coffee"]:
		check(not mentions.has(id), id + " is not a mention spell")
	# One spell never fires another.
	for text in ["cast vines", "cast damp", "cast coffee"]:
		for c in _say(text):
			eq(c["spell"], text.substr(5), "only itself: " + text)


## Chicken: "cast chicken" and the plural cast with the trigger at full power; the look-alikes ("kitchen", "chick",
## "check in", "thicken") never do, a bare "chicken" (and "don't chicken out") casts in chaos only, and it is not a mention
## word. Measured through the real model: tests/test_voice_audio.gd (the CHICKEN note in Incantation's header).
func _test_chicken() -> void:
	for text in ["cast chicken", "cast chickens", "okay cast chicken", "please cast chicken", "cast chicken now", "castchicken"]:
		var c := _say(text)
		eq(c.size(), 1, "chicken form: " + text)
		if c.size() == 1:
			eq(c[0]["spell"], "chicken", text)
			check(float(c[0]["power"]) >= 0.85, "%s is not weak: %s" % [text, c[0]["power"]])
			check(not bool(c[0]["accidental"]), "%s is deliberate" % text)
	near(float(_say("cast chicken")[0]["power"]), 1.0, 0.001, "cast chicken is full power")
	for text in ["chicken", "chickens", "don't chicken out", "watch out for the chicken", "kitchen", "chick", "check in", "thicken"]:
		eq(_say(text).size(), 0, "no trigger, no cast (loose): " + text)
		eq(_say(text, {"strictness": "strict"}).size(), 0, "no trigger, no cast (strict): " + text)
	for text in ["cast kitchen", "cast chick", "cast check in", "cast thicken"]:
		eq(_say(text).size(), 0, "look-alike does not cast: " + text)
	var chaos := _say("don't chicken out", {"strictness": "chaos"})
	eq(chaos.size(), 1, "chaos: the real word anywhere")
	if chaos.size() == 1:
		eq(chaos[0]["spell"], "chicken", "chaos picks chicken")
		check(bool(chaos[0]["accidental"]), "and flags it accidental")
	check(_inc().vocabulary().has("chicken"), "vocab has chicken")
	check(not VoiceSettings.validate_trigger("chicken")["ok"], "chicken cannot be the trigger word")
	check(not (_inc().config()["mention_spells"] as Array).has("chicken"), "chicken is not a mention spell")
	for c in _say("cast chicken"):
		eq(c["spell"], "chicken", "only itself")


func _order_events(evs: Array) -> Array:
	return evs.filter(func(e: Dictionary) -> bool: return e["kind"] == "order").map(func(e: Dictionary) -> String: return "%s %s" % [e["who"], e["order"]])


## One typed utterance through a fresh Incantation: the orders, as "who order".
func _orders_of(text: String, overrides: Dictionary = {}) -> Array:
	return _order_events(_run(_inc(overrides), [[1.0, text, true]]))


## Voice orders (Incantation's VOICE ORDERS): the name is the trigger, the order word follows at once.
func _test_orders() -> void:
	# Every official name with every order.
	for said: String in ["everyone", "crew", "hench", "hench four", "rebar", "wick", "gasket", "beatrice", "mabel", "elsie",
			"lionel", "pearl", "penny", "molly", "bloom", "iris", "stan", "gary", "steve", "simon", "nigel", "brad", "todd", "gordon",
			"kevin", "craig", "keith"]:
		for o: String in ["go", "attack", "follow"]:
			eq(_orders_of("%s %s" % [said, o]), ["%s %s" % [said, o]], "order: %s %s" % [said, o])
	# Aliases, punctuation and case as the recognizer writes them.
	var aliases := {"EVERYBODY GO": "everyone go", "all hands follow": "everyone follow", "Team attack": "crew attack",
		"SQUAD GO": "crew go", "Mr. Bloom follow": "bloom follow", "MISTER BLOOM GO": "bloom go", "henchmen attack": "hench attack",
		"henchman follow": "hench follow", "number four go": "hench four go", "Hench #4 go": "hench four go", "RIBAR FOLLOW": "rebar follow",
		"Rebar, go!": "rebar go", "okay rebar go": "rebar go", "rebar go now": "rebar go", "rebar follow me": "rebar follow"}
	for text: String in aliases:
		eq(_orders_of(text), [aliases[text]], "alias: " + text)
	# A run-together name and order word is split, and the model's measured spellings of the names count.
	var heard := {"REBARGO": "rebar go", "CRUGO": "crew go", "CREWO": "crew go", "SQUADO": "crew go", "HENNYGO": "penny go",
		"WICKOW": "wick go", "TODGO": "todd go", "GERRYGO": "gary go", "HENCHFOREGO": "hench four go", "GASKETATTACK": "gasket attack",
		"STEVE FOLLOWED": "steve follow", "GARRY ATTACK": "gary attack", "TOD FOLLOW": "todd follow", "LION'LL FOLLOW": "lionel follow",
		"HENCH FOR ATTACK": "hench four attack", "HENCEFORE FOLLOW": "hench four follow", "STAND ATTACK": "stan attack",
		"WE BAR ATTACK": "rebar attack", "CRUE ATTACK": "crew attack", "HEDGE GO": "hench go", "IRAS ATTACK": "iris attack",
		"BLOOMGOT": "bloom go", "KAVIN FOLLOW": "kevin follow", "CABIN GO": "kevin go",
		"BEATRICE GIRL": "beatrice go", "KEITH GIRL": "keith go", "ELSIE GOE": "elsie go", "PEARL FALLOW": "pearl follow",
		"BREAD FOLLOW": "brad follow", "CREEK ATTACK": "craig attack", "GORDING GO": "gordon go", "LION ALL ATTACK": "lionel attack"}
	for text: String in heard:
		eq(_orders_of(text), [heard[text]], "heard as: " + text)
	for text: String in ["CASTLE", "TOMATO", "GO TO", "A CABIN IN THE WOODS", "TRIM THE HEDGE", "HODGEPODGE"]:
		eq(_orders_of(text), [], "no order: " + text)
	# Chatter: the order word must follow the name at once; possessives and other forms are not the name / order word.
	for text: String in ["Rebar just goes in", "Rebar goes in first", "Gasket's down", "everyone's dead", "let's go", "follow me guys",
			"hold on", "crew's dead", "Gasket's holding the door", "go go go", "attack", "nice one Gasket", "the henchmen are attacking",
			"Gary's following us", "we should go", "rebar going", "gasket heal me", "cast heal", "go rebar", "attack wick",
			"Steve followed us here", "Gary got shot", "Keith girl is here", "Stan got it", "stand back"]:
		eq(_orders_of(text), [], "no order: " + text)
	# A bare order word never orders anyone, in any mode.
	for mode: String in ["strict", "loose", "chaos"]:
		eq(_orders_of("go", {"strictness": mode}), [], "[%s] a bare go" % mode)
		eq(_orders_of("rebar go", {"strictness": mode}), ["rebar go"], "[%s] rebar go" % mode)
	# Strict: the name opens the utterance (preamble aside); loose and chaos take it anywhere.
	eq(_orders_of("where did Wick go", {"strictness": "strict"}), [], "strict: a name mid-sentence is chatter")
	eq(_orders_of("where did Wick go"), ["wick go"], "loose: name and order word together anywhere (by design)")
	eq(_orders_of("okay wick go", {"strictness": "strict"}), ["wick go"], "strict: preamble words are fine")
	var mid: Array = _run(_inc(), [[1.0, "where did Wick go", true]]).filter(func(e: Dictionary) -> bool: return e["kind"] == "order")
	check(mid.size() == 1 and bool(mid[0]["accidental"]) and not bool(mid[0]["at_start"]), "a mid-sentence order is labelled accidental")
	# The name and the order word in two utterances (a comma's pause): within order_window it is one order; later, nothing.
	var inc := _inc()
	var evs := _run(inc, [[1.0, "REBAR", false], [1.2, "REBAR", true], [1.6, "GO", false], [1.7, "GO", true]])
	eq(_order_events(evs), ["rebar go"], "REBAR | GO (a short pause) is one order")
	inc = _inc()
	evs = _run(inc, [[1.0, "REBAR", true], [3.5, "GO", true]])
	eq(_order_events(evs), [], "REBAR ... 2.5 s ... GO is not")
	inc = _inc()
	evs = _run(inc, [[1.0, "REBAR", true]], 1.0 + float(inc.config()["order_window"]) + 0.2)
	evs.append_array(_run(inc, [[3.0, "GO", true]]))
	eq(_order_events(evs), [], "a name waiting for its order word expires")
	# Partials do not fire an order: only the final ("REBAR GO" could still become "REBAR GOES IN").
	inc = _inc()
	eq(_order_events(_run(inc, [[1.0, "REBAR GO", false]])), [], "no order on a partial")
	eq(_order_events(_run(inc, [[1.3, "REBAR GOES IN", true]])), [], "and the final that turned into chatter gives none")
	# The double fire: the same order again within order_lockout is one order.
	inc = _inc()
	evs = _run(inc, [[1.0, "rebar go", true], [1.6, "rebar go", true], [4.0, "rebar go", true]])
	eq(_order_events(evs), ["rebar go", "rebar go"], "a repeat within the lockout is dropped, a later one counts")
	check(evs.any(func(e: Dictionary) -> bool: return e["kind"] == "ignored" and bool(e.get("order", false))), "the dropped one is reported ignored")
	# Orders and casts in one breath, and the Gasket / "cast" collision both ways.
	evs = _run(_inc(), [[1.0, "rebar go cast corn", true]])
	eq(_order_events(evs), ["rebar go"], "an order and a cast: the order")
	eq(_casts(evs).size(), 1, "... and the cast")
	eq(_say("gasket go"), [], "Gasket is not the trigger: no cast")
	eq(_say("gasket heal"), [], "gasket heal: no cast in loose")
	eq(_orders_of("cast heal"), [], "cast heal: no order")
	eq(_orders_of("cast go"), [], "cast go: no order (cast is not a name)")
	# Orders off: nothing.
	eq(_orders_of("rebar go", {"orders": false}), [], "orders off")
	# The floor's own employees' names (VoiceCaster.set_order_names).
	eq(_orders_of("marguerite go"), [], "a name the floor does not have: nothing")
	eq(_orders_of("Marguerite go", {"order_names_extra": ["marguerite", "gary"]}), ["marguerite go"], "the floor's employee by name")
	eq(_orders_of("garry follow", {"order_names_extra": ["gary"]}), ["gary follow"], "a name already listed keeps its aliases")
	# The recognizer's vocabulary: the order hotwords only when set.
	eq(_inc().vocabulary().size(), 1 + SPELLS.size(), "no order hotwords by default")
	check(_inc({"order_hotwords": ["rebar", "go"]}).vocabulary().has("rebar"), "order hotwords when set")


## Twelve cards (trigger + eleven spells) in a 3-column grid: four rows, and a long
## "sound-alike 'headacles'" caption must not push the grid past the 400 px panel.
func _test_panel_cards() -> void:
	var caster := VoiceCaster.new()
	caster.use_mic = false
	caster.use_saved_settings = false
	caster.persist_settings = false
	caster.voice_log.enabled = false
	add_child(caster)
	caster.start(VoiceCaster.default_spells())
	var panel := VoiceDebugPanel.new()
	panel.toggle_with_f1 = false
	add_child(panel)
	panel.attach(caster)
	eq(panel._cards.size(), 12, "panel has trigger + eleven spell cards")
	eq(panel._card_grid.columns, 3, "three columns")
	eq(int(ceil(float(panel._cards.size()) / float(panel._card_grid.columns))), 4, "four rows")
	var names: Array = []
	for c in panel._cards:
		names.append(str(c["word"]))
	check(names.has("tentacles") and names.has("teeth"), "tentacles and teeth cards exist: %s" % str(names))
	for i in panel._cards.size():
		panel._set_card(i, "sound_alike", "headacles tentacles tentacle", 0.7)
		(panel._cards[i]["power"] as Label).text = "ACCIDENTAL 100%"
	var widest: float = panel._card_grid.get_combined_minimum_size().x
	check(widest <= VoiceDebugPanel.PANEL_WIDTH - 20.0, "card grid min width %.0f fits the panel (%.0f)" % [widest, VoiceDebugPanel.PANEL_WIDTH - 20.0])
	panel.queue_free()
	caster.queue_free()


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
