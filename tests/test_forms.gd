extends TestCase
## The carbon-copy form components (scripts/ui/forms/) and the screens built on them: theme and fonts, the box
## scale, rows and focus, the job board's highlight and backdrop shade, the spell picker's flow, the pause and
## elevator slips, the "Clocking in..." form (M6), the invoice and the objective slip. Presentation only: no simulation state.


func setup() -> void:
	timeout_sec = 90.0
	_check_theme()
	await _check_box_scale()
	await _check_rows()
	await _check_job_board()
	await _check_picker()
	await _check_slips()
	await _check_invoice_revival()
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
	board.sign_hold = 0.0   # emit at once (the hold only keeps the signature on screen)
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
	eq(got.size(), 2, "number keys don't pick (no key bindings on the cards)")
	var signed: String = board._sign_lines[0].signature
	eq(signed, JobBoard.signer_name(), "taking an offer signs its Take line with the player's name")
	check(signed != "", "the signature isn't blank")
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
	check(bool((p._buttons[ids[0]] as LicenseCard).button_pressed), "a picked card is ticked")
	p.set_trigger_word("pickle")
	check((p._buttons[ids[0]] as LicenseCard).hint.contains("pickle"), "the trigger word reaches the card hints")
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
	for r: Control in e._rows:
		check(not (r as FormRow).hint.to_lower().contains("always works"), "the elevator slip no longer says it always works (floor 1)")
	e.queue_free()
	var last := ElevatorMenu.new({"floor": 3, "floor_count": 3})
	add_child(last)
	await frames(2)
	check(not last.can_descend() and last._rows.size() == 2, "no go-down row on the last floor")
	check(last._rows[0].number == "1", "on the last floor the exit is row 1")
	for r: Control in last._rows:
		check(not (r as FormRow).hint.to_lower().contains("always works"), "the elevator slip no longer says it always works")
	last.queue_free()
	await frames(2)
	var van := VanExitMenu.new(info)
	add_child(van)
	await frames(2)
	check(van._rows.size() == 2, "the van slip: clock out / cancel")
	check((van._rows[0] as FormRow).text == "Clock out", "its first row clocks out")
	check(not (van._rows[0] as FormRow).hint.to_lower().contains("always works"), "the van slip no longer says it always works")
	van.queue_free()
	await frames(2)

	# M6: a late joiner's "Clocking in..." form.
	var clock := ClockInSlip.new()
	add_child(clock)
	await frames(3)
	check(clock.leave_button.has_focus(), "Clocking in focuses its one row, Leave the crew")
	clock.set_values("host's crew", "Hollis-Crane Continuity Holdings Of A Very Long Name", "2 of 3", "", "Building floor 2...")
	await frames(2)
	eq(clock.floor_value.text, "2 of 3", "the floor is typed in")
	eq(clock.seat_value.text, "-", "a value not known yet is a dash")
	eq(clock.step_label.text, "Building floor 2...", "the one line says what is happening")
	check(clock.job_value.clip_text, "a long job name is trimmed on the form")
	eq(clock.license_value.text, "-", "no license signed yet: a dash")
	clock.set_license("TENTACLES · TEETH")
	eq(clock.license_value.text, "TENTACLES · TEETH", "the joiner's signed license is typed in")
	eq(clock.sheet.header.copy_value.text, "LICENSED", "... and its status reads LICENSED")
	var left := [false]
	clock.leave.connect(func() -> void: left[0] = true)
	clock.leave_button.pressed.emit()
	check(left[0], "Leave the crew leaves")
	clock.queue_free()
	await frames(2)

	var tracker := ObjectiveTracker.new()
	add_child(tracker)
	var rows: Array[Dictionary] = [{"text": "Close hellgates", "detail": "1/2", "state": "partial"}]
	tracker.show_state("Floor 1 of 3", "Sub", rows, 100, 0)
	await frames(2)
	check(tracker.custom_minimum_size.y > 100.0, "the slip sizes to its rows")
	tracker.queue_free()
	await frames(2)
	await _check_tracker_header()
	await _check_use_prompt_node()


