class_name Hud
extends CanvasLayer
## The in-game HUD, built in code: player HP bar, ally mini bars, two spell
## cards (name, incantation, key, cooldown sweep, charges, an empty-slot look and a HELD
## highlight), toasts for casts / fizzles / pickups / out-of-component, the swap prompt, a mic
## level meter, a big center message, and an optional typed-spell console (stand-in for voice;
## Enter focuses it).
##
## Pure presentation: it reads Hero state each frame and is told about voice
## events through show_cast / show_fizzle / show_unknown_spell / set_mic_level.

signal console_submitted(text: String)

const TOAST_TIME := 1.8
const CARD_SIZE := Vector2(210, 104)
const BAR_COLOR_PLAYER := Color(0.3, 0.85, 0.5)
const BAR_COLOR_ALLY := Color(0.4, 0.7, 0.95)
const COLOR_DANGER := Color(1.0, 0.45, 0.4)
const COLOR_NEUTRAL := Color(0.8, 0.8, 0.85)

var player: Hero = null
var allies: Array[Hero] = []
var console: LineEdit = null
var trigger_word := "cast"   ## spoken keyword shown on the cards ("say: PICKLE HEAL")

var _root: Control
var _player_bar: HudBar
var _player_name: Label
var _ally_box: VBoxContainer
var _ally_bars: Array[HudBar] = []
var _cards: Array[SpellCard] = []
var _card_box: HBoxContainer
var _toast: Label
var _prompt: Label
var _toast_tween: Tween
var _center: Label
var _center_tween: Tween
var _mic_bar: HudBar
var _mic_target := 0.0
var _console_enabled := false


func _init() -> void:
	layer = 10
	name = "Hud"


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_player_panel()
	_build_ally_panel()
	_build_cards()
	_build_toasts()
	_build_prompt()
	_build_mic()


## Show this hero's HP and spell slots; list the allies' mini bars.
func bind(new_player: Hero, new_allies: Array[Hero]) -> void:
	player = new_player
	allies = new_allies
	_player_name.text = player.display_name
	for b in _ally_bars:
		b.get_parent().queue_free()
	_ally_bars.clear()
	for a in allies:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = a.display_name
		lbl.custom_minimum_size = Vector2(70, 0)
		_style_label(lbl, 16)
		row.add_child(lbl)
		var bar := HudBar.new()
		bar.custom_minimum_size = Vector2(150, 14)
		bar.fill = BAR_COLOR_ALLY
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar)
		_ally_box.add_child(row)
		_ally_bars.append(bar)
	for c in _cards:
		c.queue_free()
	_cards.clear()
	for i in SpellComponents.SLOT_COUNT:
		var card := SpellCard.new()
		card.setup(self, player, i)
		card.custom_minimum_size = CARD_SIZE
		_card_box.add_child(card)
		_cards.append(card)
	if not player.spell_cast.is_connected(_on_spell_cast):
		player.spell_cast.connect(_on_spell_cast)
	if not player.component_collected.is_connected(_on_component_collected):
		player.component_collected.connect(_on_component_collected)


func _process(delta: float) -> void:
	if player != null and is_instance_valid(player):
		_player_bar.set_value(player.hp / player.max_hp, "%d / %d" % [int(ceilf(player.hp)), int(player.max_hp)])
	for i in _ally_bars.size():
		if i < allies.size() and is_instance_valid(allies[i]):
			var a := allies[i]
			_ally_bars[i].fill = BAR_COLOR_ALLY if not a.dead else Color(0.4, 0.4, 0.42)
			_ally_bars[i].set_value(a.hp / a.max_hp, "DOWN" if a.dead else "")
	_mic_bar.set_value(lerpf(_mic_bar.value, _mic_target, clampf(18.0 * delta, 0.0, 1.0)), "")
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if _console_enabled and console != null and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			console.grab_focus()
			get_viewport().set_input_as_handled()


# --- Public API -------------------------------------------------------------------------

## Keep the HUD clear of a side panel docked on the right (0 = full width).
func set_right_inset(px: float) -> void:
	_root.offset_right = -px


## Add a full-screen Control (e.g. the SpellPicker) on top of the HUD.
func add_overlay(c: Control) -> void:
	_root.add_child(c)


## Change the spoken trigger word; the spell cards re-render ("say: PICKLE HEAL").
func set_trigger_word(word: String) -> void:
	trigger_word = word.strip_edges() if word.strip_edges() != "" else "cast"
	for c in _cards:
		c.queue_redraw()


