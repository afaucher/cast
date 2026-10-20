extends RefCounted
## The shark lab's swim prototype (docs/design/sharks.md, "Smooth movement"): continuous steering inside a pool's real
## water polygon (PoolGeo's outline and, for a moat, its island), not hex hops. Lab-only: the game has no shark yet.
## Everything here is what the host's Shark would run (the steering) plus what every screen would draw from the
## streamed position (the bending chain, the bank): see the doc's networking section.
##
## STEERING (host, per physics frame):
##   - a heading and a speed, never a teleport: the yaw RATE is limited by the turning radius at the current speed
##     (omega <= v / R_TURN, with a floor so it can still pivot slowly when nearly stopped) and the yaw ACCELERATION is
##     limited too (YAW_ACCEL), so every turn eases in and out; the speed ramps (ACCEL up, DECEL down) and drops in a
##     hard turn (TURN_SLOW);
##   - where it wants to go: PATROL pursues a carrot LOOKAHEAD ahead on a patrol loop (a moat: the channel's middle
##     line; a pool: its outline pulled in to the middle of the water), and in a convex pool it now and then turns
##     round and runs the loop the other way; HUNT swims to a point in the water facing its target;
##   - rim avoidance: three feelers ahead (FEELERS); one that comes within CLEAR of a rim bends the wanted heading
##     away along the distance field's gradient, and the centre line is held CLEAR off every rim (a hard clamp);
##   - the LUNGE (the regular shark's attack): HUNT to a spot APPROACH (2.8) short of the target, slow and turn to face it, the
##     wind-up (the fin dips, the bow wave swells: WINDUP), then 9 u/s along the heading for up to LUNGE_LEN; the head
##     may go up to LUNGE_OVER over the rim onto the deck (its belly lifted onto the coping) while the body stays in the
##     water, then it slides back down its own trail (RECOIL) and swims on.
## DRAWING (every screen, from the shown position): the head joint J0 is the steered point; the body joint J1 and the
## tail's end are the points BODY_LEN and BODY_LEN + TAIL_LEN back along the TRAIL J0 has swum, so the body bends
## through a turn and the dorsal fin (on the body) trails the head; each segment banks into the turn (BANK) and the
## head pitches up as it climbs the rim.

const SharkModels := preload("res://scripts/art/lowpoly/props/shark_models.gd")
const SharkMeasure := preload("res://scripts/art/lowpoly/shark_measure.gd")

const CRUISE := 1.6
const HUNT_SPEED := 2.8
const ACCEL := 1.6
const DECEL := 3.2
const R_TURN := 1.5           ## the turning radius at speed (the doc's table: tight 1.2, roomy 2.0)
const OMEGA_FLOOR := 0.9      ## rad/s: it can still turn this fast when nearly still
const YAW_ACCEL := 3.2        ## rad/s^2
const TURN_SLOW := 0.35       ## a turn at full omega slows it to 65 %
const LOOKAHEAD := 2.2
const CLEAR := 0.42           ## SharkMeasure.BODY_CLEAR
const FEELERS: Array[float] = [-0.55, 0.0, 0.55]
const FEEL_LEN := 1.3
const WINDUP := 0.6
const AIM_SPEED := 0.45         ## laser: it drifts this slowly while it turns its nose onto the target
const APPROACH := 2.8           ## lunge: it waits this far from the victim (centre to the head joint)
const LUNGE_SPEED := 9.0
const LUNGE_LEN := 2.5
const LUNGE_OVER := 0.7
const RECOIL := 0.45
const BANK := 0.16
const BANK_MAX := 0.42
const TRAIL_STEP := 0.04
const FLOAT := 0.06           ## its belly rides this far over the pool floor (more of its back out of the water)

var outline: PackedVector2Array
var hole: PackedVector2Array
var loop: PackedVector2Array
var floor_y := 0.0
var deck_y := 0.5

var pos := Vector2.ZERO
var dir := Vector2.RIGHT
var speed := 0.0
var omega := 0.0
var bank := 0.0
var trail := PackedVector2Array()
var mode := "patrol"            ## patrol | hunt | face | windup | lunge | recoil
var loop_sign := 1.0            ## +1 / -1: which way round the loop
var reverse_every := 0.0        ## convex pools: turn round on the loop every this many seconds (0 = never)
var target := Vector2.ZERO      ## hunt / lunge: the victim's spot on the deck
var telegraph := 0.0            ## 0..1 through the wind-up (the look: the fin dips, the bow wave)
var lift := 0.0                 ## how far the head is up on the rim (0..1)
var strikes := 0
var _t := 0.0
var _t_mode := 0.0
var _lunged := 0.0
var _back := 0.0                ## recoil: how far back down the trail J0 is drawn
var _since_reverse := 0.0
var _turn_side := 1.0
var _turn_goal := Vector2.LEFT


