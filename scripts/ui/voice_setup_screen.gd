class_name VoiceSetupScreen
extends Control
## The menu's Voice setup screen. It runs a real VoiceCaster (the same code the game uses, with the
## microphone) so everything can be tested live, and edits the persisted VoiceSettings through it:
##   - the cast word (TRIGGER_OPTIONS or a custom word, validated by VoiceSettings.validate_trigger),
##   - the strictness (strict / loose / chaos) with a one-line explanation of each,
##   - the min-voice slider and a big live mic meter in dB: the threshold line, the learned noise floor and
##     the peak of the last voice (the numbers come from the caster's SpeechGate),
##   - "Try it": say "<cast word> heal"; HEARD, the matched spell and its power show live, like the debug panel.
## Changes are saved at once (VoiceCaster persists them to `settings_path`) and the game picks them up when
## it starts its own VoiceCaster. Emits `back` once the form is voided (void_back(): the Back button, or Esc through the
## menu; FormVoid). Free the screen to stop the mic.

signal back

const STRICTNESS_HELP := {
	"strict": "The cast word must start the phrase: \"cast heal\". \"Should I cast heal?\" does nothing.",
	"loose": "The cast word anywhere before a spell counts, so \"should I cast heal?\" fires. The default.",
	"chaos": "Any spell word anywhere casts, cast word or not. Saying \"corn\" is now a decision.",
}
const GATE_HINT := "Raise until the TV stops showing up; your own voice should still go past the line."
const GLOW_SECONDS := 1.8
## Typed ink at half strength: a value that is not live yet.
const DIM_INK := Color(0.114, 0.102, 0.149, 0.5)

## Open the microphone. Tests turn it off (typed input still works).
var use_mic := true
## "" = VoiceSettings.DEFAULT_PATH. Tests point this at a temp file.
var settings_path := ""
## Append every utterance to user://voice_log.csv like the game does. Tests turn it off.
var log_utterances := true

var caster: VoiceCaster
var trigger_menu: OptionButton
var strict_menu: OptionButton
var custom_row: HBoxContainer
var custom_edit: LineEdit
var trigger_note: Label
var strict_help: Label
var gate_slider: BoxScale
var gate_value: Label
var meter: MicMeter
var status_label: Label
var heard_label: Label
var heard_tag: Label
var result_label: Label
var say_label: Label
var type_edit: LineEdit
var back_button: Button
var sheet: FormSheet

var _chips: Dictionary = {}       ## spell id -> {style, power, glow}
var _voice_lamp: Label
var _gate_info: Label
var _syncing := false
var _note_word := ""             ## the cast word the trigger note was written for


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_caster()
	_build()
	_sync()
	set_process(true)


func first_focus() -> Control:
	return trigger_menu


## Back is VOID (form-rules.md §6): stamp the sheet, then emit `back`. False while it is already being voided.
func void_back() -> bool:
	return FormVoid.void_and(self, back.emit, sheet)


func _exit_tree() -> void:
	if caster != null:
		caster.stop()


func _start_caster() -> void:
	caster = VoiceCaster.new()
	caster.name = "VoiceCaster"
	caster.use_mic = use_mic
	if settings_path != "":
		caster.settings_path = settings_path
	if not log_utterances:
		caster.voice_log.enabled = false
	add_child(caster)
	caster.heard.connect(_on_heard)
	caster.cast_detail.connect(_on_cast)
	caster.spell_fizzled.connect(_on_fizzle)
	caster.utterance_finished.connect(_on_utterance_finished)
	caster.voice_activity.connect(_on_voice_activity)
	caster.trigger_word_changed.connect(func(_w: String) -> void: _sync())
	caster.strictness_changed.connect(func(_m: String) -> void: _sync())
	caster.start(PackedStringArray(SpellBook.ids()))


# --- API (the controls call these too) -----------------------------------------------------------------

## Set the cast word; returns VoiceSettings.validate_trigger()'s verdict (ok=false changes nothing).
func set_trigger(word: String) -> Dictionary:
	var v := caster.set_trigger_word(word)
	_sync()
	if bool(v["ok"]):
		var warnings: PackedStringArray = v["warnings"]
		var note := "; ".join(warnings)
		if note == "":
			note = _note_for(str(v["word"]))
		_note_word = str(v["word"])
		_show_note(note, FormTheme.RED)
	else:
		_show_note(str(v["error"]), FormTheme.RED)
	return v


