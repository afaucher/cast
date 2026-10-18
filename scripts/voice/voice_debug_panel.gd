class_name VoiceDebugPanel
extends Control
## In-game voice debug side panel, docked on the right (F1 toggles it), modeled
## on Hero-Reader's "Word match" view. Everything except the dropdowns and the
## custom-word box ignores the mouse, so it never eats game clicks.
##
## Top to bottom: title/status, trigger + strictness dropdowns, voice lamp and
## scrolling mic level graph, HEARD (the recognizer's raw text, large; partials
## grey and updating in place, finals white) with a rolling transcript of the
## last utterances and what each did, cards for the trigger word and each spell
## (colored by how the heard text matched), the event log, game sections, stats.
##
## API:
##   var panel := VoiceDebugPanel.new(); parent.add_child(panel); panel.attach(caster)
##   panel.log_game("player cast HEAL p=0.87 -> healed 3", Color.WHITE)
##   panel.add_section("GAME", some_control)      # the game's own stats block
##
## Works without a model ("no model, typed input only"): typed text, fed through
## VoiceCaster.inject_text(), is shown as heard (marked typed) and logged.
##
## Online (M7) the panel is still ONE recognizer: this machine's own (each player's mic is heard on that
## player's machine, and a teammate's cast arrives as an event, never through here). set_mic_owner() puts a
## line under the title saying whose mic it is ("THIS MACHINE'S MIC  ·  c1, seat 2").

const PANEL_WIDTH := 400.0
const HISTORY := 160           # mic level samples (~2.7 s at 60 fps)
const TRANSCRIPT_LINES := 8
const MAX_LOG_LINES := 300

const C_BG := Color(0.05, 0.06, 0.12, 0.84)
const C_CARD := Color(0.14, 0.16, 0.30)
const C_TEXT := Color(0.95, 0.95, 1.0)
const C_DIM := Color(0.62, 0.65, 0.85)
const C_WARN := Color(1.0, 0.82, 0.30)
const C_BAD := Color(1.0, 0.45, 0.45)
const C_GAME := Color(0.78, 0.62, 1.0)
const KIND_COLORS := {
	"exact": Color(0.30, 1.00, 0.60),
	"homophone": Color(0.30, 0.90, 1.00),
	"sound_alike": Color(1.00, 0.85, 0.30),
	"wait": Color(0.55, 0.65, 1.00),
	"cast": Color(0.30, 1.00, 0.60),
	"accidental": Color(1.00, 0.62, 0.25),
	"fizzle": Color(1.00, 0.45, 0.45),
}

## F1 (action "toggle_voice_debug") shows/hides the panel. Visible by default.
var toggle_with_f1 := true

var caster: VoiceCaster
var _t0 := 0
var _level_hist := PackedFloat32Array()
var _voice_hist := PackedByteArray()
var _voice := false

var _status: Label
var _owner: Label
var _trigger_menu: OptionButton
var _strict_menu: OptionButton
var _custom_row: HBoxContainer
var _custom_edit: LineEdit
var _trigger_note: Label
var _lamp: Label
var _scope: Control
var _heard: Label
var _heard_tag: Label
var _transcript: RichTextLabel
var _card_grid: GridContainer
var _cards: Array = []          # {panel, style, name, kind, bar, power, word}
var _log_box: RichTextLabel
var _sections: VBoxContainer
var _stats: Label
var _interactive: Array = []
var _gate_slider: HSlider
var _gate_value: Label
var _gate_info: Label
var _syncing_gate := false

var _transcript_rows: Array = []
var _n_casts := 0
var _n_accidental := 0
var _n_fizzle := 0
var _n_nomatch := 0
var _n_ignored := 0
var _latencies: Array = []
var _last_partial_logged := ""


func _init() -> void:
	_t0 = Time.get_ticks_msec()
	_level_hist.resize(HISTORY)
	_voice_hist.resize(HISTORY)
	_build()


func _ready() -> void:
	set_process(true)
	if toggle_with_f1 and not InputMap.has_action("toggle_voice_debug"):
		InputSetup.ensure_actions()


