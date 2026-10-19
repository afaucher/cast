class_name Incantation
extends RefCounted
## Pure incantation parsing and power scoring. No audio, no engine nodes, so it
## is unit-testable: feed it speech-recognizer hypotheses and read back events.
##
##   var inc := Incantation.new(PackedStringArray(["heal", "fireball", "armor", "corn", "tentacles", "teeth", "vines", "damp", "coffee", "chicken"]))
##   inc.vocabulary()                       # words to give the recognizer as hotwords
##   for ev in inc.feed("cast heel", false, t): ...   # streaming partial (or final=true)
##   for ev in inc.tick(t): ...             # call regularly so a lone trigger can time out
##
## Events are Dictionaries:
##   {"kind": "cast", "spell": id, "power": 0..1, "heard": "cast heel",
##    "accidental": bool, "gap": s, "cast_q", "spell_q", "penalty", "t"}
##   {"kind": "fizzle", "heard": "cast hello", "reason": "garbled"}
##   {"kind": "ignored", "spell": id, "heard": "...", "reason": "repeat"}
## And one signal, `trigger_armed(token)`: a trigger word was heard and a cast now waits for its spell word (once per
## trigger, even when the spell word arrives in the same hypothesis; VoiceCaster.trigger_heard, the "cast heard" cue).
##
## ---------------------------------------------------------------------------
## DESIGN (measured with Windows TTS clips through the real zipformer-hot model;
## see tests/test_voice_audio.gd, tests/test_voice_triggers.gd and
## tools/make_voice_clips.ps1)
##
## What the recognizer gives us. The streaming zipformer (chunk-16) sends a new
## partial hypothesis every ~0.32 s (audio time), UPPER CASE, and ends an
## utterance (final) after ~0.3 s of silence. Since 2026-10-17 SpeechGate flushes
## each voice end (docs/design/stt-latency-staggered-streams.md), so the last word
## of a phrase arrives ~0.15 s after the voice stops instead of ~0.6-0.9 s, and a
## pause of 0.1 s or more ends the utterance at once. A "cast <short pause> heal" is
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
##      reads as ~0.9 s of recognition time: the pause plus the trigger word
##      itself, since the trigger is only recognized when the phrase ends)
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
## TENTACLES (5th spell; 9 letters, rare word, hotword-biased like the others).
## Measured with TTS (David + Zira, rates -3..+3, 16 deliberate clips): the model
## writes "TENTACLES"/"TENTACLE" for every clip at rate -3..+2 and in both voices
## (16 of 16 cast, no other spell ever fires, no tentacles from any other spell's
## clips, ~0.5 s after the voice stops). Mishearings, all aliased below 0.85 so
## they cannot fire without the trigger: rate +3 gives "HEADACLES"/"HEADAGLE"
## (0.8/0.75) and a 300 ms pause after "cast" can lose the front half:
## "CA STE ACLES" (alias "acles" 0.75, via the CA+STE+ACLES rejoin and compound
## split). Chatter does not fire it: "attack", "ten tickets", "I can't tackle
## this" are heard as such, "testicles" as "TESTACLES" (hotword pull toward
## -ACLES, NOT aliased), "watch out for the tentacles" only casts in chaos. Not a
## mention word (only corn is). Adding the hotword changed nothing in the
## phantom tests (identical to the 4-spell vocabulary, 0 through the gate).
## ASR RISK: "tentacles" is long and unambiguous, so recall is the best of the
## five; the risk is a fast, clipped voice ("tent-" lost, see rate +3) and the
## pause case above. If it measured badly (untested), "kraken" or "squid" are shorter
## but more confusable ("crack in", "squad"); "tentacle" alone is already accepted.
##
## TEETH (6th spell; one syllable, the shortest and on paper the riskiest word).
## Measured with TTS (David + Zira, rates -3..+3, tests/test_voice_audio.gd plus a one-off
## sweep of 48 clips): the model writes "TEETH" for every "cast teeth" clip. 14 of 14
## (every rate, both voices) fire teeth at 1.00, ~0.8 to 1.0 s after the voice stops (partial
## ladder "CAST CAST TE CAST TEETH"; TE/TEE do nothing). "okay/please cast teeth", "cast teeth
## now" and "cast the teeth" cast (0.93 to 1.00); "cast ... teeth" with a 300/500/800 ms pause
## casts at 1.00/0.97/0.76. "tooth" is also heard exactly (12 of 14 sweep clips, plus the alias below): the rate -1
## David clip lost the trigger ("CA | TO TOOTH") and is simply missed; at rate +3 "cast tooth" is fused to
## "CASTOOTH", which the compound split reads as cast + "ooth" (alias 0.75, the ONLY alias).
## The look-alikes are heard as themselves and are deliberately NOT aliased, because "cast these"
## and "cast tea" are ordinary phrases and a miss is cheaper than a false cast: "these" is "THE SE"
## (alone) or "CAST THESE" (fizzles, "unknown_spell"); "tea" is "TWO"/"T"/"TEA"/"TIT"; "tease",
## "tees", "teen" are "TEAS"/"TIES"/"TEES"/"CASTING"; "teach me" is "TEACH ME" ("cast teach" is
## "garbled", a fizzle). None casts in any strictness. Chatter that really says it ("nice teeth",
## "brush your teeth") is heard as "TEETH" and only casts in chaos (0.90 to 0.95, flagged accidental);
## loose needs the trigger, and teeth is not a mention word (only corn is). The hotword did not create
## phantoms: idle noise through the model with the gate OFF gave 0 utterances, digital silence gave the
## same "HE"/"AND" as before (no TEETH), and the gate leaves 0 either way (tests/test_voice_noise.gd).
## Spell confusion holds both ways (16 of 16 deliberate teeth clips fire teeth and nothing else, and
## no other clip fires it; same for tentacles). ASR RISK: it is short, so a hurried or mumbled
## "cast teeth" in a noisy room is the likeliest to lose its front ("TE" and a vowel) or to meet a
## trigger it fuses with ("summon teeth" is heard as one word, "SEVENTEENTH", every time, so that pairing
## is left out of the trigger clips; "abracadabra" is hopeless anyway).
## If it measured badly on real mics: "cast fangs" (also one syllable, but "fans"/"fines"), "cast
## molar" or "cast dentist" (long and distinctive, the best bet) are the alternatives; "tooth" is
## already accepted.
##
## VINES, DAMP, COFFEE (7th to 9th spells; measured 2026-10-17 with TTS, David + Zira, rates -3/0/+3, through the
## real model with the nine-word vocabulary: tests/test_voice_audio.gd, test_voice_triggers.gd, test_voice_noise.gd).
## Deliberate clips (loose): vines 11 of 11, damp 10 of 10, coffee 10 of 10 fired the right spell and no other, and no
## other clip fired them (0 confusions); latency is the same ~150 ms as the other spells.
## VINES: "VINES" for every clip but one: rate +3 David fuses it, "CASTBINES", which the compound split reads as cast +
## "bines" (alias 0.75). The singular is "VINE", accepted exactly (a rate +3 "cast vine" was once heard as "CAST ONE" and
## is simply missed). The look-alikes are heard as themselves: "wines" is "ONES"/"WINES", "vibes" "VI BES"/"BIBES",
## "fines" "FINES", and "cast wines/vibes/fines/binds" only fizzle ("garbled"). EXCEPT "binds": both voices write it
## as "VINES", so it is a true hearing of the spell word: it casts in chaos only (a bare word needs the trigger in loose).
## DAMP: "DAMP" for every clip, both voices, all rates, power 0.96 to 1.00. The look-alikes are not aliased: "damn"
## is "DAMN"/"DIM", "dam" "DAMN"/"DIM"/"DOWN", "dump" "DUMP", "camp" "CAMP". "damn" is common chatter, but loose needs
## the trigger word ("that was damn good", "goddamn it" never cast) and "cast damn" is not a cast. "damp towel" casts
## damp in chaos only. If real mics often hear "cast damp" as "DAMN", add "damn" at 0.75 (below the bare floor, so chaos
## still ignores it) and accept that "cast damn" then casts.
## COFFEE: Zira writes "COFFEE" every time; David writes "COUGHING" or "COUGH" for 3 of his 5 clips ("cast coffee" at
## rate 0 and +3, "okay cast coffee"), so both are aliased (0.8 / 0.75, power about 0.8, which is why coffee's clean-cast
## bar is 0.75). "copy" is "COPY"/"COP"/"CO PY", never coffee ("cast copy" fizzles). So "cast coughing" IS a cast of
## coffee (a measured mishearing, and rare chatter). "coffee break" and "I need coffee" cast coffee in chaos only.
## Chatter: none of the new words fires in strict or loose without the trigger, and the extra hotwords created no
## phantoms (idle noise and digital silence give the same nothing / "HE" "AND" as with six spells, none through the
## gate). Also measured: "summon vines" is heard as "SUM IN VINES", so "sum in" joined the summon trigger's aliases.
##
## CHICKEN (10th spell; measured 2026-10-18 with TTS, David + Zira, rates -3/0/+3, through the real model with the ten-word
## vocabulary: tests/test_voice_audio.gd). Every deliberate clip (13 of 13: clean, both rates in both voices, "okay / please
## cast chicken", "cast chicken now", "cast chickens", a 300 / 500 ms pause) fired chicken and nothing else, 0.96 to 1.00, about
## 150-300 ms after the voice stops (partial ladder "CAST CHI" / "CAST CHICK" / "CAST CHICKEN"; CHI and CHICK do nothing). No
## other clip fired chicken. "chickens" is accepted exactly. The look-alikes are heard as themselves and NOT aliased: "kitchen"
## is "KITCHEN" ("cast kitchen" fizzles, "unknown_spell"), "chick" is "CHI CK" / "CHICK" ("cast chick" is spell-ish:
## "garbled"), "thicken" is "THICKEN". EXCEPT "check in": Zira writes it "CHICK CHICKEN" and "cast check in" "CAST CHICKEN"
## (David: "CHECK IN", "CAST CHEQUE IN"), a true hearing of the spell word like "binds" for vines: bare it casts in chaos only,
## after the trigger it casts. "don't chicken out" / "watch out for the chicken" cast in chaos only. Not a mention word.
## Adding the hotword: one chaos pass heard David's "fines" as "VI VINES" (it was "FI NES" in the other passes and before),
## so "fines" now counts as heard-as-vines in chaos, like "binds".
##
## VOICE ORDERS (2026-10-19; docs/design/combat-proposals.md 1.0 / 1.8): "<name> <go | attack | follow>" gives an event
## {"kind": "order", "who": name key, "order", "heard", "gap", "at_start", "accidental", "t"}. The name is the trigger (no
## "cast"); the order word must be the very next token, within `order_window` of recognition time (timed from when each
## word's slot first appeared, so a word still being heard, "AT" -> "ATTACK", is not a pause). Finals only: a partial
## "REBAR GO" may still become "REBAR GOES IN". A name that ends an utterance waits `order_window` (from that final) for an
## order word to open the next one. Strict: the name opens the utterance (preamble aside); loose / chaos: anywhere; a bare
## order word never orders anyone. The same order to the same name within `order_lockout` is one order ("ignored").
## Names (`order_names`) are the decided ones plus measured spellings; a name fused with its "go" ("CRUGO", "HENNYGO",
## "WICKOW") is split (`order_fused_go`). Possessives are not names. Spells and orders never share a word, so they never
## interfere; "GASKET" is never heard as the trigger. Measured with tests/test_voice_orders.gd (148 TTS clips, David + Zira):
## 94% of the order clips heard right in loose (97% strict), 0 false orders from 38 chatter clips, 0 casts from order clips,
## 0 orders from test_voice_audio's clips. No order hotwords (`order_hotwords` empty, so the spells' vocabulary is what it
## was): with the names as hotwords it was 96%, without aliases 64%. Details: combat-proposals.md 1.8.
##
## POWER = cast_q * spell_q * gap_factor * (1 - extras), in (0, 1]:
##   cast_q, spell_q  quality of the matched words (tables below; 1.0 exact or
##                    homophone, down to ~0.6 for a near miss).
##   gap_factor       "fluency": 1.0 while the spell word is recognized within
##                    `gap_free` of the trigger, falling linearly to `gap_floor`
##                    at `window`; later than that the phrase is broken.
##                    These are recognition-time deltas, not pauses. With the
##                    gate's flush on voice end (2026-10-17) a fluent "cast armor"
##                    measures 0.04 to 0.54 s, and a pause shows up as the pause
##                    PLUS the spell word (the trigger is flushed when the pause
##                    starts, the spell word when it ends): 0.3 s ~0.65-0.95 s,
##                    0.5 s ~0.9-1.15 s, 0.7-0.8 s ~1.1-1.45 s, 1.2 s ~1.6 s.
##                    gap_free 1.0 / window 1.8 keeps every TTS cast at the power
##                    it had before the flush (clean/rate/sloppy unchanged, the
##                    hesitations within ~0.06, b800 "teeth" +0.16): a 0.3 s
##                    pause is free, 0.5 s costs ~10%, 0.8 s ~25%. (Before the
##                    flush the deltas carried 0.3-0.65 s of chunk lag and the
##                    tuning was gap_free 0.9 / window 1.7.)
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
	"window": 1.8,
	# Gap (recognition-time) that costs nothing, then linear to gap_floor at window.
	"gap_free": 1.0,
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
		"summon": {"summon": 1.0, "some in": 0.9, "sum in": 0.9, "summons": 0.95, "summoned": 0.9},
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
			"healer": 0.8, "eel": 0.8, "hail": 0.7, "hill": 0.6, "ill": 0.6,
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
		# Aliases are measured mishearings only, all below the 0.85 bare-match floor
		# so none can fire without the trigger (see the tentacles note in the header).
		"tentacles": {
			"tentacles": 1.0, "tentacle": 1.0,
			"headacles": 0.8, "headacle": 0.75, "headagle": 0.75, "acles": 0.75,
		},
		# The exact words plus the one measured mishearing, below the 0.85 bare floor (see the TEETH note in the header).
		"teeth": {
			"teeth": 1.0, "tooth": 1.0,
			"ooth": 0.75,
		},
		# vines / damp / coffee: the exact words plus the measured mishearings, all below the 0.85 bare floor
		# (see the VINES / DAMP / COFFEE note in the header).
		"vines": {
			"vines": 1.0, "vine": 1.0,
			"bines": 0.75,
		},
		"damp": {
			"damp": 1.0,
		},
		"coffee": {
			"coffee": 1.0,
			"coughing": 0.8, "cough": 0.75,
		},
		# chicken: the word and its plural (see the CHICKEN note in the header).
		"chicken": {
			"chicken": 1.0, "chickens": 1.0,
		},
	},
	# --- Voice orders (see VOICE ORDERS below) ---
	# Orders on or off (the game turns them on; Incantation on its own parses them too).
	"orders": true,
	# Recognition-time budget from the end of the name to the order word (seconds). Like the spells' gap_free: a fluent
	# "Rebar go" measures 0-0.35 s, a 0.3 s pause (two utterances since the gate's flush) about 0.65-0.95 s.
	"order_window": 1.0,
	# The same order to the same name again sooner than this is one order (the recognizer's double fires).
	"order_lockout": 1.5,
	# Order -> {heard word: quality}. Only the exact words: "goes" / "going" are chatter ("Rebar goes in first").
	# The forms below 1.0 are how the model writes a FINAL order word (measured, both voices: "BEATRICE GIRL", "HECTOR GOAT",
	# "ELSIE GOE", "PEARL FALLOW", "STEVE FOLLOWED"); they count only as the utterance's last word ("Steve followed us here"
	# is chatter).
	"order_words": {
		"go": {"go": 1.0, "goe": 0.9, "goat": 0.9, "girl": 0.9, "got": 0.9},
		"attack": {"attack": 1.0},
		"follow": {"follow": 1.0, "followed": 0.9, "fallow": 0.9},
	},
	# Name key (VoiceOrders resolves it to characters) -> {heard phrase: quality}. The key is the official name; the
	# aliases are the decided ones (combat-proposals.md 1.0) plus the model's measured spellings of each name (VOICE ORDERS;
	# the employees' from tests/probe_voice_names.gd, the one name set: SiteBuilder.STAFF_NAMES / HENCHMAN_NAMES).
	"order_names": {
		"everyone": {"everyone": 1.0, "everybody": 1.0, "every one": 1.0, "every body": 1.0, "all hands": 1.0},
		"crew": {"crew": 1.0, "team": 1.0, "squad": 1.0, "crue": 0.9, "cru": 0.9},
		"hench": {"hench": 1.0, "henchmen": 1.0, "henchman": 1.0, "hedge": 0.8, "hedgeman": 0.9, "hedgemen": 0.9},
		"hench four": {"hench four": 1.0, "hench 4": 1.0, "number four": 1.0, "number 4": 1.0, "hench for": 0.9,
			"henchfore": 0.9, "hencefore": 0.9, "hedgefore": 0.9},
		"rebar": {"rebar": 1.0, "ribar": 0.9, "we bar": 0.9, "ribard": 0.9},
		"wick": {"wick": 1.0, "whit": 0.8, "whig": 0.8, "wig": 0.8},
		"gasket": {"gasket": 1.0},
		# Staff.
		"beatrice": {"beatrice": 1.0}, "mabel": {"mabel": 1.0}, "elsie": {"elsie": 1.0},
		"lionel": {"lionel": 1.0, "lion'll": 0.9, "lion all": 0.9, "lion ll": 0.9, "lion or": 0.8},
		"pearl": {"pearl": 1.0}, "penny": {"penny": 1.0, "henny": 0.9}, "molly": {"molly": 1.0},
		"bloom": {"bloom": 1.0, "mister bloom": 1.0, "mr bloom": 1.0, "blue": 0.8}, "iris": {"iris": 1.0, "iras": 0.9},
		"stan": {"stan": 1.0, "stand": 0.8},
		# Henchmen.
		"gary": {"gary": 1.0, "garry": 1.0, "gerry": 0.9}, "steve": {"steve": 1.0}, "simon": {"simon": 1.0},
		"nigel": {"nigel": 1.0}, "brad": {"brad": 1.0, "bread": 0.9}, "todd": {"todd": 1.0, "tod": 1.0},
		"gordon": {"gordon": 1.0, "gording": 0.9}, "kevin": {"kevin": 1.0, "kavin": 0.9, "cabin": 0.8, "caving": 0.8},
		"craig": {"craig": 1.0, "creek": 0.8, "cre": 0.8}, "keith": {"keith": 1.0},
	},
	# A name run together with its order word ("CRUGO", "WICKOW", "HENNYGO", "BLOOMGOT") ends in one of these: read as "go".
	"order_fused_go": ["go", "ko", "co", "ow", "o", "got", "goe", "ga", "gio", "giot"],
	# Extra words handed to the recognizer as hotwords for the orders (besides the trigger and the spells). Empty: the
	# names and order words are left to the plain model (see VOICE ORDERS for why).
	"order_hotwords": [],
	# More one-word names, each its own key: the floor's employees (VoiceCaster.set_order_names). A word that is already a
	# name or an alias above is skipped.
	"order_names_extra": [],
}