## "HEAL 92%" in the spell's color.
func show_cast(id: String, power: float) -> void:
	_show_toast("%s %d%%" % [SpellBook.spell_name(id).to_upper(), int(roundf(power * 100.0))], SpellBook.color_of(id).lightened(0.15))


## Heard something spell-ish but too garbled.
func show_fizzle(heard: String, reason: String = "") -> void:
	var t := "Fizzle! heard \"%s\"" % heard if heard != "" else "Fizzle!"
	if reason != "":
		t += " (%s)" % reason
	_show_toast(t, Color(0.75, 0.75, 0.8))


func show_unknown_spell(id: String) -> void:
	_show_toast("You don't know %s!" % SpellBook.spell_name(id), COLOR_DANGER)


## "Out of Ember horn": the spell has no charges left (the cast fizzled, no cooldown was spent).
func show_out_of_component(id: String) -> void:
	_show_toast("Out of %s" % SpellBook.component_name(id), COLOR_DANGER)


## "+3 Ember horn" in the spell's color; `slot` >= 0 adds where it went when it filled a new slot.
func show_pickup(id: String, amount: int, slot: int = -1) -> void:
	var t := "+%d %s" % [amount, SpellBook.component_name(id)]
	if slot >= 0:
		t += "  (%s, slot %d)" % [SpellBook.spell_name(id), slot + 1]
	_show_toast(t, SpellBook.color_of(id).lightened(0.2))


## The text of the swap prompt for the pickup the player stands by, or "" when there is none:
## "F: swap Fireball into slot 2 (held)".
func swap_prompt_text() -> String:
	if player == null or not is_instance_valid(player) or player.dead:
		return ""
	var cand := player.swap_candidate
	if cand == null or not is_instance_valid(cand) or cand.is_queued_for_deletion():
		return ""
	return "F: swap %s into slot %d (held)" % [SpellBook.spell_name(cand.spell_id), player.held_slot + 1]


func show_cooldown(id: String, seconds_left: float) -> void:
	_show_toast("%s is recharging (%.1fs)" % [SpellBook.spell_name(id), seconds_left], COLOR_NEUTRAL)


func show_message(text: String, color: Color = Color.WHITE) -> void:
	_show_toast(text, color)


func set_mic_level(v: float) -> void:
	_mic_target = clampf(v, 0.0, 1.0)


## Big center text: "You died", "Exit reached". hold <= 0 keeps it until clear_center().
func show_center(text: String, color: Color = Color.WHITE, hold: float = 0.0) -> void:
	if _center_tween:
		_center_tween.kill()
	_center.text = text
	_center.modulate = color
	_center.visible = true
	_center.scale = Vector2(1.4, 1.4)
	_center_tween = create_tween()
	_center_tween.tween_property(_center, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if hold > 0.0:
		_center_tween.tween_interval(hold)
		_center_tween.tween_property(_center, "modulate:a", 0.0, 0.5)
		_center_tween.tween_callback(func() -> void: _center.visible = false)


func clear_center() -> void:
	if _center_tween:
		_center_tween.kill()
	_center.visible = false


## Add the typed-spell box (bottom right). Enter focuses it; submit emits console_submitted.
func enable_console() -> void:
	if console != null:
		return
	_console_enabled = true
	console = LineEdit.new()
	console.placeholder_text = "type a spell (Enter): heal / cast fireball"
	console.custom_minimum_size = Vector2(300, 32)
	console.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	console.offset_left = -320
	console.offset_right = -16
	console.offset_top = -92
	console.offset_bottom = -60
	console.text_submitted.connect(func(t: String) -> void:
		console.clear()
		console.release_focus()
		console_submitted.emit(t))
	console.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			console.release_focus())
	_root.add_child(console)


# --- Callbacks ---------------------------------------------------------------------------

func _on_spell_cast(id: String, _power: float) -> void:
	for c in _cards:
		if c.spell_id() == id:
			c.flash = 1.0


func _on_component_collected(id: String, amount: int, kind: String) -> void:
	show_pickup(id, amount, player.spell_slots.find(id) if kind == "filled" else -1)
	for c in _cards:
		if c.spell_id() == id:
			c.flash = 1.0


func _update_prompt() -> void:
	if _prompt == null:
		return
	var t := swap_prompt_text()
	_prompt.visible = t != ""
	if t != "":
		_prompt.text = t
		_prompt.modulate = SpellBook.color_of(player.swap_candidate.spell_id).lerp(Color.WHITE, 0.75)


# --- Building ----------------------------------------------------------------------------

