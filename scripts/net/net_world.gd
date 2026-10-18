class_name NetWorld
extends Node
## The host-owned world on every screen (docs/design/networking-build-plan.md M3): child "World" of the Session
## autoload, so it survives the scene reloads. The host SIMULATES its monsters, hellgates and employees as ever; a
## client shows them as PUPPETS of the host's stream, interpolated on the shared clock like the hero puppets.
##
## HOST
##   - every tick of the hero snapshot (NetSnapshot, 30 Hz) asks section(): the world's entries (NetWorldCodec) are
##     packed ONCE and appended to every client's packet after the heroes, so a monster and a hero share one moment;
##   - an entry rides only when it matters: when it CHANGED (and REDUNDANCY times after, so one lost packet never
##     strands a stop), plus every entry at least every REFRESH ticks (a keyframe, spread over the ticks so no packet
##     carries the whole floor at once), oldest first, up to the packet budget (NetWorldCodec.PACKET_BUDGET);
##   - deaths, runtime spawns (a hellgate's burst, with host-assigned ids from NetRegistry.RUNTIME_BASE up), an
##     employee's speech bubble and its extraction, a gate's phase change and its shove are reliable EVENTS.
## CLIENT
##   - every host-owned actor is a puppet (Net.make_puppet: no AI, no damage, no shoves); each frame it is shown at
##     host_time() - delay (the delay adapts like NetInterp's, measured on the world packets), Hermite between samples;
##   - Monster.net_show / Employee.net_show / Hellgate.net_show apply what changed and play it (hit flash, wind-up,
##     swing, mood); net_tick runs the visuals the physics process would have run;
##   - a death is shown when the render time reaches the moment the host stamped it, so it lands on the same beat as
##     the movement that led to it (and at once if the actor has no samples).
##
## The game calls begin() at the floor's barrier (after NetFloor.assign_ids and freeze_copies) and set_active() with
## the hero sync (NetSnapshot.set_active). Nothing here knows about game.gd.

## A runtime monster appeared on this client (a gate's burst): its ids.
signal spawned(ids: Array)
## A host-owned actor's death was shown here.
signal died(id: int)

const MONSTER := 0
const EMPLOYEE := 1
const GATE := 2

const REDUNDANCY := 3       ## a changed entry is sent this many ticks in a row
const REFRESH := 30         ## every entry at least once per this many ticks (1 s at 30 Hz): a still floor costs about 16 B per actor per second
const TELEPORT_DIST := 3.0
const HOLD_GAP := 0.09      ## a sample this long after the last one of a STILL actor gets a "held still" sample before it
const DEATH_WAIT_MAX := 0.6 ## a death is shown at the latest this long after it arrived
## Host -> client packet: the wire header, the hero count and two heroes (drawing) come first.
const WORLD_BUDGET := NetWorldCodec.PACKET_BUDGET - NetWire.HEADER - 1 - 2 * NetCodec.ENTRY_SIZE_DRAWING

## Host: an entry it streams.
class Track extends RefCounted:
	var node: Actor
	var id := 0
	var kind := MONSTER
	var last_pos := Vector3.INF
	var sent_pos := Vector3.INF
	var vel := Vector2.ZERO
	var tp := 0
	var last_bytes := PackedByteArray()
	var quiet := 1 << 20        ## ticks since its bytes last changed
	var last_sent := -(1 << 20) ## the tick it last rode in a packet


## Client: a puppet it shows.
class Shown extends RefCounted:
	var node: Actor
	var id := 0
	var kind := MONSTER
	var interp := NetInterp.new()
	var shown: NetHeroState = null
	var render_t := 0.0
	var applied := false
	var gate_t := -1.0          ## a gate: the stamp of the state last applied


var active := false
## Counters (tests and the report). Host: sections built, entries and bytes; client: entries applied.
var stats := {}
## Test seam: stream as the host without a session (track_for_test).
var host_override := false

