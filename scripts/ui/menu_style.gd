class_name MenuStyle
extends RefCounted
## The look shared by the main menu, its sub-screens and the pause overlay: the job board's dark slate
## panels with amber accents. Everything is built in code (no theme resource), so the screens stay plain
## Controls that work headless.

const BG := Color(0.045, 0.05, 0.075)
const PANEL := Color(0.085, 0.095, 0.135)
const CARD := Color(0.095, 0.105, 0.15)
const CARD_HOVER := Color(0.13, 0.145, 0.205)
const TEXT := Color(0.93, 0.94, 0.98)
const DIM := Color(0.62, 0.65, 0.76)
const AMBER := Color(0.95, 0.72, 0.25)
const AMBER_HOT := Color(1.0, 0.86, 0.45)
const GOOD := Color(0.55, 0.92, 0.62)
const WARN := Color(1.0, 0.8, 0.3)
const BAD := Color(1.0, 0.5, 0.45)
const EDGE := Color(0.22, 0.25, 0.35)


static func label(text: String, size: int, color: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_color_override("font_outline_color", color)
		l.add_theme_constant_override("outline_size", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func wrapped(text: String, size: int, color: Color = DIM) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func box(bg: Color = PANEL, border: Color = EDGE, border_w: int = 2, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	return sb


static func margins(sb: StyleBoxFlat, h: float, v: float) -> StyleBoxFlat:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


## A modal-style panel (amber frame, like the elevator menu).
static func panel(border: Color = AMBER, pad_h: float = 30.0, pad_v: float = 24.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", margins(box(PANEL, border, 3, 8), pad_h, pad_v))
	return p


## A big menu button: dark slate card, amber frame while hovered or focused.
static func button(text: String, size: int = 26) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 58)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", AMBER_HOT)
	b.add_theme_color_override("font_focus_color", AMBER_HOT)
	b.add_theme_color_override("font_pressed_color", AMBER_HOT)
	b.add_theme_color_override("font_disabled_color", Color(DIM, 0.5))
	b.add_theme_stylebox_override("normal", margins(box(CARD, EDGE, 2, 6), 22, 8))
	b.add_theme_stylebox_override("hover", margins(box(CARD_HOVER, AMBER, 2, 6), 22, 8))
	b.add_theme_stylebox_override("focus", margins(box(CARD_HOVER, AMBER, 3, 6), 22, 8))
	b.add_theme_stylebox_override("pressed", margins(box(CARD_HOVER, AMBER_HOT, 3, 6), 22, 8))
	b.add_theme_stylebox_override("disabled", margins(box(Color(CARD, 0.5), EDGE, 2, 6), 22, 8))
	return b


## A small button for in-panel rows (Back, Apply ...).
static func small_button(text: String) -> Button:
	var b := button(text, 20)
	b.custom_minimum_size = Vector2(0, 44)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


## Dark styling for the stock controls (OptionButton, CheckButton, LineEdit) so they match the panels.
static func style_control(c: Control) -> void:
	if c is Button:
		var b := c as Button
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_color_override("font_color", TEXT)
		b.add_theme_color_override("font_hover_color", AMBER_HOT)
		b.add_theme_color_override("font_focus_color", AMBER_HOT)
		b.add_theme_stylebox_override("normal", margins(box(CARD, EDGE, 2, 6), 14, 6))
		b.add_theme_stylebox_override("hover", margins(box(CARD_HOVER, AMBER, 2, 6), 14, 6))
		b.add_theme_stylebox_override("pressed", margins(box(CARD_HOVER, AMBER_HOT, 2, 6), 14, 6))
		b.add_theme_stylebox_override("focus", margins(box(CARD_HOVER, AMBER, 3, 6), 14, 6))
		b.add_theme_stylebox_override("disabled", margins(box(Color(CARD, 0.5), EDGE, 2, 6), 14, 6))
	elif c is LineEdit:
		var e := c as LineEdit
		e.add_theme_font_size_override("font_size", 20)
		e.add_theme_color_override("font_color", TEXT)
		e.add_theme_stylebox_override("normal", margins(box(Color(0.03, 0.035, 0.055), EDGE, 2, 6), 12, 6))
		e.add_theme_stylebox_override("focus", margins(box(Color(0.03, 0.035, 0.055), AMBER, 2, 6), 12, 6))


## A slim slider: dark groove, amber fill.
static func style_slider(s: HSlider) -> void:
	var groove := box(Color(0.03, 0.035, 0.055), EDGE, 1, 4)
	groove.content_margin_top = 5
	groove.content_margin_bottom = 5
	var fill := box(AMBER.darkened(0.35), AMBER.darkened(0.35), 1, 4)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	s.add_theme_stylebox_override("slider", groove)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)


static func dim_rect(alpha: float = 0.78) -> ColorRect:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, alpha)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dim


static func gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
