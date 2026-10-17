extends Node3D
## BACKDROP PROTOTYPE C, "The storefront": the business at night. A cinder-block unit on a hex-paved lot, its
## roll-up door half open onto a warm-lit shop, a rooftop neon sign (dead letters flicker), a painted
## 1-800-LOW-MANA board, the van parked in its pentagram bay, the crew loitering, a sodium street lamp, and a
## manhole in the foreground leaking red: the next job is right outside. A red glow on the skyline says the city
## has problems.
##
## Moods (opts "mood"): night (default) | rain

const Kit := preload("res://scripts/ui/backdrops/backdrop_kit.gd")
const VanStandIn := preload("res://scripts/ui/backdrop_options/van_stand_in.gd")

const FACADE_Z := -4.0
const SHOP_W := 15.0
const SHOP_H := 5.6
const SHOP_X := 4.0
const DOOR_X := 3.6
const DOOR_W := 4.4
const DOOR_H := 3.5
const VAN_AT := Vector3(-0.6, 0.0, 1.8)
const MANHOLE_AT := Vector3(5.0, 0.0, 5.0)
const CAM_POS := Vector3(-0.8, 2.5, 13.0)
const CAM_LOOK := Vector3(1.6, 3.4, -2.0)
const FOV := 50.0

const BLOCK := Color(0.42, 0.42, 0.45)
const BLOCK_DK := Color(0.33, 0.33, 0.37)
const TRIM := Color(0.17, 0.17, 0.2)
const AMBER := Color(1.0, 0.62, 0.15)

var mood := "night"
var use_real_van := true
var camera: Camera3D
var map: HexMap
var _t := 0.0


func setup(opts: Dictionary) -> void:
	mood = str(opts.get("mood", "night"))
	use_real_van = str(opts.get("van", "real")) != "stand-in"


func _ready() -> void:
	map = HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 18):
		var w := Hex.to_world(c)
		if w.z > FACADE_Z - 0.3 and w.z < 22.0 and absf(w.x - 2.0) < 22.0:
			map.set_cell(c, 0).tag = "room:0"
	var terrain := HexMapView.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self)
	_tune_light()
	_build_shop()
	_build_sign()
	_build_lot()
	_build_crew()
	_build_skyline()
	if mood == "rain":
		_build_rain()
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.2
	camera.far = 200.0
	add_child(camera)
	camera.current = true
	_place_camera(0.0)


func _process(delta: float) -> void:
	_t += delta
	_place_camera(_t)


func _place_camera(t: float) -> void:
	camera.position = CAM_POS + Vector3(sin(t * 0.1) * 0.8, sin(t * 0.14) * 0.15, 0)
	camera.look_at(CAM_LOOK, Vector3.UP)


func _tune_light() -> void:
	var we := get_node_or_null("LookEnvironment") as WorldEnvironment
	if we != null:
		var env := we.environment
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.03, 0.04, 0.09)
		env.ambient_light_color = Color(0.4, 0.45, 0.7)
		env.ambient_light_energy = 0.35
		env.fog_enabled = true
		env.fog_light_color = Color(0.05, 0.06, 0.12)
		env.fog_density = 0.005
	var key := get_node_or_null("KeyLight") as DirectionalLight3D
	if key != null:
		# moonlight
		key.light_color = Color(0.6, 0.7, 1.0)
		key.light_energy = 0.28
		key.rotation_degrees = Vector3(-40, 40, 0)
	var fill := get_node_or_null("FillLight") as DirectionalLight3D
	if fill != null:
		fill.light_energy = 0.1


