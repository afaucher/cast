extends Monster
## Hooded archer: kites. Wants 5-8 units of distance and a clear flat shot
## (the arrow flies at chest height, so ledges block it); backs away when a
## hero gets within 3.5, repositions when it has no shot, and prefers nearby
## high ground. Draws for 0.5 s (bow string pulls back) before each arrow.
##
## TARGET PRACTICE (idle life near the crew, docs/design/monster-awareness.md, step 2): every 40 s -> 12 s (the R ramp) an
## idle archer draws on a priced prop it can see within 10 and shoots it with its ordinary arrow (the same projectile,
## damage and hits as in a fight: a hero who steps into it is hit, and a prop it hits takes the damage like any arrow's;
## user, 2026-10-18). WHAT IT AIMS AT is kept safe: only while IDLE (a "?", an alert or a fight ends it at once), never
## while a hero is within its sight (PRACTICE_CLEAR), never at a prop in the room the crew is in, only with a clear lane
## and line of sight, before R 0.5 only props priced PRACTICE_PRICE_LIMIT or less, and never a prop that has taken
## PRACTICE_HITS_PER_PROP practice hits (every archer together) or that the next arrows could break. So practice on its
## own chips props and never breaks or bills one.

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

# --- Target practice (the safety numbers; the user may want breaks later) ---------------------------------------------
const PRACTICE_RANGE := 10.0            ## props within this (flat) and in line of sight
const PRACTICE_EVERY_CALM := 40.0       ## seconds between practice shots at R 0 ...
const PRACTICE_EVERY_RESTLESS := 12.0   ## ... and at R 1 (x0.8-1.2, rolled)
const PRACTICE_CHEAP_UNTIL := 0.5       ## below this restlessness ...
const PRACTICE_PRICE_LIMIT := 3000      ## ... only props priced this many dollars or less
const PRACTICE_HITS_PER_PROP := 2       ## a prop takes at most this many practice arrows a floor (all archers) ...
const PRACTICE_BREAK_MARGIN := 1.0      ## ... and none that would leave it with less HP than this (never a break)
const PRACTICE_CLEAR := 16.0            ## no hero within this of the archer (its cone sight, aggro + 6)
const PRACTICE_LANE := 0.35             ## nothing else (actor, mail, another prop) this close to the arrow's lane at release
const PRACTICE_MAX_DY := 0.6            ## the arrow flies flat at chest height: the prop must stand about level

var _string: MeshInstance3D = null
var _arrow: MeshInstance3D = null
var _hg_goal := Vector2i.ZERO
var _hg_time := 0.0            ## >0 while walking to a perch
var _hg_check_t := 1.5
var _practice_t := -1.0        ## seconds to the next practice try (< 0: not rolled yet)
var _practice_prop = null      ## the prop it is drawing on (untyped: PricedProp lives in contracts/)
var _practice_draw := -1.0     ## >= 0 while drawing a practice shot: seconds drawn
var _practice_frame := -1      ## the physics frame its idle life last ran (a draw dies with it)
var practice_shots := 0        ## practice arrows loosed (tests, the combat log)


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
		# Target practice is host AI working state; the draw shows through _telegraph, the shot through strikes.
		"_practice_t": Net.PRIVATE, "_practice_prop": Net.PRIVATE, "_practice_draw": Net.PRIVATE,
		"_practice_frame": Net.PRIVATE, "practice_shots": Net.PRIVATE,
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
	var tp := target_point()
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
		if c == here or cell == null or cell.type != HexMap.Tile.FLOOR or not map.is_walkable_cell(c) or float(cell.level) < best_lvl:
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
	return map.line_of_sight(from, to, 0.08)   # fine: an arrow released beside a wall corner must not clip its tip


func _strike() -> void:
	if not _target_alive() or not _clear_shot():
		return   # lost the shot during the draw: no arrow
	var dir := target_point() - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	facing = dir
	_fire_arrow(dir, attack_damage)


## The archer's arrow: an ordinary Projectile that hits heroes, breakables and the priced props it runs into.
func _fire_arrow(dir: Vector3, dmg: float) -> Projectile:
	var p := Projectile.fire(self, Combat.chest(self) + dir * 0.45, dir, dmg, ARROW_SPEED, ARROW_RANGE)
	p.hits_props = true
	return p


## A puppet's shot (M3): the arrow flies on this screen too. A fight's arrow is harmless here (M4: this machine resolved
## the strike on its own hero from the wind-up event). A practice shot (the host's archer was IDLE: no wind-up event) is
## the ordinary arrow with its damage, but on this screen it can only hurt this machine's own hero (the victim decides):
## a prop, a monster, an employee or another player's hero is never decided here (Net.resolves_hit: the archer is a copy).
func _on_strike_visual() -> void:
	var dir := Vector3(facing.x, 0.0, facing.z)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	_fire_arrow(dir, attack_damage if state == State.IDLE else 0.0)


# --- Target practice ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# A practice draw lasts only while idle life runs: a "?", an alert, a fight, a shove or the crew leaving ends it.
	if _practice_draw >= 0.0 and (state != State.IDLE or Engine.get_physics_frames() - _practice_frame > 1):
		_stop_practice()
	super._physics_process(delta)


