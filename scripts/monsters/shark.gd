class_name Shark
extends Monster
## A pool shark (docs/design/sharks.md "As built"): the client's property with teeth, living in one pool of HexMap.pools.
## Three variants: "regular" (bites), "laser" (bites, and a beam strapped to its head that fires along its snout) and
## "imp" (the laser shark with an imp gunner, a Jockey, who swings the emitter up to 90 degrees off the snout and lends
## the shark an imp's eyes).
##
## WHAT IT IS (user, 2026-10-19): a killable priced thing. HP 150; hits are free; the KILL bills its price once, on the
## host, to whoever landed it ("Shark" $8,400 / "Laser shark" $12,600, worded like any prop). Team NEUTRAL, group "sharks"
## and PricedProp.GROUP (so the crew's swings, arrows and bolts hit it and the AI allies' prop care keeps it out of their
## swings and lanes), NOT "monsters": it is never a pest and monsters never fight it.
##
## MOVEMENT (host): SharkSteer, continuous steering inside the pool's real water polygon (a turning radius, speed ramps,
## rim feelers, a hard clamp CLEAR off the rim); it never leaves the water and a shove never moves it (a hard one HOLDS it).
## LOOK (every screen, LOCAL): SharkBody bends the body along the path this screen shows, banks it, trails the fin.
##
## ATTACKS
##   BITE    a target in the water or within BITE_ZONE of the rim: swim to APPROACH from it, face it, the wind-up
##           (BITE_WINDUP: the fin dips, the bow wave swells, the orange pulse), a lunge (LUNGE_T, the head up to 0.7 onto
##           the deck), the bite at the end of the lunge: BITE_DAMAGE and a BITE_SHOVE AWAY FROM THE POOL (back onto the
##           deck; a wader toward the nearer rim), then it slides back down its own path (RECOIL_T). Online the wind-up is a
##           world.windup of BITE_WINDUP + LUNGE_T and every machine resolves the bite on what it owns (Combat.bite).
##           In a one-row moat ring the lunge is short (the channel): the "drive-by snap" of the doc, same numbers here.
##   LASER   (laser / imp) a hero in sight: the CHARGE (CHARGE_T / attack rate): the red line tracks the victim for
##           TRACK_T, then LOCKS for the rest (solid, a reticle); then one straight beam along the locked line: BEAM_DAMAGE to
##           the first body it meets (Combat.beam: walls, solids and shut doors stop it; it lights an explosive prop: a hard
##           hit). Riderless it fires along its snout (it turns its whole body to aim); ridden, the imp swings the emitter
##           up to RIDER_SWING degrees. Online: world.charge (start, length, victim) at the charge, world.lock (origin,
##           direction, fire time) at the lock, and every machine fires the beam at the fire time on its own clock.
## STATUS  tentacles / a shove of HOLD_SHOVE+ HOLD it (no bite, no beam, a charge is dropped); vines root it (it stays
##         put, still bites what is in reach, still fires); a daze holds it; coffee speeds it and shortens the charge;
##         corn in its water is CHUM for CHUM_T (it noses the kernels, no attacks); a chicken that pecks it gets eaten.
## States ride the stream's 3 bits: CRUISE 0, HUNT 1, BITE 2, RECOIL 3, DEAD 4, CHARGE 5, HELD 6, CHUM 7.

signal charge_begun(length: float)
signal charge_dropped
signal beam_locked(origin: Vector3, dir: Vector3, fire_at: float)

const SharkModels := preload("res://scripts/art/lowpoly/props/shark_models.gd")

const CRUISE := 0
const HUNT := 1
const BITE := 2
const RECOIL := 3
const DEAD_STATE := 4
const CHARGE := 5
const HELD := 6
const CHUM := 7

