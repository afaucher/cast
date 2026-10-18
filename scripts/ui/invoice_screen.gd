class_name InvoiceScreen
extends Control
## The end-of-contract summary, drawn as FORM 99 (the carbon-copy family, scripts/ui/forms/): a paper invoice
## with the client's company in the header block, invoice number and date, BILL TO, line items per floor
## (earned), an itemised deductions section with the culprit named, "Damages (capped at contract value)", a
## subtotal, the crew revival fee (corporate revives every hero still down at the end; billed to the client,
## uncapped, so NET PAYOUT can be negative and then prints in red with a minus sign), NET PAYOUT, a deadpan footer note from the client and a 1-3 star rating stamp. To the right on a
## canary slip: the crew debrief (credit and blame) and the row back to the job board.
##
## Data comes from ContractInvoice.build(). Add under a Control (Hud.add_overlay). Emits next_contract.

signal next_contract

const INK := FormTheme.TYPED
const INK_DIM := Color(0.114, 0.102, 0.149, 0.62)
const RED := FormTheme.RED
const GREEN := FormTheme.GREEN_INK
const BG := Color(0.065, 0.055, 0.07)
const PAPER_W := 1000.0
const SIDE_W := 340.0

## Earned + damage + revival rows that fit on one screen with NET PAYOUT in view (1280x720). Over this, each floor's
## earned lines fold into one row per floor, then (if still over) the damages fold into one row per culprit (fit_rows).
const ROW_BUDGET := 13

## Keys are ignored for this long after the screen appears (so a held key cannot skip it).
const INPUT_GUARD_MS := 900

var inv: Dictionary = {}
var next_button: FormRow = null
var _born_ms := 0
var _accent := Color(0.2, 0.3, 0.5)
var _scroll: ScrollContainer = null


func _init(data: Dictionary = {}) -> void:
	inv = data


func _ready() -> void:
	_born_ms = Time.get_ticks_msec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = FormTheme.theme()
	_accent = ClientArchetype.accent_of(str(inv.get("archetype", "prepper")))
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(PAPER_W + 24.0, 860)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(_scroll)
	_scroll.add_child(FormTheme.margin(_build_paper(), 6, 6, 14, 14))
	row.add_child(_build_side())
	get_tree().create_timer(INPUT_GUARD_MS / 1000.0, true).timeout.connect(_grab_next)


func _grab_next() -> void:
	if is_inside_tree() and next_button != null and get_viewport().gui_get_focus_owner() == null:
		next_button.grab_focus()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and Time.get_ticks_msec() - _born_ms > INPUT_GUARD_MS:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
			next_contract.emit()
			get_viewport().set_input_as_handled()
			return
	# Up / Down (and the controller's stick) scroll the paper when it is taller than the screen.
	if _scroll != null and event.is_action_pressed("ui_down", true):
		_scroll.scroll_vertical += 90
	elif _scroll != null and event.is_action_pressed("ui_up", true):
		_scroll.scroll_vertical -= 90


# --- The document -----------------------------------------------------------------------------