func _idle_life(delta: float) -> bool:
	_practice_frame = Engine.get_physics_frames()
	var r := MonsterSenses.restlessness()
	if _practice_draw >= 0.0:
		if not _practice_ok(_practice_prop, r):
			_stop_practice()
			return false
		face_point(_practice_prop.global_position)
		_practice_draw += delta
		_telegraph = clampf(_practice_draw / scaled_cooldown(DRAW_TIME), 0.0, 1.0)
		if _telegraph >= 1.0:
			_loose_practice()
		_prog_t = 0.0
		return true
	if _practice_t < 0.0:
		_practice_t = GameWorld.rng.randf_range(0.25, 1.0) * lerpf(PRACTICE_EVERY_CALM, PRACTICE_EVERY_RESTLESS, r)
	_practice_t -= delta
	if _practice_t > 0.0:
		return false
	_practice_t = lerpf(PRACTICE_EVERY_CALM, PRACTICE_EVERY_RESTLESS, r) * GameWorld.rng.randf_range(0.8, 1.2)
	var prop: Variant = _pick_practice_target(r)
	if prop == null:
		return false
	_practice_prop = prop
	_practice_draw = 0.0
	_telegraph = 0.0
	face_point(_practice_prop.global_position)
	_on_windup_begin()
	return true


## The props it may practise on now, one picked with GameWorld.rng (null: none).
func _pick_practice_target(r: float) -> Variant:
	var opts: Array = []
	for n in get_tree().get_nodes_in_group("priced_props"):
		if _practice_ok(n, r):
			opts.append(n)
	return opts[GameWorld.rng.randi_range(0, opts.size() - 1)] if not opts.is_empty() else null


## Every safety rule for a practice shot at `prop` (checked when it picks the prop, every frame of the draw and at the
## release). The crew: nobody within PRACTICE_CLEAR, nobody in the prop's room. The prop: alive, within range and level,
## in line of sight with a clear lane, cheap enough before R 0.5, under its practice cap, and able to take the arrows in
## flight plus this one with PRACTICE_BREAK_MARGIN HP to spare.
func _practice_ok(prop: Variant, r: float) -> bool:
	if prop == null or not is_instance_valid(prop) or prop.dead or state != State.IDLE or is_frozen():
		return false
	var from := Combat.chest(self)
	var to: Vector3 = prop.global_position
	if GameWorld.flat_distance(global_position, to) > PRACTICE_RANGE or absf(to.y - global_position.y) > PRACTICE_MAX_DY:
		return false
	if r < PRACTICE_CHEAP_UNTIL and int(prop.price) > PRACTICE_PRICE_LIMIT:
		return false
	if MonsterSenses.practice_hits(prop) >= PRACTICE_HITS_PER_PROP:
		return false
	var flying := MonsterSenses.practice_flying(prop)
	if prop.hp - attack_damage * prop.damage_taken_mult() * float(flying + 1) < PRACTICE_BREAK_MARGIN:
		return false
	var prop_room := MonsterSenses.room_of(Hex.from_world(to))
	for h in heroes():
		if not is_instance_valid(h) or h.dead:
			continue
		if GameWorld.flat_distance(global_position, h.global_position) <= PRACTICE_CLEAR:
			return false
		if prop_room != "" and MonsterSenses.room_of(h.current_cell()) == prop_room:
			return false
	var map := GameWorld.map
	if map != null:
		var flat := Vector3(to.x, from.y, to.z)
		var d := flat - from
		d.y = 0.0
		var stop := flat - d.normalized() * float(prop.radius) * 0.8   # (the line ends at the prop's face)
		if not map.line_of_sight(from, stop, 0.08):
			return false
	return _lane_clear(from, to, prop)


## Nothing but the prop near the arrow's lane: no actor of any team (heroes, employees, monsters, other props) and no
## mail or crate, so the practice arrow's first hit is the prop it is aimed at.
func _lane_clear(from: Vector3, to: Vector3, prop: Node) -> bool:
	var a2 := Vector2(from.x, from.z)
	var b2 := Vector2(to.x, to.z)
	var others: Array = GameWorld.actors()
	others.append_array(GameWorld.breakables_in_radius(global_position, PRACTICE_RANGE + 2.0))
	for n in others:
		if n == self or n == prop or not is_instance_valid(n) or n.dead:
			continue
		var p2 := Vector2(n.global_position.x, n.global_position.z)
		if Geometry2D.get_closest_point_to_segment(p2, a2, b2).distance_to(p2) <= float(n.radius) + PRACTICE_LANE:
			return false
	return true


## Loose the practice arrow: the archer's ordinary arrow (Projectile, hits props). The strike count moves on, so the other
## screens play the shot (_on_strike_visual).
func _loose_practice() -> void:
	var prop: Variant = _practice_prop
	_stop_practice()
	if not _practice_ok(prop, MonsterSenses.restlessness()):
		return
	practice_shot(prop)


## The release itself (no safety rules: _practice_ok decided them; tests call it directly). Null if the prop is on top
## of the archer.
func practice_shot(prop: Variant) -> Projectile:
	var dir: Vector3 = prop.global_position - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return null
	dir = dir.normalized()
	facing = dir
	var hp_before: float = prop.hp
	var arrow := _fire_arrow(dir, attack_damage)
	MonsterSenses.note_practice_hit(prop)
	MonsterSenses.note_practice_flying(prop, 1)
	practice_shots += 1
	strikes += 1
	_strike_t = 1.0
	if model != null:
		model.attack_swing()
	var prop_ref: WeakRef = weakref(prop)
	var me: WeakRef = weakref(self)
	var dist := GameWorld.flat_distance(global_position, prop.global_position)
	arrow.impacted.connect(func(_pos: Vector3, hit: Actor) -> void:
		var pr: Variant = prop_ref.get_ref()
		if pr != null:
			MonsterSenses.note_practice_flying(pr, -1)
		var a: Variant = me.get_ref()
		CombatLog.practice(a, pr, dist, (hp_before - pr.hp) if pr != null and hit == pr else 0.0, hit), CONNECT_ONE_SHOT)
	return arrow


func _stop_practice() -> void:
	_practice_draw = -1.0
	_practice_prop = null
	if _telegraph > 0.0 and state != State.ATTACK:
		_telegraph = 0.0
	_on_windup_end()
