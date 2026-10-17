extends Node
## Autoload "GameWorld": the one place systems find the map, the actors and
## where to put spawned things. Set up by the game scene (or a test) via
## begin(); everything else only reads from here.

signal actor_spawned(actor: Actor)
signal actor_died(actor: Actor)

const TEAM_HEROES := 0
const TEAM_MONSTERS := 1
## Employees and priced props: not a side in the fight. Area spells (team -1) still hit them.
const TEAM_NEUTRAL := 2

var map: HexMap = null
var root: Node3D = null      ## parent for actors, projectiles, zones, fx
var rng := RandomNumberGenerator.new()
var floor_drops := 0         ## component pickups monsters dropped on this floor (SpellComponents.FLOOR_DROP_CAP)
var time := 0.0              ## game clock (seconds of physics time); use for cooldowns/durations


func _physics_process(delta: float) -> void:
	time += delta


func begin(new_map: HexMap, new_root: Node3D, seed_value: int = 0) -> void:
	map = new_map
	root = new_root
	rng.seed = seed_value
	floor_drops = 0


func end() -> void:
	map = null
	root = null


## Add any node (projectile, zone, effect) to the world.
func spawn(node: Node3D, at: Vector3 = Vector3.INF) -> Node3D:
	root.add_child(node)
	if at != Vector3.INF:
		node.global_position = at
	if node is Actor:
		actor_spawned.emit(node)
	return node


func actors() -> Array[Actor]:
	var out: Array[Actor] = []
	if root == null:
		return out
	for n in root.get_tree().get_nodes_in_group("actors"):
		var a := n as Actor
		if a and not a.dead:
			out.append(a)
	return out


func team_actors(team: int) -> Array[Actor]:
	return actors().filter(func(a: Actor) -> bool: return a.team == team)


## Living actors whose X/Z distance to `pos` is within radius (+ their own radius).
## team = -1 for any team.
func actors_in_radius(pos: Vector3, radius: float, team: int = -1) -> Array[Actor]:
	var out: Array[Actor] = []
	for a in actors():
		if team != -1 and a.team != team:
			continue
		if flat_distance(a.global_position, pos) <= radius + a.radius:
			out.append(a)
	return out


func nearest_actor(pos: Vector3, team: int, max_range: float = INF) -> Actor:
	var best: Actor = null
	var best_d := max_range
	for a in team_actors(team):
		var d := flat_distance(a.global_position, pos)
		if d <= best_d:
			best = a
			best_d = d
	return best


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func other_team(team: int) -> int:
	return TEAM_MONSTERS if team == TEAM_HEROES else TEAM_HEROES
