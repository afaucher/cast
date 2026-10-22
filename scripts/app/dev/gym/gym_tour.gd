class_name GymTour
extends Node
## The test gym's screenshot tour (`--gym --gym-tour <dir> --no-fog`; docs/design/test-gym.md): the camera visits the
## overview and each environment, then the panel, and saves `<dir>/gym_sheet.png` (every view, small, in a grid) and
## `<dir>/gym_panel.png` (the panel over the arena), then quits. Dev only (screenshots for the docs).

const VIEWS := [
	# [name, the crew's spot (GymMap.spots) or "", the camera's spot or "", zoom]
	["overview", "arena", "@center", 112.0],
	["arena", "arena", "", 19.0],
	["course", "course_pad", "@course", 30.0],
	["materials", "course_end", "@materials", 22.0],
	["offices", "cinema", "", 30.0],
	["hellgate", "throne", "", 24.0],
	["pool", "pool", "", 24.0],
	["moat", "moat", "", 28.0],
	["sewer", "sewer_a", "@sewer", 36.0],
	["gator", "sewer_a", "@gator", 13.0],
	["lava", "cave_a", "@cave", 34.0],
	["elevator", "lobby", "", 18.0],
]
const SETTLE := 1.2
const TILE := Vector2i(400, 225)
const COLS := 3

var game: Node = null
var gym: GymDev = null
var dir := ""


func run(g: Node, d: GymDev, out_dir: String) -> void:
	game = g
	gym = d
	dir = out_dir
	name = "GymTour"
	g.add_child(self)
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(1.0).timeout
	var rig: CameraRig = game.get("rig")
	var mark := Node3D.new()
	GameWorld.root.add_child(mark)
	var tiles: Array[Image] = []
	for v: Array in VIEWS:
		_layers(false)
		var spots := GymMap.spots(GameWorld.map)
		if str(v[1]) != "" and spots.has(v[1]):
			game.call("_teleport_crew", spots[v[1]])
		mark.global_position = _where(str(v[2]), spots, str(v[1]))
		rig.target = mark
		rig._zoom_target = float(v[3])
		rig.camera.size = float(v[3])
		rig.snap()
		if str(v[0]) == "arena":
			_stage_fight()
		await get_tree().create_timer(SETTLE).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
		tiles.append(img)
		gym.set_toggle("areas", false)
		print("[gym tour] %s" % v[0])
	# the panel over the arena, the hit areas on
	_layers(true)
	game.call("_teleport_crew", GymMap.spots(GameWorld.map)["arena"])
	rig.target = game.get("player")
	rig._zoom_target = 22.0
	rig.snap()
	await get_tree().create_timer(SETTLE).timeout
	await RenderingServer.frame_post_draw
	var panel_img := get_viewport().get_texture().get_image()
	panel_img.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	panel_img.save_png(dir.path_join("gym_panel.png"))
	var rows := ceili(tiles.size() / float(COLS))
	var sheet := Image.create(TILE.x * COLS, TILE.y * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.05, 0.05, 0.06))
	for i in tiles.size():
		tiles[i].convert(Image.FORMAT_RGB8)
		sheet.blit_rect(tiles[i], Rect2i(Vector2i.ZERO, TILE), Vector2i((i % COLS) * TILE.x, (i / COLS) * TILE.y))
	sheet.save_png(dir.path_join("gym_sheet.png"))
	print("[gym tour] saved %s" % dir)
	get_tree().quit()


## The HUD, the panel and the banners: off for the environment views, on for the panel's.
func _layers(on: bool) -> void:
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = on
	gym.panel.visible = on
	gym.set_toggle("areas", on)


func _where(key: String, spots: Dictionary, crew: String) -> Vector3:
	var m := GameWorld.map
	match key:
		"@center":
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for c: Vector2i in m.cells:
				var w := Hex.to_world(c)
				lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
				hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
			var mid := (lo + hi) * 0.5
			return Vector3(mid.x, 0.0, mid.y)
		"@course":
			return Vector3(GymMap.COURSE_X0 + 24.0, 1.5, 0.0)
		"@materials":
			return Vector3(GymMap.COURSE_X0 + float(GymMap.COURSE[GymMap.COURSE.size() - 1][0]) + 14.0, 1.5, 0.0)
		"@gator":
			var site: SiteBuilder.Site = game.get("_site")
			if site != null and not site.gators.is_empty():
				return site.gators[0].global_position
		"@sewer":
			return Hex.to_world(GymMap.center_of("sewer_a") + Hex.DIRS[0] * 6, 1.0)
		"@cave":
			var isles: Array = m.cave.get("isles", [])
			var ic: Vector2i = (isles[0] as Dictionary)["center"] if not isles.is_empty() else GymMap.center_of("cave_a")
			return Hex.to_world(ic, 3.0)
	var c: Vector2i = spots.get(crew, GymMap.center_of("arena"))
	return Hex.to_world(c, m.ground_level(Hex.to_world(c)))


## The arena view: a few monsters standing (AI off) by the dummies, the hit areas on.
func _stage_fight() -> void:
	gym.set_toggle("ai", false)
	var at := Hex.to_world(GymMap.center_of("arena") + Hex.DIRS[5] * 3)
	for k: String in ["monster:grunt", "monster:brute", "monster:pavise", "monster:goo_imp"]:
		gym.spawn(k, at)
		at += Vector3(2.2, 0.0, 0.0)
	gym.set_toggle("areas", true)

