class_name NetSession
extends Node
## Autoload "Session": the crew session. Ported from Bridge to Friendship's network_manager.gd (same two
## transports, same peer bookkeeping, "wait for both sides") plus what Cast's plan adds: the hello handshake,
## the crew roster, refusals with a reason, the session clock and telemetry (docs/design/networking-build-plan.md
## M0). Gameplay code only ASKS (Net.is_host(), Session.online(), the roster); every send lives in scripts/net/.
##
## TRANSPORTS
##   STEAM: what ships. A Steam lobby (SteamLobby) plus SteamMultiplayerPeer (no_nagle) to the lobby owner.
##   ENET:  dev and tests. Plain UDP on localhost, so several instances (and the multi-process test harness)
##          can play on one machine with no Steam client.
## Both are the same MultiplayerAPI, so everything above this file is transport-agnostic.
##
## HANDSHAKE (all reliable events on NetWire, kinds "sys.*")
##   host -> joiner   sys.ask      {protocol, build}                 sent when the host sees the peer connect
##   joiner -> host   sys.hello    {protocol, build, name, character, steam_id}
##   host -> joiner   sys.welcome  {seat, peer, entries, host_unix}  or   sys.refuse {reason}
##   host -> all      sys.roster   {entries}                          after every join and leave
##   host -> all      sys.bye      {reason}                           the host is leaving (then it closes)
## The host speaks first, so it has always registered the peer before the joiner says anything (Bridge: the
## two ends become ready on different frames). A refused joiner is told why ("Crew is full", "Different
## build") and dropped REFUSE_GRACE later; the transport admits a few more peers than MAX_CREW for that.
##
## ROSTER: peer id -> {peer, seat, name, character, steam_id}. The host is seat 1; a joiner takes the lowest
## free seat. `character` is each player's character id (the default character until a character select sets
## `character_id`). Same list on every machine (the host broadcasts it).
## The shared run (CrewFlow, M1) adds the fields "signed", "spells" and "ready" to an entry through set_members();
## kick() sends a member out with a reason. M6: a hello while the crew is on a job (crew_state "job") is admitted as a
## JOINING member ("joining" true, the seat chosen by SeatHandover.choose_seat: one of the AI's) that NetJoin brings onto
## the next running floor; the 4th is still refused with "Crew is full" (and the lobby's seats_free is 0 by then).
##
## LEAVING. A client leaves: the host drops it from the roster. The host leaves (or dies, or goes silent for
## HOST_SILENCE): every client's session ends with "The host clocked out". No host migration.
## session_ended(reason) fires for every way a session (or an attempt at one) ends. A client that leaves mid-floor
## also hands its seat's hero to the AI (SeatHandover, M2).
##
## HEROES (M2): `snap` (NetSnapshot) streams the heroes this machine owns and shows the others as puppets over
## NetWire.T_SNAP; `seats` (SeatHandover) says who owns which seat and runs the hand-back to the AI.
## THE WORLD (M3): `world` (NetWorld) streams the host's monsters, hellgates and employees in the same packets and shows
## them as puppets on clients; `objects` (NetObjects) arbitrates props, crates, mail, pickups, employee requests, the
## Ledger and the exits (requests from players, one decision on the host).
## JOINING MID-CONTRACT (M6): `join` (NetJoin) brings a player who joined a crew on the job onto a running floor (the
## late-join snapshot) and into an AI's seat (SeatHandover).
##
## CLOCK: NetClock, pinged over unreliable packets; `host_time()` is the shared clock.
## TELEMETRY: NetTelemetry, one row a second, clients' rows collected on the host. M7 adds two passive sheets: every cast
## (`note_cast`: sent with its voice onset and recognition latency, applied on every machine) and hits taken per player per
## minute (`note_hit`, every HITS_WINDOW); a client's rows reach the host as reliable `tele.cast` / `tele.hits` events.
##
## M7 (polish):
##   LINK SIMULATOR. The host's Settings > Diagnostics "Simulate a long link" (GameSettings link_sim: off / coast / rough) is
##   the crew's link: applied on the host when it opens the crew, carried in sys.welcome and re-sent as `sys.link {preset}`
##   when it changes (set_link), and every machine applies it to what IT receives: NetLink on ENet, Steam's FakePacket*
##   config on Steam (NetSteamLink). A --net-link dev flag (and a test) sets the host's instead of the setting.
##   INVITES. Steam's join_requested (an overlay invite accepted while the game runs) becomes `invite_received(lobby,
##   inviter)`: the screen that is up asks first (the game: "Leave this job and join?") and calls accept_invite() or
##   decline_invite(); with nobody listening it joins at once. `+connect_lobby <id>` (Steam launching the game for an
##   invite) joins at start. `invite_crew()` opens the overlay's invite dialog for this lobby (`can_invite()`).
##   AVATARS. `avatars` (SteamAvatars): roster pictures by steam id, null without Steam.
##
## Dev flags (after `--`; also README "Online play"):
##   --net-host               host over ENet on --net-port (and open the job board)
##   --net-join <ip[:port]>   join over ENet (the menu shows the crew)
##   --net-port <P>           ENet port (default DEFAULT_PORT)
##   --net-link off|coast|rough   simulate lag and loss on everything this process receives
##   --net-name <name>        the name in the roster (two local instances share one Steam name)
##   --net-steam-probe        create a Steam lobby, print it, leave and quit (the manual Steam check)
##   +connect_lobby <id>      Steam launched us to accept an invite: join that lobby

signal session_started(as_host: bool)
## An overlay invite arrived while the game runs (M7): ask the player, then accept_invite() / decline_invite().
signal invite_received(lobby_id: int, inviter: String)
## The crew's simulated link changed (M7: "off", "coast", "rough").
signal link_changed(preset: String)
signal session_ended(reason: String)
signal roster_changed()
signal peer_joined(peer: int)
signal peer_left(peer: int)
signal status_changed(text: String)
## A non-system reliable event from a crew member (gameplay events, test probes).
signal event_received(from: int, kind: String, data: Dictionary, stamp: float)
## A non-system unreliable packet that passed the sequence check.
signal packet_received(from: int, type: int, seq: int, stamp_ms: int, payload: PackedByteArray)

enum Transport { NONE, ENET, STEAM }
enum State { OFFLINE, OPENING, CONNECTING, HELLO, ONLINE }

