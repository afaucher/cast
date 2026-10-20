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
## WIND-UPS (M4, the victim decides): a monster's wind-up on the host is an event, `world.windup {id, s start, l length,
## v victim}` (and `world.unwind {id}` when it is called off: shoved, staggered, the target gone). The host's own strike
## hits only the heroes the host owns (Combat skips a player's hero); each client resolves the strike against ITS OWN
## hero when its screen shows the strike's moment (render time >= s + l: Monster.net_strike), from where it shows the
## monster and where its own hero really is. What a player dodged on their screen did not hit them.
##
## GOBLIN SCOUTS (monster awareness step 2, goblin-scout.md §7): a scout's phase and rack are `world.scout {id, p, l}` on
## every change (his "!", the light, the fuse, the cower, an empty rack); his volley is `world.fireworks {id, x, y, z, s,
## f, dx, dz}` (the launch point, its start on the shared clock, the fx seed and the drift: every screen builds the same
## FireworksFx, a cosmetic) and a soaked rack `world.dud {x, y, z}`. The alarm itself is host gameplay (the host owns
## every monster it wakes): nothing more travels for it. A late joiner gets every scout's phase in its snapshot
## (scout_states / apply_scouts); a volley already in the air is skipped.
##
## CHICKENS (the Chicken spell): the host spawns a flock when a chicken cast lands and runs it; each chicken is a runtime
## spawn like a gate's monster (`world.spawn`, kind "chicken", gate 0), rides the stream as a MONSTER-format entry
## (NetWorldCodec.read_chicken / write_chicken: the codec's layout is unchanged, this file knows which ids are chickens) and
## dies with `world.die`. A client shows it as a puppet (Chicken.net_show / net_tick).
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
const CHICKEN := 3

const REDUNDANCY := 3       ## a changed entry is sent this many ticks in a row
const REFRESH := 30         ## every entry at least once per this many ticks (1 s at 30 Hz): a still floor costs about 16 B per actor per second
const TELEPORT_DIST := 3.0
const HOLD_GAP := 0.09      ## a sample this long after the last one of a STILL actor gets a "held still" sample before it
const DEATH_WAIT_MAX := 0.6 ## a death is shown at the latest this long after it arrived
const STRIKE_EARLY := 0.02  ## a client resolves a strike this much before its render time reaches it (so the strike count
                            ## in the snapshot, sampled a moment after the blow, never plays it first)
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
var _windups: Dictionary = {}       ## client: monster id -> [strike time (host_time), victim id]
## Client, tests: every strike this screen resolved: [monster id, victim id, host_time, damage its own hero took].
var resolved: Array = []
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
		"unknown": 0, "spawns": 0, "deaths": 0, "events_out": 0, "windups": 0, "unwinds": 0, "strikes": 0, "since": _now()}


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
	_windups.clear()
	resolved.clear()
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
	if n is Chicken:
		return CHICKEN
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
	elif n is Monster:
		_link((n as Monster).windup_begun, _on_windup.bind(id))
		_link((n as Monster).windup_dropped, _on_unwind.bind(id))
		if n.has_signal("scout_phase_changed"):
			_link(Signal(n, "scout_phase_changed"), _on_scout.bind(id))
			_link(Signal(n, "fireworks_launched"), _on_fireworks.bind(id))
			_link(Signal(n, "fireworks_dud"), _on_dud)
		if n.has_signal("beam_locked"):
			_link(Signal(n, "charge_begun"), _on_charge.bind(id))
			_link(Signal(n, "charge_dropped"), _on_uncharge.bind(id))
			_link(Signal(n, "beam_locked"), _on_lock.bind(id))
		if n.has_signal("dismounted"):
			_link(Signal(n, "dismounted"), _on_dismount.bind(id))


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
			MONSTER, CHICKEN:
				mon_parts.append(tr.last_bytes)   # (a chicken rides as a monster entry)
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
	if tr.kind == CHICKEN:
		NetWorldCodec.read_chicken(tr.node as Chicken, st)
		return NetWorldCodec.monster_bytes(st)
	NetWorldCodec.read_employee(tr.node as Employee, st)
	return NetWorldCodec.employee_bytes(st)


