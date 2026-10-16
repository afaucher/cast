class_name Incantation
extends RefCounted
## Pure incantation parsing and power scoring. No audio, no engine nodes, so it
## is unit-testable: feed it speech-recognizer hypotheses and read back events.
##
##   var inc := Incantation.new(PackedStringArray(["heal", "fireball", "armor", "corn"]))
##   inc.vocabulary()                       # words to give the recognizer as hotwords
##   for ev in inc.feed("cast heel", false, t): ...   # streaming partial (or final=true)
##   for ev in inc.tick(t): ...             # call regularly so a lone trigger can time out
##
## Events are Dictionaries:
##   {"kind": "cast", "spell": id, "power": 0..1, "heard": "cast heel",
##    "accidental": bool, "gap": s, "cast_q", "spell_q", "penalty", "t"}
##   {"kind": "fizzle", "heard": "cast hello", "reason": "garbled"}
##   {"kind": "ignored", "spell": id, "heard": "...", "reason": "repeat"}
##
## ---------------------------------------------------------------------------
## DESIGN (measured with Windows TTS clips through the real zipformer-hot model;
## see tests/test_voice_audio.gd, tests/test_voice_triggers.gd and
## tools/make_voice_clips.ps1)
##
## What the recognizer gives us. The streaming zipformer (chunk-16) sends a new
## partial hypothesis every ~0.32 s (audio time), UPPER CASE, and ends an
## utterance (final) after ~0.3 s of silence. A "cast <short pause> heal" is
## therefore often TWO utterances ("CAST" final, then "HEEL"), so the trigger
## word is tracked as a pending cast that outlives utterance boundaries. All
## timing here is the caller's clock (audio time in VoiceCaster), never wall time.
##
## TRIGGER WORD. The player's keyword (default "cast"; see VoiceCaster
## TRIGGER_OPTIONS, or any custom word). Its phrases/near-misses live in
## TUNING.triggers; an unlisted word accepts itself, itself + "s", and (for
## words of 6+ letters) a letter-similar token. A run-together token such as
## "castcorn" or "pickleheel" is split. Measured per option: see the table in the
## test_voice_triggers report; "summon" is often heard as "SOME IN" (an alias).
##
## STRICTNESS (the "accidental invocations fit the theme" rule):
##   strict  the utterance must START with the trigger ("okay cast heal" counts,
##           preamble words aside). "should I cast heal" does nothing.
##   loose   (default) the trigger ANYWHERE followed by a spell word casts
##           ("should I cast heal?" casts). Bare spell words do not cast, except
##           "corn", which fires on any mention including sound-alikes
##           ("corner", "cornbread"). That is a feature.
##   chaos   any spell word anywhere casts, trigger or not.
## Each cast is tagged deliberate or accidental. That label is a HEURISTIC for
## callouts and stats only: it changes no power, cooldown or anything mechanical.
## It is an explainable score (TUNING.accidental) from these signals, all logged
## in the event's `signals` and `why`:
##   trigger present at all (a bare "corn"/chaos cast has none)      +0.60
##   trigger mid-sentence rather than first word of the utterance    +0.50
##     (minus 0.20 when a pause precedes it: a fresh phrase. A real 0.3 s pause
##      reads as ~0.9 s of recognition time between the words, because each
##      word already lags the previous one by 0.3 to 0.6 s)
##   sound-alike instead of exact/homophone match                    +0.10
##   utterance longer than 3 words                                   +0.04 per word (max 0.30)
## accidental = score >= 0.5. "cast heal" scores 0; "should I cast heal" 0.54;
## "corn on the cob" 0.64. Example `why`: "no trigger, sound-alike 'corner', 9 words".
##
## Measured: the model hears "cast" reliably (all casts, both voices, TTS rates
## -3..+3, plus the fast run-together "CASTCORN"). It writes "HEEL" for "heal"
## every time even with the hotword boost, so heel/he'll are exact. "fireball" is
## "FIREBALL", or "FIRE BALL" when spoken apart ("fire bowl" is a near miss).
##
## POWER = cast_q * spell_q * gap_factor * (1 - extras), in (0, 1]:
##   cast_q, spell_q  quality of the matched words (tables below; 1.0 exact or
##                    homophone, down to ~0.6 for a near miss).
##   gap_factor       "fluency": 1.0 while the spell word is recognized within
##                    `gap_free` of the trigger, falling linearly to `gap_floor`
##                    at `window`; later than that the phrase is broken.
##                    These are recognition-time deltas, not pauses: a clean
##                    "cast armor" already measures 0.3 to 0.65 s (word length +
##                    0.32 s chunking), a 0.3 s pause ~1.0 s, 0.7 s ~1.6 s,
##                    1.2 s ~1.9 s. The design doc's "reduce past 0.25 s, break
##                    past 0.7 s" therefore maps to gap_free 0.9 / window 1.7.
##   extras           each other word in the utterance costs `word_penalty`
##                    (fillers / 1-2 letter noise `filler_penalty`), capped at
##                    `penalty_cap` ("okay cast heal" is 96%; accidents in
##                    chatter are weaker for the same reason).
## Below `fizzle_below` the cast fizzles ("too_garbled"). A trigger-started
## utterance followed by something spell-ish that did not match fizzles
## ("garbled"), by another word ("unknown_spell"), or by nothing until `window`
## runs out ("no_spell"). A trigger buried in chatter is silent. A plain miss
## (nothing recognized) emits nothing: the game must not spend a cooldown on it.
##
## STREAMING AND DEDUPE. Exact matches (quality >= early_min_q) fire on the
## first partial that contains them (the cast fires about when the voice
## stops). Near misses and bare/mention matches wait for the final so trailing
## words can still count (and "corn" may still turn into "corner"). Tokens used
## by a cast are remembered per utterance (a partial followed by its final, or
## "cast corn corn", never fires twice), and the same spell cannot fire again
## within `repeat_lockout` seconds (reported as an "ignored" event); a deliberate
## repeat after 1 s works. "fire" waits for "ball".
## ---------------------------------------------------------------------------

