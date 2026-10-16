class_name MonsterTestBase
extends TestCase
## Shared helpers for tests/test_monster_*.gd: tiny worlds, plain Actor heroes, polling.

var world: Node3D = null


## Start (or restart) a world on `map`. Frees whatever the previous world held.
func new_world(map: HexMap) -> void:
	if world != null:
		world.free()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	GameWorld.begin(map, world, 7)


## A hex-shaped flat arena of `radius` around (0,0).
func flat_map(radius: int, level: int = 0) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, level)
	return m


## Turn every cell whose world position satisfies pred(pos: Vector3) -> bool into a tall wall.
func wall_where(map: HexMap, pred: Callable) -> void:
	for c in map.cells.keys():
		if pred.call(Hex.to_world(c)):
			map.set_cell(c, 12, HexMap.Tile.WALL)


## Plain stationary stand-in for a hero (team heroes, 100 hp).
func add_hero(cell: Vector2i, level: float = 0.0) -> Actor:
	var h := Actor.new()
	h.team = GameWorld.TEAM_HEROES
	h.max_hp = 100.0
	h.display_name = "TestHero"
	GameWorld.spawn(h, Hex.to_world(cell, level))
	return h


## Poll once per physics frame; true as soon as cond() holds, false after max_frames.
func wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func fdist(a: Node3D, b: Node3D) -> float:
	return GameWorld.flat_distance(a.global_position, b.global_position)
