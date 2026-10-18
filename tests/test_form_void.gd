extends TestCase
## Back is VOID (docs/design/form-rules.md §6, FormVoid): on every form screen with a back, Esc (and the screen's own back
## row) stamps a big red VOID across its sheet, holds it FormVoid.HOLD_S, then runs the screen's back exactly once. While
## the stamp holds, a second Esc, a click or a key does nothing (a voided form can't be acted on). If the screen goes
## away first, its back never runs. Presentation only: the screens' back signals are counted, nothing else is wired.

const TMP := "user://test_form_void_settings.cfg"


func setup() -> void:
	timeout_sec = 120.0
	InputSetup.ensure_actions()
	_rm(TMP)
	check(is_equal_approx(FormVoid.hold_s, FormVoid.HOLD_S) and FormVoid.HOLD_S > 0.2 and FormVoid.HOLD_S < 0.5, "the hold is about 0.3 s")
	check(FormVoid.SLAM_S < FormVoid.HOLD_S and FormVoid.SLAM_FROM > 1.0, "the stamp slams in (scale down to 1) inside the hold")
	for spec: Dictionary in _screens():
		await _check_screen(spec, true)    # Esc
		await _check_screen(spec, false)   # its back row
	await _check_blocks_input()
	await _check_dies_with_screen()
	await _check_seam()
	await _check_hints()
	_rm(TMP)
	finish()


func _rm(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)


func _esc() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.physical_keycode = KEY_ESCAPE
	e.pressed = true
	return e


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


## Every form screen with a back, as the game builds it. `esc`: how Esc reaches it ("self": the screen's own _input;
## "game": the game or the menu calls void_back(), as their Esc handlers do). `sig`: its back signal.
func _screens() -> Array[Dictionary]:
	var info := {"floor": 1, "floor_count": 3, "payout": 5000, "damages": 300, "followers": 1, "lines": ["Line."]}
	return [
		{"name": "job board (FORM 12)", "esc": "game", "sig": "back",
			"make": func() -> Control: return JobBoard.new(ContractBoard.offers(7)),
			"over": func(s: Control) -> Control: return (s.get("_cards") as Array)[0], "stamps": 3},
		{"name": "client's job board", "esc": "game", "sig": "back",
			"make": func() -> Control:
				var b := JobBoard.new(ContractBoard.offers(7))
				b.read_only = true
				return b,
			"over": func(s: Control) -> Control: return (s.get("_cards") as Array)[0], "stamps": 3},
		{"name": "license checkout (FORM 15)", "esc": "game", "sig": "cancelled",
			"make": func() -> Control: return SpellPicker.new(),
			"row": func(s: Control) -> BaseButton: return s.get("_back"),
			"over": func(s: Control) -> Control: return s.get("_sheet")},
		{"name": "joiner's requisition (FORM 15-S)", "esc": "game", "sig": "cancelled",
			"make": func() -> Control:
				var p := SpellPicker.new()
				p.back_text = "Leave the crew"
				p.back_hint = "back to the menu"
				p.requisition = {"job": "08137-PR", "client": "Hollis-Crane", "floor": "2 of 3", "relieving": "Gasket"}
				return p,
			"row": func(s: Control) -> BaseButton: return s.get("_back"),
			"over": func(s: Control) -> Control: return s.get("_sheet")},
		{"name": "voice setup (FORM 7)", "esc": "game", "sig": "back",
			"make": func() -> Control:
				var v := VoiceSetupScreen.new()
				v.use_mic = false
				v.log_utterances = false
				v.settings_path = TMP
				return v,
			"row": func(s: Control) -> BaseButton: return (s as VoiceSetupScreen).back_button,
			"over": func(s: Control) -> Control: return (s as VoiceSetupScreen).sheet},
		{"name": "settings (FORM 3)", "esc": "game", "sig": "back",
			"make": func() -> Control:
				var st := SettingsScreen.new()
				st.settings_path = TMP
				st.apply_live = false
				return st,
			"row": func(s: Control) -> BaseButton: return (s as SettingsScreen).back_button,
			"over": func(s: Control) -> Control: return (s as SettingsScreen).sheet},
		{"name": "pause (FORM 27-B)", "esc": "self", "sig": "resume",
			"make": func() -> Control: return PauseMenu.new(),
			"row": func(s: Control) -> BaseButton: return (s as PauseMenu).resume_button,
			"over": func(s: Control) -> Control: return (s as PauseMenu).sheet},
		{"name": "online pause", "esc": "self", "sig": "resume",
			"make": func() -> Control:
				var p := PauseMenu.new()
				p.online = true
				p.hosting = false
				return p,
			"row": func(s: Control) -> BaseButton: return (s as PauseMenu).resume_button,
			"over": func(s: Control) -> Control: return (s as PauseMenu).sheet},
		{"name": "elevator slip (E-1)", "esc": "self", "sig": "stay",
			"make": func() -> Control: return ElevatorMenu.new(info),
			"row": func(s: Control) -> BaseButton: return (s.get("_rows") as Array).back(),
			"over": func(s: Control) -> Control: return s.get("_sheet")},
		{"name": "van slip (E-2)", "esc": "self", "sig": "cancel",
			"make": func() -> Control: return VanExitMenu.new(info),
			"row": func(s: Control) -> BaseButton: return (s.get("_rows") as Array).back(),
			"over": func(s: Control) -> Control: return s.get("_sheet")},
		{"name": "crew confirm (27-B)", "esc": "self", "sig": "declined",
			"make": func() -> Control: return CrewConfirm.new(),
			"row": func(s: Control) -> BaseButton: return (s as CrewConfirm).stay_button,
			"over": func(s: Control) -> Control: return (s as CrewConfirm).sheet},
		{"name": "invite confirm (27-C)", "esc": "self", "sig": "declined",
			"make": func() -> Control:
				var i := InviteConfirm.new()
				i.inviter = "Rosa"
				return i,
			"row": func(s: Control) -> BaseButton: return (s as InviteConfirm).stay_button,
			"over": func(s: Control) -> Control: return (s as InviteConfirm).sheet},
		{"name": "clocking in (12-C)", "esc": "self", "sig": "leave",
			"make": func() -> Control: return ClockInSlip.new(),
			"row": func(s: Control) -> BaseButton: return (s as ClockInSlip).leave_button,
			"over": func(s: Control) -> Control: return (s as ClockInSlip).sheet},
	]