var _session: NetSession = null
var _tracks: Dictionary = {}        ## host: id -> Track
var _tick := 0
var _pending_spawns: Array[int] = []
var _shown: Dictionary = {}         ## client: id -> Shown
var _timing := NetInterp.new()      ## client: the world stream's own delay (one per stream, so the whole floor is shown at one moment)
var _deaths: Array = []             ## client: [id, stamp, arrival]
var _links: Array = []              ## [Signal, Callable] connected in begin(), disconnected in end()
var _world_section := PackedByteArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_stats()
	_session = get_parent() as NetSession
	if _session == null:
		return
	_session.event_received.connect(_on_event)
	_session.session_ended.connect(func(_reason: String) -> void: end())


func _reset_stats() -> void:
	stats = {"sections": 0, "bytes": 0, "max": 0, "entries": 0, "monsters_max": 0, "in_sections": 0, "in_entries": 0,
		"unknown": 0, "spawns": 0, "deaths": 0, "events_out": 0, "since": _now()}


# --- Setup -----------------------------------------------------------------------------------------------

## The floor is built: ids assigned (NetFloor.assign_ids), the host's things are copies on a client. Take every
## host-owned actor in the registry: the host streams it, a client shows it.
func begin() -> void:
	end()
	if _session == null or not _session.online():
		return
	for id in NetRegistry.ids():
		if id < NetFloor.ID_BASE:
			continue   # heroes: NetSnapshot
		var n := NetRegistry.node(id) as Actor
		if n == null:
			continue
		var kind := _kind_of(n)
		if kind < 0:
			continue
		if _session.hosting:
			_track(id, n, kind)
		else:
			_show(id, n, kind)
	if _session.hosting:
		_link(GameWorld.actor_spawned, _on_actor_spawned)
		_link(GameWorld.actor_died, _on_actor_died)
	_reset_stats()


## Forget the floor (the scene is going, or the session ended).
func end() -> void:
	active = false
	for l: Array in _links:
		var sig: Signal = l[0]
		if is_instance_valid(sig.get_object()) and sig.is_connected(l[1]):
			sig.disconnect(l[1])
	_links.clear()
	_tracks.clear()
	_shown.clear()
	_deaths.clear()
	_pending_spawns.clear()
	_timing.clear()
	_tick = 0


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if on:
		_reset_stats()
		for id: int in _shown:
			(_shown[id] as Shown).applied = false


static func _kind_of(n: Node) -> int:
	if n is Monster:
		return MONSTER
	if n is Employee:
		return EMPLOYEE
	if n is Hellgate:
		return GATE
	return -1


func _link(sig: Signal, c: Callable) -> void:
	if not sig.is_connected(c):
		sig.connect(c)
	_links.append([sig, c])


func _track(id: int, n: Actor, kind: int) -> void:
	var tr := Track.new()
	tr.node = n
	tr.id = id
	tr.kind = kind
	_tracks[id] = tr
	if n is Employee:
		_link((n as Employee).said, _on_said.bind(id))
		_link((n as Employee).rescued, _on_rescued.bind(id))
	elif n is Hellgate:
		_link((n as Hellgate).phase_changed, _on_gate_phase.bind(id))
		_link((n as Hellgate).shove_burst, _on_gate_shove.bind(id))


func _show(id: int, n: Actor, kind: int) -> void:
	Net.make_puppet(n)
	var sh := Shown.new()
	sh.node = n
	sh.id = id
	sh.kind = kind
	_shown[id] = sh


# --- Asking ----------------------------------------------------------------------------------------------

func is_shown(id: int) -> bool:
	return _shown.has(id)


func shown_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in _shown:
		out.append(id)
	out.sort()
	return out


func tracked_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in _tracks:
		out.append(id)
	out.sort()
	return out


## Client: the shared-clock time the world is shown at right now.
func render_time() -> float:
	return _now() - _timing.delay


func delay() -> float:
	return _timing.delay


## Client: the state a puppet showed last frame (null before its first sample).
func shown_state(id: int) -> NetHeroState:
	var sh: Shown = _shown.get(id)
	return sh.shown if sh != null else null


# --- Host: sampling and packing ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not active or not _streams():
		return
	for id: int in _tracks:
		var tr: Track = _tracks[id]
		if tr.kind == GATE or not is_instance_valid(tr.node):
			continue
		var p := tr.node.global_position
		tr.vel = Vector2.ZERO
		if tr.last_pos != Vector3.INF:
			var d := p - tr.last_pos
			if Vector2(d.x, d.z).length() <= TELEPORT_DIST and absf(d.y) <= TELEPORT_DIST:
				tr.vel = Vector2(d.x, d.z) / maxf(delta, 0.0001)
		tr.last_pos = p


