extends Node3D
## Pavise Crossbowman READ TEST (docs/design/combat-proposals.md Â§2; findings: docs/design/pavise-read-test.md). The four
## PaviseModel variants on the real terrain look (HexMapView + DungeonLook, the game's light and floors), with the live
## monsters and the crew, shot with the real game camera (orthographic, yaw 45, pitch -56, size 24) unless named
## "close" (size 9, same angle). Lab only: nothing in the game uses PaviseModel. Scene: scenes/pavise_lab.tscn.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/pavise_lab.tscn --shot <dir>/pavise.png
##
## --shot <png>  renders every view and quits; each is <base>_<view>.png, game-size views also <base>_<view>_crop.png
##               (the middle of the frame at 2x, nearest, so the game's pixels can be inspected):
##                 solo_<v>                  the variant alone: walking with the shield, planted (front), planted (side),
##                                           planted (back)
##                 pack_<v>_<front|back|side> planted on the far side of a room with 2 grunts, 2 archers, 3 imps and a
##                                           brute, the crew coming at it from the camera side / the far side / the left
##                 aim_<mode>_<v>            the aim telegraph on Wick: glow (the bolt head only), track (a dim dashed
##                                           floor line, the first 0.8 s), lock (a solid floor line, the last 0.4 s),
##                                           beam (a raised line from the bolt head)
##                 arrows_<v> / arrows_<v>_close   a pavise bristling with Wick's arrows, a blocked hit's spark and "0"
##                 close_<v>                 size 9: walking, aiming (front), aiming (back) / left, dropped, broken
##                 cues_<cue>                variant A in five facings with a front cue: none, glint, arc
##                 lineup                    the crew, the four variants and the live monsters in a row, for scale
##                 compare (+ _gray, _both)  the four variants side by side at game size: planted front, planted back,
##                                           walking; and the same in grayscale (silhouette and value only)
##               and a contact sheet of the main views at <png>.
## --view <a,b,..> only those views (same file names).
## No --shot: the comparison layout, the variants cycling carry / plant / aim.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const CLOSE_SIZE := 9.0
const ROOM := 12                         ## hex radius of the room (DungeonGen-style wall ring round it)
const WALL_HEIGHT := 3

const VARIANTS: Array[String] = ["a", "b", "c", "d"]
const AIM_MODES: Array[String] = ["glow", "track", "lock", "beam"]
const CUES: Array[String] = ["none", "glint", "arc"]
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
		_place("compare")


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


func _pavise(v: String, pos: Vector3, face: Vector3, state: String = "planted", aim: float = 1.0, walk: float = 0.0, locked: bool = false) -> PaviseModel:
	var m := PaviseModel.new(v)
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


## A raised beam from the bolt head to the target's chest.
func _beam(from: Vector3, to: Vector3) -> void:
	_strip(from, to, 0.10, LINE_RED, 2.4)


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
	match String(parts[0]):
		"solo":
			_place_solo(parts[1])
		"pack":
			_place_pack(parts[1], parts[2])
		"aim":
			_place_aim(parts[1], parts[2])
		"arrows":
			_place_arrows(parts[1], parts.size() > 2)
		"close":
			_place_close(parts[1])
		"cues":
			_place_cues(parts[1])
		"lineup":
			_place_lineup()
		"compare":
			_place_compare()
		"turn":
			_place_turn(parts[1], parts[2] if parts.size() > 2 else "planted")


func _place_solo(v: String) -> void:
	var c := Vector3.ZERO
	_pavise(v, c + R * -6.0, TC, "carried", 0.0, 2.5)
	_pavise(v, c + R * -2.0, TC, "planted", 1.0)
	_pavise(v, c + R * 2.0, R, "planted", 1.0)
	_pavise(v, c + R * 6.0, U, "planted", 1.0)
	_game(c)
	_caption("%s alone, game camera (size 24)   |   walking with it  -  planted, front  -  planted, side  -  planted, back" % PaviseModel.TITLES[v])


## The pack: the pavise planted on the far side, facing the crew; fodder rushing, archers either side, a brute.
func _pack(v: String, p: Vector3, f: Vector3, aim: float = 1.0, locked: bool = false) -> PaviseModel:
	var s := f.cross(Vector3.UP).normalized()
	var pav := _pavise(v, p, f, "planted", aim, 0.0, locked)
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


