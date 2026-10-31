class_name ProcessionPath
extends RefCounted
## A polyline measured by arc length (docs/design/haunted-build-plan.md, "H4 as built"): the file of a procession walks it, each
## walker GAP behind the one before. Shared by the game's procession (Procession: the trail its leader leaves, growing at the
## head and trimmed at the tail) and the look-dev's (NecroProcession: a closed oval it laps, the caller wrapping the arc).
## Plain data: no nodes, no dice.
##
## Arcs are absolute: `tail_arc()` is where the first kept point sits (it moves up as the tail is trimmed), `head_arc()` where
## the last one does. point(at) clamps to them.

var pts := PackedVector3Array()
var cum := PackedFloat64Array()     ## the arc length at each point (absolute)


## A path through `points`, starting at arc `from`.
static func through(points: Array[Vector3], from: float = 0.0) -> ProcessionPath:
	var p := ProcessionPath.new()
	for q in points:
		p.add(q, from)
	return p


## Append a point at the head (`base`: the arc of the very first point).
func add(q: Vector3, base: float = 0.0) -> void:
	if pts.is_empty():
		pts.append(q)
		cum.append(base)
		return
	cum.append(cum[cum.size() - 1] + q.distance_to(pts[pts.size() - 1]))
	pts.append(q)


func is_empty() -> bool:
	return pts.is_empty()


func head_arc() -> float:
	return cum[cum.size() - 1] if not cum.is_empty() else 0.0


func tail_arc() -> float:
	return cum[0] if not cum.is_empty() else 0.0


func length() -> float:
	return head_arc() - tail_arc()


func head() -> Vector3:
	return pts[pts.size() - 1] if not pts.is_empty() else Vector3.ZERO


## The path at arc `at` (clamped to the path): {pos, dir} (dir the way it runs, flat).
func point(at: float) -> Dictionary:
	if pts.size() < 2:
		return {"pos": pts[0] if not pts.is_empty() else Vector3.ZERO, "dir": Vector3.FORWARD}
	var u := clampf(at, tail_arc(), head_arc())
	var lo := 1
	var hi := cum.size() - 1
	while lo < hi:   # (the first point whose arc reaches u)
		var mid := (lo + hi) >> 1
		if cum[mid] < u:
			lo = mid + 1
		else:
			hi = mid
	var seg := cum[lo] - cum[lo - 1]
	var k := (u - cum[lo - 1]) / seg if seg > 0.0 else 0.0
	var d := pts[lo] - pts[lo - 1]
	d.y = 0.0
	return {"pos": pts[lo - 1].lerp(pts[lo], k), "dir": d.normalized() if d.length() > 0.0001 else Vector3.FORWARD}


## Forget the points wholly before arc `before` (the one that spans it stays).
func trim(before: float) -> void:
	var n := 0
	while n + 1 < cum.size() and cum[n + 1] <= before:
		n += 1
	if n > 0:
		pts = pts.slice(n)
		cum = cum.slice(n)
