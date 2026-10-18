class_name SpellPicker
extends Control
## Pre-game screen: choose exactly 2 of the spells, drawn as FORM 15 "License checkout" (scripts/ui/forms/).
## The catalog is a grid of compact licence cards (LicenseCard) built from SpellBook.ids() with nothing
## hard-coded per spell, so a new spell needs no change here. The grid is COLUMNS wide and grows downward;
## past MAX_ROWS rows it scrolls (focus keeps the focused card in view). The details of whichever card has focus
## (description, "say: cast X", cooldown, component) are in the panel on the right instead of on every row.
##
## Keys: arrows / D-pad move in 2D, Enter / A ticks, 1-9 tick the first nine cards (optional: later ones are
## reached with the arrows), Enter on Start signs, Esc voids the form. Add it under a Control (Hud.add_overlay), not a
## bare CanvasLayer. Emits picked(spells) with the ids in pick order, or cancelled() once the form is voided (void_back():
## the "Back to the board" row, or Esc through the game; FormVoid).
##
## Test hook: set `spell_ids` (and `spell_meta` for ids SpellBook does not know) before adding it to the tree, e.g.
## SpellPicker.fake_ids(24), to see how a long list lays out.

signal picked(spells: Array[String])
signal cancelled

const PICK_COUNT := 2
const COLUMNS := 3
const CARD_H := 64.0
const MIN_ROWS := 5                 ## the grid is at least this tall (so a short list does not collapse the sheet)
const MAX_ROWS := 7                 ## ... and at most this tall; more spells scroll
const SHEET_W := 1500.0
const DETAIL_W := 430.0
const NUMBER_KEYS := 9

## Spoken keyword shown in the details. Set before adding to the tree, or call set_trigger_word().
var trigger_word := "cast"
## The ids to offer, in order. Empty (the default) = SpellBook.ids().
var spell_ids: Array[String] = []
## Extra data for ids SpellBook does not know (test hook): id -> {name, color, desc, cooldown, component, word}.
var spell_meta := {}
## The row at the bottom (and what it says it does): "Back to the board" for a host or solo, "Leave the crew" for a
## client, who has no board of its own to go back to. Set before adding to the tree.
var back_text := "Back to the board"
var back_hint := "pick another job"
## A player joining a job already under way (user, 2026-10-18) files a supplemental requisition for the job in progress
## instead of a fresh license checkout: FORM 15-S on canary, the job's details typed across the top, "Submit
## requisition" to sign. Keys (all typed values, "" leaves a dash): job (number), client, floor, relieving (the seat's
## hero). Empty = the ordinary FORM 15. Set before adding to the tree.
var requisition := {}

var _ids: Array[String] = []
var _selected: Array[String] = []
var _buttons := {}          ## id -> LicenseCard
var _cards: Array[LicenseCard] = []
var _start: FormRow
var _back: FormRow
var _sheet: FormSheet
var _sub: Label
var _grid: GridContainer
var _scroll: ScrollContainer
var _d_swatch: ColorRect
var _d_name: Label
var _d_say: Label
var _d_facts: Label
var _d_desc: Label
var _d_state: Label
var _d_picks: Label
var _shown := ""            ## the id whose details are on the panel


## `count` made-up spells (test hook): returns their ids; pair with fake_meta().
static func fake_ids(count: int) -> Array[String]:
	var out: Array[String] = []
	for i in count:
		out.append("spell_%02d" % (i + 1))
	return out


