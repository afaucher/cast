class_name PersonnelFile
extends FormSheet
## FORM 31 Personnel file (green carbon: the crew's paperwork): the card beside the main menu's work order that says who
## the player is clocking in as (the character select, user 2026-10-19). `show_hero(id)` types it up for a hero; the main
## menu calls it whenever the pick changes (a click on a hero in the garage, or the NAME line below).
##
## Printed captions, typed values, nothing that explains the game or names a key (form-rules.md). Every number comes from
## the hero's kit (HeroKit) or, for the secondaries that live on Hero, Hero's constants: nothing here is a copy of them.
## The box bars put the three heroes on one scale per stat (the best of the three fills all ten boxes), typed X's in
## printed boxes, so they compare at a glance. The deadpan one-line roles are the only per-hero text kept here.
##
## Keyboard and controller: the NAME line is in the menu's focus chain (the yellow band and the red tick, like any row);
## Left / Right on it, Enter or a click step to the next hero (`step`). The keys go in the menu's key strip, off the paper.

## The role line under the name: the office's one-line summary of each hero.
const ROLES := {
	"wick": "Ranged. Climbs. Bruises easily.",
	"gasket": "Demolition. Big hits. No range.",
	"rebar": "Tank. Immovable. Not a closer.",
}
const FORM_NO := "31"
const TITLE := "Personnel file"
const BOXES := 10
const TYPE_SIZE := 19
const CAPTION_SIZE := 16
const CAPTION_W := 100.0
const ROW_H := 27.0
const PAD_H := 18.0

## Left / Right on the NAME line (-1 / +1), Enter or a click on it (+1).
signal step(dir: int)

var hero_id := ""
## The NAME line: focusable (it joins the menu's chain).
var name_row: NameLine
var role_label: Label
## stat key -> {value: Label, bar: StatBoxes}
var rows := {}

var _width := 560.0


func _init(sheet_w: float = 560.0) -> void:
	super(FORM_NO, TITLE, "Cast  ·  Licensed Budget Sorcery", "Copy", "CREW", "green", 28)
	_width = sheet_w
	custom_minimum_size = Vector2(sheet_w, 0)
	name = "PersonnelFile"
	header.form_no_label.add_theme_font_size_override("font_size", 28)
	name_row = NameLine.new()
	name_row.name = "NameLine"
	name_row.pressed.connect(func() -> void: step.emit(1))
	name_row.stepped.connect(func(dir: int) -> void: step.emit(dir))
	body.add_child(name_row)
	role_label = _row("role", "Role", false)
	_row("hp", "HP", true)
	_row("primary", "Primary", true)
	_row("speed", "Speed", true)
	_row("secondary", "Secondary", false)
	_row("climb", "Climbing", true)
	_row("weight", "Weight", true)


## Type the card up for `id` (wick, gasket, rebar). False (and nothing changes) for a hero without a kit.
func show_hero(id: String) -> bool:
	var kit := HeroKit.get_kit(id)
	if kit == null:
		return false
	hero_id = kit.id
	name_row.value = kit.display_name.to_upper()
	header.copy_value.text = "CREW"
	var f := facts(kit)
	for key: String in rows:
		var r: Dictionary = rows[key]
		(r["value"] as Label).text = str(f.get(key, ""))
		if r["bar"] != null:
			(r["bar"] as StatBoxes).filled = int(bars(kit.id).get(key, 0))
	return true


## The typed values for a kit, by row key (the card's text; tests read it too).
static func facts(kit: HeroKit) -> Dictionary:
	var out := {}
	out["role"] = str(ROLES.get(kit.id, ""))
	out["hp"] = "%d" % roundi(kit.max_hp)
	out["primary"] = "%s, %s dmg" % [kit.primary_name, _num(kit.melee_damage)]
	out["speed"] = "every %s s" % _num(kit.melee_cooldown)
	out["secondary"] = _secondary(kit)
	if kit.can_climb:
		out["climb"] = "+2 at %d%% pace" % roundi(kit.climb_speed_factor * 100.0)
	else:
		out["climb"] = "+1 steps only"
	out["weight"] = "Immovable" if kit.shove_mult <= 0.0 else "Shoved x%s" % _num(kit.shove_mult)
	return out


static func _secondary(kit: HeroKit) -> String:
	match kit.secondary_kind:
		"bowl":
			return "Bowl, %s dmg, every %s s" % [_num(Hero.BOWL_DAMAGE), _num(Hero.BOWL_COOLDOWN)]
		"spin":
			return "Spin, %s dmg, every %s s" % [_num(Hero.SPIN_DAMAGE), _num(Hero.SPIN_COOLDOWN)]
		"arrow":
			return "Arrow, %s-%s dmg, every %s s" % [_num(float(kit.arrow["tap_damage"])), _num(float(kit.arrow["draw_damage"])),
				_num(float(kit.arrow["tap_cooldown"]))]
	return kit.secondary_kind.capitalize()


