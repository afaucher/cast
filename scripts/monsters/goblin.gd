extends Monster
## Goblin scout: the alarm (docs/design/goblin-scout.md; monster-awareness.md Option 4). He walks a corridor between two
## rooms (SiteBuilder plans the route), glancing about and stopping in each doorway to look into the room. When he
## spots the crew he panics, lights the fireworks on his back and runs for the nearest pack; when the rockets go up
## the alarm (MonsterSenses.alarm) sends the resting monsters around to where he saw the crew.
##
##   PATROL --(a hero in his cone 0.35 s, within 3, or a hit)--> TELL "!" 0.6 s --> LIGHT 1.4 s --> FUSE 1.6 s --> LAUNCH
##   LAUNCH --> HIDE (cowers behind the pack, tosses a firecracker if cornered) --> PATROL with an empty rack; he restocks
##   RESTOCK_TIME after a volley.
##
## Stopping him (the user's decisions, 2026-10-18):
##   - killed before the fuse catches (TELL or LIGHT): SILENT;
##   - shoved, staggered or rooted while lighting: he starts the light over when free (a rooted scout can't light);
##   - soaked (Damp) before the fuse: no light for the soak; he runs to the nearest pack and YELLS (a room shout);
##   - soaked with the fuse lit: a DUD (and he runs and yells);
##   - killed with the fuse lit: the fireworks STILL go off, where he fell, unless the rack is soaked;
##   - fire on the rack (a fireball's blast: MonsterSenses.fire_at; or burning for 1 s): the rack goes up at once;
##   - no sneak-attack bonus damage.
## His own "!" over his head is his tell (part of his animation in goblin-scout.md), not the general "?"/"!" indicator
## the user turned down for every monster.
##
## Online (goblin-scout.md §7): host AI. His phase and his rack travel as one reliable `world.scout {id, p, l}` per change
## (NetWorld), the volley as `world.fireworks` (launch point, start time, fx seed, drift: every screen builds the same
## FireworksFx), a dud as `world.dud`; a late joiner gets every scout's phase and rack in its snapshot. On the wire his
## monster state stands for the phase (PATROL/LOOK IDLE, TELL SUSPICIOUS, LIGHT ATTACK with the telegraph byte, FUSE /
## RUN / ASSIST ALERT, HIDE SEARCH). The cornered firecracker is a real wind-up (world.windup): each player's machine
## resolves the pop on its own hero (the victim decides). The alarm is host gameplay: the host owns what it wakes.

signal scout_phase_changed(phase: int, rack: bool)
signal fireworks_launched(pos: Vector3, fx_seed: int, drift: Vector3)
signal fireworks_dud(pos: Vector3)

enum Phase { PATROL, LOOK, TELL, LIGHT, FUSE, HIDE, RUN, ASSIST }

const HP := 24.0
const RUN_SPEED := 5.0            ## fleeing (heroes walk 4.5)
const PATROL_SPEED := 2.0
const SIGHT := 14.0               ## his front cone reaches this far (= Wick's tap range) ...
const SIGHT_COS := 0.5736         ## ... 110 degrees wide (cos 55)
const NEAR_SIGHT := 3.0           ## all round: "he heard you"
const SPOT_TIME := 0.35           ## seconds of continuous sight in the cone before he is sure (a double take)
const TELL_TIME := 0.6            ## the "!" (user: timing is right)
const LIGHT_TIME := 1.4           ## striking a light: his wind-up (coffee on him makes it faster)
const FUSE_TIME := 1.6
const LOOK_TIME := 2.5            ## a doorway look at each end of his route
const LOOK_SWEEP_DEG := 80.0
const GLANCE_MIN := 6.0           ## a glance on patrol every 6-10 s: the ears perk, then he looks
const GLANCE_MAX := 10.0
const GLANCE_PERK := 0.4
const GLANCE_HOLD := 1.2
const HIDE_TIME := 20.0           ## cowering after a volley before he goes back on patrol
const RESTOCK_TIME := 60.0        ## the rack is full again this long after a volley or a dud (user: restocks)
const RUN_MAX := 8.0              ## a soaked run ends (and he yells) at the latest after this long
const RUN_ARRIVE := 3.0
const ASSIST_MAX := 10.0          ## another scout's alarm: he runs to its sighting point for at most this long ...
const NO_CHAIN := 30.0            ## ... and lights no volley of his own for this long (no chain reactions)
const FLEE_SEARCH := 30.0         ## the pack he runs to is at most this far
const HIDE_CLEAR := 4.0           ## he hides more than this far from any hero
const BURN_LIGHTS := 1.0          ## a burning scout's rack goes up after this long
const CORNERED := 2.0             ## a hero this close while he hides: a firecracker
const TOSS_WINDUP := 0.45
const TOSS_REACH := 1.2           ## the pop lands this far ahead of him (where he aimed: dodgeable)
const TOSS_RADIUS := 1.5
const TOSS_DAMAGE := 3.0
const TOSS_SHOVE := 1.0
const TOSS_COOLDOWN := 3.0
const ARRIVE := 0.6

