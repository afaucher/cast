class_name HeroFeel
extends RefCounted
## The animation track's treatment B and strike-first melee in the game (docs/design/animation-research.md "As built"),
## under a MoveFeel profile with `body` / `strike_first` on (grounded_anim). Lifted from the look-dev layer
## (scripts/art/lowpoly/anim_lab_feel.gd); the stride and the legs stay Gait's (HeroGait). COSMETIC, on every screen, for
## every hero with a faceted model, from the motion that screen shows (a puppet's streamed position too) and the events
## every screen already has (a melee swing is replayed on a puppet as an `act`): nothing here is gameplay, nothing travels,
## no randomness.
##
##   - LEAN: a pivot node between Hero._visual and the model leans the whole body toward where it is going: the smoothed
##     velocity times `lean` plus the acceleration (quick velocity minus smoothed) times `kick`, through a spring (`f` Hz,
##     `zeta`) per hero, so starting tips it forward, stopping throws it back and it settles, turning banks it. Never past
##     LEAN_MAX (22 degrees). A shove tips it back against the slide (the feet go first).
##   - SQUASH: a spring kicked on starting (a stretch) and stopping (a squash), about the feet, within SQUASH_MIN..SQUASH_MAX.
##   - STRIKE FIRST: a melee swing's pose is driven from here (STRIKES: kick channels on the model) so the weapon is at its
##     impact on the frame the hit resolves (Hero.melee resolves on the click frame), then a small lunge, a forward pitch
##     and, when the blow touched something, a HITSTOP freeze of this hero's pose only (the model and this layer hold for
##     `hitstop` (50 ms; Gasket's smash 83 ms; the simulation, the hero's motion and the damage are untouched). Gasket's and
##     Rebar's big overhead shapes play in the follow-through (STYLE "follow") or as a 2-frame wind-up before the impact
##     ("wind": the lab's alternative). A SMASH (the hit area says `smash`: Gasket's hammer) also marks its landing on the
##     floor (Fx.ground_smash: cracks, a shock ring, dust) on every screen, and nudges the camera of the attacker's own
##     screen only (`shake`).
##   - The stride is held while shoved or airborne (HeroGait asks `body`): the legs stop walking under a sliding body.

## Per-hero personality (the lab's numbers): lean rad per unit/s, kick rad per unit/s of velocity change, the lean spring
## (f Hz, zeta: lower f is heavier, lower zeta overshoots more), the squash impulse scale, the strike's lunge (units) and
## forward pitch kick (rad/s), the hit-stop on a connect (s) and the own-screen camera nudge of a smash.
const TUNING := {
	"wick": {"lean": 0.032, "kick": 0.075, "f": 2.6, "zeta": 0.42, "squash": 1.0, "lunge": 0.16, "pitch": 3.2, "hitstop": 0.05, "shake": 0.0},
	"gasket": {"lean": 0.028, "kick": 0.065, "f": 3.2, "zeta": 0.50, "squash": 1.2, "lunge": 0.14, "pitch": 2.6, "hitstop": 0.083, "shake": 0.12},
	"rebar": {"lean": 0.018, "kick": 0.045, "f": 1.7, "zeta": 0.65, "squash": 0.6, "lunge": 0.10, "pitch": 1.8, "hitstop": 0.05, "shake": 0.0},
}
const LEAN_MAX := 0.38             ## rad (22 degrees), the lean's hard limit
const SQUASH_MIN := -0.16          ## a stretch (the body 16% taller)
const SQUASH_MAX := 0.20           ## a squash (20% shorter)
const SQUASH_F := 4.5
const SQUASH_ZETA := 0.32
const START_KICK := -3.0           ## the squash spring's impulse on a start (a stretch, about 7%) ...
const STOP_KICK := 4.0             ## ... and on a stop from a walk (a squash, about 10%); both x the hero's `squash`
const KICK_SPEED := 4.5            ## the walk the impulses are sized for (a slower start or stop kicks less)
const MOVING := 0.5                ## shown speed (u/s) above which the body counts as moving
const SHOVE_LEAN := 0.07           ## rad per unit/s of slide: the head left behind by a shove
const HITSTOP := 0.05              ## s: the attacker's freeze when its blow touches something (3 frames at 60 Hz; TUNING's)
const LUNGE_DECAY := 10.0
const F := 1.0 / 60.0              ## STRIKES' keys are in 60ths of a second

