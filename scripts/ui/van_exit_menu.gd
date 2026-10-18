class_name VanExitMenu
extends Control
## The exit slip that opens when the player presses E at the work van (floor 1 only; the van parks there and nowhere else):
##   [1] Clock out: drive off and invoice the client
##   [Esc] Cancel (Esc or the row voids the slip first: form-rules.md §6, FormVoid; void_back())
## Followers near the van ride out with the crew (extracted, $100 each). Clocking out is always allowed, finished or not:
## objectives not met do not pay. Drawn as a canary carbon-copy slip like the elevator's (scripts/ui/forms/). Add under a
## Control (Hud.add_overlay or the game's screen layer). The game pauses the simulation while it is open.

signal clock_out
signal cancel

## {floor: int, floor_count: int, payout: int, damages: int, followers: int, lines: Array[String]}
var info: Dictionary = {}

## Keys are ignored briefly after the slip opens (the E that opened it, or a key held on the walk here, cannot pick a row).
const INPUT_GUARD_MS := 500

var _rows: Array[Control] = []
var _born_ms := 0
var _sheet: FormSheet


func _init(new_info: Dictionary = {}) -> void:
	info = new_info


func _ready() -> void:
	_born_ms = Time.get_ticks_msec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = FormTheme.theme()
	add_child(FormTheme.dim_rect(0.7))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var floor_n := int(info.get("floor", 1))
	var floors := int(info.get("floor_count", 3))
	var sheet := FormSheet.new("E-2", "Clock out", "Work van  ·  floor %d of %d" % [floor_n, floors], "Floor", "%d / %d" % [floor_n, floors], "canary", 36)
	sheet.custom_minimum_size = Vector2(820, 0)
	center.add_child(sheet)
	_sheet = sheet
	var body := sheet.body

	var facts := FormSection.new("Report")
	body.add_child(facts)
	facts.box.add_child(FormField.new("Payout so far", FormTheme.typed(ContractRun.money(int(info.get("payout", 0))), 30, FormTheme.GREEN_INK), 330.0, 52.0))
	if int(info.get("damages", 0)) > 0:
		facts.box.add_child(FormField.new("Property damage so far", FormTheme.typed("-" + ContractRun.money(int(info["damages"])), 24, FormTheme.RED), 330.0, 46.0))
	for line: String in info.get("lines", []):
		var ll := FormTheme.typed_wrapped(line, 20)
		ll.custom_minimum_size = Vector2(700, 0)
		facts.box.add_child(ll)
	var followers := int(info.get("followers", 0))
	if followers > 0:
		var fl := FormTheme.typed_wrapped("%d employee%s riding along: +$%d each on the way out." % [followers, "s" if followers != 1 else "", ContractRun.EMPLOYEE_EXTRACTED], 20, FormTheme.GREEN_INK, true)
		fl.custom_minimum_size = Vector2(700, 0)
		facts.box.add_child(fl)

	_rows.clear()
	var out := FormRow.new("Clock out", "1", "")
	out.sub = "drive off and invoice the client"
	out.pressed.connect(func() -> void: clock_out.emit())
	body.add_child(out)
	_rows.append(out)
	var back := FormRow.new("Cancel", "Esc", "")
	back.pressed.connect(void_back)
	body.add_child(back)
	_rows.append(back)
	body.add_child(FormTheme.gap(10))
	FormTheme.chain(_rows)
	# Take focus once the keys-held guard has passed, so a key still down from the walk here cannot press a row.
	get_tree().create_timer(INPUT_GUARD_MS / 1000.0, true).timeout.connect(_grab_first)


func _grab_first() -> void:
	if is_inside_tree() and not _rows.is_empty() and get_viewport().gui_get_focus_owner() == null:
		(_rows[0] as Control).grab_focus()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or Time.get_ticks_msec() - _born_ms < INPUT_GUARD_MS:
		return
	match event.keycode:
		KEY_1, KEY_KP_1:
			clock_out.emit()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			void_back()
			get_viewport().set_input_as_handled()


## Back is VOID: stamp the slip, then emit `cancel`. False while it is already being voided.
func void_back() -> bool:
	return FormVoid.void_and(self, cancel.emit, _sheet)