const STRICTNESS := ["strict", "loose", "chaos"]

signal trigger_armed(token: String)

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
var _tok_first: Array[float] = []   # when each token slot first appeared in this utterance (the orders' timing)
var _utt_last_t := -1e9
var _consumed := -1             # token indexes <= this were used by a fired cast
var _spent: Dictionary = {}     # trigger token idx -> true once resolved this utterance

# The trigger waiting for its spell word; outlives utterances. Empty = none.
# keys: utt, idx, n, t, q, lead_pen, at_start, after (Array), after_prev
var _pending: Dictionary = {}
var _armed_key := ""            # "<utterance serial>:<token idx>" of the last trigger_armed (a revised partial re-arms nothing)
var _last_fire: Dictionary = {}
var _last_final_t := -1e9

# Voice orders (see VOICE ORDERS).
var _orders_on := true
var _name_phrases: Array = []   # [{who, toks, q}], longest then best first
var _order_tokens: Dictionary = {}   # heard word -> [order, q]
var _pending_name: Dictionary = {}   # a name that ended the last utterance: {who, t, at_start, token}; its order word may open the next
var _last_order: Dictionary = {}     # "who|order" -> t of the last one fired


func _init(spell_ids: PackedStringArray = PackedStringArray(["heal", "fireball", "armor", "corn", "tentacles", "teeth", "vines", "damp", "coffee", "chicken"]), overrides: Dictionary = {}) -> void:
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
	_build_order_phrases()
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


