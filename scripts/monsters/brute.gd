extends Monster
## Brute: slow, tanky, cannot climb (a +2 ledge is a safe spot). Its ground
## slam shows a red ring of the true radius that fills up during the 0.9 s
## windup; when it lands, `slammed(pos)` fires (for screen shake) and every hero
## inside the ring at a similar height takes damage (linear falloff to 50%).
## Step 2: rare restless fights with a rival brute or a bullied skeleton (see "Restless fights" below).

signal slammed(pos: Vector3)

const HP := 140.0
const SPEED := 2.2
const SLAM_DAMAGE := 25.0
const SLAM_RADIUS := 2.0
const SLAM_EDGE_MULT := 0.5
const SLAM_SHOVE := 1.0         ## outward push on everything the slam hits
const WINDUP := 0.9
const COOLDOWN := 2.4
const AGGRO := 9.0
const START_RANGE := 1.9        ## a hero this close (and level with us) triggers a slam
const MAX_SLAM_DY := 0.8        ## world units; a hero on a +2 ledge (1.0) is out of reach

var _arm_l: Node3D = null
var _arm_r: Node3D = null
var _ring: Node3D = null
var _ring_fill: MeshInstance3D = null
var _ring_mat: StandardMaterial3D = null


func _init() -> void:
	super._init()
	kind = "brute"
	display_name = "Brute"
	max_hp = HP
	move_speed = SPEED
	radius = 0.6
	can_climb = false
	shove_mult = 0.4
	aggro_range = AGGRO
	attack_damage = SLAM_DAMAGE
	attack_windup = WINDUP
	attack_cooldown = COOLDOWN
	attack_start_range = START_RANGE
	stop_distance = 1.5
	bar_height = 2.55
	bar_width = 1.3
	walk_bob = 0.07
	walk_freq = 6.0
	windup_scale = 0.08


## Who may write each var (see Net); Monster's come from super(). All presentation.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"_arm_l": Net.LOCAL, "_arm_r": Net.LOCAL,
		"_ring": Net.LOCAL, "_ring_fill": Net.LOCAL, "_ring_mat": Net.LOCAL,
	})
	f.merge(_fight_fields())   # restless fights: host AI working state
	return f


func _build_visual(root: Node3D) -> void:
	var fur := _mat(Color(0.55, 0.16, 0.1))
	var dark := _mat(Color(0.32, 0.12, 0.08))
	var skin := _mat(Color(0.45, 0.2, 0.12))
	var horn := _mat(Color(0.9, 0.85, 0.7))
	var eye := _mat(Color(1.0, 0.85, 0.1), 3.0)
	# Legs
	_box(root, Vector3(0.32, 0.55, 0.36), Vector3(-0.3, 0.28, 0.0), dark)
	_box(root, Vector3(0.32, 0.55, 0.36), Vector3(0.3, 0.28, 0.0), dark)
	# Torso (big block) and belly
	_box(root, Vector3(1.05, 0.95, 0.72), Vector3(0.0, 1.0, 0.0), fur)
	_box(root, Vector3(0.7, 0.4, 0.2), Vector3(0.0, 0.8, -0.3), dark)
	# Shoulders
	_sphere(root, 0.3, Vector3(-0.66, 1.4, 0.0), skin)
	_sphere(root, 0.3, Vector3(0.66, 1.4, 0.0), skin)
	# Head + horns + eyes
	_box(root, Vector3(0.45, 0.38, 0.42), Vector3(0.0, 1.72, -0.06), skin)
	_cone(root, 0.08, 0.45, Vector3(-0.3, 2.0, -0.04), horn, Vector3(0, 0, 38))
	_cone(root, 0.08, 0.45, Vector3(0.3, 2.0, -0.04), horn, Vector3(0, 0, -38))
	_sphere(root, 0.05, Vector3(-0.11, 1.76, -0.27), eye)
	_sphere(root, 0.05, Vector3(0.11, 1.76, -0.27), eye)
	# Arms with fists (pivot at the shoulder for the slam animation)
	_arm_l = _pivot(root, Vector3(-0.68, 1.4, 0.0))
	_arm_r = _pivot(root, Vector3(0.68, 1.4, 0.0))
	for arm in [_arm_l, _arm_r]:
		var a: Node3D = arm
		_box(a, Vector3(0.3, 0.7, 0.3), Vector3(0.0, -0.36, 0.0), fur)
		_box(a, Vector3(0.38, 0.38, 0.38), Vector3(0.0, -0.8, 0.0), dark)