## Wire state per phase (Monster.State values; NetWorld streams them, the world.scout event carries the phase).
const WIRE := {
	Phase.PATROL: State.IDLE, Phase.LOOK: State.IDLE, Phase.TELL: State.SUSPICIOUS, Phase.LIGHT: State.ATTACK,
	Phase.FUSE: State.ALERT, Phase.HIDE: State.SEARCH, Phase.RUN: State.ALERT, Phase.ASSIST: State.ALERT,
}

var scout_phase: int = Phase.PATROL
var loaded := true                ## rockets in the rack
## The patrol, from SiteBuilder's plan (world points along the corridor, both ends doorways) and the way to look into
## the room at each end. Empty: he stands and glances (a dev spawn, a test arena).
var route: Array[Vector3] = []
var route_looks: Array[Vector3] = []

var volleys := 0                  ## tests and the log
var _route_i := 0
var _route_step := 1
var _phase_t := 0.0
var _spot_t := 0.0
var _sight_point := Vector3.INF   ## S: where the crew was seen
var _sighted_at := -1.0
var _light_t := 0.0
var _fuse_end := 0.0
var _goal := Vector3.INF          ## where he runs (FUSE, RUN, ASSIST, HIDE)
var _glance_t := 0.0
var _glance := 0                  ## 0 walking, 1 ears perked, 2 looking
var _glance_dir := Vector3.ZERO
var _look_base := Vector3.ZERO
var _restock_at := INF
var _burn_t := 0.0
var _no_alarm_until := -INF
var _tossing := false
var _next_toss := 0.0
var _yelled := false

# Look (every screen)
var _alert_k := 0.0
var _shown_phase := -1


func _init() -> void:
	super._init()
	kind = "goblin"
	display_name = "Goblin Scout"
	max_hp = HP
	move_speed = RUN_SPEED
	radius = 0.32
	shove_mult = 1.4
	aggro_range = NEAR_SIGHT       # (all-round sight; 0 freezes him like any monster)
	attack_damage = TOSS_DAMAGE
	attack_windup = TOSS_WINDUP
	attack_cooldown = TOSS_COOLDOWN
	attack_start_range = CORNERED
	employee_chance = 0.0
	bar_height = 2.4
	bar_width = 0.6


func _ready() -> void:
	super._ready()
	_glance_t = GameWorld.rng.randf_range(GLANCE_MIN, GLANCE_MAX)


## Who may write each var (see Net); Monster's come from super().
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		# What every screen draws: the "!", the fuse, the cower, the rack (world.scout).
		"scout_phase": Net.OWNER, "loaded": Net.OWNER,
		# The patrol comes from the floor plan (the same on every machine); only the host walks it.
		"route": Net.PRIVATE, "route_looks": Net.PRIVATE,
		# Host AI working state.
		"volleys": Net.PRIVATE, "_route_i": Net.PRIVATE, "_route_step": Net.PRIVATE, "_phase_t": Net.PRIVATE,
		"_spot_t": Net.PRIVATE, "_sight_point": Net.PRIVATE, "_sighted_at": Net.PRIVATE, "_light_t": Net.PRIVATE,
		"_fuse_end": Net.PRIVATE, "_goal": Net.PRIVATE, "_glance_t": Net.PRIVATE, "_glance": Net.PRIVATE,
		"_glance_dir": Net.PRIVATE, "_look_base": Net.PRIVATE, "_restock_at": Net.PRIVATE, "_burn_t": Net.PRIVATE,
		"_no_alarm_until": Net.PRIVATE, "_tossing": Net.PRIVATE, "_next_toss": Net.PRIVATE, "_yelled": Net.PRIVATE,
		# Presentation.
		"_alert_k": Net.LOCAL, "_shown_phase": Net.LOCAL,
	})
	return f


