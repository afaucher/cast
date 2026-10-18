class_name SpecSheet
extends FormSheet
## A spec sheet: a small separate page that lies beside the form it explains (form-rules.md, "a spec sheet is its own
## page"), with its own form number, header and carbon, so it reads as a second document pulled up alongside rather
## than a panel of the same sheet. Its body is ruled cells of a printed caption over a typed value; the form fills
## them (for whichever line has focus) with set_value(). Key "copy" is the header's copy box.
##
##   var spec := SpecSheet.new("15-A", "Spec sheet", "Spell licensing office", "License", "blue", 430.0)
##   spec.add_field("say", "Say", true)
##   spec.add_pair("component", "Component", "cooldown", "Cooldown")
##   spec.add_field("desc", "What it does", false, 6)
##   spec.set_value("say", "cast heal")

const TYPE_SIZE := 21
const CAPTION_SIZE := 16
const PAD_H := 18.0

var width := 430.0
var _values := {}     ## key -> the typed Label


func _init(form_no: String = "", title: String = "", company: String = "", copy_caption: String = "", carbon_name: String = "white", sheet_w: float = 430.0, title_size: int = 32) -> void:
	super(form_no, title, company, copy_caption, "-", carbon_name, title_size)
	width = sheet_w
	custom_minimum_size = Vector2(width, 0)
	# The copy box holds a typed value that changes with the line in focus: clip it, so a long name never widens the page.
	header.copy_value.clip_text = true
	header.copy_value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.copy_value.custom_minimum_size = Vector2(120, 0)
	header.copy_label.custom_minimum_size = Vector2(120, 0)
	_values["copy"] = header.copy_value


## A full-width cell: the caption, then the typed value (`boxed`: in a printed box, for the one thing to read first;
## `lines` > 0: running text that wraps, with room for that many lines so the page keeps its size).
func add_field(key: String, caption: String, boxed: bool = false, lines: int = 0) -> Label:
	var v := _cell_box()
	v.add_child(_caption(caption))
	var val := _typed(lines)
	if lines > 0:
		val.custom_minimum_size = Vector2(width - PAD_H * 2.0, FormTheme.typed_font().get_height(TYPE_SIZE) * lines)
	if boxed:
		v.add_child(FormTheme.boxed(val, 12.0, 6.0))
	else:
		v.add_child(val)
	_values[key] = val
	body.add_child(_ruled(v, false))
	return val


## Two cells side by side.
func add_pair(key_a: String, caption_a: String, key_b: String, caption_b: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for f: Array in [[key_a, caption_a, true], [key_b, caption_b, false]]:
		var v := _cell_box()
		v.add_child(_caption(str(f[1])))
		var val := _typed(0)
		val.clip_text = true
		v.add_child(val)
		_values[str(f[0])] = val
		var cell := _ruled(v, bool(f[2]))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = 1.4 if bool(f[2]) else 1.0
		row.add_child(cell)
	body.add_child(row)


func set_value(key: String, text: String) -> void:
	var l: Label = _values.get(key)
	if l != null:
		l.text = text


func value(key: String) -> String:
	var l: Label = _values.get(key)
	return l.text if l != null else ""


## Every typed label on the page (tests: what is typed).
func typed_labels() -> Array[Label]:
	var out: Array[Label] = []
	for k: String in _values:
		out.append(_values[k])
	return out


func _cell_box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _caption(text: String) -> Label:
	return FormTheme.label(text.to_upper(), CAPTION_SIZE, FormTheme.INK, true)


func _typed(lines: int) -> Label:
	var l := FormTheme.typed("", TYPE_SIZE)
	if lines > 0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return l


## A ruled cell: padding, a rule below (and one on the right for a left-hand cell).
func _ruled(inner: Control, right_rule: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := FormTheme.box_style(Color(0, 0, 0, 0), FormTheme.INK, 0.0, PAD_H, 8.0)
	sb.border_width_bottom = 2
	if right_rule:
		sb.border_width_right = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(inner)
	return p
