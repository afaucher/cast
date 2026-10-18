class_name NetCodec
extends RefCounted
## The hero snapshot, hand-packed (docs/design/networking-build-plan.md M2): what rides in a NetWire.T_SNAP
## packet, how much of it is quantised, and how a hero's OWNER fields go in and out.
##
## PAYLOAD  (after NetWire's 7-byte header: u8 type | u16 seq | u32 stamp_ms)
##   u8  count                                  heroes in this packet (a client sends 1, the host sends up to 2)
##   count x ENTRY
##
## ENTRY (16 bytes, 17 with the bow drawn)
##   u8  head    seat (bits 0-1, 1-3) | held_slot (bits 2-3) | teleport counter (bits 4-7)
##   u8  flags   dead 1 | climbing 2 | ghost 4 | drawing 8 | the seat's ownership EPOCH mod 16 (bits 4-7, M6: a sample from
##               the seat's previous owner is dropped by everyone once the seat has changed hands)
##   u8  age     ms between the sample and the packet's stamp: 0 for the sender's own hero, more for a client's hero
##               the host FORWARDS (the sample time is stamp - age, so everyone shares one timeline)
##   i16 x, z, y   centimetres
##   i8  vx, vz    velocity in 1/8 unit per second (+-15.9)
##   u8  angle     facing, 256 steps of a turn
##   i8  aimx, aimz  the aim point relative to the hero in 1/4 unit (+-31.75)
##   u16 hp        tenths of a point
##   u8  draw      only when flags has drawing: how long the bow has been drawn, centiseconds
##
## A snapshot to the host is 7 + 1 + 16 = 24 bytes; the host's to a client carries two heroes, 40 bytes; at 30 Hz
## that is 0.72 KB/s up and 1.2 KB/s down per client (the plan's budget is 3 KB/s). M3: the host appends the world
## section (NetWorldCodec: monsters, employees, hellgates) after the heroes in the same packet.
##
## HERO_FIELDS is the list the contract test holds this codec to: every var in it must be OWNER on Hero (a codec
## must never stream a SPAWN / PRIVATE / LOCAL var), and every OWNER var of Hero must be in it or in
## NetEvents.CARRIES. Position, velocity, aim and the teleport counter are not vars, they come from the sampler.

const SNAP_TYPE := NetWire.T_SNAP
const FLAG_DEAD := 1
const FLAG_CLIMBING := 2
const FLAG_GHOST := 4
const FLAG_DRAWING := 8
const ENTRY_SIZE := 16
const ENTRY_SIZE_DRAWING := 17
const HEADER_SIZE := NetWire.HEADER + 1     ## the wire header plus the count byte
const AIM_MAX := 31.75
const VEL_MAX := 15.875
const POS_MAX := 327.67
## How long a received "passing through" flag keeps the puppet a ghost (it is refreshed by every snapshot).
const GHOST_HOLD := 0.3

## Hero / Actor var -> the part of the entry that carries it.
const HERO_FIELDS := {
	"hp": "hp",
	"dead": "flags",
	"facing": "angle",
	"climbing": "flags",
	"pass_through_until": "flags",
	"held_slot": "head",
	"_draw_start": "draw",
}
## Carried, but not vars of the hero.
const EXTRA_CARRIERS := ["position", "velocity", "aim", "teleport"]


# --- Packing -------------------------------------------------------------------------------------------

## The payload for `states`; `sent_at` is the packet's moment on the shared clock (ages are measured to it).
static func encode(states: Array[NetHeroState], sent_at: float) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(states.size())
	for s in states:
		_put_entry(b, s, sent_at)
	return b.data_array


static func _put_entry(b: StreamPeerBuffer, s: NetHeroState, sent_at: float) -> void:
	b.put_u8((s.seat & 3) | ((s.held_slot & 3) << 2) | ((s.tp & 15) << 4))
	var flags := 0
	if s.dead:
		flags |= FLAG_DEAD
	if s.climbing:
		flags |= FLAG_CLIMBING
	if s.ghost:
		flags |= FLAG_GHOST
	if s.drawing:
		flags |= FLAG_DRAWING
	flags |= (s.epoch & 15) << 4
	b.put_u8(flags)
	b.put_u8(clampi(roundi((sent_at - s.t) * 1000.0), 0, 255))
	b.put_16(_cm(s.pos.x))
	b.put_16(_cm(s.pos.z))
	b.put_16(_cm(s.pos.y))
	b.put_8(clampi(roundi(s.vel.x * 8.0), -127, 127))
	b.put_8(clampi(roundi(s.vel.y * 8.0), -127, 127))
	b.put_u8(roundi(wrapf(s.angle, 0.0, TAU) / TAU * 256.0) & 255)
	b.put_8(clampi(roundi(s.aim.x * 4.0), -127, 127))
	b.put_8(clampi(roundi(s.aim.y * 4.0), -127, 127))
	b.put_u16(clampi(roundi(s.hp * 10.0), 0, 65535))
	if s.drawing:
		b.put_u8(clampi(roundi(s.draw_age * 100.0), 0, 255))