func setup(rec_outline: Array, rec_hole: Array, rec_floor_y: float, rec_deck_y: float, start: Vector2, heading: Vector2) -> void:
	outline = PackedVector2Array(rec_outline)
	hole = PackedVector2Array(rec_hole)
	floor_y = rec_floor_y + FLOAT
	deck_y = rec_deck_y
	if hole.is_empty():
		var ir: Array = SharkMeasure.inradius(outline, hole)
		loop = PoolGeo.offset(Array(outline), -minf(CLEAR + 0.75, float(ir[0]) * 0.62))
	else:
		loop = PackedVector2Array()
		for i in hole.size():
			loop.append((outline[i] + hole[i]) * 0.5)
	pos = start
	dir = heading.normalized()
	# a straight trail behind it, so the body is laid out from the first frame
	trail = PackedVector2Array()
	var n := int((SharkModels.BODY_LEN + SharkModels.TAIL_LEN + 0.5) / TRAIL_STEP)
	for i in n:
		trail.append(pos - dir * TRAIL_STEP * float(n - i))
	trail.append(pos)


func rim(p: Vector2) -> float:
	return SharkMeasure.rim_distance(p, outline, hole)


## The distance field's gradient at p (points away from the nearest rim, into the water).
func rim_grad(p: Vector2) -> Vector2:
	var e := 0.05
	var g := Vector2(rim(p + Vector2(e, 0)) - rim(p - Vector2(e, 0)), rim(p + Vector2(0, e)) - rim(p - Vector2(0, e)))
	return g.normalized() if g.length() > 0.0001 else Vector2.ZERO


## Order an attack on a spot on the deck (the lab's lunge; the game's would come from its senses).
func hunt(at: Vector2) -> void:
	target = at
	_set_mode("hunt")


## Laser: slow right down and keep the nose on `at` (the rider steers; a riderless laser shark aims this way too, its
## emitter lashed along the snout). Call it every frame with the target's spot; release() goes back to patrol.
func aim_at(at: Vector2) -> void:
	target = at
	if mode != "aim":
		_set_mode("aim")


func release() -> void:
	_set_mode("patrol")


func _set_mode(m: String) -> void:
	mode = m
	_t_mode = 0.0


func step(dt: float) -> void:
	_t += dt
	_t_mode += dt
	match mode:
		"patrol": _patrol(dt)
		"hunt": _hunt(dt)
		"face": _face(dt)
		"windup": _windup(dt)
		"lunge": _lunge(dt)
		"recoil": _recoil(dt)
		"aim": _steer(target - pos, AIM_SPEED, dt)
		"turn": _turn(dt)


# --- modes -----------------------------------------------------------------------------------------------------------

func _patrol(dt: float) -> void:
	_since_reverse += dt
	if reverse_every > 0.0 and _since_reverse >= reverse_every:
		_since_reverse = 0.0
		# turn round: hard over toward the side with more water, until it heads the other way round the loop
		var perp := Vector2(-dir.y, dir.x)
		_turn_side = 1.0 if rim(pos + perp * 1.5) > rim(pos - perp * 1.5) else -1.0
		_turn_goal = -dir
		_set_mode("turn")
		return
	var want := _carrot(LOOKAHEAD) - pos
	_steer(want, CRUISE, dt)


func _turn(dt: float) -> void:
	_steer(dir.rotated(_turn_side * 1.3), CRUISE * 0.85, dt)
	if dir.dot(_turn_goal) > 0.8 or _t_mode > 6.0:
		loop_sign = -loop_sign
		_set_mode("patrol")


func _hunt(dt: float) -> void:
	var spot := _approach_spot()
	var to := spot - pos
	if to.length() < 0.35:
		_set_mode("face")
		return
	# arrive: slow down inside the last 1.5
	_steer(to, lerpf(0.6, HUNT_SPEED, clampf(to.length() / 1.5, 0.0, 1.0)), dt)