func _unhandled_input(event: InputEvent) -> void:
	if toggle_with_f1 and InputMap.has_action("toggle_voice_debug") and event.is_action_pressed("toggle_voice_debug"):
		visible = not visible
		get_viewport().set_input_as_handled()


# --- public API -----------------------------------------------------------------

func attach(voice_caster: VoiceCaster) -> void:
	caster = voice_caster
	caster.heard.connect(_on_heard)
	caster.voice_activity.connect(_on_voice_activity)
	caster.cast_detail.connect(_on_cast)
	caster.spell_fizzled.connect(_on_fizzle)
	caster.ignored.connect(_on_ignored)
	caster.utterance_finished.connect(_on_utterance_finished)
	caster.trigger_word_changed.connect(func(_w: String) -> void: _rebuild_cards(); _sync_menus())
	caster.strictness_changed.connect(func(_m: String) -> void: _sync_menus())
	_rebuild_cards()
	_sync_menus()
	_refresh_status()
	_log("[color=#8890c0]attached: trigger '%s', %s[/color]" % [caster.get_trigger_word(), caster.get_strictness()])


## Online: whose recognizer this is ("" hides the line).
func set_mic_owner(text: String) -> void:
	_owner.text = text
	_owner.visible = text != ""


func mic_owner_text() -> String:
	return _owner.text if _owner.visible else ""


## Casts this panel's recognizer made (tests: a teammate's casts never count here).
func cast_count() -> int:
	return _n_casts


## The game appends its reactions here ("player cast HEAL p=0.87 -> healed 3").
func log_game(text: String, color: Color = Color.WHITE) -> void:
	_log("[color=#%s]GAME[/color]  [color=#%s]%s[/color]" % [C_GAME.to_html(false), color.to_html(false), _esc(text)])


## Add a titled block (the game's stats: fps, player cell, cooldowns, monsters ...).
func add_section(title: String, content: Control) -> void:
	var box := VBoxContainer.new()
	box.add_child(_label(title, 12, C_GAME))
	box.add_child(content)
	_sections.add_child(box)
	_ignore_mouse(box)


