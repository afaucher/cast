class_name JobBoard
extends Control
## The dispatch job board, drawn as FORM 12 "Dispatch offers" (scripts/ui/forms/): a header strip and a 3-part
## tear-off set (white / canary / pink) with the SAME fields in the SAME places on every part, so the crew can
## compare across columns: client, site and danger boxes, what happened, an objectives table with $, a
## red-boxed property warning, the contract value and a "Take" line the player signs.
##
## Pick one with the mouse, or Left / Right then Enter (A on a controller): the player's name is written on its
## Take line, and `picked` follows SIGN_HOLD seconds later so the signature is seen. The highlighted offer
## lifts a little and gets a yellow outline. Add it under a Control (Hud.add_overlay) or a CanvasLayer's root
## Control. Emits picked(run), or `back` once the board is voided (void_back(): Esc, through the game; back is VOID,
## form-rules.md §6, FormVoid: a VOID stamp lands on each of the three parts, since leaving drops the whole set).
##
## Under the cards, the CREW strip: the roster (seat, name, character) while hosting a crew (Session, the
## autoload in scripts/net/), or why this job is solo ("Steam not running: solo only"). Opening the board tells
## the lobby the crew is on the board; taking a job says it's on a job. M7: each member is a CrewBadge with their Steam
## avatar (a lettered square without one), the strip names the crew's simulated link when there is one, and with a seat
## free in a Steam crew an "Invite crew (I)" button opens the overlay's invite dialog (Session.invite_crew).
##
## Nothing here is full-screen and opaque except the fallback shade, which only shows while `backdrop_behind` is
## false: the game sets it to true because the garage (MenuBackdrop, the main menu's backdrop) is behind the
## cards, and then only a light vignette sits over it.

signal picked(run: ContractRun)
## The highlighted card changed (the host's board tells the crew which one it is looking at).
signal highlight_changed(index: int)
## The board was voided (Esc, through the game): leave it (a client leaves the crew; a crew's host is asked first).
signal back

const CARD_W := 480.0
const LIFT := 12.0
const PARTS := ["white", "canary", "pink"]
## Seconds the signed card stays up before `picked` (tests set `sign_hold` to 0).
const SIGN_HOLD := 0.6
## One typewriter: every typed value on the card is the same face, weight, size and ribbon.
const TYPE_SIZE := 19
## How the Take line is signed: "pen" (the red grease pencil, a slight tilt) or "stamp" (a red name stamp).
const SIGN_STYLE := "stamp"
const SHADE_OPAQUE := Color(0.06, 0.05, 0.07, 1.0)   ## no backdrop: a plain dark screen
const SHADE_LIGHT := Color(0.03, 0.025, 0.035, 0.22) ## garage behind: a light dim only

var offers: Array[ContractRun] = []
## A client's board in a shared run: the host picks, so keys and clicks do nothing here (the host's highlighted
## card is set from outside with set_highlight). Esc (through the game) leaves the crew.
var read_only := false
## A short line from the crew's last job, written on the side in the red grease pencil (M5: "c1 abandoned the job").
## "" for none. Set before the board enters the tree.
var notice := ""
## True when a 3D backdrop (the garage) is rendered behind the board: the opaque dark shade goes and a light
## vignette stays. Set it any time.
var backdrop_behind := false:
	set(v):
		backdrop_behind = v
		_apply_shade()

var _cards: Array[PaperPanel] = []
var _slots: Array[Control] = []
var _lifts: Dictionary = {}
var _hi := 0
var sign_hold := SIGN_HOLD
var _signing := false
var _sign_lines: Array[SignLine] = []
var _fallback: ColorRect = null
var _lift_tweens: Dictionary = {}
## The crew strip under the cards (hidden when there's nothing to say).
var crew_strip: Label = null
## M7: the crew's badges (avatar and name) above the strip's note, and the invite button.
var crew_badges: HBoxContainer = null
var invite_button: Button = null
## Show the invite button even without a Steam crew (screenshots, tests).
var force_invite := false