func _pose(_delta: float, _moving: bool) -> void:
	if _arm_l == null:
		return
	var a := -2.7 * _telegraph + 1.1 * _strike_t
	_arm_l.rotation.x = a
	_arm_r.rotation.x = a


# --- Slam -------------------------------------------------------------------------------------

func _can_strike_target() -> bool:
	# Out of reach if the hero stands on a ledge we can't climb (or in a pit).
	return absf(target.global_position.y - global_position.y) <= MAX_SLAM_DY


func _strike() -> void:
	var pos := global_position
	# Judged by each hero's center, so the ring is honest; online each hero's own machine decides it (Combat.slam).
	Combat.slam(pos, SLAM_RADIUS, SLAM_DAMAGE, SLAM_EDGE_MULT, SLAM_SHOVE, MAX_SLAM_DY, GameWorld.other_team(team), self)
	slammed.emit(pos)
	_spawn_shockwave(pos)


## A puppet's slam (M3): the shockwave only; the host deals the damage.
func _on_strike_visual() -> void:
	_spawn_shockwave(global_position)


func _on_windup_begin() -> void:
	_free_ring()
	_ring = Node3D.new()
	_ring.top_level = true
	add_child(_ring)
	_ring.global_position = global_position + Vector3.UP * 0.07
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat.albedo_color = Color(1.0, 0.1, 0.05, 0.85)
	var rim := TorusMesh.new()
	rim.inner_radius = SLAM_RADIUS - 0.07
	rim.outer_radius = SLAM_RADIUS
	rim.rings = 32
	rim.ring_segments = 4
	var rim_mi := MeshInstance3D.new()
	rim_mi.mesh = rim
	rim_mi.material_override = _ring_mat
	rim_mi.scale = Vector3(1.0, 0.3, 1.0)
	rim_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(rim_mi)
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.albedo_color = Color(1.0, 0.12, 0.05, 0.3)
	var disc := CylinderMesh.new()
	disc.top_radius = SLAM_RADIUS - 0.05
	disc.bottom_radius = SLAM_RADIUS - 0.05
	disc.height = 0.02
	disc.radial_segments = 32
	disc.rings = 1
	_ring_fill = MeshInstance3D.new()
	_ring_fill.mesh = disc
	_ring_fill.material_override = fill_mat
	_ring_fill.scale = Vector3(0.05, 1.0, 0.05)
	_ring_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(_ring_fill)


func _on_windup_end() -> void:
	_free_ring()


func _free_ring() -> void:
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null
	_ring_fill = null


func _update_visual(delta: float) -> void:
	super._update_visual(delta)
	if _ring_fill != null:
		var k := maxf(_telegraph, 0.05)
		_ring_fill.scale = Vector3(k, 1.0, k)
		# The ring stays put on the ground even while the body swells.
		_ring.global_position = Vector3(_ring.global_position.x, global_position.y + 0.07, _ring.global_position.z)


func _spawn_shockwave(pos: Vector3) -> void:
	if GameWorld.root == null:
		return
	var holder := Node3D.new()
	GameWorld.root.add_child(holder)
	holder.global_position = pos + Vector3.UP * 0.1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.55, 0.25, 0.8)
	var torus := TorusMesh.new()
	torus.inner_radius = SLAM_RADIUS - 0.12
	torus.outer_radius = SLAM_RADIUS
	torus.rings = 32
	torus.ring_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	holder.scale = Vector3(0.3, 1.0, 0.3)
	var tw := holder.create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.set_parallel(true)
	tw.tween_property(holder, "scale", Vector3(1.15, 1.0, 1.15), 0.3)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(holder.queue_free)