func _build_order_phrases() -> void:
	_orders_on = bool(_cfg.get("orders", true))
	var names: Dictionary = _cfg.get("order_names", {})
	for who in names:
		var entries: Dictionary = names[who]
		for phrase in entries:
			_name_phrases.append({"who": str(who), "toks": PackedStringArray(str(phrase).split(" ")), "q": float(entries[phrase])})
	# The floor's own employees' names (VoiceCaster.set_order_names: "beatrice", "bloom"), each its own key.
	for extra in (_cfg.get("order_names_extra", []) as Array):
		var w := str(extra).to_lower().strip_edges()
		if w != "" and not w.contains(" ") and not names.has(w) and not _order_tokens_has_name(w):
			_name_phrases.append({"who": w, "toks": PackedStringArray([w]), "q": 1.0})
	_name_phrases.sort_custom(_longest_first)
	var words: Dictionary = _cfg.get("order_words", {})
	for order in words:
		for w in (words[order] as Dictionary):
			_order_tokens[str(w)] = [str(order), float(words[order][w])]


## True when `w` already is a heard form of some name.
func _order_tokens_has_name(w: String) -> bool:
	for ph in _name_phrases:
		if (ph["toks"] as PackedStringArray).size() == 1 and (ph["toks"] as PackedStringArray)[0] == w:
			return true
	return false


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
	if _orders_on:
		for w in (_cfg.get("order_hotwords", []) as Array):
			if not out.has(str(w)):
				out.append(str(w))
	return out


