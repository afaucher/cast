extends Node3D
## Room fog and office doors lab (docs/design/exploration.md, "Decisions: map information, fog and doors", 2026-10-19): a real generated contract floor
## (DungeonGen.for_run + SiteBuilder: rooms, halls, props, decor, notes, mail, gates, employees, packs) with an office door
## in every doorway that takes one, the crew, the game camera (CameraRig) and the fog (RoomFog + FogView). Nothing here is
## wired into game.gd. Scene: scenes/fog_lab.tscn.
##
##   godot --path . -- --scene res://scenes/fog_lab.tscn [--seed 7] [--look a|b|c]
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/fog_lab.tscn --shot <dir>    (the screenshots, then quits)
##
## Keys: 1 / 2 / 3 the looks (A black void, B blueprint, C smoke), 4 / 5 / 6 the doors (single, double, slider), 0 fog off / on, WASD walk Wick (the crew follows), E the
## door in reach (shut / open), B a brute behind the nearest shut door comes for Wick and smashes it, R forget what was
## seen, L space labels. The monsters stand frozen (the lab is about what shows, not the fight); the brute is live.

const RUN_ARCHETYPE := "prepper"
const WALK_STEP := 0.22          ## the staged fast walk: world units a physics frame
const TRAIL_GAP := 14            ## the followers walk this many trail points behind the one ahead

var seed_value := 7
var shot_dir := ""
var run: ContractRun
var map: HexMap
var plan: SitePlan
var site: SiteBuilder.Site
var fog: RoomFog
var fog_view: FogView
var rig: CameraRig
var wick: Hero
var crew: Array[Hero] = []
var doors: Array[OfficeDoor] = []
var door_ids: Array[int] = []
var door_style := OfficeDoor.DEFAULT_STYLE
var prompt: UsePrompt
var caption: Label
var labels: Array[Label3D] = []
var brute: Monster = null
var _trail: Array[Vector3] = []
var _staging := false


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	seed_value = int(_arg(a, "--seed", "7"))
	door_style = _arg(a, "--style", OfficeDoor.DEFAULT_STYLE)
	shot_dir = _arg(a, "--shot")
	CombatLog.enabled = false
	_build()
	match _arg(a, "--look", "a"):
		"b":
			fog_view.look = FogView.LOOK_BLUEPRINT
		"c":
			fog_view.look = FogView.LOOK_SMOKE
	if shot_dir != "":
		_shots.call_deferred()


static func _arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := a.find(key)
	return a[i + 1] if i >= 0 and i + 1 < a.size() else fallback


