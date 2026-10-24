class_name TwoBoneIK
extends RefCounted
## An analytic two-bone IK for the code-built faceted limbs: a shoulder, an upper arm, a forearm and a hand target, with
## a bend direction (the "pole") so an elbow folds the natural way. The elbow study (docs/design/animation-research.md,
## "Elbow IK study (2026-10-24)"; the user: "Looking to see if an IK solver for elbows would make animations look
## better"). LowPolyModel.pose_ik_arm lays two parts on it; the gym's "Elbows" picker (LowPolyModel.elbow_ik) switches the
## models that have split arms (Gasket, the grunt).
##
## Pure maths, no state: every machine poses its own copy of a model, so this is a look and carries nothing on the net.
## All points are in one space (the parent's of the upper arm). The law of cosines gives the elbow's angle; the pole's
## part across the root-to-target line says which way it sticks out.

## The straightest a chain goes, as a share of its full length: a dead-straight chain has no bend direction, so the elbow
## would flip from one frame to the next.
const REACH := 0.999
## The most folded a chain goes, as a share of its full length (a hand never passes through its own shoulder).
const FOLD := 0.08


## The elbow and the end of the chain root -> elbow -> end (bone lengths l1, l2) reaching for `target`: the end is the
## target when the chain can reach it, else the nearest point it can reach on the line from the root (clamped between
## FOLD and REACH of l1 + l2, and never closer than |l1 - l2|). The elbow bends toward `pole` (a direction; only its part
## across the root-to-target line counts). Returns [elbow, end].
static func solve(root: Vector3, target: Vector3, l1: float, l2: float, pole: Vector3) -> PackedVector3Array:
	var d := target - root
	var dist := d.length()
	var dir := d / dist if dist > 0.00001 else Vector3.DOWN
	var full := l1 + l2
	dist = clampf(dist, maxf(absf(l1 - l2) + 0.0001, full * FOLD), full * REACH)
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var bend := across(pole, dir)
	var elbow := root + dir * (l1 * cos_a) + bend * (l1 * sqrt(1.0 - cos_a * cos_a))
	return PackedVector3Array([elbow, root + dir * dist])


## The unit part of `v` across the unit `axis` (a steady perpendicular when `v` lies along it).
static func across(v: Vector3, axis: Vector3) -> Vector3:
	var p := v - axis * axis.dot(v)
	if p.length_squared() < 0.000001:
		p = Vector3.BACK - axis * axis.z
		if p.length_squared() < 0.000001:
			p = Vector3.RIGHT - axis * axis.x
	return p.normalized()


## The basis of a bone part whose soup hangs down its local -Y from its pivot, laid from `from` to `to`, its local +Z turned
## toward `side` (the elbow's outer side) so the limb does not twist as it swings.
static func bone_basis(from: Vector3, to: Vector3, side: Vector3) -> Basis:
	var y := (from - to).normalized()
	var z := across(side, y)
	return Basis(y.cross(z), y, z)


## A bend direction for an arm on `side` (-1 left, +1 right; the model faces -Z) whose hand lies along `dir` from the
## shoulder: the elbow out to the side, back while the hand is low, forward once the hand is up by the head (a raised
## sword or wrench is held with the elbow out in front, a hanging arm bends with the elbow behind).
static func arm_pole(side: int, dir: Vector3, out: float = 0.8) -> Vector3:
	var up := smoothstep(-0.15, 0.65, dir.y)
	return Vector3(out * side, -0.3, lerpf(0.7, -0.6, up))


## The IK target for an arm posed by rotations: where the old rigid arm put its hand (`shoulder` + `rot` * `hand_local`),
## drawn in toward the shoulder by `flex` (0 straight, 1 at the shoulder). The solver then bends the elbow to meet it.
static func flexed(shoulder: Vector3, rot: Basis, hand_local: Vector3, flex: float) -> Vector3:
	return shoulder + (rot * hand_local) * (1.0 - clampf(flex, 0.0, 0.9))
