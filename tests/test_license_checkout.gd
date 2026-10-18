extends TestCase
## FORM 15, the licence checkout (SpellPicker): a catalog grid of compact licence cards built from
## SpellBook.ids() with nothing hard-coded per spell, 2D keyboard / controller navigation, a detail panel for the
## focused card, number keys 1-9 (optional beyond that), scrolling when the list outgrows the sheet, and a layout
## that still fits 1600 x 900 canvas units (1280 x 720) and 1600 x 1000 (the Steam Deck's 1280 x 800) with a made-up
## list of 24 spells as well as the real nine.

const CANVAS_W := 1600.0
const CANVAS_H := 900.0


func setup() -> void:
	await _real_spells()
	await _long_list()
	await _empty_and_tiny_lists()
	await _requisition()
	finish()


func _open(ids: Array[String] = [], meta: Dictionary = {}) -> SpellPicker:
	var p := SpellPicker.new()
	if not ids.is_empty():
		p.spell_ids = ids
		p.spell_meta = meta
	add_child(p)
	return p


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _focus_step(from: Control, side: Side) -> Control:
	return from.find_valid_focus_neighbor(side)


func _real_spells() -> void:
	var p := _open()
	await frames(4)
	var ids := SpellBook.ids()
	eq(ids.size(), 9, "the real catalog has nine spells")
	eq(p.offered(), ids, "the picker offers exactly SpellBook.ids(), in order")
	eq(p._cards.size(), 9, "one card per spell")
	for i in ids.size():
		var card: LicenseCard = p._cards[i]
		eq(card.spell_id, ids[i], "card %d is %s" % [i + 1, ids[i]])
		eq(card.text, SpellBook.spell_name(ids[i]).to_upper(), "its name is the spell's")
		eq(card.number, str(i + 1), "keys 1-9 are the first nine cards")
		check(card.swatch == SpellBook.color_of(ids[i]), "its colour bar is the spell's colour")
	# It fits both canvases: width and height.
	var min_size := p._sheet.get_combined_minimum_size()
	check(min_size.x <= CANVAS_W and min_size.y <= CANVAS_H - 60.0, "the sheet fits 1600 x 900 (%s)" % str(min_size))
	check(p._sheet.size.y <= CANVAS_H and p._sheet.size.x <= CANVAS_W, "and its laid-out size does (%s)" % str(p._sheet.size))
	eq(p._grid.columns, SpellPicker.COLUMNS, "a three-column catalog")
	check(p._scroll.custom_minimum_size.y >= SpellPicker.MIN_ROWS * SpellPicker.CARD_H, "the grid keeps a minimum height")

	# The first card has the focus and its details are shown; focus changes follow.
	check(p._cards[0].has_focus(), "the first card has focus")
	eq(p._d_name.text, "HEAL", "its details are in the panel")
	check(p._d_say.text.contains("cast heal"), "with how to say it")
	check(p._d_facts.text.contains("COOLDOWN 8") and p._d_facts.text.contains("GRAVE MOSS"), "the cooldown and the component")
	check(p._d_desc.text == SpellBook.desc_of("heal"), "and the description")
	p.focus_card(7)
	await frames(2)
	eq(p._d_name.text, "DAMP", "focusing a card shows its details")
	check(p._d_desc.text.contains("soggy") or p._d_desc.text.contains("fires"), "damp's description")
	p.set_trigger_word("pickle")
	check(p._d_say.text.contains("pickle damp") and (p._cards[7] as LicenseCard).hint.contains("pickle"), "the trigger word reaches the details and the card hints")
	p.set_trigger_word("cast")

	# 2D navigation (the neighbours are what the arrow keys, the D-pad and Tab follow).
	var c0: LicenseCard = p._cards[0]
	check(_focus_step(c0, SIDE_RIGHT) == p._cards[1] and _focus_step(c0, SIDE_BOTTOM) == p._cards[3], "right goes to the next card, down to the one below")
	check(_focus_step(p._cards[4], SIDE_LEFT) == p._cards[3] and _focus_step(p._cards[4], SIDE_TOP) == p._cards[1], "left, up")
	check(_focus_step(c0, SIDE_LEFT) in [c0, null], "left on the first column stays")
	check(_focus_step(p._cards[2], SIDE_RIGHT) in [p._cards[2], null], "right on the last column stays on the row")
	check(_focus_step(p._cards[8], SIDE_BOTTOM) == p._start, "down from the last row goes to Start")
	check(_focus_step(p._start, SIDE_BOTTOM) == p._back and _focus_step(p._back, SIDE_BOTTOM) == c0, "Start, then Back, then round to the first card")
	check(_focus_step(c0, SIDE_TOP) == p._back and _focus_step(p._start, SIDE_TOP) == p._cards[8], "and back up the other way")
	check(c0.find_next_valid_focus() == p._cards[1], "Tab goes card to card")

	# Ticking: Enter on a card, keys 1-9, three picks drop the oldest, two enable Start.
	p.focus_card(5)
	await frames(2)
	p._cards[5].pressed.emit()
	eq(p.selected(), ["teeth"] as Array[String], "pressing a card ticks it")
	check(p._cards[5].button_pressed, "its box shows the X")
	p._input(_key(KEY_7))
	eq(p.selected(), ["teeth", "vines"] as Array[String], "key 7 is the seventh card (vines)")
	p._input(_key(KEY_9))
	eq(p.selected(), ["vines", "coffee"] as Array[String], "a third pick drops the oldest (key 9: coffee)")
	check(not p._start.disabled and p._start.has_focus(), "two picks enable Start and move focus to it")
	var got := []
	p.picked.connect(func(s: Array[String]) -> void: got.append(s))
	check(p.confirm(), "sign")
	eq(got, [["vines", "coffee"]], "the payload is in pick order")
	check(p._d_picks.text.contains("VINES") and p._d_picks.text.contains("COFFEE"), "the picks list shows them")
	p.toggle("not_a_spell")
	eq(p.selected().size(), 2, "an id the picker does not offer is ignored")
	p.queue_free()
	await frames(2)


