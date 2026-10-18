class_name CrewConfirm
extends Control
## "This ends the job for the whole crew": the question a crew's HOST answers before leaving the job board or the
## floor, because the host leaving ends the session for everyone (no host migration, networking-build-plan.md §5).
## A small FORM 27-B on a clipboard like the pause menu: "End the job" (leave) and "Stay" (the default and Esc).
## Emits confirmed / declined; the game does the work. Add it under a CanvasLayer. Stay and Esc void the form first
## (form-rules.md §6, FormVoid; void_back()).

signal confirmed
signal declined

## Keys are ignored briefly after opening (the Esc that opened it must not close it again).
const INPUT_GUARD_MS := 150

var leave_button: Button
var stay_button: Button
var sheet: FormSheet

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
	holder.custom_minimum_size = Vector2(640.0, 520.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(holder)
	var board := FormClipboard.new(640.0, 520.0, 1.0)
	holder.add_child(board)
	sheet = FormSheet.new("27-B", "Leave the job?", "CAST  ·  crew on a job", "Crew", "ON THE CLOCK", "white", 46)
	board.set_content(sheet)
	var body := sheet.body
	var note := FormTheme.typed_wrapped("You are the host. If you leave, the job ends for everyone and the whole crew goes back to the menu.", 21)
	body.add_child(FormTheme.margin(note, 22, 14, 22, 10))
	body.add_child(FormTheme.rule(2.0))
	stay_button = _row(body, "Stay", "01", "esc")
	stay_button.pressed.connect(void_back)
	leave_button = _row(body, "End the job", "02", "everyone leaves")
	leave_button.pressed.connect(func() -> void: confirmed.emit())
	body.add_child(FormTheme.spacer())
	FormTheme.chain([stay_button, leave_button])
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


## Back is VOID: stamp the form, then emit `declined` (stay). False while it is already being voided.
func void_back() -> bool:
	return FormVoid.void_and(self, declined.emit, sheet)


func _focus() -> void:
	if is_instance_valid(stay_button) and stay_button.is_inside_tree():
		stay_button.grab_focus()
