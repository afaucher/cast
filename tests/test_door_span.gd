extends MonsterTestBase
## Office doors stand across the SHORTEST span of their opening, square to the hall (user, 2026-10-21: "normal doors would
## be placed perpendicular to the hall, or at least prioritize the shortest span"; Doorways._square_place). Over SEEDS
## contract seeds x 3 floors, built the way the game builds them (DungeonGen.for_run, SiteBuilder.plan), every planned door
## (office and service style):
##   - is no longer than the shortest valid cut of its opening (+ TOL): a chord between two hex centres (wall corners or
##     wall-face points) crossing the corridor's centre line within the opening's reach, wall to wall (both ends run on into
##     wall), over open level floor (brute force, not the planner's own search);
##   - is square to the hall (its line at 90 degrees to the axis) wherever a square valid cut exists, and no square cut of
##     the same length stands nearer the room (the door is at the mouth, not down the hall);
##   - SEALS the opening: a flood over the floor round it (wall and the shut door's line blocking, 0.1 apart) from the
##     room side never reaches the hall side within FLOOD_HALF of the door;
##   - keeps its doorway cell a full cell on the hall side of the door line (in the hall's space once settled), and its
##     band's cut cells at the jambs;
##   - and the FOG's spaces agree (Doorways.settle, what RoomFog builds on): the floor just past the door on the room side is
##     the room's space, on the hall side the hall's, so a hero in front of a shut door is never "in" the space behind it.
## And the stats: how many doors, their mean span, how many are square.

const SEEDS := 30
const FLOORS := 3
const TOL := 0.05
const REACH_BACK := 2.5          ## cuts are looked for from this far room-ward of the doorway's middle ...
const REACH_ON := 5.5            ## ... to this far into the hall
const FLOOD_HALF := 4.5          ## the flood's window (half its side, world units)
const FLOOD_STEP := 0.1


func setup() -> void:
	timeout_sec = 300.0
	Monster.use_proto_visuals = true
	var n := 0
	var square := 0
	var sum_span := 0.0
	var worst := 0.0
	var services := 0
	for s in range(1, SEEDS + 1):
		for f in range(1, FLOORS + 1):
			var run := ContractBoard.run_for_seed(s)
			var map := DungeonGen.for_run(run, f)
			new_world(map)
			GameWorld.begin(map, world, run.floor_seed(f))
			var plan := SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
			var sp := Doorways.spaces(map)
			Doorways.settle(map, sp["cell_space"], Doorways.find(map, sp))   # (as RoomFog settles its spaces)
			var cell_space: Dictionary = sp["cell_space"]
			for i in plan.doors.size():
				var dr: Dictionary = plan.doors[i]
				var tag := "seed %d floor %d door %d (doorway %d, %s)" % [s, f, i, int(dr["id"]), str(dr.get("style", ""))]
				var a: Vector2 = dr["a"]
				var b: Vector2 = dr["b"]
				var ax: Vector3 = dr["axis"]
				var axis := Vector2(ax.x, ax.z)
				var span := a.distance_to(b)
				var cosv := absf((b - a).normalized().dot(axis))
				n += 1
				sum_span += span
				if cosv < 0.02:
					square += 1
				if str(dr.get("style", "")) == OfficeDoorModel.SERVICE:
					services += 1
				var cuts := valid_cuts(map, dr)
				var best := INF
				var best_square := INF
				var square_s := INF
				for cut: Dictionary in cuts:
					best = minf(best, float(cut["len"]))
					if float(cut["cos"]) < 0.02:
						if float(cut["len"]) < best_square - 0.001 or (absf(float(cut["len"]) - best_square) <= 0.001 and float(cut["s"]) < square_s):
							best_square = float(cut["len"])
							square_s = float(cut["s"])
				worst = maxf(worst, span - best)
				check(best < INF, "%s: its opening has a valid cut" % tag)
				check(span <= best + TOL, "%s: spans %.2f, the shortest cut is %.2f" % [tag, span, best])
				if best_square < INF:
					check(cosv < 0.02, "%s: a square cut exists (%.2f) but the door is at cos %.2f to the hall" % [tag, best_square, cosv])
					var own_s := _s_of(dr, (a + b) * 0.5)
					check(own_s <= square_s + TOL, "%s: a square cut stands nearer the room (%.2f) than the door (%.2f)" % [tag, square_s, own_s])
				check(seals(map, dr), "%s: the shut door seals its opening" % tag)
				_cells_agree(map, dr, cell_space, tag)
				_sides_agree(map, dr, cell_space, tag)
	Monster.use_proto_visuals = false
	print("[door span] %d doors (%d service), %d square to the hall, mean span %.3f, worst over the shortest cut +%.3f" % [n, services, square, sum_span / maxf(1.0, n), worst])
	check(n > 100, "enough doors looked at (%d)" % n)
	finish()