func _init(new_offers: Array[ContractRun] = []) -> void:
	offers = new_offers


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = FormTheme.theme()
	# With no 3D backdrop: a plain dark shade, so the cards never float over nothing. With the garage behind
	# (backdrop_behind): only a light dim so the white rules text and the card edges stay readable.
	_fallback = FormTheme.dim_rect(1.0)
	add_child(_fallback)
	_apply_shade()

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 50)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	# Top row: the FORM 12 header strip on the left, the key hints and the house rules on the right.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 26)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var strip := FormSheet.new("12", "Available contracts", "Dispatch offers  ·  3-part set  ·  tear off one", "Board", "%d open" % offers.size(), "white", 36)
	strip.custom_minimum_size = Vector2(840, 0)
	strip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(strip)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if read_only:
		side.add_child(KeyHints.new([["Esc", "void"]]))
	else:
		side.add_child(KeyHints.new([["Left", "Right", "pick"], ["Enter", "take job"], ["Esc", "void"]]))
	var rules := FormTheme.label("LEAVING EARLY ALWAYS WORKS  ·  UNMET OBJECTIVES DO NOT PAY", 18, Color(1, 1, 1, 0.85))
	rules.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	rules.add_theme_constant_override("outline_size", 5)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.custom_minimum_size = Vector2(300, 0)
	side.add_child(rules)
	if read_only:
		var host_note := FormTheme.label("THE HOST PICKS THE JOB", 22, Color(1.0, 0.9, 0.45, 0.95), true)
		host_note.name = "HostPicks"
		host_note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		host_note.add_theme_constant_override("outline_size", 6)
		side.add_child(host_note)
	if notice != "":
		var note := FormTheme.hand(notice, 30, FormTheme.GREASE)
		note.name = "Notice"
		note.add_theme_color_override("font_outline_color", Color(0.96, 0.93, 0.86, 0.9))
		note.add_theme_constant_override("outline_size", 6)
		side.add_child(note)
	top.add_child(side)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	for i in offers.size():
		row.add_child(_make_slot(offers[i], i))

	var badges_row := HBoxContainer.new()
	badges_row.alignment = BoxContainer.ALIGNMENT_CENTER
	badges_row.add_theme_constant_override("separation", 26)
	badges_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(badges_row)
	crew_badges = HBoxContainer.new()
	crew_badges.name = "CrewBadges"
	crew_badges.add_theme_constant_override("separation", 26)
	crew_badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badges_row.add_child(crew_badges)
	invite_button = FormTheme.button("Invite crew  (I)", 20)
	invite_button.name = "InviteCrew"
	invite_button.custom_minimum_size = Vector2(220, 42)
	invite_button.focus_mode = Control.FOCUS_NONE   # (the cards keep the keys; I or a click opens the overlay)
	invite_button.pressed.connect(invite_crew)
	badges_row.add_child(invite_button)
	crew_strip = FormTheme.label("", 20, Color(1, 1, 1, 0.92), true)
	crew_strip.name = "CrewStrip"
	crew_strip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	crew_strip.add_theme_constant_override("outline_size", 5)
	crew_strip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(crew_strip)
	Session.roster_changed.connect(refresh_crew)
	Session.link_changed.connect(refresh_crew.unbind(1))
	if Session.avatars != null:
		Session.avatars.avatar_ready.connect(refresh_crew.unbind(1))
	if not read_only:
		Session.set_crew_state("board")
	refresh_crew()

	_hi = clampi(_hi, 0, maxi(offers.size() - 1, 0))
	_apply_highlight(false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I and invite_button != null and invite_button.visible:
		invite_crew()
		get_viewport().set_input_as_handled()
		return
	if read_only:
		return
	if offers.is_empty():
		return
	if event.is_action_pressed("ui_left") and not (event is InputEventMouse):
		set_highlight((_hi - 1 + offers.size()) % offers.size())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") and not (event is InputEventMouse):
		set_highlight((_hi + 1) % offers.size())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and not event.is_echo() and not (event is InputEventMouse):
		choose(_hi)
		get_viewport().set_input_as_handled()


## Back is VOID: stamp every part of the set, then emit `back`. False while it is already being voided.
func void_back() -> bool:
	return FormVoid.void_and(self, back.emit, _cards)


## Take offer `index` (mouse click or Enter): sign its Take line, then emit `picked` after `sign_hold`.
func choose(index: int) -> void:
	if read_only or _signing:
		return
	if index < 0 or index >= offers.size():
		return
	set_highlight(index)
	if index < _sign_lines.size():
		_sign_lines[index].signature = signer_name()
	Session.set_crew_state("job")
	if sign_hold > 0.0 and is_inside_tree():
		_signing = true
		await get_tree().create_timer(sign_hold).timeout
		_signing = false
		if not is_inside_tree():
			return
	picked.emit(offers[index])


## Who signs: the player's crew / Steam name, else their character's name.
static func signer_name() -> String:
	var n := str(Session.local_entry().get("name", ""))
	return n if n != "" else SteamIdentity.player_name(Session.local_character().capitalize())


## The crew strip: the roster as badges (avatar, seat, name, character) while in a crew, with the open seats, the
## simulated link and the invite button; else why it's solo; else nothing.
func refresh_crew() -> void:
	if crew_strip == null:
		return
	var text := ""
	for c in crew_badges.get_children():
		crew_badges.remove_child(c)
		c.queue_free()
	if Session.online():
		for e: Dictionary in Session.crew():
			var tex: Texture2D = Session.avatars.texture(int(e.get("steam_id", 0))) if Session.avatars != null else null
			crew_badges.add_child(CrewBadge.new(e, tex, int(e["peer"]) == Session.local_id()))
		var notes: PackedStringArray = []
		if Session.roster.size() < NetSession.MAX_CREW:
			notes.append("seats open: friends can Join a crew")
		if Session.link_preset != "off":
			notes.append("simulated link: %s (Settings > Diagnostics)" % Session.link_preset)
		text = "  ·  ".join(notes)
	elif Session.offline_note != "":
		text = Session.offline_note
	crew_strip.text = text
	crew_strip.visible = text != ""
	crew_badges.visible = crew_badges.get_child_count() > 0
	invite_button.visible = force_invite or Session.can_invite()


## "Invite crew": the Steam overlay's invite dialog for this crew's lobby.
func invite_crew() -> void:
	Session.invite_crew()


## The highlighted offer (keyboard / controller / the last one the mouse touched).
func highlighted() -> int:
	return _hi


## Highlight offer `index`: it lifts and gets the yellow outline.
func set_highlight(index: int) -> void:
	if offers.is_empty():
		return
	index = clampi(index, 0, offers.size() - 1)
	if index == _hi and not _cards.is_empty() and _cards[index].outline_color.a > 0.0:
		return
	_hi = index
	_apply_highlight(true)
	highlight_changed.emit(index)


## The shade behind the cards: opaque dark with no 3D backdrop, a light dim when the garage is behind.
func _apply_shade() -> void:
	if _fallback == null:
		return
	_fallback.color = SHADE_LIGHT if backdrop_behind else SHADE_OPAQUE


func _apply_highlight(animate: bool) -> void:
	for i in _cards.size():
		var on := i == _hi
		_cards[i].outline_color = FormTheme.OUTLINE_YELLOW if on else Color(0, 0, 0, 0)
		var to := 1.0 if on else 0.0
		if _lift_tweens.has(i) and (_lift_tweens[i] as Tween).is_valid():
			(_lift_tweens[i] as Tween).kill()
		var from_f: float = float(_lifts.get(i, 0.0))
		if animate and is_inside_tree() and not is_equal_approx(from_f, to):
			var tw := create_tween()
			tw.tween_method(_set_lift.bind(i), from_f, to, 0.09)
			_lift_tweens[i] = tw
		else:
			_set_lift(to, i)


## `f` 0..1: how far the card in slot `i` is lifted. The slot keeps its size; only the card's top margin moves.
func _set_lift(f: float, i: int) -> void:
	_lifts[i] = f
	var slot := _slots[i] as MarginContainer
	slot.add_theme_constant_override("margin_top", int(roundf(LIFT * (1.0 - f))))
	slot.add_theme_constant_override("margin_bottom", int(roundf(LIFT * f)))


# --- Cards ----------------------------------------------------------------------------------

## A slot holding the card: a margin that moves the card up by LIFT when it is highlighted (a Container
## would otherwise reset the card's position). All three slots stretch to the tallest card.
func _make_slot(run: ContractRun, index: int) -> Control:
	var card := _make_card(run, index)
	var slot := MarginContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(card)
	_slots.append(slot)
	_cards.append(card)
	_set_lift(0.0, index)
	return slot


func _make_card(run: ContractRun, index: int) -> PaperPanel:
	var part: String = PARTS[index % PARTS.size()]
	var card := PaperPanel.new(FormTheme.carbon(part))
	card.set_padding(0, 0, 0, 0)
	card.tear_y = 40.0
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			choose(index))
	card.mouse_entered.connect(func() -> void:
		if not read_only:
			set_highlight(index))

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)

	# Stub: the job number (printed "JOB #", the number typed in), above the tear-off line.
	var stub := HBoxContainer.new()
	stub.add_theme_constant_override("separation", 6)
	stub.alignment = BoxContainer.ALIGNMENT_END
	stub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var job_l := FormTheme.label("JOB #", 18, FormTheme.INK, true)
	job_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stub.add_child(job_l)
	var job_n := _typed(run.invoice_number.replace("INV-", ""))
	job_n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stub.add_child(job_n)
	var stub_box := FormTheme.margin(stub, 16, 0, 16, 0)
	stub_box.custom_minimum_size = Vector2(0, 40)
	v.add_child(stub_box)

	# Client.
	var client := _cell()
	client.add_child(_cap("CLIENT"))
	var name_l := _typed(run.client_name)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size = Vector2(CARD_W - 36, 0)
	client.add_child(name_l)
	var who := _typed("%s  ·  %s" % [run.archetype_title(), run.company])
	who.clip_text = true
	who.custom_minimum_size = Vector2(CARD_W - 36, 0)
	client.add_child(who)
	v.add_child(_boxed_cell(client))

	# Site and danger, side by side.
	var two := HBoxContainer.new()
	two.add_theme_constant_override("separation", 0)
	two.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var site := _cell()
	site.add_child(_cap("SITE"))
	site.add_child(_typed("Survival bunker" if run.site_type == "bunker" else "Villain lair"))
	var site_cell := _boxed_cell(site, 0.0, true)
	site_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(site_cell)
	var danger := _cell()
	danger.add_child(_cap("DANGER"))
	var dr := HBoxContainer.new()
	dr.add_theme_constant_override("separation", 10)
	dr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var boxes := DangerBoxes.new()
	boxes.value = run.difficulty_stars()
	dr.add_child(boxes)
	danger.add_child(dr)
	var danger_cell := _boxed_cell(danger, 0.0, false)
	danger_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	two.add_child(danger_cell)
	v.add_child(two)

	# What happened.
	var story := _cell()
	story.add_child(_cap("WHAT HAPPENED"))
	var ev := _typed(str(run.story["event"]), true)
	ev.custom_minimum_size = Vector2(CARD_W - 36, 78)
	story.add_child(ev)
	# "Origin:" is printed; where it is (the room and its floor) is typed in.
	var origin := HBoxContainer.new()
	origin.add_theme_constant_override("separation", 8)
	origin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var origin_cap := FormTheme.small("Origin:", 18)
	origin_cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	origin.add_child(origin_cap)
	origin.add_child(_typed("%s, floor %d" % [str(run.story["origin"]).capitalize(), ContractRun.FLOOR_COUNT]))
	story.add_child(origin)
	v.add_child(_boxed_cell(story))

	# Objectives table.
	var obj := _cell()
	obj.add_child(_cap("OBJECTIVES"))
	for line in run.card_lines():
		obj.add_child(_objective_row(line))
	v.add_child(_boxed_cell(obj))

	# Property warning in a red box.
	var warn_v := VBoxContainer.new()
	warn_v.add_theme_constant_override("separation", 0)
	warn_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warn_v.add_child(FormTheme.label("PROPERTY WARNING", 17, FormTheme.RED, true))
	var wl := _typed(str(ClientArchetype.get_data(run.archetype_id)["warning"]), true)
	wl.custom_minimum_size = Vector2(CARD_W - 70, 66)
	warn_v.add_child(wl)
	var warn := PanelContainer.new()
	warn.add_theme_stylebox_override("panel", FormTheme.box_style(Color(1, 1, 1, 0.0), FormTheme.RED, 2.0, 10.0, 5.0))
	warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warn.add_child(warn_v)
	v.add_child(FormTheme.margin(warn, 16, 8, 16, 4))
	v.add_child(FormTheme.margin(FormTheme.small("Damages are deducted, up to the contract value.", 17), 16, 0, 16, 4))

	# Contract value.
	var total := HBoxContainer.new()
	total.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := FormTheme.label("CONTRACT VALUE", 19, FormTheme.INK, true)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	total.add_child(tl)
	var value_l := _typed(ContractRun.money(run.contract_value))
	value_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	total.add_child(value_l)
	var total_box := FormTheme.margin(total, 16, 4, 16, 4)
	var total_panel := PanelContainer.new()
	var tsb := FormTheme.box_style(Color(0, 0, 0, 0), FormTheme.INK, 0.0, 0.0, 0.0)
	tsb.border_width_top = 3
	total_panel.add_theme_stylebox_override("panel", tsb)
	total_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	total_panel.add_child(total_box)
	v.add_child(total_panel)

	# Signature line: "Take ______", signed with the player's name when taken.
	var sign := HBoxContainer.new()
	sign.add_theme_constant_override("separation", 10)
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var take := FormTheme.label("TAKE", 20, FormTheme.INK, true)
	take.size_flags_vertical = Control.SIZE_SHRINK_END
	sign.add_child(take)
	var line := SignLine.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.custom_minimum_size = Vector2(0, 34)
	line.style = SIGN_STYLE
	sign.add_child(line)
	_sign_lines.append(line)
	v.add_child(FormTheme.margin(sign, 16, 4, 16, 12))
	return card