## The tracker's header is stacked (WORK ORDER, then the name on its own lines, then the floor), so the longest names
## ClientArchetype can roll never run into each other: at most two lines, each inside the slip, ellipsis past that.
func _check_tracker_header() -> void:
	var font := FormTheme.typed_font()
	var inner := ObjectiveTracker.WIDTH - 2.0 * ObjectiveTracker.PAD
	var names := {}   # every company ClientArchetype can produce -> true
	var longest := ""
	for id in ClientArchetype.IDS:
		var d := ClientArchetype.get_data(id)
		for last: String in d["last"]:
			for pattern: String in d["company"]:
				var nm := pattern % last
				names[nm] = true
				if nm.length() > longest.length():
					longest = nm
			names[last] = true
	for seed_n in 12:   # and what the rolls actually give, seed by seed
		for id in ClientArchetype.IDS:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_n
			var who := ClientArchetype.roll_name(id, rng)
			names[str(who["company"])] = true
			names[str(who["name"])] = true
	check(names.size() > 40, "found the client / company names (%d)" % names.size())
	var worst_lines := 0
	var tracker := ObjectiveTracker.new()
	add_child(tracker)
	var rows: Array[Dictionary] = [{"text": "Close hellgates", "detail": "1/2", "state": "partial"}]
	var single_h := 0.0
	var bad := 0
	for nm: String in names:
		tracker.show_state("FLOOR 2 / 3", nm, rows, 100, 0)
		var lines := tracker.name_lines()
		worst_lines = maxi(worst_lines, lines.size())
		var fits := lines.size() >= 1 and lines.size() <= ObjectiveTracker.NAME_LINES
		for l in lines:
			if font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, ObjectiveTracker.NAME_SIZE).x > inner:
				fits = false
		if not fits:
			bad += 1
			print("tracker name did not fit: ", nm, " -> ", lines)
		# the stacked header: label above the name above the floor line, inside the header
		if tracker.name_lines().size() > 0 and not (19.0 < tracker._name_baseline(0) - ObjectiveTracker.NAME_SIZE * 0.85 + 4.0 and tracker.floor_baseline() > tracker._name_baseline(lines.size() - 1) + 6.0 and tracker.header_height() > tracker.floor_baseline()):
			bad += 1
	eq(bad, 0, "every name wraps to at most 2 lines inside the slip and the header lines are stacked")
	check(worst_lines == 2, "the longest names do use two lines (the longest is '%s')" % longest)
	tracker.show_state("FLOOR 1 / 3", "Vanderkeep Labs", rows, 100, 0)
	single_h = tracker.custom_minimum_size.y
	tracker.show_state("FLOOR 1 / 3", longest, rows, 100, 0)
	check(tracker.custom_minimum_size.y > single_h, "a two-line name makes the slip taller instead of overlapping")
	var tiny: PackedStringArray = ObjectiveTracker.wrap_name("Supercalifragilisticexpialidocious-Supercalifragilisticexpialidocious-Pneumonoultramicroscopic Holdings", font, ObjectiveTracker.NAME_SIZE, inner, 2)
	check(tiny.size() == 2 and tiny[1].ends_with("…"), "a name that cannot fit ends in an ellipsis")
	check(ObjectiveTracker.wrap_name("", font, 20, inner, 2).is_empty(), "no name, no lines")
	tracker.queue_free()
	await frames(2)


## The use prompt node: a keycap and a verb that fade in and out over about 0.15 s.
func _check_use_prompt_node() -> void:
	var p := UsePrompt.new()
	add_child(p)
	await frames(2)
	check(not p.wanted and p.alpha == 0.0 and not p._sprite.visible, "starts hidden")
	p.show_at(Vector3(1, 2, 3), "E", "Clock out")
	check(p.key == "E" and p.verb == "Clock out" and p.is_showing(), "shows its key and verb")
	check(p.global_position.is_equal_approx(Vector3(1, 2, 3)), "floats at the given point")
	await frames(4)
	check(p.alpha > 0.0 and p.alpha < 1.0, "fading in (alpha %.2f)" % p.alpha)
	await frames(12)
	near(p.alpha, 1.0, 0.0001, "fully in after ~0.2 s")
	check(p._sprite.visible and p._viewport.size.x > p._viewport.size.y, "a wide slip with the verb on it")
	var narrow := p._viewport.size.x
	p.show_at(Vector3.ZERO, "F", "Swap in Grave moss")
	await frames(2)
	check(p._viewport.size.x > narrow, "a longer verb makes a wider slip")
	await _check_use_prompt_zoom(p)
	p.hide_prompt()
	await frames(4)
	check(p.alpha > 0.0 and p.alpha < 1.0, "fading out")
	await frames(12)
	check(p.alpha == 0.0 and not p._sprite.visible, "gone after ~0.2 s")
	p.queue_free()
	await frames(2)


