extends Node3D
## Enemy healer lab (docs/design/enemy-healer-options.md): the four healer blockouts (HealerBlockouts) in a mixed pack with
## grunts, an archer, imps and a brute, the three heroes for scale, at the REAL game camera (CameraRig: yaw 45, pitch -56,
## ortho size 24) at 1920x1080. Look-dev only: the heal effects are lab stand-ins, nothing here is used by the game and
## nothing declares gameplay state. Scene: scenes/healer_lab.tscn.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/healer_lab.tscn --shot <dir> [--view <name>]
##
## --shot <dir>  renders every view into <dir>, then quits:
##   <kind>_pack.png (+ _gray, _crop, _crop_gray)   the pack at the game camera, the healer hanging back; kind in
##                                                  cooler / iv_nurse / eye / orderly
##   <kind>_heal.png (+ _crop)                      the same pack with the heal effect mocked (pulse, line, tethers, jump)
##   <kind>_close.png                               low angle: grunt, the healer, a brute and Wick
##   lineup.png (+ _gray)                           everyone in a row at the game camera, named
##   sheet.png                                      the comparison sheet: the lineup crop (colour over grey), the four
##                                                  pack crops and the four heal crops
##   measure.txt                                    each model alone at the game camera: screen pixels covered, the
##                                                  bounding box in pixels (no floor, no bloom)
## --view <name> only that view (as above, without the derived images).

const HealerBlockouts := preload("res://scripts/art/lowpoly/monsters/healer_blockouts.gd")

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const KINDS: Array[String] = ["cooler", "iv_nurse", "eye", "orderly"]
const BILE := HealerBlockouts.BILE
const BILE_HOT := HealerBlockouts.BILE_HOT

var out_dir := ""
var only_view := ""
var map: HexMap
var terrain: HexMapView
var camera: Camera3D
var env: Environment
var heroes := {}                 ## wick / gasket / rebar -> LowPolyModel
var mons := {}                   ## slot name -> MonsterModel (grunt_a, grunt_b, archer, brute, swarm0..2, goblin, corpse)
var healers := {}                ## kind -> HealerModel
var fx: Node3D
var labels: Node3D
var _right := Vector3.ZERO
var _fwd := Vector3.ZERO


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_dir = _arg(a, "--shot")
	only_view = _arg(a, "--view")
	_build_world()
	for h: String in ["wick", "gasket", "rebar"]:
		var m: LowPolyModel
		match h:
			"wick": m = WickModel.new()
			"gasket": m = GasketModel.new()
			_: m = RebarModel.new()
		heroes[h] = m
		add_child(m)
	for slot: String in ["grunt_a", "grunt_b", "archer", "brute", "swarm0", "swarm1", "swarm2", "goblin", "corpse"]:
		var kind := slot
		if slot.begins_with("grunt") or slot == "corpse":
			kind = "grunt"
		elif slot.begins_with("swarm"):
			kind = "swarmer"
		var m := MonsterModels.make(kind)
		mons[slot] = m
		add_child(m)
	for k in KINDS:
		var hm := HealerBlockouts.build(k)
		healers[k] = hm
		add_child(hm)
	fx = Node3D.new()
	add_child(fx)
	labels = Node3D.new()
	add_child(labels)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 220.0
	add_child(camera)
	var yaw := deg_to_rad(GAME_YAW)
	_right = Vector3(cos(yaw), 0.0, -sin(yaw))
	_fwd = Vector3(-sin(yaw), 0.0, -cos(yaw))
	for m in _all():
		m.idle_enabled = false
		m.apply_idle(0.6)
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		_run_shots()
	else:
		_place("lineup")


static func _arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := a.find(key)
	if i >= 0 and i + 1 < a.size():
		return a[i + 1]
	return fallback