func config() -> Dictionary:
	return _cfg


## True when `tok` (lower case) is a name or an order word of the order grammar (VoiceCaster's fragment rejoin must not
## glue "REBAR" + "GO" into one word).
func is_order_word(tok: String) -> bool:
	if not _orders_on:
		return false
	if _order_tokens.has(tok):
		return true
	for ph in _name_phrases:
		if (ph["toks"] as PackedStringArray)[0] == tok:
			return true
	return false


## Forget everything (between levels, tests).
func reset() -> void:
	_end_utterance()
	_pending = {}
	_last_fire = {}
	_last_final_t = -1e9
	_pending_name = {}
	_last_order = {}


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
		_try_orders(tokens, t, events)
		_finish_utterance(events)
		_last_final_t = t
	return events


## Time passes without new hypotheses (call from _process). Returns events.
func tick(t: float) -> Array:
	var events: Array = []
	_expire(t, events)
	if not _pending_name.is_empty() and t - float(_pending_name["t"]) > float(_cfg["order_window"]):
		_pending_name = {}
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
			for q in _split_order(p):
				out.append(q)
	return out


## A run-together name and order word into the two: "REBARGO", "GASKETATTACK", and the measured fusions of a name with "go"
## ("CRUGO", "CREWO", "HENNYGO", "WICKOW", "BLOOMGOT": order_fused_go).
func _split_order(tok: String) -> PackedStringArray:
	if not _orders_on or tok.length() < 5 or _order_tokens.has(tok) or is_order_word(tok):
		return PackedStringArray([tok])
	var tails: Array = []
	for w: String in _order_tokens:
		tails.append([w, w])
	for w in (_cfg.get("order_fused_go", []) as Array):
		tails.append([str(w), "go"])
	for tail: Array in tails:
		var w: String = tail[0]
		if tok.length() >= w.length() + 3 and tok.ends_with(w):
			var head := tok.substr(0, tok.length() - w.length())
			for ph in _name_phrases:
				var pt: PackedStringArray = ph["toks"]
				if pt.size() == 1 and pt[0] == head:
					return PackedStringArray([head, str(tail[1])])
	return PackedStringArray([tok])


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
	# The orders time a word from when its slot first appeared, whatever it said then ("AT" -> "ATTA" -> "ATTACK" is one word
	# being heard, not a pause).
	while _tok_first.size() < tokens.size():
		_tok_first.append(t)
	_tok_first.resize(tokens.size())
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
		var key := "%d:%d" % [_serial, i]
		if key != _armed_key:
			_armed_key = key
			trigger_armed.emit(str(_pending["token"]))
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