func _build() -> void:
	run = ContractRun.make(RUN_ARCHETYPE, seed_value, 0.5)
	map = DungeonGen.for_run(run, 1)
	plan = SiteBuilder.plan(map, run, 1, ContractParts.prop_catalog(run.site_type))
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	GameWorld.begin(map, world, run.floor_seed(1))
	var view := HexMapView.new()
	view.name = "Terrain"
	add_child(view)
	view.build(map)
	DungeonLook.apply(self, map)
	site = SiteBuilder.spawn(map, run, plan)
	for m in site.monsters + site.scouts:
		m.aggro_range = 0.0                      # frozen: no sight, no idle life (the lab is about what shows)
	for g in site.gates:
		g.set_physics_process(false)
	for e in site.employees:
		e.set_physics_process(false)
	fog = RoomFog.build(map)
	door_ids = DoorPlan.choose(fog.doorways, plan, run.floor_seed(1))
	if _arg(OS.get_cmdline_user_args(), "--doors") == "narrow":
		door_ids.clear()
		for dw in fog.doorways:
			if bool(dw["door_ok"]):
				door_ids.append(int(dw["id"]))
	print("fog lab: seed %d, %d doorways, %d narrow, doors on %s (DoorPlan.DOOR_SHARE %.2f), style %s" % [seed_value,
		fog.doorways.size(), fog.doorways.filter(func(dw: Dictionary) -> bool: return bool(dw["narrow"])).size(), str(door_ids),
		DoorPlan.DOOR_SHARE, door_style])
	_spawn_doors()
	var start: Vector2i = map.cells_with_tag("start")[0]
	wick = _hero(start, "wick", "Wick", Color(0.3, 0.55, 0.95))
	crew = [wick, _hero(start, "rebar", "Rebar", Color(0.85, 0.5, 0.25)), _hero(start, "gasket", "Gasket", Color(0.7, 0.4, 0.85))]
	_place_crew_at(Hex.to_world(start, float(map.get_cell(start).level)))
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.target = wick
	rig.snap()
	fog_view = FogView.new()
	fog_view.name = "FogView"
	add_child(fog_view)
	fog_view.setup(map, fog, rig.camera)
	fog_view.heroes = crew
	var still: Array = []
	for n in site.props + site.decor + site.notes + site.packages + site.gates:
		if n is Node3D and n.name != "ThemeLights":
			still.append(n)
	fog_view.track_static(still)
	fog_view.watch_doors(doors)
	fog_view.refresh_now(true)
	prompt = UsePrompt.new()
	add_child(prompt)
	var layer := CanvasLayer.new()
	add_child(layer)
	caption = Label.new()
	caption.position = Vector2(24, 18)
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
	caption.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.04))
	caption.add_theme_constant_override("outline_size", 6)
	layer.add_child(caption)


## (Re)build the doors on `door_ids` in `door_style`, keeping each one's shut / broken state.
func _spawn_doors() -> void:
	var state := {}
	for d in doors:
		if is_instance_valid(d):
			state[d.doorway_id] = d.shut
			d.queue_free()
	doors.clear()
	for id in door_ids:
		var d := OfficeDoor.spawn(fog.doorways[id], door_style, bool(state.get(id, true)))
		if d != null:
			doors.append(d)
	if fog_view != null:
		fog_view.watch_doors(doors)


## A door in `style` on doorway `id` (the lab's showcase), replacing any door there.
func door_at(id: int, style: String) -> OfficeDoor:
	for d in doors:
		if is_instance_valid(d) and d.doorway_id == id:
			doors.erase(d)
			d.free()
			break
	if map.blockers.has("door:%d" % id):
		map.clear_blocker("door:%d" % id)
	var nd := OfficeDoor.spawn(fog.doorways[id], style, true)
	doors.append(nd)
	fog_view.watch_doors([nd])
	return nd


func _hero(cell: Vector2i, kit: String, hero_name: String, color: Color) -> Hero:
	var model: Node3D = WickModel.new()
	match kit:
		"rebar":
			model = RebarModel.new()
		"gasket":
			model = GasketModel.new()
	var h := HeroFactory.spawn_hero(cell, hero_name, color, "sword", model, kit)
	h.set_modifier("lab_ward", 0.0, 1.0e9)
	return h


func _place_crew_at(p: Vector3) -> void:
	_trail.clear()
	for i in crew.size():
		var q := p + Vector3(-0.9 * i, 0.0, 0.6 * i)
		if map.blocks_point(q, 0.4) or is_nan(map.ground_height(q)):
			q = p
		q.y = map.ground_height(q)
		crew[i].global_position = q
	for i in TRAIL_GAP * 3:
		_trail.append(p)


# --- Live ------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if wick == null or _staging:
		return
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir += Vector3(-1, 0, -1)
	if Input.is_physical_key_pressed(KEY_S):
		dir += Vector3(1, 0, 1)
	if Input.is_physical_key_pressed(KEY_A):
		dir += Vector3(-1, 0, 1)
	if Input.is_physical_key_pressed(KEY_D):
		dir += Vector3(1, 0, -1)
	if dir.length() > 0.01:
		wick.move(dir.normalized(), delta)
		_push_trail()
	for i in range(1, crew.size()):
		var want := _trail[maxi(0, _trail.size() - 1 - TRAIL_GAP * i)]
		var d := want - crew[i].global_position
		d.y = 0.0
		if d.length() > 0.35:
			crew[i].move(d.normalized(), delta)