## Every tunable in one place. Override per instance via the second argument.
const TUNING := {
	"trigger": "cast",
	# "strict" | "loose" | "chaos" (see above).
	"strictness": "loose",
	# Recognition-time budget from the trigger to the spell word (seconds).
	"window": 1.7,
	# Gap (recognition-time) that costs nothing, then linear to gap_floor at window.
	"gap_free": 0.9,
	"gap_floor": 0.5,
	# Words allowed between the trigger and the spell word ("cast the heal").
	"max_between": 3,
	# Extra-word costs.
	"filler_penalty": 0.02,
	"word_penalty": 0.05,
	"penalty_cap": 0.25,
	# Final power below this fizzles.
	"fizzle_below": 0.45,
	# Matches at or above this quality may fire on a streaming partial.
	"early_min_q": 0.95,
	# Same spell cannot fire again sooner than this (seconds).
	"repeat_lockout": 1.0,
	# A partial hypothesis silent for this long starts a new utterance.
	"utterance_gap": 3.0,
	# Letter similarity (1 - edit distance / length) that counts as "spell-ish".
	"spellish_sim": 0.6,
	# Fuzzy trigger match (words of 6+ letters only) and its quality.
	"fuzzy_trigger_sim": 0.8,
	"fuzzy_trigger_q": 0.85,
	# Bare (no trigger) matches need at least this quality ...
	"bare_min_q": 0.85,
	# ... except the "mention" spells, which also accept any token starting with
	# the spell word (cornbread) at this quality.
	"mention_spells": ["corn"],
	"mention_prefix_q": 0.65,
	# Accidental-invocation label (a heuristic score; see the header).
	"accidental": {
		"threshold": 0.5, "no_trigger": 0.6, "mid_trigger": 0.5,
		"fresh_pause": -0.2, "fresh_pause_s": 0.9,
		"sound_alike": 0.1, "free_words": 3, "per_word": 0.04, "words_cap": 0.3,
	},
	# Trigger word -> {phrase: quality}. Phrases are space-separated tokens.
	"triggers": {
		"cast": {
			"cast": 1.0, "caste": 1.0, "kast": 1.0, "casts": 0.95,
			"cass": 0.85, "cats": 0.8, "cost": 0.75, "cash": 0.65,
		},
		"summon": {"summon": 1.0, "some in": 0.9, "summons": 0.95, "summoned": 0.9},
		"pickle": {"pickle": 1.0, "pickles": 0.95},
		"magic": {"magic": 1.0},
		"conjure": {"conjure": 1.0, "conjured": 0.9},
		"invoke": {"invoke": 1.0, "invoked": 0.9},
		"presto": {"presto": 1.0},
	},
	# Words that cost only filler_penalty (tokens of 1-2 letters count too).
	"fillers": [
		"uh", "um", "er", "ah", "the", "a", "an", "please", "now", "okay", "ok",
		"and", "then", "so", "hey", "to", "on", "me", "my", "i", "oh", "just",
	],
	# Words that may precede the trigger and still make it the start of an
	# incantation (a lone letter counts too: "okay" is heard as "O K").
	"preamble": ["okay", "ok", "please", "now", "uh", "um", "er", "ah", "hey", "so", "then", "and", "alright", "right", "oh"],
	# spell id -> {phrase: quality}. A spell id missing here accepts its own name.
	"spells": {
		"heal": {
			"heal": 1.0, "heel": 1.0, "he'll": 1.0, "heals": 0.9, "healing": 0.85,
			"healer": 0.8, "eel": 0.8, "hail": 0.7, "hill": 0.6,
		},
		"fireball": {
			"fireball": 1.0, "fire ball": 1.0, "fireballs": 0.9, "fire balls": 0.9,
			"fire bowl": 0.9, "fire bull": 0.85, "fire bald": 0.85, "fire ball's": 0.9,
			"fire": 0.7,
		},
		"armor": {
			"armor": 1.0, "armour": 1.0, "armer": 0.9, "arm or": 0.9, "arm er": 0.9,
			"armored": 0.85, "armory": 0.8,
		},
		"corn": {
			"corn": 1.0, "korn": 0.9, "corns": 0.9, "corner": 0.75, "corners": 0.7,
			"corny": 0.75, "cornet": 0.7, "kern": 0.6, "cord": 0.6,
		},
	},
}

