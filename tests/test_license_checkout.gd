extends TestCase
## The license requisition (SpellPicker): one component, two variants. FORM 15 "License requisition" (white) at a contract
## start and FORM 15-S "Supplemental requisition" (canary) for a player joining a job in progress, each with FORM 15-A, a
## separate "Spec sheet" page beside it that follows the focused line. Covers: the typed header (job number, client, who
## it is issued to; 15-S also the floor), the catalog as line items built from SpellBook.ids()
## (nothing hard-coded per spell; the red tick is the only record of a pick), the printed limit once, no instructional or
## state copy, Up / Down navigation, scrolling past MAX_LINES, signing "Requested by" with the red name stamp before
## `picked`, and a layout that fits 1600 x 900 canvas units (1280 x 720) and 1600 x 1000 (the Steam Deck's 1280 x 800)
## with the real nine spells, 24 and 100 made-up ones.

const CANVAS_W := 1600.0
const CANVAS_H := 900.0
const DECK_H := 1000.0
## Copy the old checkout carried that the requisition must not: state counters, instructions, key bindings.
const BANNED := ["picks", "your picks", "chosen", "enter to", "tick this", "give it back", "you will say", "licensed (", "go", "start"]


func setup() -> void:
	timeout_sec = 120.0
	await _real_spells()
	await _signing()
	await _long_list()
	await _empty_and_tiny_lists()
	await _requisition()
	await _fit_windows()
	finish()


func _open(ids: Array[String] = [], meta: Dictionary = {}) -> SpellPicker:
	var p := SpellPicker.new()
	if not ids.is_empty():
		p.spell_ids = ids
		p.spell_meta = meta
	p.job = {"job": "08137-PR", "client": "Hollis-Crane Continuity Holdings"}
	p.signer = "Duckbob"
	add_child(p)
	return p


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _focus_step(from: Control, side: Side) -> Control:
	return from.find_valid_focus_neighbor(side)


## Every Label's text under `n` (what is printed or typed on a page).
func _texts(n: Node) -> Array[String]:
	var out: Array[String] = []
	for l in n.find_children("*", "Label", true, false):
		out.append((l as Label).text)
	return out


## Both pages fit: their laid-out rects are no bigger than the canvas (`placed`: the picker fills a canvas-sized holder at
## the origin, so they must also sit inside it).
func _fits(p: SpellPicker, w: float, h: float, what: String, placed: bool = false) -> void:
	var a := p._sheet.get_global_rect()
	var b := p._spec.get_global_rect()
	var both := a.merge(b)
	check(both.size.x <= w and both.size.y <= h - 50.0, "%s: both pages fit %d x %d (%s)" % [what, int(w), int(h), str(both.size)])
	if placed:
		check(both.position.x >= 0.0 and both.end.x <= w and both.position.y >= 0.0 and both.end.y <= h, "%s: and sit inside it (%s)" % [what, str(both)])
	check(a.end.x <= b.position.x, "%s: the spec sheet lies beside the requisition, not on it" % what)


