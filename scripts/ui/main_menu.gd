class_name MainMenu
extends Node
## The main menu (scenes/main_menu.tscn), the default boot target (see Boot.route). A living background
## (MenuBackdrop: the crew idling in a slate hall with a hellgate glowing in the distance) behind a work
## order (FORM 27-B, scripts/ui/forms/) clipped to a clipboard on the left third, with four rows: Start (the game scene, i.e. the contract job board), Voice setup (VoiceSetupScreen: live mic
## test), Settings (SettingsScreen) and Quit. Keyboard (arrows / Tab / Enter) and mouse; Esc backs out of a
## sub-screen. Everything is built in code.
##
## Dev flags (after `--`; see Boot): --no-mic, --menu-screen main|voice|settings, --menu-shot <png>
## [--menu-after s], --menu-say <text>.

const GAME_SCRIPT := preload("res://scripts/app/game.gd")
const TAGLINE := "Licensed Budget Sorcery"

signal screen_changed(screen_name: String)

## Open the microphone in the voice setup. Tests turn it off (also --no-mic).
var use_mic := true
## Where settings are read and written; "" = GameSettings.path (user://settings.cfg).
var settings_path := ""
## Build the 3D background. Tests that only poke buttons can turn it off.
var backdrop_enabled := true
## Settings changes take effect at once (audio bus, window). Tests turn it off.
var apply_settings_live := true
## Test seams: how the menu changes scene / quits. Empty = the scene tree does it.
var change_scene := Callable()
var quit_game := Callable()

var screen := "main"
var backdrop: MenuBackdrop
var ui: CanvasLayer
var main_panel: Control
var start_button: Button
var voice_button: Button
var settings_button: Button
var quit_button: Button
var clipboard: FormClipboard
var build_label: Label
var voice_screen: VoiceSetupScreen = null
var settings_screen: SettingsScreen = null

var _opened_from: Button = null


func _ready() -> void:
	InputSetup.ensure_actions()
	var args := OS.get_cmdline_user_args()
	if args.has("--no-mic"):
		use_mic = false
	if backdrop_enabled:
		backdrop = MenuBackdrop.new()
		backdrop.name = "Backdrop"
		add_child(backdrop)
	ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	_build_main()
	var wanted := Boot.arg_value(args, "--menu-screen")
	if wanted != "" and wanted != "main":
		show_screen(wanted)
	else:
		_focus_start.call_deferred()
	if backdrop_enabled and DisplayServer.get_name() != "headless":
		_fade_in()
	var shot := Boot.arg_value(args, "--menu-shot")
	if shot != "":
		var after := Boot.arg_value(args, "--menu-after")
		_shot_later(shot, float(after) if after != "" else 1.5, Boot.arg_value(args, "--menu-say"))


func _unhandled_input(event: InputEvent) -> void:
	if screen != "main" and event.is_action_pressed("pause"):
		show_screen("main")
		get_viewport().set_input_as_handled()


# --- Actions ----------------------------------------------------------------------------------------

## Start: a fresh run of the game scene (which opens on the contract job board).
func start_game() -> void:
	GAME_SCRIPT.reset_flow()
	_go(Boot.GAME_SCENE)


func quit() -> void:
	if quit_game.is_valid():
		quit_game.call()
	else:
		get_tree().quit()


func _go(path: String) -> void:
	if change_scene.is_valid():
		change_scene.call(path)
	else:
		get_tree().change_scene_to_file.call_deferred(path)


## "main", "voice" or "settings". Sub-screens replace the title and buttons over the backdrop.
func show_screen(which: String) -> void:
	_close_sub_screens()
	match which:
		"voice":
			voice_screen = VoiceSetupScreen.new()
			voice_screen.use_mic = use_mic
			voice_screen.settings_path = _settings_file()
			voice_screen.back.connect(func() -> void: show_screen("main"))
			ui.add_child(voice_screen)
			screen = "voice"
			_grab.call_deferred(voice_screen.first_focus())
		"settings":
			settings_screen = SettingsScreen.new()
			settings_screen.settings_path = _settings_file()
			settings_screen.apply_live = apply_settings_live
			settings_screen.back.connect(func() -> void: show_screen("main"))
			ui.add_child(settings_screen)
			screen = "settings"
			_grab.call_deferred(settings_screen.first_focus())
		_:
			screen = "main"
			_refresh_info()
			if _opened_from != null and is_instance_valid(_opened_from):
				_grab.call_deferred(_opened_from)
			else:
				_focus_start.call_deferred()
	main_panel.visible = screen == "main"
	screen_changed.emit(screen)


func _close_sub_screens() -> void:
	for s: Control in [voice_screen, settings_screen]:
		if s != null and is_instance_valid(s):
			ui.remove_child(s)
			s.queue_free()
	voice_screen = null
	settings_screen = null


func _settings_file() -> String:
	return settings_path if settings_path != "" else GameSettings.path


func _focus_start() -> void:
	_grab(start_button)


## Focus a control if it still exists (deferred calls can outlive the screen).
func _grab(c: Control) -> void:
	if c != null and is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree():
		c.grab_focus()


# --- UI ---------------------------------------------------------------------------------------------

