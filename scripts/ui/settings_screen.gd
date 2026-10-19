class_name SettingsScreen
extends Control
## The menu's Settings screen (FORM 3, goldenrod, scripts/ui/forms/): the volumes (master, Effects, Paperwork, Spell
## feedback: one audio bus each, GameSettings.BUS_VOLUMES), fullscreen / windowed, window resolution, whether the voice
## debug panel is open when a contract starts, and (4. Diagnostics, M7) "Simulate a long link": off / coast / rough, the
## lag the host's crew plays under (playtests of the netcode; the host's choice is broadcast to the crew). Every change is
## applied at once and saved through GameSettings (user://settings.cfg, section "game"). Emits `back` once the form is
## voided (void_back(): the Back button, or Esc through the menu; FormVoid).

signal back

const LINK_TEXT := {"off": "Off", "coast": "Coast to coast", "rough": "Rough evening"}
## The volume rows, in order: setting -> printed caption.
const VOLUME_ROWS := {"master_volume": "Master volume", "sfx_volume": "Effects", "ui_volume": "Paperwork",
	"voice_feedback_volume": "Spell feedback"}

## "" = GameSettings.path. Tests point this at a temp file.
var settings_path := ""
## Put changes into effect (audio bus, window). Tests turn it off.
var apply_live := true

var settings: Dictionary = {}
var volume_slider: BoxScale          ## the master volume (volume_sliders["master_volume"])
var volume_value: Label
## Every volume row's scale and its typed value, by setting (VOLUME_ROWS).
var volume_sliders: Dictionary = {}
var volume_values: Dictionary = {}
var fullscreen_check: FormCheck
var resolution_menu: OptionButton
var panel_check: FormCheck
var link_menu: OptionButton
var link_state: Label
var back_button: Button
var sheet: FormSheet
var fullscreen_state: Label
var panel_state: Label

var _syncing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Sfx.play("paper")   # the form slides in
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings = GameSettings.load_settings(settings_path)
	_build()
	_sync()


func first_focus() -> Control:
	return volume_slider


## Back is VOID (form-rules.md §6): stamp the sheet, then emit `back`. False while it is already being voided.
func void_back() -> bool:
	return FormVoid.void_and(self, back.emit, sheet)


# --- API (the controls call these too) -----------------------------------------------------------

func set_master_volume(v: float) -> void:
	set_volume("master_volume", v)


## One of the volumes (a GameSettings.BUS_VOLUMES key), 0..1: saved, and its bus set at once.
func set_volume(key: String, v: float) -> void:
	if not GameSettings.BUS_VOLUMES.has(key):
		return
	_commit(key, clampf(v, 0.0, 1.0))
	if apply_live:
		GameSettings.apply_bus_volume(GameSettings.BUS_VOLUMES[key], float(settings[key]))
	_sync()


func set_fullscreen(on: bool) -> void:
	_commit("fullscreen", on)
	_apply_window()
	_sync()


func set_resolution(res: Vector2i) -> void:
	_commit("resolution", GameSettings.resolution_text(res))
	_apply_window()
	_sync()


func set_voice_panel_visible(on: bool) -> void:
	_commit("voice_panel_visible", on)
	_sync()


## Diagnostics: the crew's simulated link ("off", "coast", "rough"). A host with a crew open applies it at once.
func set_link_sim(preset: String) -> void:
	if not GameSettings.LINK_PRESETS.has(preset):
		return
	_commit("link_sim", preset)
	if apply_live and Session.online() and Session.hosting:
		Session.set_link(preset)
	_sync()


func _commit(key: String, value: Variant) -> void:
	settings[key] = value
	GameSettings.save_settings({key: value}, settings_path)


func _apply_window() -> void:
	if apply_live:
		GameSettings.apply_window(bool(settings["fullscreen"]), GameSettings.parse_resolution(str(settings["resolution"])))


# --- UI ----------------------------------------------------------------------------------------------