## Where p sits along the hall, measured from the doorway's middle into the hall.
static func _s_of(dr: Dictionary, p: Vector2) -> float:
	var ax: Vector3 = dr["axis"]
	var mid: Vector3 = _mid(dr)
	return (p - Vector2(mid.x, mid.z)).dot(Vector2(ax.x, ax.z))


## The doorway's middle (between its room cells and its hall cells), as Doorways measures it.
static func _mid(dr: Dictionary) -> Vector3:
	var s := Vector3.ZERO
	for c: Vector2i in dr["door_cells"]:
		s += Hex.to_world(c)
	var rc := s / maxf(1.0, (dr["door_cells"] as Array).size())
	s = Vector3.ZERO
	for c: Vector2i in dr["mouth_cells"]:
		s += Hex.to_world(c)
	var mc := s / maxf(1.0, (dr["mouth_cells"] as Array).size())
	return (rc + mc) * 0.5


## Every valid cut of a door's opening: {len, cos (to the axis), s (where it crosses the centre line, from the doorway's
## middle into the hall), p, q}. The centre line runs along the axis through the doorway cell (the corridor's centre lane).
static func valid_cuts(map: HexMap, dr: Dictionary) -> Array:
	var c: Vector2i = dr["cell"]
	var lv := map.get_cell(c).level
	var cw := Hex.to_world(c)
	var o := Vector2(cw.x, cw.z)
	var ax: Vector3 = dr["axis"]
	var axis := Vector2(ax.x, ax.z)
	var perp := Vector2(-axis.y, axis.x)
	var mid := _mid(dr)
	var m2 := Vector2(mid.x, mid.z)
	var pts: Array[Vector2] = []
	for h in Hex.range_cells(Hex.from_world(mid), 5):
		var w := Hex.to_world(h)
		pts.append(Vector2(w.x, w.z))
	var out := []
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			var p := pts[i]
			var q := pts[j]
			var L := p.distance_to(q)
			if L < 1.5 or L > 6.0:
				continue
			var rp := (p - o).dot(perp)
			var rq := (q - o).dot(perp)
			if rp * rq >= 0.0:
				continue
			var x := p.lerp(q, rp / (rp - rq))
			var s := (x - m2).dot(axis)
			if s < -REACH_BACK or s > REACH_ON:
				continue
			if not valid_cut(map, p, q, lv):
				continue
			out.append({"len": L, "cos": absf((q - p).normalized().dot(axis)), "s": s, "p": p, "q": q})
	return out


## Wall to wall (each end runs on into wall), open level floor between, no stairs.
static func valid_cut(map: HexMap, p: Vector2, q: Vector2, lv: int) -> bool:
	var u := (q - p).normalized()
	if not map.wall_at(Vector3(p.x - u.x * 0.12, 0.0, p.y - u.y * 0.12)) or not map.wall_at(Vector3(q.x + u.x * 0.12, 0.0, q.y + u.y * 0.12)):
		return false
	for i in range(1, 24):
		var m := p.lerp(q, i / 24.0)
		var m3 := Vector3(m.x, 0.0, m.y)
		if map.wall_at(m3):
			return false
		var cell := map.get_cell(Hex.from_world(m3))
		if cell == null or cell.type == HexMap.Tile.STAIRS or absf(map.ground_level(m3) - lv) > 0.01:
			return false
	return true


