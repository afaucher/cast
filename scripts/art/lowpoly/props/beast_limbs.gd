class_name BeastLimbs
extends RefCounted
## The centrelines of the hellgate beast's tentacles (HellgateBeast) and the clearance rules that keep them out of each
## other, out of themselves and out of the level, at rest AND in every pose the shader can give them.
##
## A limb (Path) is a centreline resampled every STEP world units (point i sits at s = i * STEP along it), a tube radius
## per point, and a motion weight per point (`free`: 0 where it grips, 1 at the tip; smoothstep(grip_end, length, s), the
## same curve BeastFlesh's shader uses). Its ENVELOPE at a point is everything the shader can put there:
##   env(i) = radius * ENV_K (the ring jitter, the suckers, the beat's swell) + free(i) * motion() (the sway, the low-HP
##   writhe and the hurt flail at their largest: MOTION_K * (sway_amp * SWAY_WRITHE + FLAIL_MAX)).
## The exits move every vertex BACK along its own centreline with a radius no bigger than the one already there (the
## tubes taper), so a limb whose envelope is clear at rest is clear through its whole exit too.
##
## Clearance (positive = clear, in world units beyond MARGIN):
##   level: Level.sdf(p) (a conservative distance to the terrain columns and the room's props) minus env, at every
##          point and every segment midpoint;
##   self:  segment to segment, for segments further apart along the limb than their envelopes can bend round;
##   limbs: segment to segment against every limb already placed on the floor (every beast's), envelopes summed;
##   spines: each obsidian spine's tip as a small ball, against the level and the other limbs.

const STEP := 0.3            ## world units between centreline points (the skeleton texture's column spacing)
const MARGIN := 0.03         ## clearance kept beyond the envelopes
const ENV_K := 1.2           ## a tube's widest point (jitter, suckers, swell) as a multiple of its radius
const FLAIL_MAX := 0.32      ## world units: the hurt flail (and the whip's lash) at a tip, at most
const SWAY_WRITHE := 1.5     ## low gate HP multiplies the sway by up to this
const MOTION_K := 1.17       ## |side * a + up * 0.6 * a| <= 1.17 a
const SPINE_R := 0.04        ## a spine's tip, as a ball
const WAVE_K := 0.35         ## the sway's phase lag per world unit along a limb (the shader's wave_k)
const FLAIL_K := 0.5         ## the flail's phase lag per world unit along a limb (the shader's flail_k)

## Hex footprints: the 19 cells within two steps of a cell.
static var _near: Array[Vector2i] = []
## Measuring only (labs, tests): envelopes without the motion (the resting tube).
static var rest_only := false
static var debug_self := false
static var dbg := ""
## Where the last clearances() found its worst value (labs: the before / after pictures).
static var worst_at := Vector3.ZERO
static var _best := 1.0e9


class Path extends RefCounted:
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var free := PackedFloat32Array()
	var xs := PackedVector3Array()          ## ring frames (parallel transport): x, y; the tangent is x cross y
	var ys := PackedVector3Array()
	var ts := PackedVector3Array()
	var grip_end := 0.0                     ## s where the free part starts
	var sway_amp := 0.1                     ## the tip's sway amplitude at rest (world units)
	## The one horizontal axis the free part sways and flails along (with some up and down): one axis for the whole limb,
	## so its points move alike and never fold into each other.
	var side := Vector3.RIGHT
	## Obsidian spines: [{i, dir (world, unit), h (length), r (base radius)}]: their tips are checked like small balls.
	var spines: Array[Dictionary] = []
	var lo := Vector3.ZERO                  ## bounding box (envelopes included)
	var hi := Vector3.ZERO

	func size() -> int:
		return pts.size()

	func length() -> float:
		return STEP * float(pts.size() - 1)

	func motion() -> float:
		return MOTION_K * (sway_amp * SWAY_WRITHE + FLAIL_MAX)

	func env(i: int) -> float:
		return radii[i] * ENV_K + (0.0 if BeastLimbs.rest_only else free[i] * motion())

	func spine_tip(sp: Dictionary) -> Vector3:
		var i: int = sp["i"]
		return pts[i] + (sp["dir"] as Vector3) * (radii[i] * 0.8 + float(sp["h"]))

	func update_box() -> void:
		lo = Vector3.INF
		hi = -Vector3.INF
		for i in pts.size():
			var e := env(i)
			lo = lo.min(pts[i] - Vector3.ONE * e)
			hi = hi.max(pts[i] + Vector3.ONE * e)
		for sp in spines:
			var tip := spine_tip(sp)
			lo = lo.min(tip - Vector3.ONE * 0.5)
			hi = hi.max(tip + Vector3.ONE * 0.5)