## The cinder-block unit: facade with the roll-up door half open, a shop window, the lit interior.
func _build_shop() -> void:
	var s := LowPoly.Soup.new(71, 0.08)
	var x0 := SHOP_X - SHOP_W * 0.5
	var x1 := SHOP_X + SHOP_W * 0.5
	var win_x := 8.6
	var win_w := 3.0
	var win_y0 := 1.0
	var win_y1 := 2.9
	var bh := 0.4
	var bw := 0.8
	var rows := int(SHOP_H / bh)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for r in rows:
		var y := (float(r) + 0.5) * bh
		var x := x0 - (0.0 if r % 2 == 0 else bw * 0.5)
		while x < x1:
			var cx := x + bw * 0.5
			x += bw
			if cx < x0 or cx > x1:
				continue
			if absf(cx - DOOR_X) < DOOR_W * 0.5 + 0.1 and y < DOOR_H:
				continue
			if absf(cx - win_x) < win_w * 0.5 + 0.1 and y > win_y0 and y < win_y1:
				continue
			Kit.box(s, Vector3(bw - 0.04, bh - 0.04, 0.4), Vector3(cx, y, FACADE_Z - 0.2), BLOCK if rng.randf() < 0.7 else BLOCK_DK)
	# side walls and the roof slab
	Kit.box(s, Vector3(0.4, SHOP_H, 7.0), Vector3(x0 - 0.2, SHOP_H * 0.5, FACADE_Z - 3.5), BLOCK_DK)
	Kit.box(s, Vector3(0.4, SHOP_H, 7.0), Vector3(x1 + 0.2, SHOP_H * 0.5, FACADE_Z - 3.5), BLOCK_DK)
	Kit.box(s, Vector3(SHOP_W + 1.0, 0.4, 7.6), Vector3(SHOP_X, SHOP_H + 0.2, FACADE_Z - 3.5), TRIM)
	Kit.box(s, Vector3(SHOP_W + 0.6, 0.25, 0.5), Vector3(SHOP_X, SHOP_H - 0.1, FACADE_Z + 0.05), TRIM)
	# interior: back wall, floor, shelves of supplies, a workbench
	Kit.box(s, Vector3(SHOP_W, SHOP_H, 0.3), Vector3(SHOP_X, SHOP_H * 0.5, FACADE_Z - 6.5), Color(0.5, 0.4, 0.3))
	Kit.box(s, Vector3(SHOP_W, 0.1, 6.5), Vector3(SHOP_X, 0.02, FACADE_Z - 3.25), Color(0.25, 0.22, 0.2))
	var supply: Array[Color] = [Color(0.85, 0.25, 0.2), Color(0.3, 0.6, 0.9), Color(0.95, 0.8, 0.3), Color(0.4, 0.8, 0.45), Color(0.8, 0.5, 0.9), Color(0.95, 0.95, 0.9)]
	for shelf in 3:
		var sy := 0.8 + float(shelf) * 0.85
		Kit.box(s, Vector3(5.0, 0.08, 0.6), Vector3(DOOR_X, sy, FACADE_Z - 6.0), Color(0.5, 0.35, 0.2))
		for k in 9:
			Kit.box(s, Vector3(0.36, 0.3 + 0.12 * float((k + shelf) % 3), 0.3), Vector3(DOOR_X - 2.1 + float(k) * 0.52, sy + 0.2, FACADE_Z - 6.0), supply[(k + shelf * 2) % supply.size()])
	Kit.box(s, Vector3(2.6, 0.9, 1.0), Vector3(win_x, 0.45, FACADE_Z - 2.5), Color(0.4, 0.28, 0.17))
	# the roll-up door, half open: slats bunched at the top of the opening
	for i in 4:
		Kit.box(s, Vector3(DOOR_W + 0.2, 0.22, 0.12), Vector3(DOOR_X, DOOR_H - 0.12 - float(i) * 0.22, FACADE_Z + 0.06), Color(0.6, 0.62, 0.66) if i % 2 == 0 else Color(0.52, 0.54, 0.58))
	Kit.box(s, Vector3(DOOR_W + 0.5, 0.35, 0.4), Vector3(DOOR_X, DOOR_H + 0.15, FACADE_Z + 0.1), TRIM)
	# hazard stripes on the door frame
	for i in 9:
		var yy := 0.2 + float(i) * 0.4
		for side: float in [-1.0, 1.0]:
			Kit.box(s, Vector3(0.18, 0.2, 0.06), Vector3(DOOR_X + side * (DOOR_W * 0.5 + 0.1), yy, FACADE_Z + 0.03), Color(0.98, 0.8, 0.12) if i % 2 == 0 else PropModels.OBSIDIAN, Vector3(0, 0, 30))
	# window frame and glass
	Kit.box(s, Vector3(win_w + 0.2, 0.15, 0.3), Vector3(win_x, win_y0, FACADE_Z + 0.02), TRIM)
	Kit.box(s, Vector3(win_w + 0.2, 0.15, 0.3), Vector3(win_x, win_y1, FACADE_Z + 0.02), TRIM)
	Kit.box(s, Vector3(win_w, win_y1 - win_y0, 0.04), Vector3(win_x, (win_y0 + win_y1) * 0.5, FACADE_Z - 0.05), Kit.glow(Color(0.22, 0.16, 0.08)))
	# an awning-ish strip and the downspout
	Kit.rod(s, Vector3(x1 - 0.3, 0.0, FACADE_Z + 0.2), Vector3(x1 - 0.3, SHOP_H, FACADE_Z + 0.2), 0.08, 0.08, 6, TRIM)
	add_child(Kit.mesh(s, 1.8, "Shop"))
	Kit.omni(self, Vector3(DOOR_X, 3.0, FACADE_Z - 2.8), Color(1.0, 0.72, 0.42), 5.0, 9.0)
	Kit.omni(self, Vector3(DOOR_X, 1.4, FACADE_Z + 1.2), Color(1.0, 0.7, 0.4), 2.0, 6.0)
	Kit.omni(self, Vector3(win_x, 2.0, FACADE_Z - 1.0), Color(1.0, 0.75, 0.45), 2.0, 4.0)
	# signs in the window
	var sign_node := Kit.paper_sign("WE FIX YOUR HEXES\nOR IT'S FREE!", Vector2(1.8, 0.8), 38)
	Kit.put(self, sign_node, Vector3(win_x - 0.6, 1.65, FACADE_Z + 0.02))
	var open_sign := Kit.neon("OPEN", Color(1.0, 0.2, 0.25), 0.055, [], true)
	Kit.put(self, open_sign, Vector3(win_x + 1.05, 2.35, FACADE_Z + 0.03))
	var hours := Kit.paper_sign("24/7\nEMERGENCY\nDISPATCH", Vector2(0.9, 0.9), 30, Color(1.0, 0.92, 0.55))
	Kit.put(self, hours, Vector3(DOOR_X - DOOR_W * 0.5 - 0.9, 2.2, FACADE_Z + 0.03))


