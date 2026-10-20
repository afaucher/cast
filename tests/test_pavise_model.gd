extends TestCase
## The Pavise Crossbowman look (lab only, PaviseModel; docs/design/pavise-read-test.md): with either carry style the
## crossbow never passes through the pavise, in any shield state, through a walk cycle, while reloading and aiming.
## (The user, 2026-10-20: "The at-rest crossbow penetrates the shield.") It also stays within a triangle budget.

const BUDGET := 3200


func setup() -> void:
	for carry: String in PaviseModel.CARRY_STYLES:
		var m := PaviseModel.new(carry)
		add_child(m)
		check(m.triangle_count() <= BUDGET, "%s: %d triangles (budget %d)" % [carry, m.triangle_count(), BUDGET])
		for i in 8:   # a walk cycle
			m.pose_state("carried", 0.0, 2.5, 0.11 * i)
			eq(m.bow_shield_overlap(), 0, "%s: walking (t %.2f): the crossbow clear of the shield" % [carry, 0.11 * i])
		for k in 21:   # reloading (0) up to aiming (1), the whole raise
			var aim := k / 20.0
			for t: float in [0.0, 0.3]:
				m.pose_state("planted", aim, 0.0, t, aim >= 1.0)
				var hits := m.bow_shield_hits()
				check(hits.is_empty(), "%s: planted, aim %.2f (0 = reloading): the crossbow clear of the shield (%d points inside, e.g. %s in the shield's space)" % [
						carry, aim, hits.size(), str(hits[0]) if not hits.is_empty() else ""])
		for st: String in ["carried", "left", "dropped", "broken"]:
			m.pose_state(st, 0.0, 0.0, 0.6)
			eq(m.bow_shield_overlap(), 0, "%s: %s: the crossbow clear of the shield" % [carry, st])
		m.queue_free()
	# the check itself: a crossbow pushed into the boards is caught
	var probe := PaviseModel.new("side")
	add_child(probe)
	probe.pose_state("planted", 1.0)
	(probe.get_part("weapon") as Node3D).position = (probe.get_part("shield") as Node3D).position + Vector3(0, 0.8, 0)
	check(probe.bow_shield_overlap() > 20, "a crossbow inside the boards is found")
	probe.queue_free()
	finish()
