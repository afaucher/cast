extends TestCase
## Midpoint walls (HexMap.cut_walls, DungeonGen): walls run from hex center to hex center through the edge
## midpoints, the border cells are cut in half, and everything that collides or places things treats the wall LINE
## as the boundary.
##  - generated floors over many seeds: cut cells consistent, every wall segment runs from a center to an edge
##    midpoint and continues into the next cell, no sliver or pocket of floor, every room reachable, doorways open
##    and full, deterministic;
##  - an actor walking into a flat wall stops with its body touching the face at any angle and slides along it;
##    corners (the room's 120-degree corners and a wall's tip on a hex center) hold still without jitter or
##    tunnelling; a shove slams at the face; arrows and bolts stop at the face;
##  - nothing is planned or spawned on the wall side of a cut cell, and wall-backed props stand flush and square.

const SEEDS: Array[int] = [1, 2, 3, 4, 5, 7, 11, 13, 17, 21, 42, 99, 123, 777, 1234, 31337]
const R := 0.4                       ## actor radius used by the collision checks
const DT := 1.0 / 60.0

var root: Node3D
var _halves := 0
var _segments := 0


func setup() -> void:
	timeout_sec = 180.0
	for s in SEEDS:
		_check_floor(DungeonGen.generate(s), "seed %d" % s)
	for s in [1, 2, 42, 777]:
		_check_floor(DungeonGen.generate(s, {"elevator": ElevatorGeo.PLACE_FREE}), "seed %d (free elevator)" % s)
	_check_doors()
	_check_determinism()
	print("midpoint walls: %d cut cells, %d wall segments over %d seeds" % [_halves, _segments, SEEDS.size()])
	_check_walk_into_wall()
	_check_corners()
	await _check_slam()
	await _check_arrows()
	await _check_placement()
	finish()


# --- generated floors --------------------------------------------------------------------------------------------

func _check_floor(m: HexMap, tag: String) -> void:
	check(m.midpoint_walls, tag + ": the generator cuts the walls")
	var bad_mask := 0
	var bad_seg := 0
	var spikes := 0
	for c: Vector2i in m.cells:
		var cell: HexMap.Cell = m.cells[c]
		if cell.type == HexMap.Tile.WALL or cell.wall_mask == 0:
			continue
		if m.is_half(c):
			_halves += 1
		check(cell.wall_top >= cell.level + 3, "%s: the wall part of %s towers over its floor (%d vs %d)" % [tag, str(c), cell.wall_top, cell.level])
		var ctr := Hex.to_world(c)
		for k in 6:
			# the same triangle has the same state in all three of its cells
			var nb: Vector2i = c + Hex.DIRS[k]
			if m.has_cell(nb) and m.kite_blocked(c, k) != m.kite_blocked(nb, k + 2):
				bad_mask += 1
		var segs := m.wall_segments(c)
		var i := 0
		while i < segs.size():
			_segments += 1
			var a: Vector2 = segs[i]
			var b: Vector2 = segs[i + 1]
			# a face runs from this cell's center to an edge midpoint, along one of the six directions
			var from_center := a.distance_to(Vector2(ctr.x, ctr.z)) < 0.0001
			var to_mid := absf(b.distance_to(a) - Hex.INNER) < 0.0001
			var d := _dir_of(b - a)
			var continues := false
			if from_center and to_mid and d >= 0:
				# ... and goes on from that midpoint to the next center: the neighbour holds the other half
				var other := m.wall_segments(c + Hex.DIRS[d])
				var j := 0
				while j < other.size():
					if other[j + 1].distance_to(b) < 0.0001:
						continues = true
					j += 3
			if not (from_center and to_mid and d >= 0 and continues):
				bad_seg += 1
			i += 3
		# no 60-degree spike of floor between two faces
		for k in 6:
			if m.kite_blocked(c, k) or not m._tri_all_floor(c, k):
				continue
			var walls := 0
			if m._tri_blocked(c, k - 1):
				walls += 1
			if m._tri_blocked(c, k + 1):
				walls += 1
			if m._tri_blocked(c + Hex.DIRS[k], k + 1):
				walls += 1
			if walls >= 2:
				spikes += 1
	eq(bad_mask, 0, tag + ": cut cells agree on every triangle")
	eq(bad_seg, 0, tag + ": every wall segment runs center -> edge midpoint and continues to the next center")
	eq(spikes, 0, tag + ": no sliver of floor between two wall faces")
	_check_elevator_cut(m, tag)
	_check_floor_connected(m, tag)
	_check_rooms_reachable(m, tag)