## The rooftop sign: a steel frame, CAST in amber neon, a painted board underneath.
func _build_sign() -> void:
	var root := Node3D.new()
	root.name = "RoofSign"
	add_child(root)
	root.position = Vector3(SHOP_X + 1.0, SHOP_H + 0.4, FACADE_Z - 1.0)
	var s := LowPoly.Soup.new(72, 0.06)
	for sx: float in [-3.0, 3.0]:
		Kit.rod(s, Vector3(sx, 0, 0), Vector3(sx, 3.6, 0), 0.08, 0.08, 6, TRIM)
		Kit.rod(s, Vector3(sx, 0, -0.9), Vector3(sx, 2.4, 0), 0.06, 0.06, 5, TRIM)
	Kit.box(s, Vector3(7.0, 1.0, 0.12), Vector3(0, 0.75, 0.05), Color(0.92, 0.88, 0.76))
	Kit.box(s, Vector3(7.0, 0.12, 0.16), Vector3(0, 0.22, 0.05), Color(0.78, 0.2, 0.15))
	Kit.box(s, Vector3(7.0, 0.12, 0.16), Vector3(0, 1.28, 0.05), Color(0.78, 0.2, 0.15))
	root.add_child(Kit.mesh(s, 1.6, "Frame"))
	var neon := Kit.neon("CAST", AMBER, 0.22, [], true)
	neon.position = Vector3(0, 2.65, 0.05)
	root.add_child(neon)
	var board := Kit.decal_text("LICENSED BUDGET SORCERY  ·  1-800-LOW-MANA", 46, Color(0.14, 0.12, 0.16), 0.0055)
	board.position = Vector3(0, 0.78, 0.13)
	root.add_child(board)
	# two little floodlights washing the board
	for sx: float in [-2.2, 2.2]:
		var sp := SpotLight3D.new()
		sp.position = Vector3(sx, -0.4, 1.6)
		root.add_child(sp)
		sp.look_at(root.global_position + Vector3(sx * 0.6, 0.8, 0.0), Vector3.UP)
		sp.light_color = Color(1.0, 0.85, 0.6)
		sp.light_energy = 3.0
		sp.spot_range = 4.0
		sp.spot_angle = 40.0
	Kit.omni(root, Vector3(0, 2.6, 1.2), AMBER, 2.5, 7.0)