# --- UI ---------------------------------------------------------------------------

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -PANEL_WIDTH
	offset_right = 0
	offset_top = 0
	offset_bottom = 0
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_top = 8
	root.offset_right = -10
	root.offset_bottom = -8
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var title_row := HBoxContainer.new()
	root.add_child(title_row)
	title_row.add_child(_label("VOICE", 18, C_TEXT))
	_status = _label("", 12, C_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_row.add_child(_status)
	_owner = _label("", 12, C_WARN)
	_owner.visible = false
	root.add_child(_owner)

	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 6)
	root.add_child(opts)
	opts.add_child(_label("say:", 12, C_DIM))
	_trigger_menu = OptionButton.new()
	for w in VoiceCaster.TRIGGER_OPTIONS:
		_trigger_menu.add_item(w)
	_trigger_menu.add_item("custom...")
	_trigger_menu.item_selected.connect(_on_trigger_selected)
	_trigger_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opts.add_child(_trigger_menu)
	_strict_menu = OptionButton.new()
	for m in VoiceCaster.STRICTNESS_OPTIONS:
		_strict_menu.add_item(m)
	_strict_menu.item_selected.connect(func(i: int) -> void:
		if caster != null:
			caster.set_strictness(VoiceCaster.STRICTNESS_OPTIONS[i]))
	opts.add_child(_strict_menu)
	_interactive.append_array([_trigger_menu, _strict_menu])

	_custom_row = HBoxContainer.new()
	_custom_row.visible = false
	root.add_child(_custom_row)
	_custom_edit = LineEdit.new()
	_custom_edit.placeholder_text = "custom trigger word, Enter"
	_custom_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom_edit.text_submitted.connect(_on_custom_submitted)
	_custom_row.add_child(_custom_edit)
	_interactive.append(_custom_edit)
	# Voice level gate: frames quieter than this never reach the recognizer.
	var gate_row := HBoxContainer.new()
	gate_row.add_theme_constant_override("separation", 6)
	root.add_child(gate_row)
	gate_row.add_child(_label("min voice", 12, C_DIM))
	_gate_slider = HSlider.new()
	_gate_slider.min_value = -70.0
	_gate_slider.max_value = -10.0
	_gate_slider.step = 1.0
	_gate_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gate_slider.custom_minimum_size = Vector2(0, 20)
	_gate_slider.tooltip_text = "Raise until background speech (TV, speakers) stops showing up, but your own voice still opens the gate."
	_gate_slider.value_changed.connect(func(v: float) -> void:
		_gate_value.text = "%d dB" % roundi(v)
		if caster != null and not _syncing_gate:
			caster.set_min_voice_db(v))
	gate_row.add_child(_gate_slider)
	_gate_value = _label("", 12, C_TEXT)
	_gate_value.custom_minimum_size = Vector2(52, 0)
	gate_row.add_child(_gate_value)
	_interactive.append(_gate_slider)
	_gate_info = _label("", 11, C_DIM)
	_gate_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_gate_info)

	_trigger_note = _label("", 11, C_WARN)
	_trigger_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trigger_note.visible = false
	root.add_child(_trigger_note)

	# Mic strip: lamp + scrolling level graph.
	var mic := HBoxContainer.new()
	mic.add_theme_constant_override("separation", 8)
	root.add_child(mic)
	_lamp = _label("  MIC  ", 14, C_DIM)
	_lamp.custom_minimum_size = Vector2(70, 34)
	_lamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lamp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mic.add_child(_lamp)
	_scope = Control.new()
	_scope.custom_minimum_size = Vector2(0, 34)
	_scope.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scope.draw.connect(_draw_scope)
	mic.add_child(_scope)

	# HEARD: the recognizer's raw text, always.
	var heard_head := HBoxContainer.new()
	root.add_child(heard_head)
	heard_head.add_child(_label("HEARD", 11, C_DIM))
	_heard_tag = _label("", 11, C_WARN)
	heard_head.add_child(_heard_tag)
	_heard = _label("...", 26, C_DIM)
	_heard.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heard.custom_minimum_size = Vector2(0, 66)
	_heard.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	root.add_child(_heard)
	_transcript = RichTextLabel.new()
	_transcript.bbcode_enabled = true
	_transcript.scroll_active = false
	_transcript.custom_minimum_size = Vector2(0, 124)
	_transcript.add_theme_font_size_override("normal_font_size", 12)
	_transcript.add_theme_color_override("default_color", C_DIM)
	root.add_child(_transcript)

	_card_grid = GridContainer.new()
	_card_grid.columns = 3
	_card_grid.add_theme_constant_override("h_separation", 5)
	_card_grid.add_theme_constant_override("v_separation", 5)
	root.add_child(_card_grid)

	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.fit_content = true
	legend.scroll_active = false
	legend.add_theme_font_size_override("normal_font_size", 10)
	legend.text = "[color=#%s]exact[/color] [color=#%s]homophone[/color] [color=#%s]sound-alike[/color] [color=#%s]waiting[/color]  bar = letter closeness" % [
		KIND_COLORS["exact"].to_html(false), KIND_COLORS["homophone"].to_html(false),
		KIND_COLORS["sound_alike"].to_html(false), KIND_COLORS["wait"].to_html(false)]
	root.add_child(legend)

	_log_box = RichTextLabel.new()
	_log_box.bbcode_enabled = true
	_log_box.scroll_following = true
	_log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_box.custom_minimum_size = Vector2(0, 120)
	_log_box.add_theme_font_size_override("normal_font_size", 12)
	_log_box.add_theme_color_override("default_color", C_DIM)
	root.add_child(_log_box)

	_sections = VBoxContainer.new()
	root.add_child(_sections)

	_stats = _label("", 11, C_DIM)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_stats)

	_ignore_mouse(self)
	_update_stats()


