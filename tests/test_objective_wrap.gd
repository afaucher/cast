extends TestCase
## Objective lines never clip: a contract objective ("Exterminate everything", "Exterminate skeletons", ...) wraps onto a
## second line instead of being cut, on the work-order tracker (hand-drawn, 360 wide) and on the job board (every label of
## every card, with the longest client and company names and every pest). Sizes are canvas units, so what fits at
## 1600x900 is what fits at 1280x720 (the same canvas, scaled).


func setup() -> void:
	timeout_sec = 120.0
	await _check_tracker_rows()
	await _check_tracker_detail()
	await _check_board()
	finish()


func _tracker_rows(pest: String, detail: String, employees: String) -> Array[Dictionary]:
	var run := ContractRun.make("prepper", 1, 0.5)
	run.pest = pest
	return [
		{"text": "Close hellgates", "detail": "2 / 4", "state": "partial"},
		{"text": "ORIGIN gate", "detail": "OPEN", "state": "todo"},
		{"text": run.pest_label(), "detail": detail, "state": "todo"},
		{"text": "Employees", "detail": employees, "state": "todo"},
	]


## Every row's wrapped text lies inside the room left of its detail; a row that wrapped is taller by LINE_H a line, and the
## slip (and so the ticker under it) grows with it.
func _check_tracker_rows() -> void:
	var tf := FormTheme.typed_font()
	var t := ObjectiveTracker.new()
	add_child(t)
	await frames(2)
	var one_line := 0.0
	for pest: String in ClientArchetype.PEST_NAMES:
		for detail in ["24 left", "clean", "100 left"]:
			t.show_state("FLOOR 2 / 3", "Vanderkeep Labs", _tracker_rows(pest, detail, "1 rescued"), 100, 0)
			var tag := "%s / %s" % [pest, detail]
			var total := t._header_h + _foot_and_pad()
			for i in t.rows.size():
				var lines := t.row_text_lines(i)
				var avail := ObjectiveTracker.row_text_width(_detail_width(t, i))
				var joined := " ".join(lines)
				eq(joined, str(t.rows[i]["text"]), "%s: row %d keeps all its text" % [tag, i])
				for l in lines:
					check(tf.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, ObjectiveTracker.ROW_TEXT_SIZE).x <= avail + 0.01, "%s: '%s' fits its %.0f px" % [tag, l, avail])
				near(t.row_height(i), ObjectiveTracker.ROW_H + ObjectiveTracker.LINE_H * float(maxi(lines.size(), t.row_detail_lines(i).size()) - 1), 0.01, "%s: row %d is as tall as its lines" % [tag, i])
				total += t.row_height(i)
			near(t.custom_minimum_size.y, total, 0.01, "%s: the slip is as tall as its rows" % tag)
			near(t.offset_bottom - t.offset_top, total, 0.01, "%s: and its bottom edge (the ticker hangs from it) follows" % tag)
			if pest == "everything" and detail == "24 left":
				eq(t.row_text_lines(2).size(), 2, "'Exterminate everything' wraps to two lines beside '24 left'")
				eq(t.row_text_lines(2)[0], "Exterminate", "... at the word")
				eq(t.row_text_lines(2)[1], "everything", "... and the second line is its own text")
			if pest == "swarmer" and detail == "24 left":
				one_line = t.custom_minimum_size.y
	t.show_state("FLOOR 2 / 3", "Vanderkeep Labs", _tracker_rows("everything", "24 left", "1 rescued"), 100, 0)
	check(t.custom_minimum_size.y > one_line - 0.01, "a wrapped row never makes the slip shorter")
	t.queue_free()
	await frames(2)


func _foot_and_pad() -> float:
	return ObjectiveTracker.FOOT_H + ObjectiveTracker.PAD


func _detail_width(t: ObjectiveTracker, i: int) -> float:
	var lf := FormTheme.label_font(true)
	var w := 0.0
	for l in t.row_detail_lines(i):
		w = maxf(w, lf.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, ObjectiveTracker.DETAIL_SIZE).x)
	return w


