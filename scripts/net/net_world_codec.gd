class_name NetWorldCodec
extends RefCounted
## The host-owned world in the snapshot, hand-packed (docs/design/networking-build-plan.md M3): what rides after the
## hero entries of a host -> client NetWire.T_SNAP packet, how much of it is quantised, and how a monster's, an
## employee's and a hellgate's OWNER fields go in and out of the bytes.
##
## WORLD SECTION (after NetCodec's hero entries; a client's packet to the host has none)
##   u8 n_monsters,  n x MONSTER   (16 bytes)
##   u8 n_employees, n x EMPLOYEE  (15 bytes)
##   u8 n_gates,     n x GATE      (7 bytes)
##
## MONSTER (16)
##   u16 id        net id (NetRegistry: seed-built 100+, runtime spawns 10000+)
##   i16 x, z, y   centimetres
##   i8  vx, vz    velocity in 1/8 unit per second (+-15.9)
##   u8  angle     facing, 256 steps of a turn
##   u16 hp        tenths of a point
##   u8  flags     state (bits 0-2: IDLE 0, CHASE 1, ATTACK 2, RETURN 3, DEAD 4) | climbing 8 | helpless 16 (shoved or
##                 staggered) | teleport counter (bits 5-7)
##   u8  telegraph the wind-up, 0..1 in 255 steps
##   u8  strikes   how many attacks it has struck (mod 256): a change plays the swing on the other screens
## EMPLOYEE (15)
##   u16 id | i16 x, z, y | i8 vx, vz | u8 angle | u16 hp
##   u8  head      state (bits 0-2: COWER 0, PANIC 1, FOLLOW 2, EXTRACT 3, WAIT 4, FIGHT 5) | dismissed 8 | climbing 16 |
##                 teleport counter (bits 5-7)
##   u8  leader    the seat (1-3) of the hero it follows, 0 for nobody
## GATE (7)
##   u16 id | u16 hp (tenths)
##   u8  flags     active 1 | telegraphing 2 | phase (bits 2-3)
##   u8  burst_in  seconds to the burst in 1/50 s while the flare is up (255 = no flare)
##   u8  shove_t   seconds to the origin gate's shove in centiseconds (255 = none winding up)
##
## RUNTIME ACTORS (16 each): a MONSTER entry, filled and shown by the class (RUNTIME_ACTORS below). NetWorld knows which ids
##   are runtime actors (their `world.spawn` says so). The chicken: state = Chicken.State (WANDER 0, RUN 1, PECK 2, FLAP 3,
##   POOF 4), telegraph = the peck's wind-up, strikes = its pecks (mod 256).
##
## Deaths, spawns, speech, extraction, breaks and pickups are reliable EVENTS (NetWorld, NetObjects), not snapshot
## fields: the field tables below and NetEvents.WORLD_CARRIES together cover every OWNER var of these classes
## (test_net_contract holds them to it).

const MONSTER_SIZE := 16
const EMPLOYEE_SIZE := 15
const GATE_SIZE := 7
const SECTION_HEADER := 3          ## the three counts
const NO_BYTE := 255
const MAX_ENTRIES := 255           ## per kind per packet (a count is a u8)
## The whole host -> client packet (wire header, heroes and world) stays under this (networking.md: about 1.2 KB, one
## datagram on Steam's relays). NetWorld fills the world section up to it.
const PACKET_BUDGET := 1200

const FLAG_CLIMBING := 8
const FLAG_HELPLESS := 16
const FLAG_DISMISSED := 8
const FLAG_EMP_CLIMBING := 16
const GATE_ACTIVE := 1
const GATE_TELEGRAPH := 2

