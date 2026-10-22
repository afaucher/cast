class_name Pavise
extends Monster
## The Pavise Crossbowman (docs/design/combat-proposals.md §2, "As built"; the look: docs/design/pavise-read-test.md): a
## skeleton behind a door-sized shield that blocks from the FRONT, carried or planted (user, 2026-10-20), and a heavy
## crossbow that outranges the crew. "Who goes round?"
##
## BEHAVIOUR (host; §2.3). It chases like any monster (awareness: monster.gd) and fights in phases:
##   ADVANCE   shield carried (it still blocks), walks toward its mark until it has a shot within ADVANCE_MAX
##   PLANT     PLANT_TIME: stamps the pavise in, facing the mark
##   AIM       AIM_TIME: TRACKS its victim for TRACK_TIME (a dashed red floor line on every screen), then LOCKS the line
##             (solid and bright) for the rest; then LOOSE: a bolt (BOLT_DAMAGE + a BOLT_SHOVE push) along the locked line
##             at BOLT_SPEED, stopping at the first hero, prop or breakable it meets
##   RELOAD    RELOAD_TIME (RELOAD_SOAKED while Damp has it): cranks the bow, still shielded; then AIM again
##   TURN      planted it drags the pavise round at TURN_PLANTED toward the nearest hero within NEAR_TURN, else its mark;
##             past REPLANT_DEG it lifts and re-plants (PLANT_TIME, turning at TURN_CARRIED meanwhile). No shot for
##             LOS_GRACE: it lifts and advances again
##   BASH      a hero within BASH_REACH in the front arc: BASH_WINDUP (the monsters' orange pulse), BASH_DAMAGE + BASH_SHOVE
##   EXPOSED   a shove that gets through while planted leaves the pavise standing where it was (shield LEFT): no block
##             until it walks back and lifts it (LIFT_TIME). Shoved from behind into its own shield it TRIPS: both go flat
##             (shield FLAT, FLAT_TIME), then it lifts it
## Who it shoots (its mark): the hero in line of sight with no monster within BACKLINE of them (the backline), else the
## nearest it can shoot, else whoever it chases; a chicken that pecked it has it (it turns its shield to the chicken).
## Vines bind the shield's foot: rooted, it cannot turn (§2.5's exception). Coffee: turns, aims and reloads faster.
##
## THE SHIELD (§2.4, Combat.shielded): hits from inside the front arc (±SHIELD_HALF_ARC of `facing`) do nothing while the
## shield is CARRIED or PLANTED: melee by the attacker's spot, shots and arrows by where they came from, blasts and blast
## shoves when the centre is ahead of the shield plane (SHIELD_PLANE) and in the arc; corn comes from above and teeth from
## inside, so never. A blocked hit shows a spark and a grey "0"; an arrow or a bolt sticks in the planks (`stuck`).
##
## ONLINE (§2.7): a host-owned actor. The bolt is a scheduled effect on the shark's laser channel: world.charge (start,
## length, victim: the dashed line tracks the victim as each screen shows it), world.uncharge (dropped, also after the
## lock: a shove cancels the shot), world.lock (origin, direction, the shared loose time); every machine looses the bolt
## then and the victim decides (Projectile). The shield's state is world.shield {id, st, x, y, z, w} (NetWorld; a late
## joiner gets each pavise's in the snapshot). The block is decided by the machine that resolves the hit, with the
## shield's facing as it shows it (the host's stream on a client).

signal charge_begun(length: float)
signal charge_dropped
signal beam_locked(origin: Vector3, dir: Vector3, fire_at: float)
## The shield's state changed (NetWorld sends world.shield): state, where a LEFT / FLAT pavise lies, its yaw.
signal shield_changed(state: int, pos: Vector3, yaw: float)

enum Shield { CARRIED, PLANTED, LEFT, FLAT }
enum Phase { ADVANCE, PLANT, AIM, RELOAD, EXPOSED, LIFT, FLAT }