func _place_pack(v: String, side: String) -> void:
	var f := TC
	match side:
		"back":
			f = U
		"side":
			f = -R
	var p := -f * 6.0
	_pack(v, p, f)
	_crew(p, f)
	_game(p + f * 6.0)
	_focus = p + f * 3.0
	var what := {"front": "crew on the camera side: the shield faces the camera",
			"back": "crew on the far side: we see its back", "side": "crew on the left: we see it side-on"}
	_caption("%s in a pack (2 grunts, 2 archers, 3 imps, a brute) with the crew, game camera   |   %s" % [PaviseModel.TITLES[v], what[side]])


func _place_aim(mode: String, v: String) -> void:
	var f := (TC - R).normalized()
	var p := -f * 6.5 + R * 0.5
	var locked := mode != "track"
	var pav := _pack(v, p, f, 0.5 if mode == "track" else 1.0, locked)
	var crew := _crew(p, f)
	var wick := crew["wick"] as Node3D
	# turn the pavise to its target (Wick)
	_put(pav, pav.global_position, wick.global_position - pav.global_position)
	pav.aim_distance = (wick.global_position - pav.global_position).length()
	pav.pose_state("planted", 0.5 if mode == "track" else 1.0, 0.0, 0.6, locked)
	var tip := pav.tip_position()
	match mode:
		"track":
			_floor_line(pav.global_position + (wick.global_position - pav.global_position).normalized() * 0.9, wick.global_position, false)
		"lock":
			_floor_line(pav.global_position + (wick.global_position - pav.global_position).normalized() * 0.9, wick.global_position, true)
		"beam":
			_beam(tip, wick.global_position + Vector3(0, 1.35, 0))
	_game(p + f * 6.5)
	_focus = p + f * 6.8
	var what := {"glow": "the bolt head's glow only (no line)", "track": "tracking (first 0.8 s): a dim dashed floor line",
			"lock": "locked (last 0.4 s): a solid floor line", "beam": "a raised beam from the bolt head to Wick's chest"}
	_caption("%s aiming at Wick   |   %s" % [PaviseModel.TITLES[v], what[mode]])


func _place_arrows(v: String, close: bool) -> void:
	var f := (TC - R).normalized()
	var p := Vector3.ZERO
	var pav := _pavise(v, p, f, "planted", 0.0)
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
	_caption("%s bristling with Wick's arrows, a blocked hit (spark + grey 0), Rebar in front, Gasket on its flank   |   %s" % [
			PaviseModel.TITLES[v], "size 9" if close else "game camera"])


func _place_close(v: String) -> void:
	var c := Vector3.ZERO
	_pavise(v, c + R * -4.6 + U * 2.0, TC, "carried", 0.0, 2.5)
	_pavise(v, c + U * 2.0, TC, "planted", 1.0, 0.0, true)
	_pavise(v, c + R * 4.6 + U * 2.0, U, "planted", 1.0)
	_pavise(v, c + R * -4.6 - U * 1.8, TC, "left", 0.0)
	_pavise(v, c - U * 1.8, TC, "dropped", 0.0)
	_pavise(v, c + R * 4.6 - U * 1.8, TC, "broken", 0.0)
	_game(c - U * 0.7, CLOSE_SIZE)
	_caption("%s, size 9   |   back row: walking with it - aiming, locked (front) - aiming (back)   |   front row: shoved off it (left) - dropped - broken" % PaviseModel.TITLES[v])


## Variant A in five facings, with one front cue: none, glint (lit front edges) or arc (a red fan over the blocked arc).
func _place_cues(cue: String) -> void:
	var c := Vector3.ZERO
	var faces: Array[Vector3] = [TC, (TC - R).normalized(), -R, (U - R).normalized(), U]
	for i in faces.size():
		var m := _pavise("a", c + R * (-8.0 + 4.0 * i), faces[i], "planted", 0.0)
		m.set_front_cue("" if cue == "none" else cue)
	_hero("wick", c + R * -8.0 - U * 6.0, U)
	_game(c - U * 1.0)
	_caption("A doc pavise, front cue: %s   |   facing: camera - camera-left - left - away-left - away" % cue)


func _place_lineup() -> void:
	var c := Vector3.ZERO
	var row: Array = [["wick", -15.0], ["gasket", -12.6], ["rebar", -9.8], ["a", -6.6], ["b", -3.6], ["c", -0.6], ["d", 2.4],
			["grunt", 5.2], ["archer", 7.4], ["swarmer", 9.4], ["brute", 12.2]]
	for e: Array in row:
		var id: String = e[0]
		var pos := c + R * float(e[1])
		if id in ["wick", "gasket", "rebar"]:
			_hero(id, pos, TC)
		elif id.length() == 1:
			_pavise(id, pos, TC, "planted", 1.0)
		else:
			_monster(id, pos, TC)
	_game(c)
	_caption("Scale: Wick, Gasket, Rebar  |  A doc, B heavy, C painted, D lamp (planted, aiming)  |  grunt, archer, imp, brute")


