class_name GymPanel
extends CanvasLayer
## The test gym's dev panel (`--gym`, docs/design/test-gym.md): a plain Godot panel on the right of the screen (a dev tool,
## not one of the game's trade forms), built at runtime from what GymDev hands it: the heroes (HeroKit), the spell slots'
## pickers, the toggles and actions, the spawn count, a button for every GymSpawns entry (grouped, each group folds), the
## teleports and the hit log. F9 hides it. It only emits; GymDev does the work.

signal spawn_pressed(id: String)
signal hero_pressed(kit: String)
signal slot_picked(slot: int, spell: String)
signal toggled(name: String, on: bool)
signal action_pressed(name: String)
signal count_picked(n: int)
signal goto_pressed(spot: String)

const LAYER := 55                  ## over the HUD (10) and the voice panel (50), under the game's screens (60)
const WIDTH := 380.0
const TOP := 300.0                 ## under the HUD's work order (top right)
const FONT_SIZE := 12
const COLUMNS := 3
const COUNTS: Array[int] = [1, 5, 10]
const TITLES := {"monster": "Monsters", "dummy": "Dummies", "prop": "Props", "hazard": "Hazards", "staff": "Staff",
	"pickup": "Components", "gate": "Gates", "decor": "Decor"}
const FOLDED: Array[String] = ["decor", "prop", "goto"]   ## groups that start folded

var stats_label: Label
var status_label: Label
var _root: PanelContainer
var _hero_buttons := {}           ## kit -> Button
var _toggle_buttons := {}         ## name -> Button
var _count_buttons := {}          ## n -> Button
var _spawn_buttons := {}          ## entry id -> Button
var _slot_options: Array[OptionButton] = []
var _slot_ids: Array[String] = []  ## the pickers' items after the empty one
var _selected := ""


func _init() -> void:
	layer = LAYER
	name = "GymPanel"


## Build it. `entries`: GymSpawns.entries(); `kits`: the heroes; `spells`: what a slot may hold; `toggles`: [[name, label,
## on]]; `actions`: [[name, label]]; `spots`: the teleports' names.
func build(entries: Array[Dictionary], kits: Array[String], spells: Array[String], toggles: Array, actions: Array, spots: Array) -> void:
	_root = PanelContainer.new()
	_root.name = "Root"
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left = -WIDTH - 8.0
	_root.offset_right = -8.0
	_root.offset_top = TOP
	_root.offset_bottom = -8.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var th := Theme.new()
	th.default_font_size = FONT_SIZE
	_root.theme = th
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.08, 0.1, 0.97)
	bg.set_corner_radius_all(4)
	bg.set_content_margin_all(6)
	_root.add_theme_stylebox_override("panel", bg)
	add_child(_root)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "TEST GYM   F9 hide  F2 hero  F3 areas  F4 AI  F8 god\nbutton: spawn at the ring  G / middle-click: at the cursor"
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	box.add_child(title)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	box.add_child(status_label)
	# heroes
	var heroes := _grid(box, "hero", "Hero", kits.size())
	for kit in kits:
		_hero_buttons[kit] = _button(heroes, kit.capitalize(), func() -> void: hero_pressed.emit(kit))
	# spells
	var spells_box := _grid(box, "spells", "Spell slots", 2)
	_slot_ids = spells
	for i in SpellComponents.SLOT_COUNT:
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.add_item("%d: -" % (i + 1))
		for id in spells:
			ob.add_item("%d: %s" % [i + 1, id])
		var slot := i
		ob.item_selected.connect(func(k: int) -> void: slot_picked.emit(slot, "" if k == 0 else _slot_ids[k - 1]))
		spells_box.add_child(ob)
		_slot_options.append(ob)
	# toggles and actions
	var tools := _grid(box, "tools", "Tools", COLUMNS)
	for t: Array in toggles:
		var nm := str(t[0])
		var b := _button(tools, str(t[1]), Callable())
		b.toggle_mode = true
		b.set_meta("label", str(t[1]))
		b.toggled.connect(func(on: bool) -> void: toggled.emit(nm, on))
		_toggle_buttons[nm] = b
		set_toggle(nm, bool(t[2]))
	for a: Array in actions:
		var an := str(a[0])
		_button(tools, str(a[1]), func() -> void: action_pressed.emit(an))
	# the count
	var counts := _grid(box, "count", "Spawn count", COUNTS.size())
	var group := ButtonGroup.new()
	for n in COUNTS:
		var b := _button(counts, "x%d" % n, func() -> void: count_picked.emit(n))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = n == 1
		_count_buttons[n] = b
	# a button per spawn entry, by group
	var grids := {}
	for e in entries:
		var g := str(e["group"])
		if not grids.has(g):
			grids[g] = _grid(box, g, str(TITLES.get(g, g.capitalize())), COLUMNS)
		var id := str(e["id"])
		var b := _button(grids[g], str(e["label"]), func() -> void: spawn_pressed.emit(id))
		if str(e.get("skip", "")) != "":
			b.disabled = true
			b.tooltip_text = "Not spawnable: %s" % e["skip"]
		else:
			b.tooltip_text = id
		_spawn_buttons[id] = b
	# the teleports
	var goto := _grid(box, "goto", "Go to", COLUMNS)
	for s: String in spots:
		_button(goto, s.replace("_", " "), func() -> void: goto_pressed.emit(s))
	# the hit log
	var head := Label.new()
	head.text = "Hit log"
	head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	box.add_child(head)
	stats_label = Label.new()
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	stats_label.add_theme_font_override("font", mono)
	stats_label.add_theme_font_size_override("font_size", 11)
	box.add_child(stats_label)


