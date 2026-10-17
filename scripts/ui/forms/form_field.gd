class_name FormField
extends HBoxContainer
## A labelled field in a ruled row: the typed label on the left and any control(s) on the right. Controls
## added with add() are "watched": while one has focus (mouse hover grabs focus, so keyboard, controller and
## mouse all agree) the whole row gets the yellow highlighter band and the red tick.

var label: Label
var bleed := 22.0

var _watched: Array[Control] = []


func _init(label_text: String = "", control: Control = null, label_w: float = 250.0, min_h: float = 60.0) -> void:
	add_theme_constant_override("separation", 14)
	custom_minimum_size = Vector2(0, min_h)
	mouse_filter = Control.MOUSE_FILTER_STOP
	label = FormTheme.typed(label_text, 24)
	label.custom_minimum_size = Vector2(label_w, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(label)
	if control != null:
		add(control)
	mouse_entered.connect(func() -> void:
		for c in _watched:
			if _grabbable(c):
				c.grab_focus()
				return)


## Add a control to the row. `watch_it` = it drives the row's focus band.
func add(control: Control, expand: bool = false, watch_it: bool = true) -> Control:
	if control.size_flags_vertical == Control.SIZE_FILL:
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if expand:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(control)
	if watch_it:
		watch(control)
	return control


func watch(c: Control) -> void:
	_watched.append(c)
	c.focus_entered.connect(queue_redraw)
	c.focus_exited.connect(queue_redraw)
	c.mouse_entered.connect(func() -> void:
		if _grabbable(c):
			c.grab_focus())
	if c is FormCheck:
		(c as FormCheck).own_band = false


func _grabbable(c: Control) -> bool:
	if not is_instance_valid(c) or not c.is_inside_tree() or not c.is_visible_in_tree() or c.focus_mode == Control.FOCUS_NONE:
		return false
	if c is BaseButton and (c as BaseButton).disabled:
		return false
	return true


func _focused() -> bool:
	for c in _watched:
		if is_instance_valid(c) and c.has_focus():
			return true
	return false


func _draw() -> void:
	draw_line(Vector2(0, size.y - 1.0), Vector2(size.x, size.y - 1.0), FormTheme.FAINT, 1.5)
	if _focused():
		FormTheme.draw_band(self, Rect2(-bleed, 2, size.x + bleed * 2.0, size.y - 4))
		var box := Rect2(-bleed - 3.0, size.y * 0.5 - 6.0, 18.0, 18.0)
		FormTheme.draw_tick(self, box, FormTheme.GREASE, 3.5)
