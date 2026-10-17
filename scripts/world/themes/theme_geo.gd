class_name ThemeGeo
extends RefCounted
## Pure 2D geometry for the room themes. World X/Z points are Vector2 (x, z). A yaw is degrees about +Y with
## the model's front (+Z) at yaw 0, so facing(yaw) = (sin yaw, cos yaw) and lateral(yaw) (the model's +X) =
## (cos yaw, -sin yaw). A footprint is an oriented rectangle: w along the lateral axis, d along the facing.

const GAP := 0.06                ## clearance between a wall-backed prop's back and the wall face
const JITTER := 8.0              ## yaw jitter (degrees, +-) on top of an orientation rule; the rule allows 10

## Where the game camera sits, as a unit X/Z vector from the scene (ortho yaw 45): pieces that face this way show
## their front to the player; one on a near wall shows its back. Placement prefers the far walls.
const CAMERA_DIR := Vector2(0.7071, 0.7071)

static var _normals: Array[Vector2] = []


## The six hex face normals (world X/Z), index = Hex.DIRS index.
static func normals() -> Array[Vector2]:
	if _normals.is_empty():
		for d in 6:
			var v := Hex.dir_vector(d)
			_normals.append(Vector2(v.x, v.z))
	return _normals


static func v2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func cell_of(p: Vector2) -> Vector2i:
	return Hex.from_world(Vector3(p.x, 0.0, p.y))


static func world(c: Vector2i) -> Vector2:
	var w := Hex.to_world(c)
	return Vector2(w.x, w.z)


static func facing(yaw_deg: float) -> Vector2:
	var r := deg_to_rad(yaw_deg)
	return Vector2(sin(r), cos(r))


static func lateral(yaw_deg: float) -> Vector2:
	var r := deg_to_rad(yaw_deg)
	return Vector2(cos(r), -sin(r))


static func yaw_of(f: Vector2) -> float:
	return rad_to_deg(atan2(f.x, f.y))


## A point `lx` to the model's right and `lf` ahead of `pos` for a model at `yaw`.
static func local_to_world(pos: Vector2, yaw_deg: float, lx: float, lf: float) -> Vector2:
	return pos + lateral(yaw_deg) * lx + facing(yaw_deg) * lf


## Smallest angle (degrees, 0..180) between two yaws.
static func yaw_diff(a: float, b: float) -> float:
	return absf(wrapf(a - b, -180.0, 180.0))


## Angle (degrees, 0..180) between a facing vector and a direction.
static func angle_to(f: Vector2, dir: Vector2) -> float:
	if f.length() < 0.0001 or dir.length() < 0.0001:
		return 0.0
	return absf(rad_to_deg(f.angle_to(dir)))


## Signed distance from world point p to cell c's hexagon (negative inside). Exact on the faces, a
## slight underestimate past a corner (so clearance tests stay on the safe side).
static func hex_dist(p: Vector2, c: Vector2i) -> float:
	var rel := p - world(c)
	var m := -INF
	for n in normals():
		m = maxf(m, rel.dot(n))
	return m - Hex.INNER


## The unit normal of the face of cell c nearest to point p (pointing from the cell toward p).
static func nearest_face(p: Vector2, c: Vector2i) -> Vector2:
	var rel := p - world(c)
	var best := Vector2.ZERO
	var m := -INF
	for n in normals():
		var d := rel.dot(n)
		if d > m:
			m = d
			best = n
	return best


## Sample points of an oriented footprint: a grid over the rectangle (corners, edges and the middle).
static func foot_points(pos: Vector2, yaw_deg: float, w: float, d: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var nx := clampi(int(ceilf(w / 0.8)), 1, 7)
	var nz := clampi(int(ceilf(d / 0.8)), 1, 4)
	for i in nx + 1:
		var lx := lerpf(-w * 0.5, w * 0.5, float(i) / float(nx))
		for j in nz + 1:
			var lf := lerpf(-d * 0.5, d * 0.5, float(j) / float(nz))
			out.append(local_to_world(pos, yaw_deg, lx, lf))
	return out


## Overlap test between two footprints given as (pos, yaw, w, d); `tol` is how far they may interpenetrate.
static func overlap(p1: Vector2, yaw1: float, w1: float, d1: float, p2: Vector2, yaw2: float, w2: float, d2: float, tol: float = 0.0) -> bool:
	var l1 := lateral(yaw1)
	var f1 := facing(yaw1)
	var l2 := lateral(yaw2)
	var f2 := facing(yaw2)
	var delta := p2 - p1
	for axis: Vector2 in [l1, f1, l2, f2]:
		var e1 := absf(axis.dot(l1)) * w1 * 0.5 + absf(axis.dot(f1)) * d1 * 0.5
		var e2 := absf(axis.dot(l2)) * w2 * 0.5 + absf(axis.dot(f2)) * d2 * 0.5
		if absf(axis.dot(delta)) > e1 + e2 - tol:
			return false
	return true