const HP := 150.0
const PRICES := {"regular": 8400, "laser": 12600, "imp": 12600}   ## user, 2026-10-19: the design's prices less 30 %
const NAMES := {"regular": "Shark", "laser": "Laser shark", "imp": "Laser shark"}
const FLOAT := 0.06
const SCAN := 0.25
const BITE_ZONE := 1.2           ## a target this far onto the deck (or anywhere in the water) can be bitten
const SENSE_RANGE := 9.0
const APPROACH := 2.8
const BITE_WINDUP := 0.6
const LUNGE_T := 0.25
const BITE_DAMAGE := 18.0
const BITE_SHOVE := 1.5
const BITE_AT := 0.5             ## the jaws: this far ahead of the head joint ...
const BITE_REACH := 1.25         ## ... and this far round them (the snout tip, 0.85 ahead, and the sides of the head)
const RECOIL_T := 0.45
const BITE_COOLDOWN := 3.0
const BITE_COOLDOWN_LASER := 4.0
const HUNT_GIVE_UP := 1.5        ## the target out of reach this long: back to cruising
const AIM_BITE_DEG := 35.0       ## it lunges once the victim is this close to its nose (a moat channel allows no better)
const CHARGE_T := 1.2
const TRACK_T := 0.8
const BEAM_DAMAGE := 22.0
const BEAM_RANGE := 20.0
const BEAM_HALF_WIDTH := 0.25
const LASER_COOLDOWN := 7.0
const LASER_COOLDOWN_RIDDEN := 6.0
const NOSE_RANGE := 16.0         ## a riderless laser shark sees heroes this far in its nose cone ...
const NOSE_COS := 0.707          ## ... 90 degrees wide
const NOSE_FIRE_DEG := 12.0      ## ... and fires only once its snout is this close to the victim
const AIM_TURN := 1.3            ## rad/s (75 degrees a second): how fast it swings its body round while charging
const RIDER_SWING := 90.0
const RIDER_SIGHT := 9.0         ## the imp's eyes: all round ...
const RIDER_CONE := 15.0         ## ... and in its front cone
const HOLD_SHOVE := 1.0
const HOLD_T := 1.5
const CHUM_T := 4.0
const CHUM_RADIUS := 3.0         ## corn this close to its water is chum
const REVERSE_MIN := 6.0
const REVERSE_MAX := 12.0

# --- spawn data (SiteBuilder) -----------------------------------------------------------------------------------------
var variant := "regular"
var pool_index := -1
var price := 8400
var start_xz := Vector2.ZERO
var start_heading := Vector2.RIGHT
var rider: Monster = null        ## the imp gunner (a Jockey), set at spawn on every machine

# --- the stream and its events ---------------------------------------------------------------------------------------
var charge_victim: Actor = null  ## world.charge: whom the red line tracks
var lock_origin := Vector3.ZERO  ## world.lock: where the beam starts ...
var lock_dir := Vector3.ZERO     ## ... which way it goes ...
var fire_at := -1.0              ## ... and when (GameWorld.time on this machine; -1 = no beam pending)

# --- host AI ----------------------------------------------------------------------------------------------------------
var steer: SharkSteer = null
var _rec: Dictionary = {}
var _mode_t := 0.0
var _scan_s := 0.0
var _bite_ready := 0.0
var _laser_ready := 0.0
var _hunt_out := 0.0
var _recoil_left := 0.0
var _recoil_len := 0.0
var _turn_side := 1.0
var _turn_goal := Vector2.LEFT
var _turning := false
var _reverse_at := INF
var _held_until := -INF
var _chum_until := -INF
var _chum_at := Vector3.ZERO
var _charge_len := CHARGE_T
var _charge_t := 0.0
var _last_by: WeakRef = null     ## the last thing that hurt it: the kill's culprit

# --- the look ---------------------------------------------------------------------------------------------------------
var body: SharkBody = null
var _laser_fx: SharkLaserFx = null
var _aim_yaw := 0.0
var _beam_shown := -INF
var _cells := {}                 ## its pool's basin and ring cells (shark_water)


## Spawn data, before add_child (every machine, from the floor plan).
func setup(p_variant: String, p_pool: int, start: Vector2, heading: Vector2) -> void:
	variant = p_variant
	pool_index = p_pool
	price = int(PRICES.get(variant, PRICES["regular"]))
	display_name = String(NAMES.get(variant, NAMES["regular"]))
	start_xz = start
	start_heading = heading.normalized() if heading.length() > 0.001 else Vector2.RIGHT
	name = "Shark"


func _init() -> void:
	super._init()
	kind = "shark"
	team = GameWorld.TEAM_NEUTRAL
	display_name = "Shark"
	max_hp = HP
	move_speed = SharkSteer.HUNT
	radius = 0.75
	shove_mult = 0.0
	can_climb = false
	aggro_range = SENSE_RANGE
	attack_damage = BITE_DAMAGE
	attack_windup = BITE_WINDUP + LUNGE_T
	attack_cooldown = BITE_COOLDOWN
	attack_reach = BITE_REACH
	employee_chance = 0.0
	bar_height = 1.5
	bar_width = 1.2