# --- M6: the late joiner's keyframe ------------------------------------------------------------------------------

## Host: a world section with EVERY surviving host-owned mover in it (no budget: it rides the late-join snapshot, a reliable
## event, not a datagram). Sampled now, without touching the stream's own bookkeeping.
func keyframe(now: float) -> PackedByteArray:
	var mons: Array[PackedByteArray] = []
	var emps: Array[PackedByteArray] = []
	var gates: Array[PackedByteArray] = []
	for id: int in _tracks:
		var tr: Track = _tracks[id]
		if not is_instance_valid(tr.node) or tr.node.dead or (tr.kind == EMPLOYEE and (tr.node as Employee).is_extracted()):
			continue
		match tr.kind:
			MONSTER:
				var st := _state_now(tr, now)
				NetWorldCodec.read_monster(tr.node as Monster, st)
				mons.append(NetWorldCodec.monster_bytes(st))
			CHICKEN:
				var st := _state_now(tr, now)
				NetWorldCodec.read_chicken(tr.node as Chicken, st)
				mons.append(NetWorldCodec.monster_bytes(st))
			EMPLOYEE:
				var st := _state_now(tr, now)
				NetWorldCodec.read_employee(tr.node as Employee, st)
				emps.append(NetWorldCodec.employee_bytes(st))
			_:
				var g := NetWorldCodec.GateState.new()
				g.id = tr.id
				NetWorldCodec.read_gate(tr.node as Hellgate, g)
				gates.append(NetWorldCodec.gate_bytes(g))
	return NetWorldCodec.encode(mons, emps, gates)


func _state_now(tr: Track, now: float) -> NetHeroState:
	var st := NetHeroState.new()
	st.id = tr.id
	st.t = now
	st.pos = tr.node.global_position
	st.vel = tr.vel
	st.tp = tr.tp
	return st


## Host: every runtime monster alive (a gate's burst, a dev spawn) and every chicken, as a world.spawn replay:
## [[id, kind, x, y, z, gate id]].
func runtime_spawns() -> Array:
	var out: Array = []
	for id: int in _tracks:
		var tr: Track = _tracks[id]
		if id < NetRegistry.RUNTIME_BASE or (tr.kind != MONSTER and tr.kind != CHICKEN) or not is_instance_valid(tr.node) or tr.node.dead:
			continue
		var row := _spawn_row(id, tr.node)
		row.append(_gate_of(tr.node))
		out.append(row)
	return out


## [id, kind, x, y, z] of a runtime spawn (a monster's kind, or "chicken").
static func _spawn_row(id: int, a: Actor) -> Array:
	var p := a.global_position
	return [id, (a as Monster).kind if a is Monster else "chicken", p.x, p.y, p.z]


## The net id of the gate a runtime monster came out of (0: none, and for a chicken).
static func _gate_of(a: Actor) -> int:
	var gate_node: Variant = a.get_meta("from_gate") if a.has_meta("from_gate") else null
	return NetFloor.id_of(gate_node as Node) if gate_node != null and is_instance_valid(gate_node) else 0


## The late joiner: build the host's runtime monsters (no burst to watch: they came out a while ago).
func apply_spawns(list: Array) -> void:
	var by_gate := {}
	for e: Variant in list:
		var row := e as Array
		if row == null or row.size() < 6:
			continue
		var g := int(row[5])
		if not by_gate.has(g):
			by_gate[g] = []
		(by_gate[g] as Array).append(row.slice(0, 5))
	for g: int in by_gate:
		_receive_spawn(g, by_gate[g], true)


