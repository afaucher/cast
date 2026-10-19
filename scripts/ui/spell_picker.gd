class_name SpellPicker
extends Control
## Pre-game screen: requisition exactly 2 spell licenses for the job. Drawn as paperwork (scripts/ui/forms/,
## docs/design/form-rules.md), one component with two variants that share every part:
##   FORM 15   "License requisition" (white): the ordinary one, at a contract start.
##   FORM 15-S "Supplemental requisition" (canary): a player joining a job already under way (`requisition` set).
## Beside it lies FORM 15-A, a separate "Spec sheet" page (SpecSheet), showing the line that has focus: how to say it,
## its component and cooldown, and what it does.
##
## The requisition: the job number in the header's copy box; typed fields for the client and who it is issued to (and on
## 15-S the floor); the catalog as line items (RequisitionLine: a printed box, the license,
## its component and cooldown), built from SpellBook.ids() with nothing hard-coded per spell, scrolling past MAX_LINES;
## the printed limit; and "Requested by ______", the line it is submitted on. With exactly PICK_COUNT lines ticked,
## Enter or a click on that line stamps the player's name on it in red (SignRow / SignLine, the job board's stamp),
## holds `sign_hold` seconds so it is seen, then emits picked(spells) with the ids in pick order. Before that the line is
## inert. The red ticks on the lines are the only record of what was chosen.
##
## Keys: Up / Down (D-pad) move line to line, then the signature line and the back row (wrapping); Enter / A ticks a line
## or signs; Esc voids the form (void_back(), through the game; the back row does the same; FormVoid) and then emits
## cancelled(). Add it under a Control (Hud.add_overlay), not a bare CanvasLayer.
##
## Test hook: set `spell_ids` (and `spell_meta` for ids SpellBook does not know) before adding it to the tree, e.g.
## SpellPicker.fake_ids(24), to see how a long list lays out. `sign_hold` = 0 submits at once.

signal picked(spells: Array[String])
signal cancelled

const PICK_COUNT := 2
const LINE_H := 48.0
const MIN_LINES := 5                ## the list is at least this tall (so a short list does not collapse the sheet)
const MAX_LINES := 10               ## ... and at most this tall (the ten spells of 2026-10-18 all show); more scroll
const SHEET_W := 1040.0
const SPEC_W := 430.0
const PAGE_GAP := 26.0
const SPEC_DROP := 46.0             ## the spec sheet lies a little lower than the requisition, as if pulled up beside it
const TYPE_SIZE := 21               ## the one typewriter (form-rules rule 7)
## Seconds the stamped signature stays up before `picked` (as the job board's Take line).
const SIGN_HOLD := 0.6
const LIMIT_TEXT := "Limit %d licenses per crew member, per job."
const SPEC_CARBON := "blue"

## Spoken keyword shown on the spec sheet. Set before adding to the tree, or call set_trigger_word().
var trigger_word := "cast"
## The ids to offer, in order. Empty (the default) = SpellBook.ids().
var spell_ids: Array[String] = []
## Extra data for ids SpellBook does not know (test hook): id -> {name, color, desc, cooldown, component, word}.
var spell_meta := {}
## The row at the bottom (and what it says it does): "Back to the board" for a host or solo, "Leave the crew" for a
## client, who has no board of its own to go back to. Set before adding to the tree.
var back_text := "Back to the board"
var back_hint := ""
## FORM 15's typed header (all typed values, "" leaves a dash): job (number), client. Set before adding to the tree.
var job := {}
## A player joining a job already under way (user, 2026-10-18) files FORM 15-S, the supplemental requisition for the job
## in progress, instead: canary, with the same keys as `job` plus floor. Empty = FORM 15.
var requisition := {}
## Who the form is issued to and who signs it ("" = JobBoard.signer_name(): the crew / Steam name).
var signer := ""
## Seconds from the signature to `picked` (0 = at once).
var sign_hold := SIGN_HOLD

var _ids: Array[String] = []
var _selected: Array[String] = []
var _by_id := {}            ## id -> RequisitionLine
var _lines: Array[RequisitionLine] = []
var _sign: SignRow
var _back: FormRow
var _sheet: FormSheet       ## the requisition (VOID lands here)
var _spec: SpecSheet        ## FORM 15-A, the page beside it
var _fields: Dictionary = {} ## typed header field key -> Label
var _limit: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _signing := false
var _shown := ""            ## the id on the spec sheet


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


## FORM 15-S (a joiner's supplemental requisition) rather than FORM 15.
func supplemental() -> bool:
	return not requisition.is_empty()