func _ready() -> void:
	_rec = pool_record()
	super._ready()
	remove_from_group("monsters")
	add_to_group("sharks")
	add_to_group(PricedProp.GROUP)
	Burning.set_fireproof(self, true)   # (it is always wet: a fireball's blast hurts it, never sets it alight)
	steer = SharkSteer.new()
	if not _rec.is_empty():
		steer.setup(_rec, start_xz, start_heading)
		steer.pos = steer.clamp_in(start_xz)
		for c: Vector2i in (_rec.get("basin", []) as Array) + (_rec.get("ring", []) as Array):
			_cells[c] = true
	_sync_place()
	if body != null:
		body.reset(steer.pos, steer.dir)
	_reverse_at = GameWorld.time + GameWorld.rng.randf_range(REVERSE_MIN, REVERSE_MAX)


func pool_record() -> Dictionary:
	var map := GameWorld.map
	if map == null or pool_index < 0 or pool_index >= map.pools.size():
		return {}
	return map.pools[pool_index]


## Who may write each var (see Net). Monster's come from super().
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"variant": Net.SPAWN, "pool_index": Net.SPAWN, "price": Net.SPAWN, "start_xz": Net.SPAWN,
		"start_heading": Net.SPAWN, "rider": Net.SPAWN,
		"charge_victim": Net.OWNER, "lock_origin": Net.OWNER, "lock_dir": Net.OWNER, "fire_at": Net.OWNER,
		"steer": Net.PRIVATE, "_rec": Net.LOCAL, "_mode_t": Net.PRIVATE, "_scan_s": Net.PRIVATE,
		"_bite_ready": Net.PRIVATE, "_laser_ready": Net.PRIVATE, "_hunt_out": Net.PRIVATE,
		"_recoil_left": Net.PRIVATE, "_recoil_len": Net.PRIVATE, "_turn_side": Net.PRIVATE, "_turn_goal": Net.PRIVATE,
		"_turning": Net.PRIVATE, "_reverse_at": Net.PRIVATE, "_held_until": Net.PRIVATE, "_chum_until": Net.PRIVATE,
		"_chum_at": Net.PRIVATE, "_charge_len": Net.PRIVATE, "_charge_t": Net.PRIVATE, "_last_by": Net.PRIVATE,
		"body": Net.LOCAL, "_laser_fx": Net.LOCAL, "_aim_yaw": Net.LOCAL, "_beam_shown": Net.LOCAL, "_cells": Net.LOCAL,
	})
	return f


func has_laser() -> bool:
	return variant != "regular"


## The imp gunner is aboard and alive.
func ridden() -> bool:
	return rider != null and is_instance_valid(rider) and not rider.dead and bool(rider.get("mounted"))


## Is cell `c` water a living shark swims in (or its rim)? The AI allies keep their formation slots out of it.
static func shark_water(c: Vector2i) -> bool:
	if GameWorld.root == null or not GameWorld.root.is_inside_tree() or GameWorld.map == null or not GameWorld.map.is_pool_cell(c):
		return false
	for n in GameWorld.root.get_tree().get_nodes_in_group("sharks"):
		var s := n as Shark
		if s != null and not s.dead and s._cells.has(c):
			return true
	return false


## Is `a` this shark's own rider (the AI allies' lane check lets a shot at the imp pass its mount)?
func is_mount_of(a: Object) -> bool:
	return a != null and a == rider


# --- the look ---------------------------------------------------------------------------------------------------------

func _build_visual(_root: Node3D) -> void:
	body = SharkBody.new()
	add_child(body)
	if not _rec.is_empty():
		body.setup(variant, _rec)


func _apply_tint(color: Color, k: float) -> void:
	if state == CHARGE and color == WINDUP_TINT:
		k = 0.0   # (the laser's one telegraph is its red line: no orange pulse on the body while it charges)
	if body != null:
		body.set_tint(color, k)


