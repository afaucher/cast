class_name Actor
extends Node3D
## Base for everything that has hit points and walks the hex terrain:
## heroes, allies and monsters. Movement is kinematic on GameWorld.map
## (no physics bodies): step up 1 level, climb 2 (slowly), blocked above.
##
## Subclasses drive it by calling move(dir, delta) from _physics_process and
## build their own visuals as children.

signal damaged(amount: float, source: Node)
signal healed(amount: float)
signal died
## A shove began: world direction (X/Z unit) and the distance already scaled by shove_mult.
signal shoved(dir: Vector3, distance: float)
## Something happened during forced movement: kind is "slam", "land" or "void"; amount is the
## damage dealt (may be 0); pos is where. Fx listens to this for dust and numbers.
signal shove_impact(kind: String, pos: Vector3, amount: float)
## A peck landed (the Chicken spell's zero hit, `peck`): `source` is the chicken.
signal pecked(source: Node)

@export var team: int = 0
@export var max_hp: float = 100.0
@export var move_speed: float = 4.0
@export var radius: float = 0.4
@export var display_name: String = "Actor"
## How far shoves carry this actor: 1 = normal, 0 = immovable, 0.4 = heavy, 1.5 = light.
@export var shove_mult := 1.0
## Speed multiplier while crossing a +2 climb ledge (a hero kit tunes it: Wick 0.6, Gasket 0.25).
@export var climb_speed_factor := CLIMB_SPEED_FACTOR

const CLIMB_SPEED_FACTOR := 0.35

# --- Modifiers (set_modifier) -----------------------------------------------------------
# One verb, four stats. Each active modifier is {mult, until, stat}; a stat's value is the PRODUCT of its live
# modifiers, so different sources stack (haste 1.6 x a goo slow 0.5 = 0.8) and the same id refreshes instead of
# stacking. Speed and attack rate are clamped so no pile-up freezes or rockets an actor; being rooted is the
# only way to stand still.
const STAT_DAMAGE_TAKEN := "damage_taken"   ## multiplies incoming damage (armor 0.4); the default stat
const STAT_MOVE_SPEED := "move_speed"       ## multiplies walking speed (coffee 1.6, crash 0.7, goo)
const STAT_ATTACK_RATE := "attack_rate"     ## multiplies attacks per second: cooldowns and the bow draw divide by it
const STAT_ROOT := "root"                   ## present = rooted: cannot move and cannot be shoved (vines); mult is unused
const STAT_DAZE := "daze"                   ## present = dazed: cannot move or attack, still casts (the brute's slam); mult is unused
const MOVE_MULT_MIN := 0.2
const MOVE_MULT_MAX := 2.5
const ATTACK_RATE_MIN := 0.25
const ATTACK_RATE_MAX := 3.0

# --- Forced movement (shove) tuning -------------------------------------------------
const SHOVE_TIME := 0.35          ## slide duration for a full-size shove (shorter for small nudges)
const SHOVE_TIME_MIN := 0.2
const SHOVE_FULL_DIST := 2.5      ## distance at which the slide takes the full SHOVE_TIME
const SHOVE_SUBSTEP := 0.2        ## max distance per collision check (cells are ~1.7 wide)
const SHOVE_GRAVITY := 24.0       ## world units / s^2 while airborne
const SHOVE_COAST_SPEED := 2.5    ## horizontal drift kept when a slide ends in mid-air
const SHOVE_COAST_DRAG := 2.5
const SLAM_RISE_LEVELS := 1.95    ## a rise of 2+ levels in the path stops the shove
const WALL_SLAM_DAMAGE := 8.0
const WALL_SLAM_STAGGER := 0.4
const WALL_SLAM_MIN_SHOVE := 1.0  ## a shorter nudge (melee) just stops at the wall: no damage, no stagger
const FALL_SAFE_LEVELS := 3       ## drops up to this are free; walking forbids more, shoves allow it
const FALL_DAMAGE_PER_LEVEL := 6.0
const FALL_STAGGER := 0.4
const VOID_FALL_TIME := 0.7       ## non-heroes fall this long into a pit, then die
const VOID_TICK_DAMAGE := 5.0     ## heroes pulled back from a pit take this
const PULL_TIME := 0.3

