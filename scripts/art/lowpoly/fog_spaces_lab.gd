extends LabBase
## Fog SPACES lab (docs/design/fog-spaces-audit.md): top-down maps of how RoomFog / Doorways cut a floor into fog spaces.
## Look-dev only (no gameplay state). One run renders a list of maps:
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/fog_spaces_lab.tscn --maps s3f1,s7f2,c1 --out <dir> [--whole]
##
## sSfF: contract seed S (ContractBoard.run_for_seed), floor F (DungeonGen.for_run); cN: lava cave N (LavaCave).
## Long halls are cut into segments as in the game (RoomFog.split_long_halls); --whole: as before 2026-10-20, every hall
## one space (files get "_whole").
##
## IN THE GAME (--game-shot): the real game (game.tscn, its game flags as given), then the crew walked partway down the
## floor's longest cut hall, screenshots into --out: game_walk.png (the game camera on the player), game_ahead.png (the
## crew and the silhouette ahead in one frame), game_cut.png (close up on the first boundary ahead between two segments
## that show differently). With --whole the same spots, halls whole
## ("_whole"). The walk stops at --walk-share of the hall (default 0.45).
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/fog_spaces_lab.tscn --game-shot --out <dir>
##       --seed 3 --floor 1 --spells heal,corn --no-mic --no-van-intro [--whole]
## Each cell is a flat hex in its space's colour (rooms saturated, halls pale, lighter for higher floor; walls dark; a
## lava cave's lava darker, its rim grey), white lines between spaces, thin dark lines where the floor steps inside a
## space, a white dot on a cell the generator left untagged (it took the nearest space), a yellow ring on each doorway
## (cyan: a doorway between two segments of a cut hall), the space names, and a title.

var _holder: Node3D


func _ready() -> void:
	var maps := arg(args, "--maps", "s3f1").split(",")
	var out := arg(args, "--out", "user://")
	RoomFog.split_long_halls = not args.has("--whole")
	if args.has("--game-shot"):
		var d := GameShot.new()
		d.name = "FogGameShot"
		d.out = out
		d.whole = args.has("--whole")
		d.share = float(arg(args, "--walk-share", "0.45"))
		get_tree().root.add_child.call_deferred(d)
		get_tree().change_scene_to_file.call_deferred("res://scenes/game.tscn")
		return
	make_camera(400.0)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.06, 0.06, 0.07)
	add_child(env)
	_render_all(maps, out, not args.has("--whole"))


func _render_all(maps: PackedStringArray, out: String, split: bool) -> void:
	for spec in maps:
		var m: HexMap
		var title := ""
		var skip := {}
		if spec.begins_with("c"):
			var id := int(spec.substr(1))
			m = LavaCave.build_map(id)
			title = "lava cave %d (%s)" % [id, LavaCave.layout(id)["name"]]
			for il: Array in LavaCave.layout(id)["isles"]:
				for c in Hex.range_cells(il[1], int(il[2])):
					skip[c] = true
		else:
			var parts := spec.substr(1).split("f")
			var run := ContractBoard.run_for_seed(int(parts[0]))
			m = DungeonGen.for_run(run, int(parts[1]))
			title = "seed %s floor %s" % [parts[0], parts[1]]
		var fog := RoomFog.build(m)
		title += "  |  %d spaces, %d doorways%s" % [fog.space_count(), fog.doorways.size(), "  |  long halls cut into segments" if split else "  |  halls whole"]
		if _holder != null:
			_holder.queue_free()
		_holder = Node3D.new()
		add_child(_holder)
		var bounds := _draw(m, fog, skip, title)
		var centre := bounds.get_center()
		camera.size = maxf(bounds.size.y + 6.0, (bounds.size.x + 6.0) * 9.0 / 16.0)
		camera.global_position = Vector3(centre.x, 100.0, centre.y)
		camera.rotation_degrees = Vector3(-90, 0, 0)
		await snap("%s/spaces_%s%s.png" % [out, spec, "" if split else "_whole"])
	finish()


static func space_color(s: int, hall: bool) -> Color:
	var h := fmod(float(s) * 0.61803398875, 1.0)
	return Color.from_hsv(h, 0.32 if hall else 0.62, 0.62 if hall else 0.85)


