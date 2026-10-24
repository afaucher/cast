extends TestCase
## The elbow study (docs/design/animation-research.md, "Elbow IK study (2026-10-24)"; TwoBoneIK, LowPolyModel.elbow_ik):
##   1. THE SOLVER reaches a reachable target exactly with both bones at their lengths; an unreachable one (too far, or
##      closer than the folded chain) is clamped onto the line toward it, bones still at their lengths; the elbow bends
##      toward the pole (and flips with it) in the plane of root, target and pole; a bone's basis is orthonormal, lies
##      along the bone and turns its +Z toward the side asked
##   2. GASKET with the IK arms builds and poses: each arm is an upper arm and a forearm (the held item in the left fist,
##      both ways), the right forearm's fist meets the wrench's grip in every pose (rest, walk, wind-up, slam, the overhead
##      smash top and bottom, the spin, the cast; a grip out of the stretched reach comes in to the fist), the elbow bends out to her right when the fist comes up by her shoulder,
##      and switching back gives today's arms with the wrench where it was
##   3. THE GRUNT with the IK arms builds and poses: the sword rides in the forearm's fist with exactly today's blade angle
##      in every pose (rest, walk, wind-up, strike, war cry), the elbow is bent more cocking the sword than striking, and
##      the downed slump hangs the arms straight
##   4. both stay inside their node and triangle budgets with the extra parts

const L1 := 0.4
const L2 := 0.3
const EPS := 0.0005


func setup() -> void:
	LowPolyModel.elbow_ik = false
	_check_solver()
	await _check_gasket()
	await _check_grunt()
	finish()


# ------------------------------------------------------------------ 1. the solver

func _check_solver() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 24
	var root := Vector3(0.3, 1.2, -0.1)
	var bad_reach := 0
	var bad_len := 0
	var bad_side := 0
	for i in 200:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var dist := rng.randf_range(absf(L1 - L2) + 0.05, (L1 + L2) * 0.99)
		var target := root + dir * dist
		var pole := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var j := TwoBoneIK.solve(root, target, L1, L2, pole)
		if j[1].distance_to(target) > EPS:
			bad_reach += 1
		if absf(j[0].distance_to(root) - L1) > EPS or absf(j[1].distance_to(j[0]) - L2) > EPS:
			bad_len += 1
		var off := j[0] - (root + dir * dir.dot(j[0] - root))   # the elbow's offset from the root-target line
		if off.length() > 0.001 and off.normalized().dot(TwoBoneIK.across(pole, dir)) < 0.999:
			bad_side += 1
	eq(bad_reach, 0, "every reachable target is reached")
	eq(bad_len, 0, "both bones keep their lengths")
	eq(bad_side, 0, "the elbow sticks out along the pole's part across the line, in the plane of root, target and pole")

	# too far: clamped onto the line, at the chain's REACH
	var far := root + Vector3(0.0, 0.0, -5.0)
	var jf := TwoBoneIK.solve(root, far, L1, L2, Vector3.UP)
	near(jf[1].distance_to(root), (L1 + L2) * TwoBoneIK.REACH, EPS, "a far target is clamped to the chain's reach")
	check((jf[1] - root).normalized().dot(Vector3.FORWARD) > 0.9999, "... on the line toward it")
	near(jf[0].distance_to(root), L1, EPS, "... the upper bone at its length")
	near(jf[1].distance_to(jf[0]), L2, EPS, "... the forearm at its length")
	check(jf[0].y > root.y, "... and the nearly straight elbow still on the pole's side")
	# too near: no closer than the folded chain allows, and never a NaN (the target on the root itself)
	for t: Vector3 in [root + Vector3(0.0, -0.02, 0.0), root]:
		var jn := TwoBoneIK.solve(root, t, L1, L2, Vector3.BACK)
		var d := jn[1].distance_to(root)
		check(d >= maxf(absf(L1 - L2), (L1 + L2) * TwoBoneIK.FOLD) - EPS, "a near target is clamped out to the folded chain (%.3f)" % d)
		check(not is_nan(jn[0].x + jn[0].y + jn[0].z + jn[1].x), "no NaN at %s" % str(t - root))
		near(jn[0].distance_to(root), L1, EPS, "... the upper bone at its length")
		near(jn[1].distance_to(jn[0]), L2, EPS, "... the forearm at its length")

	# the pole decides the bend: an arm hanging straight down to a hand 0.5 below, the elbow back or forward
	var hand := root + Vector3(0.0, -0.5, 0.0)
	var back := TwoBoneIK.solve(root, hand, L1, L2, Vector3.BACK)
	var fwd := TwoBoneIK.solve(root, hand, L1, L2, Vector3.FORWARD)
	check(back[0].z - root.z > 0.15, "pole back: the elbow sticks out behind (%.3f)" % (back[0].z - root.z))
	check(fwd[0].z - root.z < -0.15, "pole forward: the elbow sticks out in front (%.3f)" % (fwd[0].z - root.z))
	near(back[0].x, root.x, EPS, "... with no sideways drift")
	# a pole along the line (no across part) still gives a steady bend, not a NaN
	var along := TwoBoneIK.solve(root, hand, L1, L2, Vector3.DOWN)
	check(not is_nan(along[0].x) and absf(along[0].distance_to(root) - L1) < EPS, "a pole along the line still bends")
	eq(TwoBoneIK.solve(root, hand, L1, L2, Vector3.BACK), back, "the same inputs give the same pose")

	# a bone's basis: orthonormal, -Y along the bone, +Z toward the side
	var b := TwoBoneIK.bone_basis(root, back[0], Vector3.BACK)
	check(b.is_conformal() and absf(b.determinant() - 1.0) < 0.001, "a bone basis is a rotation")
	check((b * Vector3.DOWN).dot((back[0] - root).normalized()) > 0.9999, "its -Y lies along the bone")
	check(b.z.dot(TwoBoneIK.across(Vector3.BACK, -b.y)) > 0.9999, "its +Z turns toward the side asked")
	var flex := TwoBoneIK.flexed(root, Basis(), Vector3(0.0, -0.6, 0.0), 0.25)
	near(flex.distance_to(root), 0.45, EPS, "flexed draws a hand in toward the shoulder")