func _build_player_panel() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 20
	box.offset_top = -76
	box.offset_right = 340
	box.offset_bottom = -20
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_player_name = Label.new()
	_player_name.text = "Hero"
	_style_label(_player_name, 20)
	box.add_child(_player_name)
	_player_bar = HudBar.new()
	_player_bar.custom_minimum_size = Vector2(320, 26)
	_player_bar.fill = BAR_COLOR_PLAYER
	_player_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_player_bar)


func _build_ally_panel() -> void:
	_ally_box = VBoxContainer.new()
	_ally_box.position = Vector2(20, 20)
	_ally_box.add_theme_constant_override("separation", 6)
	_ally_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_ally_box)


func _build_cards() -> void:
	_card_box = HBoxContainer.new()
	_card_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_card_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card_box.offset_bottom = -20
	_card_box.add_theme_constant_override("separation", 12)
	_card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_card_box)


func _build_prompt() -> void:
	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt.offset_bottom = -140
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_label(_prompt, 28)
	_prompt.add_theme_constant_override("outline_size", 10)
	_prompt.visible = false
	_root.add_child(_prompt)


func _build_toasts() -> void:
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 70
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_label(_toast, 40)
	_toast.modulate.a = 0.0
	_root.add_child(_toast)
	_center = Label.new()
	_center.set_anchors_preset(Control.PRESET_CENTER)
	_center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center.grow_vertical = Control.GROW_DIRECTION_BOTH
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_label(_center, 84)
	_center.visible = false
	_root.add_child(_center)
	_center.resized.connect(func() -> void: _center.pivot_offset = _center.size * 0.5)
	_toast.resized.connect(func() -> void: _toast.pivot_offset = _toast.size * 0.5)


func _build_mic() -> void:
	var lbl := Label.new()
	lbl.text = "MIC"
	_style_label(lbl, 14)
	lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	lbl.offset_left = -64
	lbl.offset_top = -50
	lbl.offset_right = -16
	lbl.offset_bottom = -30
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(lbl)
	_mic_bar = HudBar.new()
	_mic_bar.fill = Color(0.95, 0.75, 0.25)
	_mic_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_mic_bar.offset_left = -320
	_mic_bar.offset_right = -70
	_mic_bar.offset_top = -44
	_mic_bar.offset_bottom = -32
	_mic_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_mic_bar)


func _show_toast(text: String, color: Color) -> void:
	if _toast_tween:
		_toast_tween.kill()
	_toast.text = text
	_toast.modulate = color
	_toast.scale = Vector2(1.25, 1.25)
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(TOAST_TIME)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


static func _style_label(l: Label, size: int) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", maxi(3, size / 6))


# --- Custom controls ------------------------------------------------------------------------

