extends LabBase
## Goblin scout look-dev lab (docs/design/goblin-scout.md): the real terrain look (HexMapView + DungeonLook) on a
## hand-built bit of bunker: room A, a three-wide corridor, room B with a pack in it, and a lineup room. The scout
## (GoblinModel), his fireworks (FireworksFx), the crew (Wick, Gasket, Rebar) and the live monsters for scale.
## Scene: scenes/goblin_lab.tscn.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/goblin_lab.tscn --shot <dir>/goblin.png
##
## --shot <png>  renders every view and quits (game = the real game camera, yaw 45, pitch -56, size 24):
##                 <base>_patrol_game / _patrol_close      patrolling the corridor, the crew sneaking up behind
##                 <base>_alert_game / _alert_close        the "!" moment, Wick in view
##                 <base>_light_close                      lighting the fuse (the window to stop him)
##                 <base>_fuse_close                       fleeing toward the pack with the fuse lit
##                 <base>_fireworks_game / _close          the volley over room B, the pack turning to it
##                 <base>_lineup / _lineup_game            next to the crew and the four live monsters
##                 <base>_turn_<front|side|back|three_quarter> and <base>_turnaround (strip)
##                 <base>_pose_<name> and <base>_poses (sheet)
##               and a contact sheet of the main views at <png>.
## --view <name> only that view, written to <png>.
## No --shot: an orbiting look at the lineup room with the scout cycling his poses.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0

const ROOM_A := Vector2i(0, 0)
const ROOM_B := Vector2i(20, 0)
const ROOM_C := Vector2i(-12, 26)        ## the lineup room (not connected; nobody walks there)
const RADIUS_AB := 6
const RADIUS_C := 9
const WALL_HEIGHT := 3                   ## levels, as DungeonGen's default wall_height

const MAIN_VIEWS: Array[String] = ["patrol_game", "patrol_close", "alert_game", "alert_close", "light_close", "fuse_close",
		"fireworks_game", "fireworks_close", "lineup", "lineup_game"]
const TURN_VIEWS := {"front": 180.0, "three_quarter": 142.0, "side": 90.0, "back": 0.0}
const POSES: Array[String] = ["patrol", "look", "alert", "light", "fuse_run", "throw", "cower", "rest"]

var goblin: GoblinModel
var wick: WickModel
var gasket: GasketModel
var rebar: RebarModel
var pack := {}                          ## name -> MonsterModel (grunt, archer, brute, swarmer, swarmer2, swarmer3)
var marks: Array[MeshInstance3D] = []
var fireworks: FireworksFx
var cone: MeshInstance3D
var _t := 0.0


func _ready() -> void:
	_build_world()
	goblin = GoblinModel.new()
	wick = WickModel.new()
	gasket = GasketModel.new()
	rebar = RebarModel.new()
	for n: Node3D in [goblin, wick, gasket, rebar]:
		add_child(n)
	for k: String in ["grunt", "archer", "brute", "swarmer", "swarmer2", "swarmer3"]:
		var m := MonsterModels.make(k.trim_suffix("2").trim_suffix("3"))
		pack[k] = m
		add_child(m)
		var mk := GoblinModel.make_alert_mark()
		mk.visible = false
		add_child(mk)
		marks.append(mk)
	fireworks = FireworksFx.new()
	fireworks.frozen = true
	fireworks.fx_seed = 11
	fireworks.drift = Vector3(1.0, 0.0, 0.25).normalized() * 2.0
	fireworks.visible = false
	add_child(fireworks)
	cone = _vision_cone()
	cone.visible = false
	add_child(cone)
	make_camera(300.0)
	for m in _models():
		m.idle_enabled = false
		m.apply_idle(0.6)
	if shot_path != "":
		_run_shots()
	else:
		_place("lineup")


# ------------------------------------------------------------------ the bit of bunker

func _build_world() -> void:
	map = HexMap.new()
	var floor_cells := {}
	for c in Hex.range_cells(ROOM_A, RADIUS_AB):
		floor_cells[c] = "room:0"
	for c in Hex.range_cells(ROOM_B, RADIUS_AB):
		floor_cells[c] = "room:1"
	for c in Hex.range_cells(ROOM_C, RADIUS_C):
		floor_cells[c] = "room:2"
	var xa := Hex.to_world(ROOM_A).x
	var xb := Hex.to_world(ROOM_B).x
	for q in range(0, 21):
		for r in range(-2, 2):
			var c := Vector2i(q, r)
			var x := Hex.to_world(c).x
			if x > xa and x < xb and not floor_cells.has(c):
				floor_cells[c] = "corridor"
	for c: Vector2i in floor_cells:
		var level := 0
		if Hex.distance(c, ROOM_B + Vector2i(2, -4)) <= 1:
			level = 2      # a little platform in room B (the archer's perch)
		map.set_cell(c, level).tag = floor_cells[c]
	# walls as DungeonGen builds them: one ring, WALL_HEIGHT levels above the highest floor next to it
	var wall_level := {}
	for c: Vector2i in floor_cells.keys():
		for d in Hex.DIRS:
			var n: Vector2i = c + d
			if not floor_cells.has(n):
				wall_level[n] = maxi(int(wall_level.get(n, -99)), map.get_cell(c).level)
	for n: Vector2i in wall_level:
		map.set_cell(n, int(wall_level[n]) + WALL_HEIGHT, HexMap.Tile.WALL)
	map.cut_walls()
	GameWorld.begin(map, self, 1)
	var terrain := HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)