# --- Daze (the brute's direct slam) --------------------------------------------------------
const DAZE_ID := "daze"           ## the modifier id a daze lives under (STAT_DAZE)
const DAZE_GUARD := 1.5           ## seconds after a daze ends during which no new daze takes (no stun-lock)

var hp: float:
	set(v):
		if v != hp and Net.is_copy(self):
			Net.guard_write(self, "hp")   # (M4c: only the owner, or the net layer applying the owner's state, writes it)
		hp = v
var dead := false:
	set(v):
		if v != dead and Net.is_copy(self):
			Net.guard_write(self, "dead")
		dead = v
var facing := Vector3.FORWARD     ## unit X/Z vector the actor faces
var climbing := false             ## true while crossing a climb ledge
var pass_through_until := 0.0     ## GameWorld.time until which this actor does not push or get pushed by others
var _modifiers := {}              ## id -> {"mult": float, "until": float}

# Forced movement state. All of it is driven by _forced_tick(), connected to the tree's
# physics_frame signal only while a shove is active (idle actors pay nothing).
var _forced := false              ## any forced motion active (slide, fall, pit fall, pull-back)
var _hooked := false
var _slide_dir := Vector3.ZERO
var _slide_dist := 0.0
var _slide_dur := SHOVE_TIME
var _slide_t := 0.0
var _coast := Vector3.ZERO
var _airborne := false
var _vy := 0.0
var _fall_from_y := 0.0
var _void_fall := false
var _void_t := 0.0
var _pull := false
var _pull_t := 0.0
var _pull_from := Vector3.ZERO
var _pull_to := Vector3.ZERO
var _src_team := -1               ## team of whoever caused the current shove (-1 unknown)
var _src_ref: WeakRef = null
var _stagger_until := -1.0
var _daze_guard_until := -1.0     ## GameWorld.time until which a new daze is refused (the daze plus DAZE_GUARD)
var _safe_cell := Vector2i(1 << 20, 1 << 20)   ## last cell this actor stood on, for pit rescues


func _ready() -> void:
	hp = max_hp
	add_to_group("actors")
	snap_to_ground()


## Who may write each script var (see Net). Subclasses merge theirs into super(). Position and
## rotation are the owner's too. test_net_contract fails if a var is missing here.
func net_fields() -> Dictionary:
	return {
		"team": Net.SPAWN, "max_hp": Net.SPAWN, "move_speed": Net.SPAWN, "radius": Net.SPAWN,
		"display_name": Net.SPAWN, "shove_mult": Net.SPAWN, "climb_speed_factor": Net.SPAWN,
		"hp": Net.OWNER, "dead": Net.OWNER, "facing": Net.OWNER, "climbing": Net.OWNER,
		"pass_through_until": Net.OWNER,
		"_modifiers": Net.OWNER,        # armor shows on every screen
		# The shove slide runs on the owner; everyone else sees the resulting motion.
		"_forced": Net.PRIVATE, "_hooked": Net.PRIVATE, "_slide_dir": Net.PRIVATE,
		"_slide_dist": Net.PRIVATE, "_slide_dur": Net.PRIVATE, "_slide_t": Net.PRIVATE,
		"_coast": Net.PRIVATE, "_airborne": Net.PRIVATE, "_vy": Net.PRIVATE,
		"_fall_from_y": Net.PRIVATE, "_void_fall": Net.PRIVATE, "_void_t": Net.PRIVATE,
		"_pull": Net.PRIVATE, "_pull_t": Net.PRIVATE, "_pull_from": Net.PRIVATE,
		"_pull_to": Net.PRIVATE, "_src_team": Net.PRIVATE, "_src_ref": Net.PRIVATE,
		"_stagger_until": Net.PRIVATE, "_safe_cell": Net.PRIVATE,
		# The daze itself is a modifier (_modifiers, announced like any status); the immunity after it is the owner's
		# bookkeeping: only the owner applies a daze (Combat asks who resolves the target).
		"_daze_guard_until": Net.PRIVATE,
	}


