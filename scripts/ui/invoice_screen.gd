class_name InvoiceScreen
extends Control
## The end-of-contract summary, drawn as a real invoice: a paper-white document on a dark background
## with the client's letterhead, invoice number and date, BILL TO, line items per floor (earned), an
## itemised deductions section with the culprit named, "Damages (capped at contract value)", a
## subtotal, NET PAYOUT, a deadpan footer note from the client and a 1-3 star rating stamp. To the right
## on the dark background: the crew debrief (credit and blame) and the button back to the job board.
##
## Data comes from ContractInvoice.build(). Add under a Control (Hud.add_overlay). Emits next_contract.

signal next_contract

const PAPER := Color(0.965, 0.955, 0.925)
const PAPER_BAND := Color(0.885, 0.875, 0.845)
const INK := Color(0.11, 0.12, 0.17)
const INK_DIM := Color(0.4, 0.41, 0.46)
const RED := Color(0.72, 0.13, 0.15)
const GREEN := Color(0.12, 0.45, 0.25)
const BG := Color(0.04, 0.045, 0.065)
const PAPER_W := 900.0
const SIDE_W := 340.0

## Keys are ignored for this long after the screen appears (so a held key cannot skip it).
const INPUT_GUARD_MS := 900

var inv: Dictionary = {}
var _born_ms := 0
var _accent := Color(0.2, 0.3, 0.5)


func _init(data: Dictionary = {}) -> void:
	inv = data


func _ready() -> void:
	_born_ms = Time.get_ticks_msec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
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

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PAPER_W + 14.0, 872)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	scroll.add_child(_build_paper())
	row.add_child(_build_side())


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and Time.get_ticks_msec() - _born_ms > INPUT_GUARD_MS:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
			next_contract.emit()
			get_viewport().set_input_as_handled()


# --- The document -----------------------------------------------------------------------------