# ------------------------------------------------------------------ 2. Gasket

## The right fist in the body's space (the right forearm's end).
func _fist_r(m: GasketModel) -> Vector3:
	var up := m.get_part("arm_r")
	return up.transform * (m.get_part("fore_r").transform * Vector3(0.0, -GasketModel.R_L2, 0.0))


func _elbow_angle(upper: Node3D, fore: Node3D, l2: float) -> float:
	var sh := upper.position
	var el := upper.transform * fore.position
	var hand := upper.transform * (fore.transform * Vector3(0.0, -l2, 0.0))
	return rad_to_deg((sh - el).angle_to(hand - el))


func _pose_gasket(m: GasketModel, pose: String) -> void:
	for k: String in ["weapon", "spin", "smash_w", "smash_a"]:
		m._arm_kick[k] = 0.0
	var speed := 0.0
	var t := 0.6
	match pose:
		"walk":
			speed = 4.0
			t = 3.0 * PI / 16.0   # (sin(8 t) = -1: the left arm at its forward swing)
		"wind":
			m._arm_kick["weapon"] = 1.0
		"slam":
			m._arm_kick["weapon"] = -1.25
		"cast":
			m._arm_kick["weapon"] = 0.9
		"spin":
			m._arm_kick["spin"] = 1.0
		"smash_up":
			m._arm_kick["smash_w"] = 1.0
			m._arm_kick["smash_a"] = GasketModel.SMASH_UP
		"smash_down":
			m._arm_kick["smash_w"] = 1.0
			m._arm_kick["smash_a"] = GasketModel.SMASH_DOWN
	m.apply_idle(t, speed)


