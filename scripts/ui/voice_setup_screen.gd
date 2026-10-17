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
## it starts its own VoiceCaster. Emits `back` (the menu also handles Esc). Free the screen to stop the mic.

signal back

const STRICTNESS_HELP := {
	"strict": "The cast word must start the phrase: \"cast heal\". \"Should I cast heal?\" does nothing.",
	"loose": "The cast word anywhere before a spell counts, so \"should I cast heal?\" fires. The default.",
	"chaos": "Any spell word anywhere casts, cast word or not. Saying \"corn\" is now a decision.",
}
const GATE_HINT := "Raise until the TV stops showing up; your own voice should still go past the line."
const GLOW_SECONDS := 1.8

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
var gate_slider: HSlider
var gate_value: Label
var meter: MicMeter
var status_label: Label
var heard_label: Label
var heard_tag: Label
var result_label: Label
var say_label: Label
var type_edit: LineEdit
var back_button: Button

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
		_show_note(note, MenuStyle.WARN)
	else:
		_show_note(str(v["error"]), MenuStyle.BAD)
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
	add_child(MenuStyle.dim_rect(0.72))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := MenuStyle.panel(MenuStyle.AMBER, 36, 22)
	panel.custom_minimum_size = Vector2(1240, 0)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(MenuStyle.label("VOICE SETUP", 38, MenuStyle.AMBER_HOT))
	var head_gap := Control.new()
	head_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_gap)
	back_button = MenuStyle.small_button("Back  (Esc)")
	back_button.custom_minimum_size = Vector2(180, 44)
	back_button.pressed.connect(func() -> void: back.emit())
	head.add_child(back_button)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	root.add_child(cols)
	cols.add_child(_build_word_column())
	cols.add_child(_build_mic_column())

	root.add_child(_hline())
	root.add_child(_build_try_it())


func _build_word_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(440, 0)
	col.add_theme_constant_override("separation", 8)

	col.add_child(MenuStyle.label("CAST WORD", 14, MenuStyle.DIM, true))
	trigger_menu = OptionButton.new()
	for w in VoiceCaster.TRIGGER_OPTIONS:
		trigger_menu.add_item(w)
	trigger_menu.add_item("custom...")
	MenuStyle.style_control(trigger_menu)
	trigger_menu.item_selected.connect(_on_trigger_selected)
	col.add_child(trigger_menu)
	col.add_child(MenuStyle.wrapped("The word you say before a spell. Pick one that is easy to say and rare in conversation.", 15))

	custom_row = HBoxContainer.new()
	custom_row.visible = false
	custom_row.add_theme_constant_override("separation", 8)
	custom_edit = LineEdit.new()
	custom_edit.placeholder_text = "your own word, then Enter"
	custom_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuStyle.style_control(custom_edit)
	custom_edit.text_submitted.connect(func(text: String) -> void: set_trigger(text))
	custom_row.add_child(custom_edit)
	col.add_child(custom_row)
	trigger_note = MenuStyle.wrapped("", 15, MenuStyle.WARN)
	trigger_note.visible = false
	col.add_child(trigger_note)

	col.add_child(MenuStyle.gap(6))
	col.add_child(MenuStyle.label("STRICTNESS", 14, MenuStyle.DIM, true))
	strict_menu = OptionButton.new()
	for m in VoiceCaster.STRICTNESS_OPTIONS:
		strict_menu.add_item(m)
	MenuStyle.style_control(strict_menu)
	strict_menu.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			set_strictness(VoiceCaster.STRICTNESS_OPTIONS[i]))
	col.add_child(strict_menu)
	strict_help = MenuStyle.wrapped("", 16, MenuStyle.TEXT)
	strict_help.custom_minimum_size = Vector2(0, 66)
	col.add_child(strict_help)
	return col


func _build_mic_column() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)

	var title := HBoxContainer.new()
	col.add_child(title)
	title.add_child(MenuStyle.label("MICROPHONE", 14, MenuStyle.DIM, true))
	_voice_lamp = MenuStyle.label("   ", 14, MenuStyle.DIM)
	title.add_child(_voice_lamp)
	status_label = MenuStyle.label("", 14, MenuStyle.DIM)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title.add_child(status_label)

	meter = MicMeter.new()
	meter.gate = caster.gate
	meter.custom_minimum_size = Vector2(0, MicMeter.HEIGHT)
	meter.threshold_dragged.connect(func(db: float) -> void: set_min_voice(db))
	col.add_child(meter)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	row.add_child(MenuStyle.label("Min voice", 18, MenuStyle.TEXT))
	gate_slider = HSlider.new()
	gate_slider.min_value = SpeechGate.METER_MIN_DB
	gate_slider.max_value = SpeechGate.METER_MAX_DB
	gate_slider.step = 1.0
	gate_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gate_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gate_slider.custom_minimum_size = Vector2(0, 28)
	MenuStyle.style_slider(gate_slider)
	gate_slider.tooltip_text = GATE_HINT
	gate_slider.value_changed.connect(func(v: float) -> void:
		if not _syncing:
			set_min_voice(v))
	row.add_child(gate_slider)
	gate_value = MenuStyle.label("", 18, MenuStyle.AMBER_HOT)
	gate_value.custom_minimum_size = Vector2(70, 0)
	gate_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(gate_value)

	col.add_child(MenuStyle.wrapped(GATE_HINT, 16, MenuStyle.TEXT))
	_gate_info = MenuStyle.wrapped("", 13, MenuStyle.DIM)
	col.add_child(_gate_info)
	return col


