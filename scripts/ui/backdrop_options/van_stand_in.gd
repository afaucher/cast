extends RefCounted
## A rough STAND-IN for the crew's work van, only for the backdrop prototypes (the real VanModel is being
## built separately in scripts/art/lowpoly/props/van_model.gd). Beat-up white panel van: amber stripe, rust,
## roof rack with a ladder, pipes and a hose coil, the sliding side door open (+Z side) with a lit shelf
## inside. Nose at +X, origin at the ground centre.
##
##   var van := VanStandIn.build({"door_open": true, "headlights": false})

const Kit := preload("res://scripts/ui/backdrops/backdrop_kit.gd")

const BODY := Color(0.80, 0.78, 0.71)
const BODY_DK := Color(0.64, 0.62, 0.56)
const STRIPE := Color(0.93, 0.6, 0.16)
const RUST := Color(0.47, 0.25, 0.13)
const TRIM := Color(0.16, 0.16, 0.19)
const GLASS := Color(0.16, 0.22, 0.30)
const TYRE := Color(0.09, 0.09, 0.1)
const COPPER := Color(0.78, 0.45, 0.22)
const HOSE := Color(0.22, 0.52, 0.26)
const INSIDE := Color(0.07, 0.06, 0.06)


const VAN_MODEL_PATH := "res://scripts/art/lowpoly/props/van_model.gd"


## The van for a backdrop, in the stand-in's frame (nose +X, open side door facing +Z). Uses the real VanModel
## (being built by another agent: nose +Z, sliding door on -X) when its script loads and opts "real" is not
## false; otherwise the stand-in below. opts: door_open (bool), headlights (bool), real (bool, default true).
static func make(opts: Dictionary = {}) -> Node3D:
	if bool(opts.get("real", true)) and ResourceLoader.exists(VAN_MODEL_PATH):
		var script := load(VAN_MODEL_PATH) as GDScript
		if script != null and script.can_instantiate():
			var inst: Variant = script.new()
			if inst is Node3D:
				var van := inst as Node3D
				var holder := Node3D.new()
				holder.name = "Van"
				holder.add_child(van)
				van.rotation.y = deg_to_rad(90.0)   # its -X door side -> +Z, its +Z nose -> +X
				if van.has_method("set_door_open"):
					van.call("set_door_open", 1.0 if bool(opts.get("door_open", true)) else 0.0)
				if van.has_method("set_lights"):
					van.call("set_lights", 1.0 if bool(opts.get("headlights", false)) else 0.0)
				return holder
	return build(opts)


