class_name NetSnapshot
extends Node
## Hero sync (docs/design/networking-build-plan.md M2): every machine OWNS its own seat's hero and streams it, and
## shows everyone else's as a PUPPET. Child "Snap" of the Session autoload, so it survives scene reloads.
##
## OWNERSHIP
##   - the local player's hero is simulated here, as ever (its PlayerController); no input crosses the wire;
##   - on the HOST the heroes of empty seats are simulated here too (AllyBrain) and streamed;
##   - every other hero is a puppet (Net.make_puppet): no controller, no AI, no damage, no shoves. It applies the
##     interpolated state it is sent and keeps animating (the model tracks its own walk from the movement).
##
## STREAMING (NetWire.T_SNAP, unreliable, sequence-numbered; NetCodec has the bytes)
##   client -> host   30 Hz: its own hero (24 bytes);
##   host -> client   30 Hz: every hero but that client's own: the host's, the AI ones (live), and the OTHER clients'
##                    (the newest state received, forwarded with its age so every sample keeps its original moment
##                    on the shared clock). Clients only talk to the host.
##
## SHOWING (NetInterp): a puppet renders `delay` behind host_time() (100 ms or more, adaptive), Hermite on position
## and velocity between two samples, a step for hp/dead/the bow, and a teleport (the sample's counter changed)
## never blends across the gap.
##
## The game calls begin() when the floor is built and set_active() at the shared start (and once its own van
## arrival is over: the arrival places the heroes itself). Nothing here knows about game.gd.
##
## M3: the host's packets to a client carry the world after the heroes (NetWorld.section, NetWorldCodec), and a client
## hands that part to NetWorld; set_active() switches the world's stream with the heroes'.

const SEND_RATE := 30.0
const SEND_INTERVAL := 1.0 / SEND_RATE
const TELEPORT_DIST := 3.0        ## a hero that moves farther than this between two physics frames jumped
const FORWARD_MAX_AGE := 0.3      ## a client's state older than this is not forwarded (it stopped sending)
const AI_AIM_AHEAD := 4.0         ## an AI hero "aims" this far in front of it
const LEAD_MAX := 0.25            ## M3a: a monster leads a remote hero by at most this much of its velocity

## Tracks a hero this machine streams (physics-frame velocity and the teleport counter).
class Track extends RefCounted:
	var hero: Hero
	var last_pos := Vector3.INF
	var sent_pos := Vector3.INF     ## where the last sample was taken (a jump from it is a teleport)
	var vel := Vector2.ZERO
	var tp := 0


## A puppet: the hero node and the buffer it is shown from.
class Puppet extends RefCounted:
	var hero: Hero
	var interp := NetInterp.new()
	var render_t := 0.0
	var shown: NetHeroState = null
	var applied := false


## Streaming and showing are on (the floor has started and this machine's own van arrival is over).
var active := false
var local_seat := 0
## Counters (tests and the report): packets and bytes sent and received on T_SNAP, entries refused as not newer.
var stats := {"out_packets": 0, "out_bytes": 0, "out_max": 0, "world_out_bytes": 0, "packet_max": 0, "in_world_bytes": 0, "in_packets": 0, "in_bytes": 0, "in_entries": 0,
	"in_foreign": 0, "in_stale_epoch": 0, "since": 0.0}

var _session: NetSession = null
var _live: Dictionary = {}        ## seat -> Track (heroes this machine owns and streams)
var _puppets: Dictionary = {}     ## seat -> Puppet
var _next_send := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session = get_parent() as NetSession
	if _session == null:
		return
	_session.packet_received.connect(_on_packet)
	_session.session_ended.connect(func(_reason: String) -> void: end())


# --- Setup -----------------------------------------------------------------------------------------------

## The floor is built (ids assigned, SeatHandover.begin() done): decide each seat's role. `heroes_by_seat` is
## seat -> Hero, `own_seat` the seat this machine's player controls.
func begin(heroes_by_seat: Dictionary, own_seat: int) -> void:
	end()
	if _session == null or not _session.online():
		return
	local_seat = own_seat
	for seat: int in heroes_by_seat:
		var hero := heroes_by_seat[seat] as Hero
		if hero == null:
			continue
		if seat == own_seat or (_session.hosting and _session.seats.owner_of(seat) == 0):
			var tr := Track.new()
			tr.hero = hero
			_live[seat] = tr
		else:
			Net.make_puppet(hero)
			var pp := Puppet.new()
			pp.hero = hero
			_puppets[seat] = pp
	_reset_stats()


