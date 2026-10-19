class_name Monster
extends Actor
## Base class for every monster. A small state machine on top of Actor (awareness: docs/design/monster-awareness.md):
##
##   IDLE       -> a hero within aggro_range AND in line of sight -> CHASE. A hero in the front cone (120 degrees) out
##                 to aggro_range + 6 -> SUSPICIOUS; a sound (MonsterSenses.noise) -> SUSPICIOUS. Looks around every
##                 4-9 s (never at a wall); near the crew a kind may have idle life (skeleton patrols, imp play).
##   SUSPICIOUS -> turns to the sight or sound and edges toward it at half speed. 1.5 s of seeing a hero (in total), a
##                 hero inside aggro_range or a hit -> CHASE. Nothing for 6 s -> IDLE (or RETURN if it wandered).
##   ALERT      -> a monster was hit within 10 (its shout): walks to where the attacker stood at 80% speed for up to
##                 20 s, seeing farther (all round aggro + 4, cone aggro + 8). Sees a hero -> CHASE; arrives -> SEARCH.
##   SEARCH     -> stands and looks around for 5 s with the wide sight, then RETURN. Also where a chase that lost its
##                 target (beyond 2.5x aggro) ends up.
##   CHASE      -> path (A*) toward the target; start a windup when in attack range
##   ATTACK     -> telegraphed windup (no movement), then the strike, back to CHASE
##   RETURN     -> dragged too far from home (or lost the target): walk home, heal, IDLE. A hit turns it around.
##
## Online all of it runs on the host; the state rides the stream's 3 state bits (SUSPICIOUS/SEARCH/ALERT are 5-7). No
## "?"/"!" tells (user, 2026-10-18): turning and behaviour only. `aggro_range = 0` freezes a monster (tests,
## --idle-monsters): no sight, no look-arounds, no idle life, deaf, and it never shouts.
##
## Kinds (grunt/archer/brute/swarmer) set stats in _init(), build their look in
## _build_visual(), and override _strike() / _try_start_attack() / _chase_move()
## (or _tick_chase for completely custom behavior, as the archer does).
##
## Hit flash, windup tint, death topple/fade and the billboard HP bar live here.
##
## Looks: by default every kind wears its faceted MonsterModel (scripts/art/lowpoly/monsters). The
## model animates idle / walk by itself and gets the hooks windup(t), attack_swing(), set_tint(),
## set_fade() and set_downed(). The old primitive bodies (_build_visual) stay as a fallback: set
## `Monster.use_proto_visuals = true` before spawning (tests, a dev flag).

enum State { IDLE, CHASE, ATTACK, RETURN, DEAD, SUSPICIOUS, SEARCH, ALERT }

## A wind-up began (`length` seconds to the strike). Online the host sends it to every client (NetWorld world.windup), and
## each player's machine resolves the strike against its own hero (the victim decides, M4).
signal windup_begun(length: float)
## The wind-up ended without a strike (shoved, staggered, the target gone).
signal windup_dropped

const SCAN_INTERVAL := 0.25       ## idle LOS scan period (seconds)
const FLASH_TIME := 0.12
const REPATH_MIN := 0.4
const REPATH_MAX := 0.6
const PATH_MAX_NODES := 1200
const RETARGET_INTERVAL := 1.0
const RETURN_TIMEOUT := 25.0
const HOME_ARRIVE_DIST := 0.5
const WINDUP_LOCK_FRACTION := 0.4 ## facing stops tracking the target for the last 40% of the windup
const WINDUP_TINT := Color(1.0, 0.22, 0.0)
const DEATH_TIME := 0.9
const MELEE_SHOVE := 0.35         ## mild outward nudge on every melee hit

# --- Awareness (docs/design/monster-awareness.md, step 1) -------------------------------------
const CONE_COS := 0.5             ## the front cone is 120 degrees wide
const CONE_EXTRA := 6.0           ## ... and sees this much farther than aggro_range
const SUSPECT_CONFIRM := 1.5      ## seconds of seeing a hero (in total) before a "?" becomes a fight
const SUSPECT_FORGET := 6.0       ## nothing seen or heard for this long: calm down
const SUSPECT_TURN := 0.5         ## it turns first and only then edges toward the point
const SUSPECT_SPEED := 0.5
const ALERT_TIME := 20.0
const ALERT_SPEED := 0.8
const ALERT_SIGHT := 4.0          ## ALERT / SEARCH sight: all round aggro_range + this ...
const ALERT_CONE := 8.0           ## ... and the front cone aggro_range + this
const SEARCH_TIME := 5.0
const SEARCH_TURN := 1.7          ## a look around this often while searching
const ARRIVE_DIST := 1.2
const SHOUT_RADIUS := 10.0        ## a hit wakes every resting monster this close (to ALERT), walls or not
const SHOUT_EVERY := 2.0
const LOOK_MIN := 4.0
const LOOK_MAX := 9.0
const LOOK_SPREAD_DEG := 70.0
const NOISE_MEMORY := 30.0        ## look-arounds may turn toward a sound heard this recently
const LIFE_RANGE := 28.0          ## idle life only within this of a hero (CPU, and bandwidth: still monsters are free)
const STUCK_GIVE_UP := 3          ## an ALERT walk that got stuck this many times searches where it is
# Step 2 (the goblin's fireworks alarm, monster-awareness.md Option 4): after an alarm a monster stays "on edge".
const EDGE_CONE := 2.0            ## on edge: the front cone sees this much farther ...
const EDGE_CONFIRM := 1.0         ## ... and a "?" confirms after this long instead of SUSPECT_CONFIRM
## A pecked monster chases the chicken (the Chicken spell) this long, over its hero target; every peck restarts it. It goes
## back to the crew when the time is up or the chicken dies.
const TAUNT_TIME := 4.0

# --- Tunables (kinds set these in _init) --------------------------------------------
var kind := "monster"
var can_climb := true
var aggro_range := 8.0
var alert_radius := 5.0           ## pack-mates within this wake up when we aggro
var leash_range := 18.0           ## max distance from home before giving up
var attack_start_range := 1.5     ## center-to-center distance at which a windup may start
var attack_reach := 1.4           ## melee reach used at strike time (target radius is added)
var attack_arc_deg := 120.0
var attack_damage := 10.0
var attack_windup := 0.35
var attack_cooldown := 1.1
var stop_distance := 1.0          ## chasers stop moving this close
var bar_height := 1.8
var bar_width := 0.9
var walk_bob := 0.05              ## visual bounce amplitude while walking
var walk_freq := 9.0
var windup_scale := 0.12          ## visual swell at full windup (primitive bodies)
var model_windup_scale := 0.06    ## the same for a faceted model (its own windup pose does the rest)
var employee_chance := 0.3        ## contracts: odds per retarget roll of going for a closer Employee (0 = never)