func _push_trail() -> void:
	if _trail.is_empty() or _trail[-1].distance_to(wick.global_position) > 0.2:
		_trail.append(wick.global_position)
		if _trail.size() > TRAIL_GAP * 4:
			_trail.pop_front()


func _process(_delta: float) -> void:
	if wick == null:
		return
	var d := OfficeDoor.interact_target(wick)
	if d != null and not _staging:
		prompt.show_at(d.prompt_point(), "E", d.use_verb())
	else:
		prompt.hide_prompt()
	var c := fog.census()
	caption.text = "%s%s\nspaces: %d in view, %d seen, %d next, %d unknown\n1 2 3 look   4 5 6 door   0 fog   WASD walk   E door   B brute   R forget   L labels" % [
		FogView.LOOK_NAMES[fog_view.look], "" if fog_view.enabled else "  (fog off)", c["in_view"], c["seen"], c["next"], c["unknown"]]
	for l in labels:
		var s := int(l.get_meta("space"))
		l.text = "%s\n%s" % [fog.tags[s], RoomFog.NAMES[fog.state[s]]]


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.physical_keycode:
		KEY_1:
			fog_view.look = FogView.LOOK_VOID
		KEY_2:
			fog_view.look = FogView.LOOK_BLUEPRINT
		KEY_3:
			fog_view.look = FogView.LOOK_SMOKE
		KEY_0:
			fog_view.enabled = not fog_view.enabled
		KEY_4, KEY_5, KEY_6:
			door_style = OfficeDoorModel.STYLES[k.physical_keycode - KEY_4]
			_spawn_doors()
		KEY_E:
			var d := OfficeDoor.interact_target(wick)
			if d != null:
				d.use(wick)
		KEY_B:
			_brute_at_nearest_door()
		KEY_R:
			fog.seen.fill(0)
			fog_view.refresh_now()
		KEY_L:
			_toggle_labels()


func _toggle_labels() -> void:
	if not labels.is_empty():
		for l in labels:
			l.queue_free()
		labels.clear()
		return
	for s in fog.space_count():
		var sum := Vector3.ZERO
		var n := 0
		for c: Vector2i in fog.cell_space:
			if int(fog.cell_space[c]) == s:
				sum += Hex.to_world(c, float(map.get_cell(c).level))
				n += 1
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font_size = 64
		l.pixel_size = 0.02
		l.outline_size = 12
		l.modulate = Color(1.0, 0.95, 0.6) if not fog.is_hall[s] else Color(0.6, 0.95, 1.0)
		l.render_priority = 127
		l.set_meta("space", s)
		add_child(l)
		l.global_position = sum / maxf(1.0, float(n)) + Vector3.UP * 2.5
		labels.append(l)


## A brute on the far side of the shut door nearest Wick, chasing him: it walks into the door and smashes it.
func _brute_at_nearest_door() -> OfficeDoor:
	var best: OfficeDoor = null
	var best_d := INF
	for d in doors:
		if d.broken or not d.shut:
			continue
		var dd := GameWorld.flat_distance(d.global_position, wick.global_position)
		if dd < best_d:
			best_d = dd
			best = d
	if best == null:
		return null
	var side := signf(best.local_flat(wick.global_position).y)
	var at := best.global_position - best.axis * side * 4.0
	brute = MonsterFactory.spawn("brute", Hex.from_world(at))
	brute.global_position = Vector3(at.x, map.ground_height(at), at.z)
	await get_tree().physics_frame
	brute.aggro(wick)
	return best


# --- Staged walk (the screenshots) -----------------------------------------------------------------------------------

