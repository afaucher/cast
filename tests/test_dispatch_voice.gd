extends TestCase
## The dispatch headset's voice (scripts/fx/dispatch_voice.gd, DispatchBanner):
## - every line the game can show is enumerated from its own constants, with a stable, non-empty, collision-free key;
## - the performance pass changes only punctuation (the words are the same; first names, titles and numbers are spoken);
## - DispatchBanner.show_line starts the line's clip when it exists, is silent and error-free when it does not, and a new
##   line cuts the previous clip. No rendered clips, speech model or audio files are needed (a test stream stands in).

const FAKE_DIR := "res://tests/no_such_dispatch_dir/"


func setup() -> void:
	timeout_sec = 120.0
	_check_lines()
	_check_spoken()
	_check_keys()
	Sfx.enable_for_tests()
	await _check_banner()
	Sfx.disable_for_tests()
	finish()


func _tone(seconds: float = 1.0) -> AudioStreamWAV:
	var n := int(seconds * 22050.0)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(2000.0 * sin(TAU * 440.0 * float(i) / 22050.0)))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	w.data = bytes
	return w


# --- the lines -------------------------------------------------------------------------------------

func _check_lines() -> void:
	var lines := DispatchVoice.all_lines()
	check(lines.size() > 100, "the game has plenty of dispatch lines (%d)" % lines.size())
	var keys := {}
	var texts := {}
	var kinds := {}
	for l in lines:
		var key := str(l["key"])
		check(key != "" and key.length() == DispatchVoice.KEY_LEN and key.is_valid_hex_number(false), "key %s is %d hex chars" % [key, DispatchVoice.KEY_LEN])
		check(str(l["text"]) != "" and str(l["spoken"]) != "", "line %s has text and something to say" % key)
		check(not keys.has(key), "key %s is unique (%s vs %s)" % [key, str(l["text"]), str(keys.get(key, ""))])
		check(not texts.has(l["text"]), "text is listed once: %s" % l["text"])
		check(not str(l["text"]).contains("{") and not str(l["text"]).contains("%"), "no unfilled slot or format in: %s" % l["text"])
		keys[key] = l["text"]
		texts[l["text"]] = true
		kinds[l["kind"]] = int(kinds.get(l["kind"], 0)) + 1
	for kind: String in ["incident", "floor2", "floor3", "origin_shut", "wipe", "call", "rescue_one", "rescue_many"]:
		check(int(kinds.get(kind, 0)) > 0, "lines of kind %s exist" % kind)
	# every source is covered
	var incidents := 0
	for id: String in ClientArchetype.IDS:
		for ev: Dictionary in (ClientArchetype.get_data(id)["events"] as Array):
			incidents += 1
			check(texts.has(str(ev["dispatch"])), "floor 1 incident listed: %s" % ev["dispatch"])
			for t: String in NoteCopy.DISPATCH[3]:
				check(texts.has(NoteCopy.fill(t, {"origin": ev["origin"]})), "floor 3 line listed for %s" % ev["origin"])
			check(texts.has(NoteCopy.fill(NoteCopy.DISPATCH[2][1], {"origin": ev["origin"]})), "floor 2 origin line listed for %s" % ev["origin"])
	eq(int(kinds["incident"]), incidents, "one floor-1 line per client event")
	for pest: String in ClientArchetype.PEST_NAMES:
		check(texts.has(NoteCopy.fill(NoteCopy.DISPATCH[2][0], {"pest": ClientArchetype.pest_name(pest)})), "floor 2 pest line listed for %s" % pest)
	check(texts.has(NoteCopy.ORIGIN_SHUT), "the origin-gate line is listed")
	for t: String in [NoteCopy.WIPE, NoteCopy.FLOOR_CLEAN, NoteCopy.STAFF_LOST, NoteCopy.YOU_DOWN, NoteCopy.EXIT_DOWN, NoteCopy.EXIT_OUT]:
		check(texts.has(t), "the call is listed: %s" % t)
	for t: String in NoteCopy.RESCUE_ONE:
		check(texts.has(t), "rescue line listed: %s" % t)
		check(not t.contains("%"), "no employee name in a rescue line (2026-10-20): %s" % t)
	eq(int(kinds["rescue_one"]), NoteCopy.RESCUE_ONE.size(), "one clip per rescue line, not one per employee")
	for n in DispatchVoice.RESCUE_COUNTS:
		for t: String in NoteCopy.RESCUE_MANY:
			check(texts.has(t % n), "rescue line listed for %d riders: %s" % [n, t])
	for n in [2, 3, 4]:
		check(DispatchVoice.RESCUE_COUNTS.has(n), "%d riders is covered (a floor has 2-4 employees)" % n)


func _check_keys() -> void:
	var t := "Copy, Pearl (valet) is out."
	eq(DispatchVoice.key_of(t), t.sha256_text().substr(0, 12), "the key is the first 12 hex chars of the text's sha256")
	eq(DispatchVoice.key_of(t), DispatchVoice.key_of(t), "and stable")
	check(DispatchVoice.key_of(t) != DispatchVoice.key_of(t + " "), "any change to the text changes the key")
	eq(DispatchVoice.path_of(t), "res://assets/audio/dispatch/%s.ogg" % DispatchVoice.key_of(t), "the clip is <dir>/<key>.ogg")


