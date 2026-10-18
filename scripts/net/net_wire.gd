class_name NetWire
extends Node
## The two channels every message rides (networking.md "Day-one infrastructure" item 1), as the child "Wire"
## of the Session autoload, so its RPC path (/root/Session/Wire) survives every scene reload:
##
## - EVENTS: one reliable RPC, `_ev(kind, data, stamp)`, on a channel of its own (EVENT_CHANNEL). One-shot
##   decisions (hello, roster, casts, hits, deaths...) go here. Ordered, never lost.
## - PACKETS: `send_bytes` with TRANSFER_MODE_UNRELIABLE and our own 7-byte header
##       u8 type | u16 sequence | u32 stamp (host_time in ms)
##   Continuous state (clock pings, telemetry rows, and from M2 the snapshots) goes here. The receiver keeps
##   the newest sequence per (sender, type) and DROPS anything stale or duplicated, so a late packet is never
##   applied over a newer one. Never `unreliable_ordered`: GodotSteam sends that reliably (networking.md).
##
## Every inbound message passes through `link` (NetLink), which simulates lag and loss when configured.
## Counters for telemetry are kept here, at the lines that send and receive.

signal event_received(from: int, kind: String, data: Dictionary, stamp: float)
signal packet_received(from: int, type: int, seq: int, stamp_ms: int, payload: PackedByteArray)

const EVENT_CHANNEL := 1
const PACKET_CHANNEL := 2
const HEADER := 7

## Packet types. 1-15 are the session's own; gameplay streams (snapshots, M2+) take 16 and up.
const T_PING := 1
const T_PONG := 2
const T_ROW := 3          ## a client's telemetry row for the host's file
const T_SNAP := 16        ## hero snapshots (M2: NetCodec, NetSnapshot; M3 appends the world); the M0 tests stream numbered dummies on it
const T_TEST := 15        ## tests only

var link := NetLink.new()
## Where the stamp comes from (NetSession sets it to its host_time()).
var clock_source := Callable()

## Counters since the last take_counters().
var bytes_out := 0
var bytes_in := 0
var packets_out := 0
var packets_in := 0        ## accepted packets
var events_out := 0
var events_in := 0
var gaps := 0              ## sequence numbers skipped at acceptance (lost or not yet arrived)
var stale := 0             ## packets dropped as older than (or equal to) the newest seen

## Since reset(), per packet type: [accepted, stale, gaps] (never zeroed by take_counters; tests read it).
var type_stats: Dictionary = {}

var _next_seq: Dictionary = {}     ## (type << 32 | to) -> next sequence number
var _last_seq: Dictionary = {}     ## (type << 32 | from) -> newest accepted sequence number


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_packet.connect(_on_peer_packet)


func _process(_delta: float) -> void:
	if not link.is_active() and link.held() == 0:
		return
	for item: Array in link.pop_due(Time.get_ticks_usec()):
		_deliver(item)


## Forget every sequence stream (a new session).
func reset() -> void:
	_next_seq.clear()
	_last_seq.clear()
	type_stats.clear()
	link.clear()
	take_counters()


## Zero the counters and return them.
func take_counters() -> Dictionary:
	var c := {"bytes_out": bytes_out, "bytes_in": bytes_in, "packets_out": packets_out, "packets_in": packets_in,
		"events_out": events_out, "events_in": events_in, "gaps": gaps, "stale": stale}
	bytes_out = 0
	bytes_in = 0
	packets_out = 0
	packets_in = 0
	events_out = 0
	events_in = 0
	gaps = 0
	stale = 0
	return c


# --- Events (reliable) --------------------------------------------------------------------------------

## Send a reliable event to one peer, or to everyone (to = 0).
func send_event(to: int, kind: String, data: Dictionary = {}) -> void:
	if not _online() or not _reachable(to):
		return
	var stamp := _stamp()
	bytes_out += var_to_bytes([kind, data, stamp]).size()
	events_out += 1
	if to == 0:
		_ev.rpc(kind, data, stamp)
	else:
		_ev.rpc_id(to, kind, data, stamp)


