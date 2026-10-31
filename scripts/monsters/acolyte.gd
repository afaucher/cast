class_name Acolyte
extends Monster
## The necromancer's acolyte (docs/design/haunted-build-plan.md, H4; new-themes.md "Zombies and acolytes", decided; its look:
## necro-look.md, AcolyteModel "cowl", the lantern lighting the floor round it). A living cultist of the dead family on haunted
## floors 1-2, and the ones to hunt first: it RAISES the zombies' bodies it comes across and FLEES the crew. It is no fighter:
## it has no attack at all (cornered, it keeps trying to get away), so the AI allies rank it first (is_priority_target).
## Paid per kill (ContractRun's acolyte objectives, ContractSession.acolyte_stopped).
##
##   IDLE (marching)  walks in its PROCESSION (Procession.drive: the leader on the route, the rear at the back of the file), or
##                    stands where it is without one. It sees a hero within SIGHT in line of sight, or within NEAR at all ->
##                    FLEE, and calls its file onto them (Procession.engage). A body within RAISE_SIGHT (in sight, no hero
##                    within RAISE_SAFE of it, not another acolyte's) -> it walks to it (the file stops: Procession) ...
##   ATTACK (raising) ... and raises it: its wind-up (RAISE_T, world.windup with the body as its "victim"): arms up and out,
##                    the hands lit (AcolyteModel.set_raise, the look test's gesture), the body raised RAISE_AT in (Zombie.raise:
##                    Actor.revive at full HP, world.rise; it pushes up over Zombie.RISE_TIME) and it joins the file
##                    (Procession.join); the arms come down. A hero within NEAR, a shove or a stagger breaks it off (world.unwind).
##   ALERT (fleeing)  runs (FLEE_SPEED: the crew walks faster) to a spot away from the nearest hero, picked again every
##                    FLEE_PICK s; with no hero within SAFE for CALM s it goes back to its place in the file (IDLE), raising
##                    the bodies it passes on the way (what fell while it was away).
## A burnt body is never raised (Zombie._can_revive: out of the downed query). It dies and is freed like any monster (a living
## cultist leaves no body).
##
## Online (an owned actor, a host monster): no OWNER var of its own. Its state rides the stream's state bits (IDLE, ALERT,
## ATTACK) and the raise's progress the telegraph byte, so every screen poses the gesture from the stream; the raise itself is
## the host's (the body's world.rise). A late joiner gets it from the keyframe (a raise under way: its state and telegraph).

const HP := 30.0
const FLEE_SPEED := 3.2             ## its run (move_speed); the procession's walk is Procession.MARCH_SPEED
const SIGHT := 9.0                  ## it sees a hero this far, in line of sight ...
const NEAR := 4.0                   ## ... and knows one this close without
const SAFE := 12.0                  ## it stops running with no hero this close ...
const CALM := 3.0                   ## ... for this long
const FLEE_PICK := 1.2              ## a new spot to run to this often (or when it gets there)
const FLEE_MIN := 3                 ## the spot is this many cells away at least ...
const FLEE_MAX := 6                 ## ... and at most
const RAISE_SIGHT := 4.0            ## it notices a body this close (in line of sight)
const RAISE_SAFE := 7.0             ## and goes for it only with no hero this close to the body
const RAISE_REACH := 1.5            ## it raises from this close
const RAISE_WALK := 1.3             ## (times the march) its walk to a body
const RAISE_T := 3.0                ## the raise: arms up ARMS_UP, the body raised at RAISE_AT and standing RISE_TIME later, arms down
const RAISE_AT := 0.9
const ARMS_UP := 0.9
const ARMS_DOWN := 0.6
const GIVE_UP := 10.0               ## a body it could not reach is left alone this long

## Which acolyte is raising which body: body instance id -> acolyte instance id (two never go for one body).
static var _claims := {}

var raised := 0                     ## bodies it stood up (the host's; tests)
var _body: Actor = null             ## the body it walks to or raises
var _did_raise := false             ## the body was raised in this wind-up
var _flee_goal := Vector3.INF
var _flee_pick_t := 0.0
var _calm_t := 0.0
var _from := Vector3.INF            ## where the danger it runs from is
var _skip := {}                     ## body instance id -> GameWorld.time it may be tried again
var _arms := 0.0                    ## the gesture shown (a look on every machine, from the state and the telegraph)