func _reset_stats() -> void:
	stats = {"out_packets": 0, "out_bytes": 0, "out_max": 0, "world_out_bytes": 0, "packet_max": 0, "in_world_bytes": 0, "in_packets": 0, "in_bytes": 0, "in_entries": 0, "in_foreign": 0,
		"in_stale_epoch": 0, "since": _now()}


## Forget the floor (the scene is going, or the session ended).
func end() -> void:
	active = false
	_live.clear()
	_puppets.clear()
	local_seat = 0


## Start or stop streaming and showing. Turning it on starts the sender's tracking afresh and makes the first
## frame of every puppet a jump (the van arrival put them somewhere else a moment ago).
func set_active(on: bool) -> void:
	if _session != null and _session.world != null:
		_session.world.set_active(on)   # (M3: the host-owned world rides in the same packets)
	if on == active:
		return
	active = on
	if not on:
		return
	_next_send = _now()
	_reset_stats()   # (the byte counters measure the streaming itself)
	for seat: int in _live:
		var tr: Track = _live[seat]
		tr.last_pos = Vector3.INF
		tr.sent_pos = Vector3.INF
		tr.vel = Vector2.ZERO
	for seat: int in _puppets:
		(_puppets[seat] as Puppet).applied = false


## M6: `seat` changed hands to `peer` (SeatHandover.take / take_local / seat.take). On the joiner (peer is this machine) the
## puppet becomes its own live hero; on the host the AI's live hero becomes a puppet of the joiner's stream; anywhere else
## the puppet stays a puppet and forgets the old owner's samples (the epoch already drops any still on their way).
func seat_taken(seat: int, peer: int) -> void:
	if _session == null:
		return
	if peer == _session.local_id():
		var pp: Puppet = _puppets.get(seat)
		_puppets.erase(seat)
		var hero: Hero = pp.hero if pp != null else NetRegistry.hero(seat)
		if hero == null or not is_instance_valid(hero):
			return
		Net.release_copy(hero)
		hero.reset_physics_interpolation()
		var tr := Track.new()
		tr.hero = hero
		_live[seat] = tr
		local_seat = seat
		return
	if _live.has(seat):
		var tr: Track = _live[seat]
		_live.erase(seat)
		if not is_instance_valid(tr.hero):
			return
		Net.make_puppet(tr.hero)
		var pp := Puppet.new()
		pp.hero = tr.hero
		_puppets[seat] = pp
		return
	var old: Puppet = _puppets.get(seat)
	if old != null:
		old.interp.clear()
		old.applied = false


## Host: the player of `seat` left (SeatHandover). The puppet becomes a live hero at the last state received: it
## stands there, acts again (the game attaches the AI), and is streamed to the clients from now on.
func seat_released(seat: int) -> void:
	if not _puppets.has(seat):
		return
	var pp: Puppet = _puppets[seat]
	_puppets.erase(seat)
	var hero := pp.hero
	if not is_instance_valid(hero):
		return
	var last := pp.interp.newest()
	if last != null:
		Net.apply_begin()
		NetCodec.write_hero(hero, last)
		Net.apply_end()
		hero.reset_physics_interpolation()
	Net.release_copy(hero)
	var tr := Track.new()
	tr.hero = hero
	_live[seat] = tr


# --- Asking ------------------------------------------------------------------------------------------------

func is_puppet(seat: int) -> bool:
	return _puppets.has(seat)


## The seats shown as puppets here, and the seats this machine streams (its own, plus the AI's on the host).
func puppet_seats() -> Array[int]:
	var out: Array[int] = []
	for seat: int in _puppets:
		out.append(seat)
	out.sort()
	return out


func live_seats() -> Array[int]:
	var out: Array[int] = []
	for seat: int in _live:
		out.append(seat)
	out.sort()
	return out


func is_live(seat: int) -> bool:
	return _live.has(seat)


func puppet(seat: int) -> Puppet:
	return _puppets.get(seat) as Puppet


## The shared-clock time the puppet in `seat` is showing right now (0 before its first sample).
func render_time(seat: int) -> float:
	var pp := puppet(seat)
	return pp.render_t if pp != null else 0.0


func delay_of(seat: int) -> float:
	var pp := puppet(seat)
	return pp.interp.delay if pp != null else NetInterp.DELAY



