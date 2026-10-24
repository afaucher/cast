class_name Hud
extends CanvasLayer
## The in-game HUD, built in code: the party frame top left (PartyFrame: a portrait, name, HP bar and order chip per crew
## member, and the employees following you), two spell
## cards (name, incantation, key, cooldown sweep, charges, an empty-slot look and a HELD
## highlight), toasts for casts / fizzles / pickups / out-of-component, a mic
## level meter, a big center message, and an optional typed-spell console (stand-in for voice;
## Enter focuses it).
##
## Pure presentation: it reads Hero state each frame and is told about voice
## events through show_cast / show_fizzle / show_unknown_spell.

signal console_submitted(text: String)

const TOAST_TIME := 1.8
const CARD_SIZE := Vector2(210, 104)
const CARD_BOTTOM_GAP := 20.0     ## the spell cards sit this far above the screen bottom
const TOAST_GAP := 12.0           ## the toast floats this far above the cards, so it never meets the dispatch banner at the top
const TOAST_HEIGHT := 56.0
const COLOR_DANGER := Color(1.0, 0.45, 0.4)
const COLOR_NEUTRAL := Color(0.8, 0.8, 0.85)
## The party frame lists the employees following you under the crew (a row each, "+N more" past PartyFrame.MAX_FOLLOWERS).
const SHOW_FOLLOWERS := true

## What this run uses (the constant above; the dev flag --party-followers overrides it for screenshots).
static var show_followers := SHOW_FOLLOWERS

var player: Hero = null
var allies: Array[Hero] = []
var console: LineEdit = null
var trigger_word := "cast"   ## spoken keyword shown on the cards ("say: PICKLE HEAL")

var _root: Control
var party: PartyFrame              ## top left: the crew (yours first, biggest) and the employees following you
var _cards: Array[SpellCard] = []
var _card_box: HBoxContainer
var _toast: Label
var _toast_tween: Tween
var _console_enabled := false


func _init() -> void:
	layer = 10
	name = "Hud"


func _ready() -> void:
	add_to_group("hud")
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	party = PartyFrame.new()
	party.show_followers = show_followers
	party.position = Vector2(16, 14)
	_root.add_child(party)
	_build_cards()
	_build_toasts()


## Show this hero's HP and spell slots; the party frame lists the crew.
func bind(new_player: Hero, new_allies: Array[Hero]) -> void:
	player = new_player
	allies = new_allies
	party.bind(player, allies)
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


func _unhandled_input(event: InputEvent) -> void:
	if _console_enabled and console != null and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			console.visible = true   # hidden until Enter (user, 2026-10-18); it hides again when it loses focus
			console.grab_focus()
			get_viewport().set_input_as_handled()


# --- Public API -------------------------------------------------------------------------

## Keep the HUD clear of a side panel docked on the right (0 = full width).
func set_right_inset(px: float) -> void:
	_root.offset_right = -px


## The screen rectangle (canvas pixels) the spell cards cover; an empty Rect2 before bind(). The use prompt keeps clear of it.
func cards_rect() -> Rect2:
	if _card_box == null or _cards.is_empty():
		return Rect2()
	return _card_box.get_global_rect()



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


## "You have no Ember horn": the spell is not slotted (never picked up, or its last component was spent).
func show_unknown_spell(id: String) -> void:
	_show_toast("You have no %s" % SpellBook.component_name(id), COLOR_DANGER)


## "You have no Ember horn": the spell has no charges left (the cast fizzled, no cooldown was spent).
func show_out_of_component(id: String) -> void:
	_show_toast("You have no %s" % SpellBook.component_name(id), COLOR_DANGER)


## "+3 Ember horn" in the spell's color; `slot` >= 0 adds where it went when it filled a new slot.
func show_pickup(id: String, amount: int, slot: int = -1) -> void:
	var t := "+%d %s" % [amount, SpellBook.component_name(id)]
	if slot >= 0:
		t += "  (%s, slot %d)" % [SpellBook.spell_name(id), slot + 1]
	_show_toast(t, SpellBook.color_of(id).lightened(0.2))


func show_cooldown(id: String, seconds_left: float) -> void:
	_show_toast("%s is recharging (%.1fs)" % [SpellBook.spell_name(id), seconds_left], COLOR_NEUTRAL)


func show_message(text: String, color: Color = Color.WHITE) -> void:
	_show_toast(text, color)


## Add the typed-spell box (bottom right). It stays hidden until Enter shows and focuses it; submit, Esc or a click
## away hides it again. Submit emits console_submitted.
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
	console.visible = false
	console.focus_exited.connect(func() -> void: console.visible = false)
	console.text_submitted.connect(func(t: String) -> void:
		console.clear()
		console.release_focus()
		console_submitted.emit(t))
	console.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			console.release_focus()
			console.accept_event())   # Esc leaves the box; it must not also open the pause menu
	_root.add_child(console)


# --- Callbacks ---------------------------------------------------------------------------

## Blink slot `i`'s card (an empty slot pressed: it flashes red instead of a line of text).
func flash_slot(i: int) -> void:
	if i >= 0 and i < _cards.size():
		_cards[i].flash = 1.0


func _on_spell_cast(id: String, _power: float) -> void:
	for c in _cards:
		if c.spell_id() == id:
			c.flash = 1.0


func _on_component_collected(id: String, amount: int, kind: String) -> void:
	show_pickup(id, amount, player.spell_slots.find(id) if kind == "filled" else -1)
	for c in _cards:
		if c.spell_id() == id:
			c.flash = 1.0


# --- Building ----------------------------------------------------------------------------

func _build_cards() -> void:
	_card_box = HBoxContainer.new()
	_card_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_card_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card_box.offset_bottom = -CARD_BOTTOM_GAP
	_card_box.add_theme_constant_override("separation", 12)
	_card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_card_box)


func _build_toasts() -> void:
	_toast = Label.new()
	# Just above the spell cards at the bottom centre. (It used to sit at the top centre, behind the dispatch banner.)
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_bottom = -(CARD_BOTTOM_GAP + CARD_SIZE.y + TOAST_GAP)
	_toast.offset_top = _toast.offset_bottom - TOAST_HEIGHT
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_label(_toast, 40)
	_toast.modulate.a = 0.0
	_root.add_child(_toast)
	_toast.resized.connect(func() -> void: _toast.pivot_offset = _toast.size * 0.5)


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
		if flash > 0.0:
			draw_rect(rect, Color(1.0, 0.35, 0.3, 0.4 * flash))
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