## Walk the crew to `cell` along a real path, fast: Wick steps WALK_STEP a frame (doors open as he walks into them),
## the others follow his trail, the fog follows them.
func walk_to(cell: Vector2i) -> void:
	_staging = true
	var path := map.find_path(wick.current_cell(), cell, true)
	for c in path:
		var goal := Hex.to_world(c, float(map.get_cell(c).level))
		while true:
			var d := goal - wick.global_position
			d.y = 0.0
			if d.length() < 0.05:
				break
			var step := d.normalized() * minf(WALK_STEP, d.length())
			var p := wick.global_position + step
			p.y = map.ground_height(p)
			wick.global_position = p
			wick.face_point(goal)
			_push_trail()
			for i in range(1, crew.size()):
				var tp := _trail[maxi(0, _trail.size() - 1 - TRAIL_GAP * i)]
				crew[i].global_position = tp
			await get_tree().physics_frame
	_staging = false


## The doorway between a room and a hall (by tag), or {}.
func doorway(room: String, hall: String) -> Dictionary:
	for dw in fog.doorways:
		if dw["room"] == room and dw["hall"] == hall:
			return dw
	return {}


func door_of(dw: Dictionary) -> OfficeDoor:
	for d in doors:
		if not dw.is_empty() and d.doorway_id == int(dw["id"]):
			return d
	return null


## A walkable cell `dist` world units from a doorway's middle along its axis (+ into the hall, - into the room).
func cell_off(dw: Dictionary, dist: float, side: float = 0.0) -> Vector2i:
	var axis: Vector3 = dw["axis"]
	var p: Vector3 = (dw["mid"] as Vector3) + axis * dist + Vector3(-axis.z, 0.0, axis.x) * side
	var c := Hex.from_world(p)
	if map.is_walkable_cell(c):
		return c
	for r in [1, 2]:
		for n in Hex.ring(c, r):
			if map.is_walkable_cell(n):
				return n
	return c