## The patrol from the floor plan: corridor waypoints (doorway to doorway) and the way to face into each end's room.
func set_route(points: Array[Vector3], looks: Array[Vector3], start: int) -> void:
	route = points
	route_looks = looks
	_route_i = clampi(start, 0, maxi(0, points.size() - 1))
	_route_step = 1 if _route_i < points.size() - 1 else -1


# --- Main loop --------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		return
	if not _home_set:
		_home_set = true
		home = global_position
		_prog_pos = global_position
		if spawn_facing == Vector3.ZERO:
			spawn_facing = facing
		_room = MonsterSenses.room_of(current_cell())
	CombatLog.tick()
	_phase_t += delta
	_check_fire(delta)
	_check_restock()
	if dead:
		return
	if scout_phase == Phase.FUSE and GameWorld.time >= _fuse_end:
		_launch()   # (the fuse burns on while he is shoved about)
	if is_helpless() or is_frozen():
		_update_visual(delta)
		return
	match scout_phase:
		Phase.PATROL:
			_tick_patrol(delta)
		Phase.LOOK:
			_tick_look(delta)
		Phase.TELL:
			_tick_tell(delta)
		Phase.LIGHT:
			_tick_light(delta)
		Phase.FUSE:
			_run_to(_goal, delta)
			if Burning.is_soaked(self):
				_dud()
		Phase.HIDE:
			_tick_hide(delta)
		Phase.RUN:
			_tick_run(delta)
		Phase.ASSIST:
			_tick_assist(delta)
	_update_visual(delta)


func _set_phase(p: int) -> void:
	scout_phase = p
	_phase_t = 0.0
	state = WIRE[p]
	if p != Phase.LIGHT:
		_telegraph = 0.0
	_clear_path()
	_stuck_n = 0
	scout_phase_changed.emit(p, loaded)


# --- Patrol -----------------------------------------------------------------------------------------------------

func _tick_patrol(delta: float) -> void:
	if _scan(delta):
		return
	# The glance: ears perk (he stops), then a look to one side, then on.
	if _glance > 0:
		_prog_t = 0.0
		if _glance == 1 and _phase_t >= GLANCE_PERK:
			_glance = 2
			_phase_t = 0.0
			var side := 1.0 if GameWorld.rng.randf() < 0.5 else -1.0
			var d := facing.rotated(Vector3.UP, deg_to_rad(side * GameWorld.rng.randf_range(70.0, 120.0)))
			_glance_dir = MonsterSenses.clear_heading(self, d, d)
			facing = _glance_dir.normalized()
		elif _glance == 2 and _phase_t >= GLANCE_HOLD:
			_glance = 0
			_glance_t = GameWorld.rng.randf_range(GLANCE_MIN, GLANCE_MAX)
		return
	_glance_t -= delta
	if _glance_t <= 0.0:
		_glance = 1
		_phase_t = 0.0
		return
	if route.size() < 2:
		return   # no route: he stands his post and glances
	var goal := route[_route_i]
	if GameWorld.flat_distance(global_position, goal) <= ARRIVE or _stuck_n >= STUCK_GIVE_UP:
		var at_end := _route_i == 0 or _route_i == route.size() - 1
		var look := route_looks[0 if _route_i == 0 else 1] if at_end and route_looks.size() >= 2 else Vector3.ZERO
		if _route_i + _route_step < 0 or _route_i + _route_step >= route.size():
			_route_step = -_route_step
		_route_i += _route_step
		_stuck_n = 0
		if at_end and look != Vector3.ZERO:
			_look(look)
		return
	_speed_k = PATROL_SPEED / RUN_SPEED
	_nav_to(goal, delta)
	_speed_k = 1.0


func _look(dir: Vector3) -> void:
	dir.y = 0.0
	_look_base = dir.normalized() if dir.length() > 0.01 else facing
	facing = _look_base
	_set_phase(Phase.LOOK)


