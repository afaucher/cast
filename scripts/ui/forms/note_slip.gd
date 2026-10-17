class_name NoteSlip
extends Control
## The on-screen slip for a note the player is reading (docs/design/notes-rethink.md). It slides in at the lower
## left drawn in the note's own format, so the object is the frame and no "Note:" label is needed:
##   sticky     a yellow square in grease-pencil handwriting, tilted, the signature right-aligned
##   report     white carbon, the header as a printed title, a typed body, a red stamp
##   sign       a glossy plate with hazard-stripe bands, the ALL-CAPS rule big, pen additions in red hand
##   voicemail  a dark phone card: "1 new voicemail", the caller, the transcript, a waveform
##   memo       letterhead in the client's accent colour, the company, a typed body
##   complaint  pink carbon, URGENT ticked, the free text handwritten in blue pen
## Opened and closed by the game (E on the note; E again or walking away closes it). Never blocks input.
##
##   var slip := NoteSlip.new(); hud.add_overlay(slip)
##   slip.open_note("sign", "Bunker Protocol", "DO NOT ...", accent, "Pemberton Resilience Partners")
##   slip.close_note()
##
## Pure presentation, LOCAL to each machine: no GameWorld.rng, no global randf (the report's number and the
## waveform come from the text's hash).

const MARGIN := 24.0
const BOTTOM := 150.0       ## clear of the spell cards along the bottom edge
const SLIDE_TIME := 0.22
const WIDTHS := {"sticky": 400.0, "report": 520.0, "sign": 500.0, "voicemail": 480.0, "memo": 520.0, "complaint": 520.0}
const STICKY := Color("f7dc5c")
const STICKY_INK := Color("23284a")
const PHONE := Color("1b1d24")
const PHONE_TEXT := Color("e9e6dc")
const PINK := Color("f4cfc8")
const HAZARD := Color("f3c514")

var format := ""
var header := ""
var text := ""
var accent := Color(0.4, 0.4, 0.45)
var company := ""
var shown := false          ## true while open (or sliding in)
var slide := 0.0            ## 0 = off-screen, 1 = in place

var _w := 400.0
var _h := 200.0
var _layout := {}           ## measured pieces of the current slip


func _init() -> void:
	name = "NoteSlip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	visible = false


## Who may write each var (see Net). All presentation, kept per machine.
func net_fields() -> Dictionary:
	return {
		"format": Net.LOCAL, "header": Net.LOCAL, "text": Net.LOCAL, "accent": Net.LOCAL, "company": Net.LOCAL,
		"shown": Net.LOCAL, "slide": Net.LOCAL, "_w": Net.LOCAL, "_h": Net.LOCAL, "_layout": Net.LOCAL,
	}


func open_note(new_format: String, new_header: String, new_text: String, new_accent: Color = Color(0.4, 0.4, 0.45), new_company: String = "") -> void:
	var same := shown and new_format == format and new_text == text
	format = new_format
	header = new_header
	text = new_text
	accent = new_accent
	company = new_company
	_measure()
	if not same:
		slide = 0.0
	shown = true
	visible = true
	queue_redraw()


func close_note() -> void:
	shown = false


func is_open() -> bool:
	return shown


func _process(delta: float) -> void:
	slide = move_toward(slide, 1.0 if shown else 0.0, delta / SLIDE_TIME)
	if slide <= 0.0 and not shown:
		visible = false
		return
	var e := 1.0 - pow(1.0 - slide, 3.0)
	var parent_h := get_parent_area_size().y if get_parent() is Control else 900.0
	position = Vector2(lerpf(-_w - 60.0, MARGIN, e), parent_h - _h - BOTTOM)
	modulate.a = clampf(slide * 1.6, 0.0, 1.0)


# --- Measuring ----------------------------------------------------------------------------------------------

func _text_h(font: Font, s: String, width: float, fsize: int) -> float:
	if s == "":
		return 0.0
	return font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, fsize).y


## Split a trailing "— Name" signature off the body.
static func split_signature(s: String) -> PackedStringArray:
	var i := s.rfind(" — ")
	if i > 0:
		return PackedStringArray([s.substr(0, i), s.substr(i + 1)])
	return PackedStringArray([s, ""])


## Split a sign into its ALL-CAPS rule, the printed small print, and a "(In pen ...)" addition.
static func split_sign(s: String) -> PackedStringArray:
	var pen := ""
	var body := s
	var p := body.find("(In pen")
	if p >= 0:
		pen = body.substr(p).trim_prefix("(").trim_suffix(")")
		body = body.substr(0, p).strip_edges()
	# the headline is the leading run of sentences with no lower-case letters
	var cut := 0
	var i := 0
	while i < body.length():
		var j := body.find(". ", i)
		var end := body.length() if j < 0 else j + 1
		var sentence := body.substr(i, end - i)
		if sentence != sentence.to_upper():
			break
		cut = end
		i = end + 1
		if j < 0:
			break
	var head := body.substr(0, cut).strip_edges()
	var rest := body.substr(cut).strip_edges()
	if head == "":
		head = rest
		rest = ""
	return PackedStringArray([head, rest, pen])


