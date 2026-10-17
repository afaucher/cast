class_name BoxScale
extends Range
## A slider drawn as a row of boxes (10 by default), filled in typed ink up to the value. It is a Range, so
## `value`, `min_value`, `max_value`, `step` and `value_changed` behave as on an HSlider. Keyboard and
## controller: Left / Right move one box (Shift: one `step`); the mouse clicks or drags to a box. Focus shows
## the red grease-pencil arrow at the end of the scale.

const BOX := 38.0
const GAP := 6.0
const ARROW_W := 76.0

var boxes := 10:
	set(v):
		boxes = maxi(1, v)
		update_minimum_size()
		queue_redraw()
## How far Left / Right move (0 = one box's worth of the range).
var key_step := 0.0

var _dragging := false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	step = 1.0
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value_changed.connect(func(_v: float) -> void: queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(func() -> void:
		if is_inside_tree() and is_visible_in_tree():
			grab_focus())


func _get_minimum_size() -> Vector2:
	return Vector2(boxes * (BOX + GAP) - GAP + ARROW_W, 46.0)


## The value at which `count_filled` boxes are full.
func box_value(count_filled: int) -> float:
	return min_value + (max_value - min_value) * float(count_filled) / float(boxes)


func _key_step() -> float:
	return key_step if key_step > 0.0 else (max_value - min_value) / float(boxes)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_right", true):
		var dir := -1.0 if event.is_action("ui_left") else 1.0
		var st := step if (event is InputEventKey and (event as InputEventKey).shift_pressed) else _key_step()
		value = clampf(value + dir * st, min_value, max_value)
		accept_event()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			grab_focus()
			_set_from_x((event as InputEventMouseButton).position.x)
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x((event as InputEventMouseMotion).position.x)


func _set_from_x(x: float) -> void:
	var idx := int(floorf((x + GAP * 0.5) / (BOX + GAP)))
	if x < BOX * 0.25:
		idx = -1
	value = box_value(clampi(idx + 1, 0, boxes))


func _draw() -> void:
	var span := max_value - min_value
	var frac := 0.0 if span <= 0.0 else (value - min_value) / span
	var f := FormTheme.label_font(true)
	var y := (size.y - BOX) * 0.5
	for i in boxes:
		var r := Rect2(i * (BOX + GAP), y, BOX, BOX)
		var lo := float(i) / float(boxes)
		var hi := float(i + 1) / float(boxes)
		var fill := clampf((frac - lo) / (hi - lo), 0.0, 1.0)
		draw_rect(r, FormTheme.FIELD_FILL)
		if fill > 0.0:
			draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), Color(FormTheme.TYPED, 0.88))
		draw_rect(r, FormTheme.INK, false, 2.5)
		var s := str(i + 1)
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		draw_string(f, Vector2(r.position.x + (BOX - w) * 0.5, y + FormTheme.baseline(f, 19, BOX)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, FormTheme.PAPER if fill >= 0.99 else FormTheme.INK)
	if has_focus():
		var ex := boxes * (BOX + GAP) - GAP + 14.0
		var cy := size.y * 0.5
		var b := Vector2(ex, cy)
		draw_polyline(PackedVector2Array([Vector2(ex + 52.0, cy + 2.0), Vector2(ex + 26.0, cy - 2.0), b]), FormTheme.GREASE, 4.0, true)
		draw_polyline(PackedVector2Array([b + Vector2(13, -11), b, b + Vector2(12, 12)]), FormTheme.GREASE, 4.0, true)
