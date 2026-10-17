class_name ElevatorMenu
extends Control
## The freight elevator prompt that opens when the crew steps on the exit cell:
##   [1] Go down to floor N (more pay, more danger)     (not offered on the last floor)
##   [2] Exit: clock out and invoice the client        (the only way out on the last floor, where it is [1])
##   [Esc] Stay on this floor
## Followers near the elevator ride along (extracted, $100 each). Exiting is always available. (Floor 1's van is the
## other exit, see VanExitMenu.)
## Drawn as a canary "while you were out" slip (scripts/ui/forms/). Add under a Control (Hud.add_overlay).
## The game pauses the simulation while it is open.

signal go_down
signal cash_out
signal stay

## {floor: int, floor_count: int, payout: int, damages: int, followers: int, lines: Array[String]}
var info: Dictionary = {}

## Keys are ignored briefly after the menu opens (a slot key held while stepping on cannot pick an option).
const INPUT_GUARD_MS := 500

var _can_descend := false
var _rows: Array[Control] = []
var _born_ms := 0


func _init(new_info: Dictionary = {}) -> void:
	info = new_info


func _ready() -> void:
	_born_ms = Time.get_ticks_msec()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = FormTheme.theme()
	_can_descend = int(info.get("floor", 1)) < int(info.get("floor_count", 3))
	add_child(FormTheme.dim_rect(0.7))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# A short canary "while you were out" slip (scripts/ui/forms/).
	var floor_n := int(info.get("floor", 1))
	var floors := int(info.get("floor_count", 3))
	var sheet := FormSheet.new("E-1", "While you were out", "Freight elevator  ·  floor %d of %d" % [floor_n, floors], "Floor", "%d / %d" % [floor_n, floors], "canary", 36)
	sheet.custom_minimum_size = Vector2(820, 0)
	center.add_child(sheet)
	var body := sheet.body

	var facts := FormSection.new("Report")
	body.add_child(facts)
	var pay := FormField.new("Payout so far", FormTheme.typed(ContractRun.money(int(info.get("payout", 0))), 30, FormTheme.GREEN_INK), 330.0, 52.0)
	facts.box.add_child(pay)
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
	if _can_descend:
		var down := FormRow.new("Go down to floor %d" % (floor_n + 1), "1", "more pay, more danger")
		down.pressed.connect(func() -> void: go_down.emit())
		body.add_child(down)
		_rows.append(down)
	var out := FormRow.new("Exit", "2" if _can_descend else "1", "always works")
	out.sub = "clock out and invoice the client"
	out.pressed.connect(func() -> void: cash_out.emit())
	body.add_child(out)
	_rows.append(out)
	var stay_b := FormRow.new("Stay on this floor", "Esc", "")
	stay_b.pressed.connect(func() -> void: stay.emit())
	body.add_child(stay_b)
	_rows.append(stay_b)
	if not _can_descend:
		body.add_child(FormTheme.margin(FormTheme.small("Last floor: there is nowhere further down to go.", 18), 22, 8, 22, 4))
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
			if _can_descend:
				go_down.emit()
			else:
				cash_out.emit()      # on the last floor the exit is row 1
			get_viewport().set_input_as_handled()
		KEY_2, KEY_KP_2:
			if _can_descend:
				cash_out.emit()
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			stay.emit()
			get_viewport().set_input_as_handled()


func can_descend() -> bool:
	return int(info.get("floor", 1)) < int(info.get("floor_count", 3))