func set_strictness(mode: String) -> bool:
	var ok := caster.set_strictness(mode)
	_sync()
	return ok


## The min-voice threshold in dBFS (clamped to the slider's range).
func set_min_voice(db: float) -> void:
	caster.set_min_voice_db(db)
	_sync()


## Type a line as if it had been heard (the keyboard fallback and the screenshots).
func say(text: String) -> void:
	caster.inject_text(text)


# --- UI ------------------------------------------------------------------------------------------------

func _build() -> void:
	theme = FormTheme.theme()
	add_child(FormTheme.dim_rect(0.55))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	sheet = FormSheet.new("7", "Rig calibration", "Dispatch rig  ·  microphone and cast word", "Mic status", "...", "white", 44)
	sheet.custom_minimum_size = Vector2(1500, 0)
	center.add_child(sheet)
	status_label = sheet.header.copy_value
	status_label.custom_minimum_size = Vector2(330, 0)
	status_label.add_theme_font_size_override("font_size", 19)
	var root := sheet.body

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 0)
	cols.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(cols)
	var left := _build_word_column()
	left.custom_minimum_size = Vector2(620, 0)
	cols.add_child(FormTheme.margin(left, 26, 10, 26, 12))
	var vline := ColorRect.new()
	vline.color = FormTheme.INK
	vline.custom_minimum_size = Vector2(3, 0)
	vline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(vline)
	var right := FormTheme.margin(_build_mic_column(), 26, 10, 26, 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	root.add_child(FormTheme.rule(3.0))
	root.add_child(FormTheme.margin(_build_try_it(), 26, 10, 26, 14))

	var keys := KeyHints.new([["Up", "Down", "field"], ["Left", "Right", "adjust"], ["Esc", "void"]])
	keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	keys.offset_left = 58.0
	keys.offset_top = -48.0
	keys.offset_bottom = -14.0
	add_child(keys)

	FormTheme.chain([trigger_menu, custom_edit, strict_menu, gate_slider, type_edit, back_button], false)


func _caption(text: String) -> Label:
	return FormTheme.label(text, 20, FormTheme.INK, true)


func _build_word_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_PASS

	col.add_child(_caption("A. CAST WORD"))
	trigger_menu = OptionButton.new()
	for w in VoiceCaster.TRIGGER_OPTIONS:
		trigger_menu.add_item(w)
	trigger_menu.add_item("custom...")
	trigger_menu.custom_minimum_size = Vector2(0, 52)
	trigger_menu.item_selected.connect(_on_trigger_selected)
	col.add_child(trigger_menu)
	col.add_child(FormTheme.small("The word you say before a spell. Pick one that is easy to say and rare in conversation.", 19))

	custom_row = HBoxContainer.new()
	custom_row.visible = false
	custom_row.add_theme_constant_override("separation", 8)
	custom_edit = LineEdit.new()
	custom_edit.placeholder_text = "your own word, then Enter"
	custom_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_edit.text_submitted.connect(func(text: String) -> void: set_trigger(text))
	custom_row.add_child(custom_edit)
	col.add_child(custom_row)
	trigger_note = FormTheme.typed_wrapped("", 19, FormTheme.RED, true)
	trigger_note.visible = false
	col.add_child(trigger_note)

	col.add_child(FormTheme.gap(6))
	col.add_child(_caption("B. STRICTNESS"))
	strict_menu = OptionButton.new()
	for m in VoiceCaster.STRICTNESS_OPTIONS:
		strict_menu.add_item(m)
	strict_menu.custom_minimum_size = Vector2(0, 52)
	strict_menu.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			set_strictness(VoiceCaster.STRICTNESS_OPTIONS[i]))
	col.add_child(strict_menu)
	strict_help = FormTheme.typed_wrapped("", 19, FormTheme.TYPED)
	strict_help.custom_minimum_size = Vector2(0, 88)
	col.add_child(strict_help)
	return col