func _face(dt: float) -> void:
	_steer(target - pos, 0.25, dt, false)
	if absf(dir.angle_to(target - pos)) < 0.12 or _t_mode > 1.2:
		_set_mode("windup")


func _windup(dt: float) -> void:
	telegraph = clampf(_t_mode / WINDUP, 0.0, 1.0)
	_steer(target - pos, 0.12, dt, false)
	if _t_mode >= WINDUP:
		telegraph = 0.0
		_lunged = 0.0
		_set_mode("lunge")


func _lunge(dt: float) -> void:
	speed = LUNGE_SPEED
	var step_len := speed * dt
	var next := pos + dir * step_len
	var over := -rim(next)
	if _lunged + step_len > LUNGE_LEN or over > LUNGE_OVER:
		strikes += 1
		_set_mode("recoil")
		_back = 0.0
		return
	_lunged += step_len
	pos = next
	_push_trail()
	lift = clampf((0.25 - rim(pos)) / (0.25 + LUNGE_OVER), 0.0, 1.0)


func _recoil(dt: float) -> void:
	# slide back down its own trail (sharks don't reverse: the water takes it back), then swim on
	var k := clampf(_t_mode / RECOIL, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	_back = _lunged * 0.85 * e
	var p := _trail_point(_back)
	lift = clampf((0.25 - rim(p)) / (0.25 + LUNGE_OVER), 0.0, 1.0)
	speed = 0.0
	if k >= 1.0:
		_cut_trail(_back)
		_back = 0.0
		pos = trail[trail.size() - 1]
		lift = 0.0
		omega = 0.0
		_set_mode("patrol")


## Where it waits to lunge: APPROACH short of the target, pulled CLEAR into the water.
func _approach_spot() -> Vector2:
	var d := target - pos
	var best := pos
	var best_score := INF
	# search a ring round the target for water spots LUNGE reach away, nearest to the shark
	for i in 24:
		var a := TAU * float(i) / 24.0
		var p := target + Vector2.from_angle(a) * APPROACH
		if rim(p) < CLEAR + 0.25:
			continue
		var score := p.distance_to(pos)
		if score < best_score:
			best_score = score
			best = p
	return best if best_score < INF else pos + d.normalized() * maxf(d.length() - APPROACH, 0.0)


# --- steering -----------------------------------------------------------------------------------------------------

## Turn toward `want` (limited yaw rate and yaw acceleration), ramp toward `v_want`, avoid the rims, move.
func _steer(want: Vector2, v_want: float, dt: float, avoid: bool = true) -> void:
	if want.length() < 0.001:
		want = dir
	var wanted := want.normalized()
	if avoid:
		wanted = _avoid(wanted)
	var err := dir.angle_to(wanted)
	var omega_max := maxf(speed / R_TURN, OMEGA_FLOOR)
	var omega_want := clampf(err * 2.6, -omega_max, omega_max)
	omega = move_toward(omega, omega_want, YAW_ACCEL * dt)
	dir = dir.rotated(omega * dt).normalized()
	var v := v_want * (1.0 - TURN_SLOW * clampf(absf(omega) / maxf(omega_max, 0.01), 0.0, 1.0))
	speed = move_toward(speed, v, (ACCEL if v > speed else DECEL) * dt)
	var next := pos + dir * speed * dt
	var d := rim(next)
	if d < CLEAR:
		next += rim_grad(next) * (CLEAR - d)
	pos = next
	_push_trail()
	lift = move_toward(lift, 0.0, dt * 3.0)
	var bank_want := clampf(omega * speed * BANK, -BANK_MAX, BANK_MAX)
	bank = lerpf(bank, bank_want, clampf(dt * 5.0, 0.0, 1.0))


## Bend the wanted heading away from a rim a feeler finds within CLEAR + 0.3.
func _avoid(wanted: Vector2) -> Vector2:
	var push := Vector2.ZERO
	var reach := FEEL_LEN + speed * 0.5
	for a in FEELERS:
		var q := pos + dir.rotated(a) * reach
		var d := rim(q)
		var margin := CLEAR + 0.3
		if d < margin:
			push += rim_grad(q) * (margin - d) * (1.6 if a == 0.0 else 1.0)
	if push.length() < 0.0001:
		return wanted
	return (wanted + push * 1.4).normalized()


## The point `ahead` along the patrol loop past the loop point nearest the shark (in the loop's current direction).
func _carrot(ahead: float) -> Vector2:
	var n := loop.size()
	var best_i := 0
	var best_t := 0.0
	var best_d := INF
	for i in n:
		var a := loop[i]
		var b := loop[(i + 1) % n]
		var ab := b - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := pos.distance_to(a + ab * t)
		if d < best_d:
			best_d = d
			best_i = i
			best_t = t
	var i := best_i
	var p := loop[i].lerp(loop[(i + 1) % n], best_t)
	var left := ahead
	if loop_sign > 0.0:
		while left > 0.0:
			var q := loop[(i + 1) % n]
			var seg := p.distance_to(q)
			if seg >= left:
				return p + (q - p).normalized() * left
			left -= seg
			p = q
			i = (i + 1) % n
	else:
		var q0 := loop[i]
		var seg0 := p.distance_to(q0)
		if seg0 >= left:
			return p + (q0 - p).normalized() * left if seg0 > 0.0001 else p
		left -= seg0
		p = q0
		while left > 0.0:
			i = (i - 1 + n) % n
			var q := loop[i]
			var seg := p.distance_to(q)
			if seg >= left:
				return p + (q - p).normalized() * left
			left -= seg
			p = q
	return p


# --- the trail and the bending body -------------------------------------------------------------------------------

func _push_trail() -> void:
	if trail.is_empty() or trail[trail.size() - 1].distance_to(pos) >= TRAIL_STEP:
		trail.append(pos)
		if trail.size() > 400:
			trail = trail.slice(trail.size() - 300)


## The point `back` units back along the trail from its newest end (straight on past its oldest point).
func _trail_point(back: float) -> Vector2:
	var left := back
	var i := trail.size() - 1
	var p := pos if mode != "recoil" else trail[i]
	if mode != "recoil":
		var d0 := p.distance_to(trail[i])
		if d0 >= left:
			return p + (trail[i] - p).normalized() * left if d0 > 0.0001 else p
		left -= d0
		p = trail[i]
	while i > 0:
		var q := trail[i - 1]
		var seg := p.distance_to(q)
		if seg >= left:
			return p + (q - p).normalized() * left if seg > 0.0001 else p
		left -= seg
		p = q
		i -= 1
	var tail_dir := (trail[0] - trail[mini(1, trail.size() - 1)]).normalized() if trail.size() > 1 else -dir
	return p + tail_dir * left


func _cut_trail(back: float) -> void:
	var keep := PackedVector2Array()
	var total := 0.0
	var i := trail.size() - 1
	while i > 0 and total < back:
		total += trail[i].distance_to(trail[i - 1])
		i -= 1
	keep = trail.slice(0, i + 1)
	trail = keep


## The three segments' transforms (world space) for SharkModels.pose: [head, body, tail].
func segment_transforms() -> Array[Transform3D]:
	var j0 := _trail_point(_back)
	var j1 := _trail_point(_back + SharkModels.BODY_LEN)
	var j2 := _trail_point(_back + SharkModels.BODY_LEN + SharkModels.TAIL_LEN)
	var head_dir := dir if _back <= 0.0001 else (j0 - j1).normalized()
	var dip := 0.12 * telegraph
	var y0 := floor_y + lift * (deck_y - floor_y + 0.02) - dip
	var y1 := floor_y + lift * 0.18 - dip * 0.6
	var y2 := floor_y
	var p0 := Vector3(j0.x, y0, j0.y)
	var p1 := Vector3(j1.x, y1, j1.y)
	var p2 := Vector3(j2.x, y2, j2.y)
	var head_fwd := Vector3(head_dir.x, -0.18 * lift - 0.25 * telegraph * 0.4, head_dir.y).normalized()
	var body_fwd := (p0 - p1).normalized()
	var tail_fwd := (p1 - p2).normalized()
	return [_xf(p0, head_fwd, bank * 0.6), _xf(p0, body_fwd, bank), _xf(p1, tail_fwd, bank * 0.7)]


static func _xf(at: Vector3, fwd: Vector3, roll: float) -> Transform3D:
	var b := Basis.looking_at(-fwd, Vector3.UP)
	b = Basis(fwd.normalized(), -roll) * b
	return Transform3D(b, at)


## Where the dorsal fin is (for the ripple and the wake): on the body, 0.42 behind J0.
func fin_point() -> Vector2:
	return _trail_point(_back + 0.42)


## A point `d` behind J0 along the body's path (the wake follows it).
func behind(d: float) -> Vector2:
	return _trail_point(_back + d)