func _shots() -> void:
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var only := _arg(OS.get_cmdline_user_args(), "--only")
	for i in 10:
		await get_tree().process_frame
	if only == "" or only == "overview":
		fog_view.enabled = false
		await _overview("overview_plain")
		fog_view.enabled = true
	var dw_show := doorway("room:7", "hall:3")
	if dw_show.is_empty() or not bool(dw_show["door_ok"]):
		for dw in fog.doorways:
			if bool(dw["door_ok"]):
				dw_show = dw
				break
	# 1. The door variants side by side (single | double | slider), shut, opening, open, smashed, from the room side, at
	#    the doorway that faces the camera best (a door seen edge-on shows only its frame's top).
	if only == "variants":   # (run it on a floor whose doorways face the camera: --seed 2)
		await _door_variants(_facing_doorway(false))
		finish_shots()
		return
	if only == "bend":
		await _bend_shot(_facing_doorway(true))
		finish_shots()
		return
		_spawn_doors()
		fog.seen.fill(0)
		_place_crew_at(Hex.to_world(map.cells_with_tag("start")[0]))
		await _settle()
	# 2. A wide hall's open archway: from hall:4 the room past it (room:5) is in view, contents and all.
	var dw_a := doorway("room:0", "hall:4")
	var dw_b := doorway("room:5", "hall:4")
	if dw_a.is_empty() or dw_b.is_empty() or seed_value != 7:
		finish_shots()   # (the staged walk below is seed 7's floor)
		return
	await walk_to(cell_off(dw_a, 2.5))
	await walk_to(cell_off(dw_b, 3.2))
	await _settle()
	if only == "" or only == "archway":
		await _all_looks("archway")
	# 3. The four states at once: into room:5, a step into hall:6 and back. In view: room:5, hall:6 (an archway). Seen:
	#    room:0, hall:4. Next: room:7 (past hall:6), hall:5 and what is past it, hall:0 / room:1. Unknown: the rest.
	var dw_c := doorway("room:5", "hall:6")
	await walk_to(cell_off(dw_b, -3.0))
	await walk_to(cell_off(dw_c, 2.0))
	await walk_to(cell_off(dw_c, -3.6, -1.0))
	await _settle()
	if only == "" or only == "looks" or only == "measure":
		await _measure()
	if only == "" or only == "looks":
		await _all_looks("looks")
		fog_view.enabled = false
		await _snap("looks_fog_off")
		fog_view.enabled = true
	# 4. A shut door versus an open one: the crew goes on to room:7 and through its door onto the narrow hall:3 (the door
	#    opens as Wick walks into it, a noise), turns round: room:7 behind the open door is in view; E shuts it.
	var door := door_of(dw_show)
	if door == null:
		door = door_at(int(dw_show["id"]), door_style)
	var dw_7 := doorway("room:7", "hall:6")
	if not dw_7.is_empty():
		await walk_to(cell_off(dw_7, -3.0))
	await walk_to(cell_off(dw_show, -2.6))
	await walk_to(cell_off(dw_show, 3.4))
	_crew_behind(dw_show["axis"])
	await _settle()
	if only == "" or only == "door":
		await _all_looks("door_open")
		door.use(wick)
		await _until(func() -> bool: return false, 40)
		await _settle()
		await _all_looks("door_shut")
	# 5. A brute comes up hall:3 for Wick, who waits in room:7 behind the shut door: wind-up, then the burst.
	if only == "" or only == "brute":
		if door.shut:
			door.use(wick)
		await walk_to(cell_off(dw_show, -3.2, 1.2))
		_crew_behind(-(dw_show["axis"] as Vector3))
		door.request(true, wick)
		await _until(func() -> bool: return false, 40)
		await _settle()
		brute = MonsterFactory.spawn("brute", cell_off(dw_show, 8.0))
		await get_tree().physics_frame
		brute.aggro(wick)
		await _until(func() -> bool: return float(brute.get("_telegraph")) > 0.3, 60 * 12)
		await _snap("brute_windup_fog")             # what Wick sees: the door shuddering, nothing behind it
		fog_view.enabled = false
		await _snap("brute_windup_fog_off")         # what is behind it
		fog_view.enabled = true
		await _until(func() -> bool: return door.broken, 60 * 4)
		await _until(func() -> bool: return false, 8)
		fog_view.refresh_now(true)
		await _snap("brute_smash")                  # the burst: the hall comes into view, the brute mid-swing, hex rubble
	finish_shots()


## The narrow doorway whose door faces the camera best from its room side (`bend`: the longest chord among those facing it
## well: a doorway at a bend in the room wall).
func _facing_doorway(bend: bool) -> Dictionary:
	var cam := Vector2(1, 1).normalized()   # (CameraRig.YAW_DEG 45: the camera sits toward +X +Z)
	var best := {}
	var best_s := -INF
	for dw in fog.doorways:
		if not bool(dw["door_ok"]):
			continue
		var t := ((dw["b"] as Vector2) - (dw["a"] as Vector2)).normalized()
		var n := Vector2(-t.y, t.x)
		if n.dot(Vector2((dw["axis"] as Vector3).x, (dw["axis"] as Vector3).z)) > 0.0:
			n = -n   # (into the room)
		var score := n.dot(cam)
		if bend:
			score = (dw["a"] as Vector2).distance_to(dw["b"]) if score > 0.5 else -INF
		if score > best_s:
			best_s = score
			best = dw
	print("fog lab: showcase doorway %s (%s|%s), chord %.2f" % [best.get("id"), best.get("room"), best.get("hall"),
		(best["a"] as Vector2).distance_to(best["b"]) if not best.is_empty() else 0.0])
	return best