## The elevator's cut: a wall car opens exactly the five triangles of its trapezoid (the mouth on the room's wall line, the
## car's back wall on the next line, nothing open behind it) with a jamb solid over each sliver; a free car has its five
## closed sides as solids and stands on floor that the walls do not cut.
func _check_elevator_cut(m: HexMap, tag: String) -> void:
	var e := m.elevator
	if not check(not e.is_empty(), tag + ": the floor has an elevator"):
		return
	var cs: Array = e["cells"]
	if str(e["place"]) == ElevatorGeo.PLACE_WALL:
		var ms: Array = e["mouth"]
		var tris := [[ms[0], cs[0], ms[1]], [cs[0], cs[1], ms[1]], [ms[1], cs[1], ms[2]], [cs[1], cs[2], ms[2]], [ms[2], cs[2], ms[3]]]
		for tri: Array in tris:
			check(_tri_open(m, tri[0], tri[1], tri[2]), tag + ": the car's triangle %s is open floor" % str(tri))
		var k := int(e["k"])
		for c: Vector2i in cs:
			check(m.kite_blocked(c, k) and m.kite_blocked(c, k - 1) and m.kite_blocked(c, k + 1), tag + ": behind the car is wall at %s" % str(c))
		eq(m.solids.size(), 2, tag + ": two jamb solids")
	else:
		for c: Vector2i in cs:
			eq(m.wall_mask_of(c), 0, tag + ": the free car's cell %s is not cut" % str(c))
		eq(m.solids.size(), 5, tag + ": five closed sides")


## Is the triangle of the three adjacent cells a, b, c open (no corner a wall, not blocked)?
func _tri_open(m: HexMap, a: Vector2i, b: Vector2i, c: Vector2i) -> bool:
	for k in 6:
		var x: Vector2i = a + Hex.DIRS[k]
		var y: Vector2i = a + Hex.DIRS[(k + 1) % 6]
		if (x == b and y == c) or (x == c and y == b):
			return m._tri_all_floor(a, k) and not m._tri_blocked(a, k)
	return false


## Every open triangle of floor (heights aside) joins the start's floor: no pocket cut off by a wall line.
func _check_floor_connected(m: HexMap, tag: String) -> void:
	var start := m.cells_with_tag("start")[0]
	var first := Vector3i(start.x, start.y, 0)
	var seen := {first: true}
	var queue: Array[Vector3i] = [first]
	var qi := 0
	while qi < queue.size():
		var t := queue[qi]
		qi += 1
		var tc := Vector2i(t.x, t.y)
		for nb: Vector3i in [m._canon(tc, t.z - 1), m._canon(tc, t.z + 1), m._canon(tc + Hex.DIRS[t.z], t.z + 1)]:
			var nc := Vector2i(nb.x, nb.y)
			if seen.has(nb) or not m._tri_all_floor(nc, nb.z) or m._tri_blocked(nc, nb.z):
				continue
			seen[nb] = true
			queue.append(nb)
	var lost := 0
	for c: Vector2i in m.cells:
		for k in 2:
			if m._tri_all_floor(c, k) and not m._tri_blocked(c, k) and not seen.has(Vector3i(c.x, c.y, k)):
				lost += 1
	eq(lost, 0, tag + ": every piece of floor joins the rest (no pocket behind a wall line)")