func _build_world() -> void:
	map = HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 26):
		var d := Hex.distance(c, Vector2i.ZERO)
		if d <= 15:
			map.set_cell(c, 0).tag = "room:0"
		elif d <= 21:
			map.set_cell(c, 6, HexMap.Tile.WALL)
	GameWorld.begin(map, self, 1)
	terrain = HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)
	for c in get_children():
		if c is WorldEnvironment:
			env = (c as WorldEnvironment).environment


func _all() -> Array[LowPolyModel]:
	var out: Array[LowPolyModel] = []
	for h: LowPolyModel in heroes.values():
		out.append(h)
	for m: LowPolyModel in mons.values():
		out.append(m)
	for m: LowPolyModel in healers.values():
		out.append(m)
	return out


func _park_all() -> void:
	var i := 0
	for m in _all():
		m.position = Vector3(90.0 + 4.0 * float(i), 0.0, 90.0)
		m.rotation = Vector3.ZERO
		if m is MonsterModel:
			(m as MonsterModel).set_tint(Color.BLACK, 0.0)
		if m is MonsterModel and not (m == mons["corpse"]):
			(m as MonsterModel).pose_preview("rest")
		i += 1
	for c in fx.get_children():
		c.queue_free()
	for c in labels.get_children():
		c.queue_free()


## Put `m` at (right, fwd) screen-aligned coordinates, facing the X/Z direction `face`.
func _put(m: Node3D, r: float, f: float, face: Vector3) -> void:
	m.position = _right * r + _fwd * f
	m.rotation = Vector3(0.0, atan2(-face.x, -face.z), 0.0)


func _aim(yaw_deg: float, pitch_deg: float, size: float, tgt: Vector3) -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	camera.size = size
	camera.global_position = tgt + Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * 60.0
	camera.look_at(tgt, Vector3.UP)


# --------------------------------------------------------------------------- layouts

## The healer's slot in the pack (right, fwd): 8-9 from the nearest hero, behind the brute.
func _healer_slot(kind: String) -> Vector2:
	return Vector2(5.0, -1.0) if kind == "orderly" else Vector2(3.8, -0.9)


## The pack: heroes on the left facing right, the monsters on the right facing them, the healer at the back.
func _place_pack(kind: String) -> void:
	_park_all()
	var to_heroes := -_right
	_put(heroes["wick"], -7.4, 1.4, _right)
	_put(heroes["gasket"], -6.4, -1.2, _right)
	_put(heroes["rebar"], -5.0, 0.4, _right)
	_put(mons["grunt_a"], -0.8, -1.4, to_heroes)
	_put(mons["grunt_b"], -0.4, 1.8, to_heroes)
	_put(mons["swarm0"], -1.8, 0.4, to_heroes)
	_put(mons["swarm1"], -1.0, -3.0, to_heroes)
	_put(mons["swarm2"], 0.6, 3.4, to_heroes)
	_put(mons["brute"], 1.4, 0.2, to_heroes)
	_put(mons["archer"], 3.6, 2.8, to_heroes)
	var hs := _healer_slot(kind)
	_put(healers[kind], hs.x, hs.y, to_heroes)
	_aim(GAME_YAW, GAME_PITCH, GAME_SIZE, _right * -1.0 + Vector3(0.0, 0.8, 0.0))
	for h: LowPolyModel in heroes.values():
		h.apply_idle(0.6)


func _place_close(kind: String) -> void:
	_park_all()
	var yaw := 160.0
	var r := Vector3(cos(deg_to_rad(yaw)), 0.0, -sin(deg_to_rad(yaw)))
	var toward := Vector3(sin(deg_to_rad(yaw)), 0.0, cos(deg_to_rad(yaw)))
	var row: Array = [[mons["grunt_a"], -2.6], [healers[kind], 0.0], [mons["brute"], 2.9], [heroes["wick"], 5.2]]
	if kind == "orderly":
		row = [[mons["grunt_a"], -2.9], [healers[kind], 0.0], [mons["brute"], 3.0], [heroes["wick"], 5.3]]
	for e: Array in row:
		var n: Node3D = e[0]
		n.position = r * float(e[1])
		n.rotation = Vector3(0.0, atan2(-toward.x, -toward.z) + (0.6 if n == healers[kind] else 0.0), 0.0)
	_aim(yaw, -18.0, 5.2, r * 1.3 + Vector3(0.0, 1.25, 0.0))