func _build_paper() -> Control:
	var paper := PaperPanel.new(FormTheme.carbon("white"))
	paper.custom_minimum_size = Vector2(PAPER_W, 0)
	paper.set_padding(0, 0, 0, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	paper.add_child(v)

	# Header block: FORM 99, the client's company, INVOICE and the number.
	var head := FormHeader.new("99", "Invoice", str(inv["company"]), "No.", str(inv["number"]), 42)
	v.add_child(head)
	var accent := ColorRect.new()
	accent.color = _accent
	accent.custom_minimum_size = Vector2(0, 6)
	v.add_child(accent)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 3)
	v.add_child(FormTheme.margin(inner, 36, 12, 36, 14))

	var sub := HBoxContainer.new()
	var sub_l := FormTheme.typed("%s  |  %s" % [str(inv["dept"]), str(inv["address"])], 15, INK_DIM, false)
	sub_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_l.clip_text = true
	sub.add_child(sub_l)
	sub.add_child(FormTheme.typed("Date: %s" % str(inv["date"]), 16, INK, true))
	inner.add_child(sub)
	var tag_row := HBoxContainer.new()
	var tag := FormTheme.typed("\"%s\"" % str(inv["tagline"]), 15, INK_DIM, false)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.clip_text = true
	tag_row.add_child(tag)
	tag_row.add_child(FormTheme.typed("Terms: net $0 (paid on completion)", 15, INK_DIM, false))
	inner.add_child(tag_row)

	# BILL TO / VENDOR / SITE.
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 24)
	inner.add_child(meta)
	meta.add_child(_meta_box("BILL TO", [str(inv["client"]), str(inv["company"]), "Attn: Accounts Payable"]))
	meta.add_child(_meta_box("VENDOR", [str(inv["vendor"]), "Licensed sorcery, billed by the job", "Crew of three, headsets included"]))
	var status := "Cashed out on floor %d of %d" % [int(inv.get("floor_reached", 1)), ContractRun.FLOOR_COUNT]
	if str(inv["reason"]) == ContractSession.END_INCAPACITATED:
		status = "Crew incapacitated on floor %d of %d" % [int(inv.get("floor_reached", 1)), ContractRun.FLOOR_COUNT]
	meta.add_child(_meta_box("SITE / STATUS", [str(inv["site"]), status, "Contract value %s" % ContractRun.money(int(inv["contract_value"]))]))

	# Line items.
	inner.add_child(_header_band("LINE ITEMS (EARNED)"))
	var grid := _grid()
	inner.add_child(grid)
	var revivals: Array = inv.get("revivals", [])
	var fitted := fit_rows(inv["floors"], inv["deductions"], ROW_BUDGET, revivals.size() + 1 if not revivals.is_empty() else 0)
	var floors: Array = fitted["floors"]
	if floors.is_empty():
		_row(grid, "", "No billable work completed.", "", "$0", INK_DIM)
	for sec: Dictionary in floors:
		var first := true
		for r: Dictionary in sec["rows"]:
			_row(grid, "FL %d" % int(sec["floor"]) if first else "", str(r["label"]), "x%d" % int(r["qty"]), ContractRun.money(int(r["amount"])), INK)
			first = false
	inner.add_child(_rule())
	inner.add_child(_total_line("SUBTOTAL (EARNED)", ContractRun.money(int(inv["earned"])), INK, 20))

	# Deductions.
	inner.add_child(_header_band("DEDUCTIONS: PROPERTY DAMAGE"))
	var dgrid := _grid()
	inner.add_child(dgrid)
	var ded: Array = fitted["deductions"]
	if ded.is_empty():
		_row(dgrid, "", "No property damage reported. (We checked twice.)", "", "$0", INK_DIM)
	for d: Dictionary in ded:
		_row(dgrid, "", "%s - %s" % [str(d["label"]), str(d["who"])], "x%d" % int(d["qty"]), "-" + ContractRun.money(int(d["amount"])), RED)
	inner.add_child(_rule())
	if bool(inv["capped"]):
		inner.add_child(_total_line("Total damages (uncapped)", "-" + ContractRun.money(int(inv["damages"])), INK_DIM, 18))
	var cap_text := "Damages (capped at contract value %s)" % ContractRun.money(int(inv["contract_value"]))
	inner.add_child(_total_line(cap_text, "-" + ContractRun.money(int(inv["deducted"])), RED, 20))

	# Crew revival: corporate revives each hero still down at the end and bills the client. Not capped.
	if not revivals.is_empty():
		if int(inv["earned"]) < int(inv["deducted"]):   # the $0 floor bit: say so, or the net below would not add up
			inner.add_child(_total_line("Pay after damages (never below $0)", "$0", INK_DIM, 18))
		inner.add_child(_header_band("CREW REVIVAL (CORPORATE)"))
		var rgrid := _grid()
		inner.add_child(rgrid)
		for rv: Dictionary in revivals:
			_row(rgrid, "", str(rv["label"]), "x1", "-" + ContractRun.money(int(rv["amount"])), RED)
		inner.add_child(_total_line("Revival fees (billed in full, no cap)", "-" + ContractRun.money(int(inv["revival_fees"])), RED, 20))

	# NET PAYOUT with the rating stamp.
	var net_row := HBoxContainer.new()
	net_row.add_theme_constant_override("separation", 16)
	inner.add_child(net_row)
	var stamp_holder := Control.new()
	stamp_holder.custom_minimum_size = Vector2(280, 124)
	stamp_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	net_row.add_child(stamp_holder)
	var stamp := FormStamp.new("RATED", 26, -7.5, int(inv["stars"]))
	stamp.footer = _verdict()
	stamp.position = Vector2(14, -6)
	stamp.size = stamp.get_combined_minimum_size()
	stamp_holder.add_child(stamp)
	var net := PanelContainer.new()
	net.add_theme_stylebox_override("panel", FormTheme.box_style(Color(1, 1, 1, 0.45), INK, 3.0, 24.0, 8.0))
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -4)
	net.add_child(nv)
	var nl := FormTheme.label("NET PAYOUT", 20, FormTheme.INK, true)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nv.add_child(nl)
	var pay_l := FormTheme.typed(ContractRun.money(int(inv["payout"])), 54, GREEN if int(inv["payout"]) > 0 else RED)   # money() prints the minus sign
	pay_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nv.add_child(pay_l)
	net_row.add_child(net)

	# Footer: the client's note.
	inner.add_child(_rule())
	var note := FormTheme.typed_wrapped("\"%s\"" % str(inv["footer"]), 19, INK, true)
	note.custom_minimum_size = Vector2(PAPER_W - 90, 0)
	inner.add_child(note)
	inner.add_child(FormTheme.typed("- %s, %s" % [str(inv["client"]), str(inv["dept"])], 16, INK_DIM, false))
	return paper


