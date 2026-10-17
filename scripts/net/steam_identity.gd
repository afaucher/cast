class_name SteamIdentity
extends RefCounted
## The player's Steam name, for the HUD. Uses the GodotSteam GDExtension (addons/godotsteam, binaries copied
## from ../bridge-to-friendship, never committed) through Engine.get_singleton, so the game still parses and
## runs when the extension is missing, Steam isn't running, or it is a headless/test run: then the caller's
## fallback (the hero's name) is used.
##
## Steam is initialised at most once per process. steam_appid.txt (480, Valve's Spacewar test app) sits in the
## project root and next to the exported exe until Cast has an app id of its own.

static var _tried := false
static var _name := ""


## The Steam persona name, or `fallback` when Steam is unavailable.
static func player_name(fallback: String) -> String:
	if not _tried:
		_tried = true
		_name = _init_steam()
	return _name if _name != "" else fallback


static func available() -> bool:
	player_name("")
	return _name != ""


static func _init_steam() -> String:
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--run-test"):
		return ""
	if OS.get_cmdline_user_args().has("--no-steam") or not Engine.has_singleton("Steam"):
		return ""
	var steam: Object = Engine.get_singleton("Steam")
	# GodotSteam has returned both a bool and a Dictionary from steamInit() across versions.
	var result: Variant = steam.call("steamInit")
	var ok := false
	if typeof(result) == TYPE_DICTIONARY:
		ok = int((result as Dictionary).get("status", 1)) == 0
	else:
		ok = bool(result)
	if not ok:
		print("[Steam] not available (", result, "): using the hero's name")
		return ""
	var persona := str(steam.call("getPersonaName")).strip_edges()
	print("[Steam] player: ", persona)
	return persona
