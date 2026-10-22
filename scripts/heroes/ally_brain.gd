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
##
## NO PACING (user playtest, 2026-10-21: "Rebar on the host is vibrating violently"): the formation rules must never argue.
## A hero that does not make room itself (a person's: the leader, or in a crew another player's hero, a puppet on the host)
## standing near the slot used to start a loop: settled at the slot, personal space walked the ally out past FOLLOW_SLACK,
## the slot called it straight back into the crowd, and again, about four 180-degree turns a second for as long as that
## player stood there. So the slot is taken on a cell outside such a hero's personal space (`_snap_walkable` roomy), and
## personal space never steps the ally out past the slack. Likewise beside a walking leader: an ally that has stepped out
## of the lane waits there rather than cutting back across it toward its slot (out and back in, every other frame, was
## the same shake), and it keeps to the side it chose while it steps out.
##
## RESTRAINT (combat-variety-research.md A1, combat-proposals.md 1.0 / 1.4; the default, with no order): the ally follows
## and supports, it never leads. It only joins a fight already started (a monster ALERT, or chasing / attacking anyone but
## another monster; a hellgate once the crew has dented it), REACT_MIN..MAX seconds after it first sees that monster in
## the fight (rolled per monster from a generator seeded by the floor), goes first for what is attacking its leader, then
## what is attacking a teammate (itself included), then the nearest, and needs line of sight unless the monster is hitting
## it. Rebar's bowl peels a monster off a teammate (within PEEL_RANGE of the hero it attacks); it never opens a fight.
## `restraint` false is the old eager AI (the nearest monster near the leader, at once), kept so tests can measure both.
##
## THE NEW MONSTERS (combat-proposals.md §2 / §3, "As built"): a priority target (the Water Boy healer,
## Monster.is_priority_target) ranks like a monster on a teammate, and under "attack" it counts PRIORITY_BONUS nearer: the
## AI goes for the healer a little sooner, still only once it is in the fight. A foe whose shield faces this ally (the
## Pavise, Combat.shielded) is not swung or shot at from the front: the ally steps round toward its flank first.
##
## ORDERS (voice, VoiceOrders; combat-proposals.md 1.0): one at a time, `give_order(kind, by, point)` on the host:
##   "go"      walk to `point` (a walkable spot near where the speaker aimed), then hold there until a new order: fight
##             what is in the fight within HOLD_RANGE of the spot (on the way there, only what attacks the ally itself)
##   "attack"  fight freely: anything within ATTACK_RANGE of the ally, no reaction delay, the bowl opens fights again,
##             until nothing near it has fought for ATTACK_QUIET; then it follows the speaker (no order)
##   "follow"  clears the order; the speaker becomes the leader (until then it is seat 1's hero)

const HEX_STEP := Hex.INNER * 2.0   ## world distance between two adjacent hex centers
const FORMATION_HEX_MIN := 2.5      ## formation distance range, in hexes from the leader
const FORMATION_HEX_MAX := 3.5
const FOLLOW_SLACK := 1.6      ## start walking back to the slot when this far from it (world units) ...
const SLOT_REACHED := 0.6      ## ... and stop when this close
const PERSONAL_SPACE := 2.4    ## an idle ally backs off from a hero closer than this (world units) ...
const SPACE_SLACK_MARGIN := 0.15   ## ... but stays this far inside FOLLOW_SLACK of its slot while it does (NO PACING)
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
# Restraint (see the header).
const REACT_MIN := 0.6         ## seconds from first seeing a monster in the fight to engaging it ...
const REACT_MAX := 1.0         ## ... rolled per monster
const PEEL_RANGE := 3.0        ## the bowl only goes at a monster this close to the teammate it is attacking
# Orders (see the header).
const HOLD_RANGE := 6.0        ## "go", arrived: fight what is in the fight this close to the spot ...
const HOLD_LEASH := 8.0        ## ... and never farther than this from it
const GO_ARRIVED := 0.7        ## "go": this close to the spot counts as there
const ATTACK_RANGE := 9.0      ## "attack": anything within this of the ally ...
const ATTACK_LEASH := 14.0     ## ... while it is no farther than this from the speaker
const ATTACK_END_RANGE := 10.0 ## "attack" ends once no monster within this is in the fight ...
const ATTACK_QUIET := 1.0      ## ... for this long
const PRIORITY_BONUS := 3.0    ## "attack": a priority target (the Water Boy) counts this much nearer
const FLANK_TIME := 0.5        ## a shielded foe: step round its flank this long before trying again
const ARRIVE_MIN := 0.35       ## a movement feel's arrival slowdown never walks slower than this share of full speed
## What the ally says when it takes an order, by kit (VoiceOrders shows it over its head on every screen).
const BARKS := {
	"rebar": {"go": "Moving.", "attack": "Finally.", "follow": "Right behind you."},
	"gasket": {"go": "On my way!", "attack": "Hammer time!", "follow": "With you!"},
	"wick": {"go": "Going!", "attack": "Loosing!", "follow": "Behind you!"},
	"": {"go": "On it.", "attack": "On it.", "follow": "On you."},
}

