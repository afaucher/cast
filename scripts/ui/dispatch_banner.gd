class_name DispatchBanner
extends Control
## Dispatch on the crew's headset (docs/design/notes-rethink.md, section 4): a canary strip at the top centre
## with a headset glyph as its frame, so no "Dispatch:" prefix is needed. Canary is dispatch's carbon
## (FormTheme.CARBONS). An optional first line above the dispatch line (floor 1: the client's event, typed).
##
##   banner.show_line("Floor 2. Halfway down. The pay gets better. So do the imps.", 6.0)
##   banner.show_line(line, 7.0, run.story["event"])
##
## Pure presentation, LOCAL to each machine.

const WIDTH := 760.0
const TOP := 112.0
const PAD := 18.0
const GLYPH_W := 64.0
const FADE := 0.8

var line := ""
var lead := ""
var hold := 0.0             ## seconds left at full strength
var alpha := 0.0


func _init() -> void:
	name = "DispatchBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	modulate.a = 0.0


## Who may write each var (see Net). All presentation, kept per machine.
func net_fields() -> Dictionary:
	return {"line": Net.LOCAL, "lead": Net.LOCAL, "hold": Net.LOCAL, "alpha": Net.LOCAL}


func show_line(text: String, seconds: float, lead_text: String = "") -> void:
	line = text
	lead = lead_text
	hold = seconds
	alpha = 1.0
	_relayout()
	queue_redraw()


func _process(delta: float) -> void:
	if hold > 0.0:
		hold -= delta
	elif alpha > 0.0:
		alpha = maxf(0.0, alpha - delta / FADE)
	modulate.a = alpha


func _text_w() -> float:
	return WIDTH - GLYPH_W - PAD * 2.0


func _relayout() -> void:
	var h := PAD * 2.0
	if lead != "":
		h += FormTheme.typed_font(false).get_multiline_string_size(lead, HORIZONTAL_ALIGNMENT_LEFT, _text_w(), 19).y + 8.0
	h += FormTheme.label_font(true).get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, _text_w(), 27).y
	h = maxf(h, 76.0)
	size = Vector2(WIDTH, h)
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = TOP
	offset_bottom = TOP + h


func _draw() -> void:
	if line == "":
		return
	var r := Rect2(Vector2.ZERO, size)
	for i in 6:
		var g := float(i) * 3.0
		draw_rect(Rect2(Vector2(3, 8) - Vector2(g, g) * 0.8, r.size + Vector2(g, g) * 1.6), Color(0, 0, 0, 0.08 * (1.0 - float(i) / 6.0)))
	draw_texture_rect(FormTheme.paper_texture(), r, true, FormTheme.carbon("canary"))
	draw_rect(Rect2(0, 0, GLYPH_W, r.size.y), Color(FormTheme.INK, 0.92))
	_headset(Vector2(GLYPH_W * 0.5, r.size.y * 0.5))
	var x := GLYPH_W + PAD
	var y := PAD
	if lead != "":
		var tf := FormTheme.typed_font(false)
		draw_multiline_string(tf, Vector2(x, y + tf.get_ascent(19)), lead, HORIZONTAL_ALIGNMENT_LEFT, _text_w(), 19, -1, Color(FormTheme.TYPED, 0.8))
		y += tf.get_multiline_string_size(lead, HORIZONTAL_ALIGNMENT_LEFT, _text_w(), 19).y + 8.0
	var lf := FormTheme.label_font(true)
	draw_multiline_string(lf, Vector2(x, y + lf.get_ascent(27)), line, HORIZONTAL_ALIGNMENT_LEFT, _text_w(), 27, -1, FormTheme.INK)


## A headset: the band, two ear cups and the boom mic, in paper on the ink panel.
func _headset(c: Vector2) -> void:
	var col := FormTheme.carbon("canary")
	draw_arc(c + Vector2(0, 2), 16.0, PI * 1.08, PI * 1.92, 16, col, 4.0, true)
	draw_rect(Rect2(c + Vector2(-21, -2), Vector2(9, 15)), col)
	draw_rect(Rect2(c + Vector2(12, -2), Vector2(9, 15)), col)
	draw_polyline(PackedVector2Array([c + Vector2(-17, 13), c + Vector2(-14, 21), c + Vector2(-2, 23)]), col, 3.0, true)
	draw_circle(c + Vector2(1, 23), 3.5, col)
