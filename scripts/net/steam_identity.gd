class_name SteamIdentity
extends RefCounted
## The ONE place Steam is initialised (once per process), plus the player's Steam name for the HUD and the
## crew roster. Uses the GodotSteam GDExtension (addons/godotsteam, binaries copied from
## ../bridge-to-friendship, never committed) through Engine.get_singleton, so the game still parses and runs
## when the extension is missing, Steam isn't running, or it is a headless/test run: then the caller's
## fallback (the hero's name) is used and `steam()` is null.
##
## SteamLobby (lobbies) and NetSession (the Steam transport) get the singleton from `steam()`; nothing outside
## scripts/net/ touches Steam (test_net_contract enforces it).
##
## steam_appid.txt (480, Valve's Spacewar test app) sits in the project root and next to the exported exe
## until Cast has an app id of its own.

static var _tried := false
static var _name := ""
static var _steam: Object = null


## The Steam persona name, or `fallback` when Steam is unavailable.
static func player_name(fallback: String) -> String:
	_ensure()
	return _name if _name != "" else fallback


static func available() -> bool:
	_ensure()
	return _steam != null


## The initialised GodotSteam singleton, or null.
static func steam() -> Object:
	_ensure()
	return _steam


## Our own Steam id, or 0.
static func steam_id() -> int:
	_ensure()
	return int(_steam.call("getSteamID")) if _steam != null else 0


## Test seam (M7): stand a fake Steam object in for the singleton (lobbies, invites, avatars and the fake-lag config are
## then exercised against it with no Steam client). `reset_for_tests()` forgets it and Steam is looked for again.
static func use_for_tests(fake: Object) -> void:
	_tried = true
	_steam = fake
	_name = str(fake.call("getPersonaName")).strip_edges() if fake != null else ""


static func reset_for_tests() -> void:
	_tried = false
	_steam = null
	_name = ""


static func _ensure() -> void:
	if _tried:
		return
	_tried = true
	_steam = _init_steam()
	if _steam != null:
		_name = str(_steam.call("getPersonaName")).strip_edges()
		print("[Steam] player: ", _name)


static func _init_steam() -> Object:
	var args := OS.get_cmdline_user_args()
	# Headless and test runs never touch Steam, except the manual lobby check (--net-steam-probe, NetSession).
	if (DisplayServer.get_name() == "headless" or args.has("--run-test")) and not args.has("--net-steam-probe"):
		return null
	if args.has("--no-steam") or not Engine.has_singleton("Steam"):
		return null
	var steam: Object = Engine.get_singleton("Steam")
	# GodotSteam has returned both a bool and a Dictionary from steamInit() across versions.
	var result: Variant = steam.call("steamInit")
	var ok := false
	if typeof(result) == TYPE_DICTIONARY:
		ok = int((result as Dictionary).get("status", 1)) == 0
	else:
		ok = bool(result)
	if not ok:
		print("[Steam] not available (", result, "): solo only")
		return null
	return steam
