class_name PauseMenu
extends Control
## The in-contract pause overlay (Esc): Resume, Abandon contract (back to the job board) or Main menu, as
## FORM 27-B on a clipboard (scripts/ui/forms/). The game pauses the scene tree while it is open; this overlay
## runs while paused (process mode ALWAYS). Add it under a CanvasLayer. Esc resumes.
## Emits resume / abandon / main_menu; the game does the work.

signal resume
signal abandon
signal main_menu

## Keys are ignored briefly after opening (the Esc that opened it must not close it again).
const INPUT_GUARD_MS := 150

var resume_button: Button
var abandon_button: Button
var menu_button: Button

var _born_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_born_ms = Time.get_ticks_msec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = FormTheme.theme()
	add_child(FormTheme.dim_rect(0.6))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(640.0, 660.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(holder)
	var board := FormClipboard.new(640.0, 660.0, 1.0)
	holder.add_child(board)
	var sheet := FormSheet.new("27-B", "On hold", "CAST  ·  shift paused", "Status", "STANDING BY", "white", 46)
	board.set_content(sheet)
	var body := sheet.body

	resume_button = _row(body, "Resume", "01", "esc")
	resume_button.pressed.connect(func() -> void: resume.emit())
	abandon_button = _row(body, "Abandon contract", "02", "no invoice")
	abandon_button.pressed.connect(func() -> void: abandon.emit())
	menu_button = _row(body, "Main menu", "03", "")
	menu_button.pressed.connect(func() -> void: main_menu.emit())

	var note := FormTheme.typed_wrapped("The crew is standing by. Esc resumes. Abandoning drops this contract: back to the job board, no invoice.", 19)
	body.add_child(FormTheme.margin(note, 22, 14, 22, 8))
	body.add_child(FormTheme.spacer())
	var build := HBoxContainer.new()
	build.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build.add_theme_constant_override("separation", 10)
	build.add_child(FormTheme.label("BUILD", 16, FormTheme.INK, true))
	build.add_child(FormTheme.typed(BuildVersion.text(), 16))
	body.add_child(FormTheme.margin(build, 22, 6, 22, 14))

	var stamp := FormStamp.new("ON HOLD", 34, -9.0)
	stamp.position = Vector2(350.0, 430.0)
	board.add_child(stamp)

	FormTheme.chain([resume_button, abandon_button, menu_button])
	_focus.call_deferred()


func _row(parent: Control, text: String, number: String, hint: String) -> FormRow:
	var r := FormRow.new(text, number, hint)
	r.row_h = 76.0
	parent.add_child(r)
	return r


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or Time.get_ticks_msec() - _born_ms < INPUT_GUARD_MS:
		return
	if event.keycode == KEY_ESCAPE:
		resume.emit()
		get_viewport().set_input_as_handled()


func _focus() -> void:
	if is_instance_valid(resume_button) and resume_button.is_inside_tree():
		resume_button.grab_focus()
