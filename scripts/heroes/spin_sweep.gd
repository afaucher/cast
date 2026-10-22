class_name SpinSweep
extends Node3D
## Gasket's spin under a profile with `strike_first` (grounded_anim): a TIMED sweep. The wrench head starts out at her right
## and goes once round her (counter-clockwise seen from above) on a fixed schedule (angle_at): a short twist back
## (ANTICIPATION), then the turn over turn_frames(). Each target is hit when the head passes ITS angle, once per spin; a
## teammate the head passes is shoved, as by today's spin. (The user, 2026-10-22, on the 7-frame whirl: "It's too fast! It
## doesn't read as a spin it is so fast."; the hits had all landed on the click.)
##
## A SCHEDULED EFFECT (AGENTS.md shape 1), like the bowl's boulder: the spin's start is the `act` every other screen already
## replays on its puppet at the moment it shows the act's time (NetCasts), so each machine runs the same schedule from the
## same shared moment, and applies only what it resolves (Combat.land_melee / shove_actors: the attacker's machine for the
## monsters and props, each teammate's own machine for its hero). Kinematic and deterministic: physics ticks, no randomness.
## The look (the whirl, the dust it drags round) is HeroFeel's, reading the same schedule.

const ANTICIPATION := 3         ## frames of twist back before the head moves forward
const TURN_FRAMES := 25         ## frames for the full turn (0.42 s): the pick of DEV_SPEEDS
const DEV_SPEEDS: Array[int] = [20, 25, 30]   ## what the test gym's F10 cycles through (quick, the pick, slow)
const TWIST := 0.45             ## rad the wrench is drawn back during the anticipation
const F := 1.0 / 60.0

## A dev override of TURN_FRAMES (0: the game's): the strike lab (--spin-frames) and the test gym (F10, "Spin speed", solo
## only) try others live. Never set in play.
static var dev_frames := 0

var source: Hero = null
var start_dir := Vector3.RIGHT  ## the head's direction at angle 0 (the hero's right when it spun)
var reach := 2.1
var damage := 16.0
var shove := 2.2
var elapsed := 0.0
var touched := 0                ## targets the head passed (hit here or not: every machine counts the same; HeroFeel, tests)
var _done := {}                 ## instance id -> true: passed once already
var _prev := -INF
var _heard := false


static func turn_frames() -> int:
	return dev_frames if dev_frames > 0 else TURN_FRAMES


## Seconds from the spin's start to the end of the turn.
static func duration() -> float:
	return float(ANTICIPATION + turn_frames()) * F


## The head's angle past its start (rad, counter-clockwise from above) `t` seconds after the spin started: back to -TWIST
## during the anticipation, then round to TAU, quick in the middle (a smoothstep: the whirl winds up and slows).
static func angle_at(t: float) -> float:
	var a := ANTICIPATION * F
	if t <= a:
		return -TWIST * smoothstep(0.0, a, t)
	var u := clampf((t - a) / (turn_frames() * F), 0.0, 1.0)
	return lerpf(-TWIST, TAU, u * u * (3.0 - 2.0 * u))


## The angle (0..TAU, the sweep's way round) at which the head passes `to` (a direction from the hero, X/Z).
static func angle_of(start: Vector3, to: Vector3) -> float:
	return wrapf(atan2(-to.z, to.x) - atan2(-start.z, start.x), 0.0, TAU)


## Start the spin of `hero`, facing `facing` (X/Z), now. Every machine calls it from Hero._spin_effect.
static func start(hero: Hero, facing: Vector3, spin_reach: float, spin_damage: float, spin_shove: float) -> SpinSweep:
	var s := SpinSweep.new()
	s.source = hero
	facing.y = 0.0
	facing = facing.normalized() if facing.length() > 0.001 else Vector3.FORWARD
	s.start_dir = facing.rotated(Vector3.UP, -PI * 0.5)   # (the wrench is held out at her right)
	s.reach = spin_reach
	s.damage = spin_damage
	s.shove = spin_shove
	GameWorld.spawn(s, hero.global_position)
	return s


func net_fields() -> Dictionary:
	return {
		"source": Net.SPAWN, "start_dir": Net.SPAWN, "reach": Net.SPAWN, "damage": Net.SPAWN, "shove": Net.SPAWN,
		"elapsed": Net.LOCAL, "touched": Net.LOCAL, "_done": Net.LOCAL, "_prev": Net.LOCAL, "_heard": Net.LOCAL,
	}


## Where the head points now (X/Z, unit).
func head_dir() -> Vector3:
	return start_dir.rotated(Vector3.UP, angle_at(elapsed))


func _physics_process(delta: float) -> void:
	if source == null or not is_instance_valid(source) or source.dead:
		queue_free()
		return
	elapsed += delta
	var now := angle_at(elapsed)
	if now >= 0.0:
		_sweep(maxf(_prev, -0.0001), minf(now, TAU))
		_prev = now
	if elapsed >= duration():
		queue_free()


## Every target whose angle the head crossed between `from` and `to` (rad), once each.
func _sweep(from: float, to: float) -> void:
	if to <= from:
		return
	var pos := source.global_position
	global_position = pos
	var foes: Array[Actor] = []
	for a in Combat.arc_targets(source, start_dir, reach, 360.0):
		if _passed(a, pos, from, to):
			foes.append(a)
	var mates: Array[Actor] = []
	for a in GameWorld.actors_in_radius(pos, reach, source.team):
		if a != source and absf(a.global_position.y - pos.y) <= 2.1 * Hex.LEVEL_HEIGHT and _passed(a, pos, from, to):
			mates.append(a)
	if foes.is_empty() and mates.is_empty():
		return
	touched += foes.size() + mates.size()
	if not Combat.land_melee(source, foes, head_dir(), damage, shove).is_empty() and not _heard:
		_heard = true
		MonsterSenses.noise(pos, MonsterSenses.NOISE_MELEE, "melee")
	Combat.shove_actors(mates, pos, shove, source)   # (a teammate's machine shoves its own hero)
	if source._feel != null:
		source._feel.spin_pass(foes.size() + mates.size())


func _passed(a: Actor, pos: Vector3, from: float, to: float) -> bool:
	var id := a.get_instance_id()
	if _done.has(id):
		return false
	var d := a.global_position - pos
	d.y = 0.0
	var phi := angle_of(start_dir, d) if d.length() > 0.001 else 0.0
	if phi > from and phi <= to or (from < 0.0 and phi == 0.0):
		_done[id] = true
		return true
	return false
