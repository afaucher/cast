class_name HexMap
extends RefCounted
## Terrain data + the queries every system uses: ground height, movement
## rules (step / climb / blocked), line of sight and A* pathing.
##
## Terrain is a heightfield of hex columns. A cell that is absent is void
## (a pit / out of bounds): nothing stands there. Walls are just very tall
## cells (WALL type, rendered as rock).
##
## Movement rule, measured in height LEVELS between two nearby ground points:
##   rise <= STEP_LEVELS   walk (step up)
##   rise <= CLIMB_LEVELS  climb (slow)
##   rise >  CLIMB_LEVELS  blocked
##   drop >  DROP_LEVELS   blocked (no jumping off cliffs)
## STAIRS cells ramp smoothly from `level` (back edge) to `level + rise`
## (the edge facing `stair_dir`), which is how big height gaps are bridged.

enum Tile { FLOOR, WALL, STAIRS, BRIDGE }
enum Move { OK, CLIMB, BLOCKED }

const STEP_LEVELS := 1.05
const CLIMB_LEVELS := 2.05
const DROP_LEVELS := 3.05


class Cell:
	var level: int = 0
	var type: int = Tile.FLOOR
	var stair_dir: int = 0   ## direction index (Hex.DIRS) the stairs climb toward
	var stair_rise: int = 0  ## levels gained across the stairs
	var tag: String = ""     ## free-form (e.g. "room:3", "exit", "spawn")


var cells: Dictionary = {}  ## Vector2i -> Cell


func set_cell(c: Vector2i, level: int, type: int = Tile.FLOOR) -> Cell:
	var cell := Cell.new()
	cell.level = level
	cell.type = type
	cells[c] = cell
	return cell


func set_stairs(c: Vector2i, level: int, dir: int, rise: int) -> Cell:
	var cell := set_cell(c, level, Tile.STAIRS)
	cell.stair_dir = posmod(dir, 6)
	cell.stair_rise = rise
	return cell


func get_cell(c: Vector2i) -> Cell:
	return cells.get(c)


func has_cell(c: Vector2i) -> bool:
	return cells.has(c)


func is_walkable_cell(c: Vector2i) -> bool:
	var cell: Cell = cells.get(c)
	return cell != null and cell.type != Tile.WALL


## Ground height in LEVELS at a world X/Z point, or NAN over void.
func ground_level(p: Vector3) -> float:
	var c := Hex.from_world(p)
	var cell: Cell = cells.get(c)
	if cell == null:
		return NAN
	if cell.type != Tile.STAIRS:
		return float(cell.level)
	var off := p - Hex.to_world(c)
	off.y = 0.0
	var t := clampf(off.dot(Hex.dir_vector(cell.stair_dir)) / (2.0 * Hex.INNER) + 0.5, 0.0, 1.0)
	return cell.level + t * cell.stair_rise


## Ground height in WORLD units at a world X/Z point, or NAN over void.
func ground_height(p: Vector3) -> float:
	return ground_level(p) * Hex.LEVEL_HEIGHT


## Can something standing at `from` move to the nearby point `to`?
## Meant for short hops (one frame of movement, or across one cell edge).
func movement_check(from: Vector3, to: Vector3) -> int:
	var a := ground_level(from)
	var b := ground_level(to)
	if is_nan(a) or is_nan(b):
		return Move.BLOCKED
	var cb: Cell = cells.get(Hex.from_world(to))
	if cb.type == Tile.WALL:
		return Move.BLOCKED
	var d := b - a
	if d > CLIMB_LEVELS or -d > DROP_LEVELS:
		return Move.BLOCKED
	if d > STEP_LEVELS:
		return Move.CLIMB
	return Move.OK


## Movement between two adjacent cells, judged across their shared edge.
func cell_transition(a: Vector2i, b: Vector2i) -> int:
	if not is_walkable_cell(a) or not is_walkable_cell(b):
		return Move.BLOCKED
	var pa := Hex.to_world(a)
	var pb := Hex.to_world(b)
	var mid := (pa + pb) * 0.5
	var eps := 0.05
	return movement_check(mid.lerp(pa, eps / Hex.INNER), mid.lerp(pb, eps / Hex.INNER))


## True when nothing taller than the sight line sits between the two points.
## Points are world positions (Y included, e.g. eye height). Void never blocks.
func line_of_sight(from: Vector3, to: Vector3) -> bool:
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	var steps := maxi(1, int(flat / 0.25))
	for i in range(1, steps):
		var p := from.lerp(to, float(i) / steps)
		var g := ground_height(p)
		if not is_nan(g) and g > p.y:
			return false
	return true


## A* over cells. Returns the cell path from start to goal (inclusive of
## both) or [] if unreachable. Climbs cost extra; allow_climb=false treats
## them as walls (e.g. for heavy monsters).
func find_path(start: Vector2i, goal: Vector2i, allow_climb: bool = true, max_nodes: int = 4000) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not is_walkable_cell(start) or not is_walkable_cell(goal):
		return empty
	var open := {start: true}
	var came := {}
	var g := {start: 0.0}
	var f := {start: float(Hex.distance(start, goal))}
	var expanded := 0
	while not open.is_empty():
		var cur: Vector2i = open.keys()[0]
		for k in open:
			if f[k] < f[cur]:
				cur = k
		if cur == goal:
			var path: Array[Vector2i] = [cur]
			while came.has(cur):
				cur = came[cur]
				path.push_front(cur)
			return path
		open.erase(cur)
		expanded += 1
		if expanded > max_nodes:
			return empty
		for d in Hex.DIRS:
			var nb: Vector2i = cur + d
			var mv := cell_transition(cur, nb)
			if mv == Move.BLOCKED or (mv == Move.CLIMB and not allow_climb):
				continue
			var cost: float = g[cur] + (3.0 if mv == Move.CLIMB else 1.0)
			if cost < g.get(nb, INF):
				came[nb] = cur
				g[nb] = cost
				f[nb] = cost + Hex.distance(nb, goal)
				open[nb] = true
	return empty


func walkable_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		if is_walkable_cell(c):
			out.append(c)
	return out


func cells_with_tag(tag: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		if cells[c].tag == tag:
			out.append(c)
	return out