## The late joiner: the host's keyframe (keyframe()). Every mover's sample goes into its buffer (the puppet shows it from
## the first frame the world is live; the stream carries on from there) and the gates take their state at once. The stream's
## delay is not fed from it: it arrived as a reliable event, not on the stream.
func apply_keyframe(bytes: PackedByteArray, stamp: float) -> int:
	if bytes.is_empty():
		return 0
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var sec := NetWorldCodec.decode(b, stamp)
	var n := 0
	for list: Array[NetHeroState] in [sec.monsters, sec.employees]:
		for st in list:
			var sh: Shown = _shown.get(st.id)
			if sh == null or not is_instance_valid(sh.node) or sh.node.dead:
				continue
			sh.interp.push(st, stamp)
			sh.node.global_position = st.pos   # (where it stands now, also while the floor is still frozen here)
			sh.node.reset_physics_interpolation()
			n += 1
	for g in sec.gates:
		var sh: Shown = _shown.get(g.id)
		if sh == null or not is_instance_valid(sh.node) or sh.node.dead:
			continue
		sh.gate_t = g.t
		NetWorldCodec.write_gate(sh.node as Hellgate, g)
		n += 1
	return n


# --- Host: events ---------------------------------------------------------------------------------------------

func _on_actor_spawned(a: Actor) -> void:
	if not (a is Monster or a is Chicken) or NetFloor.id_of(a) != 0:   # (from the barrier on, even before the stream starts)
		return
	var id := NetRegistry.next_runtime_id()
	NetRegistry.register(id, a)
	_track(id, a, _kind_of(a))
	_pending_spawns.append(id)
	call_deferred("_flush_spawns")


## The monsters spawned since the last flush, in one event per gate (a burst is one message).
func _flush_spawns() -> void:
	if _pending_spawns.is_empty():
		return
	var by_gate: Dictionary = {}
	for id in _pending_spawns:
		var m := NetRegistry.node(id) as Actor
		if m == null or not (m is Monster or m is Chicken):
			continue
		var gate := _gate_of(m)
		if not by_gate.has(gate):
			by_gate[gate] = []
		(by_gate[gate] as Array).append(_spawn_row(id, m))
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


## Host: a monster began a wind-up: every client resolves the strike against its own hero (the victim decides).
func _on_windup(length: float, id: int) -> void:
	var m := NetRegistry.node(id) as Monster
	if m == null:
		return
	var victim := NetFloor.id_of(m.target) if m.target != null and is_instance_valid(m.target) else 0
	_send("world.windup", {"id": id, "s": _now(), "l": length, "v": victim})
	stats["windups"] = int(stats["windups"]) + 1


## Host: a goblin scout's phase or rack changed.
func _on_scout(phase: int, rack: bool, id: int) -> void:
	_send("world.scout", {"id": id, "p": phase, "l": rack})
	stats["scouts"] = int(stats.get("scouts", 0)) + 1


## Host: a scout's volley went up at `pos` (its launch point) now.
func _on_fireworks(pos: Vector3, fx_seed: int, drift: Vector3, id: int) -> void:
	_send("world.fireworks", {"id": id, "x": pos.x, "y": pos.y, "z": pos.z, "s": _now(), "f": fx_seed, "dx": drift.x, "dz": drift.z})
	stats["fireworks"] = int(stats.get("fireworks", 0)) + 1


func _on_dud(pos: Vector3) -> void:
	_send("world.dud", {"x": pos.x, "y": pos.y, "z": pos.z})


## Host: every living scout's phase and rack, for a late joiner: [[id, phase, loaded]].
func scout_states() -> Array:
	var out: Array = []
	for id: int in _tracks:
		var tr: Track = _tracks[id]
		if tr.kind == MONSTER and is_instance_valid(tr.node) and not tr.node.dead and tr.node.has_method("net_scout"):
			out.append([id, int(tr.node.get("scout_phase")), bool(tr.node.get("loaded"))])
	return out