## The terrain (hex columns from the slab's underside up to each cell's top) and the room's props (upright cylinders),
## as a conservative signed distance.
class Level extends RefCounted:
	var map: HexMap
	var bottom := -1.0
	var cyls: Array[Vector4] = []         ## (x, z, radius, top y): props, decor, the gate; they stand on the floor
	var _tops := {}                       ## cell -> top y (cached)

	func _init(m: HexMap) -> void:
		map = m
		bottom = HexMapView.FLOOR_DEPTH * Hex.LEVEL_HEIGHT
		if BeastLimbs._near.is_empty():
			BeastLimbs._near.assign(Hex.range_cells(Vector2i.ZERO, 2))

	func add_cylinder(xz: Vector2, radius: float, top: float) -> void:
		cyls.append(Vector4(xz.x, xz.y, radius, top))

	## A column: (centre x, centre z, top y), or y = NAN for void (cached).
	func _column(c: Vector2i) -> Vector3:
		var hit: Variant = _tops.get(c)
		if hit != null:
			return hit
		var cell := map.get_cell(c)
		var t := NAN
		if cell != null:
			var lv := cell.level
			if cell.type == HexMap.Tile.STAIRS:
				lv += cell.stair_rise
			if cell.wall_mask != 0:
				lv = maxi(lv, cell.wall_top)
			t = float(lv) * Hex.LEVEL_HEIGHT
		var cw := Hex.to_world(c)
		var col := Vector3(cw.x, cw.z, t)
		_tops[c] = col
		return col

	## Distance from p to the nearest solid (negative inside). Hex columns use the three-slab hexagon distance, which never
	## overestimates, so a clear result is really clear.
	func sdf(p: Vector3) -> float:
		return sdf_grad(p).w

	## The distance (w) and its gradient (xyz: the way out of the nearest solid), in one pass.
	func sdf_grad(p: Vector3) -> Vector4:
		var best := 6.0
		var g := Vector3.UP
		var home := Hex.from_world(p)
		for off in BeastLimbs._near:
			var col := _column(home + off)
			var top := col.z
			if is_nan(top):
				continue
			var qx := p.x - col.x
			var qz := p.z - col.y
			# the hexagon as three slabs (edge normals at 0, 60 and 120 degrees: Hex.dir_vector(0..2))
			var a0 := qx
			var a1 := qx * 0.5 - qz * 0.8660254
			var a2 := qx * 0.5 + qz * 0.8660254
			var dh := absf(a0)
			var gh := Vector3(signf(a0), 0.0, 0.0)
			if absf(a1) > dh:
				dh = absf(a1)
				gh = Vector3(0.5, 0.0, -0.8660254) * signf(a1)
			if absf(a2) > dh:
				dh = absf(a2)
				gh = Vector3(0.5, 0.0, 0.8660254) * signf(a2)
			dh -= Hex.INNER
			var below := bottom - p.y
			var above := p.y - top
			var dv := maxf(below, above)
			var gv := Vector3(0, -1, 0) if below > above else Vector3(0, 1, 0)
			var d := 0.0
			var gd := Vector3.ZERO
			if dh > 0.0 and dv > 0.0:
				d = sqrt(dh * dh + dv * dv)
				gd = (gh * dh + gv * dv) / d
			elif dh > dv:
				d = dh
				gd = gh
			else:
				d = dv
				gd = gv
			if d < best:
				best = d
				g = gd
		for cy in cyls:
			var rx := p.x - cy.x
			var rz := p.z - cy.y
			var rl := sqrt(rx * rx + rz * rz)
			var gh2 := Vector3(rx / rl, 0.0, rz / rl) if rl > 0.0001 else Vector3.RIGHT
			var dh2 := rl - cy.z
			var below2 := bottom - p.y
			var above2 := p.y - cy.w
			var dv2 := maxf(below2, above2)
			var gv2 := Vector3(0, -1, 0) if below2 > above2 else Vector3(0, 1, 0)
			var d2 := 0.0
			var gd2 := Vector3.ZERO
			if dh2 > 0.0 and dv2 > 0.0:
				d2 = sqrt(dh2 * dh2 + dv2 * dv2)
				gd2 = (gh2 * dh2 + gv2 * dv2) / d2
			elif dh2 > dv2:
				d2 = dh2
				gd2 = gh2
			else:
				d2 = dv2
				gd2 = gv2
			if d2 < best:
				best = d2
				g = gd2
		return Vector4(g.x, g.y, g.z, best)


