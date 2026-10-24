extends TestCase
## The active walk and the war cry's pose (playtest feedback 2026-10-24, item 4, batch 2; MonsterModel.gait_k, cry_k):
##   1. AT REST nothing changes: the new walk's pose standing still is exactly the old one (it idles as before);
##   2. WALKING, each kind's walk is more alive than the old one: over a stride cycle the body sways or rolls from side to
##      side much more, and it leans differently into its speed (forward; the Water Boy into its truck);
##   3. THE STRIKE IS KEPT: a full wind-up and a strike at walking speed are exactly the old walk's poses (the new walk gives
##      way to them);
##   4. THE WAR CRY'S POSE: cry 1 is clearly a different pose (weapon or arms up), a wind-up takes over from it, war_cry()
##      plays it in the tree and it settles back to rest by itself;
##   5. THE PAVISE: walking and crying, its crossbow never cuts through the shield.
## The kinds that walk (not the shark, the gator or the jockey) at their full walking share.

const SPEEDS := {"grunt": 4.0, "brute": 2.6, "swarmer": 5.0, "archer": 3.5, "pavise": 2.5, "goblin": 2.2, "goo_imp": 5.0,
		"water_boy": 3.5}
const CYCLE := 24                 ## samples over the slowest stride's cycle


func setup() -> void:
	for kind: String in SPEEDS:
		var m := MonsterModels.make(kind)
		if not check(m != null, "%s has a model" % kind):
			continue
		add_child(m)
		m.idle_enabled = false
		_check_rest(kind, m)
		_check_walk(kind, m, float(SPEEDS[kind]))
		_check_strike(kind, m, float(SPEEDS[kind]))
		if not Monster.CRY_SKIP.has(kind):
			await _check_cry(kind, m)   # (the goblin scout never yells: his alarm is his own)
		if kind == "pavise":
			_check_pavise(m as PaviseModel)
		m.queue_free()
	MonsterModel.active_walk = true
	finish()


func _snapshot(m: MonsterModel) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var names: Array = m.parts.keys()
	names.sort()
	for n: String in names:
		out.append((m.parts[n] as Node3D).transform)
	return out


func _dist(a: Array[Transform3D], b: Array[Transform3D]) -> float:
	var d := 0.0
	for i in a.size():
		d = maxf(d, (a[i].origin - b[i].origin).length())
		d = maxf(d, (a[i].basis.x - b[i].basis.x).length())
		d = maxf(d, (a[i].basis.y - b[i].basis.y).length())
		d = maxf(d, (a[i].basis.z - b[i].basis.z).length())
	return d


func _pose(m: MonsterModel, walk: bool, t: float, speed: float) -> Array[Transform3D]:
	MonsterModel.active_walk = walk
	m.apply_idle(t, speed)
	m.apply_idle(t, speed)   # (twice: the Water Boy's hands follow the truck's tilt of the call before)
	return _snapshot(m)


func _check_rest(kind: String, m: MonsterModel) -> void:
	for t: float in [0.0, 0.6, 1.37]:
		var old := _pose(m, false, t, 0.0)
		var new := _pose(m, true, t, 0.0)
		check(_dist(old, new) < 0.0001, "%s: standing still, the new walk idles exactly as the old (t %.2f)" % [kind, t])


## Over a stride cycle: the body's side-to-side range (the larger of its roll's range, in radians, and twice its sideways
## shift's) and its mean lean.
func _body_track(m: MonsterModel, walk: bool, speed: float) -> Vector3:
	var body := m.parts["body"] as Node3D
	var roll := Vector2(INF, -INF)
	var shift := Vector2(INF, -INF)
	var lean := 0.0
	for i in CYCLE:
		var t := 0.3 + 1.1 * float(i) / CYCLE   # (over a full cycle of every kind's stride: the brute's is 1.05 s)
		_pose(m, walk, t, speed)
		roll = Vector2(minf(roll.x, body.rotation.z), maxf(roll.y, body.rotation.z))
		shift = Vector2(minf(shift.x, body.position.x), maxf(shift.y, body.position.x))
		lean += body.rotation.x / CYCLE
	return Vector3(maxf(roll.y - roll.x, 2.0 * (shift.y - shift.x)), lean, 0.0)