## Open a screen, void it (Esc or its back row), and follow the stamp through the hold.
func _check_screen(spec: Dictionary, by_esc: bool) -> void:
	if not by_esc and not spec.has("row"):
		return
	var what := "%s, %s" % [str(spec["name"]), "Esc" if by_esc else "its back row"]
	var screen: Control = (spec["make"] as Callable).call()
	var fired := [0]
	screen.connect(str(spec["sig"]), func() -> void: fired[0] += 1)
	add_child(screen)
	await frames(4)
	if "_born_ms" in screen:
		screen.set("_born_ms", int(screen.get("_born_ms")) - 1000)   # past the input guard (wall time; tests run fast)
	check(FormVoid.of(screen) == null, what + ": nothing is void yet")

	if by_esc:
		if str(spec["esc"]) == "self":
			Input.parse_input_event(_esc())
		else:
			check(screen.call("void_back"), what + ": void_back() starts the void")
	else:
		((spec["row"] as Callable).call(screen) as BaseButton).pressed.emit()
	await frames(2)
	var v := FormVoid.of(screen)
	if not check(v != null, what + ": the form is voided"):
		screen.queue_free()
		await frames(2)
		return
	eq(fired[0], 0, what + ": the back waits for the stamp")
	var stamp := v.stamp
	check(stamp != null and stamp.is_visible_in_tree(), what + ": the VOID stamp is on screen")
	eq(stamp.lines, PackedStringArray(["VOID"]), what + ": it says VOID")
	eq(stamp.font_size, FormVoid.FONT_SIZE, what + ": the same size everywhere")
	eq(v.stamps.size(), int(spec.get("stamps", 1)), what + ": one stamp per part")
	near(stamp.rotation_degrees, FormVoid.ANGLE_DEG, 0.01, what + ": tilted the same way everywhere")

	# A second Esc (or a second press of the row) while it holds does nothing.
	if by_esc and str(spec["esc"]) == "self":
		Input.parse_input_event(_esc())
	else:
		check(not screen.call("void_back"), what + ": a second void is refused")
	if spec.has("row"):
		((spec["row"] as Callable).call(screen) as BaseButton).pressed.emit()
	await frames(6)
	eq(FormVoid.of(screen), v, what + ": still the one void")
	near(stamp.scale.x, 1.0, 0.001, what + ": the stamp has landed (scale 1)")
	near(stamp.modulate.a, 1.0, 0.001, what + ": fully inked")
	var over: Control = (spec["over"] as Callable).call(screen)
	var want: Vector2 = over.get_global_transform() * (over.size * 0.5)
	var got: Vector2 = stamp.get_global_transform() * stamp.pivot_offset
	check(got.distance_to(want) < 2.0, what + ": centred on the sheet (%s vs %s)" % [got, want])
	eq(fired[0], 0, what + ": still holding")

	await after_void()
	eq(fired[0], 1, what + ": the back ran once, after the hold")
	check(FormVoid.of(screen) == null, what + ": the void lifts once the back ran")
	await frames(20)
	eq(fired[0], 1, what + ": and only once")
	screen.queue_free()
	await frames(2)