func _init() -> void:
	super._init()
	kind = "acolyte"
	display_name = "Acolyte"
	max_hp = HP
	move_speed = FLEE_SPEED
	radius = 0.38
	aggro_range = SIGHT
	attack_damage = 0.0
	attack_windup = RAISE_T          # (a puppet times the raise's telegraph by it: Monster.net_show)
	attack_cooldown = 0.0
	attack_reach = 0.0
	attack_start_range = 0.0
	stop_distance = 1.0
	employee_chance = 0.0
	bar_width = 0.8
	walk_bob = 0.02


## Who may write each var (see Net); Monster's come from super(). Its AI is the host's.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"raised": Net.PRIVATE, "_body": Net.PRIVATE, "_did_raise": Net.PRIVATE, "_flee_goal": Net.PRIVATE,
		"_flee_pick_t": Net.PRIVATE, "_calm_t": Net.PRIVATE, "_from": Net.PRIVATE, "_skip": Net.PRIVATE,
		"_arms": Net.LOCAL,   # (the gesture: from `state` and `_telegraph` on every machine)
	})
	return f


func _ready() -> void:
	if model == null and not Monster.use_proto_visuals:
		model = AcolyteModel.new("cowl")
	super._ready()


## The gesture's arms at `t` seconds into a raise of `total` (0..1): up over `up`, held, down over the last ARMS_DOWN. The look
## test's curve (NecroProcession uses it with its own timing).
static func arms_at(t: float, total: float = RAISE_T, up: float = ARMS_UP) -> float:
	return clampf(t / up, 0.0, 1.0) * (1.0 - clampf((t - (total - ARMS_DOWN)) / ARMS_DOWN, 0.0, 1.0))


# --- How the floor reaches it ------------------------------------------------------------------------------------------

## Resting (marching or standing): what a hit or a sighting may start from.
func is_passive() -> bool:
	return state == State.IDLE


## It never fights.
func is_aggro() -> bool:
	return false


## The AI allies go for it first (the acolytes are the ones to hunt).
func is_priority_target() -> bool:
	return true


## True while it walks to a body or raises one (its procession stands).
func is_raising() -> bool:
	return _body != null or state == State.ATTACK


## True while it runs from the crew.
func is_fleeing() -> bool:
	return state == State.ALERT


## A hit, a pack-mate's call, a chicken: it runs from `t` (and calls its file onto it).
func aggro(t: Actor) -> void:
	if dead or t == null or not is_instance_valid(t) or t.dead:
		return
	_flee(t.global_position, t if t.team == GameWorld.TEAM_HEROES else null)


func _enter_chase(t: Actor) -> void:
	aggro(t)


## A monster's shout or an alarm: it runs from where the trouble is.
func alert(pos: Vector3) -> bool:
	if dead or is_frozen() or state == State.ALERT:
		return false
	_flee(pos, null)
	return true


## A sound: close by, it runs; farther off it only looks.
func hear(pos: Vector3) -> bool:
	if dead or is_frozen() or state != State.IDLE:
		return false
	if GameWorld.flat_distance(global_position, pos) <= NEAR * 2.0:
		_flee(pos, null)
	else:
		face_point(pos)
	return true


# --- Resting: marching, and the bodies it comes across -------------------------------------------------------------------

func _tick_idle(delta: float) -> void:
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_INTERVAL
		var h := _threat()
		if h != null:
			_flee(h.global_position, h)
			return
		if _body == null:
			_body = _find_body()
			if _body != null:
				_claims[_body.get_instance_id()] = get_instance_id()
				_clear_path()
	if _body != null:
		_go_raise(delta)
		return
	_march(delta)


## The nearest hero it notices: within SIGHT in line of sight, or within NEAR at all. None while frozen.
func _threat() -> Actor:
	if is_frozen():
		return null
	var h := _nearest_hero(aggro_range, true)
	return h if h != null else _nearest_hero(NEAR, false)