func _verdict() -> String:
	if str(inv["reason"]) == ContractSession.END_INCAPACITATED:
		return "CREW INCAPACITATED"
	match int(inv["stars"]):
		3: return "EXCELLENT"
		2: return "ACCEPTABLE"
	return "UNSATISFACTORY"


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 0)
	return g


func _row(grid: GridContainer, floor_text: String, desc: String, qty: String, amount: String, color: Color) -> void:
	var f := _t(floor_text, 17, FormTheme.INK)
	f.custom_minimum_size = Vector2(60, 0)
	f.add_theme_font_override("font", FormTheme.label_font(true))
	grid.add_child(f)
	var d := _t(desc, 18, color)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.custom_minimum_size = Vector2(600, 0)
	d.clip_text = true
	grid.add_child(d)
	var q := _t(qty, 18, INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	q.custom_minimum_size = Vector2(60, 0)
	grid.add_child(q)
	var a := _t(amount, 18, color, HORIZONTAL_ALIGNMENT_RIGHT)
	a.custom_minimum_size = Vector2(150, 0)
	grid.add_child(a)


func _total_line(label_text: String, amount: String, color: Color, size: int) -> Control:
	var h := HBoxContainer.new()
	var l := _t(label_text, size, color, HORIZONTAL_ALIGNMENT_RIGHT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var a := _t(amount, size, color, HORIZONTAL_ALIGNMENT_RIGHT)
	a.custom_minimum_size = Vector2(170, 0)
	h.add_child(a)
	return h


func _header_band(text: String) -> Control:
	var p := PanelContainer.new()
	var sb := FormTheme.box_style(Color(FormTheme.INK, 0.12), FormTheme.INK, 0.0, 10.0, 3.0)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(FormTheme.label(text, 19, FormTheme.INK, true))
	return p


func _rule() -> Control:
	return FormTheme.rule(2.0, Color(FormTheme.INK, 0.7))


func _meta_box(title: String, lines: Array) -> Control:
	var b := VBoxContainer.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_constant_override("separation", 0)
	b.add_child(FormTheme.label(title, 18, FormTheme.INK, true))
	for i in lines.size():
		var l := _t(str(lines[i]), 18 if i == 0 else 15, INK if i == 0 else INK_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # long client / company names wrap instead of being cut off
		b.add_child(l)
	return b


## Fold the invoice's rows so earned + damage rows (plus `extra_rows`, the revival section's header and rows, which
## never fold) fit ROW_BUDGET: first each floor's earned lines become one "Floor n work" row (qty = items, amount =
## the floor's total), then the damages become one row per culprit.
## Totals never change. Returns {floors, deductions} in the same shapes ContractInvoice.build() uses.
static func fit_rows(floors: Array, ded: Array, budget: int = ROW_BUDGET, extra_rows: int = 0) -> Dictionary:
	var earned_rows := 0
	for sec: Dictionary in floors:
		earned_rows += (sec["rows"] as Array).size()
	var out_floors := floors
	if earned_rows + ded.size() + extra_rows > budget:
		out_floors = []
		for sec: Dictionary in floors:
			var qty := 0
			var amount := 0
			for r: Dictionary in sec["rows"]:
				qty += int(r["qty"])
				amount += int(r["amount"])
			out_floors.append({"floor": sec["floor"], "rows": [{"label": "Floor %d work" % int(sec["floor"]), "qty": qty, "amount": amount}]})
		earned_rows = out_floors.size()
	var out_ded := ded
	if earned_rows + ded.size() + extra_rows > budget:
		var by_who: Dictionary = {}
		var order: Array[String] = []
		for d: Dictionary in ded:
			var who := str(d["who"])
			if not by_who.has(who):
				by_who[who] = {"label": "Damage", "who": who, "qty": 0, "amount": 0}
				order.append(who)
			var row: Dictionary = by_who[who]
			row["qty"] = int(row["qty"]) + int(d["qty"])
			row["amount"] = int(row["amount"]) + int(d["amount"])
		out_ded = []
		for who in order:
			out_ded.append(by_who[who])
		out_ded.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["amount"]) > int(b["amount"]))
	return {"floors": out_floors, "deductions": out_ded}


## A typed line.
func _t(text: String, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := FormTheme.typed(text, size, color, size >= 18 and color != INK_DIM)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.horizontal_alignment = align as HorizontalAlignment
	return l


# --- Crew debrief (a canary slip) ---------------------------------------------------------------

func _build_side() -> Control:
	var slip := PaperPanel.new(FormTheme.carbon("canary"))
	slip.custom_minimum_size = Vector2(SIDE_W + 40.0, 0)
	slip.set_padding(22, 18, 22, 22)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	slip.add_child(v)
	v.add_child(FormTheme.label("FORM 99-B", 18, FormTheme.INK, true))
	v.add_child(FormTheme.label("CREW DEBRIEF", 38, FormTheme.INK, true))
	v.add_child(FormTheme.small("The pot is shared. The blame is not.", 18))
	v.add_child(FormTheme.rule(3.0))
	v.add_child(FormTheme.gap(4))
	v.add_child(FormTheme.label("PROPERTY DAMAGE BY CULPRIT", 17, FormTheme.INK, true))
	var blame: Array = inv["blame"]
	if blame.is_empty():
		v.add_child(_side_t("Nobody. Remarkable.", 20, GREEN))
	for b: Dictionary in blame:
		var h := HBoxContainer.new()
		var n := _side_t(str(b["who"]), 20, INK)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		h.add_child(_side_t("-" + ContractRun.money(int(b["amount"])), 20, RED))
		v.add_child(h)
	var downed: Array = inv.get("revivals", [])
	if not downed.is_empty():
		v.add_child(FormTheme.gap(6))
		v.add_child(FormTheme.label("DOWN AT THE END", 17, FormTheme.INK, true))
		for rv: Dictionary in downed:
			var rh := HBoxContainer.new()
			var rn := _side_t("%s (revived)" % str(rv["who"]), 20, INK)
			rn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rh.add_child(rn)
			rh.add_child(_side_t("-" + ContractRun.money(int(rv["amount"])), 20, RED))
			v.add_child(rh)
	v.add_child(FormTheme.gap(6))
	v.add_child(FormTheme.label("EMPLOYEES", 17, FormTheme.INK, true))
	var e: Dictionary = inv["employees"]
	v.add_child(_side_t("%d extracted ($100 each)" % int(e["extracted"]), 19, INK))
	v.add_child(_side_t("%d still alive ($10 each)" % int(e["alive"]), 19, INK))
	v.add_child(_side_t("%d lost" % int(e["lost"]), 19, RED if int(e["lost"]) > 0 else INK))
	if int(e["lost"]) > 0 and str(e["lost_causes"]) != "":
		var cause := _side_t("Cause: %s." % str(e["lost_causes"]), 17, INK_DIM)
		cause.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cause.custom_minimum_size = Vector2(SIDE_W, 0)
		v.add_child(cause)
	v.add_child(FormTheme.gap(18))
	next_button = FormRow.new("Next contract", "Enter", "")
	next_button.label_size = 26
	next_button.row_h = 66.0
	next_button.pressed.connect(func() -> void: next_contract.emit())
	v.add_child(next_button)
	slip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return slip


func _side_t(text: String, size: int, color: Color) -> Label:
	var l := FormTheme.typed(text, size, color, size >= 19)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l
