extends Control
## Screenshot lab for the carbon-copy forms. Scene: scenes/forms_lab.tscn. Opens one screen over a stand-in
## dark backdrop (the menu screens main / voice / settings are reached with the menu's own flags instead).
##
##   godot --path . --resolution 1280x720 -- --scene res://scenes/forms_lab.tscn --screen board --lab-shot <abs.png>
##
## --screen <s>    board | picker | picker_s | pause | elevator | elevator_last | van | invoice | tracker | gallery
##                 (picker: FORM 15, the license requisition; picker_s: FORM 15-S, a joiner's supplemental requisition)
## --lab-shot <p>  save a screenshot after --lab-after seconds (default 1.2) and quit
## --lab-after <s>
## --invoice-seed <n> / --invoice-down <n>   invoice: the contract's seed, and how many heroes are still down (revival fees)
## --lab-focus <n> board: which offer is highlighted (default 0)
## --lab-down <n>  press Down n times first (focus walk), for the picker / pause / elevator
## --lab-card <i> picker: focus line i (0-based) after the first lines are ticked
## --lab-picks <n> picker: tick the first n lines (default 2)
## --lab-sign      picker: sign it (the name stamp on "Requested by") and hold there
## --lab-fake <n>  picker: offer n made-up spells instead of the real ones (checks a long catalog)
## --lab-void      void the screen (its void_back(), as Esc does) 0.4 s before the shot and hold the VOID stamp there
##                 (board, picker, pause, elevator, elevator_last, van; FormVoid)

var screen := "board"
## The screen _open() built (for --lab-void).
var opened: Control = null


func _ready() -> void:
	InputSetup.ensure_actions()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var a := OS.get_cmdline_user_args()
	screen = Boot.arg_value(a, "--screen") if Boot.arg_value(a, "--screen") != "" else "board"
	var bg := TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.2, 0.17, 0.2), Color(0.07, 0.06, 0.09)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.3, 0.0)
	gt.fill_to = Vector2(0.7, 1.0)
	gt.width = 256
	gt.height = 256
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_open(screen, a)
	var shot := Boot.arg_value(a, "--lab-shot")
	if shot != "":
		var after := Boot.arg_value(a, "--lab-after")
		var at := float(after) if after != "" else 1.2
		if a.has("--lab-void"):
			_void_later(maxf(at - 0.4, 0.1))
		_shot_later(shot, at)


## --lab-void: void the open screen like Esc does, holding the stamp (nothing is wired to its back signal here anyway).
func _void_later(after: float) -> void:
	await get_tree().create_timer(after).timeout
	FormVoid.hold_s = 3600.0
	if opened != null and opened.has_method("void_back"):
		opened.call("void_back")