func _label(text: String, size: int, color: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		var c := node as Control
		if not (c is BaseButton or c is LineEdit or _interactive.has(c)):
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


func _make_card(word: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.pivot_offset = Vector2(55, 30)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_CARD
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(3)
	sb.border_color = C_CARD
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	panel.add_child(box)
	var name_l := _label(word, 14, C_TEXT)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_l)
	var kind := _label(" ", 10, C_DIM)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# "sound-alike 'tent tickles'" must not widen the card past the 400 px panel.
	kind.clip_text = true
	kind.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(kind)
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	box.add_child(bar)
	var power := _label(" ", 11, C_DIM)
	power.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(power)
	_ignore_mouse(panel)
	return {"panel": panel, "style": sb, "name": name_l, "kind": kind, "bar": bar, "power": power, "word": word}


func _rebuild_cards() -> void:
	for c in _card_grid.get_children():
		c.queue_free()
	_cards.clear()
	if caster == null:
		return
	for ex in caster.get_incantation().explain(""):
		var card := _make_card(str(ex["word"]).to_upper())
		card["word"] = ex["word"]
		_card_grid.add_child(card["panel"])
		_cards.append(card)
	if not _cards.is_empty():
		(_cards[0]["kind"] as Label).text = "trigger"


func _set_card(i: int, kind: String, token: String, closeness: float) -> void:
	var c: Dictionary = _cards[i]
	var col: Color = KIND_COLORS.get(kind, C_CARD)
	(c["style"] as StyleBoxFlat).border_color = col if kind != "" else C_CARD
	(c["name"] as Label).add_theme_color_override("font_color", col if kind != "" else C_TEXT)
	var label := kind.replace("_", "-")
	if kind == "" and i == 0:
		label = "trigger"
	elif kind != "" and token != "":
		label += " '%s'" % token
	(c["kind"] as Label).text = label if label != "" else " "
	(c["kind"] as Label).add_theme_color_override("font_color", col if kind != "" else C_DIM)
	(c["bar"] as ProgressBar).value = closeness


func _reset_cards() -> void:
	for i in _cards.size():
		_set_card(i, "", "", 0.0)
		(_cards[i]["power"] as Label).text = " "


func _sync_menus() -> void:
	if caster == null:
		return
	var w := caster.get_trigger_word()
	var idx := VoiceCaster.TRIGGER_OPTIONS.find(w)
	if idx < 0:
		idx = VoiceCaster.TRIGGER_OPTIONS.size()
		_trigger_menu.set_item_text(idx, "custom: " + w)
		_custom_edit.text = w
	else:
		_trigger_menu.set_item_text(VoiceCaster.TRIGGER_OPTIONS.size(), "custom...")
	_trigger_menu.select(idx)
	_strict_menu.select(maxi(0, VoiceCaster.STRICTNESS_OPTIONS.find(caster.get_strictness())))
	var note := str(VoiceCaster.TRIGGER_NOTES.get(w, ""))
	if note != "":
		_show_note("not recommended: " + note, C_WARN)
	elif not _custom_row.visible:
		_trigger_note.visible = false


func _show_note(text: String, color: Color) -> void:
	_trigger_note.text = text
	_trigger_note.add_theme_color_override("font_color", color)
	_trigger_note.visible = text != ""


func _on_trigger_selected(i: int) -> void:
	if caster == null:
		return
	if i >= VoiceCaster.TRIGGER_OPTIONS.size():
		_custom_row.visible = true
		_custom_edit.grab_focus()
		return
	_custom_row.visible = false
	_trigger_note.visible = false
	caster.set_trigger_word(VoiceCaster.TRIGGER_OPTIONS[i])


func _on_custom_submitted(text: String) -> void:
	if caster == null:
		return
	var v := caster.set_trigger_word(text)
	if not bool(v["ok"]):
		_show_note(str(v["error"]), C_BAD)
		return
	var warnings: PackedStringArray = v["warnings"]
	_show_note("; ".join(warnings), C_WARN)
	_custom_edit.release_focus()
	_sync_menus()


func _refresh_status() -> void:
	if caster == null:
		_status.text = "no caster attached"
		_status.add_theme_color_override("font_color", C_BAD)
		return
	_status.text = caster.status
	var ok := caster.is_ready()
	_status.add_theme_color_override("font_color", KIND_COLORS["exact"] if ok else C_WARN)


# --- per-frame -----------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not visible or caster == null:
		return
	_gate_info.text = caster.gate.describe()
	if not _gate_slider.has_focus() and absf(_gate_slider.value - caster.gate.min_voice_db) > 0.5:
		_syncing_gate = true
		_gate_slider.value = caster.gate.min_voice_db
		_syncing_gate = false
	_level_hist = _level_hist.slice(1)
	_level_hist.append(_db_to_unit(caster.gate.level_db))
	_voice_hist = _voice_hist.slice(1)
	_voice_hist.append(1 if _voice else 0)
	_scope.queue_redraw()
	_lamp.add_theme_color_override("font_color", KIND_COLORS["exact"] if _voice else C_DIM)
	_lamp.text = "VOICE" if _voice else "  MIC  "
	_refresh_status()
	if Engine.get_frames_drawn() % 30 == 0:
		_update_stats()


func _draw_scope() -> void:
	var s := _scope.size
	_scope.draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.3))
	var dx := s.x / HISTORY
	for i in HISTORY:
		var h: float = clampf(_level_hist[i], 0.0, 1.0) * s.y
		var col: Color = KIND_COLORS["exact"] if _voice_hist[i] else C_DIM
		_scope.draw_rect(Rect2(i * dx, s.y - h, maxf(dx - 1.0, 1.0), h), col)
	if caster != null:
		# dB scale: the min-voice threshold (yellow) and the learned noise floor (grey).
		var ty := s.y * (1.0 - _db_to_unit(caster.gate.min_voice_db))
		_scope.draw_line(Vector2(0, ty), Vector2(s.x, ty), Color(C_WARN, 0.9), 1.0)
		var fy := s.y * (1.0 - _db_to_unit(SpeechGate.db(caster.gate.noise_floor)))
		_scope.draw_line(Vector2(0, fy), Vector2(s.x, fy), Color(C_DIM, 0.6), 1.0)


