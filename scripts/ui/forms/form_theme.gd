class_name FormTheme
extends RefCounted
## The carbon-copy form look (Option B in docs/design/ui-theme-options.md): warm paper, one spot ink for
## printed lines and labels, typed values, red stamps and grease-pencil marks, a yellow highlighter band for
## focus. The ONE place that knows colours, fonts and the shared Theme; the other forms/ components and the
## screens in scripts/ui/ build on it. All sizes are in the project's 1600x900 canvas units (the window
## scales them: 1280x720 shows them at 0.8, so a 20 unit value is 16 px there).
##
## Everything here is presentation only: no GameWorld.rng, no global randf. The paper grain uses a local
## RandomNumberGenerator with a fixed seed so it looks the same every run.

# --- Ink and paper ----------------------------------------------------------------------------------
const INK := Color("1f5c63")        ## the spot ink: printed lines and labels
const TYPED := Color("1d1a26")      ## typed values
const RED := Color("b3261e")        ## warnings and stamps
const GREASE := Color("c0261c")     ## the grease pencil (ticks, circles)
const GREEN_INK := Color("17482a")  ## money
const BLUE_PEN := Color("1b3f86")   ## signatures
const PAPER := Color("f6f3ea")
const HIGHLIGHT := Color(1.0, 0.886, 0.235, 0.55)   ## the yellow highlighter band
const OUTLINE_YELLOW := Color("e2b712")
const FIELD_FILL := Color(1, 1, 1, 0.4)             ## a boxed field's fill
const FAINT := Color(0.122, 0.361, 0.388, 0.4)      ## ruled lines inside a row

## Carbon copy colours per screen family.
const CARBONS := {
	"white": Color("f6f3ea"),   # office / main
	"canary": Color("f5e6a3"),  # dispatch, job board
	"pink": Color("f4cfc8"),    # shop
	"gold": Color("ecc979"),    # settings
	"green": Color("d4e6c5"),   # crew, cosmetics
	"blue": Color("cfdfea"),    # spare
}

const FONT_DIR := "res://assets/fonts/"
const TAG_WGHT := 2003265652    ## the OpenType 'wght' axis tag, for the variable Caveat

static var _fonts: Dictionary = {}
static var _paper_tex: Texture2D = null
static var _band_tex: Texture2D = null
static var _theme: Theme = null


static func carbon(name_: String) -> Color:
	return CARBONS.get(name_, CARBONS["white"]) as Color


# --- Fonts -------------------------------------------------------------------------------------------
# Real files (OFL, assets/fonts/): Barlow Condensed (printed labels), Courier Prime (typed values), Black Ops
# One (stamps), Caveat (grease pencil; variable, weight 700). Each falls back to a SystemFont (Bahnschrift /
# Courier New / Impact / Segoe Print) when the file is not imported, so the menus never render blank.

static func _font(key: String, file: String, system_names: PackedStringArray, weight: int, spacing: int = 0, wght: float = 0.0) -> Font:
	if _fonts.has(key):
		return _fonts[key] as Font
	var fv := FontVariation.new()
	var sys := SystemFont.new()
	sys.font_names = system_names
	sys.font_weight = weight
	var base: Font = null
	if ResourceLoader.exists(FONT_DIR + file):
		base = load(FONT_DIR + file) as Font
	if base == null:
		base = sys
	else:
		fv.fallbacks = [sys]
	fv.base_font = base
	fv.spacing_glyph = spacing
	if wght > 0.0:
		fv.variation_opentype = {TAG_WGHT: wght}
	_fonts[key] = fv
	return fv


## Printed form labels: Barlow Condensed Bold. `heavy` = ExtraBold (header titles), `light` = SemiBold.
static func label_font(heavy: bool = false, light: bool = false) -> Font:
	var names := PackedStringArray(["Bahnschrift SemiCondensed", "Bahnschrift", "Arial Narrow", "Arial"])
	if heavy:
		return _font("label_xb", "barlow_condensed/BarlowCondensed-ExtraBold.ttf", names, 800, 1)
	if light:
		return _font("label_sb", "barlow_condensed/BarlowCondensed-SemiBold.ttf", names, 600, 1)
	return _font("label_b", "barlow_condensed/BarlowCondensed-Bold.ttf", names, 700, 1)