## The Employees row's detail (the worst case: every fact, four of each) wraps at its separators into a column no wider than
## DETAIL_MAX, so it stays on the slip.
func _check_tracker_detail() -> void:
	var lf := FormTheme.label_font(true)
	var t := ObjectiveTracker.new()
	add_child(t)
	await frames(2)
	for detail in ["2 rescued · 3 alive · 2 with you · 1 lost", "4 rescued · 4 alive · 4 with you · 4 lost", "1 rescued"]:
		t.show_state("FLOOR 2 / 3", "Vanderkeep Labs", _tracker_rows("everything", "24 left", detail), 100, 0)
		var lines := t.row_detail_lines(3)
		for l in lines:
			check(lf.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, ObjectiveTracker.DETAIL_SIZE).x <= ObjectiveTracker.DETAIL_MAX + 0.01, "'%s' fits the detail column" % l)
		eq(" · ".join(lines), detail, "no fact of '%s' is lost in the wrap" % detail)
		check(ObjectiveTracker.row_text_width(_detail_width(t, 3)) > 90.0, "'Employees' still has room beside '%s'" % detail)
		var text_lines := t.row_text_lines(3)
		eq(text_lines.size(), 1, "'Employees' stays on one line")
	eq(ObjectiveTracker.wrap_text("", lf, 20, 100.0).size(), 0, "no text, no lines")
	var long_word := ObjectiveTracker.wrap_text("Supercalifragilisticexpialidocious", FormTheme.typed_font(), 18, 120.0)
	check(long_word.size() > 1 and "".join(long_word) == "Supercalifragilisticexpialidocious", "a word longer than the line is broken, not cut")
	t.queue_free()
	await frames(2)


## The job board with the longest client / company of every archetype and every pest: no single-line label is wider than its
## box, every wrapped label shows all its lines, and the cards stay on the 1600x900 canvas.
func _check_board() -> void:
	var longest: Array[ContractRun] = []
	for id in ClientArchetype.IDS:
		var best: ContractRun = null
		for s in range(1, 301):
			var r := ContractRun.make(id, s, 0.5)
			if best == null or r.client_name.length() + r.company.length() > best.client_name.length() + best.company.length():
				best = r
		longest.append(best)
	var boards := 0
	for pest: String in ClientArchetype.PEST_NAMES:
		for start in [0, longest.size() - ContractBoard.OFFER_COUNT]:   # the first three archetypes, then the last three
			var offers: Array[ContractRun] = []
			for r in longest.slice(start, start + ContractBoard.OFFER_COUNT):
				r.pest = pest
				r._build_objectives()
				offers.append(r)
			var board := JobBoard.new(offers)
			add_child(board)
			await frames(3)
			boards += 1
			var tag := "%s / %s" % [pest, offers[0].client_name]
			var labels: Array[Label] = []
			_collect_labels(board, labels)
			var seen_pest := 0
			for l in labels:
				if l.text == "" or not l.is_visible_in_tree():
					continue
				var font := l.get_theme_font("font")
				var fs := l.get_theme_font_size("font_size")
				if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
					check(font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= l.size.x + 0.5, "%s: '%s' is not wider than its box (%.0f of %.0f)" % [tag, l.text, font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, l.size.x])
				else:
					check(l.size.y + 1.0 >= float(l.get_line_count()) * l.get_line_height(), "%s: '%s' shows all its %d lines" % [tag, l.text, l.get_line_count()])
				if l.text.begins_with("Exterminate"):
					seen_pest += 1
			eq(seen_pest, ContractBoard.OFFER_COUNT, "%s: every card prints its pest objective" % tag)
			for card in board._cards:
				check(card.get_global_rect().end.y <= 900.0, "%s: a card ends on the 900 unit canvas (%.0f)" % [tag, card.get_global_rect().end.y])
			board.queue_free()
			await frames(2)
	check(boards >= 10, "boards built for every pest (%d)" % boards)


func _collect_labels(n: Node, out: Array[Label]) -> void:
	if n is Label:
		out.append(n as Label)
	for c in n.get_children():
		_collect_labels(c, out)