## True: AI allies keep the client's property out of their swings, spins, bowls and shots (tests measure it off too).
static var prop_care := true
## True: the restraint baseline (see the header). False: the old eager AI, for measuring the difference.
static var restraint := true

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
## The order it is under: "" (none), "go" or "attack" ("follow" clears it). See the header.
var order := ""
var order_point := Vector3.INF    ## "go": the spot
var order_by: Hero = null         ## who gave the order
var _arrived := false             ## "go": reached the spot once (from then on it holds there)
var _quiet_since := -1.0          ## "attack": nothing near has been fighting since then (-1: something is)
var _foe: Actor = null            ## the monster it is fighting (kept while it stays a fair pick)
var _react_at: Dictionary = {}    ## monster instance id -> when this ally may engage it (the reaction delay)
var _rng := RandomNumberGenerator.new()
var _clear_side := 0.0            ## stepping out of the leader's lane to this side (+1 / -1 across its heading), 0 when not
var _roomy_cell := Vector2i(1 << 20, 1 << 20)   ## the formation slot's cell last frame (kept while a crowd moves; NO PACING)


func _exit_tree() -> void:
	if hero != null and is_instance_valid(hero):
		hero.order_state = ""   # (a person takes the seat: no AI order any more)


func _ready() -> void:
	hero = get_parent() as Hero
	_rng.seed = GameWorld.rng.seed ^ hash(hero.display_name if hero != null else name)


## Who may write each var (see Net). The host runs every AllyBrain; all of it is its working state (an order reaches the
## host as a request, NetOrders; what the other screens see of it is the bark event and the hero's own stream).
func net_fields() -> Dictionary:
	return {
		"prefers_ranged": Net.SPAWN, "formation_angle": Net.SPAWN, "formation_dist": Net.SPAWN,
		"hero": Net.LOCAL,        # the parent node
		"leader": Net.PRIVATE,    # AI target pick; the host alone steers the ally
		"_following": Net.PRIVATE, "_heading": Net.PRIVATE, "_leader_prev": Net.PRIVATE,
		"_leader_walking_until": Net.PRIVATE,
		"_path": Net.PRIVATE, "_path_goal": Net.PRIVATE, "_path_idx": Net.PRIVATE, "_repath_at": Net.PRIVATE,
		"_sidestep_until": Net.PRIVATE, "_sidestep_dir": Net.PRIVATE, "held_for_props": Net.PRIVATE,
		"order": Net.PRIVATE, "order_point": Net.PRIVATE, "order_by": Net.PRIVATE, "_arrived": Net.PRIVATE,
		"_quiet_since": Net.PRIVATE, "_foe": Net.PRIVATE, "_react_at": Net.PRIVATE,
		"_rng": Net.PRIVATE,      # the reaction delays: a generator seeded from the floor, rolled on the host only
		"_clear_side": Net.PRIVATE, "_roomy_cell": Net.PRIVATE,
	}


func _physics_process(delta: float) -> void:
	_track_leader()
	if hero != null and hero.order_state != order_state():
		hero.order_state = order_state()   # (the party HUD's chip; the host sends the change to the clients, NetOrders)
	if hero == null or hero.dead or hero.is_helpless():
		return
	hero.pace = 1.0   # (a profile's catch-up sets it again below while the ally is far behind: _follow)
	match order:
		"go":
			_tick_go(delta)
		"attack":
			_tick_attack(delta)
		_:
			var foe := _pick_target()
			if foe:
				_fight(foe, delta)
			else:
				_follow(delta)