func _build_try_it() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	box.add_child(head)
	head.add_child(MenuStyle.label("TRY IT", 14, MenuStyle.DIM, true))
	say_label = MenuStyle.label("", 22, MenuStyle.TEXT)
	head.add_child(say_label)

	var heard_row := HBoxContainer.new()
	heard_row.add_theme_constant_override("separation", 10)
	box.add_child(heard_row)
	heard_row.add_child(MenuStyle.label("HEARD", 14, MenuStyle.DIM))
	heard_tag = MenuStyle.label("", 14, MenuStyle.WARN)
	heard_row.add_child(heard_tag)
	heard_label = MenuStyle.label("...", 40, MenuStyle.DIM)
	heard_label.custom_minimum_size = Vector2(0, 54)
	heard_label.clip_text = true
	box.add_child(heard_label)
	result_label = MenuStyle.label(" ", 26, MenuStyle.DIM, true)
	box.add_child(result_label)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	box.add_child(chips)
	for id in SpellBook.ids():
		chips.add_child(_make_chip(id))

	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 10)
	box.add_child(type_row)
	type_row.add_child(MenuStyle.label("no microphone? type it:", 16, MenuStyle.DIM))
	type_edit = LineEdit.new()
	type_edit.placeholder_text = "cast heal   (Enter)"
	type_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuStyle.style_control(type_edit)
	type_edit.text_submitted.connect(func(text: String) -> void:
		if text.strip_edges() != "":
			say(text)
		type_edit.clear())
	type_row.add_child(type_edit)
	return box


func _make_chip(id: String) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := MenuStyle.margins(MenuStyle.box(MenuStyle.CARD, MenuStyle.EDGE, 2, 8), 8, 5)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var name_l := MenuStyle.label(SpellBook.spell_name(id).to_upper(), 16, SpellBook.color_of(id), true)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	var power := MenuStyle.label(" ", 18, MenuStyle.TEXT)
	power.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(power)
	_chips[id] = {"style": sb, "power": power, "glow": 0.0}
	return p


func _hline() -> Control:
	var r := ColorRect.new()
	r.color = MenuStyle.EDGE
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


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
		_show_note("not recommended: " + note if note != "" else "", MenuStyle.WARN)
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
	status_label.add_theme_color_override("font_color", MenuStyle.GOOD if caster.is_ready() else MenuStyle.WARN)
	_gate_info.text = caster.gate.describe()
	for id: String in _chips:
		var c: Dictionary = _chips[id]
		var g := maxf(0.0, float(c["glow"]) - delta / GLOW_SECONDS)
		c["glow"] = g
		var sb := c["style"] as StyleBoxFlat
		var col := SpellBook.color_of(id)
		sb.bg_color = MenuStyle.CARD.lerp(col.darkened(0.45), g)
		sb.border_color = MenuStyle.EDGE.lerp(col, g)
		if g <= 0.0:
			(c["power"] as Label).text = " "


# --- caster events ------------------------------------------------------------------------------------

func _on_voice_activity(active: bool) -> void:
	_voice_lamp.text = "   hearing you" if active else "   "
	_voice_lamp.add_theme_color_override("font_color", MenuStyle.GOOD)


func _on_heard(text: String, final: bool) -> void:
	heard_label.text = ("\"%s\"" % text) if text != "" else "..."
	heard_label.add_theme_color_override("font_color", MenuStyle.TEXT if final else MenuStyle.DIM)
	heard_tag.text = "  typed" if caster.last_heard_typed else ("  final" if final else "  hearing...")
	if text != "":
		result_label.text = " "


