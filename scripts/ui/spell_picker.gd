class_name SpellPicker
extends Control
## Pre-game screen: choose exactly 2 of the spells, drawn as FORM 15 "License checkout" (scripts/ui/forms/):
## one ruled row per spell with a box to tick. Click rows (or press 1-6, or arrow to a row and press
## Enter), then Start (or Enter once two are chosen). Add it under a Control (Hud.add_overlay), not a bare
## CanvasLayer. Emits picked(spells) with the ids in pick order.

signal picked(spells: Array[String])

const PICK_COUNT := 2

## Spoken keyword shown on the rows. Set before adding to the tree, or call set_trigger_word().
var trigger_word := "cast"
var _selected: Array[String] = []
var _buttons := {}          ## id -> FormRow
var _start: FormRow
var _sheet: FormSheet
var _sub: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = FormTheme.theme()
	add_child(FormTheme.dim_rect(0.78))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_sheet = FormSheet.new("15", "License checkout", "Spell licensing office  ·  pick %d" % PICK_COUNT, "Picks", "0 / %d" % PICK_COUNT, "white", 44)
	_sheet.custom_minimum_size = Vector2(1240, 0)
	center.add_child(_sheet)
	var body := _sheet.body

	_sub = FormTheme.typed("", 21)
	body.add_child(FormTheme.margin(_sub, 22, 10, 22, 8))
	_sub_text()
	body.add_child(FormTheme.rule(2.0))

	var n := 1
	var rows: Array[Control] = []
	for id in SpellBook.ids():
		var b := _make_row(id, n)
		body.add_child(b)
		_buttons[id] = b
		rows.append(b)
		n += 1
	_start = FormRow.new("Start", "GO", "")
	_start.row_h = 70.0
	_start.show_box = false
	_start.label_size = 34
	_start.pressed.connect(confirm)
	body.add_child(_start)
	rows.append(_start)
	FormTheme.chain(rows)
	_refresh()

	var keys := KeyHints.new([["1-6", "tick a license"], ["Up", "Down", "move"], ["Enter", "tick / sign"]])
	keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	keys.offset_left = 330.0
	keys.offset_top = -46.0
	keys.offset_bottom = -12.0
	add_child(keys)
	_initial_focus.call_deferred(rows[0])


func _initial_focus(first: Control) -> void:
	if is_instance_valid(first) and first.is_inside_tree() and get_viewport().gui_get_focus_owner() == null:
		first.grab_focus()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var ids := SpellBook.ids()
	var idx: int = int(event.keycode) - KEY_1
	if idx >= 0 and idx < ids.size():
		toggle(ids[idx])
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		# On a focused row, Enter ticks it (the row's own button handles that); otherwise it signs.
		if get_viewport().gui_get_focus_owner() == null:
			confirm()
			get_viewport().set_input_as_handled()


## Update the "say: ..." lines (hook for a trigger-word dropdown).
func set_trigger_word(word: String) -> void:
	trigger_word = word if word.strip_edges() != "" else "cast"
	if _sub:
		_sub_text()
	for id in _buttons:
		(_buttons[id] as FormRow).hint = _hint_for(id)


func _sub_text() -> void:
	_sub.text = "You will say them out loud: \"%s\", \"%s\"..." % [SpellBook.incantation("heal", trigger_word).to_lower(), SpellBook.incantation("fireball", trigger_word).to_lower()]


func _hint_for(id: String) -> String:
	return "say: %s   cooldown %ds" % [SpellBook.incantation(id, trigger_word).to_lower(), int(SpellBook.cooldown_of(id))]


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
	# Two licences ticked: the next Enter should sign, so move to Start.
	if _selected.size() == PICK_COUNT and is_inside_tree() and _start != null and _start.is_visible_in_tree():
		_start.grab_focus()


## Emit picked() if exactly PICK_COUNT spells are chosen. Returns whether it did.
func confirm() -> bool:
	if _selected.size() != PICK_COUNT:
		return false
	picked.emit(selected())
	return true


func _refresh() -> void:
	for id in _buttons:
		var b: FormRow = _buttons[id]
		b.set_pressed_no_signal(_selected.has(id))
		b.queue_redraw()
	if _start == null:
		return
	_start.disabled = _selected.size() != PICK_COUNT
	_start.hint = "%d / %d chosen" % [_selected.size(), PICK_COUNT]
	_sheet.header.copy_value.text = "%d / %d" % [_selected.size(), PICK_COUNT]


func _make_row(id: String, number: int) -> FormRow:
	var b := FormRow.new(SpellBook.spell_name(id).to_upper(), str(number), _hint_for(id))
	b.toggle_mode = true
	b.label_size = 30
	b.sub = str(SpellBook.SPELLS[id]["desc"])
	var sf := FormTheme.typed_font(false)
	var wrapped := sf.get_multiline_string_size(b.sub, HORIZONTAL_ALIGNMENT_LEFT, 1060.0, 19)
	b.sub_lines = clampi(int(ceilf(wrapped.y / sf.get_height(19))), 1, 3)
	b.swatch = SpellBook.color_of(id)
	b.pressed.connect(func() -> void: toggle(id))
	return b