## Every room's full floor at its own level is reachable from the start (climbing allowed), and every cut cell of a room
## touches the room's full floor.
func _check_rooms_reachable(m: HexMap, tag: String) -> void:
	var start := m.cells_with_tag("start")[0]
	var reached := {start: true}
	var queue: Array[Vector2i] = [start]
	var qi := 0
	while qi < queue.size():
		var c := queue[qi]
		qi += 1
		for d in Hex.DIRS:
			var nb: Vector2i = c + d
			if not reached.has(nb) and m.cell_transition(c, nb) != HexMap.Move.BLOCKED:
				reached[nb] = true
				queue.append(nb)
	var rooms := {}   # tag -> {level -> count}
	for c: Vector2i in m.cells:
		var t: String = m.cells[c].tag
		if t.begins_with("room:") and m.is_walkable_cell(c):
			if not rooms.has(t):
				rooms[t] = {}
			var per: Dictionary = rooms[t]
			per[m.cells[c].level] = int(per.get(m.cells[c].level, 0)) + 1
	for t: String in rooms:
		var per: Dictionary = rooms[t]
		var base := 0
		var best := -1
		for lv: int in per:
			if int(per[lv]) > best:
				best = int(per[lv])
				base = lv
		var missing := 0
		for c: Vector2i in m.cells:
			var cell: HexMap.Cell = m.cells[c]
			if cell.tag == t and cell.level == base and m.is_walkable_cell(c) and not reached.has(c):
				missing += 1
		eq(missing, 0, "%s: all of %s's floor is reachable" % [tag, t])
	for c: Vector2i in m.cells:
		if not m.is_half(c):
			continue
		var touches := false
		for d in Hex.DIRS:
			if m.is_walkable_cell(c + d):
				touches = true
		check(touches, "%s: cut cell %s borders full floor" % [tag, str(c)])


## Doorways: both door cells of every corridor are full and the corridor leads from one to the other.
func _check_doors() -> void:
	var links := 0
	for s in SEEDS:
		var b := DungeonGen.Builder.new(s, {})
		var m := b.build()
		if m == null:
			continue   # this attempt was retried by generate(); the floors above cover the result
		for l in b.links:
			links += 1
			check(m.is_walkable_cell(l.door_a) and m.is_walkable_cell(l.door_b), "seed %d: doorways %s / %s are open floor" % [s, str(l.door_a), str(l.door_b)])
			check(not m.find_path(l.door_a, l.door_b, true).is_empty(), "seed %d: the corridor %s -> %s is walkable" % [s, str(l.door_a), str(l.door_b)])
			# the door cell's neighbours outside the room are corridor floor: a clean opening, no wall stub in it
			var room_tag: String = m.cells[l.door_a].tag
			for d in Hex.DIRS:
				var nb: HexMap.Cell = m.get_cell(l.door_a + d)
				check(nb != null and nb.type != HexMap.Tile.WALL, "seed %d: no wall right beside door %s (room %s)" % [s, str(l.door_a), room_tag])
	check(links >= 20, "doorways checked on %d corridors" % links)


func _check_determinism() -> void:
	for s: int in [3, 42]:
		var a := DungeonGen.generate(s)
		var b := DungeonGen.generate(s)
		var same := a.cells.size() == b.cells.size()
		for c: Vector2i in a.cells:
			var x: HexMap.Cell = a.cells[c]
			var y: HexMap.Cell = b.cells.get(c)
			if y == null or x.wall_mask != y.wall_mask or x.wall_top != y.wall_top or x.level != y.level or x.type != y.type or x.tag != y.tag:
				same = false
				break
		check(same, "seed %d: the same cut cells and wall lines every time" % s)


# --- collision -----------------------------------------------------------------------------------------------------

## A flat hex room of radius 8 (level 0) in a wall ring, cut: its walls are the hexagon through the ring-8 centers.
## `pillar` adds a WALL cell inside first (a hexagonal pillar whose corners are its neighbours' centers).
func _room(pillar: Vector2i = HexMap.NO_CELL) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 8):
		m.set_cell(c, 0).tag = "room:0"
	for c in Hex.ring(Vector2i.ZERO, 9):
		m.set_cell(c, 3, HexMap.Tile.WALL)
	if pillar != HexMap.NO_CELL:
		m.set_cell(pillar, 3, HexMap.Tile.WALL)
	m.cut_walls()
	return m


func _world(m: HexMap) -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(m, root, 3)


func _actor(pos: Vector3, team: int = GameWorld.TEAM_MONSTERS) -> Actor:
	var a := Actor.new()
	a.team = team
	a.radius = R
	GameWorld.spawn(a, pos)
	a.snap_to_ground()
	return a


## The side between the ring-8 corners 8*DIRS[0] and 8*DIRS[1]: unit outward normal N, tangent T, the face at N.p = 12.
func _side() -> Array[Vector3]:
	var n := (Hex.to_world(Hex.DIRS[0]) + Hex.to_world(Hex.DIRS[1])).normalized()
	var t := Hex.to_world(Hex.DIRS[2]).normalized()
	return [n, t]


