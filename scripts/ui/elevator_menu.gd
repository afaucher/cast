class_name ElevatorMenu
extends Control
## The freight elevator prompt that opens when the crew steps on the exit cell:
##   [1] Go down to floor N (more pay, more danger)     (not offered on the last floor)
##   [2] Cash out
##   [Esc] Stay on this floor
## Followers near the elevator ride along (extracted, $100 each). Cashing out is always available.
## Add under a Control (Hud.add_overlay). The game pauses the simulation while it is open.

signal go_down
signal cash_out
signal stay

const C_TEXT := Color(0.93, 0.94, 0.98)
const C_DIM := Color(0.62, 0.65, 0.76)
const C_MONEY := Color(0.55, 0.92, 0.62)
const C_WARN := Color(1.0, 0.8, 0.3)

## {floor: int, floor_count: int, payout: int, damages: int, followers: int, lines: Array[String]}
var info: Dictionary = {}

## Keys are ignored briefly after the menu opens (a slot key held while stepping on cannot pick an option).
const INPUT_GUARD_MS := 500

var _can_descend := false
var _born_ms := 0


func _init(new_info: Dictionary = {}) -> void:
	info = new_info


func _ready() -> void:
	_born_ms = Time.get_ticks_msec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_can_descend = int(info.get("floor", 1)) < int(info.get("floor_count", 3))
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.085, 0.095, 0.135)
	sb.border_color = Color(0.95, 0.85, 0.3)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 24
	sb.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var title := _label("FREIGHT ELEVATOR", 34, Color(1.0, 0.9, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := _label("Floor %d of %d" % [int(info.get("floor", 1)), int(info.get("floor_count", 3))], 18, C_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(_gap(4))

	var pay_row := HBoxContainer.new()
	v.add_child(pay_row)
	var pl := _label("Payout so far", 20, C_TEXT)
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pay_row.add_child(pl)
	pay_row.add_child(_label(ContractRun.money(int(info.get("payout", 0))), 26, C_MONEY))
	if int(info.get("damages", 0)) > 0:
		var dr := HBoxContainer.new()
		v.add_child(dr)
		var dl := _label("Property damage so far", 16, C_DIM)
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dr.add_child(dl)
		dr.add_child(_label("-" + ContractRun.money(int(info["damages"])), 18, Color(1.0, 0.5, 0.45)))
	for line: String in info.get("lines", []):
		var ll := _label(line, 16, C_TEXT)
		ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ll.custom_minimum_size = Vector2(540, 0)
		v.add_child(ll)
	var followers := int(info.get("followers", 0))
	if followers > 0:
		v.add_child(_label("%d employee%s riding along: +$%d each on the way out." % [followers, "s" if followers != 1 else "", ContractRun.EMPLOYEE_EXTRACTED], 16, C_WARN))
	v.add_child(_gap(6))

	if _can_descend:
		var down := _button("[1]  Go down to floor %d  (more pay, more danger)" % (int(info["floor"]) + 1), Color(0.75, 0.3, 0.2))
		down.pressed.connect(func() -> void: go_down.emit())
		v.add_child(down)
	var out := _button("[2]  Cash out", Color(0.2, 0.5, 0.3))
	out.pressed.connect(func() -> void: cash_out.emit())
	v.add_child(out)
	var stay_b := _button("[Esc]  Stay on this floor", Color(0.25, 0.28, 0.4))
	stay_b.custom_minimum_size = Vector2(0, 40)
	stay_b.add_theme_font_size_override("font_size", 18)
	stay_b.pressed.connect(func() -> void: stay.emit())
	v.add_child(stay_b)
	if not _can_descend:
		var last := _label("Last floor: there is nowhere further down to go.", 14, C_DIM)
		last.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(last)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or Time.get_ticks_msec() - _born_ms < INPUT_GUARD_MS:
		return
	match event.keycode:
		KEY_1, KEY_KP_1:
			if _can_descend:
				go_down.emit()
				get_viewport().set_input_as_handled()
		KEY_2, KEY_KP_2:
			cash_out.emit()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			stay.emit()
			get_viewport().set_input_as_handled()


func can_descend() -> bool:
	return int(info.get("floor", 1)) < int(info.get("floor_count", 3))


func _button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	for state in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = color.darkened(0.3 if state == "normal" else 0.1)
		s.border_color = color.lightened(0.2)
		s.set_border_width_all(2)
		s.set_corner_radius_all(6)
		b.add_theme_stylebox_override(state, s)
	return b


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
