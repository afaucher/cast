class_name FormSection
extends PanelContainer
## A ruled section of a form: a small printed caption ("1. AUDIO") over its rows, closed by a 2.5 unit rule.
## Add rows to `box`.

var box: VBoxContainer
var caption: Label


func _init(title: String = "", last: bool = false, pad_h: float = 22.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = FormTheme.INK
	sb.border_width_bottom = 0 if last else 3
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_PASS
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(box)
	if title != "":
		caption = FormTheme.label(title.to_upper(), 19, FormTheme.INK, true)
		box.add_child(caption)