func _on_cast(info: Dictionary) -> void:
	var id := str(info["spell"])
	var accidental := bool(info["accidental"])
	var pct := roundi(float(info["power"]) * 100.0)
	var col := SpellBook.color_of(id)
	result_label.text = "%s%s  %d%%" % ["ACCIDENTAL " if accidental else "CAST ", id.to_upper(), pct]
	result_label.add_theme_color_override("font_color", col)
	if _chips.has(id):
		var c: Dictionary = _chips[id]
		c["glow"] = 1.0
		(c["power"] as Label).text = "%d%%" % pct


func _on_fizzle(_heard_text: String, reason: String) -> void:
	result_label.text = "fizzle  (%s)" % reason
	result_label.add_theme_color_override("font_color", MenuStyle.BAD)


func _on_utterance_finished(text: String, outcome: Dictionary, _typed: bool) -> void:
	if text.strip_edges() == "" or str(outcome["kind"]) != "none":
		return
	result_label.text = "no spell: %s" % ("say the cast word, then a spell" if caster.get_strictness() != "chaos" else "say a spell word")
	result_label.add_theme_color_override("font_color", MenuStyle.DIM)


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
		var font := ThemeDB.fallback_font
		var bar := Rect2(PAD, BAR_TOP, size.x - 2.0 * PAD, BAR_H)
		draw_rect(bar, Color(0.03, 0.035, 0.055))
		# Scale: a tick and a number every 10 dB.
		for db in range(-70, -9, 10):
			var x := x_of(float(db))
			draw_line(Vector2(x, bar.end.y), Vector2(x, bar.end.y + 6.0), MenuStyle.EDGE, 2.0)
			var s := str(db)
			var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(font, Vector2(clampf(x - w * 0.5, 0.0, size.x - w), bar.end.y + 20.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MenuStyle.DIM)
			if db > -70:
				draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), Color(1, 1, 1, 0.05), 1.0)
		# The level: quiet blue-grey up to the min-voice line, green past it (that part opens the gate).
		var tx := x_of(gate.min_voice_db)
		var lx := x_of(shown_db)
		if lx > bar.position.x:
			var quiet_end := minf(lx, tx)
			draw_rect(Rect2(bar.position.x, bar.position.y + 4.0, quiet_end - bar.position.x, bar.size.y - 8.0), Color(0.34, 0.42, 0.62))
			if lx > tx:
				draw_rect(Rect2(tx, bar.position.y + 4.0, lx - tx, bar.size.y - 8.0), MenuStyle.GOOD)
		# Recent peak.
		if peak_db > SpeechGate.METER_MIN_DB:
			var px := x_of(peak_db)
			draw_line(Vector2(px, bar.position.y + 4.0), Vector2(px, bar.end.y - 4.0), Color(1, 1, 1, 0.55), 2.0)
		draw_rect(bar, MenuStyle.EDGE, false, 2.0)

		# The learned noise floor.
		var fdb := SpeechGate.db(gate.noise_floor)
		var fx := x_of(fdb)
		draw_line(Vector2(fx, bar.position.y), Vector2(fx, bar.end.y), Color(0.75, 0.78, 0.88, 0.85), 2.0)
		var ftext := "floor %d dB" % roundi(fdb)
		var fw := font.get_string_size(ftext, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var fpos := fx + 6.0 if fx + 6.0 + fw < bar.end.x - 4.0 else fx - 6.0 - fw
		if absf(fx - tx) < fw + 14.0 and fx < tx:
			fpos = fx - 6.0 - fw
		draw_string(font, Vector2(maxf(fpos, bar.position.x + 4.0), bar.end.y - 8.0), ftext, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.83, 0.92))

		# The last voice peak (green), labelled above.
		if gate.last_peak_db > -99.0:
			var vx := x_of(gate.last_peak_db)
			draw_line(Vector2(vx, 22.0), Vector2(vx, bar.end.y), MenuStyle.GOOD, 2.0)
			_label_above(font, "last voice %d dB" % roundi(gate.last_peak_db), vx, 18.0, MenuStyle.GOOD)

		# The min-voice threshold (amber), with a grab handle.
		draw_line(Vector2(tx, 4.0), Vector2(tx, bar.end.y + 4.0), MenuStyle.AMBER_HOT, 3.0)
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 7.0, 4.0), Vector2(tx + 7.0, 4.0), Vector2(tx, 15.0)]), MenuStyle.AMBER_HOT)
		_label_above(font, "min voice %d dB" % roundi(gate.min_voice_db), tx, 40.0, MenuStyle.AMBER_HOT, true)

	func _label_above(font: Font, text: String, x: float, baseline: float, color: Color, right_of: bool = false) -> void:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var px := x + 10.0 if right_of else x - w * 0.5
		if px + w > size.x:
			px = x - 10.0 - w if right_of else size.x - w
		draw_string(font, Vector2(maxf(px, 0.0), baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, color)
