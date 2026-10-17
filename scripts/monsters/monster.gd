class_name Monster
extends Actor
## Base class for every monster. A small state machine on top of Actor:
##
##   IDLE   -> a hero is within aggro_range AND in line of sight -> CHASE
##   CHASE  -> path (A*) toward the target; start a windup when in attack range
##   ATTACK -> telegraphed windup (no movement), then the strike, back to CHASE
##   RETURN -> dragged too far from home (or lost the target): walk home, heal, IDLE
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

enum State { IDLE, CHASE, ATTACK, RETURN, DEAD }

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

var _home_set := false
var _scan_t := 0.0
var _retarget_t := 0.0
var _next_attack_time := 0.0
var _windup_left := 0.0
var _windup_total := 0.1
var _telegraph := 0.0             ## 0..1 windup progress (visual)
var _strike_t := 0.0              ## 1 -> 0 right after a strike (visual)
var _return_t := 0.0

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
		"home": Net.PRIVATE, "_home_set": Net.PRIVATE,
		# Attack windup: players see a swing coming, so the telegraph is OWNER.
		"_windup_total": Net.OWNER, "_windup_left": Net.OWNER, "_telegraph": Net.OWNER,
		# AI working state.
		"_scan_t": Net.PRIVATE, "_retarget_t": Net.PRIVATE, "_next_attack_time": Net.PRIVATE,
		"_return_t": Net.PRIVATE,
		"_path": Net.PRIVATE, "_path_i": Net.PRIVATE, "_path_goal": Net.PRIVATE,
		"_path_age": Net.PRIVATE, "_repath_t": Net.PRIVATE, "_prog_t": Net.PRIVATE,
		"_prog_pos": Net.PRIVATE, "_nudge_t": Net.PRIVATE, "_nudge_dir": Net.PRIVATE,
		"_last_nav_frame": Net.PRIVATE,
		# Presentation: models, bars, materials, animation phases.
		"model": Net.LOCAL, "_visual": Net.LOCAL, "_bar": Net.LOCAL, "_bar_mat": Net.LOCAL,
		"_mats": Net.LOCAL, "_flash_t": Net.LOCAL, "_tint_key": Net.LOCAL,
		"_strike_t": Net.LOCAL, "_prev_pos": Net.LOCAL, "_walk_phase": Net.LOCAL, "_bob": Net.LOCAL,
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
	if state != State.IDLE and state != State.RETURN:
		return
	_enter_chase(t)
	_alert_pack(t)


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
	_update_visual(delta)


func _tick_idle(delta: float) -> void:
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = SCAN_INTERVAL
	var h := _nearest_hero(aggro_range, true)
	if h != null:
		aggro(h)


func _tick_chase(delta: float) -> void:
	if not _validate_target(delta):
		return
	var dist := GameWorld.flat_distance(global_position, target.global_position)
	face_point(target.global_position)
	if _try_start_attack(dist):
		return
	_chase_move(delta, dist)


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
		_nav_to(target.global_position, delta)
	else:
		_prog_t = 0.0


func _tick_attack(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		_end_windup()
		state = State.CHASE
		return
	_windup_left -= delta
	if _windup_left > _windup_total * WINDUP_LOCK_FRACTION:
		face_point(target.global_position)
	_telegraph = clampf(1.0 - _windup_left / _windup_total, 0.0, 1.0)
	_prog_t = 0.0
	if _windup_left <= 0.0:
		_end_windup()
		_strike()
		_strike_employee()
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
		return
	_nav_to(home, delta)


## Override: deliver the attack. Default is a melee cone toward `facing`.
func _strike() -> void:
	Combat.melee_arc(self, facing, attack_reach, attack_arc_deg, attack_damage, MELEE_SHOVE)


func _begin_windup(duration: float) -> void:
	state = State.ATTACK
	_windup_total = maxf(duration, 0.01)
	_windup_left = _windup_total
	_telegraph = 0.0
	_on_windup_begin()


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
		if n == self or n.dead or n.state != State.IDLE:
			continue
		var d: Vector3 = n.global_position - global_position
		d.y = 0.0
		if d.length_squared() <= r2:
			n._enter_chase(t)


## Keeps `target` valid: retargets, leashes, gives up. Returns false if the state changed.
func _validate_target(delta: float) -> bool:
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
			_begin_return()
			return false
	return true


func _begin_return() -> void:
	state = State.RETURN
	target = null
	_return_t = 0.0
	_path.clear()
	_path_goal = Vector2i(1 << 30, 1 << 30)
	_repath_t = 0.0


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
## directly: melee kinds need it inside reach, ranged kinds (attack_start_range > 4) need a clear shot.
func _strike_employee() -> void:
	if not _target_alive() or target.team != GameWorld.TEAM_NEUTRAL or not target.is_in_group("employees"):
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
	var scale_f := minf(1.0, l / maxf(effective_speed() * delta, 0.0001))   # never overshoot the point
	return move(d / l * scale_f, delta)


func _on_stuck() -> void:
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
	if state == State.IDLE:
		var a := source as Actor
		if a != null and a.team != team and not a.dead:
			aggro(a)


func _on_death() -> void:
	state = State.DEAD
	remove_from_group("monsters")
	SpellComponents.drop_for(self)   # material components, per the drop table
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