# --- Restless fights (docs/design/monster-awareness.md, Option 3, step 2) ------------------------------------------------
# Rare, and only on a floor the crew has taken long on: an idle brute rolls every FIGHT_ROLL_EVERY s with
# p = FIGHT_P x R^2 (R = MonsterSenses.restlessness(): 0 for the first 2 minutes). On a hit it walks to a rival: the
# nearest idle brute within a FIGHT_PATH_NODES path, else it bullies the nearest idle skeleton within BULLY_RANGE. A
# SQUARE_OFF s stare, then FIGHT_SLAMS_MIN-MAX slams over about FIGHT_LENGTH s (two brutes take turns; a skeleton only
# takes them) with the real slam telegraph (the ring) and real shoves, but no HP lost: no damage, and each shove is
# clamped so its slide stays under the wall-slam threshold (Actor.WALL_SLAM_MIN_SHOVE) and never goes over a void or a
# drop. A shove can still knock a monster into a priced prop, which chips or breaks it like any shove (billed as today).
# The slams make noise (NOISE_BRUTE_FIGHT 14): nearby monsters turn SUSPICIOUS and drift over to watch.
# A hero sighting (either fighter), a hit, a noise or a shout breaks it up: both go to CHASE, worked up (+20% speed for
# 10 s). Idle life's relevance limit holds (a hero within 28 of either fighter), so a brute far from the crew may walk
# over to a rival that is near it, and the fight stops when both are far from the crew.
# Online: host AI only. Both stay IDLE on the wire: the slam's wind-up rides the telegraph byte (Monster.net_show draws
# the ring for an idle wind-up) and each slam the strike count (the shockwave). No world.windup event, so no client ever
# resolves a fight slam against its hero.

const FIGHT_ROLL_EVERY := 20.0
const FIGHT_P := 0.15             ## p per roll = FIGHT_P x R^2 (~4% at R 0.5, 15% at R 1)
const FIGHT_PATH_NODES := 400
const BULLY_RANGE := 12.0
const SQUARE_OFF := 2.0
const FIGHT_SLAMS_MIN := 3
const FIGHT_SLAMS_MAX := 5
const FIGHT_LENGTH := 8.0
const FIGHT_GAP := 1.7            ## they face off this far apart (centre to centre); the slam reaches 2.0
const FIGHT_SHOVE := 2.2          ## the shove asked for, clamped per target (SAFE_SLIDE / its shove_mult)
const SAFE_SLIDE := 0.95          ## a slide below Actor.WALL_SLAM_MIN_SHOVE (1.0) stops at a wall without damage
const SAFE_DROP_LEVELS := 2       ## never shove anyone toward a drop deeper than this (falls hurt past 3)
const FIGHT_WALK_TIMEOUT := 25.0
const WORKED_UP := 1.2
const WORKED_UP_TIME := 10.0
const WALK_SPEED_K := 0.8
const FIGHT_NONE := 0
const FIGHT_WALK := 1
const FIGHT_SQUARE := 2
const FIGHT_SLAMS := 3

var _fight_roll_t := FIGHT_ROLL_EVERY
var _rival = null                 ## the brute or skeleton it fights (untyped: read duck-typed)
var _fight_phase := FIGHT_NONE
var _fight_lead := false          ## it picked the fight (and runs it)
var _fight_t := 0.0
var _fight_started := 0.0
var _fight_slams := 0             ## slams left
var _fight_slams_done := 0
var _fight_next := 0.0            ## seconds to the next slam's wind-up
var _fight_slammer = null         ## who is winding up now (self or the rival brute)
var _fight_wind := -1.0           ## >= 0: seconds into that wind-up
var fights_started := 0           ## tests


func _fight_fields() -> Dictionary:
	return {
		"_fight_roll_t": Net.PRIVATE, "_rival": Net.PRIVATE, "_fight_phase": Net.PRIVATE, "_fight_lead": Net.PRIVATE,
		"_fight_t": Net.PRIVATE, "_fight_started": Net.PRIVATE, "_fight_slams": Net.PRIVATE, "_fight_slams_done": Net.PRIVATE,
		"_fight_next": Net.PRIVATE, "_fight_slammer": Net.PRIVATE, "_fight_wind": Net.PRIVATE, "fights_started": Net.PRIVATE,
	}


func is_fighting() -> bool:
	return _fight_phase != FIGHT_NONE


func _tick_idle(delta: float) -> void:
	if _fight_phase == FIGHT_NONE:
		_roll_fight(delta)
		if _fight_phase == FIGHT_NONE:
			super._tick_idle(delta)
		return
	# In a fight: the usual sight scan breaks it up.
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_INTERVAL
		var h := _nearest_hero(aggro_range, true)
		if h == null:
			h = _cone_hero(aggro_range + CONE_EXTRA + _edge_cone())
		if h != null:
			_break_up("sighting", h)
			return
	if _fight_lead:
		_fight_tick(delta)
	elif _rival_ok():
		_keep_close(delta)


