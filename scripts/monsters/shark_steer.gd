class_name SharkSteer
extends RefCounted
## A shark's steering inside its pool's real water polygon (docs/design/sharks.md, "Smooth movement"; the lab prototype
## is scripts/art/lowpoly/shark_swim.gd). Host-side AI working state of a Shark: pure geometry and a heading, no nodes.
##
##   - the water is the pool record's convex `outline` and, for a moat, its convex `hole` (the island); the centre line
##     keeps CLEAR off every rim (rim(): the distance field, positive in the water);
##   - the HEADING is steered, never the position: the yaw rate is capped by the turning radius at the current speed
##     (omega <= v / R_TURN, with OMEGA_FLOOR when nearly still) and the yaw acceleration by YAW_ACCEL, so every turn eases
##     in and out; the speed ramps (ACCEL / DECEL) and drops in a hard turn (TURN_SLOW);
##   - patrol pursues a carrot LOOKAHEAD ahead on a loop (a moat: the channel's middle line; a pool: the outline pulled in to
##     the middle of the water) and, in a pool, now and then turns round (hard over toward the side with more water);
##   - three feelers bend the wanted heading off a rim they find within CLEAR + 0.3, and a hard clamp holds the centre
##     line CLEAR off every rim after each move;
##   - the lunge goes straight along the heading; the head joint may go LUNGE_OVER past the rim, then it slides back down
##     its own trail (`back()`).
## Deterministic given its inputs: the caller passes the only roll (the reverse timer) from GameWorld.rng.

const CRUISE := 1.6
const HUNT := 2.8
const ACCEL := 1.6
const DECEL := 3.2
const R_TURN := 1.5
const OMEGA_FLOOR := 0.9          ## rad/s: it can still turn this fast when nearly still
const YAW_ACCEL := 3.2            ## rad/s^2
const TURN_SLOW := 0.35
const LOOKAHEAD := 2.2
const CLEAR := 0.42               ## half the body's 0.72 width plus a hair of liner
const FEEL_LEN := 1.3
const FEELERS: Array[float] = [-0.55, 0.0, 0.55]
const LUNGE_SPEED := 9.0
const LUNGE_LEN := 2.5
const LUNGE_OVER := 0.7           ## the head joint may go this far past the rim onto the deck
const TRAIL_STEP := 0.05
const TRAIL_KEEP := 120

var outline := PackedVector2Array()
var hole := PackedVector2Array()
var loop := PackedVector2Array()
var pos := Vector2.ZERO
var dir := Vector2.RIGHT
var speed := 0.0
var omega := 0.0
var loop_sign := 1.0
var trail := PackedVector2Array()   ## where pos has been (newest last): the lunge slides back down it
var lunged := 0.0                   ## how far the current lunge has gone


## Who may write each var (see Net): all of it is the host's AI working state (a client's shark keeps the geometry only,
## to know its water: SPAWN from the pool record).
func net_fields() -> Dictionary:
	return {
		"outline": Net.SPAWN, "hole": Net.SPAWN, "loop": Net.SPAWN,
		"pos": Net.PRIVATE, "dir": Net.PRIVATE, "speed": Net.PRIVATE, "omega": Net.PRIVATE, "loop_sign": Net.PRIVATE,
		"trail": Net.PRIVATE, "lunged": Net.PRIVATE,
	}


## `rec`: a HexMap.pools record. `start`, `heading`: X/Z.
func setup(rec: Dictionary, start: Vector2, heading: Vector2) -> void:
	outline = PackedVector2Array(rec["outline"])
	hole = PackedVector2Array(rec.get("hole", []))
	if hole.is_empty():
		loop = PoolGeo.offset(Array(outline), -minf(CLEAR + 0.75, inradius(outline) * 0.62))
	else:
		loop = PackedVector2Array()
		for i in hole.size():
			loop.append((outline[i] + hole[i]) * 0.5)
	pos = start
	dir = heading.normalized() if heading.length() > 0.001 else Vector2.RIGHT
	trail = PackedVector2Array([pos])


# --- the water -------------------------------------------------------------------------------------------------------

## Distance from p to the nearest rim: positive in the water, negative on the deck or the island.
func rim(p: Vector2) -> float:
	return rim_distance(p, outline, hole)


static func rim_distance(p: Vector2, ol: PackedVector2Array, hl: PackedVector2Array) -> float:
	var d := INF
	for i in ol.size():
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, ol[i], ol[(i + 1) % ol.size()])))
	if not Geometry2D.is_point_in_polygon(p, ol):
		d = -d
	if not hl.is_empty():
		var dh := INF
		for i in hl.size():
			dh = minf(dh, p.distance_to(Geometry2D.get_closest_point_to_segment(p, hl[i], hl[(i + 1) % hl.size()])))
		if Geometry2D.is_point_in_polygon(p, hl):
			dh = -dh
		d = minf(d, dh)
	return d


## The gradient of rim() at p: away from the nearest rim, into the water.
func rim_grad(p: Vector2) -> Vector2:
	var e := 0.05
	var g := Vector2(rim(p + Vector2(e, 0)) - rim(p - Vector2(e, 0)), rim(p + Vector2(0, e)) - rim(p - Vector2(0, e)))
	return g.normalized() if g.length() > 0.0001 else Vector2.ZERO


## The outward normal of the rim nearest p (the way a bite knocks its victim: out of the water, onto the deck).
func out_of_water(p: Vector2) -> Vector2:
	return -rim_grad(p)


