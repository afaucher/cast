class_name KeyHints
extends HBoxContainer
## A line of key hints drawn as small paper keycaps: set_hints([["Up", "Down", "move"], ["Enter", "sign"]]).
## In each entry the last string is the caption and the ones before it are keys. Meant to sit on the dark
## scene behind the forms (light caption text with an outline), so it needs no paper under it.


func _init(hints: Array = []) -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_hints(hints)


func set_hints(hints: Array) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for entry in hints:
		var parts: Array = entry
		for i in parts.size() - 1:
			add_child(keycap(str(parts[i])))
		var cap := FormTheme.label(str(parts[parts.size() - 1]).to_upper(), 21, Color(1, 1, 1, 0.9))
		cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		cap.add_theme_constant_override("outline_size", 5)
		add_child(cap)
		add_child(FormTheme.gap(0, 14))


static func keycap(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = FormTheme.PAPER
	sb.set_corner_radius_all(4)
	sb.border_color = Color("8a8270")
	sb.border_width_bottom = 4
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_child(FormTheme.typed(text, 20))
	return p
