class_name FormCheck
extends Button
## A boxed checkbox with a typed X when ticked and a typed label. A toggle Button (button_pressed / toggled
## work as on any CheckBox). Inside a FormField the row draws the focus band (`own_band` is turned off).

const BOX := 30.0

var own_band := true


func _init(label_text: String = "", on: bool = false) -> void:
	text = label_text
	_fit()
	toggle_mode = true
	button_pressed = on
	FormTheme.make_blank(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	toggled.connect(func(_on: bool) -> void: queue_redraw())
	mouse_entered.connect(func() -> void:
		if not disabled and is_inside_tree() and is_visible_in_tree() and own_band:
			grab_focus())


func _fit() -> void:
	var w := FormTheme.typed_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	custom_minimum_size = Vector2(BOX + 16.0 + w + 12.0, 44.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENABLED:
		queue_redraw()


func _draw() -> void:
	var alpha := 0.42 if disabled else 1.0
	if has_focus() and own_band and not disabled:
		FormTheme.draw_band(self, Rect2(-8, 2, size.x + 16, size.y - 4))
	var box := Rect2(0, (size.y - BOX) * 0.5, BOX, BOX)
	draw_rect(box, FormTheme.FIELD_FILL)
	draw_rect(box, Color(FormTheme.INK, alpha), false, 2.5)
	if button_pressed:
		FormTheme.draw_x(self, box, Color(FormTheme.TYPED, alpha))
	var tf := FormTheme.typed_font()
	draw_string(tf, Vector2(BOX + 16.0, FormTheme.baseline(tf, 24, size.y)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(FormTheme.TYPED, alpha))