func _update_visual(delta: float) -> void:
	super._update_visual(delta)
	if body == null or body.shark == null:
		return
	body.telegraph = _telegraph if state == BITE else 0.0
	body.follow(Vector2(global_position.x, global_position.z), Vector2(facing.x, facing.z), delta)
	_update_laser_look()
	if rider != null and is_instance_valid(rider) and rider.has_method("ride"):
		rider.call("ride")


## The emitter's swivel and the lens, the red line while charging, the beam when it fires (every screen).
func _update_laser_look() -> void:
	if not has_laser():
		return
	var charging := state == CHARGE and not dead
	var want_yaw := 0.0
	var aim_pt := Vector3.INF
	if fire_at >= 0.0 and lock_dir != Vector3.ZERO:
		aim_pt = lock_origin + lock_dir * 4.0
	elif charging and charge_victim != null and is_instance_valid(charge_victim):
		aim_pt = charge_victim.global_position
	if aim_pt != Vector3.INF and ridden():
		var to := aim_pt - global_position
		want_yaw = clampf(rad_to_deg(Vector2(facing.x, facing.z).angle_to(Vector2(to.x, to.z))) * -1.0, -RIDER_SWING, RIDER_SWING)
	_aim_yaw = lerpf(_aim_yaw, want_yaw, 0.35)
	body.aim(_aim_yaw, _telegraph if charging else 0.0)
	if _laser_fx == null:
		_laser_fx = SharkLaserFx.new()
		add_child(_laser_fx)
	if charging or fire_at >= 0.0:
		var m: Array = body.muzzle()
		var deck := float(_rec.get("deck_level", 0)) * Hex.LEVEL_HEIGHT
		if fire_at >= 0.0 and lock_dir != Vector3.ZERO:
			var end := _beam_end(lock_origin, lock_dir)
			_laser_fx.aim(lock_origin, end, deck, true)
		else:
			var from: Vector3 = m[0]
			var end := _beam_end(from, m[1])
			_laser_fx.aim(from, end, deck, false)
	elif GameWorld.time - _beam_shown > SharkLaserFx.BEAM_LIFE:
		_laser_fx.clear()


## Where a beam from `from` along `dir` would stop now (the line drawn while it charges).
func _beam_end(from: Vector3, dir: Vector3) -> Vector3:
	var map := GameWorld.map
	var d := dir
	d.y = 0.0
	d = d.normalized() if d.length() > 0.0001 else Vector3.FORWARD
	var reach := BEAM_RANGE
	if map != null:
		var t := 0.1
		while t < BEAM_RANGE:
			var p := from + d * t
			var g := map.ground_height(p)
			if (not is_nan(g) and g > p.y) or map.solid_at(p):
				reach = t
				break
			t += 0.2
		var door := map.blocker_contact(from, from + d * reach)
		if door != Vector3.INF:
			reach = minf(reach, GameWorld.flat_distance(from, door))
	return from + d * reach


# --- host AI ------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead or steer == null or _rec.is_empty():
		return
	_mode_t += delta
	_check_fire()
	if is_dazed() or GameWorld.time < _held_until:
		_enter_held()
		steer.hold(delta)
	else:
		if state == HELD:
			_set_state(CRUISE)
		_tick_ai(delta)
	_sync_place()
	_update_visual(delta)


func _tick_ai(delta: float) -> void:
	var k := move_speed_mult()
	var rooted := is_rooted()
	match state:
		CRUISE:
			if GameWorld.time < _chum_until:
				_set_state(CHUM)
				return
			_scan(delta)
			if state != CRUISE:
				return
			if rooted:
				steer.hold(delta)
			elif _turning:
				if steer.turn_round(delta, _turn_side, _turn_goal, k):
					_turning = false
					steer.loop_sign = -steer.loop_sign
			else:
				if steer.hole.is_empty() and GameWorld.time >= _reverse_at:
					_reverse_at = GameWorld.time + GameWorld.rng.randf_range(REVERSE_MIN, REVERSE_MAX)
					_turning = true
					_turn_side = steer.roomier_side()
					_turn_goal = -steer.dir
				else:
					steer.patrol(delta, k)
		HUNT:
			_tick_hunt(delta, k, rooted)
		BITE:
			_tick_bite(delta, rooted)
		RECOIL:
			_recoil_left -= delta
			var u := clampf(1.0 - _recoil_left / RECOIL_T, 0.0, 1.0)
			var want := _recoil_len * 0.85 * u * u * (3.0 - 2.0 * u)
			var done := steer.lunged
			if want > done:
				steer.back(want - done)
				steer.lunged = want
			if _recoil_left <= 0.0:
				_set_state(CRUISE)
		CHARGE:
			_tick_charge(delta, k, rooted)
		CHUM:
			if GameWorld.time >= _chum_until:
				_set_state(CRUISE)
				return
			var to := Vector2(_chum_at.x, _chum_at.z) - steer.pos
			if rooted:
				steer.hold(delta)
			elif to.length() > 0.8:
				steer.steer(to, SharkSteer.HUNT * 0.6 * k, delta)
			else:
				steer.steer(steer.dir.rotated(0.9), 0.5 * k, delta)   # (circling the kernels)
		HELD:
			_set_state(CRUISE)