# --- Health -------------------------------------------------------------------

## Multiplier on incoming damage from active modifiers (e.g. Armor zone 0.5).
func damage_taken_mult() -> float:
	return stat_mult(STAT_DAMAGE_TAKEN)


## Add or refresh a modifier. Same id refreshes, never stacks. `stat` says what it changes (the STAT_ constants);
## it defaults to damage taken, which is what every older caller means. Modifiers of one stat multiply, so a
## spell and a status stack sensibly. This is the verb for every timed buff or debuff: once the Net layer exists
## it applies here if this machine owns the actor and is sent to the owner otherwise.
func set_modifier(id: String, mult: float, duration: float, stat: String = STAT_DAMAGE_TAKEN) -> void:
	if Net.is_copy(self):
		Net.route_modifier(self, id, mult, duration, stat)   # (M4: its owner applies it)
		return
	_modifiers[id] = {"mult": mult, "until": _now() + duration, "stat": stat}
	Net.status_changed(self, "mods")   # (online: the other screens are told)


## Drop a modifier early (a re-dose of coffee cancels its crash). Part of the set_modifier verb.
func clear_modifier(id: String) -> void:
	if Net.is_copy(self) or not _modifiers.has(id):
		return
	_modifiers.erase(id)
	Net.status_changed(self, "mods")


## The modifiers this actor's owner announced (NetStatus, M4), on a copy: replaces the whole set. `mods` is id ->
## [mult, seconds left, stat]; `grace` keeps each one a little past its end, so a buff the owner keeps refreshing
## (armor) does not blink between two announcements. A daze is one blow, never refreshed, so it gets no grace (the stars
## leave every screen when they leave the owner's).
func net_set_modifiers(mods: Dictionary, grace: float) -> void:
	_modifiers.clear()
	for id: Variant in mods:
		var e := mods[id] as Array
		if e == null or e.size() < 3:
			continue
		var g := 0.0 if str(e[2]) == STAT_DAZE else grace
		_modifiers[str(id)] = {"mult": float(e[0]), "until": _now() + float(e[1]) + g, "stat": str(e[2])}


## The live modifiers as id -> [mult, seconds left, stat] (what the owner announces).
func modifiers_snapshot() -> Dictionary:
	var out := {}
	var now := _now()
	for id: String in _modifiers:
		var e: Dictionary = _modifiers[id]
		if float(e["until"]) >= now:
			out[id] = [float(e["mult"]), float(e["until"]) - now, str(e.get("stat", STAT_DAMAGE_TAKEN))]
	return out


func has_modifier(id: String) -> bool:
	return _modifiers.has(id) and _modifiers[id]["until"] >= _now()


## Seconds left on a modifier, 0 when it is not active.
func modifier_left(id: String) -> float:
	return maxf(0.0, float(_modifiers[id]["until"]) - _now()) if has_modifier(id) else 0.0


## The product of every live modifier of `stat` (1.0 with none). Expired ones are dropped here.
func stat_mult(stat: String) -> float:
	var now := _now()
	var m := 1.0
	for id in _modifiers.keys():
		var e: Dictionary = _modifiers[id]
		if e["until"] < now:
			_modifiers.erase(id)
		elif e.get("stat", STAT_DAMAGE_TAKEN) == stat:
			m *= float(e["mult"])
	return m


## Walking speed multiplier from every STAT_MOVE_SPEED modifier, clamped to MOVE_MULT_MIN..MOVE_MULT_MAX.
func move_speed_mult() -> float:
	return clampf(stat_mult(STAT_MOVE_SPEED), MOVE_MULT_MIN, MOVE_MULT_MAX)


## Units per second the actor really walks at: move_speed x its modifiers (x Wading.SPEED_MULT in pool water), 0 while
## rooted. Movement code reads this, never move_speed (which stays the base value kits and AI set).
func effective_speed() -> float:
	return 0.0 if is_rooted() else move_speed * move_speed_mult() * (Wading.speed_mult(global_position) if is_inside_tree() else 1.0)