const HP := 70.0
const SPEED := 2.2                 ## carrying the shield
const AGGRO := 10.0                ## all round 10, the front cone 16 (aggro + Monster.CONE_EXTRA)
const LEASH := 24.0
const TURN_CARRIED := 150.0        ## degrees a second
const TURN_PLANTED := 60.0
const BOLT_DAMAGE := 18.0
const BOLT_SHOVE := 0.8
const BOLT_RANGE := 20.0
const BOLT_SPEED := 30.0
const BOLT_HEIGHT := 1.25          ## the bolt flies this high over the feet (a +2 ledge, 1.0, does not stop it)
const AIM_TIME := 1.2
const SHOW_AIM_LINE := false       ## the red aim line on the floor (removed by the user, 2026-10-22; _update_line)
const TRACK_TIME := 0.8           ## of AIM_TIME: the line tracks, then locks for the rest
const AIM_START_DEG := 15.0        ## the mark within this of its facing before it starts aiming
const LOCK_MAX_DEG := 20.0         ## the locked line stays within this of the shield's facing (it shoots through the notch)
const RELOAD_TIME := 2.0
const RELOAD_SOAKED := 3.0         ## a wet string (Damp)
const PLANT_TIME := 0.6
const LIFT_TIME := 1.0
const FLAT_TIME := 1.5
const ADVANCE_MAX := 14.0          ## plants with a shot this close (the doc's 10-14 spot)
const LOS_GRACE := 1.5
const REPLANT_DEG := 90.0
const NEAR_TURN := 4.0
const BACKLINE := 3.0
const BASH_DAMAGE := 8.0
const BASH_SHOVE := 2.0
const BASH_REACH := 1.8
const BASH_WINDUP := 0.5
const BASH_COOLDOWN := 1.6
const SHIELD_HALF_ARC := 70.0      ## the front 140 degrees
const SHIELD_PLANE := 0.55         ## a blast centre must be this far ahead of the body to be in front of the planks
const SHIELD_AHEAD := 0.6          ## the planted pavise's foot stands this far ahead of the body (world units)
const TRIP_DOT := 0.5              ## a shove this much along its facing pushes it into its own shield: a trip
const FETCH_DIST := 0.9
const MAX_STUCK := 9
const BOLT_COLOR := Color(1.0, 0.72, 0.22)
const MARK_EVERY := 1.0

# --- Replicated (OWNER) ---------------------------------------------------------------------------------------
var shield_state: int = Shield.CARRIED
var shield_pos := Vector3.ZERO     ## LEFT / FLAT: where the pavise stands or lies (its foot)
var shield_yaw := 0.0              ## ... and its yaw (the visual's: atan2(-f.x, -f.z))
var charge_victim: Actor = null    ## world.charge: whom the dashed line tracks
var lock_origin := Vector3.ZERO    ## world.lock: where the bolt starts ...
var lock_dir := Vector3.ZERO       ## ... which way it flies ...
var fire_at := -1.0                ## ... and when (GameWorld.time on this machine; -1 = none pending)

# --- Host AI (PRIVATE) ------------------------------------------------------------------------------------------
var _phase: int = Phase.ADVANCE
var _phase_until := 0.0
var _loaded := true
var _mark: Actor = null
var _mark_t := 0.0
var _no_shot_t := 0.0
var _charge_t0 := 0.0
var _charge_len := AIM_TIME
var _turn_frame := -1
var _turn_left := 0.0
var _look_goal := Vector3.ZERO

# --- This screen (LOCAL) --------------------------------------------------------------------------------------
var stuck := 0                     ## arrows stuck in its front, as this screen saw them
var blocks_shown := 0              ## blocks this screen showed (tests)
var blocks_decided := 0            ## ... of them, the ones this machine resolved (it applied nothing)
var bolts_fired := 0               ## bolts this screen loosed (tests)
var last_bolt: Projectile = null
var _fx: PaviseFx = null
var _aim_look := 0.0
var _shown_shield := -1
var _lock_len := BOLT_RANGE