func _tick_look(delta: float) -> void:
	if _scan(delta):
		return
	_prog_t = 0.0
	var k := sin(_phase_t / LOOK_TIME * TAU)
	facing = _look_base.rotated(Vector3.UP, deg_to_rad(LOOK_SWEEP_DEG * k))
	if _phase_t >= LOOK_TIME:
		facing = _look_base
		_set_phase(Phase.PATROL)


## His sight: a hero in his front cone (110 degrees, out to 14, line of sight) for 0.35 s, or one within 3. True if he
## spotted someone (and is now telling).
func _scan(delta: float) -> bool:
	var near := _nearest_hero(NEAR_SIGHT, true)
	if near != null:
		_spotted(near.global_position)
		return true
	var h := _cone_sight()
	if h == null:
		_spot_t = 0.0
		return false
	_spot_t += delta
	if _spot_t >= SPOT_TIME - 0.0001:
		_spotted(h.global_position)
		return true
	return false


func _cone_sight() -> Actor:
	var best: Actor = null
	var best_d := SIGHT
	var map := GameWorld.map
	var fwd := Vector3(facing.x, 0.0, facing.z).normalized()
	for h in heroes():
		if not is_instance_valid(h) or h.dead:
			continue
		var to := h.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > best_d or d < 0.001 or fwd.dot(to / d) < SIGHT_COS:
			continue
		if map != null and not map.line_of_sight(Combat.chest(self), Combat.chest(h)):
			continue
		best = h
		best_d = d
	return best


## He saw the crew at `pos` (or was hit from there): the "!" and then the light. An empty rack (or a recent alarm):
## he just hides.
func _spotted(pos: Vector3) -> void:
	if dead or not (scout_phase == Phase.PATROL or scout_phase == Phase.LOOK):
		return
	_sight_point = pos
	_sighted_at = GameWorld.time
	_spot_t = 0.0
	_glance = 0
	face_point(pos)
	CombatLog.scout(self, "sighted", GameWorld.flat_distance(global_position, pos))
	if not loaded or GameWorld.time < _no_alarm_until:
		_begin_hide()
		return
	_alert_k = 1.0
	_set_phase(Phase.TELL)


# --- The light and the fuse -----------------------------------------------------------------------------------------

func _tick_tell(_delta: float) -> void:
	face_point(_sight_point)
	_prog_t = 0.0
	if _phase_t >= TELL_TIME:
		if Burning.is_soaked(self):
			_begin_run()
			return
		_light_t = 0.0
		_set_phase(Phase.LIGHT)


func _tick_light(delta: float) -> void:
	_prog_t = 0.0
	if Burning.is_soaked(self):
		CombatLog.scout(self, "stopped", -1.0, GameWorld.time - _sighted_at, -1, "", "soaked")
		_begin_run()
		return
	if is_rooted():
		_light_t = 0.0   # the vines bind his match arm: he starts over when they let go
	else:
		_light_t += delta
	_telegraph = clampf(_light_t / scaled_cooldown(LIGHT_TIME), 0.0, 1.0)
	if _telegraph >= 1.0:
		_telegraph = 0.0
		_fuse_end = GameWorld.time + FUSE_TIME
		_goal = _pack_goal()
		_set_phase(Phase.FUSE)


## A shove or a stagger while he lights: the match drops, he starts over when he is free.
func _on_interrupted() -> void:
	if _tossing:
		_tossing = false
		_end_windup()
		state = WIRE[scout_phase]
		windup_dropped.emit()
	if scout_phase == Phase.LIGHT:
		_light_t = 0.0
		_telegraph = 0.0
	_nudge_t = 0.0
	_prog_t = 0.0


## The volley: rockets up from the rack at F (where he is), the alarm on the host.
func _launch() -> void:
	if not loaded:
		return
	loaded = false
	volleys += 1
	_restock_at = GameWorld.time + RESTOCK_TIME
	var f := global_position
	var at := _launch_point()
	var s := _sight_point if _sight_point != Vector3.INF else _nearest_hero_pos(f)
	var v := Vector3(facing.x, 0.0, facing.z)
	var drift := v.normalized() * 1.2 if v.length() > 0.01 else Vector3.ZERO
	var fx_seed := GameWorld.fx_rng.randi() & 0xFFFFFF   # (a look: its seed travels in the event)
	FireworksFx.launch(at, GameWorld.time, fx_seed, drift)
	fireworks_launched.emit(at, fx_seed, drift)
	var res := MonsterSenses.alarm(f, s, self)
	CombatLog.scout(self, "launch", -1.0, GameWorld.time - _sighted_at if _sighted_at >= 0.0 else -1.0, int(res["woken"]), str(res["gates"]), "scouts %d" % int(res["scouts"]))
	if not dead:
		_begin_hide()