# --- State ----------------------------------------------------------------------------
var state: int = State.IDLE
var target: Actor = null
var home := Vector3.ZERO
## How many attacks it has struck (the other screens play a swing when it moves on: NetWorldCodec, M3).
var strikes := 0

var _home_set := false
var _scan_t := 0.0
var _retarget_t := 0.0
var _next_attack_time := 0.0
var _windup_left := 0.0
var _windup_total := 0.1
var _telegraph := 0.0             ## 0..1 windup progress (visual)
var _strike_t := 0.0              ## 1 -> 0 right after a strike (visual)
var _return_t := 0.0

# Awareness (host AI working state)
var spawn_facing := Vector3.ZERO  ## where it looks when at rest (ZERO until set: then its facing at the first tick)
var _look_t := 0.0
var _state_t := 0.0               ## seconds in the current awareness state
var _aware_t := 0.0               ## SUSPICIOUS: since the last sight or sound; ALERT / SEARCH: time left
var _seen_t := 0.0                ## SUSPICIOUS: seconds a hero has been seen in total
var _point := Vector3.ZERO        ## SUSPICIOUS / ALERT: what it turns and walks to
var _noise_at := -INF
var _noise_pos := Vector3.ZERO
var _shout_at := -INF
var _speed_k := 1.0               ## walking speed factor for _nav_to (patrols, suspicion, alerts)
var _stuck_n := 0
var _room := ""                   ## its home room's tag ("" = none: no idle life)
var _life_ok := false             ## a hero within LIFE_RANGE at the last scan
var _suspect_at := -1.0           ## combat log: when the current "?" began
var _first_hit_at := -1.0         ## combat log: when the crew first hit it
var busy_until := -INF            ## step 2: a restless activity holds it in place until then (a brute picked a fight with it)
var edge_until := -INF            ## step 2: on edge after a fireworks alarm (wider cone, quicker "?")
var _taunt_by: Actor = null       ## the chicken that pecked it (Chicken spell), chased over any hero until _taunt_until
var _taunt_until := -INF

# Navigation
var _path: Array[Vector2i] = []
var _path_i := 1
var _path_goal := Vector2i(1 << 30, 1 << 30)
var _path_age := 0.0
var _repath_t := 0.0
var _prog_t := 0.0
var _prog_pos := Vector3.ZERO
var _nudge_t := 0.0
var _nudge_dir := Vector3.ZERO
var _last_nav_frame := -100

# Visuals
var model: MonsterModel = null    ## faceted body (null when use_proto_visuals or an unknown kind)
var _visual: Node3D = null
var _bar: MeshInstance3D = null
var _bar_mat: ShaderMaterial = null
var _flash_t := 0.0
var _tint_key := -1.0
var _mats: Array = []             ## [StandardMaterial3D, base emission Color, base emission on, base energy]
var _prev_pos := Vector3.ZERO
var _walk_phase := 0.0
var _bob := 0.0
## A puppet (M4): GameWorld.time this screen last resolved one of this monster's strikes from the wind-up event (so the
## strike count arriving in the snapshot does not play the swing's effect twice).
var _net_struck_at := -INF

const BAR_SHADER_PATH := "res://scripts/monsters/hp_bar.gdshader"
const MODEL_BAR_GAP := 0.25       ## HP bar floats this far above the model's ui_height

## True: spawn the old primitive bodies instead of the faceted models (tests, dev flag).
static var use_proto_visuals := false


func _init() -> void:
	team = GameWorld.TEAM_MONSTERS
	display_name = "Monster"


func _ready() -> void:
	super._ready()
	add_to_group("monsters")
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	if model == null and not use_proto_visuals:
		model = MonsterModels.make(kind)
	if model != null:
		_visual.add_child(model)
		bar_height = model.ui_height + MODEL_BAR_GAP
		windup_scale = model_windup_scale
	else:
		_build_visual(_visual)
	damaged.connect(_on_damaged)
	# Stagger timers so a pack never scans/paths on the same frame.
	_scan_t = GameWorld.rng.randf() * SCAN_INTERVAL
	_repath_t = GameWorld.rng.randf() * REPATH_MAX
	_retarget_t = GameWorld.rng.randf() * RETARGET_INTERVAL
	_look_t = GameWorld.rng.randf_range(LOOK_MIN, LOOK_MAX)
	_prev_pos = global_position


