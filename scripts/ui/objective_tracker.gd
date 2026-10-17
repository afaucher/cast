class_name ObjectiveTracker
extends Control
## The HUD's objective list (top-right of the play area, left of the voice debug panel because the HUD
## root shrinks for it): the floor, each objective with a check box, the running payout and damages.
## Pure presentation: the game feeds it with show_state(); it never reads simulation data itself.
##
## rows: [{text: String, detail: String, state: "todo"|"partial"|"done"|"fail"}]

const WIDTH := 340.0
const PAD := 12.0
const ROW_H := 24.0
const TITLE_H := 44.0
const FOOT_H := 52.0

const C_BG := Color(0.04, 0.05, 0.09, 0.8)
const C_EDGE := Color(1, 1, 1, 0.22)
const C_TEXT := Color(0.93, 0.94, 0.98)
const C_DIM := Color(0.62, 0.65, 0.76)
const C_DONE := Color(0.5, 0.95, 0.6)
const C_PARTIAL := Color(1.0, 0.82, 0.35)
const C_MONEY := Color(0.55, 0.92, 0.62)
const C_BAD := Color(1.0, 0.45, 0.4)

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
	var font := ThemeDB.fallback_font
	var full := Rect2(Vector2.ZERO, size)
	draw_rect(full, C_BG)
	draw_rect(full, C_EDGE, false, 1.5)
	draw_string(font, Vector2(PAD, 24), title, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 2 * PAD, 18, C_TEXT)
	draw_string(font, Vector2(PAD, 41), subtitle, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 2 * PAD, 13, C_DIM)
	var y := TITLE_H
	for r in rows:
		var st: String = str(r["state"])
		var col := C_DONE if st == "done" else (C_PARTIAL if st == "partial" else (C_BAD if st == "fail" else C_TEXT))
		var box := Rect2(PAD, y + 5, 14, 14)
		draw_rect(box, Color(0, 0, 0, 0.5))
		draw_rect(box, col, false, 1.5)
		if st == "done":
			draw_polyline(PackedVector2Array([box.position + Vector2(3, 7), box.position + Vector2(6, 11), box.position + Vector2(12, 3)]), col, 2.2)
		elif st == "partial":
			draw_rect(box.grow(-4), col)
		draw_string(font, Vector2(PAD + 22, y + 18), str(r["text"]), HORIZONTAL_ALIGNMENT_LEFT, 190, 15, col)
		var detail := str(r["detail"])
		var dw := font.get_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2(WIDTH - PAD - dw, y + 18), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_DIM)
		y += ROW_H
	y += 6
	draw_line(Vector2(PAD, y), Vector2(WIDTH - PAD, y), C_EDGE, 1.0)
	draw_string(font, Vector2(PAD, y + 22), "PAYOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_DIM)
	var pay_text := ContractRun.money(payout)
	var pw := font.get_string_size(pay_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	draw_string(font, Vector2(WIDTH - PAD - pw, y + 26), pay_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, C_MONEY)
	if damages > 0:
		var dt := "property damage -%s" % ContractRun.money(damages)
		draw_string(font, Vector2(PAD, y + 44), dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_BAD)
