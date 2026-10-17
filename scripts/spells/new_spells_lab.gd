extends Node3D
## Look-dev lab for Vines, Damp and Coffee: the crew, a few monsters and an employee in the middle of a flat room, with
## the chosen spell cast on them by an invisible caster. Scene: scenes/new_spells_lab.tscn.
##
##   godot --path . -- --scene res://scenes/new_spells_lab.tscn --spell vines|damp|coffee --shot <abs.png>
##                     [--shot-after 1.2] [--zoom 7.5] [--walk]
##
## --spell <id>      which spell (default vines)
## --shot <png>      save a screenshot --shot-after game seconds after the cast (default 1.2) and quit
## --zoom <s>        camera size (default 7.5)
## --walk            Wick walks to and fro so the damp footprints / the twitch show
##
## Everyone is frozen in place (AI off) so the shot shows the spell, and the real spell code runs: what you see is
## what the game draws. Damp starts with a few fires burning (to see them put out) and a grime layer for the puddles.

const GAME_YAW := 45.0
const GAME_PITCH := -50.0

var camera: Camera3D
var _walker: Hero = null
var _walk_t := 0.0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var spell := _arg(a, "--spell", "vines")
	var shot := _arg(a, "--shot")
	var after := float(_arg(a, "--shot-after", "1.2"))
	var zoom := float(_arg(a, "--zoom", "7.5"))
	var map := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 12):
		map.set_cell(c, 0).tag = "room:0"
	GameWorld.begin(map, self, 7)
	var terrain := HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)
	GrimeLayer.attach(self, map, null, 5)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 200.0
	add_child(camera)
	var caster := Hero.new()
	caster.display_name = "Caster"
	GameWorld.spawn(caster, Hex.to_world(Vector2i(-7, 7)))
	caster.visible = false
	var crowd: Array[Actor] = []
	crowd.append(HeroFactory.spawn_hero(Vector2i(-1, 0), "Wick", Color(0.3, 0.8, 0.5), "sword", WickModel.new(), HeroKit.WICK))
	crowd.append(HeroFactory.spawn_hero(Vector2i(1, 0), "Gasket", Color(0.7, 0.4, 0.85), "sword", GasketModel.new(), HeroKit.GASKET))
	crowd.append(HeroFactory.spawn_hero(Vector2i(0, 1), "Rebar", Color(0.85, 0.5, 0.25), "sword", RebarModel.new(), HeroKit.REBAR))
	crowd.append(MonsterFactory.spawn("brute", Vector2i(-2, -2)))
	crowd.append(MonsterFactory.spawn("grunt", Vector2i(2, -2)))
	crowd.append(MonsterFactory.spawn("swarmer", Vector2i(0, -3)))
	crowd.append(MonsterFactory.spawn("swarmer", Vector2i(1, -3)))
	crowd.append(Employee.spawn(Vector2i(-3, 1), {"style": "staff"}))
	for m in crowd:
		m.set_physics_process(false)
	_walker = crowd[0] as Hero
	if spell == "damp":
		for i in [3, 4, 7]:
			Burning.ignite(crowd[i], caster, 12.0)
	_aim(zoom, Vector3(0, 0.9, -0.3))
	await get_tree().create_timer(0.3).timeout
	SpellBook.cast(spell, caster, 1.0, Vector3(0.0, 0.0, 0.0) if spell != "coffee" else Hex.to_world(Vector2i(0, 0)))
	if shot != "":
		await get_tree().create_timer(after).timeout
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		print("shot ", shot, " ", img.save_png(shot))
		get_tree().quit()


func _physics_process(delta: float) -> void:
	if _walker == null or not OS.get_cmdline_user_args().has("--walk"):
		return
	_walk_t += delta
	_walker.move(Vector3(1.0 if fmod(_walk_t, 2.4) < 1.2 else -1.0, 0.0, 0.0), delta)


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
