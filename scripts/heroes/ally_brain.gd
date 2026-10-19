class_name AllyBrain
extends Node
## AI for an allied hero (add as a child of the Hero). Follows the leader
## loosely, engages monsters near the leader, never wanders off, and uses
## HexMap.find_path when the straight way is blocked. One ally prefers melee
## (closes in), the other ranged (kites at a distance, melees when cornered).
## Allies do not cast spells in the POC.
##
## THE CLIENT'S PROPERTY. The crew's swings and every arrow, bolt and boulder hit priced props (user, 2026-10-18), so an
## AI ally is careful where a player may not be (`prop_care`): it only ever targets monsters, picks the side of its arc
## that keeps a prop out of a swing, holds Gasket's spin while a prop is within reach, never bowls or shoots down a lane
## a prop stands in, and otherwise steps around its target to a clean angle (SIDESTEP_TIME at a time) before it attacks.
##
## Formation: each ally settles FORMATION_HEX_MIN..MAX hexes from the leader, trailing behind it to one
## side (formation_angle - PI is the side offset in radians, so two allies are always at distinct angles),
## snapped to real floor so a slot never lands in a wall. Heroes keep PERSONAL_SPACE from each other, and
## an ally standing in the leader's path steps out of the lane (or falls behind it in a one-wide hall)
## instead of blocking. None of this applies while there is something to fight.

const HEX_STEP := Hex.INNER * 2.0   ## world distance between two adjacent hex centers
const FORMATION_HEX_MIN := 2.5      ## formation distance range, in hexes from the leader
const FORMATION_HEX_MAX := 3.5
const FOLLOW_SLACK := 1.6      ## start walking back to the slot when this far from it (world units) ...
const SLOT_REACHED := 0.6      ## ... and stop when this close
const PERSONAL_SPACE := 2.4    ## an idle ally backs off from a hero closer than this (world units)
const BLOCK_AHEAD := 3.4       ## an ally this far ahead of a moving leader, inside the lane, is "in the way"
const BLOCK_LANE := 1.25       ## half-width of the leader's lane
const HEADING_MIN_STEP := 0.012   ## the leader moved at least this far this frame: it is walking
const ENGAGE_RANGE := 9.0      ## only fight monsters this close to the leader
const LEASH := 8.0             ## never chase farther than this from the leader
const MELEE_STOP := 1.25       ## melee ally closes to this distance
const RANGED_MIN := 3.5
const RANGED_MAX := 7.0
const REPATH_INTERVAL := 0.6
const WAYPOINT_REACHED := 0.35
const PROBE_STEP := 0.4
const BOWL_MIN := 3.0          ## Rebar bowls at enemies this far ...
const BOWL_MAX := 9.0          ## ... up to this far
const BOWL_LANE := 1.0         ## skip a throw that would pass this close to another hero
const PROP_MARGIN := 0.3       ## a prop this much beyond a swing's reach / a lane's width still counts as in the way
const ARC_SLACK_DEG := 8.0     ## a swing turned this far short of its half-arc still has the target in it
const SIDESTEP_TIME := 0.45    ## a blocked attack steps around the target for this long before it tries again

## True: AI allies keep the client's property out of their swings, spins, bowls and shots (tests measure it off too).
static var prop_care := true

@export var prefers_ranged := false
@export var formation_angle := 2.4   ## radians; where around the leader this ally likes to stand (PI = straight behind)
@export var formation_dist := FORMATION_HEX_MIN * HEX_STEP   ## world units from the leader where it settles

var hero: Hero
var leader: Hero

var _following := false
var _heading := Vector3.ZERO      ## the leader's smoothed walking direction (flat), ZERO until it has moved
var _leader_prev := Vector3.INF
var _leader_walking_until := -1.0
var _path: Array[Vector2i] = []
var _path_goal := Vector2i(1 << 20, 1 << 20)
var _path_idx := 0
var _repath_at := 0.0
var _sidestep_until := -1.0       ## stepping around the target to a clean angle until then
var _sidestep_dir := Vector3.ZERO
## Measurements (tests): attacks held for a prop in the way.
var held_for_props := 0


func _ready() -> void:
	hero = get_parent() as Hero