const PROTOCOL := 1
const MAX_CREW := 3
const DEFAULT_PORT := 24600
## The character everyone plays until a character select exists (MenuBackdrop.PLAYER_HERO; test_net_session checks they agree).
const DEFAULT_CHARACTER := "wick"
const OPEN_TIMEOUT := 12.0      ## Steam lobby create / list / join
const CONNECT_TIMEOUT := 10.0   ## transport connect
const HELLO_TIMEOUT := 10.0     ## connected, waiting for the host's welcome (or a joiner's hello)
const HOST_SILENCE := 6.0       ## a client hears nothing from the host this long: the host is gone
const CLIENT_SILENCE := 10.0    ## the host hears nothing from a client this long: drop it
const REFUSE_GRACE := 1.0       ## a refused joiner is dropped this long after being told why
const ENET_THROTTLE_INTERVAL_MS := 5000   ## ENet's own defaults, except that the throttle never goes down (see _tune_enet)
const ENET_THROTTLE_UP := 2

const CREW_FULL := "Crew is full"
const DIFFERENT_BUILD := "Different build"
const HOST_LEFT := "The host clocked out"
const YOU_LEFT := "You left the crew"
const CREW_CLOSED := "You closed the crew"
const CONNECT_FAILED := "Couldn't reach the crew"
const NO_ANSWER := "The crew never answered"
const NO_CREWS := "No crews hiring right now"
const STEAM_OFF := "Steam not running"
## Seconds per row of the hits sheet (hits taken per player per minute). Tests shorten it.
const HITS_WINDOW := 60.0
## (M0-M5: a crew on a job refused new hellos with this; from M6 a hello mid-job is admitted as a joiner. Kept for the logs.)
const JOB_RUNNING := "That crew is already on a job"
const DESYNC := "Desync: different floor"

var state := State.OFFLINE
var transport := Transport.NONE
var hosting := false
## peer id -> {"peer", "seat", "name", "character", "steam_id"}
var roster: Dictionary = {}
## The roster name; "" = the Steam persona, else "Crew <seat>". --net-name sets it.
var player_name := ""
## This player's character id; "" = DEFAULT_CHARACTER. A character select sets it.
var character_id := ""
## What this machine says it is in the hello (tests change them to provoke "Different build").
var protocol := PROTOCOL
var build := ""
var last_reason := ""
## Why "Start a job" ended up solo ("Steam not running: solo only"); the job board shows it. Not net state.
var offline_note := ""
var telemetry_enabled := true
var telemetry_dir := NetTelemetry.DIR
## Client: the host's unix time at host_time 0 (only tests use it, to measure the clock on one machine).
var host_unix_epoch := 0.0
## "board" or "job", published in the lobby.
var crew_state := "board"
## Host: every refused hello, [{peer, name, reason}] (tests and logs).
var refusals: Array = []

var wire: NetWire = null
var lobby: SteamLobby = null
## The shared run (board, job, license checkout, floor barrier, floor clock): scripts/net/crew_flow.gd, child "Flow".
var flow: CrewFlow = null
## Who owns each seat's hero, and the handover to the AI when a player drops (scripts/net/seat_handover.gd), child "Seats".
var seats: SeatHandover = null
## Hero sync (M2): streams the heroes this machine owns and shows the others as puppets (scripts/net/net_snapshot.gd), child "Snap".
var snap: NetSnapshot = null
## The host-owned world (M3): monsters, hellgates and employees streamed to clients as puppets (scripts/net/net_world.gd), child "World".
var world: NetWorld = null
## Host-arbitrated objects (M3): hits on props, crates and mail, pickups, employee requests, the Ledger mirror and exits
## (scripts/net/net_objects.gd), child "Objects".
var objects: NetObjects = null
## Casts and hero attacks as events (M4a): child "Casts".
var casts: NetCasts = null
## Statuses (modifiers, fires, soaks) from their owners to every screen (M4b): child "Status".
var status: NetStatus = null
## Joining mid-contract (M6): the late-join snapshot and the way onto a running floor: child "Join".
var join: NetJoin = null
## Voice orders (combat-proposals.md 1.0): a player's order is a request the host applies, then every screen shows the
## barks and markers (scripts/net/net_orders.gd), child "Orders".
var orders: NetOrders = null
## Hits this machine's own heroes took since the last telemetry row (the `hits` column, M4).
var hits_taken := 0
## The crew's simulated link (M7): the host decides, every machine applies it to what it receives.
var link_preset := "off"
## Host: take the crew's link from Settings > Diagnostics when the crew opens. Only the game's own Session does (its flags
## set it: not with a --net-link dev flag, not in a test), so a test's NetSession never reads the player's settings.
var link_from_settings := false
## Steam roster pictures (M7): child "Avatars".
var avatars: SteamAvatars = null
## An overlay invite waiting for the player's answer: {lobby, inviter} ({} = none).
var pending_invite: Dictionary = {}
## Seconds per row of the hits sheet (HITS_WINDOW; tests shorten it).
var hits_window := HITS_WINDOW
## Host: the whole session's hits per player, "peer:seat" -> {name, who, hits, damage, floor_s} (printed at the end).
var hits_totals: Dictionary = {}
var clock := NetClock.new()
var telemetry: NetTelemetry = null

var _pending: Dictionary = {}      ## host: peer -> usec it connected (no hello yet)
var _refused: Dictionary = {}      ## host: peer -> usec to drop it
var _last_heard: Dictionary = {}   ## peer -> usec of the last message
var _deadline_usec := 0
var _pings_sent := 0
var _next_ping_usec := 0
var _next_row_usec := 0
var _find_first := false           ## a join_first() is waiting for the lobby list
var _probe := false                ## --net-steam-probe
var _steam_link := false           ## Steam's fake-lag config is set (cleared when the session ends)
var _tally: Dictionary = {}        ## seat this machine owns -> {hits, damage, floor_s, sources {kind: n}} this window
var _next_hits_usec := 0
var _hits_minute := 0
var _last_frame_usec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	wire = NetWire.new()
	wire.name = "Wire"
	wire.clock_source = host_time
	add_child(wire)
	wire.event_received.connect(_on_event)
	wire.packet_received.connect(_on_packet)
	flow = CrewFlow.new()
	flow.name = "Flow"
	add_child(flow)
	seats = SeatHandover.new()
	seats.name = "Seats"
	add_child(seats)
	snap = NetSnapshot.new()
	snap.name = "Snap"
	add_child(snap)
	world = NetWorld.new()
	world.name = "World"
	add_child(world)
	objects = NetObjects.new()
	objects.name = "Objects"
	add_child(objects)
	casts = NetCasts.new()
	casts.name = "Casts"
	add_child(casts)
	status = NetStatus.new()
	status.name = "Status"
	add_child(status)
	join = NetJoin.new()
	join.name = "Join"
	add_child(join)
	orders = NetOrders.new()
	orders.name = "Orders"
	add_child(orders)
	avatars = SteamAvatars.new()
	avatars.name = "Avatars"
	add_child(avatars)
	lobby = SteamLobby.new()
	lobby.name = "Lobby"
	add_child(lobby)
	lobby.created.connect(_on_lobby_created)
	lobby.joined.connect(_on_lobby_joined)
	lobby.failed.connect(_on_lobby_failed)
	lobby.listed.connect(_on_lobby_listed)
	lobby.invite_accepted.connect(_on_invite)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if get_parent() == get_tree().root:
		_apply_flags.call_deferred(OS.get_cmdline_user_args(), OS.get_cmdline_args())


