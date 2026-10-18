class_name InviteConfirm
extends Control
## "Leave this job and join?": a Steam overlay invite was accepted while the game runs (M7, NetSession.invite_received).
## A small carbon copy (the canary dispatch part, FORM 27-C) on a clipboard like CrewConfirm: "Stay" (the default and Esc)
## and "Leave and join". It says whose crew is calling, and what leaving costs: the job in progress, and for a host with a
## crew the job of everyone in it. Emits confirmed / declined; the game does the work. Add it under a CanvasLayer. Stay and
## Esc void the form first (form-rules.md §6, FormVoid; void_back()).

signal confirmed
signal declined

## Keys are ignored briefly after opening (a key held while the overlay closed must not answer it).
const INPUT_GUARD_MS := 150

## Who invited ("" when Steam did not say). Set before it enters the tree.
var inviter := ""
## A contract is running (the question is about leaving the job, not just the board).
var on_job := true
## This machine hosts a crew: leaving ends the job for everyone.
var hosting_crew := false
## This machine is a member of someone else's crew: the AI takes its seat when it leaves.
var in_crew := false

var join_button: Button
var stay_button: Button
var note_label: Label
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
	holder.custom_minimum_size = Vector2(640.0, 480.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(holder)
	var board := FormClipboard.new(640.0, 480.0, 1.2)
	holder.add_child(board)
	var title := "Leave this job and join?" if on_job else "Join another crew?"
	sheet = FormSheet.new("27-C", title, "CAST  ·  crew transfer request", "Copy", "DISPATCH", "canary", 40)
	board.set_content(sheet)
	var body := sheet.body

	var from := HBoxContainer.new()
	from.mouse_filter = Control.MOUSE_FILTER_IGNORE
	from.add_theme_constant_override("separation", 12)
	from.add_child(FormTheme.label("FROM", 18, FormTheme.INK, true))
	var crew := FormTheme.typed("%s's crew" % inviter if inviter != "" else "A crew on Steam", 22)
	crew.name = "Inviter"
	from.add_child(crew)
	body.add_child(FormTheme.margin(from, 22, 12, 22, 4))
	note_label = FormTheme.typed_wrapped(note_text(), 20)
	note_label.name = "Note"
	body.add_child(FormTheme.margin(note_label, 22, 6, 22, 10))
	body.add_child(FormTheme.rule(2.0))
	stay_button = _row(body, "Stay", "01", "esc")
	stay_button.pressed.connect(void_back)
	join_button = _row(body, "Leave and join" if on_job or in_crew or hosting_crew else "Join their crew", "02", "everyone leaves" if hosting_crew else "")
	join_button.pressed.connect(func() -> void: confirmed.emit())
	body.add_child(FormTheme.spacer())
	FormTheme.chain([stay_button, join_button])

	var stamp := FormStamp.new("INVITE", 30, -7.0)
	stamp.position = Vector2(380.0, 385.0)
	board.add_child(stamp)
	_focus.call_deferred()


## What leaving costs, in one line.
func note_text() -> String:
	if hosting_crew:
		return "You are the host. Joining ends this job for the whole crew and sends them back to the menu."
	if in_crew and on_job:
		return "Joining drops this job for you: the AI takes your seat and your crew carries on."
	if on_job:
		return "Joining drops this job: no invoice for it."
	if in_crew:
		return "Joining leaves your crew for theirs."
	return "Joining leaves the job board for their crew."


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
