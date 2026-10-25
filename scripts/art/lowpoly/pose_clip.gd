class_name PoseClip
extends RefCounted
## How deep a faceted hero's arms sink into its own body right now (the user, 2026-10-22, on Gasket's smash: "the arm
## penetrates the body and disappears when the hammer comes down"). A measure for the strike lab (--clipcheck) and
## test_move_feel_anim: each arm's centre line, from a little past the shoulder to the fist, is sampled and every sample is
## tested against the body parts' boxes (each part mesh's own AABB, in that part's space, shrunk by MARGIN so a sleeve
## brushing a coat's edge is fine). An arm split at the elbow (elbow IK) is sampled along its upper arm and forearm. Returns
## the deepest a sample sits inside a box (0 = clear).

const MARGIN := 0.05
const SAMPLES := 12
const FROM := 0.4              ## the first sample's share of the way from the shoulder (the shoulder itself sits in the yoke)

## kit -> [body part names, [arm part, fist (in that arm part's space, or a part name whose origin is the fist)], ...]
const ARMS := {
	"gasket": [["body", "head", "beard", "coat", "belt"], [["arm_r", "weapon"], ["arm_l", Vector3(0, -0.76, 0)]]],
	"rebar": [["body", "head", "vest", "belt"], [["arm_r", "glove_r"], ["arm_l", "glove_l"]]],
	"wick": [["body", "head", "jacket", "belt"], [["arm_r", Vector3(0, -0.64, 0)], ["arm_l", Vector3(0, -0.64, 0)]]],
}


## The deepest any arm's sample sits inside a body part (world units) and which ("arm_r in beard"), as [depth, text].
static func depth(m: LowPolyModel, kit: String) -> Array:
	var spec: Array = ARMS[kit]
	var boxes := []
	for pn: String in spec[0]:
		var p := m.parts[pn] as MeshInstance3D
		var bb := p.mesh.get_aabb().grow(-MARGIN)
		boxes.append([pn, p.global_transform, bb])
	var worst := 0.0
	var what := ""
	for arm: Array in spec[1]:
		var a := m.parts[arm[0]] as Node3D
		var s := a.global_position
		var f: Vector3 = (m.parts[arm[1]] as Node3D).global_position if arm[1] is String else a.global_transform * (arm[1] as Vector3)
		# an IK arm (elbow IK) bends: sample shoulder -> elbow -> hand instead of the straight line
		var side := String(arm[0]).substr(4)
		var el := s
		if m.parts.has("fore_" + side):
			el = (m.parts["fore_" + side] as Node3D).global_position
			if not (arm[1] is String):
				f = m.ik_hand(side)
		for k in SAMPLES:
			var u := lerpf(FROM, 1.0, float(k) / (SAMPLES - 1))
			var q := s.lerp(f, u)
			if el != s:
				var l1 := s.distance_to(el)
				var at := u * (l1 + el.distance_to(f))
				q = s.lerp(el, at / maxf(l1, 0.0001)) if at <= l1 else el.lerp(f, (at - l1) / maxf(el.distance_to(f), 0.0001))
			for b: Array in boxes:
				var l: Vector3 = (b[1] as Transform3D).affine_inverse() * q
				var bb: AABB = b[2]
				if not bb.has_point(l):
					continue
				var d := minf(minf(minf(l.x - bb.position.x, bb.end.x - l.x), minf(l.y - bb.position.y, bb.end.y - l.y)), minf(l.z - bb.position.z, bb.end.z - l.z))
				d *= (b[1] as Transform3D).basis.get_scale().x
				if d > worst:
					worst = d
					what = "%s in %s" % [arm[0], b[0]]
	return [worst, what]
