extends Monster
## Hooded archer: kites. Wants 5-8 units of distance and a clear flat shot
## (the arrow flies at chest height, so ledges block it); backs away when a
## hero gets within 3.5, repositions when it has no shot, and prefers nearby
## high ground. Draws for 0.5 s (bow string pulls back) before each arrow.

const HP := 25.0
const SPEED := 3.0
const DAMAGE := 8.0
const COOLDOWN := 1.6
const DRAW_TIME := 0.5
const AGGRO := 10.0
const MIN_RANGE := 5.0         ## below this it steps back (when it can)
const MAX_RANGE := 8.0         ## beyond this it moves closer
const FLEE_RANGE := 3.5        ## a hero this close makes it run
const ARROW_SPEED := 13.0
const ARROW_RANGE := 16.0
const HIGH_GROUND_SEARCH := 2  ## hex radius searched for a better perch
const HIGH_GROUND_EVERY := 3.0

var _string: MeshInstance3D = null
var _arrow: MeshInstance3D = null
var _hg_goal := Vector2i.ZERO
var _hg_time := 0.0            ## >0 while walking to a perch
var _hg_check_t := 1.5


func _init() -> void:
	super._init()
	kind = "archer"
	display_name = "Archer"
	max_hp = HP
	move_speed = SPEED
	radius = 0.36
	aggro_range = AGGRO
	attack_damage = DAMAGE
	attack_windup = DRAW_TIME
	attack_cooldown = COOLDOWN
	attack_start_range = MAX_RANGE
	stop_distance = MIN_RANGE
	bar_height = 1.7
	bar_width = 0.7
	windup_scale = 0.06


## Who may write each var (see Net); Monster's come from super().
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"_string": Net.LOCAL, "_arrow": Net.LOCAL,
		# The perch search is AI working state.
		"_hg_goal": Net.PRIVATE, "_hg_time": Net.PRIVATE, "_hg_check_t": Net.PRIVATE,
	})
	return f


func _build_visual(root: Node3D) -> void:
	var robe := _mat(Color(0.2, 0.5, 0.26))
	var hood := _mat(Color(0.1, 0.34, 0.16))
	var skin := _mat(Color(0.08, 0.06, 0.05))
	var wood := _mat(Color(0.5, 0.33, 0.16))
	var cord := _mat(Color(0.9, 0.9, 0.8))
	var glint := _mat(Color(1.0, 0.85, 0.3), 2.5)
	# Robe, hood, face shadow
	_cyl(root, 0.13, 0.3, 0.95, Vector3(0.0, 0.48, 0.0), robe)
	_sphere(root, 0.15, Vector3(0.0, 1.05, 0.0), robe)
	_cone(root, 0.21, 0.42, Vector3(0.0, 1.28, 0.03), hood, Vector3(-8, 0, 0))
	_sphere(root, 0.1, Vector3(0.0, 1.1, -0.08), skin)
	_sphere(root, 0.025, Vector3(-0.04, 1.12, -0.17), glint)
	_sphere(root, 0.025, Vector3(0.04, 1.12, -0.17), glint)
	# Quiver on the back
	_cyl(root, 0.06, 0.06, 0.45, Vector3(0.1, 0.95, 0.2), wood, Vector3(15, 0, -10))
	# Bow held out to the left-front
	var bow := _pivot(root, Vector3(-0.3, 0.88, -0.28))
	_box(bow, Vector3(0.05, 0.34, 0.05), Vector3.ZERO, wood)
	_box(bow, Vector3(0.045, 0.36, 0.045), Vector3(0.0, 0.3, 0.07), wood, Vector3(-22, 0, 0))
	_box(bow, Vector3(0.045, 0.36, 0.045), Vector3(0.0, -0.3, 0.07), wood, Vector3(22, 0, 0))
	_string = _box(bow, Vector3(0.012, 0.9, 0.012), Vector3(0.0, 0.0, 0.14), cord)
	_arrow = _box(bow, Vector3(0.025, 0.025, 0.7), Vector3(0.0, 0.0, -0.1), glint)
	_arrow.visible = false


func _pose(_delta: float, _moving: bool) -> void:
	if _string == null:
		return
	# Draw telegraph: the string and arrow pull back toward the archer.
	_string.position.z = 0.14 + 0.22 * _telegraph
	_arrow.visible = _telegraph > 0.0
	_arrow.position.z = -0.1 + 0.22 * _telegraph