## A faint floor overlay (design illustration, not a game visual): the scout's forward sight (9 units, 110
## degrees) and his all-round hearing ring (2.5), each ray stopped by the walls.
func _vision_cone() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.material_override = Fx.glow_material(Color(1.0, 0.78, 0.25, 0.13))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _vision_mesh(from: Vector3, facing: Vector3) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var yaw := atan2(facing.x, -facing.z)
	var half := deg_to_rad(55.0)
	var fan: Array[Vector3] = []
	for i in 45:
		var a := yaw - half + 2.0 * half * float(i) / 44.0
		fan.append(_ray(from, Vector3(sin(a), 0, -cos(a)), 9.0))
	for i in fan.size() - 1:
		st.add_vertex(Vector3(from.x, 0, from.z))
		st.add_vertex(fan[i])
		st.add_vertex(fan[i + 1])
	var ring: Array[Vector3] = []
	for i in 41:
		var a := TAU * float(i) / 40.0
		ring.append(_ray(from, Vector3(sin(a), 0, -cos(a)), 2.5))
	for i in ring.size() - 1:
		st.add_vertex(Vector3(from.x, 0, from.z))
		st.add_vertex(ring[i])
		st.add_vertex(ring[i + 1])
	return st.commit()


## March from `from` along `dir` until a wall (or the edge of the floor) or `reach`.
func _ray(from: Vector3, dir: Vector3, reach: float) -> Vector3:
	var p := Vector3(from.x, 0.0, from.z)
	var d := 0.0
	while d < reach:
		var q := p + dir * (d + 0.1)
		var c := map.get_cell(Hex.from_world(q))
		if c == null or c.type == HexMap.Tile.WALL or map.wall_at(q):
			break
		d += 0.1
	return p + dir * d


# ------------------------------------------------------------------ placement helpers

func _models() -> Array[LowPolyModel]:
	var out: Array[LowPolyModel] = [goblin, wick, gasket, rebar]
	for k in pack:
		out.append(pack[k])
	return out


func _heroes() -> Array[LowPolyModel]:
	var out: Array[LowPolyModel] = [wick, gasket, rebar]
	return out


func _park_all() -> void:
	var i := 0
	for m in _models():
		m.global_position = Vector3(200.0 + 4.0 * float(i), 0.0, 200.0)
		i += 1
	for mk in marks:
		mk.visible = false
	fireworks.visible = false
	cone.visible = false


## World point of a cell plus an offset (y from the floor level).
func _cell(q: int, r: int, off: Vector3 = Vector3.ZERO) -> Vector3:
	var c := Vector2i(q, r)
	var lvl := map.get_cell(c).level if map.has_cell(c) else 0
	return Hex.to_world(c, lvl) + off


func _put(m: Node3D, pos: Vector3, face: Vector3) -> void:
	m.global_position = pos
	var d := Vector3(face.x, 0.0, face.z)
	if d.length() > 0.001:
		d = d.normalized()
		m.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)


func _face_point(m: Node3D, pos: Vector3, look_at_pos: Vector3) -> void:
	_put(m, pos, look_at_pos - pos)


func _aim(yaw_deg: float, pitch_deg: float, size: float, tgt: Vector3) -> void:
	aim(yaw_deg, pitch_deg, size, tgt, 80.0)


func _rest_all() -> void:
	goblin.pose_scout("rest")
	for h in _heroes():
		if h.has_method("pose_preview"):
			h.call("pose_preview", "rest")
		else:
			h.apply_idle(0.6)
	for k in pack:
		(pack[k] as MonsterModel).pose_preview("rest", 1.0)


# ------------------------------------------------------------------ the views