## The process is quitting. The Wire child has already left the tree, so no goodbye event: closing the
## transport is what tells the others (ENet sends its disconnects on close; a silent death is caught by the
## other side's HOST_SILENCE / CLIENT_SILENCE watch).
func _exit_tree() -> void:
	if state != State.OFFLINE:
		_end(CREW_CLOSED if hosting else YOU_LEFT, true)


# --- Asking (anyone may) -------------------------------------------------------------------------------

## In a crew session (hosting, or a welcomed client).
func online() -> bool:
	return state == State.ONLINE


## Hosting a session, or offline (solo is hosting with nobody joining).
func is_host() -> bool:
	return hosting or state == State.OFFLINE


func is_client() -> bool:
	return state == State.ONLINE and not hosting


## Busy opening, connecting or saying hello.
func busy() -> bool:
	return state != State.OFFLINE and state != State.ONLINE


## This machine's peer id, or 0 offline. (get_unique_id() is 1 offline too, so never use it for "host".)
func local_id() -> int:
	return multiplayer.get_unique_id() if state == State.ONLINE else 0


## The shared session clock in seconds (0 offline, and on a client before the first pong).
func host_time() -> float:
	if state != State.ONLINE:
		return 0.0
	return clock.host_time(Time.get_ticks_usec())


## The roster sorted by seat.
func crew() -> Array:
	var out: Array = roster.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["seat"]) < int(b["seat"]))
	return out


func local_entry() -> Dictionary:
	return roster.get(local_id(), {})


## The host's roster name ("" when unknown).
func host_name() -> String:
	for e: Dictionary in roster.values():
		if int(e["seat"]) == 1:
			return str(e["name"])
	return ""


func steam_available() -> bool:
	return SteamIdentity.available()


func local_character() -> String:
	return character_id if character_id != "" else DEFAULT_CHARACTER


# --- Starting and ending ----------------------------------------------------------------------------

## Host over ENet. False (and session_ended) when the port can't be opened.
func host_enet(port: int = DEFAULT_PORT) -> bool:
	if not _can_start():
		return false
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(port, MAX_CREW + 2)   # room to tell a 4th "Crew is full" before dropping it
	if err != OK:
		_end("Couldn't open port %d (error %d)" % [port, err])
		return false
	_begin_host(enet, Transport.ENET)
	return true


## Join over ENet. The result arrives as session_started(false) or session_ended(reason).
func join_enet(address: String, port: int = DEFAULT_PORT) -> bool:
	if not _can_start():
		return false
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(address, port)
	if err != OK:
		_end("%s (%s:%d, error %d)" % [CONNECT_FAILED, address, port, err])
		return false
	_set_peer(enet)
	transport = Transport.ENET
	_set_state(State.CONNECTING, CONNECT_TIMEOUT, "Calling the crew at %s:%d..." % [address, port])
	return true


## Host over Steam: open a lobby, then the Steam peer. The result arrives as session_started(true) or
## session_ended(reason).
func host_steam() -> bool:
	if not _can_start():
		return false
	if not SteamIdentity.available():
		_end(STEAM_OFF)
		return false
	transport = Transport.STEAM
	hosting = true
	_set_state(State.OPENING, OPEN_TIMEOUT, "Opening a lobby...")
	return lobby.create(MAX_CREW)


## Join the first Steam lobby hiring for this game and build (Bridge's Join: no browser).
func join_first() -> bool:
	if not _can_start():
		return false
	if not SteamIdentity.available():
		_end(STEAM_OFF)
		return false
	transport = Transport.STEAM
	_find_first = true
	_set_state(State.OPENING, OPEN_TIMEOUT, "Looking for a crew that's hiring...")
	return lobby.request_list()


## Join a specific Steam lobby (an invite).
func join_lobby(lobby_id: int) -> bool:
	if not _can_start():
		return false
	if not SteamIdentity.available():
		_end(STEAM_OFF)
		return false
	transport = Transport.STEAM
	_set_state(State.OPENING, OPEN_TIMEOUT, "Joining the crew...")
	return lobby.join(lobby_id)


## Leave the session (or stop trying to join one). The host tells everyone first.
func leave(reason: String = "") -> void:
	if state == State.OFFLINE:
		return
	if reason == "":
		reason = CREW_CLOSED if hosting else YOU_LEFT
	if hosting and state == State.ONLINE:
		_to_crew("sys.bye", {"reason": HOST_LEFT})
		wire.flush()
	_end(reason)


## Send a reliable event to one crew member, or the whole crew (to = 0; from a client that is the host).
## Kinds starting "sys." are reserved.
func send_event(to: int, kind: String, data: Dictionary = {}) -> void:
	if state != State.ONLINE:
		return
	if to != 0:
		wire.send_event(to, kind, data)
	elif hosting:
		_to_crew(kind, data)
	else:
		wire.send_event(1, kind, data)


## Send an unreliable, sequence-numbered packet (types: NetWire.T_SNAP and up, or T_TEST) to one crew
## member, or the whole crew (to = 0: one send, and one sequence stream, per member). Returns the sequence
## number (the last one, for to = 0), or -1 offline.
func send_packet(to: int, type: int, payload: PackedByteArray) -> int:
	if state != State.ONLINE:
		return -1
	if to != 0 or not hosting:
		return wire.send_packet(to if to != 0 else 1, type, payload)
	var seq := -1
	for p: int in roster:
		if p != 1:
			seq = wire.send_packet(p, type, payload)
	return seq


## "board" or "job": what the host's crew is doing, for the lobby list (and M1+).
func set_crew_state(s: String) -> void:
	crew_state = s
	if hosting and state == State.ONLINE:
		_publish_lobby()