## The late joiner: the scouts' phases and racks (scout_states).
func apply_scouts(list: Array) -> void:
	for e: Variant in list:
		var row := e as Array
		if row == null or row.size() < 3:
			continue
		var n := NetRegistry.node(int(row[0]))
		if n != null and n.has_method("net_scout") and not (n as Actor).dead:
			n.call("net_scout", int(row[1]), bool(row[2]))


func _on_unwind(id: int) -> void:
	_send("world.unwind", {"id": id})
	stats["unwinds"] = int(stats["unwinds"]) + 1


## Host: a laser shark began charging at its victim (docs/design/sharks.md): every screen draws the red line tracking the
## victim as it shows them.
func _on_charge(length: float, id: int) -> void:
	var s := NetRegistry.node(id)
	var v: Variant = s.get("charge_victim") if s != null else null
	_send("world.charge", {"id": id, "s": _now(), "l": length, "v": NetFloor.id_of(v) if v != null and is_instance_valid(v) else 0})
	stats["charges"] = int(stats.get("charges", 0)) + 1


func _on_uncharge(id: int) -> void:
	_send("world.uncharge", {"id": id})


## Host: the beam's line is locked: its origin, direction and the moment it fires on the shared clock. Every machine fires
## it then on its own clock and applies what it resolves (the victim decides its own hero).
func _on_lock(origin: Vector3, dir: Vector3, fire_at: float, id: int) -> void:
	_send("world.lock", {"id": id, "x": origin.x, "y": origin.y, "z": origin.z, "dx": dir.x, "dz": dir.z,
		"t": _now() + (fire_at - GameWorld.time)})
	stats["locks"] = int(stats.get("locks", 0)) + 1


## Host: an imp gunner left its shark (knocked off, or its shark died): where it landed.
func _on_dismount(how: String, id: int) -> void:
	var n := NetRegistry.node(id) as Node3D
	var p := n.global_position if n != null else Vector3.ZERO
	_send("world.dismount", {"id": id, "h": how, "x": p.x, "y": p.y, "z": p.z})
	stats["dismounts"] = int(stats.get("dismounts", 0)) + 1


## Host: every dismounted, living imp gunner, for a late joiner: [[id, how, x, y, z]] (its position then rides the keyframe).
func dismount_states() -> Array:
	var out: Array = []
	for id: int in _tracks:
		var tr: Track = _tracks[id]
		if is_instance_valid(tr.node) and not tr.node.dead and tr.node.has_method("net_dismount") and not bool(tr.node.get("mounted")):
			var p := tr.node.global_position
			out.append([id, "knocked", p.x, p.y, p.z])
	return out