## A folding section: its header button and the grid under it.
func _grid(box: VBoxContainer, key: String, title: String, columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "Grid_" + key
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	var head := Button.new()
	head.flat = true
	head.focus_mode = Control.FOCUS_NONE
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	grid.visible = not FOLDED.has(key)
	var label := func() -> String: return ("v " if grid.visible else "> ") + title
	head.text = label.call()
	head.pressed.connect(func() -> void:
		grid.visible = not grid.visible
		head.text = label.call())
	box.add_child(head)
	box.add_child(grid)
	return grid


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0.0, 22.0)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	parent.add_child(b)
	return b


## The mouse is over the panel (spawning at the cursor waits for the world).
func is_hovered() -> bool:
	if not visible or _root == null:
		return false
	return _root.get_global_rect().has_point(_root.get_viewport().get_mouse_position())


func set_hero(kit: String) -> void:
	for k: String in _hero_buttons:
		(_hero_buttons[k] as Button).modulate = Color(1.0, 0.85, 0.4) if k == kit else Color.WHITE


func set_toggle(nm: String, on: bool) -> void:
	if _toggle_buttons.has(nm):
		var b: Button = _toggle_buttons[nm]
		b.set_pressed_no_signal(on)
		b.text = "%s: %s" % [b.get_meta("label"), "on" if on else "off"]
		b.modulate = Color(0.6, 1.0, 0.6) if on else Color.WHITE


func set_selected(id: String) -> void:
	if _spawn_buttons.has(_selected):
		(_spawn_buttons[_selected] as Button).modulate = Color.WHITE
	_selected = id
	if _spawn_buttons.has(id):
		(_spawn_buttons[id] as Button).modulate = Color(0.6, 1.0, 0.6)


## Show the hero's slots in the pickers (no signal).
func set_slots(slots: Array[String]) -> void:
	for i in _slot_options.size():
		var id := slots[i] if i < slots.size() else ""
		var k := _slot_ids.find(id) + 1 if id != "" else 0
		if _slot_options[i].selected != k:
			_slot_options[i].select(k)


func spawn_button(id: String) -> Button:
	return _spawn_buttons.get(id)