## The biggest circle in a convex outline (a coarse grid search, then a refine): its radius.
static func inradius(ol: PackedVector2Array) -> float:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in ol:
		lo = lo.min(p)
		hi = hi.max(p)
	var best := -INF
	var at := (lo + hi) * 0.5
	var step := 0.25
	var y := lo.y
	while y <= hi.y:
		var x := lo.x
		while x <= hi.x:
			var d := rim_distance(Vector2(x, y), ol, PackedVector2Array())
			if d > best:
				best = d
				at = Vector2(x, y)
			x += step
		y += step
	for _i in 2:
		step *= 0.35
		var c := at
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var q := c + Vector2(dx, dy) * step
				var d := rim_distance(q, ol, PackedVector2Array())
				if d > best:
					best = d
					at = q
	return best


## A water point where the shark may sit: CLEAR + `margin` off every rim, nearest `p` (p itself when it already is).
func clamp_in(p: Vector2, margin: float = 0.0) -> Vector2:
	var q := p
	for _i in 8:
		var d := rim(q)
		if d >= CLEAR + margin:
			return q
		q += rim_grad(q) * (CLEAR + margin - d + 0.02)
	return q


# --- steering ---------------------------------------------------------------------------------------------------------

## Patrol one frame along the loop at CRUISE x `k` (coffee, a slow while aiming...).
func patrol(dt: float, k: float = 1.0) -> void:
	steer(carrot(LOOKAHEAD) - pos, CRUISE * k, dt)


## Turn round on the loop: hard over toward `side` (+1 left, -1 right). True when it now heads `goal`.
func turn_round(dt: float, side: float, goal: Vector2, k: float = 1.0) -> bool:
	steer(dir.rotated(side * 1.3), CRUISE * 0.85 * k, dt)
	return dir.dot(goal) > 0.8


## The side with more water (+1 left, -1 right): where a turn round goes.
func roomier_side() -> float:
	var perp := Vector2(-dir.y, dir.x)
	return 1.0 if rim(pos + perp * 1.5) > rim(pos - perp * 1.5) else -1.0


## Turn toward `want` (limited yaw rate and acceleration), ramp toward `v_want`, avoid the rims, move.
func steer(want: Vector2, v_want: float, dt: float, avoid: bool = true, omega_floor: float = OMEGA_FLOOR) -> void:
	if want.length() < 0.001:
		want = dir
	var wanted := want.normalized()
	if avoid:
		wanted = _avoid(wanted)
	var err := dir.angle_to(wanted)
	var omega_max := maxf(speed / R_TURN, omega_floor)
	omega = move_toward(omega, clampf(err * 2.6, -omega_max, omega_max), YAW_ACCEL * dt)
	dir = dir.rotated(omega * dt).normalized()
	var v := v_want * (1.0 - TURN_SLOW * clampf(absf(omega) / maxf(omega_max, 0.01), 0.0, 1.0))
	speed = move_toward(speed, v, (ACCEL if v > speed else DECEL) * dt)
	var next := pos + dir * speed * dt
	var d := rim(next)
	if d < CLEAR:
		next += rim_grad(next) * (CLEAR - d)
	pos = next
	_push_trail()


## Stand still and keep the heading (rooted, held, dazed): the speed drains away.
func hold(dt: float) -> void:
	speed = move_toward(speed, 0.0, DECEL * 2.0 * dt)
	omega = move_toward(omega, 0.0, YAW_ACCEL * 2.0 * dt)


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


## The point `ahead` along the patrol loop past the loop point nearest the shark, in the loop's current direction.
func carrot(ahead: float) -> Vector2:
	var n := loop.size()
	if n < 2:
		return pos + dir
	var best_i := 0
	var best_t := 0.0
	var best_d := INF
	for i in n:
		var a := loop[i]
		var ab := loop[(i + 1) % n] - a
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
		for _k in n + 1:
			var q := loop[(i + 1) % n]
			var seg := p.distance_to(q)
			if seg >= left:
				return p + (q - p).normalized() * left
			left -= seg
			p = q
			i = (i + 1) % n
		return p
	var q0 := loop[i]
	if p.distance_to(q0) >= left:
		return p + (q0 - p).normalized() * left if p.distance_to(q0) > 0.0001 else p
	left -= p.distance_to(q0)
	p = q0
	for _k in n + 1:
		i = (i - 1 + n) % n
		var q := loop[i]
		var seg := p.distance_to(q)
		if seg >= left:
			return p + (q - p).normalized() * left
		left -= seg
		p = q
	return p


# --- the lunge -----------------------------------------------------------------------------------------------------

func begin_lunge() -> void:
	lunged = 0.0
	omega = 0.0


## One frame of the lunge. True when it is over (its length, or the head LUNGE_OVER past the rim).
func lunge(dt: float) -> bool:
	speed = LUNGE_SPEED
	var step_len := speed * dt
	var next := pos + dir * step_len
	if lunged + step_len > LUNGE_LEN or -rim(next) > LUNGE_OVER:
		return true
	lunged += step_len
	pos = next
	_push_trail()
	return false


## Slide `dist` back down the trail (the recoil after a lunge). Keeps the heading.
func back(dist: float) -> void:
	var left := dist
	while left > 0.0 and trail.size() > 1:
		var last := trail[trail.size() - 1]
		var prev := trail[trail.size() - 2]
		var seg := last.distance_to(prev)
		if seg > left:
			pos = last + (prev - last).normalized() * left
			trail[trail.size() - 1] = pos
			return
		left -= seg
		trail.remove_at(trail.size() - 1)
		pos = prev
	speed = 0.0


func _push_trail() -> void:
	if trail.is_empty() or trail[trail.size() - 1].distance_to(pos) >= TRAIL_STEP:
		trail.append(pos)
		if trail.size() > TRAIL_KEEP:
			trail = trail.slice(trail.size() - TRAIL_KEEP)
