class_name JobBoard
extends Control
## The dispatch job board: three contract offers as job cards (client, site, story, objectives and pay,
## floors, difficulty stars, a property warning). Pick one with the mouse or the keys 1-3. Add it under
## a Control (Hud.add_overlay) or a CanvasLayer's root Control. Emits picked(run).

signal picked(run: ContractRun)

const BG := Color(0.045, 0.05, 0.075)
const CARD_BG := Color(0.095, 0.105, 0.15)
const CARD_BG_HOVER := Color(0.13, 0.145, 0.205)
const TEXT := Color(0.93, 0.94, 0.98)
const DIM := Color(0.62, 0.65, 0.76)
const MONEY := Color(0.55, 0.92, 0.62)
const WARN := Color(1.0, 0.8, 0.3)
const CARD_W := 480.0

var offers: Array[ContractRun] = []
var _cards: Array[PanelContainer] = []
var _styles: Array[StyleBoxFlat] = []
var _hover := -1


func _init(new_offers: Array[ContractRun] = []) -> void:
	offers = new_offers


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)

	var title := _label("DISPATCH  |  AVAILABLE CONTRACTS", 38, TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := _label("Pick a job with the mouse or keys 1-3. Every job is billed per objective; property damage comes out of your pay.", 17, DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	for i in offers.size():
		row.add_child(_make_card(offers[i], i))

	var foot := _label("Leaving a job early always works. Unmet objectives do not pay. Pay never goes below $0.", 15, DIM)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foot)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var idx: int = int(event.keycode) - KEY_1
	if idx >= 0 and idx < offers.size():
		choose(idx)
		get_viewport().set_input_as_handled()


## Take offer `index` (mouse click or the key).
func choose(index: int) -> void:
	if index >= 0 and index < offers.size():
		picked.emit(offers[index])


# --- Cards ----------------------------------------------------------------------------------

func _make_card(run: ContractRun, index: int) -> Control:
	var accent := ClientArchetype.accent_of(run.archetype_id)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CARD_W, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = accent.darkened(0.15)
	sb.set_border_width_all(2)
	sb.border_width_top = 8
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	_cards.append(panel)
	_styles.append(sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			choose(index))
	panel.mouse_entered.connect(func() -> void: _set_hover(index, accent))
	panel.mouse_exited.connect(func() -> void: _set_hover(-1, accent))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)

	# Header: job number + difficulty stars.
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	head.add_child(_label("JOB %d   %s" % [index + 1, run.invoice_number.replace("INV", "REF")], 14, DIM, true))
	var stars := StarRow.new()
	stars.value = run.difficulty_stars()
	stars.count = 5
	stars.star_size = 17.0
	stars.on_color = Color(1.0, 0.45, 0.35)
	stars.off_color = Color(1, 1, 1, 0.14)
	stars.custom_minimum_size = stars.wanted_size()
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(stars)
	head.add_child(_label("  danger", 14, DIM))

	var name_l := _label(run.client_name, 24, TEXT)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name_l)
	v.add_child(_label(run.company, 16, DIM))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(chips)
	chips.add_child(_chip(run.archetype_title().to_upper(), accent))
	chips.add_child(_chip("BUNKER" if run.site_type == "bunker" else "VILLAIN LAIR", Color(0.35, 0.4, 0.55)))
	chips.add_child(_chip("3 FLOORS", Color(0.35, 0.4, 0.55)))
	v.add_child(_gap(4))

	var story := _label("%s" % str(run.story["event"]), 16, Color(0.82, 0.84, 0.92))
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size = Vector2(CARD_W - 44, 0)
	v.add_child(story)
	v.add_child(_label("Origin: the %s (floor 3)." % str(run.story["origin"]), 14, DIM))
	v.add_child(_gap(4))

	v.add_child(_label("OBJECTIVES", 13, DIM, true))
	for line in run.card_lines():
		v.add_child(_objective_row(line))
	v.add_child(_gap(2))

	var value_row := HBoxContainer.new()
	value_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(value_row)
	var vl := _label("Contract value", 16, DIM)
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_row.add_child(vl)
	value_row.add_child(_label(ContractRun.money(run.contract_value), 26, MONEY))

	var warn := PanelContainer.new()
	var wsb := StyleBoxFlat.new()
	wsb.bg_color = Color(0.2, 0.15, 0.04)
	wsb.border_color = WARN.darkened(0.2)
	wsb.border_width_left = 5
	wsb.content_margin_left = 12
	wsb.content_margin_right = 10
	wsb.content_margin_top = 6
	wsb.content_margin_bottom = 6
	warn.add_theme_stylebox_override("panel", wsb)
	warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wl := _label(str(ClientArchetype.get_data(run.archetype_id)["warning"]), 14, WARN)
	wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wl.custom_minimum_size = Vector2(CARD_W - 70, 0)
	warn.add_child(wl)
	v.add_child(warn)
	v.add_child(_label("Damages are deducted, up to %s." % ContractRun.money(run.contract_value), 13, DIM))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	var take := Button.new()
	take.text = "TAKE JOB  [%d]" % (index + 1)
	take.custom_minimum_size = Vector2(0, 46)
	take.focus_mode = Control.FOCUS_NONE
	take.add_theme_font_size_override("font_size", 22)
	take.pressed.connect(func() -> void: choose(index))
	for state in ["normal", "hover", "pressed"]:
		var b := StyleBoxFlat.new()
		b.bg_color = accent.darkened(0.45 if state == "normal" else 0.25)
		b.set_corner_radius_all(6)
		take.add_theme_stylebox_override(state, b)
	v.add_child(take)
	return panel


func _objective_row(line: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(str(line["label"]), 15, TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var pay := ContractRun.money(int(line["pay"]))
	if line.has("alive"):
		pay = "%s / %s" % [ContractRun.money(int(line["alive"])), ContractRun.money(int(line["pay"]))]
	elif bool(line["each"]):
		pay += " each"
	row.add_child(_label(pay, 15, MONEY))
	return row


func _chip(text: String, color: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.35)
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_label(text, 12, Color(0.95, 0.95, 1.0)))
	return p


func _set_hover(index: int, _accent: Color) -> void:
	_hover = index
	for i in _styles.size():
		_styles[i].bg_color = CARD_BG_HOVER if i == index else CARD_BG


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _label(text: String, size: int, color: Color, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_color_override("font_outline_color", color)
		l.add_theme_constant_override("outline_size", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A row of drawn stars (no font glyphs needed). `value` of `count` are lit.
class StarRow:
	extends Control
	var value := 0:
		set(v):
			value = v
			queue_redraw()
	var count := 3
	var star_size := 18.0
	var on_color := Color(1.0, 0.82, 0.25)
	var off_color := Color(0, 0, 0, 0.15)

	func wanted_size() -> Vector2:
		return Vector2((star_size + 3.0) * count, star_size + 2.0)

	func _draw() -> void:
		var r := star_size * 0.5
		for i in count:
			var c := Vector2(r + 1.0 + i * (star_size + 3.0), r + 1.0)
			draw_colored_polygon(star_points(c, r), on_color if i < value else off_color)

	static func star_points(c: Vector2, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI * 0.5 + k * PI / 5.0
			var rr := r if k % 2 == 0 else r * 0.42
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		return pts