func _init() -> void:
	super._init()
	kind = "pavise"
	display_name = "Pavise Crossbowman"
	max_hp = HP
	move_speed = SPEED
	radius = 0.45
	can_climb = false              # (a door-sized shield: a +2 ledge stops it; melee must reach it)
	aggro_range = AGGRO
	leash_range = LEASH
	attack_damage = BASH_DAMAGE
	attack_reach = BASH_REACH
	attack_arc_deg = SHIELD_HALF_ARC * 2.0
	attack_windup = BASH_WINDUP
	attack_cooldown = BASH_COOLDOWN
	attack_start_range = BASH_REACH
	stop_distance = BASH_REACH
	employee_chance = 0.0
	bar_height = 2.4
	bar_width = 1.0


func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"shield_state": Net.OWNER, "shield_pos": Net.OWNER, "shield_yaw": Net.OWNER,
		"charge_victim": Net.OWNER, "lock_origin": Net.OWNER, "lock_dir": Net.OWNER, "fire_at": Net.OWNER,
		"_phase": Net.PRIVATE, "_phase_until": Net.PRIVATE, "_loaded": Net.PRIVATE, "_mark": Net.PRIVATE, "_mark_t": Net.PRIVATE,
		"_no_shot_t": Net.PRIVATE, "_charge_t0": Net.PRIVATE, "_charge_len": Net.PRIVATE, "_turn_frame": Net.PRIVATE,
		"_turn_left": Net.PRIVATE, "_look_goal": Net.PRIVATE,
		"stuck": Net.LOCAL, "blocks_shown": Net.LOCAL, "blocks_decided": Net.LOCAL, "bolts_fired": Net.LOCAL,
		"last_bolt": Net.LOCAL, "_fx": Net.LOCAL, "_aim_look": Net.LOCAL, "_shown_shield": Net.LOCAL, "_lock_len": Net.LOCAL,
	})
	return f


func _ready() -> void:
	super._ready()
	_fx = PaviseFx.new()
	_fx.name = "AimFx"
	add_child(_fx)


## The primitive fallback body (Monster.use_proto_visuals): a bone figure behind a crimson-fronted door, a glowing bolt.
func _build_visual(root: Node3D) -> void:
	var bone := _mat(Color(0.9, 0.85, 0.72))
	var wood := _mat(Color(0.7, 0.54, 0.34))
	var paint := _mat(Color(0.82, 0.1, 0.1))
	var tip := _mat(Color(1.0, 0.72, 0.22), 3.0)
	_cyl(root, 0.14, 0.2, 0.9, Vector3(0.0, 0.75, 0.1), bone)
	_sphere(root, 0.17, Vector3(0.0, 1.35, 0.1), bone)
	_box(root, Vector3(1.24, 1.87, 0.1), Vector3(0.0, 0.94, -0.6), wood)
	_box(root, Vector3(1.18, 1.8, 0.02), Vector3(0.0, 0.94, -0.66), paint)
	_box(root, Vector3(0.08, 0.08, 0.7), Vector3(0.2, 1.95, -0.3), wood)
	_sphere(root, 0.08, Vector3(0.2, 1.95, -0.7), tip)


# --- The shield ------------------------------------------------------------------------------------------------

## Combat.shielded asks: does the shield stop a hit of `kind` coming from `from_point`? (See the header.)
func blocks_hit(from_point: Vector3, hit_kind: String) -> bool:
	if dead or not shield_up():
		return false
	var f := Vector3(facing.x, 0.0, facing.z)
	if f.length() < 0.001:
		return false
	f = f.normalized()
	var to := from_point - global_position
	to.y = 0.0
	var l := to.length()
	if l < 0.05:
		return false
	if hit_kind == Combat.HIT_BLAST and to.dot(f) < SHIELD_PLANE:
		return false   # (the blast is level with or behind the planks)
	return rad_to_deg(f.angle_to(to / l)) <= SHIELD_HALF_ARC


## The shield is in its hands (carried or planted): it blocks from the front.
func shield_up() -> bool:
	return shield_state == Shield.CARRIED or shield_state == Shield.PLANTED