func _check_walk_into_wall() -> void:
	var m := _room()
	_world(m)
	var nt := _side()
	var n := nt[0]
	var t := nt[1]
	var face := 12.0
	for ang: float in [0.0, 20.0, 40.0, 60.0, 75.0]:
		var a := _actor(n * 10.0 - t * 3.0)
		var dir := (n * cos(deg_to_rad(ang)) + t * sin(deg_to_rad(ang))).normalized()
		var deepest := -INF
		var touched_at := INF
		var t_at_touch := 0.0
		for i in 150:
			a.move(dir, DT)
			var depth := a.global_position.dot(n)
			deepest = maxf(deepest, depth)
			if touched_at == INF and depth > face - R - 0.01:
				touched_at = i
				t_at_touch = a.global_position.dot(t)
		var end := a.global_position.dot(n)
		check(deepest <= face - R + 0.002, "%.0f deg: the body never crosses the face (deepest %.3f, face - r = %.3f)" % [ang, deepest, face - R])
		near(end, face - R, 0.01, "%.0f deg: the body ends touching the flat face" % ang)
		check(not m.blocks_point(a.global_position, R - 0.005), "%.0f deg: not overlapping the wall" % ang)
		var hit := m.nearest_wall(a.global_position, 2.0)
		check(not hit.is_empty() and absf(float(hit["dist"]) - R) < 0.01, "%.0f deg: nearest_wall agrees (%.3f)" % [ang, float(hit.get("dist", -1.0))])
		if ang >= 20.0:
			var slid := a.global_position.dot(t) - t_at_touch
			check(touched_at < 150 and slid > 0.5, "%.0f deg: it slides along the face once touching (%.2f)" % [ang, slid])
		else:
			# pressed straight in: it holds still (no drift along the face)
			var p0 := a.global_position
			for _i in 30:
				a.move(dir, DT)
			check(a.global_position.distance_to(p0) < 0.0005, "%.0f deg: pressed straight in, it holds still (%.4f)" % [ang, a.global_position.distance_to(p0)])
		a.free()


func _check_corners() -> void:
	# --- the room's 120-degree corner at the hex center of cell (8, 0)
	var m := _room()
	_world(m)
	var corner := Hex.to_world(Vector2i(8, 0))
	for off: float in [0.0, 12.0, -20.0]:
		var a := _actor(corner + Vector3(-4.0, 0.0, 0.0))
		var dir := Vector3(cos(deg_to_rad(off)), 0.0, sin(deg_to_rad(off)))
		var path: Array[Vector3] = []
		for i in 400:
			a.move(dir, DT)
			path.append(a.global_position)
			check(not m.wall_at(a.global_position), "corner %.0f: never inside the wall" % off)
		var spread := 0.0
		for i in range(370, 400):
			spread = maxf(spread, path[i].distance_to(path[399]))
		check(spread < 0.001, "corner %.0f: it settles in the corner without jitter (%.5f)" % [off, spread])
		check(not m.blocks_point(a.global_position, R - 0.005), "corner %.0f: touching, not overlapping" % off)
		near(a.global_position.x, corner.x - R / sin(deg_to_rad(60.0)), 0.02, "corner %.0f: wedged into the corner point" % off)
		a.free()
	# --- a wall's tip on a hex center: the pillar (2, 2)'s corner at the center of (3, 2)
	var pm := _room(Vector2i(2, 2))
	_world(pm)
	var tip := Hex.to_world(Vector2i(3, 2))
	var b := _actor(tip + Vector3(3.0, 0.0, 0.0))
	for i in 120:
		b.move(Vector3.LEFT, DT)
	var hold := b.global_position
	for i in 30:
		b.move(Vector3.LEFT, DT)
	check(b.global_position.distance_to(hold) < 0.001, "tip: pushed straight at it, it holds still (%.4f)" % b.global_position.distance_to(hold))
	near(b.global_position.distance_to(tip), R, 0.01, "tip: the body touches the tip point")
	b.free()
	# aimed a little to one side it slides round the tip and carries on
	var c := _actor(tip + Vector3(3.0, 0.0, 0.25))
	var min_clear := INF
	for i in 200:
		c.move(Vector3.LEFT, DT)
		var hit := pm.nearest_wall(c.global_position, 2.0)
		if not hit.is_empty():
			min_clear = minf(min_clear, float(hit["dist"]))
	check(min_clear >= R - 0.005, "tip: sliding past, the body never overlaps the wall (closest %.3f)" % min_clear)
	check(c.global_position.x < tip.x - 0.3, "tip: it gets round the tip (x %.2f vs tip %.2f)" % [c.global_position.x, tip.x])
	c.free()
	# big steps (a frame hitch) into the tip: never through it
	var d := _actor(tip + Vector3(3.0, 0.0, 0.0))
	for i in 20:
		d.move(Vector3.LEFT, 0.15)
		check(not pm.blocks_point(d.global_position, R - 0.005), "tip, big steps: never inside the wall")
	check(d.global_position.x > tip.x, "tip, big steps: it never tunnels to the far side")
	d.free()


