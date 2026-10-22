class_name HeroMotion
extends RefCounted
## A hero's walking under a MoveFeel profile with an envelope (package A, "grounded": docs/design/movement-research.md
## §4 and "As built"). Runs only on the machine that moves the hero (its player's; the host for the AI seats): the owner's
## motion, streamed like any walk, so nothing here travels. With the `today` profile none of it runs and Hero.move is the
## old walk, frame for frame.
##
##   ENVELOPE  The walk has a velocity. A fresh press jumps to `boost` of full speed on its first frame (the first frame
##             always moves), then ramps to full over `start`; letting go slides to rest over `stop` (0.16 u at 4.5); a
##             turn of more than 60 degrees (a reversal) runs at the `reversal` rate, through zero. Top speed is unchanged.
##             Every step still goes through Actor.move, so walls slide, ledges stop and lava and pits refuse the step
##             exactly as before: a stop slide can never carry a hero off an edge.
##   HOP       A +1 step is a hop arc (`hop_time`, peak `hop_peak` above the step), started a little before the edge so the
##             feet clear the face. Stairs are walked as before (the ramp).
##   MANTLE    A +2 climb: the hero is held at the lip for `mantle_hold` (per kit), then rises onto the ledge over
##             `mantle_rise`. Letting go or turning away during the hold cancels it. `climbing` is set for both (it is
##             streamed: the other screens know). A hero that can't climb (Rebar) finds the ledge a wall, as before.
##   GRAVITY   A walked-off drop falls under `gravity` with the walk carrying on; a landing of MoveFeel.LAND_BIG_LEVELS or
##             more keeps `land_slow` of the speed (it ramps back on the envelope).
##
## Casting is never touched (no root, no slow while speaking). A shove, a daze or a root resets the walk (the shove's own
## slide runs as before).

const MANTLE_SCAN_MIN := 0.3      ## how far past the lip the landing spot is looked for (units)
const MANTLE_SCAN_MAX := 1.4
const HOP_LEAD := 0.04            ## the hop starts this many seconds of walking (plus half a radius) before the step's edge
const DROP_START := 0.15          ## ground this far below the feet is a fall, not a settle
const TELEPORT := 1.5             ## a jump this big between frames is a teleport: the vertical state starts over

var hero: Hero
var vel := Vector3.ZERO           ## the walking velocity (X/Z), units/s
var moved_frame := -1             ## the physics frame of the last move() call (Hero coasts on the frames without one)
var input_live := false           ## the last move had an input (a new press after none is a fresh start: the boost)
var ramping := false              ## a fresh start, still ramping up from the boost
# vertical
var air := false                  ## falling off a drop
var vy := 0.0
var fall_top := 0.0
var hop_t := -1.0                 ## seconds into the hop, -1 when not hopping
var hop_from := 0.0
var hop_a := 0.0                  ## y = hop_from + hop_a u + hop_b u^2 (u = hop_t / hop_time)
var hop_b := 0.0
var hop_to := 0.0
var last_pos := Vector3.INF
# mantle
var mantle := 0                   ## 0 none, 1 held at the lip, 2 rising
var mantle_t := 0.0
var mantle_dir := Vector3.ZERO
var mantle_from := Vector3.ZERO
var mantle_to := Vector3.ZERO
var mantle_hold := 0.0
var landings := 0                 ## walked-off drops landed (tests)
var hops := 0                     ## hops started (tests)
var mantles := 0                  ## mantles finished (tests)


func _init(h: Hero = null) -> void:
	hero = h


## Who may write each var (see Net): the owner's working state; the result streams as the hero's position.
func net_fields() -> Dictionary:
	return {
		"hero": Net.LOCAL,
		"vel": Net.PRIVATE, "moved_frame": Net.PRIVATE, "input_live": Net.PRIVATE, "ramping": Net.PRIVATE,
		"air": Net.PRIVATE, "vy": Net.PRIVATE, "fall_top": Net.PRIVATE, "hop_t": Net.PRIVATE, "hop_from": Net.PRIVATE,
		"hop_a": Net.PRIVATE, "hop_b": Net.PRIVATE, "hop_to": Net.PRIVATE, "last_pos": Net.PRIVATE,
		"mantle": Net.PRIVATE, "mantle_t": Net.PRIVATE, "mantle_dir": Net.PRIVATE, "mantle_from": Net.PRIVATE,
		"mantle_to": Net.PRIVATE, "mantle_hold": Net.PRIVATE,
		"landings": Net.PRIVATE, "hops": Net.PRIVATE, "mantles": Net.PRIVATE,
	}


## Everything back to standing still (a profile switch, a shove, death).
func reset() -> void:
	vel = Vector3.ZERO
	input_live = false
	ramping = false
	air = false
	vy = 0.0
	hop_t = -1.0
	if mantle != 0:
		mantle = 0
		hero.climbing = false
	last_pos = Vector3.INF