## The lot: the van in its pentagram bay, a street lamp, the leaking manhole, cones and a dumpster.
func _build_lot() -> void:
	var circle := DecorModels.build("summoning_circle", {"radius": 3.0})
	Kit.put(self, circle, VAN_AT + Vector3(0, 0.02, 0))
	var bay := Kit.decal_text("RESERVED: VAN", 70, Color(0.95, 0.92, 0.85), 0.006)
	bay.rotation_degrees = Vector3(-90, 0, 0)
	bay.position = VAN_AT + Vector3(0, 0.05, 3.5)
	add_child(bay)
	var van := VanStandIn.make({"door_open": false, "headlights": false, "real": use_real_van})
	Kit.put(self, van, VAN_AT, 35.0)
	# street lamp
	var s := LowPoly.Soup.new(73, 0.05)
	var lamp_at := Vector3(-6.5, 0, 4.5)
	Kit.cyl(s, 0.14, 0.1, 6.0, 6, lamp_at + Vector3(0, 3.0, 0), TRIM)
	Kit.rod(s, lamp_at + Vector3(0, 5.9, 0), lamp_at + Vector3(1.4, 6.1, 0), 0.07, 0.07, 5, TRIM)
	Kit.box(s, Vector3(0.7, 0.18, 0.4), lamp_at + Vector3(1.5, 6.0, 0), TRIM)
	Kit.box(s, Vector3(0.55, 0.06, 0.3), lamp_at + Vector3(1.5, 5.9, 0), Kit.glow(Color(1.0, 0.65, 0.3)))
	# dumpster
	Kit.box(s, Vector3(2.4, 1.3, 1.4), Vector3(13.4, 0.65, FACADE_Z + 1.0), Color(0.2, 0.38, 0.28))
	Kit.box(s, Vector3(2.5, 0.12, 1.5), Vector3(13.4, 1.36, FACADE_Z + 1.0), Color(0.15, 0.3, 0.22), Vector3(-8, 0, 0))
	# traffic cones around the manhole
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		var p := MANHOLE_AT + Vector3(cos(a) * 1.9, 0, sin(a) * 1.6)
		Kit.cyl(s, 0.24, 0.03, 0.7, 6, p + Vector3(0, 0.35, 0), Color(1.0, 0.45, 0.1))
		Kit.box(s, Vector3(0.5, 0.06, 0.5), p + Vector3(0, 0.03, 0), Color(0.15, 0.15, 0.15))
		Kit.cyl(s, 0.17, 0.12, 0.1, 6, p + Vector3(0, 0.4, 0), Color(0.95, 0.95, 0.9))
	# the manhole cover, knocked aside
	Kit.cyl(s, 0.8, 0.8, 0.08, 10, MANHOLE_AT + Vector3(-1.3, 0.05, 0.5), Color(0.28, 0.28, 0.3), Vector3(0, 0, 6))
	add_child(Kit.mesh(s, 1.8, "Lot"))
	var sodium := SpotLight3D.new()
	sodium.position = lamp_at + Vector3(1.5, 5.8, 0)
	sodium.rotation_degrees = Vector3(-90, 0, 0)
	sodium.light_color = Color(1.0, 0.62, 0.3)
	sodium.light_energy = 7.0
	sodium.spot_range = 12.0
	sodium.spot_angle = 42.0
	sodium.shadow_enabled = true
	add_child(sodium)
	var shaft := Kit.light_shaft(5.6, 0.25, 2.6, Color(1.0, 0.7, 0.4), 0.12)
	shaft.position = lamp_at + Vector3(1.5, 3.0, 0)
	add_child(shaft)
	# the leaking manhole: a small gate under the street
	var gate := HellgateModel.make(false)
	add_child(gate)
	gate.set_active(true)
	gate.position = MANHOLE_AT + Vector3(0, -0.2, 0)
	gate.scale = Vector3.ONE * 0.75
	var red := Kit.omni(self, MANHOLE_AT + Vector3(0, 1.2, 0), Color(1.0, 0.22, 0.08), 3.5, 6.0)
	var f := Kit.Flicker.new()
	f.light = red
	f.base = 3.5
	f.speed = 2.0
	add_child(f)
	Kit.put(self, DecorModels.build("hazard_tape"), MANHOLE_AT + Vector3(0, 0, 2.0), 0.0)