func _measure() -> void:
	_w = float(WIDTHS.get(format, 500.0))
	_layout = {}
	var inner := _w - 56.0
	match format:
		"sticky":
			var parts := split_signature(text)
			_layout["body"] = parts[0]
			_layout["sig"] = parts[1]
			var hf := FormTheme.hand_font()
			_h = 46.0 + _text_h(hf, parts[0], inner, 34) + (44.0 if parts[1] != "" else 8.0) + 22.0
			_h = maxf(_h, _w * 0.72)
		"sign":
			var sp := split_sign(text)
			_layout["head"] = sp[0]
			_layout["rest"] = sp[1]
			_layout["pen"] = sp[2]
			_h = 30.0 + 30.0 + _text_h(FormTheme.label_font(true), sp[0], inner, 34) + 10.0
			_h += _text_h(FormTheme.label_font(false, true), sp[1], inner, 23) + (8.0 if sp[1] != "" else 0.0)
			_h += _text_h(FormTheme.hand_font(), sp[2], inner, 30) + (6.0 if sp[2] != "" else 0.0)
			_h += 42.0
		"voicemail":
			var caller := header
			var dot := header.find(" · ")
			if dot >= 0:
				caller = header.substr(dot + 3)
			_layout["caller"] = caller
			_h = 24.0 + 26.0 + 36.0 + 14.0 + _text_h(FormTheme.typed_font(false), "\"%s\"" % text, inner, 21) + 18.0 + 40.0 + 34.0
		"memo":
			_h = 28.0 + 34.0 + 26.0 + 18.0 + _text_h(FormTheme.typed_font(false), text, inner, 21) + 30.0
		"complaint":
			var cp := split_signature(text)
			_layout["body"] = cp[0]
			_layout["sig"] = cp[1]
			_h = 24.0 + 34.0 + 16.0 + 34.0 + 26.0 + _text_h(FormTheme.hand_font(), cp[0], inner, 30) + (40.0 if cp[1] != "" else 0.0) + 26.0
		_:   # report
			_h = 24.0 + 34.0 + 16.0 + _text_h(FormTheme.typed_font(false), text, inner - 14.0, 21) + 70.0
	size = Vector2(_w, _h)
	pivot_offset = size * 0.5
	rotation = deg_to_rad(-2.5) if format == "sticky" else (deg_to_rad(1.2) if format == "complaint" else 0.0)


# --- Drawing ------------------------------------------------------------------------------------------------

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	_shadow(r)
	match format:
		"sticky": _draw_sticky(r)
		"sign": _draw_sign(r)
		"voicemail": _draw_voicemail(r)
		"memo": _draw_memo(r)
		"complaint": _draw_complaint(r)
		_: _draw_report(r)


func _shadow(r: Rect2) -> void:
	for i in 7:
		var g := float(i) * 3.0
		draw_rect(Rect2(r.position + Vector2(4, 10) - Vector2(g, g) * 0.8, r.size + Vector2(g, g) * 1.6), Color(0, 0, 0, 0.09 * (1.0 - float(i) / 7.0)))


func _paper(r: Rect2, tint: Color) -> void:
	draw_texture_rect(FormTheme.paper_texture(), r, true, tint)
	draw_rect(r, Color(0.3, 0.25, 0.15, 0.35), false, 1.0)


