class_name ObjectiveTracker
extends Control
## The HUD's objective list, drawn as a small canary work-order slip (top-right of the play area, left of the
## voice debug panel because the HUD root shrinks for it): a small "WORK ORDER" label, the client / company name on
## its own lines (wrapped to NAME_LINES, ellipsis after that), "FLOOR n / 3", then each objective with a check box,
## the running payout and damages. The header is stacked, never side by side, so nothing can overlap. Kept small and opaque enough to read mid-fight.
## Pure presentation: the game feeds it with show_state(); it never reads simulation data itself.
##
## rows: [{text: String, detail: String, state: "todo"|"partial"|"done"|"fail"}]

const WIDTH := 360.0
const PAD := 14.0
const ROW_H := 31.0
const FOOT_H := 62.0
const LABEL_SIZE := 16          ## "WORK ORDER"
const NAME_SIZE := 20           ## the client / company name
const NAME_LINES := 2           ## at most this many lines, then an ellipsis
const NAME_LEAD := 24.0
const FLOOR_SIZE := 28

const INK := FormTheme.INK
const TYPED := FormTheme.TYPED
const C_DONE := Color(0.1, 0.42, 0.22)
const C_PARTIAL := Color(0.62, 0.4, 0.02)
const C_BAD := FormTheme.RED
const C_MONEY := FormTheme.GREEN_INK

var title := ""        ## the floor line: "FLOOR 2 / 3"
var subtitle := ""     ## the client or company name
var rows: Array[Dictionary] = []
var payout := 0
var damages := 0

var _name_lines := PackedStringArray()
var _header_h := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name = "ObjectiveTracker"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_layout_header()
	_resize()


## Replace everything shown. Redraws only when something changed.
func show_state(new_title: String, new_subtitle: String, new_rows: Array[Dictionary], new_payout: int, new_damages: int) -> void:
	if new_title == title and new_subtitle == subtitle and new_rows == rows and new_payout == payout and new_damages == damages:
		return
	title = new_title
	subtitle = new_subtitle
	rows = new_rows.duplicate(true)
	payout = new_payout
	damages = new_damages
	_layout_header()
	_resize()
	queue_redraw()


## The name wrapped to NAME_LINES and the header's height, from the current subtitle.
func _layout_header() -> void:
	_name_lines = wrap_name(subtitle, FormTheme.typed_font(), NAME_SIZE, WIDTH - 2.0 * PAD, NAME_LINES)
	_header_h = floor_baseline() + 14.0


## The text lines of the name, as drawn (wrapped, ellipsised).
func name_lines() -> PackedStringArray:
	return _name_lines


## The header's height: "WORK ORDER", the name lines, the floor line.
func header_height() -> float:
	return _header_h


func _name_top() -> float:
	return 26.0


## Baseline y of name line `i` (0-based).
func _name_baseline(i: int) -> float:
	return _name_top() + NAME_SIZE * 0.85 + NAME_LEAD * i


## Baseline y of the "FLOOR n / 3" line.
func floor_baseline() -> float:
	var lines := maxi(_name_lines.size(), 0)
	var last := _name_baseline(lines - 1) if lines > 0 else 20.0
	return last + 6.0 + FLOOR_SIZE * 0.9