## A flat HP-style bar with an optional centered text.
class HudBar extends Control:
	var value := 1.0
	var fill := Color(0.3, 0.85, 0.5)
	var text := ""

	func set_value(v: float, label: String = "") -> void:
		v = clampf(v, 0.0, 1.0)
		if is_equal_approx(v, value) and label == text:
			return
		value = v
		text = label
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * value, size.y)), fill)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.4), false, 1.5)
		if text != "":
			var fs := int(size.y * 0.62)
			var font := ThemeDB.fallback_font
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(font, Vector2((size.x - w) * 0.5, size.y * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
			draw_string(font, Vector2((size.x - w) * 0.5, size.y * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## One spell slot: key, name, "say: CAST X", the component and its charges, a radial cooldown sweep.
## An empty slot is a dim dashed outline; the held slot is highlighted with a bright frame and tag.
class SpellCard extends Control:
	const HELD_COLOR := Color(1.0, 0.88, 0.4)
	var slot := 0
	var key_text := ""
	var hero: Hero = null
	var hud: Hud = null
	var flash := 0.0

	func setup(owner_hud: Hud, h: Hero, slot_index: int) -> void:
		hud = owner_hud
		hero = h
		slot = slot_index
		key_text = str(slot_index + 1)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	## The spell in this slot ("" when empty).
	func spell_id() -> String:
		return hero.slot_spell(slot) if hero and is_instance_valid(hero) else ""

	func is_held() -> bool:
		return hero != null and is_instance_valid(hero) and hero.held_slot == slot and spell_id() != ""

	func _process(delta: float) -> void:
		flash = maxf(0.0, flash - delta * 3.0)
		queue_redraw()

	func _draw() -> void:
		var id := spell_id()
		var font := ThemeDB.fallback_font
		var rect := Rect2(Vector2.ZERO, size)
		if id == "":
			_draw_empty(font, rect)
			return
		var col := SpellBook.color_of(id)
		var held := is_held()
		draw_rect(rect, Color(0.12, 0.11, 0.09, 0.92) if held else Color(0.07, 0.08, 0.12, 0.88))
		draw_rect(Rect2(0, 0, 8, size.y), col)
		if flash > 0.0:
			draw_rect(rect, Color(col.r, col.g, col.b, 0.45 * flash))
		# Key badge and name
		draw_rect(Rect2(20, 14, 26, 26), Color(1, 1, 1, 0.14))
		draw_string(font, Vector2(20, 34), key_text, HORIZONTAL_ALIGNMENT_CENTER, 26, 21, Color.WHITE)
		var nm := SpellBook.spell_name(id).to_upper()
		draw_string_outline(font, Vector2(54, 36), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 4, Color(0, 0, 0, 0.7))
		draw_string(font, Vector2(54, 36), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, col.lightened(0.2))
		draw_string(font, Vector2(20, 60), "say:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.65, 0.65, 0.72))
		draw_string(font, Vector2(48, 60), SpellBook.incantation(id, hud.trigger_word if hud else "cast"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		# Component and charges
		var charges := hero.charges_of(id)
		draw_rect(Rect2(20, 77, 9, 9), col)
		draw_string(font, Vector2(34, 87), SpellBook.component_name(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.78, 0.78, 0.84))
		var ctext := "x%d" % charges if charges > 0 else "OUT"
		var ccol := Color(1.0, 0.4, 0.35) if charges <= 0 else (Color(1.0, 0.8, 0.3) if charges <= 1 else Color.WHITE)
		var cw := font.get_string_size(ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		var cat := Vector2(size.x - cw - 12.0, 92.0)
		draw_string_outline(font, cat, ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 5, Color(0, 0, 0, 0.9))
		draw_string(font, cat, ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ccol)
		# Cooldown sweep: dark pie covering the remaining fraction, clockwise from 12 o'clock.
		var total := hero.cooldown_total(id)
		var left := hero.cooldown_left(id)
		if left > 0.0 and total > 0.0:
			var frac := clampf(left / total, 0.0, 1.0)
			var c := size * 0.5
			var pts := PackedVector2Array([c])
			var start := -PI * 0.5 + TAU * (1.0 - frac)
			var end := -PI * 0.5 + TAU
			var steps := maxi(2, int(40.0 * frac))
			for i in steps + 1:
				var a := lerpf(start, end, float(i) / steps)
				pts.append(c + Vector2(cos(a), sin(a)) * size.length())
			draw_colored_polygon(pts, Color(0, 0, 0, 0.66))
			var s := "%.1f" % left
			var fs := 40
			var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			# Centered on the card (the long names and the charges leave no free corner).
			var at := Vector2((size.x - w) * 0.5, size.y * 0.5 + fs * 0.36)
			draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.9))
			draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		if held:
			draw_rect(rect, HELD_COLOR, false, 4.0)
			var tag := "HELD"
			var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_rect(Rect2(size.x - tw - 14.0, 0, tw + 14.0, 15), HELD_COLOR)
			draw_string(font, Vector2(size.x - tw - 7.0, 12), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.12, 0.09, 0.02))
		else:
			draw_rect(rect, Color(col.r, col.g, col.b, 0.7), false, 2.0)

	## An empty slot: dim, a dashed outline, the key and a hint.
	func _draw_empty(font: Font, rect: Rect2) -> void:
		draw_rect(rect, Color(0.05, 0.05, 0.08, 0.55))
		var edge := Color(1, 1, 1, 0.25)
		var dash := 10.0
		var x := 1.0
		while x < size.x - 1.0:
			var x2 := minf(x + dash, size.x - 1.0)
			draw_line(Vector2(x, 1.5), Vector2(x2, 1.5), edge, 2.0)
			draw_line(Vector2(x, size.y - 1.5), Vector2(x2, size.y - 1.5), edge, 2.0)
			x += dash * 2.0
		var y := 1.0
		while y < size.y - 1.0:
			var y2 := minf(y + dash, size.y - 1.0)
			draw_line(Vector2(1.5, y), Vector2(1.5, y2), edge, 2.0)
			draw_line(Vector2(size.x - 1.5, y), Vector2(size.x - 1.5, y2), edge, 2.0)
			y += dash * 2.0
		draw_rect(Rect2(20, 14, 26, 26), Color(1, 1, 1, 0.07))
		draw_string(font, Vector2(20, 34), key_text, HORIZONTAL_ALIGNMENT_CENTER, 26, 21, Color(1, 1, 1, 0.4))
		draw_string(font, Vector2(54, 36), "EMPTY", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.3))
		draw_string(font, Vector2(20, 66), "walk over a component", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.3))
		draw_string(font, Vector2(20, 84), "to fill this slot", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.3))
