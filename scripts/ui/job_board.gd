class_name JobBoard
extends Control
## The dispatch job board, drawn as FORM 12 "Dispatch offers" (scripts/ui/forms/): a header strip and a 3-part
## tear-off set (white / canary / pink) with the SAME fields in the SAME places on every part, so the crew can
## compare across columns: client, site and danger boxes, what happened, an objectives table with $, a
## red-boxed property warning, the contract value and a "Take [n]" signature line.
##
## Pick one with the mouse, the keys 1-3, or Left / Right then Enter (A on a controller). The highlighted offer
## lifts a little and gets a yellow outline. Add it under a Control (Hud.add_overlay) or a CanvasLayer's root
## Control. Emits picked(run).
##
## Nothing here is full-screen and opaque except the fallback shade, which only shows while `backdrop_behind` is
## false: the game sets it to true because the garage (MenuBackdrop, the main menu's backdrop) is behind the
## cards, and then only a light vignette sits over it.

signal picked(run: ContractRun)

const CARD_W := 480.0
const LIFT := 12.0
const PARTS := ["white", "canary", "pink"]
const SHADE_OPAQUE := Color(0.06, 0.05, 0.07, 1.0)   ## no backdrop: a plain dark screen
const SHADE_LIGHT := Color(0.03, 0.025, 0.035, 0.22) ## garage behind: a light dim only

var offers: Array[ContractRun] = []
## True when a 3D backdrop (the garage) is rendered behind the board: the opaque dark shade goes and a light
## vignette stays. Set it any time.
var backdrop_behind := false:
	set(v):
		backdrop_behind = v
		_apply_shade()

var _cards: Array[PaperPanel] = []
var _slots: Array[Control] = []
var _lifts: Dictionary = {}
var _hi := 0
var _fallback: ColorRect = null
var _lift_tweens: Dictionary = {}


