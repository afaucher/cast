extends LabBase
## Hellgate look-dev lab: a normal gate and the big origin gate set into slate hexes (HexMapView +
## DungeonLook), with the three heroes for scale and a few monsters spawned by the gates. Scene:
## scenes/hellgate_lab.tscn.
##
##   godot --path . -- --scene res://scenes/hellgate_lab.tscn --shot <abs.png> [--view <name>]
##
## --shot <png>   renders every view and writes <base>_<view>.png (base = the png without extension):
##                  game     the real game camera (ortho yaw 45, pitch -56, size 24): both gates, heroes, monsters
##                  close    the normal gate close up, game yaw, a bit steeper
##                  side     the normal gate from the side (low angle)
##                  origin   the origin gate, game yaw, size 16
##                  flare    the normal gate holding its burst telegraph
##                  phase    the origin gate winding up its phase shove
##                  closing  the normal gate part way through its collapse
##                  fight    game camera, gates active and monsters rushing a hero
## --view <name>  only that view, written to <png> exactly.
## No --shot: an interactive lab. A stand-in hero (invulnerable) walks in circles so the gates wake and spawn.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0

const VIEWS: Array[String] = ["game", "close", "side", "origin", "flare", "phase", "closing", "fight"]

var gate: Hellgate
var origin_gate: Hellgate
var wick: WickModel
var gasket: GasketModel
var rebar: RebarModel
var hero: Actor = null
var _t := 0.0


func _ready() -> void:
	build_arena(22, 15, 20, 1)
	make_camera()
	gate = Hellgate.spawn(Vector2i(-6, 3), {"difficulty": 0.6, "depth": 2})
	origin_gate = Hellgate.spawn(Vector2i(5, -3), {"difficulty": 0.8, "depth": 3, "origin": true})
	if shot_path != "":
		for g in [gate, origin_gate]:
			g.set_physics_process(false)
			g.set_process(false)
		_place_heroes()
		_run_shots()
	else:
		hero = Actor.new()
		hero.team = GameWorld.TEAM_HEROES
		hero.max_hp = 1.0e9
		hero.display_name = "Stand-in"
		GameWorld.spawn(hero, Hex.to_world(Vector2i(0, 0)))
		var m := WickModel.new()
		hero.add_child(m)
		aim(GAME_YAW, GAME_PITCH, GAME_SIZE, Vector3(0, 0.6, 0))


func _place_heroes() -> void:
	wick = WickModel.new()
	gasket = GasketModel.new()
	rebar = RebarModel.new()
	var spots: Array = [[wick, Vector2i(-3, 4)], [gasket, Vector2i(-2, 5)], [rebar, Vector2i(-4, 5)]]
	for e: Array in spots:
		var m: LowPolyModel = e[0]
		add_child(m)
		m.idle_enabled = false
		m.apply_idle(0.6)
		m.global_position = Hex.to_world(e[1])
		m.rotation.y = deg_to_rad(GAME_YAW + 180.0)


func _process(delta: float) -> void:
	if shot_path != "" or hero == null:
		return
	_t += delta
	var p := Hex.to_world(Vector2i(-3, 2)) + Vector3(cos(_t * 0.5), 0, sin(_t * 0.5)) * 7.0
	hero.global_position = p
	hero.facing = Vector3(-sin(_t * 0.5), 0, cos(_t * 0.5))


func _clear_monsters() -> void:
	for n in get_tree().get_nodes_in_group("monsters"):
		n.free()


func _prepare(view: String) -> void:
	_clear_monsters()
	for g in [gate, origin_gate]:
		g.model.set_flare(0.0)
		g.model.freeze_at(1.7)
		g.fx_enabled = false
	var gp := gate.global_position
	var op := origin_gate.global_position
	var mid := (gp + op) * 0.5
	match view:
		"game":
			_burst(gate, 4)
			_burst(origin_gate, 6)
			aim(GAME_YAW, GAME_PITCH, GAME_SIZE, mid + Vector3(0, 0.5, 0))
		"fight":
			gate.activate()
			origin_gate.activate()
			_burst(gate, 5)
			_burst(origin_gate, 6)
			aim(GAME_YAW, GAME_PITCH, GAME_SIZE, mid + Vector3(0, 0.5, 0))
		"close":
			aim(GAME_YAW, -42.0, 7.5, gp + Vector3(0, 0.9, 0))
		"side":
			aim(160.0, -18.0, 7.5, gp + Vector3(0, 1.0, 0))
		"origin":
			aim(GAME_YAW, -50.0, 15.0, op + Vector3(0, 1.4, 0))
		"flare":
			gate.activate()
			gate.model.set_flare(1.0)
			gate.model.pulse(0.6)
			gate.model.freeze_at(1.7)
			aim(GAME_YAW, -42.0, 7.5, gp + Vector3(0, 0.9, 0))
		"phase":
			origin_gate.activate()
			origin_gate.model.set_phase(1)
			origin_gate.model.telegraph_shove(0.9, Hellgate.SHOVE_RADIUS)
			origin_gate.model.freeze_at(1.7)
			origin_gate.model._shove_t = 0.8
			origin_gate.model._animate(0.0)
			aim(GAME_YAW, -50.0, 17.0, op + Vector3(0, 1.0, 0))
		"closing":
			gate.model.freeze_at(1.7, 0.42)
			aim(GAME_YAW, -42.0, 7.5, gp + Vector3(0, 0.9, 0))


func _burst(g: Hellgate, n: int) -> void:
	g.activate()
	g.spawn_cap = 20
	g.burst_size = n
	g.spawn_burst_now()
	g.model.set_active(true)


func _run_shots() -> void:
	for i in 20:
		await get_tree().process_frame
	var base := shot_path.get_basename()
	var list: Array[String] = []
	if only_view == "":
		list.append_array(VIEWS)
	else:
		list.append(only_view)
	for v in list:
		_prepare(v)
		for i in 4:
			await get_tree().physics_frame
		var out := shot_path if only_view != "" else "%s_%s.png" % [base, v]
		await snap(out, 8)
		if v == "closing":
			gate.model._closing = false
			gate.model._close_t = 0.0
			gate.model._close_k = 0.0
	finish()