const STRICTNESS := ["strict", "loose", "chaos"]

var _cfg: Dictionary
var _spell_ids: PackedStringArray
var _phrases: Array = []        # spell phrases [{spell, toks, q}], longest then best first
var _trig_phrases: Array = []   # trigger phrases [{toks, q}], longest first
var _trigger := "cast"
var _strictness := "loose"
var _fillers: Dictionary = {}
var _preamble: Dictionary = {}

# Current utterance (reset by each final).
var _serial := 0
var _toks: PackedStringArray = PackedStringArray()
var _tok_t: Array[float] = []
var _utt_last_t := -1e9
var _consumed := -1             # token indexes <= this were used by a fired cast
var _spent: Dictionary = {}     # trigger token idx -> true once resolved this utterance

# The trigger waiting for its spell word; outlives utterances. Empty = none.
# keys: utt, idx, n, t, q, lead_pen, at_start, after (Array), after_prev
var _pending: Dictionary = {}
var _last_fire: Dictionary = {}
var _last_final_t := -1e9


func _init(spell_ids: PackedStringArray = PackedStringArray(["heal", "fireball", "armor", "corn"]), overrides: Dictionary = {}) -> void:
	_cfg = TUNING.duplicate(true)
	for k in overrides:
		_cfg[k] = overrides[k]
	_spell_ids = spell_ids
	_trigger = str(_cfg["trigger"]).to_lower().strip_edges()
	_strictness = str(_cfg["strictness"])
	if not STRICTNESS.has(_strictness):
		_strictness = "loose"
	for f in _cfg["fillers"]:
		_fillers[str(f)] = true
	for w in _cfg["preamble"]:
		_preamble[str(w)] = true
	_build_trigger_phrases()
	var table: Dictionary = _cfg["spells"]
	for id in spell_ids:
		var entries: Dictionary = table.get(id, {id: 1.0})
		for phrase in entries:
			var q: float = entries[phrase]
			_phrases.append({"spell": id, "toks": PackedStringArray(str(phrase).split(" ")), "q": q})
	_phrases.sort_custom(_longest_first)


static func _longest_first(a: Dictionary, b: Dictionary) -> bool:
	var la: int = (a["toks"] as PackedStringArray).size()
	var lb: int = (b["toks"] as PackedStringArray).size()
	if la != lb:
		return la > lb
	return float(a["q"]) > float(b["q"])


func _build_trigger_phrases() -> void:
	var table: Dictionary = _cfg["triggers"]
	var entries: Dictionary
	if table.has(_trigger):
		entries = table[_trigger]
	else:
		entries = {_trigger: 1.0}
		if not _trigger.ends_with("s"):
			entries[_trigger + "s"] = 0.95
	for phrase in entries:
		_trig_phrases.append({"toks": PackedStringArray(str(phrase).split(" ")), "q": float(entries[phrase])})
	_trig_phrases.sort_custom(_longest_first)