## Hero.move under the envelope: `dir` is the wish (X/Z, length <= 1). Returns true if the hero moved.
func walk(dir: Vector3, delta: float) -> bool:
	moved_frame = Engine.get_physics_frames()
	dir.y = 0.0
	if hero.is_shoved() or hero.dead or hero.is_dazed():
		reset()
		return hero._walk(dir, delta)   # (refuses, as it always did)
	if mantle != 0:
		return _tick_mantle(dir, delta)
	if hero.is_rooted():
		vel = Vector3.ZERO
		input_live = dir.length() > 0.001
		return hero._walk(dir, delta)   # (vines: turns, never walks)
	var wish := dir.limit_length(1.0)
	if wish.length() > 0.1 and _ledge_ahead(wish):
		return false
	return _step(wish, delta)


## A physics frame without a move() call: the stop slide carries on, and a held mantle lets go.
func coast(delta: float) -> void:
	if mantle == 1:
		mantle = 0
		hero.climbing = false
	elif mantle == 2:
		_tick_mantle(Vector3.ZERO, delta)
		return
	if hero.is_shoved() or hero.dead or hero.is_dazed() or hero.is_rooted():
		vel = Vector3.ZERO
		input_live = false
		return
	if vel.length() > 0.0005 or input_live:
		var f := hero.facing
		_step(Vector3.ZERO, delta)
		hero.facing = f   # (the stop slide carries the body on but does not turn it: whoever steered last chose the facing,
		# e.g. an AI archer that stopped backing off to face and shoot; turning it to the slide flipped it 180 for a frame)


## The envelope, then the walk at the new velocity.
func _step(wish: Vector3, delta: float) -> bool:
	var s := hero.walk_speed()
	var target := wish * s
	var fresh := not input_live   # (a new press; a stop by a shove, a root or a mantle ramps back at the turn rate)
	input_live = wish.length() > 0.001
	envelope(target, s, fresh, delta)
	if vel.length() < 0.0005 or s <= 0.0:
		hero.climbing = false
		return false
	return hero._walk(vel / s, delta, hero.pace)


## Move `vel` toward `target` (X/Z, units/s) for one frame. `s` is the full walking speed now; `fresh` is a new press.
func envelope(target: Vector3, s: float, fresh: bool, delta: float) -> void:
	var boost := MoveFeel.num("boost")
	var full := maxf(s, 0.1)
	if target.length() < 0.001:
		vel = vel.move_toward(Vector3.ZERO, full / maxf(MoveFeel.num("stop"), 0.001) * delta)
		return
	var w := target.normalized()
	if fresh and vel.dot(w) >= 0.0 and vel.length() < boost * target.length():
		vel = w * boost * target.length()   # the first frame moves, at the boost
		ramping = true
		return
	# A fresh start ramps from the boost over `start`; any other change of velocity (a turn, a reversal through zero, a speed
	# change while walking) runs at the reversal rate: full speed one way to full speed the other in `reversal`.
	if ramping and vel.normalized().dot(w) < 0.5:
		ramping = false
	var rate := (1.0 - boost) * full / maxf(MoveFeel.num("start"), 0.001) if ramping \
			else 2.0 * full / maxf(MoveFeel.num("reversal"), 0.001)
	vel = vel.move_toward(target, rate * delta)
	if ramping and vel.is_equal_approx(target):
		ramping = false


# --- Vertical: hop, fall, land -----------------------------------------------------------------------------------------

## Every physics frame, after the walk: the feet and the ground. (Actor.snap_to_ground's eased settle is off meanwhile.)
func vertical(delta: float) -> void:
	var map: HexMap = GameWorld.map
	if map == null or hero.is_shoved() or hero.dead or mantle != 0:
		air = false
		hop_t = -1.0
		last_pos = hero.global_position
		return
	var p := hero.global_position
	if last_pos != Vector3.INF and p.distance_to(last_pos) > TELEPORT:
		air = false
		hop_t = -1.0
	var g := map.ground_height(p)
	if is_nan(g):
		last_pos = p
		return
	var y := p.y
	if hop_t >= 0.0:
		hop_t += delta
		var u := hop_t / maxf(MoveFeel.num("hop_time"), 0.001)
		if u >= 1.0:
			hop_t = -1.0
			y = hop_to
		else:
			y = hop_from + hop_a * u + hop_b * u * u
		if y < g:
			y = g
			hop_t = -1.0
		if hop_t < 0.0 and y > g + DROP_START:
			_start_fall(y)   # (stopped short of the step: back down)
	elif air:
		vy -= MoveFeel.num("gravity") * delta
		y += vy * delta
		if y <= g:
			y = g
			_land(g)
	else:
		var dy := g - y
		var on_stairs := _stairs(map, p)
		if not on_stairs and MoveFeel.on("hop") and _hop_ahead(map, p, y):
			last_pos = p
			return
		if on_stairs:
			y = g
		elif dy < -DROP_START and MoveFeel.num("gravity") > 0.0:
			_start_fall(y)
			vy -= MoveFeel.num("gravity") * delta
			y = maxf(g, y + vy * delta)
		elif dy > 0.2 and MoveFeel.on("hop"):
			_start_hop(y, g)   # (already under the step: hop from here)
			y = hop_from
		else:
			y = lerpf(y, g, clampf(14.0 * delta, 0.0, 1.0))   # (small settles: Actor.snap_to_ground's ease)
			if absf(y - g) < 0.01:
				y = g
	hero.global_position.y = y
	last_pos = hero.global_position