## Everyone in a row at the game camera, named on the floor.
func _place_lineup() -> void:
	_park_all()
	var row: Array = [["Wick", heroes["wick"], 0.0], ["Gasket", heroes["gasket"], 2.0], ["Rebar", heroes["rebar"], 4.4],
			["Imp", mons["swarm0"], 6.6], ["Grunt", mons["grunt_a"], 8.4], ["Archer", mons["archer"], 10.4],
			["Goblin", mons["goblin"], 12.6], ["Brute", mons["brute"], 15.2],
			["Water Cooler", healers["cooler"], 18.6], ["Company Nurse", healers["iv_nurse"], 21.6],
			["Night Nurse", healers["eye"], 24.4], ["Orderly", healers["orderly"], 27.4]]
	var mid := 13.7
	var toward := -_fwd
	for e: Array in row:
		var n: Node3D = e[1]
		var x := float(e[2]) - mid
		_put(n, x, 0.0, toward)
		var below := 1.6
		if n == healers["orderly"]:
			_put(n, x, 1.0, toward)     # its gurney runs out in front
			below = 1.9
		_label(String(e[0]), _right * x - _fwd * below + Vector3(0, 0.05, 0), Color(0.95, 0.92, 0.84), 24)
	for h: LowPolyModel in heroes.values():
		h.apply_idle(0.6)
	_aim(GAME_YAW, GAME_PITCH, GAME_SIZE, Vector3(0.0, 0.8, 0.0))


# --------------------------------------------------------------------------- heal effects (lab stand-ins)

func _glow_mat(c: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.render_priority = 3
	return m


func _bar(a: Vector3, b: Vector3, w: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, w, maxf(a.distance_to(b), 0.001))
	mi.mesh = bm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(mi)
	var d := b - a
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(d, up), (a + b) * 0.5)
	return mi