static func fake_meta(ids: Array[String]) -> Dictionary:
	var out := {}
	var words := ["Aether", "Brine", "Cinder", "Dusk", "Ember", "Frost", "Gale", "Hex", "Iris", "Jinx", "Knot", "Lumen",
		"Mire", "Nimbus", "Onyx", "Plague", "Quill", "Rust", "Static", "Thorn", "Umbra", "Vortex", "Wisp", "Zenith"]
	for i in ids.size():
		var nm: String = words[i % words.size()]
		out[ids[i]] = {
			"name": nm, "color": Color.from_hsv(fposmod(float(i) * 0.11, 1.0), 0.6, 0.9), "word": nm.to_lower(),
			"desc": "A made-up spell number %d for checking how the licence catalog lays out when the list grows." % (i + 1),
			"cooldown": 6.0 + float(i % 7) * 2.0, "component": "Component %d" % (i + 1),
		}
	return out


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = FormTheme.theme()
	_ids = spell_ids.duplicate() if not spell_ids.is_empty() else SpellBook.ids()
	add_child(FormTheme.dim_rect(0.78))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	if requisition.is_empty():
		_sheet = FormSheet.new("15", "License checkout", "Spell licensing office  ·  pick %d" % PICK_COUNT, "Picks", "0 / %d" % PICK_COUNT, "white", 44)
	else:
		_sheet = FormSheet.new("15-S", "Supplemental requisition", "Added crew  ·  job in progress  ·  request %d licenses" % PICK_COUNT, "Requested", "0 / %d" % PICK_COUNT, "canary", 44)
	_sheet.custom_minimum_size = Vector2(SHEET_W, 0)
	center.add_child(_sheet)
	var body := _sheet.body

	if not requisition.is_empty():
		body.add_child(_requisition_strip())
		body.add_child(FormTheme.rule(2.0))
	_sub = FormTheme.typed("", 21)
	body.add_child(FormTheme.margin(_sub, 22, 10, 22, 8))
	_sub_text()
	body.add_child(FormTheme.rule(2.0))

	# The catalog (left) and the details of the focused card (right).
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 0)
	main.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(main)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rows_needed := ceili(float(maxi(_ids.size(), 1)) / float(COLUMNS))
	_scroll.custom_minimum_size = Vector2(0, float(clampi(rows_needed, MIN_ROWS, MAX_ROWS)) * CARD_H)
	main.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 0)
	_grid.add_theme_constant_override("v_separation", 0)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)
	main.add_child(_detail_panel())

	for i in _ids.size():
		var c := _make_card(_ids[i], i)
		_grid.add_child(c)
		_buttons[_ids[i]] = c
		_cards.append(c)
	body.add_child(FormTheme.rule(2.0))

	_start = FormRow.new("Start" if requisition.is_empty() else "Submit requisition", "GO", "")
	_start.row_h = 62.0
	_start.show_box = false
	_start.label_size = 34
	_start.pressed.connect(confirm)
	body.add_child(_start)
	_back = FormRow.new(back_text, "ESC", back_hint)
	_back.row_h = 52.0
	_back.show_box = false
	_back.pressed.connect(void_back)
	body.add_child(_back)
	_wire_focus()
	_refresh()
	if not _cards.is_empty():
		_show_details(_ids[0])

	var keys := KeyHints.new([["Arrows", "move"], ["Enter", "tick / sign"], ["1-9", "tick a license"], ["Esc", "void"]])
	keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	keys.offset_left = 330.0
	keys.offset_top = -46.0
	keys.offset_bottom = -12.0
	add_child(keys)
	var focus_first: Control = _start
	if not _cards.is_empty():
		focus_first = _cards[0]
	_initial_focus.call_deferred(focus_first)


## The job in progress, typed across the top of a supplemental requisition: printed captions, typed values.
func _requisition_strip() -> Control:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 34)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for f: Array in [["JOB #", "job"], ["CLIENT", "client"], ["FLOOR", "floor"], ["RELIEVING", "relieving"]]:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 10)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap := FormTheme.label(str(f[0]), 18, FormTheme.INK, true)
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(cap)
		var v := str(requisition.get(f[1], ""))
		var val := FormTheme.typed(v if v != "" else "-", 21)
		val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(val)
		strip.add_child(cell)
	return FormTheme.margin(strip, 22, 10, 22, 10)