func _real_spells() -> void:
	var p := _open()
	await frames(4)
	var ids := SpellBook.ids()
	eq(ids.size(), 9, "the real catalog has nine spells")
	eq(p.offered(), ids, "the picker offers exactly SpellBook.ids(), in order")
	eq(p._lines.size(), 9, "one line item per spell")
	for i in ids.size():
		var line: RequisitionLine = p._lines[i]
		eq(line.spell_id, ids[i], "line %d is %s" % [i + 1, ids[i]])
		eq(line.text, SpellBook.spell_name(ids[i]).to_upper(), "its name is the spell's")
		eq(line.component, SpellBook.component_name(ids[i]), "its component column")
		eq(line.cooldown, "%d s" % int(SpellBook.cooldown_of(ids[i])), "its cooldown column")
		check(line.swatch == SpellBook.color_of(ids[i]), "its colour tag is the spell's colour")
		check(not line.ticked(), "nothing ticked yet")
	check(p.find_children("*", "LicenseCard", true, false).is_empty(), "no licence cards: line items")

	# FORM 15: the title, the carbon, the typed header.
	var h := p._sheet.header
	eq(h.form_no_label.text, "15", "FORM 15")
	eq(h.title_label.text, "LICENSE REQUISITION", "titled License requisition")
	check(p._sheet.carbon == FormTheme.carbon("white"), "on white")
	eq(h.copy_label.text, "JOB #", "the copy box is the job number (printed caption)")
	eq(h.copy_value.text, "08137-PR", "... typed")
	eq(p._fields.keys(), ["client", "issued_to"], "FORM 15 types the client and who it is issued to")
	eq((p._fields["client"] as Label).text, "Hollis-Crane Continuity Holdings", "the client is typed")
	eq((p._fields["issued_to"] as Label).text, "Duckbob", "issued to the player, typed")
	for k: String in p._fields:
		check((p._fields[k] as Label).get_theme_font("font") == FormTheme.typed_font(), "%s is in the typewriter" % k)
	eq(_open_default_signer_name(), JobBoard.signer_name(), "by default it is issued to JobBoard.signer_name()")

	# Say less: the limit once, and none of the old checkout's state or instructions.
	var texts := _texts(p._sheet)
	var limit := SpellPicker.LIMIT_TEXT % SpellPicker.PICK_COUNT
	eq(texts.count(limit), 1, "the limit is printed once (%s)" % limit)
	check(p._limit.get_theme_font("font") != FormTheme.typed_font(), "and printed, not typed")
	for t in texts:
		var words := t.to_lower().split(" ")
		for bad: String in BANNED:
			var found := words.has(bad) if bad in ["go", "start"] else t.to_lower().contains(bad)
			check(not found, "no \"%s\" on the form (%s)" % [bad, t])
	check(not h.company_label.text.to_lower().contains("pick"), "the company line has no instructions")
	for i in 9:
		check(not (p._lines[i] as RequisitionLine).text.contains(str(i + 1)), "no key number printed on line %d" % (i + 1))
	eq(p._sign.caption, "Requested by", "the signature line")
	check(p._sign.disabled and p._sign.signature() == "", "inert and blank before two are ticked")

	# The spec sheet: its own page, its own header, following focus.
	check(p._spec is SpecSheet and p._spec != p._sheet and not p._sheet.is_ancestor_of(p._spec), "the spec sheet is a separate sheet")
	eq(p._spec.header.form_no_label.text, "15-A", "FORM 15-A")
	eq(p._spec.header.title_label.text, "SPEC SHEET", "titled Spec sheet")
	check(p._spec.carbon != p._sheet.carbon, "on its own carbon")
	check(p._lines[0].has_focus(), "the first line has focus")
	eq(p.shown(), "heal", "its spec is shown")
	eq(p._spec.value("copy"), "HEAL", "the spec sheet names the license (typed, in its copy box)")
	eq(p._spec.value("say"), "cast heal", "how to say it, with the player's trigger word")
	eq(p._spec.value("cooldown"), "8 s", "the cooldown")
	eq(p._spec.value("component"), "Grave moss", "the component")
	eq(p._spec.value("desc"), SpellBook.desc_of("heal"), "and the description")
	for l in p._spec.typed_labels():
		check(l.get_theme_font("font") == FormTheme.typed_font() and l.get_theme_font_size("font_size") == SpellPicker.TYPE_SIZE, "one typewriter on the spec sheet (%s)" % l.text)
	p.focus_line(7)
	await frames(2)
	eq(p._spec.value("copy"), "DAMP", "focusing a line swaps the spec sheet")
	check(p._spec.value("desc").contains("soggy"), "damp's description")
	p.set_trigger_word("pickle")
	eq(p._spec.value("say"), "pickle damp", "the trigger word reaches the spec sheet")
	p.set_trigger_word("cast")

	# Navigation: Up / Down (and Tab) run down the lines, then the signature and the back row, and round.
	var l0: RequisitionLine = p._lines[0]
	check(_focus_step(l0, SIDE_BOTTOM) == p._lines[1] and _focus_step(p._lines[4], SIDE_TOP) == p._lines[3], "down and up a line")
	check(_focus_step(l0, SIDE_LEFT) in [l0, null] and _focus_step(l0, SIDE_RIGHT) in [l0, null], "left and right stay")
	check(_focus_step(p._lines[8], SIDE_BOTTOM) == p._sign, "down from the last line goes to the signature")
	check(_focus_step(p._sign, SIDE_BOTTOM) == p._back and _focus_step(p._back, SIDE_BOTTOM) == l0, "then the back row, then round to the top")
	check(_focus_step(l0, SIDE_TOP) == p._back and _focus_step(p._sign, SIDE_TOP) == p._lines[8], "and back up the other way")
	check(l0.find_next_valid_focus() == p._lines[1], "Tab goes line to line")

	# Ticking: pressing a line (Enter / A / click) ticks it, three drop the oldest, two make the signature live.
	p.focus_line(5)
	await frames(2)
	p._lines[5].pressed.emit()
	eq(p.selected(), ["teeth"] as Array[String], "pressing a line ticks it")
	check(p._lines[5].ticked(), "its box has the red tick")
	p._input(_key(KEY_7))
	eq(p.selected(), ["teeth"] as Array[String], "number keys do nothing (no key bindings on the paper)")
	p.toggle("vines")
	p.toggle("coffee")
	eq(p.selected(), ["vines", "coffee"] as Array[String], "a third pick drops the oldest")
	check(not p._lines[5].ticked() and p._lines[6].ticked() and p._lines[8].ticked(), "the ticks follow")
	check(not p._sign.disabled and p._sign.has_focus(), "two picks make the signature live and move focus to it")
	p.toggle("not_a_spell")
	eq(p.selected().size(), 2, "an id the picker does not offer is ignored")
	p.queue_free()
	await frames(2)