## A soaked rack with the fuse lit: pfft. He runs and yells instead.
func _dud() -> void:
	loaded = false
	_restock_at = GameWorld.time + RESTOCK_TIME
	Fx.fizzle_puff(global_position)
	fireworks_dud.emit(global_position)
	CombatLog.scout(self, "dud", -1.0, GameWorld.time - _sighted_at)
	_begin_run()


func _launch_point() -> Vector3:
	if model != null and model.has_method("launch_point") and model.is_inside_tree():
		return model.call("launch_point")
	return global_position + Vector3.UP * 2.2


## Fire lights fireworks (goblin-scout.md §4): a fireball's blast (MonsterSenses.fire_at, before its damage lands).
func catch_fire() -> void:
	if dead or not loaded or Burning.is_soaked(self) or is_frozen():
		return
	if _sight_point == Vector3.INF:
		_sight_point = _nearest_hero_pos(global_position)
	_launch()


func _check_fire(delta: float) -> void:
	if loaded and Burning.is_burning(self) and not Burning.is_soaked(self):
		_burn_t += delta
		if _burn_t >= BURN_LIGHTS:
			catch_fire()
	else:
		_burn_t = 0.0


func _check_restock() -> void:
	if loaded or GameWorld.time < _restock_at:
		return
	if scout_phase == Phase.PATROL or scout_phase == Phase.LOOK or scout_phase == Phase.HIDE:
		loaded = true
		_restock_at = INF
		scout_phase_changed.emit(scout_phase, loaded)


# --- Running, hiding, yelling -----------------------------------------------------------------------------------

func _run_to(goal: Vector3, delta: float) -> bool:
	if goal == Vector3.INF or GameWorld.flat_distance(global_position, goal) <= RUN_ARRIVE:
		_prog_t = 0.0
		return false
	_nav_to(goal, delta)
	return true


## Soaked: no fireworks. He runs to the nearest pack and yells there (a room shout toward where he saw the crew).
func _begin_run() -> void:
	_goal = _pack_goal()
	_yelled = false
	_set_phase(Phase.RUN)


func _tick_run(delta: float) -> void:
	if (not _run_to(_goal, delta) or _phase_t >= RUN_MAX or _stuck_n >= STUCK_GIVE_UP) and not _yelled:
		_yelled = true
		var woken := 0
		for n in get_tree().get_nodes_in_group("monsters"):   # (duck-typed: see Monster._alert_pack)
			if n == self or n.dead or not Net.simulates(n) or n.kind == kind:
				continue
			if GameWorld.flat_distance(n.global_position, global_position) <= SHOUT_RADIUS and n.alert(_sight_point if _sight_point != Vector3.INF else global_position):
				woken += 1
		CombatLog.scout(self, "yell", -1.0, -1.0, woken)
		_begin_hide()


func _begin_hide() -> void:
	_goal = _hide_goal()
	_set_phase(Phase.HIDE)


func _tick_hide(delta: float) -> void:
	if _tossing:
		_tick_attack(delta)   # (Monster: the wind-up, then _strike, then it sets CHASE: back to hiding)
		if state != State.ATTACK:
			_tossing = false
			state = WIRE[scout_phase]
		return
	var h := _nearest_hero(CORNERED, true)
	if h != null and GameWorld.time >= _next_toss:
		target = h
		face_point(h.global_position)
		_tossing = true
		_next_toss = GameWorld.time + TOSS_COOLDOWN
		_begin_windup(TOSS_WINDUP)
		return
	if _phase_t < 1.0 or GameWorld.flat_distance(global_position, _goal) > RUN_ARRIVE:
		if _run_to(_goal, delta):
			return
	_prog_t = 0.0
	if _phase_t >= HIDE_TIME and not _hero_within(HIDE_CLEAR):
		_back_to_patrol()


