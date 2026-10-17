class_name PauseMenu
extends Control
## The in-contract pause overlay (Esc): Resume, Abandon contract (back to the job board) or Main menu.
## The game pauses the scene tree while it is open; this overlay runs while paused (process mode ALWAYS).
## Add it under a CanvasLayer. Esc resumes. Emits resume / abandon / main_menu; the game does the work.

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
	add_child(MenuStyle.dim_rect(0.72))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := MenuStyle.panel(MenuStyle.AMBER, 34, 26)
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var title := MenuStyle.label("PAUSED", 36, MenuStyle.AMBER_HOT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := MenuStyle.label("The crew is standing by.", 16, MenuStyle.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(MenuStyle.gap(6))

	resume_button = MenuStyle.button("Resume")
	resume_button.pressed.connect(func() -> void: resume.emit())
	v.add_child(resume_button)
	abandon_button = MenuStyle.button("Abandon contract")
	abandon_button.pressed.connect(func() -> void: abandon.emit())
	v.add_child(abandon_button)
	menu_button = MenuStyle.button("Main menu")
	menu_button.pressed.connect(func() -> void: main_menu.emit())
	v.add_child(menu_button)
	var hint := MenuStyle.label("Esc resumes.  Abandoning drops this contract: back to the job board, no invoice.", 14, MenuStyle.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(450, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or Time.get_ticks_msec() - _born_ms < INPUT_GUARD_MS:
		return
	if event.keycode == KEY_ESCAPE:
		resume.emit()
		get_viewport().set_input_as_handled()


func _focus() -> void:
	if is_instance_valid(resume_button) and resume_button.is_inside_tree():
		resume_button.grab_focus()