func _build_mic_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_PASS

	var title := HBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)
	title.add_child(_caption("C. MICROPHONE"))
	_voice_lamp = FormTheme.label("", 19, FormTheme.GREEN_INK, true)
	_voice_lamp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voice_lamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title.add_child(_voice_lamp)

	meter = MicMeter.new()
	meter.gate = caster.gate
	meter.custom_minimum_size = Vector2(0, MicMeter.HEIGHT)
	meter.threshold_dragged.connect(func(db: float) -> void: set_min_voice(db))
	col.add_child(meter)

	gate_slider = BoxScale.new()
	gate_slider.min_value = SpeechGate.METER_MIN_DB
	gate_slider.max_value = SpeechGate.METER_MAX_DB
	gate_slider.step = 1.0
	gate_slider.tooltip_text = GATE_HINT
	gate_slider.value_changed.connect(func(v: float) -> void:
		if not _syncing:
			set_min_voice(v))
	gate_value = FormTheme.typed("", 24)
	gate_value.custom_minimum_size = Vector2(96, 0)
	gate_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var row := FormField.new("Min voice", gate_slider, 170.0, 56.0)
	row.add(gate_value, false, false)
	col.add_child(row)

	col.add_child(FormTheme.typed_wrapped(GATE_HINT, 18, FormTheme.TYPED))
	_gate_info = FormTheme.small("", 17, FormTheme.INK)
	col.add_child(_gate_info)
	return col


func _build_try_it() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_PASS

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	head.add_child(_caption("D. TRY IT"))
	say_label = FormTheme.typed("", 24)
	head.add_child(say_label)

	var heard_row := HBoxContainer.new()
	heard_row.add_theme_constant_override("separation", 10)
	heard_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(heard_row)
	heard_row.add_child(FormTheme.label("HEARD", 18, FormTheme.INK, true))
	heard_tag = FormTheme.label("", 18, FormTheme.RED, true)
	heard_row.add_child(heard_tag)
	heard_label = FormTheme.typed("...", 38, DIM_INK)
	heard_label.custom_minimum_size = Vector2(0, 52)
	heard_label.clip_text = true
	heard_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(FormTheme.boxed(heard_label, 14, 4, Color(1, 1, 1, 0.3)))
	result_label = FormTheme.typed(" ", 26, DIM_INK)
	box.add_child(result_label)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(chips)
	for id in SpellBook.ids():
		chips.add_child(_make_chip(id))

	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 12)
	type_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(type_row)
	type_row.add_child(FormTheme.label("NO MICROPHONE? TYPE IT:", 19, FormTheme.INK, true))
	type_edit = LineEdit.new()
	type_edit.placeholder_text = "cast heal   (Enter)"
	type_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_edit.text_submitted.connect(func(text: String) -> void:
		if text.strip_edges() != "":
			say(text)
		type_edit.clear())
	type_row.add_child(type_edit)
	back_button = FormTheme.button("Back  (Esc)")
	back_button.custom_minimum_size = Vector2(220, 50)
	back_button.pressed.connect(void_back)
	type_row.add_child(back_button)
	return box


func _make_chip(id: String) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := FormTheme.box_style(FormTheme.FIELD_FILL, FormTheme.INK, 2.0, 8.0, 4.0)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var name_l := FormTheme.label(SpellBook.spell_name(id).to_upper(), 20, FormTheme.INK, true)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var power := FormTheme.typed(" ", 22)
	power.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(power)
	_chips[id] = {"style": sb, "power": power, "glow": 0.0}
	return p


# --- state -> controls --------------------------------------------------------------------------------

func _sync() -> void:
	if caster == null or trigger_menu == null:
		return
	_syncing = true
	var w := caster.get_trigger_word()
	var idx := VoiceCaster.TRIGGER_OPTIONS.find(w)
	if idx < 0:
		idx = VoiceCaster.TRIGGER_OPTIONS.size()
		trigger_menu.set_item_text(idx, "custom: " + w)
		custom_edit.text = w
		custom_row.visible = true
	else:
		trigger_menu.set_item_text(VoiceCaster.TRIGGER_OPTIONS.size(), "custom...")
	trigger_menu.select(idx)
	var mode := caster.get_strictness()
	strict_menu.select(maxi(0, VoiceCaster.STRICTNESS_OPTIONS.find(mode)))
	strict_help.text = str(STRICTNESS_HELP.get(mode, ""))
	gate_slider.value = caster.gate.min_voice_db
	gate_value.text = "%d dB" % roundi(caster.gate.min_voice_db)
	say_label.text = _say_text()
	if w != _note_word:   # a new word: its built-in warning (messages for a word you just typed stay)
		_note_word = w
		var note := _note_for(w)
		_show_note("not recommended: " + note if note != "" else "", FormTheme.RED)
	_syncing = false


func _say_text() -> String:
	if caster.get_strictness() == "chaos":
		return "Say  \"HEAL\"  (any spell word works)"
	return "Say  \"%s\"" % SpellBook.incantation("heal", caster.get_trigger_word())