## Attacks-per-second multiplier from every STAT_ATTACK_RATE modifier, clamped to ATTACK_RATE_MIN..ATTACK_RATE_MAX.
func attack_rate_mult() -> float:
	return clampf(stat_mult(STAT_ATTACK_RATE), ATTACK_RATE_MIN, ATTACK_RATE_MAX)


## A base cooldown (or draw time) as it is right now: shorter when hasted, longer when slowed.
func scaled_cooldown(base: float) -> float:
	return base / attack_rate_mult()


## Rooted (vines): cannot walk and cannot be shoved, but may still attack and cast.
func is_rooted() -> bool:
	return stat_mult_present(STAT_ROOT)


## Dazed (a direct hit from the brute's slam): cannot walk or attack (move refuses, is_helpless), but casts still go off.
func is_dazed() -> bool:
	return stat_mult_present(STAT_DAZE)


## Daze this actor for `seconds` (the verb; Combat.slam calls it on the targets this machine resolves, so the target's
## owner applies it, and the modifier is announced to the other screens like any status). It ignores shove_mult: an
## immovable hero still reels. Refused while already dazed or within DAZE_GUARD of the last daze ending (no stun-lock),
## while dead, and on a copy (its owner decides). Returns true when the daze took.
func daze(seconds: float, _source: Node = null) -> bool:
	if dead or seconds <= 0.0 or Net.is_copy(self) or not is_inside_tree():
		return false
	if is_dazed() or _now() < _daze_guard_until:
		return false
	_daze_guard_until = _now() + seconds + DAZE_GUARD
	set_modifier(DAZE_ID, 1.0, seconds, STAT_DAZE)
	_on_interrupted()
	_on_dazed(seconds)
	return true


## Seconds of immunity to a new daze left (0 when one would take; tests and the HUD).
func daze_guard_left() -> float:
	return maxf(0.0, _daze_guard_until - _now())


## Override: a daze just took (a hero lowers its bow and drops its swing).
func _on_dazed(_seconds: float) -> void:
	pass


## True if any live modifier has this stat (for stats where only presence matters).
func stat_mult_present(stat: String) -> bool:
	var now := _now()
	for id in _modifiers.keys():
		var e: Dictionary = _modifiers[id]
		if e["until"] < now:
			_modifiers.erase(id)
		elif e.get("stat", STAT_DAMAGE_TAKEN) == stat:
			return true
	return false


## Returns the damage actually dealt.
func apply_damage(amount: float, source: Node = null) -> float:
	if dead or amount <= 0.0:
		return 0.0
	if Net.is_copy(self):
		# A copy of a host-owned thing takes no damage on this machine (Net.simulates). A hit on a host-arbitrated object
		# (a priced prop, a crate, a mail box) goes to the host as a request instead (M3); the host applies it once.
		Net.route_hit(self, amount, source)
		return 0.0
	var dealt := amount * damage_taken_mult()
	hp = maxf(0.0, hp - dealt)
	if dealt > 0.0 and self is Hero:
		Net.note_hit(self, dealt, source)   # (telemetry: hits taken per player, and by what)
	damaged.emit(dealt, source)
	if hp <= 0.0:
		die()
	return dealt


## A hit for nothing: the Chicken spell's peck (Combat.peck). No damage, no stagger, no shove, so no Ledger line, no break,
## no panic and no damage number from here (apply_damage ignores an amount <= 0 on purpose, and every `damaged` listener
## assumes real damage, so a zero hit has this verb of its own). The chicken shows the "0" and the feathers itself, on every
## screen. A monster turns on whoever pecked it (Monster._on_pecked); everything else shrugs. Applied by the machine that
## resolves the hit (Combat.peck); a copy ignores it (nobody but its owner reacts to a peck, and a hero does not react).
func peck(source: Node = null) -> void:
	if dead or Net.is_copy(self):
		return
	pecked.emit(source)
	_on_pecked(source)


## Override: what a peck does to this actor (Monster: it chases the chicken). Default: nothing.
func _on_pecked(_source: Node) -> void:
	pass


