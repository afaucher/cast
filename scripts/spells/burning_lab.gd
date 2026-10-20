extends LabBase
## Burning look-dev lab: the crew, a few monsters and an employee, all on fire, for screenshots. Scene:
## scenes/burning_lab.tscn.
##
##   godot --path . -- --scene res://scenes/burning_lab.tscn --shot <abs.png> [--shot-after 1.5] [--zoom 7]
##
## Everyone is frozen in place (AI and input off) and ignited by an invisible caster; the fires are the real
## Burning nodes, so what the shot shows is what the game draws.

const GAME_YAW := 45.0
const GAME_PITCH := -50.0


func _ready() -> void:
	var after := float(arg(args, "--shot-after", "1.5"))
	var zoom := float(arg(args, "--zoom", "7.5"))
	build_arena(12, 12, 12, 7)
	make_camera()
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
	aim(GAME_YAW, GAME_PITCH, zoom, Vector3(0, 0.9, -0.3))
	if shot_path != "":
		shot_after(shot_path, after)