## The nearest zombie body within RAISE_SIGHT it can see, that no other acolyte is raising and no hero stands near. Null if none.
func _find_body() -> Actor:
	var best: Actor = null
	var best_d := INF
	var map := GameWorld.map
	for b in GameWorld.downed_in_radius(global_position, RAISE_SIGHT, GameWorld.TEAM_MONSTERS, true):   # (out in the fog too)
		if b.team != GameWorld.TEAM_MONSTERS or not b.has_method("raise") or not _free_body(b):
			continue
		if GameWorld.time < float(_skip.get(b.get_instance_id(), -INF)):
			continue
		var d := GameWorld.flat_distance(global_position, b.global_position)
		if d >= best_d or _hero_near(b.global_position, RAISE_SAFE):
			continue
		if map != null and not map.line_of_sight(Combat.chest(self), b.global_position + Vector3.UP * 0.4):
			continue
		best = b
		best_d = d
	return best


## True when no other living acolyte has claimed body `b`.
func _free_body(b: Actor) -> bool:
	var who: Variant = _claims.get(b.get_instance_id())
	if who == null or int(who) == get_instance_id():
		return true
	var other := instance_from_id(int(who)) as Monster
	return other == null or other.dead or not other.is_inside_tree()


func _hero_near(at: Vector3, r: float) -> bool:
	for h in heroes():
		if is_instance_valid(h) and not h.dead and GameWorld.flat_distance(h.global_position, at) <= r:
			return true
	return false


## Walking to the body it means to raise: raise it once close enough; let it go when it is gone, burnt, raised by someone else,
## or the crew is near it.
func _go_raise(delta: float) -> void:
	if not _body_ok() or _hero_near(_body.global_position, RAISE_SAFE):
		_let_go()
		return
	if GameWorld.flat_distance(global_position, _body.global_position) <= RAISE_REACH:
		_begin_raise()
		return
	if _stuck_n >= 3:
		_skip[_body.get_instance_id()] = GameWorld.time + GIVE_UP   # (it cannot get there: try another)
		_let_go()
		return
	march_to(_body.global_position, delta, Procession.MARCH_SPEED * RAISE_WALK)


func _body_ok() -> bool:
	return _body != null and is_instance_valid(_body) and _body.is_inside_tree() and _body.is_downed() and _free_body(_body)


func _let_go() -> void:
	if _body != null and is_instance_valid(_body) and int(_claims.get(_body.get_instance_id(), 0)) == get_instance_id():
		_claims.erase(_body.get_instance_id())
	_body = null
	target = null
	_stuck_n = 0


# --- Raising (its wind-up) -----------------------------------------------------------------------------------------------

func _begin_raise() -> void:
	face_point(_body.global_position)
	target = _body
	_did_raise = false
	_begin_windup(RAISE_T)   # (world.windup {v: the body}: every screen sees the gesture from the stream's telegraph)


func _tick_attack(delta: float) -> void:
	if _body == null or not is_instance_valid(_body) or (not _did_raise and not _body_ok()):
		_abort_raise()
		return
	var h := _threat()
	if h != null and GameWorld.flat_distance(global_position, h.global_position) <= NEAR:
		_abort_raise()
		_flee(h.global_position, h)
		return
	_windup_left -= delta
	_telegraph = clampf(1.0 - _windup_left / _windup_total, 0.0, 1.0)
	face_point(_body.global_position)
	_prog_t = 0.0
	if not _did_raise and _windup_total - _windup_left >= RAISE_AT:
		_did_raise = true
		if Net.resolves(_body) and bool(_body.call("raise")):
			raised += 1
			if procession != null and is_instance_valid(procession):
				procession.call("join", _body)
	if _windup_left <= 0.0:
		_end_windup()
		state = State.IDLE
		_let_go()


## The raise is broken off (the crew came, a shove, the body went): the arms drop; every screen hears world.unwind.
func _abort_raise() -> void:
	if state == State.ATTACK:
		_end_windup()
		state = State.IDLE
		windup_dropped.emit()
	_let_go()


func _on_interrupted() -> void:
	if state == State.ATTACK:
		_abort_raise()
	_nudge_t = 0.0
	_prog_t = 0.0


## No blow: the raise is the body's (Zombie.raise on the host). A puppet's "strike" (the end of the announced wind-up) is
## nothing on a client either.
func _strike() -> void:
	pass


func net_strike(_victim: Actor) -> void:
	pass


# --- Fleeing ---------------------------------------------------------------------------------------------------------------

