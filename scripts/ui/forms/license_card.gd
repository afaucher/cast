class_name LicenseCard
extends Button
## One compact cell of FORM 15's licence catalog: a key-number cell (1 to 9; later cards have none), a colour bar,
## the spell's name and a tick box. A real toggle Button, so keyboard and controller focus, Enter/A and the mouse
## work natively; it draws itself (the Button's own text is transparent but stays set). Focus is the yellow
## highlighter band, a ticked card shows the red grease X in its box. The spell's details are not on the card:
## the picker's detail panel shows them for whichever card has focus.

const KEY_W := 54.0
const BOX := 28.0
const MIN_FONT := 17

var number := "":
	set(v):
		number = v
		queue_redraw()
## The "say: cast heal   cooldown 8s" line (the picker shows it in its detail panel).
var hint := ""
var swatch := Color(0, 0, 0, 0):
	set(v):
		swatch = v
		queue_redraw()
var label_size := 26:
	set(v):
		label_size = v
		queue_redraw()
## The spell this card stands for.
var spell_id := ""


func _init(label_text: String = "", number_text: String = "", card_h: float = 64.0) -> void:
	text = label_text
	number = number_text
	FormTheme.make_blank(self)
	custom_minimum_size = Vector2(250.0, card_h)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	toggle_mode = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	toggled.connect(func(_on: bool) -> void: queue_redraw())
	mouse_entered.connect(func() -> void:
		if not disabled and focus_mode != Control.FOCUS_NONE and is_inside_tree() and is_visible_in_tree():
			grab_focus())


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var s := size
	var focused := has_focus()
	if focused:
		FormTheme.draw_band(self, Rect2(-6, 3, s.x + 12, s.y - 6))
	# The ruled grid: a line under the card and one on its right.
	draw_line(Vector2(0, s.y - 1.0), Vector2(s.x, s.y - 1.0), FormTheme.INK, 2.0)
	draw_line(Vector2(s.x - 1.0, 0), Vector2(s.x - 1.0, s.y), Color(FormTheme.INK, 0.55), 2.0)
	# Key-number cell.
	draw_line(Vector2(KEY_W, 0), Vector2(KEY_W, s.y), FormTheme.INK, 2.0)
	if number != "":
		var nf := FormTheme.label_font(true)
		var nw := nf.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(nf, Vector2((KEY_W - nw) * 0.5, FormTheme.baseline(nf, 26, s.y)), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, FormTheme.INK)
	var x := KEY_W + 14.0
	if swatch.a > 0.0:
		draw_rect(Rect2(x, 13.0, 8.0, s.y - 26.0), swatch)
		draw_rect(Rect2(x, 13.0, 8.0, s.y - 26.0), Color(FormTheme.INK, 0.7), false, 1.5)
		x += 20.0
	# The tick box at the right.
	var box := Rect2(s.x - BOX - 16.0, (s.y - BOX) * 0.5, BOX, BOX)
	draw_rect(box, FormTheme.FIELD_FILL)
	draw_rect(box, FormTheme.INK, false, 2.5)
	if button_pressed:
		FormTheme.draw_grease_x(self, box)
	elif focused:
		FormTheme.draw_tick(self, box)
	# The name, shrunk to fit the room between the colour bar and the box.
	var tf := FormTheme.typed_font()
	var room := box.position.x - x - 10.0
	var fs := label_size
	while fs > MIN_FONT and tf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs -= 1
	draw_string(tf, Vector2(x, FormTheme.baseline(tf, fs, s.y)), text, HORIZONTAL_ALIGNMENT_LEFT, room, fs, FormTheme.TYPED)