## Returns the HP actually restored.
func heal(amount: float) -> float:
	if dead or amount <= 0.0 or Net.is_copy(self):
		return 0.0   # (a copy: its owner heals it, M4: the heal is a cast every machine runs, layer 4)
	var before := hp
	hp = minf(max_hp, hp + amount)
	if hp > before:
		healed.emit(hp - before)
	return hp - before


func die() -> void:
	if dead or Net.is_copy(self):
		return
	dead = true
	died.emit()
	GameWorld.actor_died.emit(self)
	_on_death()


## Override for death visuals. Default: vanish.
func _on_death() -> void:
	queue_free()


# --- Movement -----------------------------------------------------------------

## Move along X/Z direction `dir` (length <= 1 scales speed) for one frame.
## Slides along blocked edges, slows on climbs, and keeps Y on the ground.
## Returns true if the actor moved.
func move(dir: Vector3, delta: float) -> bool:
	dir.y = 0.0
	if _forced:
		return false   # being shoved: steering is ignored
	if dir.length() < 0.001 or dead or is_dazed():
		climbing = false
		return false   # (dazed: the brute's slam; no walking until it wears off)
	if dir.length() > 1.0:
		dir = dir.normalized()
	facing = dir.normalized()
	if is_rooted():
		climbing = false
		return false   # vines: can turn and attack, cannot walk
	var map: HexMap = GameWorld.map
	var step := dir * effective_speed() * delta
	var from := global_position
	var moved := false
	for raw in [step, Vector3(step.x, 0, 0), Vector3(0, 0, step.z)]:
		var attempt: Vector3 = raw
		if map:
			# walls (HexMap.clip_move): the body stops touching the face and slides along it
			attempt = map.clip_move(from, from + raw, radius) - from
			attempt.y = 0.0
		if attempt.length() < 0.0001:
			if map and raw == step:
				break   # pressed straight into a wall or a corner: stay put (no drift from the per-axis tries)
			continue
		var probe: Vector3 = from + attempt + attempt.normalized() * radius * 0.5
		if map and map.wall_at(probe):
			probe = from + attempt   # the wall was already handled by clip_move: judge the height where the body goes
		var mv := map.movement_check(from, probe) if map else HexMap.Move.OK
		if mv == HexMap.Move.BLOCKED or (mv == HexMap.Move.CLIMB and not _climb_allowed()):
			continue
		climbing = mv == HexMap.Move.CLIMB
		var s: Vector3 = attempt * (climb_speed_factor if climbing else 1.0)
		global_position = from + s
		moved = true
		break
	if not moved:
		climbing = false
	_separate()
	snap_to_ground(delta)
	_note_safe()
	return moved


# --- Forced movement: shove / slam / fall / pit ---------------------------------------
#
# Kinematic and deterministic, no physics bodies. shove() starts a short ease-out slide on
# the X/Z plane. While it runs the actor ignores move() (and the controllers skip their
# input via is_helpless()). Terrain rules differ from walking:
#   - a rise of 2+ levels (or a wall) stops the slide: "slam", WALL_SLAM_DAMAGE + a stagger
#   - drops are free up to FALL_SAFE_LEVELS; beyond that the actor falls under gravity and
#     takes FALL_DAMAGE_PER_LEVEL per extra level on landing (shoves may cross ledges that
#     walking forbids)
#   - void: heroes are pulled back to the last cell they stood on (small damage); everyone
#     else falls in and dies
#   - a shove caused by a hero can never take a hero below 1 HP (slam, fall or pit)

