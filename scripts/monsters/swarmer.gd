extends Monster
## Swarmer: a fast, fragile spiky imp that comes in packs. Instead of stacking
## on the hero it closes in, darts in for a bite when off cooldown, and circles
## (each imp picks its own direction) while the bite recharges.

const HP := 12.0
const SPEED := 5.5
const DAMAGE := 4.0
const WINDUP := 0.3   ## user, 2026-10-18 (option A): long enough to react to on any machine
const COOLDOWN := 0.6
const AGGRO := 9.0
const REACH := 0.7
const START_RANGE := 1.0
const FLANK_RANGE := 2.8       ## inside this (with line of sight) it darts/circles instead of pathing
const ORBIT_DIST := 1.5        ## preferred circling distance while the bite recharges

## Play (idle life near the crew, docs/design/monster-awareness.md): a clump's imps hop about its centre, chase each
## other and tussle (a tiny real shove each), and the clump's centre drifts a hex every 15-25 s within its room.
## Restlessness R widens the drift (2 -> 5 hexes from where the clump spawned) and the hops, and makes play busier.
const PLAY_SIT := 0
const PLAY_HOP := 1
const PLAY_CHASE := 2
const PLAY_SPEED := 0.7
const CHASE_SPEED := 0.9
const CLUMP_RADIUS := 4.5         ## imps whose homes are this close (and in the same room) are one clump
const BUDDY_RANGE := 4.0
const DRIFT_MIN := 15.0
const DRIFT_MAX := 25.0
const DRIFT_HEX_CALM := 2
const DRIFT_HEX_RESTLESS := 5
const TUSSLE_SHOVE := 0.3         ## x shove_mult 1.5 = 0.45: below a wall slam, so it never hurts
const TUSSLE_EVERY := 3.0
const TUSSLE_REACH := 0.75

var _side := 1.0
var _los_t := 0.0
var _los_ok := false
var _leader = null                   ## the clump's leader (lowest instance id): owns the drifting centre
var _clump_home := Vector3.INF
var _clump_center := Vector3.INF
var _drift_t := 0.0
var _play := PLAY_SIT
var _play_t := 0.0
var _play_goal := Vector3.ZERO
var _buddy = null                    ## (untyped: another Swarmer, read duck-typed)
var _tussle_at := -INF


func _init() -> void:
	super._init()
	kind = "swarmer"
	display_name = "Swarmer"
	max_hp = HP
	move_speed = SPEED
	radius = 0.26
	shove_mult = 1.5
	aggro_range = AGGRO
	attack_damage = DAMAGE
	attack_windup = WINDUP
	attack_cooldown = COOLDOWN
	attack_reach = REACH
	attack_start_range = START_RANGE
	attack_arc_deg = 160.0
	stop_distance = 0.6
	bar_height = 0.95
	bar_width = 0.5
	walk_bob = 0.14
	walk_freq = 16.0
	windup_scale = 0.3
	model_windup_scale = 0.12


func _ready() -> void:
	super._ready()
	_side = 1.0 if GameWorld.rng.randf() < 0.5 else -1.0


## Who may write each var (see Net); Monster's come from super(). The circling side and the
## LOS check are host-side AI choices that nobody else needs.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({"_side": Net.PRIVATE, "_los_t": Net.PRIVATE, "_los_ok": Net.PRIVATE,
		# Play is host AI working state.
		"_leader": Net.PRIVATE, "_clump_home": Net.PRIVATE, "_clump_center": Net.PRIVATE, "_drift_t": Net.PRIVATE,
		"_play": Net.PRIVATE, "_play_t": Net.PRIVATE, "_play_goal": Net.PRIVATE, "_buddy": Net.PRIVATE,
		"_tussle_at": Net.PRIVATE,
	})
	return f


# --- Play -------------------------------------------------------------------------------------