## A door across a bend in the room wall (the chord between the jambs cuts across the corner): shut and open, close and at
## the game camera, fog look A.
func _bend_shot(dw: Dictionary) -> void:
	await walk_to(cell_off(dw, -3.4, 0.0))
	_crew_behind(-(dw["axis"] as Vector3))
	var d := door_at(int(dw["id"]), door_style)
	await _settle()
	rig.target = d
	for st in ["shut", "open"]:
		if st == "open":
			d.request(false, wick)
			await _until(func() -> bool: return false, 30)
		for view in ["game", "close"]:
			var size := CameraRig.SIZE_DEFAULT if view == "game" else 9.0
			rig.camera.size = size
			rig._zoom_target = size
			rig.snap()
			await _snap("doors_v3_bend_%s_%s" % [st, view])


## The three door looks at one doorway, four states each; one strip per state, column | edge | iris, at the game camera
## (doors_v3_<state>.png) and close up (doors_v3_close_<state>.png). The crew stands back in the room.
func _door_variants(dw: Dictionary) -> void:
	await walk_to(cell_off(dw, -3.4, 0.0))
	_staging = true                               # (the followers stand where they are put)
	var axis: Vector3 = dw["axis"]
	crew[1].global_position = wick.global_position - axis * 1.6 + Vector3(-axis.z, 0.0, axis.x) * 1.3
	crew[2].global_position = wick.global_position - axis * 1.6 - Vector3(-axis.z, 0.0, axis.x) * 1.3
	for h in crew:
		h.global_position.y = map.ground_height(h.global_position)
		h.face_point(dw["center"])
	await _settle()
	caption.visible = false
	if _arg(OS.get_cmdline_user_args(), "--nofog") != "":
		fog_view.enabled = false
	var states := ["shut", "opening", "open", "smashed"]
	var shots := {}
	for st in states:
		shots["game_" + st] = []
		shots["close_" + st] = []
	var tag := Label.new()
	tag.add_theme_font_size_override("font_size", 26)
	tag.add_theme_color_override("font_color", Color(0.96, 0.94, 0.88))
	tag.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.04))
	tag.add_theme_constant_override("outline_size", 7)
	caption.get_parent().add_child(tag)
	var styles := OfficeDoorModel.STYLES
	for style in styles:
		for n in GameWorld.root.get_children():
			if n is PropDebris:
				n.queue_free()   # (the last style's splinters)
		var d := door_at(int(dw["id"]), style)
		await _settle()
		for st in states:
			match st:
				"shut":
					d.hold_k = -1.0
				"opening":
					d.request(false, null)
					d.hold_k = 0.5
				"open":
					d.hold_k = -1.0
					await _until(func() -> bool: return false, 30)
				"smashed":
					d.smash(null)
					await _until(func() -> bool: return false, 24)
			for view in ["game", "close"]:
				rig.target = d
				var size := CameraRig.SIZE_DEFAULT if view == "game" else 9.0
				rig.camera.size = size
				rig._zoom_target = size
				rig.snap()
				await _until(func() -> bool: return false, 2)
				var vs := get_viewport().get_visible_rect().size
				var sp := rig.camera.unproject_position(d.center() + Vector3.UP * CameraRig.FOCUS_HEIGHT)
				if st == "shut" and view == "game":
					tag.visible = false
					var whole := await _grab()
					whole.save_png(shot_dir.path_join("doors_v3_floor_%s.png" % style))   # (the whole frame: on a real floor, fog look A)
					tag.visible = true
				var img := await _grab()
				var k := float(img.get_width()) / vs.x      # (the window's content scale: the image is in its pixels)
				var x0 := clampi(int(sp.x * k) - 320, 0, img.get_width() - 640)
				var y0 := clampi(int(sp.y * k) - 420, 0, img.get_height() - 760)
				tag.position = Vector2(x0 + 18, y0 + 12) / k
				tag.text = "%s: %s" % [style, st]
				img = await _grab()
				(shots[view + "_" + st] as Array).append(img.get_region(Rect2i(x0, y0, 640, 760)))
	rig.target = wick
	rig.camera.size = CameraRig.SIZE_DEFAULT
	rig._zoom_target = CameraRig.SIZE_DEFAULT
	rig.snap()
	tag.queue_free()
	caption.visible = true
	fog_view.enabled = true
	_staging = false
	for key: String in shots:
		var strip := Image.create(640 * styles.size(), 760, false, Image.FORMAT_RGBA8)
		for i in styles.size():
			var part: Image = shots[key][i]
			part.convert(Image.FORMAT_RGBA8)
			strip.blit_rect(part, Rect2i(0, 0, 640, 760), Vector2i(640 * i, 0))
		var file := "doors_v3_%s.png" % key.trim_prefix("game_") if key.begins_with("game_") else "doors_v3_%s.png" % key
		var out := shot_dir.path_join(file)
		print("shot ", out, " ", strip.save_png(out))