@rpc("any_peer", "call_remote", "reliable", EVENT_CHANNEL)
func _ev(kind: String, data: Dictionary, stamp: float) -> void:
	var from := multiplayer.get_remote_sender_id()
	bytes_in += var_to_bytes([kind, data, stamp]).size()
	var item: Array = [0, from, kind, data, stamp]
	if link.is_active():
		link.push_reliable(Time.get_ticks_usec(), item)
	else:
		_deliver(item)


# --- Packets (unreliable, sequenced) -------------------------------------------------------------------

## Send an unreliable packet of `type` to one peer, or to everyone (to = 0). Use one target style per type:
## the receiver keeps one sequence stream per (sender, type).
func send_packet(to: int, type: int, payload: PackedByteArray) -> int:
	if not _online() or not _reachable(to):
		return -1
	var key := (type << 32) | (to & 0xFFFFFFFF)
	var seq: int = int(_next_seq.get(key, 0))
	_next_seq[key] = (seq + 1) & 0xFFFF
	var buf := StreamPeerBuffer.new()
	buf.put_u8(type)
	buf.put_u16(seq)
	buf.put_u32(int(_stamp() * 1000.0) & 0xFFFFFFFF)
	buf.put_data(payload)
	var bytes := buf.data_array
	bytes_out += bytes.size()
	packets_out += 1
	(multiplayer as SceneMultiplayer).send_bytes(bytes, to, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, PACKET_CHANNEL)
	return seq


## Push queued packets onto the socket now instead of at the next poll (ENet; Steam sends on its own). The
## clock pings use it so a frame of queueing doesn't sit inside the measured round trip.
func flush() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer and (peer as ENetMultiplayerPeer).host != null:
		(peer as ENetMultiplayerPeer).host.flush()


## Start a type's outgoing sequence at `seq` (tests use it to cross the u16 wrap).
func set_next_seq(to: int, type: int, seq: int) -> void:
	_next_seq[(type << 32) | (to & 0xFFFFFFFF)] = seq & 0xFFFF


func _on_peer_packet(from: int, bytes: PackedByteArray) -> void:
	if bytes.size() < HEADER:
		return
	bytes_in += bytes.size()
	var item: Array = [1, from, bytes]
	if link.is_active():
		link.push_unreliable(Time.get_ticks_usec(), item)
	else:
		_deliver(item)


## True when `a` is newer than `b` on a u16 sequence that wraps.
static func seq_newer(a: int, b: int) -> bool:
	var d := (a - b) & 0xFFFF
	return d != 0 and d < 0x8000


func _accept_packet(from: int, bytes: PackedByteArray) -> void:
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var type := buf.get_u8()
	var seq := buf.get_u16()
	var stamp_ms := buf.get_u32()
	var key := (type << 32) | (from & 0xFFFFFFFF)
	if not type_stats.has(type):
		type_stats[type] = [0, 0, 0]
	var ts: Array = type_stats[type]
	if _last_seq.has(key):
		var last: int = _last_seq[key]
		if not seq_newer(seq, last):
			stale += 1
			ts[1] = int(ts[1]) + 1
			return
		var skipped := ((seq - last) & 0xFFFF) - 1
		gaps += skipped
		ts[2] = int(ts[2]) + skipped
	_last_seq[key] = seq
	packets_in += 1
	ts[0] = int(ts[0]) + 1
	packet_received.emit(from, type, seq, stamp_ms, bytes.slice(HEADER))


func _deliver(item: Array) -> void:
	if int(item[0]) == 0:
		events_in += 1
		event_received.emit(int(item[1]), str(item[2]), item[3] as Dictionary, float(item[4]))
	else:
		_accept_packet(int(item[1]), item[2] as PackedByteArray)


func _stamp() -> float:
	return float(clock_source.call()) if clock_source.is_valid() else 0.0


## A specific target must still be connected: the link simulator can release a message from a peer that has
## since left, and answering it would send to nobody.
func _reachable(to: int) -> bool:
	return to == 0 or multiplayer.get_peers().has(to)


func _online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer) \
			and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