## Monster / Actor var -> the part of the entry that carries it.
const MONSTER_FIELDS := {
	"hp": "hp",
	"facing": "angle",
	"climbing": "flags",
	"state": "flags",
	"_telegraph": "telegraph",
	"strikes": "strikes",
}
## Employee / Actor var -> the part of the entry that carries it.
const EMPLOYEE_FIELDS := {
	"hp": "hp",
	"facing": "angle",
	"climbing": "head",
	"state": "head",
	"_dismissed": "head",
	"_leader": "leader",
}
## RUNTIME ACTORS: host-owned actors spawned during play by something other than a hellgate (a cast: the Chicken spell's
## chickens). NetWorld streams them all through one track as MONSTER-format entries and announces each with `world.spawn`
## (its kind). Script -> {
##   "kind":   the name a world.spawn row carries,
##   "group":  its query group (a late joiner drops a runtime actor the host no longer has from it, NetJoin),
##   "fields": its var -> the part of the monster-format entry that carries it (test_net_contract holds its OWNER vars to it)}.
## The class implements net_read(st) (host: its own slots of the entry, mode, telegraph and extra; read_runtime fills the
## rest), net_write(st) (client: show the state on the puppet, already placed), static make_shown(at) (client: the puppet a world.spawn row builds) and
## net_tick(delta); net_flash() if a client's hit on it should show at once (NetObjects.request_hit).
const RUNTIME_ACTORS := {
	"res://scripts/spells/chicken.gd": {
		"kind": "chicken",
		"group": Chicken.GROUP,
		"fields": {
			"hp": "hp",
			"facing": "angle",
			"climbing": "flags",
			"state": "flags",
			"_peck_t": "telegraph",
			"pecks": "strikes",
		},
	},
}
## Hellgate / Actor var -> the part of the entry that carries it.
const GATE_FIELDS := {
	"hp": "hp",
	"_active": "flags",
	"_telegraphing": "flags",
	"phase": "flags",
	"_next_burst_in": "burst_in",
	"_shove_t": "shove_t",
}


## A hellgate's replicated state (gates never move, so they are not interpolated).
class GateState extends RefCounted:
	var id := 0
	var t := 0.0
	var hp := 0.0
	var active := false
	var telegraphing := false
	var phase := 0
	var burst_in := -1.0           ## < 0: no flare
	var shove_t := -1.0            ## < 0: no shove winding up


## One decoded world section.
class Section extends RefCounted:
	var monsters: Array[NetHeroState] = []
	var employees: Array[NetHeroState] = []
	var gates: Array[GateState] = []


# --- Bytes -----------------------------------------------------------------------------------------------

## The world section for these entries (already chosen and in order). Entries are pre-packed (entry_bytes) so the host
## packs each one once per tick and compares it with what it sent before.
static func encode(monsters: Array[PackedByteArray], employees: Array[PackedByteArray], gates: Array[PackedByteArray]) -> PackedByteArray:
	var out := PackedByteArray()
	for part: Array[PackedByteArray] in [monsters, employees, gates]:
		out.append(mini(part.size(), MAX_ENTRIES))
		for i in mini(part.size(), MAX_ENTRIES):
			out.append_array(part[i])
	return out


## Read a world section from `b` (positioned at its start), for a packet stamped `stamp` (host_time seconds). A short
## or malformed section gives what was complete.
static func decode(b: StreamPeerBuffer, stamp: float) -> Section:
	var s := Section.new()
	if b.get_available_bytes() < 1:
		return s
	var n := b.get_u8()
	for _i in n:
		if b.get_available_bytes() < MONSTER_SIZE:
			return s
		s.monsters.append(get_monster(b, stamp))
	if b.get_available_bytes() < 1:
		return s
	n = b.get_u8()
	for _i in n:
		if b.get_available_bytes() < EMPLOYEE_SIZE:
			return s
		s.employees.append(get_employee(b, stamp))
	if b.get_available_bytes() < 1:
		return s
	n = b.get_u8()
	for _i in n:
		if b.get_available_bytes() < GATE_SIZE:
			return s
		s.gates.append(get_gate(b, stamp))
	return s


static func monster_bytes(s: NetHeroState) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u16(s.id & 0xFFFF)
	_put_motion(b, s)
	var flags := (s.mode & 7) | ((s.tp & 7) << 5)
	if s.climbing:
		flags |= FLAG_CLIMBING
	if s.helpless:
		flags |= FLAG_HELPLESS
	b.put_u8(flags)
	b.put_u8(clampi(roundi(s.telegraph * 255.0), 0, 255))
	b.put_u8(s.extra & 255)
	return b.data_array