## Who signs (and who the form is issued to).
func signer_name() -> String:
	return signer if signer != "" else JobBoard.signer_name()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Sfx.play("paper")   # the form slides in
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = FormTheme.theme()
	_ids = spell_ids.duplicate() if not spell_ids.is_empty() else SpellBook.ids()
	add_child(FormTheme.dim_rect(0.78))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var pages := HBoxContainer.new()
	pages.name = "Pages"
	pages.add_theme_constant_override("separation", int(PAGE_GAP))
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(pages)

	var info := _info()
	var job_no := str(info.get("job", ""))
	if supplemental():
		_sheet = FormSheet.new("15-S", "Supplemental requisition", "Spell licensing office  ·  job in progress", "Job #", _dash(job_no), "canary", 44)
	else:
		_sheet = FormSheet.new("15", "License requisition", "Spell licensing office", "Job #", _dash(job_no), "white", 44)
	_sheet.name = "Requisition"
	_sheet.custom_minimum_size = Vector2(SHEET_W, 0)
	_sheet.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pages.add_child(_sheet)
	var body := _sheet.body

	# Typed header: who and what this requisition is for.
	body.add_child(_field_strip(info))

	# The catalog: column heads, then a line item per license (scrolling past MAX_LINES).
	body.add_child(RequisitionLine.Captions.new())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.custom_minimum_size = Vector2(0, float(clampi(_ids.size(), MIN_LINES, MAX_LINES)) * LINE_H)
	body.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	for id in _ids:
		var line := _make_line(id)
		_list.add_child(line)
		_by_id[id] = line
		_lines.append(line)
	body.add_child(FormTheme.rule(2.0))

	# The printed limit, once.
	_limit = FormTheme.label(LIMIT_TEXT % PICK_COUNT, 18, FormTheme.INK)
	_limit.name = "Limit"
	body.add_child(FormTheme.margin(_limit, 22, 6, 22, 2))

	# Submitting is signing.
	_sign = SignRow.new("Requested by")
	_sign.name = "RequestedBy"
	_sign.pressed.connect(confirm)
	body.add_child(_sign)
	body.add_child(FormTheme.rule(2.0))
	_back = FormRow.new(back_text, "", back_hint)
	_back.name = "Back"
	_back.row_h = 46.0
	_back.label_size = 24
	_back.show_box = false
	_back.pressed.connect(void_back)
	body.add_child(_back)

	# FORM 15-A, the spec sheet, a separate page lying beside the requisition.
	_spec = SpecSheet.new("15-A", "Spec sheet", "Licensing office", "License", SPEC_CARBON, SPEC_W)
	_spec.name = "SpecSheet"
	_spec.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_spec.add_field("say", "Say", true)
	_spec.add_pair("component", "Component", "cooldown", "Cooldown")
	_spec.add_field("desc", "What it does", false, 6)
	var drop := MarginContainer.new()
	drop.add_theme_constant_override("margin_top", int(SPEC_DROP))
	drop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop.add_child(_spec)
	pages.add_child(drop)

	_wire_focus()
	_refresh()
	if not _lines.is_empty():
		_show_spec(_ids[0])

	var esc_hint := "leave the crew" if back_text == "Leave the crew" else "back"
	var keys := KeyHints.new([["Arrows", "move"], ["Enter", "tick / sign"], ["Esc", esc_hint]])
	keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	keys.offset_top = -46.0
	keys.offset_bottom = -12.0
	add_child(keys)
	var focus_first: Control = _sign
	if not _lines.is_empty():
		focus_first = _lines[0]
	_initial_focus.call_deferred(focus_first)


func _info() -> Dictionary:
	return requisition if supplemental() else job


static func _dash(v: String) -> String:
	return v if v != "" else "-"


## The typed header fields across the top: printed captions over typed values, in ruled cells.
func _field_strip(info: Dictionary) -> Control:
	var strip := HBoxContainer.new()
	strip.name = "Fields"
	strip.add_theme_constant_override("separation", 0)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cells: Array = [["client", "Client", 3.0]]
	if supplemental():
		cells.append(["floor", "Floor", 0.9])
	cells.append(["issued_to", "Issued to", 1.6])
	for i in cells.size():
		var c: Array = cells[i]
		var key := str(c[0])
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(FormTheme.label(str(c[1]).to_upper(), 16, FormTheme.INK, true))
		var value := signer_name() if key == "issued_to" else str(info.get(key, ""))
		var l := FormTheme.typed(_dash(value), TYPE_SIZE)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(l)
		_fields[key] = l
		var p := PanelContainer.new()
		var sb := FormTheme.box_style(Color(0, 0, 0, 0), FormTheme.INK, 0.0, 18.0, 6.0)
		sb.border_width_bottom = 2
		if i < cells.size() - 1:
			sb.border_width_right = 2
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.size_flags_stretch_ratio = float(c[2])
		p.add_child(v)
		strip.add_child(p)
	return strip