func _text(font: Font, pos: Vector2, s: String, width: float, fsize: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> float:
	if s == "":
		return 0.0
	draw_multiline_string(font, pos + Vector2(0, font.get_ascent(fsize)), s, align, width, fsize, -1, col)
	return _text_h(font, s, width, fsize)


func _draw_sticky(r: Rect2) -> void:
	draw_rect(r, STICKY)
	draw_rect(Rect2(0, 0, r.size.x, 26), STICKY.darkened(0.08))
	# a curled bottom-right corner
	var c := r.size
	draw_colored_polygon(PackedVector2Array([c - Vector2(46, 0), c, c - Vector2(0, 46)]), Color(0, 0, 0, 0.18))
	draw_colored_polygon(PackedVector2Array([c - Vector2(46, 0), c - Vector2(0, 46), c - Vector2(30, 30)]), STICKY.lightened(0.15))
	var hf := FormTheme.hand_font()
	var inner := r.size.x - 56.0
	var y := 46.0
	y += _text(hf, Vector2(28, y), str(_layout.get("body", text)), inner, 34, STICKY_INK)
	var sig := str(_layout.get("sig", ""))
	if sig != "":
		_text(hf, Vector2(28, y + 10.0), sig, inner, 32, STICKY_INK, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_report(r: Rect2) -> void:
	_paper(r, FormTheme.carbon("white"))
	var lf := FormTheme.label_font(true)
	var inner := r.size.x - 56.0
	var title := (header if header != "" else "Report").to_upper()
	draw_string(lf, Vector2(28, 24 + lf.get_ascent(28)), title, HORIZONTAL_ALIGNMENT_LEFT, inner - 110.0, 28, FormTheme.INK)
	var no := "No. %04d" % (absi(text.hash()) % 9000 + 1000)
	var tf := FormTheme.typed_font()
	draw_string(tf, Vector2(r.size.x - 28.0 - tf.get_string_size(no, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, 24 + lf.get_ascent(28)), no, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, FormTheme.RED)
	draw_line(Vector2(28, 64), Vector2(r.size.x - 28, 64), FormTheme.INK, 2.0)
	draw_line(Vector2(34, 74), Vector2(34, r.size.y - 18), Color(FormTheme.RED, 0.35), 1.5)
	var y := 78.0
	_text(FormTheme.typed_font(false), Vector2(46, y), text, inner - 14.0, 21, FormTheme.TYPED)
	_stamp(Vector2(r.size.x - 120.0, r.size.y - 44.0), "FILED", -9.0)


func _stamp(at: Vector2, word: String, angle: float) -> void:
	var sf := FormTheme.stamp_font()
	var w := sf.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	draw_set_transform(at, deg_to_rad(angle), Vector2.ONE)
	var box := Rect2(Vector2(-10, -26), Vector2(w + 20, 34))
	draw_rect(box, Color(FormTheme.RED, 0.6), false, 2.5)
	draw_string(sf, Vector2(0, 0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(FormTheme.RED, 0.6))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _hazard_band(y: float, w: float, h: float) -> void:
	draw_rect(Rect2(0, y, w, h), HAZARD)
	var step := 26.0
	var x := -h
	while x < w:
		draw_colored_polygon(PackedVector2Array([Vector2(maxf(x, 0.0), y + h), Vector2(clampf(x + h, 0, w), y), Vector2(clampf(x + h + step * 0.5, 0, w), y), Vector2(clampf(x + step * 0.5, 0, w), y + h)]), FormTheme.TYPED)
		x += step


func _draw_sign(r: Rect2) -> void:
	draw_rect(r, Color("fbfbf8"))
	_hazard_band(0.0, r.size.x, 16.0)
	_hazard_band(r.size.y - 16.0, r.size.x, 16.0)
	var inner := r.size.x - 56.0
	var y := 30.0
	if header != "":
		draw_string(FormTheme.label_font(), Vector2(28, y + FormTheme.label_font().get_ascent(19)), header.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, inner, 19, FormTheme.INK)
	y += 30.0
	y += _text(FormTheme.label_font(true), Vector2(28, y), str(_layout.get("head", text)), inner, 34, FormTheme.TYPED) + 10.0
	var rest := str(_layout.get("rest", ""))
	if rest != "":
		y += _text(FormTheme.label_font(false, true), Vector2(28, y), rest, inner, 23, Color("2c2a2e")) + 8.0
	var pen := str(_layout.get("pen", ""))
	if pen != "":
		_text(FormTheme.hand_font(), Vector2(36, y), pen, inner - 8.0, 30, FormTheme.GREASE)
	# lamination: a soft diagonal sheen and a rounded clear edge
	draw_colored_polygon(PackedVector2Array([Vector2(r.size.x * 0.55, 0), Vector2(r.size.x * 0.75, 0), Vector2(r.size.x * 0.35, r.size.y), Vector2(r.size.x * 0.15, r.size.y)]), Color(1, 1, 1, 0.16))
	draw_rect(r.grow(3.0), Color(1, 1, 1, 0.5), false, 3.0)


func _draw_voicemail(r: Rect2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PHONE
	sb.set_corner_radius_all(20)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(2)
	draw_style_box(sb, r)
	var lf := FormTheme.label_font(true)
	var inner := r.size.x - 56.0
	var y := 24.0
	draw_circle(Vector2(36, y + 12), 7.0, Color(1.0, 0.25, 0.2))
	draw_string(lf, Vector2(52, y + lf.get_ascent(20)), "1 NEW VOICEMAIL", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(PHONE_TEXT, 0.75))
	var secs := 6 + text.length() / 9
	var dur := "0:%02d" % secs
	var tf := FormTheme.typed_font(false)
	draw_string(tf, Vector2(r.size.x - 28.0 - tf.get_string_size(dur, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, y + lf.get_ascent(20)), dur, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(PHONE_TEXT, 0.6))
	y += 26.0
	draw_string(lf, Vector2(28, y + lf.get_ascent(30)), str(_layout.get("caller", header)), HORIZONTAL_ALIGNMENT_LEFT, inner, 30, PHONE_TEXT)
	y += 36.0
	draw_line(Vector2(28, y + 4), Vector2(r.size.x - 28, y + 4), Color(1, 1, 1, 0.12), 1.0)
	y += 14.0
	y += _text(tf, Vector2(28, y), "\"%s\"" % text, inner, 21, PHONE_TEXT) + 18.0
	# the waveform, from the text's hash
	var h := absi(text.hash())
	var bars := 46
	var bw := inner / float(bars)
	for i in bars:
		h = (h * 1103515245 + 12345) & 0x7fffffff
		var amp := 6.0 + float(h % 26) * (0.55 + 0.45 * sin(float(i) * 0.35))
		draw_rect(Rect2(28 + bw * float(i), y + 20 - amp * 0.5, bw * 0.6, amp), Color(0.45, 0.85, 0.75, 0.85))
	y += 40.0
	draw_string(FormTheme.label_font(false, true), Vector2(28, y + 18), "Transcribed automatically. Accuracy not guaranteed.", HORIZONTAL_ALIGNMENT_LEFT, inner, 16, Color(PHONE_TEXT, 0.45))


func _draw_memo(r: Rect2) -> void:
	_paper(r, FormTheme.carbon("white"))
	draw_rect(Rect2(0, 0, r.size.x, 10), accent)
	var lf := FormTheme.label_font(true)
	var inner := r.size.x - 56.0
	var y := 28.0
	var co := company if company != "" else "Interoffice"
	draw_string(lf, Vector2(28, y + lf.get_ascent(30)), co.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, inner, 30, accent.darkened(0.25))
	y += 34.0
	draw_string(FormTheme.label_font(false, true), Vector2(28, y + FormTheme.label_font().get_ascent(20)), header, HORIZONTAL_ALIGNMENT_LEFT, inner, 20, FormTheme.INK)
	y += 26.0
	draw_line(Vector2(28, y), Vector2(r.size.x - 28, y), Color(accent, 0.7), 2.0)
	y += 18.0
	_text(FormTheme.typed_font(false), Vector2(28, y), text, inner, 21, FormTheme.TYPED)


func _draw_complaint(r: Rect2) -> void:
	_paper(r, PINK)
	var lf := FormTheme.label_font(true)
	var inner := r.size.x - 56.0
	var y := 24.0
	draw_string(lf, Vector2(28, y + lf.get_ascent(28)), (header if header != "" else "Complaint").to_upper(), HORIZONTAL_ALIGNMENT_LEFT, inner - 90.0, 28, FormTheme.INK)
	draw_string(FormTheme.label_font(), Vector2(r.size.x - 108.0, y + lf.get_ascent(28)), "PINK COPY", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(FormTheme.INK, 0.7))
	y += 34.0
	draw_line(Vector2(28, y), Vector2(r.size.x - 28, y), FormTheme.INK, 2.0)
	y += 16.0
	# the tick boxes
	var bf := FormTheme.label_font()
	var x := 28.0
	for i in 2:
		var label := "URGENT" if i == 0 else "NOT URGENT"
		var box := Rect2(Vector2(x, y + 2), Vector2(22, 22))
		draw_rect(box, FormTheme.INK, false, 2.0)
		if i == 0:
			FormTheme.draw_tick(self, box)
		draw_string(bf, Vector2(x + 32, y + bf.get_ascent(20)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, FormTheme.INK)
		x += 32.0 + bf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 34.0
	y += 34.0
	draw_string(bf, Vector2(28, y + bf.get_ascent(18)), "DETAILS OF COMPLAINT", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(FormTheme.INK, 0.8))
	y += 26.0
	var hf := FormTheme.hand_font()
	var body := str(_layout.get("body", text))
	var bh := _text_h(hf, body, inner, 30)
	var line_h := hf.get_height(30)
	var ly := y + line_h - 2.0
	while ly < y + bh + 2.0:
		draw_line(Vector2(28, ly), Vector2(r.size.x - 28, ly), FormTheme.FAINT, 1.0)
		ly += line_h
	_text(hf, Vector2(30, y), body, inner, 30, FormTheme.BLUE_PEN)
	var sig := str(_layout.get("sig", ""))
	if sig != "":
		_text(hf, Vector2(28, y + bh + 6.0), sig, inner, 30, FormTheme.BLUE_PEN, HORIZONTAL_ALIGNMENT_RIGHT)