static func build(opts: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "VanStandIn"
	var s := LowPoly.Soup.new(4242, 0.07)
	# chassis, cargo box, cab
	Kit.box(s, Vector3(4.5, 0.32, 1.86), Vector3(0, 0.56, 0), TRIM)
	Kit.box(s, Vector3(3.15, 1.62, 2.0), Vector3(-0.72, 1.46, 0), BODY)
	Kit.box(s, Vector3(1.36, 1.0, 2.0), Vector3(1.43, 1.15, 0), BODY)
	s.merge(LowPoly.frustum(Vector2(1.36, 2.0), Vector2(0.8, 1.9), 0.62, BODY, Kit.n(), 0.0, 1, Vector2(-0.28, 0), 0.07), LowPoly.at(Vector3(1.43, 1.96, 0)))
	Kit.box(s, Vector3(0.42, 0.56, 1.92), Vector3(2.28, 0.94, 0), BODY_DK)
	Kit.box(s, Vector3(0.14, 0.22, 2.04), Vector3(2.5, 0.62, 0), TRIM)
	Kit.box(s, Vector3(0.12, 0.2, 2.04), Vector3(-2.33, 0.68, 0), TRIM)
	# glass: windshield (sloped) and the cab side windows
	Kit.box(s, Vector3(0.05, 0.62, 1.74), Vector3(1.85, 1.96, 0), GLASS, Vector3(0, 0, 42))
	for side: float in [-1.0, 1.0]:
		Kit.box(s, Vector3(0.72, 0.46, 0.05), Vector3(1.32, 1.92, side * 0.985), GLASS)
		# mirror
		Kit.box(s, Vector3(0.08, 0.26, 0.16), Vector3(1.92, 1.72, side * 1.14), TRIM)
	# amber stripe and rust
	Kit.box(s, Vector3(3.17, 0.17, 2.03), Vector3(-0.72, 0.98, 0), STRIPE)
	Kit.box(s, Vector3(1.38, 0.17, 2.03), Vector3(1.43, 0.98, 0), STRIPE)
	Kit.box(s, Vector3(0.34, 0.2, 2.02), Vector3(-2.02, 0.78, 0), RUST)
	Kit.box(s, Vector3(0.22, 0.14, 2.02), Vector3(1.9, 0.78, 0), RUST)
	Kit.box(s, Vector3(0.5, 0.12, 2.02), Vector3(-1.2, 2.18, 0), RUST)
	# lights
	for side: float in [-1.0, 1.0]:
		Kit.box(s, Vector3(0.06, 0.18, 0.34), Vector3(2.5, 1.0, side * 0.7), Kit.glow(Color(1.0, 0.92, 0.7)) if bool(opts.get("headlights", false)) else Color(0.85, 0.85, 0.78))
		Kit.box(s, Vector3(0.06, 0.3, 0.16), Vector3(-2.31, 1.22, side * 0.86), Kit.glow(Color(0.9, 0.12, 0.08)))
	# wheels
	for wx: float in [-1.45, 1.45]:
		for side: float in [-1.0, 1.0]:
			Kit.cyl(s, 0.4, 0.4, 0.3, 10, Vector3(wx, 0.4, side * 0.86), TYRE, Vector3(90, 0, 0))
			Kit.cyl(s, 0.2, 0.2, 0.32, 6, Vector3(wx, 0.4, side * 0.87), Color(0.6, 0.6, 0.62), Vector3(90, 0, 0))
	# roof rack, ladder, pipes, hose
	for side: float in [-1.0, 1.0]:
		Kit.rod(s, Vector3(-2.2, 2.42, side * 0.82), Vector3(0.9, 2.42, side * 0.82), 0.035, 0.035, 5, TRIM)
		for x: float in [-2.0, -0.7, 0.6]:
			Kit.rod(s, Vector3(x, 2.27, side * 0.82), Vector3(x, 2.42, side * 0.82), 0.03, 0.03, 4, TRIM)
	for x: float in [-2.0, -0.7, 0.6]:
		Kit.rod(s, Vector3(x, 2.43, -0.84), Vector3(x, 2.43, 0.84), 0.03, 0.03, 4, TRIM)
	for side: float in [0.05, 0.62]:
		Kit.rod(s, Vector3(-2.45, 2.5, side), Vector3(1.05, 2.5, side), 0.04, 0.04, 5, Color(0.72, 0.74, 0.78))
	var rx := -2.3
	while rx < 1.0:
		Kit.rod(s, Vector3(rx, 2.5, 0.05), Vector3(rx, 2.5, 0.62), 0.025, 0.025, 4, Color(0.72, 0.74, 0.78))
		rx += 0.36
	for i in 3:
		var z := -0.62 + float(i) * 0.13
		Kit.rod(s, Vector3(-2.6, 2.52 + float(i % 2) * 0.05, z), Vector3(1.25, 2.52 + float(i % 2) * 0.05, z), 0.06, 0.06, 6, COPPER if i != 1 else Color(0.62, 0.64, 0.68))
	var segs := 12
	for i in segs:
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		for ring: float in [0.3, 0.38]:
			Kit.rod(s, Vector3(-1.55 + cos(a0) * ring, 2.6, -0.42 + sin(a0) * ring * 0.9), Vector3(-1.55 + cos(a1) * ring, 2.6, -0.42 + sin(a1) * ring * 0.9), 0.045, 0.045, 4, HOSE)
	# the sliding side door, open: the dark opening, the shelf inside, the door slid back over the rear
	if bool(opts.get("door_open", true)):
		Kit.box(s, Vector3(1.22, 1.42, 0.04), Vector3(0.16, 1.36, 1.0), INSIDE)
		for sy: float in [0.98, 1.5]:
			Kit.box(s, Vector3(1.14, 0.04, 0.12), Vector3(0.16, sy, 0.98), Color(0.45, 0.32, 0.2))
		var jars: Array[Color] = [Color(0.85, 0.25, 0.2), Color(0.3, 0.6, 0.9), Color(0.95, 0.8, 0.3), Color(0.4, 0.8, 0.45), Color(0.8, 0.5, 0.9)]
		for j in 5:
			Kit.cyl(s, 0.07, 0.07, 0.2 + 0.06 * float(j % 2), 6, Vector3(-0.3 + float(j) * 0.22, 1.1 + 0.03 * float(j % 2), 1.0), jars[j])
			Kit.box(s, Vector3(0.16, 0.16, 0.12), Vector3(-0.28 + float(j) * 0.23, 1.6, 0.99), jars[(j + 2) % 5].darkened(0.2))
		Kit.box(s, Vector3(1.28, 1.48, 0.07), Vector3(-1.2, 1.4, 1.07), BODY)
		Kit.box(s, Vector3(1.3, 0.17, 0.08), Vector3(-1.2, 0.98, 1.075), STRIPE)
		Kit.box(s, Vector3(0.18, 0.05, 0.05), Vector3(-0.68, 1.35, 1.12), TRIM)
	var body := Kit.mesh(s, 2.4)
	root.add_child(body)
	if bool(opts.get("door_open", true)):
		Kit.omni(root, Vector3(0.16, 1.7, 1.3), Color(1.0, 0.78, 0.45), 1.4, 3.2)
	# lettering on the side (the slid-back door carries the logo, like a real van)
	var logo := Kit.decal_text("CAST", 112, Color(0.14, 0.13, 0.16), 0.004)
	logo.position = Vector3(-1.22, 1.66, 1.115)
	root.add_child(logo)
	var sub := Kit.decal_text("LICENSED BUDGET SORCERY", 25, Color(0.14, 0.13, 0.16), 0.004)
	sub.position = Vector3(-1.22, 1.36, 1.115)
	root.add_child(sub)
	var phone := Kit.decal_text("1-800-LOW-MANA", 30, Color(0.55, 0.12, 0.1), 0.004)
	phone.position = Vector3(1.43, 1.25, 1.03)
	root.add_child(phone)
	if bool(opts.get("headlights", false)):
		for side: float in [-1.0, 1.0]:
			var sp := SpotLight3D.new()
			sp.position = Vector3(2.6, 1.0, side * 0.7)
			sp.rotation_degrees = Vector3(-8, -90, 0)
			sp.light_color = Color(1.0, 0.93, 0.75)
			sp.light_energy = 4.0
			sp.spot_range = 14.0
			sp.spot_angle = 26.0
			root.add_child(sp)
	return root