## Another scout's volley (MonsterSenses.alarm): run to where the crew was seen instead of setting off his own.
func assist(s: Vector3) -> bool:
	if dead or is_frozen() or not (scout_phase == Phase.PATROL or scout_phase == Phase.LOOK):
		return false
	_sight_point = s
	_goal = s
	_no_alarm_until = GameWorld.time + NO_CHAIN
	_set_phase(Phase.ASSIST)
	return true


func _tick_assist(delta: float) -> void:
	if not _run_to(_goal, delta) or _phase_t >= ASSIST_MAX or _stuck_n >= STUCK_GIVE_UP:
		_look(facing)


func _back_to_patrol() -> void:
	# Rejoin the route at its nearest waypoint.
	var best := INF
	for i in route.size():
		var d := GameWorld.flat_distance(global_position, route[i])
		if d < best:
			best = d
			_route_i = i
	_set_phase(Phase.PATROL)


## The nearest resting pack within FLEE_SEARCH (where a scout runs to warn), else a spot away from the crew.
func _pack_goal() -> Vector3:
	var best := FLEE_SEARCH
	var goal := Vector3.INF
	for n in get_tree().get_nodes_in_group("monsters"):
		if n == self or n.dead or n.kind == kind or not Net.simulates(n) or n._room == "":
			continue
		if n.state != State.IDLE and n.state != State.SUSPICIOUS:
			continue
		var d := GameWorld.flat_distance(n.global_position, global_position)
		if d < best and d > RUN_ARRIVE:
			best = d
			goal = n.global_position
	return goal if goal != Vector3.INF else _away_spot()


## Behind the nearest monster that stands farther from the crew than he does, else a spot away from the crew.
func _hide_goal() -> Vector3:
	var crew := _nearest_hero_pos(global_position)
	if crew == Vector3.INF:
		return global_position
	var my_d := GameWorld.flat_distance(global_position, crew)
	var best := FLEE_SEARCH
	var goal := Vector3.INF
	for n in get_tree().get_nodes_in_group("monsters"):
		if n == self or n.dead or n.kind == kind or not Net.simulates(n):
			continue
		var d := GameWorld.flat_distance(n.global_position, global_position)
		var away: Vector3 = n.global_position - crew
		away.y = 0.0
		if d < best and away.length() > maxf(my_d, HIDE_CLEAR) and away.length() > 0.1:
			best = d
			goal = n.global_position + away.normalized() * 1.5
	return goal if goal != Vector3.INF and _walkable(goal) else _away_spot()


## A walkable cell 4-6 hexes out, as far from the crew as possible (and reachable).
func _away_spot() -> Vector3:
	var map := GameWorld.map
	var crew := _nearest_hero_pos(global_position)
	if map == null or crew == Vector3.INF:
		return global_position
	var here := current_cell()
	var best := -INF
	var goal := global_position
	for c in Hex.range_cells(here, 6):
		if Hex.distance(c, here) < 4 or not map.is_walkable_cell(c):
			continue
		var p := Hex.to_world(c, float(map.get_cell(c).level))
		var score := GameWorld.flat_distance(p, crew)
		if score > best and not map.find_path(here, c, can_climb, 200).is_empty():
			best = score
			goal = p
	return goal


func _walkable(p: Vector3) -> bool:
	var map := GameWorld.map
	return map == null or map.is_walkable_cell(Hex.from_world(p))


func _nearest_hero_pos(from: Vector3) -> Vector3:
	var best := INF
	var out := Vector3.INF
	for h in heroes():
		if is_instance_valid(h) and not h.dead and GameWorld.flat_distance(h.global_position, from) < best:
			best = GameWorld.flat_distance(h.global_position, from)
			out = h.global_position
	return out


# --- How the rest of the floor reaches him --------------------------------------------------------------------------

## Patrolling or looking: other code may treat him as a resting monster.
func is_passive() -> bool:
	return scout_phase == Phase.PATROL or scout_phase == Phase.LOOK


## Only the cornered firecracker is fighting (the combat log's engagements).
func is_aggro() -> bool:
	return _tossing


## A hit (or a pack call) counts as being spotted by the attacker.
func aggro(t: Actor) -> void:
	if t != null and is_instance_valid(t) and not t.dead:
		_spotted(t.global_position)