## Combat.shielded: a hit stopped on the planks, on this screen (`decided`: this machine resolved it, so nothing applied).
func show_block(_from_point: Vector3, hit_kind: String, decided: bool, source: Node) -> void:
	Sfx.play_at("hit_shield", global_position)
	blocks_shown += 1
	if decided:
		blocks_decided += 1
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	var high := 1.15 if hit_kind == Combat.HIT_ARROW or hit_kind == Combat.HIT_SHOT else 0.9
	PaviseFx.block(global_position + f * (SHIELD_AHEAD + 0.12) + Vector3.UP * high, f)
	if hit_kind == Combat.HIT_ARROW:
		stuck += 1
		var pm := model as PaviseModel
		if pm != null:
			pm.set_stuck(mini(stuck, MAX_STUCK))
	if not Net.owns(self):
		return
	if decided:
		CombatLog.block(self, hit_kind, source)
	# A clank still says "a hero is there": it wakes up and fights (no shout: nothing was hurt).
	var a := source as Actor
	if a != null and is_instance_valid(a) and not a.dead and a.team == GameWorld.TEAM_HEROES and is_passive():
		if state == State.RETURN:
			home = global_position
		aggro(a)


func _set_shield(st: int, pos: Vector3 = Vector3.ZERO, yaw: float = 0.0) -> void:
	if st == shield_state and (st == Shield.CARRIED or st == Shield.PLANTED):
		return
	shield_state = st
	shield_pos = pos
	shield_yaw = yaw
	shield_changed.emit(st, pos, yaw)


## Where the planted pavise's foot stands now, and its yaw.
func _shield_spot() -> Array:
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	var p := global_position + f * SHIELD_AHEAD
	var map := GameWorld.map
	if map != null:
		var g := map.ground_height(p)
		if not is_nan(g):
			p.y = g
	return [p, atan2(-f.x, -f.z)]


# --- Turning (TURN_CARRIED / TURN_PLANTED; rooted: none) ----------------------------------------------------------------

func _turn_rate() -> float:
	if is_rooted():
		return 0.0   # (§2.5: the vines bind the shield's foot)
	if not shield_up():
		return 720.0
	return (TURN_PLANTED if shield_state == Shield.PLANTED else TURN_CARRIED) * attack_rate_mult()


## `want` (flat, unit) reached from the current facing at most this frame's turn budget (shared by every turn this frame).
func _turned(want: Vector3) -> Vector3:
	var fr := Engine.get_physics_frames()
	if fr != _turn_frame:
		_turn_frame = fr
		_turn_left = deg_to_rad(_turn_rate()) * get_physics_process_delta_time()
	var cur := Vector3(facing.x, 0.0, facing.z)
	if cur.length() < 0.001:
		return want
	cur = cur.normalized()
	var ang := cur.signed_angle_to(want, Vector3.UP)
	var step := clampf(ang, -_turn_left, _turn_left)
	_turn_left -= absf(step)
	return cur.rotated(Vector3.UP, step).normalized()