func _idle_life(delta: float) -> bool:
	if _clump_home == Vector3.INF:
		_join_clump()
	var r := MonsterSenses.restlessness()
	if _leads():
		_drift_t -= delta
		if _drift_t <= 0.0:
			_drift_t = GameWorld.rng.randf_range(DRIFT_MIN, DRIFT_MAX)
			_drift(r)
	_play_t -= delta
	if _play_t <= 0.0:
		_pick_play(r)
	match _play:
		PLAY_HOP:
			if GameWorld.flat_distance(global_position, _play_goal) < 0.35 or _stuck_n >= 2:
				_stuck_n = 0
				_play = PLAY_SIT
				return false
			_speed_k = PLAY_SPEED
			_nav_to(_play_goal, delta)
			_speed_k = 1.0
			return true
		PLAY_CHASE:
			if not _buddy_ok():
				_play = PLAY_SIT
				return false
			var bp: Vector3 = _buddy.global_position
			if GameWorld.flat_distance(global_position, bp) <= TUSSLE_REACH:
				_tussle()
				_play = PLAY_SIT
				_play_t = GameWorld.rng.randf_range(0.6, 1.2)
				return false
			_speed_k = CHASE_SPEED
			_nav_to(bp, delta)
			_speed_k = 1.0
			return true
	return false


## The clump: every imp whose home is within CLUMP_RADIUS in the same room; the one with the lowest instance id leads.
func _join_clump() -> void:
	_clump_home = home
	_clump_center = home
	_leader = self
	var best := get_instance_id()
	for n in get_tree().get_nodes_in_group("monsters"):
		if n == self or n.dead or n.kind != kind or n._room != _room:
			continue
		var h: Vector3 = n.home if n._home_set else n.global_position
		if GameWorld.flat_distance(h, home) <= CLUMP_RADIUS and n.get_instance_id() < best:
			best = n.get_instance_id()
			_leader = n


func _leads() -> bool:
	return _leader == self or _leader == null or not is_instance_valid(_leader) or _leader.dead


## Where the clump plays now: the leader's drifting centre.
func _centre() -> Vector3:
	if _leads():
		return _clump_center
	var c: Vector3 = _leader._clump_center
	return c if c != Vector3.INF else _clump_center


## The leader moves the clump's centre one hex, staying in the room and within the drift radius of where it spawned.
func _drift(r: float) -> void:
	var map := GameWorld.map
	if map == null:
		return
	var max_hex := roundi(lerpf(DRIFT_HEX_CALM, DRIFT_HEX_RESTLESS, r))
	var from := Hex.from_world(_clump_center)
	var origin := Hex.from_world(_clump_home)
	var opts: Array[Vector2i] = []
	for nb in Hex.neighbors(from):
		if Hex.distance(nb, origin) <= max_hex and _play_cell(nb):
			opts.append(nb)
	if opts.is_empty():
		return
	var pick := opts[GameWorld.rng.randi_range(0, opts.size() - 1)]
	_clump_center = Hex.to_world(pick, float(map.get_cell(pick).level))


func _play_cell(c: Vector2i) -> bool:
	var map := GameWorld.map
	return map != null and map.is_walkable_cell(c) and not map.is_pool_cell(c) and MonsterSenses.room_of(c) == _room


func _pick_play(r: float) -> void:
	_play_t = GameWorld.rng.randf_range(1.2, 3.0) * lerpf(1.0, 0.6, r)
	var roll := GameWorld.rng.randf()
	var sit := lerpf(0.45, 0.25, r)
	if roll < sit:
		_play = PLAY_SIT
		return
	if roll < sit + 0.25:
		_buddy = _find_buddy()
		if _buddy != null:
			_play = PLAY_CHASE
			return
	var centre := _centre()
	var hop := 2 if r < 0.5 else 3
	var cells := Hex.range_cells(Hex.from_world(centre), hop)
	for _i in 6:
		var c: Vector2i = cells[GameWorld.rng.randi_range(0, cells.size() - 1)]
		if _play_cell(c):
			_play = PLAY_HOP
			_play_goal = Hex.to_world(c, float(GameWorld.map.get_cell(c).level))
			return
	_play = PLAY_SIT