## Greedy word wrap of `text` into at most `max_lines` lines no wider than `width`. A word longer than a line is
## broken; whatever does not fit in the last line is cut with an ellipsis. Empty text gives no lines.
static func wrap_name(text: String, font: Font, size: int, width: float, max_lines: int) -> PackedStringArray:
	var out := PackedStringArray()
	if text.strip_edges() == "":
		return out
	var cur := ""
	var overflow := false
	for word in text.split(" ", false):
		var w: String = word
		while font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:   # break an over-long word
			var n := w.length() - 1
			while n > 1 and font.get_string_size(w.substr(0, n), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
				n -= 1
			if cur != "":
				out.append(cur)
				cur = ""
			out.append(w.substr(0, n))
			w = w.substr(n)
		var trial := w if cur == "" else cur + " " + w
		if cur != "" and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			out.append(cur)
			cur = w
		else:
			cur = trial
	if cur != "":
		out.append(cur)
	if out.size() > max_lines:
		overflow = true
		var kept := out.slice(0, max_lines)
		var rest := " ".join(out.slice(max_lines - 1))
		kept[max_lines - 1] = rest
		out = kept
	if overflow or (out.size() == max_lines and font.get_string_size(out[out.size() - 1], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width):
		var last := out[out.size() - 1]
		while last.length() > 1 and font.get_string_size(last + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			last = last.substr(0, last.length() - 1)
		out[out.size() - 1] = last.strip_edges() + "…"
	return out


func _resize() -> void:
	var h := _header_h + ROW_H * rows.size() + FOOT_H + PAD
	custom_minimum_size = Vector2(WIDTH, h)
	offset_left = -WIDTH - 16.0
	offset_right = -16.0
	offset_top = 16.0
	offset_bottom = 16.0 + h


func _draw() -> void:
	var lf := FormTheme.label_font(true)
	var tf := FormTheme.typed_font()
	var full := Rect2(Vector2.ZERO, size)
	for i in 5:
		var g := float(i) * 2.5
		draw_rect(Rect2(Vector2(2, 6) - Vector2(g, g) * 0.8, size + Vector2(g, g) * 1.6), Color(0, 0, 0, 0.07 * (1.0 - i / 5.0)))
	draw_texture_rect(FormTheme.paper_texture(), full, true, Color(FormTheme.carbon("canary"), 0.96))
	draw_rect(full, Color(0.3, 0.25, 0.1, 0.4), false, 1.0)
	draw_string(lf, Vector2(PAD, 19), "WORK ORDER", HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, Color(INK, 0.8))
	for i in _name_lines.size():
		draw_string(tf, Vector2(PAD, _name_baseline(i)), _name_lines[i], HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 2.0 * PAD, NAME_SIZE, TYPED)
	draw_string(lf, Vector2(PAD, floor_baseline()), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 2.0 * PAD, FLOOR_SIZE, INK)
	draw_line(Vector2(0, _header_h - 4.0), Vector2(WIDTH, _header_h - 4.0), INK, 2.5)
	var y := _header_h
	for r in rows:
		var st: String = str(r["state"])
		var col := C_DONE if st == "done" else (C_PARTIAL if st == "partial" else (C_BAD if st == "fail" else TYPED))
		var box := Rect2(PAD, y + 6, 18, 18)
		draw_rect(box, Color(1, 1, 1, 0.45))
		draw_rect(box, INK, false, 2.0)
		if st == "done":
			FormTheme.draw_tick(self, box, FormTheme.GREASE, 3.0)
		elif st == "partial":
			draw_rect(box.grow(-4), Color(FormTheme.GREASE, 0.8))
		elif st == "fail":
			FormTheme.draw_x(self, box, FormTheme.GREASE, 2.5)
		draw_string(tf, Vector2(PAD + 30, y + 22), str(r["text"]), HORIZONTAL_ALIGNMENT_LEFT, 215, 18, col)
		var detail := str(r["detail"])
		var dw := lf.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(lf, Vector2(WIDTH - PAD - dw, y + 22), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
		draw_line(Vector2(PAD, y + ROW_H - 1), Vector2(WIDTH - PAD, y + ROW_H - 1), FormTheme.FAINT, 1.0)
		y += ROW_H
	y += 6
	draw_line(Vector2(0, y), Vector2(WIDTH, y), INK, 2.5)
	draw_string(lf, Vector2(PAD, y + 27), "PAYOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, INK)
	var pay_text := ContractRun.money(payout)
	var pw := tf.get_string_size(pay_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	draw_string(tf, Vector2(WIDTH - PAD - pw, y + 30), pay_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, C_MONEY if payout >= 0 else C_BAD)   # money() prints a minus sign when negative
	if damages > 0:
		draw_string(tf, Vector2(PAD, y + 52), "property damage -%s" % ContractRun.money(damages), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, C_BAD)