func _note_for(word: String) -> String:
	return str(VoiceCaster.TRIGGER_NOTES.get(word, ""))


func _show_note(text: String, color: Color) -> void:
	trigger_note.text = text
	trigger_note.add_theme_color_override("font_color", color)
	trigger_note.visible = text != ""


func _on_trigger_selected(i: int) -> void:
	if _syncing:
		return
	if i >= VoiceCaster.TRIGGER_OPTIONS.size():
		custom_row.visible = true
		custom_edit.grab_focus()
		return
	custom_row.visible = false
	set_trigger(VoiceCaster.TRIGGER_OPTIONS[i])


# --- per frame ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if caster == null:
		return
	status_label.text = caster.status
	status_label.add_theme_color_override("font_color", FormTheme.GREEN_INK if caster.is_ready() else FormTheme.RED)
	_gate_info.text = caster.gate.describe()
	for id: String in _chips:
		var c: Dictionary = _chips[id]
		var g := maxf(0.0, float(c["glow"]) - delta / GLOW_SECONDS)
		c["glow"] = g
		var sb := c["style"] as StyleBoxFlat
		var col := SpellBook.color_of(id)
		sb.bg_color = FormTheme.FIELD_FILL.lerp(Color(col.lightened(0.1), 0.85), g)
		sb.border_color = FormTheme.INK.lerp(col.darkened(0.45), g)
		if g <= 0.0:
			(c["power"] as Label).text = " "


# --- caster events ------------------------------------------------------------------------------------

func _on_voice_activity(active: bool) -> void:
	_voice_lamp.text = "HEARING YOU" if active else ""
	_voice_lamp.add_theme_color_override("font_color", FormTheme.GREEN_INK)


func _on_heard(text: String, final: bool) -> void:
	heard_label.text = ("\"%s\"" % text) if text != "" else "..."
	heard_label.add_theme_color_override("font_color", FormTheme.TYPED if final else DIM_INK)
	heard_tag.text = "  typed" if caster.last_heard_typed else ("  final" if final else "  hearing...")
	if text != "":
		result_label.text = " "


func _on_cast(info: Dictionary) -> void:
	var id := str(info["spell"])
	var accidental := bool(info["accidental"])
	var pct := roundi(float(info["power"]) * 100.0)
	var col := SpellBook.color_of(id)
	result_label.text = "%s%s  %d%%" % ["ACCIDENTAL " if accidental else "CAST ", id.to_upper(), pct]
	result_label.add_theme_color_override("font_color", col.darkened(0.5))
	if _chips.has(id):
		var c: Dictionary = _chips[id]
		c["glow"] = 1.0
		(c["power"] as Label).text = "%d%%" % pct


func _on_fizzle(_heard_text: String, reason: String) -> void:
	result_label.text = "fizzle  (%s)" % reason
	result_label.add_theme_color_override("font_color", FormTheme.RED)


func _on_utterance_finished(text: String, outcome: Dictionary, _typed: bool) -> void:
	if text.strip_edges() == "" or str(outcome["kind"]) != "none":
		return
	result_label.text = "no spell: %s" % ("say the cast word, then a spell" if caster.get_strictness() != "chaos" else "say a spell word")
	result_label.add_theme_color_override("font_color", DIM_INK)


# --- the mic meter -----------------------------------------------------------------------------------

