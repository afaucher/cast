class_name Hex
extends RefCounted
## Pointy-top axial hex math. A cell is a Vector2i(q, r).
## World space: X/Z is the ground plane, Y is up. One height level is
## LEVEL_HEIGHT world units tall.

const SIZE := 1.0                 ## center-to-corner radius, world units
const LEVEL_HEIGHT := 0.5         ## world units per height level
const SQRT3 := 1.7320508075688772
const INNER := SIZE * SQRT3 * 0.5 ## center-to-edge distance

## Neighbor directions, index 0..5, counter-clockwise starting East.
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func to_world(c: Vector2i, level: float = 0.0) -> Vector3:
	return Vector3(SIZE * SQRT3 * (c.x + c.y * 0.5), level * LEVEL_HEIGHT, SIZE * 1.5 * c.y)


## World X/Z -> containing cell (Y ignored).
static func from_world(p: Vector3) -> Vector2i:
	var q := (SQRT3 / 3.0 * p.x - p.z / 3.0) / SIZE
	var r := (2.0 / 3.0 * p.z) / SIZE
	return round_axial(q, r)


static func round_axial(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


static func neighbor(c: Vector2i, dir: int) -> Vector2i:
	return c + DIRS[posmod(dir, 6)]


static func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		out.append(c + d)
	return out


## Direction index from a to an adjacent b, or -1 if not adjacent.
static func dir_to(a: Vector2i, b: Vector2i) -> int:
	return DIRS.find(b - a)


## Unit X/Z world vector pointing from a cell center toward neighbor `dir`.
static func dir_vector(dir: int) -> Vector3:
	return (to_world(DIRS[posmod(dir, 6)]) - to_world(Vector2i.ZERO)).normalized()


static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2


## Cells on the straight line from a to b, inclusive.
static func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var n := distance(a, b)
	var out: Array[Vector2i] = []
	for i in range(n + 1):
		var t := 0.0 if n == 0 else float(i) / n
		var q := lerpf(a.x + 1e-6, b.x + 1e-6, t)
		var r := lerpf(a.y + 1e-6, b.y + 1e-6, t)
		out.append(round_axial(q, r))
	return out


## All cells within `radius` steps of c (including c).
static func range_cells(c: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			out.append(c + Vector2i(q, r))
	return out


## Cells exactly `radius` steps from c.
static func ring(c: Vector2i, radius: int) -> Array[Vector2i]:
	if radius == 0:
		return [c]
	var out: Array[Vector2i] = []
	var cur := c + DIRS[4] * radius
	for side in 6:
		for _i in radius:
			out.append(cur)
			cur += DIRS[side]
	return out


## Corner i (0..5) offset from the cell center, pointy-top (corner 0 at 30°... see below).
## Corners run counter-clockwise starting at angle -30° (between E and SE edges).
static func corner(i: int) -> Vector3:
	var a := deg_to_rad(60.0 * i - 30.0)
	return Vector3(SIZE * cos(a), 0.0, SIZE * sin(a))
