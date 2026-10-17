extends Node3D
## Burning look-dev lab: the crew, a few monsters and an employee, all on fire, for screenshots. Scene:
## scenes/burning_lab.tscn.
##
##   godot --path . -- --scene res://scenes/burning_lab.tscn --shot <abs.png> [--shot-after 1.5] [--zoom 7]
##
## Everyone is frozen in place (AI and input off) and ignited by an invisible caster; the fires are the real
## Burning nodes, so what the shot shows is what the game draws.

const GAME_YAW := 45.0
const GAME_PITCH := -50.0

var camera: Camera3D


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var shot := _arg(a, "--shot")
	var after := float(_arg(a, "--shot-after", "1.5"))
	var zoom := float(_arg(a, "--zoom", "7.5"))
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 12):
		map.set_cell(c, 0).tag = "room:0"
	GameWorld.begin(map, self, 7)
	var terrain := HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 200.0
	add_child(camera)
	var caster := Hero.new()
	caster.display_name = "Caster"
	GameWorld.spawn(caster, Hex.to_world(Vector2i(-6, 6)))
	var crowd: Array[Actor] = []
	crowd.append(HeroFactory.spawn_hero(Vector2i(-1, 0), "Wick", Color(0.3, 0.8, 0.5), "sword", WickModel.new(), HeroKit.WICK))
	crowd.append(HeroFactory.spawn_hero(Vector2i(1, 0), "Gasket", Color(0.7, 0.4, 0.85), "sword", GasketModel.new(), HeroKit.GASKET))
	crowd.append(HeroFactory.spawn_hero(Vector2i(0, 1), "Rebar", Color(0.85, 0.5, 0.25), "sword", RebarModel.new(), HeroKit.REBAR))
	crowd.append(MonsterFactory.spawn("brute", Vector2i(-2, -2)))
	crowd.append(MonsterFactory.spawn("grunt", Vector2i(2, -2)))
	crowd.append(Employee.spawn(Vector2i(0, -3), {"style": "staff"}))
	for i in crowd.size():
		var m := crowd[i]
		m.set_physics_process(false)
		m.hp = m.max_hp
		Burning.ignite(m, caster, 10.0 if i != 4 else 9.0)
	_aim(zoom, Vector3(0, 0.9, -0.3))
	if shot != "":
		await get_tree().create_timer(after).timeout
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		print("shot ", shot, " ", img.save_png(shot))
		get_tree().quit()


static func _arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := a.find(key)
	if i >= 0 and i + 1 < a.size():
		return a[i + 1]
	return fallback


func _aim(size: float, tgt: Vector3) -> void:
	var yaw := deg_to_rad(GAME_YAW)
	var pitch := deg_to_rad(GAME_PITCH)
	camera.size = size
	camera.global_position = tgt + Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * 60.0
	camera.look_at(tgt, Vector3.UP)
