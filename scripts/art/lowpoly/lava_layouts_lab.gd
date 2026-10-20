extends "res://scripts/art/lowpoly/lava_lab.gd"
## Lava cave LAYOUTS lab (docs/design/lava-playtest.md): the prototype's hand-authored caves (LavaCave, the same maps the
## dev flag --lava-cave builds) in the game's look (LavaLook), with the fight marked on them for the plan diagrams. Look-dev
## only: the monsters here are models, nothing declares gameplay state.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/lava_layouts_lab.tscn --case layout --layout <1-5> --shot <png>
##
## Views: plan (top down, the whole cave: the fog spaces and their doorways in cyan, the entry and exit, the archers'
## isles, the melee pack, cover, where a shove into the lava tempts, and where a damp crust opens a shortcut), game (the
## game camera, size 24, nothing marked), marked (the game camera with the marks).

var _marks: Array[Node3D] = []


func _case_layout() -> void:
	var id := int(_arg(OS.get_cmdline_user_args(), "--layout", "1"))
	var L := LavaCave.layout(id)
	map = LavaCave.build_map(id)
	if OS.get_cmdline_user_args().has("--no-rim"):
		# (the plan diagram: without the rim's dark columns, which read like rock from above)
		for c: Vector2i in map.cells.keys():
			if map.cells[c].tag == "rim":
				map.cells.erase(c)
	for c in LavaCave.lava_cells(map):
		lava[c] = true
	GameWorld.begin(map, self, 1)
	terrain = HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)
	LavaLook.dress(self, map, terrain)
	var letters := "ABCDEFG"
	for i in (L["chambers"] as Array).size():
		var ch: Array = L["chambers"][i]
		spaces_named[str(ch[0])] = "%s (chamber)" % letters[i]
	_draw_spaces()
	for n in _labels:
		_marks.append(n)
	# the crew at the entry, the monsters (models) where the prototype spawns them
	var start: Vector2i = L["start"]
	_hero("gasket", _top(start), Hex.dir_vector(1))
	_hero("wick", _top(start + Hex.DIRS[3]), Hex.dir_vector(1))
	_hero("rebar", _top(start + Hex.DIRS[4]), Hex.dir_vector(1))
	for c: Vector2i in L["archers"]:
		_monster("archer", c)
	for e: Array in L["melee"]:
		_monster(str(e[0]), e[1])
	# the marks
	_mark_text(_top(start) + Vector3(0, 2.4, 0), "ENTRY", Color(0.4, 1.0, 0.8), 64)
	_mark_text(_top(L["exit"]) + Vector3(0, 2.4, 0), "EXIT", Color(1.0, 0.5, 1.0), 64)
	_mark_ring(_top(L["exit"]), 0.8, Color(1.0, 0.5, 1.0))
	var isle_done := {}
	for c: Vector2i in L["archers"]:
		for isle: Array in L["isles"]:
			if Hex.distance(c, isle[1]) <= int(isle[2]) and not isle_done.has(isle[1]):
				isle_done[isle[1]] = true
				_mark_ring(_top(isle[1]), 2.0, Color(1.0, 0.2, 0.15))
				_mark_text(_top(isle[1]) + Vector3(0, 3.4, 0), "ARCHERS\n(no path)", Color(1.0, 0.35, 0.3), 54)
	var pack := Vector3.ZERO
	for e: Array in L["melee"]:
		pack += _top(e[1])
	pack /= float((L["melee"] as Array).size())
	_mark_text(pack + Vector3(0, 3.0, 0), "MELEE PACK", Color(1.0, 0.65, 0.2), 54)
	for c: Vector2i in L["cover"]:
		_mark_text(_top(c) + Vector3(0, 1.6, 0), "cover", Color(0.55, 0.75, 1.0), 44)
	for c: Vector2i in L["shove"]:
		_mark_ring(_top(c), 1.0, Color(1.0, 0.3, 0.1))
		_mark_text(_top(c) + Vector3(0, 1.4, 0), "SHOVE!", Color(1.0, 0.45, 0.2), 46)
	for dm: Array in L["damp"]:
		var a := _top(dm[0]) + Vector3(0, 0.15, 0)
		var b := Hex.to_world(dm[1]) + Vector3(0, (float(map.cells[dm[1]].level) * LH) if map.has_cell(dm[1]) and not lava.has(dm[1]) else LavaCave.LAVA_Y, 0) + Vector3(0, 0.15, 0)
		_mark_line(a, b, Color(0.3, 0.85, 1.0))
		_mark_text((a + b) * 0.5 + Vector3(0, 1.2, 0), "DAMP", Color(0.4, 0.9, 1.0), 46)
	for b: Dictionary in L["bridges"]:
		if int(b["w"]) < 2:
			var rows := LavaCave.bridge_rows(b)
			var mid: Vector2i = rows[rows.size() / 2][0]
			_mark_text(_top(mid) + Vector3(0, 1.6, 0), "1-wide (risky)", Color(1.0, 0.9, 0.5), 44)
	# the views
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c: Vector2i in map.cells:
		if map.cells[c].tag == "rim":
			continue
		var w := Hex.to_world(c)
		lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
		hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
	var centre := Vector3((lo.x + hi.x) * 0.5, 0, (lo.y + hi.y) * 0.5)
	var span := maxf((hi.y - lo.y) + 4.0, ((hi.x - lo.x) + 4.0) * 9.0 / 16.0)
	var self_ref := self
	var marks_on := func() -> void: self_ref._show_marks(true)
	var marks_off := func() -> void: self_ref._show_marks(false)
	_view("plan", span, centre, 0.0, -89.5, marks_on)
	_view("game", GAME_SIZE, centre + Vector3(0, 0, 1.0), GAME_YAW, GAME_PITCH, marks_off)
	_view("marked", GAME_SIZE, centre + Vector3(0, 0, 1.0), GAME_YAW, GAME_PITCH, marks_on)
	var r := LavaCave.check(id)
	print("layout %d %s: %s" % [id, L["name"], "ok" if r["ok"] else str(r["problems"])])


func _monster(kind: String, c: Vector2i) -> void:
	var m := MonsterModels.make(kind)
	add_child(m)
	m.position = _top(c)
	m.rotation_degrees.y = 225.0


func _show_marks(on: bool) -> void:
	for n in _marks:
		if is_instance_valid(n):
			n.visible = on


func _mark_text(pos: Vector3, text: String, col: Color, size: int) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = size
	lbl.outline_size = 16
	lbl.pixel_size = 0.014
	lbl.modulate = col
	lbl.render_priority = 12
	lbl.outline_render_priority = 11
	add_child(lbl)
	lbl.position = pos
	_marks.append(lbl)


func _mark_ring(pos: Vector3, radius: float, col: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius
	tm.outer_radius = radius + 0.14
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true
	m.render_priority = 10
	ring.material_override = m
	add_child(ring)
	ring.position = pos + Vector3(0, 0.12, 0)
	ring.scale = Vector3(1, 0.2, 1)
	_marks.append(ring)


## A dashed line from a to b (world points).
func _mark_line(a: Vector3, b: Vector3, col: Color) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true
	m.render_priority = 10
	var n := maxi(2, int(a.distance_to(b) / 0.5))
	for i in n:
		if i % 2 == 1:
			continue
		var p0 := a.lerp(b, float(i) / float(n))
		var p1 := a.lerp(b, float(i + 1) / float(n))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.14, 0.05, p0.distance_to(p1))
		mi.mesh = bm
		mi.material_override = m
		add_child(mi)
		mi.look_at_from_position((p0 + p1) * 0.5, p1, Vector3.UP)
		_marks.append(mi)
