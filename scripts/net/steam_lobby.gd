class_name SteamLobby
extends Node
## Steam lobbies: create, find the first one hiring, join, leave, invites. Ported from Bridge to Friendship's
## steam_manager.gd, through SteamIdentity.steam() (the one Steam init; GodotSteam reached by string names so
## the project parses without the extension). The child "Lobby" of the Session autoload; NetSession drives it
## and turns its signals into session state. Nothing else touches Steam.
##
## Lobby data: name, game (LOBBY_GAME_KEY: app 480 Spacewar is shared by every test project, so a short key
## collides), version (the build stamp, so different builds never pair), protocol, seats_free and state
## (board / job). The list filters on game + version + a free seat.
##
## `run_callbacks()` is pumped every frame while Steam is up, or nothing async ever completes.

signal created(lobby_id: int)
signal joined(lobby_id: int)
signal failed(reason: String)
signal listed(lobbies: Array)
## The player accepted an invite or "Join game" in the Steam overlay while the game was running. `friend_id` is who
## invited them (0 when Steam doesn't say).
signal invite_accepted(lobby_id: int, friend_id: int)

const LOBBY_GAME_KEY := "cast_licensed_sorcery"
## Steam's chat-room enter responses (EChatRoomEnterResponse).
const ENTER_SUCCESS := 1
const ENTER_FULL := 4

var lobby_id := 0
var _wired_to: Object = null   ## the Steam object whose signals are connected (a test's fake replaces the real one)
var _join_requested := false   ## Steam also sends lobby_joined to a lobby's creator: only a join we asked for counts


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	var steam := SteamIdentity.steam()   # initialises Steam on the first frame (invites need the callbacks)
	if steam == null:
		return
	_wire(steam)
	steam.call("run_callbacks")


static func available() -> bool:
	return SteamIdentity.available()


## The build stamp lobbies are matched on.
static func build_version() -> String:
	return BuildVersion.text()


## `+connect_lobby <id>` on the command line: how Steam launches a game that wasn't running to accept an
## invite. 0 when absent.
static func connect_lobby_arg(args: PackedStringArray) -> int:
	var i := args.find("+connect_lobby")
	if i >= 0 and i + 1 < args.size() and args[i + 1].is_valid_int():
		return int(args[i + 1])
	return 0


func create(max_members: int) -> bool:
	var steam := SteamIdentity.steam()
	if steam == null:
		failed.emit("Steam not running")
		return false
	if lobby_id != 0:
		failed.emit("already in a lobby")
		return false
	_wire(steam)
	steam.call("createLobby", _const("LOBBY_TYPE_PUBLIC", 2), max_members)
	return true


func request_list() -> bool:
	var steam := SteamIdentity.steam()
	if steam == null:
		failed.emit("Steam not running")
		return false
	_wire(steam)
	var equal := _const("LOBBY_COMPARISON_EQUAL", 0)
	steam.call("addRequestLobbyListDistanceFilter", _const("LOBBY_DISTANCE_FILTER_WORLDWIDE", 3))
	steam.call("addRequestLobbyListStringFilter", "game", LOBBY_GAME_KEY, equal)
	steam.call("addRequestLobbyListStringFilter", "version", build_version(), equal)
	steam.call("addRequestLobbyListStringFilter", "seats_free", "0", _const("LOBBY_COMPARISON_NOT_EQUAL", 3))
	steam.call("addRequestLobbyListFilterSlotsAvailable", 1)
	steam.call("requestLobbyList")
	return true


func join(id: int) -> bool:
	var steam := SteamIdentity.steam()
	if steam == null:
		failed.emit("Steam not running")
		return false
	_wire(steam)
	_join_requested = true
	steam.call("joinLobby", id)
	return true


func leave() -> void:
	var steam := SteamIdentity.steam()
	if steam != null and lobby_id != 0:
		steam.call("leaveLobby", lobby_id)
		print("[Steam] left lobby ", lobby_id)
	lobby_id = 0
	_join_requested = false


## The Steam overlay's invite dialog for this lobby (M7, "Invite crew"). False without Steam or a lobby.
func open_invite_dialog() -> bool:
	var steam := SteamIdentity.steam()
	if steam == null or lobby_id == 0:
		return false
	steam.call("activateGameOverlayInviteDialog", lobby_id)
	return true


## A Steam friend's persona name ("" when unknown or without Steam).
func friend_name(steam_id: int) -> String:
	var steam := SteamIdentity.steam()
	if steam == null or steam_id == 0:
		return ""
	return str(steam.call("getFriendPersonaName", steam_id)).strip_edges()


func owner_id() -> int:
	var steam := SteamIdentity.steam()
	if steam == null or lobby_id == 0:
		return 0
	return int(steam.call("getLobbyOwner", lobby_id))


func get_data(id: int, key: String) -> String:
	var steam := SteamIdentity.steam()
	return str(steam.call("getLobbyData", id, key)) if steam != null else ""


func set_data(key: String, value: String) -> void:
	var steam := SteamIdentity.steam()
	if steam != null and lobby_id != 0:
		steam.call("setLobbyData", lobby_id, key, value)


func _wire(steam: Object) -> void:
	if _wired_to == steam:
		return
	_wired_to = steam
	steam.connect("lobby_created", _on_lobby_created)
	steam.connect("lobby_joined", _on_lobby_joined)
	steam.connect("lobby_match_list", _on_lobby_match_list)
	steam.connect("join_requested", _on_join_requested)


func _on_lobby_created(result: int, id: int) -> void:
	if result != 1:
		failed.emit("Steam couldn't open a lobby (%d)" % result)
		return
	lobby_id = id
	set_data("name", "%s's crew" % SteamIdentity.player_name("A"))
	set_data("game", LOBBY_GAME_KEY)
	set_data("version", build_version())
	set_data("protocol", str(NetSession.PROTOCOL))
	print("[Steam] created lobby ", lobby_id)
	created.emit(lobby_id)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if not _join_requested:
		return   # the creator's own echo after createLobby
	_join_requested = false
	if response != ENTER_SUCCESS:
		var reason := "Steam refused the lobby (%d)" % response
		match response:
			2: reason = "That crew is gone"
			ENTER_FULL: reason = NetSession.CREW_FULL
			3, 6, 10, 11: reason = "Not allowed to join that crew"
		failed.emit(reason)
		return
	lobby_id = id
	print("[Steam] joined lobby ", lobby_id)
	joined.emit(lobby_id)


func _on_lobby_match_list(lobbies: Array) -> void:
	print("[Steam] found ", lobbies.size(), " lobbies")
	listed.emit(lobbies)


func _on_join_requested(id: int, friend_id: int) -> void:
	invite_accepted.emit(id, friend_id)


static func _const(name_: String, fallback: int) -> int:
	if ClassDB.class_has_integer_constant("Steam", name_):
		return ClassDB.class_get_integer_constant("Steam", name_)
	return fallback