## Who may write each var (see Net); Actor's come from super(). Monster AI runs on the host only,
## so its working state is PRIVATE; what other screens draw or react to (state, target, the
## attack windup) is OWNER.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		# Stats the kind's _init sets at spawn.
		"kind": Net.SPAWN, "can_climb": Net.SPAWN, "aggro_range": Net.SPAWN,
		"alert_radius": Net.SPAWN, "leash_range": Net.SPAWN, "attack_start_range": Net.SPAWN,
		"attack_reach": Net.SPAWN, "attack_arc_deg": Net.SPAWN, "attack_damage": Net.SPAWN,
		"attack_windup": Net.SPAWN, "attack_cooldown": Net.SPAWN, "stop_distance": Net.SPAWN,
		"employee_chance": Net.SPAWN,
		# Look tuning; _ready rewrites bar_height and windup_scale from the model.
		"bar_height": Net.LOCAL, "bar_width": Net.LOCAL, "walk_bob": Net.LOCAL,
		"walk_freq": Net.LOCAL, "windup_scale": Net.LOCAL, "model_windup_scale": Net.LOCAL,
		"state": Net.OWNER,
		"target": Net.OWNER,            # will travel as an entity id; the victim's machine needs to know who is being hit
		"strikes": Net.OWNER,           # the swing on the other screens (M3)
		"home": Net.PRIVATE, "_home_set": Net.PRIVATE,
		# Attack windup: players see a swing coming, so the telegraph is OWNER.
		"_windup_total": Net.OWNER, "_windup_left": Net.OWNER, "_telegraph": Net.OWNER,
		# AI working state.
		"_scan_t": Net.PRIVATE, "_retarget_t": Net.PRIVATE, "_next_attack_time": Net.PRIVATE,
		"_return_t": Net.PRIVATE,
		"spawn_facing": Net.PRIVATE, "_look_t": Net.PRIVATE, "_state_t": Net.PRIVATE, "_aware_t": Net.PRIVATE,
		"_seen_t": Net.PRIVATE, "_point": Net.PRIVATE, "_noise_at": Net.PRIVATE, "_noise_pos": Net.PRIVATE,
		"_shout_at": Net.PRIVATE, "_speed_k": Net.PRIVATE, "_stuck_n": Net.PRIVATE, "_room": Net.PRIVATE,
		"_life_ok": Net.PRIVATE, "_suspect_at": Net.PRIVATE, "_first_hit_at": Net.PRIVATE,
		"busy_until": Net.PRIVATE, "edge_until": Net.PRIVATE,
		"_taunt_by": Net.PRIVATE, "_taunt_until": Net.PRIVATE,   # (who it chases rides `target`, in world.windup)
		"_path": Net.PRIVATE, "_path_i": Net.PRIVATE, "_path_goal": Net.PRIVATE,
		"_path_age": Net.PRIVATE, "_repath_t": Net.PRIVATE, "_prog_t": Net.PRIVATE,
		"_prog_pos": Net.PRIVATE, "_nudge_t": Net.PRIVATE, "_nudge_dir": Net.PRIVATE,
		"_last_nav_frame": Net.PRIVATE,
		# Presentation: models, bars, materials, animation phases.
		"model": Net.LOCAL, "_visual": Net.LOCAL, "_bar": Net.LOCAL, "_bar_mat": Net.LOCAL,
		"_mats": Net.LOCAL, "_flash_t": Net.LOCAL, "_tint_key": Net.LOCAL,
		"_strike_t": Net.LOCAL, "_prev_pos": Net.LOCAL, "_walk_phase": Net.LOCAL, "_bob": Net.LOCAL,
		"_net_struck_at": Net.LOCAL,
	})
	return f


## Override: build the look from primitives. Use _mat/_box/_sphere/_cyl/_cone.
func _build_visual(_root: Node3D) -> void:
	pass


# --- Public helpers -------------------------------------------------------------------

## Wake up and go for `t` (also alerts nearby pack-mates).
func aggro(t: Actor) -> void:
	if dead or t == null or not is_instance_valid(t) or t.dead:
		return
	if not is_passive():
		return
	_end_suspicion(true)
	_enter_chase(t)
	_alert_pack(t)


## Not fighting: idle, suspicious, alert, searching or walking home (a hit or a sighting can still start a fight).
func is_passive() -> bool:
	return state == State.IDLE or state == State.RETURN or state == State.SUSPICIOUS or state == State.ALERT or state == State.SEARCH


## Frozen: aggro_range 0 (tests, --idle-monsters). Sees nothing, hears nothing, never shouts, has no idle life.
func is_frozen() -> bool:
	return aggro_range <= 0.0


## A sound at `pos` (MonsterSenses.noise): turn SUSPICIOUS toward it. True if it reacted.
func hear(pos: Vector3) -> bool:
	if dead or is_frozen():
		return false
	_noise_at = GameWorld.time
	_noise_pos = pos
	match state:
		State.IDLE, State.RETURN, State.SEARCH:
			_suspect(pos)
			return true
		State.SUSPICIOUS:
			_point = pos
			_aware_t = 0.0
			return true
	return false


## The shout of a monster that was hit: walk to `pos` (where the attacker stood) on ALERT. True if it reacted.
func alert(pos: Vector3) -> bool:
	if dead or is_frozen() or not is_passive():
		return false
	_end_suspicion(false)
	state = State.ALERT
	_point = pos
	_aware_t = ALERT_TIME
	_state_t = 0.0
	_stuck_n = 0
	_clear_path()
	return true


## On edge after a fireworks alarm (MonsterSenses.alarm): the front cone sees EDGE_CONE farther and a "?" confirms in
## EDGE_CONFIRM s.
func is_on_edge() -> bool:
	return GameWorld.time < edge_until


func _edge_cone() -> float:
	return EDGE_CONE if is_on_edge() else 0.0