## Run from `from` (a hero, a shout); the file turns on the crew (Procession.engage).
func _flee(from: Vector3, hero: Actor) -> void:
	if dead:
		return
	if state == State.ATTACK:
		_abort_raise()
	_let_go()
	var was := state
	state = State.ALERT
	_from = from
	_calm_t = 0.0
	_flee_pick_t = 0.0
	_flee_goal = Vector3.INF
	_clear_path()
	if was != State.ALERT and procession != null and is_instance_valid(procession):
		procession.call("engage", from, hero)


func _tick_alert(delta: float) -> void:
	var h := _nearest_hero(SAFE, false)
	if h == null:
		_calm_t += delta
		_prog_t = 0.0
		if _calm_t >= CALM:
			state = State.IDLE   # (back to its place in the file: Procession.drive; the bodies on its way first)
			_flee_goal = Vector3.INF
			_scan_t = 0.0
		return
	_calm_t = 0.0
	_from = h.global_position
	_flee_pick_t -= delta
	if _flee_goal == Vector3.INF or _flee_pick_t <= 0.0 or GameWorld.flat_distance(global_position, _flee_goal) < 0.6:
		_flee_goal = _away_spot(_from)
		_flee_pick_t = FLEE_PICK
	_nav_to(_flee_goal, delta)


## A walkable cell FLEE_MIN-FLEE_MAX cells off, as far from `from` as it can find and that it can reach (no dice: the host's
## AI, the same answer for the same floor).
func _away_spot(from: Vector3) -> Vector3:
	var map := GameWorld.map
	if map == null:
		var away := global_position - from
		away.y = 0.0
		return global_position + (away.normalized() if away.length() > 0.01 else Vector3.FORWARD) * 4.0
	var here := current_cell()
	var cell_here := map.get_cell(here)
	var lv := cell_here.level if cell_here != null else 0
	var cands: Array = []
	for c in Hex.range_cells(here, FLEE_MAX):
		if Hex.distance(c, here) < FLEE_MIN or not map.is_walkable_cell(c) or map.is_pool_cell(c):
			continue
		var cc := map.get_cell(c)
		if absi(cc.level - lv) > 2:
			continue
		var p := Hex.to_world(c, float(cc.level))
		cands.append([GameWorld.flat_distance(p, from) - GameWorld.flat_distance(global_position, from), c, p])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for i in mini(cands.size(), 6):
		if not map.find_path(here, cands[i][1], can_climb, 300).is_empty():
			return cands[i][2]
	return global_position


# --- Never a fighter's states --------------------------------------------------------------------------------------------
# (Nothing here starts them; a stray one goes back to rest.)

func _tick_chase(_delta: float) -> void:
	state = State.IDLE


func _tick_suspicious(_delta: float) -> void:
	state = State.IDLE


func _tick_search(_delta: float) -> void:
	state = State.IDLE


func _tick_return(_delta: float) -> void:
	state = State.IDLE


func _on_death() -> void:
	_let_go()
	super._on_death()


# --- The look ------------------------------------------------------------------------------------------------------------

## The raise is not a blow: no orange wind-up pulse (its hands light up instead). The hit flash stays.
func _apply_tint(color: Color, k: float) -> void:
	super._apply_tint(color, 0.0 if color == WINDUP_TINT else k)


## The gesture from the state and the telegraph (the host's own, a puppet's from the stream).
func _pose(_delta: float, _moving: bool) -> void:
	var a := arms_at(_telegraph * RAISE_T) if state == State.ATTACK else 0.0
	if absf(a - _arms) < 0.002:
		return
	_arms = a
	if model is AcolyteModel:
		(model as AcolyteModel).set_raise(a)


func _build_visual(root: Node3D) -> void:
	var robe := _mat(Color(0.15, 0.13, 0.13))
	var stole := _mat(Color(0.88, 0.84, 0.72))
	var skin := _mat(Color(0.84, 0.76, 0.68))
	var glow := _mat(Color(0.7, 0.85, 1.0), 2.0)
	_cone(root, 0.36, 1.2, Vector3(0, 0.6, 0), robe)
	_box(root, Vector3(0.12, 0.9, 0.04), Vector3(0, 0.8, -0.2), stole)
	_sphere(root, 0.14, Vector3(0, 1.45, -0.04), skin)
	_cone(root, 0.2, 0.4, Vector3(0, 1.55, 0.02), robe)
	_box(root, Vector3(0.05, 1.9, 0.05), Vector3(0.3, 0.95, -0.1), robe)
	_sphere(root, 0.08, Vector3(0.38, 1.75, -0.1), glow)
