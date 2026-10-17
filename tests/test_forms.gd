extends TestCase
## The carbon-copy form components (scripts/ui/forms/) and the screens built on them: theme and fonts, the box
## scale, rows and focus, the job board's highlight and backdrop shade, the spell picker's flow, the pause and
## elevator slips, the invoice and the objective slip. Presentation only: no simulation state.


func setup() -> void:
	timeout_sec = 90.0
	_check_theme()
	await _check_box_scale()
	await _check_rows()
	await _check_job_board()
	await _check_picker()
	await _check_slips()
	finish()


func _action(name_: String) -> InputEventAction:
	var e := InputEventAction.new()
	e.action = name_
	e.pressed = true
	return e


func _check_theme() -> void:
	check(FormTheme.label_font() != null and FormTheme.typed_font() != null and FormTheme.stamp_font() != null and FormTheme.hand_font() != null, "the four fonts resolve")
	check(FormTheme.theme() == FormTheme.theme(), "one shared Theme")
	var tex := FormTheme.paper_texture()
	check(tex != null and tex.get_width() == 256, "the paper grain is generated")
	eq(FormTheme.carbon("canary"), Color("f5e6a3"), "canary carbon")
	eq(FormTheme.carbon("nonsense"), FormTheme.PAPER, "an unknown carbon is white")
	for key in ["white", "canary", "pink", "gold", "green", "blue"]:
		check(FormTheme.CARBONS.has(key), "carbon " + key)
	var stamp := FormStamp.new("TRADE PRICE", 24, -6.0)
	check(stamp.size.x > 100.0 and absf(stamp.rotation_degrees + 6.0) < 0.01, "a stamp sizes itself and tilts")
	stamp.free()


func _check_box_scale() -> void:
	var s := BoxScale.new()
	s.min_value = 0.0
	s.max_value = 100.0
	s.value = 100.0
	add_child(s)
	await frames(2)
	var seen: Array[float] = []
	s.value_changed.connect(func(v: float) -> void: seen.append(v))
	s._gui_input(_action("ui_left"))
	near(s.value, 90.0, 0.001, "Left moves one box (10 of 100)")
	s._gui_input(_action("ui_left"))
	s._gui_input(_action("ui_right"))
	near(s.value, 90.0, 0.001, "Left then Right")
	for i in 20:
		s._gui_input(_action("ui_right"))
	near(s.value, 100.0, 0.001, "clamped at the top")
	eq(seen.size() > 0, true, "value_changed fires")
	near(s.box_value(3), 30.0, 0.001, "three boxes = 30")
	s.value = 35.0
	near(s.value, 35.0, 0.001, "a value between boxes is kept (the settings test sets 35)")
	var g := BoxScale.new()
	g.min_value = -70.0
	g.max_value = -10.0
	g.value = -50.0
	near(g.box_value(5), -40.0, 0.001, "a dB scale: 5 boxes = -40")
	g.free()
	s.queue_free()
	await frames(2)


func _check_rows() -> void:
	var root := VBoxContainer.new()
	add_child(root)
	var a := FormRow.new("First", "01", "hint a")
	var b := FormRow.new("Second", "02", "")
	var c := FormRow.new("Third", "03", "")
	root.add_child(a)
	root.add_child(b)
	root.add_child(c)
	FormTheme.chain([a, b, c])
	await frames(3)
	eq(a.text, "First", "a row keeps its text")
	check(a.custom_minimum_size.y >= 60.0, "a row is tall enough to read and hit")
	eq(a.find_valid_focus_neighbor(SIDE_BOTTOM), b, "Down: first -> second")
	eq(c.find_valid_focus_neighbor(SIDE_BOTTOM), a, "Down wraps from the last row to the first")
	eq(a.find_valid_focus_neighbor(SIDE_TOP), c, "Up wraps from the first row to the last")
	check(not a.has_focus(), "nothing is focused until something asks")
	b.mouse_entered.emit()
	check(b.has_focus(), "mouse hover grabs focus, so there is one highlight")
	c.mouse_entered.emit()
	check(c.has_focus() and not b.has_focus(), "hover moves the single focus")
	var pressed := [0]
	a.pressed.connect(func() -> void: pressed[0] += 1)
	a.pressed.emit()
	eq(pressed[0], 1, "a row is a button")
	a.disabled = true
	a.mouse_entered.emit()
	check(not a.has_focus(), "a disabled row does not take focus")
	root.queue_free()

	# A field row: the band follows the watched control's focus; a check ticks with a typed X.
	var f := FormCheck.new("Fullscreen")
	var field := FormField.new("Display", f)
	add_child(field)
	await frames(2)
	check(not f.button_pressed, "unticked")
	f.button_pressed = true
	check(f.button_pressed, "ticked")
	check(not f.own_band, "inside a field the row draws the band")
	f.grab_focus()
	check(field._focused(), "the field sees its control's focus")
	field.queue_free()
	await frames(2)


