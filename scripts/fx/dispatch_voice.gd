class_name DispatchVoice
extends RefCounted
## The dispatch headset's voice: every line DispatchBanner shows has a pre-rendered clip, assets/audio/dispatch/<key>.ogg,
## where <key> is a stable hash of the EXACT banner text (key_of). Cosmetic and local (AGENTS.md rule 6): each machine
## plays its own clip for the line it shows, nothing is sent, and a missing clip just means a silent banner.
##
##   DispatchVoice.key_of("Copy, Pearl (valet) is out.")   # "3f9a..." (12 hex chars)
##   DispatchVoice.all_lines()                              # [{"key", "text", "spoken", "kind"}], from the real constants
##   DispatchVoice.spoken("Got Mr. Bloom. All fingers accounted for.")   # "Got Mister Bloom! All fingers... accounted for!"
##
## The clips are rendered offline by tools/render_dispatch.ps1 (tools/render_dispatch.py: Kokoro TTS, then the walkie
## radio chain) from tools/dispatch_lines.gd's list, which is all_lines() written as JSON. The clips are not in git.
## The banner text itself never changes; `spoken` is only what the voice is given to read: the same words, a first name
## without its "(role)", titles and numbers as words, and punctuation that pushes the read (Kokoro's only lever).

const DIR := "res://assets/audio/dispatch/"
const KEY_LEN := 12
## How many employees can ride out at once (ContractRun clamps each floor to 2-4 employees): RESCUE_MANY's %d.
const RESCUE_COUNTS: Array[int] = [2, 3, 4]

## Where the clips are (tests point it at a folder of their own).
static var dir := DIR
static var _overrides := {}   ## text -> AudioStream (tests)

const _ONES: Array[String] = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
	"twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
const _TENS: Array[String] = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
## Sentences that call for action or confirm one end in "!".
const _ACTION := ["Close ", "Closing ", "Find ", "Bring "]
const _CONFIRM := ["Copy", "Got ", "Headcount ", "One more "]
const _CONFIRM_ANYWHERE := [" is out", " just walked past", " is topside", " staff out", " just came through",
	"All fingers accounted"]


## The stable id of a banner line (the first KEY_LEN hex chars of its sha256).
static func key_of(text: String) -> String:
	return text.sha256_text().substr(0, KEY_LEN)


static func path_of(text: String) -> String:
	return dir.path_join(key_of(text) + ".ogg")


## The clip for a banner line, or null when it was never rendered (the banner then stays silent).
static func stream_of(text: String) -> AudioStream:
	if _overrides.has(text):
		return _overrides[text]
	var path := path_of(text)
	if text == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


## Tests: play `stream` for `text` instead of its file.
static func override_stream(text: String, stream: AudioStream) -> void:
	_overrides[text] = stream


static func clear_overrides() -> void:
	_overrides.clear()


# --- the lines -------------------------------------------------------------------------------------

## Every banner line the game can show, from the real constants (NoteCopy.DISPATCH, ClientArchetype events, NoteCopy.
## ORIGIN_SHUT, NoteCopy.RESCUE_*; no employee names), deduplicated by text: [{"key", "text", "spoken", "kind"}].
## kind: "incident" (floor 1), "floor2", "floor3", "origin_shut", "wipe", "call" (the other one-off calls), "rescue_one",
## "rescue_many".
static func all_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var origins: Array[String] = []
	var incidents: Array[String] = []
	for id: String in ClientArchetype.IDS:
		for ev: Dictionary in (ClientArchetype.get_data(id)["events"] as Array):
			if not origins.has(str(ev["origin"])):
				origins.append(str(ev["origin"]))
			incidents.append(str(ev["dispatch"]))
	var pests: Array[String] = []
	for k: String in ClientArchetype.PEST_NAMES:
		pests.append(ClientArchetype.pest_name(k))
	var values := {"origin": origins, "pest": pests, "incident": incidents}
	for floor_n in range(1, 4):
		var kind := "incident" if floor_n == 1 else "floor%d" % floor_n
		for t: String in NoteCopy.DISPATCH[floor_n]:
			for text in _fills(t, values):
				_add(out, seen, text, kind)
	_add(out, seen, NoteCopy.ORIGIN_SHUT, "origin_shut")
	_add(out, seen, NoteCopy.WIPE, "wipe")
	for t: String in [NoteCopy.FLOOR_CLEAN, NoteCopy.STAFF_LOST, NoteCopy.YOU_DOWN, NoteCopy.EXIT_DOWN, NoteCopy.EXIT_OUT]:
		_add(out, seen, t, "call")
	for t: String in NoteCopy.RESCUE_ONE:
		_add(out, seen, t, "rescue_one")
	for n in RESCUE_COUNTS:
		for t: String in NoteCopy.RESCUE_MANY:
			_add(out, seen, t % n, "rescue_many")
	return out