func _build() -> void:
	theme = FormTheme.theme()
	add_child(FormTheme.dim_rect(0.5))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 58)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 60)   # (the key hints)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	sheet = FormSheet.new("3", "Options", "Equipment settings  ·  filed at once", "Saved", "at once", "gold", 44)
	sheet.custom_minimum_size = Vector2(960, 0)
	sheet.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(sheet)
	var body := sheet.body

	# 1. Audio
	var audio := FormSection.new("1. Audio")
	body.add_child(audio)
	for key: String in VOLUME_ROWS:
		var bar := BoxScale.new()
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.step = 1.0
		bar.value_changed.connect(func(value: float) -> void:
			if not _syncing:
				set_volume(key, value / 100.0))
		var value_label := FormTheme.typed("", 24)
		value_label.custom_minimum_size = Vector2(84, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var vol_row := FormField.new(str(VOLUME_ROWS[key]), bar, 250.0, 46.0)   # (compact: four of them)
		vol_row.add(value_label, false, false)
		audio.box.add_child(vol_row)
		volume_sliders[key] = bar
		volume_values[key] = value_label
	volume_slider = volume_sliders["master_volume"]
	volume_value = volume_values["master_volume"]

	# 2. Display
	var display := FormSection.new("2. Display")
	body.add_child(display)
	fullscreen_check = FormCheck.new("Fullscreen")
	fullscreen_check.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			set_fullscreen(on))
	fullscreen_state = FormTheme.label("", 20, FormTheme.INK, true)
	fullscreen_state.custom_minimum_size = Vector2(118, 0)
	var display_row := FormField.new("Display", fullscreen_check)
	display_row.add(fullscreen_state, false, false)

	# The window size shares the display row (the form has four volume rows above it).
	resolution_menu = OptionButton.new()
	for res in GameSettings.RESOLUTIONS:
		resolution_menu.add_item("%d x %d" % [res.x, res.y])
	resolution_menu.custom_minimum_size = Vector2(230, 48)
	resolution_menu.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			set_resolution(GameSettings.RESOLUTIONS[i]))
	display_row.add(FormTheme.label("WINDOW", 18, FormTheme.INK), false, false)
	display_row.add(resolution_menu)
	display.box.add_child(display_row)

	# 3. Dispatch rig
	var rig := FormSection.new("3. Dispatch rig")
	body.add_child(rig)
	panel_check = FormCheck.new("F1 toggles it in play")
	panel_check.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			set_voice_panel_visible(on))
	panel_state = FormTheme.label("", 20, FormTheme.INK, true)
	var game_row := FormField.new("Debug panel at start", panel_check)
	game_row.add(panel_state, false, false)
	rig.box.add_child(game_row)
	rig.box.add_child(FormTheme.small("The panel shows what the microphone hears and what each cast did. Cast word, strictness and the mic line live on FORM 7: Rig calibration (main menu, Voice setup).", 18))

	# 4. Diagnostics (M7): the link simulator, for playtesting the netcode.
	var diag := FormSection.new("4. Diagnostics")
	body.add_child(diag)
	link_menu = OptionButton.new()
	for p in GameSettings.LINK_PRESETS:
		link_menu.add_item(LINK_TEXT[p])
	link_menu.custom_minimum_size = Vector2(280, 48)
	link_menu.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			set_link_sim(GameSettings.LINK_PRESETS[i]))
	link_state = FormTheme.label("", 20, FormTheme.INK, true)
	var link_row := FormField.new("Simulate a long link", link_menu)
	link_row.add(link_state, false, false)
	diag.box.add_child(link_row)
	diag.box.add_child(FormTheme.small("When you host, your whole crew plays as if the line were this long (every machine delays and drops what it receives). Coast: 45 ms each way, 1.5% loss. Rough: 80 ms, 4%. Solo: no effect.", 18))

	# Footer
	var foot := FormSection.new("", true)
	body.add_child(foot)
	var foot_row := HBoxContainer.new()
	foot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var note := FormTheme.label("CHANGES APPLY AT ONCE AND ARE SAVED.", 18)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot_row.add_child(note)
	back_button = FormTheme.button("Back  (Esc)")
	back_button.custom_minimum_size = Vector2(220, 50)
	back_button.pressed.connect(void_back)
	foot_row.add_child(back_button)
	foot.box.add_child(foot_row)

	var keys := KeyHints.new([["Up", "Down", "field"], ["Left", "Right", "adjust"], ["Esc", "back"]])
	keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	keys.offset_left = 58.0
	keys.offset_top = -52.0
	keys.offset_bottom = -20.0
	add_child(keys)

	var order: Array = volume_sliders.values()
	order.append_array([fullscreen_check, resolution_menu, panel_check, link_menu, back_button])
	FormTheme.chain(order)


func _sync() -> void:
	_syncing = true
	for key: String in volume_sliders:
		var bar: BoxScale = volume_sliders[key]
		bar.value = roundf(float(settings[key]) * 100.0)
		(volume_values[key] as Label).text = "%d%%" % roundi(bar.value)
	fullscreen_check.button_pressed = bool(settings["fullscreen"])
	resolution_menu.select(maxi(0, GameSettings.RESOLUTIONS.find(GameSettings.parse_resolution(str(settings["resolution"])))))
	resolution_menu.disabled = bool(settings["fullscreen"])
	panel_check.button_pressed = bool(settings["voice_panel_visible"])
	link_menu.select(maxi(0, GameSettings.LINK_PRESETS.find(str(settings["link_sim"]))))
	link_state.text = "CREW-WIDE" if str(settings["link_sim"]) != "off" else "REAL LINE"
	link_state.add_theme_color_override("font_color", FormTheme.RED if str(settings["link_sim"]) != "off" else FormTheme.INK)
	_state(fullscreen_state, bool(settings["fullscreen"]), "FULLSCREEN", "WINDOWED")
	_state(panel_state, bool(settings["voice_panel_visible"]), "ON", "OFF")
	_syncing = false


func _state(l: Label, on: bool, on_text: String, off_text: String) -> void:
	l.text = on_text if on else off_text
	l.add_theme_color_override("font_color", FormTheme.GREEN_INK if on else FormTheme.INK)