## The strike timelines: kit (or kit + "_wind") -> {"impact": the key frame of the impact pose, channel -> [[frame, value],
## ...]}. Each channel is a kick the model's apply_idle reads (WickModel bash / follow, GasketModel smash_w / smash_a,
## RebarModel slam_w / slam_a); between keys the value eases out. Frame 0 is the click; the hit has already resolved.
const STRIKES := {
	"wick": {"impact": 1, "squash": -1.5, "keys": {
		"bash": [[0, 0.0], [1, -1.2], [3, -1.2], [9, -1.2], [26, 0.0]],
		"follow": [[0, 0.0], [3, 0.0], [9, 1.0], [26, 0.0]]}},
	# Gasket: the wrench lands on her centre line on the click's frame, holds, bounces back up over her head (her big
	# overhead silhouette, now in the follow-through) and settles at her side.
	"gasket": {"impact": 1, "squash": 3.0, "keys": {
		"smash_w": [[0, 0.0], [1, 1.0], [20, 1.0], [36, 0.0]],
		"smash_a": [[0, GasketModel.SMASH_DOWN], [3, GasketModel.SMASH_DOWN], [14, GasketModel.SMASH_UP], [20, GasketModel.SMASH_UP], [36, 0.0]]}},
	"gasket_wind": {"impact": 4, "squash": 3.0, "keys": {
		"smash_w": [[0, 0.0], [2, 1.0], [20, 1.0], [36, 0.0]],
		"smash_a": [[0, GasketModel.SMASH_UP], [2, GasketModel.SMASH_UP], [4, GasketModel.SMASH_DOWN], [8, GasketModel.SMASH_DOWN], [20, -0.6], [36, 0.0]]}},
	# Rebar: both fists come down together in front of him on the click's frame, then lift back over his head and drop.
	"rebar": {"impact": 1, "squash": 2.5, "keys": {
		"slam_w": [[0, 0.0], [1, 1.0], [20, 1.0], [38, 0.0]],
		"slam_a": [[0, RebarModel.SLAM_DOWN], [3, RebarModel.SLAM_DOWN], [15, RebarModel.SLAM_UP], [20, RebarModel.SLAM_UP], [38, 0.0]]}},
	"rebar_wind": {"impact": 4, "squash": 2.5, "keys": {
		"slam_w": [[0, 0.0], [2, 1.0], [20, 1.0], [38, 0.0]],
		"slam_a": [[0, RebarModel.SLAM_UP], [2, RebarModel.SLAM_UP], [4, RebarModel.SLAM_DOWN], [8, RebarModel.SLAM_DOWN], [20, 0.6], [38, 0.0]]}},
}
## Which timeline the heavy hitters play: "follow" (the overhead shape after the impact: impact on the click's frame) or
## "wind" (a 2-frame wind-up: impact 3 frames after the click). The lab sets it to compare (--strike); the game plays FOLLOW.
const FOLLOW := "follow"
const WIND := "wind"
static var style := FOLLOW

var hero: Hero
var pivot: Node3D = null           ## between Hero._visual and the model: carries the lean, the squash and the lunge
var model: LowPolyModel = null
var lean := Vector2.ZERO           ## x = pitch (negative: forward), y = roll (rad)
var squash := 0.0                  ## + squash / - stretch
var strikes := 0                   ## swings played (tests)
var impact_frame := -1             ## Engine process frame the last strike's impact pose was shown on (tests)
var max_lean := 0.0                ## the largest lean shown so far (tests)
var _tu: Dictionary = {}
var _prev := Vector3.INF
var _vs := Vector3.ZERO            ## the shown velocity, smoothed slowly (the body's mass)
var _vq := Vector3.ZERO            ## ... and quickly (what the feet are doing now)
var _lean_v := Vector2.ZERO
var _sq_v := 0.0
var _moving := false
var _top := 0.0                    ## the recent top speed (decays at 6 u/s per s)
var _lunge := 0.0
var held_frames := 0               ## frames of hit-stop shown so far (tests)
var _freeze := 0.0                 ## s of hit-stop left
var _held := false                 ## this frame is a hit-stop frame
var _strike: Dictionary = {}       ## the timeline playing ({} none)
var _age := -1.0                   ## s since the click (-1: no strike)
var _connect := false              ## the blow touched something (a hit-stop at the impact)
var _dir := Vector3.FORWARD        ## the swing's direction (X/Z)
var smashes := 0                   ## smash landings marked on the floor (tests)
var _impacted := false


func _init(h: Hero = null) -> void:
	hero = h