## Where the hero in a puppet seat most likely is NOW (host, M3a: monsters aim here): the newest sample received,
## carried along its velocity for as long as that sample is old (at most LEAD_MAX). Vector3.INF without a sample.
func lead_point(seat: int) -> Vector3:
	var pp := puppet(seat)
	if pp == null:
		return Vector3.INF
	var newest := pp.interp.newest()
	if newest == null:
		return Vector3.INF
	var age := clampf(_now() - newest.t, 0.0, LEAD_MAX)
	return Vector3(newest.pos.x + newest.vel.x * age, pp.hero.global_position.y, newest.pos.z + newest.vel.y * age)




# --- Sampling the heroes this machine owns --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not active:
		return
	for seat: int in _live:
		var tr: Track = _live[seat]
		if not is_instance_valid(tr.hero):
			continue
		var p := tr.hero.global_position
		tr.vel = Vector2.ZERO
		if tr.last_pos != Vector3.INF:
			var d := p - tr.last_pos
			if Vector2(d.x, d.z).length() <= TELEPORT_DIST and absf(d.y) <= TELEPORT_DIST:
				tr.vel = Vector2(d.x, d.z) / maxf(delta, 0.0001)
		tr.last_pos = p


## The hero's state right now. A jump from where the last sample was taken is a TELEPORT: the counter goes up (decided
## here, at the moment of sampling, so no sample can carry the new place with the old counter) and the velocity is nothing.
func _live_state(seat: int, now: float) -> NetHeroState:
	var tr: Track = _live[seat]
	if not is_instance_valid(tr.hero):
		return null
	var st := NetHeroState.new()
	st.seat = seat
	st.t = now
	st.pos = tr.hero.global_position
	st.vel = tr.vel
	if tr.sent_pos != Vector3.INF and (Vector2(st.pos.x - tr.sent_pos.x, st.pos.z - tr.sent_pos.z).length() > TELEPORT_DIST or absf(st.pos.y - tr.sent_pos.y) > TELEPORT_DIST):
		tr.tp = (tr.tp + 1) & 15
		tr.vel = Vector2.ZERO
		st.vel = Vector2.ZERO
	tr.sent_pos = st.pos
	st.tp = tr.tp
	st.epoch = _session.seats.epoch_of(seat) & 15 if _session.seats != null else 0
	NetCodec.read_hero(tr.hero, st)
	var aim := _aim_of(tr) - st.pos
	st.aim = Vector2(clampf(aim.x, -NetCodec.AIM_MAX, NetCodec.AIM_MAX), clampf(aim.z, -NetCodec.AIM_MAX, NetCodec.AIM_MAX))
	return st


func _aim_of(tr: Track) -> Vector3:
	var pc := tr.hero.get_node_or_null("PlayerController") as PlayerController
	if pc != null:
		var a := pc.aim_point()
		if a != Vector3.INF:
			return a
	return tr.hero.global_position + tr.hero.facing * AI_AIM_AHEAD


# --- Every frame -----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not active or _session == null or not _session.online():
		return
	var now := _session.host_time()
	Net.apply_begin()   # (M4c: the puppets show their owners' state)
	_show_puppets(now, delta)
	Net.apply_end()
	if now >= _next_send:
		_next_send += SEND_INTERVAL
		if _next_send < now - SEND_INTERVAL:
			_next_send = now
		_send(now)


## Apply every puppet's state for this frame.
func _show_puppets(now: float, delta: float) -> void:
	for seat: int in _puppets:
		var pp: Puppet = _puppets[seat]
		if not is_instance_valid(pp.hero):
			continue
		pp.interp.step_delay(delta)
		var t_r := now - pp.interp.delay
		var st := pp.interp.sample(t_r)
		if st == null:
			continue
		pp.render_t = t_r
		pp.shown = st
		NetCodec.write_hero(pp.hero, st)
		if pp.interp.take_teleport() or not pp.applied:
			pp.applied = true
			pp.hero.reset_physics_interpolation()


