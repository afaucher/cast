class_name NetHeroState
extends RefCounted
## One hero's replicated state at one moment: what an owner packs into a snapshot (NetCodec) and what a puppet
## is shown (NetInterp). Plain data, in game units (the wire quantises it).
##
## M3: the host-owned movers (monsters, employees) reuse it as their sample (NetWorldCodec, NetWorld), so one buffer and
## one interpolation serve every puppet. `id` is then the net id and the M3 fields below carry what those classes add.

var seat := 0
## The sample's moment on the shared clock (host_time seconds).
var t := 0.0
var pos := Vector3.ZERO
## Horizontal velocity (x, z) in units per second: Hermite tangents, and the extrapolation when a packet is late.
var vel := Vector2.ZERO
## Facing as atan2(z, x) of the unit facing vector.
var angle := 0.0
## The aim point relative to the hero (x, z), clamped to AIM_MAX on the wire.
var aim := Vector2.ZERO
var hp := 0.0
var held_slot := 0
var dead := false
var climbing := false
## Passing through other heroes (Actor.pass_through_until is in the future).
var ghost := false
## The bow is drawn; draw_age is how long (seconds).
var drawing := false
var draw_age := 0.0
## Teleport counter (0-15): it changes when the hero jumps, so a receiver never blends across the gap.
var tp := 0
## M6: the seat's ownership epoch (mod 16) when the sample was taken; a receiver drops a sample from an older owner.
var epoch := 0
## M3, host-owned movers: the net id, the state machine's state, a wind-up 0..1 (interpolated), a byte the class uses
## (a monster's strike count, an employee's leader seat) and a flag (a monster is helpless, an employee dismissed).
var id := 0
var mode := 0
var telegraph := 0.0
var extra := 0
var helpless := false


func facing_vector() -> Vector3:
	return Vector3(cos(angle), 0.0, sin(angle))


func aim_point() -> Vector3:
	return pos + Vector3(aim.x, 0.0, aim.y)


func copy() -> NetHeroState:
	var s := NetHeroState.new()
	s.seat = seat
	s.t = t
	s.pos = pos
	s.vel = vel
	s.angle = angle
	s.aim = aim
	s.hp = hp
	s.held_slot = held_slot
	s.dead = dead
	s.climbing = climbing
	s.ghost = ghost
	s.drawing = drawing
	s.draw_age = draw_age
	s.tp = tp
	s.epoch = epoch
	s.id = id
	s.mode = mode
	s.telegraph = telegraph
	s.extra = extra
	s.helpless = helpless
	return s