# --- Behavior -------------------------------------------------------------------------------

func _tick_chase(delta: float) -> void:
	if not _validate_target(delta):
		return
	var tp := target.global_position
	var dist := GameWorld.flat_distance(global_position, tp)
	face_point(tp)
	var ready := GameWorld.time >= _next_attack_time
	var shot := _clear_shot()
	_hg_check_t -= delta

	# 1. A hero is on top of us: run (unless cornered, then shoot anyway).
	if dist < FLEE_RANGE:
		_hg_time = 0.0
		if _retreat(delta):
			return
		if ready and shot:
			_begin_windup(attack_windup)
		return

	# 2. Out of range or no shot: reposition toward the target until we can see it.
	if dist > MAX_RANGE or not shot:
		_hg_time = 0.0
		_nav_to(tp, delta)
		return

	# 3. In the 5-8 band with a shot.
	if ready:
		_begin_windup(attack_windup)
		return
	if dist < MIN_RANGE:
		_hg_time = 0.0
		_retreat(delta)
		return
	_perch(delta, tp)


## Step directly away from the target along the most open direction.
func _retreat(delta: float) -> bool:
	var away := global_position - target.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.001 else Vector3.BACK
	var d := _open_dir(away)
	if d == Vector3.ZERO:
		_prog_t = 0.0
		return false
	var moved := move(d, delta)
	facing = -away   # keep the bow pointed at the hero while backing up
	return moved


func _open_dir(away: Vector3) -> Vector3:
	var map := GameWorld.map
	if map == null:
		return away
	var here_lvl := map.ground_level(global_position)
	var best := Vector3.ZERO
	var best_score := -INF
	for ang in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 130.0, -130.0]:
		var d := away.rotated(Vector3.UP, deg_to_rad(ang))
		var p1 := global_position + d * 0.8
		if map.movement_check(global_position, p1) != HexMap.Move.OK:
			continue
		var l1 := map.ground_level(p1)
		if l1 < here_lvl - HexMap.STEP_LEVELS:
			continue   # don't hop off ledges while fleeing
		var score := d.dot(away)
		var p2 := global_position + d * 1.8
		if map.movement_check(global_position, p2) == HexMap.Move.OK:
			score += 0.4
		if score > best_score:
			best_score = score
			best = d
	return best


## Standing in the firing band: look for a higher cell to perch on, and walk there.
func _perch(delta: float, tp: Vector3) -> void:
	if _hg_time > 0.0:
		_hg_time -= delta
		var goal := Hex.to_world(_hg_goal)
		if GameWorld.flat_distance(global_position, goal) < 0.35:
			_hg_time = 0.0
		else:
			_nav_to(goal, delta)
			return
	elif _hg_check_t <= 0.0:
		_hg_check_t = HIGH_GROUND_EVERY
		_consider_high_ground(tp)
	_prog_t = 0.0


func _consider_high_ground(tp: Vector3) -> void:
	var map := GameWorld.map
	if map == null:
		return
	var here := current_cell()
	var best_lvl := map.ground_level(global_position) + 0.5
	var best := here
	for c in Hex.range_cells(here, HIGH_GROUND_SEARCH):
		var cell := map.get_cell(c)
		if c == here or cell == null or cell.type != HexMap.Tile.FLOOR or float(cell.level) < best_lvl:
			continue
		var d := GameWorld.flat_distance(Hex.to_world(c), tp)
		if d < MIN_RANGE or d > MAX_RANGE:
			continue
		var p := map.find_path(here, c, false, 150)
		if p.is_empty() or p.size() > HIGH_GROUND_SEARCH + 2:
			continue
		best = c
		best_lvl = float(cell.level)
	if best != here:
		_hg_goal = best
		_hg_time = 3.0


## The arrow flies flat at chest height, so test the line at the shooter's height.
func _clear_shot() -> bool:
	if not _target_alive():
		return false
	var map := GameWorld.map
	if map == null:
		return true
	var from := Combat.chest(self)
	var to := Combat.chest(target)
	to.y = from.y
	return map.line_of_sight(from, to)


func _strike() -> void:
	if not _target_alive() or not _clear_shot():
		return   # lost the shot during the draw: no arrow
	var dir := target.global_position - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	facing = dir
	Projectile.fire(self, Combat.chest(self) + dir * 0.45, dir, attack_damage, ARROW_SPEED, ARROW_RANGE)
