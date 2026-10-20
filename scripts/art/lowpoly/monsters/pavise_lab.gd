extends Node3D
## Pavise Crossbowman lab (docs/design/combat-proposals.md §2; read test and decisions: docs/design/pavise-read-test.md).
## The final look (PaviseModel) with its two crossbow carry styles, "side" (slung at the hip, outside the shield's edge)
## and "above" (shouldered over the shield's top), on the real terrain look (HexMapView + DungeonLook, the game's light
## and floors) with the live monsters and the crew. "game" views use the game camera (orthographic, yaw 45, pitch -56,
## size 24), "close" views the same angle at size 9. Lab only: nothing in the game uses PaviseModel.
## Scene: scenes/pavise_lab.tscn.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/pavise_lab.tscn --shot <dir>/pavise.png
##
## --shot <png>  renders every view and quits; each is <base>_<view>.png, game-size views also <base>_<view>_crop.png
##               (the area round the pavise at 2x, nearest, so the game's pixels can be inspected):
##                 states_close / states_game     walking, planted (raising the bow), aiming (locked) and reloading;
##                                                the top row carries the crossbow "side", the bottom row "above"
##                 facings_close / facings_game   walking (front), aiming front, side and back; rows as above
##                 exposed_close                  shoved off it (left), dropped, broken; rows as above
##                 aim_track / aim_lock           the telegraph on Wick in a pack: a dashed floor line while it tracks
##                                                (0.8 s), then a solid one when it locks (0.4 s)
##                 arrows / arrows_close          bristling with Wick's arrows, a blocked hit's spark and grey "0"
##                 lineup                         the crew, both carry styles and the live monsters, for scale
##               and a contact sheet of the views at <png>.
## --view <a,b,..> only those views (same file names). turn_<side|above>_<carried|planted|reload|left|dropped|broken>
## (not in the set): one state in four facings from a low camera, for model review.
## No --shot: the facings layout, cycling carry / reload / aim.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const CLOSE_SIZE := 9.0
const ROOM := 12                         ## hex radius of the room (DungeonGen-style wall ring round it)
const WALL_HEIGHT := 3

const CARRIES: Array[String] = ["side", "above"]
const RECOMMENDED := "above"             ## the carry style the aim and arrows views use (pavise-read-test.md)
const VIEWS: Array[String] = ["states_close", "states_game", "facings_close", "facings_game", "exposed_close",
		"aim_track", "aim_lock", "arrows", "arrows_close", "lineup"]
const LINE_RED := Color(1.0, 0.16, 0.08)