# --- Orders ---------------------------------------------------------------------------------------

## Take a voice order (VoiceOrders, on the host): "go" (to `point`), "attack" or "follow". `by` is the speaker's hero.
## Returns what the ally says, or "" when it can't take it (down).
func give_order(kind: String, by: Hero, point: Vector3 = Vector3.INF) -> String:
	if hero == null or hero.dead:
		return ""
	_foe = null
	_arrived = false
	_quiet_since = -1.0
	_path.clear()
	_repath_at = 0.0
	match kind:
		"follow":
			order = ""
			if by != null:
				leader = by
		"go":
			if point == Vector3.INF:
				return ""
			order = "go"
			order_point = _snap_point(point)
			hero.face_point(order_point)
		"attack":
			order = "attack"
			if by != null:
				leader = by   # (it follows the speaker when the fight is over)
		_:
			return ""
	order_by = by
	var lines: Dictionary = BARKS.get(hero.kit_id, BARKS[""])
	return str(lines.get(kind, ""))


## What the ally is doing under orders, for the party HUD (read on the machine that runs this brain: the host, or solo):
## "follow" (no order), "go" (on its way to the spot), "hold" (there, holding it) or "attack".
func order_state() -> String:
	match order:
		"go":
			return "hold" if _arrived else "go"
		"attack":
			return "attack"
	return "follow"


## "go": walk to the spot, then hold it. On the way only what attacks the ally itself is fought; once there, whatever is
## in the fight near the spot.
func _tick_go(delta: float) -> void:
	var d := GameWorld.flat_distance(hero.global_position, order_point)
	if not _arrived and d <= GO_ARRIVED:
		_arrived = true
	var foe: Actor = null
	if _arrived:
		if d <= HOLD_LEASH:
			foe = _pick_restrained(order_point, HOLD_RANGE)
	else:
		foe = _pick_restrained(order_point, 0.0)   # (range 0: self-defence only)
	if foe != null:
		_fight(foe, delta)
	elif d > SLOT_REACHED:
		_move_toward(order_point, delta)


## "attack": fight anything near, no restraint; when nothing near has been fighting for ATTACK_QUIET, follow the speaker.
func _tick_attack(delta: float) -> void:
	var foe: Actor = null
	if leader == null or leader.dead or GameWorld.flat_distance(hero.global_position, leader.global_position) <= ATTACK_LEASH:
		foe = _pick_free(hero.global_position, ATTACK_RANGE)
	if foe != null:
		_quiet_since = -1.0
		_fight(foe, delta)
		return
	var fighting := false
	for m in GameWorld.team_actors(GameWorld.TEAM_MONSTERS):
		if _in_fight(m) and GameWorld.flat_distance(m.global_position, hero.global_position) <= ATTACK_END_RANGE:
			fighting = true
			break
	if fighting:
		_quiet_since = -1.0
	elif _quiet_since < 0.0:
		_quiet_since = GameWorld.time
	elif GameWorld.time - _quiet_since >= ATTACK_QUIET:
		order = ""   # the fight is over: back to following the speaker (the leader since the order)
		_quiet_since = -1.0
	_follow(delta)


## The walkable floor cell nearest `p` (within 3 rings, any level), else `p`.
func _snap_point(p: Vector3) -> Vector3:
	var map: HexMap = GameWorld.map
	if map == null:
		return p
	var c0 := Hex.from_world(p)
	if map.is_walkable_cell(c0):
		var lv0 := map.ground_level(p)
		return Vector3(p.x, p.y if is_nan(lv0) else lv0, p.z)
	var best := Vector2i(1 << 20, 1 << 20)
	var best_d := INF
	for c in Hex.range_cells(c0, 3):
		if not map.is_walkable_cell(c):
			continue
		var d := GameWorld.flat_distance(Hex.to_world(c), p)
		if d < best_d:
			best_d = d
			best = c
	if best_d == INF:
		return p
	var lv := map.ground_level(Hex.to_world(best))
	return Hex.to_world(best, 0.0 if is_nan(lv) else lv)