func _set_state(s: int) -> void:
	state = s
	_mode_t = 0.0
	if s != BITE:
		_telegraph = 0.0


## Every SCAN seconds: a bite target (something in its water or at the rim), else a laser target.
func _scan(delta: float) -> void:
	_scan_s -= delta
	if _scan_s > 0.0:
		return
	_scan_s = SCAN
	if GameWorld.time >= _bite_ready:
		var t := _bite_target()
		if t != null:
			target = t
			_hunt_out = 0.0
			_set_state(HUNT)
			return
	if has_laser() and GameWorld.time >= _laser_ready:
		var v := _laser_target()
		if v != null:
			_begin_charge(v)


## Can it bite `a`: alive, not itself or its rider, not a prop, in its water or within BITE_ZONE of the rim, close enough
## and level with the pool.
func _biteable(a: Actor) -> bool:
	if a == null or not is_instance_valid(a) or a.dead or a == self or a == rider:
		return false
	if a.is_in_group(PricedProp.GROUP) or a.is_in_group("breakables") or a is Hellgate or a is DecorBlocker:
		return false
	var p := Vector2(a.global_position.x, a.global_position.z)
	if steer.rim(p) < -BITE_ZONE:
		return false
	var deck := float(_rec.get("deck_level", 0)) * Hex.LEVEL_HEIGHT
	return absf(a.global_position.y - deck) <= 0.8


func _bite_target() -> Actor:
	var best: Actor = null
	var best_d := SENSE_RANGE
	for a in GameWorld.actors():
		if not _biteable(a):
			continue
		var d := GameWorld.flat_distance(a.global_position, global_position)
		if d < best_d:
			best_d = d
			best = a
	return best


## A hero the laser can see: riderless, in its nose cone within NOSE_RANGE; ridden, anyone the imp sees.
func _laser_target() -> Actor:
	var best: Actor = null
	var best_d := INF
	var fwd := Vector2(facing.x, facing.z).normalized()
	var map := GameWorld.map
	var eye := global_position + Vector3.UP * 0.9
	for h in heroes():
		if not is_instance_valid(h) or h.dead:
			continue
		var to := Vector2(h.global_position.x - global_position.x, h.global_position.z - global_position.z)
		var d := to.length()
		if d < 0.5 or d >= best_d:
			continue
		var cs := fwd.dot(to / d)
		var ok := false
		if ridden():
			ok = d <= RIDER_SIGHT or (d <= RIDER_CONE and cs >= 0.5)
		else:
			ok = d <= NOSE_RANGE and cs >= NOSE_COS
		if not ok:
			continue
		if map != null and not map.line_of_sight(eye, Combat.chest(h)):
			continue
		best = h
		best_d = d
	return best


func _tick_hunt(delta: float, k: float, rooted: bool) -> void:
	if not _biteable(target):
		_hunt_out += delta
		if _hunt_out >= HUNT_GIVE_UP or target == null or not is_instance_valid(target) or target.dead:
			target = null
			_set_state(CRUISE)
			return
	else:
		_hunt_out = 0.0
	var tp := Vector2(target.global_position.x, target.global_position.z)
	var to := tp - steer.pos
	var close := to.length() <= APPROACH + 0.35
	var aimed := absf(steer.dir.angle_to(to)) <= deg_to_rad(AIM_BITE_DEG)
	if close and aimed:
		_begin_bite()
		return
	if rooted:
		steer.hold(delta)
		return
	if close:
		steer.steer(to, 0.3 * k, delta, false)
		return
	var spot := _approach_spot(tp)
	var go := spot - steer.pos
	steer.steer(go, lerpf(0.6, SharkSteer.HUNT, clampf(go.length() / 1.5, 0.0, 1.0)) * k, delta)


