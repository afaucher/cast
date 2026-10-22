class_name MoveFeelTag
extends CanvasLayer
## The movement-feel A/B on screen (docs/design/movement-research.md "As built"): F6 switches the profile (MoveFeel.cycle),
## F7 physics interpolation, and a small dev tag in the corner names the profile for SHOW_FOR seconds after a switch (and
## at the start). Blind (shuffle) it says only "feel 1" / "feel 2". It is the arena's and the floor's dev tag, not a form
## (form-rules.md does not apply). It also carries the passive MoveLog for the local player.

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
	t.show_tag(MoveFeel.label() if MoveFeel.active() != MoveFeel.TODAY or MoveFeel.blind() else "")
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


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_F6:
		get_viewport().set_input_as_handled()
		if MoveFeel.cycle():
			move_log.switched()
			show_tag(MoveFeel.label())
		else:
			show_tag("feel: set by the host")
	elif k.physical_keycode == KEY_F7:
		get_viewport().set_input_as_handled()
		MoveFeel.toggle_interp()
		move_log.switched()
		show_tag("interp %s" % ("on" if MoveFeel.interp else "off"))
