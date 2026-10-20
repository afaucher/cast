extends LabBase
## Monster awareness step 2 lab (docs/design/monster-awareness.md, "Step 2 as built"): the LIVE behaviours on a
## hand-built bit of bunker with the real terrain look (room A for the crew, a corridor, room B with a pack). Every view
## stages real actors (Monster kinds, PricedProp, a Hero) and lets the game logic run until the moment it shows.
## Scene: scenes/awareness_lab.tscn.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/awareness_lab.tscn --shot <dir>/step2.png
##
## --shot <png>  writes <base>_<view>.png for every view and quits:
##                 goblin_light   the goblin scout striking a light, Wick in his cone
##                 fireworks      his volley over room B, the pack walking toward where he saw the crew
##                 practice       an archer's practice arrow in flight at a priced prop
##                 brawl          a restless brute fight with onlookers drawn by the noise
## --view <name> only that view.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const ROOM_A := Vector2i(0, 0)
const ROOM_B := Vector2i(22, 0)
const RADIUS := 7
const WALL_HEIGHT := 3
const VIEWS: Array[String] = ["goblin_light", "fireworks", "practice", "brawl"]

var stage: Node3D


func _ready() -> void:
	MonsterSenses.restless_override = 1.0
	CombatLog.enabled = false
	_build_world()
	make_camera(300.0)
	camera.current = true
	_run.call_deferred()


func _build_world() -> void:
	map = HexMap.new()
	var cells := {}
	for c in Hex.range_cells(ROOM_A, RADIUS):
		cells[c] = "room:0"
	for c in Hex.range_cells(ROOM_B, RADIUS):
		cells[c] = "room:1"
	var xa := Hex.to_world(ROOM_A).x
	var xb := Hex.to_world(ROOM_B).x
	for q in range(0, 23):
		for r in range(-2, 2):
			var c := Vector2i(q, r)
			var x := Hex.to_world(c).x
			if x > xa and x < xb and not cells.has(c):
				cells[c] = "corridor"
	for c: Vector2i in cells:
		map.set_cell(c, 0).tag = cells[c]
	var walls := {}
	for c: Vector2i in cells.keys():
		for d in Hex.DIRS:
			var n: Vector2i = c + d
			if not cells.has(n):
				walls[n] = true
	for n: Vector2i in walls:
		map.set_cell(n, WALL_HEIGHT, HexMap.Tile.WALL)
	map.cut_walls()
	GameWorld.begin(map, self, 1)
	var terrain := HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)


func _new_stage() -> void:
	if stage != null:
		stage.free()
	stage = Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	GameWorld.begin(map, stage, 7)


func _aim(size: float, tgt: Vector3) -> void:
	aim(GAME_YAW, GAME_PITCH, size, tgt, 80.0)


func _wick(cell: Vector2i) -> Hero:
	var h := HeroFactory.spawn_hero(cell, "Wick", Color(0.35, 0.8, 1.0), "bow", WickModel.new(), "wick")
	h.set_modifier("lab_ward", 0.0, 9999.0)
	return h


func _monster(kind: String, cell: Vector2i, face: Vector3, sees: bool = true) -> Monster:
	var m := MonsterFactory.spawn(kind, cell)
	m.set_spawn_facing(face)
	if not sees:
		m.aggro_range = 0.001   # (hears, sees nothing: the lab's crew stays out of the fight)
	return m


func _wait(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _snap(view: String) -> void:
	await snap("%s_%s.png" % [shot_path.get_basename(), view], 3)


func _run() -> void:
	for i in 10:
		await get_tree().process_frame
	for v in VIEWS:
		if only_view != "" and v != only_view:
			continue
		_new_stage()
		match v:
			"goblin_light":
				await _view_goblin_light()
			"fireworks":
				await _view_fireworks()
			"practice":
				await _view_practice()
			"brawl":
				await _view_brawl()
		if shot_path != "":
			await _snap(v)
		else:
			await get_tree().create_timer(4.0).timeout
	if shot_path != "":
		get_tree().quit()


# --- Views ----------------------------------------------------------------------------------------------------------

func _view_goblin_light() -> void:
	var wick := _wick(Vector2i(4, 1))
	var g = _monster("goblin", Vector2i(10, 0), Vector3.LEFT)
	g._glance_t = 99.0
	_monster("grunt", Vector2i(20, 3), Vector3.RIGHT, false)
	_monster("swarmer", Vector2i(19, -2), Vector3.RIGHT, false)
	_aim(10.0, (g.global_position + wick.global_position) * 0.5 + Vector3(1.5, 0.0, 0.0))
	await _wait(func() -> bool: return g.scout_phase == g.Phase.LIGHT and g._telegraph > 0.75, 60 * 8)


func _view_fireworks() -> void:
	var wick := _wick(Vector2i(4, 0))
	var pack: Array = []
	for row in [["grunt", Vector2i(22, 3)], ["grunt", Vector2i(25, -3)], ["archer", Vector2i(27, 0)], ["brute", Vector2i(24, 1)],
			["swarmer", Vector2i(21, -4)], ["swarmer", Vector2i(22, -4)], ["swarmer", Vector2i(21, -3)]]:
		pack.append(_monster(row[0], row[1], Vector3.RIGHT, false))
	var g = _monster("goblin", Vector2i(13, 0), Vector3.LEFT)
	await get_tree().physics_frame
	g.aggro(wick)
	await _wait(func() -> bool: return int(g.volleys) > 0, 60 * 8)
	await _wait(func() -> bool: return false, 90)                  # the bursts over the room, the pack walking in
	_aim(19.0, Hex.to_world(Vector2i(18, 0)) + Vector3(0.0, 0.0, -1.0))


func _view_practice() -> void:
	_wick(Vector2i(12, 0))                                          # in the corridor: 22 from the archer, out of its sight
	var a = _monster("archer", Vector2i(26, -2), Vector3.RIGHT)
	var prop := PricedProp.spawn(Vector2i(24, 2), "crystal_lamp", {"yaw": 200.0})
	await get_tree().physics_frame
	a._practice_t = 0.2
	await _wait(func() -> bool: return int(a.practice_shots) > 0, 60 * 8)
	await _wait(func() -> bool: return false, 7)                   # the arrow halfway
	_aim(8.0, (a.global_position + prop.global_position) * 0.5)


func _view_brawl() -> void:
	_wick(Vector2i(10, 0))
	var b1 = _monster("brute", Vector2i(21, 1), Vector3.RIGHT)
	var b2 = _monster("brute", Vector2i(24, -1), Vector3.LEFT)
	var crowd: Array = []
	for row in [["grunt", Vector2i(19, 5), Vector3.RIGHT], ["grunt", Vector2i(27, 3), Vector3.LEFT], ["archer", Vector2i(26, -5), Vector3.LEFT],
			["swarmer", Vector2i(20, -4), Vector3.RIGHT], ["swarmer", Vector2i(21, -5), Vector3.RIGHT], ["swarmer", Vector2i(19, -3), Vector3.RIGHT]]:
		crowd.append(_monster(row[0], row[1], row[2], false))
	await get_tree().physics_frame
	b1._start_fight(b2)
	await _wait(func() -> bool: return b1._fight_phase == b1.FIGHT_SLAMS and b1._fight_slams_done >= 1 and b1._fight_wind > 0.6, 60 * 20)
	_aim(12.0, (b1.global_position + b2.global_position) * 0.5 + Vector3(0.0, 0.0, 0.5))