## A wide horizontal level meter on the -70..-10 dBFS scale. The bar is the latest 10 ms frame (fast attack,
## slow release); it turns green past the min-voice line. Marks: the min-voice threshold (amber, draggable),
## the learned noise floor (grey) and the peak of the last voice (green).
class MicMeter:
	extends Control

	signal threshold_dragged(db: float)

	const HEIGHT := 140.0
	const PAD := 6.0
	const BAR_TOP := 46.0
	const BAR_H := 66.0
	const FALL_DB_PER_SEC := 70.0
	const PEAK_HOLD := 1.2

	var gate: SpeechGate = null
	var shown_db := -100.0
	var peak_db := -100.0
	var _peak_age := 0.0
	var _dragging := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _process(delta: float) -> void:
		if gate == null:
			return
		var now := gate.level_db
		shown_db = now if now > shown_db else maxf(now, shown_db - FALL_DB_PER_SEC * delta)
		_peak_age += delta
		if now >= peak_db or _peak_age > PEAK_HOLD:
			peak_db = now
			_peak_age = 0.0
		queue_redraw()

	func _ready() -> void:
		set_process(true)

	func x_of(db: float) -> float:
		return PAD + SpeechGate.db_to_unit(db) * (size.x - 2.0 * PAD)

	func db_at(x: float) -> float:
		var u := clampf((x - PAD) / maxf(size.x - 2.0 * PAD, 1.0), 0.0, 1.0)
		return roundf(SpeechGate.METER_MIN_DB + u * (SpeechGate.METER_MAX_DB - SpeechGate.METER_MIN_DB))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				threshold_dragged.emit(db_at(event.position.x))
		elif event is InputEventMouseMotion and _dragging:
			threshold_dragged.emit(db_at(event.position.x))

	func _draw() -> void:
		if gate == null:
			return
		var font := FormTheme.typed_font()
		var nfont := FormTheme.label_font(true)
		var bar := Rect2(PAD, BAR_TOP, size.x - 2.0 * PAD, BAR_H)
		draw_rect(bar, Color(1, 1, 1, 0.45))
		# Scale: a tick and a number every 10 dB.
		for db in range(-70, -9, 10):
			var x := x_of(float(db))
			draw_line(Vector2(x, bar.end.y), Vector2(x, bar.end.y + 7.0), FormTheme.INK, 2.0)
			var s := str(db)
			var w := nfont.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			draw_string(nfont, Vector2(clampf(x - w * 0.5, 0.0, size.x - w), bar.end.y + 24.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, FormTheme.INK)
			if db > -70:
				draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(FormTheme.INK, 0.22), 1.0)
		# The level: quiet teal up to the min-voice line, green past it (that part opens the gate).
		var tx := x_of(gate.min_voice_db)
		var lx := x_of(shown_db)
		if lx > bar.position.x:
			var quiet_end := minf(lx, tx)
			draw_rect(Rect2(bar.position.x, bar.position.y + 4.0, quiet_end - bar.position.x, bar.size.y - 8.0), Color(0.36, 0.58, 0.62))
			if lx > tx:
				draw_rect(Rect2(tx, bar.position.y + 4.0, lx - tx, bar.size.y - 8.0), Color(0.2, 0.62, 0.36))
		# Recent peak.
		if peak_db > SpeechGate.METER_MIN_DB:
			var px := x_of(peak_db)
			draw_line(Vector2(px, bar.position.y + 4.0), Vector2(px, bar.end.y - 4.0), Color(FormTheme.TYPED, 0.7), 2.0)
		draw_rect(bar, FormTheme.INK, false, 2.5)

		# The learned noise floor.
		var fdb := SpeechGate.db(gate.noise_floor)
		var fx := x_of(fdb)
		draw_line(Vector2(fx, bar.position.y), Vector2(fx, bar.end.y), Color(FormTheme.TYPED, 0.65), 2.0)
		var ftext := "floor %d dB" % roundi(fdb)
		var fw := font.get_string_size(ftext, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var fpos := fx + 6.0 if fx + 6.0 + fw < bar.end.x - 4.0 else fx - 6.0 - fw
		if absf(fx - tx) < fw + 14.0 and fx < tx:
			fpos = fx - 6.0 - fw
		draw_string(font, Vector2(maxf(fpos, bar.position.x + 4.0), bar.end.y - 8.0), ftext, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, FormTheme.TYPED)

		# The last voice peak (green), labelled above.
		if gate.last_peak_db > -99.0:
			var vx := x_of(gate.last_peak_db)
			draw_line(Vector2(vx, 24.0), Vector2(vx, bar.end.y), FormTheme.GREEN_INK, 2.5)
			_label_above(font, "last voice %d dB" % roundi(gate.last_peak_db), vx, 20.0, FormTheme.GREEN_INK)

		# The min-voice threshold (red grease pencil), with a grab handle.
		draw_line(Vector2(tx, 4.0), Vector2(tx, bar.end.y + 4.0), FormTheme.GREASE, 4.0)
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 8.0, 4.0), Vector2(tx + 8.0, 4.0), Vector2(tx, 17.0)]), FormTheme.GREASE)
		_label_above(font, "min voice %d dB" % roundi(gate.min_voice_db), tx, 42.0, FormTheme.GREASE, true)

	func _label_above(font: Font, text: String, x: float, baseline: float, color: Color, right_of: bool = false) -> void:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var px := x + 12.0 if right_of else x - w * 0.5
		if px + w > size.x:
			px = x - 12.0 - w if right_of else size.x - w
		draw_string(font, Vector2(maxf(px, 0.0), baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, color)
