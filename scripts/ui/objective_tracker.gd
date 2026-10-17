class_name ObjectiveTracker
extends Control
## The HUD's objective list, drawn as a small canary work-order slip (top-right of the play area, left of the
## voice debug panel because the HUD root shrinks for it): the floor, each objective with a check box, the
## running payout and damages. Kept small and opaque enough to read mid-fight.
## Pure presentation: the game feeds it with show_state(); it never reads simulation data itself.
##
## rows: [{text: String, detail: String, state: "todo"|"partial"|"done"|"fail"}]

const WIDTH := 360.0
const PAD := 14.0
const ROW_H := 31.0
const TITLE_H := 60.0
const FOOT_H := 62.0

const INK := FormTheme.INK
const TYPED := FormTheme.TYPED
const C_DONE := Color(0.1, 0.42, 0.22)
const C_PARTIAL := Color(0.62, 0.4, 0.02)
const C_BAD := FormTheme.RED
const C_MONEY := FormTheme.GREEN_INK

var title := ""
var subtitle := ""
var rows: Array[Dictionary] = []
var payout := 0
var damages := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name = "ObjectiveTracker"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
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
	_resize()
	queue_redraw()


func _resize() -> void:
	var h := TITLE_H + ROW_H * rows.size() + FOOT_H + PAD
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
	draw_string(lf, Vector2(PAD, 20), "WORK ORDER", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
	draw_string(lf, Vector2(PAD, 46), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 2 * PAD, 28, INK)
	var sw := lf.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(lf, Vector2(WIDTH - PAD - sw, 20), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	draw_line(Vector2(0, TITLE_H - 4), Vector2(WIDTH, TITLE_H - 4), INK, 2.5)
	var y := TITLE_H
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
	draw_string(tf, Vector2(WIDTH - PAD - pw, y + 30), pay_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, C_MONEY)
	if damages > 0:
		draw_string(tf, Vector2(PAD, y + 52), "property damage -%s" % ContractRun.money(damages), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, C_BAD)