func face_point(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.001:
		facing = _turned(d.normalized())


func move(dir: Vector3, delta: float) -> bool:
	var before := facing
	var moved := super.move(dir, delta)
	var want := facing
	facing = before
	if want.length() > 0.001:
		facing = _turned(Vector3(want.x, 0.0, want.z).normalized())
	return moved


## A look-around turns it at its turn rate too (the shield lags behind; monster-awareness.md's look-arounds).
func look_around(spread: float = LOOK_SPREAD_DEG) -> void:
	var before := facing
	super.look_around(spread)
	_look_goal = facing
	facing = before


# --- Main loop -----------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		return
	if not is_passive() or state == State.RETURN:
		_look_goal = Vector3.ZERO
	elif _look_goal != Vector3.ZERO and not is_helpless():
		facing = _turned(_look_goal)
	if state != State.CHASE and state != State.ATTACK:
		if shield_state == Shield.PLANTED:
			_drop_aim()
			_set_shield(Shield.CARRIED)
			_phase = Phase.ADVANCE
		if not shield_up() and _home_set and not is_helpless():
			_tick_fetch(delta)   # (its pavise first, whatever else it was doing)
			_update_visual(delta)
			_check_fire()
			return
	super._physics_process(delta)
	_check_fire()


func _process(_delta: float) -> void:
	if Net.is_puppet(self) and not dead:
		_check_fire()


func _tick_chase(delta: float) -> void:
	if not _validate_target(delta):
		_drop_aim()
		return
	if not shield_up() or _phase == Phase.LIFT or _phase == Phase.EXPOSED or _phase == Phase.FLAT:
		_tick_fetch(delta)
		return
	if shield_state == Shield.CARRIED and (_phase == Phase.AIM or _phase == Phase.RELOAD):
		_phase = Phase.ADVANCE   # (it lifted its pavise meanwhile: walk, then plant again)
	var mark := _pick_mark(delta)
	if mark == null:
		return
	target = mark
	# The bash: a hero in its face (it drops a tracking aim for it; a locked shot goes first).
	if fire_at < 0.0 and GameWorld.time >= _next_attack_time:
		var h := _bash_target()
		if h != null:
			_drop_aim()
			target = h
			_begin_windup(scaled_cooldown(BASH_WINDUP))
			return
	_prog_t = 0.0
	match _phase:
		Phase.ADVANCE:
			_tick_advance(delta, mark)
		Phase.PLANT:
			face_point(mark.global_position)
			if GameWorld.time >= _phase_until:
				_plant()
		_:
			_tick_planted(delta, mark)


func _tick_advance(delta: float, mark: Actor) -> void:
	var d := GameWorld.flat_distance(global_position, mark.global_position)
	if d <= ADVANCE_MAX and _clear_shot(mark):
		_begin_plant()
		return
	_nav_to(target_point(), delta)


func _begin_plant() -> void:
	_phase = Phase.PLANT
	_phase_until = GameWorld.time + PLANT_TIME
	_set_shield(Shield.CARRIED)


func _plant() -> void:
	_set_shield(Shield.PLANTED)
	_no_shot_t = 0.0
	if _loaded:
		_phase = Phase.AIM
	else:
		_begin_reload()


func _begin_reload() -> void:
	_phase = Phase.RELOAD
	_phase_until = GameWorld.time + scaled_cooldown(RELOAD_SOAKED if Burning.is_soaked(self) else RELOAD_TIME)


func _tick_planted(delta: float, mark: Actor) -> void:
	var locked := fire_at >= 0.0
	var tracking := charge_victim != null and not locked
	# Who it turns to: the victim it tracks; else a hero right in front of it; else its mark.
	var turn_to: Actor = charge_victim if tracking and is_instance_valid(charge_victim) else _near_hero(NEAR_TURN)
	if turn_to == null:
		turn_to = mark
	if not locked:
		var to := turn_to.global_position - global_position
		to.y = 0.0
		if to.length() > 0.01 and rad_to_deg(Vector3(facing.x, 0.0, facing.z).normalized().angle_to(to.normalized())) > REPLANT_DEG:
			_drop_aim()
			_begin_plant()   # (lifts it, turns at the carried rate, stamps it in again)
			return
		face_point(turn_to.global_position)
	var shot := _clear_shot(mark) and GameWorld.flat_distance(global_position, mark.global_position) <= BOLT_RANGE
	_no_shot_t = 0.0 if shot or locked else _no_shot_t + delta
	if _no_shot_t >= LOS_GRACE:
		_drop_aim()
		_set_shield(Shield.CARRIED)
		_phase = Phase.ADVANCE
		return
	match _phase:
		Phase.RELOAD:
			if GameWorld.time >= _phase_until:
				_loaded = true
				_phase = Phase.AIM
		Phase.AIM:
			if tracking:
				var v := charge_victim
				if v == null or not is_instance_valid(v) or v.dead or not _clear_shot(v):
					_drop_aim()
				elif GameWorld.time >= _charge_t0 + _charge_len * (TRACK_TIME / AIM_TIME):
					_lock(v)
			elif not locked and _loaded and shot:
				var to_m := mark.global_position - global_position
				to_m.y = 0.0
				if to_m.length() > 0.01 and rad_to_deg(Vector3(facing.x, 0.0, facing.z).normalized().angle_to(to_m.normalized())) <= AIM_START_DEG:
					_begin_charge(mark)


## The mark (see the header), re-picked every MARK_EVERY (never while aiming).
func _pick_mark(delta: float) -> Actor:
	if _taunted():
		_mark = target
		return _mark
	_mark_t -= delta
	var keep := _mark != null and is_instance_valid(_mark) and not _mark.dead
	if keep and (_mark_t > 0.0 or charge_victim != null or fire_at >= 0.0):
		return _mark
	_mark_t = MARK_EVERY
	var best: Actor = null
	var best_back := false
	var best_d := INF
	for h in heroes():
		if not is_instance_valid(h) or h.dead:
			continue
		var d := GameWorld.flat_distance(global_position, h.global_position)
		if d > BOLT_RANGE or not _clear_shot(h):
			continue
		var back := not _monster_near(h, BACKLINE)
		if (back and not best_back) or (back == best_back and d < best_d):
			best = h
			best_back = back
			best_d = d
	_mark = best if best != null else target
	return _mark


func _monster_near(h: Actor, r: float) -> bool:
	for m in get_tree().get_nodes_in_group("monsters"):   # (duck-typed: see Monster._alert_pack)
		if m == self or m.dead:
			continue
		if GameWorld.flat_distance(m.global_position, h.global_position) <= r:
			return true
	return false


func _near_hero(r: float) -> Actor:
	var best: Actor = null
	var best_d := r
	for h in heroes():
		if not is_instance_valid(h) or h.dead:
			continue
		var d := GameWorld.flat_distance(global_position, h.global_position)
		if d <= best_d:
			best = h
			best_d = d
	return best


## A hero (or the chicken it chases) within the bash's reach, in the front arc and level with it.
func _bash_target() -> Actor:
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	var cands: Array = heroes().duplicate()
	if _taunted():
		cands.append(target)
	for h: Actor in cands:
		if h == null or not is_instance_valid(h) or h.dead:
			continue
		var to := h.global_position - global_position
		if absf(to.y) > 2.1 * Hex.LEVEL_HEIGHT:
			continue
		to.y = 0.0
		if to.length() > BASH_REACH + h.radius or to.length() < 0.001:
			continue
		if rad_to_deg(f.angle_to(to.normalized())) <= SHIELD_HALF_ARC:
			return h
	return null


## The bolt flies flat at BOLT_HEIGHT: the line at that height must be clear (an archer's rule, higher).
func _clear_shot(a: Actor) -> bool:
	if a == null or not is_instance_valid(a) or a.dead:
		return false
	var map := GameWorld.map
	if map == null:
		return true
	var from := global_position + Vector3.UP * BOLT_HEIGHT
	var to := Vector3(a.global_position.x, from.y, a.global_position.z)
	return map.line_of_sight(from, to, 0.08)


# --- The bolt: charge, lock, loose (a scheduled effect on every machine) --------------------------------------------------

func _begin_charge(v: Actor) -> void:
	charge_victim = v
	_charge_t0 = GameWorld.time
	_charge_len = scaled_cooldown(AIM_TIME)
	lock_dir = Vector3.ZERO
	fire_at = -1.0
	charge_begun.emit(_charge_len)


func _lock(v: Actor) -> void:
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	var origin := _bow_point()
	var to := Net.lead_point(v) - origin
	to.y = 0.0
	var dir := f
	if to.length() > 0.01:
		var off := rad_to_deg(f.signed_angle_to(to.normalized(), Vector3.UP))
		dir = f.rotated(Vector3.UP, deg_to_rad(clampf(off, -LOCK_MAX_DEG, LOCK_MAX_DEG)))
	facing = dir.normalized()
	lock_origin = origin
	lock_dir = dir.normalized()
	fire_at = _charge_t0 + _charge_len
	_lock_len = to.length() + 1.0 if to.length() > 0.01 else BOLT_RANGE
	beam_locked.emit(lock_origin, lock_dir, fire_at)


## Where the bolt starts: just past the planks, BOLT_HEIGHT over the feet.
func _bow_point() -> Vector3:
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	return global_position + f * (SHIELD_AHEAD + 0.35) + Vector3.UP * BOLT_HEIGHT


## Call off the aim (a shove, a daze, the victim gone, a bash): the line goes on every screen, a locked shot too.
func _drop_aim() -> void:
	if charge_victim == null and fire_at < 0.0:
		return
	charge_victim = null
	fire_at = -1.0
	lock_dir = Vector3.ZERO
	if Net.owns(self):
		charge_dropped.emit()


## The loose at fire_at (every machine: the host from its own lock, a client from world.lock). The bolt is an ordinary
## Projectile: each machine applies what it resolves (a player's hero by its own machine, the rest by the host's).
func _check_fire() -> void:
	if fire_at < 0.0 or GameWorld.time < fire_at:
		return
	var o := lock_origin
	var d := lock_dir
	fire_at = -1.0
	lock_dir = Vector3.ZERO
	charge_victim = null
	if dead or d == Vector3.ZERO:
		return
	_fire_bolt(o, d)
	if Net.owns(self):
		_loaded = false
		if _phase == Phase.AIM:
			_begin_reload()


func _fire_bolt(origin: Vector3, dir: Vector3) -> Projectile:
	var me: WeakRef = weakref(self)
	var on_hit := func(p: Projectile, hit: Actor, _pos: Vector3) -> void:
		var src: Node = me.get_ref() as Node
		if hit != null and is_instance_valid(hit) and not hit.dead and Net.resolves_hit(hit, src):
			hit.shove(p.direction, BOLT_SHOVE, src)
	var b := Fx.make_projectile(self, origin, dir, BOLT_DAMAGE, BOLT_SPEED, BOLT_RANGE, BOLT_COLOR, 0.13, on_hit)
	b.hits_props = true   # (it stops at the first hero, prop or box in its line)
	Sfx.play_at("bow_shot", origin)
	bolts_fired += 1
	last_bolt = b
	return b


## A client: the aim began (world.charge): the dashed line tracks `victim` as this screen shows it.
func net_charge(victim: Actor) -> void:
	charge_victim = victim
	lock_dir = Vector3.ZERO
	fire_at = -1.0


## A client: the aim was called off (world.uncharge), before or after the lock.
func net_uncharge() -> void:
	charge_victim = null
	fire_at = -1.0
	lock_dir = Vector3.ZERO


## A client: the lock (world.lock): the bolt's line, and when it looses on this machine's clock.
func net_lock(origin: Vector3, dir: Vector3, at: float) -> void:
	lock_origin = origin
	lock_dir = dir
	fire_at = at
	_lock_len = BOLT_RANGE
	if charge_victim != null and is_instance_valid(charge_victim):
		_lock_len = GameWorld.flat_distance(origin, charge_victim.global_position) + 1.0


## A client (world.shield) or a late joiner (NetWorld.apply_shields): the shield's state.
func net_shield(st: int, pos: Vector3, yaw: float) -> void:
	shield_state = st
	shield_pos = pos
	shield_yaw = yaw


# --- Shoves and interruptions -------------------------------------------------------------------------------------

func _on_interrupted() -> void:
	super._on_interrupted()
	if Net.owns(self):
		_drop_aim()   # (a shove, a stagger or a daze calls the aim off)


## A shove that reaches it got past the shield (Combat stops the ones from the front). Planted, it leaves the pavise
## standing (EXPOSED); pushed from behind into its own shield, it trips over it (FLAT). Carried, the shield goes with it.
func shove(dir: Vector3, distance: float, source: Node = null) -> void:
	if Net.is_copy(self):
		super.shove(dir, distance, source)   # (a request to the host)
		return
	var was_planted := shield_state == Shield.PLANTED and not dead
	var spot := _shield_spot()
	var f := Vector3(facing.x, 0.0, facing.z).normalized()
	super.shove(dir, distance, source)
	if not was_planted or not is_shoved() or dead:
		return
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() > 0.001 and d.normalized().dot(f) >= TRIP_DOT:
		_set_shield(Shield.FLAT, spot[0], spot[1])
		_phase = Phase.FLAT
		_phase_until = GameWorld.time + FLAT_TIME
		stagger(FLAT_TIME)
	else:
		_set_shield(Shield.LEFT, spot[0], spot[1])
		_phase = Phase.EXPOSED


## EXPOSED: walk back to the pavise and lift it; FLAT: get up and lift it.
func _tick_fetch(delta: float) -> void:
	match _phase:
		Phase.FLAT:
			_prog_t = 0.0
			if GameWorld.time >= _phase_until:
				_phase = Phase.LIFT
				_phase_until = GameWorld.time + LIFT_TIME
		Phase.LIFT:
			_prog_t = 0.0
			if GameWorld.time >= _phase_until:
				var yaw := shield_yaw
				_set_shield(Shield.CARRIED)
				facing = Vector3(-sin(yaw), 0.0, -cos(yaw))
				_phase = Phase.ADVANCE
		_:
			if shield_up():
				_phase = Phase.ADVANCE
				return
			_phase = Phase.EXPOSED
			if GameWorld.flat_distance(global_position, shield_pos) <= FETCH_DIST:
				_phase = Phase.LIFT
				_phase_until = GameWorld.time + LIFT_TIME
				return
			_nav_to(shield_pos, delta)


func _on_death() -> void:
	_drop_aim()
	if _fx != null:
		_fx.clear()
	super._on_death()


# --- Look (every screen) ----------------------------------------------------------------------------------------------

func _update_visual(delta: float) -> void:
	super._update_visual(delta)
	var pm := model as PaviseModel
	if pm != null and _shown_shield != shield_state:
		_shown_shield = shield_state
		pm.set_shield(["carried", "planted", "left", "dropped"][clampi(shield_state, 0, 3)])
		if shield_state == Shield.LEFT:
			pm.set_left_anchor(shield_pos, shield_yaw)
	var aiming := shield_state == Shield.PLANTED and (charge_victim != null or fire_at >= 0.0)
	var want := 1.0 if aiming else 0.0
	var k := move_toward(_aim_look, want, delta / (0.3 if aiming else 0.4))
	if pm != null and (absf(k - _aim_look) > 0.0001 or (k == 0.0 and pm.aim_k != 0.0)):
		pm.set_aim(k)
	_aim_look = k
	if pm != null:
		var lk := fire_at >= 0.0
		if lk != pm._locked:
			pm.set_locked(lk)
	_update_line()


## The floor line: dashed toward the tracked victim as this screen shows it, solid along the locked line. OFF (user,
## 2026-10-22: "Lets remove the laser on the pavise"): the aim reads from the crossbowman's own pose; SHOW_AIM_LINE
## brings it back.
func _update_line() -> void:
	if _fx == null or dead:
		return
	if not SHOW_AIM_LINE:
		if _fx.showing():
			_fx.clear()
		return
	if fire_at >= 0.0 and lock_dir != Vector3.ZERO:
		_fx.aim(lock_origin, lock_origin + lock_dir * _line_reach(lock_origin, lock_dir, _lock_len), true)
	elif charge_victim != null and is_instance_valid(charge_victim) and not charge_victim.dead:
		_fx.aim(_bow_point(), charge_victim.global_position, false)
	elif _fx.showing():
		_fx.clear()


## How far the locked line runs: to `want`, or the first wall or solid before it.
func _line_reach(from: Vector3, dir: Vector3, want: float) -> float:
	var reach := minf(want, BOLT_RANGE)
	var map := GameWorld.map
	if map == null:
		return reach
	var t := 0.2
	while t < reach:
		var p := from + dir * t
		var g := map.ground_height(p)
		if (not is_nan(g) and g > p.y) or map.solid_at(p):
			return t
		t += 0.25
	return reach


## A puppet's strike (the bash only: the bolt looses from world.lock): nothing extra to show.
func _on_strike_visual() -> void:
	pass


func _strike() -> void:
	Combat.melee_arc(self, facing, BASH_REACH, SHIELD_HALF_ARC * 2.0, BASH_DAMAGE, BASH_SHOVE)