func _check_job_board() -> void:
	var offers := ContractBoard.offers(7)
	var board := JobBoard.new(offers)
	add_child(board)
	await frames(3)
	eq(board.highlighted(), 0, "offer 1 starts highlighted")
	check(not board.backdrop_behind, "no 3D backdrop is assumed by default")
	check(board._fallback != null and board._fallback.visible and is_equal_approx(board._fallback.color.a, 1.0), "an opaque dark shade shows with no backdrop")
	board.backdrop_behind = true
	check(board._fallback.color.a < 0.5, "the shade turns light when the garage is behind the board (alpha %.2f)" % board._fallback.color.a)
	board.backdrop_behind = false
	check(is_equal_approx(board._fallback.color.a, 1.0), "and opaque again when the backdrop goes")
	board.backdrop_behind = true
	board._input(_action("ui_right"))
	eq(board.highlighted(), 1, "Right highlights the next offer")
	board._input(_action("ui_left"))
	board._input(_action("ui_left"))
	eq(board.highlighted(), 2, "Left wraps")
	var got: Array[ContractRun] = []
	board.picked.connect(func(r: ContractRun) -> void: got.append(r))
	board._input(_action("ui_accept"))
	eq(got.size(), 1, "Enter takes the highlighted offer")
	check(got[0] == offers[2], "the right offer")
	board.choose(0)
	check(got.size() == 2 and got[1] == offers[0], "choose() still takes any offer")
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	board._input(key)
	check(got.size() == 3 and got[2] == offers[1], "the key 2 takes offer 2")
	board.set_highlight(0)
	await frames(8)
	check(board._cards[0].outline_color.a > 0.0 and board._cards[1].outline_color.a == 0.0, "only the highlighted card has the yellow outline")
	# The same fields in the same places: the three cards are the same height.
	var h0: float = board._cards[0].size.y
	near(board._cards[1].size.y, h0, 14.0, "cards share a height (modulo the lift)")
	board.queue_free()
	await frames(2)
	# Setting backdrop_behind before the board is in the tree (as the game does) must not break either.
	var early := JobBoard.new(offers)
	early.backdrop_behind = true
	add_child(early)
	await frames(2)
	check(early._fallback.color.a < 0.5, "a board told about its backdrop before _ready starts with the light shade")
	early._input(_action("ui_right"))
	eq(early.highlighted(), 1, "works with the backdrop flag set early")
	early.queue_free()
	await frames(2)


func _check_picker() -> void:
	var p := SpellPicker.new()
	add_child(p)
	await frames(3)
	var ids := SpellBook.ids()
	eq(p._buttons.size(), ids.size(), "a row per spell")
	check(p._start.disabled, "Start is disabled with no picks")
	p.toggle(ids[0])
	p.toggle(ids[1])
	check(not p._start.disabled, "two picks enable Start")
	check(p._start.has_focus(), "the second pick moves focus to Start, so Enter signs")
	check(bool((p._buttons[ids[0]] as FormRow).button_pressed), "a picked row is ticked")
	p.set_trigger_word("pickle")
	check((p._buttons[ids[0]] as FormRow).hint.contains("pickle"), "the trigger word reaches the row hints")
	var got := []
	p.picked.connect(func(s: Array[String]) -> void: got.append(s))
	check(p.confirm(), "confirm with two")
	eq(got.size(), 1, "picked emitted")
	p.queue_free()
	await frames(2)


func _check_slips() -> void:
	var pause := PauseMenu.new()
	add_child(pause)
	await frames(4)
	check(pause.resume_button.has_focus(), "pause focuses Resume")
	eq(pause.resume_button.find_valid_focus_neighbor(SIDE_BOTTOM), pause.abandon_button, "Down: Resume -> Abandon")
	pause.queue_free()
	await frames(2)

	var info := {"floor": 1, "floor_count": 3, "payout": 5000, "damages": 300, "followers": 1, "lines": ["Line."]}
	var e := ElevatorMenu.new(info)
	add_child(e)
	await frames(2)
	check(e.can_descend() and e._rows.size() == 3, "go down / cash out / stay on floor 1")
	e.queue_free()
	var last := ElevatorMenu.new({"floor": 3, "floor_count": 3})
	add_child(last)
	await frames(2)
	check(not last.can_descend() and last._rows.size() == 2, "no go-down row on the last floor")
	last.queue_free()
	await frames(2)

	var tracker := ObjectiveTracker.new()
	add_child(tracker)
	var rows: Array[Dictionary] = [{"text": "Close hellgates", "detail": "1/2", "state": "partial"}]
	tracker.show_state("Floor 1 of 3", "Sub", rows, 100, 0)
	await frames(2)
	check(tracker.custom_minimum_size.y > 100.0, "the slip sizes to its rows")
	tracker.queue_free()
	await frames(2)
