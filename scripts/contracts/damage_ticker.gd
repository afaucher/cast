class_name DamageTicker
extends Control
## A live feed of property damage: every `damage` line the Ledger records shows up as
## "-$1,200  Wine rack (Wick)" in red and cream, stacks under the newest-first, and fades away.
## Pure presentation: it only listens to Ledger.line_added.
##
## Agent A adds it to the HUD:   hud_root.add_child(DamageTicker.new())
## It anchors itself to the top-right corner (below a 70px margin); reposition freely.

const WIDTH := 620.0
const ROW_HEIGHT := 30.0
const RED := Color(1.0, 0.38, 0.32)
const CREAM := Color(0.97, 0.92, 0.78)
const DIM := Color(0.8, 0.75, 0.62)

@export var max_rows := 6
@export var hold_time := 4.5
@export var fade_time := 1.2

var _box: VBoxContainer


func _init() -> void:
	name = "DamageTicker"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -WIDTH - 24.0
	offset_right = -24.0
	offset_top = 70.0
	offset_bottom = 70.0 + ROW_HEIGHT * 7.0


func _ready() -> void:
	_box = VBoxContainer.new()
	_box.name = "Rows"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box.add_theme_constant_override("separation", 2)
	_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_box)
	if not Ledger.line_added.is_connected(_on_line):
		Ledger.line_added.connect(_on_line)


func _exit_tree() -> void:
	if Ledger.line_added.is_connected(_on_line):
		Ledger.line_added.disconnect(_on_line)


## How many rows are currently on screen.
func row_count() -> int:
	return _box.get_child_count() if _box != null else 0


## Plain text of row `i` (0 = newest).
func row_text(i: int) -> String:
	if _box == null or i < 0 or i >= _box.get_child_count():
		return ""
	return (_box.get_child(i) as RichTextLabel).get_parsed_text()


## "-$1,200  Wine rack (Wick)" for a ledger damage line.
static func format_line(line: Dictionary) -> String:
	var who := String(line.get("who", ""))
	var txt := "-%s  %s" % [PricedProp.money(int(line["amount"])), String(line["label"])]
	if who != "":
		txt += " (%s)" % who
	return txt


func _on_line(line: Dictionary) -> void:
	if String(line.get("kind", "")) != "damage":
		return
	_add_row(line)


func _add_row(line: Dictionary) -> void:
	var who := String(line.get("who", ""))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.custom_minimum_size = Vector2(WIDTH, ROW_HEIGHT)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 22)
	rt.add_theme_font_size_override("bold_font_size", 22)
	rt.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.03, 0.95))
	rt.add_theme_constant_override("outline_size", 6)
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var text := "[right][b][color=#%s]-%s[/color][/b]  [color=#%s]%s[/color]" % [
			RED.to_html(false), PricedProp.money(int(line["amount"])), CREAM.to_html(false), String(line["label"])]
	if who != "":
		text += " [color=#%s](%s)[/color]" % [DIM.to_html(false), who]
	text += "[/right]"
	rt.text = text
	_box.add_child(rt)
	_box.move_child(rt, 0)   # newest on top
	while _box.get_child_count() > max_rows:
		var old := _box.get_child(_box.get_child_count() - 1)
		_box.remove_child(old)
		old.queue_free()
	# Pop in, hold, fade, go.
	rt.modulate.a = 0.0
	var tw := rt.create_tween()
	tw.tween_property(rt, "modulate:a", 1.0, 0.12)
	tw.tween_interval(hold_time)
	tw.tween_property(rt, "modulate:a", 0.0, fade_time)
	tw.tween_callback(func() -> void:
		if is_instance_valid(rt):
			if rt.get_parent() != null:
				rt.get_parent().remove_child(rt)
			rt.queue_free())