# ------------------------------------------------------------------ building a path

## A Path from control points (Catmull-Rom through them, resampled every STEP). `grip_idx`: the control point where the
## free part (the tip) starts; sway_amp: the tip's sway at rest.
static func from_ctrl(ctrl: Array[Vector3], rad: Array[float], grip_idx: int, sway_amp: float) -> Path:
	var dense: Array[Vector3] = []
	var dr: Array[float] = []
	var dense_grip := 0
	var n := ctrl.size()
	for i in n - 1:
		var p0 := ctrl[maxi(i - 1, 0)]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[mini(i + 2, n - 1)]
		if i == grip_idx:
			dense_grip = dense.size()
		for j in 10:
			var u := float(j) / 10.0
			var u2 := u * u
			var u3 := u2 * u
			dense.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3))
			dr.append(lerpf(rad[i], rad[i + 1], u))
	dense.append(ctrl[n - 1])
	dr.append(rad[n - 1])
	var grip_s := 0.0
	for i in range(1, dense_grip + 1):
		grip_s += dense[i].distance_to(dense[i - 1])
	var p := Path.new()
	p.sway_amp = sway_amp
	_resample(p, dense, dr)
	p.grip_end = minf(grip_s, p.length() - STEP)
	refresh(p)
	return p


## Resample a polyline (with a radius per point) at exact multiples of STEP into `p`.
static func _resample(p: Path, src: Array[Vector3], src_r: Array[float]) -> void:
	p.pts = PackedVector3Array([src[0]])
	p.radii = PackedFloat32Array([src_r[0]])
	var want := STEP
	var acc := 0.0
	for i in range(1, src.size()):
		var a := src[i - 1]
		var b := src[i]
		var l := a.distance_to(b)
		while acc + l >= want and l > 0.000001:
			var f := (want - acc) / l
			p.pts.append(a.lerp(b, f))
			p.radii.append(lerpf(src_r[i - 1], src_r[i], f))
			want += STEP
		acc += l