## Draw the map; returns its bounds (world X/Z).
func _draw(m: HexMap, fog: RoomFog, skip: Dictionary, title: String) -> Rect2:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c: Vector2i in m.cells:
		var cell: HexMap.Cell = m.cells[c]
		var w := Hex.to_world(c)
		var col := Color(0.16, 0.16, 0.18)
		var s := fog.space_of_cell(c)
		if cell.type != HexMap.Tile.WALL and s >= 0:
			col = space_color(s, fog.is_hall[s])
			if cell.tag == "lava" or cell.level == LavaCave.LAVA_BED:
				col = col.darkened(0.6)
			elif cell.tag == "rim":
				col = Color(0.3, 0.3, 0.32)
			else:
				col = col.lightened(clampf(float(cell.level) * 0.04, -0.3, 0.3))
			if skip.has(c):
				col = col.lerp(Color(1.0, 0.3, 0.3), 0.35)
		elif cell.type != HexMap.Tile.WALL:
			col = Color(0.5, 0.0, 0.5)
		lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
		hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
		for i in 6:
			st.set_color(col)
			st.add_vertex(w)
			st.set_color(col)
			st.add_vertex(w + Hex.corner((i + 1) % 6) * 0.98)
			st.set_color(col)
			st.add_vertex(w + Hex.corner(i) * 0.98)
		if cell.type != HexMap.Tile.WALL and cell.tag == "" and s >= 0:
			_dot(st, w + Vector3(0, 0.02, 0), 0.22, Color.WHITE)
		# edges: between spaces (white), floor steps inside a space (dark)
		for d in 3:
			var nb: Vector2i = c + Hex.DIRS[d]
			var nc: HexMap.Cell = m.cells.get(nb)
			if nc == null:
				continue
			var e0 := w + Hex.kite_corner(posmod(d - 1, 6))
			var e1 := w + Hex.kite_corner(d)
			var s2 := fog.space_of_cell(nb)
			if cell.type == HexMap.Tile.WALL or nc.type == HexMap.Tile.WALL or s < 0 or s2 < 0:
				continue
			if s != s2:
				_line(lines, e0, e1, 0.3, Color.WHITE)
			elif cell.level != nc.level and cell.level != LavaCave.LAVA_BED and nc.level != LavaCave.LAVA_BED:
				_line(lines, e0, e1, 0.14, Color(0.05, 0.05, 0.05))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	_holder.add_child(mi)
	var lmi := MeshInstance3D.new()
	lmi.mesh = lines.commit()
	lmi.material_override = mat
	lmi.position.y = 0.05
	_holder.add_child(lmi)
	# doorways
	for dw in fog.doorways:
		var mid: Vector3 = dw["mid"]
		var split: bool = dw.get("split", false)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.9
		tm.outer_radius = 1.3
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color(0.3, 0.95, 1.0) if split else Color(1.0, 0.9, 0.2)
		ring.material_override = rm
		_holder.add_child(ring)
		ring.position = Vector3(mid.x, 0.3, mid.z)
		ring.scale = Vector3(1, 0.1, 1)
		_label(Vector3(mid.x + 1.9, 0.5, mid.z), str(dw["id"]), rm.albedo_color, 34)
	# space names
	var sums := {}
	for c: Vector2i in fog.cell_space:
		var cell: HexMap.Cell = m.cells[c]
		if not m.is_walkable_cell(c) or cell.tag == "lava" or cell.tag == "rim" or cell.level == LavaCave.LAVA_BED:
			continue
		var s := fog.space_of_cell(c)
		if not sums.has(s):
			sums[s] = [Vector3.ZERO, 0]
		sums[s][0] += Hex.to_world(c)
		sums[s][1] = int(sums[s][1]) + 1
	for s: int in sums:
		var p: Vector3 = (sums[s][0] as Vector3) / float(sums[s][1])
		_label(p + Vector3(0, 0.6, 0), fog.tags[s], Color.WHITE, 44 if not fog.is_hall[s] else 34)
	_label(Vector3(lo.x, 0.6, lo.y - 2.0), title, Color(0.9, 0.9, 0.95), 56, false)
	return Rect2(lo, hi - lo).grow(2.0)


func _label(pos: Vector3, text: String, col: Color, size: int, centred: bool = true) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 12
	l.pixel_size = 0.045
	l.modulate = col
	l.rotation_degrees = Vector3(-90, 0, 0)
	l.no_depth_test = true
	if not centred:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_holder.add_child(l)
	l.position = pos