func net_fields() -> Dictionary:
	return {
		"hero": Net.LOCAL, "pivot": Net.LOCAL, "model": Net.LOCAL, "lean": Net.LOCAL, "squash": Net.LOCAL,
		"strikes": Net.LOCAL, "impact_frame": Net.LOCAL, "max_lean": Net.LOCAL, "_tu": Net.LOCAL, "_prev": Net.LOCAL,
		"_vs": Net.LOCAL, "_vq": Net.LOCAL, "_lean_v": Net.LOCAL, "_sq_v": Net.LOCAL, "_moving": Net.LOCAL,
		"_lunge": Net.LOCAL, "_freeze": Net.LOCAL, "_strike": Net.LOCAL, "_age": Net.LOCAL, "_connect": Net.LOCAL,
		"_impacted": Net.LOCAL, "held_frames": Net.LOCAL, "_held": Net.LOCAL, "_top": Net.LOCAL, "_dir": Net.LOCAL,
		"smashes": Net.LOCAL,
	}


## True while this layer drives the hero's body (the profile has `body` and the hero wears a faceted model it knows).
func active() -> bool:
	return pivot != null and model != null


## True on a frame of hit-stop: the pose holds (HeroGait does not advance or re-pose the model this frame).
func frozen() -> bool:
	return active() and _held


## One rendered frame (Hero._process, after the body's yaw, before HeroGait poses the model).
func tick(delta: float) -> void:
	if not MoveFeel.on("body") or hero.dead or not hero.is_inside_tree() or delta <= 0.0:
		stop()
		return
	var m := hero.visual_override as LowPolyModel
	if m != model:
		stop()
	if model == null:
		if m == null or not TUNING.has(hero.kit_id) or m.get_parent() == null or m.is_queued_for_deletion():
			return
		_attach(m)
	var pos := hero.global_position
	if _prev == Vector3.INF:
		_prev = pos
	var raw := (pos - _prev) / delta
	raw.y = 0.0
	_prev = pos
	if raw.length() > 20.0:
		raw = Vector3.ZERO   # a teleport
	_held = _freeze > 0.002   # (not a float's crumb: 3 frames at 60 Hz)
	if _held:
		_freeze -= delta
		held_frames += 1
		return   # (the hit-stop: everything this layer and the gait show holds still)
	_vq += (raw - _vq) * clampf(delta * 25.0, 0.0, 1.0)
	_vs += (_vq - _vs) * clampf(delta * 9.0, 0.0, 1.0)

	# --- the lean: where the head goes, through a spring ------------------------------------------------------------
	var yaw := hero._visual_yaw
	var lv: Vector3
	if hero.is_shoved():
		lv = -_vq.rotated(Vector3.UP, -yaw) * SHOVE_LEAN
	else:
		lv = _vs.rotated(Vector3.UP, -yaw) * float(_tu["lean"]) + (_vq - _vs).rotated(Vector3.UP, -yaw) * float(_tu["kick"])
	var target := Vector2(lv.z, -lv.x).limit_length(LEAN_MAX)
	var px := _spring(lean.x, _lean_v.x, target.x, float(_tu["f"]), float(_tu["zeta"]), delta)
	var py := _spring(lean.y, _lean_v.y, target.y, float(_tu["f"]), float(_tu["zeta"]), delta)
	lean = Vector2(px.x, py.x)
	_lean_v = Vector2(px.y, py.y)
	if lean.length() > LEAN_MAX:
		lean = lean.limit_length(LEAN_MAX)
		_lean_v *= 0.5
	max_lean = maxf(max_lean, lean.length())

	# --- squash on start / stop -------------------------------------------------------------------------------------
	var moving := _vq.length() > MOVING
	_top = maxf(_top - delta * 6.0, _vq.length())   # (the speed the hero just had: a stop is sized by it)
	if moving != _moving:
		var k := 1.0 if moving else clampf(_top / KICK_SPEED, 0.3, 1.2)
		_sq_v += (START_KICK if moving else STOP_KICK) * float(_tu["squash"]) * k
		_moving = moving
	var s := _spring(squash, _sq_v, 0.0, SQUASH_F, SQUASH_ZETA, delta)
	squash = clampf(s.x, SQUASH_MIN, SQUASH_MAX)
	_sq_v = s.y if squash == s.x else 0.0

	# --- the strike ------------------------------------------------------------------------------------------------
	_step_strike(delta)
	_lunge = lerpf(_lunge, 0.0, clampf(delta * LUNGE_DECAY, 0.0, 1.0))

	pivot.rotation = Vector3(lean.x, 0.0, lean.y)
	pivot.scale = Vector3(1.0 + squash * 0.5, 1.0 - squash, 1.0 + squash * 0.5)
	pivot.position = Vector3(0.0, 0.0, -_lunge)