## Push this actor `distance` world units along `dir` (X/Z, any length) after scaling by
## shove_mult (and by a wet floor, Damp.slide_mult). A rooted actor (vines) is not pushed at all.
## `source` is who caused it (used for friendly-fire protection and damage credit).
func shove(dir: Vector3, distance: float, source: Node = null) -> void:
	if Net.is_copy(self):
		if not dead and distance > 0.0:
			Net.route_shove(self, dir, distance, source)   # (M4: a request to its owner, which runs the slide itself)
		return
	if dead or shove_mult <= 0.0 or distance <= 0.0 or _void_fall or _pull or not is_inside_tree() or is_rooted():
		return   # (a rooted actor ignores every shove: tentacles, the bowl, the spin, melee, props)
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = facing
	dir.y = 0.0
	dir = dir.normalized()
	if not _forced:
		_note_safe()
	var d := distance * shove_mult * Damp.slide_mult(self)   # a wet floor slides further
	_slide_dir = dir
	_slide_dist = d
	_slide_dur = lerpf(SHOVE_TIME_MIN, SHOVE_TIME, clampf(d / SHOVE_FULL_DIST, 0.0, 1.0))
	_slide_t = 0.0
	_coast = Vector3.ZERO
	var a := source as Actor
	_src_team = a.team if a != null else -1
	_src_ref = weakref(source) if source != null else null
	climbing = false
	_forced = true
	if not _hooked:
		_hooked = true
		get_tree().physics_frame.connect(_forced_tick)
	_on_interrupted()
	shoved.emit(dir, d)


## True while forced motion is in progress (sliding, airborne from a shove, falling into a
## pit, being pulled back).
func is_shoved() -> bool:
	return _forced


## How hard this slide would hit something now: the slide's distance times the share of it still to go (0.3 at least),
## 0 when only coasting. A priced prop prices the impact from it, on this actor's own machine (the slide is its owner's).
func slide_impact() -> float:
	if not _forced or _slide_t >= _slide_dur:
		return 0.0
	return _slide_dist * clampf(1.0 - _slide_t / maxf(_slide_dur, 0.001), 0.3, 1.0)


## Stop the slide dead against an obstacle (a prop), like a wall slam without the damage.
func stop_slide() -> void:
	_slide_t = _slide_dur
	_coast = Vector3.ZERO
	shove_impact.emit("slam", global_position, 0.0)


## Who caused the current shove (null if unknown or gone).
func shove_source() -> Node:
	return _src_ref.get_ref() as Node if _src_ref != null else null


## True during the stagger after a wall slam or a hard landing.
func is_staggered() -> bool:
	return _now() < _stagger_until


## Shoved, staggered or dazed: AI and input should not steer or attack (voice casts still work).
func is_helpless() -> bool:
	return _forced or _now() < _stagger_until or is_dazed()


## True while a shove has the actor off the ground.
func is_airborne() -> bool:
	return _airborne or _void_fall


func stagger(seconds: float) -> void:
	if dead:
		return
	_stagger_until = maxf(_stagger_until, _now() + seconds)
	_on_interrupted()


## Override: a shove or stagger just started (monsters cancel their wind-up here).
func _on_interrupted() -> void:
	pass


## Override: forced motion finished and the actor is standing again (not called on death).
func _on_shove_ended() -> void:
	pass


static func _shove_ease(u: float) -> float:
	var k := 1.0 - clampf(u, 0.0, 1.0)
	return 1.0 - k * k


func _note_safe() -> void:
	if _airborne or GameWorld.map == null:
		return
	var c := Hex.from_world(global_position)
	if GameWorld.map.is_walkable_cell(c):
		_safe_cell = c


func _safe_position() -> Vector3:
	var map: HexMap = GameWorld.map
	if map == null or not map.is_walkable_cell(_safe_cell):
		return global_position
	var p := Hex.to_world(_safe_cell)
	var g := map.ground_height(p)
	p.y = global_position.y if is_nan(g) else g
	return p


## Damage from forced movement, honouring friendly-fire protection.
func _forced_damage(amount: float) -> float:
	if dead or amount <= 0.0:
		return 0.0
	if team == GameWorld.TEAM_HEROES and _src_team == GameWorld.TEAM_HEROES:
		var room := hp - 1.0
		if room <= 0.0:
			return 0.0
		amount = minf(amount, room / maxf(damage_taken_mult(), 0.0001))
	var src: Node = null
	if _src_ref != null:
		src = _src_ref.get_ref() as Node
	return apply_damage(amount, src)