## Level graph scale: -70 dBFS at the bottom, -10 dBFS at the top.
static func _db_to_unit(v: float) -> float:
	return SpeechGate.db_to_unit(v)


# --- caster events -------------------------------------------------------------------

func _on_voice_activity(active: bool) -> void:
	_voice = active
	if active:
		_log("voice")
		_reset_cards()


func _on_heard(text: String, is_final: bool) -> void:
	var typed := caster.last_heard_typed
	_heard.text = ("\"%s\"" % text) if text != "" else "..."
	_heard.add_theme_color_override("font_color", C_TEXT if is_final else C_DIM)
	_heard_tag.text = "  typed" if typed else ("  final" if is_final else "  hearing...")
	var parts: PackedStringArray = PackedStringArray()
	if text != "" and not _cards.is_empty():
		var ex := caster.get_incantation().explain(text)
		for i in mini(ex.size(), _cards.size()):
			_set_card(i, str(ex[i]["kind"]), str(ex[i]["token"]), float(ex[i]["closeness"]))
			if ex[i]["kind"] != "":
				parts.append("%s=%s" % [ex[i]["word"], str(ex[i]["kind"]).replace("_", "-")])
	if is_final or typed:
		_log("%s \"%s\"%s" % ["[color=#ffffff]typed[/color]" if typed else "[color=#ffffff]final[/color]", _esc(text),
			("  -> " + ", ".join(parts)) if not parts.is_empty() else ""])
	elif text != _last_partial_logged:
		_last_partial_logged = text
		_log("partial \"%s\"%s" % [_esc(text), ("  -> " + ", ".join(parts)) if not parts.is_empty() else ""])


func _on_cast(info: Dictionary) -> void:
	_n_casts += 1
	var accidental: bool = info["accidental"]
	if accidental:
		_n_accidental += 1
	var lat: float = info["latency_ms"]
	if lat >= 0.0:
		_latencies.append(lat)
	var sig: Dictionary = info["signals"]
	var pct := int(round(float(info["power"]) * 100.0))
	var label := "%s%s %d%%" % ["ACCIDENTAL " if accidental else "CAST ", str(info["spell"]).to_upper(), pct]
	var col: Color = KIND_COLORS["accidental"] if accidental else KIND_COLORS["cast"]
	_log("[color=#%s][b]%s[/b][/color]  [%s]\n        heard \"%s\"  kinds %s  gap %d ms  %s  score %.2f" % [
		col.to_html(false), label, _esc(str(info["why"])), _esc(str(info["heard"])), str(sig.get("kind", "")),
		int(float(info["gap"]) * 1000.0), ("%d ms after voice stopped" % int(lat)) if lat >= 0.0 else "typed",
		float(info["accidental_score"])])
	for c in _cards:
		if c["word"] == info["spell"]:
			(c["power"] as Label).text = ("ACCIDENTAL %d%%" if accidental else "%d%%") % pct
			(c["power"] as Label).add_theme_color_override("font_color", col)
			(c["style"] as StyleBoxFlat).border_color = Color.WHITE
			if is_inside_tree():
				var panel: Control = c["panel"]
				var tw := create_tween()
				tw.tween_property(panel, "scale", Vector2(1.12, 1.12), 0.08)
				tw.tween_property(panel, "scale", Vector2.ONE, 0.25)
	_update_stats()


