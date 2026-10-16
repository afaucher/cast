class_name AllyBrain
extends Node
## AI for an allied hero (add as a child of the Hero). Follows the leader
## loosely, engages monsters near the leader, never wanders off, and uses
## HexMap.find_path when the straight way is blocked. One ally prefers melee
## (closes in), the other ranged (kites at a distance, melees when cornered).
## Allies do not cast spells in the POC.

const FOLLOW_FAR := 3.6        ## start walking back when farther than this from the leader
const FORMATION_DIST := 2.2    ## where in the leader's surroundings to settle
const ENGAGE_RANGE := 9.0      ## only fight monsters this close to the leader
const LEASH := 8.0             ## never chase farther than this from the leader
const MELEE_STOP := 1.25       ## melee ally closes to this distance
const RANGED_MIN := 3.5
const RANGED_MAX := 7.0
const REPATH_INTERVAL := 0.6
const WAYPOINT_REACHED := 0.35
const PROBE_STEP := 0.4

@export var prefers_ranged := false
@export var formation_angle := 2.4   ## radians; where around the leader this ally likes to stand

var hero: Hero
var leader: Hero

var _following := false
var _path: Array[Vector2i] = []
var _path_goal := Vector2i(1 << 20, 1 << 20)
var _path_idx := 0
var _repath_at := 0.0


func _ready() -> void:
	hero = get_parent() as Hero


func _physics_process(delta: float) -> void:
	if hero == null or hero.dead:
		return
	var foe := _pick_target()
	if foe:
		_fight(foe, delta)
	else:
		_follow(delta)


func _anchor() -> Vector3:
	return leader.global_position if leader and not leader.dead else hero.global_position


## Nearest monster to this ally among those close to the leader, unless we are too far out.
func _pick_target() -> Actor:
	if leader and not leader.dead and GameWorld.flat_distance(hero.global_position, leader.global_position) > LEASH:
		return null
	var anchor := _anchor()
	var best: Actor = null
	var best_d := INF
	for m in GameWorld.team_actors(GameWorld.TEAM_MONSTERS):
		if GameWorld.flat_distance(m.global_position, anchor) > ENGAGE_RANGE:
			continue
		var d := GameWorld.flat_distance(m.global_position, hero.global_position)
		if d < best_d:
			best_d = d
			best = m
	return best


func _fight(foe: Actor, delta: float) -> void:
	var to := foe.global_position - hero.global_position
	to.y = 0.0
	var d := to.length()
	var dir := to.normalized() if d > 0.001 else hero.facing
	if prefers_ranged:
		if d < Hero.MELEE_REACH - 0.2:
			hero.face_point(foe.global_position)
			hero.melee(dir)
		elif d < RANGED_MIN:
			hero.move(-dir, delta)
			hero.face_point(foe.global_position)
			if _has_los(foe):
				hero.shoot(dir)
		elif d <= RANGED_MAX and _has_los(foe):
			hero.face_point(foe.global_position)
			hero.shoot(dir)
		else:
			_move_toward(foe.global_position, delta)
	else:
		if d <= MELEE_STOP + 0.2:
			hero.face_point(foe.global_position)
			hero.melee(dir)
		else:
			_move_toward(foe.global_position, delta)
			if d <= Hero.MELEE_REACH - 0.2:
				hero.melee(dir)


func _follow(delta: float) -> void:
	if leader == null or leader.dead:
		return
	var slot := leader.global_position + Vector3(cos(formation_angle), 0, sin(formation_angle)) * FORMATION_DIST
	var d_leader := GameWorld.flat_distance(hero.global_position, leader.global_position)
	if d_leader > FOLLOW_FAR:
		_following = true
	if _following:
		if GameWorld.flat_distance(hero.global_position, slot) < 0.5 or (d_leader < FORMATION_DIST + 0.3 and GameWorld.flat_distance(hero.global_position, slot) < 1.2):
			_following = false
		else:
			_move_toward(slot, delta)


func _has_los(foe: Actor) -> bool:
	var map: HexMap = GameWorld.map
	return map == null or map.line_of_sight(Combat.chest(hero), Combat.chest(foe))


## Step toward a world point: straight when the way is clear, else along an A* cell path.
func _move_toward(goal: Vector3, delta: float) -> void:
	var to := goal - hero.global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	if _direct_clear(hero.global_position, goal):
		hero.move(to.normalized(), delta)
		return
	var map: HexMap = GameWorld.map
	var goal_cell := Hex.from_world(goal)
	if GameWorld.time >= _repath_at or goal_cell != _path_goal:
		_path = map.find_path(hero.current_cell(), goal_cell, true)
		_path_goal = goal_cell
		_path_idx = 1
		_repath_at = GameWorld.time + REPATH_INTERVAL
	if _path.size() < 2:
		hero.move(to.normalized(), delta)   # no path known: just push toward it
		return
	while _path_idx < _path.size() and GameWorld.flat_distance(hero.global_position, Hex.to_world(_path[_path_idx])) < WAYPOINT_REACHED:
		_path_idx += 1
	var waypoint := goal if _path_idx >= _path.size() else Hex.to_world(_path[_path_idx])
	var step := waypoint - hero.global_position
	step.y = 0.0
	hero.move(step.normalized(), delta)


## True if walking a straight line is free of ledges, walls and holes.
func _direct_clear(from: Vector3, to: Vector3) -> bool:
	var map: HexMap = GameWorld.map
	if map == null:
		return true
	var flat := Vector3(to.x - from.x, 0, to.z - from.z)
	var n := maxi(1, int(flat.length() / PROBE_STEP))
	var prev := from
	for i in range(1, n + 1):
		var p := from + flat * (float(i) / n)
		p.y = from.y
		if map.movement_check(prev, p) != HexMap.Move.OK:
			return false
		prev = p
	return true