func _end_forced(notify: bool) -> void:
	_forced = false
	_slide_t = _slide_dur
	_coast = Vector3.ZERO
	_airborne = false
	_vy = 0.0
	_pull = false
	_void_fall = false
	if _hooked:
		_hooked = false
		var tree := get_tree()
		if tree != null and tree.physics_frame.is_connected(_forced_tick):
			tree.physics_frame.disconnect(_forced_tick)
	if notify and not dead:
		_on_shove_ended()


func _forced_tick() -> void:
	var delta := get_physics_process_delta_time()
	if dead or not is_inside_tree():
		_end_forced(false)
		if dead and is_inside_tree():
			snap_to_ground()
		return
	if _pull:
		_tick_pull(delta)
		return
	# Horizontal: the slide schedule, then any coasting momentum from a mid-air finish.
	var step := Vector3.ZERO
	if _slide_t < _slide_dur:
		var t1 := minf(_slide_dur, _slide_t + delta)
		step = _slide_dir * _slide_dist * (_shove_ease(t1 / _slide_dur) - _shove_ease(_slide_t / _slide_dur))
		_slide_t = t1
		if _slide_t >= _slide_dur and (_airborne or _void_fall):
			_coast = _slide_dir * SHOVE_COAST_SPEED
	elif _coast.length() > 0.05:
		step = _coast * delta
		_coast *= exp(-SHOVE_COAST_DRAG * delta)
	else:
		_coast = Vector3.ZERO
	var map: HexMap = GameWorld.map
	if _void_fall:
		global_position += step
		_tick_void(delta)
		return
	if map == null:
		global_position += step
		if _slide_t >= _slide_dur:
			_end_forced(true)
		return
	_advance(step, map)
	if _void_fall:
		_tick_void(delta)
		return
	if _pull or dead or not _forced:
		return
	if not _airborne:
		_separate()
	_tick_vertical(delta, map)
	if _forced and not _airborne and not _void_fall and not _pull and _slide_t >= _slide_dur and _coast == Vector3.ZERO:
		_end_forced(true)


## Move horizontally by `step` in small increments, checking the terrain at each one.
func _advance(step: Vector3, map: HexMap) -> void:
	var total := step.length()
	if total < 0.00001:
		return
	var dir := step / total
	var left := total
	while left > 0.0001:
		var s := minf(left, SHOVE_SUBSTEP)
		left -= s
		var from := global_position
		var np := from + dir * s
		np.y = from.y
		var cell: HexMap.Cell = map.get_cell(Hex.from_world(np))
		if cell == null:
			_enter_void(from, np)
			return
		var wall := map.blocks_point(np, radius)   # the body would overlap a wall face (HexMap)
		var blocked := wall
		if not blocked:
			var probe := np + dir * radius * 0.5
			var pcell: HexMap.Cell = map.get_cell(Hex.from_world(probe))
			if pcell != null:
				var ref_y := from.y
				if not _airborne:
					var g0 := map.ground_height(from)
					if not is_nan(g0):
						ref_y = g0
				blocked = (map.ground_height(probe) - ref_y) / Hex.LEVEL_HEIGHT >= SLAM_RISE_LEVELS
		if blocked:
			if wall:
				global_position = from.lerp(np, map.sweep(from, np, radius))   # slam with the body touching the face
			_slam()
			return
		global_position = np


func _slam() -> void:
	_slide_t = _slide_dur
	_coast = Vector3.ZERO
	if _slide_dist < WALL_SLAM_MIN_SHOVE:
		return
	var dealt := _forced_damage(WALL_SLAM_DAMAGE)
	stagger(WALL_SLAM_STAGGER)
	shove_impact.emit("slam", global_position, dealt)


func _enter_void(from: Vector3, over: Vector3) -> void:
	_airborne = false
	if team == GameWorld.TEAM_HEROES:
		_slide_t = _slide_dur
		_coast = Vector3.ZERO
		_pull = true
		_pull_t = 0.0
		_pull_from = from
		_pull_to = _safe_position()
		global_position = from
		var dealt := _forced_damage(VOID_TICK_DAMAGE)
		shove_impact.emit("void", from, dealt)
	else:
		global_position = over
		_void_fall = true
		_void_t = 0.0
		_vy = -1.0
		shove_impact.emit("void", over, 0.0)