func _open(which: String, a: PackedStringArray) -> void:
	match which:
		"board":
			var board := JobBoard.new(ContractBoard.offers(7))
			add_child(board)
			opened = board
			var f := Boot.arg_value(a, "--lab-focus")
			if f != "":
				board.set_highlight(int(f))
		"picker", "picker_s":
			var p := SpellPicker.new()
			var fake := int(Boot.arg_value(a, "--lab-fake"))   # a made-up list of this many spells (0 = the real ones)
			if fake > 0:
				p.spell_ids = SpellPicker.fake_ids(fake)
				p.spell_meta = SpellPicker.fake_meta(p.spell_ids)
			if which == "picker_s":
				p.back_text = "Leave the crew"
				p.back_hint = "back to the menu"
				p.requisition = {"job": "08137-PR", "client": "Hollis-Crane Continuity Holdings", "floor": "2 of 3", "relieving": "Gasket"}
			else:
				p.job = {"job": "08137-PR", "client": "Hollis-Crane Continuity Holdings"}
			add_child(p)
			opened = p
			var offered := p.offered()
			var picks := int(Boot.arg_value(a, "--lab-picks")) if Boot.arg_value(a, "--lab-picks") != "" else 2
			for i in mini(picks, offered.size()):
				p.toggle(offered[i])
			if Boot.arg_value(a, "--lab-card") != "":
				p.focus_line.call_deferred(int(Boot.arg_value(a, "--lab-card")))
			if a.has("--lab-sign"):
				p.sign_hold = 3600.0   # hold the stamp: the shot catches it before `picked`
				p.confirm()
			_walk(a)
		"pause":
			var p := PauseMenu.new()
			add_child(p)
			opened = p
		"elevator", "elevator_last":
			var last := which == "elevator_last"
			var e := ElevatorMenu.new({"floor": 3 if last else 1, "floor_count": 3, "payout": 8400, "damages": 1200, "followers": 2,
				"lines": ["Wine cellar sealed.", "Colin (valet) did not make it."]})
			add_child(e)
			opened = e
		"van":
			var v := VanExitMenu.new({"floor": 1, "floor_count": 3, "payout": 8400, "damages": 1200, "followers": 2,
				"lines": ["Hellgates closed on this floor: 1 of 2.", "Objectives not met do not pay. Damage comes out of what you earned."]})
			add_child(v)
			opened = v
		"invoice":
			var inv := _demo_invoice()
			var s := InvoiceScreen.new(inv)
			add_child(s)
		"gallery":
			var l := Label.new()
			l.text = "LICENSED BONDED 0123 abc"
			l.add_theme_font_override("font", FormTheme.stamp_font())
			l.add_theme_font_size_override("font_size", 60)
			l.position = Vector2(100, 100)
			add_child(l)
			var l2 := Label.new()
			l2.text = "LICENSED BONDED 0123 abc"
			l2.add_theme_font_override("font", load("res://assets/fonts/black_ops_one/BlackOpsOne-Regular.ttf"))
			l2.add_theme_font_size_override("font_size", 60)
			l2.position = Vector2(100, 300)
			add_child(l2)
			var st := FormStamp.new("LICENSED
BONDED", 40, -6.0)
			st.position = Vector2(100, 500)
			add_child(st)
		"tracker":
			var t := ObjectiveTracker.new()
			add_child(t)
			var rows: Array[Dictionary] = [
				{"text": "Close hellgates", "detail": "2/4", "state": "partial"},
				{"text": "Exterminate: imps", "detail": "0/12", "state": "todo"},
				{"text": "Employees", "detail": "3/3", "state": "done"},
				{"text": "Origin gate", "detail": "", "state": "fail"},
			]
			t.show_state("Floor 2 of 3", "Wine cellar", rows, 6000, 1500)


func _walk(a: PackedStringArray) -> void:
	var n := Boot.arg_value(a, "--lab-down")
	if n == "":
		return
	await get_tree().process_frame
	for i in int(n):
		var e := InputEventAction.new()
		e.action = "ui_down"
		e.pressed = true
		Input.parse_input_event(e)
		await get_tree().process_frame


func _demo_invoice() -> Dictionary:
	var seed_arg := Boot.arg_value(OS.get_cmdline_user_args(), "--invoice-seed")
	var run := ContractBoard.run_for_seed(int(seed_arg) if seed_arg != "" else 12)   # --invoice-seed 60: the longest client name
	var s := ContractSession.begin(run, 1)
	var wick := _hero("Wick")
	var rebar := _hero("Rebar")
	var gasket := _hero("Gasket")
	s.enter_floor(1, run.floor_gates[0], false, run.floor_employees[0], 12)
	for _i in run.floor_gates[0]:
		s.gate_closed(false)
	s.check_clean(0)
	s.extract(2)
	Ledger.damage("Wine rack", 1200, wick)
	s.enter_floor(2, run.floor_gates[1], false, run.floor_employees[1], 14)
	for _i in run.floor_gates[1]:
		s.gate_closed(false)
	s.check_clean(0)
	Ledger.damage("Zen fountain", 900, rebar)
	Ledger.damage("Crystal lamp", 600, wick)
	s.employee_lost("Colin (valet)", "Wick")
	s.enter_floor(3, 0, true, run.floor_employees[2], 18)
	s.gate_closed(true)
	s.check_clean(0)
	s.extract(1)
	Ledger.damage("Gold toilet", 15000, gasket)
	# --invoice-down <n>: n heroes (Gasket, Rebar, Wick in that order) are still down, so corporate bills the revival fee.
	var down_arg := Boot.arg_value(OS.get_cmdline_user_args(), "--invoice-down")
	var downed: Array[String] = []
	for nm: String in ["Gasket", "Rebar", "Wick"].slice(0, clampi(int(down_arg) if down_arg != "" else 0, 0, 3)):
		downed.append(nm)
	s.finish(ContractSession.END_CASHED_OUT, downed)
	var inv := ContractInvoice.build(s)
	for h in [wick, rebar, gasket]:
		h.free()
	return inv


func _hero(n: String) -> Actor:
	var a := Actor.new()
	a.display_name = n
	return a


func _shot_later(path: String, after: float) -> void:
	await get_tree().create_timer(after).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[forms_lab] screenshot saved: ", path)
	get_tree().quit()
