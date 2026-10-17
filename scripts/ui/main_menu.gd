class_name MainMenu
extends Node
## The main menu (scenes/main_menu.tscn), the default boot target (see Boot.route). A living background
## (MenuBackdrop: the crew idling in a slate hall with a hellgate glowing in the distance) behind four
## buttons: Start (the game scene, i.e. the contract job board), Voice setup (VoiceSetupScreen: live mic
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
	ui.add_child(main_panel)

	# A dark slate wash from the left so the title and buttons read over the scene.
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.02, 0.025, 0.04, 0.94), Color(0.02, 0.025, 0.04, 0.78), Color(0.02, 0.025, 0.04, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(1.0, 0.0)
	tex.width = 256
	tex.height = 8
	var wash := TextureRect.new()
	wash.texture = tex
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.anchor_right = 0.55
	wash.offset_right = 0.0
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_panel.add_child(wash)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 96.0
	col.offset_right = 96.0 + 460.0
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_panel.add_child(col)

	var title := MenuStyle.label("CAST", 168, MenuStyle.AMBER_HOT)
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.1, 0.02))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 8)
	col.add_child(title)
	var bar := ColorRect.new()
	bar.color = MenuStyle.AMBER
	bar.custom_minimum_size = Vector2(0, 5)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bar)
	col.add_child(MenuStyle.label(TAGLINE, 23, MenuStyle.DIM))
	col.add_child(MenuStyle.gap(26))

	start_button = _menu_button(col, "Start", func() -> void: start_game())
	voice_button = _menu_button(col, "Voice setup", func() -> void: _open(voice_button, "voice"))
	settings_button = _menu_button(col, "Settings", func() -> void: _open(settings_button, "settings"))
	quit_button = _menu_button(col, "Quit", func() -> void: quit())

	col.add_child(MenuStyle.gap(10))
	col.add_child(MenuStyle.wrapped("First time? Open Voice setup first and make sure the crew can hear you.", 16, MenuStyle.DIM))
	var keys := MenuStyle.label("Arrows or Tab to move, Enter to choose, Esc to go back.", 14, Color(MenuStyle.DIM, 0.7))
	col.add_child(keys)


func _menu_button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := MenuStyle.button(text)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


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
