class_name NetBot
extends Node
## A scripted walker for a hero (docs/design/networking-build-plan.md §3, "Bots"): the one new seam M2 needs is the
## PlayerController's `move_override`, a world-space walk direction. The bot walks a ROUTE of waypoints (a loop by
## default) at full speed by steering the real controller, so the hero moves through the real code (Actor.move,
## walls, climbs, separation) exactly as a player's would; nothing is faked on the wire. Multi-process tests give
## each process a bot (`NetGameTest`), and the `--net-bot` dev flag gives a window one for two-window local play.
##
## route_from() walks real floor: cells reachable from where the hero stands (HexMap.find_path), out to the far side
## of a neighbourhood and back, with a corner at every hex, so the stream sees direction changes all the time.

const ARRIVE := 0.3          ## a waypoint is reached within this distance
const AIM_AHEAD := 4.0

var hero: Hero = null
var controller: PlayerController = null
var route: Array[Vector3] = []
var loop := true
var running := false
## Waypoints reached so far (a loop counts every lap).
var reached := 0

var _i := 0


## Start walking `route` with `hero`'s controller.
func start(new_hero: Hero, new_controller: PlayerController, new_route: Array[Vector3], looping: bool = true) -> void:
	hero = new_hero
	controller = new_controller
	route = new_route
	loop = looping
	_i = 0
	reached = 0
	running = not route.is_empty()


## Stand still (the controller keeps a zero walk, so the keyboard stays ignored).
func stop() -> void:
	running = false
	if controller != null:
		controller.move_override = Vector3.ZERO


## Give the keyboard back.
func release() -> void:
	running = false
	if controller != null:
		controller.move_override = Vector3.INF
		controller.aim_override = Vector3.INF


func resume() -> void:
	running = not route.is_empty()


## Put the hero at `p` at once (a teleport, as a dev warp or the elevator would).
func teleport(p: Vector3) -> void:
	hero.global_position = p
	hero.snap_to_ground()


func _physics_process(_delta: float) -> void:
	if not running or hero == null or controller == null or hero.dead:
		return
	var here := hero.global_position
	var to := route[_i] - here
	to.y = 0.0
	if to.length() < ARRIVE:
		reached += 1
		_i += 1
		if _i >= route.size():
			if loop:
				_i = 0
			else:
				stop()
				return
		to = route[_i] - here
		to.y = 0.0
	var dir := to.normalized() if to.length() > 0.001 else Vector3.ZERO
	controller.move_override = dir
	controller.aim_override = here + dir * AIM_AHEAD


## A route over real floor from `from_cell`: the farthest reachable cell within `radius` hexes (by path), then the
## farthest reachable cell from THAT one, and back to the start. World points at the cell centres. A leg that would
## run into a solid decor circle (the work van, furniture: DecorBlocker) is not used: the bot picks the next best goal.
static func route_from(map: HexMap, from_cell: Vector2i, radius: int = 7, can_climb: bool = true) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var solids := _solids()
	var a := _farthest(map, from_cell, from_cell, radius, can_climb, solids)
	var b := _farthest(map, a, from_cell, radius, can_climb, solids)
	for pair: Array in [[from_cell, a], [a, b], [b, from_cell]]:
		var path := map.find_path(pair[0] as Vector2i, pair[1] as Vector2i, can_climb)
		for i in range(1, path.size()):
			out.append(Hex.to_world(path[i]))
	return out


## The reachable cell (a walkable floor cell within `radius` of `around`) whose path from `from` is longest and clear
## of the solid circles `solids` ([center Vector2, radius]).
static func _farthest(map: HexMap, from: Vector2i, around: Vector2i, radius: int, can_climb: bool, solids: Array) -> Vector2i:
	var best := from
	var best_len := 0
	for c in Hex.range_cells(around, radius):
		var cell := map.get_cell(c)
		if cell == null or cell.type != HexMap.Tile.FLOOR or not map.is_walkable_cell(c):
			continue
		var path := map.find_path(from, c, can_climb)
		if path.size() > best_len and _path_clear(path, solids):
			best_len = path.size()
			best = c
	return best


## [[center (x, z), radius]] of every solid decor circle in the world.
static func _solids() -> Array:
	var out: Array = []
	for a in GameWorld.actors():
		if a is DecorBlocker:
			out.append([Vector2(a.global_position.x, a.global_position.z), a.radius])
	return out


## True when no leg of `path` (cell centres) passes within a hero's width of a solid circle.
static func _path_clear(path: Array[Vector2i], solids: Array) -> bool:
	for i in range(1, path.size()):
		var p := Hex.to_world(path[i - 1])
		var q := Hex.to_world(path[i])
		var seg_a := Vector2(p.x, p.z)
		var seg_b := Vector2(q.x, q.z)
		for s: Array in solids:
			var c: Vector2 = s[0]
			var nearest := Geometry2D.get_closest_point_to_segment(c, seg_a, seg_b)
			if nearest.distance_to(c) < float(s[1]) + 0.6:
				return false
	return true