func _on_fizzle(heard_text: String, reason: String) -> void:
	_n_fizzle += 1
	_log("[color=#%s][b]fizzle[/b][/color] (%s)  heard \"%s\"" % [KIND_COLORS["fizzle"].to_html(false), reason, _esc(heard_text)])
	_update_stats()


func _on_ignored(spell: String, heard_text: String, reason: String) -> void:
	_n_ignored += 1
	_log("[color=#8890c0]ignored %s (%s)[/color]  heard \"%s\"" % [spell.to_upper(), reason, _esc(heard_text)])
	_update_stats()


func _on_utterance_finished(text: String, outcome: Dictionary, typed: bool) -> void:
	if text.strip_edges() == "":
		return
	var result := outcome_text(outcome)
	var col: Color = C_DIM
	match outcome["kind"]:
		"cast":
			var casts: Array = outcome["casts"]
			col = KIND_COLORS["accidental"] if bool(casts[0]["accidental"]) else KIND_COLORS["cast"]
		"fizzle":
			col = KIND_COLORS["fizzle"]
		_:
			_n_nomatch += 1
			_log("[color=#ffd060]no match[/color] \"%s\"" % _esc(text))
			_update_stats()
	_transcript_rows.append("[color=#6870a0]%s[/color] [color=#ffffff]\"%s\"[/color]%s [color=#%s]-> %s[/color]" % [
		_stamp(), _esc(text), " (typed)" if typed else "", col.to_html(false), result])
	while _transcript_rows.size() > TRANSCRIPT_LINES:
		_transcript_rows.pop_front()
	_transcript.text = "\n".join(PackedStringArray(_transcript_rows))


## "CAST HEAL 92%", "ACCIDENTAL CORN 74%", "fizzle (garbled)" or "no spell".
static func outcome_text(outcome: Dictionary) -> String:
	var parts := PackedStringArray()
	for c in outcome["casts"]:
		parts.append("%s%s %d%%" % ["ACCIDENTAL " if bool(c["accidental"]) else "CAST ", str(c["spell"]).to_upper(),
			int(round(float(c["power"]) * 100.0))])
	for f in outcome["fizzles"]:
		parts.append("fizzle (%s)" % str(f["reason"]))
	if parts.is_empty():
		if not (outcome["ignored"] as Array).is_empty():
			return "ignored (repeat)"
		return "no spell"
	return ", ".join(parts)


func _update_stats() -> void:
	var s := _latencies.duplicate()
	s.sort()
	var med: float = s[s.size() / 2] if s.size() > 0 else 0.0
	var st: Dictionary = caster.get_stats() if caster != null else {}
	_stats.text = "casts %d (accidental %d)  fizzles %d  no-match %d  ignored dupes %d\nmedian latency %d ms   compute %.1f%% of real time" % [
		_n_casts, _n_accidental, _n_fizzle, _n_nomatch, _n_ignored, int(med), 100.0 * float(st.get("rtf", 0.0))]


# --- log -----------------------------------------------------------------------------

func _stamp() -> String:
	return "%6.1f" % ((Time.get_ticks_msec() - _t0) / 1000.0)


func _esc(text: String) -> String:
	return text.replace("[", "[lb]")


func _log(msg: String) -> void:
	_log_box.append_text("[color=#6870a0]%s[/color]  %s\n" % [_stamp(), msg])
	while _log_box.get_paragraph_count() > MAX_LOG_LINES:
		_log_box.remove_paragraph(0)