## Where it waits to lunge: APPROACH from the target, CLEAR + 0.25 inside the water, nearest the shark.
func _approach_spot(tp: Vector2) -> Vector2:
	var best := steer.pos
	var best_score := INF
	for i in 16:
		var p := tp + Vector2.from_angle(TAU * float(i) / 16.0) * APPROACH
		if steer.rim(p) < SharkSteer.CLEAR + 0.25:
			continue
		var s := p.distance_to(steer.pos)
		if s < best_score:
			best_score = s
			best = p
	return best if best_score < INF else steer.clamp_in(tp, 0.25)


func _begin_bite() -> void:
	_set_state(BITE)
	_windup_total = BITE_WINDUP + LUNGE_T
	_windup_left = _windup_total
	_telegraph = 0.0
	steer.begin_lunge()
	windup_begun.emit(_windup_total)


func _tick_bite(delta: float, rooted: bool) -> void:
	_windup_left -= delta
	var t := _windup_total - _windup_left
	if t < BITE_WINDUP:
		_telegraph = clampf(t / BITE_WINDUP, 0.0, 1.0)
		if target != null and is_instance_valid(target) and t < BITE_WINDUP * 0.6:
			steer.steer(Vector2(target.global_position.x, target.global_position.z) - steer.pos, 0.12, delta, false)
		else:
			steer.hold(delta)
		return
	_telegraph = 0.0
	if not rooted:
		steer.lunge(delta)
	if _windup_left <= 0.0:
		_strike()
		strikes += 1
		_bite_ready = GameWorld.time + scaled_cooldown(BITE_COOLDOWN_LASER if has_laser() else BITE_COOLDOWN)
		_recoil_len = steer.lunged
		steer.lunged = 0.0
		_recoil_left = RECOIL_T
		_set_state(RECOIL)


## The bite (the host's own, and every client's from the wind-up event on its own hero): at the snout, everyone in
## reach, shoved out of the water.
func _strike() -> void:
	# the jaws: round the middle of the head (its snout and both sides: a snap sideways in a moat channel lands too)
	var jaws := global_position + Vector3(facing.x, 0.0, facing.z).normalized() * BITE_AT
	jaws.y = float(_rec.get("deck_level", 0)) * Hex.LEVEL_HEIGHT
	var skip: Array = [rider] if rider != null else []
	Combat.bite(self, jaws, BITE_REACH, BITE_DAMAGE, BITE_SHOVE, _out_of_water, skip, 1.0)
	if Net.owns(self):
		MonsterSenses.noise(global_position, MonsterSenses.NOISE_MELEE, "bite")


## The way a bite throws `a`: out of the water (back onto the deck; a wader toward the nearer rim).
func _out_of_water(a: Actor) -> Vector3:
	var g := steer.out_of_water(Vector2(a.global_position.x, a.global_position.z)) if steer != null else Vector2.ZERO
	if g.length() < 0.01:
		var away := a.global_position - global_position
		return Vector3(away.x, 0.0, away.z)
	return Vector3(g.x, 0.0, g.y)


# --- the laser ----------------------------------------------------------------------------------------------------

func _begin_charge(v: Actor) -> void:
	charge_victim = v
	_charge_len = CHARGE_T / maxf(attack_rate_mult(), 0.25)
	_charge_t = 0.0
	_set_state(CHARGE)
	charge_begun.emit(_charge_len)
	Sfx.play_at("fuse", global_position)   # (the fuse's sizzle: an existing, probed cue; the beam stops it)


func _tick_charge(delta: float, k: float, rooted: bool) -> void:
	_charge_t += delta
	_telegraph = clampf(_charge_t / _charge_len, 0.0, 1.0)
	var lock_t := _charge_len * (TRACK_T / CHARGE_T)
	var v := charge_victim
	if lock_dir == Vector3.ZERO:
		if v == null or not is_instance_valid(v) or v.dead:
			_drop_charge()
			return
		var to := Vector2(v.global_position.x, v.global_position.z) - steer.pos
		if rooted:
			steer.hold(delta)
		else:
			steer.steer(to, SharkSteer.CRUISE * 0.28 * k, delta, true, AIM_TURN * k)
		if _charge_t >= lock_t:
			_lock(v)
	else:
		steer.hold(delta)