## The hero swung (Hero._swing_pose: on the owner's click, or replayed on a puppet). `connects`: the blow touched something
## (a hit-stop at the impact); `dir` the swing's direction (a smash marks its landing that way). False (the caller plays
## the model's own swing) when this layer is not driving the body.
func strike(connects: bool, dir: Vector3 = Vector3.ZERO) -> bool:
	if not active() or not MoveFeel.on("strike_first"):
		return false
	var key := hero.kit_id
	if style == WIND and STRIKES.has(key + "_wind"):
		key += "_wind"
	if not STRIKES.has(key):
		return false
	_strike = STRIKES[key]
	_age = 0.0
	_connect = connects
	_dir = Vector3(dir.x, 0.0, dir.z).normalized() if Vector3(dir.x, 0.0, dir.z).length() > 0.001 else hero.facing
	_impacted = false
	strikes += 1
	return true


## The frame (60ths of a second after the click) the playing timeline reaches its impact pose (tests, the lab).
func impact_key() -> int:
	return int(_strike.get("impact", -1))


## Hand the body back: the model under Hero._visual again, upright, its strike channels at rest.
func stop() -> void:
	if model != null and is_instance_valid(model):
		for ch: String in _channels():
			model._arm_kick[ch] = 0.0
		if pivot != null and is_instance_valid(pivot) and model.get_parent() == pivot and not model.is_queued_for_deletion():
			var vis := pivot.get_parent()
			if vis != null:
				model.reparent(vis, false)
	if pivot != null and is_instance_valid(pivot):
		pivot.queue_free()
	pivot = null
	model = null
	_prev = Vector3.INF
	_vs = Vector3.ZERO
	_vq = Vector3.ZERO
	lean = Vector2.ZERO
	_lean_v = Vector2.ZERO
	squash = 0.0
	_sq_v = 0.0
	_moving = false
	_lunge = 0.0
	_freeze = 0.0
	_held = false
	_strike = {}
	_age = -1.0


func _attach(m: LowPolyModel) -> void:
	model = m
	_tu = TUNING[hero.kit_id]
	pivot = Node3D.new()
	pivot.name = "Feel"
	var vis := m.get_parent()
	vis.add_child(pivot)
	m.reparent(pivot, false)


func _channels() -> Array[String]:
	var out: Array[String] = []
	for k: String in STRIKES:
		for ch: String in (STRIKES[k]["keys"] as Dictionary):
			if not out.has(ch) and model != null and model._arm_kick.has(ch):
				out.append(ch)
	return out


func _step_strike(delta: float) -> void:
	if _age < 0.0:
		return
	_age += delta
	var frame := _age / F
	var keys := _strike["keys"] as Dictionary
	var done := true
	for ch: String in keys:
		var k: Array = keys[ch]
		model._arm_kick[ch] = _sample(k, frame)
		if frame < float((k[k.size() - 1] as Array)[0]):
			done = false
	if not _impacted and frame >= float(_strike["impact"]) - 0.01:
		_impacted = true
		impact_frame = Engine.get_process_frames()
		_lunge = float(_tu["lunge"])
		_lean_v.x -= float(_tu["pitch"])
		_sq_v += float(_strike.get("squash", 0.0)) * float(_tu["squash"])
		if _connect:
			_freeze = float(_tu.get("hitstop", HITSTOP))
		var area := hero.melee_area()
		if bool(area.get("smash", false)):
			smashes += 1
			Fx.ground_smash(hero.global_position + _dir * float(area["far"]), float(area.get("end_radius", 0.5)))
			if hero.is_player and float(_tu["shake"]) > 0.0:
				Fx.shake(float(_tu["shake"]))   # (this screen's own hero only: a puppet's smash shakes no one)
	if done:
		for ch: String in keys:
			model._arm_kick[ch] = 0.0
		_strike = {}
		_age = -1.0


## The timeline `keys` ([[frame, value], ...]) at `frame`, easing out between keys.
static func _sample(keys: Array, frame: float) -> float:
	var prev: Array = keys[0]
	if frame <= float(prev[0]):
		return float(prev[1])
	for i in range(1, keys.size()):
		var cur: Array = keys[i]
		if frame <= float(cur[0]):
			var f := (frame - float(prev[0])) / maxf(float(cur[0]) - float(prev[0]), 0.001)
			f = 1.0 - (1.0 - f) * (1.0 - f)
			return lerpf(float(prev[1]), float(cur[1]), f)
		prev = cur
	return float(prev[1])


static func _spring(x: float, v: float, target: float, f: float, zeta: float, dt: float) -> Vector2:
	var w := TAU * f
	v += (w * w * (target - x) - 2.0 * zeta * w * v) * dt
	x += v * dt
	return Vector2(x, v)