func _ball(p: Vector3, r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(mi)
	mi.global_position = p
	return mi


func _ring(center: Vector3, r: float, w: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - w
	tm.outer_radius = r
	tm.rings = 48
	mi.mesh = tm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(mi)
	mi.global_position = center
	mi.scale = Vector3(1.0, 0.12, 1.0)


func _disc(center: Vector3, r: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.01
	cm.radial_segments = 48
	mi.mesh = cm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(mi)
	mi.global_position = center


func _label(text: String, p: Vector3, col: Color, size: int = 48) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = size
	l.outline_size = 10
	l.pixel_size = 0.012
	l.modulate = col
	l.outline_modulate = Color(0.05, 0.03, 0.03)
	labels.add_child(l)
	l.global_position = p


## A sagging line from a to b: a hot core in a soft sheath, `sag` below the straight line at the middle.
func _line(a: Vector3, b: Vector3, sag: float, wave: float = 0.0, segs: int = 18, core: float = 0.06) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var side := (b - a).cross(Vector3.UP).normalized()
	for i in segs + 1:
		var u := float(i) / segs
		var p := a.lerp(b, u) + Vector3.DOWN * sag * 4.0 * u * (1.0 - u)
		p += side * wave * sin(u * TAU * 2.0) * sin(u * PI)
		pts.append(p)
	var m_core := _glow_mat(BILE_HOT, 1.0, 3.0)
	var m_sheath := _glow_mat(BILE, 0.45, 2.0)
	for i in segs:
		_bar(pts[i], pts[i + 1], core, m_core)
		_bar(pts[i], pts[i + 1], core * 3.2, m_sheath)
	return pts


func _chest(m: Node3D, h: float = 1.2) -> Vector3:
	return m.global_position + Vector3.UP * h


func _patient(m: MonsterModel, amount: String, h: float = 2.6) -> void:
	m.set_tint(BILE, 0.24)
	_label(amount, m.global_position + Vector3.UP * h, BILE, 56)
	_ball(m.global_position + Vector3.UP * 0.9, 0.7, _glow_mat(BILE, 0.10, 1.0))


func _heal_fx(kind: String) -> void:
	var hm: HealerBlockouts.HealerModel = healers[kind]
	hm.pose_preview("heal", 1.0)
	match kind:
		"cooler":
			# THE PULSE: three rising rings out to r 5 from the cooler, a faint disc, a splash over the jug; every monster
			# in the ring takes a sip
			var c := hm.global_position + Vector3(0, 0.04, 0)
			_disc(c, 5.0, _glow_mat(BILE, 0.07, 0.8))
			_ring(c, 5.0, 0.22, _glow_mat(BILE, 0.95, 2.5))
			_ring(c + Vector3(0, 0.08, 0), 3.4, 0.16, _glow_mat(BILE, 0.70, 2.0))
			_ring(c + Vector3(0, 0.16, 0), 1.8, 0.12, _glow_mat(BILE, 0.55, 1.8))
			var top := hm.heal_from() + Vector3(0, 0.75, 0)
			for i in 7:
				var a := TAU * float(i) / 7.0
				_ball(top + Vector3(cos(a) * 0.35, 0.15 + 0.12 * (i % 3), sin(a) * 0.35), 0.09, _glow_mat(BILE_HOT, 0.9, 3.0))
			for slot: String in ["grunt_a", "grunt_b", "brute", "archer", "swarm0", "swarm2"]:
				var m: MonsterModel = mons[slot]
				if Vector2(m.global_position.x - c.x, m.global_position.z - c.z).length() <= 5.0:
					_patient(m, "+15", 3.2 if slot == "brute" else 2.5)
		"iv_nurse":
			# THE LINE: from the bag over the pack to the brute's chest; a hero stepping through it cuts it
			var pts := _line(hm.heal_from(), _chest(mons["brute"], 1.9), 1.1, 0.0, 22, 0.05)
			for i in [5, 11, 17]:
				_ball(pts[i], 0.07, _glow_mat(BILE_HOT, 1.0, 4.0))
			_patient(mons["brute"], "+12", 3.4)
		"eye":
			# THE TETHERS: three at once, from the tendril tips to three patients
			var tips: Array[Vector3] = (hm as HealerBlockouts.EyeModel).tendril_tips()
			var targets: Array = [[mons["brute"], 1.8, "+5", 3.4, 0], [mons["grunt_a"], 1.2, "+5", 2.6, 2], [mons["archer"], 1.1, "+5", 2.5, 4]]
			for t: Array in targets:
				var m: MonsterModel = t[0]
				_line(tips[int(t[4])], _chest(m, float(t[1])), 0.2, 0.16, 20, 0.04)
				_patient(m, String(t[2]), float(t[3]))
			_ball(hm.heal_from(), 0.36, _glow_mat(BILE, 0.35, 2.0))
		"orderly":
			# THE JUMP: a downed grunt beside the gurney, the cables clamped to its chest, sparks and a column
			var corpse: MonsterModel = mons["corpse"]
			corpse.set_downed(true)
			corpse.idle_enabled = false
			var spot := hm.global_position + (-_right) * 1.2 + _fwd * -2.3
			corpse.position = spot + Vector3(0, 0.22, 0)
			corpse.rotation = Vector3(0.0, deg_to_rad(GAME_YAW + 90.0), deg_to_rad(90.0))
			corpse.set_tint(BILE, 0.45)
			var chest := spot + Vector3(0, 0.45, 0)
			var bat := hm.heal_from()
			for s: float in [-1.0, 1.0]:
				var from := bat + _right * 0.10 * s
				var to := chest + _fwd * 0.20 * s
				_line(from, to, 0.5, 0.0, 14, 0.035)      # live cables: lit the enemy chartreuse while the jolt runs
			_disc(spot + Vector3(0, 0.03, 0), 1.1, _glow_mat(BILE, 0.18, 1.0))
			var col := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.55
			cm.bottom_radius = 0.75
			cm.height = 3.0
			col.mesh = cm
			col.material_override = _glow_mat(BILE, 0.16, 1.2)
			fx.add_child(col)
			col.global_position = spot + Vector3(0, 1.5, 0)
			var rng := RandomNumberGenerator.new()
			rng.seed = 11
			for i in 12:
				var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1.2), rng.randf_range(-1, 1)).normalized()
				_bar(chest, chest + d * rng.randf_range(0.35, 0.8), 0.045, _glow_mat(BILE_HOT, 1.0, 5.0))
			_label("CLEAR!", spot + Vector3(0, 0.6, 0) - _fwd * 1.3, BILE, 48)


# --------------------------------------------------------------------------- views

func _place(view: String) -> void:
	if view == "lineup":
		_place_lineup()
		return
	var parts := view.rsplit("_", true, 1)
	var kind: String = parts[0]
	var what: String = parts[1]
	match what:
		"pack":
			_place_pack(kind)
		"heal":
			_place_pack(kind)
			_heal_fx(kind)
		"close":
			_place_close(kind)


func _views() -> Array[String]:
	var out: Array[String] = []
	for k in KINDS:
		for w: String in ["pack", "heal", "close"]:
			out.append("%s_%s" % [k, w])
	out.append("lineup")
	return out


func _snap() -> Image:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _save(img: Image, name_: String) -> void:
	var p := out_dir.path_join(name_ + ".png")
	print("shot ", p, " ", img.save_png(p))


static func _gray(img: Image) -> Image:
	var g := img.duplicate() as Image
	g.adjust_bcs(1.0, 1.0, 0.0)
	return g


## A crop of `size` around the screen point of world position `at`, scaled by `k` (nearest: game pixels stay pixels).
func _crop(img: Image, at: Vector3, size: Vector2i, k: int) -> Image:
	var sp := camera.unproject_position(at)
	var vr := get_viewport().get_visible_rect().size     # (the project's stretch: viewport units, not image pixels)
	sp = Vector2(sp.x * img.get_width() / vr.x, sp.y * img.get_height() / vr.y)
	var x := clampi(int(sp.x) - size.x / 2, 0, img.get_width() - size.x)
	var y := clampi(int(sp.y) - size.y / 2, 0, img.get_height() - size.y)
	var c := img.get_region(Rect2i(x, y, size.x, size.y))
	if k > 1:
		c.resize(size.x * k, size.y * k, Image.INTERPOLATE_NEAREST)
	return c


func _pack_center() -> Vector3:
	return _right * -1.0 + Vector3(0, 1.0, 0)


func _run_shots() -> void:
	for i in 20:
		await get_tree().process_frame
	if only_view != "":
		_place(only_view)
		_save(await _snap(), only_view)
		get_tree().quit()
		return
	var crops := {}
	for v in _views():
		_place(v)
		var img := await _snap()
		img.convert(Image.FORMAT_RGB8)
		_save(img, v)
		if v.ends_with("_pack") or v.ends_with("_heal"):
			var c := _crop(img, _pack_center(), Vector2i(960, 540), 2)
			_save(c, v + "_crop")
			crops[v] = c
			if v.ends_with("_pack"):
				_save(_gray(img), v + "_gray")
				var cg := _gray(c)
				_save(cg, v + "_crop_gray")
				crops[v + "_gray"] = cg
		if v == "lineup":
			_save(_gray(img), "lineup_gray")
			crops["lineup"] = _crop(img, Vector3(0, 1.0, 0) + _right * 0.2, Vector2i(1500, 330), 1)
	_sheet(crops)
	await _measure()
	get_tree().quit()


## The comparison sheet: the lineup crop (colour, then grey) across the top; then the four packs (colour), their greys,
## and the four heal mocks, each a half-size 2x crop.
func _sheet(crops: Dictionary) -> void:
	var line: Image = crops["lineup"]
	var cw := 800
	var ch := 450
	var w := maxi(line.get_width(), cw * 2)
	var rows: Array[String] = []
	for k in KINDS:
		rows.append(k)
	var h := line.get_height() * 2 + ch * 6
	var sheet := Image.create(w, h, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.06, 0.05, 0.05))
	sheet.blit_rect(line, Rect2i(Vector2i.ZERO, line.get_size()), Vector2i((w - line.get_width()) / 2, 0))
	var lg := _gray(line)
	sheet.blit_rect(lg, Rect2i(Vector2i.ZERO, lg.get_size()), Vector2i((w - lg.get_width()) / 2, line.get_height()))
	var y0 := line.get_height() * 2
	var order: Array[String] = []
	for k in KINDS:
		order.append(k + "_pack")
	for k in KINDS:
		order.append(k + "_pack_gray")
	for k in KINDS:
		order.append(k + "_heal")
	for i in order.size():
		var c := (crops[order[i]] as Image).duplicate() as Image
		c.resize(cw, ch, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(c, Rect2i(0, 0, cw, ch), Vector2i((i % 2) * cw + (w - cw * 2) / 2, y0 + (i / 2) * ch))
	_save(sheet, "sheet")


## Each model alone at the origin, facing the game camera, no floor and no bloom: how many screen pixels it covers.
func _measure() -> void:
	_park_all()
	terrain.visible = false
	var glow_was := env.glow_enabled if env != null else false
	if env != null:
		env.glow_enabled = false
	_aim(GAME_YAW, GAME_PITCH, GAME_SIZE, Vector3(0, 0.8, 0))
	var base := await _snap()
	base.convert(Image.FORMAT_RGB8)
	var rows := PackedStringArray(["model                 px covered   box w x h (px)   (game camera, 1920x1080, ortho 24)"])
	var list: Array = [["wick", heroes["wick"]], ["gasket", heroes["gasket"]], ["rebar", heroes["rebar"]],
			["imp (swarmer)", mons["swarm0"]], ["grunt", mons["grunt_a"]], ["archer", mons["archer"]], ["goblin", mons["goblin"]],
			["brute", mons["brute"]], ["cooler", healers["cooler"]], ["iv_nurse", healers["iv_nurse"]], ["eye", healers["eye"]],
			["orderly", healers["orderly"]]]
	for e: Array in list:
		_park_all()
		var n: Node3D = e[1]
		_put(n, 0.0, 0.0, -_fwd)
		if n == heroes["wick"] or n == heroes["gasket"] or n == heroes["rebar"]:
			(n as LowPolyModel).apply_idle(0.6)
		var img := await _snap()
		img.convert(Image.FORMAT_RGB8)
		var r := _diff(base, img)
		rows.append("%-20s %8d      %4d x %-4d" % [String(e[0]), int(r[0]), int(r[1]), int(r[2])])
	terrain.visible = true
	if env != null:
		env.glow_enabled = glow_was
	var f := FileAccess.open(out_dir.path_join("measure.txt"), FileAccess.WRITE)
	f.store_string("\n".join(rows) + "\n")
	f.close()
	print("\n".join(rows))


## [pixels that differ, bbox width, bbox height] between two frames (only the central 900 x 700 is searched).
static func _diff(a: Image, b: Image) -> Array:
	var x0 := a.get_width() / 2 - 450
	var y0 := a.get_height() / 2 - 400
	var n := 0
	var minx := 99999
	var maxx := -1
	var miny := 99999
	var maxy := -1
	for y in range(y0, y0 + 700):
		for x in range(x0, x0 + 900):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.09:
				n += 1
				minx = mini(minx, x)
				maxx = maxi(maxx, x)
				miny = mini(miny, y)
				maxy = maxi(maxy, y)
	if maxx < 0:
		return [0, 0, 0]
	return [n, maxx - minx + 1, maxy - miny + 1]