## Host: send a crew member out with a reason ("Desync: different floor"). It is told why (sys.refuse ends its
## session with that reason), dropped from the roster at once and disconnected REFUSE_GRACE later.
func kick(peer: int, reason: String) -> void:
	if not hosting or state != State.ONLINE or peer == 1 or not roster.has(peer):
		return
	wire.send_event(peer, "sys.refuse", {"reason": reason})
	wire.flush()
	_refused[peer] = Time.get_ticks_usec() + int(REFUSE_GRACE * 1e6)
	_drop(peer, "was sent out: %s" % reason)


## Host: set fields on roster entries (the shared run keeps "signed", "spells" and "ready" there) and send the
## roster to the crew, so every machine reads the same entries. `peer` 0 = every member.
func set_members(peer: int, fields: Dictionary) -> void:
	if not hosting or state != State.ONLINE:
		return
	for p: int in roster:
		if peer == 0 or p == peer:
			for k: String in fields:
				(roster[p] as Dictionary)[k] = fields[k]
	_to_crew("sys.roster", {"entries": crew()})
	roster_changed.emit()


# --- M7: the link simulator, invites, the passive sheets --------------------------------------------------

## Host: the crew's simulated link ("off", "coast", "rough"): applied here and sent to every member, who applies it to what
## it receives. False on a client or for an unknown preset.
func set_link(preset: String) -> bool:
	if not NetLink.PRESETS.has(preset) or (state == State.ONLINE and not hosting):
		return false
	_apply_link(preset)
	if hosting and state == State.ONLINE:
		_to_crew("sys.link", {"preset": preset})
	return true


## Every machine: simulate `preset` on what this process receives (NetLink on ENet, Steam's fake-lag config on Steam).
func _apply_link(preset: String) -> void:
	if not NetLink.PRESETS.has(preset):
		preset = "off"
	if transport == Transport.STEAM and SteamIdentity.steam() != null:
		if wire.link.preset != "off":
			wire.link.configure("off")
		NetSteamLink.apply(SteamIdentity.steam(), preset)
		_steam_link = preset != "off"
	elif wire.link.preset != preset:
		wire.link.configure(preset)
	var changed := preset != link_preset
	link_preset = preset
	if changed:
		_log("simulated link: %s" % preset)
		link_changed.emit(preset)


## True when the overlay's invite dialog can be opened for this crew: a Steam crew with a seat free.
func can_invite() -> bool:
	return state == State.ONLINE and transport == Transport.STEAM and lobby.lobby_id != 0 and seats_free() > 0


## "Invite crew": the Steam overlay's invite dialog for this lobby. False when it can't (see can_invite).
func invite_crew() -> bool:
	return can_invite() and lobby.open_invite_dialog()


## The player said yes to the pending invite: leave whatever this is and join that crew. The caller (the screen that asked)
## takes the player to the menu, where the join's progress shows. False with no invite pending.
func accept_invite() -> bool:
	if pending_invite.is_empty():
		return false
	var id := int(pending_invite["lobby"])
	pending_invite = {}
	if state != State.OFFLINE:
		leave()
	return join_lobby(id)


func decline_invite() -> void:
	if not pending_invite.is_empty():
		_log("invite from %s declined" % str(pending_invite.get("inviter", "?")))
	pending_invite = {}


## A cast row for the casts sheet (NetCasts): `fields` keyed by NetTelemetry.CAST_COLUMNS; t, role, from and seat are
## filled here. Written on this machine; a client's also goes to the host (tele.cast).
func note_cast(fields: Dictionary) -> void:
	if state != State.ONLINE:
		return
	var row := _row(NetTelemetry.CAST_COLUMNS, fields)
	if telemetry != null:
		telemetry.casts.write(row)
	if not hosting:
		wire.send_event(1, "tele.cast", {"row": row})


## A hero this machine owns took a hit (Actor.apply_damage through Net.note_hit): the `hits` column and the hits sheet.
func note_hit(a: Node, dealt: float, source: Node) -> void:
	if state != State.ONLINE or not Net.owns(a):
		return
	hits_taken += 1
	var seat := _seat_of_hero(a)
	if seat == 0:
		return
	var t := _tally_for(seat)
	t["hits"] = int(t["hits"]) + 1
	t["damage"] = float(t["damage"]) + dealt
	var src := source_kind(source)
	var by: Dictionary = t["sources"]
	by[src] = int(by.get(src, 0)) + 1


func _row(columns: Array[String], fields: Dictionary) -> Array:
	var e := local_entry()
	var base := {"t": "%.3f" % host_time(), "role": "host" if hosting else "client", "from": local_id(), "seat": int(e.get("seat", 0))}
	var row: Array = []
	for c in columns:
		row.append(fields.get(c, base.get(c, "")))
	return row


static func _seat_of_hero(a: Node) -> int:
	var id := NetFloor.id_of(a)
	return id if id >= 1 and id <= MAX_CREW else 0


## What hit a hero, for the hits sheet: a monster's kind ("swarmer"), "crew" for a teammate or a teammate's spell, else
## the node's class.
static func source_kind(source: Node) -> String:
	if source == null or not is_instance_valid(source):
		return "other"
	if source is Monster:
		return str((source as Monster).kind)
	if source is Hero:
		return "crew"
	var caster: Variant = source.get("caster")
	if caster is Hero:
		return "crew"
	return source.get_class().to_lower()


func _tally_for(seat: int) -> Dictionary:
	if not _tally.has(seat):
		_tally[seat] = {"hits": 0, "damage": 0.0, "floor_s": 0.0, "sources": {}}
	return _tally[seat]


## Every frame: the time each hero this machine owns spends standing on a running floor (the hits sheet's exposure).
func _count_exposure(dt: float) -> void:
	if flow == null or flow.phase != CrewFlow.FLOOR:
		return
	for seat in range(1, MAX_CREW + 1):
		var h := NetRegistry.hero(seat)
		if h != null and is_instance_valid(h) and not h.dead and Net.owns(h) and h.is_inside_tree():
			var t := _tally_for(seat)
			t["floor_s"] = float(t["floor_s"]) + dt