func _check_gasket() -> void:
	var m := GasketModel.new()
	add_child(m)
	m.idle_enabled = false
	m.elbow_pick = 1
	m.apply_idle(0.0)
	await frames(1)
	for part: String in ["arm_l", "arm_r", "fore_l", "fore_r"]:
		var p := m.get_part(part)
		if check(p != null, "Gasket IK: part %s" % part):
			check(p.mesh != null and p.material_override != null, "Gasket IK: %s has a mesh and the low-poly material" % part)
	check(m.elbows_on(), "Gasket IK: the arms are split")
	check(m.get_part("fore_l").get_parent() == m.get_part("arm_l"), "Gasket IK: the forearm hangs under the upper arm")
	for part_name in GasketModel.PART_NAMES:
		check(m.has_part(part_name), "Gasket IK: part %s still exists" % part_name)
	var nodes := _count_nodes(m)
	check(nodes <= 20, "Gasket IK: node count %d inside her budget" % nodes)
	check(m.triangle_count() <= 3500, "Gasket IK: triangle budget %d" % m.triangle_count())
	m.hold_item(Node3D.new())
	check(m.hold_anchor.get_parent() == m.get_part("fore_l"), "Gasket IK: the held item rides in the left forearm's fist")

	for pose: String in ["rest", "walk", "wind", "slam", "cast", "spin", "smash_up", "smash_down"]:
		_pose_gasket(m, pose)
		var grip := m.get_part("weapon").position
		var gap := _fist_r(m).distance_to(grip)
		check(gap < 0.01, "Gasket IK %s: the right fist meets the wrench's grip (gap %.3f)" % [pose, gap])
		var sh := m.get_part("arm_r").position
		check(sh.distance_to(grip) <= (GasketModel.R_L1 + GasketModel.R_L2) * GasketModel.R_STRETCH + 0.001,
				"Gasket IK %s: the grip is inside the arm's stretched reach (%.2f)" % [pose, sh.distance_to(grip)])
		for part: String in ["arm_l", "fore_l", "arm_r", "fore_r"]:
			var o := m.get_part(part).transform.origin + m.get_part(part).basis.x
			check(not is_nan(o.x + o.y + o.z), "Gasket IK %s: %s is a number" % [pose, part])
	_pose_gasket(m, "wind")
	var bend := _elbow_angle(m.get_part("arm_r"), m.get_part("fore_r"), GasketModel.R_L2)
	check(bend < 120.0, "Gasket IK wind-up: the right elbow is bent (%.0f deg)" % bend)
	var el := m.get_part("arm_r").transform * m.get_part("fore_r").position
	var sh_r := m.get_part("arm_r").position
	var line := (m.get_part("weapon").position - sh_r).normalized()
	var out := el - (sh_r + line * line.dot(el - sh_r))
	check(out.x > 0.05, "Gasket IK wind-up: the elbow sticks out to her right (%.3f)" % out.x)
	_pose_gasket(m, "rest")
	var rest_bend := _elbow_angle(m.get_part("arm_r"), m.get_part("fore_r"), GasketModel.R_L2)
	check(rest_bend > 165.0, "Gasket IK rest: the right arm hangs nearly straight (%.0f deg)" % rest_bend)
	var bend_l := _elbow_angle(m.get_part("arm_l"), m.get_part("fore_l"), GasketModel.L_L2)
	_pose_gasket(m, "walk")
	var walk_l := _elbow_angle(m.get_part("arm_l"), m.get_part("fore_l"), GasketModel.L_L2)
	check(walk_l < bend_l - 5.0, "Gasket IK walk: the forward-swinging left arm bends more (%.0f < %.0f deg)" % [walk_l, bend_l])

	# back to today's arms: one piece each, the held item back on the sleeve, the wrench where it was
	_pose_gasket(m, "wind")
	var wrench := m.get_part("weapon").position
	m.elbow_pick = 0
	_pose_gasket(m, "wind")
	await frames(1)
	check(not m.has_part("fore_l") and not m.has_part("fore_r") and not m.elbows_on(), "Gasket old: the forearms are gone")
	check(m.hold_anchor.get_parent() == m.get_part("arm_l"), "Gasket old: the held item is back on the left sleeve")
	check(m.get_part("weapon").position.distance_to(wrench) < 0.0001, "Gasket old: the wrench is where it was")
	check(m.get_part("arm_r").scale.y < 0.6, "Gasket old: the wind-up squashes today's right sleeve (%.2f)" % m.get_part("arm_r").scale.y)
	# and the global switch drives a model that follows it
	m.elbow_pick = -1
	LowPolyModel.elbow_ik = true
	m.apply_idle(0.0)
	check(m.has_part("fore_r"), "Gasket follows the elbow_ik switch")
	LowPolyModel.elbow_ik = false
	m.apply_idle(0.0)
	check(not m.has_part("fore_r"), "... both ways")
	m.queue_free()
	await frames(1)