## A typed value from the board's one typewriter (wrapping for running text).
func _typed(text: String, wrap: bool = false) -> Label:
	var l := FormTheme.typed(text, TYPE_SIZE, FormTheme.TYPED, true)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _cell() -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A ruled cell: padding and a 1.5 unit ink rule below (and a rule on the left for a right-hand cell).
func _boxed_cell(inner: Control, min_h: float = 0.0, right_rule: bool = false) -> Control:
	var p := PanelContainer.new()
	var sb := FormTheme.box_style(Color(0, 0, 0, 0), FormTheme.INK, 0.0, 16.0, 7.0)
	sb.border_width_bottom = 2
	if right_rule:
		sb.border_width_right = 2
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if min_h > 0.0:
		p.custom_minimum_size = Vector2(0, min_h)
	p.add_child(inner)
	return p


func _cap(text: String) -> Label:
	return FormTheme.label(text, 17, FormTheme.INK, true)


func _objective_row(line: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _typed(str(line["label"]))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var pay := ContractRun.money(int(line["pay"]))
	if bool(line["each"]):
		pay += " ea"
	var pl := _typed(pay)
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pl)
	var p := PanelContainer.new()
	var sb := FormTheme.box_style(Color(0, 0, 0, 0), FormTheme.FAINT, 0.0, 0.0, 1.0)
	sb.border_width_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	return p