## Frames, motion weights and the box, after the points changed.
static func refresh(p: Path) -> void:
	var n := p.pts.size()
	p.xs.resize(n)
	p.ys.resize(n)
	p.ts.resize(n)
	p.free.resize(n)
	var ref := Vector3.UP
	var total := p.length()
	for i in n:
		var t := (p.pts[mini(i + 1, n - 1)] - p.pts[maxi(i - 1, 0)]).normalized()
		if absf(t.dot(ref)) > 0.97:
			ref = Vector3.RIGHT if absf(t.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		var x := ref.cross(t).normalized()
		var y := t.cross(x).normalized()
		ref = y
		p.xs[i] = x
		p.ys[i] = y
		p.ts[i] = x.cross(y)
		p.free[i] = smoothstep(p.grip_end, total, float(i) * STEP)
	p.update_box()


## Push every point (and both ends of every segment whose midpoint) whose envelope reaches into the level back out along
## the distance's gradient. The first passes resample (the points stay STEP apart), the last ones do not (resampling
## would pull a chord back into a corner; the shader maps each point by its index, so a little uneven spacing is fine).
static func push_out(p: Path, lv: Level, passes: int = 8) -> void:
	var extra := MARGIN + 0.05
	for pass_i in passes:
		var moved := false
		var n := p.pts.size()
		var push := PackedVector3Array()
		push.resize(n)
		for i in n:
			var need := p.env(i) + extra
			var dg := lv.sdf_grad(p.pts[i])
			if dg.w < need:
				push[i] += Vector3(dg.x, dg.y, dg.z) * (need - dg.w)
				moved = true
			if i > 0:
				var m := (p.pts[i] + p.pts[i - 1]) * 0.5
				var need_m := maxf(p.env(i), p.env(i - 1)) + extra
				var mg := lv.sdf_grad(m)
				if mg.w < need_m:
					var g := Vector3(mg.x, mg.y, mg.z) * (need_m - mg.w)
					push[i] += g
					push[i - 1] += g
					moved = true
		if not moved:
			break
		for i in n:
			p.pts[i] += push[i]
		if pass_i < passes - 3:
			var src: Array[Vector3] = []
			var src_r: Array[float] = []
			for i in n:
				src.append(p.pts[i])
				src_r.append(p.radii[i])
			var g := p.grip_end
			_resample(p, src, src_r)
			p.grip_end = minf(g, p.length() - STEP)
		refresh(p)


# ------------------------------------------------------------------ clearances

## The least level clearance along the limb (points, segment midpoints and spine tips).
static func level_clearance(p: Path, lv: Level) -> float:
	var worst := 1.0e9
	for i in p.pts.size():
		worst = _note(worst, lv.sdf(p.pts[i]) - p.env(i), p.pts[i])
		if i > 0:
			var m := (p.pts[i] + p.pts[i - 1]) * 0.5
			worst = _note(worst, lv.sdf(m) - maxf(p.env(i), p.env(i - 1)), m)
	for sp in p.spines:
		var i: int = sp["i"]
		var tip := p.spine_tip(sp)
		worst = _note(worst, lv.sdf(tip) - SPINE_R - (0.0 if rest_only else p.free[i] * p.motion()), tip)
	return worst


## minf that remembers where the overall worst value was (worst_at).
static func _note(worst: float, v: float, at: Vector3) -> float:
	if v < _best:
		_best = v
		worst_at = at
	return minf(worst, v)


## The least clearance between a limb and itself: segments further apart along it than the RESTING tube can bend round
## (the window), each pair needing its two resting radii plus how far the motion can bring them together. Two points of
## one limb move alike (along the same axes, Path.side and up): they differ only by their motion weights and by the
## phase lag along the limb (the sway's WAVE_K, the flail's FLAIL_K), so that relative bound is used, not the sum of
## the two envelopes.
static func self_clearance(p: Path) -> float:
	var worst := 1.0e9
	var n := p.pts.size()
	var rest := PackedFloat32Array()
	rest.resize(n)
	for i in n:
		rest[i] = p.radii[i] * ENV_K
	var amp := p.sway_amp * SWAY_WRITHE + FLAIL_MAX
	var lag := p.sway_amp * SWAY_WRITHE * WAVE_K + FLAIL_MAX * FLAIL_K
	for i in n - 1:
		var ri := maxf(rest[i], rest[i + 1])
		var pi := p.pts[i]
		for j in range(i + 2, n - 1):
			var rj := maxf(rest[j], rest[j + 1])
			var ds := float(j - i) * STEP
			if ds <= (ri + rj) * 1.6 + STEP:
				continue
			var rel := 0.0
			var wi := maxf(p.free[i], p.free[i + 1])
			var wj := maxf(p.free[j], p.free[j + 1])
			if not rest_only:
				# the most the two can move apart along the limb's axes (side, and up at 0.6 of it)...
				rel = absf(wi - wj) * amp + maxf(wi, wj) * lag * (ds + STEP)
			# (two segments STEP long whose starts are further apart than this can't come closer than the check needs)
			if pi.distance_to(p.pts[j]) > ri + rj + rel * MOTION_K + 2.0 * STEP + 0.5:
				continue
			var cp := Geometry3D.get_closest_points_between_segments(pi, p.pts[i + 1], p.pts[j], p.pts[j + 1])
			var gap := cp[1] - cp[0]
			var d := gap.length()
			# ...counts only along the line between their closest points: |a + D| >= |a| - |D . a^|, and D = side * x +
			# up * y with |x| <= rel, |y| <= 0.6 rel. Never more than the two envelopes' sum.
			var toward := 1.17
			var across := 1.0
			if d > 0.0001:
				var c := gap / d
				toward = absf(p.side.dot(c)) + 0.6 * absf(c.y)
				# Two cross-sections of one limb lying ALONG it (a straight stretch) don't touch however close they get, as
				# long as they keep their order; lying ACROSS it (a bend coming back) they need both radii.
				var ai := absf(c.dot(p.ts[i]))
				var aj := absf(c.dot(p.ts[j]))
				across = maxf(sqrt(maxf(0.0, 1.0 - ai * ai)), sqrt(maxf(0.0, 1.0 - aj * aj)))
			var closing := minf(rel * toward, (wi + wj) * p.motion())
			var need := (ri + rj) * across + closing
			if debug_self and d - need < worst:
				dbg = "i %d j %d (of %d, grip %.1f) d %.2f ri %.2f rj %.2f across %.2f wi %.2f wj %.2f closing %.2f toward %.2f" % [
						i, j, n, p.grip_end, d, ri, rj, across, wi, wj, closing, toward]
			worst = _note(worst, d - need, pi)
	if debug_self and worst < MARGIN:
		print("    self: ", dbg)
	return worst


## The least clearance between two limbs (envelopes and spine tips).
static func pair_clearance(a: Path, b: Path) -> float:
	if not _boxes_meet(a, b):
		return 1.0e9
	var worst := 1.0e9
	for i in a.pts.size() - 1:
		var ea := maxf(a.env(i), a.env(i + 1))
		var alo := a.pts[i].min(a.pts[i + 1]) - Vector3.ONE * ea
		var ahi := a.pts[i].max(a.pts[i + 1]) + Vector3.ONE * ea
		if alo.x > b.hi.x or alo.y > b.hi.y or alo.z > b.hi.z or ahi.x < b.lo.x or ahi.y < b.lo.y or ahi.z < b.lo.z:
			continue
		for j in b.pts.size() - 1:
			var eb := maxf(b.env(j), b.env(j + 1))
			var d := seg_seg(a.pts[i], a.pts[i + 1], b.pts[j], b.pts[j + 1])
			worst = _note(worst, d - ea - eb, a.pts[i])
	for sp in a.spines:
		var mo := 0.0 if rest_only else a.free[int(sp["i"])] * a.motion()
		worst = _note(worst, _point_clearance(a.spine_tip(sp), SPINE_R + mo, b), a.spine_tip(sp))
	for sp in b.spines:
		var mo := 0.0 if rest_only else b.free[int(sp["i"])] * b.motion()
		worst = _note(worst, _point_clearance(b.spine_tip(sp), SPINE_R + mo, a), b.spine_tip(sp))
	return worst


static func _point_clearance(q: Vector3, r: float, p: Path) -> float:
	var worst := 1.0e9
	for i in p.pts.size() - 1:
		var d := Geometry3D.get_closest_point_to_segment(q, p.pts[i], p.pts[i + 1]).distance_to(q)
		worst = minf(worst, d - r - maxf(p.env(i), p.env(i + 1)))
	return worst


static func _boxes_meet(a: Path, b: Path) -> bool:
	return not (a.lo.x > b.hi.x or a.lo.y > b.hi.y or a.lo.z > b.hi.z or a.hi.x < b.lo.x or a.hi.y < b.lo.y or a.hi.z < b.lo.z)


## Closest distance between segments p1-q1 and p2-q2.
static func seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var pts := Geometry3D.get_closest_points_between_segments(p1, q1, p2, q2)
	return pts[0].distance_to(pts[1])


## Every clearance of a limb against the level, itself and the limbs already placed: {level, self, limbs, worst}
## (worst_at: where the worst one is).
static func clearances(p: Path, lv: Level, others: Array) -> Dictionary:
	_best = 1.0e9
	var l := level_clearance(p, lv)
	var s := self_clearance(p)
	var o := 1.0e9
	for q: Path in others:
		o = minf(o, pair_clearance(p, q))
	return {"level": l, "self": s, "limbs": o, "worst": minf(l, minf(s, o))}