func _open_default_signer_name() -> String:
	var p := SpellPicker.new()
	var n := p.signer_name()
	p.free()
	return n


## Signing: the name stamp lands on "Requested by" before `picked`; the hold blocks the form; inert before two.
func _signing() -> void:
	var p := _open()
	await frames(3)
	var got := []
	p.picked.connect(func(s: Array[String]) -> void: got.append(s))
	check(not p.confirm(), "nothing to sign with no ticks")
	p._sign.pressed.emit()
	check(got.is_empty() and p._sign.signature() == "", "pressing the line before two are ticked does nothing")
	p.toggle("heal")
	check(not p.confirm() and p._sign.signature() == "", "one is not enough")
	p.toggle("corn")
	p.sign_hold = 0.25
	p._sign.pressed.emit()   # (Enter or a click on the line)
	eq(p._sign.signature(), "Duckbob", "the player's name is stamped on the signature line")
	eq(p._sign.line.style, "stamp", "with the red name stamp (the job board's)")
	check(p.signed() and got.is_empty(), "the stamp is seen before the form goes in")
	check(not p.confirm(), "a second signature is refused")
	check(not p.void_back(), "a signed form can't be voided")
	p.toggle("armor")
	eq(p.selected(), ["heal", "corn"] as Array[String], "the ticks can't change once it is signed")
	await frames(ceili(0.25 * Engine.physics_ticks_per_second) + 6)
	eq(got, [["heal", "corn"]], "then picked(), in pick order")
	p.queue_free()
	await frames(2)
	# sign_hold 0 submits at once; Enter with nothing focused signs too.
	var q := _open()
	await frames(3)
	q.sign_hold = 0.0
	var got2 := []
	q.picked.connect(func(s: Array[String]) -> void: got2.append(s))
	q.toggle("damp")
	q.toggle("vines")
	q.get_viewport().gui_release_focus()
	q._input(_key(KEY_ENTER))
	eq(got2, [["damp", "vines"]], "Enter with nothing focused signs")
	eq(q._sign.signature(), "Duckbob", "stamped")
	q.queue_free()
	await frames(2)