## Keys and clicks stop at the void: the elevator slip's "1" and a click on its Exit row do nothing while it holds; a
## real click on its Stay row voids it like Esc.
func _check_blocks_input() -> void:
	var e := ElevatorMenu.new({"floor": 1, "floor_count": 3, "payout": 100})
	var got: Array[String] = []
	e.go_down.connect(func() -> void: got.append("down"))
	e.cash_out.connect(func() -> void: got.append("out"))
	e.stay.connect(func() -> void: got.append("stay"))
	add_child(e)
	await frames(4)
	e._born_ms -= 1000
	var rows: Array = e._rows
	await _click((rows.back() as Control).get_global_rect().get_center())
	check(FormVoid.of(e) != null, "a real click on Stay voids the slip")
	Input.parse_input_event(_key(KEY_1))
	Input.parse_input_event(_key(KEY_2))
	await frames(2)
	await _click((rows[1] as Control).get_global_rect().get_center())
	eq(got, [] as Array[String], "keys and clicks on a voided slip do nothing")
	await after_void()
	eq(got, ["stay"] as Array[String], "then it stays, once")
	e.queue_free()
	await frames(2)


func _click(at: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = at
	mv.global_position = at
	get_viewport().push_input(mv, true)
	await frames(1)
	for down: bool in [true, false]:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		m.position = at
		m.global_position = at
		m.pressed = down
		get_viewport().push_input(m, true)
		await frames(2)


## A screen that goes away mid-hold takes its void with it: the back never runs.
func _check_dies_with_screen() -> void:
	var c := CrewConfirm.new()
	var fired := [0]
	c.declined.connect(func() -> void: fired[0] += 1)
	add_child(c)
	await frames(3)
	check(c.void_back(), "voided")
	await frames(3)
	c.queue_free()
	await after_void()
	eq(fired[0], 0, "freed mid-hold: no back")


## The seam: FormVoid.hold_s = 0 runs the back on the next frame (the stamp still shows for it).
func _check_seam() -> void:
	FormVoid.hold_s = 0.0
	var p := PauseMenu.new()
	var fired := [0]
	p.resume.connect(func() -> void: fired[0] += 1)
	add_child(p)
	await frames(3)
	check(p.void_back(), "voided with no hold")
	eq(fired[0], 0, "not in the same call")
	await frames(3)
	eq(fired[0], 1, "the next frame")
	FormVoid.hold_s = FormVoid.HOLD_S
	p.queue_free()
	await frames(2)


## The key strips under the forms say "void" for Esc, never "back".
func _check_hints() -> void:
	for spec: Dictionary in _screens():
		var s: Control = (spec["make"] as Callable).call()
		add_child(s)
		await frames(2)
		var caps: Array[String] = []
		for k: Node in s.find_children("*", "", true, false):
			if k is KeyHints:
				for l: Node in k.get_children():
					if l is Label:
						caps.append((l as Label).text)
		if not caps.is_empty():
			check(caps.has("VOID") and not caps.has("BACK") and not caps.has("LEAVE THE CREW"), "%s: Esc reads VOID in the key strip (%s)" % [str(spec["name"]), caps])
		s.queue_free()
		await frames(2)