## Five printed boxes, `value` of them ticked in the red grease pencil (the same tick as every other form): the
## danger rating.
class DangerBoxes:
	extends Control
	var value := 0
	var count := 5
	## A tick never lands quite the same twice: a small fixed wobble per box (x, y, size).
	const WOBBLE := [Vector3(0.0, 0.5, 0.0), Vector3(1.0, -0.5, 1.0), Vector3(-0.5, 1.0, -0.5), Vector3(0.5, 0.0, 1.5), Vector3(-1.0, 0.5, 0.0)]

	func _init() -> void:
		custom_minimum_size = Vector2(count * 32.0, 30.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		for i in count:
			var r := Rect2(i * 32.0 + 2.0, 8.0, 20.0, 20.0)
			draw_rect(r, FormTheme.FIELD_FILL)
			draw_rect(r, FormTheme.INK, false, 2.0)
		for i in mini(value, count):
			var w: Vector3 = WOBBLE[i % WOBBLE.size()]
			var b := Rect2(i * 32.0 + 4.0 + w.x, 9.0 + w.y, 17.0 + w.z, 17.0 + w.z)
			FormTheme.draw_tick(self, b, FormTheme.GREASE, 3.5)


## The ruled line you sign on; `signature` is written on it in the red grease pencil, like every mark the player
## makes on a form.
class SignLine:
	extends Control
	var signature := "":
		set(v):
			signature = v
			queue_redraw()
	var style := "pen"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_line(Vector2(0, size.y - 3.0), Vector2(size.x, size.y - 3.0), FormTheme.INK, 2.0)
		if signature == "":
			return
		if style == "stamp":
			_draw_stamp()
			return
		# A hand signature runs a little uphill.
		var f := FormTheme.hand_font()
		draw_set_transform(Vector2(12.0, size.y - 7.0), deg_to_rad(-4.0))
		draw_string(f, Vector2.ZERO, signature, HORIZONTAL_ALIGNMENT_LEFT, size.x - 12.0, 34, FormTheme.GREASE)
		draw_set_transform(Vector2.ZERO)

	## A red rubber name stamp sitting on the line, double-bordered and a touch crooked.
	func _draw_stamp() -> void:
		var f := FormTheme.stamp_font()
		var fs := 22
		var text := signature.to_upper()
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(Vector2(-tw * 0.5 - 14.0, -f.get_height(fs) * 0.5 - 6.0), Vector2(tw + 28.0, f.get_height(fs) + 12.0))
		var ink := Color(FormTheme.RED, 0.85)
		draw_set_transform(Vector2(box.size.x * 0.5 + 18.0, size.y - 14.0), deg_to_rad(-3.0))
		draw_rect(box, ink, false, 3.0)
		draw_rect(box.grow(-5.0), ink, false, 1.5)
		draw_string(f, Vector2(-tw * 0.5, f.get_ascent(fs) - f.get_height(fs) * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		draw_set_transform(Vector2.ZERO)