## The late joiner: the gunners already off their sharks (dismount_states).
func apply_dismounts(list: Array) -> void:
	for e: Variant in list:
		var row := e as Array
		if row == null or row.size() < 5:
			continue
		var n := NetRegistry.node(int(row[0]))
		if n != null and n.has_method("net_dismount") and not (n as Actor).dead:
			n.call("net_dismount", str(row[1]), Vector3(float(row[2]), float(row[3]), float(row[4])))


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
			_windups.erase(int(data.get("id", 0)))
		"world.windup":
			_windups[int(data.get("id", 0))] = [float(data.get("s", stamp)) + float(data.get("l", 0.0)), int(data.get("v", 0))]
			stats["windups"] = int(stats["windups"]) + 1
		"world.unwind":
			_windups.erase(int(data.get("id", 0)))
			stats["unwinds"] = int(stats["unwinds"]) + 1
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
		"world.scout":
			var sc := NetRegistry.node(int(data.get("id", 0)))
			if sc != null and sc.has_method("net_scout") and not (sc as Actor).dead:
				sc.call("net_scout", int(data.get("p", 0)), bool(data.get("l", true)))
			stats["scouts"] = int(stats.get("scouts", 0)) + 1
		"world.fireworks":
			# Shown on the world's render clock, like the scout it comes from: it starts when this screen shows its moment.
			var start := GameWorld.time + (float(data.get("s", _now())) - render_time())
			var at := Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0)))
			FireworksFx.launch(at, start, int(data.get("f", 1)), Vector3(float(data.get("dx", 0.0)), 0.0, float(data.get("dz", 0.0))))
			stats["fireworks"] = int(stats.get("fireworks", 0)) + 1
		"world.charge":
			var sk := NetRegistry.node(int(data.get("id", 0)))
			if sk != null and sk.has_method("net_charge") and not (sk as Actor).dead:
				sk.call("net_charge", NetRegistry.node(int(data.get("v", 0))) as Actor)
			stats["charges"] = int(stats.get("charges", 0)) + 1
		"world.uncharge":
			var sk := NetRegistry.node(int(data.get("id", 0)))
			if sk != null and sk.has_method("net_uncharge") and not (sk as Actor).dead:
				sk.call("net_uncharge")
		"world.lock":
			var sk := NetRegistry.node(int(data.get("id", 0)))
			if sk != null and sk.has_method("net_lock") and not (sk as Actor).dead:
				var at := GameWorld.time + (float(data.get("t", _now())) - _now())   # (the shared moment, on this clock)
				sk.call("net_lock", Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0))),
					Vector3(float(data.get("dx", 0.0)), 0.0, float(data.get("dz", 1.0))), at)
			stats["locks"] = int(stats.get("locks", 0)) + 1
		"world.dismount":
			var jk := NetRegistry.node(int(data.get("id", 0)))
			if jk != null and jk.has_method("net_dismount") and not (jk as Actor).dead:
				jk.call("net_dismount", str(data.get("h", "knocked")), Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0))))
			stats["dismounts"] = int(stats.get("dismounts", 0)) + 1
		"world.dud":
			Fx.fizzle_puff(Vector3(float(data.get("x", 0.0)), float(data.get("y", 0.0)), float(data.get("z", 0.0))))


func _receive_spawn(gate_id: int, list: Array, quiet: bool = false) -> void:
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
		if str(row[1]) == "chicken":
			var c := Chicken.make_shown(pos)
			NetRegistry.register(id, c)
			_show(id, c, CHICKEN)
			c.reset_physics_interpolation()
			ids.append(id)
			continue
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
	if gate != null and not gate.dead and not quiet:
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
	_resolve_strikes(t_r)   # (gameplay on this machine's own hero: outside the net layer's apply scope, so the guard watches it)
	Net.apply_begin()
	_apply_deaths(t_r, now)
	_show_world(t_r, delta)
	Net.apply_end()


## Client: the shared time a monster's announced strike falls on (its wind-up's start + length), or -1 when none is due.
func pending_strike(id: int) -> float:
	return float((_windups[id] as Array)[0]) if _windups.has(id) else -1.0


## Client: the strikes whose moment this screen now shows hit this machine's hero, if they reach it here.
func _resolve_strikes(t_r: float) -> void:
	if _windups.is_empty():
		return
	for id: int in _windups.keys():
		var w: Array = _windups[id]
		if t_r < float(w[0]) - STRIKE_EARLY:
			continue
		_windups.erase(id)
		var m := NetRegistry.node(id) as Monster
		if m == null or not is_instance_valid(m) or m.dead or not m.is_inside_tree():
			continue
		var mine := _own_heroes()
		var before := 0.0
		for h in mine:
			before += h.hp
		m.net_strike(NetRegistry.node(int(w[1])) as Actor)
		var after := 0.0
		for h in mine:
			after += h.hp
		resolved.append([id, int(w[1]), _now(), before - after])
		stats["strikes"] = int(stats["strikes"]) + 1


func _own_heroes() -> Array[Hero]:
	var out: Array[Hero] = []
	for seat in [1, 2, 3]:
		var h := NetRegistry.hero(seat)
		if h != null and Net.owns(h):
			out.append(h)
	return out


func _show_world(t_r: float, delta: float) -> void:
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
				elif sh.kind == CHICKEN:
					NetWorldCodec.write_chicken(sh.node as Chicken, st)
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