func _long_list() -> void:
	var ids := SpellPicker.fake_ids(24)
	var meta := SpellPicker.fake_meta(ids)
	var p := _open(ids, meta)
	await frames(4)
	eq(p._lines.size(), 24, "24 lines from a made-up list: nothing is hard-coded per spell")
	eq(p.offered(), ids, "in the order given")
	eq(p._lines[0].text, "AETHER", "names come from the data")
	eq(p._lines[0].component, "Component 1", "components too")
	check(p._scroll.custom_minimum_size.y <= SpellPicker.MAX_LINES * SpellPicker.LINE_H + 0.1, "the list is capped at %d lines" % SpellPicker.MAX_LINES)
	_fits(p, CANVAS_W, CANVAS_H, "24 spells")
	var real_h := p._sheet.size.y
	# The list is taller than its window: it scrolls, and focus keeps the focused line in view.
	var content_h: float = p._list.get_combined_minimum_size().y
	check(content_h > p._scroll.size.y + 1.0, "there is more than fits (%.0f in %.0f)" % [content_h, p._scroll.size.y])
	check(p._scroll.scroll_vertical == 0, "scrolled to the top at first")
	p.focus_line(23)
	await frames(6)
	check(p._scroll.scroll_vertical > 0, "focusing the last line scrolls to it (%d)" % p._scroll.scroll_vertical)
	var line: Control = p._lines[23]
	var top := line.get_global_rect().position.y - p._scroll.get_global_rect().position.y
	check(top >= -1.0 and top + line.size.y <= p._scroll.size.y + 1.0, "and it is inside the window (%.0f)" % top)
	eq(p._spec.value("copy"), "ZENITH", "its spec is shown")
	eq(p._spec.value("say"), "cast zenith", "with its incantation from the data")
	check(_focus_step(p._lines[23], SIDE_BOTTOM) == p._sign, "the last line leads to the signature")
	var walked := 0
	var at: Control = p._lines[0]
	while at != p._sign and walked < 100:
		at = _focus_step(at, SIDE_BOTTOM)
		walked += 1
	eq(walked, 24, "twenty-three steps down the list, then the signature")
	p.focus_line(17)
	await frames(2)
	p._lines[17].pressed.emit()
	p.toggle("spell_02")
	eq(p.selected(), ["spell_18", "spell_02"] as Array[String], "a line past nine is ticked from the keyboard focus")
	check(p._lines[17].ticked() and p._lines[1].ticked() and not p._lines[0].ticked(), "the ticks follow")
	p.sign_hold = 0.0
	var got := []
	p.picked.connect(func(s: Array[String]) -> void: got.append(s))
	check(p.confirm(), "sign")
	eq(got[0], ["spell_18", "spell_02"], "the made-up ids come back")
	p.queue_free()
	await frames(2)
	var big := SpellPicker.fake_ids(100)
	var p2 := _open(big, SpellPicker.fake_meta(big))
	await frames(4)
	eq(p2._lines.size(), 100, "100 lines")
	check(absf(p2._sheet.size.y - real_h) < 2.0, "a hundred spells make the same sheet as 24 (%.0f vs %.0f)" % [p2._sheet.size.y, real_h])
	p2.queue_free()
	await frames(2)


func _empty_and_tiny_lists() -> void:
	var ids := SpellPicker.fake_ids(2)
	var p := _open(ids, SpellPicker.fake_meta(ids))
	await frames(3)
	eq(p._lines.size(), 2, "two lines")
	check(p._scroll.custom_minimum_size.y >= SpellPicker.MIN_LINES * SpellPicker.LINE_H, "a short list keeps the minimum height")
	check(_focus_step(p._lines[1], SIDE_BOTTOM) == p._sign, "navigation works with two")
	p.sign_hold = 0.0
	p.toggle("spell_01")
	p.toggle("spell_02")
	check(p.confirm(), "two licenses are enough")
	p.queue_free()
	await frames(2)
	var one := SpellPicker.fake_ids(1)
	var p1 := _open(one, SpellPicker.fake_meta(one))
	await frames(3)
	eq(p1._lines.size(), 1, "one line")
	p1.toggle("spell_01")
	check(not p1.confirm(), "one is not enough")
	p1.queue_free()
	await frames(2)
	# The back row still cancels (after the void); no job given types dashes.
	var p3 := SpellPicker.new()
	add_child(p3)
	await frames(3)
	eq(p3._sheet.header.copy_value.text, "-", "no job: a dash in the job number")
	eq((p3._fields["client"] as Label).text, "-", "and in the client")
	eq(p3._back.text, "Back to the board", "the back row")
	eq(p3._back.number, "", "with no key printed on it")
	var cancelled := [0]
	p3.cancelled.connect(func() -> void: cancelled[0] += 1)
	p3._back.pressed.emit()
	await after_void()
	eq(cancelled[0], 1, "the back row cancels (after the void)")
	p3.queue_free()
	await frames(2)