func _check_slam() -> void:
	var m := _room()
	_world(m)
	var nt := _side()
	var n := nt[0]
	var a := _actor(n * 9.0)
	var impacts: Array[String] = []
	a.shove_impact.connect(func(kind: String, _p: Vector3, _amt: float) -> void: impacts.append(kind))
	a.shove(n, 4.0)
	var guard := 0
	while a.is_shoved() and guard < 120:
		await frames(1)
		guard += 1
	check(impacts.has("slam"), "a shove into the face slams (%s)" % str(impacts))
	near(a.hp, a.max_hp - Actor.WALL_SLAM_DAMAGE, 0.01, "slam damage")
	near(a.global_position.dot(n), 12.0 - R, 0.02, "the slam stops with the body against the face")
	check(not m.blocks_point(a.global_position, R - 0.005), "slammed, not inside the wall")
	a.free()


func _check_arrows() -> void:
	var m := _room()
	_world(m)
	var nt := _side()
	var n := nt[0]
	var shooter := _actor(n * 8.0 - nt[1] * 1.0, GameWorld.TEAM_HEROES)
	var at: Array[Vector3] = []
	var arrow := ArrowShot.shoot(shooter, n, 5.0, 22.0, 14.0, 1, false, Color.WHITE)
	arrow.impacted.connect(func(p: Vector3, _h: Actor) -> void: at.append(p))
	var bolt := Projectile.fire(shooter, Combat.chest(shooter) + nt[1] * 2.0, n, 5.0, 14.0, 14.0)
	bolt.impacted.connect(func(p: Vector3, _h: Actor) -> void: at.append(p))
	var guard := 0
	while at.size() < 2 and guard < 120:
		await frames(1)
		guard += 1
	eq(at.size(), 2, "the arrow and the bolt both hit the wall")
	for p in at:
		var depth := p.dot(n)
		check(depth <= 12.0 + 0.001 and depth >= 12.0 - 0.03, "a shot stops at the face (%.3f vs 12)" % depth)
	shooter.free()


# --- placement --------------------------------------------------------------------------------------------------