## How many of the ten boxes each stat fills for `id`, on one scale across the crew: the best hero fills all ten.
##   hp: max HP; primary: the primary's damage; speed: swings per second; climb: the +2 climb pace (0 when it can't);
##   weight: how little a shove moves it (immovable fills all ten; the lightest still gets one box).
static func bars(id: String) -> Dictionary:
	var kits: Array[HeroKit] = []
	for k in HeroKit.ids():
		kits.append(HeroKit.get_kit(k))
	var kit := HeroKit.get_kit(id)
	if kit == null:
		return {}
	var top := {"hp": 0.0, "primary": 0.0, "speed": 0.0, "climb": 0.0, "shove": 0.0}
	for k in kits:
		top["hp"] = maxf(top["hp"], k.max_hp)
		top["primary"] = maxf(top["primary"], k.melee_damage)
		top["speed"] = maxf(top["speed"], 1.0 / maxf(k.melee_cooldown, 0.01))
		top["climb"] = maxf(top["climb"], _climb(k))
		top["shove"] = maxf(top["shove"], k.shove_mult)
	return {
		"hp": _boxes(kit.max_hp, top["hp"]),
		"primary": _boxes(kit.melee_damage, top["primary"]),
		"speed": _boxes(1.0 / maxf(kit.melee_cooldown, 0.01), top["speed"]),
		"climb": _boxes(_climb(kit), top["climb"]),
		"weight": maxi(1, BOXES - _boxes(kit.shove_mult, top["shove"])) if float(top["shove"]) > 0.0 else BOXES,
	}


static func _climb(k: HeroKit) -> float:
	return k.climb_speed_factor if k.can_climb else 0.0


static func _boxes(v: float, top: float) -> int:
	return clampi(roundi(float(BOXES) * v / top), 0, BOXES) if top > 0.0 else 0


## "15", "0.8", "0.65", "1.3": a number as the office types it.
static func _num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return "%d" % roundi(v)
	var s := "%.2f" % v
	return s.trim_suffix("0") if s.ends_with("0") else s


## Every typed label on the card (tests: what is typed), the name line's value included.
func typed_text() -> PackedStringArray:
	var out := PackedStringArray([name_row.value, header.copy_value.text])
	for key: String in rows:
		out.append((rows[key]["value"] as Label).text)
	return out


func _row(key: String, caption: String, with_bar: bool) -> Label:
	var row := HBoxContainer.new()
	row.name = "Row_" + key
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0, ROW_H)
	var cap := FormTheme.label(caption.to_upper(), CAPTION_SIZE, FormTheme.INK, true)
	cap.custom_minimum_size = Vector2(CAPTION_W, 0)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cap)
	var val := FormTheme.typed("", TYPE_SIZE)
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.clip_text = true
	val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(val)
	var bar: StatBoxes = null
	if with_bar:
		bar = StatBoxes.new()
		bar.name = "Bar"
		row.add_child(bar)
	rows[key] = {"value": val, "bar": bar}
	body.add_child(_ruled(row))
	return val


func _ruled(inner: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := FormTheme.box_style(Color(0, 0, 0, 0), FormTheme.INK, 0.0, PAD_H, 1.0)
	sb.border_width_bottom = 1
	sb.border_color = FormTheme.FAINT
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(inner)
	return p


## A row of printed boxes with typed X's in the first `filled` (the typist x-ing out a scale), BOXES long.
class StatBoxes extends Control:
	const BOX := 15.0
	const GAP := 3.0

	var filled := 0:
		set(v):
			filled = clampi(v, 0, PersonnelFile.BOXES)
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _get_minimum_size() -> Vector2:
		return Vector2(PersonnelFile.BOXES * (BOX + GAP) - GAP, BOX + 2.0)

	func _draw() -> void:
		var y := (size.y - BOX) * 0.5
		for i in PersonnelFile.BOXES:
			var r := Rect2(i * (BOX + GAP), y, BOX, BOX)
			draw_rect(r, FormTheme.FIELD_FILL)
			draw_rect(r, FormTheme.INK, false, 1.5)
			if i < filled:
				var x := r.grow(-1.0)
				draw_line(x.position, x.end, FormTheme.TYPED, 2.4, true)
				draw_line(Vector2(x.end.x, x.position.y), Vector2(x.position.x, x.end.y), FormTheme.TYPED, 2.4, true)


## The NAME line: the printed caption and the typed name, a Button so it can take focus (band and tick) and be clicked.
class NameLine extends Button:
	signal stepped(dir: int)

	var value := "":
		set(v):
			value = v
			queue_redraw()

	func _init() -> void:
		FormTheme.make_blank(self)
		custom_minimum_size = Vector2(300.0, PersonnelFile.ROW_H + 6.0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		mouse_entered.connect(func() -> void:
			if is_inside_tree() and is_visible_in_tree():
				grab_focus())

	func _gui_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_right", true):
			stepped.emit(-1 if event.is_action("ui_left") else 1)
			accept_event()

	func _draw() -> void:
		var s := size
		if has_focus():
			FormTheme.draw_band(self, Rect2(-6, 3, s.x + 12, s.y - 6))
			FormTheme.draw_tick(self, Rect2(s.x - 44.0, (s.y - 22.0) * 0.5, 22.0, 22.0))
		draw_line(Vector2(0, s.y - 1.0), Vector2(s.x, s.y - 1.0), FormTheme.INK, 2.0)
		var lf := FormTheme.label_font(true)
		draw_string(lf, Vector2(PersonnelFile.PAD_H, FormTheme.baseline(lf, PersonnelFile.CAPTION_SIZE, s.y)), "NAME", HORIZONTAL_ALIGNMENT_LEFT, -1,
			PersonnelFile.CAPTION_SIZE, FormTheme.INK)
		var tf := FormTheme.typed_font()
		draw_string(tf, Vector2(PersonnelFile.PAD_H + PersonnelFile.CAPTION_W + 8.0, FormTheme.baseline(tf, PersonnelFile.TYPE_SIZE, s.y)), value,
			HORIZONTAL_ALIGNMENT_LEFT, -1, PersonnelFile.TYPE_SIZE, FormTheme.TYPED)