## The lock: the beam's line is fixed (origin at the lens, along the emitter), and fires at fire_at on every machine.
func _lock(v: Actor) -> void:
	var m: Array = body.muzzle() if body != null else [global_position + Vector3.UP * 0.8, facing]
	var origin: Vector3 = m[0]
	var dir := Vector3(facing.x, 0.0, facing.z).normalized()
	var to := v.global_position - origin
	to.y = 0.0
	if ridden():
		var off := rad_to_deg(Vector2(dir.x, dir.z).angle_to(Vector2(to.x, to.z)))
		dir = dir.rotated(Vector3.UP, -deg_to_rad(clampf(off, -RIDER_SWING, RIDER_SWING)))
	elif to.length() > 0.01 and rad_to_deg(Vector2(dir.x, dir.z).angle_to(Vector2(to.x, to.z))) <= NOSE_FIRE_DEG:
		dir = to.normalized()
	lock_origin = origin
	lock_dir = dir.normalized()
	fire_at = GameWorld.time + (_charge_len - _charge_t)
	beam_locked.emit(lock_origin, lock_dir, fire_at)


func _drop_charge() -> void:
	if state == CHARGE:
		_set_state(CRUISE)
	charge_victim = null
	if fire_at < 0.0:
		lock_dir = Vector3.ZERO
	charge_dropped.emit()
	Sfx.stop_cue("fuse", 0.08)


## The beam at fire_at (every machine: the host from its own lock, a client from world.lock). Each applies what it resolves.
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
	var skip: Array = [rider] if rider != null else []
	var res := Combat.beam(self, o, d, BEAM_RANGE, BEAM_DAMAGE, BEAM_HALF_WIDTH, skip)
	_beam_shown = GameWorld.time
	if _laser_fx == null:
		_laser_fx = SharkLaserFx.new()
		add_child(_laser_fx)
	_laser_fx.fire(o, res["end"], float(_rec.get("deck_level", 0)) * Hex.LEVEL_HEIGHT)
	Sfx.stop_cue("fuse", 0.05)
	Sfx.play_at("fireball", res["end"])
	if Net.owns(self):
		strikes += 1
		_laser_ready = GameWorld.time + scaled_cooldown(LASER_COOLDOWN_RIDDEN if ridden() else LASER_COOLDOWN)
		if state == CHARGE:
			_set_state(CRUISE)


## A client: the charge began (world.charge): the red line tracks `victim` as this screen shows it.
func net_charge(victim: Actor) -> void:
	charge_victim = victim
	lock_dir = Vector3.ZERO
	fire_at = -1.0
	Sfx.play_at("fuse", global_position)


## A client: the charge was dropped before the lock.
func net_uncharge() -> void:
	charge_victim = null
	if fire_at < 0.0:
		lock_dir = Vector3.ZERO
	Sfx.stop_cue("fuse", 0.08)


## A client: the lock (world.lock): the beam's line, and when it fires on this machine's clock.
func net_lock(origin: Vector3, dir: Vector3, at: float) -> void:
	lock_origin = origin
	lock_dir = dir
	fire_at = at


func _process(_delta: float) -> void:
	if Net.is_puppet(self):
		_check_fire()


# --- position --------------------------------------------------------------------------------------------------------

## The actor sits where the steering put the head joint, at the pool's float height (never on the deck: the lunge's
## climb onto the coping is SharkBody's look).
func _sync_place() -> void:
	if steer == null:
		return
	var y := float(_rec.get("floor_level", 0)) * Hex.LEVEL_HEIGHT + FLOAT
	global_position = Vector3(steer.pos.x, y, steer.pos.y)
	facing = Vector3(steer.dir.x, 0.0, steer.dir.y)


## It never walks (coffee's twitch, a door's nudge): the steering moves it.
func move(_dir: Vector3, _delta: float) -> bool:
	return false


## A shove never moves it out of the water: a hard one (HOLD_SHOVE+: tentacles, a bowl, a spin, a blast) holds it.
func shove(dir: Vector3, distance: float, source: Node = null) -> void:
	if Net.is_copy(self):
		super.shove(dir, distance, source)   # (a request to the host)
		return
	if dead or distance < HOLD_SHOVE or is_rooted():
		return
	_held_until = maxf(_held_until, GameWorld.time + HOLD_T)
	_enter_held()


