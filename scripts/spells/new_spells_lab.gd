extends Node3D
## Look-dev lab for Vines, Damp, Coffee and Chicken: the crew, a few monsters and an employee in the middle of a flat room,
## with the chosen spell cast on them by an invisible caster. Scene: scenes/new_spells_lab.tscn.
##
##   godot --path . -- --scene res://scenes/new_spells_lab.tscn --spell vines|damp|coffee|chicken --shot <abs.png>
##                     [--shot-after 1.2] [--zoom 7.5] [--pitch -50] [--walk] [--closeup] [--pickup]
##
## --spell <id>      which spell (default vines)
## --shot <png>      save a screenshot --shot-after game seconds after the cast (default 1.2) and quit
## --zoom <s>        camera size (default 7.5; the game's camera is 24)
## --pitch <deg>     camera pitch (default -50; the game's camera is -56)
## --walk            Wick walks to and fro so the damp footprints / the twitch show
## --closeup         chicken only: no crowd, the chicken model close up in a few poses (rest, run, the peck's wind-up,
##                   the peck, a flap) beside an imp for scale
## --pickup          chicken only: the Chicken feather pickup on the floor beside two others, by Wick
##
## Everyone is frozen in place (AI off) so the shot shows the spell, and the real spell code runs: what you see is
## what the game draws. Damp starts with a few fires burning (to see them put out) and a grime layer for the puddles.
## Chicken keeps the monsters' AI on but blind (aggro_range 0: they ignore the crew), so the flock's pecks pull them about.

const GAME_YAW := 45.0
const GAME_PITCH := -50.0

var camera: Camera3D
var _pitch := GAME_PITCH
var _walker: Hero = null
var _walk_t := 0.0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var spell := _arg(a, "--spell", "vines")
	var shot := _arg(a, "--shot")
	var after := float(_arg(a, "--shot-after", "1.2"))
	var zoom := float(_arg(a, "--zoom", "7.5"))
	_pitch = float(_arg(a, "--pitch", str(GAME_PITCH)))
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
	if spell == "chicken" and (a.has("--closeup") or a.has("--pickup")):
		await _chicken_still(a, shot, zoom)
		return
	var caster := Hero.new()
	caster.display_name = "Caster"
	GameWorld.spawn(caster, Hex.to_world(Vector2i(-7, 7)))
	caster.visible = false
	var crowd: Array[Actor] = []
	var target := Vector3.ZERO if spell != "coffee" else Hex.to_world(Vector2i(0, 0))
	if spell == "chicken":
		target = _chicken_fight(caster)
		_aim(zoom, target + Vector3(0.0, 0.6, 0.0))
	else:
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
	SpellBook.cast(spell, caster, 1.0, target)
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


## Chicken mid-fight: the crew (frozen) on the left of the screen, a pack on the right with its AI on but blind to the crew
## (aggro_range 0), so only the flock's pecks move it. The flock lands between them. Returns where it is cast.
func _chicken_fight(caster: Hero) -> Vector3:
	var right := Vector3(1.0, 0.0, -1.0).normalized()   # screen right at the camera's yaw 45
	var down := Vector3(1.0, 0.0, 1.0).normalized()
	var crew: Array[Actor] = []
	crew.append(HeroFactory.spawn_hero(Vector2i.ZERO, "Wick", Color(0.3, 0.8, 0.5), "sword", WickModel.new(), HeroKit.WICK))
	crew.append(HeroFactory.spawn_hero(Vector2i(0, 1), "Gasket", Color(0.7, 0.4, 0.85), "sword", GasketModel.new(), HeroKit.GASKET))
	crew.append(HeroFactory.spawn_hero(Vector2i(1, 1), "Rebar", Color(0.85, 0.5, 0.25), "sword", RebarModel.new(), HeroKit.REBAR))
	var spots := [right * -5.0 - down * 1.2, right * -5.6 + down * 0.6, right * -4.2 + down * 1.6]
	for i in crew.size():
		crew[i].global_position = spots[i]
		crew[i].snap_to_ground()
		crew[i].set_physics_process(false)
		crew[i].face_point(Vector3.ZERO)
	var pack := [["brute", right * 3.6 - down * 1.4], ["grunt", right * 2.6 + down * 1.4], ["grunt", right * 4.4 + down * 0.4],
		["swarmer", right * 2.2 - down * 0.4], ["swarmer", right * 3.0 + down * 0.2], ["archer", right * 5.6 - down * 0.2]]
	for e: Array in pack:
		var m := MonsterFactory.spawn(str(e[0]), Hex.from_world(e[1]))
		m.global_position = e[1]
		m.snap_to_ground()
		m.aggro_range = 0.0   # blind to the crew: only the pecks move them
		m.set_spawn_facing(-right)
	caster.global_position = right * -6.0
	return right * -0.3


## Chicken stills: the model close up in a few poses beside an imp (--closeup), or the feather pickup (--pickup).
func _chicken_still(a: PackedStringArray, shot: String, zoom: float) -> void:
	if a.has("--closeup"):
		# A row across the screen (the camera looks down yaw 45: screen right is world (1, 0, -1)), all three-quarter on.
		var right := Vector3(1.0, 0.0, -1.0).normalized()
		var down := Vector3(1.0, 0.0, 1.0).normalized()
		var poses := ["rest", "run", "windup", "peck", "flap"]
		for i in poses.size():
			var m := ChickenModel.new()
			add_child(m)
			m.position = right * (-3.0 + 1.25 * float(i)) - down * 0.9
			m.rotation.y = deg_to_rad(-110.0)
			m.pose_preview(poses[i], 1.0 if poses[i] != "windup" else 0.9)
		var imp := MonsterModels.make("swarmer")
		add_child(imp)
		imp.position = right * 3.3 - down * 0.9
		imp.rotation.y = deg_to_rad(-110.0)
		# A real chicken too, pecking at Wick, so the feathers and the "0" show.
		var target := HeroFactory.spawn_hero(Vector2i.ZERO, "Wick", Color(0.3, 0.8, 0.5), "sword", WickModel.new(), HeroKit.WICK)
		target.set_physics_process(false)
		target.global_position = right * -1.2 + down * 1.6
		var c := Chicken.new()
		c.home = target.global_position
		c.born = GameWorld.time
		GameWorld.spawn(c, target.global_position + right * 1.1)
		_aim(zoom if zoom != 7.5 else 5.0, down * 0.3 + Vector3.UP * 0.5)
	else:
		var hero := HeroFactory.spawn_hero(Vector2i(-1, 0), "Wick", Color(0.3, 0.8, 0.5), "sword", WickModel.new(), HeroKit.WICK)
		hero.set_physics_process(false)
		ComponentPickup.drop("chicken", 3, Vector3(0.4, 0.0, 0.2), 0.0)
		ComponentPickup.drop("coffee", 3, Vector3(2.0, 0.0, -0.6), 0.0)
		ComponentPickup.drop("teeth", 3, Vector3(1.6, 0.0, 1.3), 0.0)
		_aim(zoom if zoom != 7.5 else 4.0, Vector3(0.7, 0.5, 0.2))
	if shot != "":
		await get_tree().create_timer(float(_arg(a, "--shot-after", "1.0"))).timeout
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
	var pitch := deg_to_rad(_pitch)
	camera.size = size
	camera.global_position = tgt + Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * 60.0
	camera.look_at(tgt, Vector3.UP)