func trigger_word() -> String:
	return _trigger


func strictness() -> String:
	return _strictness


## Words to hand the recognizer as its (hotword-biased) closed vocabulary.
func vocabulary() -> PackedStringArray:
	var out := PackedStringArray([_trigger])
	for id in _spell_ids:
		if not out.has(id):
			out.append(id)
	return out


func config() -> Dictionary:
	return _cfg


## Forget everything (between levels, tests).
func reset() -> void:
	_end_utterance()
	_pending = {}
	_last_fire = {}
	_last_final_t = -1e9


## True while a trigger has been heard and the spell word is still awaited.
func is_pending() -> bool:
	return not _pending.is_empty()


## Feed one hypothesis. `final` marks the end of an utterance. `t` is seconds on
## any monotonic clock the caller keeps (audio time). Returns events.
func feed(text: String, final: bool, t: float) -> Array:
	var events: Array = []
	_expire(t, events)
	if not final and t - _utt_last_t > float(_cfg["utterance_gap"]):
		_end_utterance()
	var tokens := _prepare_tokens(text)
	if tokens.is_empty() and not final:
		return events
	_update_times(tokens, t)
	_utt_last_t = t

	_refresh_pending(tokens)
	if not _pending.is_empty() and int(_pending["utt"]) != _serial:
		# Trigger from an earlier utterance: keep collecting what follows it.
		_pending["after"] = (_pending["after_prev"] as Array) + _after_words(tokens, 0)
	# A cast may be followed by another in the same breath ("cast heal cast corn").
	for _round in 4:
		if _pending.is_empty() or int(_pending["utt"]) != _serial:
			_register_trigger(tokens)
		if not _pending.is_empty():
			_try_pending_cast(tokens, final, t, events)
			if not _pending.is_empty():
				break  # still waiting for its spell word
		else:
			break
	if _pending.is_empty() and _strictness != "strict":
		_try_bare_cast(tokens, final, t, events)

	if final:
		_finish_utterance(events)
		_last_final_t = t
	return events


## Time passes without new hypotheses (call from _process). Returns events.
func tick(t: float) -> Array:
	var events: Array = []
	_expire(t, events)
	if t - _utt_last_t > float(_cfg["utterance_gap"]) and not _toks.is_empty():
		_end_utterance()
	return events


## For a debug view: how the heard text matches the trigger and each spell.
## Returns [{word, kind, token, q, closeness}] with kind one of "exact",
## "homophone" (same sound, other spelling), "sound_alike" (near miss),
## "wait" (could still become the word) or "" (nothing); closeness 0..1.
func explain(text: String) -> Array:
	var tokens := _prepare_tokens(text)
	var out: Array = []
	out.append(_explain_word(tokens, _trigger, _trig_phrases))
	for id in _spell_ids:
		var ph: Array = _phrases.filter(func(p: Dictionary) -> bool: return p["spell"] == id)
		out.append(_explain_word(tokens, id, ph))
	return out


func _explain_word(tokens: PackedStringArray, word: String, phrases: Array) -> Dictionary:
	var res := {"word": word, "kind": "", "token": "", "q": 0.0, "closeness": 0.0}
	for ph in phrases:
		var pt: PackedStringArray = ph["toks"]
		for i in range(0, tokens.size() - pt.size() + 1):
			var ok := true
			for k in pt.size():
				if tokens[i + k] != pt[k]:
					ok = false
					break
			if ok and float(ph["q"]) > float(res["q"]):
				res["q"] = ph["q"]
				res["token"] = " ".join(pt)
				var q: float = ph["q"]
				res["kind"] = "exact" if " ".join(pt) == word else ("homophone" if q >= 0.95 else "sound_alike")
				res["closeness"] = q
	if res["kind"] != "":
		return res
	var best := 0.0
	for tok in tokens:
		if tok.length() < 2:
			continue
		for ph in phrases:
			var first: String = (ph["toks"] as PackedStringArray)[0]
			if tok.length() < first.length() and first.begins_with(tok) and tok == tokens[tokens.size() - 1]:
				res["kind"] = "wait"
				res["token"] = tok
				res["closeness"] = 0.6
				return res
		var s := similarity(tok, word)
		if s > best:
			best = s
			res["token"] = tok
	res["closeness"] = best if best >= 0.4 else 0.0
	if res["closeness"] == 0.0:
		res["token"] = ""
	return res