## Seed the formation's heading before the leader has walked anywhere: the slots trail opposite `dir`. The elevator's
## arrival passes the way INTO the car, so the allies settle out in the room in front of it, not back in the car.
func set_heading(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length() > 0.001:
		_heading = dir.normalized()


func _anchor() -> Vector3:
	return leader.global_position if leader and not leader.dead else hero.global_position


## No order: under the restraint baseline, the best monster already in the fight near the leader (see the header); without
## it (tests), the old eager pick. Nothing while we are too far out.
func _pick_target() -> Actor:
	if leader and not leader.dead and GameWorld.flat_distance(hero.global_position, leader.global_position) > LEASH:
		return null
	if not restraint:
		return _pick_eager(_anchor(), ENGAGE_RANGE)
	return _pick_restrained(_anchor(), ENGAGE_RANGE)


## The old pick (restraint off): the monster nearest this ally among those within `reach` of `anchor`.
func _pick_eager(anchor: Vector3, reach: float) -> Actor:
	var best: Actor = null
	var best_d := INF
	for m in GameWorld.team_actors(GameWorld.TEAM_MONSTERS):
		if GameWorld.flat_distance(m.global_position, anchor) > reach:
			continue
		var d := GameWorld.flat_distance(m.global_position, hero.global_position)
		if d < best_d:
			best_d = d
			best = m
	return best


## "attack": the nearest monster within `reach` of `anchor` that is in the fight or in sight (it opens fights), no delay.
func _pick_free(anchor: Vector3, reach: float) -> Actor:
	if _foe != null and is_instance_valid(_foe) and not _foe.dead \
			and GameWorld.flat_distance(_foe.global_position, anchor) <= reach:
		return _foe
	var best: Actor = null
	var best_d := INF
	for m in GameWorld.team_actors(GameWorld.TEAM_MONSTERS):
		if GameWorld.flat_distance(m.global_position, anchor) > reach:
			continue
		var d := GameWorld.flat_distance(m.global_position, hero.global_position)
		if m is Monster and (m as Monster).is_priority_target():
			d -= PRIORITY_BONUS
		if d < best_d and (_in_fight(m) or _has_los(m)):
			best_d = d
			best = m
	_foe = best
	return best


## The restraint pick (see the header): among the monsters in the fight within `reach` of `anchor` (and any monster attacking
## this ally, wherever it is), those this ally has had time to react to, with line of sight unless it is hitting the ally:
## what attacks the leader, then what attacks a teammate, then the rest, nearest first. The current foe is kept while it
## is still as good a pick as the best.
func _pick_restrained(anchor: Vector3, reach: float) -> Actor:
	var now := GameWorld.time
	var best: Actor = null
	var best_rank := 99
	var best_d := INF
	var keep_rank := 99
	for m in GameWorld.team_actors(GameWorld.TEAM_MONSTERS):
		if not _in_fight(m):
			continue
		var on_me := _target_of(m) == hero
		var d := GameWorld.flat_distance(m.global_position, hero.global_position)
		if not on_me and GameWorld.flat_distance(m.global_position, anchor) > reach:
			continue
		if on_me and d > ENGAGE_RANGE:
			continue
		if not on_me and not _has_los(m):
			continue
		var id := m.get_instance_id()
		if not _react_at.has(id):
			_react_at[id] = now + _rng.randf_range(REACT_MIN, REACT_MAX)
		if now < float(_react_at[id]):
			continue
		var rank := _rank(m)
		if m == _foe:
			keep_rank = rank
		if rank < best_rank or (rank == best_rank and d < best_d):
			best_rank = rank
			best_d = d
			best = m
	if _foe != null and is_instance_valid(_foe) and not _foe.dead and keep_rank <= best_rank:
		best = _foe
	_foe = best
	if _react_at.size() > 64:
		_forget_gone()
	return best


## Already in the fight (the restraint baseline never opens one): a monster on ALERT (its pack heard a fight), or chasing /
## attacking anything but another monster (a restless brute's brawl is not the crew's fight); a hellgate (or any other
## monster-side actor) once the crew has dented it.
func _in_fight(m: Actor) -> bool:
	if m == null or m.dead:
		return false
	var mm := m as Monster
	if mm == null:
		return m.hp < m.max_hp - 0.01
	if mm.state == Monster.State.ALERT:
		return true
	if mm.state == Monster.State.CHASE or mm.state == Monster.State.ATTACK:
		return mm.target == null or not is_instance_valid(mm.target) or mm.target.team != GameWorld.TEAM_MONSTERS
	return false


## Who a monster is going for (null for none, or for a hellgate).
func _target_of(m: Actor) -> Actor:
	var mm := m as Monster
	if mm == null or mm.target == null or not is_instance_valid(mm.target):
		return null
	return mm.target


## 0: it attacks the leader; 1: a teammate (this ally included), or a priority target (the Water Boy); 2: anything else.
func _rank(m: Actor) -> int:
	var t := _target_of(m)
	var floor_rank := 1 if m is Monster and (m as Monster).is_priority_target() else 2
	if t == null:
		return floor_rank
	if t == leader:
		return 0
	return 1 if t.team == hero.team else floor_rank


func _forget_gone() -> void:
	var live := {}
	for m in GameWorld.team_actors(GameWorld.TEAM_MONSTERS):
		live[m.get_instance_id()] = true
	for id: int in _react_at.keys():
		if not live.has(id):
			_react_at.erase(id)


func _fight(foe: Actor, delta: float) -> void:
	if GameWorld.time < _sidestep_until:
		hero.move(_sidestep_dir, delta)   # stepping around the target to a clean angle (a prop was in the way)
		hero.face_point(foe.global_position)
		return
	if _try_secondary(foe):
		return
	if Combat.shielded(foe, hero.global_position, Combat.HIT_MELEE, hero, false):
		_flank(foe)   # (a pavise facing this ally: its front takes nothing)
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
	var turn := maxf(0.0, hero.melee_half_angle() - ARC_SLACK_DEG)
	for k: float in [0.0, turn, -turn]:
		var d := dir.rotated(Vector3.UP, deg_to_rad(k))
		if _area_clear(d):
			hero.face_point(hero.global_position + d)
			hero.melee(d)
			return
	_hold(foe)


## A shot (arrow or bolt) at `foe` `dist` away: only down a lane with no prop before the target.
func _shoot(foe: Actor, dir: Vector3, dist: float) -> void:
	if prop_care and not _lane_clear(dir, dist, 0.3, foe):
		_hold(foe)
		return
	hero.shoot(dir)


## A shield faces this ally: step round toward the foe's flank (the side this ally is already on), a little forward.
func _flank(foe: Actor) -> void:
	var f := Vector3(foe.facing.x, 0.0, foe.facing.z).normalized()
	var side := Vector3(-f.z, 0.0, f.x)
	var rel := hero.global_position - foe.global_position
	rel.y = 0.0
	if side.dot(rel) < 0.0:
		side = -side
	_sidestep_dir = (side - f * 0.35).normalized()
	_sidestep_until = GameWorld.time + FLANK_TIME


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


## No priced prop inside this hero's primary swung along `dir` (Hero.melee_area: the wedge, or grounded_anim's lane).
func _area_clear(dir: Vector3) -> bool:
	var area := hero.melee_area()
	if str(area["shape"]) != "lane":
		return _arc_clear(dir, float(area["reach"]), float(area["arc"]))
	var p0 := hero.global_position
	var a0 := Vector2(p0.x + dir.x * float(area["near"]), p0.z + dir.z * float(area["near"]))
	var a1 := Vector2(p0.x + dir.x * float(area["far"]), p0.z + dir.z * float(area["far"]))
	var end := float(area.get("end_radius", 0.0))   # (a smash's disc round the landing)
	for p in GameWorld.props_in_radius(p0, float(area["far"]) + maxf(float(area["radius"]), end) + PROP_MARGIN):
		var q := Vector2(p.global_position.x, p.global_position.z)
		if Geometry2D.get_closest_point_to_segment(q, a0, a1).distance_to(q) <= float(area["radius"]) + p.radius + PROP_MARGIN:
			return false
		if end > 0.0 and q.distance_to(a1) <= end + p.radius + PROP_MARGIN:
			return false
	return true


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
func _lane_clear(dir: Vector3, length: float, width: float, foe: Actor = null) -> bool:
	var from := Vector2(hero.global_position.x, hero.global_position.z)
	var to := from + Vector2(dir.x, dir.z) * length
	for p in GameWorld.props_in_radius(hero.global_position, length + 2.0):
		if foe != null and p.has_method("is_mount_of") and p.call("is_mount_of", foe) and p.hp > p.max_hp * 0.25:
			continue   # (a shot at an imp gunner passes its shark, unless a stray arrow could land the $12,600 kill)
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


## True when the straight line from a to b (X/Z) crosses the void: a pit, or a lava cave's lava.
static func _gap_between(map: HexMap, a: Vector3, b: Vector3) -> bool:
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var n := maxi(1, int(flat.length() / 0.4))
	for i in range(1, n):
		if is_nan(map.ground_height(a.lerp(b, float(i) / float(n)))):
			return true
	return false


## `p` pulled onto a walkable floor cell near it (same level as the leader give or take one), so a formation
## slot or a side-step never points into a wall. Returns `p` when nothing is better. `roomy` (the formation slot): the
## nearest such cell outside the personal space of every hero that does not make room itself (`_holds_ground`) when there
## is one, so the slot and personal space never pull the ally two ways (NO PACING in the header).
func _snap_walkable(p: Vector3, roomy: bool = false) -> Vector3:
	var map: HexMap = GameWorld.map
	if map == null or leader == null:
		return p
	var base := map.get_cell(leader.current_cell())
	var base_level: int = base.level if base != null else 0
	var crowd: Array[Vector3] = []
	if roomy:
		crowd = _ground_holders()
	var none := Vector2i(1 << 20, 1 << 20)
	var best := none        # the nearest cell
	var best_d := INF
	var best_crowded := false
	var roomy_c := none     # the nearest cell out of the crowd's personal space
	var roomy_d := INF
	var keep_d := INF       # the roomy cell taken last frame, while it still is one
	for c in Hex.range_cells(Hex.from_world(p), 3):
		var cell := map.get_cell(c)
		if cell == null or cell.type != HexMap.Tile.FLOOR or not map.is_walkable_cell(c) or absi(cell.level - base_level) > 1 or Shark.shark_water(c):
			continue
		var w := Hex.to_world(c)
		var d := GameWorld.flat_distance(w, p)
		var crowded := false
		for q in crowd:
			if GameWorld.flat_distance(w, q) < PERSONAL_SPACE:
				crowded = true
				break
		var wanted := d < best_d or (roomy and not crowded and (d < roomy_d or c == _roomy_cell))
		if not wanted or _gap_between(map, leader.global_position, w):
			continue   # (never a slot across a hole from the leader: a lava cave's parallel walkway two hexes over is the same
			# level and three cells away, but the way there is the long way round, and the ally went to it)
		if d < best_d:
			best_d = d
			best = c
			best_crowded = crowded
		if roomy and not crowded:
			if d < roomy_d:
				roomy_d = d
				roomy_c = c
			if c == _roomy_cell:
				keep_d = d
	if best_d == INF:
		return p
	var pick := best
	if roomy and best_crowded and roomy_d < INF:
		# The nearest cell is crowded: the nearest roomy one, or the roomy one it already took while that is still about as
		# near (a hex of slack), so a hero walking past does not flip the slot from one side of them to the other.
		pick = _roomy_cell if keep_d <= roomy_d + HEX_STEP else roomy_c
	if roomy:
		_roomy_cell = pick
	var lv := map.ground_level(Hex.to_world(pick))
	return Hex.to_world(pick, 0.0 if is_nan(lv) else lv)


## Where the heroes that do not make room themselves stand (not this ally): the people's, that is the leader and, in a
## crew, the other players' heroes (puppets on the host). An AI ally steps out of the way on its own.
func _ground_holders() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for h in GameWorld.team_actors(hero.team):
		if h != hero and not h.dead and _holds_ground(h):
			out.append(h.global_position)
	return out


static func _holds_ground(h: Actor) -> bool:
	return h.get_node_or_null("AllyBrain") == null


## True when this ally stands in the lane the leader is walking into.
func _in_leader_path() -> bool:
	return _in_lane(hero.global_position)


## True when `pos` is in the lane the leader is walking into.
func _in_lane(pos: Vector3) -> bool:
	if not _leader_walking():
		return false
	var rel := pos - leader.global_position
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
	if _clear_side != 0.0:
		side = _clear_side   # (the side it already chose: the leader turning a little must not send it back across)
	for s: float in [side, -side]:
		var want: Vector3 = leader.global_position + _heading * along + perp * s * (BLOCK_LANE + 1.0)
		var spot := _snap_walkable(want)
		var off := spot - leader.global_position
		off.y = 0.0
		var off_lane := (off - _heading * off.dot(_heading)).length()
		if off_lane >= BLOCK_LANE * 0.9:
			_clear_side = s
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
	_clear_side = 0.0
	var slot := _snap_walkable(_slot_point(), true)
	var d_slot := GameWorld.flat_distance(hero.global_position, slot)
	if d_slot > FOLLOW_SLACK:
		_following = true
	if _following:
		if d_slot < SLOT_REACHED:
			_following = false
		else:
			var to := slot - hero.global_position
			to.y = 0.0
			to = to.normalized()
			if _in_lane(hero.global_position + to * hero.effective_speed() * delta) or _in_lane(hero.global_position + to * PROBE_STEP):
				return   # just out of the walking leader's lane: wait beside it rather than cut back across it to the slot
			# A movement feel's smoother catch-up (MoveFeel "ally_catchup", grounded): a little faster while far behind a moving
			# leader, and easing into the slot (ally_arrive) instead of stopping dead on it. Nothing with `today`.
			if MoveFeel.num("ally_catchup") > 1.0 and _leader_walking() and d_slot > MoveFeel.num("ally_catchup_dist"):
				hero.pace = MoveFeel.num("ally_catchup")
			_move_toward(slot, delta, MoveFeel.num("ally_arrive"))
			return
	_keep_personal_space(delta, slot)


## Idle and settled: step away from any hero that is crowding us, but never so far from `slot` that the slot calls the
## ally back (that walk back into the crowd and out again was the pacing: NO PACING in the header).
func _keep_personal_space(delta: float, slot: Vector3) -> void:
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
		var next := hero.global_position + away.normalized() * hero.effective_speed() * delta
		if GameWorld.flat_distance(next, slot) <= FOLLOW_SLACK - SPACE_SLACK_MARGIN:
			hero.move(away.normalized(), delta)


func _has_los(foe: Actor) -> bool:
	var map: HexMap = GameWorld.map
	return map == null or map.line_of_sight(Combat.chest(hero), Combat.chest(foe))


## Step toward a world point: straight when the way is clear, else along an A* cell path. `arrive` > 0: inside that many
## units of the goal the walk slows with the distance left (down to ARRIVE_MIN of full speed).
func _move_toward(goal: Vector3, delta: float, arrive: float = 0.0) -> void:
	var to := goal - hero.global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	if _direct_clear(hero.global_position, goal):
		var k := clampf(to.length() / arrive, ARRIVE_MIN, 1.0) if arrive > 0.0 else 1.0
		hero.move(to.normalized() * k, delta)
		return
	var map: HexMap = GameWorld.map
	var goal_cell := Hex.from_world(goal)
	if GameWorld.time >= _repath_at or goal_cell != _path_goal:
		_path = map.find_path(hero.current_cell(), goal_cell, hero.can_climb)
		_path_goal = goal_cell
		_path_idx = 1
		_repath_at = GameWorld.time + REPATH_INTERVAL
	if _path.size() < 2:
		# No path known: push toward it, unless that walks into a drop it can't take (a pit, a lava cave's lava, a crust
		# that melted under the path): then wait where it stands rather than grind against the edge.
		var ahead := hero.global_position + to.normalized() * (hero.radius + 0.6)
		if map.movement_check(hero.global_position, ahead) != HexMap.Move.BLOCKED or map.wall_at(ahead):
			hero.move(to.normalized(), delta)
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
		if restraint and order != "attack" and not _peels(foe):
			return false   # (the bowl peels a monster off a teammate; it never opens a fight)
		var to := foe.global_position - hero.global_position
		to.y = 0.0
		var d := to.length()
		if d >= BOWL_MIN and d <= BOWL_MAX and _has_los(foe) and _bowl_lane_clear(to / d) \
				and (not prop_care or _lane_clear(to / d, Hero.BOWL_RANGE, BowlBoulder.HIT_RADIUS)):   # (it rolls on past the target)
			hero.face_point(foe.global_position)
			return hero.shoot(to / d)
	return false


## A bowl at `foe` would peel it off a teammate: it is attacking another hero and is within PEEL_RANGE of them.
func _peels(foe: Actor) -> bool:
	var t := _target_of(foe)
	return t != null and t != hero and t.team == hero.team and not t.dead \
			and GameWorld.flat_distance(foe.global_position, t.global_position) <= PEEL_RANGE


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