func _find_buddy() -> Variant:
	var opts: Array = []
	for n in get_tree().get_nodes_in_group("monsters"):
		if n == self or n.dead or n.kind != kind or n.state != State.IDLE or n.is_frozen():
			continue
		if GameWorld.flat_distance(n.global_position, global_position) <= BUDDY_RANGE:
			opts.append(n)
	return opts[GameWorld.rng.randi_range(0, opts.size() - 1)] if not opts.is_empty() else null


func _buddy_ok() -> bool:
	return _buddy != null and is_instance_valid(_buddy) and not _buddy.dead and _buddy.state == State.IDLE \
			and GameWorld.flat_distance(_buddy.global_position, global_position) <= BUDDY_RANGE * 1.5


## Bump and bounce: a tiny real shove each (the verb), never toward a drop or the void.
func _tussle() -> void:
	if GameWorld.time < _tussle_at:
		return
	_tussle_at = GameWorld.time + TUSSLE_EVERY
	var d: Vector3 = _buddy.global_position - global_position
	d.y = 0.0
	if d.length() < 0.01:
		d = facing
	d = d.normalized()
	if not _safe_ground(_buddy.global_position + d * 0.8) or not _safe_ground(global_position - d * 0.8):
		return
	_buddy.shove(d, TUSSLE_SHOVE, self)
	shove(-d, TUSSLE_SHOVE, self)


func _safe_ground(p: Vector3) -> bool:
	var map := GameWorld.map
	if map == null:
		return true
	var c := Hex.from_world(p)
	var cell := map.get_cell(c)
	return cell != null and cell.type == HexMap.Tile.FLOOR and map.is_walkable_cell(c) \
			and absf(map.ground_level(p) - map.ground_level(global_position)) < 1.0


func _build_visual(root: Node3D) -> void:
	var body := _mat(Color(0.5, 0.2, 0.7))
	var spike := _mat(Color(0.3, 0.08, 0.42))
	var eye := _mat(Color(1.0, 0.9, 0.2), 3.0)
	_sphere(root, 0.28, Vector3(0.0, 0.32, 0.0), body)
	# Spikes spread over the upper hemisphere (fibonacci spiral).
	var n := 11
	for i in n:
		var y := lerpf(1.0, -0.15, (float(i) + 0.5) / float(n))
		var ring_r := sqrt(maxf(0.0, 1.0 - y * y))
		var a := float(i) * 2.399963
		var dir := Vector3(cos(a) * ring_r, y, sin(a) * ring_r)
		var mi := _cone(root, 0.06, 0.24, Vector3(0.0, 0.32, 0.0) + dir * 0.35, spike)
		mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), Vector3(0.0, 0.32, 0.0) + dir * 0.36)
	_sphere(root, 0.055, Vector3(-0.1, 0.38, -0.24), eye)
	_sphere(root, 0.055, Vector3(0.1, 0.38, -0.24), eye)


func _chase_move(delta: float, dist: float) -> void:
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = 0.3
		_los_ok = dist < FLANK_RANGE and _can_strike_target()
	var tp := target_point()
	if dist > FLANK_RANGE or not _los_ok:
		_nav_to(tp, delta)
		return
	var to := tp - global_position
	to.y = 0.0
	var fwd := to.normalized()
	var side := Vector3(-fwd.z, 0.0, fwd.x) * _side
	var dir: Vector3
	if GameWorld.time >= _next_attack_time:
		dir = (fwd + side * 0.4).normalized()       # dart in on a curve
	else:
		# Recharging: circle the hero at roughly ORBIT_DIST.
		var radial := clampf((dist - ORBIT_DIST) * 0.8, -0.7, 0.7)
		dir = (side + fwd * radial).normalized()
	if not move(dir, delta):
		_nav_to(tp, delta)
	else:
		_prog_t = 0.0
		face_point(tp)   # keep biting end toward the hero while circling