# --- voice orders: "<name> <go | attack | follow>" ---------------------------------

## The name phrase starting at tokens[i]: {who, n, q} or {}.
func _name_at(tokens: PackedStringArray, i: int) -> Dictionary:
	for ph in _name_phrases:
		var pt: PackedStringArray = ph["toks"]
		if i + pt.size() > tokens.size():
			continue
		var ok := true
		for k in pt.size():
			if tokens[i + k] != pt[k]:
				ok = false
				break
		if ok:
			return {"who": ph["who"], "n": pt.size(), "q": ph["q"]}
	return {}


## The order word at tokens[i]: {order, q} or {}.
func _order_at(tokens: PackedStringArray, i: int) -> Dictionary:
	if i >= tokens.size() or not _order_tokens.has(tokens[i]):
		return {}
	var o: Array = _order_tokens[tokens[i]]
	return {"order": o[0], "q": o[1]}


## A whole utterance (a final): every name followed AT ONCE by an order word (nothing between them, at most order_window
## of recognition time apart) is an order. Strict wants the name to open the utterance (preamble aside); loose and chaos
## take it anywhere. A name that ends the utterance waits (order_window) for an order word to open the next one: with the
## gate's flush, "Rebar, go" with a comma's pause is two utterances.
func _try_orders(tokens: PackedStringArray, t: float, events: Array) -> void:
	if not _orders_on:
		_pending_name = {}
		return
	var window: float = _cfg["order_window"]
	var i := 0
	if tokens.is_empty():
		return   # (an empty final keeps a name that is waiting for its order word)
	if not _pending_name.is_empty():
		var o0 := _order_at(tokens, 0)
		var gap0 := _tok_first[0] - float(_pending_name["t"])   # (from the end of the name's utterance to this one's start)
		if not o0.is_empty() and gap0 <= window:
			_fire_order(str(_pending_name["who"]), str(o0["order"]), "%s %s" % [_pending_name["token"], tokens[0]], gap0,
				bool(_pending_name["at_start"]), t, events)
			i = 1
	_pending_name = {}
	while i < tokens.size():
		var nm := _name_at(tokens, i)
		if nm.is_empty():
			i += 1
			continue
		var e: int = i + int(nm["n"])
		var at_start := bool(_lead_of(tokens, i)["at_start"])
		if _strictness == "strict" and not at_start:
			i = e
			continue
		var token := " ".join(tokens.slice(i, e))
		if e >= tokens.size():
			_pending_name = {"who": nm["who"], "t": t, "at_start": at_start, "token": token}
			break
		var o := _order_at(tokens, e)
		var gap := _tok_first[e] - _tok_first[e - 1]
		if not o.is_empty() and float(o["q"]) < 1.0 and e < tokens.size() - 1:
			o = {}   # (a heard-as form, "followed", only as the last word: "Steve followed us here" is chatter)
		if o.is_empty() or gap > window:
			i = e
			continue
		_fire_order(str(nm["who"]), str(o["order"]), "%s %s" % [token, tokens[e]], gap, at_start, t, events)
		i = e + 1


func _fire_order(who: String, order: String, heard: String, gap: float, at_start: bool, t: float, events: Array) -> void:
	var key := "%s|%s" % [who, order]
	if t - float(_last_order.get(key, -1e9)) < float(_cfg["order_lockout"]):
		events.append({"kind": "ignored", "spell": "%s %s" % [who, order], "heard": heard, "reason": "repeat", "order": true})
		return
	_last_order[key] = t
	# (`accidental` is the same heuristic label as a cast's: the name buried mid-sentence. Stats and the log only.)
	events.append({"kind": "order", "who": who, "order": order, "heard": heard, "gap": maxf(gap, 0.0),
		"at_start": at_start, "accidental": not at_start, "t": t})


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
	_tok_first = []
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