static func _add(out: Array[Dictionary], seen: Dictionary, text: String, kind: String) -> void:
	if text == "" or seen.has(text):
		return
	seen[text] = true
	out.append({"key": key_of(text), "text": text, "spoken": spoken(text), "kind": kind})


## `template` with every combination of its {slots} filled from `values` (slot -> candidate strings).
static func _fills(template: String, values: Dictionary) -> Array[String]:
	var out: Array[String] = [template]
	for slot in NoteCopy.slots_in(template):
		var next: Array[String] = []
		for t in out:
			for v: String in (values.get(slot, []) as Array):
				next.append(t.replace("{%s}" % slot, v))
		out = next
	return out


# --- the performance pass --------------------------------------------------------------------------

## What the voice reads for a banner line: normalize() then the punctuation pass. Deterministic (a function of the text):
## confirmations and calls to action end in "!", a setup sentence that leads into one is a question or trails off (which of
## the two alternates by the line's key, not by a roll), and a few phrases get an ellipsis. The words never change.
static func spoken(text: String) -> String:
	var sentences := _sentences(normalize(text))
	var trail := key_of(text).hex_to_int() % 2 == 1
	var calls := false
	for s in sentences:
		calls = calls or _is_action(s) or _is_confirm(s)
	var out: Array[String] = []
	for i in sentences.size():
		var body: String = sentences[i].rstrip(".!?")
		var nxt: String = sentences[i + 1] if i + 1 < sentences.size() else ""
		var mark := "."
		if _is_action(body):
			mark = "!"
			for lead: String in ["Close them", "Close the big gate"]:
				body = body.replace(lead + " and ", lead + ", and ")
		elif _is_confirm(body):
			mark = "!"
			if body.begins_with("Copy, "):
				var rest := body.trim_prefix("Copy, ")
				body = "Copy! " + rest.substr(0, 1).to_upper() + rest.substr(1)
			body = body.replace(" and asking for", "... and asking for")
			body = body.replace("All fingers accounted", "All fingers... accounted")
		elif body.begins_with("Some of "):
			mark = "..."
		elif _is_action(nxt):
			mark = "..." if trail else "?"
		elif nxt.begins_with("Some of "):
			mark = "." if trail else "?"
		elif not calls:
			mark = "!" if i == 0 or i == sentences.size() - 1 else "..."   # a flat report: the headline and the sting
		out.append(body.substr(0, 1).to_upper() + body.substr(1) + mark)
	return " ".join(out)


## The text the voice may read: "(role)" dropped, "Mr." / "Mrs." / "Ms." / "Dr." as words, digits as words.
static func normalize(text: String) -> String:
	var t := text
	var re := RegEx.new()
	re.compile("\\s*\\([^)]*\\)")
	t = re.sub(t, "", true)
	for pair: Array in [["Mrs.", "Missus"], ["Mr.", "Mister"], ["Ms.", "Miss"], ["Dr.", "Doctor"]]:
		t = t.replace(str(pair[0]), str(pair[1]))
	t = t.replace("#", "number ")
	re.compile("\\d+")
	var m := re.search(t)
	while m != null:
		t = t.substr(0, m.get_start()) + number_words(int(m.get_string())) + t.substr(m.get_end())
		m = re.search(t, m.get_start() + 1)
	return t.replace("  ", " ")


static func number_words(n: int) -> String:
	if n < 0:
		return "minus " + number_words(-n)
	if n < 20:
		return _ONES[n]
	if n < 100:
		return _TENS[n / 10] + ("" if n % 10 == 0 else "-" + _ONES[n % 10])
	if n < 1000:
		return _ONES[n / 100] + " hundred" + ("" if n % 100 == 0 else " " + number_words(n % 100))
	return str(n)


static func _sentences(t: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("(?<=[.!?])\\s+(?=[A-Z])")
	var start := 0
	for m in re.search_all(t):
		out.append(t.substr(start, m.get_start() - start))
		start = m.get_end()
	out.append(t.substr(start))
	return out


static func _is_action(s: String) -> bool:
	for p: String in _ACTION:
		if s.begins_with(p):
			return true
	return false


static func _is_confirm(s: String) -> bool:
	for p: String in _CONFIRM:
		if s.begins_with(p):
			return true
	for p: String in _CONFIRM_ANYWHERE:
		if s.contains(p):
			return true
	return false