## Every FIGHT_ROLL_EVERY s, with p = FIGHT_P x R^2. No draw at all while R is 0 (the first 2 minutes of a floor).
func _roll_fight(delta: float) -> void:
	if is_frozen() or _room == "" or GameWorld.time < busy_until:
		return
	_fight_roll_t -= delta
	if _fight_roll_t > 0.0:
		return
	_fight_roll_t = FIGHT_ROLL_EVERY
	var r := MonsterSenses.restlessness()
	var p := FIGHT_P * r * r
	if p <= 0.0 or GameWorld.rng.randf() >= p:
		return
	var rival: Variant = _find_rival()
	if rival == null:
		return
	if not (_hero_within(LIFE_RANGE) or rival._hero_within(LIFE_RANGE)):
		return   # the relevance limit (28): only near the crew, or walking over to a rival that is near it
	_start_fight(rival)


## The nearest idle brute within a FIGHT_PATH_NODES path, else the nearest idle skeleton within BULLY_RANGE (null: none).
func _find_rival() -> Variant:
	var brutes: Array = []
	var grunts: Array = []
	for n in get_tree().get_nodes_in_group("monsters"):
		if n == self or n.dead or n.state != State.IDLE or n.is_frozen() or not Net.simulates(n) or GameWorld.time < n.busy_until:
			continue
		var d := GameWorld.flat_distance(n.global_position, global_position)
		if n.kind == kind and not n.is_fighting() and n._room != "":
			brutes.append([d, n])
		elif n.kind == "grunt" and d <= BULLY_RANGE:
			grunts.append([d, n])
	var nearest := func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0])
	brutes.sort_custom(nearest)
	grunts.sort_custom(nearest)
	for list: Array in [brutes, grunts]:
		for i in mini(list.size(), 3):
			var n = list[i][1]
			if _reachable(n):
				return n
	return null


func _reachable(n: Node3D) -> bool:
	var map := GameWorld.map
	if map == null:
		return true
	var here := current_cell()
	var there := Hex.from_world(n.global_position)
	return Hex.distance(here, there) <= 1 or not map.find_path(here, there, can_climb, FIGHT_PATH_NODES).is_empty()


func _start_fight(rival: Variant) -> void:
	_rival = rival
	_fight_lead = true
	_fight_phase = FIGHT_WALK
	_fight_t = 0.0
	_fight_started = GameWorld.time
	_fight_wind = -1.0
	_fight_slammer = null
	_fight_slams_done = 0
	_stuck_n = 0
	_clear_path()
	fights_started += 1
	rival.busy_until = GameWorld.time + 1.0
	if rival.kind == kind:
		rival._join_fight(self)
	CombatLog.brute_fight(self, rival)


## The rival brute: held in the fight (its own scan still breaks it up; it keeps close and takes its turns).
func _join_fight(lead: Variant) -> void:
	_rival = lead
	_fight_lead = false
	_fight_phase = FIGHT_WALK
	_fight_wind = -1.0
	_clear_path()


func _rival_ok() -> bool:
	return _rival != null and is_instance_valid(_rival) and not _rival.dead


## The fight, run by the brute that picked it.
func _fight_tick(delta: float) -> void:
	if not _rival_ok():
		_end_fight("lost")
		return
	if _rival.state != State.IDLE:
		# The rival saw, heard or was hit by something (a skeleton reacts on its own): both fight the crew now.
		var t: Variant = _rival.target if _rival.state == State.CHASE or _rival.state == State.ATTACK else null
		_break_up("rival_" + _rival.state_name(), t, _rival._point)
		return
	if not (_hero_within(LIFE_RANGE) or _rival._hero_within(LIFE_RANGE)):
		_end_fight("far")
		return
	_rival.busy_until = GameWorld.time + 1.0
	busy_until = GameWorld.time + 1.0
	_fight_t += delta
	var d := GameWorld.flat_distance(global_position, _rival.global_position)
	match _fight_phase:
		FIGHT_WALK:
			if d <= FIGHT_GAP + 0.3:
				_fight_phase = FIGHT_SQUARE
				if _rival.kind == kind:
					_rival._fight_phase = FIGHT_SQUARE
				_fight_t = 0.0
				face_point(_rival.global_position)
				_rival.face_point(global_position)
				MonsterSenses.noise(global_position, MonsterSenses.NOISE_BRUTE_FIGHT, "brute_fight", [self, _rival], MonsterSenses.WATCH_DISTANCE)   # the roar
				return
			if _fight_t > FIGHT_WALK_TIMEOUT or _stuck_n >= STUCK_GIVE_UP:
				_end_fight("lost")
				return
			_speed_k = WALK_SPEED_K
			_nav_to(_rival.global_position, delta)
			_speed_k = 1.0
		FIGHT_SQUARE:
			face_point(_rival.global_position)
			_rival.face_point(global_position)
			_prog_t = 0.0
			if _fight_t >= SQUARE_OFF:
				_fight_phase = FIGHT_SLAMS
				if _rival.kind == kind:
					_rival._fight_phase = FIGHT_SLAMS
				_fight_t = 0.0
				_fight_slams = GameWorld.rng.randi_range(FIGHT_SLAMS_MIN, FIGHT_SLAMS_MAX)
				_fight_next = 0.2
		FIGHT_SLAMS:
			_slams_tick(delta, d)


