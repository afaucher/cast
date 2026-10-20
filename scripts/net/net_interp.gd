class_name NetInterp
extends RefCounted
## The interpolation buffer behind one puppet (docs/design/networking-build-plan.md M2b): snapshot samples of a
## remote hero, shown about DELAY behind the shared clock so the puppet is always BETWEEN two samples and moves on
## smoothly through a lost packet or a late one.
##
##   position  Hermite (cubic) on x and z from the samples' positions AND velocities, linear on height
##   facing    the short way round between the two samples
##   the rest  (hp, dead, the held slot, the bow) is a step: the earlier sample's value, so a death lands on the
##             same beat as the movement that led to it (M3: a monster's wind-up is linear within one state)
##
## When the render time runs past the newest sample (a packet is late or lost) the puppet extrapolates along the
## last velocity for up to EXTRAP_MAX seconds, then holds. A TELEPORT (the sample's counter changed) empties the
## buffer: the puppet jumps to the new spot and never slides across the gap.
##
## The delay is adaptive: it follows the 90th percentile of how late samples arrive (arrival time minus sample
## time) plus a margin, never below DELAY. A direct stream on a good link sits at DELAY; a hero forwarded through
## the host (two hops) or a bad link gets the extra room it needs, and the change is slewed (at most 10%) so the
## motion never visibly speeds up or stalls.

const DELAY := 0.10
const DELAY_MAX := 0.40
const MARGIN := 0.03
const EXTRAP_MAX := 0.12
const KEEP := 24             ## samples kept
const LAG_WINDOW := 60       ## arrival lags the percentile looks at (2 s of a 30 Hz stream)
const WARMUP := 8            ## the first samples set the delay outright
const SLEW := 0.10           ## the delay moves at most this fraction of a second per second
const LINEAR_GAP := 0.25     ## samples farther apart than this (a stall) are blended linearly: a stale velocity would overshoot

var delay := DELAY
var samples: Array[NetHeroState] = []
## How many teleports (counter changes) the stream had.
var teleports := 0
## Samples accepted / refused as not newer than the newest.
var accepted := 0
var refused := 0

var _lags: Array[float] = []
var _tp := -1
var _teleported := false
var _target := DELAY


## Add a sample that arrived at `arrival` (host_time seconds). False when it is not newer than what we have.
func push(s: NetHeroState, arrival: float) -> bool:
	if not samples.is_empty() and s.t <= samples[samples.size() - 1].t + 0.0001:
		refused += 1
		return false
	if _tp != -1 and s.tp != _tp:
		samples.clear()
		teleports += 1
		_teleported = true
	_tp = s.tp
	samples.append(s)
	if samples.size() > KEEP:
		samples.remove_at(0)
	accepted += 1
	_lags.append(maxf(arrival - s.t, 0.0))
	if _lags.size() > LAG_WINDOW:
		_lags.remove_at(0)
	_target = _compute_target()
	if accepted <= WARMUP:
		delay = _target
	return true


## True once after a teleport sample was pushed (the puppet resets its physics interpolation).
func take_teleport() -> bool:
	var t := _teleported
	_teleported = false
	return t



func _compute_target() -> float:
	if _lags.is_empty():
		return DELAY
	var sorted := _lags.duplicate()
	sorted.sort()
	var p90: float = sorted[mini(int(float(sorted.size()) * 0.9), sorted.size() - 1)]
	return clampf(p90 + MARGIN, DELAY, DELAY_MAX)


## Move the delay toward its target by `dt` seconds' worth of slewing.
func step_delay(dt: float) -> void:
	var step := SLEW * dt
	delay += clampf(_target - delay, -step, step)


func newest() -> NetHeroState:
	return samples[samples.size() - 1] if not samples.is_empty() else null


func clear() -> void:
	samples.clear()
	_lags.clear()
	_tp = -1
	_teleported = false
	_target = DELAY
	delay = DELAY
	accepted = 0


## The state to show at shared-clock time `t`, or null with no samples. A new object every call.
func sample(t: float) -> NetHeroState:
	if samples.is_empty():
		return null
	var first := samples[0]
	if t <= first.t:
		var s := first.copy()
		s.t = t
		return s
	var last := samples[samples.size() - 1]
	if t >= last.t:
		var s := last.copy()
		var dt := minf(t - last.t, EXTRAP_MAX)
		s.pos += Vector3(last.vel.x * dt, 0.0, last.vel.y * dt)
		s.t = t
		return s
	var i := samples.size() - 2
	while i > 0 and samples[i].t > t:
		i -= 1
	var a := samples[i]
	var b := samples[i + 1]
	var h := b.t - a.t
	var u := clampf((t - a.t) / maxf(h, 0.0001), 0.0, 1.0)
	var out := a.copy()
	out.t = t
	if h > LINEAR_GAP:
		out.pos = a.pos.lerp(b.pos, u)
	else:
		var x := _hermite(a.pos.x, a.vel.x, b.pos.x, b.vel.x, h, u)
		var z := _hermite(a.pos.z, a.vel.y, b.pos.z, b.vel.y, h, u)
		out.pos = Vector3(x, lerpf(a.pos.y, b.pos.y, u), z)
	out.vel = a.vel.lerp(b.vel, u)
	out.angle = lerp_angle(a.angle, b.angle, u)
	out.aim = a.aim.lerp(b.aim, u)
	if a.mode == b.mode:
		out.telegraph = lerpf(a.telegraph, b.telegraph, u)   # (M3: a wind-up grows smoothly between samples)
	return out


## Cubic Hermite: positions p0 / p1, velocities v0 / v1 (per second), samples h seconds apart, u in 0..1.
static func _hermite(p0: float, v0: float, p1: float, v1: float, h: float, u: float) -> float:
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * p0 + (u3 - 2.0 * u2 + u) * v0 * h \
			+ (-2.0 * u3 + 3.0 * u2) * p1 + (u3 - u2) * v1 * h
