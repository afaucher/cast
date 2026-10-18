class_name CrewBadge
extends HBoxContainer
## One crew member on a roster strip (M7): their picture, then "<seat>  <name> · <Character>". The picture is the Steam
## avatar when there is one (Session.avatars, by the roster's steam_id); otherwise, and while it is still loading, a square
## in the seat's colour with the name's first letter, so the strip never waits on Steam and looks the same without it.

const PIC := 38.0
## Seat colours for the fallback square (the crew's carbon tints, darkened so the white letter reads).
const SEAT_COLORS := {1: Color("8a5a12"), 2: Color("1f5c63"), 3: Color("7a2f4a")}

var entry: Dictionary = {}
var you := false
var picture: TextureRect
var initial: Label
var name_label: Label

var _box: Control


func _init(e: Dictionary = {}, avatar: Texture2D = null, is_you: bool = false) -> void:
	entry = e
	you = is_you
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = Control.new()
	_box.custom_minimum_size = Vector2(PIC, PIC)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.draw.connect(_draw_box)
	add_child(_box)
	picture = TextureRect.new()
	picture.name = "Avatar"
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(picture)
	initial = Label.new()
	initial.name = "Initial"
	initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_override("font", FormTheme.label_font(true))
	initial.add_theme_font_size_override("font_size", 24)
	initial.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(initial)
	var name_ := str(e.get("name", ""))
	initial.text = name_.substr(0, 1).to_upper() if name_ != "" else "?"
	name_label = FormTheme.label("%d  %s · %s%s" % [int(e.get("seat", 0)), name_, str(e.get("character", "")).capitalize(),
		"  (you)" if you else ""], 20, Color(1, 1, 1, 0.92), true)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_label.add_theme_constant_override("outline_size", 5)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(name_label)
	set_avatar(avatar)


## Show the Steam picture, or the lettered square when `tex` is null.
func set_avatar(tex: Texture2D) -> void:
	picture.texture = tex
	picture.visible = tex != null
	initial.visible = tex == null
	_box.queue_redraw()


func has_avatar() -> bool:
	return picture.texture != null


func _draw_box() -> void:
	var r := Rect2(Vector2.ZERO, _box.size)
	if picture.texture == null:
		_box.draw_rect(r, SEAT_COLORS.get(int(entry.get("seat", 0)), FormTheme.INK))
	_box.draw_rect(r, Color(1, 1, 1, 0.85), false, 2.0)