## A flood over the floor round the door (wall, void and the door's line blocking) from a point a cell into the room side
## never reaches the point a cell into the hall side, within the window.
static func seals(map: HexMap, dr: Dictionary) -> bool:
	var a: Vector2 = dr["a"]
	var b: Vector2 = dr["b"]
	var ax: Vector3 = dr["axis"]
	var t := (b - a).normalized()
	var nrm := Vector2(-t.y, t.x)
	if nrm.dot(Vector2(ax.x, ax.z)) < 0.0:
		nrm = -nrm   # (toward the hall)
	var m := (a + b) * 0.5
	var from := m - nrm * 0.9
	var goal := m + nrm * 0.9
	var side := int(FLOOD_HALF * 2.0 / FLOOD_STEP) + 1
	var origin := m - Vector2(FLOOD_HALF, FLOOD_HALF)
	var open := func(ix: int, iy: int) -> bool:
		var p := origin + Vector2(ix, iy) * FLOOD_STEP
		var p3 := Vector3(p.x, 0.0, p.y)
		if map.get_cell(Hex.from_world(p3)) == null or map.wall_at(p3):
			return false
		var cl := Geometry2D.get_closest_point_to_segment(p, a, b)
		return cl.distance_to(p) > FLOOD_STEP * 0.75
	var start := Vector2i(roundi((from.x - origin.x) / FLOOD_STEP), roundi((from.y - origin.y) / FLOOD_STEP))
	var end := Vector2i(roundi((goal.x - origin.x) / FLOOD_STEP), roundi((goal.y - origin.y) / FLOOD_STEP))
	if not open.call(start.x, start.y) or not open.call(end.x, end.y):
		return false
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var qi := 0
	while qi < queue.size():
		var cur := queue[qi]
		qi += 1
		if cur == end:
			return false
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cur + d
			if nb.x < 0 or nb.y < 0 or nb.x >= side or nb.y >= side or seen.has(nb):
				continue
			seen[nb] = true
			if open.call(nb.x, nb.y):
				queue.append(nb)
	return true


## The doorway cell is a full hall cell on the hall side of the door line; a square door's jambs are its band's cut cells.
func _cells_agree(map: HexMap, dr: Dictionary, cell_space: Dictionary, tag: String) -> void:
	var c: Vector2i = dr["cell"]
	check(map.is_walkable_cell(c) and str(cell_space.get(c, "")) == str(dr["hall"]), "%s: the doorway cell %s is a full cell of %s" % [tag, str(c), str(dr["hall"])])
	var a: Vector2 = dr["a"]
	var b: Vector2 = dr["b"]
	var w := Hex.to_world(c)
	var ax: Vector3 = dr["axis"]
	check((Vector2(w.x, w.z) - (a + b) * 0.5).dot(Vector2(ax.x, ax.z)) > 0.3, "%s: the doorway cell is on the hall side of the door" % tag)
	var band: Array = dr["band"]
	if absf((b - a).normalized().dot(Vector2(ax.x, ax.z))) < 0.02 and band.size() == 3:
		var j1 := Hex.to_world(band[1])
		var j2 := Hex.to_world(band[2])
		var ends := [Vector2(j1.x, j1.z), Vector2(j2.x, j2.z)]
		check(((ends[0] as Vector2).distance_to(a) < 0.01 or (ends[1] as Vector2).distance_to(a) < 0.01) \
			and ((ends[0] as Vector2).distance_to(b) < 0.01 or (ends[1] as Vector2).distance_to(b) < 0.01), "%s: a square door's jambs are its band's cut cells" % tag)


## Points on either side of the door (0.5 to 2.2 off its line, up to 0.7 either side of its middle): the room's space on
## the room side, the hall's on the hall side (cells of other spaces, walls and the jambs' own cut cells aside).
func _sides_agree(map: HexMap, dr: Dictionary, cell_space: Dictionary, tag: String) -> void:
	var a: Vector2 = dr["a"]
	var b: Vector2 = dr["b"]
	var ax: Vector3 = dr["axis"]
	var t := (b - a).normalized()
	var nrm := Vector2(-t.y, t.x)
	if nrm.dot(Vector2(ax.x, ax.z)) < 0.0:
		nrm = -nrm
	var m := (a + b) * 0.5
	var room := str(dr["room"])
	var hall := str(dr["hall"])
	var bad := []
	for k: float in [0.5, 1.0, 1.6, 2.2]:
		for sgn: float in [-1.0, 1.0]:
			for lat: float in [-0.7, 0.0, 0.7]:
				var p := m + nrm * k * sgn + t * lat
				var p3 := Vector3(p.x, 0.0, p.y)
				var c := Hex.from_world(p3)
				var cell := map.get_cell(c)
				if cell == null or map.wall_at(p3):
					continue
				var w := Hex.to_world(c)
				if absf((Vector2(w.x, w.z) - m).dot(nrm)) <= Doorways.SETTLE_ON:
					continue   # (a jamb's cut cell, on the line)
				var sp := str(cell_space.get(c, ""))
				if sp != room and sp != hall:
					continue
				var want := hall if sgn > 0.0 else room
				if sp != want:
					bad.append("%s at %s is %s" % [str(c), "hall side" if sgn > 0.0 else "room side", sp])
	check(bad.is_empty(), "%s: the fog's spaces disagree with the door line: %s" % [tag, ", ".join(bad)])
