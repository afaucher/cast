class_name ElevatorLobbyProps
extends RefCounted
## LOOK-DEV ONLY (docs/design/elevator-options.md, placement B): the dressing of a dedicated elevator lobby, in the
## two elevator looks. Faceted low-poly like the rest of the props (PropModels helpers, MonsterMaterial).
## Every model's origin is its base centre on the floor; wall pieces have their back on z = 0 and face +Z.
##
##   var n := ElevatorLobbyProps.build("bench", "fancy")
##
## Kinds: bench, palm, directory (a building directory board, fancy), service_sign, extinguisher, keep_clear (a
## striped floor box), pallet (shrink-wrapped boxes on a pallet), runner (a carpet runner; params length).

const SEED := 6113


static func build(kind: String, look: String, params: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = kind.capitalize().replace(" ", "")
	PropModels._seed = SEED + kind.hash() % 997
	var s := LowPoly.Soup.new(SEED, 0.05)
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.9
	match kind:
		"bench": _bench(s, look)
		"palm": _palm(s, look)
		"directory": _directory(s, root, font)
		"service_sign": _service_sign(s, root, font)
		"extinguisher": _extinguisher(s)
		"keep_clear": _keep_clear(s, root, font, float(params.get("width", 3.4)), float(params.get("depth", 1.6)))
		"pallet": _pallet(s)
		"runner": _runner(s, float(params.get("length", 4.0)))
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = s.to_mesh()
	mi.material_override = PropModels.material()
	root.add_child(mi)
	return root


static func _b(s: LowPoly.Soup, size: Vector3, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
	PropModels.box(s, size, pos, col, rot)


static func _label(root: Node3D, font: Font, text: String, size: int, pixel: float, col: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, outline: int = 5) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = pixel
	l.shaded = false
	l.double_sided = false
	l.modulate = col
	l.outline_size = outline
	l.outline_modulate = Color(0.04, 0.03, 0.05)
	l.position = pos
	l.rotation_degrees = rot
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	root.add_child(l)
	return l


static func _bench(s: LowPoly.Soup, look: String) -> void:
	if look == "fancy":
		for i in 4:
			_b(s, Vector3(1.5, 0.05, 0.1), Vector3(0, 0.46, -0.17 + i * 0.115), ElevatorModel.WOOD)
		for i in 3:
			_b(s, Vector3(1.5, 0.08, 0.05), Vector3(0, 0.62 + i * 0.13, -0.24), ElevatorModel.WOOD, Vector3(-8, 0, 0))
		for sx in [-0.68, 0.68]:
			_b(s, Vector3(0.06, 0.45, 0.42), Vector3(sx, 0.22, 0), ElevatorModel.BRASS)
			_b(s, Vector3(0.06, 0.5, 0.06), Vector3(sx, 0.7, -0.24), ElevatorModel.BRASS)
			_b(s, Vector3(0.08, 0.05, 0.42), Vector3(sx, 0.6, 0), ElevatorModel.BRASS_DK)
	else:
		_b(s, Vector3(1.4, 0.06, 0.4), Vector3(0, 0.45, 0), ElevatorModel.STEEL)
		_b(s, Vector3(1.4, 0.3, 0.05), Vector3(0, 0.75, -0.2), ElevatorModel.STEEL, Vector3(-6, 0, 0))
		for sx in [-0.62, 0.62]:
			_b(s, Vector3(0.05, 0.44, 0.36), Vector3(sx, 0.22, 0), ElevatorModel.STEEL_DK)
		# a hard hat and a lunch box left on it
		PropModels.ball(s, Vector3(0.16, 0.1, 0.18), Vector3(-0.35, 0.53, 0.02), ElevatorModel.HAZ_Y, 1, 0.05)
		_b(s, Vector3(0.36, 0.02, 0.06), Vector3(-0.35, 0.49, 0.18), ElevatorModel.HAZ_Y)
		_b(s, Vector3(0.3, 0.18, 0.18), Vector3(0.35, 0.57, 0.0), Color(0.2, 0.35, 0.7))


static func _palm(s: LowPoly.Soup, look: String) -> void:
	var pot := ElevatorModel.BRASS if look == "fancy" else Color(0.55, 0.36, 0.22)
	PropModels.cyl(s, 0.2, 0.28, 0.55, 8, Vector3(0, 0.275, 0), pot)
	PropModels.cyl(s, 0.29, 0.29, 0.05, 8, Vector3(0, 0.55, 0), pot.darkened(0.25))
	PropModels.cyl(s, 0.24, 0.24, 0.03, 8, Vector3(0, 0.56, 0), Color(0.22, 0.14, 0.08))
	var top := Vector3(0.05, 1.55, 0.0)
	PropModels.rod(s, Vector3(0, 0.55, 0), top, 0.06, 0.04, 6, Color(0.42, 0.3, 0.18))
	var leaf := Color(0.18, 0.48, 0.22) if look == "fancy" else Color(0.48, 0.42, 0.2)   # the service one is dying
	for i in 7:
		var a := TAU * i / 7.0 + 0.3
		var d := Vector3(cos(a), 0, sin(a))
		var droop := 0.25 if look == "fancy" else 0.55
		var mid := top + d * 0.42 + Vector3(0, 0.1 - droop * 0.4, 0)
		var tip := top + d * 0.8 + Vector3(0, -droop, 0)
		PropModels.rod(s, top, mid, 0.07, 0.11, 4, leaf)
		PropModels.rod(s, mid, tip, 0.11, 0.02, 4, leaf.darkened(0.1))


static func _directory(s: LowPoly.Soup, root: Node3D, font: Font) -> void:
	_b(s, Vector3(1.2, 1.25, 0.06), Vector3(0, 1.55, 0.03), ElevatorModel.BRASS_DK)
	_b(s, Vector3(1.08, 1.13, 0.02), Vector3(0, 1.55, 0.065), Color(0.07, 0.06, 0.08))
	_b(s, Vector3(1.24, 0.08, 0.1), Vector3(0, 2.2, 0.05), ElevatorModel.BRASS)
	_label(root, font, "DIRECTORY", 44, 0.0042, ElevatorModel.BRASS, Vector3(0, 2.02, 0.08))
	_label(root, font, "SPA . . . . . . . . . LOW\nWINE CELLAR . . . . MED\nCINEMA . . . . . . . . MED\nPANIC ROOM . . . . . ???", 26, 0.0032,
			Color(0.95, 0.92, 0.84), Vector3(0, 1.48, 0.08), Vector3.ZERO, 3)


static func _service_sign(s: LowPoly.Soup, root: Node3D, font: Font) -> void:
	_b(s, Vector3(1.6, 0.62, 0.03), Vector3(0, 1.75, 0.015), ElevatorModel.HAZ_Y)
	_b(s, Vector3(1.5, 0.08, 0.01), Vector3(0, 1.96, 0.035), ElevatorModel.HAZ_K)
	_label(root, font, "SERVICE ELEVATOR", 40, 0.0038, ElevatorModel.HAZ_K, Vector3(0, 1.8, 0.042), Vector3.ZERO, 0)
	_label(root, font, "AUTHORIZED CREW ONLY\nNO PASSENGERS", 26, 0.0036, ElevatorModel.HAZ_K, Vector3(0, 1.6, 0.042), Vector3.ZERO, 0)


static func _extinguisher(s: LowPoly.Soup) -> void:
	_b(s, Vector3(0.22, 0.08, 0.06), Vector3(0, 1.05, 0.03), ElevatorModel.STEEL_DK)
	PropModels.cyl(s, 0.1, 0.1, 0.55, 8, Vector3(0, 0.75, 0.13), Color(0.82, 0.1, 0.08))
	PropModels.cyl(s, 0.05, 0.06, 0.08, 6, Vector3(0, 1.07, 0.13), ElevatorModel.HAZ_K)
	PropModels.rod(s, Vector3(0.02, 1.08, 0.13), Vector3(0.12, 0.85, 0.22), 0.015, 0.015, 4, ElevatorModel.HAZ_K)


static func _keep_clear(s: LowPoly.Soup, root: Node3D, font: Font, w: float, d: float) -> void:
	# a painted floor box: striped border, KEEP CLEAR stencilled inside
	for i in 4:
		var yaw := i * 90.0
		var along := w if i % 2 == 0 else d
		var off := d * 0.5 - 0.08 if i % 2 == 0 else w * 0.5 - 0.08
		var bs := Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0))
		ElevatorModel._stripes(s, LowPoly.at(bs * Vector3(0, 0.012, off), Vector3(-90, yaw, 0)), along, 0.16, int(along / 0.25))
	var l := _label(root, font, "KEEP CLEAR", 64, 0.008, ElevatorModel.HAZ_Y, Vector3(0, 0.02, 0), Vector3(-90, 0, 0), 0)
	l.modulate = Color(0.95, 0.75, 0.2, 0.85)
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED


static func _pallet(s: LowPoly.Soup) -> void:
	var wood := Color(0.62, 0.48, 0.3)
	for z in [-0.45, 0.0, 0.45]:
		_b(s, Vector3(1.2, 0.1, 0.12), Vector3(0, 0.05, z), wood.darkened(0.15))
	for i in 7:
		_b(s, Vector3(0.14, 0.03, 1.0), Vector3(-0.52 + i * 0.173, 0.115, 0), wood)
	var card := Color(0.72, 0.55, 0.34)
	_b(s, Vector3(0.55, 0.45, 0.45), Vector3(-0.28, 0.355, -0.22), card)
	_b(s, Vector3(0.55, 0.45, 0.45), Vector3(0.28, 0.355, -0.22), card.darkened(0.08))
	_b(s, Vector3(0.55, 0.45, 0.45), Vector3(-0.28, 0.355, 0.24), card.lightened(0.05))
	_b(s, Vector3(0.5, 0.4, 0.42), Vector3(-0.1, 0.78, -0.05), card, Vector3(0, 12, 0))
	for p: Vector3 in [Vector3(-0.28, 0.58, -0.22), Vector3(0.28, 0.58, -0.22), Vector3(-0.28, 0.58, 0.24)]:
		_b(s, Vector3(0.56, 0.01, 0.08), p + Vector3(0, 0.0, 0), Color(0.85, 0.75, 0.5))


static func _runner(s: LowPoly.Soup, length: float) -> void:
	_b(s, Vector3(1.6, 0.02, length), Vector3(0, 0.01, 0), PropModels.GOLD_DK)
	_b(s, Vector3(1.44, 0.024, length - 0.16), Vector3(0, 0.013, 0), ElevatorModel.CARPET)
	for i in int(length / 0.8):
		_b(s, Vector3(0.18, 0.026, 0.18), Vector3(0, 0.014, -length * 0.5 + 0.4 + i * 0.8), PropModels.GOLD_DK, Vector3(0, 45, 0))