## Typed values: Courier Prime Bold (Regular for running text).
static func typed_font(bold: bool = true) -> Font:
	var names := PackedStringArray(["Courier New", "Consolas", "monospace"])
	if bold:
		return _font("typed_b", "courier_prime/CourierPrime-Bold.ttf", names, 700)
	return _font("typed_r", "courier_prime/CourierPrime-Regular.ttf", names, 400)


## Rubber stamps: Black Ops One.
static func stamp_font() -> Font:
	return _font("stamp", "black_ops_one/BlackOpsOne-Regular.ttf", PackedStringArray(["Impact", "Bahnschrift Bold", "Arial Black"]), 800)


## Grease-pencil marks and signatures (decoration only, never a value): Caveat 700.
static func hand_font() -> Font:
	return _font("hand", "caveat/Caveat-Variable.ttf", PackedStringArray(["Segoe Print", "Ink Free", "Comic Sans MS"]), 700, 0, 700.0)


# --- Labels ------------------------------------------------------------------------------------------

## A printed label (spot ink, condensed). Pass the text already upper-cased if it should be.
static func label(text: String, size: int = 18, color: Color = INK, heavy: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", label_font(heavy))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A typed value (near-black Courier).
static func typed(text: String, size: int = 22, color: Color = TYPED, bold: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", typed_font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Running typed text that wraps.
static func typed_wrapped(text: String, size: int = 20, color: Color = TYPED, bold: bool = false) -> Label:
	var l := typed(text, size, color, bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Printed small print that wraps.
static func small(text: String, size: int = 17, color: Color = INK) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", label_font(false, true))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func hand(text: String, size: int = 30, color: Color = BLUE_PEN) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", hand_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --- Small building blocks ---------------------------------------------------------------------------

static func gap(h: float, w: float = 0.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func rule(h: float = 2.0, color: Color = INK) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func dim_rect(alpha: float = 0.6) -> ColorRect:
	var d := ColorRect.new()
	d.color = Color(0.03, 0.025, 0.035, alpha)
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


static func margin(child: Control, l: float, t: float, r: float, b: float) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", int(l))
	m.add_theme_constant_override("margin_top", int(t))
	m.add_theme_constant_override("margin_right", int(r))
	m.add_theme_constant_override("margin_bottom", int(b))
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(child)
	return m


## A flat box: translucent paper fill and an ink border.
static func box_style(fill: Color = FIELD_FILL, border: Color = INK, width: float = 2.0, pad_h: float = 12.0, pad_v: float = 4.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(int(ceilf(width)))
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	sb.anti_aliasing = false
	return sb


## A boxed field around any control: ink border, light fill (the typed value goes inside).
static func boxed(child: Control, pad_h: float = 12.0, pad_v: float = 4.0, fill: Color = FIELD_FILL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box_style(fill, INK, 2.0, pad_h, pad_v))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(child)
	return p


## A small "classified ad" box for the bottom of the main-menu form.
static func ad(title: String, body: String) -> PanelContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(label(title.to_upper(), 17, INK, true))
	var t := small(body, 16, Color("2c2a2e"))
	t.custom_minimum_size = Vector2(120, 0)
	v.add_child(t)
	var p := boxed(v, 8, 5, Color(1, 1, 1, 0.3))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


# --- Drawing helpers (call from a CanvasItem's _draw) -----------------------------------------------

## The yellow highlighter band: a soft-ended translucent swipe.
static func draw_band(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_texture_rect(band_texture(), rect, false)


static func band_texture() -> Texture2D:
	if _band_tex != null:
		return _band_tex
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(HIGHLIGHT, 0.0), Color(HIGHLIGHT, 0.58), Color(HIGHLIGHT, 0.52), Color(HIGHLIGHT, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.05, 0.93, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 4
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 0)
	_band_tex = t
	return t


## The red grease-pencil tick, drawn in `box` (a hand-made check that overshoots its box a little).
static func draw_tick(ci: CanvasItem, box: Rect2, color: Color = GREASE, width: float = 4.0) -> void:
	var s := box.size.x
	var p := box.position
	var pts := PackedVector2Array([
		p + Vector2(-0.12, 0.52) * s, p + Vector2(0.14, 0.50) * s, p + Vector2(0.34, 0.86) * s,
		p + Vector2(0.62, 0.30) * s, p + Vector2(1.10, -0.28) * s,
	])
	ci.draw_polyline(pts, color, width, true)


## A typed X in `box`.
static func draw_x(ci: CanvasItem, box: Rect2, color: Color = TYPED, width: float = 3.5) -> void:
	var r := box.grow(-4.0)
	ci.draw_line(r.position, r.end, color, width, true)
	ci.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), color, width, true)


## A grease-pencil X (slightly off true).
static func draw_grease_x(ci: CanvasItem, box: Rect2, width: float = 4.0) -> void:
	var r := box.grow(-3.0)
	ci.draw_line(r.position + Vector2(-2, 1), r.end + Vector2(3, -1), GREASE, width, true)
	ci.draw_line(Vector2(r.end.x + 1, r.position.y - 3), Vector2(r.position.x - 1, r.end.y + 2), GREASE, width, true)


## Baseline y that centres a line of `size` text in a row of height `h`.
static func baseline(font: Font, size: int, h: float) -> float:
	return (h - font.get_height(size)) * 0.5 + font.get_ascent(size)


# --- Paper -------------------------------------------------------------------------------------------

## A tileable warm-white grain with a few horizontal fibres (generated once, fixed seed). It is tinted by
## the carbon colour when drawn.
static func paper_texture() -> Texture2D:
	if _paper_tex != null:
		return _paper_tex
	const N := 256
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.9
	noise.seed = 4
	var img: Image = noise.get_seamless_image(N, N, false, false, 0.1, true)
	img.convert(Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var n: float = img.get_pixel(x, y).r
			var b := 0.945 + 0.055 * n
			img.set_pixel(x, y, Color(b, b * 0.992, b * 0.975, 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 27
	for i in 150:
		var x0 := rng.randi_range(0, N - 1)
		var y0 := rng.randi_range(0, N - 1)
		var len_ := rng.randi_range(14, 60)
		var dark := rng.randf_range(0.955, 0.985)
		for k in len_:
			var px := (x0 + k) % N
			var c := img.get_pixel(px, y0)
			img.set_pixel(px, y0, Color(c.r * dark, c.g * dark, c.b * dark * 0.99, 1.0))
	_paper_tex = ImageTexture.create_from_image(img)
	return _paper_tex


# --- The shared Theme --------------------------------------------------------------------------------

static func _hot_style() -> StyleBoxFlat:
	return box_style(Color(1.0, 0.92, 0.45, 0.85), GREASE, 2.0, 18.0, 6.0)


static func _set_button_colors(t: Theme, type_name: String) -> void:
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, type_name, TYPED)
	t.set_color("font_disabled_color", type_name, Color(TYPED, 0.4))
	t.set_font("font", type_name, typed_font())
	t.set_font_size("font_size", type_name, 24)


## A Theme for the stock controls (Label, Button, LineEdit, OptionButton, PopupMenu, scrollbars) so anything
## a screen does not hand-style still looks like a form. Set it on a screen's root: `root.theme = FormTheme.theme()`.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = label_font()
	t.default_font_size = 20

	t.set_color("font_color", "Label", INK)
	t.set_font("font", "Label", label_font())

	# Buttons and the OptionButton: a boxed field; the highlighter fill while focused or hovered.
	var normal := box_style(Color(1, 1, 1, 0.35), INK, 2.0, 18.0, 6.0)
	var down := box_style(Color(1.0, 0.82, 0.2, 0.9), GREASE, 3.0, 18.0, 6.0)
	var off := box_style(Color(1, 1, 1, 0.15), Color(INK, 0.4), 2.0, 18.0, 6.0)
	for type_name in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type_name, normal)
		t.set_stylebox("hover", type_name, _hot_style())
		t.set_stylebox("focus", type_name, _hot_style())
		t.set_stylebox("pressed", type_name, down)
		t.set_stylebox("hover_pressed", type_name, down)
		t.set_stylebox("disabled", type_name, off)
		_set_button_colors(t, type_name)
	t.set_color("icon_normal_color", "OptionButton", INK)
	t.set_color("icon_hover_color", "OptionButton", GREASE)
	t.set_color("icon_focus_color", "OptionButton", GREASE)
	t.set_color("icon_pressed_color", "OptionButton", GREASE)
	t.set_color("icon_disabled_color", "OptionButton", Color(INK, 0.4))
	t.set_constant("arrow_margin", "OptionButton", 10)

	# LineEdit: a typed boxed field.
	t.set_stylebox("normal", "LineEdit", box_style(FIELD_FILL, INK, 2.0, 12.0, 6.0))
	t.set_stylebox("focus", "LineEdit", box_style(Color(1.0, 0.95, 0.6, 0.7), GREASE, 2.0, 12.0, 6.0))
	t.set_stylebox("read_only", "LineEdit", box_style(Color(1, 1, 1, 0.15), Color(INK, 0.4), 2.0, 12.0, 6.0))
	t.set_font("font", "LineEdit", typed_font())
	t.set_font_size("font_size", "LineEdit", 24)
	t.set_color("font_color", "LineEdit", TYPED)
	t.set_color("font_placeholder_color", "LineEdit", Color(TYPED, 0.45))
	t.set_color("caret_color", "LineEdit", GREASE)
	t.set_color("selection_color", "LineEdit", Color(HIGHLIGHT, 0.8))

	# PopupMenu (the OptionButton list): a paper slip, the highlighter on the hovered line.
	t.set_stylebox("panel", "PopupMenu", box_style(PAPER, INK, 2.0, 6.0, 6.0))
	t.set_stylebox("hover", "PopupMenu", box_style(HIGHLIGHT, Color(0, 0, 0, 0), 0.0, 8.0, 4.0))
	t.set_font("font", "PopupMenu", typed_font())
	t.set_font_size("font_size", "PopupMenu", 24)
	t.set_color("font_color", "PopupMenu", TYPED)
	t.set_color("font_hover_color", "PopupMenu", TYPED)
	t.set_color("font_disabled_color", "PopupMenu", Color(TYPED, 0.4))
	t.set_constant("v_separation", "PopupMenu", 10)
	t.set_constant("item_start_padding", "PopupMenu", 10)
	t.set_constant("item_end_padding", "PopupMenu", 10)

	# Scrollbars: thin ink rails.
	var rail := box_style(Color(INK, 0.15), Color(0, 0, 0, 0), 0.0, 3.0, 3.0)
	var grab := box_style(Color(INK, 0.7), Color(0, 0, 0, 0), 0.0, 3.0, 3.0)
	t.set_stylebox("scroll", "VScrollBar", rail)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	_theme = t
	return t


## A boxed form button ("Back (Esc)", "Apply") using the shared theme styles.
static func button(text: String, size: int = 24) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.theme = theme()
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 50)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled and b.is_inside_tree():
			b.grab_focus())
	return b


## Make a Button draw nothing itself (no text, no styles) so a subclass can draw everything in _draw.
static func make_blank(b: Button) -> void:
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(s, empty)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(c, Color(0, 0, 0, 0))
	b.focus_mode = Control.FOCUS_ALL


## Wire Up / Down focus between controls (already in the tree), wrapping at the ends, so keyboard and
## controller navigation never depends on screen geometry (a tilted clipboard, say).
static func chain(controls: Array, wrap: bool = true) -> void:
	var n := controls.size()
	for i in n:
		var c: Control = controls[i]
		var nxt: Control = controls[(i + 1) % n]
		var prv: Control = controls[(i - 1 + n) % n]
		if wrap or i < n - 1:
			c.focus_neighbor_bottom = c.get_path_to(nxt)
			c.focus_next = c.get_path_to(nxt)
		if wrap or i > 0:
			c.focus_neighbor_top = c.get_path_to(prv)
			c.focus_previous = c.get_path_to(prv)