## Who may write each var (see Net). The host runs every AllyBrain; all of it is its working state.
func net_fields() -> Dictionary:
	return {
		"prefers_ranged": Net.SPAWN, "formation_angle": Net.SPAWN, "formation_dist": Net.SPAWN,
		"hero": Net.LOCAL,        # the parent node
		"leader": Net.PRIVATE,    # AI target pick; the host alone steers the ally
		"_following": Net.PRIVATE, "_heading": Net.PRIVATE, "_leader_prev": Net.PRIVATE,
		"_leader_walking_until": Net.PRIVATE,
		"_path": Net.PRIVATE, "_path_goal": Net.PRIVATE, "_path_idx": Net.PRIVATE, "_repath_at": Net.PRIVATE,
		"_sidestep_until": Net.PRIVATE, "_sidestep_dir": Net.PRIVATE, "held_for_props": Net.PRIVATE,
	}


func _physics_process(delta: float) -> void:
	_track_leader()
	if hero == null or hero.dead or hero.is_helpless():
		return
	var foe := _pick_target()
	if foe:
		_fight(foe, delta)
	else:
		_follow(delta)


## Seed the formation's heading before the leader has walked anywhere: the slots trail opposite `dir`. The elevator's
## arrival passes the way INTO the car, so the allies settle out in the room in front of it, not back in the car.
func set_heading(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length() > 0.001:
		_heading = dir.normalized()


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
	if GameWorld.time < _sidestep_until:
		hero.move(_sidestep_dir, delta)   # stepping around the target to a clean angle (a prop was in the way)
		hero.face_point(foe.global_position)
		return
	if _try_secondary(foe):
		return
	var to := foe.global_position - hero.global_position
	to.y = 0.0
	var d := to.length()
	var dir := to.normalized() if d > 0.001 else hero.facing
	if prefers_ranged:
		if d < hero.melee_reach - 0.2:
			_swing(foe, dir)
		elif d < RANGED_MIN:
			hero.move(-dir, delta)
			hero.face_point(foe.global_position)
			if _has_los(foe):
				_shoot(foe, dir, d)
		elif d <= RANGED_MAX and _has_los(foe):
			hero.face_point(foe.global_position)
			_shoot(foe, dir, d)
		else:
			_move_toward(foe.global_position, delta)
	else:
		if d <= _melee_stop() + 0.2:
			_swing(foe, dir)
		else:
			_move_toward(foe.global_position, delta)
			if d <= hero.melee_reach - 0.2:
				_swing(foe, dir)


# --- The client's property ---------------------------------------------------------------------

## A melee swing at `foe`: straight at it, or turned to one side of the arc (the target still in it) to keep a priced prop
## out; with no clean side it steps around the target instead.
func _swing(foe: Actor, dir: Vector3) -> void:
	if not prop_care:
		hero.face_point(foe.global_position)
		hero.melee(dir)
		return
	if hero.cooldown_left(Hero.KEY_MELEE) > 0.0:
		hero.face_point(foe.global_position)
		return
	var turn := maxf(0.0, hero.melee_arc * 0.5 - ARC_SLACK_DEG)
	for k: float in [0.0, turn, -turn]:
		var d := dir.rotated(Vector3.UP, deg_to_rad(k))
		if _arc_clear(d, hero.melee_reach, hero.melee_arc):
			hero.face_point(hero.global_position + d)
			hero.melee(d)
			return
	_hold(foe)


## A shot (arrow or bolt) at `foe` `dist` away: only down a lane with no prop before the target.
func _shoot(foe: Actor, dir: Vector3, dist: float) -> void:
	if prop_care and not _lane_clear(dir, dist, 0.3):
		_hold(foe)
		return
	hero.shoot(dir)


## Hold the attack: step around the target, to the side away from the nearest prop in the way.
func _hold(foe: Actor) -> void:
	held_for_props += 1
	var to := foe.global_position - hero.global_position
	to.y = 0.0
	var side := Vector3(-to.z, 0.0, to.x).normalized()
	var near := GameWorld.props_in_radius(hero.global_position, 4.0)
	if not near.is_empty():
		var away := hero.global_position - near[0].global_position
		if side.dot(away) < 0.0:
			side = -side
	_sidestep_dir = side
	_sidestep_until = GameWorld.time + SIDESTEP_TIME


## No priced prop inside a swing of `reach` and `arc_deg` along `dir` (Combat.melee_arc's own test, a little wider).
func _arc_clear(dir: Vector3, reach: float, arc_deg: float) -> bool:
	for p in GameWorld.props_in_radius(hero.global_position, reach + PROP_MARGIN):
		var to := p.global_position - hero.global_position
		to.y = 0.0
		if arc_deg >= 360.0 or to.length() < 0.001:
			return false
		if rad_to_deg(dir.angle_to(to.normalized())) <= arc_deg * 0.5 + ARC_SLACK_DEG:
			return false
	return true


## No priced prop within `width` (plus its radius) of the lane from this hero along `dir` for `length`.
func _lane_clear(dir: Vector3, length: float, width: float) -> bool:
	var from := Vector2(hero.global_position.x, hero.global_position.z)
	var to := from + Vector2(dir.x, dir.z) * length
	for p in GameWorld.props_in_radius(hero.global_position, length + 2.0):
		var q := Vector2(p.global_position.x, p.global_position.z)
		if Geometry2D.get_closest_point_to_segment(q, from, to).distance_to(q) <= width + p.radius + PROP_MARGIN:
			return false
	return true


## How close a melee ally closes in: a little inside its own primary's reach (Rebar's long fist stops
## farther out than Gasket's hammer).
func _melee_stop() -> float:
	return clampf(hero.melee_reach - 0.25, 1.0, MELEE_STOP + 0.35)


## Remember which way the leader is walking (for the formation and the lane check).
func _track_leader() -> void:
	if leader == null or leader.dead:
		_leader_prev = Vector3.INF
		return
	var now := leader.global_position
	if _leader_prev != Vector3.INF:
		var step := now - _leader_prev
		step.y = 0.0
		if step.length() >= HEADING_MIN_STEP:
			var dir := step.normalized()
			_heading = dir if _heading == Vector3.ZERO else _heading.lerp(dir, 0.12).normalized()
			_leader_walking_until = GameWorld.time + 0.35
	_leader_prev = now


func _leader_walking() -> bool:
	return _heading != Vector3.ZERO and GameWorld.time <= _leader_walking_until


## The unsnapped formation point: behind the leader (or at formation_angle until it has walked anywhere).
func _slot_point() -> Vector3:
	var angle := formation_angle
	if _heading != Vector3.ZERO:
		angle = atan2(-_heading.z, -_heading.x) + (formation_angle - PI)
	return leader.global_position + Vector3(cos(angle), 0, sin(angle)) * formation_dist


## `p` pulled onto a walkable floor cell near it (same level as the leader give or take one), so a formation
## slot or a side-step never points into a wall. Returns `p` when nothing is better.
func _snap_walkable(p: Vector3) -> Vector3:
	var map: HexMap = GameWorld.map
	if map == null or leader == null:
		return p
	var base := map.get_cell(leader.current_cell())
	var base_level: int = base.level if base != null else 0
	var cell0 := Hex.from_world(p)
	var best := Vector2i(1 << 20, 1 << 20)
	var best_d := INF
	for c in Hex.range_cells(cell0, 3):
		var cell := map.get_cell(c)
		if cell == null or cell.type != HexMap.Tile.FLOOR or not map.is_walkable_cell(c) or absi(cell.level - base_level) > 1:
			continue
		var d := GameWorld.flat_distance(Hex.to_world(c), p)
		if d < best_d:
			best_d = d
			best = c
	if best_d == INF:
		return p
	var lv := map.ground_level(Hex.to_world(best))
	return Hex.to_world(best, 0.0 if is_nan(lv) else lv)


## True when this ally stands in the lane the leader is walking into.
func _in_leader_path() -> bool:
	if not _leader_walking():
		return false
	var rel := hero.global_position - leader.global_position
	rel.y = 0.0
	var along := rel.dot(_heading)
	if along < -0.2 or along > BLOCK_AHEAD:
		return false
	return (rel - _heading * along).length() < BLOCK_LANE


## Where to go to get out of the lane: the nearest walkable spot beside it, else behind the leader.
func _clear_spot() -> Vector3:
	var rel := hero.global_position - leader.global_position
	rel.y = 0.0
	var along := clampf(rel.dot(_heading), 0.0, BLOCK_AHEAD)
	var perp := Vector3(-_heading.z, 0, _heading.x)
	var lat := rel.dot(perp)
	var side := 1.0 if lat > 0.0 or (lat == 0.0 and formation_angle >= PI) else -1.0
	for s: float in [side, -side]:
		var want: Vector3 = leader.global_position + _heading * along + perp * s * (BLOCK_LANE + 1.0)
		var spot := _snap_walkable(want)
		var off := spot - leader.global_position
		off.y = 0.0
		var off_lane := (off - _heading * off.dot(_heading)).length()
		if off_lane >= BLOCK_LANE * 0.9:
			return spot
	# A one-wide hall: fall behind the leader, slipping through it (heroes do not shove each other while passing).
	hero.pass_through_until = GameWorld.time + 0.4
	return _snap_walkable(leader.global_position - _heading * formation_dist)


func _follow(delta: float) -> void:
	if leader == null or leader.dead:
		return
	if _in_leader_path():
		_following = true
		_move_toward(_clear_spot(), delta)
		return
	var slot := _snap_walkable(_slot_point())
	var d_slot := GameWorld.flat_distance(hero.global_position, slot)
	if d_slot > FOLLOW_SLACK:
		_following = true
	if _following:
		if d_slot < SLOT_REACHED:
			_following = false
		else:
			_move_toward(slot, delta)
			return
	_keep_personal_space(delta)


## Idle and settled: step away from any hero that is crowding us.
func _keep_personal_space(delta: float) -> void:
	var away := Vector3.ZERO
	for h in GameWorld.team_actors(hero.team):
		if h == hero or h.dead:
			continue
		var d := hero.global_position - h.global_position
		d.y = 0.0
		var len := d.length()
		if len < PERSONAL_SPACE:
			away += (d / len if len > 0.001 else Vector3.RIGHT) * (PERSONAL_SPACE - len)
	if away.length() > 0.05:
		hero.move(away.normalized(), delta)


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
		_path = map.find_path(hero.current_cell(), goal_cell, hero.can_climb)
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


## True if walking a straight line is free of ledges, walls and holes (and the elevator's thin sides).
func _direct_clear(from: Vector3, to: Vector3) -> bool:
	var map: HexMap = GameWorld.map
	if map == null:
		return true
	if map.crosses_solid(from, to, hero.radius):
		return false
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


# --- Secondary attacks (bowl / spin) -----------------------------------------------------

## Use the hero's secondary when it makes sense. True if it fired this frame.
##   spin: 2+ enemies within reach, or 1 in reach and the spin is ready.
##   bowl: an enemy 3 to 9 away in line of sight, and no other hero standing in the lane.
func _try_secondary(foe: Actor) -> bool:
	if hero.secondary_kind == "spin":
		var reach := Hero.SPIN_REACH
		var close := GameWorld.actors_in_radius(hero.global_position, reach, GameWorld.TEAM_MONSTERS)
		if close.size() >= 2 or (close.size() == 1 and hero.cooldown_left(Hero.KEY_RANGED) <= 0.0):
			if prop_care and not _arc_clear(hero.facing, reach, 360.0):
				return false   # a prop within the spin: the hammer will do
			return hero.shoot(hero.facing)
	elif hero.secondary_kind == "bowl":
		var to := foe.global_position - hero.global_position
		to.y = 0.0
		var d := to.length()
		if d >= BOWL_MIN and d <= BOWL_MAX and _has_los(foe) and _bowl_lane_clear(to / d) \
				and (not prop_care or _lane_clear(to / d, Hero.BOWL_RANGE, BowlBoulder.HIT_RADIUS)):   # (it rolls on past the target)
			hero.face_point(foe.global_position)
			return hero.shoot(to / d)
	return false


## True when no other living hero stands within BOWL_LANE of the boulder's path.
func _bowl_lane_clear(dir: Vector3) -> bool:
	var origin := hero.global_position
	for h in GameWorld.team_actors(hero.team):
		if h == hero:
			continue
		var rel := h.global_position - origin
		rel.y = 0.0
		var along := rel.dot(dir)
		if along < 0.0 or along > Hero.BOWL_RANGE:
			continue
		if (rel - dir * along).length() < BOWL_LANE:
			return false
	return true
