class_name MoveFeelTag
extends CanvasLayer
## The movement profile's dev tag (docs/design/movement-research.md "As built"): a small tag in the corner names the
## profile for SHOW_FOR seconds at the start when a flag picked one other than the default (MoveFeel.DEFAULT), and shows
## what the test gym's experiments switch (GymDev). No keys: the A/B is concluded (movement-research.md §5.3). It is the
## arena's and the floor's dev tag, not a form (form-rules.md does not apply). It also carries the passive MoveLog for the
## local player.

const SHOW_FOR := 1.8
const FADE := 0.4

var label: Label
var move_log: MoveLog
var _shown := 0.0


## Put the tag (and the log) on `parent` for the local `player`; `lab` is MoveLab's lap gates, {} on a normal floor.
static func attach(parent: Node, player: Hero, lab: Dictionary = {}) -> MoveFeelTag:
	MoveFeel.boot()
	var t := MoveFeelTag.new()
	t.name = "MoveFeelTag"
	parent.add_child(t)
	t.move_log = MoveLog.new()
	t.move_log.name = "MoveLog"
	t.move_log.player = player
	t.move_log.lab = lab
	t.add_child(t.move_log)
	t.show_tag(MoveFeel.label() if MoveFeel.active() != MoveFeel.DEFAULT else "")
	return t


func _ready() -> void:
	layer = 45
	label = Label.new()
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	label.anchor_left = 0.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 14.0
	label.offset_top = -30.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate.a = 0.0
	add_child(label)


func _process(delta: float) -> void:
	if _shown > 0.0:
		_shown -= delta
		label.modulate.a = clampf(_shown / FADE, 0.0, 1.0) * 0.85


## Show `text` for SHOW_FOR seconds ("" shows nothing).
func show_tag(text: String) -> void:
	if label == null or text == "":
		return
	label.text = text
	_shown = SHOW_FOR

