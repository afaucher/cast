class_name ClockInSlip
extends Control
## "Clocking in...": what a player who joined a crew on the job sees while their machine catches up (networking-build-plan.md
## M6). A white FORM 12-C on a clipboard like the pause menu: the crew, the job, the floor and the seat they are taking,
## typed in as they become known, the license they signed (set_license(): a joiner signs its own license checkout while it
## waits, and the form takes it back afterwards with the spells typed in and its status LICENSED), and one short line about
## what is happening ("Building floor 2..."). The only row is "Leave the crew" (Esc): either voids the form first, then
## emits `leave` (form-rules.md §6, FormVoid; void_back()). The game fills it with set_values() and removes it when the
## floor starts. Add it under a CanvasLayer. Hidden (the joiner's license checkout is up over it), it ignores the keys.

signal leave

const INPUT_GUARD_MS := 150

var leave_button: Button
var crew_value: Label
var job_value: Label
var floor_value: Label
var seat_value: Label
var license_value: Label
var sheet: FormSheet
var step_label: Label
var stamp: FormStamp

var _born_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_born_ms = Time.get_ticks_msec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = FormTheme.theme()
	add_child(FormTheme.dim_rect(0.82))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(660.0, 652.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(holder)
	var board := FormClipboard.new(660.0, 652.0, -0.8)
	holder.add_child(board)
	sheet = FormSheet.new("12-C", "Clocking in...", "CAST  ·  joining a crew on the job", "Status", "EN ROUTE", "white", 44)
	board.set_content(sheet)
	var body := sheet.body
	crew_value = _field(body, "Crew")
	job_value = _field(body, "Job")
	floor_value = _field(body, "Floor")
	seat_value = _field(body, "Seat")
	license_value = _field(body, "License")
	body.add_child(FormTheme.rule(2.0))
	step_label = FormTheme.typed_wrapped("Calling the crew...", 21)
	step_label.custom_minimum_size = Vector2(560.0, 0.0)
	body.add_child(FormTheme.margin(step_label, 22, 12, 22, 10))
	body.add_child(FormTheme.spacer())
	var row := FormRow.new("Leave the crew", "01", "esc")
	row.row_h = 70.0
	body.add_child(row)
	leave_button = row
	leave_button.pressed.connect(void_back)
	stamp = FormStamp.new("CLOCKING IN", 30, -7.0)
	stamp.position = Vector2(330.0, 462.0)
	board.add_child(stamp)
	_focus.call_deferred()


func _field(parent: Control, label_text: String) -> Label:
	var value := FormTheme.typed("-", 22)
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	value.custom_minimum_size = Vector2(10.0, 0.0)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := FormField.new(label_text, value, 130.0, 52.0)
	parent.add_child(FormTheme.margin(row, 0, 0, 26, 0))
	return value


## Fill the form in. Empty strings keep a dash (not known yet).
func set_values(crew: String, job: String, floor_text: String, seat: String, step: String) -> void:
	crew_value.text = crew if crew != "" else "-"
	job_value.text = job if job != "" else "-"
	floor_value.text = floor_text if floor_text != "" else "-"
	seat_value.text = seat if seat != "" else "-"
	step_label.text = step


## The license this joiner signed ("" = not yet: a dash, status EN ROUTE); signed, the status reads LICENSED.
func set_license(spells: String) -> void:
	license_value.text = spells if spells != "" else "-"
	sheet.header.copy_value.text = "LICENSED" if spells != "" else "EN ROUTE"


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or Time.get_ticks_msec() - _born_ms < INPUT_GUARD_MS:
		return
	if not is_visible_in_tree():
		return   # the joiner's license checkout is over it: Esc voids that form (through the game)
	if event.keycode == KEY_ESCAPE:
		void_back()
		get_viewport().set_input_as_handled()


## Back is VOID: stamp the form, then emit `leave` (leave the crew). False while it is already being voided.
func void_back() -> bool:
	return FormVoid.void_and(self, leave.emit, sheet)


func _focus() -> void:
	if is_instance_valid(leave_button) and leave_button.is_inside_tree():
		leave_button.grab_focus()