## A player joining a job under way files FORM 15-S: the same form on canary, the supplemental header, and the job's
## floor typed in too.
func _requisition() -> void:
	var p := SpellPicker.new()
	p.requisition = {"job": "08323-PR", "client": "Hollis-Crane Continuity Holdings", "floor": "2 of 3"}
	p.back_text = "Leave the crew"
	p.signer = "Duckbob"
	add_child(p)
	await frames(4)
	check(p.supplemental(), "supplemental")
	eq(p._sheet.header.form_no_label.text, "15-S", "a joiner's form is 15-S")
	eq(p._sheet.header.title_label.text, "SUPPLEMENTAL REQUISITION", "titled Supplemental requisition")
	check(p._sheet.carbon == FormTheme.carbon("canary"), "on canary")
	eq(p._sheet.header.copy_value.text, "08323-PR", "the job number in the copy box")
	eq(p._fields.keys(), ["client", "floor", "issued_to"], "15-S types the client, floor and issued to (not the AI it replaces)")
	var typed := _texts(p._sheet)
	for v in ["08323-PR", "Hollis-Crane Continuity Holdings", "2 of 3", "Duckbob"]:
		check(typed.has(v), "the requisition types %s" % v)
	eq(typed.count(SpellPicker.LIMIT_TEXT % SpellPicker.PICK_COUNT), 1, "the same limit, once")
	eq(p._spec.header.form_no_label.text, "15-A", "the same spec sheet beside it")
	eq(p._sign.caption, "Requested by", "the same signature line")
	eq(p._back.text, "Leave the crew", "its back row leaves the crew")
	_fits(p, CANVAS_W, CANVAS_H, "15-S")
	p.sign_hold = 0.0
	var got := []
	p.picked.connect(func(s: Array[String]) -> void: got.append(s))
	p.toggle("heal")
	p.toggle("teeth")
	p._sign.pressed.emit()
	eq(p._sign.signature(), "Duckbob", "15-S is signed with the name stamp too")
	eq(got, [["heal", "teeth"]], "and submits")
	p.queue_free()
	await frames(2)


## Both pages fit 1600 x 900 (1280 x 720) and 1600 x 1000 (the Deck), both variants, real and long lists.
func _fit_windows() -> void:
	for size: Vector2 in [Vector2(CANVAS_W, CANVAS_H), Vector2(CANVAS_W, DECK_H)]:
		var holder := Control.new()
		holder.position = Vector2.ZERO
		holder.size = size
		add_child(holder)
		for variant in ["15", "15-S", "15 x24"]:
			var p := SpellPicker.new()
			if variant == "15-S":
				p.requisition = {"job": "08323-PR", "client": "Hollis-Crane Continuity Holdings", "floor": "2 of 3"}
			if variant.ends_with("x24"):
				p.spell_ids = SpellPicker.fake_ids(24)
				p.spell_meta = SpellPicker.fake_meta(p.spell_ids)
			holder.add_child(p)
			await frames(4)
			_fits(p, size.x, size.y, "FORM %s at %dx%d" % [variant, int(size.x), int(size.y)], true)
			p.queue_free()
			await frames(2)
		holder.queue_free()
		await frames(2)
