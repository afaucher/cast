class_name SignLine
extends Control
## The ruled line a player signs on (form-rules.md rule 9): `signature` is stamped on it with the red rubber name stamp
## (style "stamp": the name in caps, a double border, a slight tilt), or written in the red grease pencil (style "pen").
## Shared by every form that is signed: the job board's Take line (JobBoard) and the requisition's "Requested by" line
## (SignRow, SpellPicker). Draws only; the form decides when to sign.

const STAMP_SIZE := 22
const STAMP_ANGLE_DEG := -3.0

var signature := "":
	set(v):
		if v != "" and v != signature and style == "stamp" and is_inside_tree():
			Sfx.play("stamp")   # the name stamp lands (not when a form is built already signed)
		signature = v
		queue_redraw()
var style := "pen":
	set(v):
		style = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_line(Vector2(0, size.y - 3.0), Vector2(size.x, size.y - 3.0), FormTheme.INK, 2.0)
	if signature == "":
		return
	if style == "stamp":
		draw_stamp(self, signature, Vector2(0.0, size.y - 14.0))
		return
	# A hand signature runs a little uphill.
	var f := FormTheme.hand_font()
	draw_set_transform(Vector2(12.0, size.y - 7.0), deg_to_rad(-4.0))
	draw_string(f, Vector2.ZERO, signature, HORIZONTAL_ALIGNMENT_LEFT, size.x - 12.0, 34, FormTheme.GREASE)
	draw_set_transform(Vector2.ZERO)


## The red rubber name stamp, double-bordered and a touch crooked, its left edge near `left_mid.x` (+18) and centred on
## `left_mid.y`. Returns the stamp's (untilted) rect in `ci`'s space.
static func draw_stamp(ci: CanvasItem, name_text: String, left_mid: Vector2) -> Rect2:
	var f := FormTheme.stamp_font()
	var fs := STAMP_SIZE
	var text := name_text.to_upper()
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2(Vector2(-tw * 0.5 - 14.0, -f.get_height(fs) * 0.5 - 6.0), Vector2(tw + 28.0, f.get_height(fs) + 12.0))
	var ink := Color(FormTheme.RED, 0.85)
	var centre := Vector2(left_mid.x + box.size.x * 0.5 + 18.0, left_mid.y)
	ci.draw_set_transform(centre, deg_to_rad(STAMP_ANGLE_DEG))
	ci.draw_rect(box, ink, false, 3.0)
	ci.draw_rect(box.grow(-5.0), ink, false, 1.5)
	ci.draw_string(f, Vector2(-tw * 0.5, f.get_ascent(fs) - f.get_height(fs) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	ci.draw_set_transform(Vector2.ZERO)
	return Rect2(box.position + centre, box.size)