## Test seam (single process, no session): stream `node` under `id` as if this were the host.
func track_for_test(id: int, node: Actor) -> void:
	host_override = true
	_track(id, node, _kind_of(node))


func _streams() -> bool:
	return host_override or (_session != null and _session.hosting)


## The world section for this tick (built once; NetSnapshot appends it to every client's packet). `budget` is how
## many bytes it may take.
func section(now: float, budget: int = WORLD_BUDGET) -> PackedByteArray:
	if not active or not _streams():
		return PackedByteArray()
	_tick += 1
	var hot: Array[Track] = []
	var cold: Array[Track] = []
	for id: int in _tracks.keys():
		var tr: Track = _tracks[id]
		if not is_instance_valid(tr.node) or tr.node.dead or (tr.kind == EMPLOYEE and (tr.node as Employee).is_extracted()):
			_tracks.erase(id)
			continue
		var bytes := _entry(tr, now)
		if bytes != tr.last_bytes:
			tr.last_bytes = bytes
			tr.quiet = 0
		else:
			tr.quiet += 1
		if tr.quiet < REDUNDANCY:
			hot.append(tr)
		else:
			cold.append(tr)
	var oldest := func(a: Track, b: Track) -> bool: return a.last_sent < b.last_sent
	hot.sort_custom(oldest)
	cold.sort_custom(oldest)
	# Every cold entry rides at least once per REFRESH ticks: the overdue ones, and a share of the rest each tick.
	var share := ceili(float(_tracks.size()) / float(REFRESH))
	var chosen: Array[Track] = []
	var used := NetWorldCodec.SECTION_HEADER
	for tr in hot:
		if used + tr.last_bytes.size() > budget:
			break
		chosen.append(tr)
		used += tr.last_bytes.size()
	var refreshed := 0
	for tr in cold:
		var due := _tick - tr.last_sent >= REFRESH
		if not due and refreshed >= share:
			break
		if used + tr.last_bytes.size() > budget:
			break
		chosen.append(tr)
		used += tr.last_bytes.size()
		refreshed += 1
	var mon_parts: Array[PackedByteArray] = []
	var emp_parts: Array[PackedByteArray] = []
	var gate_parts: Array[PackedByteArray] = []
	for tr in chosen:
		tr.last_sent = _tick
		match tr.kind:
			MONSTER:
				mon_parts.append(tr.last_bytes)
			EMPLOYEE:
				emp_parts.append(tr.last_bytes)
			_:
				gate_parts.append(tr.last_bytes)
	var mons := mon_parts.size()
	_world_section = NetWorldCodec.encode(mon_parts, emp_parts, gate_parts)
	stats["sections"] = int(stats["sections"]) + 1
	stats["bytes"] = int(stats["bytes"]) + _world_section.size()
	stats["max"] = maxi(int(stats["max"]), _world_section.size())
	stats["entries"] = int(stats["entries"]) + chosen.size()
	stats["monsters_max"] = maxi(int(stats["monsters_max"]), mons)
	_flush_spawns()
	return _world_section


## One entry's bytes, sampled now. A jump from where the last sample was taken is a teleport (the counter moves on).
func _entry(tr: Track, now: float) -> PackedByteArray:
	if tr.kind == GATE:
		var g := NetWorldCodec.GateState.new()
		g.id = tr.id
		NetWorldCodec.read_gate(tr.node as Hellgate, g)
		return NetWorldCodec.gate_bytes(g)
	var st := NetHeroState.new()
	st.id = tr.id
	st.t = now
	st.pos = tr.node.global_position
	st.vel = tr.vel
	if tr.sent_pos != Vector3.INF and (Vector2(st.pos.x - tr.sent_pos.x, st.pos.z - tr.sent_pos.z).length() > TELEPORT_DIST or absf(st.pos.y - tr.sent_pos.y) > TELEPORT_DIST):
		tr.tp = (tr.tp + 1) & 7
		tr.vel = Vector2.ZERO
		st.vel = Vector2.ZERO
	tr.sent_pos = st.pos
	st.tp = tr.tp
	if tr.kind == MONSTER:
		NetWorldCodec.read_monster(tr.node as Monster, st)
		return NetWorldCodec.monster_bytes(st)
	NetWorldCodec.read_employee(tr.node as Employee, st)
	return NetWorldCodec.employee_bytes(st)


