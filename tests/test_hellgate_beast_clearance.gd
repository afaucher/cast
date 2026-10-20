extends TestCase
## The hellgate beast's tentacles never pass through each other, through themselves or through the level (the terrain's
## columns, the room's props and decor, the gate), at rest or in any pose the shader can give them: over many seeds and
## every gate room of floors 1-3 (every gate's beast on the floor, so neighbouring beasts count too).
##   - the envelope check (BeastLimbs.clearances: the tube's widest point plus every motion's bound) is at least MARGIN;
##   - and independently, the flail's EXTREME poses: every free point pushed to the four corners of its sway-plus-flail
##     box (side and up, both signs) with the resting tube, against the level and itself.
## The worst values found are printed; the first wired version's placement (HellgateBeast.check_clearance off) is
## measured too, for the record.

const SEEDS := 10
const EPS := 0.0005


func setup() -> void:
	var worst_after := 1.0e9
	var worst_pose := 1.0e9
	var worst_before := 1.0e9
	var where := ""
	var limbs := 0
	for sd in range(1, SEEDS + 1):
		for fl in [1, 2, 3]:
			var run := ContractRun.make("guru", sd, 0.8)
			var map := DungeonGen.for_run(run, fl)
			var plan := SiteBuilder.plan(map, run, fl, PricedProp.catalog(run.site_type))
			var root := Node3D.new()
			add_child(root)
			GameWorld.begin(map, root, run.floor_seed(fl))
			var dummies: Array[Node3D] = []
			for g in plan.gates:
				var c: Vector2i = g["cell"]
				var d := Node3D.new()
				root.add_child(d)
				d.global_position = Hex.to_world(c, float(map.get_cell(c).level))
				dummies.append(d)
			for checked in [false, true]:
				HellgateBeast.check_clearance = checked
				var built: Array[HellgateBeast] = []
				for d in dummies:
					var b := HellgateBeast.for_gate(d, map, plan, run.floor_seed(fl))
					if b != null:
						built.append(b)
				for b in built:
					var rep := b.clearance_report()
					if not checked:
						BeastLimbs.rest_only = true
						worst_before = minf(worst_before, float(b.clearance_report()["worst"]))
						BeastLimbs.rest_only = false
						continue
					limbs += int(b.stats["limbs"])
					if float(rep["worst"]) < worst_after:
						worst_after = float(rep["worst"])
						where = "seed %d floor %d gate %s %s" % [sd, fl, str(b.gate_cell), str(rep)]
					worst_pose = minf(worst_pose, _extreme_poses(b))
				for b in built:
					b.free()
			HellgateBeast.check_clearance = true
			GameWorld.end()
			root.free()
		await frames(1)
	print("[beast clearance] %d limbs over %d seeds: worst envelope clearance %.3f (%s), worst extreme pose %.3f; first version at rest %.3f" % [
			limbs, SEEDS, worst_after, where, worst_pose, worst_before])
	check(limbs > SEEDS * 6, "the beasts still have their limbs (%d)" % limbs)
	check(worst_after >= BeastLimbs.MARGIN - EPS, "no limb comes within %.2f of the level, itself or another limb, motion included (worst %.3f: %s)" % [
			BeastLimbs.MARGIN, worst_after, where])
	check(worst_pose >= BeastLimbs.MARGIN - EPS, "nor in the flail's extreme poses (worst %.3f)" % worst_pose)
	finish()


## The least level / self clearance of a beast's limbs with every free point at a corner of its motion box, the
## resting tube around it.
func _extreme_poses(b: HellgateBeast) -> float:
	var worst := 1.0e9
	BeastLimbs.rest_only = true
	for p: BeastLimbs.Path in b._paths:
		var amp := p.sway_amp * BeastLimbs.SWAY_WRITHE + BeastLimbs.FLAIL_MAX
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var q := BeastLimbs.Path.new()
				q.pts = p.pts.duplicate()
				q.radii = p.radii.duplicate()
				q.free = p.free.duplicate()
				q.xs = p.xs
				q.ys = p.ys
				q.ts = p.ts
				q.grip_end = p.grip_end
				q.sway_amp = p.sway_amp
				q.side = p.side
				for i in q.pts.size():
					q.pts[i] += (p.side * sx + Vector3(0, 0.6, 0) * sy) * amp * p.free[i]
				q.update_box()
				worst = minf(worst, BeastLimbs.level_clearance(q, b._level))
				worst = minf(worst, BeastLimbs.self_clearance(q))
	BeastLimbs.rest_only = false
	return worst