func _build_paper() -> Control:
	var paper := PanelContainer.new()
	paper.custom_minimum_size = Vector2(PAPER_W, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.set_corner_radius_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 12
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 18
	sb.content_margin_bottom = 14
	paper.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	paper.add_child(v)

	# Letterhead: the client's company on the left, INVOICE + number + date on the right.
	var head := HBoxContainer.new()
	v.add_child(head)
	var lh := VBoxContainer.new()
	lh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_theme_constant_override("separation", 0)
	head.add_child(lh)
	lh.add_child(_t(str(inv["company"]), 28, _accent.darkened(0.2)))
	lh.add_child(_t("%s  |  %s" % [str(inv["dept"]), str(inv["address"])], 13, INK_DIM))
	lh.add_child(_t("\"%s\"" % str(inv["tagline"]), 13, INK_DIM))
	var rh := VBoxContainer.new()
	rh.add_theme_constant_override("separation", 0)
	head.add_child(rh)
	rh.add_child(_t("INVOICE", 40, INK, HORIZONTAL_ALIGNMENT_RIGHT))
	rh.add_child(_t("No. %s" % str(inv["number"]), 16, INK, HORIZONTAL_ALIGNMENT_RIGHT))
	rh.add_child(_t("Date: %s" % str(inv["date"]), 16, INK, HORIZONTAL_ALIGNMENT_RIGHT))
	rh.add_child(_t("Terms: net $0 (paid on completion)", 12, INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	var bar := ColorRect.new()
	bar.color = _accent
	bar.custom_minimum_size = Vector2(0, 4)
	v.add_child(bar)

	# BILL TO / VENDOR / SITE.
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 20)
	v.add_child(meta)
	meta.add_child(_meta_box("BILL TO", [str(inv["client"]), str(inv["company"]), "Attn: Accounts Payable"]))
	meta.add_child(_meta_box("VENDOR", [str(inv["vendor"]), "Licensed sorcery, per diem", "Crew of three, headsets included"]))
	var status := "Cashed out on floor %d of %d" % [int(inv.get("floor_reached", 1)), ContractRun.FLOOR_COUNT]
	if str(inv["reason"]) == ContractSession.END_INCAPACITATED:
		status = "Crew incapacitated on floor %d of %d" % [int(inv.get("floor_reached", 1)), ContractRun.FLOOR_COUNT]
	meta.add_child(_meta_box("SITE / STATUS", [str(inv["site"]), status, "Contract value %s" % ContractRun.money(int(inv["contract_value"]))]))

	# Line items.
	v.add_child(_header_band("LINE ITEMS (EARNED)"))
	var grid := _grid()
	v.add_child(grid)
	var floors: Array = inv["floors"]
	if floors.is_empty():
		_row(grid, "", "No billable work completed.", "", "$0", INK_DIM)
	for sec: Dictionary in floors:
		var first := true
		for r: Dictionary in sec["rows"]:
			_row(grid, "FL %d" % int(sec["floor"]) if first else "", str(r["label"]), "x%d" % int(r["qty"]), ContractRun.money(int(r["amount"])), INK)
			first = false
	v.add_child(_rule())
	v.add_child(_total_line("SUBTOTAL (EARNED)", ContractRun.money(int(inv["earned"])), INK, 17))

	# Deductions.
	v.add_child(_header_band("DEDUCTIONS: PROPERTY DAMAGE"))
	var dgrid := _grid()
	v.add_child(dgrid)
	var ded: Array = inv["deductions"]
	if ded.is_empty():
		_row(dgrid, "", "No property damage reported. (We checked twice.)", "", "$0", INK_DIM)
	for d: Dictionary in ded:
		_row(dgrid, "", "%s - %s" % [str(d["label"]), str(d["who"])], "x%d" % int(d["qty"]), "-" + ContractRun.money(int(d["amount"])), RED)
	v.add_child(_rule())
	if bool(inv["capped"]):
		v.add_child(_total_line("Total damages (uncapped)", "-" + ContractRun.money(int(inv["damages"])), INK_DIM, 15))
	var cap_text := "Damages (capped at contract value %s)" % ContractRun.money(int(inv["contract_value"]))
	v.add_child(_total_line(cap_text, "-" + ContractRun.money(int(inv["deducted"])), RED, 17))

	# NET PAYOUT with the rating stamp.
	var net_row := HBoxContainer.new()
	net_row.add_theme_constant_override("separation", 16)
	v.add_child(net_row)
	var stamp_holder := Control.new()
	stamp_holder.custom_minimum_size = Vector2(250, 96)
	stamp_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	net_row.add_child(stamp_holder)
	var stamp := Stamp.new()
	stamp.stars = int(inv["stars"])
	stamp.verdict = _verdict()
	stamp.size = Vector2(250, 96)
	stamp.position = Vector2(4, 4)
	stamp.pivot_offset = stamp.size * 0.5
	stamp.rotation = -0.13
	stamp_holder.add_child(stamp)
	var net := PanelContainer.new()
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color(1, 1, 1, 0.6)
	nsb.border_color = INK
	nsb.set_border_width_all(3)
	nsb.content_margin_left = 22
	nsb.content_margin_right = 22
	nsb.content_margin_top = 8
	nsb.content_margin_bottom = 8
	net.add_theme_stylebox_override("panel", nsb)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -2)
	net.add_child(nv)
	nv.add_child(_t("NET PAYOUT", 16, INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	nv.add_child(_t(ContractRun.money(int(inv["payout"])), 48, GREEN if int(inv["payout"]) > 0 else RED, HORIZONTAL_ALIGNMENT_RIGHT))
	net_row.add_child(net)

	# Footer: the client's note.
	v.add_child(_rule())
	var note := _t("\"%s\"" % str(inv["footer"]), 16, INK)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(PAPER_W - 90, 0)
	v.add_child(note)
	v.add_child(_t("- %s, %s" % [str(inv["client"]), str(inv["dept"])], 13, INK_DIM))
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
	var f := _t(floor_text, 14, INK_DIM)
	f.custom_minimum_size = Vector2(54, 0)
	grid.add_child(f)
	var d := _t(desc, 15, color)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.custom_minimum_size = Vector2(500, 0)
	d.clip_text = true
	grid.add_child(d)
	var q := _t(qty, 15, INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	q.custom_minimum_size = Vector2(60, 0)
	grid.add_child(q)
	var a := _t(amount, 15, color, HORIZONTAL_ALIGNMENT_RIGHT)
	a.custom_minimum_size = Vector2(130, 0)
	grid.add_child(a)


func _total_line(label: String, amount: String, color: Color, size: int) -> Control:
	var h := HBoxContainer.new()
	var l := _t(label, size, color, HORIZONTAL_ALIGNMENT_RIGHT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var a := _t(amount, size, color, HORIZONTAL_ALIGNMENT_RIGHT)
	a.custom_minimum_size = Vector2(150, 0)
	h.add_child(a)
	return h


func _header_band(text: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER_BAND
	sb.content_margin_left = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_t(text, 14, INK))
	return p


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(INK.r, INK.g, INK.b, 0.35)
	r.custom_minimum_size = Vector2(0, 1)
	return r


func _meta_box(title: String, lines: Array) -> Control:
	var b := VBoxContainer.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_constant_override("separation", 0)
	b.add_child(_t(title, 12, _accent.darkened(0.1)))
	for i in lines.size():
		var l := _t(str(lines[i]), 15 if i == 0 else 13, INK if i == 0 else INK_DIM)
		l.clip_text = true
		b.add_child(l)
	return b


func _t(text: String, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align as HorizontalAlignment
	return l


# --- Crew debrief (dark side) -------------------------------------------------------------------

func _build_side() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(SIDE_W, 0)
	v.add_theme_constant_override("separation", 10)
	v.add_child(_side_t("CREW DEBRIEF", 28, Color(0.93, 0.94, 0.98)))
	v.add_child(_side_t("The pot is shared. The blame is not.", 14, Color(0.62, 0.65, 0.76)))
	v.add_child(_side_gap(6))
	v.add_child(_side_t("PROPERTY DAMAGE BY CULPRIT", 13, Color(0.62, 0.65, 0.76)))
	var blame: Array = inv["blame"]
	if blame.is_empty():
		v.add_child(_side_t("Nobody. Remarkable.", 17, Color(0.55, 0.92, 0.62)))
	for b: Dictionary in blame:
		var h := HBoxContainer.new()
		var n := _side_t(str(b["who"]), 18, Color(0.93, 0.94, 0.98))
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		h.add_child(_side_t("-" + ContractRun.money(int(b["amount"])), 18, Color(1.0, 0.5, 0.45)))
		v.add_child(h)
	v.add_child(_side_gap(6))
	v.add_child(_side_t("EMPLOYEES", 13, Color(0.62, 0.65, 0.76)))
	var e: Dictionary = inv["employees"]
	v.add_child(_side_t("%d extracted ($100 each)" % int(e["extracted"]), 17, Color(0.93, 0.94, 0.98)))
	v.add_child(_side_t("%d still alive ($10 each)" % int(e["alive"]), 17, Color(0.93, 0.94, 0.98)))
	var lost_line := _side_t("%d lost" % int(e["lost"]), 17, Color(1.0, 0.5, 0.45) if int(e["lost"]) > 0 else Color(0.93, 0.94, 0.98))
	v.add_child(lost_line)
	if int(e["lost"]) > 0 and str(e["lost_causes"]) != "":
		var cause := _side_t("Cause: %s." % str(e["lost_causes"]), 15, Color(0.62, 0.65, 0.76))
		cause.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cause.custom_minimum_size = Vector2(SIDE_W, 0)
		v.add_child(cause)
	v.add_child(_side_gap(18))
	var next := Button.new()
	next.text = "NEXT CONTRACT   [Enter]"
	next.custom_minimum_size = Vector2(0, 58)
	next.focus_mode = Control.FOCUS_NONE
	next.add_theme_font_size_override("font_size", 22)
	for state in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.2, 0.5, 0.3).darkened(0.25 if state == "normal" else 0.05)
		s.border_color = Color(0.4, 0.8, 0.5)
		s.set_border_width_all(2)
		s.set_corner_radius_all(6)
		next.add_theme_stylebox_override(state, s)
	next.pressed.connect(func() -> void: next_contract.emit())
	v.add_child(next)
	return v


func _side_t(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _side_gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## The rubber stamp: a double border, the verdict and 1-3 stars, tilted.
class Stamp:
	extends Control
	var stars := 1
	var verdict := ""
	const INK := Color(0.75, 0.12, 0.18, 0.82)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, INK, false, 4.0)
		draw_rect(r.grow(-7), INK, false, 1.5)
		var font := ThemeDB.fallback_font
		var t := "RATED"
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(font, Vector2((size.x - tw) * 0.5, 28), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
		var star_size := 26.0
		var total := star_size * 3.0 + 12.0
		var x0 := (size.x - total) * 0.5
		for i in 3:
			var c := Vector2(x0 + star_size * 0.5 + i * (star_size + 6.0), 48)
			draw_colored_polygon(JobBoard.StarRow.star_points(c, star_size * 0.5), INK if i < stars else Color(INK.r, INK.g, INK.b, 0.18))
		var vf := 17 if verdict.length() < 15 else 14
		var vw := font.get_string_size(verdict, HORIZONTAL_ALIGNMENT_LEFT, -1, vf).x
		draw_string(font, Vector2((size.x - vw) * 0.5, 82), verdict, HORIZONTAL_ALIGNMENT_LEFT, -1, vf, INK)