func _enter_held() -> void:
	if state == HELD:
		return
	if state == BITE:
		windup_dropped.emit()
	if state == CHARGE and lock_dir == Vector3.ZERO:
		_drop_charge()
	steer.lunged = 0.0
	_set_state(HELD)


## A chicken pecked it: it turns on the chicken (and its bite eats it).
func _on_pecked(source: Node) -> void:
	var c := source as Actor
	if dead or c == null or not is_instance_valid(c) or c.dead or state == BITE or state == CHARGE:
		return
	if _biteable(c):
		target = c
		_hunt_out = 0.0
		_set_state(HUNT)


## Corn in its water (CornStrike's slam, every machine; the host decides): chum for CHUM_T.
static func corn_at(pos: Vector3) -> void:
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return
	for n in GameWorld.root.get_tree().get_nodes_in_group("sharks"):
		var s := n as Shark
		if s == null or s.dead or not Net.simulates(s) or s.steer == null:
			continue
		if s.steer.rim(Vector2(pos.x, pos.z)) < -CHUM_RADIUS:
			continue
		s._chum(pos)


func _chum(pos: Vector3) -> void:
	_chum_until = GameWorld.time + CHUM_T
	_chum_at = pos
	if state == BITE:
		windup_dropped.emit()
	if state == CHARGE and lock_dir == Vector3.ZERO:
		_drop_charge()
	if state != HELD:
		_set_state(CHUM)


# --- damage and death ------------------------------------------------------------------------------------------------

func _on_damaged(_amount: float, source: Node) -> void:
	_flash_t = FLASH_TIME
	_update_bar()
	if source != null and is_instance_valid(source) and source != self:
		_last_by = weakref(source)


## The one who landed the kill (the bill's culprit; an explosive's blast blames its igniter, via Ledger).
func last_culprit() -> Node:
	return _last_by.get_ref() as Node if _last_by != null else null


func _on_death() -> void:
	state = DEAD_STATE
	_telegraph = 0.0
	fire_at = -1.0
	lock_dir = Vector3.ZERO
	charge_victim = null
	remove_from_group(PricedProp.GROUP)
	if Net.owns(self):
		Ledger.damage(display_name, price, last_culprit())   # (online the host bills it; a client's Ledger mirrors it)
		MonsterSenses.noise(global_position, MonsterSenses.NOISE_DEATH, "death")
		if rider != null and is_instance_valid(rider) and not rider.dead and rider.has_method("dismount"):
			rider.call("dismount", "jump")
	if _bar != null:
		_bar.visible = false
	if _laser_fx != null:
		_laser_fx.clear()
	Fx.number(global_position + Vector3(0, 1.4, 0), "-" + PricedProp.money(price), PricedProp.MONEY_RED, 1.1)
	if body != null:
		var tw := create_tween()
		tw.tween_property(body, "dead_k", 1.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_method(func(_v: float) -> void: _refresh_corpse(), 0.0, 1.0, 0.8)


func _refresh_corpse() -> void:
	if body != null and is_instance_valid(body):
		body.follow(Vector2(global_position.x, global_position.z), Vector2(facing.x, facing.z), 0.016)


# --- puppet (a client shows the host's shark) -----------------------------------------------------------------------

func net_show(new_facing: Vector3, _is_climbing: bool, new_hp: float, new_state: int, telegraph: float, strike_count: int) -> void:
	facing = new_facing
	if absf(new_hp - hp) > 0.05:
		if new_hp < hp:
			_flash_t = FLASH_TIME
		hp = new_hp
		_update_bar()
	if new_state != state:
		if state == CHARGE and new_state != CHARGE and fire_at < 0.0:
			Sfx.stop_cue("fuse", 0.08)
		state = new_state
	_telegraph = telegraph
	if strike_count != strikes:
		strikes = strike_count


## A client: the bite's moment reached this screen (world.windup): resolve it on this machine's hero.
func net_strike(victim: Actor) -> void:
	if dead:
		return
	target = victim
	_net_struck_at = GameWorld.time
	_strike()


func net_tick(delta: float) -> void:
	if body != null and body.dead_k <= 0.0 and not dead:
		_update_visual(delta)