func _detail_panel() -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.22)
	sb.border_color = FormTheme.INK
	sb.border_width_left = 3
	sb.content_margin_left = 22
	sb.content_margin_right = 20
	sb.content_margin_top = 14
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(DETAIL_W, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	v.add_child(FormTheme.label("LICENSE DETAILS", 17, FormTheme.INK, true))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_d_swatch = ColorRect.new()
	_d_swatch.custom_minimum_size = Vector2(12, 44)
	_d_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_d_swatch)
	_d_name = FormTheme.typed("", 38)
	head.add_child(_d_name)
	v.add_child(head)
	_d_say = FormTheme.label("", 26, FormTheme.GREASE, true)
	v.add_child(_d_say)
	_d_facts = FormTheme.label("", 20, FormTheme.INK)
	v.add_child(_d_facts)
	v.add_child(FormTheme.rule(2.0, FormTheme.FAINT))
	_d_desc = FormTheme.typed_wrapped("", 19, FormTheme.TYPED)
	_d_desc.custom_minimum_size = Vector2(DETAIL_W - 50.0, 0)
	_d_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_d_desc)
	_d_state = FormTheme.label("", 21, FormTheme.INK, true)
	v.add_child(_d_state)
	v.add_child(FormTheme.rule(2.0, FormTheme.FAINT))
	v.add_child(FormTheme.label("YOUR PICKS", 17, FormTheme.INK, true))
	_d_picks = FormTheme.typed("", 21)
	v.add_child(_d_picks)
	return panel


## Back is VOID (form-rules.md §6): stamp the sheet, then emit `cancelled`. False while it is already being voided.
func void_back() -> bool:
	return FormVoid.void_and(self, cancelled.emit, _sheet)


func _initial_focus(first: Control) -> void:
	if is_instance_valid(first) and first.is_inside_tree() and get_viewport().gui_get_focus_owner() == null:
		first.grab_focus()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var idx: int = int(event.keycode) - KEY_1
	if idx >= 0 and idx < mini(_ids.size(), NUMBER_KEYS):
		toggle(_ids[idx])
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		# On a focused card or row, Enter ticks / presses it (the Button handles that); otherwise it signs.
		if get_viewport().gui_get_focus_owner() == null:
			confirm()
			get_viewport().set_input_as_handled()


# --- Data --------------------------------------------------------------------------------------

func _meta(id: String, key: String, fallback: Variant) -> Variant:
	if SpellBook.has_spell(id):
		return null   # callers use the SpellBook accessors for real spells
	return (spell_meta.get(id, {}) as Dictionary).get(key, fallback)


func _name_of(id: String) -> String:
	return SpellBook.spell_name(id) if SpellBook.has_spell(id) else str(_meta(id, "name", id.capitalize()))


func _color_of(id: String) -> Color:
	return SpellBook.color_of(id) if SpellBook.has_spell(id) else (_meta(id, "color", Color.WHITE) as Color)


func _desc_of(id: String) -> String:
	return SpellBook.desc_of(id) if SpellBook.has_spell(id) else str(_meta(id, "desc", ""))


func _cooldown_of(id: String) -> float:
	return SpellBook.cooldown_of(id) if SpellBook.has_spell(id) else float(_meta(id, "cooldown", 0.0))


func _component_of(id: String) -> String:
	return SpellBook.component_name(id) if SpellBook.has_spell(id) else str(_meta(id, "component", "component"))


func _incantation_of(id: String) -> String:
	if SpellBook.has_spell(id):
		return SpellBook.incantation(id, trigger_word)
	return ("%s %s" % [trigger_word.strip_edges(), str(_meta(id, "word", id))]).strip_edges().to_upper()


## Update the "say: ..." lines (hook for a trigger-word dropdown).
func set_trigger_word(word: String) -> void:
	trigger_word = word if word.strip_edges() != "" else "cast"
	if _sub:
		_sub_text()
	for id in _buttons:
		(_buttons[id] as LicenseCard).hint = _hint_for(id)
	if _shown != "":
		_show_details(_shown)


func _sub_text() -> void:
	var a := _ids[0] if _ids.size() > 0 else "heal"
	var b := _ids[1] if _ids.size() > 1 else a
	_sub.text = "You will say them out loud: \"%s\", \"%s\"..." % [_incantation_of(a).to_lower(), _incantation_of(b).to_lower()]


func _hint_for(id: String) -> String:
	return "say: %s   cooldown %ds" % [_incantation_of(id).to_lower(), int(_cooldown_of(id))]


## Put keyboard focus on card `i` (0-based; clamped). Also scrolls it into view.
func focus_card(i: int) -> void:
	if not _cards.is_empty():
		_cards[clampi(i, 0, _cards.size() - 1)].grab_focus()


