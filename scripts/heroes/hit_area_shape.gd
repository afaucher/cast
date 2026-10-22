class_name HitAreaShape
extends RefCounted
## The outline of a melee hit area (Hero.melee_area(): a wedge {"shape": "arc", reach, arc} or a lane {"shape": "lane", near,
## far, radius, end_radius?}) in the attacker's own frame: x to its side, y forward. Shared by the strike lab's overlay
## (scripts/art/lowpoly/strike_lab.gd) and the test gym's hit-area overlay (GymOverlay). Drawing only: Combat decides hits.


## The area's outline, grown by `grow` (a lane's capsule; a wedge's fan from the attacker's centre).
static func outline(area: Dictionary, grow: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if str(area["shape"]) == "lane":
		var r := float(area["radius"]) + grow
		var near := float(area["near"])
		var far := float(area["far"])
		for k in 13:
			var a := PI * k / 12.0
			pts.append(Vector2(r * cos(a), near - r * sin(a)))
		for k in 13:
			var a := PI * k / 12.0
			pts.append(Vector2(-r * cos(a), far + r * sin(a)))
		return pts
	var reach := float(area["reach"]) + grow
	var half := deg_to_rad(minf(float(area["arc"]), 360.0) * 0.5)
	if float(area["arc"]) < 360.0:
		pts.append(Vector2.ZERO)
	for k in 25:
		var a := -half + 2.0 * half * k / 24.0
		pts.append(Vector2(sin(a), cos(a)) * reach)
	return pts


## A circle of n points round c.
static func circle(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n:
		pts.append(c + Vector2(cos(TAU * k / n), sin(TAU * k / n)) * r)
	return pts


## A lane's disc at its far end (the smash's landing), {} when it has none: {center: Vector2, r}.
static func end_disc(area: Dictionary) -> Dictionary:
	var end := float(area.get("end_radius", 0.0))
	if str(area["shape"]) != "lane" or end <= 0.0:
		return {}
	return {"center": Vector2(0.0, float(area["far"])), "r": end}