func _grab() -> Image:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

## The pass's cost here: GPU frame time (RenderingServer's measure) over 120 frames, fog off and each look; the CPU side
## is FogView.stats.
func _measure() -> void:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var rows: Array[String] = []
	for mode in [-1, FogView.LOOK_VOID, FogView.LOOK_BLUEPRINT, FogView.LOOK_SMOKE]:
		fog_view.enabled = mode >= 0
		if mode >= 0:
			fog_view.look = mode
		for i in 30:
			await get_tree().process_frame
		var gpu := 0.0
		var cpu := 0.0
		for i in 120:
			await get_tree().process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		rows.append("%s: gpu %.3f ms, render cpu %.3f ms" % ["fog off" if mode < 0 else FogView.LOOK_NAMES[mode], gpu / 120.0, cpu / 120.0])
	fog_view.enabled = true
	fog_view.look = FogView.LOOK_VOID
	print("fog cost: " + "; ".join(rows) + "; FogView cpu: update %.0f us, upload %.0f us, contents %.0f us" % [
		float(fog_view.stats["update_us"]), float(fog_view.stats["upload_us"]), float(fog_view.stats["contents_us"])])


func _all_looks(base: String) -> void:
	for lk in [FogView.LOOK_VOID, FogView.LOOK_BLUEPRINT, FogView.LOOK_SMOKE]:
		fog_view.look = lk
		await _snap("%s_%s" % [base, ["a", "b", "c"][lk]])
	fog_view.look = FogView.LOOK_VOID


## Stand the other two behind Wick (further along `dir`), out of the doorway, and keep them there (_staging).
func _crew_behind(dir: Vector3) -> void:
	_staging = true
	var side := Vector3(-dir.z, 0.0, dir.x)
	for i in [1, 2]:
		var p := wick.global_position + dir * 1.4 + side * (1.1 if i == 1 else -1.1)
		if map.blocks_point(p, 0.4) or is_nan(map.ground_height(p)):
			p = wick.global_position + dir * (1.2 + 1.0 * i)
		p.y = map.ground_height(p)
		crew[i].global_position = p


## Let the fog catch up and every fade finish.
func _settle() -> void:
	fog_view.refresh_now(true)
	rig.snap()
	for i in 3:
		await get_tree().physics_frame


func _until(cond: Callable, max_frames: int) -> void:
	for i in max_frames:
		if cond.call():
			return
		await get_tree().physics_frame


func _overview(file: String) -> void:
	_toggle_labels()
	var cam := rig.camera
	var keep := cam.size
	var mid := Vector3.ZERO
	var n := 0
	for c: Vector2i in map.cells:
		mid += Hex.to_world(c)
		n += 1
	mid /= float(n)
	rig.target = null
	rig.global_position = mid
	cam.size = 110.0
	rig._zoom_target = 110.0
	await _snap(file)
	cam.size = keep
	rig._zoom_target = keep
	rig.target = wick
	rig.snap()
	_toggle_labels()


func _snap(file: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := shot_dir.path_join(file + ".png")
	print("shot ", out, " ", img.save_png(out))


func finish_shots() -> void:
	get_tree().quit()
