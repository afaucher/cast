extends Control
## Standalone voice test scene (scenes/voice_lab.tscn): say an incantation into
## the mic (or type it) and watch the four spell cards light up with their power.
## The debug panel is docked on the right (F1 hides it): level graph, the
## recognizer's raw text, match cards, event log and stats. Run:
##   godot --path . res://scenes/voice_lab.tscn      (or .\run.ps1, scene arg)
## Without a model it still works for typed input ("no model, typed input only").

const SPELLS := {
	"heal": {"label": "HEAL", "color": Color(0.35, 0.90, 0.50)},
	"fireball": {"label": "FIREBALL", "color": Color(1.00, 0.55, 0.20)},
	"armor": {"label": "ARMOR", "color": Color(0.45, 0.65, 1.00)},
	"corn": {"label": "CORN", "color": Color(1.00, 0.88, 0.30)},
}
const GLOW_SECONDS := 1.6
const C_BG := Color(0.07, 0.08, 0.16)
const C_TEXT := Color(0.95, 0.95, 1.0)
const C_DIM := Color(0.62, 0.65, 0.85)

var caster: VoiceCaster
var panel: VoiceDebugPanel
var _cards := {}          # id -> {panel, style, name, power, bar, glow}
var _hint: Label
var _heard: Label
var _heard_tag: Label
var _input: LineEdit


func _ready() -> void:
	InputSetup.ensure_actions()
	_build_ui()
	caster = VoiceCaster.new()
	add_child(caster)
	panel = VoiceDebugPanel.new()
	add_child(panel)
	panel.attach(caster)
	caster.cast_detail.connect(_on_cast)
	caster.spell_fizzled.connect(_on_fizzle)
	caster.heard.connect(_on_heard)
	caster.trigger_word_changed.connect(func(_w: String) -> void: _update_hint())
	caster.strictness_changed.connect(func(_m: String) -> void: _update_hint())
	var ok := caster.start(PackedStringArray(SPELLS.keys()))
	panel.log_game("voice lab started: %s" % caster.status)
	_update_hint()
	if not ok:
		_hint.text += "\n(%s)" % caster.status
	_input.grab_focus()


func _process(delta: float) -> void:
	for id in _cards:
		var c: Dictionary = _cards[id]
		var g: float = maxf(0.0, float(c["glow"]) - delta / GLOW_SECONDS)
		c["glow"] = g
		var col: Color = SPELLS[id]["color"]
		(c["style"] as StyleBoxFlat).bg_color = Color(0.14, 0.16, 0.30).lerp(col.darkened(0.25), g)
		(c["style"] as StyleBoxFlat).border_color = Color(0.14, 0.16, 0.30).lerp(Color.WHITE, g)
		if g <= 0.0:
			(c["power"] as Label).text = " "
			(c["bar"] as ProgressBar).value = 0.0


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 30
	root.offset_top = 22
	root.offset_right = -(VoiceDebugPanel.PANEL_WIDTH + 30)
	root.offset_bottom = -22
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	root.add_child(_label("Voice lab", 30))
	_hint = _label("", 20, C_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size = Vector2(0, 190)
	root.add_child(row)
	for id in SPELLS:
		row.add_child(_make_card(id))

	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(_label("HEARD", 14, C_DIM))
	_heard_tag = _label("", 14, Color(1.0, 0.82, 0.30))
	head.add_child(_heard_tag)
	_heard = _label("...", 40, C_DIM)
	_heard.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_heard.custom_minimum_size = Vector2(0, 110)
	root.add_child(_heard)

	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 10)
	root.add_child(type_row)
	type_row.add_child(_label("type it:", 18, C_DIM))
	_input = LineEdit.new()
	_input.placeholder_text = "e.g. cast heal   (Enter)"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(_on_typed)
	type_row.add_child(_input)


func _label(text: String, size: int, color: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _make_card(id: String) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.16, 0.30)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(4)
	sb.border_color = sb.bg_color
	p.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(box)
	var name_l := _label(str(SPELLS[id]["label"]), 28)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_l)
	var power := _label(" ", 30)
	power.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(power)
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	box.add_child(bar)
	_cards[id] = {"panel": p, "style": sb, "name": name_l, "power": power, "bar": bar, "glow": 0.0}
	return p


func _update_hint() -> void:
	var t := caster.get_trigger_word().to_upper()
	_hint.text = "Say \"%s HEAL\", \"%s FIREBALL\", \"%s ARMOR\" or \"%s CORN\".  Mode: %s.  Pick the trigger word and mode in the panel on the right (F1 hides it)." % [
		t, t, t, t, caster.get_strictness()]


func _on_cast(info: Dictionary) -> void:
	var id: String = info["spell"]
	if not _cards.has(id):
		return
	var c: Dictionary = _cards[id]
	var pct := int(round(float(info["power"]) * 100.0))
	c["glow"] = 1.0
	(c["power"] as Label).text = ("acc. %d%%" if bool(info["accidental"]) else "%d%%") % pct
	(c["bar"] as ProgressBar).value = float(info["power"])


func _on_fizzle(heard_text: String, reason: String) -> void:
	_heard_tag.text = "  fizzle: %s" % reason


func _on_heard(text: String, is_final: bool) -> void:
	_heard.text = ("\"%s\"" % text) if text != "" else "..."
	_heard.add_theme_color_override("font_color", C_TEXT if is_final else C_DIM)
	_heard_tag.text = "  typed" if caster.last_heard_typed else ("  final" if is_final else "  hearing...")


func _on_typed(text: String) -> void:
	if text.strip_edges() == "":
		return
	caster.inject_text(text)
	_input.clear()
	_input.grab_focus()