## The spell ids this picker offers, in grid order.
func offered() -> Array[String]:
	return _ids.duplicate()


## Currently selected ids, in pick order.
func selected() -> Array[String]:
	return _selected.duplicate()


## Toggle a spell. Picking a third one drops the oldest pick.
func toggle(id: String) -> void:
	if not _ids.has(id):
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


# --- Cards and the details panel ---------------------------------------------------------------------

func _make_card(id: String, index: int) -> LicenseCard:
	var c := LicenseCard.new(_name_of(id).to_upper(), str(index + 1) if index < NUMBER_KEYS else "", CARD_H)
	c.spell_id = id
	c.swatch = _color_of(id)
	c.hint = _hint_for(id)
	c.pressed.connect(func() -> void: toggle(id))
	c.focus_entered.connect(func() -> void: _show_details(id))
	return c


func _show_details(id: String) -> void:
	_shown = id
	if _d_name == null:
		return
	_d_swatch.color = _color_of(id)
	_d_name.text = _name_of(id).to_upper()
	_d_say.text = "say: " + _incantation_of(id).to_lower()
	_d_facts.text = "COOLDOWN %d s    COMPONENT: %s" % [int(_cooldown_of(id)), _component_of(id).to_upper()]
	_d_desc.text = _desc_of(id)
	_d_state.text = "LICENSED (Enter to give it back)" if _selected.has(id) else "Enter to tick this license"


func _refresh() -> void:
	for id in _buttons:
		var b: LicenseCard = _buttons[id]
		b.set_pressed_no_signal(_selected.has(id))
		b.queue_redraw()
	if _start == null:
		return
	_start.disabled = _selected.size() != PICK_COUNT
	_start.hint = "%d / %d chosen" % [_selected.size(), PICK_COUNT]
	_sheet.header.copy_value.text = "%d / %d" % [_selected.size(), PICK_COUNT]
	var picks: PackedStringArray = []
	for i in PICK_COUNT:
		picks.append("%d. %s" % [i + 1, _name_of(_selected[i]).to_upper() if i < _selected.size() else "-"])
	_d_picks.text = "\n".join(picks)
	if _shown != "":
		_show_details(_shown)


## Focus by geometry-free rules: left/right step through the cards, up/down jump a row, and the bottom row leads to
## Start, Back, and round to the top (so a controller never gets stuck, and 24 cards behave like 9).
func _wire_focus() -> void:
	var n := _cards.size()
	for i in n:
		var c := _cards[i]
		var left: Control = c
		var right: Control = c
		var up: Control = _back
		var down: Control = _start
		var prev: Control = _back
		var next: Control = _start
		if i % COLUMNS > 0:
			left = _cards[i - 1]
		if i % COLUMNS < COLUMNS - 1 and i + 1 < n:
			right = _cards[i + 1]
		if i - COLUMNS >= 0:
			up = _cards[i - COLUMNS]
		if i + COLUMNS < n:
			down = _cards[i + COLUMNS]
		if i > 0:
			prev = _cards[i - 1]
		if i + 1 < n:
			next = _cards[i + 1]
		c.focus_neighbor_left = c.get_path_to(left)
		c.focus_neighbor_right = c.get_path_to(right)
		c.focus_neighbor_top = c.get_path_to(up)
		c.focus_neighbor_bottom = c.get_path_to(down)
		c.focus_previous = c.get_path_to(prev)
		c.focus_next = c.get_path_to(next)
	var first: Control = _back
	var last: Control = _start
	if n > 0:
		first = _cards[0]
		last = _cards[n - 1]
	_start.focus_neighbor_top = _start.get_path_to(last)
	_start.focus_neighbor_bottom = _start.get_path_to(_back)
	_start.focus_previous = _start.get_path_to(last)
	_start.focus_next = _start.get_path_to(_back)
	_back.focus_neighbor_top = _back.get_path_to(_start)
	_back.focus_neighbor_bottom = _back.get_path_to(first)
	_back.focus_previous = _back.get_path_to(_start)
	_back.focus_next = _back.get_path_to(first)