## The hits sheet's rows for the window that just ended (`send`: a client also files them on the host).
func _flush_hits(send: bool) -> void:
	_hits_minute += 1
	for seat: int in _tally.keys():
		var t: Dictionary = _tally[seat]
		var floor_s := float(t["floor_s"])
		if floor_s <= 0.0 and int(t["hits"]) == 0:
			continue
		var h := NetRegistry.hero(seat)
		var mine := seat == int(local_entry().get("seat", 0))
		var name_ := str(local_entry().get("name", "")) if mine else (str(h.display_name) if h != null and is_instance_valid(h) else "seat %d" % seat)
		var parts: PackedStringArray = []
		var by: Dictionary = t["sources"]
		for k: String in by:
			parts.append("%s:%d" % [k, int(by[k])])
		parts.sort()
		var fields := {"name": name_, "who": "player" if mine else "ai", "minute": _hits_minute, "floor_s": "%.1f" % floor_s,
			"hits": int(t["hits"]), "damage": "%.1f" % float(t["damage"]),
			"per_min": "%.2f" % (float(t["hits"]) * 60.0 / maxf(floor_s, 1.0)), "sources": ";".join(parts), "seat": seat}
		var row := _row(NetTelemetry.HIT_COLUMNS, fields)
		if telemetry != null:
			telemetry.hits.write(row)
		if hosting:
			_note_hits_total(local_id(), row)
		elif send:
			wire.send_event(1, "tele.hits", {"row": row})
	_tally.clear()


## Host: the session's running totals per player (from the hits rows: its own and the clients').
func _note_hits_total(peer: int, row: Array) -> void:
	var cols := NetTelemetry.HIT_COLUMNS
	var key := "%d:%s" % [peer, str(row[cols.find("seat")])]
	var tot: Dictionary = hits_totals.get(key, {"name": str(row[cols.find("name")]), "who": str(row[cols.find("who")]),
		"hits": 0, "damage": 0.0, "floor_s": 0.0})
	tot["hits"] = int(tot["hits"]) + int(row[cols.find("hits")])
	tot["damage"] = float(tot["damage"]) + float(row[cols.find("damage")])
	tot["floor_s"] = float(tot["floor_s"]) + float(row[cols.find("floor_s")])
	hits_totals[key] = tot


## Host, at the end: hits per minute per player for the whole session, one log line (the "keep them level" check).
func _print_hits_totals() -> void:
	if hits_totals.is_empty():
		return
	var parts: PackedStringArray = []
	for key: String in hits_totals:
		var tot: Dictionary = hits_totals[key]
		parts.append("%s (%s, seat %s) %.2f/min over %.1f min" % [str(tot["name"]), str(tot["who"]), key.get_slice(":", 1),
			float(tot["hits"]) * 60.0 / maxf(float(tot["floor_s"]), 1.0), float(tot["floor_s"]) / 60.0])
	_log("hits taken per minute this session: " + ", ".join(parts))


func _can_start() -> bool:
	if state != State.OFFLINE:
		push_warning("[Net] already in a session")
		return false
	last_reason = ""
	return true


func _begin_host(peer: MultiplayerPeer, via: Transport) -> void:
	_set_peer(peer)
	transport = via
	hosting = true
	crew_state = "board"
	roster.clear()
	refusals.clear()
	clock.start_host(Time.get_ticks_usec())
	wire.reset()
	_set_state(State.ONLINE, 0.0, "")
	roster[1] = {"peer": 1, "seat": 1, "name": _local_name(1), "character": local_character(), "steam_id": SteamIdentity.steam_id()}
	hits_totals.clear()
	_hits_minute = 0
	_next_hits_usec = 0
	_apply_link(str(GameSettings.load_settings()["link_sim"]) if link_from_settings else wire.link.preset)
	_open_telemetry()
	_publish_lobby()
	_log("hosting via %s" % ("steam" if via == Transport.STEAM else "enet"))
	status_changed.emit("Crew open. Waiting for the crew to clock in.")
	session_started.emit(true)
	roster_changed.emit()


func _set_peer(peer: MultiplayerPeer) -> void:
	var sm := multiplayer as SceneMultiplayer
	if sm != null:
		sm.server_relay = false   # clients only ever talk to the host
	multiplayer.multiplayer_peer = peer


func _set_state(s: State, timeout: float, status: String) -> void:
	state = s
	_deadline_usec = Time.get_ticks_usec() + int(timeout * 1e6) if timeout > 0.0 else 0
	if status != "":
		status_changed.emit(status)


## `close_now`: close the transport immediately (only safe outside its poll; the deferred close never runs
## while the process is quitting).
func _end(reason: String, close_now: bool = false) -> void:
	var was := state
	if was == State.ONLINE:
		_flush_hits(false)   # (the last window of the hits sheet; before the peer goes: the rows need this machine's seat)
		if hosting:
			_print_hits_totals()
	var peer := multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		# Deferred: _end often runs inside the peer's own poll (an RPC or a disconnect signal), and freeing the
		# peer there crashes the engine. Until then state is OFFLINE, so nothing it still delivers is used.
		if close_now:
			_close_peer(peer)
		else:
			_close_peer.call_deferred(peer)
	if _steam_link and SteamIdentity.steam() != null:
		NetSteamLink.apply(SteamIdentity.steam(), "off")
	_steam_link = false
	_tally.clear()
	pending_invite = {}
	lobby.leave()
	wire.reset()
	if telemetry != null:
		telemetry.close()
	telemetry = null
	state = State.OFFLINE
	transport = Transport.NONE
	hosting = false
	roster.clear()
	_pending.clear()
	_refused.clear()
	_last_heard.clear()
	_find_first = false
	_deadline_usec = 0
	last_reason = reason
	_log("session ended: %s (was %s)" % [reason, State.keys()[was]])
	session_ended.emit(reason)
	roster_changed.emit()
	status_changed.emit(reason)


func _close_peer(peer: MultiplayerPeer) -> void:
	if multiplayer.multiplayer_peer == peer:
		multiplayer.multiplayer_peer = null
	peer.close()


# --- Transport callbacks -----------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not hosting or state != State.ONLINE:
		return
	_tune_enet(id)
	_pending[id] = Time.get_ticks_usec()
	_last_heard[id] = Time.get_ticks_usec()
	wire.send_event(id, "sys.ask", {"protocol": protocol, "build": _build()})
	_log("peer %d connected, asking who it is" % id)


func _on_peer_disconnected(id: int) -> void:
	if hosting:
		_pending.erase(id)
		_refused.erase(id)
		_last_heard.erase(id)
		if roster.has(id):
			_drop(id, "left")
	elif id == 1 and state != State.OFFLINE:
		_end(HOST_LEFT)