# ------------------------------------------------------------------ 3. the grunt

func _pose_grunt(m: GruntModel, pose: String) -> void:
	m._wind = 0.0
	m._swing = 0.0
	m._cry = 0.0
	var speed := 0.0
	match pose:
		"walk":
			speed = 4.0
		"windup":
			m._wind = 1.0
		"swing":
			m._swing = 1.0
		"cry":
			m._cry = 1.0
	m.apply_idle(0.6 if pose != "walk" else PI / 17.0, speed)


func _check_grunt() -> void:
	var old := GruntModel.new()
	var ik := GruntModel.new()
	add_child(old)
	add_child(ik)
	for m: GruntModel in [old, ik]:
		m.idle_enabled = false
	old.elbow_pick = 0
	ik.elbow_pick = 1
	ik.apply_idle(0.0)
	await frames(1)
	check(ik.has_part("fore_l") and ik.has_part("fore_r"), "grunt IK: the arms are split")
	check(ik.get_part("weapon").get_parent() == ik.get_part("fore_r"), "grunt IK: the sword is in the right forearm's fist")
	check(ik.get_part("fore_r").material_override != null, "grunt IK: the forearm has the enemy material")
	var budget := int(MonsterDefs.row("grunt")["tris"])
	check(ik.triangle_count() <= budget, "grunt IK: triangle budget %d <= %d (today's %d)" % [ik.triangle_count(), budget, old.triangle_count()])
	var bends := {}
	for pose: String in ["rest", "walk", "windup", "swing", "cry"]:
		_pose_grunt(old, pose)
		_pose_grunt(ik, pose)
		var bo := old.get_part("weapon").global_basis
		var bi := ik.get_part("weapon").global_basis
		var same := bo.x.distance_to(bi.x) + bo.y.distance_to(bi.y) + bo.z.distance_to(bi.z)
		check(same < 0.002, "grunt IK %s: the blade keeps today's angle (diff %.4f)" % [pose, same])
		var up := ik.get_part("arm_r")
		var fist := up.transform * (ik.get_part("fore_r").transform * GruntModel.IK_HAND)
		check(fist.distance_to(up.position) <= GruntModel.L1 + GruntModel.L2 + 0.001, "grunt IK %s: the fist is in reach" % pose)
		bends[pose] = _elbow_angle(up, ik.get_part("fore_r"), GruntModel.L2)
	check(float(bends["windup"]) < float(bends["swing"]) - 30.0,
			"grunt IK: the elbow is cocked in the wind-up (%.0f deg) and flung out in the strike (%.0f deg)" % [bends["windup"], bends["swing"]])
	check(float(bends["rest"]) < 150.0, "grunt IK: the sword is carried with a bent elbow (%.0f deg)" % bends["rest"])
	ik.set_downed(true)
	check(ik.get_part("fore_r").basis.is_equal_approx(Basis.IDENTITY), "grunt IK downed: the arms hang straight")
	old.queue_free()
	ik.queue_free()
	await frames(1)


func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c