func _build_crew() -> void:
	var to_cam := (CAM_POS - CAM_LOOK)
	to_cam.y = 0.0
	to_cam = to_cam.normalized()
	var face := rad_to_deg(atan2(-to_cam.x, -to_cam.z))
	Kit.put(self, RebarModel.new(), Vector3(DOOR_X + 3.0, 0, FACADE_Z + 1.4), face - 25.0)
	Kit.put(self, GasketModel.new(), Vector3(DOOR_X + 0.6, 0, FACADE_Z + 2.6), face + 15.0)
	# Wick is eyeing the manhole
	var wick := WickModel.new()
	Kit.put(self, wick, MANHOLE_AT + Vector3(2.4, 0, -1.3), 0.0)
	wick.rotation.y = atan2(-(MANHOLE_AT.x - wick.position.x), -(MANHOLE_AT.z - wick.position.z))


## Rooftops on the horizon and a red glow behind them: the city has problems.
func _build_skyline() -> void:
	var s := LowPoly.Soup.new(74, 0.05)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var x := -40.0
	while x < 50.0:
		var w := rng.randf_range(3.0, 7.0)
		var h := rng.randf_range(6.0, 18.0)
		Kit.box(s, Vector3(w, h, 4.0), Vector3(x + w * 0.5, h * 0.5 - 1.0, -38.0 - rng.randf() * 6.0), Color(0.06, 0.065, 0.1))
		for k in int(h / 2.5):
			if rng.randf() < 0.3:
				Kit.box(s, Vector3(0.6, 0.5, 0.05), Vector3(x + rng.randf_range(0.8, w - 0.8), 1.0 + float(k) * 2.4, -35.9), Kit.glow(Color(1.0, 0.8, 0.45) if rng.randf() < 0.7 else Color(0.5, 0.8, 1.0)))
		x += w + rng.randf_range(0.2, 1.5)
	# the red glow on the horizon and a moon
	Kit.box(s, Vector3(40.0, 10.0, 0.2), Vector3(22.0, 3.0, -47.0), Kit.glow(Color(0.4, 0.06, 0.03)))
	Kit.cyl(s, 2.2, 2.2, 0.1, 16, Vector3(26.0, 24.0, -60.0), Kit.glow(Color(0.85, 0.88, 1.0)), Vector3(90, 0, 0))
	# a banded night sky: brighter toward the horizon
	for band in 6:
		var k := float(band) / 5.0
		Kit.box(s, Vector3(200.0, 6.0, 0.2), Vector3(0, 2.0 + float(band) * 6.0, -75.0), Kit.glow(Color(0.2, 0.14, 0.3).lerp(Color(0.03, 0.035, 0.08), k)))
	add_child(Kit.mesh(s, 0.0, "Skyline"))


func _build_rain() -> void:
	var p := CPUParticles3D.new()
	p.amount = 900
	p.lifetime = 1.2
	p.preprocess = 1.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(18, 0.5, 14)
	p.position = Vector3(3, 12, 4)
	p.direction = Vector3(0.08, -1, 0)
	p.spread = 2.0
	p.gravity = Vector3(0, -6, 0)
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 15.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.025, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.7, 0.8, 1.0, 0.35)
	qm.material = m
	p.mesh = qm
	add_child(p)