func _start_fall(y: float) -> void:
	air = true
	vy = 0.0
	fall_top = y


func _land(g: float) -> void:
	air = false
	vy = 0.0
	landings += 1
	if (fall_top - g) / Hex.LEVEL_HEIGHT >= MoveFeel.LAND_BIG_LEVELS - 0.1:
		vel *= MoveFeel.num("land_slow")   # the landing recovery: the envelope ramps it back over `start`
		ramping = true


## A step up ahead of the walk: start the hop now so it lands as the feet cross the edge.
func _hop_ahead(map: HexMap, p: Vector3, y: float) -> bool:
	if vel.length() < 0.5:
		return false
	var ahead := p + vel.normalized() * (hero.radius * 0.5 + vel.length() * HOP_LEAD)
	if _stairs(map, ahead) or map.movement_check(p, ahead) != HexMap.Move.OK:
		return false
	var g2 := map.ground_height(ahead)
	if is_nan(g2):
		return false
	var rise := (g2 - y) / Hex.LEVEL_HEIGHT
	if rise < 0.4 or rise > HexMap.STEP_LEVELS:
		return false
	_start_hop(y, g2)
	return true


## The arc from `from` to the step's top `to`, peaking hop_peak above it: y(u) = from + a u + b u^2.
func _start_hop(from: float, to: float) -> void:
	var d := to - from
	var h := MoveFeel.num("hop_peak")
	hop_a = 2.0 * (d + h) + 2.0 * sqrt((d + h) * h)
	hop_b = d - hop_a
	hop_from = from
	hop_to = to
	hop_t = 0.0
	hops += 1


static func _stairs(map: HexMap, p: Vector3) -> bool:
	var c := map.get_cell(Hex.from_world(p))
	return c != null and c.type == HexMap.Tile.STAIRS


# --- Mantle: the +2 climb ------------------------------------------------------------------------------------------------

## Walking into a +2 ledge this hero can climb: start the mantle (true: this frame's walk is the mantle's).
func _ledge_ahead(wish: Vector3) -> bool:
	if not MoveFeel.on("mantle") or not hero.can_climb or air or hop_t >= 0.0:
		return false
	var map: HexMap = GameWorld.map
	if map == null:
		return false
	var p := hero.global_position
	var w := wish.normalized()
	var probe := p + w * (hero.radius * 0.5 + maxf(vel.length(), 1.0) * 0.05)
	if map.movement_check(p, probe) != HexMap.Move.CLIMB or map.wall_at(probe):
		return false
	var top := map.ground_height(probe)
	var d := MANTLE_SCAN_MIN
	while d <= MANTLE_SCAN_MAX:
		var q := p + w * d
		var gq := map.ground_height(q)
		if not is_nan(gq) and absf(gq - top) < 0.05 and not map.blocks_point(q, hero.radius) \
				and map.movement_check(probe, q) == HexMap.Move.OK:
			mantle = 1
			mantle_t = 0.0
			mantle_dir = w
			mantle_from = p
			mantle_to = Vector3(q.x, gq, q.z) + w * 0.05
			var kits := MoveFeel.value("mantle_hold_kits") as Dictionary
			mantle_hold = float(kits.get(hero.kit_id, MoveFeel.num("mantle_hold")))
			vel = Vector3.ZERO
			hero.climbing = true
			return true
		d += 0.05
	return false


func _tick_mantle(dir: Vector3, delta: float) -> bool:
	mantle_t += delta
	if mantle == 1:
		var w := dir
		w.y = 0.0
		if w.length() < 0.1 or w.normalized().dot(mantle_dir) < 0.3:
			mantle = 0   # let go or turned away: no climb
			hero.climbing = false
			return false
		if mantle_t >= mantle_hold:
			mantle = 2
			mantle_t = 0.0
		return false
	var rise := maxf(MoveFeel.num("mantle_rise"), 0.001)
	var u := clampf(mantle_t / rise, 0.0, 1.0)
	var k := 1.0 - (1.0 - u) * (1.0 - u)   # ease out: up fast, settle onto the lip
	var p := mantle_from.lerp(mantle_to, smoothstep(0.0, 1.0, u))
	p.y = lerpf(mantle_from.y, mantle_to.y, k)
	hero.global_position = p
	if u >= 1.0:
		mantle = 0
		mantles += 1
		hero.climbing = false
		hero.global_position = mantle_to
		vel = mantle_dir * hero.walk_speed() * MoveFeel.num("boost")
		input_live = true
		ramping = true
		last_pos = hero.global_position
	return true