func _slams_tick(delta: float, d: float) -> void:
	if _fight_wind >= 0.0:
		var s = _fight_slammer
		if s == null or not is_instance_valid(s) or s.dead or s.is_helpless():
			_wind_off()
			return
		var other = _rival if s == self else self
		s.face_point(other.global_position)
		_fight_wind += delta
		s._telegraph = clampf(_fight_wind / WINDUP, 0.0, 1.0)
		if _fight_wind >= WINDUP:
			_wind_off()
			s._fight_slam(other)
			_fight_slams -= 1
			_fight_slams_done += 1
			_fight_next = maxf(0.3, FIGHT_LENGTH / float(_fight_slams_done + _fight_slams) - WINDUP)
		return
	if _fight_slams <= 0:
		_fight_next -= delta
		if _fight_next <= 0.0:
			_end_fight("done")
		return
	_keep_close(delta)
	_fight_next -= delta
	if _fight_next > 0.0 or d > SLAM_RADIUS - 0.15:
		return
	# Whose turn: two brutes take turns (the one that picked the fight first); a skeleton only takes the slams.
	_fight_slammer = _rival if _rival.kind == kind and _fight_slams_done % 2 == 1 else self
	_fight_wind = 0.0
	_fight_slammer._telegraph = 0.0
	_fight_slammer._on_windup_begin()


func _wind_off() -> void:
	var s = _fight_slammer
	if s != null and is_instance_valid(s):
		s._telegraph = 0.0
		s._on_windup_end()
	_fight_wind = -1.0
	_fight_slammer = null


## Close in on the other fighter (a shove pushed them apart) and face it.
func _keep_close(delta: float) -> void:
	if not _rival_ok() or is_helpless():
		return
	var d := GameWorld.flat_distance(global_position, _rival.global_position)
	if _fight_phase == FIGHT_SLAMS and d > FIGHT_GAP + 0.15 and (_fight_lead or _rival._fight_wind < 0.0):
		_speed_k = WALK_SPEED_K
		_nav_to(_rival.global_position, delta)
		_speed_k = 1.0
	else:
		face_point(_rival.global_position)
		_prog_t = 0.0


## A fight slam: the shockwave and real shoves on every monster in the ring but itself (team MONSTERS, Combat), no
## damage, each clamped to a harmless slide. The fight's noise goes out with it.
func _fight_slam(other: Node3D) -> void:
	var pos := global_position
	face_point(other.global_position)
	strikes += 1
	_strike_t = 1.0
	if model != null:
		model.attack_swing()
	_spawn_shockwave(pos)
	for a in Combat.hits_in_radius(pos, SLAM_RADIUS, self, GameWorld.TEAM_MONSTERS):
		if a == self or a.shove_mult <= 0.0 or absf(a.global_position.y - pos.y) > MAX_SLAM_DY:
			continue
		if GameWorld.flat_distance(a.global_position, pos) > SLAM_RADIUS + 0.1:
			continue   # judged by the centre, like the real slam
		var away := a.global_position - pos
		away.y = 0.0
		if away.length() < 0.05:
			away = facing
		away = away.normalized()
		var dist := minf(FIGHT_SHOVE, SAFE_SLIDE / maxf(a.shove_mult * Damp.slide_mult(a), 0.001))
		if not _safe_slide(a, away, dist * a.shove_mult * Damp.slide_mult(a)):
			continue
		a.shove(away, dist, self)
	MonsterSenses.noise(pos, MonsterSenses.NOISE_BRUTE_FIGHT, "brute_fight", [self, other], MonsterSenses.WATCH_DISTANCE)