## Back is VOID (form-rules.md §6): stamp the requisition, then emit `cancelled`. False while it is already being voided
## or once it is signed.
func void_back() -> bool:
	if _signing:
		return false
	return FormVoid.void_and(self, cancelled.emit, _sheet)


func _initial_focus(first: Control) -> void:
	if is_instance_valid(first) and first.is_inside_tree() and get_viewport().gui_get_focus_owner() == null:
		first.grab_focus()


func _input(event: InputEvent) -> void:
	if _signing:
		# Signed: the form is on its way, nothing on it changes.
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		# On a focused line or row, Enter ticks / presses it (the Button handles that); otherwise it signs.
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


## What the player says to cast `id` ("cast heal"), with this player's trigger word.
func say_of(id: String) -> String:
	return _incantation_of(id).to_lower()


## Update the spoken words on the spec sheet (hook for a trigger-word dropdown).
func set_trigger_word(word: String) -> void:
	trigger_word = word if word.strip_edges() != "" else "cast"
	if _shown != "":
		_show_spec(_shown)


## Put keyboard focus on line `i` (0-based; clamped). Also scrolls it into view.
func focus_line(i: int) -> void:
	if not _lines.is_empty():
		_lines[clampi(i, 0, _lines.size() - 1)].grab_focus()


## The spell ids this picker offers, in list order.
func offered() -> Array[String]:
	return _ids.duplicate()


## Currently selected ids, in pick order.
func selected() -> Array[String]:
	return _selected.duplicate()


## The spell on the spec sheet ("" = none).
func shown() -> String:
	return _shown


## Toggle a spell. Picking a third one drops the oldest pick.
func toggle(id: String) -> void:
	if not _ids.has(id) or _signing:
		_refresh()   # (a toggle Button flips itself before it asks: put it back)
		return
	if _selected.has(id):
		_selected.erase(id)
	else:
		_selected.append(id)
		while _selected.size() > PICK_COUNT:
			_selected.remove_at(0)
	_refresh()
	# Two licenses ticked: the next Enter should sign, so move to the signature line.
	if _selected.size() == PICK_COUNT and is_inside_tree() and _sign != null and _sign.is_visible_in_tree():
		_sign.grab_focus()


## Sign: with exactly PICK_COUNT licenses ticked, stamp the player's name on "Requested by", hold `sign_hold`, then emit
## picked(). Returns whether it signed (false with the wrong count, while signing, or while the form is being voided).
func confirm() -> bool:
	if _signing or _selected.size() != PICK_COUNT or FormVoid.voiding(self):
		return false
	_signing = true
	if _sign != null:
		_sign.sign(signer_name())
	if sign_hold > 0.0 and is_inside_tree():
		get_tree().create_timer(sign_hold).timeout.connect(_submit)
	else:
		_submit()
	return true


## Signed (the stamp is on the line).
func signed() -> bool:
	return _signing


func _submit() -> void:
	picked.emit(selected())


# --- Lines and the spec sheet --------------------------------------------------------------------

func _make_line(id: String) -> RequisitionLine:
	var line := RequisitionLine.new(_name_of(id).to_upper(), LINE_H)
	line.spell_id = id
	line.swatch = _color_of(id)
	line.component = _component_of(id)
	line.cooldown = "%d s" % int(_cooldown_of(id))
	line.pressed.connect(func() -> void: toggle(id))
	line.focus_entered.connect(func() -> void: _show_spec(id))
	return line


func _show_spec(id: String) -> void:
	if _shown != "" and id != _shown:
		Sfx.play("paper")   # the spec sheet turns to another spell's page (min_gap keeps fast scrolling quiet)
	_shown = id
	if _spec == null:
		return
	_spec.set_value("copy", _name_of(id).to_upper())
	_spec.set_value("say", "\"%s\"" % say_of(id))   # quoted: the words to say (user, 2026-10-19)
	_spec.set_value("component", _component_of(id))
	_spec.set_value("cooldown", "%d s" % int(_cooldown_of(id)))
	_spec.set_value("desc", _desc_of(id))


func _refresh() -> void:
	for id in _by_id:
		var line: RequisitionLine = _by_id[id]
		line.set_pressed_no_signal(_selected.has(id))
		line.queue_redraw()
	if _sign != null:
		_sign.disabled = _selected.size() != PICK_COUNT


## Focus without geometry: Up / Down (and Tab) run down the lines, then the signature line and the back row, and round to
## the top (so a controller never gets stuck, and 24 lines behave like 9). Left / Right stay put.
func _wire_focus() -> void:
	var order: Array = []
	order.append_array(_lines)
	order.append(_sign)
	order.append(_back)
	FormTheme.chain(order)
	for c: Control in order:
		c.focus_neighbor_left = c.get_path_to(c)
		c.focus_neighbor_right = c.get_path_to(c)