## The states in a payload that arrived in a packet stamped `stamp` (host_time seconds). Malformed or short data
## gives what was complete; an entry with an impossible seat is skipped.
static func decode(payload: PackedByteArray, stamp: float) -> Array[NetHeroState]:
	var b := StreamPeerBuffer.new()
	b.data_array = payload
	return decode_from(b, stamp)


## The hero entries read from `b` (positioned at the count byte); `b` is left just past them, where the host's
## packet goes on with the world (NetWorldCodec, M3).
static func decode_from(b: StreamPeerBuffer, stamp: float) -> Array[NetHeroState]:
	var out: Array[NetHeroState] = []
	if b.get_available_bytes() < 1:
		return out
	var count := b.get_u8()
	for _i in count:
		if b.get_available_bytes() < ENTRY_SIZE:
			break
		var s := NetHeroState.new()
		var head := b.get_u8()
		var flags := b.get_u8()
		s.seat = head & 3
		s.held_slot = (head >> 2) & 3
		s.tp = (head >> 4) & 15
		s.dead = (flags & FLAG_DEAD) != 0
		s.climbing = (flags & FLAG_CLIMBING) != 0
		s.ghost = (flags & FLAG_GHOST) != 0
		s.drawing = (flags & FLAG_DRAWING) != 0
		s.epoch = (flags >> 4) & 15
		s.t = stamp - float(b.get_u8()) / 1000.0
		s.pos = Vector3(float(b.get_16()) / 100.0, 0.0, float(b.get_16()) / 100.0)
		s.pos.y = float(b.get_16()) / 100.0
		s.vel = Vector2(float(b.get_8()) / 8.0, float(b.get_8()) / 8.0)
		s.angle = float(b.get_u8()) / 256.0 * TAU
		s.aim = Vector2(float(b.get_8()) / 4.0, float(b.get_8()) / 4.0)
		s.hp = float(b.get_u16()) / 10.0
		if s.drawing:
			if b.get_available_bytes() < 1:
				break
			s.draw_age = float(b.get_u8()) / 100.0
		if s.seat >= 1 and s.seat <= NetSession.MAX_CREW:
			out.append(s)
	return out


## Bytes a packet with these states takes on the wire (header included).
static func packet_size(states: Array[NetHeroState]) -> int:
	var n := HEADER_SIZE
	for s in states:
		n += ENTRY_SIZE_DRAWING if s.drawing else ENTRY_SIZE
	return n


## `value` (world units) as centimetres in an i16.
static func _cm(v: float) -> int:
	return clampi(roundi(v * 100.0), -32768, 32767)


## The quantum of each carried quantity: the most a pack/unpack round trip can move it.
static func quantum(what: String) -> float:
	match what:
		"position":
			return 0.005
		"velocity":
			return 1.0 / 16.0
		"angle":
			return TAU / 512.0
		"aim":
			return 1.0 / 8.0
		"hp":
			return 0.05
		"draw":
			return 0.005
		"time":
			return 0.0005
	return 0.0


# --- The hero's OWNER fields ----------------------------------------------------------------------------

## Fill `st` from the hero's OWNER vars (HERO_FIELDS). Position, velocity, aim and the teleport counter are the
## sampler's.
static func read_hero(hero: Hero, st: NetHeroState) -> void:
	st.hp = hero.hp
	st.dead = hero.dead
	st.angle = atan2(hero.facing.z, hero.facing.x)
	st.climbing = hero.climbing
	st.ghost = hero.pass_through_until > GameWorld.time
	st.held_slot = hero.held_slot
	st.drawing = hero.is_drawing()
	st.draw_age = maxf(GameWorld.time - hero._draw_start, 0.0) if st.drawing else 0.0


## Put a (decoded, interpolated) state onto a puppet. HP, death, the bow and the held spell show on its screen the
## way they do on its owner's; nothing here is damage or a cast (those are events: M4).
static func write_hero(hero: Hero, st: NetHeroState) -> void:
	hero.global_position = st.pos
	hero.facing = st.facing_vector()
	hero.climbing = st.climbing
	if st.ghost:
		hero.pass_through_until = GameWorld.time + GHOST_HOLD
	elif hero.pass_through_until > GameWorld.time:
		hero.pass_through_until = 0.0
	if hero.held_slot != st.held_slot:
		hero.held_slot = st.held_slot
		hero._refresh_hold()
		hero.held_changed.emit()
	if absf(hero.hp - st.hp) > 0.05 and not hero.dead:
		hero.hp = st.hp
		hero._refresh_bar()
	if st.drawing:
		if hero._draw_start < 0.0 or absf((GameWorld.time - hero._draw_start) - st.draw_age) > 0.2:
			hero._draw_start = GameWorld.time - st.draw_age
	elif hero._draw_start >= 0.0:
		hero.cancel_draw()
	if st.dead and not hero.dead:
		hero.hp = 0.0
		hero.dead = true
		hero.died.emit()
		GameWorld.actor_died.emit(hero)
		hero._on_death()