static func get_monster(b: StreamPeerBuffer, stamp: float) -> NetHeroState:
	var s := NetHeroState.new()
	s.id = b.get_u16()
	_get_motion(b, s, stamp)
	var flags := b.get_u8()
	s.mode = flags & 7
	s.climbing = (flags & FLAG_CLIMBING) != 0
	s.helpless = (flags & FLAG_HELPLESS) != 0
	s.tp = (flags >> 5) & 7
	s.telegraph = float(b.get_u8()) / 255.0
	s.extra = b.get_u8()
	return s


static func employee_bytes(s: NetHeroState) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u16(s.id & 0xFFFF)
	_put_motion(b, s)
	var head := (s.mode & 7) | ((s.tp & 7) << 5)
	if s.helpless:
		head |= FLAG_DISMISSED   # (an employee's `helpless` slot carries "dismissed")
	if s.climbing:
		head |= FLAG_EMP_CLIMBING
	b.put_u8(head)
	b.put_u8(clampi(s.extra, 0, 255))
	return b.data_array


static func get_employee(b: StreamPeerBuffer, stamp: float) -> NetHeroState:
	var s := NetHeroState.new()
	s.id = b.get_u16()
	_get_motion(b, s, stamp)
	var head := b.get_u8()
	s.mode = head & 7
	s.helpless = (head & FLAG_DISMISSED) != 0
	s.climbing = (head & FLAG_EMP_CLIMBING) != 0
	s.tp = (head >> 5) & 7
	s.extra = b.get_u8()
	return s


static func gate_bytes(g: GateState) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u16(g.id & 0xFFFF)
	b.put_u16(clampi(roundi(g.hp * 10.0), 0, 65535))
	var flags := (g.phase & 3) << 2
	if g.active:
		flags |= GATE_ACTIVE
	if g.telegraphing:
		flags |= GATE_TELEGRAPH
	b.put_u8(flags)
	b.put_u8(NO_BYTE if g.burst_in < 0.0 else clampi(roundi(g.burst_in * 50.0), 0, 254))
	b.put_u8(NO_BYTE if g.shove_t < 0.0 else clampi(roundi(g.shove_t * 100.0), 0, 254))
	return b.data_array


static func get_gate(b: StreamPeerBuffer, stamp: float) -> GateState:
	var g := GateState.new()
	g.t = stamp
	g.id = b.get_u16()
	g.hp = float(b.get_u16()) / 10.0
	var flags := b.get_u8()
	g.active = (flags & GATE_ACTIVE) != 0
	g.telegraphing = (flags & GATE_TELEGRAPH) != 0
	g.phase = (flags >> 2) & 3
	var bi := b.get_u8()
	g.burst_in = -1.0 if bi == NO_BYTE else float(bi) / 50.0
	var sh := b.get_u8()
	g.shove_t = -1.0 if sh == NO_BYTE else float(sh) / 100.0
	return g


## Position (cm), velocity (1/8 u/s), facing and hp: the shared part of a mover's entry (11 bytes).
static func _put_motion(b: StreamPeerBuffer, s: NetHeroState) -> void:
	b.put_16(NetCodec._cm(s.pos.x))
	b.put_16(NetCodec._cm(s.pos.z))
	b.put_16(NetCodec._cm(s.pos.y))
	b.put_8(clampi(roundi(s.vel.x * 8.0), -127, 127))
	b.put_8(clampi(roundi(s.vel.y * 8.0), -127, 127))
	b.put_u8(roundi(wrapf(s.angle, 0.0, TAU) / TAU * 256.0) & 255)
	b.put_u16(clampi(roundi(s.hp * 10.0), 0, 65535))


static func _get_motion(b: StreamPeerBuffer, s: NetHeroState, stamp: float) -> void:
	s.t = stamp
	s.pos = Vector3(float(b.get_16()) / 100.0, 0.0, float(b.get_16()) / 100.0)
	s.pos.y = float(b.get_16()) / 100.0
	s.vel = Vector2(float(b.get_8()) / 8.0, float(b.get_8()) / 8.0)
	s.angle = float(b.get_u8()) / 256.0 * TAU
	s.hp = float(b.get_u16()) / 10.0


# --- Monsters: OWNER fields in and out -------------------------------------------------------------------

