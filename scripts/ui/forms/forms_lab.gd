extends Control
## Screenshot lab for the carbon-copy forms. Scene: scenes/forms_lab.tscn. Opens one screen over a stand-in
## dark backdrop (the menu screens main / voice / settings are reached with the menu's own flags instead).
##
##   godot --path . --resolution 1280x720 -- --scene res://scenes/forms_lab.tscn --screen board --lab-shot <abs.png>
##
## --screen <s>    board | picker | picker_s | pause | elevator | elevator_last | van | invoice | tracker | employees | gallery
##                 (employees: mock-ups of the tracker's Employees row, three options; picker: FORM 15, the license requisition; picker_s: FORM 15-S, a joiner's supplemental requisition)
## --lab-shot <p>  save a screenshot after --lab-after seconds (default 1.2) and quit
## --lab-after <s>
## --invoice-seed <n> / --invoice-down <n>   invoice: the contract's seed, and how many heroes are still down (revival fees)
## --lab-focus <n> board: which offer is highlighted (default 0)
## --lab-down <n>  press Down n times first (focus walk), for the picker / pause / elevator
## --lab-card <i> picker: focus line i (0-based) after the first lines are ticked
## --lab-picks <n> picker: tick the first n lines (default 2)
## --lab-sign      picker: sign it (the name stamp on "Requested by") and hold there
## --lab-fake <n>  picker: offer n made-up spells instead of the real ones (checks a long catalog)
## --lab-pest <k> force every contract's pest: grunt | archer | brute | swarmer | everything (the longest line, "Exterminate everything")
## --lab-long      the longest client / company names (board, invoice, tracker) and, unless --lab-pest says otherwise, the pest "everything"
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
			var board := JobBoard.new(_offers(a))
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
				p.requisition = {"job": "08137-PR", "client": "Hollis-Crane Continuity Holdings", "floor": "2 of 3"}
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
				"lines": ["Wine cellar sealed.", "Colin (valet) did not make it.", "Floor not clean: 24 %s left." % ClientArchetype.pest_name(_pest(a))]})
			add_child(e)
			opened = e
		"van":
			var v := VanExitMenu.new({"floor": 1, "floor_count": 3, "payout": 8400, "damages": 1200, "followers": 2,
				"lines": ["Hellgates closed on this floor: 1 of 2.", "Floor not clean: 24 %s left." % ClientArchetype.pest_name(_pest(a)),
					"Objectives not met do not pay. Damage comes out of what you earned."]})
			add_child(v)
			opened = v
		"invoice":
			var inv := _demo_invoice(a)
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
			var run := _lab_run(a)
			var rows: Array[Dictionary] = [
				{"text": "Close hellgates", "detail": "2 / 4", "state": "partial"},
				{"text": "ORIGIN gate", "detail": "OPEN", "state": "todo"},
				{"text": run.pest_label(), "detail": "24 left", "state": "todo"},
				{"text": "Employees", "detail": "2 rescued · 3 alive · 2 with you · 1 lost", "state": "fail"},
			]
			t.show_state("FLOOR 2 / 3", run.company, rows, 6000, 1500)
		"employees":
			_employee_mockups(a)


## --screen employees: mock-ups of the work order's Employees row (not shipped; the player's call). Columns: what the tracker
## says now (minus "with you"), then three options; rows: the worst case (2 rescued, 3 alive, 1 lost) and a typical one
## (1 rescued, 2 alive, 0 lost). Every slip is a real ObjectiveTracker, so the wrapping is real; the lost marks of option B
## are an overlay (the tracker has no such thing yet).
const EMPLOYEE_CASES := [{"name": "worst case", "rescued": 2, "alive": 3, "lost": 1}, {"name": "typical", "rescued": 1, "alive": 2, "lost": 0}]
const EMPLOYEE_OPTIONS := [
	{"id": "now", "title": "NOW (minus \"with you\")", "why": "what the tracker prints today, for comparison"},
	{"id": "a", "title": "A  WORDS, SHORTER", "why": "rescued and lost in words; alive is whatever is left, lost only when there is one"},
	{"id": "b", "title": "B  COUNT + LOST MARKS", "why": "rescued / total, with one red X per employee lost, drawn by hand"},
	{"id": "c", "title": "C  ONE COUNT", "why": "rescued / total only; a loss shows as the row's red text and X box"},
]