func _build_main() -> void:
	main_panel = Control.new()
	main_panel.name = "Main"
	main_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_panel.theme = FormTheme.theme()
	ui.add_child(main_panel)

	# A soft shade down the left edge so the board has something to sit on; the rest is the 3D backdrop's.
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.02, 0.015, 0.02, 0.6), Color(0.02, 0.015, 0.02, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(1.0, 0.0)
	tex.width = 128
	tex.height = 4
	var shade := TextureRect.new()
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.anchor_right = 0.5
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_panel.add_child(shade)

	# The work order on the clipboard, on the left third of the screen.
	clipboard = FormClipboard.new(600.0, 838.0, -1.2)
	clipboard.anchor_left = 0.0
	clipboard.anchor_right = 0.0
	clipboard.anchor_top = 0.5
	clipboard.anchor_bottom = 0.5
	clipboard.offset_left = 58.0
	clipboard.offset_right = 658.0
	clipboard.offset_top = -419.0
	clipboard.offset_bottom = 419.0
	main_panel.add_child(clipboard)

	var sheet := FormSheet.new("27-B", "Work order", "CAST  ·  " + TAGLINE, "Copy", "OFFICE", "white", 46)
	clipboard.set_content(sheet)
	var body := sheet.body

	var strip := HBoxContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip_l := FormTheme.label("1-800-LOW-MANA  ·  24/7 EMERGENCY DISPATCH", 17)
	strip_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.add_child(strip_l)
	strip.add_child(FormTheme.label("LIC. LBS-0427", 17))
	body.add_child(FormTheme.margin(strip, 22, 8, 22, 8))
	body.add_child(FormTheme.rule(2.0))

	start_button = _menu_row(body, "Start", "01", "new contract", func() -> void: start_game())
	voice_button = _menu_row(body, "Voice setup", "02", "", func() -> void: _open(voice_button, "voice"))
	settings_button = _menu_row(body, "Settings", "03", "options", func() -> void: _open(settings_button, "settings"))
	quit_button = _menu_row(body, "Quit", "04", "clock out", func() -> void: quit())

	var note := FormTheme.typed_wrapped("First time? Open Voice setup first and make sure the crew can hear you.", 19, FormTheme.TYPED)
	body.add_child(FormTheme.margin(note, 22, 12, 22, 6))

	var office_head := HBoxContainer.new()
	office_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	office_head.add_theme_constant_override("separation", 10)
	var office_cap := FormTheme.label("FOR OFFICE USE ONLY", 17, FormTheme.INK, true)
	office_cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	office_head.add_child(office_cap)
	office_head.add_child(FormTheme.label("BUILD", 16, FormTheme.INK, true))
	build_label = FormTheme.typed(BuildVersion.text(), 16)
	build_label.name = "BuildVersion"
	office_head.add_child(build_label)
	body.add_child(FormTheme.margin(office_head, 22, 6, 22, 0))
	body.add_child(FormTheme.spacer())
	body.add_child(FormTheme.rule(2.0))
	var ads := HBoxContainer.new()
	ads.add_theme_constant_override("separation", 8)
	ads.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ads.add_child(FormTheme.ad("Contract service", "Gates closed while you wait."))
	ads.add_child(FormTheme.ad("Local trade", "Hexes, drains, leaks. Free estimates."))
	ads.add_child(FormTheme.ad("Lost: shark", "Answers to \"Bruce\". Do not hit."))
	body.add_child(FormTheme.margin(ads, 22, 10, 22, 14))

	var stamp := FormStamp.new("LICENSED · BONDED · MOSTLY", 18, -8.0)
	stamp.position = Vector2(235.0, 650.0)   # the blank strip above the ads, clear of the BUILD line
	clipboard.add_child(stamp)

	var keys := KeyHints.new([["Up", "Down", "move"], ["Enter", "sign"], ["Esc", "back"]])
	keys.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	keys.offset_left = 720.0
	keys.offset_top = -52.0
	keys.offset_bottom = -20.0
	main_panel.add_child(keys)

	FormTheme.chain([start_button, voice_button, settings_button, quit_button])
	_refresh_info()


func _menu_row(parent: Control, text: String, number: String, hint: String, on_press: Callable) -> FormRow:
	var r := FormRow.new(text, number, hint)
	r.row_h = 76.0
	r.pressed.connect(on_press)
	parent.add_child(r)
	return r


## Fill the hint on Voice setup from the saved voice settings.
func _refresh_info() -> void:
	var vs := VoiceSettings.load_settings(_settings_file())
	var word := str(vs["trigger_word"])
	var strict := str(vs["strictness"])
	voice_button.hint = "\"%s\" · %s" % [word, strict]


func _open(from: Button, which: String) -> void:
	_opened_from = from
	show_screen(which)


func _fade_in() -> void:
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 1)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(rect)
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 0.0, 0.7)
	tw.tween_callback(rect.queue_free)


func _shot_later(path: String, after: float, say_text: String) -> void:
	if say_text != "" and voice_screen != null:
		get_tree().create_timer(maxf(after - 0.7, 0.2)).timeout.connect(func() -> void:
			if voice_screen != null:
				voice_screen.say(say_text))
	await get_tree().create_timer(after).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[menu] screenshot saved: ", path)
	get_tree().quit()