## No void and no deep drop along the slide (a shove over a void kills a monster; a fall past 3 levels hurts).
func _safe_slide(a: Node3D, dir: Vector3, length: float) -> bool:
	var map := GameWorld.map
	if map == null:
		return true
	var start := map.ground_level(a.global_position)
	var steps := ceili((length + float(a.radius)) / 0.3)
	for i in range(1, steps + 1):
		var p: Vector3 = a.global_position + dir * minf(float(i) * 0.3, length + float(a.radius))
		var cell := map.get_cell(Hex.from_world(p))
		if cell == null:
			return false
		if cell.type == HexMap.Tile.WALL:
			return true   # it stops at the wall (gently: the slide is under the slam threshold)
		var g := map.ground_level(p)
		if is_nan(g) or start - g > float(SAFE_DROP_LEVELS):
			return false
	return true


## The fight ends on its own (done, the rival gone or the crew far away): both go back to rest.
func _end_fight(reason: String) -> void:
	var r = _rival
	CombatLog.brute_fight_end(self, reason, GameWorld.time - _fight_started, _fight_slams_done)
	_clear_fight()
	if r != null and is_instance_valid(r) and not r.dead:
		r.busy_until = -INF
		if r.kind == kind:
			r._clear_fight()
		if r.state == State.IDLE:
			r._calm()
	if state == State.IDLE:
		_calm()


## Broken up by the crew (a sighting, a hit, a noise or a shout): both go to CHASE together, worked up. `culprit` is the
## hero to chase if known (else the nearest living hero); with no hero at all they walk to `pos` on ALERT.
func _break_up(reason: String, culprit: Variant = null, pos: Vector3 = Vector3.INF) -> void:
	var lead = self if _fight_lead else _rival
	var other = _rival if _fight_lead else self
	if lead != null and is_instance_valid(lead):
		CombatLog.brute_fight_end(lead, reason, GameWorld.time - float(lead._fight_started), int(lead._fight_slams_done))
	var fighters: Array = []
	for m in [lead, other]:
		if m != null and is_instance_valid(m) and not m.dead:
			fighters.append(m)
	for m in fighters:
		if m.kind == kind:
			m._clear_fight()
		m.busy_until = -INF
	var h: Actor = culprit as Actor if culprit != null and is_instance_valid(culprit) and culprit is Actor and not culprit.dead and culprit.team != team else null
	if h == null:
		var best := INF
		for c in heroes():
			if is_instance_valid(c) and not c.dead and GameWorld.flat_distance(c.global_position, global_position) < best:
				best = GameWorld.flat_distance(c.global_position, global_position)
				h = c
	for m in fighters:
		m.set_modifier("worked_up", WORKED_UP, WORKED_UP_TIME, Actor.STAT_MOVE_SPEED)
		m._end_suspicion(true)
		if h != null:
			m._enter_chase(h)
		elif pos != Vector3.INF and m.is_passive():
			m.alert(pos)


func _clear_fight() -> void:
	if _fight_wind >= 0.0:
		_wind_off()
	_fight_phase = FIGHT_NONE
	_fight_lead = false
	_rival = null
	_fight_wind = -1.0
	_fight_slammer = null
	busy_until = -INF


# The crew interrupts: a hit, a noise, a shout, a sighting by its own scan (aggro).

func _on_damaged(amount: float, source: Node) -> void:
	if is_fighting() and source is Actor and source.team != team and not source.dead:
		_break_up("hit", source)
	super._on_damaged(amount, source)


func aggro(t: Actor) -> void:
	if is_fighting():
		_break_up("sighting", t)
		_alert_pack(t)
		return
	super.aggro(t)


func hear(pos: Vector3) -> bool:
	if is_fighting() and not dead and not is_frozen():
		_break_up("noise", null, pos)
		return true
	return super.hear(pos)


func alert(pos: Vector3) -> bool:
	if is_fighting() and not dead and not is_frozen():
		_break_up("shout", null, pos)
		return true
	return super.alert(pos)


func _physics_process(delta: float) -> void:
	# Out of IDLE some other way (a pack call put it straight into CHASE): the fight is over for both.
	if is_fighting() and state != State.IDLE and not dead:
		_break_up("pack", target)
	super._physics_process(delta)