## The four side by side at game size: planted front, planted back, walking.
func _place_compare() -> void:
	var c := Vector3.ZERO
	for i in VARIANTS.size():
		var x := R * (-6.0 + 4.0 * i)
		_pavise(VARIANTS[i], c + x - U * 3.2, TC, "planted", 1.0)
		_pavise(VARIANTS[i], c + x + U * 0.4, U, "planted", 1.0)
		_pavise(VARIANTS[i], c + x + U * 4.0, TC, "carried", 0.0, 2.5)
	_monster("grunt", c + R * -10.0 + U * 0.4, TC)
	_monster("archer", c + R * 10.0 + U * 0.4, TC)
	_game(c)
	_caption("A doc - B heavy - C painted - D lamp   |   front row: planted, facing the camera   middle: planted, facing away   back: walking   (grunt left, archer right)")


## Model review (not the game camera): one state in four facings from a low three-quarter camera.
func _place_turn(v: String, state: String) -> void:
	var yaw := deg_to_rad(160.0)
	var tc := Vector3(sin(yaw), 0.0, cos(yaw))
	var rt := Vector3(cos(yaw), 0.0, -sin(yaw))
	var faces: Array[Vector3] = [tc, tc.rotated(Vector3.UP, 0.8), tc.rotated(Vector3.UP, PI * 0.5), -tc]
	for i in faces.size():
		_pavise(v, rt * (-4.8 + 3.2 * i), faces[i], state, 1.0 if state == "planted" else 0.0, 2.5 if state == "carried" else 0.0)
	_aim(160.0, -18.0, 6.2, Vector3(0, 1.1, 0))
	_caption("%s, %s (model review, low camera): front - three-quarter - side - back" % [PaviseModel.TITLES[v], state])


# ------------------------------------------------------------------ live (no --shot)

func _process(delta: float) -> void:
	if shot_path != "":
		return
	_t += delta
	var phase := int(_t / 2.5) % 3
	for n in _view_nodes:
		if n is PaviseModel:
			var m := n as PaviseModel
			match phase:
				0:
					m.pose_state("carried", 0.0, 2.5, _t)
				1:
					m.pose_state("planted", 0.0, 0.0, _t)
				2:
					m.pose_state("planted", clampf(fmod(_t, 2.5) / 1.2, 0.0, 1.0), 0.0, _t, fmod(_t, 2.5) > 0.8)


# ------------------------------------------------------------------ screenshots

func _views() -> Array[String]:
	var out: Array[String] = []
	for v in VARIANTS:
		out.append("solo_" + v)
		out.append("close_" + v)
		for side in ["front", "back", "side"]:
			out.append("pack_%s_%s" % [v, side])
		for mode in AIM_MODES:
			out.append("aim_%s_%s" % [mode, v])
		out.append("arrows_" + v)
		out.append("arrows_%s_close" % v)
	for cue in CUES:
		out.append("cues_" + cue)
	out.append("lineup")
	out.append("compare")
	return out


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
	var views := _views()
	if only_view != "":
		views.clear()
		for v in only_view.split(","):
			views.append(v)
	var sheet: Array[Image] = []
	for view in views:
		_place(view)
		var img := await _snap("%s_%s.png" % [base, view])
		var game_size := not view.begins_with("close") and not view.ends_with("close")
		if game_size:
			var cr := _crop(img)
			if view == "compare":
				cr = _crop(img, 1100, 480)
			elif view == "lineup":
				cr = _crop(img, 1400, 360)
			elif view.begins_with("aim"):
				cr = _crop(img, 1000, 560)
			cr.save_png("%s_%s_crop.png" % [base, view])
			if view == "compare":
				var gray := cr.duplicate() as Image
				gray.convert(Image.FORMAT_RGBA8)
				gray.adjust_bcs(1.0, 1.0, 0.0)
				gray.save_png("%s_compare_gray.png" % base)
				var both := Image.create(cr.get_width(), cr.get_height() * 2, false, Image.FORMAT_RGBA8)
				var cr8 := cr.duplicate() as Image
				cr8.convert(Image.FORMAT_RGBA8)
				both.blit_rect(cr8, Rect2i(Vector2i.ZERO, cr8.get_size()), Vector2i.ZERO)
				both.blit_rect(gray, Rect2i(Vector2i.ZERO, gray.get_size()), Vector2i(0, cr.get_height()))
				both.save_png("%s_compare_both.png" % base)
		if view.begins_with("solo") or view.begins_with("close") or view.ends_with("_front") or view == "compare":
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