static func _line(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var t := (b - a).normalized()
	var n := Vector3(-t.z, 0, t.x) * w * 0.5
	for v: Vector3 in [a - n, b - n, b + n, a - n, b + n, a + n]:
		st.set_color(col)
		st.add_vertex(v)


static func _dot(st: SurfaceTool, at: Vector3, r: float, col: Color) -> void:
	for i in 6:
		st.set_color(col)
		st.add_vertex(at)
		st.set_color(col)
		st.add_vertex(at + Hex.corner((i + 1) % 6) * r)
		st.set_color(col)
		st.add_vertex(at + Hex.corner(i) * r)


## --game-shot: rides along with the real game (a node on the root, so it outlives the scene change), walks the crew down
## the floor's longest cut hall and takes the screenshots. Look-dev only: it moves the crew the way game.gd's own dev
## teleports do (_teleport_crew) and points the camera rig at a marker for the close-up.
class GameShot extends Node:
	var out := "user://"
	var whole := false
	var share := 0.45

	func _ready() -> void:
		var game: Node = null
		for i in 1200:
			await get_tree().process_frame
			game = get_tree().current_scene
			if game != null and game.get("fog_view") != null and game.get("map") != null and game.get("rig") != null:
				break
			game = null
		if game == null:
			push_error("fog game shot: the game never set up its fog")
			get_tree().quit(1)
			return
		await get_tree().create_timer(7.0).timeout   # (past the floor's dispatch banner)
		var map: HexMap = game.get("map")
		# the hall and the walk from the cut plan (built the same either way, so --whole stands on the same spots)
		var keep := RoomFog.split_long_halls
		RoomFog.split_long_halls = true
		var plan := RoomFog.build(map)
		RoomFog.split_long_halls = keep
		var longest := -1
		for s in plan.space_count():
			if plan.segmented[s] == 1 and (longest < 0 or plan.hall_segments(s).size() > plan.hall_segments(longest).size()):
				longest = s
		if longest < 0:
			push_error("fog game shot: no cut hall on this floor")
			get_tree().quit(1)
			return
		var segs := plan.hall_segments(longest)
		var corr: Array[Vector2i] = []
		for c: Vector2i in plan.cell_space:
			if segs.has(plan.space_of_cell(c)) and map.cells[c].tag == "corridor" and map.is_walkable_cell(c):
				corr.append(c)
		corr.sort()
		var e0 := RoomFog._walk_far(corr, corr[0])[0] as Vector2i
		var e1 := RoomFog._walk_far(corr, e0)[0] as Vector2i
		var path := _path(corr, e0, e1)
		var stop := clampi(int(float(path.size()) * share), 1, path.size() - 1)
		for i in range(0, stop + 1, 2):
			game.call("_teleport_crew", path[i])
			await get_tree().create_timer(0.12).timeout
		game.call("_teleport_crew", path[stop])
		await get_tree().create_timer(1.2).timeout
		var tag := "_whole" if whole else ""
		var rig: CameraRig = game.get("rig")
		await _shot("%s/game_walk%s.png" % [out, tag])
		# the cut plan walked the same way: the boundaries ahead of the crew where the state changes
		for i in range(0, stop + 1, 2):
			plan.update([_at(map, path[i])])
		plan.update([_at(map, path[stop])])
		var ahead: Array = []          # [path index, state before, state after]
		for i in range(stop, path.size() - 1):
			var a := plan.space_of_cell(path[i])
			var b := plan.space_of_cell(path[i + 1])
			if a != b and plan.state_of(a) != plan.state_of(b):
				ahead.append([i, plan.state_of(a), plan.state_of(b)])
		var marker := Marker3D.new()
		game.add_child(marker)
		# the crew and the silhouette ahead in one frame: the camera between them, zoomed out to fit
		var crew_at := _at(map, path[stop])
		var silhouette := crew_at
		for e: Array in ahead:
			if int(e[2]) == RoomFog.NEXT:
				silhouette = (_at(map, path[int(e[0])]) + _at(map, path[int(e[0]) + 1])) * 0.5
				break
		marker.global_position = crew_at.lerp(silhouette, 0.5)
		rig.target = marker
		var fit := clampf(crew_at.distance_to(silhouette) * 0.9 + 10.0, 24.0, 36.0)
		rig.set("_zoom_target", fit)
		rig.camera.size = fit
		rig.snap()
		await get_tree().create_timer(0.6).timeout
		await _shot("%s/game_ahead%s.png" % [out, tag])
		# close up on the first boundary ahead with no monster standing on it
		var target := Vector3.INF
		for e: Array in ahead:
			var p := (_at(map, path[int(e[0])]) + _at(map, path[int(e[0]) + 1])) * 0.5
			var clear := true
			for mn in get_tree().get_nodes_in_group("monsters"):
				if mn is Node3D and Vector2((mn as Node3D).global_position.x - p.x, (mn as Node3D).global_position.z - p.z).length() < 3.0:
					clear = false
			if clear:
				target = p
				break
		if target != Vector3.INF:
			marker.global_position = target
			rig.set("_zoom_target", 14.0)
			rig.camera.size = 14.0
			rig.snap()
			await get_tree().create_timer(0.8).timeout
			await _shot("%s/game_cut%s.png" % [out, tag])
		print("fog game shot: %s, %d segments, crew at %s (step %d of %d), silhouette at %s, cut close-up at %s, boundaries ahead %s" % [
				plan.tags[longest], segs.size(), path[stop], stop, path.size() - 1, silhouette, target, ahead])
		get_tree().quit()

	static func _at(map: HexMap, c: Vector2i) -> Vector3:
		return Hex.to_world(c, float(map.cells[c].level))

	func _shot(path: String) -> void:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		print("shot ", path, " ", img.save_png(path))

	static func _path(cells: Array[Vector2i], a: Vector2i, b: Vector2i) -> Array[Vector2i]:
		var inside := {}
		for c in cells:
			inside[c] = true
		var parent := {a: a}
		var queue: Array[Vector2i] = [a]
		var i := 0
		while i < queue.size():
			var cur := queue[i]
			i += 1
			for d in Hex.DIRS:
				var n: Vector2i = cur + d
				if inside.has(n) and not parent.has(n):
					parent[n] = cur
					queue.append(n)
		var out_path: Array[Vector2i] = [b]
		while out_path[0] != a:
			out_path.push_front(parent[out_path[0]])
		return out_path