func _enter_chase(t: Actor) -> void:
	aggro(t)


## A chicken pecked him (the Chicken spell): he startles and looks at it, but a chicken is not the crew (no "!", no
## fireworks, and he never chases it).
func _on_pecked(source: Node) -> void:
	var c := source as Node3D
	if c != null and is_instance_valid(c):
		hear(c.global_position)


## A shout or a sound: he stops and looks that way (a doorway look). Never ALERT: the scout's job is the fireworks.
func alert(pos: Vector3) -> bool:
	return hear(pos)


func hear(pos: Vector3) -> bool:
	if dead or is_frozen() or not is_passive():
		return false
	_noise_at = GameWorld.time
	_noise_pos = pos
	_look(pos - global_position)
	return true


## The cornered firecracker: a pop where he aimed (TOSS_REACH ahead), through Combat (each machine resolves its own
## heroes: on a client this runs from the wind-up event, Monster.net_strike).
func _strike() -> void:
	var at := global_position + Vector3(facing.x, 0.0, facing.z).normalized() * TOSS_REACH
	Combat.explode(at, TOSS_RADIUS, TOSS_DAMAGE, GameWorld.other_team(team), self, 1.0)
	Combat.shove_radius(at, TOSS_RADIUS, TOSS_SHOVE, self, GameWorld.other_team(team))
	_pop_fx(at)


func _on_strike_visual() -> void:
	_pop_fx(global_position + Vector3(facing.x, 0.0, facing.z).normalized() * TOSS_REACH)


func _pop_fx(at: Vector3) -> void:
	var cols: Array[Color] = [Color(1.0, 0.8, 0.3), Color(1.0, 0.35, 0.1)]
	Fx.burst(at + Vector3.UP * 0.3, cols, 10, 3.0, 0.08, 0.35, 2.0)
	Fx.number(at + Vector3.UP * 1.2, "POP!", Color(1.0, 0.75, 0.25), 0.7)


func _on_death() -> void:
	if Net.owns(self):
		if scout_phase == Phase.FUSE and loaded and not Burning.is_soaked(self):
			_launch()   # the fuse had caught: the rockets go up where he fell (user, 2026-10-18)
		elif scout_phase == Phase.TELL or scout_phase == Phase.LIGHT:
			CombatLog.scout(self, "stopped", -1.0, GameWorld.time - _sighted_at, -1, "", "killed")
	if model is GoblinModel:
		var gm := model as GoblinModel
		gm.set_mark(false)
		gm.set_fuse_lit(false)
	super._on_death()


# --- Look (every screen) ----------------------------------------------------------------------------------------

## A client: the host's phase and rack (world.scout, or the late-join snapshot).
func net_scout(phase: int, rack: bool) -> void:
	if phase == Phase.TELL and scout_phase != Phase.TELL:
		_alert_k = 1.0
	scout_phase = phase
	loaded = rack


func _pose(delta: float, moving: bool) -> void:
	if not (model is GoblinModel):
		return
	var gm := model as GoblinModel
	_alert_k = maxf(0.0, _alert_k - delta / TELL_TIME) if scout_phase == Phase.TELL else 0.0
	var ak := minf(1.0, _alert_k * 1.6) if scout_phase == Phase.TELL else 0.0
	if absf(ak - gm.alert_k) > 0.001:
		gm.set_alert(ak)
	var mark := scout_phase == Phase.TELL or scout_phase == Phase.LIGHT or scout_phase == Phase.FUSE or scout_phase == Phase.RUN
	if gm.mark_on != mark:
		gm.set_mark(mark)
	var lit := scout_phase == Phase.FUSE and loaded
	if gm.fuse_lit != lit:
		gm.set_fuse_lit(lit)
	if gm.loaded != loaded:
		gm.set_loaded(loaded)
	var look := 1.0 if scout_phase == Phase.LOOK else 0.0
	if look > 0.0 or gm.look_k > 0.0:
		gm.set_look(look, fmod(GameWorld.time / LOOK_TIME, 1.0))
	var cower := 1.0 if scout_phase == Phase.HIDE and not moving and not _tossing else 0.0
	var ck := move_toward(gm.cower_k, cower, delta * 4.0)
	if absf(ck - gm.cower_k) > 0.0001:
		gm.set_cower(ck)