func _init(new_offers: Array[ContractRun] = []) -> void:
	offers = new_offers


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = FormTheme.theme()
	# With no 3D backdrop: a plain dark shade, so the cards never float over nothing. With the garage behind
	# (backdrop_behind): only a light dim so the white rules text and the card edges stay readable.
	_fallback = FormTheme.dim_rect(1.0)
	add_child(_fallback)
	_apply_shade()

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 50)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	# Top row: the FORM 12 header strip on the left, the key hints and the house rules on the right.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 26)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var strip := FormSheet.new("12", "Available contracts", "Dispatch offers  ·  3-part set  ·  tear off one", "Board", "%d open" % offers.size(), "white", 36)
	strip.custom_minimum_size = Vector2(840, 0)
	strip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(strip)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(KeyHints.new([["1", "3", "or"], ["Left", "Right", "pick"], ["Enter", "take job"], ["Esc", "back"]]))
	var rules := FormTheme.label("LEAVING EARLY ALWAYS WORKS  ·  UNMET OBJECTIVES DO NOT PAY  ·  PAY NEVER GOES BELOW $0", 18, Color(1, 1, 1, 0.85))
	rules.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	rules.add_theme_constant_override("outline_size", 5)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.custom_minimum_size = Vector2(300, 0)
	side.add_child(rules)
	top.add_child(side)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	for i in offers.size():
		row.add_child(_make_slot(offers[i], i))

	_hi = clampi(_hi, 0, maxi(offers.size() - 1, 0))
	_apply_highlight(false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var idx: int = int((event as InputEventKey).keycode) - KEY_1
		if idx >= 0 and idx < offers.size():
			choose(idx)
			get_viewport().set_input_as_handled()
			return
	if offers.is_empty():
		return
	if event.is_action_pressed("ui_left") and not (event is InputEventMouse):
		set_highlight((_hi - 1 + offers.size()) % offers.size())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") and not (event is InputEventMouse):
		set_highlight((_hi + 1) % offers.size())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and not event.is_echo() and not (event is InputEventMouse):
		choose(_hi)
		get_viewport().set_input_as_handled()


## Take offer `index` (mouse click or the key).
func choose(index: int) -> void:
	if index >= 0 and index < offers.size():
		picked.emit(offers[index])


## The highlighted offer (keyboard / controller / the last one the mouse touched).
func highlighted() -> int:
	return _hi


## Highlight offer `index`: it lifts and gets the yellow outline.
func set_highlight(index: int) -> void:
	if offers.is_empty():
		return
	index = clampi(index, 0, offers.size() - 1)
	if index == _hi and not _cards.is_empty() and _cards[index].outline_color.a > 0.0:
		return
	_hi = index
	_apply_highlight(true)


## The shade behind the cards: opaque dark with no 3D backdrop, a light dim when the garage is behind.
func _apply_shade() -> void:
	if _fallback == null:
		return
	_fallback.color = SHADE_LIGHT if backdrop_behind else SHADE_OPAQUE


func _apply_highlight(animate: bool) -> void:
	for i in _cards.size():
		var on := i == _hi
		_cards[i].outline_color = FormTheme.OUTLINE_YELLOW if on else Color(0, 0, 0, 0)
		var to := 1.0 if on else 0.0
		if _lift_tweens.has(i) and (_lift_tweens[i] as Tween).is_valid():
			(_lift_tweens[i] as Tween).kill()
		var from_f: float = float(_lifts.get(i, 0.0))
		if animate and is_inside_tree() and not is_equal_approx(from_f, to):
			var tw := create_tween()
			tw.tween_method(_set_lift.bind(i), from_f, to, 0.09)
			_lift_tweens[i] = tw
		else:
			_set_lift(to, i)


## `f` 0..1: how far the card in slot `i` is lifted. The slot keeps its size; only the card's top margin moves.
func _set_lift(f: float, i: int) -> void:
	_lifts[i] = f
	var slot := _slots[i] as MarginContainer
	slot.add_theme_constant_override("margin_top", int(roundf(LIFT * (1.0 - f))))
	slot.add_theme_constant_override("margin_bottom", int(roundf(LIFT * f)))


# --- Cards ----------------------------------------------------------------------------------

## A slot holding the card: a margin that moves the card up by LIFT when it is highlighted (a Container
## would otherwise reset the card's position). All three slots stretch to the tallest card.
func _make_slot(run: ContractRun, index: int) -> Control:
	var card := _make_card(run, index)
	var slot := MarginContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(card)
	_slots.append(slot)
	_cards.append(card)
	_set_lift(0.0, index)
	return slot


func _make_card(run: ContractRun, index: int) -> PaperPanel:
	var part: String = PARTS[index % PARTS.size()]
	var card := PaperPanel.new(FormTheme.carbon(part))
	card.set_padding(0, 0, 0, 0)
	card.tear_y = 40.0
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			choose(index))
	card.mouse_entered.connect(func() -> void: set_highlight(index))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)

	# Stub: part and job number, above the tear-off line.
	var stub := HBoxContainer.new()
	stub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var part_l := FormTheme.label("PART %d  ·  %s" % [index + 1, part.to_upper()], 18, FormTheme.INK, true)
	part_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stub.add_child(part_l)
	stub.add_child(FormTheme.label(run.invoice_number.replace("INV-", "JOB #"), 18, FormTheme.INK, true))
	var stub_box := FormTheme.margin(stub, 16, 0, 16, 0)
	stub_box.custom_minimum_size = Vector2(0, 40)
	v.add_child(stub_box)

	# Client.
	var client := _cell()
	client.add_child(_cap("CLIENT"))
	var name_l := FormTheme.typed(run.client_name, 24)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size = Vector2(CARD_W - 36, 0)
	client.add_child(name_l)
	var who := FormTheme.label("%s  ·  %s" % [run.archetype_title().to_upper(), run.company], 18)
	who.add_theme_font_override("font", FormTheme.label_font(false, true))
	who.clip_text = true
	who.custom_minimum_size = Vector2(CARD_W - 36, 0)
	client.add_child(who)
	v.add_child(_boxed_cell(client))

	# Site and danger, side by side.
	var two := HBoxContainer.new()
	two.add_theme_constant_override("separation", 0)
	two.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var site := _cell()
	site.add_child(_cap("SITE"))
	site.add_child(FormTheme.typed("Survival bunker" if run.site_type == "bunker" else "Villain lair", 20))
	var site_cell := _boxed_cell(site, 0.0, true)
	site_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(site_cell)
	var danger := _cell()
	danger.add_child(_cap("DANGER"))
	var dr := HBoxContainer.new()
	dr.add_theme_constant_override("separation", 10)
	dr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var boxes := DangerBoxes.new()
	boxes.value = run.difficulty_stars()
	dr.add_child(boxes)
	dr.add_child(FormTheme.typed("3 floors", 19))
	danger.add_child(dr)
	var danger_cell := _boxed_cell(danger, 0.0, false)
	danger_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(danger_cell)
	v.add_child(two)

	# What happened.
	var story := _cell()
	story.add_child(_cap("WHAT HAPPENED"))
	var ev := FormTheme.typed_wrapped(str(run.story["event"]), 19, FormTheme.TYPED, false)
	ev.custom_minimum_size = Vector2(CARD_W - 36, 78)
	story.add_child(ev)
	story.add_child(FormTheme.small("Origin: the %s (floor 3)." % str(run.story["origin"]), 18))
	v.add_child(_boxed_cell(story))

	# Objectives table.
	var obj := _cell()
	obj.add_child(_cap("OBJECTIVES"))
	for line in run.card_lines():
		obj.add_child(_objective_row(line))
	v.add_child(_boxed_cell(obj))

	# Property warning in a red box.
	var warn_v := VBoxContainer.new()
	warn_v.add_theme_constant_override("separation", 0)
	warn_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warn_v.add_child(FormTheme.label("PROPERTY WARNING", 17, FormTheme.RED, true))
	var wl := FormTheme.typed_wrapped(str(ClientArchetype.get_data(run.archetype_id)["warning"]), 18, Color("6a1a14"), true)
	wl.custom_minimum_size = Vector2(CARD_W - 70, 66)
	warn_v.add_child(wl)
	var warn := PanelContainer.new()
	warn.add_theme_stylebox_override("panel", FormTheme.box_style(Color(1, 1, 1, 0.0), FormTheme.RED, 2.0, 10.0, 5.0))
	warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warn.add_child(warn_v)
	v.add_child(FormTheme.margin(warn, 16, 8, 16, 4))
	v.add_child(FormTheme.margin(FormTheme.small("Damages are deducted, up to %s." % ContractRun.money(run.contract_value), 17), 16, 0, 16, 4))

	# Contract value.
	var total := HBoxContainer.new()
	total.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := FormTheme.label("CONTRACT VALUE", 19, FormTheme.INK, true)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	total.add_child(tl)
	total.add_child(FormTheme.typed(ContractRun.money(run.contract_value), 34, FormTheme.GREEN_INK))
	var total_box := FormTheme.margin(total, 16, 4, 16, 4)
	var total_panel := PanelContainer.new()
	var tsb := FormTheme.box_style(Color(0, 0, 0, 0), FormTheme.INK, 0.0, 0.0, 0.0)
	tsb.border_width_top = 3
	total_panel.add_theme_stylebox_override("panel", tsb)
	total_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	total_panel.add_child(total_box)
	v.add_child(total_panel)

	# Signature line: "Take ______ [1]".
	var sign := HBoxContainer.new()
	sign.add_theme_constant_override("separation", 10)
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var take := FormTheme.label("TAKE", 20, FormTheme.INK, true)
	take.size_flags_vertical = Control.SIZE_SHRINK_END
	sign.add_child(take)
	var line := SignLine.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.custom_minimum_size = Vector2(0, 34)
	sign.add_child(line)
	var key := FormTheme.typed("[%d]" % (index + 1), 24)
	key.size_flags_vertical = Control.SIZE_SHRINK_END
	sign.add_child(key)
	v.add_child(FormTheme.margin(sign, 16, 4, 16, 12))
	return card


