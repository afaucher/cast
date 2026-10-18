class_name SignRow
extends Button
## The line a form is submitted on (form-rules.md: submitting is signing): a printed caption ("REQUESTED BY") and a
## ruled SignLine. It is a real Button, so Enter / A / a click press it; the form decides what pressing means and calls
## sign(name), which stamps the player's name on the line in red (SignLine.draw_stamp, the job board's Take stamp).
## While `disabled` (the form is not complete yet) it is inert: keyboard focus can still land on it (the band shows where
## you are) but pressing does nothing. Focus is the yellow band, as on every row.

const ROW_H := 62.0
const CAPTION_SIZE := 20

var caption := "":
	set(v):
		caption = v
		text = v
		_place_line()
		queue_redraw()
var line: SignLine


func _init(caption_text: String = "Requested by") -> void:
	FormTheme.make_blank(self)
	custom_minimum_size = Vector2(300.0, ROW_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	line = SignLine.new()
	line.name = "SignLine"
	line.style = "stamp"
	add_child(line)
	caption = caption_text
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(func() -> void:
		if not disabled and focus_mode != Control.FOCUS_NONE and is_inside_tree() and is_visible_in_tree():
			grab_focus())


## Stamp `who` on the line ("" clears it).
func sign(who: String) -> void:
	line.signature = who


func signature() -> String:
	return line.signature


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place_line()
		queue_redraw()
	elif what == NOTIFICATION_DISABLED or what == NOTIFICATION_ENABLED:
		queue_redraw()


func _caption_w() -> float:
	return FormTheme.label_font(true).get_string_size(caption.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE).x


func _place_line() -> void:
	if line == null:
		return
	var x := 22.0 + _caption_w() + 14.0
	line.position = Vector2(x, 8.0)
	line.size = Vector2(maxf(size.x - x - 30.0, 40.0), size.y - 18.0)


func _draw() -> void:
	if has_focus():
		FormTheme.draw_band(self, Rect2(-10, 3, size.x + 20, size.y - 6))
	var f := FormTheme.label_font(true)
	# The caption sits on the line's baseline, as on a printed form.
	var base := line.position.y + line.size.y - 3.0 - f.get_descent(CAPTION_SIZE) - 1.0
	draw_string(f, Vector2(22.0, base), caption.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_SIZE, FormTheme.INK)
