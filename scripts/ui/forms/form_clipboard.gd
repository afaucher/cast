class_name FormClipboard
extends Control
## The clipboard that holds a form on the short-list screens (main menu, pause): a wooden board with a metal
## clip, tilted a degree or so, with coloured index tabs poking out of its right edge. Put the FormSheet in
## it with set_content(). The tilt rotates the whole board (paper included); keep it small.
##
## tabs: [{text: String, color: Color}] (decoration only: the other forms in the set).

var tabs: Array[Dictionary] = []:
	set(v):
		tabs = v
		queue_redraw()
var tilt_deg := -1.0
var content: Control = null

var _grain: Array[Vector4] = []   ## y, x0, length, alpha
var _clip: ClipArt


func _init(w: float = 600.0, h: float = 800.0, tilt: float = -1.0) -> void:
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)
	tilt_deg = tilt
	rotation = deg_to_rad(tilt)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 90:
		_grain.append(Vector4(rng.randf_range(6.0, h - 6.0), rng.randf_range(0.0, w * 0.5), rng.randf_range(80.0, w * 0.9), rng.randf_range(0.04, 0.13)))
	_clip = ClipArt.new()
	add_child(_clip)
	_layout_clip()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size * 0.5
		_layout_clip()


func _layout_clip() -> void:
	if _clip != null:
		_clip.size = Vector2(210.0, 76.0)
		_clip.position = Vector2((size.x - 210.0) * 0.5, -26.0)


func set_content(c: Control, left: float = 22.0, top: float = 38.0, right: float = 22.0, bottom: float = 22.0) -> void:
	content = c
	add_child(c)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.offset_left = left
	c.offset_top = top
	c.offset_right = -right
	c.offset_bottom = -bottom
	move_child(_clip, -1)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# Index tabs first, so they tuck behind the board's right edge.
	var f := FormTheme.label_font(true)
	var y := 120.0
	for t in tabs:
		var txt := str(t["text"]).to_upper()
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var th := tw + 34.0
		var tr := Rect2(size.x - 16.0, y, 62.0, th)
		var col: Color = t["color"]
		draw_rect(Rect2(tr.position + Vector2(3, 4), tr.size), Color(0, 0, 0, 0.35))
		draw_rect(tr, col)
		draw_rect(tr, Color(0.25, 0.2, 0.1, 0.45), false, 1.5)
		draw_set_transform(Vector2(tr.position.x + 36.0, tr.position.y + 17.0), PI * 0.5, Vector2.ONE)
		draw_string(f, Vector2.ZERO, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, FormTheme.INK)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		y += th + 10.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("6d4528")
	sb.set_corner_radius_all(18)
	sb.border_color = Color(1, 1, 1, 0.1)
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 28
	sb.shadow_offset = Vector2(0, 16)
	draw_style_box(sb, r)
	draw_rect(Rect2(10, 10, size.x - 20, size.y * 0.5), Color(1, 0.8, 0.5, 0.05))
	for g in _grain:
		draw_line(Vector2(g.y, g.x), Vector2(minf(g.y + g.z, size.x - 10.0), g.x + 1.5), Color(0.16, 0.08, 0.03, g.w), 2.0)


## The metal clip at the top of the board.
class ClipArt:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("8a8d96")
		sb.set_corner_radius_all(12)
		sb.border_color = Color("3a3b42")
		sb.set_border_width_all(3)
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 8
		sb.shadow_offset = Vector2(0, 5)
		draw_style_box(sb, r)
		draw_rect(Rect2(10, 8, size.x - 20, 14), Color(1, 1, 1, 0.22))
		var hole := StyleBoxFlat.new()
		hole.bg_color = Color("3d3d44")
		hole.set_corner_radius_all(9)
		hole.border_color = Color(0, 0, 0, 0.5)
		hole.set_border_width_all(2)
		draw_style_box(hole, Rect2(size.x * 0.5 - 30.0, 30.0, 60.0, 18.0))