func _place(view: String) -> void:
	_park_all()
	_rest_all()
	var east := Vector3(1, 0, 0)
	var west := Vector3(-1, 0, 0)
	match view:
		"patrol_game", "patrol_close":
			# mid-corridor, ambling east toward room B; the crew slips out of room A behind him
			var g := _cell(10, 0, Vector3(0.0, 0.0, 0.35))
			_put(goblin, g, east)
			goblin.pose_scout("patrol")
			_put(wick, _cell(5, 0, Vector3(0.6, 0, 0.9)), east)
			_put(gasket, _cell(4, 0, Vector3(0.0, 0, -1.1)), east)
			_put(rebar, _cell(2, 1, Vector3(0.0, 0, 0.3)), east)
			for h in _heroes():
				h.apply_idle(0.35, 2.0)
			if view == "patrol_game":
				cone.mesh = _vision_mesh(g, east)
				cone.visible = true
				cone.global_position = Vector3(0, 0.05, 0)
				_aim(GAME_YAW, GAME_PITCH, GAME_SIZE, _cell(9, 0) + Vector3(2.0, 0, 0))
			else:
				_aim(GAME_YAW, GAME_PITCH, 9.0, g + Vector3(-2.2, 0.8, 0.0))
		"alert_game", "alert_close", "light_close":
			# he turned round at a look-around stop and saw Wick at the corridor mouth
			var g2 := _cell(10, 0, Vector3(0.0, 0.0, 0.35))
			_put(goblin, g2, west)
			if view == "light_close":
				goblin.pose_scout("light", 0.9)
			else:
				goblin.pose_scout("alert", 1.0)
			_face_point(wick, _cell(6, 0, Vector3(0.0, 0, 0.6)), g2)
			wick.pose_preview("shoot")
			_face_point(gasket, _cell(5, 0, Vector3(-0.6, 0, -1.2)), g2)
			_face_point(rebar, _cell(3, 1, Vector3(0.0, 0, 0.4)), g2)
			if view == "alert_game":
				_aim(GAME_YAW, GAME_PITCH, GAME_SIZE, _cell(8, 0) + Vector3(2.0, 0, 0))
			else:
				_aim(GAME_YAW, GAME_PITCH, 10.5, (g2 + _cell(6, 0)) * 0.5 + Vector3(0.0, 1.2, -0.5))
		"fuse_close":
			# fuse lit, legging it east toward room B, glancing back over his shoulder
			var g3 := _cell(13, 0, Vector3(0.0, 0.0, 0.2))
			_put(goblin, g3, east)
			goblin.pose_scout("fuse_run")
			_put(wick, _cell(8, 0, Vector3(0.0, 0, 0.6)), east)
			wick.pose_preview("shoot")
			_put(gasket, _cell(7, 0, Vector3(0.0, 0, -1.1)), east)
			gasket.apply_idle(0.4, 4.5)
			_aim(GAME_YAW, GAME_PITCH, 10.0, (g3 + _cell(9, 0)) * 0.5 + Vector3(0.6, 1.0, 0.0))
		"fireworks_game", "fireworks_close":
			_place_fireworks(view)
		"lineup", "lineup_game":
			_place_lineup(view)


func _place_fireworks(view: String) -> void:
	# the fuse ran out at room B's door: the volley goes up, the scout cowers, the pack turns toward the bang
	var g := _cell(14, 0, Vector3(-0.4, 0.0, 0.5))
	_put(goblin, g, Vector3(1, 0, 0.3))
	goblin.pose_scout("cower")
	fireworks.visible = true
	fireworks.global_position = goblin.launch_point()
	fireworks.sample(1.22)
	var bang := fireworks.global_position + Vector3(0.0, 5.0, 0.0)
	var spots := {
		"grunt": _cell(19, -3), "archer": _cell(22, -4), "brute": _cell(23, 1),
		"swarmer": _cell(18, 3), "swarmer2": _cell(19, 3, Vector3(0.5, 0, 0.5)), "swarmer3": _cell(17, 4, Vector3(0.3, 0, 0)),
	}
	var i := 0
	for k: String in spots:
		var m: MonsterModel = pack[k]
		var p: Vector3 = spots[k]
		_face_point(m, p, g)
		m.pose_preview("windup", 0.25)
		var mk := marks[i]
		mk.visible = true
		mk.global_position = p + Vector3(0.0, m.ui_height + 0.35, 0.0)
		mk.scale = Vector3.ONE * (0.8 if k.begins_with("swarmer") else 1.0)
		i += 1
	_face_point(wick, _cell(9, 0, Vector3(0, 0, 0.5)), bang)
	_face_point(gasket, _cell(8, 0, Vector3(0, 0, -1.0)), bang)
	_face_point(rebar, _cell(6, 1), bang)
	if view == "fireworks_game":
		_aim(GAME_YAW, GAME_PITCH, GAME_SIZE, _cell(17, 0) + Vector3(-1.0, 1.5, 0.0))
	else:
		_aim(GAME_YAW, GAME_PITCH, 17.0, _cell(18, 0) + Vector3(-0.5, 2.6, 0.5))