func _on_connected_to_server() -> void:
	if state != State.CONNECTING:
		return
	_tune_enet(1)
	_last_heard[1] = Time.get_ticks_usec()
	_set_state(State.HELLO, HELLO_TIMEOUT, "Connected. Saying hello...")


## ENet throttles a connection whose round trips vary: it starts dropping UNRELIABLE packets on purpose (its congestion
## control). The lag link (NetLink, jitter) provokes exactly that, and it would hide behind the simulated loss; the
## snapshots of M2 are unreliable too. So the throttle is not allowed to fall: unreliable loss on ENet is the link's alone.
## (Steam has its own congestion control; this is the dev and test transport only.)
func _tune_enet(peer_id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var pp := enet.get_peer(peer_id)
	if pp != null:
		pp.throttle_configure(ENET_THROTTLE_INTERVAL_MS, ENET_THROTTLE_UP, 0)


func _on_connection_failed() -> void:
	if state != State.OFFLINE:
		_end(CONNECT_FAILED)


func _on_server_disconnected() -> void:
	if state == State.OFFLINE:
		return
	_end(HOST_LEFT if state == State.ONLINE or state == State.HELLO else CONNECT_FAILED)


# --- Steam lobby callbacks ---------------------------------------------------------------------------

func _on_lobby_created(lobby_id: int) -> void:
	if state != State.OPENING or not hosting:
		return
	var peer: Object = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer == null:
		_end("This build has no Steam transport")
		return
	peer.set("no_nagle", true)
	var err := int(peer.call("create_host", 0))
	if err != OK:
		_end("Steam couldn't host (error %d)" % err)
		return
	print("[Net] Steam lobby ", lobby_id, " open")
	_begin_host(peer as MultiplayerPeer, Transport.STEAM)


func _on_lobby_listed(lobbies: Array) -> void:
	if _probe and hosting:
		_finish_probe(lobbies)
		return
	if not _find_first or state != State.OPENING:
		return
	_find_first = false
	var version := SteamLobby.build_version()
	for id: Variant in lobbies:
		var lid := int(id)
		if lobby.get_data(lid, "version") == version and lobby.get_data(lid, "seats_free") != "0":
			status_changed.emit("Found %s. Joining..." % lobby.get_data(lid, "name"))
			lobby.join(lid)
			return
	_end(NO_CREWS)


func _on_lobby_joined(_lobby_id: int) -> void:
	if state != State.OPENING or hosting:
		return
	var host_steam := lobby.owner_id()
	var peer: Object = ClassDB.instantiate("SteamMultiplayerPeer")
	if host_steam == 0 or peer == null:
		_end(CONNECT_FAILED)
		return
	peer.set("no_nagle", true)
	var err := int(peer.call("create_client", host_steam, 0))
	if err != OK:
		_end("%s (Steam error %d)" % [CONNECT_FAILED, err])
		return
	_set_peer(peer as MultiplayerPeer)
	_set_state(State.CONNECTING, CONNECT_TIMEOUT, "Calling the crew...")


func _on_lobby_failed(reason: String) -> void:
	if _probe:
		print("[Net] steam probe FAILED: ", reason)
		get_tree().quit(1)
		return
	if state == State.OPENING:
		_end(reason)


## An overlay invite accepted while the game runs (M7). Already in that lobby: nothing to do. Otherwise the screen that
## is up asks the player (invite_received; the game shows "Leave this job and join?", the menu joins at once) and calls
## accept_invite() / decline_invite(). With nobody listening, it leaves whatever this is, joins and shows the menu.
func _on_invite(lobby_id: int, friend_id: int = 0) -> void:
	if lobby_id != 0 and lobby_id == lobby.lobby_id and state != State.OFFLINE:
		_log("invite to the lobby we are in: ignored")
		return
	var inviter := lobby.friend_name(friend_id)
	print("[Net] invite accepted in the overlay: lobby %d from %s" % [lobby_id, inviter if inviter != "" else "?"])
	pending_invite = {"lobby": lobby_id, "inviter": inviter}
	if not get_signal_connection_list("invite_received").is_empty():
		invite_received.emit(lobby_id, inviter)
		return
	accept_invite()
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path != Boot.MENU_SCENE:
		get_tree().change_scene_to_file.call_deferred(Boot.MENU_SCENE)


# --- Events ------------------------------------------------------------------------------------------

func _on_event(from: int, kind: String, data: Dictionary, stamp: float) -> void:
	if state == State.OFFLINE:
		return
	_last_heard[from] = Time.get_ticks_usec()
	if kind.begins_with("sys."):
		if hosting:
			_host_sys(from, kind, data)
		else:
			_client_sys(from, kind, data)
		return
	if state != State.ONLINE or (hosting and not roster.has(from)) or (not hosting and from != 1):
		return
	if kind.begins_with("tele."):
		_host_tele(from, kind, data)
		return
	Net.apply_begin()   # (M4c: what an event changes on a copy is the owner's word; the debug guard lets it)
	event_received.emit(from, kind, data, stamp)
	Net.apply_end()


func _host_sys(from: int, kind: String, data: Dictionary) -> void:
	if kind != "sys.hello" or not _pending.has(from):
		return
	_pending.erase(from)
	var name_ := str(data.get("name", ""))
	var their_build := str(data.get("build", ""))
	if int(data.get("protocol", -1)) != protocol or their_build != _build():
		_refuse(from, name_, "%s (crew on %s, you on %s)" % [DIFFERENT_BUILD, _build(), their_build])
		return
	if roster.size() >= MAX_CREW:
		_refuse(from, name_, CREW_FULL)
		return
	var character := str(data.get("character", DEFAULT_CHARACTER))
	var seat := 1
	var taken: Array[int] = []
	for e: Dictionary in roster.values():
		taken.append(int(e["seat"]))
	while taken.has(seat):
		seat += 1
	# M6: mid-job the joiner takes one of the AI's seats (the plan's order when a floor is running; NetJoin decides again
	# when it sends the joiner onto a floor, so the order is applied at the moment the seat changes hands).
	var joining := crew_state == "job"
	if joining and seats != null:
		var free: Array = []
		for s in range(1, MAX_CREW + 1):
			if not taken.has(s):
				free.append(s)
		var chosen := seats.choose_seat(character, free)
		if chosen != 0:
			seat = chosen
	if name_ == "":
		name_ = "Crew %d" % seat
	roster[from] = {"peer": from, "seat": seat, "name": name_, "character": character,
		"steam_id": int(data.get("steam_id", 0))}
	if joining:
		roster[from]["joining"] = true
	wire.send_event(from, "sys.welcome", {"seat": seat, "peer": from, "entries": crew(),
		"host_unix": Time.get_unix_time_from_system() - host_time(), "link": link_preset})
	_to_crew("sys.roster", {"entries": crew()})
	_publish_lobby()
	_log("%s clocked in (peer %d, seat %d%s)" % [name_, from, seat, ", joining the job" if joining else ""])
	status_changed.emit("%s clocked in." % name_)
	peer_joined.emit(from)
	roster_changed.emit()


## Host: a client's sheet row (M7): filed in the host's casts / hits sheet under the transport's peer id.
func _host_tele(from: int, kind: String, data: Dictionary) -> void:
	if not hosting:
		return
	var row: Variant = data.get("row")
	if not (row is Array):
		return
	match kind:
		"tele.cast":
			if telemetry != null:
				telemetry.casts.write_peer(from, row as Array)
		"tele.hits":
			if telemetry != null:
				telemetry.hits.write_peer(from, row as Array)
			if (row as Array).size() == NetTelemetry.HIT_COLUMNS.size():
				_note_hits_total(from, row as Array)


## Host: an event to every client in the roster (one send each: a broadcast would also reach peers still
## saying hello, or being refused, which must not see the crew).
func _to_crew(kind: String, data: Dictionary) -> void:
	for p: int in roster:
		if p != 1:
			wire.send_event(p, kind, data)


func _refuse(peer: int, name_: String, reason: String) -> void:
	refusals.append({"peer": peer, "name": name_, "reason": reason})
	wire.send_event(peer, "sys.refuse", {"reason": reason})
	wire.flush()
	_refused[peer] = Time.get_ticks_usec() + int(REFUSE_GRACE * 1e6)
	_log("refused %s (peer %d): %s" % [name_, peer, reason])


func _drop(peer: int, why: String) -> void:
	var e: Dictionary = roster[peer]
	roster.erase(peer)
	_to_crew("sys.roster", {"entries": crew()})
	_publish_lobby()
	_log("%s %s (peer %d)" % [str(e["name"]), why, peer])
	status_changed.emit("%s clocked out." % str(e["name"]))
	peer_left.emit(peer)
	roster_changed.emit()


func _client_sys(from: int, kind: String, data: Dictionary) -> void:
	if from != 1:
		return
	match kind:
		"sys.ask":
			if state == State.HELLO or state == State.CONNECTING:
				wire.send_event(1, "sys.hello", {"protocol": protocol, "build": _build(), "name": player_name if player_name != "" else SteamIdentity.player_name(""),
					"character": local_character(), "steam_id": SteamIdentity.steam_id()})
		"sys.welcome":
			if state == State.ONLINE:
				return
			host_unix_epoch = float(data.get("host_unix", 0.0))
			_set_roster(data.get("entries", []) as Array)
			_apply_link(str(data.get("link", link_preset)))
			_hits_minute = 0
			_next_hits_usec = 0
			clock.start_client(Time.get_ticks_usec())
			_pings_sent = 0
			_next_ping_usec = 0
			_set_state(State.ONLINE, 0.0, "")
			_open_telemetry()
			_log("welcomed: seat %d as peer %d" % [int(data.get("seat", 0)), local_id()])
			status_changed.emit("Connected to %s's crew." % host_name())
			session_started.emit(false)
			roster_changed.emit()
		"sys.roster":
			if state == State.ONLINE:
				_set_roster(data.get("entries", []) as Array)
				roster_changed.emit()
		"sys.link":
			if state == State.ONLINE:
				_apply_link(str(data.get("preset", "off")))
		"sys.refuse":
			_end(str(data.get("reason", CONNECT_FAILED)))
		"sys.bye":
			_end(HOST_LEFT)


func _set_roster(entries: Array) -> void:
	roster.clear()
	for e: Variant in entries:
		var d := e as Dictionary
		roster[int(d["peer"])] = d


# --- Packets -----------------------------------------------------------------------------------------

func _on_packet(from: int, type: int, seq: int, stamp_ms: int, payload: PackedByteArray) -> void:
	if state == State.OFFLINE:
		return
	_last_heard[from] = Time.get_ticks_usec()
	if state != State.ONLINE:
		return
	match type:
		NetWire.T_PING:
			if hosting and roster.has(from) and payload.size() >= 8:
				var out := StreamPeerBuffer.new()
				out.put_u64(payload.decode_u64(0))
				out.put_double(host_time())
				wire.send_packet(from, NetWire.T_PONG, out.data_array)
				wire.flush()
		NetWire.T_PONG:
			if not hosting and from == 1 and payload.size() >= 16:
				clock.add_sample(payload.decode_u64(0), payload.decode_double(8), Time.get_ticks_usec())
		NetWire.T_ROW:
			if hosting and telemetry != null and roster.has(from):
				var row: Variant = bytes_to_var(payload)
				if row is Array:
					telemetry.note_peer_row(from, row as Array)
		_:
			if hosting and not roster.has(from):
				return
			Net.apply_begin()   # (M4c: the net layer applies an owner's state to copies; the debug guard lets it)
			packet_received.emit(from, type, seq, stamp_ms, payload)
			Net.apply_end()


# --- Every frame -------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if state == State.OFFLINE:
		_last_frame_usec = 0
		return
	var now := Time.get_ticks_usec()
	clock.advance(now)
	if state == State.ONLINE:
		if _last_frame_usec > 0:
			_count_exposure(float(now - _last_frame_usec) / 1e6)
		_last_frame_usec = now
		if _next_hits_usec == 0:
			_next_hits_usec = now + int(hits_window * 1e6)
		elif now >= _next_hits_usec:
			_next_hits_usec = now + int(hits_window * 1e6)
			_flush_hits(true)
	if _deadline_usec > 0 and now > _deadline_usec and state != State.ONLINE:
		match state:
			State.OPENING: _end("Steam didn't answer")
			State.CONNECTING: _end(CONNECT_FAILED)
			_: _end(NO_ANSWER)
		return
	if state != State.ONLINE:
		return
	if hosting:
		_host_watch(now)
	else:
		if now - int(_last_heard.get(1, now)) > int(HOST_SILENCE * 1e6):
			_end(HOST_LEFT)
			return
		if now >= _next_ping_usec:
			var buf := StreamPeerBuffer.new()
			buf.put_u64(now)
			wire.send_packet(1, NetWire.T_PING, buf.data_array)
			wire.flush()
			_pings_sent += 1
			_next_ping_usec = now + int(NetClock.ping_interval(_pings_sent) * 1e6)
	if telemetry != null and now >= _next_row_usec:
		_next_row_usec = now + 1000000
		_telemetry_row()


func _host_watch(now: int) -> void:
	var peer := multiplayer.multiplayer_peer
	for id: int in _pending.keys():
		if now - int(_pending[id]) > int(HELLO_TIMEOUT * 1e6):
			_pending.erase(id)
			peer.disconnect_peer(id)
	for id: int in _refused.keys():
		if now > int(_refused[id]):
			_refused.erase(id)
			peer.disconnect_peer(id)
	for id: int in roster.keys():
		if id != 1 and now - int(_last_heard.get(id, now)) > int(CLIENT_SILENCE * 1e6):
			_drop(id, "went silent")
			peer.disconnect_peer(id)


# --- Telemetry ---------------------------------------------------------------------------------------

func _open_telemetry() -> void:
	if not telemetry_enabled:
		return
	telemetry = NetTelemetry.new()
	telemetry.dir = telemetry_dir
	if not telemetry.open("host" if hosting else "client"):
		telemetry = null
	_next_row_usec = Time.get_ticks_usec() + 1000000


func _telemetry_row() -> void:
	var c := wire.take_counters()
	var arrived := int(c["packets_in"])
	var expected := arrived + maxi(int(c["gaps"]) - int(c["stale"]), 0)
	var e := local_entry()
	var row: Array = [
		"%.3f" % host_time(), "host" if hosting else "client", local_id(), int(e.get("seat", 0)), roster.size(),
		"" if hosting else "%.1f" % clock.rtt_ms, "" if hosting else "%.1f" % clock.rtt_min_ms,
		"" if hosting else "%.1f" % clock.jitter_ms, "" if hosting else "%.2f" % clock.pending_correction_ms(),
		"%.3f" % (float(arrived) / float(expected) if expected > 0 else 1.0),
		c["bytes_out"], c["bytes_in"], c["packets_out"], c["packets_in"], c["events_out"], c["events_in"], c["gaps"], c["stale"],
		link_preset, wire.link.held(), wire.link.dropped, "", hits_taken,
	]
	hits_taken = 0
	telemetry.write_row(row)
	if not hosting:
		wire.send_packet(1, NetWire.T_ROW, var_to_bytes(row))


# --- Lobby data, names, flags ------------------------------------------------------------------------

## Seats a joiner could still take (M6: every member holds a seat, the rest are the AI's): what the lobby publishes, so
## "Join a crew" only finds crews with an AI seat left; 0 = the crew is full.
func seats_free() -> int:
	return maxi(MAX_CREW - roster.size(), 0)


func _publish_lobby() -> void:
	if transport != Transport.STEAM or not hosting:
		return
	lobby.set_data("seats_free", str(seats_free()))
	lobby.set_data("state", crew_state)


func _local_name(seat: int) -> String:
	if player_name != "":
		return player_name
	var steam_name := SteamIdentity.player_name("")
	return steam_name if steam_name != "" else "Crew %d" % seat


func _build() -> String:
	return build if build != "" else SteamLobby.build_version()


func _apply_flags(args: PackedStringArray, engine_args: PackedStringArray) -> void:
	var link := Boot.arg_value(args, "--net-link")
	if link != "" and not wire.link.configure(link):
		push_warning("[Net] unknown --net-link %s (off, coast, rough)" % link)
	# The crew's link comes from Settings > Diagnostics unless a dev flag (or a test) sets it (M7).
	link_from_settings = link == "" and not args.has("--run-test")
	wire.link.seed_with(OS.get_process_id())
	var name_ := Boot.arg_value(args, "--net-name")
	if name_ != "":
		player_name = name_
	if args.has("--run-test"):
		return   # tests drive the session themselves (NetTest)
	var port_s := Boot.arg_value(args, "--net-port")
	var port := int(port_s) if port_s.is_valid_int() else DEFAULT_PORT
	if args.has("--net-steam-probe"):
		_steam_probe()
	elif args.has("--net-host"):
		host_enet(port)
	elif Boot.arg_value(args, "--net-join") != "":
		var target := Boot.arg_value(args, "--net-join")
		var addr := target
		if target.contains(":"):
			addr = target.get_slice(":", 0)
			port = int(target.get_slice(":", 1))
		join_enet(addr, port)
	else:
		var invite := SteamLobby.connect_lobby_arg(engine_args)
		if invite == 0:
			invite = SteamLobby.connect_lobby_arg(args)
		if invite != 0:
			join_lobby(invite)


## The manual Steam check (README "Online play"): host through the real path (host_steam: lobby, lobby data,
## SteamMultiplayerPeer host, roster), ask Steam for the lobby list with Join a crew's filters (our own lobby
## should be in it), then leave and quit. One lobby, a few seconds.
func _steam_probe() -> void:
	_probe = true
	if not SteamIdentity.available():
		print("[Net] steam probe FAILED: Steam not available")
		get_tree().quit(1)
		return
	print("[Net] steam probe: hosting as ", SteamIdentity.player_name("?"))
	session_started.connect(func(_as_host: bool) -> void:
		print("[Net] steam probe: hosting via steam, lobby %d, roster %s" % [lobby.lobby_id, str(crew())])
		lobby.request_list())
	session_ended.connect(func(reason: String) -> void:
		if _probe:
			print("[Net] steam probe FAILED: ", reason)
			get_tree().quit(1))
	telemetry_enabled = false
	host_steam()
	get_tree().create_timer(OPEN_TIMEOUT * 2.0).timeout.connect(func() -> void:
		print("[Net] steam probe FAILED: timed out")
		get_tree().quit(1))


func _finish_probe(lobbies: Array) -> void:
	var id := lobby.lobby_id
	var data := {}
	for k in ["name", "game", "version", "protocol", "seats_free", "state"]:
		data[k] = lobby.get_data(id, k)
	var listed := lobbies.map(func(v: Variant) -> int: return int(v)).has(id)
	print("[Net] steam probe OK: lobby %d owned by %d (me %d), data %s; the Join list (%d lobbies) %s it" % [
		id, lobby.owner_id(), SteamIdentity.steam_id(), str(data), lobbies.size(), "includes" if listed else "does NOT include"])
	_probe = false
	leave()
	get_tree().create_timer(0.5).timeout.connect(func() -> void: get_tree().quit(0))


func _log(msg: String) -> void:
	print("[Net] ", msg)
