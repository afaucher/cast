class_name FormHeader
extends HBoxContainer
## The printed header block of a form: "FORM 27-B" numbers on the left, the company line and the title in the
## middle, and a "copy / shift" box on the right, divided by 2.5 unit rules (3 px here) in the spot ink.

const RULE := 3.0

var form_no_label: Label
var title_label: Label
var company_label: Label
var copy_label: Label
var copy_value: Label


func _init(form_no: String = "", title: String = "", company: String = "", copy_caption: String = "", copy_text: String = "", title_size: int = 40) -> void:
	add_theme_constant_override("separation", 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", -4)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(FormTheme.label("FORM", 18, FormTheme.INK, true))
	form_no_label = FormTheme.label(form_no, 42, FormTheme.INK, true)
	left.add_child(form_no_label)
	add_child(FormTheme.margin(left, 16, 8, 16, 8))

	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", -2)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	company_label = FormTheme.label(company.to_upper(), 17, FormTheme.INK)
	company_label.add_theme_font_override("font", FormTheme.label_font(false, true))
	mid.add_child(company_label)
	title_label = FormTheme.label(title.to_upper(), title_size, FormTheme.INK, true)
	mid.add_child(title_label)
	var mid_m := FormTheme.margin(mid, 18, 8, 12, 8)
	mid_m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(mid_m)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 0)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy_label = FormTheme.label(copy_caption.to_upper(), 16, FormTheme.INK)
	copy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(copy_label)
	copy_value = FormTheme.typed(copy_text, 21)
	copy_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(copy_value)
	add_child(FormTheme.margin(right, 14, 8, 16, 8))
	sort_children.connect(queue_redraw)


func _draw() -> void:
	draw_line(Vector2(0, size.y - RULE * 0.5), Vector2(size.x, size.y - RULE * 0.5), FormTheme.INK, RULE)
	for i in [0, 2]:
		var c := get_child(i) as Control
		var x := c.position.x + c.size.x
		if i == 2:
			x = c.position.x
		draw_line(Vector2(x, 0), Vector2(x, size.y), FormTheme.INK, RULE)