func _place_lineup(view: String) -> void:
	var centre := Hex.to_world(ROOM_C)
	var yaw_deg := 160.0 if view == "lineup" else GAME_YAW
	var yaw := deg_to_rad(yaw_deg)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var toward_cam := Vector3(sin(yaw), 0.0, cos(yaw))
	var row: Array = [[wick, -8.0], [gasket, -6.0], [rebar, -3.6], [goblin, -1.0], [pack["swarmer"], 1.0],
			[pack["grunt"], 2.8], [pack["archer"], 4.8], [pack["brute"], 7.3]]
	for e: Array in row:
		var m: Node3D = e[0]
		_put(m, centre + right * float(e[1]), toward_cam)
	if view == "lineup":
		_aim(yaw_deg, -20.0, 11.5, centre + right * -0.35 + Vector3(0, 1.3, 0))
	else:
		_aim(yaw_deg, GAME_PITCH, GAME_SIZE, centre + right * -0.35 + Vector3(0, 0.6, 0))


func _place_turn(view: String) -> void:
	_park_all()
	_rest_all()
	var centre := Hex.to_world(ROOM_C)
	_put(goblin, centre, Vector3(0, 0, -1))
	goblin.pose_scout("rest")
	var yaw: float = TURN_VIEWS[view]
	_aim(yaw, -10.0, 3.3, centre + Vector3(0, 1.2, 0))


func _place_pose(pose: String) -> void:
	_park_all()
	_rest_all()
	var centre := Hex.to_world(ROOM_C)
	_put(goblin, centre, Vector3(0, 0, -1))
	goblin.pose_scout(pose, 1.0 if pose != "light" else 0.9)
	_aim(142.0, -24.0, 3.5, centre + Vector3(0, 1.15, 0))


# ------------------------------------------------------------------ live (no --shot)

func _process(delta: float) -> void:
	if shot_path != "":
		return
	_t += delta
	var poses := POSES
	var idx := int(_t / 2.0) % poses.size()
	goblin.pose_scout(poses[idx])
	var centre := Hex.to_world(ROOM_C)
	_aim(160.0 + 30.0 * sin(_t * 0.3), -22.0, 11.5, centre + Vector3(0, 1.3, 0))


# ------------------------------------------------------------------ screenshots

func _run_shots() -> void:
	await wait_frames(20)
	var base := shot_path.get_basename()
	if only_view != "":
		if TURN_VIEWS.has(only_view):
			_place_turn(only_view)
		elif POSES.has(only_view):
			_place_pose(only_view)
		else:
			_place(only_view)
		await snap(shot_path)
		finish()
		return
	var sheet: Array[Image] = []
	for view in MAIN_VIEWS:
		_place(view)
		sheet.append(await snap("%s_%s.png" % [base, view]))
	var turns: Array[Image] = []
	for view: String in TURN_VIEWS:
		_place_turn(view)
		turns.append(await snap("%s_turn_%s.png" % [base, view]))
	var strip := _save_grid(turns, 4, "%s_turnaround.png" % base, 0.5, 0.5)
	sheet.append(strip)
	var poses: Array[Image] = []
	for pose in POSES:
		_place_pose(pose)
		poses.append(await snap("%s_pose_%s.png" % [base, pose]))
	sheet.append(_save_grid(poses, 4, "%s_poses.png" % base, 0.5, 0.5))
	_save_grid(sheet, 3, shot_path, 1.0, 1.0 / 3.0)
	finish()


## Lay images out in a grid: each is cropped to its middle `crop_w` of the width, then scaled by `k`.
func _save_grid(images: Array[Image], cols: int, path: String, crop_w: float, k: float) -> Image:
	var tiles: Array[Image] = []
	for im0 in images:
		var im := im0.duplicate() as Image
		im.convert(Image.FORMAT_RGBA8)
		var cw := int(im.get_width() * crop_w)
		im = im.get_region(Rect2i((im.get_width() - cw) / 2, 0, cw, im.get_height()))
		im.resize(maxi(1, int(im.get_width() * k)), maxi(1, int(im.get_height() * k)), Image.INTERPOLATE_BILINEAR)
		tiles.append(im)
	var tw := 0
	var th := 0
	for im in tiles:
		tw = maxi(tw, im.get_width())
		th = maxi(th, im.get_height())
	var rows := ceili(tiles.size() / float(cols))
	var out := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.05, 0.04, 0.035))
	for i in tiles.size():
		out.blit_rect(tiles[i], Rect2i(0, 0, tiles[i].get_width(), tiles[i].get_height()), Vector2i((i % cols) * tw, (i / cols) * th))
	print("grid ", path, " ", out.save_png(path))
	return out
