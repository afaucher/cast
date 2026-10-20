class_name FormStamp
extends Control
## A red rubber stamp: a double border, one or more lines in the stamp face, an optional row of 1-3 stars,
## tilted a few degrees, inked at 88% so the paper shows through. (A true multiply blend turns every glyph
## quad into a solid block in Godot's canvas renderer, so it is plain alpha.) Pass fixed angles.

var lines := PackedStringArray()
var font_size := 28
var angle_deg := -8.0:
	set(v):
		angle_deg = v
		rotation = deg_to_rad(v)
## -1 = no stars row; otherwise how many of `star_count` are inked.
var stars := -1
var star_count := 3
## A last line under the stars (a verdict), in a smaller face.
var footer := "":
	set(v):
		footer = v
		update_minimum_size()
		size = get_combined_minimum_size()
		queue_redraw()
var ink := Color(FormTheme.RED, 0.88)


func _init(text: String = "", size_px: int = 28, angle: float = -8.0, star_value: int = -1) -> void:
	lines = text.split("\n")
	font_size = size_px
	stars = star_value
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	angle_deg = angle
	size = _get_minimum_size()



func _get_minimum_size() -> Vector2:
	var f := FormTheme.stamp_font()
	var w := 0.0
	for l in lines:
		w = maxf(w, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var h := f.get_height(font_size) * lines.size()
	if stars >= 0:
		w = maxf(w, star_count * (font_size + 6.0))
		h += font_size + 10.0
	if footer != "":
		var ff := FormTheme.stamp_font()
		w = maxf(w, ff.get_string_size(footer, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_size * 0.66)).x)
		h += ff.get_height(int(font_size * 0.66)) + 4.0
	return Vector2(w + 54.0, h + 36.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size * 0.5


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r.grow(-2.0), ink, false, 5.0)
	draw_rect(r.grow(-12.0), ink, false, 2.0)
	var f := FormTheme.stamp_font()
	var lh := f.get_height(font_size)
	var fs := int(font_size * 0.66)
	var total := lh * lines.size() + (font_size + 10.0 if stars >= 0 else 0.0) + (f.get_height(fs) + 4.0 if footer != "" else 0.0)
	var y := (size.y - total) * 0.5
	for l in lines:
		var w := f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(f, Vector2((size.x - w) * 0.5, y + f.get_ascent(font_size)), l, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
		y += lh
	if stars >= 0:
		var sz := float(font_size)
		var row_w := star_count * sz + (star_count - 1) * 6.0
		var x0 := (size.x - row_w) * 0.5
		for i in star_count:
			var c := Vector2(x0 + sz * 0.5 + i * (sz + 6.0), y + sz * 0.55)
			draw_colored_polygon(star_points(c, sz * 0.5), ink if i < stars else Color(ink, 0.2))
		y += sz + 10.0
	if footer != "":
		var fw := f.get_string_size(footer, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2((size.x - fw) * 0.5, y + 2.0 + f.get_ascent(fs)), footer, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


static func star_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + k * PI / 5.0
		var rr := r if k % 2 == 0 else r * 0.42
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts
