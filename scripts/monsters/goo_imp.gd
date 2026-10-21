class_name GooImp
extends Monster
## The goo imp (docs/design/goo-imp.md, "As built"): the SEWER's ranged pest, a pink axolotl cousin of the swarmer imp that
## drips with its own bile goo (look-dev's Gloop, GooImpModel). Packs of PACK_MIN-PACK_MAX, the swarmer's HP. It lives only
## in the sewer: MonsterDefs marks it `"habitat": "sewer"` (no "pack" and no "gate"), so a normal floor's packs and the
## hellgates never deal it; MonsterFactory.compose_sewer / spawn_sewer_pack do (the sewer slice's layout 2 stages a pack).
##
## BEHAVIOUR (host). Awareness as every monster (monster.gd). In a fight it HANGS BACK ON DRY GROUND:
##   THE BAND    it throws from KEEP_MIN-THROW_RANGE of its target when it can see it. Closer than FLEE_RANGE it backs
##               away (never into water; cornered, it throws anyway). Farther, or out of sight, it walks toward the target,
##               but while it fights it never steps INTO water (GooImp.move refuses the step), so a pack on a deck across a
##               channel waits at the edge and throws from there
##   THE TELL    THROW_TELL (0.7 s, the monsters' wind-up): its right hand takes the ball back over its head and the ball
##               swells to the size of the one that flies (GooImpModel)
##   THE THROW   a GooBall from its hand on an arc to where the target stands (plus up to SCATTER), about a second in the
##               air, with a landing marker on the floor (GooBall: the hit, the splash in water, the patch on a miss). Then
##               COOLDOWN x 0.8-1.25 (so a pack's throws spread out); its first throw of a fight waits FIRST_MIN-FIRST_MAX
## A shove, a stagger or a daze during the tell calls the throw off (Monster._on_interrupted). It is light (shove_mult 1.5)
## and never goes for an employee (employee_chance 0).
##
## ONLINE: a host-owned monster with no state of its own beyond a monster's. The tell is the monsters' wind-up (world.windup);
## the ball is announced by the host (Net.announce: NetObjects obj.new "goo_ball"), so every screen flies the same ball to
## the same point at the same moment, and a puppet's net_strike throws nothing (the host's ball is on its way). A late
## joiner: a monster's keyframe; balls in flight are skipped, patches are replayed (GooPatch).

const HP := 12.0                 ## the swarmer's toughness (the user: "same toughness")
const SPEED := 3.6
const AGGRO := 10.0
const THROW_RANGE := 9.0
const KEEP_MIN := 5.0            ## it would rather not be closer than this
const FLEE_RANGE := 2.6          ## a hero this close: it backs away
const THROW_TELL := 0.7
const COOLDOWN := 2.6
const COOLDOWN_JITTER_MIN := 0.6   ## 1.6-4.0 s between throws, so a pack never falls into step (user, 2026-10-21:
const COOLDOWN_JITTER_MAX := 1.55  ## "can we jitter their throws a bit?" -> when they throw; was 0.8-1.25)
const FIRST_MIN := 0.2           ## its first throw of a fight: after this much ...
const FIRST_MAX := 2.0           ## ... to this much (a pack does not volley; was 1.4)
const SCATTER := 0.6             ## the landing point: up to this far from where the target stands
const PACK_MIN := 3              ## the user: "3-4 per pack"
const PACK_MAX := 4
const DRY_LOOK := 0.35           ## the step it judges for water: this far ahead of its edge

## Host, tests: balls thrown, and the last one.
var throws := 0
var last_ball: GooBall = null
var _engaged := false
var _held := false               ## the last move was refused at the water's edge


func _init() -> void:
	super._init()
	kind = "goo_imp"
	display_name = "Goo Imp"
	max_hp = HP
	move_speed = SPEED
	radius = 0.26
	shove_mult = 1.5
	aggro_range = AGGRO
	attack_damage = GooBall.DAMAGE
	attack_windup = THROW_TELL
	attack_cooldown = COOLDOWN
	attack_start_range = THROW_RANGE   # (> 4: a ranged kind, Monster._strike_neutral)
	attack_reach = 0.0
	stop_distance = KEEP_MIN
	employee_chance = 0.0
	bar_height = 1.25
	bar_width = 0.55
	walk_bob = 0.1
	walk_freq = 14.0
	windup_scale = 0.2
	model_windup_scale = 0.06


func net_fields() -> Dictionary:
	var f := super()
	f.merge({"throws": Net.PRIVATE, "last_ball": Net.PRIVATE, "_engaged": Net.PRIVATE, "_held": Net.PRIVATE})
	return f


## The primitive fallback body (Monster.use_proto_visuals): a pink imp with a glowing goo ball.
func _build_visual(root: Node3D) -> void:
	var skin := _mat(Color(0.88, 0.52, 0.50))
	var gill := _mat(Color(0.78, 0.22, 0.34))
	var goo := _mat(GooSoups.BILE, 2.5)
	var eye := _mat(Color(1.0, 0.9, 0.2), 3.0)
	_sphere(root, 0.27, Vector3(0.0, 0.32, 0.0), skin)
	_sphere(root, 0.2, Vector3(0.0, 0.62, -0.04), goo)
	for x: float in [-0.22, 0.22]:
		_cone(root, 0.06, 0.2, Vector3(x, 0.62, 0.05), gill, Vector3(0, 0, -70.0 * signf(x)))
	_sphere(root, 0.05, Vector3(-0.09, 0.62, -0.22), eye)
	_sphere(root, 0.05, Vector3(0.09, 0.62, -0.22), eye)
	_sphere(root, 0.12, Vector3(0.18, 0.2, -0.2), goo)


## Where a ball leaves its hand (the throw's start: the same on every screen, it rides in the ball's row).
func hand_point() -> Vector3:
	var f := Vector3(facing.x, 0.0, facing.z)
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	return global_position + Vector3.UP * 1.05 + f * 0.1


# --- Host AI ------------------------------------------------------------------------------------------------------

func _tick_chase(delta: float) -> void:
	if not _validate_target(delta):
		return
	if not _engaged:
		_engaged = true
		_next_attack_time = maxf(_next_attack_time, GameWorld.time + GameWorld.rng.randf_range(FIRST_MIN, FIRST_MAX))
	var tp := target_point()
	var dist := GameWorld.flat_distance(global_position, tp)
	face_point(tp)
	var ready := GameWorld.time >= _next_attack_time
	var sight := can_throw_at(target)
	if dist < FLEE_RANGE:
		if _back_off(delta):
			return
		if ready and sight:
			_begin_windup(attack_windup)   # cornered: it throws anyway
		return
	if is_wet(global_position):
		_nav_to(_dry_spot(tp), delta)   # (shoved or spawned into the water: out onto dry ground first)
		return
	if dist > THROW_RANGE or not sight:
		_held = false
		_nav_to(tp, delta)
		if _held:
			_prog_t = 0.0   # at the water's edge: it waits there (not stuck)
			face_point(tp)
		return
	if ready:
		_begin_windup(attack_windup)
		return
	if dist < KEEP_MIN:
		_back_off(delta)
		return
	_prog_t = 0.0


## A clear lob at `t`: alive, and nothing (a wall) between its chest and the target's.
func can_throw_at(t: Actor) -> bool:
	if t == null or not is_instance_valid(t) or t.dead:
		return false
	var map := GameWorld.map
	return map == null or map.line_of_sight(Combat.chest(self), Combat.chest(t))


## The cooldown after each throw is spread a little (the pack's balls come one by one).
func _tick_attack(delta: float) -> void:
	var before := strikes
	super._tick_attack(delta)
	if strikes != before:
		_next_attack_time = GameWorld.time + scaled_cooldown(attack_cooldown) * GameWorld.rng.randf_range(COOLDOWN_JITTER_MIN, COOLDOWN_JITTER_MAX)


func _on_home() -> void:
	_engaged = false


## Back away from the target along the most open dry direction. False when it could not move.
func _back_off(delta: float) -> bool:
	if not _target_alive():
		return false
	var away := global_position - target.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.001 else -Vector3(facing.x, 0.0, facing.z).normalized()
	var d := _open_dir(away)
	if d == Vector3.ZERO:
		_prog_t = 0.0
		return false
	var moved := move(d, delta)
	facing = -away   # (it keeps its eyes on the hero while it backs off)
	return moved


func _open_dir(away: Vector3) -> Vector3:
	var map := GameWorld.map
	if map == null:
		return away
	var here_lvl := map.ground_level(global_position)
	var best := Vector3.ZERO
	var best_score := -INF
	for ang: float in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 130.0, -130.0]:
		var d := away.rotated(Vector3.UP, deg_to_rad(ang))
		var p1 := global_position + d * 0.8
		if map.movement_check(global_position, p1) != HexMap.Move.OK or is_wet(p1):
			continue
		if map.ground_level(p1) < here_lvl - HexMap.STEP_LEVELS:
			continue   # (never hops off a ledge backing away)
		var score := d.dot(away)
		if map.movement_check(global_position, global_position + d * 1.8) == HexMap.Move.OK and not is_wet(global_position + d * 1.8):
			score += 0.4
		if score > best_score:
			best_score = score
			best = d
	return best


## The nearest dry floor within 4 cells (the far side from `from` breaks ties), or `from` when there is none.
func _dry_spot(from: Vector3) -> Vector3:
	var map := GameWorld.map
	if map == null:
		return from
	var best := from
	var best_d := INF
	for c in Hex.range_cells(current_cell(), 4):
		if not map.is_walkable_cell(c) or map.is_pool_cell(c):
			continue
		var p := Hex.to_world(c, float(map.get_cell(c).level))
		if is_wet(p):
			continue
		var d := GameWorld.flat_distance(p, global_position) - 0.1 * GameWorld.flat_distance(p, from)
		if d < best_d:
			best_d = d
			best = p
	return best


## Is `p` in water (a pool, the sewer's channel)?
static func is_wet(p: Vector3) -> bool:
	var map := GameWorld.map
	return map != null and not map.pools.is_empty() and map.water_at(p)


## While it fights (and idles, and searches) it keeps to dry ground: a step that would take it from dry floor into water is
## refused (`_held`). Walking home it may wade (it was shoved across a channel), and in water it may always move.
func move(dir: Vector3, delta: float) -> bool:
	if state != State.RETURN and not dead:
		var d := Vector3(dir.x, 0.0, dir.z)
		if d.length() > 0.001 and not is_wet(global_position) and is_wet(global_position + d.normalized() * (radius + DRY_LOOK)):
			_held = true
			return false
	return super.move(dir, delta)


# --- The throw (the host's strike) ----------------------------------------------------------------------------------

## The wind-up is over: the ball goes. Only the owner throws (a puppet's comes from the host: net_strike).
func _strike() -> void:
	if not Net.owns(self) or not _target_alive():
		return
	throw_at(landing_point())


## Where this throw lands: where the target stands now (the host's lead point for another player's hero), up to SCATTER
## off (GameWorld.rng: the host rolls it and the ball's row carries the result), on the floor there.
func landing_point() -> Vector3:
	var tp := target_point()
	var map := GameWorld.map
	var a := GameWorld.rng.randf() * TAU
	var r := SCATTER * sqrt(GameWorld.rng.randf())
	var p := tp + Vector3(cos(a) * r, 0.0, sin(a) * r)
	if map != null:
		var h := map.ground_height(p)
		if is_nan(h) or map.wall_at(p):
			p = tp
			h = map.ground_height(tp)
		if not is_nan(h):
			p.y = h
	return p


## Throw a ball at `to` now (the owner; tests). Announced to the crew (Net.announce).
func throw_at(to: Vector3) -> GooBall:
	var from := hand_point()
	var b := GooBall.throw(self, from, to, GameWorld.time, GooBall.flight_for(GameWorld.flat_distance(from, to)))
	throws += 1
	last_ball = b
	Net.announce(b)
	return b


## A puppet (M4): the host's wind-up reached its strike on this screen. Nothing to resolve here: the host's ball is on its
## way (obj.new), and this screen resolves its own hero's hit when that ball lands (GooBall).
func net_strike(_victim: Actor) -> void:
	_net_struck_at = GameWorld.time