## Fill `st` from a monster (host). Position, velocity and the teleport counter are the sampler's.
static func read_monster(m: Monster, st: NetHeroState) -> void:
	st.hp = m.hp
	st.angle = atan2(m.facing.z, m.facing.x)
	st.climbing = m.climbing
	st.mode = m.state
	st.helpless = m.is_helpless()
	st.telegraph = m._telegraph
	st.extra = m.strikes & 255


## Show an (interpolated) state on a monster puppet (client). The monster's own net_show() plays what changed: the hit
## flash and the bar when HP drops, the wind-up's start and end, the swing when its strike count moves on.
static func write_monster(m: Monster, st: NetHeroState) -> void:
	m.global_position = st.pos
	var f := st.facing_vector()
	m.net_show(f, st.climbing, st.hp, st.mode, st.telegraph, st.extra)


# --- Runtime actors (a monster entry) -------------------------------------------------------------------------

## The RUNTIME_ACTORS entry of `a`'s class (or of a class it extends), {} when it is not a runtime actor.
static func runtime_entry(a: Object) -> Dictionary:
	var s: Script = a.get_script() as Script if a != null else null
	while s != null:
		if RUNTIME_ACTORS.has(s.resource_path):
			return RUNTIME_ACTORS[s.resource_path]
		s = s.get_base_script()
	return {}


static func is_runtime(a: Object) -> bool:
	return not runtime_entry(a).is_empty()


## The world.spawn kind of a runtime actor ("chicken").
static func runtime_kind(a: Object) -> String:
	return str(runtime_entry(a).get("kind", ""))


## The script of the runtime actor a world.spawn row names, or null (a monster kind).
static func runtime_script(kind: String) -> GDScript:
	for path: String in RUNTIME_ACTORS:
		if str(RUNTIME_ACTORS[path]["kind"]) == kind:
			return load(path) as GDScript
	return null


## Fill `st` from a runtime actor (host): what every actor has here, then the class's own slots (net_read: mode, telegraph,
## extra). Position, velocity and the teleport counter are the sampler's (NetWorld).
static func read_runtime(a: Actor, st: NetHeroState) -> void:
	st.hp = a.hp
	st.angle = atan2(a.facing.z, a.facing.x)
	st.climbing = a.climbing
	st.helpless = a.is_helpless()
	a.call("net_read", st)


## Show a state on a runtime actor's puppet (client): placed here, then shown by the class (net_write).
static func write_runtime(a: Actor, st: NetHeroState) -> void:
	a.global_position = st.pos
	a.call("net_write", st)


# --- Employees ---------------------------------------------------------------------------------------------

static func read_employee(e: Employee, st: NetHeroState) -> void:
	st.hp = e.hp
	st.angle = atan2(e.facing.z, e.facing.x)
	st.climbing = e.climbing
	st.mode = e.state
	st.helpless = e._dismissed
	var ld := e.leader()
	st.extra = clampi(NetFloor.id_of(ld), 0, NetSession.MAX_CREW) if ld != null and ld is Hero else 0


## Show a state on an employee puppet (client): position, facing, HP, its state (mood and pose follow it), who it
## follows (a hero by seat) and whether it was told to wait.
static func write_employee(e: Employee, st: NetHeroState) -> void:
	e.global_position = st.pos
	e.net_show(st.facing_vector(), st.climbing, st.hp, st.mode, st.helpless, NetRegistry.hero(st.extra) if st.extra > 0 else null)


# --- Hellgates ---------------------------------------------------------------------------------------------

static func read_gate(g: Hellgate, out: GateState) -> void:
	out.hp = g.hp
	out.active = g._active
	out.telegraphing = g._telegraphing
	out.phase = g.phase
	out.burst_in = maxf(g._next_burst_in, 0.0) if g._telegraphing else -1.0
	out.shove_t = g._shove_t if g._shove_t >= 0.0 else -1.0


static func write_gate(g: Hellgate, st: GateState) -> void:
	g.net_show(st.hp, st.active, st.telegraphing, st.phase, st.burst_in, st.shove_t)


## The most a pack/unpack round trip moves each quantity (tests).
static func quantum(what: String) -> float:
	match what:
		"telegraph":
			return 0.5 / 255.0
		"burst_in":
			return 0.01
		"shove_t":
			return 0.005
	return NetCodec.quantum(what)
