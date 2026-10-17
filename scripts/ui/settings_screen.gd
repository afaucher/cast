class_name SettingsScreen
extends Control
## The menu's Settings screen: master volume, fullscreen / windowed, window resolution, and whether the voice
## debug panel is open when a contract starts. Every change is applied at once and saved through GameSettings
## (user://settings.cfg, section "game"). Emits `back` for the Back button (the menu also handles Esc).

signal back

## "" = GameSettings.path. Tests point this at a temp file.
var settings_path := ""
## Put changes into effect (audio bus, window). Tests turn it off.
var apply_live := true

var settings: Dictionary = {}
var volume_slider: HSlider
var volume_value: Label
var fullscreen_check: CheckButton
var resolution_menu: OptionButton
var panel_check: CheckButton
var back_button: Button
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


func _commit(key: String, value: Variant) -> void:
	settings[key] = value
	GameSettings.save_settings({key: value}, settings_path)


func _apply_window() -> void:
	if apply_live:
		GameSettings.apply_window(bool(settings["fullscreen"]), GameSettings.parse_resolution(str(settings["resolution"])))


# --- UI ----------------------------------------------------------------------------------------------

func _build() -> void:
	add_child(MenuStyle.dim_rect(0.62))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := MenuStyle.panel(MenuStyle.AMBER, 40, 30)
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)

	v.add_child(MenuStyle.label("SETTINGS", 38, MenuStyle.AMBER_HOT))
	v.add_child(MenuStyle.label("Changes apply at once and are saved.", 17, MenuStyle.DIM))
	v.add_child(MenuStyle.gap(4))

	volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.step = 1.0
	volume_slider.custom_minimum_size = Vector2(300, 30)
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	MenuStyle.style_slider(volume_slider)
	volume_slider.value_changed.connect(func(value: float) -> void:
		if not _syncing:
			set_master_volume(value / 100.0))
	volume_value = MenuStyle.label("", 20, MenuStyle.TEXT)
	volume_value.custom_minimum_size = Vector2(64, 0)
	volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var vol_row := _row("Master volume", volume_slider)
	vol_row.add_child(volume_value)
	v.add_child(vol_row)

	fullscreen_check = CheckButton.new()
	fullscreen_check.text = "Fullscreen"
	MenuStyle.style_control(fullscreen_check)
	fullscreen_check.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			set_fullscreen(on))
	fullscreen_state = MenuStyle.label("", 18, MenuStyle.DIM, true)
	var display_row := _row("Display", fullscreen_check)
	display_row.add_child(fullscreen_state)
	v.add_child(display_row)

	resolution_menu = OptionButton.new()
	for res in GameSettings.RESOLUTIONS:
		resolution_menu.add_item("%d x %d" % [res.x, res.y])
	MenuStyle.style_control(resolution_menu)
	resolution_menu.custom_minimum_size = Vector2(220, 0)
	resolution_menu.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			set_resolution(GameSettings.RESOLUTIONS[i]))
	var res_row := _row("Window size", resolution_menu)
	res_row.add_child(MenuStyle.label("  (windowed only)", 15, MenuStyle.DIM))
	v.add_child(res_row)

	panel_check = CheckButton.new()
	panel_check.text = "Voice debug panel visible at start"
	MenuStyle.style_control(panel_check)
	panel_check.toggled.connect(func(on: bool) -> void:
		if not _syncing:
			set_voice_panel_visible(on))
	panel_state = MenuStyle.label("", 18, MenuStyle.DIM, true)
	var game_row := _row("In game", panel_check)
	game_row.add_child(panel_state)
	v.add_child(game_row)
	v.add_child(MenuStyle.wrapped("The panel shows what the microphone hears and what each cast did. F1 shows or hides it during play.", 15))

	v.add_child(MenuStyle.gap(8))
	back_button = MenuStyle.small_button("Back  (Esc)")
	back_button.custom_minimum_size = Vector2(200, 46)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back_button.pressed.connect(func() -> void: back.emit())
	v.add_child(back_button)


func _row(title: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := MenuStyle.label(title, 20, MenuStyle.DIM)
	l.custom_minimum_size = Vector2(190, 0)
	row.add_child(l)
	row.add_child(control)
	return row


func _sync() -> void:
	_syncing = true
	volume_slider.value = roundf(float(settings["master_volume"]) * 100.0)
	volume_value.text = "%d%%" % roundi(volume_slider.value)
	fullscreen_check.button_pressed = bool(settings["fullscreen"])
	resolution_menu.select(maxi(0, GameSettings.RESOLUTIONS.find(GameSettings.parse_resolution(str(settings["resolution"])))))
	resolution_menu.disabled = bool(settings["fullscreen"])
	panel_check.button_pressed = bool(settings["voice_panel_visible"])
	_state(fullscreen_state, bool(settings["fullscreen"]), "FULLSCREEN", "WINDOWED")
	_state(panel_state, bool(settings["voice_panel_visible"]), "ON", "OFF")
	_syncing = false


func _state(l: Label, on: bool, on_text: String, off_text: String) -> void:
	l.text = on_text if on else off_text
	l.add_theme_color_override("font_color", MenuStyle.GOOD if on else MenuStyle.DIM)
