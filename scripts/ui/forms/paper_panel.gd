class_name PaperPanel
extends PanelContainer
## A sheet of carbon-copy paper: the generated grain tinted by `carbon`, a soft drop shadow, an optional
## yellow outline (a focused job offer) and an optional tear-off perforation. Children are laid out like any
## PanelContainer; the padding is `set_padding()`. Drawn in code, so it works headless.

var carbon := FormTheme.PAPER:
	set(v):
		carbon = v
		queue_redraw()
var shadow := true:
	set(v):
		shadow = v
		queue_redraw()
## A coloured outline drawn just outside the sheet (alpha 0 = none).
var outline_color := Color(0, 0, 0, 0):
	set(v):
		outline_color = v
		queue_redraw()
var outline_width := 6.0
## y of a dashed tear-off line across the sheet (0 = none).
var tear_y := 0.0:
	set(v):
		tear_y = v
		queue_redraw()

var _pad := StyleBoxEmpty.new()


func _init(carbon_color: Color = FormTheme.PAPER) -> void:
	carbon = carbon_color
	add_theme_stylebox_override("panel", _pad)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_padding(l: float, t: float, r: float, b: float) -> void:
	_pad.content_margin_left = l
	_pad.content_margin_top = t
	_pad.content_margin_right = r
	_pad.content_margin_bottom = b
	update_minimum_size()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if shadow:
		for i in 8:
			var g := float(i) * 3.0
			var a := 0.085 * (1.0 - float(i) / 8.0)
			draw_rect(Rect2(r.position + Vector2(3, 10) - Vector2(g, g) * 0.8, r.size + Vector2(g, g) * 1.6), Color(0, 0, 0, a))
	draw_texture_rect(FormTheme.paper_texture(), r, true, carbon)
	draw_rect(r, Color(0.3, 0.25, 0.15, 0.35), false, 1.0)
	if tear_y > 0.0:
		draw_dashed_line(Vector2(0, tear_y), Vector2(r.size.x, tear_y), Color(FormTheme.INK, 0.6), 2.0, 9.0)
	if outline_color.a > 0.0:
		draw_rect(r.grow(outline_width * 0.5), outline_color, false, outline_width)