func _long_list() -> void:
	var ids := SpellPicker.fake_ids(24)
	var meta := SpellPicker.fake_meta(ids)
	var p := _open(ids, meta)
	await frames(4)
	eq(p._cards.size(), 24, "24 cards from a made-up list: nothing is hard-coded per spell")
	eq(p.offered(), ids, "in the order given")
	eq(p._cards[0].text, "AETHER", "names come from the data")
	eq(p._cards[8].number, "9", "the ninth card has key 9")
	eq(p._cards[9].number, "", "later cards have no number key")
	eq(p._cards[23].number, "", "")
	# Layout: bounded height, so it scrolls.
	var rows := ceili(24.0 / float(SpellPicker.COLUMNS))
	eq(rows, 8, "eight rows of three")
	check(p._scroll.custom_minimum_size.y <= SpellPicker.MAX_ROWS * SpellPicker.CARD_H + 0.1, "the grid is capped at %d rows" % SpellPicker.MAX_ROWS)
	var min_size := p._sheet.get_combined_minimum_size()
	check(min_size.x <= CANVAS_W and min_size.y <= CANVAS_H - 60.0, "24 spells still fit 1600 x 900 (%s)" % str(min_size))
	check(p._sheet.size.y <= CANVAS_H, "laid out at %.0f tall" % p._sheet.size.y)
	var real_h := p._sheet.size.y
	# The grid is taller than its window: it scrolls, and focus keeps the focused card in view.
	var content_h: float = p._grid.get_combined_minimum_size().y
	check(content_h > p._scroll.size.y + 1.0, "there is more than fits (%.0f in %.0f)" % [content_h, p._scroll.size.y])
	check(p._scroll.scroll_vertical == 0, "scrolled to the top at first")
	p.focus_card(23)
	await frames(6)
	check(p._scroll.scroll_vertical > 0, "focusing the last card scrolls to it (%d)" % p._scroll.scroll_vertical)
	var card: Control = p._cards[23]
	var top := card.get_global_rect().position.y - p._scroll.get_global_rect().position.y
	check(top >= -1.0 and top + card.size.y <= p._scroll.size.y + 1.0, "and it is inside the window (%.0f)" % top)
	eq(p._d_name.text, "ZENITH", "its details are shown")
	check(p._d_say.text.contains("cast zenith"), "with its incantation from the data")
	# Navigation across rows works the same as with nine.
	check(_focus_step(p._cards[0], SIDE_BOTTOM) == p._cards[3], "down one row")
	check(_focus_step(p._cards[20], SIDE_BOTTOM) == p._cards[23] or _focus_step(p._cards[20], SIDE_BOTTOM) == p._start, "down in the last row")
	check(_focus_step(p._cards[23], SIDE_BOTTOM) == p._start and _focus_step(p._cards[22], SIDE_BOTTOM) == p._start, "the last row leads to Start")
	check(_focus_step(p._cards[22], SIDE_RIGHT) == p._cards[23], "right along a row")
	check(_focus_step(p._cards[23], SIDE_RIGHT) in [p._cards[23], null], "and no running off the end")
	var walked := 0
	var at: Control = p._cards[0]
	while at != p._start and walked < 100:
		at = _focus_step(at, SIDE_BOTTOM)
		walked += 1
	check(at == p._start and walked == 8, "seven steps down the column, then Start (%d)" % walked)
	# Keys 1-9 still work, and ticking any card works with the keyboard alone (Enter on a focused card).
	p._input(_key(KEY_1))
	p._input(_key(KEY_2))
	eq(p.selected(), ["spell_01", "spell_02"] as Array[String], "number keys tick the first nine")
	p.focus_card(17)
	await frames(2)
	p._cards[17].pressed.emit()
	eq(p.selected(), ["spell_02", "spell_18"] as Array[String], "a card past nine is ticked from the keyboard focus")
	check(p._cards[17].button_pressed and not p._cards[0].button_pressed, "the boxes follow")
	check(p._d_picks.text.contains("BRINE") and p._d_picks.text.contains("RUST"), "the picks list names them (%s)" % p._d_picks.text.replace("\n", " | "))
	var got := []
	p.picked.connect(func(s: Array[String]) -> void: got.append(s))
	check(p.confirm(), "sign")
	eq(got[0], ["spell_02", "spell_18"], "the made-up ids come back")
	# The layout of the tall list is no taller than the cap (a 100-spell list would not grow the sheet either).
	p.queue_free()
	await frames(2)
	var big := SpellPicker.fake_ids(100)
	var p2 := _open(big, SpellPicker.fake_meta(big))
	await frames(4)
	eq(p2._cards.size(), 100, "100 cards")
	check(absf(p2._sheet.size.y - real_h) < 2.0, "a hundred spells make the same sheet as 24 (%.0f vs %.0f)" % [p2._sheet.size.y, real_h])
	p2.queue_free()
	await frames(2)


func _empty_and_tiny_lists() -> void:
	# Fewer than the grid is tall: the sheet keeps its minimum height and nothing errors.
	var ids := SpellPicker.fake_ids(2)
	var p := _open(ids, SpellPicker.fake_meta(ids))
	await frames(3)
	eq(p._cards.size(), 2, "two cards")
	check(p._scroll.custom_minimum_size.y >= SpellPicker.MIN_ROWS * SpellPicker.CARD_H, "a short list keeps the minimum height")
	check(_focus_step(p._cards[1], SIDE_BOTTOM) == p._start, "navigation works with two")
	p.toggle("spell_01")
	p.toggle("spell_02")
	check(p.confirm(), "two licences are enough")
	p.queue_free()
	await frames(2)
	var one := SpellPicker.fake_ids(1)
	var p1 := _open(one, SpellPicker.fake_meta(one))
	await frames(3)
	eq(p1._cards.size(), 1, "one card")
	check(not p1.confirm(), "one is not enough")
	p1.queue_free()
	await frames(2)
	# Cancelling from the Back row still reports it.
	var p3 := _open()
	await frames(3)
	var cancelled := [0]
	p3.cancelled.connect(func() -> void: cancelled[0] += 1)
	p3._back.pressed.emit()
	eq(cancelled[0], 1, "the Back row cancels")
	p3.queue_free()
	await frames(2)


## A player joining a job under way files FORM 15-S, a supplemental requisition: canary, the job typed across the top,
## "Submit requisition" to sign; still fits 1600 x 900.
func _requisition() -> void:
	var p := SpellPicker.new()
	p.requisition = {"job": "08323-PR", "client": "Hollis-Crane Continuity Holdings", "floor": "2 of 3", "relieving": "Gasket"}
	p.back_text = "Leave the crew"
	add_child(p)
	await frames(4)
	eq(p._sheet.header.form_no_label.text, "15-S", "a joiner's form is 15-S")
	check(p._sheet.header.title_label.text.to_lower().contains("supplemental requisition"), "titled Supplemental requisition")
	eq(p._start.text, "Submit requisition", "signing is Submit requisition")
	var typed: Array[String] = []
	for l in p._sheet.body.find_children("*", "Label", true, false):
		typed.append((l as Label).text)
	for v in ["08323-PR", "Hollis-Crane Continuity Holdings", "2 of 3", "Gasket"]:
		check(typed.has(v), "the requisition types %s" % v)
	var min_size := p._sheet.get_combined_minimum_size()
	check(min_size.x <= CANVAS_W and min_size.y <= CANVAS_H - 60.0, "15-S fits 1600 x 900 (%s)" % str(min_size))
	p.queue_free()
	await frames(2)