func _check_placement() -> void:
	var floors := 0
	var flush := 0
	var worst_gap := 0.0
	var worst_dot := 1.0
	for spec: Array in [["prepper", 3], ["supervillain", 8], ["tech_founder", 21]]:
		var run := ContractRun.make(str(spec[0]), int(spec[1]), 0.5)
		var catalog := ContractParts.prop_catalog(run.site_type)
		for f in range(1, ContractRun.FLOOR_COUNT + 1):
			var m := DungeonGen.generate(run.floor_seed(f))
			var p := SiteBuilder.plan(m, run, f, catalog)
			floors += 1
			var tag := "%s/%d floor %d" % [spec[0], spec[1], f]
			for pr in p.props:
				var foot: Vector2 = pr["foot"]
				var pos: Vector2 = pr["pos"]
				_foot_clear(m, pos, float(pr["yaw"]), foot.x, foot.y, "%s: priced %s" % [tag, pr["kind"]])
				if String(pr["place"]) == "wall":
					var hit := _back_face(m, pos, float(pr["yaw"]), foot.y)
					if check(not hit.is_empty(), "%s: wall prop %s has a wall behind it" % [tag, pr["kind"]]):
						var gap := float(hit["dist"]) - foot.y * 0.5
						var dot := float(hit["dot"])
						worst_gap = maxf(worst_gap, gap)
						worst_dot = minf(worst_dot, dot)
						flush += 1
						check(gap > -0.02 and gap < 0.3, "%s: %s stands flush against the flat face (gap %.2f)" % [tag, pr["kind"], gap])
						check(dot > 0.97, "%s: %s is square to the face (%.3f)" % [tag, pr["kind"], dot])
			for dc in p.decor:
				_foot_clear(m, dc["pos"], float(dc["yaw"]), float(dc["w"]), float(dc["d"]), "%s: decor %s" % [tag, dc["kind"]])
			for pk in p.packages:
				var sz := PackageModels.size_of(str((pk["sizes"] as Array)[0]))
				_foot_clear(m, pk["pos"], float(pk["yaw"]), sz.x, sz.z, "%s: mail package" % tag)
			for list: Array in [p.gates, p.employees, p.notes]:
				for e: Dictionary in list:
					check(m.is_walkable_cell(e["cell"]), "%s: %s stands on full floor" % [tag, str(e["cell"])])
			if not p.van.is_empty():
				_foot_clear(m, p.van["pos"], float(p.van["yaw"]), float(p.van["w"]), float(p.van["d"]), "%s: the van" % tag)
				for s: Vector2 in (p.van["crew"] as Array):
					check(not m.blocks_point(Vector3(s.x, 0.0, s.y), R), "%s: a crew spot by the van is clear of the walls" % tag)
			if f == 1:
				# spawn one floor for real: every monster and the props stand on floor, off the walls
				_world(m)
				var site := SiteBuilder.spawn(m, run, p)
				await frames(1)
				for mo in site.monsters:
					check(m.is_walkable_cell(mo.current_cell()), "%s: monster %s spawns on full floor" % [tag, mo.display_name])
					check(not m.blocks_point(mo.global_position, mo.radius), "%s: monster %s is clear of the walls" % [tag, mo.display_name])
				for e in site.employees:
					check(not m.blocks_point(e.global_position, e.radius), "%s: employee clear of the walls" % tag)
				root.free()
				root = null
	check(floors >= 9 and flush >= 5, "placement checked on %d floors, %d wall-backed props" % [floors, flush])
	print("midpoint walls: wall props flush within %.2f, square within dot %.3f" % [worst_gap, worst_dot])


func _foot_clear(m: HexMap, pos: Vector2, yaw: float, w: float, d: float, label: String) -> void:
	var inside := 0
	for p in ThemeGeo.foot_points(pos, yaw, w, d):
		if m.wall_at(Vector3(p.x, 0.0, p.y)):
			inside += 1
	# no wall face crosses the footprint either (a tip poking in between the sample points)
	var lat := ThemeGeo.lateral(yaw)
	var fac := ThemeGeo.facing(yaw)
	var segs := m.segments_near(Vector3(pos.x, 0.0, pos.y), Vector2(w, d).length() * 0.5)
	var i := 0
	while i < segs.size():
		var a := segs[i] - pos
		var b := segs[i + 1] - pos
		if ThemeCtx._seg_hits_box(Vector2(a.dot(lat), a.dot(fac)), Vector2(b.dot(lat), b.dot(fac)), w * 0.5 - 0.02, d * 0.5 - 0.02):
			inside += 1
		i += 3
	eq(inside, 0, label + " keeps out of the wall half")


## The wall face behind a prop at (pos, yaw) of depth d: among the faces within reach of its back, the one it is most
## square to. {dist (from pos), dot (facing . face normal)} or {}.
func _back_face(m: HexMap, pos: Vector2, yaw: float, d: float) -> Dictionary:
	var f := ThemeGeo.facing(yaw)
	var segs := m.segments_near(Vector3(pos.x, 0.0, pos.y), d * 0.5 + 0.5)
	var best: Dictionary = {}
	var i := 0
	while i < segs.size():
		var cp := HexMap._closest(pos, segs[i], segs[i + 1])
		var dist := pos.distance_to(cp)
		var dot := f.dot(segs[i + 2])
		if dist > d * 0.5 + 0.45:
			pass
		elif best.is_empty() or dot > float(best["dot"]) + 0.02 or (dot > float(best["dot"]) - 0.02 and dist < float(best["dist"])):
			best = {"dist": dist, "dot": dot}   # the best-aligned face; of the parallel pieces of one wall line, the nearest
		i += 3
	return best


static func _dir_of(v: Vector2) -> int:
	for d in 6:
		var dv := Hex.dir_vector(d)
		if Vector2(dv.x, dv.z).dot(v.normalized()) > 0.9999:
			return d
	return -1
