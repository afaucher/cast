class_name RequisitionLine
extends Button
## One line item of a requisition (FORM 15 / 15-S, SpellPicker): a printed box the player ticks with the red grease
## pencil, then the typed columns: the item (with its colour tag), its component and its cooldown. A real toggle Button,
## so keyboard and controller focus, Enter / A and the mouse work natively; it draws itself (the Button's own text is
## transparent but stays set, so `line.text` reads as usual). Focus is the yellow highlighter band; a ticked line has the
## red tick in its box (the tick IS the record: nothing else on the form repeats what was chosen).
##
## The columns are fixed from the left (COL_*), so a scrollbar on the right never shifts them; `Captions` prints the
## matching column heads above the lines.

const BOX := 26.0
const COL_ITEM := 62.0        ## the box column's width: the item starts here
const COL_COMPONENT := 500.0  ## where the component column starts
const COL_COOLDOWN := 830.0   ## where the cooldown column starts
const TYPE_SIZE := 21
const MIN_FONT := 15

## The spell (or item) this line stands for.
var spell_id := ""
var swatch := Color(0, 0, 0, 0):
	set(v):
		swatch = v
		queue_redraw()
var component := "":
	set(v):
		component = v
		queue_redraw()
var cooldown := "":
	set(v):
		cooldown = v
		queue_redraw()


func _init(item: String = "", line_h: float = 46.0) -> void:
	text = item
	FormTheme.make_blank(self)
	custom_minimum_size = Vector2(COL_COOLDOWN + 120.0, line_h)
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


## The red tick is in this line's box (it is ticked).
func ticked() -> bool:
	return button_pressed


func _draw() -> void:
	var s := size
	if has_focus():
		FormTheme.draw_band(self, Rect2(-4, 3, s.x + 8, s.y - 6))
	# The ruled ledger: a line under each item and the column rules.
	draw_line(Vector2(0, s.y - 1.0), Vector2(s.x, s.y - 1.0), FormTheme.FAINT, 1.5)
	for x in [COL_ITEM, COL_COMPONENT, COL_COOLDOWN]:
		draw_line(Vector2(x, 0), Vector2(x, s.y), FormTheme.FAINT, 1.5)
	# The printed box, ticked in red grease pencil.
	var box := Rect2((COL_ITEM - BOX) * 0.5, (s.y - BOX) * 0.5, BOX, BOX)
	draw_rect(box, FormTheme.FIELD_FILL)
	draw_rect(box, FormTheme.INK, false, 2.5)
	if button_pressed:
		FormTheme.draw_tick(self, box)
	# The item: its colour tag, then the typed name.
	var x := COL_ITEM + 16.0
	if swatch.a > 0.0:
		draw_rect(Rect2(x, 12.0, 7.0, s.y - 24.0), swatch)
		draw_rect(Rect2(x, 12.0, 7.0, s.y - 24.0), Color(FormTheme.INK, 0.7), false, 1.5)
		x += 19.0
	_typed_cell(text, x, COL_COMPONENT - 12.0)
	_typed_cell(component, COL_COMPONENT + 16.0, COL_COOLDOWN - 12.0)
	_typed_cell(cooldown, COL_COOLDOWN + 16.0, s.x - 10.0)


## A typed value between x0 and x1, in the form's one typewriter (shrunk only if a made-up name will not fit).
func _typed_cell(value: String, x0: float, x1: float) -> void:
	if value == "":
		return
	var tf := FormTheme.typed_font()
	var room := x1 - x0
	var fs := TYPE_SIZE
	while fs > MIN_FONT and tf.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs -= 1
	draw_string(tf, Vector2(x0, FormTheme.baseline(tf, fs, size.y)), value, HORIZONTAL_ALIGNMENT_LEFT, room, fs, FormTheme.TYPED)


## The printed column heads over a list of RequisitionLines (same COL_* positions).
class Captions:
	extends Control
	var heads: Array = ["License", "Component", "Cooldown"]
	const SIZE := 16

	func _init() -> void:
		custom_minimum_size = Vector2(0, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var f := FormTheme.label_font(true)
		var y := FormTheme.baseline(f, SIZE, size.y)
		var xs := [COL_ITEM, COL_COMPONENT, COL_COOLDOWN]
		for i in mini(heads.size(), xs.size()):
			draw_string(f, Vector2(float(xs[i]) + 16.0, y), str(heads[i]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, FormTheme.INK)
		for x in xs:
			draw_line(Vector2(x, 0), Vector2(x, size.y), FormTheme.FAINT, 1.5)
		draw_line(Vector2(0, size.y - 1.0), Vector2(size.x, size.y - 1.0), FormTheme.INK, 2.0)