func _send(now: float) -> void:
	if _session.roster.size() < 2:
		return
	# Each hero this machine owns is sampled ONCE per tick (the same state goes to every client).
	var live: Dictionary = {}
	for seat: int in _live:
		var own := _live_state(seat, now)
		if own != null:
			live[seat] = own
	if _session.hosting:
		# M3: the world (monsters, employees, hellgates) is packed once and rides after the heroes in every packet.
		var world := _session.world.section(now) if _session.world != null else PackedByteArray()
		var seats: Array = _live.keys() + _puppets.keys()
		seats.sort()
		for peer: int in _session.roster:
			if peer == 1:
				continue
			var states: Array[NetHeroState] = []
			for seat: int in seats:
				if _session.seats.owner_of(seat) == peer:
					continue
				var st: NetHeroState = live.get(seat) if live.has(seat) else _forwarded(seat, now)
				if st != null:
					states.append(st)
			_send_to(peer, states, now, world)
	elif live.has(local_seat):
		var one: Array[NetHeroState] = [live[local_seat]]
		_send_to(0, one, now)


## Host: the newest state received from the client that owns `seat`, to pass on (null if it went quiet).
func _forwarded(seat: int, now: float) -> NetHeroState:
	var pp := puppet(seat)
	if pp == null:
		return null
	var newest := pp.interp.newest()
	if newest == null or now - newest.t > FORWARD_MAX_AGE:
		return null
	return newest


func _send_to(peer: int, states: Array[NetHeroState], now: float, world: PackedByteArray = PackedByteArray()) -> void:
	if states.is_empty() and world.is_empty():
		return
	var payload := NetCodec.encode(states, now)
	var bytes := NetWire.HEADER + payload.size()   # the hero stream (M2's budget is measured on this part alone)
	if not world.is_empty():
		payload.append_array(world)
	if _session.send_packet(peer, NetCodec.SNAP_TYPE, payload) < 0:
		return
	stats["out_packets"] = int(stats["out_packets"]) + 1
	stats["out_bytes"] = int(stats["out_bytes"]) + bytes
	stats["out_max"] = maxi(int(stats["out_max"]), bytes)
	stats["world_out_bytes"] = int(stats["world_out_bytes"]) + world.size()
	stats["packet_max"] = maxi(int(stats["packet_max"]), NetWire.HEADER + payload.size())


# --- Receiving ---------------------------------------------------------------------------------------------

func _on_packet(from: int, type: int, _seq: int, stamp_ms: int, payload: PackedByteArray) -> void:
	if type != NetCodec.SNAP_TYPE or _session == null or not _session.online() or (_live.is_empty() and _puppets.is_empty()):
		return   # (not a hero snapshot, or no floor is up here to show it on)
	if not _session.hosting and from != 1:
		return
	stats["in_packets"] = int(stats["in_packets"]) + 1
	var arrival := _session.host_time()
	var stamp := float(stamp_ms) / 1000.0
	var b := StreamPeerBuffer.new()
	b.data_array = payload
	var heroes := NetCodec.decode_from(b, stamp)
	stats["in_bytes"] = int(stats["in_bytes"]) + NetWire.HEADER + b.get_position()
	stats["in_world_bytes"] = int(stats["in_world_bytes"]) + b.get_available_bytes()
	if not _session.hosting and _session.world != null and b.get_available_bytes() > 0:
		_session.world.receive(b, stamp, arrival)   # M3: the host's world, after the heroes
	for st in heroes:
		stats["in_entries"] = int(stats["in_entries"]) + 1
		if st.seat == local_seat or not _puppets.has(st.seat):
			stats["in_foreign"] = int(stats["in_foreign"]) + 1
			continue
		# The host takes a client's state for the seat that client owns, nothing else.
		if _session.hosting and _session.seats.owner_of(st.seat) != from:
			stats["in_foreign"] = int(stats["in_foreign"]) + 1
			continue
		# M6: a state the seat's PREVIOUS owner sent (an older epoch, before a handover) is dropped everywhere. A newer one
		# is taken: the reliable handover event is on its way behind it.
		if _session.seats != null and not epoch_current(st.epoch, _session.seats.epoch_of(st.seat)):
			stats["in_stale_epoch"] = int(stats.get("in_stale_epoch", 0)) + 1
			continue
		(_puppets[st.seat] as Puppet).interp.push(st, arrival)


## True when a sample stamped with `sample_epoch` (mod 16) is not from an earlier owner than the seat's `known` epoch: the
## same epoch, or up to 7 handovers newer (wrap-aware, like the wire's sequence numbers).
static func epoch_current(sample_epoch: int, known: int) -> bool:
	var ahead := (sample_epoch - known) & 15
	return ahead < 8


func _now() -> float:
	return _session.host_time() if _session != null else 0.0