# --- tokens ------------------------------------------------------------------

static func tokenize(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for ch in text.to_lower():
		var c: int = ch.unicode_at(0)
		var word_char: bool = (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or ch == "'"
		if word_char:
			cur += ch
		elif cur != "":
			out.append(cur)
			cur = ""
	if cur != "":
		out.append(cur)
	var cleaned := PackedStringArray()
	for tok in out:
		var s: String = tok.lstrip("'").rstrip("'")
		if s != "":
			cleaned.append(s)
	return cleaned


## Tokenize, then split run-together "castcorn" into "cast", "corn".
func _prepare_tokens(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for tok in tokenize(text):
		for p in _split_compound(tok):
			out.append(p)
	return out


func _is_single_trigger(tok: String) -> bool:
	for tp in _trig_phrases:
		if (tp["toks"] as PackedStringArray).size() == 1 and (tp["toks"] as PackedStringArray)[0] == tok:
			return true
	return false


func _split_compound(tok: String) -> PackedStringArray:
	if tok.length() < 6 or _is_single_trigger(tok):
		return PackedStringArray([tok])
	for ph in _phrases:
		if (ph["toks"] as PackedStringArray)[0] == tok:
			return PackedStringArray([tok])
	for k in range(3, tok.length() - 1):
		var a := tok.substr(0, k)
		var b := tok.substr(k)
		if not _is_single_trigger(a):
			continue
		for ph in _phrases:
			if (ph["toks"] as PackedStringArray)[0] == b:
				return PackedStringArray([a, b])
	return PackedStringArray([tok])


func _update_times(tokens: PackedStringArray, t: float) -> void:
	var times: Array[float] = []
	for i in tokens.size():
		if i < _toks.size() and _toks[i] == tokens[i]:
			times.append(_tok_t[i])
		else:
			times.append(t)
	_toks = tokens
	_tok_t = times


func _is_filler(tok: String) -> bool:
	return tok.length() <= 2 or _fillers.has(tok)


func _is_preamble(tok: String) -> bool:
	return (tok.length() == 1 and tok != "i") or _preamble.has(tok)


func _penalty_of(tok: String) -> float:
	return float(_cfg["filler_penalty"]) if _is_filler(tok) else float(_cfg["word_penalty"])


func _after_words(tokens: PackedStringArray, from: int) -> Array:
	var out: Array = []
	for i in range(from, tokens.size()):
		out.append(tokens[i])
	return out


# --- trigger word ------------------------------------------------------------

## Trigger match starting at tokens[i]: {q, n} or {}.
func _trigger_at(tokens: PackedStringArray, i: int) -> Dictionary:
	for tp in _trig_phrases:
		var pt: PackedStringArray = tp["toks"]
		if i + pt.size() > tokens.size():
			continue
		var ok := true
		for k in pt.size():
			if tokens[i + k] != pt[k]:
				ok = false
				break
		if ok:
			return {"q": float(tp["q"]), "n": pt.size()}
	if _trigger.length() >= 6 and tokens[i].length() >= 5 and similarity(tokens[i], _trigger) >= float(_cfg["fuzzy_trigger_sim"]):
		return {"q": float(_cfg["fuzzy_trigger_q"]), "n": 1}
	return {}


## Silence before the trigger, in recognition time: since the previous word of
## this utterance, or since the previous utterance ended.
func _pause_before(idx: int) -> float:
	if idx > 0:
		return _tok_t[idx] - _tok_t[idx - 1]
	if _last_final_t < -1e8:
		return 99.0
	return maxf(0.0, _tok_t[0] - _last_final_t)


func _lead_of(tokens: PackedStringArray, idx: int) -> Dictionary:
	var lead := 0.0
	var at_start := true
	for k in idx:
		lead += _penalty_of(tokens[k])
		if not _is_preamble(tokens[k]):
			at_start = false
	return {"lead_pen": lead, "at_start": at_start}


## A pending trigger from this utterance may have been revised by the recognizer.
func _refresh_pending(tokens: PackedStringArray) -> void:
	if _pending.is_empty() or int(_pending["utt"]) != _serial:
		return
	var idx: int = _pending["idx"]
	var m := {} if idx >= tokens.size() else _trigger_at(tokens, idx)
	if m.is_empty():
		_pending = {}
		return
	var lead := _lead_of(tokens, idx)
	_pending["q"] = m["q"]
	_pending["n"] = m["n"]
	_pending["t"] = _tok_t[idx]
	_pending["after"] = _after_words(tokens, idx + int(m["n"]))
	_pending["lead_pen"] = lead["lead_pen"]
	_pending["at_start"] = lead["at_start"]
	_pending["utt_words"] = tokens.size()
	_pending["token"] = " ".join(tokens.slice(idx, idx + int(m["n"])))
	_pending["pause_before"] = _pause_before(idx)


func _register_trigger(tokens: PackedStringArray) -> void:
	for i in tokens.size():
		if i <= _consumed or _spent.has(i):
			continue
		var m := _trigger_at(tokens, i)
		if m.is_empty():
			continue
		var lead := _lead_of(tokens, i)
		if _strictness == "strict" and not bool(lead["at_start"]):
			continue
		_pending = {
			"utt": _serial, "idx": i, "n": m["n"], "t": _tok_t[i], "q": m["q"],
			"lead_pen": lead["lead_pen"], "at_start": lead["at_start"],
			"after": _after_words(tokens, i + int(m["n"])), "after_prev": [],
			"pause_before": _pause_before(i), "utt_words": tokens.size(),
			"token": " ".join(tokens.slice(i, i + int(m["n"]))),
		}
		return


# --- spell word --------------------------------------------------------------

## First spell phrase starting at tokens[j] that may be accepted now, or {}.
func _match_at(tokens: PackedStringArray, j: int, final: bool) -> Dictionary:
	for ph in _phrases:
		var pt: PackedStringArray = ph["toks"]
		var n := pt.size()
		if j + n > tokens.size():
			continue
		var ok := true
		for k in n:
			if tokens[j + k] != pt[k]:
				ok = false
				break
		if not ok:
			continue
		var q: float = ph["q"]
		var last := j + n - 1 == tokens.size() - 1
		if not final:
			if q < float(_cfg["early_min_q"]):
				return {}
			if last and _extendable(pt):
				return {}
		return {"spell": ph["spell"], "q": q, "n": n, "j": j}
	return {}


## Could `toks` still grow into a longer known phrase ("fire" -> "fire ball")?
func _extendable(toks: PackedStringArray) -> bool:
	for ph in _phrases:
		var pt: PackedStringArray = ph["toks"]
		if pt.size() <= toks.size():
			continue
		var same := true
		for k in toks.size():
			if pt[k] != toks[k]:
				same = false
				break
		if same:
			return true
	return false


func _try_pending_cast(tokens: PackedStringArray, final: bool, t: float, events: Array) -> void:
	var same_utt: bool = int(_pending["utt"]) == _serial
	var start := (int(_pending["idx"]) + int(_pending["n"])) if same_utt else 0
	var max_between: int = _cfg["max_between"]
	var hit := {}
	for j in range(start, mini(start + max_between + 1, tokens.size())):
		hit = _match_at(tokens, j, final)
		if not hit.is_empty():
			break
	if hit.is_empty():
		return
	var j: int = hit["j"]
	var e: int = j + int(hit["n"]) - 1
	var delta := maxf(0.0, _tok_t[j] - float(_pending["t"]))
	if delta > float(_cfg["window"]):
		return
	# Extras: every other token seen so far in this utterance, plus the lead.
	var pen: float = float(_pending["lead_pen"]) if not same_utt else 0.0
	var cast_lo: int = int(_pending["idx"]) if same_utt else -1
	var cast_hi: int = cast_lo + int(_pending["n"]) - 1 if same_utt else -1
	for i in tokens.size():
		if i >= j and i <= e:
			continue
		if same_utt and i >= cast_lo and i <= cast_hi:
			continue
		pen += _penalty_of(tokens[i])
	pen = minf(pen, float(_cfg["penalty_cap"]))
	var power := float(_pending["q"]) * float(hit["q"]) * _gap_factor(delta) * (1.0 - pen)
	var heard := _heard_string(tokens, same_utt, e)
	var spell_tok := " ".join(tokens.slice(j, e + 1))
	var words := tokens.size() + (0 if same_utt else int(_pending["utt_words"]))
	var detail := {"cast_q": float(_pending["q"]), "spell_q": float(hit["q"]), "gap": delta, "penalty": pen}
	detail.merge(_label({
		"trigger_present": true, "trigger_first": bool(_pending["at_start"]),
		"pause_before": float(_pending["pause_before"]), "trigger_token": _pending["token"],
		"spell_token": spell_tok, "spell": str(hit["spell"]),
		"cast_q": float(_pending["q"]), "spell_q": float(hit["q"]), "words": words}), true)
	var cast_idx: int = _pending["idx"]
	_pending = {}
	_consumed = e
	_spent[cast_idx] = true
	_resolve(str(hit["spell"]), power, heard, t, detail, events)


func _gap_factor(delta: float) -> float:
	var free: float = _cfg["gap_free"]
	var window: float = _cfg["window"]
	if delta <= free:
		return 1.0
	var u := clampf((delta - free) / maxf(window - free, 0.001), 0.0, 1.0)
	return lerpf(1.0, float(_cfg["gap_floor"]), u)


func _heard_string(tokens: PackedStringArray, same_utt: bool, e: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if same_utt:
		for i in range(int(_pending["idx"]), e + 1):
			parts.append(tokens[i])
	else:
		parts.append(_trigger)
		for i in e + 1:
			parts.append(tokens[i])
	return " ".join(parts)


func _resolve(spell: String, power: float, heard: String, t: float, detail: Dictionary, events: Array) -> void:
	power = clampf(power, 0.0, 1.0)
	var last: float = _last_fire.get(spell, -1e9)
	if t - last < float(_cfg["repeat_lockout"]):
		events.append({"kind": "ignored", "spell": spell, "heard": heard, "reason": "repeat"})
		return
	if power < float(_cfg["fizzle_below"]):
		events.append({"kind": "fizzle", "heard": heard, "reason": "too_garbled", "spell": spell, "power": power})
		return
	_last_fire[spell] = t
	var ev := {"kind": "cast", "spell": spell, "power": power, "heard": heard, "t": t}
	ev.merge(detail, true)
	events.append(ev)


# --- accidental label ---------------------------------------------------------

## Explainable deliberate/accidental score from the signals. Heuristic only.
func _label(sig: Dictionary) -> Dictionary:
	var a: Dictionary = _cfg["accidental"]
	var score := 0.0
	var reasons: PackedStringArray = PackedStringArray()
	var spell_token: String = sig["spell_token"]
	var kind := "exact"
	if spell_token != str(sig["spell"]) or float(sig["cast_q"]) < 0.95:
		kind = "homophone"
	if float(sig["spell_q"]) < 0.95 or float(sig["cast_q"]) < 0.95:
		kind = "sound_alike"
	if not bool(sig["trigger_present"]):
		score += float(a["no_trigger"])
		reasons.append("no trigger")
	elif not bool(sig["trigger_first"]):
		score += float(a["mid_trigger"])
		var fresh := float(sig["pause_before"]) >= float(a["fresh_pause_s"])
		if fresh:
			score += float(a["fresh_pause"])
		reasons.append("trigger mid-sentence" + (" after a pause" if fresh else ""))
	else:
		reasons.append("trigger first")
	if kind == "sound_alike":
		score += float(a["sound_alike"])
		reasons.append("sound-alike '%s'" % spell_token)
	elif kind == "homophone":
		reasons.append("homophone '%s'" % spell_token)
	else:
		reasons.append("exact")
	var words: int = sig["words"]
	var extra := maxi(0, words - int(a["free_words"]))
	score += minf(float(extra) * float(a["per_word"]), float(a["words_cap"]))
	reasons.append("%d word%s" % [words, "" if words == 1 else "s"])
	var signals := sig.duplicate()
	signals["kind"] = kind
	return {
		"accidental": score >= float(a["threshold"]), "accidental_score": score,
		"signals": signals, "why": ", ".join(reasons),
	}


# --- no trigger: mentions (loose: corn; chaos: every spell) --------------------

## The bare spell word at tokens[j...] under the current strictness, or {}.
func _bare_match(tokens: PackedStringArray, j: int) -> Dictionary:
	var min_q: float = _cfg["bare_min_q"]
	var mention: Array = _cfg["mention_spells"]
	for ph in _phrases:
		var pt: PackedStringArray = ph["toks"]
		if j + pt.size() > tokens.size():
			continue
		var ok := true
		for k in pt.size():
			if tokens[j + k] != pt[k]:
				ok = false
				break
		if not ok:
			continue
		var allowed: bool = _strictness == "chaos" or mention.has(ph["spell"])
		if allowed and float(ph["q"]) >= min_q:
			return {"spell": ph["spell"], "q": ph["q"], "n": pt.size(), "j": j}
	for id in mention:
		if _spell_ids.has(id) and tokens[j].begins_with(str(id)) and tokens[j].length() <= str(id).length() + 6:
			return {"spell": id, "q": float(_cfg["mention_prefix_q"]), "n": 1, "j": j}
	return {}


func _try_bare_cast(tokens: PackedStringArray, final: bool, t: float, events: Array) -> void:
	if not final:
		return  # wait for the whole utterance: extras count, "corn" may become "corner"
	for j in tokens.size():
		if j <= _consumed:
			continue
		var hit := _bare_match(tokens, j)
		if hit.is_empty():
			continue
		var e: int = j + int(hit["n"]) - 1
		var pen := 0.0
		for i in tokens.size():
			if i < j or i > e:
				pen += _penalty_of(tokens[i])
		pen = minf(pen, float(_cfg["penalty_cap"]))
		_consumed = e
		var heard := " ".join(tokens.slice(j, e + 1))
		var detail := {"cast_q": 1.0, "spell_q": float(hit["q"]), "gap": 0.0, "penalty": pen}
		detail.merge(_label({
			"trigger_present": false, "trigger_first": false, "pause_before": 0.0,
			"trigger_token": "", "spell_token": heard, "spell": str(hit["spell"]),
			"cast_q": 1.0, "spell_q": float(hit["q"]), "words": tokens.size()}), true)
		_resolve(str(hit["spell"]), float(hit["q"]) * (1.0 - pen), heard, t, detail, events)
		return


# --- utterance and trigger lifetime --------------------------------------------

func _finish_utterance(events: Array) -> void:
	if not _pending.is_empty():
		var same_utt: bool = int(_pending["utt"]) == _serial
		var after: Array = _pending["after"]
		var meaningful := after.filter(func(w: String) -> bool: return not _is_filler(w))
		if bool(_pending["at_start"]):
			if not meaningful.is_empty():
				_fizzle_pending(events)  # "cast away": said in one breath, nothing matched
			elif same_utt:
				_pending["after_prev"] = (_pending["after_prev"] as Array) + after
			else:
				_pending["after_prev"] = after
		elif same_utt and not after.is_empty():
			_pending = {}  # chatter that merely contains the trigger word
	_end_utterance()


func _end_utterance() -> void:
	_serial += 1
	_toks = PackedStringArray()
	_tok_t = []
	_consumed = -1
	_spent = {}
	_utt_last_t = -1e9


func _expire(t: float, events: Array) -> void:
	if _pending.is_empty():
		return
	if t - float(_pending["t"]) <= float(_cfg["window"]):
		return
	if bool(_pending["at_start"]):
		_fizzle_pending(events)
	else:
		_pending = {}


func _fizzle_pending(events: Array) -> void:
	var after: Array = _pending["after"]
	var reason := "no_spell"
	var meaningful := after.filter(func(w: String) -> bool: return not _is_filler(w))
	if not meaningful.is_empty():
		reason = "unknown_spell"
		for w in meaningful:
			if _spellish(str(w)):
				reason = "garbled"
				break
	var heard := _trigger
	if not after.is_empty():
		heard += " " + " ".join(PackedStringArray(after))
	if int(_pending["utt"]) == _serial:
		_spent[int(_pending["idx"])] = true
	_pending = {}
	events.append({"kind": "fizzle", "heard": heard, "reason": reason})


## Does `tok` look like a mangled spell word (letters close, or a clear prefix)?
func _spellish(tok: String) -> bool:
	if tok.length() < 2:
		return false
	var thresh: float = _cfg["spellish_sim"]
	for ph in _phrases:
		for w in (ph["toks"] as PackedStringArray):
			if w.length() < 3:
				continue
			if w.begins_with(tok) and tok.length() < w.length():
				return true
			if similarity(tok, w) >= thresh:
				return true
	return false


## 1 - edit distance / longer length, in 0..1.
static func similarity(a: String, b: String) -> float:
	var n := a.length()
	var m := b.length()
	if n == 0 and m == 0:
		return 1.0
	var prev: Array[int] = []
	var cur: Array[int] = []
	for j in m + 1:
		prev.append(j)
		cur.append(0)
	for i in range(1, n + 1):
		cur[0] = i
		for j in range(1, m + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			cur[j] = mini(mini(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost)
		var tmp := prev
		prev = cur
		cur = tmp
	return 1.0 - float(prev[m]) / float(maxi(n, m))