func _employee_mockups(a: PackedStringArray) -> void:
	var run := _lab_run(a)
	var x0 := 40.0
	var colw := 390.0
	var y0 := 56.0
	var rowh := 372.0
	for ci in EMPLOYEE_OPTIONS.size():
		var opt: Dictionary = EMPLOYEE_OPTIONS[ci]
		var head := FormTheme.label(str(opt["title"]), 22, Color(0.92, 0.88, 0.7), true)
		head.position = Vector2(x0 + colw * ci, 10)
		add_child(head)
		var why := FormTheme.small(str(opt["why"]), 17, Color(0.8, 0.78, 0.7))
		why.position = Vector2(x0 + colw * ci, y0 + 2 * rowh - 10)
		why.custom_minimum_size = Vector2(colw - 30, 0)
		why.size = Vector2(colw - 30, 60)
		add_child(why)
		for ri in EMPLOYEE_CASES.size():
			var c: Dictionary = EMPLOYEE_CASES[ri]
			var t := ObjectiveTracker.new()
			add_child(t)
			var emp := _employee_row(str(opt["id"]), int(c["rescued"]), int(c["alive"]), int(c["lost"]))
			var rows: Array[Dictionary] = [
				{"text": "Close hellgates", "detail": "2 / 4", "state": "partial"},
				{"text": run.pest_label(), "detail": "24 left", "state": "todo"},
				emp,
			]
			t.show_state("FLOOR 2 / 3", run.company, rows, 6000, 1500)
			var pos := Vector2(x0 + colw * ci, y0 + rowh * ri + 26.0)
			t.set_anchors_preset(Control.PRESET_TOP_LEFT)
			t.offset_left = pos.x
			t.offset_top = pos.y
			t.offset_right = pos.x + ObjectiveTracker.WIDTH
			t.offset_bottom = pos.y + t.custom_minimum_size.y
			var cap := FormTheme.label(str(c["name"]), 16, Color(0.7, 0.7, 0.75))
			cap.position = Vector2(pos.x, pos.y - 22.0)
			add_child(cap)
			if str(opt["id"]) == "b" and int(c["lost"]) > 0:
				var y := t.header_height()
				for i in 2:
					y += t.row_height(i)
				var m := _LostMarks.new()
				m.count = int(c["lost"])
				m.right_edge = ObjectiveTracker.WIDTH - ObjectiveTracker.PAD - FormTheme.label_font(true).get_string_size(str(emp["detail"]), HORIZONTAL_ALIGNMENT_LEFT, -1, ObjectiveTracker.DETAIL_SIZE).x - 8.0
				m.position = pos + Vector2(0, y)
				m.size = Vector2(ObjectiveTracker.WIDTH, t.row_height(2))
				add_child(m)


## The Employees row of option `id` for these counts (alive = still on the floor, not yet out).
func _employee_row(id: String, rescued: int, alive: int, lost: int) -> Dictionary:
	var total := rescued + alive + lost
	var state := "fail" if lost > 0 else ("done" if rescued > 0 and alive == 0 else "todo")
	var detail := ""
	match id:
		"now":
			var parts: Array[String] = []
			if rescued > 0:
				parts.append("%d rescued" % rescued)
			parts.append("%d alive" % alive)
			if lost > 0:
				parts.append("%d lost" % lost)
			detail = " · ".join(parts)
		"a":
			var parts: Array[String] = ["%d rescued" % rescued]
			if lost > 0:
				parts.append("%d lost" % lost)
			detail = " · ".join(parts)
		"b", "c":
			detail = "%d / %d" % [rescued, total]
	return {"text": "Employees", "detail": detail, "state": state}


## Option B's lost marks: one red grease X in a printed box per employee lost, left of the row's detail.
class _LostMarks extends Control:
	var count := 1
	var right_edge := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in count:
			var box := Rect2(right_edge - 22.0 * (i + 1), 6, 18, 18)
			draw_rect(box, Color(1, 1, 1, 0.45))
			draw_rect(box, FormTheme.INK, false, 2.0)
			FormTheme.draw_x(self, box, FormTheme.GREASE, 2.5)


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


## --lab-pest, else "everything" under --lab-long, else "" (leave each contract's own pest).
func _pest(a: PackedStringArray) -> String:
	var p := Boot.arg_value(a, "--lab-pest")
	if p != "":
		return p
	return "everything" if a.has("--lab-long") else ""


## `run` with the lab's pest forced (and its objectives rebuilt to match).
func _forced(run: ContractRun, a: PackedStringArray) -> ContractRun:
	var p := _pest(a)
	if p != "":
		run.pest = p
		run._build_objectives()
	return run


## The contract with the longest client + company line of its archetype `id` (seeds 1..300), at difficulty `diff`.
static func longest_run(id: String, diff: float) -> ContractRun:
	var best: ContractRun = null
	for s in range(1, 301):
		var r := ContractRun.make(id, s, diff)
		if best == null or r.client_name.length() + r.company.length() > best.client_name.length() + best.company.length():
			best = r
	return best


## Three offers for the board: the usual ones, or under --lab-long the longest names of three archetypes.
func _offers(a: PackedStringArray) -> Array[ContractRun]:
	var out: Array[ContractRun] = []
	if a.has("--lab-long"):
		var ids: Array[String] = ClientArchetype.IDS.duplicate()
		var scored: Array[ContractRun] = []
		for id in ids:
			scored.append(longest_run(id, 0.5))
		scored.sort_custom(func(x: ContractRun, y: ContractRun) -> bool: return x.client_name.length() + x.company.length() > y.client_name.length() + y.company.length())
		out.assign(scored.slice(0, ContractBoard.OFFER_COUNT))
	else:
		out = ContractBoard.offers(7)
	for r in out:
		_forced(r, a)
	return out


## The one contract a single-sheet screen (tracker, invoice) is built on.
func _lab_run(a: PackedStringArray) -> ContractRun:
	var seed_arg := Boot.arg_value(a, "--invoice-seed")
	var run: ContractRun
	if a.has("--lab-long") and seed_arg == "":
		var longest: ContractRun = null
		for id in ClientArchetype.IDS:
			var r := longest_run(id, 0.6)
			if longest == null or r.client_name.length() + r.company.length() > longest.client_name.length() + longest.company.length():
				longest = r
		run = longest
	else:
		run = ContractBoard.run_for_seed(int(seed_arg) if seed_arg != "" else 12)
	return _forced(run, a)


func _demo_invoice(a: PackedStringArray) -> Dictionary:
	var run := _lab_run(a)
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
	var down_arg := Boot.arg_value(a, "--invoice-down")
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