const LINE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.16, 0.08, 1.0);
uniform float energy = 1.5;
void fragment() {
	float e = 1.0 - abs(UV.x - 0.5) * 2.0;
	ALBEDO = color.rgb * energy * (0.35 + 0.65 * e);
	ALPHA = color.a * clamp(e * 1.6, 0.0, 1.0);
}
"""

var shot_path := ""
var only_view := ""
var map: HexMap
var camera: Camera3D
var caption: Label
var _view_nodes: Array[Node] = []
var _focus := Vector3.INF                ## the world point the 2x crop centres on (INF: the middle of the frame)
var _line_shader: Shader
var _t := 0.0

# the game camera's floor frame: toward the camera, screen right, screen up (away)
var TC := Vector3(sin(deg_to_rad(GAME_YAW)), 0.0, cos(deg_to_rad(GAME_YAW)))
var R := Vector3(cos(deg_to_rad(GAME_YAW)), 0.0, -sin(deg_to_rad(GAME_YAW)))
var U := -Vector3(sin(deg_to_rad(GAME_YAW)), 0.0, cos(deg_to_rad(GAME_YAW)))


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	shot_path = _arg(a, "--shot")
	only_view = _arg(a, "--view")
	_build_world()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 220.0
	add_child(camera)
	camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	caption = Label.new()
	caption.position = Vector2(18, 12)
	caption.add_theme_font_size_override("font_size", 22)
	caption.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	caption.add_theme_constant_override("outline_size", 6)
	layer.add_child(caption)
	if shot_path != "":
		_run_shots()
	else:
		_place("facings_game")


static func _arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := a.find(key)
	if i >= 0 and i + 1 < a.size():
		return a[i + 1]
	return fallback


func _build_world() -> void:
	map = HexMap.new()
	var floor_cells := {}
	for c in Hex.range_cells(Vector2i.ZERO, ROOM):
		floor_cells[c] = "room:0"
	for c: Vector2i in floor_cells:
		map.set_cell(c, 0).tag = floor_cells[c]
	var wall_level := {}
	for c: Vector2i in floor_cells.keys():
		for d in Hex.DIRS:
			var n: Vector2i = c + d
			if not floor_cells.has(n):
				wall_level[n] = 0
	for n: Vector2i in wall_level:
		map.set_cell(n, WALL_HEIGHT, HexMap.Tile.WALL)
	map.cut_walls()
	GameWorld.begin(map, self, 1)
	var terrain := HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)


# ------------------------------------------------------------------ helpers

func _clear() -> void:
	for n in _view_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_view_nodes.clear()


func _keep(n: Node3D) -> Node3D:
	add_child(n)
	_view_nodes.append(n)
	return n


func _put(m: Node3D, pos: Vector3, face: Vector3) -> void:
	m.global_position = Vector3(pos.x, 0.0, pos.z)
	var d := Vector3(face.x, 0.0, face.z)
	if d.length() > 0.001:
		d = d.normalized()
		m.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)


func _aim(yaw_deg: float, pitch_deg: float, size: float, tgt: Vector3) -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	camera.size = size
	camera.global_position = tgt + Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * 80.0
	camera.look_at(tgt, Vector3.UP)


func _game(tgt: Vector3, size: float = GAME_SIZE) -> void:
	_aim(GAME_YAW, GAME_PITCH, size, tgt + Vector3(0, 0.6, 0))


func _pavise(carry: String, pos: Vector3, face: Vector3, state: String = "planted", aim: float = 1.0, walk: float = 0.0, locked: bool = false) -> PaviseModel:
	var m := PaviseModel.new(carry)
	_keep(m)
	_put(m, pos, face)
	m.pose_state(state, aim, walk, 0.35 if walk > 0.0 else 0.6, locked)
	return m


func _monster(kind: String, pos: Vector3, face: Vector3, pose: String = "rest", k: float = 1.0, walk: float = 0.0) -> MonsterModel:
	var m := MonsterModels.make(kind)
	_keep(m)
	_put(m, pos, face)
	m.idle_enabled = false
	m.pose_preview(pose, k)
	if walk > 0.0:
		m.apply_idle(0.35, walk)
	return m


func _hero(which: String, pos: Vector3, face: Vector3, pose: String = "rest") -> LowPolyModel:
	var h: LowPolyModel
	match which:
		"wick":
			h = WickModel.new()
		"gasket":
			h = GasketModel.new()
		_:
			h = RebarModel.new()
	_keep(h)
	_put(h, pos, face)
	h.idle_enabled = false
	if h.has_method("pose_preview"):
		h.call("pose_preview", pose)
	else:
		h.apply_idle(0.6)
	return h


func _line_mat(col: Color, energy: float) -> ShaderMaterial:
	if _line_shader == null:
		_line_shader = Shader.new()
		_line_shader.code = LINE_SHADER
	var m := ShaderMaterial.new()
	m.shader = _line_shader
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", energy)
	return m


## A glowing strip from a to b, `width` wide, lying flat (floor lines) or turned to face up as much as it can (beams).
func _strip(a: Vector3, b: Vector3, width: float, col: Color, energy: float) -> MeshInstance3D:
	var d := b - a
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(width, d.length())
	mi.mesh = pm
	mi.material_override = _line_mat(col, energy)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_keep(mi)
	var z := d.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x).normalized()
	# PlaneMesh: X across, Z along, normal +Y
	mi.global_transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	return mi


## The aim line on the floor from the pavise to its target: dashed and dim while it tracks, solid and bright when it locks.
func _floor_line(from: Vector3, to: Vector3, locked: bool) -> void:
	var a := Vector3(from.x, 0.035, from.z)
	var b := Vector3(to.x, 0.035, to.z)
	if locked:
		_strip(a, b, 0.20, LINE_RED, 2.2)
		_strip(a + Vector3(0, 0.004, 0), b + Vector3(0, 0.004, 0), 0.07, Color(1.0, 0.55, 0.35), 1.6)
		return
	var n := int((b - a).length() / 0.7)
	for i in n:
		var p0 := a.lerp(b, (i + 0.0) / n)
		var p1 := a.lerp(b, (i + 0.55) / n)
		_strip(p0, p1, 0.13, Color(LINE_RED.r, LINE_RED.g, LINE_RED.b, 0.7), 1.3)


## A blocked hit on the front of the shield: a white-hot spark, a few streaks and the grey "0" (the chicken's style).
func _blocked_spark(p: Vector3, face: Vector3) -> void:
	var f := MeshInstance3D.new()
	var q := QuadMesh.new()
	f.mesh = q
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = PaviseModel.FLARE_SHADER
	sm.shader = sh
	sm.set_shader_parameter("color", Color(1.0, 0.85, 0.55))
	sm.set_shader_parameter("energy", 3.0)
	f.material_override = sm
	_keep(f)
	f.global_position = p + face * 0.1
	f.scale = Vector3.ONE * 0.9
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for i in 7:
		var dir := (face * 0.6 + Vector3(r.randf_range(-1, 1), r.randf_range(-0.2, 1.0), r.randf_range(-1, 1))).normalized()
		_strip(p, p + dir * r.randf_range(0.35, 0.7), 0.05, Color(1.0, 0.78, 0.40), 2.6)
	var l := Label3D.new()
	l.text = "0"
	l.modulate = Color(0.82, 0.82, 0.82)
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.outline_size = 14
	l.font_size = int(64.0 * 0.85)
	l.pixel_size = 0.012
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 20
	_keep(l)
	l.global_position = p + Vector3(0, 0.9, 0)


func _caption(text: String) -> void:
	caption.text = text


# ------------------------------------------------------------------ the views

func _place(view: String) -> void:
	_clear()
	_focus = Vector3.INF
	var parts := view.split("_")
	match view:
		"states_close", "states_game":
			_place_rows(["walk", "raise", "aim", "reload"], view.ends_with("close"))
			_caption("States, %s  |  walking - raising the bow - aiming (locked) - reloading  |  top: crossbow (a) side   bottom: (b) above" % ("size 9" if view.ends_with("close") else "game camera"))
		"facings_close", "facings_game":
			_place_rows(["walk", "front", "side", "back"], view.ends_with("close"))
			_caption("Facings, %s  |  walking - aiming: front, side, back  |  top: crossbow (a) side   bottom: (b) above" % ("size 9" if view.ends_with("close") else "game camera"))
		"exposed_close":
			_place_rows(["left", "dropped", "broken"], true)
			_caption("Off its pavise, size 9  |  shoved off it - dropped - broken  |  top: crossbow (a) side   bottom: (b) above")
		"aim_track", "aim_lock":
			_place_aim(view == "aim_lock")
		"arrows", "arrows_close":
			_place_arrows(view == "arrows_close")
		"lineup":
			_place_lineup()
		_:
			if String(parts[0]) == "turn":
				_place_turn(parts[1], parts[2] if parts.size() > 2 else "planted")


## Two rows (top: "side", bottom: "above"), one column per pose.
func _place_rows(poses: Array, close: bool) -> void:
	var gap := 3.6 if close else 4.0
	var row_gap := 2.2 if close else 2.6
	for r in CARRIES.size():
		for i in poses.size():
			var pos := R * (gap * (i - (poses.size() - 1) * 0.5)) + U * (row_gap if r == 0 else -row_gap)
			_pose(CARRIES[r], String(poses[i]), pos)
	if close:
		_game(-U * 0.5, CLOSE_SIZE)
	else:
		_game(Vector3.ZERO)


func _pose(carry: String, pose: String, pos: Vector3) -> PaviseModel:
	match pose:
		"walk":
			return _pavise(carry, pos, TC, "carried", 0.0, 2.5)
		"raise":
			return _pavise(carry, pos, TC, "planted", 0.5)
		"aim", "front":
			return _pavise(carry, pos, TC, "planted", 1.0, 0.0, pose == "aim")
		"reload":
			return _pavise(carry, pos, TC, "planted", 0.0)
		"side":
			return _pavise(carry, pos, R, "planted", 1.0)
		"back":
			return _pavise(carry, pos, U, "planted", 1.0)
	return _pavise(carry, pos, TC, pose, 0.0)


## The pack: the pavise planted on the far side, facing the crew; fodder rushing, archers either side, a brute.
func _pack(carry: String, p: Vector3, f: Vector3, aim: float = 1.0, locked: bool = false) -> PaviseModel:
	var s := f.cross(Vector3.UP).normalized()
	var pav := _pavise(carry, p, f, "planted", aim, 0.0, locked)
	_monster("grunt", p + f * 5.0 + s * 1.4, f, "rest", 1.0, 3.0)
	_monster("grunt", p + f * 4.4 - s * 1.8, f, "windup", 0.4, 3.0)
	_monster("archer", p + f * 0.6 + s * 3.6, f, "windup", 0.6)
	_monster("archer", p + f * 1.2 - s * 3.8, f, "rest")
	_monster("swarmer", p + f * 7.0 + s * 0.4, f, "rest", 1.0, 4.0)
	_monster("swarmer", p + f * 6.5 - s * 0.9, f, "windup", 0.7)
	_monster("swarmer", p + f * 7.6 + s * 1.6, f, "rest", 1.0, 4.0)
	_monster("brute", p + f * 3.0 + s * 3.4, f, "rest")
	return pav


func _crew(p: Vector3, f: Vector3) -> Dictionary:
	var s := f.cross(Vector3.UP).normalized()
	var w := _hero("wick", p + f * 12.5 - s * 0.6, -f, "shoot")
	var g := _hero("gasket", p + f * 10.2 + s * 2.4, -f)
	var r := _hero("rebar", p + f * 9.6 - s * 2.6, -f)
	return {"wick": w, "gasket": g, "rebar": r}


## The telegraph on Wick: tracking (aim 0.5, a dim dashed floor line) or locked (a solid one).
func _place_aim(locked: bool) -> void:
	var f := (TC - R).normalized()
	var p := -f * 6.5 + R * 0.5
	var aim := 1.0 if locked else 0.5
	var pav := _pack(RECOMMENDED, p, f, aim, locked)
	var wick := _crew(p, f)["wick"] as Node3D
	_put(pav, pav.global_position, wick.global_position - pav.global_position)
	pav.pose_state("planted", aim, 0.0, 0.6, locked)
	var dir := (wick.global_position - pav.global_position).normalized()
	_floor_line(pav.global_position + dir * 0.9, wick.global_position, locked)
	_game(p + f * 6.5)
	_focus = p + f * 6.8
	_caption("Aiming at Wick   |   %s" % ("locked (last 0.4 s): a solid floor line, the bolt head flares" if locked else "tracking (first 0.8 s): a dim dashed floor line"))


func _place_arrows(close: bool) -> void:
	var f := (TC - R).normalized()
	var p := Vector3.ZERO
	var pav := _pavise(RECOMMENDED, p, f, "planted", 0.0)
	pav.set_stuck(9)
	var s := f.cross(Vector3.UP).normalized()
	_hero("wick", p + f * 7.5 + s * 0.4, -f, "shoot")
	_hero("rebar", p + f * 3.4 - s * 0.8, -f)
	_hero("gasket", p + s * 2.2 - f * 0.4, -s)
	_blocked_spark(pav.shield_point(0.62), f)
	if close:
		_game(p + f * 1.5, CLOSE_SIZE)
	else:
		_game(p + f * 3.5)
		_focus = p + f * 2.5
	_caption("Bristling with Wick's arrows, reloading; a blocked hit (spark + grey 0); Rebar in front, Gasket on its flank   |   %s" % ("size 9" if close else "game camera"))


func _place_lineup() -> void:
	var row: Array = [["wick", -12.6], ["gasket", -10.2], ["rebar", -7.4], ["side", -4.2], ["above", -1.4],
			["grunt", 1.6], ["archer", 3.8], ["swarmer", 5.8], ["brute", 8.6]]
	for e: Array in row:
		var id: String = e[0]
		var pos := R * float(e[1])
		if id in ["wick", "gasket", "rebar"]:
			_hero(id, pos, TC)
		elif id in CARRIES:
			_pavise(id, pos, TC, "planted", 1.0)
		else:
			_monster(id, pos, TC)
	_game(R * -2.0)
	_focus = R * -2.0
	_caption("Scale: Wick, Gasket, Rebar  |  the pavise (crossbow side, above), aiming  |  grunt, archer, imp, brute")


## Model review (not the game camera): one state in four facings from a low three-quarter camera.
func _place_turn(carry: String, state: String) -> void:
	var yaw := deg_to_rad(160.0)
	var tc := Vector3(sin(yaw), 0.0, cos(yaw))
	var rt := Vector3(cos(yaw), 0.0, -sin(yaw))
	var faces: Array[Vector3] = [tc, tc.rotated(Vector3.UP, 0.8), tc.rotated(Vector3.UP, PI * 0.5), -tc]
	var aim := 1.0 if state == "planted" else 0.0
	var st := "planted" if state == "reload" else state
	for i in faces.size():
		_pavise(carry, rt * (-4.8 + 3.2 * i), faces[i], st, aim, 2.5 if st == "carried" else 0.0)
	_aim(160.0, -18.0, 6.2, Vector3(0, 1.1, 0))
	_caption("crossbow %s, %s (model review, low camera): front - three-quarter - side - back" % [carry, state])


# ------------------------------------------------------------------ live (no --shot)

func _process(delta: float) -> void:
	if shot_path != "":
		return
	_t += delta
	var phase := int(_t / 2.5) % 4
	for n in _view_nodes:
		if n is PaviseModel:
			var m := n as PaviseModel
			match phase:
				0:
					m.pose_state("carried", 0.0, 2.5, _t)
				1, 3:
					m.pose_state("planted", 0.0, 0.0, _t)
				2:
					m.pose_state("planted", clampf(fmod(_t, 2.5) / 1.2, 0.0, 1.0), 0.0, _t, fmod(_t, 2.5) > 0.8)


# ------------------------------------------------------------------ screenshots

func _snap(out_path: String) -> Image:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("shot ", out_path, " ", img.save_png(out_path))
	return img


## The middle of a game-size frame at 2x (nearest): the game's own pixels, enlarged.
func _crop(img: Image, w: int = 900, h: int = 440) -> Image:
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2 + 20
	if _focus != Vector3.INF:
		var sp := camera.unproject_position(_focus)
		cx = clampi(int(sp.x), w / 2, img.get_width() - w / 2)
		cy = clampi(int(sp.y), h / 2, img.get_height() - h / 2)
	var crop := img.get_region(Rect2i(cx - w / 2, cy - h / 2, w, h))
	crop.resize(w * 2, h * 2, Image.INTERPOLATE_NEAREST)
	return crop


func _run_shots() -> void:
	for i in 20:
		await get_tree().process_frame
	var base := shot_path.get_basename()
	var views: Array[String] = []
	views.assign(VIEWS)
	if only_view != "":
		views.clear()
		for v in only_view.split(","):
			views.append(v)
	var sheet: Array[Image] = []
	for view in views:
		_place(view)
		var img := await _snap("%s_%s.png" % [base, view])
		if not view.ends_with("close") and not view.begins_with("turn"):
			var cr := _crop(img)
			if view == "lineup":
				cr = _crop(img, 1300, 380)
			elif view.begins_with("aim"):
				cr = _crop(img, 1000, 560)
			elif view.ends_with("game"):
				cr = _crop(img, 1000, 420)
			cr.save_png("%s_%s_crop.png" % [base, view])
		sheet.append(img)
	if only_view == "" and not sheet.is_empty():
		_save_grid(sheet, 4, shot_path, 1.0 / 4.0)
	get_tree().quit()


func _save_grid(images: Array[Image], cols: int, path: String, k: float) -> void:
	var tw := int(images[0].get_width() * k)
	var th := int(images[0].get_height() * k)
	var rows := ceili(images.size() / float(cols))
	var out := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.05, 0.04, 0.035))
	for i in images.size():
		var im := images[i].duplicate() as Image
		im.convert(Image.FORMAT_RGBA8)
		im.resize(tw, th, Image.INTERPOLATE_BILINEAR)
		out.blit_rect(im, Rect2i(0, 0, tw, th), Vector2i((i % cols) * tw, (i / cols) * th))
	print("grid ", path, " ", out.save_png(path))
