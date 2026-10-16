class_name SpellPicker
extends Control
## Pre-game screen: choose exactly 2 of the 4 spells. Click cards (or press
## 1-4), then Start (or Enter). Add it under a Control (Hud.add_overlay), not a bare CanvasLayer. Emits picked(spells) with the ids in pick order.

signal picked(spells: Array[String])

const PICK_COUNT := 2
const CARD_W := 250.0
const CARD_H := 230.0

## Spoken keyword shown on the cards. Set before adding to the tree, or call set_trigger_word().
var trigger_word := "cast"
var _selected: Array[String] = []
var _say_labels := {}       ## id -> Label
var _buttons := {}          ## id -> Button
var _start: Button
var _hint: Label
var _sub: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.07, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	title.text = "Choose %d spells" % PICK_COUNT
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	col.add_child(title)
	var sub := Label.new()
	_sub = sub
	_sub_text()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	sub.modulate = Color(0.75, 0.78, 0.85)
	col.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var n := 1
	for id in SpellBook.ids():
		var b := _make_card(id, n)
		row.add_child(b)
		_buttons[id] = b
		n += 1

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 20)
	col.add_child(_hint)
	_start = Button.new()
	_start.text = "Start"
	_start.custom_minimum_size = Vector2(220, 52)
	_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start.add_theme_font_size_override("font_size", 26)
	_start.pressed.connect(confirm)
	col.add_child(_start)
	_refresh()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var ids := SpellBook.ids()
	var idx: int = int(event.keycode) - KEY_1
	if idx >= 0 and idx < ids.size():
		toggle(ids[idx])
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		confirm()
		get_viewport().set_input_as_handled()


## Update the "say: ..." lines (hook for a trigger-word dropdown).
func set_trigger_word(word: String) -> void:
	trigger_word = word if word.strip_edges() != "" else "cast"
	if _sub:
		_sub_text()
	for id in _say_labels:
		_say_labels[id].text = "say: " + SpellBook.incantation(id, trigger_word)


func _sub_text() -> void:
	_sub.text = "You will say them out loud: \"%s\", \"%s\"..." % [SpellBook.incantation("heal", trigger_word).to_lower(), SpellBook.incantation("fireball", trigger_word).to_lower()]


## Currently selected ids, in pick order.
func selected() -> Array[String]:
	return _selected.duplicate()


## Toggle a spell. Picking a third one drops the oldest pick.
func toggle(id: String) -> void:
	if not SpellBook.has_spell(id):
		return
	if _selected.has(id):
		_selected.erase(id)
	else:
		_selected.append(id)
		while _selected.size() > PICK_COUNT:
			_selected.remove_at(0)
	_refresh()


## Emit picked() if exactly PICK_COUNT spells are chosen. Returns whether it did.
func confirm() -> bool:
	if _selected.size() != PICK_COUNT:
		return false
	picked.emit(selected())
	return true


func _refresh() -> void:
	for id in _buttons:
		var b: Button = _buttons[id]
		b.set_pressed_no_signal(_selected.has(id))
	if _start == null:
		return
	_start.disabled = _selected.size() != PICK_COUNT
	_hint.text = "%d / %d chosen" % [_selected.size(), PICK_COUNT]


func _make_card(id: String, number: int) -> Button:
	var spell_col := SpellBook.color_of(id)
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(CARD_W, CARD_H)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void: toggle(id))
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		var selected_state: bool = state.ends_with("pressed")
		sb.bg_color = Color(0.1, 0.12, 0.18) if not selected_state else spell_col.darkened(0.55)
		if state.begins_with("hover"):
			sb.bg_color = sb.bg_color.lightened(0.1)
		sb.border_color = spell_col if selected_state else spell_col.darkened(0.4)
		sb.set_border_width_all(4 if selected_state else 2)
		sb.set_corner_radius_all(10)
		b.add_theme_stylebox_override(state, sb)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	v.add_child(_label("[%d]  %s" % [number, SpellBook.spell_name(id).to_upper()], 28, spell_col.lightened(0.2)))
	var say := _label("say: " + SpellBook.incantation(id, trigger_word), 18, Color.WHITE)
	_say_labels[id] = say
	v.add_child(say)
	var desc := _label(str(SpellBook.SPELLS[id]["desc"]), 15, Color(0.75, 0.78, 0.85))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(desc)
	v.add_child(_label("cooldown %ds" % int(SpellBook.cooldown_of(id)), 14, Color(0.6, 0.62, 0.7)))
	return b


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
