class_name SettingsScreen
extends Control
## The menu's Settings screen (FORM 3, goldenrod, scripts/ui/forms/): master volume, fullscreen / windowed, window resolution, whether the voice
## debug panel is open when a contract starts, and (4. Diagnostics, M7) "Simulate a long link": off / coast / rough, the
## lag the host's crew plays under (playtests of the netcode; the host's choice is broadcast to the crew). Every change is
## applied at once and saved through GameSettings (user://settings.cfg, section "game"). Emits `back` once the form is
## voided (void_back(): the Back button, or Esc through the menu; FormVoid).

signal back

const LINK_TEXT := {"off": "Off", "coast": "Coast to coast", "rough": "Rough evening"}

## "" = GameSettings.path. Tests point this at a temp file.
var settings_path := ""
## Put changes into effect (audio bus, window). Tests turn it off.
var apply_live := true

var settings: Dictionary = {}
var volume_slider: BoxScale
var volume_value: Label
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
	_commit("master_volume", clampf(v, 0.0, 1.0))
	if apply_live:
		GameSettings.apply_volume(float(settings["master_volume"]))
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
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
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
	volume_slider = BoxScale.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.step = 1.0
	volume_slider.value_changed.connect(func(value: float) -> void:
		if not _syncing:
			set_master_volume(value / 100.0))
	volume_value = FormTheme.typed("", 24)
	volume_value.custom_minimum_size = Vector2(84, 0)
	volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var vol_row := FormField.new("Master volume", volume_slider)
	vol_row.add(volume_value, false, false)
	audio.box.add_child(vol_row)

	# 2. Display
	var display := FormSection.new("2. Display")
	body.add_child(display)
	fullscreen_check = FormCheck.new("Fullscreen")
	fullscreen_check.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			set_fullscreen(on))
	fullscreen_state = FormTheme.label("", 20, FormTheme.INK, true)
	var display_row := FormField.new("Display", fullscreen_check)
	display_row.add(fullscreen_state, false, false)
	display.box.add_child(display_row)

	resolution_menu = OptionButton.new()
	for res in GameSettings.RESOLUTIONS:
		resolution_menu.add_item("%d x %d" % [res.x, res.y])
	resolution_menu.custom_minimum_size = Vector2(280, 48)
	resolution_menu.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			set_resolution(GameSettings.RESOLUTIONS[i]))
	var res_row := FormField.new("Window size", resolution_menu)
	res_row.add(FormTheme.label("(WINDOWED ONLY)", 18, FormTheme.INK), false, false)
	display.box.add_child(res_row)

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

	var keys := KeyHints.new([["Up", "Down", "field"], ["Left", "Right", "adjust"], ["Esc", "void"]])
	keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	keys.offset_left = 58.0
	keys.offset_top = -52.0
	keys.offset_bottom = -20.0
	add_child(keys)

	FormTheme.chain([volume_slider, fullscreen_check, resolution_menu, panel_check, link_menu, back_button])


func _sync() -> void:
	_syncing = true
	volume_slider.value = roundf(float(settings["master_volume"]) * 100.0)
	volume_value.text = "%d%%" % roundi(volume_slider.value)
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
