class_name FormVoid
extends Control
## Back is VOID (docs/design/form-rules.md §6, rule 27): Esc, or a form's own back row, voids the form you are on. A big
## red VOID rubber stamp slams onto the sheet, holds a moment, and only then does the screen's existing back action run.
## Every form screen calls this one helper, so the look and the timing are the same everywhere:
##
##   FormVoid.void_and(screen, action, over)
##     screen  the screen's root Control. The void is a full-rect child of it, on top: clicks and keys stop there until
##             the action (a voided form can't be acted on, and a second Esc or click does nothing). It dies with the
##             screen: if something else frees the screen first, the action never runs.
##     action  the screen's back, usually its back signal's emit (`cancelled.emit`, `stay.emit`).
##     over    where the stamp lands, centred: the screen's main sheet (a Control), or every part of a multi-part set (an
##             Array of Controls, one stamp on each: the job board's three carbon parts). Default: the screen.
##   Returns false, doing nothing, while that screen is already being voided (or when it is not in the tree).
##
## The stamp is a FormStamp (Black Ops One, red, double border, tilted, plain alpha), the same size on every form: it lands
## in SLAM_S (scale SLAM_FROM to 1, fading in), and the action runs HOLD_S after the press. When the screen outlives its
## action (the job board while a host's "Leave the job?" asks), the void lifts and the screen works again.
## The void only delays a local back action; nothing here knows about the network.

const WORD := "VOID"
const FONT_SIZE := 132
const ANGLE_DEG := -9.0
## The stamp lands: scale SLAM_FROM -> 1 over SLAM_S, fading in over the first half of it.
const SLAM_S := 0.1
const SLAM_FROM := 1.3
## From the press to the back action (the landing included).
const HOLD_S := 0.3

## Test / dev seam: the press-to-action time actually used. 0 = the action on the next frame; the screenshot flags set it
## very long to catch the stamp mid-hold. Process-wide; tests that change it put it back.
static var hold_s := HOLD_S

var action := Callable()
## The parts stamped (one stamp each, same order).
var parts: Array[Control] = []
var stamps: Array[FormStamp] = []
## The first (usually only) stamp.
var stamp: FormStamp = null
var _fired := false


## Void `screen` and run `back` once the stamp has held. See the class notes.
static func void_and(screen: Control, back: Callable, over: Variant = null) -> bool:
	if screen == null or not is_instance_valid(screen) or not screen.is_inside_tree() or voiding(screen):
		return false
	var v := FormVoid.new()
	v.name = "FormVoid"
	v.action = back
	var list: Array = over if over is Array else [over]
	for c: Variant in list:
		if c is Control and is_instance_valid(c):
			v.parts.append(c)
	if v.parts.is_empty():
		v.parts.append(screen)
	screen.add_child(v)
	return true


## A void is running on `screen` (its back action has not run yet).
static func voiding(screen: Node) -> bool:
	return of(screen) != null


## The void running on `screen`, or null.
static func of(screen: Node) -> FormVoid:
	if screen == null or not is_instance_valid(screen):
		return null
	for c in screen.get_children():
		if c is FormVoid and not c.is_queued_for_deletion() and not (c as FormVoid)._fired:
			return c
	return null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	for i in parts.size():
		var s := FormStamp.new(WORD, FONT_SIZE, ANGLE_DEG)
		s.name = "VoidStamp%d" % i if i > 0 else "VoidStamp"
		s.scale = Vector2.ONE * SLAM_FROM
		s.modulate.a = 0.0
		add_child(s)
		stamps.append(s)
	stamp = stamps[0] if not stamps.is_empty() else null
	_place()
	var slam := minf(SLAM_S, hold_s)
	var tw := create_tween()
	tw.set_parallel(true)
	for s in stamps:
		tw.tween_property(s, "scale", Vector2.ONE, slam).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(s, "modulate:a", 1.0, slam * 0.5)
	tw.chain().tween_interval(maxf(hold_s - slam, 0.0))
	tw.chain().tween_callback(_fire)


## Keep each stamp centred on its part (the screen may still be laying out on the first frames; a board card lifts).
func _process(_delta: float) -> void:
	_place()


func _place() -> void:
	var inv := get_global_transform().affine_inverse()
	for i in stamps.size():
		var part := parts[i]
		if part == null or not is_instance_valid(part):
			continue
		var s := stamps[i]
		var centre: Vector2 = part.get_global_transform() * (part.size * 0.5)
		s.pivot_offset = s.size * 0.5
		s.position = inv * centre - s.size * 0.5


## Every key, button and click stops here while the form is void (mouse motion goes nowhere either: the void covers it).
func _input(event: InputEvent) -> void:
	if _fired or event is InputEventMouseMotion:
		return
	get_viewport().set_input_as_handled()


func _fire() -> void:
	if _fired:
		return
	_fired = true
	if action.is_valid():
		action.call()
	if is_instance_valid(self) and is_inside_tree():
		queue_free()