func _cell() -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A ruled cell: padding and a 1.5 unit ink rule below (and a rule on the left for a right-hand cell).
func _boxed_cell(inner: Control, min_h: float = 0.0, right_rule: bool = false) -> Control:
	var p := PanelContainer.new()
	var sb := FormTheme.box_style(Color(0, 0, 0, 0), FormTheme.INK, 0.0, 16.0, 7.0)
	sb.border_width_bottom = 2
	if right_rule:
		sb.border_width_right = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if min_h > 0.0:
		p.custom_minimum_size = Vector2(0, min_h)
	p.add_child(inner)
	return p


func _cap(text: String) -> Label:
	return FormTheme.label(text, 17, FormTheme.INK, true)


func _objective_row(line: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := FormTheme.label(str(line["label"]), 21, FormTheme.TYPED)
	l.add_theme_font_override("font", FormTheme.label_font(false, false))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var pay := ContractRun.money(int(line["pay"]))
	if line.has("alive"):
		pay = "%s/%s" % [ContractRun.money(int(line["alive"])), ContractRun.money(int(line["pay"]))]
	elif bool(line["each"]):
		pay += " ea"
	var pl := FormTheme.typed(pay, 20)
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pl)
	var p := PanelContainer.new()
	var sb := FormTheme.box_style(Color(0, 0, 0, 0), FormTheme.FAINT, 0.0, 0.0, 1.0)
	sb.border_width_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	return p


## Five small boxes, `value` of them inked red: the danger rating.
class DangerBoxes:
	extends Control
	var value := 0
	var count := 5

	func _init() -> void:
		custom_minimum_size = Vector2(count * 23.0, 24.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		for i in count:
			var r := Rect2(i * 23.0, 2.0, 19.0, 19.0)
			if i < value:
				draw_rect(r, FormTheme.RED)
			else:
				draw_rect(r, FormTheme.FIELD_FILL)
				draw_rect(r, FormTheme.INK, false, 2.0)


## The ruled line you sign on.
class SignLine:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_line(Vector2(0, size.y - 3.0), Vector2(size.x, size.y - 3.0), FormTheme.INK, 2.0)
