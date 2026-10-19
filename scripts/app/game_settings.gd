class_name GameSettings
extends RefCounted
## Persisted game options (user://settings.cfg, section "game", next to VoiceSettings' "voice" section).
## Applied once at boot (Boot) and live from the Settings screen; the game reads voice_panel_visible.
##
##   master_volume        0..1, the Master audio bus (default 1.0)
##   fullscreen           true = borderless fullscreen, false = a window (default false)
##   resolution           "1280x720" | "1600x900" (default) | "1920x1080": the window size when windowed
##   voice_panel_visible  the voice debug panel (F1) is open when a contract starts (default true)
##   link_sim             Diagnostics, "Simulate a long link": "off" (default) | "coast" | "rough". The host's choice is
##                        the whole crew's (NetSession applies it when the crew opens and sends it to everyone); solo it
##                        does nothing
##
## Every function takes an optional settings path (tests use a temp file); "" means `path`, which is
## user://settings.cfg unless a dev flag (--settings-file) moved it.

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "game"
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const DEFAULT_RESOLUTION := Vector2i(1600, 900)
## Each volume setting and the bus it drives (default_bus_layout.tres). Only the master: the other buses' levels are tuned
## in the game itself (Sfx cue volumes and the bus layout), not by players (user, 2026-10-18: "no individual sound controls").
const BUS_VOLUMES := {"master_volume": "Master"}
## Link simulator presets (NetLink.PRESETS / NetSteamLink): what Settings > Diagnostics offers.
const LINK_PRESETS: Array[String] = ["off", "coast", "rough"]

## Where settings live. Boot sets it from --settings-file (screenshots must not touch the player's file).
static var path: String = DEFAULT_PATH


static func defaults() -> Dictionary:
	return {"master_volume": 1.0, "fullscreen": false, "resolution": resolution_text(DEFAULT_RESOLUTION), "voice_panel_visible": true,
		"link_sim": "off"}


static func resolution_text(res: Vector2i) -> String:
	return "%dx%d" % [res.x, res.y]


## "1920x1080" -> Vector2i; anything that is not one of RESOLUTIONS gives the default.
static func parse_resolution(text: String) -> Vector2i:
	var bits := text.strip_edges().to_lower().split("x")
	if bits.size() == 2:
		var res := Vector2i(int(bits[0]), int(bits[1]))
		if RESOLUTIONS.has(res):
			return res
	return DEFAULT_RESOLUTION


static func load_settings(settings_path: String = "") -> Dictionary:
	var out := defaults()
	var cfg := ConfigFile.new()
	if cfg.load(settings_path if settings_path != "" else path) != OK:
		return out
	for key: String in out:
		out[key] = cfg.get_value(SECTION, key, out[key])
	for key: String in BUS_VOLUMES:
		out[key] = clampf(float(out[key]), 0.0, 1.0)
	out["fullscreen"] = bool(out["fullscreen"])
	out["voice_panel_visible"] = bool(out["voice_panel_visible"])
	out["resolution"] = resolution_text(parse_resolution(str(out["resolution"])))
	out["link_sim"] = str(out["link_sim"]) if LINK_PRESETS.has(str(out["link_sim"])) else "off"
	return out


## Writes only the keys given, keeping everything else in the file (the voice section too).
static func save_settings(settings: Dictionary, settings_path: String = "") -> bool:
	var file := settings_path if settings_path != "" else path
	var cfg := ConfigFile.new()
	cfg.load(file)   # a missing file is fine
	var known := defaults()
	for key: String in known:
		if settings.has(key):
			cfg.set_value(SECTION, key, settings[key])
	return cfg.save(file) == OK


## Put the saved settings into effect (every audio bus by name and, if include_window, the window).
static func apply(settings: Dictionary = {}, include_window: bool = true) -> void:
	var s := settings if not settings.is_empty() else load_settings()
	for key: String in BUS_VOLUMES:
		apply_bus_volume(BUS_VOLUMES[key], float(s.get(key, 1.0)))
	if include_window:
		apply_window(bool(s.get("fullscreen", false)), parse_resolution(str(s.get("resolution", ""))))


static func apply_volume(volume: float) -> void:
	apply_bus_volume("Master", volume)


## Set the bus called `bus` to `volume` (0..1; 0 mutes it). A bus that does not exist is skipped.
static func apply_bus_volume(bus: String, volume: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	var v := clampf(volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(i, v <= 0.001)


static func apply_window(fullscreen: bool, res: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if DisplayServer.window_get_size() == res:
		return
	DisplayServer.window_set_size(res)
	var screen := DisplayServer.screen_get_usable_rect()
	var pos := screen.position + (screen.size - res) / 2
	DisplayServer.window_set_position(Vector2i(maxi(pos.x, screen.position.x), maxi(pos.y, screen.position.y)))