## The slip is the same size on screen at every camera zoom (--zoom 6 to 36), and stays inside the viewport even when its
## anchor is off screen or out of the camera's frame.
func _check_use_prompt_zoom(p: UsePrompt) -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CameraRig.SIZE_DEFAULT
	add_child(cam)
	cam.position = Vector3(0, 30, 21)
	cam.look_at(Vector3.ZERO)
	cam.make_current()
	p.show_at(Vector3.ZERO, "E", "Clock out")
	var heights: Array[float] = []
	for zoom: float in [CameraRig.SIZE_DEFAULT, 11.0, 6.0, 36.0]:
		cam.size = zoom
		await frames(3)
		var world_h := p._sprite.pixel_size * float(UsePrompt.PX_H)
		var a := cam.unproject_position(p.global_position)
		var b := cam.unproject_position(p.global_position + cam.global_basis.y * world_h)
		heights.append(a.distance_to(b))
	for i in range(1, heights.size()):
		near(heights[i], heights[0], 0.5, "the use prompt is %.1f px tall at every zoom (%.1f)" % [heights[0], heights[i]])
	near(heights[0], p.screen_height(), 0.5, "and that is its design height at the default zoom")
	# far off screen: clamped back inside the viewport
	cam.size = 6.0
	p.show_at(Vector3(40, 0, -40), "E", "Clock out")
	await frames(3)
	var vp := p.get_viewport().get_visible_rect().size
	var c := cam.unproject_position(p.global_position) + Vector2(p._sprite.offset.x, -p._sprite.offset.y) * (p.screen_height() / float(UsePrompt.PX_H))
	check(c.x >= 0.0 and c.x <= vp.x and c.y >= 0.0 and c.y <= vp.y, "an anchor off screen keeps its slip on screen (%s in %s)" % [c, vp])
	# over the HUD's spell cards: nudged up so it never covers them
	var hud := Hud.new()
	add_child(hud)
	var hero := Hero.new()
	add_child(hero)
	hud.bind(hero, [] as Array[Hero])
	await frames(3)
	var cards := hud.cards_rect()
	check(cards.size.x > 100.0 and cards.position.y > vp.y * 0.6, "the HUD reports where its spell cards are (%s)" % cards)
	cam.size = CameraRig.SIZE_DEFAULT
	var below := cam.project_position(cards.get_center(), 30.0)   # a world point that projects onto the cards' middle
	p.show_at(below, "E", "Clock out")
	await frames(3)
	var at := cam.unproject_position(p.global_position)
	var slip := Rect2(at + Vector2(p._sprite.offset.x, -p._sprite.offset.y) * (p.screen_height() / float(UsePrompt.PX_H)) - Vector2(float(p._viewport.size.x), float(UsePrompt.PX_H)) * (p.screen_height() / float(UsePrompt.PX_H)) * 0.5,
			Vector2(float(p._viewport.size.x), float(UsePrompt.PX_H)) * (p.screen_height() / float(UsePrompt.PX_H)))
	check(slip.end.y <= cards.position.y, "a prompt anchored over the spell cards sits above them (bottom %.0f, cards top %.0f)" % [slip.end.y, cards.position.y])
	hud.queue_free()
	hero.queue_free()
	cam.queue_free()
	await frames(2)


## FORM 99 bills corporate's crew revival: a section after property damage, one row per downed hero, the side slip names
## them, and a negative NET PAYOUT prints in red with a minus sign.
func _check_invoice_revival() -> void:
	var run := ContractRun.make("prepper", 71, 0.5)
	var session := ContractSession.begin(run)
	session.enter_floor(1, 1, false, 2, 10)
	session.gate_closed(false)
	session.finish(ContractSession.END_CASHED_OUT, ["Wick", "Gasket"])
	var inv := ContractInvoice.build(session)
	check(int(inv["payout"]) < 0, "two revivals outweigh the gate: the net payout is negative")
	var screen := InvoiceScreen.new(inv)
	add_child(screen)
	await frames(3)
	var texts: Array[String] = []
	_collect_text(screen, texts)
	check(texts.has("CREW REVIVAL (CORPORATE)"), "the invoice has the crew revival section")
	check(texts.has("Revival - Wick") and texts.has("Revival - Gasket"), "one row per downed hero")
	check(texts.has("-$10,000"), "each row bills -$10,000")
	check(texts.has("NET PAYOUT"), "NET PAYOUT is on the invoice")
	var net_text := ContractRun.money(int(inv["payout"]))
	check(net_text.begins_with("-$") and texts.has(net_text), "NET PAYOUT prints with a minus sign (%s)" % net_text)
	var net_label := _find_label(screen, net_text)
	check(net_label != null and net_label.get_theme_color("font_color") == FormTheme.RED, "and in red")
	check(texts.has("Wick (revived)"), "the crew debrief slip notes who went down")
	screen.queue_free()
	await frames(2)

	# Nobody down: no revival section at all.
	var run2 := ContractRun.make("prepper", 72, 0.5)
	var s2 := ContractSession.begin(run2)
	s2.enter_floor(1, 1, false, 2, 10)
	s2.gate_closed(false)
	s2.finish(ContractSession.END_CASHED_OUT)
	var screen2 := InvoiceScreen.new(ContractInvoice.build(s2))
	add_child(screen2)
	await frames(3)
	var texts2: Array[String] = []
	_collect_text(screen2, texts2)
	check(not texts2.has("CREW REVIVAL (CORPORATE)"), "no revival section when nobody is down")
	screen2.queue_free()
	await frames(2)


func _collect_text(n: Node, out: Array[String]) -> void:
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_collect_text(c, out)


func _find_label(n: Node, text: String) -> Label:
	if n is Label and (n as Label).text == text:
		return n as Label
	for c in n.get_children():
		var f := _find_label(c, text)
		if f != null:
			return f
	return null
