class_name FormRow
extends Button
## One ruled row of a form: a number cell, a checkbox, the typed label and a printed hint on the right.
## A real Button, so keyboard and controller focus, Enter/A and the mouse all work natively; the row draws
## itself (the Button's own text is transparent but stays set, so `row.text` reads as usual).
##
## Focus (mouse hover grabs focus, so there is only ever one) = the yellow highlighter band plus a red
## grease-pencil tick in the box. With toggle_mode the box shows a red grease X while the row is ticked, and
## the band alone shows focus.

const NUM_W := 78.0
const BOX := 30.0

var number := "":
	set(v):
		number = v
		queue_redraw()
var hint := "":
	set(v):
		hint = v
		queue_redraw()
## A second, smaller typed line under the label (a description).
var sub := "":
	set(v):
		sub = v
		_fit()
		queue_redraw()
## A colour bar before the label (a spell colour). Alpha 0 = none.
var swatch := Color(0, 0, 0, 0):
	set(v):
		swatch = v
		queue_redraw()
## How many lines the description may wrap to.
var sub_lines := 1:
	set(v):
		sub_lines = maxi(1, v)
		_fit()
		queue_redraw()
var label_size := 34:
	set(v):
		label_size = v
		queue_redraw()
var row_h := 66.0:
	set(v):
		row_h = v
		_fit()
var show_box := true


func _init(label_text: String = "", number_text: String = "", hint_text: String = "") -> void:
	text = label_text
	number = number_text
	hint = hint_text
	FormTheme.make_blank(self)
	_fit()
	mouse_filter = Control.MOUSE_FILTER_STOP
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	toggled.connect(func(_on: bool) -> void: queue_redraw())
	mouse_entered.connect(func() -> void:
		if not disabled and focus_mode != Control.FOCUS_NONE and is_inside_tree() and is_visible_in_tree():
			grab_focus())


## (A Button's own minimum size ignores _get_minimum_size, so the height goes in custom_minimum_size.)
func _fit() -> void:
	custom_minimum_size = Vector2(300.0, row_h if sub == "" else maxf(row_h, 54.0 + 25.0 * sub_lines))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENABLED or what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var s := size
	var alpha := 0.42 if disabled else 1.0
	var focused := has_focus() and not disabled
	if focused:
		FormTheme.draw_band(self, Rect2(-10, 3, s.x + 20, s.y - 6))
	draw_line(Vector2(0, s.y - 1.0), Vector2(s.x, s.y - 1.0), Color(FormTheme.INK, alpha), 2.0)
	# Number cell.
	draw_line(Vector2(NUM_W, 0), Vector2(NUM_W, s.y), Color(FormTheme.INK, alpha), 2.0)
	var nf := FormTheme.label_font(true)
	var nw := nf.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string(nf, Vector2((NUM_W - nw) * 0.5, FormTheme.baseline(nf, 26, s.y)), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(FormTheme.INK, alpha))
	# Box.
	var x := NUM_W + 18.0
	if show_box:
		var box := Rect2(x, (s.y - BOX) * 0.5, BOX, BOX)
		draw_rect(box, FormTheme.FIELD_FILL)
		draw_rect(box, Color(FormTheme.INK, alpha), false, 2.5)
		if toggle_mode:
			if button_pressed:
				FormTheme.draw_grease_x(self, box)
		elif focused:
			FormTheme.draw_tick(self, box)
		x += BOX + 18.0
	if swatch.a > 0.0:
		draw_rect(Rect2(x, 14.0, 9.0, s.y - 28.0), Color(swatch, alpha))
		draw_rect(Rect2(x, 14.0, 9.0, s.y - 28.0), Color(FormTheme.INK, 0.7 * alpha), false, 1.5)
		x += 20.0
	# Label (and the description line).
	var tf := FormTheme.typed_font()
	var ty := FormTheme.baseline(tf, label_size, s.y)
	var hint_y := FormTheme.baseline(FormTheme.label_font(true), 21, s.y)
	if sub != "":
		ty = 10.0 + tf.get_ascent(label_size)
		hint_y = ty
		var sf := FormTheme.typed_font(false)
		draw_multiline_string(sf, Vector2(x, ty + tf.get_descent(label_size) + sf.get_ascent(19) + 2.0), sub, HORIZONTAL_ALIGNMENT_LEFT, s.x - x - 24.0, 19, sub_lines, Color(FormTheme.TYPED, 0.78 * alpha))
	draw_string(tf, Vector2(x, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color(FormTheme.TYPED, alpha))
	# Hint, printed at the right.
	if hint != "":
		var hf := FormTheme.label_font(true)
		var hw := hf.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
		draw_string(hf, Vector2(s.x - hw - 20.0, hint_y), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color(FormTheme.INK, alpha))