# --- Host: events ---------------------------------------------------------------------------------------------

func _on_actor_spawned(a: Actor) -> void:
	if not (a is Monster) or NetFloor.id_of(a) != 0:   # (from the barrier on, even before the stream starts)
		return
	var id := NetRegistry.next_runtime_id()
	NetRegistry.register(id, a)
	_track(id, a, MONSTER)
	_pending_spawns.append(id)
	call_deferred("_flush_spawns")


## The monsters spawned since the last flush, in one event per gate (a burst is one message).
func _flush_spawns() -> void:
	if _pending_spawns.is_empty():
		return
	var by_gate: Dictionary = {}
	for id in _pending_spawns:
		var m := NetRegistry.node(id) as Monster
		if m == null:
			continue
		var gate_node: Variant = m.get_meta("from_gate", null)
		var gate := NetFloor.id_of(gate_node as Node) if gate_node != null and is_instance_valid(gate_node) else 0
		if not by_gate.has(gate):
			by_gate[gate] = []
		var p := m.global_position
		(by_gate[gate] as Array).append([id, m.kind, p.x, p.y, p.z])
	_pending_spawns.clear()
	for gate: int in by_gate:
		_send("world.spawn", {"g": gate, "m": by_gate[gate]})
		stats["spawns"] = int(stats["spawns"]) + (by_gate[gate] as Array).size()


func _on_actor_died(a: Actor) -> void:
	var id := NetFloor.id_of(a)
	if not _tracks.has(id):
		return
	_flush_spawns()   # (a monster that spawns and dies in one frame is announced before its death)
	_tracks.erase(id)
	_send("world.die", {"id": id})
	stats["deaths"] = int(stats["deaths"]) + 1


func _on_said(text: String, seconds: float, id: int) -> void:
	_send("world.say", {"id": id, "s": text, "d": seconds})


func _on_rescued(e: Employee, id: int) -> void:
	_tracks.erase(id)
	_send("world.extract", {"id": id, "s": e._say_text})


func _on_gate_phase(phase: int, id: int) -> void:
	_send("world.phase", {"id": id, "p": phase})


func _on_gate_shove(_radius: float, id: int) -> void:
	_send("world.shove", {"id": id})


func _send(kind: String, data: Dictionary) -> void:
	if _session == null or not _session.online() or _session.roster.size() < 2:
		return
	_session.send_event(0, kind, data)
	stats["events_out"] = int(stats["events_out"]) + 1


# --- Client: receiving -------------------------------------------------------------------------------------

## A world section arrived (NetSnapshot hands it over after the heroes). `stamp` is the packet's moment.
func receive(b: StreamPeerBuffer, stamp: float, arrival: float) -> void:
	if _session == null or _session.hosting or _shown.is_empty():
		return
	var sec := NetWorldCodec.decode(b, stamp)
	var tick := NetHeroState.new()
	tick.t = stamp
	_timing.push(tick, arrival)
	stats["in_sections"] = int(stats["in_sections"]) + 1
	for list: Array[NetHeroState] in [sec.monsters, sec.employees]:
		for st in list:
			var sh: Shown = _shown.get(st.id)
			if sh == null or not is_instance_valid(sh.node) or sh.node.dead:
				stats["unknown"] = int(stats["unknown"]) + 1
				continue
			var newest := sh.interp.newest()
			if newest != null and st.t - newest.t > HOLD_GAP and newest.vel.length() < 0.05 and st.tp == newest.tp:
				# It stood still (nothing was sent while it did): it stood there until just before this sample.
				var hold := newest.copy()
				hold.t = st.t - NetSnapshot.SEND_INTERVAL
				if hold.t > newest.t:
					sh.interp.push(hold, arrival)
			sh.interp.push(st, arrival)
			stats["in_entries"] = int(stats["in_entries"]) + 1
	for g in sec.gates:
		var sh: Shown = _shown.get(g.id)
		if sh == null or not is_instance_valid(sh.node) or sh.node.dead or g.t <= sh.gate_t:
			continue
		sh.gate_t = g.t
		NetWorldCodec.write_gate(sh.node as Hellgate, g)
		stats["in_entries"] = int(stats["in_entries"]) + 1