func _tick_pull(delta: float) -> void:
	_pull_t += delta
	var k := clampf(_pull_t / PULL_TIME, 0.0, 1.0)
	var p := _pull_from.lerp(_pull_to, _shove_ease(k))
	p.y += sin(k * PI) * 0.9
	global_position = p
	if k >= 1.0:
		global_position = _pull_to
		_end_forced(true)
		stagger(0.3)
		_note_safe()


func _tick_void(delta: float) -> void:
	_void_t += delta
	_vy -= SHOVE_GRAVITY * 0.8 * delta
	global_position.y += _vy * delta
	rotation.x += 5.0 * delta
	var k := clampf(_void_t / VOID_FALL_TIME, 0.0, 1.0)
	scale = Vector3.ONE * lerpf(1.0, 0.35, k)
	if k >= 1.0:
		_end_forced(false)
		die()


func _tick_vertical(delta: float, map: HexMap) -> void:
	var g := map.ground_height(global_position)
	if is_nan(g):
		_enter_void(global_position, global_position)
		return
	if not _airborne:
		if global_position.y > g + 0.03:
			_airborne = true
			_fall_from_y = global_position.y
			_vy = 0.0
		else:
			global_position.y = lerpf(global_position.y, g, clampf(18.0 * delta, 0.0, 1.0))
			if absf(global_position.y - g) < 0.01:
				global_position.y = g
			return
	_vy -= SHOVE_GRAVITY * delta
	global_position.y += _vy * delta
	if global_position.y <= g:
		_land(g)


func _land(g: float) -> void:
	global_position.y = g
	var levels := (_fall_from_y - g) / Hex.LEVEL_HEIGHT
	_airborne = false
	_vy = 0.0
	_coast = Vector3.ZERO
	var over := int(floorf(levels + 0.1)) - FALL_SAFE_LEVELS
	if over > 0:
		var dealt := _forced_damage(FALL_DAMAGE_PER_LEVEL * over)
		stagger(FALL_STAGGER)
		shove_impact.emit("land", global_position, dealt)
	elif levels > 0.9:
		shove_impact.emit("land", global_position, 0.0)
	_note_safe()


## Keep Y on the ground. With delta, eases (so climbs and drops look smooth).
func snap_to_ground(delta: float = -1.0) -> void:
	var map: HexMap = GameWorld.map
	if map == null or not is_inside_tree():
		return
	var g := map.ground_height(global_position)
	if is_nan(g):
		return
	if delta < 0.0:
		global_position.y = g
	else:
		var rate := 4.0 if climbing else 14.0
		global_position.y = lerpf(global_position.y, g, clampf(rate * delta, 0.0, 1.0))
		if absf(global_position.y - g) < 0.01:
			global_position.y = g


## Push apart from overlapping actors (cheap circle separation). An actor with pass_through_until in the
## future neither pushes nor is pushed (an ally squeezing past the leader in a one-wide hall).
func _separate() -> void:
	var map: HexMap = GameWorld.map
	var ghost := pass_through_until > GameWorld.time
	for other in GameWorld.actors_in_radius(global_position, radius):
		if other == self or ghost or other.pass_through_until > GameWorld.time:
			continue
		var d := global_position - other.global_position
		d.y = 0.0
		var overlap := radius + other.radius - d.length()
		if overlap <= 0.0:
			continue
		var push := (d.normalized() if d.length() > 0.001 else Vector3.RIGHT) * overlap * 0.5
		var target := global_position + push
		if map != null:
			target = map.clip_move(global_position, target, radius)   # never pushed into a wall face
		if map == null or map.movement_check(global_position, target) == HexMap.Move.OK:
			global_position = target


## Override: may this actor cross a +2 climb ledge on foot? (Heroes: the kit's can_climb; Rebar can't.)
func _climb_allowed() -> bool:
	return true


## Turn to face a world point (X/Z only).
func face_point(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.001:
		facing = d.normalized()


func current_cell() -> Vector2i:
	return Hex.from_world(global_position)


func _now() -> float:
	return GameWorld.time