func _check_walk(kind: String, m: MonsterModel, speed: float) -> void:
	var old := _body_track(m, false, speed)
	var new := _body_track(m, true, speed)
	print("  %s: side-to-side %.3f -> %.3f, lean %.3f -> %.3f" % [kind, old.x, new.x, old.y, new.y])
	check(new.x > old.x + 0.08, "%s walks with a sway / weight shift (side-to-side %.3f -> %.3f)" % [kind, old.x, new.x])
	check(absf(new.y - old.y) > 0.03, "%s leans into its walk (mean lean %.3f -> %.3f)" % [kind, old.y, new.y])
	if kind != "water_boy":
		check(new.y < old.y, "%s leans forward, not back (%.3f -> %.3f)" % [kind, old.y, new.y])
	var moved := 0.0
	for t: float in [0.45, 0.6, 0.75]:
		moved = maxf(moved, _dist(_pose(m, false, t, speed), _pose(m, true, t, speed)))
	check(moved > 0.05, "%s: the new walk moves more than the body (%.3f)" % [kind, moved])
	MonsterModel.active_walk = true
	m.apply_idle(0.6, 0.0)


func _check_strike(kind: String, m: MonsterModel, speed: float) -> void:
	m.windup(1.0)
	check(_dist(_pose(m, false, 0.6, speed), _pose(m, true, 0.6, speed)) < 0.0001, "%s: a full wind-up at walking speed is the old pose" % kind)
	m.windup(0.0)
	m._swing = 1.0
	check(_dist(_pose(m, false, 0.6, speed), _pose(m, true, 0.6, speed)) < 0.0001, "%s: the strike at walking speed is the old pose" % kind)
	m._swing = 0.0
	MonsterModel.active_walk = true
	m.apply_idle(0.6, 0.0)


func _check_cry(kind: String, m: MonsterModel) -> void:
	var rest := _pose(m, true, 0.6, 0.0)
	m._cry = 1.0
	var cry := _pose(m, true, 0.6, 0.0)
	check(_dist(rest, cry) > 0.3, "%s: the war cry is a clearly different pose (%.2f)" % [kind, _dist(rest, cry)])
	_check_arms_forward(kind, m)
	m.windup(1.0)
	var wound := _pose(m, true, 0.6, 0.0)
	m._cry = 0.0
	check(_dist(wound, _pose(m, true, 0.6, 0.0)) < 0.0001, "%s: a wind-up takes over from the cry" % kind)
	m.windup(0.0)
	# the hook: up at once, back to rest by itself
	m.idle_enabled = true
	m.war_cry()
	await get_tree().create_timer(MonsterModel.CRY_UP + 0.1).timeout
	check(m.is_crying() and m._cry > 0.9, "%s: war_cry() throws the pose up" % kind)
	await get_tree().create_timer(MonsterModel.CRY_HOLD + MonsterModel.CRY_DOWN + 0.1).timeout
	check(not m.is_crying(), "%s: ... and it settles" % kind)
	m.idle_enabled = false
	check(_dist(rest, _pose(m, true, 0.6, 0.0)) < 0.0001, "%s: back to rest after the cry" % kind)
	m.set_downed(true)
	m.war_cry()
	check(not m.is_crying(), "%s: no cry when downed" % kind)
	m.set_downed(false)


## The cry raises the arms in FRONT (the user, 2026-10-24: "lets have the arms move foward instead of spin backwards"):
## on the way up, an arm's far end never swings behind its shoulder, nor further back than it rested (the model faces -Z).
func _check_arms_forward(kind: String, m: MonsterModel) -> void:
	for arm_name: String in ["arm_l", "arm_r"]:
		if not m.parts.has(arm_name):
			continue
		var arm := m.parts[arm_name] as MeshInstance3D
		var aabb := arm.mesh.get_aabb()
		var tip := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
		m._cry = 0.0
		m.apply_idle(0.6, 0.0)
		var limit := maxf((arm.transform * tip - arm.position).z, 0.0) + 0.15
		var worst := -INF
		for i in range(1, 11):
			m._cry = i / 10.0
			m.apply_idle(0.6, 0.0)
			worst = maxf(worst, (arm.transform * tip - arm.position).z - limit)
		check(worst <= 0.0, "%s %s: the cry raises it in front, never behind (%.2f past the limit at worst)" % [kind, arm_name, worst])
	m._cry = 1.0
	m.apply_idle(0.6, 0.0)


func _check_pavise(p: PaviseModel) -> void:
	var worst := 0
	for i in CYCLE:
		var t := 0.3 + 1.1 * float(i) / CYCLE
		for cr: float in [0.0, 0.5, 1.0, 1.1]:
			p._cry = cr
			_pose(p, true, t, 2.5)
			worst = maxi(worst, p.bow_shield_overlap())
	p._cry = 0.0
	eq(worst, 0, "pavise: walking and crying, the crossbow never cuts the shield")
