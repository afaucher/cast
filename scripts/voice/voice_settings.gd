class_name VoiceSettings
extends RefCounted
## Persisted voice options (user://settings.cfg, section "voice") plus trigger
## word validation. The game reads these at startup; VoiceCaster applies them
## in start() unless `tuning` already overrides them.
##
##   trigger_word  "cast" (default), one of VoiceCaster.TRIGGER_OPTIONS, or custom
##   strictness    "strict" | "loose" (default) | "chaos"   (see Incantation)

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "voice"
const PRON_DICT := "res://data/pron_dict.txt"

## Everyday words a trigger should not be (it would fire constantly or never
## be told apart from chatter). Warned about, not forbidden.
const COMMON_WORDS := [
	"the", "and", "you", "that", "this", "what", "okay", "yes", "no", "go", "now", "hey",
	"hello", "please", "oh", "well", "just", "like", "come", "look", "here", "there", "get",
	"got", "let", "see", "one", "two", "three", "wait", "stop", "help", "left", "right", "up",
	"down", "back", "over", "on", "in", "it", "is", "to", "a", "i", "we", "he", "she", "they",
	"me", "my", "yeah", "nice", "good", "great", "thanks", "sorry", "cool", "take", "give",
	"use", "need", "want", "think", "know", "say", "do", "did", "can", "will", "have", "has",
]

static var _pron_text := ""
static var _pron_loaded := false


static func defaults() -> Dictionary:
	return {"trigger_word": "cast", "strictness": "loose", "min_voice_db": SpeechGate.DEFAULT_MIN_VOICE_DB}


static func load_settings(path: String = DEFAULT_PATH) -> Dictionary:
	var out := defaults()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return out
	for key in out:
		out[key] = cfg.get_value(SECTION, key, out[key])
	out["trigger_word"] = str(out["trigger_word"]).to_lower().strip_edges()
	if out["trigger_word"] == "":
		out["trigger_word"] = "cast"
	if not Incantation.STRICTNESS.has(str(out["strictness"])):
		out["strictness"] = "loose"
	out["min_voice_db"] = clampf(float(out["min_voice_db"]), -70.0, -10.0)
	return out


## Writes only the keys given, keeping everything else in the file.
static func save_settings(settings: Dictionary, path: String = DEFAULT_PATH) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(path)  # missing file is fine
	var current := defaults()
	for key in current:
		if settings.has(key):
			cfg.set_value(SECTION, key, settings[key])
	return cfg.save(path) == OK


## Check a candidate trigger word.
## Returns {ok: bool, word: String, error: String, warnings: PackedStringArray}.
static func validate_trigger(word: String, spell_ids: Array = ["heal", "fireball", "armor", "corn", "tentacles", "teeth"]) -> Dictionary:
	var w := word.strip_edges().to_lower()
	var res := {"ok": false, "word": w, "error": "", "warnings": PackedStringArray()}
	if w == "":
		res["error"] = "type a word"
		return res
	if " " in w or "\t" in w:
		res["error"] = "must be a single word"
		return res
	for ch in w:
		var c: int = ch.unicode_at(0)
		if not ((c >= 97 and c <= 122) or ch == "'"):
			res["error"] = "letters only (a-z)"
			return res
	if w.length() < 2:
		res["error"] = "too short"
		return res
	if spell_ids.has(w):
		res["error"] = "that is a spell word"
		return res
	res["ok"] = true
	var warnings: PackedStringArray = res["warnings"]
	if w.length() < 4:
		warnings.append("very short word: easily misheard, may fire by accident")
	if COMMON_WORDS.has(w):
		warnings.append("common chatter word: it will trigger constantly in conversation")
	var known := _in_pron_dict(w)
	if known == 0:
		warnings.append("not in the pronunciation dictionary: sound-alike matching will not work, only the exact spelling")
	elif known == -1:
		warnings.append("pronunciation dictionary not found: cannot check this word")
	res["warnings"] = warnings
	return res


## 1 = present, 0 = absent, -1 = no dictionary file.
static func _in_pron_dict(w: String) -> int:
	if not _pron_loaded:
		_pron_loaded = true
		if FileAccess.file_exists(PRON_DICT):
			_pron_text = "\n" + FileAccess.get_file_as_string(PRON_DICT)
	if _pron_text == "":
		return -1
	return 1 if _pron_text.contains("\n" + w + " ") else 0
