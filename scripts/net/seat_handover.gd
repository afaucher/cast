class_name SeatHandover
extends Node
## Who owns each crew seat's hero, and what happens when an owner leaves (docs/design/networking-build-plan.md
## M2b; M6 builds the other direction, an AI seat handed to a joiner, on the same table).
##
## owners: seat -> the peer whose machine owns that seat's hero, or 0 for an AI hero (the host owns those). The game
## fills it when the floor is built (begin()) from the roster.
##
## A PLAYER DROPS (the host sees `peer_left`):
##   1. the seat's owner becomes 0 and its epoch goes up (a stale state from the old owner is ignored);
##   2. NetSnapshot lets go of the puppet: the hero stops being a copy and stands where the last snapshot left it
##      (position, HP, downed);
##   3. `to_ai(seat, character)` fires on the host and the game re-kits that hero node in place as the seat's
##      ORIGINAL character (the Rebar or Gasket the seat started as) and attaches an AllyBrain;
##   4. the host tells every client in a reliable event (`seat.ai {seat, character, epoch}`), whose `to_ai` makes
##      the same re-kit on their screens (the hero stays a puppet there: the host streams it from now on).
## The hero node and its net id never change, so followers, HUD rows and every reference to it stay valid.
##
## A player who left BEFORE the floor's barrier (during the license checkout) has no hero state to hand over: the
## game converts that seat itself when it builds the table (game.gd `_drop_departed_seats`), identically on every
## machine, so the floor checksum still agrees. The table starts at the barrier (begin()), not at the roster.

## The game re-kits `seat`'s hero as `character`. On the host it also attaches the AllyBrain (Net.is_host()).
signal to_ai(seat: int, character: String)

var owners: Dictionary = {}       ## seat -> peer (0 = AI)
var originals: Dictionary = {}    ## seat -> the character an AI plays in that seat
var epoch: Dictionary = {}        ## seat -> int, up at every handover
## Every handover this machine has seen: [{seat, peer, character, epoch, t}] (tests and logs).
var history: Array = []

var _session: NetSession = null


func _ready() -> void:
	_session = get_parent() as NetSession
	if _session == null:
		return
	_session.peer_left.connect(_on_peer_left)
	_session.event_received.connect(_on_event)
	_session.session_ended.connect(func(_reason: String) -> void: reset())
	_session.session_started.connect(func(_as_host: bool) -> void: reset())


func reset() -> void:
	owners = {}
	originals = {}
	epoch = {}
	history = []


## The floor's seats: `owners` (seat -> peer, 0 for AI) and `originals` (seat -> the AI character for that seat).
func begin(new_owners: Dictionary, new_originals: Dictionary) -> void:
	owners = new_owners.duplicate()
	originals = new_originals.duplicate()
	epoch = {}
	for seat: int in owners:
		epoch[seat] = 0


func owner_of(seat: int) -> int:
	return int(owners.get(seat, 0))


## The seat a peer's hero sits in, 0 if it has none.
func seat_of(peer: int) -> int:
	for seat: int in owners:
		if int(owners[seat]) == peer and peer != 0:
			return seat
	return 0


func epoch_of(seat: int) -> int:
	return int(epoch.get(seat, 0))


## Host: the player in `seat` is gone (also the seam tests use). Does nothing on a client or for an AI seat.
func release(seat: int) -> void:
	if _session == null or not _session.hosting or not owners.has(seat) or owner_of(seat) == 0:
		return
	var peer := owner_of(seat)
	var character := str(originals.get(seat, NetSession.DEFAULT_CHARACTER))
	owners[seat] = 0
	epoch[seat] = epoch_of(seat) + 1
	if _session.snap != null:
		_session.snap.seat_released(seat)
	history.append({"seat": seat, "peer": peer, "character": character, "epoch": epoch_of(seat), "t": _session.host_time()})
	print("[Net] seat %d: peer %d is gone, the AI plays %s (epoch %d)" % [seat, peer, character, epoch_of(seat)])
	to_ai.emit(seat, character)
	_session.send_event(0, NetEvents.KIND_SEAT_AI, {"seat": seat, "character": character, "epoch": epoch_of(seat)})


func _on_peer_left(peer: int) -> void:
	if _session != null and _session.hosting:
		var seat := seat_of(peer)
		if seat != 0:
			release(seat)


func _on_event(from: int, kind: String, data: Dictionary, _stamp: float) -> void:
	if kind != NetEvents.KIND_SEAT_AI or _session == null or _session.hosting or from != 1:
		return
	var seat := int(data.get("seat", 0))
	if not owners.has(seat) or int(data.get("epoch", 0)) <= epoch_of(seat):
		return
	var character := str(data.get("character", NetSession.DEFAULT_CHARACTER))
	owners[seat] = 0
	epoch[seat] = int(data["epoch"])
	history.append({"seat": seat, "peer": 0, "character": character, "epoch": epoch_of(seat), "t": _session.host_time()})
	to_ai.emit(seat, character)