func _on_event(from: int, kind: String, data: Dictionary, stamp: float) -> void:
	if not kind.begins_with("world.") or _session == null or _session.hosting or from != 1:
		return
	match kind:
		"world.spawn":
			_receive_spawn(int(data.get("g", 0)), data.get("m", []) as Array)
		"world.die":
			_deaths.append([int(data.get("id", 0)), stamp, _now()])
		"world.say":
			var e := NetRegistry.node(int(data.get("id", 0))) as Employee
			if e != null and not e.dead:
				e.say(str(data.get("s", "")), float(data.get("d", 1.5)))
		"world.extract":
			var e := NetRegistry.node(int(data.get("id", 0))) as Employee
			if e != null and not e.dead and not e.is_extracted():
				_shown.erase(int(data.get("id", 0)))
				e.extract(str(data.get("s", "thank you!")))
		"world.phase":
			var g := NetRegistry.node(int(data.get("id", 0))) as Hellgate
			if g != null and not g.dead:
				g.net_phase(int(data.get("p", 0)))
		"world.shove":
			var g := NetRegistry.node(int(data.get("id", 0))) as Hellgate
			if g != null and not g.dead:
				g.net_shove_fx()


func _receive_spawn(gate_id: int, list: Array) -> void:
	if GameWorld.root == null:
		return
	var gate := NetRegistry.node(gate_id) as Hellgate if gate_id != 0 else null
	var ids: Array = []
	for e: Variant in list:
		var row := e as Array
		if row == null or row.size() < 5:
			continue
		var id := int(row[0])
		if NetRegistry.has_id(id):
			continue
		var pos := Vector3(float(row[2]), float(row[3]), float(row[4]))
		var m := MonsterFactory.spawn(str(row[1]), Hex.from_world(pos))
		if m == null:
			continue
		m.global_position = pos
		NetRegistry.register(id, m)
		if gate != null:
			m.set_meta("from_gate", gate)
		_show(id, m, MONSTER)
		m.reset_physics_interpolation()
		ids.append(id)
	if gate != null and not gate.dead:
		gate.net_burst_fx(ids.map(func(i: int) -> Node: return NetRegistry.node(i)))
	stats["spawns"] = int(stats["spawns"]) + ids.size()
	if not ids.is_empty():
		spawned.emit(ids)


# --- Client: every frame -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _session == null or _session.hosting or not _session.online():
		return
	if not active:
		return
	var now := _now()
	_timing.step_delay(delta)
	var t_r := now - _timing.delay
	_apply_deaths(t_r, now)
	for id: int in _shown.keys():
		var sh: Shown = _shown[id]
		if not is_instance_valid(sh.node):
			_shown.erase(id)
			continue
		if sh.node.dead:
			continue
		if sh.kind != GATE:
			var st := sh.interp.sample(t_r)
			if st != null:
				sh.render_t = t_r
				sh.shown = st
				if sh.kind == MONSTER:
					NetWorldCodec.write_monster(sh.node as Monster, st)
				else:
					NetWorldCodec.write_employee(sh.node as Employee, st)
				if sh.interp.take_teleport() or not sh.applied:
					sh.applied = true
					sh.node.reset_physics_interpolation()
		sh.node.call("net_tick", delta)


## Deaths whose moment the render time has reached (or that waited long enough).
func _apply_deaths(t_r: float, now: float) -> void:
	var keep: Array = []
	for d: Array in _deaths:
		if t_r >= float(d[1]) or now - float(d[2]) >= DEATH_WAIT_MAX:
			_die(int(d[0]))
		else:
			keep.append(d)
	_deaths = keep


func _die(id: int) -> void:
	var n := NetRegistry.node(id) as Actor
	_shown.erase(id)
	if n == null or n.dead:
		return
	Net.remote_die(n)
	stats["deaths"] = int(stats["deaths"]) + 1
	died.emit(id)


func _now() -> float:
	return _session.host_time() if _session != null else 0.0
