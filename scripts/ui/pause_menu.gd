class_name PauseMenu
extends Control
## The in-contract pause overlay (Esc): Resume, Abandon contract (back to the job board) or Main menu, as
## FORM 27-B on a clipboard (scripts/ui/forms/). The game pauses the scene tree while it is open; this overlay
## runs while paused (process mode ALWAYS). Add it under a CanvasLayer. Esc (or Resume) voids the form and then
## resumes: back is VOID (form-rules.md §6, FormVoid; void_back()). Emits resume / abandon / main_menu; the game does the work.
##
## `online` (set before adding it): another player is in the crew, so NOTHING pauses (networking-build-plan.md M5): the
## form says the job runs on, Abandon takes the whole crew back to the board, and Main menu ends the job for everyone
## (`hosting`) or leaves the crew (a client).
##
## `can_invite` (M7, a Steam crew with a free seat): one more row, "Invite crew", which opens the Steam overlay's invite
## dialog (`invite`). Solo and offline the form is exactly as before.

signal resume
signal abandon
signal main_menu
signal invite

## Keys are ignored briefly after opening (the Esc that opened it must not close it again).
const INPUT_GUARD_MS := 150

var resume_button: Button
var abandon_button: Button
var menu_button: Button
var invite_button: Button = null
## A crew is on the job: the tree is NOT paused (see above). Set before the overlay enters the tree.
var online := false
## This machine hosts the crew (Main menu ends the job for everyone). Read only when `online`.
var hosting := true
## The Steam overlay can invite a friend into this crew (a seat is free): show the "Invite crew" row. Set before adding it.
var can_invite := false

var sheet: FormSheet

var _born_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Sfx.play("paper")   # the form slides in
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
	var tall := 660.0 + (76.0 if can_invite else 0.0)
	holder.custom_minimum_size = Vector2(640.0, tall)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(holder)
	var board := FormClipboard.new(640.0, tall, 1.0)
	holder.add_child(board)
	sheet = FormSheet.new("27-B", "On break" if online else "On hold", "CAST  ·  the job runs on" if online else "CAST  ·  shift paused",
		"Status", "ON THE CLOCK" if online else "STANDING BY", "white", 46)
	board.set_content(sheet)
	var body := sheet.body

	resume_button = _row(body, "Resume", "01", "esc")
	resume_button.pressed.connect(void_back)
	abandon_button = _row(body, "Abandon contract", "02", "whole crew" if online else "no invoice")
	abandon_button.pressed.connect(func() -> void: abandon.emit())
	menu_button = _row(body, "Main menu", "03", ("ends the job" if hosting else "leave the crew") if online else "")
	menu_button.pressed.connect(func() -> void: main_menu.emit())
	if can_invite:
		invite_button = _row(body, "Invite crew", "04", "steam overlay")
		invite_button.pressed.connect(func() -> void: invite.emit())

	var note_text := "The crew is standing by. Esc resumes. Abandoning drops this contract: back to the job board, no invoice."
	if online:
		note_text = "Nothing is paused: the job runs on and only you stand still. Abandoning sends the whole crew to the board."
	var note := FormTheme.typed_wrapped(note_text, 19)
	body.add_child(FormTheme.margin(note, 22, 14, 22, 8))
	body.add_child(FormTheme.spacer())
	var build := HBoxContainer.new()
	build.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build.add_theme_constant_override("separation", 10)
	build.add_child(FormTheme.label("BUILD", 16, FormTheme.INK, true))
	build.add_child(FormTheme.typed(BuildVersion.text(), 16))
	body.add_child(FormTheme.margin(build, 22, 6, 22, 14))

	var stamp := FormStamp.new("LIVE" if online else "ON HOLD", 34, -9.0)
	stamp.position = Vector2(350.0, 430.0 + (120.0 if can_invite else 0.0))
	board.add_child(stamp)

	var rows: Array = [resume_button, abandon_button, menu_button]
	if invite_button != null:
		rows.append(invite_button)
	FormTheme.chain(rows)
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
		void_back()
		get_viewport().set_input_as_handled()


## Back is VOID: stamp the form, then emit `resume` (back to the game). False while it is already being voided.
func void_back() -> bool:
	return FormVoid.void_and(self, resume.emit, sheet)


func _focus() -> void:
	if is_instance_valid(resume_button) and resume_button.is_inside_tree():
		resume_button.grab_focus()