## Spawn facing (MonsterSenses.face_spawn): look this way now and whenever it is back home.
func set_spawn_facing(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	spawn_facing = dir.normalized()
	facing = spawn_facing
	if _visual != null:
		_visual.rotation.y = atan2(-facing.x, -facing.z)


## True while the monster has a target (chasing or winding up an attack).
func is_aggro() -> bool:
	return state == State.CHASE or state == State.ATTACK


func is_hp_bar_visible() -> bool:
	return _bar != null and _bar.visible


## Living heroes, cached once per physics frame so 40 monsters don't each rescan the tree.
## (Cached in GameWorld metadata rather than static vars: keeps script teardown simple.)
func heroes() -> Array[Actor]:
	var f := Engine.get_physics_frames()
	if GameWorld.get_meta("monster_heroes_frame", -1) != f:
		GameWorld.set_meta("monster_heroes_frame", f)
		GameWorld.set_meta("monster_heroes", GameWorld.team_actors(GameWorld.TEAM_HEROES))
	return GameWorld.get_meta("monster_heroes")


# --- Main loop ----------------------------------------------------------------------------

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
	if is_helpless():
		# Shoved or staggered: no steering, no attacks (and the leash does not tick).
		_update_visual(delta)
		return
	match state:
		State.IDLE:
			_tick_idle(delta)
		State.CHASE:
			_tick_chase(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.RETURN:
			_tick_return(delta)
		State.SUSPICIOUS:
			_tick_suspicious(delta)
		State.ALERT:
			_tick_alert(delta)
		State.SEARCH:
			_tick_search(delta)
	_update_visual(delta)


func _tick_idle(delta: float) -> void:
	if is_frozen():
		return   # stays put and silent
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_INTERVAL
		var h := _nearest_hero(aggro_range, true)
		if h != null:
			aggro(h)
			return
		h = _cone_hero(aggro_range + CONE_EXTRA + _edge_cone())
		if h != null:
			_suspect(h.global_position, true)
			return
		_life_ok = _room != "" and _hero_within(LIFE_RANGE)
	if GameWorld.time < busy_until:
		return   # held by a restless activity (a brute's square-off): it stands, no look-arounds
	if _life_ok and _idle_life(delta):
		return
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = GameWorld.rng.randf_range(LOOK_MIN, LOOK_MAX)
		look_around()


## Override: what an idle monster near the crew does this frame (only with a home room and a hero within LIFE_RANGE).
## True = it is busy (moving), so it skips its look-around. Default: nothing.
func _idle_life(_delta: float) -> bool:
	return false


## Turn to a new heading: its spawn facing +/- 70 degrees (`spread`), or toward a recent sound. Never a heading with a
## wall within 2 hexes ahead; if every try is blocked it keeps its facing.
func look_around(spread: float = LOOK_SPREAD_DEG) -> void:
	var base := spawn_facing if spawn_facing != Vector3.ZERO else facing
	var tries: Array[Vector3] = []
	if GameWorld.time - _noise_at < NOISE_MEMORY and GameWorld.rng.randf() < 0.5:
		var to := _noise_pos - global_position
		to.y = 0.0
		if to.length() > 0.3:
			tries.append(to.normalized())
	for _i in 4:
		tries.append(base.rotated(Vector3.UP, deg_to_rad(GameWorld.rng.randf_range(-spread, spread))))
	tries.append(base)
	for d in tries:
		if not MonsterSenses.wall_ahead(self, d):
			facing = d.normalized()
			return
	var sweep := MonsterSenses.clear_heading(self, base, base)   # every roll was blocked: the nearest open heading
	if not MonsterSenses.wall_ahead(self, sweep):
		facing = sweep.normalized()


# --- Awareness ------------------------------------------------------------------------------

func _tick_suspicious(delta: float) -> void:
	_state_t += delta
	_aware_t += delta
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_INTERVAL
		var h := _nearest_hero(aggro_range, true)
		if h != null:
			aggro(h)
			return
		h = _cone_hero(aggro_range + CONE_EXTRA + _edge_cone())
		if h != null:
			_seen_t += SCAN_INTERVAL
			_point = h.global_position
			_aware_t = 0.0
			if _seen_t >= (EDGE_CONFIRM if is_on_edge() else SUSPECT_CONFIRM) - 0.001:
				aggro(h)
				return
	if _aware_t >= SUSPECT_FORGET:
		_end_suspicion(false)
		_calm()
		return
	var d := GameWorld.flat_distance(global_position, _point)
	if _state_t < SUSPECT_TURN or d <= ARRIVE_DIST:
		face_point(_point)
		_prog_t = 0.0
		return
	_speed_k = SUSPECT_SPEED
	_nav_to(_point, delta)
	_speed_k = 1.0


func _tick_alert(delta: float) -> void:
	_state_t += delta
	_aware_t -= delta
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_INTERVAL
		var h := _wide_sight()
		if h != null:
			aggro(h)
			return
	var far := GameWorld.flat_distance(global_position, home) > leash_range
	if _aware_t <= 0.0 or far or _stuck_n >= STUCK_GIVE_UP or GameWorld.flat_distance(global_position, _point) <= ARRIVE_DIST:
		_begin_search()
		return
	_speed_k = ALERT_SPEED
	_nav_to(_point, delta)
	_speed_k = 1.0


func _tick_search(delta: float) -> void:
	_state_t += delta
	_aware_t -= delta
	_scan_t -= delta
	_prog_t = 0.0
	if _scan_t <= 0.0:
		_scan_t = SCAN_INTERVAL
		var h := _wide_sight()
		if h != null:
			aggro(h)
			return
	if _aware_t <= 0.0:
		_begin_return()
		return
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = SEARCH_TURN
		look_around(110.0)


## Turn SUSPICIOUS toward `pos` (a hero seen in the outer cone: `seen`, or a sound).
func _suspect(pos: Vector3, seen: bool = false) -> void:
	if state != State.SUSPICIOUS:
		_suspect_at = GameWorld.time
	state = State.SUSPICIOUS
	_point = pos
	_seen_t = 0.0
	_aware_t = 0.0
	_state_t = 0.0
	_scan_t = SCAN_INTERVAL
	_clear_path()
	if seen:
		face_point(pos)


## The "?" is over (it fought, or calmed down): the combat log's "?" -> "!" time.
func _end_suspicion(fought: bool) -> void:
	if state == State.SUSPICIOUS and _suspect_at >= 0.0:
		CombatLog.suspect_ended(self, GameWorld.time - _suspect_at, fought)
	_suspect_at = -1.0


## Nothing came of it: back to rest (home first if it wandered off).
func _calm() -> void:
	if GameWorld.flat_distance(global_position, home) > HOME_ARRIVE_DIST * 3.0:
		_begin_return()
		return
	state = State.IDLE
	_look_t = GameWorld.rng.randf_range(LOOK_MIN, LOOK_MAX)


func _begin_search() -> void:
	state = State.SEARCH
	target = null
	_aware_t = SEARCH_TIME
	_state_t = 0.0
	_look_t = 0.0
	_clear_path()


func _clear_path() -> void:
	_path.clear()
	_path_goal = Vector2i(1 << 30, 1 << 30)
	_repath_t = 0.0


## ALERT / SEARCH sight: all round out to aggro + 4, the front cone out to aggro + 8 (line of sight either way).
func _wide_sight() -> Actor:
	var h := _nearest_hero(aggro_range + ALERT_SIGHT, true)
	return h if h != null else _cone_hero(aggro_range + ALERT_CONE)


## The nearest living hero inside the front cone within `max_range`, in line of sight. Cheap order: distance, the cone,
## then the line of sight.
func _cone_hero(max_range: float) -> Actor:
	if is_frozen():
		return null
	var best: Actor = null
	var best_d := max_range
	var map := GameWorld.map
	var fwd := Vector3(facing.x, 0.0, facing.z).normalized()
	for h in heroes():
		if not is_instance_valid(h) or h.dead:
			continue
		var to := h.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > best_d or d < 0.001:
			continue
		if fwd.dot(to / d) < CONE_COS:
			continue
		if map != null and not map.line_of_sight(Combat.chest(self), Combat.chest(h)):
			continue
		best = h
		best_d = d
	return best


func _hero_within(r: float) -> bool:
	for h in heroes():
		if is_instance_valid(h) and not h.dead and GameWorld.flat_distance(global_position, h.global_position) <= r:
			return true
	return false


## The shout: every resting monster within SHOUT_RADIUS (flat, through walls) walks to `pos` on ALERT.
func _shout(pos: Vector3) -> void:
	var r2 := SHOUT_RADIUS * SHOUT_RADIUS
	for n in get_tree().get_nodes_in_group("monsters"):   # (duck-typed: see _alert_pack)
		if n == self or n.dead or not Net.simulates(n):
			continue
		var d: Vector3 = n.global_position - global_position
		d.y = 0.0
		if d.length_squared() <= r2:
			n.alert(pos)


func _tick_chase(delta: float) -> void:
	if not _validate_target(delta):
		return
	var tp := target_point()
	var dist := GameWorld.flat_distance(global_position, tp)
	face_point(tp)
	if _try_start_attack(dist):
		return
	_chase_move(delta, dist)


## Where to aim at the target: where it stands, or for another player's hero (online, on the host) where its newest
## snapshot says it is now (Net.lead_point, M3a), so monsters press every player alike.
func target_point() -> Vector3:
	return Net.lead_point(target) if target != null else global_position


## Default melee start: in range, off cooldown, and able to actually hit.
func _try_start_attack(dist: float) -> bool:
	if dist > attack_start_range or GameWorld.time < _next_attack_time:
		return false
	if not _can_strike_target():
		return false
	_begin_windup(attack_windup)
	return true


func _can_strike_target() -> bool:
	if absf(target.global_position.y - global_position.y) > 2.1 * Hex.LEVEL_HEIGHT:
		return false
	var map := GameWorld.map
	return map == null or map.line_of_sight(Combat.chest(self), Combat.chest(target))


## Default: path to the target and stop at stop_distance.
func _chase_move(delta: float, dist: float) -> void:
	if dist > stop_distance:
		_nav_to(target_point(), delta)
	else:
		_prog_t = 0.0


func _tick_attack(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		_end_windup()
		state = State.CHASE
		windup_dropped.emit()
		return
	_windup_left -= delta
	if _windup_left > _windup_total * WINDUP_LOCK_FRACTION:
		face_point(target_point())
	_telegraph = clampf(1.0 - _windup_left / _windup_total, 0.0, 1.0)
	_prog_t = 0.0
	if _windup_left <= 0.0:
		var neutral_hp := target.hp if target.team == GameWorld.TEAM_NEUTRAL else -1.0
		_end_windup()
		_strike()
		_strike_neutral(neutral_hp)
		strikes += 1
		_next_attack_time = GameWorld.time + scaled_cooldown(attack_cooldown)
		_strike_t = 1.0
		if model != null:
			model.attack_swing()
		if state == State.ATTACK:
			state = State.CHASE


func _tick_return(delta: float) -> void:
	_return_t += delta
	var d := GameWorld.flat_distance(global_position, home)
	if d <= HOME_ARRIVE_DIST or _return_t > RETURN_TIMEOUT:
		if _return_t > RETURN_TIMEOUT:
			home = global_position
		state = State.IDLE
		target = null
		hp = max_hp
		_update_bar()
		if spawn_facing != Vector3.ZERO:
			facing = spawn_facing
		_look_t = GameWorld.rng.randf_range(LOOK_MIN, LOOK_MAX)
		_on_home()
		return
	_nav_to(home, delta)


## Hook: the monster got home and is at rest again (kinds restart their idle life).
func _on_home() -> void:
	pass


## Override: deliver the attack. Default is a melee cone toward `facing`.
func _strike() -> void:
	Combat.melee_arc(self, facing, attack_reach, attack_arc_deg, attack_damage, MELEE_SHOVE)


func _begin_windup(duration: float) -> void:
	state = State.ATTACK
	_windup_total = maxf(duration, 0.01)
	_windup_left = _windup_total
	_telegraph = 0.0
	_on_windup_begin()
	windup_begun.emit(_windup_total)


func _end_windup() -> void:
	_telegraph = 0.0
	_on_windup_end()


## Hooks for kinds (ground ring decal, bow draw...).
func _on_windup_begin() -> void:
	pass


func _on_windup_end() -> void:
	pass


# --- Targeting ------------------------------------------------------------------------------

func _nearest_hero(max_range: float, need_los: bool) -> Actor:
	var best: Actor = null
	var best_d := max_range
	var map := GameWorld.map
	for h in heroes():
		if not is_instance_valid(h) or h.dead:
			continue
		var d := GameWorld.flat_distance(global_position, h.global_position)
		if d > best_d:
			continue
		if need_los and map != null and not map.line_of_sight(Combat.chest(self), Combat.chest(h)):
			continue
		best = h
		best_d = d
	return best


func _target_alive() -> bool:
	return target != null and is_instance_valid(target) and not target.dead


func _enter_chase(t: Actor) -> void:
	target = t
	state = State.CHASE
	_path.clear()
	_path_goal = Vector2i(1 << 30, 1 << 30)
	_repath_t = GameWorld.rng.randf() * 0.2
	_retarget_t = RETARGET_INTERVAL


func _alert_pack(t: Actor) -> void:
	var r2 := alert_radius * alert_radius
	# Group "monsters" only holds Monsters; duck-typed on purpose (a self-typed cast in here
	# triggered intermittent exit crashes in Godot 4.7 for any script that references Monster).
	for n in get_tree().get_nodes_in_group("monsters"):
		if n == self or n.dead or not n.is_passive() or n.state == State.RETURN:
			continue
		var d: Vector3 = n.global_position - global_position
		d.y = 0.0
		if d.length_squared() <= r2:
			n._end_suspicion(true)
			n._enter_chase(t)


## Keeps `target` valid: retargets, leashes, gives up. Returns false if the state changed.
func _validate_target(delta: float) -> bool:
	if _taunted():
		if target != _taunt_by:
			target = _taunt_by
			_clear_path()
		if GameWorld.flat_distance(global_position, home) > leash_range:
			_taunt_by = null
			_begin_return()
			return false
		return true   # (no retarget roll while a chicken has it: not a closer hero, not an employee)
	if _taunt_by != null:
		# The chicken is dead or the time is up: back to the crew (or home, with nobody near).
		var was := _taunt_by
		_taunt_by = null
		if target == was:
			target = _nearest_hero(aggro_range * 1.5, false)
	if not _target_alive():
		var t := _nearest_hero(aggro_range * 1.5, false)
		if t == null:
			_begin_return()
			return false
		target = t
	if GameWorld.flat_distance(global_position, home) > leash_range:
		_begin_return()
		return false
	_retarget_t -= delta
	if _retarget_t <= 0.0:
		_retarget_t = RETARGET_INTERVAL
		if _consider_employee():
			return true
		var cur_d := GameWorld.flat_distance(global_position, target.global_position)
		if cur_d > 3.0:
			var t2 := _nearest_hero(aggro_range * 1.5, false)
			if t2 != null and t2 != target:
				if GameWorld.flat_distance(global_position, t2.global_position) < cur_d - 2.0:
					target = t2
		if cur_d > aggro_range * 2.5:
			_begin_search()   # lost it: look around where it is, then home
			return false
	return true


func _begin_return() -> void:
	state = State.RETURN
	target = null
	_return_t = 0.0
	_path.clear()
	_path_goal = Vector2i(1 << 30, 1 << 30)
	_repath_t = 0.0


# --- Chickens (the Chicken spell) --------------------------------------------------------------------
# Chickens are neutral actors in group "chickens" (duck-typed here like the employees: no Chicken reference in this file).

## A chicken pecked us (Actor.peck, on the machine that runs this monster): chase it, over any hero, for TAUNT_TIME (each
## peck restarts it). Only the pecked monster turns: no shout, no pack alert. A peck from a second chicken while the first
## is still alive only keeps the chase going.
func _on_pecked(source: Node) -> void:
	var c := source as Actor
	if dead or c == null or not is_instance_valid(c) or c.dead or state == State.DEAD:
		return
	_taunt_until = GameWorld.time + TAUNT_TIME
	if _taunted() and _taunt_by != c:
		return
	_taunt_by = c
	if is_passive():
		_end_suspicion(true)
		if state == State.RETURN:
			home = global_position   # (as a hit: it fights from here)
		_enter_chase(c)
	elif target != c:
		target = c   # (a wind-up under way turns toward it and lands where it faces)
		_clear_path()


## True while a living chicken has it (the Chicken spell).
func is_taunted() -> bool:
	return _taunted()


func _taunted() -> bool:
	return _taunt_by != null and is_instance_valid(_taunt_by) and not _taunt_by.dead and GameWorld.time < _taunt_until


# --- Employees (contracts) ----------------------------------------------------------------------
# Employees are neutral actors in group "employees" (duck-typed here on purpose: no Employee reference).

## On a retarget roll (`employee_chance`), switch to the nearest employee if it is inside aggro range and
## closer than every living hero; keep it while it stays the closest thing. True = the target was settled
## here and the usual hero retargeting is skipped.
func _consider_employee() -> bool:
	if employee_chance <= 0.0:
		return false
	var hero_d := INF
	for h in heroes():
		if is_instance_valid(h) and not h.dead:
			hero_d = minf(hero_d, GameWorld.flat_distance(global_position, h.global_position))
	if target != null and target.team == GameWorld.TEAM_NEUTRAL:
		var cur_d := GameWorld.flat_distance(global_position, target.global_position)
		return _target_alive() and target.is_in_group("employees") and cur_d < hero_d
	if GameWorld.rng.randf() >= employee_chance:
		return false
	var best: Actor = null
	var best_d := minf(aggro_range, hero_d)
	for n in get_tree().get_nodes_in_group("employees"):
		var e := n as Actor
		if e == null or e.dead:
			continue
		var d := GameWorld.flat_distance(global_position, e.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return false
	target = best
	_path.clear()
	_path_goal = Vector2i(1 << 30, 1 << 30)
	return true


## The strike hits heroes only (other_team), so when the target is an employee deliver the blow to it
## directly: melee kinds need it inside reach, ranged kinds (attack_start_range > 4) need a clear shot. A chicken target
## (the Chicken spell) is in every melee swing's reach already (GameWorld.hittable_in_radius) and in an arrow's path: it is
## given the blow here only when the kind's own strike did not reach it (`before_hp`, its HP before the strike: the brute's
## slam is for heroes only), and only by a melee kind (an arrow is on its way).
func _strike_neutral(before_hp: float) -> void:
	if not _target_alive() or target.team != GameWorld.TEAM_NEUTRAL:
		return
	if target.is_in_group("chickens"):
		if attack_start_range > 4.0 or target.hp < before_hp - 0.001:
			return
	elif not target.is_in_group("employees"):
		return
	if absf(target.global_position.y - global_position.y) > 2.1 * Hex.LEVEL_HEIGHT:
		return
	var d := GameWorld.flat_distance(global_position, target.global_position)
	if attack_start_range > 4.0:
		if not _can_strike_target():
			return
	elif d > maxf(attack_reach, attack_start_range) + target.radius:
		return
	var away := target.global_position - global_position
	away.y = 0.0
	target.apply_damage(attack_damage, self)
	if attack_start_range <= 4.0 and not target.dead:
		target.shove(away, MELEE_SHOVE, self)


# --- Navigation ---------------------------------------------------------------------------

## Is the single step between adjacent cells allowed for this monster?
func _step_ok(a: Vector2i, b: Vector2i) -> bool:
	var map := GameWorld.map
	if map == null:
		return true
	var mv := map.cell_transition(a, b)
	return mv == HexMap.Move.OK or (mv == HexMap.Move.CLIMB and can_climb)


## Path toward a world point; steers directly when in the same/adjacent cell.
## Returns true if the monster moved this frame.
func _nav_to(goal: Vector3, delta: float) -> bool:
	var map := GameWorld.map
	if map == null:
		return _steer_to(goal, delta)

	# No-progress detection (only counts while navigation is being asked for continuously).
	var frame := Engine.get_physics_frames()
	if frame - _last_nav_frame > 2:
		_prog_t = 0.0
		_prog_pos = global_position
	_last_nav_frame = frame
	_prog_t += delta
	if _prog_t >= 1.0:
		if GameWorld.flat_distance(global_position, _prog_pos) < 0.3:
			_on_stuck()
		_prog_t = 0.0
		_prog_pos = global_position
	if _nudge_t > 0.0:
		_nudge_t -= delta
		return move(_nudge_dir, delta)

	var here := current_cell()
	var goal_cell := Hex.from_world(goal)
	_path_age += delta
	if here == goal_cell or (Hex.distance(here, goal_cell) == 1 and _step_ok(here, goal_cell)):
		_path.clear()
		_path_goal = goal_cell
		return _steer_to(goal, delta)

	_repath_t -= delta
	if _repath_t <= 0.0:
		_repath_t = GameWorld.rng.randf_range(REPATH_MIN, REPATH_MAX)
		var max_age := 1.5 if not _path.is_empty() else 2.5
		if goal_cell != _path_goal or _path_age > max_age or _path.find(here) < 0:
			_path = map.find_path(here, goal_cell, can_climb, PATH_MAX_NODES)
			_path_goal = goal_cell
			_path_i = 1
			_path_age = 0.0

	if _path.size() < 2:
		return _steer_to(goal, delta)   # unreachable (or trivial): push straight at it
	var idx := _path.find(here)
	if idx >= 0:
		_path_i = idx + 1
	if _path_i >= _path.size():
		return _steer_to(goal, delta)
	var wp_cell := _path[_path_i]
	var wp := goal if wp_cell == goal_cell else Hex.to_world(wp_cell)
	if wp_cell != goal_cell and GameWorld.flat_distance(global_position, wp) < 0.3:
		_path_i += 1
		if _path_i < _path.size():
			wp_cell = _path[_path_i]
			wp = goal if wp_cell == goal_cell else Hex.to_world(wp_cell)
	return _steer_to(wp, delta)


func _steer_to(pos: Vector3, delta: float) -> bool:
	var d := pos - global_position
	d.y = 0.0
	var l := d.length()
	if l < 0.05:
		return false
	var scale_f := minf(_speed_k, l / maxf(effective_speed() * delta, 0.0001))   # never overshoot the point
	return move(d / l * scale_f, delta)


func _on_stuck() -> void:
	_stuck_n += 1
	_repath_t = 0.0
	_path_age = 99.0
	var side := 1.0 if GameWorld.rng.randf() < 0.5 else -1.0
	_nudge_dir = Vector3(-facing.z, 0.0, facing.x) * side
	_nudge_t = 0.35


## Monsters that cannot climb refuse CLIMB moves (so heroes can escape onto +2 ledges).
func move(dir: Vector3, delta: float) -> bool:
	if is_shoved() or is_rooted():
		return false
	if not can_climb and not dead:
		var d := dir
		d.y = 0.0
		if d.length() > 0.001:
			if d.length() > 1.0:
				d = d.normalized()
			var map := GameWorld.map
			if map != null:
				var spd := effective_speed()
				var step := d * spd * delta
				var from := global_position
				var chosen := Vector3.ZERO
				for attempt in [step, Vector3(step.x, 0, 0), Vector3(0, 0, step.z)]:
					var a: Vector3 = map.clip_move(from, from + attempt, radius) - from   # walls: slide along the face
					a.y = 0.0
					if a.length() < 0.0001:
						if attempt == step:
							break   # pressed into a wall: no per-axis drift (as Actor.move)
						continue
					var probe: Vector3 = from + a + a.normalized() * radius * 0.5
					if map.wall_at(probe):
						probe = from + a   # (as Actor.move: the wall is clip_move's, judge the height where the body goes)
					if map.movement_check(from, probe) == HexMap.Move.OK:
						chosen = a
						break
				if chosen == Vector3.ZERO:
					climbing = false
					facing = d.normalized()
					return false
				var moved := super.move(chosen / maxf(spd * delta, 0.0001), delta)
				facing = d.normalized()
				return moved
	return super.move(dir, delta)


# --- Shove hooks -------------------------------------------------------------------------------

## A shove or stagger cancels a wind-up (the attack never lands).
func _on_interrupted() -> void:
	if state == State.ATTACK:
		_end_windup()
		state = State.CHASE
		windup_dropped.emit()
	_nudge_t = 0.0
	_prog_t = 0.0


## Being shoved away is not leashing: re-home where the monster lands (so it neither walks
## back and heals to full, nor tries to path up a ledge it was thrown off).
func _on_shove_ended() -> void:
	if state != State.RETURN:
		home = global_position
	_prog_pos = global_position
	_prog_t = 0.0
	_path.clear()
	_path_goal = Vector2i(1 << 30, 1 << 30)
	_repath_t = 0.0


# --- Damage / death ---------------------------------------------------------------------------

func _on_damaged(_amount: float, source: Node) -> void:
	_flash_t = FLASH_TIME
	_update_bar()
	var a := source as Actor
	if a == null or a.team == team or a.dead:
		return
	if _first_hit_at < 0.0 and a.team == GameWorld.TEAM_HEROES:
		_first_hit_at = GameWorld.time
		CombatLog.first_hit(self, a, state_name())
	if is_passive():
		if state == State.RETURN:
			home = global_position   # shot on the way home: it fights from here (it neither walks off nor heals)
		aggro(a)
	# The shout: the room hears a fight (to ALERT, toward where the attacker stands). Frozen monsters stay silent.
	if not is_frozen() and GameWorld.time >= _shout_at:
		_shout_at = GameWorld.time + SHOUT_EVERY
		_shout(a.global_position)


## The state's name (the combat log).
func state_name() -> String:
	return str(State.keys()[state]).to_lower() if state >= 0 and state < State.size() else str(state)


func _on_death() -> void:
	var was := state_name()
	state = State.DEAD
	remove_from_group("monsters")
	if Net.owns(self):
		SpellComponents.drop_for(self)   # material components, per the drop table (the owner rolls them: a client is told)
		CombatLog.kill(self, was, GameWorld.time - _first_hit_at if _first_hit_at >= 0.0 else -1.0)
		if not is_frozen():
			MonsterSenses.noise(global_position, MonsterSenses.NOISE_DEATH, "death")   # the neighbours hear it fall
	_end_windup()
	if model != null:
		model.set_downed(true)
	if _bar != null:
		_bar.visible = false
	for e in _mats:
		var em: StandardMaterial3D = e[0]
		em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_apply_tint(Color.WHITE, 0.0)
	var side := 1.0 if GameWorld.fx_rng.randf() < 0.5 else -1.0   # topple side is cosmetic
	var tw := create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.set_parallel(true)
	tw.tween_property(_visual, "rotation:x", -PI * 0.5 * side, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_visual, "position:y", -0.2, DEATH_TIME)
	tw.tween_method(_set_fade, 1.0, 0.0, DEATH_TIME * 0.55).set_delay(DEATH_TIME * 0.45)
	tw.chain().tween_callback(queue_free)


func _set_fade(a: float) -> void:
	if model != null:
		model.set_fade(a)
		return
	for e in _mats:
		var m: StandardMaterial3D = e[0]
		var c: Color = m.albedo_color
		c.a = a
		m.albedo_color = c


# --- HP bar ---------------------------------------------------------------------------------

func _ensure_bar() -> void:
	if _bar != null:
		return
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = load(BAR_SHADER_PATH)
	_bar_mat.render_priority = 10
	var quad := QuadMesh.new()
	quad.size = Vector2(bar_width, 0.1)
	_bar = MeshInstance3D.new()
	_bar.name = "HpBar"
	_bar.mesh = quad
	_bar.material_override = _bar_mat
	_bar.position = Vector3(0.0, bar_height, 0.0)
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bar)


func _update_bar() -> void:
	if hp >= max_hp - 0.001:
		if _bar != null:
			_bar.visible = false
		return
	_ensure_bar()
	_bar.visible = not dead
	_bar_mat.set_shader_parameter("fill", clampf(hp / max_hp, 0.0, 1.0))


# --- Visuals --------------------------------------------------------------------------------

func _update_visual(delta: float) -> void:
	var yaw := atan2(-facing.x, -facing.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, yaw, clampf(14.0 * delta, 0.0, 1.0))
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
	if _strike_t > 0.0:
		_strike_t = maxf(0.0, _strike_t - delta * 6.0)

	var moved := (global_position - _prev_pos).length_squared() > 0.000001
	_prev_pos = global_position
	if moved:
		_walk_phase += delta * walk_freq
	_bob = lerpf(_bob, absf(sin(_walk_phase)) * walk_bob if moved else 0.0, clampf(12.0 * delta, 0.0, 1.0))
	_visual.position.y = _bob
	var s := 1.0 + windup_scale * _telegraph
	_visual.scale = Vector3(s, s, s)

	# Tint: white flash on hit beats the orange windup pulse.
	var key := 0.0
	var col := WINDUP_TINT
	if _flash_t > 0.0:
		col = Color.WHITE
		key = 0.9 * (_flash_t / FLASH_TIME)
	elif _telegraph > 0.0:
		key = (0.25 + 0.4 * _telegraph) * (0.75 + 0.25 * sin(GameWorld.time * 32.0))
	if absf(key - _tint_key) > 0.002:
		_tint_key = key
		_apply_tint(col, key)
	if model != null:
		model.windup(_telegraph)
	_pose(delta, moved)


# --- Puppet (M3): on a client the host's monster is SHOWN, not simulated ------------------------------------

## Show the host's state (NetWorldCodec.write_monster) and play what changed the way the host's own monster played
## it: an HP drop flashes and updates the bar, a wind-up starts and ends (the brute's ring), a new strike swings.
func net_show(new_facing: Vector3, is_climbing: bool, new_hp: float, new_state: int, telegraph: float, strike_count: int) -> void:
	facing = new_facing
	climbing = is_climbing
	if absf(new_hp - hp) > 0.05:
		if new_hp < hp:
			_flash_t = FLASH_TIME
		hp = new_hp
		_update_bar()
	if new_state != state:
		var was := state
		state = new_state
		if state == State.ATTACK:
			_windup_total = maxf(attack_windup, 0.01)
			_on_windup_begin()
		elif was == State.ATTACK:
			_end_windup()
	var tel := telegraph if state == State.ATTACK or state == State.IDLE else 0.0
	if state == State.IDLE:
		# An idle wind-up (step 2: an archer's practice draw, a brute's slam in a restless fight): its look only.
		if tel > 0.0 and _telegraph <= 0.0:
			_on_windup_begin()
		elif tel <= 0.0 and _telegraph > 0.0:
			_on_windup_end()
	_telegraph = tel
	if strike_count != strikes:
		strikes = strike_count
		_strike_t = 1.0
		if model != null:
			model.attack_swing()
		if GameWorld.time - _net_struck_at > 0.4:
			_on_strike_visual()   # (unless this screen just resolved the strike itself: it already played it)


## A puppet (M4): the host's wind-up has reached its strike on THIS screen's clock, so this machine resolves the strike
## against its own hero (the victim decides, rule 1). `victim` is the host's target (an archer aims at it). _strike runs
## the kind's own blow (a cleave, the brute's slam, an arrow); Combat applies it only to what this machine resolves, so
## here that is this player's hero and nothing else (the host decided everyone else at its own strike).
func net_strike(victim: Actor) -> void:
	if dead:
		return
	target = victim
	_net_struck_at = GameWorld.time
	_strike()


## A puppet (M4): this machine's player hit it (the hit is on its way to the host): flash now rather than a round trip later.
func net_flash() -> void:
	_flash_t = FLASH_TIME


## A puppet's look each frame (on the host the physics process does it).
func net_tick(delta: float) -> void:
	if not dead:
		_update_visual(delta)


## Override: what a strike looks like on a screen that only shows this monster (no damage: the host decides that).
func _on_strike_visual() -> void:
	pass


## Override: animate limbs. Uses _telegraph (windup 0..1) and _strike_t (1 -> 0 after the hit).
func _pose(_delta: float, _moving: bool) -> void:
	pass


func _apply_tint(color: Color, k: float) -> void:
	if model != null:
		model.set_tint(color, k)
		return
	for e in _mats:
		var m: StandardMaterial3D = e[0]
		var base_em: Color = e[1]
		var base_on: bool = e[2]
		var base_energy: float = e[3]
		if k <= 0.001:
			m.emission_enabled = base_on
			m.emission = base_em
			m.emission_energy_multiplier = base_energy
		else:
			var base: Color = base_em if base_on else Color.BLACK
			m.emission_enabled = true
			m.emission = base.lerp(color, minf(k, 1.0))
			m.emission_energy_multiplier = maxf(base_energy, 1.0)


## A per-monster material (tint/fade operate on all of them). glow > 0 makes it emissive.
func _mat(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	_mats.append([m, m.emission, glow > 0.0, maxf(glow, 1.0)])
	return m


func _place(mi: MeshInstance3D, parent: Node3D, pos: Vector3, m: Material, rot_deg: Vector3) -> MeshInstance3D:
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return _place(mi, parent, pos, m, rot_deg)


func _sphere(parent: Node3D, r: float, pos: Vector3, m: Material, squash: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = squash
	return _place(mi, parent, pos, m, Vector3.ZERO)


func _cyl(parent: Node3D, r_top: float, r_bottom: float, h: float, pos: Vector3, m: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_top
	mesh.bottom_radius = r_bottom
	mesh.height = h
	mesh.radial_segments = 8
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return _place(mi, parent, pos, m, rot_deg)


func _cone(parent: Node3D, r: float, h: float, pos: Vector3, m: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return _cyl(parent, 0.0, r, h, pos, m, rot_deg)


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n