# --- the performance pass ----------------------------------------------------------------------------

func _words(s: String) -> PackedStringArray:
	var re := RegEx.create_from_string("[^a-z' ]")
	return re.sub(s.to_lower().replace("-", " "), "", true).split(" ", false)


func _check_spoken() -> void:
	eq(DispatchVoice.spoken("Got Mrs. Bloom. All fingers accounted for."), "Got Missus Bloom! All fingers... accounted for!", "Mrs. is Missus, the confirmation is lively")
	eq(DispatchVoice.spoken("Copy, Mabel is out."), "Copy! Mabel is out!", "a confirmation")
	eq(DispatchVoice.spoken("Copy, Pearl (valet) is out."), "Copy! Pearl is out!", "first name only, the role dropped")
	eq(DispatchVoice.spoken("Nigel (Henchman 4) just walked past my desk."), "Nigel just walked past my desk!", "the henchman number is part of the role")
	eq(DispatchVoice.spoken("Mr. Bloom (accounts) is topside and asking for a lawyer."), "Mister Bloom is topside... and asking for a lawyer!", "Mr. is Mister")
	eq(DispatchVoice.spoken("Copy, Unit #4 is out."), "Copy! Unit number four is out!", "numbers are words")
	eq(DispatchVoice.spoken("Headcount up by 3."), "Headcount up by three!", "a count as a word")
	eq(DispatchVoice.spoken("Copy, 2 staff out."), "Copy! Two staff out!", "a count first in the line")
	eq(DispatchVoice.number_words(21), "twenty-one", "numbers up to 99 and beyond")
	eq(DispatchVoice.spoken(NoteCopy.ORIGIN_SHUT), "The origin gate is shut! The site calms down... The invoice does not!", "the origin-gate line")
	for l in DispatchVoice.all_lines():
		var text := str(l["text"])
		var say := str(l["spoken"])
		eq(say, DispatchVoice.spoken(text), "spoken is deterministic: %s" % text)
		eq(_words(say), _words(DispatchVoice.normalize(text)), "same words once normalized: %s -> %s" % [text, say])
		check(not say.contains("(") and not say.contains("#") and not say.contains("Mr.") and not say.contains("Mrs."), "no role, number sign or title mark left: %s" % say)
		check(not RegEx.create_from_string("\\d").search(say), "no digits left: %s" % say)
		check(say.ends_with("!") or say.ends_with("?") or say.ends_with("."), "ends in a mark: %s" % say)
		if str(l["kind"]) == "incident" or str(l["kind"]) == "floor2" or str(l["kind"]) == "floor3":
			check(say.contains("!"), "calls to action are lively: %s" % say)


# --- the banner ----------------------------------------------------------------------------------------

func _check_banner() -> void:
	DispatchVoice.dir = FAKE_DIR
	var banner := DispatchBanner.new()
	add_child(banner)
	var a := "Copy, Mabel is out."
	var b := "Headcount up by 3."
	var c := "No clip was ever rendered for this line."
	# no clip: silent, no player built, no error
	banner.show_line(a, 4.0)
	check(not banner.is_speaking() and banner.voiced == 0, "no clip rendered: the banner is silent")
	eq(banner.get_child_count(), 0, "and builds no player")
	eq(banner.line, a, "but still shows the line")
	# with clips: the line's clip starts
	DispatchVoice.override_stream(a, _tone(2.0))
	DispatchVoice.override_stream(b, _tone(2.0))
	banner.show_line(a, 4.0)
	await frames(2)
	check(banner.is_speaking(), "a rendered clip plays when the line shows")
	eq(banner.voiced, 1, "one clip started")
	eq(str((banner.get_child(0) as AudioStreamPlayer).bus), "UI", "on the UI bus (Master's slider is the only volume)")
	# a new line cuts the previous clip
	banner.show_line(c, 4.0)
	await frames(2)
	check(not banner.is_speaking(), "a new line without a clip cuts the previous clip")
	banner.show_line(a, 4.0)
	await frames(2)
	banner.show_line(b, 4.0)
	await frames(2)
	check(banner.is_speaking(), "a new line with a clip speaks it")
	eq(banner.voiced, 3, "each started once")
	eq(banner.get_child_count(), 1, "one player, reused: the clips never overlap")
	# sounds off (headless default): silent
	Sfx.disable_for_tests()
	banner.show_line(a, 4.0)
	await frames(2)
	check(not banner.is_speaking() and banner.voiced == 3, "sounds off: silent")
	Sfx.enable_for_tests()
	# a real rendered clip (tools/render_dispatch.ps1), when this checkout has them
	DispatchVoice.clear_overrides()
	DispatchVoice.dir = DispatchVoice.DIR
	if ResourceLoader.exists(DispatchVoice.path_of(NoteCopy.ORIGIN_SHUT)):
		banner.show_line(NoteCopy.ORIGIN_SHUT, 6.0)
		await frames(2)
		check(banner.is_speaking(), "the rendered clip for the origin-gate line plays")
	banner.queue_free()
	await frames(2)
	DispatchVoice.clear_overrides()
	DispatchVoice.dir = DispatchVoice.DIR
